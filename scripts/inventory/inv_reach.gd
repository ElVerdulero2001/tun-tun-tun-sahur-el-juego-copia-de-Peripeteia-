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
## - Un objeto suelto se toca con su forma de selección (desde el 2026-11-15,
##   decisión del usuario en docs/net/prompt_claude_revision_objetos_fisicos.md):
##   - con una hitbox de agarre propia que sirve (InvPickupHitbox.active), esa
##     forma, aunque el rayo pase por un hueco del modelo: no hace falta tocar
##     antes sus triángulos;
##   - sin hitbox (o con «Forma del modelo», o con una que no sirve), los
##     triángulos de su modelo tal como se ve en el mundo (InvVisuals.world_model:
##     escalado y apoyado, o la caja de color si no tiene modelo).
##   Las dos se arman una vez por tipo, sin el nodo que lo dibuja: el host las
##   consulta con sus objetos y su copia del tipo, sin dibujar nada.
## - **El acceso** (con la hitbox): tocar la hitbox no alcanza. El punto del
##   modelo más cercano al punto tocado (access_point) tiene que verse desde los
##   ojos, sin el nivel ni una caja en el medio, y estar a no más del alcance
##   (interaction_range) más ACCESS_SLACK. Así una hitbox que asoma de una pared
##   no deja agarrar lo que está detrás, y una más grande que su modelo ayuda a
##   apuntar sin dejar agarrar algo que está más lejos que el alcance. El punto tocado sigue
##   siendo por donde se agarra (un anclaje virtual, aunque caiga en un hueco).
## - Con la caja abierta (box_distance): la distancia de los ojos a la parte
##   más cercana de su volumen, con el mismo alcance, sin rayo ni vista.
##
## Del 2026-11-11 a la mañana hasta ese día, la distancia se medía desde el
## torso hasta la caja envolvente del modelo, y la vista se probaba con unos
## pocos puntos del modelo (docs/net/problema_alcances_del_inventario.md). Del
## 2026-11-11 a la noche al 2026-11-15 la hitbox de agarre no se usaba.

## Tipo de objeto -> [modelo, malla, tamaño, lado, triángulos (TriangleMesh o
## null), su caja (AABB), huella]: se arma una vez por tipo y se vuelve a armar
## si cambia el modelo, la malla, el tamaño o los lados del tipo.
static var _items := {}

const _MESH := 4
const _BOUNDS := 5
const _PRINT := 6
const _FACES := 7

## Tipo -> [clave (hitbox_key), forma, su lugar, sus planos si es convexa, su
## caja en el espacio del objeto]: la hitbox de agarre de cada tipo, armada una
## vez para el rayo.
static var _hitboxes := {}
## Tipo -> [los triángulos del modelo (de a tres puntos), la caja de cada uno
## (mínimo y máximo, de a dos)]: para buscar el punto del modelo más cercano.
static var _closest := {}

## Lo más que puede estar el punto del modelo usado para el acceso más allá del
## alcance, en metros (elegido por Claude el 2026-11-15): una hitbox puede ayudar
## a apuntar, no a alcanzar más lejos. Es lo que puede quedar el modelo detrás
## del punto tocado de una hitbox razonable.
const ACCESS_SLACK := 0.25
## Cuánto antes del punto del modelo puede tocar el rayo del acceso el nivel sin
## que cuente como tapado (el objeto apoyado contra una pared), en metros.
const ACCESS_TOUCH := 0.01

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
## toca nada. De un objeto, además, "by": "hitbox" o "model" (con qué se lo
## tocó) y, con la hitbox, "access": el punto del modelo con que se comprobó el
## acceso. Los objetos sueltos también tapan a los de atrás; uno cuya hitbox
## se toca pero no tiene acceso no tapa ni se elige. Con `skip`
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
## mira el rayo: un hueco del cuerpo no cambia con qué se apunta, y una hitbox
## más grande no lo agranda.
static func first_hit(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3, length: float,
		world: Variant, catalog: InvCatalog, exclude: Array[RID] = [], skip := Callable(), at_tick := -1.0, reach := -1.0) -> Dictionary:
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
	# [lo mejor, su distancia, el espacio, lo excluido y el alcance, para el acceso]
	var found := [best, best_t, space, exclude, reach if reach > 0.0 else length]
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


## La cuenta precisa con un objeto en `place`: si su forma de selección (su
## hitbox de agarre o, sin una, su modelo) toca el rayo antes que lo mejor hasta
## ahora (`found`: [lo mejor, su distancia, el espacio, lo excluido]) y, con la
## hitbox, tiene acceso (access_point), lo reemplaza.
static func _try_item(uid: int, stack: InvStack, place: Transform3D, origin: Vector3, direction: Vector3,
		catalog: InvCatalog, skip: Callable, found: Array) -> void:
	if skip.is_valid() and skip.call(uid):
		return
	var def := catalog.find(stack.def_id) if catalog != null else null
	var best_t: float = found[1]
	var inverse := place.affine_inverse()
	var from := inverse * origin
	var to := inverse * (origin + direction * best_t)
	var local_point: Variant = null
	var by := "model"
	var hitbox := _hitbox(def)
	if not hitbox.is_empty():
		last_tested += 1
		by = "hitbox"
		local_point = _hitbox_hit(hitbox, from, to)
	else:
		var entry := _item(def)
		var triangles := entry[_MESH] as TriangleMesh
		if triangles == null:
			return
		last_tested += 1
		var bounds: AABB = entry[_BOUNDS]
		if bounds.intersects_segment(from, to) == null:
			return
		var touched := triangles.intersect_segment(from, to)
		if not touched.is_empty():
			local_point = touched["position"]
	if local_point == null:
		return
	var point: Vector3 = place * (local_point as Vector3)
	var t := origin.distance_to(point)
	var best: Dictionary = found[0]
	if not (t < best_t or (t <= best_t and (best.get("kind", "") != "item" or uid < best["id"]))):
		return
	var result := {"kind": "item", "id": uid, "point": point, "distance": t, "by": by}
	if by == "hitbox":
		var access: Variant = access_point(found[2], origin, found[4], def, place, local_point, found[3])
		if access == null:
			return
		result["access"] = access
	found[0] = result
	found[1] = t


## El acceso de un objeto elegido por su hitbox de agarre: el punto de su
## modelo más cercano al punto tocado (`local_point`, en el espacio del objeto),
## en el mundo, si se ve desde `origin` (ni el nivel ni una caja en el medio,
## salvo a ACCESS_TOUCH del punto) y está a no más de `reach` + ACCESS_SLACK
## de `origin` (`reach`: el alcance); si no, null. Sin modelo (sin triángulos), el centro de su caja.
## Es la regla de acceso de la hitbox, la misma en todas las máquinas.
static func access_point(space: PhysicsDirectSpaceState3D, origin: Vector3, reach: float, def: InvItemDef,
		place: Transform3D, local_point: Vector3, exclude: Array[RID] = []) -> Variant:
	var nearest := closest_model_point(def, local_point)
	var target := place * nearest
	var distance := origin.distance_to(target)
	if distance > reach + ACCESS_SLACK:
		return null
	if space != null and distance > ACCESS_TOUCH:
		var toward := (target - origin) / distance
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, target - toward * ACCESS_TOUCH,
				InvAuthority.WORLD_MASK, exclude))
		if not hit.is_empty():
			return null
	return target


## Si lo sostenido se ve: el punto de su modelo más cercano al punto agarrado
## (`anchor`, en el espacio del objeto; con una hitbox puede caer en un hueco)
## se ve desde `eyes`, sin el nivel ni una caja en el medio, salvo a
## ACCESS_TOUCH del punto (apretado contra una pared, se sigue viendo). Es la
## misma mirada que el acceso (access_point), sin límite de distancia. El host
## suelta lo que no se ve durante Hold Break Time (InvBodies._carry): lo pidió
## el usuario el 2026-11-15, después de llevar la tabla detrás de un muro y
## seguir moviéndola.
static func held_visible(space: PhysicsDirectSpaceState3D, eyes: Vector3, def: InvItemDef, place: Transform3D,
		anchor: Vector3, exclude: Array[RID] = []) -> bool:
	return access_point(space, eyes, INF, def, place, anchor, exclude) != null


## El punto de los triángulos del modelo de un tipo más cercano a `point` (en
## el espacio del objeto). Sin triángulos, el centro de su caja.
static func closest_model_point(def: InvItemDef, point: Vector3) -> Vector3:
	var data := _closest_data(def)
	var faces: PackedVector3Array = data[0]
	if faces.size() < 3:
		return item_bounds(def).get_center()
	var boxes: PackedVector3Array = data[1]
	var best := faces[0]
	var best_d := INF
	for i in range(0, faces.size() - 2, 3):
		var low := boxes[i]
		var high := boxes[i + 1]
		var outside := (low - point).max(Vector3.ZERO) + (point - high).max(Vector3.ZERO)
		if outside.length_squared() >= best_d:
			continue
		var candidate := _closest_on_triangle(point, faces[i], faces[i + 1], faces[i + 2])
		var d := candidate.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = candidate
	return best


## [los triángulos, y la caja de cada uno en el mismo lugar que su primer
## punto: lo más bajo en i y lo más alto en i + 1 (el tercero queda sin usar)].
static func _closest_data(def: InvItemDef) -> Array:
	var faces := item_faces(def)
	var known: Array = _closest.get(def, [])
	if not known.is_empty() and known[0] == faces:
		return [known[0], known[1]]
	var boxes := PackedVector3Array()
	boxes.resize(faces.size())
	for i in range(0, faces.size() - 2, 3):
		boxes[i] = faces[i].min(faces[i + 1]).min(faces[i + 2])
		boxes[i + 1] = faces[i].max(faces[i + 1]).max(faces[i + 2])
	_closest[def] = [faces, boxes]
	return [faces, boxes]


## El punto del triángulo abc más cercano a p (Ericson, Real-Time Collision
## Detection, 5.1.5).
static func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


# --- La hitbox de agarre para el rayo -----------------------------------------------

## La caja de la hitbox de agarre que vale para un tipo, en el espacio del
## objeto, o vacía si no tiene (InvItemPhysics.local_bounds la suma al índice).
static func hitbox_bounds(def: InvItemDef) -> AABB:
	var hitbox := _hitbox(def)
	return hitbox[4] if not hitbox.is_empty() else AABB()


## Lo que cambia la hitbox de un tipo (para saber si hay que armarla de nuevo).
static func hitbox_key(def: InvItemDef) -> String:
	var hitbox := InvPickupHitbox.active(def)
	if hitbox == null:
		return ""
	var text := hitbox.effective_text()
	if hitbox.kind == InvPickupHitbox.Kind.CUSTOM and hitbox.custom_shape != null:
		text += " %d" % hitbox.custom_shape.get_instance_id()
	return text


## [clave, forma, su lugar, sus planos (si es convexa o caja), su caja], o
## vacío si el tipo se elige por su modelo.
static func _hitbox(def: InvItemDef) -> Array:
	var key := hitbox_key(def)
	if key == "":
		return []
	var known: Array = _hitboxes.get(def, [])
	if not known.is_empty() and known[0] == key:
		return known
	var hitbox := InvPickupHitbox.active(def)
	var shape := hitbox.build_shape()
	var planes: Array[Plane] = []
	if shape is BoxShape3D:
		planes.assign(Geometry3D.build_box_planes((shape as BoxShape3D).size * 0.5))
	elif shape is ConvexPolygonShape3D:
		planes = _hull_planes(shape as ConvexPolygonShape3D)
	var entry := [key, shape, hitbox.local_transform(), planes, hitbox.bounds()]
	_hitboxes[def] = entry
	return entry


## Los planos de las caras de una forma convexa (de las caras que arma Godot
## con sus puntos), mirando para afuera, sin repetir. Una cara del casco deja
## todos los puntos de un lado: así se orienta (mirar el centro de los puntos
## falla en una forma muy fina, como un machete de 2 cm de grueso), y la que no
## los deja de un lado no es una cara.
static func _hull_planes(shape: ConvexPolygonShape3D) -> Array[Plane]:
	var planes: Array[Plane] = []
	var points := shape.points
	var faces := shape.get_debug_mesh().get_faces()
	for i in range(0, faces.size() - 2, 3):
		var normal := (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
		if normal.length_squared() < 1e-14:
			continue
		var plane := Plane(normal.normalized(), faces[i])
		var low := 0.0
		var high := 0.0
		for point in points:
			var d := plane.distance_to(point)
			low = minf(low, d)
			high = maxf(high, d)
		if high > 0.0002 and low < -0.0002:
			continue
		if high > 0.0002:
			plane = -plane
		var repeated := false
		for other in planes:
			if other.normal.dot(plane.normal) > 0.99999 and absf(other.d - plane.d) < 0.00001:
				repeated = true
				break
		if not repeated:
			planes.append(plane)
	if planes.size() < 4 and not points.is_empty():
		# Sin caras (no debería pasar): la caja de sus puntos.
		var box := AABB(points[0], Vector3.ZERO)
		for point in points:
			box = box.expand(point)
		for plane in Geometry3D.build_box_planes(box.size * 0.5):
			planes.append(Plane(plane.normal, plane.d + plane.normal.dot(box.get_center())))
	return planes


## Dónde toca el segmento `from`-`to` (en el espacio del objeto) la hitbox, en
## ese espacio, o null. Si `from` ya está adentro, la toca ahí mismo.
static func _hitbox_hit(hitbox: Array, from: Vector3, to: Vector3) -> Variant:
	var bounds: AABB = hitbox[4]
	if bounds.grow(0.001).intersects_segment(from, to) == null and not bounds.grow(0.001).has_point(from):
		return null
	var place: Transform3D = hitbox[2]
	var inverse := place.affine_inverse()
	var a := inverse * from
	var b := inverse * to
	var t := segment_fraction(hitbox[1], hitbox[3], a, b)
	if t < 0.0:
		return null
	return from + (to - from) * t


## Cuánto del segmento a-b (de 0 a 1, en el espacio de la forma) recorre hasta
## entrar en la forma, o -1 si no la toca. Si `a` está adentro, 0. Caja y
## convexa con sus planos; esfera, cilindro (parado, a lo largo de y) y cápsula
## con sus cuentas.
static func segment_fraction(shape: Shape3D, planes: Array[Plane], a: Vector3, b: Vector3) -> float:
	if shape is SphereShape3D:
		return _sphere_fraction(a, b, Vector3.ZERO, (shape as SphereShape3D).radius)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return _cylinder_fraction(a, b, cylinder.radius, cylinder.height * 0.5)
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var half := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		var best := _cylinder_fraction(a, b, capsule.radius, half)
		for end in [Vector3.UP * half, Vector3.DOWN * half]:
			var t := _sphere_fraction(a, b, end, capsule.radius)
			if t >= 0.0 and (best < 0.0 or t < best):
				best = t
		return best
	if planes.is_empty():
		return -1.0
	var enter := 0.0
	var leave := 1.0
	var delta := b - a
	for plane in planes:
		var den := plane.normal.dot(delta)
		var dist := plane.distance_to(a)
		if absf(den) < 1e-12:
			if dist > 0.0:
				return -1.0
			continue
		var t := -dist / den
		if den < 0.0:
			enter = maxf(enter, t)
		else:
			leave = minf(leave, t)
		if enter > leave:
			return -1.0
	return enter


static func _sphere_fraction(a: Vector3, b: Vector3, center: Vector3, radius: float) -> float:
	var d := b - a
	var m := a - center
	var c := m.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var aa := d.length_squared()
	if aa < 1e-14:
		return -1.0
	var bb := m.dot(d)
	var disc := bb * bb - aa * c
	if disc < 0.0:
		return -1.0
	var t := (-bb - sqrt(disc)) / aa
	return t if t >= 0.0 and t <= 1.0 else -1.0


## Un cilindro parado (a lo largo de y) de radio `radius` y de -half a half.
static func _cylinder_fraction(a: Vector3, b: Vector3, radius: float, half: float) -> float:
	var inside := Vector2(a.x, a.z).length_squared() <= radius * radius and absf(a.y) <= half
	if inside:
		return 0.0
	var d := b - a
	var best := -1.0
	# El costado.
	var aa := d.x * d.x + d.z * d.z
	if aa > 1e-14:
		var bb := a.x * d.x + a.z * d.z
		var c := a.x * a.x + a.z * a.z - radius * radius
		var disc := bb * bb - aa * c
		if disc >= 0.0:
			var t := (-bb - sqrt(disc)) / aa
			if t >= 0.0 and t <= 1.0 and absf(a.y + d.y * t) <= half:
				best = t
	# Las tapas.
	if absf(d.y) > 1e-12:
		for cap in [half, -half]:
			var t: float = (cap - a.y) / d.y
			if t >= 0.0 and t <= 1.0:
				var at := a + d * t
				if at.x * at.x + at.z * at.z <= radius * radius and (best < 0.0 or t < best):
					best = t
	return best


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
	_hitboxes.clear()
	_closest.clear()
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
