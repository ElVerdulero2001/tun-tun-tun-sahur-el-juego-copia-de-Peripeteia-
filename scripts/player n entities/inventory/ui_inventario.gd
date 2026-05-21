extends CanvasLayer

@onready var grilla = $Control/Grilla

const COLS = 15
const ROWS = 20
const CELL_SIZE = 20

var item_en_mano: Dictionary = {}

func _ready():
	visible = false
	_construir_grilla()

func _construir_grilla():
	var escala = get_viewport().get_visible_rect().size.y / 648.0
	var cell_size = int(CELL_SIZE * escala)
	grilla.columns = COLS
	grilla.position = Vector2(50, 40)
	for i in range(ROWS * COLS):
		var celda = ColorRect.new()
		celda.custom_minimum_size = Vector2(cell_size, cell_size)
		celda.color = Color(0.1, 0.1, 0.1)
		grilla.add_child(celda)

func _actualizar_grilla():
	for celda in grilla.get_children():
		celda.color = Color(0.1, 0.1, 0.1)
	for instancia in Inventario.items:
		var col = instancia["grid_col"]
		var fila = instancia["grid_fila"]
		if col == -1 or fila == -1:
			continue
		var indice = fila * COLS + col
		if indice < grilla.get_child_count():
			grilla.get_child(indice).color = Color(0.2, 0.6, 0.2)
	if not item_en_mano.is_empty():
		var celda = _obtener_celda_bajo_mouse()
		if celda != Vector2i(-1, -1):
			var indice = celda.y * COLS + celda.x
			if indice < grilla.get_child_count():
				grilla.get_child(indice).color = Color(0.6, 0.6, 0.2)

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
		if instancia["grid_col"] == col and instancia["grid_fila"] == fila:
			return instancia
	return null

func _process(_delta):
	if visible:
		_actualizar_grilla()

func _input(event):
	if event.is_action_pressed("toggle_inventario"):
		visible = !visible
		if visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
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
			else:
				if item_en_celda != null:
					var temp_col = item_en_celda["grid_col"]
					var temp_fila = item_en_celda["grid_fila"]
					item_en_celda["grid_col"] = celda.x
					item_en_celda["grid_fila"] = celda.y
					item_en_mano["grid_col"] = temp_col
					item_en_mano["grid_fila"] = temp_fila
					item_en_mano = {}
				else:
					item_en_mano["grid_col"] = celda.x
					item_en_mano["grid_fila"] = celda.y
					item_en_mano = {}
