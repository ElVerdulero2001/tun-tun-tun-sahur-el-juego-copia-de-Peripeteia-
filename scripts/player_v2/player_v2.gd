extends CharacterBody3D

## PlayerV2 — locomoción básica (SUA-1.1).
##
## Alcance deliberadamente mínimo: gravedad, caminar, salto simple y mouse-look
## (yaw en este Body, pitch en el nodo View). Nada más.
##
## Este script es la autoridad física del Player: posee velocity, move_and_slide()
## y el yaw. NO accede a autoloads ni a sistemas del proyecto, y PlayerV2 no está
## en el grupo "player" todavía.

# ── Parámetros ──────────────────────────────────────────────────────
# Valores tomados como REFERENCIA de sensación del Player V1, no como contrato.
const WALK_SPEED        := 5.0
const JUMP_VELOCITY     := 4.5
const MOUSE_SENSITIVITY := 0.003
const PITCH_LIMIT       := 1.553343  # deg_to_rad(89°) — impide el giro vertical completo

# ── Referencias internas ────────────────────────────────────────────
@onready var _view: Node3D = $View

# ─────────────────────────────────────────────────────────────────────
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ── Mouse-look ──────────────────────────────────────────────────────
## ui_cancel / ESC NO se maneja acá (SUA-1.4 C4-C): el cuerpo físico no es
## dueño del foco de input. Con el InventoryPanel abierto, PlayerInventoryUI
## consume ESC para cerrarlo; con nada abierto, ESC no hace nada. Un futuro
## menú de pausa podrá apropiarse de ESC cuando exista.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)                       # yaw en el Body
		_view.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)                 # pitch en View
		_view.rotation.x = clampf(_view.rotation.x, -PITCH_LIMIT, PITCH_LIMIT)

# ── Locomoción ──────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * WALK_SPEED
		velocity.z = direction.z * WALK_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED)

	move_and_slide()
