class_name InvReplica
extends RefCounted

## Lo que esta máquina sabe del inventario, tal como lo confirmó el host: la
## grilla y la barra del jugador local, la caja que tiene abierta, los objetos
## del mundo y el equipo de cada jugador. También en el host, que se manda sus
## paquetes a sí mismo por el mismo camino. La interfaz lee de acá y pide
## cambios con request(); nunca escribe este estado.
##
## Pedidos pendientes: mientras el host no contesta uno, los objetos y accesos
## que toca quedan marcados, y otro pedido sobre ellos no sale (así un doble
## clic no manda dos veces lo mismo). Recoger no los marca: lo recogido ya se
## ve en la grilla y se puede manejar (ver shown_own).
##
## Lo que se ve sin esperar al host (desde el 2026-11-04): shown_own() es la
## grilla propia confirmada con lo que esta máquina ya hizo y el host todavía
## no confirmó: lo recogido adentro (con InvOps.insert, como lo va a meter el
## host) y una unidad menos por cada consumible usado (InvNet.queue_use). Lo
## recogido entero deja de verse en el mundo (is_taken). Cuando el host
## contesta, lo predicho se borra y queda lo que confirmó: si dijo que no, el
## objeto vuelve a verse en el piso o la unidad en la grilla.

## Cambió lo propio, la caja o la barra.
signal changed
signal world_changed
signal equipment_changed
## Cambió lo que se ve sin esperar al host (shown_own, is_taken).
signal shown_changed
## El host contestó un pedido de esta máquina.
signal answered(seq: int, ok: bool, reason: String)
## El host no pudo usar un consumible que esta máquina ya mostraba usado.
signal use_refused(reason: String)
## Se cerró la caja abierta (el jugador se alejó, la caja desapareció…).
signal container_closed(id: int, reason: String)

## Sin respuesta del host en este tiempo, un pedido deja de estar pendiente.
const PENDING_TIMEOUT_MSEC := 10000

var catalog: InvCatalog
## Manda un pedido: func(seq: int, op: int, args: Array). Lo pone InvNet.
var send: Callable
## Ya llegó el estado inicial del host.
var has_state := false
var own: InvGrid
var loadout: InvLoadout
var box_id := 0
var box: InvGrid
## uid -> {"stack": InvStack, "pos": Vector3}
var world := {}
## peer -> id del tipo equipado ("" si nada)
var equipment := {}
## Pedidos sin contestar: número -> {"op", "uids", "slots", "box", "msec"}.
var pending := {}

var _next_seq := 0
## La caja que se cerró desde acá: lo que llegue de ella hasta volver a abrirla
## (un paquete que ya venía en viaje) no la vuelve a mostrar.
var _ignored_box := 0
## Consumibles usados que el host todavía no confirmó, en orden: {"uid",
## "counter"}; el contador es -1 hasta que el uso sale en un input.
var _uses: Array = []
var _shown: InvGrid
var _shown_dirty := true
var _taken := {}  # id de un objeto del mundo -> true: recogido entero, sin confirmar


func reset() -> void:
	has_state = false
	own = null
	loadout = null
	box_id = 0
	box = null
	_ignored_box = 0
	world.clear()
	equipment.clear()
	pending.clear()
	_uses.clear()
	_next_seq = 0
	_mark_shown()
	changed.emit()
	world_changed.emit()
	equipment_changed.emit()


## Pide algo al host. Devuelve el número del pedido, o 0 si no salió: todavía
## no llegó el estado inicial, o alguno de esos objetos o accesos ya tiene un
## pedido sin contestar.
func request(op: int, args: Array, uids: Array = [], slots: Array = []) -> int:
	if not has_state or send.is_null():
		return 0
	for uid in uids:
		if is_uid_pending(uid):
			return 0
	for slot in slots:
		if is_slot_pending(slot):
			return 0
	if op == InvProtocol.Op.OPEN:
		_ignored_box = 0
	_next_seq += 1
	pending[_next_seq] = {"op": op, "uids": uids, "slots": slots, "msec": Time.get_ticks_msec()}
	send.call(_next_seq, op, args)
	if op == InvProtocol.Op.PICKUP:
		_mark_shown()
	changed.emit()
	return _next_seq


## Si ese objeto tiene un pedido sin contestar. Recoger no cuenta: lo recogido
## ya se ve en la grilla y se maneja como lo demás (el host contesta los
## pedidos en orden, así que el que sigue lo encuentra ya recogido).
func is_uid_pending(uid: int) -> bool:
	for seq in pending:
		if pending[seq]["op"] != InvProtocol.Op.PICKUP and uid in pending[seq]["uids"]:
			return true
	return false


# --- Lo que se ve sin esperar al host --------------------------------------------

## Un consumible de la grilla propia ya usado en esta máquina (InvNet.queue_use).
func add_use(uid: int) -> void:
	_uses.append({"uid": uid, "counter": -1})
	_mark_shown()
	changed.emit()


## El uso más viejo sin contador salió en un input con este valor.
func assign_use(counter: int) -> void:
	for use: Dictionary in _uses:
		if use["counter"] < 0:
			use["counter"] = counter
			return


## Si ese objeto tiene un uso que el host todavía no confirmó.
func has_use(uid: int) -> bool:
	return _uses.any(func(use: Dictionary) -> bool: return use["uid"] == uid)


## La grilla propia como se ve: la confirmada más lo que esta máquina ya hizo.
## Sin nada de eso, es la misma `own`.
func shown_own() -> InvGrid:
	if _shown_dirty:
		_rebuild_shown()
	return _shown


## Si ese objeto del mundo ya se recogió entero en esta máquina (no se dibuja
## ni se puede mirar para agarrarlo).
func is_taken(uid: int) -> bool:
	if _shown_dirty:
		_rebuild_shown()
	return _taken.has(uid)


func _mark_shown() -> void:
	_shown_dirty = true
	shown_changed.emit()


func _rebuild_shown() -> void:
	_shown_dirty = false
	_taken.clear()
	var pickups := pending.keys().filter(func(seq: int) -> bool: return pending[seq]["op"] == InvProtocol.Op.PICKUP)
	if own == null or (pickups.is_empty() and _uses.is_empty()):
		_shown = own
		return
	var grid := own.copy()
	pickups.sort()
	for seq in pickups:
		var uids: Array = pending[seq]["uids"]
		var item: Dictionary = world.get(uids[0], {}) if not uids.is_empty() else {}
		if item.is_empty():
			continue
		var stack: InvStack = item["stack"]
		var result := InvOps.insert(grid, stack.copy())
		if result["reason"] == "" and result["taken"] >= stack.quantity:
			_taken[stack.uid] = true
	for use: Dictionary in _uses:
		InvOps.consume(grid, use["uid"], 1)
	_shown = grid


func is_slot_pending(slot: int) -> bool:
	for seq in pending:
		if slot in pending[seq]["slots"]:
			return true
	return false


func is_op_pending(op: int) -> bool:
	for seq in pending:
		if pending[seq]["op"] == op:
			return true
	return false


## Los pedidos que el host no contestó a tiempo dejan de estar pendientes.
func expire_pending() -> PackedInt32Array:
	var now := Time.get_ticks_msec()
	var gone := PackedInt32Array()
	for seq in pending.keys():
		if now - pending[seq]["msec"] > PENDING_TIMEOUT_MSEC:
			pending.erase(seq)
			gone.append(seq)
	if not gone.is_empty():
		_mark_shown()
		changed.emit()
	return gone


## Aplica un paquete del host, ya en orden. Lo que no tenga la forma esperada
## se ignora.
func apply_commit(payload: Dictionary) -> void:
	var mine := false
	var in_world := false
	if payload.has("world") and payload["world"] is Array:
		world.clear()
		for entry in payload["world"]:
			_world_put(entry)
		has_state = true
		in_world = true
		mine = true
	if payload.has("wa") and payload["wa"] is Array:
		for entry in payload["wa"]:
			_world_put(entry)
		in_world = true
	if payload.has("wr") and payload["wr"] is Array:
		for uid in payload["wr"]:
			world.erase(uid)
		in_world = true
	if payload.has("own"):
		var grid := InvGrid.from_snapshot(payload["own"], catalog)
		if grid != null and (own == null or grid.revision > own.revision):
			own = grid
		mine = true
	if payload.has("lo"):
		var fresh := InvLoadout.from_snapshot(payload["lo"])
		if fresh != null and (loadout == null or fresh.revision > loadout.revision):
			loadout = fresh
		mine = true
	if payload.has("box") and payload["box"] is Array and payload["box"].size() == 2 and typeof(payload["box"][0]) == TYPE_INT \
			and payload["box"][0] != _ignored_box:
		var grid := InvGrid.from_snapshot(payload["box"][1], catalog)
		if grid != null and (box_id != payload["box"][0] or box == null or grid.revision >= box.revision):
			box_id = payload["box"][0]
			box = grid
		mine = true
	if payload.has("closed") and payload["closed"] is Array and payload["closed"].size() == 2:
		var id: int = payload["closed"][0]
		if box_id == id:
			box_id = 0
			box = null
		mine = true
		container_closed.emit(id, str(payload["closed"][1]))
	var results: Array = payload.get("r", []) if payload.get("r") is Array else []
	for result in results:
		if result is Array and result.size() == 3:
			pending.erase(result[0])
			mine = true
	# Hasta qué uso de consumible llegó el host: esos ya están en lo confirmado.
	var refused := ""
	var used: Variant = payload.get("u")
	if used is Array and used.size() == 2 and typeof(used[0]) == TYPE_INT:
		_uses = _uses.filter(func(use: Dictionary) -> bool:
			return use["counter"] < 0 or ((used[0] - use["counter"]) & 0xFF) >= 128)
		refused = str(used[1])
		mine = true
	if payload.has("eq") and payload["eq"] is Array:
		for entry in payload["eq"]:
			if entry is Array and entry.size() == 2:
				equipment[entry[0]] = str(entry[1])
		equipment_changed.emit()
	if in_world or mine:
		_mark_shown()
	if in_world:
		world_changed.emit()
	if mine:
		changed.emit()
	for result in results:
		if result is Array and result.size() == 3:
			answered.emit(result[0], result[1], str(result[2]))
	if refused != "":
		use_refused.emit(refused)


## La interfaz cerró la caja (y le pidió al host que deje de mandarla). Se
## deja de mostrar ya, sin esperar.
func forget_box() -> void:
	_ignored_box = box_id
	box_id = 0
	box = null
	changed.emit()


## El tipo de un objeto propio o de la caja abierta.
func def_of(grid: InvGrid, uid: int) -> InvItemDef:
	return grid.def_of(uid) if grid != null else null


func _world_put(entry: Variant) -> void:
	if not entry is Array or entry.size() != 4:
		return
	var stack := InvStack.from_array(entry[0])
	if stack == null:
		return
	world[stack.uid] = {"stack": stack, "pos": Vector3(entry[1], entry[2], entry[3])}
