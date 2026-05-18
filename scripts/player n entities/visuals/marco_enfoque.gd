extends Control

@onready var c_tl = $E_ArribaIzquierda
@onready var c_tr = $E_ArribaDerecha
@onready var c_bl = $E_AbajoIzquierda
@onready var c_br = $E_AbajoDerecha

var raycast: Node3D = null
@export var padding: float = 15.0
@export var margen: float = 20.0

func buscar_mesh(nodo) -> MeshInstance3D:
	if nodo is MeshInstance3D:
		return nodo
	for child in nodo.get_children():
		var resultado = buscar_mesh(child)
		if resultado:
			return resultado
	return null

func _process(_delta):
	if raycast == null or raycast.objeto_mirado == null:
		visible = false
		return
	
	var objeto = raycast.objeto_mirado
	var camara = get_viewport().get_camera_3d()
	
	if camara.is_position_behind(objeto.global_position):
		visible = false
		return
	
	var mesh = buscar_mesh(objeto)
	if mesh == null:
		visible = false
		return
	
	var aabb = mesh.get_aabb()
	var min_2d = Vector2(99999, 99999)
	var max_2d = Vector2(-99999, -99999)
	
	for i in range(8):
		var punto_3d = mesh.global_transform * aabb.get_endpoint(i)
		var punto_2d = camara.unproject_position(punto_3d)
		min_2d.x = min(min_2d.x, punto_2d.x)
		min_2d.y = min(min_2d.y, punto_2d.y)
		max_2d.x = max(max_2d.x, punto_2d.x)
		max_2d.y = max(max_2d.y, punto_2d.y)
	
	visible = true
	var resolucion = get_viewport().get_visible_rect().size
	
	global_position = Vector2.ZERO
	c_tl.global_position = Vector2(clamp(min_2d.x - padding, margen, resolucion.x - margen), clamp(min_2d.y - padding, margen, resolucion.y - margen))
	c_tr.global_position = Vector2(clamp(max_2d.x + padding, margen, resolucion.x - margen), clamp(min_2d.y - padding, margen, resolucion.y - margen))
	c_bl.global_position = Vector2(clamp(min_2d.x - padding, margen, resolucion.x - margen), clamp(max_2d.y + padding, margen, resolucion.y - margen))
	c_br.global_position = Vector2(clamp(max_2d.x + padding, margen, resolucion.x - margen), clamp(max_2d.y + padding, margen, resolucion.y - margen))
