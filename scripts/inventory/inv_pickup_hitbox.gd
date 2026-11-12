@tool
class_name InvPickupHitbox
extends Resource

## La hitbox de agarre de un tipo de objeto (desde el 2026-11-07, pedido del
## usuario): un volumen invisible fácil de apuntar para un objeto suelto de ese
## tipo. Sirve para que algo chico sea fácil de apuntar, o para tapar los
## huecos de una silueta con una forma sencilla.
##
## Desde el 2026-11-11 a la noche el juego no la usa para recoger: un rayo
## desde los ojos tiene que tocar el modelo (InvReach), y una hitbox agrandada
## que asoma de una pared no deja agarrar lo que está detrás. Se conserva tal
## cual: va en InvItemDef.pickup_hitbox, guardada con el resto del tipo, el
## panel Objetos la edita y la muestra, y entra en la huella. Del 2026-11-07 a
## ese día, la mira tenía que tocar esta forma (InvWorldItem la ponía en su
## forma para apuntar), sin el margen del Tuning; sin hitbox (null) o con
## Kind.MODEL, los triángulos del modelo, con ese margen.
##
## No choca con nada, y no cambia la física, lo equipado ni la miniatura.
##
## Todo se mide en el espacio del objeto suelto, en metros: el origen está en
## el piso, en el centro de la base del modelo ya escalado
## (InvVisuals.world_model), tenga el modelo importado el origen que tenga, y
## también con la caja de color de los que no tienen modelo. `offset` corre la
## forma desde ahí y `rotation_degrees` la gira, en grados, como en el
## Inspector (orden YXZ). El panel Objetos la edita y la muestra en su vista
## previa con estas mismas funciones.

enum Kind { MODEL, BOX, SPHERE, CYLINDER, CUSTOM }

## Lo más chico y lo más grande que puede medir cada lado, radio o alto, en metros.
const MIN_SIZE := 0.001
const MAX_SIZE := 10.0
## Lo más lejos que se puede correr del origen, en metros, en cada eje.
const MAX_OFFSET := 10.0
## Lo más que se puede girar en cada eje, en grados.
const MAX_DEGREES := 360.0
## Las formas propias que sirven: convexas.
const CUSTOM_TYPES := "ConvexPolygonShape3D,BoxShape3D,SphereShape3D,CylinderShape3D,CapsuleShape3D"

## La forma. MODEL: la del modelo, como si no hubiera hitbox.
@export var kind := Kind.BOX

@export_group("Caja")
## Ancho (x), alto (y) y largo (z), en metros.
@export var box_size := Vector3(0.2, 0.1, 0.2)

@export_group("Esfera")
@export var sphere_radius := 0.1

@export_group("Cilindro")
## El cilindro va parado (a lo largo de y); para acostarlo, se gira.
@export var cylinder_radius := 0.05
@export var cylinder_height := 0.2

@export_group("Forma personalizada")
## Un recurso de colisión convexo: ConvexPolygonShape3D, o una caja, esfera,
## cilindro o cápsula de colisión.
@export var custom_shape: Shape3D

@export_group("Lugar")
## Cuánto se corre la forma desde el origen del objeto suelto, en metros.
@export var offset := Vector3.ZERO
## Cuánto se gira, en grados (no cambia nada en una esfera).
@export var rotation_degrees := Vector3.ZERO


## Si tiene una forma propia (no la del modelo).
func is_configured() -> bool:
	return kind != Kind.MODEL


## La hitbox con la que se elige un objeto de ese tipo: la suya, si tiene una
## forma y sirve. Si no (no tiene, es la del modelo o tiene un problema), null:
## se usa la forma del modelo, con el margen del Tuning.
static func active(def: InvItemDef) -> InvPickupHitbox:
	var hitbox := def.pickup_hitbox if def != null else null
	if hitbox == null or not hitbox.is_configured() or not hitbox.problems().is_empty():
		return null
	return hitbox


## Dónde va la forma, en el espacio del objeto suelto.
func local_transform() -> Transform3D:
	return Transform3D(Basis.from_euler(rotation_degrees * (PI / 180.0)), offset)


## La forma de colisión, con sus medidas: una nueva para la caja, la esfera y
## el cilindro; la propia, tal cual (no se cambia). null con MODEL.
func build_shape() -> Shape3D:
	match kind:
		Kind.BOX:
			var box := BoxShape3D.new()
			box.size = box_size
			return box
		Kind.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = sphere_radius
			return sphere
		Kind.CYLINDER:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = cylinder_radius
			cylinder.height = cylinder_height
			return cylinder
		Kind.CUSTOM:
			return custom_shape
	return null


## La caja que encierra la forma, en el espacio del objeto suelto. Vacía con
## MODEL o si la forma no sirve.
func bounds() -> AABB:
	var shape := build_shape() if problems().is_empty() else null
	if shape == null:
		return AABB()
	return local_transform() * shape.get_debug_mesh().get_aabb()


## Lo que impide usarla. Vacío si sirve (y con MODEL, siempre).
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	match kind:
		Kind.MODEL:
			return found
		Kind.BOX:
			if not _length_ok(box_size.x) or not _length_ok(box_size.y) or not _length_ok(box_size.z):
				found.append("la caja mide de 1 mm a 10 m por lado.")
		Kind.SPHERE:
			if not _length_ok(sphere_radius):
				found.append("el radio de la esfera va de 1 mm a 10 m.")
		Kind.CYLINDER:
			if not _length_ok(cylinder_radius) or not _length_ok(cylinder_height):
				found.append("el radio y el alto del cilindro van de 1 mm a 10 m.")
		Kind.CUSTOM:
			var problem := shape_problem(custom_shape)
			if problem != "":
				found.append(problem)
		_:
			found.append("no es una forma conocida (%s)." % kind)
	if not offset.is_finite() or absf(offset.x) > MAX_OFFSET or absf(offset.y) > MAX_OFFSET or absf(offset.z) > MAX_OFFSET:
		found.append("el desplazamiento va de −10 a 10 m en cada eje.")
	if not rotation_degrees.is_finite() or absf(rotation_degrees.x) > MAX_DEGREES or absf(rotation_degrees.y) > MAX_DEGREES \
			or absf(rotation_degrees.z) > MAX_DEGREES:
		found.append("la rotación va de −360° a 360° en cada eje.")
	return found


## Por qué esa forma propia no sirve, o "" si sirve: tiene que ser convexa,
## con números de verdad y con volumen.
static func shape_problem(shape: Resource) -> String:
	if shape == null:
		return "falta el recurso de colisión de la forma personalizada (por ejemplo, una ConvexPolygonShape3D)."
	if shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if points.size() < 4:
			return "la forma convexa está vacía o tiene menos de 4 puntos: así no encierra nada."
		for point in points:
			if not point.is_finite():
				return "un punto de la forma convexa no es un número."
		var box := AABB(points[0], Vector3.ZERO)
		for point in points:
			box = box.expand(point)
		if box.size.x > MAX_SIZE or box.size.y > MAX_SIZE or box.size.z > MAX_SIZE:
			return "la forma convexa mide más de 10 m."
		if not _has_volume(points):
			return "los puntos de la forma convexa están en un plano o en una línea: así no encierra nada."
		return ""
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return "" if _length_ok(size.x) and _length_ok(size.y) and _length_ok(size.z) else "la caja de colisión mide de 1 mm a 10 m por lado."
	if shape is SphereShape3D:
		return "" if _length_ok((shape as SphereShape3D).radius) else "el radio de la esfera de colisión va de 1 mm a 10 m."
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return "" if _length_ok(cylinder.radius) and _length_ok(cylinder.height) else "el radio y el alto del cilindro de colisión van de 1 mm a 10 m."
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return "" if _length_ok(capsule.radius) and _length_ok(capsule.height) else "el radio y el alto de la cápsula de colisión van de 1 mm a 10 m."
	return "%s no sirve: tiene que ser convexa (ConvexPolygonShape3D, o una caja, esfera, cilindro o cápsula de colisión)." % shape.get_class()


static func _length_ok(value: float) -> bool:
	return is_finite(value) and value >= MIN_SIZE and value <= MAX_SIZE


## Si los puntos encierran algo: hay cuatro que no están en un mismo plano.
static func _has_volume(points: PackedVector3Array) -> bool:
	var a := points[0]
	var b := a
	for point in points:
		if point.distance_squared_to(a) > b.distance_squared_to(a):
			b = point
	var line := b - a
	if line.length() < MIN_SIZE:
		return false
	var c := a
	var far := 0.0
	for point in points:
		var away := (point - a).cross(line).length() / line.length()
		if away > far:
			far = away
			c = point
	if far < MIN_SIZE:
		return false
	var normal := line.cross(c - a).normalized()
	for point in points:
		if absf(normal.dot(point - a)) >= MIN_SIZE:
			return true
	return false


## Le da medidas y lugar para encerrar `box` (la caja del modelo, en el
## espacio del objeto suelto): un punto de partida, que después se agranda o se
## corre a mano. La caja, justo; la esfera, con el radio que llega a las
## esquinas; el cilindro, acostado a lo largo del lado más largo, con el radio
## que encierra a los otros dos. Redondeado al milímetro, siempre hacia afuera.
## La forma personalizada y la del modelo no se tocan.
func fit(box: AABB) -> void:
	if kind == Kind.MODEL or kind == Kind.CUSTOM or not box.position.is_finite() or not box.size.is_finite():
		return
	var center := box.get_center().snapped(Vector3.ONE * 0.001)
	offset = center
	# Lo que hay del centro (ya redondeado) a cada lado.
	var half := (box.end - center).max(center - box.position)
	match kind:
		Kind.BOX:
			box_size = _up(half * 2.0)
			rotation_degrees = Vector3.ZERO
		Kind.SPHERE:
			sphere_radius = _up_one(half.length())
			rotation_degrees = Vector3.ZERO
		Kind.CYLINDER:
			match box.size.max_axis_index():
				Vector3.AXIS_X:
					cylinder_height = _up_one(half.x * 2.0)
					cylinder_radius = _up_one(Vector2(half.y, half.z).length())
					rotation_degrees = Vector3(0.0, 0.0, 90.0)
				Vector3.AXIS_Z:
					cylinder_height = _up_one(half.z * 2.0)
					cylinder_radius = _up_one(Vector2(half.x, half.y).length())
					rotation_degrees = Vector3(90.0, 0.0, 0.0)
				_:
					cylinder_height = _up_one(half.y * 2.0)
					cylinder_radius = _up_one(Vector2(half.x, half.z).length())
					rotation_degrees = Vector3.ZERO
	emit_changed()


## Agranda (o achica, con `amount` negativo) la forma simple esa distancia por
## cada lado, en metros, sin bajar de MIN_SIZE. La propia y la del modelo, no.
func grow(amount: float) -> void:
	match kind:
		Kind.BOX:
			box_size = (box_size + Vector3.ONE * amount * 2.0).max(Vector3.ONE * MIN_SIZE)
		Kind.SPHERE:
			sphere_radius = maxf(sphere_radius + amount, MIN_SIZE)
		Kind.CYLINDER:
			cylinder_radius = maxf(cylinder_radius + amount, MIN_SIZE)
			cylinder_height = maxf(cylinder_height + amount * 2.0, MIN_SIZE)
		_:
			return
	emit_changed()


static func _up(size: Vector3) -> Vector3:
	return Vector3(_up_one(size.x), _up_one(size.y), _up_one(size.z))


## Al milímetro de arriba (y nunca menos que MIN_SIZE), sin que un error de
## redondeo de la última cifra sume un milímetro de más.
static func _up_one(value: float) -> float:
	return maxf(ceilf(value * 1000.0 - 0.0001) / 1000.0, MIN_SIZE)


## La caja del modelo como se ve suelto en el mundo (InvVisuals.world_model),
## en el espacio del objeto suelto: escalado y apoyado en el piso, o la caja de
## color si no tiene modelo. Vacía si no tiene mallas. Es la que enmarca el
## indicador.
static func model_bounds(def: InvItemDef) -> AABB:
	var model := InvVisuals.world_model(def)
	var box := InteractFocus.mesh_bounds(model)
	model.free()
	return box


## Lo que va en la huella del catálogo (InvItemDef.fingerprint_text): lo que
## usa de verdad la mira con ese tipo, con números redondeados a la décima de
## milímetro, iguales en todas las máquinas. Sin hitbox, con la del modelo o con
## una que no sirve, "modelo".
static func fingerprint_of(def: InvItemDef) -> String:
	var hitbox := active(def)
	return "agarre " + (hitbox.effective_text() if hitbox != null else "modelo")


## La forma y su lugar, solo con lo que cuenta para esa forma.
func effective_text() -> String:
	var text := ""
	match kind:
		Kind.MODEL:
			return "modelo"
		Kind.BOX:
			text = "caja %s" % _vector_text(box_size)
		Kind.SPHERE:
			text = "esfera %s" % _number_text(sphere_radius)
		Kind.CYLINDER:
			text = "cilindro %s %s" % [_number_text(cylinder_radius), _number_text(cylinder_height)]
		Kind.CUSTOM:
			text = "propia " + _shape_text(custom_shape)
	text += " en %s" % _vector_text(offset)
	if kind != Kind.SPHERE:
		text += " giro %s" % _vector_text(rotation_degrees)
	return text


static func _shape_text(shape: Shape3D) -> String:
	if shape == null:
		return "ninguna"
	var text := "%s margen %s" % [shape.get_class(), _number_text(shape.margin)]
	if shape is ConvexPolygonShape3D:
		var points := PackedStringArray()
		for point in (shape as ConvexPolygonShape3D).points:
			points.append(_vector_text(point))
		text += " " + " ".join(points)
	elif shape is BoxShape3D:
		text += " " + _vector_text((shape as BoxShape3D).size)
	elif shape is SphereShape3D:
		text += " " + _number_text((shape as SphereShape3D).radius)
	elif shape is CylinderShape3D:
		text += " %s %s" % [_number_text((shape as CylinderShape3D).radius), _number_text((shape as CylinderShape3D).height)]
	elif shape is CapsuleShape3D:
		text += " %s %s" % [_number_text((shape as CapsuleShape3D).radius), _number_text((shape as CapsuleShape3D).height)]
	return text


## Un número con cuatro decimales; −0 da 0.
static func _number_text(value: float) -> String:
	return "%.4f" % (snappedf(value, 0.0001) + 0.0)


static func _vector_text(value: Vector3) -> String:
	return "%s,%s,%s" % [_number_text(value.x), _number_text(value.y), _number_text(value.z)]
