extends RefCounted

## Una instancia por objeto y sesión del servidor. El adaptador conserva las
## validaciones geométricas y del personaje; este componente ordena acciones.
const State := preload("res://runtime/state.gd")
const RESULT_LIMIT := 256
const MAX_FUTURE := 60

var state = State.new()
var pending := {}
var pending_exit := {} # Depende de la concesión del grab pendiente de la misma sesión.
var _results := {}
var _latest := {} # Conexión -> ID mayor recibido. No se reutiliza al reconectar.

func request(peer: int, command: Dictionary, now: int) -> Dictionary:
	if not valid_command(command):
		return {"status": "invalid"}
	var action: int = command.action
	var key := "%d:%d" % [peer, action]
	if _results.has(key):
		return _results[key].duplicate(true)
	if pending.get("key", "") == key:
		return {"status": "pending"}
	if pending_exit.get("key", "") == key:
		return {"status": "pending"}
	if action <= int(_latest.get(peer, 0)):
		return {"status": "stale"}
	_latest[peer] = action
	var reason := ""
	if command.uid != state.uid or command.epoch != state.epoch:
		reason = "identity"
	elif command.tick > now + MAX_FUTURE:
		reason = "future"
	elif command.op == "grab":
		if state.phase != State.Phase.FREE or not pending.is_empty():
			reason = "occupied"
	else:
		var owns_now: bool = state.phase == State.Phase.HELD and state.owner == peer and state.session == command.session
		var owns_pending: bool = not pending.is_empty() and pending.peer == peer \
			and pending.command.op == "grab" and pending.command.session == command.session
		if not owns_now and not owns_pending:
			reason = "ownership"
		elif not pending_exit.is_empty() or (not pending.is_empty() and not owns_pending):
			reason = "pending"
	if not reason.is_empty():
		return _remember(key, {"status": "rejected", "reason": reason, "action": action})
	# RELEASE/THROW van después del último tick sostenido, nunca antes.
	var due := maxi(now, int(command.tick) + 1)
	var job := {"key": key, "peer": peer, "command": command.duplicate(true), "due": due}
	if command.op != "grab" and not pending.is_empty():
		pending_exit = job
	else:
		pending = job
	return {"status": "pending"}

func commit(now: int) -> Dictionary:
	if pending.is_empty() or now < int(pending.due):
		return {}
	var job := pending
	pending = pending_exit
	pending_exit = {}
	var command: Dictionary = job.command
	state.revision += 1
	state.action = command.action
	state.applied_tick = now
	state.sleeping = false
	if command.op == "grab":
		state.phase = State.Phase.HELD
		state.owner = job.peer
		state.session = command.session
	else:
		state.phase = State.Phase.FREE
		state.owner = 0
		state.session = 0
	return {"peer": job.peer, "command": command, "key": job.key,
		"late": now > int(command.tick) + 1}

func remember_commit(job: Dictionary, packet: PackedByteArray) -> Dictionary:
	return _remember(job.key, {"status": "accepted", "action": job.command.action,
		"late": job.late, "state": packet})

func release_peer(peer: int, now: int) -> bool:
	if not pending.is_empty() and pending.peer == peer:
		pending = {}
	if not pending_exit.is_empty() and pending_exit.peer == peer:
		pending_exit = {}
	if state.owner != peer:
		return false
	state.phase = State.Phase.FREE
	state.owner = 0
	state.session = 0
	state.revision += 1
	state.applied_tick = now
	state.action = 0
	return true

func _remember(key: String, result: Dictionary) -> Dictionary:
	_results[key] = result.duplicate(true)
	while _results.size() > RESULT_LIMIT:
		_results.erase(_results.keys()[0])
	return result

static func valid_command(c: Dictionary) -> bool:
	if c.size() != 9:
		return false
	for key in ["uid", "epoch", "session", "action", "tick"]:
		if typeof(c.get(key)) != TYPE_INT or c[key] < 0 or c[key] > State.MAX_ID:
			return false
	return c.uid > 0 and c.epoch > 0 and c.action > 0 and c.session > 0 \
		and typeof(c.get("op")) == TYPE_STRING and c.op in ["grab", "release", "throw"] \
		and typeof(c.get("target")) == TYPE_TRANSFORM3D and c.target.origin.is_finite() \
		and c.target.basis.is_finite() and absf(c.target.basis.determinant() - 1.0) < 0.01 \
		and typeof(c.get("anchor")) == TYPE_VECTOR3 and c.anchor.is_finite() \
		and typeof(c.get("direction")) == TYPE_VECTOR3 and c.direction.is_finite() \
		and (c.op != "throw" or absf(c.direction.length_squared() - 1.0) < 0.01)
