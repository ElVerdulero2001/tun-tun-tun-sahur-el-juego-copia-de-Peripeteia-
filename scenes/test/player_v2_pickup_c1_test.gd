extends Node3D

## ARNES DE TEST — NO ES PRODUCCION. PlayerV2 · FASE C1.
##
## End-to-end del routing REAL de pickup:
##   Interaction(actor = PlayerV2_A, &"usar")
##   -> WorldItemV2._on_interact
##   -> resolver InventoryReceiver entre los HIJOS DIRECTOS del actor
##   -> InventoryReceiver_A.recibir_pickup(world_item)
##   -> LocalAuthority_A -> InventoryV2_A -> TransferOperation (MUNDO_A_INVENTARIO)
##
## PROHIBIDO en el camino demostrado: llamar a mano
##   authority.set_inventory_receptor(...) / authority.solicitar_pickup(...)
## desde el test — eso seria saltarse justo lo que C1 debe probar.
##
## Headless / llamadas directas a _on_interact. SIN input real: dos PlayerV2
## comparten el InputMap y el input ownership no es parte de C1.

const PLAYER_V2 := preload("res://scenes/player_v2/player_v2.tscn")

@export var item_definition_test: ItemDefinition   # 2x1, world_scene = test_item_v0

var _fallos := 0
var _checks := 0
var _emis_a := 0
var _emis_b := 0


func _ready() -> void:
	print("\n===== PLAYERV2 · FASE C1 · routing de pickup (actor -> su inventario) =====")

	var pa := PLAYER_V2.instantiate()
	var pb := PLAYER_V2.instantiate()
	add_child(pa)
	add_child(pb)

	var inv_a: InventoryV2 = pa.get_node("Inventory")
	var inv_b: InventoryV2 = pb.get_node("Inventory")
	var auth_a: LocalAuthority = pa.get_node("InventoryAuthority")
	var auth_b: LocalAuthority = pb.get_node("InventoryAuthority")
	var recv_a: InventoryReceiver = pa.get_node("InventoryReceiver")
	var recv_b: InventoryReceiver = pb.get_node("InventoryReceiver")
	inv_a.contenido_cambiado.connect(func() -> void: _emis_a += 1)
	inv_b.contenido_cambiado.connect(func() -> void: _emis_b += 1)

	# ── 1. el actor A expone un InventoryReceiver valido ─────────────
	print("-- 1. PlayerV2_A expone un InventoryReceiver valido --")
	_check(recv_a != null and recv_a is InventoryReceiver, "1: A tiene un InventoryReceiver")
	_check(recv_a.get_parent() == pa, "1: es hijo DIRECTO del actor (nodo raiz PlayerV2)")
	_check(recv_a.inventory == inv_a and recv_a.authority == auth_a, "1: cableado a SU inventario y SU autoridad")

	# ── 2. WorldItemV2 resuelve el receiver desde el actor ───────────
	print("-- 2. WorldItemV2 resuelve el InventoryReceiver del actor --")
	var wi := _spawn_world_item()
	var ii: ItemInstance = wi.item_instance
	_check(wi._resolver_receiver(pa) == recv_a, "2: _resolver_receiver(PlayerV2_A) -> ReceiverA")
	_check(wi._resolver_receiver(pb) == recv_b, "2: _resolver_receiver(PlayerV2_B) -> ReceiverB (no cruza)")

	# ── 3..10. pickup por la ruta real; A recibe, B intacto ─────────
	print("-- 3. pickup A por _on_interact (ruta real, sin atajos) --")
	_check(_custodia(ii, [inv_a, inv_b]) == Vector2i(1, 0), "pre: custodia World=1 / Inv=0")

	var ok: bool = wi._on_interact(Interaction.new(pa, &"usar"))
	_check(ok, "3: _on_interact(actor = A) -> exito")
	_check(inv_a.get_entries().size() == 1, "4: InventoryA tiene exactamente 1 entry")
	_check(inv_a.has_item(ii), "5: la entry conserva el ItemInstance esperado")
	_check(inv_b.get_entries().is_empty(), "6: InventoryB queda vacio")
	_check(inv_b.get_entries().is_empty() and _emis_b == 0, "7: ReceiverB / AuthorityB nunca participaron (B byte-identico)")
	_check(_emis_a == 1, "8: InventoryA emitio contenido_cambiado exactamente 1 vez")
	_check(_emis_b == 0, "9: InventoryB no emitio ningun cambio")

	await get_tree().process_frame   # asienta el queue_free() del WorldItem consumido

	_check(_custodia(ii, [inv_a, inv_b]) == Vector2i(0, 1), "10: custodia XOR World=0 / Inv=1 (el WorldItem dejo el mundo)")
	_check(not is_instance_valid(wi) or wi.is_queued_for_deletion(), "10: el WorldItemV2 fue consumido")

	# ── 11. actor sin InventoryReceiver -> false, item intacto ──────
	print("-- 11. actor sin capacidad de inventario --")
	var wi2 := _spawn_world_item()
	var ii2: ItemInstance = wi2.item_instance
	var actor_pelado := Node.new()
	add_child(actor_pelado)
	var r11: bool = wi2._on_interact(Interaction.new(actor_pelado, &"usar"))
	_check(r11 == false, "11: _on_interact(actor sin receiver) -> false")
	_check(is_instance_valid(wi2) and wi2.is_inside_tree() and not wi2.is_queued_for_deletion(), "11: el WorldItemV2 sigue vivo en el mundo")
	_check(wi2.item_instance == ii2, "11: conserva su ItemInstance (no se movio ni destruyo)")
	_check(inv_a.get_entries().size() == 1 and inv_b.get_entries().is_empty(), "11: ningun inventario cambio")

	# ── 12. actor == null -> false seguro ──────────────────────────
	print("-- 12. actor null --")
	var r12: bool = wi2._on_interact(Interaction.new(null, &"usar"))
	_check(r12 == false, "12: _on_interact(actor = null) -> false, sin crash")
	_check(is_instance_valid(wi2) and not wi2.is_queued_for_deletion(), "12: el WorldItemV2 sigue intacto")

	print("========================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: FASE C1 (routing de pickup por InventoryReceiver) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de C1")
	get_tree().quit(_fallos)


func _spawn_world_item() -> WorldItemV2:
	var wi: WorldItemV2 = item_definition_test.world_scene.instantiate()
	wi.item_instance = ItemInstance.new(item_definition_test)
	add_child(wi)
	return wi


## (World, Inventory) = cuantos WorldItemV2 vivos + cuantas entries (sumando
## `inventarios`) representan a `ii`. Instrumentacion de test.
func _custodia(ii: ItemInstance, inventarios: Array) -> Vector2i:
	var w := 0
	var pila: Array[Node] = [get_tree().root]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is WorldItemV2 and not n.is_queued_for_deletion() and (n as WorldItemV2).item_instance == ii:
			w += 1
		pila.append_array(n.get_children())
	var i := 0
	for inv: InventoryV2 in inventarios:
		for e in inv.get_entries():
			if e.item_instance == ii:
				i += 1
	return Vector2i(w, i)


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
