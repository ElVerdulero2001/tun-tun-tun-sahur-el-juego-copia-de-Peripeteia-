class_name InventoryEntry
extends RefCounted

## Relaciona un ItemInstance con su posicion y orientacion dentro de UN
## Inventory concreto (docs/inventory_system_v0_v1.md secciones 3 y 4).
##
## Las coordenadas NO forman parte del ItemInstance: solo tienen sentido
## mientras la instancia esta colocada en este inventario. Por eso viven
## aca y no en ItemInstance.
##
## DOS usos, misma clase:
##  - VIVA: la que InventoryV2 guarda en _entries (fuente de verdad). SOLO
##    la muta InventoryV2._reubicar_entry, in-place, sobre la MISMA
##    InventoryEntry (INV-09/INV-10).
##  - SNAPSHOT: copia detached que devuelven get_entries() / entry_en_celda()
##    a los consumidores. Mutar una snapshot NO afecta al modelo (no comparte
##    estado con la entry viva). item_instance SI es la misma referencia:
##    es la identidad logica compartida (D1 cubre placement; ItemInstance en
##    si sigue siendo mutable desde afuera -> ver docs seccion 17, D8).
##
## GDScript 4.6.3 no tiene privacidad real (el prefijo "_" es convencion):
## la barrera de D1 es "InventoryV2 NUNCA entrega la entry viva", no "los
## campos estan protegidos". Ver docs/inventory_system_v0_v1.md seccion 17 (D1).

var item_instance: ItemInstance
var position: Vector2i
var rotated: bool


func _init(p_item_instance: ItemInstance, p_position: Vector2i, p_rotated: bool = false) -> void:
	item_instance = p_item_instance
	position = p_position
	rotated = p_rotated


## Copia detached de esta entry: mismo ItemInstance (identidad compartida),
## position/rotated por valor. Mutarla no toca el modelo.
func snapshot() -> InventoryEntry:
	return InventoryEntry.new(item_instance, position, rotated)


## Reubicacion in-place autorizada. SOLO la debe invocar InventoryV2._reubicar_entry
## (que a su vez solo se llama desde TransferOperation._commit_reubicar).
## Conserva la MISMA InventoryEntry y el MISMO ItemInstance (INV-09).
func _reubicar(p_position: Vector2i, p_rotated: bool) -> void:
	position = p_position
	rotated = p_rotated


## Huella (width, height) de esta entrada considerando su orientacion actual.
func get_footprint() -> Vector2i:
	var def := item_instance.definition
	if rotated:
		return Vector2i(def.grid_height, def.grid_width)
	return Vector2i(def.grid_width, def.grid_height)
