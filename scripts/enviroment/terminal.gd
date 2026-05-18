class_name Terminal
extends Interactable

@export var contrasena: String = ""
@export var objetivo: NodePath

func interactuar():
	UIHacking.abrir(self)
