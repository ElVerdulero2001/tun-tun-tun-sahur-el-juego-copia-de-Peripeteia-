class_name LinkSimulator
extends Node

## Simulador de red del paso 5: demora, variación y pérdida de paquetes dentro
## de nuestra propia capa. Se activa en una sola máquina y afecta todo lo que
## esa máquina manda y recibe, así una LAN se comporta como internet.
##
## Tiene su propio generador aleatorio con semilla: la misma configuración da
## las mismas pérdidas, y la simulación del juego no se entera de que existe.

## Ida y vuelta que se agrega, en milisegundos. Cada sentido demora la mitad.
var added_rtt_ms := 0.0
## Cuánto puede variar la demora de cada paquete, hacia arriba o hacia abajo.
var jitter_ms := 0.0
## Porcentaje de paquetes que se pierden en cada sentido.
var loss_percent := 0.0
## Tirones, como un Wi-Fi que se traba: cada stall_every_ms la conexión se
## traba durante stall_ms, y lo que sale o llega en ese rato pasa todo junto
## cuando se destraba.
var stall_every_ms := 0.0
var stall_ms := 0.0
var delivered := 0
var dropped := 0

var _rng := RandomNumberGenerator.new()
var _queue: Array = []  # [momento de entrega en µs, Callable]


func configure(rtt_ms: float, jitter: float, loss: float, seed_value: int = 1, stall_every: float = 0.0, stall: float = 0.0) -> void:
	added_rtt_ms = maxf(rtt_ms, 0.0)
	jitter_ms = maxf(jitter, 0.0)
	loss_percent = clampf(loss, 0.0, 100.0)
	stall_every_ms = maxf(stall_every, 0.0)
	stall_ms = clampf(stall, 0.0, stall_every_ms)
	_rng.seed = seed_value


func is_active() -> bool:
	return added_rtt_ms > 0.0 or jitter_ms > 0.0 or loss_percent > 0.0 or stall_ms > 0.0


## Entrega un paquete (una llamada) ahora, más tarde o nunca.
func deliver(packet: Callable) -> void:
	if not is_active():
		delivered += 1
		packet.call()
		return
	if _rng.randf() * 100.0 < loss_percent:
		dropped += 1
		return
	_enqueue(packet)


## Como deliver(), para lo que viaja confiable: se demora pero nunca se pierde.
func deliver_reliable(packet: Callable) -> void:
	if not is_active():
		delivered += 1
		packet.call()
		return
	_enqueue(packet)


func _enqueue(packet: Callable) -> void:
	var delay_ms := maxf(added_rtt_ms / 2.0 + _rng.randf_range(-jitter_ms, jitter_ms), 0.0) + _stall_left_ms()
	_queue.append([Time.get_ticks_usec() + int(delay_ms * 1000.0), packet])


## Si la conexión está trabada, cuánto falta para que se destrabe.
func _stall_left_ms() -> float:
	if stall_ms <= 0.0:
		return 0.0
	var phase := fmod(Time.get_ticks_msec(), stall_every_ms)
	return stall_ms - phase if phase < stall_ms else 0.0


## Descarta lo que estaba en viaje, por ejemplo al terminar la sesión.
func clear() -> void:
	_queue.clear()


func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	var now := Time.get_ticks_usec()
	var due: Array = []
	var waiting: Array = []
	for item in _queue:
		if item[0] <= now:
			due.append(item)
		else:
			waiting.append(item)
	_queue = waiting
	# Con variación, dos paquetes pueden llegar al revés de como salieron, igual que en internet.
	due.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for item in due:
		delivered += 1
		item[1].call()
