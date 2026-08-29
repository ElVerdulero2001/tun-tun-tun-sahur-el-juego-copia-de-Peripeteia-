extends Node

## ARNES DE TEST — NO ES PRODUCCION. PlayerV2 · FASE C4-B / C4-C (ownership de TAB / ESC).
##
## Verifica por EVENTOS DE TECLADO SINTETICOS (InputEventKey via push_input) que
## PlayerInventoryUI es dueño de toggle_inventario y de ui_cancel-con-panel-abierto,
## y (C4-C) que con el panel CERRADO el ESC es inerte para el flujo PlayerV2 —
## player_v2.gd ya no togglea Input.mouse_mode por ui_cancel.
## NO simula movimiento de mouse real (eso lo cubre la prueba manual).
##
## mouse_mode NO se verifica: en headless el DisplayServer no honra
## Input.mouse_mode de forma robusta (ver C4-B0). Se verifica en la prueba manual.

const PLAYER_V2 := preload("res://scenes/player_v2/player_v2.tscn")
const SPY := preload("res://scenes/test/helpers/unhandled_action_spy.gd")
const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

var _fallos := 0
var _checks := 0
var _emis := 0   # MIEMBRO: los lambdas de GDScript capturan las locales por valor


func _ready() -> void:
	print("\n===== PLAYERV2 · FASE C4-B · ownership de toggle_inventario / ui_cancel =====")

	# ── Parte 1: una entidad, ciclo TAB / ESC ───────────────────────
	var p := PLAYER_V2.instantiate()
	add_child(p)
	var spy: Node = SPY.new()
	add_child(spy)
	await get_tree().process_frame

	var ui: CanvasLayer = p.get_node("PlayerInventoryUI")
	var panel: InventoryPanel = ui.panel
	var inv: InventoryV2 = p.get_node("Inventory")
	var auth: LocalAuthority = p.get_node("InventoryAuthority")

	print("-- 1. estado inicial --")
	_check(not panel.esta_abierto(), "1: panel arranca CERRADO")

	print("-- 2. TAB abre --")
	await _pulsar(&"toggle_inventario")
	_check(panel.esta_abierto(), "2: tras TAB, panel.esta_abierto() == true")
	_check(panel.visible, "2: panel.visible == true")
	_check(panel.manipulator.esta_activo(), "2: manipulator activo")
	_check(spy.toggle_inventario_count == 0, "2: PlayerInventoryUI consumio el TAB (spy no lo vio en _unhandled_input)")

	print("-- 3. TAB cierra --")
	await _pulsar(&"toggle_inventario")
	_check(not panel.esta_abierto(), "3: tras 2do TAB, panel.esta_abierto() == false")
	_check(not panel.visible, "3: panel.visible == false")
	_check(not panel.manipulator.esta_activo(), "3: manipulator inactivo")

	print("-- 4. ESC con panel abierto -> cierra, y PlayerInventoryUI lo consume --")
	await _pulsar(&"toggle_inventario")          # abrir
	_check(panel.esta_abierto(), "4: (setup) panel abierto")
	var esc0: int = spy.ui_cancel_count
	await _pulsar(&"ui_cancel")
	_check(not panel.esta_abierto(), "4: tras ESC, panel cerrado")
	_check(spy.ui_cancel_count == esc0, "4: PlayerInventoryUI consumio el ESC (spy no lo vio)")

	print("-- 5. ESC con panel CERRADO -> PlayerInventoryUI NO lo consume --")
	_check(not panel.esta_abierto(), "5: (setup) panel cerrado")
	var esc1: int = spy.ui_cancel_count
	await _pulsar(&"ui_cancel")
	_check(spy.ui_cancel_count == esc1 + 1, "5: el ESC llego SIN consumir a _unhandled_input (PlayerInventoryUI no lo toco)")
	_check(not panel.esta_abierto(), "5: el panel sigue cerrado")

	print("-- 6. ESC con panel abierto y un item AGARRADO -> cancela seguro --")
	var actor: Node = InventoryTestActor.crear(inv, auth)
	add_child(actor)
	var def := load("res://assets/data/test_inventory_v2/item_definition_test.tres") as ItemDefinition
	var ii := ItemInstance.new(def)
	var wi: WorldItemV2 = def.world_scene.instantiate()
	wi.item_instance = ii
	add_child(wi)
	var sembrado: bool = wi._on_interact(Interaction.new(actor, &"usar"))
	_check(sembrado and inv.get_entries().size() == 1, "6: (setup) item sembrado en el inventario")

	await _pulsar(&"toggle_inventario")          # abrir
	var m := panel.manipulator
	var pos0: Vector2i = inv.get_entries()[0].position
	_check(m.agarrar_en(pos0), "6: (setup) manipulator agarro el item")
	_check(m.esta_agarrando(), "6: (setup) item held")
	_emis = 0
	inv.contenido_cambiado.connect(func() -> void: _emis += 1)

	await _pulsar(&"ui_cancel")
	_check(not panel.esta_abierto(), "6: ESC cerro el panel")
	_check(not m.esta_agarrando(), "6: el item ya NO esta held (cancelado via panel.cerrar->desactivar->cancelar)")
	_check(inv.get_entries().size() == 1, "6: el item sigue en el inventario (modelo intacto)")
	_check(inv.get_entries()[0].position == pos0, "6: el item no se movio")
	_check(_emis == 0, "6: cancelar NO emitio contenido_cambiado")

	# ── Parte C4-C: ESC con inventario CERRADO es inerte para PlayerV2 ──
	print("-- 8. C4-C: ESC con panel CERRADO no hace nada (player_v2.gd ya no togglea mouse_mode) --")
	_check(not panel.esta_abierto(), "8: (setup) panel cerrado")
	var esc8: int = spy.ui_cancel_count
	await _pulsar(&"ui_cancel")
	await _pulsar(&"ui_cancel")
	await _pulsar(&"ui_cancel")
	_check(not panel.esta_abierto(), "8: 3x ESC no abrieron ni cambiaron el panel")
	_check(spy.ui_cancel_count == esc8 + 3, "8: los 3 ESC llegaron SIN consumir (PlayerInventoryUI inerte con panel cerrado)")
	await _pulsar(&"toggle_inventario")
	_check(panel.esta_abierto(), "8: TAB sigue abriendo despues de los ESC")
	await _pulsar(&"toggle_inventario")
	_check(not panel.esta_abierto(), "8: y cerrando")
	# Que player_v2.gd NO cambie Input.mouse_mode por ESC se verifica en la prueba
	# MANUAL (headless no honra Input.mouse_mode de forma robusta — ver C4-B0).

	# ── Parte 2: dos entidades, instancias separadas ────────────────
	print("-- 7. dos PlayerInventoryUI son instancias separadas --")
	var pa := PLAYER_V2.instantiate()
	var pb := PLAYER_V2.instantiate()
	add_child(pa)
	add_child(pb)
	await get_tree().process_frame
	var ui_a: CanvasLayer = pa.get_node("PlayerInventoryUI")
	var ui_b: CanvasLayer = pb.get_node("PlayerInventoryUI")
	_check(ui_a != ui_b, "7: dos PlayerInventoryUI distintos")
	_check(ui_a.panel != ui_b.panel, "7: dos InventoryPanel distintos")
	_check(ui_a.inventory == pa.get_node("Inventory") and ui_b.inventory == pb.get_node("Inventory"), "7: cada uno cableado a SU Inventory")
	_check(ui_a.inventory != ui_b.inventory, "7: sin referencia cruzada de Inventory")

	print("=========================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: FASE C4-B / C4-C (ownership TAB/ESC) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de C4-B")
	get_tree().quit(_fallos)


## Pulsa y suelta una accion como InputEventKey sintetico a traves del viewport.
## Setea keycode Y physical_keycode: toggle_inventario esta bound por
## physical_keycode (TAB) y ui_cancel (built-in) por keycode (ESC).
func _pulsar(accion: StringName) -> void:
	var kc := KEY_TAB if accion == &"toggle_inventario" else KEY_ESCAPE
	var press := InputEventKey.new()
	press.keycode = kc
	press.physical_keycode = kc
	press.pressed = true
	get_viewport().push_input(press)
	await get_tree().process_frame
	var release := InputEventKey.new()
	release.keycode = kc
	release.physical_keycode = kc
	release.pressed = false
	get_viewport().push_input(release)
	await get_tree().process_frame


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
