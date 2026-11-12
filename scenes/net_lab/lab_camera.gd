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
## Con + y − del teclado numérico (acciones camara_acercar y camara_alejar del
## Mapa de entrada), mantenidas, cuánto del recorrido entero avanza por segundo:
## con 1, un segundo va de tercera a primera persona. Desde el 2026-11-12, para
## una PC sin rueda (pedido del usuario; el número lo eligió Claude). Valen
## donde vale la rueda: jugando, sin el menú ni el inventario abiertos.
@export_range(0.1, 5.0, 0.05) var key_zoom_speed := 1.0
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

@export_group("Muerte")
## En primera persona, al morir (desde el 2026-11-05): la cámara cae hasta
## esta altura sobre los pies, en metros, y se ladea este tanto, en grados,
## mientras el cuerpo se desploma (ActorBody.collapse_amount); después vuelve.
## En tercera persona no se mueve: se ve el desplome del cuerpo.
@export_range(0.1, 1.6, 0.05) var death_eye_height := 0.35
@export_range(0.0, 90.0, 1.0) var death_roll_degrees := 70.0

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
## Interfaces que necesitan el mouse libre (el inventario): mientras haya
## alguna, la cámara no lo vuelve a capturar ni gira.
var _mouse_holders := {}

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
	if _mouse_holders.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Una interfaz pide el mouse libre: se suelta y la cámara deja de girar.
func hold_mouse(holder: Object) -> void:
	_mouse_holders[holder.get_instance_id()] = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## La interfaz ya no lo necesita. Si no queda ninguna otra, la cámara lo vuelve
## a tomar (salvo en el menú del laboratorio).
func release_mouse(holder: Object) -> void:
	_mouse_holders.erase(holder.get_instance_id())
	if _mouse_holders.is_empty() and _capture_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _capture_enabled or not _mouse_holders.is_empty():
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
	# El actor puede borrarse (por ejemplo, si el host cierra la sesión). Antes
	# de borrarlo, la red lo saca del árbol: ese cuadro tampoco se lo sigue.
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	# La cámara va a la altura de la cabeza, que depende de la postura. En el
	# suelo, cambiar de postura mueve la cabeza (los pies quedan): la cámara la
	# sigue con suavizado, y agachado bajo un techo queda adentro y no arriba.
	# En el aire, cambiar de postura mueve los pies y la cabeza queda: la
	# cámara cambia de golpe lo mismo que saltaron los pies, y no se mueve. Lo
	# mismo al agarrarse encogido (ver ActorMotor.keeps_head).
	var wanted := head_height
	var actor := target.get_parent() as ActorBody
	if actor != null:
		var standing := actor.stance_height(ActorState.Stance.STANDING)
		wanted = head_height - standing + actor.stance_height(actor.state.stance)
		if _last_stance != -1 and actor.state.stance != _last_stance \
				and ActorMotor.keeps_head(actor.state.mode, _last_stance):
			_head_height = wanted
		_last_stance = actor.state.stance
	_head_height = lerpf(_head_height, wanted, 1.0 - exp(-head_follow_rate * delta))
	# + y − del teclado numérico, como la rueda: + acerca, − aleja. Con el tiempo
	# real, así la cámara lenta no los frena.
	if _capture_enabled and _mouse_holders.is_empty():
		var keys := Input.get_axis(&"camara_acercar", &"camara_alejar")
		if keys != 0.0:
			_wanted_zoom = clampf(_wanted_zoom + keys * key_zoom_speed * delta / maxf(Engine.time_scale, 0.01), 0.0, 1.0)
	_zoom = lerpf(_zoom, _wanted_zoom, 1.0 - exp(-zoom_follow_rate * delta))
	pitch = clampf(pitch, _pitch_min(), _pitch_max())
	# Al morir, en primera persona, la cámara cae al piso y se ladea mientras dura
	# el desplome (es solo dibujo: el mouse y la simulación siguen igual).
	var fall := death_fall_amount()
	global_position = target.get_global_transform_interpolated().origin \
			+ Vector3.UP * lerpf(_head_height, death_eye_height, fall)
	rotation = Vector3(pitch, yaw, deg_to_rad(death_roll_degrees) * fall)
	_place_on_guide()
	# Muy cerca de la cabeza, el cuerpo propio taparía la vista. Cuenta la
	# distancia real, con el resorte: una pared detrás también la acerca.
	target.visible = _spring.get_hit_length() > hide_body_distance


## Cuánto cayó la cámara por una muerte, de 0 a 1: el desplome del cuerpo
## propio, solo en primera persona (pasando a tercera, se va apagando).
func death_fall_amount() -> float:
	var actor := target.get_parent() as ActorBody if is_instance_valid(target) else null
	if actor == null:
		return 0.0
	var first_person := 1.0 - clampf(_spring.spring_length / maxf(hide_body_distance, 0.01), 0.0, 1.0)
	return actor.collapse_amount() * first_person


## Si está en tercera persona: sobre la guía, lo bastante lejos de la cabeza
## como para que se dibuje el cuerpo (sin contar las paredes que acercan el
## resorte). Viaja en el input: el motor lo usa al salir de una escalera.
func third_person() -> bool:
	return _spring.spring_length > hide_body_distance


## La mira: la línea que sale de la cámara por el centro de la pantalla. Empieza
## a la altura de la cabeza, así lo que queda entre la cámara y el personaje
## (en tercera persona) no cuenta. [desde, hacia dónde].
func aim_ray() -> Array:
	var look := -global_basis.z
	var eye := _camera.global_position
	return [eye + look * maxf((global_position - eye).dot(look), 0.0), look]


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
