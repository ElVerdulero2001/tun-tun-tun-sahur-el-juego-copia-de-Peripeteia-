extends LinkSimulator
## Validación independiente (Claude), entrega 13: derivación del simulador de enlace
## de NetSync (API pública `NetSync.link`). No toca NetSync. Sin configurar entrega
## en el acto, como el simulador inactivo del laboratorio. Para cada Callable que
## NetSync le pasa anota el método ligado, sus argumentos y el remitente del RPC
## en curso; lo anota otra vez cuando de verdad lo ejecuta (después de la demora).
## Puede retener los anuncios confiables de cámara lenta hasta que se los suelte.

var notes: Array = []  # [{"at": ms, "phase": "in"|"run", "method", "sender", "tick", ...}]
var hold_world_slow := false
var held: Array = []
var executed_snapshots: Array = []  # ticks, en el orden en que NetSync los ejecutó
var executed_slow: Array = []  # [start, end, steps]
var own_peer := 0

func deliver(packet: Callable) -> void:
	var info := _describe(packet)
	if info.is_empty():
		super.deliver(packet)
		return
	info.phase = "in"; notes.append(info)
	super.deliver(_wrap(packet, info))

func deliver_reliable(packet: Callable) -> void:
	var info := _describe(packet)
	if info.is_empty():
		super.deliver_reliable(packet)
		return
	info.phase = "in"; notes.append(info)
	if hold_world_slow and info.method == "_accept_world_slow":
		held.append([packet, info])
		return
	super.deliver_reliable(_wrap(packet, info))

func release_held() -> int:
	var count := held.size()
	var list := held
	held = []
	for item in list:
		super.deliver_reliable(_wrap(item[0], item[1]))
	return count

func _wrap(packet: Callable, info: Dictionary) -> Callable:
	return func() -> void:
		var run := info.duplicate(true)
		run.phase = "run"; run.at = Time.get_ticks_msec()
		notes.append(run)
		if info.method == "_accept_snapshot": executed_snapshots.append(info.tick)
		elif info.method == "_accept_world_slow": executed_slow.append([info.start, info.end, info.steps])
		packet.call()

## Solo describe lo que NetSync recibe: métodos ligados con bytes. Lo que manda
## (lambdas sin argumentos ligados) pasa sin anotar.
func _describe(packet: Callable) -> Dictionary:
	var method := String(packet.get_method())
	var args := packet.get_bound_arguments()
	if method not in ["_accept_snapshot", "_accept_world_slow", "_accept_scheduled_event"] or args.is_empty() \
		or typeof(args[-1]) != TYPE_PACKED_BYTE_ARRAY:
		return {}
	var data: PackedByteArray = args[-1]
	var info := {"at": Time.get_ticks_msec(), "method": method, "sender": multiplayer.get_remote_sender_id(),
		"bytes": data.size(), "sha": _sha(data)}
	if method == "_accept_snapshot" and data.size() >= 5:
		info.tick = data.decode_s32(0)
		info.merge(_own_state(data))
	elif method == "_accept_world_slow" and data.size() >= 10:
		info.start = data.decode_s32(0); info.end = data.decode_s32(4); info.steps = data.decode_u16(8)
	return info

func _own_state(data: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new(); b.data_array = data
	b.get_32()
	var count := b.get_u8()
	for _i in count:
		var owner_id := b.get_32(); var used := b.get_32(); var margin := b.get_16(); var length := b.get_u8()
		var state: PackedByteArray = b.get_data(length)[1]
		if owner_id == own_peer:
			return {"own_sha": _sha(state), "used": used, "margin": margin}
	return {"own_sha": ""}

static func _sha(data: PackedByteArray) -> String:
	var c := HashingContext.new(); c.start(HashingContext.HASH_SHA256); c.update(data)
	return c.finish().hex_encode()
