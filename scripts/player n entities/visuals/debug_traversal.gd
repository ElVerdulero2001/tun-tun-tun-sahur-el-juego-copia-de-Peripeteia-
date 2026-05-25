# debug_traversal.gd
# Panel de debug CONTEXTUAL del sistema de traversal.
#
# Filosofía: el debug_ui.gd general muestra siempre lo mismo (velocidad,
# ángulos). Este panel es distinto — solo aparece cuando el traversal
# está ACTIVO, y muestra exactamente lo que importa en ese contexto:
#   - el estado interno del TraversalController, frame a frame
#   - el INPUT CRUDO del jugador (qué teclas aprieta de verdad)
#   - un LOG de eventos: la HISTORIA de transiciones y decisiones
#
# Por qué esto: el shimmy y los bugs de máquina de estados no se cazan
# mirando geometría ni una foto del frame actual. Se cazan viendo la
# brecha entre "lo que el jugador aprieta" y "lo que el sistema decide",
# y viendo la SECUENCIA de eventos. Eso es lo que este panel hace visible.
#
# ── SETUP EN GODOT ────────────────────────────────────────────────
#   1. Crear un CanvasLayer nuevo en la escena (o como autoload).
#   2. Adentro, un nodo Label. Anclarlo arriba a la IZQUIERDA
#      (el debug_ui general suele estar a la otra esquina — así no
#      se pisan).
#   3. Asignar este script al CanvasLayer.
#   4. Para que el texto se lea: en el Label, poner una fuente
#      monoespaciada o al menos subir el font size. Un panel/fondo
#      oscuro detrás ayuda mucho a la legibilidad.
#
# No necesita que toques nada más. Encuentra al player solo, por grupo.

extends CanvasLayer

@onready var label : Label = $Label

# Lo buscamos por grupo, igual que hace tu debug_ui.gd.
@onready var player = get_tree().get_first_node_in_group("player")

# Referencia cacheada al TraversalController. Se resuelve una sola vez.
var _traversal : Node = null


func _ready() -> void:
	# Resolver el TraversalController una vez. Si no está, el panel
	# simplemente no muestra nada — nunca crashea.
	if player != null:
		_traversal = player.get_node_or_null("TraversalController")

	# Arranca oculto. Solo se muestra cuando el traversal se activa.
	visible = false


func _process(_delta: float) -> void:
	# Sin traversal, no hay nada que mostrar. Panel oculto.
	if _traversal == null:
		visible = false
		return

	var st : Dictionary = _traversal.get_debug_state()

	# ── Panel contextual: solo visible si el traversal está activo ──
	# Cuando estás en IDLE el panel desaparece y no estorba la vista.
	if not st["active"]:
		visible = false
		return

	visible = true
	label.text = _build_text(st)


# ─────────────────────────────────────────────────────────────────
# ── ARMADO DEL TEXTO ─────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _build_text(st: Dictionary) -> String:
	var lines : Array = []

	lines.append("══ TRAVERSAL DEBUG ══")
	lines.append("Estado: %s" % st["state"])
	lines.append("")

	# ── Sección según el estado ───────────────────────────────────
	# Cada estado tiene datos distintos que importan. Mostramos solo
	# los relevantes para no saturar.
	match st["state"]:
		"SNAPPING":
			_append_snapping(lines, st)
		"HANGING":
			_append_hanging(lines, st)
		"CLIMBING":
			_append_climbing(lines, st)

	# ── Input crudo ───────────────────────────────────────────────
	# Lo que el jugador APRIETA, siempre visible. Es la referencia
	# contra la cual comparar las decisiones del sistema.
	lines.append("")
	lines.append("── INPUT CRUDO ──")
	lines.append("  L:%s  R:%s  ADEL:%s  ATRAS:%s  SALTO:%s" % [
		_yn(st["in_left"]),  _yn(st["in_right"]),
		_yn(st["in_fwd"]),   _yn(st["in_back"]),
		_yn(st["in_jump"]),
	])

	# ── Log de eventos ────────────────────────────────────────────
	# La historia: las últimas transiciones y decisiones, con su tiempo.
	# Acá se ve la SECUENCIA, que es donde se cazan los bugs de estados.
	lines.append("")
	lines.append("── LOG (mas reciente abajo) ──")
	var entries : Array = _traversal.get_event_log()
	if entries.is_empty():
		lines.append("  (sin eventos aun)")
	else:
		for ev in entries:
			lines.append("  [%7.2f] %s" % [ev["t"], ev["msg"]])

	return "\n".join(lines)


# ── SNAPPING: lo que importa es si el snap progresa o se cuelga ──
func _append_snapping(lines: Array, st: Dictionary) -> void:
	lines.append("── SNAP ──")
	# Distancia restante al destino. Si NO baja, el snap está trabado.
	lines.append("  Dist al destino: %.3f" % st["snap_dist"])
	# Timer del timeout. Si llega a ~1.0, el destino es inalcanzable.
	lines.append("  Snap timer: %.2f / 1.00" % st["snap_timer"])
	lines.append("  Destino: %s" % _v3(st["hang_pos"]))


# ── HANGING: el estado clave para el bug del shimmy ──────────────
func _append_hanging(lines: Array, st: Dictionary) -> void:
	lines.append("── HANGING / SHIMMY ──")
	lines.append("  Pos de agarre: %s" % _v3(st["hang_pos"]))
	lines.append("  Normal pared:  %s" % _v3(st["hang_normal"]))
	lines.append("  Vector lateral: %s" % _v3(st["along_wall"]))
	lines.append("")

	# El corazón del debug del shimmy: comparar APRIETA vs PUEDE.
	# Si apretás L pero can_go_left es NO -> el borde está bloqueado.
	# Si apretás L y can_go_left es SI pero no te movés -> el problema
	# está en el movimiento mismo, no en la detección.
	lines.append("  ┌ IZQUIERDA")
	lines.append("  │  apretas:    %s" % _yn(st["in_left"]))
	lines.append("  │  puede ir:   %s" % _yn(st["can_go_left"]))
	lines.append("  └ DERECHA")
	lines.append("     apretas:    %s" % _yn(st["in_right"]))
	lines.append("     puede ir:   %s" % _yn(st["can_go_right"]))
	lines.append("")
	lines.append("  >> shimmy_dir: %s" % _shimmy_label(st["shimmy_dir"]))


# ── CLIMBING: lo que importa es si la trepada progresa ───────────
func _append_climbing(lines: Array, st: Dictionary) -> void:
	lines.append("── CLIMBING ──")
	lines.append("  Pos de agarre base: %s" % _v3(st["hang_pos"]))


# ─────────────────────────────────────────────────────────────────
# ── HELPERS DE FORMATO ───────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

# Booleano legible. SI bien claro, no/-- apagado.
func _yn(b: bool) -> String:
	return "SI" if b else "no"

# Vector3 compacto.
func _v3(v: Vector3) -> String:
	return "(%5.2f, %5.2f, %5.2f)" % [v.x, v.y, v.z]

# Traduce el shimmy_dir a algo legible.
# Recordá los valores especiales del traversal_controller:
#   -1 / +1  -> moviéndose
#    0       -> quieto
#   -99/+99  -> apretás ese lado pero está BLOQUEADO (sin borde)
func _shimmy_label(d: float) -> String:
	if d == -1.0:
		return "<<< moviendo IZQUIERDA"
	elif d == 1.0:
		return "moviendo DERECHA >>>"
	elif d == -99.0:
		return "IZQUIERDA bloqueada (sin borde)"
	elif d == 99.0:
		return "DERECHA bloqueada (sin borde)"
	else:
		return "quieto"
