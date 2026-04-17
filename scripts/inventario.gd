extends Node

var items: Array = []

func agregar_item(data: ItemData) -> void:
	items.append(data)
	print("Item agregado: ", data.nombre)
	print("Inventario actual: ", items.size(), " items")

func devolver_item(data: ItemData, posicion: Vector3) -> void:
	var escena = Catalogo.get_prefab(data.tipo)
	if escena == null:
		print("Error: no existe prefab para el tipo '", data.tipo, "' en el catalogo")
		return
	var instancia = escena.instantiate()
	instancia.global_position = posicion
	get_tree().current_scene.add_child(instancia)
	items.erase(data)
	print("Item devuelto: ", data.nombre)

func mostrar_inventario() -> void:
	print("=== INVENTARIO ===")
	for item in items:
		print("- ", item.nombre)
	print("==================")
