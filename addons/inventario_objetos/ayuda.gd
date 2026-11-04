@tool
extends Button

## La burbujita de ayuda del panel Objetos: un signo de pregunta en un círculo,
## al lado del nombre de un campo o de una sección. Un clic abre un globo con la
## explicación; otro clic, uno afuera o Escape lo cierran. Sin explicación, no
## se ve.

const DIAMETER := 16.0
const WIDTH := 300.0
const MARGIN := 6.0
## El clic que cierra el globo (afuera de él, sobre la burbujita) no lo vuelve a abrir.
const REOPEN_GUARD_MS := 200

## La explicación. Si cambia con el globo abierto, cambia ahí también.
var explanation := "":
	set(value):
		explanation = value
		visible = value != ""
		_text.text = value
		if _popup.visible:
			var rect := _rect()
			_popup.position = rect.position
			_popup.size = rect.size

var _popup: PopupPanel
var _margins: MarginContainer
var _text: Label
var _closed_at := -REOPEN_GUARD_MS


func _init(p_explanation := "") -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_HELP
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2.ONE * DIAMETER * _scale()
	_popup = PopupPanel.new()
	_popup.popup_hide.connect(func() -> void:
		_closed_at = Time.get_ticks_msec()
		queue_redraw())
	add_child(_popup)
	_margins = MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		_margins.add_theme_constant_override("margin_" + side, int(MARGIN * _scale()))
	_popup.add_child(_margins)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_margins.add_child(_text)
	pressed.connect(_on_pressed)
	explanation = p_explanation


func _on_pressed() -> void:
	if Time.get_ticks_msec() - _closed_at < REOPEN_GUARD_MS:
		return
	open()


## Abre el globo abajo de la burbujita (arriba, si abajo no entra), adentro de
## la pantalla.
func open() -> void:
	_popup.popup(_rect())
	queue_redraw()


func is_open() -> bool:
	return _popup.visible


## Dónde va el globo y qué tamaño tiene, con el texto partido en renglones.
func _rect() -> Rect2i:
	var area := _area()
	var frame := _popup.get_contents_minimum_size() - _text.get_combined_minimum_size()
	var width := minf(WIDTH * _scale(), area.size.x - frame.x - 8.0)
	# El alto de un texto partido depende de su ancho: se mide con ese ancho puesto.
	_text.custom_minimum_size = Vector2(width, 0)
	_text.size = Vector2(width, 0)
	_text.custom_minimum_size.y = _text.get_minimum_size().y
	var popup_size := Vector2(width, _text.custom_minimum_size.y) + frame
	var top := get_screen_position()
	var at := top + Vector2(0, size.y + 2.0)
	if at.y + popup_size.y > area.end.y:
		at.y = top.y - popup_size.y - 2.0
	at.x = clampf(at.x, area.position.x, maxf(area.end.x - popup_size.x, area.position.x))
	at.y = maxf(at.y, area.position.y)
	return Rect2i(Vector2i(at), Vector2i(popup_size.ceil()))


## Dónde puede ir el globo: la pantalla, o la ventana si los globos van adentro
## de ella (el editor en una sola ventana).
func _area() -> Rect2:
	var window := get_window()
	if window.is_embedding_subwindows() or not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		return Rect2(Vector2.ZERO, window.size)
	return Rect2(DisplayServer.screen_get_usable_rect(window.current_screen))


func _draw() -> void:
	var color := get_theme_color(&"font_color", &"Label")
	color.a = 1.0 if is_hovered() or _popup.visible else 0.55
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - 1.0
	draw_arc(center, radius, 0.0, TAU, 32, color, maxf(1.2 * _scale(), 1.0), true)
	var font := get_theme_font(&"font", &"Label")
	var font_size := maxi(int(radius * 1.5), 6)
	var mark := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(font, Vector2(center.x - mark.x / 2.0, baseline), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Pone la burbujita de una sección (FoldableContainer) pegada a su título, y
## no en la punta derecha, donde la deja el contenedor. Se llama cada vez que
## el contenedor acomoda lo suyo.
static func beside_title(fold: FoldableContainer, bubble: Control) -> void:
	var style := fold.get_theme_stylebox(&"title_collapsed_panel" if fold.folded else &"title_panel")
	var icon := fold.get_theme_icon(&"folded_arrow" if fold.folded else &"expanded_arrow")
	var gap := maxi(fold.get_theme_constant(&"h_separation"), 0) + 4.0 * _scale()
	var font := fold.get_theme_font(&"font")
	var title_width := font.get_string_size(fold.title, HORIZONTAL_ALIGNMENT_LEFT, -1, fold.get_theme_font_size(&"font_size")).x
	var left := style.get_margin(SIDE_LEFT) + (icon.get_width() if icon != null else 0) + maxi(fold.get_theme_constant(&"h_separation"), 0)
	# Si el título no entra entero, queda donde la puso el contenedor.
	bubble.position.x = minf(left + title_width + gap, bubble.position.x)


static func _scale() -> float:
	return EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
