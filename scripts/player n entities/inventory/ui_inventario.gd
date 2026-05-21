extends CanvasLayer

@onready var grilla = $Control/Grilla
@onready var tooltip = $Control/Tooltip

const COLS = 15
const ROWS = 20
const CELL_SIZE = 20

var item_en_mano: Dictionary = {}
var grilla_sucia: bool = true
var celda_highlight: Vector2i = Vector2i(-1, -1)

func _ready():
	visible = false
	_construir_grilla()

func _construir_grilla():
	var escala = get_viewport().get_visible_rect().size.y / 648.0
	var cell_size = int(CELL_SIZE * escala)
	grilla.columns = COLS
	grilla.position = Vector2(50, 40)
	grilla.add_theme_constant_override("h_separation", 0)
	grilla.add_theme_constant_override("v_separation", 0)
	for i in range(ROWS * COLS):
		var celda = ColorRect.new()
		celda.custom_minimum_size = Vector2(cell_size, cell_size)
		celda.color = Color(0.1, 0.1, 0.1)
		grilla.add_child(celda)

func _actualizar_grilla():
	for celda in grilla.get_children():
		celda.color = Color(0.1, 0.1, 0.1)
	for instancia in Inventario.items:
		var col_base = instancia["grid_col"]
		var fila_base = instancia["grid_fila"]
		if col_base == -1 or fila_base == -1:
			continue
		var forma = Catalogo.get_forma(instancia["data"].item_id)
		for f in range(forma.size()):
			for c in range(forma[f].size()):
				if forma[f][c] == 0:
					continue
				var indice = (fila_base + f) * COLS + (col_base + c)
				if indice < grilla.get_child_count():
					grilla.get_child(indice).color = Color(0.2, 0.6, 0.2)

func _actualizar_highlight():
	var celda_anterior = celda_highlight
	celda_highlight = _obtener_celda_bajo_mouse()
	if celda_anterior == celda_highlight:
		return
	if celda_anterior != Vector2i(-1, -1):
		var indice_anterior = celda_anterior.y * COLS + celda_anterior.x
		var item_anterior = _obtener_item_en_celda(celda_anterior.x, celda_anterior.y)
		if item_anterior != null:
			grilla.get_child(indice_anterior).color = Color(0.2, 0.6, 0.2)
		else:
			grilla.get_child(indice_anterior).color = Color(0.1, 0.1, 0.1)
	if celda_highlight != Vector2i(-1, -1):
		var indice = celda_highlight.y * COLS + celda_highlight.x
		if not item_en_mano.is_empty():
			grilla.get_child(indice).color = Color(0.6, 0.6, 0.2)
		else:
			grilla.get_child(indice).color = Color(0.4, 0.4, 0.4)

func _actualizar_tooltip():
	if celda_highlight == Vector2i(-1, -1):
		tooltip.visible = false
		return
	var item = _obtener_item_en_celda(celda_highlight.x, celda_highlight.y)
	if item == null:
		tooltip.visible = false
		return
	tooltip.visible = true
	tooltip.text = item["data"].nombre
	tooltip.position = get_viewport().get_mouse_position() + Vector2(10, 10)

func _obtener_celda_bajo_mouse() -> Vector2i:
	var mouse_pos = get_viewport().get_mouse_position()
	for i in range(grilla.get_child_count()):
		var celda = grilla.get_child(i)
		if celda.get_global_rect().has_point(mouse_pos):
			var col = i % COLS
			var fila = int(i / float(COLS))
			return Vector2i(col, fila)
	return Vector2i(-1, -1)

func _obtener_item_en_celda(col: int, fila: int):
	for instancia in Inventario.items:
		var col_base = instancia["grid_col"]
		var fila_base = instancia["grid_fila"]
		if col_base == -1 or fila_base == -1:
			continue
		var forma = Catalogo.get_forma(instancia["data"].item_id)
		for f in range(forma.size()):
			for c in range(forma[f].size()):
				if forma[f][c] == 0:
					continue
				if col_base + c == col and fila_base + f == fila:
					return instancia
	return null

func _process(_delta):
	if visible and grilla_sucia:
		_actualizar_grilla()
		grilla_sucia = false

func _input(event):
	if visible and event is InputEventMouseMotion:
		_actualizar_highlight()
		_actualizar_tooltip()

	if event.is_action_pressed("toggle_inventario"):
		visible = !visible
		if visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			grilla_sucia = true
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			tooltip.visible = false
			if not item_en_mano.is_empty():
				item_en_mano["grid_col"] = 0
				item_en_mano["grid_fila"] = 0
				item_en_mano = {}

	if visible and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var celda = _obtener_celda_bajo_mouse()
			if celda == Vector2i(-1, -1):
				return
			var item_en_celda = _obtener_item_en_celda(celda.x, celda.y)
			if item_en_mano.is_empty():
				if item_en_celda != null:
					item_en_mano = item_en_celda
					item_en_celda["grid_col"] = -1
					item_en_celda["grid_fila"] = -1
					grilla_sucia = true
			else:
				if item_en_celda != null:
					var temp_col = item_en_celda["grid_col"]
					var temp_fila = item_en_celda["grid_fila"]
					item_en_celda["grid_col"] = celda.x
					item_en_celda["grid_fila"] = celda.y
					item_en_mano["grid_col"] = temp_col
					item_en_mano["grid_fila"] = temp_fila
					item_en_mano = {}
					grilla_sucia = true
				else:
					item_en_mano["grid_col"] = celda.x
					item_en_mano["grid_fila"] = celda.y
					item_en_mano = {}
					grilla_sucia = true
