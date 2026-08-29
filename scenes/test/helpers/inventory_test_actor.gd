extends Node

## TEST-ONLY (Inventory · SUA-1.3 C1). NO ES PRODUCCION.
##
## Actor minimo para ejercitar el flujo de pickup REAL de C1 en arneses que
## prueban el MODELO de inventario, sin instanciar un PlayerV2 entero.
##
## Reproduce la unica forma que WorldItemV2._resolver_receiver() reconoce: un
## nodo con un InventoryReceiver como HIJO DIRECTO, exactamente como PlayerV2
## expone esa capacidad (scenes/player_v2/player_v2.tscn).
##
## Reemplaza el par pre-C1 de los arneses:
##     authority.set_inventory_receptor(inv)   # routing implicito por autoridad
##     wi.setup(authority)                     # pre-binding en el WorldItem
## Ninguno de los dos representa ya el contrato de gameplay: el pickup se
## resuelve desde Interaction.actor -> InventoryReceiver, no desde un receptor
## global ni una _authority inyectada en el WorldItem.
##
## Produccion sigue siendo InventoryReceiver colgado de la entidad real.

## Crea (SIN agregarlo al arbol) un actor con un InventoryReceiver hijo directo
## cableado a `inventory` / `authority`. El llamador hace add_child(actor): ahi
## corre InventoryReceiver._ready(), que valida el cableado y fija el receptor
## inicial de la autoridad.
static func crear(inventory: InventoryV2, authority: LocalAuthority) -> Node:
	var actor := Node.new()
	actor.name = "InventoryTestActor"
	var receiver := InventoryReceiver.new()
	receiver.name = "InventoryReceiver"
	receiver.inventory = inventory
	receiver.authority = authority
	actor.add_child(receiver)
	return actor
