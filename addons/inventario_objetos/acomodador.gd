@tool
extends Control

## La miniatura de la grilla o de la barra rápida, grande, para acomodarla con el
## mouse: arrastrar la gira, arrastrar con el botón derecho la corre y la rueda
## la acerca o la aleja. Es la misma imagen que hace el juego
## (InvThumbnails.build_viewport y frame), del mismo tamaño en píxeles, sobre
## el fondo de una celda y con las líneas de su huella encima.
##
## Escribe en el borrador (giro, zoom y corrimiento de la miniatura). Mientras
## arrastrás se redibuja solo acá; al soltar avisa con `changed`, y recién ahí
## se rehace el resto de la vista previa.

signal changed

const Guardado := preload("guardado.gd")
const GizmoRotacion := preload("gizmo_rotacion.gd")
## Grados por píxel al arrastrar; con Ctrl apretado, gira de a SNAP grados.
const DEGREES_PER_PIXEL := 0.5
const SNAP := 15.0
## El alto más grande con que se muestra, en píxeles.
const MAX_HEIGHT := 260.0
## El ancho con que se calcula el alto si todavía no tiene ancho (pestaña
## oculta): así no se estira sin control.
const FALLBACK_WIDTH := 220.0

var _hotbar: bool
var _rotation_field := &"thumbnail_rotation"
var _zoom_field := &"thumbnail_zoom"
var _offset_field := &"thumbnail_offset"
var _gizmo: GizmoRotacion
var _gizmo_origin := Basis.IDENTITY
var _def: Resource
var _viewport: SubViewport
## Con qué se armó el modelo: si cambia, se rearma; si no, solo se reencuadra.
var _built_from := ""
var _dragging := 0
var _moved := false
var _pending_turn := Vector2.ZERO
var _headless := false
var _per_cell := 96
var _max_pixels := 384
var _padding := 1.12


func _init(hotbar := false) -> void:
	_hotbar = hotbar
	if _hotbar:
		_rotation_field = &"hotbar_thumbnail_rotation"
		_zoom_field = &"hotbar_thumbnail_zoom"
		_offset_field = &"hotbar_thumbnail_offset"
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Arrastrá para girarlo (con Ctrl, de a 15°). Con Shift + arrastre izquierdo o con el botón derecho, correlo. La rueda lo acerca o lo aleja. Para girar por eje, usá los anillos de abajo."
	_gizmo = GizmoRotacion.new()
	_gizmo.hide()
	_gizmo.drag_started.connect(func() -> void: _gizmo_origin = _preview_basis())
	_gizmo.rotated.connect(_rotate_local)
	_gizmo.drag_finished.connect(func() -> void: changed.emit())
	add_child(_gizmo)


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	var script: Script = InvThumbnails
	_per_cell = int(script.get_property_default_value(&"pixels_per_cell"))
	_max_pixels = int(script.get_property_default_value(&"max_pixels"))
	_padding = float(script.get_property_default_value(&"padding"))


## Muestra la miniatura de ese ítem (el borrador). Si cambió de qué está hecho
## (modelo, malla, huella, color), la rearma; si no, solo la reencuadra.
func show_item(def: Resource) -> void:
	if _def != def:
		_gizmo.cancel_drag()
	_def = def
	var source := "%s|%s|%s|%s|%s" % [Guardado.value_text(def.get(&"model")), Guardado.value_text(def.get(&"mesh")),
			def.get(&"size"), def.get(&"color"), _custom_hotbar()] if def != null else ""
	if source != _built_from or _viewport == null:
		_built_from = source
		_rebuild()
	else:
		_reframe()
	_gizmo.visible = has_image() and (not _hotbar or _custom_hotbar())
	if _gizmo.visible:
		_position_gizmo()
		_gizmo.orient(_preview_basis())
	else:
		_gizmo.cancel_drag()
	update_minimum_size()
	queue_redraw()


## Si hay una imagen para acomodar (con modelo o malla, y con pantalla).
func has_image() -> bool:
	return _viewport != null


func _custom_hotbar() -> bool:
	return _hotbar and _def != null and bool(_def.get(&"custom_hotbar_thumbnail"))


func _rebuild() -> void:
	if _viewport != null:
		_viewport.queue_free()
		_viewport = null
	if _def == null or _headless or not InvVisuals.has_visual(_def):
		return
	var custom := _custom_hotbar()
	_viewport = InvThumbnails.build_viewport(_def, InvThumbnails.image_size(_def, _per_cell, _max_pixels, custom), _padding, custom)
	add_child(_viewport)


func _reframe() -> void:
	if _viewport != null:
		InvThumbnails.frame(_viewport, _def, _padding, _custom_hotbar())
		if _gizmo.visible:
			_gizmo.orient(_preview_basis())
		queue_redraw()


# --- Lo que hacen los botones y el mouse -------------------------------------------------

## Lo gira esos grados alrededor de un eje de la pantalla: x (de izquierda a
## derecha), y (para arriba) o z (hacia vos).
func turn(axis: Vector3, degrees: float) -> void:
	_make_manual()
	var basis := Basis(axis, deg_to_rad(degrees)) * _basis()
	_set_basis(basis)
	_reframe()


## Orientación visible, incluido el giro automático de la miniatura de la grilla.
func _preview_basis() -> Basis:
	var turn := _viewport.get_node("Giro") as Node3D
	return turn.basis * (turn.get_child(0) as Node3D).basis


func _rotate_local(axis: Vector3, degrees: float) -> void:
	if not _hotbar:
		_def.set(&"thumbnail_auto_align", false)
	_set_basis(_gizmo_origin * Basis(axis, deg_to_rad(degrees)))
	_reframe()


## De frente: sin giro.
func face_front() -> void:
	if not _hotbar:
		_def.set(&"thumbnail_auto_align", false)
	_def.set(_rotation_field, Vector3.ZERO)
	_reframe()


## En el medio y sin zoom.
func center() -> void:
	_def.set(_offset_field, Vector2.ZERO)
	_def.set(_zoom_field, 1.0)
	_reframe()


## Como sale solo: en diagonal y acostado si su lado largo no coincide con el
## de la huella (los valores de fábrica de InvItemDef).
func automatic() -> void:
	var script: Script = InvItemDef
	for field in [_rotation_field, _zoom_field, _offset_field]:
		_def.set(field, script.get_property_default_value(field))
	if not _hotbar:
		_def.set(&"thumbnail_auto_align", script.get_property_default_value(&"thumbnail_auto_align"))
	_reframe()


func zoom_by(factor: float) -> void:
	_def.set(_zoom_field, clampf(snappedf(float(_def.get(_zoom_field)) * factor, 0.01), 0.3, 3.0))
	_reframe()


## Lo corre esa parte del cuadro (0,5 es medio cuadro), sin sacarlo del todo.
func shift_by(amount: Vector2) -> void:
	var shift: Vector2 = _def.get(_offset_field) + amount
	_def.set(_offset_field, Vector2(clampf(snappedf(shift.x, 0.001), -1.0, 1.0), clampf(snappedf(shift.y, 0.001), -1.0, 1.0)))
	_reframe()


func _gui_input(event: InputEvent) -> void:
	if _viewport == null or (_hotbar and not _custom_hotbar()):
		return
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if button.pressed and _dragging == 0:
				_dragging = button.button_index
				_moved = false
				_pending_turn = Vector2.ZERO
			elif not button.pressed and button.button_index == _dragging:
				_dragging = 0
				if _moved:
					changed.emit()
			accept_event()
		elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(1.1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1)
			changed.emit()
			accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion == null or _dragging == 0:
		return
	_moved = true
	if _dragging == MOUSE_BUTTON_LEFT and not motion.shift_pressed:
		_drag_turn(motion.relative * DEGREES_PER_PIXEL, motion.ctrl_pressed)
	else:
		var area := _frame_rect()
		shift_by(motion.relative / area.size)
	accept_event()


## Arrastrar de costado lo gira alrededor del eje vertical; para arriba o para
## abajo, alrededor del horizontal. Con Ctrl, junta el arrastre y gira de a SNAP.
func _drag_turn(degrees: Vector2, snap: bool) -> void:
	_pending_turn += degrees
	var step := _pending_turn
	if snap:
		step = Vector2(snappedf(_pending_turn.x, SNAP) if absf(_pending_turn.x) >= SNAP else 0.0,
				snappedf(_pending_turn.y, SNAP) if absf(_pending_turn.y) >= SNAP else 0.0)
	_pending_turn -= step
	if step == Vector2.ZERO:
		return
	_make_manual()
	_set_basis(Basis(Vector3.UP, deg_to_rad(step.x)) * Basis(Vector3.RIGHT, deg_to_rad(step.y)) * _basis())
	_reframe()


## Al acomodarlo a mano deja de acostarse solo. Si estaba acostado, ese giro
## pasa a ser parte del suyo: la imagen no salta.
func _make_manual() -> void:
	if _hotbar or not _def.get(&"thumbnail_auto_align"):
		return
	if _viewport == null:
		_def.set(&"thumbnail_auto_align", false)
		return
	var turned := _viewport.get_node("Giro") as Node3D
	var basis := _basis()
	if not is_zero_approx(turned.rotation.z):
		basis = Basis(Vector3.BACK, turned.rotation.z) * basis
	_def.set(&"thumbnail_auto_align", false)
	_set_basis(basis)


## El giro de la miniatura como Basis (en el mismo orden que Node3D: YXZ).
func _basis() -> Basis:
	var degrees: Vector3 = _def.get(_rotation_field)
	return Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)))


func _set_basis(basis: Basis) -> void:
	var euler := basis.orthonormalized().get_euler()
	var degrees := Vector3(rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)).snapped(Vector3.ONE * 0.1)
	# Sin −0.
	_def.set(_rotation_field, degrees + Vector3.ZERO)


# --- Dibujo ----------------------------------------------------------------------------

func _notification(what: int) -> void:
	# El alto sale del ancho: cambia con él.
	if what == NOTIFICATION_RESIZED:
		if _gizmo != null and _gizmo.visible:
			_position_gizmo()
		update_minimum_size()


func _get_minimum_size() -> Vector2:
	var height := _frame_rect().size.y if _def != null else 0.0
	if _gizmo != null and _gizmo.visible:
		height += GizmoRotacion.HEIGHT + 4.0
	return Vector2(120.0, height)


func _position_gizmo() -> void:
	var frame := _frame_rect()
	_gizmo.position = Vector2(frame.get_center().x - GizmoRotacion.WIDTH * 0.5, frame.end.y + 4.0)


## Dónde va la imagen: con la proporción de la huella, a lo ancho y centrada,
## sin pasar de MAX_HEIGHT de alto.
func _frame_rect() -> Rect2:
	var width := size.x if size.x > 40.0 else FALLBACK_WIDTH
	var cells: Vector2i = _def.get(&"size") if _def != null and not _hotbar else Vector2i.ONE
	var aspect := float(maxi(cells.x, 1)) / maxi(cells.y, 1)
	var drawn := Vector2(width, width / aspect)
	if drawn.y > MAX_HEIGHT:
		drawn = Vector2(MAX_HEIGHT * aspect, MAX_HEIGHT)
	return Rect2(Vector2((width - drawn.x) / 2.0, 0.0), drawn)


func _draw() -> void:
	if _def == null:
		return
	var area := _frame_rect()
	var tint: Color = _def.get(&"color")
	# El fondo y el borde de una celda ocupada, como en el inventario.
	draw_rect(area, Color(tint.darkened(0.55), 0.85))
	draw_rect(area, Color(tint.lightened(0.2), 0.7), false, 1.0)
	var cells: Vector2i = Vector2i.ONE if _hotbar else _def.get(&"size")
	var edge := Color(1, 1, 1, 0.18)
	for x in range(1, cells.x):
		var at := area.position.x + area.size.x * x / cells.x
		draw_line(Vector2(at, area.position.y), Vector2(at, area.end.y), edge)
	for y in range(1, cells.y):
		var at := area.position.y + area.size.y * y / cells.y
		draw_line(Vector2(area.position.x, at), Vector2(area.end.x, at), edge)
	if _viewport != null:
		var image_rect := InvThumbnails.fit_rect(area, Vector2(_viewport.size)) if _hotbar else area
		draw_texture_rect(_viewport.get_texture(), image_rect, false)
	else:
		var text := "Sin pantalla no se dibuja." if _headless else "Sin modelo ni malla se ve un rectángulo con el nombre."
		draw_string(get_theme_default_font(), area.position + Vector2(6, area.size.y / 2.0), text, HORIZONTAL_ALIGNMENT_CENTER,
				area.size.x - 12.0, get_theme_default_font_size() - 3)
