class_name ActorMotor
extends RefCounted

## Paso por tick de un actor: recibe estado, input y dt, mueve el cuerpo y deja
## el estado del tick siguiente. No guarda nada propio; por eso cualquier tick
## se puede repetir después de restaurar el estado.
##
## Sigue el orden fijo de etapas de la arquitectura. Por ahora existen los modos
## Suelo, Aire, Deslizamiento, Ladder, Hanging, Enganchado (HOOKED: colgado de
## un compañero), Cable (colgado de un cable, la Tirolesa de la arquitectura) y
## Mantle (subirse a un borde bajo, desde el 2026-10-25), y la postura
## (parado, agachado o encogido). La etapa de sondas (4) revalida el borde
## agarrado (colgado o en el mantle) y busca al compañero del que cuelga. Las
## demás sondas corren donde se usan: la de suelo en la de contactos, la de
## espacio libre en la de postura, la de escalera, la del mantle, la de agarrar
## un borde y la de colgarse de un compañero en la de transición, y la de
## escalón en la de movimiento, porque necesita saber si el movimiento chocó.
##
## Colgado de un compañero, la pose sale de la del compañero en este mismo
## tick: el reloj mueve primero a los que no cuelgan de nadie.
##
## Sobre una base (plataforma, balsa), la posición y la velocidad del estado
## son relativas a ella. La base no se rebobina al repetir ticks: si se repiten,
## todo pasa en coordenadas de la base, sobre su pose de ahora.

## Consulta de la sonda de suelo, armada una sola vez.
static var _probe_params: PhysicsShapeQueryParameters3D
## Para validar una afirmación de colgarse de un compañero: cuánto puede
## diferir su pose de la que da el compañero en el host. Es amplia porque el
## cliente vio al compañero en el pasado.
const HOOK_TOLERANCE := 0.5
## Colgado de un compañero en un borde o una escalera: cuánto se puede pasar
## de hook_turn_limit, en radianes (un paso de la cuantización del ángulo).
const HOOK_TURN_SLACK := 0.0001
## Esquinas colgado (ver _hang): cuánto adentro de cada cara se revalida el
## filo al lado de una esquina, y dónde queda el punto al terminar de doblar.
const CORNER_INSET := 0.03
## Cuánto puede diferir de perpendicular la cara de al lado: el coseno del
## ángulo entre su normal y la que tendría en un ángulo recto (20°).
const CORNER_SQUARE := 0.94
## Cuánto puede diferir la altura del filo de la cara de al lado.
const CORNER_HEIGHT := 0.02
## El giro más chico con el que se empieza a doblar por afuera, en radianes.
const CORNER_MIN_TURN := 0.002
## En cuántos tramos se prueba que el cuerpo pase al doblar.
const CORNER_SWEEP_STEPS := 6
## Por adentro: a qué distancia del rincón se revalida el filo de cada cara.
const CORNER_PROBE := 0.1
## Por adentro: cuánto antes de donde empieza la curva vale para empezarla, y
## cuánto más allá de donde termina queda al terminarla. Así, al volver, la
## encuentra otra vez.
const CORNER_SLACK := 0.005
## Agarre de un cable: de a cuánto se barre el movimiento del tick, en metros.
const CABLE_SWEEP_STEP := 0.1
## Escalera por atrás: hasta esta altura sobre el pie se agarra parado en el
## suelo, como de frente. Más arriba, solo si debajo de los pies no hay piso.
const LADDER_BACK_FOOT := 0.5
## Cuánto debajo de los pies se busca ese piso, en metros.
const LADDER_BACK_FLOOR := 0.35
## Salida por arriba: hasta cuánto más arriba o más abajo del alto de la
## escalera se busca el piso donde termina, en metros. Sin piso, termina parado
## arriba de la escalera (ver ladder_exit_length).
const LADDER_TOP_FLOOR := 0.3
## Salida por arriba: cuánto sube el cuerpo por encima del alto para pasar al
## rellano sin rozar nada (los peldaños y los largueros no chocan más arriba
## del alto), en metros. Al terminar, baja hasta el piso. Lo justo para pasar
## por encima del margen de la física (1 mm): el piso de arriba va a la altura
## del alto, así que el cuerpo pasa a la altura del piso. Hasta el 2026-10-23
## era 3 cm, y al terminar se notaba la bajada (pedido del usuario: "esos 3 cm
## se notan"); con 1 mm ya pasaba en todas las escaleras del laboratorio.
const LADDER_EXIT_LIFT := 0.002
## Desde cuánto antes del alto se calcula si se puede salir, en metros.
const LADDER_EXIT_NEAR := 0.1
## Mantle: cuánto pasan los pies por encima del filo antes de ir hacia
## adentro, en metros. Lo justo para pasar sin rozar, como en la salida por
## arriba de la escalera (LADDER_EXIT_LIFT).
const MANTLE_LIFT := 0.002
## Para validar una afirmación en el mantle: hasta dónde delante de la cara
## del borde puede estar el cuerpo (las manos llegan hasta 0,6 m delante del
## centro), y el margen de las demás medidas, en metros.
const MANTLE_REACH := 0.7
const MANTLE_SLACK := 0.01
## Mantle con teclas: termina apenas el centro del cuerpo queda este tanto
## detrás del filo, con piso debajo, y de ahí camina hacia donde apuntan.
const MANTLE_STAND := 0.1
## Mantle: subiendo, se arrima a la pared hasta quedar a esto de ella, en metros.
const MANTLE_WALL_GAP := 0.01


static func step(body: ActorBody, state: ActorState, input: ActorInput, tuning: ActorTuning, dt: float) -> void:
	body.snap_jump = Vector3.ZERO
	body.grab_jump = Vector3.ZERO
	body.grab_jump_speed = ActorBody.GRAB_MAX_SPEED
	body.fit_tuck(tuning.hang_climb_tuck)

	# 1. Tiempo: dt es el del mundo, 1/60 por la escala del mundo (cámara lenta).
	state.coyote_left = maxf(state.coyote_left - dt, 0.0)
	state.jump_buffer_left = maxf(state.jump_buffer_left - dt, 0.0)
	state.regrab_left = maxf(state.regrab_left - dt, 0.0)
	if state.regrab_left == 0.0:
		state.regrab_id = 0
	# El daño en el tiempo también va con el tiempo del mundo (ActorVitals.step).
	ActorVitals.step(state, tuning, dt)

	# 2. Base: la base se movió desde el tick anterior y lleva al actor.
	_ride_base(body, state)

	# 3. Eventos. Una pulsación nueva se detecta porque el contador cambió,
	# aunque se haya perdido el tick exacto en que ocurrió.
	if input.jump_presses != state.jump_presses_seen:
		state.jump_presses_seen = input.jump_presses
		state.jump_buffer_left = tuning.jump_buffer_time
	# Cada pulsación prende o apaga el súper salto y velocidad o el pedido de
	# cámara lenta (dos que caen entre dos ticks se anulan); después se cobra la
	# estamina del tick, y si se acaba se apagan todos (ActorPowers).
	ActorPowers.step(state, input, tuning)
	# Con el súper, desde acá todas las velocidades de moverse vienen
	# multiplicadas (ActorTuning.with_boost).
	tuning = tuning.with_boost(state.boosted)

	# 4. Sondas: colgado o en el mantle, la de borde revalida cada tick el borde
	# agarrado; colgado de un compañero, se lo busca por su id.
	var edge := _held_edge(body, state, tuning) if state.mode == ActorState.Mode.HANGING \
			else _mantle_edge(body, state) if state.mode == ActorState.Mode.MANTLE else {}
	var mate: ActorBody = body.teammate(state.anchor_id) if state.mode == ActorState.Mode.HOOKED else null
	var cable: Cable = Cable.find(state.anchor_id) if state.mode == ActorState.Mode.CABLE else null

	# 5. Transición: como máximo una por tick, decidida por la situación actual.
	# Cada modo revisa su lista de salidas en orden de prioridad.
	var wants_jump := state.jump_buffer_left > 0.0
	var crouch_held := input.is_held(ActorInput.BUTTON_CROUCH)
	# Después de salir por arriba de una escalera con W, va derecho mientras
	# siga con W sola: soltarla o tocar A, S o D lo corta (pedido del usuario,
	# 2026-10-16). Shift, Espacio y Ctrl no lo cortan. Desde el 2026-10-20, solo
	# en tercera persona y mirando para atrás: pasar a primera persona o girar
	# la cámara hacia adelante también lo corta (ver straight_exit).
	if state.straight_out and (input.move.y <= 0.0 or input.move.x != 0.0 \
			or not straight_exit(input, state.facing_yaw, tuning)):
		state.straight_out = false
	# La vuelta sola a la escalera (después de soltarse con Ctrl o del salto
	# para arriba mirándola) se corta con A o D: moverse de costado quiere decir
	# que se va. Vale apretada antes, en el momento o durante la caída (pedido
	# del usuario, 2026-10-20: tocando Ctrl con A apretada, se corría un poco y
	# se volvía a pegar).
	if state.ladder_return != 0 and input.move.x != 0.0:
		state.ladder_return = 0
	var direction := _wish_direction(input, state)
	# El salto para arriba desde el colgado pide encogerse (etapa 7).
	var tuck := false
	# En la escalera, el largo del tramo de la salida por arriba (0 si no se
	# puede salir o si está lejos del alto); lo usa también la etapa 6.
	var ladder_exit := 0.0
	match state.mode:
		ActorState.Mode.GROUND:
			if wants_jump:
				_jump(state, tuning, dt)
			elif not state.on_floor:
				state.mode = ActorState.Mode.AIR
				state.coyote_left = tuning.coyote_time
			elif not crouch_held and _try_grab_ladder(body, state, direction, tuning):
				# Con Ctrl no: Ctrl suelta la escalera, y se volvería a agarrar.
				pass
			elif crouch_held and state.stance == ActorState.Stance.STANDING \
					and _horizontal_speed(state) >= tuning.slide_entry_speed:
				state.mode = ActorState.Mode.SLIDE
		ActorState.Mode.AIR:
			if state.on_floor and state.velocity.y <= 0.0:
				state.mode = ActorState.Mode.GROUND
			elif wants_jump and state.coyote_left > 0.0:
				_jump(state, tuning, dt)
			elif wants_jump and not state.jumped and state.velocity.y <= 0.0:
				_air_jump(state, input.look_yaw, tuning, dt)
			elif not crouch_held:
				# Con Ctrl no se agarra de nada: así cae el que se soltó de una
				# escalera con Ctrl, mientras lo tenga apretado. Primero el mantle:
				# llegando con las manos por encima de un borde bajo, sube en vez de
				# colgarse (pedido del usuario, 2026-10-25).
				edge = _try_mantle(body, state, grab_direction(input.look_yaw), tuning, dt)
				if edge.is_empty():
					edge = _try_grab_edge(body, state, grab_direction(input.look_yaw), tuning, dt)
				if edge.is_empty():
					mate = _try_hook(body, state, grab_direction(input.look_yaw), tuning, dt)
				if edge.is_empty() and mate == null:
					cable = _try_grab_cable(body, state, grab_direction(input.look_yaw), tuning, dt)
				if state.mode == ActorState.Mode.AIR and not _try_grab_ladder(body, state, direction, tuning, grab_direction(input.look_yaw)):
					_return_to_ladder(body, state)
		ActorState.Mode.SLIDE:
			if wants_jump:
				_jump(state, tuning, dt)
			elif not state.on_floor:
				state.mode = ActorState.Mode.AIR
				state.coyote_left = tuning.coyote_time
			elif not crouch_held or _horizontal_speed(state) < tuning.slide_min_speed:
				# Soltar Ctrl corta el deslizamiento: vuelve a Suelo, que frena o
				# sigue según lo que se apriete. Bajo un techo queda agachado.
				state.mode = ActorState.Mode.GROUND
		ActorState.Mode.LADDER:
			var ladder := Ladder.find(state.anchor_id)
			# W sube y S baja, mire donde mire la cámara.
			var climb := clampf(input.move.y, -1.0, 1.0)
			if ladder != null and state.anchor_t >= ladder.height - LADDER_EXIT_NEAR:
				ladder_exit = ladder_exit_length(body, ladder, ladder.side_of_yaw(state.facing_yaw), tuning)
			if ladder == null:
				# Invariante roto: la escalera ya no existe. Sale al respaldo.
				_leave_anchor(state, tuning, Vector3.ZERO, false)
			elif crouch_held:
				# Ctrl se suelta, sin empujón: cae mientras siga con Ctrl y, al
				# soltarlo, si sigue frente a la escalera, se vuelve a agarrar
				# solo (pedido del usuario, 2026-10-16). Si un compañero cuelga
				# de él, se caen los dos, como colgado de un borde.
				var held := ladder.ladder_id
				_leave_anchor(state, tuning, Vector3.ZERO, false)
				state.ladder_return = held
			elif state.hooked_by != 0:
				# Un compañero cuelga de él: se queda quieto. Saltar no hace nada.
				state.jump_buffer_left = 0.0
			elif wants_jump:
				# Mirando a la escalera salta derecho para arriba, más alto que
				# desde el piso, y bajando se vuelve a agarrar solo (pedido del
				# usuario, 2026-10-16). Mirando a otro lado, salta hacia donde
				# mira, sin la parte que iría contra la pared, y se da vuelta
				# hacia allá.
				var look := Vector3.FORWARD.rotated(Vector3.UP, input.look_yaw)
				var out := ladder.face(ladder.side_of_yaw(state.facing_yaw))
				var into := look.dot(-out)
				if into >= cos(tuning.climb_look_angle):
					var held := ladder.ladder_id
					_leave_anchor(state, tuning, ladder.up() * _ladder_jump_speed(tuning, dt), true)
					state.ladder_return = held
				else:
					var away := (look + out * maxf(into, 0.0)).normalized()
					_leave_anchor(state, tuning, away * tuning.ladder_jump_out_speed + ladder.up() * tuning.ladder_jump_up, true)
					state.facing_yaw = _yaw_of(away)
				state.jumped = true
			elif state.anchor_t <= 0.0 and climb < -0.5:
				_leave_anchor(state, tuning, Vector3.ZERO, false)
			elif ladder_exit > 0.0 and state.anchor_t >= ladder.height + ladder_exit - ActorState.POSITION_STEP:
				# Terminó el tramo de la salida por arriba: queda parado arriba.
				_finish_ladder_exit(body, state, ladder, input, tuning)
				direction = _wish_direction(input, state)
			elif ladder_exit > 0.0 and climb == 0.0 and state.anchor_t >= ladder.height + LADDER_EXIT_LIFT \
					and _floor_under(body, body.global_position, tuning):
				# Sin W ni S en la parte de la salida que va hacia el rellano, con el
				# centro del cuerpo ya sobre el piso: termina la escalera y frena como
				# caminando, con la velocidad que traía (pedido del usuario,
				# 2026-10-28: quedaba en Ladder parado sobre la plataforma). Arriba
				# de una escalera suelta no hay piso (sus piezas no cuentan), y ahí
				# sigue quedando donde está.
				var moving := state.velocity
				_finish_ladder_exit(body, state, ladder, input, tuning)
				state.velocity = moving
				direction = _wish_direction(input, state)
		ActorState.Mode.HANGING:
			if edge.is_empty():
				# Invariante roto: el borde ya no está o quedó fuera de alcance.
				_leave_edge(state, tuning, Vector3.ZERO)
			elif crouch_held:
				# Si un compañero cuelga de él, se caen los dos: al compañero se le
				# rompe el invariante en este mismo tick.
				_leave_edge(state, tuning, Vector3.ZERO)
			elif state.hooked_by != 0:
				# Un compañero cuelga de él: se queda quieto. Saltar no hace nada.
				state.jump_buffer_left = 0.0
			elif wants_jump:
				# Mirando a la pared salta derecho para arriba, encogido, y con el
				# control aéreo pasa arriba del borde; mirando a otro lado, salta
				# hacia allá y se da vuelta hacia donde salta, así las manos buscan
				# para ese lado y no la pared que deja.
				var look := Vector3.FORWARD.rotated(Vector3.UP, input.look_yaw)
				if look.dot(-edge["normal"]) >= cos(tuning.climb_look_angle):
					_leave_edge(state, tuning, Vector3.UP * _climb_jump_speed(tuning, dt))
					tuck = true
				else:
					_leave_edge(state, tuning, look * tuning.hang_jump_out_speed + Vector3.UP * tuning.hang_jump_up)
					state.facing_yaw = _yaw_of(look)
				state.jumped = true
		ActorState.Mode.HOOKED:
			if not _hook_holds(body, mate):
				# Invariante roto: el compañero se soltó, lo soltaron o se fue. Sale
				# a Aire con la velocidad que traía él.
				_leave_hook(state, tuning, _world_velocity(mate.state) if mate != null else Vector3.ZERO, false)
			elif crouch_held:
				_leave_hook(state, tuning, Vector3.ZERO, true)
			elif wants_jump:
				# Como colgado de un borde: mirando hacia el compañero salta para
				# arriba, con los pies hasta hang_climb_clearance por encima de sus
				# manos; mirando a otro lado, salta hacia allá y se da vuelta.
				var look := Vector3.FORWARD.rotated(Vector3.UP, input.look_yaw)
				if look.dot(_toward_mate(state)) >= cos(tuning.climb_look_angle):
					_leave_hook(state, tuning, Vector3.UP * _climb_jump_speed(tuning, dt), true)
				else:
					_leave_hook(state, tuning, look * tuning.hang_jump_out_speed + Vector3.UP * tuning.hang_jump_up, true)
					state.facing_yaw = _yaw_of(look)
				state.jumped = true
		ActorState.Mode.CABLE:
			if cable == null or crouch_held:
				# Ctrl se suelta, o se rompió el invariante: el cable ya no existe.
				# Sale con la velocidad que traía sobre el cable. Si un compañero
				# cuelga de él, se caen los dos, como colgado de un borde.
				_leave_cable(state, tuning, state.velocity)
			elif state.hooked_by != 0:
				# Un compañero cuelga de él: se queda quieto. Saltar no hace nada.
				state.jump_buffer_left = 0.0
			elif wants_jump:
				# Salta hacia donde mira la cámara, como colgado de un borde mirando a
				# otro lado, y se da vuelta hacia allá. Se lleva la velocidad que traía
				# sobre el cable, sin pasar del tope del salto. Con el súper salto y
				# velocidad, como el salto en el aire: sale más rápido y los pies
				# suben boost_jump_extra más (pedido del usuario, 2026-10-19; hasta
				# entonces salía igual que sin el súper).
				var look := Vector3.FORWARD.rotated(Vector3.UP, input.look_yaw)
				var most := tuning.jump_max_speed
				var out := tuning.hang_jump_out_speed
				var up := raised_jump_speed(tuning.hang_jump_up, tuning, dt, tuning.boost_jump_extra) if state.boosted \
						else tuning.hang_jump_up
				var carried := Vector3(state.velocity.x, 0.0, state.velocity.z) + look * out
				carried = carried.limit_length(maxf(most, out))
				_leave_cable(state, tuning, carried + Vector3.UP * up)
				state.facing_yaw = _yaw_of(look)
				state.jumped = true
		ActorState.Mode.MANTLE:
			if edge.is_empty() or crouch_held:
				# Invariante roto (el borde ya no está), o Ctrl lo suelta, como de
				# todo: cae. Como soltarse no es saltar, no vuelve a subir solo.
				_leave_mantle(state, tuning, Vector3.ZERO, false)
			elif _mantle_done(body, body.global_position, edge, input, tuning):
				_finish_mantle(body, state, input, tuning)
				direction = _wish_direction(input, state)

	# 6. Modo: el modo activo decide la velocidad.
	match state.mode:
		ActorState.Mode.GROUND:
			_ground(state, direction * _ground_speed(state, input, tuning), tuning, dt)
		ActorState.Mode.AIR:
			_air(state, direction, tuning, dt)
		ActorState.Mode.SLIDE:
			_slide(state, direction, tuning, dt)
		ActorState.Mode.LADDER:
			_ladder(state, input.move.y, ladder_exit, tuning, dt)
		ActorState.Mode.HANGING:
			edge = _hang(body, state, edge, input, tuning, dt)
		ActorState.Mode.HOOKED:
			# La pose la da el compañero; W y S suben y bajan, y A y D giran
			# alrededor de él.
			state.velocity = Vector3.ZERO
			_hook_move(body, state, mate, input, tuning, dt)
		ActorState.Mode.CABLE:
			_cable(state, cable, input, tuning, dt)
		ActorState.Mode.MANTLE:
			_mantle(body, state, edge, direction, tuning, dt)
	if state.mode == ActorState.Mode.SLIDE:
		if _horizontal_speed(state) > 0.01:
			state.facing_yaw = _yaw_of(state.velocity)
	elif not _is_anchored(state) and direction.length_squared() > 0.0001:
		state.facing_yaw = _yaw_of(direction)

	# 7. Postura y movimiento. Deslizamiento siempre pide agachado; en los modos
	# anclados se va parado; si no, lo pide el input. Encogido (el salto para
	# arriba desde el colgado) sigue así mientras esté en el aire: al tocar el
	# piso o agarrarse de algo pide parado. En el mantle sigue la postura con
	# que empezó (agachado si arriba solo cabe así). Los modos libres mueven con
	# move_and_slide(), sin snap en el aire; los anclados (Ladder, Hanging,
	# Enganchado, Cable, Mantle), con un barrido. En Suelo, si el movimiento
	# chocó, la sonda de escalón prueba subirlo. Con la vuelta a la escalera
	# pendiente (ladder_return), Ctrl solo impide agarrarse: no agacha, porque
	# agachado en el aire sube los pies y el que se suelta tiene que caer.
	var wanted := ActorState.Stance.STANDING
	if state.mode == ActorState.Mode.SLIDE or (crouch_held and not _is_anchored(state) and state.ladder_return == 0):
		wanted = ActorState.Stance.CROUCHED
	elif state.mode == ActorState.Mode.AIR and (tuck or state.stance == ActorState.Stance.TUCKED):
		wanted = ActorState.Stance.TUCKED
	elif state.mode == ActorState.Mode.MANTLE:
		wanted = state.stance as ActorState.Stance
	_resolve_stance(body, state, wanted)
	if state.mode == ActorState.Mode.LADDER:
		_move_on_ladder(body, state)
	elif state.mode == ActorState.Mode.HANGING:
		_move_hanging(body, state, edge, tuning)
	elif state.mode == ActorState.Mode.HOOKED:
		_move_hooked(body, state, mate, tuning)
	elif state.mode == ActorState.Mode.CABLE:
		_move_on_cable(body, state, cable, tuning)
	elif state.mode == ActorState.Mode.MANTLE:
		_move_mantling(body, state, edge, tuning, dt)
	else:
		var snap := 0.0 if state.mode == ActorState.Mode.AIR else tuning.floor_snap_length
		var start := body.global_transform
		var wish := state.velocity
		body.slide(state, snap, dt)
		if state.mode == ActorState.Mode.GROUND:
			_step_up(body, state, start, wish, tuning, dt)

	# 8. Contactos: los indicadores de Godot pasan al estado, y la sonda de
	# suelo dice sobre qué base quedó parado. Al cambiar de base, la velocidad
	# pasa al marco de la nueva: quien deja una base se lleva su velocidad.
	# Todo se cuantiza, y el cuerpo arranca el tick siguiente desde la posición
	# cuantizada, igual que arrancaría después de restaurar. En los modos
	# anclados no hubo move_and_slide(): los indicadores de Godot quedaron
	# viejos. Colgado, la base es la del borde y la velocidad propia es cero
	# respecto de ella; en el mantle también es la del borde, y la velocidad,
	# la del mantle respecto de ella. Colgado de un compañero, la posición va en
	# el mundo.
	state.on_floor = body.is_on_floor() and not _is_anchored(state)
	state.floor_normal = body.get_floor_normal() if state.on_floor else Vector3.UP
	# Se quedó sin piso caminando o deslizándose: se cae de un borde sin saltar
	# (ver _air). De una base que se mueve, no: se lleva su velocidad, y frenar
	# en el aire lo dejaría atrás. Se borra al apoyarse o agarrarse de algo.
	if (state.mode == ActorState.Mode.GROUND or state.mode == ActorState.Mode.SLIDE) and not state.on_floor:
		state.walked_off = state.base_id == 0
	elif state.on_floor or _is_anchored(state):
		state.walked_off = false
	if state.mode == ActorState.Mode.HANGING or state.mode == ActorState.Mode.MANTLE:
		state.base_id = state.anchor_id
	else:
		var base_now := _probe_base(body) if state.on_floor else 0
		if base_now != state.base_id:
			state.velocity += BaseRegistry.velocity(state.base_id) - BaseRegistry.velocity(base_now)
			state.base_id = base_now
	# Solo se puede colgar alguien de un actor agarrado de un borde, de una
	# escalera o de un cable: si dejó de estarlo, ya no cuelga nadie de él. Lo
	# calculan igual el host y el cliente, así soltarse no necesita un evento
	# del host.
	if not holds_mates(state.mode):
		state.hooked_by = 0
	# El salto en el aire vuelve al apoyarse o agarrarse de algo.
	if state.mode != ActorState.Mode.AIR:
		state.jumped = false
	# Agarrarse de algo termina el ir derecho de la salida de la escalera.
	if _is_anchored(state):
		state.straight_out = false
	# La vuelta sola a la escalera es solo en el aire.
	if state.mode != ActorState.Mode.AIR:
		state.ladder_return = 0
	# Apoyado sobre una base, no puede alejarse de ella hacia arriba. Al aterrizar,
	# Godot deja en cero la velocidad vertical en el mundo; si la base baja, en su
	# marco eso sería subir, y el actor nunca pasaría a Suelo.
	if state.on_floor and state.base_id != 0:
		state.velocity.y = minf(state.velocity.y, 0.0)
	var origin := BaseRegistry.origin(state.base_id)
	state.position = body.global_position - origin
	state.quantize()
	body.global_position = origin + state.position


## Dirección pedida en el mundo, de largo hasta 1 (los ejes pueden ser parciales).
## Según la cámara, salvo yendo derecho al salir de una escalera (straight_out):
## ahí W va hacia donde mira el cuerpo, que es hacia donde subía.
static func _wish_direction(input: ActorInput, state: ActorState) -> Vector3:
	if state.straight_out:
		return Vector3.FORWARD.rotated(Vector3.UP, state.facing_yaw) * input.move.y
	var local := Vector3(input.move.x, 0.0, -input.move.y)
	return local.rotated(Vector3.UP, input.look_yaw)


## En Suelo: agachado va despacio; correr pide postura parada. Con el súper
## salto y velocidad, todo más rápido.
static func _ground_speed(state: ActorState, input: ActorInput, tuning: ActorTuning) -> float:
	var speed := tuning.walk_speed
	if state.stance == ActorState.Stance.CROUCHED:
		speed = tuning.crouch_speed
	elif input.is_held(ActorInput.BUTTON_RUN):
		speed = tuning.sprint_speed
	return speed


static func _horizontal_speed(state: ActorState) -> float:
	return Vector2(state.velocity.x, state.velocity.z).length()


## Modos anclados: la pose sale del ancla y se mueven con un barrido.
static func _is_anchored(state: ActorState) -> bool:
	return _anchored_mode(state.mode)


static func _anchored_mode(mode: int) -> bool:
	return mode == ActorState.Mode.LADDER or mode == ActorState.Mode.HANGING \
			or mode == ActorState.Mode.HOOKED or mode == ActorState.Mode.CABLE \
			or mode == ActorState.Mode.MANTLE


## Orientación de una dirección horizontal: 0 mira hacia -Z.
static func _yaw_of(v: Vector3) -> float:
	return atan2(-v.x, -v.z)


static func _ground(state: ActorState, wish: Vector3, tuning: ActorTuning, dt: float) -> void:
	var horizontal := Vector3(state.velocity.x, 0.0, state.velocity.z)
	var rate := tuning.ground_accel if wish.length_squared() > 0.0 else tuning.ground_decel
	horizontal = horizontal.move_toward(wish, rate * dt)
	# En Suelo la velocidad vertical es cero: las pendientes las resuelve el snap.
	state.velocity = horizontal


## En el aire, el control lleva hacia la dirección pedida sin frenar a quien
## venía más rápido que caminando (de una carrera o un deslizamiento); con el
## súper, que caminando con el súper. Cayéndose de
## un borde sin haber saltado (walked_off) y sin teclas, frena a
## walk_off_brake: en el aire nada más frena, y el último toque antes del borde
## lo llevaba mucho más lejos que en el piso (pedido del usuario, 2026-10-22).
static func _air(state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> void:
	var horizontal := Vector3(state.velocity.x, 0.0, state.velocity.z)
	if direction.length_squared() > 0.0:
		var wish := direction * maxf(tuning.walk_speed, horizontal.length())
		horizontal = horizontal.move_toward(wish, tuning.air_accel * dt)
	elif direction.length_squared() == 0.0 and state.walked_off and not state.jumped:
		horizontal = horizontal.move_toward(Vector3.ZERO, tuning.walk_off_brake * dt)
	var vertical := maxf(state.velocity.y - tuning.gravity * dt, -tuning.fall_limit())
	state.velocity = Vector3(horizontal.x, vertical, horizontal.z)


## Deslizamiento: frena por rozamiento, acelera en bajada y gira poco hacia la
## dirección pedida. Como en Suelo, la velocidad vertical es cero y el snap lo
## pega a la pendiente.
static func _slide(state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> void:
	var horizontal := Vector3(state.velocity.x, 0.0, state.velocity.z)
	var downhill := Vector3.DOWN.slide(state.floor_normal) * tuning.gravity
	horizontal += Vector3(downhill.x, 0.0, downhill.z) * dt
	horizontal = horizontal.move_toward(Vector3.ZERO, tuning.slide_friction * dt)
	if direction.length_squared() > 0.0001 and horizontal.length_squared() > 0.0001:
		var turn := wrapf(_yaw_of(direction) - _yaw_of(horizontal), -PI, PI)
		var limit := tuning.slide_turn_rate * dt
		horizontal = horizontal.rotated(Vector3.UP, clampf(turn, -limit, limit))
	state.velocity = horizontal.limit_length(tuning.slide_max_speed)


## Etapa 7, antes de mover: concede la postura pedida si cabe. Achicarse
## siempre cabe; crecer necesita espacio libre, y nunca se crece hacia un
## espacio ocupado. En el suelo la forma cambia con los pies fijos; en el
## aire, con la cabeza fija: agacharse sube los pies y pararse los baja (ver
## keeps_head). Encogido, si al tocar el piso un techo no lo deja pararse, se
## agacha, que siempre cabe: así encogido solo se está en el aire.
static func _resolve_stance(body: ActorBody, state: ActorState, wanted: int) -> void:
	state.stance_wanted = wanted
	if wanted == state.stance:
		return
	if not _change_stance(body, state, wanted) and state.stance == ActorState.Stance.TUCKED \
			and not keeps_head(state.mode, state.stance):
		_change_stance(body, state, ActorState.Stance.CROUCHED)


## Pasa a `stance` si cabe. Devuelve si pasó.
static func _change_stance(body: ActorBody, state: ActorState, stance: int) -> bool:
	var growth := body.stance_height(stance) - body.stance_height(state.stance)
	var feet := body.global_position
	if keeps_head(state.mode, state.stance):
		feet.y -= growth
	if growth > 0.0 and not body.stance_fits(stance, feet):
		return false
	state.stance = stance
	body.global_position = feet
	body.use_stance(stance)
	return true


## Al cambiar de postura, qué queda quieto. En el suelo, los pies: la cabeza
## sube o baja. En el aire, la cabeza: suben o bajan los pies. Al agarrarse de
## algo encogido también queda la cabeza, porque el agarre se midió desde donde
## estarían los pies parado (ver _standing_feet). `mode` es el modo del tick y
## `from_stance`, la postura que deja. Lo usan también el dibujo y la cámara.
static func keeps_head(mode: int, from_stance: int) -> bool:
	return mode == ActorState.Mode.AIR \
			or (from_stance == ActorState.Stance.TUCKED and _anchored_mode(mode))


## Dónde estarían los pies parado. Encogido, la cabeza está donde estaría
## parado y los pies, más arriba: las manos y la pose de los agarres se miden
## desde los pies de parado, así se agarra igual que sin encogerse.
static func _standing_feet(body: ActorBody, state: ActorState) -> Vector3:
	var feet := body.global_position
	if state.stance == ActorState.Stance.TUCKED:
		feet.y -= body.stance_height(ActorState.Stance.STANDING) - body.stance_height(ActorState.Stance.TUCKED)
	return feet


## Sonda de escalón de Suelo, en la etapa 7: el movimiento normal chocó contra
## algo. Desde donde arrancó el tick prueba subir hasta step_height, avanzar y
## bajar, y lo acepta solo si cae más arriba, en suelo caminable, y llega más
## lejos que el movimiento normal. Es un snap lógico: el cuerpo queda arriba en
## este tick, y la presentación reparte la subida.
##
## La parte de abajo de la cápsula es redonda: apoyada sobre el filo de un
## escalón, solo cuenta como suelo si el centro ya se acercó bastante al filo.
## Por eso, al subir, se acerca al escalón como mínimo eso, aunque vaya
## despacio o en diagonal. Y por lo mismo, el alto del escalón no sale de la
## cápsula, que puede quedar apoyada en el filo más abajo, sino de un rayo
## sobre la superficie que pisa.
static func _step_up(body: ActorBody, state: ActorState, start: Transform3D, wish: Vector3, tuning: ActorTuning, dt: float) -> void:
	if tuning.step_height <= 0.0 or not body.is_on_wall():
		return
	var motion := Vector3(wish.x, 0.0, wish.z) * dt
	if motion.length_squared() < 1e-8:
		return
	var direction := motion.normalized()
	var wall := body.get_wall_normal()
	var into := -Vector3(wall.x, 0.0, wall.z).normalized()
	var advanced := (body.global_position - start.origin).dot(direction)
	var reach := body.capsule_radius() * (1.0 - sin(body.floor_max_angle)) + 0.01
	var forward := motion + into * maxf(reach - motion.dot(into), 0.0)
	var hit := KinematicCollision3D.new()
	var rise := tuning.step_height
	if body.test_move(start, Vector3.UP * rise, hit):
		rise = hit.get_travel().y
	if rise < 0.01:
		return
	var raised := start.translated(Vector3.UP * rise)
	var travel := forward
	if body.test_move(raised, forward, hit):
		travel = hit.get_travel()
	if travel.dot(direction) <= advanced + 0.001:
		return
	var above := raised.translated(travel)
	if not body.test_move(above, Vector3.DOWN * rise, hit):
		return
	if hit.get_normal().angle_to(Vector3.UP) > body.floor_max_angle:
		return
	var landing := above.origin + hit.get_travel()
	var gained := landing.y - start.origin.y
	if gained < 0.01:
		return
	# Lo que pisa: un rayo justo pasando el punto de apoyo, desde la altura del
	# centro de la parte redonda. Tiene que ser suelo caminable, más arriba que
	# los pies y a no más de step_height del piso de partida.
	var spot := hit.get_position() + into * 0.02
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(spot.x, landing.y + body.capsule_radius(), spot.z),
			Vector3(spot.x, start.origin.y, spot.z), EdgeProbe.mask(body), [body.get_rid()])
	var ground := body.get_world_3d().direct_space_state.intersect_ray(ray)
	if ground.is_empty():
		return
	var top: float = ground["position"].y
	if top < landing.y - 0.005 or top - start.origin.y > tuning.step_height + 0.005:
		return
	if (ground["normal"] as Vector3).angle_to(Vector3.UP) > body.floor_max_angle:
		return
	body.global_position = landing
	body.settle_on_floor(tuning.floor_snap_length)
	state.velocity = Vector3(wish.x, 0.0, wish.z)
	body.snap_jump += Vector3.UP * gained


## Etapa 2: si el actor está sobre una base, lo lleva hasta donde quedó la base
## en este tick. Barre ignorando la base: si algo fijo le cierra el paso, el
## actor se baja ahí y se lleva la velocidad de la base. Si la base ya no
## existe, sigue desde donde estaba, sin base.
static func _ride_base(body: ActorBody, state: ActorState) -> void:
	if state.base_id == 0:
		return
	var base = BaseRegistry.find(state.base_id)
	if base == null:
		state.position = body.global_position
		state.base_id = 0
		return
	var motion: Vector3 = base.base_origin() + state.position - body.global_position
	if motion.length_squared() < 1e-12:
		return
	body.add_collision_exception_with(base)
	var blocked := body.move_and_collide(motion) != null
	body.remove_collision_exception_with(base)
	if blocked:
		state.velocity += base.base_velocity()
		state.position = body.global_position
		state.base_id = 0


## Sonda de suelo: una caja chica bajo el centro de los pies. Si toca una base,
## ese es el piso del actor; con varias gana el id más chico, así todas las
## máquinas eligen la misma aunque Jolt las devuelva en otro orden.
static func _probe_base(body: ActorBody) -> int:
	if _probe_params == null:
		var box := BoxShape3D.new()
		box.size = Vector3(0.2, 0.1, 0.2)
		_probe_params = PhysicsShapeQueryParameters3D.new()
		_probe_params.shape = box
	_probe_params.transform = Transform3D(Basis(), body.global_position + Vector3(0, -0.04, 0))
	_probe_params.collision_mask = body.collision_mask
	_probe_params.exclude = [body.get_rid()]
	var best := 0
	for hit in body.get_world_3d().direct_space_state.intersect_shape(_probe_params, 8):
		var id := BaseRegistry.id_of(hit["collider"])
		if id != 0 and (best == 0 or id < best):
			best = id
	return best


## Impulso de afuera, como un empujón, con su fuerza de 0 a 5. Es un evento:
## lo aplica quien lo maneja al empezar el tick, antes del paso, y sube la
## época del actor. Regla de fuerza contra agarre: en los modos libres
## (agarre 0) se suma y pasa a Aire, como el salto, así el snap no lo vuelve a
## pegar al piso. En un modo anclado, si la fuerza alcanza el agarre, se
## suelta y sale a Aire con el impulso y un bloqueo de reagarre; si no, el
## modo lo proyecta sobre lo que puede moverse (en Ladder, sobre el eje;
## colgado, sobre el filo; con un compañero colgado o colgado de un compañero,
## nada; en un cable, sobre el cable; en el mantle, nada: tiene el agarre de
## colgado) y el resto se descarta. Con un compañero colgado, el agarre es
## menor.
static func apply_impulse(state: ActorState, impulse: Vector3, force: int, tuning: ActorTuning) -> void:
	if state.mode == ActorState.Mode.MANTLE:
		if force >= tuning.hang_grip:
			_leave_mantle(state, tuning, impulse, true)
		return
	var load_drop := tuning.hook_load_grip_drop if state.hooked_by != 0 else 0
	if state.mode == ActorState.Mode.LADDER:
		if force >= tuning.ladder_grip - load_drop:
			_leave_anchor(state, tuning, impulse, true)
		else:
			state.velocity += impulse
		return
	if state.mode == ActorState.Mode.HANGING:
		if force >= tuning.hang_grip - load_drop:
			_leave_edge(state, tuning, impulse)
		else:
			state.velocity += impulse
		return
	if state.mode == ActorState.Mode.HOOKED:
		if force >= tuning.hook_grip:
			_leave_hook(state, tuning, impulse, true)
		return
	if state.mode == ActorState.Mode.CABLE:
		if force >= tuning.cable_grip - load_drop:
			_leave_cable(state, tuning, state.velocity + impulse)
		else:
			var cable := Cable.find(state.anchor_id)
			if cable != null:
				var tangent := cable.tangent_at(state.anchor_t)
				state.velocity += tangent * impulse.dot(tangent)
		return
	state.velocity += impulse
	state.mode = ActorState.Mode.AIR
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
	# Un empujón no es caerse de un borde: el aire no lo frena.
	state.walked_off = false


## Para validar una afirmación en un modo anclado: el ancla existe, el
## parámetro está en rango y el cuerpo está en la pose que le corresponde.
static func anchored_pose_valid(body: ActorBody, state: ActorState, tuning: ActorTuning) -> bool:
	if state.mode == ActorState.Mode.HOOKED:
		# El compañero existe, sigue agarrado y no cuelga otro de él; la pose,
		# cerca de la que da el compañero acá (el cliente lo vio en el pasado).
		# Las manos en la franja, y de uno en un borde o una escalera, no del lado
		# de la pared.
		var mate := body.teammate(state.anchor_id)
		if not _hook_holds(body, mate):
			return false
		if state.anchor_t < tuning.hook_min_height - ActorState.POSITION_STEP \
				or state.anchor_t > tuning.hook_max_height + ActorState.POSITION_STEP \
				or not _hook_side_allowed(mate, state.facing_yaw, tuning):
			return false
		return BaseRegistry.world_position(state).distance_to(hooked_pose(state, mate, tuning)) <= HOOK_TOLERANCE
	if state.mode == ActorState.Mode.HANGING:
		var edge := _held_edge(body, state, tuning)
		if edge.is_empty() or absf(state.anchor_t) >= PI * 0.5:
			return false
		return BaseRegistry.world_position(state).distance_to(_hang_pose(edge, tuning)) <= 0.1
	if state.mode == ActorState.Mode.MANTLE:
		# El borde sigue ahí y el cuerpo está en el camino del mantle: entre lo
		# más bajo desde donde pudo arrancar y el filo, y entre lo más lejos de
		# la cara desde donde pudo arrancar y donde termina.
		if not is_finite(state.anchor_t) or absf(state.anchor_t) > PI + MANTLE_SLACK:
			return false
		var edge := _mantle_edge(body, state)
		if edge.is_empty():
			return false
		var rel := BaseRegistry.world_position(state) - (edge["point"] as Vector3)
		var ahead := rel.dot(edge["normal"])
		return rel.y >= -tuning.mantle_max_height - MANTLE_SLACK and rel.y <= MANTLE_LIFT + MANTLE_SLACK \
				and ahead <= MANTLE_REACH and ahead >= -tuning.mantle_land - MANTLE_SLACK
	if state.mode == ActorState.Mode.CABLE:
		var cable := Cable.find(state.anchor_id)
		if cable == null or state.anchor_t < 0.0 or state.anchor_t > cable.length() + ActorState.POSITION_STEP:
			return false
		return BaseRegistry.world_position(state).distance_to(_cable_pose(cable, state.anchor_t, tuning)) <= 0.1
	if state.mode != ActorState.Mode.LADDER:
		return true
	var ladder := Ladder.find(state.anchor_id)
	if ladder == null or state.anchor_t < 0.0:
		return false
	var side := ladder.side_of_yaw(state.facing_yaw)
	# Pasado el alto, en el tramo de la salida por arriba, si se puede salir.
	if state.anchor_t > ladder.height + ActorState.POSITION_STEP \
			and state.anchor_t > ladder.height + ladder_exit_length(body, ladder, side, tuning) + ActorState.POSITION_STEP:
		return false
	return BaseRegistry.world_position(state).distance_to(ladder_pose(ladder, state.anchor_t, side)) <= 0.1


## Ladder desde Suelo o Aire: dentro del volumen de una escalera, de
## cualquiera de sus lados, con intención de ir hacia ella y a no más de
## ladder_grab_side de su eje, de costado. Desde atrás (desde el 2026-10-20,
## pedido del usuario), solo si la escalera tiene lugar detrás al pie
## (Ladder.back_open). De los dos lados, el cuerpo tiene que caber en la pose y
## el camino hasta ella tiene que estar libre (ver _ladder_blocked). Parado en
## el piso, en el tramo de arriba (ladder_top_no_grab) no se agarra: ahí está
## parado en el filo de arriba, no yendo a trepar (pedido del usuario,
## 2026-10-22). Con varias,
## gana la de id más chico, así todas las máquinas eligen la misma. La que se
## acaba de soltar está bloqueada un rato. Con Ctrl no se llama. El cuerpo va a
## la pose de golpe en la etapa 7; el dibujo lo alcanza como en el agarre de un
## borde (grab_jump).
static func _try_grab_ladder(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, look := Vector3.ZERO) -> bool:
	# Saltando para arriba desde un borde (encogido, ver tuck), sin teclas
	# alcanza con mirar la escalera, como para agarrar un borde (pedido del
	# usuario, 2026-10-21: colgado de una pilastra con la escalera arriba, sin
	# W subía y volvía a caer). Con A o D no: apuntan a otro lado.
	if direction.length_squared() < 0.01 and state.stance == ActorState.Stance.TUCKED:
		direction = look
	if direction.length_squared() < 0.01:
		return false
	var feet := _standing_feet(body, state)
	# Ladder.all() ya viene en orden de número, igual en todas las máquinas.
	for ladder: Ladder in Ladder.all():
		if ladder.ladder_id == state.regrab_id:
			continue
		var side := ladder.side_for(feet)
		if side == 0.0 or direction.dot(-ladder.face(side)) < 0.5:
			continue
		if absf(ladder.across(feet)) > tuning.ladder_grab_side:
			continue
		var t := ladder.height_for(feet, side)
		if state.mode == ActorState.Mode.GROUND and t > 0.0 and t > ladder.height - tuning.ladder_top_no_grab:
			continue
		if _ladder_blocked(body, ladder, t, feet, side):
			continue
		_grab_ladder(body, state, ladder, t, feet, side)
		return true
	return false


## Si no se puede agarrar de la escalera del lado `side` a la altura t: el
## cuerpo no cabe en la pose (por atrás, debajo de un balcón, más arriba de lo
## que se puede trepar por ese lado) o algo tapa el camino hasta ella (una
## pared fina, o un larguero: de costado, el cuerpo quedaba trabado contra él,
## colgado al lado de la escalera y sin poder subir; arreglado el 2026-10-22).
## Por atrás, además, más arriba del pie, si hay piso debajo de los pies: es
## el rellano al que se sale por arriba, como el balcón de la escalera de la
## corona; ahí uno está parado al lado de la escalera, no colgado de ella
## (pedido del usuario, 2026-10-20).
static func _ladder_blocked(body: ActorBody, ladder: Ladder, t: float, feet: Vector3, side: float) -> bool:
	var pose := ladder.pose_at(t, side)
	if side < 0.0 and t > LADDER_BACK_FOOT:
		var ray := PhysicsRayQueryParameters3D.create(pose + Vector3.UP * 0.05,
				pose + Vector3.DOWN * LADDER_BACK_FLOOR, EdgeProbe.mask(body), [body.get_rid()])
		if not body.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			return true
	return not body.stance_fits(ActorState.Stance.STANDING, pose) or body.test_move(body.global_transform, pose - feet)


## Vuelve sola, sin teclas, a la escalera que dejó saltando mirándola o con
## Ctrl (ladder_return): bajando, frente a ella y pasado el bloqueo de
## reagarre. Si el salto pasó por encima del final, se agarra al volver a bajar
## hasta ella (pedido del usuario, 2026-10-16). Con Ctrl no se llama.
static func _return_to_ladder(body: ActorBody, state: ActorState) -> bool:
	if state.ladder_return == 0 or state.velocity.y > 0.0 or state.regrab_id == state.ladder_return:
		return false
	var ladder := Ladder.find(state.ladder_return)
	if ladder == null:
		return false
	var feet := _standing_feet(body, state)
	var side := ladder.side_for(feet)
	if side == 0.0:
		return false
	var t := ladder.height_for(feet, side)
	if _ladder_blocked(body, ladder, t, feet, side):
		return false
	_grab_ladder(body, state, ladder, t, feet, side)
	return true


## Se agarra de la escalera del lado `side` (1 adelante, -1 atrás): el lado
## queda en hacia dónde mira, que es hacia la escalera (facing_yaw), así no
## hace falta otro dato en el estado ni en la red.
static func _grab_ladder(body: ActorBody, state: ActorState, ladder: Ladder, t: float, feet: Vector3, side: float) -> void:
	body.grab_jump += ladder.pose_at(t, side) - feet
	state.facing_yaw = _yaw_of(-ladder.face(side))
	state.mode = ActorState.Mode.LADDER
	state.anchor_id = ladder.ladder_id
	state.anchor_t = t
	state.velocity = Vector3.ZERO
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0


## Sale de un ancla a Aire con una velocidad. Si `block`, no se la puede
## volver a agarrar por un rato (salto o empujón: todavía está al alcance).
static func _leave_anchor(state: ActorState, tuning: ActorTuning, velocity: Vector3, block: bool) -> void:
	if block:
		state.regrab_id = state.anchor_id
		state.regrab_left = tuning.regrab_block_time
	state.mode = ActorState.Mode.AIR
	state.velocity = velocity
	state.anchor_id = 0
	state.anchor_t = 0.0
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0


## Ladder: la velocidad va sobre el eje. W sube y S baja, mire donde mire la
## cámara (`climb` es el eje adelante-atrás de las teclas); A y D no hacen nada.
## Hasta el 2026-10-16 contaba hacia dónde apuntaban las teclas según la
## cámara: hacia la escalera subía y alejándose bajaba, así que mirando para
## atrás W bajaba. Lo que llegó de afuera (un empujón menor al agarre) queda
## proyectado sobre el eje y se va frenando. Con un compañero colgado, se queda
## quieto. Pasado el alto, si se puede salir (`exit_length`, el largo de ese tramo; ver
## ladder_exit_length), la altura sigue por el tramo de la salida, con las
## mismas teclas. Donde ese tramo va hacia el rellano, va como caminando:
## walk_speed, con ground_accel y
## ground_decel (pedido del usuario, 2026-10-23: a climb_speed "se sienten
## horribles"); de vuelta a la parte que sube, otra vez a climb_speed como mucho.
static func _ladder(state: ActorState, climb: float, exit_length: float, tuning: ActorTuning, dt: float) -> void:
	var ladder := Ladder.find(state.anchor_id)
	if ladder == null:
		return
	var side := ladder.side_of_yaw(state.facing_yaw)
	var along := state.velocity.dot(_ladder_tangent(ladder, state.anchor_t, side))
	var walking := state.anchor_t >= ladder.height + LADDER_EXIT_LIFT
	var wish := clampf(climb, -1.0, 1.0) * tuning.climb_speed
	var rate := tuning.climb_accel
	if walking:
		wish = clampf(climb, -1.0, 1.0) * tuning.walk_speed
		rate = tuning.ground_accel if wish != 0.0 else tuning.ground_decel
	along = move_toward(along, wish, rate * dt)
	if state.hooked_by != 0:
		along = 0.0
	var top := ladder.height + exit_length
	var t := state.anchor_t + along * dt
	if walking and t < ladder.height + LADDER_EXIT_LIFT:
		along = clampf(along, -tuning.climb_speed, tuning.climb_speed)
	# Al final del tramo, con W, la velocidad queda: al terminar sigue caminando
	# (ver _finish_ladder_exit).
	if t <= 0.0 or (t >= top and not (walking and climb > 0.0)):
		along = 0.0
	state.anchor_t = clampf(t, 0.0, top)
	state.velocity = _ladder_tangent(ladder, state.anchor_t, side) * along
	state.facing_yaw = _yaw_of(-ladder.face(side))


## Etapa 7 en Ladder: un barrido hasta la pose de la altura pedida. Si algo lo
## frena, la altura queda donde llegó.
static func _move_on_ladder(body: ActorBody, state: ActorState) -> void:
	var ladder := Ladder.find(state.anchor_id)
	if ladder == null:
		return
	var side := ladder.side_of_yaw(state.facing_yaw)
	var motion := ladder_pose(ladder, state.anchor_t, side) - body.global_position
	if motion.length_squared() < 1e-12:
		return
	if body.move_and_collide(motion) != null:
		state.anchor_t = _ladder_t_of(ladder, side, body.global_position)
		state.velocity = Vector3.ZERO


## Salida por arriba, sin saltito (pedido del usuario, 2026-10-23: "averigua la
## manera de quitar [el saltito], no importa como"). Pasado el alto, la altura
## sobre la escalera (anchor_t) sigue por un tramo: el cuerpo, todavía en la
## escalera, sube LADDER_EXIT_LIFT, y después avanza hacia el rellano Standoff más
## ladder_top_land (o solo Standoff, hasta el eje, si ahí no hay piso: una
## escalera suelta, y queda parado arriba de ella). Sube a climb_speed y hacia
## el rellano va a walk_speed (ver _ladder), con W;
## vuelve con S y sin teclas se queda donde está, salvo que el centro del
## cuerpo ya tenga piso debajo: ahí termina la escalera y frena caminando
## (pedido del usuario, 2026-10-28); al final queda parado arriba,
## quieto (_finish_ladder_exit). Hasta entonces, un saltito por el aire lo
## llevaba al rellano (hasta el 2026-10-22, a 2,5 m/s y con W empujando en el
## aire; después, justo hasta ladder_top_land).
## Devuelve el largo de ese tramo, o 0 si algo lo tapa: ahí no se sale, y
## arriba de todo se queda en la escalera. El camino se prueba desde la pose de
## arriba de todo, así da lo mismo en todas las máquinas.
static func ladder_exit_length(body: ActorBody, ladder: Ladder, side: float, tuning: ActorTuning) -> float:
	var out := ladder.face(side)
	var lift := LADDER_EXIT_LIFT
	var land := tuning.ladder_top_land
	if ladder.collides and ladder.show_pieces and not _floor_behind_top(body, ladder, out, land):
		land = 0.0
	var over := ladder.standoff + land
	var top := Transform3D(body.global_basis, ladder.pose_at(ladder.height, side))
	if body.test_move(top, ladder.up() * lift) or body.test_move(top.translated(ladder.up() * lift), -out * over):
		return 0.0
	return lift + over


## Dónde van los pies a la altura t, del lado `side`: sobre la escalera hasta el
## alto; pasado el alto, por el tramo de la salida por arriba, primero para
## arriba y después hacia el rellano (ver ladder_exit_length).
static func ladder_pose(ladder: Ladder, t: float, side: float) -> Vector3:
	if t <= ladder.height:
		return ladder.pose_at(t, side)
	var past := t - ladder.height
	return ladder.pose_at(ladder.height, side) + ladder.up() * minf(past, LADDER_EXIT_LIFT) - ladder.face(side) * maxf(past - LADDER_EXIT_LIFT, 0.0)


## Hacia dónde va el tramo a la altura t: para arriba, y en la salida por
## arriba, después de subir, hacia el rellano.
static func _ladder_tangent(ladder: Ladder, t: float, side: float) -> Vector3:
	if t < ladder.height + LADDER_EXIT_LIFT:
		return ladder.up()
	return -ladder.face(side)


## La altura sobre la escalera (o sobre el tramo de la salida) de unos pies
## cerca de la escalera: para cuando algo frena el barrido a la pose.
static func _ladder_t_of(ladder: Ladder, side: float, feet: Vector3) -> float:
	var rel := feet - ladder.pose_at(ladder.height, side)
	var rise := rel.dot(ladder.up())
	if rise <= 0.0:
		return clampf((feet - ladder.pose_at(0.0, side)).dot(ladder.up()), 0.0, ladder.height)
	return ladder.height + minf(rise, LADDER_EXIT_LIFT) + maxf(-rel.dot(ladder.face(side)), 0.0)


## Terminó el tramo de la salida por arriba: pasa a Suelo y el cuerpo
## baja en el acto hasta el rellano (o el peldaño de arriba), lo poco que
## había subido para pasar; el dibujo lo acompaña suave
## (snap_jump). Sin eso, el snap no lo apoyaba (el tick anterior no estaba en
## el piso) y caía unos ticks. La escalera queda bloqueada un rato, como al soltarse. En tercera
## persona y mirando para atrás, desde acá va derecho (straight_out) mientras
## siga con W sola, así no vuelve hacia la escalera; si no, W va según la
## cámara (ver straight_exit). Con W apretada sigue caminando a la velocidad
## que traía, sin pausa (pedido del usuario, 2026-10-23: "te pega una pausa y
## despues volves a moverte"); sin W, queda quieto, así arriba de una escalera
## suelta no se sale del otro lado.
static func _finish_ladder_exit(body: ActorBody, state: ActorState, ladder: Ladder, input: ActorInput, tuning: ActorTuning) -> void:
	state.regrab_id = ladder.ladder_id
	state.regrab_left = tuning.regrab_block_time
	state.mode = ActorState.Mode.GROUND
	if input.move.y <= 0.0:
		state.velocity = Vector3.ZERO
	state.anchor_id = 0
	state.anchor_t = 0.0
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
	state.straight_out = straight_exit(input, state.facing_yaw, tuning)
	var before := body.global_position
	body.settle_on_floor(tuning.floor_snap_length)
	body.snap_jump += body.global_position - before


## Si hay piso donde termina la salida por arriba, `land` detrás del eje de la
## escalera, del lado contrario a `out`: un rayo de LADDER_TOP_FLOOR para
## arriba y para abajo del alto de la escalera. Las piezas de la escalera no
## cuentan (EdgeProbe.mask).
static func _floor_behind_top(body: ActorBody, ladder: Ladder, out: Vector3, land: float) -> bool:
	var spot := ladder.global_position + ladder.up() * ladder.height - out * land
	var ray := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * LADDER_TOP_FLOOR,
			spot + Vector3.DOWN * LADDER_TOP_FLOOR, EdgeProbe.mask(body), [body.get_rid()])
	return not body.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


## Si la salida por arriba de una escalera va derecho: con la cámara en
## tercera persona y mirando a más de ladder_exit_back_angle de `ahead_yaw`,
## hacia donde subía. Ahí W, según la cámara, lo llevaría de vuelta a la
## escalera y se caería. En primera persona, o mirando hacia adelante o de
## costado, W va según la cámara (pedido del usuario, 2026-10-20: la guarda
## servía en ese caso y molestaba en los demás). Lo usan el motor y el panel.
static func straight_exit(input: ActorInput, ahead_yaw: float, tuning: ActorTuning) -> bool:
	if not input.is_held(ActorInput.BUTTON_THIRD_PERSON):
		return false
	var look := Vector3.FORWARD.rotated(Vector3.UP, input.look_yaw)
	var ahead := Vector3.FORWARD.rotated(Vector3.UP, ahead_yaw)
	return look.dot(ahead) < cos(tuning.ladder_exit_back_angle)


## Hanging desde Aire: si grab_check() encuentra un borde que se puede agarrar,
## entra a Hanging; en la etapa 7 de este mismo tick el cuerpo va a la pose de
## colgado. Es un snap lógico; la presentación lo suaviza. Devuelve el borde
## agarrado, o vacío.
static func _try_grab_edge(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> Dictionary:
	var check := grab_check(body, state, direction, tuning, dt)
	if check["why"] != "":
		return {}
	var edge: Dictionary = check["edge"]
	var pose: Vector3 = check["pose"]
	var from := _standing_feet(body, state)
	state.mode = ActorState.Mode.HANGING
	state.anchor_id = edge["base"]
	state.anchor_point = edge["point"] - BaseRegistry.origin(edge["base"])
	state.anchor_t = 0.0
	state.corner_inside = false
	state.velocity = Vector3.ZERO
	state.facing_yaw = _yaw_of(-edge["normal"])
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
	body.grab_jump += pose - from
	if check["from_above"]:
		body.grab_jump_speed = tuning.hang_drop_speed
	return edge


## La decisión del agarre, sin cambiar nada: barre las manos desde donde están
## hasta donde van a estar al final de este tick, hacia `direction`: hacia
## donde mira la cámara (ver grab_direction). La pared tiene que estar en esa
## dirección.
## Subiendo también agarra, pero recién cuando las manos llegan al filo: la
## pose no puede quedar más de hang_rise_reach por encima de los pies. Si en
## este tick o en el anterior (el del salto, que todavía era Suelo) las manos
## ya pasaron el filo, lo buscan de arriba hacia abajo.
## Si las manos no tocaron nada, busca un filo debajo de ellas, hasta
## hang_reach_down (from_above): llegó a la pared con las manos por encima del
## filo, y se agarra en el acto, con el cuerpo bajando hasta colgar (pedido del
## usuario, 2026-10-19). Subiendo, no, si ese salto le lleva los pies arriba
## del filo: ahí sigue y cae arriba.
## El filo se toma enfrente del centro del cuerpo (las manos pueden quedar
## corridas si llega en diagonal), si el borde sigue ahí. Valida la pose de
## colgado: cabe, el camino hasta ella está libre, queda a menos de
## hang_snap_max (desde arriba, de costado; para abajo, hasta hang_reach_down)
## y no cae delante de una escalera (Ladder.any_at). Devuelve {edge, pose, why,
## from_above}: why vacío si se puede agarrar, o por qué no. Lo usan el motor y
## las pruebas de confirmación.
## Agachado no agarra; encogido sí, y todo se mide desde donde estarían los
## pies parado (_standing_feet).
static func grab_check(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> Dictionary:
	var result := {"edge": {}, "pose": Vector3.ZERO, "why": "sin borde", "from_above": false}
	if state.regrab_id == ActorState.REGRAB_EDGES or state.stance == ActorState.Stance.CROUCHED:
		result["why"] = "bloqueo o postura"
		return result
	if direction.length_squared() < 0.01:
		result["why"] = "sin dirección"
		return result
	var toward := Vector3(direction.x, 0.0, direction.z).normalized()
	var from := _standing_feet(body, state)
	var fall := maxf(state.velocity.y - tuning.gravity * dt, -tuning.fall_limit())
	var motion := Vector3(state.velocity.x, fall, state.velocity.z) * dt
	var hands_to := EdgeProbe.hands_at(body, from + motion, toward, tuning)
	var edge := EdgeProbe.find(body, EdgeProbe.hands_at(body, from, toward, tuning), hands_to, toward)
	var rising := state.velocity.y > 0.0
	if edge.is_empty() and rising:
		var hands_before := EdgeProbe.hands_at(body, from - state.velocity * dt, toward, tuning)
		edge = EdgeProbe.find(body, hands_to, hands_before, toward)
	var from_above := false
	if edge.is_empty() and tuning.hang_reach_down > 0.0:
		var hands := EdgeProbe.hands_at(body, from, toward, tuning)
		edge = EdgeProbe.find(body, hands, hands + Vector3.DOWN * tuning.hang_reach_down, toward)
		if not edge.is_empty() and edge["point"].y > hands.y:
			edge = {}
		from_above = not edge.is_empty()
	if edge.is_empty():
		return result
	var normal: Vector3 = edge["normal"]
	var right := (-normal).cross(Vector3.UP)
	var ahead := EdgeProbe.hold(body, edge["point"] + right * (from - edge["point"]).dot(right), normal)
	if not ahead.is_empty():
		edge = ahead
	result["edge"] = edge
	result["pose"] = _hang_pose(edge, tuning)
	result["from_above"] = from_above
	var drop: Vector3 = from - result["pose"]
	if toward.dot(-edge["normal"]) < 0.5:
		result["why"] = "intención de costado"
	elif rising and result["pose"].y > from.y + tuning.hang_rise_reach:
		result["why"] = "subiendo, las manos todavía no llegan"
	elif from_above and rising and from.y + state.velocity.y * state.velocity.y / (2.0 * tuning.gravity) > edge["point"].y:
		result["why"] = "subiendo, el salto pasa arriba del filo"
	elif from.y + body.stance_height(ActorState.Stance.STANDING) * 0.5 > edge["point"].y:
		# Con el cuerpo por encima del filo es un aterrizaje, no un agarre.
		result["why"] = "por encima del filo"
	elif not from_above and drop.length() > tuning.hang_snap_max:
		result["why"] = "snap muy largo"
	elif from_above and (Vector2(drop.x, drop.z).length() > tuning.hang_snap_max or drop.y > tuning.hang_reach_down):
		result["why"] = "snap muy largo"
	elif not body.stance_fits(ActorState.Stance.STANDING, result["pose"]):
		result["why"] = "la pose no cabe"
	elif body.test_move(body.global_transform, result["pose"] - from):
		result["why"] = "camino tapado"
	elif Ladder.any_at(result["pose"]):
		result["why"] = "delante de una escalera"
	else:
		result["why"] = ""
	return result


## Hacia dónde buscan las manos un borde o un compañero: hacia donde mira la
## cámara, con o sin teclas. Así hay que mirar la pared para agarrarse, y no
## hace falta apretar W. Lo usan el motor y las pruebas de confirmación.
static func grab_direction(look_yaw: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, look_yaw)


## El borde agarrado, revalidado con la sonda: el punto guardado y la normal
## contraria a la orientación. Vacío si el borde ya no está o si desapareció
## la base que lo llevaba.
##
## Doblando una esquina (anchor_t distinto de 0, ver _hang), el punto guardado
## es la esquina y la normal va girando entre las de las dos caras: se
## revalidan las dos caras, cada una un poco antes de la esquina.
static func _held_edge(body: ActorBody, state: ActorState, tuning: ActorTuning) -> Dictionary:
	if state.anchor_id != 0 and BaseRegistry.find(state.anchor_id) == null:
		return {}
	var point := BaseRegistry.origin(state.anchor_id) + state.anchor_point
	var normal := -Vector3.FORWARD.rotated(Vector3.UP, state.facing_yaw)
	if state.anchor_t == 0.0:
		return EdgeProbe.hold(body, point, normal)
	var spin := signf(state.anchor_t)
	var first := normal.rotated(Vector3.UP, -state.anchor_t)
	var second := first.rotated(Vector3.UP, spin * PI * 0.5)
	# Por afuera, las dos caras siguen detrás de la esquina; por adentro, cada
	# una sigue a lo largo de la normal de la otra.
	var first_at := point + second * CORNER_PROBE if state.corner_inside \
			else point + first.cross(Vector3.UP) * spin * CORNER_INSET
	var second_at := point + first * CORNER_PROBE if state.corner_inside else point - first * CORNER_INSET
	var first_side := EdgeProbe.hold(body, first_at, first)
	var second_side := EdgeProbe.hold(body, second_at, second)
	if first_side.is_empty() or second_side.is_empty():
		return {}
	return _arc_edge(point, first, state.anchor_t, state.corner_inside, first_side["base"], tuning)


## El borde a mitad de una esquina, para `angle` girado desde la normal
## `first` de la cara donde empezó. Por afuera, el punto es la esquina: el
## cuerpo gira a hang_distance de ella. Por adentro, el cuerpo va por una
## curva de hang_corner_radius que toca el camino de colgado de las dos caras;
## el punto es el del filo que tendría delante, que queda en el aire, y la
## esquina va aparte, en "corner".
static func _arc_edge(corner: Vector3, first: Vector3, angle: float, inside: bool, base: int, tuning: ActorTuning) -> Dictionary:
	var bent := first.rotated(Vector3.UP, angle)
	if not inside:
		return {"point": corner, "normal": bent, "base": base, "corner": corner}
	var second := first.rotated(Vector3.UP, signf(angle) * PI * 0.5)
	var reach := tuning.hang_distance + tuning.hang_corner_radius
	var center := corner + (first + second) * reach
	return {"point": center - bent * reach, "normal": bent, "base": base, "corner": corner}


## Hanging, etapa 6: se desplaza sobre el filo. La velocidad va a lo largo del
## filo y la deja un empujón menor al agarre o la pide el input lateral, A y D,
## que es la izquierda y la derecha del personaje frente a la pared, mire donde
## mire la cámara. Solo avanza si el borde sigue, no entra delante de una
## escalera y el cuerpo pasa. Con un compañero colgado, se queda quieto.
##
## Las esquinas en ángulo recto se doblan sin soltarse, con una curva
## continua de una cara a la otra:
## - Por afuera, donde el filo se termina y sigue por la cara de al lado: el
##   cuerpo da la vuelta a la esquina por un cuarto de círculo, a la misma
##   velocidad, con las manos en la esquina.
## - Por adentro (un rincón), donde una pared de frente corta el paso y su
##   filo sigue a la misma altura: hang_corner_radius antes de llegar, el
##   cuerpo empieza una curva que lo deja en el camino de colgado de esa pared.
##   Si ya está más cerca que eso (se agarró pegado al rincón), al chocar se da
##   vuelta hacia la otra pared en el lugar.
## Mientras dobla, anchor_t dice cuánto giró la normal desde la cara donde
## empezó (en radianes, con signo), corner_inside si es un rincón, y
## anchor_point es la esquina.
## Devuelve el borde donde quedó.
static func _hang(body: ActorBody, state: ActorState, edge: Dictionary, input: ActorInput, tuning: ActorTuning, dt: float) -> Dictionary:
	if edge.is_empty():
		return edge
	var normal: Vector3 = edge["normal"]
	var right := (-normal).cross(Vector3.UP)
	var wish := clampf(input.move.x, -1.0, 1.0) * tuning.shimmy_speed
	var along := move_toward(state.velocity.dot(right), wish, tuning.climb_accel * dt)
	if state.hooked_by != 0:
		along = 0.0
	state.velocity = right * along
	if state.anchor_t != 0.0:
		edge = _round_corner(body, state, edge, along, tuning, dt)
	elif absf(along) > 0.001:
		var turn := signf(along)
		var stride := absf(along) * dt
		var turned := _inside_arc(body, state, edge, turn, stride, tuning)
		if turned.is_empty():
			var moved := EdgeProbe.hold(body, edge["point"] + right * along * dt, normal)
			var from := _hang_pose(edge, tuning)
			var to := _hang_pose(moved, tuning) if not moved.is_empty() else from
			if moved.is_empty():
				var corner := _outer_corner(body, edge, turn, tuning)
				if not corner.is_empty():
					state.anchor_t = turn * maxf(stride / tuning.hang_distance, CORNER_MIN_TURN)
					state.corner_inside = false
					turned = _arc_edge(corner["point"], normal, state.anchor_t, false, corner["base"], tuning)
			elif not Ladder.any_at(to) and body.test_move(Transform3D(body.global_basis, from), to - from):
				turned = _inner_corner(body, edge, turn, tuning)
			elif not Ladder.any_at(to):
				turned = moved
		if turned.is_empty():
			state.velocity = Vector3.ZERO
		else:
			edge = turned
			state.velocity = (-edge["normal"] as Vector3).cross(Vector3.UP) * along
	state.anchor_point = edge.get("corner", edge["point"]) - BaseRegistry.origin(state.anchor_id)
	state.facing_yaw = _yaw_of(-edge["normal"])
	return edge


## Por adentro, con curva: si hacia donde va hay un rincón (una pared de
## frente en ángulo recto, con el filo a la misma altura) y en este paso llega
## a donde empieza la curva, la empieza y devuelve el borde a mitad de ella;
## si no, vacío. La curva tiene que estar libre de punta a punta.
static func _inside_arc(body: ActorBody, state: ActorState, edge: Dictionary, turn: float, stride: float, tuning: ActorTuning) -> Dictionary:
	var point: Vector3 = edge["point"]
	var normal: Vector3 = edge["normal"]
	var ahead := (-normal).cross(Vector3.UP) * turn
	var radius := tuning.hang_corner_radius
	var reach := tuning.hang_distance + radius
	var from := point + normal * CORNER_INSET + Vector3.DOWN * EdgeProbe.FACE_DROP
	var hit := _corner_ray(body, from, from + ahead * (reach + stride + 0.05))
	if hit.is_empty() or (hit["normal"] as Vector3).dot(-ahead) < CORNER_SQUARE:
		return {}
	var corner: Vector3 = point + ahead * (hit["position"] - point).dot(ahead)
	var now := (corner - point).dot(ahead)
	if now < reach - CORNER_SLACK or now - stride >= reach:
		return {}
	# Por adentro la normal gira al revés de hacia donde va.
	var spin := -turn
	var second := normal.rotated(Vector3.UP, spin * PI * 0.5)
	var side := EdgeProbe.hold(body, corner + normal * reach, second)
	if side.is_empty() or absf(side["point"].y - point.y) > CORNER_HEIGHT:
		return {}
	# El camino: hasta donde empieza la curva y la curva, de a tramos.
	var center := corner + (normal + second) * reach
	var at := _hang_pose(edge, tuning)
	for i in CORNER_SWEEP_STEPS + 1:
		var bent := normal.rotated(Vector3.UP, spin * PI * 0.5 * i / CORNER_SWEEP_STEPS)
		var next: Vector3 = center - bent * radius + Vector3.DOWN * tuning.hang_height
		if body.test_move(Transform3D(body.global_basis, at), next - at):
			return {}
		at = next
	if Ladder.any_at(at):
		return {}
	state.anchor_t = spin * maxf((stride - (now - reach)) / radius, CORNER_MIN_TURN)
	state.corner_inside = true
	return _arc_edge(corner, normal, state.anchor_t, true, edge["base"], tuning)


## Por afuera: el filo se terminó entre el punto agarrado y el próximo. Si es
## una esquina en ángulo recto (la cara de al lado mira hacia donde va y su
## filo sigue a la misma altura) y el cuerpo puede dar la vuelta sin chocar,
## devuelve el borde en la esquina, con la normal de la cara donde está; si
## no, vacío.
static func _outer_corner(body: ActorBody, edge: Dictionary, turn: float, tuning: ActorTuning) -> Dictionary:
	var point: Vector3 = edge["point"]
	var normal: Vector3 = edge["normal"]
	var ahead := (-normal).cross(Vector3.UP) * turn
	# La cara de la punta: un rayo desde más allá, apenas detrás de la cara
	# de enfrente, que vuelve hacia atrás.
	var from := point + ahead * 0.5 - normal * CORNER_INSET + Vector3.DOWN * EdgeProbe.FACE_DROP
	var hit := _corner_ray(body, from, from - ahead * 0.6)
	if hit.is_empty() or (hit["normal"] as Vector3).dot(ahead) < CORNER_SQUARE:
		return {}
	var corner: Vector3 = point + ahead * (hit["position"] - point).dot(ahead)
	var side := EdgeProbe.hold(body, corner - normal * CORNER_INSET, hit["normal"])
	if side.is_empty() or absf(side["point"].y - point.y) > CORNER_HEIGHT:
		return {}
	# El camino: hasta la esquina y la vuelta, de a tramos.
	var at := _hang_pose(edge, tuning)
	for i in CORNER_SWEEP_STEPS + 1:
		var bent := normal.rotated(Vector3.UP, turn * PI * 0.5 * i / CORNER_SWEEP_STEPS)
		var next: Vector3 = corner + bent * tuning.hang_distance + Vector3.DOWN * tuning.hang_height
		if body.test_move(Transform3D(body.global_basis, at), next - at):
			return {}
		at = next
	if Ladder.any_at(at):
		return {}
	return {"point": corner, "normal": normal, "base": edge["base"]}


## Por adentro, sin lugar para la curva (se agarró pegado al rincón): el
## cuerpo choca contra algo hacia donde va. Si es una pared en ángulo recto
## con un filo a la misma altura, devuelve ese borde, en el punto donde la pose
## de colgado de esa pared es la de la esquina; si no, vacío.
static func _inner_corner(body: ActorBody, edge: Dictionary, turn: float, tuning: ActorTuning) -> Dictionary:
	var point: Vector3 = edge["point"]
	var normal: Vector3 = edge["normal"]
	var ahead := (-normal).cross(Vector3.UP) * turn
	var from := point + normal * CORNER_INSET + Vector3.DOWN * EdgeProbe.FACE_DROP
	var hit := _corner_ray(body, from, from + ahead * 0.8)
	if hit.is_empty() or (hit["normal"] as Vector3).dot(-ahead) < CORNER_SQUARE:
		return {}
	var corner: Vector3 = point + ahead * (hit["position"] - point).dot(ahead)
	var side := EdgeProbe.hold(body, corner + normal * tuning.hang_distance, hit["normal"])
	if side.is_empty() or absf(side["point"].y - point.y) > CORNER_HEIGHT:
		return {}
	var at := _hang_pose(edge, tuning)
	var to := _hang_pose(side, tuning)
	if Ladder.any_at(to) or body.test_move(Transform3D(body.global_basis, at), to - at):
		return {}
	return side


## Doblando: avanza el giro, a la velocidad de siempre sobre la curva. Al
## volver a cero queda en la cara donde empezó; al llegar al cuarto de vuelta,
## en la otra. Por afuera, un poco adentro de la cara, donde la sonda la
## encuentra; por adentro, donde termina la curva, un poco más allá para que
## al volver la vuelva a encontrar.
static func _round_corner(body: ActorBody, state: ActorState, edge: Dictionary, along: float, tuning: ActorTuning, dt: float) -> Dictionary:
	var corner: Vector3 = edge["corner"]
	var spin := signf(state.anchor_t)
	var first := (edge["normal"] as Vector3).rotated(Vector3.UP, -state.anchor_t)
	var second := first.rotated(Vector3.UP, spin * PI * 0.5)
	var inside := state.corner_inside
	var reach := tuning.hang_distance + tuning.hang_corner_radius + CORNER_SLACK
	# Por afuera la normal gira hacia donde va; por adentro, al revés.
	var angle := state.anchor_t
	if inside:
		angle -= along * dt / tuning.hang_corner_radius
	else:
		angle += along * dt / tuning.hang_distance
	var landed := {}
	if angle * spin <= 0.0:
		var back := corner + second * reach if inside else corner + first.cross(Vector3.UP) * spin * CORNER_INSET
		landed = EdgeProbe.hold(body, back, first)
	elif angle * spin >= PI * 0.5:
		var ahead := corner + first * reach if inside else corner - first * CORNER_INSET
		landed = EdgeProbe.hold(body, ahead, second)
	else:
		state.anchor_t = angle
		var arc := _arc_edge(corner, first, angle, inside, edge["base"], tuning)
		state.velocity = (-arc["normal"] as Vector3).cross(Vector3.UP) * along
		return arc
	if landed.is_empty():
		# No debería pasar: _held_edge acaba de ver las dos caras. Se queda donde está.
		state.velocity = Vector3.ZERO
		return edge
	state.anchor_t = 0.0
	state.corner_inside = false
	state.velocity = (-landed["normal"] as Vector3).cross(Vector3.UP) * along
	return landed


## Rayo de las esquinas, contra lo mismo que las manos.
static func _corner_ray(body: ActorBody, from: Vector3, to: Vector3) -> Dictionary:
	var hit := body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			from, to, EdgeProbe.mask(body), [body.get_rid()]))
	if hit.is_empty():
		return {}
	var flat := Vector3(hit["normal"].x, 0.0, hit["normal"].z)
	if flat.length_squared() < 0.5:
		return {}
	hit["normal"] = flat.normalized()
	return hit


## Pose de colgado: los pies, a la distancia fija de la pared y a la altura
## fija bajo el filo. Depende solo del borde.
static func _hang_pose(edge: Dictionary, tuning: ActorTuning) -> Vector3:
	return edge["point"] + edge["normal"] * tuning.hang_distance + Vector3.DOWN * tuning.hang_height


## Saltar hacia arriba desde el colgado: la velocidad justa para que los pies,
## que cuelgan hang_height por debajo del filo, suban hasta hang_climb_clearance
## por encima. En Aire la gravedad se aplica antes de mover, y así el tick
## sigue la parábola de una velocidad inicial menor en g·dt/2: por eso se suma.
static func _climb_jump_speed(tuning: ActorTuning, dt: float) -> float:
	var rise := tuning.hang_height + tuning.hang_climb_clearance
	return sqrt(2.0 * tuning.gravity * rise) + tuning.gravity * dt * 0.5


## Saltar de la escalera mirándola: los pies suben ladder_jump_extra más que en
## un salto desde el piso.
static func _ladder_jump_speed(tuning: ActorTuning, dt: float) -> float:
	return floor_jump_speed(tuning, dt, tuning.ladder_jump_extra)


## La velocidad justa para que los pies suban `extra` metros más que en un
## salto desde el piso con jump_velocity. Con la misma cuenta que
## _climb_jump_speed: el salto del piso sigue la parábola de una velocidad
## menor en g·dt/2, y a esa se le suma la altura extra.
static func floor_jump_speed(tuning: ActorTuning, dt: float, extra: float) -> float:
	return raised_jump_speed(tuning.jump_velocity, tuning, dt, extra)


## Lo mismo, partiendo de otra velocidad de salto (el salto en el aire).
static func raised_jump_speed(jump_speed: float, tuning: ActorTuning, dt: float, extra: float) -> float:
	var base := jump_speed - tuning.gravity * dt * 0.5
	var speed := sqrt(base * base + 2.0 * tuning.gravity * extra)
	return speed + tuning.gravity * dt * 0.5


## Hanging, etapa 7: un barrido hasta la pose de colgado. Si algo la tapa,
## sale a Aire.
static func _move_hanging(body: ActorBody, state: ActorState, edge: Dictionary, tuning: ActorTuning) -> void:
	if edge.is_empty():
		return
	var motion := _hang_pose(edge, tuning) - body.global_position
	if motion.length_squared() > 1e-12 and body.move_and_collide(motion) != null:
		_leave_edge(state, tuning, Vector3.ZERO)


## Sale de un borde a Aire con una velocidad y un bloqueo corto de reagarre de
## bordes y cables. La velocidad de la base del borde se suma en la etapa de
## contactos.
static func _leave_edge(state: ActorState, tuning: ActorTuning, velocity: Vector3) -> void:
	state.mode = ActorState.Mode.AIR
	state.velocity = velocity
	state.anchor_id = 0
	state.anchor_t = 0.0
	state.corner_inside = false
	state.anchor_point = Vector3.ZERO
	state.regrab_id = ActorState.REGRAB_EDGES
	state.regrab_left = tuning.hang_regrab_time
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0


## Mantle desde Aire: si mantle_check() encuentra un borde bajo al que se
## puede subir, entra a Mantle desde donde está, sin snap. Devuelve el borde,
## o vacío.
static func _try_mantle(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> Dictionary:
	var check := mantle_check(body, state, direction, tuning, dt)
	if check["why"] != "":
		return {}
	var edge: Dictionary = check["edge"]
	# Encogido (el salto para arriba desde el colgado), primero se para con la
	# cabeza quieta, como en el aire: el camino se midió desde los pies de parado.
	if state.stance == ActorState.Stance.TUCKED:
		_change_stance(body, state, ActorState.Stance.STANDING)
	state.mode = ActorState.Mode.MANTLE
	state.anchor_id = edge["base"]
	state.anchor_point = edge["point"] - BaseRegistry.origin(edge["base"])
	# La normal del borde va en anchor_t: el cuerpo deja de mirar a la pared al
	# pasar arriba (ver _mantle).
	state.anchor_t = _yaw_of(edge["normal"])
	state.corner_inside = false
	state.velocity = Vector3.ZERO
	state.facing_yaw = _yaw_of(-edge["normal"])
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
	# Si arriba solo cabe agachado, se agacha ya, con los pies quietos.
	if check["stance"] != state.stance:
		_change_stance(body, state, check["stance"])
	return edge


## La decisión del mantle, sin cambiar nada (pedido del usuario, 2026-10-25).
## Solo después de saltar (jumped: desde el piso, en el aire, desde un borde,
## una escalera, un cable o un compañero): cayéndose sin saltar (bajando de
## espaldas, soltándose con Ctrl, por un empujón), como antes, se cuelga o cae
## (pedido del usuario: bajando de espaldas de un borde, mirándolo, el mantle lo
## volvía a subir). Y solo subiendo: cayendo nunca, apriete lo que apriete; se
## cuelga como siempre (pedido del usuario, después de probarlo: cayendo con
## los pies cerca del filo, lo subía con las manos abajo de todo, por ejemplo
## al no apretar W en el salto para arriba desde el colgado). En el aire, las manos buscan hacia `direction` (hacia donde
## mira la cámara, ver grab_direction) un filo entre mantle_min_height y mantle_max_height por
## encima de los pies: barren esa franja de arriba hacia abajo, delante del
## pecho. Subiendo, no, si el salto ya le lleva los pies arriba del filo: ahí
## sigue y cae arriba, como saltando a un bloque bajo. El filo se toma enfrente
## del centro del cuerpo, como en grab_check.
## El camino que se prueba: derecho para arriba hasta que los pies pasan el filo
## por MANTLE_LIFT, y derecho hacia adentro hasta que el centro queda
## mantle_land detrás del filo (con teclas, después va hacia donde apuntan: ver
## _mantle). Parado, si arriba cabe y el camino está libre; si no,
## agachado, con los pies quietos (pedido del usuario: si arriba solo cabés
## agachado, sube agachado). Donde termina tiene que haber piso debajo del
## centro del cuerpo (_floor_under): en un muro finito o una baranda no hay
## mantle, y se choca como siempre (pedido del usuario, 2026-10-25: primero
## pasaba por encima y caía del otro lado, y en la torre de servicio la baranda
## del pasillo del 86 lo tiraba al vacío). No se llama con Ctrl;
## agachado no sube (como para colgarse) y encogido sí, midiendo desde los pies
## de parado. Con los pies en el volumen de una escalera, no: se agarra la
## escalera.
## Devuelve {edge, stance, why}: why vacío si sube, o por qué no. Lo usan el
## motor y las pruebas.
static func mantle_check(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, _dt: float) -> Dictionary:
	var result := {"edge": {}, "stance": ActorState.Stance.STANDING, "why": "sin borde"}
	if tuning.mantle_max_height <= 0.0:
		result["why"] = "apagado"
		return result
	if not state.jumped:
		result["why"] = "no saltó"
		return result
	if state.velocity.y <= 0.0:
		result["why"] = "cayendo"
		return result
	if state.regrab_id == ActorState.REGRAB_EDGES or state.stance == ActorState.Stance.CROUCHED:
		result["why"] = "bloqueo o postura"
		return result
	if direction.length_squared() < 0.01:
		result["why"] = "sin dirección"
		return result
	var toward := Vector3(direction.x, 0.0, direction.z).normalized()
	var feet := _standing_feet(body, state)
	if Ladder.any_at(feet):
		result["why"] = "delante de una escalera"
		return result
	var hands := EdgeProbe.hands_at(body, feet, toward, tuning)
	var high := hands + Vector3.DOWN * (tuning.hang_height - tuning.mantle_max_height)
	var low := hands + Vector3.DOWN * (tuning.hang_height - tuning.mantle_min_height)
	var edge := EdgeProbe.find(body, high, low, toward)
	if edge.is_empty():
		return result
	var normal: Vector3 = edge["normal"]
	var right := (-normal).cross(Vector3.UP)
	var ahead := EdgeProbe.hold(body, edge["point"] + right * (feet - edge["point"]).dot(right), normal)
	if not ahead.is_empty():
		edge = ahead
	result["edge"] = edge
	var point: Vector3 = edge["point"]
	var rise := point.y - feet.y
	if toward.dot(-normal) < 0.5:
		result["why"] = "intención de costado"
	elif rise < tuning.mantle_min_height or rise > tuning.mantle_max_height:
		result["why"] = "fuera de la franja"
	elif feet.y + state.velocity.y * state.velocity.y / (2.0 * tuning.gravity) > point.y:
		result["why"] = "subiendo, el salto pasa arriba del filo"
	elif not body.stance_fits(ActorState.Stance.STANDING, feet):
		# Encogido, los pies de parado no caben.
		result["why"] = "no cabe parado"
	else:
		var up := Vector3.UP * (rise + MANTLE_LIFT)
		var inward := -normal * _mantle_left(feet, edge, tuning)
		if not _floor_under(body, feet + up + inward, tuning):
			result["why"] = "arriba no hay piso (un muro finito)"
			return result
		result["why"] = "arriba no cabe o el camino está tapado"
		for stance: int in [ActorState.Stance.STANDING, ActorState.Stance.CROUCHED]:
			if body.stance_fits(stance, feet + up + inward) and body.stance_moves(stance, feet, up) \
					and body.stance_moves(stance, feet + up, inward):
				result["stance"] = stance
				result["why"] = ""
				break
	return result


## Mantle, etapa 4: el borde del mantle, revalidado con la sonda en el punto
## guardado y con la normal guardada en anchor_t. Vacío si el borde ya no está
## o si desapareció la base que lo llevaba.
static func _mantle_edge(body: ActorBody, state: ActorState) -> Dictionary:
	if state.anchor_id != 0 and BaseRegistry.find(state.anchor_id) == null:
		return {}
	var normal := Vector3.FORWARD.rotated(Vector3.UP, state.anchor_t)
	return EdgeProbe.hold(body, BaseRegistry.origin(state.anchor_id) + state.anchor_point, normal)


## Mantle, etapa 6: primero sube derecho, a mantle_up_speed, hasta que los pies
## pasan el filo, mirando a la pared; después pasa arriba, arrancando desde
## quieto con ground_accel hasta mantle_forward_speed, hacia donde apuntan las
## teclas según la cámara (`direction`, ver _mantle_way) y mirando hacia
## allá (pedido del usuario, 2026-10-25: iba siempre derecho contra la pared, y
## recién después de medio metro se movía para donde quería). Sin teclas, derecho hacia adentro.
static func _mantle(body: ActorBody, state: ActorState, edge: Dictionary, direction: Vector3, tuning: ActorTuning, dt: float) -> void:
	if edge.is_empty():
		return
	var normal: Vector3 = edge["normal"]
	if body.global_position.y < _mantle_top(edge) - ActorState.POSITION_STEP:
		state.velocity = Vector3.UP * tuning.mantle_up_speed
		state.facing_yaw = _yaw_of(-normal)
		return
	var way := _mantle_way(normal, direction, tuning)
	var along := move_toward(Vector2(state.velocity.x, state.velocity.z).length(), tuning.mantle_forward_speed, tuning.ground_accel * dt)
	state.velocity = way * along
	state.facing_yaw = _yaw_of(way)


## Hacia dónde pasa arriba: hacia donde apuntan las teclas, hasta
## mantle_side_angle de costado de derecho hacia adentro (más de costado, se
## queda en ese ángulo: con A o D solas, en diagonal hacia ese lado). Sin
## teclas, o con teclas hacia afuera, derecho hacia adentro.
static func _mantle_way(normal: Vector3, direction: Vector3, tuning: ActorTuning) -> Vector3:
	var inward := -normal
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001 or flat.normalized().dot(inward) < -0.01:
		return inward
	var angle := inward.signed_angle_to(flat.normalized(), Vector3.UP)
	return inward.rotated(Vector3.UP, clampf(angle, -tuning.mantle_side_angle, tuning.mantle_side_angle))


## Mantle, etapa 7: un barrido hasta donde lleva la velocidad, sin pasar del
## filo al subir ni de mantle_land al entrar. Mientras sube se arrima a la
## pared, hasta casi tocarla, a mantle_forward_speed: así al pasar arriba le
## queda menos camino, y en diagonal se corre menos de costado (sin eso, en un
## bloque angosto se caía por el costado). Si hacia donde apuntan las teclas
## algo tapa el paso, prueba derecho hacia adentro, que se probó al empezar; si
## eso también está tapado, sale a Aire.
static func _move_mantling(body: ActorBody, state: ActorState, edge: Dictionary, tuning: ActorTuning, dt: float) -> void:
	if edge.is_empty():
		return
	var feet := body.global_position
	var top := _mantle_top(edge)
	var normal: Vector3 = edge["normal"]
	var left := maxf(_mantle_left(feet, edge, tuning), 0.0)
	var motion := Vector3.ZERO
	if feet.y < top - ActorState.POSITION_STEP:
		motion.y = minf(state.velocity.y * dt, top - feet.y)
		var gap := (feet - (edge["point"] as Vector3)).dot(normal) - body.capsule_radius() - MANTLE_WALL_GAP
		if gap > 0.0:
			var closer := -normal * minf(gap, tuning.mantle_forward_speed * dt)
			if not body.test_move(body.global_transform, motion + closer):
				motion += closer
	else:
		motion = state.velocity * dt
		var inward := motion.dot(-normal)
		if inward > left:
			motion *= left / inward
		if motion.length_squared() > 1e-12 and body.test_move(body.global_transform, motion):
			motion = -normal * minf(state.velocity.length() * dt, left)
	if motion.length_squared() > 1e-12 and body.move_and_collide(motion) != null:
		_leave_mantle(state, tuning, Vector3.ZERO, false)


## Hasta dónde suben los pies en el mantle: el filo, más MANTLE_LIFT.
static func _mantle_top(edge: Dictionary) -> float:
	return (edge["point"] as Vector3).y + MANTLE_LIFT


## Cuánto le falta al mantle hacia adentro, con los pies en `feet`: hasta que
## el centro queda mantle_land detrás del filo.
static func _mantle_left(feet: Vector3, edge: Dictionary, tuning: ActorTuning) -> float:
	return (feet - (edge["point"] as Vector3)).dot(edge["normal"]) + tuning.mantle_land


## Si el mantle llegó: los pies pasaron el filo y el centro está mantle_land
## detrás. Con teclas, antes: apenas el centro pasa MANTLE_STAND detrás del
## filo con piso debajo, y desde ahí camina hacia donde apuntan.
static func _mantle_done(body: ActorBody, feet: Vector3, edge: Dictionary, input: ActorInput, tuning: ActorTuning) -> bool:
	if feet.y < _mantle_top(edge) - ActorState.POSITION_STEP:
		return false
	var left := _mantle_left(feet, edge, tuning)
	if left <= ActorState.POSITION_STEP:
		return true
	return input.move != Vector2.ZERO and left <= tuning.mantle_land - MANTLE_STAND \
			and _floor_under(body, feet, tuning)


## Terminó el mantle: queda parado (o agachado, si arriba solo cabe así) arriba,
## como al salir por arriba de una escalera: con teclas sigue caminando a la
## velocidad que traía, y sin teclas, quieto. El cuerpo baja en el acto hasta el
## piso lo poco que subió para pasar (MANTLE_LIFT), y el dibujo lo acompaña
## suave. Si ahí ya no hay piso debajo del centro del cuerpo (mantle_check lo
## pidió al empezar, pero pudo desaparecer, como una base que se fue), sigue en
## el aire con la velocidad que traía.
static func _finish_mantle(body: ActorBody, state: ActorState, input: ActorInput, tuning: ActorTuning) -> void:
	var moving := state.velocity
	state.mode = ActorState.Mode.GROUND
	if input.move == Vector2.ZERO:
		state.velocity = Vector3.ZERO
	state.anchor_id = 0
	state.anchor_point = Vector3.ZERO
	state.anchor_t = 0.0
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
	var before := body.global_position
	body.settle_on_floor(tuning.floor_snap_length)
	body.snap_jump += body.global_position - before
	if not body.is_on_floor() or not _floor_under(body, body.global_position, tuning):
		state.mode = ActorState.Mode.AIR
		state.velocity = moving


## Si debajo de unos pies hay piso caminable, hasta floor_snap_length más
## abajo: un rayo desde el centro, como el del escalón. Con la parte redonda de
## abajo del cuerpo sobre la arista de un muro finito, no cuenta.
static func _floor_under(body: ActorBody, feet: Vector3, tuning: ActorTuning) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.05,
			feet + Vector3.DOWN * tuning.floor_snap_length, EdgeProbe.mask(body), [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and (hit["normal"] as Vector3).angle_to(Vector3.UP) <= body.floor_max_angle


## Sale del mantle a Aire con una velocidad. Si `block` (un empujón), no se
## puede agarrar de un borde ni de un cable por un rato, como al soltar un
## borde. Sin haber saltado, de ahí no vuelve a subir solo (ver mantle_check).
static func _leave_mantle(state: ActorState, tuning: ActorTuning, velocity: Vector3, block: bool) -> void:
	state.mode = ActorState.Mode.AIR
	state.velocity = velocity
	state.anchor_id = 0
	state.anchor_t = 0.0
	state.anchor_point = Vector3.ZERO
	if block:
		state.regrab_id = ActorState.REGRAB_EDGES
		state.regrab_left = tuning.hang_regrab_time
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0


## Enganchado desde Aire: si hook_check() encuentra un compañero del que
## colgarse, entra a Enganchado; en la etapa 7 de este mismo tick el cuerpo va
## a la pose. Es un snap lógico, como el agarre de un borde. Las manos quedan en
## su cintura. Devuelve el compañero, o null.
static func _try_hook(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> ActorBody:
	var check := hook_check(body, state, direction, tuning, dt)
	if check["why"] != "":
		return null
	var mate: ActorBody = check["anchor"]
	state.mode = ActorState.Mode.HOOKED
	state.anchor_id = mate.owner_peer_id
	state.anchor_t = tuning.hook_height
	state.velocity = Vector3.ZERO
	state.facing_yaw = check["yaw"]
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
	body.grab_jump += check["pose"] - _standing_feet(body, state)
	return mate


## La decisión de colgarse de un compañero, sin cambiar nada. El compañero
## tiene que estar agarrado de un borde, de una escalera o de un cable, sin
## otro colgado de él. Con varios, gana el de id más chico.
##
## El compañero es como un cilindro (pedido del usuario, 2026-10-18): mire
## donde mire la cámara, alcanza con que en este tick las manos pasen a no más
## de hook_reach de su eje, en horizontal, entre hook_min_height y
## hook_max_height sobre sus pies (ver _cylinder_side). Se cuelga del lado por
## el que llegó, con las manos en su cintura (hook_height); de uno en un borde
## o una escalera, solo si ese lado está a no más de hook_turn_limit de su
## espalda (nunca del lado de la pared o de la escalera). La pose cabe y el
## camino hasta ella está libre.
##
## Del compañero se usa lo que esta máquina tiene de él: en el host, su estado
## de este tick; en un cliente, el que se está mostrando, que es del pasado.
## Como el compañero está quieto, da lo mismo. En un cable puede estar
## moviéndose al colgarse uno de él: ahí, con internet mala, el host corrige.
##
## Devuelve {anchor, pose, yaw, why}: why vacío si se puede, o por qué no (el
## del último compañero mirado); yaw, hacia dónde va a mirar colgado, que es
## hacia él. Lo usan el motor y las pruebas. Como en grab_check, agachado no se
## cuelga, y encogido se mide desde los pies de parado. Hasta el 2026-10-18 se
## colgaba solo de su espalda, mirándolo, cuando las manos pasaban por la
## altura de su cintura; `_direction`, hacia dónde miraba, ya no se usa.
static func hook_check(body: ActorBody, state: ActorState, _direction: Vector3, tuning: ActorTuning, dt: float) -> Dictionary:
	var result := {"anchor": null, "pose": Vector3.ZERO, "yaw": 0.0, "why": "sin compañero"}
	# Recién soltado un cable tampoco: ver ActorState.REGRAB_CABLES.
	if state.regrab_id == ActorState.REGRAB_TEAMMATES or state.regrab_id == ActorState.REGRAB_CABLES \
			or state.stance == ActorState.Stance.CROUCHED:
		result["why"] = "bloqueo o postura"
		return result
	var from := _standing_feet(body, state)
	var fall := maxf(state.velocity.y - tuning.gravity * dt, -tuning.fall_limit())
	var motion := Vector3(state.velocity.x, fall, state.velocity.z) * dt
	for mate in body.teammates():
		if not _hook_holds(body, mate):
			continue
		var side := _cylinder_side(mate, from, motion, tuning)
		var yaw: float = side.get("yaw", mate.state.facing_yaw)
		var pose := hook_pose(mate, tuning, yaw, tuning.hook_height)
		result["anchor"] = mate
		result["pose"] = pose
		result["yaw"] = yaw
		if side.is_empty():
			result["why"] = "las manos no tocan su cuerpo"
		elif not _hook_side_allowed(mate, yaw, tuning):
			result["why"] = "del lado de la pared"
		elif not body.stance_fits(ActorState.Stance.STANDING, pose):
			result["why"] = "la pose no cabe"
		elif body.test_move(body.global_transform, pose - from):
			result["why"] = "camino tapado"
		else:
			result["why"] = ""
			return result
	return result


## Colgarse de un compañero: el primer punto del movimiento de este tick,
## barrido de a CABLE_SWEEP_STEP como en cable_check, en que las manos
## (hang_height sobre los pies de parado) tocan el cilindro de su cuerpo: a no
## más de hook_reach de su eje, en horizontal, y entre hook_min_height y
## hook_max_height sobre sus pies. Devuelve {yaw}: hacia él desde ese lado, ya
## cuantizado; si las manos pasan justo por su eje, desde su espalda. Vacío si
## no lo tocan.
static func _cylinder_side(mate: ActorBody, from: Vector3, motion: Vector3, tuning: ActorTuning) -> Dictionary:
	var axis := mate.global_position
	var steps := maxi(ceili(motion.length() / CABLE_SWEEP_STEP), 1)
	for i in steps + 1:
		var feet := from + motion * (float(i) / steps)
		var hands := feet.y + tuning.hang_height - axis.y
		var flat := Vector3(feet.x - axis.x, 0.0, feet.z - axis.z)
		if flat.length() <= tuning.hook_reach and hands >= tuning.hook_min_height \
				and hands <= tuning.hook_max_height:
			var out := flat.normalized() if flat.length() > 0.01 else _out_of(mate.state)
			return {"yaw": ActorState.quantize_yaw(_yaw_of(-out))}
	return {}


## Pose colgado de un compañero: las manos `height` por encima de sus pies, y
## el cuerpo hook_distance afuera de él, mirándolo (hacia `yaw`). Con `yaw`
## igual a hacia donde mira él, de su espalda.
static func hook_pose(mate: ActorBody, tuning: ActorTuning, yaw: float, height: float) -> Vector3:
	return mate.global_position + Vector3.BACK.rotated(Vector3.UP, yaw) * tuning.hook_distance \
			+ Vector3.UP * (height - tuning.hang_height)


## La pose de un actor colgado de `mate`, según su estado: hacia dónde mira y
## la altura de las manos (anchor_t).
static func hooked_pose(state: ActorState, mate: ActorBody, tuning: ActorTuning) -> Vector3:
	return hook_pose(mate, tuning, state.facing_yaw, state.anchor_t)


## Colgado de un compañero: a cuántos radianes de su espalda está, alrededor de
## él (0 en su espalda, PI adelante, positivo hacia su izquierda). Lo usan el
## panel y las pruebas.
static func hook_angle(state: ActorState, mate: ActorBody) -> float:
	return angle_difference(mate.state.facing_yaw, state.facing_yaw)


## Hacia afuera de la pared de un actor agarrado (de espaldas a donde mira).
static func _out_of(state: ActorState) -> Vector3:
	return Vector3.BACK.rotated(Vector3.UP, state.facing_yaw)


## Colgado de un compañero: hacia él, en horizontal. Es hacia donde mira.
static func _toward_mate(state: ActorState) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, state.facing_yaw)


## Si se puede estar de ese lado del compañero (mirándolo hacia `yaw`): de uno
## en un cable, de cualquier lado; de uno en un borde o una escalera, a no más
## de hook_turn_limit de su espalda, para cada lado.
static func _hook_side_allowed(mate: ActorBody, yaw: float, tuning: ActorTuning) -> bool:
	if mate.state.mode == ActorState.Mode.CABLE:
		return true
	return absf(angle_difference(mate.state.facing_yaw, yaw)) <= tuning.hook_turn_limit + HOOK_TURN_SLACK


## Colgado de un compañero, etapa 6: W y S suben y bajan las manos, mire donde
## mire la cámara, entre hook_min_height y hook_max_height, a
## hook_climb_speed; A y D giran alrededor de él, a hook_turn_speed sobre el
## círculo de hook_distance (pedido del usuario, 2026-10-18). De uno en un
## borde o una escalera, el giro frena a hook_turn_limit de su espalda. Si el
## camino hasta la pose nueva no está libre, prueba solo subir o bajar y
## después solo girar; si tampoco, no se mueve.
static func _hook_move(body: ActorBody, state: ActorState, mate: ActorBody, input: ActorInput, tuning: ActorTuning, dt: float) -> void:
	var height := clampf(state.anchor_t + clampf(input.move.y, -1.0, 1.0) * tuning.hook_climb_speed * dt,
			tuning.hook_min_height, tuning.hook_max_height)
	var turned := state.facing_yaw + clampf(input.move.x, -1.0, 1.0) * tuning.hook_turn_speed / tuning.hook_distance * dt
	if mate.state.mode != ActorState.Mode.CABLE:
		var limit := tuning.hook_turn_limit
		turned = mate.state.facing_yaw + clampf(angle_difference(mate.state.facing_yaw, turned), -limit, limit)
	var yaw := ActorState.quantize_yaw(turned)
	for option: Array in [[yaw, height], [state.facing_yaw, height], [yaw, state.anchor_t]]:
		if option[0] == state.facing_yaw and option[1] == state.anchor_t:
			continue
		var to := hook_pose(mate, tuning, option[0], option[1])
		if not body.test_move(body.global_transform, to - body.global_position):
			state.facing_yaw = option[0]
			state.anchor_t = option[1]
			return


## Los modos de los que se puede colgar un compañero.
static func holds_mates(mode: int) -> bool:
	return mode == ActorState.Mode.HANGING or mode == ActorState.Mode.LADDER or mode == ActorState.Mode.CABLE


## Si `mate` sostiene a este actor: existe, está agarrado de un borde, de una
## escalera o de un cable, y no cuelga otro de él.
static func _hook_holds(body: ActorBody, mate: ActorBody) -> bool:
	if mate == null:
		return false
	if not holds_mates(mate.state.mode):
		return false
	return mate.state.hooked_by == 0 or mate.state.hooked_by == body.owner_peer_id


## Enganchado, etapa 7: un barrido hasta la pose que da el compañero. Si algo
## la tapa, sale a Aire. Las manos quedan sobre su cuerpo, para dibujarlas.
static func _move_hooked(body: ActorBody, state: ActorState, mate: ActorBody, tuning: ActorTuning) -> void:
	if mate == null:
		return
	var pose := hooked_pose(state, mate, tuning)
	var motion := pose - body.global_position
	if motion.length_squared() > 1e-12 and body.move_and_collide(motion) != null:
		_leave_hook(state, tuning, Vector3.ZERO, true)
		return
	var inward := _toward_mate(state)
	state.anchor_point = pose + Vector3.UP * tuning.hang_height + inward * (tuning.hook_distance - body.capsule_radius())


## Lo del host al empezar cada tick, antes de mover a nadie: quién cuelga de
## quién. Cada actor agarrado anota en hooked_by al compañero que cuelga de él;
## eso lo deja quieto, así que es un evento del host para ese actor y sube su
## época. Si dos se colgaron del mismo en el mismo tick, se queda el de id más
## chico y el otro se suelta (otro evento). Devuelve [cambios anotados,
## soltados].
static func assign_hooks(actors: Array[ActorBody], tuning: ActorTuning) -> Array:
	var changes := 0
	var released := 0
	var hooked_on := {}  # peer del que sostiene -> peer del que cuelga de él
	var by_id := actors.duplicate()
	by_id.sort_custom(func(a: ActorBody, b: ActorBody) -> bool: return a.owner_peer_id < b.owner_peer_id)
	for actor: ActorBody in by_id:
		if actor.state.mode != ActorState.Mode.HOOKED:
			continue
		var mate := actor.teammate(actor.state.anchor_id)
		if not _hook_holds(actor, mate):
			continue  # su propio paso lo suelta en este tick
		if hooked_on.has(mate.owner_peer_id):
			_leave_hook(actor.state, tuning, Vector3.ZERO, true)
			actor.state.epoch += 1
			released += 1
			continue
		hooked_on[mate.owner_peer_id] = actor.owner_peer_id
	for actor: ActorBody in by_id:
		var by: int = hooked_on.get(actor.owner_peer_id, 0)
		if actor.state.hooked_by != by:
			actor.state.hooked_by = by
			actor.state.epoch += 1
			changes += 1
	return [changes, released]


## Lo del host al terminar cada tick: si `actor`, que al empezarlo colgaba del
## compañero `mate_id`, ya no cuelga porque el compañero dejó de sostenerlo (se
## soltó, lo empujaron o se fue). Su PC ve al compañero en el pasado y sigue
## prediciendo que cuelga hasta que le llega el snapshot: para él es un evento
## del host, y el host le sube la época (ver net_lab.gd, _mark_hooks_released).
static func hook_released_by_mate(actor: ActorBody, mate_id: int) -> bool:
	return actor.state.mode != ActorState.Mode.HOOKED and not _hook_holds(actor, actor.teammate(mate_id))


## Sale de colgar de un compañero a Aire con una velocidad. Con `block`
## (soltarse, saltar, un empujón), no se puede volver a colgar de un compañero
## por un rato: las manos todavía están a la altura de su cintura.
static func _leave_hook(state: ActorState, tuning: ActorTuning, velocity: Vector3, block: bool) -> void:
	state.mode = ActorState.Mode.AIR
	state.velocity = velocity
	state.anchor_id = 0
	state.anchor_t = 0.0
	state.anchor_point = Vector3.ZERO
	if block:
		state.regrab_id = ActorState.REGRAB_TEAMMATES
		state.regrab_left = tuning.hang_regrab_time
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0


## Cable desde Aire: si cable_check() encuentra un cable del que colgarse, entra
## al modo Cable; en la etapa 7 de este mismo tick el cuerpo va a la pose. Es un
## snap lógico, como el agarre de un borde. Se queda con la velocidad que traía
## a lo largo del cable: cayendo derecho sobre uno inclinado, sale hacia donde
## baja; sobre uno plano, no se mueve (pedido del usuario, 2026-10-19; hasta
## entonces arrancaba quieto). Lo que pase de la velocidad del cable se va
## perdiendo en _cable. Devuelve el cable, o null.
static func _try_grab_cable(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> Cable:
	var check := cable_check(body, state, direction, tuning, dt)
	if check["why"] != "":
		return null
	var cable: Cable = check["cable"]
	var t: float = check["t"]
	body.grab_jump += check["pose"] - _standing_feet(body, state)
	state.mode = ActorState.Mode.CABLE
	state.anchor_id = cable.cable_id
	state.anchor_t = t
	state.anchor_point = cable.point_at(t)
	var tangent := cable.tangent_at(t)
	state.velocity = tangent * state.velocity.dot(tangent)
	state.facing_yaw = _yaw_of(check["facing"])
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
	return cable


## La decisión de colgarse de un cable, sin cambiar nada. Sin tecla, como un
## borde, pero más fácil: alcanza con que en este tick el cable toque la parte
## de arriba del cuerpo de parado (cable_grab_body: con 0,5, de la mitad para
## arriba) o las manos, que llegan hasta hang_height por encima de los pies, a
## no más de cable_reach del eje del cuerpo, mire donde mire la cámara. Se barre el movimiento del tick de a CABLE_SWEEP_STEP, así a mucha
## velocidad no lo atraviesa sin verlo. Las manos van al punto del cable que
## tocó, y el cuerpo cuelga debajo, de frente al cable, del lado hacia donde
## mira la cámara. La pose cabe y el camino hasta ella está libre. Con varios,
## gana el de id más chico.
##
## Devuelve {cable, t, pose, facing, why}: why vacío si se puede, o por qué no
## (el del último cable mirado). Lo usan el motor y las pruebas. Como en
## grab_check, agachado no se agarra, y encogido se mide desde los pies de parado.
static func cable_check(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> Dictionary:
	var result := {"cable": null, "t": 0.0, "pose": Vector3.ZERO, "facing": Vector3.FORWARD, "why": "sin cable"}
	# Recién soltado un borde o un compañero tampoco: ver ActorState.REGRAB_EDGES
	# y REGRAB_TEAMMATES.
	if state.regrab_id == ActorState.REGRAB_CABLES or state.regrab_id == ActorState.REGRAB_EDGES \
			or state.regrab_id == ActorState.REGRAB_TEAMMATES or state.stance == ActorState.Stance.CROUCHED:
		result["why"] = "bloqueo o postura"
		return result
	var toward := Vector3(direction.x, 0.0, direction.z)
	if toward.length_squared() < 0.0001:
		toward = Vector3.FORWARD.rotated(Vector3.UP, state.facing_yaw)
	toward = toward.normalized()
	var from := _standing_feet(body, state)
	var fall := maxf(state.velocity.y - tuning.gravity * dt, -tuning.fall_limit())
	var motion := Vector3(state.velocity.x, fall, state.velocity.z) * dt
	var low := body.stance_height(ActorState.Stance.STANDING) * (1.0 - tuning.cable_grab_body)
	var high := tuning.hang_height
	var steps := maxi(ceili(motion.length() / CABLE_SWEEP_STEP), 1)
	for cable: Cable in Cable.all():
		if not cable.usable():
			continue
		result["cable"] = cable
		var touched := false
		var t := 0.0
		var point := Vector3.ZERO
		for i in steps + 1:
			var feet := from + motion * (float(i) / steps)
			# El punto del cable más cercano a la franja del cuerpo que agarra,
			# hasta las manos: primero a su centro, después a la altura de ese punto.
			t = cable.closest(feet + Vector3.UP * (low + high) * 0.5)
			point = cable.point_at(t)
			t = cable.closest(feet + Vector3.UP * clampf(point.y - feet.y, low, high))
			point = cable.point_at(t)
			var flat := Vector2(point.x - feet.x, point.z - feet.z).length()
			if flat <= tuning.cable_reach and point.y >= feet.y + low - 0.01 and point.y <= feet.y + high + 0.01:
				touched = true
				break
		if not touched:
			result["why"] = "no toca el cable"
			continue
		var tangent := cable.tangent_at(t)
		var across := Vector3.UP.cross(tangent)
		across.y = 0.0
		var pose := point + Vector3.DOWN * tuning.hang_height
		result["t"] = t
		result["pose"] = pose
		if across.length_squared() < 0.0001:
			result["why"] = "cable vertical"
		elif not body.stance_fits(ActorState.Stance.STANDING, pose):
			result["why"] = "la pose no cabe"
		elif body.test_move(body.global_transform, pose - from):
			result["why"] = "camino tapado"
		else:
			across = across.normalized()
			result["facing"] = across if across.dot(toward) >= 0.0 else -across
			result["why"] = ""
			return result
	return result


## Pose colgado de un cable: los pies, hang_height debajo del punto del cable.
static func _cable_pose(cable: Cable, t: float, tuning: ActorTuning) -> Vector3:
	return cable.point_at(t) + Vector3.DOWN * tuning.hang_height


## Cable, etapa 6: la velocidad va sobre el cable. Sin teclas se queda quieto,
## esté como esté inclinado. Las teclas se toman según la cámara, como
## caminando: si apuntan a menos de cable_move_angle del cable, lo mueven hacia
## ese lado (mirando a lo largo, W y S; mirándolo de costado, A y D); más de
## costado, nada. Va a cable_speed, salvo en un cable más inclinado que
## cable_slide_angle: hacia arriba sube a cable_climb_speed, y hacia abajo se
## desliza, acelerando con la gravedad sobre el cable hasta cable_slide_speed
## por el seno de la inclinación. Soltando las teclas o apretando las de para
## arriba (y si el cable se aplana) frena a cable_brake. En las puntas se frena
## en seco. Con un compañero colgado, se queda quieto.
##
## Lo que traiga por encima de la velocidad del cable hacia ese lado (del
## agarre, que conserva la caída: ver _try_grab_cable) se va perdiendo a
## cable_carry_brake, salvo que apriete para el otro lado, que frena como
## siempre (pedido del usuario, 2026-10-19).
##
## Con el súper salto y velocidad, las tres velocidades (cable_speed,
## cable_climb_speed y cable_slide_speed) vienen por boost_speed_scale (pedido
## del usuario, 2026-10-22; desde el 2026-10-24, como todas, por with_boost).
static func _cable(state: ActorState, cable: Cable, input: ActorInput, tuning: ActorTuning, dt: float) -> void:
	if cable == null:
		return
	var cable_speed := tuning.cable_speed
	var climb_speed := tuning.cable_climb_speed
	var slide_speed := tuning.cable_slide_speed
	var tangent := cable.tangent_at(state.anchor_t)
	# Hacia dónde piden ir las teclas, según la cámara, y cuánto de eso va sobre
	# el cable: positivo hacia la punta `end`.
	var look := Vector3.FORWARD.rotated(Vector3.UP, input.look_yaw)
	var asked := look.cross(Vector3.UP) * input.move.x + look * input.move.y
	var flat := Vector3(tangent.x, 0.0, tangent.z)
	var press := 0.0
	if asked.length_squared() > 0.0001 and flat.length_squared() > 0.0001:
		var lined := asked.normalized().dot(flat.normalized())
		if absf(lined) >= cos(tuning.cable_move_angle):
			press = signf(lined) * minf(asked.length(), 1.0)
	var along := state.velocity.dot(tangent)
	var slope := asin(clampf(tangent.y, -1.0, 1.0))
	var steep := absf(slope) >= tuning.cable_slide_angle
	var downhill := -signf(slope)
	# La velocidad del cable hacia donde va ahora.
	var cable_top := cable_speed
	if steep:
		cable_top = slide_speed * absf(sin(slope)) if along * downhill > 0.0 else climb_speed
	var wish := press * cable_speed
	var rate := tuning.climb_accel
	if absf(along) > cable_top + 0.001 and press * along >= 0.0:
		# Trae más que la velocidad del cable: se le va pasando.
		wish = signf(along) * cable_top
		rate = tuning.cable_carry_brake
	elif steep and press * downhill > 0.0:
		wish = downhill * slide_speed * absf(sin(slope))
		rate = tuning.gravity * absf(sin(slope)) if along * downhill < absf(wish) else tuning.cable_brake
	else:
		if steep and press * downhill < 0.0:
			wish = press * climb_speed
		if absf(along) > cable_speed + 0.001:
			# Venía deslizándose: soltó las teclas, pidió para arriba o el cable se aplanó.
			rate = tuning.cable_brake
	along = move_toward(along, wish, rate * dt)
	if state.hooked_by != 0:
		along = 0.0
	var t := state.anchor_t + along * dt
	var top := cable.length()
	if t <= 0.0 or t >= top:
		along = 0.0
	state.anchor_t = clampf(t, 0.0, top)
	state.velocity = cable.tangent_at(state.anchor_t) * along


## Cable, etapa 7: un barrido hasta la pose del punto del cable. Si algo lo
## frena, vuelve a donde estaba y se queda quieto ahí. Las manos quedan sobre
## el cable, para dibujarlas.
static func _move_on_cable(body: ActorBody, state: ActorState, cable: Cable, tuning: ActorTuning) -> void:
	if cable == null:
		return
	var start := body.global_position
	var motion := _cable_pose(cable, state.anchor_t, tuning) - start
	if motion.length_squared() > 1e-12 and body.move_and_collide(motion) != null:
		body.global_position = start
		state.anchor_t = cable.closest(start + Vector3.UP * tuning.hang_height)
		state.velocity = Vector3.ZERO
	state.anchor_point = cable.point_at(state.anchor_t)


## Sale de un cable a Aire con una velocidad y un bloqueo corto de reagarre de
## cables.
static func _leave_cable(state: ActorState, tuning: ActorTuning, velocity: Vector3) -> void:
	state.mode = ActorState.Mode.AIR
	state.velocity = velocity
	state.anchor_id = 0
	state.anchor_t = 0.0
	state.anchor_point = Vector3.ZERO
	state.regrab_id = ActorState.REGRAB_CABLES
	state.regrab_left = tuning.hang_regrab_time
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0


## Velocidad de un actor en el mundo: la propia más la de su base.
static func _world_velocity(state: ActorState) -> Vector3:
	return state.velocity + BaseRegistry.velocity(state.base_id)


## Impulso que fija el eje vertical. El snap no lo vuelve a pegar al piso
## porque la velocidad sube: así lo documenta floor_snap_length. Con el súper
## salto y velocidad, los pies llegan boost_jump_extra más alto. La velocidad
## horizontal sale limitada (jump_max_speed, con el súper por
## boost_speed_scale): de eso depende cuánto se avanza. Es la propia, relativa
## a la base si está sobre una.
static func _jump(state: ActorState, tuning: ActorTuning, dt: float) -> void:
	var most := tuning.jump_max_speed
	var horizontal := Vector2(state.velocity.x, state.velocity.z).limit_length(most)
	state.velocity.x = horizontal.x
	state.velocity.z = horizontal.y
	state.velocity.y = floor_jump_speed(tuning, dt, tuning.boost_jump_extra) if state.boosted \
			else tuning.jump_velocity
	state.mode = ActorState.Mode.AIR
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
	state.jumped = true


## Salto en el aire: cayendo sin haber saltado desde que dejó el piso o algo
## de donde estaba agarrado (se cayó, se soltó, lo empujaron), Espacio salta
## una vez, tan alto como desde el piso (air_jump_velocity; con el súper,
## boost_jump_extra más) y hacia donde mira la cámara: con la velocidad
## horizontal que traía, pero no menos que air_jump_speed ni más que el tope
## del salto. El cuerpo se da vuelta hacia allá.
static func _air_jump(state: ActorState, look_yaw: float, tuning: ActorTuning, dt: float) -> void:
	var most := tuning.jump_max_speed
	var least := tuning.air_jump_speed
	var look := Vector3.FORWARD.rotated(Vector3.UP, look_yaw)
	state.velocity = look * minf(maxf(_horizontal_speed(state), least), most)
	state.velocity.y = raised_jump_speed(tuning.air_jump_velocity, tuning, dt, tuning.boost_jump_extra) \
			if state.boosted else tuning.air_jump_velocity
	state.facing_yaw = _yaw_of(look)
	state.jump_buffer_left = 0.0
	state.jumped = true
