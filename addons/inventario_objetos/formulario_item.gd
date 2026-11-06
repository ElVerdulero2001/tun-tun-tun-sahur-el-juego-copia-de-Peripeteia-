@tool
extends VBoxContainer

## Formulario de un ítem del panel Objetos. Escribe cada cambio en el borrador
## (`draft`, una copia de trabajo), nunca en el recurso guardado, y avisa con
## `edited`. Guardar lo hace el panel.

signal edited

const Guardado := preload("guardado.gd")
const Destinos := preload("destinos.gd")
const EditorEstado := preload("editor_estado.gd")
const Acomodador := preload("acomodador.gd")
const Ayuda := preload("ayuda.gd")

enum Shape { NONE, BOX, CYLINDER, SPHERE, CAPSULE, FILE, OTHER }
const SHAPE_NAMES := ["Sin malla", "Caja", "Cilindro", "Esfera", "Cápsula", "Malla de un archivo…", "Malla propia (se conserva)"]
## Las medidas que se editan de cada forma simple: [texto, propiedad, eje].
const SHAPE_DIMS := {
	Shape.BOX: [["Ancho", &"size", 0], ["Alto", &"size", 1], ["Largo", &"size", 2]],
	Shape.CYLINDER: [["Radio de arriba", &"top_radius", -1], ["Radio de abajo", &"bottom_radius", -1], ["Alto", &"height", -1]],
	Shape.SPHERE: [["Radio", &"radius", -1]],
	Shape.CAPSULE: [["Radio", &"radius", -1], ["Alto", &"height", -1]],
}
const WRAP_WIDTH := 200.0

var draft: Resource
var is_new := true
## Dónde se guarda: la del recurso si ya existe; si es nuevo, la elegida.
var path := ""

var _loading := false
var _id_touched := false
var _path_touched := false

var _name: LineEdit
var _description: TextEdit
var _id: LineEdit
var _id_help: Ayuda
var _path_edit: LineEdit
var _path_help: Ayuda
var _width: EditorSpinSlider
var _height: EditorSpinSlider
var _rotates: CheckBox
var _stacks: CheckBox
var _stack_size: EditorSpinSlider
var _grid_notes: Label
var _model_help: Ayuda
var _model: EditorResourcePicker
var _shape: OptionButton
var _dims: GridContainer
var _mesh_file: EditorResourcePicker
var _mesh_file_label: Control
var _color: ColorPickerButton
var _simple_look: VBoxContainer
var _world_size: EditorSpinSlider
var _arranger: Acomodador
var _arranger_buttons: Array[Button] = []
var _abilities: VBoxContainer
var _add_use: Button
var _add_equip: Button
var _state: EditorEstado


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_build_identity()
	_build_grid()
	_build_look()
	_build_thumbnail()
	_build_abilities()
	_build_state()


# --- Armado ----------------------------------------------------------------------

func _build_identity() -> void:
	var box := _section("Identidad")
	var grid := _grid(box)
	_name = LineEdit.new()
	_name.placeholder_text = "Cuerda"
	_name.text_changed.connect(_on_name_changed)
	_row(grid, "Nombre", _name)
	_description = TextEdit.new()
	_description.custom_minimum_size.y = 64
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description.placeholder_text = "Lo que se lee al inspeccionarlo."
	_description.text_changed.connect(func() -> void: _put(&"description", _description.text))
	_row(grid, "Descripción", _description)
	_id = LineEdit.new()
	_id.text_changed.connect(_on_id_changed)
	_id_help = _help("")
	_row(grid, "ID", _id, _id_help)
	_path_edit = LineEdit.new()
	_path_edit.text_changed.connect(func(text: String) -> void:
		if _loading:
			return
		_path_touched = true
		path = text.strip_edges()
		edited.emit())
	_path_help = _help("")
	_row(grid, "Archivo", _path_edit, _path_help)


func _build_grid() -> void:
	var box := _section("Grilla y pila")
	var grid := _grid(box)
	_width = _int_spin(1, Guardado.MAX_CELLS)
	_height = _int_spin(1, Guardado.MAX_CELLS)
	_width.value_changed.connect(func(_v: float) -> void: _put(&"size", Vector2i(int(_width.value), int(_height.value))))
	_height.value_changed.connect(func(_v: float) -> void: _put(&"size", Vector2i(int(_width.value), int(_height.value))))
	_row(grid, "Celdas", _line([_width, _label("×"), _height]))
	_rotates = CheckBox.new()
	_rotates.text = "Se gira (R, de a 90°)"
	_rotates.toggled.connect(func(on: bool) -> void: _put(&"can_rotate", on))
	_row(grid, "", _rotates)
	_stacks = CheckBox.new()
	_stacks.text = "Se apila, hasta"
	_stack_size = _int_spin(1, Guardado.MAX_STACK)
	_stacks.toggled.connect(func(on: bool) -> void:
		_stack_size.read_only = not on
		if on and _stack_size.value < 2 and not _loading:
			_stack_size.value = 2
		_put(&"stackable", on))
	_stack_size.value_changed.connect(func(v: float) -> void: _put(&"max_stack", int(v)))
	_row(grid, "", _line([_stacks, _stack_size]))
	_grid_notes = _note(box, "")


## Cómo se ve: el modelo o, si no hay, una forma simple de un color. Lo que no
## se usa no se muestra (la forma y el color, cuando hay modelo).
func _build_look() -> void:
	var box := _section("Apariencia", _help("Cómo se ve en el piso, en la mano y en la miniatura del inventario: con su modelo; si no tiene, con la forma simple; si tampoco, como una caja de su color."))
	var grid := _grid(box)
	_model = EditorResourcePicker.new()
	_model.base_type = "PackedScene"
	_model.custom_minimum_size.x = 120
	_model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model.resource_changed.connect(func(resource: Resource) -> void:
		_put(&"model", resource)
		_refresh_source())
	_model_help = _help("")
	_row(grid, "Modelo", _model, _model_help)
	_simple_look = VBoxContainer.new()
	_simple_look.add_theme_constant_override("separation", 4)
	box.add_child(_simple_look)
	var simple := _grid(_simple_look)
	_shape = OptionButton.new()
	for shape_name in SHAPE_NAMES:
		_shape.add_item(shape_name)
	_shape.fit_to_longest_item = false
	_shape.clip_text = true
	_shape.item_selected.connect(_on_shape_selected)
	_row(simple, "Forma simple", _shape)
	_mesh_file = EditorResourcePicker.new()
	_mesh_file.base_type = "Mesh"
	_mesh_file.custom_minimum_size.x = 120
	_mesh_file.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mesh_file.resource_changed.connect(func(resource: Resource) -> void:
		_put(&"mesh", resource)
		_refresh_source())
	_mesh_file_label = _row(simple, "Archivo de la malla", _mesh_file)
	_dims = GridContainer.new()
	_dims.columns = 2
	_simple_look.add_child(_dims)
	var simple2 := _grid(_simple_look)
	_color = ColorPickerButton.new()
	_color.custom_minimum_size = Vector2(60, 24)
	_color.color_changed.connect(func(value: Color) -> void: _put(&"color", value))
	_row(simple2, "Color", _color)
	var grid2 := _grid(box)
	_world_size = _float_spin(0.02, 10.0, 0.01, " m")
	_world_size.value_changed.connect(func(v: float) -> void: _put(&"world_size", v))
	_row(grid2, "Tamaño en el piso", _world_size, _help("Lo que mide su lado más largo cuando está suelto en el mundo."))


## La miniatura del inventario, para acomodarla con el mouse y unos botones.
func _build_thumbnail() -> void:
	var box := _section("Miniatura del inventario", _help("Así se ve en la grilla. Arrastrá para girarlo (con Ctrl, de a 15°); con el botón derecho, correlo; la rueda lo acerca o lo aleja."))
	_arranger = Acomodador.new()
	_arranger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_arranger.changed.connect(func() -> void: edited.emit())
	box.add_child(_arranger)
	_arranger_buttons = [
		_button("↺ 90°", "Un cuarto de vuelta, para la izquierda.", _arranger.turn.bind(Vector3.BACK, 90.0)),
		_button("↻ 90°", "Un cuarto de vuelta, para la derecha.", _arranger.turn.bind(Vector3.BACK, -90.0)),
		_button("De frente", "Sin giro: como se lo ve de frente.", _arranger.face_front),
		_button("Centrar", "En el medio del cuadro y sin acercar.", _arranger.center),
		_button("Automático", "Como sale solo: en diagonal, acostado si su lado largo no coincide con el de la huella, y en el medio.",
				_arranger.automatic),
	]
	box.add_child(_line(_arranger_buttons.slice(0, 2)))
	box.add_child(_line(_arranger_buttons.slice(2, 4)))
	box.add_child(_arranger_buttons[4])


## Vuelve a dibujar la miniatura con lo que tiene el borrador ahora.
func refresh_thumbnail() -> void:
	_arranger.show_item(draft)
	for button: Button in _arranger_buttons:
		button.disabled = not _arranger.has_image()


func _build_abilities() -> void:
	var box := _section("Capacidades", _help("\n\n".join([
		"Sin capacidades, se recoge, se guarda, se pasa y se suelta. La primera de la lista es la que hace su acceso de la barra rápida (1 a 9 y 0).",
		"Consumible: al usarlo cura o daña la salud, o recupera estamina, y gasta una unidad.",
		"Equipable: se lleva en la mano sin sacarlo de la grilla, y los demás lo ven. Solo se lleva: no dispara, no pega ni ilumina.",
	])))
	_abilities = VBoxContainer.new()
	_abilities.add_theme_constant_override("separation", 6)
	box.add_child(_abilities)
	_add_use = Button.new()
	_add_use.text = "+ Consumible"
	_add_use.tooltip_text = "Al usarlo cura o daña la salud, o recupera estamina, y gasta una unidad."
	_add_use.pressed.connect(func() -> void: _add_ability(InvConsumable.new()))
	_add_equip = Button.new()
	_add_equip.text = "+ Equipable"
	_add_equip.tooltip_text = "Se lleva en la mano sin sacarlo de la grilla; los demás lo ven."
	_add_equip.pressed.connect(func() -> void: _add_ability(InvEquippable.new()))
	box.add_child(_add_use)
	box.add_child(_add_equip)


func _build_state() -> void:
	var box := _section("Estado inicial", _help("\n\n".join([
		"Opcional. Son datos que lleva cada unidad del objeto, y con estos valores nace. Ejemplo: una batería con carga = 100.",
		"Para qué sirve hoy: dos unidades del mismo objeto se juntan en una pila solo si sus datos son iguales. Una batería con carga 100 y otra con carga 40 no se apilan, aunque se llamen igual.",
		"Hoy ningún dato cambia solo al jugar: la carga no baja. Queda listo para mecánicas futuras. Si no lo necesitás, dejalo vacío.",
	])), true)
	_state = EditorEstado.new()
	_state.changed.connect(func() -> void:
		if _state.problems().is_empty():
			_put(&"default_state", _state.get_state())
		elif not _loading:
			edited.emit())
	box.add_child(_state)


# --- Cargar y escribir -------------------------------------------------------------

## Muestra ese borrador. `p_path`: su archivo, o dónde se crearía si es nuevo.
func load_draft(p_draft: Resource, p_is_new: bool, p_path: String) -> void:
	draft = p_draft
	is_new = p_is_new
	_loading = true
	var shown := String(draft.get(&"display_name"))
	var id := String(draft.get(&"id"))
	_name.text = shown
	_description.text = String(draft.get(&"description"))
	_id.text = id
	_id.editable = is_new
	_id_touched = is_new and id != "" and id != Guardado.id_for(shown)
	path = p_path if p_path != "" else _default_path(id)
	_path_edit.text = path
	_path_edit.editable = is_new
	_path_touched = is_new and path != _default_path(id)
	_id_help.explanation = "El nombre interno del ítem: es lo que viaja por red. Sale del nombre; se puede cambiar antes de crearlo." if is_new \
			else "El nombre interno del ítem: es lo que viaja por red. Ya está creado: no se cambia desde acá (cambiarlo rompería sus referencias)."
	_path_help.explanation = "Dónde se guarda su .tres. Sale del ID; se puede cambiar antes de crearlo." if is_new \
			else "Dónde está guardado. Ya está creado: no se cambia de lugar desde acá (rompería sus referencias)."
	var cells: Vector2i = draft.get(&"size")
	_width.value = cells.x
	_height.value = cells.y
	_rotates.button_pressed = draft.get(&"can_rotate")
	_stacks.button_pressed = draft.get(&"stackable")
	_stack_size.value = int(draft.get(&"max_stack"))
	_stack_size.read_only = not _stacks.button_pressed
	_model.edited_resource = draft.get(&"model")
	_show_shape()
	_color.color = draft.get(&"color")
	_world_size.value = float(draft.get(&"world_size"))
	_state.set_state(draft.get(&"default_state"))
	_rebuild_abilities()
	_refresh_source()
	refresh_thumbnail()
	_loading = false


## Lo escrito que todavía no se pudo pasar al borrador (un estado mal escrito).
func form_problems() -> PackedStringArray:
	var found := PackedStringArray()
	for problem in _state.problems():
		found.append("Estado inicial: " + problem + ".")
	return found


func set_notes(lines: PackedStringArray) -> void:
	_grid_notes.text = "\n".join(lines)
	_grid_notes.visible = not lines.is_empty()


func _put(field: StringName, value: Variant) -> void:
	if _loading or draft == null:
		return
	draft.set(field, value)
	edited.emit()


func _on_name_changed(text: String) -> void:
	if _loading:
		return
	_put(&"display_name", text.strip_edges())
	if is_new and not _id_touched:
		_set_id(Guardado.id_for(text))


func _on_id_changed(text: String) -> void:
	if _loading:
		return
	_id_touched = true
	_set_id(text.strip_edges(), false)


func _set_id(id: String, show := true) -> void:
	if show:
		_loading = true
		_id.text = id
		_loading = false
	draft.set(&"id", StringName(id))
	if not _path_touched:
		path = _default_path(id)
		_loading = true
		_path_edit.text = path
		_loading = false
	edited.emit()


static func _default_path(id: String) -> String:
	return Destinos.ITEMS_DIR.path_join((id if id != "" else "nuevo") + ".tres")


# --- Apariencia --------------------------------------------------------------------

func _shape_of(mesh: Resource) -> int:
	if mesh == null:
		return Shape.NONE
	if Guardado.is_external(mesh):
		return Shape.FILE
	if mesh is BoxMesh:
		return Shape.BOX
	if mesh is CylinderMesh:
		return Shape.CYLINDER
	if mesh is SphereMesh:
		return Shape.SPHERE
	if mesh is CapsuleMesh:
		return Shape.CAPSULE
	return Shape.OTHER


func _show_shape() -> void:
	var mesh: Resource = draft.get(&"mesh")
	var shape := _shape_of(mesh)
	_shape.select(shape)
	_shape.set_item_disabled(Shape.OTHER, shape != Shape.OTHER)
	_mesh_file.edited_resource = mesh if shape == Shape.FILE else null
	_mesh_file_label.visible = shape == Shape.FILE
	_mesh_file.visible = shape == Shape.FILE
	for child in _dims.get_children():
		_dims.remove_child(child)
		child.queue_free()
	for dim: Array in SHAPE_DIMS.get(shape, []):
		var spin := _float_spin(0.005, 10.0, 0.005, " m")
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value: Variant = mesh.get(dim[1])
		spin.value = value[dim[2]] if dim[2] >= 0 else value
		spin.value_changed.connect(_on_dim_changed.bind(dim))
		_dims.add_child(_label(dim[0]))
		_dims.add_child(spin)


func _on_shape_selected(index: int) -> void:
	if _loading:
		return
	var mesh: Mesh = null
	match index:
		Shape.BOX:
			mesh = BoxMesh.new()
			mesh.size = Vector3(0.3, 0.2, 0.2)
		Shape.CYLINDER:
			mesh = CylinderMesh.new()
			mesh.top_radius = 0.05
			mesh.bottom_radius = 0.05
			mesh.height = 0.25
		Shape.SPHERE:
			mesh = SphereMesh.new()
			mesh.radius = 0.1
			mesh.height = 0.2
		Shape.CAPSULE:
			mesh = CapsuleMesh.new()
			mesh.radius = 0.06
			mesh.height = 0.3
		Shape.FILE, Shape.OTHER:
			var current: Resource = draft.get(&"mesh")
			mesh = current if _shape_of(current) == index else null
	_put(&"mesh", mesh)
	_loading = true
	_show_shape()
	_loading = false
	_refresh_source()


func _on_dim_changed(value: float, dim: Array) -> void:
	if _loading:
		return
	var mesh: Resource = draft.get(&"mesh")
	if dim[2] >= 0:
		var size: Vector3 = mesh.get(dim[1])
		size[dim[2]] = value
		mesh.set(dim[1], size)
	else:
		mesh.set(dim[1], value)
		if mesh is SphereMesh:
			mesh.set(&"height", value * 2.0)
	edited.emit()


## Qué se ve y por qué: el modelo, si hay; si no, la malla; si no, una caja
## del color (InvVisuals).
func _refresh_source() -> void:
	var model: Resource = draft.get(&"model")
	var mesh: Mesh = draft.get(&"mesh")
	# Con modelo, la forma simple y el color no se usan: no se muestran.
	_simple_look.visible = model == null
	var text := ""
	if model != null:
		text = "Ahora se ve el modelo. Para usar una forma simple, sacá el modelo (la flecha de al lado → Clear)."
		if mesh != null:
			text += " Tiene una forma guardada que no se usa mientras haya modelo."
	elif mesh != null:
		var material := mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else null
		text = "Sin modelo: se ve la forma simple, con su material." if material != null else "Sin modelo: se ve la forma simple, del color de abajo."
	else:
		text = "Sin modelo ni forma: en el piso se ve una caja del color de abajo, y en el inventario, un rectángulo de ese color con el nombre."
	_model_help.explanation = "\n\n".join([
		"Se arrastra desde FileSystem: un .glb o un .tscn. Del modelo solo se usan sus mallas: no corren sus scripts, ni su física, ni sus efectos.",
		text,
	])


# --- Capacidades -------------------------------------------------------------------

func _rebuild_abilities() -> void:
	for child in _abilities.get_children():
		_abilities.remove_child(child)
		child.queue_free()
	var list: Array = draft.get(&"abilities")
	var kinds := {}
	for i in list.size():
		_abilities.add_child(_ability_row(list, i))
		kinds[Guardado.ability_kind(list[i])] = true
	if list.is_empty():
		var none := _label("Ninguna.")
		none.modulate = Color(1, 1, 1, 0.6)
		_abilities.add_child(none)
	_add_use.disabled = kinds.has("consumible")
	_add_equip.disabled = kinds.has("equipable")


func _add_ability(ability: Resource) -> void:
	var list: Array = draft.get(&"abilities").duplicate()
	list.append(ability)
	_set_abilities(list)


func _set_abilities(list: Array) -> void:
	var typed: Array[InvAbility] = []
	for ability: Resource in list:
		typed.append(ability)
	draft.set(&"abilities", typed)
	_rebuild_abilities()
	edited.emit()


func _ability_row(list: Array, index: int) -> Control:
	var ability: Resource = list[index]
	var kind := Guardado.ability_kind(ability)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.04)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := "Lugar vacío"
	if ability != null:
		title = "Consumible" if kind == "consumible" else "Equipable" if kind == "equipable" else "Otra capacidad"
	var header := _label("%d. %s%s" % [index + 1, title, " · barra rápida" if index == 0 else ""])
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.clip_text = true
	var up := _icon_button(&"MoveUp", "Subir (la primera es la de la barra rápida)")
	up.disabled = index == 0
	up.pressed.connect(func() -> void:
		var moved := list.duplicate()
		moved.insert(index - 1, moved.pop_at(index))
		_set_abilities(moved))
	var down := _icon_button(&"MoveDown", "Bajar")
	down.disabled = index == list.size() - 1
	down.pressed.connect(func() -> void:
		var moved := list.duplicate()
		moved.insert(index + 1, moved.pop_at(index))
		_set_abilities(moved))
	var remove := _icon_button(&"Remove", "Quitar esta capacidad")
	remove.pressed.connect(func() -> void:
		var left := list.duplicate()
		left.remove_at(index)
		_set_abilities(left))
	box.add_child(_line([header, up, down, remove]))
	if ability == null:
		return panel
	if Guardado.is_external(ability) or kind == "":
		var why := "Es un archivo aparte (%s), compartido: se conserva tal cual." % ability.resource_path.get_file() \
				if Guardado.is_external(ability) else "El panel no sabe editarla (%s): se conserva tal cual." \
				% (ability.get_script().resource_path.get_file() if ability.get_script() != null else ability.get_class())
		_note(box, why)
		var inspect := Button.new()
		inspect.text = "Abrir en el Inspector"
		inspect.pressed.connect(func() -> void: EditorInterface.inspect_object(ability))
		box.add_child(inspect)
		return panel
	var grid := _grid(box)
	if kind == "consumible":
		var summary := _note(box, "")
		var show_summary := func() -> void:
			summary.text = Guardado.consumable_summary(int(ability.get(&"health")), int(ability.get(&"stamina")),
					int(ability.get(&"damage_over_time")), float(ability.get(&"damage_seconds")), float(ability.get(&"part_repair")))
		var health := _int_spin(-Guardado.MAX_EFFECT, Guardado.MAX_EFFECT)
		health.value = int(ability.get(&"health"))
		health.value_changed.connect(func(v: float) -> void:
			ability.set(&"health", int(v))
			show_summary.call()
			edited.emit())
		_row(grid, "Efecto en la salud (puntos)", health,
				_help("Positivo cura y negativo daña. La salud completa son 100: con −100 o menos, una unidad mata (muerte de prueba). En 0, no toca la salud."))
		var stamina := _int_spin(0, Guardado.MAX_EFFECT)
		stamina.value = int(ability.get(&"stamina"))
		stamina.value_changed.connect(func(v: float) -> void:
			ability.set(&"stamina", int(v))
			show_summary.call()
			edited.emit())
		_row(grid, "Recupera estamina", stamina, _help("La reserva completa son 200 y no vuelve sola: solo con consumibles. En 0, no la toca."))
		var over_time := _int_spin(0, Guardado.MAX_EFFECT)
		over_time.value = int(ability.get(&"damage_over_time"))
		over_time.value_changed.connect(func(v: float) -> void:
			ability.set(&"damage_over_time", int(v))
			show_summary.call()
			edited.emit())
		_row(grid, "Daño en el tiempo (puntos)", over_time,
				_help("Quita esa salud de a poco, parejo, hasta terminar o hasta que te morís. Se acumulan, hasta 4 a la vez. En 0, no hace nada."))
		var seconds := _float_spin(0.1, Guardado.MAX_EFFECT_SECONDS, 0.1, " s")
		seconds.value = float(ability.get(&"damage_seconds"))
		seconds.value_changed.connect(func(v: float) -> void:
			ability.set(&"damage_seconds", v)
			show_summary.call()
			edited.emit())
		_row(grid, "En cuántos segundos", seconds,
				_help("En cuánto tiempo quita todo el daño en el tiempo: 4 en 2 s son 2 por segundo. Con la cámara lenta va más despacio."))
		# Desde el 2026-11-06 (pedido del usuario): InvConsumable.part_repair.
		var parts := _float_spin(0.0, 100.0, 0.01, " %")
		parts.value = float(ability.get(&"part_repair"))
		parts.value_changed.connect(func(v: float) -> void:
			ability.set(&"part_repair", v)
			show_summary.call()
			edited.emit())
		_row(grid, "Cura una parte del cuerpo", parts,
				_help("Con Tab, se agarra de la grilla y se suelta sobre una parte dañada del panel del cuerpo: le suma eso, sin pasar del 100 %, y gasta una unidad. 100 la deja entera; 30 lleva una del 50 % al 80 %. No toca la salud y no cambia el uso normal. En 0, no cura partes."))
		show_summary.call()
	else:
		_row(grid, "Posición (m)", _vector_editor(ability, &"hold_offset", -3.0, 3.0, 0.01, ""),
				_help("Respecto de los pies del personaje, mirando para adelante."))
		_row(grid, "Giro (°)", _vector_editor(ability, &"hold_rotation", -360.0, 360.0, 1.0, ""))
		var hold := _float_spin(0.02, 5.0, 0.01, " m")
		hold.value = float(ability.get(&"hold_size"))
		hold.value_changed.connect(func(v: float) -> void:
			ability.set(&"hold_size", v)
			edited.emit())
		_row(grid, "Tamaño", hold, _help("Lo que mide su lado más largo en la mano."))
	return panel


func _vector_editor(target: Resource, field: StringName, low: float, high: float, step: float, suffix: String) -> VBoxContainer:
	var spins: Array[EditorSpinSlider] = []
	var value: Vector3 = target.get(field)
	for i in 3:
		var spin := _float_spin(low, high, step, suffix)
		spin.label = ["x", "y", "z"][i]
		spin.value = value[i]
		spins.append(spin)
	for spin in spins:
		spin.value_changed.connect(func(_v: float) -> void:
			target.set(field, Vector3(spins[0].value, spins[1].value, spins[2].value))
			edited.emit())
	return _column(spins)


# --- Controles ---------------------------------------------------------------------

## Una sección plegable; `help`, su burbujita, va pegada al título.
func _section(title: String, help: Ayuda = null, folded := false) -> VBoxContainer:
	var fold := FoldableContainer.new()
	fold.title = title
	fold.folded = folded
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


## Arriba el nombre, con su burbujita al lado si tiene (`help`), y abajo el
## control. Devuelve el renglón del nombre.
func _row(box: VBoxContainer, text: String, control: Control, help: Ayuda = null) -> Control:
	var label := _label(text)
	label.modulate = Color(1, 1, 1, 0.8)
	var header: Control = label
	if help != null:
		header = _line([label, help])
	header.visible = text != ""
	box.add_child(header)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	return header


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


## La burbujita con el signo de pregunta: un clic muestra `text`.
func _help(text: String) -> Ayuda:
	return Ayuda.new(text)


## Un texto que se parte en renglones, con un ancho mínimo: sin ancho (con la
## pestaña oculta) se partía letra por letra y su alto estiraba todo el editor.
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


## Un botón a lo ancho que hace eso y avisa que cambió el borrador.
func _button(text: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.pressed.connect(func() -> void:
		action.call()
		edited.emit())
	return button


func _icon_button(icon: StringName, tip: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.tooltip_text = tip
	if Engine.is_editor_hint() and EditorInterface.get_editor_theme() != null:
		button.icon = EditorInterface.get_editor_theme().get_icon(icon, &"EditorIcons")
	return button
