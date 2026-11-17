extends "res://prototypes/objetos_adaptador/probe_network.gd"
var close_count := 0
var applied_before_final := 0
var applied_future := false
var close_sample := ""
var close_msec := -1
var peer_done := false

func setup(client_id: int) -> void:
	super.setup(client_id)
	channel.closed.connect(func():
		close_count += 1; close_msec = Time.get_ticks_msec()
		close_sample = state_hash(); clock.paused = true)
	if role == "client":
		network.object_authority_applied.connect(func(t: int, _r: int):
			if clock.tick < FINAL_TICK: applied_before_final += 1
			if t > clock.tick: applied_future = true)

@rpc("authority", "call_remote", "reliable")
func _go() -> void:
	if mode == "net_future": await get_tree().create_timer(0.3, true, false, true).timeout
	running = true; clock.paused = false

func after_tick(tick: int) -> void:
	super.after_tick(tick)
	if role == "host" and mode != "net_future" and tick == 20:
		clock.paused = true
		if mode == "net_close": channel.stop()
		elif mode == "net_timeout":
			# Inject age of a local in-flight transfer; the close itself is a real
			# control RPC. The separate lease mode waits actual wall-clock time.
			channel._tx = {"id": 99, "data": PackedByteArray([1]), "index": 0,
				"awaiting_ack": true, "started": Time.get_ticks_msec() - Channel.TIMEOUT_MS - 1}
		elif mode == "net_lease": channel.stop(false) # simulate lost close notice

func on_authority(_checkpoint: int, _revision: int) -> void:
	pass # Future-client mode has zero-step restores; positive replay is tested separately.

func _process(_delta: float) -> void:
	if done: return
	if Time.get_ticks_msec() - started > 7200:
		check("lifecycle_deadline", false); finish(); return
	if role == "host" or not running: return
	if clock.paused: network.after_actor_tick()
	if mode == "net_future":
		if clock.tick != FINAL_TICK or adapter.last_authority().tick != FINAL_TICK or final_hash.is_empty(): return
		check("future_client_updates_before_host_final", applied_before_final >= 4)
		check("no_future_state_applied", not applied_future)
		check("future_client_final_equal", state_hash() == final_hash)
		check("bounded_two_bridge_slots", network._pending.size() == 0 and network._latest.size() == 0)
		_lifecycle_done.rpc_id(1, true)
		finish()
	elif close_count == 1 and Time.get_ticks_msec() - close_msec >= 60:
		check("peer_close_once", close_count == 1 and not channel.stats().bound)
		check("peer_close_invalidates_native", not adapter.ready_for_input and not history.actor_baseline_ready)
		check("all_pending_released", network._pending.is_empty() and network._latest.is_empty() \
			and channel.stats().rx_bytes == 0 and channel.stats().pending_bytes == 0)
		check("native_stays_frozen", state_hash() == close_sample)
		if mode == "net_lease":
			check("real_lease_expired", channel.last_error == "peer_idle_timeout" and close_msec - started >= Channel.TIMEOUT_MS)
		else: check("real_peer_close_notice", channel.last_error == "peer_closed" and close_msec - started < 3000)
		_lifecycle_done.rpc_id(1, true)
		finish()

@rpc("any_peer", "call_remote", "reliable")
func _lifecycle_done(ok: bool) -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id: return
	check("peer_observed_lifecycle_result", ok)
	if mode == "net_timeout": check("sender_timeout_closed", channel.last_error == "send_timeout" and not channel.stats().bound)
	if mode != "net_future": check("sender_closed_once", close_count == 1)
	finish()
