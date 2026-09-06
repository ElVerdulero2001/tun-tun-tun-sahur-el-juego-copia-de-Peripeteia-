class_name TraversalOpportunities
extends RefCounted

## Salida pura de TraversalDetector.collect() (doc de arquitectura V0.3,
## sección 10). Describe oportunidades físicas del tick actual — nunca
## intención ni decisión: eso es trabajo de TraversalResolver (Fase 1) y de
## TraversalController (fases futuras). ledge/ladder son null cuando no hay
## candidato de ese tipo.

var ledge: LedgeCandidate
var ladder: LadderCandidate


func _init(p_ledge: LedgeCandidate = null, p_ladder: LadderCandidate = null) -> void:
	ledge = p_ledge
	ladder = p_ladder
