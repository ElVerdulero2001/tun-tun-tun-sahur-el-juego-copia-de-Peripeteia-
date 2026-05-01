extends RigidBody3D

@export var viewport_externo: SubViewport

@onready var pantalla: MeshInstance3D = $osciloscopio5/pantalla

func _ready():
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = viewport_externo.get_texture()
	mat.emission_enabled = true
	mat.emission_texture = viewport_externo.get_texture()
	mat.emission_energy_multiplier = 1.0
	pantalla.set_surface_override_material(0, mat)
