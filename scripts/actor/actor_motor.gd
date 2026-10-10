class_name ActorMotor
extends RefCounted

## Paso por tick de un actor: recibe estado, input y dt, mueve el cuerpo y deja
## el estado del tick siguiente. No guarda nada propio; por eso cualquier tick
## se puede repetir después de restaurar el estado.
##
## Sigue el orden fijo de etapas de la arquitectura. Por ahora existen los modos
## Suelo, Aire, Deslizamiento, Ladder, Hanging y Enganchado (HOOKED: colgado de
## un compañero), y la postura (parado o agachado). La etapa de sondas (4)
## revalida el borde agarrado y busca al compañero del que cuelga. Las demás
## sondas corren donde se usan: la de suelo en la de contactos, la de espacio
## libre en la de postura, la de escalera, la de agarrar un borde y la de
## colgarse de un compañero en la de transición, y la de escalón en la de
## movimiento, porque necesita saber si el movimiento chocó.
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


static func step(body: ActorBody, state: ActorState, input: ActorInput, tuning: ActorTuning, dt: float) -> void:
	body.snap_jump = Vector3.ZERO
	body.grab_jump = Vector3.ZERO

	# 1. Tiempo: dt es el del mundo, 1/60 por la escala del mundo. Con cámara
	# lenta personal, el del actor es más chico todavía, y todo lo que dura se
	# descuenta en tiempo del actor. La cámara lenta personal vence en tiempo
	# del mundo, para no alargarse a sí misma (regla 5).
	var slowed := state.slow_left > 0.0
	state.slow_left = maxf(state.slow_left - dt, 0.0)
	if slowed:
		dt *= tuning.slow_scale
	state.coyote_left = maxf(state.coyote_left - dt, 0.0)
	state.jump_buffer_left = maxf(state.jump_buffer_left - dt, 0.0)
	state.regrab_left = maxf(state.regrab_left - dt, 0.0)
	if state.regrab_left == 0.0:
		state.regrab_id = 0

	# 2. Base: la base se movió desde el tick anterior y lleva al actor.
	_ride_base(body, state)

	# 3. Eventos. Una pulsación nueva se detecta porque el contador cambió,
	# aunque se haya perdido el tick exacto en que ocurrió.
	if input.jump_presses != state.jump_presses_seen:
		state.jump_presses_seen = input.jump_presses
		state.jump_buffer_left = tuning.jump_buffer_time

	# 4. Sondas: colgado, la de borde revalida cada tick el borde agarrado;
	# colgado de un compañero, se lo busca por su id.
	var edge := _held_edge(body, state) if state.mode == ActorState.Mode.HANGING else {}
	var mate: ActorBody = body.teammate(state.anchor_id) if state.mode == ActorState.Mode.HOOKED else null

	# 5. Transición: como máximo una por tick, decidida por la situación actual.
	# Cada modo revisa su lista de salidas en orden de prioridad.
	var wants_jump := state.jump_buffer_left > 0.0
	var crouch_held := input.is_held(ActorInput.BUTTON_CROUCH)
	var direction := _wish_direction(input)
	match state.mode:
		ActorState.Mode.GROUND:
			if wants_jump:
				_jump(state, tuning)
			elif not state.on_floor:
				state.mode = ActorState.Mode.AIR
				state.coyote_left = tuning.coyote_time
			elif _try_grab_ladder(body, state, direction):
				pass
			elif crouch_held and state.stance == ActorState.Stance.STANDING \
					and _horizontal_speed(state) >= tuning.slide_entry_speed:
				state.mode = ActorState.Mode.SLIDE
		ActorState.Mode.AIR:
			if state.on_floor and state.velocity.y <= 0.0:
				state.mode = ActorState.Mode.GROUND
			elif wants_jump and state.coyote_left > 0.0:
				_jump(state, tuning)
			else:
				if not crouch_held:
					edge = _try_grab_edge(body, state, grab_direction(state, direction), tuning, dt)
					if edge.is_empty():
						mate = _try_hook(body, state, grab_direction(state, direction), tuning, dt)
				if edge.is_empty() and mate == null:
					_try_grab_ladder(body, state, direction)
		ActorState.Mode.SLIDE:
			if wants_jump:
				_jump(state, tuning)
			elif not state.on_floor:
				state.mode = ActorState.Mode.AIR
				state.coyote_left = tuning.coyote_time
			elif _horizontal_speed(state) < tuning.slide_min_speed:
				state.mode = ActorState.Mode.GROUND
		ActorState.Mode.LADDER:
			var ladder := Ladder.find(state.anchor_id)
			var toward := direction.dot(-ladder.outward()) if ladder != null else 0.0
			if ladder == null:
				# Invariante roto: la escalera ya no existe. Sale al respaldo.
				_leave_anchor(state, tuning, Vector3.ZERO, false)
			elif state.hooked_by != 0:
				# Un compañero cuelga de él: se queda quieto. Saltar no hace nada.
				state.jump_buffer_left = 0.0
			elif wants_jump:
				_leave_anchor(state, tuning,
						ladder.outward() * tuning.ladder_jump_out + ladder.up() * tuning.ladder_jump_up, true)
			elif state.anchor_t <= 0.0 and toward < -0.5:
				_leave_anchor(state, tuning, Vector3.ZERO, false)
			elif state.anchor_t >= ladder.height and toward > 0.5:
				_climb_out_top(body, state, ladder, tuning)
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
				# Mirando a la pared salta derecho para arriba, y con el control
				# aéreo pasa arriba del borde; mirando a otro lado, salta hacia allá
				# y se da vuelta hacia donde salta, así las manos buscan para ese
				# lado y no la pared que deja.
				var look := Vector3.FORWARD.rotated(Vector3.UP, input.look_yaw)
				if look.dot(-edge["normal"]) >= cos(tuning.climb_look_angle):
					_leave_edge(state, tuning, Vector3.UP * _climb_jump_speed(tuning, dt))
				else:
					_leave_edge(state, tuning, look * tuning.hang_jump_out + Vector3.UP * tuning.hang_jump_up)
					state.facing_yaw = _yaw_of(look)
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
				if look.dot(-_out_of(mate.state)) >= cos(tuning.climb_look_angle):
					_leave_hook(state, tuning, Vector3.UP * _climb_jump_speed(tuning, dt), true)
				else:
					_leave_hook(state, tuning, look * tuning.hang_jump_out + Vector3.UP * tuning.hang_jump_up, true)
					state.facing_yaw = _yaw_of(look)

	# 6. Modo: el modo activo decide la velocidad.
	match state.mode:
		ActorState.Mode.GROUND:
			_ground(state, direction * _ground_speed(state, input, tuning), tuning, dt)
		ActorState.Mode.AIR:
			_air(state, direction, tuning, dt)
		ActorState.Mode.SLIDE:
			_slide(state, direction, tuning, dt)
		ActorState.Mode.LADDER:
			_ladder(state, direction, tuning, dt)
		ActorState.Mode.HANGING:
			edge = _hang(body, state, edge, input, tuning, dt)
		ActorState.Mode.HOOKED:
			# Cuelga quieto: la pose la da el compañero.
			state.velocity = Vector3.ZERO
			state.facing_yaw = mate.state.facing_yaw
	if state.mode == ActorState.Mode.SLIDE:
		if _horizontal_speed(state) > 0.01:
			state.facing_yaw = _yaw_of(state.velocity)
	elif not _is_anchored(state) and direction.length_squared() > 0.0001:
		state.facing_yaw = _yaw_of(direction)

	# 7. Postura y movimiento. Deslizamiento siempre pide agachado; en los modos
	# anclados se va parado; si no, lo pide el input. Los modos libres mueven
	# con move_and_slide(), sin snap en el aire; los anclados (Ladder, Hanging,
	# Enganchado), con un barrido. En Suelo, si el movimiento chocó, la sonda de
	# escalón prueba subirlo.
	var wanted := ActorState.Stance.STANDING
	if state.mode == ActorState.Mode.SLIDE or (crouch_held and not _is_anchored(state)):
		wanted = ActorState.Stance.CROUCHED
	_resolve_stance(body, state, wanted)
	if state.mode == ActorState.Mode.LADDER:
		_move_on_ladder(body, state)
	elif state.mode == ActorState.Mode.HANGING:
		_move_hanging(body, state, edge, tuning)
	elif state.mode == ActorState.Mode.HOOKED:
		_move_hooked(body, state, mate, tuning)
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
	# respecto de ella. Colgado de un compañero, la posición va en el mundo.
	state.on_floor = body.is_on_floor() and not _is_anchored(state)
	state.floor_normal = body.get_floor_normal() if state.on_floor else Vector3.UP
	if state.mode == ActorState.Mode.HANGING:
		state.base_id = state.anchor_id
	else:
		var base_now := _probe_base(body) if state.on_floor else 0
		if base_now != state.base_id:
			state.velocity += BaseRegistry.velocity(state.base_id) - BaseRegistry.velocity(base_now)
			state.base_id = base_now
	# Solo se puede colgar alguien de un actor agarrado de un borde o de una
	# escalera: si dejó de estarlo, ya no cuelga nadie de él. Lo calculan igual
	# el host y el cliente, así soltarse no necesita un evento del host.
	if state.mode != ActorState.Mode.HANGING and state.mode != ActorState.Mode.LADDER:
		state.hooked_by = 0
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
static func _wish_direction(input: ActorInput) -> Vector3:
	var local := Vector3(input.move.x, 0.0, -input.move.y)
	return local.rotated(Vector3.UP, input.look_yaw)


## En Suelo: agachado va despacio; correr pide postura parada.
static func _ground_speed(state: ActorState, input: ActorInput, tuning: ActorTuning) -> float:
	if state.stance == ActorState.Stance.CROUCHED:
		return tuning.crouch_speed
	if input.is_held(ActorInput.BUTTON_RUN):
		return tuning.sprint_speed
	return tuning.walk_speed


static func _horizontal_speed(state: ActorState) -> float:
	return Vector2(state.velocity.x, state.velocity.z).length()


## Modos anclados: la pose sale del ancla y se mueven con un barrido.
static func _is_anchored(state: ActorState) -> bool:
	return state.mode == ActorState.Mode.LADDER or state.mode == ActorState.Mode.HANGING \
			or state.mode == ActorState.Mode.HOOKED


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
## venía más rápido que caminando (de una carrera o un deslizamiento).
static func _air(state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> void:
	var horizontal := Vector3(state.velocity.x, 0.0, state.velocity.z)
	if direction.length_squared() > 0.0:
		var wish := direction * maxf(tuning.walk_speed, horizontal.length())
		horizontal = horizontal.move_toward(wish, tuning.air_accel * dt)
	var vertical := maxf(state.velocity.y - tuning.gravity * dt, -tuning.max_fall_speed)
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
## aire, con la cabeza fija: agacharse sube los pies y pararse los baja.
static func _resolve_stance(body: ActorBody, state: ActorState, wanted: int) -> void:
	state.stance_wanted = wanted
	if wanted == state.stance:
		return
	var growth := body.stance_height(wanted) - body.stance_height(state.stance)
	var feet := body.global_position
	if state.mode == ActorState.Mode.AIR:
		feet.y -= growth
	if growth > 0.0 and not body.stance_fits(wanted, feet):
		return
	state.stance = wanted
	body.global_position = feet
	body.use_stance(wanted)


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
			Vector3(spot.x, start.origin.y, spot.z), body.collision_mask, [body.get_rid()])
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
## nada) y el resto se descarta. Con un compañero colgado, el agarre es menor.
static func apply_impulse(state: ActorState, impulse: Vector3, force: int, tuning: ActorTuning) -> void:
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
	state.velocity += impulse
	state.mode = ActorState.Mode.AIR
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0


## Cámara lenta personal, como evento: la pone quien maneja el actor al
## empezar el tick, igual que un empujón, y sube la época. Dura
## personal_slow_time en tiempo del mundo; si ya estaba lento, empieza de nuevo.
static func apply_slow(state: ActorState, tuning: ActorTuning) -> void:
	state.slow_left = tuning.personal_slow_time


## Para validar una afirmación en un modo anclado: el ancla existe, el
## parámetro está en rango y el cuerpo está en la pose que le corresponde.
static func anchored_pose_valid(body: ActorBody, state: ActorState, tuning: ActorTuning) -> bool:
	if state.mode == ActorState.Mode.HOOKED:
		# El compañero existe, sigue agarrado y no cuelga otro de él; la pose,
		# cerca de la que da el compañero acá (el cliente lo vio en el pasado).
		var mate := body.teammate(state.anchor_id)
		if not _hook_holds(body, mate):
			return false
		return BaseRegistry.world_position(state).distance_to(hook_pose(mate, tuning)) <= HOOK_TOLERANCE
	if state.mode == ActorState.Mode.HANGING:
		var edge := _held_edge(body, state)
		if edge.is_empty() or state.anchor_t != 0.0:
			return false
		return BaseRegistry.world_position(state).distance_to(_hang_pose(edge, tuning)) <= 0.1
	if state.mode != ActorState.Mode.LADDER:
		return true
	var ladder := Ladder.find(state.anchor_id)
	if ladder == null or state.anchor_t < 0.0 or state.anchor_t > ladder.height:
		return false
	return BaseRegistry.world_position(state).distance_to(ladder.pose_at(state.anchor_t)) <= 0.1


## Ladder desde Suelo o Aire: dentro del volumen de una escalera y con
## intención de ir hacia ella. Con varias, gana la de id más chico, así todas
## las máquinas eligen la misma. La que se acaba de soltar está bloqueada un rato.
static func _try_grab_ladder(body: ActorBody, state: ActorState, direction: Vector3) -> bool:
	if direction.length_squared() < 0.01:
		return false
	var ladders := Ladder.all()
	ladders.sort_custom(func(a: Ladder, b: Ladder) -> bool: return a.ladder_id < b.ladder_id)
	for ladder: Ladder in ladders:
		if ladder.ladder_id == state.regrab_id:
			continue
		var t := ladder.height_for(body.global_position)
		if t < 0.0 or direction.dot(-ladder.outward()) < 0.5:
			continue
		state.mode = ActorState.Mode.LADDER
		state.anchor_id = ladder.ladder_id
		state.anchor_t = t
		state.velocity = Vector3.ZERO
		state.jump_buffer_left = 0.0
		state.coyote_left = 0.0
		return true
	return false


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


## Ladder: la velocidad va sobre el eje. Empujar hacia la escalera sube y
## alejarse baja; de costado no hace nada. Lo que llegó de afuera (un empujón
## menor al agarre) queda proyectado sobre el eje y se va frenando. Con un
## compañero colgado, se queda quieto.
static func _ladder(state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> void:
	var ladder := Ladder.find(state.anchor_id)
	if ladder == null:
		return
	var along := state.velocity.dot(ladder.up())
	var wish := clampf(direction.dot(-ladder.outward()), -1.0, 1.0) * tuning.climb_speed
	along = move_toward(along, wish, tuning.climb_accel * dt)
	if state.hooked_by != 0:
		along = 0.0
	var t := state.anchor_t + along * dt
	if t <= 0.0 or t >= ladder.height:
		along = 0.0
	state.anchor_t = clampf(t, 0.0, ladder.height)
	state.velocity = ladder.up() * along
	state.facing_yaw = _yaw_of(-ladder.outward())


## Etapa 7 en Ladder: un barrido hasta la pose de la altura pedida. Si algo lo
## frena, la altura queda donde llegó.
static func _move_on_ladder(body: ActorBody, state: ActorState) -> void:
	var ladder := Ladder.find(state.anchor_id)
	if ladder == null:
		return
	var motion := ladder.pose_at(state.anchor_t) - body.global_position
	if motion.length_squared() < 1e-12:
		return
	if body.move_and_collide(motion) != null:
		var climbed := (body.global_position - ladder.pose_at(0.0)).dot(ladder.up())
		state.anchor_t = clampf(climbed, 0.0, ladder.height)
		state.velocity = Vector3.ZERO


## Salida por arriba: una trayectoria autorada de dos tramos, un poco hacia
## arriba y después hacia adentro sobre el borde. Se valida antes con
## test_move(); si algo la tapa, sigue en la escalera. Termina en Aire, a pocos
## centímetros del piso de arriba: el tick siguiente aterriza.
static func _climb_out_top(body: ActorBody, state: ActorState, ladder: Ladder, tuning: ActorTuning) -> void:
	var rise := ladder.up() * 0.05
	var inward := -ladder.outward() * (ladder.standoff + tuning.ladder_top_step)
	var start := body.global_transform
	if body.test_move(start, rise) or body.test_move(start.translated(rise), inward):
		return
	body.global_position += rise + inward
	_leave_anchor(state, tuning, Vector3.ZERO, false)


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
	var from := body.global_position
	state.mode = ActorState.Mode.HANGING
	state.anchor_id = edge["base"]
	state.anchor_point = edge["point"] - BaseRegistry.origin(edge["base"])
	state.anchor_t = 0.0
	state.velocity = Vector3.ZERO
	state.facing_yaw = _yaw_of(-edge["normal"])
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
	body.grab_jump += pose - from
	return edge


## La decisión del agarre, sin cambiar nada: barre las manos desde donde están
## hasta donde van a estar al final de este tick, hacia `direction`: la
## intención de movimiento si hay, y si no, hacia donde mira el personaje (ver
## grab_direction). La pared tiene que estar en esa dirección.
## Subiendo también agarra, pero recién cuando las manos llegan al filo: la
## pose no puede quedar más de hang_rise_reach por encima de los pies. Si en
## este tick o en el anterior (el del salto, que todavía era Suelo) las manos
## ya pasaron el filo, lo buscan de arriba hacia abajo.
## El filo se toma enfrente del centro del cuerpo (las manos pueden quedar
## corridas si llega en diagonal), si el borde sigue ahí. Valida la pose de
## colgado: cabe, el camino hasta ella está libre y queda a menos de
## hang_snap_max. Devuelve {edge, pose, why}: why vacío si se puede agarrar, o
## por qué no. Lo usan el motor y las pruebas de confirmación.
static func grab_check(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> Dictionary:
	var result := {"edge": {}, "pose": Vector3.ZERO, "why": "sin borde"}
	if state.regrab_id == ActorState.REGRAB_EDGES or state.stance != ActorState.Stance.STANDING:
		result["why"] = "bloqueo o postura"
		return result
	if direction.length_squared() < 0.01:
		result["why"] = "sin dirección"
		return result
	var toward := Vector3(direction.x, 0.0, direction.z).normalized()
	var from := body.global_position
	var fall := maxf(state.velocity.y - tuning.gravity * dt, -tuning.max_fall_speed)
	var motion := Vector3(state.velocity.x, fall, state.velocity.z) * dt
	var hands_to := EdgeProbe.hands_at(body, from + motion, toward, tuning)
	var edge := EdgeProbe.find(body, EdgeProbe.hands_at(body, from, toward, tuning), hands_to, toward)
	var rising := state.velocity.y > 0.0
	if edge.is_empty() and rising:
		var hands_before := EdgeProbe.hands_at(body, from - state.velocity * dt, toward, tuning)
		edge = EdgeProbe.find(body, hands_to, hands_before, toward)
	if edge.is_empty():
		return result
	var normal: Vector3 = edge["normal"]
	var right := (-normal).cross(Vector3.UP)
	var ahead := EdgeProbe.hold(body, edge["point"] + right * (from - edge["point"]).dot(right), normal)
	if not ahead.is_empty():
		edge = ahead
	result["edge"] = edge
	result["pose"] = _hang_pose(edge, tuning)
	if toward.dot(-edge["normal"]) < 0.5:
		result["why"] = "intención de costado"
	elif rising and result["pose"].y > from.y + tuning.hang_rise_reach:
		result["why"] = "subiendo, las manos todavía no llegan"
	elif from.y + body.stance_height(state.stance) * 0.5 > edge["point"].y:
		# Con el cuerpo por encima del filo es un aterrizaje, no un agarre.
		result["why"] = "por encima del filo"
	elif result["pose"].distance_to(from) > tuning.hang_snap_max:
		result["why"] = "snap muy largo"
	elif not body.stance_fits(ActorState.Stance.STANDING, result["pose"]):
		result["why"] = "la pose no cabe"
	elif body.test_move(body.global_transform, result["pose"] - from):
		result["why"] = "camino tapado"
	else:
		result["why"] = ""
	return result


## Hacia dónde buscan las manos un borde: la intención de movimiento si hay
## alguna tecla de dirección apretada, y si no, hacia donde mira el personaje,
## que es hacia donde se venía moviendo. Así no hace falta apretar W. Lo usan
## el motor y las pruebas de confirmación.
static func grab_direction(state: ActorState, direction: Vector3) -> Vector3:
	if direction.length_squared() >= 0.01:
		return direction
	return Vector3.FORWARD.rotated(Vector3.UP, state.facing_yaw)


## El borde agarrado, revalidado con la sonda: el punto guardado y la normal
## contraria a la orientación. Vacío si el borde ya no está o si desapareció
## la base que lo llevaba.
static func _held_edge(body: ActorBody, state: ActorState) -> Dictionary:
	if state.anchor_id != 0 and BaseRegistry.find(state.anchor_id) == null:
		return {}
	var point := BaseRegistry.origin(state.anchor_id) + state.anchor_point
	var normal := -Vector3.FORWARD.rotated(Vector3.UP, state.facing_yaw)
	return EdgeProbe.hold(body, point, normal)


## Hanging, etapa 6: se desplaza sobre el filo. La velocidad va a lo largo del
## filo y la deja un empujón menor al agarre o la pide el input lateral, A y D,
## que es la izquierda y la derecha del personaje frente a la pared, mire donde
## mire la cámara. Solo avanza si el borde sigue y el cuerpo pasa. Con un
## compañero colgado, se queda quieto. Devuelve el borde donde quedó.
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
	if absf(along) > 0.001:
		var moved := EdgeProbe.hold(body, edge["point"] + right * along * dt, normal)
		var from := _hang_pose(edge, tuning)
		if moved.is_empty() or body.test_move(Transform3D(body.global_basis, from), _hang_pose(moved, tuning) - from):
			state.velocity = Vector3.ZERO
		else:
			edge = moved
	state.anchor_point = edge["point"] - BaseRegistry.origin(state.anchor_id)
	state.facing_yaw = _yaw_of(-edge["normal"])
	return edge


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


## Hanging, etapa 7: un barrido hasta la pose de colgado. Si algo la tapa,
## sale a Aire.
static func _move_hanging(body: ActorBody, state: ActorState, edge: Dictionary, tuning: ActorTuning) -> void:
	if edge.is_empty():
		return
	var motion := _hang_pose(edge, tuning) - body.global_position
	if motion.length_squared() > 1e-12 and body.move_and_collide(motion) != null:
		_leave_edge(state, tuning, Vector3.ZERO)


## Sale de un borde a Aire con una velocidad y un bloqueo corto de reagarre de
## bordes. La velocidad de la base del borde se suma en la etapa de contactos.
static func _leave_edge(state: ActorState, tuning: ActorTuning, velocity: Vector3) -> void:
	state.mode = ActorState.Mode.AIR
	state.velocity = velocity
	state.anchor_id = 0
	state.anchor_t = 0.0
	state.anchor_point = Vector3.ZERO
	state.regrab_id = ActorState.REGRAB_EDGES
	state.regrab_left = tuning.hang_regrab_time
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0


## Enganchado desde Aire: si hook_check() encuentra un compañero del que
## colgarse, entra a Enganchado; en la etapa 7 de este mismo tick el cuerpo va
## a la pose. Es un snap lógico, como el agarre de un borde. Devuelve el
## compañero, o null.
static func _try_hook(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> ActorBody:
	var check := hook_check(body, state, direction, tuning, dt)
	if check["why"] != "":
		return null
	var mate: ActorBody = check["anchor"]
	state.mode = ActorState.Mode.HOOKED
	state.anchor_id = mate.owner_peer_id
	state.anchor_t = 0.0
	state.velocity = Vector3.ZERO
	state.facing_yaw = mate.state.facing_yaw
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
	body.grab_jump += check["pose"] - body.global_position
	return mate


## La decisión de colgarse de un compañero, sin cambiar nada. Es el mismo
## agarre que el de un borde, sin tecla: las manos buscan hacia `direction`
## (ver grab_direction), y tienen que pasar en este tick por la altura de la
## cintura del compañero (subiendo, recién cuando llegan; en el tick del salto,
## que todavía era Suelo, cuenta también el anterior). El compañero tiene que
## estar agarrado de un borde o de una escalera, sin otro colgado de él. La
## pose cabe, el camino hasta ella está libre y queda a no más de hook_reach.
## Con varios, gana el de id más chico.
##
## Del compañero se usa lo que esta máquina tiene de él: en el host, su estado
## de este tick; en un cliente, el que se está mostrando, que es del pasado.
## Como el compañero está quieto, da lo mismo.
##
## Devuelve {anchor, pose, why}: why vacío si se puede, o por qué no (el del
## último compañero mirado). Lo usan el motor y las pruebas.
static func hook_check(body: ActorBody, state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> Dictionary:
	var result := {"anchor": null, "pose": Vector3.ZERO, "why": "sin compañero"}
	if state.regrab_id == ActorState.REGRAB_TEAMMATES or state.stance != ActorState.Stance.STANDING:
		result["why"] = "bloqueo o postura"
		return result
	if direction.length_squared() < 0.01:
		result["why"] = "sin dirección"
		return result
	var toward := Vector3(direction.x, 0.0, direction.z).normalized()
	var from := body.global_position
	var fall := maxf(state.velocity.y - tuning.gravity * dt, -tuning.max_fall_speed)
	var to_y := from.y + fall * dt
	var low := minf(from.y, to_y)
	var high := maxf(from.y, to_y)
	if state.velocity.y > 0.0:
		low = minf(low, from.y - state.velocity.y * dt)
	for mate in body.teammates():
		if not _hook_holds(body, mate):
			continue
		var pose := hook_pose(mate, tuning)
		result["anchor"] = mate
		result["pose"] = pose
		if pose.y < low or pose.y > high:
			result["why"] = "las manos no pasan por su cintura"
		elif toward.dot(-_out_of(mate.state)) < 0.5:
			result["why"] = "intención de costado"
		elif pose.distance_to(from) > tuning.hook_reach:
			result["why"] = "muy lejos"
		elif not body.stance_fits(ActorState.Stance.STANDING, pose):
			result["why"] = "la pose no cabe"
		elif body.test_move(body.global_transform, pose - from):
			result["why"] = "camino tapado"
		else:
			result["why"] = ""
			return result
	return result


## Pose colgado de un compañero: las manos en su cintura, hook_height por
## encima de sus pies, y el cuerpo hook_distance más afuera que él, de
## espaldas a la pared. Depende solo del compañero.
static func hook_pose(mate: ActorBody, tuning: ActorTuning) -> Vector3:
	return mate.global_position + _out_of(mate.state) * tuning.hook_distance \
			+ Vector3.UP * (tuning.hook_height - tuning.hang_height)


## Hacia afuera de la pared de un actor agarrado (de espaldas a donde mira).
static func _out_of(state: ActorState) -> Vector3:
	return Vector3.BACK.rotated(Vector3.UP, state.facing_yaw)


## Si `mate` sostiene a este actor: existe, está agarrado de un borde o de una
## escalera, y no cuelga otro de él.
static func _hook_holds(body: ActorBody, mate: ActorBody) -> bool:
	if mate == null:
		return false
	if mate.state.mode != ActorState.Mode.HANGING and mate.state.mode != ActorState.Mode.LADDER:
		return false
	return mate.state.hooked_by == 0 or mate.state.hooked_by == body.owner_peer_id


## Enganchado, etapa 7: un barrido hasta la pose que da el compañero. Si algo
## la tapa, sale a Aire. Las manos quedan sobre su cintura, para dibujarlas.
static func _move_hooked(body: ActorBody, state: ActorState, mate: ActorBody, tuning: ActorTuning) -> void:
	if mate == null:
		return
	var pose := hook_pose(mate, tuning)
	var motion := pose - body.global_position
	if motion.length_squared() > 1e-12 and body.move_and_collide(motion) != null:
		_leave_hook(state, tuning, Vector3.ZERO, true)
		return
	var inward := -_out_of(mate.state)
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


## Velocidad de un actor en el mundo: la propia más la de su base.
static func _world_velocity(state: ActorState) -> Vector3:
	return state.velocity + BaseRegistry.velocity(state.base_id)


## Impulso que fija el eje vertical. El snap no lo vuelve a pegar al piso
## porque la velocidad sube: así lo documenta floor_snap_length.
static func _jump(state: ActorState, tuning: ActorTuning) -> void:
	state.velocity.y = tuning.jump_velocity
	state.mode = ActorState.Mode.AIR
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
