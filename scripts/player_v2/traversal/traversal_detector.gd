class_name TraversalDetector
extends Node

## Detector físico de oportunidades de traversal (Parkour V2, Fase 3; doc de
## arquitectura V0.3, sección 10).
##
## Hace queries físicas y produce candidatos tipados. NO lee input, NO
## arbitra decisiones (eso es TraversalResolver), NO cambia estados y NUNCA
## mueve a nadie. Es pasivo por completo: jamás escribe global_transform,
## velocity, postura, collider ni lease de probe_body — solo lo lee, junto
## con collision_mask, para no duplicar una máscara hardcodeada.
##
## collect() recibe un MotorSnapshot, no un TraversalIntent: describe
## oportunidades, no arbitra con intención (eso lo combina el resolver).
##
## Conserva del legacy (ParkourDetector, ver auditoría del commit que lo
## borró) las ideas geométricas que probaron servir: sondeo a varias
## alturas, validación de inclinación de pared y de superficie, coherencia
## lateral pared/borde, clearance por cápsula, y scoring ponderado por
## frente + velocidad + mira + distancia. Descarta señales, cooldowns,
## conocimiento del controller, grupo "ladder" + búsqueda por ancestros, y
## todo el DebugDraw de las queries — una escalera V2 se reconoce por
## contrato directo con TraversalSegment (cast del collider), nunca por
## nombre, grupo o cercanía sin contrato.
##
## Todos los rangos/ángulos/distancias de abajo son PROVISIONALES (sección
## 14, pendientes de calibración de feel): la arquitectura no depende de
## sus valores exactos.

## Cuerpo físico a sondear. Solo lectura: este nodo nunca lo modifica.
@export var probe_body: CharacterBody3D

## Fuente de "hacia dónde mira" el jugador (típicamente la cámara), separada
## del facing horizontal del cuerpo. Solo lectura, igual que probe_body.
@export var aim_source: Node3D

# ── Borde — parámetros de feel (calibrables) ─────────────────────────
@export var distancia_deteccion: float = 0.85
@export var borde_altura_minima: float = 0.5
@export var borde_altura_maxima: float = 1.5
# Iguales a PlayerMotor.STANDING_HEIGHT / el radio de su cápsula de pie
# (Fase 5): un volumen de clearance MENOR que el jugador real de pie podía
# marcar un borde como válido sin que el jugador real entrara parado ahí
# — importante ahora que MANTLING de verdad para al personaje en esa pose.
@export var clearance_altura: float = 1.8
@export var clearance_radio: float = 0.3
@export var superficie_inclinacion_max_deg: float = 30.0
@export var borde_tolerancia_lateral: float = 0.35
@export var alturas_de_sondeo: PackedFloat32Array = [0.3, 0.6, 0.9, 1.2, 1.5]

# ── Escalera — parámetros de feel (calibrables) ──────────────────────
@export var escalera_radio_deteccion: float = 1.0
@export var escalera_tolerancia_progreso: float = 0.15

# ── Pesos de scoring del borde — suman 1.0, calibrables ──────────────
const PESO_FRENTE := 0.35
const PESO_VELOCIDAD := 0.30
const PESO_AIM := 0.20
const PESO_DISTANCIA := 0.15

const _UMBRAL_FRENTE_MINIMO := 0.3
const _VELOCIDAD_MINIMA_PARA_PUNTUAR := 0.5


## Único punto de entrada. Puro respecto de probe_body: no lo mueve, no le
## cambia velocity/postura/collider/lease. Devuelve las oportunidades del
## tick actual, cada una null si no hay candidato de ese tipo.
func collect(motor_snapshot: MotorSnapshot) -> TraversalOpportunities:
	var ledge := _detectar_borde(motor_snapshot)
	var ladder := _detectar_escalera()
	return TraversalOpportunities.new(ledge, ladder)


## Consulta pasiva: ¿probe_body podría ocupar esta pose (posición +
## orientación) ahora mismo sin penetrar geometría? No lee input, no conoce
## estados, no mueve nada — CharacterBody3D.test_move() es una query
## hipotética por diseño, nunca aplica el movimiento que prueba. La usa
## TraversalController (Fase 5) para revalidar la pose de hang cuando un
## mantle se bloquea, sin que el detector tenga que saber qué es "mantle"
## ni por qué se le pregunta (doc sección 9.1: "revalidar la pose de hang
## en ese instante; no confiar en la validación de entrada").
func is_pose_clear(pose: Transform3D) -> bool:
	return not probe_body.test_move(pose, Vector3.ZERO, null, 0.001, true)


# ── Borde ──────────────────────────────────────────────────────────
func _detectar_borde(motor_snapshot: MotorSnapshot) -> LedgeCandidate:
	var espacio := probe_body.get_world_3d().direct_space_state
	var frente := -probe_body.global_transform.basis.z

	var mejor: LedgeCandidate = null
	var mejor_score := -1.0

	for altura in alturas_de_sondeo:
		var origen := probe_body.global_position + Vector3.UP * altura
		var candidato := _sondear_borde_en(espacio, origen, frente, motor_snapshot)
		if candidato == null:
			continue
		if candidato.score > mejor_score:
			mejor_score = candidato.score
			mejor = candidato

	return mejor


func _sondear_borde_en(espacio: PhysicsDirectSpaceState3D, origen: Vector3, frente: Vector3,
		motor_snapshot: MotorSnapshot) -> LedgeCandidate:
	var fin_rayo := origen + frente * distancia_deteccion
	var golpe_pared := _raycast(espacio, origen, fin_rayo)
	if golpe_pared.is_empty():
		return null

	var normal_pared: Vector3 = golpe_pared["normal"]
	var punto_pared: Vector3 = golpe_pared["position"]

	# Pared demasiado inclinada (casi un piso o un techo, no una pared real).
	var normal_y_max := sin(deg_to_rad(superficie_inclinacion_max_deg))
	if absf(normal_pared.y) > normal_y_max:
		return null

	# Buscar el borde superior: rayo hacia abajo desde por encima de la
	# altura máxima de borde, pegado a la pared (mismo punto XZ).
	var techo_busqueda := probe_body.global_position.y + borde_altura_maxima + 0.3
	var origen_borde := Vector3(punto_pared.x, techo_busqueda, punto_pared.z) - normal_pared * 0.08
	var fin_borde := Vector3(punto_pared.x, punto_pared.y, punto_pared.z) - normal_pared * 0.08
	var golpe_borde := _raycast(espacio, origen_borde, fin_borde)
	if golpe_borde.is_empty():
		return null

	var punto_borde: Vector3 = golpe_borde["position"]

	# El borde encontrado tiene que estar sobre la MISMA pared, no en otra
	# superficie lejana en el mismo eje de búsqueda.
	var horizontal_pared := Vector2(punto_pared.x, punto_pared.z)
	var horizontal_borde := Vector2(punto_borde.x, punto_borde.z)
	if horizontal_pared.distance_to(horizontal_borde) > borde_tolerancia_lateral:
		return null

	# La superficie de aterrizaje tiene que ser razonablemente horizontal.
	var normal_borde: Vector3 = golpe_borde["normal"]
	if normal_borde.dot(Vector3.UP) < cos(deg_to_rad(superficie_inclinacion_max_deg)):
		return null

	var diferencia_altura := punto_borde.y - probe_body.global_position.y
	if diferencia_altura < borde_altura_minima or diferencia_altura > borde_altura_maxima:
		return null

	var punto_aterrizaje := punto_borde + Vector3.UP * 0.05
	if not _hay_espacio_libre(espacio, punto_aterrizaje):
		return null

	var score := _puntuar_borde(frente, normal_pared, motor_snapshot, punto_borde)

	# Fase 6: si el collider del propio borde tiene un TraversalSegment de
	# tipo LEDGE asociado (mismo patrón que la escalera: cast directo, sin
	# grupo ni nombre), ese segmento habilita shimmy para este candidato.
	# Reutiliza el raycast del borde que ya se hizo arriba — no hace falta
	# una query nueva. Un segmento de OTRO tipo (p. ej. LADDER) o inválido
	# se descarta silenciosamente: el borde sigue siendo válido, solo sin
	# shimmy.
	var segmento_borde := golpe_borde.get("collider") as TraversalSegment
	if segmento_borde == null or segmento_borde.segment_type != TraversalSegment.Type.LEDGE \
			or not segmento_borde.is_valid():
		segmento_borde = null

	return LedgeCandidate.new(punto_borde, normal_pared, punto_aterrizaje, score, true, segmento_borde)


func _puntuar_borde(frente: Vector3, normal_pared: Vector3, motor_snapshot: MotorSnapshot,
		punto_borde: Vector3) -> float:
	var dot_frente := frente.dot(-normal_pared)
	if dot_frente < _UMBRAL_FRENTE_MINIMO:
		return 0.0

	var puntaje := dot_frente * PESO_FRENTE

	var vel_h := Vector2(motor_snapshot.velocity.x, motor_snapshot.velocity.z)
	if vel_h.length() > _VELOCIDAD_MINIMA_PARA_PUNTUAR:
		var dir_vel := Vector3(vel_h.x, 0.0, vel_h.y).normalized()
		puntaje += clampf(dir_vel.dot(-normal_pared), 0.0, 1.0) * PESO_VELOCIDAD

	if aim_source != null:
		var frente_aim := -aim_source.global_transform.basis.z
		frente_aim.y = 0.0
		if frente_aim.length() > 0.001:
			frente_aim = frente_aim.normalized()
			puntaje += clampf(frente_aim.dot(-normal_pared), 0.0, 1.0) * PESO_AIM

	var distancia := probe_body.global_position.distance_to(punto_borde)
	var puntaje_distancia := 1.0 - clampf(distancia / (distancia_deteccion * 2.5), 0.0, 1.0)
	puntaje += puntaje_distancia * PESO_DISTANCIA

	return clampf(puntaje, 0.0, 1.0)


func _hay_espacio_libre(espacio: PhysicsDirectSpaceState3D, punto: Vector3) -> bool:
	var forma := CapsuleShape3D.new()
	forma.radius = clearance_radio
	forma.height = clearance_altura

	var parametros := PhysicsShapeQueryParameters3D.new()
	parametros.shape = forma
	parametros.transform = Transform3D(Basis.IDENTITY, punto + Vector3.UP * (clearance_altura * 0.5 + 0.1))
	parametros.collision_mask = probe_body.collision_mask
	parametros.exclude = [probe_body.get_rid()]

	var resultados := espacio.intersect_shape(parametros)
	return resultados.is_empty()


# ── Escalera ───────────────────────────────────────────────────────
func _detectar_escalera() -> LadderCandidate:
	var espacio := probe_body.get_world_3d().direct_space_state
	var forma := SphereShape3D.new()
	forma.radius = escalera_radio_deteccion

	var parametros := PhysicsShapeQueryParameters3D.new()
	parametros.shape = forma
	parametros.transform = Transform3D(Basis.IDENTITY, probe_body.global_position)
	parametros.collision_mask = probe_body.collision_mask
	parametros.exclude = [probe_body.get_rid()]

	var resultados := espacio.intersect_shape(parametros)

	var mejor: LadderCandidate = null
	var mejor_alineacion := -1.0

	for resultado in resultados:
		var segmento := resultado.get("collider") as TraversalSegment
		# Fase 6: un TraversalSegment de tipo LEDGE (shimmy de borde) puede
		# estar perfectamente cerca de probe_body sin ser una escalera —
		# filtrar por tipo evita que la query de escalera confunda uno con
		# otro (antes de esta fase solo existía LADDER, así que no hacía
		# falta distinguir).
		if segmento == null or segmento.segment_type != TraversalSegment.Type.LADDER or not segmento.is_valid():
			continue

		var candidato := _evaluar_segmento(segmento)
		if candidato == null:
			continue
		if candidato.approach_alignment > mejor_alineacion:
			mejor_alineacion = candidato.approach_alignment
			mejor = candidato

	return mejor


## Una escalera V2 se reconoce por contrato directo con TraversalSegment
## (el `segmento` ya validado que recibe esta función), nunca por nombre de
## nodo, grupo o cercanía sin contrato.
func _evaluar_segmento(segmento: TraversalSegment) -> LadderCandidate:
	# get_progress_along()/get_position_at() son de TraversalSegment (Fase 6):
	# la misma proyección sobre la línea del segmento que antes se calculaba
	# acá a mano, ahora reutilizada — shimmy (borde) la necesita igual.
	var progreso_crudo := segmento.get_progress_along(probe_body.global_position)
	var punto_proyectado := segmento.get_position_at(clampf(progreso_crudo, 0.0, 1.0))
	var distancia_lateral := probe_body.global_position.distance_to(punto_proyectado)
	if distancia_lateral > escalera_radio_deteccion:
		return null

	if progreso_crudo < -escalera_tolerancia_progreso or progreso_crudo > 1.0 + escalera_tolerancia_progreso:
		return null

	var progreso := clampf(progreso_crudo, 0.0, 1.0)
	var alineacion := _alinear_con_segmento(punto_proyectado)

	return LadderCandidate.new(segmento, progreso, alineacion, true)


## Qué tan alineado está el frente horizontal del cuerpo con la dirección
## hacia el punto más cercano del segmento — no con la dirección DEL
## segmento (que para una escalera vertical es ~UP y no dice nada sobre
## "avanzar hacia ella"). Mismo tipo de dot-product que _puntuar_borde.
func _alinear_con_segmento(punto_proyectado: Vector3) -> float:
	var hacia_segmento := punto_proyectado - probe_body.global_position
	hacia_segmento.y = 0.0
	if hacia_segmento.length() <= 0.001:
		return 1.0  # prácticamente encima del segmento

	hacia_segmento = hacia_segmento.normalized()
	var frente := -probe_body.global_transform.basis.z
	frente.y = 0.0
	if frente.length() <= 0.001:
		return 1.0

	frente = frente.normalized()
	return clampf(frente.dot(hacia_segmento), 0.0, 1.0)


# ── Helper de queries físicas ────────────────────────────────────────
func _raycast(espacio: PhysicsDirectSpaceState3D, desde: Vector3, hasta: Vector3) -> Dictionary:
	var consulta := PhysicsRayQueryParameters3D.create(desde, hasta)
	consulta.collision_mask = probe_body.collision_mask
	consulta.exclude = [probe_body.get_rid()]
	return espacio.intersect_ray(consulta)
