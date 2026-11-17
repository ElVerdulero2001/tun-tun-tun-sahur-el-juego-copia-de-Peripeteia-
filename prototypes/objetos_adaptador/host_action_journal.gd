extends Node
## Host-only, scene-owned scheduler for ONE fixed granted object/peer binding.
## The channel checks sender/scope first; this journal does not grant ownership.
## Scene policy checks permissions/reach on the actual execution tick.
signal action_resolved(result: Dictionary)
const Channel = preload("res://prototypes/objetos_adaptador/authority_channel.gd")
const WINDOW := 120
const MAX_RECORDS := 256
var last_error := ""
var _adapter
var _peer := 0
var _scope := {}
var _policy: Callable
var _bound := false
var _records := {}
var _scheduled := {}
var _inflight := 0
var _max_id := 0
var _retired_id := 0
var _last_scheduled_tick := -1

func start(adapter, peer: int, policy: Callable) -> bool:
	if _adapter != null or adapter == null or not adapter.ready_for_input or peer <= 0 or not policy.is_valid():
		return _fail("invalid_binding")
	_adapter = adapter; _peer = peer; _scope = adapter.authority_scope(); _policy = policy; _bound = true
	adapter.clock.tick_finished.connect(_after_tick)
	adapter.recovery_required.connect(func(_reason: String): stop("prediction_stopped"))
	return true

## Returns copies. Duplicates retain the original outcome and never execute again.
## No callback occurs here: only execution/cancellation emits action_resolved.
func request(peer: int, action: Dictionary) -> Dictionary:
	if not _bound: return _reject("not_bound")
	if peer != _peer: return _reject("invalid_peer")
	if action.size() != 5 or not Channel._valid_action(action): return _reject("invalid_action")
	_trim(_adapter.clock.tick)
	if _records.has(action.id):
		if _records[action.id].action != action: return _reject("action_identity_conflict")
		return _records[action.id].result.duplicate(true)
	if action.id <= _retired_id: return _reject("retired_action")
	if action.id <= _max_id: return _reject("nonmonotonic_action_id")
	if not _current_binding(): return _reject("not_ready")
	var now: int = _adapter.clock.tick
	if action.tick < now - WINDOW or action.tick > now + WINDOW: return _reject("action_tick_window")
	var at := maxi(action.tick, now + 1)
	if at > 0x7FFFFFFF or _scheduled.has(at) or _records.size() >= MAX_RECORDS: return _reject("action_capacity")
	# The adapter requires increasing IDs at execution too. Never reorder a newer
	# action ahead of an already scheduled older ID, even if its requested tick is earlier.
	if at <= _last_scheduled_tick: return _reject("action_order")
	var result := {"id": action.id, "kind": action.kind, "requested_tick": action.tick,
		"scheduled_tick": at, "applied_tick": -1, "status": "scheduled", "reason": ""}
	_records[action.id] = {"action": action.duplicate(true), "result": result, "terminal_tick": -1}
	_scheduled[at] = action.id; _max_id = action.id; _last_scheduled_tick = at
	return result.duplicate(true)

## Called by host input provider BEFORE adapter.capture, with the actual tick.
func before_capture(tick: int) -> bool:
	if not _bound: return _fail("not_bound")
	if tick != _adapter.clock.tick or tick != _adapter.world.get_tick() + 1 or _inflight != 0:
		return _fail("execution_phase")
	if not _current_binding(): stop("not_ready"); return _fail("not_ready")
	for at in _scheduled.keys():
		if at < tick:
			var missed: int = _scheduled[at]; _scheduled.erase(at)
			_resolve(missed, "cancelled", "execution_tick_missed", tick)
	if not _scheduled.has(tick): return true
	var id: int = _scheduled[tick]; _scheduled.erase(tick)
	var a: Dictionary = _records[id].action
	var sample: Dictionary = _adapter.world.sample(_scope.uid, _scope.epoch)
	if sample.is_empty(): _resolve(id, "rejected", "object_missing", tick); return true
	if (a.kind == "grab" and sample.held) or (a.kind == "release" and not sample.held):
		_resolve(id, "rejected", "invalid_hand_transition", tick); return true
	# Policy returns a reason, or an empty String to allow. It is mandatory and
	# receives a copy; it must not step/re-enter this journal or mutate the world.
	var reason = _policy.call(_peer, a.duplicate(true), tick)
	if typeof(reason) != TYPE_STRING or not reason.is_empty():
		_resolve(id, "rejected", reason if typeof(reason) == TYPE_STRING else "invalid_policy_result", tick)
		return true
	if not _adapter.queue_action(tick, id, a.kind, a.anchor, a.impulse):
		_resolve(id, "rejected", _adapter.last_error, tick); return true
	_inflight = id
	return true

func _after_tick(tick: int) -> void:
	if not _bound: return
	_trim(tick)
	if _inflight == 0: return
	var id := _inflight; _inflight = 0
	if not _adapter.ready_for_input or _adapter.world.get_tick() != tick:
		_resolve(id, "cancelled", "native_step_not_completed", tick); return
	_resolve(id, "applied", "", tick)

func _resolve(id: int, status: String, reason: String, tick: int) -> void:
	var record: Dictionary = _records[id]
	if record.terminal_tick >= 0: return
	record.terminal_tick = tick
	record.result.status = status; record.result.reason = reason
	if status == "applied": record.result.applied_tick = tick
	action_resolved.emit(record.result.duplicate(true))

## At most 16 most recent physical ACKs, not an inventory transaction ledger.
func confirmations() -> Array:
	var out: Array = []
	for id in _records:
		var r: Dictionary = _records[id].result
		if r.status == "applied":
			out.append({"id": id, "kind": r.kind, "requested_tick": r.requested_tick, "applied_tick": r.applied_tick})
	out.sort_custom(func(a, b): return a.id < b.id)
	return out.slice(maxi(0, out.size() - 16)).duplicate(true)

func stop(reason := "closed") -> void:
	if not _bound: return
	_bound = false; _scheduled.clear(); _inflight = 0
	for id in _records.keys():
		if _records[id].terminal_tick < 0: _resolve(id, "cancelled", reason, _adapter.clock.tick)

func stats() -> Dictionary:
	return {"bound": _bound, "records": _records.size(), "scheduled": _scheduled.size(),
		"inflight": _inflight, "max_id": _max_id, "retired_id": _retired_id}

func _trim(tick: int) -> void:
	for id in _records.keys():
		var terminal: int = _records[id].terminal_tick
		if terminal >= 0 and terminal < tick - WINDOW:
			_retired_id = maxi(_retired_id, id); _records.erase(id)

func _current_binding() -> bool:
	return _adapter.ready_for_input and _adapter.authority_scope() == _scope

func _reject(reason: String) -> Dictionary:
	last_error = reason
	return {"status": "rejected", "reason": reason}

func _fail(reason: String) -> bool:
	last_error = reason
	return false
