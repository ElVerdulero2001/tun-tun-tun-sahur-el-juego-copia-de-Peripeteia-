extends Node

## Prueba de los objetos sueltos con física (desde el 2026-11-14,
## docs/net/prompt_claude_objetos_dinamicos.md y docs/net/objetos_fisicos.md).
## El laboratorio entero, con la pista de física de la zona de inventario.
##
## Sin argumentos, jugando solo:
##
## - las preferencias: las de fábrica, guardar y leer, y los dos esquemas de
##   botones con los dos modos de sostener (sin doble suelta ni doble
##   lanzamiento; sin objeto no lanza; después de lanzar no agarra otra cosa);
## - la rueda y el botón central: sin cámara, con límites, los tres ejes de giro
##   y el regreso a mirar; sin objeto, la rueda vuelve a la cámara; abrir el
##   inventario, Opciones o perder la ventana sueltan sin estados pegados;
## - la tabla larga: agarrada por una punta, sin salto al centro, girada
##   alrededor de ese punto, metida a lo largo por la ranura del muro, y
##   cruzada contra el muro, que la frena y no la deja pasar;
## - la física: reposa, choca con otro objeto, cae de la mesa, lanzada contra la
##   pared de 2 cm no la atraviesa, contra una pared se suelta sola, lejos
##   también, y al morir;
## - el inventario: soltar en el aire, soltar una parte, E sobre lo sostenido
##   (entero y en parte);
## - el selector: un objeto girando se elige por el punto que se ve; un hueco
##   no es sólido; lo de adelante tapa lo de atrás, en primera y en tercera
##   persona;
## - lo metido en el piso: nada queda metido al caer de 1 m ni debajo de una
##   pila apretada con la mano, y lo que igual arranca metido se agarra y se
##   saca (_sunk_and_pressed);
## - lo tapado: lo sostenido detrás de una pared se suelta solo («no se ve»), y
##   la regla mira el punto agarrado (_hidden_release);
## - la medición del selector con muchos objetos lejos, contra la cuenta que
##   recorre todos, con el costo de la física y de lo que viaja, y que al
##   sacarlos no queda nada en el índice ni en los cuerpos.
##
## Con --fisica-pair=host, a o b (y los argumentos de red de siempre), en red:
## ver _pair_host, _pair_a y _pair_b. Con --fisica-detalle escribe cada
## comprobación.
##
## Para correrla: --headless --fixed-fps 60 --path . --scene
## res://scenes/net_lab/inventario/pruebas/inv_fisica_test.tscn

const ZONE := Vector3(37, 0, 13)
## La pista de física, dentro de la zona de inventario.
const TRACK := ZONE + Vector3(0, 0, -12)
const SLOT := TRACK + Vector3(-1.5, 1.25, -2.5)
const WALL_Z := SLOT.z
const THIN_X := TRACK.x + 4.5
const TABLE_TOP := 1.0
const TABLE_EDGE_X := TRACK.x + 2.0 - 0.8
const PLANK_AT := TRACK + Vector3(-1.5, 0, 0.8)
const CROSS_PLANK_AT := TRACK + Vector3(-3.5, 0, 2.2)
const THROW_GRENADE_AT := TRACK + Vector3(2.8, 0, -0.5)
const EDGE_GRENADE_AT := TRACK + Vector3(1.35, 1, 3.2)
const SCREWS_AT := TRACK + Vector3(2.1, 1, 3.2)
const ROW_FRONT_AT := TRACK + Vector3(-4.5, 1.55, 3.2)
const ROW_MIDDLE_AT := TRACK + Vector3(-4.5, 1.55, 3.55)
const ROW_BACK_AT := TRACK + Vector3(-4.5, 1.55, 3.95)
## Se puede elegir una carpeta escribible al correr en un entorno restringido,
## sin tocar las preferencias reales del jugador: --fisica-prefs-path=RUTA.
var prefs_path := "user://prueba_fisica_opciones.cfg"
const Op := InvProtocol.Op
const Mano := preload("res://scenes/net_lab/inventario/pruebas/inv_mano_de_prueba.gd")

var role := ""
var verbose := false
## Con --fisica-solo=SECCIÓN, jugando solo, corre solo esa (para depurar).
var only := ""
var lab: Node3D
var net: InvNet
var ui: InvUI
var hands: InvHands
var camera: LabCamera
var view_camera: Camera3D
var actor: ActorBody
var catalog: InvCatalog
var _answers := {}
var _checks := 0
var _failures := 0
var _finishing := false
## La granada de lanzar (desde el 2026-11-15 es redonda de verdad y rueda: la
## prueba la vuelve a poner en su lugar antes de cada parte, _throw_grenade).
var _grenade := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--fisica-pair="):
			role = arg.trim_prefix("--fisica-pair=")
		elif arg.begins_with("--fisica-solo="):
			only = arg.trim_prefix("--fisica-solo=")
		elif arg == "--fisica-detalle":
			verbose = true
		elif arg.begins_with("--fisica-prefs-path="):
			prefs_path = arg.trim_prefix("--fisica-prefs-path=")
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func() -> void:
		_failures += 1
		_log("TIEMPO AGOTADO: el recorrido no terminó")
		_finish())
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	add_child(lab)
	net = lab.get_node("Inventario")
	ui = lab.get_node("Hud/InventarioUI")
	camera = lab.get_node("CameraRig")
	view_camera = camera.get_node("SpringArm/Camera")
	hands = lab._hands
	hands.ignore_mouse_mode = true
	hands.prefs = InvHandPrefs.new()
	hands.prefs_path = prefs_path
	catalog = net.catalog
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	match role:
		"":
			_solo()
		"host":
			_pair_host()
		"a":
			_pair_a()
		"b":
			_pair_b()
		"mano_host":
			_mano_host()
		"mano_cliente":
			_mano_cliente()
		_:
			_log("--fisica-pair tiene que ser host, a, b, mano_host o mano_cliente")
			get_tree().quit(3)


# --- Herramientas ------------------------------------------------------------------

func _log(text: String) -> void:
	print("[inv_fisica%s] %s" % [":" + role if role != "" else "", text])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		_log("FALLA: " + what)
	elif verbose:
		_log("ok: " + what)


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs_path))
	_log("%d comprobaciones, %d fallas" % [_checks, _failures])
	if role == "a" or role == "b" or role == "mano_cliente":
		lab._session.say_goodbye()
		await _ticks(10)
	get_tree().quit(1 if _failures > 0 else 0)


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _until(condition: Callable, seconds: float) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < limit:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func _teleport(position: Vector3, yaw: float) -> void:
	var state := actor.state
	state.position = position
	state.velocity = Vector3.ZERO
	state.facing_yaw = yaw
	state.mode = ActorState.Mode.GROUND
	state.on_floor = true
	state.base_id = 0
	if role == "host":
		state.epoch += 1
	state.quantize()
	actor.apply_state(state)
	actor.teleported()
	camera.yaw = yaw
	await _ticks(3)
	await _frames(2)


## Pone al personaje ahí, sin esperar ticks (para moverlo de a poco).
func _place_actor(position: Vector3) -> void:
	var state := actor.state
	state.position = position
	state.velocity = Vector3.ZERO
	state.mode = ActorState.Mode.GROUND
	state.on_floor = true
	state.quantize()
	actor.apply_state(state)


func _set_first_person(first: bool) -> void:
	camera._wanted_zoom = 0.0 if first else 1.0
	camera._zoom = camera._wanted_zoom
	await _frames(3)


## Gira la cámara para que el centro de la pantalla pase por ese punto.
func _aim(point: Vector3) -> void:
	for i in 6:
		var from := camera.global_position if i == 0 else view_camera.global_position
		var direction := (point - from).normalized()
		camera.yaw = atan2(-direction.x, -direction.z)
		camera.pitch = asin(clampf(direction.y, -1.0, 1.0))
		await _frames(2)


## La granada de lanzar, puesta quieta en `spot` (la primera vez se busca en su
## marcador), o 0 si no está.
func _throw_grenade(spot: Vector3) -> int:
	if _grenade == 0 or _body(_grenade) == null:
		_grenade = _uid_near(THROW_GRENADE_AT, &"granada", 0.3)
	var body := _body(_grenade)
	if body == null:
		return 0
	if body.global_position.distance_to(spot) > 0.05:
		body.global_transform = Transform3D(Basis.IDENTITY, spot + Vector3(0, 0.02, 0))
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		net.bodies.wake(_grenade)
		await _ticks(2)
	await _rested(_grenade)
	return _grenade


## El objeto del mundo más cerca de `spot` de ese tipo (o cualquiera), a menos de `within`.
func _uid_near(spot: Vector3, def_id := &"", within := 0.3) -> int:
	var best := 0
	var best_d := within
	var world := net.authority.world if net.authority != null else net.replica.world
	for uid: int in world:
		var stack: InvStack = world[uid]["stack"]
		if def_id != &"" and stack.def_id != def_id:
			continue
		var d := (world[uid]["pos"] as Vector3).distance_to(spot)
		if d < best_d:
			best_d = d
			best = uid
	return best


func _body(uid: int) -> InvWorldItem:
	return net.bodies.view(uid)


func _place_of(uid: int) -> Transform3D:
	var view := _body(uid)
	return view.global_transform if view != null else Transform3D.IDENTITY


## La caja del modelo de un objeto en el mundo, con su giro.
func _box_of(uid: int) -> AABB:
	var view := _body(uid)
	return view.global_transform * view.interact_focus().bounds if view != null else AABB()


## Un botón del mouse, como lo manda Godot. Devuelve si alguien se lo quedó.
## Va fuera de la pantalla: sin ventana el mouse no está capturado y, sobre el
## HUD, se lo quedaría la interfaz (jugando, con el mouse capturado, la
## interfaz no recibe el mouse).
func _mouse_button(button: MouseButton, pressed: bool, shift := false) -> bool:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.shift_pressed = shift
	event.factor = 1.0
	event.position = Vector2(-5000, -5000)
	event.global_position = event.position
	var taken := hands.taken
	get_viewport().push_input(event)
	return hands.taken > taken


func _mouse_motion(relative: Vector2, shift := false) -> bool:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.shift_pressed = shift
	event.position = Vector2(-5000, -5000)
	event.global_position = event.position
	var taken := hands.taken
	get_viewport().push_input(event)
	return hands.taken > taken


func _press(button: MouseButton) -> void:
	_mouse_button(button, true)
	await _ticks(1)


func _release(button: MouseButton) -> void:
	_mouse_button(button, false)
	await _ticks(1)


func _grab_button() -> MouseButton:
	return MOUSE_BUTTON_XBUTTON1 if hands.prefs.buttons == InvHandPrefs.Buttons.SIDE else MOUSE_BUTTON_RIGHT


func _throw_button() -> MouseButton:
	return MOUSE_BUTTON_XBUTTON2 if hands.prefs.buttons == InvHandPrefs.Buttons.SIDE else MOUSE_BUTTON_LEFT


## Agarra lo que está mirando con el botón del esquema (y lo suelta enseguida
## si es mantener, cuando `keep_pressed` es falso).
func _grab_aimed() -> bool:
	var before := hands.grabs
	await _press(_grab_button())
	await _ticks(4)
	return hands.grabs > before and hands.is_holding()


## Espera a que el host confirme el agarre que está en viaje.
func _wait_confirmed() -> void:
	await _until(_confirmed, 3.0)


func _confirmed() -> bool:
	if hands.held_uid() == 0:
		return false
	if net.authority != null:
		return net.authority.holder_of(hands.held_uid()) == actor.owner_peer_id
	return hands._confirmed


func _rested(uid: int) -> void:
	await _until(func() -> bool: return Mano.rested(net, uid), 8.0)


# --- Jugando solo --------------------------------------------------------------------

func _solo() -> void:
	await get_tree().process_frame
	lab._start(0)
	for i in 120:
		await get_tree().physics_frame
		if net.replica.own != null and is_instance_valid(lab._local_actor):
			break
	actor = lab._local_actor
	_check(actor != null and net.replica.own != null, "jugando solo: hay personaje e inventario")
	if actor == null:
		_finish()
		return
	await _set_first_person(true)
	await _ticks(10)
	if only != "":
		await call(only)
		_finish()
		return
	await _spawned_items_rest()
	_prefs_saved()
	for buttons in [InvHandPrefs.Buttons.PRIMARY, InvHandPrefs.Buttons.SIDE]:
		for mode in [InvHandPrefs.Mode.TOGGLE, InvHandPrefs.Mode.HOLD]:
			await _buttons_and_modes(buttons, mode)
	hands.prefs = InvHandPrefs.new()
	await _wheel_and_turns()
	await _ui_takes_mouse()
	await _plank_tip()
	await _plank_through_slot()
	await _plank_across_slot()
	await _physics_basics()
	await _limits()
	await _inventory_and_hands()
	await _moving_selection()
	await _holes_and_occlusion()
	await _bodies_prepared()
	await _hitbox_rules()
	await _stack_wake()
	await _sunk_and_pressed()
	await _hidden_release()
	await _drop_toward_camera()
	await _measure()
	_finish()


## Lo colocado en el mapa arranca dormido donde está el marcador, también
## girado, y no se mueve solo.
func _spawned_items_rest() -> void:
	var plank := _uid_near(PLANK_AT, &"tabla_larga")
	var cross := _uid_near(CROSS_PLANK_AT, &"tabla_larga")
	_check(plank != 0 and cross != 0, "las dos tablas de la pista están en el mundo")
	if plank == 0 or cross == 0:
		return
	await _ticks(30)
	var place := _place_of(cross)
	_check(place.origin.distance_to(CROSS_PLANK_AT) < 0.001 and absf(place.basis.z.dot(Vector3.RIGHT)) > 0.999,
			"la tabla cruzada arranca girada como su marcador (y quieta): %s" % place.basis.z)
	_check(_body(plank).sleeping and _body(cross).sleeping and _place_of(plank).origin.distance_to(PLANK_AT) < 0.001,
			"y las dos duermen donde las pusieron")
	var edge := _uid_near(EDGE_GRENADE_AT, &"granada")
	_check(edge != 0 and _place_of(edge).origin.distance_to(EDGE_GRENADE_AT) < 0.001, "la granada del borde de la mesa no se cae sola")


func _prefs_saved() -> void:
	var fresh := InvHandPrefs.new()
	_check(fresh.buttons == InvHandPrefs.Buttons.PRIMARY and fresh.mode == InvHandPrefs.Mode.TOGGLE,
			"de fábrica: botones principales y alternar")
	_check(fresh.actions() == [&"objeto_agarrar", &"objeto_lanzar"], "principales: agarrar y lanzar son las acciones de siempre")
	var side := InvHandPrefs.new()
	side.buttons = InvHandPrefs.Buttons.SIDE
	side.mode = InvHandPrefs.Mode.HOLD
	_check(side.save(prefs_path) == OK, "se guardan en un archivo de esta PC")
	var back := InvHandPrefs.load_saved(prefs_path)
	_check(back.buttons == InvHandPrefs.Buttons.SIDE and back.mode == InvHandPrefs.Mode.HOLD, "y se leen igual: %s" % back.describe())
	_check(InvHandPrefs.load_saved("user://no_existe_este_archivo.cfg").describe() == "principales, alternar",
			"sin archivo, las de fábrica")
	_check(InputMap.has_action(&"objeto_agarrar_lateral") and InputMap.action_get_events(&"objeto_agarrar_lateral").any(
			func(e: InputEvent) -> bool: return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_XBUTTON1),
			"el lateral trasero es MOUSE_BUTTON_XBUTTON1 (8), no la rueda")
	_check(InputMap.action_get_events(&"objeto_alejar").any(
			func(e: InputEvent) -> bool: return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_WHEEL_UP),
			"la rueda para arriba aleja")


## Un esquema de botones con un modo de sostener, sobre la granada para lanzar.
func _buttons_and_modes(buttons: int, mode: int) -> void:
	var fresh := InvHandPrefs.new()
	fresh.buttons = buttons as InvHandPrefs.Buttons
	fresh.mode = mode as InvHandPrefs.Mode
	hands.set_prefs(fresh)
	var what := fresh.describe()
	var grenade := await _throw_grenade(THROW_GRENADE_AT)
	if grenade == 0:
		_check(false, "%s: hay una granada para probar" % what)
		return
	await _rested(grenade)
	var spot := _place_of(grenade).origin
	await _teleport(spot + Vector3(-1.0, 0, 0), -PI / 2.0)
	await _aim(_box_of(grenade).get_center())
	var grab := _grab_button()
	var throw := _throw_button()
	# Sin objeto, el botón de lanzar no hace nada.
	var thrown := hands.throws
	await _press(throw)
	await _release(throw)
	_check(hands.throws == thrown and not hands.is_holding(), "%s: sin objeto, lanzar no hace nada" % what)
	# Agarrar y soltar sin lanzar.
	var released := hands.releases
	await _press(grab)
	await _ticks(3)
	_check(hands.is_holding() and hands.held_uid() == grenade, "%s: el botón de agarrar lo agarra" % what)
	await _wait_confirmed()
	_check(net.authority.holder_of(grenade) == actor.owner_peer_id, "%s: el host dice que lo tiene" % what)
	if mode == InvHandPrefs.Mode.TOGGLE:
		await _release(grab)
		_check(hands.is_holding(), "%s: alternar: soltar el botón no lo suelta" % what)
		await _press(grab)
		await _release(grab)
	else:
		await _ticks(10)
		_check(hands.is_holding(), "%s: mantener: mientras está apretado lo sostiene" % what)
		await _release(grab)
	await _ticks(4)
	_check(not hands.is_holding() and hands.releases == released + 1 and hands.throws == thrown,
			"%s: lo suelta una vez y sin lanzar" % what)
	_check(net.authority.holder_of(grenade) == 0, "%s: el host lo soltó" % what)
	var velocity := _body(grenade).linear_velocity.length()
	_check(velocity < 2.0, "%s: soltado no sale disparado (%.2f m/s)" % [what, velocity])
	await _rested(grenade)
	# Agarrar y lanzar.
	await _aim(_box_of(grenade).get_center())
	await _press(grab)
	await _wait_confirmed()
	_check(hands.is_holding(), "%s: lo vuelve a agarrar" % what)
	# Mirando un poco para arriba (no contra el piso), lo levanta y lo lanza.
	camera.pitch = 0.15
	await _ticks(12)
	released = hands.releases
	_mouse_button(throw, true)
	# Lo más rápido que va en los ticks siguientes (puede chocar enseguida).
	var fastest := 0.0
	for i in 6:
		await _ticks(1)
		fastest = maxf(fastest, _body(grenade).linear_velocity.length())
	_mouse_button(throw, false)
	_check(not hands.is_holding() and hands.throws == thrown + 1, "%s: lanzar lo suelta y lo lanza una vez" % what)
	var expected := net.tuning.throw_impulse / net.tuning.item_mass
	_check(fastest > expected * 0.7, "%s: sale lanzado (hasta %.1f m/s; el impulso da %.1f)" % [what, fastest, expected])
	await _release(grab)
	await _ticks(4)
	_check(hands.releases == released and hands.throws == thrown + 1, "%s: después de lanzar, soltar el botón no hace otra cosa" % what)
	_check(not hands.is_holding(), "%s: y no agarra otra cosa hasta otra pulsación" % what)
	await _rested(grenade)


func _wheel_and_turns() -> void:
	var grenade := await _throw_grenade(THROW_GRENADE_AT)
	if grenade == 0:
		_check(false, "hay una granada para la rueda")
		return
	await _rested(grenade)
	await _teleport(_place_of(grenade).origin + Vector3(-1.0, 0, 0), -PI / 2.0)
	# Sin objeto: la rueda es de la cámara y el botón central no hace nada.
	_check(not _mouse_button(MOUSE_BUTTON_WHEEL_UP, true), "sin objeto, la rueda llega a la cámara")
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, false)
	camera._wanted_zoom = 0.0
	_check(_mouse_button(MOUSE_BUTTON_MIDDLE, true) and not hands.is_rotating(), "sin objeto, el botón central no hace nada (y no llega a la cámara)")
	_mouse_button(MOUSE_BUTTON_MIDDLE, false)
	await _aim(_box_of(grenade).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	_check(hands.is_holding(), "la agarra para la rueda")
	var zoom := camera._wanted_zoom
	var start := hands._distance
	_check(_mouse_button(MOUSE_BUTTON_WHEEL_UP, true), "con objeto, la rueda la usa la mano")
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, false)
	_check(is_equal_approx(hands._distance, minf(start + net.tuning.hold_wheel_step, net.tuning.hold_max_distance))
			and camera._wanted_zoom == zoom, "rueda para arriba: la aleja un paso (%.2f → %.2f m) y la cámara no cambia" % [start, hands._distance])
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, false)
	_check(is_equal_approx(hands._distance, start) or start >= net.tuning.hold_max_distance, "rueda para abajo: la acerca")
	for i in 60:
		_mouse_button(MOUSE_BUTTON_WHEEL_UP, true)
	_check(is_equal_approx(hands._distance, net.tuning.hold_max_distance), "no pasa de Hold Max Distance (%.2f m)" % hands._distance)
	for i in 80:
		_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	_check(is_equal_approx(hands._distance, net.tuning.hold_min_distance), "ni de Hold Min Distance (%.2f m)" % hands._distance)
	net.tuning.hold_wheel_inverted = true
	_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true)
	_check(hands._distance > net.tuning.hold_min_distance, "con Hold Wheel Inverted, la rueda para abajo aleja")
	net.tuning.hold_wheel_inverted = false
	hands._distance = 1.0
	# El botón central gira; el mouse no mueve la cámara mientras tanto.
	var yaw := camera.yaw
	var pitch := camera.pitch
	_check(not _mouse_motion(Vector2(10, 0)), "sin el central, el mouse llega a la cámara")
	camera.yaw = yaw
	_check(_mouse_button(MOUSE_BUTTON_MIDDLE, true) and hands.is_rotating(), "el central empieza a girar")
	var view := Basis(Vector3.UP, camera.yaw) * Basis(Vector3.RIGHT, camera.pitch)
	var axes := [["de costado", Vector2(40, 0), false, view.y], ["para arriba o abajo", Vector2(0, 40), false, view.x],
			["con Shift, de costado", Vector2(40, 0), true, view.z]]
	for axis: Array in axes:
		# Llegado por Godot (el movimiento viene escalado por el estiramiento de
		# la pantalla, como el de la cámara): lo usa la mano y no la cámara.
		var kept_before := hands._rotation
		var handled := _mouse_motion(axis[1], axis[2])
		_check(handled and camera.yaw == yaw and camera.pitch == pitch and hands._rotation != kept_before,
				"%s: lo usa la mano, gira, y la cámara no gira" % axis[0])
		# La cuenta, con esos mismos píxeles: el eje y los grados.
		var before := Basis(Vector3.UP, camera.yaw) * Basis(hands._rotation)
		hands._rotate_by(axis[1], axis[2])
		var after := Basis(Vector3.UP, camera.yaw) * Basis(hands._rotation)
		var turn := (after * before.inverse()).get_rotation_quaternion()
		var turn_axis := turn.get_axis().normalized()
		var angle := turn.get_angle()
		_check(absf(turn_axis.dot(axis[3])) > 0.99 and absf(rad_to_deg(angle) - 40.0 * net.tuning.hold_rotate_sensitivity) < 0.2,
				"%s: 40 píxeles giran %.1f° alrededor del eje de la vista que corresponde (%s)" % [axis[0], rad_to_deg(angle), turn_axis])
	_check(_mouse_button(MOUSE_BUTTON_MIDDLE, false) and not hands.is_rotating(), "soltar el central deja de girar")
	var kept := hands._rotation
	_check(not _mouse_motion(Vector2(10, 5)) and hands._rotation == kept, "y el mouse vuelve a mirar")
	camera.yaw = yaw
	camera.pitch = pitch
	# Perder la ventana con el central apretado: suelta y no queda girando.
	_mouse_button(MOUSE_BUTTON_MIDDLE, true)
	hands.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _ticks(2)
	_check(not hands.is_holding() and not hands.is_rotating(), "perder la ventana suelta lo que sostiene y deja de girar")
	_mouse_button(MOUSE_BUTTON_MIDDLE, false)
	await _ticks(4)
	_check(net.authority.holder_of(grenade) == 0, "y el host lo soltó")


## Abrir el inventario, Opciones o el selector de la Q sueltan sin lanzar.
func _ui_takes_mouse() -> void:
	var grenade := await _throw_grenade(THROW_GRENADE_AT)
	if grenade == 0:
		return
	var options: LabOptions = lab._options
	var what_opens := [["el inventario", func() -> void: ui.open(), func() -> void: ui.close()],
			["Opciones", func() -> void: options.open(), func() -> void: options.close()]]
	for entry: Array in what_opens:
		await _rested(grenade)
		await _teleport(_place_of(grenade).origin + Vector3(-1.0, 0, 0), -PI / 2.0)
		await _aim(_box_of(grenade).get_center())
		await _press(MOUSE_BUTTON_RIGHT)
		await _release(MOUSE_BUTTON_RIGHT)
		await _wait_confirmed()
		var thrown := hands.throws
		(entry[1] as Callable).call()
		await _ticks(4)
		_check(not hands.is_holding() and hands.throws == thrown, "abrir %s lo suelta sin lanzar" % entry[0])
		_check(net.authority.holder_of(grenade) == 0, "abrir %s: el host lo soltó" % entry[0])
		var held := hands.grabs
		_mouse_button(MOUSE_BUTTON_RIGHT, true)
		_mouse_button(MOUSE_BUTTON_RIGHT, false)
		_check(hands.grabs == held, "con %s abierto, el botón no agarra" % entry[0])
		(entry[2] as Callable).call()
		await _ticks(2)
	# Cambiar las preferencias con algo en la mano lo suelta.
	await _rested(grenade)
	await _aim(_box_of(grenade).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	hands.set_prefs(InvHandPrefs.new())
	await _ticks(3)
	_check(not hands.is_holding() and net.authority.holder_of(grenade) == 0, "cambiar las preferencias lo suelta")


## La tabla larga, agarrada por la punta cercana: el punto agarrado es la punta,
## no el centro, y no salta; girada, gira alrededor de ese punto.
func _plank_tip() -> void:
	var plank := _uid_near(PLANK_AT, &"tabla_larga")
	if plank == 0:
		_check(false, "está la tabla larga")
		return
	var place := _place_of(plank)
	# Parado al sur de la tabla, mirando al norte, a la punta de su lado.
	await _teleport(PLANK_AT + Vector3(0, 0, 1.75), 0.0)
	var tip := place * Vector3(0, 0.04, 0.74)
	await _aim(tip)
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	_check(hands.held_uid() == plank, "agarra la tabla larga por la punta")
	var anchor := hands._anchor
	_check(absf(anchor.z - 0.74) < 0.05 and absf(anchor.x) < 0.07, "el punto agarrado es la punta tocada, no el centro: %s" % anchor)
	var held: Dictionary = net.bodies.holds().get(plank, {})
	_check(not held.is_empty() and (held["anchor"] as Vector3).distance_to(anchor) < 0.01, "el host agarra por el mismo punto: %s" % held.get("anchor"))
	await _ticks(20)
	var now := _place_of(plank)
	_check((now * anchor).distance_to(tip) < 0.05 and now.origin.distance_to(place.origin) < 0.06,
			"agarrada, no salta ni se alinea sola: la punta queda a %.3f m y el centro se movió %.3f m" % [(now * anchor).distance_to(tip),
			now.origin.distance_to(place.origin)])
	# Girada 90° de costado: la punta queda donde estaba y el resto da la vuelta.
	hands._distance = clampf(hands._distance, 0.9, 1.2)
	await _ticks(20)
	var before := _place_of(plank)
	var anchor_before := before * anchor
	# 90° alrededor del eje vertical (como 360 píxeles de costado con el central).
	hands._rotation = (Basis(Vector3.UP, PI / 2.0) * Basis(hands._rotation)).get_rotation_quaternion()
	await _ticks(60)
	var after := _place_of(plank)
	var turned := rad_to_deg(acos(clampf(before.basis.z.normalized().dot(after.basis.z.normalized()), -1.0, 1.0)))
	_check((after * anchor).distance_to(anchor_before) < 0.08 and absf(turned - 90.0) < 8.0,
			"girada 90°, gira alrededor del punto agarrado: giró %.1f° y la punta se movió %.3f m" % [turned,
			(after * anchor).distance_to(anchor_before)])
	_check(after.origin.distance_to(before.origin) > 0.5, "y el centro de la tabla dio la vuelta (%.2f m)" % after.origin.distance_to(before.origin))
	hands.release()
	await _ticks(4)
	await _rested(plank)


## La tabla por la ranura: agarrada por una punta, derecha y a lo largo, a la
## altura de la ranura; la mano la va llevando hacia adelante y la tabla pasa
## del otro lado del muro sin tocarlo (más que al rozar).
func _plank_through_slot() -> void:
	var plank := _uid_near(PLANK_AT, &"tabla_larga", 3.0)
	if plank == 0:
		_check(false, "está la tabla larga para la ranura")
		return
	var place := _place_of(plank)
	var feet := Vector3(SLOT.x, 0, WALL_Z + 3.4)
	await _teleport(feet, 0.0)
	# La punta de la tabla más lejos del muro, a la vista.
	var far_tip: Vector3 = place * Vector3(0, 0.03, 0.74) if (place * Vector3(0, 0, 0.74)).z > (place * Vector3(0, 0, -0.74)).z \
			else place * Vector3(0, 0.03, -0.74)
	await _teleport(Vector3(far_tip.x, 0, far_tip.z + 1.0), 0.0)
	await _aim(far_tip)
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	_check(hands.held_uid() == plank, "agarra la tabla por la punta de atrás")
	if hands.held_uid() != plank:
		return
	var anchor := hands._anchor
	# Derecha, a lo largo de hacia donde mira, con la punta agarrada atrás: el
	# resto de la tabla, adelante.
	var turn: Basis = Basis.IDENTITY if anchor.z > 0.0 else Basis(Vector3.UP, PI)
	hands._rotation = turn.get_rotation_quaternion()
	await _teleport(feet, 0.0)
	var overlaps := 0
	var passed := false
	var max_error := 0.0
	var front_z := INF
	for step in 300:
		# La mano a la altura de la ranura, a 1,2 m de los ojos, y el personaje
		# caminando hacia el muro, de a 1 cm por tick, hasta quedar a 1 m.
		var at := Vector3(SLOT.x, 0, maxf(WALL_Z + 1.0, feet.z - 0.01 * step))
		_place_actor(at)
		var eyes := InvAuthority.eyes(actor, actor.global_position)
		var distance := 1.2
		hands._distance = distance
		camera.yaw = 0.0
		camera.pitch = asin(clampf((SLOT.y - eyes.y) / distance, -1.0, 1.0))
		await _ticks(1)
		var pose := _place_of(plank)
		var front := pose * Vector3(0, 0.02, -0.78 * signf(anchor.z))
		front_z = front.z
		if not InvItemPhysics.fits(get_viewport().world_3d.direct_space_state, catalog.find(&"tabla_larga"), pose, 1):
			overlaps += 1
		max_error = maxf(max_error, _body(plank).hold_error)
		if front.z < WALL_Z - 0.6:
			passed = true
		# Hasta que pasa entera (también la punta agarrada): soltada a medias, se
		# vuelve para este lado y queda apoyada en la ranura.
		if passed and (pose * anchor).z < WALL_Z - 0.15:
			break
	var now := _place_of(plank)
	var middle := now * Vector3(0, 0.02, 0)
	_check(passed, "la tabla pasa a lo largo por la ranura: la punta de adelante llegó a z %.2f (el muro en %.2f)" % [front_z, WALL_Z])
	_check(absf(middle.x - SLOT.x) < 0.1 and absf(middle.y - SLOT.y) < 0.1, "por la ranura: el medio de la tabla en %s (la ranura en %s)" % [
			middle, SLOT])
	_check(overlaps <= 6, "sin meterse en el muro (en %d ticks tocó algo del nivel)" % overlaps)
	_log("ranura: lo más lejos que quedó el punto agarrado de la mano, %.3f m" % max_error)
	hands.release()
	await _ticks(4)
	await _rested(plank)


## Cruzada (90° de costado) contra el muro: el muro la frena, no pasa, no se
## mete en él y, trabada, la mano la suelta sola.
func _plank_across_slot() -> void:
	var plank := _uid_near(CROSS_PLANK_AT, &"tabla_larga", 3.0)
	if plank == 0:
		_check(false, "está la tabla cruzada")
		return
	await _rested(plank)
	var place := _place_of(plank)
	var tip := place * Vector3(0, 0.03, 0.72)
	await _teleport(tip + Vector3(0, -tip.y, 1.0), 0.0)
	await _aim(tip)
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	_check(hands.held_uid() == plank, "agarra la otra tabla")
	if hands.held_uid() != plank:
		return
	# Cruzada: a lo ancho, y el personaje frente al muro.
	hands._rotation = Basis(Vector3.UP, PI / 2.0).get_rotation_quaternion()
	var feet := Vector3(SLOT.x + 0.4, 0, WALL_Z + 2.4)
	await _teleport(feet, 0.0)
	await _ticks(20)
	# Después, el personaje se pone a 1,2 m del muro: la mano queda del otro lado.
	feet = Vector3(SLOT.x + 0.4, 0, WALL_Z + 1.2)
	_place_actor(feet)
	var eyes := InvAuthority.eyes(actor, actor.global_position)
	var furthest := INF
	var lost := [""]  # en un arreglo: las lambdas copian las variables sueltas
	var released := func(_uid: int, reason: String) -> void: lost[0] = reason
	net.replica.hold_lost.connect(released)
	for step in 150:
		hands._distance = net.tuning.hold_max_distance
		camera.yaw = 0.0
		camera.pitch = asin(clampf((SLOT.y - eyes.y) / net.tuning.hold_max_distance, -1.0, 1.0))
		await _ticks(1)
		var box := _box_of(plank)
		furthest = minf(furthest, box.position.z)
		if not hands.is_holding():
			break
	net.replica.hold_lost.disconnect(released)
	_check(furthest > WALL_Z - 0.15, "cruzada, el muro la frena: no pasa (lo más lejos, z %.2f; el muro en %.2f)" % [furthest, WALL_Z])
	_check(not hands.is_holding() and lost[0] == "se trabó", "trabada contra el muro, la mano la suelta sola: «%s»" % lost[0])
	await _ticks(4)
	_check(net.authority.holder_of(plank) == 0, "y el host la soltó")
	await _rested(plank)


## Gravedad, reposo, choque entre objetos, caída de la mesa y lanzamiento
## contra la pared de 2 cm.
func _physics_basics() -> void:
	# Cae desde arriba de otro objeto y queda encima.
	var under := _uid_near(ROW_FRONT_AT, &"bateria")
	var screws_def := catalog.find(&"tornillos")
	if under != 0:
		var top := _box_of(under).end.y
		var stack := InvStack.make(net.authority.alloc_uid(), &"tornillos", 4, {})
		net.authority._put_in_world(stack, Transform3D(Basis.IDENTITY, _box_of(under).get_center() + Vector3.UP * 0.6), true, false)
		net.authority.flush({})
		await _ticks(2)
		_check(not _body(stack.uid).sleeping, "puesto en el aire, cae (está despierto)")
		await _rested(stack.uid)
		var box := _box_of(stack.uid)
		_check(_body(stack.uid).sleeping and box.position.y > top - 0.02, "cae, choca con la batería y queda encima: abajo en %.3f, la batería arriba en %.3f" % [
				box.position.y, top])
		_check(net.authority.world[stack.uid]["sleep"] and (net.authority.world[stack.uid]["xf"] as Transform3D).is_equal_approx(_place_of(stack.uid)),
				"y dormido, con su pose en el mundo del host")
		var r := await _pickup_uid(stack.uid)
		_check(r, "lo recoge después")
	_check(screws_def != null, "están los tornillos")
	# La granada del borde de la mesa: agarrada, llevada afuera del borde y soltada, cae al piso.
	var edge := _uid_near(EDGE_GRENADE_AT, &"granada")
	if edge != 0:
		await _teleport(Vector3(TABLE_EDGE_X - 1.0, 0, EDGE_GRENADE_AT.z), -PI / 2.0)
		await _aim(_box_of(edge).get_center())
		await _press(MOUSE_BUTTON_RIGHT)
		await _release(MOUSE_BUTTON_RIGHT)
		await _wait_confirmed()
		_check(hands.held_uid() == edge, "agarra la granada del borde de la mesa")
		camera.yaw = PI / 2.0
		hands._distance = 0.8
		await _ticks(40)
		hands.release()
		await _ticks(3)
		await _rested(edge)
		var box := _box_of(edge)
		_check(box.position.y < 0.05, "soltada afuera de la mesa, cae al piso: abajo en %.3f" % box.position.y)
	# Lanzada muy rápido contra la pared de 2 cm: no la atraviesa (CCD).
	var grenade := await _throw_grenade(Vector3(THIN_X - 1.0, 0, TRACK.z))
	if grenade != 0:
		await _rested(grenade)
		var impulse := net.tuning.throw_impulse
		for fast: float in [60.0, 120.0]:
			await _teleport(Vector3(THIN_X - 2.2, 0, TRACK.z), -PI / 2.0)
			grenade = await _throw_grenade(Vector3(THIN_X - 1.0, 0, TRACK.z))
			await _aim(_box_of(grenade).get_center())
			await _press(MOUSE_BUTTON_RIGHT)
			await _release(MOUSE_BUTTON_RIGHT)
			await _wait_confirmed()
			if hands.held_uid() != grenade:
				_check(false, "agarra la granada para lanzarla a %.0f m/s" % fast)
				continue
			hands._distance = 0.9
			camera.yaw = -PI / 2.0
			camera.pitch = 0.0
			await _ticks(20)
			net.tuning.throw_impulse = fast * net.tuning.item_mass
			hands.throw_held()
			var furthest := -INF
			var fastest := 0.0
			for i in 60:
				await _ticks(1)
				var box := _box_of(grenade)
				furthest = maxf(furthest, box.get_center().x)
				fastest = maxf(fastest, _body(grenade).linear_velocity.length())
			net.tuning.throw_impulse = impulse
			# A 120 m/s choca en el mismo paso en que sale: la velocidad que se ve ya es la del rebote.
			_check((fastest > fast * 0.8 or fast > 100.0) and furthest < THIN_X,
					"lanzada a %.0f m/s (llegó a %.0f) contra la pared de 2 cm, no la atraviesa: el centro, como mucho en x %.3f (la pared de %.3f a %.3f)" % [
					fast, fastest, furthest, THIN_X - 0.01, THIN_X + 0.01])
			await _rested(grenade)
		net.tuning.throw_impulse = impulse


## Los límites: contra una pared la mano empuja con fuerza acotada y no la
## atraviesa; lejos, se suelta sola; al morir, también.
func _limits() -> void:
	var grenade := _uid_near(Vector3(THIN_X - 0.5, 0, TRACK.z), &"granada", 4.0)
	if grenade == 0:
		return
	await _rested(grenade)
	await _teleport(_place_of(grenade).origin + Vector3(-1.0, 0, 0), -PI / 2.0)
	await _aim(_box_of(grenade).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	_check(hands.held_uid() == grenade, "agarra la granada para los límites")
	# Contra la pared fina, con la mano del otro lado: empuja sin pasar.
	await _teleport(Vector3(THIN_X - 1.0, 0, TRACK.z), -PI / 2.0)
	camera.pitch = -0.4
	hands._distance = net.tuning.hold_max_distance
	var fastest := 0.0
	var furthest := -INF
	var lost := [""]
	var on_lost := func(_uid: int, reason: String) -> void: lost[0] = reason
	net.replica.hold_lost.connect(on_lost)
	for i in 90:
		await _ticks(1)
		fastest = maxf(fastest, _body(grenade).linear_velocity.length())
		furthest = maxf(furthest, _box_of(grenade).get_center().x)
		if not hands.is_holding():
			break
	_check(furthest < THIN_X, "empujada contra la pared fina con la mano del otro lado, no la atraviesa (el centro, como mucho en x %.3f)" % furthest)
	_check(fastest <= net.tuning.hold_move_limit + 0.5, "y no pasa de Hold Move Limit (%.1f m/s)" % fastest)
	_check(lost[0] == "se trabó", "y trabada, se suelta sola: «%s»" % lost[0])
	# Lejos: el personaje se va y se suelta sola.
	await _rested(grenade)
	await _teleport(_place_of(grenade).origin + Vector3(-1.0, 0, 0), -PI / 2.0)
	await _aim(_box_of(grenade).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	lost[0] = ""
	await _teleport(actor.global_position + Vector3(-6.0, 0, 0), -PI / 2.0)
	await _ticks(10)
	_check(not hands.is_holding() and lost[0] == "quedó muy lejos", "el personaje se aleja de golpe: se suelta sola («%s»)" % lost[0])
	# Al morir.
	await _rested(grenade)
	await _teleport(_place_of(grenade).origin + Vector3(-1.0, 0, 0), -PI / 2.0)
	await _aim(_box_of(grenade).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	lost[0] = ""
	ActorVitals.of(actor.state, net.tuning).apply(-1000, 0)
	await _ticks(6)
	net.replica.hold_lost.disconnect(on_lost)
	_check(not hands.is_holding() and net.authority.holder_of(grenade) == 0, "al morir se suelta (%s)" % lost[0])
	await _rested(grenade)


## Soltar en el aire, una parte de una pila, y E sobre lo sostenido.
func _inventory_and_hands() -> void:
	_empty_inventory()
	await _ticks(3)
	var grid := net.authority.player_inventory(actor.owner_peer_id).grid
	var screws := InvStack.make(net.authority.alloc_uid(), &"tornillos", 10, {})
	InvOps.insert(grid, screws)
	net.authority._dirty_players[actor.owner_peer_id] = true
	net.authority.flush({})
	await _ticks(3)
	var own := net.replica.own.sorted_uids().filter(func(id: int) -> bool: return net.replica.own.stacks[id].def_id == &"tornillos")
	_check(not own.is_empty(), "tiene tornillos en el inventario")
	if own.is_empty():
		return
	# En el aire, 5 m arriba del piso: hasta el 2026-11-14 decía "No hay lugar cerca para soltarlo".
	await _teleport(TRACK + Vector3(0, 5.0, 0), 0.0)
	actor.state.mode = ActorState.Mode.AIR
	actor.state.on_floor = false
	var before := net.replica.world.keys()
	var uid: int = own[0]
	var seq := ui.drop_item(InvProtocol.OWN, uid, net.replica.shown_own().get_stack(uid).ver, 3)
	_check(seq != 0, "en el aire, soltar 3 sale")
	await _until(func() -> bool: return _answers.has(seq), 3.0)
	_check(_answers.get(seq, [false])[0], "y el host lo acepta: %s" % [_answers.get(seq)])
	var dropped := 0
	for key: int in net.replica.world:
		if not before.has(key):
			dropped = key
	_check(dropped != 0 and net.replica.world[dropped]["stack"].quantity == 3 and net.replica.own.get_stack(uid) != null
			and net.replica.own.get_stack(uid).quantity == 7, "soltó 3 y quedan 7 en la pila, que conserva su número")
	if dropped != 0:
		_check(_place_of(dropped).origin.y > 4.0, "aparece en el aire, junto al personaje (y %.2f)" % _place_of(dropped).origin.y)
		await _rested(dropped)
		_check(_box_of(dropped).position.y < 0.05, "y cae hasta el piso (abajo en %.3f)" % _box_of(dropped).position.y)
	await _teleport(TRACK, 0.0)
	# E sobre lo sostenido: entra al inventario y deja de sostenerse.
	if dropped != 0:
		await _teleport(_place_of(dropped).origin + Vector3(0, 0, 1.0), 0.0)
		await _aim(_box_of(dropped).get_center())
		await _press(MOUSE_BUTTON_RIGHT)
		await _release(MOUSE_BUTTON_RIGHT)
		await _wait_confirmed()
		_check(hands.held_uid() == dropped, "agarra los 3 tornillos")
		var target := ui.interaction_target()
		_check(target.get("id", 0) == dropped, "con algo en la mano, E elige lo que sostiene")
		ui._interact()
		await _ticks(6)
		_check(not net.replica.world.has(dropped) and not hands.is_holding() and net.replica.own.quantity_of(&"tornillos") == 10,
				"E lo guarda: sale del mundo, la mano queda vacía y vuelven a ser 10")
	# En parte: con lugar para 5 de 10, quedan 5 en el mundo, sostenidos.
	var full := await _fill_inventory_but(&"tornillos", 25)
	var loose := InvStack.make(net.authority.alloc_uid(), &"tornillos", 10, {})
	var spot := TRACK + Vector3(0.5, 0, -0.8)
	net.authority._put_in_world(loose, spot)
	net.authority.flush({})
	await _ticks(4)
	await _teleport(spot + Vector3(0, 0, 1.0), 0.0)
	await _aim(_box_of(loose.uid).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	_check(hands.held_uid() == loose.uid, "agarra la pila de 10")
	var place := _place_of(loose.uid)
	ui._interact()
	await _ticks(6)
	_check(net.replica.world.has(loose.uid) and net.replica.world[loose.uid]["stack"].quantity == 5
			and net.replica.own.quantity_of(&"tornillos") == 30 + (0 if full else 0), "entran 5: quedan 5 en el mundo, con el mismo número")
	_check(hands.held_uid() == loose.uid and net.authority.holder_of(loose.uid) == actor.owner_peer_id,
			"y la sigue sosteniendo")
	_check(_place_of(loose.uid).origin.distance_to(place.origin) < 0.3, "en el mismo lugar")
	hands.release()
	await _ticks(4)
	_empty_inventory()
	await _ticks(3)


## Llena el inventario del jugador con banquitos, salvo lugar para una pila de
## `def_id` con `quantity`. Devuelve si quedó lleno.
func _fill_inventory_but(def_id: StringName, quantity: int) -> bool:
	_empty_inventory()
	var grid := net.authority.player_inventory(actor.owner_peer_id).grid
	InvOps.insert(grid, InvStack.make(net.authority.alloc_uid(), def_id, quantity, {}))
	for i in 200:
		var result := InvOps.insert(grid, InvStack.make(net.authority.alloc_uid(), &"llave", 1, {}))
		if result["reason"] != "":
			break
	net.authority._dirty_players[actor.owner_peer_id] = true
	net.authority.flush({})
	await _ticks(3)
	return true


func _empty_inventory() -> void:
	var grid := net.authority.player_inventory(actor.owner_peer_id).grid
	for uid in grid.sorted_uids():
		InvOps.take(grid, uid, grid.get_stack(uid).ver, grid.get_stack(uid).quantity, net.authority.alloc_uid())
	net.authority._dirty_players[actor.owner_peer_id] = true
	net.authority.flush({})


func _pickup_uid(uid: int) -> bool:
	await _teleport(_place_of(uid).origin + Vector3(0, 0, 1.0), 0.0)
	await _aim(_box_of(uid).get_center())
	var target := ui.interaction_target()
	if target.get("id", 0) != uid:
		return false
	ui._interact()
	await _ticks(6)
	return not net.replica.world.has(uid)


## Un objeto que gira se elige por el punto que se ve, el de su pose de ahora.
func _moving_selection() -> void:
	var plank := _uid_near(PLANK_AT, &"tabla_larga", 4.0)
	if plank == 0:
		plank = _uid_near(SLOT + Vector3(0, -1.25, -1.0), &"tabla_larga", 4.0)
	if plank == 0:
		_check(false, "hay una tabla para elegirla girando")
		return
	await _rested(plank)
	await _teleport(_place_of(plank).origin + Vector3(0, 0, 1.8), 0.0)
	var body := _body(plank)
	body.angular_velocity = Vector3(0, 2.0, 0)
	# Despertarlo con el gestor (desde el 2026-11-15): cambiar `sleeping` a mano no
	# pone al día la pose que ve el rayo.
	net.bodies.wake(plank)
	var hits := 0
	var right := 0
	for i in 20:
		await _ticks(2)
		var place := _place_of(plank)
		var point := place * Vector3(0, 0.04, 0.5)
		await _aim(point)
		var target := net.interaction_target(actor, camera.aim_ray()[0], camera.aim_ray()[1], false)
		if target.get("id", 0) == plank:
			hits += 1
			var expected := _place_of(plank) * Vector3(0, 0.04, 0.5)
			if (target["point"] as Vector3).distance_to(expected) < 0.06:
				right += 1
	_check(hits >= 16 and right >= 16, "girando, se elige por donde se la ve: %d de 20 la eligen, %d con el punto correcto" % [hits, right])
	await _rested(plank)


## Un hueco del modelo no se vuelve sólido con el cuerpo; lo de adelante tapa
## lo de atrás, en primera y en tercera persona.
func _holes_and_occlusion() -> void:
	# Un marco de 60 cm con un hueco de 40, en memoria (como inv_alcance_test).
	var frame := _frame_def()
	catalog.items.append(frame)
	# El cuerpo, de varias formas armadas con la herramienta de Godot (desde el
	# 2026-11-15): conserva el hueco.
	var body := InvBodyShape.new()
	body.kind = InvPickupHitbox.Kind.MODEL
	body.generation = InvBodyShape.Generation.PARTS
	var generated := InvItemPhysics.generate(frame, body)
	frame.body_shape = body
	var parts := InvItemPhysics.parts(frame)
	_check(generated["ok"] and parts.size() >= 4 and InvItemPhysics.status_of(frame) == "preparado",
			"el marco tiene un cuerpo preparado de varias formas (%d), no una sola que tape el hueco" % parts.size())
	var stack := InvStack.make(net.authority.alloc_uid(), frame.id, 1, {})
	var spot := TRACK + Vector3(-1.0, 0, 3.0)
	net.authority._put_in_world(stack, spot)
	net.authority.flush({})
	await _ticks(4)
	var space := get_viewport().world_3d.direct_space_state
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3(0, 1.0, 0), spot + Vector3(0, -0.5, 0),
			InvItemPhysics.LAYER))
	_check(down.is_empty(), "el cuerpo del marco no tapa el hueco: un rayo de la física por el medio no lo toca")
	await _teleport(spot + Vector3(0, 0, 0.9), 0.0)
	await _aim(spot)
	var through := net.interaction_target(actor, camera.aim_ray()[0], camera.aim_ray()[1], false)
	_check(through.is_empty(), "sin hitbox, por el hueco el rayo de la mano llega al piso y no lo elige: %s" % [through.get("id", 0)])
	await _aim(spot + Vector3(0.25, 0.02, 0))
	var bar := net.interaction_target(actor, camera.aim_ray()[0], camera.aim_ray()[1], false)
	_check(bar.get("id", 0) == stack.uid, "por una barra, sí")
	# Con una hitbox de agarre que tapa el hueco: se elige por el hueco, el punto
	# tocado queda en el hueco (anclaje virtual) y el cuerpo sigue sin taparlo.
	var hitbox := InvPickupHitbox.new()
	hitbox.kind = InvPickupHitbox.Kind.BOX
	hitbox.fit(InvReach.item_bounds(frame))
	frame.pickup_hitbox = hitbox
	net.authority.space.move(stack.uid, net.authority.space.transform_of(stack.uid).translated(Vector3(0, 0.0001, 0)))
	net.authority.space.move(stack.uid, Transform3D(Basis.IDENTITY, spot))
	await _aim(spot)
	var covered := net.interaction_target(actor, camera.aim_ray()[0], camera.aim_ray()[1], false)
	var virtual := (covered.get("place", Transform3D()) as Transform3D).affine_inverse() * (covered.get("point", Vector3.ONE * 9) as Vector3)
	_check(covered.get("id", 0) == stack.uid and Vector2(virtual.x, virtual.z).length() < 0.15,
			"con la hitbox, por el hueco se elige el marco y el punto tocado queda en el hueco: %s" % [virtual])
	down = space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3(0, 1.0, 0), spot + Vector3(0, -0.5, 0),
			InvItemPhysics.LAYER))
	_check(down.is_empty() and InvItemPhysics.parts(frame).size() == parts.size(),
			"la hitbox no cambia el cuerpo: el rayo de la física sigue pasando por el hueco")
	net.authority._take_from_world(stack.uid)
	net.authority.flush({})
	catalog.items.erase(frame)
	# La fila: la de adelante tapa a las de atrás.
	var front := _uid_near(ROW_FRONT_AT, &"bateria")
	var middle := _uid_near(ROW_MIDDLE_AT, &"bateria")
	if front == 0 or middle == 0:
		_check(false, "están las baterías de la fila")
		return
	for first: bool in [true, false]:
		var what := "primera persona" if first else "tercera persona"
		await _set_first_person(first)
		await _teleport(Vector3(ROW_FRONT_AT.x, 0, ROW_FRONT_AT.z - 1.0), PI)
		await _aim(_box_of(middle).get_center())
		var seen := net.interaction_target(actor, camera.aim_ray()[0], camera.aim_ray()[1], not first)
		_check(seen.get("id", 0) == front, "%s: apuntando a la del medio por detrás de la de adelante, se elige la de adelante" % what)
	await _set_first_person(true)


func _frame_def() -> InvItemDef:
	var def := InvItemDef.new()
	def.id = &"marco_de_fisica"
	def.display_name = "Marco de física"
	def.size = Vector2i(2, 2)
	var mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bars := [AABB(Vector3(-0.3, 0, -0.3), Vector3(0.1, 0.04, 0.6)), AABB(Vector3(0.2, 0, -0.3), Vector3(0.1, 0.04, 0.6)),
			AABB(Vector3(-0.2, 0, -0.3), Vector3(0.4, 0.04, 0.1)), AABB(Vector3(-0.2, 0, 0.2), Vector3(0.4, 0.04, 0.1))]
	for bar: AABB in bars:
		var box := BoxMesh.new()
		box.size = bar.size
		var faces := box.get_faces()
		for i in faces.size():
			surface.add_vertex(faces[i] + bar.get_center())
	surface.commit(mesh)
	def.mesh = mesh
	def.world_size = 0.6
	return def


# --- Desde el 2026-11-15 (docs/net/prompt_claude_revision_objetos_fisicos.md) ---------

## Un piso de prueba lejos de todo, en el aire (más arriba que FALL_LIMIT): lo
## que se pone ahí no toca nada de la pista.
const TEST_FLOOR := Vector3(160, 40, 160)


func _test_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	body.add_child(shape)
	body.position = TEST_FLOOR + Vector3(0, -0.5, 0)
	lab.add_child(body)
	return body


## Los cuerpos del catálogo: todos preparados y usados tal como se guardaron
## (sin generar nada al jugar), sin rendijas ni recortes (cada vértice del
## modelo adentro de su cuerpo, o a menos de un margen), sin sobresalir, y
## apoyados en el piso sin hundirse más que lo que Jolt deja.
func _bodies_prepared() -> void:
	var floor_body := _test_floor()
	var dropped: Array = []
	var x := -15.0
	for def: InvItemDef in catalog.items:
		var name := def.display_name
		var body := def.body_shape
		var parts := InvItemPhysics.parts(def)
		var loaded := body != null and (body.kind != InvPickupHitbox.Kind.MODEL or (parts.size() == body.shapes.size()
				and range(parts.size()).all(func(i: int) -> bool: return parts[i][0] == body.shapes[i])))
		_check(InvItemPhysics.status_of(def) == "preparado" and loaded,
				"%s: cuerpo preparado y usado tal como está en el .tres (%s)" % [name, InvItemPhysics.status_of(def)])
		# Hasta TRIM_TOLERANCE (3 mm): lo que acepta InvItemPhysics.suggest (Godot
		# redondea el casco convexo un par de milímetros).
		var tolerance := InvItemPhysics.TRIM_TOLERANCE
		var worst := InvItemPhysics.worst_outside(def, parts)
		_check(worst <= tolerance, "%s: ningún punto del modelo queda afuera de su cuerpo (el más lejos, a %.1f mm; se acepta %.0f)" % [
				name, worst * 1000.0, tolerance * 1000.0])
		var model := InvReach.item_bounds(def).grow(-0.001)
		var area := InvItemPhysics.body_bounds(def)
		var over := 0.0
		for axis in 3:
			over = maxf(over, maxf(model.position[axis] - area.position[axis], area.end[axis] - model.end[axis]))
		_check(over <= tolerance, "%s: el cuerpo no sobresale del modelo (%.1f mm)" % [name, over * 1000.0])
		# Derecho, y apoyado inclinado (así Jolt dejaba metidas las formas
		# convexas planas: 2026-11-15), de 2 cm y de 1 m (así quedaban hasta 2 cm
		# adentro con la tolerancia de fábrica de Jolt: lo encontró el usuario).
		for drop: int in 4:
			var tilted := drop % 2 == 1
			var turn := Basis(Vector3(1, 0, 0.3).normalized(), 0.35) if tilted else Basis.IDENTITY
			var height := 1.0 if drop >= 2 else 0.02
			var stack := InvStack.make(net.authority.alloc_uid(), def.id, 1, def.default_state)
			net.authority._put_in_world(stack, _on_floor(def.id, TEST_FLOOR + Vector3(x, 0, 3.0 * drop - 9.0), height, turn), true, false)
			dropped.append([def, stack.uid])
		x += 1.6
	net.authority.flush({})
	var plank := catalog.find(&"tabla_larga")
	var plank_parts := InvItemPhysics.parts(plank)
	_check(plank_parts.size() == 1 and plank_parts[0][0] is BoxShape3D and InvItemPhysics.body_bounds(plank).size.z >= 1.599,
			"la tabla larga es una sola caja de todo su largo: sin rendijas")
	var rescued := net.bodies.unstuck
	var uids: Array[int] = []
	for pair: Array in dropped:
		uids.append(pair[1])
	await _ticks(10)
	await _rested_all(uids)
	var sink := 0.0
	var lines := PackedStringArray()
	for pair: Array in dropped:
		var def: InvItemDef = pair[0]
		var place := _place_of(pair[1])
		var lowest := INF
		for vertex in InvReach.item_faces(def):
			lowest = minf(lowest, (place * vertex).y)
		var below := TEST_FLOOR.y - lowest
		sink = maxf(sink, below)
		lines.append("%s %.1f" % [def.display_name, below * 1000.0])
		net.authority._take_from_world(pair[1])
	net.authority.flush({})
	_log("medición: lo más bajo del modelo, en mm por debajo del piso al reposar (derecho e inclinado, de 2 cm y de 1 m): " + ", ".join(lines))
	_check(sink <= 0.006 and net.bodies.unstuck == rescued, "nada queda metido en el piso, derecho ni inclinado, de 2 cm ni de 1 m: lo más, %.1f mm (el host tuvo que sacar %d)" % [
			sink * 1000.0, net.bodies.unstuck - rescued])
	floor_body.queue_free()
	await _ticks(2)


## La hitbox de agarre como selección principal: más grande que la llave, la
## elige y la agarra por un punto que no es del modelo (anclaje virtual), sin
## cambiar su cuerpo; afuera de ella, no; asomando de una pared, no deja
## agarrar lo de atrás (ni en el host); en el borde de la mesa, sí; y el
## alcance se mide desde los ojos hasta el punto tocado.
func _hitbox_rules() -> void:
	var key := catalog.find(&"llave")
	var keep := key.pickup_hitbox
	var body_print := InvItemPhysics.fingerprint_of(key)
	var model := InvReach.item_bounds(key)
	var hitbox := InvPickupHitbox.new()
	hitbox.kind = InvPickupHitbox.Kind.BOX
	hitbox.fit(model)
	hitbox.grow(0.03)
	key.pickup_hitbox = hitbox
	_check(InvItemPhysics.fingerprint_of(key) == body_print and InvItemPhysics.local_bounds(key).encloses(hitbox.bounds()),
			"agrandar la hitbox de la llave no cambia su cuerpo, y el índice la incluye")
	# 1. En el piso, abierta: 2 cm afuera del modelo, adentro de la hitbox.
	var spot := TRACK + Vector3(-3.2, 0, -0.4)
	var uid := _spawn(&"llave", Transform3D(Basis.IDENTITY, spot))
	await _ticks(3)
	var world_box := net.authority.space.transform_of(uid) * hitbox.bounds()
	_check(net.authority.space.index.near(world_box).has(uid), "la llave está anotada en el índice con su hitbox")
	await _teleport(spot + Vector3(-1.0, 0, 0), -PI / 2.0)
	var beside := spot + Vector3(0, 0.005, model.end.z + 0.02)
	await _aim(beside)
	var seen := net.interaction_target(actor, camera.aim_ray()[0], camera.aim_ray()[1], false)
	var local: Vector3 = (seen.get("place", Transform3D()) as Transform3D).affine_inverse() * (seen.get("point", Vector3.ZERO) as Vector3)
	var off_model := InvReach.closest_model_point(key, local).distance_to(local)
	_check(seen.get("id", 0) == uid and off_model > 0.01, "2 cm al costado del modelo, adentro de la hitbox, la elige (el punto, a %.1f cm del modelo)" % (
			off_model * 100.0))
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	var hold: Dictionary = net.bodies.holds().get(uid, {})
	_check(hands.held_uid() == uid and not hold.is_empty() and (hold["anchor"] as Vector3).distance_to(hands._anchor) < 0.002
			and InvReach.closest_model_point(key, hold["anchor"]).distance_to(hold["anchor"]) > 0.01,
			"la agarra por ese punto, afuera del modelo (anclaje virtual), igual en la mano y en el host")
	var anchor_before: Vector3 = hold.get("anchor", Vector3.ZERO)
	camera.yaw -= 0.8
	await _ticks(20)
	_check((net.bodies.holds().get(uid, {}).get("anchor", Vector3.ONE) as Vector3).is_equal_approx(anchor_before),
			"al girar, sigue agarrada por ese punto (no salta al centro)")
	hands.release()
	await _ticks(4)
	await _rested(uid)
	await _teleport(_place_of(uid).origin + Vector3(-1.0, 0, 0), -PI / 2.0)
	var place := _place_of(uid)
	await _aim(place * Vector3(0, 0.005, hitbox.bounds().end.z + 0.02))
	seen = net.interaction_target(actor, camera.aim_ray()[0], camera.aim_ray()[1], false)
	_check(seen.get("id", 0) != uid, "2 cm afuera de la hitbox, no")
	# 2. Detrás de la pared fina, con una hitbox que asoma de este lado.
	var big := InvPickupHitbox.new()
	big.kind = InvPickupHitbox.Kind.BOX
	big.fit(model)
	big.grow(0.12)
	key.pickup_hitbox = big
	net.authority._take_from_world(uid)
	var behind := Transform3D(Basis.IDENTITY, Vector3(THIN_X + 0.01 + 0.02 + model.size.x * 0.5 - model.get_center().x, 0, TRACK.z + 1.0))
	uid = _spawn(&"llave", behind)
	await _ticks(3)
	var poking := behind * big.bounds()
	_check(poking.position.x < THIN_X - 0.03, "la hitbox de la llave de atrás asoma de este lado de la pared (hasta x %.2f; la pared en %.2f)" % [
			poking.position.x, THIN_X - 0.01])
	await _teleport(Vector3(THIN_X - 1.0, 0, TRACK.z + 1.0), -PI / 2.0)
	await _aim(Vector3(THIN_X - 0.025, 0.02, TRACK.z + 1.0))
	seen = net.interaction_target(actor, camera.aim_ray()[0], camera.aim_ray()[1], false)
	_check(seen.get("id", 0) != uid, "apuntando a lo que asoma, no se elige la llave de atrás de la pared")
	var direction := (Vector3(THIN_X - 0.025, 0.02, TRACK.z + 1.0) - InvAuthority.eyes(actor, actor.global_position)).normalized()
	var asked := await _req(Op.GRAB, InvProtocol.grab_args(uid, direction, net.aim_tick(), -1.0, 9000), [uid])
	_check(not asked[0], "y el host no la deja agarrar con esa dirección: %s" % asked[1])
	if asked[0]:
		await _req(Op.RELEASE, InvProtocol.release_args(uid, 9000, net.aim_tick()), [uid])
		hands._session_counter = maxi(hands._session_counter, 9000)
	net.authority._take_from_world(uid)
	# 3. En el borde de la mesa, desde el piso: la hitbox asoma del borde y se ve.
	key.pickup_hitbox = hitbox
	var edge := Transform3D(Basis.IDENTITY, Vector3(TABLE_EDGE_X + model.size.x * 0.5 - model.get_center().x + 0.005, TABLE_TOP,
			EDGE_GRENADE_AT.z + 0.45))
	uid = _spawn(&"llave", edge)
	await _ticks(3)
	await _teleport(Vector3(TABLE_EDGE_X - 1.1, 0, edge.origin.z), -PI / 2.0)
	# Lo que asoma del borde, un poco por debajo de la tabla de la mesa.
	await _aim(Vector3(TABLE_EDGE_X - 0.012, TABLE_TOP - 0.004, edge.origin.z))
	seen = net.interaction_target(actor, camera.aim_ray()[0], camera.aim_ray()[1], false)
	_check(seen.get("id", 0) == uid and seen.has("point"), "en el borde de la mesa, la hitbox que asoma del borde la elige")
	net.authority._take_from_world(uid)
	# 4. El alcance, desde los ojos hasta el punto tocado.
	uid = _spawn(&"llave", Transform3D(Basis.IDENTITY, spot))
	await _ticks(3)
	var reach := net.interaction_range
	for extra: float in [-0.15, 0.1]:
		var eyes_height := InvAuthority.eyes(actor, actor.global_position).y - actor.global_position.y
		# Los ojos a reach + extra del punto más cercano de la hitbox, mirándolo.
		var near_point := spot + Vector3(0, 0.005, model.position.z - 0.03)
		var flat := sqrt(maxf(pow(reach + extra, 2.0) - pow(eyes_height - 0.005, 2.0), 0.01))
		await _teleport(Vector3(spot.x, 0, near_point.z - flat), PI)
		await _aim(near_point)
		seen = net.interaction_target(actor, camera.aim_ray()[0], camera.aim_ray()[1], false)
		var at := InvAuthority.eyes(actor, actor.global_position).distance_to(near_point)
		if extra < 0.0:
			_check(seen.get("id", 0) == uid, "con la hitbox a %.2f m de los ojos (el alcance, %.2f), la elige" % [at, reach])
		else:
			_check(seen.get("id", 0) != uid, "con la hitbox a %.2f m de los ojos (más que el alcance, %.2f), no" % [at, reach])
	net.authority._take_from_world(uid)
	net.authority.flush({})
	key.pickup_hitbox = keep
	InvReach.clear_cache()
	await _ticks(2)


func _spawn(def_id: StringName, place: Transform3D, asleep := true) -> int:
	var def := catalog.find(def_id)
	var stack := InvStack.make(net.authority.alloc_uid(), def_id, 1, def.default_state if def != null else {})
	net.authority._put_in_world(stack, place, true, asleep)
	net.authority.flush({})
	return stack.uid


func _req(op: int, args: Array, uids: Array = []) -> Array:
	var seq := net.replica.request(op, args, uids)
	if seq == 0:
		return [false, "no salió"]
	for i in 60:
		if _answers.has(seq):
			return _answers[seq]
		await _ticks(1)
	return [false, "sin respuesta"]


## Sacar del mundo lo que sostiene a otros: una pila de tres baterías dormidas,
## recogida la de abajo, cae entera y vuelve a reposar; la del costado, que no
## pierde su apoyo, no se mueve; también si la de abajo se saca en el mismo
## tick en que nacieron dormidas (el arreglo de lo que nace dormido no las
## vuelve a dormir); recoger una parte de una pila que sigue en el mundo no
## despierta a nadie; y no queda nada anotado de más.
func _stack_wake() -> void:
	var floor_body := _test_floor()
	for same_tick: bool in [false, true]:
		var what := "en el mismo tick en que nacen" if same_tick else "dormidas"
		var base := TEST_FLOOR + Vector3(4.0 if same_tick else 0.0, 0, 6.0)
		var stack: Array[int] = []
		for i in 3:
			stack.append(_spawn(&"bateria", Transform3D(Basis.IDENTITY, base + Vector3(0, 0.18 * i, 0))))
		var side := _spawn(&"bateria", Transform3D(Basis.IDENTITY, base + Vector3(0.12, 0, 0)))
		if not same_tick:
			await _ticks(20)
			_check(stack.all(func(uid: int) -> bool: return net.bodies.view(uid).sleeping), "%s: la pila de tres baterías duerme" % what)
		var start_y: float = _place_of(stack[2]).origin.y
		var side_at := _place_of(side).origin
		var wakes := net.bodies.wakes
		net.authority._take_from_world(stack[0])
		net.authority.flush({})
		_check(net.bodies.wakes >= wakes + 1, "%s: recoger la de abajo despierta a las de arriba (%d despertadas)" % [what, net.bodies.wakes - wakes])
		var during := []
		for i in 30:
			await _ticks(1)
			var item: Dictionary = net.authority.world.get(stack[2], {})
			during.append([item.get("sleep", true), (item.get("xf", Transform3D()) as Transform3D).origin.y,
					net.authority.space.transform_of(stack[2]).origin.y])
		var moving := during.filter(func(entry: Array) -> bool: return not entry[0] and entry[1] < start_y - 0.01)
		_check(moving.size() >= 3 and moving.all(func(entry: Array) -> bool: return absf(entry[1] - entry[2]) < 0.0001),
				"%s: la de arriba cae, despierta, y su pose y el índice se ponen al día durante la caída (%d ticks)" % [what, moving.size()])
		var settle: Array[int] = stack.slice(1)
		settle.append(side)
		await _rested_all(settle)
		var middle := _place_of(stack[1]).origin.y - base.y
		var top := _place_of(stack[2]).origin.y - base.y
		_check(absf(middle) < 0.025 and absf(top - 0.18) < 0.035, "%s: caen y vuelven a reposar una sobre otra (la del medio a %.3f m, la de arriba a %.3f)" % [
				what, middle, top])
		_check(_place_of(side).origin.distance_to(side_at) < 0.002, "%s: la del costado, que no perdió su apoyo, no se movió" % what)
		var leftovers := stack.slice(1) + [side]
		var noted := leftovers.filter(func(uid: int) -> bool: return net.bodies._awake.has(uid) or net.bodies._sleep_next.has(uid) or net.bodies._born_asleep.has(uid))
		_check(noted.is_empty(), "%s: dormidas otra vez, no queda nada anotado (%s)" % [what, noted])
		for uid: int in leftovers:
			net.authority._take_from_world(uid)
		net.authority.flush({})
		await _ticks(5)
	# Recoger una parte de una pila de tornillos con una batería encima: el
	# cuerpo sigue, y no se despierta nadie.
	var screws := _spawn(&"tornillos", Transform3D(Basis.IDENTITY, TEST_FLOOR + Vector3(-4, 0, 6)))
	net.authority.world[screws]["stack"].quantity = 5
	var on_top := _spawn(&"bateria", Transform3D(Basis.IDENTITY, TEST_FLOOR + Vector3(-4, 0.142, 6)))
	await _ticks(20)
	var wakes := net.bodies.wakes
	var stack_item: InvStack = net.authority.world[screws]["stack"]
	stack_item.quantity -= 2
	stack_item.ver += 1
	net.authority.space.set_stack(screws, stack_item)
	net.bodies.refresh_view(screws)
	net.authority.flush({})
	await _ticks(10)
	_check(net.bodies.wakes == wakes and net.bodies.view(on_top).sleeping, "recoger una parte de una pila que sigue en el mundo no despierta a nadie")
	for uid: int in [screws, on_top]:
		net.authority._take_from_world(uid)
	net.authority.flush({})
	floor_body.queue_free()
	await _ticks(2)


## La pose de un objeto de ese tipo apoyado en `at` (su punto más bajo a `gap`
## del piso; negativo: metido), con ese giro.
func _on_floor(def_id: StringName, at: Vector3, gap: float, turn := Basis.IDENTITY) -> Transform3D:
	var lowest := INF
	for vertex in InvReach.item_faces(catalog.find(def_id)):
		lowest = minf(lowest, (turn * vertex).y)
	return Transform3D(turn, Vector3(at.x, at.y + gap - lowest, at.z))


## Lo metido en el piso (desde el 2026-11-15, lo encontró el usuario en las dos
## notebooks): el machete debajo de una pila apretada para abajo con la mano no
## queda metido (con la tolerancia de fábrica de Jolt, 2 cm, quedaba 14 mm
## adentro y no salía; ahora 2 mm, en project.godot); y algo que igual arranca
## metido se puede agarrar y sacar, sin hundirlo más (InvHoldMotion.path_free:
## antes la mano lo daba por trabado y no lo movía).
func _sunk_and_pressed() -> void:
	var floor_body := _test_floor()
	var spot := TEST_FLOOR + Vector3(-8, 0, -8)
	var space := get_viewport().world_3d.direct_space_state
	await _teleport(spot + Vector3(0, 0, 0.9), 0.0)
	await _ticks(20)
	# 1. Una pila sobre el machete, apretada para abajo con la mano.
	var machete := _spawn(&"machete", _on_floor(&"machete", spot, 0.002), false)
	var machete_def := catalog.find(&"machete")
	var pile: Array[int] = [machete]
	for i in 3:
		var id := &"caja_de_herramientas" if i == 2 else &"botiquin"
		pile.append(_spawn(id, _on_floor(id, spot, 0.12 + 0.3 * i), false))
	await _ticks(10)
	await _rested_all(pile)
	var top: int = pile[-1]
	await _aim(_box_of(top).get_center())
	var grabbed := await _grab_aimed()
	await _wait_confirmed()
	_check(grabbed and hands.held_uid() == top, "agarré la caja de arriba de la pila")
	var deepest := 0.0
	if hands.held_uid() == top:
		# Medio metro debajo de la caja: empuja con todo lo que deja la mano, sin
		# llegar a la distancia en que se suelta sola (Hold Break Distance, 0,8 m).
		var below := _box_of(top).get_center() + Vector3(0, -0.5, 0)
		await _aim(below)
		hands._distance = view_camera.global_position.distance_to(below)
		for i in 120:
			await _ticks(1)
			deepest = maxf(deepest, InvItemPhysics.depth(space, machete_def, _place_of(machete), InvAuthority.WORLD_MASK))
		_check(hands.held_uid() == top, "apreté la pila 2 s sin que se suelte sola")
		hands.release()
	await _ticks(10)
	await _rested_all(pile)
	var after := InvItemPhysics.depth(space, machete_def, _place_of(machete), InvAuthority.WORLD_MASK)
	_log("medición: el machete debajo de la pila apretada, metido en el piso: lo más %.1f mm, al reposar %.1f mm" % [
			deepest * 1000.0, after * 1000.0])
	_check(after <= InvItemPhysics.INSET, "el machete debajo de la pila apretada no queda metido en el piso (%.1f mm; se acepta %.0f)" % [
			after * 1000.0, InvItemPhysics.INSET * 1000.0])
	for uid: int in pile:
		net.authority._take_from_world(uid)
	net.authority.flush({})
	await _ticks(5)
	# 2. La caja de herramientas metida 1,5 cm en el piso.
	var box_def := catalog.find(&"caja_de_herramientas")
	var sunk := _on_floor(&"caja_de_herramientas", spot, -0.015)
	var start := InvItemPhysics.depth(space, box_def, sunk, InvAuthority.WORLD_MASK)
	var path_ok := func(to: Transform3D) -> bool: return InvHoldMotion.path_free(space, box_def, sunk, to, InvAuthority.WORLD_MASK)
	_check(start > 0.01 and path_ok.call(sunk.translated(Vector3(0.05, 0, 0))) and path_ok.call(sunk.translated(Vector3(0, 0.03, 0)))
			and not path_ok.call(sunk.translated(Vector3(0, -0.005, 0))),
			"metida %.1f mm: el camino deja arrastrarla y sacarla para arriba, no hundirla más" % (start * 1000.0))
	var box := _spawn(&"caja_de_herramientas", sunk, true)
	await _ticks(5)
	var from := _place_of(box)
	var first := InvItemPhysics.depth(space, box_def, from, InvAuthority.WORLD_MASK)
	await _aim(_box_of(box).get_center())
	var got := await _grab_aimed()
	await _wait_confirmed()
	_check(got and hands.held_uid() == box, "agarré la caja metida en el piso")
	var worst := first
	if hands.held_uid() == box:
		var lift := from.origin + Vector3(0, 0.6, 0.3)
		await _aim(lift)
		hands._distance = view_camera.global_position.distance_to(lift)
		for i in 60:
			await _ticks(1)
			worst = maxf(worst, InvItemPhysics.depth(space, box_def, _place_of(box), InvAuthority.WORLD_MASK))
	var moved := _place_of(box).origin.distance_to(from.origin)
	var end_depth := InvItemPhysics.depth(space, box_def, _place_of(box), InvAuthority.WORLD_MASK)
	_check(hands.held_uid() == box and moved > 0.3 and end_depth < 0.001 and worst <= first + 0.002,
			"la caja metida %.1f mm se agarra y se saca: se movió %.2f m, quedó metida %.1f mm, nunca más que al empezar (lo más, %.1f mm)" % [
			first * 1000.0, moved, end_depth * 1000.0, worst * 1000.0])
	hands.release()
	await _rested(box)
	net.authority._take_from_world(box)
	net.authority.flush({})
	floor_body.queue_free()
	await _ticks(2)


## Una pared de 2 cm de grosor, de `size` de ancho y alto, con su centro en `at`
## y de frente al eje z.
func _wall(at: Vector3, size: Vector2) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.02)
	shape.shape = box
	body.add_child(shape)
	body.position = at
	lab.add_child(body)
	return body


## Tapado por el nivel (pedido por el usuario el 2026-11-15, después de llevar
## la tabla detrás de un muro y seguir moviéndola): el punto agarrado tiene que
## verse desde los ojos (InvReach.held_visible). La tabla con una pared delante
## de una punta: agarrada por la otra, se ve; por la tapada, no. Y la caja
## sostenida, con una pared que aparece entre los ojos y ella, se suelta sola
## («no se ve»): de fábrica en el acto (Hold Hidden Time 0, desde la segunda
## prueba del usuario, 2026-11-15; antes, a los Hold Break Time) y, con Hold
## Hidden Time en 0,25 s, a los 0,25 s, no antes.
func _hidden_release() -> void:
	var floor_body := _test_floor()
	var spot := TEST_FLOOR + Vector3(8, 0, -8)
	var space := get_viewport().world_3d.direct_space_state
	await _teleport(spot + Vector3(0, 0, 1.5), 0.0)
	await _ticks(10)
	var eyes := view_camera.global_position
	# 1. La regla, con la tabla quieta a lo largo de la vista y una pared delante
	#    de su mitad lejana.
	var plank_def := catalog.find(&"tabla_larga")
	var plank_place := _on_floor(&"tabla_larga", spot, 0.0)
	var plank := _spawn(&"tabla_larga", plank_place, true)
	await _ticks(3)
	var bounds := InvReach.item_bounds(plank_def)
	var near_tip := Vector3(bounds.get_center().x, bounds.end.y, bounds.end.z - 0.02)
	var far_tip := Vector3(bounds.get_center().x, bounds.end.y, bounds.position.z + 0.02)
	if (plank_place * near_tip).distance_to(eyes) > (plank_place * far_tip).distance_to(eyes):
		var swap := near_tip
		near_tip = far_tip
		far_tip = swap
	# La pared corta la línea a la punta lejana (va entre los ojos y esa punta,
	# sin tocar la tabla) y no la de la cercana.
	var blocker := _wall(eyes.lerp(plank_place * far_tip, 0.6), Vector2(1.0, 1.0))
	await _ticks(2)
	_check(InvReach.held_visible(space, eyes, plank_def, plank_place, near_tip)
			and not InvReach.held_visible(space, eyes, plank_def, plank_place, far_tip),
			"la tabla con una pared delante de una punta: agarrada por la otra se ve, por la tapada no")
	blocker.queue_free()
	net.authority._take_from_world(plank)
	net.authority.flush({})
	await _ticks(3)
	# 2. La caja sostenida, con una pared que aparece entre los ojos y ella.
	var box := _spawn(&"caja_de_herramientas", _on_floor(&"caja_de_herramientas", spot, 0.0), true)
	await _ticks(3)
	var kept_time := net.tuning.hold_hidden_time
	for hidden_time: float in [0.0, 0.25]:
		net.tuning.hold_hidden_time = hidden_time
		await _teleport(spot + Vector3(0, 0, 1.5), 0.0)
		await _aim(_box_of(box).get_center())
		await _grab_aimed()
		await _wait_confirmed()
		_check(hands.held_uid() == box, "agarré la caja para lo tapado (Hold Hidden Time %.2f s)" % hidden_time)
		if hands.held_uid() != box:
			continue
		var front := eyes + Vector3(0, -0.2, -1.4)
		await _aim(front)
		hands._distance = view_camera.global_position.distance_to(front)
		await _ticks(40)
		var lost := [""]
		var on_lost := func(_uid: int, reason: String) -> void: lost[0] = reason
		net.replica.hold_lost.connect(on_lost)
		var held_ticks := 0
		for i in 40:
			await _ticks(1)
			if not hands.is_holding():
				break
			held_ticks += 1
		_check(hands.held_uid() == box and lost[0] == "", "a la vista, la sigo sosteniendo")
		var cover := _wall(view_camera.global_position.lerp(_box_of(box).get_center(), 0.5), Vector2(1.5, 1.5))
		held_ticks = 0
		for i in 90:
			await _ticks(1)
			if not hands.is_holding():
				break
			held_ticks += 1
		net.replica.hold_lost.disconnect(on_lost)
		var expected := floori(hidden_time * 60.0)
		_log("medición: con Hold Hidden Time %.2f s, la pared la soltó a los %d ticks" % [hidden_time, held_ticks])
		_check(not hands.is_holding() and lost[0] == "no se ve" and held_ticks >= expected and held_ticks <= expected + 2,
				"con una pared delante y Hold Hidden Time %.2f s, se suelta sola a los %d ticks (se esperaban %d a %d): «%s»" % [
				hidden_time, held_ticks, expected, expected + 2, lost[0]])
		cover.queue_free()
		await _rested(box)
	net.tuning.hold_hidden_time = kept_time
	net.authority._take_from_world(box)
	net.authority.flush({})
	floor_body.queue_free()
	await _ticks(2)


## Soltar del inventario sale hacia la cámara, no hacia donde mira el cuerpo
## (segunda prueba del usuario, 2026-11-15: el cuerpo gira hacia donde camina,
## y caminando para atrás salía para el lado de la cámara). Con el cuerpo
## mirando para atrás de la cámara: lo que esta máquina muestra y lo que deja
## el host salen adelante de la cámara y girados como ella (hasta ese día el
## host no usaba el giro que mandaba esta máquina), y el lugar que busca el
## host cuando no le sirve el propuesto, también.
func _drop_toward_camera() -> void:
	var floor_body := _test_floor()
	var spot := TEST_FLOOR + Vector3(-8, 0, -8)
	_empty_inventory()
	var battery := _spawn(&"bateria", _on_floor(&"bateria", spot + Vector3(0, 0, -1.0), 0.0), true)
	await _ticks(3)
	_check(await _pickup_uid(battery), "recogí la batería para soltarla")
	await _teleport(spot, 0.0)
	for camera_yaw: float in [0.9, -2.2]:
		var state := actor.state
		state.facing_yaw = wrapf(camera_yaw + PI, -PI, PI)
		state.quantize()
		actor.apply_state(state)
		camera.yaw = camera_yaw
		camera.pitch = 0.0
		await _ticks(4)
		var forward := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
		var feet := actor.global_position
		var grid := net.replica.own
		var uid := 0
		for candidate: int in grid.sorted_uids():
			if grid.get_stack(candidate).def_id == &"bateria":
				uid = candidate
		var def := catalog.find(&"bateria")
		var shown: Variant = net.predict_drop_spot(actor, def)
		# El host tiene el espacio físico solo mientras procesa un pedido (handle).
		net.authority._space = get_viewport().world_3d.direct_space_state
		var fallback: Variant = net.authority._drop_spot(actor.owner_peer_id, def)
		net.authority._space = null
		var seq := ui.drop_item(InvProtocol.OWN, uid, grid.get_stack(uid).ver if uid != 0 else 0, 1)
		await _until(func() -> bool: return _answers.has(seq), 2.0)
		var dropped := _uid_near(feet + forward * net.drop_distance + Vector3.UP, &"bateria", 2.0)
		_check(dropped != 0 and _answers.get(seq, [false])[0], "solté la batería (cámara a %.1f rad, cuerpo para atrás)" % camera_yaw)
		for pair: Array in [["lo que se muestra", shown], ["el lugar del host sin propuesta", fallback],
				["lo que dejó el host", net.authority.world.get(dropped, {}).get("xf")]]:
			var place: Variant = pair[1]
			if not place is Transform3D:
				_check(false, "%s: hay lugar" % pair[0])
				continue
			var flat := (place as Transform3D).origin - feet
			flat.y = 0.0
			var turned := absf(angle_difference((place as Transform3D).basis.get_euler().y, camera_yaw))
			_check(flat.length() > 0.3 and flat.normalized().dot(forward) > 0.95 and turned < 0.01,
					"%s sale hacia la cámara (%.2f; 1 es justo adelante, −1 atrás) y girado como ella (%.3f rad de diferencia)" % [
					pair[0], flat.normalized().dot(forward), turned])
		await _rested(dropped)
		if dropped != 0:
			await _pickup_uid(dropped)
			await _teleport(spot, 0.0)
	_empty_inventory()
	floor_body.queue_free()
	await _ticks(2)


# --- En red: la mano adelantada (desde el 2026-11-15) ----------------------------------
#
# --fisica-pair=mano_host y --fisica-pair=mano_cliente, en dos procesos: el
# cliente sostiene la caja de herramientas (el caso original) y la tabla por una
# punta, gira la cámara a 180, 360 y 720 °/s y la para, en el aire; empuja la
# caja contra la pared fina y la gira sin moverse; ve caer una pila. Desde la
# segunda prueba del usuario (2026-11-15), además: «no se ve» con la pared solo
# en el cliente (la suelta él, en el acto) y solo en el host (la suelta el host
# a los Hold Break Time), y lo de abajo de una pila, sacado por el host o
# recogido con E por el cliente, que deja de verse junto con la caída de lo de
# arriba (lo suelto, en el acto); la cámara lenta va al final. Se mide el
# atraso en tres partes: el del controlador de la mano (lo predicho contra
# adónde la lleva la mano), el del host (su cuerpo contra la mano, en el mismo
# tick) y el de lo que se ve (lo dibujado contra la mano), con lo que corrigió.

const MANO_SPOT := TRACK + Vector3(-0.6, 0, 1.4)
const MANO_BOX_AT := MANO_SPOT + Vector3(0, 0, -0.9)
const MANO_PLANK_AT := MANO_SPOT + Vector3(0.6, 0, -0.9)
const MANO_WALL_SPOT := Vector3(THIN_X - 1.9, 0, TRACK.z + 0.6)
const MANO_WALL_BOX_AT := Vector3(THIN_X - 1.05, 0, TRACK.z + 0.6)
const MANO_STACK_AT := MANO_SPOT + Vector3(-1.2, 0, -1.2)
# Las partes 5 a 7, sobre el piso de prueba (lo arman las dos máquinas igual).
const MANO_HIDE_SPOT := TEST_FLOOR + Vector3(0, 0, 2.0)
const MANO_HIDE_BOX_AT := TEST_FLOOR + Vector3(0, 0, 1.0)
const MANO_TOWER_SPOT := TEST_FLOOR + Vector3(3.5, 0, 2.0)
const MANO_TOWER_AT := TEST_FLOOR + Vector3(3.5, 0, 1.1)
const MANO_LONE_AT := TEST_FLOOR + Vector3(4.3, 0, 1.3)


## Host: arma cada parte cuando el cliente terminó la anterior.
func _mano_host() -> void:
	await _wait_local()
	await _until(func() -> bool: return _first_remote() != 0, 60.0)
	var peer := _first_remote()
	_check(peer != 0, "llegó el cliente")
	if peer == 0:
		_finish()
		return
	await _ticks(60)
	await _teleport(MANO_SPOT + Vector3(0, 0, 4.0), 0.0)
	# 1. La caja de herramientas, en el aire.
	var box := _spawn(&"caja_de_herramientas", Transform3D(Basis.IDENTITY, MANO_BOX_AT))
	_move_remote(peer, MANO_SPOT, 0.0)
	_check(await _until(func() -> bool: return _holder(box) == peer, 60.0), "el cliente agarró la caja de herramientas")
	var furthest := await _host_watch(box, peer)
	_check(_holder(box) == 0, "y la soltó")
	await _rested(box)
	net.authority._take_from_world(box)
	# 2. La tabla, por una punta, y lanzada.
	var plank := _spawn(&"tabla_larga", Transform3D(Basis(Vector3.UP, PI / 2.0), MANO_PLANK_AT))
	_check(await _until(func() -> bool: return _holder(plank) == peer, 60.0), "el cliente agarró la tabla")
	var hold: Dictionary = net.bodies.holds().get(plank, {})
	_check(not hold.is_empty() and absf((hold["anchor"] as Vector3).z) > 0.6, "el host la tiene agarrada por la punta (z %.2f)" % [
			(hold.get("anchor", Vector3.ZERO) as Vector3).z])
	var anchor: Vector3 = hold.get("anchor", Vector3.ZERO)
	var speeds: Array[float] = []
	while _holder(plank) == peer:
		var now: Dictionary = net.bodies.holds().get(plank, {})
		if not now.is_empty() and not (now["anchor"] as Vector3).is_equal_approx(anchor):
			_check(false, "la punta agarrada cambió en el host: %s → %s" % [anchor, now["anchor"]])
			anchor = now["anchor"]
		speeds.append(_body(plank).linear_velocity.length())
		await _ticks(1)
	var after: Array[float] = []
	for i in 12:
		after.append(_body(plank).linear_velocity.length())
		await _ticks(1)
	var jumps := 0
	for i in range(1, after.size()):
		if after[i] > after[i - 1] + 3.0:
			jumps += 1
	_check(after.max() > 4.0 and after.max() < 12.0 and jumps <= 1, "la lanzó una sola vez: hasta %.1f m/s, %d saltos de velocidad" % [after.max(), jumps])
	await _rested(plank)
	net.authority._take_from_world(plank)
	# 3. Contra la pared fina.
	box = _spawn(&"caja_de_herramientas", Transform3D(Basis.IDENTITY, MANO_WALL_BOX_AT))
	_move_remote(peer, MANO_WALL_SPOT, -PI / 2.0)
	_check(await _until(func() -> bool: return _holder(box) == peer, 60.0), "el cliente agarró la caja frente a la pared")
	furthest = await _host_watch(box, peer)
	_check(furthest < THIN_X + 0.01, "en el host la caja nunca pasó la pared: lo más lejos, x %.3f (la pared hasta %.3f)" % [furthest, THIN_X + 0.01])
	await _rested(box)
	net.authority._take_from_world(box)
	# 4. Una pila de dos baterías que pierde su apoyo, a la vista del cliente.
	_move_remote(peer, MANO_SPOT, PI / 4.0)
	var bottom := _spawn(&"bateria", Transform3D(Basis.IDENTITY, MANO_STACK_AT))
	var top := _spawn(&"bateria", Transform3D(Basis.IDENTITY, MANO_STACK_AT + Vector3(0, 0.18, 0)))
	await _ticks(150)
	net.authority._take_from_world(bottom)
	net.authority.flush({})
	await _until(func() -> bool: return Mano.rested(net, top), 6.0)
	_log("medición: la batería de arriba quedó a %.3f m del piso" % (_place_of(top).origin.y - MANO_STACK_AT.y))
	# 5. «No se ve» lo decide la máquina del cliente (segunda prueba del usuario,
	#    2026-11-15): la pared la pone solo el cliente, así que el host nunca la
	#    ve tapada y la suelta porque el cliente se lo pidió.
	var floor_body := _test_floor()
	var hide := _spawn(&"caja_de_herramientas", _on_floor(&"caja_de_herramientas", MANO_HIDE_BOX_AT, 0.0))
	_move_remote(peer, MANO_HIDE_SPOT, 0.0)
	_check(await _until(func() -> bool: return _holder(hide) == peer, 60.0), "el cliente agarró la caja para lo tapado")
	var most_hidden := 0.0
	while _holder(hide) == peer:
		most_hidden = maxf(most_hidden, float(net.bodies.holds().get(hide, {}).get("hidden", 0.0)))
		await _ticks(1)
	_check(most_hidden == 0.0, "el cliente la soltó por su cuenta: el host nunca la vio tapada (lo más, %.3f s)" % most_hidden)
	await _rested(hide)
	# 6. Si el host la ve tapada y la máquina del cliente no (la pared, solo en
	#    el host), el host la suelta igual, a los Hold Break Time.
	_check(await _until(func() -> bool: return _holder(hide) == peer, 30.0), "el cliente la volvió a agarrar")
	await _ticks(40)
	var remote := net.authority.actor_of(peer)
	var hold_now: Dictionary = net.bodies.holds().get(hide, {})
	if remote != null and not hold_now.is_empty():
		var point: Vector3 = _place_of(hide) * (hold_now["anchor"] as Vector3)
		var cover := _wall(InvAuthority.eyes(remote, BaseRegistry.world_position(remote.state)).lerp(point, 0.5), Vector2(1.5, 1.5))
		var held_ticks := 0
		while _holder(hide) == peer and held_ticks < 120:
			held_ticks += 1
			await _ticks(1)
		var break_ticks := roundi(net.tuning.hold_break_time * 60.0)
		_check(_holder(hide) == 0 and held_ticks >= break_ticks - 2 and held_ticks <= break_ticks + 6,
				"con la pared solo en el host, el host la soltó a los %d ticks (Hold Break Time: %d)" % [held_ticks, break_ticks])
		cover.queue_free()
	await _rested(hide)
	net.authority._take_from_world(hide)
	net.authority.flush({})
	# 7. Lo que recoge el cliente: suelto, se va en el acto; debajo de otro, se
	#    va junto con la caída (decidido por el usuario el 2026-11-15).
	var lone := _spawn(&"bateria", _on_floor(&"bateria", MANO_LONE_AT, 0.0))
	var base_place := _on_floor(&"caja_de_herramientas", MANO_TOWER_AT, 0.0)
	var base := _spawn(&"caja_de_herramientas", base_place)
	var base_top := (base_place * InvItemPhysics.body_bounds(catalog.find(&"caja_de_herramientas"))).end.y
	var on_top := _spawn(&"bateria", _on_floor(&"bateria", Vector3(MANO_TOWER_AT.x, base_top + 0.002, MANO_TOWER_AT.z), 0.0))
	_move_remote(peer, MANO_TOWER_SPOT, 0.0)
	_check(await _until(func() -> bool: return not net.authority.world.has(lone) and not net.authority.world.has(base), 60.0),
			"el cliente recogió la batería suelta y la caja de abajo")
	await _until(func() -> bool: return Mano.rested(net, on_top), 6.0)
	net.authority._take_from_world(on_top)
	net.authority.flush({})
	floor_body.queue_free()
	_move_remote(peer, MANO_SPOT, PI / 4.0)
	# Al final: lo que se adoptó y lo que no, y por qué.
	await _until(func() -> bool: return multiplayer.get_peers().is_empty(), 90.0)
	var stats: Dictionary = net.bodies.adoption.get(peer, {})
	_log("medición: lo que afirmó el cliente de lo que sostenía: %s" % net.bodies.adoption_text(peer))
	_check(stats.get("adoptada", 0) + stats.get("igual", 0) > 100, "el host adoptó o coincidió con lo que afirmaba el cliente (%d y %d)" % [
			stats.get("adoptada", 0), stats.get("igual", 0)])
	_finish()


## Host: mientras el cliente sostiene ese objeto, lo más lejos en x que llega
## su cuerpo; vuelve cuando lo suelta.
func _host_watch(uid: int, peer: int) -> float:
	var furthest := -INF
	while _holder(uid) == peer:
		var body := _body(uid)
		if body != null:
			furthest = maxf(furthest, (body.global_transform * InvItemPhysics.body_bounds(body.def)).end.x)
		await _ticks(1)
	return furthest


## Cliente: las ocho partes.
func _mano_cliente() -> void:
	_test_floor()
	await _wait_local()
	await _until(func() -> bool: return actor.global_position.distance_to(MANO_SPOT) < 0.3 and _uid_near(MANO_BOX_AT, &"caja_de_herramientas") != 0, 60.0)
	var box := _uid_near(MANO_BOX_AT, &"caja_de_herramientas")
	_check(box != 0, "el host me puso frente a la caja de herramientas")
	if box == 0:
		_finish()
		return
	await _ticks(30)
	# 1. En el aire, la caja de herramientas.
	if await _mano_grab(box, _box_of(box).get_center()):
		camera.pitch = 0.9
		hands._distance = 1.0
		await _ticks(60)
		for speed: float in [180.0, 360.0, 720.0]:
			await _mano_turn("caja de herramientas", speed)
		var before := hands._shown
		var floor_hit := get_viewport().world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
				before.origin, before.origin + Vector3.DOWN * 10.0, InvAuthority.WORLD_MASK))
		var floor_y: float = (floor_hit.get("position", Vector3.ZERO) as Vector3).y
		var drop_height := _lowest_of(net.world_view(box)) - floor_y
		hands.release()
		await _ticks(1)
		var copy := net.world_view(box)
		var jump := copy.global_transform.origin.distance_to(before.origin) if copy != null else 0.0
		_check(jump < 0.05, "al soltarla no salta hacia atrás: se movió %.3f m en el primer tick" % jump)
		# Lo que se ve al caer (lo encontró el usuario en la notebook: soltada de
		# más de medio metro, se metía en el piso unos 800 ms).
		var sunk := 0.0
		for i in 120:
			await _ticks(1)
			copy = net.world_view(box)
			if copy != null:
				sunk = maxf(sunk, floor_y - _lowest_of(copy))
		_log("medición: soltada de %.2f m, lo más que se vio metida en el piso al caer: %.1f mm" % [drop_height, sunk * 1000.0])
		_check(not floor_hit.is_empty() and drop_height > 0.5 and sunk <= 0.01,
				"soltada de %.2f m, lo que se ve no se mete en el piso al caer: lo más, %.1f mm" % [drop_height, sunk * 1000.0])
	# 2. La tabla por una punta, girada y lanzada.
	await _until(func() -> bool: return _uid_near(MANO_PLANK_AT, &"tabla_larga") != 0, 30.0)
	var plank := _uid_near(MANO_PLANK_AT, &"tabla_larga")
	camera.pitch = 0.0
	await _ticks(30)
	var tip := _place_of(plank) * Vector3(0, 0.02, -0.74)
	if plank != 0 and await _mano_grab(plank, tip):
		var anchor := hands._anchor
		_check(absf(anchor.z) > 0.6, "la agarré por la punta (z %.2f)" % anchor.z)
		camera.pitch = 0.9
		hands._distance = 0.9
		await _ticks(60)
		await _mano_turn("tabla por una punta", 360.0)
		_check(hands._anchor.is_equal_approx(anchor), "girando, sigue agarrada por la misma punta")
		hands.throw_held()
		await _ticks(30)
	# 3. La caja contra la pared fina: empujar, y girar sin moverse.
	await _until(func() -> bool: return actor.global_position.distance_to(MANO_WALL_SPOT) < 0.3 and _uid_near(MANO_WALL_BOX_AT, &"caja_de_herramientas") != 0, 60.0)
	box = _uid_near(MANO_WALL_BOX_AT, &"caja_de_herramientas")
	await _ticks(30)
	if box != 0 and await _mano_grab(box, _box_of(box).get_center()):
		camera.pitch = 0.0
		var space := get_viewport().world_3d.direct_space_state
		var crossed := 0
		var furthest := -INF
		var corrections := hands.held_version_resets
		for i in 150:
			if i < 60:
				# Hasta unos 40 cm detrás de la pared: empuja sin llegar a la distancia en
				# que se suelta sola (Hold Break Distance, 0,8 m).
				hands._distance = minf(hands._distance + 0.02, 2.0)
			elif i < 120:
				# Girar sin moverse: alrededor del eje vertical de la vista.
				hands._rotation = (Quaternion(Vector3.UP, deg_to_rad(4.0)) * hands._rotation).normalized()
			await _ticks(1)
			if net.world_view(box) == null or hands.held_uid() != box:
				_check(false, "la sigo sosteniendo contra la pared (tick %d)" % i)
				break
			var shown := hands._shown
			var reach := (shown * InvItemPhysics.body_bounds(net.world_view(box).def)).end.x
			furthest = maxf(furthest, reach)
			if reach > THIN_X + 0.01 or InvItemPhysics.blocked_inset(space, net.world_view(box).def, shown, InvAuthority.WORLD_MASK):
				crossed += 1
		_check(crossed == 0, "lo que se ve nunca se mete en la pared ni la pasa, empujando y girando sin moverse (lo más lejos, x %.3f; la pared de %.3f a %.3f)" % [
				furthest, THIN_X - 0.01, THIN_X + 0.01])
		_log("medición: contra la pared, %d correcciones en 150 ticks (la más grande %.3f m)" % [
				hands.held_version_resets - corrections, hands.max_held_correction])
		hands.release()
		await _ticks(60)
	# 4. Ver caer una pila.
	await _until(func() -> bool: return actor.global_position.distance_to(MANO_SPOT) < 0.3, 30.0)
	await _until(func() -> bool: return _uid_near(MANO_STACK_AT + Vector3(0, 0.18, 0), &"bateria", 0.05) != 0, 20.0)
	var top := _uid_near(MANO_STACK_AT + Vector3(0, 0.18, 0), &"bateria", 0.05)
	var bottom := _uid_near(MANO_STACK_AT, &"bateria", 0.05)
	var heights := {}
	var start := Time.get_ticks_msec()
	# Cuándo se dejó de ver la de abajo y cuándo empezó a caer la de arriba, en
	# el tick del host que se muestra (segunda prueba del usuario, 2026-11-15:
	# lo de arriba quedaba en el aire).
	var top_start := net.world_view(top).global_position.y if net.world_view(top) != null else NAN
	var timing := [-1.0, -1.0]
	while Time.get_ticks_msec() - start < 6000:
		var copy := net.world_view(top)
		if copy != null:
			heights[snappedf(copy.global_position.y - MANO_STACK_AT.y, 0.005)] = true
		await _ticks(1)
		_note_fall(timing, bottom, top, top_start)
		if heights.size() > 3 and copy != null and copy.global_position.y < MANO_STACK_AT.y + 0.03 and Mano.rested(net, top):
			break
	_check(heights.size() >= 4 and net.world_view(top) != null and net.world_view(top).global_position.y < MANO_STACK_AT.y + 0.03,
			"vi caer la batería de arriba durante la caída (%d alturas distintas), no solo al final" % heights.size())
	_check_fall_timing(timing, "la batería de abajo (la sacó el host)")
	# 5. «No se ve» lo decide esta máquina, en el acto: la pared la pone solo
	#    esta máquina (el host no la tiene).
	await _until(func() -> bool: return actor.global_position.distance_to(MANO_HIDE_SPOT) < 0.3 \
			and _uid_near(MANO_HIDE_BOX_AT, &"caja_de_herramientas", 0.3) != 0, 60.0)
	box = _uid_near(MANO_HIDE_BOX_AT, &"caja_de_herramientas", 0.3)
	await _ticks(30)
	var lost := [""]
	var on_lost := func(_uid: int, reason: String) -> void: lost[0] = reason
	net.replica.hold_lost.connect(on_lost)
	if box != 0 and await _mano_grab(box, _box_of(box).get_center()):
		camera.pitch = 0.0
		hands._distance = 1.2
		await _ticks(40)
		var released_before := hands.hidden_releases
		var cover := _wall(view_camera.global_position.lerp(_box_of(box).get_center(), 0.5), Vector2(1.5, 1.5))
		var held_ticks := 0
		while hands.is_holding() and held_ticks < 60:
			await _ticks(1)
			if hands.is_holding():
				held_ticks += 1
		_log("medición: tapada solo en esta máquina, se soltó a los %d ticks" % held_ticks)
		_check(not hands.is_holding() and hands.hidden_releases == released_before + 1 and held_ticks <= 2,
				"con la pared solo en esta máquina, la soltó esta máquina en el acto: a los %d ticks" % held_ticks)
		cover.queue_free()
	await _until(func() -> bool: return Mano.rested(net, box) and net.replica.world.get(box, {}).get("holder", 0) == 0, 8.0)
	# 6. La pared solo en el host: esta máquina no la ve tapada, y el host la
	#    suelta igual a los Hold Break Time.
	await _ticks(20)
	if box != 0 and await _mano_grab(box, _box_of(box).get_center()):
		camera.pitch = 0.0
		hands._distance = 1.2
		var released_before := hands.hidden_releases
		lost[0] = ""
		await _until(func() -> bool: return not hands.is_holding(), 6.0)
		_check(lost[0] == "no se ve" and hands.hidden_releases == released_before,
				"con la pared solo en el host, me la soltó el host: «%s»" % lost[0])
	net.replica.hold_lost.disconnect(on_lost)
	# 7. Recoger con E: lo suelto se va en el acto; lo de abajo de una torre, junto
	#    con la caída de lo de arriba (decidido por el usuario el 2026-11-15).
	await _until(func() -> bool: return actor.global_position.distance_to(MANO_TOWER_SPOT) < 0.3 \
			and _uid_near(MANO_LONE_AT, &"bateria", 0.3) != 0 and _uid_near(MANO_TOWER_AT, &"caja_de_herramientas", 0.3) != 0, 60.0)
	await _ticks(30)
	var lone := _uid_near(MANO_LONE_AT, &"bateria", 0.3)
	var base := _uid_near(MANO_TOWER_AT, &"caja_de_herramientas", 0.3)
	var on_top := 0
	for uid: int in net.replica.world:
		if uid != lone and net.replica.world[uid]["stack"].def_id == &"bateria" \
				and Vector2((net.replica.world[uid]["pos"] as Vector3).x - MANO_TOWER_AT.x, (net.replica.world[uid]["pos"] as Vector3).z - MANO_TOWER_AT.z).length() < 0.2:
			on_top = uid
	var waited_before := net.bodies.pickups_waited
	await _aim(_box_of(lone).get_center())
	_check(ui.interaction_target().get("id", 0) == lone, "miro la batería suelta")
	ui._interact()
	await _ticks(1)
	_check(net.world_view(lone) == null and net.bodies.pickups_waited == waited_before,
			"la batería suelta, sin nada encima, se dejó de ver en el acto")
	await _until(func() -> bool: return not net.replica.world.has(lone), 5.0)
	await _aim(_box_of(base).get_center())
	_check(on_top != 0 and ui.interaction_target().get("id", 0) == base, "miro la caja de abajo de la torre")
	top_start = net.world_view(on_top).global_position.y if net.world_view(on_top) != null else NAN
	timing = [-1.0, -1.0]
	var pressed := Time.get_ticks_msec()
	ui._interact()
	var gone_msec := -1
	while Time.get_ticks_msec() - pressed < 4000 and (timing[0] < 0.0 or timing[1] < 0.0):
		await _ticks(1)
		_note_fall(timing, base, on_top, top_start)
		if timing[0] >= 0.0 and gone_msec < 0:
			gone_msec = Time.get_ticks_msec() - pressed
	_log("medición: la caja de abajo, recogida con E, se dejó de ver a los %d ms" % gone_msec)
	_check(net.bodies.pickups_waited == waited_before + 1, "la caja de abajo esperó al host (tenía algo encima)")
	_check_fall_timing(timing, "la caja de abajo (la recogí yo)")
	await _until(func() -> bool: return actor.global_position.distance_to(MANO_SPOT) < 0.3, 30.0)
	await _ticks(30)
	# 8. Con cámara lenta del mundo: corrige igual de poco.
	lab.ability_presses = (lab.ability_presses + 1) & 0xFF
	await _ticks(60)
	var slow := SimClock.world_scale(lab._clock.tick)
	box = _uid_near(MANO_STACK_AT, &"bateria", 0.3)
	if box != 0 and await _mano_grab(box, _box_of(box).get_center()):
		camera.pitch = 0.6
		hands._distance = 1.0
		await _ticks(40)
		await _mano_turn("batería con cámara lenta (escala %.2f)" % slow, 180.0)
		hands.release()
	lab.ability_presses = (lab.ability_presses + 1) & 0xFF
	await _ticks(60)
	_log("medición: la predicción de lo sostenido, en total: %s" % hands.prediction_text())
	_finish()


## Cliente: anota en `timing` el tick del host que se mostraba cuando dejó de
## verse `gone` ([0]) y cuando `top` bajó más de 2 mm desde `top_start` ([1]).
func _note_fall(timing: Array, gone: int, top: int, top_start: float) -> void:
	var at: float = net.bodies.render_tick.call()
	if timing[0] < 0.0 and net.world_view(gone) == null:
		timing[0] = at
	var copy := net.world_view(top)
	if timing[1] < 0.0 and copy != null and not is_nan(top_start) and copy.global_position.y < top_start - 0.002:
		timing[1] = at


## Cliente: lo de abajo se dejó de ver junto con la caída de lo de arriba, a
## no más de 4 ticks (hasta la segunda prueba del usuario, 2026-11-15, lo que
## sacaba el host se iba unos 6 ticks antes, y lo que recogía esta máquina,
## además, todo el ping antes).
func _check_fall_timing(timing: Array, what: String) -> void:
	var gap: float = timing[1] - timing[0]
	_log("medición: %s se dejó de ver en el tick %.1f y lo de arriba empezó a caer en el %.1f: %.1f ticks después" % [
			what, timing[0], timing[1], gap])
	_check(timing[0] >= 0.0 and timing[1] >= 0.0 and absf(gap) <= 4.0,
			"%s se deja de ver junto con la caída de lo de arriba (%.1f ticks de diferencia)" % [what, gap])


## Cliente: apunta, agarra y espera la confirmación.
func _mano_grab(uid: int, point: Vector3) -> bool:
	await _aim(point)
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	var ok := await _until(func() -> bool: return hands.held_uid() == uid and hands._confirmed, 5.0)
	_check(ok, "agarré %d y el host lo confirmó" % uid)
	return ok


## Cliente: gira la cámara a `speed` °/s durante medio segundo y la para otro
## tanto; mide el atraso del controlador (lo predicho), del host (su cuerpo, en
## el mismo tick) y de lo que se ve, en grados vistos desde los ojos, y cuánto
## tarda cada uno en quedar a menos de 2° al parar.
func _mano_turn(what: String, speed: float) -> void:
	var turn_ticks := 30
	var eyes_at := {}
	var worst := {"control": 0.0, "host": 0.0, "visto": 0.0}
	var settle := {"control": -1, "host": -1, "visto": -1}
	var net_diff := 0.0
	var corrections := hands.held_version_resets
	var checked := -1
	var stop_tick := -1
	for i in turn_ticks + 45:
		if i < turn_ticks:
			camera.yaw += deg_to_rad(speed) / 60.0
		await _ticks(1)
		var tick := hands._done_tick
		if i == turn_ticks:
			stop_tick = tick
		var eyes := InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state))
		eyes_at[tick] = eyes
		var goal: Transform3D = hands._goals.get(tick, Transform3D())
		var pred: Array = hands._pred.get(tick, [])
		if pred.is_empty():
			continue
		var errors := {"control": _angle_at(eyes, goal.origin, (pred[0] as Transform3D) * hands._anchor),
				"visto": _angle_at(eyes, goal.origin, hands._shown * hands._anchor)}
		var newest := net.bodies.newest_sample(hands.held_uid())
		if newest.size() >= 7 and newest[0] > checked and eyes_at.has(newest[0]) and hands._goals.has(newest[0]):
			checked = newest[0]
			var host_goal: Transform3D = hands._goals[newest[0]]
			errors["host"] = _angle_at(eyes_at[newest[0]], host_goal.origin, (newest[1] as Transform3D) * hands._anchor)
			var mine: Array = hands._pred.get(newest[0], [])
			if not mine.is_empty():
				net_diff = maxf(net_diff, ((mine[0] as Transform3D) * hands._anchor).distance_to((newest[1] as Transform3D) * hands._anchor))
		for key: String in errors:
			if i < turn_ticks:
				worst[key] = maxf(worst[key], errors[key])
			elif settle[key] < 0 and errors[key] < 2.0:
				settle[key] = (tick if key != "host" else checked) - stop_tick
	var ms := func(ticks: int) -> String: return "%d ms" % roundi(ticks * 1000.0 / 60.0) if ticks >= 0 else "no llegó"
	var fixed: int = hands.held_version_resets - corrections
	_log("medición: %s a %d °/s: girando, atraso del controlador %.1f°, del host %.1f°, de lo que se ve %.1f°; al parar, a menos de 2° en %s, %s y %s; lo predicho y el host, como mucho a %.3f m en el mismo tick; %d correcciones (ida y vuelta %d ms)" % [
			what, speed, worst["control"], worst["host"], worst["visto"], ms.call(settle["control"]), ms.call(settle["host"]),
			ms.call(settle["visto"]), net_diff, fixed, roundi(lab._clock.rtt_ms)])
	_check(worst["visto"] <= worst["control"] + 3.0 and settle["visto"] >= 0 and settle["visto"] <= settle["control"] + 6,
			"%s a %d °/s: lo que se ve no se atrasa más que el controlador de la mano (%.1f° y %.1f°): la red no suma atraso" % [
			what, speed, worst["visto"], worst["control"]])
	_check(fixed <= 6, "%s a %d °/s: en el aire casi no hay correcciones (%d)" % [what, speed, fixed])


static func _angle_at(eyes: Vector3, a: Vector3, b: Vector3) -> float:
	return rad_to_deg((a - eyes).angle_to(b - eyes))


## Lo más bajo del modelo de un objeto, como se ve (en un cliente, su copia).
static func _lowest_of(view: InvWorldItem) -> float:
	var lowest := INF
	if view == null:
		return lowest
	for vertex in InvReach.item_faces(view.def):
		lowest = minf(lowest, (view.global_transform * vertex).y)
	return lowest


## El selector con muchos objetos lejanos, dormidos: el mismo grupo cercano y
## 0, 300 y 3000 objetos a 1 km. Se mide el selector (los dos rayos), el rayo
## del host y la cuenta que recorre todos (la de antes), los candidatos que
## mira cada uno, y aparte lo que cuesta la física por paso y lo que sale por
## red de poses. Al final se sacan y no queda nada.
func _measure() -> void:
	await _teleport(Vector3(ROW_FRONT_AT.x, 0, ROW_FRONT_AT.z - 1.0), PI)
	await _aim(_box_of(_uid_near(ROW_FRONT_AT, &"bateria")).get_center())
	var bodies_before := net.bodies.views().size()
	var index_before := net.authority.space.index.size()
	var far: Array[int] = []
	var lines := PackedStringArray()
	for count: int in [0, 300, 3000]:
		while far.size() < count:
			var stack := InvStack.make(net.authority.alloc_uid(), &"llave", 1, {})
			var i := far.size()
			net.authority._put_in_world(stack, TRACK + Vector3(1000.0 + (i % 60) * 1.5, 0, floorf(i / 60.0) * 1.5))
			far.append(stack.uid)
		net.authority.flush({})
		await _ticks(5)
		var aim := camera.aim_ray()
		var start := Time.get_ticks_usec()
		for i in 200:
			net.interaction_target(actor, aim[0], aim[1], false)
		var selector := (Time.get_ticks_usec() - start) / 200.0
		var eyes := InvAuthority.eyes(actor, actor.global_position)
		var direction: Vector3 = aim[1]
		var space := get_viewport().world_3d.direct_space_state
		start = Time.get_ticks_usec()
		var hit := {}
		for i in 200:
			hit = InvReach.first_hit(space, eyes, direction, 4.7, net.authority.space, catalog, InvReach.own_shapes(actor))
		var indexed := (Time.get_ticks_usec() - start) / 200.0
		var tested := InvReach.last_tested
		var candidates := net.authority.space.index.last_candidates
		start = Time.get_ticks_usec()
		var reference := {}
		for i in 20:
			reference = InvReach.first_hit(space, eyes, direction, 4.7, net.authority.world, catalog, InvReach.own_shapes(actor))
		var full := (Time.get_ticks_usec() - start) / 20.0
		_check(hit.get("id", -1) == reference.get("id", -1) and (hit.get("point", Vector3.ZERO) as Vector3).is_equal_approx(
				reference.get("point", Vector3.ZERO)), "con %d lejos, el índice da lo mismo que recorrer todos" % count)
		# Lo que tarda un cuadro entero (la física de Jolt y todo lo demás), en
		# tiempo real: con los objetos lejos dormidos, crece poco; y lo que sale de
		# poses por red en 30 ticks (los dormidos no se mandan, salvo uno por vez).
		var sent := net.bodies.poses_sent
		var frame_start := Time.get_ticks_usec()
		for i in 30:
			await get_tree().physics_frame
		var frame_ms := (Time.get_ticks_usec() - frame_start) / 30.0 / 1000.0
		lines.append("%d lejos: selector %.1f µs, rayo con índice %.1f µs (%d candidatos, %d con triángulos), recorriendo todos %.1f µs, un cuadro entero %.2f ms, poses enviadas en 30 ticks %d (%d bytes)" % [
				count, selector, indexed, candidates, tested, full, frame_ms, net.bodies.poses_sent - sent, (net.bodies.poses_sent - sent) * InvBodies.POSE_BYTES])
	for line in lines:
		_log("medición: " + line)
	for uid in far:
		net.authority._take_from_world(uid)
	net.authority.flush({})
	await _ticks(5)
	_check(net.bodies.views().size() == bodies_before and net.authority.space.index.size() == index_before
			and net.authority.space.size() == net.authority.world.size(), "sacados los 3000, no queda ninguno en los cuerpos ni en el índice (%d y %d)" % [
			net.bodies.views().size(), net.authority.space.index.size()])


# --- En red ---------------------------------------------------------------------------

## Tres procesos en esta PC: el host, A (con la internet que se le pida, por
## ejemplo --sim-rtt=200 --sim-jitter=40 --sim-loss=5) y B, que entra tarde.
## El host pone cuatro botiquines frente a A y lo para ahí; los tiempos de cada
## paso salen de cuando A suelta el primero (cada uno lo mide en su reloj):
##
## 1. A agarra el primero por donde lo toca, lo mueve con la mano (se ve en la
##    mano sin esperar al host) y lo suelta: el host lo ve movido y suelto.
## 2. A agarra el segundo y lo suelta antes de que conteste el host: queda
##    suelto en los dos, sin trabarse.
## 3. A los 3 s, el host agarra el tercero, y A, que todavía no lo sabe, lo pide
##    también: gana el host, A recibe el rechazo y deja de verlo en la mano.
## 4. A los 6 s, A lanza el cuarto: el host le da un solo impulso.
## 5. A los 9 s, A agarra el primero y el host lo mata: se suelta.
## 6. A los 13 s, A agarra el segundo y lo mueve hasta irse. B entra (lo
##    arranca el lanzador unos 30 s después) y lo ve sostenido por A y
##    moviéndose, y la tabla cruzada girada y dormida. A se va con el segundo en
##    la mano: el host lo suelta y B lo ve soltarse y caer.
##
## Al final el host y B escriben el mundo (lugar, quién lo sostiene, si duerme)
## para compararlo.
const PAIR_SPOT := TRACK + Vector3(0.8, 0, 1.6)
const PAIR_OFFSETS := [Vector3(0, 0, -1.0), Vector3(0.6, 0, -1.0), Vector3(-0.6, 0, -1.0), Vector3(1.2, 0, -1.0)]


func _wait_local() -> void:
	# Tener réplica no implica poder jugar: antes de sincronizar el reloj el
	# cliente todavía no simula al actor ni manda inputs. Las acciones de mano
	# y estas pruebas tienen que esperar esa misma condición.
	await _until(func() -> bool: return is_instance_valid(lab._local_actor) and net.replica.has_state \
			and lab._local_actor.simulated, 60.0)
	actor = lab._local_actor
	await _set_first_person(true)
	await _ticks(30)


func _first_remote() -> int:
	for peer in multiplayer.get_peers():
		if net.authority != null and net.authority.actor_of(peer) != null:
			return peer
	return 0


## Host: pone al actor de otro jugador ahí, como un evento del host.
func _move_remote(peer: int, position: Vector3, yaw: float) -> void:
	var remote := net.authority.actor_of(peer)
	if remote == null:
		return
	var state := remote.state
	state.position = position
	state.velocity = Vector3.ZERO
	state.facing_yaw = yaw
	state.mode = ActorState.Mode.GROUND
	state.on_floor = true
	state.base_id = 0
	state.epoch += 1
	state.quantize()
	remote.apply_state(state)
	remote.teleported()


## Los cuatro botiquines del host, en el orden de PAIR_OFFSETS (0 si falta).
func _pair_objects() -> Array[int]:
	var out: Array[int] = []
	for offset: Vector3 in PAIR_OFFSETS:
		out.append(_uid_near(PAIR_SPOT + offset, &"botiquin", 0.25))
	return out


func _holder(uid: int) -> int:
	var world := net.authority.world if net.authority != null else net.replica.world
	return world.get(uid, {}).get("holder", 0)


func _print_world() -> void:
	var world := net.authority.world if net.authority != null else net.replica.world
	var lines := PackedStringArray()
	var uids := world.keys()
	uids.sort()
	for uid: int in uids:
		var item: Dictionary = world[uid]
		if not item.get("sleep", true):
			continue
		var pos: Vector3 = item["pos"]
		lines.append("%d %s (%.2f, %.2f, %.2f) sostiene %d" % [uid, item["stack"].def_id, pos.x, pos.y, pos.z, item.get("holder", 0)])
	_log("mundo (lo que duerme): " + "; ".join(lines))


func _pair_host() -> void:
	await _wait_local()
	var a := 0
	await _until(func() -> bool: return _first_remote() != 0, 60.0)
	a = _first_remote()
	_check(a != 0, "llegó A")
	if a == 0:
		_finish()
		return
	await _ticks(60)
	var objects: Array[int] = []
	for offset: Vector3 in PAIR_OFFSETS:
		var stack := InvStack.make(net.authority.alloc_uid(), &"botiquin", 1, {})
		net.authority._put_in_world(stack, PAIR_SPOT + offset)
		objects.append(stack.uid)
	net.authority.flush({})
	_move_remote(a, PAIR_SPOT, 0.0)
	await _teleport(PAIR_SPOT + Vector3(-1.6, 0, 0), 0.0)
	# 1. A agarra el primero, lo mueve y lo suelta.
	_check(await _until(func() -> bool: return _holder(objects[0]) == a, 60.0), "A agarró el primero")
	_check(await _until(func() -> bool: return _holder(objects[0]) == 0, 30.0), "y lo soltó")
	var released := Time.get_ticks_msec()
	await _ticks(2)
	var moved := (net.authority.world[objects[0]]["pos"] as Vector3).distance_to(PAIR_SPOT + PAIR_OFFSETS[0])
	_check(moved > 0.2, "A lo movió con la mano: está a %.2f m de donde estaba" % moved)
	# 3. La carrera por el tercero.
	await _until(func() -> bool: return Time.get_ticks_msec() >= released + 3000, 10.0)
	await _aim(_box_of(objects[2]).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _wait_confirmed()
	_check(_holder(objects[2]) == actor.owner_peer_id, "el host agarra el tercero")
	await _ticks(120)
	_check(_holder(objects[2]) == actor.owner_peer_id, "y lo sigue teniendo: el pedido de A no se lo sacó")
	hands.release()
	_check(_holder(objects[1]) == 0, "el segundo (A lo agarró y lo soltó enseguida) quedó suelto")
	# 4. A lanza el cuarto.
	var fastest := 0.0
	while Time.get_ticks_msec() < released + 9000:
		await _ticks(1)
		fastest = maxf(fastest, _body(objects[3]).linear_velocity.length() if _body(objects[3]) != null else 0.0)
	var expected := net.tuning.throw_impulse / net.tuning.item_mass
	_check(fastest > expected * 0.6 and fastest < expected * 1.6 + net.tuning.hold_move_limit,
			"A lanzó el cuarto, con un solo impulso: llegó a %.1f m/s (el impulso da %.1f)" % [fastest, expected])
	# 5. A agarra el primero y muere.
	_check(await _until(func() -> bool: return _holder(objects[0]) == a, 10.0), "A agarró otra vez el primero")
	await _ticks(30)
	var remote := net.authority.actor_of(a)
	if remote != null:
		ActorVitals.of(remote.state, net.tuning).apply(-1000, 0)
	await _ticks(10)
	_check(_holder(objects[0]) == 0, "A murió: se le soltó")
	# 6. A agarra el segundo, lo mueve, entra B y A se va con él en la mano.
	_check(await _until(func() -> bool: return _holder(objects[1]) == a, 10.0), "A agarró el segundo para irse con él")
	_check(await _until(func() -> bool: return not a in multiplayer.get_peers(), 90.0), "A se fue")
	await _ticks(20)
	_check(_holder(objects[1]) == 0, "A se fue con el segundo en la mano: el host lo soltó")
	await _until(func() -> bool: return Mano.rested(net, objects[1]), 10.0)
	await _ticks(60)
	_print_world()
	await _until(func() -> bool: return multiplayer.get_peers().is_empty(), 60.0)
	_finish()


func _pair_a() -> void:
	await _wait_local()
	await _until(func() -> bool: return actor.global_position.distance_to(PAIR_SPOT) < 0.3 and not _pair_objects().has(0), 60.0)
	var objects := _pair_objects()
	_check(not objects.has(0) and actor.global_position.distance_to(PAIR_SPOT) < 0.3, "el host me puso frente a los cuatro botiquines")
	if objects.has(0):
		_finish()
		return
	await _ticks(30)
	# 1. Agarra el primero, lo mueve y lo suelta.
	await _aim(_box_of(objects[0]).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	_check(hands.held_uid() == objects[0], "lo agarra ya, sin esperar al host")
	_check(await _until(func() -> bool: return hands._confirmed, 5.0), "y el host lo confirma")
	for i in 90:
		camera.yaw += 0.006
		hands._distance = 1.3
		await _ticks(1)
	var shown := _place_of(objects[0])
	var goal: Transform3D = hands._goals.get(hands._done_tick, Transform3D())
	var held_at := shown * hands._anchor
	_check(held_at.distance_to(goal.origin) < 0.25,
			"lo que sostiene se ve en la mano, adelantado: el punto agarrado a %.3f m de donde lo lleva la mano (con %d ms de ida y vuelta)" % [
			held_at.distance_to(goal.origin), roundi(lab._clock.rtt_ms)])
	hands.release()
	var released := Time.get_ticks_msec()
	var half_rtt := roundi(lab._clock.rtt_ms / 2.0)
	# 2. Agarra el segundo y lo suelta antes de que conteste el host.
	await _aim(_box_of(objects[1]).get_center())
	var grabs := hands.grabs
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	_mouse_button(MOUSE_BUTTON_RIGHT, true)
	_mouse_button(MOUSE_BUTTON_RIGHT, false)
	_check(hands.grabs == grabs + 1 and not hands.is_holding(), "agarra el segundo y lo suelta en el mismo cuadro")
	await _ticks(90)
	_check(_holder(objects[1]) == 0 and not hands.is_holding(), "llega todo y queda suelto, no trabado en la mano")
	# 3. La carrera: lo pide cuando el host ya lo agarró, sin saberlo todavía.
	await _until(func() -> bool: return Time.get_ticks_msec() >= released + 3000 + half_rtt, 10.0)
	await _aim(_box_of(objects[2]).get_center())
	var refused := hands.refused
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	var tried := hands.grabs > grabs + 1
	await _until(func() -> bool: return hands.refused > refused or (hands._confirmed and hands.is_holding()), 4.0)
	if tried:
		_check(hands.refused > refused and not hands.is_holding(), "pierde la carrera por el tercero: el host dice que no y deja de verse en la mano")
	else:
		_log("la carrera: cuando la pidió ya veía el tercero en la mano del host (no salió el pedido)")
		_check(_holder(objects[2]) != 0, "pierde la carrera por el tercero: ya lo veía en la mano del host")
	# 4. Lanza el cuarto.
	await _until(func() -> bool: return Time.get_ticks_msec() >= released + 6000, 10.0)
	await _aim(_box_of(objects[3]).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	await _until(func() -> bool: return hands._confirmed, 5.0)
	camera.pitch = 0.2
	await _ticks(20)
	var thrown := hands.throws
	hands.throw_held()
	_check(hands.throws == thrown + 1 and not hands.is_holding(), "lanza el cuarto")
	# 5. Agarra el primero; el host lo mata.
	await _until(func() -> bool: return Time.get_ticks_msec() >= released + 9000, 10.0)
	await _aim(_box_of(objects[0]).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	var deaths := actor.state.deaths
	_check(await _until(func() -> bool: return actor.state.deaths != deaths, 6.0), "el host lo mata con el primero en la mano")
	await _ticks(10)
	_check(not hands.is_holding(), "y se le suelta")
	# 6. Agarra el segundo y lo mueve hasta irse.
	await _until(func() -> bool: return Time.get_ticks_msec() >= released + 13000, 10.0)
	await _rested_all(objects)
	await _aim(_box_of(objects[1]).get_center())
	await _press(MOUSE_BUTTON_RIGHT)
	await _release(MOUSE_BUTTON_RIGHT)
	_check(await _until(func() -> bool: return hands._confirmed, 5.0), "agarra el segundo para irse con él")
	var wiggle := 0
	while Time.get_ticks_msec() < released + 40000 and hands.is_holding():
		wiggle += 1
		camera.yaw = 0.3 * sin(wiggle / 40.0)
		await _ticks(1)
	_check(hands.is_holding(), "lo sigue sosteniendo hasta irse")
	_finish()


## Lo que sostiene otro jugador que no es el host ni esta máquina (0 si nada).
func _held_by_other() -> int:
	var me := multiplayer.get_unique_id()
	for uid: int in net.replica.world:
		var holder: int = net.replica.world[uid].get("holder", 0)
		if holder != 0 and holder != 1 and holder != me:
			return uid
	return 0


func _rested_all(uids: Array[int]) -> void:
	for uid in uids:
		await _until(func() -> bool: return Mano.rested(net, uid), 6.0)


func _pair_b() -> void:
	await _wait_local()
	await _ticks(60)
	var held := [0]
	await _until(func() -> bool: return _held_by_other() != 0, 30.0)
	held[0] = _held_by_other()
	_check(held[0] != 0, "al entrar tarde, ve un objeto sostenido por A")
	if held[0] != 0:
		var start := _place_of(held[0]).origin
		var newest := net.bodies.newest_sample(held[0])
		_check(not newest.is_empty() and (newest[4] as bool), "y las poses que llegan dicen que está sostenido")
		await _ticks(180)
		_check(_place_of(held[0]).origin.distance_to(start) > 0.02, "y lo ve moverse con la mano de A (%.2f m)" % _place_of(held[0]).origin.distance_to(start))
	var cross := _uid_near(CROSS_PLANK_AT, &"tabla_larga", 0.3)
	_check(cross != 0 and absf(_place_of(cross).basis.z.dot(Vector3.RIGHT)) > 0.999 and Mano.rested(net, cross),
			"la tabla cruzada, girada como su marcador y dormida")
	var throw_grenade := _uid_near(THROW_GRENADE_AT, &"granada", 0.3)
	_check(throw_grenade != 0 and Mano.rested(net, throw_grenade), "la granada de la pista, dormida en su lugar")
	if held[0] != 0:
		var uid: int = held[0]
		_check(await _until(func() -> bool: return net.replica.world.get(uid, {}).get("holder", -1) == 0, 90.0),
				"A se va con él en la mano: queda suelto")
		var up := _place_of(uid).origin.y
		await _until(func() -> bool: return Mano.rested(net, uid), 10.0)
		await _ticks(60)
		_check(_place_of(uid).origin.y <= up + 0.01, "y cae (o queda apoyado) donde lo deja el host")
		var newest := net.bodies.newest_sample(uid)
		_check(not newest.is_empty() and _place_of(uid).origin.distance_to((newest[1] as Transform3D).origin) < 0.01,
				"quieto, se ve en la última pose del host")
	_print_world()
	_finish()
