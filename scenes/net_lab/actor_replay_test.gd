extends Node3D

## Prueba del paso 2: el mismo input, repetido, da el mismo estado tick por tick.
##
## 1. Pasada en vivo: un tick por frame de física, como en el juego.
## 2. Repeticiones largas: desde algunos ticks intermedios se restaura el estado
##    guardado y se repite hasta el final dentro de un solo frame, como hará
##    la reconciliación.
## 3. Repeticiones cortas: lo mismo desde cada tick del recorrido, con una
##    ventana corta, para probar la restauración en todas las situaciones.
##
## Cada tick repetido tiene que coincidir byte a byte con la pasada en vivo.
## Sale con código 0 si todo coincide, 1 si algo difiere y 2 si no terminó a tiempo.

const TICK_DT := 1.0 / 60.0
const TIMEOUT_SECONDS := 150.0
const LONG_CHECKPOINTS := [0, 1, 2, 17, 60, 151, 152, 203, 333, 444, 555, 666, 777, 888, 955, 1050]
const SHORT_WINDOW := 30
const SHORT_BATCH := 40
const MAX_REPORTED_FAILURES := 5
const LOG_PREFIX := "[actor_replay_test]"

enum Phase { LIVE, LONG, SHORT, DONE }

var _tuning := ActorTuning.new()
var _inputs: Array[ActorInput] = []
## Último tick de cada tramo del recorrido, para informar dónde terminó.
var _segment_ends: Array[int] = []
var _live: Array[PackedByteArray] = []
var _initial := ActorState.new()
var _state: ActorState
var _phase := Phase.LIVE
var _tick := 0
var _long_index := 0
var _short_start := 0
var _replays := 0
var _replayed_ticks := 0
var _failure_count := 0
var _failures: Array[String] = []
# Cobertura de la pasada en vivo: confirma que el recorrido tocó cosas.
var _ticks_ground := 0
var _ticks_air := 0
var _ticks_wall := 0
var _jumps := 0
var _max_height := 0.0

@onready var _actor: ActorBody = $Actor


func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.physics_jitter_fix = 0.0
	get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_build_inputs()
	_initial.position = _actor.global_position
	_initial.quantize()
	print("%s %d ticks de input" % [LOG_PREFIX, _inputs.size()])


func _physics_process(_delta: float) -> void:
	match _phase:
		Phase.LIVE:
			_live_tick()
		Phase.LONG:
			_replay_next_long()
		Phase.SHORT:
			_replay_short_batch()


func _live_tick() -> void:
	if _tick == 0:
		_state = _initial.copy()
		_actor.apply_state(_state)
	var previous_vertical := _state.velocity.y
	ActorMotor.step(_actor, _state, _inputs[_tick], _tuning, TICK_DT)
	_live.append(_state.to_bytes())

	if _state.mode == ActorState.Mode.GROUND:
		_ticks_ground += 1
	else:
		_ticks_air += 1
	if _actor.is_on_wall():
		_ticks_wall += 1
	if previous_vertical <= 0.0 and _state.velocity.y > 1.0:
		_jumps += 1
	_max_height = maxf(_max_height, _state.position.y)
	if _tick in _segment_ends:
		print("%s tramo %d termina en %s" % [LOG_PREFIX, _segment_ends.find(_tick) + 1, _state.describe()])

	_tick += 1
	if _tick == _inputs.size():
		_phase = Phase.LONG


func _replay_next_long() -> void:
	if _long_index >= LONG_CHECKPOINTS.size():
		_phase = Phase.SHORT
		return
	var start: int = LONG_CHECKPOINTS[_long_index]
	_long_index += 1
	_replay(start, _inputs.size())


func _replay_short_batch() -> void:
	var end := mini(_short_start + SHORT_BATCH, _inputs.size())
	for start in range(_short_start, end):
		_replay(start, mini(start + SHORT_WINDOW, _inputs.size()))
	_short_start = end
	if _short_start >= _inputs.size():
		_finish()


## Restaura el estado previo a `start` y repite hasta `stop` dentro de este
## frame, comparando cada tick con la pasada en vivo. Corta en el primer desvío.
func _replay(start: int, stop: int) -> void:
	_replays += 1
	var state := _initial.copy() if start == 0 else ActorState.from_bytes(_live[start - 1])
	_actor.apply_state(state)
	for t in range(start, stop):
		ActorMotor.step(_actor, state, _inputs[t], _tuning, TICK_DT)
		_replayed_ticks += 1
		if state.to_bytes() != _live[t]:
			_failure_count += 1
			if _failures.size() < MAX_REPORTED_FAILURES:
				var expected := ActorState.from_bytes(_live[t])
				_failures.append("repitiendo desde el tick %d, difiere en el tick %d\n  en vivo:  %s\n  repetido: %s" % [start, t, expected.describe(), state.describe()])
			return


func _finish() -> void:
	_phase = Phase.DONE
	print("%s cobertura: %d ticks en Suelo, %d en Aire, %d tocando pared, %d saltos, altura máxima %.2f m" % [LOG_PREFIX, _ticks_ground, _ticks_air, _ticks_wall, _jumps, _max_height])
	print("%s %d repeticiones, %d ticks repetidos" % [LOG_PREFIX, _replays, _replayed_ticks])
	if _failure_count == 0:
		print("%s OK: todas las repeticiones coinciden byte a byte con la pasada en vivo" % LOG_PREFIX)
		get_tree().quit(0)
		return
	print("%s %d repeticiones con desvío; las primeras:" % [LOG_PREFIX, _failure_count])
	for failure in _failures:
		print("%s FALLA %s" % [LOG_PREFIX, failure])
	get_tree().quit(1)


func _on_timeout() -> void:
	if _phase == Phase.DONE:
		return
	print("%s TIMEOUT: no terminó en %d s (fase %s, tick %d)" % [LOG_PREFIX, TIMEOUT_SECONDS, Phase.keys()[_phase], _tick])
	get_tree().quit(2)


## Recorrido guionado por el laboratorio: piso, escalón, pared, esquina, costado
## del túnel, rampa y caída desde la plataforma. Las posiciones son aproximadas;
## lo que importa es tocar cosas y que el resultado se repita.
func _build_inputs() -> void:
	var segments := [
		# [ticks, ejes (x derecha, y adelante), yaw de la mirada, ticks del tramo con pulsación de salto]
		[30, Vector2.ZERO, 0.0, []],  # se asienta en el piso
		[150, Vector2(0, 1), 0.0, []],  # camina hasta el escalón y lo empuja
		[50, Vector2(0, 1), 0.0, [0, 30]],  # salta al escalón y sigue
		[120, Vector2(0, 1), -PI / 2.0, []],  # gira a la derecha hasta la pared
		[140, Vector2(0, 1), -PI / 4.0, []],  # en diagonal contra la pared, hasta la esquina
		[90, Vector2(0, 1), PI / 2.0, [0, 25, 50, 75]],  # hacia la izquierda saltando, contra el túnel
		[150, Vector2(0, 1), PI, []],  # hacia atrás, rozando el costado del escalón
		[105, Vector2(0, 1), PI / 2.0, []],  # hacia la izquierda por el piso abierto, frente a la rampa
		[230, Vector2(0, 1), 0.0, [150, 165, 180]],  # sube la rampa, cae de la plataforma y salta al caer
		[40, Vector2.ZERO, 0.0, []],  # se queda quieto
	]
	var presses := 0
	var tick := 0
	for segment in segments:
		for i in segment[0]:
			if i in segment[3]:
				presses += 1
			_inputs.append(ActorInput.make(tick, segment[1], segment[2], 0, presses))
			tick += 1
		_segment_ends.append(tick - 1)
