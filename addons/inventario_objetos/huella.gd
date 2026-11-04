@tool
extends Control

## Dibujo de una grilla para la vista previa del panel Objetos. Para un ítem:
## su huella con la miniatura, sin girar y girada 90°, como se ve en el
## inventario (el mismo dibujo de InvThumbnails.draw_turned); sin miniatura, un
## rectángulo de su color con el nombre, como en el juego. Para un contenedor:
## sus columnas y filas.

## Celdas de la huella de un ítem, o columnas y filas de un contenedor.
var cells := Vector2i.ONE
var can_rotate := false
var texture: Texture2D
var color := Color.GRAY
var item_name := ""
## Si es la grilla de un contenedor (sin miniatura ni giro).
var container := false

const GAP := 16.0
const CAPTION := 18.0
## El ancho con que se calcula el alto si todavía no tiene ancho (pestaña
## oculta): así no se estira sin control.
const FALLBACK_WIDTH := 220.0


func show_item(p_cells: Vector2i, p_rotates: bool, p_texture: Texture2D, p_color: Color, p_name: String) -> void:
	container = false
	cells = p_cells
	can_rotate = p_rotates
	texture = p_texture
	color = p_color
	item_name = p_name
	update_minimum_size()
	queue_redraw()


func show_grid(columns: int, rows: int) -> void:
	container = true
	cells = Vector2i(columns, rows)
	can_rotate = false
	texture = null
	update_minimum_size()
	queue_redraw()


func _notification(what: int) -> void:
	# El alto sale del ancho: cambia con él.
	if what == NOTIFICATION_RESIZED:
		update_minimum_size()


func _get_minimum_size() -> Vector2:
	return Vector2(120.0, _cell(_width()) * _tall_cells() + CAPTION + 4.0)


func _width() -> float:
	return size.x if size.x > 40.0 else FALLBACK_WIDTH


## Lado de una celda: lo que entra a lo ancho, entre 6 y 28 píxeles.
func _cell(width: float) -> float:
	var across := float(cells.x + (cells.y if can_rotate else 0))
	var room := width - (GAP if can_rotate else 0.0)
	return clampf(floorf(room / maxf(across, 1.0)), 3.0 if container else 6.0, 16.0 if container else 28.0)


func _tall_cells() -> int:
	return maxi(cells.y, cells.x if can_rotate else 0)


func _draw() -> void:
	var cell := _cell(_width())
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var line := get_theme_color(&"font_color", &"Label")
	if container:
		_draw_grid(Vector2(0, CAPTION), cells, cell)
		draw_string(font, Vector2(0, CAPTION - 5), "%d × %d = %d celdas" % [cells.x, cells.y, cells.x * cells.y],
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, line)
		return
	var flat := Vector2(0, CAPTION)
	_draw_item(Rect2(flat, Vector2(cells) * cell), 0, cell)
	draw_string(font, Vector2(0, CAPTION - 5), "%d × %d" % [cells.x, cells.y], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, line)
	if can_rotate:
		var turned := Vector2(cells.x * cell + GAP, CAPTION)
		_draw_item(Rect2(turned, Vector2(cells.y, cells.x) * cell), 1, cell)
		draw_string(font, Vector2(turned.x, CAPTION - 5), "girado 90°: %d × %d" % [cells.y, cells.x],
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, line)


func _draw_item(rect: Rect2, rot: int, cell: float) -> void:
	_draw_grid(rect.position, Vector2i(rect.size / cell), cell)
	var inner := rect.grow(-2.0)
	draw_rect(inner, Color(color.darkened(0.55), 0.85))
	draw_rect(inner, Color(color.lightened(0.2), 0.7), false, 1.0)
	if texture != null:
		InvThumbnails.draw_turned(self, texture, inner, rot, Color.WHITE)
	else:
		draw_string(get_theme_default_font(), inner.position + Vector2(4, minf(inner.size.y / 2.0 + 5.0, inner.size.y - 4.0)),
				item_name, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x - 8.0, get_theme_default_font_size() - 3)


func _draw_grid(origin: Vector2, count: Vector2i, cell: float) -> void:
	var dim := Color(1, 1, 1, 0.08)
	var edge := Color(1, 1, 1, 0.22)
	for x in count.x:
		for y in count.y:
			var rect := Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell)
			draw_rect(rect.grow(-1.0), dim)
			draw_rect(rect, edge, false, 1.0)
