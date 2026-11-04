extends Node

## Segunda parte de la prueba del panel Objetos: lo que creó
## prueba_del_creador.gd en la copia del proyecto, jugando. Arranca net_lab
## jugando solo y pide todo por el camino real del host, con un segundo
## jugador simulado en el host (como inv_lab_test). Sin lo creado por la
## primera parte, falla: se corre solo en esa copia.
##
## --headless --fixed-fps 60 --scene res://addons/inventario_objetos/pruebas/prueba_del_creador_juego.tscn

const Op := InvProtocol.Op

var lab: Node3D
var net: InvNet
var actor: ActorBody
var other: ActorBody
var _answers := {}
var _checks := 0
var _failures := 0
var _peer2_payloads: Array = []
var _peer2_seq := 0


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[creador_juego] TIEMPO AGOTADO")
		get_tree().quit(2))
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	add_child(lab)
	net = lab.get_node("Inventario")
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	await get_tree().process_frame
	lab._start(0)
	for i in 120:
		await get_tree().physics_frame
		if net.replica.own != null and is_instance_valid(lab._local_actor):
			break
	actor = lab._local_actor
	_check(actor != null, "jugando solo")
	await _rope()
	await _thermos()
	await _poison()
	await _second_player()
	await _rope_in_hand()
	await _wardrobes()
	print("[creador_juego] %d comprobaciones, %d fallas" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- 1 y 2. La cuerda: 12 de a 5 ----------------------------------------------------------------

func _rope() -> void:
	var piles := _world_uids(&"cuerda_de_prueba")
	var amounts := piles.map(func(uid: int) -> int: return net.replica.world[uid]["stack"].quantity)
	amounts.sort()
	_check(amounts == [2, 5, 5], "la cuerda está en el piso en pilas de 5, 5 y 2: %s" % [amounts])
	for uid in piles:
		await _teleport(net.replica.world[uid]["pos"] + Vector3(-1, 0, 0))
		var got := await _req(Op.PICKUP, [uid], [uid])
		_check(got[0], "recoger cuerda: %s" % got[1])
	var mine := _own_uids(&"cuerda_de_prueba").map(func(uid: int) -> int: return net.replica.own.get_stack(uid).quantity)
	mine.sort()
	_check(mine == [2, 5, 5], "en el inventario, pilas de hasta 5 y las 12 unidades: %s" % [mine])
	_check(_world_uids(&"cuerda_de_prueba").is_empty(), "y ya no está en el piso")
	_check(net.replica.own.rect_of(_own_uids(&"cuerda_de_prueba")[0]).size == Vector2i(1, 3), "ocupa 1 × 3")


# --- 3. El termo: cura 7 de salud y recupera 3 de estamina ------------------------------------------

func _thermos() -> void:
	var uid: int = _world_uids(&"termo_de_cafe")[0]
	await _teleport(net.replica.world[uid]["pos"] + Vector3(-1, 0, 0))
	var got := await _req(Op.PICKUP, [uid], [uid])
	_check(got[0] and net.replica.own.get_stack(uid).quantity == 2, "recoger 2 termos: %s" % got[1])
	var me := net.authority.actor_of(1)
	const H := ActorState.HEALTH_UNIT
	me.state.health = 40 * H
	me.state.stamina = 100 * ActorPowers.STAMINA_UNIT
	var r := await _req(Op.USE, [uid, net.replica.own.get_stack(uid).ver], [uid])
	_check(r[0] and me.state.health == 47 * H and me.state.stamina == 103 * ActorPowers.STAMINA_UNIT
			and net.replica.own.get_stack(uid).quantity == 1,
			"usar uno: el host cura 7 (40 → %.1f), recupera 3 de estamina (100 → %.0f) y gasta uno (quedan %d)" % [me.state.health / float(H),
			me.state.stamina / float(ActorPowers.STAMINA_UNIT), net.replica.own.get_stack(uid).quantity])


# --- 3b. El veneno: quita 30, también con la salud completa ----------------------------------------

func _poison() -> void:
	var uid: int = _world_uids(&"veneno_de_prueba")[0]
	await _teleport(net.replica.world[uid]["pos"] + Vector3(-1, 0, 0))
	var got := await _req(Op.PICKUP, [uid], [uid])
	_check(got[0], "recoger el veneno: %s" % got[1])
	var me := net.authority.actor_of(1)
	const H := ActorState.HEALTH_UNIT
	me.state.health = 100 * H
	var r := await _req(Op.USE, [uid, net.replica.own.get_stack(uid).ver], [uid])
	_check(r[0] and me.state.health <= 70 * H and me.state.health > 68 * H and not net.replica.own.has(uid),
			"usarlo con la salud completa quita 30 de golpe (%.2f) y se gasta" % (me.state.health / float(H)))
	for i in 70:
		await get_tree().physics_frame
	_check(me.state.health == 60 * H, "y en un segundo, 10 más de a poco: %.3f" % (me.state.health / float(H)))


# --- 4. La soga en la mano del otro jugador ----------------------------------------------------------

func _second_player() -> void:
	other = load("res://scenes/actor/actor.tscn").instantiate()
	other.name = "Actor2"
	other.owner_peer_id = 2
	var soga: int = _world_uids(&"soga_de_prueba")[0]
	other.state.position = net.replica.world[soga]["pos"] + Vector3(1, 0, 0)
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


func _rope_in_hand() -> void:
	var soga: int = _world_uids(&"soga_de_prueba")[0]
	var got := await _peer2(Op.PICKUP, [soga])
	_check(not got.is_empty() and got[1], "el otro jugador recoge la soga: %s" % [got])
	var grid := net.authority.player_inventory(2).grid
	var r := await _peer2(Op.EQUIP, [soga, grid.get_stack(soga).ver])
	_check(not r.is_empty() and r[1], "y se la equipa: %s" % [r])
	for i in 3:
		await get_tree().physics_frame
	_check(net.replica.equipment.get(2, "") == "soga_de_prueba", "acá se sabe que el otro tiene la soga")
	var view := other.visual_root().get_node_or_null(NodePath(InvNet.EQUIP_NODE)) as InvEquipView
	_check(view != null and view.equipped_id() == &"soga_de_prueba", "y se ve en su personaje")
	if view != null and view._model != null:
		_check(view._model.position.is_equal_approx(Vector3(0.2, 1.1, -0.3)) and view._model.rotation_degrees.is_equal_approx(Vector3(0, 45, 0)),
				"con la posición y el giro que se le pusieron en el panel: %s %s" % [view._model.position, view._model.rotation_degrees])


# --- 6. Dos armarios: compartidos, pero cada uno con lo suyo ------------------------------------------

func _wardrobes() -> void:
	var boxes: Array[InvContainer] = []
	for box in net.containers():
		if box.display_name == "Armario de prueba":
			boxes.append(box)
	_check(boxes.size() == 2, "los dos armarios están en el mundo (%d)" % boxes.size())
	if boxes.size() != 2:
		return
	var a := boxes[0]
	var b := boxes[1]
	_check(a.columns == 4 and a.rows == 3 and a.inventory.grid != null and a.inventory.grid.columns == 4 and a.inventory.grid.rows == 3,
			"con los valores de la última edición: 4 × 3")
	_check(a.inventory != b.inventory and a.inventory.grid != b.inventory.grid, "cada uno con su propio inventario")
	await _teleport(a.global_position + Vector3(-1.0, 0, 0))
	var r := await _req(Op.OPEN, [a.container_id])
	_check(r[0] and net.replica.box_id == a.container_id, "abrir el primero: %s" % r[1])
	var rope: int = _own_uids(&"cuerda_de_prueba")[0]
	r = await _req(Op.MOVE, [0, rope, net.replica.own.get_stack(rope).ver, a.container_id, 0, 0, 1], [rope])
	_check(r[0] and net.replica.box.has(rope), "una cuerda adentro, acostada (3 × 1 en 4 columnas): %s" % r[1])
	other.state.position = a.global_position + Vector3(0, 0, 0.9)
	other.apply_state(other.state)
	var theirs := await _peer2(Op.OPEN, [a.container_id])
	var seen: Array = _last_peer2("box")
	_check(not theirs.is_empty() and theirs[1] and not seen.is_empty() and seen[0] == a.container_id and _box_has(seen[1], rope),
			"el otro jugador lo abre y ve la cuerda: %s" % [theirs])
	other.state.position = b.global_position + Vector3(0, 0, 0.9)
	other.apply_state(other.state)
	theirs = await _peer2(Op.OPEN, [b.container_id])
	seen = _last_peer2("box")
	_check(not theirs.is_empty() and theirs[1] and not seen.is_empty() and seen[0] == b.container_id and seen[1][3].is_empty(),
			"el segundo armario está vacío: no comparten lo de adentro")
	_check(b.inventory.grid.stacks.is_empty() and a.inventory.grid.has(rope), "en el host, la cuerda está solo en el primero")


# --- Ayudas ------------------------------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[creador_juego] FALLA: %s" % what)
	else:
		print("[creador_juego] ok: %s" % what)


func _req(op: int, args: Array, uids: Array = []) -> Array:
	var seq := net.replica.request(op, args, uids)
	if seq == 0:
		return [false, "no salió"]
	for i in 30:
		if _answers.has(seq):
			return _answers[seq]
		await get_tree().physics_frame
	return [false, "sin respuesta"]


func _peer2(op: int, args: Array) -> Array:
	_peer2_seq += 1
	net._inbox.append([2, _peer2_seq, op, args])
	for i in 4:
		await get_tree().physics_frame
	for payload in _peer2_payloads:
		for result in payload.get("r", []):
			if result[0] == _peer2_seq:
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


func _teleport(position: Vector3) -> void:
	var state := actor.state
	state.position = position
	state.velocity = Vector3.ZERO
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
	for uid in net.replica.own.sorted_uids():
		if net.replica.own.stacks[uid].def_id == def_id:
			list.append(uid)
	return list
