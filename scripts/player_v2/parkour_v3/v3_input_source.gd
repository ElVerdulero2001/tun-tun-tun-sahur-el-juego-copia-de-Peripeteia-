class_name V3InputSource
extends Node

## Fuente compartida de directivas voluntarias. No conoce H0 ni ningún core.
var movement_axis: Vector2 = Vector2.ZERO
var jump_pressed := false
var crouch_just_pressed := false
var sprint_active := false


func _physics_process(_delta: float) -> void:
	movement_axis = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	jump_pressed = Input.is_action_pressed("jump")
	crouch_just_pressed = Input.is_action_just_pressed("crouch")
	sprint_active = Input.is_action_pressed("run")
