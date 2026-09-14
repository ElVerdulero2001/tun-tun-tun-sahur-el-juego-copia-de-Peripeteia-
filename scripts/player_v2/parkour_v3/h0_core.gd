class_name H0Core
extends Node

## H0 decide la locomoción mínima. No mueve el CharacterBody3D directamente:
## sólo expresa una intención a la capa física común.
@export var input_source: V3InputSource
@export var camera_rig: V3CameraRig
@export var physics_body: V3PhysicsBody
@export var walk_speed := 5.0

var last_input_axis := Vector2.ZERO
var last_desired_horizontal_velocity := Vector3.ZERO
var last_observed_facts: Dictionary = {}


func _physics_process(_delta: float) -> void:
	if input_source == null or camera_rig == null or physics_body == null:
		return

	last_observed_facts = physics_body.get_physics_facts()
	last_input_axis = input_source.movement_axis

	var direction := camera_rig.get_planar_right() * last_input_axis.x
	direction += camera_rig.get_planar_forward() * -last_input_axis.y
	if direction.length_squared() > 0.000001:
		direction = direction.normalized()

	last_desired_horizontal_velocity = direction * walk_speed
	physics_body.submit_motion_intent(self, last_desired_horizontal_velocity)
