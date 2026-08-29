extends Node3D

## ARNES DE TEST — NO ES PRODUCCION. PlayerV2 · FASE C5-C (drop UI -> ItemDropper).
##
## El root es Node3D a proposito: get_tree().current_scene es este nodo y
## ItemDropper.soltar() valida current_scene as Node3D (y ahi cuelga el WorldItem).
##
## Cierra el ciclo de gameplay conectando las dos mitades que ya existian:
##   C5-B/B2:  InventoryManipulator.drop_fuera_solicitado -> InventoryPanel (1:1)
##   C5-C:     InventoryPanel.drop_fuera_solicitado -> PlayerInventoryUI -> ItemDropper.soltar
##   C5-A:     ItemDropper.soltar -> LocalAuthority.solicitar_devolucion -> WorldItemV2
##
## Se dispara SIEMPRE desde la señal real (manipulator held + _resolver_click_held
## con cursor EXTERIOR), nunca llamando al handler de PlayerInventoryUI a mano.
##
## Demostracion central: MUNDO -> INVENTARIO -> MUNDO -> INVENTARIO con el MISMO
## ItemInstance (identidad por referencia) en todo el ciclo.

const PLAYER_V2 := preload("res://scenes/player_v2/player_v2.tscn")

@export var item_definition_test: ItemDefinition   # 2x1, world_scene = test_item_v0

var _fallos := 0
var _checks := 0
var _emis_a := 0
var _emis_b := 0


func _ready() -> void:
	print("\n===== PLAYERV2 · FASE C5-C · drop desde la UI -> ItemDropper =====")

	var pa := PLAYER_V2.instantiate()
	var pb := PLAYER_V2.instantiate()
	add_child(pa)
	add_child(pb)
	await get_tree().process_frame

	var inv_a: InventoryV2 = pa.get_node("Inventory")
	var inv_b: InventoryV2 = pb.get_node("Inventory")
	var auth_a: LocalAuthority = pa.get_node("InventoryAuthority")
	var drop_a: ItemDropper = pa.get_node("ItemDropper")
	var drop_b: ItemDropper = pb.get_node("ItemDropper")
	var dp_a: Marker3D = pa.get_node("Body/DropPoint")
	var ui_a: CanvasLayer = pa.get_node("PlayerInventoryUI")
	var ui_b: CanvasLayer = pb.get_node("PlayerInventoryUI")
	var panel_a: InventoryPanel = ui_a.panel
	var manip_a: InventoryManipulator = panel_a.manipulator

	inv_a.contenido_cambiado.connect(func() -> void: _emis_a += 1)
	inv_b.contenido_cambiado.connect(func() -> void: _emis_b += 1)

	# ── 1. wiring PlayerInventoryUI -> ItemDropper de SU PlayerV2 ────
	print("-- 1. cada PlayerInventoryUI apunta al ItemDropper de SU entidad --")
	_check(ui_a.dropper == drop_a, "1: ui_a.dropper == ItemDropper de A")
	_check(ui_b.dropper == drop_b, "1: ui_b.dropper == ItemDropper de B")
	_check(ui_a.dropper != null and ui_b.dropper != null, "1: ambos dropper cableados (no null)")

	# ── 2. dos PlayerV2 -> wiring aislado, sin referencia cruzada ────
	print("-- 2. dos PlayerV2: dos UI, dos droppers, sin cruce --")
	_check(ui_a != ui_b, "2: dos PlayerInventoryUI distintos")
	_check(drop_a != drop_b, "2: dos ItemDropper distintos")
	_check(ui_a.dropper != ui_b.dropper, "2: ninguna UI ve el dropper de la otra")
	_check(drop_a.inventory == inv_a and drop_b.inventory == inv_b, "2: cada dropper -> SU Inventory")
	_check(drop_a.spawn_source == dp_a and drop_b.spawn_source != dp_a, "2: cada dropper -> SU DropPoint")

	# ── 3. sembrar un item en el Inventory de A por pickup REAL ─────
	print("-- 3. (setup) MUNDO -> INVENTARIO de A por la ruta real de pickup --")
	var wi0: WorldItemV2 = item_definition_test.world_scene.instantiate()
	var ii := ItemInstance.new(item_definition_test)
	wi0.item_instance = ii
	add_child(wi0)
	var sembrado: bool = wi0._on_interact(Interaction.new(pa, &"usar"))
	await get_tree().process_frame
	_check(sembrado and inv_a.has_item(ii), "3: A recogio el item (pickup real, actor = PlayerV2_A)")
	_check(inv_a.get_entries().size() == 1, "3: Inventory de A tiene 1 entry")
	_check(_custodia(ii, [inv_a, inv_b]) == Vector2i(0, 1), "3: custodia World=0 / Inv=1")
	var emis_a_pre_drop := _emis_a

	# ── 4. disparar la INTENCION real: held + click EXTERIOR ───────
	print("-- 4. TAB (abrir) + agarrar + soltar con cursor EXTERIOR -> señal real --")
	panel_a.abrir()
	_check(panel_a.esta_abierto() and manip_a.esta_activo(), "4: (setup) panel abierto, manipulator activo")
	_check(manip_a.agarrar_en(inv_a.get_entries()[0].position), "4: (setup) manipulator agarro el item")
	_check(manip_a.item_agarrado() == ii, "4: (setup) held == MISMA referencia ItemInstance")

	var world0 := _contar_world_items()
	# Body es CharacterBody3D con gravedad y este arnes no tiene piso: DropPoint
	# se desplaza entre frames. El drop spawnea en spawn_source.global_position
	# EN EL MOMENTO del drop, y toda la cadena señal -> handler -> soltar ->
	# solicitar_devolucion -> commit es SINCRONA -> capturamos la referencia ya.
	var dp_esperado := dp_a.global_position
	# cursor claramente fuera de la grilla y del anillo neutro (grilla 4x4 * cell_size, +margen)
	manip_a._resolver_click_held(Vector2(5000, 5000))

	# ── 5. resultado del drop: A vacio, B intacto, 1 WorldItem en DropPoint de A ──
	print("-- 5. INVENTARIO de A -> MUNDO en el DropPoint de A --")
	var wi_dropped := _world_item_de(ii)
	_check(wi_dropped != null, "5: aparecio un WorldItemV2 para ese ItemInstance")
	_check(_contar_world_items() == world0 + 1, "5: exactamente UN WorldItemV2 nuevo bajo la escena")
	_check(wi_dropped != null and wi_dropped.item_instance == ii, "5: WorldItemV2.item_instance == MISMA referencia")
	_check(wi_dropped != null and wi_dropped.get_parent() == get_tree().current_scene, "5: el WorldItemV2 cuelga de current_scene")
	_check(get_tree().current_scene == self, "5: (contexto) current_scene == este arnes")
	_check(wi_dropped != null and wi_dropped.global_position.is_equal_approx(dp_esperado),
		"5: global_position == DropPoint de A al soltar (%s)" % dp_esperado)
	_check(wi_dropped != null and not ("_authority" in wi_dropped), "5: el WorldItemV2 sigue NEUTRAL")

	_check(not inv_a.has_item(ii), "5: el ItemInstance ya NO esta en el Inventory de A")
	_check(inv_a.get_entries().is_empty(), "5: Inventory de A quedo vacio")
	_check(inv_b.get_entries().is_empty() and _emis_b == 0, "5: Inventory de B no cambio")
	_check(_emis_a == emis_a_pre_drop + 1, "5: Inventory de A emitio contenido_cambiado exactamente 1 vez")
	_check(not manip_a.esta_agarrando(), "5: el manipulator ya no esta held")
	_check(_custodia(ii, [inv_a, inv_b]) == Vector2i(1, 0), "5: custodia XOR World=1 / Inv=0")

	# ── 6. panel NO se cierra tras el drop ────────────────────────
	print("-- 6. tras el drop el InventoryPanel sigue abierto --")
	_check(panel_a.esta_abierto(), "6: el panel permanece abierto (el jugador sigue en el inventario)")
	panel_a.cerrar()

	# ── 7. MUNDO -> INVENTARIO otra vez por la ruta real de pickup ─
	print("-- 7. re-pickup del WorldItemV2 soltado: MUNDO -> INVENTARIO de A --")
	var emis_a_pre_pick := _emis_a
	var repick: bool = wi_dropped._on_interact(Interaction.new(pa, &"usar"))
	await get_tree().process_frame
	_check(repick, "7: _on_interact(actor = A) sobre el item soltado -> exito")
	_check(inv_a.has_item(ii), "7: el ItemInstance volvio al Inventory de A")
	_check(inv_a.get_entries().size() == 1, "7: Inventory de A tiene 1 entry de nuevo")
	_check(inv_a.get_entries()[0].item_instance == ii, "7: la entry conserva la MISMA referencia ItemInstance")
	_check(inv_b.get_entries().is_empty(), "7: Inventory de B sigue vacio")
	_check(_emis_a == emis_a_pre_pick + 1, "7: contenido_cambiado exactamente 1 vez en el re-pickup")
	_check(not is_instance_valid(wi_dropped) or wi_dropped.is_queued_for_deletion(), "7: el WorldItemV2 dejo el mundo")
	_check(_custodia(ii, [inv_a, inv_b]) == Vector2i(0, 1), "7: custodia XOR World=0 / Inv=1")

	# ── 8. identidad estable en TODO el ciclo ─────────────────────
	print("-- 8. MUNDO -> INV -> MUNDO -> INV con identidad estable --")
	_check(inv_a.get_entries()[0].item_instance == ii, "8: el objeto final es EXACTAMENTE la referencia inicial (==)")

	# ── 9. caso de fallo: drop de un ItemInstance ajeno al inventario ──
	print("-- 9. intento de drop de un ItemInstance que NO pertenece al Inventory de A --")
	var ii_ajeno := ItemInstance.new(item_definition_test)
	var world_pre := _contar_world_items()
	var entries_pre := inv_a.get_entries().size()
	var emis_pre := _emis_a
	# emitir la señal real de la UI (manipulator -> panel -> PlayerInventoryUI -> dropper)
	manip_a.drop_fuera_solicitado.emit(ii_ajeno)
	await get_tree().process_frame
	_check(_contar_world_items() == world_pre, "9: no aparecio ningun WorldItemV2 adicional")
	_check(inv_a.get_entries().size() == entries_pre, "9: Inventory de A intacto")
	_check(inv_a.has_item(ii) and not inv_a.has_item(ii_ajeno), "9: custodia sin corrupcion")
	_check(_emis_a == emis_pre, "9: sin contenido_cambiado")
	_check(drop_a.soltar(ii_ajeno) == null, "9: (contrato C5-A) ItemDropper.soltar(item ajeno) -> null")

	print("=================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: FASE C5-C (drop UI -> ItemDropper) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de C5-C")
	get_tree().quit(_fallos)


## (World, Inventory) = WorldItemV2 vivos + entries (sumando `invs`) que representan a `ii`.
func _custodia(ii: ItemInstance, invs: Array) -> Vector2i:
	var w := 0
	for wi in _todos_world_items():
		if wi.item_instance == ii:
			w += 1
	var i := 0
	for inv: InventoryV2 in invs:
		for e in inv.get_entries():
			if e.item_instance == ii:
				i += 1
	return Vector2i(w, i)


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


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
