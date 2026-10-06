class_name ScriptedPlatform
extends AnimatableBody3D

## Plataforma guionada: su posición es función del tick del mundo, así que da
## igual en todas las máquinas sin mandar nada por red. Va desde su lugar en la
## escena hasta ese lugar más `travel` y vuelve, con arranque y frenada suaves.
##
## Jolt mueve los cuerpos cinemáticos recién en el paso de física: lo que se
## coloca durante el tick T, las consultas lo ven en el tick T+1. Por eso el
## reloj la coloca al final de cada tick en su pose del tick siguiente, y la
## parte visual se corre un tick hacia atrás para no adelantarse a lo que lleva.
##
## En un cliente, la parte visual además puede ir más atrás (`visual_lag`):
## lejos del jugador propio se la dibuja en el mismo pasado que a los demás
## jugadores, así quien salta de ella o se sube se ve donde corresponde.

## Id de red de la base. Tiene que ser único y el mismo en todas las máquinas.
@export var base_id := 1
## Desplazamiento hasta el otro extremo del recorrido, en metros.
@export var travel := Vector3(8, 0, 0)
## Segundos de una ida y vuelta.
@export var period := 8.0

var _start := Vector3.ZERO
## Cuántos ticks más atrás que su pose se la dibuja. Solo lo cambia un
## cliente, en cada tick; no toca la física.
var visual_lag := 0.0
## Tick para el que está colocada: el que ven las consultas ahora.
var _tick := 0

@onready var _visual: Node3D = $Mesh
@onready var _box: BoxShape3D = ($Shape as CollisionShape3D).shape


func _enter_tree() -> void:
	BaseRegistry.add(self)


func _exit_tree() -> void:
	BaseRegistry.remove(self)


func _ready() -> void:
	sync_to_physics = false
	_start = global_position


## Posición en un tick del mundo. Entre dos ticks también vale, para dibujarla.
func pose_at(tick: float) -> Vector3:
	var turns := tick * SimClock.TICK_DT / period
	return _start + travel * (0.5 - 0.5 * cos(TAU * turns))


## Al final del tick anterior: la deja colocada para `tick`.
func prepare_tick(tick: int) -> void:
	var jumped := absi(tick - _tick) > 1
	_tick = tick
	global_position = pose_at(tick)
	_visual.position = pose_at(tick - 1 - visual_lag) - pose_at(tick)
	if jumped:
		reset_physics_interpolation()


func base_origin() -> Vector3:
	return global_position


func base_velocity() -> Vector3:
	return (pose_at(_tick + 1) - pose_at(_tick)) / SimClock.TICK_DT


## Dónde se la ve después de este tick.
func visual_origin() -> Vector3:
	return pose_at(_tick - visual_lag)


func visual_velocity() -> Vector3:
	return (pose_at(_tick + 1 - visual_lag) - pose_at(_tick - visual_lag)) / SimClock.TICK_DT


## Distancia de un punto a la caja de la plataforma tal como la ven las
## consultas, en metros; cero si está adentro.
func distance_to(point: Vector3) -> float:
	var outside := ((point - global_position).abs() - _box.size * 0.5).max(Vector3.ZERO)
	return outside.length()
