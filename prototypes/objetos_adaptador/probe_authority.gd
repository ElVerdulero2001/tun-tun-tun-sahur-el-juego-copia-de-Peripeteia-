extends "res://prototypes/objetos_adaptador/probe.gd"
## Local construction scenarios for the checked authority/recovery API.
## No network transport and no modifications to production actor/clock scripts.
var owned_frames := {}
var owned_bytes := {}
var commands := {}
var factory_calls := 0
var corrected_frames: Array = []
var generation_before := 0

func make_world():
	factory_calls += 1
	return super.make_world()

func provide_input(_who: ActorBody, at_tick: int) -> ActorInput:
	provider_calls += 1
	var movement := Vector2.ZERO if mode == "api_time" and at_tick >= 20 else Vector2(0.25, 0.05)
	var input := ActorInput.make(at_tick, movement, float(at_tick) * 0.004, 0, 0)
	input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion(Vector3.UP, float(at_tick) * 0.015))
	var b := StreamPeerBuffer.new(); input.write_to(b)
	owned_bytes[at_tick] = b.data_array.duplicate()
	if adapter.ready_for_input:
		if at_tick in [3, 30]:
			var action := {"id": 1 if at_tick == 3 else 2, "kind": "grab" if at_tick == 3 else "release",
				"tick": at_tick, "anchor": Vector3(0.05, 0, 0) if at_tick == 3 else Vector3.ZERO,
				"impulse": Vector3.ZERO if at_tick == 3 else Vector3(1.5, 2, -1)}
			commands[at_tick] = action
			check("queue_%d" % at_tick, adapter.queue_action(at_tick, action.id, action.kind, action.anchor, action.impulse))
		check("capture_%d" % at_tick, adapter.capture(input))
	return input

func reference_step(w, f: Dictionary, delayed := false) -> void:
	var b := StreamPeerBuffer.new(); b.data_array = f.input
	var input := ActorInput.read_from(b)
	var goal := InvHoldMotion.target_of(f.eyes, input, tuning)
	if f.action.get("kind", "") == "grab": check("ref_grab", w.begin_hold(2, 1, f.action.anchor, goal))
	if w.sample(2, 1).held: check("ref_goal", w.set_goal(2, 1, goal))
	if f.action.get("kind", "") == "release" and not delayed:
		check("ref_release", w.release_body(2, 1, f.action.impulse))
	if delayed and f.tick == 34: check("ref_late_release", w.release_body(2, 1, commands[30].impulse))
	check("ref_step", w.step(f.dt))

func packet(at_tick: int, revision: int, acks: Array = []) -> Dictionary:
	var p: Dictionary = adapter.authority_scope()
	p.merge({"version": 1, "revision": revision, "tick": at_tick,
		"snapshot": checkpoints[at_tick].duplicate(), "acks": acks.duplicate(true)})
	return p

func ack(id: int, requested: int, applied: int, kind: String) -> Dictionary:
	return {"id": id, "requested_tick": requested, "applied_tick": applied, "kind": kind}

func after_tick(t: int) -> void:
	if done: return
	var frame := {"tick": t, "dt": SimClock.world_dt(t),
		"eyes": InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state)),
		"input": owned_bytes[t], "action": commands.get(t, {}).duplicate(true)}
	owned_frames[t] = frame.duplicate(true)
	reference_step(reference, frame, mode == "api_authority")
	if t == 12: check("authority_only_neighbor_impulse", reference.apply_impulse(3, 1, Vector3(0.8, 0, 0)))
	if t in [15, 24, 34]: checkpoints[t] = reference.snapshot_trusted()
	trace.append({"tick": t, "dt": frame.dt, "native_tick": adapter.world.get_tick(),
		"native_sha": hash_state(adapter.world), "reference_sha": hash_state(reference),
		"ready": adapter.ready_for_input, "generation": adapter.recovery_generation()})
	if mode in ["api_authority", "api_scope"]:
		if t == 20:
			var p := packet(15, 1, [ack(1, 3, 3, "grab")])
			if mode == "api_scope": check_envelopes(p)
			check("negative_authority_differs", hash_state(adapter.world) != hash_state(reference))
			check("apply_scoped_authority", adapter.apply_authority_trusted(p))
			check("authority_exact", hash_state(adapter.world) == hash_state(reference))
		if t == 22:
			check("new_revision_same_tick", adapter.apply_authority_trusted(packet(15, 2)))
			var before := hash_state(adapter.world)
			check("duplicate_revision_ignored", not adapter.apply_authority_trusted(packet(15, 2)) and adapter.last_error == "duplicate_or_stale_revision")
			check("revision_does_not_change_world", hash_state(adapter.world) == before and adapter.last_authority().revision == 2)
		if t == 33 and mode == "api_authority": check("late_release_diverges", hash_state(adapter.world) != hash_state(reference))
		if t == 37:
			var p := packet(34, 3, [ack(2, 30, 34 if mode == "api_authority" else 30, "release")])
			var invalid := p.duplicate(true); invalid.acks[0].applied_tick = 38
			check("post_action_checkpoint_required", not adapter.apply_authority_trusted(invalid) and adapter.last_error == "invalid_action_confirmation")
			check("rejected_ack_does_not_consume_revision", adapter.last_authority().revision == 2)
			check("confirm_release_after_application", adapter.apply_authority_trusted(p))
			check("late_release_exact", hash_state(adapter.world) == hash_state(reference))
	if mode == "api_time" and t == 32: correct_time()
	if mode == "api_recovery":
		if t == 20: begin_actor_recovery()
		if t == 21:
			var old_generation: int = adapter.recovery_generation()
			check("accept_new_history_revision", adapter.invalidate_history_from(16, "actor"))
			check("new_change_invalidates_inflight_recovery", adapter.recovery_generation() > old_generation)
		if t > 20 and t <= 25: corrected_frames.append(frame.duplicate(true))
		if t == 25:
			var before := hash_state(adapter.world)
			check("world_frozen_while_actor_advances", adapter.world.get_tick() == 20 and clock.tick == 25)
			check("stale_recovery_rejected", not adapter.recover_authority_trusted(packet(15, 1), corrected_frames, generation_before))
			check("incomplete_batch_rejected", not adapter.recover_authority_trusted(packet(15, 1), [], adapter.recovery_generation()))
			check("bad_recovery_keeps_native_world", hash_state(adapter.world) == before and not adapter.ready_for_input)
			var actor_before := [actor.state.position, clock.tick]
			check("recover_after_suspension", adapter.recover_authority_trusted(packet(15, 1), corrected_frames, adapter.recovery_generation()))
			check("recovered_exact", hash_state(adapter.world) == hash_state(reference))
			check("recovery_does_not_move_actor_clock", actor_before == [actor.state.position, clock.tick])
	if t == 60:
		check("resumed_reference_exact", hash_state(adapter.world) == hash_state(reference))
		check("effects_unique_across_recovery", effects == [[1, "grab"], [2, "release"]])
		check("prediction_ready", adapter.ready_for_input)
		if mode in ["api_time", "api_recovery"]: check("recovery_exercised", recoveries.size() == (2 if mode == "api_recovery" else 1))
		finish()

func check_envelopes(good: Dictionary) -> void:
	var before := hash_state(adapter.world)
	for key in ["connection", "context", "uid", "epoch", "hold_session", "revision", "version", "hand_signature", "extra", "acks", "snapshot"]:
		var p := good.duplicate(true)
		if key in ["connection", "context", "uid", "epoch", "hold_session"]: p[key] += 1
		elif key == "revision": p[key] = 0
		elif key == "version": p[key] = 2
		elif key == "hand_signature": p[key] = "wrong"
		elif key == "acks": p[key] = [ack(99, 3, 3, "grab")]
		elif key == "snapshot": p[key] = "not bytes"
		else: p[key] = 1
		var factories := factory_calls
		check("reject_envelope_" + key, not adapter.apply_authority_trusted(p))
		check("reject_before_native_" + key, factory_calls == factories and hash_state(adapter.world) == before and adapter.ready_for_input and adapter.last_authority().revision == 0)

func correct_time() -> void:
	SimClock.add_world_slow(25, 33, 0.25)
	var fresh: Array = []
	var corrected = make_world()
	check("time_reference_checkpoint", corrected.restore_trusted(checkpoints[24]))
	for t in range(25, 33):
		var f: Dictionary = owned_frames[t].duplicate(true)
		check("stationary_actor_validates_time_only_repair_%d" % t, f.eyes == owned_frames[24].eyes)
		f.dt = SimClock.world_dt(t)
		fresh.append(f)
		reference_step(corrected, f)
	var p := packet(24, 1)
	check("old_dt_branch_differs", hash_state(reference) != hash_state(corrected))
	check("retroactive_time_detected", not adapter.apply_authority_trusted(p) and adapter.last_error == "timeline_invalidated:world_time" and not adapter.ready_for_input)
	var before := hash_state(adapter.world)
	var bad := fresh.duplicate(true); bad[0].dt = SimClock.TICK_DT
	check("stale_time_batch_rejected", not adapter.recover_authority_trusted(p, bad, adapter.recovery_generation()))
	check("stale_time_batch_atomic", before == hash_state(adapter.world) and adapter.last_authority().revision == 0)
	check("recover_corrected_time", adapter.recover_authority_trusted(p, fresh, adapter.recovery_generation()))
	check("corrected_time_exact", hash_state(adapter.world) == hash_state(corrected))
	reference = corrected

func begin_actor_recovery() -> void:
	generation_before = adapter.recovery_generation()
	check("accept_actor_history_invalidation", adapter.invalidate_history_from(16, "actor"))
	check("actor_history_invalidated", not adapter.ready_for_input and adapter.recorded_frame(16).is_empty())
	# An injected correction on a flat unobstructed floor: the producer of actor
	# history owns the corrected eyes. The adapter never fabricates this history.
	actor.state.position.x += 0.15; actor.apply_state(actor.state)
	var corrected = make_world(); check("actor_reference_checkpoint", corrected.restore_trusted(checkpoints[15]))
	for t in range(16, 21):
		var f: Dictionary = owned_frames[t].duplicate(true)
		f.eyes += Vector3(0.15, 0, 0)
		corrected_frames.append(f)
		reference_step(corrected, f)
	reference = corrected
