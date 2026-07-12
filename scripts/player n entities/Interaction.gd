class_name Interaction
extends RefCounted

## Forma mínima de una interacción: actor, acción, resultado.
## Contrato cerrado para esta etapa. Si en el futuro "accion" necesita
## dejar de ser un StringName (modding, herramientas, etc.), se reabre
## este archivo puntualmente — no implica tocar InteractionComponent
## ni a ningún propietario.

var actor: Node
var accion: StringName
var resultado: Variant = null

func _init(p_actor: Node, p_accion: StringName) -> void:
	actor = p_actor
	accion = p_accion
