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
## clic no manda dos veces lo mismo).

## Cambió lo propio, la caja o la barra.
signal changed
signal world_changed
signal equipment_changed
## El host contestó un pedido de esta máquina.
signal answered(seq: int, ok: bool, reason: String)
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
	_next_seq = 0
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
	changed.emit()
	return _next_seq


func is_uid_pending(uid: int) -> bool:
	for seq in pending:
		if uid in pending[seq]["uids"]:
			return true
	return false


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
	if payload.has("eq") and payload["eq"] is Array:
		for entry in payload["eq"]:
			if entry is Array and entry.size() == 2:
				equipment[entry[0]] = str(entry[1])
		equipment_changed.emit()
	if in_world:
		world_changed.emit()
	if mine:
		changed.emit()
	for result in results:
		if result is Array and result.size() == 3:
			answered.emit(result[0], result[1], str(result[2]))


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
