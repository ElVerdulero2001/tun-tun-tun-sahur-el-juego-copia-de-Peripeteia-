class_name LabOptions
extends PanelContainer

## El panel Opciones del laboratorio (desde el 2026-11-14): las preferencias de
## la mano de cada jugador (InvHandPrefs), que se guardan en esta PC. Se abre y
## se cierra con F3 (acción `opciones`) o con el botón Opciones del menú del
## laboratorio; Esc también lo cierra. Mientras está abierto el mouse queda
## libre y el mundo sigue (como con el inventario). Si estabas sosteniendo
## algo, se suelta al abrirlo.
##
## Abajo, «Probá el mouse»: apretando cualquier botón del mouse sobre el panel
## dice qué número le llega a Godot y qué hace con el esquema elegido. Sirve
## para ver si el programa del mouse (Logitech G HUB u otro) cambió lo que
## mandan los laterales: tienen que llegar como 8 (trasero) y 9 (delantero).

signal opened
signal closed

const BUTTON_NAMES := {
	MOUSE_BUTTON_LEFT: "1, el izquierdo (MOUSE_BUTTON_LEFT)",
	MOUSE_BUTTON_RIGHT: "2, el derecho (MOUSE_BUTTON_RIGHT)",
	MOUSE_BUTTON_MIDDLE: "3, el central: la rueda apretada (MOUSE_BUTTON_MIDDLE)",
	MOUSE_BUTTON_WHEEL_UP: "4, la rueda para arriba (MOUSE_BUTTON_WHEEL_UP)",
	MOUSE_BUTTON_WHEEL_DOWN: "5, la rueda para abajo (MOUSE_BUTTON_WHEEL_DOWN)",
	MOUSE_BUTTON_WHEEL_LEFT: "6, la rueda inclinada a la izquierda",
	MOUSE_BUTTON_WHEEL_RIGHT: "7, la rueda inclinada a la derecha",
	MOUSE_BUTTON_XBUTTON1: "8, el lateral trasero, cerca de la palma (MOUSE_BUTTON_XBUTTON1; Windows lo llama Mouse 4)",
	MOUSE_BUTTON_XBUTTON2: "9, el lateral delantero, cerca del cable (MOUSE_BUTTON_XBUTTON2; Windows lo llama Mouse 5)",
}

var hands: InvHands
var camera: LabCamera

var _buttons: OptionButton
var _mode: OptionButton
var _probe: Label
var _summary: Label


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.94)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(_text("Opciones", 22))
	box.add_child(_text("Objetos sueltos: sostener y lanzar", 16, Color(1, 0.85, 0.5)))
	box.add_child(_text("Botones del mouse", 15))
	_buttons = OptionButton.new()
	_buttons.add_item("Principales: el derecho agarra y suelta, el izquierdo lanza", InvHandPrefs.Buttons.PRIMARY)
	_buttons.add_item("Laterales: el trasero (cerca de la palma) agarra y suelta, el delantero (cerca del cable) lanza",
			InvHandPrefs.Buttons.SIDE)
	_buttons.item_selected.connect(func(_index: int) -> void: _changed())
	box.add_child(_buttons)
	box.add_child(_text("Sostener", 15))
	_mode = OptionButton.new()
	_mode.add_item("Alternar: un clic agarra y otro clic del mismo botón suelta", InvHandPrefs.Mode.TOGGLE)
	_mode.add_item("Mantener: agarra al apretar y suelta al soltar el botón", InvHandPrefs.Mode.HOLD)
	_mode.item_selected.connect(func(_index: int) -> void: _changed())
	box.add_child(_mode)
	_summary = _text("", 13, Color(1, 1, 1, 0.75))
	box.add_child(_summary)
	box.add_child(_text("Probá el mouse: apretá un botón sobre este panel", 15))
	_probe = _text("Todavía no apretaste ninguno.", 13, Color(0.6, 0.9, 1.0))
	box.add_child(_probe)
	var close_button := Button.new()
	close_button.text = "Cerrar (F3)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	box.add_child(close_button)
	custom_minimum_size = Vector2(620, 0)


func _text(value: String, font: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 580
	return label


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	if hands != null:
		hands.drop_hold("", true)
		_buttons.select(_buttons.get_item_index(hands.prefs.buttons))
		_mode.select(_mode.get_item_index(hands.prefs.mode))
	_show_summary()
	visible = true
	if camera != null:
		camera.hold_mouse(self)
	_center.call_deferred()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	if camera != null:
		camera.release_mouse(self)
	closed.emit()


func _center() -> void:
	reset_size()
	position = (get_viewport_rect().size - size) * 0.5


func _changed() -> void:
	if hands == null:
		return
	var fresh := InvHandPrefs.new()
	fresh.buttons = _buttons.get_selected_id() as InvHandPrefs.Buttons
	fresh.mode = _mode.get_selected_id() as InvHandPrefs.Mode
	hands.set_prefs(fresh)
	_show_summary()


func _show_summary() -> void:
	if hands == null:
		_summary.text = ""
		return
	_summary.text = "Guardado en esta PC (%s). La rueda aleja (para arriba) y acerca (para abajo) lo que sostenés; con el botón central apretado, el mouse lo gira (Shift: el tercer eje)." \
			% hands.prefs.describe()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		_probe.text = "Llegó el botón %s.%s" % [BUTTON_NAMES.get(event.button_index, str(event.button_index)),
				_meaning(event)]


## Qué hace ese botón jugando, con el esquema elegido.
func _meaning(event: InputEvent) -> String:
	if hands == null:
		return ""
	var actions := hands.prefs.actions()
	if event.is_action(actions[0]):
		return " Jugando: agarra y suelta."
	if event.is_action(actions[1]):
		return " Jugando: lanza lo que sostenés."
	if event.is_action(&"objeto_rotar"):
		return " Jugando: mantenido, gira lo que sostenés."
	if event.is_action(&"objeto_alejar"):
		return " Jugando: aleja lo que sostenés (sin objeto, la cámara)."
	if event.is_action(&"objeto_acercar"):
		return " Jugando: acerca lo que sostenés (sin objeto, la cámara)."
	return " Jugando, con este esquema, no hace nada con los objetos."


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
