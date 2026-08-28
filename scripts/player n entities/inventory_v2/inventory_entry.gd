class_name InventoryEntry
extends RefCounted

## Relaciona un ItemInstance con su posicion y orientacion dentro de UN
## Inventory concreto (docs/inventory_system_v0_v1.md secciones 3 y 4).
##
## Las coordenadas NO forman parte del ItemInstance: solo tienen sentido
## mientras la instancia esta colocada en este inventario. Por eso viven
## aca y no en ItemInstance.

var item_instance: ItemInstance
var position: Vector2i
var rotated: bool

func _init(p_item_instance: ItemInstance, p_position: Vector2i, p_rotated: bool = false) -> void:
	item_instance = p_item_instance
	position = p_position
	rotated = p_rotated

## Huella (width, height) de esta entrada considerando su orientacion actual.
func get_footprint() -> Vector2i:
	var def := item_instance.definition
	if rotated:
		return Vector2i(def.grid_height, def.grid_width)
	return Vector2i(def.grid_width, def.grid_height)
