extends Node3D

## Pista de escalones del laboratorio. Tiene escalones sueltos de 10, 20, 30 y
## 40 cm (el de 40 ya no se sube caminando) y dos escaleras iguales, de seis
## escalones de 20 cm. Una no tiene nada encima; la otra tiene una rampa de
## colisión invisible, que es lo que pide la arquitectura para las escaleras.
## Todo se arma al cargar, con el mismo código en todas las máquinas.
##
## Los escalones miran hacia -Z local: se suben caminando hacia +Z.

const LOOSE_HEIGHTS := [0.1, 0.2, 0.3, 0.4]
## Ancho (x) y fondo (z) de cada escalón suelto.
const LOOSE_SIZE := Vector2(1.5, 2.0)
const LOOSE_SPACING := 2.5
const STAIR_RISE := 0.2
const STAIR_TREAD := 0.35
const STAIR_COUNT := 6
const STAIR_WIDTH := 2.0
const LANDING_DEPTH := 2.0
const STAIR_SPACING := 3.0
const RAMP_THICKNESS := 0.1

var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.albedo_color = Color(0.62, 0.55, 0.45)
	var x := 0.0
	for height: float in LOOSE_HEIGHTS:
		_add_block(Vector3(LOOSE_SIZE.x, height, LOOSE_SIZE.y), Vector3(x, height * 0.5, LOOSE_SIZE.y * 0.5))
		var text := "%d cm" % roundi(height * 100.0)
		if height > 0.3:
			text += "\nno se sube"
		_add_label(text, Vector3(x, height + 0.6, LOOSE_SIZE.y * 0.5))
		x -= LOOSE_SPACING
	x -= STAIR_SPACING - LOOSE_SPACING + LOOSE_SIZE.x * 0.5
	_add_stairs(x, false)
	_add_label("Escalera\nsin rampa", Vector3(x, 1.0, -0.6))
	x -= STAIR_SPACING
	_add_stairs(x, true)
	_add_label("Escalera con\nrampa invisible", Vector3(x, 1.0, -0.6))


func _add_stairs(x: float, ramp: bool) -> void:
	for i in STAIR_COUNT:
		var top := STAIR_RISE * (i + 1)
		_add_block(Vector3(STAIR_WIDTH, top, STAIR_TREAD), Vector3(x, top * 0.5, STAIR_TREAD * (i + 0.5)))
	var rise := STAIR_RISE * STAIR_COUNT
	var run := STAIR_TREAD * STAIR_COUNT
	_add_block(Vector3(STAIR_WIDTH, rise, LANDING_DEPTH), Vector3(x, rise * 0.5, run + LANDING_DEPTH * 0.5))
	if not ramp:
		return
	# La cara de arriba de la rampa pasa por los filos de los escalones: arranca
	# en el piso un escalón antes del primero y llega arriba en el filo del
	# último. Solo colisión: se ven los escalones y se camina sobre la rampa.
	var angle := atan2(rise, run)
	var tilt := Basis(Vector3.RIGHT, -angle)
	var middle := Vector3(x, rise * 0.5, run * 0.5 - STAIR_TREAD)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(STAIR_WIDTH, RAMP_THICKNESS, Vector2(run, rise).length())
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(tilt, middle - tilt.y * RAMP_THICKNESS * 0.5)
	add_child(body)


func _add_block(size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
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
