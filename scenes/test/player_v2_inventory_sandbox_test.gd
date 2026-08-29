extends Node

## ARNES DE TEST — NO ES PRODUCCION. PlayerV2 · FASE C3 (integracion estructural).
##
## Instancia el sandbox real (player_v2_inventory_sandbox.tscn) y verifica que
## las piezas para el pickup end-to-end quedaron CONECTADAS. NO simula raycast
## ni input — esa parte se prueba a mano (ver el reporte de C3). Aca solo:
##   - cada WorldItemV2 del sandbox tiene un InteractionComponent como hijo directo;
##   - cada WorldItemV2 recibio un ItemInstance valido (definition = el .tres esperado);
##   - PlayerV2 expone un InventoryReceiver hijo directo del nodo raiz;
##   - ese InventoryReceiver apunta al Inventory y al InventoryAuthority de ESE PlayerV2;
##   - el InventoryV2 del Player arranca vacio.

const SANDBOX := preload("res://scenes/player_v2/player_v2_inventory_sandbox.tscn")

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== PLAYERV2 · FASE C3 · integracion estructural del sandbox =====")

	var sb := SANDBOX.instantiate()
	add_child(sb)
	await get_tree().process_frame   # deja correr _ready() del coordinador (asigna ItemInstances)

	var pv2: Node = sb.get_node("PlayerV2")
	var inventory: InventoryV2 = pv2.get_node("Inventory")
	var authority: LocalAuthority = pv2.get_node("InventoryAuthority")
	var receiver: InventoryReceiver = pv2.get_node("InventoryReceiver")
	var items := sb.get_node("Items").get_children()

	# ── PlayerV2: costura de recepcion ───────────────────────────────
	print("-- PlayerV2 expone la capacidad de recibir items --")
	_check(receiver != null and receiver is InventoryReceiver, "PlayerV2 tiene un InventoryReceiver")
	_check(receiver.get_parent() == pv2, "InventoryReceiver es hijo DIRECTO del nodo raiz PlayerV2 (== Interaction.actor)")
	_check(receiver.inventory == inventory, "receiver.inventory == Inventory de ESTE PlayerV2")
	_check(receiver.authority == authority, "receiver.authority == InventoryAuthority de ESTE PlayerV2")
	_check(inventory.get_entries().is_empty(), "el InventoryV2 del Player arranca vacio")

	# ── WorldItemV2 del sandbox ──────────────────────────────────────
	print("-- cada WorldItemV2 del sandbox esta listo para el pickup --")
	_check(items.size() >= 1, "hay al menos un WorldItemV2 en Items/")
	for it in items:
		var wi := it as WorldItemV2
		_check(wi != null, "%s es un WorldItemV2" % it.name)
		if wi == null:
			continue
		var comp := _hijo_interaction_component(wi)
		_check(comp != null, "%s: InteractionComponent como hijo DIRECTO" % wi.name)
		_check(wi.item_instance != null, "%s: tiene un ItemInstance" % wi.name)
		_check(wi.item_instance != null and wi.item_instance.definition != null, "%s: su ItemInstance tiene ItemDefinition" % wi.name)

	# ── el actor de la interaccion resuelve el receiver correcto ─────
	print("-- WorldItemV2._resolver_receiver(actor) --")
	if items.size() > 0 and items[0] is WorldItemV2:
		_check((items[0] as WorldItemV2)._resolver_receiver(pv2) == receiver, "_resolver_receiver(PlayerV2) -> el InventoryReceiver del Player")

	print("===================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: FASE C3 (integracion estructural) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos estructurales de C3")
	get_tree().quit(_fallos)


func _hijo_interaction_component(nodo: Node) -> InteractionComponent:
	for h in nodo.get_children():
		if h is InteractionComponent:
			return h
	return null


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
