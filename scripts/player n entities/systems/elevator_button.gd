# elevator_button.gd
# Va en un nodo con MeshInstance3D hijo (para que el marco de enfoque lo detecte)
# y CollisionShape3D en layer 2 (para que el raycast lo detecte).
# Implementa interactuar() para integrarse con el sistema de raycast existente.

extends StaticBody3D

@export var platform      : NodePath  # path al TransportPlatform
@export var station_index : int = 0   # índice de la estación destino
@export var floor_name    : String = "Piso"  # nombre que aparece en consola

# Datos para el marco de enfoque (requerido por raycast_interaction.gd)
var data = null  # sin Resource por ahora, el raycast maneja null

var _platform : Node = null

func _ready() -> void:
	if platform:
		_platform = get_node(platform)
	else:
		push_warning("[ElevatorButton] No hay plataforma asignada en botón: " + name)

func interactuar() -> void:
	if _platform == null:
		push_error("[ElevatorButton] Plataforma no encontrada.")
		return
	print("[ElevatorButton] Botón presionado: ", floor_name)
	_platform.go_to_station(station_index)
