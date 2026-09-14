extends Node3D

## SANDBOX / DEBUG ONLY — NO ES PRODUCCION (SUA-1.3 C3).
##
## Arnes de integracion end-to-end: InteractionV2 (raycast + input REALES) +
## WorldItemV2 -> InventoryReceiver -> LocalAuthority -> InventoryV2 de ESTE
## PlayerV2. NO llama a mano _on_interact() / recibir_pickup() /
## solicitar_pickup(): el pickup ocurre solo por mirar el item y pulsar la
## accion "interactuar".
##
## Responsabilidades de arnes (nada de esto es produccion):
##  - dar un ItemInstance valido a cada WorldItemV2 del sandbox en _ready();
##  - mostrar en pantalla el target actual de InteractionV2 y el contenido del
##    InventoryV2 del Player. La lectura directa de InventoryV2._entries via
##    get_entries() esta permitida porque esto es un arnes, no la UI real
##    (InventoryPanel se integra en una fase posterior, no aca).

@export var item_definition_test: ItemDefinition

@onready var _items_root: Node3D = $Items
@onready var _interaction: Node = $PlayerV2/Body/Interaction
@onready var _inventory: InventoryV2 = $PlayerV2/Inventory
@onready var _label: Label = $DebugReadout/Label


func _ready() -> void:
	assert(item_definition_test != null, "player_v2_inventory_sandbox: falta item_definition_test (arrastrar el .tres)")
	for hijo in _items_root.get_children():
		if hijo is WorldItemV2:
			(hijo as WorldItemV2).item_instance = ItemInstance.new(item_definition_test)


func _process(_delta: float) -> void:
	var target := _interaction.get("current_target_owner") as Node

	var ids := PackedStringArray()
	for e in _inventory.get_entries():
		ids.append("#%d" % e.item_instance.instance_id)

	_label.text = "\n".join(PackedStringArray([
		"[SANDBOX C3 - debug only]",
		"InteractionV2 target : %s" % (String(target.name) if target != null else "(ninguno)"),
		"Inventory entries    : %d" % _inventory.get_entries().size(),
		"ItemInstances        : %s" % (", ".join(ids) if ids.size() > 0 else "-"),
	]))
