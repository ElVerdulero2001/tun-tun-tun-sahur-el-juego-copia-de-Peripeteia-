extends Node
const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const History = preload("res://prototypes/objetos_adaptador/history_bridge.gd")
const Channel = preload("res://prototypes/objetos_adaptador/authority_channel.gd")
const NetworkBridge = preload("res://prototypes/objetos_adaptador/scene_network_bridge.gd")
const ACTOR = preload("res://scenes/actor/actor.tscn")
const FINAL_TICK := 80
var role := "host"
var mode := "net_plain"
var port := 29453
var result_path := ""
var trace_path := ""
var checks: Array = []
var trace: Array = []
var done := false
var running := false
var peer_id := 0
var clock: SimClock
var actor: ActorBody
var tuning: ActorTuning
var sync: NetSync
var channel
var adapter
var history
var network
var prediction := ClientPrediction.new()
var local_input: ActorInput
var requests := {}
var ledger := {}
var acks: Array = []
var effects: Array = []
var confirmations: Array = []
var rejected_authorities: Array = []
var release_requested := -1
var release_applied := -1
var final_hash := ""
var midpoint_requested := false
var midpoint_checked := false
var midpoint_tick := -1
var midpoint_checkpoint := -1
var host_hashes := {}
var pending_midpoint := {}
var started := Time.get_ticks_msec()

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		elif arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
		elif arg.begins_with("--trace="): trace_path = arg.trim_prefix("--trace=")
	check("extension", ClassDB.class_exists("SahurObjectWorld"))
	sync = NetSync.new(); sync.name = "ActorSync"; add_child(sync)
	channel = Channel.new(); channel.name = "ObjectAuthority"; add_child(channel)
	var peer := ENetMultiplayerPeer.new()
	if role == "host":
		check("listen", peer.create_server(port, 1, 2) == OK)
		multiplayer.peer_connected.connect(setup)
	else:
		check("connect", peer.create_client("127.0.0.1", port, 2) == OK)
		multiplayer.connected_to_server.connect(func():
			setup(multiplayer.get_unique_id())
			_client_ready.rpc_id(1))
	multiplayer.multiplayer_peer = peer

func setup(client_id: int) -> void:
	peer_id = client_id
	SimClock.clear_world_slow()
	tuning = ActorTuning.new(); add_child(tuning)
	var actors := Node3D.new(); add_child(actors)
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(12, 0.2, 12)
	shape.shape = box; floor_body.add_child(shape); add_child(floor_body); floor_body.position.y = -0.1
	actor = ACTOR.instantiate(); actor.owner_peer_id = client_id
	actor.state.position = Vector3(0, 0.02, 1.5); actors.add_child(actor)
	clock = SimClock.new(); clock.actors_root = actors; clock.tuning = tuning
	clock.paused = true; clock.input_provider = provide; add_child(clock); sync.clock = clock
	adapter = Adapter.new(); add_child(adapter)
	check("adapter_start", adapter.start(clock, actor, tuning, make_world, 2, 1, 1, 13, 1))
	check("bound_enet_channel", channel.start(adapter.authority_scope(), client_id if role == "host" else 1))
	if role == "host":
		channel.action_requested.connect(receive_action)
		sender_guards()
	else:
		history = History.new(); add_child(history)
		check("real_history_start", history.start(adapter, prediction, step_actor))
		history.effect_ready.connect(func(id: int, kind: String): effects.append([id, kind]))
		history.action_confirmed.connect(func(id: int, kind: String, r: int, a: int): confirmations.append([id, kind, r, a]))
		network = NetworkBridge.new(); add_child(network)
		check("scene_network_start", network.start(history, sync, channel, func(_id, _tick, _state): pass, func(_id, _tick, _p, _v): pass))
		network.object_authority_rejected.connect(func(reason: String): rejected_authorities.append(reason))
		network.object_authority_applied.connect(on_authority)
		transport_guards()
	clock.tick_started.connect(before_tick)
	clock.tick_finished.connect(after_tick)

@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id: return
	_go.rpc_id(peer_id)
	await get_tree().create_timer(0.12, true, false, true).timeout
	running = true; clock.paused = false

@rpc("authority", "call_remote", "reliable")
func _go() -> void:
	running = true; clock.paused = false

func make_world():
	var w = ClassDB.instantiate("SahurObjectWorld")
	w.add_box(1, 1, Vector3(12, 0.2, 12), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)))
	w.add_box(2, 1, Vector3(0.5, 0.4, 0.5), 2.0, Transform3D(Basis.IDENTITY, Vector3(0, 0.7, -0.3)))
	w.add_box(3, 1, Vector3(0.4, 0.4, 0.4), 1.0, Transform3D(Basis.IDENTITY, Vector3(0.4, 0.2, -0.7)))
	w.seal_topology(1)
	return w

func before_tick(tick: int) -> void:
	if role == "client":
		network.before_actor_tick(tick)
		if tick == 18: actor.state.position.x += 0.12; actor.apply_state(actor.state)
	else:
		if mode == "net_time" and tick == 18: SimClock.add_world_slow(18, 34, 0.5)
		if mode == "net_time" and tick == 26: sync.send_world_slow(18, 34, 500, peer_id)

func provide(_who: ActorBody, tick: int) -> ActorInput:
	var input: ActorInput
	if role == "host":
		input = sync.input_for(peer_id, tick)
		if input == null: input = ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
		if input.hold.is_empty(): input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion.IDENTITY)
		if requests.has(tick):
			var a: Dictionary = requests[tick]
			check("host_apply_action_%d" % a.id, adapter.queue_action(tick, a.id, a.kind, a.anchor, a.impulse))
			acks.append({"id": a.id, "kind": a.kind, "requested_tick": a.tick, "applied_tick": tick})
			if a.kind == "release": release_applied = tick; release_requested = a.tick
			requests.erase(tick)
		check("host_capture_%d" % tick, adapter.capture(input))
	else:
		var buttons := ActorInput.BUTTON_CROUCH if tick >= 12 and tick < 17 else 0
		input = ActorInput.make(tick, Vector2(0.3, 0.1), float(tick) * 0.004, buttons, 0)
		input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion(Vector3.UP, float(tick) * 0.01))
		if tick == 3: submit_action(tick, 1, "grab", Vector3(0.05, 0, 0), Vector3.ZERO)
		if tick >= 38 and release_requested < 0 and adapter.ready_for_input:
			release_requested = tick
			submit_action(tick, 2, "release", Vector3.ZERO, Vector3(1.5, 2, -1))
		check("client_capture_%d" % tick, history.capture_input(input))
		local_input = input
	return input

func submit_action(tick: int, id: int, kind: String, anchor: Vector3, impulse: Vector3) -> void:
	var a := {"id": id, "tick": tick, "kind": kind, "anchor": anchor, "impulse": impulse}
	check("predicted_action_%d" % id, history.queue_action(tick, id, kind, anchor, impulse).status == "queued")
	if kind == "release":
		# Deliberately arrives AFTER the requested physical tick at the host.
		await get_tree().create_timer(0.25, true, false, true).timeout
	check("send_action_%d" % id, channel.request_action(a))
	check("resend_action_%d" % id, channel.request_action(a))

func receive_action(a: Dictionary) -> void:
	# Fixture grant: this connection owns exactly this object/hand. No inventory.
	if a.tick < clock.tick - 120 or a.tick > clock.tick + 120: return
	if a.id not in [1, 2] or (a.id == 1 and a.kind != "grab") or (a.id == 2 and a.kind != "release"): return
	if ledger.has(a.id):
		check("host_duplicate_request_%d" % a.id, ledger[a.id] == a)
		return
	if a.id == 2 and not ledger.has(1): return
	var applied := maxi(a.tick, clock.tick + 1)
	if requests.has(applied): return
	ledger[a.id] = a.duplicate(true); requests[applied] = a

func step_actor(input: ActorInput) -> void:
	ActorMotor.step(actor, actor.state, input, tuning, SimClock.world_dt(input.tick))

func after_tick(tick: int) -> void:
	if role == "host":
		host_hashes[tick] = state_hash()
		answer_midpoint()
		sync.send_snapshot(tick, [actor], [])
		if tick % 4 == 0 or tick == FINAL_TICK: publish()
	else:
		prediction.record(tick, local_input, actor.state)
		sync.send_ticks(prediction.recent(NetSync.INPUT_REDUNDANCY), 0.0)
	trace.append({"tick": tick, "native_tick": adapter.world.get_tick(), "ready": adapter.ready_for_input,
		"native_sha": state_hash(), "actor_hex": actor.state.to_bytes().hex_encode(), "channel": channel.stats()})
	if tick == FINAL_TICK:
		clock.paused = true
		if role == "host":
			final_hash = state_hash()
			_final_reference.rpc_id(peer_id, final_hash, release_requested, release_applied)

func publish() -> void:
	var p: Dictionary = adapter.authority_scope()
	p.version = 1; p.revision = int(clock.tick / 4); p.tick = clock.tick
	p.snapshot = adapter.world.snapshot_trusted(); p.acks = acks.duplicate(true)
	check("publish_%d" % clock.tick, channel.publish(p))

@rpc("authority", "call_remote", "reliable")
func _final_reference(hash_value: String, requested: int, applied: int) -> void:
	final_hash = hash_value; release_applied = applied
	check("release_was_late", requested == release_requested and applied > requested)

func on_authority(checkpoint: int, _revision: int) -> void:
	if midpoint_requested or clock.tick <= checkpoint or clock.tick >= FINAL_TICK: return
	if confirmations.filter(func(a): return a[0] == 2).is_empty(): return
	midpoint_requested = true; midpoint_tick = clock.tick; midpoint_checkpoint = checkpoint
	_compare_midpoint.rpc_id(1, clock.tick, checkpoint, state_hash())

@rpc("any_peer", "call_remote", "reliable")
func _compare_midpoint(tick: int, checkpoint: int, expected: String) -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id or tick <= checkpoint \
		or tick > FINAL_TICK or not pending_midpoint.is_empty(): return
	pending_midpoint = {"tick": tick, "checkpoint": checkpoint, "expected": expected}
	answer_midpoint()

func answer_midpoint() -> void:
	if pending_midpoint.is_empty() or not host_hashes.has(pending_midpoint.tick): return
	var ok: bool = host_hashes[pending_midpoint.tick] == pending_midpoint.expected
	check("host_equals_replayed_client_before_final", ok)
	_midpoint_result.rpc_id(peer_id, ok)
	pending_midpoint.clear()

@rpc("authority", "call_remote", "reliable")
func _midpoint_result(ok: bool) -> void:
	midpoint_checked = true
	check("same_tick_equal_after_positive_network_replay", ok and midpoint_tick > midpoint_checkpoint)

func _process(_dt: float) -> void:
	if done: return
	if Time.get_ticks_msec() - started > 6500:
		check("internal_deadline", false); finish(); return
	if role != "client" or not running: return
	if clock.paused: network.after_actor_tick()
	if clock.tick == FINAL_TICK and adapter.last_authority().tick == FINAL_TICK and not final_hash.is_empty() and midpoint_checked:
		check("exact_host_client_same_tick", state_hash() == final_hash and adapter.world.get_tick() == FINAL_TICK)
		check("real_netsync_snapshots", sync.snapshots_received > 0 and network.own_states_received > 0)
		check("real_actor_reconciliation", prediction.corrections > 0 and history.replay_callbacks > 0)
		check("native_authorities_applied", network.authorities_applied > 0)
		check("effects_unique", effects == [[1, "grab"], [2, "release"]])
		check("confirmations_unique", confirmations.size() == 2)
		if mode == "net_time": check("real_world_time_announcement", network.slow_announcements == 1)
		check("bounded_wire", channel.stats().max_wire_bytes <= Channel.HEADER_BYTES + Channel.CHUNK_BYTES)
		_finished.rpc_id(1)
		finish()

@rpc("any_peer", "call_remote", "reliable")
func _finished() -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id: return
	check("release_ledger_once", ledger.size() == 2 and acks.size() == 2 and release_applied > release_requested)
	check("bounded_sender_wire", channel.max_wire_bytes <= 1012 and channel.sent_chunks > 0 and channel.transfer_acks > 0)
	finish()

func state_hash() -> String:
	return Channel.digest(var_to_bytes(adapter.world.samples())).hex_encode()

func chunks(payload: PackedByteArray, id: int, connection: int = 13) -> Array:
	var out: Array = []; var count := ceili(float(payload.size()) / Channel.CHUNK_BYTES)
	for i in count:
		var b := StreamPeerBuffer.new()
		b.put_u32(Channel.MAGIC); b.put_u32(connection); b.put_u32(id); b.put_u32(payload.size())
		b.put_u16(i); b.put_u16(count); b.put_data(Channel.digest(payload))
		b.put_data(payload.slice(i * Channel.CHUNK_BYTES, mini((i + 1) * Channel.CHUNK_BYTES, payload.size())))
		out.append(b.data_array)
	return out

func transport_guards() -> void:
	var unit = Channel.new(); add_child(unit)
	check("guard_live_binding", unit.start(adapter.authority_scope()))
	var p: Dictionary = adapter.authority_scope(); p.version = 1; p.revision = 1; p.tick = 0; p.acks = []
	var opaque := PackedByteArray(); opaque.resize(4096); opaque.fill(7)
	p.snapshot = opaque # Transport-only fixture; NEVER passed to the native decoder.
	var data := Channel.encode_packet(p, adapter.authority_scope())
	var parts := chunks(data, 1)
	check("wrong_sender_before_allocation", not unit.accept_host_chunk(17, parts[0]) and unit.stats().rx_bytes == 0)
	check("short_chunk", not unit.accept_host_chunk(1, PackedByteArray([0])) and unit.stats().rx_bytes == 0)
	check("old_connection", not unit.accept_host_chunk(1, chunks(data, 1, 12)[0]) and unit.stats().rx_bytes == 0)
	var oversized: PackedByteArray = parts[0].duplicate(); oversized.encode_u32(12, Channel.MAX_BYTES + 1)
	check("oversize_before_allocation", not unit.accept_host_chunk(1, oversized) and unit.stats().rx_bytes == 0)
	check("first_fragment", unit.accept_host_chunk(1, parts[-1]) and unit.take_packet().is_empty())
	check("fragment_retry", unit.accept_host_chunk(1, parts[-1]))
	for i in range(parts.size() - 2, -1, -1): check("out_of_order_%d" % i, unit.accept_host_chunk(1, parts[i]))
	check("complete_transport_only", unit.take_packet().get("snapshot") == opaque and unit.stats().rx_bytes == 0)
	check("stale_transfer", not unit.accept_host_chunk(1, parts[0]))
	parts = chunks(data, 2); unit.accept_host_chunk(1, parts[0])
	var conflict: PackedByteArray = parts[0].duplicate(); conflict[-1] ^= 1
	check("conflicting_retry_drops_transfer", not unit.accept_host_chunk(1, conflict) and unit.stats().rx_bytes == 0)
	parts = chunks(data, 3); unit.accept_host_chunk(1, parts[0]); unit._rx.started -= Channel.TIMEOUT_MS + 1; unit._process(0.0)
	check("transfer_timeout", unit.stats().rx_bytes == 0 and not unit.accept_host_chunk(1, parts[1]))
	parts = chunks(data, 4); parts[-1][-1] ^= 1
	for part in parts: unit.accept_host_chunk(1, part)
	check("digest_rejection", unit.take_packet().is_empty() and unit.last_error == "transfer_digest")
	var wrong := p.duplicate(true); wrong.context = 2
	check("wrong_scope_encode", Channel.encode_packet(wrong, adapter.authority_scope()).is_empty())
	var bad := data.duplicate(); bad.encode_u32(5, 2) # context inside serialized scope
	for part in chunks(bad, 5): unit.accept_host_chunk(1, part)
	check("wrong_scope_decode", unit.take_packet().is_empty() and unit.last_error == "packet_format_or_scope")
	parts = chunks(data, 6); unit.accept_host_chunk(1, parts[0]); unit.stop()
	check("stop_clears_buffers", unit.stats().rx_bytes == 0 and unit.take_packet().is_empty() and not unit.accept_host_chunk(1, parts[1]))
	check("stopped_binding_not_reusable", not unit.start(adapter.authority_scope()))
	unit.queue_free()

func sender_guards() -> void:
	var unit = Channel.new(); add_child(unit); unit.set_process(false)
	check("sender_guard_binding", unit.start(adapter.authority_scope(), peer_id))
	var p: Dictionary = adapter.authority_scope(); p.version = 1; p.revision = 1; p.tick = 0; p.acks = []
	var opaque := PackedByteArray(); opaque.resize(4096); opaque.fill(11); p.snapshot = opaque
	check("sender_accepts_packet", unit.publish(p))
	# Freeze a transfer awaiting its REAL remote ACK. This deterministic seam must
	# not send an RPC from the extra test node; production ACKs run in the pair.
	unit._tx = {"id": 1, "data": unit._next_packet, "index": 5, "awaiting_ack": true,
		"started": Time.get_ticks_msec(), "digest": Channel.digest(unit._next_packet)}
	unit._next_packet = PackedByteArray()
	for i in range(2, 52):
		p.revision = i; check("coalesce_publish_%d" % i, unit.publish(p))
	unit._process(0.0)
	check("one_transfer_waits_for_ack", unit._tx.id == 1 and unit._tx.awaiting_ack and unit.sent_chunks == 0)
	check("only_latest_pending", Channel.decode_packet(unit._next_packet, adapter.authority_scope()).revision == 51)
	check("bounded_pending_storage", unit.stats().tx_bytes <= 2 * Channel.MAX_BYTES)
	check("duplicate_revision_rejected", not unit.publish(p))
	p.revision = 52; p.tick = 3; check("new_authority_tick", unit.publish(p))
	p.revision = 53; p.tick = 2; check("older_tick_rejected", not unit.publish(p))
	unit._tx.started -= Channel.TIMEOUT_MS + 1; unit._process(0.0)
	check("send_timeout_stops_binding", not unit.stats().bound and unit.stats().tx_bytes == 0 and unit.last_error == "send_timeout")
	unit.queue_free()

func check(id: String, passed: bool) -> void:
	checks.append({"id": id, "passed": passed})
	if not passed: push_error("CHECK_FAILED: " + id)

func finish() -> void:
	if done: return
	done = true
	var failures := checks.filter(func(c): return not c.passed).size()
	var result := {"role": role, "mode": mode, "status": "PASSED" if failures == 0 else "FAILED", "checks": checks,
		"failures": failures, "transport": "real_enet_two_process", "native_sha": state_hash() if adapter != null else "",
		"channel": channel.stats(), "release_requested": release_requested, "release_applied": release_applied,
		"own_states": network.own_states_received if network != null else 0,
		"actor_corrections": prediction.corrections, "replay_callbacks": history.replay_callbacks if history != null else 0,
		"effects": effects, "confirmations": confirmations, "rejected_authorities": rejected_authorities}
	result.midpoint_tick = midpoint_tick; result.midpoint_checkpoint = midpoint_checkpoint; result.midpoint_checked = midpoint_checked
	if not result_path.is_empty(): FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(result))
	if not trace_path.is_empty(): FileAccess.open(trace_path, FileAccess.WRITE).store_string(JSON.stringify(trace))
	print(JSON.stringify(result))
	# Allow the result RPC to leave before closing ENet.
	await get_tree().create_timer(0.08, true, false, true).timeout
	multiplayer.multiplayer_peer.close()
	get_tree().quit(0 if failures == 0 else 1)
