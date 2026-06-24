class_name CallButton
extends StaticBody3D

## Botón de llamada fijo en el mundo.
## Llama al vehículo guiado para que viaje al stop destino asignado.
## Debe vivir en la capa de física 2 para ser detectado por el raycast de interacción.

@export var vehiculo: GuidedVehicle
@export var stop_destino: StopPoint

var data: Resource = null  # Requerido por raycast_interaction.gd

func interactuar() -> void:
	assert(vehiculo != null, "CallButton: falta asignar 'vehiculo' en el Inspector.")
	assert(stop_destino != null, "CallButton: falta asignar 'stop_destino' en el Inspector.")
	vehiculo.solicitar_destino(stop_destino)
