extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory V1 · Paso 5 (headless).
##
## Prueba la MÁQUINA DE ESTADOS de InventoryManipulator llamando sus
## transiciones públicas directamente (agarrar_en / mover_hover_a /
## rotar_tentativo / soltar / cancelar). No simula input de píxeles ni
## dibujo: eso se prueba a mano con inventory_v1_manual_test.tscn.
##
## Verifica: preview no muta el modelo; drop real pasa por LocalAuthority;
## drop fallido -> sigue held + modelo idéntico; cancelar/cerrar -> idéntico.
##
## get_entries()/entry_en_celda() devuelven SNAPSHOTS: la identidad se
## chequea por ItemInstance y el estado actual se re-consulta con _entry_de().

@export var item_definition_test: ItemDefinition        # 2x1 can_rotate = true
@export var item_definition_no_rota: ItemDefinition     # 2x1 can_rotate = false

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv                    # 4x4
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo
@onready var view: InventoryGridView = $CanvasLayer/InventoryGridView
@onready var manip: InventoryManipulator = $CanvasLayer/InventoryGridView/InventoryManipulator

var _fallos := 0
var _checks := 0
var _emis := 0
var _sig_agarrado := 0
var _sig_soltado_ok := 0
var _sig_soltado_fail := 0
var _sig_cancelado := 0
var _sig_rot_rechazada := 0


func _ready() -> void:
	print("\n===== INVENTORY V1 · PASO 5 · MÁQUINA DE ESTADOS DEL MANIPULATOR =====")

	var entries := _sembrar()          # A (rota) -> (0,0) ; C (no-rota) -> (2,0)
	var iiA: ItemInstance = entries[0].item_instance
	var iiC: ItemInstance = entries[1].item_instance

	inv.contenido_cambiado.connect(func() -> void: _emis += 1)
	manip.agarrado.connect(func(_e) -> void: _sig_agarrado += 1)
	manip.soltado.connect(_on_soltado_spy)
	manip.cancelado.connect(func(_e) -> void: _sig_cancelado += 1)
	manip.rotacion_rechazada.connect(func(_e) -> void: _sig_rot_rechazada += 1)

	view.set_inventory(inv)
	manip.setup(view, authority)

	_t1_estado_inicial()
	_t2_agarrar_celda_vacia()
	_t3_agarrar_item(iiA)
	_t4_preview_no_muta(iiA)
	_t5_rotacion_tentativa_no_muta(iiA)
	_t6_soltar_valido(iiA)
	_t7_rotar_no_permitido(iiC)
	_t8_soltar_solapando(iiC)
	_t9_soltar_fuera_de_limites()
	_t10_cancelar_con_held()
	_t11_cerrar_ui_con_held(iiA)

	print("====================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: PASO 5 OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos del Paso 5 de V1")
	get_tree().quit(_fallos)


func _sembrar() -> Array[InventoryEntry]:
	authority.set_inventory_receptor(inv)
	for d in [item_definition_test, item_definition_no_rota]:
		var wi: WorldItemV2 = d.world_scene.instantiate()
		wi.item_instance = ItemInstance.new(d)
		add_child(wi)
		wi.global_position = punto_spawn.global_position
		wi.setup(authority)
		var ok: bool = wi._on_interact(Interaction.new(self, &"usar"))
		_check(ok, "siembra: pickup de %s" % d.id)
	return inv.get_entries()


## Snapshot ACTUAL de la entry de `ii` (o null). El estado del modelo se
## re-consulta siempre por acá, nunca desde un snapshot viejo.
func _entry_de(ii: ItemInstance) -> InventoryEntry:
	for e in inv.get_entries():
		if e.item_instance == ii:
			return e
	return null


func _t1_estado_inicial() -> void:
	print("-- T1 estado inicial --")
	_check(not manip.esta_agarrando(), "manip no está agarrando nada")
	_check(manip.entry_agarrada() == null, "entry_agarrada() == null")
	_check(manip.item_agarrado() == null, "item_agarrado() == null")


func _t2_agarrar_celda_vacia() -> void:
	print("-- T2 agarrar celda vacía --")
	var r: bool = manip.agarrar_en(Vector2i(3, 3))
	_check(not r, "agarrar_en(celda vacía) -> false")
	_check(not manip.esta_agarrando(), "sigue sin agarrar")


func _t3_agarrar_item(iiA: ItemInstance) -> void:
	print("-- T3 agarrar A en (0,0) --")
	var pos0 := _entry_de(iiA).position
	var rot0 := _entry_de(iiA).rotated
	var r: bool = manip.agarrar_en(Vector2i(0, 0))
	_check(r, "agarrar_en((0,0)) -> true")
	_check(manip.esta_agarrando() and manip.item_agarrado() == iiA, "held == A (por ItemInstance)")
	_check(manip.rotacion_tentativa() == rot0, "rotacion_tentativa arranca en el valor real (%s)" % rot0)
	_check(_entry_de(iiA).position == pos0 and _entry_de(iiA).rotated == rot0, "T3: modelo NO cambió al agarrar")
	_check(_emis == 0, "T3: contenido_cambiado no se emitió (%d)" % _emis)
	_check(_sig_agarrado == 1, "señal agarrado emitida 1 vez")


func _t4_preview_no_muta(iiA: ItemInstance) -> void:
	print("-- T4 mover el hover (preview) no muta el modelo --")
	var pos0 := _entry_de(iiA).position
	var rot0 := _entry_de(iiA).rotated
	manip.mover_hover_a(Vector2i(2, 2))
	_check(manip.celda_destino_tentativa() == Vector2i(2, 2), "destino tentativo (2,2) (offset 0)")
	_check(manip.destino_es_valido(), "(2,2) libre -> destino válido")
	manip.mover_hover_a(Vector2i(0, 0))
	_check(manip.destino_es_valido(), "(0,0) excluyéndose a sí misma -> válido")
	manip.mover_hover_a(Vector2i(3, 0))
	_check(not manip.destino_es_valido(), "(3,0) footprint 2x1 -> fuera de límites -> inválido")
	_check(_entry_de(iiA).position == pos0 and _entry_de(iiA).rotated == rot0, "T4: modelo NO cambió durante el preview")
	_check(_emis == 0, "T4: contenido_cambiado no se emitió (%d)" % _emis)


func _t5_rotacion_tentativa_no_muta(iiA: ItemInstance) -> void:
	print("-- T5 rotación tentativa no toca entry.rotated real --")
	var rot_real := _entry_de(iiA).rotated
	var rot_tent := manip.rotacion_tentativa()
	var r: bool = manip.rotar_tentativo()
	_check(r, "rotar_tentativo() en A (can_rotate=true) -> true")
	_check(manip.rotacion_tentativa() == not rot_tent, "rotacion_tentativa se invirtió")
	_check(_entry_de(iiA).rotated == rot_real, "entry.rotated REAL sin cambios (%s)" % rot_real)
	_check(_emis == 0, "T5: contenido_cambiado no se emitió (%d)" % _emis)


func _t6_soltar_valido(iiA: ItemInstance) -> void:
	print("-- T6 soltar en posición válida (rotado) --")
	# rotacion_tentativa quedó en true tras T5; llevar el hover a (0,2):
	# footprint rotado 1x2 -> celdas (0,2),(0,3), libres.
	manip.mover_hover_a(Vector2i(0, 2))
	_check(manip.destino_es_valido(), "destino (0,2) rotado 1x2 -> válido")
	var id0 := iiA.instance_id
	var r: bool = manip.soltar()
	_check(r, "soltar() -> true")
	_check(not manip.esta_agarrando(), "ya no está agarrando")
	var e := _entry_de(iiA)
	_check(e != null and e.position == Vector2i(0, 2) and e.rotated, "entryA quedó en (0,2) ROTADA")
	_check(inv.has_item(iiA), "A sigue en el inventario")
	_check(iiA.instance_id == id0, "mismo instance_id (#%d)" % id0)
	_check(inv.get_entries().size() == 2, "_entries.size() == 2")
	_check(_emis == 1, "contenido_cambiado emitido EXACTAMENTE 1 vez (%d)" % _emis)
	_check(_sig_soltado_ok == 1, "señal soltado(exito=true) 1 vez")
	# INV-09 (misma InventoryEntry viva) -> white-box:
	_check(_reubico_in_place_white_box(iiA), "INV-09 white-box: la MISMA InventoryEntry viva se reubicó in-place")


func _t7_rotar_no_permitido(iiC: ItemInstance) -> void:
	print("-- T7 rotar un ítem con can_rotate=false --")
	_check(manip.agarrar_en(Vector2i(2, 0)), "agarrar C en (2,0)")
	var rot_tent := manip.rotacion_tentativa()
	var r: bool = manip.rotar_tentativo()
	_check(not r, "rotar_tentativo() en C -> false")
	_check(manip.rotacion_tentativa() == rot_tent, "rotacion_tentativa sin cambios")
	_check(_entry_de(iiC).rotated == false, "entry.rotated real de C intacto")
	_check(_sig_rot_rechazada == 1, "señal rotacion_rechazada 1 vez")


func _t8_soltar_solapando(iiC: ItemInstance) -> void:
	print("-- T8 soltar C solapando A (A quedó en (0,2) tras T6) --")
	var snap := _snap()
	var emis0 := _emis
	# C sigue held desde T7. Destino (0,2): footprint 2x1 -> (0,2),(1,2). (0,2) es de A.
	manip.mover_hover_a(Vector2i(0, 2))
	_check(not manip.destino_es_valido(), "destino (0,2) solapa a A -> inválido")
	var r: bool = manip.soltar()
	_check(not r, "soltar() -> false")
	_check(manip.esta_agarrando() and manip.item_agarrado() == iiC, "C SIGUE held tras el drop fallido")
	_check(_igual(snap), "T8: modelo idéntico")
	_check(_emis == emis0, "T8: sin emisión (%d)" % (_emis - emis0))
	_check(_sig_soltado_fail == 1, "señal soltado(exito=false) 1 vez")


func _t9_soltar_fuera_de_limites() -> void:
	print("-- T9 soltar C fuera de límites --")
	var snap := _snap()
	var emis0 := _emis
	manip.mover_hover_a(Vector2i(3, 0))  # (3,0),(4,0) -> OOB
	_check(not manip.destino_es_valido(), "destino (3,0) 2x1 -> fuera de límites")
	var r: bool = manip.soltar()
	_check(not r, "soltar() -> false")
	_check(manip.esta_agarrando(), "C sigue held")
	_check(_igual(snap), "T9: modelo idéntico")
	_check(_emis == emis0, "T9: sin emisión")


func _t10_cancelar_con_held() -> void:
	print("-- T10 cancelar() con C held --")
	var snap := _snap()
	var emis0 := _emis
	manip.cancelar()
	_check(not manip.esta_agarrando(), "tras cancelar() no está agarrando")
	_check(_igual(snap), "T10: modelo idéntico (C sigue donde estaba)")
	_check(_emis == emis0, "T10: sin emisión")
	_check(_sig_cancelado == 1, "señal cancelado 1 vez")


func _t11_cerrar_ui_con_held(iiA: ItemInstance) -> void:
	print("-- T11 'cerrar UI' con un ítem held: modelo idéntico --")
	_check(manip.agarrar_en(_entry_de(iiA).position), "agarrar A en su celda actual")
	manip.mover_hover_a(Vector2i(2, 1))
	manip.rotar_tentativo()
	var snap := _snap()
	var emis0 := _emis
	manip.cancelar()   # lo que hace el harness al cerrar la UI
	_check(not manip.esta_agarrando(), "no está agarrando")
	_check(_igual(snap), "T11: modelo EXACTAMENTE igual a antes de cerrar")
	_check(_emis == emis0, "T11: sin emisión")


# ── Instrumentación ────────────────────────────────────────────────

func _on_soltado_spy(_entry: InventoryEntry, exito: bool) -> void:
	if exito:
		_sig_soltado_ok += 1
	else:
		_sig_soltado_fail += 1


## White-box de INV-09: comprueba que reubicar in-place NO cambia el objeto
## InventoryEntry vivo en inv._entries.
func _reubico_in_place_white_box(ii: ItemInstance) -> bool:
	var vivo_antes: InventoryEntry = null
	for e in inv._entries:
		if e.item_instance == ii:
			vivo_antes = e
			break
	if vivo_antes == null:
		return false
	var pos_antes := vivo_antes.position
	var rot_antes := vivo_antes.rotated
	authority.solicitar_reubicacion(ii, inv, Vector2i(2, 2), false)
	var vivo_despues: InventoryEntry = null
	for e in inv._entries:
		if e.item_instance == ii:
			vivo_despues = e
			break
	var ok := vivo_despues == vivo_antes and vivo_despues.position == Vector2i(2, 2)
	authority.solicitar_reubicacion(ii, inv, pos_antes, rot_antes)   # restaurar estado exacto
	return ok


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
		if live[i].item_instance != r[0] or live[i].position != r[1] or live[i].rotated != r[2] \
		or live[i].item_instance.instance_id != r[3]:
			return false
	return true


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
