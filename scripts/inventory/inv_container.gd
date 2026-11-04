class_name InvContainer
extends StaticBody3D

## Una caja con inventario propio: se abre con E mirándola de cerca, y la pueden
## tener abierta varios jugadores a la vez. Su grilla es el componente
## InvInventory hijo; las medidas se cambian acá (Columns y Rows). La caja se
## dibuja y choca con una caja de Box Size, apoyada en el piso.
##
## No hace falta numerarla: InvNet la numera según su orden en la escena.

@export var display_name := "Caja"
## Hasta qué distancia, de los pies del jugador al centro de la caja, se abre y
## se opera. Alejándose más, se cierra sola.
@export var access_range := 2.2
@export_range(1, 64) var columns := 8
@export_range(1, 64) var rows := 6
@export var box_size := Vector3(1.0, 0.8, 0.7)
@export var color := Color(0.55, 0.38, 0.2)
## La grilla de la caja.
@export var inventory: InvInventory

## Lo pone InvNet al arrancar: el número con que la nombran los pedidos.
var container_id := 0


func _ready() -> void:
	if inventory != null:
		inventory.columns = columns
		inventory.rows = rows
		inventory.has_loadout = false
	var shape := CollisionShape3D.new()
	shape.name = "Forma"
	var box_shape := BoxShape3D.new()
	box_shape.size = box_size
	shape.shape = box_shape
	shape.position = Vector3.UP * box_size.y / 2.0
	add_child(shape)
	for part in InvContainer.look(display_name, box_size, color):
		add_child(part)


## Cómo se ve una caja: su malla apoyada en el piso y el cartel. Lo usa también
## la vista previa del panel Objetos del editor.
static func look(shown_name: String, size: Vector3, tint: Color) -> Array[Node3D]:
	var mesh := MeshInstance3D.new()
	mesh.name = "Malla"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	box_mesh.material = material
	mesh.mesh = box_mesh
	mesh.position = Vector3.UP * size.y / 2.0
	var label := Label3D.new()
	label.name = "Cartel"
	label.text = "%s\nE para abrir" % shown_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.004
	label.outline_size = 8
	label.position = Vector3.UP * (size.y + 0.35)
	return [mesh, label]


## Hacia dónde se mide el alcance.
func access_point() -> Vector3:
	return global_position


## El centro de la caja: hacia ahí se mira si el personaje la ve.
func center() -> Vector3:
	return to_global(Vector3.UP * box_size.y / 2.0)
