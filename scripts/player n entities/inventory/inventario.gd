extends Node

const COLS = 15
const ROWS = 20

var items: Array[ItemInstancia] = []

func agregar_item(data: ItemData) -> void:
	var instancia = ItemInstancia.new(data)
	_buscar_celda_libre(instancia)
	items.append(instancia)
	print("Item agregado: ", data.nombre)
	print("Inventario actual: ", items.size(), " items")

func _buscar_celda_libre(instancia: ItemInstancia) -> void:
	var forma = Catalogo.get_forma(instancia.data.item_id)
	for fila in range(ROWS):
		for col in range(COLS):
			if _caben_todas(col, fila, forma):
				instancia.grid_col = col
				instancia.grid_fila = fila
				return

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
		if item.grid_col == -1 or item.grid_fila == -1:
			continue
		var forma = Catalogo.get_forma(item.data.item_id)
		for f in range(forma.size()):
			for c in range(forma[f].size()):
				if forma[f][c] == 0:
					continue
				if item.grid_col + c == col and item.grid_fila + f == fila:
					return false
	return true

func devolver_item(instancia: ItemInstancia, posicion: Vector3) -> void:
	var escena = Catalogo.get_prefab(instancia.data.item_id)
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
		print("- ", instancia.data.nombre, " en (", instancia.grid_col, ",", instancia.grid_fila, ")")
	print("==================")
