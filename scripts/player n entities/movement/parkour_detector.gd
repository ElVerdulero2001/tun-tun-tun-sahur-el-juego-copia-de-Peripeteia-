# parkour_detector.gd
# Nodo hijo del Player.
# Responsabilidad ÚNICA: detectar oportunidades de traversal y emitir señales.
# NO modifica velocity. NO cambia estados. Solo detecta y puntúa.
#
# Detecta dos tipos de candidatos:
#   - LedgeCandidate  → señal candidate_found
#   - LadderCandidate → señal ladder_candidate_found

extends Node

# ── Señales ───────────────────────────────────────────────────────
signal candidate_found(candidate: Dictionary)
signal candidate_lost()
signal ladder_candidate_found(candidate: Dictionary)
signal ladder_candidate_lost()

# ── Parámetros de detección — ledge ──────────────────────────────
@export var detection_distance   : float = 0.85
@export var edge_probe_up        : float = 0.15
@export var min_edge_height      : float = 0.5
@export var max_edge_height      : float = 1.5
@export var clearance_height     : float = 1.2
@export var clearance_radius     : float = 0.25
@export var min_score            : float = 0.35
@export var max_surface_tilt_deg : float = 30.0

# ── Parámetros de detección — ladder ─────────────────────────────
@export var ladder_detection_radius : float = 1.2
@export var ladder_max_distance     : float = 2.0

# ── Alturas de sondeo ─────────────────────────────────────────────
const PROBE_HEIGHTS : Array = [0.3, 0.6, 0.9, 1.2, 1.5]

# ── Referencias ───────────────────────────────────────────────────
var body      : CharacterBody3D
var camera    : Camera3D
var traversal : Node

# ── Estado interno — ledge ────────────────────────────────────────
var _last_candidate : Dictionary = {}
var _has_candidate  : bool = false

# ── Estado interno — ladder ───────────────────────────────────────
var _has_ladder_candidate  : bool       = false
var _last_ladder_candidate : Dictionary = {}

# ── Cooldown ──────────────────────────────────────────────────────
@export var detection_cooldown : float = 0.8
var _cooldown_timer : float = 0.0

# ─────────────────────────────────────────────────────────────────
func setup(p_body: CharacterBody3D, p_camera: Camera3D, p_traversal: Node = null) -> void:
	body      = p_body
	camera    = p_camera
	traversal = p_traversal

func start_cooldown() -> void:
	_cooldown_timer = detection_cooldown

# ─────────────────────────────────────────────────────────────────
func process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		_clear_candidate()
		_clear_ladder_candidate()
		return

	if body.is_on_floor():
		_clear_candidate()
	else:
		_process_ledge()

	_process_ladder()

# ─────────────────────────────────────────────────────────────────
# ── LEDGE ────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _process_ledge() -> void:
	var best = _find_best_candidate()

	if best.is_empty() or best["score"] < min_score:
		_clear_candidate()
		return

	if traversal and traversal.last_hanging_pos != Vector3.ZERO:
		var last = traversal.last_hanging_pos
		if best["edge_point"].distance_to(last) < 2.0:
			_clear_candidate()
			return
		if body.global_position.distance_to(last) < 2.0:
			_clear_candidate()
			return

	_last_candidate = best
	_has_candidate  = true
	candidate_found.emit(best)

func get_current_candidate() -> Dictionary:
	return _last_candidate

func has_candidate() -> bool:
	return _has_candidate

# ─────────────────────────────────────────────────────────────────
# ── LADDER ───────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _process_ladder() -> void:
	var space    = body.get_world_3d().direct_space_state
	var shape    = SphereShape3D.new()
	shape.radius = ladder_detection_radius

	var params            = PhysicsShapeQueryParameters3D.new()
	params.shape          = shape
	params.transform      = Transform3D(Basis.IDENTITY, body.global_position)
	params.exclude        = [body]
	params.collision_mask = body.collision_mask

	var results = space.intersect_shape(params)

	for result in results:
		var collider = result.get("collider", null)
		if collider == null:
			continue

		# Buscar el nodo con grupo "ladder" subiendo por la jerarquía.
		var segment = _find_ladder_area(collider)
		if segment == null:
			continue

		# Validar que el segmento tiene los markers necesarios.
		# Sin markers no hay segmento válido — descartamos.
		if segment.get("start_marker") == null or segment.get("end_marker") == null:
			continue
		if segment.start_marker == null or segment.end_marker == null:
			continue

		# Validar distancia.
		var dist = body.global_position.distance_to(segment.start_marker.global_position)
		if dist > ladder_max_distance:
			continue

		# Validar intención.
		if not _has_ladder_intent(segment):
			continue

		# Candidato válido — construir y emitir.
		var candidate = {
			"type"     : "ladder",
			"area"     : segment,   # el TraversalSegment
			"distance" : dist,
		}

		# Debug — mostrar markers
		DebugDraw.sphere(segment.start_marker.global_position, 0.15, Color.GREEN)
		DebugDraw.sphere(segment.end_marker.global_position,   0.15, Color.RED)
		DebugDraw.ray(
			segment.start_marker.global_position,
			segment.end_marker.global_position,
			Color.ORANGE
		)

		if not ladder_detected() or _last_ladder_candidate.get("area") != segment:
			_last_ladder_candidate = candidate
			_has_ladder_candidate  = true
			ladder_candidate_found.emit(candidate)
		return

	_clear_ladder_candidate()

func _find_ladder_area(node: Node) -> Node:
	var current = node
	for _i in range(4):
		if current == null:
			break
		if current.is_in_group("ladder"):
			return current
		current = current.get_parent()
	return null

func _has_ladder_intent(segment: Node) -> bool:
	if Input.is_action_pressed("move_forward"):
		return true

	var to_ladder = (segment.start_marker.global_position - body.global_position)
	to_ladder.y   = 0.0
	if to_ladder.length() < 0.01:
		return true

	to_ladder = to_ladder.normalized()
	var cam_fwd = -camera.global_transform.basis.z
	cam_fwd.y   = 0.0
	if cam_fwd.length() < 0.01:
		return false
	cam_fwd = cam_fwd.normalized()

	return cam_fwd.dot(to_ladder) > 0.3

func ladder_detected() -> bool:
	return _has_ladder_candidate

func get_current_ladder_candidate() -> Dictionary:
	return _last_ladder_candidate

func _clear_ladder_candidate() -> void:
	if _has_ladder_candidate:
		_has_ladder_candidate  = false
		_last_ladder_candidate = {}
		ladder_candidate_lost.emit()

# ─────────────────────────────────────────────────────────────────
# ── DETECCIÓN DE LEDGE — sin cambios ─────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _find_best_candidate() -> Dictionary:
	var space     = body.get_world_3d().direct_space_state
	var facing    = -body.transform.basis.z
	var best      : Dictionary = {}
	var best_score: float = -1.0

	for probe_offset in PROBE_HEIGHTS:
		var origin = body.global_position + Vector3.UP * probe_offset
		var candidate = _probe_at(space, origin, facing)
		if candidate.is_empty():
			continue

		var score = _score_candidate(candidate)
		candidate["score"] = score

		var col = Color(1.0 - score, score, 0.0)
		DebugDraw.point(candidate["edge_point"], col, 0.12)
		DebugDraw.sphere(candidate["edge_point"], 0.15, col)

		if score > best_score:
			best_score = score
			best       = candidate

	if not best.is_empty():
		DebugDraw.sphere(best["edge_point"], 0.28, Color.CYAN)

	return best

func _probe_at(space, origin: Vector3, facing: Vector3) -> Dictionary:
	var ray_end  = origin + facing * detection_distance
	var wall_hit = _raycast(space, origin, ray_end)

	DebugDraw.ray(origin, ray_end, Color.GRAY if wall_hit.is_empty() else Color.WHITE)

	if wall_hit.is_empty():
		return {}

	var wall_normal : Vector3 = wall_hit["normal"]
	var wall_point  : Vector3 = wall_hit["position"]

	var max_normal_y = sin(deg_to_rad(max_surface_tilt_deg))
	if abs(wall_normal.y) > max_normal_y:
		return {}

	var search_top         = body.global_position.y + max_edge_height + 0.3
	var edge_search_origin = Vector3(wall_point.x, search_top, wall_point.z) - wall_normal * 0.08
	var edge_search_end    = Vector3(wall_point.x, wall_point.y, wall_point.z) - wall_normal * 0.08
	var edge_hit           = _raycast(space, edge_search_origin, edge_search_end)

	DebugDraw.ray(edge_search_origin, edge_search_end,
				  Color.GRAY if edge_hit.is_empty() else Color.AQUA)

	if edge_hit.is_empty():
		return {}

	var edge_point : Vector3 = edge_hit["position"]

	var horiz_pared = Vector2(wall_point.x, wall_point.z)
	var horiz_borde = Vector2(edge_point.x, edge_point.z)
	if horiz_pared.distance_to(horiz_borde) > 0.35:
		return {}

	var edge_normal : Vector3 = edge_hit["normal"]
	if edge_normal.dot(Vector3.UP) < cos(deg_to_rad(max_surface_tilt_deg)):
		return {}

	var height_diff = edge_point.y - body.global_position.y
	if height_diff < min_edge_height or height_diff > max_edge_height:
		return {}

	if not _check_clearance(space, edge_point):
		return {}

	return {
		"type"        : "ledge",
		"wall_normal" : wall_normal,
		"wall_point"  : wall_point,
		"edge_point"  : edge_point,
		"height_diff" : height_diff,
		"score"       : 0.0
	}

func _score_candidate(c: Dictionary) -> float:
	var score : float = 0.0

	var facing   = -body.transform.basis.z
	var wall_dot = facing.dot(-c["wall_normal"])
	if wall_dot < 0.3:
		return 0.0
	score += wall_dot * 0.35

	var vel_h = Vector2(body.velocity.x, body.velocity.z)
	if vel_h.length() > 0.5:
		var vel_dir = Vector3(vel_h.x, 0.0, vel_h.y).normalized()
		var vel_dot = vel_dir.dot(-c["wall_normal"])
		score += clamp(vel_dot, 0.0, 1.0) * 0.30

	var cam_forward = -camera.global_transform.basis.z
	cam_forward.y   = 0.0
	cam_forward     = cam_forward.normalized()
	var cam_dot     = cam_forward.dot(-c["wall_normal"])
	score += clamp(cam_dot, 0.0, 1.0) * 0.20

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
	var shape        = CapsuleShape3D.new()
	shape.radius     = clearance_radius
	shape.height     = clearance_height

	var params               = PhysicsShapeQueryParameters3D.new()
	params.shape             = shape
	params.transform         = Transform3D(Basis.IDENTITY, edge_point + Vector3.UP * (clearance_height * 0.5 + 0.1))
	params.exclude           = [body]
	params.collision_mask    = body.collision_mask

	var results = space.intersect_shape(params)
	return results.is_empty()

func _clear_candidate() -> void:
	if _has_candidate:
		_has_candidate  = false
		_last_candidate = {}
		candidate_lost.emit()
