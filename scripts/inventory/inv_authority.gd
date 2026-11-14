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
## su propio rayo desde los ojos del actor, con su estado y su postura al
## terminar el tick en que el jugador apretó E (desde el 2026-11-12, INT-01:
## los anota InvNet.record_aim_pose), en la dirección que manda el jugador
## (InvProtocol.direction_of, que la valida), y
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
##
## Desde el 2026-11-14 los objetos del mundo tienen física (InvBodies los
## simula acá) y cada uno puede estar en uno de tres lugares, nunca en dos:
##
## - **suelto en el mundo** (holder 0): en `world`, con su cuerpo;
## - **sostenido en el mundo** por un jugador (holder, con la sesión de ese
##   agarre): sigue en `world`, con su cuerpo, y no entra al inventario. Uno
##   solo a la vez por objeto y por jugador;
## - **en un inventario** (una grilla): ya no está en `world` ni tiene cuerpo.
##
## Las transiciones son pedidos, en el orden de siempre: GRAB (suelto →
## sostenido, si el rayo del host lo toca primero, al alcance), RELEASE y THROW
## (sostenido → suelto; THROW con un solo impulso), PICKUP (suelto o sostenido
## por el mismo jugador → inventario, entero o en parte: lo que no entra queda
## en el mundo, con su pose y su sujeción) y DROP / DROP_AT (inventario →
## suelto, en el aire, y cae). Además el host suelta solo (auto_release) lo que
## se traba, queda lejos o cuyo jugador muere, se va o se desconecta. Sostener
## no es llevar algo con el cursor dentro del inventario: eso es de InvUI y no
## cambia nada acá hasta que se deja.

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
## Lo soltado aparece entre esto debajo y esto arriba de los pies (el centro
## de su cuerpo), en metros (desde el 2026-11-14: CHEST y 0,45 m más o menos).
const DROP_LOW := 0.0
const DROP_HIGH := 1.5
## Con qué no puede tocarse lo soltado al aparecer: el nivel y las cajas, los
## personajes y las escaleras. Los demás objetos sueltos se miran por su caja
## (crowded_in), igual en el host y en el cliente.
const DROP_FIT_MASK := 1 | 2 | 4
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
## Los cuerpos de los objetos del mundo (InvBodies). Lo pone InvNet; sin él
## (las pruebas del modelo), el mundo es solo esta lista.
var bodies: InvBodies
## El tick del host en que se procesa (func() -> int). Lo pone InvNet.
var clock_tick: Callable

## Objetos en el mundo: uid -> {"stack": InvStack, "pos": Vector3, "xf":
## Transform3D, "label": bool, "lv" y "av" (velocidades), "sleep" (si
## duerme), "holder" (quién lo sostiene, 0 nadie), "session" (la de su
## agarre), "t" (el tick de esta pose)}. "label" es si se ve el cartel de
## arriba: lo apaga el InvPickupSpawn (show_label); lo soltado siempre lo
## lleva. "pos" es el origen de "xf": el centro de la base del objeto. Desde
## el 2026-11-14; hasta ese día eran solo "stack", "pos" y "label".
var world := {}
## Los mismos objetos para el rayo de la mano: con su giro, un índice espacial
## y la historia del último segundo de lo que se mueve (InvItemSpace).
var space := InvItemSpace.new()
## Cajas, por su número: id -> InvContainer.
var containers := {}
## Cuántos pedidos se aceptaron, rechazaron o llegaron repetidos.
var accepted := 0
var rejected := 0
var repeated := 0
## Muertes de prueba causadas por un consumible.
var deaths := 0
## Para las pruebas: el tick de lo que se veía con que se validó el último
## recoger o agarrar (-1: las poses de ahora).
var last_view_tick := -1.0

var _next_uid := 0
var _open_of := {}  # peer -> id de la caja que tiene abierta
var _welcomed := {}  # peer -> true: ya recibió el estado inicial
var _results := {}  # peer -> {número de pedido: [ok, motivo]}
var _result_order := {}  # peer -> números en el orden en que se recuerdan
var _equip_sent := {}  # peer -> id del tipo equipado que ya se contó a todos
var _space: PhysicsDirectSpaceState3D
var _aim_eyes: Variant = null  # los ojos para el rayo del pedido que se procesa (handle), o null
# Lo que cambió en el paso que se está procesando.
var _dirty_players := {}
var _dirty_boxes := {}
var _box_snapshot_for := {}  # peer -> caja: se le manda entera (la acaba de abrir)
var _world_set := {}
var _world_gone := {}
var _closed := {}  # peer -> [caja, motivo]
var _equip_all := false
var _use_answers := {}  # peer -> [hasta qué uso llegó, [[número, motivo], ...] de los que no se pudieron]
var _sessions := {}  # peer -> la última sesión de agarre que usó
var _hold_news := {}  # peer -> [[número, motivo], ...]: lo que el host le soltó solo, para avisarle
var _grabbed := {}  # peer -> [número, sesión, punto agarrado (3), distancia, giro (4)]: el agarre que se le contesta
## Lo último que tocó el rayo del host en _reach_reason, para el agarre:
## {"point", "eyes", "direction", "place" (la pose del objeto con que se validó)}.
var _last_reach := {}


func _init() -> void:
	space.history_ticks = InvNet.AIM_HISTORY_TICKS


func alloc_uid() -> int:
	_next_uid += 1
	return _next_uid


func _now_tick() -> int:
	return clock_tick.call() if clock_tick.is_valid() else -1


# --- Estado del mundo -------------------------------------------------------

func add_spawn(spawn: InvPickupSpawn) -> void:
	if spawn.item == null or catalog.find(spawn.item.id) != spawn.item:
		push_warning("[inventario] %s no tiene un objeto del catálogo" % spawn.get_path())
		return
	var limit := spawn.item.stack_limit()
	if spawn.quantity > limit:
		push_warning("[inventario] %s pide %d, pero en una pila entran %d" % [spawn.get_path(), spawn.quantity, limit])
	_put_in_world(InvStack.make(alloc_uid(), spawn.item.id, clampi(spawn.quantity, 1, limit), spawn.initial_state()),
			spawn.spawn_transform(), spawn.show_label)


## Pone una pila en el mundo, suelta, en `place` (un Transform3D, o un
## Vector3: la base del objeto, sin girar). `asleep`: arranca quieta y dormida
## (lo colocado en el mapa); si no, cae desde ahí (lo soltado), con `velocity`.
func _put_in_world(stack: InvStack, place: Variant, label := true, asleep := true, velocity := Vector3.ZERO) -> void:
	var xf: Transform3D = place if place is Transform3D else Transform3D(Basis.IDENTITY, place as Vector3)
	world[stack.uid] = {"stack": stack, "pos": xf.origin, "xf": xf, "label": label, "lv": velocity, "av": Vector3.ZERO,
			"sleep": asleep, "holder": 0, "session": 0, "t": _now_tick()}
	space.catalog = catalog
	space.put(stack.uid, stack, xf)
	_world_set[stack.uid] = true
	_world_gone.erase(stack.uid)
	if bodies != null:
		bodies.spawn(stack.uid)


## Lo saca del mundo (entra a un inventario): su cuerpo se va, y con él la
## sujeción, si la tenía.
func _take_from_world(uid: int) -> void:
	world.erase(uid)
	space.remove(uid)
	_world_gone[uid] = true
	_world_set.erase(uid)
	if bodies != null:
		bodies.despawn(uid)


## Cómo viaja un objeto suelto: [pila, x, y, z, cartel, el giro (cuatro), la
## velocidad (tres), la velocidad de giro (tres), si duerme, quién lo sostiene,
## su sesión, el tick de esa pose]. Desde el 2026-11-14; hasta ese día, solo
## las cinco primeras.
func _world_entry(uid: int) -> Array:
	var item: Dictionary = world[uid]
	var xf: Transform3D = item["xf"]
	var q := xf.basis.orthonormalized().get_rotation_quaternion()
	var lv: Vector3 = item.get("lv", Vector3.ZERO)
	var av: Vector3 = item.get("av", Vector3.ZERO)
	return [item["stack"].to_array(), xf.origin.x, xf.origin.y, xf.origin.z, item.get("label", true), q.x, q.y, q.z, q.w,
			lv.x, lv.y, lv.z, av.x, av.y, av.z, item.get("sleep", false), item.get("holder", 0), item.get("session", 0),
			item.get("t", -1)]


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
	# Lo que sostenía el actor anterior se suelta: el nuevo empieza con la mano vacía.
	release_all(old_actor.owner_peer_id, "volviste con otro personaje")
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
	# Se cortó o se fue: lo que sostenía se suelta ya, aunque su personaje
	# quede esperándolo en el mundo.
	release_all(peer, "se cortó la conexión")
	_welcomed.erase(peer)
	_open_of.erase(peer)
	_results.erase(peer)
	_result_order.erase(peer)
	_box_snapshot_for.erase(peer)
	_closed.erase(peer)
	_dirty_players.erase(peer)
	_sessions.erase(peer)
	_hold_news.erase(peer)
	if not _world_set.is_empty():
		flush({})


## El actor de ese jugador se va del mundo: con él se va su inventario, y lo
## que sostenía queda suelto.
func actor_left(peer: int) -> void:
	if _equip_sent.has(peer):
		_equip_sent.erase(peer)
	_open_of.erase(peer)
	release_all(peer, "tu personaje ya no está")
	if not _world_set.is_empty():
		flush({})


func is_welcomed(peer: int) -> bool:
	return _welcomed.has(peer)


func welcomed_peers() -> Array:
	return _welcomed.keys()


func open_container_of(peer: int) -> int:
	return _open_of.get(peer, 0)


# --- Pedidos -----------------------------------------------------------------

## Procesa un pedido: valida y aplica en el mismo paso, y manda lo que cambió.
## `aim_eyes`: para recoger y abrir, desde dónde sale el rayo de la mano (los
## ojos del personaje al terminar el tick del pedido, que anota InvNet); con
## null, los de ahora.
func handle(peer: int, seq: int, op: int, args: Array, physics: PhysicsDirectSpaceState3D, aim_eyes: Variant = null) -> void:
	_space = physics
	_aim_eyes = aim_eyes
	var reason := _run(peer, op, args)
	_space = null
	_aim_eyes = null
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
	# Los de otra PC ya llegan con esta forma (InvProtocol.parse_request); los del
	# jugador del host no pasan por ahí: se miran acá (desde el 2026-11-14).
	if not InvProtocol.args_ok(op, a):
		return "pedido inválido: no tiene la forma de ese pedido"
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
		InvProtocol.Op.GRAB:
			return _grab(peer, a)
		InvProtocol.Op.RELEASE:
			return _release(peer, a[0], a[1], Vector3.ZERO)
		InvProtocol.Op.THROW:
			var direction: Variant = InvProtocol.direction_at(a, 2)
			if direction == null:
				return "pedido inválido: la dirección del lanzamiento no sirve"
			return _release(peer, a[0], a[1], direction)
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


## Soltar, desde el inventario propio o desde una caja abierta: aparece
## adelante del personaje, a la altura del pecho, y cae (desde el 2026-11-14;
## hasta ese día se apoyaba en el piso y sin piso cerca no se soltaba). Con
## `proposed` (DROP_AT, desde el 2026-11-04), donde el cliente ya lo muestra,
## si ese lugar sirve (drop_spot_ok); si no, donde lo elige el host. Si no cabe
## en ningún lado sin tocar una pared, a un personaje u otro objeto, no se
## suelta nada.
func _drop(peer: int, ref: int, uid: int, ver: int, quantity: int, proposed: Variant = null) -> String:
	var src := _grid_for(peer, ref)
	if src[1] != "":
		return src[1]
	var grid: InvGrid = src[0]
	var reason := InvOps.can_take(grid, uid, ver, quantity)
	if reason != "":
		return reason
	var def := grid.def_of(uid)
	var spot: Variant = proposed if proposed != null and drop_spot_ok(peer, proposed, def) else _drop_spot(peer, def)
	if spot == null:
		return "no hay lugar cerca para soltarlo"
	var out := InvOps.take(grid, uid, ver, quantity, alloc_uid())
	_put_in_world(out[1], spot, true, false)
	_mark(peer, ref)
	return ""


## Recoger: [número del objeto, dirección de la mano, tick, tick de lo que se
## veía]. Lo primero que toca el rayo del host desde los ojos del actor, al
## alcance, tiene que ser ese objeto (_reach_reason). Si no entra entero, se
## lleva lo que entra y el resto queda, con su cuerpo, su pose y, si lo
## sostenía, su sujeción. Desde el 2026-11-14: uno que sostiene otro jugador no
## se recoge (no se le quita), y uno que sostiene el mismo jugador se recoge sin
## rayo (ya lo tiene en la mano; el agarre ya se validó).
func _pickup(peer: int, inventory: InvInventory, a: Array) -> String:
	var uid: int = a[0]
	var item: Dictionary = world.get(uid, {})
	if item.is_empty():
		return "ya no está: lo agarró otro jugador"
	var stack: InvStack = item["stack"]
	var actor := actor_of(peer)
	if actor == null:
		return "estás muy lejos para agarrarlo"
	var holder: int = item.get("holder", 0)
	if holder != 0 and holder != peer:
		return "lo tiene otro jugador en la mano"
	if holder == 0:
		var bounds := InvReach.item_bounds(catalog.find(stack.def_id))
		var reason := _reach_reason(actor, a, "item", uid, (item["xf"] as Transform3D) * bounds.get_center(),
				bounds.size.length(), "estás muy lejos para agarrarlo", "no lo ves desde ahí: hay algo en el medio",
				"no lo estás mirando")
		if reason != "":
			return reason
	elif InvProtocol.direction_of(a) == null:
		return "pedido inválido: la dirección de la mano no sirve"
	var result := InvOps.insert(inventory.grid, stack)
	if result["reason"] != "":
		return result["reason"]
	if result["taken"] >= stack.quantity:
		_take_from_world(uid)
	else:
		stack.quantity -= result["taken"]
		stack.ver += 1
		space.set_stack(uid, stack)
		if bodies != null:
			bodies.refresh_view(uid)
		_world_set[uid] = true
	_dirty_players[peer] = true
	return ""


# --- Sostener en el mundo (desde el 2026-11-14) --------------------------------

## Agarrar: [número del objeto, dirección de la mano, tick, tick de lo que se
## veía, sesión]. Como recoger: lo primero que toca el rayo del host, al
## alcance, tiene que ser ese objeto, y el punto que toca, pasado al espacio
## del objeto, es por donde se agarra (el de verdad, no su centro). El objeto
## no tiene que tenerlo nadie, el jugador no tiene que tener otro, y la sesión
## tiene que ser más nueva que la última que usó. Le contesta por dónde lo
## agarró ("g"), para que su máquina use el mismo punto.
func _grab(peer: int, a: Array) -> String:
	var uid: int = a[0]
	var session: int = a[6]
	var item: Dictionary = world.get(uid, {})
	if item.is_empty():
		return "ya no está"
	if session < 1 or session > InvProtocol.MAX_SESSION or session <= _sessions.get(peer, 0):
		return "pedido inválido: ese agarre ya pasó"
	var actor := actor_of(peer)
	if actor == null or not actor.is_inside_tree():
		return "todavía no tenés personaje"
	var holder: int = item.get("holder", 0)
	if holder != 0:
		return "ya lo tenés en la mano" if holder == peer else "lo tiene otro jugador en la mano"
	for other: int in world:
		if world[other].get("holder", 0) == peer:
			return "ya tenés otro en la mano"
	var bounds := InvReach.item_bounds(catalog.find((item["stack"] as InvStack).def_id))
	var reason := _reach_reason(actor, a, "item", uid, (item["xf"] as Transform3D) * bounds.get_center(),
			bounds.size.length(), "estás muy lejos para agarrarlo", "no lo ves desde ahí: hay algo en el medio",
			"no lo estás mirando")
	if reason != "":
		return reason
	_sessions[peer] = session
	# El punto que tocó el rayo del host, en el espacio del objeto, con la pose
	# en que el host lo validó (la de lo que veía el jugador).
	var place: Transform3D = _last_reach.get("place", item["xf"])
	var anchor := place.affine_inverse() * (_last_reach["point"] as Vector3)
	var eyes_at: Vector3 = _last_reach["eyes"]
	var direction: Vector3 = _last_reach["direction"]
	# El giro se lleva relativo al yaw de la cámara (decidido por el usuario: el
	# objeto gira con vos). El del input más nuevo de ese jugador; hasta que
	# llegue su primer input con este agarre, que lo trae él.
	var yaw: float = bodies.look_yaw_of(peer) if bodies != null else NAN
	if is_nan(yaw):
		yaw = atan2(-direction.x, -direction.z)
	var pitch := asin(clampf(direction.y, -1.0, 1.0))
	var now: Transform3D = item["xf"]
	var rotation := (Basis(Vector3.UP, yaw).inverse() * now.basis.orthonormalized()).get_rotation_quaternion()
	var distance := eyes_at.distance_to(_last_reach["point"])
	item["holder"] = peer
	item["session"] = session
	_world_set[uid] = true
	if bodies != null:
		bodies.begin_hold(uid, peer, session, anchor, distance, rotation, pitch)
	_grabbed[peer] = [uid, session, anchor.x, anchor.y, anchor.z, distance, rotation.x, rotation.y, rotation.z, rotation.w]
	return ""


## Soltar o lanzar: [número, sesión] (y la dirección, al lanzar). Solo si lo
## sostiene ese jugador con esa sesión: una sesión vieja (un pedido que llegó
## después de otro agarre) no hace nada. Lanzar suma un solo impulso, el común
## del Tuning (InvItemPhysics.throw_impulse_of), hacia `direction`.
func _release(peer: int, uid: int, session: int, direction: Variant) -> String:
	var item: Dictionary = world.get(uid, {})
	if item.is_empty():
		return "ya no está"
	if item.get("holder", 0) != peer or item.get("session", 0) != session:
		return "ya no lo tenías en la mano"
	item["holder"] = 0
	_world_set[uid] = true
	var impulse := Vector3.ZERO
	if direction is Vector3:
		var def := catalog.find((item["stack"] as InvStack).def_id)
		impulse = (direction as Vector3) * InvItemPhysics.throw_impulse_of(def, tuning)
	if bodies != null:
		bodies.end_hold(uid, impulse)
	return ""


## El host lo suelta solo (InvBodies: se trabó, quedó lejos, el jugador murió
## o ya no está; o el jugador se fue): sin impulso, y se le avisa por qué.
func auto_release(uid: int, reason: String) -> void:
	var item: Dictionary = world.get(uid, {})
	if item.is_empty() or item.get("holder", 0) == 0:
		if bodies != null:
			bodies.end_hold(uid)
		return
	var peer: int = item["holder"]
	item["holder"] = 0
	_world_set[uid] = true
	if bodies != null:
		bodies.end_hold(uid)
	(_hold_news.get_or_add(peer, []) as Array).append([uid, reason])
	flush({})


## Suelta todo lo que sostiene ese jugador (se fue, se cortó, cambió de actor).
func release_all(peer: int, reason: String) -> void:
	for uid: int in world.keys():
		if world[uid].get("holder", 0) == peer:
			world[uid]["holder"] = 0
			_world_set[uid] = true
			if bodies != null:
				bodies.end_hold(uid)
			(_hold_news.get_or_add(peer, []) as Array).append([uid, reason])


## Quién sostiene ese objeto (0 nadie).
func holder_of(uid: int) -> int:
	return world.get(uid, {}).get("holder", 0)


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
## (los del tick del pedido si InvNet los pasó a handle, o los de ahora con su
## estado y su postura), en la dirección del pedido, contra el nivel, las cajas
## y los objetos sueltos del host como están ahora. "" si lo primero que toca, al alcance,
## es lo pedido (`kind` y `id`); si no, el motivo: `far` si lo pedido es lo
## primero pero más allá del alcance, `blocked` si al alcance hay otra cosa
## antes, `missed` si no lo toca, y uno propio si la dirección no sirve.
## `center` y `size` (lo pedido, en el mundo) solo alargan la línea para elegir
## el motivo (FAR_LOOK).
##
## Los objetos sueltos (desde el 2026-11-14, que se mueven) van en la pose que
## tenían en el tick del host que mostraba esa máquina al pedir (el último
## argumento: InvProtocol.view_tick_of; InvItemSpace.pose_at, con la historia
## del último segundo). Los ojos son los del tick del input del pedido (INT-01).
## No son el mismo instante del host, a propósito: son lo que el jugador tenía
## en pantalla al apretar, su personaje en su presente y los demás objetos un
## poco en el pasado (la interpolación). Un tick de lo que se veía de hace más
## de un segundo, o futuro, usa las poses de ahora. El nivel y las cajas no se
## mueven: van como están.
func _reach_reason(actor: ActorBody, a: Array, kind: String, id: int, center: Vector3, size: float, far: String,
		blocked: String, missed: String) -> String:
	var direction: Variant = InvProtocol.direction_of(a)
	if direction == null:
		return "pedido inválido: la dirección de la mano no sirve"
	var at: Vector3 = _aim_eyes if _aim_eyes is Vector3 else eyes(actor, BaseRegistry.world_position(actor.state))
	var length := minf(maxf(interaction_range + FAR_LOOK, at.distance_to(center) + size), 1000.0)
	var view_tick := InvProtocol.view_tick_of(InvProtocol.Op.PICKUP, a)
	var now := _now_tick()
	if view_tick >= 0.0 and (now < 0 or view_tick > now or view_tick < now - InvNet.AIM_HISTORY_TICKS):
		view_tick = -1.0
	space.catalog = catalog
	var hit := InvReach.first_hit(_space, at, direction, length, space, catalog, InvReach.own_shapes(actor), Callable(),
			view_tick)
	last_view_tick = view_tick
	_last_reach = {}
	if hit.is_empty():
		return missed
	var reached: bool = hit["distance"] <= interaction_range
	if hit["kind"] == kind and hit.get("id", 0) == id:
		if reached and kind == "item":
			_last_reach = {"point": hit["point"], "eyes": at, "direction": direction,
					"place": space.pose_at(id, view_tick) if view_tick >= 0.0 else space.transform_of(id)}
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


func _drop_spot(peer: int, def: InvItemDef) -> Variant:
	var actor := actor_of(peer)
	if actor == null or _space == null:
		return null
	return find_drop_spot(_space, BaseRegistry.world_position(actor.state), actor.state.facing_yaw, drop_distance, def,
			crowded_in.bind(space, []))


## Si el lugar donde el cliente ya muestra lo que soltó (DROP_AT) sirve: cerca
## del personaje, con un margen por la demora (el cliente lo eligió con su
## personaje unos ticks por delante del host), y el resto como en
## find_drop_spot, mirado desde el pecho del personaje en el host. Así queda
## donde se ve y no salta.
func drop_spot_ok(peer: int, place: Variant, def: InvItemDef = null) -> bool:
	var actor := actor_of(peer)
	if actor == null or _space == null:
		return false
	var xf: Transform3D = place if place is Transform3D else Transform3D(Basis.IDENTITY, place as Vector3)
	if not xf.origin.is_finite() or not xf.basis.is_finite():
		return false
	var feet := BaseRegistry.world_position(actor.state)
	var center := xf * InvItemPhysics.body_bounds(def).get_center()
	if Vector2(center.x - feet.x, center.z - feet.z).length() > drop_distance + 0.5 + DROP_LAG_MARGIN \
			or center.y - feet.y > DROP_HIGH + DROP_LAG_MARGIN or feet.y - center.y > DROP_LOW + DROP_LAG_MARGIN:
		return false
	return _drop_place(_space, feet + Vector3.UP * CHEST, xf, def, crowded_in.bind(space, []))


## Dónde aparece lo que suelta un personaje con los pies en `feet`, mirando
## hacia `yaw`: adelante, a la altura del pecho, o alrededor si ahí no se
## puede, siempre en el mismo orden; con el giro del personaje (el yaw). Desde
## el 2026-11-14 aparece en el aire y cae, así que no hace falta piso: se puede
## soltar colgado de un cable o saltando. Tiene que verse desde el pecho (no se
## suelta atrás de una pared) y caber: sus formas (InvItemPhysics) no pueden
## tocar el nivel, una caja, una escalera ni un personaje, y su caja no puede
## tocar la de otro objeto suelto (`crowded`, func(lugar, tipo) -> bool: así
## la cuenta da lo mismo en el cliente, que no tiene los cuerpos). Devuelve el
## lugar (Transform3D) o null si no cabe en ningún lado. La usa el host y,
## desde el 2026-11-04, también el cliente, para mostrar lo que suelta sin
## esperar (InvNet.predict_drop_spot). Hasta el 2026-11-14 buscaba piso hasta
## 1,5 m debajo de los pies y lo apoyaba ahí.
static func find_drop_spot(physics: PhysicsDirectSpaceState3D, feet: Vector3, yaw: float, distance: float, def: InvItemDef,
		crowded: Callable) -> Variant:
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var chest := feet + Vector3.UP * CHEST
	var turn := Basis(Vector3.UP, yaw)
	var center := InvItemPhysics.body_bounds(def).get_center()
	for height: float in [CHEST, CHEST - 0.45, CHEST + 0.45]:
		for reach: float in [distance, distance + 0.5, distance * 0.7]:
			for degrees: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0]:
				var point := feet + forward.rotated(Vector3.UP, deg_to_rad(degrees)) * reach + Vector3.UP * height
				var place := Transform3D(turn, point - turn * center)
				if _drop_place(physics, chest, place, def, crowded):
					return place
	return null


## Si se puede soltar en `place`: se ve desde el pecho y cabe.
static func _drop_place(physics: PhysicsDirectSpaceState3D, chest: Vector3, place: Transform3D, def: InvItemDef,
		crowded: Callable) -> bool:
	var center := place * InvItemPhysics.body_bounds(def).get_center()
	if not physics.intersect_ray(PhysicsRayQueryParameters3D.create(chest, center, WORLD_MASK)).is_empty():
		return false
	if not InvItemPhysics.fits(physics, def, place, DROP_FIT_MASK):
		return false
	return not crowded.call(place, def)


## Si la caja de un objeto de tipo `def` en `place` toca la de algún objeto
## suelto de `items` (InvItemSpace, con su índice) o de `extra` (otros lugares
## ocupados: [[Transform3D, InvItemDef], ...], lo soltado sin confirmar).
static func crowded_in(place: Transform3D, def: InvItemDef, items: InvItemSpace, extra: Array) -> bool:
	var box := place * InvItemPhysics.local_bounds(def)
	if items != null:
		for uid in items.index.near(box):
			var item: Dictionary = items.items.get(uid, {})
			if item.is_empty():
				continue
			var other := items.catalog.find((item["stack"] as InvStack).def_id) if items.catalog != null else null
			if ((item["xf"] as Transform3D) * InvItemPhysics.local_bounds(other)).intersects(box):
				return true
	for taken: Array in extra:
		if ((taken[0] as Transform3D) * InvItemPhysics.local_bounds(taken[1])).intersects(box):
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
		# Por dónde agarró lo que pidió agarrar, y lo que el host le soltó solo
		# (desde el 2026-11-14).
		if _grabbed.has(peer):
			payload["g"] = _grabbed[peer]
		if _hold_news.has(peer):
			payload["hr"] = _hold_news[peer]
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
	_grabbed.clear()
	_hold_news.clear()
	_equip_all = false
