extends Node3D

## Prueba del mantle, sin red, con el motor real y los valores del nodo Tuning
## de net_lab.tscn. Un carril por caso, cada uno con su obstáculo, armado acá
## (no usa el nivel): el actor salta, o hace lo que pide el caso, y al final se
## compara con lo que tiene que pasar según lo que decidió el usuario (sección
## 8.33 del historial):
##
## - si entra al mantle o no;
## - dónde termina: arriba del bloque, colgado, abajo o en la escalera;
## - el mantle que tiene que terminar arriba, termina en Suelo, parado o
##   agachado según el caso, en menos de MAX_MANTLE_SECONDS, y con teclas de
##   costado, corrido hacia ese lado;
## - el que se corta (Ctrl o un empujón fuerte a mitad de camino) sale del
##   mantle y no termina arriba.
##
## Además, como el host al adoptar, cada pose del mantle la tiene que aceptar
## anchored_pose_valid, y cada tick del mantle (y el que lo termina), repetido
## desde el estado anterior, tiene que dar los mismos bytes.
##
## Nació del diagnóstico temporal diag_mantle.gd del 2026-10-25 (Apéndice B del
## historial), que solo imprimía; desde el 2026-10-30 es una prueba fija, a
## pedido del usuario, después de la auditoría de GPT. Los resultados
## esperados dependen del Tuning: si se cambia la franja del mantle o la altura
## del salto, algunos casos pueden dejar de dar lo de acá, y la prueba lo dice.
##
## Sale con 0 si todos los casos dan lo esperado, 1 si alguno no y 2 si no
## terminó a tiempo. Con --traza=<comienzo del nombre> imprime ese caso tick a
## tick.

const LANE := 8.0
const FACE_Z := -1.0
const DT := 1.0 / 60.0
const TIMEOUT_SECONDS := 300.0
## Un mantle de 1,9 m tarda unos 0,7 s; más de esto es que algo lo traba.
const MAX_MANTLE_SECONDS := 1.0
## Con teclas de costado, cuánto se tiene que correr hacia ese lado, en metros.
const MIN_SIDE_SHIFT := 0.1
## Para cortar el mantle: cuántos ticks después de empezar.
const CUT_AFTER_TICKS := 5
## Fondo de los bloques de los casos que siguen con W o corriendo después de
## subir: así terminan arriba y no del otro lado.
const DEEP := 25.0
const LOG_PREFIX := "[mantle_test]"

var _tuning := ActorTuning.from_scene()
var _cases: Array[Dictionary] = []
var _index := -1
var _t := 0
var _tick := 0
var _presses := 0
var _state: ActorState
var _case: Dictionary
var _wait := 5
var _trace := ""
var _jumped_once := false
var _hang_jumped := false
var _started_msec := 0
# Por caso.
var _modes: Array[String] = []
var _befores: Array[PackedByteArray] = []
var _afters: Array[PackedByteArray] = []
var _inputs: Array[ActorInput] = []
var _mantle_from := -1
var _mantle_until := -1
var _mantle_stance := -1
var _mantle_feet := Vector3.ZERO
## Dónde quedan los pies en el tick en que sale del mantle, en el carril.
var _mantle_end := Vector3.ZERO
var _mode_after_mantle := -1
var _invalid := 0
var _failed: Array[String] = []

@onready var _actor: ActorBody = $Actor


func _ready() -> void:
	add_child(_tuning)
	SimClock.apply_tick_rate(SimClock.TICK_RATE)
	_started_msec = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--traza="):
			_trace = arg.trim_prefix("--traza=")
	_add_cases()
	_add_box(Vector3(_cases.size() * LANE + 100.0, 1, 60), Vector3(_cases.size() * LANE * 0.5, -0.5, 0))
	for i in _cases.size():
		var offset := Vector3(i * LANE, 0, 0)
		for b: Array in _cases[i]["blocks"]:
			_add_box(b[0], b[1] + offset)
		if _cases[i].has("ladder"):
			var ladder := Ladder.new()
			ladder.height = _cases[i]["ladder"]
			ladder.position = Vector3(0, 0, FACE_Z + 0.05) + offset
			add_child(ladder)
	print("%s %d casos" % [LOG_PREFIX, _cases.size()])


## Cada caso: nombre, bloques ([tamaño, centro]), alto del filo (h) y qué tiene
## que pasar: "mantle" (si entra) y "end" (arriba, colgado, abajo o escalera);
## "stance" si el mantle tiene que ir agachado, "side" si tiene que correrse de
## costado (1 hacia +x, -1 hacia -x) y "cut" si se corta a mitad de camino.
## Lo demás es el input: "jump_at" (ticks con Espacio), "move" entre
## "move_from" y "move_until", "look" (yaw de la cámara), "run", "crouch"
## ([desde, hasta]), "jump_when_z", "start", "air", "jumped", "boost", etc.
func _add_cases() -> void:
	# Saltando parado y caminando, de 0,6 a 2,2 m: debajo de 1,2 el salto pasa
	# el filo solo; de 1,2 a 1,9, mantle; desde 2,0, colgado (2,0 caminando, justo).
	var heights := [0.6, 1.0, 1.2, 1.4, 1.6, 1.8, 1.9, 2.0, 2.2]
	for h: float in heights:
		var want := "nada" if h < 1.1 else "mantle" if h < 1.95 else "colgado"
		_cases.append({"name": "salto en el lugar, %.1f m" % h, "blocks": [_block(h)], "jump_at": [10], "ticks": 150, "h": h,
				"mantle": want == "mantle", "end": "arriba" if want == "mantle" else "colgado" if want == "colgado" else "abajo"})
	for h: float in heights:
		var want := "nada" if h < 1.1 else "mantle" if h < 1.95 else "colgado"
		_cases.append({"name": "salto con W, %.1f m" % h, "blocks": [_block(h, DEEP)], "jump_at": [10], "move": Vector2(0, 1), "move_from": 10,
				"ticks": 150, "h": h, "mantle": want == "mantle", "end": "colgado" if want == "colgado" else "arriba"})
	# Sin piso arriba (muro finito, ventana, baranda): sin mantle, choca. De
	# un filo de 1,5 m no se cuelga desde el piso: los pies quedarían debajo.
	_cases.append({"name": "muro finito 1,5 m x 0,2", "blocks": [[Vector3(3, 1.5, 0.2), Vector3(0, 0.75, FACE_Z - 0.1)]],
			"jump_at": [10], "ticks": 150, "h": 1.5, "mantle": false, "end": "abajo"})
	# Arriba solo cabe agachado: sube agachado.
	_cases.append({"name": "techo bajo: repisa 1,6, techo a 3,0", "blocks": [_block(1.6), [Vector3(3, 0.2, 3), Vector3(0, 3.1, FACE_Z - 1.5)]],
			"jump_at": [10], "ticks": 150, "h": 1.6, "mantle": true, "end": "arriba", "stance": ActorState.Stance.CROUCHED})
	_cases.append({"name": "ventana 1,8 a 3,1 en muro de 0,4", "blocks": [[Vector3(3, 1.8, 0.4), Vector3(0, 0.9, FACE_Z - 0.2)],
			[Vector3(3, 0.5, 0.4), Vector3(0, 3.35, FACE_Z - 0.2)]], "jump_at": [10], "ticks": 180, "h": 1.8, "mantle": false, "end": "abajo"})
	# Desde el colgado, el salto para arriba: sin W vuelve a colgarse (cayendo
	# nunca hay mantle); con W en la punta, sube con el salto, no con el mantle.
	_cases.append({"name": "colgado de 2,4 m, salto para arriba sin W", "blocks": [_block(2.4)], "start": Vector3(0, 0, FACE_Z + 0.36),
			"jump_at": [10], "hang_jump_at": 80, "ticks": 220, "h": 2.4, "mantle": false, "end": "colgado"})
	_cases.append({"name": "colgado de 2,4 m, salto para arriba con W en la punta", "blocks": [_block(2.4, DEEP)], "start": Vector3(0, 0, FACE_Z + 0.36),
			"jump_at": [10], "hang_jump_at": 80, "w_at_top": true, "ticks": 220, "h": 2.4, "mantle": false, "end": "arriba"})
	# Sin haber saltado (bajando de espaldas), sin mantle: desde 1,5 m, al piso;
	# desde 3,0, colgado.
	_cases.append({"name": "de espaldas desde una plataforma de 1,5, mirándola", "blocks": [[Vector3(3, 1.5, 4), Vector3(0, 0.75, FACE_Z - 2)]],
			"start": Vector3(0, 1.5, FACE_Z - 0.3), "move": Vector2(0, -1), "move_from": 10, "move_until": 40, "ticks": 150, "h": 1.5,
			"mantle": false, "end": "abajo"})
	_cases.append({"name": "de espaldas, un paso, desde 1,5, mirándola", "blocks": [[Vector3(3, 1.5, 4), Vector3(0, 0.75, FACE_Z - 2)]],
			"start": Vector3(0, 1.5, FACE_Z - 0.1), "move": Vector2(0, -1), "move_from": 10, "move_until": 16, "ticks": 150, "h": 1.5,
			"mantle": false, "end": "abajo"})
	_cases.append({"name": "de espaldas, un paso, desde 3,0, mirándola", "blocks": [[Vector3(3, 3.0, 4), Vector3(0, 1.5, FACE_Z - 2)]],
			"start": Vector3(0, 3.0, FACE_Z - 0.1), "move": Vector2(0, -1), "move_from": 10, "move_until": 16, "ticks": 150, "h": 3.0,
			"mantle": false, "end": "colgado"})
	_cases.append({"name": "salto en el lugar a 0,6 de la cara, 1,6 m", "blocks": [_block(1.6)], "start": Vector3(0, 0, FACE_Z + 0.6),
			"jump_at": [10], "ticks": 150, "h": 1.6, "mantle": true, "end": "arriba"})
	_cases.append({"name": "salto en el lugar a 0,6 de la cara, 0,6 m", "blocks": [_block(0.6)], "start": Vector3(0, 0, FACE_Z + 0.6),
			"jump_at": [10], "ticks": 150, "h": 0.6, "mantle": false, "end": "abajo"})
	_cases.append({"name": "baranda de 1 m x 6 cm, salto en el lugar", "blocks": [[Vector3(3, 1.0, 0.06), Vector3(0, 0.5, FACE_Z - 0.03)]],
			"jump_at": [10], "ticks": 150, "h": 1.0, "thin": 0.06, "mantle": false, "end": "abajo"})
	_cases.append({"name": "baranda de 1 m x 6 cm, caminando y saltando", "blocks": [[Vector3(3, 1.0, 0.06), Vector3(0, 0.5, FACE_Z - 0.03)]],
			"start": Vector3(0, 0, FACE_Z + 3), "move": Vector2(0, 1), "move_until": 40, "jump_when_z": FACE_Z + 1.3, "ticks": 150, "h": 1.0,
			"thin": 0.06, "mantle": false, "end": "abajo"})
	# Con teclas: hacia donde apuntan según la cámara, hasta 45° de costado.
	_cases.append({"name": "diagonal 30°, W, 1,6 m", "blocks": [_block(1.6)], "start": Vector3(0, 0, FACE_Z + 0.5), "jump_at": [10],
			"look": deg_to_rad(30.0), "move": Vector2(0, 1), "move_from": 10, "move_until": 60, "ticks": 150, "h": 1.6,
			"mantle": true, "end": "arriba", "side": -1})
	_cases.append({"name": "diagonal 50°, W, 1,6 m", "blocks": [_block(1.6)], "start": Vector3(0, 0, FACE_Z + 0.5), "jump_at": [10],
			"look": deg_to_rad(50.0), "move": Vector2(0, 1), "move_from": 10, "move_until": 60, "ticks": 150, "h": 1.6,
			"mantle": true, "end": "arriba", "side": -1})
	_cases.append({"name": "de frente, solo D, 1,6 m", "blocks": [_block(1.6, 3.0, 6.0)], "start": Vector3(0, 0, FACE_Z + 0.5), "jump_at": [10],
			"move": Vector2(1, 0), "move_from": 30, "move_until": 60, "ticks": 150, "h": 1.6, "mantle": true, "end": "arriba", "side": 1})
	_cases.append({"name": "de frente, W, 1,6 m", "blocks": [_block(1.6)], "start": Vector3(0, 0, FACE_Z + 0.5), "jump_at": [10],
			"move": Vector2(0, 1), "move_from": 30, "move_until": 60, "ticks": 150, "h": 1.6, "mantle": true, "end": "arriba"})
	_cases.append({"name": "bloque de 2 m x 1 m de fondo, caminando, D en el mantle", "blocks": [[Vector3(2.4, 2.0, 1.0), Vector3(0, 1.0, FACE_Z - 0.5)]],
			"start": Vector3(0, 0, FACE_Z + 2.2), "move": Vector2(0, 1), "jump_when_z": FACE_Z + 1.3, "until_mantle": true, "d_in_mantle": true,
			"ticks": 150, "h": 2.0, "mantle": true, "end": "arriba", "side": 1})
	# Con Ctrl o mirando de costado, sin mantle.
	_cases.append({"name": "con Ctrl, 1,6 m", "blocks": [_block(1.6)], "jump_at": [10], "crouch": [5, 90], "ticks": 150, "h": 1.6,
			"mantle": false, "end": "abajo"})
	_cases.append({"name": "mirando de costado, 1,6 m", "blocks": [_block(1.6)], "jump_at": [10], "look": PI * 0.5, "ticks": 150, "h": 1.6,
			"mantle": false, "end": "abajo"})
	_cases.append({"name": "corriendo y saltando, 1,6 m", "blocks": [_block(1.6, DEEP)], "start": Vector3(0, 0, FACE_Z + 6), "move": Vector2(0, 1),
			"run": true, "jump_when_z": FACE_Z + 1.5, "ticks": 150, "h": 1.6, "mantle": true, "end": "arriba"})
	_cases.append({"name": "corriendo y saltando, 1,0 m (el salto alcanza)", "blocks": [_block(1.0, DEEP)], "start": Vector3(0, 0, FACE_Z + 6),
			"move": Vector2(0, 1), "run": true, "jump_when_z": FACE_Z + 1.5, "ticks": 150, "h": 1.0, "mantle": false, "end": "arriba"})
	# En el aire: subiendo después de saltar, sí; sin haber saltado o cayendo, no
	# (se cuelga como siempre).
	_cases.append({"name": "en el aire, filo 1,3 sobre los pies", "blocks": [_block(4.0)], "start": Vector3(0, 2.7, FACE_Z + 0.6), "air": true,
			"jumped": true, "ticks": 150, "h": 4.0, "mantle": false, "end": "colgado"})
	_cases.append({"name": "en el aire sin haber saltado, filo 1,3", "blocks": [_block(4.0)], "start": Vector3(0, 2.7, FACE_Z + 0.6), "air": true,
			"ticks": 150, "h": 4.0, "mantle": false, "end": "colgado"})
	_cases.append({"name": "en el aire, filo 1,7 sobre los pies", "blocks": [_block(4.0)], "start": Vector3(0, 2.3, FACE_Z + 0.6), "air": true,
			"ticks": 150, "h": 4.0, "mantle": false, "end": "colgado"})
	_cases.append({"name": "pegado a la pared, salto en el lugar, 1,6 m", "blocks": [_block(1.6)], "start": Vector3(0, 0, FACE_Z + 0.36),
			"jump_at": [10], "ticks": 150, "h": 1.6, "mantle": true, "end": "arriba"})
	# Con el súper, saltando en el lugar las manos llegan al filo cuando todavía
	# está más alto que el pecho: colgado, como en los bloques del súper de la
	# pista de salto agachado.
	_cases.append({"name": "súper, salto en el lugar, 2,4 m", "blocks": [_block(2.4)], "jump_at": [10], "boost": true, "ticks": 150, "h": 2.4,
			"mantle": false, "end": "colgado"})
	_cases.append({"name": "súper, salto en el lugar, 3,0 m", "blocks": [_block(3.0)], "jump_at": [10], "boost": true, "ticks": 150, "h": 3.0,
			"mantle": false, "end": "colgado"})
	# Agregados el 2026-10-30 (los que la auditoría marcó sin prueba): Ctrl y
	# empujón a mitad de camino, las cajas apiladas y delante de una escalera.
	_cases.append({"name": "Ctrl a mitad del mantle, 1,6 m", "blocks": [_block(1.6)], "jump_at": [10], "crouch_in_mantle": true, "ticks": 150,
			"h": 1.6, "mantle": true, "cut": true, "end": "abajo"})
	_cases.append({"name": "empujón fuerte a mitad del mantle, 1,6 m", "blocks": [_block(1.6)], "jump_at": [10], "push_in_mantle": _tuning.hang_grip,
			"ticks": 150, "h": 1.6, "mantle": true, "cut": true, "end": "abajo"})
	_cases.append({"name": "empujón débil a mitad del mantle, 1,6 m", "blocks": [_block(1.6)], "jump_at": [10], "push_in_mantle": _tuning.hang_grip - 1,
			"ticks": 150, "h": 1.6, "mantle": true, "end": "arriba"})
	_cases.append({"name": "dos cajas de 0,8 apiladas, salto en el lugar", "blocks": [[Vector3(3, 0.8, 3), Vector3(0, 0.4, FACE_Z - 1.5)],
			[Vector3(3, 0.8, 3), Vector3(0, 1.2, FACE_Z - 1.5)]], "jump_at": [10], "ticks": 150, "h": 1.6, "mantle": true, "end": "arriba"})
	_cases.append({"name": "delante de una escalera, 1,6 m", "blocks": [_block(1.6)], "ladder": 1.6, "jump_at": [10], "ticks": 150, "h": 1.6,
			"mantle": false, "end": "abajo"})


## Un bloque de alto h con la cara en FACE_Z. Los casos que siguen apretando
## una tecla después de subir lo llevan más hondo o más ancho, así no se caen
## por atrás o por el costado antes de terminar.
func _block(h: float, depth := 3.0, width := 3.0) -> Array:
	return [Vector3(width, h, depth), Vector3(0, h * 0.5, FACE_Z - depth * 0.5)]


func _add_box(size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	add_child(body)


func _start_case() -> void:
	_index += 1
	if _index >= _cases.size():
		_report()
		return
	_case = _cases[_index]
	_state = ActorState.new()
	_state.position = _case.get("start", Vector3(0, 0, FACE_Z + 0.5)) + Vector3(_index * LANE, 0, 0)
	if _case.get("air", false):
		_state.mode = ActorState.Mode.AIR
	else:
		_state.mode = ActorState.Mode.GROUND
		_state.on_floor = true
	_state.facing_yaw = _case.get("look", 0.0)
	_state.boosted = _case.get("boost", false)
	_state.jumped = _case.get("jumped", false)
	_state.quantize()
	_actor.apply_state(_state)
	_actor.teleported()
	_t = 0
	_presses = 0
	_jumped_once = false
	_hang_jumped = false
	_modes.clear()
	_befores.clear()
	_afters.clear()
	_inputs.clear()
	_mantle_from = -1
	_mantle_until = -1
	_mantle_stance = -1
	_mode_after_mantle = -1
	_invalid = 0


func _input_now() -> ActorInput:
	var move := Vector2.ZERO
	if _t >= _case.get("move_from", 0) and _t < _case.get("move_until", 99999):
		move = _case.get("move", Vector2.ZERO)
	if _case.get("w_at_top", false) and _hang_jumped and _state.velocity.y <= 0.0 and _state.mode != ActorState.Mode.HANGING:
		move = Vector2(0, 1)
	if _case.get("until_mantle", false) and _jumped_once:
		move = Vector2.ZERO
	if _case.get("d_in_mantle", false) and _state.mode == ActorState.Mode.MANTLE:
		move = Vector2(1, 0)
	var buttons := ActorInput.BUTTON_THIRD_PERSON
	if _case.get("run", false):
		buttons |= ActorInput.BUTTON_RUN
	var crouch: Array = _case.get("crouch", [-1, -1])
	if _t >= crouch[0] and _t < crouch[1]:
		buttons |= ActorInput.BUTTON_CROUCH
	if _case.get("crouch_in_mantle", false) and _mantle_from != -1 and _t >= _mantle_from + CUT_AFTER_TICKS and _t < _mantle_from + 60:
		buttons |= ActorInput.BUTTON_CROUCH
	if _t in _case.get("jump_at", []):
		_presses += 1
	if _case.has("jump_when_z") and not _jumped_once and _state.position.z < _case["jump_when_z"]:
		_presses += 1
		_jumped_once = true
	if _case.has("hang_jump_at") and not _hang_jumped and _t >= _case["hang_jump_at"] and _state.mode == ActorState.Mode.HANGING:
		_presses += 1
		_hang_jumped = true
	return ActorInput.make(_tick, move, _case.get("look", 0.0), buttons, _presses)


func _physics_process(_delta: float) -> void:
	if (Time.get_ticks_msec() - _started_msec) / 1000.0 > TIMEOUT_SECONDS:
		print("%s NO TERMINÓ a tiempo (%.0f s), en el caso %d" % [LOG_PREFIX, TIMEOUT_SECONDS, _index])
		set_physics_process(false)
		get_tree().quit(2)
		return
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_start_case()
		return
	if _index >= _cases.size():
		return
	var mode_before := _state.mode
	# El empujón, como un evento: antes del paso.
	if _case.has("push_in_mantle") and _state.mode == ActorState.Mode.MANTLE and _t == _mantle_from + CUT_AFTER_TICKS:
		ActorMotor.apply_impulse(_state, Vector3(0, 0, 3), _case["push_in_mantle"], _tuning)
	var input := _input_now()
	var why := ""
	var tracing: bool = _trace != "" and (_case["name"] as String).begins_with(_trace)
	if tracing and _state.mode == ActorState.Mode.AIR:
		var check := ActorMotor.mantle_check(_actor, _state, ActorMotor.grab_direction(input.look_yaw), _tuning, DT)
		why = check["why"]
		if not (check["edge"] as Dictionary).is_empty():
			why += " (filo y=%.3f)" % check["edge"]["point"].y
	var before := _state.to_bytes()
	ActorMotor.step(_actor, _state, input, _tuning, DT)
	_befores.append(before)
	_afters.append(_state.to_bytes())
	_inputs.append(input)
	var mode_name: String = ActorState.Mode.keys()[_state.mode]
	if _modes.is_empty() or _modes[-1] != mode_name:
		_modes.append(mode_name)
	if _state.mode == ActorState.Mode.MANTLE:
		if _mantle_from == -1:
			_mantle_from = _t
			_mantle_stance = _state.stance
			_mantle_feet = BaseRegistry.world_position(_state)
		if not ActorMotor.anchored_pose_valid(_actor, _state, _tuning):
			_invalid += 1
	elif mode_before == ActorState.Mode.MANTLE and _mantle_until == -1:
		_mantle_until = _t
		_mode_after_mantle = _state.mode
		_mantle_end = BaseRegistry.world_position(_state) - Vector3(_index * LANE, 0, 0)
	if tracing:
		print("  t=%3d %-7s %-8s pies=(%.3f, %.3f, %.3f) vel=(%.2f, %.2f, %.2f) piso=%s %s" % [_t, mode_name,
				ActorState.Stance.keys()[_state.stance], _state.position.x - _index * LANE, _state.position.y, _state.position.z,
				_state.velocity.x, _state.velocity.y, _state.velocity.z, _state.on_floor, why])
	_t += 1
	_tick += 1
	if _t >= _case["ticks"]:
		_finish_case()
		_start_case()


## Dónde terminó: arriba del bloque (en Suelo, a la altura del filo y detrás de
## la cara), colgado, en la escalera, abajo (en el piso, de cualquier lado) o
## en otro lado.
func _where(feet: Vector3) -> String:
	var h: float = _case["h"]
	if _state.mode == ActorState.Mode.HANGING:
		return "colgado"
	if _state.mode == ActorState.Mode.LADDER:
		return "escalera"
	if _state.mode == ActorState.Mode.GROUND and absf(feet.y - h) < 0.02 and feet.z < FACE_Z:
		return "arriba"
	if _state.mode == ActorState.Mode.GROUND and feet.y < 0.02:
		return "abajo"
	return "otro"


func _finish_case() -> void:
	var feet := BaseRegistry.world_position(_state) - Vector3(_index * LANE, 0, 0)
	var where := _where(feet)
	var name: String = _case["name"]
	var problems: Array[String] = []
	var entered := _mantle_from != -1
	if entered != (_case["mantle"] as bool):
		problems.append("tenía que %s al mantle" % ("entrar" if _case["mantle"] else "no entrar"))
	if where != _case["end"]:
		problems.append("tenía que terminar %s y terminó %s" % [_case["end"], where])
	if entered and _case["mantle"]:
		var until := _mantle_until if _mantle_until != -1 else _t
		var seconds := (until - _mantle_from) * DT
		if _case.get("cut", false):
			if _mantle_until == -1 or _mode_after_mantle != ActorState.Mode.AIR:
				problems.append("el mantle tenía que cortarse y salir al aire")
		else:
			if _mantle_until == -1 or _mode_after_mantle != ActorState.Mode.GROUND:
				problems.append("el mantle tenía que terminar en Suelo")
			elif absf(_mantle_end.y - (_case["h"] as float)) > 0.02 or _mantle_end.z >= FACE_Z:
				problems.append("el mantle tenía que terminar arriba del filo y terminó en (%.2f, %.3f, %.2f)" % [
						_mantle_end.x, _mantle_end.y, _mantle_end.z])
			if seconds > MAX_MANTLE_SECONDS:
				problems.append("el mantle tardó %.2f s (más de %.1f)" % [seconds, MAX_MANTLE_SECONDS])
			var stance: int = _case.get("stance", ActorState.Stance.STANDING)
			if _mantle_stance != stance:
				problems.append("el mantle tenía que ir %s" % ("agachado" if stance == ActorState.Stance.CROUCHED else "parado"))
			if _case.has("side") and feet.x * float(_case["side"]) < MIN_SIDE_SHIFT:
				problems.append("tenía que correrse hacia %s x y quedó en x %.2f" % ["+" if _case["side"] > 0 else "-", feet.x])
	if _invalid > 0:
		problems.append("%d poses del mantle no las acepta anchored_pose_valid" % _invalid)
	var different := _replay_mantle_ticks()
	if different > 0:
		problems.append("%d ticks del mantle, repetidos, dan otros bytes" % different)
	var line := "%s %-5s %-56s %s" % [LOG_PREFIX, "OK" if problems.is_empty() else "FALLA", name, " > ".join(_modes)]
	if entered:
		var until := _mantle_until if _mantle_until != -1 else _t
		line += " · mantle t=%d a %d (%.2f s), %s, pies al empezar %.2f" % [_mantle_from, until, (until - _mantle_from) * DT,
				"agachado" if _mantle_stance == ActorState.Stance.CROUCHED else "parado", _mantle_feet.y]
	line += " · final %s %s en (%.2f, %.3f, %.2f): %s" % [ActorState.Mode.keys()[_state.mode], ActorState.Stance.keys()[_state.stance],
			feet.x, feet.y, feet.z, where]
	print(line)
	for problem in problems:
		print("%s       %s" % [LOG_PREFIX, problem])
	if not problems.is_empty():
		_failed.append(name)


## Repite cada tick del mantle, y el que lo termina, desde el estado anterior,
## y cuenta los que no dan los mismos bytes que en vivo.
func _replay_mantle_ticks() -> int:
	var bad := 0
	for k in _afters.size():
		var s_before := ActorState.from_bytes(_befores[k])
		var s_after := ActorState.from_bytes(_afters[k])
		if s_before.mode != ActorState.Mode.MANTLE and s_after.mode != ActorState.Mode.MANTLE:
			continue
		_actor.apply_state(s_before)
		ActorMotor.step(_actor, s_before, _inputs[k], _tuning, DT)
		if s_before.to_bytes() != _afters[k]:
			bad += 1
			if bad <= 3:
				print("%s       repetición distinta en t=%d:\n        en vivo  %s\n        repetido %s" % [LOG_PREFIX, k, s_after.describe(), s_before.describe()])
	return bad


func _report() -> void:
	set_physics_process(false)
	if _failed.is_empty():
		print("%s OK: los %d casos dan lo esperado" % [LOG_PREFIX, _cases.size()])
		get_tree().quit(0)
	else:
		print("%s FALLAN %d de %d casos: %s" % [LOG_PREFIX, _failed.size(), _cases.size(), ", ".join(_failed)])
		get_tree().quit(1)
