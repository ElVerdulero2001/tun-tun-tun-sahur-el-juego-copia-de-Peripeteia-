class_name V3CameraRig
extends Node

## Cámara compartida del laboratorio. En esta primera rebanada usa la
## referencia acoplada de primera persona; no pertenece a H0.
@export var body: CharacterBody3D
@export var view: Node3D
@export var camera: Camera3D
@export var physics_body: Node
@export var mouse_sensitivity := 0.003
@export var pitch_limit := deg_to_rad(89.0)
@export var crouched_view_height := 1.0
# La diferencia actual de altura es 0.6 m: a 3.5 m/s tarda ~0.17 s.
# Es sólo presentación; el collider cambia en el tick físico.
@export var stance_view_transition_speed := 3.5

var _standing_view_height := 0.0
var _seen_stance_anchor_revision := -1


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if view != null:
		_standing_view_height = view.position.y
	process_physics_priority = 200
	if physics_body != null:
		_seen_stance_anchor_revision = physics_body.stance_anchor_revision


func _physics_process(delta: float) -> void:
	if view == null or physics_body == null:
		return
	if physics_body.stance_anchor_revision != _seen_stance_anchor_revision:
		# Si el body se reancló al piso al aterrizar, compensamos el movimiento
		# local de la cámara antes de suavizarla para que no pegue un salto visual.
		view.position.y -= physics_body.last_stance_anchor_rebase_delta
		_seen_stance_anchor_revision = physics_body.stance_anchor_revision
	var use_ground_crouch_view: bool = physics_body.is_crouched \
		and physics_body.crouch_anchor == V3PhysicsBody.CrouchAnchor.GROUND
	var target_height := crouched_view_height if use_ground_crouch_view else _standing_view_height
	view.position.y = move_toward(view.position.y, target_height, stance_view_transition_speed * delta)


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
