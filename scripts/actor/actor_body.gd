class_name ActorBody
extends CharacterBody3D

## Cuerpo físico de un actor. Solo lo mueve ActorMotor, y solo dentro de un
## tick. Los indicadores de Godot (is_on_floor() y compañía) se copian al
## estado del actor apenas termina cada movimiento: el resto del juego lee el
## estado, nunca los indicadores.

## Distancia del snap manual al restaurar un estado apoyado: solo tiene que
## cubrir la fracción de milímetro que agrega la cuantización.
const RESTORE_SNAP_LENGTH := 0.01

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
func apply_state(state: ActorState) -> void:
	global_position = state.position
	# Un movimiento de velocidad cero refresca los indicadores según el
	# contacto real; con el snap en 0 no arrastra el cuerpo hacia el piso.
	floor_snap_length = 0.0
	velocity = Vector3.ZERO
	move_and_slide()
	# Apoyado, el cuerpo queda a la distancia del margen, y al cuantizar puede
	# quedar una fracción de milímetro más arriba: fuera del margen, el
	# movimiento de arriba no ve el piso. El snap manual lo encuentra igual.
	if state.on_floor and not is_on_floor():
		floor_snap_length = RESTORE_SNAP_LENGTH
		apply_floor_snap()
	global_position = state.position
	velocity = state.velocity
	present(state)


## Presentación mínima: orienta el visual. No escribe nada en la simulación.
func present(state: ActorState) -> void:
	_visual.rotation.y = state.facing_yaw
