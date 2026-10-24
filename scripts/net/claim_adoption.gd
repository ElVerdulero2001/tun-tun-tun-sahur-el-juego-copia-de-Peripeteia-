class_name ClaimAdoption
extends RefCounted

## Paso 7, en el host: después de simular el tick de un cliente, mira lo que
## ese cliente afirma haber predicho para el mismo tick y, si es creíble, se
## queda con eso. Así un input que llegó tarde no termina en una corrección
## para el cliente, y Jolt puede dar milésimas distintas en cada máquina sin
## que el host las imponga. El host solo impone lo que el cliente no sabía.
##
## Adopta solo si se cumple todo:
## - la época coincide: el cliente ya incluyó todos los eventos del host;
## - los valores son posibles: la velocidad no se aleja de la del host más que
##   lo que cambia un input que llegó tarde, los tiempos no pasan de su máximo
##   en el Tuning, y lo que decide el host (quién cuelga de este actor) es lo
##   que dice el host. Un cliente con un error no
##   le pasa al host, ni a los demás, un estado imposible;
## - la posición difiere de la del host en menos de MAX_DIFFERENCE;
## - la pose entra en el mundo del host: no queda metida en la geometría y,
##   si dice estar apoyada, hay piso. En un modo anclado, además, el ancla
##   existe y el cuerpo está en la pose que le corresponde.
##
## Riesgo: adoptar puede tapar una desincronización real. Por eso se registra
## cuánto difería cada afirmación adoptada, y la adopción se puede apagar.
##
## Colgado de un compañero (Enganchado), el ancla es otro actor: el compañero
## existe, lo sostiene y la pose está cerca de la que da el compañero acá (el
## cliente lo vio en el pasado, quieto).

enum Result { NO_CLAIM, SAME, ADOPTED, OFF, WRONG_EPOCH, TOO_FAR, BAD_POSE, BAD_VALUES }

## Diferencia máxima de posición para adoptar, en metros. Valor de partida, a
## calibrar: caminando, cubre un input que llegó unos 10 ticks tarde.
const MAX_DIFFERENCE := 1.0
## Margen sobre la diferencia de velocidad más grande que puede dar un input
## que llegó tarde (ver _max_velocity_difference()), en m/s.
const VELOCITY_MARGIN := 1.5
## Margen para comparar tiempos ya cuantizados.
const TIME_MARGIN := ActorState.TIME_STEP

var enabled := true
var _stats := {}  # peer -> {Result: veces, "max": diferencia adoptada más grande}


## Considera la afirmación del cliente para el tick que el host acaba de
## simular y, si corresponde, la adopta como estado del actor.
func consider(actor: ActorBody, claim_bytes: PackedByteArray, tuning: ActorTuning) -> Result:
	var stats: Dictionary = _stats.get_or_add(actor.owner_peer_id, {"max": 0.0})
	var result := _decide(actor, claim_bytes, stats, tuning)
	stats[result] = stats.get(result, 0) + 1
	return result


## Jugadores con alguna afirmación considerada, incluidos los que ya se fueron.
func peers() -> Array:
	return _stats.keys()


func count(peer_id: int, result: Result) -> int:
	return _stats.get(peer_id, {}).get(result, 0)


## La diferencia más grande entre el host y una afirmación que igual se adoptó.
func max_difference(peer_id: int) -> float:
	return _stats.get(peer_id, {}).get("max", 0.0)


func _decide(actor: ActorBody, claim_bytes: PackedByteArray, stats: Dictionary, tuning: ActorTuning) -> Result:
	if claim_bytes.is_empty():
		return Result.NO_CLAIM
	if claim_bytes == actor.state.to_bytes():
		return Result.SAME
	if not enabled:
		return Result.OFF
	var claim := ActorState.from_bytes(claim_bytes)
	if claim.epoch != actor.state.epoch:
		return Result.WRONG_EPOCH
	if not _values_possible(claim, actor.state, tuning):
		return Result.BAD_VALUES
	# En el mundo: la afirmación puede estar sobre otra base que el resultado del host.
	var difference := BaseRegistry.world_position(claim).distance_to(BaseRegistry.world_position(actor.state))
	if difference > MAX_DIFFERENCE:
		return Result.TOO_FAR
	if not ActorMotor.anchored_pose_valid(actor, claim, tuning):
		return Result.BAD_POSE
	var seen := actor.seen_position()
	if not actor.apply_state(claim):
		actor.apply_state(actor.state)
		return Result.BAD_POSE
	actor.state = claim
	# En el host el actor salta a lo que afirmó el cliente; se suaviza igual que una corrección.
	actor.smooth_from(seen)
	stats["max"] = maxf(stats["max"], difference)
	return Result.ADOPTED


## Si lo que afirma el cliente puede salir del motor partiendo de lo que tiene
## el host, con la misma época: modos y posturas que existen, una base que
## existe, una velocidad cerca de la del host, tiempos dentro de su máximo, y
## lo que decide el host igual que en el host. Soltarse borra quién cuelga de
## este actor, así que el cliente puede tener cero si ya no está en un modo del
## que se cuelga un compañero. Agarrado todavía, cero sería borrar al que
## cuelga sin soltarse: que alguien se cuelgue es un evento del host
## (ActorMotor.assign_hooks), así que con la misma época el cliente ya lo sabe.
func _values_possible(claim: ActorState, host: ActorState, tuning: ActorTuning) -> bool:
	if claim.mode >= ActorState.Mode.size() or claim.stance >= ActorState.Stance.size() \
			or claim.stance_wanted >= ActorState.Stance.size():
		return false
	if claim.base_id != 0 and BaseRegistry.find(claim.base_id) == null:
		return false
	if absf(claim.floor_normal.length() - 1.0) > 0.01:
		return false
	if claim.velocity.distance_to(host.velocity) > _max_velocity_difference(tuning):
		return false
	if not _time_within(claim.coyote_left, tuning.coyote_time) \
			or not _time_within(claim.jump_buffer_left, tuning.jump_buffer_time) \
			or not _time_within(claim.regrab_left, maxf(tuning.regrab_block_time, tuning.hang_regrab_time)):
		return false
	return claim.hooked_by == host.hooked_by or (claim.hooked_by == 0 and not ActorMotor.holds_mates(claim.mode))


## Lo más que un input que llegó tarde puede cambiar la velocidad: arrancar a
## correr, deslizarse hasta su tope o deslizarse por un cable, lo más rápido de
## los tres con el súper salto y velocidad (with_boost), y saltar a la vez, en
## direcciones distintas, con el salto más alto (el de la escalera o el súper
## salto), más un margen. Con el Tuning de partida: 18 m/s y 7,2 m/s, unos
## 21 m/s.
static func _max_velocity_difference(tuning: ActorTuning) -> float:
	var fast := tuning.with_boost(true)
	var run := maxf(maxf(fast.sprint_speed, fast.cable_slide_speed), fast.slide_max_speed)
	var dt := SimClock.TICK_DT
	var jump := maxf(ActorMotor.floor_jump_speed(tuning, dt, maxf(tuning.ladder_jump_extra, tuning.boost_jump_extra)),
			ActorMotor.raised_jump_speed(tuning.air_jump_velocity, tuning, dt, tuning.boost_jump_extra))
	return Vector2(run, jump).length() + VELOCITY_MARGIN


static func _time_within(value: float, most: float) -> bool:
	return value >= 0.0 and value <= most + TIME_MARGIN
