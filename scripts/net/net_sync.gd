class_name NetSync
extends Node

## Transporte del paso 4. El cliente manda el input de cada tick; el host mueve
## a todos y manda el estado de todos los actores. Todavía sin predicción: el
## cliente muestra exactamente lo que dice el host, con la demora de la red.
## La predicción (paso 6) se apoya en estos mismos mensajes.

## Ticks de input que viajan en cada paquete: si se pierde uno, el siguiente
## trae los mismos ticks otra vez.
const INPUT_REDUNDANCY := 6
## Cada cuántos ticks manda el host un snapshot. Con 1 son 60 por segundo;
## hasta que haya interpolación (paso 8), con menos se vería a los saltos.
const SNAPSHOT_INTERVAL_TICKS := 1
## Cuánta historia de input guarda el host por jugador, en ticks.
const INPUT_HISTORY_TICKS := 120

## Simulador de red (paso 5). Todo lo que se manda o se recibe pasa por acá.
var link: LinkSimulator
## Cliente: tick del último snapshot aplicado.
var latest_snapshot_tick := -1
## Cliente: último tick de input propio que el host usó, según el snapshot.
var acked_input_tick := -1
## Cliente: snapshots aceptados y snapshots que nunca llegaron a tiempo.
var snapshots_received := 0
var snapshots_missing := 0

# Cliente
var _recent_inputs: Array[ActorInput] = []
var _pending_snapshot := PackedByteArray()
var _pending_snapshot_tick := -1
# Host
var _inputs := {}  # peer -> {tick: ActorInput}
var _latest_input := {}  # peer -> ActorInput con el tick más alto recibido
var _used_input_tick := {}  # peer -> tick del input usado en el último tick simulado


func _ready() -> void:
	multiplayer.peer_disconnected.connect(forget_peer)


# --- Cliente ---------------------------------------------------------------

## Guarda el input del tick y se lo manda al host junto con los anteriores.
func send_input(input: ActorInput) -> void:
	_recent_inputs.append(input)
	if _recent_inputs.size() > INPUT_REDUNDANCY:
		_recent_inputs.pop_front()
	var b := StreamPeerBuffer.new()
	b.put_u8(_recent_inputs.size())
	for recent in _recent_inputs:
		recent.write_to(b)
	var data := b.data_array
	_send(func() -> void: _submit_inputs.rpc_id(1, data))


## Aplica el snapshot más nuevo que llegó desde el tick anterior. Se llama
## dentro del tick de física para no romper la interpolación. Los demás
## actores toman el estado tal cual; el propio no: se lo pasa a `on_own_state`
## (tick del host, estado en bytes, tick del input usado, margen del input)
## para que la predicción lo compare y corrija.
func apply_pending_snapshot(actors_root: Node, on_own_state: Callable) -> void:
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
			continue
		var actor := actors_root.get_node_or_null("Actor%d" % owner_id) as ActorBody
		if actor == null:
			continue  # el spawner todavía no lo creó en este cliente
		actor.state = ActorState.from_bytes(state_bytes)
		actor.global_position = actor.state.position
		actor.present(actor.state)


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
	var by_tick: Dictionary = _inputs[peer_id]
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var count := b.get_u8()
	for i in count:
		var input := ActorInput.read_from(b)
		by_tick[input.tick] = input
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
	for t in by_tick.keys():
		if t < tick - INPUT_HISTORY_TICKS:
			by_tick.erase(t)
	if chosen == null:
		return null
	_used_input_tick[peer_id] = chosen.tick
	return ActorInput.make(tick, chosen.move, chosen.look_yaw, chosen.buttons, chosen.jump_presses)


## Cuántos ticks por delante de este llegó el input más nuevo de un jugador.
## Negativo = está llegando tarde. Cero si todavía no mandó nada.
func input_margin_ticks(peer_id: int, tick: int) -> int:
	var latest: ActorInput = _latest_input.get(peer_id)
	return latest.tick - tick if latest != null else 0


## Manda a todos los clientes el estado de todos los actores en este tick.
func send_snapshot(tick: int, actors: Array[ActorBody]) -> void:
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
	var data := b.data_array
	_send(func() -> void: _receive_snapshot.rpc(data))


func forget_peer(peer_id: int) -> void:
	_inputs.erase(peer_id)
	_latest_input.erase(peer_id)
	_used_input_tick.erase(peer_id)


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


func _is_connected() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
