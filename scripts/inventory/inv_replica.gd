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
## no confirmó, en el orden en que lo hizo: lo recogido adentro (con
## InvOps.insert, como lo va a meter el host), lo soltado afuera (DROP_AT, con
## InvOps.take) y una unidad menos por cada consumible usado
## (InvNet.queue_use). Recoger, soltar y usar van en un solo registro con su
## orden (`order`): hasta la auditoría del mismo día se aplicaban primero
## todos los pedidos y después todos los usos, y usar lo último de una pila y
## después recoger otra igual mostraba la pila vieja llena (INV-03). El host
## los hace en ese mismo orden (InvProtocol, uso anterior). shown_box() es lo
## mismo para la caja abierta, con lo soltado desde ella. Lo recogido entero
## deja de verse en el mundo (is_taken) y lo soltado ya se ve en el piso, en su
## lugar (predicted_drops). Cuando el host contesta, lo predicho se borra y
## queda lo que confirmó: si dijo que no, el objeto vuelve a verse en el piso o
## en la grilla.

## Cambió lo propio, la caja o la barra.
signal changed
signal world_changed
signal equipment_changed
## Cambió lo que se ve sin esperar al host (shown_own, is_taken).
signal shown_changed
## Puede haber cambiado lo que se ve suelto en el mundo: lo que dice el host,
## lo recogido entero y lo soltado sin confirmar. Una vez por paquete del host
## o por pedido; usar un consumible no lo cambia (auditoría, ESC-01).
signal world_view_changed
## El host contestó un pedido de esta máquina.
signal answered(seq: int, ok: bool, reason: String)
## El host no pudo usar un consumible que esta máquina ya mostraba usado (uno
## por uso, con su número).
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
## uid -> {"stack": InvStack, "pos": Vector3, "label": bool}; "label" es si se
## ve su cartel, como lo dice el host.
var world := {}
## peer -> id del tipo equipado ("" si nada)
var equipment := {}
## Pedidos sin contestar: número -> {"op", "args", "uids", "slots", "msec", "order"}.
var pending := {}

var _next_seq := 0
## La caja que esta máquina quiere ver (desde la auditoría del 2026-11-08,
## CAJ-01): el pedido OPEN que la pidió (0: ninguna), qué caja es y si el host
## ya contestó que sí. Lo que llega de una caja se muestra solo si es esa y el
## host ya contestó ese pedido. Así una apertura que se dejó antes de que
## contestara (con Tab, con E, cerrando el inventario o porque no contestó a
## tiempo) no aparece cuando llega tarde, ni las novedades de esa caja que
## vengan después; y una apertura posterior, de la misma caja o de otra, no se
## confunde con la anterior. Hasta ese día era _ignored_box: la caja que se
## cerró desde acá, olvidada al pedir cualquier apertura, y una respuesta tardía
## mostraba la caja después de que la interfaz la había dado por fallida.
var _want_seq := 0
var _want_box := 0
var _want_answered := false
## Consumibles usados que el host todavía no confirmó, en orden: {"uid",
## "counter" (su número de uso), "after" (el último pedido hecho antes),
## "order", "sent" (ya salió en un input)}.
var _uses: Array = []
## Número del último uso puesto en fila desde que se conectó, o -1: cada pedido
## lo lleva, para que el host no lo procese antes de ese uso.
var _last_use := -1
## Orden común de pedidos y usos hechos en esta máquina (INV-03).
var _order := 0
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
	_forget_want()
	world.clear()
	equipment.clear()
	pending.clear()
	_uses.clear()
	_last_use = -1
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
	_next_seq += 1
	_order += 1
	if op == InvProtocol.Op.OPEN:
		_want_seq = _next_seq
		_want_box = args[0]
		_want_answered = false
	pending[_next_seq] = {"op": op, "args": args, "uids": uids, "slots": slots, "msec": Time.get_ticks_msec(),
			"order": _order}
	send.call(_next_seq, op, args, _last_use)
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

## Un consumible de la grilla propia ya usado en esta máquina, con su número
## de uso (InvNet.queue_use). Va después del último pedido hecho. `part`: -1
## el uso normal, o la parte del cuerpo sobre la que se soltó (ActorState.Part).
func add_use(uid: int, counter: int, part := -1) -> void:
	_order += 1
	_uses.append({"uid": uid, "counter": counter, "after": _next_seq, "order": _order, "sent": false, "part": part})
	_last_use = counter
	_mark_shown(false)
	changed.emit()


## El uso más viejo que todavía no salió, si viajan menos de `in_flight` sin
## confirmar: queda como enviado y devuelve su número; si no, -1.
func send_next_use(in_flight: int) -> int:
	var sent := 0
	for use: Dictionary in _uses:
		if use["sent"]:
			sent += 1
		elif sent < in_flight:
			use["sent"] = true
			return use["counter"]
		else:
			break
	return -1


## Los usos que ya salieron y el host todavía no contestó, del más viejo al más
## nuevo, como van en el input: [id del objeto, último pedido antes del uso,
## parte del cuerpo o -1].
func uses_in_flight() -> Array:
	var list := []
	for use: Dictionary in _uses:
		if use["sent"]:
			list.append([use["uid"], use["after"], use["part"]])
	return list


## Cuántos usos esperan al host, en fila o en viaje.
func uses_waiting() -> int:
	return _uses.size()


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


## Lo que se ve hay que rearmarlo. `world_too`: también puede haber cambiado
## lo que se ve suelto en el mundo (no con un consumible usado).
func _mark_shown(world_too := true) -> void:
	_shown_dirty = true
	shown_changed.emit()
	if world_too:
		world_view_changed.emit()


## Rearma lo que se ve desde lo confirmado, haciendo lo que esta máquina hizo y
## el host todavía no confirmó en el orden en que lo hizo: recoger, soltar y
## usar mezclados, como el host los va a hacer.
func _rebuild_shown() -> void:
	_shown_dirty = false
	_taken.clear()
	_drops = []
	_shown = own
	_shown_box = box
	var steps := []  # [orden, número de pedido o 0, uso o null]
	for seq in pending:
		if pending[seq]["op"] in PREDICTED:
			steps.append([pending[seq]["order"], seq, null])
	for use: Dictionary in _uses:
		steps.append([use["order"], 0, use])
	if own == null or steps.is_empty():
		return
	_shown = own.copy()
	steps.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for step: Array in steps:
		if step[2] != null:
			InvOps.consume(_shown, step[2]["uid"], 1)
			continue
		var seq: int = step[1]
		var entry: Dictionary = pending[seq]
		var args: Array = entry["args"]
		if entry["op"] == InvProtocol.Op.PICKUP:
			var item: Dictionary = world.get(args[0], {})
			if item.is_empty():
				continue
			var picked: InvStack = item["stack"]
			var result := InvOps.insert(_shown, picked.copy())
			if result["reason"] == "" and result["taken"] >= picked.quantity:
				_taken[picked.uid] = true
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


## Si hay algún recoger o soltar sin contestar (lo que cambia lo que se ve en el mundo).
func _has_predicted() -> bool:
	for seq in pending:
		if pending[seq]["op"] in PREDICTED:
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
	var results: Array = payload.get("r", []) if payload.get("r") is Array else []
	# La respuesta a la apertura que se quiere ver viene en el mismo paquete que
	# la caja entera (InvAuthority.handle): se mira antes que la caja.
	for result in results:
		if _want_seq != 0 and result is Array and result.size() == 3 and result[0] == _want_seq:
			if result[1]:
				_want_answered = true
			else:
				_forget_want()
	if payload.has("box") and payload["box"] is Array and payload["box"].size() == 2 and typeof(payload["box"][0]) == TYPE_INT:
		# De otra caja, o de una apertura que se dejó o que el host todavía no
		# contestó: no se muestra (CAJ-01).
		if _want_answered and payload["box"][0] == _want_box:
			var grid := InvGrid.from_snapshot(payload["box"][1], catalog)
			if grid != null and (box_id != payload["box"][0] or box == null or grid.revision >= box.revision):
				box_id = payload["box"][0]
				box = grid
		mine = true
	if payload.has("closed") and payload["closed"] is Array and payload["closed"].size() == 2:
		var id: int = payload["closed"][0]
		mine = true
		# Si es la que se ve. Una que esta máquina ya dejó, o la de una apertura
		# vieja mientras se espera otra, no cierra nada ni avisa nada.
		if box_id == id:
			box_id = 0
			box = null
			_forget_want()
			container_closed.emit(id, str(payload["closed"][1]))
	var world_view := in_world or payload.has("closed")
	for result in results:
		if result is Array and result.size() == 3:
			if pending.has(result[0]) and pending[result[0]]["op"] in PREDICTED:
				world_view = true
			pending.erase(result[0])
			mine = true
	# Hasta qué uso de consumible llegó el host, y los que no pudo hacer, cada
	# uno con su número y su motivo: [último hecho, [[número, motivo], ...]].
	# Los hechos ya están en lo confirmado. Solo pueden estar hechos los que
	# salieron; como nunca hay más de InvNet.MAX_USES_WAITING sin confirmar, el
	# número, que da la vuelta en 256, no se confunde (INV-01).
	var refused := PackedStringArray()
	var used: Variant = payload.get("u")
	if used is Array and used.size() == 2 and typeof(used[0]) == TYPE_INT and used[1] is Array:
		_uses = _uses.filter(func(use: Dictionary) -> bool:
			return not use["sent"] or ((used[0] - use["counter"]) & 0xFF) >= 128)
		for entry in used[1]:
			if entry is Array and entry.size() == 2 and typeof(entry[0]) == TYPE_INT:
				refused.append(str(entry[1]))
		mine = true
	if payload.has("eq") and payload["eq"] is Array:
		for entry in payload["eq"]:
			if entry is Array and entry.size() == 2:
				equipment[entry[0]] = str(entry[1])
		equipment_changed.emit()
	if in_world or mine:
		_mark_shown(world_view or (mine and _has_predicted()))
	if in_world:
		world_changed.emit()
	if mine:
		changed.emit()
	for result in results:
		if result is Array and result.size() == 3:
			answered.emit(result[0], result[1], str(result[2]))
	for reason in refused:
		use_refused.emit(reason)


## La interfaz deja la caja que se ve o la que pidió (Tab, E, cerrar el
## inventario, o el host no contestó a tiempo): deja de mostrarse ya, sin
## esperar, y se le pide al host que la cierre. Ese pedido sale aunque el host
## todavía no haya contestado la apertura: los procesa en orden, así que si la
## abre, la cierra enseguida, y si no la abrió, cerrar no hace nada. Lo que
## llegue después de esa caja no se muestra (ver _want_seq), hasta otra
## apertura. Devuelve el número del último pedido de cerrar, o 0 si no había
## nada que dejar.
func leave_box() -> int:
	var ids: Array[int] = []
	if box_id != 0:
		ids.append(box_id)
	if _want_seq != 0 and not _want_box in ids:
		ids.append(_want_box)
	_forget_want()
	var seq := 0
	for id in ids:
		seq = request(InvProtocol.Op.CLOSE, [id])
	if box_id != 0 or box != null:
		box_id = 0
		box = null
		_mark_shown()
		changed.emit()
	return seq


func _forget_want() -> void:
	_want_seq = 0
	_want_box = 0
	_want_answered = false


## El tipo de un objeto propio o de la caja abierta.
func def_of(grid: InvGrid, uid: int) -> InvItemDef:
	return grid.def_of(uid) if grid != null else null


## Un objeto suelto como lo manda el host: [pila, x, y, z, cartel]. Sin el
## último (las pruebas del modelo), lleva cartel.
func _world_put(entry: Variant) -> void:
	if not entry is Array or entry.size() < 4 or entry.size() > 5:
		return
	var stack := InvStack.from_array(entry[0])
	if stack == null:
		return
	var label: bool = entry[4] if entry.size() == 5 and entry[4] is bool else true
	world[stack.uid] = {"stack": stack, "pos": Vector3(entry[1], entry[2], entry[3]), "label": label}
