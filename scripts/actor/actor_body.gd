class_name ActorBody
extends CharacterBody3D

## Cuerpo físico de un actor. Solo lo mueve ActorMotor, y solo dentro de un
## tick. Los indicadores de Godot (is_on_floor() y compañía) se copian al
## estado del actor apenas termina cada movimiento: el resto del juego lee el
## estado, nunca los indicadores.

## Distancia del snap manual al restaurar un estado apoyado: solo tiene que
## cubrir la fracción de milímetro que agrega la cuantización.
const RESTORE_SNAP_LENGTH := 0.01
## Cuánto puede empujar la geometría a una pose restaurada sin que cuente como
## metida adentro. Una pose válida se mueve menos de un milímetro.
const POSE_TOLERANCE := 0.01
## Presentación: después de un salto del cuerpo (una corrección), el desvío
## visual se reduce a la mitad cada este tiempo; en unos 100 ms ya no se nota.
const CORRECTION_HALF_LIFE := 0.025
## Saltos más grandes que esto no se suavizan: se ven como un salto.
const MAX_SMOOTHED_JUMP := 1.5

## Desvío del visual respecto del cuerpo. Es solo presentación: la simulación
## no lo lee nunca.
var visual_offset := Vector3.ZERO

## Estado del actor. Solo lo escriben ActorMotor y la red al restaurar.
var state := ActorState.new()
## Peer dueño del actor: el que manda su input. El host es 1.
var owner_peer_id := 1
## Falso hasta que el reloj ubica el cuerpo en su estado por primera vez.
var placed := false
## Si esta máquina lo simula. El host simula a todos; el cliente, solo al
## propio (predicción), y a los demás los muestra como los manda el host.
var simulated := true

@onready var _visual: Node3D = $Visual


func _ready() -> void:
	# La base (plataformas) la maneja la arquitectura y no Godot: Godot lee la
	# velocidad de plataforma del presente, y eso falla al repetir ticks.
	platform_floor_layers = 0
	platform_wall_layers = 0
	platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING
	floor_block_on_wall = true
	floor_stop_on_slope = true


## Mueve el cuerpo con move_and_slide() avanzando exactamente dt.
## move_and_slide() toma el delta del frame de física por su cuenta; el factor
## lo compensa cuando dt es otro (escala de tiempo, ticks repetidos).
func slide(state: ActorState, snap_length: float, dt: float) -> void:
	var factor := dt / get_physics_process_delta_time()
	floor_snap_length = snap_length
	velocity = state.velocity * factor
	move_and_slide()
	state.velocity = velocity / factor


## Pone el cuerpo en el estado dado, por ejemplo al restaurar una corrección.
## Además sincroniza el estado interno de piso de Godot: move_and_slide() usa
## el resultado del llamado anterior para decidir el snap, y después de
## restaurar ese dato quedó viejo.
##
## Devuelve si el estado entra en este mundo: que la geometría no tenga que
## empujar el cuerpo para afuera y que, si dice estar apoyado, haya piso. Con
## eso el host valida la afirmación de un cliente antes de adoptarla.
##
## Sobre una base, la posición del estado es relativa: el cuerpo va a la pose
## que la base tiene ahora (al repetir ticks, eso es trabajar en coordenadas
## de la base).
func apply_state(state: ActorState) -> bool:
	var world := BaseRegistry.world_position(state)
	global_position = world
	# Un movimiento de velocidad cero refresca los indicadores según el
	# contacto real; con el snap en 0 no arrastra el cuerpo hacia el piso.
	floor_snap_length = 0.0
	velocity = Vector3.ZERO
	move_and_slide()
	var fits := global_position.distance_to(world) <= POSE_TOLERANCE
	# Apoyado, el cuerpo queda a la distancia del margen, y al cuantizar puede
	# quedar una fracción de milímetro más arriba: fuera del margen, el
	# movimiento de arriba no ve el piso. El snap manual lo encuentra igual.
	if state.on_floor and not is_on_floor():
		floor_snap_length = RESTORE_SNAP_LENGTH
		apply_floor_snap()
		fits = fits and is_on_floor()
	global_position = world
	velocity = state.velocity
	present(state)
	return fits


## Presentación mínima: orienta el visual. No escribe nada en la simulación.
func present(state: ActorState) -> void:
	_visual.rotation.y = state.facing_yaw


## Dónde se ve el actor: el cuerpo más el desvío visual.
func seen_position() -> Vector3:
	return global_position + visual_offset


## El cuerpo acaba de saltar por una corrección y antes se lo veía en `seen`:
## el visual arranca desde ahí y llega solo a la posición nueva. Un salto más
## grande que MAX_SMOOTHED_JUMP se muestra tal cual.
func smooth_from(seen: Vector3) -> void:
	visual_offset = seen - global_position
	if visual_offset.length() > MAX_SMOOTHED_JUMP:
		teleported()
		return
	_visual.position = visual_offset


## Fija el desvío visual tal cual, sin que decaiga solo: lo va moviendo quien
## lo pide. Va en el tick, como decay_visual_offset().
func set_visual_offset(offset: Vector3) -> void:
	visual_offset = offset
	_visual.position = offset


## Una vez por tick, en el tick: el desvío decae hacia cero. Va en el tick
## para que la interpolación de física lo suavice entre ticks.
func decay_visual_offset(dt: float) -> void:
	if visual_offset == Vector3.ZERO:
		return
	visual_offset *= pow(0.5, dt / CORRECTION_HALF_LIFE)
	if visual_offset.length_squared() < 1e-8:
		visual_offset = Vector3.ZERO
	_visual.position = visual_offset


## El actor apareció en otro lugar (reaparición, teleport): sin desvío y sin
## interpolar desde la posición vieja.
func teleported() -> void:
	visual_offset = Vector3.ZERO
	_visual.position = Vector3.ZERO
	reset_physics_interpolation()


## Nodo que se ve y que sigue la cámara: incluye el desvío visual.
func visual_root() -> Node3D:
	return _visual
