@tool
extends ScrollContainer

## Panel "Objetos" del editor: crea, edita y duplica ítems del inventario de
## grilla (InvItemDef) y contenedores fijos del mundo (escenas heredadas de
## caja.tscn), con vista previa, y los coloca en la zona de prueba.
##
## Guardar y colocar son pasos separados. Guardar escribe la definición (el
## .tres y su lugar en el catálogo, o la escena del contenedor); colocar pone
## marcadores o cajas en la zona con el deshacer del editor y deja la zona sin
## guardar, para que la guardes vos. Lo que guarda son recursos y escenas
## normales del proyecto: el juego no necesita este panel.
##
## Todo el panel va en un ScrollContainer: ningún contenido puede estirar el
## editor (con la pestaña oculta, un texto sin ancho se partía letra por letra
## y la vista 3D llegó a 5448 píxeles de alto).

const Destinos := preload("destinos.gd")
const Guardado := preload("guardado.gd")
const Colocacion := preload("colocacion.gd")
const FormularioItem := preload("formulario_item.gd")
const FormularioContenedor := preload("formulario_contenedor.gd")
const VistaPrevia := preload("vista_previa.gd")
const EditorEstado := preload("editor_estado.gd")
const Ayuda := preload("ayuda.gd")

const WRAP_WIDTH := 200.0
const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERROR_COLOR := Color(1.0, 0.5, 0.45)
## Cuántos se muestran a la vez en la lista del buscador.
const MAX_RESULTS := 200

enum Mode { ITEM, BOX }

## El deshacer del editor, para colocar (lo pone el plugin).
var undo_redo: EditorUndoRedoManager
## Para las pruebas: guarda los recursos en vez de ResourceSaver.save.
var writer := Callable()
## Lo que puso la última colocación.
var last_placed: Array[Node3D] = []

var _mode := Mode.ITEM
var _built := false
var _body: VBoxContainer
var _item_tab: Button
var _box_tab: Button
var _search: LineEdit
var _results: ItemList
var _results_note: Label
## Lo que se puede abrir: [{"text", "path", "key"}], en el orden de la lista.
var _entries: Array[Dictionary] = []
## Lo marcado en la lista (para no volver a marcarlo).
var _selected_path := ""
var _new_button: Button
var _duplicate_button: Button
var _status: Label
var _problems: Label
var _item_form: FormularioItem
var _box_form: FormularioContenedor
var _preview: VistaPrevia
var _preview_help: Ayuda
var _save_button: Button
var _discard_button: Button
var _inspect_button: Button
var _catalog_button: Button
var _place_help: Ayuda
var _quantity: SpinBox
var _quantity_label: Label
var _quantity_help: Ayuda
var _place_state: EditorEstado
var _place_state_box: Control
var _place_button: Button
var _save_zone_button: Button
var _result: Label
var _destination: Label

## El ítem que se edita: el guardado (null si es nuevo) y su copia de trabajo.
var _item_original: Resource
var _item_draft: Resource
## Cómo eran el borrador y el original al abrirlo o guardarlo, y la fecha del
## archivo: para saber si hay cambios sin guardar y si cambió por afuera.
var _item_baseline := ""
var _item_source := ""
var _item_mtime := 0
## El contenedor que se edita: su escena ("" si es nuevo).
var _box_path := ""
var _box_baseline := ""
var _box_mtime := 0
var _box_read_only := false
## Lo que se lee de la zona y del laboratorio para los avisos.
var _player_grid := Vector2i(12, 16)
var _known_boxes: Array = []


func _ready() -> void:
	if _built:
		return
	_built = true
	# Sin desplazamiento a lo ancho: todo entra en el ancho del panel.
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	_build_top()
	_item_form = FormularioItem.new()
	_item_form.edited.connect(_on_edited)
	_body.add_child(_item_form)
	_box_form = FormularioContenedor.new()
	_box_form.edited.connect(_on_edited)
	_body.add_child(_box_form)
	_preview_help = Ayuda.new()
	var preview_box := _section("Vista previa", false, _preview_help)
	_preview = VistaPrevia.new()
	preview_box.add_child(_preview)
	_build_save()
	_build_place()
	_result = _wrapped_label(_body)
	_build_help()
	var timer := Timer.new()
	timer.wait_time = 0.75
	timer.autostart = true
	# Lo que se cambie en el Inspector también cuenta como cambio.
	timer.timeout.connect(func() -> void:
		if is_visible_in_tree():
			_update_status())
	_body.add_child(timer)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_refresh_lists)
	_set_mode(Mode.ITEM)


func _exit_tree() -> void:
	var files := EditorInterface.get_resource_filesystem()
	if files != null and files.filesystem_changed.is_connected(_refresh_lists):
		files.filesystem_changed.disconnect(_refresh_lists)


# --- Armado ----------------------------------------------------------------------

func _build_top() -> void:
	var tabs := HBoxContainer.new()
	var group := ButtonGroup.new()
	_item_tab = _toggle("Ítems", group)
	_item_tab.tooltip_text = "Ítems del inventario: lo que se recoge, se guarda en la grilla y se usa."
	_box_tab = _toggle("Contenedores", group)
	_box_tab.tooltip_text = "Contenedores fijos del mundo: cajas con inventario propio, compartidas."
	_item_tab.pressed.connect(_on_tab.bind(Mode.ITEM))
	_box_tab.pressed.connect(_on_tab.bind(Mode.BOX))
	tabs.add_child(_item_tab)
	tabs.add_child(_box_tab)
	_body.add_child(tabs)
	# Buscador: lo escrito filtra la lista; un clic en la lista lo abre.
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar por nombre, ID o archivo…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if EditorInterface.get_editor_theme() != null:
		_search.right_icon = EditorInterface.get_editor_theme().get_icon(&"Search", &"EditorIcons")
	_search.text_changed.connect(func(_text: String) -> void: _show_results())
	# Enter abre el primero de la lista.
	_search.text_submitted.connect(func(_text: String) -> void:
		if _results.item_count > 0:
			_open_result(0))
	var search_line := HBoxContainer.new()
	search_line.add_child(_search)
	search_line.add_child(Ayuda.new("Busca por nombre, ID o archivo, sin importar mayúsculas ni tildes. Un clic en la lista lo abre; Enter abre el primero."))
	_body.add_child(search_line)
	_results = ItemList.new()
	_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_results.item_selected.connect(_open_result)
	_body.add_child(_results)
	_results_note = _wrapped_label(_body)
	_results_note.modulate = Color(1, 1, 1, 0.65)
	_new_button = Button.new()
	_new_button.text = "Nuevo"
	_new_button.pressed.connect(func() -> void: _guard(_new_current))
	_duplicate_button = Button.new()
	_duplicate_button.text = "Duplicar"
	_duplicate_button.tooltip_text = "Una copia nueva para empezar, con otro ID y otro archivo. El original no cambia."
	_duplicate_button.pressed.connect(func() -> void: _guard(duplicate_current))
	var buttons := HBoxContainer.new()
	for button: Button in [_new_button, _duplicate_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(button)
	_body.add_child(buttons)
	_status = _wrapped_label(_body)
	_problems = _wrapped_label(_body)
	_problems.add_theme_color_override(&"font_color", ERROR_COLOR)


func _build_save() -> void:
	_save_button = Button.new()
	_save_button.text = "Guardar"
	_save_button.pressed.connect(_on_save_pressed)
	_discard_button = Button.new()
	_discard_button.text = "Descartar cambios"
	_discard_button.pressed.connect(func() -> void:
		discard()
		_show_result("Cambios descartados: no se escribió nada.", true))
	_inspect_button = Button.new()
	_inspect_button.text = "Inspector"
	_inspect_button.tooltip_text = "Abre lo guardado en el Inspector (no el borrador del panel)."
	_inspect_button.pressed.connect(_on_inspect)
	_save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_save_button)
	var line := HBoxContainer.new()
	for button: Button in [_discard_button, _inspect_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		line.add_child(button)
	_body.add_child(line)
	_catalog_button = Button.new()
	_catalog_button.text = "Sumarlo al catálogo"
	_catalog_button.pressed.connect(func() -> void:
		var result := Guardado.add_to_catalog(_item_original, load(Destinos.CATALOG_PATH), writer)
		_show_result(result["message"], result["ok"])
		_refresh_lists())
	_body.add_child(_catalog_button)


func _build_place() -> void:
	_place_help = Ayuda.new()
	var box := _section("Colocar en la zona", false, _place_help)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_quantity = SpinBox.new()
	_quantity.min_value = 0
	_quantity.max_value = 9999
	_quantity.step = 1
	_quantity.rounded = true
	_quantity.value = 1
	_quantity.custom_minimum_size.x = 70
	_quantity_label = _label("Unidades")
	_quantity_help = Ayuda.new()
	var quantity_name := HBoxContainer.new()
	quantity_name.add_child(_quantity_label)
	quantity_name.add_child(_quantity_help)
	grid.add_child(quantity_name)
	grid.add_child(_quantity)
	_place_state_box = VBoxContainer.new()
	var state_title := HBoxContainer.new()
	state_title.add_child(_label("Datos propios (opcional)"))
	state_title.add_child(Ayuda.new("Reemplazan los del estado inicial solo para las unidades que pongas ahora. Ejemplo: unas baterías gastadas, con carga = 40."))
	_place_state_box.add_child(state_title)
	_place_state = EditorEstado.new()
	_place_state.set_empty_text("Sin datos: nacen con el estado inicial del objeto.")
	_place_state_box.add_child(_place_state)
	box.add_child(_place_state_box)
	_place_button = Button.new()
	_place_button.text = "Colocar en la zona"
	_place_button.pressed.connect(func() -> void:
		var result := place_current(int(_quantity.value), _place_state.get_state())
		_show_result(result["message"], result["ok"]))
	box.add_child(_place_button)
	_save_zone_button = Button.new()
	_save_zone_button.text = "Guardar la zona"
	_save_zone_button.tooltip_text = "Guarda zona_de_inventario.tscn, con todo lo que tenga sin guardar."
	_save_zone_button.pressed.connect(_on_save_zone)
	box.add_child(_save_zone_button)


func _build_help() -> void:
	var box := _section("Ayuda", true)
	_destination = _wrapped_label(box)
	var help := _wrapped_label(box)
	help.text = "\n".join([
		"Guardar escribe la definición: el .tres del ítem y su lugar en el catálogo, o la escena del contenedor. No pone nada en el mapa.",
		"Colocar pone marcadores (ítems) o cajas (contenedores) en lugares libres de la zona y los deja seleccionados, para moverlos con las herramientas de Godot. La zona queda sin guardar: Ctrl+S o «Guardar la zona».",
		"Ctrl+Z saca lo colocado. No borra el .tres, no lo saca del catálogo ni deshace un guardado: eso ya está escrito en el disco.",
		"Un ítem se ve con su modelo; si no tiene, con su malla; si tampoco, como una caja de su color. Del modelo solo se usan sus mallas: no corren sus scripts, ni su física, ni sus efectos.",
		"Las cantidades van en pilas válidas: 12 unidades de a 5 son tres pilas, de 5, 5 y 2. Con 0 no se coloca nada.",
		"En cooperativo: después de guardar o colocar, las dos PC tienen que tener la misma versión del laboratorio (en la notebook, actualizar_lab.bat, o una exportación nueva para los dos). Si no, la notebook no entra: «difiere en el inventario».",
		"Para verlo más grande: el menú de la pestaña Objetos permite hacerla flotante o pasarla abajo.",
	])


# --- Modo y lista --------------------------------------------------------------------

func _set_mode(mode: int) -> void:
	_mode = mode
	# Cada pestaña busca en lo suyo.
	_search.text = ""
	_item_tab.set_pressed_no_signal(mode == Mode.ITEM)
	_box_tab.set_pressed_no_signal(mode == Mode.BOX)
	_item_form.visible = mode == Mode.ITEM
	_box_form.visible = mode == Mode.BOX
	_quantity_label.text = "Unidades" if mode == Mode.ITEM else "Cajas"
	_quantity.max_value = 9999 if mode == Mode.ITEM else 20
	_place_state_box.visible = mode == Mode.ITEM
	var after := "Es para probar en el laboratorio: lo puesto queda seleccionado para moverlo, y la zona, sin guardar (Ctrl+S). Ctrl+Z lo saca."
	if mode == Mode.ITEM:
		_place_help.explanation = "Guardar crea el objeto, pero no lo pone en ningún lado del mundo. Esto pone unidades en el piso de la zona de inventario (pasando el borde este del piso, a unos 30 m de donde aparecés), para recogerlas con E al jugar.\n\n" + after
		_quantity_help.explanation = "Si se apila, van en pilas válidas: 12 de a 5 son tres pilas, de 5, 5 y 2. Con 0 no se coloca nada."
		_preview_help.explanation = "Arrastrá con clic izquierdo para girar. Shift + arrastre izquierdo desplaza la cámara. La rueda acerca y aleja. Si es equipable, arriba se elige verlo en el piso o en la mano. En el piso, si tiene una hitbox de agarre con forma, se ve en celeste, en su lugar y de su tamaño; la casilla la oculta. Hoy el juego no la usa para recoger: se recoge apuntando al modelo. Abajo, cómo ocupa la grilla del inventario (también girado, si se gira)."
	else:
		_place_help.explanation = "Guardar crea el contenedor, pero no lo pone en ningún lado del mundo. Esto pone cajas en el piso de la zona de inventario (pasando el borde este del piso), para abrirlas con E al jugar.\n\n" + after
		_quantity_help.explanation = "Hasta 20 cajas por vez. Cada una nace vacía, con su propio inventario."
		_preview_help.explanation = "Arrastrá con clic izquierdo para girar. Shift + arrastre izquierdo desplaza la cámara. La rueda acerca y aleja. El personaje, al lado, es para ver el tamaño. Se abre con E apuntándole: un rayo desde los ojos tiene que tocarla a no más de Interaction Range (el alcance común del nodo Tuning); abierta, sigue abierta mientras los ojos estén a ese alcance de su parte más cercana. Abajo, las celdas de su inventario."
	if mode == Mode.ITEM:
		if _item_draft == null:
			new_item()
		else:
			_show_item()
	else:
		if _box_form.values.is_empty():
			new_box()
		else:
			_show_box()
	_refresh_lists()


func _on_tab(mode: int) -> void:
	if mode == _mode:
		_restore_tab()
		return
	_guard(_set_mode.bind(mode), _restore_tab)


func _restore_tab() -> void:
	_item_tab.set_pressed_no_signal(_mode == Mode.ITEM)
	_box_tab.set_pressed_no_signal(_mode == Mode.BOX)


## Vuelve a armar lo que se puede abrir (los ítems o los contenedores) y lo
## muestra filtrado por el buscador.
func _refresh_lists() -> void:
	if not _built:
		return
	_read_destinations()
	_entries.clear()
	if _mode == Mode.ITEM:
		var catalog: Resource = load(Destinos.CATALOG_PATH)
		var listed := {}
		if catalog != null:
			for item: Resource in catalog.get(&"items"):
				if item != null and item.resource_path != "":
					_add_entry(String(item.get(&"display_name")), item.resource_path, String(item.get(&"id")))
					listed[item.resource_path] = true
		for path in _files_in(Destinos.ITEMS_DIR, "tres"):
			if listed.has(path):
				continue
			var item := ResourceLoader.load(path) as Resource
			if item != null and item.get_script() == InvItemDef:
				_add_entry(String(item.get(&"display_name")), path, String(item.get(&"id")), " · fuera del catálogo")
	else:
		_add_entry("Caja base", Destinos.BOX_BASE_PATH, "", " · solo para duplicar")
		for path in _files_in(Destinos.CONTAINERS_DIR, "tscn"):
			var values := Guardado.box_values(path)
			if not values.is_empty():
				_add_entry(String(values["display_name"]), path, String(values["node_name"]))
	_show_results()
	_update_status()


func _add_entry(shown: String, path: String, id: String, note := "") -> void:
	_entries.append({"text": "%s (%s)%s" % [shown, path.get_file(), note], "path": path,
			"key": plain_text("%s %s %s" % [shown, id, path.get_file()])})


## Los que coinciden con lo que se escribió: todas las palabras, sin importar
## mayúsculas, tildes ni guiones bajos, en el nombre, el ID o el archivo.
func matching(query: String) -> Array[Dictionary]:
	var words := plain_text(query).split(" ", false)
	var found: Array[Dictionary] = []
	for entry in _entries:
		var all := true
		for word in words:
			if not String(entry["key"]).contains(word):
				all = false
				break
		if all:
			found.append(entry)
	return found


## La lista de abajo del buscador, con lo que coincide.
func _show_results() -> void:
	var found := matching(_search.text)
	_results.clear()
	for entry in found.slice(0, MAX_RESULTS):
		var index := _results.add_item(entry["text"])
		_results.set_item_metadata(index, entry["path"])
		_results.set_item_tooltip(index, entry["path"])
	# Alta según lo que muestra, hasta unos 7 renglones; más, con scroll.
	_results.custom_minimum_size = Vector2(120, clampf(26.0 * _results.item_count + 8.0, 34.0, 190.0))
	var kind := "ítems" if _mode == Mode.ITEM else "contenedores"
	if _entries.is_empty():
		_results_note.text = "Todavía no hay %s: Nuevo crea el primero." % kind
	elif found.is_empty():
		_results_note.text = "Ninguno coincide con «%s»." % _search.text.strip_edges()
	elif _search.text.strip_edges() == "":
		_results_note.text = "%d %s." % [found.size(), kind]
	else:
		_results_note.text = "%d de %d." % [found.size(), _entries.size()]
	if found.size() > MAX_RESULTS:
		_results_note.text += " Se muestran los primeros %d: escribí más para achicar." % MAX_RESULTS
	_selected_path = ""
	_select_current()


## Que la lista muestre marcado lo que está abierto. Solo si cambió: así no
## salta mientras recorrés la lista.
func _select_current() -> void:
	var current := _current_path()
	if current == _selected_path:
		return
	_selected_path = current
	_results.deselect_all()
	for i in _results.item_count:
		if current != "" and _results.get_item_metadata(i) == current:
			_results.select(i)
			_results.ensure_current_is_visible()
			return


## Plano, para comparar: minúsculas, sin tildes y con espacios en vez de _.
static func plain_text(text: String) -> String:
	var plain := text.to_lower().replace("_", " ")
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"]]:
		plain = plain.replace(pair[0], pair[1])
	return plain


static func _files_in(dir: String, extension: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == extension:
			out.append(dir.path_join(file))
	return out


## Abre lo que está en ese renglón de la lista (preguntando antes si hay
## cambios sin guardar).
func _open_result(index: int) -> void:
	var path: String = _results.get_item_metadata(index)
	if path == "" or path == _current_path():
		return
	var open := func() -> void:
		if _mode == Mode.ITEM:
			open_item(path)
		else:
			open_box(path)
		_select_current()
	_guard(open, func() -> void:
		_selected_path = "-"
		_select_current())


func _current_path() -> String:
	if _mode == Mode.ITEM:
		return _item_original.resource_path if _item_original != null else ""
	return _box_path


## Lo que se lee del laboratorio y de la zona para los avisos.
func _read_destinations() -> void:
	_player_grid = Destinos.player_grid()
	var zone := Colocacion.zone_for_reading()
	_known_boxes = Colocacion.zone_boxes(zone["root"])
	if zone["owned"] and zone["root"] != null:
		zone["root"].free()
	for path in _files_in(Destinos.CONTAINERS_DIR, "tscn"):
		var values := Guardado.box_values(path)
		if not values.is_empty():
			_known_boxes.append({"name": values["display_name"], "columns": values["columns"], "rows": values["rows"]})
	var problem := Destinos.check_lab()
	_destination.text = "Destinos: el catálogo %s y la zona %s. Los usa la red del laboratorio (net_lab.tscn → Inventario): lo que se guarda y se coloca acá aparece al jugar. Otro nivel necesitaría su propio nodo Inventario, con su catálogo y su World Root." % [
			Destinos.CATALOG_PATH, Destinos.ZONE_PATH] if problem == "" else "Ojo: " + problem
	_destination.add_theme_color_override(&"font_color", ERROR_COLOR if problem != "" else get_theme_color(&"font_color", &"Label"))


# --- Ítems ---------------------------------------------------------------------------

func new_item() -> void:
	_item_original = null
	_item_draft = InvItemDef.new()
	_item_baseline = Guardado.snapshot(_item_draft)
	_item_form.load_draft(_item_draft, true, "")
	_show_item()


## Abre un ítem guardado: el formulario edita una copia de trabajo.
func open_item(path: String) -> bool:
	var item := ResourceLoader.load(path) as Resource
	if item == null or item.get_script() != InvItemDef:
		_show_result("%s no es un ítem del inventario (InvItemDef)." % path.get_file(), false)
		return false
	_item_original = item
	_reopen_item()
	return true


func _reopen_item() -> void:
	_item_draft = Guardado.working_copy(_item_original)
	_item_baseline = Guardado.snapshot(_item_draft)
	_item_source = Guardado.snapshot(_item_original)
	_item_mtime = FileAccess.get_modified_time(_item_original.resource_path)
	_item_form.load_draft(_item_draft, false, _item_original.resource_path)
	_show_item()


## Una copia nueva del que está abierto: otro ID y otro archivo; sus
## capacidades, su malla interna y su estado son copias.
func duplicate_current() -> void:
	if _mode == Mode.BOX:
		_duplicate_box()
		return
	var copy := Guardado.working_copy(_item_draft)
	var shown := String(copy.get(&"display_name"))
	shown = (shown if shown != "" else "Objeto") + " (copia)"
	var id := Guardado.id_for(shown)
	var catalog: Resource = load(Destinos.CATALOG_PATH)
	var n := 2
	while _id_taken(id, catalog):
		id = Guardado.id_for(shown) + "_%d" % n
		n += 1
	copy.set(&"display_name", shown)
	copy.set(&"id", StringName(id))
	_item_original = null
	_item_draft = copy
	# Una copia sin guardar se perdería: cuenta como cambio.
	_item_baseline = ""
	_item_form.load_draft(copy, true, Destinos.ITEMS_DIR.path_join(id + ".tres"))
	_show_item()


static func _id_taken(id: String, catalog: Resource) -> bool:
	if FileAccess.file_exists(Destinos.ITEMS_DIR.path_join(id + ".tres")):
		return true
	if catalog != null:
		for item: Resource in catalog.get(&"items"):
			if item != null and String(item.get(&"id")) == id:
				return true
	return false


func _show_item() -> void:
	_preview.show_item(_item_draft)
	_item_form.refresh_thumbnail()
	_item_form.refresh_hitbox()
	_item_form.set_notes(Guardado.item_notes(_item_draft, _player_grid, _known_boxes))
	_update_status()


# --- Contenedores --------------------------------------------------------------------

func new_box() -> void:
	_box_path = ""
	_box_read_only = false
	var values := Guardado.box_defaults()
	values["display_name"] = ""
	_box_form.load_values(values, true, "", false)
	_box_baseline = Guardado.box_snapshot(_box_form.values)
	_show_box()


func open_box(path: String) -> bool:
	var values := Guardado.box_values(path)
	if values.is_empty():
		_show_result("%s no es un contenedor (InvContainer)." % path.get_file(), false)
		return false
	_box_path = path
	_box_read_only = path == Destinos.BOX_BASE_PATH
	_box_form.load_values(values, false, path, _box_read_only)
	_box_baseline = Guardado.box_snapshot(_box_form.values)
	_box_mtime = FileAccess.get_modified_time(path)
	_show_box()
	return true


func _duplicate_box() -> void:
	var values := _box_form.values.duplicate()
	var shown := "Caja nueva" if _box_read_only else String(values["display_name"]) + " (copia)"
	values["display_name"] = shown
	values["node_name"] = Guardado.id_for(shown).to_pascal_case()
	var path := Destinos.CONTAINERS_DIR.path_join(Guardado.id_for(shown) + ".tscn")
	var n := 2
	while FileAccess.file_exists(path):
		path = Destinos.CONTAINERS_DIR.path_join(Guardado.id_for(shown) + "_%d.tscn" % n)
		n += 1
	_box_path = ""
	_box_read_only = false
	_box_form.load_values(values, true, path, false)
	_box_baseline = ""
	_show_box()


func _show_box() -> void:
	_preview.show_box(_box_form.values)
	_update_status()


func _new_current() -> void:
	if _mode == Mode.ITEM:
		new_item()
	else:
		new_box()


# --- Estado, guardar y descartar ---------------------------------------------------------

func _on_edited() -> void:
	if _mode == Mode.ITEM:
		_show_item()
	else:
		_show_box()


## Si lo del panel tiene cambios sin guardar.
func is_dirty() -> bool:
	if _mode == Mode.ITEM:
		return _item_draft != null and (Guardado.snapshot(_item_draft) != _item_baseline or not _item_form.form_problems().is_empty())
	return not _box_read_only and Guardado.box_snapshot(_box_form.values) != _box_baseline


## Lo que impide guardar ahora (vacío si se puede).
func problems() -> PackedStringArray:
	if _mode == Mode.ITEM:
		var found := _item_form.form_problems()
		found.append_array(Guardado.check_item(_item_draft, _item_form.path, _item_original, load(Destinos.CATALOG_PATH)))
		return found
	if _box_read_only:
		return PackedStringArray(["La caja base no se cambia: usá Duplicar."])
	return Guardado.check_box(_box_form.values, _box_form.path, _box_path == "")


func _update_status() -> void:
	if not _built:
		return
	_select_current()
	var dirty := is_dirty()
	var text := ""
	if _mode == Mode.ITEM:
		text = "Ítem nuevo, sin guardar." if _item_original == null else "Editando %s." % _item_original.resource_path.get_file()
		if _item_original != null and not _in_catalog(_item_original):
			text += " No está en el catálogo: la red no lo conoce."
	else:
		text = "Contenedor nuevo, sin guardar." if _box_path == "" else ("Viendo la caja base." if _box_read_only else "Editando %s." % _box_path.get_file())
	if dirty and (_current_path() != ""):
		text += " Tiene cambios sin guardar."
	_status.text = text
	# Lo que falta para guardar, mientras se edita (un formulario recién
	# empezado no necesita una lista de errores).
	_problems.text = "\n".join(problems()) if dirty else ""
	_problems.visible = _problems.text != ""
	_save_button.disabled = not dirty or _box_read_only and _mode == Mode.BOX
	_discard_button.disabled = not dirty
	_inspect_button.disabled = _current_path() == ""
	_catalog_button.visible = _mode == Mode.ITEM and _item_original != null and not _in_catalog(_item_original)
	_duplicate_button.disabled = _mode == Mode.ITEM and _item_original == null
	var placeable := not dirty and _current_path() != "" and (_mode == Mode.BOX or _in_catalog(_item_original))
	_place_button.disabled = not placeable
	_place_button.tooltip_text = "" if placeable else "Se coloca lo guardado: guardalo primero (y, si es un ítem, que esté en el catálogo)."
	_save_zone_button.visible = Destinos.ZONE_PATH in EditorInterface.get_unsaved_scenes()


static func _in_catalog(def: Resource) -> bool:
	var catalog: Resource = load(Destinos.CATALOG_PATH)
	if catalog == null or def == null:
		return false
	for item: Resource in catalog.get(&"items"):
		if item != null and item.resource_path == def.resource_path:
			return true
	return false


func _on_save_pressed() -> void:
	var result := save_current(false)
	if result.has("confirm"):
		_ask(result["confirm"], "Guardar igual", func() -> void:
			var again := save_current(true)
			_show_result(again["message"], again["ok"]))
		return
	_show_result(result["message"], result["ok"])


## Guarda lo del panel. Sin `confirmed`, si hay algo que conviene saber antes
## (el archivo cambió por afuera, o cambia algo de lo colocado), no guarda y
## devuelve {"ok": false, "confirm": texto}.
func save_current(confirmed: bool) -> Dictionary:
	var result := _save(confirmed)
	_update_status()
	return result


func _save(confirmed: bool) -> Dictionary:
	if _mode == Mode.ITEM:
		var form_problems := _item_form.form_problems()
		if not form_problems.is_empty():
			return {"ok": false, "message": "\n".join(form_problems)}
		if _item_original == null:
			var created := Guardado.create_item(_item_draft, _item_form.path, load(Destinos.CATALOG_PATH), writer)
			if created["ok"]:
				_item_original = _item_draft
				_reopen_item()
				_refresh_lists()
				created["message"] += " Para ponerlo en el mapa: Colocar en la zona."
			return created
		var warnings := PackedStringArray()
		if FileAccess.get_modified_time(_item_original.resource_path) != _item_mtime \
				or Guardado.snapshot(_item_original) != _item_source:
			warnings.append("%s cambió desde que lo abriste (en el Inspector o en otro programa). Si guardás, esos cambios se pisan con los del panel." % _item_original.resource_path.get_file())
		var zone := Colocacion.zone_for_reading()
		warnings.append_array(Guardado.edit_consequences(_item_original, _item_draft, zone["root"]))
		if zone["owned"] and zone["root"] != null:
			zone["root"].free()
		if not warnings.is_empty() and not confirmed:
			return {"ok": false, "confirm": "\n\n".join(warnings), "message": "No se guardó: hay algo para confirmar."}
		var saved := Guardado.save_item(_item_original, _item_draft, writer)
		if saved["ok"]:
			_reopen_item()
			_refresh_lists()
		return saved
	if _box_read_only:
		return {"ok": false, "message": "La caja base no se cambia: usá Duplicar."}
	if _box_path == "":
		var path := _box_form.path
		var created := Guardado.create_box(_box_form.values, path, writer)
		if created["ok"]:
			open_box(path)
			_refresh_lists()
			created["message"] += " Para ponerlo en el mapa: Colocar en la zona."
		return created
	if FileAccess.get_modified_time(_box_path) != _box_mtime and not confirmed:
		return {"ok": false, "confirm": "%s cambió desde que la abriste. Si guardás, se pisan esos valores con los del panel." % _box_path.get_file(),
				"message": "No se guardó: hay algo para confirmar."}
	var saved := Guardado.save_box(_box_path, _box_form.values)
	if saved["ok"]:
		open_box(_box_path)
		_refresh_lists()
	return saved


## Vuelve a lo guardado (o a un formulario nuevo vacío). No escribe nada.
func discard() -> void:
	if _mode == Mode.ITEM:
		if _item_original != null:
			_reopen_item()
		else:
			new_item()
	elif _box_path != "":
		open_box(_box_path)
	else:
		new_box()


## Si hay cambios sin guardar, pregunta antes de seguir: guardar, descartar o
## cancelar. `on_cancel` deja la interfaz como estaba.
func _guard(action: Callable, on_cancel := Callable()) -> void:
	if not is_dirty():
		action.call()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Cambios sin guardar"
	dialog.dialog_text = "Lo que estás editando tiene cambios sin guardar."
	dialog.dialog_autowrap = true
	dialog.ok_button_text = "Guardar"
	dialog.add_button("Descartar", true, "discard")
	dialog.confirmed.connect(resolve_pending.bind("guardar", action, on_cancel))
	dialog.custom_action.connect(func(_action: StringName) -> void:
		dialog.hide()
		resolve_pending("descartar", action, on_cancel))
	dialog.canceled.connect(resolve_pending.bind("cancelar", action, on_cancel))
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	EditorInterface.popup_dialog_centered(dialog, Vector2i(380, 0))


## Lo que hace cada respuesta del diálogo de cambios sin guardar: "guardar"
## guarda y, si salió, sigue con `action`; "descartar" vuelve a lo guardado y
## sigue; "cancelar" no hace nada y deja la interfaz como estaba (`on_cancel`).
func resolve_pending(choice: String, action: Callable, on_cancel: Callable) -> void:
	match choice:
		"guardar":
			var result := save_current(false)
			if result.get("ok", false):
				action.call()
				return
			_show_result(result["message"] + ("\n" + result["confirm"] if result.has("confirm") else ""), false)
		"descartar":
			discard()
			action.call()
			return
	if on_cancel.is_valid():
		on_cancel.call()


func _ask(text: String, ok_text: String, on_ok: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Antes de guardar"
	dialog.dialog_text = text
	dialog.dialog_autowrap = true
	dialog.ok_button_text = ok_text
	dialog.confirmed.connect(on_ok)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	EditorInterface.popup_dialog_centered(dialog, Vector2i(420, 0))


func _on_inspect() -> void:
	if _mode == Mode.ITEM and _item_original != null:
		EditorInterface.edit_resource(_item_original)
	elif _mode == Mode.BOX and _box_path != "":
		EditorInterface.select_file(_box_path)


# --- Colocar -------------------------------------------------------------------------

## Coloca lo guardado en la zona: `quantity` unidades del ítem (en pilas
## válidas, con `state` como estado propio si no está vacío) o `quantity` cajas
## del contenedor. Valida todo antes de tocar la zona: si no entra todo, no
## pone nada.
func place_current(quantity: int, state: Dictionary) -> Dictionary:
	last_placed.clear()
	if is_dirty() or _current_path() == "":
		return {"ok": false, "message": "Se coloca lo guardado: guardalo primero."}
	if _mode == Mode.ITEM:
		return _place_item(quantity, state)
	return _place_box(quantity)


func _place_item(quantity: int, state: Dictionary) -> Dictionary:
	if not _in_catalog(_item_original):
		return {"ok": false, "message": "No está en el catálogo: la red no lo conocería. Sumalo primero."}
	if quantity <= 0:
		return {"ok": false, "message": "Con 0 unidades no se coloca nada."}
	if quantity > 9999:
		return {"ok": false, "message": "Van hasta 9999 unidades por vez."}
	var state_problems := _place_state.problems()
	var state_problem := Guardado.check_state(state)
	if not state_problems.is_empty() or state_problem != "":
		return {"ok": false, "message": "El estado de las apariciones: %s" % (", ".join(state_problems) if not state_problems.is_empty() else state_problem)}
	var limit := Guardado.stack_limit(_item_original)
	var piles := Colocacion.piles_of(quantity, limit)
	var zone := Colocacion.open_zone()
	if zone.has("error"):
		return {"ok": false, "message": zone["error"]}
	var spots := Colocacion.free_item_spots(zone["root"], piles.size())
	if spots.size() < piles.size():
		return {"ok": false, "message": "En la zona hay lugar para %d pilas y hacen falta %d (%d unidades de a %d). No se colocó nada: poné menos unidades o hacé lugar." % [
				spots.size(), piles.size(), quantity, limit]}
	last_placed = Colocacion.place_items(zone["root"], _item_original, piles, spots, state, undo_redo)
	_select(last_placed)
	var sizes := PackedStringArray()
	for pile in piles:
		sizes.append(str(pile))
	return {"ok": true, "message": "Quedaron %d %s en la zona (%s), %s. %s" % [piles.size(),
			"marcador" if piles.size() == 1 else "marcadores", " + ".join(sizes),
			"seleccionado" if piles.size() == 1 else "seleccionados", _after_place_text()]}


func _place_box(count: int) -> Dictionary:
	if count <= 0:
		return {"ok": false, "message": "Con 0 cajas no se coloca nada."}
	if count > 20:
		return {"ok": false, "message": "Van hasta 20 cajas por vez."}
	var scene := load(_box_path) as PackedScene
	var probe := scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if scene != null else null
	var problem := Guardado.check_box_node(probe)
	if probe != null:
		probe.free()
	if problem != "":
		return {"ok": false, "message": problem}
	var zone := Colocacion.open_zone()
	if zone.has("error"):
		return {"ok": false, "message": zone["error"]}
	var size: Vector3 = _box_form.values["box_size"]
	var spots := Colocacion.free_box_spots(zone["root"], size, count)
	if spots.size() < count:
		return {"ok": false, "message": "En la zona hay lugar para %d %s de esas medidas y pediste %d. No se colocó nada." % [
				spots.size(), "caja" if spots.size() == 1 else "cajas", count]}
	last_placed = Colocacion.place_boxes(zone["root"], scene, spots, undo_redo)
	_select(last_placed)
	return {"ok": true, "message": "Quedaron %d %s en la zona, %s. %s" % [count, "caja" if count == 1 else "cajas",
			"seleccionada" if count == 1 else "seleccionadas", _after_place_text()]}


func _after_place_text() -> String:
	return "Movelos con las herramientas de Godot si querés. La zona quedó SIN GUARDAR: Ctrl+S o «Guardar la zona». Ctrl+Z saca lo colocado, pero no borra lo guardado ni lo saca del catálogo."


func _select(nodes: Array[Node3D]) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	for node in nodes:
		selection.add_node(node)
	EditorInterface.set_main_screen_editor("3D")
	_update_status()


func _on_save_zone() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != Destinos.ZONE_PATH:
		EditorInterface.open_scene_from_path(Destinos.ZONE_PATH)
	var saved := EditorInterface.save_scene()
	_show_result("Zona guardada." if saved == OK else "No se pudo guardar la zona (error %d)." % saved, saved == OK)
	_update_status()


# --- Ayudas --------------------------------------------------------------------------

func _show_result(text: String, ok: bool) -> void:
	_result.text = text
	_result.add_theme_color_override(&"font_color", OK_COLOR if ok else ERROR_COLOR)


## Una sección plegable; `help`, su burbujita, va pegada al título.
func _section(title: String, folded := false, help: Ayuda = null) -> VBoxContainer:
	var fold := FoldableContainer.new()
	fold.title = title
	fold.folded = folded
	if help != null:
		fold.add_title_bar_control(help)
		fold.sort_children.connect(Ayuda.beside_title.bind(fold, help))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	fold.add_child(box)
	_body.add_child(fold)
	return box


func _toggle(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	return button


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


## Un texto que se parte en renglones, con un ancho mínimo: sin ancho (con la
## pestaña oculta) se partía letra por letra y su alto estiraba todo el editor.
func _wrapped_label(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WRAP_WIDTH
	parent.add_child(label)
	return label
