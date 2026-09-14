extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Parkour V2 · Fase 6.
##
## Integración de TraversalController: FREE -> HANGING (agarre instantáneo,
## sin estado intermedio — plan de recuperación de feel V1→V2, Parte 2) ->
## MANTLING -> FREE (con la recuperación de la sección 9.1 ante bloqueo de
## mantle), shimmy lateral DENTRO de HANGING (sección 8), y FREE -> LADDER ->
## FREE para escaleras (sección 10). Cada zona (separada por X) es geometría
## flotante SIN piso debajo — sin piso, is_on_floor() da false de verdad, y
## el resolver de Fase 1 ya trata el agarre de borde como automático al caer
## (sección 8), así que no hace falta simular caminata para disparar el
## agarre (la escalera SÍ exige intención explícita de movimiento,
## ver TraversalResolver._escalera_valida). Usa frames físicos reales (no
## ticks manuales): PlayerMotor usa move_and_slide() en FREE, que solo
## funciona con frames reales (ver hallazgo de Fase 2), y esto además
## ejercita de verdad el orden de proceso Controller -> Motor.
##
## Las zonas de escalera (x=140/150/160) offsetean start_marker/end_marker
## 0.7 unidades en Z respecto del propio CollisionShape3D del "peldaño" (y
## ubican al jugador en ese mismo Z): a diferencia del harness de Fase 3
## (traversal_detector_test.gd), donde ProbeBody nunca corre física real y
## un solape con el collider del segmento no tiene consecuencia, acá
## PlayerMotor SÍ llama move_and_slide()/move_and_collide() cada tick — si
## la cápsula del jugador arrancara incrustada en el propio collider del
## peldaño, la física la empujaría de forma espuria antes de que el
## controller pueda actuar. El offset deja la cápsula completamente libre
## del "peldaño" (que solo hace falta como collider para la query de
## detección) sin alejarse de escalera_radio_deteccion.
##
## Las transiciones de estado se esperan con _esperar_estado() (sondeo
## frame a frame hasta un máximo), no con un conteo fijo de frames: el
## primer par de "await get_tree().physics_frame" de una corrida tiene un
## desfase de 1-2 frames no determinista (confirmado empíricamente) antes
## de que el motor empiece a llamar _physics_process de los nodos recién
## instanciados. Contar frames fijos ahí da falsos negativos intermitentes.

@onready var player: PlayerMotor = $Player
@onready var controller: TraversalController = $Player/TraversalController
@onready var camera: Camera3D = $Player/View/Camera3D

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== PARKOUR V2 · FASE 7 · TraversalController (getters de solo lectura para debug) =====")

	await _test_flujo_completo_lease_y_cooldown()
	await _test_agarre_bloqueado_aborta_seguro()
	await _test_candidatos_nuevos_no_interrumpen_hanging()
	await _test_bloqueo_de_pose_durante_hanging()
	await _test_lease_invalidado_externamente_durante_hanging()
	await _test_last_safe_pose_no_se_pisa_con_pose_bloqueada()
	await _test_mantle_por_salto_completa_a_free()
	await _test_mantle_por_avance_completa_a_free()
	await _test_mantle_bloqueado_con_hang_valido_vuelve_a_hanging()
	await _test_mantle_bloqueado_con_hang_invalido_sale_a_free()
	await _test_shimmy_valido_y_limites()
	await _test_shimmy_bloqueado_no_suelta()
	await _test_shimmy_transicion_a_vecino()
	await _test_ladder_entrada_invalida_y_valida_movimiento_vertical()
	await _test_ladder_salida_por_crouch_y_salto()
	await _test_ladder_transicion_a_vecino()
	await _test_ladder_bloqueo_libera_a_free()
	await _test_ladder_lease_rechazado_externamente()
	await _test_ladder_no_cruza_a_vecino_de_otro_tipo()
	await _test_shimmy_no_cruza_a_vecino_de_otro_tipo()
	await _test_getters_debug_en_ladder()
	await _test_camara_libre_durante_hanging()
	await _test_camara_libre_durante_mantling()
	await _test_camara_libre_durante_ladder()
	await _test_camara_arco_limite_en_hanging()
	await _test_entrada_a_hanging_es_instantanea()
	await _test_direct_mantle_sin_salto_nunca_engancha()
	await _test_direct_mantle_caja_baja_desde_piso()
	await _test_direct_mantle_bloqueo_dinamico_aborta_seguro()
	await _test_direct_mantle_arco_de_camara()
	await _test_direct_mantle_caja_demasiado_alta_sin_mantle_ni_hanging()
	await _test_direct_mantle_buffer_cruza_de_piso_a_aire()
	await _test_direct_mantle_buffer_dentro_de_la_ventana()
	await _test_direct_mantle_buffer_vencido_no_dispara()
	await _test_direct_mantle_aire_cima_valida()
	await _test_direct_mantle_aire_sin_landing_rescata_hanging()
	await _test_direct_mantle_espacio_sin_candidato_salta_normal()
	_test_playerv2_root_sigue_vacio()

	print("=============================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: TraversalController OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	get_tree().quit(_fallos)
	assert(_fallos == 0, "TraversalController no cumple el contrato de la Fase 7")


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


## Sondea hasta max_frames frames físicos esperando que el estado sea el
## indicado. Devuelve true apenas lo alcanza (sin esperar de más) o false
## si nunca llegó dentro del límite.
func _esperar_estado(esperado: TraversalState.Value, max_frames: int = 10) -> bool:
	for i in max_frames:
		if controller.get_estado() == esperado:
			return true
		await get_tree().physics_frame
	return controller.get_estado() == esperado


## Simula un movimiento de mouse horizontal llamando DIRECTO a
## PlayerMotor._procesar_mouse_look() con un InputEventMouseMotion real —
## no player.rotate_y(). El arco de cámara (plan de recuperación de feel
## V1→V2) se aplica dentro de ese mismo método, no en el tick físico (ver
## el comentario en player_motor.gd): llamar rotate_y() a mano NO pasa por
## ahí y el clamp nunca se ejercitaría. delta_yaw_rad es el yaw resultante
## SIN clampear (positivo = gira hacia la izquierda, igual que rotate_y());
## se despeja el event.relative.x necesario invirtiendo la fórmula de
## PlayerMotor._procesar_mouse_look() (rotate_y(-relative.x *
## MOUSE_SENSITIVITY)).
##
## _procesar_mouse_look(), no _unhandled_input(): en headless el
## DisplayServer no honra Input.mouse_mode de forma robusta (comprobado
## empíricamente — ni el propio getter refleja una asignación reciente),
## así que ningún test headless puede atravesar el guard de
## _unhandled_input() de forma consistente. Ver el comentario en
## player_motor.gd — el guard no se toca, solo se lo saltea acá para poder
## probar la lógica real de rotación/clamp que sí protege.
func _rotar_camara_con_mouse(delta_yaw_rad: float) -> void:
	var evento := InputEventMouseMotion.new()
	evento.relative = Vector2(-delta_yaw_rad / PlayerMotor.MOUSE_SENSITIVITY, 0.0)
	player._procesar_mouse_look(evento)


# ── Flujo completo: FREE -> HANGING (agarre instantáneo) -> release -> cooldown ──
## Plan de recuperación de feel V1→V2, Parte 2: ya no hay un ACQUIRE_LEDGE
## que observar entre FREE y HANGING (ni el propio enum TraversalState.Value
## tiene ese valor) — el agarre completo ocurre en el mismo tick. La
## velocidad de convergencia en sí (Parte 1) dejó de tener sentido como
## medida: no hay más "ticks hasta llegar" que contar, ver
## _test_entrada_a_hanging_es_instantanea() más abajo para esa garantía.
func _test_flujo_completo_lease_y_cooldown() -> void:
	_ubicar(Vector3(0, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING),
		"borde válido + caída libre: FREE pasa directo a HANGING (agarre instantáneo)")

	# apply_traversal_pose() aplica el desplazamiento COMPLETO en una sola
	# move_and_collide() cuando no hay colisión (Status.OK): la posición ya
	# es la pose de hang exacta desde este primerísimo tick, sin el tick de
	# "acomodo" que hacía falta con el snap proporcional de la Parte 1.
	var pos_colgado := player.global_position

	var otro_dueno := Node.new()
	_check(player.begin_traversal(otro_dueno) == null,
		"único lease: un begin_traversal externo durante HANGING es rechazado")
	otro_dueno.free()

	_check(player.velocity.is_equal_approx(Vector3.ZERO),
		"HANGING: sin gravedad ni locomoción normal (velocity en cero)")

	await _avanzar_frames(10)
	_check(controller.get_estado() == TraversalState.Value.HANGING,
		"HANGING se mantiene varios ticks (renovando el lease con pose inmóvil)")
	# Tolerancia de distancia, no is_equal_approx: apply_traversal_pose sigue
	# pasando por move_and_collide cada tick aun con motion ~0, y el motor
	# físico puede corregir un solapamiento mínimo (safe_margin) en cada
	# llamada — un drift de decenas de micras por tick no es "se mueve
	# sola", es precisión de punto flotante normal de un motor real.
	_check(player.global_position.distance_to(pos_colgado) < 0.05,
		"HANGING: la pose se mantiene anclada (deriva < 5cm en 10 ticks), no se mueve sola")

	# Release con ATRÁS.
	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"release con atrás: HANGING vuelve a FREE")

	var vel_justo_tras_release := player.velocity
	await _avanzar_frames(3)
	_check(player.velocity.y < vel_justo_tras_release.y - 0.01,
		"tras el release, la gravedad vuelve a actuar (velocity.y cae)")

	# Cooldown: un reintento inmediato NO debe reingresar a HANGING.
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"cooldown activo: sigue en FREE pese a que el borde sigue siendo válido")
	await _avanzar_frames(5)
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"cooldown activo: unos ticks más tarde sigue sin reingresar a HANGING")

	# Esperar a que venza el cooldown (release_cooldown_seg default 0.5s) y reintentar.
	await _avanzar_frames(40)
	_ubicar(Vector3(0, 0, 0))  # el jugador cayó durante el cooldown; reposicionar junto al borde
	_check(await _esperar_estado(TraversalState.Value.HANGING),
		"cooldown vencido: una nueva adquisición vuelve a agarrar de inmediato")

	# Release con CROUCH esta vez.
	Input.action_press("crouch")
	await _avanzar_frames(1)
	Input.action_release("crouch")
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"release con crouch: HANGING vuelve a FREE")

	await _avanzar_frames(40)  # dejar pasar el cooldown antes de la siguiente zona


# ── Agarre bloqueado: fallo seguro ────────────────────────────────────
## BloqueadorB corta la línea recta entre el punto de caída y la pose de
## hang de MuroB (mismo obstáculo que antes bloqueaba un acercamiento
## gradual de varios ticks): move_and_collide() barre TODO el desplazamiento
## de una sola vez, así que sigue detectando la colisión aunque el intento
## ahora sea un único movimiento guiado. El controller debe abortar en el
## MISMO tick en que lo detecta — nunca queda un estado a medio camino
## (de hecho no hay ningún valor de TraversalState.Value para eso), y el
## jugador debe permanecer en FREE en todo momento, listo para que el motor
## acepte un lease nuevo.
func _test_agarre_bloqueado_aborta_seguro() -> void:
	_ubicar(Vector3(10, 0, 0))
	await _avanzar_frames(15)  # tiempo de sobra para que el agarre automático se intente y aborte
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"agarre bloqueado: el intento aborta en el mismo tick, nunca queda a medio camino")

	var otro_dueno := Node.new()
	var lease_libre := player.begin_traversal(otro_dueno)
	_check(lease_libre != null, "tras el agarre bloqueado, el motor vuelve a aceptar un lease nuevo")
	if lease_libre != null:
		player.end_traversal(lease_libre, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	otro_dueno.free()


# ── Candidatos nuevos no interrumpen HANGING ──────────────────────────
func _test_candidatos_nuevos_no_interrumpen_hanging() -> void:
	_ubicar(Vector3(40, 0, 0))  # también hay una escalera válida muy cerca de la pose de hang
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"candidatos nuevos: llega a HANGING con una escalera válida cerca")

	await _avanzar_frames(15)
	_check(controller.get_estado() == TraversalState.Value.HANGING,
		"candidatos nuevos: sigue en HANGING pese a la escalera detectable al lado")

	# El salto desde HANGING iniciando MANTLING ya se prueba a fondo en las
	# zonas dedicadas de mantle (80/90/100/110) — acá el foco es que la
	# escalera cercana no interrumpe nada, así que no se toca jump.

	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"limpieza: release normal sigue funcionando después de todo lo anterior")


# ── Bloqueo de pose durante HANGING ───────────────────────────────────
func _test_bloqueo_de_pose_durante_hanging() -> void:
	# La prueba anterior termina con un release voluntario, que arma el
	# cooldown anti-reagarre — hay que dejarlo vencer antes de esta zona.
	await _avanzar_frames(35)
	_ubicar(Vector3(50, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"bloqueo en hang: llega a HANGING normalmente antes de bloquearlo")

	# Un obstáculo real se materializa justo en la pose de hang YA alcanzada
	# — no en el camino de acercamiento, que ya se recorrió. apply_traversal_pose()
	# valida esto de forma determinista aunque la pose sea inmóvil (motion
	# cero): no depende de que move_and_collide() reciba un desplazamiento
	# distinto de cero por drift de punto flotante.
	var obstaculo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(1.0, 1.0, 1.0)
	forma.shape = caja
	obstaculo.add_child(forma)
	add_child(obstaculo)
	obstaculo.global_position = player.global_position

	_check(await _esperar_estado(TraversalState.Value.FREE, 30),
		"bloqueo de pose en HANGING: sale a FREE en vez de quedarse con un lease bloqueado")

	obstaculo.queue_free()

	var otro_dueno := Node.new()
	var lease_libre := player.begin_traversal(otro_dueno)
	_check(lease_libre != null, "tras el bloqueo en hang, el motor vuelve a aceptar un lease nuevo")
	if lease_libre != null:
		player.end_traversal(lease_libre, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	otro_dueno.free()

	await _avanzar_frames(2)  # dejar que el obstáculo se libere antes de seguir


# ── Lease invalidado externamente durante HANGING ─────────────────────
## El lease del controller es privado (sin getter público) — para simular
## una invalidación "externa" real, no hay atajo: se apaga el procesamiento
## del propio TraversalController un par de ticks, dejando que PlayerMotor
## fuerce el cierre por falta de renovación (mismo mecanismo de Fase 2), y
## se lo vuelve a encender. En su siguiente tick, el controller llama
## apply_traversal_pose() con su _lease ya invalidado por el motor -> REJECTED.
func _test_lease_invalidado_externamente_durante_hanging() -> void:
	_ubicar(Vector3(60, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"lease externo: llega a HANGING normalmente antes de invalidarlo desde afuera")

	controller.set_physics_process(false)
	await _avanzar_frames(2)  # el motor no recibe renovación -> fuerza el cierre del lease
	controller.set_physics_process(true)

	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"lease invalidado externamente (FORCED_NO_RENEWAL): el controller no queda trabado en HANGING")

	var otro_dueno := Node.new()
	var lease_libre := player.begin_traversal(otro_dueno)
	_check(lease_libre != null, "tras la invalidación externa, el motor vuelve a aceptar un lease nuevo")
	if lease_libre != null:
		player.end_traversal(lease_libre, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	otro_dueno.free()


# ── last_safe_pose no se pisa con una pose bloqueada ──────────────────
## TraversalController.get_lease() no existe (a propósito: el lease es
## privado del controller). Para inspeccionar el TraversalMoveResult crudo
## de apply_traversal_pose() —el controller solo mira .status, descarta el
## resto— este test pide su PROPIO lease directo a PlayerMotor, igual que
## los tests de Fase 2. Es un test del contrato de PlayerMotor/TraversalLease,
## no de la máquina de estados del controller (por eso no pasa por HANGING
## de verdad, aunque el escenario —pose inmóvil, luego bloqueada— es el
## mismo que vive HANGING).
func _test_last_safe_pose_no_se_pisa_con_pose_bloqueada() -> void:
	_ubicar(Vector3(70, 0, 0))

	var dueno := Node.new()
	var lease := player.begin_traversal(dueno)

	var pose_inmovil := player.global_transform
	var resultado := player.apply_traversal_pose(lease, pose_inmovil)
	_check(resultado.status == TraversalMoveResult.Status.OK,
		"last_safe_pose: pose inmóvil sin obstáculo se acepta (OK)")

	var pose_segura_guardada := resultado.last_safe_pose

	# Un obstáculo real se materializa justo sobre esa pose ya confirmada.
	var obstaculo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(1.0, 1.0, 1.0)
	forma.shape = caja
	obstaculo.add_child(forma)
	add_child(obstaculo)
	obstaculo.global_position = pose_inmovil.origin

	# El physics server necesita un frame para registrar el collider nuevo
	# antes de que una query lo detecte (mismo motivo por el que el test de
	# bloqueo en HANGING sondea varios frames en vez de chequear al toque).
	await _avanzar_frames(1)

	var resultado_bloqueado := player.apply_traversal_pose(lease, pose_inmovil)
	_check(resultado_bloqueado.status == TraversalMoveResult.Status.BLOCKED,
		"last_safe_pose: la misma pose, ahora con un obstáculo encima, da BLOCKED")
	_check(resultado_bloqueado.last_safe_pose.origin.is_equal_approx(pose_segura_guardada.origin),
		"last_safe_pose: devuelve la pose previa confirmada, no se pisa con el intento bloqueado")

	# El lease sigue vigente pese al bloqueo (eso ya lo prueba
	# _test_bloqueo_de_pose_durante_hanging); acá solo hace falta limpiar.
	obstaculo.queue_free()
	player.end_traversal(lease, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	dueno.free()


# ── MANTLING ──────────────────────────────────────────────────────────
func _test_mantle_por_salto_completa_a_free() -> void:
	_ubicar(Vector3(80, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"mantle por salto: llega a HANGING normalmente antes de intentar mantle")

	Input.action_press("jump")
	_check(await _esperar_estado(TraversalState.Value.MANTLING, 10),
		"salto desde HANGING inicia MANTLING")
	Input.action_release("jump")

	_check(await _esperar_estado(TraversalState.Value.FREE, 45),
		"mantle exitoso: MANTLING llega a FREE")
	# Horizontal solamente: landing_position queda 5cm por encima de la
	# superficie, así que uno o dos ticks de gravedad normal antes de
	# asentarse son esperables y no son "impulso extra" — lo que importa es
	# que no haya empuje horizontal residual.
	_check(Vector2(player.velocity.x, player.velocity.z).is_equal_approx(Vector2.ZERO),
		"mantle exitoso: sin impulso horizontal de salida (la vertical puede reflejar el asentamiento por gravedad)")

	var otro_dueno := Node.new()
	var lease_libre := player.begin_traversal(otro_dueno)
	_check(lease_libre != null, "tras el mantle exitoso, el lease quedó invalidado (el motor acepta uno nuevo)")
	if lease_libre != null:
		player.end_traversal(lease_libre, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	otro_dueno.free()

	# MANTLE_COMPLETED también arma cooldown (ver comentario en
	# _completar_mantle): dejarlo vencer para no arrastrarlo a la zona
	# siguiente.
	await _avanzar_frames(35)


func _test_mantle_por_avance_completa_a_free() -> void:
	_ubicar(Vector3(90, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"mantle por avance: llega a HANGING normalmente antes de intentar mantle")

	Input.action_press("move_forward")
	_check(await _esperar_estado(TraversalState.Value.MANTLING, 10),
		"avance frontal desde HANGING también inicia mantle (doc sección 8: 'salto o avance')")
	Input.action_release("move_forward")

	_check(await _esperar_estado(TraversalState.Value.FREE, 45),
		"mantle por avance también llega a FREE")

	await _avanzar_frames(35)  # dejar vencer el cooldown de MANTLE_COMPLETED


## Obstáculo SOLO en el tramo de mantle, lejos de la pose de hang — para
## eso se separa temporalmente hang_distancia_pared (más lejos de la pared
## que el default) y el obstáculo se coloca cerca de landing_position, que
## no se mueve con ese parámetro.
func _test_mantle_bloqueado_con_hang_valido_vuelve_a_hanging() -> void:
	var distancia_original := controller.hang_distancia_pared
	controller.hang_distancia_pared = 1.0

	_ubicar(Vector3(100, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"mantle bloqueado (hang válido): llega a HANGING normalmente")

	var obstaculo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(0.6, 0.6, 0.6)
	forma.shape = caja
	obstaculo.add_child(forma)
	add_child(obstaculo)
	obstaculo.global_position = Vector3(100, 1.0, -0.65)  # cerca de landing_position
	await _avanzar_frames(1)  # que el physics server registre el collider nuevo

	Input.action_press("jump")
	_check(await _esperar_estado(TraversalState.Value.MANTLING, 10),
		"mantle bloqueado (hang válido): el salto igual inicia MANTLING")

	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"mantle bloqueado con hang todavía válido: vuelve a HANGING con el mismo lease (no lo cierra)")

	# Sección 9.1: "mantenerlo pulsado no reinicia mantle".
	await _avanzar_frames(10)
	_check(controller.get_estado() == TraversalState.Value.HANGING,
		"salto sostenido tras el bloqueo NO reinicia mantle")

	Input.action_release("jump")
	await _avanzar_frames(2)
	Input.action_press("jump")
	_check(await _esperar_estado(TraversalState.Value.MANTLING, 10),
		"soltar y volver a pulsar salto SÍ permite un nuevo intento de mantle")
	Input.action_release("jump")

	# Sacar el obstáculo ANTES de que el segundo intento lo vuelva a chocar.
	obstaculo.queue_free()
	await _avanzar_frames(2)
	_check(await _esperar_estado(TraversalState.Value.FREE, 45),
		"limpieza: sin el obstáculo, el segundo intento de mantle completa a FREE")

	controller.hang_distancia_pared = distancia_original

	# El segundo intento también terminó en MANTLE_COMPLETED, que arma el
	# mismo cooldown que los otros mantles exitosos (ver comentario en
	# _completar_mantle): dejarlo vencer para no arrastrarlo a la zona
	# siguiente (x=110 empezaría con el agarre bloqueado si no).
	await _avanzar_frames(35)


## Obstáculo GRANDE que cubre tanto el tramo de mantle como la propia pose
## de hang (con hang_distancia_pared default, ambas quedan cerca en Z).
func _test_mantle_bloqueado_con_hang_invalido_sale_a_free() -> void:
	_ubicar(Vector3(110, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"mantle bloqueado (hang inválido): llega a HANGING normalmente")

	var obstaculo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(2.0, 3.0, 2.0)
	forma.shape = caja
	obstaculo.add_child(forma)
	add_child(obstaculo)
	obstaculo.global_position = Vector3(110, 0.5, -0.45)  # cubre hang Y landing
	await _avanzar_frames(1)

	# Acá el obstáculo también cubre la pose de hang, así que la revalidación
	# que _iniciar_mantle() hace al entrar a MANTLING (para renovar el lease
	# ese mismo tick, ver comentario ahí) encuentra el bloqueo de inmediato y
	# recupera a FREE dentro del MISMO frame físico en el que se procesó el
	# salto — a diferencia del caso "hang válido", acá MANTLING nunca llega a
	# existir en un frame que este test pueda observar sondeando entre
	# frames, y no debería: si el hang ya es inválido cuando se intenta
	# mantle, no hay nada real que "iniciar". Lo que importa (y sí se
	# verifica) es que el resultado final sea FREE, sin impulso hacia
	# adelante, con el lease liberado y el cooldown activo.
	Input.action_press("jump")
	_check(await _esperar_estado(TraversalState.Value.FREE, 45),
		"mantle bloqueado con hang también inválido: sale a FREE (no se queda esperando)")
	Input.action_release("jump")
	_check(absf(player.velocity.z) < 0.1,
		"salida sin impulso hacia adelante: velocity.z queda ~0, no empuja de vuelta a la pared")

	var otro_dueno := Node.new()
	var lease_libre := player.begin_traversal(otro_dueno)
	_check(lease_libre != null, "tras salir por bloqueo con hang inválido, el motor acepta un lease nuevo")
	if lease_libre != null:
		player.end_traversal(lease_libre, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	otro_dueno.free()

	obstaculo.queue_free()
	await _avanzar_frames(2)

	_check(controller.get_estado() == TraversalState.Value.FREE,
		"cooldown activo tras el mantle bloqueado: sigue en FREE aunque el borde ya está libre de nuevo")
	await _avanzar_frames(35)  # dejar vencer el cooldown
	_ubicar(Vector3(110, 0, 0))  # pudo haber caído durante el cooldown; reposicionar junto al borde

	# Dejar la zona en FREE limpio antes de terminar: los tests que siguen
	# (Fase 6) asumen que ninguno anterior deja un HANGING a medio camino
	# colgado de esta pared — de lo contrario, un _ubicar() posterior solo
	# teletransporta al PLAYER, no reinicia el estado del controller, y el
	# próximo apply_traversal_pose() interpolaría desde la nueva posición
	# hacia el objetivo VIEJO de esta zona.
	_check(await _esperar_estado(TraversalState.Value.HANGING, 10),
		"cooldown vencido: una nueva adquisición vuelve a funcionar en la misma zona")
	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: release normal deja la zona en FREE para los tests siguientes")
	await _avanzar_frames(35)  # dejar vencer el cooldown de este release


# ── Shimmy (desplazamiento lateral dentro de HANGING) ─────────────────
## MuroShimmyA (x=120) tiene un TraversalSegment de tipo LEDGE de 3 unidades
## de largo (world x=118.5..121.5); el jugador se agarra en el centro
## (progreso 0.5, x=120).
func _test_shimmy_valido_y_limites() -> void:
	_ubicar(Vector3(120, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"shimmy: llega a HANGING normalmente antes de desplazarse lateralmente")

	var x_inicial := player.global_position.x

	Input.action_press("move_right")
	await _avanzar_frames(20)
	Input.action_release("move_right")
	_check(controller.get_estado() == TraversalState.Value.HANGING,
		"shimmy: moverse lateralmente no dispara mantle ni suelta el hang")
	_check(player.global_position.x > x_inicial + 0.1,
		"shimmy: la pose se desplazó lateralmente en la dirección esperada (%.3f -> %.3f)"
			% [x_inicial, player.global_position.x])

	# Empujar mucho más lejos de lo que el segmento permite (3 unidades de
	# largo total, sin vecino en este extremo) para forzar el límite.
	Input.action_press("move_right")
	await _avanzar_frames(60)
	Input.action_release("move_right")
	_check(controller.get_estado() == TraversalState.Value.HANGING,
		"shimmy: al llegar al límite del segmento sigue colgado, no suelta ni cae")
	_check(player.global_position.x <= 121.5 + 0.1,
		"shimmy: no sobrepasa el extremo autorizado del segmento (x=%.3f)" % player.global_position.x)

	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: release normal libera el shimmy sin problemas")
	await _avanzar_frames(35)  # dejar vencer el cooldown de HANG_RELEASED


## Obstáculo dinámico en el camino del shimmy (no en la pose de hang en sí):
## debe quedarse colgado sin atravesarlo ni soltarse, y retomar el
## desplazamiento apenas se quita.
func _test_shimmy_bloqueado_no_suelta() -> void:
	_ubicar(Vector3(120, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"shimmy bloqueado: llega a HANGING normalmente")

	var obstaculo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(0.6, 0.6, 0.6)
	forma.shape = caja
	obstaculo.add_child(forma)
	add_child(obstaculo)
	obstaculo.global_position = Vector3(121.0, player.global_position.y, player.global_position.z)
	await _avanzar_frames(1)  # que el physics server registre el collider nuevo

	var x_antes := player.global_position.x
	Input.action_press("move_right")
	await _avanzar_frames(40)
	Input.action_release("move_right")
	_check(controller.get_estado() == TraversalState.Value.HANGING,
		"shimmy bloqueado: sigue colgado, no se suelta contra el obstáculo")
	_check(player.global_position.x > x_antes + 0.1,
		"shimmy bloqueado: sí avanzó hasta justo antes del obstáculo (x=%.3f)" % player.global_position.x)
	_check(player.global_position.x < 121.0 - 0.2,
		"shimmy bloqueado: no atraviesa el obstáculo (x=%.3f)" % player.global_position.x)

	obstaculo.queue_free()
	await _avanzar_frames(2)
	Input.action_press("move_right")
	await _avanzar_frames(30)
	Input.action_release("move_right")
	_check(player.global_position.x > 120.9,
		"limpieza: sin el obstáculo, el shimmy retoma y lo supera (x=%.3f)" % player.global_position.x)

	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: release normal sigue funcionando tras el shimmy bloqueado")
	await _avanzar_frames(35)


## MuroShimmyIzq (x=129, world 128..130) y MuroShimmyDer (x=131, world
## 130..132) son dos TraversalSegment LEDGE contiguos, enlazados por
## neighbour_up/neighbour_down. El jugador se agarra al centro de Izq
## (progreso 0.5, x=129) y shimmea a la derecha lo suficiente para cruzar el
## límite compartido en x=130.
func _test_shimmy_transicion_a_vecino() -> void:
	_ubicar(Vector3(129, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"shimmy con vecino: llega a HANGING normalmente en el segmento izquierdo")

	Input.action_press("move_right")
	await _avanzar_frames(90)
	Input.action_release("move_right")
	_check(controller.get_estado() == TraversalState.Value.HANGING,
		"shimmy con vecino: sigue colgado tras cruzar hacia el segmento vecino")
	_check(player.global_position.x > 130.2,
		"shimmy con vecino: la transición a MuroShimmyDer ocurrió, no se clampeó en el límite (x=%.3f)"
			% player.global_position.x)

	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: release normal libera el shimmy con vecino sin problemas")
	await _avanzar_frames(35)


# ── LADDER (escaleras) ─────────────────────────────────────────────────
## EscaleraF (x=140) es un TraversalSegment de tipo LADDER de 4 unidades
## (world y=-1..3, z=0.7), sin vecinos.
func _test_ladder_entrada_invalida_y_valida_movimiento_vertical() -> void:
	_ubicar(Vector3(140, -1, 0.7))

	# Entrada inválida: sin intención de movimiento, el resolver no dispara
	# ENTER_LADDER pese a estar exactamente sobre el segmento y alineado
	# (sección 7: la escalera exige intención explícita, no solo cercanía).
	await _avanzar_frames(10)
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"escalera: sin intención de movimiento, no entra a LADDER pese a estar cerca y alineado")

	Input.action_press("move_forward")
	_check(await _esperar_estado(TraversalState.Value.LADDER, 15),
		"escalera: con intención de movimiento, entra a LADDER")

	await _avanzar_frames(60)
	var y_medio := player.global_position.y
	_check(y_medio > -1.0 + 0.5 and y_medio < 3.0 - 0.5,
		"escalera: progreso medio del ascenso, ni en la base ni en la cima (y=%.3f)" % y_medio)

	# Seguir sosteniendo adelante mucho más de lo necesario para llegar a la
	# cima: sin vecino arriba, el progreso debe clampear en end_marker, no
	# desbordar ni soltar solo.
	await _avanzar_frames(100)
	Input.action_release("move_forward")
	_check(controller.get_estado() == TraversalState.Value.LADDER,
		"escalera: llegar a la cima sin vecino no sale sola de LADDER")
	_check(player.global_position.y <= 3.0 + 0.05,
		"escalera: el progreso clampea en end_marker, no lo sobrepasa (y=%.3f)" % player.global_position.y)

	# Bajar: retroceder a mitad de camino es descenso normal, no salida (a
	# diferencia del extremo inferior sin vecino, más abajo).
	Input.action_press("move_back")
	await _avanzar_frames(20)
	_check(controller.get_estado() == TraversalState.Value.LADDER,
		"escalera: retroceder a mitad de camino baja, no suelta")
	_check(player.global_position.y < 3.0 - 0.2,
		"escalera: efectivamente bajó (y=%.3f)" % player.global_position.y)

	# Seguir bajando hasta la base y más allá: sin vecino abajo, retroceder
	# ahí sí suelta (sección 10 — ver comentario en TraversalController._tick_ladder()).
	await _avanzar_frames(150)
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"escalera: retroceder en la base sin vecino suelta (comportamiento documentado)")
	Input.action_release("move_back")

	var vel_justo_tras_release := player.velocity
	await _avanzar_frames(3)
	_check(player.velocity.y < vel_justo_tras_release.y - 0.01,
		"escalera: tras soltar por retroceso en la base, la gravedad vuelve a actuar")

	await _avanzar_frames(35)  # dejar vencer el cooldown de LADDER_RELEASED


## Reutiliza la misma EscaleraF (x=140): crouch suelta a mitad de camino
## (no solo en un extremo, a diferencia de retroceso); salto sale con un
## impulso coherente con la CÁMARA (rotada, no el cuerpo del jugador) más
## la vertical estándar de salto.
func _test_ladder_salida_por_crouch_y_salto() -> void:
	_ubicar(Vector3(140, -1, 0.7))
	Input.action_press("move_forward")
	_check(await _esperar_estado(TraversalState.Value.LADDER, 15),
		"escalera (crouch): entra a LADDER normalmente")
	await _avanzar_frames(30)
	Input.action_release("move_forward")

	Input.action_press("crouch")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"escalera: crouch suelta a mitad de camino, no solo en un extremo")
	Input.action_release("crouch")
	await _avanzar_frames(35)  # dejar vencer el cooldown de LADDER_RELEASED

	_ubicar(Vector3(140, -1, 0.7))
	Input.action_press("move_forward")
	_check(await _esperar_estado(TraversalState.Value.LADDER, 15),
		"escalera (salto): entra a LADDER normalmente")
	await _avanzar_frames(30)
	Input.action_release("move_forward")

	# Rotar SOLO la cámara (no el Player): si el impulso siguiera la
	# orientación del cuerpo en vez de la de detector.aim_source, este test
	# lo distinguiría.
	camera.rotation.y = deg_to_rad(90)
	await _avanzar_frames(1)
	var direccion_esperada := -camera.global_transform.basis.z
	direccion_esperada.y = 0.0
	direccion_esperada = direccion_esperada.normalized()

	Input.action_press("jump")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"escalera: salto sale de LADDER")
	var vel_salida := player.velocity
	var horizontal_salida := Vector3(vel_salida.x, 0.0, vel_salida.z)
	_check(horizontal_salida.length() > 0.5,
		"escalera: el salto da impulso horizontal real (%.3f)" % horizontal_salida.length())
	_check(horizontal_salida.normalized().dot(direccion_esperada) > 0.9,
		"escalera: el impulso sigue la dirección de la cámara, no la del cuerpo (dot=%.3f)"
			% horizontal_salida.normalized().dot(direccion_esperada))
	_check(vel_salida.y > 4.0,
		"escalera: el salto conserva un impulso vertical real (y=%.3f)" % vel_salida.y)
	Input.action_release("jump")
	camera.rotation.y = 0.0  # restaurar para el resto de los tests

	var otro_dueno := Node.new()
	var lease_libre := player.begin_traversal(otro_dueno)
	_check(lease_libre != null, "escalera: tras el salto, el motor acepta un lease nuevo")
	if lease_libre != null:
		player.end_traversal(lease_libre, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	otro_dueno.free()

	await _avanzar_frames(35)  # dejar vencer el cooldown de LADDER_JUMP_EXIT


## EscaleraInferior150 (world y=-1..3) y EscaleraSuperior150 (world y=3..7)
## están enlazadas (neighbour_up/neighbour_down): subir más allá del límite
## de la inferior debe continuar en la superior, no clampear en y=3.
func _test_ladder_transicion_a_vecino() -> void:
	_ubicar(Vector3(150, -1, 0.7))
	Input.action_press("move_forward")
	_check(await _esperar_estado(TraversalState.Value.LADDER, 15),
		"escalera con vecino: entra a LADDER normalmente en el segmento inferior")

	await _avanzar_frames(190)
	Input.action_release("move_forward")
	_check(controller.get_estado() == TraversalState.Value.LADDER,
		"escalera con vecino: sigue en LADDER tras cruzar hacia el segmento superior")
	_check(player.global_position.y > 3.3,
		"escalera con vecino: la transición a EscaleraSuperior150 ocurrió, no se clampeó en y=3 (y=%.3f)"
			% player.global_position.y)

	Input.action_press("crouch")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: crouch libera la escalera con vecino sin problemas")
	Input.action_release("crouch")
	await _avanzar_frames(35)


## EscaleraBloqueo160: un obstáculo a mitad de camino bloquea el ascenso.
## A diferencia de MANTLING (sección 9.1), LADDER no revalida ni reintenta:
## libera y vuelve a FREE directo (ver TraversalController._salir_de_ladder_por_falla()).
func _test_ladder_bloqueo_libera_a_free() -> void:
	_ubicar(Vector3(160, -1, 0.7))
	Input.action_press("move_forward")
	_check(await _esperar_estado(TraversalState.Value.LADDER, 15),
		"escalera bloqueada: entra a LADDER normalmente")

	var obstaculo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(1.0, 0.5, 1.0)
	forma.shape = caja
	obstaculo.add_child(forma)
	add_child(obstaculo)
	obstaculo.global_position = Vector3(160, 1.0, 0.7)  # a mitad de camino
	await _avanzar_frames(1)  # que el physics server registre el collider nuevo

	_check(await _esperar_estado(TraversalState.Value.FREE, 120),
		"escalera bloqueada: el bloqueo libera y vuelve a FREE (sin revalidar ni reintentar)")
	Input.action_release("move_forward")

	var otro_dueno := Node.new()
	var lease_libre := player.begin_traversal(otro_dueno)
	_check(lease_libre != null, "escalera bloqueada: el motor acepta un lease nuevo tras el bloqueo")
	if lease_libre != null:
		player.end_traversal(lease_libre, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	otro_dueno.free()

	obstaculo.queue_free()
	await _avanzar_frames(35)  # dejar vencer el cooldown de LADDER_BLOCKED


## Mismo patrón que la Fase 4 ("lease invalidado externamente durante
## HANGING"): apagar el procesamiento del controller un par de ticks deja
## que PlayerMotor fuerce el cierre del lease por falta de renovación
## (FORCED_NO_RENEWAL); al reactivar el controller, su próximo
## apply_traversal_pose() recibe REJECTED y debe limpiar su estado sin
## quedar trabado en LADDER ni volver a llamar end_traversal().
func _test_ladder_lease_rechazado_externamente() -> void:
	_ubicar(Vector3(160, -1, 0.7))
	Input.action_press("move_forward")
	_check(await _esperar_estado(TraversalState.Value.LADDER, 15),
		"escalera + lease externo: entra a LADDER normalmente")

	controller.set_physics_process(false)
	await _avanzar_frames(2)
	controller.set_physics_process(true)

	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"escalera + lease externo: el controller no queda trabado en LADDER tras REJECTED")
	Input.action_release("move_forward")

	var otro_dueno := Node.new()
	var lease_libre := player.begin_traversal(otro_dueno)
	_check(lease_libre != null, "escalera + lease externo: el motor acepta un lease nuevo")
	if lease_libre != null:
		player.end_traversal(lease_libre, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	otro_dueno.free()

	await _avanzar_frames(35)


# ── Guardia de tipo en TraversalSegment.advance_progress() ────────────
## EscaleraTipoErroneo170 (LADDER) tiene su neighbour_up enlazado por error
## a LedgeSenueloTipoErroneo170 (LEDGE) — una configuración de Inspector
## accidental, no un caso de uso real. advance_progress() debe rechazar el
## cruce por tipo distinto y clampear en su propio extremo, sin sacar al
## jugador de LADDER ni cambiarlo de segmento.
func _test_ladder_no_cruza_a_vecino_de_otro_tipo() -> void:
	_ubicar(Vector3(170, -1, 0.7))
	Input.action_press("move_forward")
	_check(await _esperar_estado(TraversalState.Value.LADDER, 15),
		"escalera (guardia de tipo): entra a LADDER normalmente")

	await _avanzar_frames(190)  # de sobra para llegar arriba y de más
	Input.action_release("move_forward")
	_check(controller.get_estado() == TraversalState.Value.LADDER,
		"escalera (guardia de tipo): un vecino LEDGE mal enlazado no la saca de LADDER")
	_check(player.global_position.y <= 3.0 + 0.05,
		"escalera (guardia de tipo): el progreso clampea en su propio extremo, no cruza a un tipo distinto (y=%.3f)"
			% player.global_position.y)

	Input.action_press("crouch")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: crouch libera la escalera de guardia de tipo sin problemas")
	Input.action_release("crouch")

	# Este release ocurre en la CIMA (y=3): a diferencia de las demás zonas
	# de escalera (donde se sale cerca de la base o el release empuja lejos
	# de cualquier geometría), acá el jugador quedaría cayendo en caída
	# libre JUSTO por encima del mismo peldaño que acaba de soltar — y ese
	# peldaño, visto desde arriba mientras cae, puede volver a calificar
	# como un borde válido para el propio EscaleraTipoErroneo170 (mismo
	# collider). Con is_grounded=false, la regla de "agarre automático al
	# caer" de Fase 1 lo reengancharía sin necesitar ningún input, filtrando
	# ese estado al test siguiente (el mismo tipo de fuga ya visto y
	# corregido en Fase 5 con las posiciones "stale" entre zonas). Se
	# reubica lejos de toda geometría ANTES de dejarlo caer el resto del
	# cooldown, en vez de confiar en que la caída libre sobre la propia
	# escalera sea inofensiva.
	_ubicar(Vector3(170, 50, 0.7))
	await _avanzar_frames(35)


## MuroShimmyTipoErroneo180 (LEDGE) tiene su neighbour_up enlazado por error
## a LadderSenueloTipoErroneo180 (LADDER) — mismo tipo de error de
## configuración, del lado del shimmy. Debe clampear en su propio extremo
## sin soltar al jugador ni cambiarlo de segmento.
func _test_shimmy_no_cruza_a_vecino_de_otro_tipo() -> void:
	_ubicar(Vector3(180, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"shimmy (guardia de tipo): llega a HANGING normalmente")

	Input.action_press("move_right")
	await _avanzar_frames(90)  # de sobra para llegar al límite y de más
	Input.action_release("move_right")
	_check(controller.get_estado() == TraversalState.Value.HANGING,
		"shimmy (guardia de tipo): un vecino LADDER mal enlazado no suelta ni cambia de estado")
	_check(player.global_position.x <= 181.5 + 0.1,
		"shimmy (guardia de tipo): el progreso clampea en su propio extremo, no cruza a un tipo distinto (x=%.3f)"
			% player.global_position.x)

	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: release normal libera el shimmy de guardia de tipo sin problemas")
	await _avanzar_frames(35)


# ── Getters de solo lectura para TraversalDebug (Fase 7) ──────────────
## El caso HANGING+shimmy de estos getters ya se prueba en
## traversal_debug_test.gd (junto con la pasividad de TraversalDebug); acá
## se cubre el ángulo que ese arnés no toca: LADDER, donde
## get_segmento_activo() devuelve un TraversalSegment DISTINTO del de
## HANGING y get_progreso_activo() avanza de verdad con el ascenso.
func _test_getters_debug_en_ladder() -> void:
	_ubicar(Vector3(140, -1, 0.7))
	_check(controller.get_segmento_activo() == null,
		"getters: get_segmento_activo() es null en FREE")

	Input.action_press("move_forward")
	_check(await _esperar_estado(TraversalState.Value.LADDER, 15),
		"getters: entra a LADDER normalmente")

	_check(controller.get_segmento_activo() is TraversalSegment,
		"getters: get_segmento_activo() devuelve el TraversalSegment de la escalera en LADDER")

	var progreso_inicial := controller.get_progreso_activo()
	await _avanzar_frames(30)
	Input.action_release("move_forward")
	_check(controller.get_progreso_activo() > progreso_inicial,
		"getters: get_progreso_activo() avanza de verdad con el ascenso (%.3f -> %.3f)"
			% [progreso_inicial, controller.get_progreso_activo()])
	_check(controller.get_pose_objetivo().origin.distance_to(player.global_position) < 0.1,
		"getters: get_pose_objetivo() refleja la pose real durante LADDER")

	Input.action_press("crouch")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: crouch libera la escalera sin problemas")
	Input.action_release("crouch")
	_check(controller.get_segmento_activo() == null,
		"getters: get_segmento_activo() vuelve a null al salir de LADDER")
	_check(controller.get_ultimo_motivo_salida() == TraversalExitReason.Value.LADDER_RELEASED,
		"getters: get_ultimo_motivo_salida() reporta LADDER_RELEASED")

	await _avanzar_frames(35)


# ── Plan de recuperación de feel V1→V2, Parte 1 ───────────────────────
## Verificado contra el V1 histórico (commit bd38e49^, antes de borrarse):
## nunca reorientaba el Body durante ningún estado de traversal — el
## mouse-look quedaba completamente libre. Acá se simula ese mouse-look
## llamando player.rotate_y() directo (lo mismo que haría
## PlayerMotor._unhandled_input() con un evento de mouse real) y se
## confirma que el tick físico siguiente NO lo revierte.
func _test_camara_libre_durante_hanging() -> void:
	_ubicar(Vector3(0, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"cámara libre en HANGING: llega a HANGING normalmente")

	var yaw_antes := player.rotation.y
	var pos_antes := player.global_position
	player.rotate_y(0.6)
	await _avanzar_frames(1)

	_check(is_equal_approx(player.rotation.y, yaw_antes + 0.6),
		"cámara libre en HANGING: el yaw introducido no se revierte al tick físico siguiente (%.3f -> %.3f, esperado %.3f)"
			% [yaw_antes, player.rotation.y, yaw_antes + 0.6])
	_check(player.global_position.distance_to(pos_antes) < 0.05,
		"cámara libre en HANGING: la posición guiada sigue anclada pese a la rotación libre")

	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: release normal sigue funcionando tras rotar la cámara en HANGING")
	await _avanzar_frames(35)


func _test_camara_libre_durante_mantling() -> void:
	_ubicar(Vector3(80, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"cámara libre en MANTLING: llega a HANGING normalmente")
	# Recién agarrado, de frente al borde — mismo truco que en
	# _test_camara_arco_limite_en_hanging() para tener una referencia de yaw
	# sin leer ningún campo privado del controller (ver ese comentario).
	var yaw_referencia := player.rotation.y

	Input.action_press("jump")
	_check(await _esperar_estado(TraversalState.Value.MANTLING, 10),
		"cámara libre en MANTLING: salto inicia MANTLING")
	Input.action_release("jump")

	await _avanzar_frames(3)  # dejar que el mantle progrese un poco antes de rotar
	var yaw_antes := player.rotation.y
	_rotar_camara_con_mouse(0.6)
	await _avanzar_frames(1)

	_check(is_equal_approx(player.rotation.y, yaw_antes + 0.6),
		"cámara libre en MANTLING: dentro del arco, el yaw introducido a mitad de mantle no se revierte")
	_check(controller.get_estado() == TraversalState.Value.MANTLING,
		"cámara libre en MANTLING: sigue en MANTLING, la rotación no lo bloqueó")

	# El arco de cámara (feel nuevo, no V1 — ver el comentario en
	# player_motor.gd) también aplica durante MANTLING, no solo HANGING: el
	# smoke check de acá alcanza porque el mecanismo es el mismo
	# (PlayerMotor.activar_yaw_arco()/_unhandled_input(), activado sobre
	# este mismo lease desde _entrar_a_hanging()) que ya se prueba a fondo,
	# en ambos extremos y sin temblor, en _test_camara_arco_limite_en_hanging().
	var arco_rad := deg_to_rad(controller.camara_arco_yaw_grados)
	_rotar_camara_con_mouse(arco_rad + deg_to_rad(60.0))  # de sobra para exceder el arco
	var relativo := wrapf(player.rotation.y - yaw_referencia, -PI, PI)
	_check(absf(relativo) <= arco_rad + 0.01,
		"arco de cámara en MANTLING: también recorta el yaw fuera de rango")
	_check(controller.get_estado() == TraversalState.Value.MANTLING,
		"arco de cámara en MANTLING: el clamp no interrumpe el mantle en curso")

	_check(await _esperar_estado(TraversalState.Value.FREE, 60),
		"cámara libre en MANTLING: el mantle igual completa a FREE pese a la rotación libre")

	await _avanzar_frames(35)  # dejar vencer el cooldown de MANTLE_COMPLETED


## LADDER ya construía la pose con motor.global_transform.basis leído en el
## momento (no hizo falta cambiar código) — este test deja eso confirmado
## y protegido contra una futura regresión.
func _test_camara_libre_durante_ladder() -> void:
	_ubicar(Vector3(140, -1, 0.7))
	Input.action_press("move_forward")
	_check(await _esperar_estado(TraversalState.Value.LADDER, 15),
		"cámara libre en LADDER: entra a LADDER normalmente")

	await _avanzar_frames(3)
	var yaw_antes := player.rotation.y
	var y_antes := player.global_position.y
	player.rotate_y(0.6)
	await _avanzar_frames(1)

	_check(is_equal_approx(player.rotation.y, yaw_antes + 0.6),
		"cámara libre en LADDER: el yaw introducido no se revierte al tick físico siguiente")
	_check(player.global_position.y > y_antes,
		"cámara libre en LADDER: el ascenso sigue progresando pese a la rotación libre")

	Input.action_release("move_forward")
	Input.action_press("crouch")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: crouch libera la escalera tras rotar la cámara")
	Input.action_release("crouch")
	await _avanzar_frames(35)


# ── Límite de cámara (arco de yaw) durante HANGING/MANTLING ───────────
## NO es una recuperación de V1 (ver el comentario en player_motor.gd): es
## una decisión de feel nueva, confirmada tras el playtest de la Parte 2.
## Prueba ambos extremos del arco, que sostener el mouse contra el límite
## no produce temblor (varios eventos seguidos no lo mueven ni un poco más
## allá del tope), y que volver hacia el centro responde de inmediato (sin
## arrastre/backlog). Usa _rotar_camara_con_mouse() — eventos reales de
## InputEventMouseMotion vía PlayerMotor._unhandled_input(), NO
## player.rotate_y() directo — porque el clamp vive en ese callback, no en
## el tick físico (ver el comentario del plan de recuperación de feel
## V1→V2 en traversal_controller.gd): llamar rotate_y() a mano se saltearía
## el propio mecanismo que este test tiene que ejercitar.
##
## El yaw introducido por cada evento se interpreta relativo a
## yaw_referencia — el yaw justo al agarrar, cuando el jugador cae de
## frente al borde, ya alineado con -wall_normal (la misma referencia que
## usa PlayerMotor.activar_yaw_arco()). Lee camara_arco_yaw_grados del
## propio controller en vez de asumir 85°, para seguir siendo válido si se
## recalibra a 75°/95° en el playground.
func _test_camara_arco_limite_en_hanging() -> void:
	_ubicar(Vector3(30, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING),
		"arco de cámara: llega a HANGING normalmente")

	var yaw_referencia := player.rotation.y  # recién agarrado, de frente al borde
	var arco_grados := controller.camara_arco_yaw_grados
	var arco_rad := deg_to_rad(arco_grados)

	# Extremo positivo: un solo evento bastante más allá de lo que el arco permite.
	_rotar_camara_con_mouse(deg_to_rad(arco_grados + 60.0))
	var relativo_pos := wrapf(player.rotation.y - yaw_referencia, -PI, PI)
	_check(relativo_pos <= arco_rad + 0.01,
		"arco de cámara: no supera +camara_arco_yaw_grados aunque el mouse pida más (%.1f° <= %.1f°)"
			% [rad_to_deg(relativo_pos), arco_grados])
	_check(relativo_pos >= arco_rad - 0.05,
		"arco de cámara: dentro del arco responde 1:1 hasta pegar justo en el límite positivo")

	# Sin temblor: seguir empujando contra el límite, evento tras evento, no
	# lo corre ni un poco más — cada evento se clampea en el mismo callback
	# en el que se escribe, sin ventana entre escritura y corrección (a
	# diferencia del mecanismo viejo, por tick físico).
	for i in 5:
		_rotar_camara_con_mouse(deg_to_rad(10.0))
	var relativo_pos_sostenido := wrapf(player.rotation.y - yaw_referencia, -PI, PI)
	_check(absf(relativo_pos_sostenido - relativo_pos) < 0.001,
		"arco de cámara: sin temblor en el límite positivo — insistir no lo mueve más allá del tope")

	# Extremo negativo: cruzar bien para el otro lado (sin dar la vuelta completa).
	_rotar_camara_con_mouse(deg_to_rad(-(2.0 * arco_grados + 60.0)))
	var relativo_neg := wrapf(player.rotation.y - yaw_referencia, -PI, PI)
	_check(relativo_neg >= -arco_rad - 0.01,
		"arco de cámara: no supera -camara_arco_yaw_grados del otro lado (%.1f° >= %.1f°)"
			% [rad_to_deg(relativo_neg), -arco_grados])
	_check(relativo_neg <= -arco_rad + 0.05,
		"arco de cámara: llega hasta pegar justo en el límite negativo")

	# Mismo chequeo de temblor, ahora en el extremo negativo.
	for i in 5:
		_rotar_camara_con_mouse(deg_to_rad(-10.0))
	var relativo_neg_sostenido := wrapf(player.rotation.y - yaw_referencia, -PI, PI)
	_check(absf(relativo_neg_sostenido - relativo_neg) < 0.001,
		"arco de cámara: sin temblor en el límite negativo — insistir no lo mueve más allá del tope")

	# Volver hacia el centro: respuesta inmediata, sin "desenroscar" nada
	# de los eventos previos que quedaron clampeados.
	_rotar_camara_con_mouse(deg_to_rad(30.0))
	var relativo_vuelta := wrapf(player.rotation.y - yaw_referencia, -PI, PI)
	_check(absf(relativo_vuelta - (-arco_rad + deg_to_rad(30.0))) < 0.01,
		"arco de cámara: sin arrastre — mover el mouse de vuelta responde de inmediato, no arrastra el exceso previo")

	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: release normal tras probar el arco de cámara")
	await _avanzar_frames(35)


# ── Plan de recuperación de feel V1→V2, Parte 2 ───────────────────────
## Entrada a hanging instantánea: confirma la garantía central del cambio.
## Sondea frame a frame desde
## que el jugador cae hasta que deja FREE — el PRIMER frame que ya no es
## FREE debe ser HANGING (no hay otro valor posible: TraversalState.Value ni
## siquiera tiene ya un ACQUIRE_LEDGE), y la posición en ESE MISMO frame ya
## debe coincidir con la pose de hang calculada (get_pose_objetivo(), Fase
## 7), sin ningún desplazamiento gradual posterior — a diferencia del snap
## proporcional de la Parte 1, acá no hay "ticks hasta converger" que medir.
func _test_entrada_a_hanging_es_instantanea() -> void:
	_ubicar(Vector3(20, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.HANGING, 15),
		"entrada instantánea: FREE pasa directo a HANGING sin ningún estado intermedio")
	_check(player.global_position.distance_to(controller.get_pose_objetivo().origin) < 0.01,
		"entrada instantánea: la posición ya es la pose de hang exacta desde el primer frame en HANGING")

	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"limpieza: release normal (entrada instantánea)")
	await _avanzar_frames(35)


# ── Plan de separación HANGING/DIRECT_MANTLE ──────────────────────────
## "No se debe predecir intención": caminar, correr, quedarse quieto o
## moverse lateral/hacia atrás junto a un borde bajo, EN EL PISO, sin una
## orden explícita de salto, nunca dispara nada — ni HANGING (ya no arranca
## desde el piso, ver TraversalResolver._hang_valido()) ni DIRECT_MANTLE
## (exige el flanco de Espacio, ver
## TraversalController._intentar_direct_mantle_o_rescate()).
func _test_direct_mantle_sin_salto_nunca_engancha() -> void:
	_ubicar(Vector3(200, 0, 0))
	await _avanzar_frames(3)
	_check(player.is_on_floor(), "caja baja: setup en piso (sanity check del test)")
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"caja baja: quieto, sin salto, no dispara nada")

	for accion in ["move_forward", "move_back", "move_left"]:
		Input.action_press(accion)
		await _avanzar_frames(10)
		_check(controller.get_estado() == TraversalState.Value.FREE,
			"caja baja: %s sin salto no dispara nada" % accion)
		Input.action_release(accion)
		await _avanzar_frames(1)

	_ubicar(Vector3(200, 0, 0))  # el forward de arriba pudo haber acercado/rotado al jugador
	await _avanzar_frames(3)


## Caja baja (0.7m, dentro de direct_mantle_altura_maxima_en_piso), con
## Espacio desde el piso: sube directo por DIRECT_MANTLE, sin pasar en
## ningún momento por HANGING.
func _test_direct_mantle_caja_baja_desde_piso() -> void:
	_ubicar(Vector3(200, 0, 0))
	await _avanzar_frames(3)
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"caja baja: FREE antes de pedir el salto")

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")

	_check(controller.get_estado() == TraversalState.Value.DIRECT_MANTLE,
		"caja baja + Espacio desde el piso: entra a DIRECT_MANTLE en el mismo tick")

	var paso_por_hanging := false
	var ticks := 0
	while controller.get_estado() != TraversalState.Value.FREE and ticks < 60:
		if controller.get_estado() == TraversalState.Value.HANGING:
			paso_por_hanging = true
		await _avanzar_frames(1)
		ticks += 1
	_check(not paso_por_hanging, "caja baja: en ningún momento pasó por HANGING")
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"caja baja: DIRECT_MANTLE completa a FREE")
	_check(controller.hubo_motivo_salida()
			and controller.get_ultimo_motivo_salida() == TraversalExitReason.Value.DIRECT_MANTLE_COMPLETED,
		"caja baja: motivo de salida es DIRECT_MANTLE_COMPLETED")
	_check(player.global_position.y > 0.5,
		"caja baja: terminó arriba de la caja (y=%.2f)" % player.global_position.y)

	await _avanzar_frames(35)  # dejar vencer el cooldown


## Bloqueo dinámico DURANTE la trayectoria ya comprometida (a diferencia de
## detector.is_pose_clear() fallando ANTES de arrancar, que cae a
## HANGING/nada, ver _intentar_direct_mantle_o_rescate()): acá ya hay un
## lease tomado y el mantle ya empezó — un bloqueo real en el camino debe
## abortar seguro a FREE, sin dejar lease, estado ni buffer trabados.
func _test_direct_mantle_bloqueo_dinamico_aborta_seguro() -> void:
	_ubicar(Vector3(200, 0, 0))
	await _avanzar_frames(3)

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")
	_check(controller.get_estado() == TraversalState.Value.DIRECT_MANTLE,
		"bloqueo dinámico: DIRECT_MANTLE arrancó normalmente")

	var obstaculo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = Vector3(3.0, 2.0, 3.0)
	forma.shape = caja
	obstaculo.add_child(forma)
	add_child(obstaculo)
	obstaculo.global_position = Vector3(200, 1.2, -1.0)  # tapa el tramo de subida/aterrizaje
	await _avanzar_frames(1)

	_check(await _esperar_estado(TraversalState.Value.FREE, 30),
		"bloqueo dinámico: aborta a FREE, no se queda trabado")
	_check(controller.get_ultimo_motivo_salida() == TraversalExitReason.Value.DIRECT_MANTLE_BLOCKED,
		"bloqueo dinámico: motivo de salida es DIRECT_MANTLE_BLOCKED")

	var otro_dueno := Node.new()
	var lease_libre := player.begin_traversal(otro_dueno)
	_check(lease_libre != null, "bloqueo dinámico: el motor vuelve a aceptar un lease nuevo (no quedó trabado)")
	if lease_libre != null:
		player.end_traversal(lease_libre, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	otro_dueno.free()

	obstaculo.queue_free()
	await _avanzar_frames(2)
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"bloqueo dinámico: cooldown activo tras abortar, sigue en FREE")
	await _avanzar_frames(35)  # dejar vencer el cooldown para no arrastrar estado a la próxima zona


## El arco de cámara (mismo mecanismo que HANGING/MANTLING, activado en
## _iniciar_direct_mantle()) también se activa durante DIRECT_MANTLE: smoke
## check liviano — el arco en sí, en ambos extremos y sin temblor, ya se
## prueba a fondo en _test_camara_arco_limite_en_hanging().
func _test_direct_mantle_arco_de_camara() -> void:
	_ubicar(Vector3(200, 0, 0))
	await _avanzar_frames(3)
	var yaw_referencia := player.rotation.y

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")
	_check(controller.get_estado() == TraversalState.Value.DIRECT_MANTLE,
		"arco en DIRECT_MANTLE: arrancó normalmente")

	var arco_rad := deg_to_rad(controller.camara_arco_yaw_grados)
	_rotar_camara_con_mouse(arco_rad + deg_to_rad(60.0))
	var relativo := wrapf(player.rotation.y - yaw_referencia, -PI, PI)
	_check(absf(relativo) <= arco_rad + 0.01,
		"arco en DIRECT_MANTLE: recorta el yaw fuera de rango")
	_check(controller.get_estado() == TraversalState.Value.DIRECT_MANTLE,
		"arco en DIRECT_MANTLE: el clamp no interrumpe el mantle en curso")

	_check(await _esperar_estado(TraversalState.Value.FREE, 60),
		"arco en DIRECT_MANTLE: el mantle igual completa a FREE")
	await _avanzar_frames(35)


## "Borde alto/no aterrizable desde piso": una caja que excede incluso el
## techo aéreo (detector.borde_altura_maxima) ni siquiera se detecta como
## candidato — el único desenlace posible, en piso o ya en el aire tras el
## salto, es el salto normal de PlayerMotor. Distinto del caso "alto para
## el piso pero válido en el aire" (ver
## _test_direct_mantle_buffer_cruza_de_piso_a_aire()), que sí es un
## DIRECT_MANTLE legítimo.
func _test_direct_mantle_caja_demasiado_alta_sin_mantle_ni_hanging() -> void:
	_ubicar(Vector3(205, 0, 0))
	await _avanzar_frames(3)
	var vel_y_antes := player.velocity.y

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")

	_check(player.velocity.y > vel_y_antes + 1.0,
		"caja demasiado alta: el salto normal de PlayerMotor se ejecutó")
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"caja demasiado alta: FREE inmediatamente después del salto")

	await _avanzar_frames(70)  # dejar completar el arco del salto y aterrizar
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"caja demasiado alta: FREE también después de caer (nunca DIRECT_MANTLE ni HANGING)")


## El buffer no distingue "en qué momento físico" se resuelve la
## oportunidad: pedir Espacio en el piso junto a un borde demasiado alto
## para direct_mantle_altura_maxima_en_piso arranca el salto normal ahí
## mismo — pero, ya en el aire (mismo salto, misma ventana de buffer), esa
## MISMA altura sí entra dentro del techo aéreo (detector.borde_altura_maxima)
## y el buffer completa DIRECT_MANTLE de todos modos: "encadenar bloques"
## también funciona saltando desde el piso, no solo ya estando en el aire.
func _test_direct_mantle_buffer_cruza_de_piso_a_aire() -> void:
	_ubicar(Vector3(210, 0, 0))
	await _avanzar_frames(3)
	_check(player.is_on_floor(), "buffer piso->aire: setup en piso (sanity check)")

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")

	_check(await _esperar_estado(TraversalState.Value.DIRECT_MANTLE, 10),
		"buffer piso->aire: la misma orden, ya en el aire, sí completa DIRECT_MANTLE")
	_check(await _esperar_estado(TraversalState.Value.FREE, 60),
		"buffer piso->aire: DIRECT_MANTLE completa a FREE")
	await _avanzar_frames(35)


## Buffer: una orden de salto dada ANTES de estar en rango, si la
## oportunidad real aparece dentro de la ventana (direct_mantle_buffer_seg),
## igual completa DIRECT_MANTLE — no es predicción, es memoria de una orden
## ya dada. Simula "cerrar la distancia" con un teletransporte directo del
## jugador (sin WASD sostenido) para no depender del tiempo real de
## locomoción.
func _test_direct_mantle_buffer_dentro_de_la_ventana() -> void:
	_ubicar(Vector3(220, 0, 1.5))  # lejos: fuera de distancia_deteccion, sin candidato todavía
	await _avanzar_frames(3)

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"buffer: todavía sin candidato, sigue en FREE (el salto normal ya se ejecutó)")

	# Cerrar la distancia DENTRO de la ventana del buffer (default 0.15s).
	# Y en 0, no la altura actual del salto: los rayos de sondeo del
	# detector salen desde altura_de_sondeo POR ENCIMA de los pies actuales
	# del jugador — a mitad del arco del salto, los pies ya están más
	# arriba que la caja entera, y ningún rayo la tocaría.
	await _avanzar_frames(2)
	player.global_position = Vector3(220, 0, 0)
	await _avanzar_frames(1)

	_check(controller.get_estado() == TraversalState.Value.DIRECT_MANTLE,
		"buffer: la oportunidad real, dentro de la ventana, sí completa el pedido")
	_check(await _esperar_estado(TraversalState.Value.FREE, 60),
		"buffer: DIRECT_MANTLE completa a FREE")
	await _avanzar_frames(35)


## Buffer vencido: se espera a que el salto termine del todo y el jugador
## vuelva a aterrizar ANTES de acercarse — bien pasado el buffer y también
## pasado el agarre automático al caer (mecanismo aparte, solo en el aire,
## sin relación con el buffer de salto: acercarse todavía en el aire
## colgaría por esa vía y no aislaría nada). Ya en el piso, sin una orden de
## salto nueva, la misma caja no dispara nada.
func _test_direct_mantle_buffer_vencido_no_dispara() -> void:
	_ubicar(Vector3(220, 0, 1.5))
	await _avanzar_frames(3)

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")

	await _avanzar_frames(70)
	_check(player.is_on_floor(), "buffer vencido: setup — ya aterrizó de nuevo (sanity check)")

	player.global_position = Vector3(220, 0, 0)
	await _avanzar_frames(3)

	_check(controller.get_estado() == TraversalState.Value.FREE,
		"buffer vencido: la oportunidad real, fuera de la ventana, ya no dispara nada (ni mantle ni hang)")


## En el aire, cayendo, con Espacio: la caja es demasiado alta para
## direct_mantle_altura_maxima_en_piso (1.0m) pero está dentro del techo
## aéreo (detector.borde_altura_maxima, 1.5m) — encadenar bloques saltando
## hacia bordes más altos que los que se podrían subir caminando.
func _test_direct_mantle_aire_cima_valida() -> void:
	_ubicar(Vector3(300, 0, 0))
	await _avanzar_frames(1)
	_check(not player.is_on_floor(), "aire + cima válida: setup en el aire (sanity check)")

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")

	_check(controller.get_estado() == TraversalState.Value.DIRECT_MANTLE,
		"aire + cima válida: Espacio en el aire entra a DIRECT_MANTLE")
	_check(await _esperar_estado(TraversalState.Value.FREE, 60),
		"aire + cima válida: DIRECT_MANTLE completa a FREE")
	_check(controller.get_ultimo_motivo_salida() == TraversalExitReason.Value.DIRECT_MANTLE_COMPLETED,
		"aire + cima válida: motivo DIRECT_MANTLE_COMPLETED")
	await _avanzar_frames(35)  # dejar vencer el cooldown antes de la próxima zona


## En el aire, con un borde válido pero SIN landing libre (techo bajo
## encima, ver TechoBloqueador en la escena): Espacio no debe subir directo
## — cae al mismo rescate de HANGING que ya existía (sección 8), nunca
## queda "colgado del intento" de mantle.
func _test_direct_mantle_aire_sin_landing_rescata_hanging() -> void:
	_ubicar(Vector3(310, 0, 0))
	await _avanzar_frames(1)
	_check(not player.is_on_floor(), "aire sin landing: setup en el aire (sanity check)")

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")

	_check(controller.get_estado() == TraversalState.Value.HANGING,
		"aire sin landing: Espacio cae a HANGING (rescate), no a DIRECT_MANTLE")

	Input.action_press("move_back")
	await _avanzar_frames(1)
	Input.action_release("move_back")
	_check(await _esperar_estado(TraversalState.Value.FREE, 10),
		"aire sin landing: release normal libera el rescate")
	await _avanzar_frames(35)


## Sin candidato alguno: PlayerMotor ejecuta el salto normal — la orden no
## se pierde, simplemente no hay nada de traversal que ofrecerle.
func _test_direct_mantle_espacio_sin_candidato_salta_normal() -> void:
	_ubicar(Vector3(225, 0, 0))
	await _avanzar_frames(3)
	var vel_y_antes := player.velocity.y

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")

	_check(player.velocity.y > vel_y_antes + 1.0,
		"sin candidato: el salto normal de PlayerMotor se ejecuta igual")
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"sin candidato: sigue en FREE, no se disparó nada de traversal")
	await _avanzar_frames(60)  # dejar caer y asentarse antes de terminar


# ── Estructura de escena ──────────────────────────────────────────────
func _test_playerv2_root_sigue_vacio() -> void:
	var escena := load("res://scenes/player_v2/player_v2.tscn") as PackedScene
	var instancia := escena.instantiate()
	_check(instancia.get_script() == null, "PlayerV2 root sigue sin script")
	instancia.free()


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
