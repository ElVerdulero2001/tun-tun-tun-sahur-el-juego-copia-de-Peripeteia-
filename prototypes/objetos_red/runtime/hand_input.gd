extends RefCounted

## Entradas inmutables por tick. Redundancia acotada, sin objetos Variant ni
## recursos en el cable. Este formato tiene su versión propia; no cambia el
## formato de snapshots (State.VERSION).
const MAGIC := 0x4849
const VERSION := 1
const REDUNDANCY := 6
const HEADER_BYTES := 4
const FRAME_BYTES := 44
const MAX_PACKET_BYTES := HEADER_BYTES + REDUNDANCY * FRAME_BYTES
const MAX_ID := 0x7FFFFFFF

static func valid(frame: Dictionary) -> bool:
	if frame.size() != 5: return false
	for key in ["uid", "epoch", "session", "tick"]:
		if typeof(frame.get(key)) != TYPE_INT or frame[key] < 0 or frame[key] > MAX_ID:
			return false
	return frame.uid > 0 and frame.epoch > 0 and frame.session > 0 \
		and typeof(frame.get("target")) == TYPE_TRANSFORM3D and valid_target(frame.target)

static func valid_target(target: Transform3D) -> bool:
	return target.origin.is_finite() and target.basis.is_finite() \
		and absf(target.basis.determinant() - 1.0) < 0.01 \
		and target.basis.is_equal_approx(target.basis.orthonormalized())

static func encode(frames: Array) -> PackedByteArray:
	if frames.is_empty() or frames.size() > REDUNDANCY: return PackedByteArray()
	var b := StreamPeerBuffer.new()
	b.put_u16(MAGIC)
	b.put_u8(VERSION)
	b.put_u8(frames.size())
	for frame in frames:
		if typeof(frame) != TYPE_DICTIONARY or not valid(frame): return PackedByteArray()
		for value in [frame.uid, frame.epoch, frame.session, frame.tick]: b.put_u32(value)
		for value in [frame.target.origin.x, frame.target.origin.y, frame.target.origin.z]: b.put_float(value)
		var q: Quaternion = frame.target.basis.get_rotation_quaternion()
		for value in [q.x, q.y, q.z, q.w]: b.put_float(value)
	return b.data_array

static func decode(bytes: PackedByteArray) -> Array:
	if bytes.size() < HEADER_BYTES or bytes.size() > MAX_PACKET_BYTES: return []
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	if b.get_u16() != MAGIC or b.get_u8() != VERSION: return []
	var count := b.get_u8()
	if count == 0 or count > REDUNDANCY or bytes.size() != HEADER_BYTES + count * FRAME_BYTES: return []
	var frames: Array = []
	for _index in count:
		var frame := {"uid": b.get_u32(), "epoch": b.get_u32(), "session": b.get_u32(), "tick": b.get_u32()}
		var position := Vector3(b.get_float(), b.get_float(), b.get_float())
		var q := Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float())
		if not q.is_finite() or absf(q.length_squared() - 1.0) > 0.01: return []
		frame["target"] = Transform3D(Basis(q.normalized()), position)
		if not valid(frame): return []
		frames.append(frame)
	return frames
