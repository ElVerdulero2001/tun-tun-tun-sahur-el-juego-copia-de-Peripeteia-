extends Node

var carga: float = 0.0
var cargando: bool = false
var velocidad_carga: float = 1.5
var instancia_seleccionada = null

func _process(delta):
	if not is_inside_tree():
		return
	if cargando:
		if Inventario.items.size() > 0:
			carga = min(carga + velocidad_carga * delta, 1.0)
		else:
			carga = 0.0
			cargando = false

func _input(event):
	if not is_inside_tree():
		return
	
	if event.is_action("tirar_item"):
		if event.is_pressed() and not event.is_echo():
			if Inventario.items.size() > 0:
				cargando = true
				carga = 0.0
				instancia_seleccionada = Inventario.items[-1]
		
		if not event.is_pressed():
			if cargando and instancia_seleccionada != null and Inventario.items.has(instancia_seleccionada):
				var player = get_tree().get_first_node_in_group("player")
				var camara = player.get_node("Camera3D")
				var posicion = camara.global_position + (-camara.global_transform.basis.z * 1.5)
				var escena = Catalogo.get_prefab(instancia_seleccionada["data"].item_id)
				var nodo = escena.instantiate()
				get_tree().current_scene.add_child(nodo)
				nodo.global_position = posicion
				nodo.global_transform.basis = camara.global_transform.basis
				var fuerza = instancia_seleccionada["data"].fuerza_lanzamiento * carga
				nodo.apply_impulse(-camara.global_transform.basis.z * fuerza + Vector3(0, 2, 0))
				nodo.angular_velocity = camara.global_transform.basis.x * instancia_seleccionada["data"].velocidad_angular
				Inventario.items.erase(instancia_seleccionada)
			carga = 0.0
			cargando = false
			instancia_seleccionada = null
