class_name TraversalContext
extends RefCounted

## Contexto completo de arbitraje que recibe TraversalResolver.resolve()
## (doc de arquitectura V0.3, sección 5). Se arma en cada tick a partir de
## intent + snapshot del motor + candidatos del detector; el resolver no
## guarda estado propio entre llamadas.

var state: TraversalState.Value
var intent: TraversalIntent
var motor: MotorSnapshot
var aim_direction: Vector3
var ledge: LedgeCandidate
var ladder: LadderCandidate


func _init(p_state: TraversalState.Value, p_intent: TraversalIntent, p_motor: MotorSnapshot,
		p_aim_direction: Vector3 = Vector3.ZERO, p_ledge: LedgeCandidate = null,
		p_ladder: LadderCandidate = null) -> void:
	state = p_state
	intent = p_intent
	motor = p_motor
	aim_direction = p_aim_direction
	ledge = p_ledge
	ladder = p_ladder
