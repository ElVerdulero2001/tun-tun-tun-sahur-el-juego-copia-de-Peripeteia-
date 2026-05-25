# free_camera.gd
# Cámara libre de debug. Nodo Camera3D suelto en la escena (NO hija del player).
# Se togglea con una tecla; cuando está activa, el player queda congelado
# visualmente pero el mundo sigue corriendo, y podés volar para inspeccionar.
#
# Setup:
#   1. Agregá un nodo Camera3D a la escena raíz (al lado del player, no adentro).
#   2. Asignale este script.
#   3. Definí una acción de input "toggle_free_cam" (ej: tecla F).
#   4. Opcional: WASD ya existen como move_*, pero esta cámara usa sus propias
#      teclas para no pelearse con el player. Ver _get_move_input().

extends Camera3D

# ── Parámetros ────────────────────────────────────────────────────
@export var move_speed       : float = 8.0
@export var fast_multiplier  : float = 3.0
@export var mouse_sensitivity: float = 0.003
@export var toggle_action    : String = "toggle_free_cam"

# ── Estado ────────────────────────────────────────────────────────
var _active : bool = false
var _player_camera : Camera3D
var _yaw   : float = 0.0
var _pitch : float = 0.0

# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Arranca desactivada — la cámara del player tiene prioridad.
	current = false
	# Buscar la cámara del player para poder devolverle el control.
	var player = get_tree().get_first_node_in_group("player")
	if player:
		_player_camera = player.get_node_or_null("Camera3D")

# ─────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action):
		_toggle()

	if not _active:
		return

	if event is InputEventMouseMotion:
		_yaw   -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, -PI / 2.0 + 0.01, PI / 2.0 - 0.01)
		rotation = Vector3(_pitch, _yaw, 0.0)

# ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not _active:
		return

	var input = _get_move_input()
	var speed = move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier

	# Movimiento relativo a la orientación de la cámara
	var dir = (transform.basis * input).normalized()
	global_position += dir * speed * delta

# ─────────────────────────────────────────────────────────────────
func _toggle() -> void:
	_active = not _active

	if _active:
		# Colocar la free cam donde está la cámara del player, para no
		# desorientar al usuario al activarla.
		if _player_camera:
			global_transform = _player_camera.global_transform
			_yaw   = rotation.y
			_pitch = rotation.x
		current = true
	else:
		# Devolver el control a la cámara del player.
		current = false
		if _player_camera:
			_player_camera.current = true

# ─────────────────────────────────────────────────────────────────
# Teclas dedicadas para no chocar con el input del player.
# I/K = adelante/atrás, J/L = izquierda/derecha, U/O = abajo/arriba.
func _get_move_input() -> Vector3:
	var v = Vector3.ZERO
	if Input.is_key_pressed(KEY_I): v.z -= 1.0
	if Input.is_key_pressed(KEY_K): v.z += 1.0
	if Input.is_key_pressed(KEY_J): v.x -= 1.0
	if Input.is_key_pressed(KEY_L): v.x += 1.0
	if Input.is_key_pressed(KEY_U): v.y -= 1.0
	if Input.is_key_pressed(KEY_O): v.y += 1.0
	return v
