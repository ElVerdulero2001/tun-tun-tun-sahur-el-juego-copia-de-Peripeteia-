extends Node

func _input(event):
	if not is_inside_tree():
		return
	if event.is_action_pressed("tirar_item"):
		if Inventario.items.size() > 0:
			var player = get_tree().get_first_node_in_group("player")
			if player == null or not player.is_inside_tree():
				return
			var camara = player.get_node("Camera3D")
			if camara == null or not camara.is_inside_tree():
				return
			var instancia = Inventario.items[-1]
			var posicion = camara.global_position + (-camara.global_transform.basis.z * 1.5)
			var escena = Catalogo.get_prefab(instancia["data"].item_id)
			if escena == null:
				return
			var nodo = escena.instantiate()
			get_tree().current_scene.add_child(nodo)
			nodo.global_position = posicion
			var impulso = -camara.global_transform.basis.z * 5.0 + Vector3(0, 2, 0)
			nodo.apply_impulse(impulso)
			Inventario.items.erase(instancia)
			print("Item tirado: ", instancia["data"].nombre)
		else:
			print("Inventario vacio")
