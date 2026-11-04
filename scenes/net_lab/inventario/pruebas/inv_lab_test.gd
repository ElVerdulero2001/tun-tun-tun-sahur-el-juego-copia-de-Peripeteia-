extends Node

## Prueba del inventario dentro del laboratorio de verdad, en un solo proceso:
## arranca net_lab.tscn jugando solo y pide todo por el mismo camino que la
## interfaz (InvReplica.request → InvNet → InvAuthority), con la física del
## nivel para soltar. Un segundo jugador se simula en el host: su actor existe
## y sus pedidos entran en la misma fila que los del primero. Lo de red de
## verdad (dos procesos) está en inv_pair_test.
##
## --headless --scene res://scenes/net_lab/inventario/pruebas/inv_lab_test.tscn

const ZONE := Vector3(37, 0, 13)
const Op := InvProtocol.Op

var lab: Node3D
var net: InvNet
var ui: InvUI
var actor: ActorBody
var _answers := {}
var _checks := 0
var _failures := 0
## Lo que el host le mandó al jugador simulado (peer 2).
var _peer2_payloads: Array = []
var _peer2_seq := 0


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[inv_lab_test] TIEMPO AGOTADO")
		get_tree().quit(2))
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	add_child(lab)
	net = lab.get_node("Inventario")
	ui = lab.get_node("Hud/InventarioUI")
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	await get_tree().process_frame
	lab._start(0)
	for i in 120:
		await get_tree().physics_frame
		if net.replica.own != null and is_instance_valid(lab._local_actor):
			break
	actor = lab._local_actor
	_check(actor != null and net.replica.own != null and net.replica.own.columns == 12 and net.replica.own.rows == 16,
			"jugando solo: el jugador tiene su grilla de 12 × 16")
	var spawns := lab.get_node("ZonaDeInventario").find_children("*", "InvPickupSpawn", true, false).size()
	_check(spawns >= 13 and net.replica.world.size() == spawns, "los %d objetos de la zona están en el mundo (hay %d)" % [
			spawns, net.replica.world.size()])
	var totals := _totals()
	await _pickups()
	await _stacks_and_split()
	await _hotbar_use_and_dedup()
	await _equip_and_drop()
	await _drop_near_wall_and_cage()
	await _containers()
	await _two_players()
	await _ui_rules()
	await _hold_and_place()
	await _look_and_reach()
	await _e_closes_box()
	await _container_disappears()
	var after := _totals()
	# La llave se fue con el segundo jugador y el banquito con la caja que
	# desapareció: los dos se comprueban ahí.
	for def_id in [&"tornillos", &"granada", &"bateria", &"machete", &"linterna", &"caja_de_herramientas"]:
		_check(after.get(def_id, 0) == totals.get(def_id, 0), "se conserva la cantidad de %s: %d → %d" % [
				def_id, totals.get(def_id, 0), after.get(def_id, 0)])
	print("[inv_lab_test] aceptados %d, rechazados %d, repetidos %d" % [net.authority.accepted, net.authority.rejected,
			net.authority.repeated])
	print("[inv_lab_test] %d comprobaciones, %d fallas" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Ayudas --------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[inv_lab_test] FALLA: %s" % what)


func _req(op: int, args: Array, uids: Array = []) -> Array:
	var seq := net.replica.request(op, args, uids)
	if seq == 0:
		return [false, "no salió"]
	for i in 30:
		if _answers.has(seq):
			return _answers[seq]
		await get_tree().physics_frame
	return [false, "sin respuesta"]


func _teleport(position: Vector3, yaw := 0.0) -> void:
	var state := actor.state
	state.position = position
	state.velocity = Vector3.ZERO
	state.facing_yaw = yaw
	state.mode = ActorState.Mode.GROUND
	state.on_floor = true
	state.base_id = 0
	state.quantize()
	actor.apply_state(state)
	actor.teleported()
	for i in 3:
		await get_tree().physics_frame


func _world_uids(def_id: StringName) -> Array:
	var list := []
	for uid in net.replica.world:
		if net.replica.world[uid]["stack"].def_id == def_id:
			list.append(uid)
	list.sort()
	return list


func _own_uids(def_id: StringName) -> Array:
	var list := []
	var grid := net.replica.own
	for uid in grid.sorted_uids():
		if grid.stacks[uid].def_id == def_id:
			list.append(uid)
	return list


## La pila más grande de ese tipo en el inventario propio.
func _biggest(def_id: StringName) -> int:
	var best := 0
	for uid in _own_uids(def_id):
		if best == 0 or _stack(uid).quantity > _stack(best).quantity:
			best = uid
	return best


func _stack(uid: int) -> InvStack:
	return net.replica.own.get_stack(uid)


## Cuántas unidades de cada tipo hay en total: mundo, jugadores y cajas.
func _totals() -> Dictionary:
	var totals := {}
	for uid in net.authority.world:
		var stack: InvStack = net.authority.world[uid]["stack"]
		totals[stack.def_id] = totals.get(stack.def_id, 0) + stack.quantity
	var grids: Array = []
	for node in lab.get_node("Actors").get_children():
		var inventory := node.get_node_or_null("Inventario") as InvInventory
		if inventory != null and inventory.grid != null:
			grids.append(inventory.grid)
	for id in net.authority.containers:
		var box: InvContainer = net.authority.containers[id]
		if is_instance_valid(box):
			grids.append(box.inventory.grid)
	for grid: InvGrid in grids:
		for uid in grid.stacks:
			totals[grid.stacks[uid].def_id] = totals.get(grid.stacks[uid].def_id, 0) + grid.stacks[uid].quantity
	return totals


func _free_cell(foot := Vector2i.ONE, skip := 0) -> Vector2i:
	var grid := net.replica.own
	for y in grid.rows:
		for x in grid.columns:
			if grid.fits(foot, Vector2i(x, y)):
				if skip == 0:
					return Vector2i(x, y)
				skip -= 1
	return Vector2i(-1, -1)


## A qué va un clic con lo que está en la mano, con el mouse donde está.
func _target() -> Dictionary:
	return ui._drop_target(ui._hold, ui._mouse, "all", true)


## El centro de una celda de la grilla propia, en pantalla.
func _cell_center(cell: Vector2i) -> Vector2:
	return ui._grid_rect(0).position + (Vector2(cell) + Vector2(0.5, 0.5)) * ui._cs


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


# --- 3. Recoger -------------------------------------------------------------------

func _pickups() -> void:
	var screws := _world_uids(&"tornillos")
	await _teleport(Vector3(20, 0, 20))
	var far := await _req(Op.PICKUP, [screws[0]], [screws[0]])
	_check(not far[0] and far[1].begins_with("estás muy lejos"), "lejos no se recoge: %s" % far[1])
	await _teleport(ZONE + Vector3(-2, 0, -4.4))
	var first := await _req(Op.PICKUP, [screws[0]], [screws[0]])
	_check(first[0] and _stack(screws[0]) != null and _stack(screws[0]).quantity == 20, "20 tornillos, con el id que tenían en el mundo")
	var second := await _req(Op.PICKUP, [screws[1]], [screws[1]])
	_check(second[0] and _stack(screws[0]).quantity == 30 and _stack(screws[1]) != null and _stack(screws[1]).quantity == 10,
			"los otros 20: 10 completan la pila y 10 quedan en una pila nueva con su id")
	_check(not net.replica.world.has(screws[0]) and not net.replica.world.has(screws[1]), "los tornillos ya no están en el mundo")
	for def_id in [&"bateria", &"granada"]:
		for uid in _world_uids(def_id):
			await _teleport(net.replica.world[uid]["pos"] + Vector3(-1, 0, 0))
			var got := await _req(Op.PICKUP, [uid], [uid])
			_check(got[0], "recoger %s: %s" % [def_id, got[1]])
	var batteries := _own_uids(&"bateria")
	_check(batteries.size() == 2 and _stack(batteries[0]).quantity == 2 and _stack(batteries[1]).quantity == 2,
			"las baterías de carga 100 y de carga 40 quedan en dos pilas")
	var grenades := _own_uids(&"granada")
	_check(grenades.size() == 2 and _stack(grenades[0]).quantity + _stack(grenades[1]).quantity == 5 and _stack(grenades[0]).quantity == 4,
			"granadas 3 + 2 con pilas de 4: una llena y otra con 1")


# --- 2. Pilas y división -------------------------------------------------------------

func _stacks_and_split() -> void:
	var screws := _own_uids(&"tornillos")
	var full: InvStack = _stack(screws[0])
	var rest: InvStack = _stack(screws[1])
	var r := await _req(Op.MERGE, [0, rest.uid, rest.ver, 0, full.uid, rest.quantity], [rest.uid, full.uid])
	_check(not r[0] and r[1].begins_with("esa pila ya está llena"), "sobre una pila llena: %s" % r[1])
	var batteries := _own_uids(&"bateria")
	var a: InvStack = _stack(batteries[0])
	var b: InvStack = _stack(batteries[1])
	r = await _req(Op.MERGE, [0, b.uid, b.ver, 0, a.uid, b.quantity], [a.uid, b.uid])
	_check(not r[0] and r[1].begins_with("no se apilan: tienen distinto estado"), "distinta carga: %s" % r[1])
	var cell := _free_cell()
	for bad in [0, 30, -4, 99]:
		r = await _req(Op.SPLIT, [0, full.uid, full.ver, bad, 0, cell.x, cell.y, 0], [full.uid])
		_check(not r[0], "dividir %d de 30 se rechaza: %s" % [bad, r[1]])
	r = await _req(Op.SPLIT, [0, full.uid, full.ver, 5, 0, -1, 0, 0], [full.uid])
	_check(not r[0] and _stack(full.uid).quantity == 30, "dividir hacia afuera de la grilla se rechaza y no cambia nada")
	var before := _own_uids(&"tornillos")
	r = await _req(Op.SPLIT, [0, full.uid, full.ver, 5, 0, cell.x, cell.y, 0], [full.uid])
	var after := _own_uids(&"tornillos")
	_check(r[0] and after.size() == before.size() + 1 and _stack(full.uid).quantity == 25, "dividir 5: queda 25 y aparece una pila nueva")
	var stale := _stack(full.uid)
	r = await _req(Op.MOVE, [0, stale.uid, stale.ver - 1, 0, 11, 15, 0], [stale.uid])
	_check(not r[0] and r[1].begins_with("ese objeto cambió"), "un pedido sobre una versión vieja se rechaza: %s" % r[1])
	r = await _req(Op.MOVE, [0, stale.uid, stale.ver, -2, 0, 0, 0], [stale.uid])
	_check(not r[0] and r[1] == "no podés tocar el inventario de otro jugador", "el inventario de otro: %s" % r[1])


# --- 6. Barra rápida, uso y pedidos repetidos ---------------------------------------------

func _hotbar_use_and_dedup() -> void:
	for uid in _world_uids(&"botella"):
		await _teleport(net.replica.world[uid]["pos"] + Vector3(-1, 0, 0))
		var got := await _req(Op.PICKUP, [uid], [uid])
		_check(got[0], "recoger botellas: %s" % got[1])
	var bottles := _own_uids(&"botella")
	_check(bottles.size() == 1 and _stack(bottles[0]).quantity == 3, "2 + 1 botellas en una pila de 3")
	var bottle: int = bottles[0]
	var r := await _req(Op.HOTBAR_SET, [0, bottle])
	_check(r[0] and net.replica.loadout.hotbar[0] == bottle, "la botella al acceso 1")
	# La botella cura 25 de salud (hasta el 2026-11-01 subía la vitalidad de
	# prueba). Con la salud completa no se usaría: se la baja a 40.
	var me := net.authority.actor_of(1)
	me.state.health = 40 * ActorState.HEALTH_UNIT
	# El mismo pedido dos veces (como un reintento): se usa una sola botella.
	var seq := net.replica.request(Op.HOTBAR_PRESS, [0], [bottle], [0])
	net._send_request(seq, Op.HOTBAR_PRESS, [0])
	for i in 4:
		await get_tree().physics_frame
	_check(_stack(bottle).quantity == 2 and me.state.health == 65 * ActorState.HEALTH_UNIT,
			"un pedido repetido no gasta dos veces ni cura dos veces: quedan %d, salud %.1f" % [_stack(bottle).quantity, me.state.health / float(ActorState.HEALTH_UNIT)])
	_check(net.authority.repeated >= 1, "el host vio el repetido")
	me.state.health = lab.tuning.health_max * ActorState.HEALTH_UNIT
	r = await _req(Op.USE, [bottle, _stack(bottle).ver], [bottle])
	_check(not r[0] and r[1] == "ya tenés la salud completa" and _stack(bottle).quantity == 2,
			"con la salud completa no se usa ni se gasta: %s" % r[1])
	me.state.health = 40 * ActorState.HEALTH_UNIT
	await _req(Op.HOTBAR_PRESS, [0], [bottle])
	await _req(Op.HOTBAR_PRESS, [0], [bottle])
	_check(not net.replica.own.has(bottle) and net.replica.loadout.hotbar[0] == 0,
			"gastada la última, la pila se retira y su acceso se limpia")
	_check(me.state.health == 90 * ActorState.HEALTH_UNIT, "salud 40 + 25 + 25 = 90 (hay %.1f)" % (me.state.health / float(ActorState.HEALTH_UNIT)))
	r = await _req(Op.HOTBAR_PRESS, [0])
	_check(not r[0] and r[1].begins_with("el acceso 1 está vacío"), "el acceso vacío no busca otra botella: %s" % r[1])
	var screws := _own_uids(&"tornillos")
	await _req(Op.HOTBAR_SET, [2, screws[0]])
	var keep := _stack(screws[0])
	r = await _req(Op.MOVE, [0, keep.uid, keep.ver, 0, 11, 15, 0], [keep.uid])
	_check(r[0] and net.replica.loadout.hotbar[2] == keep.uid, "mover conserva el acceso")
	var donor := _stack(screws[1])
	var target := _stack(screws[0])
	r = await _req(Op.MERGE, [0, donor.uid, donor.ver, 0, target.uid, donor.quantity], [donor.uid, target.uid])
	_check(r[0] and net.replica.loadout.hotbar[2] == target.uid, "apilar sobre la del acceso: el destino conserva id y acceso")
	r = await _req(Op.HOTBAR_SWAP, [2, 7])
	_check(r[0] and net.replica.loadout.hotbar[7] == target.uid and net.replica.loadout.hotbar[2] == 0, "reorganizar: del 3 al 8")


# --- 9. Equipar, soltar ----------------------------------------------------------------

func _equip_and_drop() -> void:
	for def_id in [&"machete", &"linterna", &"llave", &"banquito", &"caja_de_herramientas"]:
		var uid: int = _world_uids(def_id)[0]
		await _teleport(net.replica.world[uid]["pos"] + Vector3(-1, 0, 0))
		var got := await _req(Op.PICKUP, [uid], [uid])
		_check(got[0], "recoger %s: %s" % [def_id, got[1]])
	var machete: int = _own_uids(&"machete")[0]
	var torch: int = _own_uids(&"linterna")[0]
	var r := await _req(Op.EQUIP, [machete, _stack(machete).ver], [machete])
	_check(r[0] and net.replica.loadout.equipped_uid == machete and net.replica.equipment.get(1, "") == "machete",
			"equipar el machete: lo ven todos")
	await get_tree().process_frame
	var view := actor.visual_root().get_node_or_null("Equipado") as InvEquipView
	_check(view != null and view.equipped_id() == &"machete", "el personaje muestra el machete")
	_check(net.replica.own.has(machete), "equipado sigue en la grilla")
	await _req(Op.HOTBAR_SET, [1, torch])
	r = await _req(Op.HOTBAR_PRESS, [1], [torch])
	_check(r[0] and net.replica.loadout.equipped_uid == torch and net.replica.equipment.get(1, "") == "linterna",
			"el acceso 2 equipa la linterna y reemplaza al machete")
	var cell := _free_cell(Vector2i(2, 1))
	r = await _req(Op.MOVE, [0, torch, _stack(torch).ver, 0, cell.x, cell.y, 1], [torch])
	_check(r[0] and net.replica.loadout.equipped_uid == torch and net.replica.loadout.hotbar[1] == torch,
			"mover y girar lo equipado: sigue equipado y en su acceso")
	await _teleport(ZONE + Vector3(-5, 0, 4), 0.0)
	r = await _req(Op.DROP, [0, torch, _stack(torch).ver, 1], [torch])
	_check(r[0] and net.replica.world.has(torch) and not net.replica.own.has(torch), "soltar la linterna: va al mundo con su id")
	_check(net.replica.loadout.equipped_uid == 0 and net.replica.loadout.hotbar[1] == 0 and net.replica.equipment.get(1, "x") == "",
			"soltarla la desequipa y limpia su acceso")
	if net.replica.world.has(torch):
		var spot: Vector3 = net.replica.world[torch]["pos"]
		var feet := BaseRegistry.world_position(actor.state)
		_check(absf(spot.y) < 0.01 and Vector2(spot.x - feet.x, spot.z - feet.z).length() >= 0.6,
				"cae en el piso, afuera del personaje: %s (pies en %s)" % [spot, feet])
		await get_tree().process_frame
		_check(net.world_view(torch) != null, "se ve en el mundo")
	var screws := _biggest(&"tornillos")
	var before := _stack(screws).quantity
	r = await _req(Op.DROP, [0, screws, _stack(screws).ver, 7], [screws])
	var dropped := _world_uids(&"tornillos")
	_check(r[0] and _stack(screws).quantity == before - 7 and dropped.size() == 1 and dropped[0] != screws
			and net.replica.world[dropped[0]]["stack"].quantity == 7, "soltar 7: van al mundo con un id nuevo y la pila conserva el suyo")
	r = await _req(Op.DROP, [0, screws, _stack(screws).ver, 999], [screws])
	_check(not r[0] and _stack(screws).quantity == before - 7, "soltar más de lo que hay se rechaza: %s" % r[1])
	r = await _req(Op.PICKUP, [dropped[0]], [dropped[0]])
	_check(r[0], "lo soltado se vuelve a recoger")


func _drop_near_wall_and_cage() -> void:
	# Mirando la pared de la zona a medio metro: no cae del otro lado.
	var wall_x := ZONE.x + 5.0 - 0.15
	await _teleport(Vector3(wall_x - 0.6, 0, ZONE.z - 3.0), -PI / 2.0)
	var key: int = _own_uids(&"llave")[0]
	var r := await _req(Op.DROP, [0, key, _stack(key).ver, 1], [key])
	_check(r[0] and net.replica.world.has(key) and net.replica.world[key]["pos"].x < wall_x - 0.2,
			"contra la pared cae de este lado: %s" % (net.replica.world[key]["pos"] if net.replica.world.has(key) else r[1]))
	r = await _req(Op.PICKUP, [key], [key])
	_check(r[0], "la llave se vuelve a recoger")
	# Encerrado entre paredes: no hay lugar y no se suelta nada.
	await _teleport(ZONE + Vector3(-4, 0, -6))
	var cage := Node3D.new()
	add_child(cage)
	for side in [Vector3(0.6, 1, 0), Vector3(-0.6, 1, 0), Vector3(0, 1, 0.6), Vector3(0, 1, -0.6)]:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.1 if side.x != 0.0 else 1.4, 2.0, 0.1 if side.z != 0.0 else 1.4)
		shape.shape = box
		body.add_child(shape)
		body.position = BaseRegistry.world_position(actor.state) + side
		cage.add_child(body)
	for i in 3:
		await get_tree().physics_frame
	key = _own_uids(&"llave")[0]
	r = await _req(Op.DROP, [0, key, _stack(key).ver, 1], [key])
	_check(not r[0] and r[1] == "no hay lugar cerca para soltarlo" and net.replica.own.has(key), "encerrado no se suelta: %s" % r[1])
	cage.queue_free()
	for i in 3:
		await get_tree().physics_frame


# --- 7. Cajas -------------------------------------------------------------------------

func _containers() -> void:
	var crate := net.container(1)
	var small := net.container(2)
	_check(crate != null and crate.display_name == "Caja compartida" and small != null, "las dos cajas están numeradas")
	await _teleport(crate.global_position + Vector3(-4, 0, 0))
	var r := await _req(Op.OPEN, [1])
	_check(not r[0] and r[1] == "estás muy lejos de la caja", "lejos no se abre: %s" % r[1])
	await _teleport(crate.global_position + Vector3(-1.2, 0, 0))
	r = await _req(Op.OPEN, [1])
	_check(r[0] and net.replica.box_id == 1 and net.replica.box != null and net.replica.box.columns == 8, "cerca se abre: %s" % r[1])
	var bench: int = _own_uids(&"banquito")[0]
	r = await _req(Op.MOVE, [0, bench, _stack(bench).ver, 1, 0, 0, 1], [bench])
	_check(r[0] and net.replica.box.has(bench) and not net.replica.own.has(bench)
			and net.replica.box.rect_of(bench) == Rect2i(0, 0, 3, 2), "el banquito a la caja, girado 90° (3 × 2) y con su id")
	var screws: int = _own_uids(&"tornillos")[0]
	await _req(Op.HOTBAR_SET, [4, screws])
	r = await _req(Op.MOVE, [0, screws, _stack(screws).ver, 1, 4, 0, 3], [screws])
	_check(r[0] and net.replica.box.placement(screws).rot == 3 and net.replica.loadout.hotbar[4] == 0,
			"a la caja girado 270°; su acceso se limpia")
	r = await _req(Op.MOVE, [1, screws, net.replica.box.get_stack(screws).ver, 1, 4, 0, 4], [screws])
	_check(not r[0] and r[1] == "giro inválido", "un giro de más de 3 se rechaza: %s" % r[1])
	# Soltar al piso directo desde la caja, sin pasar por el inventario.
	var loose_before := _world_uids(&"tornillos").size()
	var box_screws: InvStack = net.replica.box.get_stack(screws)
	var box_quantity := box_screws.quantity
	r = await _req(Op.DROP, [1, screws, box_screws.ver, 2], [screws])
	var loose := _world_uids(&"tornillos")
	_check(r[0] and net.replica.box.get_stack(screws).quantity == box_quantity - 2 and loose.size() == loose_before + 1
			and net.replica.world[loose[-1]]["stack"].quantity == 2, "soltar 2 desde la caja: van al piso y la caja se queda con el resto")
	var in_box: InvStack = net.replica.box.get_stack(screws)
	var back := _free_cell()
	r = await _req(Op.MOVE, [1, screws, in_box.ver, 0, back.x, back.y, 0], [screws])
	_check(r[0] and net.replica.own.has(screws) and not net.replica.box.has(screws), "de la caja al inventario")
	r = await _req(Op.MOVE, [0, screws, _stack(screws).ver, 2, 0, 0, 0], [screws])
	_check(not r[0] and r[1] == "no tenés esa caja abierta", "otra caja que no está abierta: %s" % r[1])
	# El cajón chico (4 × 3) no tiene lugar para el banquito acostado: no queda a medias.
	await _teleport(small.global_position + Vector3(-1.0, 0, 0))
	r = await _req(Op.OPEN, [2])
	_check(r[0] and net.replica.box_id == 2, "abrir el cajón chico cierra la caja grande")
	var tools: int = _own_uids(&"caja_de_herramientas")[0]
	var own_before := var_to_str(net.replica.own.snapshot())
	var box_before := var_to_str(net.replica.box.snapshot())
	r = await _req(Op.MOVE, [0, tools, _stack(tools).ver, 2, 2, 0, 0], [tools])
	_check(not r[0] and var_to_str(net.replica.own.snapshot()) == own_before and var_to_str(net.replica.box.snapshot()) == box_before,
			"una transferencia que no entra no cambia ninguno de los dos: %s" % r[1])
	r = await _req(Op.MOVE, [0, tools, _stack(tools).ver, 2, 0, 0, 0], [tools])
	_check(r[0] and net.replica.box.has(tools), "en (1, 1) sí entra")
	# Al alejarse, se cierra sola.
	var closed := []
	var on_closed := func(id: int, reason: String) -> void: closed.append([id, reason])
	net.container_closed.connect(on_closed)
	await _teleport(small.global_position + Vector3(-6, 0, 0))
	for i in 4:
		await get_tree().physics_frame
	net.container_closed.disconnect(on_closed)
	_check(closed.size() == 1 and closed[0][1] == "te alejaste de la caja" and net.replica.box == null, "alejarse la cierra: %s" % [closed])
	r = await _req(Op.MOVE, [2, tools, 0, 0, 0, 0, 0], [tools])
	_check(not r[0], "con la caja cerrada no se opera: %s" % r[1])


# --- 4. Dos jugadores sobre la misma pila ------------------------------------------------

func _two_players() -> void:
	var crate := net.container(1)
	var other: ActorBody = load("res://scenes/actor/actor.tscn").instantiate()
	other.name = "Actor2"
	other.owner_peer_id = 2
	other.state.position = crate.global_position + Vector3(0, 0, 1.2)
	other.state.mode = ActorState.Mode.GROUND
	other.state.on_floor = true
	other.position = other.state.position
	lab.get_node("Actors").add_child(other)
	var send: Callable = net.authority.send
	net.authority.send = func(peer: int, payload: Dictionary) -> void:
		if peer == 2:
			_peer2_payloads.append(payload)
		else:
			send.call(peer, payload)
	for i in 3:
		await get_tree().physics_frame
	net.test_peers[2] = true
	net.authority.welcome(2)
	_check(not _peer2_payloads.is_empty() and _peer2_payloads[-1].has("world") and _peer2_payloads[-1].has("own"),
			"el segundo jugador recibe el mundo y su inventario al entrar")
	_check(not _peer2_payloads[-1].has("box") and not _peer2_payloads[-1].get("own", [0, 0, 0, []])[3].size(),
			"no recibe la caja (no la abrió) y su inventario está vacío")
	await _teleport(crate.global_position + Vector3(-1.2, 0, 0))
	await _req(Op.OPEN, [1])
	await _peer2(Op.OPEN, [1])
	var grenades := _own_uids(&"granada")
	var g: InvStack = _stack(grenades[0])
	var r := await _req(Op.MOVE, [0, g.uid, g.ver, 1, 6, 6, 0], [g.uid])
	_check(r[0] and net.replica.box.has(g.uid), "granadas a la caja compartida")
	var last_box: Array = _last_peer2("box")
	_check(not last_box.is_empty() and last_box[0] == 1 and _box_has(last_box[1], g.uid), "el otro jugador ve las granadas en la caja")
	var shared: InvStack = net.replica.box.get_stack(g.uid)
	# Los dos tiran del mismo objeto a la vez: entra uno solo.
	var mine := net.replica.request(Op.MOVE, [1, g.uid, shared.ver, 0, 0, 15, 0], [g.uid])
	_peer2_seq += 1
	net._inbox.append([2, _peer2_seq, Op.MOVE, [1, g.uid, shared.ver, 0, 0, 0, 0]])
	for i in 4:
		await get_tree().physics_frame
	var theirs := _result_peer2(_peer2_seq)
	_check(_answers.get(mine, [false])[0] and not theirs.is_empty() and not theirs[1],
			"el primero en la fila se lo lleva y el segundo se rechaza: %s" % [theirs])
	var other_inventory := net.authority.player_inventory(2)
	_check(other_inventory != null and not other_inventory.grid.has(g.uid) and net.replica.own.has(g.uid), "las granadas están en un solo lugar")
	# Un objeto del mundo que agarran los dos: uno solo.
	var key: int = _own_uids(&"llave")[0]
	await _req(Op.DROP, [0, key, _stack(key).ver, 1], [key])
	var spot: Vector3 = net.replica.world[key]["pos"]
	other.state.position = spot + Vector3(0.8, 0, 0)
	other.apply_state(other.state)
	_peer2_seq += 1
	net._inbox.append([2, _peer2_seq, Op.PICKUP, [key]])
	var late := net.replica.request(Op.PICKUP, [key], [key])
	for i in 4:
		await get_tree().physics_frame
	_check(_result_peer2(_peer2_seq)[1] and not _answers.get(late, [true])[0] and other_inventory.grid.has(key),
			"del mundo también: uno solo se la lleva (%s)" % [_answers.get(late)])
	_check(not net.replica.world.has(key) and not net.replica.own.has(key), "y no queda en dos lugares")
	# El segundo jugador intenta tocar la caja estando lejos.
	other.state.position = crate.global_position + Vector3(0, 0, 6)
	other.apply_state(other.state)
	_peer2_seq += 1
	net._inbox.append([2, _peer2_seq, Op.MOVE, [0, key, other_inventory.grid.get_stack(key).ver, 1, 0, 7, 0]])
	for i in 4:
		await get_tree().physics_frame
	var result := _result_peer2(_peer2_seq)
	_check(not result.is_empty() and not result[1], "lejos de la caja, el otro no la opera: %s" % [result])
	# Se desconecta: se olvida todo lo suyo en el host, sin tocar lo confirmado.
	net.test_peers.erase(2)
	for i in 2:
		await get_tree().physics_frame
	_check(net.authority.open_container_of(2) == 0 and not net.authority.is_welcomed(2), "desconectado: sin suscripciones")
	other.queue_free()
	net.authority.send = send
	for i in 3:
		await get_tree().physics_frame


func _peer2(op: int, args: Array) -> Array:
	_peer2_seq += 1
	net._inbox.append([2, _peer2_seq, op, args])
	for i in 4:
		await get_tree().physics_frame
	return _result_peer2(_peer2_seq)


func _result_peer2(seq: int) -> Array:
	for payload in _peer2_payloads:
		for result in payload.get("r", []):
			if result[0] == seq:
				return result
	return []


func _last_peer2(key: String) -> Variant:
	for i in range(_peer2_payloads.size() - 1, -1, -1):
		if _peer2_payloads[i].has(key):
			return _peer2_payloads[i][key]
	return []


func _box_has(snapshot: Array, uid: int) -> bool:
	for item in snapshot[3]:
		if item[0][0] == uid:
			return true
	return false


# --- 10. Entradas, arrastre y Esc ------------------------------------------------------------

func _ui_rules() -> void:
	ui.size = Vector2(1600, 900)
	var camera: LabCamera = lab.get_node("CameraRig")
	ui.open()
	_check(ui.is_open and not camera._mouse_holders.is_empty(), "abrir el inventario suelta el mouse para la interfaz")
	Input.action_press("move_forward")
	var input: ActorInput = lab._local_input(1)
	_check(input.move.y > 0.9, "con el inventario abierto, W sigue moviendo al personaje")
	ui._layout()
	var screws: int = _own_uids(&"tornillos")[0]
	ui._mouse = ui._item_rect(0, screws).get_center()
	ui._open_dialog("split", 0, screws)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(ui.is_typing(), "con el diálogo abierto, el campo de cantidad tiene el foco")
	input = lab._local_input(2)
	_check(input.move == Vector2.ZERO, "escribiendo una cantidad, W no mueve al personaje")
	Input.action_release("move_forward")
	ui._spin.get_line_edit().text = "abc"
	ui._accept_dialog()
	_check(ui._dialog.visible and ui._dialog_error.text != "", "una cantidad que no es un número no se acepta")
	_check(ui._escape() and not ui._dialog.visible and ui.is_open, "Esc cierra primero el diálogo")
	# En la mano: R gira de a 90° alrededor del centro de la celda agarrada, no
	# del punto del clic; cuatro veces vuelve.
	var torch_world := _world_uids(&"linterna")
	_check(torch_world.size() == 1, "la linterna sigue en el piso")
	var machete: int = _own_uids(&"machete")[0]
	var machete_name: String = net.replica.own.def_of(machete).display_name
	var rect := ui._item_rect(0, machete)
	ui._mouse = rect.position + Vector2(5, ui._cs * 2.9)
	ui._left_press()
	_check(ui._mode == InvUI.Mode.HOLD and net.replica.pending.is_empty(), "un clic agarra el machete, sin pedir nada")
	_check(ui._hold["grab"] == Vector2i(0, 2), "se agarró por la celda de abajo: %s" % ui._hold["grab"])
	_check(ui._grab_offset(ui._hold).is_equal_approx(Vector2(0.5, 2.5) * ui._cs),
			"el cursor queda en el centro de esa celda, no en la esquina donde se hizo clic")
	_check(ui._hover_name() == "", "con algo en la mano no se muestra el nombre de lo que está abajo")
	# Agarrado por abajo: girando en el sentido del reloj, esa punta va a la
	# izquierda, arriba, a la derecha y otra vez abajo.
	var turns := [[Vector2i(0, 0), Vector2i(3, 1), "90°, acostado, la punta a la izquierda"],
			[Vector2i(0, 0), Vector2i(1, 3), "180°, parado, la punta arriba"],
			[Vector2i(2, 0), Vector2i(3, 1), "270°, acostado, la punta a la derecha"],
			[Vector2i(0, 2), Vector2i(1, 3), "360°, como estaba"]]
	for i in turns.size():
		ui._rotate_held()
		var foot: Vector2i = ui._hold["def"].footprint(ui._hold["rot"])
		_check(ui._hold["rot"] == (i + 1) % 4 and ui._hold["grab"] == turns[i][0] and foot == turns[i][1],
				"R %d: %s (celda agarrada %s, %s)" % [i + 1, turns[i][2], ui._hold["grab"], foot])
	ui._rotate_held()
	var lying := _free_cell(Vector2i(3, 1))
	ui._mouse = _cell_center(lying) + Vector2(0.4, -0.4) * ui._cs
	var aimed := _target()
	_check(aimed["kind"] == "move" and aimed["cell"] == lying,
			"acostado, la celda agarrada va a la celda bajo el cursor, aunque el cursor esté cerca de su borde: %s" % [aimed])
	for i in 3:
		ui._rotate_held()
	ui._mouse = ui._slot_rect(5).get_center()
	_check(_target()["kind"] == "slot", "dejarlo sobre la barra lo asigna, no lo suelta al piso")
	ui._mouse = ui._panel_rect(0).position + Vector2(20, 10)
	_check(_target()["kind"] == "invalid", "sobre el encabezado del panel se rechaza")
	ui._mouse = Vector2(1300, 300)
	_check(_target()["kind"] == "world", "afuera de los paneles es soltar al piso")
	ui._menu.show()
	ui._menu.position = Vector2(1250, 250)
	ui._menu.size = Vector2(200, 200)
	_check(_target()["kind"] == "invalid", "sobre un menú se rechaza")
	ui._menu.hide()
	ui._mouse = ui._item_rect(0, machete).position + ui._grab_offset(ui._hold)
	_check(ui._hold["rot"] == 0 and _target()["kind"] == "move" and _target()["cell"] == net.replica.own.placement(machete).cell,
			"sobre su propio lugar no lo bloquea")
	_check(ui._escape() and ui._mode == InvUI.Mode.NONE and ui.is_open, "Esc suelta primero lo que está en la mano")
	_check(net.replica.own.has(machete) and net.replica.pending.is_empty(), "soltarlo con Esc no cambió nada ni dejó pedidos")
	# Con la mano vacía, el cursor sobre un objeto muestra su nombre.
	ui._mouse = ui._item_rect(0, machete).get_center()
	_check(ui._hover_name() == machete_name, "el cursor sobre el machete muestra su nombre: '%s'" % ui._hover_name())
	ui._mouse = _cell_center(_free_cell())
	_check(ui._hover_name() == "", "sobre una celda vacía, nada")
	for i in InvUI.KEYS.size():
		var in_slot: int = net.replica.loadout.hotbar[i]
		if in_slot != 0:
			ui._mouse = ui._slot_rect(i).get_center()
			_check(ui._hover_name() == net.replica.own.def_of(in_slot).display_name,
					"también sobre un acceso de la barra: '%s'" % ui._hover_name())
			break
	ui._mouse = ui._item_rect(0, machete).get_center()
	ui._open_menu(0, machete)
	_check(ui._menu.visible, "clic derecho abre el menú")
	_check(ui._hover_name() == "", "con el menú abierto no se muestra el nombre")
	_check(ui._escape() and not ui._menu.visible and ui.is_open, "Esc después cierra el menú")
	_check(ui._escape() and not ui.is_open and camera._mouse_holders.is_empty(), "y por último el inventario, devolviendo el mouse a la cámara")
	_check(not ui._escape(), "con todo cerrado, Esc sigue de largo (la cámara suelta el mouse)")


# --- Un clic agarra y otro deja; clic derecho de a una unidad ----------------------------------

func _hold_and_place() -> void:
	ui.size = Vector2(1600, 900)
	ui.open()
	ui._layout()
	var machete: int = _own_uids(&"machete")[0]
	var old_center := ui._item_rect(0, machete).get_center()
	ui._mouse = old_center
	ui._left_press()
	_check(not ui._shown(0, machete) and ui._item_at(old_center).is_empty(),
			"en la mano, su lugar queda vacío: no se dibuja ni se agarra ahí")
	var spot := _free_cell(Vector2i(1, 3))
	ui._mouse = ui._grid_rect(0).position + (Vector2(spot) + Vector2(0.5, 1.5)) * ui._cs
	ui._left_press()
	_check(ui._mode == InvUI.Mode.NONE, "otro clic lo deja: la mano queda vacía")
	_check(not net.replica.pending.is_empty() and not ui._shown(0, machete) and ui._hover_name() == "",
			"esperando al host, tampoco se ve en el lugar de antes")
	await _frames(4)
	_check(net.replica.own.placement(machete).cell == spot, "el machete quedó donde se hizo el segundo clic")
	_check(ui._shown(0, machete), "cuando contesta el host, se ve en el lugar nuevo")
	# Asignarlo a un acceso no lo saca de su lugar: se sigue viendo. Se usa un
	# acceso vacío y después se deja todo como estaba.
	var empty_slot := -1
	for i in InvUI.KEYS.size():
		if net.replica.loadout.hotbar[i] == 0:
			empty_slot = i
	var old_slot := net.replica.loadout.slot_of(machete)
	ui._mouse = ui._item_rect(0, machete).get_center()
	ui._left_press()
	ui._mouse = ui._slot_rect(empty_slot).get_center()
	ui._left_press()
	_check(empty_slot >= 0 and not net.replica.pending.is_empty() and ui._shown(0, machete),
			"asignado a un acceso y esperando al host, se sigue viendo en su lugar")
	await _frames(4)
	_check(net.replica.loadout.hotbar[empty_slot] == machete, "quedó en el acceso %s" % InvUI.KEYS[empty_slot])
	var r := await _req(Op.HOTBAR_SET, [old_slot, machete] if old_slot >= 0 else [empty_slot, 0])
	_check(r[0] and net.replica.loadout.slot_of(machete) == old_slot, "y vuelve a como estaba: %s" % r[1])
	# Un clic donde no se puede lo dice, y el objeto sigue en la mano.
	var screws := _biggest(&"tornillos")
	ui._mouse = ui._item_rect(0, machete).get_center()
	ui._left_press()
	ui._mouse = ui._item_rect(0, screws).get_center()
	ui._left_press()
	_check(ui._mode == InvUI.Mode.HOLD and ui.last_message().begins_with("No se apilan"),
			"sobre otro objeto no se deja y sigue en la mano: %s" % ui.last_message())
	ui._escape()
	# Clic derecho con la pila en la mano: deja de a una, y lo demás sigue en la mano.
	var total := net.replica.own.quantity_of(&"tornillos")
	var before := _stack(screws).quantity
	_check(before >= 6, "hay tornillos para repartir (%d)" % before)
	ui._mouse = ui._item_rect(0, screws).position + Vector2(ui._cs, ui._cs) * 0.5
	ui._left_press()
	var free := _free_cell()
	ui._mouse = _cell_center(free)
	for i in 3:
		ui._right_press()
	_check(ui._held_quantity(ui._hold) == before - 3, "en la mano quedan %d de %d" % [ui._held_quantity(ui._hold), before])
	await _frames(6)
	var placed := net.replica.own.uid_at(free)
	_check(placed != 0 and placed != screws and _stack(placed).quantity == 3 and _stack(screws).quantity == before - 3,
			"tres clics derechos seguidos: una pila nueva de 3, y quedan %d" % _stack(screws).quantity)
	_check(ui._mode == InvUI.Mode.HOLD and ui._hold["ver"] == _stack(screws).ver and ui._held_quantity(ui._hold) == before - 3,
			"lo que quedó sigue en la mano: el cambio propio no la soltó")
	ui._right_press()
	await _frames(4)
	_check(_stack(placed).quantity == 4 and _stack(screws).quantity == before - 4, "otro clic derecho sobre esa pila le suma una")
	var elsewhere := _free_cell()
	ui._mouse = _cell_center(elsewhere)
	ui._right_press()
	ui._right_press()
	await _frames(6)
	var second := net.replica.own.uid_at(elsewhere)
	_check(second != 0 and second != placed and _stack(second).quantity == 2, "dos clics derechos en otro lugar: otra pila de 2")
	ui._mouse = ui._item_rect(0, screws).get_center()
	ui._right_press()
	_check(ui._placing.is_empty() and ui._flight.is_empty() and ui.last_message().begins_with("Ahí está lo que tenés en la mano"),
			"sobre su propio lugar el clic derecho no deja nada: %s" % ui.last_message())
	ui._mouse = ui._item_rect(0, screws).position + ui._grab_offset(ui._hold)
	ui._left_press()
	_check(ui._mode == InvUI.Mode.NONE and net.replica.pending.is_empty(), "un clic en su lugar lo devuelve, sin pedir nada")
	_check(net.replica.own.quantity_of(&"tornillos") == total, "no se perdió ni se duplicó ningún tornillo")
	# Con la última unidad la mano queda vacía: los 4 pasan, de a uno, a otro lugar.
	ui._mouse = ui._item_rect(0, placed).get_center()
	ui._left_press()
	var last := _free_cell()
	ui._mouse = _cell_center(last)
	for i in 4:
		ui._right_press()
	_check(ui._mode == InvUI.Mode.NONE, "con la cuarta, la mano queda vacía")
	await _frames(8)
	var moved := net.replica.own.uid_at(last)
	_check(moved != 0 and _stack(moved).quantity == 4 and not net.replica.own.has(placed), "los 4 quedaron juntos en el lugar nuevo")
	_check(net.replica.own.quantity_of(&"tornillos") == total and ui._placing.is_empty() and ui._flight.is_empty(),
			"y sigue el mismo total, sin nada en fila")
	ui.close()


# --- 9. Mirar para recoger y abrir ----------------------------------------------------------------

func _look_and_reach() -> void:
	await _teleport(ZONE + Vector3(-4, 0, 4), 0.0)
	var grenade: int = _own_uids(&"granada")[0]
	var r := await _req(Op.DROP, [0, grenade, _stack(grenade).ver, 1], [grenade])
	var on_floor := _world_uids(&"granada")
	_check(r[0] and on_floor.size() == 1, "una granada al piso para mirarla: %s" % r[1])
	var dropped: int = on_floor[-1] if not on_floor.is_empty() else 0
	var spot: Vector3 = net.replica.world[dropped]["pos"] if dropped != 0 else Vector3.ZERO
	var eyes := InvAuthority.eyes(actor, actor.global_position)
	var aim := (spot + Vector3.UP * 0.1 - eyes).normalized()
	var seen := net.interaction_target(actor, eyes, aim, false)
	_check(seen.get("kind", "") == "item" and seen.get("id", 0) == dropped, "mirándola se elige: %s" % [seen])
	_check(net.interaction_target(actor, eyes, -aim, false).is_empty(), "mirando para el otro lado no se elige nada")
	_check(net.interaction_target(actor, eyes, aim.rotated(Vector3.UP, deg_to_rad(40.0)), false).is_empty(),
			"mirando 40° al costado tampoco")
	actor.state.facing_yaw = PI
	_check(net.interaction_target(actor, eyes, aim, true).is_empty(),
			"en tercera persona, de espaldas a la granada, no se elige aunque la cámara la vea")
	_check(not net.interaction_target(actor, eyes, aim, false).is_empty(), "en primera persona sí: la cámara es la vista")
	actor.state.facing_yaw = 0.0
	_check(not net.interaction_target(actor, eyes, aim, true).is_empty(), "en tercera persona, de frente, sí")
	# Una pared entre los ojos y la granada: no se elige, y el host no deja recogerla.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(1.4, 2.4, 0.1)
	shape.shape = slab
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = actor.global_position.lerp(spot, 0.5) + Vector3.UP * 1.2
	await _frames(3)
	_check(net.interaction_target(actor, eyes, aim, false).is_empty(), "con una pared en el medio no se elige")
	r = await _req(Op.PICKUP, [dropped], [dropped])
	_check(not r[0] and r[1].begins_with("no lo ves desde ahí"), "y el host no deja recogerla: %s" % r[1])
	wall.queue_free()
	await _frames(3)
	r = await _req(Op.PICKUP, [dropped], [dropped])
	_check(r[0], "sin la pared se recoge: %s" % r[1])
	# La caja: de frente se elige; de espaldas, en tercera persona, no.
	var crate := net.container(1)
	await _teleport(crate.global_position + Vector3(-1.2, 0, 0), -PI / 2.0)
	eyes = InvAuthority.eyes(actor, actor.global_position)
	var at_box := (crate.center() - eyes).normalized()
	seen = net.interaction_target(actor, eyes, at_box, true)
	_check(seen.get("kind", "") == "box" and seen.get("id", 0) == 1, "mirando la caja de frente se elige: %s" % [seen])
	actor.state.facing_yaw = PI / 2.0
	_check(net.interaction_target(actor, eyes, at_box, true).is_empty(), "de espaldas a la caja, en tercera persona, no")
	actor.state.facing_yaw = -PI / 2.0
	# La mira de la cámara arranca a la altura de la cabeza, no en la cámara.
	var camera: LabCamera = lab.get_node("CameraRig")
	await get_tree().process_frame
	var ray := camera.aim_ray()
	var from: Vector3 = ray[0]
	_check(from.distance_to(camera.global_position) < 1.0, "la mira arranca a la altura de la cabeza: a %.2f m del centro de la cámara" % [
			from.distance_to(camera.global_position)])


# --- E abre la caja y también la cierra ------------------------------------------------------

func _e_closes_box() -> void:
	var crate := net.container(1)
	await _teleport(crate.global_position + Vector3(-1.2, 0, 0), -PI / 2.0)
	var e_key := InputEventKey.new()
	e_key.physical_keycode = KEY_E
	e_key.pressed = true
	ui.open()
	var r := await _req(Op.OPEN, [1])
	_check(r[0] and net.replica.box_id == 1 and ui.is_open, "la caja abierta, con el inventario: %s" % r[1])
	ui._unhandled_key_input(e_key)
	_check(not ui.is_open and net.replica.box_id == 0, "E la cierra, junto con el inventario")
	await _frames(4)
	_check(net.authority.open_container_of(1) == 0, "y el host la da por cerrada")
	# Abierto con Tab y sin caja, E no cierra el inventario.
	ui.open()
	ui._unhandled_key_input(e_key)
	_check(ui.is_open, "con el inventario abierto con Tab y sin caja, E no lo cierra")
	ui.close()
	# E otra vez antes de que conteste el host: se cierra igual, y la caja no
	# queda abierta cuando llega.
	ui.open()
	var seq := net.replica.request(Op.OPEN, [1])
	ui._sent[seq] = {"op": Op.OPEN, "name": crate.display_name}
	_check(net.replica.is_op_pending(Op.OPEN), "la caja está pedida y el host todavía no contestó")
	ui._unhandled_key_input(e_key)
	_check(not ui.is_open, "E con la caja pedida cierra el inventario")
	await _frames(6)
	_check(_answers.has(seq) and _answers[seq][0], "el host la abrió: %s" % [_answers.get(seq, [])])
	_check(net.replica.box_id == 0 and net.replica.box == null, "cuando llega, no se muestra")
	await _frames(4)
	_check(net.authority.open_container_of(1) == 0, "y el host la cierra")


# --- 7. La caja desaparece con alguien operando -------------------------------------------

func _container_disappears() -> void:
	var crate := net.container(1)
	await _teleport(crate.global_position + Vector3(-1.2, 0, 0))
	ui.open()
	var r := await _req(Op.OPEN, [1])
	_check(r[0] and net.replica.box_id == 1, "la caja abierta otra vez")
	ui._layout()
	var uid: int = net.replica.box.sorted_uids()[0]
	ui._mouse = ui._item_rect(1, uid).get_center()
	ui._left_press()
	_check(ui._mode == InvUI.Mode.HOLD, "con algo de la caja en la mano")
	ui._mouse = Vector2(1300, 300)
	_check(_target()["kind"] == "world", "lo de la caja también se suelta al piso, afuera de los paneles")
	ui._mouse = ui._slot_rect(2).get_center()
	_check(_target()["kind"] == "invalid", "pero a la barra solo va lo del inventario propio")
	var lost := _totals()
	crate.get_parent().remove_child(crate)
	for i in 4:
		await get_tree().physics_frame
	_check(ui._mode == InvUI.Mode.NONE and net.replica.box == null and net.authority.open_container_of(1) == 0,
			"la caja desaparece: se cierra el panel y se suelta lo que estaba en la mano")
	_check(net.replica.pending.is_empty(), "sin pedidos colgados")
	var after := _totals()
	_check(after.get(&"banquito", 0) == lost.get(&"banquito", 0) - 1, "lo que tenía adentro se fue con ella (el banquito)")
	crate.queue_free()
	ui.close()
