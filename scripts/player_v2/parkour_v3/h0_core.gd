class_name H0Core
extends Node

## H0 decide la locomoción mínima. No mueve el CharacterBody3D directamente:
## sólo expresa una intención a la capa física común.
@export var input_source: V3InputSource
@export var camera_rig: V3CameraRig
@export var physics_body: V3PhysicsBody
@export var fall_damage_state: Node
@export var walk_speed := 5.0
@export var crouch_speed := 2.5
@export var sprint_speed := 8.0
@export var sprint_release_air_deceleration := 8.0
@export var air_control_duration := 0.35

var last_input_axis := Vector2.ZERO
var last_desired_horizontal_velocity := Vector3.ZERO
var last_observed_facts: Dictionary = {}
var last_jump_requested := false
var last_air_control_remaining := 0.0
var last_jump_blocked_by_fall_damage := false
var wants_crouched := false
var last_crouch_requested := false
var last_sprint_active := false
var _was_on_floor := false


func _physics_process(delta: float) -> void:
	if input_source == null or camera_rig == null or physics_body == null or fall_damage_state == null:
		return

	last_observed_facts = physics_body.get_physics_facts()
	last_input_axis = input_source.movement_axis
	var is_on_floor := bool(last_observed_facts["is_on_floor"])
	# Una orden de pararse rechazada no queda pendiente. H0 vuelve a conservar
	# crouch como postura deseada: al salir de un techo bajo, el player no se
	# expone automáticamente. Hace falta una nueva pulsación para pararse.
	if bool(last_observed_facts["stand_request_blocked"]):
		wants_crouched = true
	if input_source.crouch_just_pressed:
		wants_crouched = not wants_crouched
	last_crouch_requested = wants_crouched

	var direction := camera_rig.get_planar_right() * last_input_axis.x
	direction += camera_rig.get_planar_forward() * -last_input_axis.y
	if direction.length_squared() > 0.000001:
		direction = direction.normalized()

	# Espacio sostenido es una intención continua. No hay buffer: al recuperar
	# piso, H0 vuelve a solicitar salto mientras siga existiendo esa intención.
	# Una lesión por caída es una condición externa, no un temporizador de H0.
	last_jump_blocked_by_fall_damage = fall_damage_state.jump_is_penalized
	last_jump_requested = input_source.jump_pressed and is_on_floor and not last_jump_blocked_by_fall_damage

	if is_on_floor:
		last_air_control_remaining = air_control_duration
	elif _was_on_floor:
		# También cubre el instante en que el player abandona un borde.
		last_air_control_remaining = air_control_duration
	else:
		last_air_control_remaining = maxf(last_air_control_remaining - delta, 0.0)

	var is_physically_crouched := bool(last_observed_facts["is_crouched"])
	# La postura agachada cancela sprint sólo en piso. En aire, crouch cambia
	# tamaño físico pero no debe borrar la inercia de carrera por sí mismo.
	last_sprint_active = input_source.sprint_active and (
		not is_on_floor or not (wants_crouched or is_physically_crouched))

	if is_on_floor:
		var ground_speed := crouch_speed if wants_crouched or is_physically_crouched else (
			sprint_speed if last_sprint_active else walk_speed)
		last_desired_horizontal_velocity = direction * ground_speed
	elif last_air_control_remaining > 0.0:
		last_desired_horizontal_velocity = _get_air_control_velocity(direction, delta)
	else:
		# Cuando vence el control aéreo, H0 conserva la inercia horizontal que
		# publicó la capa física; no corrige trayectoria hasta tocar piso.
		var current_velocity := last_observed_facts["velocity"] as Vector3
		last_desired_horizontal_velocity = Vector3(current_velocity.x, 0.0, current_velocity.z)

	physics_body.submit_motion_intent(self, last_desired_horizontal_velocity, last_jump_requested, last_crouch_requested)
	_was_on_floor = is_on_floor


func _get_air_control_velocity(direction: Vector3, delta: float) -> Vector3:
	var current_velocity := last_observed_facts["velocity"] as Vector3
	var current_horizontal := Vector3(current_velocity.x, 0.0, current_velocity.z)
	var target_speed := sprint_speed if input_source.sprint_active else walk_speed
	var target_velocity := direction * target_speed

	if not input_source.sprint_active and current_horizontal.length() > walk_speed:
		# Soltar Shift en aire no borra la carrera en un tick: se conserva una
		# parte de la inercia y se desacelera hacia el control normal.
		return current_horizontal.move_toward(target_velocity, sprint_release_air_deceleration * delta)
	return target_velocity
