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
## - la posición difiere de la del host en menos de MAX_DIFFERENCE;
## - la pose entra en el mundo del host: no queda metida en la geometría y,
##   si dice estar apoyada, hay piso. Los modos anclados agregarán su propio
##   validador.
##
## Riesgo: adoptar puede tapar una desincronización real. Por eso se registra
## cuánto difería cada afirmación adoptada, y la adopción se puede apagar.

enum Result { NO_CLAIM, SAME, ADOPTED, OFF, WRONG_EPOCH, TOO_FAR, BAD_POSE }

## Diferencia máxima de posición para adoptar, en metros. Valor de partida, a
## calibrar: caminando, cubre un input que llegó unos 10 ticks tarde.
const MAX_DIFFERENCE := 1.0

var enabled := true
var _stats := {}  # peer -> {Result: veces, "max": diferencia adoptada más grande}


## Considera la afirmación del cliente para el tick que el host acaba de
## simular y, si corresponde, la adopta como estado del actor.
func consider(actor: ActorBody, claim_bytes: PackedByteArray) -> Result:
	var stats: Dictionary = _stats.get_or_add(actor.owner_peer_id, {"max": 0.0})
	var result := _decide(actor, claim_bytes, stats)
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


func _decide(actor: ActorBody, claim_bytes: PackedByteArray, stats: Dictionary) -> Result:
	if claim_bytes.is_empty():
		return Result.NO_CLAIM
	if claim_bytes == actor.state.to_bytes():
		return Result.SAME
	if not enabled:
		return Result.OFF
	var claim := ActorState.from_bytes(claim_bytes)
	if claim.epoch != actor.state.epoch:
		return Result.WRONG_EPOCH
	# En el mundo: la afirmación puede estar sobre otra base que el resultado del host.
	var difference := BaseRegistry.world_position(claim).distance_to(BaseRegistry.world_position(actor.state))
	if difference > MAX_DIFFERENCE:
		return Result.TOO_FAR
	var seen := actor.seen_position()
	if not actor.apply_state(claim):
		actor.apply_state(actor.state)
		return Result.BAD_POSE
	actor.state = claim
	# En el host el actor salta a lo que afirmó el cliente; se suaviza igual que una corrección.
	actor.smooth_from(seen)
	stats["max"] = maxf(stats["max"], difference)
	return Result.ADOPTED
