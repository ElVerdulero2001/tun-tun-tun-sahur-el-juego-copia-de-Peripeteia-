extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory · Batch C1 (deuda D5).
##
## Verifica InventoryPanel como composición PURA de InventoryGridView +
## InventoryManipulator (APIs públicas existentes, cero cambio de comportamiento
## en el modelo):
##
##  1. arranca cerrado, input inactivo; cell_size del .tscn aplicado;
##  2. abrir() antes de setup() -> no-op;
##  3. setup() + abrir() -> visible + input activo + vista cableada;
##     3b. cambiar cell_size después de _ready() se propaga a grid_view;
##  4. cerrar() -> input inactivo + oculto (guard anti bug 15.2);
##  5. cerrar() con un item held -> cancela sin mutar modelo ni custodia;
##  6. las 5 señales del manipulator se reenvían 1:1 (exactamente una vez);
##  7. setup() repetido no duplica conexiones de señales;
##  8. abrir() repetido es idempotente y NO cancela un held;
##  9. reubicación end-to-end sigue pasando por LocalAuthority.
##
## Inventario poblado SOLO por la ruta V0. NO migra ningún test existente.

@export var item_definition_test: ItemDefinition        # 2x1 can_rotate = true
@export var item_definition_no_rota: ItemDefinition     # 2x1 can_rotate = false

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv                    # 4x4
@onready var mundo: Node3D = $Mundo
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo
@onready var panel: InventoryPanel = $CanvasLayer/InventoryPanel

var _fallos := 0
var _checks := 0

var _iiA: ItemInstance
var _iiB: ItemInstance
var _iiC: ItemInstance

var _emis_inv := 0
var _sig_agarrado := 0
var _sig_soltado := 0
var _sig_soltado_ok := 0
var _sig_soltado_fail := 0
var _sig_preview := 0
var _sig_cancelado := 0
var _sig_rot_rechazada := 0


func _ready() -> void:
	print("\n===== INVENTORY · BATCH C1 · InventoryPanel (composición) =====")

	panel.agarrado.connect(_on_panel_agarrado)
	panel.soltado.connect(_on_panel_soltado)
	panel.preview_cambiado.connect(_on_panel_preview)
	panel.cancelado.connect(_on_panel_cancelado)
	panel.rotacion_rechazada.connect(_on_panel_rot_rechazada)

	var e := _sembrar()                # A@(0,0) 2x1, B@(2,0) 2x1, C@(0,1) 2x1 norota
	_iiA = e[0].item_instance
	_iiB = e[1].item_instance
	_iiC = e[2].item_instance
	inv.contenido_cambiado.connect(func() -> void: _emis_inv += 1)
	await get_tree().process_frame     # asentar los queue_free de la siembra

	_t1_arranca_cerrado()
	_t2_abrir_antes_de_setup()
	_t3_setup_y_abrir()
	_t4_cerrar_desactiva_input()
	_t5_cerrar_con_held()
	_t6_senales_reenviadas()
	_t7_setup_repetido_no_duplica()
	_t8_abrir_idempotente_no_cancela_held()
	_t9_reubicacion_end_to_end()

	print("=============================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: BATCH C1 (InventoryPanel) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de InventoryPanel")
	get_tree().quit(_fallos)


func _sembrar() -> Array[InventoryEntry]:
	authority.set_inventory_receptor(inv)
	for d: ItemDefinition in [item_definition_test, item_definition_test, item_definition_no_rota]:
		var wi: WorldItemV2 = d.world_scene.instantiate()
		wi.item_instance = ItemInstance.new(d)
		add_child(wi)
		wi.global_position = punto_spawn.global_position
		wi.setup(authority)
		var ok: bool = wi._on_interact(Interaction.new(self, &"usar"))
		_check(ok, "siembra: pickup de %s" % d.id)
	return inv.get_entries()


# ── Spies de las señales reenviadas por el panel ───────────────────
func _on_panel_agarrado(_entry: InventoryEntry) -> void:
	_sig_agarrado += 1

func _on_panel_soltado(_entry: InventoryEntry, exito: bool) -> void:
	_sig_soltado += 1
	if exito:
		_sig_soltado_ok += 1
	else:
		_sig_soltado_fail += 1

func _on_panel_preview() -> void:
	_sig_preview += 1

func _on_panel_cancelado(_entry: InventoryEntry) -> void:
	_sig_cancelado += 1

func _on_panel_rot_rechazada(_entry: InventoryEntry) -> void:
	_sig_rot_rechazada += 1


# ── Instrumentación ───────────────────────────────────────────────
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

func _custodia(ii: ItemInstance) -> Vector2i:
	var w := 0
	var pila: Array[Node] = [get_tree().root]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is WorldItemV2 and not n.is_queued_for_deletion() and (n as WorldItemV2).item_instance == ii:
			w += 1
		pila.append_array(n.get_children())
	var i := 0
	for e in inv.get_entries():
		if e.item_instance == ii:
			i += 1
	return Vector2i(w, i)


# ── Tests ─────────────────────────────────────────────────────────

func _t1_arranca_cerrado() -> void:
	print("-- 1. arranca cerrado, input inactivo --")
	_check(not panel.esta_configurado(), "1: no configurado")
	_check(not panel.esta_abierto(), "1: no abierto")
	_check(not panel.visible, "1: panel.visible == false")
	_check(not panel.manipulator.esta_activo(), "1: manipulator inactivo")
	_check(not panel.manipulator.is_processing_unhandled_input(), "1: manipulator no procesa unhandled_input")
	_check(panel.grid_view.cell_size == 32, "1: cell_size del .tscn (32) aplicado a grid_view en _ready")


func _t2_abrir_antes_de_setup() -> void:
	print("-- 2. abrir() antes de setup() -> no-op --")
	panel.abrir()
	_check(not panel.esta_abierto(), "2: sigue cerrado")
	_check(not panel.visible, "2: sigue invisible")
	_check(not panel.manipulator.esta_activo(), "2: manipulator sigue inactivo")


func _t3_setup_y_abrir() -> void:
	print("-- 3. setup() + abrir() --")
	panel.setup(inv, authority)
	_check(panel.esta_configurado(), "3: configurado")
	_check(panel.grid_view.get_inventory() == inv, "3: vista cableada al inventario")

	# 3b. proxy real de cell_size (post-_ready)
	panel.cell_size = 40
	_check(panel.grid_view.cell_size == 40, "3b: cambiar cell_size post-_ready se propaga a grid_view")

	panel.abrir()
	_check(panel.esta_abierto(), "3: abierto")
	_check(panel.visible, "3: visible")
	_check(panel.manipulator.esta_activo(), "3: manipulator activo")
	_check(panel.manipulator.is_processing_unhandled_input(), "3: manipulator procesa unhandled_input")


func _t4_cerrar_desactiva_input() -> void:
	print("-- 4. cerrar() desactiva input --")
	panel.cerrar()
	_check(not panel.esta_abierto(), "4: no abierto")
	_check(not panel.visible, "4: invisible")
	_check(not panel.manipulator.esta_activo(), "4: manipulator inactivo")
	_check(not panel.manipulator.is_processing_unhandled_input(), "4: NO procesa unhandled_input (guard anti bug 15.2)")


func _t5_cerrar_con_held() -> void:
	print("-- 5. cerrar() con un item held -> cancela sin mutar --")
	panel.abrir()
	_check(panel.manipulator.agarrar_en(_pos_de(_iiA)), "5: agarrar A")
	_check(panel.manipulator.esta_agarrando(), "5: A held")
	var snap := _snap()
	var emis0 := _emis_inv
	var canc0 := _sig_cancelado
	var cust0 := _custodia(_iiA)

	panel.cerrar()

	_check(not panel.manipulator.esta_agarrando(), "5: ya no está held")
	_check(_sig_cancelado == canc0 + 1, "5: el panel reenvió 'cancelado' exactamente 1 vez")
	_check(_igual(snap), "5: modelo idéntico")
	_check(_emis_inv == emis0, "5: contenido_cambiado NO se emitió")
	_check(_custodia(_iiA) == cust0 and _custodia(_iiA) == Vector2i(0, 1), "5: custodia intacta (World=0/Inv=1)")


func _t6_senales_reenviadas() -> void:
	print("-- 6. las 5 señales del manipulator se reenvían 1:1 --")
	panel.abrir()
	var m := panel.manipulator

	var a0 := _sig_agarrado
	_check(m.agarrar_en(_pos_de(_iiA)), "6: agarrar A")
	_check(_sig_agarrado == a0 + 1, "6: 'agarrado' reenviado +1 (%d)" % (_sig_agarrado - a0))

	var p0 := _sig_preview
	m.mover_hover_a(Vector2i(2, 2))
	_check(_sig_preview == p0 + 1, "6: 'preview_cambiado' reenviado +1 (%d)" % (_sig_preview - p0))

	var s0 := _sig_soltado
	var sok0 := _sig_soltado_ok
	_check(m.destino_es_valido(), "6: (2,2) libre -> válido")
	_check(m.soltar(), "6: soltar A en (2,2)")
	_check(_sig_soltado == s0 + 1 and _sig_soltado_ok == sok0 + 1, "6: 'soltado(exito=true)' reenviado +1")

	var rr0 := _sig_rot_rechazada
	_check(m.agarrar_en(_pos_de(_iiC)), "6: agarrar C (can_rotate=false)")
	_check(not m.rotar_tentativo(), "6: rotar C -> false")
	_check(_sig_rot_rechazada == rr0 + 1, "6: 'rotacion_rechazada' reenviado +1 (%d)" % (_sig_rot_rechazada - rr0))

	var c0 := _sig_cancelado
	m.cancelar()
	_check(_sig_cancelado == c0 + 1, "6: 'cancelado' reenviado +1 (%d)" % (_sig_cancelado - c0))

	# restaurar A a (0,0)
	authority.solicitar_reubicacion(_iiA, inv, Vector2i(0, 0), false)
	_check(_pos_de(_iiA) == Vector2i(0, 0), "6: A restaurada a (0,0)")


func _t7_setup_repetido_no_duplica() -> void:
	print("-- 7. setup() repetido no duplica conexiones de señales --")
	panel.cerrar()
	panel.setup(inv, authority)        # 2do
	panel.setup(inv, authority)        # 3ro
	panel.abrir()
	var a0 := _sig_agarrado
	_check(panel.manipulator.agarrar_en(_pos_de(_iiA)), "7: agarrar A")
	_check(_sig_agarrado == a0 + 1, "7: 'agarrado' se reenvió EXACTAMENTE 1 vez (%d) — sin doble-connect" % (_sig_agarrado - a0))
	panel.manipulator.cancelar()


func _t8_abrir_idempotente_no_cancela_held() -> void:
	print("-- 8. abrir() repetido es idempotente y NO cancela held --")
	panel.cerrar()
	panel.abrir()
	var m := panel.manipulator
	_check(m.agarrar_en(_pos_de(_iiA)), "8: agarrar A")
	_check(m.esta_agarrando(), "8: A held")
	var canc0 := _sig_cancelado
	var held0 := m.item_agarrado()

	panel.abrir()                     # 2da vez, ya abierto

	_check(panel.esta_abierto(), "8: sigue abierto")
	_check(m.esta_agarrando(), "8: A SIGUE held (abrir() no re-llamó activar())")
	_check(m.item_agarrado() == held0, "8: es el mismo item held")
	_check(_sig_cancelado == canc0, "8: NO se emitió 'cancelado' (%d)" % (_sig_cancelado - canc0))
	m.cancelar()
	panel.cerrar()


func _t9_reubicacion_end_to_end() -> void:
	print("-- 9. reubicación end-to-end sigue pasando por LocalAuthority --")
	panel.abrir()
	var m := panel.manipulator
	var pos0 := _pos_de(_iiA)
	var emis0 := _emis_inv

	_check(m.agarrar_en(pos0), "9: agarrar A en %s" % pos0)
	m.mover_hover_a(Vector2i(2, 2))
	_check(m.destino_es_valido(), "9: (2,2) válido")
	_check(m.soltar(), "9: soltar -> true")
	_check(_pos_de(_iiA) == Vector2i(2, 2), "9: A quedó en (2,2) (reubicación aplicada por la autoridad)")
	_check(_emis_inv == emis0 + 1, "9: contenido_cambiado emitido exactamente 1 vez")
	_check(inv.has_item(_iiA), "9: A sigue bajo custodia")
	_check(_custodia(_iiA) == Vector2i(0, 1), "9: custodia XOR intacta (World=0/Inv=1)")

	authority.solicitar_reubicacion(_iiA, inv, Vector2i(0, 0), false)  # limpieza
	panel.cerrar()


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
