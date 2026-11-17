extends Node
## Validación independiente (Claude), entrega 13. Dos procesos ENet (host y cliente)
## con NetSync, ClientPrediction, ActorMotor, SimClock, history_bridge,
## scene_network_bridge y authority_channel REALES de Codex, sin modificarlos.
## Cada proceso anota lo suyo; la comparación entre procesos se califica fuera,
## en cv13_report.mjs. Modos de a pares: base, delay, time_order, time_old,
## conflict_pause, future, big, rpc. Modo de un proceso: capacity.
## Prefijos de las comprobaciones: run_ (recorrido real), rpc_ (mensaje RPC real
## fabricado por este instrumento), seam_ (punto local sobre un nodo aparte).
const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const History = preload("res://prototypes/objetos_adaptador/history_bridge.gd")
const Channel = preload("res://prototypes/objetos_adaptador/authority_channel.gd")
const NetworkBridge = preload("res://prototypes/objetos_adaptador/scene_network_bridge.gd")
const TapLink = preload("res://prototypes/objetos_adaptador/validacion_claude/cv13_tap_link.gd")
const ACTOR = preload("res://scenes/actor/actor.tscn")
const PAIR_MODES := ["base", "delay", "time_order", "time_old", "conflict_pause", "future", "big", "rpc", "quiet"]
const RELEASE_IMPULSE := Vector3(1.5, 2, -1)
const BOX_TARGET_BYTES := 24000
const BOX_COUNTS := [8, 16, 32, 64, 120]

var role := "host"
var mode := "base"
var port := 29461
var result_path := ""
var trace_path := ""
var final_tick := 80
var checks: Array = []
var done := false
var running := false
var phase := "run"
var peer_id := 0
var started := Time.get_ticks_msec()
var clock: SimClock
var actor: ActorBody
var tuning: ActorTuning
var sync: NetSync
var channel
var adapter
var history
var network
var tap
var prediction := ClientPrediction.new()
var local_input: ActorInput
var extra_boxes := 0
var box_sizes: Array = []
var snapshot_bytes := 0
var closed_count := 0
# Host
var requests := {}
var ledger := {}
var acks: Array = []
var host_ticks := {}
var publishes: Array = []
var held_publish: Array = []
var actions_in: Array = []
var capture_failures: Array = []
var watch := {"violations": [], "frames_by_transfer": {}, "max_tx_bytes": 0, "observations": 0}
var prev_watch := {}
var slow_announced: Array = []
var host_struct := {"first": {}, "second": {}}
var host_final := {}
var client_final_stats := {}
var inject_label := ""
var host_eval := {}
var host_close := {}
# Cliente
var applications: Array = []
var client_ticks := {}
var completions: Array = []
var effects: Array = []
var confirmations: Array = []
var rejected_authorities: Array = []
var needs: Array = []
var recoveries: Array = []
var seen_applied := 0
var release_requested := -1
var release_action := {}
var sent_actions: Array = []
var suspended_action := {}
var pause_until := -1
var paused_by_test := false
var pause_info := {}
var conflict := {}
var hold_info := {}
var provenance := {"latest_misses": [], "slow_not_drained": 0}
var future := {"frames": 0, "max_wait_ms": 0, "replaced": 0, "wait_since": -1, "rev": -1, "episodes": 0}
var client_struct := {"first": {}, "second": {}}
var rx_watch := {"max_rx": 0, "max_rx_parts": 0, "max_pending": 0, "partial_frames": 0, "frames": 0}
var final_stats := {}
var forged_acks: Array = []
var host_cases: Array = []
var case_base := {}
var current_case := ""
var close_res := {}
var after_close := {}
var cap: Array = []
# Diagnóstico agregado después de la primera corrida: estadísticas de ENet del
# peer remoto por tick (estrangulamiento, pérdida, ida y vuelta).
var enet_stats := {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		elif arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
		elif arg.begins_with("--trace="): trace_path = arg.trim_prefix("--trace=")
	check("run_extension", ClassDB.class_exists("SahurObjectWorld"))
	if mode == "capacity":
		setup_capacity()
		return
	if mode not in PAIR_MODES:
		check("run_known_mode", false); finish(); return
	final_tick = 200 if mode == "base" else 80
	sync = NetSync.new(); sync.name = "ActorSync"; add_child(sync)
	channel = Channel.new(); channel.name = "ObjectAuthority"; add_child(channel)
	var peer := ENetMultiplayerPeer.new()
	if role == "host":
		check("run_listen", peer.create_server(port, 1, 2) == OK)
		multiplayer.peer_connected.connect(setup)
	else:
		check("run_connect", peer.create_client("127.0.0.1", port, 2) == OK)
		multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.multiplayer_peer = peer

func _on_connected() -> void:
	setup(multiplayer.get_unique_id())
	_client_ready.rpc_id(1)

# --- Montaje ----------------------------------------------------------------

func base_scene(owner: int) -> Node3D:
	SimClock.clear_world_slow()
	tuning = ActorTuning.new(); add_child(tuning)
	var actors := Node3D.new(); add_child(actors)
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(12, 0.2, 12)
	shape.shape = box; floor_body.add_child(shape); add_child(floor_body); floor_body.position.y = -0.1
	actor = ACTOR.instantiate(); actor.owner_peer_id = owner
	actor.state.position = Vector3(0, 0.02, 1.5); actors.add_child(actor)
	clock = SimClock.new(); clock.actors_root = actors; clock.tuning = tuning
	clock.paused = true; clock.input_provider = provide; add_child(clock)
	return actors

func setup(client_id: int) -> void:
	if clock != null: return
	peer_id = client_id
	if mode == "big": choose_box_count()
	base_scene(client_id)
	sync.clock = clock
	adapter = Adapter.new(); add_child(adapter)
	check("run_adapter_start", adapter.start(clock, actor, tuning, make_world, 2, 1, 1, 13, 1))
	snapshot_bytes = adapter.world.snapshot_trusted().size()
	check("run_bound_enet_channel", channel.start(adapter.authority_scope(), client_id if role == "host" else 1))
	channel.closed.connect(_on_closed)
	if role == "host":
		channel.action_requested.connect(receive_action)
		if mode == "rpc": sender_seams()
	else:
		tap = TapLink.new(); tap.name = "TapLink"; tap.own_peer = client_id; add_child(tap); sync.link = tap
		if mode == "delay": tap.configure(60.0, 25.0, 0.0, 13)
		if mode == "time_order": tap.hold_world_slow = true
		history = History.new(); add_child(history)
		check("run_history_start", history.start(adapter, prediction, step_actor))
		history.effect_ready.connect(on_effect)
		history.action_confirmed.connect(on_confirm)
		history.authority_needed.connect(_on_needed)
		adapter.recovery_required.connect(_on_recovery)
		network = NetworkBridge.new(); add_child(network)
		check("run_scene_network_start", network.start(history, sync, channel, _other_state, _base_state))
		network.object_authority_rejected.connect(_on_rejected)
		channel.packet_available.connect(on_packet_available)
		check("run_client_cannot_publish", not channel.publish({}))
	clock.tick_started.connect(before_tick)
	clock.tick_finished.connect(after_tick)

func _other_state(_id, _tick, _state) -> void: pass
func _base_state(_id, _tick, _p, _v) -> void: pass
func _on_closed() -> void: closed_count += 1
func _on_needed(reason: String) -> void: needs.append([clock.tick, reason])
func _on_recovery(reason: String) -> void: recoveries.append([clock.tick, reason])
func _on_rejected(reason: String) -> void: rejected_authorities.append([clock.tick, reason])

func make_world():
	var w = ClassDB.instantiate("SahurObjectWorld")
	w.add_box(1, 1, Vector3(12, 0.2, 12), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)))
	w.add_box(2, 1, Vector3(0.5, 0.4, 0.5), 2.0, Transform3D(Basis.IDENTITY, Vector3(0, 0.7, -0.3)))
	w.add_box(3, 1, Vector3(0.4, 0.4, 0.4), 1.0, Transform3D(Basis.IDENTITY, Vector3(0.4, 0.2, -0.7)))
	for i in extra_boxes:
		var spot := Vector3(-5.4 + 0.45 * (i % 25), 0.15, -5.4 + 0.45 * floori(i / 25.0))
		w.add_box(100 + i, 1, Vector3(0.3, 0.3, 0.3), 1.0, Transform3D(Basis.IDENTITY, spot))
	w.seal_topology(1)
	return w

## Igual en los dos procesos: el tamaño del snapshot es determinista.
func choose_box_count() -> void:
	for n in BOX_COUNTS:
		extra_boxes = n
		var size: int = make_world().snapshot_trusted().size()
		box_sizes.append([n, size])
		if size >= BOX_TARGET_BYTES: return

@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id or running: return
	if mode == "future":
		running = true; clock.paused = false
		await get_tree().create_timer(0.15, true, false, true).timeout
		_go.rpc_id(peer_id)
	else:
		_go.rpc_id(peer_id)
		await get_tree().create_timer(0.12, true, false, true).timeout
		running = true; clock.paused = false

@rpc("authority", "call_remote", "reliable")
func _go() -> void:
	running = true; clock.paused = false

# --- Tick -------------------------------------------------------------------

func before_tick(tick: int) -> void:
	if role == "host":
		if mode in ["time_order", "time_old"]:
			if tick == 18: SimClock.add_world_slow(18, 34, 0.5)
			if tick == (26 if mode == "time_order" else 44):
				sync.send_world_slow(18, 34, 500, peer_id); slow_announced.append([18, 34, 500, tick])
		return
	var latest_before: int = sync.latest_snapshot_tick
	network.before_actor_tick(tick)
	if not sync.received_world_slow.is_empty(): provenance.slow_not_drained += 1
	if sync.latest_snapshot_tick != latest_before and sync.latest_snapshot_tick not in tap.executed_snapshots:
		provenance.latest_misses.append([tick, sync.latest_snapshot_tick])
	if tick == 18 or (mode == "conflict_pause" and tick == 46):
		actor.state.position.x += 0.12; actor.apply_state(actor.state)

func provide(_who: ActorBody, tick: int) -> ActorInput:
	if mode == "capacity": return provide_capacity(tick)
	var input: ActorInput
	if role == "host":
		input = sync.input_for(peer_id, tick)
		if input == null: input = ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
		if input.hold.is_empty(): input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion.IDENTITY)
		if requests.has(tick):
			var a: Dictionary = requests[tick]
			if not adapter.queue_action(tick, a.id, a.kind, a.anchor, a.impulse): capture_failures.append([tick, "action", adapter.last_error])
			acks.append({"id": a.id, "kind": a.kind, "requested_tick": a.tick, "applied_tick": tick})
			requests.erase(tick)
		if not adapter.capture(input): capture_failures.append([tick, "capture", adapter.last_error])
		return input
	var buttons := ActorInput.BUTTON_CROUCH if tick >= 12 and tick < 17 else 0
	input = ActorInput.make(tick, Vector2(0.3, 0.1), float(tick) * 0.004, buttons, 0)
	input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion(Vector3.UP, float(tick) * 0.01))
	if tick == 3: submit_action(tick, 1, "grab", Vector3(0.05, 0, 0), Vector3.ZERO)
	if tick >= 38 and release_requested < 0 and adapter.ready_for_input:
		release_requested = tick
		submit_action(tick, 2, "release", Vector3.ZERO, RELEASE_IMPULSE)
	if not history.capture_input(input): capture_failures.append([tick, "capture", history.last_error])
	if mode == "conflict_pause" and tick == 22:
		var other := ActorInput.make(tick, Vector2(0.3, 0.1), float(tick) * 0.004 + 0.05, buttons, 0)
		other.hold = input.hold.duplicate()
		var ok: bool = history.capture_input(other)
		conflict = {"tick": tick, "accepted": ok, "error": history.last_error,
			"baseline": history.actor_baseline_ready, "ready": adapter.ready_for_input}
	local_input = input
	return input

func submit_action(tick: int, id: int, kind: String, anchor: Vector3, impulse: Vector3) -> void:
	var a := {"id": id, "tick": tick, "kind": kind, "anchor": anchor, "impulse": impulse}
	if kind == "release": release_action = a.duplicate(true)
	var status: Dictionary = history.queue_action(tick, id, kind, anchor, impulse)
	check("run_predicted_action_%d" % id, status.status == "queued")
	if kind == "release":
		await get_tree().create_timer(0.5 if mode == "delay" else 0.25, true, false, true).timeout
	for i in 2:
		check("run_send_action_%d_%d" % [id, i], channel.request_action(a))
	sent_actions.append([id, clock.tick, Time.get_ticks_msec() - started, 2])

func receive_action(a: Dictionary) -> void:
	var entry := {"id": a.id, "kind": a.kind, "tick": a.tick, "sender": multiplayer.get_remote_sender_id(),
		"host_tick": clock.tick, "phase": phase, "label": inject_label}
	if phase != "run":
		actions_in.append(entry); return
	if a.tick < clock.tick - 120 or a.tick > clock.tick + 120: entry.outcome = "out_of_window"
	elif a.id not in [1, 2] or (a.id == 1 and a.kind != "grab") or (a.id == 2 and a.kind != "release"): entry.outcome = "not_granted"
	elif ledger.has(a.id): entry.outcome = "duplicate_same" if ledger[a.id] == a else "duplicate_conflict"
	elif a.id == 2 and not ledger.has(1): entry.outcome = "release_before_grab"
	else:
		var applied := maxi(a.tick, clock.tick + 1)
		if requests.has(applied): entry.outcome = "slot_taken"
		else:
			ledger[a.id] = a.duplicate(true); requests[applied] = a
			entry.outcome = "scheduled"; entry.applied = applied
	actions_in.append(entry)

func step_actor(input: ActorInput) -> void:
	ActorMotor.step(actor, actor.state, input, tuning, SimClock.world_dt(input.tick))

func after_tick(tick: int) -> void:
	if mode == "capacity":
		capacity_tick(tick); return
	var enet: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(peer_id if role == "host" else 1)
	if enet != null:
		enet_stats[str(tick)] = [enet.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE), enet.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS),
			enet.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), enet.get_statistic(ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME)]
	if role == "host":
		host_ticks[str(tick)] = {"world": world_sha(), "frame": frame_parts(adapter.recorded_frame(tick)),
			"actor": sha(actor.state.to_bytes()), "used": sync.used_input_tick(peer_id), "dt": SimClock.world_dt(tick)}
		sync.send_snapshot(tick, [actor], [])
		maybe_publish(tick)
		sample_host(tick)
		if tick == final_tick: clock.paused = true
		return
	prediction.record(tick, local_input, actor.state)
	sync.send_ticks(prediction.recent(NetSync.INPUT_REDUNDANCY), 0.0)
	note_applications(false)
	client_ticks[str(tick)] = {"world": world_sha(), "ready": adapter.ready_for_input,
		"baseline": history.actor_baseline_ready, "snap": sync.latest_snapshot_tick}
	sample_client(tick)
	if suspended_action.is_empty() and not adapter.ready_for_input \
		and ((mode == "time_old" and network.slow_announcements > 0) or (mode == "conflict_pause" and not conflict.is_empty())):
		suspended_action = history.queue_action(tick + 1, 3, "grab", Vector3.ZERO, Vector3.ZERO).duplicate()
		suspended_action.tick = tick
		suspended_action.adapter_error = adapter.last_error
	if mode == "time_order" and tap.hold_world_slow and adapter.last_authority().tick >= 24:
		tap.hold_world_slow = false
		hold_info = {"released_at": tick, "authority_tick": adapter.last_authority().tick, "held": tap.held.size()}
		hold_info.released = tap.release_held()
	if mode == "conflict_pause" and tick == 56:
		clock.paused = true; paused_by_test = true; pause_until = Time.get_ticks_msec() + 80
		pause_info = {"tick": tick, "applied_before": network.authorities_applied, "frames": 0}
	if tick == final_tick: clock.paused = true

func maybe_publish(tick: int) -> void:
	if mode == "quiet": return # control: sin tráfico del canal de objetos
	var every := 1 if mode == "big" else 4
	if tick % every != 0 and tick != final_tick: return
	var p: Dictionary = adapter.authority_scope()
	p.version = 1; p.revision = tick if mode == "big" else floori(tick / 4.0); p.tick = tick
	p.snapshot = adapter.world.snapshot_trusted(); p.acks = acks.duplicate(true)
	if mode == "delay":
		held_publish.append(p)
		while not held_publish.is_empty() and (held_publish[0].tick <= tick - 6 or tick == final_tick):
			do_publish(held_publish.pop_front(), tick)
	else:
		do_publish(p, tick)

func do_publish(p: Dictionary, now: int) -> void:
	var ok: bool = channel.publish(p)
	publishes.append({"revision": p.revision, "tick": p.tick, "snap": sha(p.snapshot), "bytes": p.snapshot.size(),
		"acks": p.acks.map(func(k): return k.id), "at": now, "ok": ok, "error": "" if ok else channel.last_error})

func note_applications(in_pause: bool) -> void:
	if network.authorities_applied == seen_applied: return
	seen_applied = network.authorities_applied
	var la: Dictionary = adapter.last_authority()
	var c: int = la.tick
	var t: int = clock.tick
	var frames := {}
	for k in range(c + 1, t + 1): frames[str(k)] = frame_parts(adapter.recorded_frame(k))
	applications.append({"T": t, "C": c, "revision": la.revision, "world": world_sha(), "frames": frames,
		"paused": in_pause, "at": Time.get_ticks_msec() - started, "phase": phase, "count": seen_applied})
	if in_pause and paused_by_test: pause_info.applied_in_pause = int(pause_info.get("applied_in_pause", 0)) + 1

func on_packet_available() -> void:
	var p: Dictionary = channel._pending
	completions.append({"revision": p.revision, "tick": p.tick, "snap": sha(p.snapshot),
		"acks": p.acks.map(func(k): return k.id), "clock": clock.tick, "phase": phase, "transfer": channel._high_water})
	if mode == "base" and phase == "run" and channel.completed in [5, 10]:
		for id in [0, channel._high_water, 100000]:
			channel._transfer_ack.rpc_id(1, id)
			forged_acks.append([channel.completed, id])

func on_effect(id: int, kind: String) -> void:
	effects.append([id, kind, clock.tick, adapter.last_authority().revision])

func on_confirm(id: int, kind: String, r: int, a: int) -> void:
	var la: Dictionary = adapter.last_authority()
	confirmations.append([id, kind, r, a, la.revision, la.tick, clock.tick])
	if mode == "base" and id == 2:
		check("run_resend_after_confirmation", channel.request_action(release_action))
		sent_actions.append([2, clock.tick, Time.get_ticks_msec() - started, 1])

# --- Cuadro a cuadro ----------------------------------------------------------

func _process(_dt: float) -> void:
	if done: return
	if Time.get_ticks_msec() - started > 7000:
		check("run_internal_deadline", false); finish(); return
	if bye_deadline >= 0 and (bye_received or Time.get_ticks_msec() >= bye_deadline):
		finish(); return
	if mode == "capacity" or not running: return
	if role == "host":
		if phase == "run": host_watch()
		return
	client_watch()
	if phase != "run": return
	if paused_by_test:
		pause_info.frames += 1
		if Time.get_ticks_msec() >= pause_until:
			paused_by_test = false; clock.paused = false; pause_info.resumed_tick = clock.tick
	if clock.paused:
		network.after_actor_tick(); note_applications(true)
	if clock.tick == final_tick and (mode == "quiet" or adapter.last_authority().tick == final_tick):
		client_final()

func host_watch() -> void:
	if not channel.stats().bound: return
	var tx: Dictionary = channel._tx
	var now := {"id": int(tx.get("id", 0)), "active": not tx.is_empty(), "awaiting": bool(tx.get("awaiting_ack", false)),
		"sent": channel.sent_chunks, "acks": channel.transfer_acks}
	watch.observations += 1
	if now.active and now.acks != now.id - 1: violation("acks_vs_id", now)
	if not prev_watch.is_empty():
		if prev_watch.awaiting and now.sent > prev_watch.sent and now.acks == prev_watch.acks: violation("sent_while_awaiting", now)
		if now.sent > prev_watch.sent:
			var key := str(now.id if now.active else channel._next_transfer)
			watch.frames_by_transfer[key] = int(watch.frames_by_transfer.get(key, 0)) + 1
	watch.max_tx_bytes = maxi(watch.max_tx_bytes, channel.stats().tx_bytes)
	prev_watch = now

func violation(kind: String, data: Dictionary) -> void:
	if watch.violations.size() < 20: watch.violations.append([kind, data.duplicate(), clock.tick])

func client_watch() -> void:
	var s: Dictionary = channel.stats()
	rx_watch.frames += 1
	rx_watch.max_rx = maxi(rx_watch.max_rx, s.rx_bytes)
	rx_watch.max_rx_parts = maxi(rx_watch.max_rx_parts, s.rx_parts)
	rx_watch.max_pending = maxi(rx_watch.max_pending, s.pending_bytes)
	if s.rx_parts > 0: rx_watch.partial_frames += 1
	var pend: Dictionary = network._pending
	var now := Time.get_ticks_msec()
	if not pend.is_empty() and pend.tick > clock.tick:
		future.frames += 1
		if future.wait_since < 0:
			future.wait_since = now; future.episodes += 1; future.rev = pend.revision
		elif pend.revision != future.rev:
			future.replaced += 1; future.rev = pend.revision
		future.max_wait_ms = maxi(future.max_wait_ms, now - future.wait_since)
	else:
		future.wait_since = -1

func sample_host(tick: int) -> void:
	var a: Dictionary = adapter.history_stats()
	var s := {"inputs": sync._inputs.get(peer_id, {}).size(), "claims": sync._claims.get(peer_id, {}).size(),
		"adapter_ticks": a.ticks, "adapter_bytes": a.bytes, "adapter_actions": adapter._actions.size(),
		"tx_bytes": channel.stats().tx_bytes, "objects": Performance.get_monitor(Performance.OBJECT_COUNT)}
	keep_max(host_struct, tick, s)

func sample_client(tick: int) -> void:
	var h: Dictionary = history.stats()
	var a: Dictionary = adapter.history_stats()
	var s := {"bridge_ticks": h.ticks, "bridge_bytes": h.bytes, "adapter_ticks": a.ticks, "adapter_bytes": a.bytes,
		"pending_inputs": history._pending_inputs.size(), "commands": history._commands.size(),
		"known_actions": history._known_actions.size(), "adapter_actions": adapter._actions.size(),
		"adapter_pending": adapter._pending.size(), "adapter_queued": adapter._queued.size(),
		"pred_inputs": prediction._inputs.size(), "pred_states": prediction._states.size(), "pred_claimed": prediction._claimed.size(),
		"events": sync.received_events.size(), "spans": SimClock.world_slow_spans().size(), "tap_queue": tap._queue.size(),
		"bridge_pending": 0 if network._pending.is_empty() else 1, "channel_rx": channel.stats().rx_bytes,
		"channel_pending": channel.stats().pending_bytes, "objects": Performance.get_monitor(Performance.OBJECT_COUNT)}
	keep_max(client_struct, tick, s)

func keep_max(store: Dictionary, tick: int, s: Dictionary) -> void:
	var half: Dictionary = store.first if tick <= (final_tick >> 1) else store.second
	for k in s: half[k] = maxi(int(half.get(k, 0)), int(s[k]))

# --- Final ------------------------------------------------------------------

func client_final() -> void:
	phase = "final"
	final_stats = {"channel": channel.stats(), "completed": channel.completed, "applied": network.authorities_applied,
		"snapshots_received": sync.snapshots_received, "snapshots_missing": sync.snapshots_missing,
		"own_states": network.own_states_received, "slow_announcements": network.slow_announcements,
		"world": world_sha(), "tick": clock.tick, "high_water": channel._high_water, "last_revision": channel._last_revision,
		"corrections": prediction.corrections, "alignments": prediction.alignments, "replay_callbacks": history.replay_callbacks,
		"history": history.stats(), "adapter_ready": adapter.ready_for_input}
	if mode == "rpc":
		phase = "rpc"
		_rpc_phase.rpc_id(1, channel._high_water, channel._last_revision)
		return
	_finished.rpc_id(1, final_stats)
	wait_bye()

## Corrección tras la segunda corrida: el cliente espera el saludo del host (hasta 1 s)
## antes de cerrar ENet, para que su último aviso no se pierda en el cierre.
var bye_deadline := -1
var bye_received := false

func wait_bye() -> void:
	bye_deadline = Time.get_ticks_msec() + 1000

@rpc("authority", "call_remote", "reliable", 1)
func _bye() -> void:
	if role == "client" and multiplayer.get_remote_sender_id() == 1: bye_received = true

func host_stats() -> Dictionary:
	return {"transfer_acks": channel.transfer_acks, "sent": channel.sent_chunks, "max_wire": channel.max_wire_bytes,
		"next_transfer": channel._next_transfer, "tx_bytes": channel.stats().tx_bytes, "bound": channel.stats().bound,
		"tick": clock.tick, "last_error": channel.last_error}

@rpc("any_peer", "call_remote", "reliable", 1)
func _finished(stats: Dictionary) -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id: return
	if host_final.is_empty(): host_final = host_stats()
	client_final_stats = stats
	_bye.rpc_id(peer_id)
	finish()

# --- Modo rpc: mensajes reales fabricados y cierre ---------------------------

@rpc("any_peer", "call_remote", "reliable", 1)
func _rpc_phase(client_high: int, client_rev: int) -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id or phase != "run": return
	host_final = host_stats(); phase = "rpc"
	var cb := Channel.CHUNK_BYTES
	var real := envelope(client_rev + 1, 0)
	var dup := envelope(client_rev, 0)
	var foreign := envelope(client_rev + 1, 2)
	var h := client_high
	var n := ceili(float(real.size()) / cb)
	var bad_digest := Channel.digest(real); bad_digest[0] ^= 1
	var other_digest := Channel.digest(dup); other_digest[5] ^= 1
	var conflicting := chunk(dup, h + 4, 0); conflicting[-1] ^= 1
	var cases := [
		["magic", [chunk(real, h + 1, 0, {"magic": Channel.MAGIC + 1})]],
		["old_connection", [chunk(real, h + 1, 0, {"connection": 12})]],
		["short", [filled(Channel.HEADER_BYTES, 0)]],
		["over_wire", [chunk(real, h + 1, 0, {"data": filled(cb + 1, 1)})]],
		["total_over_max", [chunk(real, h + 1, 0, {"total": Channel.MAX_BYTES + 1, "count": ceili(float(Channel.MAX_BYTES + 1) / cb), "data": filled(cb, 1)})]],
		["count_mismatch", [chunk(real, h + 1, 0, {"count": n + 1})]],
		["index_out_of_range", [chunk(real, h + 1, n, {"data": real.slice(0, 80)})]],
		["data_length", [chunk(real, h + 1, 0, {"data": real.slice(0, cb - 1)})]],
		["id_zero", [chunk(real, 0, 0)]],
		["id_over", [chunk(real, 0x80000000, 0)]],
		["stale_id", [chunk(real, h, 0)]],
		["digest", all_chunks(real, h + 1, {"digest": bad_digest})],
		["scope", all_chunks(foreign, h + 2, {})],
		["stale_revision", all_chunks(dup, h + 3, {})],
		["chunk_conflict", [chunk(dup, h + 4, 0), conflicting]],
		["after_conflict", all_chunks(dup, h + 4, {}).slice(1)],
		["transfer_conflict", [chunk(dup, h + 5, 0), chunk(dup, h + 5, 1, {"digest": other_digest})]],
		["control_accept", all_chunks(real, h + 6, {})],
	]
	for c in cases:
		_case_marker.rpc_id(peer_id, c[0])
		for data in c[1]: channel._receive_chunk.rpc_id(peer_id, data)
	_case_marker.rpc_id(peer_id, "")

## Sobre con bytes nativos REALES del host en el tick final. Con otro contexto
## se arma con ese contexto (el cliente debe rechazarlo antes de restaurar).
func envelope(revision: int, context: int) -> PackedByteArray:
	var scope: Dictionary = adapter.authority_scope()
	var p: Dictionary = scope.duplicate(true)
	p.version = 1; p.revision = revision; p.tick = final_tick; p.acks = acks.duplicate(true)
	p.snapshot = adapter.world.snapshot_trusted()
	if context > 0:
		scope = scope.duplicate(true); scope.context = context; p.context = context
	return Channel.encode_packet(p, scope)

func chunk(payload: PackedByteArray, id: int, index: int, opts: Dictionary = {}) -> PackedByteArray:
	var cb := Channel.CHUNK_BYTES
	var total: int = opts.get("total", payload.size())
	var count: int = opts.get("count", ceili(float(payload.size()) / cb))
	# Corrección tras la segunda corrida: get() evaluaba el SHA del sobre entero en cada fragmento.
	var dg: PackedByteArray = opts.digest if opts.has("digest") else Channel.digest(payload)
	var data: PackedByteArray = opts.get("data", payload.slice(index * cb, mini((index + 1) * cb, payload.size())))
	var b := StreamPeerBuffer.new()
	b.put_u32(opts.get("magic", Channel.MAGIC)); b.put_u32(opts.get("connection", 13)); b.put_u32(id)
	b.put_u32(total); b.put_u16(index); b.put_u16(count); b.put_data(dg); b.put_data(data)
	return b.data_array

func all_chunks(payload: PackedByteArray, id: int, opts: Dictionary) -> Array:
	var out: Array = []
	var once := opts.duplicate()
	if not once.has("digest"): once.digest = Channel.digest(payload)
	for i in ceili(float(payload.size()) / Channel.CHUNK_BYTES): out.append(chunk(payload, id, i, once))
	return out

@rpc("authority", "call_remote", "reliable", 1)
func _case_marker(label: String) -> void:
	if role != "client" or multiplayer.get_remote_sender_id() != 1: return
	if current_case != "":
		var s: Dictionary = channel.stats()
		host_cases.append({"case": current_case, "error": channel.last_error,
			"rejected": channel.rejected_chunks - int(case_base.rejected), "completed": channel.completed - int(case_base.completed),
			"rx_bytes": s.rx_bytes, "rx_parts": s.rx_parts, "pending_bytes": s.pending_bytes,
			"applied": network.authorities_applied - int(case_base.applied), "world_same": world_sha() == case_base.world,
			"high_water": channel._high_water})
	current_case = label
	case_base = {"rejected": channel.rejected_chunks, "completed": channel.completed,
		"applied": network.authorities_applied, "world": world_sha()}
	if label == "": inject_client_cases()

func action_bytes(scope: Dictionary, id: int, tick: int, kind: int, anchor: Vector3, impulse: Vector3) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	for key in Channel.SCOPE_FIELDS: b.put_u32(scope[key])
	b.put_data(String(scope.hand_signature).hex_decode())
	b.put_u32(id); b.put_u32(tick); b.put_u8(kind)
	for v: Vector3 in [anchor, impulse]:
		b.put_float(v.x); b.put_float(v.y); b.put_float(v.z)
	return b.data_array

func inject_client_cases() -> void:
	var scope: Dictionary = adapter.authority_scope()
	var t := final_tick + 1
	var base := action_bytes(scope, 99, t, 1, Vector3.ZERO, Vector3.ZERO)
	var longer := base.duplicate(); longer.append(0)
	var old_conn: Dictionary = scope.duplicate(); old_conn.connection = 12
	var other_hand: Dictionary = scope.duplicate()
	other_hand.hand_signature = ("1" if String(scope.hand_signature)[0] == "0" else "0") + String(scope.hand_signature).substr(1)
	var cases := [
		["size84", base.slice(0, 84)], ["size86", longer],
		["connection12", action_bytes(old_conn, 99, t, 1, Vector3.ZERO, Vector3.ZERO)],
		["hand_signature", action_bytes(other_hand, 99, t, 1, Vector3.ZERO, Vector3.ZERO)],
		["kind0", action_bytes(scope, 99, t, 0, Vector3.ZERO, Vector3.ZERO)],
		["kind3", action_bytes(scope, 99, t, 3, Vector3.ZERO, Vector3.ZERO)],
		["anchor_nan", action_bytes(scope, 99, t, 1, Vector3(NAN, 0, 0), Vector3.ZERO)],
		["anchor_long", action_bytes(scope, 99, t, 1, Vector3(1.01, 0, 0), Vector3.ZERO)],
		["impulse_long", action_bytes(scope, 99, t, 2, Vector3.ZERO, Vector3(100.01, 0, 0))],
		["id0", action_bytes(scope, 0, t, 1, Vector3.ZERO, Vector3.ZERO)],
		["id_over", action_bytes(scope, 0x80000000, t, 1, Vector3.ZERO, Vector3.ZERO)],
		["tick_over", action_bytes(scope, 99, 0x80000000, 1, Vector3.ZERO, Vector3.ZERO)],
		["control", base],
	]
	for c in cases:
		_client_case.rpc_id(1, c[0])
		channel._submit_action.rpc_id(1, c[1])
	_client_case.rpc_id(1, "forged_acks")
	for id in [0, int(final_stats.high_water), channel._high_water, 100000]:
		channel._transfer_ack.rpc_id(1, id)
	_client_case.rpc_id(1, "")

@rpc("any_peer", "call_remote", "reliable", 1)
func _client_case(label: String) -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id or phase != "rpc": return
	inject_label = label
	if label != "": return
	var counts := {}
	for e in actions_in:
		if e.phase == "rpc": counts[e.label] = int(counts.get(e.label, 0)) + 1
	host_eval = {"counts": counts, "transfer_acks_before": host_final.transfer_acks, "transfer_acks_after": channel.transfer_acks,
		"control_entry": actions_in.filter(func(e): return e.phase == "rpc" and e.label == "control")}
	# Cierre de un solo lado: el host detiene su canal; el cliente no recibe aviso del canal.
	var before := closed_count
	channel.stop()
	var p: Dictionary = adapter.authority_scope()
	p.version = 1; p.revision = 0x7000; p.tick = final_tick; p.acks = []; p.snapshot = filled(16, 1)
	host_close = {"closed": closed_count - before, "publish": channel.publish(p), "error": channel.last_error,
		"restart": channel.start(adapter.authority_scope(), peer_id), "stats": channel.stats()}
	_host_closed.rpc_id(peer_id)

@rpc("authority", "call_remote", "reliable", 1)
func _host_closed() -> void:
	if role != "client" or multiplayer.get_remote_sender_id() != 1: return
	var bound_after_host_stop: bool = channel.stats().bound
	var pending_before: int = channel.stats().pending_bytes
	var before := closed_count
	channel.stop()
	close_res = {"client_bound_after_host_stop": bound_after_host_stop, "pending_before": pending_before,
		"closed_once": closed_count - before, "bridge_pending_empty": network._pending.is_empty(),
		"baseline": history.actor_baseline_ready, "ready": adapter.ready_for_input, "adapter_error": adapter.last_error,
		"stats": channel.stats(),
		"queue_new": history.queue_action(clock.tick + 1, 7, "grab", Vector3.ZERO, Vector3.ZERO),
		"restart": channel.start(adapter.authority_scope()),
		"request": channel.request_action({"id": 8, "tick": clock.tick + 1, "kind": "grab", "anchor": Vector3.ZERO, "impulse": Vector3.ZERO})}
	case_base = {"rejected": channel.rejected_chunks}
	_client_closed.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 1)
func _client_closed() -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id: return
	channel._receive_chunk.rpc_id(peer_id, chunk(envelope(0x7001, 0), int(host_final.next_transfer) + 7, 0))
	_after_close.rpc_id(peer_id)

@rpc("authority", "call_remote", "reliable", 1)
func _after_close() -> void:
	if role != "client" or multiplayer.get_remote_sender_id() != 1: return
	after_close = {"error": channel.last_error, "rejected": channel.rejected_chunks - int(case_base.rejected),
		"stats": channel.stats()}
	client_seams()
	_finished.rpc_id(1, final_stats)
	wait_bye()

# --- Puntos locales (seam_) -----------------------------------------------------

func packet_dict(scope: Dictionary, revision: int, tick: int, ack_list: Array, snapshot: PackedByteArray) -> Dictionary:
	var p: Dictionary = scope.duplicate(true)
	p.version = 1; p.revision = revision; p.tick = tick; p.acks = ack_list.duplicate(true); p.snapshot = snapshot
	return p

func ack_list(count: int) -> Array:
	var out: Array = []
	for i in count: out.append({"id": i + 1, "kind": "grab", "requested_tick": 1, "applied_tick": 2})
	return out

func client_seams() -> void:
	var scope: Dictionary = adapter.authority_scope()
	var p := packet_dict(scope, 5, 10, ack_list(16), filled(64, 3))
	var encoded := Channel.encode_packet(p, scope)
	check("seam_encode_16_acks", not encoded.is_empty())
	var q := p.duplicate(true); q.acks = ack_list(17)
	check("seam_encode_17_acks_rejected", Channel.encode_packet(q, scope).is_empty())
	q = p.duplicate(true); q.acks[1].id = 1
	check("seam_encode_duplicate_ack_id", Channel.encode_packet(q, scope).is_empty())
	q = p.duplicate(true); q.acks[0].requested_tick = 3
	check("seam_encode_applied_before_requested", Channel.encode_packet(q, scope).is_empty())
	q = p.duplicate(true); q.acks[0].applied_tick = 11
	check("seam_encode_applied_after_tick", Channel.encode_packet(q, scope).is_empty())
	q = p.duplicate(true); q.snapshot = PackedByteArray()
	check("seam_encode_empty_snapshot", Channel.encode_packet(q, scope).is_empty())
	q = p.duplicate(true); q.snapshot = filled(1048620, 2)
	check("seam_encode_snapshot_1048620", not Channel.encode_packet(q, scope).is_empty())
	q.snapshot = filled(1048621, 2)
	check("seam_encode_snapshot_1048621_rejected", Channel.encode_packet(q, scope).is_empty())
	q = p.duplicate(true); q.version = 2
	check("seam_encode_version_2", Channel.encode_packet(q, scope).is_empty())
	q = p.duplicate(true); q.revision = 0
	check("seam_encode_revision_0", Channel.encode_packet(q, scope).is_empty())
	q.revision = 0x80000000
	check("seam_encode_revision_over", Channel.encode_packet(q, scope).is_empty())
	q = p.duplicate(true); q.tick = -1
	check("seam_encode_negative_tick", Channel.encode_packet(q, scope).is_empty())
	var d: Dictionary = Channel.decode_packet(encoded, scope)
	check("seam_decode_roundtrip", not d.is_empty() and d.revision == 5 and d.tick == 10 and d.acks.size() == 16 and d.snapshot == p.snapshot)
	check("seam_decode_truncated", Channel.decode_packet(encoded.slice(0, encoded.size() - 1), scope).is_empty())
	var extra := encoded.duplicate(); extra.append(0)
	check("seam_decode_trailing_byte", Channel.decode_packet(extra, scope).is_empty())
	var bad := encoded.duplicate(); bad[0] = 2
	check("seam_decode_version_2", Channel.decode_packet(bad, scope).is_empty())
	bad = encoded.duplicate(); bad[61] = 17
	check("seam_decode_ack_count_17", Channel.decode_packet(bad, scope).is_empty())
	bad = encoded.duplicate(); bad.encode_u32(62 + 16 * 13, 65)
	check("seam_decode_snapshot_length", Channel.decode_packet(bad, scope).is_empty())
	bad = encoded.duplicate(); bad.encode_u32(53, 0)
	check("seam_decode_revision_0", Channel.decode_packet(bad, scope).is_empty())
	bad = encoded.duplicate(); bad[66] = 3
	check("seam_decode_ack_kind_3", Channel.decode_packet(bad, scope).is_empty())
	bad = encoded.duplicate(); bad.encode_u32(71, 0)
	check("seam_decode_applied_before_requested", Channel.decode_packet(bad, scope).is_empty())
	bad = encoded.duplicate(); bad.encode_u32(5, 2)
	check("seam_decode_other_context", Channel.decode_packet(bad, scope).is_empty())
	# Rearmado en un nodo aparte, sin puente: estos buffers nunca llegan al mundo nativo.
	var unit = Channel.new(); unit.name = "SeamUnit"; add_child(unit)
	check("seam_unit_binding", unit.start(scope))
	var big_snap := filled(1048620, 5)
	var data := Channel.encode_packet(packet_dict(scope, 1, 10, ack_list(16), big_snap), scope)
	check("seam_max_envelope_size", data.size() == 66 + 16 * 13 + 1048620)
	var parts := all_chunks(data, 1, {})
	var all_ok := true
	var max_rx := 0
	for i in range(parts.size() - 1, -1, -1):
		all_ok = unit.accept_host_chunk(1, parts[i]) and all_ok
		max_rx = maxi(max_rx, unit.stats().rx_bytes)
	var after_rx: int = unit.stats().rx_bytes
	var pending_now: int = unit.stats().pending_bytes
	var got: Dictionary = unit.take_packet()
	check("seam_max_transfer_reverse_order", all_ok and parts.size() == 1093 and got.get("snapshot", PackedByteArray()) == big_snap)
	check("seam_max_rearm_bounded_and_released", max_rx <= Channel.MAX_BYTES and max_rx >= data.size() - Channel.CHUNK_BYTES \
		and after_rx == 0 and pending_now == 1048620 and unit.stats().pending_bytes == 0)
	var over := chunk(filled(Channel.CHUNK_BYTES, 1), 2, 0, {"total": 1095 * Channel.CHUNK_BYTES, "count": 1095})
	check("seam_count_over_max_chunks", not unit.accept_host_chunk(1, over) and unit.last_error == "chunk_header" and unit.stats().rx_bytes == 0)
	var small := Channel.encode_packet(packet_dict(scope, 2, 11, [], filled(3000, 9)), scope)
	parts = all_chunks(small, 3, {})
	check("seam_partial_started", unit.accept_host_chunk(1, parts[0]) and unit.stats().rx_bytes > 0)
	unit._rx.started -= Channel.TIMEOUT_MS + 1; unit._process(0.0)
	check("seam_rx_timeout_releases", unit.stats().rx_bytes == 0 and unit.stats().rx_parts == 0 and unit.last_error == "transfer_timeout")
	check("seam_timeout_no_resurrection", not unit.accept_host_chunk(1, parts[1]) and unit.last_error == "stale_transfer")
	parts = all_chunks(small, 4, {})
	unit.accept_host_chunk(1, parts[0])
	var flipped: PackedByteArray = parts[0].duplicate(); flipped[-1] ^= 1
	check("seam_chunk_conflict_releases", not unit.accept_host_chunk(1, flipped) and unit.last_error == "chunk_conflict" and unit.stats().rx_bytes == 0)
	parts = all_chunks(small, 5, {})
	parts[-1][-1] ^= 1
	for part in parts: unit.accept_host_chunk(1, part)
	check("seam_digest_releases", unit.take_packet().is_empty() and unit.last_error == "transfer_digest" and unit.stats().rx_bytes == 0)
	parts = all_chunks(small, 6, {})
	var order_ok: bool = unit.accept_host_chunk(1, parts[2]) and unit.accept_host_chunk(1, parts[2])
	var rx_after_dup: int = unit.stats().rx_bytes
	order_ok = order_ok and rx_after_dup == parts[2].size() - Channel.HEADER_BYTES
	for i in [0, 3, 1]: order_ok = unit.accept_host_chunk(1, parts[i]) and order_ok
	var small_got: Dictionary = unit.take_packet()
	check("seam_out_of_order_with_identical_duplicate", order_ok and small_got.get("revision", -1) == 2 and unit.stats().rx_bytes == 0)
	parts = all_chunks(Channel.encode_packet(packet_dict(scope, 3, 12, [], filled(3000, 8)), scope), 7, {})
	unit.accept_host_chunk(1, parts[0])
	unit.stop()
	var stopped: Dictionary = unit.stats()
	check("seam_stop_releases", stopped.rx_bytes == 0 and stopped.pending_bytes == 0 and not stopped.bound)
	check("seam_stopped_rejects_chunks", not unit.accept_host_chunk(1, parts[1]) and unit.last_error == "unbound_sender")
	check("seam_stopped_not_reusable", not unit.start(scope))
	check("seam_stopped_no_actions", not unit.request_action({"id": 1, "tick": 1, "kind": "grab", "anchor": Vector3.ZERO, "impulse": Vector3.ZERO}))
	unit.queue_free()

func sender_seams() -> void:
	var scope: Dictionary = adapter.authority_scope()
	var unit = Channel.new(); unit.name = "SeamSender"; add_child(unit); unit.set_process(false)
	check("seam_sender_binding", unit.start(scope, peer_id))
	var p1 := packet_dict(scope, 1, 5, [], filled(2000, 11))
	check("seam_sender_publish", unit.publish(p1))
	var first: PackedByteArray = unit._next_packet.duplicate()
	var bad := p1.duplicate(true); bad.revision = 2; bad.snapshot = PackedByteArray()
	check("seam_invalid_does_not_replace", not unit.publish(bad) and unit._next_packet == first)
	var same_tick := p1.duplicate(true); same_tick.revision = 2
	check("seam_same_tick_newer_revision_replaces", unit.publish(same_tick) and unit._next_packet != first \
		and Channel.decode_packet(unit._next_packet, scope).get("revision", -1) == 2)
	var kept: PackedByteArray = unit._next_packet.duplicate()
	var older := p1.duplicate(true); older.revision = 3; older.tick = 4
	check("seam_older_tick_rejected", not unit.publish(older) and unit._next_packet == kept and unit.last_error == "stale_authority_tick")
	check("seam_duplicate_revision_rejected", not unit.publish(same_tick) and unit.last_error == "duplicate_revision")
	check("seam_sender_rejects_chunks", not unit.accept_host_chunk(1, chunk(kept, 1, 0)) and unit.last_error == "unbound_sender")
	check("seam_sender_cannot_request_action", not unit.request_action({"id": 1, "tick": 1, "kind": "grab", "anchor": Vector3.ZERO, "impulse": Vector3.ZERO}))
	unit.stop()
	var newer := p1.duplicate(true); newer.revision = 9; newer.tick = 9
	check("seam_sender_stop_releases", unit.stats().tx_bytes == 0 and not unit.stats().bound and not unit.publish(newer) and not unit.start(scope, peer_id))
	unit.queue_free()

# --- Modo capacity: un proceso, sin red -----------------------------------------

func setup_capacity() -> void:
	final_tick = 280
	base_scene(1)
	adapter = Adapter.new(); add_child(adapter)
	check("run_adapter_start", adapter.start(clock, actor, tuning, make_world, 2, 1, 1, 13, 1))
	history = History.new(); add_child(history)
	check("run_history_start", history.start(adapter, prediction, step_actor))
	clock.tick_finished.connect(after_tick)
	running = true; clock.paused = false

func provide_capacity(tick: int) -> ActorInput:
	var input := ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion.IDENTITY)
	if tick <= 270:
		var r: Dictionary = history.queue_action(tick, tick, "grab" if tick % 2 == 1 else "release", Vector3.ZERO, Vector3.ZERO)
		cap.append([tick, r.status, r.get("reason", ""), adapter.ready_for_input])
	if not history.capture_input(input): capture_failures.append([tick, "capture", history.last_error])
	local_input = input
	return input

func capacity_tick(tick: int) -> void:
	prediction.record(tick, local_input, actor.state)
	if tick in [120, 200, 256, 257, 270, final_tick]:
		client_ticks[str(tick)] = {"ready": adapter.ready_for_input, "adapter_actions": adapter._actions.size(),
			"known_actions": history._known_actions.size(), "effects": history._effects.size(),
			"bridge_ticks": history.stats().ticks, "adapter_ticks": adapter.history_stats().ticks, "error": adapter.last_error}
	if tick == final_tick:
		clock.paused = true
		finish()

# --- Utilidades ---------------------------------------------------------------

static func filled(size: int, value: int) -> PackedByteArray:
	var b := PackedByteArray(); b.resize(size); b.fill(value)
	return b

static func sha(data: PackedByteArray) -> String:
	return Channel.digest(data).hex_encode()

static func short(data: PackedByteArray) -> String:
	return Channel.digest(data).hex_encode().substr(0, 16)

static func frame_parts(f: Dictionary) -> Array:
	if f.is_empty(): return []
	var a: Dictionary = f.get("action", {})
	var act: Array = [] if a.is_empty() else [a.id, a.kind, a.tick, a.anchor, a.impulse]
	return [f.tick, short(var_to_bytes(f.dt)), short(var_to_bytes(f.eyes)), short(f.input), short(var_to_bytes(act))]

func world_sha() -> String:
	return sha(var_to_bytes(adapter.world.samples()))

func check(id: String, passed: bool) -> void:
	checks.append({"id": id, "passed": passed})
	if not passed: push_error("CHECK_FAILED: " + id)

func finish() -> void:
	if done: return
	done = true
	var failures := checks.filter(func(c): return not c.passed).size()
	var result := {"role": role, "mode": mode, "final_tick": final_tick, "peer_id": peer_id, "checks": checks,
		"failures": failures, "snapshot_bytes": snapshot_bytes, "extra_boxes": extra_boxes, "box_sizes": box_sizes,
		"capture_failures": capture_failures, "closed_count": closed_count, "elapsed_ms": Time.get_ticks_msec() - started,
		"enet": enet_stats, "bye_received": bye_received}
	if role == "host":
		result.merge({"ticks": host_ticks, "publishes": publishes, "actions_in": actions_in, "acks": acks,
			"watch": watch, "slow_announced": slow_announced, "struct": host_struct, "final": host_final,
			"client_final": client_final_stats, "rpc_eval": host_eval, "host_close": host_close})
	else:
		result.merge({"applications": applications, "ticks": client_ticks, "completions": completions,
			"effects": effects, "confirmations": confirmations, "rejected_authorities": rejected_authorities,
			"needs": needs, "recoveries": recoveries, "release_requested": release_requested, "sent_actions": sent_actions,
			"suspended_action": suspended_action, "pause": pause_info, "conflict": conflict, "hold": hold_info,
			"provenance": provenance, "future": future, "struct": client_struct, "rx_watch": rx_watch, "final": final_stats,
			"forged_acks": forged_acks, "host_cases": host_cases, "close": close_res, "after_close": after_close, "capacity": cap})
		if tap != null:
			result.tap = {"executed_snapshots": tap.executed_snapshots, "executed_slow": tap.executed_slow,
				"in_senders": tap.notes.filter(func(n): return n.phase == "in").map(func(n): return n.sender),
				"delivered": tap.delivered, "dropped": tap.dropped}
	if not result_path.is_empty(): FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(result))
	if not trace_path.is_empty() and tap != null: FileAccess.open(trace_path, FileAccess.WRITE).store_string(JSON.stringify(tap.notes))
	print("CV13 %s %s checks=%d failures=%d" % [role, mode, checks.size(), failures])
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		await get_tree().create_timer(0.08, true, false, true).timeout
		multiplayer.multiplayer_peer.close()
	get_tree().quit(0 if failures == 0 else 1)
