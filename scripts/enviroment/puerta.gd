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
var desbloqueada: bool = false

func _on_interact(interaction: Interaction) -> Variant:
	match interaction.accion:
		&"usar":
			return _toggle()
		_:
			return false

func _toggle() -> bool:
	if requiere_llave and not desbloqueada:
		var tiene_llave := false
		for instancia in Inventario.items:
			if instancia["data"].item_id == id_llave:
				tiene_llave = true
				break
		if not tiene_llave:
			# Antes iba un print acá ("Necesitas una llave"). Ese feedback
			# es de UI, no de esta lógica — el sistema que consuma este
			# false todavía no está diseñado.
			return false

	if moviendose:
		return false

	abierta = !abierta
	direccion = 1.0 if abierta else -1.0
	angulo_actual = 0.0
	moviendose = true
	return true

func desbloquear() -> void:
	desbloqueada = true
	_toggle()

func _physics_process(delta):
	if not moviendose:
		return
	var paso = velocidad * delta
	rotate(Vector3.UP, paso * direccion)
	angulo_actual += paso
	if angulo_actual >= deg_to_rad(angulo_apertura):
		moviendose = false
		angulo_actual = 0.0
