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

## Veces que a un actor le faltó el snapshot siguiente y quedó quieto esperándolo.
var starved := 0

var _render_tick := 0.0
var _newest_tick := -1
var _last_usec := 0
var _samples := {}  # peer -> Array de [tick del host, ActorState], del más viejo al más nuevo


## Guarda el estado de otro jugador que llegó en un snapshot.
func add(peer_id: int, host_tick: int, state: ActorState) -> void:
	var samples: Array = _samples.get_or_add(peer_id, [])
	if samples.is_empty() or host_tick > samples[-1][0]:
		samples.append([host_tick, state])
	_newest_tick = maxi(_newest_tick, host_tick)


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


## Pone al actor en su pose del momento que se muestra.
func place(actor: ActorBody) -> void:
	var samples: Array = _samples.get(actor.owner_peer_id, [])
	if samples.is_empty():
		return
	while samples.size() >= 2 and samples[1][0] <= _render_tick:
		samples.pop_front()
	var from: Array = samples[0]
	var state: ActorState = from[1]
	if samples.size() >= 2:
		var to: Array = samples[1]
		var weight := clampf((_render_tick - from[0]) / float(to[0] - from[0]), 0.0, 1.0)
		state = _blend(from[1], to[1], weight)
	elif from[0] < _render_tick:
		starved += 1
	var jumped := state.position.distance_to(actor.global_position) > TELEPORT_DISTANCE
	actor.state = state
	actor.global_position = state.position
	actor.present(state)
	if jumped:
		actor.teleported()


func forget(peer_id: int) -> void:
	_samples.erase(peer_id)


## Pose intermedia entre dos snapshots. Lo que no es continuo (modo, piso,
## época) sale del más cercano. Si entre los dos hubo un teleport, no se mezcla.
static func _blend(from: ActorState, to: ActorState, weight: float) -> ActorState:
	var nearest := from if weight < 0.5 else to
	if from.position.distance_to(to.position) > TELEPORT_DISTANCE:
		return nearest
	var state := nearest.copy()
	state.position = from.position.lerp(to.position, weight)
	state.velocity = from.velocity.lerp(to.velocity, weight)
	state.facing_yaw = lerp_angle(from.facing_yaw, to.facing_yaw, weight)
	return state
