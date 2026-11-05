extends Node

## Prueba del inventario en red, con procesos separados: arranca net_lab.tscn
## con los argumentos de siempre (--host, --client, --sim-…, --test-relay…) y
## además --inv-pair=host, a o b, que dice qué guion sigue esta máquina:
##
## - host: recoge tornillos, pone una pila en la caja compartida y, cuando el
##   cliente A la tiene abierta, pone la llave como aviso y tira de la misma
##   pila que A (gana uno solo). Después mueve la llave mientras A la arrastra,
##   equipa el machete y suelta 3 tornillos. Espera a que se vayan todos.
## - a: camina hasta la zona, recoge las dos baterías (no se apilan), abre la
##   caja, tira de la pila cuando ve la llave, arrastra la llave hasta que el
##   host la mueve, se corta (relevo) y al volver comprueba que su inventario
##   sigue igual.
## - b: entra tarde y comprueba que ve el mundo como el host, con lo soltado, y
##   el machete en la mano del host.
##
## Cada uno imprime el estado del mundo y de su inventario ("MUNDO", "PROPIO",
## y el host "INVENTARIO <peer>") para compararlos entre procesos.

const ZONE := Vector3(37, 0, 13)
const CRATE_SPOT := Vector3(38.8, 0, 10.6)
const Op := InvProtocol.Op

var role := ""
var lab: Node3D
var net: InvNet
var ui: InvUI
var _answers := {}
var _checks := 0
var _failures := 0
var _finishing := false
var _printed := {}


func _ready() -> void:
	var limit := 100.0
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--inv-pair="):
			role = arg.trim_prefix("--inv-pair=")
		elif arg.begins_with("--inv-timeout="):
			limit = arg.trim_prefix("--inv-timeout=").to_float()
	# Si se acaba el tiempo, el recorrido no terminó: es una falla, aunque lo
	# que se alcanzó a comprobar haya dado bien (auditoría del 2026-11-04, PRU-01).
	# --inv-timeout=SEGUNDOS lo acorta, para comprobar justamente eso.
	get_tree().create_timer(limit, true, false, true).timeout.connect(func() -> void:
		_failures += 1
		_log("TIEMPO AGOTADO: el recorrido no terminó")
		_finish())
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	add_child(lab)
	net = lab.get_node("Inventario")
	ui = lab.get_node("Hud/InventarioUI")
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	match role:
		"host":
			_host()
		"a":
			_client_a()
		"b":
			_client_b()
		_:
			_log("falta --inv-pair")
			get_tree().quit(3)


func _log(text: String) -> void:
	print("[inv_pair:%s] %s" % [role, text])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	_log("%s: %s" % ["ok" if ok else "FALLA", what])


## Termina la prueba. Sale bien solo si el recorrido llegó al final
## (`completed`), con alguna comprobación y sin fallas: el tiempo agotado, un
## recorrido cortado a la mitad o uno sin comprobaciones salen con error.
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


func _frames(count: int) -> void:
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
				await _frames(20)
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


## El host mueve a su personaje de golpe: es la autoridad.
func _teleport(position: Vector3) -> void:
	var actor := _actor()
	var state := actor.state
	state.position = position
	state.velocity = Vector3.ZERO
	state.mode = ActorState.Mode.GROUND
	state.on_floor = true
	state.base_id = 0
	state.epoch += 1
	state.quantize()
	actor.apply_state(state)
	actor.teleported()
	await _frames(3)


func _world_uid(def_id: StringName, quantity := -1, state := {}) -> int:
	var found := 0
	var keys := net.replica.world.keys()
	keys.sort()
	for uid in keys:
		var stack: InvStack = net.replica.world[uid]["stack"]
		if stack.def_id == def_id and (quantity < 0 or stack.quantity == quantity) \
				and (state.is_empty() or InvStack.same_state(stack.state, state)):
			found = uid
			break
	return found


static func world_digest(world: Dictionary) -> String:
	var keys := world.keys()
	keys.sort()
	var parts := PackedStringArray()
	for uid in keys:
		var stack: InvStack = world[uid]["stack"]
		var pos: Vector3 = world[uid]["pos"]
		parts.append("%d:%s:%d:%s@%.2f,%.2f,%.2f" % [uid, stack.def_id, stack.quantity, var_to_str(stack.state).replace("\n", ""),
				pos.x, pos.y, pos.z])
	return " ".join(parts)


static func grid_digest(grid: InvGrid) -> String:
	if grid == null:
		return "(sin grilla)"
	var parts := PackedStringArray()
	for uid in grid.sorted_uids():
		var place := grid.placement(uid)
		parts.append("%d:%s:%d:%d,%d,%d" % [uid, grid.stacks[uid].def_id, grid.stacks[uid].quantity, place.cell.x,
				place.cell.y, place.rot])
	return " ".join(parts)


# --- Host -----------------------------------------------------------------------------

func _host() -> void:
	var seen := {}
	multiplayer.peer_connected.connect(func(peer: int) -> void: seen[peer] = true)
	await _until(func() -> bool: return net.authority != null and _actor() != null and net.replica.own != null, 10.0)
	_watch_inventories()
	var found := {}
	await _until(func() -> bool:
		for peer in net.authority._welcomed:
			if peer != 1:
				found["a"] = peer
		return found.has("a"), 20.0)
	var peer_a: int = found.get("a", 0)
	_check(peer_a != 0, "entró el cliente A (jugador %d)" % peer_a)
	var screws_a := _world_uid(&"tornillos")
	await _teleport(ZONE + Vector3(-2, 0, -4.4))
	await _req(Op.PICKUP, [screws_a], [screws_a])
	var screws_b := _world_uid(&"tornillos")
	await _req(Op.PICKUP, [screws_b], [screws_b])
	_check(net.replica.own.has(screws_b) and net.replica.own.get_stack(screws_b).quantity == 10, "el host tiene 30 + 10 tornillos")
	var key := _world_uid(&"llave")
	await _teleport(net.replica.world[key]["pos"] + Vector3(-1, 0, 0))
	await _req(Op.PICKUP, [key], [key])
	var machete := _world_uid(&"machete")
	await _teleport(net.replica.world[machete]["pos"] + Vector3(-1, 0, 0))
	await _req(Op.PICKUP, [machete], [machete])
	await _teleport(CRATE_SPOT + Vector3(0, 0, -1.2))
	var r := await _req(Op.OPEN, [1])
	_check(r[0], "el host abre la caja compartida")
	r = await _req(Op.MOVE, [0, screws_b, net.replica.own.get_stack(screws_b).ver, 1, 0, 0, 0], [screws_b])
	_check(r[0], "pone la pila de 10 en la caja")
	_check(await _until(func() -> bool: return net.authority.open_container_of(peer_a) == 1, 30.0), "el cliente A abrió la caja")
	await _frames(30)
	# El aviso: la llave en la caja. A, al verla, tira de la pila de tornillos.
	r = await _req(Op.MOVE, [0, key, net.replica.own.get_stack(key).ver, 1, 4, 4, 0], [key])
	_check(r[0], "la llave a la caja (aviso para A)")
	await _frames(4)
	var in_box: InvStack = net.replica.box.get_stack(screws_b)
	var mine := await _req(Op.MOVE, [1, screws_b, in_box.ver if in_box != null else 0, 0, 11, 15, 0], [screws_b])
	await _frames(60)
	var host_has := net.authority.player_inventory(1).grid.has(screws_b)
	var a_inventory := net.authority.player_inventory(peer_a)
	var a_has := a_inventory != null and a_inventory.grid.has(screws_b)
	var box_has: bool = net.authority.containers[1].inventory.grid.has(screws_b)
	_log("carrera por la pila %d: el host %s (%s), A la tiene: %s" % [screws_b, "ganó" if mine[0] else "perdió", mine[1], a_has])
	_check(int(host_has) + int(a_has) == 1 and not box_has, "la pila quedó en un solo lugar")
	_check(mine[0] == host_has, "el resultado que vio el host coincide con dónde quedó")
	# A tiene la llave en la mano: el host la mueve dentro de la caja.
	await get_tree().create_timer(1.5).timeout
	var key_box: InvStack = net.replica.box.get_stack(key)
	r = await _req(Op.MOVE, [1, key, key_box.ver, 1, 6, 6, 0], [key])
	_check(r[0], "el host mueve la llave mientras A la tiene en la mano")
	r = await _req(Op.EQUIP, [machete, net.replica.own.get_stack(machete).ver], [machete])
	_check(r[0], "el host se equipa el machete")
	var screws_kept := screws_a if net.replica.own.has(screws_a) else screws_b
	r = await _req(Op.DROP, [0, screws_kept, net.replica.own.get_stack(screws_kept).ver, 3], [screws_kept])
	_check(r[0], "el host suelta 3 tornillos")
	# A se corta y vuelve; B entra tarde. Se espera a que se vayan los dos.
	var session: NetSession = lab._session
	_check(await _until(func() -> bool: return session.players_back >= 1, 60.0), "A volvió después del corte (otro número de jugador)")
	await _until(func() -> bool: return seen.size() >= 3 and multiplayer.get_peers().is_empty(), 60.0)
	_check(seen.size() >= 3, "entraron A, A de vuelta y B (%s)" % [seen.keys()])
	await _frames(30)
	_check(multiplayer.get_peers().is_empty(), "se fueron todos")
	_check(net.queued_requests() == 0, "sin pedidos en la fila")
	for peer in seen:
		if peer != 1:
			_check(net.authority.open_container_of(peer) == 0 and not net.authority.is_welcomed(peer),
					"del jugador %d no queda ninguna suscripción" % peer)
	_log("MUNDO %s" % world_digest(net.authority.world))
	_log("MUNDO_REPLICA %s" % world_digest(net.replica.world))
	_finish(true)


## Host: cada vez que cambia el inventario de alguien, lo imprime.
func _watch_inventories() -> void:
	while true:
		for node in lab.get_node("Actors").get_children():
			var actor := node as ActorBody
			var inventory := actor.get_node_or_null("Inventario") as InvInventory if actor != null else null
			if inventory == null or inventory.grid == null:
				continue
			var digest := grid_digest(inventory.grid)
			if _printed.get(actor.owner_peer_id, "") != digest:
				_printed[actor.owner_peer_id] = digest
				_log("INVENTARIO %d %s" % [actor.owner_peer_id, digest])
		await get_tree().create_timer(0.25).timeout


# --- Cliente A ------------------------------------------------------------------------------

func _client_a() -> void:
	_check(await _until(func() -> bool: return net.replica.has_state and _actor() != null and net.replica.own != null, 20.0),
			"A recibe el estado inicial del host")
	for state in [{"carga": 100}, {"carga": 40}]:
		var uid := _world_uid(&"bateria", -1, state)
		_check(uid != 0, "A ve la batería %s" % [state])
		_check(await _walk_to(net.replica.world[uid]["pos"] + Vector3(-1.0, 0, 0)), "A camina hasta la batería")
		var got := await _req(Op.PICKUP, [uid], [uid])
		_check(got[0], "A recoge la batería %s: %s" % [state, got[1]])
	var batteries := []
	for uid in net.replica.own.sorted_uids():
		if net.replica.own.stacks[uid].def_id == &"bateria":
			batteries.append(uid)
	_check(batteries.size() == 2, "las dos baterías quedan en pilas separadas")
	_check(await _walk_to(CRATE_SPOT), "A camina hasta la caja")
	var found := {}
	await _until(func() -> bool:
		var box := net.container(1)
		return box != null and _actor().global_position.distance_to(box.access_point()) < box.access_range - 0.2, 5.0)
	var r := await _req(Op.OPEN, [1])
	_check(r[0] and net.replica.box_id == 1, "A abre la caja compartida: %s" % r[1])
	_check(await _until(func() -> bool:
		if net.replica.box == null:
			return false
		for uid in net.replica.box.stacks:
			if net.replica.box.stacks[uid].def_id == &"tornillos":
				found["screws"] = uid
		return found.has("screws"), 30.0), "A ve los tornillos del host en la caja")
	_check(await _until(func() -> bool:
		if net.replica.box == null:
			return false
		for uid in net.replica.box.stacks:
			if net.replica.box.stacks[uid].def_id == &"llave":
				found["key"] = uid
		return found.has("key"), 30.0), "A ve la llave (el aviso)")
	var screws: int = found.get("screws", 0)
	var key: int = found.get("key", 0)
	var stack: InvStack = net.replica.box.get_stack(screws)
	var race := await _req(Op.MOVE, [1, screws, stack.ver if stack != null else 0, 0, 0, 15, 0], [screws])
	await _frames(30)
	var mine := net.replica.own.has(screws)
	_log("carrera por la pila %d: A %s (%s)" % [screws, "ganó" if race[0] else "perdió", race[1]])
	_check(race[0] == mine and not net.replica.box.has(screws), "lo que ve A coincide con lo que contestó el host")
	# Agarra la llave con un clic; el host la mueve: se le suelta de la mano.
	ui.size = Vector2(1600, 900)
	ui.open()
	ui._layout()
	ui._mouse = ui._item_rect(1, key).get_center()
	ui._left_press()
	_check(ui._mode == InvUI.Mode.HOLD, "A tiene la llave en la mano")
	_check(await _until(func() -> bool: return ui._mode == InvUI.Mode.NONE, 10.0), "el host la movió: a A se le soltó de la mano")
	_check(ui.last_message().begins_with("Ese objeto cambió"), "A ve el aviso: %s" % ui.last_message())
	_check(net.replica.box.has(key) and net.replica.box.placement(key).cell == Vector2i(6, 6), "y ve la llave donde la dejó el host")
	_check(await _until(func() -> bool: return net.replica.equipment.get(1, "") == "machete", 10.0), "A ve que el host equipó el machete")
	await _frames(10)
	var host_actor: ActorBody = lab.get_node_or_null("Actors/Actor1")
	var view := host_actor.visual_root().get_node_or_null("Equipado") as InvEquipView if host_actor != null else null
	_check(view != null and view.equipped_id() == &"machete", "y lo dibuja en su personaje")
	_check(await _until(func() -> bool: return _world_uid(&"tornillos", 3) != 0, 10.0), "A ve los 3 tornillos que soltó el host")
	await _frames(10)
	_check(net.world_view(_world_uid(&"tornillos", 3)) != null, "y los dibuja en el mundo")
	ui.close()
	var before := grid_digest(net.replica.own)
	_log("PROPIO_ANTES %d %s" % [multiplayer.get_unique_id(), before])
	# El corte llega solo (--test-cut-at): se espera a volver.
	var session: NetSession = lab._session
	_check(await _until(func() -> bool: return session.reconnects >= 1 and net.replica.has_state and net.replica.own != null, 60.0),
			"A vuelve después del corte")
	await _frames(30)
	var after := grid_digest(net.replica.own)
	_check(after == before, "su inventario es el mismo, con los mismos ids: %s" % after)
	_check(net.replica.box == null, "la caja quedó cerrada al cortarse")
	_log("PROPIO %d %s" % [multiplayer.get_unique_id(), after])
	await get_tree().create_timer(2.0).timeout
	_log("MUNDO %s" % world_digest(net.replica.world))
	_finish(true)


# --- Cliente B (entra tarde) --------------------------------------------------------------------

func _client_b() -> void:
	_check(await _until(func() -> bool: return net.replica.has_state and _actor() != null, 20.0), "B recibe el estado inicial")
	await _frames(30)
	var dropped := _world_uid(&"tornillos", 3)
	_check(dropped != 0, "B ve los 3 tornillos que soltó el host antes de que entrara")
	_check(net.world_view(dropped) != null, "y los dibuja en el mundo")
	_check(_world_uid(&"bateria") == 0 and _world_uid(&"llave") == 0, "y no ve lo que ya se recogió")
	_check(net.replica.equipment.get(1, "") == "machete", "B sabe que el host tiene el machete")
	var host_actor: ActorBody = lab.get_node_or_null("Actors/Actor1")
	var view := host_actor.visual_root().get_node_or_null("Equipado") as InvEquipView if host_actor != null else null
	_check(view != null and view.equipped_id() == &"machete", "y lo dibuja en la mano del host")
	_check(net.replica.own != null and net.replica.own.stacks.is_empty(), "B empieza con su inventario vacío")
	_log("MUNDO %s" % world_digest(net.replica.world))
	_finish(true)
