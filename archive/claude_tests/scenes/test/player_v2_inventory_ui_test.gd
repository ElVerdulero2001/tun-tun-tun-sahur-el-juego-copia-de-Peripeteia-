extends Node

## ARNES DE TEST — NO ES PRODUCCION. PlayerV2 · FASE C4-A (composicion estructural de UI).
##
## Instancia dos player_v2.tscn y verifica que PlayerInventoryUI compone el
## InventoryPanel y lo cablea al InventoryV2 / LocalAuthority de SU entidad, sin
## referencias cruzadas y con el panel cerrado.
##
## NO prueba TAB / toggle_inventario / Input.mouse_mode / convivencia legacy
## (eso es C4-B). White-box sobre panel.grid_view / panel.manipulator: consistente
## con inventory_panel_test.

const PLAYER_V2 := preload("res://scenes/player_v2/player_v2.tscn")

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== PLAYERV2 · FASE C4-A · composicion estructural PlayerInventoryUI =====")

	var pa := PLAYER_V2.instantiate()
	var pb := PLAYER_V2.instantiate()
	add_child(pa)
	add_child(pb)
	await get_tree().process_frame   # _ready() de PlayerInventoryUI (panel.setup)

	var inv_a: InventoryV2 = pa.get_node("Inventory")
	var auth_a: LocalAuthority = pa.get_node("InventoryAuthority")
	var ui_a: CanvasLayer = pa.get_node("PlayerInventoryUI")
	var inv_b: InventoryV2 = pb.get_node("Inventory")
	var auth_b: LocalAuthority = pb.get_node("InventoryAuthority")
	var ui_b: CanvasLayer = pb.get_node("PlayerInventoryUI")

	# ── 1. PlayerInventoryUI hijo directo del root ───────────────────
	print("-- 1. PlayerInventoryUI colgado del root PlayerV2 --")
	_check(ui_a != null and ui_a is CanvasLayer, "1: PlayerInventoryUI es un CanvasLayer")
	_check(ui_a.get_parent() == pa, "1: hijo DIRECTO del nodo raiz PlayerV2")

	# ── 2. tiene un InventoryPanel valido ───────────────────────────
	print("-- 2. InventoryPanel compuesto --")
	var panel_a: InventoryPanel = ui_a.panel
	var panel_b: InventoryPanel = ui_b.panel
	_check(panel_a != null and panel_a is InventoryPanel, "2: ui.panel es un InventoryPanel")
	_check(panel_a.get_parent() == ui_a, "2: el panel es hijo del PlayerInventoryUI (el CanvasLayer que exige su contrato)")

	# ── 3-4. @export cableados a SU entidad ─────────────────────────
	print("-- 3-4. cableado @export --")
	_check(ui_a.inventory == inv_a, "3: ui_a.inventory == PlayerV2_A/Inventory")
	_check(ui_a.authority == auth_a, "4: ui_a.authority == PlayerV2_A/InventoryAuthority")

	# ── 5. configurado tras _ready ─────────────────────────────────
	print("-- 5-6. estado del panel tras _ready --")
	_check(panel_a.esta_configurado(), "5: panel.esta_configurado() == true")

	# ── 6. arranca cerrado / no visible ────────────────────────────
	_check(not panel_a.esta_abierto(), "6: panel.esta_abierto() == false")
	_check(not panel_a.visible, "6: panel.visible == false")
	_check(not panel_a.manipulator.esta_activo(), "6: manipulator inactivo")
	_check(not panel_a.manipulator.is_processing_unhandled_input(), "6: manipulator no procesa unhandled_input")

	# ── 7. grid_view apunta al InventoryV2 de esa entidad ──────────
	print("-- 7-8. la UI opera sobre el modelo/autoridad de A --")
	_check(panel_a.grid_view.get_inventory() == inv_a, "7: panel.grid_view apunta al InventoryV2 de A")

	# ── 8. manipulator usa la LocalAuthority de esa entidad (white-box) ──
	_check(panel_a.manipulator._authority == auth_a, "8: panel.manipulator._authority == LocalAuthority de A")

	# ── 9. dos entidades, sin cruces ──────────────────────────────
	print("-- 9. aislamiento entre dos PlayerV2 --")
	_check(ui_a != ui_b, "9: dos PlayerInventoryUI distintos")
	_check(panel_a != panel_b, "9: dos InventoryPanel distintos")
	_check(ui_b.inventory == inv_b and ui_b.authority == auth_b, "9: ui_b cableado a SU Inventory/Authority")
	_check(ui_a.inventory != inv_b and ui_a.authority != auth_b, "9: ui_a NO cruza a los nodos de B")
	_check(panel_b.grid_view.get_inventory() == inv_b, "9: grid_view de B -> InventoryV2 de B")
	_check(panel_a.grid_view.get_inventory() != inv_b, "9: grid_view de A NO -> InventoryV2 de B")
	_check(panel_a.manipulator._authority != auth_b, "9: manipulator de A NO usa la autoridad de B")

	print("=========================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: FASE C4-A (composicion PlayerInventoryUI) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de C4-A")
	get_tree().quit(_fallos)


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
