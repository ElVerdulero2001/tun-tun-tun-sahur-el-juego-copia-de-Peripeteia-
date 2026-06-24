class_name VehicleButton
extends StaticBody3D

## Botón físico hijo del vehículo guiado.
## Al ser interactuado, solicita al vehículo que viaje al stop destino asignado.
## Debe vivir en la capa de física 2 para ser detectado por el raycast de interacción.

@export var stop_destino: StopPoint

var data: Resource = null  # Requerido por raycast_interaction.gd

@onready var vehiculo: GuidedVehicle = get_parent().get_parent()

func interactuar() -> void:
	assert(stop_destino != null, "VehicleButton: falta asignar 'stop_destino' en el Inspector.")
	vehiculo.solicitar_destino(stop_destino)
