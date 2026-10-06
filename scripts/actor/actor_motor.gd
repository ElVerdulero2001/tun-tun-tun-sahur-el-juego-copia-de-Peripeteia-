class_name ActorMotor
extends RefCounted

## Paso por tick de un actor: recibe estado, input y dt, mueve el cuerpo y deja
## el estado del tick siguiente. No guarda nada propio; por eso cualquier tick
## se puede repetir después de restaurar el estado.
##
## Sigue el orden fijo de etapas de la arquitectura. Por ahora existen los modos
## Suelo, Aire y Deslizamiento, y la postura (parado o agachado). Todavía no
## hace falta la etapa de sondas (4): la de suelo corre en la etapa de
## contactos y la de espacio libre, en la de postura.
##
## Sobre una base (plataforma, balsa), la posición y la velocidad del estado
## son relativas a ella. La base no se rebobina al repetir ticks: si se repiten,
## todo pasa en coordenadas de la base, sobre su pose de ahora.

## Consulta de la sonda de suelo, armada una sola vez.
static var _probe_params: PhysicsShapeQueryParameters3D


static func step(body: ActorBody, state: ActorState, input: ActorInput, tuning: ActorTuning, dt: float) -> void:
	# 1. Tiempo: todo lo que dura se descuenta en tiempo del actor.
	state.coyote_left = maxf(state.coyote_left - dt, 0.0)
	state.jump_buffer_left = maxf(state.jump_buffer_left - dt, 0.0)

	# 2. Base: la base se movió desde el tick anterior y lleva al actor.
	_ride_base(body, state)

	# 3. Eventos. Una pulsación nueva se detecta porque el contador cambió,
	# aunque se haya perdido el tick exacto en que ocurrió.
	if input.jump_presses != state.jump_presses_seen:
		state.jump_presses_seen = input.jump_presses
		state.jump_buffer_left = tuning.jump_buffer_time

	# 5. Transición: como máximo una por tick, decidida por la situación actual.
	var wants_jump := state.jump_buffer_left > 0.0
	var crouch_held := input.is_held(ActorInput.BUTTON_CROUCH)
	match state.mode:
		ActorState.Mode.GROUND:
			if wants_jump:
				_jump(state, tuning)
			elif not state.on_floor:
				state.mode = ActorState.Mode.AIR
				state.coyote_left = tuning.coyote_time
			elif crouch_held and state.stance == ActorState.Stance.STANDING \
					and _horizontal_speed(state) >= tuning.slide_entry_speed:
				state.mode = ActorState.Mode.SLIDE
		ActorState.Mode.AIR:
			if state.on_floor and state.velocity.y <= 0.0:
				state.mode = ActorState.Mode.GROUND
			elif wants_jump and state.coyote_left > 0.0:
				_jump(state, tuning)
		ActorState.Mode.SLIDE:
			if wants_jump:
				_jump(state, tuning)
			elif not state.on_floor:
				state.mode = ActorState.Mode.AIR
				state.coyote_left = tuning.coyote_time
			elif _horizontal_speed(state) < tuning.slide_min_speed:
				state.mode = ActorState.Mode.GROUND

	# 6. Modo: el modo activo decide la velocidad.
	var direction := _wish_direction(input)
	match state.mode:
		ActorState.Mode.GROUND:
			_ground(state, direction * _ground_speed(state, input, tuning), tuning, dt)
		ActorState.Mode.AIR:
			_air(state, direction, tuning, dt)
		ActorState.Mode.SLIDE:
			_slide(state, direction, tuning, dt)
	if state.mode == ActorState.Mode.SLIDE:
		if _horizontal_speed(state) > 0.01:
			state.facing_yaw = _yaw_of(state.velocity)
	elif direction.length_squared() > 0.0001:
		state.facing_yaw = _yaw_of(direction)

	# 7. Postura y movimiento. Deslizamiento siempre pide agachado; si no, lo
	# pide el input. El snap al piso no existe en el aire.
	var wanted := ActorState.Stance.CROUCHED if crouch_held or state.mode == ActorState.Mode.SLIDE \
			else ActorState.Stance.STANDING
	_resolve_stance(body, state, wanted)
	var snap := 0.0 if state.mode == ActorState.Mode.AIR else tuning.floor_snap_length
	body.slide(state, snap, dt)

	# 8. Contactos: los indicadores de Godot pasan al estado, y la sonda de
	# suelo dice sobre qué base quedó parado. Al cambiar de base, la velocidad
	# pasa al marco de la nueva: quien deja una base se lleva su velocidad.
	# Todo se cuantiza, y el cuerpo arranca el tick siguiente desde la posición
	# cuantizada, igual que arrancaría después de restaurar.
	state.on_floor = body.is_on_floor()
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


## Empujón: un evento del host, que lo aplica al empezar el tick, antes del
## paso. Suma el impulso y pasa a Aire como el salto, así el snap no lo vuelve
## a pegar al piso. Quien lo aplica también sube la época del actor.
static func push(state: ActorState, impulse: Vector3) -> void:
	state.velocity += impulse
	state.mode = ActorState.Mode.AIR
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0


## Impulso que fija el eje vertical. El snap no lo vuelve a pegar al piso
## porque la velocidad sube: así lo documenta floor_snap_length.
static func _jump(state: ActorState, tuning: ActorTuning) -> void:
	state.velocity.y = tuning.jump_velocity
	state.mode = ActorState.Mode.AIR
	state.jump_buffer_left = 0.0
	state.coyote_left = 0.0
