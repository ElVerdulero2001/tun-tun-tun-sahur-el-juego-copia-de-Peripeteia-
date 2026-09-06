class_name LadderCandidate
extends RefCounted

## Oportunidad de entrar a una escalera (u otro TraversalSegment), producida
## por TraversalDetector.collect() (doc de arquitectura V0.3, sección 5).
## approach_alignment mide qué tan alineada está la aproximación del jugador
## con el segmento; el resolver la usa para exigir intención explícita, no
## solo cercanía (sección 7).
##
## `segment` tipado como TraversalSegment desde la Fase 3 (Detector): una
## escalera V2 se reconoce por contrato directo con TraversalSegment, nunca
## por nombre de nodo, grupo o cercanía sin contrato (sección 10).
##
## Invariante: is_valid == true implica segment != null. Una oportunidad
## "válida" sin segmento detrás no la produce ningún detector real; nadie
## fuera de TraversalDetector debería construir una así. Como en el resto
## del repo (ver contrato D8 de ItemInstance), esto se documenta y se cubre
## con tests — GDScript no puede imponerlo en runtime de forma barata.

var segment: TraversalSegment
var initial_progress: float
var approach_alignment: float
var is_valid: bool


func _init(p_segment: TraversalSegment = null, p_initial_progress: float = 0.0,
		p_approach_alignment: float = 0.0, p_is_valid: bool = false) -> void:
	segment = p_segment
	initial_progress = p_initial_progress
	approach_alignment = p_approach_alignment
	is_valid = p_is_valid
