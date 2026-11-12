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
	await _pickup_hitbox()
	await _thumbnail_arranging()
	await _hotbar_thumbnail()
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


# --- Hitbox de agarre (2026-11-07) ------------------------------------------------------------------

## Un modelo de prueba con el origen lejos de lo que se ve: una varilla con
## una perilla en la punta. Lo escribe esta prueba en la copia.
const SHIFTED_MODEL := "res://scenes/net_lab/inventario/modelos_de_prueba/varilla_corrida.tscn"
const KIND := InvPickupHitbox.Kind


func _pickup_hitbox() -> void:
	var form = panel._item_form
	panel.new_item()
	await _frames(2)
	var titles: Array = form.find_children("*", "FoldableContainer", true, false).map(func(fold: FoldableContainer) -> String: return fold.title)
	_check(titles.find("Hitbox de agarre") == titles.find("Apariencia") + 1 and titles.has("Apariencia"),
			"la sección Hitbox de agarre va debajo de Apariencia: %s" % [titles])
	var options := []
	for i in form._hitbox_kind.item_count:
		options.append(form._hitbox_kind.get_item_text(i))
	_check(options == ["Forma del modelo", "Caja", "Esfera", "Cilindro", "Forma personalizada"], "ofrece %s" % [options])
	_check(form._hitbox_kind.selected == KIND.MODEL and not form._hitbox_place.visible and panel._item_draft.get(&"pickup_hitbox") == null
			and panel._preview.shown_hitbox() == null and not panel._preview._hitbox_toggle.visible and not form._hitbox_preview.visible,
			"un ítem nuevo usa la forma del modelo: sin medidas, sin hitbox en el borrador ni en la vista previa")
	# Con un modelo que tiene el origen lejos.
	_write_shifted_model()
	_type(form._name, "Varilla corrida de prueba")
	var model: PackedScene = load(SHIFTED_MODEL)
	form._model.edited_resource = model
	form._model.resource_changed.emit(model)
	form._world_size.value = 0.5
	_pick_hitbox(form, KIND.BOX)
	var draft: Resource = panel._item_draft
	var hitbox: InvPickupHitbox = draft.get(&"pickup_hitbox")
	var model_box := InvPickupHitbox.model_bounds(draft)
	_check(model_box.position.y > -0.0001 and model_box.position.y < 0.0001 and Vector2(model_box.get_center().x, model_box.get_center().z).length() < 0.0001
			and is_equal_approx(model_box.size.z, 0.5), "con el origen del modelo lejos, su caja queda en el centro, apoyada y escalada: %s" % model_box)
	_check(hitbox != null and hitbox.kind == KIND.BOX and hitbox.bounds().encloses(model_box) and hitbox.bounds().size.distance_to(model_box.size) < 0.003,
			"Caja arranca ajustada al modelo (%s; el modelo, %s)" % [str(hitbox.bounds()) if hitbox != null else "sin hitbox", model_box])
	if hitbox == null:
		return
	await _frames(3)
	var shown: Node3D = panel._preview.shown_hitbox()
	_check(shown != null and shown.transform.is_equal_approx(hitbox.local_transform()) and _overlay_box(shown).is_equal_approx(
			AABB(-hitbox.box_size / 2.0, hitbox.box_size)), "la vista previa la muestra en el mismo lugar y del mismo tamaño que la usa el juego")
	var inline: Node = form._hitbox_preview
	var inline_shape: Node3D = inline.shown_hitbox()
	_check(inline.visible and inline_shape != null and inline_shape.transform.is_equal_approx(hitbox.local_transform())
			and form._hitbox_fields.is_ancestor_of(form._hitbox_dims) and not form._hitbox_fields.is_ancestor_of(inline),
			"la hitbox aparece junto a las medidas, con el visor fuera del desplazamiento de los controles")
	panel._preview._hitbox_toggle.button_pressed = false
	await _frames(3)
	_check(panel._preview.shown_hitbox() == null and panel._preview._hitbox_toggle.visible, "la casilla la oculta")
	panel._preview._hitbox_toggle.button_pressed = true
	await _frames(3)
	_check(panel._preview.shown_hitbox() != null, "y la vuelve a mostrar")
	_check_preview_pan(inline)
	_check_preview_pan(panel._preview)
	var inline_pan: Vector3 = inline._pan
	# A mano, al milímetro, y de a centímetro por cada lado.
	var spins := _hitbox_spins(form)
	_check(spins.size() == 3 and form._hitbox_rotation_box.visible and _hitbox_button(form, "Ajustar al modelo").visible,
			"la caja muestra ancho, alto y largo, la rotación y Ajustar al modelo")
	spins[0].value = 0.123
	form._hitbox_offset[1].value = 0.012
	_check(is_equal_approx(hitbox.box_size.x, 0.123) and is_equal_approx(hitbox.offset.y, 0.012),
			"se ajusta al milímetro: ancho %s m, alto del centro %s m" % [hitbox.box_size.x, hitbox.offset.y])
	await _frames(3)
	inline_shape = inline.shown_hitbox()
	_check(inline_shape != null and inline_shape.transform.is_equal_approx(hitbox.local_transform())
			and _overlay_box(inline_shape).is_equal_approx(AABB(-hitbox.box_size / 2.0, hitbox.box_size)),
			"el visor de la sección se actualiza al cambiar el ancho y el desplazamiento")
	_check(inline._pan.is_equal_approx(inline_pan), "editar la hitbox conserva el desplazamiento de cámara")
	var before := hitbox.box_size
	_hitbox_button(form, "+1 cm").pressed.emit()
	_check(hitbox.box_size.is_equal_approx(before + Vector3.ONE * 0.02) and is_equal_approx(_hitbox_spins(form)[0].value, 0.143),
			"+1 cm la agranda 1 cm por cada lado: %s" % hitbox.box_size)
	_hitbox_button(form, "−1 cm").pressed.emit()
	_check(hitbox.box_size.is_equal_approx(before), "−1 cm la vuelve a achicar")
	# Lo que no se guarda.
	var path := Destinos.ITEMS_DIR.path_join("varilla_corrida_de_prueba.tres")
	_hitbox_spins(form)[1].value = 0.0
	var result: Dictionary = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("Hitbox de agarre: la caja mide") and not FileAccess.file_exists(path),
			"con alto 0 no se guarda nada: %s" % result["message"])
	_hitbox_spins(form)[1].value = NAN
	_check(" ".join(panel.problems()).contains("Hitbox de agarre"), "un alto que no es un número, tampoco")
	_hitbox_button(form, "Ajustar al modelo").pressed.emit()
	_check(hitbox.bounds().encloses(model_box) and panel.problems().is_empty(), "Ajustar al modelo la deja de nuevo encerrándolo")
	_hitbox_button(form, "+1 cm").pressed.emit()
	var saved_size := hitbox.box_size
	var saved_offset := hitbox.offset
	result = panel.save_current(false)
	_check(result["ok"], "guardar la varilla con su hitbox: %s" % result["message"])
	var text := FileAccess.get_file_as_string(path)
	_check(text.contains("inv_pickup_hitbox.gd") and text.contains("pickup_hitbox = SubResource("), "la hitbox va adentro del .tres, con el resto")
	var fresh: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var fresh_hitbox: InvPickupHitbox = fresh.get(&"pickup_hitbox") if fresh != null else null
	_check(fresh_hitbox != null and fresh_hitbox.kind == KIND.BOX and fresh_hitbox.box_size.is_equal_approx(saved_size)
			and fresh_hitbox.offset.is_equal_approx(saved_offset), "leída de nuevo del disco, tiene lo mismo: %s" % (str(fresh_hitbox.box_size) if fresh_hitbox != null else "nada"))
	# Reabrir.
	panel.open_item(path)
	await _frames(3)
	var original: Resource = panel._item_original
	hitbox = panel._item_draft.get(&"pickup_hitbox")
	_check(not panel.is_dirty() and form._hitbox_kind.selected == KIND.BOX and is_equal_approx(_hitbox_spins(form)[0].value, saved_size.x)
			and is_equal_approx(form._hitbox_offset[1].value, saved_offset.y), "reabierta, se ve igual y sin cambios")
	_check(hitbox != null and hitbox != original.get(&"pickup_hitbox"), "el borrador tiene su propia hitbox, no la del original")
	_hitbox_spins(form)[2].value = 0.4
	_check(is_equal_approx((original.get(&"pickup_hitbox") as InvPickupHitbox).box_size.z, saved_size.z) and FileAccess.get_file_as_string(path) == text,
			"cambiar el borrador no toca el original, ni en memoria ni en el disco")
	panel.discard()
	# Cambiar el tamaño del modelo: la hitbox no se mueve sola; se avisa.
	hitbox = panel._item_draft.get(&"pickup_hitbox")
	form._world_size.value = 0.8
	_check(form._hitbox_notes.text.contains("Cambiaste el modelo o su tamaño") and hitbox.box_size.is_equal_approx(saved_size),
			"más grande el modelo, la hitbox queda igual y la sección lo avisa: %s" % form._hitbox_notes.text)
	result = panel.save_current(false)
	_check(not result["ok"] and String(result.get("confirm", "")).contains("la hitbox de agarre quedó igual") and FileAccess.get_file_as_string(path) == text,
			"al guardar pregunta antes: %s" % result.get("confirm", result["message"]))
	_hitbox_button(form, "Ajustar al modelo").pressed.emit()
	var bigger := InvPickupHitbox.model_bounds(panel._item_draft)
	_check(hitbox.bounds().encloses(bigger) and not form._hitbox_notes.text.contains("Cambiaste"), "Ajustar al modelo la acomoda y el aviso se va")
	_hitbox_button(form, "+1 cm").pressed.emit()
	result = panel.save_current(false)
	_check(result["ok"], "ajustada, se guarda sin preguntar: %s" % result["message"])
	saved_size = hitbox.box_size
	text = FileAccess.get_file_as_string(path)
	# Colocarla, para la segunda parte (prueba_del_creador_juego).
	result = panel.place_current(1, {})
	_check(result["ok"], "colocar la varilla: %s" % result["message"])
	panel._on_save_zone()
	_check(_markers_of("varilla_corrida_de_prueba", _zone_file()).size() == 1, "y queda en la zona guardada")
	# Las otras formas.
	_pick_hitbox(form, KIND.SPHERE)
	hitbox = panel._item_draft.get(&"pickup_hitbox")
	var model_now := InvPickupHitbox.model_bounds(panel._item_draft)
	_check(hitbox.kind == KIND.SPHERE and hitbox.bounds().encloses(model_now) and not form._hitbox_rotation_box.visible and _hitbox_spins(form).size() == 1,
			"Esfera: un radio que llega a las esquinas del modelo, sin rotación")
	_pick_hitbox(form, KIND.CYLINDER)
	_check(hitbox.kind == KIND.CYLINDER and hitbox.rotation_degrees.is_equal_approx(Vector3(90, 0, 0)) and hitbox.bounds().encloses(model_now)
			and form._hitbox_rotation_box.visible and is_equal_approx(form._hitbox_rotation[0].value, 90.0),
			"Cilindro: acostado a lo largo del modelo (giro %s), encerrándolo" % hitbox.rotation_degrees)
	_pick_hitbox(form, KIND.CUSTOM)
	var picker: EditorResourcePicker = form._hitbox_dims.find_children("*", "EditorResourcePicker", true, false)[0] \
			if not form._hitbox_dims.find_children("*", "EditorResourcePicker", true, false).is_empty() else null
	_check(picker != null and not _hitbox_button(form, "Ajustar al modelo").visible and " ".join(panel.problems()).contains("falta el recurso"),
			"Forma personalizada: pide un recurso de colisión, y sin él no se guarda")
	if picker == null:
		panel.discard()
		return
	_check(picker.base_type.contains("ConvexPolygonShape3D") and not picker.base_type.contains("Concave"), "y solo ofrece formas convexas: %s" % picker.base_type)
	# Una cóncava el selector no la acepta; puesta igual (por ejemplo, en el
	# Inspector), tampoco se guarda.
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(BoxMesh.new().get_faces())
	form._put_hitbox(&"custom_shape", concave)
	_check(" ".join(panel.problems()).contains("tiene que ser convexa"), "una cóncava, puesta a mano, se rechaza")
	var empty := ConvexPolygonShape3D.new()
	_assign(picker, empty)
	_check(" ".join(panel.problems()).contains("vacía"), "una convexa vacía, también")
	var tetra_points := PackedVector3Array([Vector3(-0.1, 0, -0.3), Vector3(0.1, 0, -0.3), Vector3(0, 0, 0.3), Vector3(0, 0.12, 0)])
	# La convexa nueva, vacía, se edita en el Inspector (desde la auditoría del
	# 2026-11-08, OBJ-01: antes no había cómo). Un clic en el recurso la abre
	# ahí, y el panel se entera de los puntos que se le ponen.
	await _frames(2)
	_check(form._custom_note != null and form._custom_note.text.contains("Está vacía") and not form._custom_own.visible,
			"la sección dice que está vacía y cómo ponerle los puntos: %s" % (form._custom_note.text if form._custom_note != null else "sin texto"))
	_check(panel._preview.shown_hitbox() == null, "(vacía, la vista previa no la muestra)")
	picker.resource_selected.emit(empty, true)
	await _frames(2)
	_check(EditorInterface.get_inspector().get_edited_object() == empty, "un clic en la forma la abre en el Inspector")
	var before_points := Guardado.snapshot(panel._item_draft)
	empty.points = tetra_points  # lo que hace el Inspector al escribirle los puntos
	await _frames(3)
	_check(panel.problems().is_empty() and Guardado.snapshot(panel._item_draft) != before_points and panel.is_dirty()
			and panel._preview.shown_hitbox() != null and form._hitbox_preview.shown_hitbox() != null,
			"con 4 puntos puestos en el Inspector, sirve, cuenta como cambio y las dos vistas previas la muestran")
	var tetra := ConvexPolygonShape3D.new()
	tetra.points = tetra_points
	_assign(picker, tetra)
	await _frames(3)
	_check(panel.problems().is_empty() and panel._preview.shown_hitbox() != null, "una convexa con volumen sirve y se ve en la vista previa")
	_check(EditorInterface.get_inspector().get_edited_object() != empty, "cambiada la forma, el Inspector suelta la de antes")
	_pick_hitbox(form, KIND.MODEL)
	_check(panel._item_draft.get(&"pickup_hitbox") == null and not form._hitbox_place.visible, "Forma del modelo deja el ítem sin hitbox")
	_pick_hitbox(form, KIND.CUSTOM)
	_check((panel._item_draft.get(&"pickup_hitbox") as InvPickupHitbox).custom_shape == tetra, "y volviendo a una forma, sigue la de antes")
	# Un archivo aparte (arrastrado desde FileSystem): se avisa que lo comparten
	# los ítems que lo usan, y «Usar una copia propia» la pasa adentro del ítem
	# sin tocar el archivo.
	var shared_path := SHIFTED_MODEL.get_base_dir().path_join("forma_compartida.tres")
	ResourceSaver.save(tetra.duplicate(), shared_path)
	var shared_text := FileAccess.get_file_as_string(shared_path)
	var shared: ConvexPolygonShape3D = ResourceLoader.load(shared_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	picker = form._hitbox_dims.find_children("*", "EditorResourcePicker", true, false)[0]
	_assign(picker, shared)
	_check(form._custom_own.visible and form._custom_note.text.contains("forma_compartida.tres"),
			"un archivo aparte: avisa que lo comparten los ítems que lo usan, y ofrece una copia propia")
	form._custom_own.pressed.emit()
	var owned := (panel._item_draft.get(&"pickup_hitbox") as InvPickupHitbox).custom_shape as ConvexPolygonShape3D
	_check(owned != null and owned != shared and owned.resource_path == "" and owned.points == shared.points
			and not form._custom_own.visible and FileAccess.get_file_as_string(shared_path) == shared_text,
			"«Usar una copia propia» la copia adentro del ítem, con los mismos puntos, y el archivo no cambia")
	owned.points = PackedVector3Array([Vector3(-0.2, 0, -0.3), Vector3(0.2, 0, -0.3), Vector3(0, 0, 0.3), Vector3(0, 0.2, 0)])
	_check(shared.points == tetra_points, "cambiar la copia propia no toca el archivo compartido")
	panel.discard()
	# Duplicar: la copia tiene su propia hitbox (y su forma propia, si la tiene).
	panel.duplicate_current()
	var copy: Resource = panel._item_draft
	var source: Resource = load(path)
	_check(copy.get(&"pickup_hitbox") != null and copy.get(&"pickup_hitbox") != source.get(&"pickup_hitbox")
			and (copy.get(&"pickup_hitbox") as InvPickupHitbox).box_size.is_equal_approx(saved_size), "la copia trae una hitbox igual, pero suya")
	_pick_hitbox(form, KIND.CUSTOM)
	picker = form._hitbox_dims.find_children("*", "EditorResourcePicker", true, false)[0]
	# Como lo haría el usuario: una nueva desde el selector, con los puntos
	# puestos en el Inspector (OBJ-01).
	var fresh_shape := ConvexPolygonShape3D.new()
	_assign(picker, fresh_shape)
	picker.resource_selected.emit(fresh_shape, true)
	fresh_shape.points = tetra_points
	await _frames(2)
	_check(panel.problems().is_empty() and EditorInterface.get_inspector().get_edited_object() == fresh_shape,
			"la copia, con una forma nueva y sus puntos puestos en el Inspector, se puede guardar")
	result = panel.save_current(false)
	var copy_path := Destinos.ITEMS_DIR.path_join("varilla_corrida_de_prueba_copia.tres")
	_check(result["ok"] and FileAccess.get_file_as_string(copy_path).contains("ConvexPolygonShape3D"),
			"la copia, con una forma propia, se guarda con la forma adentro: %s" % result["message"])
	_check(FileAccess.get_file_as_string(path) == text and (load(path).get(&"pickup_hitbox") as InvPickupHitbox).kind == KIND.BOX
			and (load(path).get(&"pickup_hitbox") as InvPickupHitbox).box_size.is_equal_approx(saved_size),
			"y el original sigue con su caja, en el disco y en memoria")
	panel.open_item(copy_path)
	var reopened: InvPickupHitbox = panel._item_draft.get(&"pickup_hitbox")
	var stored: InvPickupHitbox = panel._item_original.get(&"pickup_hitbox")
	_check(not panel.is_dirty() and reopened.custom_shape != null and reopened.custom_shape != stored.custom_shape
			and (reopened.custom_shape as ConvexPolygonShape3D).points == tetra.points, "reabierta, el borrador edita una copia de su forma propia")
	_check(EditorInterface.get_inspector().get_edited_object() != fresh_shape, "reabierta, el Inspector ya no edita la forma del borrador de antes")
	# Duplicar la que tiene forma propia y cambiar los puntos de la copia: los
	# del original no cambian, ni en memoria ni en el disco.
	var copy_text := FileAccess.get_file_as_string(copy_path)
	panel.duplicate_current()
	var twin := (panel._item_draft.get(&"pickup_hitbox") as InvPickupHitbox).custom_shape as ConvexPolygonShape3D
	var saved_shape := (load(copy_path).get(&"pickup_hitbox") as InvPickupHitbox).custom_shape as ConvexPolygonShape3D
	twin.points = PackedVector3Array([Vector3(-0.15, 0, -0.3), Vector3(0.15, 0, -0.3), Vector3(0, 0, 0.35), Vector3(0, 0.15, 0)])
	await _frames(2)
	_check(twin != saved_shape and saved_shape.points == tetra.points and FileAccess.get_file_as_string(copy_path) == copy_text and panel.is_dirty(),
			"duplicada otra vez, cambiar los puntos de la copia no toca los del original")
	panel.discard()
	# Sin modelo: la malla de respaldo (la caja de color), con la misma regla del juego.
	panel.new_item()
	_type(form._name, "Bloque de respaldo")
	form._world_size.value = 0.3
	_pick_hitbox(form, KIND.BOX)
	var plain := InvPickupHitbox.model_bounds(panel._item_draft)
	_check(plain.size.is_equal_approx(Vector3(0.3, 0.15, 0.3)) and (panel._item_draft.get(&"pickup_hitbox") as InvPickupHitbox).bounds().encloses(plain),
			"sin modelo, se ajusta a la caja de color que se ve en el piso: %s" % plain)
	panel.discard()
	panel.new_item()


func _check_preview_pan(preview: Node) -> void:
	var before: Transform3D = preview._camera.transform
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = true
	preview._on_view_input(button)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(24.0, -12.0)
	drag.shift_pressed = true
	preview._on_view_input(drag)
	var moved: Transform3D = preview._camera.transform
	var offset: Vector3 = preview._pan
	_check(moved.basis.is_equal_approx(before.basis) and offset.dot(before.basis.x) < 0.0
			and offset.dot(before.basis.y) < 0.0 and moved.origin.is_equal_approx(before.origin + offset),
			"Shift + arrastre izquierdo desplaza la cámara sin girarla")
	drag.shift_pressed = false
	preview._on_view_input(drag)
	_check(preview._pan.is_equal_approx(offset) and not preview._camera.basis.is_equal_approx(moved.basis),
			"arrastrar sin Shift sigue girando alrededor del centro desplazado")
	button.pressed = false
	preview._on_view_input(button)


func _pick_hitbox(form: Node, kind: int) -> void:
	form._hitbox_kind.select(kind)
	form._hitbox_kind.item_selected.emit(kind)


func _hitbox_spins(form: Node) -> Array:
	return form._hitbox_dims.find_children("*", "EditorSpinSlider", true, false)


func _hitbox_button(form: Node, text: String) -> Button:
	for button: Button in form._hitbox_place.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null


func _assign(picker: EditorResourcePicker, resource: Resource) -> void:
	picker.edited_resource = resource
	picker.resource_changed.emit(resource)


## La caja del contorno de la hitbox que muestra la vista previa, en su espacio.
func _overlay_box(shown: Node3D) -> AABB:
	var outline := shown.get_node_or_null(^"Contorno") as MeshInstance3D
	return outline.mesh.get_aabb() if outline != null else AABB()


func _write_shifted_model() -> void:
	var root := Node3D.new()
	root.name = "VarillaCorrida"
	var rod := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.04, 0.04, 0.6)
	rod.mesh = bar
	rod.position = Vector3(3.0, -2.0, 1.5)
	root.add_child(rod)
	rod.owner = root
	var knob := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.05
	ball.height = 0.1
	knob.mesh = ball
	knob.position = Vector3(3.0, -2.0, 1.85)
	root.add_child(knob)
	knob.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHIFTED_MODEL.get_base_dir()))
	ResourceSaver.save(packed, SHIFTED_MODEL)
	EditorInterface.get_resource_filesystem().update_file(SHIFTED_MODEL)


# --- Acomodar la miniatura -------------------------------------------------------------------------
# Sin pantalla no hay imagen: acá se prueban los valores que escribe. El
# arrastre con el mouse y que la imagen no salte se prueban con ventana.

## El ítem de las pruebas de miniatura (desde la auditoría del 2026-11-08,
## PRU-01): uno que crea esta prueba con el panel, de 1 × 3, con la miniatura
## de fábrica y sin encuadre propio en la barra. Antes se usaba el machete del
## laboratorio, que es contenido que se edita: con su encuadre ya acomodado,
## estas comprobaciones fallaban sin que nada estuviera roto.
const THUMB_ITEM := "miniatura_de_prueba"


func _thumbnail_item() -> String:
	var path := Destinos.ITEMS_DIR.path_join(THUMB_ITEM + ".tres")
	if FileAccess.file_exists(path):
		return path
	if not ResourceLoader.exists(SHIFTED_MODEL):
		_write_shifted_model()
	var form = panel._item_form
	panel.new_item()
	_type(form._name, "Miniatura de prueba")
	form._height.value = 3
	var model: PackedScene = load(SHIFTED_MODEL)
	form._model.edited_resource = model
	form._model.resource_changed.emit(model)
	var result: Dictionary = panel.save_current(false)
	_check(result["ok"] and FileAccess.file_exists(path), "(preparación) el ítem de las miniaturas se crea con el panel: %s" % result["message"])
	return path


## Si el .tres tiene escrita esa propiedad, en un renglón propio (así
## "thumbnail_rotation" no coincide con "hotbar_thumbnail_rotation").
static func _has_field(text: String, field: String) -> bool:
	return text.begins_with(field + " = ") or text.contains("\n" + field + " = ")


## Si el recurso, leído otra vez del disco, tiene la miniatura de la grilla de fábrica.
static func _factory_thumbnail(path: String) -> bool:
	var fresh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as InvItemDef
	var factory := InvItemDef.new()
	return fresh != null and fresh.thumbnail_rotation == factory.thumbnail_rotation and fresh.thumbnail_zoom == factory.thumbnail_zoom \
			and fresh.thumbnail_offset == factory.thumbnail_offset and fresh.thumbnail_auto_align == factory.thumbnail_auto_align


func _thumbnail_arranging() -> void:
	var form = panel._item_form
	var arranger = form._arranger
	var door_path := _thumbnail_item()
	panel.open_item(door_path)
	var draft: Resource = panel._item_draft
	_check(draft.get(&"thumbnail_auto_align") and draft.get(&"thumbnail_rotation") == Vector3(-20, 35, 0),
			"el ítem de prueba arranca con la miniatura automática")
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
	_check(result["ok"] and text.contains("\nthumbnail_offset = Vector2(0.25, -0.1)") and text.contains("\nthumbnail_auto_align = false")
			and text.contains("\nthumbnail_zoom = 1.1"), "se guarda como quedó: %s" % result["message"])
	_check(load(door_path).get(&"thumbnail_offset").is_equal_approx(Vector2(0.25, -0.1)), "y el recurso del juego lo tiene")
	form._arranger.center()
	_check(panel._item_draft.get(&"thumbnail_offset") == Vector2.ZERO and panel._item_draft.get(&"thumbnail_zoom") == 1.0, "Centrar")
	panel._item_draft.set(&"thumbnail_offset", Vector2(2, 0))
	result = panel.save_current(false)
	_check(not result["ok"] and result["message"].contains("fuera del cuadro"), "corrido fuera del cuadro se rechaza: %s" % result["message"])
	form._arranger.automatic()
	result = panel.save_current(false)
	text = FileAccess.get_file_as_string(door_path)
	_check(result["ok"] and not _has_field(text, "thumbnail_offset") and not _has_field(text, "thumbnail_auto_align")
			and not _has_field(text, "thumbnail_rotation") and not _has_field(text, "thumbnail_zoom") and _factory_thumbnail(door_path),
			"Automático vuelve a los valores de fábrica (en el archivo y leído otra vez)")


func _hotbar_thumbnail() -> void:
	var form = panel._item_form
	var path := _thumbnail_item()
	panel.open_item(path)
	var draft: InvItemDef = panel._item_draft
	var grid_key := draft.appearance_key()
	_check(not form._custom_hotbar.button_pressed and not draft.custom_hotbar_thumbnail
			and is_equal_approx(form._hotbar_arranger._frame_rect().size.aspect(), 1.0),
			"un ítem sin encuadre propio de la barra abre con la casilla apagada y la vista de la barra es cuadrada")
	form._custom_hotbar.button_pressed = true
	var arranger = form._hotbar_arranger
	arranger.face_front()
	arranger.turn(Vector3.BACK, 90.0)
	arranger.shift_by(Vector2(0.15, 0.1))
	arranger.zoom_by(1.1)
	arranger.changed.emit()
	_check(panel.is_dirty() and draft.custom_hotbar_thumbnail and draft.appearance_key() == grid_key
			and draft.hotbar_thumbnail_rotation.is_equal_approx(Vector3(0, 0, 90))
			and draft.hotbar_thumbnail_offset.is_equal_approx(Vector2(0.15, 0.1))
			and is_equal_approx(draft.hotbar_thumbnail_zoom, 1.1),
			"los controles de la barra cambian solo su giro, desplazamiento y zoom")
	var result: Dictionary = panel.save_current(false)
	panel.open_item(path)
	draft = panel._item_draft
	_check(result["ok"] and not panel.is_dirty() and form._custom_hotbar.button_pressed
			and draft.appearance_key() == grid_key and draft.hotbar_thumbnail_offset.is_equal_approx(Vector2(0.15, 0.1)),
			"al reabrir se conserva el encuadre propio de la barra")
	var fresh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as InvItemDef
	_check(fresh != null and fresh.custom_hotbar_thumbnail and fresh.hotbar_thumbnail_rotation.is_equal_approx(Vector3(0, 0, 90))
			and fresh.hotbar_thumbnail_offset.is_equal_approx(Vector2(0.15, 0.1)) and is_equal_approx(fresh.hotbar_thumbnail_zoom, 1.1)
			and _factory_thumbnail(path), "leído otra vez del disco: el encuadre de la barra guardado, y el de la grilla sigue de fábrica")
	form._custom_hotbar.button_pressed = false
	_check(not draft.custom_hotbar_thumbnail and draft.hotbar_thumbnail_offset.is_equal_approx(Vector2(0.15, 0.1)),
			"apagar el encuadre propio conserva los ajustes")
	panel.discard()
	await _frames(2)


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
	# Desde el 2026-11-11 una caja no tiene alcance propio: ni campo, ni aviso
	# de los lados largos, ni rechazo por no llegar desde ningún lado (el
	# alcance es el común del Tuning, hasta la parte más cercana de la caja).
	var box_script: Script = InvContainer
	_check(form.get(&"_reach") == null and not form.values.has("access_range") and not Guardado.BOX_FIELDS.has(&"access_range")
			and not box_script.get_script_property_list().any(func(p: Dictionary) -> bool: return p["name"] == "access_range"),
			"una caja no tiene campo de alcance propio")
	form._size[0].value = 10.0
	form._size[2].value = 0.1
	_check(Guardado.check_box(form.values, form.path, true).is_empty(),
			"una caja larga y finita no tiene avisos ni rechazos por el alcance")
	form._size[0].value = 0.9
	form._size[2].value = 0.5
	var result: Dictionary = panel.save_current(false)
	_check(result["ok"], "guardar el armario: %s" % result["message"])
	var path := Destinos.CONTAINERS_DIR.path_join("armario_de_prueba.tscn")
	var text := FileAccess.get_file_as_string(path)
	_check(text.contains('path="%s"' % Destinos.BOX_BASE_PATH) and text.contains("instance=ExtResource") and text.contains("columns = 3")
			and not text.contains("access_range"), "la escena hereda de caja.tscn y guarda sus valores, sin alcance propio")
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
	# Más de un segundo después del último guardado de la caja: así el editor
	# siempre nota que su archivo cambió y vuelve a armar la zona al volver a
	# ella, que borra su historial de deshacer (OBJ-02, auditoría del
	# 2026-11-08). Antes de esperar, la prueba fallaba solo a veces: cuando los
	# dos guardados caían en segundos distintos.
	await get_tree().create_timer(1.2).timeout
	panel.open_box(path)
	form._rows.value = 3
	result = panel.save_current(false)
	_check(result["ok"] and result["message"].contains("zona_de_inventario.tscn tiene cambios sin guardar"),
			"con la zona sin guardar, avisa: %s" % result["message"])
	await _frames(5)
	var now := EditorInterface.get_edited_scene_root().get_node_or_null(NodePath("Objetos/" + moved_name)) as Node3D
	_check(now != null and now.position.is_equal_approx(moved_to), "el cambio de la zona sigue en el editor")
	_check(Destinos.ZONE_PATH in EditorInterface.get_unsaved_scenes(), "y la zona sigue marcada sin guardar")
	var rows_now: Array = EditorInterface.get_edited_scene_root().find_children("ArmarioDePrueba*", "", false, false) \
			.map(func(node: Node) -> int: return node.get(&"rows"))
	if result["message"].contains("historial de deshacer"):
		_check(rows_now == [3, 3], "el editor la volvió a armar: las cajas colocadas ya tienen 3 filas (%s), y el aviso lo dice" % [rows_now])
	else:
		_check(rows_now == [2, 2] and result["message"].contains("valores de antes"),
				"el editor no la volvió a armar: las cajas siguen con 2 filas (%s), y el aviso lo dice" % [rows_now])
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
	"Busca por nombre, ID o archivo", "Shift + arrastre izquierdo desplaza la cámara", "Guardar crea el objeto", "12 de a 5",
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
	_check(panel._place_help.explanation.contains("Guardar crea el contenedor") and panel._preview_help.explanation.contains("Interaction Range")
			and not panel._preview_help.explanation.contains("círculo amarillo")
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
		for phrase: String in HELP_PHRASES + ["Escribí arriba para buscar", "Datos propios de estas unidades", "Interaction Range"]:
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
