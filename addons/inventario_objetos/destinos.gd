@tool
extends RefCounted

## Dónde lee y escribe el panel Objetos, en un solo lugar: las carpetas de los
## ítems y de los contenedores, el catálogo y la zona donde se colocan. Son los
## del laboratorio: su red (InvNet, el nodo Inventario de net_lab.tscn) usa ese
## catálogo y busca las cajas y los marcadores bajo su World Root, que es la
## zona. Para otro nivel haría falta su propio InvNet con su catálogo y su
## World Root; el panel no lo arma.

## Todo lo que crea el panel va adentro de esta carpeta.
const CONTENT_ROOT := "res://scenes/net_lab/inventario/"
const ITEMS_DIR := "res://scenes/net_lab/inventario/objetos"
const CONTAINERS_DIR := "res://scenes/net_lab/inventario/contenedores"
const CATALOG_PATH := "res://scenes/net_lab/inventario/catalogo_de_prueba.tres"
const ZONE_PATH := "res://scenes/net_lab/inventario/zona_de_inventario.tscn"
## El nodo de la zona donde van los marcadores de los ítems.
const ITEMS_NODE := "Objetos"
const LAB_PATH := "res://scenes/net_lab/net_lab.tscn"
## La caja de la que heredan los contenedores nuevos.
const BOX_BASE_PATH := "res://scenes/inventory/caja.tscn"
## El personaje, para la vista previa de lo que se lleva en la mano.
const ACTOR_PATH := "res://scenes/actor/actor.tscn"
const NET_SCRIPT_PATH := "res://scripts/inventory/inv_net.gd"


## Por qué la red del laboratorio no usaría este catálogo y esta zona, o "" si
## están conectados. Se lee la escena guardada del laboratorio, sin armarla.
static func check_lab() -> String:
	var net := _net_node()
	if net.is_empty():
		return "No encontré el nodo Inventario (InvNet) en %s." % LAB_PATH
	var state: SceneState = net["state"]
	var index: int = net["index"]
	var catalog: Variant = _node_property(state, index, &"catalog")
	if not catalog is Resource or (catalog as Resource).resource_path != CATALOG_PATH:
		return "El nodo Inventario de net_lab.tscn no usa %s como catálogo." % CATALOG_PATH.get_file()
	var root_path: Variant = _node_property(state, index, &"world_root")
	if not root_path is NodePath:
		return "El nodo Inventario de net_lab.tscn no tiene World Root: la red no buscaría las cajas ni los objetos."
	var target := _clean(String(state.get_node_path(index)).path_join(String(root_path)).simplify_path())
	for i in state.get_node_count():
		if _clean(String(state.get_node_path(i))) != target:
			continue
		var instance := state.get_node_instance(i)
		if instance != null and instance.resource_path == ZONE_PATH:
			return ""
		return "El World Root del nodo Inventario no es la zona (%s)." % ZONE_PATH.get_file()
	return "No encontré el World Root del nodo Inventario en net_lab.tscn."


## Columnas y filas de la grilla del jugador, como las arma la red del
## laboratorio (Player Columns y Player Rows del nodo Inventario).
static func player_grid() -> Vector2i:
	var net := _net_node()
	var script: Script = load(NET_SCRIPT_PATH)
	var columns: Variant = script.get_property_default_value(&"player_columns")
	var rows: Variant = script.get_property_default_value(&"player_rows")
	if not net.is_empty():
		var saved_columns: Variant = _node_property(net["state"], net["index"], &"player_columns")
		var saved_rows: Variant = _node_property(net["state"], net["index"], &"player_rows")
		columns = saved_columns if saved_columns != null else columns
		rows = saved_rows if saved_rows != null else rows
	return Vector2i(int(columns), int(rows))


## Si una ruta sirve para guardar algo nuevo del panel: adentro de
## CONTENT_ROOT, con esa extensión, un nombre de archivo válido, su carpeta
## existente (o `creatable`) y sin pisar otro archivo. "" si sirve.
static func check_new_path(path: String, extension: String, creatable: String = "") -> String:
	if not path.begins_with(CONTENT_ROOT) or path.contains(".."):
		return "La ruta tiene que estar adentro de %s." % CONTENT_ROOT
	if path.get_extension() != extension:
		return "El archivo tiene que terminar en .%s." % extension
	if not path.get_file().is_valid_filename() or path.get_file().get_basename() == "":
		return "El nombre del archivo no es válido."
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir) and dir != creatable:
		return "No existe la carpeta %s." % dir
	if FileAccess.file_exists(path) or ResourceLoader.exists(path):
		return "Ya existe %s: elegí otro nombre." % path.get_file()
	return ""


## Catálogo que el Inspector ofrece para los marcadores de net-lab.
static func lab_catalog() -> InvCatalog:
	var net := _net_node()
	if net.is_empty():
		return null
	return _node_property(net["state"], net["index"], &"catalog") as InvCatalog


static func _net_node() -> Dictionary:
	var lab := load(LAB_PATH) as PackedScene
	if lab == null:
		return {}
	var state := lab.get_state()
	for i in state.get_node_count():
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"script":
				var script := state.get_node_property_value(i, p) as Script
				if script != null and script.resource_path == NET_SCRIPT_PATH:
					return {"state": state, "index": i}
	return {}


static func _node_property(state: SceneState, index: int, property: StringName) -> Variant:
	for p in state.get_node_property_count(index):
		if state.get_node_property_name(index, p) == property:
			return state.get_node_property_value(index, p)
	return null


static func _clean(path: String) -> String:
	return path.trim_prefix("./").trim_prefix(".")
