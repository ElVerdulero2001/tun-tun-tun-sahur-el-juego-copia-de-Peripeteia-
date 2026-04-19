extends Node

var items: Array = []

func agregar_item(data: ItemData) -> void:
	var instancia = {
		"data": data,
		"municion_actual": data.municion,
		"durabilidad_actual": data.vida,
	}
	items.append(instancia)
	print("Item agregado: ", data.nombre)
	print("Inventario actual: ", items.size(), " items")

func devolver_item(instancia: Dictionary, posicion: Vector3) -> void:
	var escena = Catalogo.get_prefab(instancia["data"].item_id)
	if escena == null:
		return
	var nodo = escena.instantiate()
	nodo.global_position = posicion
	get_tree().current_scene.add_child(nodo)
	items.erase(instancia)
	print("Item devuelto: ", instancia["data"].nombre)

func mostrar_inventario() -> void:
	print("=== INVENTARIO ===")
	for instancia in items:
		print("- ", instancia["data"].nombre)
	print("==================")
