class_name InvReach
extends RefCounted

## El alcance para recoger un objeto suelto y para abrir una caja: un rayo
## desde los ojos (desde el 2026-11-11 a la noche, pedido del usuario;
## docs/net/problema_objeto_sobre_un_borde.md). Es una sola regla, la misma en
## la máquina que mira (InvNet.interaction_target: lo que marca el indicador y
## lo que elige E) y en el host (InvAuthority: recoger y abrir). No hay otra
## copia de estas cuentas.
##
## - El rayo sale de los ojos del personaje (InvAuthority.eyes: bajan al
##   agacharse), en la dirección en que estira la mano (aim_direction: hacia lo
##   que señala la mira).
## - Gana lo primero que toca (first_hit): el modelo de un objeto suelto, la
##   colisión de una caja o cualquier otra cosa del nivel (que tapa). Los
##   personajes no tapan, como siempre, y las formas del propio no cuentan.
## - Alcanza si lo tocado está a no más de interaction_range del Tuning (grupo
##   «Recoger y abrir»), medido desde los ojos hasta el punto tocado. No hay
##   otra distancia ni otra vista: de un objeto largo cuenta la parte tocada, y
##   lo que asoma de un borde se agarra si el rayo lo toca.
## - Un objeto suelto se toca con los triángulos de su modelo tal como se ve en
##   el mundo (InvVisuals.world_model: escalado y apoyado, o la caja de color si
##   no tiene modelo). Se arman una vez por tipo en una TriangleMesh, sin el
##   nodo que lo dibuja: el host la consulta con sus objetos y su copia del
##   tipo, sin dibujar nada. La hitbox de agarre no cuenta.
## - Con la caja abierta (box_distance): la distancia de los ojos a la parte
##   más cercana de su volumen, con el mismo alcance, sin rayo ni vista.
##
## Del 2026-11-11 a la mañana hasta este cambio, la distancia se medía desde el
## torso hasta la caja envolvente del modelo, y la vista se probaba con unos
## pocos puntos del modelo (docs/net/problema_alcances_del_inventario.md).

## Tipo de objeto -> [modelo, malla, tamaño, lado, triángulos (TriangleMesh o
## null), su caja (AABB), huella]: se arma una vez por tipo y se vuelve a armar
## si cambia el modelo, la malla, el tamaño o los lados del tipo.
static var _items := {}

const _MESH := 4
const _BOUNDS := 5
const _PRINT := 6
const _FACES := 7

## Para la medición (inv_fisica_test): con cuántos objetos hizo la cuenta
## precisa el último first_hit.
static var last_tested := 0


## Las formas del propio personaje: el rayo no las toca.
static func own_shapes(actor: ActorBody) -> Array[RID]:
	var shapes: Array[RID] = []
	if actor != null:
		shapes.append(actor.get_rid())
	return shapes


## Lo primero que toca un rayo desde `origin` hacia `direction` (de largo 1),
## hasta `length` metros:
##
## - {"kind": "item", "id": su número} si es el modelo de un objeto suelto de
##   `world`;
## - {"kind": "box", "id": su número, "node": la InvContainer} si es una caja;
## - {"kind": "level"} si es cualquier otra cosa del nivel (InvAuthority.WORLD_MASK);
##
## siempre con "point" (dónde toca) y "distance" (desde `origin`); o {} si no
## toca nada. Los objetos sueltos también tapan a los de atrás. Con `skip`
## (func(número) -> bool), los objetos de `world` para los que da true no se
## tocan ni tapan (lo que esta máquina ya recogió y el host todavía no
## confirmó). Lo de `exclude` (own_shapes) no cuenta. Con un objeto y el nivel
## a la misma distancia (apoyado justo ahí), gana el objeto; con dos objetos a
## la misma distancia, el de número más bajo.
##
## `world` es, desde el 2026-11-14, un InvItemSpace: los objetos con su lugar y
## su giro, y un índice espacial. El rayo le pide al índice los objetos de las
## celdas que cruza, en orden, y solo con esos hace la cuenta precisa: los
## triángulos del modelo en el espacio del objeto, con su transformación entera
## (hasta ese día se restaba su lugar: los objetos no giraban). Deja de mirar
## cuando lo que ya tocó está más cerca que la celda siguiente. Con `at_tick`
## (0 o más), los objetos van en su pose de ese tick del host
## (InvItemSpace.pose_at), también los que se movieron desde entonces: así el
## host valida con lo que veía el jugador. Para las pruebas también se puede
## pasar un diccionario (número -> {"stack", "pos"}, o con "xf"): entonces se
## recorren todos, como hasta ese día. Es la cuenta de referencia.
##
## El cuerpo físico de los objetos (InvItemPhysics) no está en las capas que
## mira el rayo: un hueco del modelo que el cuerpo tapa sigue siendo hueco, y
## el rayo sigue hasta lo que hay detrás.
static func first_hit(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, length: float,
		world: Variant, catalog: InvCatalog, exclude: Array[RID] = [], skip := Callable(), at_tick := -1.0) -> Dictionary:
	last_tested = 0
	if space == null or not origin.is_finite() or not direction.is_finite() or not is_finite(length) or length <= 0.0 \
			or direction.length_squared() < 0.25:
		return {}
	var best := {}
	var best_t := length
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * length,
			InvAuthority.WORLD_MASK, exclude))
	if not hit.is_empty():
		best_t = origin.distance_to(hit["position"])
		var box := hit["collider"] as InvContainer
		if box != null and box.container_id != 0:
			best = {"kind": "box", "id": box.container_id, "node": box}
		else:
			best = {"kind": "level"}
		best["point"] = hit["position"]
		best["distance"] = best_t
	var found := [best, best_t]
	if world is InvItemSpace:
		var items := world as InvItemSpace
		var tested := {}
		for step: Array in items.index.along(origin, origin + direction * best_t):
			if step[0] > found[1]:
				break
			for uid: int in step[1]:
				tested[uid] = true
				var place := items.pose_at(uid, at_tick) if at_tick >= 0.0 else items.transform_of(uid)
				_try_item(uid, items.items[uid]["stack"], place, origin, direction, catalog, skip, found)
		if at_tick >= 0.0:
			# Lo que se movió desde ese tick puede haber estado en otras celdas.
			for uid in items.moved_since(at_tick):
				if not tested.has(uid) and items.items.has(uid):
					_try_item(uid, items.items[uid]["stack"], items.pose_at(uid, at_tick), origin, direction, catalog, skip,
							found)
	elif world is Dictionary:
		for uid: int in world:
			var item: Dictionary = world[uid]
			var place: Transform3D = item["xf"] if item.has("xf") else Transform3D(Basis.IDENTITY, item["pos"])
			_try_item(uid, item["stack"], place, origin, direction, catalog, skip, found)
	return found[0]


## La cuenta precisa con un objeto en `place`: si su modelo toca el rayo antes
## que lo mejor hasta ahora (`found`: [lo mejor, su distancia]), lo reemplaza.
static func _try_item(uid: int, stack: InvStack, place: Transform3D, origin: Vector3, direction: Vector3,
		catalog: InvCatalog, skip: Callable, found: Array) -> void:
	if skip.is_valid() and skip.call(uid):
		return
	var entry := _item(catalog.find(stack.def_id) if catalog != null else null)
	var triangles := entry[_MESH] as TriangleMesh
	if triangles == null:
		return
	last_tested += 1
	var best_t: float = found[1]
	var inverse := place.affine_inverse()
	var from := inverse * origin
	var to := inverse * (origin + direction * best_t)
	var bounds: AABB = entry[_BOUNDS]
	if bounds.intersects_segment(from, to) == null:
		return
	var touched := triangles.intersect_segment(from, to)
	if touched.is_empty():
		return
	var point: Vector3 = place * (touched["position"] as Vector3)
	var t := origin.distance_to(point)
	var best: Dictionary = found[0]
	if t < best_t or (t <= best_t and (best.get("kind", "") != "item" or uid < best["id"])):
		found[0] = {"kind": "item", "id": uid, "point": point, "distance": t}
		found[1] = t


## La dirección en que el personaje estira la mano, desde los ojos (`eyes`),
## hacia lo que señala la mira: la línea de la cámara, desde `from` hacia
## `look` y hasta `length` (InvNet.aim_length), elige lo primero que toca
## (first_hit, con lo mismo); la mano va desde los ojos hacia ese punto, o
## hacia la punta de la línea si no toca nada. En primera persona la cámara
## está casi en los ojos y es casi la misma línea; en tercera persona, ver algo
## con la cámara no deja atravesar lo que tapa los ojos: lo decide el rayo
## desde los ojos en esta dirección.
static func aim_direction(space: PhysicsDirectSpaceState3D, eyes: Vector3, from: Vector3, look: Vector3, length: float,
		world: Variant, catalog: InvCatalog, exclude: Array[RID] = [], skip := Callable()) -> Vector3:
	var hit := first_hit(space, from, look, length, world, catalog, exclude, skip)
	var target: Vector3 = hit["point"] if not hit.is_empty() else from + look * length
	var toward := target - eyes
	return toward / toward.length() if toward.length() > 0.001 else look


# --- Cajas abiertas -------------------------------------------------------------

## El punto del volumen `box` más cercano a `point`, en el mundo. `box` está en
## el espacio de `place` (lugar, giro y escala); si `point` está adentro, es él
## mismo. Exacto mientras los ejes de `place` sean perpendiculares (girar y
## escalar un nodo lo son; una escala desigual en un padre girado no).
static func closest_point(place: Transform3D, box: AABB, point: Vector3) -> Vector3:
	var center := place * box.get_center()
	var offset := point - center
	var result := center
	for axis in 3:
		var direction: Vector3 = place.basis[axis]
		var length := direction.length()
		if length < 0.000001:
			continue
		direction /= length
		var half := box.size[axis] * 0.5 * length
		result += direction * clampf(offset.dot(direction), -half, half)
	return result


## La distancia en 3D de `point` al volumen `box` (en el espacio de `place`).
static func distance_to(place: Transform3D, box: AABB, point: Vector3) -> float:
	return closest_point(place, box, point).distance_to(point)


## La distancia de los ojos (`eyes_at`) a la parte más cercana de la caja, con
## su lugar, su giro y su escala (InvContainer.reach_box, el volumen de su
## colisión): con la caja abierta, se opera y sigue abierta mientras sea como
## mucho el alcance. Como el rayo que la abrió tocó ese volumen, al abrirla ya
## se cumple.
static func box_distance(eyes_at: Vector3, box: InvContainer) -> float:
	return distance_to(box.global_transform, box.reach_box(), eyes_at)


# --- Objetos sueltos ------------------------------------------------------------------

## La caja que encierra los triángulos del modelo de un tipo tal como se ve
## suelto en el mundo (en el espacio del objeto: el origen es su punto de apoyo).
static func item_bounds(def: InvItemDef) -> AABB:
	return _item(def)[_BOUNDS]


## Los triángulos del modelo de un tipo tal como se ve suelto en el mundo, para
## consultar con un rayo (en el espacio del objeto), o null si no tiene.
static func item_mesh(def: InvItemDef) -> TriangleMesh:
	return _item(def)[_MESH]


## Los triángulos del modelo de un tipo tal como se ve suelto (de a tres
## puntos, en el espacio del objeto): con ellos se arma también su cuerpo
## físico automático (InvItemPhysics).
static func item_faces(def: InvItemDef) -> PackedVector3Array:
	return _item(def)[_FACES]


## Lo que va en la huella del catálogo (InvItemDef.fingerprint_text): los
## triángulos que toca el rayo, que deciden qué se agarra. Cuántos son y una
## suma (SHA-256) de todos sus vértices, redondeados a la décima de milímetro:
## dos PC con un modelo distinto en cualquier parte no se conectan.
static func fingerprint_of(def: InvItemDef) -> String:
	return _item(def)[_PRINT]


## Olvida lo armado por tipo (InvNet, al irse del árbol). Se arma de nuevo la
## primera vez que hace falta: al armar la huella del laboratorio, que recorre
## todo el catálogo, o al tirar un rayo cerca de un objeto de ese tipo.
static func clear_cache() -> void:
	_items.clear()
	InvItemPhysics.clear_cache()


static func _item(def: InvItemDef) -> Array:
	var known: Array = _items.get(def, [])
	if not known.is_empty() and (def == null or (known[0] == def.model and known[1] == def.mesh
			and known[2] == def.world_size and known[3] == def.size)):
		return known
	var model := InvVisuals.world_model(def)
	var faces := InvVisuals.faces(model)
	model.free()
	var triangles: TriangleMesh = null
	var bounds := AABB()
	if faces.size() >= 3:
		triangles = TriangleMesh.new()
		if not triangles.create_from_faces(faces):
			triangles = null
		bounds = AABB(faces[0], Vector3.ZERO)
		for vertex in faces:
			bounds = bounds.expand(vertex)
		# Un modelo plano tiene una caja sin espesor: con 1 mm, el rayo la cruza seguro.
		bounds = bounds.grow(0.001)
	var entry: Array = [def.model, def.mesh, def.world_size, def.size] if def != null else [null, null, 0.4, Vector2i.ONE]
	entry.append_array([triangles, bounds, _faces_print(faces), faces])
	_items[def] = entry
	return entry


static func _faces_print(faces: PackedVector3Array) -> String:
	var numbers := PackedInt32Array()
	numbers.resize(faces.size() * 3)
	for i in faces.size():
		var vertex := faces[i]
		numbers[i * 3] = roundi(vertex.x * 10000.0)
		numbers[i * 3 + 1] = roundi(vertex.y * 10000.0)
		numbers[i * 3 + 2] = roundi(vertex.z * 10000.0)
	var sum := HashingContext.new()
	sum.start(HashingContext.HASH_SHA256)
	sum.update(numbers.to_byte_array())
	return "rayo %d %s" % [faces.size() / 3.0, sum.finish().hex_encode().substr(0, 16)]
