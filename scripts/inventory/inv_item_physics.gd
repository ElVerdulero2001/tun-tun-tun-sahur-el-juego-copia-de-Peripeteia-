class_name InvItemPhysics
extends RefCounted

## El cuerpo físico de cada tipo de objeto suelto (desde el 2026-11-14): con
## qué formas choca, armadas una vez por tipo y guardadas acá, para todos los
## objetos de ese tipo (las formas son recursos compartidos). No se arma nada
## por cuadro.
##
## Son formas válidas para un cuerpo dinámico de Jolt: convexas o primitivas,
## nunca la malla cóncava del modelo. De dónde salen:
##
## - Con InvItemDef.body_shape (InvBodyShape) de caja, esfera, cilindro o
##   forma propia: esa forma, con su lugar y su giro.
## - Si no (o con la forma del modelo), la automática, con los triángulos del
##   modelo tal como se ve suelto (los mismos que toca el rayo de la mano,
##   InvReach): el modelo se parte en tajadas a lo largo de un eje y, en cada
##   tajada, cada pedazo que no se toca con los demás es una forma convexa con
##   los puntos de sus triángulos. Una tabla larga son unas pocas cajas
##   convexas en fila; las patas de un banquito, una forma cada una; un marco,
##   sus lados, sin tapar el hueco del medio. Elige sola cuántas tajadas y qué
##   eje, salvo que body_shape lo diga.
##
## Nada de esto se usa para elegir ni agarrar: eso son los triángulos del
## modelo (InvReach). Así un hueco que el cuerpo tapa no se vuelve agarrable.
##
## Todo está en el espacio del objeto suelto, el mismo de InvReach y del
## cuerpo (InvWorldItem): el origen es el centro de la base del modelo. El
## centro de masa lo calcula Jolt con estas formas (no es el origen ni el
## centro de la caja).

## Capas de física del objeto suelto: la 4 (desde el 2026-11-14; del 2026-11-06
## al 2026-11-11 ahí iba la forma para apuntar, ya sacada). Choca con el nivel y
## las cajas (1), las escaleras (3) y los demás objetos sueltos (4); no con los
## personajes (2): lo decidió el usuario (2026-10-31 y 2026-11-14), así el
## personaje, que su PC predice, no se traba con objetos que simula solo el host.
const LAYER := 8
const MASK := 1 | 4 | 8
## Para ver si un objeto cabe en un lugar al soltarlo: el nivel, las cajas,
## las escaleras, los personajes (no se suelta adentro de nadie) y los demás
## objetos sueltos.
const FIT_MASK := 1 | 2 | 4 | 8

## Margen (radio convexo de Jolt) de cada forma: redondea las aristas sin
## cambiar el tamaño. Uno grande se comería una llave de 1 cm.
const SHAPE_MARGIN := 0.004
## La forma automática: cuántas tajadas, como mucho, y en cuántas celdas, a lo
## largo del lado más largo, se busca qué pedazos se tocan.
const AUTO_MAX_PARTS := 4
const AUTO_CELLS := 12
## Como mucho, cuántas formas convexas tiene un cuerpo automático.
const MAX_PIECES := 16
## Cuántos puntos, como mucho, lleva cada forma convexa (Jolt arma el casco con
## ellos); los demás quedan adentro.
const POINT_CELLS := 4
## Un lado más finito que esto se engorda hasta esto, para que la forma tenga
## volumen (un modelo plano, una hoja).
const MIN_THICKNESS := 0.004

## Tipo -> [clave de lo que lo arma, partes ([forma, lugar]...), caja, huella]
static var _cache := {}


## Las formas del cuerpo de un tipo: [[Shape3D, Transform3D en el espacio del
## objeto], ...]. Siempre al menos una (sin modelo, la caja de su color).
static func parts(def: InvItemDef) -> Array:
	return _entry(def)[1]


## La caja que encierra las formas del cuerpo, en el espacio del objeto.
static func body_bounds(def: InvItemDef) -> AABB:
	return _entry(def)[2]


## La caja que encierra todo lo del objeto: el modelo (lo que se ve y se
## agarra) y su cuerpo. Es la que se anota en el índice del rayo.
static func local_bounds(def: InvItemDef) -> AABB:
	var model := InvReach.item_bounds(def)
	var body := body_bounds(def)
	if not model.has_volume():
		return body
	return model.merge(body) if body.has_volume() else model


## Lo que va en la huella del catálogo: las formas del cuerpo, con sus números
## redondeados a la décima de milímetro.
static func fingerprint_of(def: InvItemDef) -> String:
	return _entry(def)[3]


## La masa de un objeto de ese tipo, en kg. Por ahora todos iguales (el Tuning,
## Item Mass): no es un sistema de peso, solo lo que necesita Jolt. Si un día
## hay peso por tipo, va acá (y en throw_impulse_of).
static func mass_of(_def: InvItemDef, tuning: ActorTuning) -> float:
	return tuning.item_mass if tuning != null else 2.0


## El impulso de un lanzamiento, en N·s (kg·m/s), el mismo para todos (el
## Tuning, Throw Impulse). Un objeto de masa m sale a impulso / m m/s más de lo
## que ya traía. Si un día el peso cambia el lanzamiento, va acá.
static func throw_impulse_of(_def: InvItemDef, tuning: ActorTuning) -> float:
	return tuning.throw_impulse if tuning != null else 16.0


## Si un objeto de ese tipo cabe en `place` (su lugar y su giro) sin tocar nada
## de `mask`: cada forma de su cuerpo, una por una. `exclude`: lo que no cuenta.
static func fits(space: PhysicsDirectSpaceState3D, def: InvItemDef, place: Transform3D, mask := FIT_MASK,
		exclude: Array[RID] = []) -> bool:
	if space == null or not place.origin.is_finite():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = mask
	query.exclude = exclude
	query.margin = 0.0
	for part: Array in parts(def):
		query.shape = part[0]
		query.transform = place * (part[1] as Transform3D)
		if not space.intersect_shape(query, 1).is_empty():
			return false
	return true


## Olvida lo armado (InvNet, al irse del árbol, como InvReach.clear_cache).
static func clear_cache() -> void:
	_cache.clear()


static func _key(def: InvItemDef) -> Array:
	if def == null:
		return [null, null, 0.4, Vector2i.ONE, ""]
	var shape := InvBodyShape.active_body(def)
	return [def.model, def.mesh, def.world_size, def.size, shape.effective_text() if shape != null else ""]


static func _entry(def: InvItemDef) -> Array:
	var key := _key(def)
	var known: Array = _cache.get(def, [])
	if not known.is_empty() and known[0] == key:
		return known
	var shape := InvBodyShape.active_body(def)
	var list: Array = []
	if shape != null and shape.kind != InvPickupHitbox.Kind.MODEL:
		var built := shape.build_shape()
		if built != null:
			if built.resource_path == "":
				built.margin = SHAPE_MARGIN
			list.append([built, shape.local_transform()])
	if list.is_empty():
		var parts_count := shape.auto_parts if shape != null else 0
		var axis := (shape.auto_axis - 1) if shape != null and shape.auto_axis != InvBodyShape.Axis.AUTO else -1
		list = _auto(InvReach.item_faces(def), parts_count, axis)
	var box := AABB()
	var first := true
	for part: Array in list:
		var part_box := _shape_bounds(part[0], part[1])
		box = part_box if first else box.merge(part_box)
		first = false
	var entry := [key, list, box, _print(list)]
	_cache[def] = entry
	return entry


# --- La forma automática ---------------------------------------------------------

## Las formas convexas de la forma automática, con los triángulos del modelo
## (`faces`, de a tres puntos). `count`: tajadas (0, las elige); `axis`: 0, 1
## o 2 (-1, lo elige).
static func _auto(faces: PackedVector3Array, count: int, axis: int) -> Array:
	var points := _samples(faces)
	if points.size() < 4:
		# Sin triángulos: una caja chica, para que haya cuerpo (no debería pasar:
		# un modelo vacío ya se ve como la caja de su color).
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * 0.1
		box.margin = SHAPE_MARGIN
		return [[box, Transform3D(Basis.IDENTITY, Vector3.UP * 0.05)]]
	if count == 1:
		# Una sola forma convexa con todo, aunque haya pedazos que no se tocan
		# (lo que promete el panel: «1: una sola forma convexa», que tapa los huecos).
		var whole := ConvexPolygonShape3D.new()
		whole.points = _hull_points(points)
		whole.margin = SHAPE_MARGIN
		return [[whole, Transform3D.IDENTITY]]
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	var longest := bounds.get_longest_axis_size()
	var cell := maxf(longest / AUTO_CELLS, 0.002)
	var chosen_axis := axis
	var chosen_count := count
	var pieces: Array = []
	if chosen_axis < 0 or chosen_count <= 0:
		# Elige: con AUTO_MAX_PARTS tajadas en cada eje, el que encuentra más
		# pedazos separados (huecos); si en ninguno hay más pedazos que tajadas
		# (no hay huecos), el eje más largo, con tajadas según lo alargado.
		var best_axis := bounds.get_longest_axis_index()
		var best: Array = []
		for candidate in [best_axis, (best_axis + 1) % 3, (best_axis + 2) % 3]:
			if axis >= 0 and candidate != axis:
				continue
			var split := _split(points, bounds, candidate, AUTO_MAX_PARTS, cell)
			if split.size() > best.size():
				best = split
				best_axis = candidate
		chosen_axis = best_axis
		if count > 0:
			pieces = _split(points, bounds, chosen_axis, count, cell)
		elif best.size() > AUTO_MAX_PARTS:
			pieces = best
		else:
			var sizes := [bounds.size.x, bounds.size.y, bounds.size.z]
			sizes.sort()
			var slabs := clampi(roundi(bounds.size[chosen_axis] / maxf(sizes[1], 0.001)), 1, AUTO_MAX_PARTS)
			pieces = _split(points, bounds, chosen_axis, slabs, cell)
	else:
		pieces = _split(points, bounds, chosen_axis, chosen_count, cell)
	if pieces.size() > MAX_PIECES:
		pieces = _merge_small(pieces, MAX_PIECES)
	var list: Array = []
	for piece: PackedVector3Array in pieces:
		var hull := ConvexPolygonShape3D.new()
		hull.points = _hull_points(piece)
		hull.margin = SHAPE_MARGIN
		list.append([hull, Transform3D.IDENTITY])
	return list


## Puntos sobre los triángulos: sus vértices y, en los grandes, puntos
## repartidos, para que una tajada que cruza un triángulo grande lo tenga.
static func _samples(faces: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if faces.size() < 3:
		return out
	var bounds := AABB(faces[0], Vector3.ZERO)
	for vertex in faces:
		bounds = bounds.expand(vertex)
	var spacing := maxf(bounds.get_longest_axis_size() / 24.0, 0.002)
	# Los vértices compartidos por varios triángulos van una sola vez (al
	# milímetro): así una granada de 1546 triángulos da unos pocos miles de
	# puntos y no el triple.
	var seen := {}
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var edge := maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))
		var steps := clampi(ceili(edge / spacing), 1, 8)
		for u in steps + 1:
			for v in steps + 1 - u:
				var fu := float(u) / steps
				var fv := float(v) / steps
				var point := a + (b - a) * fu + (c - a) * fv
				var key := Vector3i(roundi(point.x * 1000.0), roundi(point.y * 1000.0), roundi(point.z * 1000.0))
				if not seen.has(key):
					seen[key] = true
					out.append(point)
	return out


## Los puntos partidos en `slabs` tajadas a lo largo de `axis` y, en cada
## tajada, en pedazos que no se tocan (con celdas de `cell`): una lista de
## pedazos, cada uno con sus puntos. Los bordes de cada tajada se comparten con
## la siguiente, así las formas se tocan y no quedan rendijas.
static func _split(points: PackedVector3Array, bounds: AABB, axis: int, slabs: int, cell: float) -> Array:
	var low := bounds.position[axis]
	var length := maxf(bounds.size[axis], 0.0001)
	var width := length / slabs
	var pieces: Array = []
	for slab in slabs:
		var from := low + width * slab
		var to := from + width
		var inside := PackedVector3Array()
		for point in points:
			var at := point[axis]
			if at >= from - cell * 0.5 and at <= to + cell * 0.5:
				inside.append(point)
		if inside.size() == 0:
			continue
		for piece in _components(inside, cell):
			if piece.size() >= 1:
				pieces.append(piece)
	return pieces


## Los puntos en pedazos que no se tocan: dos puntos van juntos si sus celdas
## (de lado `cell`) son vecinas, también en diagonal.
static func _components(points: PackedVector3Array, cell: float) -> Array:
	var cells := {}  # Vector3i -> índices de los puntos
	for i in points.size():
		var key := Vector3i(floori(points[i].x / cell), floori(points[i].y / cell), floori(points[i].z / cell))
		var list: PackedInt32Array = cells.get(key, PackedInt32Array())
		list.append(i)
		cells[key] = list
	var keys := cells.keys()
	keys.sort()
	var group := {}
	var pieces: Array = []
	for start: Vector3i in keys:
		if group.has(start):
			continue
		var piece := PackedVector3Array()
		var pending: Array[Vector3i] = [start]
		group[start] = true
		while not pending.is_empty():
			var current: Vector3i = pending.pop_back()
			for index in cells[current]:
				piece.append(points[index])
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var next := current + Vector3i(dx, dy, dz)
						if cells.has(next) and not group.has(next):
							group[next] = true
							pending.append(next)
		pieces.append(piece)
	return pieces


## Si quedaron demasiados pedazos, junta los más chicos con el más cercano.
static func _merge_small(pieces: Array, limit: int) -> Array:
	var list := pieces.duplicate()
	while list.size() > limit:
		list.sort_custom(func(a: PackedVector3Array, b: PackedVector3Array) -> bool: return a.size() < b.size())
		var small: PackedVector3Array = list.pop_front()
		var center := _center(small)
		var nearest := 0
		for i in list.size():
			if _center(list[i]).distance_to(center) < _center(list[nearest]).distance_to(center):
				nearest = i
		var joined: PackedVector3Array = list[nearest]
		joined.append_array(small)
		list[nearest] = joined
	return list


static func _center(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	return sum / maxf(points.size(), 1)


## Los puntos que van a la forma convexa de un pedazo: en cada una de las
## POINT_CELLS³ celdas de su caja, el más alejado de su centro (los de adentro
## no cambian el casco). Un pedazo plano se engorda MIN_THICKNESS.
static func _hull_points(piece: PackedVector3Array) -> PackedVector3Array:
	var box := AABB(piece[0], Vector3.ZERO)
	for point in piece:
		box = box.expand(point)
	var center := box.get_center()
	var size := box.size.max(Vector3.ONE * 0.0001)
	var kept := {}  # Vector3i -> punto
	for point in piece:
		var at := ((point - box.position) / size * POINT_CELLS).floor()
		var key := Vector3i(clampi(int(at.x), 0, POINT_CELLS - 1), clampi(int(at.y), 0, POINT_CELLS - 1),
				clampi(int(at.z), 0, POINT_CELLS - 1))
		var other: Variant = kept.get(key)
		if other == null or point.distance_squared_to(center) > (other as Vector3).distance_squared_to(center):
			kept[key] = point
	var keys := kept.keys()
	keys.sort()
	var out := PackedVector3Array()
	for key in keys:
		out.append(kept[key])
	for axis in 3:
		if box.size[axis] < MIN_THICKNESS:
			var thick := PackedVector3Array()
			var push := Vector3.ZERO
			push[axis] = (MIN_THICKNESS - box.size[axis]) * 0.5
			for point in out:
				thick.append(point + push)
				thick.append(point - push)
			out = thick
	while out.size() < 4:
		out.append(out[0] + Vector3(0.001, 0.001, 0.001) * out.size())
	return out


static func _shape_bounds(shape: Shape3D, place: Transform3D) -> AABB:
	if shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if points.is_empty():
			return AABB(place.origin, Vector3.ZERO)
		var box := AABB(place * points[0], Vector3.ZERO)
		for point in points:
			box = box.expand(place * point)
		return box
	return place * shape.get_debug_mesh().get_aabb()


static func _print(list: Array) -> String:
	var texts := PackedStringArray()
	for part: Array in list:
		var shape: Shape3D = part[0]
		var text := "%s %s" % [shape.get_class(), _transform_text(part[1])]
		if shape is ConvexPolygonShape3D:
			var numbers := PackedInt32Array()
			for point in (shape as ConvexPolygonShape3D).points:
				numbers.append_array([roundi(point.x * 10000.0), roundi(point.y * 10000.0), roundi(point.z * 10000.0)])
			var sum := HashingContext.new()
			sum.start(HashingContext.HASH_SHA256)
			sum.update(numbers.to_byte_array())
			text += " %d %s" % [numbers.size() / 3.0, sum.finish().hex_encode().substr(0, 16)]
		else:
			text += " " + InvPickupHitbox._shape_text(shape)
		texts.append(text)
	return "cuerpo %d: %s" % [list.size(), "; ".join(texts)]


static func _transform_text(place: Transform3D) -> String:
	var values := PackedStringArray()
	for axis in 3:
		values.append(InvPickupHitbox._vector_text(place.basis[axis]))
	values.append(InvPickupHitbox._vector_text(place.origin))
	return " ".join(values)
