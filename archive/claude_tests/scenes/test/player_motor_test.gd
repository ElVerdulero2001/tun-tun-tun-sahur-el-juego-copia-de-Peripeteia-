extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Parkour V2 · Fase 2.
##
## Cubre PlayerMotor: locomoción base aislada (piso + techo bajo en
## "TechoBajo") y el contrato de traversal (TraversalLease, apply_traversal_pose,
## end_traversal, salida forzada).
##
## Dos modos de avance, a propósito distintos:
##  - Locomoción: move_and_slide() NO toma un delta explícito — usa
##    get_physics_process_delta_time() internamente, que devuelve 0 si se
##    llama fuera de un frame físico real. Por eso estos tests dejan
##    set_physics_process(true) y avanzan con "await get_tree().physics_frame".
##  - Traversal lease: apply_traversal_pose() usa move_and_collide() con un
##    vector de movimiento explícito (no depende de ese delta interno), así
##    que estos tests controlan los ticks a mano (set_physics_process(false)
##    + physics_tick() explícito) para intercalar apply_traversal_pose() en
##    el momento exacto, sin depender del framerate real.
## Simula input con Input.action_press/release (estado, no eventos) — por
## eso PlayerMotor detecta el salto por flanco propio y no por
## is_action_just_pressed(), que depende de que pasen frames reales.
##
## Plan de recuperación de feel V1→V2, Parte 1: _test_locomocion_responde_
## rapido()/_frena_rapido()/_cambia_direccion_rapido()/_sin_overshoot_con_
## delta_anomalo() validan el cambio de ACCELERATION/FRICTION de
## move_toward() (rampa lineal) a lerp() (proporcional), verificado contra
## el V1 histórico (commit bd38e49^).

const FIXED_DELTA := 1.0 / 60.0
const ZONA_ABIERTA := Vector3(0.0, 0.0, 0.0)
const ZONA_TECHO_BAJO := Vector3(5.0, 0.0, 0.0)  # bajo "TechoBajo" de la escena
const ZONA_MURO := Vector3(-5.0, 0.0, 0.0)  # frente a "Muro" de la escena (muro en z=-2)

@onready var motor: PlayerMotor = $Motor

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== PARKOUR V2 · FASE 2 · PlayerMotor (locomoción + traversal lease) =====")

	await _test_locomocion_camina_y_frena()
	await _test_correr_es_mas_rapido_que_caminar()
	await _test_locomocion_responde_rapido()
	await _test_locomocion_frena_rapido()
	await _test_locomocion_cambia_direccion_rapido()
	_test_locomocion_sin_overshoot_con_delta_anomalo()
	await _test_salto_y_gravedad()
	await _test_crouch_en_zona_abierta()
	await _test_no_puede_pararse_bajo_techo_bajo()
	await _test_snapshot_refleja_estado()

	_test_lease_unico_no_permite_segundo_dueno()
	_test_lease_activo_ignora_locomocion_normal()
	_test_apply_pose_valido_renueva_lease()
	await _test_apply_pose_bloqueado_por_muro()
	await _test_apply_pose_rotacion_bloqueada_por_geometria()
	_test_falta_renovacion_fuerza_salida()
	_test_recuperacion_tras_liberar_lease()

	print("=============================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: PlayerMotor OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	# quit() antes que assert(): un assert fallido corta esta función y
	# nunca llegaría a quit(), dejando el proceso headless colgado.
	get_tree().quit(_fallos)
	assert(_fallos == 0, "PlayerMotor no cumple el contrato de la Fase 2")


# ── Helpers ──────────────────────────────────────────────────────────
func _reset(pos: Vector3) -> void:
	for accion in ["move_forward", "move_back", "move_left", "move_right", "run", "crouch", "jump"]:
		Input.action_release(accion)
	motor.global_position = pos
	motor.velocity = Vector3.ZERO


## Avance con frames físicos reales — necesario para todo lo que dependa de
## move_and_slide() (locomoción, gravedad, is_on_floor()).
func _avanzar_frames(n: int = 1) -> void:
	motor.set_physics_process(true)
	for i in n:
		await get_tree().physics_frame


## Avance con ticks manuales — para los tests de traversal lease, que
## necesitan intercalar apply_traversal_pose() en el tick exacto.
func _avanzar_ticks(n: int = 1) -> void:
	motor.set_physics_process(false)
	for i in n:
		motor.physics_tick(FIXED_DELTA)


# ── Locomoción ───────────────────────────────────────────────────────
func _test_locomocion_camina_y_frena() -> void:
	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)  # asentarse en el piso
	_check(motor.snapshot().is_grounded, "asentado: is_grounded tras settle")
	_check(motor.velocity.length() < 0.1, "asentado: velocity casi cero en reposo")

	Input.action_press("move_forward")
	await _avanzar_frames(45)
	var horizontal := Vector2(motor.velocity.x, motor.velocity.z)
	_check(absf(horizontal.length() - PlayerMotor.WALK_SPEED) < 0.05,
		"caminando: velocidad horizontal converge a WALK_SPEED (obtuvo %.3f)" % horizontal.length())

	Input.action_release("move_forward")
	await _avanzar_frames(30)
	_check(Vector2(motor.velocity.x, motor.velocity.z).length() < 0.1,
		"frenado: sin input la velocidad horizontal vuelve a ~0")


## Plan de recuperación de feel V1→V2, Parte 1: ACCELERATION/FRICTION pasaron
## de move_toward() (rampa lineal a tasa constante) a lerp() (proporcional a
## la distancia restante), con tasa 14.0 — verificada contra el V1 histórico
## (commit bd38e49^, movement_controller.gd). Con esa tasa, la fracción de
## convergencia tras N ticks a 60fps es 1-(1-14/60)^N: ~96% a los 12 ticks,
## ~93% de DECAIMIENTO (o sea <7% remanente) al frenar en 10 ticks — de ahí
## los umbrales de estos tests, con margen para no ser frágiles.
func _test_locomocion_responde_rapido() -> void:
	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)

	Input.action_press("move_forward")
	await _avanzar_frames(12)  # ~200ms a 60fps
	var horizontal := Vector2(motor.velocity.x, motor.velocity.z)
	Input.action_release("move_forward")

	_check(horizontal.length() > PlayerMotor.WALK_SPEED * 0.9,
		"respuesta rápida: supera 90%% de WALK_SPEED en 12 ticks (obtuvo %.3f de %.3f)"
			% [horizontal.length(), PlayerMotor.WALK_SPEED])

	await _avanzar_frames(30)  # asentar antes del próximo test


func _test_locomocion_frena_rapido() -> void:
	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)

	Input.action_press("move_forward")
	await _avanzar_frames(45)  # llegar a WALK_SPEED (ya cubierto por otro test)
	Input.action_release("move_forward")

	await _avanzar_frames(10)  # ~167ms
	var horizontal := Vector2(motor.velocity.x, motor.velocity.z)
	_check(horizontal.length() < PlayerMotor.WALK_SPEED * 0.15,
		"frenado rápido: cae por debajo de 15%% de WALK_SPEED en 10 ticks tras soltar (obtuvo %.3f)"
			% horizontal.length())

	await _avanzar_frames(10)  # asentar del todo antes del próximo test


func _test_locomocion_cambia_direccion_rapido() -> void:
	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)

	Input.action_press("move_forward")
	await _avanzar_frames(45)  # velocidad hacia adelante estable (velocity.z negativa)
	Input.action_release("move_forward")

	Input.action_press("move_back")
	await _avanzar_frames(12)
	Input.action_release("move_back")

	var horizontal := Vector2(motor.velocity.x, motor.velocity.z)
	_check(horizontal.y > PlayerMotor.WALK_SPEED * 0.7,
		"cambio de dirección rápido: invierte a >70%% de WALK_SPEED en el sentido contrario en 12 ticks (obtuvo z=%.3f)"
			% horizontal.y)

	await _avanzar_frames(15)  # asentar antes del próximo test


## Con lerp() sin clamp, un delta anómalo (ej. un lag spike) daría un peso
## tasa*delta >> 1, y Transform3D/Vector2.lerp() EXTRAPOLA más allá del
## objetivo en vez de detenerse ahí — el clampf() en PlayerMotor evita
## exactamente eso. Se llama physics_tick() a mano con un delta grande para
## aislar el cálculo de velocidad de la resolución de posición de
## move_and_slide() (que fuera de un frame físico real usa su propio delta
## interno, no el pasado a mano — ver cabecera del archivo).
func _test_locomocion_sin_overshoot_con_delta_anomalo() -> void:
	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)

	Input.action_press("move_forward")
	motor.set_physics_process(false)
	motor.physics_tick(1.0)  # delta anómalo: un segundo completo de una vez
	Input.action_release("move_forward")

	var horizontal := Vector2(motor.velocity.x, motor.velocity.z)
	_check(horizontal.length() <= PlayerMotor.WALK_SPEED + 0.01,
		"delta anómalo: la velocidad no sobrepasa la velocidad objetivo, obtuvo %.3f de %.3f"
			% [horizontal.length(), PlayerMotor.WALK_SPEED])

	motor.set_physics_process(true)
	await _avanzar_frames(15)  # asentar antes del próximo test


func _test_correr_es_mas_rapido_que_caminar() -> void:
	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)

	Input.action_press("move_forward")
	Input.action_press("run")
	await _avanzar_frames(90)
	var vel_run := Vector2(motor.velocity.x, motor.velocity.z).length()
	Input.action_release("move_forward")
	Input.action_release("run")

	_check(absf(vel_run - PlayerMotor.RUN_SPEED) < 0.05,
		"corriendo: velocidad horizontal converge a RUN_SPEED (obtuvo %.3f)" % vel_run)
	_check(vel_run > PlayerMotor.WALK_SPEED, "correr es más rápido que caminar")


func _test_salto_y_gravedad() -> void:
	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)
	_check(motor.snapshot().is_grounded, "en el piso antes de saltar")

	Input.action_press("jump")
	await _avanzar_frames(1)
	Input.action_release("jump")
	_check(motor.velocity.y > 0.0, "salto: velocity.y positiva en el tick del salto (%.3f)" % motor.velocity.y)

	await _avanzar_frames(1)
	_check(not motor.snapshot().is_grounded, "en el aire un tick después de saltar")

	# suficientes frames para que la gravedad lo devuelva al piso
	await _avanzar_frames(60)
	_check(motor.snapshot().is_grounded, "la gravedad lo devuelve al piso")


# ── Postura / collider ───────────────────────────────────────────────
func _test_crouch_en_zona_abierta() -> void:
	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)

	Input.action_press("crouch")
	await _avanzar_frames(3)
	var snap_agachado := motor.snapshot()
	_check(snap_agachado.stance == MotorSnapshot.Stance.CROUCHING, "crouch: stance pasa a CROUCHING")
	_check(snap_agachado.can_stand, "crouch en zona abierta: can_stand sigue true (sin techo)")

	Input.action_release("crouch")
	await _avanzar_frames(3)
	var snap_de_pie := motor.snapshot()
	_check(snap_de_pie.stance == MotorSnapshot.Stance.STANDING, "soltar crouch en zona abierta: vuelve a STANDING")


func _test_no_puede_pararse_bajo_techo_bajo() -> void:
	_reset(ZONA_TECHO_BAJO)
	await _avanzar_frames(15)

	Input.action_press("crouch")
	await _avanzar_frames(3)
	_check(motor.snapshot().stance == MotorSnapshot.Stance.CROUCHING, "bajo techo bajo: puede agacharse")

	Input.action_release("crouch")
	await _avanzar_frames(5)
	var snap := motor.snapshot()
	_check(not snap.can_stand, "bajo techo bajo: can_stand es false")
	_check(snap.stance == MotorSnapshot.Stance.CROUCHING,
		"bajo techo bajo: soltar crouch NO lo para (sigue CROUCHING)")

	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)  # devolver a postura de pie en zona abierta para los tests siguientes


func _test_snapshot_refleja_estado() -> void:
	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)
	var snap := motor.snapshot()
	_check(snap.is_grounded, "snapshot: is_grounded true en reposo sobre el piso")
	_check(snap.velocity.length() < 0.1, "snapshot: velocity casi cero en reposo")
	_check(snap.stance == MotorSnapshot.Stance.STANDING, "snapshot: stance STANDING en reposo")
	_check(snap.can_stand, "snapshot: can_stand true en reposo")


# ── Traversal lease ──────────────────────────────────────────────────
func _test_lease_unico_no_permite_segundo_dueno() -> void:
	_reset(ZONA_ABIERTA)
	_avanzar_ticks(15)

	var dueno_a := Node.new()
	var dueno_b := Node.new()
	var lease_a := motor.begin_traversal(dueno_a)
	var lease_b := motor.begin_traversal(dueno_b)

	_check(lease_a != null, "primer begin_traversal obtiene un lease")
	_check(lease_b == null, "segundo begin_traversal mientras hay uno vigente es rechazado (null)")

	motor.end_traversal(lease_a, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	dueno_a.free()
	dueno_b.free()


func _test_lease_activo_ignora_locomocion_normal() -> void:
	_reset(ZONA_ABIERTA)
	_avanzar_ticks(15)

	var dueno := Node.new()
	var pos_inicial := motor.global_position
	var lease := motor.begin_traversal(dueno)

	Input.action_press("move_forward")  # intento de locomoción normal, no debería surtir efecto
	_avanzar_ticks(1)  # cubierto por la renovación de begin_traversal
	Input.action_release("move_forward")

	_check(motor.global_position.is_equal_approx(pos_inicial),
		"con lease activo, la locomoción normal no mueve el cuerpo")
	_check(motor.velocity.is_equal_approx(Vector3.ZERO),
		"con lease activo, la gravedad/locomoción no altera velocity")

	motor.end_traversal(lease, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	dueno.free()


func _test_apply_pose_valido_renueva_lease() -> void:
	_reset(ZONA_ABIERTA)
	_avanzar_ticks(15)

	var dueno := Node.new()
	var lease := motor.begin_traversal(dueno)
	_avanzar_ticks(1)  # cubierto por begin_traversal
	_check(lease.is_valid(), "lease sigue vigente tras el primer tick (cubierto por begin_traversal)")

	var pose_objetivo := Transform3D(motor.global_transform.basis, motor.global_position + Vector3(0.0, 0.0, -1.0))
	var resultado := motor.apply_traversal_pose(lease, pose_objetivo)
	_check(resultado.status == TraversalMoveResult.Status.OK,
		"apply_traversal_pose en espacio libre devuelve OK")
	_check(resultado.last_safe_pose.origin.is_equal_approx(motor.global_position),
		"last_safe_pose coincide con la posición alcanzada")

	_avanzar_ticks(1)  # renovado por apply_traversal_pose -> NO debería forzar salida
	_check(lease.is_valid(), "un apply_traversal_pose válido renueva el lease para el siguiente tick")

	motor.end_traversal(lease, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	dueno.free()


func _test_apply_pose_bloqueado_por_muro() -> void:
	_reset(ZONA_MURO)
	await _avanzar_frames(15)

	var dueno := Node.new()
	var lease := motor.begin_traversal(dueno)
	_avanzar_ticks(1)  # cubierto por begin_traversal

	# Objetivo bien más allá del muro (en z=-2): si no bloqueara, cruzaría
	# de punta a punta el "Muro" de la escena.
	var pose_objetivo := Transform3D(motor.global_transform.basis, motor.global_position + Vector3(0.0, 0.0, -5.0))
	var resultado := motor.apply_traversal_pose(lease, pose_objetivo)

	_check(resultado.status == TraversalMoveResult.Status.BLOCKED,
		"apply_traversal_pose contra un muro devuelve BLOCKED")
	_check(resultado.blocked_reason != "", "bloqueado por muro: blocked_reason no vacío")
	_check(resultado.last_safe_pose.origin.z > pose_objetivo.origin.z + 1.0,
		"bloqueado por muro: last_safe_pose se quedó antes del muro, no en el objetivo bloqueado")
	_check(resultado.last_safe_pose.origin.z < -0.5,
		"bloqueado por muro: igual avanzó hasta cerca del obstáculo")
	_check(motor.global_position.is_equal_approx(resultado.last_safe_pose.origin),
		"bloqueado por muro: el motor quedó físicamente en last_safe_pose")
	_check(lease.is_valid(), "bloqueado por muro: el lease sigue vigente pese al bloqueo")

	_avanzar_ticks(1)  # si el bloqueo también renovó el lease, esto NO debería forzar salida
	_check(lease.is_valid(), "bloqueado por muro: el bloqueo también cuenta como renovación del lease")

	motor.end_traversal(lease, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	dueno.free()


## Una rotación objetivo puede dejar la posición sin tocar y aun así meter el
## collider en geometría (move_and_collide solo valida el tramo lineal con la
## orientación VIEJA). Se fuerza acostando la cápsula 90°: su offset local
## (0, height/2, 0) pasa a apuntar sobre el eje horizontal, así que la mitad
## de la cápsula queda bajo el piso — sin necesidad de un muro dedicado.
func _test_apply_pose_rotacion_bloqueada_por_geometria() -> void:
	_reset(ZONA_ABIERTA)
	await _avanzar_frames(15)

	var dueno := Node.new()
	var lease := motor.begin_traversal(dueno)
	_avanzar_ticks(1)  # cubierto por begin_traversal

	var basis_seguro := motor.global_transform.basis
	var basis_acostado := Basis(Vector3.RIGHT, PI / 2.0)
	var pose_objetivo := Transform3D(basis_acostado, motor.global_position)  # misma posición

	var resultado := motor.apply_traversal_pose(lease, pose_objetivo)
	_check(resultado.status == TraversalMoveResult.Status.BLOCKED,
		"rotación que penetra el piso: apply_traversal_pose devuelve BLOCKED")
	_check(resultado.blocked_reason != "", "rotación bloqueada: blocked_reason no vacío")
	_check(motor.global_transform.basis.is_equal_approx(basis_seguro),
		"rotación bloqueada: conserva la última orientación segura, no la objetivo")
	_check(lease.is_valid(), "rotación bloqueada: el lease sigue vigente pese al bloqueo")

	motor.end_traversal(lease, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	dueno.free()


func _test_falta_renovacion_fuerza_salida() -> void:
	_reset(ZONA_ABIERTA)
	_avanzar_ticks(15)

	var dueno := Node.new()
	var lease := motor.begin_traversal(dueno)
	_avanzar_ticks(1)  # cubierto por begin_traversal
	_check(lease.is_valid(), "lease vigente tras el primer tick")

	_avanzar_ticks(1)  # sin apply_traversal_pose de por medio -> debe forzar salida
	_check(not lease.is_valid(), "sin renovación en el tick siguiente, el motor fuerza la salida")
	_check(motor.velocity.is_equal_approx(Vector3.ZERO), "salida forzada normalizada: velocity queda en cero")

	var lease_nuevo := motor.begin_traversal(dueno)
	_check(lease_nuevo != null, "tras la salida forzada, el motor vuelve a aceptar un lease nuevo")
	motor.end_traversal(lease_nuevo, Vector3.ZERO, TraversalExitReason.Value.OWNER_RELEASED)
	dueno.free()


func _test_recuperacion_tras_liberar_lease() -> void:
	_reset(ZONA_ABIERTA)
	_avanzar_ticks(15)

	var dueno := Node.new()
	var lease := motor.begin_traversal(dueno)
	var vel_salida := Vector3(0.0, 0.0, -2.0)
	motor.end_traversal(lease, vel_salida, TraversalExitReason.Value.OWNER_RELEASED)

	_check(not lease.is_valid(), "end_traversal invalida el lease")
	_check(motor.velocity.is_equal_approx(vel_salida), "end_traversal restaura velocity a exit_velocity")

	var rapidez_inicial := Vector2(motor.velocity.x, motor.velocity.z).length()
	_avanzar_ticks(1)  # locomoción normal ya debería regir de nuevo (sin input -> fricción frena)
	var rapidez_luego := Vector2(motor.velocity.x, motor.velocity.z).length()
	_check(rapidez_luego < rapidez_inicial,
		"tras liberar el lease, la locomoción normal vuelve a regir (fricción frena sin input)")

	dueno.free()


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
