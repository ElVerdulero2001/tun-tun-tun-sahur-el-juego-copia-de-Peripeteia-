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
## ── DISTINCION vs LocalAuthority._inventory_receptor (NOMBRES PARECIDOS) ──
## Son cosas distintas, a distinto nivel:
##   InventoryReceiver (esta clase)     = capacidad de una ENTIDAD para recibir
##                                        un WorldItem en un InventoryV2 concreto.
##   LocalAuthority._inventory_receptor = referencia interna que usa UNA
##                                        LocalAuthority para saber sobre que
##                                        InventoryV2 ejecuta sus operaciones.
##
## ── SOBRE EL RE-SET DEL RECEPTOR (deuda C2) ──
## LocalAuthority tiene UN solo slot _inventory_receptor. En produccion cada
## entidad tiene su propia LocalAuthority (1:1) y el re-set es idempotente.
## En arneses que comparten UNA LocalAuthority entre varios InventoryV2, el
## re-set JIT de recibir_pickup() garantiza que el pickup va al inventario de
## ESTE receiver. Cuando se pueda tocar el contrato de LocalAuthority (C2+),
## solicitar_pickup() podria recibir el InventoryV2 explicito y estos set()
## desaparecen.

## InventoryV2 de ESTA entidad. Cableado por @export en la escena de la entidad.
@export var inventory: InventoryV2
## LocalAuthority de ESTA entidad. Cableado por @export en la escena de la entidad.
@export var authority: LocalAuthority


func _ready() -> void:
	assert(inventory != null, "InventoryReceiver: 'inventory' (InventoryV2 de esta entidad) sin cablear")
	assert(authority != null, "InventoryReceiver: 'authority' (LocalAuthority de esta entidad) sin cablear")
	# Cablea la LocalAuthority de ESTA entidad con SU InventoryV2, con el
	# mecanismo existente de LocalAuthority. Ver nota "RE-SET DEL RECEPTOR".
	authority.set_inventory_receptor(inventory)


## Contrato publico: el WorldItemV2 apuntado por el actor solicita pasar a
## custodia del InventoryV2 de esta entidad. Delega en SU LocalAuthority, que
## es la unica que corre TransferOperation.validate()/commit() (INV-08).
## true = quedo bajo custodia del inventario.
func recibir_pickup(world_item: WorldItemV2) -> bool:
	# Reafirma el destino de ESTA entidad justo antes de la operacion (ver
	# nota "RE-SET DEL RECEPTOR"): idempotente en produccion, necesario si la
	# LocalAuthority esta compartida.
	authority.set_inventory_receptor(inventory)
	return authority.solicitar_pickup(world_item)
