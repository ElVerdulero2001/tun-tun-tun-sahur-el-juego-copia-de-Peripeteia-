class_name ItemDropper
extends Node

## ItemDropper — capacidad de PlayerV2: "un ItemInstance sale de MI InventoryV2
## y reaparece en el mundo, en una posicion relativa a MI" (SUA-1.5 C5-A).
##
## Simetrico a InventoryReceiver:
##   InventoryReceiver = mundo -> inventario (pickup)
##   ItemDropper       = inventario -> mundo (drop)
##
## Es dueño SOLO de la semantica ESPACIAL del drop (donde, y bajo que parent,
## reaparece el item). La transferencia atomica + la custodia las ejecuta
## LocalAuthority / TransferOperation, sin cambios. WorldItemV2 nace NEUTRAL
## (C2) -> el item soltado puede recogerse despues por cualquier actor.
##
## NO conoce: la UI (InventoryPanel / InventoryManipulator), quien dispara el
## drop, ni como se selecciono el item. Alguien le pasa un ItemInstance y el
## resto es LocalAuthority. En C5-A NADIE lo invoca todavia — el disparador
## (arrastrar fuera de la grilla) es C5-B / C5-C.
##
## Cableado: @export con node_paths en player_v2.tscn (mismo patron que
## InventoryReceiver e Interaction). Sin grupos, sin autoloads, sin busqueda de
## player. El unico lookup de runtime es get_tree().current_scene (ver soltar()).

## InventoryV2 de ESTA entidad.
@export var inventory: InventoryV2
## LocalAuthority de ESTA entidad.
@export var authority: LocalAuthority
## Punto de aparicion: un Marker3D bajo Body. Sigue posicion + yaw del Body,
## SIN el pitch de la Camera3D (la camara se reserva para un futuro throw/aim).
@export var spawn_source: Node3D


func _ready() -> void:
	assert(inventory != null, "ItemDropper: 'inventory' (InventoryV2 de esta entidad) sin cablear")
	assert(authority != null, "ItemDropper: 'authority' (LocalAuthority de esta entidad) sin cablear")
	assert(spawn_source != null, "ItemDropper: 'spawn_source' (Marker3D bajo Body) sin cablear")


## Saca `item_instance` de MI inventario y lo hace reaparecer en el mundo, en
## spawn_source.global_position, como hijo de la escena activa.
## Devuelve EXACTAMENTE el WorldItemV2 producido por LocalAuthority, o null si
## algo impidio la operacion. En cualquier caso de null el inventario NO se
## modifica (o no se llama a la autoridad, o su validate() rechaza y no commitea).
func soltar(item_instance: ItemInstance) -> WorldItemV2:
	# 1. referencias propias
	if item_instance == null:
		return null
	if inventory == null or authority == null or spawn_source == null:
		push_warning("ItemDropper.soltar(): dependencias sin cablear; no se suelta nada")
		return null

	# 2-3. mundo destino: la escena activa, validada como Node3D
	var world_parent := get_tree().current_scene as Node3D
	if world_parent == null:
		push_warning("ItemDropper.soltar(): get_tree().current_scene no es un Node3D valido; no se suelta nada")
		return null

	# 4-5. delega en la autoridad de esta entidad (inventario explicito por operacion)
	return authority.solicitar_devolucion(
		item_instance,
		inventory,
		world_parent,
		spawn_source.global_position
	)
