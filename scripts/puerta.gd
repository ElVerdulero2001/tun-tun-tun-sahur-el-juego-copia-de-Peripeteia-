extends AnimatableBody3D

@export var data: ItemData
@export var angulo_apertura: float = 90.0
@export var velocidad: float = 2.0
@export var requiere_llave: bool = false
@export var id_llave: int = 0

var abierta: bool = false
var moviendose: bool = false
var angulo_actual: float = 0.0
var direccion: float = 1.0

func interactuar():
	if requiere_llave:
		var tiene_llave = false
		for instancia in Inventario.items:
			if instancia["data"].item_id == id_llave:
				tiene_llave = true
				break
		if not tiene_llave:
			print("Necesitas una llave")
			return
	
	if moviendose:
		return
	
	abierta = !abierta
	direccion = 1.0 if abierta else -1.0
	angulo_actual = 0.0
	moviendose = true

func _physics_process(delta):
	if not moviendose:
		return
	var paso = velocidad * delta
	rotate(Vector3.UP, paso * direccion)
	angulo_actual += paso
	if angulo_actual >= deg_to_rad(angulo_apertura):
		moviendose = false
		angulo_actual = 0.0
