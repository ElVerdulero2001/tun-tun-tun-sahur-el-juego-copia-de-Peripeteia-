extends Node

## TEST-ONLY. Cuenta cuantas veces una accion llega SIN consumir a
## _unhandled_input. Sirve para verificar que otro nodo consumio (o no) un
## evento antes (p. ej. PlayerInventoryUI._shortcut_input marcando handled).

var ui_cancel_count := 0
var toggle_inventario_count := 0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		ui_cancel_count += 1
	if event.is_action_pressed("toggle_inventario"):
		toggle_inventario_count += 1
