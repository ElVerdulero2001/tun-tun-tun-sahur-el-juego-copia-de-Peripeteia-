class_name LedgeCandidate
extends RefCounted

## Oportunidad de agarrarse a un borde, producida por TraversalDetector.collect()
## (doc de arquitectura V0.3, sección 5). is_valid ya resume la elegibilidad
## geométrica (aire, distancia, orientación, clearance); el resolver no
## vuelve a mirar geometría cruda, solo combina esto con intención.
##
## segment (Fase 6, sección 10): TraversalSegment de tipo LEDGE asociado a
## este borde, si el collider detectado lo tiene — nulo para un borde
## "simple" sin recorrido lateral autorizado. Igual que LadderCandidate.segment
## desde Fase 3, es opcional acá: a diferencia de esa, is_valid == true NO
## implica segment != null (la mayoría de los bordes no tienen shimmy).

var edge_position: Vector3
var wall_normal: Vector3
var landing_position: Vector3
var score: float
var is_valid: bool
var segment: TraversalSegment


func _init(p_edge_position: Vector3 = Vector3.ZERO, p_wall_normal: Vector3 = Vector3.ZERO,
		p_landing_position: Vector3 = Vector3.ZERO, p_score: float = 0.0,
		p_is_valid: bool = false, p_segment: TraversalSegment = null) -> void:
	edge_position = p_edge_position
	wall_normal = p_wall_normal
	landing_position = p_landing_position
	score = p_score
	is_valid = p_is_valid
	segment = p_segment
