# traversal_controller.gd
# Nodo hijo del Player.
# REESCRITURA COMPLETA — sin parches acumulados.
#
# Reglas de hierro:
#   1. Mientras state != IDLE, el TraversalController es dueño absoluto del body.
#      Nada externo lo saca de un estado. Solo el input del jugador lo saca.
#   2. Cada estado dibuja su debug INCONDICIONALMENTE. Nunca volamos a ciegas.
#   3. El detector queda apagado mientras traversal está activo (lo hace player.gd).

extends Node

# ── Señales ───────────────────────────────────────────────────────
signal traversal_started()
signal traversal_ended()

# ── Estados ───────────────────────────────────────────────────────
enum State { IDLE, SNAPPING, HANGING, CLIMBING, LADDER }
var state : State = State.IDLE

# ── Parámetros ────────────────────────────────────────────────────
@export var snap_speed          : float = 14.0
@export var snap_threshold      : float = 0.2
@export var climb_speed         : float = 4.0
@export var shimmy_speed        : float = 2.5
@export var shimmy_max_dist     : float = 0.5
@export var jump_force          : float = 6.5

# Parámetros de la escalera
@export var ladder_pulse_speed   : float = 0.8   # cuánto avanza progress por segundo
@export var ladder_pulse_time    : float = 0.18  # segundos entre pulsos (el ritmo)
@export var ladder_snap_strength : float = 0.3   # atracción al centro XZ al entrar

# Probes internos para suavizado de curvas.
const PROBE_OFFSETS_INNER : Array = [-0.7, -0.4, -0.1, 0.1, 0.4, 0.7]

# ── Referencias ───────────────────────────────────────────────────
var body     : CharacterBody3D
var camera   : Camera3D
var movement : Node
var detector : Node

# ── Estado interno — hanging/shimmy ──────────────────────────────
var _hang_position        : Vector3 = Vector3.ZERO
var _hang_position_target : Vector3 = Vector3.ZERO
var _transitioning_face   : bool    = false
var _hang_normal          : Vector3 = Vector3.ZERO
var _along_wall           : Vector3 = Vector3.ZERO

var _can_go_left  : bool = false
var _can_go_right : bool = false

var last_hanging_pos             : Vector3 = Vector3.ZERO
var _last_hang_clear_timer       : float   = 0.0
var is_crouch_blocked_after_drop : bool    = false
var _shimmy_dir                  : float   = 0.0

# ── Estado interno — ladder (segment-based) ───────────────────────
# El jugador ya no se mueve sobre el eje Y.
# Se mueve sobre "progress": 0.0 = StartMarker, 1.0 = EndMarker.
# La posición mundial se reconstruye cada frame desde el segmento.
var _current_segment     : Node   = null
var _current_progress    : float  = 0.0
var _ladder_pulse_timer  : float  = 0.0
var _ladder_dir          : float  = 0.0

# ── Log de eventos ────────────────────────────────────────────────
const LOG_MAX : int = 12
var _event_log : Array = []

func _log(msg: String) -> void:
	var t = Time.get_ticks_msec() / 1000.0
	_event_log.append({ "t": t, "msg": msg })
	while _event_log.size() > LOG_MAX:
		_event_log.pop_front()

# ── Constantes de hanging ─────────────────────────────────────────
const HANG_OFFSET_Y  : float = -0.55
const HANG_WALL_GAP  : float = -0.68
const SNAP_TIMEOUT   : float = 1.0
var _snap_timer      : float = 0.0

# ─────────────────────────────────────────────────────────────────
func setup(p_body: CharacterBody3D, p_camera: Camera3D, p_movement: Node, p_detector: Node) -> void:
	body     = p_body
	camera   = p_camera
	movement = p_movement
	detector = p_detector
	detector.candidate_found.connect(_on_candidate_found)
	detector.ladder_candidate_found.connect(_on_ladder_candidate_found)

func is_active() -> bool:
	return state != State.IDLE

func process(delta: float) -> void:
	_physics_process(delta)

func get_state_name() -> String:
	return State.keys()[state]

# ─────────────────────────────────────────────────────────────────
func get_debug_state() -> Dictionary:
	return {
		"state"        : get_state_name(),
		"active"       : is_active(),
		"hang_pos"     : _hang_position,
		"hang_normal"  : _hang_normal,
		"along_wall"   : _along_wall,
		"can_go_left"  : _can_go_left,
		"can_go_right" : _can_go_right,
		"shimmy_dir"   : _shimmy_dir,
		"snap_timer"   : _snap_timer,
		"snap_dist"    : body.global_position.distance_to(_hang_position) if body else 0.0,
		"ladder_dir"   : _ladder_dir,
		"ladder_progress" : _current_progress,
		"in_left"      : Input.is_action_pressed("move_left"),
		"in_right"     : Input.is_action_pressed("move_right"),
		"in_fwd"       : Input.is_action_pressed("move_forward"),
		"in_back"      : Input.is_action_pressed("move_back"),
		"in_jump"      : Input.is_action_pressed("jump"),
	}

func get_event_log() -> Array:
	return _event_log

# ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	DebugDraw.clear()

	if state == State.IDLE:
		if is_crouch_blocked_after_drop and not Input.is_action_pressed("crouch"):
			is_crouch_blocked_after_drop = false
		if body.is_on_floor():
			last_hanging_pos = Vector3.ZERO
			_last_hang_clear_timer = 0.0
		elif _last_hang_clear_timer > 0.0:
			_last_hang_clear_timer -= delta
			if _last_hang_clear_timer <= 0.0:
				last_hanging_pos = Vector3.ZERO
		return

	match state:
		State.SNAPPING: _state_snapping(delta)
		State.HANGING:  _state_hanging(delta)
		State.CLIMBING: _state_climbing(delta)
		State.LADDER:   _state_ladder(delta)

	_draw_debug()

# ─────────────────────────────────────────────────────────────────
# ── ENTRADA — hanging ─────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _on_candidate_found(candidate: Dictionary) -> void:
	if state != State.IDLE:
		return

	_hang_normal = candidate["wall_normal"]
	_along_wall  = Vector3.UP.cross(_hang_normal).normalized()

	var edge = candidate["edge_point"]
	_hang_position  = Vector3(edge.x, edge.y + HANG_OFFSET_Y, edge.z)
	_hang_position -= _hang_normal * HANG_WALL_GAP

	_hang_position_target = _hang_position
	_snap_timer = 0.0
	_log("candidato aceptado — snap iniciado")
	_change_state(State.SNAPPING)

# ─────────────────────────────────────────────────────────────────
# ── ENTRADA — ladder ──────────────────────────────────────────────
# Recibe el LadderCandidate del detector y entra al estado LADDER.
# ─────────────────────────────────────────────────────────────────

func _on_ladder_candidate_found(candidate: Dictionary) -> void:

	_current_segment = candidate["area"]

	var seg_start = _current_segment.start_marker.global_position
	var seg_end   = _current_segment.end_marker.global_position
	var seg_vec   = seg_end - seg_start
	var seg_len   = seg_vec.length()

	if seg_len > 0.001:
		var to_player = body.global_position - seg_start
		_current_progress = clamp(
			to_player.dot(seg_vec.normalized()) / seg_len,
			0.0,
			1.0
		)
	else:
		_current_progress = 0.0

	_ladder_pulse_timer = 0.0
	_ladder_dir         = 0.0

	_log(
		"escalera — entrada | segment: %s | progress: %.2f"
		% [_current_segment.name, _current_progress]
	)

	_change_state(State.LADDER)
# ─────────────────────────────────────────────────────────────────
# ── SNAPPING ─────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _state_snapping(delta: float) -> void:
	body.velocity = Vector3.ZERO

	if Input.is_action_just_pressed("jump"):
		_release(Vector3.UP * jump_force)
		return

	_snap_timer += delta
	if _snap_timer > SNAP_TIMEOUT:
		push_warning("TraversalController: SNAPPING abortado por timeout.")
		_log("SNAP abortado — TIMEOUT")
		_release(_hang_normal * 2.0)
		return

	body.global_position = body.global_position.lerp(_hang_position, snap_speed * delta)

	if body.global_position.distance_to(_hang_position) < snap_threshold:
		body.global_position = _hang_position
		_change_state(State.HANGING)

# ─────────────────────────────────────────────────────────────────
# ── HANGING ──────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _state_hanging(delta: float) -> void:
	body.velocity = Vector3.ZERO

	if Input.is_action_just_pressed("jump"):
		_log("hanging → CLIMBING")
		_change_state(State.CLIMBING)
		return

	if Input.is_action_just_pressed("move_back"):
		_log("release por SOLTAR (atras)")
		_release(_hang_normal * 3.5 + Vector3.UP * 1.0)
		return

	if Input.is_action_just_pressed("crouch"):
		_log("release por CONTROL — caída pasiva")
		last_hanging_pos = _hang_position
		_last_hang_clear_timer = detector.detection_cooldown
		is_crouch_blocked_after_drop = true
		_release(Vector3.ZERO)
		return

	_update_shimmy_probes()

	var dir := 0.0
	var pressing_left  = Input.is_action_pressed("move_left")
	var pressing_right = Input.is_action_pressed("move_right")

	if pressing_left and _can_go_left:
		dir = -1.0
	elif pressing_right and _can_go_right:
		dir = 1.0

	if pressing_left and not _can_go_left and _shimmy_dir != -99.0:
		_log("shimmy IZQUIERDA bloqueado — sin borde")
		_shimmy_dir = -99.0
	elif pressing_right and not _can_go_right and _shimmy_dir != 99.0:
		_log("shimmy DERECHA bloqueado — sin borde")
		_shimmy_dir = 99.0
	else:
		_shimmy_dir = dir

	if dir != 0.0:
		var step = _along_wall * dir * shimmy_speed * delta
		_hang_position        += step
		_hang_position_target += step

	if _transitioning_face:
		if dir == 0.0:
			body.velocity = Vector3.ZERO
			_apply_virtual_normal()
			_transitioning_face = false
		else:
			var smooth_x = lerp(_hang_position.x, _hang_position_target.x, 4.0 * delta)
			var smooth_z = lerp(_hang_position.z, _hang_position_target.z, 4.0 * delta)
			_hang_position = Vector3(smooth_x, _hang_position.y, smooth_z)
			var dist_xz = Vector2(_hang_position.x - _hang_position_target.x, _hang_position.z - _hang_position_target.z).length()
			if dist_xz < 0.01:
				_transitioning_face = false

	body.global_position = _hang_position

# ─────────────────────────────────────────────────────────────────
# ── CLIMBING ─────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _state_climbing(delta: float) -> void:
	body.velocity = Vector3.ZERO

	var target = _hang_position + Vector3.UP * 2.2 - _hang_normal * 0.4
	body.global_position = body.global_position.lerp(target, climb_speed * delta)

	if body.global_position.distance_to(target) < 0.12:
		body.global_position = target
		_release(-_hang_normal * 1.5)

# ─────────────────────────────────────────────────────────────────
# ── LADDER ───────────────────────────────────────────────────────
# El jugador se mueve sobre "progress" (0.0 → 1.0) dentro del segmento.
# La posición mundial se reconstruye cada frame desde el segmento.
# ─────────────────────────────────────────────────────────────────

func _state_ladder(delta: float) -> void:

	body.velocity = Vector3.ZERO

	# ── Saltar fuera ──────────────────────────────────────────────
	if Input.is_action_just_pressed("jump"):
		_log("escalera — salto afuera")
		var cam_fwd = -camera.global_transform.basis.z
		cam_fwd.y   = 0.0
		cam_fwd     = cam_fwd.normalized()
		_release(cam_fwd * 4.0 + Vector3.UP * 5.0)
		return

	# ── Soltarse ────────────────────────────────────────────────
	if Input.is_action_just_pressed("crouch"):
		_log("escalera — suelta (control) — caída libre")
		_release(Vector3.ZERO, false)
		return

	# ── Input de movimiento ───────────────────────────────────────
	var pressing_up   = Input.is_action_pressed("move_forward")
	var pressing_down = Input.is_action_pressed("move_back")

	if pressing_up and not pressing_down:
		_ladder_dir = 1.0
	elif pressing_down and not pressing_up:
		_ladder_dir = -1.0
	else:
		_ladder_dir = 0.0
		_ladder_pulse_timer = 0.0
		body.global_position = _current_segment.get_position_at(_current_progress)
		return

	# ── Pulso rítmico ─────────────────────────────────────────────
	var pulse_time = ladder_pulse_time
	if _current_segment.get("move_speed"):
		pulse_time /= max(_current_segment.move_speed, 0.1)

	_ladder_pulse_timer += delta

	if _ladder_pulse_timer >= pulse_time:
		_ladder_pulse_timer -= pulse_time

		# Avanzar progress según la longitud real del segmento.
		# Así la velocidad es consistente independientemente del largo.
		var seg_len      = _current_segment.get_length()
		var progress_step = ladder_pulse_speed * pulse_time / max(seg_len, 0.001)
		var new_progress  = _current_progress + _ladder_dir * progress_step

		# ── Transición entre segmentos (stacking) ─────────────────
		if new_progress > 1.0:
			var neighbour = _current_segment.get_neighbour_up()
			if neighbour != null:
				_current_segment  = neighbour
				_current_progress = new_progress - 1.0
				_log("escalera — transición a vecino superior: %s" % neighbour.name)
			else:
				_current_progress = 1.0  # tope — no hay más segmento
		elif new_progress < 0.0:
			var neighbour = _current_segment.get_neighbour_down()
			if neighbour != null:
				_current_segment  = neighbour
				_current_progress = 1.0 + new_progress
				_log("escalera — transición a vecino inferior: %s" % neighbour.name)
			else:
				_current_progress = 0.0  # fondo — no hay más segmento
		else:
			_current_progress = new_progress

		_log("escalera — progress: %.2f" % _current_progress)

	# Reconstruir posición mundial desde el segmento.
	body.global_position = _current_segment.get_position_at(_current_progress)

# ─────────────────────────────────────────────────────────────────
# ── SHIMMY — validación de borde ─────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _update_shimmy_probes() -> void:
	var result_left  : Dictionary = _edge_continues(_along_wall * -1.0)
	var result_right : Dictionary = _edge_continues(_along_wall *  1.0)

	_can_go_left  = not result_left.is_empty()
	_can_go_right = not result_right.is_empty()

	var new_normal : Vector3 = Vector3.ZERO
	if _shimmy_dir < 0.0 and _can_go_left:
		new_normal = result_left["wall_normal"]
	elif _shimmy_dir > 0.0 and _can_go_right:
		new_normal = result_right["wall_normal"]

	if new_normal != Vector3.ZERO and new_normal != _hang_normal:
		var lado : String = "derecha" if (_shimmy_dir > 0.0 or (not _can_go_left and _can_go_right)) else "izquierda"
		_log("normal cambia: " + str(_hang_normal.snapped(Vector3(0.01,0.01,0.01))) + " -> " + str(new_normal.snapped(Vector3(0.01,0.01,0.01))) + " | lado: " + lado)
		_hang_normal = new_normal
		_along_wall  = Vector3.UP.cross(_hang_normal).normalized()

		var ref_point : Vector3 = Vector3.ZERO
		if _shimmy_dir < 0.0 and _can_go_left:
			ref_point = result_left["wall_point"]
		elif _shimmy_dir > 0.0 and _can_go_right:
			ref_point = result_right["wall_point"]
		elif _can_go_right:
			ref_point = result_right["wall_point"]
		elif _can_go_left:
			ref_point = result_left["wall_point"]

		if ref_point != Vector3.ZERO:
			_hang_position_target = Vector3(ref_point.x, _hang_position.y, ref_point.z)
			_hang_position_target -= _hang_normal * HANG_WALL_GAP
			_transitioning_face = true

	_calculate_tangent()

func _calculate_tangent() -> void:
	if _shimmy_dir == 0.0:
		return

	var centroid_left  : Vector3 = Vector3.ZERO
	var centroid_right : Vector3 = Vector3.ZERO
	var count_left  : int = 0
	var count_right : int = 0

	for offset in PROBE_OFFSETS_INNER:
		var r = _edge_continues(_along_wall * offset)
		if r.is_empty():
			continue
		if offset < 0.0:
			centroid_left  += r["wall_point"]
			count_left     += 1
		else:
			centroid_right += r["wall_point"]
			count_right    += 1

	if count_left == 0 or count_right == 0:
		return

	centroid_left  /= float(count_left)
	centroid_right /= float(count_right)

	var raw_tangent : Vector3 = centroid_right - centroid_left
	raw_tangent.y = 0.0
	if raw_tangent.length() < 0.001:
		return
	var target_tangent : Vector3 = raw_tangent.normalized()

	_along_wall = _along_wall.lerp(target_tangent, 0.15)
	_along_wall.y = 0.0
	if _along_wall.length() < 0.001:
		return
	_along_wall = _along_wall.normalized()

func _apply_virtual_normal() -> void:
	var sum_normal   : Vector3 = Vector3.ZERO
	var sum_position : Vector3 = Vector3.ZERO
	var count        : int     = 0

	var space = body.get_world_3d().direct_space_state
	var edge_y_offset : float = abs(HANG_OFFSET_Y) - 0.15
	var probe_origin  : Vector3 = _hang_position + Vector3(0.0, edge_y_offset, 0.0)

	for offset in PROBE_OFFSETS_INNER:
		var probe     : Vector3 = probe_origin + _along_wall * offset
		var to_wall   : Vector3 = -_hang_normal
		var wall_from : Vector3 = probe + to_wall * -0.2
		var wall_to   : Vector3 = probe + to_wall *  1.0
		var wall_q = PhysicsRayQueryParameters3D.create(wall_from, wall_to)
		wall_q.exclude = [body]
		var hit = space.intersect_ray(wall_q)

		if hit.is_empty():
			continue
		var max_normal_y : float = sin(deg_to_rad(30.0))
		if abs(hit["normal"].y) > max_normal_y:
			continue

		sum_normal   += hit["normal"]
		sum_position += hit["position"]
		count        += 1

	if count == 0:
		return

	var avg_normal   : Vector3 = (sum_normal / float(count)).normalized()
	var avg_position : Vector3 = sum_position / float(count)

	_hang_normal  = avg_normal
	_along_wall   = Vector3.UP.cross(_hang_normal).normalized()
	_hang_position = Vector3(
		avg_position.x - avg_normal.x * HANG_WALL_GAP,
		_hang_position.y,
		avg_position.z - avg_normal.z * HANG_WALL_GAP
	)

func _edge_continues(lateral_dir: Vector3, dist: float = -1.0) -> Dictionary:
	var probe_dist : float = dist if dist > 0.0 else shimmy_max_dist
	var edge_y_offset : float = abs(HANG_OFFSET_Y) - 0.15
	var probe_origin : Vector3 = _hang_position + Vector3(0.0, edge_y_offset, 0.0)
	var space = body.get_world_3d().direct_space_state

	var probe = probe_origin + lateral_dir * probe_dist

	var to_wall   : Vector3 = -_hang_normal
	var wall_from = probe + to_wall * -0.2
	var wall_to   = probe + to_wall *  1.0
	var wall_q = PhysicsRayQueryParameters3D.create(wall_from, wall_to)
	wall_q.exclude = [body]
	var wall_hit = space.intersect_ray(wall_q)

	DebugDraw.ray(wall_from, wall_to, Color.BLUE if wall_hit else Color.GRAY)

	if wall_hit.is_empty():
		return {}

	var max_normal_y : float = sin(deg_to_rad(30.0))
	if abs(wall_hit["normal"].y) > max_normal_y:
		DebugDraw.ray(wall_from, wall_to, Color.RED)
		return {}

	var edge_from = wall_hit["position"] + Vector3.UP * 0.4 - _hang_normal * 0.05
	var edge_to   = edge_from + Vector3.DOWN * 0.7
	var edge_q = PhysicsRayQueryParameters3D.create(edge_from, edge_to)
	edge_q.exclude = [body]
	var edge_hit = space.intersect_ray(edge_q)

	DebugDraw.ray(edge_from, edge_to, Color.GREEN if edge_hit else Color.RED)

	if edge_hit.is_empty():
		return {}

	return { "wall_normal": wall_hit["normal"], "wall_point": wall_hit["position"] }

# ─────────────────────────────────────────────────────────────────
# ── SALIDA ───────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _release(exit_velocity: Vector3, use_cooldown: bool = true) -> void:
	body.velocity    = exit_velocity
	_current_segment = null

	if use_cooldown:
		detector.start_cooldown()

	_change_state(State.IDLE)

func _change_state(new_state: State) -> void:
	var was_active = is_active()
	var old_name   = State.keys()[state]
	state          = new_state
	var now_active = is_active()

	_log("%s → %s" % [old_name, State.keys()[new_state]])

	if new_state != State.HANGING:
		_can_go_left  = false
		_can_go_right = false
		_shimmy_dir   = 0.0

	if not was_active and now_active:
		movement.freeze()
		traversal_started.emit()
	elif was_active and not now_active:
		traversal_ended.emit()
# ─────────────────────────────────────────────────────────────────
# ── DEBUG ────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _draw_debug() -> void:
	if state == State.IDLE:
		return

	if state != State.LADDER:
		DebugDraw.sphere(_hang_position, 0.2, Color.MAGENTA)
		DebugDraw.ray(_hang_position, _hang_position + _hang_normal * 0.8, Color.MAGENTA)
		DebugDraw.ray(_hang_position - _along_wall * 0.5,
					  _hang_position + _along_wall * 0.5, Color.YELLOW)

		if state == State.HANGING:
			var probe_left  = _hang_position + _along_wall * -shimmy_max_dist
			var probe_right = _hang_position + _along_wall *  shimmy_max_dist
			DebugDraw.sphere(probe_left,  0.1, Color.GREEN if _can_go_left  else Color.RED)
			DebugDraw.sphere(probe_right, 0.1, Color.GREEN if _can_go_right else Color.RED)
			for offset in PROBE_OFFSETS_INNER:
				var col = Color.CYAN if offset < 0.0 else Color.YELLOW
				DebugDraw.sphere(_hang_position + _along_wall * offset, 0.06, col)

	if state == State.LADDER and _current_segment != null:
		var pos = _current_segment.get_position_at(_current_progress)
		DebugDraw.sphere(pos, 0.2, Color.ORANGE)
		# Mostrar el eje del segmento completo
		if _current_segment.start_marker and _current_segment.end_marker:
			DebugDraw.ray(
				_current_segment.start_marker.global_position,
				_current_segment.end_marker.global_position,
				Color.ORANGE
			)
		# Esfera en start y end
		if _current_segment.start_marker:
			DebugDraw.sphere(_current_segment.start_marker.global_position, 0.15, Color.GREEN)
		if _current_segment.end_marker:
			DebugDraw.sphere(_current_segment.end_marker.global_position, 0.15, Color.RED)
