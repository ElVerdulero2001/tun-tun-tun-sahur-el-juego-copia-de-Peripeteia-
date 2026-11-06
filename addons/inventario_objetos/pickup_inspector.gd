@tool
extends EditorInspectorPlugin

const Destinos := preload("destinos.gd")
const ObjetosPanel := preload("objetos_panel.gd")


func _can_handle(object: Object) -> bool:
	return object is InvPickupSpawn


func _parse_property(_object: Object, _type: Variant.Type, property: String, _hint_type: PropertyHint,
		_hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if property != "item":
		return false
	add_property_editor(property, ItemPicker.new(), false, "Ítem del catálogo")
	return true


class ItemPicker extends EditorProperty:
	var _pick := Button.new()
	var _clear := Button.new()
	var _warning := Label.new()
	var _popup := PopupPanel.new()
	var _search := LineEdit.new()
	var _list := ItemList.new()
	var _entries: Array[InvItemDef] = []

	func _init() -> void:
		var buttons := HBoxContainer.new()
		add_child(buttons)
		buttons.add_child(_pick)
		_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_pick.pressed.connect(_open)
		add_focusable(_pick)
		buttons.add_child(_clear)
		_clear.text = "Quitar"
		_clear.pressed.connect(_set_item.bind(null))
		add_focusable(_clear)

		add_child(_warning)
		set_bottom_editor(_warning)
		_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		add_child(_popup)
		_popup.title = "Elegir ítem del catálogo"
		var body := VBoxContainer.new()
		_popup.add_child(body)
		body.add_child(_search)
		_search.placeholder_text = "Buscar por nombre o ID"
		_search.text_changed.connect(_filter)
		_search.text_submitted.connect(func(_text: String) -> void: _choose(0))
		body.add_child(_list)
		_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_list.item_clicked.connect(func(index: int, _at: Vector2, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_choose(index))
		_list.item_activated.connect(_choose)

	func _update_property() -> void:
		var item := get_edited_object().get(get_edited_property()) as InvItemDef
		_pick.text = _item_label(item) if item != null else "Elegir ítem…"
		_pick.tooltip_text = item.resource_path if item != null else ""
		_clear.disabled = item == null or is_read_only()
		_pick.disabled = is_read_only()
		var catalog := Destinos.lab_catalog()
		_warning.text = ""
		if catalog == null:
			_warning.text = "No se encontró el catálogo del laboratorio."
		elif item != null and not catalog.items.has(item):
			_warning.text = "El ítem asignado no pertenece al catálogo del laboratorio."
		_warning.visible = not _warning.text.is_empty()

	func _open() -> void:
		var catalog := Destinos.lab_catalog()
		_entries.clear()
		if catalog != null:
			for item in catalog.items:
				if item != null and item.id != &"":
					_entries.append(item)
		_search.clear()
		_filter("")
		_popup.popup_centered(Vector2i(460, 330))
		_search.grab_focus()

	func _filter(query: String) -> void:
		_list.clear()
		var words := ObjetosPanel.plain_text(query).split(" ", false)
		for item in _entries:
			var label := _item_label(item)
			var key := ObjetosPanel.plain_text(label)
			var matches := true
			for word in words:
				if not key.contains(word):
					matches = false
					break
			if matches:
				var index := _list.add_item(label)
				_list.set_item_metadata(index, item)
		if _list.item_count == 0:
			var index := _list.add_item("No hay ítems que coincidan.")
			_list.set_item_disabled(index, true)

	func _choose(index: int) -> void:
		var item := _list.get_item_metadata(index) as InvItemDef
		if item != null:
			_popup.hide()
			_set_item(item)

	func _set_item(item: InvItemDef) -> void:
		var marker := get_edited_object() as InvPickupSpawn
		if marker == null or is_read_only() or marker.item == item:
			return
		# Cada elección es discreta, incluso si se hacen dos seguidas.
		var undo_redo := EditorInterface.get_editor_undo_redo()
		undo_redo.create_action("Cambiar ítem del punto de aparición", UndoRedo.MERGE_DISABLE, marker)
		undo_redo.add_do_property(marker, &"item", item)
		undo_redo.add_undo_property(marker, &"item", marker.item)
		undo_redo.commit_action()

	func _item_label(item: InvItemDef) -> String:
		return "%s (%s)" % [item.display_name, item.id]
