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
## no confirmó, en el orden en que lo pidió: lo recogido adentro (con
## InvOps.insert, como lo va a meter el host), lo soltado afuera (DROP_AT, con
## InvOps.take) y una unidad menos por cada consumible usado
## (InvNet.queue_use). shown_box() es lo mismo para la caja abierta, con lo
## soltado desde ella. Lo recogido entero deja de verse en el mundo (is_taken)
## y lo soltado ya se ve en el piso, en su lugar (predicted_drops). Cuando el
## host contesta, lo predicho se borra y queda lo que confirmó: si dijo que no,
## el objeto vuelve a verse en el piso o en la grilla.

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
## Pedidos sin contestar: número -> {"op", "args", "uids", "slots", "msec"}.
var pending := {}

var _next_seq := 0
## La caja que se cerró desde acá: lo que llegue de ella hasta volver a abrirla
## (un paquete que ya venía en viaje) no la vuelve a mostrar.
var _ignored_box := 0
## Consumibles usados que el host todavía no confirmó, en orden: {"uid",
## "counter"}; el contador es -1 hasta que el uso sale en un input.
var _uses: Array = []
var _shown: InvGrid
var _shown_box: InvGrid
var _shown_dirty := true
var _taken := {}  # id de un objeto del mundo -> true: recogido entero, sin confirmar
var _drops: Array = []  # lo soltado sin confirmar: {"key": -número del pedido, "stack", "pos"}


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
	pending[_next_seq] = {"op": op, "args": args, "uids": uids, "slots": slots, "msec": Time.get_ticks_msec()}
	send.call(_next_seq, op, args)
	if op in PREDICTED:
		_mark_shown()
	changed.emit()
	return _next_seq


## Los pedidos que se ven hechos antes de que conteste el host.
const PREDICTED := [InvProtocol.Op.PICKUP, InvProtocol.Op.DROP_AT]


## Si ese objeto tiene un pedido sin contestar. Recoger no cuenta: lo recogido
## ya se ve en la grilla y se maneja como lo demás (el host contesta los
## pedidos en orden, así que el que sigue lo encuentra ya recogido).
func is_uid_pending(uid: int) -> bool:
	for seq in pending:
		if pending[seq]["op"] != InvProtocol.Op.PICKUP and uid in pending[seq]["uids"]:
			return true
	return false


## Si ese objeto tiene un pedido sin contestar que no se ve hecho todavía (lo
## que la interfaz marca como "esperando…"): ni recoger ni soltar cuentan.
func is_uid_waiting(uid: int) -> bool:
	for seq in pending:
		if not pending[seq]["op"] in PREDICTED and uid in pending[seq]["uids"]:
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


## La caja abierta como se ve: la confirmada menos lo que esta máquina ya soltó
## desde ella. Sin nada de eso, es la misma `box`.
func shown_box() -> InvGrid:
	if _shown_dirty:
		_rebuild_shown()
	return _shown_box


## Si ese objeto del mundo ya se recogió entero en esta máquina (no se dibuja
## ni se puede mirar para agarrarlo).
func is_taken(uid: int) -> bool:
	if _shown_dirty:
		_rebuild_shown()
	return _taken.has(uid)


## Lo que esta máquina ya soltó y el host todavía no confirmó, para dibujarlo en
## el piso: {"key": un número negativo (el del pedido), "stack", "pos"}.
func predicted_drops() -> Array:
	if _shown_dirty:
		_rebuild_shown()
	return _drops


func _mark_shown() -> void:
	_shown_dirty = true
	shown_changed.emit()


func _rebuild_shown() -> void:
	_shown_dirty = false
	_taken.clear()
	_drops = []
	_shown = own
	_shown_box = box
	var predicted := pending.keys().filter(func(seq: int) -> bool: return pending[seq]["op"] in PREDICTED)
	if own == null or (predicted.is_empty() and _uses.is_empty()):
		return
	_shown = own.copy()
	predicted.sort()
	for seq in predicted:
		var entry: Dictionary = pending[seq]
		var args: Array = entry["args"]
		if entry["op"] == InvProtocol.Op.PICKUP:
			var item: Dictionary = world.get(args[0], {})
			if item.is_empty():
				continue
			var stack: InvStack = item["stack"]
			var result := InvOps.insert(_shown, stack.copy())
			if result["reason"] == "" and result["taken"] >= stack.quantity:
				_taken[stack.uid] = true
			continue
		# Soltar: de la grilla propia o de la caja abierta.
		var from: InvGrid = _shown if args[0] == InvProtocol.OWN else null
		if args[0] != InvProtocol.OWN and args[0] == box_id and box != null:
			if _shown_box == box:
				_shown_box = box.copy()
			from = _shown_box
		var stack := from.get_stack(args[1]) if from != null else null
		if stack == null:
			continue
		var out := InvOps.take(from, stack.uid, stack.ver, mini(args[3], stack.quantity), -seq)
		if out[1] != null:
			var dropped: InvStack = (out[1] as InvStack).copy()
			dropped.uid = -seq
			_drops.append({"key": -seq, "stack": dropped, "pos": InvProtocol.drop_spot_of(args)})
	for use: Dictionary in _uses:
		InvOps.consume(_shown, use["uid"], 1)


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
	_mark_shown()
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
