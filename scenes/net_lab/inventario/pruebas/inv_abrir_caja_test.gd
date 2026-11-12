extends Node

## Prueba de abrir una caja con E (2026-11-08, pedido del usuario: al abrir una
## caja se veía un instante el panel de integridad corporal, hasta que
## contestaba el host). Con dos procesos, como inv_partes_test: arranca
## net_lab.tscn con los argumentos de siempre (--host, --client, --sim-…) y
## además --inv-caja=host o client.
##
## Los dos jugadores hacen el mismo recorrido, cada uno con su caja (el host el
## cajón chico, el cliente la caja compartida; las dos empiezan vacías): el
## host sin red y el cliente con la internet que se le simule. Desde que se
## aprieta E hasta que se ve la grilla de la caja, en cada cuadro, mira que el
## lado derecho esté reservado para la caja y que el HUD no dibuje la
## integridad; al llegar, que la grilla ocupe justo el lugar reservado. Lo hace
## con la caja vacía, con un objeto adentro y con el inventario ya abierto con
## Tab. Con la caja abierta, Tab cierra solo la caja (desde el 2026-11-08 a la
## tarde, pedido del usuario): el inventario sigue abierto con la integridad,
## con un objeto de la caja en la mano (vuelve a su lugar) y con uno propio
## (sigue en la mano). Después lejos de la caja (el host dice que no y todo
## vuelve a como estaba antes de E), Tab mientras espera, y Tab mientras espera
## seguido de otra E con la respuesta de la primera en viaje (desde la
## auditoría del 2026-11-08, CAJ-01). Antes y al final, Tab solo: la
## integridad sigue a la derecha. Tab va por el camino de la tecla.

const Op := InvProtocol.Op
## Recoger y abrir llevan la dirección de la mano (desde el 2026-11-11 a la noche).
const Mano := preload("res://scenes/net_lab/inventario/pruebas/inv_mano_de_prueba.gd")

var role := ""
var lab: Node3D
var net: InvNet
var ui: InvUI
var hud: LabHud
## número del pedido -> [ok, motivo, cuántas veces se había dibujado la
## integridad al llegar la respuesta]
var _answers := {}
var _checks := 0
var _failures := 0
var _finishing := false


func _ready() -> void:
	var limit := 150.0
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--inv-caja="):
			role = arg.trim_prefix("--inv-caja=")
		elif arg.begins_with("--inv-timeout="):
			limit = arg.trim_prefix("--inv-timeout=").to_float()
	get_tree().create_timer(limit, true, false, true).timeout.connect(func() -> void:
		_failures += 1
		_log("TIEMPO AGOTADO: el recorrido no terminó")
		_finish())
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	add_child(lab)
	net = lab.get_node("Inventario")
	ui = lab.get_node("Hud/InventarioUI")
	hud = lab.get_node("Hud/Instrumentos")
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void:
		_answers[seq] = [ok, reason, hud.integrity_draws])
	match role:
		"host":
			_host()
		"client":
			_client()
		_:
			_log("falta --inv-caja")
			get_tree().quit(3)


func _log(text: String) -> void:
	print("[inv_caja:%s] %s" % [role, text])


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
	if role != "host":
		lab._session.say_goodbye()
	for i in 10:
		await get_tree().process_frame
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
	return false


func _answer_of(seq: int) -> bool:
	return await _until(func() -> bool: return _answers.has(seq), 5.0)


func _actor() -> ActorBody:
	return lab._local_actor


## Camina hasta ahí con W, girando la cámara hacia el lugar, como un jugador.
func _walk_to(target: Vector3, tolerance := 0.35) -> bool:
	var limit := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < limit:
		var actor := _actor()
		if actor != null:
			var flat := Vector3(target.x - actor.global_position.x, 0.0, target.z - actor.global_position.z)
			if flat.length() < tolerance:
				Input.action_release("move_forward")
				Input.action_release("run")
				await _ticks(20)
				return true
			lab._camera.yaw = atan2(-flat.x, -flat.z)
			Input.action_press("move_forward")
			if flat.length() > 3.0:
				Input.action_press("run")
			else:
				Input.action_release("run")
		await get_tree().physics_frame
	Input.action_release("move_forward")
	Input.action_release("run")
	return false


## Gira la cámara para que su centro pase por ese punto.
func _aim(point: Vector3) -> void:
	for i in 6:
		var from: Vector3 = lab._camera.aim_ray()[0]
		var direction := (point - from).normalized()
		lab._camera.yaw = atan2(-direction.x, -direction.z)
		lab._camera.pitch = asin(clampf(direction.y, -1.0, 1.0))
		await _frames(2)


## Si E, ahora, abriría esa caja.
func _aims_at(id: int) -> bool:
	var target := ui.interaction_target()
	return target.get("kind", "") == "box" and target.get("id", 0) == id


func _press_e() -> void:
	var e_key := InputEventKey.new()
	e_key.physical_keycode = KEY_E
	e_key.pressed = true
	ui._unhandled_key_input(e_key)


# --- Host ---------------------------------------------------------------------------------

func _remote_actor() -> ActorBody:
	for node in lab._actors.get_children():
		if node is ActorBody and node.owner_peer_id != multiplayer.get_unique_id() and not node.is_queued_for_deletion():
			return node
	return null


func _client_ready() -> bool:
	var client := _remote_actor()
	return client != null and net.authority.is_welcomed(client.owner_peer_id)


func _host() -> void:
	_check(await _until(_client_ready, 30.0), "el cliente entra")
	await _ticks(30)
	await _route(net.container(2))
	# El host sigue hasta que el cliente termina y se va.
	while _remote_actor() != null:
		await get_tree().physics_frame
	_finish(true)


# --- Cliente --------------------------------------------------------------------------------

func _client() -> void:
	_check(await _until(func() -> bool: return net.replica.has_state and _actor() != null and net.replica.own != null, 20.0),
			"recibe el estado inicial del host")
	await _route(net.container(1))
	_log("correcciones %d, coincidencias %d" % [lab._prediction.corrections, lab._prediction.matches])
	_finish(true)


# --- El recorrido -----------------------------------------------------------------------------

func _route(box: InvContainer) -> void:
	_check(box != null and net.replica.box_id == 0, "está la caja y no hay ninguna abierta")
	if box == null:
		return
	var id := box.container_id
	_check(net.authority == null or net.authority.containers[id].inventory.grid.sorted_uids().is_empty(),
			"%s empieza vacía" % box.display_name)
	var item := await _pick_up_near(box)
	_check(await _walk_to(box.global_position + Vector3(-1.3, 0, 0)), "camina hasta %s" % box.display_name)
	await _aim(box.center())
	_check(_aims_at(id), "mira %s: E la abriría" % box.display_name)
	await _tab_shows_integrity("antes de abrir la caja")
	# 1. La caja vacía, con el inventario cerrado.
	await _open_with_e(box, "vacía, con el inventario cerrado")
	_check(net.replica.box != null and net.replica.box.sorted_uids().is_empty(), "la caja abierta está vacía")
	# 2. Con un objeto adentro.
	if item != 0:
		await _put_in_box(item, id)
	_press_e()
	_check(not ui.is_open and net.replica.box_id == 0, "E la cierra junto con el inventario")
	await _ticks(10)
	await _open_with_e(box, "con un objeto adentro, con el inventario cerrado")
	_check(item != 0 and net.replica.box != null and net.replica.box.has(item) and ui._shown(id, item),
			"y se ve el objeto en la caja")
	# 3. Tab con la caja abierta y su objeto en la mano: cierra solo la caja.
	if item != 0:
		_click(ui._item_rect(id, item).get_center())
		_check(ui._mode == InvUI.Mode.HOLD and ui._hold.get("src", -1) == id, "agarra el objeto de la caja")
	await _tab_closes_box(box, "con el objeto de la caja en la mano")
	_check(ui._mode == InvUI.Mode.NONE, "el objeto de la caja vuelve a su lugar: la mano queda vacía")
	_press_tab()
	await _frames(2)
	_check(not ui.is_open, "sin caja, Tab cierra el inventario")
	await _ticks(10)
	# 4. Con el inventario ya abierto con Tab.
	_press_tab()
	await _frames(3)
	_check(ui.is_open and hud.integrity_panel_rect().has_area(), "con Tab, la integridad a la derecha")
	await _open_with_e(box, "con el inventario abierto con Tab")
	_check(item != 0 and net.replica.box != null and net.replica.box.has(item), "el objeto sigue en la caja")
	# 5. Tab con un objeto propio en la mano: la caja se cierra y sigue en la mano.
	if item != 0:
		await _take_from_box(item, id)
		_click(ui._item_rect(InvProtocol.OWN, item).get_center())
		_check(ui._mode == InvUI.Mode.HOLD and ui._hold.get("src", -1) == InvProtocol.OWN, "agarra el objeto propio")
	await _tab_closes_box(box, "con un objeto propio en la mano")
	_check(ui._mode == InvUI.Mode.HOLD and ui._hold.get("uid", 0) == item,
			"el objeto propio sigue en la mano, para soltarlo, por ejemplo, sobre el cuerpo")
	_check(ui._escape() and ui._mode == InvUI.Mode.NONE and ui.is_open, "Esc lo devuelve a su lugar")
	_press_tab()
	await _frames(2)
	_check(not ui.is_open, "y Tab cierra el inventario")
	await _ticks(10)
	# 6. Lejos: el host dice que no.
	_check(await _walk_to(box.global_position + Vector3(-3.6, 0, 0)), "se aleja de la caja")
	await _refused(box, false)
	_press_tab()
	await _frames(3)
	await _refused(box, true)
	_press_tab()
	await _frames(2)
	# 7. Tab mientras espera la caja.
	_check(await _walk_to(box.global_position + Vector3(-1.3, 0, 0)), "vuelve a la caja")
	await _tab_while_waiting(box)
	# 8. Tab mientras espera y enseguida E otra vez (CAJ-01).
	await _tab_then_e(box)
	await _tab_shows_integrity("al final")


## Tab de verdad, por el mismo camino que la tecla (InvUI._input).
func _press_tab() -> void:
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	ui._input(tab)


func _click(at: Vector2) -> void:
	ui._layout()
	ui._mouse = at
	ui._left_press()


## Con la caja abierta, Tab cierra solo la caja: el inventario sigue abierto y a
## la derecha se dibuja la integridad. El host la da por cerrada.
func _tab_closes_box(box: InvContainer, what: String) -> void:
	var draws := hud.integrity_draws
	_check(ui.is_open and net.replica.box_id == box.container_id, "%s: la caja está abierta" % what)
	_press_tab()
	await _frames(3)
	_check(ui.is_open and net.replica.box_id == 0 and not ui.has_box(), "%s: Tab cierra la caja y el inventario sigue abierto" % what)
	_check(hud.integrity_panel_rect().has_area() and hud.integrity_draws > draws and not ui._grid_rect(box.container_id).has_area(),
			"%s: a la derecha se dibuja la integridad, en el lugar de la caja" % what)
	await _ticks(10)
	if net.authority != null:
		_check(net.authority.open_container_of(multiplayer.get_unique_id()) == 0, "%s: el host la da por cerrada" % what)


## Tab abre el inventario normal: la integridad se dibuja a la derecha de la
## grilla propia. Tab otra vez lo cierra.
func _tab_shows_integrity(what: String) -> void:
	var draws := hud.integrity_draws
	_press_tab()
	await _frames(3)
	var panel := hud.integrity_panel_rect()
	var own := ui._panel_rect(InvProtocol.OWN)
	_check(ui.is_open and not ui.is_waiting_box() and panel.has_area() and panel.position.x > own.end.x
			and hud.integrity_draws > draws, "%s: con Tab, la integridad se dibuja a la derecha de la grilla (%s, %d veces)" % [
			what, panel, hud.integrity_draws - draws])
	_press_tab()
	await _frames(2)
	_check(not ui.is_open, "%s: Tab otra vez lo cierra" % what)


## E mirando la caja, cuadro por cuadro hasta que se ve su grilla.
func _open_with_e(box: InvContainer, what: String) -> void:
	var id := box.container_id
	await _aim(box.center())
	_check(_aims_at(id), "%s: E apunta a la caja" % what)
	ui._layout()
	var cs := ui._cs
	var draws := hud.integrity_draws
	var start := Time.get_ticks_msec()
	_press_e()
	ui._layout()
	var reserved := ui._reserved_panel_rect()
	_check(ui.is_open and ui.is_waiting_box() and reserved.has_area() and not hud.integrity_panel_rect().has_area()
			and ui.hud_limits()["panels_right"] >= reserved.end.x,
			"%s: E abre el inventario directo en modo caja, con el lado derecho reservado (%s)" % [what, reserved])
	var frames := 0
	var kept := true
	while net.replica.box_id != id and Time.get_ticks_msec() - start < 5000:
		await get_tree().process_frame
		frames += 1
		if net.replica.box_id != id and (not ui.is_open or not ui.is_waiting_box() or ui._reserved_panel_rect() != reserved
				or ui.side_panel_rect().has_area()):
			kept = false
	var msec := Time.get_ticks_msec() - start
	_check(net.replica.box_id == id and not ui.is_waiting_box(), "%s: la caja se abre a los %d ms (%d cuadros esperando)" % [
			what, msec, frames])
	_check(kept, "%s: en cada cuadro de la espera, el lado derecho siguió reservado para la caja" % what)
	await _frames(2)
	_check(hud.integrity_draws == draws, "%s: el HUD no dibujó la integridad ni un cuadro (%d)" % [what, hud.integrity_draws - draws])
	_check(ui._panel_rect(id) == reserved and is_equal_approx(ui._cs, cs),
			"%s: la grilla ocupa justo el lugar reservado y las celdas no cambian de tamaño" % what)
	_log("%s: la caja tardó %d ms, %d cuadros" % [what, msec, frames])


## Lejos de la caja, el host dice que no: vuelve a como estaba antes.
func _refused(box: InvContainer, was_open: bool) -> void:
	var what := "lejos, con el inventario %s" % ("abierto con Tab" if was_open else "cerrado")
	_check(ui.is_open == was_open, "%s: así empieza" % what)
	var draws := hud.integrity_draws
	var seq := ui.open_box(box.container_id, box.display_name, Mano.toward_box(net, lab._local_actor, box))
	ui._layout()
	_check(seq != 0 and ui.is_open and ui.is_waiting_box() and ui._reserved_panel_rect().has_area()
			and not hud.integrity_panel_rect().has_area(), "%s: se pide la caja y el lado derecho queda reservado" % what)
	_check(await _answer_of(seq) and not _answers[seq][0] and _answers[seq][1] == "estás muy lejos de la caja",
			"%s: el host dice que no: %s" % [what, _answers.get(seq, [])])
	_check(_answers.get(seq, [0, 0, -1])[2] == draws, "%s: mientras esperaba, no se dibujó la integridad" % what)
	await _frames(3)
	_check(not ui.is_waiting_box() and net.replica.box_id == 0 and ui.is_open == was_open,
			"%s: vuelve a como estaba antes de E (inventario %s)" % [what, "abierto" if ui.is_open else "cerrado"])
	_check(ui.last_message() == "Estás muy lejos de la caja", "%s: y dice por qué: %s" % [what, ui.last_message()])
	if was_open:
		_check(hud.integrity_panel_rect().has_area() and hud.integrity_draws > _answers[seq][2],
				"%s: la integridad vuelve a la derecha" % what)
	else:
		_check(not hud.integrity_panel_rect().has_area() and hud.integrity_draws == draws,
				"%s: se cierra sin haber dibujado la integridad" % what)


## E y enseguida Tab, antes de que conteste el host: deja la caja pedida y el
## inventario sigue abierto, con la integridad. Aunque el host la abra, no
## aparece. Tab otra vez cierra el inventario.
func _tab_while_waiting(box: InvContainer) -> void:
	var id := box.container_id
	await _aim(box.center())
	_check(_aims_at(id), "Tab durante la espera: E apunta a la caja")
	_press_e()
	var seq: int = ui._box_wait.get("seq", 0)
	_check(seq != 0 and ui.is_waiting_box(), "Tab durante la espera: la caja está pedida")
	_press_tab()
	await _frames(2)
	_check(ui.is_open and not ui.is_waiting_box() and not ui.has_box() and hud.integrity_panel_rect().has_area(),
			"Tab antes de que conteste el host: deja la caja, y el inventario sigue abierto con la integridad")
	_check(await _answer_of(seq) and _answers[seq][0], "el host la abrió igual: %s" % [_answers.get(seq, [])])
	await _frames(3)
	_check(net.replica.box_id == 0 and ui.is_open and hud.integrity_panel_rect().has_area(),
			"pero no aparece: sigue la integridad a la derecha")
	if net.authority != null:
		await _ticks(10)
		_check(net.authority.open_container_of(multiplayer.get_unique_id()) == 0, "y el host la da por cerrada")
	_press_tab()
	await _frames(2)
	_check(not ui.is_open, "Tab otra vez cierra el inventario")
	await _ticks(10)


## E, Tab antes de que conteste el host y otra vez E, en el mismo cuadro: la
## respuesta de la primera sigue en viaje (desde la auditoría del 2026-11-08,
## CAJ-01). Después de Tab se ve la integridad, E ya no cierra el inventario y
## el indicador vuelve a marcar la caja (hasta ese día, E cerraba el
## inventario y el indicador no marcaba nada hasta que llegaba la respuesta).
## La segunda E la vuelve a pedir y se abre esa, en modo caja; el host la
## tiene abierta. Tab la cierra.
func _tab_then_e(box: InvContainer) -> void:
	var id := box.container_id
	await _aim(box.center())
	_check(_aims_at(id), "Tab y E: E apunta a la caja")
	_press_e()
	var first: int = ui._box_wait.get("seq", 0)
	_check(first != 0 and ui.is_waiting_box(), "Tab y E: la caja está pedida")
	_press_tab()
	ui._layout()
	_check(ui.is_open and not ui.has_box() and not ui._e_closes_box() and ui.can_interact() and _aims_at(id)
			and ui.side_panel_rect().has_area(),
			"después de Tab, con la respuesta en viaje: E no cierra el inventario, el indicador marca la caja y a la derecha va la integridad")
	_press_e()
	var second: int = ui._box_wait.get("seq", 0)
	_check(second != 0 and second != first and ui.is_waiting_box() and ui._reserved_panel_rect().has_area(),
			"E otra vez la vuelve a pedir, sin esperar la respuesta de la primera, con el lado derecho reservado")
	_check(await _answer_of(first) and await _answer_of(second) and _answers[second][0],
			"el host contesta las dos: %s y %s" % [_answers.get(first, []), _answers.get(second, [])])
	await _frames(3)
	_check(net.replica.box_id == id and not ui.is_waiting_box() and ui.is_open and not hud.integrity_panel_rect().has_area(),
			"se abre la de la segunda E, en modo caja")
	if net.authority != null:
		await _ticks(10)
		_check(net.authority.open_container_of(multiplayer.get_unique_id()) == id, "y el host la tiene abierta")
	await _tab_closes_box(box, "abierta con la segunda E")
	_press_tab()
	await _frames(2)
	_check(not ui.is_open, "Tab otra vez cierra el inventario")
	await _ticks(10)


## Pasa el objeto de la caja a la grilla propia, con un pedido.
func _take_from_box(uid: int, id: int) -> void:
	var stack := net.replica.box.get_stack(uid) if net.replica.box != null else null
	var def := net.replica.box.def_of(uid) if stack != null else null
	var spot := net.replica.own.free_spot(def) if def != null else []
	var seq := 0
	if not spot.is_empty():
		seq = net.replica.request(Op.MOVE, [id, uid, stack.ver, InvProtocol.OWN, spot[0].x, spot[0].y, spot[1]], [uid])
	_check(seq != 0 and await _answer_of(seq) and _answers[seq][0] and net.replica.own.has(uid),
			"pasa el objeto de la caja a su grilla: %s" % [_answers.get(seq, [])])


## Recoge un objeto suelto cercano que entre en la caja, para meterlo después.
func _pick_up_near(box: InvContainer) -> int:
	var empty := InvGrid.new(box.columns, box.rows, net.catalog)
	var options := []
	for uid in net.replica.world:
		var def := net.catalog.find(net.replica.world[uid]["stack"].def_id)
		if def != null and not empty.free_spot(def).is_empty():
			options.append([(net.replica.world[uid]["pos"] as Vector3).distance_to(box.global_position), uid])
	options.sort_custom(_closer)
	for option in options:
		var uid: int = option[1]
		if not net.replica.world.has(uid) or net.replica.is_taken(uid):
			continue
		var def_id: StringName = net.replica.world[uid]["stack"].def_id
		if not await _walk_to(net.replica.world[uid]["pos"] + Vector3(-1.0, 0, 0)) or not net.replica.world.has(uid):
			continue
		var seq := ui.pick_up_world(uid, String(def_id), Mano.toward_item(net, lab._local_actor, uid))
		if seq != 0 and await _answer_of(seq) and _answers[seq][0]:
			for own_uid in net.replica.own.sorted_uids():
				if net.replica.own.stacks[own_uid].def_id == def_id:
					_check(true, "recoge %s para meterlo en la caja" % def_id)
					return own_uid
	_check(false, "recoge algo para meter en la caja")
	return 0


static func _closer(a: Array, b: Array) -> bool:
	return a[0] < b[0]


func _put_in_box(uid: int, id: int) -> void:
	var stack := net.replica.own.get_stack(uid)
	var def := net.replica.own.def_of(uid)
	var spot := net.replica.box.free_spot(def) if net.replica.box != null and def != null else []
	var seq := 0
	if stack != null and not spot.is_empty():
		seq = net.replica.request(Op.MOVE, [InvProtocol.OWN, uid, stack.ver, id, spot[0].x, spot[0].y, spot[1]], [uid])
	_check(seq != 0 and await _answer_of(seq) and _answers[seq][0] and net.replica.box != null and net.replica.box.has(uid),
			"mete %s en la caja: %s" % [def.display_name if def != null else "?", _answers.get(seq, [])])
