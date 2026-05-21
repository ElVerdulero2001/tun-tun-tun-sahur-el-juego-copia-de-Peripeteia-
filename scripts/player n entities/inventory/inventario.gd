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
	var pos = _buscar_celda_libre(instancia)
	instancia["grid_col"] = pos.x
	instancia["grid_fila"] = pos.y
	items.append(instancia)
	print("Item agregado: ", data.nombre)
	print("Inventario actual: ", items.size(), " items")

func _buscar_celda_libre(instancia: Dictionary) -> Vector2i:
	var forma = Catalogo.get_forma(instancia["data"].item_id)
	for fila in range(15):
		for col in range(15):
			if _caben_todas(col, fila, forma):
				return Vector2i(col, fila)
	return Vector2i(-1, -1)

func _caben_todas(col_base: int, fila_base: int, forma: Array) -> bool:
	for f in range(forma.size()):
		for c in range(forma[f].size()):
			if forma[f][c] == 0:
				continue
			var col = col_base + c
			var fila = fila_base + f
			if col >= 15 or fila >= 20:
				return false
			if not _celda_libre(col, fila):
				return false
	return true

func _celda_libre(col: int, fila: int) -> bool:
	for item in items:
		var forma = Catalogo.get_forma(item["data"].item_id)
		var col_base = item["grid_col"]
		var fila_base = item["grid_fila"]
		for f in range(forma.size()):
			for c in range(forma[f].size()):
				if forma[f][c] == 0:
					continue
				if col_base + c == col and fila_base + f == fila:
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
	if UiInventario.visible:
		UiInventario.grilla_sucia = true

func mostrar_inventario() -> void:
	print("=== INVENTARIO ===")
	for instancia in items:
		print("- ", instancia["data"].nombre, " en (", instancia["grid_col"], ",", instancia["grid_fila"], ")")
	print("==================")
