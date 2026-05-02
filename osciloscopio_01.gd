extends RigidBody3D

func _ready():
	await get_tree().process_frame
