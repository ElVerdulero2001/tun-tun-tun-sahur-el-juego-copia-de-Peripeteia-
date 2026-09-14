extends Node3D

## SANDBOX / DEBUG ONLY — NO ES PRODUCCION (SUA-1.6 C).
##
## Escena de integracion para validar un SEGUNDO ASSET REAL (sable_san_martin_1.tscn
## ya migrado a WorldItemV2 + ItemDefinition) contra la arquitectura InventoryV2,
## con un PlayerV2 real. Mismo patron que botella_integration (opcion C de H.1:
## no se toca movement_test ni Player V1).
##
## NO inyecta ItemInstance: el sable se autoaprovisiona desde su `definition` en
## WorldItemV2._ready(). El unico rol de este script es un readout de debug; la
## lectura directa de InventoryV2.get_entries() esta permitida porque esto es un
## arnes, no la UI real.

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
		"[SUA-1.6 C - integracion sable real (debug only)]",
		"InteractionV2 target : %s" % (String(target.name) if target != null else "(ninguno)"),
		"Inventory entries    : %d" % _inventory.get_entries().size(),
		"Contenido            : %s" % (", ".join(ids) if ids.size() > 0 else "-"),
		"",
		"E = recoger / soltar   TAB = inventario   R = rotar (item agarrado)",
	]))
