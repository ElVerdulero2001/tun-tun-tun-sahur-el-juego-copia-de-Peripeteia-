class_name InvNet
extends Node3D

## El inventario en red. Usa la misma conexión del laboratorio y pasa por el
## mismo simulador de red (LinkSimulator), como NetSync, con mensajes propios:
##
## - El cliente manda pedidos numerados (InvProtocol). El host los ordena por
##   número, descarta los repetidos (les vuelve a mandar el resultado) y los
##   procesa en fila, uno por uno, en InvAuthority.
## - El host manda a cada jugador paquetes numerados con lo que cambió. El
##   cliente los aplica en orden en su InvReplica: el simulador de red puede
##   cambiarles el orden, el número lo arregla.
##
## Jugando solo, y para el jugador del host, es el mismo camino sin la red.
## También arma lo que se ve en el mundo en cada máquina: los objetos sueltos y
## lo que tiene equipado cada personaje.
##
## Sin esperar al host (desde el 2026-11-04, pedido del usuario):
##
## - Usar un consumible no es un pedido: viaja en el input del personaje, como
##   el salto o Kp 2 (ActorInput.use_presses y use_uid), uno por tick. Justo
##   antes de mover al personaje en ese tick (use_before_step), el host lo
##   valida con el inventario de verdad, aplica el efecto y gasta la unidad, y
##   el cliente aplica el mismo efecto en su predicción: la salud y la estamina
##   cambian al instante y sin corrección. Si el host no lo pudo usar, la
##   corrección del snapshot deshace el efecto y la unidad vuelve a verse.
## - Recoger sigue siendo un pedido, pero lo que se ve no lo espera: mientras
##   tanto la grilla propia se muestra con lo recogido adentro y el objeto deja
##   de verse en el piso (InvReplica.shown_own).
##
## Los inventarios son de cada entidad: al personaje el host le agrega un nodo
## InvInventory (INVENTORY_NODE) al aparecer; cada caja trae el suyo. Las cajas
## y los objetos iniciales se buscan en `world_root`, la zona de prueba.

## Nombre del componente de inventario que el host le agrega a cada personaje.
const INVENTORY_NODE := &"Inventario"
## Nombre de lo equipado, dentro del dibujo de cada personaje.
const EQUIP_NODE := &"Equipado"
## Pedidos que pueden esperar a uno anterior que todavía no llegó.
const MAX_WAITING := 64
## Hasta dónde se busca, sobre la línea de la mira, lo que se mira.
const AIM_LENGTH := 6.0

## Se abrió o se cerró la caja del jugador local (para la interfaz).
signal container_closed(id: int, reason: String)

@export var catalog: InvCatalog
@export var actors_root: Node3D
## Dónde están las cajas y los objetos iniciales (InvContainer, InvPickupSpawn).
@export var world_root: Node

@export_group("Alcances")
## Hasta qué distancia del pecho se recoge un objeto suelto, en metros.
@export var pickup_range := 2.0
## A qué distancia adelante del personaje cae lo que se suelta.
@export var drop_distance := 1.0

@export_group("Mirar")
## En tercera persona, qué tan al costado del cuerpo puede estar lo que se
## agarra o se abre: grados a cada lado de hacia donde mira el personaje.
@export_range(10.0, 180.0, 1.0) var look_cone_degrees := 75.0
## Cuánto se perdona al apuntar a un objeto suelto: metros alrededor de su tamaño.
@export_range(0.0, 0.5, 0.01) var aim_margin := 0.12

@export_group("Grilla del jugador")
@export_range(1, 64) var player_columns := 12
@export_range(1, 64) var player_rows := 16

## El simulador de red del laboratorio. Lo pone el laboratorio.
var link: LinkSimulator
## Los valores del laboratorio (el nodo Tuning): los consumibles los usan para
## los máximos de salud y estamina. Lo pone el laboratorio.
var tuning: ActorTuning
var replica := InvReplica.new()
## Solo en el host.
var authority: InvAuthority
var started := false
## Solo para pruebas en un proceso: jugadores que se dan por conectados sin
## red (peer -> true).
var test_peers := {}
## Contador de usos de consumibles del jugador local, de 0 a 255 y da la
## vuelta, y el objeto del último uso: el laboratorio los pone en su input.
var use_presses := 0
var use_uid := 0

var _containers: Array[InvContainer] = []
var _spawns: Array[InvPickupSpawn] = []
var _inbox: Array = []  # host: [peer, número, operación, argumentos], en orden
var _in_expected := {}  # host: peer -> próximo número de pedido
var _in_waiting := {}  # host: peer -> {número: [número, operación, argumentos]}
var _out_seq := {}  # host: peer -> último número de paquete mandado
var _commit_expected := 1
var _commit_waiting := {}
var _world_views := {}  # uid -> InvWorldItem
var _world_layer: Node3D
var _use_queue: Array = []  # [id, InvItemDef] que esperan su tick, en orden
var _use_defs := {}  # valor del contador -> InvItemDef que se usó con él (para repetir ticks)
var _use_tick := -1


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_world_layer = Node3D.new()
	_world_layer.name = "ObjetosSueltos"
	add_child(_world_layer)
	replica.catalog = catalog
	replica.send = _send_request
	replica.world_changed.connect(_sync_world_views)
	replica.shown_changed.connect(_sync_world_views)
	replica.equipment_changed.connect(_sync_equipment)
	replica.container_closed.connect(func(id: int, reason: String) -> void: container_closed.emit(id, reason))
	for problem in catalog.problems() if catalog != null else PackedStringArray(["no tiene catálogo"]):
		push_warning("[inventario] catálogo: %s" % problem)
	if world_root != null:
		_collect(world_root)
	for i in _containers.size():
		_containers[i].container_id = i + 1
	if actors_root != null:
		actors_root.child_entered_tree.connect(_on_actor_entered)
		actors_root.child_exiting_tree.connect(_on_actor_exiting)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Las cajas y los objetos iniciales, en el orden del árbol: el número de cada
## caja sale de ahí, igual en todas las máquinas.
func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is InvContainer:
			_containers.append(child)
		elif child is InvPickupSpawn:
			_spawns.append(child)
		_collect(child)


## Arranca al elegir el rol. El host (y jugando solo) arma el estado del mundo
## y se manda a sí mismo el estado inicial; el cliente espera el del host.
func start(as_host: bool) -> void:
	started = true
	replica.reset()
	_use_queue.clear()
	_commit_expected = 1
	_commit_waiting.clear()
	_in_expected.clear()
	_in_waiting.clear()
	_out_seq.clear()
	_inbox.clear()
	if not as_host:
		return
	authority = InvAuthority.new()
	authority.catalog = catalog
	authority.actors_root = actors_root
	authority.tuning = tuning
	authority.pickup_range = pickup_range
	authority.drop_distance = drop_distance
	authority.send = _send_commit
	for box in _containers:
		if box.inventory == null:
			push_warning("[inventario] %s no tiene inventario" % box.get_path())
			continue
		box.inventory.setup(catalog)
		authority.containers[box.container_id] = box
		box.tree_exiting.connect(authority.container_gone.bind(box.container_id))
	for spawn in _spawns:
		authority.add_spawn(spawn)
	for actor in actors_root.get_children():
		_attach_inventory.call_deferred(actor)
	authority.welcome(multiplayer.get_unique_id())


func is_host() -> bool:
	return authority != null


## Cliente: se cortó la conexión. Lo que sabía ya no vale; al volver, el host
## le manda todo de nuevo. Lo confirmado no se toca: queda en el host.
func connection_lost() -> void:
	replica.reset()
	_commit_expected = 1
	_commit_waiting.clear()
	_use_queue.clear()


# --- Consumibles sin esperar al host --------------------------------------------

## Usa una unidad de ese objeto del inventario propio: sale en el input del
## próximo tick libre (take_use). Quien llama ya comprobó que se puede usar
## (InvUI.use_item). Desde ya se ve gastada (InvReplica.shown_own).
func queue_use(uid: int, def: InvItemDef) -> void:
	_use_queue.append([uid, def])
	replica.add_use(uid)


## El uso que va en el input propio de este tick, si hay alguno esperando: sube
## el contador. Lo llama el laboratorio al armar ese input; otra vez en el
## mismo tick no saca otro.
func take_use(tick: int) -> void:
	if tick == _use_tick or _use_queue.is_empty():
		return
	_use_tick = tick
	var next: Array = _use_queue.pop_front()
	use_presses = (use_presses + 1) & 0xFF
	use_uid = next[0]
	_use_defs[use_presses] = next[1]
	replica.assign_use(use_presses)


## Antes de mover a un actor en un tick (SimClock.before_step, y al repetir
## ticks): si su input trae un uso nuevo, lo aplica. En el host, y jugando solo,
## vale: lo valida con el inventario y gasta la unidad
## (InvAuthority.use_from_input). En un cliente es la predicción del propio: el
## mismo efecto en el mismo tick, con lo que se usó, sin tocar el inventario,
## que lo cambia el host. Un input sin objeto no cuenta: así uno armado sin el
## contador (las pruebas con guion) no hace nada.
func use_before_step(actor: ActorBody, input: ActorInput) -> void:
	if input.use_uid == 0 or input.use_presses == actor.state.use_presses_seen:
		return
	actor.state.use_presses_seen = input.use_presses
	if authority != null:
		authority.use_from_input(actor.owner_peer_id, actor.state, input.use_uid)
		return
	var def: InvItemDef = _use_defs.get(input.use_presses)
	var ability := def.ability_of(InvAbility.Kind.USE) if def != null else null
	if ability == null or tuning == null:
		return
	var vitals := ActorVitals.of(actor.state, tuning)
	vitals.host_event = false
	if ability.check(null, null, vitals) == "":
		ability.apply(null, null, vitals)


func container(id: int) -> InvContainer:
	return _containers[id - 1] if id >= 1 and id <= _containers.size() and is_instance_valid(_containers[id - 1]) else null


func containers() -> Array[InvContainer]:
	var list: Array[InvContainer] = []
	for box in _containers:
		if is_instance_valid(box) and box.is_inside_tree():
			list.append(box)
	return list


## Lo que el jugador está mirando, si lo puede agarrar o abrir: {"kind": "box"
## o "item", "id", "name"}, o {} si no hay nada.
##
## La mira es la línea que sale de la cámara por el centro de la pantalla,
## desde `from` (la cámara, o en tercera persona el punto a la altura de la
## cabeza: lo que queda entre la cámara y el personaje no se elige) hacia
## `look`. Gana lo primero que toca, si está al alcance y el personaje lo ve
## desde los ojos, sin una pared en el medio. En tercera persona, además, tiene
## que estar adelante del cuerpo: a no más de look_cone_degrees de hacia donde
## mira el personaje, aunque la cámara lo vea desde otro lado.
##
## Es solo lo que elige esta máquina: el host vuelve a medir el alcance y la vista.
func interaction_target(actor: ActorBody, from: Vector3, look: Vector3, third_person: bool) -> Dictionary:
	if actor == null or not actor.is_inside_tree() or look.length_squared() < 0.0001:
		return {}
	var direction := look.normalized()
	var space := get_world_3d().direct_space_state
	var feet := actor.global_position
	var chest := feet + Vector3.UP * InvAuthority.CHEST
	var eyes := InvAuthority.eyes(actor, feet)
	var forward := Vector3.FORWARD.rotated(Vector3.UP, actor.state.facing_yaw)
	var cone := cos(deg_to_rad(look_cone_degrees))
	var in_front := func(point: Vector3) -> bool:
		var flat := Vector3(point.x - feet.x, 0.0, point.z - feet.z)
		return not third_person or flat.length() < 0.3 or flat.normalized().dot(forward) >= cone
	# Lo primero del nivel que toca la mira: una caja, o una pared que tapa lo de atrás.
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + direction * AIM_LENGTH,
			InvAuthority.WORLD_MASK))
	var wall := AIM_LENGTH if hit.is_empty() else from.distance_to(hit["position"])
	var best := {}
	var best_t := INF
	var box := hit.get("collider") as InvContainer
	if box != null and box.container_id != 0 and feet.distance_to(box.access_point()) <= box.access_range \
			and in_front.call(box.center()) and InvAuthority.sees(space, eyes, box.center(), [box.get_rid()]):
		best_t = wall
		best = {"kind": "box", "id": box.container_id, "name": box.display_name}
	for uid in replica.world:
		if replica.is_taken(uid):
			continue
		var item: Dictionary = replica.world[uid]
		var stack: InvStack = item["stack"]
		var def := catalog.find(stack.def_id)
		var size := def.world_size if def != null else 0.4
		var radius := size * 0.5 + aim_margin
		var t := _ray_sphere(from, direction, item["pos"] + Vector3.UP * size * 0.35, radius)
		if t >= best_t or t > wall + radius:
			continue
		var sight: Vector3 = item["pos"] + Vector3.UP * InvAuthority.ITEM_SIGHT
		if chest.distance_to(item["pos"]) > pickup_range or not in_front.call(item["pos"]) \
				or not InvAuthority.sees(space, eyes, sight):
			continue
		best_t = t
		best = {"kind": "item", "id": uid, "name": (def.display_name if def != null else String(stack.def_id)) +
				(" ×%d" % stack.quantity if stack.quantity > 1 else "")}
	return best


## A qué distancia sobre la línea entra en la esfera (0 si arranca adentro), o
## INF si no la toca.
static func _ray_sphere(from: Vector3, direction: Vector3, center: Vector3, radius: float) -> float:
	var to_center := center - from
	if to_center.length_squared() <= radius * radius:
		return 0.0
	var along := to_center.dot(direction)
	var miss := to_center.length_squared() - along * along
	if along < 0.0 or miss > radius * radius:
		return INF
	return along - sqrt(radius * radius - miss)


# --- Personajes ---------------------------------------------------------------

func _on_actor_entered(node: Node) -> void:
	# Al entrar todavía no corrió su _ready: se le agrega lo suyo después.
	_attach_inventory.call_deferred(node)
	_sync_equipment.call_deferred()


func _on_actor_exiting(node: Node) -> void:
	var actor := node as ActorBody
	if actor != null and authority != null:
		authority.actor_left(actor.owner_peer_id)


## Host: el inventario del personaje, si todavía no lo tiene (al volver de un
## corte trae el de su actor anterior: ver actor_replaced).
func _attach_inventory(node: Node) -> void:
	var actor := node as ActorBody
	if authority == null or actor == null or not is_instance_valid(actor) or actor.is_queued_for_deletion() \
			or actor.has_node(NodePath(INVENTORY_NODE)):
		return
	var inventory := InvInventory.new()
	inventory.name = INVENTORY_NODE
	inventory.columns = player_columns
	inventory.rows = player_rows
	inventory.has_loadout = true
	inventory.setup(catalog)
	actor.add_child(inventory)
	authority.inventory_attached(actor.owner_peer_id)


## Host: un jugador volvió después de un corte (NetSession.actor_replaced).
func actor_replaced(old_actor: ActorBody, new_actor: ActorBody) -> void:
	if authority != null:
		authority.actor_replaced(old_actor, new_actor)


# --- Red ----------------------------------------------------------------------

func _on_peer_connected(peer: int) -> void:
	if authority == null:
		return
	_out_seq.erase(peer)
	_in_expected.erase(peer)
	_in_waiting.erase(peer)
	# Después de que la sesión le dé su actor (o le devuelva el de antes).
	authority.welcome.call_deferred(peer)


func _on_peer_disconnected(peer: int) -> void:
	if authority == null:
		return
	authority.forget_peer(peer)
	_out_seq.erase(peer)
	_in_expected.erase(peer)
	_in_waiting.erase(peer)
	_inbox = _inbox.filter(func(item: Array) -> bool: return item[0] != peer)


## Host: cuando la sesión corta a alguien por silencio (NetSession), Godot no
## siempre avisa peer_disconnected. Quien ya no figura entre los conectados se
## olvida igual: sus suscripciones y lo que tenía en fila.
func _forget_gone_peers() -> void:
	var connected := multiplayer.get_peers()
	var local := multiplayer.get_unique_id()
	for peer in authority.welcomed_peers():
		if peer != local and not peer in connected and not test_peers.has(peer):
			_on_peer_disconnected(peer)


func _send_request(seq: int, op: int, args: Array) -> void:
	if authority != null:
		# El jugador del host: sin red, pero por la misma fila y el mismo control de repetidos.
		_queue_request(multiplayer.get_unique_id(), [seq, op, args])
		return
	var data := InvProtocol.encode_request(seq, op, args)
	_send_reliable(func() -> void: _inv_request.rpc_id(1, data))


@rpc("any_peer", "call_remote", "reliable")
func _inv_request(data: PackedByteArray) -> void:
	if authority == null:
		return
	_receive_reliable(_accept_request.bind(multiplayer.get_remote_sender_id(), data))


## Host: pone en fila un pedido, en el orden de sus números. Uno que ya pasó es
## un repetido: no se vuelve a hacer, se le contesta lo mismo.
func _accept_request(peer: int, data: PackedByteArray) -> void:
	if authority == null or not peer in multiplayer.get_peers() or not authority.is_welcomed(peer):
		return
	var parsed := InvProtocol.parse_request(data)
	if parsed.is_empty():
		authority.rejected += 1
		return
	_queue_request(peer, parsed)


func _queue_request(peer: int, parsed: Array) -> void:
	var seq: int = parsed[0]
	var expected: int = _in_expected.get(peer, 1)
	if seq < expected:
		authority.repeat_result(peer, seq)
		return
	if seq >= expected + MAX_WAITING:
		return
	if not _in_waiting.has(peer):
		_in_waiting[peer] = {}
	var waiting: Dictionary = _in_waiting[peer]
	if waiting.has(seq):
		authority.repeated += 1
		return
	waiting[seq] = parsed
	while waiting.has(expected):
		_inbox.append([peer] + waiting[expected])
		waiting.erase(expected)
		expected += 1
	_in_expected[peer] = expected


## Host: procesa los pedidos en fila. Va en el cuadro de física porque soltar
## algo consulta el espacio físico.
func _physics_process(_delta: float) -> void:
	if authority == null:
		return
	_forget_gone_peers()
	var space := get_world_3d().direct_space_state
	while not _inbox.is_empty():
		var item: Array = _inbox.pop_front()
		authority.handle(item[0], item[1], item[2], item[3], space)
	authority.watch_access()


func _process(_delta: float) -> void:
	if started:
		for seq in replica.expire_pending():
			push_warning("[inventario] el pedido %d no tuvo respuesta del host" % seq)


## Host: un paquete para un jugador, con su número. Al propio se lo entrega
## acá mismo, por el mismo camino (copiado, como si hubiera viajado).
func _send_commit(peer: int, payload: Dictionary) -> void:
	var seq: int = _out_seq.get(peer, 0) + 1
	_out_seq[peer] = seq
	payload["s"] = seq
	var data := var_to_bytes(payload)
	if peer == multiplayer.get_unique_id():
		_accept_commit(data)
		return
	# Uno que se acaba de ir (o que volvió con otra conexión) ya no tiene a quién mandarle.
	if not peer in multiplayer.get_peers():
		return
	_send_reliable(func() -> void:
		if peer in multiplayer.get_peers():
			_inv_commit.rpc_id(peer, data))


@rpc("authority", "call_remote", "reliable")
func _inv_commit(data: PackedByteArray) -> void:
	_receive_reliable(_accept_commit.bind(data))


func _accept_commit(data: PackedByteArray) -> void:
	var payload: Variant = bytes_to_var(data)
	if not payload is Dictionary or typeof(payload.get("s")) != TYPE_INT:
		return
	var seq: int = payload["s"]
	if seq < _commit_expected:
		return
	_commit_waiting[seq] = payload
	while _commit_waiting.has(_commit_expected):
		var next: Dictionary = _commit_waiting[_commit_expected]
		_commit_waiting.erase(_commit_expected)
		_commit_expected += 1
		replica.apply_commit(next)


func _send_reliable(packet: Callable) -> void:
	var guarded := func() -> void:
		if multiplayer.has_multiplayer_peer() \
				and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
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


# --- Lo que se ve en el mundo ---------------------------------------------------

## Lo que se ve suelto en el mundo: lo que dice el host, menos lo que esta
## máquina ya recogió entero y el host todavía no confirmó.
func _sync_world_views() -> void:
	for uid in _world_views.keys():
		if not replica.world.has(uid) or replica.is_taken(uid):
			_world_views[uid].queue_free()
			_world_views.erase(uid)
	for uid in replica.world:
		if replica.is_taken(uid):
			continue
		var item: Dictionary = replica.world[uid]
		var stack: InvStack = item["stack"]
		var def := catalog.find(stack.def_id)
		var view: InvWorldItem = _world_views.get(uid)
		if view == null:
			view = InvWorldItem.new()
			view.name = "Objeto%d" % uid
			_world_layer.add_child(view)
			view.setup(def, stack)
			_world_views[uid] = view
		else:
			view.refresh(def, stack)
		view.global_position = item["pos"]


func _sync_equipment() -> void:
	if actors_root == null:
		return
	for node in actors_root.get_children():
		var actor := node as ActorBody
		if actor == null or actor.is_queued_for_deletion() or actor.visual_root() == null:
			continue
		var view := actor.visual_root().get_node_or_null(NodePath(EQUIP_NODE)) as InvEquipView
		if view == null:
			view = InvEquipView.new()
			view.name = EQUIP_NODE
			view.setup(actor)
			actor.visual_root().add_child(view)
		var def_id: String = replica.equipment.get(actor.owner_peer_id, "")
		view.show_def(catalog.find(StringName(def_id)) if def_id != "" else null)


## Host: cuántos pedidos esperan en fila o a que llegue uno anterior.
func queued_requests() -> int:
	var count := _inbox.size()
	for peer in _in_waiting:
		count += _in_waiting[peer].size()
	return count


## La vista de un objeto suelto, para las pruebas.
func world_view(uid: int) -> InvWorldItem:
	return _world_views.get(uid)


## Lo que tiene que ser igual en el host y en los clientes (SimFingerprint):
## los valores de acá, el catálogo y las cajas y objetos iniciales de la zona.
func fingerprint_text() -> String:
	var text := "jugador %d×%d alcance %s soltar %s\n" % [player_columns, player_rows,
			snappedf(pickup_range, 0.0001), snappedf(drop_distance, 0.0001)]
	text += catalog.fingerprint_text() if catalog != null else "sin catálogo"
	for box in _containers:
		text += "\ncaja %d %s %d×%d alcance %s en %s" % [box.container_id, box.display_name, box.columns, box.rows,
				snappedf(box.access_range, 0.0001), box.global_position.snapped(Vector3.ONE * 0.0001)]
	for spawn in _spawns:
		text += "\nobjeto %s ×%d %s en %s" % [String(spawn.item.id) if spawn.item != null else "?", spawn.quantity,
				var_to_str(spawn.initial_state()), spawn.global_position.snapped(Vector3.ONE * 0.0001)]
	return text
