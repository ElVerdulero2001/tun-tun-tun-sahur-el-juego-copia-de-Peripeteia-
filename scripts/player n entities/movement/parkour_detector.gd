# parkour_detector.gd
# Nodo hijo del Player.
# Responsabilidad ÚNICA: detectar oportunidades de traversal y emitir señales.
# NO modifica velocity. NO cambia estados. Solo detecta y puntúa.

extends Node

# ── Señales ───────────────────────────────────────────────────────
# Emitida cada frame con el mejor candidato encontrado (o null si ninguno).
signal candidate_found(candidate: Dictionary)
signal candidate_lost()

# ── Parámetros de detección ───────────────────────────────────────
@export var detection_distance   : float = 0.85   # distancia frontal al raycast de pared
@export var edge_probe_up        : float = 0.15   # cuánto sube el probe para buscar el borde
@export var min_edge_height      : float = 0.5    # altura mínima del borde sobre el jugador
@export var max_edge_height      : float = 2.6    # altura máxima del borde sobre el jugador
@export var clearance_height     : float = 1.2    # espacio libre necesario arriba del borde
@export var clearance_radius     : float = 0.25   # radio del capsule check de clearance
@export var min_score            : float = 0.35   # score mínimo para emitir candidate_found

# Inclinación máxima de la superficie respecto a la vertical, en grados.
# 0° = pared perfectamente vertical. Una superficie más inclinada que esto
# se considera rampa/piso y NO es agarrable.
@export var max_surface_tilt_deg : float = 30.0

# ── Alturas de sondeo (relativas al centro del jugador) ───────────
# Se lanzan raycasts frontales en cada una de estas alturas.
const PROBE_HEIGHTS : Array = [0.6, 0.9, 1.2, 1.5, 1.8]

# ── Referencias ───────────────────────────────────────────────────
var body   : CharacterBody3D
var camera : Camera3D

# ── Estado interno ────────────────────────────────────────────────
var _last_candidate : Dictionary = {}
var _has_candidate  : bool = false

# ── Cooldown ──────────────────────────────────────────────────────
# Tras soltar un borde, el detector queda "ciego" este tiempo para
# evitar que el jugador se re-enganche al mismo borde inmediatamente.
@export var detection_cooldown : float = 0.4
var _cooldown_timer : float = 0.0

# ─────────────────────────────────────────────────────────────────
func setup(p_body: CharacterBody3D, p_camera: Camera3D) -> void:
	body   = p_body
	camera = p_camera

# ─────────────────────────────────────────────────────────────────
# Llamado desde el TraversalController al soltar un borde.
func start_cooldown() -> void:
	_cooldown_timer = detection_cooldown

# ─────────────────────────────────────────────────────────────────
# Llamado desde player.gd en _physics_process.
# Solo corre cuando el jugador está en el aire o saltando.
func process(delta: float) -> void:
	# Descontar cooldown — mientras esté activo, no detectar nada.
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		_clear_candidate()
		return

	if body.is_on_floor():
		_clear_candidate()
		return

	var best = _find_best_candidate()

	if best.is_empty() or best["score"] < min_score:
		_clear_candidate()
		return

	_last_candidate = best
	_has_candidate  = true
	candidate_found.emit(best)

# ─────────────────────────────────────────────────────────────────
func get_current_candidate() -> Dictionary:
	return _last_candidate

func has_candidate() -> bool:
	return _has_candidate

# ─────────────────────────────────────────────────────────────────
# ── DETECCIÓN ────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _find_best_candidate() -> Dictionary:
	var space     = body.get_world_3d().direct_space_state
	var facing    = -body.transform.basis.z  # dirección frontal del jugador
	var best      : Dictionary = {}
	var best_score: float = -1.0

	for probe_offset in PROBE_HEIGHTS:
		var origin = body.global_position + Vector3.UP * probe_offset
		var candidate = _probe_at(space, origin, facing)
		if candidate.is_empty():
			continue

		var score = _score_candidate(candidate)
		candidate["score"] = score

		# Debug: punto en el borde, color según score (rojo bajo → verde alto)
		var col = Color(1.0 - score, score, 0.0)
		DebugDraw.point(candidate["edge_point"], col, 0.12)
		DebugDraw.sphere(candidate["edge_point"], 0.15, col)

		if score > best_score:
			best_score = score
			best       = candidate

	# Debug: marcar el ganador con una esfera más grande cyan
	if not best.is_empty():
		DebugDraw.sphere(best["edge_point"], 0.28, Color.CYAN)

	return best

# ─────────────────────────────────────────────────────────────────
func _probe_at(space, origin: Vector3, facing: Vector3) -> Dictionary:
	# 1. Raycast frontal — busca una superficie
	var ray_end = origin + facing * detection_distance
	var wall_hit = _raycast(space, origin, ray_end)

	# Debug: el raycast frontal — gris si no pega, blanco si pega
	DebugDraw.ray(origin, ray_end, Color.GRAY if wall_hit.is_empty() else Color.WHITE)

	if wall_hit.is_empty():
		return {}

	var wall_normal : Vector3 = wall_hit["normal"]
	var wall_point  : Vector3 = wall_hit["position"]

	# 2. Validar que la superficie es suficientemente vertical.
	# La normal de una pared vertical es horizontal → su componente Y es ~0.
	# Una superficie inclinada X grados respecto a la vertical tiene
	# abs(normal.y) = sin(X). Rechazamos todo lo que supere el umbral.
	var max_normal_y = sin(deg_to_rad(max_surface_tilt_deg))
	if abs(wall_normal.y) > max_normal_y:
		return {}   # demasiado inclinada → rampa o piso, no agarrable

	# 3. Buscar el borde superior de la pared.
	# Arrancamos el raycast bien por encima del jugador (en el techo del
	# rango alcanzable) y bajamos hasta el punto de contacto de la pared.
	# Así cubrimos toda la altura agarrable sin quedarnos cortos.
	var search_top    = body.global_position.y + max_edge_height + 0.3
	var edge_search_origin = Vector3(wall_point.x, search_top, wall_point.z) - wall_normal * 0.08
	var edge_search_end    = Vector3(wall_point.x, wall_point.y, wall_point.z) - wall_normal * 0.08
	var edge_hit = _raycast(space, edge_search_origin, edge_search_end)

	# Debug: el raycast de búsqueda de borde
	DebugDraw.ray(edge_search_origin, edge_search_end,
				  Color.GRAY if edge_hit.is_empty() else Color.AQUA)

	if edge_hit.is_empty():
		return {}

	var edge_point : Vector3 = edge_hit["position"]

	# 3b. COHERENCIA: el borde tiene que estar casi pegado a la pared.
	# Un borde real está justo encima de su pared. Si el punto detectado
	# está lejos en horizontal del punto de la pared, es un fantasma
	# geométrico (otra cara, un saliente, geometría amontonada).
	var horiz_pared = Vector2(wall_point.x, wall_point.z)
	var horiz_borde = Vector2(edge_point.x, edge_point.z)
	if horiz_pared.distance_to(horiz_borde) > 0.35:
		return {}   # el "borde" no corresponde a esta pared

	# 3b. Validar que lo detectado es un BORDE real, no la cara de una rampa.
	# Un borde verdadero tiene una superficie horizontal (piso) encima.
	# Si la normal del punto de "borde" no apunta hacia arriba, es una
	# superficie inclinada y no sirve para colgarse.
	var edge_normal : Vector3 = edge_hit["normal"]
	if edge_normal.dot(Vector3.UP) < cos(deg_to_rad(max_surface_tilt_deg)):
		return {}   # la cara superior está demasiado inclinada → no es un borde

	# 4. Validar que el borde está en el rango de altura alcanzable
	var height_diff = edge_point.y - body.global_position.y
	if height_diff < min_edge_height or height_diff > max_edge_height:
		return {}

	# 5. Validar clearance (espacio libre arriba del borde)
	if not _check_clearance(space, edge_point):
		return {}

	return {
		"wall_normal"  : wall_normal,
		"wall_point"   : wall_point,
		"edge_point"   : edge_point,
		"height_diff"  : height_diff,
		"score"        : 0.0   # se calcula después
	}

# ─────────────────────────────────────────────────────────────────
# ── SCORING ──────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _score_candidate(c: Dictionary) -> float:
	var score : float = 0.0

	# ── Alineación jugador → pared ────────────────────────────────
	# Qué tan de frente está el jugador a la pared.
	# dot entre facing y -normal: 1.0 = perfectamente alineado
	var facing    = -body.transform.basis.z
	var wall_dot  = facing.dot(-c["wall_normal"])
	if wall_dot < 0.3:   # demasiado de lado → descartar
		return 0.0
	score += wall_dot * 0.35

	# ── Coherencia de velocidad ────────────────────────────────────
	# El jugador se mueve en la dirección del borde.
	var vel_h = Vector2(body.velocity.x, body.velocity.z)
	if vel_h.length() > 0.5:
		var vel_dir    = Vector3(vel_h.x, 0.0, vel_h.y).normalized()
		var vel_dot    = vel_dir.dot(-c["wall_normal"])
		score += clamp(vel_dot, 0.0, 1.0) * 0.30

	# ── Dirección de cámara ────────────────────────────────────────
	# La cámara mira hacia la pared.
	var cam_forward = -camera.global_transform.basis.z
	cam_forward.y   = 0.0
	cam_forward     = cam_forward.normalized()
	var cam_dot     = cam_forward.dot(-c["wall_normal"])
	score += clamp(cam_dot, 0.0, 1.0) * 0.20

	# ── Distancia al borde ─────────────────────────────────────────
	# Penaliza bordes muy lejanos, premia los alcanzables.
	var dist = body.global_position.distance_to(c["edge_point"])
	var dist_score = 1.0 - clamp(dist / (detection_distance * 2.5), 0.0, 1.0)
	score += dist_score * 0.15

	return clamp(score, 0.0, 1.0)

# ─────────────────────────────────────────────────────────────────
# ── HELPERS ──────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _raycast(space, from: Vector3, to: Vector3) -> Dictionary:
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [body]
	return space.intersect_ray(query)

func _check_clearance(space, edge_point: Vector3) -> bool:
	# Capsule check: hay espacio suficiente arriba del borde para que entre el jugador.
	var shape  = CapsuleShape3D.new()
	shape.radius = clearance_radius
	shape.height = clearance_height

	var params                    = PhysicsShapeQueryParameters3D.new()
	params.shape                  = shape
	params.transform              = Transform3D(Basis.IDENTITY, edge_point + Vector3.UP * (clearance_height * 0.5 + 0.1))
	params.exclude                = [body]
	params.collision_mask         = body.collision_mask

	var results = space.intersect_shape(params)
	return results.is_empty()

func _clear_candidate() -> void:
	if _has_candidate:
		_has_candidate  = false
		_last_candidate = {}
		candidate_lost.emit()
