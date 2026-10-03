class_name ActorMotor
extends RefCounted

## Paso por tick de un actor: recibe estado, input y dt, mueve el cuerpo y deja
## el estado del tick siguiente. No guarda nada propio; por eso cualquier tick
## se puede repetir después de restaurar el estado.
##
## Sigue el orden fijo de etapas de la arquitectura. En este paso del esqueleto
## solo existen los modos Suelo y Aire, y todavía no hacen falta las etapas de
## base (2) ni de sondas (4).


static func step(body: ActorBody, state: ActorState, input: ActorInput, tuning: ActorTuning, dt: float) -> void:
	# 1. Tiempo: todo lo que dura se descuenta en tiempo del actor.
	state.coyote_left = maxf(state.coyote_left - dt, 0.0)
	state.jump_buffer_left = maxf(state.jump_buffer_left - dt, 0.0)

	# 3. Eventos. Una pulsación nueva se detecta porque el contador cambió,
	# aunque se haya perdido el tick exacto en que ocurrió.
	if input.jump_presses != state.jump_presses_seen:
		state.jump_presses_seen = input.jump_presses
		state.jump_buffer_left = tuning.jump_buffer_time

	# 5. Transición: como máximo una por tick, decidida por la situación actual.
	var wants_jump := state.jump_buffer_left > 0.0
	match state.mode:
		ActorState.Mode.GROUND:
			if wants_jump:
				_jump(state, tuning)
			elif not state.on_floor:
				state.mode = ActorState.Mode.AIR
				state.coyote_left = tuning.coyote_time
		ActorState.Mode.AIR:
			if state.on_floor and state.velocity.y <= 0.0:
				state.mode = ActorState.Mode.GROUND
			elif wants_jump and state.coyote_left > 0.0:
				_jump(state, tuning)

	# 6. Modo: el modo activo decide la velocidad.
	var wish := _wish_velocity(input, tuning)
	match state.mode:
		ActorState.Mode.GROUND:
			_ground(state, wish, tuning, dt)
		ActorState.Mode.AIR:
			_air(state, wish, tuning, dt)
	if wish.length_squared() > 0.0001:
		state.facing_yaw = atan2(-wish.x, -wish.z)

	# 7. Movimiento. El snap al piso solo existe en Suelo.
	var snap := tuning.floor_snap_length if state.mode == ActorState.Mode.GROUND else 0.0
	body.slide(state, snap, dt)

	# 8. Contactos: los indicadores de Godot pasan al estado y todo se cuantiza.
	# El cuerpo arranca el tick siguiente desde la posición cuantizada, igual
	# que arrancaría después de restaurar.
	state.on_floor = body.is_on_floor()
	state.floor_normal = body.get_floor_normal() if state.on_floor else Vector3.UP
	state.position = body.global_position
	state.quantize()
	body.global_position = state.position


static func _wish_velocity(input: ActorInput, tuning: ActorTuning) -> Vector3:
	var local := Vector3(input.move.x, 0.0, -input.move.y)
	return local.rotated(Vector3.UP, input.look_yaw) * tuning.walk_speed


static func _ground(state: ActorState, wish: Vector3, tuning: ActorTuning, dt: float) -> void:
	var horizontal := Vector3(state.velocity.x, 0.0, state.velocity.z)
	var rate := tuning.ground_accel if wish.length_squared() > 0.0 else tuning.ground_decel
	horizontal = horizontal.move_toward(wish, rate * dt)
	# En Suelo la velocidad vertical es cero: las pendientes las resuelve el snap.
	state.velocity = horizontal


static func _air(state: ActorState, wish: Vector3, tuning: ActorTuning, dt: float) -> void:
	var horizontal := Vector3(state.velocity.x, 0.0, state.velocity.z)
	if wish.length_squared() > 0.0:
		horizontal = horizontal.move_toward(wish, tuning.air_accel * dt)
	var vertical := maxf(state.velocity.y - tuning.gravity * dt, -tuning.max_fall_speed)
	state.velocity = Vector3(horizontal.x, vertical, horizontal.z)


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
