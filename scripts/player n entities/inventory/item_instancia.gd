class_name ItemInstancia
extends RefCounted

var data: ItemData
var municion_actual: int = 0
var durabilidad_actual: float = 0.0
var grid_col: int = -1
var grid_fila: int = -1
var grid_rotacion: int = 0
var equipado: bool = false
var bloqueado: bool = false
var cantidad: int = 1
var color: Color = Color.WHITE
var forma_rotada: Array = []

func _init(item_data: ItemData):
	data = item_data
	municion_actual = item_data.municion
	durabilidad_actual = item_data.vida
	color = Color(randf(), randf(), randf())
