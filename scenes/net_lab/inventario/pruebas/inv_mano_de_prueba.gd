extends RefCounted

## Para las pruebas del inventario (desde el 2026-11-11 a la noche): recoger y
## abrir llevan la dirección de la mano, y el host tira su propio rayo desde los
## ojos del personaje con ella (InvReach.first_hit). Esto busca, como un
## jugador que apunta, una dirección desde los ojos de `actor` cuyo primer
## contacto sea ese objeto suelto o esa caja: prueba puntos de su modelo (o de
## su caja), del más cercano a los ojos al más lejano, y se queda con el
## primero que el rayo toca antes que otra cosa. No mira el alcance: si queda
## lejos, el host lo rechaza por eso. Si no encuentra ninguno, hacia el centro
## (y el host dirá por qué no).
##
## Usa lo que tiene la máquina: en el host (o jugando solo), sus objetos
## (InvAuthority.world); en un cliente, los de su réplica.
##
## Se usa con preload, sin class_name: no es parte del juego.

## Cuántos puntos por lado se prueban en la caja del objetivo.
const STEPS := 5


## Si `args` es de recoger o abrir y trae solo el número, le suma la dirección
## de la mano de `actor`; si no, lo devuelve como está.
static func aimed(net: InvNet, actor: ActorBody, op: int, args: Array) -> Array:
	if (op == InvProtocol.Op.PICKUP or op == InvProtocol.Op.OPEN) and args.size() == 1 and actor != null:
		return request_args(net, actor, op, args[0])
	return args


## Los argumentos de un pedido de recoger (`op` PICKUP) o abrir (OPEN) de `actor`.
static func request_args(net: InvNet, actor: ActorBody, op: int, id: int) -> Array:
	var direction := toward_box(net, actor, net.container(id)) if op == InvProtocol.Op.OPEN else toward_item(net, actor, id)
	return InvProtocol.aimed_args(id, direction)


## Si desde los ojos de `actor` hay alguna dirección cuyo primer contacto sea
## ese objeto (PICKUP) o esa caja (OPEN), a cualquier distancia.
static func in_sight(net: InvNet, actor: ActorBody, op: int, id: int) -> bool:
	if op == InvProtocol.Op.OPEN:
		var box := net.container(id)
		return box != null and _find(net, actor, box.global_transform, box.reach_box(), "box", id) != null
	var item: Dictionary = _world(net).get(id, {})
	return not item.is_empty() and _find(net, actor, Transform3D(Basis.IDENTITY, item["pos"]),
			InvReach.item_bounds(net.catalog.find((item["stack"] as InvStack).def_id)), "item", id) != null


## Una dirección desde los ojos de `actor` que toca primero ese objeto suelto.
static func toward_item(net: InvNet, actor: ActorBody, uid: int) -> Vector3:
	var world := _world(net)
	var item: Dictionary = world.get(uid, {})
	if item.is_empty():
		return Vector3.FORWARD
	var def := net.catalog.find((item["stack"] as InvStack).def_id)
	return _toward(net, actor, Transform3D(Basis.IDENTITY, item["pos"]), InvReach.item_bounds(def), "item", uid)


## Una dirección desde los ojos de `actor` que toca primero esa caja.
static func toward_box(net: InvNet, actor: ActorBody, box: InvContainer) -> Vector3:
	if box == null:
		return Vector3.FORWARD
	return _toward(net, actor, box.global_transform, box.reach_box(), "box", box.container_id)


static func _world(net: InvNet) -> Dictionary:
	return net.authority.world if net.authority != null else net.replica.world


static func _toward(net: InvNet, actor: ActorBody, place: Transform3D, box: AABB, kind: String, id: int) -> Vector3:
	var found: Variant = _find(net, actor, place, box, kind, id)
	if found != null:
		return found
	return (place * box.get_center() - InvAuthority.eyes(actor, actor.global_position)).normalized()


static func _find(net: InvNet, actor: ActorBody, place: Transform3D, box: AABB, kind: String, id: int) -> Variant:
	var space := net.get_world_3d().direct_space_state
	var eyes := InvAuthority.eyes(actor, actor.global_position)
	var inner := box.grow(-minf(box.size.x, minf(box.size.y, box.size.z)) * 0.02)
	var points: Array = [place * box.get_center()]
	for i in STEPS:
		for j in STEPS:
			for k in STEPS:
				points.append(place * (inner.position + inner.size * Vector3(i, j, k) / (STEPS - 1.0)))
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(eyes) < b.distance_squared_to(eyes))
	var world := _world(net)
	for point: Vector3 in points:
		var direction := (point - eyes).normalized()
		var hit := InvReach.first_hit(space, eyes, direction, 50.0, world, net.catalog, InvReach.own_shapes(actor))
		if hit.get("kind", "") == kind and hit.get("id", 0) == id:
			return direction
	return null
