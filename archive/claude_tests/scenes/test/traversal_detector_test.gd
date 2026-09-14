extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Parkour V2 · Fase 3.
##
## Harness físico independiente para TraversalDetector y TraversalSegment.
## Ningún caso depende de Input ni de TraversalController: el "input" acá es
## reposicionar/reorientar ProbeBody a mano y construir un MotorSnapshot
## directamente. Cada zona de la escena (separadas por X) es geometría fija
## dedicada a un solo caso, para no tener que reconstruir nada entre tests.

@onready var probe: CharacterBody3D = $ProbeBody
@onready var detector: TraversalDetector = $ProbeBody/Detector
@onready var escalera_valida: TraversalSegment = $EscaleraValida
@onready var segmento_inferior: TraversalSegment = $SegmentoInferior
@onready var segmento_superior: TraversalSegment = $SegmentoSuperior

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== PARKOUR V2 · FASE 3 · TraversalDetector + TraversalSegment =====")

	_test_pasividad()
	_test_borde_valido()
	_test_borde_sin_pared()
	_test_borde_pared_inclinada()
	_test_borde_clearance_bloqueado()
	_test_borde_altura_insuficiente()
	_test_escalera_valida()
	_test_ladder_candidate_siempre_tiene_segmento()
	_test_segmento_progreso_y_direccion()
	_test_segmento_vecinos()
	_test_collision_mask_afecta_deteccion()

	print("=============================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: TraversalDetector OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	get_tree().quit(_fallos)
	assert(_fallos == 0, "TraversalDetector no cumple el contrato de la Fase 3")


# ── Helpers ──────────────────────────────────────────────────────────
func _ubicar(pos: Vector3, mask: int = 1) -> void:
	probe.global_position = pos
	probe.global_rotation = Vector3.ZERO
	probe.velocity = Vector3.ZERO
	probe.collision_mask = mask


func _snapshot(velocidad: Vector3 = Vector3.ZERO) -> MotorSnapshot:
	return MotorSnapshot.new(true, velocidad, MotorSnapshot.Stance.STANDING, true)


# ── Pasividad ────────────────────────────────────────────────────────
func _test_pasividad() -> void:
	_ubicar(Vector3(0, 0, 0))
	var transform_antes := probe.global_transform
	var velocity_antes := probe.velocity

	var oportunidades := detector.collect(_snapshot(Vector3(0, 0, -2.0)))

	_check(oportunidades.ledge != null, "pasividad: de paso, hay un borde válido delante (setup correcto)")
	_check(probe.global_transform.is_equal_approx(transform_antes),
		"collect() no cambia global_transform de probe_body, incluso con candidato válido")
	_check(probe.velocity.is_equal_approx(velocity_antes),
		"collect() no cambia velocity de probe_body, incluso con candidato válido")


# ── Borde ────────────────────────────────────────────────────────────
func _test_borde_valido() -> void:
	_ubicar(Vector3(0, 0, 0))
	var oportunidades := detector.collect(_snapshot(Vector3(0, 0, -2.0)))
	var ledge := oportunidades.ledge

	_check(ledge != null, "borde válido: se detecta un candidato")
	if ledge == null:
		return
	_check(ledge.is_valid, "borde válido: is_valid true")
	_check(absf(ledge.edge_position.y - 1.0) < 0.1,
		"borde válido: altura del borde ~1.0 (obtuvo %.3f)" % ledge.edge_position.y)
	_check(ledge.wall_normal.dot(Vector3.BACK) > 0.9,
		"borde válido: normal de la pared apunta hacia el probe (%.3f)" % ledge.wall_normal.dot(Vector3.BACK))
	_check(ledge.landing_position.y > ledge.edge_position.y,
		"borde válido: landing_position está por encima del borde")
	_check(ledge.score > 0.5, "borde válido: score razonablemente alto de frente (%.3f)" % ledge.score)
	_check(absf(ledge.altura_relativa - 1.0) < 0.1,
		"borde válido: altura_relativa ~1.0 (obtuvo %.3f)" % ledge.altura_relativa)
	_check(ledge.landing_libre, "borde válido: landing_libre true (esta zona tiene espacio arriba)")


func _test_borde_sin_pared() -> void:
	_ubicar(Vector3(0, 0, 5))  # zona abierta, sin nada delante en -Z
	var oportunidades := detector.collect(_snapshot())
	_check(oportunidades.ledge == null, "sin pared delante: no hay candidato de borde")


func _test_borde_pared_inclinada() -> void:
	_ubicar(Vector3(10, 0, 0))
	detector.distancia_deteccion = 3.0  # la pared inclinada ocupa más volumen; margen generoso
	var oportunidades := detector.collect(_snapshot(Vector3(0, 0, -2.0)))
	detector.distancia_deteccion = 0.85  # restaurar default para el resto de los tests
	_check(oportunidades.ledge == null, "pared demasiado inclinada: se rechaza (no es una pared real)")


## Plan de separación HANGING/DIRECT_MANTLE: sin clearance arriba, el borde
## sigue siendo un candidato VÁLIDO (colgarse bajo un techo bajo es
## legítimo) — landing_libre = false es lo que efectivamente descarta la
## opción de TREPAR (TraversalController), no la existencia del candidato.
func _test_borde_clearance_bloqueado() -> void:
	_ubicar(Vector3(20, 0, 0))
	var oportunidades := detector.collect(_snapshot(Vector3(0, 0, -2.0)))
	_check(oportunidades.ledge != null and oportunidades.ledge.is_valid,
		"borde sin clearance: sigue siendo válido para HANGING")
	_check(oportunidades.ledge != null and not oportunidades.ledge.landing_libre,
		"borde sin clearance: landing_libre queda en false")


func _test_borde_altura_insuficiente() -> void:
	_ubicar(Vector3(30, 0, 0))
	var oportunidades := detector.collect(_snapshot(Vector3(0, 0, -2.0)))
	_check(oportunidades.ledge == null, "borde demasiado bajo: se rechaza por altura fuera de rango")


# ── Escalera ─────────────────────────────────────────────────────────
func _test_escalera_valida() -> void:
	_ubicar(Vector3(40, 0, 0.5))
	var oportunidades := detector.collect(_snapshot())
	var ladder := oportunidades.ladder

	_check(ladder != null, "escalera válida: se detecta un candidato")
	if ladder == null:
		return
	_check(ladder.is_valid, "escalera válida: is_valid true")
	_check(ladder.segment == escalera_valida, "escalera válida: el segment es el TraversalSegment real de la escena")
	_check(absf(ladder.initial_progress - 0.0) < 0.05,
		"escalera válida: initial_progress ~0 al pararse en la base (obtuvo %.3f)" % ladder.initial_progress)
	_check(ladder.approach_alignment > 0.9,
		"escalera válida: approach_alignment alto mirando de frente (obtuvo %.3f)" % ladder.approach_alignment)


func _test_ladder_candidate_siempre_tiene_segmento() -> void:
	_ubicar(Vector3(40, 0, 0.5))
	var oportunidades := detector.collect(_snapshot())
	if oportunidades.ladder != null and oportunidades.ladder.is_valid:
		_check(oportunidades.ladder.segment != null,
			"LadderCandidate válida: segment nunca es null")
	else:
		_check(false, "LadderCandidate válida: segment nunca es null (no se detectó candidato para probar)")


# ── TraversalSegment — contrato puro ─────────────────────────────────
func _test_segmento_progreso_y_direccion() -> void:
	var inicio := escalera_valida.get_position_at(0.0)
	var fin := escalera_valida.get_position_at(1.0)
	var medio := escalera_valida.get_position_at(0.5)

	_check(inicio.is_equal_approx(escalera_valida.start_marker.global_position),
		"segmento: progress 0.0 coincide con start_marker")
	_check(fin.is_equal_approx(escalera_valida.end_marker.global_position),
		"segmento: progress 1.0 coincide con end_marker")
	_check(medio.is_equal_approx((inicio + fin) * 0.5),
		"segmento: progress 0.5 es el punto medio real")

	_check(escalera_valida.get_direction_at(0.5).is_equal_approx(Vector3.UP),
		"segmento: dirección de una escalera vertical es UP")
	_check(absf(escalera_valida.get_length() - 4.0) < 0.01,
		"segmento: longitud real ~4.0 (obtuvo %.3f)" % escalera_valida.get_length())
	_check(escalera_valida.is_valid(), "segmento: is_valid() true con markers y longitud correctos")


func _test_segmento_vecinos() -> void:
	_check(segmento_inferior.get_neighbour_up() == segmento_superior,
		"segmento: neighbour_up del inferior es el superior")
	_check(segmento_superior.get_neighbour_down() == segmento_inferior,
		"segmento: neighbour_down del superior es el inferior")
	_check(segmento_inferior.is_valid(), "segmento inferior: is_valid() true")
	_check(segmento_superior.is_valid(), "segmento superior: is_valid() true")


# ── Collision mask ───────────────────────────────────────────────────
func _test_collision_mask_afecta_deteccion() -> void:
	_ubicar(Vector3(50, 0, 0), 1)  # mask = capa 1 solamente; el muro está en capa 5
	var sin_capa := detector.collect(_snapshot(Vector3(0, 0, -2.0)))
	_check(sin_capa.ledge == null,
		"collision_mask capa 1: NO detecta un muro que está solo en capa 5")

	_ubicar(Vector3(50, 0, 0), 1 | 16)  # agregar capa 5 (bit 16) al mask
	var con_capa := detector.collect(_snapshot(Vector3(0, 0, -2.0)))
	_check(con_capa.ledge != null,
		"collision_mask con capa 5 agregada: SÍ detecta el mismo muro")


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
