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
var _last_authority_revision := 0
var _connection_epoch := 1
var _context_revision := 1
var _history_generation := 1
var _observed_clock_tick := 0
var _signature := PackedByteArray()
var _pending := {}
var _queued := {}
var _actions := {}
var _max_action_id := 0
var _retired_action_id := 0
var _retired_before_tick := -1
var _history := {}
var _history_bytes := 0

func start(p_clock: SimClock, p_actor: ActorBody, p_tuning: ActorTuning,
		factory: Callable, uid: int, epoch: int, session: int,
		connection_epoch := 1, context_revision := 1) -> bool:
	if clock != null: return _fail("already_attached")
	if p_clock == null or p_actor == null or p_tuning == null or not factory.is_valid() \
		or uid <= 0 or epoch <= 0 or session <= 0 or maxi(uid, maxi(epoch, session)) > 0x7FFFFFFF:
		return _fail("invalid_binding")
	if connection_epoch <= 0 or context_revision <= 0 or maxi(connection_epoch, context_revision) > 0x7FFFFFFF:
		return _fail("invalid_context_binding")
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
	_connection_epoch = connection_epoch; _context_revision = context_revision
	_observed_clock_tick = clock.tick
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
	_retire_old_actions(clock.tick)
	if _actions.has(action_id):
		return true if _actions[action_id] == fingerprint else _fail("action_identity_conflict")
	if is_retired_action(action_id): return _fail("retired_action")
	if at_tick < _last_tick + 1 or at_tick > _last_tick + 2: return _fail("invalid_action_tick")
	if action_id <= _max_action_id: return _fail("nonmonotonic_action_id")
	if _actions.size() >= MAX_ACTIONS or _queued.has(at_tick): return _fail("action_capacity")
	_actions[action_id] = fingerprint
	_max_action_id = action_id
	_queued[at_tick] = action
	return true

func _after_tick(at_tick: int) -> void:
	_observed_clock_tick = at_tick
	_retire_old_actions(at_tick)
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

## IDs increase for the whole binding and never wrap/reuse. A watermark keeps
## old retries retired without retaining every old fingerprint forever. Sounds
## and confirmations beyond this replay window are intentionally not re-emitted;
## this journal is NOT a ledger for persistent inventory transactions.
func _retire_old_actions(present: int) -> void:
	var cutoff := present - HISTORY_TICKS
	_retired_before_tick = maxi(_retired_before_tick, cutoff)
	for id in _actions.keys():
		var original: Dictionary = bytes_to_var(_actions[id])
		if original.tick < cutoff:
			_retired_action_id = maxi(_retired_action_id, id)
			_actions.erase(id)

func is_retired_action(id: int) -> bool:
	return id > 0 and id <= _retired_action_id and not _actions.has(id)

func action_stats() -> Dictionary:
	return {"active": _actions.size(), "max_id": _max_action_id,
		"retired_id": _retired_action_id, "retired_before_tick": _retired_before_tick}

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

## Legacy entry point for the delivery 10 fixtures, with their fixed timeline.
## New integration must use apply_authority_trusted/recover_authority_trusted,
## which check scope, revisions and historical time before replay.
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

## Scene-owned metadata, not authentication. A transport must bind its sender
## before calling either checked method below. Native bytes remain trusted-only.
func authority_scope() -> Dictionary:
	return {"connection": _connection_epoch, "context": _context_revision,
		"uid": _uid, "epoch": _epoch, "hold_session": _session,
		"hand_signature": _tuning_signature().hex_encode().sha256_text()}

func recovery_generation() -> int:
	return _history_generation

func last_authority() -> Dictionary:
	return {"tick": _last_authority_tick, "revision": _last_authority_revision}

## Revisions order states independently of tick: a newer revision may correct
## the same tick, but never move authority back to an older physical tick.
func apply_authority_trusted(packet: Dictionary) -> bool:
	if not ready_for_input: return _fail("not_ready")
	if not _valid_authority(packet): return false
	if packet.tick > _last_tick: return _fail("future_authority")
	if _tuning_signature() != _signature: return _fail("tuning_changed", true)
	if _last_tick - packet.tick > MAX_REPLAY_STEPS: return _fail("replay_budget", true)
	for t in range(packet.tick + 1, _last_tick + 1):
		if not _history.has(t): return _fail("history_expired", true)
		if _history[t].dt != SimClock.world_dt(t):
			invalidate_history_from(t, "world_time")
			return false
	var candidate = _replay_candidate(packet.tick, packet.snapshot, _history, _last_tick)
	if candidate == null: return false
	world = candidate
	_last_authority_tick = packet.tick; _last_authority_revision = packet.revision
	replayed_steps += _last_tick - packet.tick
	last_error = ""
	return true

## Notify this before consuming corrected actor history or a retroactive time
## change. Future-only changes do not invalidate already simulated inputs.
func invalidate_history_from(at_tick: int, cause: String) -> bool:
	if clock == null or at_tick < 0 or at_tick > 0x7FFFFFFF or cause not in ["actor", "world_time"]:
		return _fail("invalid_history_change")
	# While native prediction is stopped the actor can still accumulate corrected
	# frames. A change in those ticks must also invalidate in-flight recovery.
	var history_present := _last_tick if ready_for_input else maxi(_last_tick, _observed_clock_tick)
	if at_tick > history_present: return true
	for t in _history.keys():
		if t >= at_tick:
			_history_bytes -= var_to_bytes(_history[t]).size()
			_history.erase(t)
	if not ready_for_input:
		_history_generation += 1
		last_error = "timeline_invalidated:" + cause
		recovery_required.emit(last_error)
		return true
	_fail("timeline_invalidated:" + cause, true)
	return true

## A caller that owns the corrected actor/time history supplies a complete batch
## from authority tick + 1 to the CURRENT clock tick. No old frames are silently
## borrowed. A generation token prevents an in-flight stale batch being reused.
func recover_authority_trusted(packet: Dictionary, frames: Array, generation: int) -> bool:
	if clock == null or ready_for_input: return _fail("recovery_not_needed")
	if generation != _history_generation: return _fail("stale_recovery_generation")
	if clock.tick != _observed_clock_tick: return _fail("recovery_phase")
	if not _valid_authority(packet): return false
	var present := clock.tick
	if packet.tick > present: return _fail("future_authority")
	var count: int = present - packet.tick
	if count > MAX_REPLAY_STEPS: return _fail("replay_budget")
	if frames.size() != count: return _fail("incomplete_recovery_frames")
	var supported := [0.08, 12.0, 80.0, 720.0, 7200.0]
	var params := [tuning.hold_follow_time, tuning.hold_move_limit, tuning.hold_accel_limit,
		tuning.hold_turn_limit, tuning.hold_turn_accel]
	for i in params.size():
		if not is_equal_approx(params[i], supported[i]): return _fail("unsupported_hand_tuning")
	var replacement := {}
	var byte_count := 0
	for i in frames.size():
		if typeof(frames[i]) != TYPE_DICTIONARY: return _fail("invalid_recovery_frame")
		var supplied: Dictionary = frames[i]
		if not _valid_recovery_frame(supplied, packet.tick + 1 + i): return false
		var frame: Dictionary = supplied.duplicate(true)
		byte_count += var_to_bytes(frame).size()
		if byte_count > HISTORY_BYTES: return _fail("recovery_history_bytes")
		replacement[frame.tick] = frame
	var candidate = _replay_candidate(packet.tick, packet.snapshot, replacement, present)
	if candidate == null: return false
	world = candidate
	_history = replacement; _history_bytes = byte_count
	_pending.clear(); _queued.clear()
	_last_tick = present; _signature = _tuning_signature()
	_last_authority_tick = packet.tick; _last_authority_revision = packet.revision
	replayed_steps += count
	ready_for_input = true
	last_error = ""
	return true

func _valid_authority(packet: Dictionary) -> bool:
	var keys := ["version", "connection", "context", "uid", "epoch", "hold_session", "hand_signature", "revision", "tick", "snapshot", "acks"]
	if packet.size() != keys.size() or not keys.all(func(k): return packet.has(k)):
		return _fail("invalid_authority_envelope")
	for key in ["version", "connection", "context", "uid", "epoch", "hold_session", "revision", "tick"]:
		if typeof(packet[key]) != TYPE_INT or packet[key] < (0 if key == "tick" else 1) or packet[key] > 0x7FFFFFFF:
			return _fail("invalid_authority_envelope")
	if packet.version != 1: return _fail("authority_version")
	if typeof(packet.hand_signature) != TYPE_STRING or packet.hand_signature.length() != 64:
		return _fail("authority_scope")
	for key in ["connection", "context", "uid", "epoch", "hold_session", "hand_signature"]:
		if packet[key] != authority_scope()[key]: return _fail("authority_scope")
	if packet.revision <= _last_authority_revision: return _fail("duplicate_or_stale_revision")
	if packet.tick < _last_authority_tick: return _fail("authority_tick_regression")
	if typeof(packet.snapshot) != TYPE_PACKED_BYTE_ARRAY or packet.snapshot.is_empty() or packet.snapshot.size() > MAX_SNAPSHOT_BYTES:
		return _fail("invalid_checkpoint")
	if typeof(packet.acks) != TYPE_ARRAY or packet.acks.size() > 16: return _fail("invalid_action_confirmation")
	var seen := {}
	for ack in packet.acks:
		if typeof(ack) != TYPE_DICTIONARY or ack.size() != 4: return _fail("invalid_action_confirmation")
		for key in ["id", "requested_tick", "applied_tick"]:
			if typeof(ack.get(key)) != TYPE_INT or ack[key] < 0 or ack[key] > 0x7FFFFFFF:
				return _fail("invalid_action_confirmation")
		if ack.id == 0 or ack.get("kind") not in ["grab", "release"] or seen.has(ack.id) \
			or ack.applied_tick < ack.requested_tick or ack.applied_tick > packet.tick:
			return _fail("invalid_action_confirmation")
		seen[ack.id] = true
		if is_retired_action(ack.id) and ack.requested_tick < _retired_before_tick: continue
		if not _actions.has(ack.id): return _fail("invalid_action_confirmation")
		var original: Dictionary = bytes_to_var(_actions[ack.id]) # our own scene-generated bytes
		if ack.kind != original.kind or ack.requested_tick != original.tick \
			or ack.applied_tick < ack.requested_tick or ack.applied_tick > packet.tick:
			return _fail("invalid_action_confirmation")
	return true

func _valid_recovery_frame(frame: Dictionary, at_tick: int) -> bool:
	var keys := ["tick", "dt", "eyes", "input", "action"]
	if frame.size() != keys.size() or not keys.all(func(k): return frame.has(k)):
		return _fail("invalid_recovery_frame")
	if typeof(frame.tick) != TYPE_INT or frame.tick != at_tick or typeof(frame.dt) != TYPE_FLOAT \
		or not is_finite(frame.dt) or frame.dt <= 0.0 or frame.dt > 1.0 / 30.0 \
		or frame.dt != SimClock.world_dt(at_tick) or typeof(frame.eyes) != TYPE_VECTOR3 or not frame.eyes.is_finite() \
		or typeof(frame.input) != TYPE_PACKED_BYTE_ARRAY or frame.input.size() > MAX_INPUT_BYTES \
		or typeof(frame.action) != TYPE_DICTIONARY:
		return _fail("invalid_recovery_frame")
	var input := _read_input(frame.input)
	if input == null or input.tick != at_tick: return _fail("invalid_recovery_input")
	if not frame.action.is_empty():
		if typeof(frame.action.get("id")) != TYPE_INT or not _actions.has(frame.action.id):
			return _fail("unknown_recovery_action")
		var original: Dictionary = bytes_to_var(_actions[frame.action.id])
		if original != frame.action or original.tick != at_tick: return _fail("recovery_action_conflict")
	return true

func _replay_candidate(at_tick: int, bytes: PackedByteArray, records: Dictionary, present: int):
	var candidate = _factory.call()
	if candidate == null or not candidate.restore_trusted(bytes):
		_fail("checkpoint_rejected"); return null
	if candidate.get_tick() != at_tick:
		_fail("checkpoint_tick_mismatch"); return null
	for t in range(at_tick + 1, present + 1):
		if not _apply_frame(candidate, records[t]):
			_fail("replay_failed:" + last_error); return null
	return candidate

func _tuning_signature() -> PackedByteArray:
	return var_to_bytes([tuning.hold_min_distance, tuning.hold_max_distance, tuning.hold_follow_time,
		tuning.hold_move_limit, tuning.hold_accel_limit, tuning.hold_turn_limit, tuning.hold_turn_accel])

func _hard_resynced() -> void:
	_pending.clear(); _queued.clear(); _history.clear(); _history_bytes = 0
	if not ready_for_input:
		_history_generation += 1
		last_error = "clock_resynced"
		recovery_required.emit("clock_resynced")
		return
	_fail("clock_resynced", true)

func _fail(reason: String, recover := false) -> bool:
	last_error = reason
	if recover and ready_for_input:
		ready_for_input = false
		_history_generation += 1
		_pending.clear(); _queued.clear()
		recovery_required.emit(reason)
	return false
