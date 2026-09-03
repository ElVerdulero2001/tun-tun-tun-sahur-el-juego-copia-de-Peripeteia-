extends Node3D

## ARNES DE TEST — NO ES PRODUCCION. SUA-1.6 C.
##
## Segundo ASSET REAL migrado: scenes/props/dinamic/sable_san_martin_1.tscn ahora
## es un WorldItemV2 con `definition` = assets/data/items_v2/sable.tres.
## Mismo patron que botella (SUA-1.6 B); este test NO re-verifica todo el contrato
## de ItemDefinition/WorldItemV2 (ya cubierto por botella_v2_migration_test) — se
## concentra en demostrar que el patron se reutiliza en un segundo asset:
##  - carga sin Parse Error;
##  - autoaprovisionamiento;
##  - footprint 1x4 y rotacion 1x4 <-> 4x1;
##  - ciclo real MUNDO -> INVENTARIO -> MUNDO -> INVENTARIO con identidad estable;
##  - el WorldItemV2 devuelto ES sable_san_martin_1 (mesh + collider + InteractionComponentV2).
##
## Root Node3D a proposito: get_tree().current_scene = este nodo (ItemDropper valida Node3D).

const SABLE_PATH := "res://scenes/props/dinamic/sable_san_martin_1.tscn"
const SABLE_DEF_PATH := "res://assets/data/items_v2/sable.tres"
const SABLE := preload(SABLE_PATH)
const SABLE_DEF := preload(SABLE_DEF_PATH)
const PLAYER_V2 := preload("res://scenes/player_v2/player_v2.tscn")

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== SUA-1.6 C · sable real -> WorldItemV2 + ItemDefinition =====")
	await _carga_y_autoaprovisionamiento()
	await _ciclo_real()

	print("=================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: SUA-1.6 C (sable real migrado) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de SUA-1.6 C")
	get_tree().quit(_fallos)


func _carga_y_autoaprovisionamiento() -> void:
	print("-- 1-6. carga fria + autoaprovisionamiento --")
	var escena := ResourceLoader.load(SABLE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	_check(escena != null, "1: sable_san_martin_1.tscn carga (IGNORE_DEEP) sin Parse Error")
	if escena == null:
		return

	var s0 := SABLE.instantiate() as WorldItemV2
	_check(s0 != null, "2: root ES WorldItemV2")
	_check(s0 != null and s0.definition != null, "3: definition != null")
	_check(s0 != null and s0.definition == SABLE_DEF, "4: definition ES sable.tres (misma referencia cacheada)")
	_check(s0 != null and s0.item_instance == null, "5: sin ItemInstance ANTES de add_child")
	add_child(s0)
	await get_tree().process_frame
	_check(s0.item_instance != null and s0.item_instance is ItemInstance, "5: autoaprovisiono EXACTAMENTE un ItemInstance")
	var ref0 := s0.item_instance
	await get_tree().process_frame
	_check(s0.item_instance == ref0, "5: no se recrea frame a frame")
	_check(s0.item_instance.definition == SABLE_DEF, "6: item_instance.definition ES sable.tres")
	_check(SABLE_DEF.grid_width == 1 and SABLE_DEF.grid_height == 4 and SABLE_DEF.can_rotate,
		"8: footprint definido 1x4, can_rotate=true")
	s0.queue_free()
	await get_tree().process_frame


func _ciclo_real() -> void:
	print("-- 7-16. ciclo real MUNDO <-> INVENTARIO con PlayerV2 --")
	var pa := PLAYER_V2.instantiate()
	add_child(pa)
	await get_tree().process_frame
	var inv: InventoryV2 = pa.get_node("Inventory")
	var authority: LocalAuthority = pa.get_node("InventoryAuthority")
	var ui: CanvasLayer = pa.get_node("PlayerInventoryUI")
	var panel: InventoryPanel = ui.panel
	var manip: InventoryManipulator = panel.manipulator
	var dp: Marker3D = pa.get_node("Body/DropPoint")

	var sable_mundo := SABLE.instantiate() as WorldItemV2
	add_child(sable_mundo)
	await get_tree().process_frame
	var ii: ItemInstance = sable_mundo.item_instance
	_check(ii != null, "7: (setup) sable en el mundo autoaprovisiono su ItemInstance")

	# 7. pickup real
	var ok: bool = sable_mundo._on_interact(Interaction.new(pa, &"usar"))
	await get_tree().process_frame
	_check(ok and inv.has_item(ii), "7: pickup real MUNDO -> InventoryV2")
	_check(inv.get_entries().size() == 1, "7: 1 entry")

	# 8. footprint 1x4 sin rotar
	var e := inv.get_entries()[0]
	_check(e.get_footprint() == Vector2i(1, 4) and not e.rotated, "8: entry ocupa 1x4 (sin rotar)")

	# 9. rotacion 1x4 <-> 4x1 via reubicacion real (LocalAuthority -> TransferOperation)
	var ok_rot: bool = authority.solicitar_reubicacion(ii, inv, Vector2i(0, 0), true)
	_check(ok_rot, "9: reubicacion a (0,0) rotado -> true")
	var er := inv.get_entries()[0]
	_check(er.get_footprint() == Vector2i(4, 1) and er.rotated, "9: entry ahora 4x1 (rotada)")
	_check(er.item_instance == ii, "9: misma referencia ItemInstance tras rotar")
	# volver a 1x4 para el resto del ciclo
	authority.solicitar_reubicacion(ii, inv, Vector2i(0, 0), false)

	# 10. drop real por la cadena de UI real (manipulator -> panel -> PlayerInventoryUI -> ItemDropper)
	panel.abrir()
	_check(manip.agarrar_en(inv.get_entries()[0].position), "10: (setup) manipulator agarro el sable")
	var world0 := _contar_world_items()
	var dp_esperado := dp.global_position
	manip._resolver_click_held(Vector2(5000, 5000))
	var wi := _world_item_de(ii)
	_check(wi != null, "10: drop real InventoryV2 -> MUNDO produjo un WorldItemV2")
	_check(_contar_world_items() == world0 + 1, "10: exactamente 1 WorldItemV2 nuevo")
	_check(not inv.has_item(ii) and inv.get_entries().is_empty(), "10: el sable dejo el InventoryV2")
	_check(wi != null and wi.global_position.is_equal_approx(dp_esperado), "10: aparecio en el DropPoint (%s)" % dp_esperado)
	panel.cerrar()

	# 11-12. el WorldItemV2 devuelto ES sable_san_martin_1, misma ItemInstance
	_check(wi != null and wi.scene_file_path == SABLE_PATH, "11: la escena reaparecida ES sable_san_martin_1.tscn")
	_check(wi != null and wi.item_instance == ii, "12: MISMA referencia ItemInstance")
	_check(wi != null and wi.definition == SABLE_DEF, "12: el WorldItemV2 nuevo trae definition = sable.tres")

	# 15-16. neutral + estructura
	_check(wi != null and not ("_authority" in wi), "15: el WorldItemV2 sigue NEUTRAL")
	_check(wi != null and wi.get_node_or_null("machetedesanmartin4") != null, "16: conserva el mesh")
	_check(wi != null and _tiene(wi, "CollisionShape3D"), "16: conserva su collider")
	_check(wi != null and _tiene_interaction_component_v2(wi), "16: conserva su InteractionComponentV2 hijo directo")

	# 13. re-pickup real
	var ok2: bool = wi._on_interact(Interaction.new(pa, &"usar"))
	await get_tree().process_frame
	_check(ok2 and inv.has_item(ii), "13: re-pickup real MUNDO -> InventoryV2")
	_check(inv.get_entries()[0].item_instance == ii, "13: la entry conserva la MISMA referencia ItemInstance")
	_check(not is_instance_valid(wi) or wi.is_queued_for_deletion(), "13: el WorldItemV2 droppeado fue consumido")

	# 14. identidad estable de punta a punta: `ii` fue capturado del sable colocado
	# en el mundo (autoaprovisionado); tras pickup -> rotar -> drop -> re-pickup la
	# entry final debe seguir llevando ESA referencia.
	_check(inv.get_entries()[0].item_instance == ii,
		"14: identidad estable: MUNDO -> INV -> MUNDO -> INV, misma referencia ItemInstance")


func _world_item_de(ii: ItemInstance) -> WorldItemV2:
	for wi in _todos_world_items():
		if wi.item_instance == ii:
			return wi
	return null


func _contar_world_items() -> int:
	return _todos_world_items().size()


func _todos_world_items() -> Array[WorldItemV2]:
	var res: Array[WorldItemV2] = []
	var pila: Array[Node] = [get_tree().root]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is WorldItemV2 and not n.is_queued_for_deletion():
			res.append(n)
		pila.append_array(n.get_children())
	return res


func _tiene(nodo: Node, clase: String) -> bool:
	for child in nodo.get_children():
		if child.get_class() == clase:
			return true
	return false


func _tiene_interaction_component_v2(nodo: Node) -> bool:
	for child in nodo.get_children():
		if child is InteractionComponentV2:
			return true
	return false


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
