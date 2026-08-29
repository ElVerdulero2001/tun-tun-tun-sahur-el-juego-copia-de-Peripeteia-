extends CanvasLayer

@onready var grilla = $Control/Grilla
@onready var tooltip = $Control/Tooltip

const COLS = 15
const ROWS = 20
const CELL_SIZE = 20

var item_en_mano: ItemInstancia = null
var grilla_sucia: bool = true
var celda_highlight: Vector2i = Vector2i(-1, -1)
var offset_mano: Vector2i = Vector2i(0, 0)
var col_original: int = -1
var fila_original: int = -1

func _ready():
	visible = false
	_construir_grilla()

	# TEMPORAL — migración PlayerV2 / InventoryV2 (SUA-1.4 C4-B0).
	# UiInventario legacy permanece como Autoload porque Player V1 todavía tiene
	# referencias (player.gd, tirar_item.gd, inventario.gd leen UiInventario.visible),
	# pero su procesamiento de input queda HIBERNADO mientras PlayerInventoryUI
	# reemplaza su función. Con esto el Autoload sigue instanciándose, sigue
	# accesible como UiInventario y `visible` sigue en false — solo deja de capturar
	# toggle_inventario / mouse motion / rotar_item / clicks de inventario.
	# El nodo se elimina definitivamente cuando se retiren sus consumidores V1.
	# NO borrar _input() ni funcionalidad: es hibernación, no eliminación.
	set_process_input(false)

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

func _rotar_forma(forma: Array) -> Array:
	var filas = forma.size()
	var cols = forma[0].size()
	var nueva_forma = []
	for c in range(cols):
		var fila = []
		for f in range(filas - 1, -1, -1):
			fila.append(forma[f][c])
		nueva_forma.append(fila)
	return nueva_forma

func _obtener_forma_actual(instancia: ItemInstancia) -> Array:
	if instancia.forma_rotada.size() > 0:
		return instancia.forma_rotada
	return Catalogo.get_forma(instancia.data.item_id)

func _actualizar_grilla():
	for celda in grilla.get_children():
		celda.color = Color(0.1, 0.1, 0.1)
	for instancia in Inventario.items:
		if instancia.grid_col == -1 or instancia.grid_fila == -1:
			continue
		var forma = _obtener_forma_actual(instancia)
		for f in range(forma.size()):
			for c in range(forma[f].size()):
				if forma[f][c] == 0:
					continue
				var indice = (instancia.grid_fila + f) * COLS + (instancia.grid_col + c)
				if indice < grilla.get_child_count():
					grilla.get_child(indice).color = instancia.color
	if item_en_mano != null:
		var celda = celda_highlight
		if celda != Vector2i(-1, -1):
			var col_base = celda.x - offset_mano.x
			var fila_base = celda.y - offset_mano.y
			var forma = _obtener_forma_actual(item_en_mano)
			for f in range(forma.size()):
				for c in range(forma[f].size()):
					if forma[f][c] == 0:
						continue
					var col = col_base + c
					var fila = fila_base + f
					if col < 0 or col >= COLS or fila < 0 or fila >= ROWS:
						continue
					var indice = fila * COLS + col
					if indice < grilla.get_child_count():
						grilla.get_child(indice).color = Color(0.6, 0.6, 0.2)

func _actualizar_highlight():
	var celda_anterior = celda_highlight
	celda_highlight = _obtener_celda_bajo_mouse()
	if celda_anterior == celda_highlight:
		return
	grilla_sucia = true

func _actualizar_tooltip():
	if celda_highlight == Vector2i(-1, -1):
		tooltip.visible = false
		return
	var item = _obtener_item_en_celda(celda_highlight.x, celda_highlight.y)
	if item == null:
		tooltip.visible = false
		return
	tooltip.visible = true
	tooltip.text = item.data.nombre
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

func _obtener_item_en_celda(col: int, fila: int) -> ItemInstancia:
	for instancia in Inventario.items:
		if instancia.grid_col == -1 or instancia.grid_fila == -1:
			continue
		var forma = _obtener_forma_actual(instancia)
		for f in range(forma.size()):
			for c in range(forma[f].size()):
				if forma[f][c] == 0:
					continue
				if instancia.grid_col + c == col and instancia.grid_fila + f == fila:
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

	if visible and event.is_action_pressed("rotar_item"):
		if item_en_mano != null:
			var forma_actual = _obtener_forma_actual(item_en_mano)
			item_en_mano.forma_rotada = _rotar_forma(forma_actual)
			item_en_mano.grid_rotacion = (item_en_mano.grid_rotacion + 90) % 360
			var nueva_forma = item_en_mano.forma_rotada
			var nuevo_offset_x = min(offset_mano.y, nueva_forma[0].size() - 1)
			var nuevo_offset_y = min(offset_mano.x, nueva_forma.size() - 1)
			offset_mano = Vector2i(nuevo_offset_x, nuevo_offset_y)
			grilla_sucia = true

	if event.is_action_pressed("toggle_inventario"):
		visible = !visible
		if visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			grilla_sucia = true
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			tooltip.visible = false
			if item_en_mano != null:
				item_en_mano.grid_col = col_original
				item_en_mano.grid_fila = fila_original
				item_en_mano = null
				grilla_sucia = true

	if visible and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var celda = _obtener_celda_bajo_mouse()
			if celda == Vector2i(-1, -1):
				if item_en_mano != null:
					var mouse_pos = get_viewport().get_mouse_position()
					var rect_seguro = grilla.get_global_rect().grow(50)
					if not rect_seguro.has_point(mouse_pos):
						var player = get_tree().get_first_node_in_group("player")
						var tirar_item = player.get_node("TirarItem")
						tirar_item.lanzar_desde_inventario(item_en_mano)
						item_en_mano = null
						grilla_sucia = true
				return
			var item_en_celda = _obtener_item_en_celda(celda.x, celda.y)
			if item_en_mano == null:
				if item_en_celda != null:
					col_original = item_en_celda.grid_col
					fila_original = item_en_celda.grid_fila
					offset_mano = Vector2i(celda.x - item_en_celda.grid_col, celda.y - item_en_celda.grid_fila)
					item_en_mano = item_en_celda
					item_en_celda.grid_col = -1
					item_en_celda.grid_fila = -1
					grilla_sucia = true
			else:
				if item_en_celda != null:
					var temp_col = item_en_celda.grid_col
					var temp_fila = item_en_celda.grid_fila
					item_en_mano.grid_col = temp_col
					item_en_mano.grid_fila = temp_fila
					item_en_celda.grid_col = -1
					item_en_celda.grid_fila = -1
					item_en_mano = item_en_celda
					col_original = temp_col
					fila_original = temp_fila
					offset_mano = Vector2i(celda.x - temp_col, celda.y - temp_fila)
					grilla_sucia = true
				else:
					var col_destino = celda.x - offset_mano.x
					var fila_destino = celda.y - offset_mano.y
					var forma = _obtener_forma_actual(item_en_mano)
					if col_destino < 0 or fila_destino < 0:
						return
					if col_destino + forma[0].size() > COLS or fila_destino + forma.size() > ROWS:
						return
					if not Inventario._caben_todas(col_destino, fila_destino, forma):
						return
					item_en_mano.grid_col = col_destino
					item_en_mano.grid_fila = fila_destino
					item_en_mano = null
					grilla_sucia = true
