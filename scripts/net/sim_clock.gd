class_name SimClock
extends Node

## Reloj único de la simulación. Cuenta los ticks y llama a cada actor simulado
## en un orden fijo (por id de dueño), así ninguna regla depende del orden de
## los nodos en la escena. Los actores no tienen _physics_process propio.
##
## En el cliente, además, mantiene el adelanto sobre el host (paso 6): el
## cliente corre unos ticks por delante para que su input llegue antes de que
## el host simule ese tick. El ping da la estimación inicial, usando el más
## rápido de los últimos, que es el que menos se equivoca. Después, el host
## informa con cuánto margen le llegan los inputs y el cliente cambia de ritmo:
## corre un poco más rápido o más lento que el host hasta volver a la franja
## buscada. Cada tick sigue avanzando exactamente TICK_DT; solo cambia cuántos
## ticks entran en un segundo real.

## Al empezar cada tick, antes de mover actores. El cliente corrige y manda su input acá.
signal tick_started(tick: int)
## Al terminar cada tick, con los actores ya movidos. El host manda el snapshot acá.
signal tick_finished(tick: int)
## El cliente saltó a otro tick: al sincronizar por primera vez o tras un tirón grande.
signal hard_resynced

const TICK_RATE := 60
const TICK_DT := 1.0 / TICK_RATE
const TICK_USEC := 1_000_000.0 / TICK_RATE
## Cada cuántos ticks el cliente vuelve a medir el reloj del host.
const SYNC_INTERVAL_TICKS := 30
## Pings que se recuerdan para elegir el más rápido.
const PING_WINDOW := 8
## Adelanto extra, además del medio ida y vuelta, al sincronizar.
const LEAD_EXTRA_TICKS := 2
## Franja del margen con que deben llegar los inputs al host, en ticks, mirando
## el peor caso reciente. Con menos de MARGIN_LOW el cliente acelera hasta
## llegar a MARGIN_TARGET; con más de MARGIN_HIGH frena hasta bajar a
## MARGIN_SETTLE. En el medio no toca nada: la variación normal de la red no lo mueve.
const MARGIN_LOW := 1.0
const MARGIN_TARGET := 2.0
const MARGIN_SETTLE := 3.0
const MARGIN_HIGH := 6.0
## Cuántos ticks del host se miran para buscar el peor margen.
const MARGIN_WINDOW_TICKS := 60
## Ticks por segundo de más por cada tick de margen que falta: lo que falta se
## recupera en alrededor de medio segundo.
const SPEEDUP_PER_MISSING_TICK := 2.0
## Ritmos límite. A 72 ticks por segundo gana 12 ticks de adelanto por segundo;
## a 57 pierde 3. Perder adelanto no apura, así que frena más suave.
const MAX_RATE := 72
const MIN_RATE := 57
## Cuántos ticks se recuerda el ajuste acumulado, para saber cuánto valía al
## mandar cada input.
const ADJUST_HISTORY_TICKS := 1024

## Lo activa la sesión cuando el cliente queda conectado.
var client_sync := false
var actors_root: Node
var tuning: ActorTuning
## Devuelve el input de un actor para un tick:
## func(actor: ActorBody, tick: int) -> ActorInput
var input_provider: Callable
## Simulador de red (paso 5): el ping pasa por acá, así la medición incluye la demora simulada.
var link: LinkSimulator

var tick := 0
## Cliente: ya tiene una estimación del tick del host.
var synced := false
## Cliente: ida y vuelta del ping más rápido reciente.
var rtt_ms := 0.0
## Cliente: cuántos ticks va por delante del host, según ese ping.
var lead_ticks := 0.0
## Cliente: el peor margen reciente con que le llegaron inputs al host, sumando
## lo que el cliente ya se corrió desde que los mandó.
var worst_margin := 0.0
## Cliente: ticks por segundo real a los que corre ahora. El host siempre va a TICK_RATE.
var rate_hz := TICK_RATE
## Cliente: adelanto ganado acelerando y perdido frenando, en ticks.
var ticks_gained := 0.0
var ticks_shed := 0.0
## Cliente: saltos de tick después de la primera sincronización.
var resyncs := 0

var _ticks_since_ping := 0
## Pings recientes: [ida y vuelta en µs, adelanto medido al recibirlo, ajustes hechos hasta ese momento].
var _pings: Array = []
## Ticks que el cliente se corrió por su cuenta: lo que ganó o perdió cambiando
## de ritmo y lo que saltó de golpe. Así una medición vieja sigue sirviendo:
## el adelanto de hoy es el que midió más los ajustes hechos desde entonces.
var _adjust_total := 0.0
## _adjust_total al empezar cada tick reciente, guardado por tick en un anillo.
var _adjust_history := PackedFloat64Array()
var _adjust_history_tick := PackedInt64Array()
## Pings seguidos que pidieron un salto; hace falta más de uno para saltar.
var _bad_estimates := 0
## Márgenes recientes: [tick del host, margen, _adjust_total al mandar ese input].
var _margins: Array = []


## Cambia cuántos ticks entran en un segundo real. time_scale compensa para
## que el delta de física siga siendo exactamente TICK_DT: la simulación da
## lo mismo, byte a byte, a cualquier ritmo.
static func apply_tick_rate(rate: int) -> void:
	Engine.physics_ticks_per_second = rate
	Engine.time_scale = float(rate) / TICK_RATE


func _ready() -> void:
	_adjust_history.resize(ADJUST_HISTORY_TICKS)
	_adjust_history_tick.resize(ADJUST_HISTORY_TICKS)
	_adjust_history_tick.fill(-1)


func _exit_tree() -> void:
	_set_rate(TICK_RATE)


func _physics_process(_delta: float) -> void:
	_run_tick()
	if client_sync and synced:
		_update_rate()
	else:
		_set_rate(TICK_RATE)
	if client_sync:
		_ticks_since_ping += 1
		if _ticks_since_ping >= SYNC_INTERVAL_TICKS:
			_ticks_since_ping = 0
			var sent_usec := Time.get_ticks_usec()
			_through_link(func() -> void:
				if client_sync:
					_ping.rpc_id(1, sent_usec)
			)


func _run_tick() -> void:
	tick += 1
	if client_sync and synced:
		# Este tick duró 1/rate_hz segundos reales, y en ese tiempo el host
		# avanzó TICK_RATE/rate_hz ticks: la diferencia es adelanto ganado o perdido.
		var change := 1.0 - float(TICK_RATE) / rate_hz
		_adjust_total += change
		ticks_gained += maxf(change, 0.0)
		ticks_shed += maxf(-change, 0.0)
		var slot := posmod(tick, ADJUST_HISTORY_TICKS)
		_adjust_history[slot] = _adjust_total
		_adjust_history_tick[slot] = tick
	tick_started.emit(tick)
	for actor in sorted_actors():
		if not actor.simulated:
			continue
		if not actor.placed:
			actor.apply_state(actor.state)
			actor.reset_physics_interpolation()
			actor.placed = true
		ActorMotor.step(actor, actor.state, input_provider.call(actor, tick), tuning, TICK_DT)
		actor.present(actor.state)
		actor.decay_visual_offset(TICK_DT)
	tick_finished.emit(tick)


func sorted_actors() -> Array[ActorBody]:
	var list: Array[ActorBody] = []
	if actors_root == null:
		return list
	for child in actors_root.get_children():
		if child is ActorBody:
			list.append(child)
	list.sort_custom(func(a: ActorBody, b: ActorBody) -> bool: return a.owner_peer_id < b.owner_peer_id)
	return list


## Cliente: el host informó que, al simular host_tick, ya tenía nuestro input
## hasta host_tick + margin.
func report_input_margin(host_tick: int, margin: int) -> void:
	var input_tick := host_tick + margin
	var slot := posmod(input_tick, ADJUST_HISTORY_TICKS)
	var adjust_when_sent := _adjust_history[slot] if _adjust_history_tick[slot] == input_tick else _adjust_total
	_margins.append([host_tick, margin, adjust_when_sent])
	while _margins[0][0] <= host_tick - MARGIN_WINDOW_TICKS:
		_margins.pop_front()


## Elige el ritmo según el peor margen reciente. Acelera más cuanto más falta,
## y deja de acelerar apenas lo ganado alcanza, sin esperar el ida y vuelta
## que tarda el host en confirmarlo.
func _update_rate() -> void:
	if _margins.is_empty() or _margins[-1][0] - _margins[0][0] < MARGIN_WINDOW_TICKS / 2:
		_set_rate(TICK_RATE)
		return
	worst_margin = _worst_margin()
	var rate := TICK_RATE
	if worst_margin < MARGIN_LOW or (rate_hz > TICK_RATE and worst_margin < MARGIN_TARGET):
		rate = mini(TICK_RATE + ceili((MARGIN_TARGET - worst_margin) * SPEEDUP_PER_MISSING_TICK), MAX_RATE)
	elif worst_margin > MARGIN_HIGH or (rate_hz < TICK_RATE and worst_margin > MARGIN_SETTLE):
		rate = maxi(TICK_RATE - ceili(worst_margin - MARGIN_SETTLE), MIN_RATE)
	_set_rate(rate)


## El peor margen de la ventana, sumándole a cada uno lo que el cliente ganó o
## perdió desde que mandó ese input: el host todavía no lo vio, pero va a llegar.
func _worst_margin() -> float:
	var worst := INF
	for sample in _margins:
		worst = minf(worst, sample[1] - sample[2])
	return worst + _adjust_total


func _set_rate(rate: int) -> void:
	if rate != rate_hz:
		rate_hz = rate
		apply_tick_rate(rate)


@rpc("any_peer", "call_remote", "unreliable")
func _ping(client_usec: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# El tick se lee cuando el ping se procesa de verdad, después de la demora simulada.
	_through_link(func() -> void:
		if sender in multiplayer.get_peers():
			_pong.rpc_id(sender, client_usec, tick)
	)


@rpc("authority", "call_remote", "unreliable")
func _pong(client_usec: int, host_tick: int) -> void:
	_through_link(_accept_pong.bind(client_usec, host_tick))


func _accept_pong(client_usec: int, host_tick: int) -> void:
	var rtt_usec := Time.get_ticks_usec() - client_usec
	# Al llegar el pong, el host ya avanzó medio viaje desde que lo mandó.
	var lead_now := tick - (host_tick + rtt_usec / 2.0 / TICK_USEC)
	_pings.append([rtt_usec, lead_now, _adjust_total])
	if _pings.size() > PING_WINDOW:
		_pings.pop_front()
	# El ping más rápido es el más confiable: su ida y su vuelta no pueden
	# haber sido muy distintas. Un pico del Wi-Fi solo hace más lento a uno.
	var best: Array = _pings[0]
	for sample in _pings:
		if sample[0] < best[0]:
			best = sample
	rtt_ms = best[0] / 1000.0
	lead_ticks = best[1] + (_adjust_total - best[2])
	var target: float = best[0] / 2.0 / TICK_USEC + LEAD_EXTRA_TICKS
	# Solo se salta al conectarse o si el adelanto quedó muy lejos dos pings
	# seguidos (un tirón grande de alguna máquina). El resto lo corrigen los márgenes.
	var far := lead_ticks < -2.0 or lead_ticks > target + 60.0
	_bad_estimates = _bad_estimates + 1 if far else 0
	if synced and _bad_estimates < 2:
		return
	var jump := ceili(target - lead_ticks)
	tick += jump
	_adjust_total += jump
	lead_ticks += jump
	_bad_estimates = 0
	if synced:
		resyncs += 1
	synced = true
	_margins.clear()
	hard_resynced.emit()


func _through_link(packet: Callable) -> void:
	if link != null:
		link.deliver(packet)
	else:
		packet.call()
