extends "res://prototypes/objetos_adaptador/authority_channel.gd"

## Canal de la pista. Los pedidos, el vínculo y la reserva para estados grandes
## usan ENet fiable. Los estados comprimidos normales van por un canal de
## snapshots que puede descartar un estado incompleto y recibir el siguiente.
## El simulador del laboratorio aplica pérdidas y demoras al flujo de estados.

const STREAM_PART_BYTES := 1080
const STREAM_PART_LIMIT := 4
const STREAM_REVISIONS := 8

var link: LinkSimulator
var _live_parts := {}
var _live_high_revision := 0


func _later(packet: Callable) -> void:
	if link != null:
		link.deliver_reliable(packet)
	else:
		packet.call()


func _valid_control_from(sender: int, data: PackedByteArray) -> bool:
	if not _bound or sender != _peer or data.size() != 52:
		return false
	var b := StreamPeerBuffer.new()
	b.data_array = data
	return _read_scope(b, _scope)


@rpc("any_peer", "call_remote", "reliable", 0)
func _remote_close(data: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_later(func() -> void:
		if _valid_control_from(sender, data):
			last_error = "peer_closed"
			stop(false))


@rpc("any_peer", "call_remote", "reliable", 0)
func _heartbeat(data: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_later(func() -> void:
		if _valid_control_from(sender, data):
			_peer_active = true
			_last_peer_activity = Time.get_ticks_msec())


@rpc("any_peer", "call_remote", "reliable", 1)
func _transfer_ack(id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_later(func() -> void:
		if not _bound or not _sender or sender != _peer or _tx.is_empty():
			return
		if id != _tx.id or not _tx.awaiting_ack:
			return
		_last_peer_activity = Time.get_ticks_msec()
		_peer_active = true
		transfer_acks += 1
		_tx.clear())


@rpc("authority", "call_remote", "reliable", 1)
func _receive_chunk(data: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_later(func() -> void:
		if _bound and not _sender and sender == _peer:
			_peer_active = true
			_last_peer_activity = Time.get_ticks_msec()
		accept_host_chunk(sender, data, true))


## Como el del canal base, pero el pedido sale por el simulador de red.
func request_action(action: Dictionary) -> bool:
	if not _bound or _sender:
		return _fail("not_action_client")
	if not _valid_action(action):
		return _fail("invalid_action")
	var b := StreamPeerBuffer.new()
	_write_scope(b, _scope)
	b.put_u32(action.id)
	b.put_u32(action.tick)
	b.put_u8(1 if action.kind == "grab" else 2)
	for v: Vector3 in [action.anchor, action.impulse]:
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
	_peer_active = true
	var data := b.data_array
	_later(func() -> void:
		if _bound and _can_send():
			_submit_action.rpc_id(1, data))
	return true


@rpc("any_peer", "call_remote", "reliable", 1)
func _submit_action(data: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_later(func() -> void:
		if not _bound or not _sender or sender != _peer or data.size() != 85:
			return
		var b := StreamPeerBuffer.new()
		b.data_array = data
		if not _read_scope(b, _scope):
			return
		var id := b.get_u32()
		var tick := b.get_u32()
		var kind := b.get_u8()
		var action := {"id": id, "tick": tick, "kind": "grab" if kind == 1 else "release",
			"anchor": Vector3(b.get_float(), b.get_float(), b.get_float()),
			"impulse": Vector3(b.get_float(), b.get_float(), b.get_float())}
		if kind not in [1, 2] or not _valid_action(action):
			return
		_last_peer_activity = Time.get_ticks_msec()
		_peer_active = true
		action_requested.emit(action))

func _process(delta: float) -> void:
	if _bound and _sender and not _next_packet.is_empty() and _tx.is_empty():
		var payload := _next_packet
		var compressed := payload.compress(FileAccess.COMPRESSION_DEFLATE)
		if not compressed.is_empty() and compressed.size() <= STREAM_PART_BYTES * STREAM_PART_LIMIT:
			_send_live_state(compressed, _last_sent_revision)
			_next_packet = PackedByteArray()
	super._process(delta)


func _send_live_state(compressed: PackedByteArray, revision: int) -> void:
	_peer_active = true
	var total := compressed.size()
	var parts := ceili(float(total) / STREAM_PART_BYTES)
	var connection: int = _scope.connection
	for index in parts:
		var bytes := compressed.slice(index * STREAM_PART_BYTES, (index + 1) * STREAM_PART_BYTES)
		max_wire_bytes = maxi(max_wire_bytes, bytes.size())
		_through_stream(func() -> void:
			if _bound and _can_send():
				_receive_live_part.rpc_id(_peer, connection, revision, total, index, bytes)
				sent_chunks += 1)


func _through_stream(packet: Callable) -> void:
	if link != null:
		link.deliver(packet)
	else:
		packet.call()


@rpc("authority", "call_remote", "unreliable", 2)
func _receive_live_part(connection: int, revision: int, total: int, index: int, bytes: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if bytes.is_empty() or bytes.size() > STREAM_PART_BYTES:
		return
	_through_stream(_accept_live_part.bind(sender, connection, revision, total, index, bytes))


func _accept_live_part(sender: int, connection: int, revision: int, total: int, index: int, bytes: PackedByteArray) -> void:
	if not _bound or _sender or sender != _peer or sender not in multiplayer.get_peers() or connection != _scope.connection:
		return
	if revision <= _last_revision or revision > 0x7FFFFFFF or revision <= _live_high_revision - STREAM_REVISIONS:
		return
	if total < 1 or total > STREAM_PART_BYTES * STREAM_PART_LIMIT:
		return
	var count := ceili(float(total) / STREAM_PART_BYTES)
	if index < 0 or index >= count or bytes.size() != mini(STREAM_PART_BYTES, total - index * STREAM_PART_BYTES):
		return
	_live_high_revision = maxi(_live_high_revision, revision)
	for old in _live_parts.keys():
		if old <= _last_revision or old <= _live_high_revision - STREAM_REVISIONS:
			_live_parts.erase(old)
	var entry: Dictionary = _live_parts.get_or_add(revision, {"total": total, "parts": {}})
	if entry.total != total:
		return
	if entry.parts.has(index):
		return
	entry.parts[index] = bytes
	received_chunks += 1
	if entry.parts.size() < count:
		return
	var compressed := PackedByteArray()
	for part in count:
		compressed.append_array(entry.parts[part])
	_live_parts.erase(revision)
	var payload := compressed.decompress_dynamic(MAX_BYTES, FileAccess.COMPRESSION_DEFLATE)
	var packet := decode_packet(payload, _scope)
	if packet.is_empty() or packet.revision != revision or packet.tick < _last_tick:
		return
	_peer_active = true
	_last_peer_activity = Time.get_ticks_msec()
	_last_revision = packet.revision
	_last_tick = packet.tick
	_pending = packet
	completed += 1
	packet_available.emit()
