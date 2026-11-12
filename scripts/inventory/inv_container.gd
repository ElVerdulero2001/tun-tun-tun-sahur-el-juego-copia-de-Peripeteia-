class_name InvContainer
extends StaticBody3D

## Una caja con inventario propio: se abre con E mirándola de cerca, y la pueden
## tener abierta varios jugadores a la vez. Su grilla es el componente
## InvInventory hijo; las medidas se cambian acá (Columns y Rows). La caja se
## dibuja y choca con una caja de Box Size, apoyada en el piso.
##
## No hace falta numerarla: InvNet la numera según su orden en la escena.
##
## Hasta dónde se abre no es de cada caja (desde el 2026-11-11; hasta ese día
## era su Access Range, de los pies al centro de su base): es el alcance común
## del Tuning (interaction_range). Se abre con un rayo desde los ojos que la
## toca antes que otra cosa, a no más del alcance (su colisión, la de
## reach_box); abierta, sigue abierta mientras los ojos estén a no más del
## alcance de su parte más cercana, con su lugar, su giro y su escala (InvReach).

@export var display_name := "Caja"
@export_range(1, 64) var columns := 8
@export_range(1, 64) var rows := 6
@export var box_size := Vector3(1.0, 0.8, 0.7)
@export var color := Color(0.55, 0.38, 0.2)
## La grilla de la caja.
@export var inventory: InvInventory

## Lo pone InvNet al arrancar: el número con que la nombran los pedidos.
var container_id := 0

var _focus: InteractFocus


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


## Lo que marca el indicador de lo que se mira (desde el 2026-11-06) cuando E
## abriría esta caja: su malla y su nombre. Mientras está marcada, el indicador
## oculta el cartel de arriba.
func interact_focus() -> InteractFocus:
	if _focus == null:
		_focus = InteractFocus.new("", self, InteractFocus.mesh_bounds(self), get_node_or_null(^"Cartel") as Node3D)
	_focus.display_name = display_name
	return _focus


## El volumen hasta el que se mide el alcance con la caja abierta, en el
## espacio de la caja (el mismo que su colisión, apoyado en el piso): InvReach
## lo lleva al mundo con su lugar, su giro y su escala.
func reach_box() -> AABB:
	return AABB(Vector3(-box_size.x / 2.0, 0.0, -box_size.z / 2.0), box_size)


## El centro de la caja: en tercera persona, tiene que estar adelante del
## cuerpo para abrirla (InvNet.look_cone_degrees).
func center() -> Vector3:
	return to_global(Vector3.UP * box_size.y / 2.0)
