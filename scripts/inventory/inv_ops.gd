class_name InvOps
extends RefCounted

## Las operaciones sobre una o dos grillas: mover (también de una grilla a
## otra), apilar, dividir, sacar unidades y meter lo que se recoge del mundo.
## Cada una valida todo primero y recién después cambia algo: si devuelve un
## motivo, no tocó nada. Las llama el host; son las mismas jugando solo.
##
## Identidad: mover conserva el id. Al apilar, el destino conserva el suyo y el
## origen lo pierde si se vacía. Al dividir, la pila nueva recibe el id que le
## da quien llama (el host) y la original conserva el suyo.


static func _check_stack(grid: InvGrid, uid: int, ver: int) -> String:
	var stack := grid.get_stack(uid)
	if stack == null:
		return "ese objeto ya no está ahí"
	if stack.ver != ver:
		return "ese objeto cambió mientras lo manejabas: quedó como se ve ahora"
	if grid.def_of(uid) == null:
		return "es de un tipo que no existe"
	return ""


static func _check_rot(def: InvItemDef, rot: int) -> String:
	if rot < 0 or rot > 3:
		return "giro inválido"
	if rot != 0 and not def.can_rotate:
		return "este objeto no se puede girar"
	return ""


static func _touch(a: InvGrid, b: InvGrid) -> void:
	a.revision += 1
	if b != a:
		b.revision += 1


## Mover dentro de una grilla o a otra, con su giro (0 a 3). El lugar de antes
## no bloquea al mismo objeto.
static func move(src: InvGrid, uid: int, ver: int, dst: InvGrid, cell: Vector2i, rot: int) -> String:
	var reason := _check_stack(src, uid, ver)
	if reason != "":
		return reason
	var def := src.def_of(uid)
	reason = _check_rot(def, rot)
	if reason != "":
		return reason
	if src != dst and dst.catalog != src.catalog:
		return "esos inventarios no usan el mismo catálogo"
	reason = dst.why_not_fits(def.footprint(rot), cell, uid if src == dst else 0)
	if reason != "":
		return reason
	var stack := src.get_stack(uid)
	var place := src.placement(uid)
	if src == dst and place.cell == cell and place.rot == rot:
		return ""
	src.remove(uid)
	dst.add(stack, cell, rot)
	stack.ver += 1
	_touch(src, dst)
	return ""


## Apilar sobre otra pila compatible, en la misma grilla o en otra: pasan hasta
## `quantity` unidades (-1: toda la pila), lo que entre hasta llenarla, y el
## resto queda en el origen.
static func merge(src: InvGrid, uid: int, ver: int, dst: InvGrid, target_uid: int, quantity := -1) -> String:
	var reason := _check_stack(src, uid, ver)
	if reason != "":
		return reason
	var stack := src.get_stack(uid)
	if quantity == -1:
		quantity = stack.quantity
	if quantity < 1 or quantity > stack.quantity:
		return "cantidad inválida: tiene que ser entre 1 y %d" % stack.quantity
	var target := dst.get_stack(target_uid)
	if target == null:
		return "la pila de destino ya no está"
	if target == stack:
		return ""
	if stack.def_id != target.def_id:
		return "no se apilan: son objetos distintos"
	if not InvStack.same_state(stack.state, target.state):
		return "no se apilan: tienen distinto estado (%s)" % ", ".join(_state_keys(stack.state, target.state))
	var def := src.def_of(uid)
	if not def.stackable:
		return "este objeto no se apila"
	var room := def.stack_limit() - target.quantity
	if room <= 0:
		return "esa pila ya está llena (%d)" % def.stack_limit()
	var moved := mini(room, quantity)
	target.quantity += moved
	target.ver += 1
	stack.quantity -= moved
	if stack.quantity <= 0:
		src.remove(uid)
	else:
		stack.ver += 1
	_touch(src, dst)
	return ""


## Dividir: `quantity` unidades pasan a una pila nueva, con el id `new_uid`, en
## ese lugar de `dst` (puede ser la misma grilla). La original queda donde está.
static func split(src: InvGrid, uid: int, ver: int, quantity: int, dst: InvGrid, cell: Vector2i, rot: int, new_uid: int) -> String:
	var reason := _check_stack(src, uid, ver)
	if reason != "":
		return reason
	var stack := src.get_stack(uid)
	var def := src.def_of(uid)
	if not def.stackable:
		return "no se divide: este objeto no se apila"
	if stack.quantity < 2:
		return "no se divide: la pila tiene una sola unidad"
	if quantity < 1 or quantity > stack.quantity - 1:
		return "cantidad inválida: tiene que ser entre 1 y %d" % (stack.quantity - 1)
	reason = _check_rot(def, rot)
	if reason != "":
		return reason
	if new_uid <= 0 or src.has(new_uid) or dst.has(new_uid):
		return "id nuevo inválido"
	reason = dst.why_not_fits(def.footprint(rot), cell)
	if reason != "":
		return reason
	stack.quantity -= quantity
	stack.ver += 1
	dst.add(InvStack.make(new_uid, stack.def_id, quantity, stack.state), cell, rot)
	_touch(src, dst)
	return ""


## Sacar unidades de una pila, para soltarlas al mundo. Si salen todas, sale la
## pila misma, con su id; si no, una pila nueva con `new_uid`. [motivo, pila que
## salió o null]. Validar todo antes con can_take() deja el resto para después.
static func can_take(grid: InvGrid, uid: int, ver: int, quantity: int) -> String:
	var reason := _check_stack(grid, uid, ver)
	if reason != "":
		return reason
	var stack := grid.get_stack(uid)
	if quantity < 1 or quantity > stack.quantity:
		return "cantidad inválida: tiene que ser entre 1 y %d" % stack.quantity
	return ""


static func take(grid: InvGrid, uid: int, ver: int, quantity: int, new_uid: int) -> Array:
	var reason := can_take(grid, uid, ver, quantity)
	if reason != "":
		return [reason, null]
	var stack := grid.get_stack(uid)
	grid.revision += 1
	if quantity == stack.quantity:
		grid.remove(uid)
		stack.ver += 1
		return ["", stack]
	stack.quantity -= quantity
	stack.ver += 1
	return ["", InvStack.make(new_uid, stack.def_id, quantity, stack.state)]


## Gastar unidades al usar un objeto. Si se termina, sale de la grilla.
static func consume(grid: InvGrid, uid: int, count: int) -> void:
	var stack := grid.get_stack(uid)
	if stack == null or count <= 0:
		return
	stack.quantity -= count
	stack.ver += 1
	if stack.quantity <= 0:
		grid.remove(uid)
	grid.revision += 1


## Meter en la grilla un objeto del mundo: primero completa las pilas
## compatibles, en el orden de la grilla, y lo que quede va al primer lugar
## libre, con el id del objeto del mundo. Si no entra todo, lo que sobra se
## queda en el mundo. {"reason", "taken", "placed"}; con un motivo no cambió nada.
static func insert(grid: InvGrid, world: InvStack) -> Dictionary:
	var def := grid.catalog.find(world.def_id) if grid.catalog != null else null
	if def == null:
		return {"reason": "es de un tipo que no existe", "taken": 0, "placed": false}
	if world.quantity < 1 or world.quantity > def.stack_limit():
		return {"reason": "cantidad inválida", "taken": 0, "placed": false}
	var remaining := world.quantity
	var merges := []
	if def.stackable:
		for uid in grid.sorted_uids():
			var stack: InvStack = grid.stacks[uid]
			if not stack.compatible_with(world):
				continue
			var take_now := mini(def.stack_limit() - stack.quantity, remaining)
			if take_now > 0:
				merges.append([stack, take_now])
				remaining -= take_now
			if remaining == 0:
				break
	var spot := grid.free_spot(def) if remaining > 0 else []
	var taken := world.quantity - remaining + (remaining if not spot.is_empty() else 0)
	if taken == 0:
		return {"reason": "no hay lugar en tu inventario para %s" % (def.display_name if def.display_name != "" else String(def.id)),
				"taken": 0, "placed": false}
	for merge_step in merges:
		merge_step[0].quantity += merge_step[1]
		merge_step[0].ver += 1
	if not spot.is_empty():
		var placed := InvStack.make(world.uid, world.def_id, remaining, world.state)
		placed.ver = world.ver + 1
		grid.add(placed, spot[0], spot[1])
	grid.revision += 1
	return {"reason": "", "taken": taken, "placed": not spot.is_empty()}


static func _state_keys(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var keys := PackedStringArray()
	for key in a:
		if not b.has(key) or a[key] != b[key]:
			keys.append(str(key))
	for key in b:
		if not a.has(key):
			keys.append(str(key))
	return keys
