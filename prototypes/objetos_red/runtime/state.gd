extends RefCounted

## Estado de un paso físico COMPLETADO. El tick de aplicación de una acción
## es otro campo: su estado inicial todavía no integra ese paso.
enum Phase { FREE, HELD, REMOVED }

const MAGIC := 0x4F32
const VERSION := 1
const BYTES := 90
const MAX_ID := 0x7FFFFFFF

var uid: int = 1
var epoch: int = 1
var revision: int = 1
var tick: int = 0
var owner: int = 0
var session: int = 0
var phase: int = Phase.FREE
var sleeping: bool = false
var action: int = 0
var applied_tick: int = 0
var pose := Transform3D.IDENTITY
var lv := Vector3.ZERO
var av := Vector3.ZERO

func valid() -> bool:
	return uid > 0 and uid <= MAX_ID and epoch > 0 and epoch <= MAX_ID \
		and revision > 0 and revision <= MAX_ID and tick >= 0 and tick <= MAX_ID \
		and owner >= 0 and owner <= MAX_ID and session >= 0 and session <= MAX_ID \
		and phase >= Phase.FREE and phase <= Phase.REMOVED \
		and action >= 0 and action <= MAX_ID and applied_tick >= 0 and applied_tick <= MAX_ID \
		and pose.origin.is_finite() and pose.basis.is_finite() \
		and absf(pose.basis.determinant() - 1.0) < 0.01 \
		and lv.is_finite() and av.is_finite() \
		and ((phase == Phase.HELD and owner > 0 and session > 0) \
			or (phase != Phase.HELD and owner == 0 and session == 0))

func encode() -> PackedByteArray:
	if not valid():
		return PackedByteArray()
	var b := StreamPeerBuffer.new()
	b.put_u16(MAGIC)
	b.put_u8(VERSION)
	b.put_u8(0) # Reservado; rechazar extensiones no negociadas.
	for value in [uid, epoch, revision, tick, owner, session, action, applied_tick]:
		b.put_u32(value)
	b.put_u8(phase)
	b.put_u8(int(sleeping))
	for value in [pose.origin.x, pose.origin.y, pose.origin.z]:
		b.put_float(value)
	var q := pose.basis.orthonormalized().get_rotation_quaternion()
	for value in [q.x, q.y, q.z, q.w, lv.x, lv.y, lv.z, av.x, av.y, av.z]:
		b.put_float(value)
	return b.data_array

static func decode(bytes: PackedByteArray):
	if bytes.size() != BYTES:
		return null
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	if b.get_u16() != MAGIC or b.get_u8() != VERSION or b.get_u8() != 0:
		return null
	var out = load("res://runtime/state.gd").new()
	out.uid = b.get_u32()
	out.epoch = b.get_u32()
	out.revision = b.get_u32()
	out.tick = b.get_u32()
	out.owner = b.get_u32()
	out.session = b.get_u32()
	out.action = b.get_u32()
	out.applied_tick = b.get_u32()
	out.phase = b.get_u8()
	var asleep := b.get_u8()
	if asleep > 1:
		return null
	out.sleeping = asleep == 1
	var position := Vector3(b.get_float(), b.get_float(), b.get_float())
	var q := Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float())
	if not q.is_finite() or absf(q.length_squared() - 1.0) > 0.01:
		return null
	out.pose = Transform3D(Basis(q.normalized()), position)
	out.lv = Vector3(b.get_float(), b.get_float(), b.get_float())
	out.av = Vector3(b.get_float(), b.get_float(), b.get_float())
	return out if out.valid() else null

func copy():
	return decode(encode())

func trace() -> Dictionary:
	var q := pose.basis.orthonormalized().get_rotation_quaternion()
	return {"uid": uid, "epoch": epoch, "revision": revision, "tick": tick,
		"owner": owner, "session": session, "phase": phase, "sleep": sleeping,
		"action": action, "applied_tick": applied_tick,
		"p": [pose.origin.x, pose.origin.y, pose.origin.z], "q": [q.x, q.y, q.z, q.w],
		"lv": [lv.x, lv.y, lv.z], "av": [av.x, av.y, av.z]}
