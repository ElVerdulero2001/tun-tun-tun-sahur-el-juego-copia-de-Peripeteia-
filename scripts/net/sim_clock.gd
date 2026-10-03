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
## informa con cuánto margen le llegan los inputs y el cliente se corrige de a
## un tick, corriendo dos ticks en un frame o ninguno, sin saltar.

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
## Con cuánto margen deben llegar los inputs al host, mirando el peor caso reciente.
const MARGIN_MIN_TICKS := 1
const MARGIN_MAX_TICKS := 4
## Cuántos márgenes informados por el host se miran antes de decidir.
const MARGIN_WINDOW := 60

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
## Cliente: el peor margen con que le llegaron inputs al host en la ventana actual.
var worst_margin := 0
## Cliente: ajustes de un tick hacia adelante y hacia atrás.
var speedups := 0
var slowdowns := 0
## Cliente: saltos de tick después de la primera sincronización.
var resyncs := 0

var _ticks_since_ping := 0
## Pings recientes: [ida y vuelta en µs, adelanto medido al recibirlo, ajustes hechos hasta ese momento].
var _pings: Array = []
## Ticks que el cliente se corrió por su cuenta: +1 por cada tick extra, -1 por
## cada tick salteado y lo que salte de golpe. Así un ping viejo sigue sirviendo:
## el adelanto de hoy es el que midió más los ajustes hechos desde entonces.
var _adjust_total := 0
## Pings seguidos que pidieron un salto; hace falta más de uno para saltar.
var _bad_estimates := 0
var _margins: Array[int] = []
var _adjust_cooldown := 0


func _physics_process(_delta: float) -> void:
	var steps := _lead_adjust_steps() if synced else 1
	for i in steps:
		_run_tick()
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


## Cliente: el host informó con cuántos ticks de margen le llegó nuestro input.
func report_input_margin(margin: int) -> void:
	_margins.append(margin)
	if _margins.size() > MARGIN_WINDOW:
		_margins.pop_front()
	worst_margin = _margins.min()


## Cuántos ticks correr en este frame: 1 normalmente, 2 para adelantarse un
## tick, 0 para atrasarse uno. Después de cada ajuste espera a ver su efecto,
## que tarda un ida y vuelta en volver en los márgenes.
func _lead_adjust_steps() -> int:
	if _adjust_cooldown > 0:
		_adjust_cooldown -= 1
		return 1
	if _margins.size() < MARGIN_WINDOW / 2:
		return 1
	var steps := 1
	if worst_margin < MARGIN_MIN_TICKS:
		speedups += 1
		_adjust_total += 1
		steps = 2
	elif worst_margin > MARGIN_MAX_TICKS:
		slowdowns += 1
		_adjust_total -= 1
		steps = 0
	else:
		return 1
	_margins.clear()
	_adjust_cooldown = maxi(30, roundi(rtt_ms / 1000.0 * TICK_RATE) * 2)
	return steps


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
