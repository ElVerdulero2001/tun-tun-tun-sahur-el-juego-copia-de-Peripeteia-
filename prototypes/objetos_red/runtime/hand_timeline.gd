extends RefCounted

## Bandeja acotada anterior a la concesión. Recibir una entrada no concede
## propiedad: solo la autoridad que consume(peer, uid, epoch, session) puede
## elegirla para un cuerpo. Los dos canales pueden llegar en cualquier orden.
const InputFrame := preload("res://runtime/hand_input.gd")
const PAST_TICKS := 120
const FUTURE_TICKS := 60
const MAX_SESSIONS_PER_PEER := 4
const MAX_PEERS := 2
const MAX_RETIRED := 256

var _slots := {}
var _retired := {}

func accept(peer: int, frame: Dictionary, now: int) -> String:
	prune(now)
	if peer <= 0 or not InputFrame.valid(frame): return "invalid"
	if frame.tick < now - PAST_TICKS or frame.tick > now + FUTURE_TICKS: return "outside_window"
	var key := _key(peer, frame.uid, frame.epoch, frame.session)
	if _retired.has(key): return "retired"
	if not _slots.has(key):
		var sessions := 0
		var peers := {}
		for slot: Dictionary in _slots.values():
			peers[slot.peer] = true
			if slot.peer == peer: sessions += 1
		if sessions >= MAX_SESSIONS_PER_PEER or (not peers.has(peer) and peers.size() >= MAX_PEERS): return "capacity"
		_slots[key] = {"peer": peer, "frames": {}, "seen": {}}
	var frames: Dictionary = _slots[key].frames
	var seen: Dictionary = _slots[key].seen
	if seen.has(frame.tick):
		return "duplicate" if seen[frame.tick].is_equal_approx(frame.target) else "conflicting_tick"
	frames[frame.tick] = frame.duplicate(true)
	seen[frame.tick] = frame.target
	return "buffered"

func consume(peer: int, uid: int, epoch: int, session: int, now: int, last_used: int) -> Dictionary:
	prune(now)
	var key := _key(peer, uid, epoch, session)
	if not _slots.has(key): return {}
	var frames: Dictionary = _slots[key].frames
	var chosen := -1
	for input_tick: int in frames:
		if input_tick <= now and input_tick > last_used: chosen = maxi(chosen, input_tick)
	var result: Dictionary = frames[chosen].duplicate(true) if chosen >= 0 else {}
	for input_tick: int in frames.keys():
		if input_tick <= now: frames.erase(input_tick)
	return result

func retire(peer: int, uid: int, epoch: int, session: int, now: int) -> void:
	var key := _key(peer, uid, epoch, session)
	_slots.erase(key)
	_retired[key] = now + PAST_TICKS
	while _retired.size() > MAX_RETIRED: _retired.erase(_retired.keys()[0])

func drop_peer(peer: int) -> void:
	for key: String in _slots.keys():
		if _slots[key].peer == peer: _slots.erase(key)

func pending_for(peer: int, uid: int, epoch: int, session: int) -> Dictionary:
	# Vista de inspección compatible con el driver anterior; nunca es una
	# segunda cola de ejecución ni permite modificar la bandeja canónica.
	var key := _key(peer, uid, epoch, session)
	var result := {}
	if _slots.has(key):
		for input_tick: int in _slots[key].frames:
			result[input_tick] = _slots[key].frames[input_tick].target
	return result

func prune(now: int) -> void:
	for key: String in _retired.keys():
		if _retired[key] < now: _retired.erase(key)
	for key: String in _slots.keys():
		var frames: Dictionary = _slots[key].frames
		var seen: Dictionary = _slots[key].seen
		for input_tick: int in frames.keys():
			if input_tick < now - PAST_TICKS: frames.erase(input_tick)
		for input_tick: int in seen.keys():
			if input_tick < now - PAST_TICKS: seen.erase(input_tick)
		if frames.is_empty() and seen.is_empty(): _slots.erase(key)

static func _key(peer: int, uid: int, epoch: int, session: int) -> String:
	return "%d:%d:%d:%d" % [peer, uid, epoch, session]
