extends Node3D

## Pruebas de confirmación de Hanging (sección "Hanging: con snap" de la
## arquitectura), sin red: barrido automático de aproximaciones contra cada
## borde fijo de la pista de bordes.
##
## Cada caso arranca al actor en el aire, con una velocidad elegida para que
## llegue a la cara del borde con la velocidad horizontal, la vertical, el
## ángulo y el corrimiento lateral de la grilla, mirando hacia donde se mueve.
## Cada caso se corre dos veces: empujando en la dirección de llegada con la
## fuerza justa para mantener esa velocidad, y sin tocar ninguna tecla (las
## manos buscan hacia donde mira el personaje). Los que llegan subiendo arrancan
## con un salto desde el piso; los que llegan bajando, desde más arriba. Si el
## cuerpo arrancaría metido en algo, el caso no es posible y no se cuenta.
##
## Se registra si se agarró y en qué tick, la distancia del snap, los ticks
## colgado con el cuerpo metido en la geometría y si funcionan las salidas:
## soltarse, saltar hacia atrás, desplazarse (mirando a la pared y con la cámara
## de costado) y subir. Cuando no se agarra, por
## qué, y si sin snap se habría agarrado (el borde estaba al alcance de las
## manos y solo falló la pose).
##
## Criterios fijados antes de medir:
## 1. 95 % o más de capturas en la banda buscada: casos en que las manos
##    cruzan la banda del filo (hasta 20 cm por debajo), sobre el filo o hasta
##    10 cm delante de la cara, bajando o subiendo, con el cuerpo debajo del
##    filo y con intención clara hacia la cara (35° o menos, empujando o
##    mirando), en un borde donde colgarse es posible;
## 2. 1 % o menos de agarres no buscados: yendo a aterrizar arriba del borde
##    donde se puede aterrizar, o pasando de largo paralelo a la cara;
## 3. cero ticks colgado con el cuerpo metido en la geometría;
## 4. 10 cm o menos de salto de la cámara en los 50 ms después de agarrarse.
##
## Sale con 0 si se cumplen los cuatro criterios y con 1 si no.

const TICK_DT := 1.0 / 60.0
const COURSE_ORIGIN := Vector3(10, 0, -10)
const SLOT_SPACING := Vector2(3.5, 8.0)
## [nombre, lugar en la grilla, alto del filo, forma, medio ancho útil del filo,
##  si colgarse es posible, si se puede aterrizar arriba, si se puede subir]
const VARIANTS := [
	["1,6 m", Vector2(0, 0), 1.6, "plano", 1.2, false, true, true],
	["2,0 m", Vector2(1, 0), 2.0, "plano", 1.2, true, true, true],
	["2,4 m", Vector2(2, 0), 2.4, "plano", 1.2, true, true, true],
	["5 cm de espesor", Vector2(3, 0), 2.0, "plano", 1.2, true, false, false],
	["20 cm de espesor", Vector2(4, 0), 2.0, "plano", 1.2, true, false, false],
	["malla", Vector2(5, 0), 2.0, "plano", 1.2, true, true, true],
	["inclinado 10°", Vector2(0, 1), 2.0, "plano", 1.2, true, true, true],
	["inclinado 25°", Vector2(1, 1), 2.0, "plano", 1.2, true, true, true],
	["curvo", Vector2(2, 1), 2.0, "curvo", 1.0, true, true, true],
	["techo bajo", Vector2(3, 1), 2.0, "plano", 1.0, true, false, false],
	["paredes al costado", Vector2(4, 1), 2.0, "plano", 0.85, true, true, true],
]
const HORIZONTAL_SPEEDS := [0.0, 2.0, 4.0, 6.0, 8.0]
const ARRIVAL_SPEEDS := [-12.0, -8.0, -4.0, -2.0, 0.0, 1.5, 3.0]
const ANGLES := [0.0, 35.0, 70.0]
const LATERAL := [0.0, 0.6]
## Segundos de vuelo antes de llegar, para los casos que llegan bajando.
const LEAD_TIME := 0.4
const RUN_TICKS := 100
const EXIT_TICKS := 90
## Hasta dónde llegan las manos sin snap (con los brazos), para la variante B.
const REACH_WITHOUT_SNAP := 0.6
const EXITS := ["soltarse", "saltar hacia atrás", "desplazarse", "desplazarse con la cámara de costado", "subir",
		"subir con W recién arriba"]
## Con las teclas de dirección apretadas o sin tocar ninguna.
const KEYS := ["empuja", "sin teclas"]

var _tuning := ActorTuning.from_scene()
var _cases: Array = []
var _index := 0
var _results: Array = []
## Con --detalle=borde,vel,llegada,ángulo,lateral,objetivo,teclas imprime ese caso tick a tick.
var _detail := ""
## Subir: la altura más alta de los pies sobre el filo en el último intento.
var _last_climb_peak := -INF

@onready var _actor: ActorBody = $Actor


func _ready() -> void:
	# Los valores del nodo Tuning de net_lab.tscn, en un nodo propio de la prueba.
	add_child(_tuning)
	SimClock.apply_tick_rate(SimClock.TICK_RATE)
	Engine.physics_jitter_fix = 0.0
	for keys in KEYS:
		for variant in VARIANTS:
			for speed in HORIZONTAL_SPEEDS:
				for arrival in ARRIVAL_SPEEDS:
					for angle in ANGLES:
						for lateral in LATERAL:
							_cases.append({"variant": variant, "speed": speed, "arrival": arrival, "angle": angle,
									"lateral": lateral, "goal": "colgarse", "keys": keys})
			# Ir a aterrizar arriba: llegar con los pies 20 cm por encima del filo.
			for speed in [2.0, 4.0, 6.0, 8.0]:
				for arrival in [-4.0, -2.0, 0.0]:
					_cases.append({"variant": variant, "speed": speed, "arrival": arrival, "angle": 0.0,
							"lateral": 0.0, "goal": "aterrizar", "keys": keys})
			# Pasar de largo: paralelo a la cara, con las manos cruzando el filo.
			for speed in [2.0, 4.0, 6.0, 8.0]:
				for arrival in [-4.0, -2.0, 0.0]:
					_cases.append({"variant": variant, "speed": speed, "arrival": arrival, "angle": 90.0,
							"lateral": 0.0, "goal": "pasar de largo", "keys": keys})
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--detalle="):
			_detail = arg.trim_prefix("--detalle=")
	print("[barrido] %d casos" % _cases.size())


func _physics_process(_delta: float) -> void:
	# Varios casos por frame de física: cada uno corre sus ticks enteros, como
	# las repeticiones de la reconciliación.
	for i in 4:
		if _index >= _cases.size():
			_finish()
			set_physics_process(false)
			return
		_results.append(_run(_cases[_index]))
		_index += 1


func _face(variant: Array) -> Vector3:
	return COURSE_ORIGIN + Vector3(variant[1].x * SLOT_SPACING.x, 0.0, -variant[1].y * SLOT_SPACING.y)


## Un caso: arma el estado inicial, corre hasta agarrarse o hasta RUN_TICKS, y
## si se agarró prueba las salidas desde el mismo estado.
func _run(c: Dictionary) -> Dictionary:
	var variant: Array = c["variant"]
	var face := _face(variant)
	var height: float = variant[2]
	var angle := deg_to_rad(c["angle"])
	# Dirección de llegada: hacia la cara (-Z), girada `angle` hacia +X.
	var direction := Vector3(sin(angle), 0.0, -cos(angle))
	var yaw := atan2(-direction.x, -direction.z)
	var contact := face + Vector3(c["lateral"], height - _tuning.hang_height, _tuning.hang_distance)
	if c["goal"] == "aterrizar":
		contact = face + Vector3(0.0, height + 0.2, -0.6)
	elif c["goal"] == "pasar de largo":
		contact = face + Vector3(-0.6, height - _tuning.hang_height, _tuning.hang_distance + 0.05)
	var speed: float = c["speed"]
	var arrival: float = c["arrival"]
	var vy0 := arrival + _tuning.gravity * LEAD_TIME
	var lead := LEAD_TIME
	if arrival > 0.0:
		# Llega subiendo: un salto desde el piso que pasa por el contacto con esa velocidad.
		vy0 = sqrt(arrival * arrival + 2.0 * _tuning.gravity * maxf(contact.y, 0.0))
		lead = (vy0 - arrival) / _tuning.gravity
	var start := contact - direction * speed * lead - Vector3.UP * (vy0 * lead - 0.5 * _tuning.gravity * lead * lead)
	var result := {"case": c, "possible": true, "captured": false, "tick": -1, "snap": Vector3.ZERO,
			"why": "", "b_would": false, "in_band": false, "landed_on_top": false, "inside": 0, "exits": {},
			"grab_normal": Vector3.ZERO}
	var state := ActorState.new()
	state.position = start
	state.velocity = direction * speed + Vector3.UP * vy0
	state.facing_yaw = yaw
	state.mode = ActorState.Mode.AIR
	state.quantize()
	if start.y < -0.001 or not _actor.stance_fits(ActorState.Stance.STANDING, state.position):
		result["possible"] = false
		return result
	# Fuerza del empuje: la justa para que el control aéreo no cambie la velocidad.
	# Sin teclas, no empuja: sigue la misma parábola, sin control aéreo.
	var push := clampf(speed / _tuning.walk_speed, 0.2, 1.0) if c["keys"] == "empuja" else 0.0
	var detailed := _detail == "%s,%.0f,%.1f,%.0f,%.1f,%s,%s" % [variant[0], speed, arrival, c["angle"], c["lateral"], c["goal"], c["keys"]]
	_actor.apply_state(state)
	for t in RUN_TICKS:
		_note_tick(state, yaw, variant, result)
		ActorMotor.step(_actor, state, ActorInput.make(t, Vector2(0, push), yaw, 0, 0), _tuning, TICK_DT)
		if detailed:
			print("[detalle] t=%d modo=%s pies=%s vel=%s ancla=%s filo=%s por_qué=%s" % [t, ActorState.Mode.keys()[state.mode],
					_actor.global_position, state.velocity, state.anchor_id, state.anchor_point, result["why"]])
		if state.mode == ActorState.Mode.HANGING:
			result["captured"] = true
			result["tick"] = t
			result["grab_normal"] = -Vector3.FORWARD.rotated(Vector3.UP, state.facing_yaw)
			result["snap"] = _actor.grab_jump
			_actor.grab_jump = Vector3.ZERO
			var hanging := state.copy()
			result["inside"] = _count_inside(hanging, 20)
			for exit in EXITS:
				result["exits"][exit] = _try_exit(hanging, exit, height)
				if exit == "subir con W recién arriba":
					result["climb_peak"] = _last_climb_peak
			break
		if state.mode == ActorState.Mode.GROUND and t > 3:
			result["landed_on_top"] = _actor.global_position.y > height - 0.2
			break
	return result


## Antes de cada tick en el aire: si las manos cruzan la banda del filo (para
## el criterio 1) y, con la misma decisión y la misma dirección que el motor, por qué no se agarraría
## (para explicar los casos sin captura y la variante sin snap).
func _note_tick(state: ActorState, look_yaw: float, variant: Array, result: Dictionary) -> void:
	if state.mode != ActorState.Mode.AIR:
		return
	var direction := ActorMotor.grab_direction(look_yaw).normalized()
	var from := _actor.global_position
	var fall := maxf(state.velocity.y - _tuning.gravity * TICK_DT, -_tuning.max_fall_speed)
	var motion := Vector3(state.velocity.x, fall, state.velocity.z) * TICK_DT
	var hands_from := EdgeProbe.hands_at(_actor, from, direction, _tuning)
	var hands_to := EdgeProbe.hands_at(_actor, from + motion, direction, _tuning)
	if not state.on_floor and _crosses_band(variant, hands_from, hands_to, from, state, direction):
		result["in_band"] = true
	if result["why"] == "se agarraría":
		return
	var check := ActorMotor.grab_check(_actor, state, ActorMotor.grab_direction(look_yaw), _tuning, TICK_DT)
	if check["edge"].is_empty():
		return
	var why: String = check["why"] if check["why"] != "" else "se agarraría"
	if why in ["snap muy largo", "la pose no cabe", "camino tapado"] \
			and hands_from.distance_to(check["edge"]["point"]) <= REACH_WITHOUT_SNAP:
		result["b_would"] = true
	if result["why"] == "" or why == "se agarraría":
		result["why"] = why


## La banda buscada de la cara principal de la variante, con su geometría
## conocida: las manos pasan, bajando o subiendo, por la franja de 20 cm bajo
## el filo, sobre el filo o hasta 10 cm delante de la cara, dentro de su ancho;
## el cuerpo está debajo del filo. En el curvo, la intención tiene que apuntar a
## la superficie donde llegan las manos (45° o menos de su normal).
func _crosses_band(variant: Array, hands_from: Vector3, hands_to: Vector3, feet: Vector3, state: ActorState, direction: Vector3) -> bool:
	var height: float = variant[2]
	if not variant[5]:
		return false
	if feet.y + _actor.stance_height(state.stance) * 0.5 > height:
		return false
	if maxf(hands_from.y, hands_to.y) < height - 0.2 or minf(hands_from.y, hands_to.y) > height:
		return false
	var face := _face(variant)
	var hands := hands_to
	var front := 0.0
	var side := 0.0
	if variant[3] == "curvo":
		var center := face + Vector3(0, 0, -1.0)
		var flat := Vector2(hands.x - center.x, hands.z - center.z)
		front = flat.length() - 1.0
		side = absf(atan2(flat.x, flat.y)) * 1.0
		var outward := Vector3(flat.x, 0.0, flat.y).normalized()
		if direction.dot(-outward) < cos(deg_to_rad(45.0)):
			return false
	else:
		front = hands.z - face.z
		side = absf(hands.x - face.x)
	return front >= -0.25 and front <= 0.1 and side <= variant[4] - 0.15


## Ticks colgado (sin input) con el cuerpo metido más de 2 cm en la geometría.
func _count_inside(hanging: ActorState, ticks: int) -> int:
	var state := hanging.copy()
	_actor.apply_state(state)
	var inside := 0
	for t in ticks:
		ActorMotor.step(_actor, state, ActorInput.make(t, Vector2.ZERO, state.facing_yaw, 0, 0), _tuning, TICK_DT)
		if state.mode == ActorState.Mode.HANGING and not _actor.stance_fits(state.stance, _actor.global_position):
			inside += 1
	return inside


## Una salida desde el estado colgado: "sí" o "no". Desplazarse prueba los dos
## lados (el borde puede terminar de uno), mirando a la pared o con la cámara
## mirando 90° a la derecha; saltar hacia atrás se mide contra la
## pared de la que estaba colgado. Subir es saltar para arriba mirando a la
## pared y apretar W hacia ella: desde el salto, o recién cuando deja de subir
## (para ver el margen). Tiene que terminar en Suelo arriba del borde.
func _try_exit(hanging: ActorState, exit: String, height: float) -> String:
	if exit == "desplazarse":
		return "sí" if _shimmy(hanging, 1.0, 0.0) or _shimmy(hanging, -1.0, 0.0) else "no"
	if exit == "desplazarse con la cámara de costado":
		return "sí" if _shimmy(hanging, 1.0, -PI / 2.0) or _shimmy(hanging, -1.0, -PI / 2.0) else "no"
	var state := hanging.copy()
	_actor.apply_state(state)
	var start := _actor.global_position
	var wall_yaw := state.facing_yaw
	var away := -Vector3.FORWARD.rotated(Vector3.UP, wall_yaw)
	_last_climb_peak = -INF
	for t in EXIT_TICKS:
		var yaw := wall_yaw
		var buttons := 0
		var presses := 0
		var move := Vector2.ZERO
		match exit:
			"soltarse":
				buttons = ActorInput.BUTTON_CROUCH if t < 3 else 0
			"saltar hacia atrás":
				yaw = wall_yaw + PI
				presses = 1
			"subir":
				presses = 1
				move = Vector2(0, 1)
			"subir con W recién arriba":
				presses = 1
				if t > 0 and state.velocity.y <= 0.0:
					move = Vector2(0, 1)
		ActorMotor.step(_actor, state, ActorInput.make(t, move, yaw, buttons, presses), _tuning, TICK_DT)
		if exit.begins_with("subir"):
			if state.mode == ActorState.Mode.AIR:
				_last_climb_peak = maxf(_last_climb_peak, _actor.global_position.y - height)
			if state.mode == ActorState.Mode.GROUND and _actor.global_position.y > height - 0.5:
				return "sí"
	match exit:
		"soltarse":
			return "sí" if state.mode != ActorState.Mode.HANGING and _actor.global_position.y < start.y + 0.01 else "no"
		"saltar hacia atrás":
			return "sí" if state.mode != ActorState.Mode.HANGING and (_actor.global_position - start).dot(away) > 1.0 else "no"
	return "no"


## Desplazarse colgado con A (side -1) o D (side 1), con la cámara girada
## `look_offset` desde la pared: tiene que ir 30 cm hacia ese lado del personaje
## frente a la pared, mire donde mire la cámara.
func _shimmy(hanging: ActorState, side: float, look_offset: float) -> bool:
	var state := hanging.copy()
	_actor.apply_state(state)
	var start := state.anchor_point
	var wall_yaw := state.facing_yaw
	var right := Vector3.FORWARD.rotated(Vector3.UP, wall_yaw).cross(Vector3.UP)
	for t in 40:
		ActorMotor.step(_actor, state, ActorInput.make(t, Vector2(side, 0), wall_yaw + look_offset, 0, 0), _tuning, TICK_DT)
		if state.mode != ActorState.Mode.HANGING:
			return false
		if (state.anchor_point - start).dot(right * side) >= 0.3:
			return true
	return false


## Métricas visuales de un agarre (prueba 4): cuánto se mueve la raíz visual,
## que es lo que sigue la cámara, en los 50 ms (3 ticks) y en los 100 ms (6
## ticks) después de agarrarse, y en cuántos segundos el desvío vuelve a cero
## (menos de 1 mm). Arranca desde donde estaba el cuerpo.
func _visual_metrics(snap: Vector3) -> Array:
	_actor.teleported()
	_actor.grab_jump = snap
	_actor.present(_actor.state)
	var before := _actor.grab_offset
	var moved_50 := 0.0
	var moved_100 := 0.0
	var ticks := 0
	while _actor.grab_offset.length() >= 0.001 and ticks < 600:
		_actor.decay_visual_offset(TICK_DT)
		ticks += 1
		if ticks == 3:
			moved_50 = (_actor.grab_offset - before).length()
		if ticks == 6:
			moved_100 = (_actor.grab_offset - before).length()
	if ticks < 6:
		moved_100 = snap.length()
		moved_50 = minf(moved_50 if ticks >= 3 else snap.length(), snap.length())
	_actor.teleported()
	return [moved_50, moved_100, ticks * TICK_DT]


func _finish() -> void:
	var impossible := 0
	var wanted := 0
	var wanted_captured := 0
	var unwanted := 0
	var unwanted_captured := 0
	var other_edges := 0
	var inside_ticks := 0
	var max_snap := 0.0
	var max_camera := 0.0
	var max_camera_100 := 0.0
	var max_settle := 0.0
	var settle_sum := 0.0
	var captures := 0
	var reasons := {}
	var b_rescues := 0
	var exit_stats := {}
	var by_variant := {}
	var by_keys := {}
	for r in _results:
		var c: Dictionary = r["case"]
		var variant: Array = c["variant"]
		var label: String = variant[0]
		if not r["possible"]:
			impossible += 1
			continue
		var row: Dictionary = by_variant.get_or_add(label, {"casos": 0, "agarres": 0, "en_banda": 0, "snap_max": 0.0})
		row["casos"] += 1
		if r["in_band"]:
			row["en_banda"] += 1
		var is_wanted: bool = c["goal"] == "colgarse" and c["angle"] <= 35.0 and r["in_band"]
		var is_unwanted: bool = (c["goal"] == "aterrizar" and variant[6]) or c["goal"] == "pasar de largo"
		var k: Dictionary = by_keys.get_or_add(c["keys"], {"buscados": 0, "agarrados": 0, "no_buscados": 0, "agarrados_sin_buscar": 0})
		if r["captured"]:
			var snap: float = r["snap"].length()
			row["agarres"] += 1
			row["snap_max"] = maxf(row["snap_max"], snap)
			max_snap = maxf(max_snap, snap)
			var visual := _visual_metrics(r["snap"])
			max_camera = maxf(max_camera, visual[0])
			max_camera_100 = maxf(max_camera_100, visual[1])
			max_settle = maxf(max_settle, visual[2])
			settle_sum += visual[2]
			captures += 1
			inside_ticks += r["inside"]
			for exit in r["exits"]:
				var verdict: String = r["exits"][exit]
				if exit.begins_with("subir") and not variant[7] and verdict == "no":
					verdict = "no corresponde"
				var e: Dictionary = exit_stats.get_or_add(exit, {"sí": 0, "no": 0, "no corresponde": 0})
				e[verdict] += 1
		if is_wanted:
			wanted += 1
			k["buscados"] += 1
			if r["captured"]:
				wanted_captured += 1
				k["agarrados"] += 1
			else:
				var why: String = r["why"] if r["why"] != "" else "las manos no encontraron borde"
				reasons[why] = reasons.get(why, 0) + 1
				if r["b_would"]:
					b_rescues += 1
		if is_unwanted:
			unwanted += 1
			k["no_buscados"] += 1
			# Solo cuenta si agarró el borde que pasaba o donde iba a aterrizar; otro
			# borde del camino (la punta de un techo) es un agarre con intención.
			if r["captured"] and (variant[3] == "curvo" or r["grab_normal"].dot(Vector3.BACK) > 0.85):
				unwanted_captured += 1
				k["agarrados_sin_buscar"] += 1
			elif r["captured"]:
				other_edges += 1
		print("[barrido] caso %s vel=%.0f llegada=%.1f ángulo=%.0f lateral=%.1f objetivo=%s teclas=%s banda=%s -> %s tick=%d snap=%.3f metido=%d por_qué=%s sin_snap=%s arriba=%s pico=%.3f salidas=%s" % [
				label, c["speed"], c["arrival"], c["angle"], c["lateral"], c["goal"], c["keys"], r["in_band"],
				"AGARRA" if r["captured"] else "no", r["tick"], r["snap"].length(), r["inside"], r["why"],
				r["b_would"], r["landed_on_top"], r.get("climb_peak", NAN), r["exits"]])
	for label in by_variant:
		var row: Dictionary = by_variant[label]
		print("[barrido] borde %-20s %3d casos posibles, %3d en la banda buscada, %3d agarres, snap máximo %.3f m" % [
				label, row["casos"], row["en_banda"], row["agarres"], row["snap_max"]])
	for exit in exit_stats:
		print("[barrido] salida %-18s %s" % [exit, exit_stats[exit]])
	# El salto para arriba, en los bordes donde se puede subir: hasta dónde
	# llegan los pies sobre el filo, apretando W recién arriba.
	var peak_min := INF
	var peak_max := -INF
	for r in _results:
		if r["captured"] and r["case"]["variant"][7] and r.has("climb_peak"):
			peak_min = minf(peak_min, r["climb_peak"])
			peak_max = maxf(peak_max, r["climb_peak"])
	print("[barrido] salto para arriba: los pies llegan entre %.3f y %.3f m por encima del filo (buscado: %.2f m)" % [
			peak_min, peak_max, _tuning.hang_climb_clearance])
	print("[barrido] casos imposibles (el cuerpo arrancaría metido en algo): %d" % impossible)
	print("[barrido] en la banda buscada sin agarre, por qué: %s; sin snap se habrían agarrado %d" % [reasons, b_rescues])
	var wanted_rate := 100.0 * wanted_captured / maxi(wanted, 1)
	var unwanted_rate := 100.0 * unwanted_captured / maxi(unwanted, 1)
	var ok_wanted := wanted_rate >= 95.0
	var ok_unwanted := unwanted_rate <= 1.0
	var ok_inside := inside_ticks == 0
	var ok_camera := max_camera <= 0.1
	print("[barrido] criterio 1, capturas en la banda buscada: %d de %d (%.1f %%) -> %s" % [wanted_captured, wanted, wanted_rate, "CUMPLE" if ok_wanted else "NO CUMPLE"])
	print("[barrido] criterio 2, agarres no buscados: %d de %d (%.1f %%) -> %s" % [unwanted_captured, unwanted, unwanted_rate, "CUMPLE" if ok_unwanted else "NO CUMPLE"])
	print("[barrido] además, en esos casos: %d agarres de otro borde que estaba en el camino" % other_edges)
	for keys in by_keys:
		var k: Dictionary = by_keys[keys]
		print("[barrido] %s: en la banda buscada %d de %d agarrados; no buscados %d de %d agarrados" % [
				keys, k["agarrados"], k["buscados"], k["agarrados_sin_buscar"], k["no_buscados"]])
	print("[barrido] criterio 3, ticks colgado metido en la geometría: %d -> %s" % [inside_ticks, "CUMPLE" if ok_inside else "NO CUMPLE"])
	print("[barrido] criterio 4, salto de cámara en 50 ms: %.3f m como máximo (snap máximo %.3f m) -> %s" % [max_camera, max_snap, "CUMPLE" if ok_camera else "NO CUMPLE"])
	print("[barrido] visual: en los 100 ms después de agarrarse la raíz visual y la cámara se mueven %.3f m como máximo; el desvío vuelve a cero en %.2f s de promedio y %.2f s como máximo" % [max_camera_100, settle_sum / maxi(captures, 1), max_settle])
	get_tree().quit(0 if ok_wanted and ok_unwanted and ok_inside and ok_camera else 1)

