extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory V1 · Paso 6.
##
## Suite de aceptación de V1: ejercita el stack completo end-to-end a través
## del InventoryManipulator (vista + manipulator + operación + modelo) y
## verifica los criterios NEGATIVOS N1..N7 del diseño, más las integraciones
## P5 (abrir/cerrar sin mutar) y P6 (una reubicación V1 no rompe el ciclo V0).
##
## Invariantes chequeadas: INV-09 (identidad de ItemInstance/InventoryEntry),
## INV-10 (_entries.size constante), INV-11 (sin solapes), INV-12 (abrir/cerrar
## no muta), INV-13 (drop rechazado -> modelo idéntico), INV-15 (can_rotate),
## INV-16 (custodia: nunca mundo+inventario a la vez).

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

var _idA := 0
var _idB := 0
var _idC := 0


func _ready() -> void:
	print("\n===== INVENTORY V1 · PASO 6 · SUITE DE ACEPTACIÓN (N1..N7 + P5/P6) =====")

	var e := _sembrar()                # A@(0,0) rota, B@(2,0) rota, C@(0,1) no-rota
	var eA: InventoryEntry = e[0]
	var eB: InventoryEntry = e[1]
	var eC: InventoryEntry = e[2]
	_idA = eA.item_instance.instance_id
	_idB = eB.item_instance.instance_id
	_idC = eC.item_instance.instance_id

	inv.contenido_cambiado.connect(func() -> void: _emis += 1)
	view.set_inventory(inv)
	manip.setup(view, authority)
	await get_tree().process_frame     # que se asienten los queue_free de la siembra

	_n1_solapamiento(eA)
	_n2_fuera_de_limites(eA)
	_n3_rotar_no_permitido(eC)
	_n4_rotar_a_posicion_invalida(eA)
	_n5_cerrar_con_held(eA)
	_n6_invariante_custodia(eA, eB, eC)
	_n7_stress(eA, eB, eC)
	_p5_abrir_cerrar_identico()
	await _p6_puente_v0(eA)

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


# ── N1: drop solapando otra entry -> rechazado, modelo idéntico, sigue held ──
func _n1_solapamiento(eA: InventoryEntry) -> void:
	print("-- N1 · drop solapando otra entry --")
	_check(manip.agarrar_en(Vector2i(0, 0)), "agarrar A")
	var snap := _snap()
	var emis0 := _emis
	manip.mover_hover_a(Vector2i(2, 0))          # destino (2,0) == celdas de B
	_check(not manip.destino_es_valido(), "destino (2,0) solapa B -> inválido")
	_check(not manip.soltar(), "soltar() -> false")
	_check(manip.esta_agarrando() and manip.entry_agarrada() == eA, "A sigue held")
	_check(_igual(snap) and _emis == emis0, "N1: modelo idéntico, sin emisión (INV-13)")
	manip.cancelar()


# ── N2: drop fuera de límites (parcial y total) -> rechazado ──
func _n2_fuera_de_limites(eA: InventoryEntry) -> void:
	print("-- N2 · drop fuera de límites --")
	_check(manip.agarrar_en(Vector2i(0, 0)), "agarrar A")
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
func _n3_rotar_no_permitido(eC: InventoryEntry) -> void:
	print("-- N3 · rotar can_rotate=false --")
	_check(manip.agarrar_en(Vector2i(0, 1)), "agarrar C")
	var rot_tent := manip.rotacion_tentativa()
	var snap := _snap()
	var emis0 := _emis
	_check(not manip.rotar_tentativo(), "rotar_tentativo() -> false")
	_check(manip.rotacion_tentativa() == rot_tent, "rotacion_tentativa sin cambios")
	_check(eC.rotated == false, "entry.rotated real de C intacto (INV-15)")
	_check(_igual(snap) and _emis == emis0, "N3: modelo idéntico, sin emisión")
	manip.cancelar()


# ── N4: rotación tentativa válida de forma, pero el drop cae inválido ──
func _n4_rotar_a_posicion_invalida(eA: InventoryEntry) -> void:
	print("-- N4 · rotar y soltar en posición inválida --")
	_check(manip.agarrar_en(Vector2i(0, 0)), "agarrar A")
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
	_check(eA.rotated == false and eA.position == Vector2i(0, 0), "entry.rotated/position reales de A intactos")
	_check(_igual(snap) and _emis == emis0, "N4: modelo idéntico, sin emisión")
	manip.cancelar()


# ── N5: cerrar la UI con un ítem held -> modelo idéntico (INV-12) ──
func _n5_cerrar_con_held(eA: InventoryEntry) -> void:
	print("-- N5 · cerrar la UI con un ítem en la mano --")
	_check(manip.agarrar_en(Vector2i(1, 0)), "agarrar A por su 2da celda")
	manip.mover_hover_a(Vector2i(3, 3))
	manip.rotar_tentativo()
	var snap := _snap()
	var emis0 := _emis
	manip.cancelar()                            # lo que hace el harness al cerrar
	_check(not manip.esta_agarrando(), "tras cerrar, no está agarrando")
	_check(eA.position == Vector2i(0, 0) and eA.rotated == false, "A quedó en su posición/orientación original")
	_check(_igual(snap) and _emis == emis0, "N5: modelo idéntico, sin emisión")


# ── N6: invariante de custodia a lo largo de una sesión ──
func _n6_invariante_custodia(eA: InventoryEntry, eB: InventoryEntry, eC: InventoryEntry) -> void:
	print("-- N6 · invariante de custodia (World/Inventory) --")
	var pasos := [
		["A a (2,1) válido",  eA, Vector2i(2, 1), false, true],
		["A solapa B",        eA, Vector2i(2, 0), false, false],
		["C a (0,3) válido",  eC, Vector2i(0, 3), false, true],
		["B fuera de límites", eB, Vector2i(3, 0), false, false],
		["A vuelve a (0,0)",  eA, Vector2i(0, 0), false, true],
	]
	for p in pasos:
		var etq: String = p[0]
		var entry: InventoryEntry = p[1]
		manip.agarrar_en(entry.position)
		manip.mover_hover_a(p[2])
		if p[3]:
			manip.rotar_tentativo()
		var ok: bool = manip.soltar()
		if manip.esta_agarrando():
			manip.cancelar()
		_check(ok == p[4], "N6 [%s]: soltar() -> %s" % [etq, p[4]])
		# tras cada operación, custodia de los 3 ítems:
		for it in [eA.item_instance, eB.item_instance, eC.item_instance]:
			var c := _custodia(it)
			if not ((c.x == 1 and c.y == 0) or (c.x == 0 and c.y == 1)):
				_check(false, "N6 [%s]: custodia rota para #%d -> World=%d/Inv=%d" % [etq, it.instance_id, c.x, c.y])
		_check(inv.get_entries().size() == 3, "N6 [%s]: _entries.size() == 3 (INV-10)" % etq)
		_check(_sin_solapamientos(), "N6 [%s]: sin solapes en el inventario (INV-11)" % etq)
	# los 3 ítems quedan en inventario, ninguno en el mundo
	for it in [eA.item_instance, eB.item_instance, eC.item_instance]:
		_check(_custodia(it) == Vector2i(0, 1), "N6 final: #%d -> World=0/Inv=1 (INV-16)" % it.instance_id)


# ── N7: stress -> sin entries duplicadas, identidades estables, sin drift ──
func _n7_stress(eA: InventoryEntry, eB: InventoryEntry, eC: InventoryEntry) -> void:
	print("-- N7 · stress --")
	var items := [eA, eB, eC]
	var destinos := [Vector2i(2, 2), Vector2i(9, 9), Vector2i(-2, 0), Vector2i(1, 3), Vector2i(0, 0),
		Vector2i(2, 0), Vector2i(3, 3), Vector2i(0, 2), Vector2i(2, 1), Vector2i(1, 1)]
	for k in range(30):
		var entry: InventoryEntry = items[k % 3]
		if not manip.agarrar_en(entry.position):
			continue
		manip.mover_hover_a(destinos[k % destinos.size()])
		if k % 2 == 0:
			manip.rotar_tentativo()
		manip.soltar()
		if manip.esta_agarrando():
			manip.cancelar()

	# no drift: 12 rotaciones seguidas sobre A
	manip.agarrar_en(eA.position)
	var off0 := manip.offset_agarre_actual()
	var drift := false
	for i in range(12):
		manip.rotar_tentativo()
	if manip.offset_agarre_actual() != off0:
		drift = true
	manip.cancelar()

	var entries := inv.get_entries()
	var refs := {}
	var ids := {}
	for e in entries:
		refs[e] = true
		ids[e.item_instance.instance_id] = true
	_check(entries.size() == 3, "N7: siguen 3 entries (%d)" % entries.size())
	_check(refs.has(eA) and refs.has(eB) and refs.has(eC), "N7: mismas 3 InventoryEntry, sin duplicados (INV-09)")
	_check(ids.has(_idA) and ids.has(_idB) and ids.has(_idC) and ids.size() == 3, "N7: mismos 3 instance_id")
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
	for i in range(min(layout0.size(), layout1.size())):
		if layout0[i]["entry"] != layout1[i]["entry"] or layout0[i]["rect"] != layout1[i]["rect"]:
			igual_layout = false
	_check(igual_layout, "P5: el layout de la vista es idéntico tras cerrar/reabrir")


# ── P6: una reubicación V1 no rompe el ciclo V0 (identidad end-to-end) ──
func _p6_puente_v0(eA: InventoryEntry) -> void:
	print("-- P6 · reubicar en V1, después devolver al mundo (V0) --")
	manip.agarrar_en(eA.position)
	var pos_orig := eA.position
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
	var iiA := eA.item_instance
	var idA := iiA.instance_id
	_check(eA.position != pos_orig, "A cambió de posición (%s -> %s)" % [pos_orig, eA.position])

	var wi: WorldItemV2 = authority.solicitar_devolucion(iiA, inv, mundo, punto_spawn.global_position)
	await get_tree().process_frame
	_check(wi != null, "P6: solicitar_devolucion devolvió un WorldItemV2")
	_check(wi != null and wi.item_instance == iiA, "P6: el WorldItem lleva la MISMA ItemInstance")
	_check(iiA.instance_id == idA, "P6: instance_id intacto (#%d)" % idA)
	_check(not inv.has_item(iiA), "P6: A ya no está en el inventario")
	_check(inv.get_entries().size() == 2, "P6: _entries.size() == 2")
	_check(_custodia(iiA) == Vector2i(1, 0), "P6: custodia de A -> World=1/Inv=0")


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
		s.append([e, e.position, e.rotated, e.item_instance, e.item_instance.instance_id])
	return s


func _igual(snap: Array) -> bool:
	var live := inv.get_entries()
	if live.size() != snap.size():
		return false
	for i in range(live.size()):
		var r: Array = snap[i]
		if live[i] != r[0] or live[i].position != r[1] or live[i].rotated != r[2] \
		or live[i].item_instance != r[3] or live[i].item_instance.instance_id != r[4]:
			return false
	return true


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
