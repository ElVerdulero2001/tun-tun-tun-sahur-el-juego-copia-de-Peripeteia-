extends Node3D

## ARNES DE TEST — NO ES PRODUCCION. PlayerV2 · FASE C5-A (ItemDropper).
##
## El root es Node3D a proposito: al correr esta escena, get_tree().current_scene
## es este nodo, y ItemDropper.soltar() valida current_scene as Node3D.
##
## Instancia dos player_v2.tscn y verifica ItemDropper estructuralmente y la
## operacion soltar() (via LocalAuthority, SIN disparador de UI — eso es C5-B/C).

const PLAYER_V2 := preload("res://scenes/player_v2/player_v2.tscn")
const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== PLAYERV2 · FASE C5-A · ItemDropper (inventario -> mundo) =====")

	var pa := PLAYER_V2.instantiate()
	var pb := PLAYER_V2.instantiate()
	add_child(pa)
	add_child(pb)
	await get_tree().process_frame

	var inv_a: InventoryV2 = pa.get_node("Inventory")
	var auth_a: LocalAuthority = pa.get_node("InventoryAuthority")
	var drop_a: ItemDropper = pa.get_node("ItemDropper")
	var dp_a: Marker3D = pa.get_node("Body/DropPoint")
	var inv_b: InventoryV2 = pb.get_node("Inventory")
	var drop_b: ItemDropper = pb.get_node("ItemDropper")
	var dp_b: Marker3D = pb.get_node("Body/DropPoint")

	# ── 1. estructura y cableado ────────────────────────────────────
	print("-- 1. estructura y cableado --")
	_check(drop_a is ItemDropper, "1: ItemDropper es un ItemDropper")
	_check(drop_a.get_parent() == pa, "1: ItemDropper es hijo DIRECTO del root PlayerV2")
	_check(dp_a is Marker3D and dp_a.get_parent() == pa.get_node("Body"), "1: DropPoint es un Marker3D hijo de Body")
	_check(drop_a.inventory == inv_a, "1: dropper.inventory == Inventory de A")
	_check(drop_a.authority == auth_a, "1: dropper.authority == InventoryAuthority de A")
	_check(drop_a.spawn_source == dp_a, "1: dropper.spawn_source == Body/DropPoint de A")

	# ── 2. aislamiento entre dos PlayerV2 ──────────────────────────
	print("-- 2. dos PlayerV2 -> droppers aislados --")
	_check(drop_a != drop_b, "2: dos ItemDropper distintos")
	_check(drop_b.inventory == inv_b and drop_b.inventory != inv_a, "2: dropper_b -> Inventory de B, sin cruce")
	_check(drop_b.spawn_source == dp_b and dp_b != dp_a, "2: cada dropper apunta a SU DropPoint")

	# ── 3. soltar un item que esta en el inventario ────────────────
	print("-- 3. soltar un item bajo custodia de A --")
	var actor: Node = InventoryTestActor.crear(inv_a, auth_a)
	add_child(actor)
	var def := load("res://assets/data/test_inventory_v2/item_definition_test.tres") as ItemDefinition
	var ii := ItemInstance.new(def)
	var wi_pick: WorldItemV2 = def.world_scene.instantiate()
	wi_pick.item_instance = ii
	add_child(wi_pick)
	var ok: bool = wi_pick._on_interact(Interaction.new(actor, &"usar"))
	_check(ok and inv_a.get_entries().size() == 1, "3: (setup) item recogido en Inventory de A")
	_check(_custodia(ii, [inv_a, inv_b]) == Vector2i(0, 1), "3: (setup) custodia World=0 / Inv=1")

	var wi := drop_a.soltar(ii)

	_check(wi != null and wi is WorldItemV2, "3: soltar() devolvio un WorldItemV2")
	_check(wi != null and wi.item_instance == ii, "3: MISMA referencia ItemInstance")
	_check(inv_a.get_entries().is_empty(), "3: el item desaparecio del InventoryV2 de A")
	_check(inv_b.get_entries().is_empty(), "3: Inventory de B no cambio")
	_check(wi != null and wi.get_parent() == get_tree().current_scene, "3: el WorldItemV2 quedo bajo current_scene")
	_check(get_tree().current_scene == self, "3: (contexto) current_scene == este arnes")
	_check(wi != null and wi.global_position.is_equal_approx(dp_a.global_position), "3: posicion del WorldItemV2 == DropPoint de A (%s)" % dp_a.global_position)
	_check(wi != null and not ("_authority" in wi), "3: el WorldItemV2 sigue NEUTRAL (sin campo _authority)")
	_check(_custodia(ii, [inv_a, inv_b]) == Vector2i(1, 0), "3: custodia XOR: World=1 / Inv=0")

	await get_tree().process_frame   # asienta el queue_free() del WorldItem del pickup
	_check(_custodia(ii, [inv_a, inv_b]) == Vector2i(1, 0), "3: custodia XOR estable tras el frame")

	# ── 4. soltar un item que NO esta en el inventario ────────────
	print("-- 4. soltar un item ajeno --")
	var ii_ajeno := ItemInstance.new(def)
	var world0 := _contar_world_items()
	var r := drop_a.soltar(ii_ajeno)
	_check(r == null, "4: soltar(item ajeno) devuelve null")
	_check(inv_a.get_entries().is_empty(), "4: Inventory de A sin cambios")
	_check(_contar_world_items() == world0, "4: no aparecio ningun WorldItemV2 adicional")

	print("==================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: FASE C5-A (ItemDropper) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de C5-A")
	get_tree().quit(_fallos)


## (World, Inventory) = WorldItemV2 vivos + entries (sumando `invs`) que representan a `ii`.
func _custodia(ii: ItemInstance, invs: Array) -> Vector2i:
	var w := 0
	var pila: Array[Node] = [get_tree().root]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is WorldItemV2 and not n.is_queued_for_deletion() and (n as WorldItemV2).item_instance == ii:
			w += 1
		pila.append_array(n.get_children())
	var i := 0
	for inv: InventoryV2 in invs:
		for e in inv.get_entries():
			if e.item_instance == ii:
				i += 1
	return Vector2i(w, i)


func _contar_world_items() -> int:
	var n := 0
	var pila: Array[Node] = [get_tree().root]
	while not pila.is_empty():
		var nodo: Node = pila.pop_back()
		if nodo is WorldItemV2 and not nodo.is_queued_for_deletion():
			n += 1
		pila.append_array(nodo.get_children())
	return n


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
