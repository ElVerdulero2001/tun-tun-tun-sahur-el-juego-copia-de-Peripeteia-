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
enum State { IDLE, SNAPPING, HANGING, CLIMBING }
var state : State = State.IDLE

# ── Parámetros ────────────────────────────────────────────────────
@export var snap_speed     : float = 14.0
@export var snap_threshold : float = 0.08
@export var climb_speed    : float = 4.0
@export var shimmy_speed   : float = 2.0
@export var shimmy_max_dist: float = 0.5    # cuánto puede sondear lateral antes de cortar
@export var jump_force     : float = 6.5

# ── Referencias ───────────────────────────────────────────────────
var body     : CharacterBody3D
var camera   : Camera3D
var movement : Node
var detector : Node

# ── Estado interno ────────────────────────────────────────────────
var _hang_position : Vector3 = Vector3.ZERO   # dónde están las "manos"
var _hang_normal   : Vector3 = Vector3.ZERO   # normal de la pared (apunta hacia afuera)
var _along_wall    : Vector3 = Vector3.ZERO   # vector lateral a lo largo de la pared

# ── Estado del shimmy — se recalcula cada frame en HANGING ────────
# Guardamos el resultado del chequeo lateral para poder dibujarlo
# y usarlo sin recalcularlo. Se actualiza en _update_shimmy_probes().
var _can_go_left  : bool = false
var _can_go_right : bool = false

# ── Dirección de shimmy del último frame ──────────────────────────
# Guardamos qué hizo el shimmy en el frame actual para poder mostrarlo
# en el panel de debug. 0 = quieto, -1 = izquierda, +1 = derecha.
# Cuando es 0 pero el jugador SÍ apretaba una tecla, significa que el
# borde estaba bloqueado de ese lado — un dato clave para debuggear.
var _shimmy_dir : float = 0.0

# ── Log de eventos ────────────────────────────────────────────────
# Lista circular de las últimas transiciones y decisiones importantes.
# Solo se escribe cuando PASA algo — nunca cada frame. Así el log es
# la HISTORIA del sistema, no ruido. El panel de debug lo lee tal cual.
const LOG_MAX : int = 12
var _event_log : Array = []   # cada uno: { "t": tiempo, "msg": texto }

# Registra un evento en el log con marca de tiempo.
func _log(msg: String) -> void:
	var t = Time.get_ticks_msec() / 1000.0
	_event_log.append({ "t": t, "msg": msg })
	# Mantener la lista acotada: descartar lo más viejo.
	while _event_log.size() > LOG_MAX:
		_event_log.pop_front()

# Desfase vertical del CENTRO del body respecto al borde, al colgarse.
# El body es una cápsula de 2.0 m → su centro está a 1.0 m de la cabeza.
# -1.15 deja la cabeza apenas debajo del borde y el cuerpo colgando.
# OJO: este valor depende de la altura de la cápsula. Si cambia, ajustar.
const HANG_OFFSET_Y : float = -0.55

# Separación del CENTRO del body respecto a la cara de la pared.
# Tiene que ser >= el radio de la cápsula (0.5) o el body penetra la
# pared y el motor lo frena antes de llegar al destino del snap.
const HANG_WALL_GAP : float = -0.68

# Red de seguridad: si el SNAPPING no termina en este tiempo, algo
# salió mal (destino inalcanzable). En vez de quedar clavados para
# siempre, abortamos y soltamos. Nunca un estado sin salida.
const SNAP_TIMEOUT : float = 1.0
var _snap_timer : float = 0.0

# ─────────────────────────────────────────────────────────────────
func setup(p_body: CharacterBody3D, p_camera: Camera3D, p_movement: Node, p_detector: Node) -> void:
	body     = p_body
	camera   = p_camera
	movement = p_movement
	detector = p_detector
	detector.candidate_found.connect(_on_candidate_found)

func is_active() -> bool:
	return state != State.IDLE

# Devuelve el nombre del estado actual como texto, para debug.
func get_state_name() -> String:
	return State.keys()[state]

# ─────────────────────────────────────────────────────────────────
# ── REPORTE DE DEBUG ─────────────────────────────────────────────
# El panel de debug lee de acá. El TraversalController no sabe NADA
# del panel — solo expone su estado interno. El panel se acopla a
# este diccionario, no a las variables privadas. Si mañana cambia
# algo interno, solo se toca este método.
# ─────────────────────────────────────────────────────────────────
func get_debug_state() -> Dictionary:
	# Leemos el input crudo acá mismo para que el panel pueda mostrar
	# QUÉ teclas estás apretando vs. qué decide el sistema. La brecha
	# entre esas dos cosas es donde viven la mayoría de los bugs.
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
		# Input crudo — lo que el jugador APRIETA, sin filtrar.
		"in_left"      : Input.is_action_pressed("move_left"),
		"in_right"     : Input.is_action_pressed("move_right"),
		"in_fwd"       : Input.is_action_pressed("move_forward"),
		"in_back"      : Input.is_action_pressed("move_back"),
		"in_jump"      : Input.is_action_pressed("jump"),
	}

# Devuelve el log de eventos para que el panel lo muestre.
func get_event_log() -> Array:
	return _event_log

# ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	DebugDraw.clear()

	# Solo corre cuando el traversal esta activo.
	# Cuando esta en IDLE, el MovementController tiene el control.
	if state == State.IDLE:
		return

	match state:
		State.SNAPPING: _state_snapping(delta)
		State.HANGING:  _state_hanging(delta)
		State.CLIMBING: _state_climbing(delta)

	_draw_debug()

# ─────────────────────────────────────────────────────────────────
# ── ENTRADA ──────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _on_candidate_found(candidate: Dictionary) -> void:
	# Solo enganchamos si estamos completamente libres.
	if state != State.IDLE:
		return

	_hang_normal = candidate["wall_normal"]
	# El vector lateral a lo largo de la pared (perpendicular a la normal y a UP).
	_along_wall  = Vector3.UP.cross(_hang_normal).normalized()

	var edge = candidate["edge_point"]
	_hang_position  = Vector3(edge.x, edge.y + HANG_OFFSET_Y, edge.z)
	_hang_position -= _hang_normal * HANG_WALL_GAP

	_snap_timer = 0.0
	_log("candidato aceptado — snap iniciado")
	_change_state(State.SNAPPING)

# ─────────────────────────────────────────────────────────────────
# ── SNAPPING — mover el body hacia el borde, sin aceptar input ───
# ─────────────────────────────────────────────────────────────────

func _state_snapping(delta: float) -> void:
	body.velocity = Vector3.ZERO

	# Único input aceptado: cancelar con salto.
	if Input.is_action_just_pressed("jump"):
		_release(Vector3.UP * jump_force)
		return

	# Red de seguridad: si el snap tarda demasiado, el destino es
	# inalcanzable. Abortamos en vez de quedar clavados para siempre.
	_snap_timer += delta
	if _snap_timer > SNAP_TIMEOUT:
		push_warning("TraversalController: SNAPPING abortado por timeout — destino inalcanzable.")
		_log("SNAP abortado — TIMEOUT (destino inalcanzable)")
		_release(_hang_normal * 2.0)
		return

	body.global_position = body.global_position.lerp(_hang_position, snap_speed * delta)

	if body.global_position.distance_to(_hang_position) < snap_threshold:
		body.global_position = _hang_position
		_change_state(State.HANGING)

# ─────────────────────────────────────────────────────────────────
# ── HANGING — colgado. Acepta TODO el input. ─────────────────────
# Maneja tanto quedarse quieto como el shimmy lateral.
# ─────────────────────────────────────────────────────────────────

func _state_hanging(delta: float) -> void:
	body.velocity = Vector3.ZERO

	# ── Salir hacia arriba (salto) ────────────────────────────────
	if Input.is_action_just_pressed("jump"):
		_log("release por SALTO")
		_release(Vector3.UP * jump_force)
		return

	# ── Soltar el borde (hacia atrás) ─────────────────────────────
	if Input.is_action_just_pressed("move_back"):
		_log("release por SOLTAR (atras)")
		_release(_hang_normal * 3.5 + Vector3.UP * 1.0)
		return

	# ── Trepar ────────────────────────────────────────────────────
	if Input.is_action_just_pressed("move_forward"):
		_change_state(State.CLIMBING)
		return

	# ── Chequeo del terreno — SIEMPRE, ambos lados, todos los frames.
	# Esto corre haya o no input. Así sus rayos de debug se dibujan
	# de forma continua y vemos el estado del borde sin tocar nada.
	_update_shimmy_probes()

	# ── Shimmy lateral ────────────────────────────────────────────
	# El input solo decide si nos movemos. El chequeo ya está hecho.
	# Distinguimos tres casos para el log:
	#   - apretás y hay borde  → te movés (no se loggea, es cada frame)
	#   - apretás y NO hay borde → bloqueado (se loggea una vez)
	#   - no apretás → quieto
	var dir := 0.0
	var pressing_left  = Input.is_action_pressed("move_left")
	var pressing_right = Input.is_action_pressed("move_right")

	if pressing_left and _can_go_left:
		dir = -1.0
	elif pressing_right and _can_go_right:
		dir = 1.0

	# Detección de "shimmy bloqueado": apretás hacia un lado pero ese
	# lado no tiene borde. Solo se loggea en el FRAME en que empieza
	# el bloqueo (cuando antes nos movíamos o estábamos quietos), no
	# cada frame, para no inundar el log.
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
		_hang_position += step

	# Anclar SIEMPRE el body a _hang_position.
	# Cubre los tres casos: quieto, shimmy exitoso y shimmy bloqueado.
	body.global_position = _hang_position

# ─────────────────────────────────────────────────────────────────
# ── CLIMBING — trepar por encima del borde ───────────────────────
# ─────────────────────────────────────────────────────────────────

func _state_climbing(delta: float) -> void:
	body.velocity = Vector3.ZERO

	var target = _hang_position + Vector3.UP * 1.9 - _hang_normal * 0.4
	body.global_position = body.global_position.lerp(target, climb_speed * delta)

	if body.global_position.distance_to(target) < 0.12:
		body.global_position = target
		_release(-_hang_normal * 1.5)

# ─────────────────────────────────────────────────────────────────
# ── VALIDACIÓN DEL BORDE PARA SHIMMY ─────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _update_shimmy_probes() -> void:
	# Recalcula si el borde continúa a izquierda y derecha.
	# Se llama todos los frames en HANGING. Sus raycasts dibujan
	# debug de forma continua, así que los rayos quedan fijos en
	# pantalla mientras estás colgado — sin necesidad de apretar nada.
	_can_go_left  = _edge_continues(_along_wall * -1.0)
	_can_go_right = _edge_continues(_along_wall *  1.0)

func _edge_continues(lateral_dir: Vector3) -> bool:
	# Devuelve true si hay pared + borde en la dirección lateral pedida.
	# Buscamos un poco por debajo del filo del borde (HANG_OFFSET_Y - 0.15)
	# para que el raycast pegue en la cara lateral, no en el filo donde
	# la geometria es inestable. El alcance del raycast (0.8) tiene que
	# superar el HANG_WALL_GAP o termina en el aire sin pegar nada.
	var edge_y_offset : float = abs(HANG_OFFSET_Y) - 0.15
	var probe_origin : Vector3 = _hang_position + Vector3(0.0, edge_y_offset, 0.0)
	var space = body.get_world_3d().direct_space_state

	# Punto de sondeo: desplazado lateralmente desde la altura del borde.
	var probe = probe_origin + lateral_dir * shimmy_max_dist

	# TEST: confirmar que la funcion se ejecuta.
	print("_edge_continues probe: ", probe, " dir: ", lateral_dir)

	# 1. Raycast hacia la pared (en dirección -normal, hacia adentro).
	# El alcance tiene que superar el HANG_WALL_GAP (0.68m) o el raycast
	# termina en el aire antes de llegar a la cara lateral del objeto.
	var wall_from = probe + _hang_normal * 0.2
	var wall_to   = probe - _hang_normal * 0.8
	var wall_q = PhysicsRayQueryParameters3D.create(wall_from, wall_to)
	wall_q.exclude = [body]
	var wall_hit = space.intersect_ray(wall_q)

	# Debug: rayo de pared — naranja si pega, gris si no.
	DebugDraw.ray(wall_from, wall_to, Color.BLUE if wall_hit else Color.GRAY)

	if wall_hit.is_empty():
		return false

	# Validar que la superficie es suficientemente vertical.
	# Rampas e inclinadas tienen normal con componente Y alta.
	# Mismo umbral que parkour_detector (30 grados).
	var max_normal_y : float = sin(deg_to_rad(30.0))
	if abs(wall_hit["normal"].y) > max_normal_y:
		DebugDraw.ray(wall_from, wall_to, Color.RED)
		return false

	# 2. Raycast hacia abajo desde arriba del hit, para confirmar el borde.
	var edge_from = wall_hit["position"] + Vector3.UP * 0.4 - _hang_normal * 0.05
	var edge_to   = edge_from + Vector3.DOWN * 0.7
	var edge_q = PhysicsRayQueryParameters3D.create(edge_from, edge_to)
	edge_q.exclude = [body]
	var edge_hit = space.intersect_ray(edge_q)

	# Debug: rayo de borde — verde si encuentra, rojo si no.
	DebugDraw.ray(edge_from, edge_to, Color.GREEN if edge_hit else Color.RED)

	return not edge_hit.is_empty()

# ─────────────────────────────────────────────────────────────────
# ── SALIDA ───────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _release(exit_velocity: Vector3) -> void:
	body.velocity = exit_velocity
	detector.start_cooldown()
	_change_state(State.IDLE)

# ─────────────────────────────────────────────────────────────────
func _change_state(new_state: State) -> void:
	var was_active = is_active()
	var old_name = State.keys()[state]
	state = new_state
	var new_name = State.keys()[new_state]
	var now_active = is_active()

	# Registrar la transición en el log — esto es la espina dorsal
	# del debug: cada cambio de estado queda anotado con su tiempo.
	_log("%s → %s" % [old_name, new_name])

	# Al salir de HANGING, los probes laterales dejan de tener sentido.
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
# Se dibuja SIEMPRE que el traversal está activo. Nunca a ciegas.
# ─────────────────────────────────────────────────────────────────

func _draw_debug() -> void:
	if state == State.IDLE:
		return

	# Punto de agarre — esfera magenta.
	DebugDraw.sphere(_hang_position, 0.2, Color.MAGENTA)
	# Normal de la pared — flecha magenta hacia afuera.
	DebugDraw.ray(_hang_position, _hang_position + _hang_normal * 0.8, Color.MAGENTA)
	# Vector lateral a lo largo de la pared — flecha amarilla a ambos lados.
	DebugDraw.ray(_hang_position - _along_wall * 0.5,
				  _hang_position + _along_wall * 0.5, Color.YELLOW)

	# Marcadores de los puntos de sondeo lateral — esferas chicas.
	# Verde si el borde continúa por ese lado, rojo si no.
	# Quedan visibles SIEMPRE que estás colgado.
	if state == State.HANGING:
		var probe_left  = _hang_position + _along_wall * -shimmy_max_dist
		var probe_right = _hang_position + _along_wall *  shimmy_max_dist
		DebugDraw.sphere(probe_left,  0.1, Color.GREEN if _can_go_left  else Color.RED)
		DebugDraw.sphere(probe_right, 0.1, Color.GREEN if _can_go_right else Color.RED)
