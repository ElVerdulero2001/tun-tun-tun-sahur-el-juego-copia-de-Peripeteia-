class_name InteractionComponent
extends Node

## Se agrega como hijo de cualquier objeto que participe de una interacción.
## No conoce gameplay. Recibe la interacción, se la entrega al propietario,
## devuelve lo que el propietario produjo.
##
## Contrato con el propietario: debe implementar
## _on_interact(interaction: Interaction) -> Variant
## Verificado con assert en debug/editor. Limitación conocida y aceptada:
## el assert no existe en builds de exportación release. Suficiente
## mientras el desarrollo sea solo mío; se reevalúa si aparece
## necesidad real (equipo, modding, herramientas).

signal interaction_received(interaction: Interaction)

var _propietario: Node

func _ready() -> void:
	_propietario = get_parent()
	print("InteractionComponent en: ", _propietario.get_path())
	assert(
		_propietario.has_method(&"_on_interact"),
		"El propietario de InteractionComponent debe implementar _on_interact(interaction: Interaction) -> Variant"
	)

func recibir_interaccion(interaction: Interaction) -> Variant:
	interaction.resultado = _propietario._on_interact(interaction)
	interaction_received.emit(interaction)
	return interaction.resultado
