extends Node

## Prueba del botiquín sobre las partes del cuerpo y de las vendas (2026-11-06),
## con dos procesos: arranca net_lab.tscn con los argumentos de siempre
## (--host, --client, --sim-…) y además --inv-partes=host o client.
##
## - host: cuando entra el cliente, le lastima las dos piernas (60,5 % cada
##   una, como la tabla amarilla de la torre), como un evento del host. Después
##   imprime la salud, la integridad y los botiquines y vendas del cliente cada
##   vez que cambian ("CLIENTE …"), para compararlos con lo que imprime el
##   cliente al final ("FINAL …"). Termina cuando el cliente se va.
## - client (con internet mala simulada): camina a la zona de inventario,
##   recoge los botiquines, las vendas y los venenos, y con Tab hace lo que
##   haría el jugador con el mouse: agarra el botiquín y lo suelta donde no
##   sirve (una parte sana, entre las piernas) y sobre la pierna izquierda; las
##   vendas sobre la derecha; el veneno, que no cura partes; y el botiquín otra
##   vez, enseguida, sobre la derecha. Desde el 2026-11-06 a la noche cada uno
##   es un uso en el input: mide que el panel lo muestre sin esperar al host.
##   Al final, el uso normal del veneno y del botiquín.
##
## Las vendas curan 25 de una parte en esta prueba, en memoria en las dos
## máquinas, sin tocar su archivo: así no depende de lo que tengan puesto.

const Op := InvProtocol.Op
const H := ActorState.HEALTH_UNIT
const FULL := ActorState.INTEGRITY_FULL
const HURT := 6050

var role := ""
var lab: Node3D
var net: InvNet
var ui: InvUI
var hud: LabHud
var _answers := {}
var _checks := 0
var _failures := 0
var _finishing := false


func _ready() -> void:
	var limit := 120.0
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--inv-partes="):
			role = arg.trim_prefix("--inv-partes=")
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
	(net.catalog.find(&"vendas").ability_of(InvAbility.Kind.USE) as InvConsumable).part_repair = 25.0
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	match role:
		"host":
			_host()
		"client":
			_client()
		_:
			_log("falta --inv-partes")
			get_tree().quit(3)


func _log(text: String) -> void:
	print("[inv_partes:%s] %s" % [role, text])


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


func _until(condition: Callable, seconds: float) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < limit:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false


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


static func digest(state: ActorState, grid: InvGrid) -> String:
	return "salud=%d integridad=%s botiquines=%d vendas=%d venenos=%d" % [state.health, state.integrity,
			grid.quantity_of(&"botiquin") if grid != null else -1, grid.quantity_of(&"vendas") if grid != null else -1,
			grid.quantity_of(&"veneno") if grid != null else -1]


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
	await _until(_client_ready, 30.0)
	var client := _remote_actor()
	_check(client != null, "el cliente entra")
	if client == null:
		_finish()
		return
	await _ticks(30)
	# Las dos piernas lastimadas, como un evento del host (sube la época).
	client.state.integrity[ActorState.Part.LEG_LEFT] = HURT
	client.state.integrity[ActorState.Part.LEG_RIGHT] = HURT
	client.state.epoch += 1
	_log("le lastima las dos piernas al cliente en el tick %d" % lab._clock.tick)
	var last := ""
	while is_instance_valid(client) and client.is_inside_tree():
		var inventory := net.authority.player_inventory(client.owner_peer_id)
		var now := digest(client.state, inventory.grid if inventory != null else null)
		if now != last:
			last = now
			_log("CLIENTE %s" % now)
		await get_tree().physics_frame
	_log("pedidos aceptados %d, rechazados %d, repetidos %d" % [net.authority.accepted, net.authority.rejected,
			net.authority.repeated])
	_finish(true)


# --- Cliente --------------------------------------------------------------------------------

func _client() -> void:
	_check(await _until(func() -> bool: return net.replica.has_state and _actor() != null and net.replica.own != null, 20.0),
			"recibe el estado inicial del host")
	_check(await _until(_legs_hurt, 20.0) and hud.injury_warning(),
			"el host le lastimó las piernas: el panel lo muestra y la luz se prende")
	for def_id in [&"botiquin", &"vendas", &"veneno"]:
		await _pick_up(def_id)
	await _heal_with_gesture()
	await _normal_uses()
	var actor := _actor()
	_log("FINAL %s" % digest(actor.state, net.replica.own))
	_log("correcciones %d, coincidencias %d" % [lab._prediction.corrections, lab._prediction.matches])
	_finish(true)


## Si el panel ya muestra las piernas lastimadas por el host.
func _legs_hurt() -> bool:
	var shown := hud.integrity()
	return shown.size() == ActorState.PARTS and shown[ActorState.Part.LEG_LEFT] == HURT


func _pick_up(def_id: StringName) -> void:
	var uid := 0
	for item in net.replica.world:
		if net.replica.world[item]["stack"].def_id == def_id:
			uid = item
			break
	_check(uid != 0, "ve %s en el piso" % def_id)
	if uid == 0:
		return
	_check(await _walk_to(net.replica.world[uid]["pos"] + Vector3(-1.0, 0, 0)), "camina hasta %s" % def_id)
	var seq := ui.pick_up_world(uid, String(def_id))
	_check(seq != 0 and await _until(func() -> bool: return _answers.has(seq), 5.0) and _answers[seq][0], "recoge %s" % def_id)


func _uid_of(def_id: StringName) -> int:
	for uid in net.replica.own.sorted_uids():
		if net.replica.own.stacks[uid].def_id == def_id:
			return uid
	return 0


func _part_center(part: int) -> Vector2:
	return LabHud._part_rect(hud.integrity_panel_rect(), part).get_center()


func _click(at: Vector2) -> void:
	ui._mouse = at
	ui._left_press()


## El botiquín, las vendas y el veneno con el gesto de agarrar y dejar, sobre
## el panel de integridad. Desde el 2026-11-06 a la noche cada uno sale como un
## uso en el input y se ve sin esperar al host.
func _heal_with_gesture() -> void:
	var actor := _actor()
	var kit := _uid_of(&"botiquin")
	var bandages := _uid_of(&"vendas")
	var poison := _uid_of(&"veneno")
	var kits := net.replica.own.quantity_of(&"botiquin")
	_check(kit != 0 and kits == 3 and bandages != 0 and poison != 0, "tres botiquines, una venda y el veneno")
	ui.open()
	await _ticks(3)
	ui._layout()
	var health := actor.state.health
	# Donde no sirve: sigue en la mano, sin pedido ni uso.
	_click(ui._item_rect(InvProtocol.OWN, kit).get_center())
	_click(_part_center(ActorState.Part.TORSO))
	var layout := LabHud._figure_layout(hud.integrity_panel_rect())
	_click(layout[0] + Vector2(32.0, 75.0) * layout[1])
	_check(ui.held_def() != null and net.replica.pending.is_empty() and net.replica.uses_waiting() == 0
			and net.replica.shown_own().quantity_of(&"botiquin") == kits,
			"sobre una parte sana y entre las piernas: sigue en la mano, sin pedido, sin uso ni gasto")
	# La pierna izquierda: sale un uso y se ve enseguida.
	var sent := Time.get_ticks_msec()
	_click(_part_center(ActorState.Part.LEG_LEFT))
	_check(ui.held_def() == null and net.replica.pending.is_empty() and net.replica.uses_waiting() == 1
			and net.replica.shown_own().quantity_of(&"botiquin") == kits - 1,
			"sobre la pierna izquierda: sale un uso, sin pedido, y ya se ve un botiquín menos")
	var shown := await _until(func() -> bool: return hud.integrity()[ActorState.Part.LEG_LEFT] == FULL, 3.0)
	var left_msec := Time.get_ticks_msec() - sent
	_check(shown and left_msec < 120, "el panel muestra la pierna izquierda al 100 %% a los %d ms del clic, sin esperar al host" % left_msec)
	_log("curar la pierna izquierda: el panel la mostró a los %d ms" % left_msec)
	_check(hud.integrity()[ActorState.Part.LEG_RIGHT] == HURT and hud.injury_warning() and actor.state.health == health,
			"la derecha sigue lastimada, la luz prendida y la salud igual")
	# Las vendas (25 en esta prueba) sobre la derecha, enseguida: la suben un poco.
	sent = Time.get_ticks_msec()
	_click(ui._item_rect(InvProtocol.OWN, bandages).get_center())
	_click(_part_center(ActorState.Part.LEG_RIGHT))
	shown = await _until(func() -> bool: return hud.integrity()[ActorState.Part.LEG_RIGHT] == HURT + 2500, 3.0)
	var right_msec := Time.get_ticks_msec() - sent
	_check(shown and right_msec < 120 and not hud.injury_warning(),
			"las vendas sobre la derecha: de 60,5 %% a 85,5 %% a los %d ms, y la luz naranja se apaga (todo arriba del 60 %%)" % right_msec)
	# El veneno no cura partes: sigue en la mano.
	_click(ui._item_rect(InvProtocol.OWN, poison).get_center())
	_click(_part_center(ActorState.Part.LEG_RIGHT))
	_check(ui.held_def() != null and ui.held_def().id == &"veneno" and ui.last_message().contains("no cura partes"),
			"el veneno sobre la pierna: sigue en la mano y dice que no cura partes")
	ui._cancel_mode("")
	# El botiquín otra vez, enseguida (su uso puede no estar confirmado), sobre
	# la derecha, la última parte dañada: se apaga la luz.
	sent = Time.get_ticks_msec()
	_click(ui._item_rect(InvProtocol.OWN, kit).get_center())
	_check(ui.held_def() != null and ui.held_def().id == &"botiquin", "el botiquín se vuelve a agarrar enseguida")
	_click(_part_center(ActorState.Part.LEG_RIGHT))
	shown = await _until(func() -> bool: return hud.integrity().count(FULL) == ActorState.PARTS and not hud.injury_warning(), 3.0)
	var last_msec := Time.get_ticks_msec() - sent
	_check(shown and last_msec < 120, "la última parte: todo al 100 %% y la luz apagada a los %d ms" % last_msec)
	# El host confirma los tres: cada uno viajó en varios inputs y se hizo una vez.
	_check(await _until(func() -> bool: return net.replica.uses_waiting() == 0, 5.0), "el host confirma los tres usos")
	await _ticks(30)
	_check(net.replica.own.quantity_of(&"botiquin") == kits - 2 and net.replica.own.quantity_of(&"vendas") == 0
			and actor.state.health == health and actor.state.integrity.count(FULL) == ActorState.PARTS
			and hud.integrity().count(FULL) == ActorState.PARTS,
			"confirmado: quedan %d botiquines, ninguna venda, la salud igual y el cuerpo entero" % net.replica.own.quantity_of(&"botiquin"))
	ui.close()


## Usados normal: dos venenos (100 → 20) y el botiquín (+50). Las vendas
## usadas normal (+25) las prueba integridad_test: acá se gastaron en la pierna.
func _normal_uses() -> void:
	var actor := _actor()
	for i in 2:
		_check(ui.use_item(_uid_of(&"veneno")), "usa un veneno")
		await _ticks(3)
	_check(await _until(func() -> bool: return net.replica._uses.is_empty(), 5.0) and actor.state.health == 20 * H,
			"dos venenos: salud 20")
	_check(ui.use_item(_uid_of(&"botiquin")), "usa el botiquín, normal")
	await _ticks(3)
	_check(actor.state.health == 70 * H, "el botiquín cura 50: salud %.1f" % (actor.state.health / float(H)))
	_check(await _until(func() -> bool: return net.replica._uses.is_empty(), 5.0), "el host contesta todos los usos")
	await _ticks(30)
	_check(actor.state.health == 70 * H and actor.state.integrity.count(FULL) == ActorState.PARTS
			and hud.integrity().count(FULL) == ActorState.PARTS, "después de que contesta el host: salud 70, todo el cuerpo entero")
