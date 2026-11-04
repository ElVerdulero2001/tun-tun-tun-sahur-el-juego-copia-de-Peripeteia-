@tool
extends VBoxContainer

## Editor de un estado (un Dictionary de datos), de a pares nombre-valor: el
## estado inicial de un ítem o el que cambia una aparición. Cada valor es un
## número entero, un número con decimales, un texto o sí/no. Lo que traiga de
## otro tipo (una lista, un vector) se muestra sin editar y se conserva; para
## cambiarlo, el Inspector. Nunca se evalúa lo que se escribe.

signal changed

enum Kind { INT, FLOAT, TEXT, BOOL, KEEP }
const KIND_NAMES := ["Número entero", "Número con decimales", "Texto", "Sí o no"]

var _rows: VBoxContainer
var _empty: Label
var _loading := false


func _init() -> void:
	add_theme_constant_override("separation", 4)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	add_child(_rows)
	_empty = Label.new()
	_empty.text = "Sin datos: todas las unidades nacen iguales."
	# Partido en renglones y con un ancho mínimo, para no ensanchar el panel.
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size.x = 160
	_empty.modulate = Color(1, 1, 1, 0.6)
	add_child(_empty)
	var add := Button.new()
	add.text = "+ Agregar un dato"
	add.pressed.connect(func() -> void:
		_add_row("", 0)
		changed.emit())
	add_child(add)


## Lo que dice cuando no hay ningún dato.
func set_empty_text(text: String) -> void:
	_empty.text = text


## Muestra ese estado (una copia: lo de afuera no se toca).
func set_state(state: Dictionary) -> void:
	_loading = true
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for key: Variant in state:
		_add_row(String(key), state[key])
	_loading = false
	_empty.visible = _rows.get_child_count() == 0


## El estado escrito, con los nombres sin espacios a los costados.
func get_state() -> Dictionary:
	var state := {}
	for row in _rows.get_children():
		state[row.get_meta(&"key").text.strip_edges()] = _value_of(row)
	return state


## Lo que está mal escrito: nombres vacíos o repetidos.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var seen := {}
	for row in _rows.get_children():
		var key: String = row.get_meta(&"key").text.strip_edges()
		if key == "":
			found.append("hay un dato sin nombre")
		elif seen.has(key):
			found.append("el dato %s está dos veces" % key)
		seen[key] = true
		var kind := int(row.get_meta(&"kind"))
		if kind in [Kind.INT, Kind.FLOAT]:
			var text := (row.get_meta(&"value") as LineEdit).text.strip_edges().replace(",", ".")
			if (kind == Kind.INT and not text.is_valid_int()) or (kind == Kind.FLOAT and not text.is_valid_float()):
				found.append("%s no es un número %s" % [key if key != "" else "un dato", "entero" if kind == Kind.INT else "válido"])
	return found


## Un dato, en dos renglones para que entre en un panel angosto: arriba su
## nombre y el botón para quitarlo; abajo su tipo y su valor.
func _add_row(key: String, value: Variant) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	var bottom := HBoxContainer.new()
	row.add_child(top)
	row.add_child(bottom)
	row.set_meta(&"bottom", bottom)
	var key_edit := LineEdit.new()
	key_edit.text = key
	key_edit.placeholder_text = "nombre del dato, por ejemplo carga"
	key_edit.custom_minimum_size.x = 60
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_edit.text_changed.connect(func(_text: String) -> void: _emit())
	top.add_child(key_edit)
	row.set_meta(&"key", key_edit)
	var kind := _kind_of(value)
	row.set_meta(&"kind", kind)
	if kind == Kind.KEEP:
		var kept := Label.new()
		kept.text = "%s (se conserva; se cambia en el Inspector)" % type_string(typeof(value))
		kept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kept.clip_text = true
		bottom.add_child(kept)
		row.set_meta(&"kept", value)
	else:
		var type_pick := OptionButton.new()
		for kind_name in KIND_NAMES:
			type_pick.add_item(kind_name)
		type_pick.select(kind)
		type_pick.fit_to_longest_item = false
		type_pick.clip_text = true
		type_pick.custom_minimum_size.x = 40
		type_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		type_pick.item_selected.connect(func(index: int) -> void:
			_set_value_editor(row, index, _convert(_value_of(row), index))
			_emit())
		bottom.add_child(type_pick)
		_set_value_editor(row, kind, value)
	var remove := Button.new()
	remove.icon = EditorInterface.get_editor_theme().get_icon(&"Remove", &"EditorIcons")
	remove.flat = true
	remove.tooltip_text = "Quitar este dato"
	remove.pressed.connect(func() -> void:
		_rows.remove_child(row)
		row.queue_free()
		_empty.visible = _rows.get_child_count() == 0
		_emit())
	top.add_child(remove)
	_rows.add_child(row)
	_empty.visible = false


func _set_value_editor(row: VBoxContainer, kind: int, value: Variant) -> void:
	var bottom: HBoxContainer = row.get_meta(&"bottom")
	if row.has_meta(&"value"):
		var old: Control = row.get_meta(&"value")
		bottom.remove_child(old)
		old.queue_free()
	row.set_meta(&"kind", kind)
	var editor: Control
	match kind:
		Kind.INT, Kind.FLOAT:
			# Un texto y no un SpinBox: el SpinBox redondea al paso, y un
			# número guardado con más decimales cambiaría sin que lo toques.
			var number := LineEdit.new()
			number.text = str(value) if kind == Kind.INT else var_to_str(float(value))
			number.custom_minimum_size.x = 60
			number.text_changed.connect(func(_text: String) -> void: _emit())
			editor = number
		Kind.TEXT:
			var line := LineEdit.new()
			line.text = value
			line.custom_minimum_size.x = 60
			line.text_changed.connect(func(_text: String) -> void: _emit())
			editor = line
		Kind.BOOL:
			var check := CheckBox.new()
			check.text = "Sí"
			check.button_pressed = value
			check.toggled.connect(func(_on: bool) -> void: _emit())
			editor = check
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(editor)
	row.set_meta(&"value", editor)


func _value_of(row: Node) -> Variant:
	match int(row.get_meta(&"kind")):
		Kind.INT:
			return (row.get_meta(&"value") as LineEdit).text.strip_edges().to_int()
		Kind.FLOAT:
			return (row.get_meta(&"value") as LineEdit).text.strip_edges().replace(",", ".").to_float()
		Kind.TEXT:
			return (row.get_meta(&"value") as LineEdit).text
		Kind.BOOL:
			return (row.get_meta(&"value") as CheckBox).button_pressed
	return row.get_meta(&"kept")


static func _kind_of(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return Kind.INT
		TYPE_FLOAT:
			return Kind.FLOAT
		TYPE_STRING:
			return Kind.TEXT
		TYPE_BOOL:
			return Kind.BOOL
	return Kind.KEEP


## El valor pasado a otro tipo, lo más parecido que se pueda.
static func _convert(value: Variant, kind: int) -> Variant:
	match kind:
		Kind.INT:
			return int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL] else String(value).to_int()
		Kind.FLOAT:
			return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL] else String(value).to_float()
		Kind.TEXT:
			return str(value)
		Kind.BOOL:
			return bool(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL] else String(value) in ["true", "sí", "si", "1"]
	return value


func _emit() -> void:
	if not _loading:
		changed.emit()
