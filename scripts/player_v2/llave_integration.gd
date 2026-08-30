extends Node3D

## SANDBOX / DEBUG ONLY — NO ES PRODUCCION (SUA-1.6 D).
##
## Escena de integracion para validar un TERCER ASSET REAL (llave_comun_1.tscn ya
## migrado a WorldItemV2 + ItemDefinition) contra la arquitectura InventoryV2,
## con un PlayerV2 real. Mismo patron que botella/sable_integration.
##
## La llave es un item INDEPENDIENTE: no tiene consumidor. El sistema funcional de
## puerta es monitor/terminal (fuera de este arnes). NO se prueba "la llave abre
## la puerta" porque esa feature no existe funcionalmente.
##
## NO inyecta ItemInstance: la llave se autoaprovisiona desde su `definition`.

@onready var _interaction: Node = $PlayerV2/Body/Interaction
@onready var _inventory: InventoryV2 = $PlayerV2/Inventory
@onready var _label: Label = $DebugReadout/Label


func _process(_delta: float) -> void:
	var target := _interaction.get("current_target_owner") as Node

	var ids := PackedStringArray()
	for e in _inventory.get_entries():
		var nombre := e.item_instance.definition.nombre if e.item_instance.definition else "???"
		var fp := e.get_footprint()
		ids.append("#%d %s (%dx%d%s)" % [
			e.item_instance.instance_id, nombre, fp.x, fp.y,
			" rotado" if e.rotated else "",
		])

	_label.text = "\n".join(PackedStringArray([
		"[SUA-1.6 D - integracion llave real (debug only)]",
		"InteractionV2 target : %s" % (String(target.name) if target != null else "(ninguno)"),
		"Inventory entries    : %d" % _inventory.get_entries().size(),
		"Contenido            : %s" % (", ".join(ids) if ids.size() > 0 else "-"),
		"",
		"E = recoger / soltar   TAB = inventario   (llave 1x1, can_rotate=false)",
	]))
