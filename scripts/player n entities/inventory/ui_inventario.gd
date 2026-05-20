extends CanvasLayer

@onready var grilla = $Control/Grilla

const COLS = 15
const ROWS = 20
const CELL_SIZE = 20

func _ready():
	visible = false
	_construir_grilla()

func _construir_grilla():
	var escala = get_viewport().get_visible_rect().size.y / 648.0
	var cell_size = int(CELL_SIZE * escala)
	grilla.columns = COLS
	grilla.position = Vector2(10, 10)
	for i in range(ROWS * COLS):
		var celda = ColorRect.new()
		celda.custom_minimum_size = Vector2(cell_size, cell_size)
		celda.color = Color(0.1, 0.1, 0.1)
		grilla.add_child(celda)

func _input(event):
	if event.is_action_pressed("toggle_inventario"):
		visible = !visible
