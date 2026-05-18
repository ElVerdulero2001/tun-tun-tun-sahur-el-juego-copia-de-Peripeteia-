extends CanvasLayer

@export var raycast: Node3D

@onready var label = $Label
@onready var marco = $marco_enfoque

func _ready():
	marco.raycast = raycast

func _process(_delta):
	if raycast == null:
		return
	if raycast.objeto_mirado and raycast.objeto_mirado.data:
		label.text = "[E] " + raycast.objeto_mirado.data.nombre
	else:
		label.text = ""
