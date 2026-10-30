extends Node3D

## Prueba del agarre con las manos por encima del filo (hang_reach_down y
## hang_drop_speed, sección 8.24 del historial), sin red, con el motor real y
## los valores del nodo Tuning de net_lab.tscn. Una pared con la cara en z = 0,
## mirando a +Z, y un cajón aparte, armados acá (no usa el nivel). Casos:
##  1. el del video del usuario: pared de 2,5 m, salta corriendo a 2,9 m. Con
##     el mantle apagado, como cuando se grabó, se agarra al llegar, baja hasta
##     colgar y el dibujo lo alcanza a hang_drop_speed. Con el mantle (desde el
##     2026-10-25) llega subiendo con el filo a la altura del pecho, y sube; en
##     una pared de 2,8 m el filo ya queda más alto y se agarra desde arriba;
##  2. el súper salto contra esa pared: pasa arriba y cae arriba, no se agarra;
##     contra una de 3,5 m, se agarra;
##  3. saltando a cajones de 0,8 y 1,0 m: cae arriba;
##  4. parado contra la pared de 2,5 m, salta en el lugar sin teclas: se agarra;
##  5. colgado, Espacio mirando la pared: sin W vuelve a colgarse, con W sube;
##  6. bajando de espaldas desde arriba de la pared, mirándola: cuánto cae
##     antes de agarrarse (solo informa);
##  7. cayendo derecho junto a la pared: pegado se agarra, a 0,35 m no;
##  8. cayendo pegado a la pared con las manos a distintas alturas sobre el
##     filo: hasta hang_reach_down se agarra en el acto y baja eso; más arriba,
##     se agarra después, sin bajar más que hang_reach_down.
##
## Nació del diagnóstico temporal diag_agarre_arriba.gd del 2026-10-19
## (Apéndice B del historial); desde el 2026-10-30 es una prueba fija, a pedido
## del usuario, después de la auditoría de GPT, con el caso 8 nuevo. Sale con 0
## si se cumplen todas las comprobaciones y con 1 si no.

const LOG_PREFIX := "[grab_above_test]"

var _tuning := ActorTuning.from_scene()
var _wall: StaticBody3D
var _box: StaticBody3D
var _checks := 0
var _fails := 0

@onready var _actor: ActorBody = $Actor


func _ready() -> void:
	add_child(_tuning)
	SimClock.apply_tick_rate(SimClock.TICK_RATE)
	add_child(_make_box(Vector3(80, 1, 80), Vector3(0, -0.5, 0)))
	_wall = _make_box(Vector3(20, 2.5, 3), Vector3(0, 1.25, -1.5))
	add_child(_wall)
	_box = _make_box(Vector3(3, 1, 3), Vector3(30, 0.5, -1.5))
	add_child(_box)
	_run.call_deferred()


func _make_box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	body.add_child(shape)
	body.position = center
	return body


func _resize(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	((body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = size
	body.position = center
	# Movido así, recién se ve en las consultas después del paso de física
	# siguiente; con esto, en el acto (sección 12 del historial).
	body.force_update_transform()


func _check(what: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("%s %s %s: %s" % [LOG_PREFIX, "OK   " if ok else "FALLA", what, detail])


func _start(position: Vector3, mode: int) -> ActorState:
	var s := ActorState.new()
	s.mode = mode
	s.on_floor = mode == ActorState.Mode.GROUND
	s.position = position
	s.quantize()
	_actor.apply_state(s)
	return s


## Camina con W mirando a -Z desde z = 7 y salta al pasar `jump_at`. Corta al
## agarrarse o al volver a apoyarse después del salto. Devuelve [estado, tick del agarre].
func _run_jump(x: float, jump_at: float, boosted: bool, ticks: int) -> Array:
	var s := _start(Vector3(x, 0, 7.0), ActorState.Mode.GROUND)
	s.boosted = boosted
	var jumps := 0
	var grab := -1
	var flew := false
	for t in ticks:
		if jumps == 0 and s.position.z <= jump_at:
			jumps = 1
		ActorMotor.step(_actor, s, ActorInput.make(t, Vector2(0, 1), 0.0, 0, jumps), _tuning, SimClock.TICK_DT)
		if s.mode == ActorState.Mode.HANGING:
			grab = t
			break
		if s.mode == ActorState.Mode.AIR:
			flew = true
		elif flew and s.mode == ActorState.Mode.GROUND:
			break
	return [s, grab]


## Como _run_jump contra la pared, sin cortar: devuelve [estado, modos por los
## que pasó].
func _run_modes(jump_at: float, ticks: int) -> Array:
	var s := _start(Vector3(0, 0, 7.0), ActorState.Mode.GROUND)
	var modes: Array[String] = []
	for t in ticks:
		var move := Vector2(0, 1) if s.mode != ActorState.Mode.GROUND or s.position.z > -0.5 else Vector2.ZERO
		ActorMotor.step(_actor, s, ActorInput.make(t, move, 0.0, 0, 1 if s.position.z <= jump_at else 0), _tuning, SimClock.TICK_DT)
		var mode_name: String = ActorState.Mode.keys()[s.mode]
		if modes.is_empty() or modes[-1] != mode_name:
			modes.append(mode_name)
	return [s, modes]


func _run() -> void:
	print("%s hang_reach_down=%.2f m, hang_drop_speed=%.1f m/s" % [LOG_PREFIX, _tuning.hang_reach_down, _tuning.hang_drop_speed])
	_resize(_wall, Vector3(20, 2.5, 3), Vector3(0, 1.25, -1.5))

	# 1. El caso del video. Desde el mantle (2026-10-25) ahí sube: llega
	# subiendo con el filo a la altura del pecho. El agarre se prueba con el
	# mantle apagado, como en el video, y además con todo prendido.
	var mantle_max := _tuning.mantle_max_height
	_tuning.mantle_max_height = 0.0
	var s := _start(Vector3(0, 0, 7.0), ActorState.Mode.GROUND)
	var jumps := 0
	var grab := -1
	var speed := 0.0
	var drop := Vector3.ZERO
	for t in 120:
		if jumps == 0 and s.position.z <= 2.9:
			jumps = 1
		var before := s.position
		ActorMotor.step(_actor, s, ActorInput.make(t, Vector2(0, 1), 0.0, 0, jumps), _tuning, SimClock.TICK_DT)
		if s.mode == ActorState.Mode.HANGING:
			grab = t
			speed = _actor.grab_jump_speed
			drop = _actor.grab_jump
			print("%s video, sin el mantle: tick %d, pies antes %.3f, colgado %.3f" % [LOG_PREFIX, t, before.y, s.position.y])
			break
	_tuning.mantle_max_height = mantle_max
	var hang_feet := 2.5 - _tuning.hang_height
	_check("video: se agarra al llegar a la pared (sin este agarre, tick 102)", grab >= 0 and grab <= 82, "tick %d" % grab)
	_check("video: cuelga con los pies a %.2f m" % hang_feet, absf(s.position.y - hang_feet) < 0.01, "%.3f" % s.position.y)
	_check("video: el dibujo baja a hang_drop_speed", speed == _tuning.hang_drop_speed, "%.1f m/s, bajada %.3f m" % [speed, -drop.y])
	_actor.teleported()
	_actor.grab_jump = drop
	_actor.grab_jump_speed = speed
	_actor.present(s)
	var ticks := 0
	while _actor.grab_offset.length() >= 0.03 and ticks < 120:
		_actor.decay_visual_offset(SimClock.TICK_DT)
		ticks += 1
	var limit := drop.length() / _tuning.hang_drop_speed + 0.05
	_check("video: el dibujo llega a 3 cm de colgar en menos de %.2f s" % limit, ticks * SimClock.TICK_DT < limit,
			"%.2f s" % (ticks * SimClock.TICK_DT))
	_actor.teleported()
	# Con el mantle: contra 2,5 m sube y queda arriba; contra 2,8 m el filo ya
	# queda más alto que el pecho y se agarra desde arriba, en el acto.
	var modes := _run_modes(2.9, 150)
	_check("video, con el mantle: sube con el mantle y queda arriba", modes[1].has("MANTLE") and modes[0].mode == ActorState.Mode.GROUND
			and modes[0].position.y > 2.4, "%s, pies %.3f" % [" > ".join(modes[1]), modes[0].position.y])
	_resize(_wall, Vector3(20, 2.8, 3), Vector3(0, 1.4, -1.5))
	var r := _run_jump(0.0, 2.9, false, 120)
	_check("pared de 2,8 m, salta a 2,9 m: se agarra al llegar, desde arriba", r[1] >= 0 and r[1] <= 82
			and _actor.grab_jump_speed == _tuning.hang_drop_speed, "agarre=%d, baja %.3f m, dibujo a %.1f m/s" % [r[1], -_actor.grab_jump.y, _actor.grab_jump_speed])
	_resize(_wall, Vector3(20, 2.5, 3), Vector3(0, 1.25, -1.5))

	# 2. Súper salto.
	r = _run_jump(0.0, 2.9, true, 200)
	_check("súper salto contra 2,5 m: no se agarra y cae arriba", r[1] < 0 and r[0].mode == ActorState.Mode.GROUND and r[0].position.y > 2.4,
			"agarre=%d modo=%s pies=%.3f" % [r[1], ActorState.Mode.keys()[r[0].mode], r[0].position.y])
	_resize(_wall, Vector3(20, 3.5, 3), Vector3(0, 1.75, -1.5))
	r = _run_jump(0.0, 2.9, true, 200)
	_check("súper salto contra 3,5 m: se agarra", r[1] >= 0, "agarre=%d pies=%.3f" % [r[1], r[0].position.y])
	_resize(_wall, Vector3(20, 2.5, 3), Vector3(0, 1.25, -1.5))

	# 3. Cajones: el cajón queda en x = 30, con la cara en z = 0.
	for height: float in [0.8, 1.0]:
		_resize(_box, Vector3(3, height, 3), Vector3(30, height * 0.5, -1.5))
		for jump_at: float in [1.5, 2.2]:
			r = _run_jump(30.0, jump_at, false, 200)
			_check("cajón de %.1f m, salta a %.1f m: cae arriba" % [height, jump_at],
					r[1] < 0 and r[0].mode == ActorState.Mode.GROUND and absf(r[0].position.y - height) < 0.01,
					"agarre=%d modo=%s pies=%.3f" % [r[1], ActorState.Mode.keys()[r[0].mode], r[0].position.y])

	# 4. Parado contra la pared, salta en el lugar sin teclas, mirándola.
	s = _start(Vector3(0, 0, 0.36), ActorState.Mode.GROUND)
	grab = -1
	for t in 90:
		ActorMotor.step(_actor, s, ActorInput.make(t, Vector2.ZERO, 0.0, 0, 1 if t >= 2 else 0), _tuning, SimClock.TICK_DT)
		if s.mode == ActorState.Mode.HANGING:
			grab = t
			break
	_check("parado contra 2,5 m, salto sin teclas: se agarra", grab >= 0, "tick %d, bajada %.3f m" % [grab, -_actor.grab_jump.y])

	# 5. Colgado: Espacio mirando la pared, sin W y con W.
	for with_w: bool in [false, true]:
		var hanging := s.copy()
		_actor.apply_state(hanging)
		var left := false
		var regrab := -1
		for t in 150:
			var move := Vector2(0, 1) if with_w and t >= 12 else Vector2.ZERO
			ActorMotor.step(_actor, hanging, ActorInput.make(t, move, 0.0, 0, 1 if t >= 1 else 0), _tuning, SimClock.TICK_DT)
			if hanging.mode != ActorState.Mode.HANGING:
				left = true
			elif left and regrab < 0:
				regrab = t
			if left and hanging.mode == ActorState.Mode.GROUND:
				break
		var end := "%s pies=%.3f vuelve=%d" % [ActorState.Mode.keys()[hanging.mode], hanging.position.y, regrab]
		if with_w:
			_check("colgado, salto para arriba con W: queda arriba", hanging.mode == ActorState.Mode.GROUND and hanging.position.y > 2.4, end)
		else:
			_check("colgado, salto para arriba sin W: vuelve a colgarse", regrab >= 0, end)

	# 6. De espaldas desde arriba de la pared, mirándola (cámara a -Z), con S.
	# Suelta S apenas deja de pisar. Informativo: con hang_reach_down en 0 (como
	# antes) y con el valor de ahora.
	var reach := _tuning.hang_reach_down
	for value: float in [0.0, reach]:
		_tuning.hang_reach_down = value
		s = _start(Vector3(0, 2.5, -0.6), ActorState.Mode.GROUND)
		grab = -1
		var feet_before := 0.0
		for t in 120:
			feet_before = s.position.y
			var keys := Vector2(0, -0.5) if s.mode == ActorState.Mode.GROUND else Vector2.ZERO
			ActorMotor.step(_actor, s, ActorInput.make(t, keys, 0.0, 0, 0), _tuning, SimClock.TICK_DT)
			if s.mode == ActorState.Mode.HANGING:
				grab = t
				break
		print("%s de espaldas desde arriba, mirándola, alcance %.2f m: %s" % [LOG_PREFIX, value,
				"se agarra en el tick %d, después de caer %.2f m; baja %.2f m" % [grab, 2.5 - feet_before, -_actor.grab_jump.y] if grab >= 0
				else "no se agarra (termina en %s, pies %.3f, z %.2f)" % [ActorState.Mode.keys()[s.mode], s.position.y, s.position.z]])
	_tuning.hang_reach_down = reach

	# 7. Cayendo derecho junto a la pared, desde los pies a 1,4 m.
	for gap: float in [0.05, 0.2, 0.35]:
		s = _start(Vector3(0, 1.4, 0.35 + gap), ActorState.Mode.AIR)
		grab = -1
		for t in 60:
			ActorMotor.step(_actor, s, ActorInput.make(t, Vector2.ZERO, 0.0, 0, 0), _tuning, SimClock.TICK_DT)
			if s.mode == ActorState.Mode.HANGING:
				grab = t
				break
		var want: bool = gap < 0.3
		_check("cayendo a %.2f m de la pared: %s" % [gap, "se agarra" if want else "no se agarra"], (grab >= 0) == want,
				"tick %d, pies %.3f" % [grab, s.position.y])

	# 8. Cayendo desde quieto, pegado a la pared (a hang_distance de la cara),
	# con las manos a una fracción de hang_reach_down por encima del filo.
	for fraction: float in [0.2, 0.5, 0.9, 1.3]:
		var above := fraction * _tuning.hang_reach_down
		s = _start(Vector3(0, hang_feet + above, _tuning.hang_distance), ActorState.Mode.AIR)
		grab = -1
		for t in 60:
			ActorMotor.step(_actor, s, ActorInput.make(t, Vector2.ZERO, 0.0, 0, 0), _tuning, SimClock.TICK_DT)
			if s.mode == ActorState.Mode.HANGING:
				grab = t
				break
		var down := -_actor.grab_jump.y
		var detail := "tick %d, baja %.3f m, pies %.3f, dibujo a %.1f m/s" % [grab, down, s.position.y, _actor.grab_jump_speed]
		if fraction <= 1.0:
			_check("manos %.2f m sobre el filo: se agarra en el acto y baja eso" % above,
					grab == 0 and absf(down - above) < 0.02 and _actor.grab_jump_speed == _tuning.hang_drop_speed, detail)
		else:
			_check("manos %.2f m sobre el filo: se agarra después, sin bajar más que %.2f" % [above, _tuning.hang_reach_down],
					grab > 0 and down <= _tuning.hang_reach_down + 0.01 and absf(s.position.y - hang_feet) < 0.01, detail)

	print("%s RESUMEN: %d comprobaciones, %d fallas" % [LOG_PREFIX, _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
