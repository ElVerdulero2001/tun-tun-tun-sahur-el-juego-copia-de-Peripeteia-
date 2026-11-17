extends Node3D
## Construction checks, not Claude's acceptance criteria. Inputs are scripted at
## capture time; the actual actor scene, motor, input codec and clock run unchanged.
const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const ACTOR = preload("res://scenes/actor/actor.tscn")
var mode := "normal"
var result_path := ""
var trace_path := ""
var clock: SimClock
var actor: ActorBody
var tuning: ActorTuning
var adapter
var reference
var checkpoints := {}
var checks: Array = []
var trace: Array = []
var effects: Array = []
var recoveries: Array = []
var done := false
var pause_started := -1
var pause_tick := -1
var provider_calls := 0
var source_inputs := {}
var start_x := 0.0
var started := 0

func _ready() -> void:
	started = Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
		elif arg.begins_with("--trace="): trace_path = arg.trim_prefix("--trace=")
	check("extension_registered", ClassDB.class_exists("SahurObjectWorld"))
	if not ClassDB.class_exists("SahurObjectWorld"): finish(); return
	check("keeps_jolt", ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics")
	tuning = ActorTuning.new(); add_child(tuning)
	var actors := Node3D.new(); add_child(actors)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(12, 0.2, 12)
	shape.shape = box; floor_body.add_child(shape); add_child(floor_body)
	floor_body.position.y = -0.1
	actor = ACTOR.instantiate(); actor.owner_peer_id = 1
	actor.state.position = Vector3(0, 0.02, 1.5)
	actors.add_child(actor)
	start_x = actor.state.position.x
	clock = SimClock.new(); clock.actors_root = actors; clock.tuning = tuning
	clock.input_provider = provide_input
	add_child(clock)
	if mode == "slow": SimClock.add_world_slow(12, 28, 0.35)
	adapter = Adapter.new(); add_child(adapter)
	adapter.action_effect.connect(func(id: int, kind: String): effects.append([id, kind]))
	adapter.recovery_required.connect(func(reason: String): recoveries.append(reason))
	check("bind_actual_actor_clock", adapter.start(clock, actor, tuning, make_world, 2, 1, 1))
	if not adapter.ready_for_input: finish(); return
	reference = make_world()
	clock.tick_finished.connect(after_tick)

func make_world():
	var w = ClassDB.instantiate("SahurObjectWorld")
	w.add_box(1, 1, Vector3(12, 0.2, 12), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)))
	w.add_box(2, 1, Vector3(0.5, 0.4, 0.5), 2.0, Transform3D(Basis.IDENTITY, Vector3(0, 0.7, -0.3)))
	w.add_box(3, 1, Vector3(0.4, 0.4, 0.4), 1.0, Transform3D(Basis.IDENTITY, Vector3(0.4, 0.2, -0.7)))
	w.seal_topology(1)
	return w

func provide_input(who: ActorBody, at_tick: int) -> ActorInput:
	provider_calls += 1
	var input := ActorInput.make(at_tick, Vector2(0.35, 0.1), float(at_tick) * 0.003, 0, 0)
	input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion(Vector3.UP, float(at_tick) * 0.013))
	source_inputs[at_tick] = input
	if adapter.ready_for_input:
		if at_tick == 3:
			check("queue_grab", adapter.queue_action(at_tick, 1, "grab", Vector3(0.05, 0, 0)))
			check("duplicate_grab_suppressed", adapter.queue_action(at_tick, 1, "grab", Vector3(0.05, 0, 0)))
		if at_tick == 30:
			check("queue_throw_from_input", adapter.queue_action(at_tick, 2, "release", Vector3.ZERO,
				input.hold_look() * tuning.throw_impulse))
			check("duplicate_throw_suppressed", adapter.queue_action(at_tick, 2, "release", Vector3.ZERO,
				input.hold_look() * tuning.throw_impulse))
		check("capture_%d" % at_tick, adapter.capture(input))
		var frame_before: int = adapter.capture_calls
		check("captured_once_%d" % at_tick, frame_before == at_tick and who == actor)
	return input

func after_tick(at_tick: int) -> void:
	if done: return
	if not adapter.ready_for_input: return
	var frame: Dictionary = adapter.recorded_frame(at_tick)
	check("same_actor_and_native_tick_%d" % at_tick, adapter.world.get_tick() == clock.tick)
	check("eyes_after_actor_motor_%d" % at_tick,
		frame.eyes == InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state)))
	check("world_dt_%d" % at_tick, frame.dt == SimClock.world_dt(at_tick))
	# Independent straight-line native reference using only frames already captured.
	var stream := StreamPeerBuffer.new(); stream.data_array = frame.input
	var input := ActorInput.read_from(stream)
	var goal := InvHoldMotion.target_of(frame.eyes, input, tuning)
	if at_tick == 3: reference.begin_hold(2, 1, Vector3(0.05, 0, 0), goal)
	if at_tick >= 3 and at_tick <= 30: reference.set_goal(2, 1, goal)
	if at_tick == 30: reference.release_body(2, 1, input.hold_look() * tuning.throw_impulse)
	reference.step(frame.dt)
	if at_tick in [15, 27, 28]: checkpoints[at_tick] = reference.snapshot_trusted()
	trace.append({"tick": at_tick, "dt": frame.dt, "actor": var_to_str(actor.state.position),
		"input_hex": frame.input.hex_encode(), "eyes": var_to_str(frame.eyes),
		"action": var_to_str(frame.action), "native_sha": hash_state(adapter.world), "reference_sha": hash_state(reference)})
	if at_tick == 19:
		check("inject_negative_control", adapter.world.apply_impulse(2, 1, Vector3(12, 6, 0)))
	if at_tick == 23:
		check("negative_control_diverges", hash_state(adapter.world) != hash_state(reference))
	if at_tick == 24:
		# These producer objects have already been used by ActorMotor. Corrupt
		# them now: replay must use owned historical bytes, not mutable references.
		for old_tick in range(16, 25):
			source_inputs[old_tick].hold[2] = 60000
			source_inputs[old_tick].look_yaw = 2.0
		var count := provider_calls
		var effects_before := effects.size()
		var actor_before := [actor.state.position, actor.state.velocity, actor.state.mode, actor.state.stance, clock.tick]
		check("reconcile_recorded_hand_targets", adapter.reconcile_trusted(15, checkpoints[15]))
		check("same_tick_exact_after_replay", hash_state(adapter.world) == hash_state(reference))
		check("no_recapture_or_effect_during_replay", provider_calls == count and effects.size() == effects_before)
		check("actor_and_clock_not_replayed", actor_before == [actor.state.position, actor.state.velocity, actor.state.mode, actor.state.stance, clock.tick])
		var saved: PackedByteArray = adapter.world.snapshot_trusted()
		check("duplicate_authority_ignored", not adapter.reconcile_trusted(15, checkpoints[15]) and adapter.last_error == "duplicate_or_stale_authority")
		check("duplicate_keeps_world", saved == adapter.world.snapshot_trusted())
	if at_tick == 35:
		var effects_before := effects.size()
		check("replay_throw_from_before_action", adapter.reconcile_trusted(27, checkpoints[27]))
		check("throw_replay_same_tick_exact", hash_state(adapter.world) == hash_state(reference))
		check("throw_effect_not_repeated", effects.size() == effects_before and effects == [[1, "grab"], [2, "release"]])
		var release_frame: Dictionary = adapter.recorded_frame(30)
		check("late_duplicate_action_ignored", adapter.queue_action(30, 2, "release", Vector3.ZERO, release_frame.action.impulse))
		check("conflicting_action_id_rejected", not adapter.queue_action(30, 2, "release", Vector3.ZERO, Vector3.ZERO) and adapter.last_error == "action_identity_conflict")
	if at_tick == 36:
		var bad: PackedByteArray = checkpoints[27].duplicate(); bad[bad.size() - 1] ^= 1
		var before := hash_state(adapter.world)
		check("bad_checkpoint_rejected_atomically", not adapter.reconcile_trusted(28, bad) and hash_state(adapter.world) == before and adapter.ready_for_input)
	if at_tick == 38 and mode == "pause":
		clock.paused = true; pause_tick = at_tick; pause_started = Time.get_ticks_usec()
	if (at_tick == 45 and mode in ["resync", "tuning"]) or (at_tick == 60 and mode == "budget"):
		var before := hash_state(adapter.world)
		if mode == "resync":
			clock.hard_resynced.emit()
			check("resync_clears_history", adapter.history_stats().ticks == 0)
		elif mode == "budget":
			check("bounded_replay", not adapter.reconcile_trusted(28, checkpoints[28]) and adapter.last_error == "replay_budget")
		else:
			tuning.hold_max_distance += 0.1
			check("changed_tuning_rejected", not adapter.reconcile_trusted(28, checkpoints[28]) and adapter.last_error == "tuning_changed")
		check("recovery_requested_without_native_change", not adapter.ready_for_input and recoveries.size() == 1 and hash_state(adapter.world) == before)
		finish(); return
	if at_tick == (150 if mode == "history" else 70):
		check("actor_really_moved", absf(actor.state.position.x - start_x) > 0.1)
		check("final_reference_exact", hash_state(adapter.world) == hash_state(reference))
		check("bounded_history", adapter.history_stats().ticks <= adapter.HISTORY_TICKS and adapter.history_stats().bytes <= adapter.HISTORY_BYTES)
		check("both_corrections_replayed", adapter.replayed_steps == 17)
		if mode == "history":
			check("old_frames_evicted", adapter.history_stats().ticks == 120 and adapter.history_stats().oldest == 31 and adapter.recorded_frame(30).is_empty())
		if mode == "slow": check("slow_recorded_once", trace.filter(func(f): return f.dt < SimClock.TICK_DT).size() == 16)
		if mode == "pause": check("pause_exercised", pause_started == -2)
		finish()

func _process(_delta: float) -> void:
	if pause_started > 0 and Time.get_ticks_usec() - pause_started > 100000:
		check("pause_did_not_step_objects", clock.tick == pause_tick and adapter.world.get_tick() == pause_tick and provider_calls == pause_tick)
		clock.paused = false; pause_started = -2
	if not done and Time.get_ticks_usec() - started > 6500000:
		check("internal_deadline", false); finish()

func hash_state(w) -> String:
	return var_to_bytes(w.samples()).hex_encode().sha256_text()

func check(id: String, ok: bool) -> void:
	checks.append({"id": id, "passed": ok})
	if not ok: print("ADAPTER_CHECK_FAILED ", id)

func finish() -> void:
	if done: return
	done = true
	if clock != null: clock.set_physics_process(false)
	var failed := checks.filter(func(c): return not c.passed).size()
	var result := {"status": "PASSED" if failed == 0 else "FAILED", "mode": mode, "checks": checks,
		"failures": failed, "provider_calls": provider_calls, "effects": effects, "recoveries": recoveries,
		"scope": "production_actor_input_motor_clock_scripted_capture_local_native_replay",
		"transport": "none", "seconds": float(Time.get_ticks_usec() - started) / 1000000.0}
	if adapter != null: result["replayed_steps"] = adapter.replayed_steps
	if not result_path.is_empty():
		var file := FileAccess.open(result_path, FileAccess.WRITE); file.store_string(JSON.stringify(result)); file.close()
	if not trace_path.is_empty():
		var file := FileAccess.open(trace_path, FileAccess.WRITE); file.store_string(JSON.stringify(trace)); file.close()
	get_tree().quit(0 if failed == 0 else 2)
