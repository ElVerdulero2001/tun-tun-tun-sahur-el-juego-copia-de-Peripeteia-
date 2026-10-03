class_name NetSession
extends Node

## Conexión y aparición de actores. El host (o el modo local, que es un host
## sin clientes) es la única autoridad: crea un actor por jugador con un
## MultiplayerSpawner, que lo replica en los clientes, y lo borra cuando el
## jugador se va. Si se va el host, termina la sesión: no hay migración.

signal status_changed(text: String)
signal local_actor_spawned(actor: ActorBody)

const ACTOR_SCENE := preload("res://scenes/actor/actor.tscn")
const MAX_CLIENTS := 7
## Lugares de aparición sobre el piso, en la línea z = 8, en orden de llegada.
const SPAWN_SLOTS := [
	Vector3(0, 0, 8), Vector3(2, 0, 8), Vector3(-2, 0, 8), Vector3(4, 0, 8),
	Vector3(-4, 0, 8), Vector3(6, 0, 8), Vector3(-6, 0, 8), Vector3(8, 0, 8),
]

@export var spawner: MultiplayerSpawner
@export var actors_root: Node3D
@export var clock: SimClock

var status := ""
## Solo en el host: qué lugar de aparición ocupa cada peer.
var _slot_of_peer := {}


func _ready() -> void:
	spawner.spawn_function = _spawn_actor


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
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_set_status("HOST: escuchando en el puerto %d" % port)
	_spawn_for(1)


func start_client(address: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_set_status("CLIENTE: no se pudo crear la conexión a %s:%d (error %d)" % [address, port, err])
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_set_status("CLIENTE: conectando a %s:%d…" % [address, port])


func _on_peer_connected(peer_id: int) -> void:
	_spawn_for(peer_id)
	_set_status("HOST: se conectó el jugador %d" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	# El MultiplayerSpawner replica el borrado en los clientes.
	var actor := actors_root.get_node_or_null("Actor%d" % peer_id)
	if actor != null:
		actor.queue_free()
	_slot_of_peer.erase(peer_id)
	_set_status("HOST: se fue el jugador %d" % peer_id)


func _on_connected_to_server() -> void:
	clock.client_sync = true
	_set_status("CLIENTE: conectado como jugador %d" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	_set_status("CLIENTE: no se pudo conectar")


func _on_server_disconnected() -> void:
	clock.client_sync = false
	for actor in actors_root.get_children():
		actor.queue_free()
	_set_status("CLIENTE: el host se fue; terminó la sesión")


func _spawn_for(peer_id: int) -> void:
	var slot := 0
	while slot in _slot_of_peer.values():
		slot += 1
	_slot_of_peer[peer_id] = slot
	spawner.spawn({"peer": peer_id, "position": SPAWN_SLOTS[slot % SPAWN_SLOTS.size()]})


## Corre en todos los peers con los mismos datos, así el actor nace igual en
## todas las máquinas.
func _spawn_actor(data: Dictionary) -> Node:
	var actor: ActorBody = ACTOR_SCENE.instantiate()
	var peer_id: int = data["peer"]
	actor.name = "Actor%d" % peer_id
	actor.owner_peer_id = peer_id
	# En el cliente nadie se simula al nacer; la predicción del propio arranca
	# cuando el reloj queda sincronizado.
	actor.simulated = multiplayer.is_server()
	actor.position = data["position"]
	actor.state.position = data["position"]
	# Nace apoyado: así coincide con lo que el host calcula en el primer tick.
	actor.state.mode = ActorState.Mode.GROUND
	actor.state.on_floor = true
	actor.state.quantize()
	if peer_id == multiplayer.get_unique_id():
		local_actor_spawned.emit.call_deferred(actor)
	return actor


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)
