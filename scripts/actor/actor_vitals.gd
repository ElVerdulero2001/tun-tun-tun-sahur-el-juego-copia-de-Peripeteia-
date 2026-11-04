class_name ActorVitals
extends RefCounted

## La salud y la estamina de un actor, para lo que las mira o las cambia desde
## afuera del motor: la interfaz del inventario las lee (para saber si un
## objeto se puede usar) y el host las cambia con los consumibles. Es el
## contrato entre el inventario y el estado del actor: no sabe de objetos.
##
## Viven en ActorState (health, stamina, los daños en el tiempo): así viajan en
## los snapshots, se predicen y se repiten como el resto. Desde el 2026-11-04 un
## consumible se usa desde el input (InvNet.use_before_step): el host y la
## predicción del cliente lo aplican en el mismo tick, sin subir la época
## (host_event falso). Pedido al host (InvProtocol USE), sigue siendo un evento
## del host: sube la época, como un empujón, y el cliente se entera con la
## corrección. El daño en el tiempo, una vez puesto, lo descuenta el motor en
## cada tick (step), igual en el host y en la predicción.
##
## Muerte de prueba (decidida por el usuario, 2026-11-02): cuando la salud
## llega a cero, en el mismo paso se registra la muerte (ActorState.deaths), se
## apagan todos los estados del jugador, se cortan los daños en el tiempo y la
## salud vuelve al máximo. La posición, el inventario y la estamina se
## conservan, y los estados no se prenden solos después.
##
## Daño en el tiempo (decidido por el usuario, 2026-11-02): baja la salud
## parejo, un poco en cada tick, hasta quitar lo que tenía que quitar o hasta
## la muerte. Va con el tiempo del mundo: con la cámara lenta, más despacio.
## Varios se acumulan, cada uno con su ritmo, hasta ActorState.MAX_EFFECTS.

## Milésimas de tick en un tick sin cámara lenta: el tiempo de un daño en el tiempo.
const TIME_PER_TICK := 1000

var state: ActorState
var tuning: ActorTuning
## Si aplicar es un evento del host (sube la época). Falso cuando el uso viene
## del input y la predicción del cliente hace lo mismo en el mismo tick.
var host_event := true


static func of(p_state: ActorState, p_tuning: ActorTuning) -> ActorVitals:
	var vitals := ActorVitals.new()
	vitals.state = p_state
	vitals.tuning = p_tuning
	return vitals


## Salud en puntos, con decimales.
func health() -> float:
	return state.health / float(ActorState.HEALTH_UNIT)


func health_max() -> int:
	return max_health(tuning)


func health_full() -> bool:
	return state.health >= health_max() * ActorState.HEALTH_UNIT


## Estamina en unidades visibles (de 0 a stamina_max), con decimales.
func stamina() -> float:
	return state.stamina / float(ActorPowers.STAMINA_UNIT)


func stamina_max() -> int:
	return clampi(tuning.stamina_max, 1, 10000)


func stamina_full() -> bool:
	return state.stamina >= stamina_max() * ActorPowers.STAMINA_UNIT


## Si queda un lugar para otro daño en el tiempo.
func has_room_for_effect() -> bool:
	return state.effect_duration.has(0)


## Cuánto les queda por quitar a los daños en el tiempo, en puntos, y cuánto
## le falta al más largo, en segundos del mundo: [puntos, segundos, cuántos].
func effects_left() -> Array:
	var damage := 0
	var longest := 0
	var count := 0
	for i in ActorState.MAX_EFFECTS:
		var duration := state.effect_duration[i]
		if duration > 0:
			damage += state.effect_total[i] - _removed(state.effect_total[i], duration, state.effect_elapsed[i])
			longest = maxi(longest, duration - state.effect_elapsed[i])
			count += 1
	return [damage / float(ActorState.HEALTH_UNIT), longest / float(TIME_PER_TICK) * SimClock.TICK_DT, count]


## Lo que un daño en el tiempo ya quitó cuando lleva `elapsed` de `duration`:
## la parte exacta del total, redondeada para abajo.
static func _removed(total: int, duration: int, elapsed: int) -> int:
	@warning_ignore("integer_division")
	return total * mini(elapsed, duration) / duration


## Aplica un consumible, todo junto y en este orden: la estamina, el cambio de
## salud de golpe y el daño en el tiempo (`over_time` puntos en `seconds`
## segundos del mundo). Curar y recuperar no pasan del máximo; si la salud
## llega a cero es una muerte de prueba, y un daño en el tiempo del mismo
## consumible ya no se pone. Quien lo llama comprobó antes que hay lugar para
## el daño en el tiempo (has_room_for_effect). Lo hace el host y, con un uso
## desde el input, también la predicción del cliente. Si es un evento del host
## (host_event), sube la época una vez. Devuelve si murió.
func apply(health_change: int, stamina_gain: int, over_time: int = 0, seconds: float = 0.0) -> bool:
	if stamina_gain > 0:
		var most := stamina_max() * ActorPowers.STAMINA_UNIT
		state.stamina = mini(state.stamina + stamina_gain * ActorPowers.STAMINA_UNIT, most)
	var died := false
	if health_change != 0:
		state.health = clampi(state.health + health_change * ActorState.HEALTH_UNIT, 0, health_max() * ActorState.HEALTH_UNIT)
		if state.health == 0:
			died = true
			die(state, tuning)
	if not died and over_time > 0:
		var slot := state.effect_duration.find(0)
		if slot >= 0:
			state.effect_total[slot] = over_time * ActorState.HEALTH_UNIT
			state.effect_duration[slot] = maxi(roundi(maxf(seconds, 0.0) * SimClock.TICK_RATE * TIME_PER_TICK), 1)
			state.effect_elapsed[slot] = 0
	if host_event:
		state.epoch += 1
	return died


## En cada tick, desde el motor: cada daño en el tiempo avanza el tiempo del
## mundo que pasó (`dt`, que con la cámara lenta es 0,3 de un tick) y quita la
## parte del total que le toca a ese tramo. Como se cuenta sobre el total y no
## sobre lo que queda, baja parejo desde el primer tick, también con daños
## chicos y largos, y al terminar quitó justo el total. Con la salud en cero,
## muerte de prueba.
static func step(p_state: ActorState, p_tuning: ActorTuning, dt: float) -> void:
	if p_state.effect_duration.count(0) == ActorState.MAX_EFFECTS:
		return
	var passed := maxi(roundi(dt / SimClock.TICK_DT * TIME_PER_TICK), 0)
	var damage := 0
	for i in ActorState.MAX_EFFECTS:
		var duration := p_state.effect_duration[i]
		if duration <= 0:
			continue
		var total := p_state.effect_total[i]
		var before := p_state.effect_elapsed[i]
		var after := mini(before + passed, duration)
		damage += _removed(total, duration, after) - _removed(total, duration, before)
		p_state.effect_elapsed[i] = after
		if after >= duration:
			p_state.effect_total[i] = 0
			p_state.effect_duration[i] = 0
			p_state.effect_elapsed[i] = 0
	if damage <= 0:
		return
	p_state.health = maxi(p_state.health - damage, 0)
	if p_state.health == 0:
		die(p_state, p_tuning)


## Muerte de prueba: sube el contador, apaga los estados, corta los daños en
## el tiempo y la salud vuelve al máximo.
static func die(p_state: ActorState, p_tuning: ActorTuning) -> void:
	p_state.deaths = (p_state.deaths + 1) & 0xFF
	ActorPowers.retire(p_state)
	p_state.effect_total.fill(0)
	p_state.effect_duration.fill(0)
	p_state.effect_elapsed.fill(0)
	p_state.health = max_health(p_tuning) * ActorState.HEALTH_UNIT


static func max_health(p_tuning: ActorTuning) -> int:
	return clampi(p_tuning.health_max, 1, 10000)


## Al aparecer: salud y reserva completas, con los máximos del Tuning.
static func fill(p_state: ActorState, p_tuning: ActorTuning) -> void:
	var vitals := of(p_state, p_tuning)
	p_state.health = vitals.health_max() * ActorState.HEALTH_UNIT
	p_state.stamina = vitals.stamina_max() * ActorPowers.STAMINA_UNIT
