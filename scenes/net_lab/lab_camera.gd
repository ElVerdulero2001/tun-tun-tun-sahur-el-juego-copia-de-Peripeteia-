class_name LabCamera
extends Node3D

## Cámara de tercera persona mínima para el laboratorio. Es presentación pura:
## a la simulación solo le llega el yaw, como parte del input.
##
## Sigue la posición interpolada del actor y rota con el mouse en _process,
## fuera de la interpolación de física, como recomienda la documentación.

const MOUSE_SENSITIVITY := 0.0025
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
const HEAD_HEIGHT := 1.6

@export var target: Node3D

var yaw := 0.0
var pitch := -0.3
## Mientras está el menú del laboratorio, la cámara no se queda con el mouse.
var _capture_enabled := false


## Empieza a usar el mouse para mirar. La llama el laboratorio al salir del menú.
func start_capture() -> void:
	_capture_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _capture_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	# El actor puede borrarse (por ejemplo, si el host cierra la sesión).
	if not is_instance_valid(target):
		return
	global_position = target.get_global_transform_interpolated().origin + Vector3.UP * HEAD_HEIGHT
	rotation = Vector3(pitch, yaw, 0.0)
