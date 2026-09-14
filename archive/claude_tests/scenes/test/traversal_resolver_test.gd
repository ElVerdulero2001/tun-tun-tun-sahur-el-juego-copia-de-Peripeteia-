extends Node

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Parkour V2 · Fase 1.
##
## Tests de tabla para TraversalResolver (doc de arquitectura V0.3, sección 7).
## No usa el árbol de escena: TraversalResolver es una clase pura, así que
## cada caso arma su propio TraversalContext y compara la decisión esperada.
## Cubre las reglas de la sección 7 y las regresiones de la sección 12 que
## le corresponden al resolver (prioridad de estado activo, escalera exige
## intención explícita, conflicto borde/escalera).
##
## Plan de separación HANGING/DIRECT_MANTLE: HANGING pasó a ser
## EXCLUSIVAMENTE rescate aéreo — la rama "en el piso, avanzando" que este
## archivo probaba antes ya no existe en el resolver (ver
## TraversalResolver._hang_valido()). DIRECT_MANTLE NO se prueba acá: su
## decisión vive en TraversalController._intentar_direct_mantle_o_rescate(),
## que necesita detector.is_pose_clear() sobre la escena real — algo que
## este arnés, deliberadamente sin árbol de escena, no puede ejercitar. Ver
## traversal_controller_test.gd para esos casos.

var _fallos := 0
var _checks := 0

# Placeholder de LadderCandidate.segment: es un TraversalSegment (Node, no
# RefCounted como el resto de los fixtures), así que hay que liberarlo a
# mano al terminar. Nunca entra al árbol de escena, así que su _ready()
# (que valida markers) no llega a correr — no hace falta configurarlo.
var _segmento_placeholder: TraversalSegment


func _ready() -> void:
	print("\n===== PARKOUR V2 · FASE 1 · TraversalResolver (tests de tabla) =====")

	for caso in _casos():
		var decision: TraversalDecision.Value = TraversalResolver.resolve(caso.context)
		_check(decision == caso.esperado, "%s -> esperado %s, obtuvo %s" % [
			caso.nombre,
			TraversalDecision.Value.keys()[caso.esperado],
			TraversalDecision.Value.keys()[decision],
		])

	_segmento_placeholder.free()

	print("=============================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: TraversalResolver OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	# quit() antes que assert(): un assert fallido corta esta función y
	# nunca llegaría a quit(), dejando el proceso headless colgado.
	get_tree().quit(_fallos)
	assert(_fallos == 0, "TraversalResolver no cumple las reglas de la sección 7")


func _casos() -> Array:
	var quieto := TraversalIntent.new(Vector2.ZERO)
	var moviendose := TraversalIntent.new(Vector2.UP)        # adelante (y < 0)
	var retrocediendo := TraversalIntent.new(Vector2.DOWN)   # atrás (y > 0)
	var lateral := TraversalIntent.new(Vector2.RIGHT)        # strafe puro (y == 0)

	var ledge_valido_alto := LedgeCandidate.new(Vector3.ZERO, Vector3.UP, Vector3.ZERO, 0.9, true)
	var ledge_valido_bajo_score := LedgeCandidate.new(Vector3.ZERO, Vector3.UP, Vector3.ZERO, 0.2, true)
	var ledge_score_limite := LedgeCandidate.new(Vector3.ZERO, Vector3.UP, Vector3.ZERO,
		TraversalResolver.LEDGE_SCORE_MINIMO, true)
	var ledge_bajo_el_limite := LedgeCandidate.new(Vector3.ZERO, Vector3.UP, Vector3.ZERO,
		TraversalResolver.LEDGE_SCORE_MINIMO - 0.01, true)

	# Placeholder no nulo: una LadderCandidate válida siempre trae un segmento
	# real (invariante documentada en LadderCandidate) — ningún fixture de
	# este archivo construye una candidata "válida" fuera de ese contrato.
	_segmento_placeholder = TraversalSegment.new()
	var ladder_valido_alineado := LadderCandidate.new(_segmento_placeholder, 0.0, 0.9, true)
	var ladder_valido_desalineado := LadderCandidate.new(_segmento_placeholder, 0.0, 0.2, true)
	var ladder_alineacion_limite := LadderCandidate.new(_segmento_placeholder, 0.0,
		TraversalResolver.LADDER_CONFIANZA_MINIMA, true)
	var ladder_bajo_el_limite := LadderCandidate.new(_segmento_placeholder, 0.0,
		TraversalResolver.LADDER_CONFIANZA_MINIMA - 0.01, true)

	var en_piso := MotorSnapshot.new(true)
	var en_aire := MotorSnapshot.new(false)

	return [
		{
			"nombre": "estado activo (HANGING) ignora candidatos válidos",
			"context": TraversalContext.new(TraversalState.Value.HANGING, moviendose, en_piso,
				Vector3.ZERO, ledge_valido_alto, ladder_valido_alineado),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "FREE sin candidatos",
			"context": TraversalContext.new(TraversalState.Value.FREE, moviendose, en_piso,
				Vector3.ZERO, null, null),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "borde válido en el piso sin movimiento no es automático",
			"context": TraversalContext.new(TraversalState.Value.FREE, quieto, en_piso,
				Vector3.ZERO, ledge_valido_alto, null),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "borde válido en el piso avanzando hacia él NO engancha (HANGING es solo rescate aéreo; DIRECT_MANTLE se decide en TraversalController, no acá)",
			"context": TraversalContext.new(TraversalState.Value.FREE, moviendose, en_piso,
				Vector3.ZERO, ledge_valido_alto, null),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "borde válido cayendo es automático sin input",
			"context": TraversalContext.new(TraversalState.Value.FREE, quieto, en_aire,
				Vector3.ZERO, ledge_valido_alto, null),
			"esperado": TraversalDecision.Value.ACQUIRE_LEDGE,
		},
		{
			"nombre": "borde con score bajo el mínimo se descarta",
			"context": TraversalContext.new(TraversalState.Value.FREE, moviendose, en_aire,
				Vector3.ZERO, ledge_valido_bajo_score, null),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "borde en el piso retrocediendo no engancha (HANGING nunca arranca desde el piso)",
			"context": TraversalContext.new(TraversalState.Value.FREE, retrocediendo, en_piso,
				Vector3.ZERO, ledge_valido_alto, null),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "borde en el piso con strafe puro no engancha (HANGING nunca arranca desde el piso)",
			"context": TraversalContext.new(TraversalState.Value.FREE, lateral, en_piso,
				Vector3.ZERO, ledge_valido_alto, null),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "frontera: score de borde exactamente en el mínimo, en el aire, entra",
			"context": TraversalContext.new(TraversalState.Value.FREE, quieto, en_aire,
				Vector3.ZERO, ledge_score_limite, null),
			"esperado": TraversalDecision.Value.ACQUIRE_LEDGE,
		},
		{
			"nombre": "frontera: score de borde apenas debajo del mínimo no entra",
			"context": TraversalContext.new(TraversalState.Value.FREE, quieto, en_aire,
				Vector3.ZERO, ledge_bajo_el_limite, null),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "escalera alineada y con movimiento entra",
			"context": TraversalContext.new(TraversalState.Value.FREE, moviendose, en_piso,
				Vector3.ZERO, null, ladder_valido_alineado),
			"esperado": TraversalDecision.Value.ENTER_LADDER,
		},
		{
			"nombre": "escalera alineada SIN movimiento no entra (solo cercanía no basta)",
			"context": TraversalContext.new(TraversalState.Value.FREE, quieto, en_piso,
				Vector3.ZERO, null, ladder_valido_alineado),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "escalera alineada retrocediendo también entra (a diferencia del borde, no exige frontal)",
			"context": TraversalContext.new(TraversalState.Value.FREE, retrocediendo, en_piso,
				Vector3.ZERO, null, ladder_valido_alineado),
			"esperado": TraversalDecision.Value.ENTER_LADDER,
		},
		{
			"nombre": "escalera alineada con strafe puro también entra (a diferencia del borde, no exige frontal)",
			"context": TraversalContext.new(TraversalState.Value.FREE, lateral, en_piso,
				Vector3.ZERO, null, ladder_valido_alineado),
			"esperado": TraversalDecision.Value.ENTER_LADDER,
		},
		{
			"nombre": "escalera desalineada por debajo del mínimo se descarta",
			"context": TraversalContext.new(TraversalState.Value.FREE, moviendose, en_piso,
				Vector3.ZERO, null, ladder_valido_desalineado),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "frontera: alineación de escalera exactamente en el mínimo, con movimiento, entra",
			"context": TraversalContext.new(TraversalState.Value.FREE, moviendose, en_piso,
				Vector3.ZERO, null, ladder_alineacion_limite),
			"esperado": TraversalDecision.Value.ENTER_LADDER,
		},
		{
			"nombre": "frontera: alineación de escalera apenas debajo del mínimo no entra",
			"context": TraversalContext.new(TraversalState.Value.FREE, moviendose, en_piso,
				Vector3.ZERO, null, ladder_bajo_el_limite),
			"esperado": TraversalDecision.Value.NONE,
		},
		{
			"nombre": "conflicto borde/escalera: la escalera gana con confianza suficiente",
			"context": TraversalContext.new(TraversalState.Value.FREE, moviendose, en_piso,
				Vector3.ZERO, ledge_valido_alto, ladder_valido_alineado),
			"esperado": TraversalDecision.Value.ENTER_LADDER,
		},
		{
			"nombre": "conflicto borde/escalera: escalera sin confianza cae a borde",
			"context": TraversalContext.new(TraversalState.Value.FREE, moviendose, en_aire,
				Vector3.ZERO, ledge_valido_alto, ladder_valido_desalineado),
			"esperado": TraversalDecision.Value.ACQUIRE_LEDGE,
		},
	]


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
