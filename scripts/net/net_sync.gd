class_name NetSync
extends Node

## Transporte del paso 4. El cliente manda el input de cada tick; el host mueve
## a todos y manda el estado de todos los actores. Todavía sin predicción: el
## cliente muestra exactamente lo que dice el host, con la demora de la red.
## La predicción (paso 6) se apoya en estos mismos mensajes. Desde el paso 7,
## junto a cada input viaja la afirmación: el estado que el cliente predijo
## para ese tick.

## Ticks que viajan en cada paquete: si se pierde uno, el siguiente trae los
## mismos ticks otra vez.
const INPUT_REDUNDANCY := 6
## Cada cuántos ticks manda el host un snapshot: con 2 son 30 por segundo. Los
## demás jugadores se ven parejos igual porque se interpolan (paso 8).
const SNAPSHOT_INTERVAL_TICKS := 2
## Cuánta historia de input guarda el host por jugador, en ticks.
const INPUT_HISTORY_TICKS := 120
## Cuantización de la pose de las bases del host en el snapshot.
const BASE_POSITION_STEP := 0.0001
const BASE_VELOCITY_STEP := 0.001
## Cuantización del impulso de un evento programado.
const IMPULSE_STEP := 0.001

## Simulador de red (paso 5). Todo lo que se manda o se recibe pasa por acá.
var link: LinkSimulator
## Cliente: tick del último snapshot aplicado.
var latest_snapshot_tick := -1
## Cliente: último tick de input propio que el host usó, según el snapshot.
var acked_input_tick := -1
## Cliente: snapshots aceptados y snapshots que nunca llegaron a tiempo.
var snapshots_received := 0
var snapshots_missing := 0
## Cliente: eventos programados que llegaron y todavía no tomó el juego, como
## [tick, impulso, fuerza].
var received_events: Array = []

# Cliente
var _pending_snapshot := PackedByteArray()
var _pending_snapshot_tick := -1
# Host
var _inputs := {}  # peer -> {tick: ActorInput}
var _claims := {}  # peer -> {tick: estado afirmado, en bytes}
var _latest_input := {}  # peer -> ActorInput con el tick más alto recibido
var _used_input_tick := {}  # peer -> tick del input usado en el último tick simulado
var _peer_rtt_ms := {}  # peer -> ida y vuelta que midió ese cliente, en ms


func _ready() -> void:
	multiplayer.peer_disconnected.connect(forget_peer)


# --- Cliente ---------------------------------------------------------------

## Manda al host los ticks predichos más recientes: por cada uno, el input y
## la afirmación ([ActorInput, estado en bytes], del más viejo al más nuevo).
## Adelante va la ida y vuelta que mide el cliente: con eso el host calcula
## con cuánta anticipación programar un evento para él.
func send_ticks(records: Array, rtt_ms: float) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u16(clampi(roundi(rtt_ms), 0, 65535))
	b.put_u8(records.size())
	for record in records:
		var claim: PackedByteArray = record[1]
		record[0].write_to(b)
		b.put_u8(claim.size())
		b.put_data(claim)
	var data := b.data_array
	_send(func() -> void: _submit_inputs.rpc_id(1, data))


## Aplica el snapshot más nuevo que llegó desde el tick anterior. Se llama
## dentro del tick de física para no romper la interpolación. El estado propio
## va a `on_own_state` (tick del host, estado en bytes, tick del input usado,
## margen del input) para que la predicción lo compare y corrija; el de cada
## otro jugador, a `on_other_state` (id, tick del host, ActorState); y el de
## cada base que simula el host, a `on_base_state` (id, tick del host,
## posición, velocidad).
func apply_pending_snapshot(on_own_state: Callable, on_other_state: Callable, on_base_state: Callable) -> void:
	if _pending_snapshot.is_empty():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = _pending_snapshot
	_pending_snapshot = PackedByteArray()
	latest_snapshot_tick = b.get_32()
	var count := b.get_u8()
	for i in count:
		var owner_id := b.get_32()
		var used_tick := b.get_32()
		var margin := b.get_16()
		var length := b.get_u8()
		var state_bytes: PackedByteArray = b.get_data(length)[1]
		if owner_id == multiplayer.get_unique_id():
			acked_input_tick = used_tick
			on_own_state.call(latest_snapshot_tick, state_bytes, used_tick, margin)
		else:
			on_other_state.call(owner_id, latest_snapshot_tick, ActorState.from_bytes(state_bytes))
	var base_count := b.get_u8()
	for i in base_count:
		var base_id := b.get_u16()
		var position := _get_vector(b, BASE_POSITION_STEP)
		var velocity := _get_vector(b, BASE_VELOCITY_STEP)
		on_base_state.call(base_id, latest_snapshot_tick, position, velocity)


@rpc("authority", "call_remote", "unreliable")
func _receive_snapshot(data: PackedByteArray) -> void:
	_receive(_accept_snapshot.bind(data))


func _accept_snapshot(data: PackedByteArray) -> void:
	# Los paquetes pueden llegar desordenados: solo cuenta el más nuevo.
	var tick := data.decode_s32(0)
	if tick <= _pending_snapshot_tick or tick <= latest_snapshot_tick:
		return
	var newest_known := maxi(_pending_snapshot_tick, latest_snapshot_tick)
	if newest_known >= 0:
		@warning_ignore("integer_division")
		snapshots_missing += maxi(tick - newest_known - SNAPSHOT_INTERVAL_TICKS, 0) / SNAPSHOT_INTERVAL_TICKS
	snapshots_received += 1
	_pending_snapshot = data
	_pending_snapshot_tick = tick


# --- Host ------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable")
func _submit_inputs(data: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	# El remitente solo se puede leer ahora, dentro de la llamada remota.
	_receive(_accept_inputs.bind(multiplayer.get_remote_sender_id(), data))


func _accept_inputs(peer_id: int, data: PackedByteArray) -> void:
	if not _inputs.has(peer_id):
		_inputs[peer_id] = {}
		_claims[peer_id] = {}
	var by_tick: Dictionary = _inputs[peer_id]
	var claims: Dictionary = _claims[peer_id]
	var b := StreamPeerBuffer.new()
	b.data_array = data
	_peer_rtt_ms[peer_id] = float(b.get_u16())
	var count := b.get_u8()
	for i in count:
		var input := ActorInput.read_from(b)
		var claim: PackedByteArray = b.get_data(b.get_u8())[1]
		by_tick[input.tick] = input
		if claim.size() == ActorState.BYTE_SIZE:
			claims[input.tick] = claim
		var latest: ActorInput = _latest_input.get(peer_id)
		if latest == null or input.tick > latest.tick:
			_latest_input[peer_id] = input


## Input de un jugador remoto para un tick del host, o null si nunca llegó
## ninguno. Si falta el de ese tick, se repite el último anterior: mismos
## botones mantenidos y mismo contador de pulsaciones, así no se inventa ni se
## duplica un salto.
func input_for(peer_id: int, tick: int) -> ActorInput:
	var by_tick: Dictionary = _inputs.get(peer_id, {})
	var chosen: ActorInput = by_tick.get(tick)
	if chosen == null:
		for t in by_tick:
			if t <= tick and (chosen == null or t > chosen.tick):
				chosen = by_tick[t]
	var claims: Dictionary = _claims.get(peer_id, {})
	for t in by_tick.keys():
		if t < tick - INPUT_HISTORY_TICKS:
			by_tick.erase(t)
			claims.erase(t)
	if chosen == null:
		return null
	_used_input_tick[peer_id] = chosen.tick
	return ActorInput.make(tick, chosen.move, chosen.look_yaw, chosen.buttons, chosen.jump_presses)


## Lo que el jugador afirma haber predicho para ese tick exacto, en bytes, o
## vacío si no llegó (o llegó tarde y ya no sirve).
func claim_for(peer_id: int, tick: int) -> PackedByteArray:
	return _claims.get(peer_id, {}).get(tick, PackedByteArray())


## Cuántos ticks por delante de este llegó el input más nuevo de un jugador.
## Negativo = está llegando tarde. Cero si todavía no mandó nada.
func input_margin_ticks(peer_id: int, tick: int) -> int:
	var latest: ActorInput = _latest_input.get(peer_id)
	return latest.tick - tick if latest != null else 0


## La ida y vuelta que dice medir un jugador, en ms (con la red simulada incluida).
func peer_rtt_ms(peer_id: int) -> float:
	return _peer_rtt_ms.get(peer_id, 0.0)


## Host: anuncia a un jugador un evento programado, un impulso con su fuerza
## para el tick `tick`. Va por un canal confiable: no se puede perder.
func send_scheduled_event(peer_id: int, tick: int, impulse: Vector3, force: int) -> void:
	var b := StreamPeerBuffer.new()
	b.put_32(tick)
	_put_vector(b, impulse, IMPULSE_STEP)
	b.put_u8(force)
	var data := b.data_array
	_send_reliable(func() -> void: _receive_scheduled_event.rpc_id(peer_id, data))


## Cliente: lo que se recibió con el impulso ya cuantizado, como lo usa el host.
static func quantize_impulse(impulse: Vector3) -> Vector3:
	var b := StreamPeerBuffer.new()
	_put_vector(b, impulse, IMPULSE_STEP)
	b.seek(0)
	return _get_vector(b, IMPULSE_STEP)


@rpc("authority", "call_remote", "reliable")
func _receive_scheduled_event(data: PackedByteArray) -> void:
	_receive_reliable(_accept_scheduled_event.bind(data))


func _accept_scheduled_event(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var tick := b.get_32()
	var impulse := _get_vector(b, IMPULSE_STEP)
	var force := b.get_u8()
	received_events.append([tick, impulse, force])


## Manda a todos los clientes el estado de todos los actores en este tick, y la
## pose de las bases que simula solo el host (balsas). Las plataformas
## guionadas no viajan: cada máquina las calcula desde el tick.
func send_snapshot(tick: int, actors: Array[ActorBody], host_bases: Array) -> void:
	if tick % SNAPSHOT_INTERVAL_TICKS != 0 or multiplayer.get_peers().is_empty():
		return
	var b := StreamPeerBuffer.new()
	b.put_32(tick)
	b.put_u8(actors.size())
	for actor in actors:
		var state_bytes := actor.state.to_bytes()
		# Margen: cuántos ticks por delante de este llegó el input más nuevo del
		# jugador. Negativo = llegó tarde y hubo que repetir uno viejo.
		var latest: ActorInput = _latest_input.get(actor.owner_peer_id)
		var margin := latest.tick - tick if latest != null else 0
		b.put_32(actor.owner_peer_id)
		b.put_32(_used_input_tick.get(actor.owner_peer_id, -1))
		b.put_16(clampi(margin, -32768, 32767))
		b.put_u8(state_bytes.size())
		b.put_data(state_bytes)
	b.put_u8(host_bases.size())
	for base in host_bases:
		b.put_u16(base.base_id)
		_put_vector(b, base.base_origin(), BASE_POSITION_STEP)
		_put_vector(b, base.base_velocity(), BASE_VELOCITY_STEP)
	var data := b.data_array
	_send(func() -> void: _receive_snapshot.rpc(data))


static func _put_vector(b: StreamPeerBuffer, v: Vector3, step: float) -> void:
	b.put_32(roundi(v.x / step))
	b.put_32(roundi(v.y / step))
	b.put_32(roundi(v.z / step))


static func _get_vector(b: StreamPeerBuffer, step: float) -> Vector3:
	var x := b.get_32() * step
	var y := b.get_32() * step
	var z := b.get_32() * step
	return Vector3(x, y, z)


func forget_peer(peer_id: int) -> void:
	_inputs.erase(peer_id)
	_claims.erase(peer_id)
	_latest_input.erase(peer_id)
	_used_input_tick.erase(peer_id)
	_peer_rtt_ms.erase(peer_id)


# --- Paso por el simulador de red -------------------------------------------

## Manda un paquete pasando por el simulador. Si cuando sale ya no hay
## conexión (por ejemplo, el host se fue mientras viajaba), se descarta.
func _send(packet: Callable) -> void:
	var guarded := func() -> void:
		if _is_connected():
			packet.call()
	if link != null:
		link.deliver(guarded)
	else:
		guarded.call()


## Procesa un paquete recibido pasando por el simulador.
func _receive(packet: Callable) -> void:
	if link != null:
		link.deliver(packet)
	else:
		packet.call()


## Como _send() y _receive(), para el canal confiable: el simulador lo demora
## pero no lo pierde, igual que ENet, que reenvía lo confiable hasta que llega.
func _send_reliable(packet: Callable) -> void:
	var guarded := func() -> void:
		if _is_connected():
			packet.call()
	if link != null:
		link.deliver_reliable(guarded)
	else:
		guarded.call()


func _receive_reliable(packet: Callable) -> void:
	if link != null:
		link.deliver_reliable(packet)
	else:
		packet.call()


func _is_connected() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
