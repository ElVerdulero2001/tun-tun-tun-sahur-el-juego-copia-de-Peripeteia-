# movement_controller.gd
# Nodo hijo del Player (CharacterBody3D).
# Responsabilidad ÚNICA: manejar velocidad, aceleración, salto,
# agacharse y fricción aérea. No sabe nada de parkour ni de combate.

extends Node

# ── Constantes de movimiento ──────────────────────────────────────
const SPEED               = 5.0
const RUN_SPEED           = 9.0
const CROUCH_SPEED        = 2.5
const JUMP_VELOCITY       = 4.5
const ACCELERATION        = 14.0
const CROUCH_TRANSITION   = 8.0
const AIR_CONTROL_FAST    = 0.3     # control aéreo con mucha velocidad horizontal
const AIR_CONTROL_SLOW    = 1.5     # control aéreo con poca velocidad horizontal
const AIR_FRICTION        = 0.8     # fricción al caer con impulso (ej: post-salto)
const FALL_FRICTION       = 3.0     # fricción al caer sin impulso

# ── Estado interno ────────────────────────────────────────────────
var current_speed : float = SPEED
var is_crouching  : bool  = false
var _jumped       : bool  = false   # privado, expuesto via propiedad

# ── Referencias (se asignan desde player.gd en _ready) ───────────
var body   : CharacterBody3D   # el CharacterBody3D del jugador
var camera : Camera3D
var collision_shape : CollisionShape3D

# ── Propiedad de solo lectura ─────────────────────────────────────
var jumped : bool:
	get: return _jumped

# ─────────────────────────────────────────────────────────────────
func setup(p_body: CharacterBody3D, p_camera: Camera3D, p_collision: CollisionShape3D) -> void:
	body           = p_body
	camera         = p_camera
	collision_shape = p_collision

# ─────────────────────────────────────────────────────────────────
# Llamado desde player.gd en _physics_process.
# Recibe delta y la dirección de input ya normalizada.
# Devuelve true si el movimiento fue procesado normalmente,
# false si algo externo (ej: TraversalController) debe tomar control.
func process(delta: float, direction: Vector3) -> void:
	_update_jump_state()
	_apply_gravity(delta)
	_handle_jump()
	_update_crouch(delta)
	_update_speed(delta)
	_apply_movement(delta, direction)

# ─────────────────────────────────────────────────────────────────
# API pública para que TraversalController pueda suspender
# o reanudar el movimiento normal.
func freeze() -> void:
	body.velocity.x = 0.0
	body.velocity.z = 0.0

func set_crouching(value: bool) -> void:
	is_crouching = value

# ─────────────────────────────────────────────────────────────────
func _update_jump_state() -> void:
	if body.is_on_floor():
		_jumped = false

func _apply_gravity(delta: float) -> void:
	if not body.is_on_floor():
		body.velocity += body.get_gravity() * delta

func _handle_jump() -> void:
	if Input.is_action_pressed("jump") and body.is_on_floor() and not is_crouching:
		body.velocity.y = JUMP_VELOCITY
		_jumped = true

func _update_crouch(delta: float) -> void:
	var target_height    = 0.8   if is_crouching else 2.0
	var target_camera_y  = 0.4   if is_crouching else 0.706
	collision_shape.shape.height = lerp(
		collision_shape.shape.height, target_height, CROUCH_TRANSITION * delta
	)
	camera.position.y = lerp(
		camera.position.y, target_camera_y, CROUCH_TRANSITION * delta
	)

func _update_speed(delta: float) -> void:
	var target_speed: float
	if is_crouching and body.is_on_floor():
		target_speed = CROUCH_SPEED
	elif Input.is_action_pressed("run"):
		target_speed = RUN_SPEED
	else:
		target_speed = SPEED
	current_speed = lerp(current_speed, target_speed, ACCELERATION * delta)

func _apply_movement(delta: float, direction: Vector3) -> void:
	if body.is_on_floor():
		var target_vx = direction.x * current_speed
		var target_vz = direction.z * current_speed
		body.velocity.x = lerp(body.velocity.x, target_vx, ACCELERATION * delta)
		body.velocity.z = lerp(body.velocity.z, target_vz, ACCELERATION * delta)

		# Clamp de velocidad horizontal en piso
		var horizontal = Vector2(body.velocity.x, body.velocity.z)
		if horizontal.length() > current_speed:
			horizontal = horizontal.normalized() * current_speed
			body.velocity.x = horizontal.x
			body.velocity.z = horizontal.y
	else:
		if direction != Vector3.ZERO:
			var vel_h = Vector2(body.velocity.x, body.velocity.z).length()
			var air_control = AIR_CONTROL_FAST if vel_h > 7.0 else AIR_CONTROL_SLOW
			body.velocity.x = lerp(body.velocity.x, direction.x * current_speed, air_control * delta)
			body.velocity.z = lerp(body.velocity.z, direction.z * current_speed, air_control * delta)
		else:
			var friction = AIR_FRICTION if _jumped else FALL_FRICTION
			body.velocity.x = lerp(body.velocity.x, 0.0, friction * delta)
			body.velocity.z = lerp(body.velocity.z, 0.0, friction * delta)
