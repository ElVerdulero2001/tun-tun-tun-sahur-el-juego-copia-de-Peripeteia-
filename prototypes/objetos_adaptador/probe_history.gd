extends "res://prototypes/objetos_adaptador/probe_authority.gd"
const History = preload("res://prototypes/objetos_adaptador/history_bridge.gd")
var history
var actor_prediction := ClientPrediction.new()
var actor_snapshots := {}
var replay_frames := {}
var user_inputs := {}
var unified_effects: Array = []
var confirmations: Array = []
var history_requests: Array = []
var frozen_tick := -1
var old_claim := PackedByteArray()

func _ready() -> void:
	super._ready()
	if done: return
	clock.tick_finished.disconnect(after_tick)
	history = History.new(); add_child(history)
	check("bind_real_client_prediction", history.start(adapter, actor_prediction, step_actor))
	check("production_prediction_script", actor_prediction.get_script().resource_path == "res://scripts/net/client_prediction.gd")
	history.effect_ready.connect(func(id: int, kind: String): unified_effects.append([id, kind]))
	history.action_confirmed.connect(func(id: int, kind: String, r: int, a: int): confirmations.append([id, kind, r, a]))
	history.authority_needed.connect(func(reason: String): history_requests.append(reason))
	clock.tick_started.connect(before_tick)
	clock.tick_finished.connect(after_tick)

func provide_input(_who: ActorBody, tick: int) -> ActorInput:
	provider_calls += 1
	var buttons := ActorInput.BUTTON_CROUCH if tick >= 28 and tick < 32 else 0
	var input := ActorInput.make(tick, Vector2(0.3, 0.15), float(tick) * 0.004, buttons, 0)
	input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion(Vector3.UP, float(tick) * 0.01))
	input.held_claim.resize(41); input.held_claim.fill(19) # output must not enter the intent diary
	user_inputs[tick] = input
	if tick == 3: submit(tick, 1, "grab", Vector3(0.05, 0, 0), Vector3.ZERO)
	if tick == 42 and mode != "hist_effect": submit(tick, 2, "release", Vector3.ZERO, Vector3(1.5, 2, -1))
	check("history_capture_%d" % tick, history.capture_input(input))
	check("claim_output_not_mutated_%d" % tick, input.held_claim.size() == 41)
	if tick == 10: check("identical_capture_retry", history.capture_input(input))
	return input

func submit(tick: int, id: int, kind: String, anchor: Vector3, impulse: Vector3) -> void:
	var outcome: Dictionary = history.queue_action(tick, id, kind, anchor, impulse)
	check("queue_history_%d" % id, outcome.status == "queued")
	if outcome.status == "queued": commands[tick] = {"id": id, "kind": kind, "tick": tick, "anchor": anchor, "impulse": impulse}

func intent(input: ActorInput) -> PackedByteArray:
	var b := StreamPeerBuffer.new(); input.write_to(b)
	b.seek(0); var copy := ActorInput.read_from(b)
	copy.held_claim = PackedByteArray()
	b = StreamPeerBuffer.new(); copy.write_to(b)
	return b.data_array

func actual_frame(input: ActorInput) -> Dictionary:
	return {"tick": input.tick, "input": intent(input), "dt": SimClock.world_dt(input.tick),
		"eyes": InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state)), "action": commands.get(input.tick, {}).duplicate(true)}

func step_actor(input: ActorInput) -> void:
	ActorMotor.step(actor, actor.state, input, tuning, SimClock.world_dt(input.tick))
	replay_frames[input.tick] = actual_frame(input)
	actor_snapshots[input.tick] = actor.state.to_bytes()

func before_tick(tick: int) -> void:
	if mode == "hist_guards" and tick == 12:
		var before := actor.state.to_bytes()
		var matches := actor_prediction.matches
		var calls: Array = []
		actor_prediction.reconcile(actor, 5, actor_snapshots[5], 4, tick, func(input: ActorInput): calls.append(input.tick))
		check("default_matching_fast_path_unchanged", actor_prediction.matches == matches + 1 and calls.is_empty() and actor.state.to_bytes() == before)
	if mode in ["hist_actor", "hist_guards"] and tick == 26: correct_actor(15, tick)
	if mode == "hist_guards" and tick == 28:
		var before := actor.state.to_bytes()
		var old_count := actor_prediction.adopted_old_claims
		var late_count := actor_prediction.waits_late_input
		var calls: Array = []
		var callback := func(input: ActorInput): calls.append(input.tick)
		actor_prediction.reconcile(actor, 18, old_claim, 18, tick, callback, true)
		check("forced_replay_preserves_old_claim_guard", actor_prediction.adopted_old_claims == old_count + 1 and calls.is_empty() and actor.state.to_bytes() == before)
		actor_prediction.reconcile(actor, 24, actor_snapshots[24], 23, tick, callback, true)
		check("forced_replay_preserves_late_input_guard", actor_prediction.waits_late_input == late_count + 1 and calls.is_empty() and actor.state.to_bytes() == before)
	if mode == "hist_effect" and tick == 30:
		submit(31, 2, "release", Vector3.ZERO, Vector3(1.5, 2, -1))
		correct_actor(20, tick)
	if mode == "hist_time" and tick == 30:
		check("real_time_replay", history.apply_world_slow(20, 35, 0.5, tick))
		check("object_stopped_on_announcement", not adapter.ready_for_input)
		rebuild_reference(19, range(20, tick))
	if mode == "hist_gap" and tick == 30:
		actor_prediction.clear()
		check("missing_actor_history_rejected", not history.apply_world_slow(20, 35, 0.5, tick) and not history.actor_baseline_ready)
	if mode == "hist_gap" and tick == 34:
		var generation: int = adapter.recovery_generation()
		var callbacks: int = history.replay_callbacks
		check("matching_snapshot_forces_real_replay", history.reconcile_actor(30, actor_snapshots[30], 30, tick))
		check("matching_snapshot_rebuilt_steps", history.replay_callbacks == callbacks + 3)
		check("suspended_history_change_advances_generation", adapter.recovery_generation() > generation)
		for t in range(31, tick): owned_frames[t] = replay_frames[t].duplicate(true)
		check("matching_replay_history_correct", history.actor_baseline_ready)

func correct_actor(host_tick: int, current: int) -> void:
	var host := ActorState.from_bytes(actor_snapshots[host_tick])
	host.position.x += 0.12; host.quantize()
	var first: Dictionary = owned_frames[host_tick].duplicate(true)
	first.eyes = BaseRegistry.world_position(host) + Vector3.UP * maxf(actor.stance_height(host.stance) - InvAuthority.EYES_BELOW_TOP, 0.3)
	var calls := provider_calls
	check("real_actor_reconcile", history.reconcile_actor(host_tick, host.to_bytes(), host_tick, current))
	check("replay_uses_cached_inputs", provider_calls == calls and actor_prediction.corrections == 1)
	check("corrected_anchor_from_host", history.recorded_frame(host_tick) == first)
	check("object_stopped_before_new_actor_tick", not adapter.ready_for_input)
	owned_frames[host_tick] = first
	for t in range(host_tick + 1, current): owned_frames[t] = replay_frames[t].duplicate(true)
	check("corrected_actor_frames_differ", owned_frames[current - 1].eyes != trace[current - 2].eyes_value)
	rebuild_reference(host_tick - 1, range(host_tick, current))
	frozen_tick = adapter.world.get_tick()

func rebuild_reference(base: int, ticks: Array) -> void:
	var w = make_world(); check("history_reference_anchor", w.restore_trusted(checkpoints[base]))
	for t in ticks:
		var f: Dictionary = replay_frames[t] if replay_frames.has(t) else owned_frames[t]
		owned_frames[t] = f.duplicate(true)
		check("eyes_from_actual_replay_%d" % t, history.recorded_frame(t) == f)
		reference_step(w, f)
	reference = w

func after_tick(tick: int) -> void:
	if done: return
	var input: ActorInput = user_inputs[tick]
	actor_prediction.record(tick, input, actor.state)
	actor_snapshots[tick] = actor.state.to_bytes()
	var frame := actual_frame(input)
	owned_frames[tick] = frame.duplicate(true)
	check("recorder_matches_actor_%d" % tick, history.recorded_frame(tick) == frame)
	check("claims_excluded_%d" % tick, frame.input.size() == 32)
	reference_step(reference, frame)
	if tick in [14, 19, 30, 36]: checkpoints[tick] = reference.snapshot_trusted()
	trace.append({"tick": tick, "dt": frame.dt, "eyes_value": frame.eyes, "native_sha": hash_state(adapter.world),
		"reference_sha": hash_state(reference), "ready": adapter.ready_for_input, "generation": adapter.recovery_generation()})
	if mode == "hist_guards" and tick == 20:
		actor_prediction.recent(10)
		old_claim = actor_snapshots[18].duplicate()
	if mode in ["hist_actor", "hist_guards"] and tick == 26: recover_at(14)
	if mode == "hist_time" and tick == 30: recover_at(19)
	if mode == "hist_effect":
		if tick == 34: check("recorder_keeps_suspended_ticks", history.recorded_frame(34).tick == 34 and adapter.world.get_tick() == frozen_tick)
		if tick == 35:
			recover_at(19)
			check("cancelled_action_waits_for_authority_effect", unified_effects == [[1, "grab"]] and not adapter.world.sample(2, 1).held)
			var status: Dictionary = history.queue_action(31, 2, "release", Vector3.ZERO, Vector3(1.5, 2, -1))
			check("known_does_not_claim_execution", status.status == "known" and not status.effect_emitted and not status.confirmed)
		if tick == 37:
			var p := packet(36, 2, [ack(2, 31, 31, "release")])
			check("late_first_effect_confirmed", history.apply_authority_trusted(p))
			check("confirmation_effect_once", unified_effects == [[1, "grab"], [2, "release"]] and confirmations == [[2, "release", 31, 31]])
			p.revision = 3
			check("new_revision_same_ack", history.apply_authority_trusted(p))
			check("same_ack_no_duplicate_effect", unified_effects.size() == 2 and confirmations.size() == 1)
	if mode == "hist_gap":
		if tick == 30: check("no_recovery_with_unrepaired_actor", not history.apply_authority_trusted(packet(30, 1)) and history.last_error == "actor_baseline_required")
		if tick == 34: recover_at(30)
	if tick == 60:
		check("history_final_native_exact", hash_state(adapter.world) == hash_state(reference))
		check("history_effects_once", unified_effects == [[1, "grab"], [2, "release"]])
		check("history_memory_bounded", history.stats().ticks <= 120 and history.stats().bytes <= history.HISTORY_BYTES)
		check("actor_provider_only_live", provider_calls == 60)
		finish()

func recover_at(base: int) -> void:
	var before := [actor.state.to_bytes(), clock.tick, provider_calls]
	check("recover_from_real_actor_history", history.apply_authority_trusted(packet(base, 1)))
	check("real_history_native_exact", hash_state(adapter.world) == hash_state(reference))
	check("object_recovery_does_not_repeat_actor", before == [actor.state.to_bytes(), clock.tick, provider_calls])
