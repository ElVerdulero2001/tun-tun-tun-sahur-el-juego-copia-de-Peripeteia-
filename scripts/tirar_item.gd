extends Node

func _input(event):
	if not is_inside_tree():
		return
	if event.is_action_pressed("tirar_item"):
		if Inventario.items.size() > 0:
			var player = get_tree().get_first_node_in_group("player")
			var camara = player.get_node("Camera3D")
			var instancia = Inventario.items[-1]
			var posicion = camara.global_position + (-camara.global_transform.basis.z * 1.5)
			var escena = Catalogo.get_prefab(instancia["data"].item_id)
			var nodo = escena.instantiate()
			get_tree().current_scene.add_child(nodo)
			nodo.global_position = posicion
			nodo.global_transform.basis = camara.global_transform.basis
			nodo.apply_impulse(-camara.global_transform.basis.z * instancia["data"].fuerza_lanzamiento + Vector3(0, 2, 0))
			nodo.angular_velocity = camara.global_transform.basis.x * instancia["data"].velocidad_angular
			Inventario.items.erase(instancia)
