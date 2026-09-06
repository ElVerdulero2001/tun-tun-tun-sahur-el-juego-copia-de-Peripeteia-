class_name TraversalDebug
extends Node3D

## Observador puro de Parkour V2 (Fase 7; doc de arquitectura V0.3, sección
## 11). Dibuja y reporta en texto lo que YA calculan Detector/Controller —
## nunca decide nada ni toca input, estado, física, transform, velocity,
## collider ni lease de nadie.
##
## Solo LEE:
##   - motor.snapshot() / motor.global_transform / motor.global_position
##     (PlayerMotor, API pública).
##   - detector.collect() / detector.is_pose_clear() (TraversalDetector,
##     pasivo por contrato — confirmado por el test de pasividad de Fase 3;
##     llamar collect() desde acá, además de desde el Controller, no viola
##     esa pasividad: es una query sin efectos secundarios, se puede llamar
##     tantas veces como haga falta).
##   - controller.get_estado() / get_segmento_activo() / get_progreso_activo()
##     / get_pose_objetivo() / hubo_motivo_salida() / get_ultimo_motivo_salida()
##     — todos getters de solo lectura agregados en esta fase.
##
## NUNCA llama begin_traversal()/apply_traversal_pose()/end_traversal(),
## nunca construye un TraversalIntent, nunca lee Input.*, nunca escribe
## nada de PlayerMotor/TraversalController/TraversalDetector.
##
## enabled en false corta _process() en _ready() y no crea un solo nodo
## hijo (ni ImmediateMesh, ni Label, ni CanvasLayer) — cero costo por
## frame, y ningún otro script del sistema sabe que este nodo existe, así
## que apagarlo no cambia el comportamiento del juego en absoluto.

@export var enabled: bool = true
@export var motor: PlayerMotor
@export var detector: TraversalDetector
@export var controller: TraversalController

@export_group("Colores")
@export var color_ledge_valido: Color = Color(0.2, 1.0, 0.3)
@export var color_ledge_invalido: Color = Color(1.0, 0.3, 0.2)
@export var color_ladder: Color = Color(0.3, 0.6, 1.0)
@export var color_segmento_activo: Color = Color(1.0, 0.85, 0.1)
@export var color_pose_objetivo: Color = Color(1.0, 1.0, 1.0)

const _RADIO_CRUZ := 0.12
const _ALPHA_VECINO := 0.4

var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _label: Label


func _ready() -> void:
	if not enabled:
		set_process(false)
		return

	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	_mesh_instance.top_level = true  # dibuja en espacio de mundo, ignora el transform del Player
	_mesh_instance.material_override = _crear_material_lineas()
	add_child(_mesh_instance)

	var canvas := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(_label)
	add_child(canvas)


func _crear_material_lineas() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true  # visible a través de geometría, como cualquier debug draw
	return material


func _process(_delta: float) -> void:
	if not enabled or motor == null or detector == null or controller == null:
		return

	var oportunidades := detector.collect(motor.snapshot())
	_dibujar(oportunidades)
	_actualizar_texto(oportunidades)


# ── Dibujo (ImmediateMesh, líneas y cruces en espacio de mundo) ───────
func _dibujar(oportunidades: TraversalOpportunities) -> void:
	_mesh.clear_surfaces()

	# ImmediateMesh.surface_end() falla (ERROR real, no solo silencioso) si
	# no se agregó ningún vértice — pasa todo el tiempo mientras no hay
	# ledge, ladder, segmento activo ni traversal en curso. Se decide ANTES
	# de abrir la superficie, con la misma condición que ya usa cada
	# _dibujar_*() por separado para no dibujar nada.
	var hay_algo_que_dibujar := (
		oportunidades.ledge != null
		or oportunidades.ladder != null
		or controller.get_segmento_activo() != null
		or controller.get_estado() != TraversalState.Value.FREE)
	if not hay_algo_que_dibujar:
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_dibujar_ledge(oportunidades.ledge)
	_dibujar_ladder(oportunidades.ladder)
	_dibujar_segmento_activo()
	_dibujar_pose_objetivo()
	_mesh.surface_end()


func _dibujar_ledge(ledge: LedgeCandidate) -> void:
	if ledge == null:
		return
	var color := color_ledge_valido if ledge.is_valid else color_ledge_invalido
	_linea(motor.global_position, ledge.edge_position, color)
	_cruz(ledge.edge_position, color)
	_cruz(ledge.landing_position, color)
	_linea(ledge.edge_position, ledge.edge_position + ledge.wall_normal * 0.5, color)
	if ledge.segment != null:
		_dibujar_segmento(ledge.segment, color_segmento_activo.lerp(Color.BLACK, 0.5))


func _dibujar_ladder(ladder: LadderCandidate) -> void:
	if ladder == null or ladder.segment == null:
		return
	_dibujar_segmento(ladder.segment, color_ladder)
	_cruz(ladder.segment.get_position_at(ladder.initial_progress), color_ladder)


func _dibujar_segmento_activo() -> void:
	var segmento := controller.get_segmento_activo()
	if segmento == null:
		return
	_dibujar_segmento(segmento, color_segmento_activo)
	_cruz(segmento.get_position_at(controller.get_progreso_activo()), color_segmento_activo)


func _dibujar_segmento(segmento: TraversalSegment, color: Color) -> void:
	_linea(segmento.get_position_at(0.0), segmento.get_position_at(1.0), color)
	var color_vecino := Color(color.r, color.g, color.b, color.a * _ALPHA_VECINO)
	var vecino_up := segmento.get_neighbour_up()
	if vecino_up != null:
		_linea(segmento.get_position_at(1.0), vecino_up.get_position_at(0.0), color_vecino)
	var vecino_down := segmento.get_neighbour_down()
	if vecino_down != null:
		_linea(segmento.get_position_at(0.0), vecino_down.get_position_at(1.0), color_vecino)


func _dibujar_pose_objetivo() -> void:
	if controller.get_estado() == TraversalState.Value.FREE:
		return
	var pose := controller.get_pose_objetivo()
	_cruz(pose.origin, color_pose_objetivo)
	_linea(pose.origin, pose.origin - pose.basis.z * 0.4, color_pose_objetivo)


func _linea(a: Vector3, b: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(b)


func _cruz(centro: Vector3, color: Color) -> void:
	_linea(centro - Vector3.RIGHT * _RADIO_CRUZ, centro + Vector3.RIGHT * _RADIO_CRUZ, color)
	_linea(centro - Vector3.UP * _RADIO_CRUZ, centro + Vector3.UP * _RADIO_CRUZ, color)
	_linea(centro - Vector3.BACK * _RADIO_CRUZ, centro + Vector3.BACK * _RADIO_CRUZ, color)


# ── Overlay de texto ───────────────────────────────────────────────────
func _actualizar_texto(oportunidades: TraversalOpportunities) -> void:
	var lineas: Array[String] = []
	lineas.append("Estado: %s" % TraversalState.Value.keys()[controller.get_estado()])
	lineas.append(_texto_ledge(oportunidades.ledge))
	lineas.append(_texto_ladder(oportunidades.ladder))

	if controller.get_segmento_activo() != null:
		lineas.append("Segmento activo: progreso=%.2f" % controller.get_progreso_activo())

	if controller.get_estado() != TraversalState.Value.FREE:
		var pose := controller.get_pose_objetivo()
		lineas.append("Pose objetivo: (%.2f, %.2f, %.2f)" % [pose.origin.x, pose.origin.y, pose.origin.z])

	if controller.hubo_motivo_salida():
		var nombre_motivo: String = TraversalExitReason.Value.keys()[controller.get_ultimo_motivo_salida()]
		lineas.append("Último motivo de salida: %s" % nombre_motivo)

	_label.text = "\n".join(lineas)


func _texto_ledge(ledge: LedgeCandidate) -> String:
	if ledge == null:
		return "Ledge: ninguno"
	return "Ledge: %s score=%.2f%s" % [
		"valido" if ledge.is_valid else "invalido",
		ledge.score,
		" (shimmy)" if ledge.segment != null else ""]


func _texto_ladder(ladder: LadderCandidate) -> String:
	if ladder == null:
		return "Ladder: ninguno"
	return "Ladder: %s alineacion=%.2f" % [
		"valido" if ladder.is_valid else "invalido", ladder.approach_alignment]
