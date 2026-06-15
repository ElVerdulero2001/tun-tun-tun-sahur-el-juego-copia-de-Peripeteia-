extends CanvasLayer

@export var raycast: Node3D

@onready var label = $Label
@onready var marco = $marco_enfoque

func _ready():
	marco.raycast = raycast

func _process(_delta):
	if raycast == null:
		return
	if raycast.objeto_mirado:
		if raycast.objeto_mirado.data:
			label.text = "[E] " + raycast.objeto_mirado.data.nombre
		elif raycast.objeto_mirado.has_method("interactuar") and "floor_name" in raycast.objeto_mirado:
			label.text = "[E] " + raycast.objeto_mirado.floor_name
		else:
			label.text = ""
	else:
		label.text = ""
