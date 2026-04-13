extends CharacterBody3D

const SPEED = 5.0
const RUN_SPEED = 9.0
const CROUCH_SPEED = 2.5
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.003
const ACCELERATION = 14.0
const CROUCH_SPEED_TRANSITION = 8.0
const AIR_CONTROL = 0.3
const AIR_FRICTION = 0.8
const FALL_FRICTION = 3.0

var current_speed = SPEED
var is_crouching = false
var jumped = false

@onready var camera = $Camera3D
@onready var collision = $CollisionShape3D

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.position.y = 0.706
	collision.shape.height = 2.0
	floor_stop_on_slope = true
	floor_max_angle = deg_to_rad(46)
	floor_snap_length = 0.5

func hay_techo() -> bool:
	var espacio = get_world_3d().direct_space_state
	var origen = global_position
	var destino = global_position + Vector3.UP * (collision.shape.height + 0.6)
	var query = PhysicsRayQueryParameters3D.create(origen, destino)
	query.exclude = [self]
	var resultado = espacio.intersect_ray(query)
	return resultado.size() > 0

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event.is_action_pressed("crouch"):
		if is_crouching and hay_techo():
			pass
		else:
			is_crouching = !is_crouching

func _physics_process(delta):
	if is_on_floor():
		jumped = false

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY
		jumped = true

	var target_height = 1.0 if is_crouching else 2.0
	var target_camera_y = 0.4 if is_crouching else 0.706
	collision.shape.height = lerp(collision.shape.height, target_height, CROUCH_SPEED_TRANSITION * delta)
	camera.position.y = lerp(camera.position.y, target_camera_y, CROUCH_SPEED_TRANSITION * delta)

	var target_speed
	if is_crouching and is_on_floor():
		target_speed = CROUCH_SPEED
	elif Input.is_action_pressed("run"):
		target_speed = RUN_SPEED
	else:
		target_speed = SPEED

	current_speed = lerp(current_speed, target_speed, ACCELERATION * delta)

	var direction = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		direction -= transform.basis.z
	if Input.is_action_pressed("move_back"):
		direction += transform.basis.z
	if Input.is_action_pressed("move_left"):
		direction -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		direction += transform.basis.x

	direction = direction.normalized()

	if is_on_floor():
		var target_velocity_x = direction.x * current_speed
		var target_velocity_z = direction.z * current_speed
		velocity.x = lerp(velocity.x, target_velocity_x, ACCELERATION * delta)
		velocity.z = lerp(velocity.z, target_velocity_z, ACCELERATION * delta)

		# Limitar velocidad horizontal maxima
		var vel_horizontal = Vector2(velocity.x, velocity.z).length()
		if vel_horizontal > current_speed:
			var direccion_actual = Vector2(velocity.x, velocity.z).normalized()
			velocity.x = direccion_actual.x * current_speed
			velocity.z = direccion_actual.y * current_speed
	else:
		if direction != Vector3.ZERO:
			var vel_horizontal = Vector2(velocity.x, velocity.z).length()
			var air_control = AIR_CONTROL if vel_horizontal > 7.0 else AIR_CONTROL * 5.0
			velocity.x = lerp(velocity.x, direction.x * current_speed, air_control * delta)
			velocity.z = lerp(velocity.z, direction.z * current_speed, air_control * delta)
		else:
			var friction = AIR_FRICTION if jumped else FALL_FRICTION
			velocity.x = lerp(velocity.x, 0.0, friction * delta)
			velocity.z = lerp(velocity.z, 0.0, friction * delta)

	move_and_slide()
