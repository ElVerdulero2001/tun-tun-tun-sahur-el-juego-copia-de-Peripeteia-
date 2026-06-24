extends Node3D

func _input(event):
	if event.is_action_pressed("ui_accept"):
		$world/enviroment/paths/teleferico_prueba/path_prueba/GuidedVehicle.solicitar_destino(
			$world/enviroment/paths/teleferico_prueba/path_prueba/stoppoint_1
		)
