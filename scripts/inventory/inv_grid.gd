class_name InvGrid
extends RefCounted

## Una grilla de inventario: columnas, filas y qué objeto está en cada lugar.
## La colocación (la celda de arriba a la izquierda y el giro) es de la grilla,
## no del objeto. No sabe de red, de nodos ni de interfaz: las operaciones que
## la cambian están en InvOps, y todo se prueba sin nada más.


class Placement:
	var cell := Vector2i.ZERO
	## Giro, de a 90° en el sentido del reloj: 0 a 3.
	var rot := 0

	func _init(p_cell := Vector2i.ZERO, p_rot := 0) -> void:
		cell = p_cell
		rot = p_rot


var columns := 12
var rows := 16
var catalog: InvCatalog
## Sube con cada cambio. Una copia más vieja que la que se tiene se descarta.
var revision := 0
var stacks := {}  # uid -> InvStack
var placements := {}  # uid -> Placement


func _init(p_columns := 12, p_rows := 16, p_catalog: InvCatalog = null) -> void:
	columns = maxi(p_columns, 1)
	rows = maxi(p_rows, 1)
	catalog = p_catalog


func has(uid: int) -> bool:
	return stacks.has(uid)


func get_stack(uid: int) -> InvStack:
	return stacks.get(uid)


func placement(uid: int) -> Placement:
	return placements.get(uid)


func def_of(uid: int) -> InvItemDef:
	var stack: InvStack = stacks.get(uid)
	return catalog.find(stack.def_id) if stack != null and catalog != null else null


## Ancho y alto en celdas que ocupa ese objeto, con su giro.
func footprint_of(uid: int) -> Vector2i:
	var def := def_of(uid)
	var place: Placement = placements.get(uid)
	if def == null or place == null:
		return Vector2i.ONE
	return def.footprint(place.rot)


func rect_of(uid: int) -> Rect2i:
	var place: Placement = placements.get(uid)
	return Rect2i(place.cell if place != null else Vector2i.ZERO, footprint_of(uid))


## Si un objeto de esa huella entra con su esquina en `cell`: adentro de la
## grilla y sin pisar a otro. `ignore_uid` no cuenta: es el que se está moviendo
## dentro de esta misma grilla, y su lugar de antes no lo bloquea.
func fits(foot: Vector2i, cell: Vector2i, ignore_uid := 0) -> bool:
	return why_not_fits(foot, cell, ignore_uid) == ""


func why_not_fits(foot: Vector2i, cell: Vector2i, ignore_uid := 0) -> String:
	if foot.x <= 0 or foot.y <= 0 or cell.x < 0 or cell.y < 0 or cell.x + foot.x > columns or cell.y + foot.y > rows:
		return "no entra ahí: se sale de la grilla"
	var area := Rect2i(cell, foot)
	for uid in placements:
		if uid != ignore_uid and rect_of(uid).intersects(area):
			return "no entra ahí: hay otro objeto"
	return ""


## El objeto que ocupa esa celda, o 0.
func uid_at(cell: Vector2i) -> int:
	for uid in placements:
		if rect_of(uid).has_point(cell):
			return uid
	return 0


## El primer lugar libre para ese tipo: de arriba abajo y de izquierda a
## derecha, primero sin girar y después girado 90°, si se puede. [celda, giro],
## o vacío si no entra en ningún lado.
func free_spot(def: InvItemDef) -> Array:
	var turns := [0, 1] if def.can_rotate and def.size.x != def.size.y else [0]
	for rot: int in turns:
		var foot := def.footprint(rot)
		for y in rows:
			for x in columns:
				if fits(foot, Vector2i(x, y)):
					return [Vector2i(x, y), rot]
	return []


## Los objetos en el orden en que se recorre la grilla: por fila y después por columna.
func sorted_uids() -> Array:
	var list := placements.keys()
	list.sort_custom(func(a: int, b: int) -> bool:
		var ca: Vector2i = placements[a].cell
		var cb: Vector2i = placements[b].cell
		if ca.y != cb.y:
			return ca.y < cb.y
		if ca.x != cb.x:
			return ca.x < cb.x
		return a < b)
	return list


## Sin validar: lo usan InvOps, después de validar, y quien arma una copia.
func add(stack: InvStack, cell: Vector2i, rot: int) -> void:
	stacks[stack.uid] = stack
	placements[stack.uid] = Placement.new(cell, rot)


func remove(uid: int) -> void:
	stacks.erase(uid)
	placements.erase(uid)


## Cuántas unidades hay de un tipo, sumando todas sus pilas.
func quantity_of(def_id: StringName) -> int:
	var total := 0
	for uid in stacks:
		if stacks[uid].def_id == def_id:
			total += stacks[uid].quantity
	return total


func snapshot() -> Array:
	var items := []
	for uid in sorted_uids():
		var place: Placement = placements[uid]
		items.append([stacks[uid].to_array(), place.cell.x, place.cell.y, place.rot])
	return [columns, rows, revision, items]


## Una grilla desde lo que manda el host, o null si no tiene la forma esperada.
static func from_snapshot(data: Variant, p_catalog: InvCatalog) -> InvGrid:
	if not data is Array or data.size() != 4 or typeof(data[0]) != TYPE_INT or typeof(data[1]) != TYPE_INT \
			or typeof(data[2]) != TYPE_INT or not data[3] is Array:
		return null
	var grid := InvGrid.new(data[0], data[1], p_catalog)
	grid.revision = data[2]
	for item in data[3]:
		if not item is Array or item.size() != 4 or typeof(item[1]) != TYPE_INT or typeof(item[2]) != TYPE_INT \
				or typeof(item[3]) != TYPE_INT or item[3] < 0 or item[3] > 3:
			return null
		var stack := InvStack.from_array(item[0])
		if stack == null:
			return null
		grid.add(stack, Vector2i(item[1], item[2]), item[3])
	return grid


func copy() -> InvGrid:
	return InvGrid.from_snapshot(snapshot(), catalog)
