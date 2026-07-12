extends RigidBody3D

## Propietario: item recogible. Reemplaza a Interactable.
## La lógica es la misma que tenía antes — la diferencia es dónde vive
## y cómo se la llama. Ya no decide nada por su cuenta más allá de
## su propio estado (recogerse o no); no hay feedback de UI acá adentro.

@export var data: ItemData

func _on_interact(interaction: Interaction) -> Variant:
	match interaction.accion:
		&"usar":
			return _recoger()
		_:
			return false

func _recoger() -> bool:
	if data == null:
		return false
	if not data.es_recogible:
		return false
	Inventario.agregar_item(data)
	queue_free.call_deferred()
	return true
