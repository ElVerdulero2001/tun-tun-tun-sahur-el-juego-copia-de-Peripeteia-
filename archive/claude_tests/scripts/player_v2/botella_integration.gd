extends Node3D

## SANDBOX / DEBUG ONLY — NO ES PRODUCCION (SUA-1.6 B).
##
## Escena de integracion para validar un ASSET REAL (botella_standar_1.tscn ya
## migrada a WorldItemV2 + ItemDefinition) contra la arquitectura InventoryV2,
## con un PlayerV2 real. Opcion C de H.1: no se toca movement_test ni Player V1.
##
## NO inyecta ItemInstance: la botella se autoaprovisiona desde su `definition`
## en WorldItemV2._ready() (SUA-1.6 B). El unico rol de este script es un readout
## de debug; la lectura directa de InventoryV2.get_entries() esta permitida porque
## esto es un arnes, no la UI real.

@onready var _interaction: Node = $PlayerV2/Body/Interaction
@onready var _inventory: InventoryV2 = $PlayerV2/Inventory
@onready var _label: Label = $DebugReadout/Label


func _process(_delta: float) -> void:
	var target := _interaction.get("current_target_owner") as Node

	var ids := PackedStringArray()
	for e in _inventory.get_entries():
		var nombre := e.item_instance.definition.nombre if e.item_instance.definition else "???"
		ids.append("#%d %s" % [e.item_instance.instance_id, nombre])

	_label.text = "\n".join(PackedStringArray([
		"[SUA-1.6 B - integracion botella real (debug only)]",
		"InteractionV2 target : %s" % (String(target.name) if target != null else "(ninguno)"),
		"Inventory entries    : %d" % _inventory.get_entries().size(),
		"Contenido            : %s" % (", ".join(ids) if ids.size() > 0 else "-"),
		"",
		"E = recoger / soltar   TAB = inventario",
	]))
