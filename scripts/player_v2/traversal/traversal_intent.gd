class_name TraversalIntent
extends RefCounted

## Intención semántica del jugador para un tick de traversal (doc de
## arquitectura V0.3, sección 5). No es el InputEvent crudo: ya viene
## traducido a ejes y flags estables para que el resolver sea testeable sin
## el árbol de escena.
##
## Convención de move_axis: la misma que Input.get_vector("move_left",
## "move_right", "move_forward", "move_back") ya usada en player_v2.gd —
## eje Y negativo es "adelante", positivo es "atrás". Quien construya el
## intent (hoy nadie; en Fase 2/4 será PlayerMotor/TraversalController)
## debe respetar este signo para que TraversalResolver interprete bien el
## avance frontal.

var move_axis: Vector2
var jump_pressed: bool
var crouch_pressed: bool
var run_pressed: bool
var buffered_jump: bool


func _init(p_move_axis: Vector2 = Vector2.ZERO, p_jump_pressed: bool = false,
		p_crouch_pressed: bool = false, p_run_pressed: bool = false,
		p_buffered_jump: bool = false) -> void:
	move_axis = p_move_axis
	jump_pressed = p_jump_pressed
	crouch_pressed = p_crouch_pressed
	run_pressed = p_run_pressed
	buffered_jump = p_buffered_jump
