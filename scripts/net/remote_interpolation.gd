class_name RemoteInterpolation
extends RefCounted

## Paso 8, en el cliente: los demás jugadores se muestran un poco en el pasado,
## interpolando entre los dos snapshots que rodean ese momento. Así se mueven
## parejo aunque los snapshots lleguen a destiempo, desordenados o cada dos ticks.
##
## El momento que se muestra avanza con el reloj real y no con el delta de
## Godot: el cliente cambia time_scale al ajustar su ritmo, y eso no tiene que
## acelerar ni frenar a los demás. Se mantiene DELAY_TICKS detrás del snapshot
## más nuevo, corrigiéndose de a poco.

## Colchón: cuánto en el pasado se muestra a los demás, en ticks del host. Seis
## ticks son 100 ms, tres snapshots a 30 por segundo.
const DELAY_TICKS := 6.0
## Si el momento mostrado se aleja más que esto de donde debería, salta.
const MAX_DRIFT_TICKS := 30.0
## Qué parte de la diferencia con donde debería estar se corrige en cada tick.
const DRIFT_CORRECTION := 0.05
## Más que esto entre dos snapshots seguidos no se interpola: es un teleport.
const TELEPORT_DISTANCE := 4.0
## Al cambiar de marco (subirse a una base o bajarse a piso fijo), el salto
## entre cómo se lo dibujaba y cómo se lo dibuja ahora se reparte en al menos
## estos ticks del host.
const MIN_FRAME_BLEND_TICKS := 6.0
## Al bajarse de una base, el salto se reparte a esta velocidad media, en m/s,
## y en no más de MAX_LEAVE_BLEND_TICKS: el actor ya no tiene la base al lado
## para compararlo, así que conviene ir despacio.
const LEAVE_BLEND_SPEED := 1.5
const MAX_LEAVE_BLEND_TICKS := 45.0

## Veces que a un actor le faltó el snapshot siguiente y quedó quieto esperándolo.
var starved := 0

var _render_tick := 0.0
var _newest_tick := -1
var _last_usec := 0
var _samples := {}  # peer -> Array de [tick del host, ActorState], del más viejo al más nuevo
var _base_samples := {}  # id de base -> Array de [tick del host, posición, velocidad]
var _frame := {}  # peer -> base en cuyo marco se lo dibuja (0 = el mundo)
var _frame_blends := {}  # peer -> [desvío al cambiar de marco, tick en que empezó, tick en que termina]


## Guarda el estado de otro jugador que llegó en un snapshot.
func add(peer_id: int, host_tick: int, state: ActorState) -> void:
	var samples: Array = _samples.get_or_add(peer_id, [])
	if samples.is_empty() or host_tick > samples[-1][0]:
		samples.append([host_tick, state])
	_newest_tick = maxi(_newest_tick, host_tick)


## Guarda la pose de una base que simula el host (una balsa).
func add_base(base_id: int, host_tick: int, position: Vector3, velocity: Vector3) -> void:
	var samples: Array = _base_samples.get_or_add(base_id, [])
	if samples.is_empty() or host_tick > samples[-1][0]:
		samples.append([host_tick, position, velocity])
	_newest_tick = maxi(_newest_tick, host_tick)


## Al terminar cada tick: deja las copias de las bases del host en la pose
## interpolada del tick que viene, que llega `ahead` ticks del host más tarde.
## Son cuerpos cinemáticos: lo que se coloca ahora, las consultas lo ven en el
## tick siguiente.
func place_bases(ahead: float) -> void:
	for base in BaseRegistry.all():
		if not (base is HostRaft) or base.simulated:
			continue
		var next := _base_pose(base.base_id, _render_tick + ahead)
		var now := _base_pose(base.base_id, _render_tick)
		if not next.is_empty():
			base.place_copy(next[0], now[0], next[1])


## [posición, velocidad] de una base del host en un momento, o vacío si no llegó nada.
func _base_pose(base_id: int, at: float) -> Array:
	var samples: Array = _base_samples.get(base_id, [])
	if samples.is_empty():
		return []
	while samples.size() >= 3 and samples[1][0] <= _render_tick:
		samples.pop_front()
	for i in range(samples.size() - 1):
		if samples[i + 1][0] > at:
			var from: Array = samples[i]
			var to: Array = samples[i + 1]
			var weight := clampf((at - from[0]) / float(to[0] - from[0]), 0.0, 1.0)
			return [from[1].lerp(to[1], weight), from[2].lerp(to[2], weight)]
	return [samples[-1][1], samples[-1][2]]


## Avanza el momento que se muestra. Una vez por tick, antes de place().
func advance() -> void:
	var now := Time.get_ticks_usec()
	if _newest_tick >= 0:
		_render_tick += (now - _last_usec) / SimClock.TICK_USEC
		var drift := _newest_tick - DELAY_TICKS - _render_tick
		if absf(drift) > MAX_DRIFT_TICKS:
			_render_tick = _newest_tick - DELAY_TICKS
		else:
			_render_tick += drift * DRIFT_CORRECTION
	_last_usec = now


## Tick del host que se muestra de los demás, o -1 si todavía no llegó nada.
func shown_tick() -> float:
	return _render_tick if _newest_tick >= 0 else -1.0


## Pone al actor en su pose del momento que se muestra.
##
## Una plataforma guionada cerca del jugador propio se ve en el tick propio,
## que va por delante de lo que se ve de los demás (lejos, se la dibuja en el
## mismo pasado que a ellos y no hay diferencia). Por eso cada actor se dibuja
## en un marco: el de una base (pegado a ella, tal como se la ve acá) o el
## mundo (donde estaba en el host). Un salto que sale de una base y vuelve a
## caer en ella se dibuja entero en el marco de esa base, así toca la
## plataforma justo donde la toca en el host.
func place(actor: ActorBody) -> void:
	var peer := actor.owner_peer_id
	var samples: Array = _samples.get(peer, [])
	if samples.is_empty():
		return
	while samples.size() >= 2 and samples[1][0] <= _render_tick:
		samples.pop_front()
	var first := not _frame.has(peer)
	var previous: int = _frame.get(peer, samples[0][1].base_id)
	var frame := _choose_frame(samples, previous)
	var changed_frame := not first and frame != previous
	_frame[peer] = frame
	if samples.size() < 2 and samples[0][0] < _render_tick:
		starved += 1
	var state := _shown_state(samples, frame)
	var world := BaseRegistry.visual_world_position(state)
	var offset := Vector3.ZERO
	if changed_frame:
		# Cambiar de marco movería el dibujo lo que se corrió la base en esa
		# diferencia de tiempo: el visual arranca desde donde se lo vería ahora
		# en el marco anterior.
		offset = BaseRegistry.visual_world_position(_shown_state(samples, previous)) \
				+ actor.visual_offset - world
	var jumped := world.distance_to(actor.global_position) > TELEPORT_DISTANCE \
			or offset.length() > TELEPORT_DISTANCE
	actor.state = state
	actor.global_position = world
	actor.present(state)
	if first or jumped:
		_frame_blends.erase(peer)
		actor.teleported()
	elif changed_frame:
		# Al subirse a una base, el desvío se termina de repartir justo cuando
		# la toca, así no se acomoda encima de ella. Al bajarse ya no hay base
		# con qué compararlo, y se reparte despacio.
		var end := _render_tick + MIN_FRAME_BLEND_TICKS
		if frame != 0:
			end = maxf(end, _support_tick(samples, frame))
		else:
			end = _render_tick + clampf(offset.length() / LEAVE_BLEND_SPEED / SimClock.TICK_DT,
					MIN_FRAME_BLEND_TICKS, MAX_LEAVE_BLEND_TICKS)
		_frame_blends[peer] = [offset, _render_tick, end]
	_apply_frame_blend(actor)


func forget(peer_id: int) -> void:
	_samples.erase(peer_id)
	_frame.erase(peer_id)
	_frame_blends.erase(peer_id)


## Lo que se muestra del actor en el marco `frame`: la mezcla de los dos
## snapshots que rodean el momento que se muestra, pasados a ese marco.
func _shown_state(samples: Array, frame: int) -> ActorState:
	var from: Array = samples[0]
	var state := _in_frame(from[1], from[0], frame)
	if samples.size() >= 2:
		var to: Array = samples[1]
		var span := float(to[0] - from[0])
		var weight := clampf((_render_tick - from[0]) / span, 0.0, 1.0)
		state = _blend(state, _in_frame(to[1], to[0], frame), weight, span)
	return state


## Reparte el desvío de un cambio de marco hasta el tick en que termina,
## arrancando y frenando suave para que no se note un cambio brusco de velocidad.
func _apply_frame_blend(actor: ActorBody) -> void:
	var blend: Variant = _frame_blends.get(actor.owner_peer_id)
	if blend == null:
		return
	var progress := clampf((_render_tick - blend[1]) / (blend[2] - blend[1]), 0.0, 1.0)
	actor.set_visual_offset(blend[0] * (1.0 - smoothstep(0.0, 1.0, progress)))
	if progress >= 1.0:
		_frame_blends.erase(actor.owner_peer_id)


## Tick del host del primer snapshot en que ya está apoyado en el marco nuevo.
static func _support_tick(samples: Array, frame: int) -> float:
	for sample in samples:
		var state: ActorState = sample[1]
		if state.on_floor and state.base_id == frame:
			return float(sample[0])
	return float(samples[-1][0])


## Marco en el que se dibuja a un actor, según su snapshot más nuevo: si está
## parado sobre una base, el de esa base; si está parado en piso fijo, el
## mundo; si está en el aire, el que ya tenía. Como el snapshot más nuevo va
## por delante de lo que se muestra, el cambio llega un poco antes de tocar.
## Pero mientras se lo ve parado sobre su base no la deja: si sale caminando,
## el marco cambia recién cuando se lo ve salir.
static func _choose_frame(samples: Array, current: int) -> int:
	var newest: ActorState = samples[-1][1]
	var shown: ActorState = samples[0][1]
	var frame := current
	if newest.base_id != 0 or newest.on_floor:
		frame = newest.base_id
	if frame != current and current != 0 and shown.on_floor and shown.base_id == current:
		frame = current
	return frame if frame == 0 or BaseRegistry.find(frame) != null else 0


## El estado de un snapshot del tick `tick` del host, con la posición y la
## velocidad pasadas al marco `frame`.
func _in_frame(state: ActorState, tick: int, frame: int) -> ActorState:
	if state.base_id == frame:
		return state
	var own_base := _base_at(state.base_id, tick)
	var frame_base := _base_at(frame, tick)
	var moved := state.copy()
	moved.base_id = frame
	moved.position = state.position + own_base[0] - frame_base[0]
	moved.velocity = state.velocity + own_base[1] - frame_base[1]
	return moved


## [posición, velocidad] de una base en un tick del host. Las plataformas
## guionadas se calculan; las balsas salen de sus snapshots.
func _base_at(base_id: int, tick: int) -> Array:
	if base_id == 0:
		return [Vector3.ZERO, Vector3.ZERO]
	var base = BaseRegistry.find(base_id)
	if base is ScriptedPlatform:
		return [base.pose_at(tick), (base.pose_at(tick + 1) - base.pose_at(tick)) / SimClock.TICK_DT]
	var pose := _base_pose(base_id, tick)
	if pose.is_empty():
		return [BaseRegistry.origin(base_id), BaseRegistry.velocity(base_id)]
	return pose


## Pose intermedia entre dos snapshots, los dos ya en el mismo marco. Lo que
## no es continuo (modo, piso, época, postura) sale del más cercano. Si entre
## los dos hubo un teleport, no se mezcla. Si cambió de postura, tampoco: en el
## aire eso mueve los pies de golpe, y mezclar las alturas dibujaría la forma
## nueva a mitad de camino. Se sigue al más cercano, avanzado con su velocidad,
## y el salto se ve de una vez (ActorBody.present). `span` es cuántos ticks
## separan a los dos.
static func _blend(from: ActorState, to: ActorState, weight: float, span: float) -> ActorState:
	var nearest := from if weight < 0.5 else to
	if from.stance != to.stance:
		var moved := nearest.copy()
		var ticks_away := weight * span if nearest == from else (weight - 1.0) * span
		moved.position += nearest.velocity * ticks_away * SimClock.TICK_DT
		return moved
	if from.position.distance_to(to.position) > TELEPORT_DISTANCE:
		return nearest
	var state := nearest.copy()
	state.position = from.position.lerp(to.position, weight)
	state.velocity = from.velocity.lerp(to.velocity, weight)
	state.facing_yaw = lerp_angle(from.facing_yaw, to.facing_yaw, weight)
	return state
