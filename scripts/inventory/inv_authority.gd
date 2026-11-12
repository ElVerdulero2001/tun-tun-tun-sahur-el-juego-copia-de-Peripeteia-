class_name InvAuthority
extends RefCounted

## Las reglas del inventario en el host: la única parte que cambia el estado
## que vale. Jugando solo es lo mismo, con el host como único jugador.
##
## Cada pedido se valida y se aplica en el mismo paso, sin nada en el medio, en
## el orden en que llegaron (InvNet los pone en fila). Quién pide sale de la
## conexión, nunca del pedido: el inventario propio es el del actor de ese
## jugador, y una caja se opera solo si la tiene abierta y está cerca. Las
## distancias se miden con el estado del actor en el host.
##
## Recoger y abrir, desde el 2026-11-11 a la noche, con la regla común de
## InvReach (la misma que usa cada máquina para elegir qué mira): el host tira
## su propio rayo desde los ojos del actor, con su estado y su postura, en la
## dirección que manda el jugador (InvProtocol.direction_of, que la valida), y
## lo primero que toca, a no más de interaction_range del Tuning, tiene que ser
## ese objeto (sus triángulos, con el tipo de su catálogo y su lugar) o esa caja
## (su colisión en la escena del host). Del cliente se usa solo la dirección:
## ni dónde está su cámara, ni distancias, ni lo que tocó, ni si lo ve. Con la
## caja abierta, la distancia de los ojos del actor a su volumen.
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
## El pecho del personaje, desde los pies: de ahí se ve dónde cae lo que se
## suelta. El alcance para recoger y abrir no sale de acá: se mide desde los
## ojos, que bajan al agacharse (eyes; desde el 2026-11-11).
const CHEST := 0.9
## Los ojos, por debajo de la punta de la forma del personaje (con su postura).
const EYES_BELOW_TOP := 0.15
## Cuánto más lejos que lo normal puede estar del personaje, en el host, el
## lugar que eligió el cliente para soltar (DROP_AT): lo que pudo moverse el
## personaje entre que el cliente lo eligió y el host lo mira, en metros.
const DROP_LAG_MARGIN := 1.0
## Al recoger o abrir, el rayo del host sigue más allá del alcance, solo para
## decir por qué no: hasta pasar lo pedido (y al menos esto más que el
## alcance). Si lo primero que toca más allá es lo pedido, "estás muy lejos"; lo
## que se acepta es lo mismo que con un rayo del largo justo.
const FAR_LOOK := 2.0

var catalog: InvCatalog
var actors_root: Node
## Los valores del laboratorio: los máximos de salud y estamina (ActorVitals).
var tuning: ActorTuning
## Hasta qué distancia se recoge un objeto o se abre y se opera una caja: el
## del Tuning (interaction_range), leído en el momento, o el de fábrica sin
## Tuning. Se mide desde los ojos, con InvReach.
var interaction_range: float:
	get:
		return tuning.interaction_range if tuning != null else InvNet.DEFAULT_INTERACTION_RANGE
var drop_distance := 1.0
## Manda un paquete a un jugador: func(peer: int, payload: Dictionary).
var send: Callable

## Objetos en el mundo: uid -> {"stack": InvStack, "pos": Vector3, "label":
## bool}. "label" es si se ve el cartel de arriba: lo apaga el InvPickupSpawn
## (show_label); lo soltado siempre lo lleva.
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
var _use_answers := {}  # peer -> [hasta qué uso llegó, [[número, motivo], ...] de los que no se pudieron]


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
			spawn.global_position, spawn.show_label)


func _put_in_world(stack: InvStack, position: Vector3, label := true) -> void:
	world[stack.uid] = {"stack": stack, "pos": position, "label": label}
	_world_set[stack.uid] = true
	_world_gone.erase(stack.uid)


## Cómo viaja un objeto suelto: [pila, x, y, z, cartel].
func _world_entry(uid: int) -> Array:
	var item: Dictionary = world[uid]
	var pos: Vector3 = item["pos"]
	return [item["stack"].to_array(), pos.x, pos.y, pos.z, item.get("label", true)]


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
		InvProtocol.Op.DROP_AT:
			return _drop(peer, a[0], a[1], a[2], a[3], InvProtocol.drop_spot_of(a))
		InvProtocol.Op.PICKUP:
			return _pickup(peer, inventory, a)
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
			return _open(peer, a)
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
	if not _box_in_reach(peer, box):
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
## adelante del personaje, como siempre. Con `proposed` (DROP_AT, desde el
## 2026-11-04), donde el cliente ya lo muestra, si ese lugar sirve
## (drop_spot_ok); si no, donde lo elige el host.
func _drop(peer: int, ref: int, uid: int, ver: int, quantity: int, proposed: Variant = null) -> String:
	var src := _grid_for(peer, ref)
	if src[1] != "":
		return src[1]
	var grid: InvGrid = src[0]
	var reason := InvOps.can_take(grid, uid, ver, quantity)
	if reason != "":
		return reason
	var spot: Variant = proposed if proposed != null and drop_spot_ok(peer, proposed) else _drop_spot(peer)
	if spot == null:
		return "no hay lugar cerca para soltarlo"
	var out := InvOps.take(grid, uid, ver, quantity, alloc_uid())
	_put_in_world(out[1], spot)
	_mark(peer, ref)
	return ""


## Recoger: [número del objeto, dirección de la mano]. Lo primero que toca el
## rayo del host desde los ojos del actor, al alcance, tiene que ser ese objeto
## (_reach_reason). Si no entra entero, se lleva lo que entra y el resto queda.
func _pickup(peer: int, inventory: InvInventory, a: Array) -> String:
	var uid: int = a[0]
	var item: Dictionary = world.get(uid, {})
	if item.is_empty():
		return "ya no está: lo agarró otro jugador"
	var stack: InvStack = item["stack"]
	var actor := actor_of(peer)
	if actor == null:
		return "estás muy lejos para agarrarlo"
	var bounds := InvReach.item_bounds(catalog.find(stack.def_id))
	var reason := _reach_reason(actor, a, "item", uid, item["pos"] + bounds.get_center(), bounds.size.length(),
			"estás muy lejos para agarrarlo", "no lo ves desde ahí: hay algo en el medio", "no lo estás mirando")
	if reason != "":
		return reason
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


## Un consumible soltado sobre una parte del cuerpo, en el panel de integridad
## (desde el 2026-11-06; hasta la noche, un pedido aparte, HEAL_PART): llega
## como un uso del input, con la parte (use_from_input). Valida y aplica en el
## mismo paso, con el estado del personaje en ese tick: que cure partes, que
## la parte exista y que siga dañada. El personaje es el de quien usa (sale de
## la conexión): el input no puede nombrar otro. Si todo da, la parte se cura
## y se gasta una unidad juntas. El cliente ya hizo lo mismo en su predicción,
## así que no es un evento del host ni sube la época. Si algo no da, no cambia
## nada y el objeto se vuelve a ver donde estaba. Cada uso tiene su número y
## se hace una sola vez, aunque viaje en varios inputs.
func _heal_part(peer: int, inventory: InvInventory, stack: InvStack, state: ActorState, part: int) -> String:
	var def := inventory.grid.def_of(stack.uid)
	var use := def.ability_of(InvAbility.Kind.USE) as InvConsumable if def != null else null
	if use == null or not use.repairs_parts():
		return "eso no cura partes del cuerpo"
	var reason := use.check_part(state, part)
	if reason != "":
		return reason
	var spent := use.apply_part(state, part)
	InvOps.consume(inventory.grid, stack.uid, spent)
	inventory.loadout.revision += 1
	_dirty_players[peer] = true
	return ""


## Usar un consumible desde el input del jugador (desde el 2026-11-04, ver
## InvNet.use_before_step): corre en el tick en que llegó, justo antes de mover
## a su personaje, con el estado de ese tick. El cliente ya aplicó lo mismo en
## su predicción: por eso no es un evento del host ni sube la época. Anota la
## respuesta de ese uso, por su número (`number`); InvNet manda una sola vez
## por tick (flush) el inventario y las respuestas ("u"): hasta qué uso llegó y
## los que no se pudieron, cada uno con su motivo. Con eso el cliente deja de
## mostrar esas unidades como gastadas, y las que no se usaron vuelven a verse.
## `part`: -1 el uso normal; una parte del cuerpo, soltado sobre ella (_heal_part).
func use_from_input(peer: int, state: ActorState, uid: int, number: int, part := -1) -> void:
	var reason := "todavía no tenés personaje"
	var inventory := player_inventory(peer)
	if inventory != null:
		var stack := inventory.grid.get_stack(uid)
		if stack == null:
			reason = "ese objeto ya no está en tu inventario"
		elif part >= 0 or part < -1:
			reason = _heal_part(peer, inventory, stack, state, part)
		else:
			reason = _apply_ability(peer, inventory, stack, InvAbility.Kind.USE, state, false)
	if reason == "":
		accepted += 1
	else:
		rejected += 1
	_answer_use(peer, number, reason)


## Un uso que el host no hace (InvNet.use_before_step): se perdió o esperó
## demasiado. Se contesta como uno rechazado.
func use_refused(peer: int, number: int, reason: String) -> void:
	rejected += 1
	_answer_use(peer, number, reason)


func _answer_use(peer: int, number: int, reason: String) -> void:
	var answer: Array = _use_answers.get_or_add(peer, [number, []])
	answer[0] = number
	if reason != "":
		answer[1].append([number, reason])


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


## Abrir: [número de la caja, dirección de la mano]. Lo primero que toca el
## rayo del host desde los ojos del actor, al alcance, tiene que ser esa caja.
## Como ese punto es parte de su volumen, la caja abierta cumple ya la
## distancia de los ojos a su volumen (_box_in_reach), y no se cierra sola.
func _open(peer: int, a: Array) -> String:
	var id: int = a[0]
	var box: InvContainer = containers.get(id)
	if box == null or not is_instance_valid(box) or not box.is_inside_tree():
		return "esa caja ya no está"
	var actor := actor_of(peer)
	if actor == null:
		return "estás muy lejos de la caja"
	var reason := _reach_reason(actor, a, "box", id, box.center(), (box.global_basis * box.box_size).length(),
			"estás muy lejos de la caja", "no ves la caja desde ahí: hay algo en el medio", "no estás mirando la caja")
	if reason != "":
		return reason
	_open_of[peer] = id
	_box_snapshot_for[peer] = id
	return ""


# --- Alcance y lugar para soltar ---------------------------------------------

## El rayo de la mano en el host (InvReach.first_hit): desde los ojos del actor
## con su estado y su postura, en la dirección del pedido, contra el nivel, las
## cajas y los objetos sueltos del host. "" si lo primero que toca, al alcance,
## es lo pedido (`kind` y `id`); si no, el motivo: `far` si lo pedido es lo
## primero pero más allá del alcance, `blocked` si al alcance hay otra cosa
## antes, `missed` si no lo toca, y uno propio si la dirección no sirve.
## `center` y `size` (lo pedido, en el mundo) solo alargan la línea para elegir
## el motivo (FAR_LOOK).
func _reach_reason(actor: ActorBody, a: Array, kind: String, id: int, center: Vector3, size: float, far: String,
		blocked: String, missed: String) -> String:
	var direction: Variant = InvProtocol.direction_of(a)
	if direction == null:
		return "pedido inválido: la dirección de la mano no sirve"
	var at := eyes(actor, BaseRegistry.world_position(actor.state))
	var length := minf(maxf(interaction_range + FAR_LOOK, at.distance_to(center) + size), 1000.0)
	var hit := InvReach.first_hit(_space, at, direction, length, world, catalog, InvReach.own_shapes(actor))
	if hit.is_empty():
		return missed
	var reached: bool = hit["distance"] <= interaction_range
	if hit["kind"] == kind and hit.get("id", 0) == id:
		return "" if reached else far
	return blocked if reached else missed


## Si la caja abierta sigue al alcance del actor de ese jugador, en el host:
## de sus ojos a la parte más cercana de su volumen (InvReach.box_distance,
## desde el 2026-11-11 a la noche; antes, desde el torso). Para operar con ella
## abierta y cerrarla al alejarse: no hace falta seguir mirándola.
func _box_in_reach(peer: int, box: InvContainer) -> bool:
	var actor := actor_of(peer)
	return actor != null \
			and InvReach.box_distance(eyes(actor, BaseRegistry.world_position(actor.state)), box) <= interaction_range


## Los ojos del personaje con los pies en `feet`: bajan si está agachado. De
## acá sale el rayo de la mano para recoger y abrir, y se mide la distancia a
## la caja abierta (InvReach). Salen del estado del personaje y del alto de su
## forma, iguales en el host y en los clientes; no de la cámara.
static func eyes(actor: ActorBody, feet: Vector3) -> Vector3:
	return feet + Vector3.UP * maxf(actor.stance_height(actor.state.stance) - EYES_BELOW_TOP, 0.3)


func _drop_spot(peer: int) -> Variant:
	var actor := actor_of(peer)
	if actor == null or _space == null:
		return null
	return find_drop_spot(_space, BaseRegistry.world_position(actor.state), actor.state.facing_yaw, drop_distance, _crowded)


## Si el lugar donde el cliente ya muestra lo que soltó (DROP_AT) sirve: cerca
## del personaje, con un margen por la demora (el cliente lo eligió con su
## personaje unos ticks por delante del host), y el resto como en
## find_drop_spot, mirado desde el pecho del personaje en el host. Así queda
## donde se ve y no salta.
func drop_spot_ok(peer: int, spot: Vector3) -> bool:
	var actor := actor_of(peer)
	if actor == null or _space == null or not spot.is_finite():
		return false
	var feet := BaseRegistry.world_position(actor.state)
	if Vector2(spot.x - feet.x, spot.z - feet.z).length() > drop_distance + 0.5 + DROP_LAG_MARGIN \
			or absf(spot.y - feet.y) > 1.5 + DROP_LAG_MARGIN:
		return false
	var found: Variant = _drop_place(_space, feet + Vector3.UP * CHEST, spot, _crowded, _drop_probe())
	return found != null and (found as Vector3).distance_to(spot) < 0.05


## Dónde cae lo que suelta un personaje con los pies en `feet`, mirando hacia
## `yaw`: adelante, o alrededor si ahí no se puede, siempre en el mismo orden.
## Tiene que verse desde el pecho (no se suelta atrás de una pared), tener piso
## abajo y lugar libre: ni dentro del personaje, ni de otro, ni de una pared o
## una caja, ni encima de otro objeto suelto (`crowded`, func(lugar) -> bool).
## null si no hay ningún lugar. La usa el host y, desde el 2026-11-04, también
## el cliente, para mostrar lo que suelta sin esperar (InvNet.predict_drop_spot).
static func find_drop_spot(space: PhysicsDirectSpaceState3D, feet: Vector3, yaw: float, distance: float, crowded: Callable) -> Variant:
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var chest := feet + Vector3.UP * CHEST
	var probe := _drop_probe()
	for reach: float in [distance, distance + 0.5, distance * 0.7]:
		for degrees: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]:
			var spot: Variant = _drop_place(space, chest, feet + forward.rotated(Vector3.UP, deg_to_rad(degrees)) * reach, crowded, probe)
			if spot != null:
				return spot
	return null


## El lugar sobre el piso justo abajo de `place`, si se puede soltar ahí: o null.
static func _drop_place(space: PhysicsDirectSpaceState3D, chest: Vector3, place: Vector3, crowded: Callable,
		probe: PhysicsShapeQueryParameters3D) -> Variant:
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, place + Vector3.UP * 0.3, WORLD_MASK)).is_empty():
		return null
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(place + Vector3.UP * 0.6, place + Vector3.DOWN * 1.5,
			WORLD_MASK))
	if floor_hit.is_empty():
		return null
	var normal: Vector3 = floor_hit["normal"]
	if normal.y < 0.7:
		return null
	var spot: Vector3 = floor_hit["position"]
	probe.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.25)
	if not space.intersect_shape(probe, 1).is_empty():
		return null
	if crowded.call(spot):
		return null
	return spot


static func _drop_probe() -> PhysicsShapeQueryParameters3D:
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = box
	probe.collision_mask = SOLID_MASK
	return probe


func _crowded(spot: Vector3) -> bool:
	return crowded_by(spot, world.values().map(func(item: Dictionary) -> Vector3: return item["pos"]))


## Si en `spot` ya hay algo suelto, de lo que está en `places`.
static func crowded_by(spot: Vector3, places: Array) -> bool:
	for other: Vector3 in places:
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
		elif not _box_in_reach(peer, box):
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
