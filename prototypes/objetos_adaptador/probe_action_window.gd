extends Node
const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const History = preload("res://prototypes/objetos_adaptador/history_bridge.gd")
const ACTOR = preload("res://scenes/actor/actor.tscn")
const Channel = preload("res://prototypes/objetos_adaptador/authority_channel.gd")
var result_path := ""
var checks: Array = []
var actor: ActorBody
var clock: SimClock
var tuning: ActorTuning
var adapter
var history
var effects := 0
var confirms := 0
var max_active := 0
var max_known := 0
var revision := 0
var checkpoint := PackedByteArray()
var expired := {}
var confirmed_ids := {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
	SimClock.clear_world_slow()
	tuning = ActorTuning.new(); add_child(tuning)
	var actors := Node3D.new(); add_child(actors)
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(12, 0.2, 12)
	shape.shape = box; floor_body.add_child(shape); add_child(floor_body); floor_body.position.y = -0.1
	actor = ACTOR.instantiate(); actor.owner_peer_id = 1; actor.state.position = Vector3(0, 0.02, 1.5); actors.add_child(actor)
	clock = SimClock.new(); clock.actors_root = actors; clock.tuning = tuning
	clock.paused = true; clock.input_provider = provide; add_child(clock); clock.set_physics_process(false)
	adapter = Adapter.new(); add_child(adapter)
	check("adapter_start", adapter.start(clock, actor, tuning, make_world, 2, 1, 1))
	history = History.new(); add_child(history)
	check("history_start", history.start(adapter, ClientPrediction.new(), step_actor))
	history.effect_ready.connect(func(_id: int, _kind: String): effects += 1)
	history.action_confirmed.connect(func(_id: int, _kind: String, _r: int, _a: int): confirms += 1)
	history.action_confirmed.connect(func(id: int, _kind: String, _r: int, _a: int): confirmed_ids[id] = true)
	history.action_expired.connect(on_expired)
	clock.tick_finished.connect(after_tick)
	# Jolt must have installed the actor/static shapes before its first queries.
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Deliberately fast single-thread fixture: 900 actual SimClock/ActorMotor/native
	# steps, not a throughput benchmark. No claim about 900 render/physics frames.
	for _i in 900:
		clock._run_tick()
		if checks.any(func(c): return not c.passed): break
	check("900_actions_450_cycles", effects == 900 and adapter.ready_for_input)
	check("ack_at_120_confirmed_without_expiry", confirmed_ids.has(1360) and not expired.has(1360))
	check("all_18_unconfirmed_actions_expired_once", expired.size() == 18)
	check("action_memory_bounded", max_active <= 122 and max_known <= 122 and history._confirmed.size() <= 122)
	if adapter.ready_for_input and clock.tick == 900:
		var reference = make_world(); reference.restore_trusted(adapter.world.snapshot_trusted())
		check("queue_before_suspension", history.queue_action(901, 1802, "grab").status == "queued")
		adapter.invalidate_history_from(899, "actor")
		for _i in 140:
			clock._run_tick(); reference.step(SimClock.TICK_DT)
		check("retirement_continues_while_suspended", adapter.action_stats().active == 0 and history._known_actions.is_empty())
		var before_confirms := confirms
		check("current_authority_recovers_long_suspension", history.apply_authority_trusted(envelope(1040, reference.snapshot_trusted(), [ack(699)])))
		check("retired_unconfirmed_ack_has_no_late_callback", confirms == before_confirms and effects == 900)
		check("long_suspension_exact", var_to_bytes(adapter.world.samples()) == var_to_bytes(reference.samples()))
		check("late_ack_never_confirms_expired_action", not confirmed_ids.has(1398) and expired.size() == 19)
		check("unexecuted_action_expires_during_suspension", expired.has(1802) and not confirmed_ids.has(1802) and effects == 900)
	var failures := checks.filter(func(c): return not c.passed).size()
	var result := {"mode": "action_window", "status": "PASSED" if failures == 0 else "FAILED", "failures": failures,
		"checks": checks, "actions": 900, "effects": effects, "confirmations_emitted": confirms,
		"max_active": max_active, "max_known": max_known, "adapter_actions": adapter.action_stats(),
		"history": history.stats(), "scope": "900_manual_real_clock_steps_not_wall_time_performance"}
	result.adapter_error = adapter.last_error; result.history_error = history.last_error
	result.native_tick = adapter.world.get_tick(); result.clock_tick = clock.tick
	FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(result))
	print(JSON.stringify(result))
	get_tree().quit(0 if failures == 0 else 1)

func make_world():
	var w = ClassDB.instantiate("SahurObjectWorld")
	w.add_box(1, 1, Vector3(12, 0.2, 12), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)))
	w.add_box(2, 1, Vector3(0.5, 0.4, 0.5), 2.0, Transform3D(Basis.IDENTITY, Vector3(0, 0.7, -0.3)))
	w.seal_topology(1)
	return w

func provide(_who: ActorBody, tick: int) -> ActorInput:
	var input := ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion.IDENTITY)
	var kind := "grab" if tick % 2 == 1 else "release"
	if tick <= 900: check("queue_%d" % tick, history.queue_action(tick, tick * 2, kind).status == "queued")
	check("capture_%d" % tick, history.capture_input(input))
	return input

func step_actor(input: ActorInput) -> void:
	ActorMotor.step(actor, actor.state, input, tuning, SimClock.world_dt(input.tick))

func envelope(tick: int, snapshot: PackedByteArray, acks: Array) -> Dictionary:
	revision += 1
	var p: Dictionary = adapter.authority_scope()
	p.version = 1; p.revision = revision; p.tick = tick; p.snapshot = snapshot; p.acks = acks
	return p

func ack(tick: int) -> Dictionary:
	return {"id": tick * 2, "kind": "grab" if tick % 2 == 1 else "release", "requested_tick": tick, "applied_tick": tick}

func after_tick(tick: int) -> void:
	if tick > 900:
		check("suspended_native_frozen_%d" % tick, not adapter.ready_for_input and adapter.world.get_tick() == 900)
		return
	if not adapter.ready_for_input:
		var frame: Dictionary = history.recorded_frame(tick)
		var s := StreamPeerBuffer.new(); s.data_array = frame.input
		print("DIAGNOSTIC_GOAL=" + var_to_str(InvHoldMotion.target_of(frame.eyes, ActorInput.read_from(s), tuning)))
		check("native_ready_%d_%s" % [tick, adapter.last_error], false)
		return
	if tick == 690: checkpoint = adapter.world.snapshot_trusted()
	if tick <= 679 or tick >= 700:
		var conf: Array = [ack(tick)]
		if tick == 800: conf.append(ack(680)) # last eligible tick, d=120
		if tick > 130: conf.append(ack(1)) # retired ACK must not grow sets/re-emit
		var before := effects
		var p: Dictionary
		if tick == 700:
			var expected: PackedByteArray = var_to_bytes(adapter.world.samples())
			adapter.invalidate_history_from(691, "actor")
			p = envelope(690, checkpoint, [ack(690)])
			check("recovery_after_retirement", history.apply_authority_trusted(p))
			check("positive_action_replay_exact", var_to_bytes(adapter.world.samples()) == expected and effects == before)
		p = envelope(tick, adapter.world.snapshot_trusted(), conf)
		check("confirm_%d" % tick, history.apply_authority_trusted(p) and effects == before)
	if tick in [260, 600, 900]:
		var before: PackedByteArray = adapter.world.snapshot_trusted()
		var status: Dictionary = history.queue_action(1, 2, "grab")
		check("retired_retry_%d" % tick, status.status == "rejected" and status.reason == "retired_action")
		status = history.queue_action(tick + 1, tick * 2 - 1, "grab")
		check("unseen_older_id_%d" % tick, status.status == "rejected" and status.reason == "nonmonotonic_action_id")
		check("old_retry_atomic_%d" % tick, adapter.world.snapshot_trusted() == before)
	max_active = maxi(max_active, adapter.action_stats().active)
	max_known = maxi(max_known, history._known_actions.size())
	check("bounded_journals_%d" % tick, history.stats().ticks <= 120 and history._effects.size() <= 122)

func check(id: String, passed: bool) -> void:
	checks.append({"id": id, "passed": passed})
	if not passed: push_error("CHECK_FAILED: " + id)

func on_expired(id: int, kind: String, requested_tick: int) -> void:
	check("expiry_once_%d" % id, not expired.has(id))
	check("expiry_unconfirmed_%d" % id, not confirmed_ids.has(id))
	check("expiry_exact_boundary_%d" % id, clock.tick == requested_tick + 121)
	check("expiry_original_identity_%d" % id, id == requested_tick * 2 and kind == ("grab" if requested_tick % 2 else "release"))
	check("expiry_cleanup_before_callback_%d" % id, not history._known_actions.has(id) and adapter.is_retired_action(id))
	expired[id] = true
