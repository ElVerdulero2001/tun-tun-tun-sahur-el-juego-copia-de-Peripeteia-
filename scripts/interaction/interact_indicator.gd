class_name InteractIndicator
extends Control

## El indicador de lo que mira el jugador local (desde el 2026-11-06): cuatro
## esquinas finas en «L» alrededor del objetivo de E, con los lados abiertos y
## un poco de margen, y su nombre centrado debajo. Nada más: ni teclas ni
## verbos. Es solo dibujo, en el HUD 2D: no toma el mouse ni el teclado.
##
## No sabe de qué tipo es el objetivo. En cada cuadro le pide a `source` el
## InteractFocus de ese momento (null si no hay nada que marcar o si la
## interfaz no deja interactuar) y proyecta las ocho esquinas de su zona con la
## cámara activa del viewport. Así el marco y el nombre acompañan al objetivo
## aunque siga siendo el mismo: si gira o se mueve la cámara, o si se mueve el
## objeto. El nombre va siempre horizontal, porque se dibuja en 2D.
##
## Mientras marca algo, oculta el cartel 3D que ya mostraba su nombre
## (InteractFocus.name_label), así el nombre se ve una sola vez, y lo vuelve a
## mostrar al dejar de marcarlo.
##
## Para usarlo con otro selector, alcanza con darle otro `source`: el HUD no se toca.

@export_group("Marco")
## Cuánto más grande que la zona proyectada es el marco, de cada lado, en píxeles.
@export_range(0.0, 40.0, 0.5) var margin := 6.0
## Largo de cada trazo de una esquina, en píxeles.
@export_range(2.0, 48.0, 0.5) var corner_length := 12.0
## Como mucho, qué parte de cada lado ocupa un trazo: así los lados quedan
## abiertos también en un marco chico.
@export_range(0.1, 0.45, 0.01) var corner_max_fraction := 0.3
@export_range(0.5, 6.0, 0.25) var line_width := 1.5
## El marco no es más chico que esto (algo lejos o diminuto), en píxeles.
@export_range(8.0, 120.0, 1.0) var min_size := 26.0
@export var color := Color(1, 1, 1, 0.95)
## Un borde oscuro alrededor de los trazos y del nombre, para que se lean sobre
## fondos claros.
@export var outline_color := Color(0, 0, 0, 0.55)

@export_group("Nombre")
@export_range(8, 40) var font_size := 15
## Separación entre las esquinas de abajo y el nombre, en píxeles.
@export_range(0.0, 40.0, 0.5) var name_gap := 4.0

## Devuelve el InteractFocus que hay que marcar ahora, o null. Lo pone quien
## monta el HUD (en el laboratorio, InvUI.interaction_focus).
var source: Callable

var _focus: InteractFocus
var _frame := Rect2()
var _shown_name := ""
## El cartel 3D que está oculto mientras se marca su objetivo (id de instancia, o 0).
var _hidden_label := 0


func _ready() -> void:
	# Toda la pantalla. Armado por código, set_anchors_preset solo dejaría el
	# rectángulo vacío que tiene: hay que mover también los bordes.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	# Después de lo que mueve la cámara y los objetos en el cuadro.
	process_priority = 1000


func _process(_delta: float) -> void:
	refresh()


func _exit_tree() -> void:
	_show_label(null)


## Vuelve a pedir el objetivo y a proyectarlo. Corre en cada cuadro.
func refresh() -> void:
	var focus: InteractFocus = source.call() if source.is_valid() else null
	var frame := Rect2()
	if focus != null and focus.is_valid():
		frame = frame_of(focus, get_viewport().get_camera_3d())
	if not frame.has_area():
		focus = null
		frame = Rect2()
	_show_label(focus)
	if focus != _focus or frame != _frame or (focus != null and focus.display_name != _shown_name):
		_focus = focus
		_frame = frame
		_shown_name = focus.display_name if focus != null else ""
		queue_redraw()


## El marco de esa zona en pantalla, con la cámara como está: el rectángulo que
## encierra sus ocho esquinas proyectadas, más el margen. Vacío si la cámara no
## está o si alguna esquina queda detrás de ella.
func frame_of(focus: InteractFocus, camera: Camera3D) -> Rect2:
	if camera == null or focus == null or not focus.is_valid():
		return Rect2()
	var to_local := get_global_transform_with_canvas().affine_inverse()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in focus.world_corners():
		if camera.is_position_behind(corner):
			return Rect2()
		var at := to_local * camera.unproject_position(corner)
		low = low.min(at)
		high = high.max(at)
	var frame := Rect2(low, high - low).grow(margin)
	var missing := (Vector2(min_size, min_size) - frame.size).max(Vector2.ZERO) / 2.0
	return frame.grow_individual(missing.x, missing.y, missing.x, missing.y)


# --- Para las pruebas ------------------------------------------------------------

## Lo que se marca ahora, o null.
func focus() -> InteractFocus:
	return _focus


## El marco que se dibuja, en píxeles de la pantalla (vacío sin objetivo).
func frame() -> Rect2:
	return _frame


## El nombre que se dibuja ("" sin objetivo).
func shown_name() -> String:
	return _shown_name


## Dónde empieza el nombre (su línea de base, a la izquierda).
func name_position() -> Vector2:
	var font := get_theme_default_font()
	var width := font.get_string_size(_shown_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := clampf(_frame.get_center().x - width / 2.0, 4.0, maxf(size.x - width - 4.0, 4.0))
	return Vector2(x, _frame.end.y + name_gap + font.get_ascent(font_size))


# --- Dibujo -------------------------------------------------------------------------

func _draw() -> void:
	if _focus == null:
		return
	var arm := minf(corner_length, minf(_frame.size.x, _frame.size.y) * corner_max_fraction)
	var corners := [
		[_frame.position, Vector2.RIGHT, Vector2.DOWN],
		[Vector2(_frame.end.x, _frame.position.y), Vector2.LEFT, Vector2.DOWN],
		[Vector2(_frame.position.x, _frame.end.y), Vector2.RIGHT, Vector2.UP],
		[_frame.end, Vector2.LEFT, Vector2.UP],
	]
	# Cada esquina: dos trazos que salen del vértice hacia adentro del marco.
	# Primero el borde oscuro, más ancho, y encima el trazo.
	for outline in [true, false]:
		for corner: Array in corners:
			var vertex: Vector2 = corner[0]
			draw_polyline(PackedVector2Array([vertex + corner[1] * arm, vertex, vertex + corner[2] * arm]),
					outline_color if outline else color, line_width + 2.0 if outline else line_width, true)
	var font := get_theme_default_font()
	var at := name_position()
	draw_string_outline(font, at, _shown_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, outline_color)
	draw_string(font, at, _shown_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Oculta el cartel 3D del objetivo que se marca y vuelve a mostrar el del
## anterior (si todavía existe).
func _show_label(focus: InteractFocus) -> void:
	var label: Node3D = focus.name_label if focus != null and is_instance_valid(focus.name_label) else null
	var id := label.get_instance_id() if label != null else 0
	if id == _hidden_label:
		return
	var previous := instance_from_id(_hidden_label) as Node3D if _hidden_label != 0 else null
	if is_instance_valid(previous):
		previous.visible = true
	_hidden_label = id
	if label != null:
		label.visible = false
