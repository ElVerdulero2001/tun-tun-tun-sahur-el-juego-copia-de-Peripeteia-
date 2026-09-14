class_name V3CameraRig
extends Node

## Cámara compartida del laboratorio. En esta primera rebanada usa la
## referencia acoplada de primera persona; no pertenece a H0.
@export var body: CharacterBody3D
@export var view: Node3D
@export var camera: Camera3D
@export var mouse_sensitivity := 0.003
@export var pitch_limit := deg_to_rad(89.0)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if body != null:
			body.rotate_y(-event.relative.x * mouse_sensitivity)
		if view != null:
			view.rotate_x(-event.relative.y * mouse_sensitivity)
			view.rotation.x = clampf(view.rotation.x, -pitch_limit, pitch_limit)


func get_planar_forward() -> Vector3:
	if camera == null:
		return Vector3.FORWARD
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.000001 else Vector3.FORWARD


func get_planar_right() -> Vector3:
	if camera == null:
		return Vector3.RIGHT
	var right := camera.global_transform.basis.x
	right.y = 0.0
	return right.normalized() if right.length_squared() > 0.000001 else Vector3.RIGHT


func get_camera_facts() -> Dictionary:
	return {
		"position": camera.global_position if camera != null else Vector3.ZERO,
		"distance_to_body": camera.global_position.distance_to(body.global_position) \
			if camera != null and body != null else 0.0,
		"planar_forward": get_planar_forward(),
		"planar_right": get_planar_right(),
		"body_yaw_degrees": rad_to_deg(body.rotation.y) if body != null else 0.0,
		"view_pitch_degrees": rad_to_deg(view.rotation.x) if view != null else 0.0,
	}
