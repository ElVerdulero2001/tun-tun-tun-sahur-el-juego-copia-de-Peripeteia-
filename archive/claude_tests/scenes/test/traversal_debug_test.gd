extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Parkour V2 · Fase 7.
##
## Verifica que TraversalDebug es un observador puro: habilitado, dibujando
## y actualizando texto cada frame (incluso con una traversal REAL activa),
## no cambia transform/velocity/lease/estado de nadie. Deshabilitado, no
## crea un solo nodo hijo. No prueba el contenido visual en sí (líneas,
## colores, texto) — eso requiere ojos humanos, no headless; ver la
## verificación manual de scenes/test/parkour_playground.tscn.
##
## Misma zona flotante sin piso que el resto de la suite de Fase 4-6
## (traversal_controller_test.tscn): sin piso, is_on_floor() da false de
## verdad y el agarre de borde es automático al caer (sección 8).

@onready var player: PlayerMotor = $Player
@onready var controller: TraversalController = $Player/TraversalController
@onready var debug: TraversalDebug = $Player/TraversalDebug

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== PARKOUR V2 · FASE 7 · TraversalDebug (observador puro) =====")

	await _test_pasividad_en_free()
	await _test_pasividad_durante_traversal_activa()
	_test_deshabilitado_no_crea_nada()

	print("=============================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: TraversalDebug OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	get_tree().quit(_fallos)
	assert(_fallos == 0, "TraversalDebug no cumple el contrato de la Fase 7")


# ── Helpers ──────────────────────────────────────────────────────────
func _ubicar(pos: Vector3) -> void:
	for accion in ["move_forward", "move_back", "move_left", "move_right", "run", "crouch", "jump"]:
		Input.action_release(accion)
	player.global_position = pos
	player.global_rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO


func _avanzar_frames(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


func _esperar_estado(esperado: TraversalState.Value, max_frames: int = 30) -> bool:
	for i in max_frames:
		if controller.get_estado() == esperado:
			return true
		await get_tree().physics_frame
	return controller.get_estado() == esperado


# ── Pasividad en FREE (sin traversal activa) ──────────────────────────
## Apaga la física de Player y Controller por completo: con ambos
## _physics_process detenidos, la ÚNICA actividad restante por frame es
## _process() de TraversalDebug. Cualquier cambio en transform/velocity/
## estado durante esta ventana sería, por descarte, obra suya — a
## diferencia de dejar correr la física normal, donde la caída por
## gravedad cambiaría transform/velocity de todos modos y el chequeo no
## probaría nada.
func _test_pasividad_en_free() -> void:
	_ubicar(Vector3(0, 0, 0))  # con un borde válido delante (MuroA), para que collect() no sea trivial
	player.set_physics_process(false)
	controller.set_physics_process(false)

	var transform_antes := player.global_transform
	var velocity_antes := player.velocity

	for i in 5:
		await get_tree().process_frame

	_check(player.global_transform.is_equal_approx(transform_antes),
		"pasividad en FREE: TraversalDebug no cambia global_transform (física apagada, solo corre _process)")
	_check(player.velocity.is_equal_approx(velocity_antes),
		"pasividad en FREE: TraversalDebug no cambia velocity (física apagada, solo corre _process)")
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"pasividad en FREE: TraversalDebug no cambia el estado del controller (sigue en FREE)")

	player.set_physics_process(true)
	controller.set_physics_process(true)


# ── Pasividad con una traversal REAL activa ───────────────────────────
func _test_pasividad_durante_traversal_activa() -> void:
	_ubicar(Vector3(0, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"llega a HANGING normalmente (con TraversalDebug procesando cada frame)")

	var otro_dueno := Node.new()
	_check(player.begin_traversal(otro_dueno) == null,
		"pasividad: el lease sigue exclusivo del controller — TraversalDebug no lo tocó")
	otro_dueno.free()

	# El agarre (plan de recuperación de feel V1→V2, Parte 2) aplica el
	# desplazamiento COMPLETO hasta la pose de hang en un único
	# apply_traversal_pose(): la posición ya es la pose exacta desde este
	# primerísimo tick en HANGING, sin ningún tick de acomodo posterior.
	var pos_colgado := player.global_position
	await _avanzar_frames(10)
	_check(player.global_position.distance_to(pos_colgado) < 0.05,
		"pasividad: la pose de HANGING se mantiene anclada con TraversalDebug activo (deriva < 5cm)")

	_check(controller.get_segmento_activo() == null or controller.get_segmento_activo() is TraversalSegment,
		"getters nuevos: get_segmento_activo() no rompe nada aunque este borde no tenga shimmy")
	_check(controller.get_pose_objetivo().origin.distance_to(player.global_position) < 0.1,
		"getters nuevos: get_pose_objetivo() refleja la pose real de HANGING")

	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: release normal sigue funcionando con TraversalDebug activo")

	_check(controller.hubo_motivo_salida(), "getters nuevos: hubo_motivo_salida() es true tras el release")
	_check(controller.get_ultimo_motivo_salida() == TraversalExitReason.Value.HANG_RELEASED,
		"getters nuevos: get_ultimo_motivo_salida() reporta HANG_RELEASED")

	await _avanzar_frames(35)  # dejar vencer el cooldown, prolijidad para futuros tests en esta zona


# ── enabled = false: no debe crear un solo nodo hijo ──────────────────
func _test_deshabilitado_no_crea_nada() -> void:
	var debug_apagado := TraversalDebug.new()
	debug_apagado.enabled = false
	debug_apagado.motor = player
	add_child(debug_apagado)

	_check(debug_apagado.get_child_count() == 0,
		"enabled=false: no crea ImmediateMesh/MeshInstance3D ni Label/CanvasLayer")
	_check(not debug_apagado.is_processing(),
		"enabled=false: _process() queda apagado por completo")

	debug_apagado.queue_free()


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
