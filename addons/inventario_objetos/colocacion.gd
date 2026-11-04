@tool
extends RefCounted

## Pone en la zona lo que ya está guardado: un ítem, como marcadores
## (InvPickupSpawn) en pilas válidas; un contenedor, como cajas de su escena.
## Busca lugares libres en el piso de la zona, lejos de lo que ya hay, y los
## agrega con el deshacer del editor (Ctrl+Z los saca). No guarda la escena:
## eso lo decidís vos.

const Destinos := preload("destinos.gd")
const Guardado := preload("guardado.gd")

## Dónde se buscan lugares para los ítems, siguiendo las filas que ya hay en la
## zona: por columnas (x) y, en cada una, de z en z.
const ITEM_COLUMNS := [-3.0, -1.0, 1.0, -5.0, 3.0, 5.0]
const ROW_START := -5.0
const ROW_END := 6.0
const ROW_STEP := 1.2
## Para las cajas: estas columnas y, en cada una, de z en z, cada BOX_STEP.
const BOX_COLUMNS := [3.0, 5.0, 1.0, -1.0, -3.0, -5.0, 4.0, 2.0, 0.0, -2.0, -4.0]
const BOX_STEP := 0.5
## Cuánto se separa un ítem de otro ítem o de una caja; una caja de otra caja;
## cualquier cosa de una pared, y del borde del piso.
const ITEM_GAP := 0.9
const BOX_GAP := 0.8
const WALL_GAP := 0.6
const FLOOR_MARGIN := 0.4
## Hasta qué altura una forma de colisión cuenta como piso (su cara de arriba).
const FLOOR_TOP := 0.05


## Las pilas en que va esa cantidad: llenas, y la última con lo que sobra.
## 12 con límite 5: 5, 5 y 2. Con 0, ninguna.
static func piles_of(quantity: int, limit: int) -> Array[int]:
	var out: Array[int] = []
	var left := quantity
	while left > 0 and limit > 0:
		out.append(mini(left, limit))
		left -= limit
	return out


## Abre la zona en el editor (si no estaba a la vista) y devuelve
## {"root": raíz} o {"error": por qué no}.
static func open_zone() -> Dictionary:
	var problem := Destinos.check_lab()
	if problem != "":
		return {"error": problem + " Lo colocado no aparecería en el juego."}
	EditorInterface.open_scene_from_path(Destinos.ZONE_PATH)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != Destinos.ZONE_PATH:
		return {"error": "No pude abrir la zona (%s)." % Destinos.ZONE_PATH}
	return {"root": root}


## La zona para leerla sin cambiarla: la abierta en el editor (con lo que
## tenga sin guardar) o una copia de la guardada. {"root", "owned"}: si
## `owned`, hay que liberarla con free().
static func zone_for_reading() -> Dictionary:
	for root: Node in EditorInterface.get_open_scene_roots():
		if root != null and root.scene_file_path == Destinos.ZONE_PATH:
			return {"root": root, "owned": false}
	var scene := load(Destinos.ZONE_PATH) as PackedScene
	return {"root": scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if scene != null else null, "owned": true}


## Los contenedores de la zona: [{"name", "columns", "rows"}].
static func zone_boxes(root: Node) -> Array:
	var out := []
	if root == null:
		return out
	for box in root.find_children("*", "InvContainer", true, false):
		out.append({"name": String(box.get(&"display_name")), "columns": int(box.get(&"columns")), "rows": int(box.get(&"rows"))})
	return out


## Pone los marcadores de un ítem: `piles` (cantidades de cada pila) en
## `spots` (lugares respecto de la raíz), bajo el nodo de los objetos de la
## zona, con `state` como estado propio si no está vacío. Devuelve los nodos.
static func place_items(root: Node, def: Resource, piles: Array[int], spots: Array[Vector3], state: Dictionary,
		undo_redo: EditorUndoRedoManager) -> Array[Node3D]:
	var parent := root.get_node_or_null(Destinos.ITEMS_NODE)
	if parent == null:
		parent = root
	var nodes: Array[Node3D] = []
	var node_name := String(def.get(&"id")).to_pascal_case()
	for i in piles.size():
		var marker := InvPickupSpawn.new()
		marker.name = node_name
		marker.set(&"item", def)
		marker.set(&"quantity", piles[i])
		if not state.is_empty():
			marker.set(&"state_override", state.duplicate(true))
		nodes.append(marker)
	_add(root, parent, nodes, spots, undo_redo, "Colocar %s en la zona (solo los marcadores)" % def.get(&"display_name"))
	return nodes


## Pone `spots.size()` cajas de esa escena, directo en la raíz de la zona.
static func place_boxes(root: Node, scene: PackedScene, spots: Array[Vector3], undo_redo: EditorUndoRedoManager) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for i in spots.size():
		nodes.append(scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D)
	_add(root, root, nodes, spots, undo_redo, "Colocar %s en la zona (solo las cajas)" % scene.resource_path.get_file())
	return nodes


static func _add(root: Node, parent: Node, nodes: Array[Node3D], spots: Array[Vector3], undo_redo: EditorUndoRedoManager,
		action: String) -> void:
	# El lugar es respecto de la raíz; el padre puede estar corrido o girado.
	var from_parent := from_root(parent, root).affine_inverse()
	for i in nodes.size():
		nodes[i].transform = from_parent * Transform3D(Basis.IDENTITY, spots[i])
	if undo_redo == null:
		for node in nodes:
			parent.add_child(node, true)
			node.owner = root
		return
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	for node in nodes:
		undo_redo.add_do_method(parent, &"add_child", node, true)
		undo_redo.add_do_method(node, &"set_owner", root)
		undo_redo.add_do_reference(node)
		undo_redo.add_undo_method(parent, &"remove_child", node)
	undo_redo.commit_action()


## Hasta `count` lugares libres para ítems en el piso de la zona, en el orden
## de las columnas: lejos de los otros ítems, de las cajas y de las paredes.
static func free_item_spots(root: Node, count: int) -> Array[Vector3]:
	var scene := _scan(root)
	var spots: Array[Vector3] = []
	for x: float in ITEM_COLUMNS:
		var z := ROW_START
		while z <= ROW_END + 0.001 and spots.size() < count:
			var spot := Vector2(x, z)
			if _point_free(spot, scene):
				spots.append(Vector3(x, 0.0, z))
				scene["items"].append(spot)
			z += ROW_STEP
	return spots


## Hasta `count` lugares libres para cajas de esas medidas (sin girar), con
## toda la caja sobre el piso y espacio alrededor para pararse.
static func free_box_spots(root: Node, size: Vector3, count: int) -> Array[Vector3]:
	var scene := _scan(root)
	var half := Vector2(size.x, size.z) / 2.0
	var spots: Array[Vector3] = []
	for x: float in BOX_COLUMNS:
		var z := ROW_START - 0.5
		while z <= ROW_END - 0.5 + 0.001 and spots.size() < count:
			var area := Rect2(Vector2(x, z) - half, half * 2.0)
			if _area_free(area, scene):
				spots.append(Vector3(x, 0.0, z))
				scene["boxes"].append(area)
			z += BOX_STEP
	return spots


## Lo que ya hay en la zona, visto desde arriba (x, z), respecto de la raíz.
static func _scan(root: Node) -> Dictionary:
	var scene := {"items": [], "boxes": [], "walls": [], "floors": []}
	_collect(root, root, scene)
	return scene


static func _collect(node: Node, root: Node, scene: Dictionary) -> void:
	for child in node.get_children():
		if child is InvPickupSpawn:
			var at := from_root(child, root).origin
			scene["items"].append(Vector2(at.x, at.z))
		elif child is InvContainer:
			var size: Vector3 = child.get(&"box_size")
			scene["boxes"].append(_top_view(from_root(child, root) * AABB(Vector3(-size.x / 2.0, 0.0, -size.z / 2.0), size)))
		elif child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var shape: BoxShape3D = (child as CollisionShape3D).shape
			var area: AABB = from_root(child, root) * AABB(-shape.size / 2.0, shape.size)
			if absf(area.end.y) <= FLOOR_TOP:
				scene["floors"].append(_top_view(area).grow(-FLOOR_MARGIN))
			elif area.end.y > FLOOR_TOP:
				# Lo que sobresale del piso: una pared, un escalón.
				scene["walls"].append(_top_view(area).grow(WALL_GAP))
		_collect(child, root, scene)


static func _top_view(box: AABB) -> Rect2:
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


static func _point_free(spot: Vector2, scene: Dictionary) -> bool:
	if not _on_floor(Rect2(spot, Vector2.ZERO), scene):
		return false
	for other: Vector2 in scene["items"]:
		if other.distance_to(spot) < ITEM_GAP:
			return false
	for area: Rect2 in scene["boxes"]:
		if area.grow(ITEM_GAP).has_point(spot):
			return false
	for wall: Rect2 in scene["walls"]:
		if wall.has_point(spot):
			return false
	return true


static func _area_free(area: Rect2, scene: Dictionary) -> bool:
	if not _on_floor(area, scene):
		return false
	var around := area.grow(BOX_GAP)
	for other: Vector2 in scene["items"]:
		if area.grow(ITEM_GAP).has_point(other):
			return false
	for box: Rect2 in scene["boxes"]:
		if around.intersects(box):
			return false
	for wall: Rect2 in scene["walls"]:
		if around.intersects(wall):
			return false
	return true


## Si toda el área está sobre un mismo piso (ya achicado por el margen).
static func _on_floor(area: Rect2, scene: Dictionary) -> bool:
	for floor_area: Rect2 in scene["floors"]:
		if floor_area.encloses(area):
			return true
	return false


## Dónde está un nodo respecto de la raíz de la escena, sin depender de que
## esté en el árbol.
static func from_root(node: Node, root: Node) -> Transform3D:
	var place := Transform3D.IDENTITY
	var current := node
	while current != null and current != root:
		if current is Node3D:
			place = (current as Node3D).transform * place
		current = current.get_parent()
	return place
