class_name TraversalResolver
extends RefCounted

## Arbitra TraversalContext -> TraversalDecision (doc de arquitectura V0.3,
## sección 7).
##
## Clase pura: no consulta la escena, no hace raycasts, no mueve nada. Solo
## arbitra entradas ambiguas mientras el estado es FREE — dentro de un estado
## activo (HANGING, MANTLING, LADDER, ACQUIRE_LEDGE) las transiciones son
## lógica directa de TraversalController y no pasan por acá (sección 5).
##
## Los umbrales de abajo son PROVISIONALES (sección 14, pendientes de
## calibración de feel): la arquitectura no depende de sus valores exactos.

const LADDER_CONFIANZA_MINIMA := 0.6
const LEDGE_SCORE_MINIMO := 0.5


## Único punto de entrada. Devuelve NONE si el estado no es FREE: un estado
## activo tiene prioridad y ninguna entrada nueva lo interrumpe (sección 7).
static func resolve(context: TraversalContext) -> TraversalDecision.Value:
	if context.state != TraversalState.Value.FREE:
		return TraversalDecision.Value.NONE

	if _escalera_valida(context):
		return TraversalDecision.Value.ENTER_LADDER
	if _borde_valido(context):
		return TraversalDecision.Value.ACQUIRE_LEDGE
	return TraversalDecision.Value.NONE


## La escalera exige intención explícita y confianza suficiente: la sola
## cercanía no basta, hace falta aproximación y alineación compatibles
## (sección 7). "Intención explícita" acá es solo "el jugador está dando
## input de movimiento" en cualquier dirección — approach_alignment ya la
## calcula el detector a partir de geometría real (posición, segmento), así
## que el resolver no le suma además la exigencia de que sea frontal: el
## documento no la pide para escaleras, a diferencia del borde.
## Al exigir esto en su propia validación, "gana" el conflicto borde/escalera
## solo cuando de verdad corresponde; si no, cae a _borde_valido (sección 7).
static func _escalera_valida(context: TraversalContext) -> bool:
	var ladder := context.ladder
	if ladder == null or not ladder.is_valid:
		return false
	if ladder.approach_alignment < LADDER_CONFIANZA_MINIMA:
		return false
	return _hay_intencion_de_movimiento(context.intent)


## El borde exige elegibilidad geométrica (ya resuelta en is_valid/score) más
## una intención compatible: automático al caer, o al avanzar DE FRENTE hacia
## el borde si el jugador está en el piso (sección 8: "Automático solo al
## caer o avanzar hacia un borde altamente válido"). A diferencia de la
## escalera, acá sí se exige que el input sea frontal: retroceder o strafear
## cerca de un borde válido no debe engancharlo por accidente.
static func _borde_valido(context: TraversalContext) -> bool:
	var ledge := context.ledge
	if ledge == null or not ledge.is_valid:
		return false
	if ledge.score < LEDGE_SCORE_MINIMO:
		return false
	if not context.motor.is_grounded:
		return true
	return _avanza_de_frente(context.intent)


## Intención de movimiento en cualquier dirección (para escalera).
static func _hay_intencion_de_movimiento(intent: TraversalIntent) -> bool:
	return intent != null and intent.move_axis.length() > 0.0


## Avance específicamente frontal (para borde), según la convención de signo
## documentada en TraversalIntent.move_axis (Y negativo = adelante).
static func _avanza_de_frente(intent: TraversalIntent) -> bool:
	return intent != null and intent.move_axis.y < 0.0
