class_name InventoryReceiver
extends Node

## Capacidad de dominio: "esta entidad puede recibir un WorldItemV2 en un
## InventoryV2 concreto". Es el bridge donde la identidad del actor de una
## interaccion (Interaction.actor) se traduce a un InventoryV2 concreto, sin
## que el mundo (WorldItemV2) conozca la entidad, su Body ni su autoridad.
##
## Reusable por CUALQUIER entidad con inventario (jugador, NPC, cofre,
## vehiculo...): se agrega como hijo directo de la entidad-actor y se le
## cablean por @export el InventoryV2 y la LocalAuthority de ESA entidad.
##
## RESOLUCION (WorldItemV2._resolver_receiver): dado Interaction.actor, el
## PRIMER InventoryReceiver entre sus hijos directos — analogo a como
## InteractionV2 resuelve un InteractionComponent como hijo directo del
## collider. Sin grupos globales, sin rutas rigidas entre arboles, sin
## singleton, sin coordinador en el nodo raiz de la entidad.
##
## recibir_pickup() delega en la LocalAuthority de esta entidad pasandole SU
## InventoryV2 explicito: la autoridad no guarda estado de routing.

## InventoryV2 de ESTA entidad. Cableado por @export en la escena de la entidad.
@export var inventory: InventoryV2
## LocalAuthority de ESTA entidad. Cableado por @export en la escena de la entidad.
@export var authority: LocalAuthority


func _ready() -> void:
	assert(inventory != null, "InventoryReceiver: 'inventory' (InventoryV2 de esta entidad) sin cablear")
	assert(authority != null, "InventoryReceiver: 'authority' (LocalAuthority de esta entidad) sin cablear")


## Contrato publico: el WorldItemV2 apuntado por el actor solicita pasar a
## custodia del InventoryV2 de esta entidad. Delega en SU LocalAuthority, que
## es la unica que corre TransferOperation.validate()/commit() (INV-08).
## true = quedo bajo custodia del inventario.
func recibir_pickup(world_item: WorldItemV2) -> bool:
	return authority.solicitar_pickup(world_item, inventory)
