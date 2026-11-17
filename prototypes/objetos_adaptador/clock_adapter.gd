extends Node
## Experimental bridge: production ActorInput + ActorMotor/SimClock -> native objects.
## Local calls only. This is not the game's authority or a network snapshot decoder.
signal frame_recorded(frame: Dictionary)
signal action_effect(action_id: int, kind: String)
signal recovery_required(reason: String)

const HISTORY_TICKS := 120
const HISTORY_BYTES := 262144
const MAX_REPLAY_STEPS := 24
const MAX_ACTIONS := 256
const MAX_INPUT_BYTES := 256
const MAX_SNAPSHOT_BYTES := 1048620

var world
var ready_for_input := false
var last_error := ""
var replayed_steps := 0
var capture_calls := 0
var goal_builds := 0
var clock: SimClock
var actor: ActorBody
var tuning: ActorTuning
var _factory: Callable
var _uid := 0
var _epoch := 0
var _session := 0
var _last_tick := 0
var _last_authority_tick := -1
var _signature := PackedByteArray()
var _pending := {}
var _queued := {}
var _actions := {}
var _history := {}
var _history_bytes := 0

func start(p_clock: SimClock, p_actor: ActorBody, p_tuning: ActorTuning,
		factory: Callable, uid: int, epoch: int, session: int) -> bool:
	if clock != null: return _fail("already_attached")
	if p_clock == null or p_actor == null or p_tuning == null or not factory.is_valid() \
		or uid <= 0 or epoch <= 0 or session <= 0 or maxi(uid, maxi(epoch, session)) > 0x7FFFFFFF:
		return _fail("invalid_binding")
	# The first native controller has explicit fixed parameters. Reject unsupported
	# tuning instead of silently simulating a different hand on this path.
	var params := [p_tuning.hold_follow_time, p_tuning.hold_move_limit, p_tuning.hold_accel_limit,
		p_tuning.hold_turn_limit, p_tuning.hold_turn_accel]
	var supported := [0.08, 12.0, 80.0, 720.0, 7200.0]
	for i in params.size():
		if not is_equal_approx(params[i], supported[i]): return _fail("unsupported_hand_tuning")
	var candidate = factory.call()
	if candidate == null or candidate.get_tick() != p_clock.tick or candidate.sample(uid, epoch).is_empty():
		return _fail("tick_or_identity_binding")
	if candidate.snapshot_trusted().is_empty(): return _fail("unsealed_context")
	clock = p_clock; actor = p_actor; tuning = p_tuning; _factory = factory
	world = candidate; _uid = uid; _epoch = epoch; _session = session
	_last_tick = clock.tick; _signature = _tuning_signature()
	clock.tick_finished.connect(_after_tick)
	clock.hard_resynced.connect(_hard_resynced)
	ready_for_input = true
	return true

## Called by the scene's input provider before ActorMotor runs. Serialization
## freezes the same quantized input that the actor uses, including its hold intent.
func capture(input: ActorInput) -> bool:
	if not ready_for_input: return _fail("not_ready")
	if input == null or input.tick != clock.tick or input.tick != _last_tick + 1 \
		or _pending.has(input.tick) or not input.is_possible() or not is_finite(input.look_yaw):
		return _fail("invalid_or_duplicate_input", true)
	var buffer := StreamPeerBuffer.new()
	input.write_to(buffer)
	if buffer.data_array.size() > MAX_INPUT_BYTES or _read_input(buffer.data_array) == null:
		return _fail("invalid_input_bytes", true)
	_pending[input.tick] = buffer.data_array.duplicate()
	capture_calls += 1
	return true

## Scene-local intent, not a permission grant. One transition per tick and one
## bound hand/object in this first bridge. Stable action IDs suppress duplicates.
func queue_action(at_tick: int, action_id: int, kind: String,
		anchor := Vector3.ZERO, impulse := Vector3.ZERO) -> bool:
	if not ready_for_input: return _fail("not_ready")
	if at_tick < 0 or at_tick > 0x7FFFFFFF or action_id <= 0 or action_id > 0x7FFFFFFF \
		or kind not in ["grab", "release"] or not anchor.is_finite() \
		or maxf(absf(anchor.x), maxf(absf(anchor.y), absf(anchor.z))) > 1000.0 \
		or not impulse.is_finite() or maxf(absf(impulse.x), maxf(absf(impulse.y), absf(impulse.z))) > 100000.0:
		return _fail("invalid_action")
	var action := {"id": action_id, "kind": kind, "tick": at_tick, "anchor": anchor, "impulse": impulse}
	var fingerprint := var_to_bytes(action)
	if _actions.has(action_id):
		return true if _actions[action_id] == fingerprint else _fail("action_identity_conflict")
	if at_tick < _last_tick + 1 or at_tick > _last_tick + 2: return _fail("invalid_action_tick")
	if _actions.size() >= MAX_ACTIONS or _queued.has(at_tick): return _fail("action_capacity")
	_actions[action_id] = fingerprint
	_queued[at_tick] = action
	return true

func _after_tick(at_tick: int) -> void:
	if not ready_for_input: return
	if at_tick != _last_tick + 1 or world.get_tick() != _last_tick or not _pending.has(at_tick):
		_fail("clock_or_input_gap", true); return
	if _tuning_signature() != _signature:
		_fail("tuning_changed", true); return
	# ActorMotor and actor.present have already run at tick_finished.
	var eyes := InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state))
	var frame := {"tick": at_tick, "dt": SimClock.world_dt(at_tick), "eyes": eyes,
		"input": _pending[at_tick], "action": _queued.get(at_tick, {}).duplicate(true)}
	if not _apply_frame(world, frame):
		_fail("native_step_failed:" + last_error, true); return
	_pending.erase(at_tick); _queued.erase(at_tick)
	_last_tick = at_tick
	_history[at_tick] = frame
	_history_bytes += var_to_bytes(frame).size()
	while _history.size() > HISTORY_TICKS or _history_bytes > HISTORY_BYTES:
		var oldest: int = _history.keys().min()
		_history_bytes -= var_to_bytes(_history[oldest]).size()
		_history.erase(oldest)
	if not frame.action.is_empty(): action_effect.emit(frame.action.id, frame.action.kind)
	frame_recorded.emit(frame.duplicate(true))

func _read_input(bytes: PackedByteArray) -> ActorInput:
	var stream := StreamPeerBuffer.new()
	stream.data_array = bytes
	var input := ActorInput.read_from(stream)
	if input == null or stream.get_available_bytes() != 0 or not input.is_possible(): return null
	if not input.hold.is_empty():
		if input.hold_session() != _session: return null
		var q := Quaternion(input.hold[3] / ActorInput.ROTATION_STEPS, input.hold[4] / ActorInput.ROTATION_STEPS,
			input.hold[5] / ActorInput.ROTATION_STEPS, input.hold[6] / ActorInput.ROTATION_STEPS)
		if not q.is_finite() or absf(q.length_squared() - 1.0) > 0.001: return null
	return input

func _apply_frame(target_world, frame: Dictionary) -> bool:
	var input := _read_input(frame.input)
	if input == null or input.tick != frame.tick or target_world.get_tick() != frame.tick - 1 \
		or not is_finite(frame.dt) or frame.dt <= 0.0 or frame.dt > 1.0 / 30.0 or not frame.eyes.is_finite():
		return _fail("invalid_recorded_frame")
	var state: Dictionary = target_world.sample(_uid, _epoch)
	var action: Dictionary = frame.action
	var kind: String = action.get("kind", "")
	if state.is_empty() or (kind == "grab" and state.held) or (kind == "release" and not state.held) \
		or ((state.held or kind == "grab") and input.hold.is_empty() and kind != "release"):
		return _fail("invalid_hand_transition")
	var goal := InvHoldMotion.target_of(frame.eyes, input, tuning)
	goal_builds += 1
	if kind == "grab" and not target_world.begin_hold(_uid, _epoch, action.anchor, goal):
		return _fail(target_world.get_last_error())
	if (state.held or kind == "grab") and not input.hold.is_empty():
		if not target_world.set_goal(_uid, _epoch, goal): return _fail(target_world.get_last_error())
	if kind == "release" and not target_world.release_body(_uid, _epoch, action.impulse):
		return _fail(target_world.get_last_error())
	if not target_world.step(frame.dt): return _fail(target_world.get_last_error())
	if target_world.cache_checkpoint() < 0: return _fail(target_world.get_last_error())
	return true

## Authority bytes only, after an external protocol has authenticated and bounded
## them. No RPC calls this method. Replay happens in a candidate world, with saved
## inputs, eyes and dt. It never calls the input provider or advances the actor.
func reconcile_trusted(checkpoint_tick: int, bytes: PackedByteArray) -> bool:
	if not ready_for_input: return _fail("not_ready")
	if checkpoint_tick <= _last_authority_tick: return _fail("duplicate_or_stale_authority")
	if checkpoint_tick < 0 or checkpoint_tick > _last_tick or bytes.is_empty() or bytes.size() > MAX_SNAPSHOT_BYTES:
		return _fail("invalid_checkpoint")
	if _tuning_signature() != _signature: return _fail("tuning_changed", true)
	if _last_tick - checkpoint_tick > MAX_REPLAY_STEPS: return _fail("replay_budget", true)
	for at_tick in range(checkpoint_tick + 1, _last_tick + 1):
		if not _history.has(at_tick): return _fail("history_expired", true)
	var candidate = _factory.call()
	if candidate == null or not candidate.restore_trusted(bytes): return _fail("checkpoint_rejected")
	if candidate.get_tick() != checkpoint_tick: return _fail("checkpoint_tick_mismatch")
	var count := 0
	for at_tick in range(checkpoint_tick + 1, _last_tick + 1):
		if not _apply_frame(candidate, _history[at_tick]): return _fail("replay_failed:" + last_error)
		count += 1
	world = candidate
	_last_authority_tick = checkpoint_tick
	replayed_steps += count
	last_error = ""
	return true

func recorded_frame(at_tick: int) -> Dictionary:
	return _history.get(at_tick, {}).duplicate(true)

func history_stats() -> Dictionary:
	return {"ticks": _history.size(), "bytes": _history_bytes,
		"oldest": _history.keys().min() if not _history.is_empty() else -1, "latest": _last_tick}

func _tuning_signature() -> PackedByteArray:
	return var_to_bytes([tuning.hold_min_distance, tuning.hold_max_distance, tuning.hold_follow_time,
		tuning.hold_move_limit, tuning.hold_accel_limit, tuning.hold_turn_limit, tuning.hold_turn_accel])

func _hard_resynced() -> void:
	_pending.clear(); _queued.clear(); _history.clear(); _history_bytes = 0
	_fail("clock_resynced", true)

func _fail(reason: String, recover := false) -> bool:
	last_error = reason
	if recover and ready_for_input:
		ready_for_input = false
		recovery_required.emit(reason)
	return false
