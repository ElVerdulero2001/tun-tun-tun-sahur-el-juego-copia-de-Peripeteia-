extends Node3D

@export var vehiculo: GuidedVehicle
@export var stop_0: StopPoint
@export var stop_1: StopPoint
@export var stop_2: StopPoint

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_SPACE:
			vehiculo.solicitar_destino(stop_2)
		KEY_C:
			vehiculo.solicitar_destino(stop_0)
