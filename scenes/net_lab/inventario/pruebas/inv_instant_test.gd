extends Node

## Prueba de usar y recoger sin esperar al host (2026-11-04), con dos procesos:
## arranca net_lab.tscn con los argumentos de siempre (--host, --client,
## --sim-…) y además --inv-instant=host o client.
##
## - client (con internet mala simulada): camina hasta los consumibles de la
##   zona y los recoge y los usa por el camino de la interfaz
##   (InvUI.pick_up_world, InvUI.use_item). Lo recogido tiene que verse en la
##   grilla y dejar de verse en el piso en el mismo cuadro; un consumible, verse
##   gastado en el mismo cuadro y cambiar la salud en el tick siguiente, sin
##   pedidos pendientes ni "esperando…", y sin correcciones cuando contesta el
##   host. También: dos seguidos (uno por tick), uno que el host no puede usar
##   porque esta máquina no lo podía usar tampoco (vuelve con un aviso), uno
##   que esta máquina predijo y el host no (se corrige solo), una muerte y un
##   daño en el tiempo.
## - host: imprime la salud, las muertes, los usos y el inventario del cliente
##   cada vez que cambian ("CLIENTE …"), para compararlos con lo que imprime
##   el cliente al final ("FINAL …"). Termina cuando el cliente se va.

const Op := InvProtocol.Op
const H := ActorState.HEALTH_UNIT

var role := ""
var lab: Node3D
var net: InvNet
var ui: InvUI
var hud: LabHud
var _answers := {}
var _checks := 0
var _failures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--inv-instant="):
			role = arg.trim_prefix("--inv-instant=")
	get_tree().create_timer(100.0, true, false, true).timeout.connect(func() -> void:
		_log("TIEMPO AGOTADO")
		_finish())
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	add_child(lab)
	net = lab.get_node("Inventario")
	ui = lab.get_node("Hud/InventarioUI")
	hud = lab.get_node("Hud/Instrumentos")
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	match role:
		"host":
			_host()
		"client":
			_client()
		_:
			_log("falta --inv-instant")
			get_tree().quit(3)


func _log(text: String) -> void:
	print("[inv_instant:%s] %s" % [role, text])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	_log("%s: %s" % ["ok" if ok else "FALLA", what])


func _finish() -> void:
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


func _world_uid(def_id: StringName) -> int:
	var keys := net.replica.world.keys()
	keys.sort()
	for uid in keys:
		if net.replica.world[uid]["stack"].def_id == def_id:
			return uid
	return 0


static func _count(grid: InvGrid, def_id: StringName) -> int:
	return grid.quantity_of(def_id) if grid != null else 0


static func _first_of(grid: InvGrid, def_id: StringName) -> int:
	for uid in grid.sorted_uids():
		if grid.stacks[uid].def_id == def_id:
			return uid
	return 0


static func grid_digest(grid: InvGrid) -> String:
	if grid == null:
		return "(sin grilla)"
	var parts := PackedStringArray()
	for uid in grid.sorted_uids():
		var place := grid.placement(uid)
		parts.append("%d:%s:%d:%d,%d,%d" % [uid, grid.stacks[uid].def_id, grid.stacks[uid].quantity, place.cell.x,
				place.cell.y, place.rot])
	return " ".join(parts)


static func vitals_digest(state: ActorState) -> String:
	return "salud=%d muertes=%d usos=%d daños=%s" % [state.health, state.deaths, state.use_presses_seen, state.effect_duration]


# --- Host ---------------------------------------------------------------------------------

func _remote_actor() -> ActorBody:
	for node in lab._actors.get_children():
		if node is ActorBody and node.owner_peer_id != multiplayer.get_unique_id() and not node.is_queued_for_deletion():
			return node
	return null


func _host() -> void:
	await _until(func() -> bool: return _remote_actor() != null, 30.0)
	var client := _remote_actor()
	_check(client != null, "el cliente entra")
	if client == null:
		_finish()
		return
	var last := ""
	while is_instance_valid(client) and client.is_inside_tree():
		var inventory := net.authority.player_inventory(client.owner_peer_id)
		var now := "%s %s" % [vitals_digest(client.state), grid_digest(inventory.grid if inventory != null else null)]
		if now != last:
			last = now
			_log("CLIENTE %s" % now)
		await get_tree().physics_frame
	_log("pedidos aceptados %d, rechazados %d" % [net.authority.accepted, net.authority.rejected])
	_finish()


# --- Cliente --------------------------------------------------------------------------------

func _client() -> void:
	_check(await _until(func() -> bool: return net.replica.has_state and _actor() != null and net.replica.own != null, 20.0),
			"recibe el estado inicial del host")
	for def_id in [&"veneno", &"botiquin", &"capsula_letal", &"toxina_lenta"]:
		await _pick_up(def_id)
	await _use_one()
	await _two_kits()
	await _two_poisons()
	await _lethal()
	await _host_says_no()
	await _over_time()
	await _drop_things()
	var actor := _actor()
	_check(net.replica.shown_own() == net.replica.own, "al final no queda nada sin confirmar")
	_log("FINAL %s %s" % [vitals_digest(actor.state), grid_digest(net.replica.own)])
	_log("correcciones %d, coincidencias %d" % [lab._prediction.corrections, lab._prediction.matches])
	_finish()


## Recoger: lo que se ve no espera la respuesta.
func _pick_up(def_id: StringName) -> void:
	var uid := _world_uid(def_id)
	_check(uid != 0, "ve %s en el piso" % def_id)
	if uid == 0:
		return
	_check(await _walk_to(net.replica.world[uid]["pos"] + Vector3(-1.0, 0, 0)), "camina hasta %s" % def_id)
	var quantity: int = net.replica.world[uid]["stack"].quantity
	var confirmed := _count(net.replica.own, def_id)
	var sent := Time.get_ticks_msec()
	var seq := ui.pick_up_world(uid, String(def_id))
	_check(seq != 0, "pide recoger %s" % def_id)
	var mine := _first_of(net.replica.shown_own(), def_id)
	_check(_count(net.replica.shown_own(), def_id) == confirmed + quantity and _count(net.replica.own, def_id) == confirmed,
			"en el mismo cuadro, %s ya se ve en la grilla (%d) y el host todavía no contestó" % [def_id, quantity])
	_check(net.replica.is_taken(uid) and net.world_view(uid) == null, "y ya no se ve en el piso")
	_check(mine != 0 and not ui._waiting(mine), "sin \"esperando…\" encima")
	_check(await _until(func() -> bool: return _answers.has(seq), 5.0) and _answers[seq][0], "el host lo confirma")
	_log("recoger %s: el host contestó a los %d ms" % [def_id, Time.get_ticks_msec() - sent])
	_check(grid_digest(net.replica.shown_own()) == grid_digest(net.replica.own), "lo que se veía es lo que confirmó")


## Espera a que el host confirme todos los usos y un rato más (llegan los snapshots).
func _settle() -> int:
	var sent := Time.get_ticks_msec()
	await _until(func() -> bool: return net.replica._uses.is_empty(), 5.0)
	var waited := Time.get_ticks_msec() - sent
	await _ticks(30)
	return waited


func _use_one() -> void:
	var actor := _actor()
	var poison := _first_of(net.replica.own, &"veneno")
	var left := _count(net.replica.shown_own(), &"veneno")
	var health := actor.state.health
	var epoch := actor.state.epoch
	var corrections: int = lab._prediction.corrections
	_check(ui.use_item(poison), "usa un veneno")
	_check(_count(net.replica.shown_own(), &"veneno") == left - 1 and net.replica.pending.is_empty() and not ui._waiting(poison),
			"en el mismo cuadro se ve gastado, sin pedido ni \"esperando…\"")
	await _ticks(2)
	_check(actor.state.health == health - 40 * H, "en el tick siguiente la salud ya bajó 40: %.1f" % (actor.state.health / float(H)))
	_check(actor.state.epoch == epoch, "no es un evento del host: la época no sube")
	var waited := await _settle()
	_log("usar un veneno: el host lo confirmó a los %d ms" % waited)
	_check(actor.state.health == health - 40 * H and lab._prediction.corrections == corrections,
			"cuando contesta el host no hay corrección: %.1f, correcciones %d → %d" % [actor.state.health / float(H), corrections,
			lab._prediction.corrections])
	_check(_count(net.replica.own, &"veneno") == left - 1, "y el host gastó una")


## Dos botiquines seguidos con 60 de salud: el primero cura hasta 100 y el
## segundo, en el tick siguiente, ya no tiene qué curar: no se usa en ninguna
## de las dos máquinas, vuelve a verse y lo dice.
func _two_kits() -> void:
	var actor := _actor()
	var kit := _first_of(net.replica.own, &"botiquin")
	var kits := _count(net.replica.own, &"botiquin")
	var corrections: int = lab._prediction.corrections
	_check(ui.use_item(kit) and ui.use_item(kit), "usa dos botiquines en el mismo cuadro")
	_check(_count(net.replica.shown_own(), &"botiquin") == kits - 2, "los dos se ven gastados")
	await _ticks(3)
	_check(actor.state.health == 100 * H, "uno por tick: el primero cura hasta 100, el segundo ya no")
	await _settle()
	_check(_count(net.replica.shown_own(), &"botiquin") == kits - 1 and _count(net.replica.own, &"botiquin") == kits - 1,
			"el host gastó uno solo y el otro vuelve a verse")
	_check(ui._toast.contains("No se usó") and ui._toast.contains("salud completa"), "y lo dice: %s" % ui._toast)
	_check(lab._prediction.corrections == corrections and actor.state.health == 100 * H, "sin correcciones")


func _two_poisons() -> void:
	var actor := _actor()
	var poison := _first_of(net.replica.own, &"veneno")
	var left := _count(net.replica.own, &"veneno")
	var corrections: int = lab._prediction.corrections
	_check(ui.use_item(poison) and ui.use_item(poison), "usa dos venenos en el mismo cuadro")
	await _ticks(1)
	var after_one := actor.state.health
	await _ticks(2)
	_check(after_one == 60 * H and actor.state.health == 20 * H, "uno por tick: 100 → 60 → 20 (%.1f, %.1f)" % [
			after_one / float(H), actor.state.health / float(H)])
	await _settle()
	_check(_count(net.replica.own, &"veneno") == left - 2 and lab._prediction.corrections == corrections
			and actor.state.health == 20 * H, "el host gastó los dos, sin correcciones")


func _lethal() -> void:
	var actor := _actor()
	var pill := _first_of(net.replica.own, &"capsula_letal")
	var deaths := actor.state.deaths
	var shown := hud.deaths_shown
	var corrections: int = lab._prediction.corrections
	# Desde la barra rápida, como el jugador.
	var slot := -1
	for i in InvLoadout.HOTBAR_SLOTS:
		if net.replica.loadout.hotbar[i] == 0:
			slot = i
			break
	var r := [false, "no salió"]
	var seq := net.replica.request(Op.HOTBAR_SET, [slot, pill], [], [slot])
	if await _until(func() -> bool: return _answers.has(seq), 5.0):
		r = _answers[seq]
	_check(r[0], "pone la cápsula en el acceso %d: %s" % [slot, r[1]])
	ui._press_slot(slot)
	_check(net.replica.pending.is_empty(), "la tecla de la barra no le pide nada al host")
	await _ticks(2)
	_check(actor.state.deaths == (deaths + 1) & 0xFF and actor.state.health == 100 * H, "en el tick siguiente, la muerte de prueba")
	await get_tree().process_frame
	_check(hud.deaths_shown == shown + 1 and hud.is_showing_death(), "y el aviso, sin esperar al host")
	await _settle()
	_check(actor.state.deaths == (deaths + 1) & 0xFF and lab._prediction.corrections == corrections and hud.deaths_shown == shown + 1,
			"el host coincide: una muerte, sin correcciones ni otro aviso")


## Uno que esta máquina predijo y el host no pudo usar (un objeto que no está
## en el inventario: lo pide sin la interfaz). La corrección del host lo deshace.
func _host_says_no() -> void:
	var actor := _actor()
	var health := actor.state.health
	var corrections: int = lab._prediction.corrections
	net.queue_use(999999, net.catalog.find(&"veneno"))
	await _ticks(2)
	_check(actor.state.health == health - 40 * H, "esta máquina lo predice: %.1f" % (actor.state.health / float(H)))
	await _settle()
	_check(actor.state.health == health and lab._prediction.corrections > corrections,
			"el host no lo usó y la corrección lo deshace: %.1f, correcciones %d → %d" % [actor.state.health / float(H),
			corrections, lab._prediction.corrections])
	_check(ui._toast.contains("No se usó") and ui._toast.contains("no está en tu inventario"), "y lo dice: %s" % ui._toast)


func _world_at(def_id: StringName, at: Vector3) -> int:
	for uid in net.replica.world:
		if net.replica.world[uid]["stack"].def_id == def_id and (net.replica.world[uid]["pos"] as Vector3).distance_to(at) < 0.002:
			return uid
	return 0


## Soltar (2026-11-04, segunda parte): desde el menú y desde la mano, ya se ve
## en el piso, y el host lo deja en ese mismo lugar.
func _drop_things() -> void:
	var poison := _first_of(net.replica.own, &"veneno")
	var left := _count(net.replica.own, &"veneno")
	var sent := Time.get_ticks_msec()
	var seq := ui.drop_item(InvProtocol.OWN, poison, net.replica.shown_own().get_stack(poison).ver, 1)
	var ghost := net.world_view(-seq)
	_check(seq != 0 and ghost != null and _count(net.replica.shown_own(), &"veneno") == left - 1 and _count(net.replica.own, &"veneno") == left,
			"soltar un veneno: en el mismo cuadro ya está en el piso y hay uno menos en la grilla, y el host todavía no contestó")
	_check(not ui._waiting(poison), "sin \"esperando…\" en lo que queda")
	var at := ghost.global_position if ghost != null else Vector3.INF
	_check(await _until(func() -> bool: return _answers.has(seq), 5.0) and _answers[seq][0], "el host lo confirma")
	_log("soltar desde el menú: el host contestó a los %d ms" % (Time.get_ticks_msec() - sent))
	var landed := _world_at(&"veneno", at)
	_check(landed != 0 and net.world_view(-seq) == null and net.world_view(landed) != null, "y queda en el mismo lugar donde se veía")
	# Desde la mano: el botiquín entero, con un clic afuera de la grilla.
	var kit := _first_of(net.replica.own, &"botiquin")
	ui.open()
	ui._pick_up(InvProtocol.OWN, kit)
	ui._mouse = Vector2(ui.size.x - 10.0, 10.0)
	sent = Time.get_ticks_msec()
	ui._place_all()
	var flight: int = ui._flight.get("seq", 0)
	ghost = net.world_view(-flight) if flight != 0 else null
	_check(ghost != null and _count(net.replica.shown_own(), &"botiquin") == 0, "desde la mano: el botiquín ya está en el piso y no en la grilla")
	at = ghost.global_position if ghost != null else Vector3.INF
	_check(await _until(func() -> bool: return _answers.has(flight), 5.0) and _answers[flight][0], "el host lo confirma")
	_log("soltar desde la mano: el host contestó a los %d ms" % (Time.get_ticks_msec() - sent))
	_check(_world_at(&"botiquin", at) != 0 and net.world_view(-flight) == null, "y queda en el mismo lugar donde se veía")
	ui.close()
	await _ticks(10)
	_check(net.replica.predicted_drops().is_empty() and ui._flight.is_empty(), "no queda nada sin confirmar")


func _over_time() -> void:
	var actor := _actor()
	var toxin := _first_of(net.replica.own, &"toxina_lenta")
	var corrections: int = lab._prediction.corrections
	_check(ui.use_item(toxin), "usa una toxina lenta")
	await _ticks(2)
	_check(actor.state.effect_duration.count(0) == ActorState.MAX_EFFECTS - 1, "en el tick siguiente ya tiene un daño en el tiempo")
	await _settle()
	var health := actor.state.health
	await _ticks(60)
	_check(actor.state.health < health and lab._prediction.corrections == corrections,
			"baja de a poco, sin correcciones: %.1f → %.1f" % [health / float(H), actor.state.health / float(H)])
	await _until(func() -> bool: return actor.state.effect_duration.count(0) == ActorState.MAX_EFFECTS, 8.0)
	await _ticks(30)
	_check(actor.state.health == 80 * H, "al terminar quitó justo 20: %.3f" % (actor.state.health / float(H)))
