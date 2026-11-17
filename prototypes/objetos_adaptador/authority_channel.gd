extends Node
## Scene-owned reliable ENet channel. Only the bound server may supply native
## bytes. Scope/digest are validation, NOT authentication or hostile-blob safety.
signal packet_available
signal action_requested(action: Dictionary)
signal closed

const MAGIC := 0x534F4231
const CHUNK_BYTES := 960
const HEADER_BYTES := 52
const MAX_BYTES := 1050000
const MAX_CHUNKS := 1094
const CHUNKS_PER_FRAME := 8
const TIMEOUT_MS := 5000
const HEARTBEAT_MS := 500
const SCOPE_FIELDS := ["connection", "context", "uid", "epoch", "hold_session"]
var last_error := ""
var sent_chunks := 0
var received_chunks := 0
var rejected_chunks := 0
var completed := 0
var transfer_acks := 0
var max_wire_bytes := 0
var _scope := {}
var _peer := 0
var _sender := false
var _bound := false
var _ever_bound := false
var _next_transfer := 0
var _high_water := 0
var _rx := {}
var _tx := {}
var _next_packet := PackedByteArray()
var _pending := {}
var _last_revision := 0
var _last_sent_revision := 0
var _last_sent_tick := -1
var _last_tick := -1
var _peer_active := false
var _last_peer_activity := 0
var _last_heartbeat := 0

func start(scope: Dictionary, target_peer: int = 1) -> bool:
	if _ever_bound or not _valid_scope(scope) or multiplayer.multiplayer_peer == null \
		or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return _fail("invalid_binding")
	_sender = multiplayer.is_server()
	if target_peer not in multiplayer.get_peers() or (_sender and target_peer == 1) or (not _sender and target_peer != 1):
		return _fail("invalid_peer")
	_scope = scope.duplicate(true); _peer = target_peer; _bound = true; _ever_bound = true
	_last_peer_activity = Time.get_ticks_msec(); _last_heartbeat = _last_peer_activity
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.server_disconnected.connect(stop)
	return true

func stop(notify_peer: bool = true) -> void:
	if not _bound: return
	# No remote control on local parser-only nodes: actual traffic establishes
	# that the peer has this RPC path. Before first traffic the 5s startup lease
	# still expires. A caller must publish/request within that initialization lease.
	if notify_peer and _peer_active and _can_send(): _remote_close.rpc_id(_peer, _control_scope())
	_bound = false; _rx.clear(); _tx.clear(); _pending.clear(); _next_packet.clear()
	closed.emit()

func _can_send() -> bool:
	return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
		and _peer in multiplayer.get_peers()

@rpc("any_peer", "call_remote", "reliable", 0)
func _remote_close(data: PackedByteArray) -> void:
	if not _valid_peer_control(data): return
	last_error = "peer_closed"; stop(false)

@rpc("any_peer", "call_remote", "unreliable", 0)
func _heartbeat(data: PackedByteArray) -> void:
	if not _valid_peer_control(data): return
	_peer_active = true; _last_peer_activity = Time.get_ticks_msec()

func _control_scope() -> PackedByteArray:
	var b := StreamPeerBuffer.new(); _write_scope(b, _scope)
	return b.data_array

func _valid_peer_control(data: PackedByteArray) -> bool:
	if not _bound or multiplayer.get_remote_sender_id() != _peer or data.size() != 52: return false
	var b := StreamPeerBuffer.new(); b.data_array = data
	return _read_scope(b, _scope)

func _peer_left(id: int) -> void:
	if id == _peer: stop()

func publish(packet: Dictionary) -> bool:
	if not _bound or not _sender: return _fail("not_authority_sender")
	var bytes := encode_packet(packet, _scope)
	if bytes.is_empty(): return _fail("invalid_packet")
	if packet.revision <= _last_sent_revision: return _fail("duplicate_revision")
	if packet.tick < _last_sent_tick: return _fail("stale_authority_tick")
	_last_sent_revision = packet.revision
	_last_sent_tick = packet.tick
	# One active transfer + one replaceable latest packet. Never enqueue snapshots
	# without limit when the producer is faster than this channel's send budget.
	_next_packet = bytes
	return true

func take_packet() -> Dictionary:
	var packet := _pending; _pending = {}
	return packet

func stats() -> Dictionary:
	return {"bound": _bound, "rx_parts": _rx.get("parts", {}).size(),
		"rx_bytes": _rx.get("bytes", 0), "pending_bytes": _pending.get("snapshot", PackedByteArray()).size(),
		"tx_bytes": _tx.get("data", PackedByteArray()).size() + _next_packet.size(),
		"sent": sent_chunks, "received": received_chunks, "rejected": rejected_chunks,
		"completed": completed, "transfer_acks": transfer_acks, "max_wire_bytes": max_wire_bytes}

func _process(_delta: float) -> void:
	if not _bound: return
	var now := Time.get_ticks_msec()
	if now - _last_peer_activity > TIMEOUT_MS:
		last_error = "peer_idle_timeout"; stop(); return
	if _peer_active and now - _last_heartbeat >= HEARTBEAT_MS and _can_send():
		_last_heartbeat = now; _heartbeat.rpc_id(_peer, _control_scope())
	if not _rx.is_empty() and Time.get_ticks_msec() - _rx.started > TIMEOUT_MS:
		_rx.clear(); last_error = "transfer_timeout"
	if not _sender: return
	if not _tx.is_empty() and Time.get_ticks_msec() - _tx.started > TIMEOUT_MS:
		last_error = "send_timeout"; stop(); return
	if _tx.is_empty() and not _next_packet.is_empty():
		_next_transfer += 1
		if _next_transfer > 0x7FFFFFFF: stop(); return
		_tx = {"id": _next_transfer, "data": _next_packet, "index": 0,
			"awaiting_ack": false, "started": Time.get_ticks_msec(),
			"digest": digest(_next_packet)}
		_next_packet = PackedByteArray()
	for _i in CHUNKS_PER_FRAME:
		if _tx.is_empty() or _tx.awaiting_ack: break
		var count := ceili(float(_tx.data.size()) / CHUNK_BYTES)
		var b := StreamPeerBuffer.new()
		b.put_u32(MAGIC); b.put_u32(_scope.connection); b.put_u32(_tx.id)
		b.put_u32(_tx.data.size()); b.put_u16(_tx.index); b.put_u16(count); b.put_data(_tx.digest)
		b.put_data(_tx.data.slice(_tx.index * CHUNK_BYTES, mini((_tx.index + 1) * CHUNK_BYTES, _tx.data.size())))
		max_wire_bytes = maxi(max_wire_bytes, b.data_array.size())
		_peer_active = true
		_receive_chunk.rpc_id(_peer, b.data_array)
		sent_chunks += 1; _tx.index += 1
		if _tx.index == count: _tx.awaiting_ack = true

@rpc("any_peer", "call_remote", "reliable", 1)
func _transfer_ack(id: int) -> void:
	if not _bound or not _sender or multiplayer.get_remote_sender_id() != _peer or _tx.is_empty(): return
	if id != _tx.id or not _tx.awaiting_ack: return
	_last_peer_activity = Time.get_ticks_msec(); _peer_active = true
	transfer_acks += 1; _tx.clear()

@rpc("authority", "call_remote", "reliable", 1)
func _receive_chunk(data: PackedByteArray) -> void:
	if _bound and not _sender and multiplayer.get_remote_sender_id() == _peer:
		_peer_active = true; _last_peer_activity = Time.get_ticks_msec()
	accept_host_chunk(multiplayer.get_remote_sender_id(), data, true)

## Also exposed as a deterministic validation seam; callers cannot bypass the
## live binding/sender check. Does not restore or deserialize any native world.
func accept_host_chunk(sender: int, data: PackedByteArray, acknowledge: bool = false) -> bool:
	if not _bound or _sender or sender != 1 or _peer != 1 or 1 not in multiplayer.get_peers():
		return _reject("unbound_sender")
	if data.size() <= HEADER_BYTES or data.size() > HEADER_BYTES + CHUNK_BYTES: return _reject("chunk_size")
	var b := StreamPeerBuffer.new(); b.data_array = data
	var magic := b.get_u32(); var connection := b.get_u32(); var id := b.get_u32()
	var total := b.get_u32(); var index := b.get_u16(); var count := b.get_u16()
	var digest: PackedByteArray = b.get_data(32)[1]
	if magic != MAGIC or connection != _scope.connection or id <= 0 or id > 0x7FFFFFFF \
		or total < 1 or total > MAX_BYTES or count < 1 or count > MAX_CHUNKS \
		or count != ceili(float(total) / CHUNK_BYTES) or index >= count \
		or b.get_available_bytes() != mini(CHUNK_BYTES, total - index * CHUNK_BYTES):
		return _reject("chunk_header")
	if id < _high_water or (id == _high_water and _rx.is_empty()): return _reject("stale_transfer")
	if id > _high_water:
		_high_water = id
		_rx = {"id": id, "total": total, "count": count, "digest": digest,
			"parts": {}, "bytes": 0, "started": Time.get_ticks_msec()}
	if _rx.total != total or _rx.count != count or _rx.digest != digest:
		_rx.clear(); return _reject("transfer_conflict")
	var part: PackedByteArray = b.get_data(b.get_available_bytes())[1]
	if _rx.parts.has(index):
		if _rx.parts[index] == part: return true
		_rx.clear(); return _reject("chunk_conflict")
	_rx.parts[index] = part; _rx.bytes += part.size(); received_chunks += 1
	if _rx.parts.size() != count: return true
	var payload := PackedByteArray()
	for i in count: payload.append_array(_rx.parts[i])
	_rx.clear()
	if digest(payload) != digest: return _reject("transfer_digest")
	var packet := decode_packet(payload, _scope)
	if packet.is_empty(): return _reject("packet_format_or_scope")
	if packet.revision <= _last_revision or packet.tick < _last_tick: return _reject("stale_authority")
	_last_revision = packet.revision; _last_tick = packet.tick
	if acknowledge: _transfer_ack.rpc_id(1, id)
	_pending = packet; completed += 1; packet_available.emit()
	return true

## Small reliable intent. The scene must still grant/check permissions and use
## an idempotent domain ledger. A guest can NEVER send a native snapshot here.
func request_action(action: Dictionary) -> bool:
	if not _bound or _sender: return _fail("not_action_client")
	if not _valid_action(action): return _fail("invalid_action")
	var b := StreamPeerBuffer.new(); _write_scope(b, _scope)
	b.put_u32(action.id); b.put_u32(action.tick); b.put_u8(1 if action.kind == "grab" else 2)
	for v: Vector3 in [action.anchor, action.impulse]:
		b.put_float(v.x); b.put_float(v.y); b.put_float(v.z)
	_peer_active = true
	_submit_action.rpc_id(1, b.data_array)
	return true

@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_action(data: PackedByteArray) -> void:
	if not _bound or not _sender or multiplayer.get_remote_sender_id() != _peer or data.size() != 85: return
	var b := StreamPeerBuffer.new(); b.data_array = data
	if not _read_scope(b, _scope): return
	var id := b.get_u32(); var tick := b.get_u32(); var kind := b.get_u8()
	var action := {"id": id, "tick": tick, "kind": "grab" if kind == 1 else "release",
		"anchor": Vector3(b.get_float(), b.get_float(), b.get_float()),
		"impulse": Vector3(b.get_float(), b.get_float(), b.get_float())}
	if kind not in [1, 2] or not _valid_action(action): return
	_last_peer_activity = Time.get_ticks_msec(); _peer_active = true
	action_requested.emit(action)

static func _valid_action(a: Dictionary) -> bool:
	return typeof(a.get("id")) == TYPE_INT and a.id > 0 and a.id <= 0x7FFFFFFF \
		and typeof(a.get("tick")) == TYPE_INT and a.tick >= 0 and a.tick <= 0x7FFFFFFF \
		and a.get("kind") in ["grab", "release"] and typeof(a.get("anchor")) == TYPE_VECTOR3 \
		and a.anchor.is_finite() and a.anchor.length() <= 1.0 and typeof(a.get("impulse")) == TYPE_VECTOR3 \
		and a.impulse.is_finite() and a.impulse.length() <= 100.0

static func _valid_scope(s: Dictionary) -> bool:
	for key in SCOPE_FIELDS:
		if typeof(s.get(key)) != TYPE_INT or s[key] < 1 or s[key] > 0x7FFFFFFF: return false
	return typeof(s.get("hand_signature")) == TYPE_STRING and s.hand_signature.length() == 64 \
		and s.hand_signature.is_valid_hex_number(false)

static func _write_scope(b: StreamPeerBuffer, scope: Dictionary) -> void:
	for key in SCOPE_FIELDS: b.put_u32(scope[key])
	b.put_data(scope.hand_signature.hex_decode())

static func _read_scope(b: StreamPeerBuffer, scope: Dictionary) -> bool:
	for key in SCOPE_FIELDS:
		if b.get_u32() != scope[key]: return false
	return b.get_data(32)[1].hex_encode() == scope.hand_signature.to_lower()

static func encode_packet(p: Dictionary, scope: Dictionary) -> PackedByteArray:
	if not _valid_scope(scope): return PackedByteArray()
	for key in SCOPE_FIELDS + ["hand_signature"]:
		if p.get(key) != scope[key]: return PackedByteArray()
	if p.get("version") != 1 or typeof(p.get("revision")) != TYPE_INT or p.revision < 1 or p.revision > 0x7FFFFFFF \
		or typeof(p.get("tick")) != TYPE_INT or p.tick < 0 or p.tick > 0x7FFFFFFF \
		or typeof(p.get("acks")) != TYPE_ARRAY or p.acks.size() > 16 \
		or typeof(p.get("snapshot")) != TYPE_PACKED_BYTE_ARRAY or p.snapshot.is_empty() or p.snapshot.size() > 1048620:
		return PackedByteArray()
	var b := StreamPeerBuffer.new(); b.put_u8(1); _write_scope(b, scope)
	b.put_u32(p.revision); b.put_u32(p.tick); b.put_u8(p.acks.size())
	var ids := {}
	for ack in p.acks:
		if typeof(ack) != TYPE_DICTIONARY or typeof(ack.get("id")) != TYPE_INT or ack.id <= 0 or ack.id > 0x7FFFFFFF \
			or ids.has(ack.id) or ack.get("kind") not in ["grab", "release"] \
			or typeof(ack.get("requested_tick")) != TYPE_INT or typeof(ack.get("applied_tick")) != TYPE_INT \
			or ack.requested_tick < 0 or ack.applied_tick < ack.requested_tick or ack.applied_tick > p.tick:
			return PackedByteArray()
		ids[ack.id] = true
		b.put_u32(ack.id); b.put_u8(1 if ack.kind == "grab" else 2)
		b.put_u32(ack.requested_tick); b.put_u32(ack.applied_tick)
	b.put_u32(p.snapshot.size()); b.put_data(p.snapshot)
	return b.data_array

static func decode_packet(data: PackedByteArray, scope: Dictionary) -> Dictionary:
	if not _valid_scope(scope) or data.size() < 66 or data.size() > MAX_BYTES: return {}
	var b := StreamPeerBuffer.new(); b.data_array = data
	if b.get_u8() != 1 or not _read_scope(b, scope): return {}
	var p := scope.duplicate(true); p.version = 1
	p.revision = b.get_u32(); p.tick = b.get_u32(); p.acks = []
	var count := b.get_u8()
	if count > 16 or b.get_available_bytes() < count * 13 + 4: return {}
	for _i in count:
		var id := b.get_u32(); var kind := b.get_u8()
		if kind not in [1, 2]: return {}
		p.acks.append({"id": id, "kind": "grab" if kind == 1 else "release",
			"requested_tick": b.get_u32(), "applied_tick": b.get_u32()})
	var length := b.get_u32()
	if length != b.get_available_bytes() or length < 1 or length > 1048620: return {}
	p.snapshot = b.get_data(length)[1]
	return p if not encode_packet(p, scope).is_empty() else {}

func _reject(reason: String) -> bool:
	rejected_chunks += 1
	return _fail(reason)

func _fail(reason: String) -> bool:
	last_error = reason
	return false

static func digest(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish()
