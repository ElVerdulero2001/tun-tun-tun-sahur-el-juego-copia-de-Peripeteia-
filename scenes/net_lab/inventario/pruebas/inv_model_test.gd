extends Node

## Prueba del modelo del inventario, sin red, sin interfaz y sin física: la
## grilla y sus operaciones (InvGrid, InvOps, InvLoadout). Cada caso dice qué
## tiene que pasar; si algo da distinto, lo cuenta y la prueba sale con error.
## Se corre con: --headless --scene res://scenes/net_lab/inventario/pruebas/inv_model_test.tscn

var _failures := 0
var _checks := 0
var _catalog := InvCatalog.new()
var _next_uid := 1000


func _ready() -> void:
	_build_catalog()
	_limits_and_overlap()
	_rotation()
	_move_over_own_footprint()
	_rejected_changes_nothing()
	_stacks()
	_merge_quantity()
	_split()
	_take_and_insert()
	_transfer_between_grids()
	_loadout_after_operations()
	_snapshot_round_trip()
	print("[inv_model_test] %d comprobaciones, %d fallas" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _def(id: StringName, size: Vector2i, can_rotate := true, max_stack := 1, state := {}) -> InvItemDef:
	var def := InvItemDef.new()
	def.id = id
	def.display_name = String(id)
	def.size = size
	def.can_rotate = can_rotate
	def.stackable = max_stack > 1
	def.max_stack = max_stack
	def.default_state = state
	_catalog.items.append(def)
	return def


func _build_catalog() -> void:
	_def(&"llave", Vector2i(1, 1))
	_def(&"machete", Vector2i(1, 3))
	_def(&"fijo", Vector2i(2, 3), false)
	_def(&"caja", Vector2i(2, 2))
	_def(&"municion", Vector2i(1, 1), true, 30)
	_def(&"bateria", Vector2i(1, 1), true, 4, {"carga": 100})


func _uid() -> int:
	_next_uid += 1
	return _next_uid


func _put(grid: InvGrid, def_id: StringName, cell: Vector2i, quantity := 1, rot := 0, state := {}) -> InvStack:
	var stack := InvStack.make(_uid(), def_id, quantity, state)
	assert(grid.fits(grid.catalog.find(def_id).footprint(rot), cell))
	grid.add(stack, cell, rot)
	return stack


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[inv_model_test] FALLA: %s" % what)


func _grid(columns := 6, rows := 5) -> InvGrid:
	return InvGrid.new(columns, rows, _catalog)


# 1. Límites, solapamiento, rotación y movimiento sobre la propia huella.

func _limits_and_overlap() -> void:
	var grid := _grid()
	var machete := _put(grid, &"machete", Vector2i(0, 0))
	_check(grid.rect_of(machete.uid) == Rect2i(0, 0, 1, 3), "el machete ocupa 1×3")
	_check(not grid.fits(Vector2i(1, 3), Vector2i(0, 3)), "1×3 en la fila 3 de 5 se sale por abajo")
	_check(grid.fits(Vector2i(1, 3), Vector2i(5, 2)), "1×3 entra justo en la última columna, filas 2 a 4")
	_check(not grid.fits(Vector2i(1, 3), Vector2i(6, 0)), "una columna de más se sale")
	_check(not grid.fits(Vector2i(1, 1), Vector2i(-1, 0)), "celda negativa se sale")
	_check(not grid.fits(Vector2i(2, 2), Vector2i(0, 1)), "pisa al machete")
	_check(grid.fits(Vector2i(2, 2), Vector2i(1, 0)), "al lado del machete entra")
	_check(grid.uid_at(Vector2i(0, 2)) == machete.uid and grid.uid_at(Vector2i(0, 3)) == 0, "uid_at mira la huella")
	var reason := InvOps.move(grid, machete.uid, machete.ver, grid, Vector2i(5, 3), 0)
	_check(reason != "" and grid.placement(machete.uid).cell == Vector2i.ZERO, "mover afuera se rechaza y no lo mueve")


func _rotation() -> void:
	var grid := _grid()
	var machete := _put(grid, &"machete", Vector2i(0, 0))
	var reason := InvOps.move(grid, machete.uid, machete.ver, grid, Vector2i(0, 4), 1)
	_check(reason == "", "el machete girado (3×1) entra en la última fila: %s" % reason)
	_check(grid.rect_of(machete.uid) == Rect2i(0, 4, 3, 1), "girado ocupa 3×1")
	var fijo := _put(grid, &"fijo", Vector2i(3, 0))
	reason = InvOps.move(grid, fijo.uid, fijo.ver, grid, Vector2i(3, 0), 1)
	_check(reason == "este objeto no se puede girar" and grid.placement(fijo.uid).rot == 0, "un objeto que no se gira no gira")
	# Cuatro posiciones: a 180° ocupa lo mismo que sin girar, y a 270° lo mismo que a 90°.
	reason = InvOps.move(grid, machete.uid, machete.ver, grid, Vector2i(0, 0), 2)
	_check(reason == "" and grid.rect_of(machete.uid) == Rect2i(0, 0, 1, 3) and grid.placement(machete.uid).rot == 2,
			"girado 180° ocupa 1×3: %s" % reason)
	reason = InvOps.move(grid, machete.uid, machete.ver, grid, Vector2i(0, 4), 3)
	_check(reason == "" and grid.rect_of(machete.uid) == Rect2i(0, 4, 3, 1) and grid.placement(machete.uid).rot == 3,
			"girado 270° ocupa 3×1: %s" % reason)
	var before := var_to_str(grid.snapshot())
	_check(InvOps.move(grid, machete.uid, machete.ver, grid, Vector2i(0, 0), 4) == "giro inválido", "un giro de 4 se rechaza")
	_check(InvOps.move(grid, machete.uid, machete.ver, grid, Vector2i(0, 0), -1) == "giro inválido", "un giro negativo se rechaza")
	_check(var_to_str(grid.snapshot()) == before, "los giros inválidos no cambian nada")
	reason = InvOps.move(grid, machete.uid, machete.ver, grid, Vector2i(0, 4), 3)
	_check(reason == "" and grid.placement(machete.uid).rot == 3 and var_to_str(grid.snapshot()) == before,
			"dejarlo en el mismo lugar con el mismo giro no cambia nada")


func _move_over_own_footprint() -> void:
	var grid := _grid()
	var caja := _put(grid, &"caja", Vector2i(0, 0))
	var reason := InvOps.move(grid, caja.uid, caja.ver, grid, Vector2i(1, 1), 0)
	_check(reason == "", "la caja 2×2 se corre una celda pisando su propio lugar: %s" % reason)
	_check(grid.placement(caja.uid).cell == Vector2i(1, 1), "quedó en (1, 1)")
	_check(caja.ver == 1, "mover sube la versión de la pila")


func _rejected_changes_nothing() -> void:
	var grid := _grid()
	var caja := _put(grid, &"caja", Vector2i(0, 0))
	var llave := _put(grid, &"llave", Vector2i(3, 0))
	var before := var_to_str(grid.snapshot())
	_check(InvOps.move(grid, caja.uid, caja.ver, grid, Vector2i(2, 0), 0) != "", "caja sobre la llave se rechaza")
	_check(InvOps.move(grid, caja.uid, caja.ver + 7, grid, Vector2i(4, 3), 0) != "", "una versión vieja se rechaza")
	_check(InvOps.move(grid, 999999, 0, grid, Vector2i(4, 3), 0) != "", "un id que no existe se rechaza")
	_check(InvOps.merge(grid, caja.uid, caja.ver, grid, llave.uid) != "", "apilar distintos se rechaza")
	_check(var_to_str(grid.snapshot()) == before, "nada de eso cambió la grilla, ni su revisión")


# 2. Pilas: parcial, llena, distinto estado; división cancelada, inválida y sin espacio.

func _stacks() -> void:
	var grid := _grid()
	var a := _put(grid, &"municion", Vector2i(0, 0), 20)
	var b := _put(grid, &"municion", Vector2i(1, 0), 20)
	var reason := InvOps.merge(grid, a.uid, a.ver, grid, b.uid)
	_check(reason == "" and b.quantity == 30 and a.quantity == 10 and grid.has(a.uid), "20 sobre 20: queda 30 y 10 en el origen")
	reason = InvOps.merge(grid, a.uid, a.ver, grid, b.uid)
	_check(reason.begins_with("esa pila ya está llena") and a.quantity == 10, "sobre una pila llena se rechaza")
	var c := _put(grid, &"municion", Vector2i(2, 0), 5)
	reason = InvOps.merge(grid, c.uid, c.ver, grid, a.uid)
	_check(reason == "" and a.quantity == 15 and not grid.has(c.uid), "5 sobre 10: el origen se vacía y su id se retira")
	var full := _put(grid, &"bateria", Vector2i(3, 0), 2, 0, {"carga": 100})
	var low := _put(grid, &"bateria", Vector2i(4, 0), 2, 0, {"carga": 40})
	reason = InvOps.merge(grid, low.uid, low.ver, grid, full.uid)
	_check(reason.begins_with("no se apilan: tienen distinto estado") and full.quantity == 2 and low.quantity == 2,
			"baterías con distinta carga no se juntan: %s" % reason)
	_check(grid.quantity_of(&"municion") == 45, "no se perdió ni se duplicó munición")


## Apilar solo una cantidad: lo que hace el clic derecho con la pila en la mano.
func _merge_quantity() -> void:
	var grid := _grid()
	var d := _put(grid, &"municion", Vector2i(0, 0), 10)
	var e := _put(grid, &"municion", Vector2i(1, 0), 1)
	var before := var_to_str(grid.snapshot())
	_check(InvOps.merge(grid, d.uid, d.ver, grid, e.uid, 0) != "", "apilar 0 se rechaza")
	_check(InvOps.merge(grid, d.uid, d.ver, grid, e.uid, 11) != "", "apilar más de lo que hay se rechaza")
	_check(var_to_str(grid.snapshot()) == before, "apilar una cantidad inválida no cambia nada")
	var reason := InvOps.merge(grid, d.uid, d.ver, grid, e.uid, 3)
	_check(reason == "" and d.quantity == 7 and e.quantity == 4 and grid.has(d.uid), "apilar 3 de 10: quedan 7 y la otra tiene 4")
	var full := _put(grid, &"municion", Vector2i(2, 0), 28)
	reason = InvOps.merge(grid, d.uid, d.ver, grid, full.uid, 5)
	_check(reason == "" and full.quantity == 30 and d.quantity == 5, "pedir 5 sobre una que tiene lugar para 2: pasan 2")
	reason = InvOps.merge(grid, d.uid, d.ver, grid, e.uid, 5)
	_check(reason == "" and not grid.has(d.uid) and e.quantity == 9, "apilar justo lo que queda vacía el origen y retira su id")


func _split() -> void:
	var grid := _grid(3, 1)
	var a := _put(grid, &"municion", Vector2i(0, 0), 12)
	var before := var_to_str(grid.snapshot())
	_check(InvOps.split(grid, a.uid, a.ver, 0, grid, Vector2i(1, 0), 0, _uid()) != "", "dividir 0 se rechaza")
	_check(InvOps.split(grid, a.uid, a.ver, 12, grid, Vector2i(1, 0), 0, _uid()) != "", "dividir todo se rechaza")
	_check(InvOps.split(grid, a.uid, a.ver, -3, grid, Vector2i(1, 0), 0, _uid()) != "", "dividir negativo se rechaza")
	_check(InvOps.split(grid, a.uid, a.ver, 4, grid, Vector2i(0, 0), 0, _uid()) != "", "dividir encima de sí mismo se rechaza")
	_check(var_to_str(grid.snapshot()) == before, "las divisiones rechazadas no cambian nada")
	var new_uid := _uid()
	var reason := InvOps.split(grid, a.uid, a.ver, 4, grid, Vector2i(2, 0), 0, new_uid)
	_check(reason == "" and a.quantity == 8 and grid.get_stack(new_uid).quantity == 4, "dividir 4 de 12: 8 y 4")
	_check(grid.has(a.uid) and new_uid != a.uid, "la original conserva su id y la nueva tiene otro")
	var b := grid.get_stack(new_uid)
	before = var_to_str(grid.snapshot())
	var reason_full := InvOps.split(grid, b.uid, b.ver, 1, grid, Vector2i(1, 0), 0, _uid())
	_check(reason_full == "", "queda una celda libre: entra")
	var c_uid := _uid()
	reason_full = InvOps.split(grid, a.uid, a.ver, 1, grid, Vector2i(1, 0), 0, c_uid)
	_check(reason_full != "" and not grid.has(c_uid), "sin espacio se rechaza y no aparece nada")
	_check(grid.quantity_of(&"municion") == 12, "dividir conserva el total")


# 3. Recoger, soltar y transferir: cantidades e identidad.

func _take_and_insert() -> void:
	var grid := _grid(2, 1)
	_put(grid, &"municion", Vector2i(0, 0), 25)
	var world := InvStack.make(_uid(), &"municion", 30, {})
	var result := InvOps.insert(grid, world)
	_check(result["reason"] == "" and result["taken"] == 30 and result["placed"], "30 del mundo: 5 completan la pila y 25 van al lugar libre")
	var placed := grid.get_stack(world.uid)
	_check(placed != null and placed.quantity == 25, "la pila nueva conserva el id del objeto del mundo")
	var world2 := InvStack.make(_uid(), &"municion", 10, {})
	result = InvOps.insert(grid, world2)
	_check(result["taken"] == 5 and not result["placed"], "10 más: solo entran 5 (recogida parcial)")
	_check(grid.quantity_of(&"municion") == 60, "60 en la grilla (2 pilas llenas)")
	var world3 := InvStack.make(_uid(), &"llave", 1, {})
	var before := var_to_str(grid.snapshot())
	result = InvOps.insert(grid, world3)
	_check(result["reason"] != "" and result["taken"] == 0 and var_to_str(grid.snapshot()) == before, "sin lugar no cambia nada")
	var uid := placed.uid
	_check(placed.quantity == 30, "la pila del lugar libre se completó con 5 de la segunda recogida")
	var out := InvOps.take(grid, uid, placed.ver, 31, _uid())
	_check(out[0] != "" and out[1] == null and grid.get_stack(uid).quantity == 30, "soltar más de lo que hay se rechaza")
	var new_uid := _uid()
	out = InvOps.take(grid, uid, placed.ver, 12, new_uid)
	_check(out[0] == "" and out[1].uid == new_uid and out[1].quantity == 12 and grid.get_stack(uid).quantity == 18, "soltar 12 de 30: nuevo id afuera")
	out = InvOps.take(grid, uid, grid.get_stack(uid).ver, 18, _uid())
	_check(out[0] == "" and out[1].uid == uid and not grid.has(uid), "soltar todo: sale la pila con su id")


func _transfer_between_grids() -> void:
	var mine := _grid()
	var crate := _grid(4, 4)
	var fijo := _put(mine, &"fijo", Vector2i(0, 0))
	var reason := InvOps.move(mine, fijo.uid, fijo.ver, crate, Vector2i(2, 1), 0)
	_check(reason == "" and crate.has(fijo.uid) and not mine.has(fijo.uid), "a la caja con su id")
	var a := _put(mine, &"municion", Vector2i(0, 0), 20)
	var b := _put(crate, &"municion", Vector2i(0, 0), 25)
	reason = InvOps.merge(mine, a.uid, a.ver, crate, b.uid)
	_check(reason == "" and b.quantity == 30 and a.quantity == 15, "apilar entre inventarios: pasa lo que entra")
	var rev_mine := mine.revision
	var rev_crate := crate.revision
	reason = InvOps.move(mine, a.uid, a.ver, crate, Vector2i(0, 3), 1)
	_check(reason == "" and crate.placement(a.uid).rot == 1, "a la caja girado")
	_check(mine.revision == rev_mine + 1 and crate.revision == rev_crate + 1, "una transferencia sube la revisión de los dos")
	var big := _put(mine, &"fijo", Vector2i(0, 0))
	var before_mine := var_to_str(mine.snapshot())
	var before_crate := var_to_str(crate.snapshot())
	reason = InvOps.move(mine, big.uid, big.ver, crate, Vector2i(2, 2), 0)
	_check(reason != "" and var_to_str(mine.snapshot()) == before_mine and var_to_str(crate.snapshot()) == before_crate,
			"una transferencia que no entra no cambia ninguno de los dos")


# 6. Barra rápida coherente (lo que es del modelo; lo de red va en la prueba de red).

func _loadout_after_operations() -> void:
	var grid := _grid()
	var crate := _grid(4, 4)
	var loadout := InvLoadout.new()
	var machete := _put(grid, &"machete", Vector2i(0, 0))
	var a := _put(grid, &"municion", Vector2i(2, 0), 10)
	var b := _put(grid, &"municion", Vector2i(3, 0), 10)
	loadout.hotbar[0] = machete.uid
	loadout.hotbar[1] = a.uid
	loadout.hotbar[2] = b.uid
	loadout.equipped_uid = machete.uid
	InvOps.move(grid, machete.uid, machete.ver, grid, Vector2i(0, 2), 1)
	_check(not loadout.forget_missing(grid) and loadout.hotbar[0] == machete.uid and loadout.equipped_uid == machete.uid,
			"mover y girar conserva el acceso y el equipo")
	var split_uid := _uid()
	InvOps.split(grid, a.uid, a.ver, 3, grid, Vector2i(4, 0), 0, split_uid)
	_check(not loadout.forget_missing(grid) and loadout.hotbar[1] == a.uid and loadout.slot_of(split_uid) == -1,
			"dividir: la original sigue en su acceso y la nueva no tiene")
	InvOps.merge(grid, b.uid, b.ver, grid, a.uid)
	_check(loadout.forget_missing(grid) and loadout.hotbar[2] == 0 and loadout.hotbar[1] == a.uid,
			"fusionar todo: el origen se limpia y no se reasigna a otra pila de munición")
	InvOps.move(grid, machete.uid, machete.ver, crate, Vector2i(0, 0), 0)
	_check(loadout.forget_missing(grid) and loadout.hotbar[0] == 0 and loadout.equipped_uid == 0,
			"pasarlo a la caja limpia el acceso y lo desequipa")


func _snapshot_round_trip() -> void:
	var grid := _grid()
	_put(grid, &"machete", Vector2i(0, 0), 1, 3)
	_put(grid, &"bateria", Vector2i(4, 4), 3, 0, {"carga": 40})
	grid.revision = 9
	var copy := InvGrid.from_snapshot(bytes_to_var(var_to_bytes(grid.snapshot())), _catalog)
	_check(copy != null and var_to_str(copy.snapshot()) == var_to_str(grid.snapshot()), "la copia que viaja por red es igual")
	_check(InvGrid.from_snapshot([1, 2, 3], _catalog) == null, "una copia mal formada se descarta")
	_check(InvGrid.from_snapshot([6, 5, 0, [[[1, "llave", 1, {}, 0], 0, 0, "x"]]], _catalog) == null, "un tipo de dato equivocado se descarta")
	_check(InvGrid.from_snapshot([6, 5, 0, [[[1, "llave", 1, {}, 0], 0, 0, 5]]], _catalog) == null, "un giro de 5 se descarta")
	_check(InvGrid.from_snapshot([6, 5, 0, [[[1, "llave", 1, {}, 0], 0, 0, true]]], _catalog) == null,
			"el giro viejo (verdadero o falso) se descarta")
