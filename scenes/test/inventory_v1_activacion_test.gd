extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory V1 · Paso 5 (fix de activación).
##
## Con la UI CERRADA el InventoryManipulator debe quedar INERTE: ningún
## clic/mouse/R puede seleccionar, mover, rotar ni soltar. Ocultar el
## CanvasLayer (visible=false) NO frena _input en Godot -> el manipulator
## necesita un estado explícito activar()/desactivar().
##
## Los eventos se sintetizan y se pasan a manip._unhandled_input(...) para
## probar el gate real de input.

@export var item_definition_test: ItemDefinition   # 2x1 can_rotate

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv               # 4x4
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo
@onready var view: InventoryGridView = $CanvasLayer/InventoryGridView
@onready var manip: InventoryManipulator = $CanvasLayer/InventoryGridView/InventoryManipulator

const CELL := 32

var _snap0: Array = []
var _fallos := 0
var _checks := 0
var _emis := 0
var _sig_agarrado := 0
var _sig_cancelado := 0
var _sig_preview := 0
var _sig_soltado := 0
var _sig_rot_rech := 0
var _iiA: ItemInstance


func _entry_de(ii: ItemInstance) -> InventoryEntry:
	for e in inv.get_entries():
		if e.item_instance == ii:
			return e
	return null

func _pos_de(ii: ItemInstance) -> Vector2i:
	var e := _entry_de(ii)
	return e.position if e != null else Vector2i(-99, -99)


func _ready() -> void:
	print("\n===== INVENTORY V1 · PASO 5 · GATE DE ACTIVACIÓN DEL MANIPULATOR =====")

	view.cell_size = CELL
	view.position = Vector2.ZERO
	view.size = Vector2(4 * CELL, 4 * CELL)

	var e := _sembrar()                # A@(0,0) 2x1, B@(2,0) 2x1
	_iiA = e[0].item_instance

	inv.contenido_cambiado.connect(func() -> void: _emis += 1)
	manip.agarrado.connect(func(_x) -> void: _sig_agarrado += 1)
	manip.cancelado.connect(func(_x) -> void: _sig_cancelado += 1)
	manip.preview_cambiado.connect(func() -> void: _sig_preview += 1)
	manip.soltado.connect(func(_x, _o) -> void: _sig_soltado += 1)
	manip.rotacion_rechazada.connect(func(_x) -> void: _sig_rot_rech += 1)

	view.set_inventory(inv)
	manip.setup(view, authority)
	_snap0 = _snap()

	_t0_estado_inicial()
	_t1_cerrado_click_no_selecciona()
	_t2_cerrado_R_no_rota()
	_t3_cerrar_con_held_cancela()
	_t4_cerrado_spam_no_recrea_estado()
	_t5_abrir_empieza_limpio()
	_t6_abierto_interaccion_funciona()
	_t7_secuencias_abrir_cerrar_spam()

	print("====================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: GATE DE ACTIVACIÓN OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos del gate de activación")
	get_tree().quit(_fallos)


func _sembrar() -> Array[InventoryEntry]:
	authority.set_inventory_receptor(inv)
	for i in range(2):
		var wi: WorldItemV2 = item_definition_test.world_scene.instantiate()
		wi.item_instance = ItemInstance.new(item_definition_test)
		add_child(wi)
		wi.global_position = punto_spawn.global_position
		wi.setup(authority)
		var ok: bool = wi._on_interact(Interaction.new(self, &"usar"))
		_check(ok, "siembra: pickup #%d" % (i + 1))
	return inv.get_entries()


# ── Eventos sintéticos ─────────────────────────────────────────────

func _ev_click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = Vector2(CELL / 2.0, CELL / 2.0)   # sobre la celda (0,0), ocupada por A
	return e

func _ev_rotar() -> InputEventAction:
	var e := InputEventAction.new()
	e.action = &"rotar_item"
	e.pressed = true
	e.strength = 1.0
	return e

func _ev_motion() -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = Vector2(3.5 * CELL, 3.5 * CELL)
	return e

func _ev_cancel() -> InputEventAction:
	var e := InputEventAction.new()
	e.action = &"ui_cancel"
	e.pressed = true
	e.strength = 1.0
	return e

func _spam_input_cerrado() -> void:
	for i in range(8):
		manip._unhandled_input(_ev_click())
		manip._unhandled_input(_ev_rotar())
		manip._unhandled_input(_ev_motion())
		manip._unhandled_input(_ev_cancel())


func _snap() -> Array:
	var s: Array = []
	for e in inv.get_entries():
		s.append([e.item_instance, e.position, e.rotated, e.item_instance.instance_id])
	return s

func _igual(snap: Array) -> bool:
	var live := inv.get_entries()
	if live.size() != snap.size():
		return false
	for i in range(live.size()):
		var r: Array = snap[i]
		# get_entries() devuelve snapshots: la identidad de objeto InventoryEntry
		# no es estable entre llamadas -> se compara por item_instance / valores.
		if live[i].item_instance != r[0] or live[i].position != r[1] or live[i].rotated != r[2] \
		or live[i].item_instance.instance_id != r[3]:
			return false
	return true


# ── Tests ──────────────────────────────────────────────────────────

func _t0_estado_inicial() -> void:
	print("-- T0 estado inicial: inactivo hasta abrir --")
	_check(not manip.esta_activo(), "manip arranca INACTIVO")
	_check(not manip.is_processing_unhandled_input(), "no procesa unhandled_input al arrancar")


func _t1_cerrado_click_no_selecciona() -> void:
	print("-- T1 cerrado + click -> no selecciona --")
	# NOTA: en headless no hay mouse real, así que _celda_bajo_mouse() no puede
	# apuntar a una celda concreta. Pero el gate de _unhandled_input es un solo
	# early-return `if not _activo` común a TODOS los eventos: T2 prueba que ese
	# gate funciona (synth R activo -> rota; inactivo -> no). Acá se verifica que
	# con la UI cerrada un click sintético no produce selección ni emisión.
	manip.desactivar()
	_check(not manip.esta_activo() and not manip.is_processing_unhandled_input(),
		"con la UI cerrada el manipulator no procesa input")

	var snap := _snap()
	var em0 := _emis
	var ag0 := _sig_agarrado
	for i in range(6):
		manip._unhandled_input(_ev_click())
	_check(not manip.esta_agarrando(), "T1: click con UI cerrada NO selecciona nada")
	_check(_sig_agarrado == ag0, "T1: no se emitió 'agarrado'")
	_check(_igual(snap) and _emis == em0, "T1: modelo idéntico, sin emisión")


func _t2_cerrado_R_no_rota() -> void:
	print("-- T2 cerrado + R -> no hay rotación tentativa --")
	# prueba mouse-independiente: ACTIVO + held -> synth R SÍ rota tentativamente;
	# INACTIVO -> synth R no hace nada.
	manip.activar()
	_check(manip.agarrar_en(Vector2i(0, 0)), "T2 setup: agarrar A (activo)")
	var t0 := manip.rotacion_tentativa()
	manip._unhandled_input(_ev_rotar())
	_check(manip.rotacion_tentativa() == not t0, "T2: ACTIVO -> synth R invierte rotacion_tentativa (input procesa)")
	manip.desactivar()   # cancela el held

	_check(not manip.esta_activo(), "sigue inactivo")
	var rp0 := _sig_preview
	manip._unhandled_input(_ev_rotar())
	manip._unhandled_input(_ev_rotar())
	_check(manip.rotacion_tentativa() == false, "T2: CERRADO -> rotacion_tentativa sigue false")
	_check(not manip.esta_agarrando(), "T2: nada quedó held")
	_check(_sig_preview == rp0, "T2: CERRADO -> no se emitió 'preview_cambiado'")


func _t3_cerrar_con_held_cancela() -> void:
	print("-- T3 cerrar con un ítem held -> se cancela y queda no-held --")
	manip.activar()
	_check(manip.agarrar_en(Vector2i(0, 0)), "agarrar A (UI abierta)")
	_check(manip.esta_agarrando(), "A held")
	var snap := _snap()
	var em0 := _emis
	var c0 := _sig_cancelado

	manip.desactivar()

	_check(not manip.esta_agarrando(), "T3: tras desactivar, NO held")
	_check(_sig_cancelado == c0 + 1, "T3: se emitió 'cancelado' una vez")
	_check(not manip.esta_activo() and not manip.is_processing_unhandled_input(), "T3: manipulator inerte")
	_check(_pos_de(_iiA) == Vector2i(0, 0) and not _entry_de(_iiA).rotated, "T3: A quedó en su lugar original")
	_check(_igual(snap) and _emis == em0, "T3: modelo idéntico, sin emisión")


func _t4_cerrado_spam_no_recrea_estado() -> void:
	print("-- T4 cerrado + spam de clicks/R/mouse -> no recrea estado transitorio --")
	var snap := _snap()
	var em0 := _emis
	var ag0 := _sig_agarrado
	var so0 := _sig_soltado
	var pr0 := _sig_preview
	var hover0 := manip.celda_hover()

	_spam_input_cerrado()

	_check(not manip.esta_agarrando(), "T4: nada held tras el spam")
	_check(manip.rotacion_tentativa() == false, "T4: sin rotación tentativa")
	_check(manip.celda_hover() == hover0, "T4: _celda_hover no cambió con el spam")
	_check(_sig_agarrado == ag0 and _sig_soltado == so0 and _sig_preview == pr0, "T4: cero señales de interacción")
	_check(_igual(snap) and _emis == em0, "T4: modelo idéntico, sin emisión")


func _t5_abrir_empieza_limpio() -> void:
	print("-- T5 abrir -> empieza limpio --")
	manip.activar()
	_check(manip.esta_activo(), "T5: activo")
	_check(manip.is_processing_unhandled_input(), "T5: procesa input de nuevo")
	_check(not manip.esta_agarrando(), "T5: sin selección")
	_check(manip.rotacion_tentativa() == false, "T5: sin rotación tentativa")
	_check(manip.offset_agarre_actual() == Vector2i.ZERO, "T5: sin offset residual")


func _t6_abierto_interaccion_funciona() -> void:
	print("-- T6 abierto -> la interacción normal vuelve a funcionar --")
	var em0 := _emis
	_check(manip.agarrar_en(Vector2i(0, 0)), "T6: agarrar A funciona")
	manip.mover_hover_a(Vector2i(2, 2))
	_check(manip.destino_es_valido(), "T6: (2,2) libre -> válido")
	_check(manip.soltar(), "T6: soltar en (2,2) funciona")
	_check(_pos_de(_iiA) == Vector2i(2, 2), "T6: A se movió a (2,2)")
	_check(_emis == em0 + 1, "T6: contenido_cambiado emitido 1 vez")
	# y el input sintético vuelve a procesarse (mouse-independiente: R sobre held)
	_check(manip.agarrar_en(Vector2i(2, 2)), "T6: re-agarrar A")
	var t0 := manip.rotacion_tentativa()
	manip._unhandled_input(_ev_rotar())
	_check(manip.rotacion_tentativa() == not t0, "T6: synth R con UI abierta rota tentativamente (input restaurado)")
	manip.cancelar()
	# restaurar A a (0,0) para T7
	authority.solicitar_reubicacion(_iiA, inv, Vector2i(0, 0), false)


func _t7_secuencias_abrir_cerrar_spam() -> void:
	print("-- T7 varias secuencias abrir/cerrar + spam -> nunca se interactúa cerrado --")
	var fallo_gate := false
	for ciclo in range(10):
		manip.desactivar()
		var snap := _snap()
		var em0 := _emis
		_spam_input_cerrado()
		if manip.esta_agarrando() or not _igual(snap) or _emis != em0 or manip.rotacion_tentativa():
			fallo_gate = true
			printerr("  [detalle] ciclo %d: interacción detectada con la UI cerrada" % ciclo)
		manip.activar()
		if not manip.agarrar_en(Vector2i(0, 0)):
			fallo_gate = true
			printerr("  [detalle] ciclo %d: no se pudo agarrar tras abrir" % ciclo)
		manip.cancelar()
	manip.desactivar()
	_check(not fallo_gate, "T7: 10 ciclos abrir/cerrar con spam -> jamás interacción estando cerrado; siempre OK al abrir")
	_check(_igual(_snap0), "T7: modelo intacto al final (== estado sembrado)")


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
