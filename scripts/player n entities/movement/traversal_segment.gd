# traversal_segment.gd
# Va directo en el StaticBody3D de la escalera (o cuerda, cable, etc).
# El grupo "ladder" también va en ese mismo nodo.
#
# CONCEPTO:
#   El segmento representa cualquier estructura recorrible.
#   El jugador no se mueve sobre el eje Y — se mueve sobre "progress":
#     0.0 = inicio (StartMarker)
#     1.0 = final  (EndMarker)
#   La posición mundial se reconstruye interpolando entre los dos markers.
#
# SETUP EN GODOT:
#   1. Asignar este script al StaticBody3D.
#   2. Agregar el grupo "ladder" al mismo nodo.
#   3. Crear dos nodos hijo Node3D llamados "StartMarker" y "EndMarker".
#      Posicionarlos en los extremos reales del recorrido.
#   4. Para stacking: asignar neighbour_up / neighbour_down en el Inspector
#      apuntando a los segmentos vecinos.

extends Node

# ── Tipo de segmento ──────────────────────────────────────────────
# Por ahora solo LADDER. En el futuro: ROPE, CABLE, CHAIN, etc.
enum SegmentType { LADDER, ROPE, CABLE, CHAIN }
@export var segment_type : SegmentType = SegmentType.LADDER

# ── Velocidad de movimiento ───────────────────────────────────────
# Multiplicador sobre la velocidad base del traversal.
@export var move_speed : float = 1.0

# ── Vecinos para stacking ─────────────────────────────────────────
# Si el jugador llega al final (progress >= 1.0) y existe neighbour_up,
# transiciona automáticamente a ese segmento.
# Idem para neighbour_down cuando progress <= 0.0.
@export var neighbour_up   : NodePath = NodePath("")
@export var neighbour_down : NodePath = NodePath("")

# ── Markers ───────────────────────────────────────────────────────
# Se resuelven en _ready() buscando nodos hijo con esos nombres.
var start_marker : Node3D = null
var end_marker   : Node3D = null

# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	start_marker = get_node_or_null("StartMarker")
	end_marker   = get_node_or_null("EndMarker")

	if start_marker == null:
		push_warning("TraversalSegment: '%s' no tiene StartMarker." % name)
	if end_marker == null:
		push_warning("TraversalSegment: '%s' no tiene EndMarker." % name)

# ─────────────────────────────────────────────────────────────────
# Devuelve la posición mundial para un progress dado (0.0 a 1.0).
# Interpolación lineal entre StartMarker y EndMarker.
func get_position_at(progress: float) -> Vector3:
	if start_marker == null or end_marker == null:
		return Vector3.ZERO
	return start_marker.global_position.lerp(end_marker.global_position, progress)

# Dirección de avance en este punto del segmento.
# Para segmentos lineales es siempre la misma.
# En el futuro, para cuerdas/cables se derivará de la curva.
func get_direction_at(_progress: float) -> Vector3:
	if start_marker == null or end_marker == null:
		return Vector3.UP
	return (end_marker.global_position - start_marker.global_position).normalized()

# Longitud total del segmento en unidades mundiales.
func get_length() -> float:
	if start_marker == null or end_marker == null:
		return 1.0
	return start_marker.global_position.distance_to(end_marker.global_position)

# Resuelve el vecino superior si existe.
func get_neighbour_up() -> Node:
	if neighbour_up == NodePath(""):
		return null
	return get_node_or_null(neighbour_up)

# Resuelve el vecino inferior si existe.
func get_neighbour_down() -> Node:
	if neighbour_down == NodePath(""):
		return null
	return get_node_or_null(neighbour_down)
