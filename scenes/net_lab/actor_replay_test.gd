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
##
## Con --rate=N corre todo a N ticks por segundo real, y con --rate=varying va
## cambiando de ritmo cada pocos ticks, como el cliente al ajustar su adelanto.
## La huella final de la pasada en vivo tiene que dar igual a cualquier ritmo.

const TICK_DT := 1.0 / 60.0
const TIMEOUT_SECONDS := 400.0
## Ritmos que recorre --rate=varying, uno cada RATE_SWITCH_FRAMES frames de física.
const VARYING_RATES := [60, 72, 57, 66, 61, 69, 58, 64]
const RATE_SWITCH_FRAMES := 7
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
var _ticks_slide := 0
var _ticks_ladder := 0
var _ticks_hanging := 0
## Empujones del recorrido, por tick: [impulso, fuerza].
var _events := {}
var _ticks_crouched := 0
## Ticks agachado aunque pedía pararse: el techo no lo dejaba.
var _ticks_kept_crouched := 0
var _jumps := 0
var _max_height := 0.0
var _varying_rate := false
var _physics_frames := 0

@onready var _actor: ActorBody = $Actor


func _ready() -> void:
	SimClock.apply_tick_rate(SimClock.TICK_RATE)
	Engine.physics_jitter_fix = 0.0
	var rate_text := "60"
	for arg in OS.get_cmdline_user_args():
		if arg == "--rate=varying":
			_varying_rate = true
			rate_text = "variable %s" % str(VARYING_RATES)
		elif arg.begins_with("--rate="):
			SimClock.apply_tick_rate(arg.trim_prefix("--rate=").to_int())
			rate_text = str(Engine.physics_ticks_per_second)
	get_tree().create_timer(TIMEOUT_SECONDS, true, false, true).timeout.connect(_on_timeout)
	_build_inputs()
	_initial.position = _actor.global_position
	_initial.quantize()
	print("%s %d ticks de input, ritmo %s ticks por segundo" % [LOG_PREFIX, _inputs.size(), rate_text])


func _physics_process(_delta: float) -> void:
	if _varying_rate:
		_physics_frames += 1
		if _physics_frames % RATE_SWITCH_FRAMES == 0:
			@warning_ignore("integer_division")
			SimClock.apply_tick_rate(VARYING_RATES[(_physics_frames / RATE_SWITCH_FRAMES) % VARYING_RATES.size()])
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
	_apply_events(_state, _tick)
	ActorMotor.step(_actor, _state, _inputs[_tick], _tuning, TICK_DT)
	_live.append(_state.to_bytes())

	match _state.mode:
		ActorState.Mode.GROUND:
			_ticks_ground += 1
		ActorState.Mode.AIR:
			_ticks_air += 1
		ActorState.Mode.SLIDE:
			_ticks_slide += 1
		ActorState.Mode.LADDER:
			_ticks_ladder += 1
		ActorState.Mode.HANGING:
			_ticks_hanging += 1
	if _state.stance == ActorState.Stance.CROUCHED:
		_ticks_crouched += 1
		if _state.stance_wanted == ActorState.Stance.STANDING:
			_ticks_kept_crouched += 1
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
		_apply_events(state, t)
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
	print("%s cobertura: %d ticks en Suelo, %d en Aire, %d deslizándose, %d en escalera, %d colgado, %d tocando pared, %d saltos, altura máxima %.2f m" % [LOG_PREFIX, _ticks_ground, _ticks_air, _ticks_slide, _ticks_ladder, _ticks_hanging, _ticks_wall, _jumps, _max_height])
	print("%s postura: %d ticks agachado, %d de ellos pidiendo pararse sin lugar" % [LOG_PREFIX, _ticks_crouched, _ticks_kept_crouched])
	print("%s %d repeticiones, %d ticks repetidos" % [LOG_PREFIX, _replays, _replayed_ticks])
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for bytes in _live:
		hashing.update(bytes)
	print("%s huella de la pasada en vivo: %s" % [LOG_PREFIX, hashing.finish().hex_encode().left(16)])
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


## Recorrido guionado por el laboratorio: deslizamiento hasta frenar bajo el
## techo del túnel largo, salida agachado, cambios de postura en el aire,
## piso, escalón, pared, esquina, costado del túnel, rampa, caída desde la
## plataforma y su escalera (agarrarse, subir, salir arriba, volver a
## agarrarse, saltar, y dos empujones: uno débil y uno fuerte), y la pista de
## escalones (uno que no se sube y las dos escaleras, subiendo y bajando). Las
## posiciones son aproximadas; lo que importa es tocar cosas y que el
## resultado se repita.
func _build_inputs() -> void:
	var run := ActorInput.BUTTON_RUN
	var crouch := ActorInput.BUTTON_CROUCH
	var segments := [
		# [ticks, ejes (x derecha, y adelante), yaw de la mirada, ticks del tramo con pulsación de salto, botones]
		[30, Vector2.ZERO, 0.0, []],  # se asienta en el piso
		[20, Vector2(0, 1), PI, [], run],  # corre hacia el túnel largo
		[100, Vector2(0, 1), PI, [], run | crouch],  # se desliza adentro y frena agachado
		[60, Vector2(0, 1), PI, [], 0],  # suelta agacharse: el techo lo deja agachado
		[120, Vector2(0, 1), PI, [], 0],  # sale por la otra punta y se para solo
		[20, Vector2.ZERO, 0.0, [], 0],  # frena
		[10, Vector2.ZERO, 0.0, [0], 0],  # salta parado
		[10, Vector2.ZERO, 0.0, [], crouch],  # se agacha en el aire: suben los pies
		[50, Vector2.ZERO, 0.0, [], 0],  # se para en el aire, cae y aterriza
		[450, Vector2(0, 1), 0.0, [], crouch],  # vuelve agachado por adentro del túnel
		[10, Vector2.ZERO, 0.0, [], 0],  # se para afuera
		[150, Vector2(0, 1), 0.0, []],  # camina hasta el escalón de 25 cm, lo sube y baja del otro lado
		[50, Vector2(0, 1), 0.0, [0, 30]],  # salta y sigue
		[120, Vector2(0, 1), -PI / 2.0, []],  # gira a la derecha hasta la pared
		[140, Vector2(0, 1), -PI / 4.0, []],  # en diagonal contra la pared, hasta la esquina
		[90, Vector2(0, 1), PI / 2.0, [0, 25, 50, 75]],  # hacia la izquierda saltando, contra el túnel
		[150, Vector2(0, 1), PI, []],  # hacia atrás, rozando el costado del escalón
		[105, Vector2(0, 1), PI / 2.0, []],  # hacia la izquierda por el piso abierto, frente a la rampa
		[230, Vector2(0, 1), 0.0, [150, 165, 180]],  # sube la rampa, cae de la plataforma y salta al caer
		[40, Vector2.ZERO, 0.0, []],  # se queda quieto
		# Escalera de la cara sur de la plataforma verde, justo delante:
		[90, Vector2(0, 1), PI, [], 0],  # camina hacia ella, se agarra, sube y sale arriba
		[20, Vector2.ZERO, 0.0, [], 0],  # se queda arriba de la plataforma
		[45, Vector2(0, 1), 0.0, [], 0],  # se va por el borde, alejándose de la escalera, y cae
		[20, Vector2.ZERO, 0.0, [], 0],  # se queda en el piso
		[75, Vector2(0, 1), PI, [], 0],  # se vuelve a agarrar y sube un poco
		[30, Vector2.ZERO, PI, [], 0, [[5, Vector3(1, 4, -1), 2]]],  # quieto: un empujón débil lo sube por la escalera
		[60, Vector2.ZERO, PI, [], 0, [[10, Vector3(2, 3, -4), 4]]],  # un empujón fuerte lo saca y cae
		[80, Vector2(0.5, 0.86), PI, [], 0],  # vuelve en diagonal, se agarra y sube un poco
		[6, Vector2(0, 1), PI, [0], 0],  # salta de la escalera
		[40, Vector2(0, 1), PI, [], 0],  # empuja hacia ella con el bloqueo de reagarre puesto
		[30, Vector2.ZERO, 0.0, [], 0],  # se queda quieto
		# Pista de escalones, detrás de donde se aparece:
		[30, Vector2(0, 1), PI, [], 0],  # sale por arriba de la escalera a la plataforma
		[170, Vector2(0, 1), PI, [], 0],  # baja de la plataforma, baja la rampa y sigue
		[40, Vector2(0, 1), -PI / 2.0, [], 0],  # a la derecha, para pasar por el costado de la pared de medidas
		[100, Vector2(0, 1), PI, [], 0],  # hacia atrás, hasta delante de la pista
		[106, Vector2(0, 1), PI / 2.0, [], 0],  # a la izquierda, por delante de los escalones sueltos
		[60, Vector2(0, 1), PI, [], 0],  # contra el de 40 cm, que no se sube
		[14, Vector2(0, 1), 0.0, [], 0],  # se aleja
		[47, Vector2(0, 1), PI / 2.0, [], 0],  # a la izquierda, hasta la escalera sin rampa
		[58, Vector2(0, 1), PI, [], 0],  # la sube, escalón por escalón
		[20, Vector2.ZERO, 0.0, [], 0],  # se queda arriba
		[70, Vector2(0, 1), 0.0, [], 0],  # la baja: sin rampa, cae por encima de los escalones
		[39, Vector2(0, 1), PI / 2.0, [], 0],  # a la izquierda, hasta la escalera con rampa
		[82, Vector2(0, 1), PI, [], 0],  # la sube por la rampa
		[82, Vector2(0, 1), 0.0, [], 0],  # la baja por la rampa, siempre en Suelo
		[30, Vector2.ZERO, 0.0, [], 0],  # se queda quieto
		# Hanging, contra el bloque de 2,4 m de la pista de bordes (cara en x 17, z -10):
		[431, Vector2(0, 1), -PI / 2.0, [], 0],  # a la derecha, por detrás de donde se aparece
		[10, Vector2.ZERO, 0.0, [], 0],
		[193, Vector2(0, 1), 0.0, [], 0],  # hacia adelante, hasta 2,2 m de la cara
		[10, Vector2.ZERO, 0.0, [], 0],
		[12, Vector2(0, 1), 0.0, [10], 0],  # corre hacia la cara y salta
		[50, Vector2(0, 1), 0.0, [], 0],  # se agarra subiendo, cuando las manos llegan al filo
		[30, Vector2(1, 0), 0.0, [], 0],  # colgado, a la derecha
		[30, Vector2(-1, 0), 0.0, [], 0],  # colgado, a la izquierda
		[40, Vector2.ZERO, 0.0, [0], 0],  # Espacio mirando a la pared: salta derecho para arriba
		[18, Vector2(0, 1), 0.0, [], 0],  # en la punta del salto, W: aterriza arriba del borde
		[40, Vector2(0, 1), PI, [], 0],  # se va por delante y cae
		[30, Vector2.ZERO, 0.0, [], 0],
		[15, Vector2(0, 1), PI, [], 0],  # se aleja un poco
		[10, Vector2.ZERO, 0.0, [], 0],
		[12, Vector2(0, 1), 0.0, [10], 0],  # corre y salta otra vez
		[50, Vector2(0, 1), 0.0, [], 0],  # se agarra
		[5, Vector2.ZERO, 0.0, [], crouch],  # Ctrl: se suelta
		[40, Vector2.ZERO, 0.0, [], 0],
		[12, Vector2(0, 1), 0.0, [10], 0],  # salta pegado a la pared
		[50, Vector2(0, 1), 0.0, [], 0],  # se agarra
		[20, Vector2.ZERO, PI, [5], 0],  # Espacio mirando hacia atrás: salta lejos
		[40, Vector2.ZERO, 0.0, [], 0],  # se queda quieto
		[70, Vector2(0, 1), 0.0, [], 0],  # vuelve hasta la pared
		[10, Vector2.ZERO, 0.0, [], 0],
		[60, Vector2.ZERO, 0.0, [0], 0],  # salta sin teclas: se agarra igual al caer
		[20, Vector2(1, 0), -PI / 2.0, [], 0],  # D con la cámara mirando a la derecha: a la derecha
		[20, Vector2(-1, 0), -PI / 2.0, [], 0],  # A con la cámara igual: a la izquierda
		[5, Vector2.ZERO, 0.0, [], crouch],  # Ctrl: se suelta
		[40, Vector2.ZERO, 0.0, [], 0],  # se queda quieto
	]
	var presses := 0
	var tick := 0
	for segment in segments:
		var buttons: int = segment[4] if segment.size() > 4 else 0
		if segment.size() > 5:
			# Empujones del tramo: [tick dentro del tramo, impulso, fuerza].
			for event in segment[5]:
				_events[tick + event[0]] = [event[1], event[2]]
		for i in segment[0]:
			if i in segment[3]:
				presses += 1
			_inputs.append(ActorInput.make(tick, segment[1], segment[2], buttons, presses))
			tick += 1
		_segment_ends.append(tick - 1)


## Un empujón del recorrido, como lo aplica el host: antes del paso de su tick,
## subiendo la época. En vivo y al repetir, igual.
func _apply_events(state: ActorState, tick: int) -> void:
	var event: Variant = _events.get(tick)
	if event != null:
		ActorMotor.apply_impulse(state, event[0], event[1], _tuning)
		state.epoch += 1
