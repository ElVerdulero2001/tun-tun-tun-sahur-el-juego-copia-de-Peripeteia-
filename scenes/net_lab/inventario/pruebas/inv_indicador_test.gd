extends Node

## Prueba del indicador de lo que mirás (InteractIndicator, desde el
## 2026-11-06), dentro del laboratorio de verdad y con su cámara.
##
## Sin argumentos, un proceso jugando solo:
##
## - en primera y en tercera persona, con el mismo objeto marcado, el marco y
##   el nombre siguen al objeto al girar la cámara en horizontal y en vertical,
##   y el nombre va centrado debajo y horizontal;
## - un recogible con el cartel apagado en su InvPickupSpawn (show_label) se
##   ve sin cartel y se marca igual, con su nombre;
## - una caja que se mueve sigue marcada y el marco la acompaña; una zona
##   propia que marca solo una parte (como haría la manija de una puerta)
##   también, sin tocar el HUD;
## - con dos objetos cerca, lo marcado es lo que elegiría E en cada punto, y E
##   recoge lo marcado;
## - se oculta al mirar a otro lado, lejos, con una pared en el medio, al
##   recogerlo, si lo recoge otro jugador (simulado en el host) y con la
##   interfaz que no deja interactuar (un diálogo, una caja abierta).
##
##   --headless --fixed-fps 60 --scene res://scenes/net_lab/inventario/pruebas/inv_indicador_test.tscn
##
## Con --foco-pair=host o client, en dos procesos, con los argumentos de red
## del laboratorio (--host --bind=127.0.0.1 --port=N o --client
## --address=127.0.0.1 --port=N): el host marca el botiquín mientras el cliente
## marca la llave, cada uno el suyo; después el host recoge la llave y el
## cliente comprueba que su marco se va al llegarle el cambio. La llave tiene el
## cartel apagado, y los dos la ven sin cartel. Sin --fixed-fps.
##
## Con --foco-capturas=CARPETA, y con ventana (sin --headless), guarda una
## captura de la pantalla en cada paso de la primera parte. Con
## --foco-detalle escribe también cada comprobación que dio bien.

const Op := InvProtocol.Op
## Cuánto se gira la cámara en cada prueba de seguimiento, en radianes: lo
## justo para que la mira siga sobre el mismo objeto.
const TURN_FIRST := 0.04
const TURN_THIRD := 0.08
## Dónde se para, respecto de lo que mira: en primera persona, justo atrás; en
## tercera, atrás y al costado, para que el cuerpo no lo tape.
const NEAR_FIRST := Vector3(-1.1, 0, 0)
const NEAR_THIRD := Vector3(-1.45, 0, -0.65)

var role := ""
var shots_dir := ""
## --foco-detalle: también escribe cada comprobación que dio bien.
var verbose := false
var lab: Node3D
var net: InvNet
var ui: InvUI
var camera: LabCamera
var view_camera: Camera3D
var indicator: InteractIndicator
var actor: ActorBody
var _answers := {}
var _checks := 0
var _failures := 0
var _finishing := false
var _shots := 0
var _peer2_seq := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--foco-pair="):
			role = arg.trim_prefix("--foco-pair=")
		elif arg.begins_with("--foco-capturas="):
			shots_dir = arg.trim_prefix("--foco-capturas=")
		elif arg == "--foco-detalle":
			verbose = true
	get_tree().create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		_failures += 1
		_log("TIEMPO AGOTADO: el recorrido no terminó")
		_finish())
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	# Un recogible sin cartel (InvPickupSpawn.show_label): jugando solo, la
	# linterna; en pareja, la llave, en los dos (la huella del laboratorio no
	# deja entrar al cliente si su zona difiere en algo, también en esto).
	var no_label := {"": "Linterna", "host": "Llave", "client": "Llave"}
	if no_label.has(role):
		(lab.get_node("ZonaDeInventario/Objetos/" + no_label[role]) as InvPickupSpawn).show_label = false
	add_child(lab)
	net = lab.get_node("Inventario")
	ui = lab.get_node("Hud/InventarioUI")
	camera = lab.get_node("CameraRig")
	view_camera = camera.get_node("SpringArm/Camera")
	indicator = lab.get_node_or_null("Hud/Indicador") as InteractIndicator
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	if indicator == null:
		_check(false, "el laboratorio tiene el indicador en Hud/Indicador")
		_finish()
		return
	match role:
		"":
			_solo()
		"host":
			_pair_host()
		"client":
			_pair_client()
		_:
			_log("--foco-pair tiene que ser host o client")
			get_tree().quit(3)


# --- Ayudas ---------------------------------------------------------------------

func _log(text: String) -> void:
	print("[inv_indicador%s] %s" % [":" + role if role != "" else "", text])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		_log("FALLA: %s" % what)
	elif role != "" or verbose:
		_log("ok: %s" % what)


## Sale bien solo si el recorrido llegó al final, con alguna comprobación y sin fallas.
func _finish(completed := false) -> void:
	if _finishing:
		return
	_finishing = true
	if not completed:
		_failures += 1
		_log("FALLA: el recorrido no llegó al final")
	_log("%d comprobaciones, %d fallas" % [_checks, _failures])
	if role == "client":
		lab._session.say_goodbye()
	for i in 10:
		await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


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


func _req(op: int, args: Array, uids: Array = []) -> Array:
	var seq := net.replica.request(op, args, uids)
	if seq == 0:
		return [false, "no salió"]
	if not await _until(func() -> bool: return _answers.has(seq), 5.0):
		return [false, "sin respuesta"]
	return _answers[seq]


## Mueve al personaje propio de golpe (jugando solo o en el host, que es la autoridad).
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
	await _ticks(3)
	await _frames(2)


## Se para en `point + offset` (sobre el piso), mirando hacia `point`. En
## tercera persona conviene que lo mirado quede un poco al costado y no justo
## adelante de los pies: si no, el propio cuerpo lo tapa en la pantalla.
func _stand_by(point: Vector3, offset: Vector3) -> void:
	var feet := Vector3(point.x + offset.x, 0.0, point.z + offset.z)
	var toward := point - feet
	await _teleport(feet, atan2(-toward.x, -toward.z))


func _set_first_person(first: bool) -> void:
	camera._wanted_zoom = 0.0 if first else 1.0
	camera._zoom = camera._wanted_zoom
	await _frames(3)


## Gira la cámara para que el centro de la pantalla pase por ese punto. La
## primera vez apunta desde la cabeza, el centro alrededor del que orbita la
## cámara en tercera persona; después ajusta desde la cámara.
func _aim(point: Vector3) -> void:
	for i in 6:
		var from := camera.global_position if i == 0 else view_camera.global_position
		var direction := (point - from).normalized()
		camera.yaw = atan2(-direction.x, -direction.z)
		camera.pitch = asin(clampf(direction.y, -1.0, 1.0))
		await _frames(2)


func _world_uid(def_id: StringName, quantity := -1) -> int:
	var keys := net.replica.world.keys()
	keys.sort()
	for uid in keys:
		var stack: InvStack = net.replica.world[uid]["stack"]
		if stack.def_id == def_id and (quantity < 0 or stack.quantity == quantity) and not net.replica.is_taken(uid):
			return uid
	return 0


## El centro de la zona que marca ese objeto suelto, en el mundo.
func _center_of(uid: int) -> Vector3:
	var view := net.world_view(uid)
	return view.to_global(view.interact_focus().bounds.get_center()) if view != null else Vector3.ZERO


func _box_named(shown: String) -> InvContainer:
	for box in net.containers():
		if box.display_name == shown:
			return box
	return null


## Si el indicador marca ese objeto suelto y E elegiría ese mismo.
func _marks(uid: int) -> bool:
	var focus := indicator.marked_focus()
	var target := ui.interaction_target()
	return focus != null and focus.anchor == net.world_view(uid) and target.get("kind", "") == "item" \
			and target.get("id", 0) == uid and indicator.marked_frame().has_area()


func _marks_box(box: InvContainer) -> bool:
	var focus := indicator.marked_focus()
	var target := ui.interaction_target()
	return focus != null and focus.anchor == box and target.get("kind", "") == "box" \
			and target.get("id", 0) == box.container_id and indicator.marked_frame().has_area()


## El objeto suelto que se marca, o 0. Lo marcado en el cuadro anterior puede
## haberse borrado recién (recogido): entonces, 0.
func _marked_uid() -> int:
	var focus := indicator.marked_focus()
	if focus == null or not is_instance_valid(focus.anchor) or not focus.anchor is InvWorldItem:
		return 0
	return (focus.anchor as InvWorldItem).uid


func _describe() -> String:
	var focus := indicator.marked_focus()
	return "marca «%s» en %s; E elegiría %s" % [indicator.shown_name(), indicator.marked_frame(), ui.interaction_target()] \
			if focus != null else "no marca nada; E elegiría %s" % [ui.interaction_target()]


func _hidden() -> bool:
	return indicator.marked_focus() == null and not indicator.marked_frame().has_area() and indicator.shown_name() == ""


## El marco que corresponde a esa zona con la cámara como está ahora, calculado
## acá aparte: las ocho esquinas proyectadas, el margen y el tamaño mínimo.
func _expected_frame(focus: InteractFocus) -> Rect2:
	var place := focus.anchor.get_global_transform_interpolated()
	var points := PackedVector2Array()
	for i in 8:
		points.append(view_camera.unproject_position(place * focus.bounds.get_endpoint(i)))
	var low := points[0]
	var high := points[0]
	for point in points:
		low = low.min(point)
		high = high.max(point)
	var frame := Rect2(low, high - low).grow(indicator.margin)
	var missing := (Vector2.ONE * indicator.min_size - frame.size).max(Vector2.ZERO) / 2.0
	return frame.grow_individual(missing.x, missing.y, missing.x, missing.y)


## El centro de la zona, proyectado.
func _projected_center(focus: InteractFocus) -> Vector2:
	return view_camera.unproject_position(focus.anchor.get_global_transform_interpolated() * focus.bounds.get_center())


## Que lo dibujado corresponda a la cámara de este cuadro: el marco, el nombre
## centrado debajo y horizontal.
func _check_frame(what: String) -> void:
	var focus := indicator.marked_focus()
	if focus == null:
		_check(false, "%s: no hay marco" % what)
		return
	var frame := indicator.marked_frame()
	var expected := _expected_frame(focus)
	_check(frame.position.distance_to(expected.position) < 0.5 and frame.size.distance_to(expected.size) < 0.5,
			"%s: el marco es la zona proyectada con la cámara de este cuadro (%s, esperado %s)" % [what, frame, expected])
	_check(frame.has_point(_projected_center(focus)), "%s: el objeto queda adentro del marco" % what)
	var font := indicator.get_theme_default_font()
	var width := font.get_string_size(indicator.shown_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, indicator.font_size).x
	var at := indicator.name_position()
	var top := at.y - font.get_ascent(indicator.font_size)
	_check(absf(at.x + width / 2.0 - frame.get_center().x) < 1.0, "%s: el nombre va centrado debajo del marco (centro del nombre %.1f, del marco %.1f; pantalla %s)" % [
			what, at.x + width / 2.0, frame.get_center().x, indicator.size])
	_check(top >= frame.end.y and top - frame.end.y <= 12.0,
			"%s: el nombre empieza %.1f px debajo de las esquinas de abajo" % [what, top - frame.end.y])
	_check(is_zero_approx(indicator.get_global_transform_with_canvas().get_rotation()), "%s: el HUD no está girado: el texto va horizontal" % what)


func _press_e() -> void:
	var e_key := InputEventKey.new()
	e_key.physical_keycode = KEY_E
	e_key.pressed = true
	ui._unhandled_key_input(e_key)


## Con --foco-capturas y con ventana: una captura de lo que se ve.
func _shot(label: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	# Sin el panel de valores (como con F1), que tapa el medio de la pantalla.
	lab.get_node("Hud/Info").visible = false
	await RenderingServer.frame_post_draw
	_shots += 1
	var path := shots_dir.path_join("%02d_%s.png" % [_shots, label])
	get_viewport().get_texture().get_image().save_png(path)
	_log("captura %s" % path)


# --- Jugando solo ----------------------------------------------------------------

func _solo() -> void:
	await get_tree().process_frame
	lab._start(0)
	for i in 120:
		await get_tree().physics_frame
		if net.replica.own != null and is_instance_valid(lab._local_actor):
			break
	actor = lab._local_actor
	_check(actor != null and net.replica.has_state, "jugando solo, con el personaje y el inventario")
	if actor == null:
		_finish()
		return
	var hud := lab.get_node("Hud")
	_check(indicator.get_parent() == hud, "el indicador está en el HUD del jugador local")
	_check(indicator.mouse_filter == Control.MOUSE_FILTER_IGNORE and indicator.focus_mode == Control.FOCUS_NONE,
			"no toma el mouse ni el teclado")
	_check(indicator.get_index() < hud.get_node("Instrumentos").get_index() and indicator.get_index() < ui.get_index(),
			"se dibuja debajo de los instrumentos y del inventario")
	_check(_hidden(), "sin mirar nada no se dibuja nada")
	await _follows_camera(true)
	await _follows_camera(false)
	await _without_label()
	await _moving_box()
	await _moving_part()
	await _two_close()
	await _dropped_and_placed()
	await _hides()
	await _ui_states()
	await _other_player_takes()
	_finish(true)


## Un recogible con el cartel apagado en su InvPickupSpawn: aparece sin cartel,
## los demás lo siguen teniendo, y el indicador lo marca igual, con su nombre.
func _without_label() -> void:
	var uid := _world_uid(&"linterna")
	_check(uid != 0, "sin cartel: está la linterna en el piso")
	if uid == 0:
		return
	var view := net.world_view(uid)
	_check(net.replica.world[uid].get("label", true) == false, "sin cartel: el host lo cuenta así")
	_check(view != null and not view.has_label() and view.find_children("*", "Label3D", true, false).is_empty(),
			"sin cartel: la linterna se ve sin cartel")
	# Los demás, según la casilla de su marcador (en el nivel puede haber otros
	# apagados a mano): todavía no se movió nada, así que cada objeto está en su
	# marcador.
	var unlabeled_spots := lab.find_children("*", "InvPickupSpawn", true, false) \
			.filter(func(spawn: InvPickupSpawn) -> bool: return not spawn.show_label) \
			.map(func(spawn: InvPickupSpawn) -> Vector3: return spawn.global_position)
	var wrong := net.replica.world.keys().filter(func(id: int) -> bool:
		var shown := net.world_view(id)
		var spot: Vector3 = net.replica.world[id]["pos"]
		var off := unlabeled_spots.any(func(at: Vector3) -> bool: return at.distance_to(spot) < 0.05)
		return shown == null or shown.has_label() == off)
	_check(wrong.is_empty(), "cada objeto lleva o no su cartel según su marcador; %d sin cartel (no coinciden: %s)" % [
			unlabeled_spots.size(), wrong])
	await _stand_by(net.replica.world[uid]["pos"], NEAR_FIRST)
	await _set_first_person(true)
	await _aim(_center_of(uid))
	_check(_marks(uid) and indicator.shown_name() == "Linterna", "sin cartel, el indicador la marca con su nombre: %s" % _describe())
	_check_frame("sin cartel")
	await _shot("sin_cartel")
	camera.yaw += 1.2
	await _frames(3)
	_check(not _marks(uid) and view.find_children("*", "Label3D", true, false).is_empty(),
			"al dejar de marcarla, sigue sin cartel")


## Mismo objeto marcado, la cámara gira: el marco y el nombre lo siguen.
func _follows_camera(first_person: bool) -> void:
	var mode := "primera persona" if first_person else "tercera persona"
	var uid := _world_uid(&"granada", 3)
	_check(uid != 0, "%s: están las granadas ×3 en el piso" % mode)
	if uid == 0:
		return
	await _stand_by(net.replica.world[uid]["pos"], NEAR_FIRST if first_person else NEAR_THIRD)
	await _set_first_person(first_person)
	_check(camera.third_person() != first_person, "%s: la cámara está en %s" % [mode, mode])
	var view := net.world_view(uid)
	await _aim(_center_of(uid))
	_check(_marks(uid), "%s: mirando las granadas, las marca: %s" % [mode, _describe()])
	_check(indicator.shown_name() == "Granada inerte", "%s: solo el nombre visible, sin cantidad ni tecla: «%s»" % [
			mode, indicator.shown_name()])
	_check(view != null and not view._label.visible, "%s: el cartel de arriba se oculta: el nombre se ve una vez" % mode)
	_check_frame("%s, de frente" % mode)
	await _shot("marca_%s" % ("primera" if first_person else "tercera"))
	var base_yaw := camera.yaw
	var base_pitch := camera.pitch
	var base_frame := indicator.marked_frame()
	var base_center := _projected_center(indicator.marked_focus())
	var turn := TURN_FIRST if first_person else TURN_THIRD
	for step: Array in [[turn, 0.0, "girada a la izquierda"], [-turn, 0.0, "girada a la derecha"],
			[0.0, turn, "levantada"], [0.0, -turn, "bajada"]]:
		camera.yaw = base_yaw + step[0]
		camera.pitch = base_pitch + step[1]
		await _frames(2)
		var what := "%s, cámara %s" % [mode, step[2]]
		_check(_marks(uid), "%s: sigue marcando las mismas granadas: %s" % [what, _describe()])
		if indicator.marked_focus() == null:
			continue
		_check_frame(what)
		var shift := indicator.marked_frame().get_center() - base_frame.get_center()
		var object_shift := _projected_center(indicator.marked_focus()) - base_center
		_check(shift.distance_to(object_shift) < 2.0, "%s: el marco se corrió lo mismo que el objeto en pantalla (%s y %s)" % [
				what, shift, object_shift])
		var horizontal: bool = step[0] != 0.0
		var main := shift.x if horizontal else shift.y
		var cross := shift.y if horizontal else shift.x
		_check(absf(main) > 6.0 and absf(main) > 2.0 * absf(cross) and signf(main) == signf(step[0] + step[1]),
				"%s: el marco se movió %s, %.1f px" % [what, "en horizontal" if horizontal else "en vertical", main])
		if step[2] == "girada a la izquierda":
			await _shot("sigue_%s" % ("primera" if first_person else "tercera"))
	camera.yaw = base_yaw
	camera.pitch = base_pitch
	await _frames(2)


## Una caja que se mueve, con la cámara quieta: sigue marcada y el marco la acompaña.
func _moving_box() -> void:
	var box := _box_named("Cajón chico")
	_check(box != null, "está el cajón chico")
	if box == null:
		return
	await _stand_by(box.global_position, Vector3(-1.5, 0, -0.75))
	await _set_first_person(false)
	await _aim(box.center())
	_check(_marks_box(box) and indicator.shown_name() == "Cajón chico", "la caja se marca con su nombre: %s" % _describe())
	var cartel := box.get_node_or_null(^"Cartel") as Node3D
	_check(cartel != null and not cartel.visible, "y su cartel de arriba («E para abrir») se oculta mientras está marcada")
	var start := box.global_position
	var base_frame := indicator.marked_frame()
	var base_center := _projected_center(indicator.marked_focus()) if indicator.marked_focus() != null else Vector2.ZERO
	var followed := true
	for i in 6:
		await get_tree().physics_frame
		box.global_position = start + Vector3(0, 0, 0.035 * (i + 1))
		await _ticks(1)
		await _frames(2)
		if not _marks_box(box):
			followed = false
			_check(false, "la caja que se mueve deja de estar marcada en el paso %d: %s" % [i + 1, _describe()])
			break
		var expected := _expected_frame(indicator.marked_focus())
		if indicator.marked_frame().position.distance_to(expected.position) > 0.5:
			followed = false
	_check(followed, "en cada paso, el marco es el de la caja donde está ahora")
	if indicator.marked_focus() != null:
		var shift := indicator.marked_frame().get_center() - base_frame.get_center()
		var object_shift := _projected_center(indicator.marked_focus()) - base_center
		_check(shift.x > 8.0 and shift.distance_to(object_shift) < 2.0,
				"la caja se corrió 21 cm a la derecha y el marco con ella: %.1f px (la caja, %.1f px)" % [shift.x, object_shift.x])
	await _shot("caja_movida")
	box.global_position = start
	await _ticks(2)
	await _frames(2)


## Una zona propia que marca solo una parte (como la manija de una puerta),
## con otro `source`: el HUD no cambia. La puerta se mueve y gira.
func _moving_part() -> void:
	var door := Node3D.new()
	door.name = "PuertaDePrueba"
	door.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var leaf := MeshInstance3D.new()
	var leaf_mesh := BoxMesh.new()
	leaf_mesh.size = Vector3(0.9, 2.0, 0.05)
	leaf.mesh = leaf_mesh
	leaf.position = Vector3(0.45, 1.0, 0.0)
	door.add_child(leaf)
	var handle := MeshInstance3D.new()
	handle.name = "Manija"
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.14, 0.04, 0.06)
	handle.mesh = handle_mesh
	handle.position = Vector3(0.75, 1.0, 0.06)
	door.add_child(handle)
	add_child(door)
	await _teleport(Vector3(20, 0, 20), 0.0)
	await _set_first_person(true)
	door.global_position = actor.global_position + Vector3(-0.45, 0, -1.4)
	var focus := InteractFocus.new("Manija de prueba", handle, InteractFocus.mesh_bounds(handle))
	_check(focus.bounds.size.is_equal_approx(handle_mesh.size), "la zona es solo la manija: %s" % focus.bounds)
	indicator.source = func() -> InteractFocus: return focus
	await _aim(handle.global_position)
	_check(indicator.marked_focus() == focus and indicator.shown_name() == "Manija de prueba", "marca la parte con su nombre: %s" % _describe())
	_check_frame("la manija")
	var whole := InteractFocus.new("", door, InteractFocus.mesh_bounds(door))
	_check(indicator.marked_frame().size.x < _expected_frame(whole).size.x * 0.5, "el marco es de la manija, no de la puerta entera")
	var followed := true
	for i in 8:
		door.global_position += Vector3(0.03, 0.0, 0.0)
		door.rotation.y += 0.04
		await _frames(2)
		var expected := _expected_frame(focus)
		if indicator.marked_focus() != focus or indicator.marked_frame().position.distance_to(expected.position) > 0.5 \
				or indicator.marked_frame().size.distance_to(expected.size) > 0.5:
			followed = false
	_check(followed, "la puerta se corre y gira, y el marco acompaña a la manija en cada cuadro")
	_check_frame("la manija después de moverse")
	await _shot("manija")
	indicator.source = ui.interaction_focus
	door.queue_free()
	await _frames(2)
	_check(_hidden(), "sin la manija y lejos de todo, no marca nada")


## Dos objetos cerca: en cada punto, lo marcado es lo que elegiría E; y E recoge lo marcado.
func _two_close() -> void:
	var poison := _world_uid(&"veneno")
	var capsule := _world_uid(&"capsula_letal")
	_check(poison != 0 and capsule != 0, "están el veneno y la cápsula letal en el piso")
	if poison == 0 or capsule == 0:
		return
	var a: Vector3 = net.replica.world[poison]["pos"]
	var b: Vector3 = net.replica.world[capsule]["pos"]
	_check(a.distance_to(b) < 1.5, "están a %.2f m uno del otro" % a.distance_to(b))
	await _teleport((a + b) / 2.0 + Vector3(-1.0, 0, 0), -PI / 2.0)
	await _set_first_person(true)
	var agree := 0
	var marked := {}
	var steps := 11
	for i in steps:
		await _aim(_center_of(poison).lerp(_center_of(capsule), float(i) / float(steps - 1)))
		var chosen := ui._look_target()
		var by_e: int = chosen.get("id", 0) if chosen.get("kind", "") == "item" else 0
		if _marked_uid() == by_e:
			agree += 1
		if by_e != 0:
			marked[by_e] = true
	_check(agree == steps, "barriendo la mira de uno al otro, en %d de %d puntos lo marcado es lo que elegiría E" % [agree, steps])
	_check(marked.has(poison) and marked.has(capsule), "y según dónde apunta se marca uno u otro")
	await _aim(_center_of(capsule))
	_check(_marks(capsule) and indicator.shown_name() == "Cápsula letal", "apuntando a la cápsula, marca la cápsula: %s" % _describe())
	await _shot("dos_cerca")
	_press_e()
	_check(net.replica.is_taken(capsule) and not net.replica.is_taken(poison), "E recoge lo marcado (la cápsula), no el veneno de al lado")
	await _frames(1)
	_check(_hidden() or _marked_uid() != capsule, "recogida, ya no se marca")
	await _ticks(6)
	await _aim(_center_of(poison))
	_check(_marks(poison) and indicator.shown_name() == "Frasco de veneno", "apuntando al veneno, marca el veneno: %s" % _describe())
	_press_e()
	_check(net.replica.is_taken(poison), "y E recoge el veneno")
	await _ticks(6)


## Lo soltado desde el inventario y lo colocado en el mapa con InvPickupSpawn
## (fuera de la zona, en pickup_root, si el nivel tiene alguno) se marcan igual.
func _dropped_and_placed() -> void:
	await _teleport(Vector3(20, 0, 20), -PI / 2.0)
	var own := net.replica.own.sorted_uids().filter(func(id: int) -> bool: return net.replica.own.stacks[id].def_id == &"veneno")
	_check(not own.is_empty(), "el veneno está en el inventario")
	if own.is_empty():
		return
	var uid: int = own[0]
	var r := await _req(Op.DROP, [0, uid, net.replica.own.get_stack(uid).ver, 1], [uid])
	var dropped := _world_uid(&"veneno")
	_check(r[0] and dropped != 0, "un veneno soltado al piso: %s" % r[1])
	if dropped != 0:
		await _set_first_person(true)
		await _aim(_center_of(dropped))
		_check(_marks(dropped) and indicator.shown_name() == "Frasco de veneno", "lo soltado se marca: %s" % _describe())
		_check_frame("lo soltado")
		await _shot("soltado")
	var zone := lab.get_node("ZonaDeInventario")
	for spawn: InvPickupSpawn in lab.find_children("*", "InvPickupSpawn", true, false):
		if zone.is_ancestor_of(spawn) or spawn.item == null:
			continue
		var placed := 0
		for key in net.replica.world:
			if net.replica.world[key]["pos"].distance_to(spawn.global_position) < 0.05:
				placed = key
		_check(placed != 0, "el recogible colocado en el mapa (%s) está en el mundo" % lab.get_path_to(spawn))
		if placed == 0:
			break
		await _teleport(Vector3(spawn.global_position.x - 1.1, 0.0, spawn.global_position.z), -PI / 2.0)
		await _aim(_center_of(placed))
		_check(_marks(placed) and indicator.shown_name() == spawn.item.display_name,
				"el colocado en el mapa con InvPickupSpawn se marca: %s" % _describe())
		break


## Se oculta: mirando a otro lado, lejos, con una pared en el medio y al recogerlo.
func _hides() -> void:
	var uid := _world_uid(&"granada", 2)
	_check(uid != 0, "están las granadas ×2 en el piso")
	if uid == 0:
		return
	var spot: Vector3 = net.replica.world[uid]["pos"]
	var view := net.world_view(uid)
	await _stand_by(spot, NEAR_THIRD)
	await _set_first_person(false)
	await _aim(_center_of(uid))
	_check(_marks(uid), "tercera persona: marca las granadas ×2: %s" % _describe())
	await _shot("antes_de_ocultarse")
	# A otro lado y hacia arriba, donde no hay nada (girando a la izquierda, la
	# mira caería en las granadas ×3 de al lado, y se marcarían esas).
	camera.yaw -= 0.9
	camera.pitch = 0.3
	await _frames(2)
	_check(_hidden() and ui.interaction_target().is_empty(), "mirando a otro lado, se van el marco y el nombre juntos: %s" % _describe())
	_check(view._label.visible, "y vuelve a verse el cartel de arriba")
	await _stand_by(spot, Vector3(-3.4, 0, -0.65))
	await _aim(_center_of(uid))
	_check(_hidden() and ui._look_target().is_empty(), "fuera de alcance no se marca (y E tampoco lo elegiría): %s" % _describe())
	await _stand_by(spot, NEAR_THIRD)
	await _aim(_center_of(uid))
	_check(_marks(uid), "de nuevo cerca, se marca")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(0.1, 2.4, 1.4)
	shape.shape = slab
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = actor.global_position.lerp(spot, 0.5) + Vector3.UP * 1.2
	await _ticks(3)
	await _frames(2)
	_check(_hidden(), "con una pared en el medio, no se marca: %s" % _describe())
	wall.queue_free()
	await _ticks(3)
	await _frames(2)
	_check(_marks(uid), "sin la pared, vuelve")
	_press_e()
	await _frames(1)
	_check(_hidden(), "recogida con E, el marco y el nombre se van en el cuadro siguiente: %s" % _describe())
	await _ticks(6)
	_check(net.replica.own.has(uid) or not net.replica.world.has(uid), "y el host la dio por recogida")


## Con la interfaz: el inventario abierto (Tab) sin caja deja interactuar; un
## diálogo o una caja abierta, no.
func _ui_states() -> void:
	var uid := _world_uid(&"granada", 3)
	await _teleport(net.replica.world[uid]["pos"] + Vector3(-1.1, 0, 0), -PI / 2.0)
	await _set_first_person(true)
	await _aim(_center_of(uid))
	_check(_marks(uid), "marca las granadas ×3")
	ui.open()
	await _frames(2)
	_check(ui.is_open and _marks(uid), "con el inventario abierto con Tab y sin caja, E recoge: el marco queda")
	ui._dialog.show()
	await _frames(2)
	_check(_hidden(), "con un diálogo abierto, E no hace nada: no se marca")
	ui._dialog.hide()
	await _frames(2)
	_check(_marks(uid), "cerrado el diálogo, vuelve")
	ui.close()
	var box := _box_named("Cajón chico")
	await _teleport(box.global_position + Vector3(-1.3, 0, 0), -PI / 2.0)
	await _aim(box.center())
	_check(_marks_box(box), "marca el cajón chico")
	ui.open()
	var r := await _req(Op.OPEN, [box.container_id])
	await _frames(2)
	_check(r[0] and net.replica.box_id == box.container_id, "el cajón abierto: %s" % r[1])
	_check(_hidden(), "con la caja abierta, E la cierra: no se marca nada")
	_press_e()
	await _frames(2)
	_check(not ui.is_open and _marks_box(box), "E la cierra y vuelve a marcarse")


## Otro jugador (simulado en el host) recoge lo que se marca: al cambiar el
## estado de esta máquina, el marco se va.
func _other_player_takes() -> void:
	var uid := _world_uid(&"tornillos", 20)
	_check(uid != 0, "están los tornillos ×20 en el piso")
	if uid == 0:
		return
	var spot: Vector3 = net.replica.world[uid]["pos"]
	await _teleport(spot + Vector3(-1.1, 0, 0), -PI / 2.0)
	await _aim(_center_of(uid))
	_check(_marks(uid), "marca los tornillos: %s" % _describe())
	var other: ActorBody = load("res://scenes/actor/actor.tscn").instantiate()
	other.name = "Actor2"
	other.owner_peer_id = 2
	other.state.position = spot + Vector3(0.8, 0, 0.3)
	other.state.mode = ActorState.Mode.GROUND
	other.state.on_floor = true
	other.position = other.state.position
	lab.get_node("Actors").add_child(other)
	await _ticks(3)
	net.test_peers[2] = true
	net.authority.welcome(2)
	await _ticks(2)
	_check(_marks(uid), "con el otro jugador al lado, sigue marcado")
	_peer2_seq += 1
	net._inbox.append([2, _peer2_seq, Op.PICKUP, [uid]])
	var marked_until_gone := true
	var ticks := 0
	while net.replica.world.has(uid) and ticks < 30:
		if not _marks(uid):
			marked_until_gone = false
		await get_tree().physics_frame
		ticks += 1
	_check(not net.replica.world.has(uid), "el otro jugador se los llevó (en %d ticks)" % ticks)
	_check(marked_until_gone, "hasta que llegó el cambio, estuvieron marcados")
	_check(_hidden(), "con el estado local ya cambiado, el marco y el nombre no están: %s" % _describe())
	var other_inventory := net.authority.player_inventory(2)
	_check(other_inventory != null and other_inventory.grid.has(uid), "los tiene el otro jugador")
	net.test_peers.erase(2)
	other.queue_free()
	await _ticks(3)


# --- En pareja (dos procesos) -------------------------------------------------------

func _pair_host() -> void:
	_check(await _until(func() -> bool: return net.authority != null and lab._local_actor != null and net.replica.own != null, 15.0),
			"el host arranca con su personaje")
	actor = lab._local_actor
	if actor == null:
		_finish()
		return
	var found := {}
	_check(await _until(func() -> bool:
		for peer in net.authority.welcomed_peers():
			if peer != multiplayer.get_unique_id():
				found["peer"] = peer
		return found.has("peer"), 30.0), "entró el cliente")
	var kit := _world_uid(&"botiquin")
	var key := _world_uid(&"llave")
	var key_spot: Vector3 = net.replica.world[key]["pos"]
	_check(net.world_view(key) != null and not net.world_view(key).has_label() and net.world_view(kit).has_label(),
			"en el host, la llave (cartel apagado) va sin cartel y el botiquín con cartel")
	await _stand_by(net.replica.world[kit]["pos"], NEAR_THIRD)
	await _set_first_person(false)
	await _aim(_center_of(kit))
	_check(_marks(kit) and indicator.shown_name() == "Botiquín", "el host, en tercera persona, marca el botiquín: %s" % _describe())
	var client_actor: ActorBody = null
	for node in lab.get_node("Actors").get_children():
		if node is ActorBody and node.owner_peer_id == found.get("peer", -1):
			client_actor = node
	_check(await _until(func() -> bool:
		if not is_instance_valid(client_actor):
			return false
		var flat := client_actor.global_position - key_spot
		flat.y = 0.0
		return flat.length() < 1.5 and client_actor.state.velocity.length() < 0.2, 40.0), "el cliente llegó a la llave y se quedó quieto")
	# El cliente apunta y marca la llave; mientras tanto, el host sigue con el botiquín.
	var steady := true
	for i in 180:
		await get_tree().process_frame
		if not _marks(kit):
			steady = false
	_check(steady, "mientras el cliente marca la llave, el host sigue marcando el botiquín: cada uno el suyo")
	_log("FOCO host %d «%s»" % [kit, indicator.shown_name()])
	await _teleport(key_spot + Vector3(1.0, 0, -0.9), PI / 2.0)
	var r := await _req(Op.PICKUP, [key], [key])
	_check(r[0], "el host recoge la llave que marca el cliente: %s" % r[1])
	_check(await _until(func() -> bool: return multiplayer.get_peers().is_empty(), 30.0), "el cliente terminó y se fue")
	_finish(true)


func _pair_client() -> void:
	_check(await _until(func() -> bool: return net.replica.has_state and lab._local_actor != null and net.replica.own != null, 20.0),
			"el cliente recibe el estado del host")
	actor = lab._local_actor
	if actor == null:
		_finish()
		return
	var key := _world_uid(&"llave")
	_check(key != 0, "el cliente ve la llave en el piso")
	var kit := _world_uid(&"botiquin")
	_check(net.replica.world[key].get("label", true) == false and net.world_view(key) != null
			and not net.world_view(key).has_label() and net.world_view(kit) != null and net.world_view(kit).has_label(),
			"en el cliente, la llave va sin cartel, como lo manda el host, y el botiquín con cartel")
	_check(await _walk_to(net.replica.world[key]["pos"] + Vector3(-1.0, 0, 0)), "el cliente camina hasta la llave")
	await _set_first_person(true)
	await _aim(_center_of(key))
	_check(_marks(key) and indicator.shown_name() == "Llave", "el cliente, en primera persona, marca la llave: %s" % _describe())
	_log("FOCO cliente %d «%s»" % [key, indicator.shown_name()])
	var lost := {"early": 0}
	var gone := await _until(func() -> bool:
		if not net.replica.world.has(key):
			return true
		if not _marks(key):
			lost["early"] += 1
		return false, 40.0)
	_check(gone, "el host recogió la llave y al cliente le llegó el cambio")
	await _frames(2)
	_check(_hidden(), "con el estado local ya cambiado, el marco y el nombre se van: %s" % _describe())
	_check(lost["early"] == 0, "hasta entonces la marcó sin cortes (%d ticks sin marcar)" % lost["early"])
	_finish(true)


## Camina hasta ahí con W, girando la cámara hacia el lugar, como un jugador.
func _walk_to(target: Vector3, tolerance := 0.35) -> bool:
	var limit := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < limit:
		var me := lab._local_actor as ActorBody
		if me != null:
			var flat := Vector3(target.x - me.global_position.x, 0.0, target.z - me.global_position.z)
			if flat.length() < tolerance:
				Input.action_release("move_forward")
				Input.action_release("run")
				await _ticks(20)
				return true
			camera.yaw = atan2(-flat.x, -flat.z)
			Input.action_press("move_forward")
			if flat.length() > 3.0:
				Input.action_press("run")
			else:
				Input.action_release("run")
		await get_tree().physics_frame
	Input.action_release("move_forward")
	Input.action_release("run")
	return false
