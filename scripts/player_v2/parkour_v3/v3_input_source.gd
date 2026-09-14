class_name V3InputSource
extends Node

## Fuente compartida de directivas voluntarias. No conoce H0 ni ningún core.
var movement_axis: Vector2 = Vector2.ZERO


func _physics_process(_delta: float) -> void:
	movement_axis = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
