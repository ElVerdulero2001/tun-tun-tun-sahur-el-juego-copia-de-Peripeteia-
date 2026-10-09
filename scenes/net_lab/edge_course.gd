extends Node3D

## Pista de bordes del laboratorio de Hanging, con las variantes que pide la
## arquitectura: altos de 1,6, 2 y 2,4 m; espesores de 5 cm, 20 cm y 1 m; la
## superficie de arriba inclinada 10 y 25°; una malla en vez de una caja; uno
## curvo; uno bajo un techo bajo; y uno entre dos paredes que salen de la cara.
## En una tercera fila, un muro alto con un cajón para colgarse de un compañero.
## Los bordes que se mueven (sobre una plataforma guionada y sobre un cuerpo
## rígido del host) son nodos del nivel, porque son bases con id de red.
##
## Todas las caras agarrables miran hacia +Z local: se llega caminando hacia -Z.
## Cada variante ocupa su lugar en la grilla, a VARIANT_SPACING de la anterior.
## Todo se arma al cargar, con el mismo código en todas las máquinas.

const VARIANT_SPACING := 3.5
const ROW_SPACING := 8.0
const WIDTH := 2.4
const DEPTH := 1.0

var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.albedo_color = Color(0.5, 0.55, 0.62)
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Fila 1: altos, espesores y malla.
	_block(Vector2(0, 0), 1.6, DEPTH, "1,6 m")
	_block(Vector2(1, 0), 2.0, DEPTH, "2,0 m")
	_block(Vector2(2, 0), 2.4, DEPTH, "2,4 m")
	_block(Vector2(3, 0), 2.0, 0.05, "5 cm de espesor")
	_block(Vector2(4, 0), 2.0, 0.2, "20 cm de espesor")
	_mesh_block(Vector2(5, 0), 2.0, "malla")
	# Fila 2: inclinados, curvo, techo bajo y paredes al costado.
	_sloped(Vector2(0, 1), 2.0, 10.0, "arriba inclinado 10°")
	_sloped(Vector2(1, 1), 2.0, 25.0, "arriba inclinado 25°")
	_curved(Vector2(2, 1), 2.0, "curvo")
	_under_ceiling(Vector2(3, 1), 2.0, "techo bajo:\nno se puede subir")
	_between_walls(Vector2(4, 1), 2.0, "paredes al costado")
	# Fila 3: el muro alto para colgarse de un compañero (punto 6).
	_teammate_wall(Vector2(1, 2))


## Centro de la cara en el piso para un lugar de la grilla.
func _slot(slot: Vector2) -> Vector3:
	return Vector3(slot.x * VARIANT_SPACING, 0.0, -slot.y * ROW_SPACING)


func _block(slot: Vector2, height: float, depth: float, text: String) -> void:
	var face := _slot(slot)
	var size := Vector3(WIDTH, height, depth)
	_add_body(BoxShape3D.new(), size, _box_mesh(size), face + Vector3(0, height * 0.5, -depth * 0.5))
	_add_label(text, face + Vector3(0, height + 0.7, 0.3))


func _mesh_block(slot: Vector2, height: float, text: String) -> void:
	var face := _slot(slot)
	var size := Vector3(WIDTH, height, DEPTH)
	var mesh := _box_mesh(size)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	body.position = face + Vector3(0, height * 0.5, -DEPTH * 0.5)
	add_child(body)
	_add_label(text, face + Vector3(0, height + 0.7, 0.3))


## La cara es vertical y el borde es lo más alto: la superficie de arriba baja
## alejándose de la cara.
func _sloped(slot: Vector2, height: float, degrees: float, text: String) -> void:
	var face := _slot(slot)
	var back := height - DEPTH * tan(deg_to_rad(degrees))
	var w := WIDTH * 0.5
	var points := PackedVector3Array([
		Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, height, 0), Vector3(-w, height, 0),
		Vector3(-w, 0, -DEPTH), Vector3(w, 0, -DEPTH), Vector3(w, back, -DEPTH), Vector3(-w, back, -DEPTH),
	])
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for quad in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(points[quad[i]])
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _material)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	body.position = face
	add_child(body)
	_add_label(text, face + Vector3(0, height + 0.7, 0.3))


func _curved(slot: Vector2, height: float, text: String) -> void:
	var face := _slot(slot)
	var radius := 1.0
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.material = _material
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	body.position = face + Vector3(0, height * 0.5, -radius)
	add_child(body)
	_add_label(text, face + Vector3(0, height + 0.7, 0.3))


## Un techo 60 cm por encima del borde, sobre la superficie y hacia afuera:
## colgarse cabe, pero arriba no entra el cuerpo agachado.
func _under_ceiling(slot: Vector2, height: float, text: String) -> void:
	_block(slot, height, DEPTH, text)
	var face := _slot(slot)
	var slab := Vector3(WIDTH, 0.2, 2.0)
	_add_body(BoxShape3D.new(), slab, _box_mesh(slab), face + Vector3(0, height + 0.6 + 0.1, 0.0))
	for side in [-1.0, 1.0]:
		var post := Vector3(0.2, height + 0.6, 0.2)
		_add_body(BoxShape3D.new(), post, _box_mesh(post), face + Vector3(side * (WIDTH * 0.5 - 0.1), (height + 0.6) * 0.5, 0.9))


## Dos paredes que salen de la cara a los costados: el borde sigue por detrás,
## pero colgado no se puede pasar más allá de ellas.
func _between_walls(slot: Vector2, height: float, text: String) -> void:
	var face := _slot(slot)
	var size := Vector3(WIDTH + 1.2, height, DEPTH)
	_add_body(BoxShape3D.new(), size, _box_mesh(size), face + Vector3(0, height * 0.5, -DEPTH * 0.5))
	for side in [-1.0, 1.0]:
		var wall := Vector3(0.3, height + 1.0, 1.2)
		_add_body(BoxShape3D.new(), wall, _box_mesh(wall), face + Vector3(side * 1.0, (height + 1.0) * 0.5, 0.6 - 0.1))
	_add_label(text, face + Vector3(0, height + 1.4, 0.3))


## Muro de 3,6 m, 6 m de ancho, centrado en el lugar: desde el piso las manos
## llegan a 3,12 m y no alcanzan el borde. El cajón de 0,6 m delante de su
## punta izquierda sí deja agarrarlo; colgado, se corre al medio, y desde el
## piso otro salta y se cuelga de su cintura.
func _teammate_wall(slot: Vector2) -> void:
	var face := _slot(slot)
	var height := 3.6
	var size := Vector3(6.0, height, DEPTH)
	_add_body(BoxShape3D.new(), size, _box_mesh(size), face + Vector3(0, height * 0.5, -DEPTH * 0.5))
	var box := Vector3(1.2, 0.6, 1.0)
	_add_body(BoxShape3D.new(), box, _box_mesh(box), face + Vector3(-3.0 + box.x * 0.5, box.y * 0.5, box.z * 0.5))
	_add_label("colgarse de un compañero: 3,6 m\ndesde el cajón, agarrate y correte al medio", face + Vector3(0, height + 0.7, 0.3))


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material
	return mesh


func _add_body(shape: Shape3D, size: Vector3, mesh: Mesh, center: Vector3) -> void:
	var box := shape as BoxShape3D
	box.size = size
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = box
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	body.position = center
	add_child(body)


func _add_label(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.95, 0.95, 0.95)
	label.outline_modulate = Color(0.1, 0.1, 0.12)
	label.outline_size = 12
	label.position = at
	add_child(label)
