extends "res://prototypes/objetos_adaptador/probe_network.gd"
## Validacion independiente (Claude), entrega 14, parte N. Hereda la escena de dos procesos de
## Codex (NetSync real, actor, history_bridge, scene_network_bridge, authority_channel) sin cambiar
## su protocolo: mismas acciones, misma publicacion cada 4 ticks. Solo agrega observacion, el
## momento de cada evento y los finales de cada modo. Modos: close_host, close_client,
## close_both, lease_silent, quiet, future. Tiempos entre procesos: reloj del sistema (unix).
const CLOSE_TICK := 60
const LEASE_TICK := 45
const FUTURE_FINAL := 240
const QUIET_LAST_PUBLISH := 40
const QUIET_END_MS := 6600
const DEADLINE_MS := 7300

var offset_ms := 0.0
var close_rec: Array = []
var stop_unix := -1.0
var stop_tx_in_flight := false
var frozen := {}
var frozen_bad: Array = []
var post_close_checked := false
var applied_log: Array = []
var rejected_count := 0
var occupancy_max := 0
var future_bad := 0
var displaced: Array = []
var prev_pending_rev := -1
var prev_pending_tick := -1
var prev_consumed := 0
var pending_since := {}
var max_wait := 0
var act_prev := -1
var act_max_gap := 0
var act_updates := 0
var throttle: Array = []
var last_sample := 0
var pause_left := -1
var paused_frames := 0
var applied_in_pause := 0
var end_sent := false
var publishes := 0

func now_unix() -> float:
	return Time.get_unix_time_from_system()

func setup(client_id: int) -> void:
	offset_ms = Time.get_unix_time_from_system() * 1000.0 - Time.get_ticks_msec()
	super.setup(client_id)
	channel.closed.connect(_on_closed)
	if role == "client":
		network.object_authority_applied.connect(_on_applied)
		network.object_authority_rejected.connect(func(_r: String): rejected_count += 1)

@rpc("authority", "call_remote", "reliable")
func _go() -> void:
	if mode == "future": await get_tree().create_timer(0.5, true, false, true).timeout
	running = true; clock.paused = false

func on_authority(_checkpoint: int, _revision: int) -> void:
	pass # sin comparacion intermedia: en estos modos los inputs del host y del cliente difieren

func publish_allowed(tick: int) -> bool:
	if mode == "quiet": return tick <= QUIET_LAST_PUBLISH
	if mode == "future": return tick <= FUTURE_FINAL
	return true

func after_tick(tick: int) -> void:
	if done: return
	if role == "host":
		host_hashes[tick] = state_hash()
		sync.send_snapshot(tick, [actor], [])
		if channel.stats().bound and tick % 4 == 0 and publish_allowed(tick):
			publish(); publishes += 1
	else:
		prediction.record(tick, local_input, actor.state)
		sync.send_ticks(prediction.recent(NetSync.INPUT_REDUNDANCY), 0.0)
		observe_slots()
	var stop_at := LEASE_TICK if mode == "lease_silent" else CLOSE_TICK
	if mode in ["close_host", "close_client", "close_both", "lease_silent"] and tick == stop_at:
		var me := (mode == "close_host" and role == "host") or (mode == "close_client" and role == "client") \
			or mode == "close_both" or (mode == "lease_silent" and role == "host")
		if me:
			stop_unix = now_unix(); stop_tx_in_flight = role == "host" and not channel._tx.is_empty()
			if mode == "lease_silent": channel.stop(false)
			else: channel.stop()
	if role == "client" and not frozen.is_empty() and tick > frozen.tick:
		if adapter.world.get_tick() != frozen.native_tick or state_hash() != frozen.hash \
			or applied_log.size() != frozen.applied or adapter.ready_for_input:
			frozen_bad.append(tick)
		var check_at := 8 if mode == "lease_silent" else 30
		if tick - frozen.tick >= check_at and not post_close_checked: post_close_checks()
		if tick - frozen.tick >= check_at + 2: end_client()
	if mode == "future":
		if role == "host" and tick == FUTURE_FINAL:
			clock.paused = true; final_hash = state_hash()
			_final_reference.rpc_id(peer_id, final_hash, release_requested, release_applied)
		if role == "client":
			if tick == 100 and pause_left < 0:
				clock.paused = true; pause_left = 25
			if tick == FUTURE_FINAL: clock.paused = true

func _on_applied(t: int, r: int) -> void:
	applied_log.append({"tick": t, "revision": r, "clock": clock.tick, "paused": clock.paused})
	if t > clock.tick: future_bad += 1
	if clock.paused: applied_in_pause += 1
	if pending_since.has(r): max_wait = maxi(max_wait, clock.tick - pending_since[r])

func observe_slots() -> void:
	var occ := int(not network._pending.is_empty()) + int(not network._latest.is_empty())
	occupancy_max = maxi(occupancy_max, occ)
	var cur_rev: int = network._pending.get("revision", -1)
	var cur_tick: int = network._pending.get("tick", -1)
	var consumed := applied_log.size() + rejected_count
	if prev_pending_rev >= 0 and cur_rev != prev_pending_rev and consumed == prev_consumed and cur_tick != prev_pending_tick:
		displaced.append([clock.tick, prev_pending_rev, cur_rev])
	if cur_rev >= 0 and not pending_since.has(cur_rev): pending_since[cur_rev] = clock.tick
	prev_pending_rev = cur_rev; prev_pending_tick = cur_tick; prev_consumed = consumed

func observe_link() -> void:
	if channel == null: return
	if channel._bound:
		var a: int = channel._last_peer_activity
		if act_prev >= 0 and a != act_prev:
			act_max_gap = maxi(act_max_gap, a - act_prev); act_updates += 1
		act_prev = a
	var now := Time.get_ticks_msec()
	if now - last_sample >= 100 and multiplayer.multiplayer_peer != null:
		last_sample = now
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		var other := peer_id if role == "host" else 1
		var pp := enet.get_peer(other) if other in multiplayer.get_peers() else null
		if pp != null:
			throttle.append([now - started, pp.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE),
				pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), pp.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)])

func _on_closed() -> void:
	if done: return
	close_rec.append({"unix": now_unix(), "tick": clock.tick if clock != null else -1, "error": channel.last_error,
		"msec": Time.get_ticks_msec(), "last_activity_msec": channel._last_peer_activity,
		"last_activity_unix": (channel._last_peer_activity + offset_ms) / 1000.0})
	if close_rec.size() != 1: return
	if role == "client":
		check("N_close_slots_empty", network._pending.is_empty() and network._latest.is_empty())
		check("N_close_channel_empty", channel.stats().rx_bytes == 0 and channel.stats().pending_bytes == 0 and channel.take_packet().is_empty())
		check("N_close_baseline_invalid", not history.actor_baseline_ready)
		check("N_close_adapter_stopped", not adapter.ready_for_input)
		frozen = {"tick": clock.tick, "native_tick": adapter.world.get_tick(), "hash": state_hash(), "applied": applied_log.size()}
	else:
		check("N_host_close_buffers", channel.stats().tx_bytes == 0)

func post_close_checks() -> void:
	post_close_checked = true
	var q: Dictionary = history.queue_action(clock.tick + 1, 99, "grab")
	check("N_post_close_queue_not_ready", q.status == "rejected" and q.get("reason", "") == "not_ready")
	check("N_post_close_channel_restart_false", not channel.start(adapter.authority_scope(), 1))
	check("N_post_close_bridge_restart_false", not network.start(history, sync, channel, func(_a, _b, _c): pass, func(_a, _b, _c, _d): pass))
	check("N_post_close_request_false", not channel.request_action({"id": 99, "tick": clock.tick + 1, "kind": "grab",
		"anchor": Vector3.ZERO, "impulse": Vector3.ZERO}))
	check("N_post_close_frozen", frozen_bad.is_empty())

func _process(_dt: float) -> void:
	if done: return
	if Time.get_ticks_msec() - started > DEADLINE_MS:
		check("N_internal_deadline", false)
		if role == "client": end_client()
		else: finish_mine(0.08)
		return
	observe_link()
	if role != "client" or not running: return
	if clock.paused:
		network.after_actor_tick()
		if mode == "future" and pause_left > 0:
			pause_left -= 1; paused_frames += 1
			if pause_left == 0: clock.paused = false
	observe_slots()
	if mode == "quiet" and Time.get_ticks_msec() - started >= QUIET_END_MS: end_client()
	if mode == "future" and clock.tick == FUTURE_FINAL and adapter.last_authority().tick == FUTURE_FINAL and not final_hash.is_empty():
		check("N_future_never_future", future_bad == 0)
		check("N_future_at_most_two", occupancy_max <= 2)
		check("N_future_pinned_not_displaced", displaced.is_empty())
		check("N_future_applied_before_final_ge3", applied_log.filter(func(a): return a.tick < FUTURE_FINAL).size() >= 3)
		check("N_future_final_equal", state_hash() == final_hash and adapter.world.get_tick() == FUTURE_FINAL)
		end_client()

func end_client() -> void:
	if end_sent: return
	end_sent = true
	_peer_done.rpc_id(1)
	finish_mine(0.3)

@rpc("any_peer", "call_remote", "reliable")
func _peer_done() -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id: return
	finish_mine(0.08)

func finish_mine(delay: float) -> void:
	if done: return
	var closing := mode in ["close_host", "close_client", "close_both", "lease_silent"]
	if closing:
		check("N_close_once", close_rec.size() == 1)
		if role == "host":
			var p: Dictionary = adapter.authority_scope(); p.version = 1; p.revision = 9999; p.tick = clock.tick
			p.snapshot = adapter.world.snapshot_trusted(); p.acks = []
			check("N_host_publish_after_close_false", not channel.publish(p) and not channel.stats().bound)
		else:
			check("N_post_close_checked", post_close_checked)
			if mode == "close_host": check("N_client_error_peer_closed", not close_rec.is_empty() and close_rec[0].error == "peer_closed")
			if mode == "lease_silent" and not close_rec.is_empty():
				var c: Dictionary = close_rec[0]
				check("N_lease_error", c.error == "peer_idle_timeout")
				check("N_lease_5000_5150", c.msec - c.last_activity_msec >= 5000 and c.msec - c.last_activity_msec <= 5150)
		if role == "host" and mode == "close_client":
			check("N_host_error_peer_closed", not close_rec.is_empty() and close_rec[0].error == "peer_closed")
	else:
		check("N_no_close", close_rec.is_empty())
	done = true
	if clock != null: clock.paused = true
	var failures := checks.filter(func(c): return not c.passed).size()
	var result := {"role": role, "mode": mode, "status": "PASSED" if failures == 0 else "FAILED", "failures": failures,
		"checks": checks, "close": close_rec, "stop_unix": stop_unix, "stop_tx_in_flight": stop_tx_in_flight,
		"frozen_bad": frozen_bad, "applied": applied_log, "rejected": rejected_count, "occupancy_max": occupancy_max,
		"future_bad": future_bad, "displaced": displaced, "max_wait": max_wait, "paused_frames": paused_frames,
		"applied_in_pause": applied_in_pause, "act_max_gap": act_max_gap, "act_updates": act_updates,
		"throttle": throttle, "clock_tick": clock.tick if clock != null else -1, "publishes": publishes,
		"channel": channel.stats(), "effects": effects, "confirmations": confirmations,
		"release_requested": release_requested, "release_applied": release_applied,
		"own_states": network.own_states_received if network != null else 0,
		"corrections": prediction.corrections, "process_ms": Time.get_ticks_msec() - started}
	if not result_path.is_empty(): FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(result))
	print(JSON.stringify({"role": role, "mode": mode, "status": result.status, "failures": failures}))
	await get_tree().create_timer(delay, true, false, true).timeout
	multiplayer.multiplayer_peer.close()
	get_tree().quit(0 if failures == 0 else 1)
