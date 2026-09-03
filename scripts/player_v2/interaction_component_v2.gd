class_name InteractionComponentV2
extends Node

## Marcador de interactuable V2. Se agrega como hijo DIRECTO del nodo que
## participa de una interacción con PlayerV2 — InteractionV2 lo busca
## únicamente ahí, sin walk por ancestros (ver interaction.gd). No conoce
## gameplay: recibe la interacción, se la entrega al propietario, devuelve
## lo que el propietario produjo.
##
## Contrato con el propietario: debe implementar
## _on_interact(interaction: Interaction) -> Variant
## Verificado con assert en debug/editor (misma limitación aceptada que
## InteractionComponent: no corre en builds de exportación release).
##
## DELIBERADAMENTE independiente de InteractionComponent (V1) — NO extiende
## esa clase y no debe hacerlo nunca. Godot resuelve `is` por cadena de
## herencia: si esta clase heredara de InteractionComponent, cualquier
## `is InteractionComponent` del lado V1 (p. ej. raycast_interaccion.gd)
## empezaría a reconocer objetos V2 sin que nadie lo haya pedido. PlayerV1 y
## PlayerV2 deben permanecer contractualmente separados mientras dure la
## migración — "hacen casi lo mismo" no es motivo para unificarlos. Compartir
## el DTO Interaction como mensaje no implica compartir este marcador: el
## mensaje no participa de ningún `is`, este componente sí.

var _propietario: Node

func _ready() -> void:
	_propietario = get_parent()
	assert(
		_propietario.has_method(&"_on_interact"),
		"El propietario de InteractionComponentV2 debe implementar _on_interact(interaction: Interaction) -> Variant"
	)

func recibir_interaccion(interaction: Interaction) -> Variant:
	interaction.resultado = _propietario._on_interact(interaction)
	return interaction.resultado
