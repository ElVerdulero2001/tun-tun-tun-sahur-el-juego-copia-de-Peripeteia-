class_name VehicleButton
extends StaticBody3D

## Botón físico hijo del vehículo guiado.
## Al ser interactuado, solicita al vehículo que viaje al stop destino asignado.
## Debe vivir en la capa de física 2 para ser detectado por el raycast de interacción.

@export var stop_destino: StopPoint
@export var nombre: String = "Botón"

var data: Dictionary:
	get: return {"nombre": nombre}

@onready var vehiculo: GuidedVehicle = get_parent().get_parent()

func _on_interact(interaction: Interaction) -> Variant:
	match interaction.accion:
		&"usar":
			return _viajar()
		_:
			return false

func _viajar() -> bool:
	assert(stop_destino != null, "VehicleButton: falta asignar 'stop_destino' en el Inspector.")
	vehiculo.solicitar_destino(stop_destino)
	return true
