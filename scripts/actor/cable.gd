@tool
class_name Cable
extends Node3D

## Cable del que se cuelga (modo Cable, la tirolesa de la arquitectura): una
## línea invisible que dice dónde se agarran las manos, sin colisión. Lo que se
## ve va aparte y se elige en `look`: un tubo, un modelo repetido a lo largo o
## una textura alargada. Está quieto: no se mueve ni se hunde con el peso.
##
## La forma: del origen del nodo a `end`, en coordenadas del nodo, con una
## comba de `sag` metros hacia abajo en el medio (una parábola; con 0 es recto).
## Sobre el cable se ubica por la distancia desde el origen, medida a lo largo
## del cable (anchor_t del actor).
##
## Por ahora los cables están fijos: la forma se calcula una vez al entrar al
## juego. Para que dé lo mismo en todas las máquinas, sale solo de los valores
## exportados y del lugar del nodo.

enum Look { TUBE, MODEL, TEXTURE }

## Largo de cada tramo recto con que se arma la curva, en metros.
const SEGMENT := 0.25
## Lados del tubo.
const TUBE_SIDES := 8

const STRIP_SHADER := """shader_type spatial;
render_mode skip_vertex_transform, cull_disabled;
uniform sampler2D strip : source_color, filter_linear_mipmap, repeat_enable;
uniform float width = 0.06;
void vertex() {
	vec3 axis = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 center = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 side = cross(axis, normalize(center));
	float size = length(side);
	side = size > 0.0001 ? side / size : vec3(0.0, 1.0, 0.0);
	VERTEX = center + side * (UV.y - 0.5) * width;
	NORMAL = normalize(cross(side, axis));
	if (dot(NORMAL, center) > 0.0) {
		NORMAL = -NORMAL;
	}
}
void fragment() {
	vec4 color = texture(strip, UV);
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""

static var _cables := {}  # id -> Cable

## Id del cable. Tiene que ser único y el mismo en todas las máquinas.
@export var cable_id := 1
## Dónde termina, en coordenadas del nodo. Empieza en el origen del nodo.
@export var end := Vector3(8, 0, 0):
	set(value):
		end = value
		_rebuild()
## Cuánto cuelga en el medio, en metros. 0 = recto.
@export_range(0.0, 10.0, 0.01, "or_greater") var sag := 0.0:
	set(value):
		sag = value
		_rebuild()

@export_group("Dibujo")
## Tubo: un cilindro a lo largo del cable. Modelo: `model` repetido a lo largo
## (sin modelo, eslabones de cadena). Textura: una tira con `texture` que
## siempre mira a la cámara, como una textura alargada.
@export var look: Look = Look.TUBE:
	set(value):
		look = value
		_rebuild()
## Radio del tubo, o medio ancho de la tira de la textura, en metros.
@export_range(0.005, 0.3, 0.005) var thickness := 0.03:
	set(value):
		thickness = value
		_rebuild()
## Color del tubo y de los eslabones, si no hay material.
@export var color := Color(0.18, 0.18, 0.2):
	set(value):
		color = value
		_rebuild()
## Material del tubo o del modelo. Sin material, uno liso de `color`.
@export var material: Material:
	set(value):
		material = value
		_rebuild()
## Modelo que se repite a lo largo del cable, con su eje largo en X. Uno al lado
## del otro, tantas veces como entren.
@export var model: Mesh:
	set(value):
		model = value
		_rebuild()
## Textura de la tira. Sin textura, una de soga.
@export var texture: Texture2D:
	set(value):
		texture = value
		_rebuild()
## Cuántos metros de cable ocupa una repetición de la textura.
@export_range(0.05, 10.0, 0.05) var texture_length := 0.4:
	set(value):
		texture_length = value
		_rebuild()

## La curva en el mundo, en tramos de SEGMENT: los puntos y la distancia sobre
## el cable hasta cada uno.
var _points := PackedVector3Array()
var _lengths := PackedFloat64Array()
var _visual: Node3D


static func find(id: int) -> Cable:
	return _cables.get(id) if id != 0 else null


## Los cables, de id más chico a más grande, así todas las máquinas los miran
## en el mismo orden.
static func all() -> Array:
	var ids := _cables.keys()
	ids.sort()
	return ids.map(func(id: int) -> Cable: return _cables[id])


func _enter_tree() -> void:
	# En el editor no: con el nivel abierto en dos pestañas, cada cable está dos veces.
	var other = _cables.get(cable_id)
	if not Engine.is_editor_hint() and other != null and other != self and is_instance_valid(other):
		push_warning("Dos cables con el id %d: %s y %s. Cada cable necesita un cable_id propio." % [
				cable_id, other.get_path(), get_path()])
	_cables[cable_id] = self


func _exit_tree() -> void:
	if _cables.get(cable_id) == self:
		_cables.erase(cable_id)


func _ready() -> void:
	_rebuild()


## Largo del cable, medido a lo largo de la curva.
func length() -> float:
	_ensure_points()
	return _lengths[_lengths.size() - 1]


## El punto del cable a la distancia t desde el origen, en el mundo.
func point_at(t: float) -> Vector3:
	_ensure_points()
	var i := _segment_at(t)
	var span := _lengths[i + 1] - _lengths[i]
	var weight := clampf((t - _lengths[i]) / span, 0.0, 1.0) if span > 0.0 else 0.0
	return _points[i].lerp(_points[i + 1], weight)


## Hacia dónde sigue el cable en la distancia t: del origen hacia `end`.
func tangent_at(t: float) -> Vector3:
	_ensure_points()
	var i := _segment_at(t)
	return (_points[i + 1] - _points[i]).normalized()


## La distancia sobre el cable del punto más cercano a `point`.
func closest(point: Vector3) -> float:
	_ensure_points()
	var best := 0.0
	var best_distance := INF
	for i in _points.size() - 1:
		var a := _points[i]
		var ab := _points[i + 1] - a
		var weight := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0) if ab.length_squared() > 0.0 else 0.0
		var distance := point.distance_squared_to(a + ab * weight)
		if distance < best_distance:
			best_distance = distance
			best = _lengths[i] + (_lengths[i + 1] - _lengths[i]) * weight
	return best


## Los puntos de la curva en coordenadas del nodo, de punta a punta.
func _local_points() -> PackedVector3Array:
	var flat := Vector2(end.x, end.z).length()
	var count := maxi(ceili(maxf(flat, absf(end.y)) / SEGMENT), 1)
	var points := PackedVector3Array()
	for i in count + 1:
		var u := float(i) / count
		points.append(end * u + Vector3.DOWN * 4.0 * sag * u * (1.0 - u))
	return points


func _ensure_points() -> void:
	if not _points.is_empty():
		return
	_points = PackedVector3Array()
	_lengths = PackedFloat64Array([0.0])
	for point in _local_points():
		_points.append(global_transform * point)
	for i in range(1, _points.size()):
		_lengths.append(_lengths[i - 1] + _points[i - 1].distance_to(_points[i]))


func _segment_at(t: float) -> int:
	var low := 0
	var high := _lengths.size() - 2
	while low < high:
		var middle := (low + high + 1) >> 1
		if _lengths[middle] <= t:
			low = middle
		else:
			high = middle - 1
	return low


## Arma de nuevo la curva y el dibujo. Es solo dibujo, sin colisión; con @tool
## también se ve en el editor, y no se guarda en la escena.
func _rebuild() -> void:
	_points = PackedVector3Array()
	if not is_inside_tree():
		return
	if _visual != null:
		_visual.queue_free()
	_visual = Node3D.new()
	add_child(_visual)
	var points := _local_points()
	match look:
		Look.TUBE:
			_visual.add_child(_tube(points))
		Look.MODEL:
			_visual.add_child(_models(points))
		Look.TEXTURE:
			_visual.add_child(_strip(points))


func _surface_material() -> Material:
	if material != null:
		return material
	var plain := StandardMaterial3D.new()
	plain.albedo_color = color
	plain.roughness = 0.6
	return plain


func _tube(points: PackedVector3Array) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for i in points.size():
		if i > 0:
			along += points[i - 1].distance_to(points[i])
		var forward := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := forward.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = forward.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(forward)
		for k in TUBE_SIDES + 1:
			var angle := TAU * k / TUBE_SIDES
			var out := side * cos(angle) + up * sin(angle)
			tool.set_normal(out)
			tool.set_uv(Vector2(along / texture_length, float(k) / TUBE_SIDES))
			tool.add_vertex(points[i] + out * thickness)
	var ring := TUBE_SIDES + 1
	for i in points.size() - 1:
		for k in TUBE_SIDES:
			var a := i * ring + k
			var b := a + ring
			for index in [a, b, a + 1, a + 1, b, b + 1]:
				tool.add_index(index)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = tool.commit()
	mesh_instance.material_override = _surface_material()
	return mesh_instance


## El modelo repetido a lo largo, con su X sobre el cable. Sin modelo, eslabones
## de cadena: anillos alternados a 90°.
func _models(points: PackedVector3Array) -> MultiMeshInstance3D:
	var mesh := model
	var spacing := 0.0
	var chain := mesh == null
	if chain:
		var link := TorusMesh.new()
		link.inner_radius = thickness * 1.2
		link.outer_radius = thickness * 2.2
		mesh = link
		spacing = thickness * 3.2
	else:
		spacing = maxf(mesh.get_aabb().size.x, 0.02)
	var lengths := PackedFloat64Array([0.0])
	for i in range(1, points.size()):
		lengths.append(lengths[i - 1] + points[i - 1].distance_to(points[i]))
	var total := lengths[lengths.size() - 1]
	var count := maxi(floori(total / spacing), 1)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var segment := 0
	for n in count:
		var t := (n + 0.5) * total / count
		while segment < points.size() - 2 and lengths[segment + 1] < t:
			segment += 1
		var span := lengths[segment + 1] - lengths[segment]
		var at := points[segment].lerp(points[segment + 1], (t - lengths[segment]) / span if span > 0.0 else 0.0)
		var forward := (points[segment + 1] - points[segment]).normalized()
		var side := forward.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = forward.cross(Vector3.RIGHT)
		side = side.normalized()
		var turned := Basis(forward, side.cross(forward), side)
		if chain and n % 2 == 1:
			turned = turned.rotated(forward, PI * 0.5)
		multimesh.set_instance_transform(n, Transform3D(turned, at))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _surface_material() if material != null or chain else null
	return instance


## La tira de la textura: dos vértices por punto, sobre el cable, con la
## dirección del cable en la normal; el shader los abre hacia los costados,
## de frente a la cámara.
func _strip(points: PackedVector3Array) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for i in points.size():
		if i > 0:
			along += points[i - 1].distance_to(points[i])
		var forward := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		for side in 2:
			tool.set_normal(forward)
			tool.set_uv(Vector2(along / texture_length, side))
			tool.add_vertex(points[i])
	for i in points.size() - 1:
		var a := i * 2
		for index in [a, a + 2, a + 1, a + 1, a + 2, a + 3]:
			tool.add_index(index)
	var shader := Shader.new()
	shader.code = STRIP_SHADER
	var strip_material := ShaderMaterial.new()
	strip_material.shader = shader
	strip_material.set_shader_parameter("strip", texture if texture != null else _rope_texture())
	strip_material.set_shader_parameter("width", thickness * 2.0)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = tool.commit()
	mesh_instance.material_override = strip_material
	# Los vértices están todos sobre el cable: sin margen, Godot creería que la
	# tira no se ve y no la dibujaría.
	mesh_instance.extra_cull_margin = thickness * 2.0 + 0.1
	return mesh_instance


## Una textura de soga: franjas en diagonal de dos tonos, con los bordes
## transparentes. Para cuando no se eligió ninguna.
func _rope_texture() -> ImageTexture:
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	var light := Color(0.72, 0.6, 0.38)
	var dark := Color(0.45, 0.35, 0.2)
	for x in 32:
		for y in 16:
			var across := absf(y - 7.5) / 8.0
			var band := posmod(x + y, 8) < 4
			var shade := (light if band else dark).darkened(across * across * 0.6)
			shade.a = 1.0 if across < 0.95 else 0.0
			image.set_pixel(x, y, shade)
	return ImageTexture.create_from_image(image)
