# transport_platform.gd
extends AnimatableBody3D

@export var move_speed      : float = 1.5
@export var acceleration    : float = 2.0
@export var deceleration    : float = 3.0
@export var decel_threshold : float = 0.15
@export var start_marker    : Node3D
@export var end_marker      : Node3D

@export var detect_area : Area3D

enum PlatformState { IDLE, MOVING_UP, MOVING_DOWN }
var _state         : PlatformState = PlatformState.IDLE
var _progress      : float = 0.0
var _speed_current : float = 0.0
var _passenger     : CharacterBody3D = null
var _movement_ctrl : Node = null

signal arrived_at_bottom()
signal arrived_at_top()

func _ready() -> void:
	detect_area.body_entered.connect(_on_body_entered)
	detect_area.body_exited.connect(_on_body_exited)
	call_deferred("_init_position")

func _init_position() -> void:
	if start_marker:
		global_position = start_marker.global_position
	else:
		push_error("[TransportPlatform] StartMarker no encontrado.")

func _physics_process(delta: float) -> void:
	if _state == PlatformState.IDLE:
		return

	var pos_before = global_position

	_update_speed(delta)
	_update_progress(delta)
	_apply_position()

	var platform_delta = global_position - pos_before

	if _passenger != null and is_instance_valid(_passenger):
		if platform_delta != Vector3.ZERO:
			_passenger.global_position += platform_delta

func call_to_bottom() -> void:
	if _progress <= 0.01:
		return
	_state = PlatformState.MOVING_DOWN
	print("[TransportPlatform] Bajando...")

func call_to_top() -> void:
	if _progress >= 0.99:
		return
	_state = PlatformState.MOVING_UP
	print("[TransportPlatform] Subiendo...")

func get_progress() -> float:
	return _progress

func _update_speed(delta: float) -> void:
	var dist_to_dest : float
	if _state == PlatformState.MOVING_UP:
		dist_to_dest = 1.0 - _progress
	else:
		dist_to_dest = _progress

	if dist_to_dest < decel_threshold:
		var t = dist_to_dest / decel_threshold
		var target_speed = move_speed * max(t, 0.05)
		_speed_current = lerp(_speed_current, target_speed, deceleration * delta)
	else:
		_speed_current = lerp(_speed_current, move_speed, acceleration * delta)

func _update_progress(delta: float) -> void:
	match _state:
		PlatformState.MOVING_UP:
			_progress += _speed_current * delta
			if _progress >= 1.0:
				_progress = 1.0
				_speed_current = 0.0
				_state = PlatformState.IDLE
				print("[TransportPlatform] Llegó arriba.")
				arrived_at_top.emit()
		PlatformState.MOVING_DOWN:
			_progress -= _speed_current * delta
			if _progress <= 0.0:
				_progress = 0.0
				_speed_current = 0.0
				_state = PlatformState.IDLE
				print("[TransportPlatform] Llegó abajo.")
				arrived_at_bottom.emit()

func _apply_position() -> void:
	if not start_marker or not end_marker:
		return
	var from      : Vector3 = start_marker.global_position
	var to        : Vector3 = end_marker.global_position
	var target    : Vector3 = from.lerp(to, _progress)
	var delta_pos : Vector3 = target - global_position
	move_and_collide(delta_pos)

func _on_body_entered(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return
	if _passenger != null:
		return
	_passenger = body
	var movement_node = body.get_node_or_null("movement/MovementController")
	if movement_node:
		_movement_ctrl = movement_node
		_movement_ctrl.set_on_platform(true)
	print("[TransportPlatform] Pasajero subió: ", body.name)

func _on_body_exited(body: Node3D) -> void:
	# Al salir del área: desactivar gravedad-lock pero mantener _passenger
	# si la plataforma se está moviendo (para seguir empujándolo)
	if body != _passenger:
		return
	if _movement_ctrl:
		_movement_ctrl.set_on_platform(false)
	# Si la plataforma está quieta, también limpiar el registro
	if _state == PlatformState.IDLE:
		_passenger = null
		_movement_ctrl = null
		print("[TransportPlatform] Pasajero bajó.")
