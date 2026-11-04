@tool
extends VBoxContainer

## Formulario de un contenedor del panel Objetos: una caja fija del mundo con
## inventario propio (InvContainer). Escribe cada cambio en `values`, nunca en
## la escena guardada, y avisa con `edited`. Guardar lo hace el panel.

signal edited

const Guardado := preload("guardado.gd")
const Destinos := preload("destinos.gd")
const Ayuda := preload("ayuda.gd")
const WRAP_WIDTH := 200.0

## {"node_name", y los campos de Guardado.BOX_FIELDS}.
var values := {}
var is_new := true
## Su escena, o dónde se crearía si es nueva.
var path := ""
var read_only := false

var _loading := false
var _node_touched := false
var _path_touched := false

var _name: LineEdit
var _node_name: LineEdit
var _path_edit: LineEdit
var _path_help: Ayuda
var _columns: EditorSpinSlider
var _rows: EditorSpinSlider
var _size: Array[EditorSpinSlider] = []
var _color: ColorPickerButton
var _reach: EditorSpinSlider
var _notes: Label
var _read_only_note: Label


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_read_only_note = _note(self, "La caja base no se cambia desde acá: usá Duplicar para hacer una propia.")
	var identity := _section("Identidad")
	var grid := _grid(identity)
	_name = LineEdit.new()
	_name.placeholder_text = "Armario"
	_name.text_changed.connect(_on_name_changed)
	_row(grid, "Nombre", _name)
	_node_name = LineEdit.new()
	_node_name.text_changed.connect(func(text: String) -> void:
		if _loading:
			return
		_node_touched = true
		_put("node_name", text.strip_edges()))
	_row(grid, "Nodo", _node_name)
	_path_edit = LineEdit.new()
	_path_edit.text_changed.connect(func(text: String) -> void:
		if _loading:
			return
		_path_touched = true
		path = text.strip_edges()
		edited.emit())
	_path_help = Ayuda.new()
	_row(grid, "Escena", _path_edit, _path_help)
	var inside := _section("Inventario y caja", Ayuda.new("Se crea vacío: lo de adentro se pone jugando. Cada caja colocada tiene su propio inventario, aunque sean de la misma escena."))
	var grid2 := _grid(inside)
	_columns = _int_spin(1, Guardado.MAX_CELLS)
	_rows = _int_spin(1, Guardado.MAX_CELLS)
	_columns.value_changed.connect(func(v: float) -> void: _put("columns", int(v)))
	_rows.value_changed.connect(func(v: float) -> void: _put("rows", int(v)))
	_row(grid2, "Grilla", _line([_columns, _label("×"), _rows]), Ayuda.new("Las celdas de su inventario: columnas × filas."))
	for axis in ["x", "y", "z"]:
		var spin := _float_spin(0.1, 10.0, 0.05, " m")
		spin.label = axis
		spin.value_changed.connect(func(_v: float) -> void:
			_put("box_size", Vector3(_size[0].value, _size[1].value, _size[2].value)))
		_size.append(spin)
	_row(grid2, "Medidas de la caja", _column(_size),
			Ayuda.new("Ancho (x), alto (y) y largo (z) de la caja que se ve y choca, apoyada en el piso."))
	_color = ColorPickerButton.new()
	_color.custom_minimum_size = Vector2(60, 24)
	_color.color_changed.connect(func(value: Color) -> void: _put("color", value))
	_row(grid2, "Color", _color)
	_reach = _float_spin(0.3, 20.0, 0.1, " m")
	_reach.value_changed.connect(func(v: float) -> void: _put("access_range", v))
	_row(grid2, "Alcance", _reach,
			Ayuda.new("Hasta qué distancia, de los pies del jugador al centro de la caja, se abre con E. Más lejos, se cierra sola."))
	_notes = _note(inside, "")


## Muestra esos valores (una copia). `p_path`: su escena, o dónde se crearía.
func load_values(p_values: Dictionary, p_is_new: bool, p_path: String, p_read_only: bool) -> void:
	values = p_values.duplicate(true)
	is_new = p_is_new
	read_only = p_read_only
	_loading = true
	_name.text = String(values["display_name"])
	_node_name.text = String(values["node_name"])
	_node_touched = is_new and String(values["node_name"]) != _node_for(_name.text)
	path = p_path if p_path != "" else _default_path(_name.text)
	_path_edit.text = path
	_path_touched = is_new and path != _default_path(_name.text)
	_path_edit.editable = is_new
	if read_only:
		_path_help.explanation = "Es la caja base: de ella heredan todos los contenedores."
	elif is_new:
		_path_help.explanation = "Dónde se guarda. La escena nueva hereda de caja.tscn: trae su inventario y lo enlaza solo. Sale del nombre; se puede cambiar antes de crearla."
	else:
		_path_help.explanation = "Dónde está guardada. Ya está creada: la escena no se cambia de lugar desde acá."
	_columns.value = int(values["columns"])
	_rows.value = int(values["rows"])
	var size: Vector3 = values["box_size"]
	for i in 3:
		_size[i].value = size[i]
	_color.color = values["color"]
	_reach.value = float(values["access_range"])
	_read_only_note.visible = read_only
	for control: Control in [_name, _node_name, _columns, _rows, _size[0], _size[1], _size[2], _color, _reach]:
		if control is LineEdit:
			(control as LineEdit).editable = not read_only
		elif control is Range:
			(control as EditorSpinSlider).read_only = read_only
		elif control is BaseButton:
			(control as BaseButton).disabled = read_only
	_loading = false


func set_notes(lines: PackedStringArray) -> void:
	_notes.text = "\n".join(lines)
	_notes.visible = not lines.is_empty()


func _put(field: String, value: Variant) -> void:
	if _loading or read_only:
		return
	values[field] = value
	edited.emit()


func _on_name_changed(text: String) -> void:
	if _loading:
		return
	values["display_name"] = text.strip_edges()
	if is_new and not _node_touched:
		values["node_name"] = _node_for(text)
		_loading = true
		_node_name.text = values["node_name"]
		_loading = false
	if is_new and not _path_touched:
		path = _default_path(text)
		_loading = true
		_path_edit.text = path
		_loading = false
	edited.emit()


static func _node_for(text: String) -> String:
	var id := Guardado.id_for(text)
	return id.to_pascal_case() if id != "" else "Contenedor"


static func _default_path(text: String) -> String:
	var id := Guardado.id_for(text)
	return Destinos.CONTAINERS_DIR.path_join((id if id != "" else "contenedor") + ".tscn")


## Una sección plegable; `help`, su burbujita, va pegada al título.
func _section(title: String, help: Ayuda = null) -> VBoxContainer:
	var fold := FoldableContainer.new()
	fold.title = title
	if help != null:
		fold.add_title_bar_control(help)
		fold.sort_children.connect(Ayuda.beside_title.bind(fold, help))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	fold.add_child(box)
	add_child(fold)
	return box


## Una columna de campos, cada uno con su nombre arriba: así entra en un
## panel angosto sin cortarse.
func _grid(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	return box


## Arriba el nombre, con su burbujita al lado si tiene (`help`), y abajo el control.
func _row(box: VBoxContainer, text: String, control: Control, help: Ayuda = null) -> void:
	var label := _label(text)
	label.modulate = Color(1, 1, 1, 0.8)
	var header: Control = label
	if help != null:
		header = _line([label, help])
	header.visible = text != ""
	box.add_child(header)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)


## Un control abajo del otro, a lo ancho (los x, y, z de un vector).
func _column(controls: Array) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	for control: Control in controls:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(control)
	return column


func _line(controls: Array) -> HBoxContainer:
	var line := HBoxContainer.new()
	for control: Control in controls:
		if control is Range:
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(control)
	return line


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


## Un texto que se parte en renglones, con un ancho mínimo (ver formulario_item.gd).
func _note(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WRAP_WIDTH
	label.modulate = Color(1, 1, 1, 0.65)
	parent.add_child(label)
	return label


## Un número entero, con el control del Inspector (angosto). Lo guardado
## fuera del rango se muestra tal cual: lo avisa la validación al guardar.
func _int_spin(low: int, high: int) -> EditorSpinSlider:
	var spin := EditorSpinSlider.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = 1
	spin.rounded = true
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.hide_slider = true
	spin.custom_minimum_size.x = 48
	return spin


## Un número con decimales, con el control del Inspector (angosto): se
## arrastra o se escribe. Va de a milésimas (de a décimas los grados), así lo
## guardado no se redondea al abrirlo; lo que estaba fuera del rango se
## muestra tal cual y lo avisa la validación al guardar.
func _float_spin(low: float, high: float, step: float, suffix: String) -> EditorSpinSlider:
	var spin := EditorSpinSlider.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = 0.1 if step >= 1.0 else 0.001
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.hide_slider = true
	spin.suffix = suffix
	spin.custom_minimum_size.x = 48
	return spin
