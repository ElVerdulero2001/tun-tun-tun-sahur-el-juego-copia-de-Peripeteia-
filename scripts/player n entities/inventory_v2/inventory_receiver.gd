class_name InventoryReceiver
extends Node

## Capacidad de dominio: "esta entidad puede recibir un WorldItemV2 en un
## InventoryV2 concreto". Es el punto donde la identidad del actor de una
## interaccion (Interaction.actor) se traduce a un InventoryV2 concreto, sin
## que el mundo (WorldItemV2) conozca la entidad, su Body ni su autoridad.
##
## Reusable por CUALQUIER entidad con inventario (jugador, NPC, cofre,
## vehiculo...): se agrega como hijo directo de la entidad-actor y se le
## cablean por @export el InventoryV2 y la LocalAuthority de ESA entidad.
##
## RESOLUCION PREVISTA (la implementa WorldItemV2 en C1, NO en C0): dado
## Interaction.actor, buscar el PRIMER InventoryReceiver entre sus hijos
## directos — analogo a como InteractionV2 resuelve un InteractionComponent
## como hijo directo del collider. Sin grupos globales, sin rutas rigidas
## entre arboles, sin singleton, sin coordinador en el nodo raiz de la entidad.
##
## ── DISTINCION vs LocalAuthority._inventory_receptor (NOMBRES PARECIDOS) ──
## Son cosas distintas, a distinto nivel:
##   InventoryReceiver (esta clase)     = capacidad de una ENTIDAD para recibir
##                                        un WorldItem en un InventoryV2 concreto.
##   LocalAuthority._inventory_receptor = referencia interna que usa UNA
##                                        LocalAuthority para saber sobre que
##                                        InventoryV2 ejecuta sus operaciones.
## Esta clase NO toca ese campo en C0.
##
## ── ALCANCE C0 (estructural, sin gameplay) ──
## En C0 este componente SOLO conoce y valida sus dos dependencias. NO
## configura la LocalAuthority (no llama set_inventory_receptor), NO participa
## en ningun flujo de pickup. El metodo publico recibir_pickup() existe como
## contrato pero su cableado funcional end-to-end es C1: hasta entonces falla
## de forma controlada (devuelve false + push_warning). Ninguna pieza depende
## todavia de el (WorldItemV2 no lo invoca en C0).

## InventoryV2 de ESTA entidad. Cableado por @export en la escena de la entidad.
@export var inventory: InventoryV2
## LocalAuthority de ESTA entidad. Cableado por @export en la escena de la entidad.
@export var authority: LocalAuthority


func _ready() -> void:
	assert(inventory != null, "InventoryReceiver: 'inventory' (InventoryV2 de esta entidad) sin cablear")
	assert(authority != null, "InventoryReceiver: 'authority' (LocalAuthority de esta entidad) sin cablear")


## Contrato publico: solicitar que `world_item` pase a custodia del InventoryV2
## de esta entidad. true = quedo bajo custodia.
##
## C0: NO implementado end-to-end a proposito. El routing real (delegar en
## LocalAuthority.solicitar_pickup detras del contrato request->validate->commit)
## es trabajo de C1. Hasta entonces devuelve false SIN efectos secundarios;
## se prefiere un fallo visible y controlado a comportamiento oculto adelantado.
func recibir_pickup(world_item: WorldItemV2) -> bool:
	push_warning("InventoryReceiver.recibir_pickup(): sin routing hasta C1 — devuelve false (world_item=%s)" % world_item)
	return false
