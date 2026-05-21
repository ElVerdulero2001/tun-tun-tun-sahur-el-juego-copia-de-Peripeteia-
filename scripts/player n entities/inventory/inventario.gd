extends Node

var items: Array = []

func agregar_item(data: ItemData) -> void:
	var instancia = {
		"data": data,
		"municion_actual": data.municion,
		"durabilidad_actual": data.vida,
		"grid_col": -1,
		"grid_fila": -1,
		"grid_rotacion": 0,
		"equipado": false,
		"bloqueado": false,
		"cantidad": 1,
	}
	instancia["grid_col"] = _buscar_celda_libre(instancia)
	items.append(instancia)
	print("Item agregado: ", data.nombre)
	print("Inventario actual: ", items.size(), " items")

func _buscar_celda_libre(instancia: Dictionary) -> int:
	for i in range(15 * 20):
		var col = i % 15
		var fila = int(i / 15.0)
		if _celda_libre(col, fila):
			instancia["grid_fila"] = fila
			return col
	return -1

func _celda_libre(col: int, fila: int) -> bool:
	for item in items:
		if item["grid_col"] == col and item["grid_fila"] == fila:
			return false
	return true

func devolver_item(instancia: Dictionary, posicion: Vector3) -> void:
	var escena = Catalogo.get_prefab(instancia["data"].item_id)
	if escena == null:
		return
	var nodo = escena.instantiate()
	nodo.global_position = posicion
	get_tree().current_scene.add_child(nodo)
	items.erase(instancia)

func mostrar_inventario() -> void:
	print("=== INVENTARIO ===")
	for instancia in items:
		print("- ", instancia["data"].nombre, " en (", instancia["grid_col"], ",", instancia["grid_fila"], ")")
	print("==================")
