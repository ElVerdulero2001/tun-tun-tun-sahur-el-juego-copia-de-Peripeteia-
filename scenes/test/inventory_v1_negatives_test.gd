extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory V1 · Paso 6.
##
## Suite de aceptación de V1: ejercita el stack completo end-to-end a través
## del InventoryManipulator (vista + manipulator + operación + modelo) y
## verifica los criterios NEGATIVOS N1..N7 del diseño, más las integraciones
## P5 (abrir/cerrar sin mutar) y P6 (una reubicación V1 no rompe el ciclo V0).
##
## Invariantes: INV-09 (misma ItemInstance; "misma InventoryEntry" es
## INTERNA -> ver white-box en inventory_v1_reubicar_test), INV-10 (_entries.size
## constante), INV-11 (sin solapes), INV-12 (abrir/cerrar no muta), INV-13
## (drop rechazado -> modelo idéntico), INV-15 (can_rotate), INV-16 (custodia).
##
## get_entries()/entry_en_celda() devuelven SNAPSHOTS: identidad por
## ItemInstance, estado actual vía _entry_de().

@export var item_definition_test: ItemDefinition        # 2x1 can_rotate = true
@export var item_definition_no_rota: ItemDefinition     # 2x1 can_rotate = false

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv                    # 4x4
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo
@onready var mundo: Node3D = $Mundo
@onready var view: InventoryGridView = $CanvasLayer/InventoryGridView
@onready var manip: InventoryManipulator = $CanvasLayer/InventoryGridView/InventoryManipulator

var _fallos := 0
var _checks := 0
var _emis := 0

var _iiA: ItemInstance
var _iiB: ItemInstance
var _iiC: ItemInstance


func _ready() -> void:
	print("\n===== INVENTORY V1 · PASO 6 · SUITE DE ACEPTACIÓN (N1..N7 + P5/P6) =====")

	var e := _sembrar()                # A@(0,0) rota, B@(2,0) rota, C@(0,1) no-rota
	_iiA = e[0].item_instance
	_iiB = e[1].item_instance
	_iiC = e[2].item_instance

	inv.contenido_cambiado.connect(func() -> void: _emis += 1)
	view.set_inventory(inv)
	manip.setup(view, authority)
	await get_tree().process_frame     # que se asienten los queue_free de la siembra

	_n1_solapamiento()
	_n2_fuera_de_limites()
	_n3_rotar_no_permitido()
	_n4_rotar_a_posicion_invalida()
	_n5_cerrar_con_held()
	_n6_invariante_custodia()
	_n7_stress()
	_p5_abrir_cerrar_identico()
	await _p6_puente_v0()

	print("=====================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: PASO 6 OK  (V1 aceptada)")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron criterios de aceptación de V1")
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


## Snapshot ACTUAL de la entry de `ii`, o null.
func _entry_de(ii: ItemInstance) -> InventoryEntry:
	for e in inv.get_entries():
		if e.item_instance == ii:
			return e
	return null

func _pos_de(ii: ItemInstance) -> Vector2i:
	var e := _entry_de(ii)
	return e.position if e != null else Vector2i(-99, -99)


# ── N1: drop solapando otra entry -> rechazado, modelo idéntico, sigue held ──
func _n1_solapamiento() -> void:
	print("-- N1 · drop solapando otra entry --")
	_check(manip.agarrar_en(_pos_de(_iiA)), "agarrar A")
	var snap := _snap()
	var emis0 := _emis
	manip.mover_hover_a(Vector2i(2, 0))          # destino (2,0) == celdas de B
	_check(not manip.destino_es_valido(), "destino (2,0) solapa B -> inválido")
	_check(not manip.soltar(), "soltar() -> false")
	_check(manip.esta_agarrando() and manip.item_agarrado() == _iiA, "A sigue held")
	_check(_igual(snap) and _emis == emis0, "N1: modelo idéntico, sin emisión (INV-13)")
	manip.cancelar()


# ── N2: drop fuera de límites (parcial y total) -> rechazado ──
func _n2_fuera_de_limites() -> void:
	print("-- N2 · drop fuera de límites --")
	_check(manip.agarrar_en(_pos_de(_iiA)), "agarrar A")
	var snap := _snap()
	var emis0 := _emis
	manip.mover_hover_a(Vector2i(3, 0))          # (3,0),(4,0) -> parcial OOB
	_check(not manip.soltar(), "parcial OOB (3,0) -> false")
	manip.mover_hover_a(Vector2i(-1, 1))         # x < 0
	_check(not manip.soltar(), "OOB negativo (-1,1) -> false")
	_check(manip.esta_agarrando(), "A sigue held")
	_check(_igual(snap) and _emis == emis0, "N2: modelo idéntico, sin emisión")
	manip.cancelar()


# ── N3: rotar un ítem con can_rotate=false -> no se aplica ──
func _n3_rotar_no_permitido() -> void:
	print("-- N3 · rotar can_rotate=false --")
	_check(manip.agarrar_en(_pos_de(_iiC)), "agarrar C")
	var rot_tent := manip.rotacion_tentativa()
	var snap := _snap()
	var emis0 := _emis
	_check(not manip.rotar_tentativo(), "rotar_tentativo() -> false")
	_check(manip.rotacion_tentativa() == rot_tent, "rotacion_tentativa sin cambios")
	_check(_entry_de(_iiC).rotated == false, "rotated real de C intacto (INV-15)")
	_check(_igual(snap) and _emis == emis0, "N3: modelo idéntico, sin emisión")
	manip.cancelar()


# ── N4: rotación tentativa válida de forma, pero el drop cae inválido ──
func _n4_rotar_a_posicion_invalida() -> void:
	print("-- N4 · rotar y soltar en posición inválida --")
	_check(manip.agarrar_en(_pos_de(_iiA)), "agarrar A")
	_check(manip.rotar_tentativo(), "rotar A (can_rotate=true) -> true")
	var snap := _snap()
	var emis0 := _emis
	manip.mover_hover_a(Vector2i(0, 3))          # rotado 1x2 -> (0,3),(0,4) OOB
	_check(not manip.destino_es_valido(), "rotado en (0,3) -> se sale por abajo")
	_check(not manip.soltar(), "soltar() -> false")
	manip.mover_hover_a(Vector2i(2, 0))          # rotado 1x2 -> (2,0),(2,1) solapa B en (2,0)
	_check(not manip.destino_es_valido(), "rotado en (2,0) -> solapa B")
	_check(not manip.soltar(), "soltar() -> false")
	_check(manip.esta_agarrando(), "A sigue held")
	var eA := _entry_de(_iiA)
	_check(eA.rotated == false and eA.position == Vector2i(0, 0), "rotated/position reales de A intactos")
	_check(_igual(snap) and _emis == emis0, "N4: modelo idéntico, sin emisión")
	manip.cancelar()


# ── N5: cerrar la UI con un ítem held -> modelo idéntico (INV-12) ──
func _n5_cerrar_con_held() -> void:
	print("-- N5 · cerrar la UI con un ítem en la mano --")
	_check(manip.agarrar_en(_pos_de(_iiA) + Vector2i(1, 0)), "agarrar A por su 2da celda")
	manip.mover_hover_a(Vector2i(3, 3))
	manip.rotar_tentativo()
	var snap := _snap()
	var emis0 := _emis
	manip.cancelar()                            # lo que hace el harness al cerrar
	_check(not manip.esta_agarrando(), "tras cerrar, no está agarrando")
	var eA := _entry_de(_iiA)
	_check(eA.position == Vector2i(0, 0) and eA.rotated == false, "A quedó en su posición/orientación original")
	_check(_igual(snap) and _emis == emis0, "N5: modelo idéntico, sin emisión")


# ── N6: invariante de custodia a lo largo de una sesión ──
func _n6_invariante_custodia() -> void:
	print("-- N6 · invariante de custodia (World/Inventory) --")
	var pasos := [
		["A a (2,1) válido",   _iiA, Vector2i(2, 1), false, true],
		["A solapa B",         _iiA, Vector2i(2, 0), false, false],
		["C a (0,3) válido",   _iiC, Vector2i(0, 3), false, true],
		["B fuera de límites",  _iiB, Vector2i(3, 0), false, false],
		["A vuelve a (0,0)",   _iiA, Vector2i(0, 0), false, true],
	]
	for p in pasos:
		var etq: String = p[0]
		var ii: ItemInstance = p[1]
		manip.agarrar_en(_pos_de(ii))
		manip.mover_hover_a(p[2])
		if p[3]:
			manip.rotar_tentativo()
		var ok: bool = manip.soltar()
		if manip.esta_agarrando():
			manip.cancelar()
		_check(ok == p[4], "N6 [%s]: soltar() -> %s" % [etq, p[4]])
		for it in [_iiA, _iiB, _iiC]:
			var c := _custodia(it)
			if not ((c.x == 1 and c.y == 0) or (c.x == 0 and c.y == 1)):
				_check(false, "N6 [%s]: custodia rota para #%d -> World=%d/Inv=%d" % [etq, it.instance_id, c.x, c.y])
		_check(inv.get_entries().size() == 3, "N6 [%s]: _entries.size() == 3 (INV-10)" % etq)
		_check(_sin_solapamientos(), "N6 [%s]: sin solapes en el inventario (INV-11)" % etq)
	for it in [_iiA, _iiB, _iiC]:
		_check(_custodia(it) == Vector2i(0, 1), "N6 final: #%d -> World=0/Inv=1 (INV-16)" % it.instance_id)


# ── N7: stress -> sin entries duplicadas, identidades estables, sin drift ──
func _n7_stress() -> void:
	print("-- N7 · stress --")
	var items := [_iiA, _iiB, _iiC]
	var destinos := [Vector2i(2, 2), Vector2i(9, 9), Vector2i(-2, 0), Vector2i(1, 3), Vector2i(0, 0),
		Vector2i(2, 0), Vector2i(3, 3), Vector2i(0, 2), Vector2i(2, 1), Vector2i(1, 1)]
	for k in range(30):
		var ii: ItemInstance = items[k % 3]
		if not manip.agarrar_en(_pos_de(ii)):
			continue
		manip.mover_hover_a(destinos[k % destinos.size()])
		if k % 2 == 0:
			manip.rotar_tentativo()
		manip.soltar()
		if manip.esta_agarrando():
			manip.cancelar()

	# no drift: 12 rotaciones seguidas sobre A
	manip.agarrar_en(_pos_de(_iiA))
	var off0 := manip.offset_agarre_actual()
	for i in range(12):
		manip.rotar_tentativo()
	var drift := manip.offset_agarre_actual() != off0
	manip.cancelar()

	var entries := inv.get_entries()
	var ids := {}
	for e in entries:
		ids[e.item_instance.instance_id] = true
	_check(entries.size() == 3, "N7: siguen 3 entries (%d)" % entries.size())
	_check(ids.has(_iiA.instance_id) and ids.has(_iiB.instance_id) and ids.has(_iiC.instance_id) and ids.size() == 3,
		"N7: mismos 3 ItemInstance, sin duplicados")
	_check(inv.has_item(_iiA) and inv.has_item(_iiB) and inv.has_item(_iiC), "N7: los 3 ítems siguen bajo custodia")
	_check(_sin_solapamientos(), "N7: sin solapes tras el stress (INV-11)")
	_check(not manip.esta_agarrando(), "N7: el manipulator no quedó trabado en held")
	_check(not drift, "N7: 12 rotaciones seguidas -> offset vuelve al original, sin drift acumulado")


# ── P5: abrir / cerrar la vista no muta el modelo (INV-12) ──
func _p5_abrir_cerrar_identico() -> void:
	print("-- P5 · abrir/cerrar la vista no muta --")
	var snap := _snap()
	var emis0 := _emis
	var layout0 := view.layout_entries()
	view.set_inventory(null)          # "cerrar"
	view.set_inventory(inv)           # "reabrir"
	manip.setup(view, authority)
	_check(_igual(snap) and _emis == emis0, "P5: modelo idéntico, sin emisión")
	var layout1 := view.layout_entries()
	var igual_layout := layout0.size() == layout1.size()
	# layout_entries() ya no expone identidad (D8): se compara por valor.
	for i in range(min(layout0.size(), layout1.size())):
		if layout0[i]["position"] != layout1[i]["position"] \
		or layout0[i]["rotated"] != layout1[i]["rotated"] \
		or layout0[i]["footprint"] != layout1[i]["footprint"] \
		or layout0[i]["rect"] != layout1[i]["rect"]:
			igual_layout = false
	_check(igual_layout, "P5: el layout de la vista es idéntico tras cerrar/reabrir")


# ── P6: una reubicación V1 no rompe el ciclo V0 (identidad end-to-end) ──
func _p6_puente_v0() -> void:
	print("-- P6 · reubicar en V1, después devolver al mundo (V0) --")
	var pos_orig := _pos_de(_iiA)
	manip.agarrar_en(pos_orig)
	var movido := false
	for y in range(4):
		for x in range(4):
			manip.mover_hover_a(Vector2i(x, y))
			if manip.destino_es_valido() and manip.celda_destino_tentativa() != pos_orig:
				movido = manip.soltar()
				break
		if movido:
			break
	if manip.esta_agarrando():
		manip.cancelar()
	_check(movido, "P6: reubicación V1 de A a un hueco libre -> true")
	var idA := _iiA.instance_id
	_check(_pos_de(_iiA) != pos_orig, "A cambió de posición (%s -> %s)" % [pos_orig, _pos_de(_iiA)])

	var wi: WorldItemV2 = authority.solicitar_devolucion(_iiA, inv, mundo, punto_spawn.global_position)
	await get_tree().process_frame
	_check(wi != null, "P6: solicitar_devolucion devolvió un WorldItemV2")
	_check(wi != null and wi.item_instance == _iiA, "P6: el WorldItem lleva la MISMA ItemInstance")
	_check(_iiA.instance_id == idA, "P6: instance_id intacto (#%d)" % idA)
	_check(not inv.has_item(_iiA), "P6: A ya no está en el inventario")
	_check(inv.get_entries().size() == 2, "P6: _entries.size() == 2")
	_check(_custodia(_iiA) == Vector2i(1, 0), "P6: custodia de A -> World=1/Inv=0")


# ── Instrumentación ────────────────────────────────────────────────

func _custodia(item: ItemInstance) -> Vector2i:
	var w := 0
	var pila: Array[Node] = [get_tree().root]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is WorldItemV2 and not n.is_queued_for_deletion() and (n as WorldItemV2).item_instance == item:
			w += 1
		pila.append_array(n.get_children())
	var i := 0
	for entry in inv.get_entries():
		if entry.item_instance == item:
			i += 1
	return Vector2i(w, i)


func _sin_solapamientos() -> bool:
	var entries := inv.get_entries()
	for i in range(entries.size()):
		var celdas_i := inv.celdas_ocupadas_por(entries[i])
		for j in range(i + 1, entries.size()):
			for c in inv.celdas_ocupadas_por(entries[j]):
				if celdas_i.has(c):
					return false
	return true


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
