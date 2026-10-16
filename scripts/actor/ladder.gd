@tool
class_name Ladder
extends Node3D

## Escalera: un objeto autorado con su eje y su alto, como pide la
## arquitectura. No se detectan peldaños: quien trepa se ubica sobre el eje,
## y su pose sale de la escalera y de la altura.
##
## El eje sale del nodo hacia arriba (+Y local). Se trepa desde el lado +Z
## local: esa cara mira hacia quien trepa. Los pies de quien está a la altura
## t van en pose_at(t), a `standoff` delante del eje.
##
## Por ahora las escaleras están fijas: no se mueven ni giran en el juego. El
## número de cada una sale solo (ladder_id).
##
## El dibujo (grupo Dibujo del Inspector) se arma con piezas: dos largueros
## estirados hasta el alto y un peldaño cada `rung_spacing`, estirado hasta el
## ancho. Las piezas son los modelos de `rail_model` y `rung_model` (un .glb o
## una escena) o, sin modelo, unas provisorias. Para el juego la escalera es
## solo el eje, el alto y el alcance: el dibujo no tiene colisión.

## Los largueros sobresalen esto por encima del alto, para agarrarse arriba.
const RAIL_EXTRA := 0.4
## Las piezas van esto adelante del eje, hacia quien trepa.
const PIECES_Z := 0.05

## Las escaleras que están en el juego, y si ya están en orden.
static var _ladders := []
static var _in_order := true

## Número de la escalera, desde 1: su lugar entre todas, ordenadas por su ruta
## en la escena. Sale solo, así nunca se repite, y como todas las máquinas
## tienen el mismo nivel, a cada escalera le toca el mismo número en todas. Es
## lo que guarda el estado del actor (anchor_id, y regrab_id para no volver a
## agarrar la misma). Si algún día se agregan o se sacan escaleras en pleno
## juego, los números de las que vienen después cambian: ahí habría que
## numerarlas de otra forma.
var ladder_id: int:
	get:
		return _ordered().find(self) + 1

## Alto, en metros: arriba de todo, los pies quedan a esta altura del nodo.
@export var height := 2.5:
	set(value):
		height = value
		_rebuild()
@export var width := 0.8:
	set(value):
		width = value
		_rebuild()
## Distancia del eje al centro de la cápsula de quien trepa.
@export var standoff := 0.45
## Volumen de entrada, una caja pegada a la escalera: hasta esta distancia
## delante del eje se puede agarrar. Más chico, hay que estar más cerca y el
## cuerpo se acomoda menos al agarrarse (queda a `standoff`).
@export var reach := 0.6
## Cuánto pasa el volumen de entrada de cada costado de la escalera.
@export var side_reach := 0.3

@export_group("Dibujo")
## Si se dibujan las piezas. Apagado, la escalera no dibuja nada: para poner un
## modelo entero, hecho a mano, como hijo de la escalera.
@export var show_pieces := true:
	set(value):
		show_pieces = value
		_rebuild()
## El larguero: un .glb o una escena, de cualquier alto y parado o acostado: su
## lado más largo se pone a lo alto. Se estira hasta el alto de la escalera
## (más RAIL_EXTRA) y va uno a cada lado, a `width`; el de la derecha, espejado.
## Sin modelo, una barra provisoria.
@export var rail_model: PackedScene:
	set(value):
		rail_model = value
		_rebuild()
## El peldaño: un .glb o una escena, de cualquier ancho y acostado como sea: su
## lado más largo se pone a lo ancho. Se estira hasta `width`, y a lo alto no.
## Sin modelo, una barra provisoria.
@export var rung_model: PackedScene:
	set(value):
		rung_model = value
		_rebuild()
## Cada cuánto va un peldaño, en metros.
@export_range(0.1, 2.0, 0.01) var rung_spacing := 0.3:
	set(value):
		rung_spacing = value
		_rebuild()
## Que la textura de los modelos no se estire con la pieza: se proyecta según
## el lugar en el mundo (Triplanar, en coordenadas del mundo) y se repite. Usa
## una copia de cada material; el original no se toca.
@export var tile_textures := true:
	set(value):
		tile_textures = value
		_rebuild()

var _visual: Node3D
## La ruta en la escena, anotada al entrar: con ella se ordenan las escaleras.
var _path := ""


static func find(id: int) -> Ladder:
	var ladders := _ordered()
	return ladders[id - 1] if id >= 1 and id <= ladders.size() else null


## Las escaleras, de número más chico a más grande, así todas las máquinas las
## miran en el mismo orden.
static func all() -> Array:
	return _ordered()


static func _ordered() -> Array:
	if not _in_order:
		_ladders.sort_custom(func(a: Ladder, b: Ladder) -> bool: return a._path < b._path)
		_in_order = true
	return _ladders


## Si unos pies en `feet` están dentro del volumen de entrada de alguna
## escalera. Ahí no se cuelga de un borde: delante de esa pared está la
## escalera, y se trepa por ella.
static func any_at(feet: Vector3) -> bool:
	for ladder: Ladder in _ladders:
		if ladder.height_for(feet) >= 0.0:
			return true
	return false


func _enter_tree() -> void:
	_path = String(get_path())
	_ladders.append(self)
	_in_order = false


func _exit_tree() -> void:
	_ladders.erase(self)


func _ready() -> void:
	_rebuild()


func up() -> Vector3:
	return global_basis.y.normalized()


## Hacia dónde mira la cara: desde la escalera hacia quien trepa.
func outward() -> Vector3:
	return global_basis.z.normalized()


## Dónde van los pies de quien está a la altura t.
func pose_at(t: float) -> Vector3:
	return global_position + up() * t + outward() * standoff


## La altura sobre la escalera para unos pies en `feet`, o -1 si están fuera
## del volumen de entrada.
func height_for(feet: Vector3) -> float:
	var local := global_transform.affine_inverse() * feet
	if absf(local.x) > width * 0.5 + side_reach or local.z < 0.0 or local.z > reach:
		return -1.0
	if local.y < -0.2 or local.y > height + 0.2:
		return -1.0
	return clampf(local.y, 0.0, height)


## Arma el dibujo de nuevo cada vez que cambia el alto, el ancho o un valor del
## grupo Dibujo: dos largueros y un peldaño cada `rung_spacing`. Es solo dibujo,
## sin colisión. Con @tool también se dibuja en el editor; no se guarda en la
## escena.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _visual != null:
		_visual.queue_free()
		_visual = null
	if not show_pieces:
		return
	_visual = Node3D.new()
	add_child(_visual)
	var copies := {}
	var rail_height := height + RAIL_EXTRA
	for side in [-1.0, 1.0]:
		var rail := _piece(rail_model, Vector3(0.06, 1.0, 0.06), Vector3.AXIS_Y, copies)
		var box := _bounds(rail)
		var stretch := Vector3(-side, rail_height / maxf(box.size.y, 0.001), 1.0)
		_place(rail, box, stretch, Vector3(side * width * 0.5, rail_height * 0.5, PIECES_Z))
	var rung_y := rung_spacing
	while rung_y < rail_height - 0.05:
		var rung := _piece(rung_model, Vector3(1.0, 0.04, 0.04), Vector3.AXIS_X, copies)
		var box := _bounds(rung)
		_place(rung, box, Vector3(width / maxf(box.size.x, 0.001), 1.0, 1.0), Vector3(0.0, rung_y, PIECES_Z))
		rung_y += rung_spacing


## Una pieza nueva: una instancia de `model`, sin colisiones, con la textura
## repetida si `tile_textures`, y girada para que su lado más largo quede sobre
## `long_axis`, así da igual cómo esté acostada en el modelo. Sin modelo, o si
## no se puede instanciar, una caja provisoria de `size`.
func _piece(model: PackedScene, size: Vector3, long_axis: int, copies: Dictionary) -> Node3D:
	var instance: Node = model.instantiate() if model != null else null
	if model != null and instance == null:
		push_warning("%s: no se pudo instanciar %s; va la pieza provisoria." % [name, model.resource_path])
	var root := Node3D.new()
	_visual.add_child(root)
	if instance == null:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = _plain_material(copies)
		box.mesh = mesh
		root.add_child(box)
		return root
	_strip_collisions(instance)
	if tile_textures:
		_tile(instance, copies)
	var holder := Node3D.new()
	holder.add_child(instance)
	root.add_child(holder)
	var longest := _longest_axis(_bounds(root).size)
	if longest != long_axis:
		var along := Vector3.ZERO
		along[longest] = 1.0
		var wanted := Vector3.ZERO
		wanted[long_axis] = 1.0
		holder.basis = Basis(Quaternion(along, wanted))
	return root


static func _longest_axis(size: Vector3) -> int:
	if size.x >= size.y and size.x >= size.z:
		return Vector3.AXIS_X
	return Vector3.AXIS_Y if size.y >= size.z else Vector3.AXIS_Z


## Escala la pieza por `stretch` y la mueve para que el centro de su caja quede
## en `center`.
func _place(piece: Node3D, box: AABB, stretch: Vector3, center: Vector3) -> void:
	piece.scale = stretch
	piece.position = center - box.get_center() * stretch


## La caja que ocupan las mallas de una pieza, en sus coordenadas.
func _bounds(piece: Node3D) -> AABB:
	var found := [null]
	_merge_bounds(piece, Transform3D.IDENTITY, found)
	return found[0] if found[0] != null else AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


func _merge_bounds(node: Node, to_piece: Transform3D, found: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var box: AABB = to_piece * (node as MeshInstance3D).get_aabb()
		found[0] = box if found[0] == null else (found[0] as AABB).merge(box)
	for child in node.get_children():
		if child is Node3D:
			_merge_bounds(child, to_piece * (child as Node3D).transform, found)


## Saca los cuerpos con colisión que traiga el modelo: el dibujo no tiene que
## chocar con quien trepa.
func _strip_collisions(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D:
			node.remove_child(child)
			child.free()
		else:
			_strip_collisions(child)


## Cambia los materiales de las mallas por copias con la textura proyectada en
## coordenadas del mundo (Triplanar): así no se estira con la pieza. Una copia
## por material, compartida por todas las piezas de la escalera.
func _tile(node: Node, copies: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.material_override is BaseMaterial3D:
			mesh_instance.material_override = _tiled(mesh_instance.material_override, copies)
		else:
			for surface in mesh_instance.get_surface_override_material_count():
				var material := mesh_instance.get_active_material(surface)
				if material is BaseMaterial3D:
					mesh_instance.set_surface_override_material(surface, _tiled(material, copies))
	for child in node.get_children():
		_tile(child, copies)


func _tiled(material: BaseMaterial3D, copies: Dictionary) -> BaseMaterial3D:
	if not copies.has(material):
		var copy := material.duplicate() as BaseMaterial3D
		copy.uv1_triplanar = true
		copy.uv1_world_triplanar = true
		copies[material] = copy
	return copies[material]


## El color de las piezas provisorias, uno por escalera.
func _plain_material(copies: Dictionary) -> StandardMaterial3D:
	if not copies.has("plain"):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.75, 0.6, 0.25)
		copies["plain"] = material
	return copies["plain"]
