class_name LabCamera
extends Node3D

## Cámara del laboratorio, de tercera a primera persona. Es presentación pura:
## a la simulación solo le llega el yaw, como parte del input.
##
## Sigue la posición interpolada del actor y rota con el mouse en _process,
## fuera de la interpolación de física, como recomienda la documentación.
##
## La rueda del mouse mueve la cámara sobre la guía, el Path3D hijo (Guide): su
## primer punto es primera persona, en la cabeza, y el último, la tercera
## persona más lejana. La guía gira con la cámara, así que se dibuja como se ve
## detrás de la cabeza; se edita en el editor moviendo sus puntos. Un resorte
## (SpringArm) va de la cabeza al punto de la guía y acerca la cámara si hay
## una pared en el medio.

@export_group("Mouse")
@export var mouse_sensitivity := 0.0025
## Cuánto puede mirar para abajo y para arriba en tercera persona.
@export_range(-89.0, 0.0, 0.1, "radians_as_degrees") var pitch_min := -1.2
@export_range(0.0, 89.0, 0.1, "radians_as_degrees") var pitch_max := 0.6
## Lo mismo en primera persona. En el medio de la guía, los límites van
## pasando de unos a otros.
@export_range(-89.0, 0.0, 0.1, "radians_as_degrees") var first_person_pitch_min := deg_to_rad(-85.0)
@export_range(0.0, 89.0, 0.1, "radians_as_degrees") var first_person_pitch_max := deg_to_rad(85.0)

@export_group("Rueda")
## Cuánto avanza la cámara sobre la guía por cada paso de la rueda, como parte
## del recorrido entero (de 0 a 1): con 0,1, diez pasos van de una punta a la otra.
@export_range(0.01, 1.0, 0.01) var zoom_step := 0.1
## Qué tan rápido llega la cámara a donde la pidió la rueda, por segundo.
@export var zoom_follow_rate := 12.0
## Dónde arranca sobre la guía: 0 es primera persona, 1 la otra punta.
@export_range(0.0, 1.0, 0.01) var start_zoom := 1.0
## Con la cámara más cerca que esto de la cabeza, en metros, no se dibuja el
## cuerpo propio (sí las manos, cuando cuelga).
@export var hide_body_distance := 0.5

@export_group("Cabeza")
## Altura de la cabeza parado; agachado baja lo mismo que la forma.
@export var head_height := 1.6
## Qué tan rápido sigue la altura de la cabeza a la postura, por segundo.
@export var head_follow_rate := 12.0

@export var target: Node3D

var yaw := 0.0
var pitch := -0.3
var _head_height := 1.6
var _last_stance := -1
## Dónde está la cámara sobre la guía y dónde la pidió la rueda (0 a 1).
var _zoom := 1.0
var _wanted_zoom := 1.0
## Mientras está el menú del laboratorio, la cámara no se queda con el mouse.
var _capture_enabled := false

@onready var _guide: Path3D = $Guide
@onready var _spring: SpringArm3D = $SpringArm
@onready var _camera: Camera3D = $SpringArm/Camera


func _ready() -> void:
	_head_height = head_height
	_zoom = start_zoom
	_wanted_zoom = start_zoom


## Empieza a usar el mouse para mirar. La llama el laboratorio al salir del menú.
func start_capture() -> void:
	_capture_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _capture_enabled:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, _pitch_min(), _pitch_max())
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if captured:
			# Rueda para adelante acerca; factor es cuánto giró (en un mouse
			# común, 1 por paso; en un touchpad, fracciones).
			var steps: float = event.factor if event.factor > 0.0 else 1.0
			var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_wanted_zoom = clampf(_wanted_zoom + direction * zoom_step * steps, 0.0, 1.0)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	# El actor puede borrarse (por ejemplo, si el host cierra la sesión).
	if not is_instance_valid(target):
		return
	# La cámara va a la altura de la cabeza, que depende de la postura. En el
	# suelo, cambiar de postura mueve la cabeza (los pies quedan): la cámara la
	# sigue con suavizado, y agachado bajo un techo queda adentro y no arriba.
	# En el aire, cambiar de postura mueve los pies y la cabeza queda: la
	# cámara cambia de golpe lo mismo que saltaron los pies, y no se mueve.
	var wanted := head_height
	var actor := target.get_parent() as ActorBody
	if actor != null:
		var standing := actor.stance_height(ActorState.Stance.STANDING)
		wanted = head_height - standing + actor.stance_height(actor.state.stance)
		if _last_stance != -1 and actor.state.stance != _last_stance and actor.state.mode == ActorState.Mode.AIR:
			_head_height = wanted
		_last_stance = actor.state.stance
	_head_height = lerpf(_head_height, wanted, 1.0 - exp(-head_follow_rate * delta))
	_zoom = lerpf(_zoom, _wanted_zoom, 1.0 - exp(-zoom_follow_rate * delta))
	pitch = clampf(pitch, _pitch_min(), _pitch_max())
	global_position = target.get_global_transform_interpolated().origin + Vector3.UP * _head_height
	rotation = Vector3(pitch, yaw, 0.0)
	_place_on_guide()
	# Muy cerca de la cabeza, el cuerpo propio taparía la vista. Cuenta la
	# distancia real, con el resorte: una pared detrás también la acerca.
	target.visible = _spring.get_hit_length() > hide_body_distance


## Pone el resorte apuntando al punto de la guía que corresponde a _zoom, y la
## cámara mirando hacia donde mira el rig, aunque el resorte vaya en diagonal.
func _place_on_guide() -> void:
	var curve := _guide.curve
	var point := Vector3.ZERO
	if curve != null and curve.point_count > 0:
		point = _guide.transform * curve.sample_baked(_zoom * curve.get_baked_length())
	var distance := point.length()
	if distance > 0.001:
		var back := point / distance
		var up := Vector3.UP if absf(back.y) < 0.99 else Vector3.BACK
		# El resorte se estira hacia su +Z: looking_at apunta su -Z para el otro lado.
		_spring.transform = Transform3D(Basis.looking_at(-back, up), Vector3.ZERO)
	_spring.spring_length = distance
	_camera.global_basis = global_basis


func _pitch_min() -> float:
	return lerpf(first_person_pitch_min, pitch_min, _zoom)


func _pitch_max() -> float:
	return lerpf(first_person_pitch_max, pitch_max, _zoom)
