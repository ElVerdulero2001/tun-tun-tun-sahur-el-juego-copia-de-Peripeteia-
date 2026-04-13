extends Node3D

@export var data: ItemData

func interactuar():
	if data == null:
		return
	if data.es_recogible:
		queue_free.call_deferred()
	else:
		print("Este objeto no se puede recoger")
