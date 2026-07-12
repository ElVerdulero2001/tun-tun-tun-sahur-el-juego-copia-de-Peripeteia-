extends CanvasLayer

@export var raycast: Node3D

@onready var label = $Label
@onready var marco = $marco_enfoque

func _ready():
	marco.raycast = raycast

func _process(_delta):
	if raycast == null:
		return
	# TODO: el objeto que expone "floor_name" (botón de piso de ascensor)
	# todavía no está migrado a InteractionComponent. Hasta que lo esté,
	# este chequeo nunca lo va a encontrar y su label va a quedar vacío.
	if raycast.componente_mirado == null:
		label.text = ""
		return
	if "data" in raycast.objeto_mirado and raycast.objeto_mirado.data:
		label.text = "[E] " + raycast.objeto_mirado.data.nombre
	elif "floor_name" in raycast.objeto_mirado:
		label.text = "[E] " + raycast.objeto_mirado.floor_name
	else:
		label.text = ""
