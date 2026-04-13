extends Node3D

@export_group("Configuracion")
@export var mostrar_raycast: bool = true
@export var distancia_interaccion: float = 2.5
@export var color_rayo: Color = Color.GREEN
@export_flags_3d_physics var capa_interaccion: int = 2

@onready var player = get_tree().get_first_node_in_group("player")
@onready var camera = player.get_node("Camera3D")

var line_mesh : ImmediateMesh
var line_instance : MeshInstance3D
var objeto_mirado = null

func _ready():
	line_instance = MeshInstance3D.new()
	add_child(line_instance)
	line_mesh = ImmediateMesh.new()
	line_instance.mesh = line_mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = color_rayo
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_instance.material_override = material

func _process(_delta):
	var espacio = player.get_world_3d().direct_space_state
	var origen = camera.global_position
	var destino = origen + (-camera.global_transform.basis.z * distancia_interaccion)
	var query = PhysicsRayQueryParameters3D.create(origen, destino, capa_interaccion)
	query.exclude = [player]
	var resultado = espacio.intersect_ray(query)
	if resultado:
		objeto_mirado = buscar_interactable(resultado.collider)
	else:
		objeto_mirado = null

	if not mostrar_raycast:
		line_mesh.clear_surfaces()
		return
	line_mesh.clear_surfaces()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	line_mesh.surface_add_vertex(line_instance.to_local(origen))
	line_mesh.surface_add_vertex(line_instance.to_local(destino))
	line_mesh.surface_end()

func buscar_interactable(nodo):
	var actual = nodo
	while actual != null:
		if actual.has_method("interactuar"):
			return actual
		actual = actual.get_parent()
	return null

func _input(event):
	if event.is_action_pressed("interactuar"):
		if objeto_mirado:
			var nombre = objeto_mirado.data.nombre if objeto_mirado.data else "desconocido"
			objeto_mirado.interactuar()
			print("Interactuando con: ", nombre)
		else:
			print("Raycast no detecto nada interactuable")
