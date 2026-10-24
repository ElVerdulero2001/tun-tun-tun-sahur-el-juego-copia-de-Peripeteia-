@tool
class_name Ladder
extends Node3D

## Escalera: un objeto autorado con su eje y su alto, como pide la
## arquitectura. No se detectan peldaños: quien trepa se ubica sobre el eje,
## y su pose sale de la escalera y de la altura.
##
## El eje sale del nodo hacia arriba (+Y local). Se trepa desde el lado +Z
## local (el frente: esa cara mira hacia quien trepa) y, si detrás hay lugar,
## también desde el otro (ver back_open). Los pies de quien está a la altura t
## van en pose_at(t, side), a `standoff` del eje, del lado que trepa: side es
## 1 adelante y -1 atrás.
##
## Por ahora las escaleras están fijas: no se mueven ni giran en el juego. El
## número de cada una sale solo (ladder_id).
##
## La escala del nodo (o de uno de arriba) tiene que ser 1: el dibujo y el
## volumen de entrada crecerían con ella, pero la pose de quien trepa no. El
## tamaño se cambia con `height` y `width`. Escalada, avisa en el editor y al
## correr.
##
## El dibujo (grupo Dibujo del Inspector) se arma con piezas: dos largueros
## estirados hasta el alto y un peldaño cada `rung_spacing`, estirado hasta el
## ancho. Las piezas son los modelos de `rail_model` y `rung_model` (un .glb o
## una escena) o, sin modelo, unas provisorias. Para trepar, la escalera es
## solo el eje, el alto y el alcance. Las piezas además chocan (grupo Colisión):
## cada una lleva una caja del tamaño de su dibujo, armada sola, en la capa de
## las escaleras (COLLISION_LAYER), que los cuerpos tocan y las sondas de los
## bordes no (un peldaño no es un borde para colgarse).

## Los largueros sobresalen esto por encima del alto, para agarrarse arriba.
## Los peldaños, no: el de más arriba es el último que no pasa del alto.
const RAIL_EXTRA := 0.4
## Las piezas van esto adelante del eje, hacia quien trepa.
const PIECES_Z := 0.05
## La capa de física de las piezas que chocan (la 3). Los actores la tocan al
## moverse; las sondas de bordes y de escalones la dejan afuera (ver EdgeProbe.mask).
const COLLISION_LAYER := 1 << 2
## Para saber si se puede trepar por detrás: el cuerpo de quien trepa, una
## cápsula como la del actor parado.
const CLIMBER_RADIUS := 0.35
const CLIMBER_HEIGHT := 1.8
const SCALED_WARNING := "La escalera está escalada (Scale distinto de 1, en ella o en un nodo de arriba): se dibuja de otro tamaño que el que se trepa. Dejá Scale en 1 y cambiá el tamaño con Height y Width."

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

@export_group("Colisión")
## Que los largueros y los peldaños choquen: quien camina o salta contra la
## escalera se la lleva por delante en vez de atravesarla (y más adelante, los
## disparos). Cada pieza lleva una caja del tamaño de su dibujo, armada sola,
## hasta el alto: lo que sobresale arriba, para agarrarse al salir, no choca,
## así se puede pasar por encima. Sin piezas (Show Pieces apagado), no hay
## colisión: el modelo entero que pongas como hijo trae la suya, y conviene que
## esté en la capa 3, la de las escaleras.
@export var collides := true:
	set(value):
		collides = value
		_rebuild()
## Grosor de la caja de colisión del peldaño de arriba, de adelante hacia
## atrás, en metros, centrada en el eje. Es donde se queda parado el que sale
## por arriba de una escalera suelta: con la caja finita de los demás peldaños
## (4 cm en los provisorios), la punta redonda del cuerpo se cae enseguida.
## El dibujo no cambia. Con el Standoff de siempre, hasta 0,16 m no toca al que
## trepa; desde unos 0,2 m lo roza, y más grueso el que sube choca con él en el
## último tramo y no termina de subir (con 0,3 m, en la de 4 m se trababa a
## 2,25 m). 0: como los demás peldaños (pedido del usuario, 2026-10-23).
@export_range(0.0, 0.6, 0.01) var top_rung_depth := 0.16:
	set(value):
		top_rung_depth = value
		_rebuild()

var _visual: Node3D
## Si se puede trepar por detrás: se calcula la primera vez que hace falta (ver
## back_open) y queda anotado.
var _back_known := false
var _back_is_open := false
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
## escalera, de cualquiera de sus lados. Ahí no se cuelga de un borde: delante
## de esa pared está la escalera, y se trepa por ella.
static func any_at(feet: Vector3) -> bool:
	for ladder: Ladder in _ladders:
		if ladder.side_for(feet) != 0.0:
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
	if Engine.is_editor_hint():
		# Para que el aviso aparezca y se vaya al escalar en el editor.
		set_notify_transform(true)
	elif is_scaled():
		push_warning("%s: %s" % [get_path(), SCALED_WARNING])


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	return [SCALED_WARNING] if is_inside_tree() and is_scaled() else []


## Si el nodo, o uno de arriba, la escala (o la espeja).
func is_scaled() -> bool:
	return not global_basis.get_scale().is_equal_approx(Vector3.ONE)


func up() -> Vector3:
	return global_basis.y.normalized()


## Hacia dónde mira el frente: desde la escalera hacia quien trepa por
## adelante.
func outward() -> Vector3:
	return global_basis.z.normalized()


## Desde la escalera hacia quien trepa del lado `side` (1 adelante, -1 atrás).
func face(side: float) -> Vector3:
	return outward() * side


## De qué lado está quien mira hacia `yaw` estando en la escalera: 1 si mira
## hacia el frente (está adelante), -1 si mira desde atrás.
func side_of_yaw(yaw: float) -> float:
	return 1.0 if Vector3.FORWARD.rotated(Vector3.UP, yaw).dot(outward()) <= 0.0 else -1.0


## Dónde van los pies de quien está a la altura t, del lado `side`.
func pose_at(t: float, side := 1.0) -> Vector3:
	return global_position + up() * t + face(side) * standoff


## La altura sobre la escalera para unos pies en `feet` del lado `side`, o -1
## si están fuera de su volumen de entrada. Atrás, solo si back_open.
func height_for(feet: Vector3, side := 1.0) -> float:
	var local := global_transform.affine_inverse() * feet
	var ahead := local.z * side
	if absf(local.x) > width * 0.5 + side_reach or ahead < 0.0 or ahead > reach:
		return -1.0
	if local.y < -0.2 or local.y > height + 0.2:
		return -1.0
	if side < 0.0 and not back_open():
		return -1.0
	return clampf(local.y, 0.0, height)


## A qué distancia del eje están unos pies, de costado (a lo ancho), con signo.
func across(feet: Vector3) -> float:
	return (global_transform.affine_inverse() * feet).x


## De qué lado de la escalera están unos pies dentro de su volumen de entrada:
## 1 adelante, -1 atrás, 0 en ninguno.
func side_for(feet: Vector3) -> float:
	if height_for(feet, 1.0) >= 0.0:
		return 1.0
	if height_for(feet, -1.0) >= 0.0:
		return -1.0
	return 0.0


## Si se puede trepar por detrás: si el cuerpo de quien trepa cabe detrás de
## la escalera, al pie, sin tocar nada fijo. Una escalera contra una pared se
## trepa solo por adelante, como siempre. Si atrás hay algo más arriba (un
## balcón, un techo), se trepa por atrás hasta que la cabeza lo toca, y de ahí
## se baja o se salta (pedido del usuario, 2026-10-20). Se calcula la primera
## vez que hace falta, que es en un tick de la simulación, y queda anotado: el
## nivel es el mismo en todas las máquinas, así que da lo mismo en todas.
func back_open() -> bool:
	if _back_known or not is_inside_tree():
		return _back_is_open
	_back_known = true
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = CLIMBER_RADIUS
	capsule.height = CLIMBER_HEIGHT
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.collision_mask = 1
	params.transform = Transform3D(Basis(), pose_at(0.0, -1.0) + up() * (CLIMBER_HEIGHT * 0.5 + 0.02))
	_back_is_open = space.intersect_shape(params, 1).is_empty()
	return _back_is_open


## Arma el dibujo de nuevo cada vez que cambia el alto, el ancho o un valor de
## los grupos Dibujo o Colisión: dos largueros y un peldaño cada
## `rung_spacing`, y su colisión. Con @tool también se arma en el editor; no se
## guarda en la escena.
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
	# Lo que choca, en coordenadas de la escalera: cada larguero hasta el alto y
	# cada peldaño. Los peldaños llegan solo hasta el alto: hasta el 2026-10-23
	# se dibujaban también entre el alto y la punta de los largueros, sin chocar,
	# y parado arriba de una escalera suelta el cuerpo atravesaba el de más
	# arriba (capturas del usuario).
	var solids: Array[AABB] = []
	for side in [-1.0, 1.0]:
		var rail := _piece(rail_model, Vector3(0.06, 1.0, 0.06), Vector3.AXIS_Y, copies)
		var box := _bounds(rail)
		var stretch := Vector3(-side, rail_height / maxf(box.size.y, 0.001), 1.0)
		_place(rail, box, stretch, Vector3(side * width * 0.5, rail_height * 0.5, PIECES_Z))
		var thick := (box.size * stretch).abs()
		solids.append(_clipped(AABB(Vector3(side * width * 0.5 - thick.x * 0.5, 0.0, PIECES_Z - thick.z * 0.5), Vector3(thick.x, height, thick.z))))
	var rung_y := rung_spacing
	var top_rung := -1
	while rung_y <= height:
		var rung := _piece(rung_model, Vector3(1.0, 0.04, 0.04), Vector3.AXIS_X, copies)
		var box := _bounds(rung)
		var stretch := Vector3(width / maxf(box.size.x, 0.001), 1.0, 1.0)
		_place(rung, box, stretch, Vector3(0.0, rung_y, PIECES_Z))
		var size := (box.size * stretch).abs()
		top_rung = solids.size()
		solids.append(_below_top(_clipped(AABB(Vector3(0.0, rung_y, PIECES_Z) - size * 0.5, size))))
		rung_y += rung_spacing
	# El peldaño de arriba, con su grosor propio, centrado en el eje y sin
	# recortar (ver top_rung_depth).
	if top_rung >= 0 and top_rung_depth > 0.0:
		var top: AABB = solids[top_rung]
		solids[top_rung] = AABB(Vector3(top.position.x, top.position.y, -top_rung_depth * 0.5),
				Vector3(top.size.x, top.size.y, top_rung_depth))
	if collides:
		_build_collision(solids)


## Una caja de colisión recortada en profundidad para no tocar a quien trepa,
## de ninguno de los dos lados: queda a no más de standoff menos el radio de su
## cuerpo (y 2 cm de margen) del eje. Los modelos pueden ser más gruesos que eso
## (un larguero de 20 cm): el dibujo queda igual, y lo que sobra no choca.
func _clipped(box: AABB) -> AABB:
	var clear := maxf(standoff - CLIMBER_RADIUS - 0.02, 0.01)
	var near := maxf(box.position.z, -clear)
	var far := minf(box.end.z, clear)
	return AABB(Vector3(box.position.x, box.position.y, near), Vector3(box.size.x, box.size.y, maxf(far - near, 0.01)))


## Una caja de colisión recortada para que no pase del alto, como los
## largueros: un peldaño justo en el alto, con un modelo grueso, sobresalía
## del piso del rellano, y la salida por arriba tenía que subir para pasarlo
## (2026-10-23). El dibujo queda igual.
func _below_top(box: AABB) -> AABB:
	if box.end.y <= height:
		return box
	return AABB(box.position, Vector3(box.size.x, maxf(height - box.position.y, 0.01), box.size.z))


## La colisión de las piezas: un cuerpo fijo en la capa de las escaleras, con
## una caja por cada una de `solids`. Va adentro del dibujo, así se rehace con él.
func _build_collision(solids: Array[AABB]) -> void:
	var body := StaticBody3D.new()
	body.name = "Colision"
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = 0
	_visual.add_child(body)
	for i in solids.size():
		var shape := BoxShape3D.new()
		shape.size = solids[i].size
		var holder := CollisionShape3D.new()
		holder.name = "Pieza%d" % i
		holder.shape = shape
		holder.position = solids[i].get_center()
		body.add_child(holder)


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
