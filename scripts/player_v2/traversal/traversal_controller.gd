class_name TraversalController
extends Node

## Controlador de estados de traversal (Parkour V2, Fase 6; doc de
## arquitectura V0.3, secciones 5, 6, 8, 9.1 y 10). Implementa
## FREE -> ACQUIRE_LEDGE -> HANGING -> MANTLING -> FREE (con la recuperación
## de la sección 9.1 ante bloqueo de mantle), shimmy lateral DENTRO de
## HANGING (no es un estado nuevo — sección 8), y FREE -> LADDER -> FREE
## para escaleras (sección 10).
##
## Nunca escribe velocity, collider, gravedad ni global_transform de Body
## directamente: solo usa la API pública de PlayerMotor (snapshot(),
## begin_traversal(), apply_traversal_pose(), end_traversal()) y el
## TraversalLease que ese begin_traversal() le entrega.
##
## Construye su propio TraversalIntent leyendo Input.* directamente — no
## hay InputManager ni autoload en este proyecto, y el arnés de test simula
## input con Input.action_press/release, igual que PlayerMotor.
##
## Orden de proceso: este nodo NO fija process_physics_priority (queda en
## el default, 0), y PlayerMotor fija el suyo en 100 (ver player_motor.gd) —
## así el Controller siempre corre antes que el Motor en el mismo frame
## físico sin que este script tenga que saber el valor exacto del motor.

@export var motor: PlayerMotor
@export var detector: TraversalDetector

# ── Acquire — parámetros de feel (calibrables) ───────────────────────
@export var acquire_duracion_seg: float = 0.3
@export var acquire_timeout_seg: float = 2.0
@export var acquire_tolerancia_posicion: float = 0.05

# ── Pose de hang — offsets desde el borde (calibrables) ──────────────
@export var hang_distancia_pared: float = 0.4
@export var hang_caida_desde_borde: float = 1.4

# ── Mantle — parámetros de feel (calibrables) ────────────────────────
@export var mantle_duracion_seg: float = 0.35
@export var mantle_tolerancia_posicion: float = 0.05

# ── Shimmy — parámetro de feel (calibrable) ──────────────────────────
@export var shimmy_velocidad: float = 1.5

# ── Ladder — parámetros de feel (calibrables) ────────────────────────
@export var ladder_velocidad_base: float = 2.0
@export var ladder_salto_impulso_horizontal: float = 3.0

# ── Cooldown anti-reagarre tras un release voluntario, un mantle
# bloqueado con hang inválido, o una salida de LADDER ─────────────────
@export var release_cooldown_seg: float = 0.5

var _estado: TraversalState.Value = TraversalState.Value.FREE
var _lease: TraversalLease = null
var _cooldown_restante: float = 0.0

# ── Datos del borde, guardados al entrar en ACQUIRE_LEDGE/HANGING ────
# Sección 9.1: hacen falta durante todo el hang y el mantle, no solo al
# arrancar — landing_position y wall_normal del candidato original son lo
# que arma la pose de aterrizaje cuando arranca el mantle.
var _ledge_actual: LedgeCandidate = null

# ── Estado interno de ACQUIRE_LEDGE ──────────────────────────────────
var _pose_inicial_acquire: Transform3D
var _pose_objetivo_hang: Transform3D
var _tiempo_en_acquire: float = 0.0

# ── Estado interno de MANTLING ────────────────────────────────────────
# La trayectoria NO es una recta hang -> aterrizaje: para un borde con
# profundidad real (la pared no es infinitamente delgada), esa recta corta
# la esquina sólida entre la cara frontal y la superficie superior, porque
# gran parte del camino la cápsula todavía está a la altura de la pared
# mientras el radio ya avanzó Z adentro de su espesor (ver comentario en
# _iniciar_mantle()). Por eso se arma un punto intermedio ("cima"): subir
# primero pegado a la pared (misma XZ que el hang, ya validada como libre
# por HANGING) hasta la altura de aterrizaje, y recién ahí desplazarse
# horizontalmente por ENCIMA de la superficie hacia landing_position.
var _pose_inicial_mantle: Transform3D
var _pose_cima_mantle: Transform3D
var _pose_aterrizaje_mantle: Transform3D
var _tiempo_en_mantle: float = 0.0

# ── Flancos de disparo de mantle desde HANGING (sección 9.1: "Nuevo
# intento ... requiere soltar y volver a pulsar salto; mantenerlo pulsado
# no reinicia mantle"). Se "arman" con el valor ACTUAL del input cada vez
# que se entra o se vuelve a HANGING, para que sostener jump o avance desde
# antes de llegar (o desde un mantle recién bloqueado) no dispare otro
# intento — hace falta una transición real de soltado a presionado. Se
# unifica el mismo mecanismo para avance frontal: si no, sostener adelante
# durante un mantle bloqueado lo reiniciaría de inmediato sin pasar por
# jump, dejando la regla de "reintento" a medias.
var _salto_armado_en_hang: bool = false
var _avance_armado_en_hang: bool = false

# ── Shimmy — estado del recorrido lateral, DENTRO de HANGING (sección 8):
# no es un estado nuevo de la máquina. Solo tiene efecto si _ledge_actual
# trajo un TraversalSegment de tipo LEDGE asociado; si no, estos campos
# quedan sin usar (segmento null, shimmy no-op por construcción). Se
# inicializan una única vez en _iniciar_acquire_ledge() — NO en
# _entrar_a_hanging(), que también se llama al volver de un mantle
# bloqueado con hang todavía válido: reinicializar ahí perdería cualquier
# avance de shimmy hecho antes de ese intento de mantle. ─────────────────
var _segmento_hang_actual: TraversalSegment = null
var _progreso_hang: float = 0.0

# ── LADDER — estado del ascenso/descenso sobre un TraversalSegment de tipo
# LADDER (sección 10) ─────────────────────────────────────────────────
var _segmento_ladder_actual: TraversalSegment = null
var _progreso_ladder: float = 0.0


func _physics_process(delta: float) -> void:
	physics_tick(delta)


## Un paso completo. Público a propósito: los tests lo manejan a través de
## frames físicos reales (necesarios porque PlayerMotor usa move_and_slide
## en FREE) dejando que el motor de Godot llame a este método y al de
## PlayerMotor en el orden correcto según prioridad de proceso.
func physics_tick(delta: float) -> void:
	match _estado:
		TraversalState.Value.FREE:
			_tick_free()
		TraversalState.Value.ACQUIRE_LEDGE:
			_tick_acquire_ledge(delta)
		TraversalState.Value.HANGING:
			_tick_hanging(delta)
		TraversalState.Value.MANTLING:
			_tick_mantling(delta)
		TraversalState.Value.LADDER:
			_tick_ladder(delta)

	if _cooldown_restante > 0.0:
		_cooldown_restante = maxf(0.0, _cooldown_restante - delta)


func get_estado() -> TraversalState.Value:
	return _estado


# ── FREE ─────────────────────────────────────────────────────────────
func _tick_free() -> void:
	var intent := _construir_intent()
	var snapshot := motor.snapshot()
	var oportunidades := detector.collect(snapshot)

	var contexto := TraversalContext.new(
		TraversalState.Value.FREE, intent, snapshot, Vector3.ZERO, oportunidades.ledge, oportunidades.ladder)
	var decision := TraversalResolver.resolve(contexto)

	if _cooldown_restante > 0.0:
		return

	if decision == TraversalDecision.Value.ACQUIRE_LEDGE:
		_iniciar_acquire_ledge(oportunidades.ledge)
	elif decision == TraversalDecision.Value.ENTER_LADDER:
		_iniciar_ladder(oportunidades.ladder)


func _construir_intent() -> TraversalIntent:
	var eje := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return TraversalIntent.new(
		eje,
		Input.is_action_pressed("jump"),
		Input.is_action_pressed("crouch"),
		Input.is_action_pressed("run"),
		false)  # buffered_jump: sigue sin consumirse


func _iniciar_acquire_ledge(ledge: LedgeCandidate) -> void:
	var lease := motor.begin_traversal(self)
	if lease == null:
		return  # no debería pasar (nadie más pide leases en esta fase), pero no se asume

	_lease = lease
	_ledge_actual = ledge
	_pose_inicial_acquire = motor.global_transform
	_pose_objetivo_hang = _calcular_pose_hang(ledge)
	_tiempo_en_acquire = 0.0
	_estado = TraversalState.Value.ACQUIRE_LEDGE

	# Shimmy (sección 8): si este borde trae un TraversalSegment de tipo
	# LEDGE asociado, el desplazamiento lateral en HANGING recorre ESE
	# segmento. Se inicializa acá, no en _entrar_a_hanging() — ver comentario
	# sobre _segmento_hang_actual más arriba en el archivo.
	_segmento_hang_actual = ledge.segment
	if _segmento_hang_actual != null:
		_progreso_hang = clampf(_segmento_hang_actual.get_progress_along(ledge.edge_position), 0.0, 1.0)


## Pose de hang en un punto de borde dado: retrocedida a lo largo de
## wall_normal (para no clavar el collider en la pared) y caída por debajo
## del borde (para quedar colgando, no parado sobre él). Orientación
## mirando hacia la pared: -wall_normal es "adelante" para un cuerpo
## colgado. Recibe el punto por separado (no un LedgeCandidate completo)
## porque shimmy (Fase 6) necesita recalcularla en puntos DISTINTOS de
## edge_position a medida que el jugador se desplaza a lo largo del
## segmento — wall_normal no cambia (misma pared), solo el punto del borde.
func _calcular_pose_hang_en_punto(punto_borde: Vector3, wall_normal: Vector3) -> Transform3D:
	var origen := punto_borde + wall_normal * hang_distancia_pared - Vector3.UP * hang_caida_desde_borde
	var basis := Basis.looking_at(-wall_normal, Vector3.UP)
	return Transform3D(basis, origen)


func _calcular_pose_hang(ledge: LedgeCandidate) -> Transform3D:
	return _calcular_pose_hang_en_punto(ledge.edge_position, ledge.wall_normal)


# ── ACQUIRE_LEDGE ────────────────────────────────────────────────────
func _tick_acquire_ledge(delta: float) -> void:
	var intent := _construir_intent()
	if intent.jump_pressed:
		_abortar_acquire(TraversalExitReason.Value.ACQUIRE_ABORTED)
		return

	_tiempo_en_acquire += delta
	if _tiempo_en_acquire > acquire_timeout_seg:
		_abortar_acquire(TraversalExitReason.Value.ACQUIRE_TIMEOUT)
		return

	var progreso := clampf(_tiempo_en_acquire / acquire_duracion_seg, 0.0, 1.0)
	var pose_intermedia: Transform3D = _pose_inicial_acquire.interpolate_with(_pose_objetivo_hang, progreso)
	var resultado := motor.apply_traversal_pose(_lease, pose_intermedia)

	if resultado.status != TraversalMoveResult.Status.OK:
		_abortar_acquire(TraversalExitReason.Value.ACQUIRE_BLOCKED)
		return

	var distancia := motor.global_position.distance_to(_pose_objetivo_hang.origin)
	if progreso >= 1.0 or distancia <= acquire_tolerancia_posicion:
		_entrar_a_hanging()


func _abortar_acquire(razon: TraversalExitReason.Value) -> void:
	motor.end_traversal(_lease, Vector3.ZERO, razon)
	_lease = null
	_ledge_actual = null
	_estado = TraversalState.Value.FREE


# ── HANGING ──────────────────────────────────────────────────────────
## Punto de entrada único a HANGING (desde ACQUIRE_LEDGE o de vuelta de un
## mantle bloqueado con hang todavía válido): arma los flancos de jump y
## avance con el valor ACTUAL del input, para que sostenerlos desde antes
## no dispare mantle de inmediato.
func _entrar_a_hanging() -> void:
	_estado = TraversalState.Value.HANGING
	var intent := _construir_intent()
	_salto_armado_en_hang = intent.jump_pressed
	_avance_armado_en_hang = intent.move_axis.y < 0.0


## Mantiene la pose anclada cada tick, aunque no cambie — eso es lo que
## renueva el lease mientras se cuelga. Ignora candidatos nuevos por
## construcción: acá no se consulta ni TraversalDetector ni TraversalResolver,
## así que un borde o escalera nuevos no pueden interrumpir el hang.
##
## Mantle arranca por salto o avance frontal (doc sección 8: "Mantle: Salto
## o avance desde HANGING"), pero solo en el FLANCO de soltado->presionado
## de cualquiera de los dos — ver _entrar_a_hanging() y el comentario sobre
## _salto_armado_en_hang más arriba en el archivo. Shimmy (movimiento
## lateral, sección 8) se procesa DESPUÉS de descartar release y mantle, y
## nunca dispara ninguno de los dos por construcción: solo lee move_axis.x,
## un eje distinto del que arma mantle (move_axis.y) o release (también
## move_axis.y).
func _tick_hanging(delta: float) -> void:
	var intent := _construir_intent()

	if intent.move_axis.y > 0.0 or intent.crouch_pressed:
		_liberar_hang()
		return

	var salto_ahora := intent.jump_pressed
	var avanza_ahora := intent.move_axis.y < 0.0
	var dispara_mantle := (salto_ahora and not _salto_armado_en_hang) or (avanza_ahora and not _avance_armado_en_hang)
	_salto_armado_en_hang = salto_ahora
	_avance_armado_en_hang = avanza_ahora

	if dispara_mantle:
		_iniciar_mantle()
		return

	_procesar_shimmy(intent, delta)

	var resultado := motor.apply_traversal_pose(_lease, _pose_objetivo_hang)
	if resultado.status != TraversalMoveResult.Status.OK:
		_salir_de_hang_por_falla(resultado)


## Shimmy (sección 8): sin segmento asociado, no-op (borde "simple", sin
## recorrido lateral autorizado). Con segmento, mueve _progreso_hang a lo
## largo de él (resolviendo cruce de vecino vía TraversalSegment.
## advance_progress(), Fase 6) y valida la pose resultante de forma PASIVA
## con detector.is_pose_clear() ANTES de aceptarla — si está bloqueada, no
## se actualiza nada acá: _tick_hanging() sigue aplicando la MISMA
## _pose_objetivo_hang de siempre ese tick, así que el jugador se queda
## colgado en la última pose segura, sin atravesar geometría ni soltarse
## (a diferencia de un bloqueo en la pose estacionaria misma, que si ocurre
## lo maneja _salir_de_hang_por_falla() como hasta ahora).
func _procesar_shimmy(intent: TraversalIntent, delta: float) -> void:
	if _segmento_hang_actual == null or intent.move_axis.x == 0.0:
		return

	var longitud := _segmento_hang_actual.get_length()
	if longitud <= 0.0:
		return

	var delta_progreso := (intent.move_axis.x * shimmy_velocidad * delta) / longitud
	var avance := TraversalSegment.advance_progress(_segmento_hang_actual, _progreso_hang, delta_progreso)

	var nuevo_punto := avance.segment.get_position_at(avance.progress)
	var nueva_pose := _calcular_pose_hang_en_punto(nuevo_punto, _ledge_actual.wall_normal)
	if not detector.is_pose_clear(nueva_pose):
		return

	_segmento_hang_actual = avance.segment
	_progreso_hang = avance.progress
	_pose_objetivo_hang = nueva_pose


func _liberar_hang() -> void:
	motor.end_traversal(_lease, Vector3.ZERO, TraversalExitReason.Value.HANG_RELEASED)
	_lease = null
	_ledge_actual = null
	_estado = TraversalState.Value.FREE
	_cooldown_restante = release_cooldown_seg


## BLOCKED: el lease sigue vigente del lado del motor (apply_traversal_pose
## solo bloquea el movimiento, no invalida el lease) — el controller es
## quien tiene que cerrarlo explícitamente. REJECTED: el lease YA no estaba
## activo (invalidado por otra vía); llamar end_traversal() de nuevo no
## corresponde — motor.end_traversal() lo rechazaría con push_error porque
## ya no coincide con el lease vigente (que en este caso es ninguno). En
## ambos casos, no hay reintento ni revalidación acá: eso es para el
## bloqueo DURANTE MANTLING (sección 9.1), no para un hang que ya de por sí
## no se pudo mantener.
func _salir_de_hang_por_falla(resultado: TraversalMoveResult) -> void:
	if resultado.status == TraversalMoveResult.Status.BLOCKED:
		motor.end_traversal(_lease, Vector3.ZERO, TraversalExitReason.Value.HANG_BLOCKED)
	_lease = null
	_ledge_actual = null
	_estado = TraversalState.Value.FREE


# ── MANTLING ─────────────────────────────────────────────────────────
## Arranca desde la pose de hang actual hacia landing_position del
## LedgeCandidate guardado al entrar en ACQUIRE_LEDGE. Mismo lease de
## siempre — no se pide uno nuevo (begin_traversal ya se llamó al iniciar
## la adquisición original). La orientación NO cambia durante el mantle: la
## de aterrizaje "mirando hacia afuera" sería un giro de ~180° respecto de
## la de hang (que mira hacia la pared), y el slerp de cuaterniones que usa
## Transform3D.interpolate_with() es ambiguo justo en 180°. Sin animaciones
## finales en esta fase, mantener el mismo basis evita el problema por
## completo — la reorientación al aterrizar queda para una fase de feel.
## Al arrancar mantle desde _tick_hanging(), HANGING no llegó a llamar
## apply_traversal_pose() ese tick (se sale temprano apenas decide iniciar
## mantle) — si nadie renueva el lease en ESTE tick, PlayerMotor lo fuerza a
## cerrar al final del mismo frame físico (ver PlayerMotor.physics_tick:
## "si nadie renovó, _forzar_salida_traversal()"), antes incluso de que
## exista un solo tick de MANTLING. Por eso acá se renueva explícitamente
## con la pose ACTUAL (progreso 0, un no-op físico) apenas se entra al
## estado — nunca debería dar otra cosa que OK, pero se maneja igual que
## cualquier otro resultado de apply_traversal_pose por prolijidad.
func _iniciar_mantle() -> void:
	_pose_inicial_mantle = motor.global_transform
	_pose_aterrizaje_mantle = Transform3D(_pose_inicial_mantle.basis, _ledge_actual.landing_position)

	# Misma XZ que el hang (ya libre de la pared) a la altura de aterrizaje:
	# el tramo de subida no se acerca nada más a la pared, y para cuando
	# arranca el tramo horizontal la cápsula ya está por encima de la
	# superficie, no a la altura de su cara frontal.
	var origen_cima := Vector3(
		_pose_inicial_mantle.origin.x, _pose_aterrizaje_mantle.origin.y, _pose_inicial_mantle.origin.z)
	_pose_cima_mantle = Transform3D(_pose_inicial_mantle.basis, origen_cima)

	_tiempo_en_mantle = 0.0
	_estado = TraversalState.Value.MANTLING

	var resultado := motor.apply_traversal_pose(_lease, _pose_inicial_mantle)
	if resultado.status != TraversalMoveResult.Status.OK:
		_manejar_bloqueo_de_mantle(resultado)


## Progreso [0, 0.5) interpola hang -> cima (solo sube, pegado a la pared).
## Progreso [0.5, 1] interpola cima -> aterrizaje (solo se desplaza
## horizontalmente, ya por encima de la superficie). Ver comentario sobre
## _pose_cima_mantle más arriba en el archivo para el motivo geométrico.
func _tick_mantling(delta: float) -> void:
	_tiempo_en_mantle += delta
	var progreso := clampf(_tiempo_en_mantle / mantle_duracion_seg, 0.0, 1.0)

	var pose_intermedia: Transform3D
	if progreso < 0.5:
		pose_intermedia = _pose_inicial_mantle.interpolate_with(_pose_cima_mantle, progreso / 0.5)
	else:
		pose_intermedia = _pose_cima_mantle.interpolate_with(_pose_aterrizaje_mantle, (progreso - 0.5) / 0.5)

	var resultado := motor.apply_traversal_pose(_lease, pose_intermedia)
	if resultado.status != TraversalMoveResult.Status.OK:
		_manejar_bloqueo_de_mantle(resultado)
		return

	var distancia := motor.global_position.distance_to(_pose_aterrizaje_mantle.origin)
	if progreso >= 1.0 or distancia <= mantle_tolerancia_posicion:
		_completar_mantle()


## landing_position queda un poco por encima de la superficie real (así lo
## calcula el detector, para no evaluar clearance con el collider ya
## incrustado) — así que, apenas termina el mantle, el cuerpo puede quedar
## un instante sin is_grounded antes de asentarse. Sin cooldown, el MISMO
## borde recién trepado seguiría siendo detectable y el agarre automático
## "al caer" de la sección 8 lo reengancharía de inmediato, en loop. Mismo
## cooldown que un release voluntario o un mantle bloqueado.
func _completar_mantle() -> void:
	motor.end_traversal(_lease, Vector3.ZERO, TraversalExitReason.Value.MANTLE_COMPLETED)
	_lease = null
	_ledge_actual = null
	_estado = TraversalState.Value.FREE
	_cooldown_restante = release_cooldown_seg


## Sección 9.1: "Mantle bloqueado -> Revalidar la pose de hang en ese
## instante; no confiar en la validación de entrada." REJECTED no tiene
## nada que revalidar (el lease ya no es nuestro); BLOCKED sí.
func _manejar_bloqueo_de_mantle(resultado: TraversalMoveResult) -> void:
	if resultado.status == TraversalMoveResult.Status.REJECTED:
		_lease = null
		_ledge_actual = null
		_estado = TraversalState.Value.FREE
		return

	if detector.is_pose_clear(_pose_objetivo_hang):
		# Hang todavía válido: NO se cierra el lease, se retoma tal cual.
		# _entrar_a_hanging() ya resetea los flancos de mantle (datos
		# volátiles) y exige soltar+repulsar jump/avance para reintentar.
		# No hay probes de shimmy que recalcular: shimmy no existe todavía.
		_entrar_a_hanging()
	else:
		_salir_de_mantle_bloqueado(resultado)


## Hang ya inválido también: hay que salir de verdad. Se vuelve hacia
## last_safe_pose SOLO con la API guiada del motor (nunca escribiendo
## transform directo) antes de cerrar el lease, sin impulso hacia
## adelante, restaurando gravedad/locomoción normal al volver a FREE, y con
## cooldown anti-reagarre para no reenganchar el mismo borde de inmediato.
func _salir_de_mantle_bloqueado(resultado: TraversalMoveResult) -> void:
	motor.apply_traversal_pose(_lease, resultado.last_safe_pose)
	motor.end_traversal(_lease, Vector3.ZERO, TraversalExitReason.Value.MANTLE_BLOCKED)
	_lease = null
	_ledge_actual = null
	_estado = TraversalState.Value.FREE
	_cooldown_restante = release_cooldown_seg


# ── LADDER ───────────────────────────────────────────────────────────
## A diferencia de ACQUIRE_LEDGE, no hay una fase de acercamiento animada:
## el resolver ya exige estar cerca y alineado (approach_alignment) para
## disparar ENTER_LADDER (sección 7), así que un solo movimiento guiado
## alcanza la pose inicial sobre el segmento — sigue siendo
## apply_traversal_pose() con su propio move_and_collide (colisión real,
## nunca un teleport), no una excepción al contrato. La orientación se
## congela tal como esté el jugador al agarrarse y no vuelve a cambiar
## mientras dure el ascenso — mismo criterio que MANTLING (Fase 5): sin
## reorientación automática, feel para una fase posterior.
func _iniciar_ladder(ladder: LadderCandidate) -> void:
	var lease := motor.begin_traversal(self)
	if lease == null:
		return  # no debería pasar (nadie más pide leases en esta fase), pero no se asume

	_lease = lease
	_segmento_ladder_actual = ladder.segment
	_progreso_ladder = clampf(ladder.initial_progress, 0.0, 1.0)

	var pose_inicial := Transform3D(
		motor.global_transform.basis, _segmento_ladder_actual.get_position_at(_progreso_ladder))
	_estado = TraversalState.Value.LADDER

	var resultado := motor.apply_traversal_pose(_lease, pose_inicial)
	if resultado.status != TraversalMoveResult.Status.OK:
		_salir_de_ladder_por_falla(resultado)


## move_axis.y controla el recorrido: adelante (< 0, misma convención de
## TraversalIntent) suma progreso (hacia end_marker), atrás resta (hacia
## start_marker) — el autor de la escena es responsable de orientar
## start/end de forma consistente (start = abajo, end = arriba), igual que
## la responsabilidad análoga documentada para el shimmy de bordes: el
## contrato de TraversalSegment no fuerza una dirección física real, así
## que "avanzar" siempre significa "progreso creciente", nunca "hacia
## arriba en el mundo" de forma implícita.
##
## Salida (sección 10 — "definir y documentar salto y crouch/retroceso"):
## crouch SIEMPRE suelta (igual que HANG_RELEASED). Retroceso, en cambio,
## NO suelta en general — se reserva para bajar, que es un requisito
## explícito de esta fase ("soportar desplazamiento hacia arriba y
## abajo") — salvo en el extremo inferior sin neighbour_down: ahí ya no
## hay nada más abajo, así que retroceder deja de significar "bajar" y
## pasa a significar "bajate", igual que crouch. En el extremo superior
## sin neighbour_up no hay un atajo equivalente por avance: no hay
## geometría de aterrizaje conocida por contrato para colocar al jugador
## ahí (a diferencia de landing_position en LedgeCandidate), así que la
## salida arriba sigue siendo siempre explícita (crouch o salto).
func _tick_ladder(delta: float) -> void:
	if _segmento_ladder_actual == null or not _segmento_ladder_actual.is_valid():
		_salir_de_ladder_por_falla(TraversalMoveResult.new(
			TraversalMoveResult.Status.BLOCKED, motor.global_transform, "segmento_ladder_invalido"))
		return

	var intent := _construir_intent()

	if intent.jump_pressed:
		_salir_de_ladder_por_salto()
		return

	var en_la_base_sin_vecino := _progreso_ladder <= 0.0 and _segmento_ladder_actual.get_neighbour_down() == null
	if intent.crouch_pressed or (intent.move_axis.y > 0.0 and en_la_base_sin_vecino):
		_liberar_ladder()
		return

	if intent.move_axis.y != 0.0:
		var longitud := _segmento_ladder_actual.get_length()
		if longitud > 0.0:
			var delta_progreso := (-intent.move_axis.y * ladder_velocidad_base
				* _segmento_ladder_actual.move_speed_multiplier * delta) / longitud
			var avance := TraversalSegment.advance_progress(_segmento_ladder_actual, _progreso_ladder, delta_progreso)
			_segmento_ladder_actual = avance.segment
			_progreso_ladder = avance.progress

	var pose_objetivo := Transform3D(
		motor.global_transform.basis, _segmento_ladder_actual.get_position_at(_progreso_ladder))
	var resultado := motor.apply_traversal_pose(_lease, pose_objetivo)
	if resultado.status != TraversalMoveResult.Status.OK:
		_salir_de_ladder_por_falla(resultado)


## Salto: impulsa al jugador AFUERA de la escalera, en la dirección
## horizontal de detector.aim_source (cámara u otra fuente de apuntado
## explícita — regla de esta fase: "sin introducir lecturas globales
## ocultas"). Se reutiliza el mismo aim_source ya expuesto de solo lectura
## para el propio detector, no un singleton de cámara (no existe ninguno en
## este proyecto). Sin aim_source configurado (defensivo, no debería pasar
## en la escena real), el impulso horizontal queda en cero — no se inventa
## una dirección arbitraria. La vertical reutiliza PlayerMotor.JUMP_VELOCITY
## (constante pública, misma sensación que un salto normal), no un valor
## nuevo inventado acá.
func _salir_de_ladder_por_salto() -> void:
	var direccion_horizontal := Vector3.ZERO
	if detector.aim_source != null:
		var frente := -detector.aim_source.global_transform.basis.z
		frente.y = 0.0
		if frente.length() > 0.001:
			direccion_horizontal = frente.normalized()

	var impulso := direccion_horizontal * ladder_salto_impulso_horizontal
	impulso.y = PlayerMotor.JUMP_VELOCITY
	motor.end_traversal(_lease, impulso, TraversalExitReason.Value.LADDER_JUMP_EXIT)
	_limpiar_estado_ladder()
	_cooldown_restante = release_cooldown_seg


func _liberar_ladder() -> void:
	motor.end_traversal(_lease, Vector3.ZERO, TraversalExitReason.Value.LADDER_RELEASED)
	_limpiar_estado_ladder()
	_cooldown_restante = release_cooldown_seg


## BLOCKED: el lease sigue vigente del lado del motor — el controller lo
## cierra explícitamente (mismo criterio que _salir_de_hang_por_falla).
## REJECTED: ya estaba invalidado por otra vía; no corresponde volver a
## cerrarlo. A diferencia de MANTLING (sección 9.1), acá no hay
## revalidación ni reintento: el pedido de esta fase es liberar y volver a
## FREE directo. Cooldown en ambos casos (incluido REJECTED, un efecto
## puramente local del controller): salir bloqueado deja al jugador
## exactamente donde el bloqueo ocurrió, todavía cerca/alineado con el
## mismo segmento — sin cooldown, un input de movimiento sostenido
## reengancharía LADDER de inmediato contra el mismo obstáculo, en loop
## (mismo tipo de bug ya encontrado y corregido en Fase 5 para
## MANTLE_COMPLETED).
func _salir_de_ladder_por_falla(resultado: TraversalMoveResult) -> void:
	if resultado.status == TraversalMoveResult.Status.BLOCKED:
		motor.end_traversal(_lease, Vector3.ZERO, TraversalExitReason.Value.LADDER_BLOCKED)
	_limpiar_estado_ladder()
	_cooldown_restante = release_cooldown_seg


func _limpiar_estado_ladder() -> void:
	_lease = null
	_segmento_ladder_actual = null
	_estado = TraversalState.Value.FREE
