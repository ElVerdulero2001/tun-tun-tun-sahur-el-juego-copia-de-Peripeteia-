extends Node
## Scene-owned integration with the REAL ClientPrediction replay. No replacement
## actor simulation, RPC, or invented historical eyes. The scene supplies its
## existing _step_local callable, including events/consumables as appropriate.
signal history_rebuilt(first_tick: int, last_tick: int)
signal authority_needed(reason: String)
signal effect_ready(action_id: int, kind: String)
signal action_confirmed(action_id: int, kind: String, requested_tick: int, applied_tick: int)
## Confirmation window elapsed, NOT an authority rejection or permission to retry.
signal action_expired(action_id: int, kind: String, requested_tick: int)

const HISTORY_TICKS := 120
const HISTORY_BYTES := 262144
var last_error := ""
var replay_callbacks := 0
var actor_baseline_ready := true
var adapter
var clock: SimClock
var actor: ActorBody
var prediction: ClientPrediction
var _step: Callable
var _frames := {}
var _states := {}
var _pending_inputs := {}
var _commands := {}
var _known_actions := {}
var _effects := {}
var _confirmed := {}
var _bytes := 0
var _actor_tick := -1
var _replaying := false
var _rebuild_started := false
var _first := 0
var _expected := 0
var _anchor_tick := -1
var _anchor_input := PackedByteArray()
var _replay_gap := false
var _cause := "actor"

func start(p_adapter, p_prediction: ClientPrediction, step_actor: Callable) -> bool:
	if adapter != null or p_adapter == null or p_prediction == null or not step_actor.is_valid(): return _fail("invalid_binding")
	if not p_adapter.ready_for_input or p_adapter.history_stats().ticks != 0 or p_adapter.capture_calls != 0 \
		or p_adapter.last_authority().tick != -1: return _fail("bridge_requires_fresh_binding")
	adapter = p_adapter; prediction = p_prediction; _step = step_actor
	clock = adapter.clock; actor = adapter.actor; _actor_tick = clock.tick
	adapter.action_effect.connect(_on_effect)
	clock.tick_finished.connect(_tick_finished)
	clock.hard_resynced.connect(_reset_history)
	return true

## Wrap the scene's own input provider, only for the bound actor. Record intents
## even while native prediction is stopped. Physical claims are output, not input;
## strip them from a COPY, without modifying the actor/network's ActorInput.
func capture_input(input: ActorInput) -> bool:
	if clock == null or _replaying or input == null or input.tick != clock.tick or input.tick <= _actor_tick:
		return _fail("input_phase")
	var bytes := _intent_bytes(input)
	if bytes.is_empty(): return _fail("invalid_input")
	if _pending_inputs.has(input.tick):
		if _pending_inputs[input.tick] == bytes: return true
		actor_baseline_ready = false
		adapter.invalidate_history_from(adapter.world.get_tick(), "actor")
		authority_needed.emit("input_conflict")
		return _fail("input_conflict")
	if _pending_inputs.size() >= 2: return _fail("pending_input_capacity")
	if adapter.ready_for_input and not adapter.capture(_read_input(bytes)): return _fail(adapter.last_error)
	_pending_inputs[input.tick] = bytes
	return true

## 'known' means identity already registered, NOT that the action ran physically.
## This distinction matters for an action cancelled when prediction was stopped.
func queue_action(tick: int, id: int, kind: String, anchor := Vector3.ZERO, impulse := Vector3.ZERO) -> Dictionary:
	if adapter == null: return {"status": "rejected", "reason": "not_started"}
	if not adapter.queue_action(tick, id, kind, anchor, impulse): return {"status": "rejected", "reason": adapter.last_error}
	if _known_actions.has(id): return {"status": "known", "effect_emitted": _effects.has(id), "confirmed": _confirmed.has(id)}
	var command := {"id": id, "kind": kind, "tick": tick, "anchor": anchor, "impulse": impulse}
	_known_actions[id] = command; _commands[tick] = command
	return {"status": "queued"}

func _tick_finished(tick: int) -> void:
	_actor_tick = tick
	# Retirement/notification also runs when input capture or prediction stopped.
	_trim()
	if not _pending_inputs.has(tick):
		actor_baseline_ready = false
		adapter.invalidate_history_from(tick, "actor")
		authority_needed.emit("input_not_captured")
		return
	var input := _read_input(_pending_inputs[tick])
	_pending_inputs.erase(tick)
	_save_actual(input)
	_trim()

func _save_actual(input: ActorInput) -> void:
	var bytes := _intent_bytes(input)
	if bytes.is_empty(): actor_baseline_ready = false; return
	var frame := {"tick": input.tick, "dt": SimClock.world_dt(input.tick),
		"eyes": InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state)),
		"input": bytes, "action": _commands.get(input.tick, {}).duplicate(true)}
	if _frames.has(input.tick): _bytes -= var_to_bytes(_frames[input.tick]).size() + _states[input.tick].size()
	_frames[input.tick] = frame
	_states[input.tick] = actor.state.to_bytes()
	_bytes += var_to_bytes(frame).size() + _states[input.tick].size()

## The scene calls this where it used ClientPrediction.reconcile. Same algorithm
## and same step callback; only replay observations/invalidation are added.
func reconcile_actor(host_tick: int, state: PackedByteArray, used_tick: int, current_tick: int) -> bool:
	if clock == null or _replaying or current_tick != clock.tick or host_tick < 0 or host_tick >= current_tick:
		return _fail("actor_reconcile_phase")
	if ActorState.from_bytes(state) == null: return _fail("invalid_actor_state")
	_setup_replay(host_tick, host_tick + 1, host_tick, "actor")
	var changes := prediction.corrections + prediction.alignments
	prediction.reconcile(actor, host_tick, state, used_tick, current_tick, _step_replay, not actor_baseline_ready)
	var corrected := prediction.corrections + prediction.alignments > changes
	if corrected and not _rebuild_started:
		_begin_rebuild()
		_save_anchor()
	_finish_replay(current_tick - 1, corrected)
	return corrected

## Replaces the scene's add_world_slow + replay_from sequence. Notify immediately,
## so objects cannot continue with stale dt until their next authority snapshot.
func apply_world_slow(start_tick: int, end_tick: int, scale: float, current_tick: int) -> bool:
	if clock == null or _replaying or current_tick != clock.tick or start_tick < 0 or end_tick <= start_tick \
		or not is_finite(scale) or scale <= 0.0 or scale > 1.0: return _fail("invalid_world_time")
	var changes := SimClock.add_world_slow(start_tick, end_tick, scale)
	if changes.is_empty(): return true
	var first: int = changes.min()
	if first >= current_tick: return true
	_setup_replay(first, first, -1, "world_time")
	_begin_rebuild()
	var ok := prediction.replay_from(actor, first, current_tick, _step_replay)
	_finish_replay(current_tick - 1, ok)
	return ok and actor_baseline_ready

func _setup_replay(first: int, expected: int, anchor: int, cause: String) -> void:
	_replaying = true; _rebuild_started = false; _replay_gap = false
	_first = first; _expected = expected; _anchor_tick = anchor; _cause = cause
	_anchor_input = _frames.get(anchor, {}).get("input", PackedByteArray()).duplicate()

func _begin_rebuild() -> void:
	if _rebuild_started: return
	_rebuild_started = true
	adapter.invalidate_history_from(_first, _cause)
	for tick in _frames.keys():
		if tick >= _first:
			_bytes -= var_to_bytes(_frames[tick]).size() + _states[tick].size()
			_frames.erase(tick); _states.erase(tick)

func _save_anchor() -> void:
	if _anchor_tick >= 0 and not _anchor_input.is_empty(): _save_actual(_read_input(_anchor_input))

func _step_replay(input: ActorInput) -> void:
	if not _rebuild_started:
		_begin_rebuild()
		_save_anchor() # actor is at the actual restored host state here
	if input.tick != _expected: _replay_gap = true
	_step.call(input)
	_save_actual(input) # actor/stance/base after its REAL replay step
	_expected = input.tick + 1
	replay_callbacks += 1

func _finish_replay(present: int, corrected: bool) -> void:
	_replaying = false
	if corrected:
		actor_baseline_ready = not _replay_gap and _expected == present + 1
		_trim()
		history_rebuilt.emit(_first, present)
		if not actor_baseline_ready: authority_needed.emit("actor_replay_gap")
	elif _rebuild_started:
		actor_baseline_ready = false
		authority_needed.emit("actor_history_unavailable")

## Called between completed actor ticks (or in pause), after the packet's sender
## was checked externally. Recovery uses this recorder, including suspended ticks.
func apply_authority_trusted(packet: Dictionary) -> bool:
	if clock == null or _replaying or clock.tick != _actor_tick: return _fail("authority_phase")
	var ok := false
	if adapter.ready_for_input:
		ok = adapter.apply_authority_trusted(packet)
		if not ok and adapter.last_error == "timeline_invalidated:world_time":
			actor_baseline_ready = false
			authority_needed.emit("actor_time_replay_required")
	else:
		if not actor_baseline_ready: return _fail("actor_baseline_required")
		if typeof(packet.get("tick")) != TYPE_INT: return _fail("invalid_authority_tick")
		var first: int = packet.tick + 1
		if first < 1 or clock.tick - packet.tick > adapter.MAX_REPLAY_STEPS: return _fail("replay_budget")
		var frames: Array = []
		for tick in range(first, clock.tick + 1):
			if not _frames.has(tick): return _fail("history_unavailable")
			frames.append(_frames[tick].duplicate(true))
		ok = adapter.recover_authority_trusted(packet, frames, adapter.recovery_generation())
	if not ok: return _fail(adapter.last_error)
	for ack in packet.acks:
		if adapter.is_retired_action(ack.id): continue
		if not _confirmed.has(ack.id):
			_confirmed[ack.id] = true
			action_confirmed.emit(ack.id, ack.kind, ack.requested_tick, ack.applied_tick)
		_emit_effect_once(ack.id, ack.kind)
	last_error = ""
	return true

func _on_effect(id: int, kind: String) -> void:
	_emit_effect_once(id, kind)

func _emit_effect_once(id: int, kind: String) -> void:
	if adapter.is_retired_action(id): return
	if _effects.has(id): return
	_effects[id] = true
	effect_ready.emit(id, kind)

func recorded_frame(tick: int) -> Dictionary:
	return _frames.get(tick, {}).duplicate(true)

func actor_state_at(tick: int) -> PackedByteArray:
	return _states.get(tick, PackedByteArray()).duplicate()

func stats() -> Dictionary:
	return {"ticks": _frames.size(), "bytes": _bytes, "actor_tick": _actor_tick,
		"oldest": _frames.keys().min() if not _frames.is_empty() else -1,
		"confirmed": _confirmed.size(), "effects": _effects.size(), "replay_callbacks": replay_callbacks}

func _trim() -> void:
	while _frames.size() > HISTORY_TICKS or _bytes > HISTORY_BYTES:
		var oldest: int = _frames.keys().min()
		_bytes -= var_to_bytes(_frames[oldest]).size() + _states[oldest].size()
		_frames.erase(oldest); _states.erase(oldest)
	if not _frames.is_empty():
		var oldest: int = _frames.keys().min()
		for tick in _commands.keys():
			if tick < oldest: _commands.erase(tick)
	var expired: Array = []
	for id in _known_actions.keys():
		if adapter.is_retired_action(id):
			if not _confirmed.has(id): expired.append(_known_actions[id])
			_known_actions.erase(id); _effects.erase(id); _confirmed.erase(id)
	# Finish cleanup before callbacks: a listener may query or re-enter the API.
	for command in expired:
		action_expired.emit(command.id, command.kind, command.tick)

func _reset_history() -> void:
	_frames.clear(); _states.clear(); _pending_inputs.clear(); _commands.clear(); _bytes = 0
	_actor_tick = -1
	actor_baseline_ready = false
	authority_needed.emit("actor_baseline_required")

func _intent_bytes(input: ActorInput) -> PackedByteArray:
	if input == null or not is_finite(input.look_yaw) or not input.is_possible(): return PackedByteArray()
	var b := StreamPeerBuffer.new(); input.write_to(b)
	if b.data_array.size() > adapter.MAX_INPUT_BYTES: return PackedByteArray()
	var copy := _read_input(b.data_array)
	if copy == null or not copy.is_possible(): return PackedByteArray()
	if not copy.hold.is_empty() and copy.hold_session() != adapter.authority_scope().hold_session: return PackedByteArray()
	if not copy.hold.is_empty():
		var q := Quaternion(copy.hold[3] / ActorInput.ROTATION_STEPS, copy.hold[4] / ActorInput.ROTATION_STEPS,
			copy.hold[5] / ActorInput.ROTATION_STEPS, copy.hold[6] / ActorInput.ROTATION_STEPS)
		if not q.is_finite() or absf(q.length_squared() - 1.0) > 0.001: return PackedByteArray()
	copy.held_claim = PackedByteArray()
	b = StreamPeerBuffer.new(); copy.write_to(b)
	return b.data_array

func _read_input(bytes: PackedByteArray) -> ActorInput:
	var b := StreamPeerBuffer.new(); b.data_array = bytes
	var input := ActorInput.read_from(b)
	return input if b.get_available_bytes() == 0 else null

func _fail(reason: String) -> bool:
	last_error = reason
	return false
