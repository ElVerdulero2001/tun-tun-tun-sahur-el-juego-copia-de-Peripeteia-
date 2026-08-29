extends Node3D

## ARNES DE TEST — NO ES PRODUCCION. Inventory · SUA-1.5 C5-B / C5-B2.
##
## C5-B  : InventoryManipulator distingue "soltar DENTRO de la grilla"
##         (reubicacion) de "soltar FUERA" (intencion drop_fuera_solicitado,
##         sin tocar el modelo ni la autoridad). InventoryPanel la reenvia 1:1.
## C5-B2 : anillo NEUTRO de drop_neutral_margin_px alrededor de la grilla ->
##         soltar ahi es NO-OP absoluto (el item sigue held/unido al mouse).
##
## Nadie consume la señal (ItemDropper se conecta en C5-C). White-box sobre
## panel.manipulator: consistente con inventory_panel_test.

const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

@export var item_definition_test: ItemDefinition        # 2x1 can_rotate
@export var item_definition_no_rota: ItemDefinition     # 2x1 can_rotate = false

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv                    # 4x4
@onready var panel: InventoryPanel = $CanvasLayer/InventoryPanel

const CELL := 32                                        # cell_size del .tscn
const W := 4 * CELL                                     # 128 -> borde derecho/inferior de la grilla
const M := 24.0                                         # drop_neutral_margin_px por defecto

var _fallos := 0
var _checks := 0

var _iiA: ItemInstance
var _iiB: ItemInstance

var _manip_drop := 0
var _manip_drop_last: ItemInstance = null
var _panel_drop := 0
var _panel_drop_last: ItemInstance = null
var _emis := 0
var _sig_cancelado := 0
var _sig_soltado := 0


func _ready() -> void:
	print("\n===== INVENTORY · C5-B / C5-B2 · intencion de drop + zona neutra =====")

	var actor: Node = InventoryTestActor.crear(inv, authority)
	add_child(actor)
	for d: ItemDefinition in [item_definition_test, item_definition_test]:
		var wi: WorldItemV2 = d.world_scene.instantiate()
		wi.item_instance = ItemInstance.new(d)
		add_child(wi)
		wi._on_interact(Interaction.new(actor, &"usar"))
	await get_tree().process_frame
	var e := inv.get_entries()
	_iiA = e[0].item_instance
	_iiB = e[1].item_instance

	panel.setup(inv, authority)
	panel.abrir()

	panel.manipulator.drop_fuera_solicitado.connect(func(ii: ItemInstance) -> void:
		_manip_drop += 1 ; _manip_drop_last = ii)
	panel.drop_fuera_solicitado.connect(func(ii: ItemInstance) -> void:
		_panel_drop += 1 ; _panel_drop_last = ii)
	panel.cancelado.connect(func(_e: InventoryEntry) -> void: _sig_cancelado += 1)
	panel.soltado.connect(func(_e: InventoryEntry, _ok: bool) -> void: _sig_soltado += 1)
	inv.contenido_cambiado.connect(func() -> void: _emis += 1)

	_t1_descartar_fuera()
	_t2_region_de_drop_bordes()
	_t3_soltar_invalido_dentro_sigue_held()
	_t4_soltar_valido_dentro_intacto()
	_t5_descartar_fuera_sin_held()
	_t6_routing_click_real()
	_t7_zona_neutra_mantiene_held()
	_t8_margen_cero_equivale_a_c5b()

	print("=====================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: C5-B / C5-B2 (intencion de drop + zona neutra) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de C5-B2")
	get_tree().quit(_fallos)


# ── C5-B: la intencion ────────────────────────────────────────────
func _t1_descartar_fuera() -> void:
	print("-- 1. item held + descartar_fuera() -> intencion, sin tocar el modelo --")
	var m := panel.manipulator
	_check(m.agarrar_en(_pos_de(_iiA)), "1: agarrar A")
	_check(m.esta_agarrando(), "1: A held")
	var snap := _snap()
	var md0 := _manip_drop ; var pd0 := _panel_drop
	var em0 := _emis ; var c0 := _sig_cancelado ; var s0 := _sig_soltado
	m.descartar_fuera()
	_check(_manip_drop == md0 + 1, "1: manipulator emitio drop_fuera_solicitado EXACTAMENTE 1 vez")
	_check(_manip_drop_last == _iiA, "1: con la MISMA referencia ItemInstance (A)")
	_check(_panel_drop == pd0 + 1 and _panel_drop_last == _iiA, "1: InventoryPanel reenvio 1 vez, misma referencia")
	_check(not m.esta_agarrando(), "1: el InventoryManipulator YA NO esta held")
	_check(inv.has_item(_iiA), "1: A SIGUE en el InventoryV2")
	_check(_igual(snap), "1: modelo identico")
	_check(_emis == em0 and _sig_cancelado == c0 and _sig_soltado == s0, "1: sin contenido_cambiado / cancelado / soltado")


# ── C5-B2: geometria de las tres regiones, en pixeles ────────────
func _t2_region_de_drop_bordes() -> void:
	print("-- 2. _region_de_drop: grilla / zona neutra / exterior (grilla 128px, margen 24) --")
	var m := panel.manipulator
	var G := InventoryManipulator.RegionDrop.GRILLA
	var N := InventoryManipulator.RegionDrop.ZONA_NEUTRA
	var X := InventoryManipulator.RegionDrop.EXTERIOR

	# DENTRO
	_check(m._region_de_drop(Vector2(64, 64)) == G, "2: centro -> GRILLA")
	_check(m._region_de_drop(Vector2(0, 0)) == G, "2: (0,0) esquina sup-izq -> GRILLA")
	_check(m._region_de_drop(Vector2(W - 1, W - 1)) == G, "2: (127,127) ultimo pixel -> GRILLA")

	# BORDE DERECHO (x), y = 64
	_check(m._region_de_drop(Vector2(W, 64)) == N, "2: x=128 (borde exacto) -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(W + 1, 64)) == N, "2: x=129 (1px afuera) -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(W + M / 2.0, 64)) == N, "2: x=140 (medio margen) -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(W + M - 1, 64)) == N, "2: x=151 (margen-1) -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(W + M, 64)) == X, "2: x=152 (== margen exacto) -> EXTERIOR (Rect2.has_point excl. der.)")
	_check(m._region_de_drop(Vector2(W + M + 1, 64)) == X, "2: x=153 (margen+1) -> EXTERIOR")
	_check(m._region_de_drop(Vector2(500, 64)) == X, "2: x=500 (lejos) -> EXTERIOR")

	# BORDE IZQUIERDO (x), y = 64
	_check(m._region_de_drop(Vector2(-1, 64)) == N, "2: x=-1 -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(-M / 2.0, 64)) == N, "2: x=-12 (medio margen) -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(-M, 64)) == N, "2: x=-24 (== -margen exacto) -> ZONA_NEUTRA (incl. sup-izq)")
	_check(m._region_de_drop(Vector2(-M - 1, 64)) == X, "2: x=-25 -> EXTERIOR")

	# BORDE SUPERIOR (y), x = 64
	_check(m._region_de_drop(Vector2(64, -1)) == N, "2: y=-1 -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(64, -M)) == N, "2: y=-24 -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(64, -M - 1)) == X, "2: y=-25 -> EXTERIOR")

	# BORDE INFERIOR (y), x = 64
	_check(m._region_de_drop(Vector2(64, W)) == N, "2: y=128 (borde exacto) -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(64, W + M - 1)) == N, "2: y=151 -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(64, W + M)) == X, "2: y=152 -> EXTERIOR")

	# ESQUINA (fuera en ambos ejes pero dentro del anillo)
	_check(m._region_de_drop(Vector2(W + 5, W + 5)) == N, "2: (133,133) esquina en el anillo -> ZONA_NEUTRA")
	_check(m._region_de_drop(Vector2(W + M, W + M)) == X, "2: (152,152) esquina en el limite -> EXTERIOR")


# ── C5-B regresion: soltar() dentro no cambia de significado ─────
func _t3_soltar_invalido_dentro_sigue_held() -> void:
	print("-- 3. held + soltar() destino invalido DENTRO -> NO drop, sigue held --")
	var m := panel.manipulator
	_check(m.agarrar_en(_pos_de(_iiA)), "3: agarrar A")
	m.mover_hover_a(Vector2i(2, 0))   # celda ocupada por B
	var md0 := _manip_drop
	_check(not m.soltar(), "3: soltar() -> false (reubicacion rechazada)")
	_check(m.esta_agarrando(), "3: A SIGUE held")
	_check(_manip_drop == md0, "3: NO se emitio drop_fuera_solicitado")
	m.cancelar()


func _t4_soltar_valido_dentro_intacto() -> void:
	print("-- 4. held + soltar() valido DENTRO -> comportamiento existente intacto --")
	var m := panel.manipulator
	_check(m.agarrar_en(_pos_de(_iiA)), "4: agarrar A")
	m.mover_hover_a(Vector2i(0, 2))
	var md0 := _manip_drop ; var emis0 := _emis
	_check(m.soltar(), "4: soltar() -> true")
	_check(_pos_de(_iiA) == Vector2i(0, 2), "4: A se reubico a (0,2)")
	_check(_emis == emis0 + 1 and _manip_drop == md0, "4: contenido_cambiado 1 vez, sin drop")
	authority.solicitar_reubicacion(_iiA, inv, Vector2i(0, 0), false)


func _t5_descartar_fuera_sin_held() -> void:
	print("-- 5. descartar_fuera() sin held -> no-op --")
	var m := panel.manipulator
	var md0 := _manip_drop ; var em0 := _emis
	m.descartar_fuera()
	_check(_manip_drop == md0 and _emis == em0 and not m.esta_agarrando(), "5: sin señal, sin cambios")


func _t6_routing_click_real() -> void:
	print("-- 6. _unhandled_input(click) con held: rutea segun _region_de_drop del cursor real --")
	var m := panel.manipulator
	var view: InventoryGridView = panel.grid_view
	_check(m.esta_activo(), "6: (setup) manipulator activo")
	_check(m.agarrar_en(_pos_de(_iiA)), "6: agarrar A")
	var reg = m._region_de_drop(view.get_local_mouse_position())
	var md0 := _manip_drop ; var s0 := _sig_soltado
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	m._unhandled_input(ev)
	match reg:
		InventoryManipulator.RegionDrop.EXTERIOR:
			_check(_manip_drop == md0 + 1 and not m.esta_agarrando(), "6: cursor EXTERIOR -> descartar_fuera, held resuelto")
		InventoryManipulator.RegionDrop.ZONA_NEUTRA:
			_check(_manip_drop == md0 and m.esta_agarrando(), "6: cursor ZONA_NEUTRA -> NO-OP, sigue held")
			m.cancelar()
		InventoryManipulator.RegionDrop.GRILLA:
			_check(_sig_soltado == s0 + 1, "6: cursor GRILLA -> soltar()")
	_check(inv.has_item(_iiA), "6: A sigue en el inventario (nadie consume la intencion)")


# ── C5-B2: el caso central — held sigue held en la zona neutra ───
func _t7_zona_neutra_mantiene_held() -> void:
	print("-- 7. click en ZONA NEUTRA con item held: NO-OP absoluto, el drag NO se interrumpe --")
	var m := panel.manipulator
	_check(m.agarrar_en(_pos_de(_iiA)), "7: (1-2) agarrar A")
	var ref := m.item_agarrado()
	var snap := _snap()
	var md0 := _manip_drop ; var pd0 := _panel_drop
	var s0 := _sig_soltado ; var c0 := _sig_cancelado ; var em0 := _emis

	# 3. "click" en la zona neutra (a medio margen del borde derecho)
	m._resolver_click_held(Vector2(W + M / 2.0, 64))

	# 4.
	_check(m.esta_agarrando(), "7: (4) esta_agarrando() == true")
	_check(m.item_agarrado() == ref and ref == _iiA, "7: (4) item_agarrado() == MISMA referencia ItemInstance")
	# 5-6.
	_check(_igual(snap), "7: (5-6) modelo identico: entry conserva posicion y rotacion")
	_check(inv.has_item(_iiA), "7: (6) A sigue bajo custodia del inventario")
	# 7-10.
	_check(_manip_drop == md0 and _panel_drop == pd0, "7: (7) drop_fuera_solicitado emitido 0 veces")
	_check(_sig_soltado == s0, "7: (8) 'soltado' emitido 0 veces")
	_check(_sig_cancelado == c0, "7: (9) 'cancelado' emitido 0 veces")
	_check(_emis == em0, "7: (10) 'contenido_cambiado' emitido 0 veces")

	# repetir el click en la zona neutra -> sigue held (el drag no se rompe)
	m._resolver_click_held(Vector2(-M / 2.0, 64))   # otro borde
	_check(m.esta_agarrando() and m.item_agarrado() == ref, "7: 2do click en zona neutra (otro borde) -> sigue held")

	# 11-14. mover el MISMO held mas alla de la zona neutra -> drop
	m._resolver_click_held(Vector2(W + M + 10, 64))
	_check(_manip_drop == md0 + 1, "7: (13) mas alla de la zona neutra -> drop_fuera_solicitado EXACTAMENTE 1 vez")
	_check(_manip_drop_last == _iiA, "7: (13) con la misma referencia")
	_check(not m.esta_agarrando(), "7: (14) held limpio como en C5-B")
	_check(inv.has_item(_iiA) and _igual(snap), "7: el modelo sigue intacto (solo intencion)")


func _t8_margen_cero_equivale_a_c5b() -> void:
	print("-- 8. drop_neutral_margin_px = 0 -> sin zona neutra (semantica C5-B) --")
	var m := panel.manipulator
	var margen_original := m.drop_neutral_margin_px
	m.drop_neutral_margin_px = 0.0
	_check(m._region_de_drop(Vector2(W + 1, 64)) == InventoryManipulator.RegionDrop.EXTERIOR, "8: 1px fuera con margen 0 -> EXTERIOR (no hay zona neutra)")
	_check(m._region_de_drop(Vector2(64, 64)) == InventoryManipulator.RegionDrop.GRILLA, "8: dentro sigue GRILLA")

	_check(m.agarrar_en(_pos_de(_iiA)), "8: agarrar A")
	var md0 := _manip_drop
	m._resolver_click_held(Vector2(W + 1, 64))   # 1px fuera -> con margen 0, drop directo
	_check(_manip_drop == md0 + 1 and not m.esta_agarrando(), "8: click 1px fuera -> descartar_fuera (como C5-B)")
	m.drop_neutral_margin_px = margen_original


# ── instrumentacion ───────────────────────────────────────────────
func _pos_de(ii: ItemInstance) -> Vector2i:
	for e in inv.get_entries():
		if e.item_instance == ii:
			return e.position
	return Vector2i(-99, -99)

func _snap() -> Array:
	var s: Array = []
	for e in inv.get_entries():
		s.append([e.item_instance, e.position, e.rotated])
	return s

func _igual(snap: Array) -> bool:
	var live := inv.get_entries()
	if live.size() != snap.size():
		return false
	for i in range(live.size()):
		var r: Array = snap[i]
		if live[i].item_instance != r[0] or live[i].position != r[1] or live[i].rotated != r[2]:
			return false
	return true


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
