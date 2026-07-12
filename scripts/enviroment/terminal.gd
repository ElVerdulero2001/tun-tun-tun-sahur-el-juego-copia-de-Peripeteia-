class_name Terminal
extends Node3D

## Ya no extiende Interactable (no existe más). El nodo InteractionComponent
## va como hijo de Terminal en la escena — no del StaticBody3D/CollisionShape3D
## si esos viven aparte, como pasaba con el Interactable viejo.

@export var contrasena: String = ""
@export var objetivo: NodePath
@export var nombre: String = "Terminal"

var data: Dictionary:
	get: return {"nombre": nombre}

func _on_interact(interaction: Interaction) -> Variant:
	match interaction.accion:
		&"usar":
			return _abrir_terminal()
		_:
			return false

func _abrir_terminal() -> bool:
	UIHacking.abrir(self)
	return true
