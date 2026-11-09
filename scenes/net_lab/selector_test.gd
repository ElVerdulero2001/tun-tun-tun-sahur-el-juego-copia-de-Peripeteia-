extends Node

## Prueba del selector de habilidades de la Q (punto 2 del roadmap,
## 2026-11-08). Arranca net_lab.tscn con los argumentos de siempre (--local,
## --host, --client, --sim-…) y además --selector=local, host o client.
##
## Las teclas y el mouse van por el camino de verdad: eventos empujados a la
## ventana (Viewport.push_input), que pasan por _input, la interfaz y
## _unhandled_input como los de un jugador.
##
## - local (un proceso, con --fixed-fps 60): el recorrido entero (abajo).
## - client: el mismo recorrido, con la internet que se le simule. Es la prueba
##   de cierre del roadmap: prende las dos habilidades, apaga solo velocidad y
##   salto y la cámara lenta sigue; Q sin mover el mouse no cambia nada.
## - host: Q ya no toca la adopción y F2 sí; mira que lo que hace el cliente
##   llegue igual (las dos prendidas, después solo la cámara lenta y la del
##   mundo andando); cuando el cliente se va, hace el recorrido él.
##
## El recorrido: Q sin mover; un poco, dentro de la zona muerta; mientras está
## abierto el mouse no llega a la cámara; izquierda prende velocidad y salto;
## derecha, mucho más allá del círculo, prende la cámara lenta (y la del mundo
## arranca); izquierda apaga solo velocidad y salto; Q sin mover; ir y volver
## al centro; Q con el inventario abierto; Tab con el selector abierto; perder
## el foco; la barra rápida con el selector abierto; el 2 del numérico sigue
## andando; derecha apaga la cámara lenta; cerrado, el mouse vuelve a la cámara.

var role := ""
var lab: Node3D
var wheel: AbilityWheel
var ui: InvUI
var _checks := 0
var _failures := 0
var _finishing := false
## Cuántos movimientos del mouse llegaron a _unhandled_input (donde los toma la
## cámara).
var _unhandled_motion := 0


func _ready() -> void:
	var limit := 150.0
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--selector="):
			role = arg.trim_prefix("--selector=")
		elif arg.begins_with("--selector-timeout="):
			limit = arg.trim_prefix("--selector-timeout=").to_float()
	get_tree().create_timer(limit, true, false, true).timeout.connect(func() -> void:
		_failures += 1
		_log("TIEMPO AGOTADO: el recorrido no terminó")
		_finish())
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	add_child(lab)
	wheel = lab.get_node("Hud/SelectorDeHabilidades")
	ui = lab.get_node("Hud/InventarioUI")
	match role:
		"local":
			_local()
		"host":
			_host()
		"client":
			_client()
		_:
			_log("falta --selector")
			get_tree().quit(3)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_unhandled_motion += 1


func _log(text: String) -> void:
	print("[selector:%s] %s" % [role, text])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	_log("%s: %s" % ["ok" if ok else "FALLA", what])


## Sale bien solo si el recorrido llegó al final, con alguna comprobación y sin fallas.
func _finish(completed := false) -> void:
	if _finishing:
		return
	_finishing = true
	if not completed:
		_failures += 1
		_log("FALLA: el recorrido no llegó al final")
	if _checks == 0:
		_failures += 1
		_log("FALLA: no se hizo ninguna comprobación")
	_log("RESULTADO %d comprobaciones, %d fallas" % [_checks, _failures])
	if role == "client":
		lab._session.say_goodbye()
	for i in 10:
		await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _until(condition: Callable, seconds: float) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < limit:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false


func _actor() -> ActorBody:
	return lab._local_actor


func _remote_actor() -> ActorBody:
	for node in lab._actors.get_children():
		if node is ActorBody and node.owner_peer_id != multiplayer.get_unique_id() and not node.is_queued_for_deletion():
			return node
	return null


func _powers() -> int:
	return _actor().state.powers & ActorPowers.ALL


func _world_slow() -> bool:
	return SimClock.world_scale(lab._clock.tick) < 1.0


static func _names(powers: int) -> String:
	var list := ActorPowers.names(powers)
	return ", ".join(list) if not list.is_empty() else "ninguna"


# --- Teclas y mouse, por el camino de verdad -----------------------------------------

func _key(physical: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.keycode = physical
	event.pressed = pressed
	get_viewport().push_input(event)


func _tap(physical: Key) -> void:
	_key(physical, true)
	_key(physical, false)


## El movimiento va en los píxeles de la interfaz (los del selector): sin
## pasarlo por la escala de la ventana, que sin pantalla es otra.
func _move(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = get_viewport().get_visible_rect().size / 2.0
	get_viewport().push_input(event, true)


## Mantiene Q, mueve el mouse en esos pasos y suelta Q. Devuelve el sector que
## estaba marcado justo antes de soltar.
func _select(moves: Array) -> int:
	_key(KEY_Q, true)
	await get_tree().process_frame
	for relative: Vector2 in moves:
		_move(relative)
		await get_tree().process_frame
	var hovered := wheel.hovered_sector()
	_key(KEY_Q, false)
	return hovered


## Elige con el selector y mira que, unos ticks después, el personaje propio
## tenga justo esas habilidades prendidas.
func _select_expect(moves: Array, sector: int, powers: int, what: String) -> void:
	var choices := wheel.choices
	var hovered := await _select(moves)
	_check(hovered == sector and not wheel.is_open, "%s: marca %s y se cierra" % [what,
			wheel.SECTORS[sector]["name"] if sector >= 0 else "el centro"])
	_check(wheel.choices == choices + (1 if sector >= 0 else 0), "%s: %s" % [what,
			"elige una vez" if sector >= 0 else "no elige nada"])
	await _ticks(6)
	_check(_powers() == powers, "%s: quedan prendidas %s (se ve: %s)" % [what, _names(powers), _names(_powers())])


# --- El recorrido ---------------------------------------------------------------------

func _route() -> void:
	var left := Vector2(-140, 12)
	var far_right := Vector2(900, -60)
	_check(_powers() == 0 and not wheel.is_open, "empieza sin habilidades y con el selector cerrado")
	var ability := lab.ability_presses as int
	var power := lab.power_presses as int

	# Q sin mover el mouse.
	var opens := wheel.opens
	_key(KEY_Q, true)
	await get_tree().process_frame
	_check(wheel.is_open and wheel.opens == opens + 1 and wheel.hovered_sector() == -1, "Q abre el selector, en el centro")
	_key(KEY_Q, false)
	_check(not wheel.is_open, "soltar Q lo cierra")
	await _ticks(6)
	_check(_powers() == 0 and lab.ability_presses == ability and lab.power_presses == power,
			"Q sin mover el mouse no cambia nada (ni los contadores)")

	await _select_expect([Vector2(15, -10), Vector2(10, 8)], -1, 0, "un poco, dentro de la zona muerta")

	# Mientras está abierto, el mouse no llega a la cámara.
	var camera: LabCamera = lab._camera
	var yaw := camera.yaw
	var pitch := camera.pitch
	var reached := _unhandled_motion
	_key(KEY_Q, true)
	_move(Vector2(-60, 0))
	_move(Vector2(-60, 0))
	_check(_unhandled_motion == reached and camera.yaw == yaw and camera.pitch == pitch,
			"con el selector abierto el mouse no llega a la cámara (no gira)")
	_check(wheel.hovered_sector() == 0, "a la izquierda marca velocidad y salto")
	_key(KEY_Q, false)
	await _ticks(6)
	_check(_powers() == ActorPowers.BOOST and lab.power_presses == (power + 1) & 0xFF and lab.ability_presses == ability,
			"soltar Q a la izquierda prende velocidad y salto, con el contador del 2 del numérico")

	await _select_expect([far_right, far_right], 1, ActorPowers.BOOST | ActorPowers.SLOW,
			"derecha, mucho más allá del círculo")
	_check(wheel.pointer().length() <= wheel.dead_zone * wheel.reach + 0.01, "el movimiento se junta hasta un tope")
	_check(await _until(_world_slow, 3.0), "arranca la cámara lenta del mundo")
	await _ticks(60)

	# La prueba de cierre: se apaga solo velocidad y salto.
	await _select_expect([left], 0, ActorPowers.SLOW, "izquierda otra vez")
	await _ticks(60)
	_check(_powers() == ActorPowers.SLOW and _world_slow(), "un segundo después la cámara lenta sigue, la propia y la del mundo")
	ability = lab.ability_presses
	power = lab.power_presses
	_key(KEY_Q, true)
	await get_tree().process_frame
	_key(KEY_Q, false)
	await _ticks(60)
	_check(_powers() == ActorPowers.SLOW and _world_slow() and lab.ability_presses == ability and lab.power_presses == power,
			"Q sin mover el mouse deja las dos como estaban")

	# Ir y volver: el tope hace que volver al centro tarde lo mismo que haber ido.
	await _select_expect([left, left, Vector2(wheel.dead_zone * wheel.reach, 0)], -1, ActorPowers.SLOW,
			"a la izquierda y de vuelta al centro")
	await _reverse_without_release(left)

	# Con el inventario abierto, Q no lo abre.
	_tap(KEY_TAB)
	await get_tree().process_frame
	_check(ui.is_open, "Tab abre el inventario")
	_key(KEY_Q, true)
	await get_tree().process_frame
	_check(not wheel.is_open, "con el inventario abierto, Q no abre el selector")
	_move(Vector2(-200, 0))
	_key(KEY_Q, false)
	_tap(KEY_TAB)
	await _ticks(6)
	_check(not ui.is_open and _powers() == ActorPowers.SLOW, "Tab lo cierra y no cambió nada")

	# Tab con el selector abierto: se abre el inventario y el selector se cierra sin elegir.
	_key(KEY_Q, true)
	_move(left)
	_tap(KEY_TAB)
	await get_tree().process_frame
	_check(ui.is_open and not wheel.is_open, "Tab con el selector abierto abre el inventario y cierra el selector")
	_key(KEY_Q, false)
	_tap(KEY_TAB)
	await _ticks(6)
	_check(not ui.is_open and _powers() == ActorPowers.SLOW, "soltar Q después no cambia nada")

	# Perder el foco de la ventana: el soltar no llegaría, se cierra sin elegir.
	_key(KEY_Q, true)
	_move(left)
	wheel.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not wheel.is_open, "perder el foco cierra el selector")
	_key(KEY_Q, false)
	await _ticks(6)
	_check(_powers() == ActorPowers.SLOW, "y no cambió nada")

	# La barra rápida sigue andando con el selector abierto.
	var slot := _empty_slot()
	if slot < 0:
		_log("todos los accesos de la barra tienen algo: no se prueba la barra")
	else:
		var key: Key = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0][slot]
		var before: int = ui._toast_until
		_key(KEY_Q, true)
		await get_tree().process_frame
		_tap(key)
		_check(wheel.is_open and ui._toast_until > before and ui._toast.contains("vacío"),
				"con el selector abierto, el %s de la barra rápida le llega al inventario" % InvUI.KEYS[slot])
		_key(KEY_Q, false)
		await _ticks(6)
		_check(_powers() == ActorPowers.SLOW, "y soltar Q en el centro no cambia nada")

	# El 2 del numérico sigue andando.
	_tap(KEY_KP_2)
	await _ticks(6)
	_check(_powers() == (ActorPowers.BOOST | ActorPowers.SLOW), "el 2 del numérico sigue prendiendo velocidad y salto")
	_tap(KEY_KP_2)
	await _ticks(6)
	_check(_powers() == ActorPowers.SLOW, "y apagándolo")

	await _select_expect([far_right], 1, 0, "derecha apaga la cámara lenta")
	_check(await _until(func() -> bool: return not _world_slow(), 3.0), "termina la cámara lenta del mundo")

	# Cerrado, el mouse vuelve a la cámara.
	reached = _unhandled_motion
	_move(Vector2(30, 0))
	_check(_unhandled_motion == reached + 1, "con el selector cerrado, el mouse vuelve a llegar a la cámara")


## A la izquierda y, sin soltar Q, mucho a la derecha: marca la derecha (el
## tope hace que cambiar de lado no tarde). Se suelta en el centro para no
## cambiar nada.
func _reverse_without_release(left: Vector2) -> void:
	_key(KEY_Q, true)
	_move(left)
	_move(left)
	_move(left)
	_check(wheel.hovered_sector() == 0, "ida y vuelta: primero marca la izquierda")
	_move(Vector2(wheel.dead_zone * wheel.reach * 2.0, 0))
	_check(wheel.hovered_sector() == 1, "ida y vuelta: sin soltar, a la derecha marca la derecha")
	_move(Vector2(-wheel.dead_zone * wheel.reach, 0))
	_check(wheel.hovered_sector() == -1, "ida y vuelta: y de nuevo en el centro")
	_key(KEY_Q, false)
	await _ticks(6)
	_check(_powers() == ActorPowers.SLOW, "ida y vuelta: soltar en el centro no cambia nada")


func _empty_slot() -> int:
	var loadout: InvLoadout = lab._inventory.replica.loadout
	if loadout == null:
		return -1
	for i in loadout.hotbar.size():
		if loadout.hotbar[i] == 0:
			return i
	return -1


# --- Jugando solo ---------------------------------------------------------------------

func _local() -> void:
	_check(await _until(func() -> bool: return _actor() != null and lab._inventory.replica.loadout != null, 10.0),
			"aparece el personaje propio")
	await _ticks(20)
	await _route()
	_finish(true)


# --- Host -----------------------------------------------------------------------------

func _client_ready() -> bool:
	var client := _remote_actor()
	return client != null and lab._inventory.authority.is_welcomed(client.owner_peer_id)


func _host() -> void:
	_check(await _until(func() -> bool: return _actor() != null, 10.0), "aparece el personaje propio")
	# Q ya no toca la adopción; F2 sí (solo en el host).
	var adoption: bool = lab._adoption.enabled
	_key(KEY_Q, true)
	_key(KEY_Q, false)
	_check(lab._adoption.enabled == adoption, "Q ya no prende ni apaga la adopción")
	_tap(KEY_F2)
	_check(lab._adoption.enabled == not adoption, "F2 prende o apaga la adopción")
	_tap(KEY_F2)
	_check(lab._adoption.enabled == adoption, "F2 otra vez la deja como estaba")
	_check(await _until(_client_ready, 30.0), "el cliente entra")
	var both := ActorPowers.BOOST | ActorPowers.SLOW
	_check(await _until(func() -> bool: return _remote_actor() != null and _remote_actor().state.powers == both, 40.0),
			"llegan las dos habilidades del cliente prendidas")
	_check(await _until(func() -> bool: return _remote_actor() != null and _remote_actor().state.powers == ActorPowers.SLOW, 40.0),
			"después le queda solo la cámara lenta")
	await _ticks(30)
	_check(_remote_actor() != null and _remote_actor().state.powers == ActorPowers.SLOW and _world_slow(),
			"en el host la cámara lenta del cliente sigue y la del mundo anda")
	# El cliente sigue con su recorrido y al final apaga la suya.
	_check(await _until(func() -> bool: return _remote_actor() == null or _remote_actor().state.powers == 0, 60.0),
			"al final el cliente las apaga")
	while _remote_actor() != null:
		await get_tree().physics_frame
	await _ticks(30)
	_check(not _world_slow(), "sin pedidos, la cámara lenta del mundo terminó")
	_log("ahora el recorrido lo hace el host")
	await _route()
	_finish(true)


# --- Cliente --------------------------------------------------------------------------

func _client_has_state() -> bool:
	return lab._inventory.replica.has_state and _actor() != null and lab._inventory.replica.loadout != null


func _client() -> void:
	_check(await _until(_client_has_state, 20.0), "recibe el estado inicial del host")
	await _ticks(30)
	await _route()
	await _ticks(30)
	_log("correcciones %d, coincidencias %d" % [lab._prediction.corrections, lab._prediction.matches])
	_finish(true)
