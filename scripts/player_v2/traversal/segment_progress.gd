class_name SegmentProgress
extends RefCounted

## Resultado de avanzar progreso a lo largo de un TraversalSegment,
## resolviendo el cruce a un vecino explícito si corresponde (Parkour V2,
## Fase 6; doc de arquitectura V0.3, sección 10). Shimmy (lateral, dentro de
## HANGING) y escalera (LADDER) comparten esta misma mecánica de avance —
## progreso normalizado [0,1] con transición a neighbour_up/neighbour_down
## cuando se cruza un extremo — así que el cálculo vive una sola vez como
## función estática de TraversalSegment (ver advance_progress()) en vez de
## duplicarse en TraversalController para cada caso.
##
## segment puede terminar siendo distinto del segmento de partida (si el
## desplazamiento cruzó a un vecino); progress siempre queda clampeado a
## [0,1] del segmento final.

var segment: TraversalSegment
var progress: float


func _init(p_segment: TraversalSegment = null, p_progress: float = 0.0) -> void:
	segment = p_segment
	progress = p_progress
