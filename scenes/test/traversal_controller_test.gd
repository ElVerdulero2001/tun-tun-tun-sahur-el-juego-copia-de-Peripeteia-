extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Parkour V2 · Fase 6.
##
## Integración de TraversalController: FREE -> ACQUIRE_LEDGE -> HANGING ->
## MANTLING -> FREE (con la recuperación de la sección 9.1 ante bloqueo de
## mantle), shimmy lateral DENTRO de HANGING (sección 8), y FREE -> LADDER ->
## FREE para escaleras (sección 10). Cada zona (separada por X) es geometría
## flotante SIN piso debajo — sin piso, is_on_floor() da false de verdad, y
## el resolver de Fase 1 ya trata el agarre de borde como automático al caer
## (sección 8), así que no hace falta simular caminata para disparar
## ACQUIRE_LEDGE (la escalera SÍ exige intención explícita de movimiento,
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
	print("\n===== PARKOUR V2 · FASE 6 · TraversalController (shimmy + escaleras) =====")

	await _test_flujo_completo_lease_y_cooldown()
	await _test_bloqueo_durante_acquire()
	await _test_salto_aborta_acquire()
	await _test_timeout_acquire()
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
	_test_playerv2_root_sigue_vacio()

	print("=============================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: TraversalController OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	get_tree().quit(_fallos)
	assert(_fallos == 0, "TraversalController no cumple el contrato de la Fase 6")


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


# ── Flujo completo: FREE -> ACQUIRE_LEDGE -> HANGING -> release -> cooldown ──
func _test_flujo_completo_lease_y_cooldown() -> void:
	_ubicar(Vector3(0, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.ACQUIRE_LEDGE),
		"borde válido + caída libre: FREE pasa a ACQUIRE_LEDGE")

	var otro_dueno := Node.new()
	_check(player.begin_traversal(otro_dueno) == null,
		"único lease: otro begin_traversal durante ACQUIRE_LEDGE es rechazado")
	otro_dueno.free()

	_check(player.velocity.is_equal_approx(Vector3.ZERO),
		"ACQUIRE_LEDGE: sin gravedad ni locomoción normal (velocity en cero)")

	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"ACQUIRE_LEDGE llega a HANGING dentro de la tolerancia configurada")

	var pos_colgado := player.global_position
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

	# Cooldown: un reintento inmediato NO debe reingresar ACQUIRE_LEDGE.
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"cooldown activo: sigue en FREE pese a que el borde sigue siendo válido")
	await _avanzar_frames(5)
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"cooldown activo: unos ticks más tarde sigue sin reingresar ACQUIRE_LEDGE")

	# Esperar a que venza el cooldown (release_cooldown_seg default 0.5s) y reintentar.
	await _avanzar_frames(40)
	_ubicar(Vector3(0, 0, 0))  # el jugador cayó durante el cooldown; reposicionar junto al borde
	_check(await _esperar_estado(TraversalState.Value.ACQUIRE_LEDGE),
		"cooldown vencido: una nueva adquisición sí entra a ACQUIRE_LEDGE")

	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"segunda adquisición llega a HANGING igual que la primera")

	# Release con CROUCH esta vez.
	Input.action_press("crouch")
	await _avanzar_frames(1)
	Input.action_release("crouch")
	_check(controller.get_estado() == TraversalState.Value.FREE,
		"release con crouch: HANGING vuelve a FREE")

	await _avanzar_frames(40)  # dejar pasar el cooldown antes de la siguiente zona


# ── Bloqueo durante ACQUIRE_LEDGE ────────────────────────────────────
func _test_bloqueo_durante_acquire() -> void:
	_ubicar(Vector3(10, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.ACQUIRE_LEDGE),
		"bloqueo: entra a ACQUIRE_LEDGE normalmente")

	_check(await _esperar_estado(TraversalState.Value.FREE, 30),
		"bloqueo durante el acercamiento (BloqueadorB en el camino): aborta a FREE")

	var otro_dueno := Node.new()
	var lease_libre := player.begin_traversal(otro_dueno)
	_check(lease_libre != null, "tras abortar por bloqueo, el motor vuelve a aceptar un lease nuevo")
	if lease_libre != null:
		player.end_traversal(lease_libre, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	otro_dueno.free()


# ── Salto aborta ACQUIRE_LEDGE ───────────────────────────────────────
func _test_salto_aborta_acquire() -> void:
	_ubicar(Vector3(20, 0, 0))
	_check(await _esperar_estado(TraversalState.Value.ACQUIRE_LEDGE),
		"salto en acquire: entra a ACQUIRE_LEDGE normalmente")

	Input.action_press("jump")
	var abortado := await _esperar_estado(TraversalState.Value.FREE, 10)
	Input.action_release("jump")
	_check(abortado, "salto durante ACQUIRE_LEDGE aborta a FREE (mantle no existe todavía)")


# ── Timeout de ACQUIRE_LEDGE ──────────────────────────────────────────
func _test_timeout_acquire() -> void:
	_ubicar(Vector3(30, 0, 0))
	var timeout_original := controller.acquire_timeout_seg
	controller.acquire_timeout_seg = 0.01

	_check(await _esperar_estado(TraversalState.Value.ACQUIRE_LEDGE),
		"timeout: entra a ACQUIRE_LEDGE normalmente")

	_check(await _esperar_estado(TraversalState.Value.FREE, 15),
		"ACQUIRE_LEDGE que excede acquire_timeout_seg sale seguro a FREE")

	controller.acquire_timeout_seg = timeout_original


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
	# siguiente (x=110 empezaría con ACQUIRE_LEDGE bloqueado si no).
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
	_check(await _esperar_estado(TraversalState.Value.ACQUIRE_LEDGE, 10),
		"cooldown vencido: una nueva adquisición vuelve a funcionar en la misma zona")

	# Dejar la zona en FREE limpio antes de terminar: los tests que siguen
	# (Fase 6) asumen que ninguno anterior deja un ACQUIRE_LEDGE/HANGING a
	# medio camino colgado de esta pared — de lo contrario, un _ubicar()
	# posterior solo teletransporta al PLAYER, no reinicia el estado del
	# controller, y el próximo apply_traversal_pose() interpolaría desde la
	# nueva posición hacia el objetivo VIEJO de esta zona.
	_check(await _esperar_estado(TraversalState.Value.HANGING, 30),
		"limpieza: la nueva adquisición llega a HANGING antes de soltar")
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
