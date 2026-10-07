class_name ActorMotor
extends RefCounted

## Paso por tick de un actor: recibe estado, input y dt, mueve el cuerpo y deja
## el estado del tick siguiente. No guarda nada propio; por eso cualquier tick
## se puede repetir después de restaurar el estado.
##
## Sigue el orden fijo de etapas de la arquitectura. Por ahora existen los modos
## Suelo, Aire, Deslizamiento y Ladder, y la postura (parado o agachado). La
## etapa de sondas (4) todavía no es una etapa aparte: la de suelo corre en la
## de contactos, la de espacio libre en la de postura, la de escalera en la
## de transición, que es la única que la usa, y la de escalón en la de
## movimiento, porque necesita saber si el movimiento chocó.
##
## Sobre una base (plataforma, balsa), la posición y la velocidad del estado
## son relativas a ella. La base no se rebobina al repetir ticks: si se repiten,
## todo pasa en coordenadas de la base, sobre su pose de ahora.

## Consulta de la sonda de suelo, armada una sola vez.
static var _probe_params: PhysicsShapeQueryParameters3D


static func step(body: ActorBody, state: ActorState, input: ActorInput, tuning: ActorTuning, dt: float) -> void:
	body.stepped_up = 0.0

	# 1. Tiempo: todo lo que dura se descuenta en tiempo del actor.
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
			elif wants_jump:
				_leave_anchor(state, tuning,
						ladder.outward() * tuning.ladder_jump_out + ladder.up() * tuning.ladder_jump_up, true)
			elif state.anchor_t <= 0.0 and toward < -0.5:
				_leave_anchor(state, tuning, Vector3.ZERO, false)
			elif state.anchor_t >= ladder.height and toward > 0.5:
				_climb_out_top(body, state, ladder, tuning)

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
	if state.mode == ActorState.Mode.SLIDE:
		if _horizontal_speed(state) > 0.01:
			state.facing_yaw = _yaw_of(state.velocity)
	elif state.mode != ActorState.Mode.LADDER and direction.length_squared() > 0.0001:
		state.facing_yaw = _yaw_of(direction)

	# 7. Postura y movimiento. Deslizamiento siempre pide agachado; en la
	# escalera se va parado; si no, lo pide el input. Los modos libres mueven
	# con move_and_slide(), sin snap en el aire; Ladder, con un barrido. En
	# Suelo, si el movimiento chocó, la sonda de escalón prueba subirlo.
	var wanted := ActorState.Stance.STANDING
	if state.mode == ActorState.Mode.SLIDE or (crouch_held and state.mode != ActorState.Mode.LADDER):
		wanted = ActorState.Stance.CROUCHED
	_resolve_stance(body, state, wanted)
	if state.mode == ActorState.Mode.LADDER:
		_move_on_ladder(body, state)
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
	# cuantizada, igual que arrancaría después de restaurar. En la escalera no
	# hubo move_and_slide(): los indicadores de Godot quedaron viejos.
	state.on_floor = body.is_on_floor() and state.mode != ActorState.Mode.LADDER
	state.floor_normal = body.get_floor_normal() if state.on_floor else Vector3.UP
	var base_now := _probe_base(body) if state.on_floor else 0
	if base_now != state.base_id:
		state.velocity += BaseRegistry.velocity(state.base_id) - BaseRegistry.velocity(base_now)
		state.base_id = base_now
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
	body.stepped_up += gained


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
## modo lo proyecta sobre lo que puede moverse (en Ladder, sobre el eje) y el
## resto se descarta.
static func apply_impulse(state: ActorState, impulse: Vector3, force: int, tuning: ActorTuning) -> void:
	if state.mode == ActorState.Mode.LADDER:
		if force >= tuning.ladder_grip:
			_leave_anchor(state, tuning, impulse, true)
		else:
			state.velocity += impulse
		return
	state.velocity += impulse
	state.mode = ActorState.Mode.AIR
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0


## Para validar una afirmación en un modo anclado: el ancla existe, el
## parámetro está en rango y el cuerpo está en la pose que le corresponde.
static func anchored_pose_valid(state: ActorState) -> bool:
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
## menor al agarre) queda proyectado sobre el eje y se va frenando.
static func _ladder(state: ActorState, direction: Vector3, tuning: ActorTuning, dt: float) -> void:
	var ladder := Ladder.find(state.anchor_id)
	if ladder == null:
		return
	var along := state.velocity.dot(ladder.up())
	var wish := clampf(direction.dot(-ladder.outward()), -1.0, 1.0) * tuning.climb_speed
	along = move_toward(along, wish, tuning.climb_accel * dt)
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


## Impulso que fija el eje vertical. El snap no lo vuelve a pegar al piso
## porque la velocidad sube: así lo documenta floor_snap_length.
static func _jump(state: ActorState, tuning: ActorTuning) -> void:
	state.velocity.y = tuning.jump_velocity
	state.mode = ActorState.Mode.AIR
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
