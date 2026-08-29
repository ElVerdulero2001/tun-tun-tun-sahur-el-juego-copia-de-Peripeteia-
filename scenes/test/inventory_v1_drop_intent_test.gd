extends Node3D

## ARNES DE TEST — NO ES PRODUCCION. Inventory · SUA-1.5 C5-B (intencion de drop).
##
## InventoryManipulator debe distinguir "soltar DENTRO del rectangulo de la
## grilla" (reubicacion, comportamiento existente) de "soltar FUERA" (emitir
## la INTENCION drop_fuera_solicitado, sin tocar el modelo ni la autoridad).
## InventoryPanel reenvia esa señal 1:1.
##
## En C5-B NADIE consume la señal (ItemDropper se conecta en C5-C). White-box
## sobre panel.manipulator: consistente con inventory_panel_test.

const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

@export var item_definition_test: ItemDefinition        # 2x1 can_rotate
@export var item_definition_no_rota: ItemDefinition     # 2x1 can_rotate = false

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv                    # 4x4
@onready var panel: InventoryPanel = $CanvasLayer/InventoryPanel

var _fallos := 0
var _checks := 0

var _iiA: ItemInstance
var _iiB: ItemInstance

# spies
var _manip_drop := 0
var _manip_drop_last: ItemInstance = null
var _panel_drop := 0
var _panel_drop_last: ItemInstance = null
var _emis := 0
var _sig_cancelado := 0
var _sig_soltado := 0


func _ready() -> void:
	print("\n===== INVENTORY · C5-B · intencion de drop (drop_fuera_solicitado) =====")

	# siembra por la ruta real: A@(0,0) 2x1, B@(2,0) 2x1
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
	_t2_geometria()
	_t3_soltar_invalido_dentro_sigue_held()
	_t4_soltar_valido_dentro_intacto()
	_t5_descartar_fuera_sin_held()
	_t6_routing_click_fuera()

	print("=====================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: C5-B (intencion de drop) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de C5-B")
	get_tree().quit(_fallos)


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
	_check(_panel_drop == pd0 + 1, "1: InventoryPanel reenvio EXACTAMENTE 1 vez")
	_check(_panel_drop_last == _iiA, "1: el panel reenvia la MISMA referencia")
	_check(not m.esta_agarrando(), "1: el InventoryManipulator YA NO esta held")
	_check(inv.has_item(_iiA), "1: A SIGUE en el InventoryV2 (C5-B no lo saca)")
	_check(_igual(snap), "1: modelo identico (posicion/rotacion sin cambios)")
	_check(_emis == em0, "1: NO se emitio contenido_cambiado por la intencion")
	_check(_sig_cancelado == c0, "1: NO se emitio 'cancelado'")
	_check(_sig_soltado == s0, "1: NO se emitio 'soltado'")


func _t2_geometria() -> void:
	print("-- 2. _celda_dentro_de_la_grilla (grilla 4x4) --")
	var m := panel.manipulator
	_check(m._celda_dentro_de_la_grilla(Vector2i(0, 0)), "2: (0,0) DENTRO")
	_check(m._celda_dentro_de_la_grilla(Vector2i(3, 3)), "2: (3,3) DENTRO (ultima celda)")
	_check(not m._celda_dentro_de_la_grilla(Vector2i(4, 0)), "2: (4,0) FUERA (x == grid_width)")
	_check(not m._celda_dentro_de_la_grilla(Vector2i(0, 4)), "2: (0,4) FUERA (y == grid_height)")
	_check(not m._celda_dentro_de_la_grilla(Vector2i(-1, 2)), "2: (-1,2) FUERA (x < 0)")
	_check(not m._celda_dentro_de_la_grilla(Vector2i(2, -1)), "2: (2,-1) FUERA (y < 0)")


func _t3_soltar_invalido_dentro_sigue_held() -> void:
	print("-- 3. held + soltar() con destino invalido DENTRO de la grilla -> NO drop, sigue held --")
	var m := panel.manipulator
	_check(m.agarrar_en(_pos_de(_iiA)), "3: agarrar A")
	m.mover_hover_a(Vector2i(2, 0))   # celda ocupada por B -> reubicacion invalida
	var md0 := _manip_drop ; var pd0 := _panel_drop
	var r: bool = m.soltar()
	_check(not r, "3: soltar() -> false (reubicacion rechazada)")
	_check(m.esta_agarrando(), "3: A SIGUE held")
	_check(_manip_drop == md0 and _panel_drop == pd0, "3: NO se emitio drop_fuera_solicitado")
	m.cancelar()   # limpieza


func _t4_soltar_valido_dentro_intacto() -> void:
	print("-- 4. held + soltar() valido DENTRO -> comportamiento existente intacto, NO drop --")
	var m := panel.manipulator
	var pos0 := _pos_de(_iiA)
	_check(m.agarrar_en(pos0), "4: agarrar A")
	m.mover_hover_a(Vector2i(0, 2))   # celda libre
	var md0 := _manip_drop
	var emis0 := _emis
	var r: bool = m.soltar()
	_check(r, "4: soltar() -> true (reubicacion aplicada)")
	_check(_pos_de(_iiA) == Vector2i(0, 2), "4: A se reubico a (0,2)")
	_check(_emis == emis0 + 1, "4: contenido_cambiado 1 vez (reubicacion real)")
	_check(_manip_drop == md0, "4: NO se emitio drop_fuera_solicitado")
	authority.solicitar_reubicacion(_iiA, inv, Vector2i(0, 0), false)  # restaurar


func _t5_descartar_fuera_sin_held() -> void:
	print("-- 5. descartar_fuera() sin item held -> no-op, sin señal --")
	var m := panel.manipulator
	_check(not m.esta_agarrando(), "5: (setup) nada held")
	var md0 := _manip_drop ; var pd0 := _panel_drop ; var em0 := _emis
	m.descartar_fuera()
	_check(_manip_drop == md0 and _panel_drop == pd0, "5: no se emitio drop_fuera_solicitado")
	_check(_emis == em0 and not m.esta_agarrando(), "5: sin cambios")


func _t6_routing_click_fuera() -> void:
	print("-- 6. routing: click con item held y cursor FUERA de la grilla (headless) --")
	var m := panel.manipulator
	_check(m.esta_activo() and m.is_processing_unhandled_input(), "6: (setup) manipulator activo")
	_check(m.agarrar_en(_pos_de(_iiA)), "6: agarrar A")
	var md0 := _manip_drop
	var s0 := _sig_soltado
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	m._unhandled_input(ev)
	# En headless el cursor cae fuera del rectangulo de la grilla -> descartar_fuera.
	_check(_manip_drop == md0 + 1, "6: el click ruteo a descartar_fuera (drop_fuera_solicitado +1)")
	_check(_sig_soltado == s0, "6: NO se llamo soltar() (sin 'soltado')")
	_check(not m.esta_agarrando(), "6: held resuelto")
	_check(inv.has_item(_iiA), "6: A sigue en el inventario (solo intencion)")


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
