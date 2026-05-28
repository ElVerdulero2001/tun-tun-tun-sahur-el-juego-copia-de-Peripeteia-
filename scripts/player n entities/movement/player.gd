# player.gd
# Coordinador. No contiene lógica de movimiento ni de parkour.
# Delega a los controllers correspondientes.

extends CharacterBody3D

const MOUSE_SENSITIVITY = 0.003

@onready var camera            : Camera3D        = $Camera3D
@onready var collision         : CollisionShape3D = $CollisionShape3D
@onready var salud                               = $Salud
@onready var movement          : Node            = $MovementController
@onready var parkour_detector  : Node            = $ParkourDetector
@onready var traversal         : Node            = $TraversalController

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	floor_stop_on_slope = true
	floor_max_angle     = deg_to_rad(46)
	floor_snap_length   = 0.5

	movement.setup(self, camera, collision)
	parkour_detector.setup(self, camera, traversal)
	traversal.setup(self, camera, movement, parkour_detector)
	salud.murio.connect(_on_murio)

func _on_murio() -> void:
	get_tree().reload_current_scene()

# ── Input: mouse y acciones de UI ────────────────────────────────
func _input(event: InputEvent) -> void:
	if UiInventario.visible:
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -PI / 2, PI / 2)

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event.is_action_pressed("crouch"):
		# Guardia: si el traversal está activo, o si se acaba de soltar
		# la cornisa y el jugador mantiene Control, ignorar el crouch.
		if traversal.is_active() or traversal.is_crouch_blocked_after_drop:
			return
		if movement.is_crouching and _hay_techo():
			pass
		else:
			movement.set_crouching(!movement.is_crouching)

# ── Physics ───────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if UiInventario.visible:
		velocity.x = lerp(velocity.x, 0.0, 14.0 * delta)
		velocity.z = lerp(velocity.z, 0.0, 14.0 * delta)
		move_and_slide()
		return

	# El TraversalController tiene prioridad cuando está activo.
	# Cuando está en IDLE, el MovementController tiene el control.
	if traversal.is_active():
		# Regla de hierro 1: mientras el traversal está activo, ÉL es el
		# dueño absoluto del body. Mueve global_position directamente.
		# NO debe correr move_and_slide() acá: reprocesaría la cápsula
		# con colisión y le pelearía la posición al traversal cada frame
		# (esto rompía el SNAPPING y el shimmy).
		traversal.process(delta)
	else:
		var direction = _get_input_direction()
		movement.process(delta, direction)
		parkour_detector.process(delta)
		move_and_slide()

# ── Helpers ───────────────────────────────────────────────────────
func _get_input_direction() -> Vector3:
	var dir = Vector3.ZERO
	if Input.is_action_pressed("move_forward"): dir -= transform.basis.z
	if Input.is_action_pressed("move_back"):    dir += transform.basis.z
	if Input.is_action_pressed("move_left"):    dir -= transform.basis.x
	if Input.is_action_pressed("move_right"):   dir += transform.basis.x
	return dir.normalized()

func _hay_techo() -> bool:
	var espacio = get_world_3d().direct_space_state
	var origen  = global_position
	var destino = global_position + Vector3.UP * (collision.shape.height + 0.6)
	var query   = PhysicsRayQueryParameters3D.create(origen, destino)
	query.exclude = [self]
	return espacio.intersect_ray(query).size() > 0
