class_name HostRaft
extends RigidBody3D

## Balsa del host: un cuerpo rígido que solo simula el host, con un rumbo al
## azar que nadie más puede predecir. Flota a una altura fija sin girar, y
## deriva dentro de una zona alrededor de su lugar en la escena.
##
## En los clientes queda congelada en modo cinemático y la mueve la
## interpolación, con la pose que manda el host en cada snapshot. Como allí es
## un cuerpo cinemático, se coloca al final de cada tick en su pose del tick
## siguiente, igual que una plataforma guionada.

## Id de red de la base. Tiene que ser único y el mismo en todas las máquinas.
@export var base_id := 3
## Mitad del ancho y del largo de la zona por la que deriva, en metros.
@export var zone := Vector2(5, 5)
## Aceleración con la que va hacia su rumbo, en m/s². Con el frenado, la
## rapidez máxima queda cerca de este número en m/s.
@export var push := 2.5
## Cada cuántos segundos elige un rumbo nuevo.
@export var turn_every := 3.0

## Si esta máquina la simula: el host y el modo local. En los clientes, no.
var simulated := true

var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _seconds_to_turn := 0.0
var _rng := RandomNumberGenerator.new()
## Cliente: velocidad que trae la interpolación, la que hereda quien la deja.
var _copy_velocity := Vector3.ZERO

@onready var _visual: Node3D = $Mesh


func _enter_tree() -> void:
	BaseRegistry.add(self)


func _exit_tree() -> void:
	BaseRegistry.remove(self)


func _ready() -> void:
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 1.0
	axis_lock_linear_y = true
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	# No choca con nada: solo sirve de piso para los actores.
	collision_mask = 0
	_home = global_position
	_target = _home
	_rng.randomize()


## Deja de simularla: desde ahora es una copia que mueve la interpolación.
func become_copy() -> void:
	simulated = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true


func _physics_process(delta: float) -> void:
	if not simulated:
		return
	_seconds_to_turn -= delta
	if _seconds_to_turn <= 0.0:
		_seconds_to_turn = turn_every
		_target = _home + Vector3(_rng.randf_range(-zone.x, zone.x), 0.0, _rng.randf_range(-zone.y, zone.y))
	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() > 0.2:
		apply_central_force(to_target.normalized() * push * mass)


## Cliente, al final del tick anterior: la deja en la pose interpolada del
## tick que viene, con la parte visual en la pose que se ve ahora.
func place_copy(next_origin: Vector3, current_origin: Vector3, next_velocity: Vector3) -> void:
	var jumped := global_position.distance_to(next_origin) > 2.0
	global_position = next_origin
	_visual.position = current_origin - next_origin
	_copy_velocity = next_velocity
	if jumped:
		reset_physics_interpolation()


func base_origin() -> Vector3:
	return global_position


func base_velocity() -> Vector3:
	return linear_velocity if simulated else _copy_velocity
