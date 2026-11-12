@tool
extends Control

signal drag_started
signal rotated(axis: Vector3, degrees: float)
signal drag_finished

const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const COLORS := [Color(1.0, 0.4, 0.43), Color(0.47, 0.9, 0.42), Color(0.39, 0.68, 1.0)]
const LABELS := ["X", "Y", "Z"]
const WIDTH := 116.0
const HEIGHT := 98.0
const RADIUS := 30.0
const CENTER := Vector2(WIDTH * 0.5, 35.0)
const SEGMENTS := 36
const PICK_RADIUS := 6.0

# Una vista oblicua deja ver los tres anillos cuando el modelo está de frente.
var _view := Basis.from_euler(Vector3(-0.45, 0.55, 0.0))

var _rings: Array[PackedVector2Array] = []
var _axis := -1
var _hover := -1
var _tangent := Vector2.ZERO
var _degrees := 0.0
var _applied := 0.0


func _init() -> void:
	size = Vector2(WIDTH, HEIGHT)
	tooltip_text = "Arrastrá X, Y o Z hacia los lados para girar sobre ese eje. También podés arrastrar su anillo. Shift para ajuste fino. Ctrl para pasos de 15°."
	mouse_exited.connect(func() -> void:
		_hover = -1
		queue_redraw())


func orient(model_basis: Basis) -> void:
	_rings.clear()
	var view_basis := _view * model_basis
	for axis in AXES.size():
		var points := PackedVector2Array()
		var u: Vector3 = view_basis * AXES[(axis + 1) % 3]
		var v: Vector3 = view_basis * AXES[(axis + 2) % 3]
		for i in SEGMENTS + 1:
			var angle := TAU * i / SEGMENTS
			var point := u * cos(angle) + v * sin(angle)
			points.append(CENTER + Vector2(point.x, -point.y) * RADIUS)
		_rings.append(points)
	queue_redraw()


func cancel_drag() -> void:
	_axis = -1
	_hover = -1
	queue_redraw()


func _axis_handle(axis: int) -> Rect2:
	return Rect2(6.0 + axis * 36.0, 70.0, 32.0, 24.0)


func _pick(point: Vector2) -> int:
	for axis in _rings.size():
		if _axis_handle(axis).has_point(point):
			_tangent = Vector2.RIGHT
			return axis
	var closest := PICK_RADIUS * PICK_RADIUS
	var picked := -1
	for axis in _rings.size():
		var ring := _rings[axis]
		for i in SEGMENTS:
			var start := ring[i]
			var end := ring[i + 1]
			var hit := Geometry2D.get_closest_point_to_segment(point, start, end)
			var distance := point.distance_squared_to(hit)
			if distance < closest:
				closest = distance
				picked = axis
				_tangent = (end - start).normalized()
	return picked


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_axis = _pick(button.position)
			_degrees = 0.0
			_applied = 0.0
			if _axis >= 0:
				drag_started.emit()
		elif _axis >= 0:
			cancel_drag()
			drag_finished.emit()
		queue_redraw()
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _axis < 0:
		_hover = _pick(motion.position)
		mouse_default_cursor_shape = CURSOR_ARROW if _hover < 0 else (CURSOR_HSIZE
				if _axis_handle(_hover).has_point(motion.position) else CURSOR_POINTING_HAND)
		queue_redraw()
		return
	_degrees += motion.relative.dot(_tangent) * (0.1 if motion.shift_pressed else 0.5)
	var angle := snappedf(_degrees, 15.0) if motion.ctrl_pressed else _degrees
	if not is_equal_approx(angle, _applied):
		_applied = angle
		rotated.emit(AXES[_axis], angle)
	accept_event()


func _draw() -> void:
	for axis in _rings.size():
		var active := axis == _axis or (_axis < 0 and axis == _hover)
		var color: Color = COLORS[axis]
		draw_polyline(_rings[axis], color, 3.0 if active else 1.5, true)
		var handle := _axis_handle(axis)
		draw_rect(handle, Color(color, 0.26 if active else 0.10))
		draw_rect(handle, Color(color, 0.95 if active else 0.55), false)
		var font := get_theme_default_font()
		var font_size := get_theme_default_font_size()
		var baseline := handle.get_center().y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		draw_string(font, Vector2(handle.position.x, baseline), LABELS[axis],
				HORIZONTAL_ALIGNMENT_CENTER, handle.size.x, font_size, color)
