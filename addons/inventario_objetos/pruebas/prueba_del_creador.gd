@tool
extends EditorPlugin

## Prueba del panel Objetos en el editor. Escribe archivos: se corre SOLO en
## una copia del proyecto, donde se le arma un plugin.cfg propio (en el
## proyecto de verdad no tiene, así que no aparece en la lista de plugins).
## Usa el panel de verdad, como lo usarías vos: escribe en sus campos, aprieta
## sus botones y revisa lo que quedó en el disco, en el catálogo y en la zona.
## Lo que pasa al jugar lo prueba después prueba_del_creador_juego.tscn, en la
## misma copia.
##
## --headless --editor --path <copia>   (con este plugin y el panel activados)

const Destinos := preload("../destinos.gd")
const Guardado := preload("../guardado.gd")
const PANEL_PLUGIN := "res://addons/inventario_objetos/plugin.cfg"

var panel: Node
var _checks := 0
var _failures := 0


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[creador] TIEMPO AGOTADO")
		get_tree().quit(2))
	await _frames(10)
	await _plugin_cycle()
	panel = _find_panel()
	_check(panel != null, "el panel está en el editor")
	if panel == null:
		_finish()
		return
	_check(Destinos.check_lab() == "", "el laboratorio usa el catálogo y la zona: %s" % Destinos.check_lab())
	_check(Destinos.player_grid() == Vector2i(12, 16), "la grilla del jugador se lee del laboratorio: %s" % Destinos.player_grid())
	await _search_list()
	await _help_bubbles()
	await _simple_item()
	await _rejections()
	await _consumable_and_equippable()
	await _edit_and_duplicate()
	await _thumbnail_arranging()
	await _pending_changes_dialog()
	await _containers()
	await _save_failures()
	_finish()


func _finish() -> void:
	print("[creador] %d comprobaciones, %d fallas" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Activar y desactivar ----------------------------------------------------------------

func _plugin_cycle() -> void:
	_check(_count_panels() == 1 and _panel_connections() == 1, "un solo panel al arrancar, con una conexión a FileSystem (%d, %d)" % [
			_count_panels(), _panel_connections()])
	EditorInterface.set_plugin_enabled(PANEL_PLUGIN, false)
	await _frames(3)
	_check(_count_panels() == 0 and _panel_connections() == 0, "desactivado, no queda el panel ni su conexión (%d, %d)" % [
			_count_panels(), _panel_connections()])
	EditorInterface.set_plugin_enabled(PANEL_PLUGIN, true)
	await _frames(3)
	EditorInterface.set_plugin_enabled(PANEL_PLUGIN, false)
	await _frames(3)
	EditorInterface.set_plugin_enabled(PANEL_PLUGIN, true)
	await _frames(3)
	_check(_count_panels() == 1 and _panel_connections() == 1, "activado dos veces más, sigue habiendo uno solo, con una conexión (%d, %d)" % [
			_count_panels(), _panel_connections()])


## Las conexiones de paneles Objetos a la señal de FileSystem.
func _panel_connections() -> int:
	var count := 0
	for connection in EditorInterface.get_resource_filesystem().filesystem_changed.get_connections():
		if (connection["callable"] as Callable).get_method() == &"_refresh_lists":
			count += 1
	return count


func _count_panels() -> int:
	return get_tree().root.find_children("PanelObjetos", "", true, false).size()


func _find_panel() -> Node:
	var found := get_tree().root.find_children("PanelObjetos", "", true, false)
	return found[0] if found.size() == 1 else null


# --- Buscador ------------------------------------------------------------------------------------

func _search_list() -> void:
	var search: LineEdit = panel._search
	var results: ItemList = panel._results
	var total: int = panel._entries.size()
	_check(total >= 10 and results.item_count == total, "sin buscar, la lista tiene todos los ítems (%d)" % total)
	for query in ["bater", "BATERÍA", "caja herr", "puerta_de", "tornillos.tres"]:
		_type(search, query)
		_check(results.item_count == 1, "«%s» encuentra uno: %s" % [query, _texts(results)])
	_type(search, "xyz123")
	_check(results.item_count == 0 and panel._results_note.text.contains("Ninguno coincide"), "algo que no existe: %s" % panel._results_note.text)
	_type(search, "llave")
	results.item_selected.emit(0)
	_check(panel._item_original != null and panel._item_original.resource_path.ends_with("llave.tres") and results.is_selected(0),
			"un clic en la lista lo abre y queda marcado")
	_type(search, "tornillos")
	search.text_submitted.emit("tornillos")
	_check(panel._item_original != null and panel._item_original.resource_path.ends_with("tornillos.tres"), "Enter abre el primero")
	panel._on_tab(1)  # contenedores
	_check(search.text == "" and _texts(results).has("Caja base (caja.tscn) · solo para duplicar"),
			"en contenedores la búsqueda arranca vacía y aparece la caja base: %s" % _texts(results))
	panel._on_tab(0)  # ítems
	# Con muchos, muestra los primeros 200 y lo dice.
	for i in 500:
		panel._add_entry("Piedra %d" % i, "res://piedra_%d.tres" % i, "piedra_%d" % i)
	_type(search, "piedra")
	_check(results.item_count == 200 and panel._results_note.text.contains("500 de") and panel._results_note.text.contains("primeros 200"),
			"con 500 que coinciden, muestra 200 y lo dice: %s" % panel._results_note.text)
	_type(search, "piedra 437")
	_check(results.item_count == 1 and _texts(results)[0].begins_with("Piedra 437 "), "y buscando más, se achica: %s" % [_texts(results)])
	_type(search, "")
	panel._refresh_lists()
	_check(results.item_count == total, "al volver a leer, quedan los de verdad")
	panel.new_item()


func _texts(list: ItemList) -> Array:
	var out := []
	for i in list.item_count:
		out.append(list.get_item_text(i))
	return out


# --- 1 y 2. Un ítem simple, apilable, colocado en pilas ----------------------------------------

func _simple_item() -> void:
	var form = panel._item_form
	panel.new_item()
	_check(not panel.is_dirty(), "un ítem nuevo sin tocar no tiene cambios")
	_type(form._name, "Cuerda de prueba")
	_check(form._id.text == "cuerda_de_prueba" and form.path == Destinos.ITEMS_DIR.path_join("cuerda_de_prueba.tres"),
			"el ID y el archivo salen del nombre: %s, %s" % [form._id.text, form.path])
	form._height.value = 3
	form._stacks.button_pressed = true
	form._stack_size.value = 5
	_check(panel.is_dirty() and panel._place_button.disabled, "con cambios: no se coloca hasta guardar")
	var catalog_before := _catalog_ids()
	var result: Dictionary = panel.save_current(false)
	_check(result["ok"], "guardar la cuerda: %s" % result["message"])
	var path := Destinos.ITEMS_DIR.path_join("cuerda_de_prueba.tres")
	_check(FileAccess.file_exists(path), "quedó su .tres")
	var ids := _catalog_ids()
	_check(ids.count("cuerda_de_prueba") == 1 and ids.size() == catalog_before.size() + 1, "está una sola vez en el catálogo")
	var catalog_text := FileAccess.get_file_as_string(Destinos.CATALOG_PATH)
	_check(catalog_text.contains('path="%s"' % path) and not catalog_text.contains('id = &"cuerda_de_prueba"'),
			"el catálogo apunta al archivo, sin una copia adentro")
	_check(not panel.is_dirty() and not panel._place_button.disabled, "guardado: sin cambios y se puede colocar")
	_check(not Destinos.ZONE_PATH in EditorInterface.get_unsaved_scenes() and _markers_of("cuerda_de_prueba", _zone_file()).is_empty(),
			"guardar no pone nada en la zona")
	result = panel.place_current(0, {})
	_check(not result["ok"], "con 0 unidades no se coloca: %s" % result["message"])
	result = panel.place_current(12, {})
	_check(result["ok"], "colocar 12: %s" % result["message"])
	var placed: Array = panel.last_placed
	var amounts := placed.map(func(node: Node) -> int: return node.get(&"quantity"))
	_check(amounts == [5, 5, 2], "12 de a 5 son pilas de 5, 5 y 2: %s" % [amounts])
	var root := EditorInterface.get_edited_scene_root()
	_check(root != null and root.scene_file_path == Destinos.ZONE_PATH, "la zona quedó abierta")
	_check(placed.all(func(node: Node) -> bool: return node.owner == root and node.get_parent() == root.get_node("Objetos")),
			"los marcadores son de la zona, en Objetos")
	_check(EditorInterface.get_selection().get_selected_nodes().size() == 3, "y quedaron seleccionados")
	_check(Destinos.ZONE_PATH in EditorInterface.get_unsaved_scenes(), "la zona quedó sin guardar (no se guarda sola)")
	_check(_markers_of("cuerda_de_prueba", _zone_file()).is_empty(), "y en el disco todavía no están")
	# Deshacer y rehacer.
	var history := _history(root)
	history.undo()
	_check(placed.all(func(node: Node) -> bool: return not node.is_inside_tree()), "Ctrl+Z saca los marcadores")
	_check(FileAccess.file_exists(path) and _catalog_ids().count("cuerda_de_prueba") == 1, "y no borra el .tres ni lo saca del catálogo")
	history.redo()
	_check(placed.all(func(node: Node) -> bool: return node.is_inside_tree() and node.owner == root), "Ctrl+Y los vuelve a poner")
	panel._on_save_zone()
	var saved := _markers_of("cuerda_de_prueba", _zone_file())
	_check(saved.size() == 3, "guardada la zona, están los 3 en el disco (%d)" % saved.size())
	_check(_zone_file().contains('path="%s"' % path), "apuntando al .tres")
	EditorInterface.close_scene()
	EditorInterface.open_scene_from_path(Destinos.ZONE_PATH)
	root = EditorInterface.get_edited_scene_root()
	var reopened := root.find_children("CuerdaDePrueba*", "", true, false)
	var total := 0
	for node in reopened:
		total += int(node.get(&"quantity"))
		_check(node.get(&"item") != null and node.get(&"item").resource_path == path, "%s apunta al .tres al reabrir" % node.name)
	_check(reopened.size() == 3 and total == 12, "cerrada y reabierta: 3 marcadores, 12 unidades en total (%d, %d)" % [reopened.size(), total])


# --- 7. Rechazos sin escrituras -----------------------------------------------------------------

func _rejections() -> void:
	var form = panel._item_form
	var files_before := _files(Destinos.ITEMS_DIR)
	var catalog_before := FileAccess.get_file_as_string(Destinos.CATALOG_PATH)
	panel.new_item()
	_type(form._name, "Cuerda de prueba")
	var result: Dictionary = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("Ya hay un objeto"), "ID repetido: %s" % result["message"])
	panel.new_item()
	_type(form._name, "Algo")
	_type(form._id, "Algo Raro!")
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("El ID"), "ID inválido: %s" % result["message"])
	panel.new_item()
	_type(form._name, "   ")
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("nombre"), "sin nombre: %s" % result["message"])
	panel.new_item()
	_type(form._name, "Piedra enorme")
	form._width.value = 0
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("celdas"), "tamaño 0: %s" % result["message"])
	panel.new_item()
	_type(form._name, "Piedra con estado")
	form._state._add_row("", 3)
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("sin nombre"), "un dato del estado sin nombre: %s" % result["message"])
	panel.new_item()
	_type(form._name, "Piedra con estado raro")
	_check(Guardado.check_state({"carga": NAN}) != "" and Guardado.check_state({"nodo": Node3D}) != ""
			and Guardado.check_state({1: 2}) != "" and Guardado.check_state({"carga": 100, "lista": [1, "a"]}) == "",
			"el estado rechaza números rotos, objetos y nombres que no son texto")
	panel.new_item()
	_type(form._name, "Cuerda de prueba otra")
	_type(form._path_edit, "res://scenes/otra_carpeta/cuerda.tres")
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("adentro de"), "ruta fuera de la carpeta: %s" % result["message"])
	panel.new_item()
	_type(form._name, "Cuerda de prueba otra")
	_type(form._path_edit, Destinos.ITEMS_DIR.path_join("botella.tres"))
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("Ya existe"), "no pisa otro archivo: %s" % result["message"])
	# Sin lugar: 500 piedras sin apilar no entran.
	panel.new_item()
	_type(form._name, "Piedra de prueba")
	result = panel.save_current(false)
	_check(result["ok"], "guardar la piedra: %s" % result["message"])
	var root := EditorInterface.get_edited_scene_root()
	var children := root.get_node("Objetos").get_child_count()
	result = panel.place_current(500, {})
	_check(not result["ok"] and result["message"].contains("hay lugar para"), "500 piedras no entran: %s" % result["message"])
	_check(root.get_node("Objetos").get_child_count() == children and not Destinos.ZONE_PATH in EditorInterface.get_unsaved_scenes(),
			"y no se colocó ninguna (ni quedó la zona sin guardar)")
	var after := _files(Destinos.ITEMS_DIR)
	_check(after.size() == files_before.size() + 1 and after.has(Destinos.ITEMS_DIR.path_join("piedra_de_prueba.tres")),
			"de los rechazos no quedó ningún archivo (solo la piedra que sí se guardó)")
	_check(_catalog_ids().count("piedra_de_prueba") == 1 and _catalog_ids().count("cuerda_de_prueba") == 1
			and FileAccess.get_file_as_string(Destinos.CATALOG_PATH) != catalog_before, "el catálogo solo sumó la piedra")


# --- 3 y 4. Consumible y equipable con valores propios -------------------------------------------

func _consumable_and_equippable() -> void:
	var form = panel._item_form
	panel.new_item()
	_type(form._name, "Termo de café")
	form._stacks.button_pressed = true
	form._stack_size.value = 3
	form._add_use.pressed.emit()
	# Desde el 2026-11-02: efecto en la salud (cura o daña) y estamina que recupera.
	# Y desde la tarde, el daño en el tiempo: sus puntos y en cuántos segundos.
	# Y desde el 2026-11-06, lo que cura de una parte del cuerpo.
	var effects: Array = form._abilities.find_children("*", "EditorSpinSlider", true, false)
	_check(effects.size() == 5, "el consumible tiene cinco números: salud, estamina, daño en el tiempo, segundos y partes del cuerpo (hay %d)"
			% effects.size())
	effects[0].value = 0
	effects[1].value = 0
	var result: Dictionary = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("no hace nada")
			and not FileAccess.file_exists(Destinos.ITEMS_DIR.path_join("termo_de_cafe.tres")),
			"un consumible que no hace nada no se guarda: %s" % result["message"])
	effects[0].value = -20000
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("efecto en la salud"), "un daño fuera de rango no se guarda: %s" % result["message"])
	effects[0].value = 7
	effects[1].value = 3
	form._shape.select(2)
	form._shape.item_selected.emit(2)
	result = panel.save_current(false)
	_check(result["ok"], "guardar el termo: %s" % result["message"])
	var termo: Resource = load(Destinos.ITEMS_DIR.path_join("termo_de_cafe.tres"))
	var use: Resource = termo.get(&"abilities")[0]
	_check(Guardado.ability_kind(use) == "consumible" and use.get(&"health") == 7 and use.get(&"stamina") == 3,
			"el termo cura 7 de salud y recupera 3 de estamina")
	_check(termo.get(&"mesh") is CylinderMesh, "y se ve como un cilindro")
	result = panel.place_current(2, {})
	_check(result["ok"] and panel.last_placed.size() == 1, "2 termos en una pila: %s" % result["message"])
	# Uno que daña (2026-11-02): salud negativa, sin estamina.
	panel.new_item()
	_type(form._name, "Veneno de prueba")
	form._add_use.pressed.emit()
	effects = form._abilities.find_children("*", "EditorSpinSlider", true, false)
	effects[0].value = -30
	effects[1].value = 0
	# Y además 10 de a poco, en un segundo. Sin segundos no se guarda.
	effects[2].value = 10
	effects[3].value = 0.0
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("dura de 0,1"), "un daño en el tiempo sin duración no se guarda: %s" % result["message"])
	effects[3].value = 1.0
	var summary := ""
	for label: Label in form._abilities.find_children("*", "Label", true, false):
		if label.text.begins_with("Al usar una unidad"):
			summary = label.text
	_check(summary.contains("quita 30 de salud") and summary.contains("quita 10 de salud de a poco en 1 s, 10 por segundo"),
			"el panel dice lo que hace: %s" % summary)
	result = panel.save_current(false)
	var poison: Resource = load(Destinos.ITEMS_DIR.path_join("veneno_de_prueba.tres"))
	var poison_use: Resource = poison.get(&"abilities")[0]
	_check(result["ok"] and poison_use.get(&"health") == -30 and poison_use.get(&"damage_over_time") == 10
			and is_equal_approx(poison_use.get(&"damage_seconds"), 1.0),
			"guardar el veneno, que quita 30 de golpe y 10 en 1 s: %s" % result["message"])
	result = panel.place_current(1, {})
	_check(result["ok"], "colocar un veneno: %s" % result["message"])
	# Uno que solo cura partes del cuerpo (2026-11-06): 30 por unidad, sin salud.
	panel.new_item()
	_type(form._name, "Venda de prueba")
	form._stacks.button_pressed = true
	form._stack_size.value = 5
	form._add_use.pressed.emit()
	effects = form._abilities.find_children("*", "EditorSpinSlider", true, false)
	effects[0].value = 0
	effects[4].value = 150.0
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("parte del cuerpo va de 0 a 100")
			and not FileAccess.file_exists(Destinos.ITEMS_DIR.path_join("venda_de_prueba.tres")),
			"curar 150 %% de una parte no se guarda: %s" % result["message"])
	effects[4].value = 30.0
	summary = ""
	for label: Label in form._abilities.find_children("*", "Label", true, false):
		if label.text.contains("parte dañada"):
			summary = label.text
	_check(summary.begins_with("Usado normal (menú o barra rápida) no hace nada") and summary.contains("le devuelve 30 % (sin pasar del 100 %)"),
			"el panel dice que solo cura partes, 30 %%: %s" % summary)
	result = panel.save_current(false)
	_check(result["ok"], "un consumible que solo cura partes se guarda: %s" % result["message"])
	var bandage: Resource = load(Destinos.ITEMS_DIR.path_join("venda_de_prueba.tres"))
	var bandage_use: Resource = bandage.get(&"abilities")[0] if bandage != null else null
	_check(bandage_use != null and bandage_use.get(&"health") == 0 and is_equal_approx(bandage_use.get(&"part_repair"), 30.0),
			"la venda guarda 30 % para una parte y 0 de salud")
	result = panel.place_current(3, {})
	_check(result["ok"] and panel.last_placed.size() == 1, "3 vendas en una pila: %s" % result["message"])
	# Al abrir de nuevo un objeto guardado, el número está ahí (el botiquín, 100).
	panel.open_item(Destinos.ITEMS_DIR.path_join("botiquin.tres"))
	effects = form._abilities.find_children("*", "EditorSpinSlider", true, false)
	_check(effects.size() == 5 and is_equal_approx(effects[4].value, 100.0), "el botiquín abierto muestra que deja entera una parte (%s)"
			% (effects[4].value if effects.size() == 5 else "sin el número"))
	panel.new_item()
	_type(form._name, "Soga de prueba")
	form._height.value = 2
	form._add_equip.pressed.emit()
	var spins: Array = form._abilities.find_children("*", "EditorSpinSlider", true, false)
	# Posición x, y, z; giro x, y, z; tamaño.
	var values := [0.2, 1.1, -0.3, 0.0, 45.0, 0.0, 0.4]
	for i in values.size():
		spins[i].value = values[i]
	form._add_use.pressed.emit()
	var rows: Array = form._abilities.get_children()
	_check(rows.size() == 2 and rows[0].find_children("*", "Label", true, false)[0].text.contains("barra rápida"),
			"la primera capacidad dice que es la de la barra rápida")
	_check(form._add_use.disabled and form._add_equip.disabled, "no se puede sumar otra del mismo tipo")
	# La saca: queda solo el equipable.
	var remove: Button = rows[1].find_children("*", "Button", true, false)[2]
	remove.pressed.emit()
	result = panel.save_current(false)
	_check(result["ok"], "guardar la soga: %s" % result["message"])
	var soga: Resource = load(Destinos.ITEMS_DIR.path_join("soga_de_prueba.tres"))
	var equip: Resource = soga.get(&"abilities")[0]
	_check(soga.get(&"abilities").size() == 1 and Guardado.ability_kind(equip) == "equipable"
			and equip.get(&"hold_offset").is_equal_approx(Vector3(0.2, 1.1, -0.3))
			and equip.get(&"hold_rotation").is_equal_approx(Vector3(0, 45, 0)) and is_equal_approx(equip.get(&"hold_size"), 0.4),
			"la soga guarda su posición, giro y tamaño en la mano")
	result = panel.place_current(1, {})
	_check(result["ok"], "colocar la soga: %s" % result["message"])
	panel._on_save_zone()


# --- 5. Editar y duplicar ---------------------------------------------------------------------------

func _edit_and_duplicate() -> void:
	var form = panel._item_form
	# Un dato que el panel no muestra: tiene que seguir ahí después de guardar.
	var battery_path := Destinos.ITEMS_DIR.path_join("bateria.tres")
	var battery: Resource = load(battery_path)
	battery.set_meta(&"nota_de_prueba", "se conserva")
	ResourceSaver.save(battery, battery_path)
	var uid_before := ResourceLoader.get_resource_uid(battery_path)
	var zone_before := _zone_file()
	panel.open_item(battery_path)
	_check(not panel.is_dirty(), "abrir la batería no inventa cambios")
	_check(not form._id.editable and not form._path_edit.editable, "el ID y el archivo de lo ya creado no se editan")
	form._description.text = "Descripción cambiada desde el panel."
	form._description.text_changed.emit()
	_check(battery.get(&"description") != "Descripción cambiada desde el panel.", "mientras se escribe, el original no cambia")
	var result: Dictionary = panel.save_current(false)
	_check(result["ok"], "guardar la batería: %s" % result["message"])
	var text := FileAccess.get_file_as_string(battery_path)
	_check(ResourceLoader.get_resource_uid(battery_path) == uid_before and load(battery_path) == battery,
			"conserva su uid y es el mismo recurso")
	_check(text.contains("Descripción cambiada") and text.contains("nota_de_prueba") and text.contains('"carga": 100')
			and text.contains('id = &"bateria"'), "guardó la descripción y conservó su ID, su estado y lo que el panel no muestra")
	_check(_zone_file() == zone_before, "la zona no cambió")
	_check(_catalog_ids().count("bateria") == 1, "sigue una vez en el catálogo")
	# El ID no se cambia ni a la fuerza.
	panel._item_draft.set(&"id", &"bateria_nueva")
	result = panel.save_current(false)
	_check(not result["ok"] and FileAccess.get_file_as_string(battery_path) == text, "cambiar el ID de algo creado se rechaza")
	panel.discard()
	_check(not panel.is_dirty() and String(panel._item_draft.get(&"id")) == "bateria", "descartar vuelve a lo guardado")
	# Descartar no escribe.
	var machete_path := Destinos.ITEMS_DIR.path_join("machete.tres")
	var machete_text := FileAccess.get_file_as_string(machete_path)
	panel.open_item(machete_path)
	_type(form._name, "Machetazo")
	form._width.value = 2
	_check(panel.is_dirty(), "cambiado el machete, hay cambios")
	panel.discard()
	_check(not panel.is_dirty() and FileAccess.get_file_as_string(machete_path) == machete_text
			and load(machete_path).get(&"display_name") == "Machete", "descartar no toca el archivo ni el recurso")
	# Cambió por afuera: se avisa antes de pisarlo.
	var bottle_path := Destinos.ITEMS_DIR.path_join("botella.tres")
	panel.open_item(bottle_path)
	var bottle: Resource = load(bottle_path)
	bottle.set(&"description", "Cambiada en el Inspector.")
	_type(form._name, "Botella de agua fría")
	result = panel.save_current(false)
	_check(not result["ok"] and result.has("confirm") and result["confirm"].contains("cambió desde que lo abriste"),
			"si cambió por afuera, pregunta antes: %s" % result.get("confirm", ""))
	_check(not FileAccess.get_file_as_string(bottle_path).contains("Botella de agua fría"), "y no guardó")
	result = panel.save_current(true)
	_check(result["ok"] and FileAccess.get_file_as_string(bottle_path).contains("Botella de agua fría"), "confirmado, guarda")
	# Bajar el límite de una pila colocada: se avisa, no se recorta.
	var screws_path := Destinos.ITEMS_DIR.path_join("tornillos.tres")
	var screws_text := FileAccess.get_file_as_string(screws_path)
	panel.open_item(screws_path)
	form._stack_size.value = 10
	result = panel.save_current(false)
	_check(not result["ok"] and result.get("confirm", "").contains("Tornillos20a"), "bajar el límite avisa por los marcadores de 20: %s" % result.get("confirm", ""))
	_check(FileAccess.get_file_as_string(screws_path) == screws_text and _zone_file().contains("quantity = 20"),
			"y no cambió nada (ni el .tres ni las cantidades de la zona)")
	panel.discard()
	# Duplicar: otra identidad, otro archivo; lo que se edita en la copia no cambia el original.
	var torch_path := Destinos.ITEMS_DIR.path_join("linterna.tres")
	var torch_text := FileAccess.get_file_as_string(torch_path)
	var torch: Resource = load(torch_path)
	panel.open_item(torch_path)
	panel.duplicate_current()
	_check(panel.is_dirty() and form._id.editable and String(panel._item_draft.get(&"id")) == "linterna_copia",
			"la copia es nueva, con otro ID: %s" % panel._item_draft.get(&"id"))
	var copy: Resource = panel._item_draft
	_check(copy.get(&"abilities")[0] != torch.get(&"abilities")[0] and copy.get(&"mesh") != torch.get(&"mesh"),
			"la copia tiene su propia capacidad y su propia malla")
	var hold: EditorSpinSlider = form._abilities.find_children("*", "EditorSpinSlider", true, false)[6]
	hold.value = 0.9
	form._dims.get_child(1).value = 0.2
	form._state._add_row("pila", 3)
	form._state.changed.emit()
	result = panel.save_current(false)
	_check(result["ok"], "guardar la copia: %s" % result["message"])
	var copy_path := Destinos.ITEMS_DIR.path_join("linterna_copia.tres")
	var saved_copy: Resource = load(copy_path)
	_check(is_equal_approx(saved_copy.get(&"abilities")[0].get(&"hold_size"), 0.9) and saved_copy.get(&"default_state") == {"pila": 3},
			"la copia guardó lo suyo")
	_check(FileAccess.get_file_as_string(torch_path) == torch_text and is_equal_approx(torch.get(&"abilities")[0].get(&"hold_size"), 0.3)
			and is_equal_approx(torch.get(&"mesh").get(&"top_radius"), 0.05) and torch.get(&"default_state").is_empty(),
			"el original quedó igual, en el disco y en memoria")
	_check(_catalog_ids().count("linterna_copia") == 1 and _catalog_ids().count("linterna") == 1, "los dos en el catálogo, una vez cada uno")
	# Seguir editando lo recién guardado no toca lo guardado hasta guardar.
	hold = form._abilities.find_children("*", "EditorSpinSlider", true, false)[6]
	hold.value = 1.5
	_check(is_equal_approx(saved_copy.get(&"abilities")[0].get(&"hold_size"), 0.9), "después de guardar, el borrador es otra copia")
	panel.discard()


# --- Acomodar la miniatura -------------------------------------------------------------------------
# Sin pantalla no hay imagen: acá se prueban los valores que escribe. El
# arrastre con el mouse y que la imagen no salte se prueban con ventana.

func _thumbnail_arranging() -> void:
	var form = panel._item_form
	var arranger = form._arranger
	var door_path := Destinos.ITEMS_DIR.path_join("machete.tres")
	panel.open_item(door_path)
	var draft: Resource = panel._item_draft
	_check(draft.get(&"thumbnail_auto_align") and draft.get(&"thumbnail_rotation") == Vector3(-20, 35, 0),
			"el machete arranca con la miniatura automática")
	arranger.face_front()
	arranger.changed.emit()
	_check(draft.get(&"thumbnail_rotation") == Vector3.ZERO and not draft.get(&"thumbnail_auto_align") and panel.is_dirty(),
			"De frente: sin giro, deja de acostarse solo y cuenta como cambio")
	arranger.turn(Vector3.BACK, 90.0)
	_check(draft.get(&"thumbnail_rotation").is_equal_approx(Vector3(0, 0, 90)), "↺ 90°: gira en la pantalla (%s)" % draft.get(&"thumbnail_rotation"))
	arranger._drag_turn(Vector2(30, 0), false)
	var expected := Basis(Vector3.UP, deg_to_rad(30)) * Basis(Vector3.BACK, deg_to_rad(90))
	_check(_same(_basis_of(draft), expected), "arrastrar de costado lo gira alrededor del eje vertical de la pantalla")
	var before: Vector3 = draft.get(&"thumbnail_rotation")
	arranger._drag_turn(Vector2(10, 0), true)
	var after_small: Vector3 = draft.get(&"thumbnail_rotation")
	arranger._drag_turn(Vector2(10, 0), true)
	_check(after_small == before and _same(_basis_of(draft), Basis(Vector3.UP, deg_to_rad(15)) * expected),
			"con Ctrl gira de a 15°: 10° no alcanzan, 20° dan 15°")
	arranger.shift_by(Vector2(0.25, -0.1))
	arranger.zoom_by(1.1)
	_check(draft.get(&"thumbnail_offset").is_equal_approx(Vector2(0.25, -0.1)) and is_equal_approx(draft.get(&"thumbnail_zoom"), 1.1),
			"correrlo y acercarlo: %s, %s" % [draft.get(&"thumbnail_offset"), draft.get(&"thumbnail_zoom")])
	var result: Dictionary = panel.save_current(false)
	var text := FileAccess.get_file_as_string(door_path)
	_check(result["ok"] and text.contains("thumbnail_offset = Vector2(0.25, -0.1)") and text.contains("thumbnail_auto_align = false")
			and text.contains("thumbnail_zoom = 1.1"), "se guarda como quedó: %s" % result["message"])
	_check(load(door_path).get(&"thumbnail_offset").is_equal_approx(Vector2(0.25, -0.1)), "y el recurso del juego lo tiene")
	form._arranger.center()
	_check(panel._item_draft.get(&"thumbnail_offset") == Vector2.ZERO and panel._item_draft.get(&"thumbnail_zoom") == 1.0, "Centrar")
	panel._item_draft.set(&"thumbnail_offset", Vector2(2, 0))
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("fuera del cuadro"), "corrido fuera del cuadro se rechaza: %s" % result["message"])
	form._arranger.automatic()
	result = panel.save_current(false)
	text = FileAccess.get_file_as_string(door_path)
	_check(result["ok"] and not text.contains("thumbnail_offset") and not text.contains("thumbnail_auto_align")
			and not text.contains("thumbnail_rotation") and not text.contains("thumbnail_zoom"), "Automático vuelve a los valores de fábrica")


## Dos giros iguales, salvo el redondeo a décimas de grado.
func _same(a: Basis, b: Basis) -> bool:
	return (a.x - b.x).length() < 0.01 and (a.y - b.y).length() < 0.01 and (a.z - b.z).length() < 0.01


func _basis_of(def: Resource) -> Basis:
	var degrees: Vector3 = def.get(&"thumbnail_rotation")
	return Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)))


# --- Cambios sin guardar al cambiar de selección ------------------------------------------------------

func _pending_changes_dialog() -> void:
	var form = panel._item_form
	var key_path := Destinos.ITEMS_DIR.path_join("llave.tres")
	var key_text := FileAccess.get_file_as_string(key_path)
	panel.open_item(key_path)
	_type(form._name, "Llave cambiada")
	panel._box_tab.button_pressed = true
	panel._box_tab.pressed.emit()
	await _frames(2)
	var dialog := _pending_dialog()
	_check(dialog != null and panel._mode == 0, "con cambios, cambiar de pestaña pregunta antes")
	if dialog != null:
		dialog.get_cancel_button().pressed.emit()
	for i in 30:
		if _pending_dialog() == null:
			break
		await _frames(1)
	_check(_pending_dialog() == null, "Cancelar cierra el diálogo")
	_check(panel._mode == 0 and panel._item_tab.button_pressed and not panel._box_tab.button_pressed and panel.is_dirty()
			and form._name.text == "Llave cambiada", "Cancelar deja todo como estaba, con lo escrito")
	# Las otras dos respuestas, por la misma función que llama el diálogo.
	panel.resolve_pending("descartar", panel._set_mode.bind(1), panel._restore_tab)
	_check(panel._mode == 1 and FileAccess.get_file_as_string(key_path) == key_text
			and load(key_path).get(&"display_name") == "Llave", "Descartar cambia de pestaña sin escribir nada")
	panel._on_tab(0)  # ítems
	panel.open_item(key_path)
	_type(form._name, "Llave de la prueba")
	panel.resolve_pending("guardar", panel.new_item, Callable())
	_check(FileAccess.get_file_as_string(key_path).contains("Llave de la prueba") and panel._item_original == null,
			"Guardar guarda y después hace lo pedido (un ítem nuevo)")


## El diálogo de cambios sin guardar que está a la vista, o null.
func _pending_dialog() -> ConfirmationDialog:
	for node in get_tree().root.find_children("*", "ConfirmationDialog", true, false):
		var dialog := node as ConfirmationDialog
		if dialog.visible and dialog.title == "Cambios sin guardar":
			return dialog
	return null


# --- 6. Contenedores -------------------------------------------------------------------------------

func _containers() -> void:
	var form = panel._box_form
	panel._on_tab(1)  # contenedores
	_check(panel._mode == 1 and form.visible and not panel._item_form.visible, "pestaña de contenedores")
	panel.new_box()
	_type(form._name, "Armario de prueba")
	_check(form._node_name.text == "ArmarioDePrueba" and form.path == Destinos.CONTAINERS_DIR.path_join("armario_de_prueba.tscn"),
			"el nodo y la escena salen del nombre: %s, %s" % [form._node_name.text, form.path])
	form._columns.value = 3
	form._rows.value = 2
	form._size[0].value = 0.9
	form._size[1].value = 1.6
	form._size[2].value = 0.5
	form._reach.value = 0.4
	var result: Dictionary = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("no se abre desde ningún lado"), "un alcance que no llega se rechaza: %s" % result["message"])
	_check(not DirAccess.dir_exists_absolute(Destinos.CONTAINERS_DIR), "y no se creó ni la carpeta")
	form._reach.value = 1.6
	result = panel.save_current(false)
	_check(result["ok"], "guardar el armario: %s" % result["message"])
	var path := Destinos.CONTAINERS_DIR.path_join("armario_de_prueba.tscn")
	var text := FileAccess.get_file_as_string(path)
	_check(text.contains('path="%s"' % Destinos.BOX_BASE_PATH) and text.contains("instance=ExtResource") and text.contains("columns = 3"),
			"la escena hereda de caja.tscn y guarda sus valores")
	var scene: PackedScene = load(path)
	var probe := scene.instantiate()
	_check(Guardado.check_box_node(probe) == "" and probe.get(&"inventory").name == "Inventario", "reabierta, su Inventory apunta a su InvInventory")
	probe.free()
	result = panel.place_current(2, {})
	_check(result["ok"] and panel.last_placed.size() == 2, "colocar 2 armarios: %s" % result["message"])
	var boxes: Array = panel.last_placed
	if boxes.size() == 2:
		_check(boxes[0].scene_file_path == path and boxes[1].scene_file_path == path, "son instancias de la escena")
		_check(boxes[0].get(&"inventory") != boxes[1].get(&"inventory"), "cada armario tiene su propio Inventario")
		var a: Vector3 = boxes[0].position
		var b: Vector3 = boxes[1].position
		_check(Vector2(a.x - b.x, a.z - b.z).length() > 1.0, "no se pisan: %s y %s" % [a, b])
	var history := _history(EditorInterface.get_edited_scene_root())
	history.undo()
	_check(boxes.all(func(node: Node) -> bool: return not node.is_inside_tree()) and FileAccess.file_exists(path),
			"Ctrl+Z saca las cajas pero no borra la escena")
	history.redo()
	panel._on_save_zone()
	_check(_zone_file().count('instance=ExtResource("') >= 4 and _zone_file().contains(path), "guardada la zona, están las dos cajas")
	# Editar el contenedor: cambia en su escena y en las cajas colocadas, sin
	# dejar el valor viejo pegado en la zona.
	var uid_before := ResourceLoader.get_resource_uid(path)
	panel.open_box(path)
	form._columns.value = 4
	result = panel.save_current(false)
	_check(result["ok"], "guardar el armario con 4 columnas: %s" % result["message"])
	await _frames(5)
	_check(FileAccess.get_file_as_string(path).contains("columns = 4") and ResourceLoader.get_resource_uid(path) == uid_before,
			"su escena tiene 4 columnas y el mismo uid")
	var zone := EditorInterface.get_edited_scene_root()
	_check(zone != null and zone.scene_file_path == Destinos.ZONE_PATH, "el editor volvió a la zona")
	var placed := zone.find_children("ArmarioDePrueba*", "", false, false)
	_check(placed.size() == 2 and placed.all(func(node: Node) -> bool: return node.get(&"columns") == 4),
			"las cajas colocadas ya tienen 4 columnas: %s" % [placed.map(func(node: Node) -> int: return node.get(&"columns"))])
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.save_scene()
	_check(not _zone_file().contains("columns = 3"), "guardar la zona no deja pegado el valor viejo")
	# Con la zona sin guardar, no se recarga (se perdería ese trabajo): se avisa.
	await _frames(5)
	EditorInterface.open_scene_from_path(Destinos.ZONE_PATH)
	# Un cambio de verdad, con el deshacer, como moverlo en la vista 3D.
	var moved: Node3D = EditorInterface.get_edited_scene_root().get_node("Objetos").get_child(0)
	var manager := EditorInterface.get_editor_undo_redo()
	manager.create_action("Mover un marcador (prueba)", UndoRedo.MERGE_DISABLE, EditorInterface.get_edited_scene_root())
	manager.add_do_property(moved, &"position", moved.position + Vector3(0, 0, 0.1))
	manager.add_undo_property(moved, &"position", moved.position)
	manager.commit_action()
	await _frames(2)
	# El editor puede volver a armar la zona por su cuenta (con los cambios): se
	# busca el marcador por nombre, no por el nodo.
	var moved_name := moved.name
	var moved_to := moved.position
	_check(Destinos.ZONE_PATH in EditorInterface.get_unsaved_scenes(), "(preparación) la zona quedó marcada sin guardar: %s, a la vista %s" % [
			EditorInterface.get_unsaved_scenes(), EditorInterface.get_edited_scene_root().scene_file_path])
	panel.open_box(path)
	form._rows.value = 3
	result = panel.save_current(false)
	_check(result["ok"] and result["message"].contains("zona_de_inventario.tscn tiene cambios sin guardar"),
			"con la zona sin guardar, avisa: %s" % result["message"])
	await _frames(5)
	var now := EditorInterface.get_edited_scene_root().get_node_or_null(NodePath("Objetos/" + moved_name)) as Node3D
	_check(now != null and now.position.is_equal_approx(moved_to), "el cambio de la zona sigue en el editor")
	_check(Destinos.ZONE_PATH in EditorInterface.get_unsaved_scenes(), "y la zona sigue marcada sin guardar")
	EditorInterface.open_scene_from_path(Destinos.ZONE_PATH)
	EditorInterface.save_scene()
	_check(not _zone_file().contains("rows = 2"), "guardarla no deja pegadas las filas viejas")
	_check(_zone_file().contains("-3, 0, -4.9)"), "y guardada, el marcador movido quedó en su lugar nuevo (z −4,9)")
	# La caja base no se cambia; se duplica.
	panel.open_box(Destinos.BOX_BASE_PATH)
	_check(not form._name.editable and panel._save_button.disabled, "la caja base no se edita")
	panel.duplicate_current()
	_check(panel.is_dirty() and form.path == Destinos.CONTAINERS_DIR.path_join("caja_nueva.tscn"), "duplicar la base da una caja nueva")
	panel.discard()
	panel._on_tab(0)  # ítems


# --- 7. Fallos al guardar, sin dañar nada ------------------------------------------------------------

func _save_failures() -> void:
	var form = panel._item_form
	var catalog_text := FileAccess.get_file_as_string(Destinos.CATALOG_PATH)
	var catalog: Resource = load(Destinos.CATALOG_PATH)
	var items_before: int = catalog.get(&"items").size()
	# Falla el catálogo: el .tres recién guardado se borra.
	panel.writer = func(resource: Resource, at: String) -> int:
		return ERR_FILE_CANT_WRITE if at == Destinos.CATALOG_PATH else ResourceSaver.save(resource, at)
	panel.new_item()
	_type(form._name, "Termo roto")
	var result: Dictionary = panel.save_current(false)
	var path := Destinos.ITEMS_DIR.path_join("termo_roto.tres")
	_check(not result["ok"] and result["message"].contains("no quedó nada creado"), "si falla el catálogo: %s" % result["message"])
	_check(not FileAccess.file_exists(path) and FileAccess.get_file_as_string(Destinos.CATALOG_PATH) == catalog_text
			and catalog.get(&"items").size() == items_before, "no queda el .tres y el catálogo está igual, en el disco y en memoria")
	_check(panel.is_dirty() and panel._item_original == null, "el formulario sigue con lo escrito, para reintentar")
	# Falla el .tres de un ítem que se edita: el original vuelve a como estaba.
	var bottle_path := Destinos.ITEMS_DIR.path_join("botella.tres")
	var bottle_text := FileAccess.get_file_as_string(bottle_path)
	var bottle: Resource = load(bottle_path)
	var before := Guardado.snapshot(bottle)
	panel.writer = func(_resource: Resource, _at: String) -> int: return ERR_FILE_CANT_WRITE
	panel.discard()
	panel.open_item(bottle_path)
	_type(form._name, "Botella rota")
	result = panel.save_current(true)
	_check(not result["ok"] and FileAccess.get_file_as_string(bottle_path) == bottle_text and Guardado.snapshot(bottle) == before,
			"si falla al editar, el archivo y el recurso quedan como estaban: %s" % result["message"])
	panel.discard()
	# Falla la escena de un contenedor nuevo: no queda ni la escena.
	panel._on_tab(1)  # contenedores
	panel.new_box()
	_type(panel._box_form._name, "Baúl roto")
	result = panel.save_current(false)
	_check(not result["ok"] and not FileAccess.file_exists(Destinos.CONTAINERS_DIR.path_join("baul_roto.tscn")),
			"si falla la escena del contenedor, no queda: %s" % result["message"])
	panel.discard()
	panel.writer = Callable()
	panel._on_tab(0)  # ítems


# --- Burbujitas de ayuda (2026-11-02) ------------------------------------------------------------

## Lo que explica cada burbujita: una frase de cada una, para buscarla.
const HELP_PHRASES := [
	"Busca por nombre, ID o archivo", "Arrastrá para girar; la rueda", "Guardar crea el objeto", "12 de a 5",
	"baterías gastadas", "es lo que viaja por red", "Dónde se guarda su .tres", "Cómo se ve en el piso",
	"Se arrastra desde FileSystem", "cuando está suelto en el mundo", "Arrastrá para girarlo", "Sin capacidades",
	"Opcional. Son datos", "Positivo cura", "La reserva completa son 200", "Quita esa salud de a poco", "4 en 2 s",
	"30 lleva una del 50 % al 80 %",
]


## El texto que explica va en burbujitas con un signo de pregunta, al lado del
## nombre de cada campo o sección: un clic abre el globo y ningún texto de
## ayuda queda suelto en el panel.
func _help_bubbles() -> void:
	var form = panel._item_form
	panel.new_item()
	form._add_use.pressed.emit()
	await _frames(3)
	var bubbles := _bubbles(panel)
	var shown := bubbles.filter(_shown)
	_check(shown.size() >= 18 and shown.all(func(bubble: Button) -> bool: return bubble.explanation != ""),
			"con un consumible, se ven %d burbujitas y todas tienen su explicación" % shown.size())
	var texts := "\n".join(bubbles.map(func(bubble: Button) -> String: return bubble.explanation))
	var missing := HELP_PHRASES.filter(func(phrase: String) -> bool: return not texts.contains(phrase))
	_check(missing.is_empty(), "cada explicación está en una burbujita (faltan: %s)" % [missing])
	var loose := _loose_help_labels()
	_check(loose.is_empty(), "ningún texto de ayuda queda suelto en el panel: %s" % [loose])
	_check(not panel._results_note.text.contains("Escribí") and panel._results_note.text.ends_with("ítems."),
			"debajo del buscador, solo cuántos hay: %s" % panel._results_note.text)
	# Las secciones la tienen pegada al título, no en la punta derecha.
	var fold: FoldableContainer = form.find_children("*", "FoldableContainer", true, false).filter(
			func(node: FoldableContainer) -> bool: return node.title == "Apariencia")[0]
	var title_bubble: Button = _bubbles(fold).filter(func(bubble: Button) -> bool: return bubble.get_parent() == fold)[0]
	var title_end := fold.get_theme_font(&"font").get_string_size(fold.title, HORIZONTAL_ALIGNMENT_LEFT, -1, fold.get_theme_font_size(&"font_size")).x
	_check(title_bubble.position.x > title_end and title_bubble.position.x < title_end + 60.0 * EditorInterface.get_editor_scale(),
			"la burbujita de Apariencia va al lado del título (en x %d, el título mide %d, la sección %d)" % [
			title_bubble.position.x, title_end, fold.size.x])
	# Un clic abre el globo con el texto; otro clic justo después de cerrarlo no lo reabre.
	var bubble: Button = form._id_help
	bubble.pressed.emit()
	var popup: PopupPanel = bubble._popup
	var popup_label: Label = popup.find_children("*", "Label", true, false)[0]
	_check(bubble.is_open() and popup_label.text == bubble.explanation and popup.size.x >= 150 and popup.size.y >= 30,
			"un clic abre el globo con la explicación (%s)" % [popup.size])
	_check(popup_label.get_line_count() >= 2 and popup.size.y >= popup_label.get_line_count() * 10,
			"el globo tiene alto para todos sus renglones (%d renglones, %d de alto)" % [popup_label.get_line_count(), popup.size.y])
	popup.hide()
	bubble.pressed.emit()
	_check(not bubble.is_open(), "el clic que lo cierra no lo vuelve a abrir")
	var wait_until := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < wait_until:
		await get_tree().process_frame
	bubble.pressed.emit()
	_check(bubble.is_open(), "un clic después lo abre de nuevo")
	popup.hide()
	# Las que cambian con lo que está abierto.
	_check(form._id_help.explanation.contains("se puede cambiar antes de crearlo") and form._model_help.explanation.contains("Sin modelo ni forma"),
			"un ítem nuevo: el ID se puede cambiar y no tiene modelo ni forma")
	panel.open_item(Destinos.ITEMS_DIR.path_join("bateria.tres"))
	_check(form._id_help.explanation.contains("no se cambia desde acá") and form._path_help.explanation.contains("no se cambia de lugar"),
			"un ítem ya creado: el ID y el archivo no se cambian")
	panel.new_item()
	panel._on_tab(1)  # contenedores
	_check(panel._place_help.explanation.contains("Guardar crea el contenedor") and panel._preview_help.explanation.contains("círculo amarillo")
			and panel._box_form._path_help.explanation.contains("hereda de caja.tscn"),
			"en contenedores, colocar, la vista previa y la escena explican lo suyo")
	loose = _loose_help_labels()
	_check(loose.is_empty(), "y tampoco queda texto de ayuda suelto: %s" % [loose])
	panel.open_box(Destinos.BOX_BASE_PATH)
	_check(panel._box_form._path_help.explanation.contains("caja base") and panel._box_form._read_only_note.visible,
			"la caja base avisa a la vista que no se cambia, y la burbujita dice por qué")
	panel._on_tab(0)  # ítems
	panel.new_item()


func _bubbles(root: Node) -> Array:
	return root.find_children("*", "Button", true, false).filter(
			func(node: Node) -> bool: return node.get_script() == preload("../ayuda.gd"))


## Los textos visibles del panel que dicen algo de una burbujita sin estar en una.
func _loose_help_labels() -> Array:
	var loose := []
	for label: Label in panel.find_children("*", "Label", true, false):
		if not _shown(label) or _in_bubble(label):
			continue
		for phrase: String in HELP_PHRASES + ["Escribí arriba para buscar", "Datos propios de estas unidades", "El círculo amarillo"]:
			if label.text.contains(phrase):
				loose.append(label.text.left(50))
	return loose


## Si se ve dentro del panel (sin importar si la pestaña del editor está al frente).
func _shown(node: Node) -> bool:
	while node != null and node != panel:
		if node is CanvasItem and not (node as CanvasItem).visible:
			return false
		node = node.get_parent()
	return node == panel


func _in_bubble(node: Node) -> bool:
	while node != null:
		if node.get_script() == preload("../ayuda.gd"):
			return true
		node = node.get_parent()
	return false


# --- Ayudas ------------------------------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[creador] FALLA: %s" % what)
	else:
		print("[creador] ok: %s" % what)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Escribe en un campo como si se tipeara.
func _type(line: LineEdit, text: String) -> void:
	line.text = text
	line.text_changed.emit(text)


func _catalog_ids() -> Array:
	var ids := []
	for item: Resource in load(Destinos.CATALOG_PATH).get(&"items"):
		ids.append(String(item.get(&"id")) if item != null else "")
	return ids


func _zone_file() -> String:
	return FileAccess.get_file_as_string(Destinos.ZONE_PATH)


## Los nodos de marcadores de ese tipo en el texto de la zona.
func _markers_of(id: String, zone_text: String) -> PackedStringArray:
	var found := PackedStringArray()
	for line in zone_text.split("\n"):
		if line.begins_with('[node name="%s' % id.to_pascal_case()):
			found.append(line)
	return found


func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		out.append(dir.path_join(file))
	return out


func _history(root: Node) -> UndoRedo:
	var manager := EditorInterface.get_editor_undo_redo()
	return manager.get_history_undo_redo(manager.get_object_history_id(root))
