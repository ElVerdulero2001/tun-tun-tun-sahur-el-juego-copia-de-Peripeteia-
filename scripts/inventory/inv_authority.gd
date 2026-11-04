class_name InvAuthority
extends RefCounted

## Las reglas del inventario en el host: la única parte que cambia el estado
## que vale. Jugando solo es lo mismo, con el host como único jugador.
##
## Cada pedido se valida y se aplica en el mismo paso, sin nada en el medio, en
## el orden en que llegaron (InvNet los pone en fila). Quién pide sale de la
## conexión, nunca del pedido: el inventario propio es el del actor de ese
## jugador, y una caja se opera solo si la tiene abierta y está cerca. Las
## distancias se miden con el estado del actor en el host. Para recoger o abrir,
## además, el personaje tiene que ver el objeto o la caja desde los ojos, sin
## una pared en el medio.
##
## Después de cada pedido sale un solo paquete por jugador con todo lo que
## cambió: el resultado para el que pidió, sus inventarios, la caja que tiene
## abierta, los objetos del mundo y el equipo de cada uno. Así una
## transferencia entre dos inventarios nunca se ve aplicada a medias.

## Cuántos resultados se recuerdan por jugador, para contestar un pedido repetido.
const RESULT_MEMORY := 64
## Capas de física: 1 el nivel (y las cajas), 2 los personajes, 3 las escaleras.
const WORLD_MASK := 1 | 4
const SOLID_MASK := 1 | 2 | 4
## El pecho del personaje, desde los pies: de ahí se mide el alcance para
## recoger y se ve dónde cae lo que se suelta.
const CHEST := 0.9
## Los ojos, por debajo de la punta de la forma del personaje (con su postura).
const EYES_BELOW_TOP := 0.15
## A qué altura sobre su lugar se mira un objeto suelto.
const ITEM_SIGHT := 0.2

var catalog: InvCatalog
var actors_root: Node
## Los valores del laboratorio: los máximos de salud y estamina (ActorVitals).
var tuning: ActorTuning
var pickup_range := 2.0
var drop_distance := 1.0
## Manda un paquete a un jugador: func(peer: int, payload: Dictionary).
var send: Callable

## Objetos en el mundo: uid -> {"stack": InvStack, "pos": Vector3}.
var world := {}
## Cajas, por su número: id -> InvContainer.
var containers := {}
## Cuántos pedidos se aceptaron, rechazaron o llegaron repetidos.
var accepted := 0
var rejected := 0
var repeated := 0
## Muertes de prueba causadas por un consumible.
var deaths := 0

var _next_uid := 0
var _open_of := {}  # peer -> id de la caja que tiene abierta
var _welcomed := {}  # peer -> true: ya recibió el estado inicial
var _results := {}  # peer -> {número de pedido: [ok, motivo]}
var _result_order := {}  # peer -> números en el orden en que se recuerdan
var _equip_sent := {}  # peer -> id del tipo equipado que ya se contó a todos
var _space: PhysicsDirectSpaceState3D
# Lo que cambió en el paso que se está procesando.
var _dirty_players := {}
var _dirty_boxes := {}
var _box_snapshot_for := {}  # peer -> caja: se le manda entera (la acaba de abrir)
var _world_set := {}
var _world_gone := {}
var _closed := {}  # peer -> [caja, motivo]
var _equip_all := false
var _use_answers := {}  # peer -> [hasta qué uso llegó, motivo si el último no se pudo]


func alloc_uid() -> int:
	_next_uid += 1
	return _next_uid


# --- Estado del mundo -------------------------------------------------------

func add_spawn(spawn: InvPickupSpawn) -> void:
	if spawn.item == null or catalog.find(spawn.item.id) != spawn.item:
		push_warning("[inventario] %s no tiene un objeto del catálogo" % spawn.get_path())
		return
	var limit := spawn.item.stack_limit()
	if spawn.quantity > limit:
		push_warning("[inventario] %s pide %d, pero en una pila entran %d" % [spawn.get_path(), spawn.quantity, limit])
	_put_in_world(InvStack.make(alloc_uid(), spawn.item.id, clampi(spawn.quantity, 1, limit), spawn.initial_state()),
			spawn.global_position)


func _put_in_world(stack: InvStack, position: Vector3) -> void:
	world[stack.uid] = {"stack": stack, "pos": position}
	_world_set[stack.uid] = true
	_world_gone.erase(stack.uid)


func _world_entry(uid: int) -> Array:
	var item: Dictionary = world[uid]
	var pos: Vector3 = item["pos"]
	return [item["stack"].to_array(), pos.x, pos.y, pos.z]


# --- Jugadores ----------------------------------------------------------------

func actor_of(peer: int) -> ActorBody:
	if actors_root == null:
		return null
	for node in actors_root.get_children():
		var actor := node as ActorBody
		if actor != null and actor.owner_peer_id == peer and not actor.is_queued_for_deletion():
			return actor
	return null


func player_inventory(peer: int) -> InvInventory:
	var actor := actor_of(peer)
	var inventory := actor.get_node_or_null(NodePath(InvNet.INVENTORY_NODE)) as InvInventory if actor != null else null
	return inventory if inventory != null and inventory.grid != null else null


## El personaje de ese jugador ya tiene inventario: si ya está adentro, se le manda.
func inventory_attached(peer: int) -> void:
	if _welcomed.has(peer):
		_dirty_players[peer] = true
		_equip_all = true
		flush({})


## Un jugador volvió después de un corte con otra conexión: su inventario pasa
## al actor nuevo, igual que su estado (NetSession._hand_over).
func actor_replaced(old_actor: ActorBody, new_actor: ActorBody) -> void:
	var inventory := old_actor.get_node_or_null(NodePath(InvNet.INVENTORY_NODE))
	if inventory == null:
		return
	var fresh := new_actor.get_node_or_null(NodePath(InvNet.INVENTORY_NODE))
	if fresh != null:
		new_actor.remove_child(fresh)
		fresh.free()
	old_actor.remove_child(inventory)
	new_actor.add_child(inventory)
	_equip_sent.erase(old_actor.owner_peer_id)
	_equip_all = true
	flush({})


## Estado inicial para el que llega (también al volver de un corte): todos los
## objetos del mundo, el equipo de todos y, si ya tiene personaje, su inventario.
func welcome(peer: int) -> void:
	_welcomed[peer] = true
	var payload := {"world": world.keys().map(_world_entry), "eq": _equipment_of_all()}
	var inventory := player_inventory(peer)
	if inventory != null:
		payload["own"] = inventory.grid.snapshot()
		payload["lo"] = inventory.loadout.snapshot()
	send.call(peer, payload)


func forget_peer(peer: int) -> void:
	_welcomed.erase(peer)
	_open_of.erase(peer)
	_results.erase(peer)
	_result_order.erase(peer)
	_box_snapshot_for.erase(peer)
	_closed.erase(peer)
	_dirty_players.erase(peer)


## El actor de ese jugador se va del mundo: con él se va su inventario.
func actor_left(peer: int) -> void:
	if _equip_sent.has(peer):
		_equip_sent.erase(peer)
	_open_of.erase(peer)


func is_welcomed(peer: int) -> bool:
	return _welcomed.has(peer)


func welcomed_peers() -> Array:
	return _welcomed.keys()


func open_container_of(peer: int) -> int:
	return _open_of.get(peer, 0)


# --- Pedidos -----------------------------------------------------------------

## Procesa un pedido: valida y aplica en el mismo paso, y manda lo que cambió.
func handle(peer: int, seq: int, op: int, args: Array, space: PhysicsDirectSpaceState3D) -> void:
	_space = space
	var reason := _run(peer, op, args)
	_space = null
	if reason == "":
		accepted += 1
	else:
		rejected += 1
		# Lo rechazado no cambió nada: no hay nada más que contar.
		_dirty_players.clear()
		_dirty_boxes.clear()
		_box_snapshot_for.clear()
		_world_set.clear()
		_world_gone.clear()
	_remember(peer, seq, reason)
	flush({peer: [[seq, reason == "", reason]]})


## Un pedido que ya se procesó y llegó otra vez: no se repite, se vuelve a
## mandar su resultado. Uno tan viejo que ya no se recuerda se descarta.
func repeat_result(peer: int, seq: int) -> void:
	repeated += 1
	var known: Dictionary = _results.get(peer, {})
	if known.has(seq):
		flush({peer: [[seq, known[seq][0], known[seq][1]]]})


func _remember(peer: int, seq: int, reason: String) -> void:
	if not _results.has(peer):
		_results[peer] = {}
		_result_order[peer] = []
	_results[peer][seq] = [reason == "", reason]
	_result_order[peer].append(seq)
	while _result_order[peer].size() > RESULT_MEMORY:
		_results[peer].erase(_result_order[peer].pop_front())


func _run(peer: int, op: int, a: Array) -> String:
	var inventory := player_inventory(peer)
	if inventory == null:
		return "todavía no tenés personaje"
	match op:
		InvProtocol.Op.MOVE:
			return _with_grids(peer, a[0], a[3], func(src: InvGrid, dst: InvGrid) -> String:
				return InvOps.move(src, a[1], a[2], dst, Vector2i(a[4], a[5]), a[6]))
		InvProtocol.Op.MERGE:
			if a[5] < 1:
				return "cantidad inválida"
			return _with_grids(peer, a[0], a[3], func(src: InvGrid, dst: InvGrid) -> String:
				return InvOps.merge(src, a[1], a[2], dst, a[4], a[5]))
		InvProtocol.Op.SPLIT:
			return _with_grids(peer, a[0], a[4], func(src: InvGrid, dst: InvGrid) -> String:
				return InvOps.split(src, a[1], a[2], a[3], dst, Vector2i(a[5], a[6]), a[7], alloc_uid()))
		InvProtocol.Op.DROP:
			return _drop(peer, a[0], a[1], a[2], a[3])
		InvProtocol.Op.PICKUP:
			return _pickup(peer, inventory, a[0])
		InvProtocol.Op.USE:
			return _use(peer, inventory, a[0], a[1], InvAbility.Kind.USE)
		InvProtocol.Op.EQUIP:
			return _use(peer, inventory, a[0], a[1], InvAbility.Kind.EQUIP)
		InvProtocol.Op.HOTBAR_SET:
			return _hotbar_set(peer, inventory, a[0], a[1])
		InvProtocol.Op.HOTBAR_SWAP:
			return _hotbar_swap(peer, inventory, a[0], a[1])
		InvProtocol.Op.HOTBAR_PRESS:
			return _hotbar_press(peer, inventory, a[0])
		InvProtocol.Op.OPEN:
			return _open(peer, a[0])
		InvProtocol.Op.CLOSE:
			if _open_of.get(peer, 0) == a[0]:
				_open_of.erase(peer)
			return ""
	return "pedido desconocido"


## La grilla que nombra un pedido, o el motivo por el que ese jugador no la
## puede tocar. [grilla, motivo].
func _grid_for(peer: int, ref: int) -> Array:
	if ref == InvProtocol.OWN:
		return [player_inventory(peer).grid, ""]
	if ref < 0:
		return [null, "no podés tocar el inventario de otro jugador"]
	var box: InvContainer = containers.get(ref)
	if box == null or not is_instance_valid(box) or not box.is_inside_tree():
		return [null, "esa caja ya no está"]
	if _open_of.get(peer, 0) != ref:
		return [null, "no tenés esa caja abierta"]
	if not _in_reach(peer, box):
		return [null, "estás muy lejos de la caja"]
	return [box.inventory.grid, ""]


## Valida el acceso a las dos grillas y, si se puede, corre la operación.
func _with_grids(peer: int, src_ref: int, dst_ref: int, operation: Callable) -> String:
	var src := _grid_for(peer, src_ref)
	if src[1] != "":
		return src[1]
	var dst := _grid_for(peer, dst_ref)
	if dst[1] != "":
		return dst[1]
	var reason: String = operation.call(src[0], dst[0])
	if reason == "":
		_mark(peer, src_ref)
		_mark(peer, dst_ref)
	return reason


func _mark(peer: int, ref: int) -> void:
	if ref == InvProtocol.OWN:
		_dirty_players[peer] = true
	else:
		_dirty_boxes[ref] = true


## Soltar al piso, desde el inventario propio o desde una caja abierta: cae
## adelante del personaje, como siempre.
func _drop(peer: int, ref: int, uid: int, ver: int, quantity: int) -> String:
	var src := _grid_for(peer, ref)
	if src[1] != "":
		return src[1]
	var grid: InvGrid = src[0]
	var reason := InvOps.can_take(grid, uid, ver, quantity)
	if reason != "":
		return reason
	var spot: Variant = _drop_spot(peer)
	if spot == null:
		return "no hay lugar cerca para soltarlo"
	var out := InvOps.take(grid, uid, ver, quantity, alloc_uid())
	_put_in_world(out[1], spot)
	_mark(peer, ref)
	return ""


func _pickup(peer: int, inventory: InvInventory, uid: int) -> String:
	var item: Dictionary = world.get(uid, {})
	if item.is_empty():
		return "ya no está: lo agarró otro jugador"
	if not _near(peer, item["pos"], pickup_range):
		return "estás muy lejos para agarrarlo"
	if not _sees(peer, item["pos"] + Vector3.UP * ITEM_SIGHT):
		return "no lo ves desde ahí: hay algo en el medio"
	var stack: InvStack = item["stack"]
	var result := InvOps.insert(inventory.grid, stack)
	if result["reason"] != "":
		return result["reason"]
	if result["taken"] >= stack.quantity:
		world.erase(uid)
		_world_gone[uid] = true
		_world_set.erase(uid)
	else:
		stack.quantity -= result["taken"]
		stack.ver += 1
		_world_set[uid] = true
	_dirty_players[peer] = true
	return ""


## Usar o equipar, desde el menú o la barra: el objeto tiene que estar en el
## inventario propio y tener esa capacidad.
func _use(peer: int, inventory: InvInventory, uid: int, ver: int, kind: int) -> String:
	var stack := inventory.grid.get_stack(uid)
	if stack == null:
		return "ese objeto no está en tu inventario"
	if stack.ver != ver:
		return "ese objeto cambió: probá de nuevo"
	return _apply_ability(peer, inventory, stack, kind)


## Valida y aplica en el mismo paso: el efecto en el personaje (su salud y su
## estamina, ActorVitals), el gasto de la unidad y la barra. Un pedido
## repetido no llega hasta acá (InvNet lo contesta con el resultado guardado),
## así que un uso aceptado se aplica una sola vez. Por pedido es un evento del
## host (sube la época); desde el input (use_from_input) se le pasa el estado
## de ese tick y no lo es.
func _apply_ability(peer: int, inventory: InvInventory, stack: InvStack, kind: int, state: ActorState = null,
		host_event := true) -> String:
	var def := inventory.grid.def_of(stack.uid)
	var ability := def.ability_of(kind) if def != null else null
	if ability == null:
		return "este objeto no se usa" if kind == InvAbility.Kind.USE else "este objeto no se equipa"
	if state == null:
		var actor := actor_of(peer)
		state = actor.state if actor != null else null
	var vitals := ActorVitals.of(state, tuning) if state != null and tuning != null else null
	if vitals != null:
		vitals.host_event = host_event
	var reason := ability.check(inventory.loadout, stack, vitals)
	if reason != "":
		return reason
	var deaths_before := state.deaths if state != null else 0
	var spent := ability.apply(inventory.loadout, stack, vitals)
	if spent > 0:
		InvOps.consume(inventory.grid, stack.uid, spent)
	if state != null and state.deaths != deaths_before:
		deaths += 1
		print("[inventario] muerte de prueba del jugador %d (%s): se le apagaron los estados y la salud volvió a %d" % [
				peer, def.display_name, roundi(state.health / float(ActorState.HEALTH_UNIT))])
	inventory.loadout.revision += 1
	_dirty_players[peer] = true
	return ""


## Usar un consumible desde el input del jugador (desde el 2026-11-04, ver
## InvNet.use_before_step): corre en el tick en que se apretó, justo antes de
## mover a su personaje, con el estado de ese tick. El cliente ya aplicó lo
## mismo en su predicción, en ese mismo tick: por eso no es un evento del host
## ni sube la época. Le manda al jugador su inventario y hasta qué uso llegó
## ("u"), con el motivo si este no se pudo: con eso el cliente deja de mostrar
## la unidad como gastada, y si no se usó, vuelve a verla.
func use_from_input(peer: int, state: ActorState, uid: int) -> void:
	var reason := "todavía no tenés personaje"
	var inventory := player_inventory(peer)
	if inventory != null:
		var stack := inventory.grid.get_stack(uid)
		reason = "ese objeto ya no está en tu inventario" if stack == null \
				else _apply_ability(peer, inventory, stack, InvAbility.Kind.USE, state, false)
		_dirty_players[peer] = true
	if reason == "":
		accepted += 1
	else:
		rejected += 1
	_use_answers[peer] = [state.use_presses_seen, reason]
	flush({})


func _hotbar_set(peer: int, inventory: InvInventory, slot: int, uid: int) -> String:
	if slot < 0 or slot >= InvLoadout.HOTBAR_SLOTS:
		return "ese acceso no existe"
	var loadout := inventory.loadout
	if uid != 0:
		if not inventory.grid.has(uid):
			return "en la barra solo van objetos de tu inventario"
		var before := loadout.slot_of(uid)
		if before >= 0:
			loadout.hotbar[before] = 0
	loadout.hotbar[slot] = uid
	loadout.revision += 1
	_dirty_players[peer] = true
	return ""


func _hotbar_swap(peer: int, inventory: InvInventory, a: int, b: int) -> String:
	if a < 0 or b < 0 or a >= InvLoadout.HOTBAR_SLOTS or b >= InvLoadout.HOTBAR_SLOTS:
		return "ese acceso no existe"
	var loadout := inventory.loadout
	var kept := loadout.hotbar[a]
	loadout.hotbar[a] = loadout.hotbar[b]
	loadout.hotbar[b] = kept
	loadout.revision += 1
	_dirty_players[peer] = true
	return ""


## Una tecla de la barra: hace la primera capacidad del objeto (usar o equipar).
func _hotbar_press(peer: int, inventory: InvInventory, slot: int) -> String:
	if slot < 0 or slot >= InvLoadout.HOTBAR_SLOTS:
		return "ese acceso no existe"
	var uid := inventory.loadout.hotbar[slot]
	if uid == 0:
		return "el acceso %d está vacío" % ((slot + 1) % 10)
	var stack := inventory.grid.get_stack(uid)
	var def := inventory.grid.def_of(uid)
	if stack == null or def == null:
		return "ese objeto ya no está en tu inventario"
	for ability in def.abilities:
		if ability != null:
			return _apply_ability(peer, inventory, stack, ability.kind())
	return "%s no se usa ni se equipa" % def.display_name


func _open(peer: int, id: int) -> String:
	var box: InvContainer = containers.get(id)
	if box == null or not is_instance_valid(box) or not box.is_inside_tree():
		return "esa caja ya no está"
	if not _in_reach(peer, box):
		return "estás muy lejos de la caja"
	if not _sees(peer, box.center(), [box.get_rid()]):
		return "no ves la caja desde ahí: hay algo en el medio"
	_open_of[peer] = id
	_box_snapshot_for[peer] = id
	return ""


# --- Alcance y lugar para soltar ---------------------------------------------

func _in_reach(peer: int, box: InvContainer) -> bool:
	var actor := actor_of(peer)
	return actor != null and BaseRegistry.world_position(actor.state).distance_to(box.access_point()) <= box.access_range


func _near(peer: int, position: Vector3, reach: float) -> bool:
	var actor := actor_of(peer)
	return actor != null and (BaseRegistry.world_position(actor.state) + Vector3.UP * CHEST).distance_to(position) <= reach


func _sees(peer: int, target: Vector3, exclude: Array[RID] = []) -> bool:
	var actor := actor_of(peer)
	return actor != null and _space != null \
			and sees(_space, eyes(actor, BaseRegistry.world_position(actor.state)), target, exclude)


## Los ojos del personaje con los pies en `feet`: bajan si está agachado.
static func eyes(actor: ActorBody, feet: Vector3) -> Vector3:
	return feet + Vector3.UP * maxf(actor.stance_height(actor.state.stance) - EYES_BELOW_TOP, 0.3)


## Si desde `from` se ve `to`: sin nada del nivel en el medio (ni paredes ni
## cajas; los personajes no tapan). Lo de `exclude` no cuenta. La usa también
## cada máquina para elegir qué se mira.
static func sees(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK, exclude)
	return space.intersect_ray(query).is_empty()


## Dónde cae lo que se suelta: adelante del personaje, o alrededor si ahí no se
## puede, siempre en el mismo orden. Tiene que verse desde el pecho (no se
## suelta atrás de una pared), tener piso abajo y lugar libre: ni dentro del
## personaje, ni de otro, ni de una pared o una caja, ni encima de otro objeto
## suelto. null si no hay ningún lugar.
func _drop_spot(peer: int) -> Variant:
	var actor := actor_of(peer)
	if actor == null or _space == null:
		return null
	var feet := BaseRegistry.world_position(actor.state)
	var yaw := actor.state.facing_yaw
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var chest := feet + Vector3.UP * CHEST
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = box
	probe.collision_mask = SOLID_MASK
	for distance: float in [drop_distance, drop_distance + 0.5, drop_distance * 0.7]:
		for degrees: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]:
			var place := feet + forward.rotated(Vector3.UP, deg_to_rad(degrees)) * distance
			if not _ray(chest, place + Vector3.UP * 0.3, WORLD_MASK).is_empty():
				continue
			var floor_hit := _ray(place + Vector3.UP * 0.6, place + Vector3.DOWN * 1.5, WORLD_MASK)
			if floor_hit.is_empty():
				continue
			var normal: Vector3 = floor_hit["normal"]
			if normal.y < 0.7:
				continue
			var spot: Vector3 = floor_hit["position"]
			probe.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.25)
			if not _space.intersect_shape(probe, 1).is_empty():
				continue
			if _crowded(spot):
				continue
			return spot
	return null


func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return _space.intersect_ray(query)


func _crowded(spot: Vector3) -> bool:
	for uid in world:
		var other: Vector3 = world[uid]["pos"]
		if Vector2(other.x - spot.x, other.z - spot.z).length() < 0.35 and absf(other.y - spot.y) < 0.5:
			return true
	return false


# --- Cajas que se cierran -----------------------------------------------------

## Cada cuadro: al que se alejó de su caja, o cuya caja ya no está, se le cierra.
func watch_access() -> void:
	for peer in _open_of.keys():
		var box: InvContainer = containers.get(_open_of[peer])
		if box == null or not is_instance_valid(box) or not box.is_inside_tree():
			_close_for(peer, "la caja ya no está")
		elif not _in_reach(peer, box):
			_close_for(peer, "te alejaste de la caja")
	if not _closed.is_empty():
		flush({})


## La caja desaparece del mundo: se cierra para todos los que la tenían
## abierta. Lo que tenía adentro se va con ella.
func container_gone(id: int) -> void:
	containers.erase(id)
	for peer in _open_of.keys():
		if _open_of[peer] == id:
			_close_for(peer, "la caja ya no está")
	if not _closed.is_empty():
		flush({})


func _close_for(peer: int, reason: String) -> void:
	_closed[peer] = [_open_of[peer], reason]
	_open_of.erase(peer)


# --- Lo que sale ----------------------------------------------------------------

func _equipped_def(peer: int) -> String:
	var inventory := player_inventory(peer)
	if inventory == null or inventory.loadout.equipped_uid == 0:
		return ""
	var stack := inventory.grid.get_stack(inventory.loadout.equipped_uid)
	return String(stack.def_id) if stack != null else ""


func _equipment_of_all() -> Array:
	var list := []
	for node in actors_root.get_children():
		var actor := node as ActorBody
		if actor != null and not actor.is_queued_for_deletion():
			var def_id := _equipped_def(actor.owner_peer_id)
			_equip_sent[actor.owner_peer_id] = def_id
			list.append([actor.owner_peer_id, def_id])
	return list


## Manda a cada jugador lo que cambió desde el último envío, en un solo paquete,
## con los resultados de `results` (peer -> [[pedido, ok, motivo]]).
func flush(results: Dictionary) -> void:
	for peer in _dirty_players:
		var inventory := player_inventory(peer)
		if inventory != null and inventory.loadout.forget_missing(inventory.grid):
			inventory.loadout.revision += 1
	var equipment := []
	if _equip_all:
		equipment = _equipment_of_all()
	else:
		for peer in _dirty_players:
			var def_id := _equipped_def(peer)
			if _equip_sent.get(peer, "") != def_id:
				_equip_sent[peer] = def_id
				equipment.append([peer, def_id])
	var world_set := _world_set.keys().filter(func(uid: int) -> bool: return world.has(uid)).map(_world_entry)
	var world_gone := _world_gone.keys()
	for peer in _welcomed:
		var payload := {}
		if results.has(peer):
			payload["r"] = results[peer]
		if _use_answers.has(peer):
			payload["u"] = _use_answers[peer]
		var inventory := player_inventory(peer)
		if _dirty_players.has(peer) and inventory != null:
			payload["own"] = inventory.grid.snapshot()
			payload["lo"] = inventory.loadout.snapshot()
		var box_id: int = _open_of.get(peer, 0)
		if box_id != 0 and (_dirty_boxes.has(box_id) or _box_snapshot_for.get(peer, 0) == box_id):
			payload["box"] = [box_id, containers[box_id].inventory.grid.snapshot()]
		if _closed.has(peer):
			payload["closed"] = _closed[peer]
		if not world_set.is_empty():
			payload["wa"] = world_set
		if not world_gone.is_empty():
			payload["wr"] = world_gone
		if not equipment.is_empty():
			payload["eq"] = equipment
		if not payload.is_empty():
			send.call(peer, payload)
	_dirty_players.clear()
	_dirty_boxes.clear()
	_box_snapshot_for.clear()
	_world_set.clear()
	_world_gone.clear()
	_closed.clear()
	_use_answers.clear()
	_equip_all = false
