extends Node3D

var activo = false
var puntos = []
var line : ImmediateMesh
var mesh_instance : MeshInstance3D

func _ready():
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	line = ImmediateMesh.new()
	mesh_instance.mesh = line
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 0, 0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material

func _input(event):
	if event.is_action_pressed("toggle_trail"):
		activo = !activo

func _process(_delta):
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	if activo:
		var pos = player.global_position
		pos.y -= 1.0
		puntos.append(pos)

	if puntos.size() < 2:
		return

	line.clear_surfaces()
	line.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in puntos:
		line.surface_add_vertex(p)
	line.surface_end()
