class_name InvItemPhysics
extends RefCounted

## El cuerpo físico de cada tipo de objeto suelto (desde el 2026-11-14): con qué
## formas choca, armadas una vez por tipo y guardadas acá, para todos los
## objetos de ese tipo (las formas son recursos compartidos). No se arma nada
## por cuadro.
##
## Son formas válidas para un cuerpo dinámico de Jolt: convexas o primitivas,
## nunca la malla cóncava del modelo. Salen de InvItemDef.body_shape
## (InvBodyShape), desde el 2026-11-15:
##
## - una caja, esfera, cilindro o forma propia: esa forma, con su lugar y su giro;
## - del modelo: las formas preparadas en el editor y guardadas en el .tres
##   (InvBodyShape.shapes). Se preparan con generate(), la herramienta de Godot
##   (una forma convexa, Mesh.create_convex_shape, o varias, la descomposición
##   de MeshInstance3D.create_multiple_convex_collisions), y el juego solo las
##   carga: el .exe exportado no necesita la descomposición, que solo está en
##   el editor.
##
## Sin cuerpo preparado (un tipo sin body_shape, o con las formas del modelo sin
## generar o desactualizadas) el cuerpo es una sola forma convexa del modelo,
## armada acá una vez (Mesh.create_convex_shape, que sí está en el juego
## exportado), y la consola lo avisa una vez por tipo: tapa los huecos. Entra en
## la huella con sus puntos, así dos PC que la armen distinto no se conectan.
## Hasta el 2026-11-15 se partía el modelo en tajadas con un algoritmo propio,
## que dejaba rendijas (docs/net/problemas_objetos_fisicos_2026-11-14.md).
##
## Nada de esto se usa para elegir ni agarrar: eso es la hitbox de agarre, si
## el tipo tiene una, o si no los triángulos del modelo (InvReach). Así un hueco
## del cuerpo no cambia con qué se apunta, y una hitbox más generosa no agranda
## el cuerpo.
##
## Todo está en el espacio del objeto suelto, el mismo de InvReach y del
## cuerpo (InvWorldItem): el origen es el centro de la base del modelo. El
## centro de masa (center_of_mass) lo calcula esto con las formas, igual en
## todas las máquinas, y el cuerpo del host lo usa tal cual.

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
## Como mucho, cuántas formas tiene un cuerpo.
const MAX_PIECES := InvBodyShape.MAX_PARTS
## Una forma convexa del modelo con más puntos que esto se simplifica (Jolt
## arma el casco con todos). Simplificar recorta los extremos de lo redondo
## (el frasco de veneno perdía 7 mm de alto): los del catálogo llegan a 159.
const HULL_POINT_LIMIT := 256
## Cuánto se achican las formas para ver si un lugar está libre mientras se
## sostiene (blocked_inset): Jolt deja que lo que se apoya se meta un poco en lo
## otro, y eso no tiene que contar como chocar. Tiene que ser más que lo que
## Jolt deja metido sin corregir (su tolerancia de penetración, 2 mm en
## project.godot desde el 2026-11-15; la de fábrica, 2 cm, dejaba objetos
## apoyados hasta 2 cm adentro del piso, y la mano los daba por trabados).
const INSET := 0.005
## Con cuánto de diferencia, en cada lado, la caja de las formas preparadas
## sigue contando como la del modelo (generate, para avisar en el panel).
const COVER_TOLERANCE := 0.006
## Lo más que pueden quedar adentro del modelo los bordes de la descomposición
## para que suggest la elija, en metros.
const TRIM_TOLERANCE := 0.003
## Un modelo más fino que esto en su lado más chico va con una caja ajustada:
## Jolt deja las formas convexas planas metidas en el piso. Medido el
## 2026-11-15 con la llave (1,4 cm) y el machete (2,3 cm), apoyados inclinados:
## de 20 a 70 mm adentro con cualquier forma convexa (la de Godot, la
## simplificada, la de la descomposición); con la caja, 0.
const FLAT_LIMIT := 0.025

## Tipo -> [clave de lo que lo arma, partes ([forma, lugar]...), caja, huella,
## estado ("preparado", "sin preparar: …"), centro de masa, partes achicadas]
static var _cache := {}
## Tipos ya avisados en la consola (sin cuerpo preparado). Solo en el juego: en
## el editor, el panel Objetos ya muestra el estado en «Cuerpo físico», y el
## aviso salía al abrir el editor por el ítem nuevo vacío del panel.
static var _warned := {}


## Las formas del cuerpo de un tipo: [[Shape3D, Transform3D en el espacio del
## objeto], ...]. Siempre al menos una (sin modelo, la caja de su color).
static func parts(def: InvItemDef) -> Array:
	return _entry(def)[1]


## La caja que encierra las formas del cuerpo, en el espacio del objeto.
static func body_bounds(def: InvItemDef) -> AABB:
	return _entry(def)[2]


## La caja que encierra todo lo del objeto: el modelo (lo que se ve), su cuerpo
## y su hitbox de agarre. Es la que se anota en el índice del rayo, así el rayo
## encuentra la hitbox aunque sea más grande que el modelo.
static func local_bounds(def: InvItemDef) -> AABB:
	var box := InvReach.item_bounds(def)
	for other in [body_bounds(def), InvReach.hitbox_bounds(def)]:
		if not (other as AABB).has_volume():
			continue
		box = other if not box.has_volume() else box.merge(other)
	return box


## Lo que va en la huella del catálogo: las formas del cuerpo, con sus números
## redondeados a la décima de milímetro, y si estaba preparado.
static func fingerprint_of(def: InvItemDef) -> String:
	return _entry(def)[3]


## "preparado", o por qué no (y entonces usa una sola forma convexa del modelo).
static func status_of(def: InvItemDef) -> String:
	return _entry(def)[4]


## El centro de masa, en el espacio del objeto: el de las formas del cuerpo,
## pesadas por su volumen (cada forma, llena y del mismo material). El cuerpo
## del host lo usa tal cual (InvWorldItem), y la mano lo predice con el mismo.
static func center_of_mass(def: InvItemDef) -> Vector3:
	return _entry(def)[5]


## Las formas achicadas INSET por cada lado, con su lugar: para ver si un lugar
## está libre sin contar lo que Jolt deja que se apoye un poco adentro.
static func inset_parts(def: InvItemDef) -> Array:
	return _entry(def)[6]


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
	return _free(space, parts(def), place, mask, exclude)


## Si el objeto, con sus formas achicadas INSET (inset_parts), toca algo de
## `mask` en `place`: con lo que está apoyado o rozando no alcanza, tiene que
## estar metido. Lo usan la mano adelantada del cliente y el host al validar lo
## que afirma el cliente (InvHoldMotion).
static func blocked_inset(space: PhysicsDirectSpaceState3D, def: InvItemDef, place: Transform3D, mask: int,
		exclude: Array[RID] = []) -> bool:
	return not _free(space, inset_parts(def), place, mask, exclude)


## Cuánto está metido el objeto en algo de `mask` en `place`, en metros: lo más
## separados que quedan los puntos de contacto que da Jolt con sus formas
## enteras (su profundidad). 0 si no toca nada.
static func depth(space: PhysicsDirectSpaceState3D, def: InvItemDef, place: Transform3D, mask: int,
		exclude: Array[RID] = []) -> float:
	if space == null or not place.origin.is_finite():
		return INF
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = mask
	query.exclude = exclude
	query.margin = 0.0
	var deepest := 0.0
	for part: Array in parts(def):
		query.shape = part[0]
		query.transform = place * (part[1] as Transform3D)
		var pairs := space.collide_shape(query, 16)
		for i in range(0, pairs.size() - 1, 2):
			deepest = maxf(deepest, (pairs[i] as Vector3).distance_to(pairs[i + 1]))
	return deepest


static func _free(space: PhysicsDirectSpaceState3D, list: Array, place: Transform3D, mask: int, exclude: Array[RID]) -> bool:
	if space == null or not place.origin.is_finite():
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = mask
	query.exclude = exclude
	query.margin = 0.0
	for part: Array in list:
		query.shape = part[0]
		query.transform = place * (part[1] as Transform3D)
		if not space.intersect_shape(query, 1).is_empty():
			return false
	return true


## Olvida lo armado (InvNet, al irse del árbol, como InvReach.clear_cache).
static func clear_cache() -> void:
	_cache.clear()


## De qué salen las formas del modelo de un tipo con ese cuerpo: la huella de
## los triángulos que se ven (InvReach.fingerprint_of) y cómo se arman. Lo
## guarda generate() en InvBodyShape.source; si no coincide, están desactualizadas.
static func source_key(def: InvItemDef, body: InvBodyShape) -> String:
	return "%s | %s" % [InvReach.fingerprint_of(def), body.generation_text() if body != null else "convexa"]


static func _key(def: InvItemDef) -> Array:
	if def == null:
		return [null, null, 0.4, Vector2i.ONE, "", ""]
	var body := def.body_shape
	var text := ""
	if body != null:
		text = "%s %d %s %s" % [body.effective_text(), body.shapes.size(), body.source, body.problems()]
		for shape in body.shapes:
			text += " %d" % (shape.get_instance_id() if shape != null else 0)
		if body.kind == InvPickupHitbox.Kind.CUSTOM and body.custom_shape != null:
			text += " " + InvPickupHitbox._shape_text(body.custom_shape)
	return [def.model, def.mesh, def.world_size, def.size, text, InvReach.hitbox_key(def)]


static func _entry(def: InvItemDef) -> Array:
	var key := _key(def)
	var known: Array = _cache.get(def, [])
	if not known.is_empty() and known[0] == key:
		return known
	var body := InvBodyShape.active_body(def)
	var list: Array = []
	var status := "preparado"
	if body != null and body.kind != InvPickupHitbox.Kind.MODEL:
		var built := body.build_shape()
		if built != null:
			if built.resource_path == "":
				built.margin = SHAPE_MARGIN
			list.append([built, body.local_transform()])
	elif body != null:
		if body.shapes.is_empty():
			status = "sin preparar: las formas del modelo todavía no se generaron"
		elif body.source != source_key(def, body):
			status = "sin preparar: las formas del modelo están desactualizadas (cambió el modelo, su tamaño o cómo se arman)"
		else:
			for shape in body.shapes:
				list.append([shape, Transform3D.IDENTITY])
	elif def != null and def.body_shape != null:
		status = "sin preparar: el cuerpo físico tiene un problema (%s)" % " ".join(def.body_shape.problems())
	else:
		status = "sin preparar: el tipo no tiene cuerpo físico"
	if list.is_empty():
		list = [_runtime_hull(def)]
		if def != null and not Engine.is_editor_hint() and not _warned.has(def):
			_warned[def] = true
			push_warning("[inventario] el cuerpo físico de %s está %s. Usa una sola forma convexa del modelo, que tapa los huecos; preparalo en el panel Objetos (Cuerpo físico → Generar) o con addons/inventario_objetos/preparar_cuerpos.gd." % [
					def.display_name if def.display_name != "" else String(def.id), status])
	var box := AABB()
	var first := true
	for part: Array in list:
		var part_box := _shape_bounds(part[0], part[1])
		box = part_box if first else box.merge(part_box)
		first = false
	var entry := [key, list, box, "%s %s" % [_print(list), "preparado" if status == "preparado" else "sin preparar"], status,
			_center_of_mass(list), _inset(list)]
	_cache[def] = entry
	return entry


## Sin cuerpo preparado: una sola forma convexa con los triángulos del modelo
## (con Mesh.create_convex_shape, que está también en el juego exportado).
static func _runtime_hull(def: InvItemDef) -> Array:
	var faces := InvReach.item_faces(def)
	var hull := _hull(faces)
	if hull == null:
		# Sin triángulos: una caja chica, para que haya cuerpo (no debería pasar:
		# un modelo vacío ya se ve como la caja de su color).
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * 0.1
		box.margin = SHAPE_MARGIN
		return [box, Transform3D(Basis.IDENTITY, Vector3.UP * 0.05)]
	return [hull, Transform3D.IDENTITY]


## Una forma convexa que envuelve los triángulos (de a tres puntos), o null.
static func _hull(faces: PackedVector3Array) -> ConvexPolygonShape3D:
	var mesh := _mesh_of(faces)
	if mesh == null:
		return null
	var hull := mesh.create_convex_shape(true, false)
	if hull != null and hull.points.size() > HULL_POINT_LIMIT:
		var simple := mesh.create_convex_shape(true, true)
		if simple != null and simple.points.size() >= 4:
			hull = simple
	if hull == null or InvPickupHitbox.shape_problem(hull) != "":
		return null
	hull.margin = SHAPE_MARGIN
	return hull


static func _mesh_of(faces: PackedVector3Array) -> ArrayMesh:
	if faces.size() < 3:
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Preparar (en el editor) ------------------------------------------------------

## Arma las formas del modelo de un tipo con lo que dice `body` (su manera, y
## para varias, sus valores) y las deja en `body.shapes` y `body.source`, si
## salen bien. Devuelve {"ok": bool, "problem": texto si no salió, "notes":
## lo que conviene revisar}. La descomposición en varias formas es de V-HACD,
## que viene solo en el editor: en el juego exportado esto no se llama.
##
## Las formas salen de un MeshInstance3D de paso con los triángulos del modelo
## tal como se ve suelto (InvReach.item_faces: escalado y apoyado, sin correr
## scripts del modelo). La herramienta de Godot arma un StaticBody3D con
## CollisionShape3D: se copian sus formas (con su lugar ya puesto en los
## puntos) y se borra todo, sin dejar ningún cuerpo.
static func generate(def: InvItemDef, body: InvBodyShape) -> Dictionary:
	if def == null or body == null:
		return {"ok": false, "problem": "no hay tipo o cuerpo", "notes": PackedStringArray()}
	var faces := InvReach.item_faces(def)
	if faces.size() < 12:
		return {"ok": false, "problem": "el modelo no tiene triángulos suficientes para armar formas", "notes": PackedStringArray()}
	var found: Array[ConvexPolygonShape3D] = []
	if body.generation == InvBodyShape.Generation.CONVEX:
		var hull := _hull(faces)
		if hull != null:
			found.append(hull)
	else:
		var holder := MeshInstance3D.new()
		holder.mesh = _mesh_of(faces)
		var settings := MeshConvexDecompositionSettings.new()
		settings.max_convex_hulls = body.max_parts
		settings.max_concavity = body.concavity
		settings.resolution = body.resolution
		holder.create_multiple_convex_collisions(settings)
		for child in holder.get_children():
			for node in child.get_children():
				var holder_shape := node as CollisionShape3D
				if holder_shape == null or not holder_shape.shape is ConvexPolygonShape3D:
					continue
				var place := (child as Node3D).transform * holder_shape.transform
				var points := PackedVector3Array()
				for point in (holder_shape.shape as ConvexPolygonShape3D).points:
					points.append(place * point)
				var shape := ConvexPolygonShape3D.new()
				shape.points = points
				shape.margin = SHAPE_MARGIN
				found.append(shape)
		holder.free()
	if found.is_empty():
		var why := "no salió ninguna forma"
		if body.generation == InvBodyShape.Generation.PARTS:
			why += " (la descomposición en varias formas solo está en el editor de Godot)"
		return {"ok": false, "problem": why, "notes": PackedStringArray()}
	if found.size() > MAX_PIECES:
		return {"ok": false, "problem": "salieron %d formas, más que las %d que se aceptan" % [found.size(), MAX_PIECES],
				"notes": PackedStringArray()}
	for shape in found:
		var problem := InvPickupHitbox.shape_problem(shape)
		if problem != "":
			return {"ok": false, "problem": "una forma no sirve: " + problem, "notes": PackedStringArray()}
	var notes := PackedStringArray()
	var model := InvReach.item_bounds(def).grow(-0.001)
	var box := AABB()
	for i in found.size():
		var part_box := _shape_bounds(found[i], Transform3D.IDENTITY)
		box = part_box if i == 0 else box.merge(part_box)
	for axis in 3:
		var name: String = ["el ancho (x)", "el alto (y)", "el largo (z)"][axis]
		var low := box.position[axis] - model.position[axis]
		var high := model.end[axis] - box.end[axis]
		if low > COVER_TOLERANCE or high > COVER_TOLERANCE:
			notes.append("Las formas quedan %s cm adentro del modelo en %s: revisalas en la vista previa." % [
					_cm(maxf(low, high)), name])
		elif low < -COVER_TOLERANCE or high < -COVER_TOLERANCE:
			notes.append("Las formas sobresalen %s cm del modelo en %s." % [_cm(-minf(low, high)), name])
	body.shapes = found
	body.source = source_key(def, body)
	body.emit_changed()
	return {"ok": true, "problem": "", "notes": notes}


## Lo que conviene de fábrica para un tipo sin cuerpo (el panel al guardar uno
## y preparar_cuerpos.gd). Lo eligió Claude el 2026-11-15, después de medir el
## catálogo:
##
## - una caja ajustada, si el modelo es una caja (una tabla, una batería) o es
##   plano (más fino que FLAT_LIMIT: una llave, un machete);
## - varias formas (la descomposición, ya generadas), si conservan los bordes
##   del modelo (ninguno queda más de TRIM_TOLERANCE adentro) y la forma
##   convexa ocupa más del doble que ellas: tiene huecos o entrantes grandes
##   (un machete curvo, un marco);
## - si no, una forma convexa (sin generar todavía): exacta en los bordes. En lo
##   chico la descomposición recorta (a la llave y a la granada les sacaba 3 mm
##   por lado), y lo redondo no tiene que perder los extremos.
##
## Usa la descomposición: solo en el editor.
static func suggest(def: InvItemDef) -> InvBodyShape:
	var body := InvBodyShape.new()
	var faces := InvReach.item_faces(def)
	var hull := _hull(faces)
	var model := InvReach.item_bounds(def).grow(-0.001)
	body.kind = InvPickupHitbox.Kind.MODEL
	body.generation = InvBodyShape.Generation.CONVEX
	if hull == null:
		return body
	var hull_box := _shape_bounds(hull, Transform3D.IDENTITY)
	var hull_volume: float = _convex_mass(hull)[0]
	var boxy := hull.points.size() <= 8 and absf(hull_volume - hull_box.get_volume()) <= hull_box.get_volume() * 0.01
	if boxy or model.size[model.get_shortest_axis_index()] < FLAT_LIMIT:
		body.kind = InvPickupHitbox.Kind.BOX
		body.fit(model)
		return body
	var split := InvBodyShape.new()
	split.kind = InvPickupHitbox.Kind.MODEL
	split.generation = InvBodyShape.Generation.PARTS
	if not generate(def, split)["ok"]:
		return body
	var volume := 0.0
	var list: Array = []
	for shape in split.shapes:
		volume += _convex_mass(shape)[0]
		list.append([shape, Transform3D.IDENTITY])
	if worst_outside(def, list) > TRIM_TOLERANCE:
		return body
	return split if hull_volume > volume * 2.0 else body


## Lo más que queda un vértice del modelo afuera de esas formas ([forma, lugar]
## de cajas o convexas), en metros: 0 si todos quedan adentro. Lo usan suggest
## y las pruebas (sin rendijas ni recortes).
static func worst_outside(def: InvItemDef, list: Array) -> float:
	var planes_of: Array = []
	for part: Array in list:
		var shape: Shape3D = part[0]
		var planes: Array[Plane] = []
		if shape is BoxShape3D:
			planes.assign(Geometry3D.build_box_planes((shape as BoxShape3D).size * 0.5))
		elif shape is ConvexPolygonShape3D:
			planes = InvReach._hull_planes(shape as ConvexPolygonShape3D)
		planes_of.append([(part[1] as Transform3D).affine_inverse(), planes])
	var worst := 0.0
	var seen := {}
	for vertex in InvReach.item_faces(def):
		var key := Vector3i((vertex * 10000.0).round())
		if seen.has(key):
			continue
		seen[key] = true
		var best := INF
		for entry: Array in planes_of:
			var local: Vector3 = (entry[0] as Transform3D) * vertex
			var away := 0.0
			for plane: Plane in entry[1]:
				away = maxf(away, plane.distance_to(local))
			best = minf(best, away)
		worst = maxf(worst, best)
	return worst


# --- Masa ---------------------------------------------------------------------------

## El centro de las formas pesadas por su volumen.
static func _center_of_mass(list: Array) -> Vector3:
	var total := 0.0
	var sum := Vector3.ZERO
	for part: Array in list:
		var mass := _convex_mass(part[0])
		var place: Transform3D = part[1]
		total += mass[0]
		sum += place * (mass[1] as Vector3) * (mass[0] as float)
	if total <= 0.0:
		return _shape_bounds(list[0][0], list[0][1]).get_center() if not list.is_empty() else Vector3.ZERO
	return sum / total


## [volumen, centro] de una forma, en su espacio. Una convexa, con las caras de
## su casco (las de su malla de depuración, que arma Godot con sus puntos); si
## no las trae, el centro de sus puntos y el volumen de su caja.
static func _convex_mass(shape: Shape3D) -> Array:
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return [size.x * size.y * size.z, Vector3.ZERO]
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return [4.0 / 3.0 * PI * r * r * r, Vector3.ZERO]
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return [PI * cylinder.radius * cylinder.radius * cylinder.height, Vector3.ZERO]
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var straight := maxf(capsule.height - 2.0 * capsule.radius, 0.0)
		return [PI * capsule.radius * capsule.radius * (straight + 4.0 / 3.0 * capsule.radius), Vector3.ZERO]
	if shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if points.is_empty():
			return [0.0, Vector3.ZERO]
		var middle := Vector3.ZERO
		for point in points:
			middle += point
		middle /= points.size()
		var faces := _hull_faces(shape as ConvexPolygonShape3D)
		var volume := 0.0
		var sum := Vector3.ZERO
		for i in range(0, faces.size() - 2, 3):
			# Un tetraedro por cara, con la punta en el medio de los puntos.
			var tetra := absf((faces[i] - middle).dot((faces[i + 1] - middle).cross(faces[i + 2] - middle))) / 6.0
			volume += tetra
			sum += (middle + faces[i] + faces[i + 1] + faces[i + 2]) * 0.25 * tetra
		if volume > 0.0:
			return [volume, sum / volume]
		var box := _shape_bounds(shape, Transform3D.IDENTITY)
		return [box.get_volume(), middle]
	var other := _shape_bounds(shape, Transform3D.IDENTITY)
	return [other.get_volume(), other.get_center()]


## Las caras del casco de una forma convexa (de a tres puntos): las de su malla
## de depuración. Vacío si no las trae.
static func _hull_faces(shape: ConvexPolygonShape3D) -> PackedVector3Array:
	var mesh := shape.get_debug_mesh()
	return mesh.get_faces() if mesh != null else PackedVector3Array()


# --- Las formas achicadas ------------------------------------------------------------

static func _inset(list: Array) -> Array:
	var out: Array = []
	for part: Array in list:
		out.append([_inset_shape(part[0]), part[1]])
	return out


static func _inset_shape(shape: Shape3D) -> Shape3D:
	var small := 0.001
	if shape is BoxShape3D:
		var box := BoxShape3D.new()
		box.size = ((shape as BoxShape3D).size - Vector3.ONE * INSET * 2.0).max(Vector3.ONE * small)
		box.margin = minf(SHAPE_MARGIN, box.size[box.size.min_axis_index()] * 0.25)
		return box
	if shape is SphereShape3D:
		var sphere := SphereShape3D.new()
		sphere.radius = maxf((shape as SphereShape3D).radius - INSET, small)
		return sphere
	if shape is CylinderShape3D:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = maxf((shape as CylinderShape3D).radius - INSET, small)
		cylinder.height = maxf((shape as CylinderShape3D).height - INSET * 2.0, small)
		cylinder.margin = minf(SHAPE_MARGIN, cylinder.radius * 0.25)
		return cylinder
	if shape is CapsuleShape3D:
		var capsule := CapsuleShape3D.new()
		capsule.radius = maxf((shape as CapsuleShape3D).radius - INSET, small)
		capsule.height = maxf((shape as CapsuleShape3D).height - INSET * 2.0, capsule.radius * 2.0)
		return capsule
	if shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		var middle := Vector3.ZERO
		for point in points:
			middle += point
		middle /= maxf(points.size(), 1)
		var moved := PackedVector3Array()
		for point in points:
			var away := point - middle
			var length := away.length()
			moved.append(middle + away * (maxf(length - INSET, length * 0.5) / length) if length > 0.000001 else point)
		var convex := ConvexPolygonShape3D.new()
		convex.points = moved
		convex.margin = 0.001
		return convex
	return shape


# --- Texto -------------------------------------------------------------------------

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


static func _cm(meters: float) -> String:
	return ("%.1f" % (meters * 100.0)).replace(".", ",")


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
