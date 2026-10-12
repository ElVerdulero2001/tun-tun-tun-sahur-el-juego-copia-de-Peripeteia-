class_name NetSession
extends Node

## Conexión y aparición de actores. El host (o el modo local, que es un host
## sin clientes) es la única autoridad: crea un actor por jugador con un
## MultiplayerSpawner, que lo replica en los clientes, y lo borra cuando el
## jugador se va. Si se va el host, termina la sesión: no hay migración.
##
## Reconexión: al unirse, el cliente elige una llave al azar y se la da al host
## antes de entrar (la autenticación de SceneMultiplayer). Si se corta la
## conexión, el host deja el actor de ese jugador en el mundo, quieto, y lo
## espera `reconnect_wait` segundos; el cliente reintenta solo. Si vuelve con la
## misma llave, el host le da un actor nuevo con el estado del que lo esperaba:
## sigue donde estaba.
##
## Un corte se nota por silencio: `connection_timeout` segundos sin recibir
## nada del otro lado. No se espera a ENet: después de un tirón largo, su
## estimación de la ida y vuelta se infla y puede tardar más de 30 s en
## cortar. Quien cierra el juego avisa antes de irse: el host no lo espera y
## el cliente no reintenta.

signal status_changed(text: String)
signal local_actor_spawned(actor: ActorBody)
## Cliente: se cortó la conexión con el host y empieza a reintentar.
signal connection_lost
## Cliente: volvió a conectarse después de un corte.
signal connection_restored

const ACTOR_SCENE := preload("res://scenes/actor/actor.tscn")
const MAX_CLIENTS := 7
## Lugares de aparición sobre el piso, en la línea z = 8, en orden de llegada.
const SPAWN_SLOTS := [
	Vector3(0, 0, 8), Vector3(2, 0, 8), Vector3(-2, 0, 8), Vector3(4, 0, 8),
	Vector3(-4, 0, 8), Vector3(6, 0, 8), Vector3(-6, 0, 8), Vector3(8, 0, 8),
]
## Largo de la llave del cliente, en bytes.
const KEY_BYTES := 16
## Cliente: si un intento de reconexión no entra en este tiempo, en segundos,
## se lo deja y se empieza otro de cero. ENet espera cada vez más entre los
## reenvíos del pedido de conexión; con intentos cortos, cuando vuelve la red
## se entra enseguida.
const ATTEMPT_SECONDS := 3.0

@export var spawner: MultiplayerSpawner
@export var actors_root: Node3D
@export var clock: SimClock
## Cuántos segundos sin recibir nada del otro lado dan la conexión por cortada.
## El host escucha los inputs del cliente; el cliente, los snapshots del host.
@export var connection_timeout := 5.0
## Host: cuánto espera a un jugador al que se le cortó la conexión, en segundos.
## Mientras tanto su actor sigue en el mundo, quieto; si vuelve, sigue desde
## ahí. Con 0 no lo espera: lo saca enseguida.
@export var reconnect_wait := 60.0
## Cliente: después de un corte, cada cuánto vuelve a intentar conectarse, en
## segundos. Cada intento que no llega al host tarda además unos 5 s en fallar.
@export var reconnect_retry := 1.0
## Cliente: cuánto sigue intentando antes de rendirse, en segundos. Con 0 no
## reintenta: un corte termina la sesión.
@export var reconnect_give_up := 60.0

## Lo que recibe por red, para saber cuándo se escuchó por última vez al otro
## lado. Lo pone el laboratorio.
var net_sync: NetSync
var status := ""
## Solo para pruebas: dónde aparece (y reaparece) el actor del host o del modo
## local, en vez de su lugar de aparición. Nulo para usar el de siempre.
var host_spawn_override = null
## Cliente: si está intentando volver después de un corte, cuántos intentos
## lleva en este corte y cuántas veces volvió.
var reconnecting := false
var reconnect_attempts := 0
var reconnects := 0
## Host: jugadores que volvieron después de un corte y que no volvieron a tiempo.
var players_back := 0
var players_dropped := 0
## Solo en el host: qué lugar de aparición ocupa cada peer.
var _slot_of_peer := {}
## Solo en el host: la llave de cada peer conectado, en hexadecimal.
var _key_of_peer := {}
## Solo en el host: cuándo se conectó cada peer, en ms. Cuenta como lo último
## que se escuchó de él hasta que manda algo.
var _connected_msec := {}
## Solo en el host: jugadores cortados a los que espera, por llave: [peer, hasta
## qué momento, en ms].
var _waiting := {}
## Solo en el host: peers que avisaron que cierran el juego.
var _leaving := {}
var _hosting := false
# Cliente: su llave, adónde reconectarse y cómo va.
var _key := PackedByteArray()
var _address := ""
var _port := 0
var _connected_at_msec := 0
var _reconnect_since_msec := 0
var _attempt_started_msec := 0
var _retry_pending := false
var _host_left := false


func _ready() -> void:
	spawner.spawn_function = _spawn_actor


func _process(_delta: float) -> void:
	if _hosting:
		_check_silent_peers()
		if not _waiting.is_empty():
			_drop_expired()
	elif clock.client_sync:
		_check_silent_host()
	elif reconnecting and _attempt_started_msec > 0 \
			and Time.get_ticks_msec() - _attempt_started_msec > ATTEMPT_SECONDS * 1000.0:
		multiplayer.multiplayer_peer.close()
		_retry_later()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		say_goodbye()


func start_local() -> void:
	_set_status("LOCAL: sin red")
	_spawn_for(1)


func start_host(port: int, bind_address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	if bind_address != "":
		peer.set_bind_ip(bind_address)
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		_set_status("HOST: no se pudo abrir el puerto %d (error %d)" % [port, err])
		return
	# Nadie entra sin dar su llave: con ella se reconoce a quien vuelve.
	var scene_multiplayer := multiplayer as SceneMultiplayer
	scene_multiplayer.auth_callback = _on_client_key
	scene_multiplayer.peer_authentication_failed.connect(func(peer_id: int) -> void: _key_of_peer.erase(peer_id))
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_lost.bind(false))
	_hosting = true
	_set_status("HOST: escuchando en el puerto %d" % port)
	_spawn_for(1)


func start_client(address: String, port: int) -> void:
	_address = address
	_port = port
	_key = Crypto.new().generate_random_bytes(KEY_BYTES)
	var scene_multiplayer := multiplayer as SceneMultiplayer
	# El host no manda nada para autenticarse; el cliente da su llave apenas se
	# abre la conexión.
	scene_multiplayer.auth_callback = func(_peer_id: int, _data: PackedByteArray) -> void: pass
	scene_multiplayer.peer_authenticating.connect(_on_authenticating)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_connect()


## Avisa al otro lado que esta máquina cierra el juego a propósito: el host
## saca su actor enseguida, y si es el host, los clientes no reintentan. El
## aviso sale ya, sin pasar por el simulador de red.
func say_goodbye() -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if _hosting:
		if multiplayer.get_peers().is_empty():
			return
		_goodbye.rpc()
	else:
		_goodbye.rpc_id(1)
	peer.host.flush()


## Cliente: en un corte, segundos que faltan para rendirse.
func give_up_left() -> float:
	return reconnect_give_up - (Time.get_ticks_msec() - _reconnect_since_msec) / 1000.0


## Host: si espera a ese jugador después de un corte, cuántos segundos le
## quedan; si no, -1.
func waiting_left(peer_id: int) -> float:
	for key in _waiting:
		if _waiting[key][0] == peer_id:
			return maxf((_waiting[key][1] - Time.get_ticks_msec()) / 1000.0, 0.0)
	return -1.0


@rpc("any_peer", "call_remote", "reliable")
func _goodbye() -> void:
	if _hosting:
		_leaving[multiplayer.get_remote_sender_id()] = true
	else:
		_host_left = true


# --- Host ------------------------------------------------------------------

func _on_client_key(peer_id: int, data: PackedByteArray) -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if data.size() != KEY_BYTES:
		scene_multiplayer.disconnect_peer(peer_id)
		return
	_key_of_peer[peer_id] = data.hex_encode()
	scene_multiplayer.complete_auth(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	_connected_msec[peer_id] = Time.get_ticks_msec()
	var old_peer := _peer_with_key(_key_of_peer.get(peer_id, ""), peer_id)
	if old_peer != 0 and _actor_of(old_peer) != null:
		_hand_over(old_peer, peer_id)
		_set_status("HOST: volvió el jugador %d, ahora como jugador %d" % [old_peer, peer_id])
		return
	_spawn_for(peer_id)
	_set_status("HOST: se conectó el jugador %d" % peer_id)


## Se perdió un peer: se fue, se le cortó la conexión (lo dijo ENet o se lo
## dejó de escuchar) o volvió por otra. Puede llegar más de una vez por el
## mismo peer. Con `close`, además se cierra su conexión, que para Godot
## todavía está abierta.
func _on_peer_lost(peer_id: int, close: bool) -> void:
	var key: String = _key_of_peer.get(peer_id, "")
	_forget_peer(peer_id, close)
	if waiting_left(peer_id) >= 0.0:
		return
	if _actor_of(peer_id) == null:
		# Ya volvió por otra conexión, o nunca llegó a aparecer.
		_slot_of_peer.erase(peer_id)
		return
	if key != "" and reconnect_wait > 0.0 and not _leaving.has(peer_id):
		_waiting[key] = [peer_id, Time.get_ticks_msec() + roundi(reconnect_wait * 1000.0)]
		_set_status("HOST: se cortó el jugador %d; lo espero %d s" % [peer_id, roundi(reconnect_wait)])
		return
	_leaving.erase(peer_id)
	_remove_player(peer_id)
	_set_status("HOST: se fue el jugador %d" % peer_id)


## Corta a los peers de los que no se escucha nada hace connection_timeout.
func _check_silent_peers() -> void:
	var now := Time.get_ticks_msec()
	for peer_id in multiplayer.get_peers():
		var heard := maxi(net_sync.heard_msec(peer_id) if net_sync != null else 0, _connected_msec.get(peer_id, now))
		if now - heard > connection_timeout * 1000.0:
			_on_peer_lost(peer_id, true)


## Olvida la conexión de un peer y, con `close`, la cierra si sigue abierta.
func _forget_peer(peer_id: int, close: bool) -> void:
	_key_of_peer.erase(peer_id)
	_connected_msec.erase(peer_id)
	if net_sync != null:
		net_sync.forget_peer(peer_id)
	if close and peer_id in multiplayer.get_peers():
		(multiplayer as SceneMultiplayer).disconnect_peer(peer_id)


## El peer que tenía esta llave antes que `new_peer`: uno cortado al que se
## espera, o uno que para el host sigue conectado (el corte se notó primero del
## lado del cliente). 0 si no hay.
func _peer_with_key(key: String, new_peer: int) -> int:
	if key == "":
		return 0
	if _waiting.has(key):
		return _waiting[key][0]
	for peer in _key_of_peer:
		if peer != new_peer and _key_of_peer[peer] == key:
			return peer
	return 0


## El jugador volvió con otra conexión. Su actor viejo se cambia por uno nuevo,
## del peer nuevo, con el mismo estado: sigue donde estaba. Es un evento del
## host (sube la época), y quien colgaba de él pasa a colgar del nuevo.
func _hand_over(old_peer: int, new_peer: int) -> void:
	var old_actor := _actor_of(old_peer)
	var state := ActorState.from_bytes(old_actor.state.to_bytes())
	state.epoch += 1
	for node in actors_root.get_children():
		var actor := node as ActorBody
		if actor != null and actor != old_actor and actor.state.mode == ActorState.Mode.HOOKED \
				and actor.state.anchor_id == old_peer:
			actor.state.anchor_id = new_peer
			actor.state.epoch += 1
	# Se saca del árbol ya: si no, el que vuelve lo recibiría junto con el nuevo.
	actors_root.remove_child(old_actor)
	old_actor.queue_free()
	_slot_of_peer[new_peer] = _slot_of_peer.get(old_peer, 0)
	_slot_of_peer.erase(old_peer)
	_waiting.erase(_key_of_peer.get(new_peer, ""))
	# Si para el host la conexión vieja seguía abierta, ya no sirve.
	_forget_peer(old_peer, true)
	players_back += 1
	spawner.spawn({"peer": new_peer, "state": state.to_bytes()})


## Saca a los jugadores cortados que no volvieron a tiempo.
func _drop_expired() -> void:
	var now := Time.get_ticks_msec()
	for key in _waiting.keys():
		var peer: int = _waiting[key][0]
		if now < _waiting[key][1]:
			continue
		_waiting.erase(key)
		_remove_player(peer)
		players_dropped += 1
		_set_status("HOST: el jugador %d no volvió a tiempo; se sacó su actor" % peer)


func _remove_player(peer_id: int) -> void:
	# El MultiplayerSpawner replica el borrado en los clientes.
	var actor := _actor_of(peer_id)
	if actor != null:
		actor.queue_free()
	_slot_of_peer.erase(peer_id)


func _actor_of(peer_id: int) -> ActorBody:
	var actor := actors_root.get_node_or_null("Actor%d" % peer_id) as ActorBody
	return actor if actor != null and not actor.is_queued_for_deletion() else null


# --- Cliente -----------------------------------------------------------------

func _connect() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_address, _port)
	if err != OK:
		if reconnecting:
			_retry_later()
		else:
			_set_status("CLIENTE: no se pudo crear la conexión a %s:%d (error %d)" % [_address, _port, err])
		return
	multiplayer.multiplayer_peer = peer
	if not reconnecting:
		_set_status("CLIENTE: conectando a %s:%d…" % [_address, _port])


func _on_authenticating(peer_id: int) -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	scene_multiplayer.send_auth(peer_id, _key)
	scene_multiplayer.complete_auth(peer_id)


func _on_connected_to_server() -> void:
	clock.client_sync = true
	_connected_at_msec = Time.get_ticks_msec()
	_attempt_started_msec = 0
	if not reconnecting:
		_set_status("CLIENTE: conectado como jugador %d" % multiplayer.get_unique_id())
		return
	reconnecting = false
	reconnects += 1
	_set_status("CLIENTE: volvió a conectarse, ahora como jugador %d" % multiplayer.get_unique_id())
	connection_restored.emit()


func _on_connection_failed() -> void:
	if reconnecting:
		_retry_later()
		return
	_set_status("CLIENTE: no se pudo conectar")


## Si no llega nada del host hace connection_timeout, la conexión se da por
## cortada sin esperar a ENet.
func _check_silent_host() -> void:
	var heard := maxi(net_sync.last_snapshot_msec if net_sync != null else 0, _connected_at_msec)
	if Time.get_ticks_msec() - heard > connection_timeout * 1000.0:
		multiplayer.multiplayer_peer.close()
		_on_server_disconnected()


## Se perdió la conexión con el host. Puede llegar dos veces por el mismo
## corte (lo nota esta sesión y después lo dice Godot), y también cuando un
## intento llegó al host pero no terminó de entrar.
func _on_server_disconnected() -> void:
	if reconnecting:
		_retry_later()
		return
	if not clock.client_sync:
		if _connected_at_msec == 0:
			# Llegó al host pero no terminó de entrar.
			_set_status("CLIENTE: no se pudo conectar")
		return
	clock.client_sync = false
	clock.reset_sync()
	for actor in actors_root.get_children():
		actor.queue_free()
	if _host_left or reconnect_give_up <= 0.0:
		_set_status("CLIENTE: el host cerró la partida; terminó la sesión" if _host_left
				else "CLIENTE: se cortó la conexión con el host; terminó la sesión")
		return
	reconnecting = true
	reconnect_attempts = 0
	_reconnect_since_msec = Time.get_ticks_msec()
	_set_status("CLIENTE: se cortó la conexión con el host; reconectando…")
	connection_lost.emit()
	_retry_later()


func _retry_later() -> void:
	_attempt_started_msec = 0
	if _retry_pending:
		return
	_retry_pending = true
	get_tree().create_timer(reconnect_retry, true, false, true).timeout.connect(_try_reconnect)


func _try_reconnect() -> void:
	_retry_pending = false
	if not reconnecting:
		return
	if give_up_left() <= 0.0:
		reconnecting = false
		_set_status("CLIENTE: no se pudo volver a conectar en %d s; cerrá el juego y volvé a unirte" % roundi(reconnect_give_up))
		return
	reconnect_attempts += 1
	_set_status("CLIENTE: se cortó la conexión con el host; reconectando (intento %d)…" % reconnect_attempts)
	_attempt_started_msec = Time.get_ticks_msec()
	_connect()


# --- Todos -------------------------------------------------------------------

## Solo en el host: dónde aparece (y reaparece) ese jugador.
func spawn_position(peer_id: int) -> Vector3:
	if peer_id == 1 and host_spawn_override != null:
		return host_spawn_override
	return SPAWN_SLOTS[_slot_of_peer.get(peer_id, 0) % SPAWN_SLOTS.size()]


func _spawn_for(peer_id: int) -> void:
	var slot := 0
	while slot in _slot_of_peer.values():
		slot += 1
	_slot_of_peer[peer_id] = slot
	spawner.spawn({"peer": peer_id, "position": spawn_position(peer_id)})


## Corre en todos los peers con los mismos datos, así el actor nace igual en
## todas las máquinas. Con "state", nace con ese estado (el de un jugador que
## volvió); si no, apoyado en "position".
func _spawn_actor(data: Dictionary) -> Node:
	var actor: ActorBody = ACTOR_SCENE.instantiate()
	var peer_id: int = data["peer"]
	actor.name = "Actor%d" % peer_id
	actor.owner_peer_id = peer_id
	# En el cliente nadie se simula al nacer; la predicción del propio arranca
	# cuando el reloj queda sincronizado.
	actor.simulated = multiplayer.is_server()
	if data.has("state"):
		actor.state = ActorState.from_bytes(data["state"])
	else:
		actor.state.position = data["position"]
		# Nace apoyado: así coincide con lo que el host calcula en el primer tick.
		actor.state.mode = ActorState.Mode.GROUND
		actor.state.on_floor = true
		actor.state.quantize()
	actor.position = BaseRegistry.world_position(actor.state)
	if peer_id == multiplayer.get_unique_id():
		local_actor_spawned.emit.call_deferred(actor)
	return actor


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)
