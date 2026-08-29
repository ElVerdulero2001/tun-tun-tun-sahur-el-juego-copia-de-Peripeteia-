extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory · Batch B (deuda D1).
##
## GDScript 4.6.3 no tiene privacidad real: el "_" es convención y una
## property get-only solo tapa un nombre. La barrera de D1 es ESTRUCTURAL:
## InventoryV2 nunca entrega sus InventoryEntry vivas. get_entries() y
## entry_en_celda() devuelven SNAPSHOTS (copias detached). Mutar una
## snapshot no puede tocar el modelo.
##
## Demuestra:
##  1. get_entries() devuelve snapshot -> mutarla no cambia el modelo;
##  2. entry_en_celda() devuelve snapshot -> mutarla no cambia el modelo;
##  3. dos snapshots de la misma entry son objetos DISTINTOS pero con el
##     MISMO ItemInstance;
##  4. ninguna mutación de snapshot emite contenido_cambiado;
##  5. custodia intacta;
##  6. reubicación autorizada modifica la entry interna real IN-PLACE
##     (white-box sobre inv._entries);
##  7. pickup y devolución preservan el mismo ItemInstance;
##  8. CERO ERROR intencionales en consola.

@export var item_definition_test: ItemDefinition   # 2x1 can_rotate

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv               # 4x4
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo
@onready var mundo: Node3D = $Mundo

const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

var _fallos := 0
var _checks := 0
var _emis := 0


func _ready() -> void:
	print("\n===== INVENTORY · BATCH B · InventoryEntry: barrera estructural =====")

	var entries := _sembrar(2)          # A@(0,0), B@(2,0), 2x1 can_rotate
	inv.contenido_cambiado.connect(func() -> void: _emis += 1)
	await get_tree().process_frame      # que se asienten los queue_free de la siembra

	var iiA: ItemInstance = entries[0].item_instance
	var idA := iiA.instance_id

	_1_get_entries_es_snapshot(iiA)
	_2_entry_en_celda_es_snapshot(iiA)
	_3_snapshots_distintas_mismo_item(iiA)
	_4_y_5_sin_efectos_colaterales(iiA)
	_6_reubicacion_autorizada_in_place(iiA)
	await _7_pickup_y_devolucion_preservan_instancia()

	print("=========================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: BATCH B (barrera estructural) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de la barrera estructural de InventoryEntry")
	get_tree().quit(_fallos)


func _sembrar(cantidad: int) -> Array[InventoryEntry]:
	var _actor := _actor_pickup(inv)
	for i in range(cantidad):
		var wi: WorldItemV2 = item_definition_test.world_scene.instantiate()
		wi.item_instance = ItemInstance.new(item_definition_test)
		add_child(wi)
		wi.global_position = punto_spawn.global_position
		var ok: bool = wi._on_interact(Interaction.new(_actor, &"usar"))
		_check(ok, "siembra: pickup #%d" % (i + 1))
	return inv.get_entries()


func _entry_viva(ii: ItemInstance) -> InventoryEntry:
	for e in inv._entries:
		if e.item_instance == ii:
			return e
	return null

func _snap_de(ii: ItemInstance) -> InventoryEntry:
	for e in inv.get_entries():
		if e.item_instance == ii:
			return e
	return null

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


# 1 ─────────────────────────────────────────────────────────────────
func _1_get_entries_es_snapshot(iiA: ItemInstance) -> void:
	print("-- 1. get_entries() devuelve snapshot: mutarla no toca el modelo --")
	var snap := inv.get_entries()[0]
	var vivo := _entry_viva(iiA)
	_check(snap != vivo, "1: la snapshot es un objeto DISTINTO a la entry viva")
	_check(snap.item_instance == iiA, "1: pero lleva el MISMO ItemInstance")

	var pos_viva := vivo.position
	var rot_viva := vivo.rotated
	snap.position = Vector2i(3, 3)                 # muta la copia, no el modelo
	snap.rotated = not snap.rotated
	snap.item_instance = ItemInstance.new(item_definition_test)

	_check(_entry_viva(iiA).position == pos_viva, "1: entry viva sin cambios en position")
	_check(_entry_viva(iiA).rotated == rot_viva, "1: entry viva sin cambios en rotated")
	_check(_entry_viva(iiA).item_instance == iiA, "1: entry viva sin cambios en item_instance")
	_check(inv.get_entries()[0].position == pos_viva, "1: una snapshot nueva refleja el modelo real, no la copia mutada")


# 2 ─────────────────────────────────────────────────────────────────
func _2_entry_en_celda_es_snapshot(iiA: ItemInstance) -> void:
	print("-- 2. entry_en_celda() devuelve snapshot: mutarla no toca el modelo --")
	var snap := inv.entry_en_celda(Vector2i(0, 0))
	_check(snap != null and snap.item_instance == iiA, "2: entry_en_celda((0,0)) -> A")
	_check(snap != _entry_viva(iiA), "2: no es la entry viva")

	var pos_viva := _entry_viva(iiA).position
	snap.position = Vector2i(1, 1)
	snap.rotated = true
	snap.item_instance = ItemInstance.new(item_definition_test)

	_check(_entry_viva(iiA).position == pos_viva, "2: entry viva sin cambios")
	_check(inv.entry_en_celda(Vector2i(0, 0)).item_instance == iiA, "2: A sigue en su celda")


# 3 ─────────────────────────────────────────────────────────────────
func _3_snapshots_distintas_mismo_item(iiA: ItemInstance) -> void:
	print("-- 3. dos snapshots de la misma entry: objetos distintos, mismo ItemInstance --")
	var s1 := _snap_de(iiA)
	var s2 := _snap_de(iiA)
	var s3 := inv.entry_en_celda(Vector2i(0, 0))
	_check(s1 != s2 and s1 != s3 and s2 != s3, "3: los tres son objetos InventoryEntry DISTINTOS")
	_check(s1.item_instance == iiA and s2.item_instance == iiA and s3.item_instance == iiA, "3: los tres llevan el MISMO ItemInstance")
	_check(s1.position == s2.position and s2.position == s3.position, "3: coinciden en position (mismo estado)")


# 4 y 5 ────────────────────────────────────────────────────────────
func _4_y_5_sin_efectos_colaterales(iiA: ItemInstance) -> void:
	print("-- 4/5. mutar snapshots: sin contenido_cambiado, custodia intacta --")
	var emis0 := _emis
	var custodia0 := _custodia(iiA)
	var pos_viva := _entry_viva(iiA).position

	for i in range(3):
		var s := inv.get_entries()[0]
		s.position = Vector2i(9, 9)
		s.rotated = true
		s.item_instance = ItemInstance.new(item_definition_test)
		var s2 := inv.entry_en_celda(Vector2i(0, 0))
		s2.position = Vector2i(-5, -5)

	_check(_emis == emis0, "4: contenido_cambiado NO se emitió (%d)" % (_emis - emis0))
	_check(_custodia(iiA) == custodia0 and _custodia(iiA) == Vector2i(0, 1), "5: custodia intacta (World=0 / Inv=1)")
	_check(_entry_viva(iiA).position == pos_viva, "5: la entry viva de A quedó intacta")
	_check(_entry_viva(iiA).item_instance == iiA, "5: identidad de A intacta")


# 6 ─────────────────────────────────────────────────────────────────
func _6_reubicacion_autorizada_in_place(iiA: ItemInstance) -> void:
	print("-- 6. reubicación autorizada muta la entry interna real IN-PLACE --")
	var vivo_antes := _entry_viva(iiA)
	var idA := iiA.instance_id
	var emis0 := _emis

	var ok: bool = authority.solicitar_reubicacion(iiA, inv, Vector2i(1, 2), true)

	_check(ok, "6: solicitar_reubicacion -> true")
	var vivo_despues := _entry_viva(iiA)
	_check(vivo_despues == vivo_antes, "6: es la MISMA InventoryEntry viva (INV-09, white-box)")
	_check(vivo_despues.position == Vector2i(1, 2) and vivo_despues.rotated, "6: se movió/rotó in-place a (1,2)")
	_check(vivo_despues.item_instance == iiA and iiA.instance_id == idA, "6: mismo ItemInstance / instance_id (#%d)" % idA)
	_check(inv.get_entries().size() == 2, "6: _entries.size() == 2 (INV-10)")
	_check(_emis == emis0 + 1, "6: contenido_cambiado emitido exactamente 1 vez")

	authority.solicitar_reubicacion(iiA, inv, Vector2i(0, 0), false)   # restaurar


# 7 ─────────────────────────────────────────────────────────────────
func _7_pickup_y_devolucion_preservan_instancia() -> void:
	print("-- 7. pickup y devolución preservan el mismo ItemInstance --")
	# pickup: la siembra ya lo ejercitó -> A nació completa con su ItemInstance
	var e := inv.get_entries()[0]
	var ii: ItemInstance = e.item_instance
	var id := ii.instance_id
	_check(inv.has_item(ii), "7 (pickup): A bajo custodia, entry con su ItemInstance definitivo")

	var wi: WorldItemV2 = authority.solicitar_devolucion(ii, inv, mundo, punto_spawn.global_position)
	await get_tree().process_frame
	_check(wi != null and wi.item_instance == ii and wi.item_instance.instance_id == id, "7 (devolución): el WorldItem lleva el MISMO ItemInstance (#%d)" % id)
	_check(not inv.has_item(ii), "7: A ya no está en el inventario")
	_check(_custodia(ii) == Vector2i(1, 0), "7: custodia de A -> World=1 / Inv=0")


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)


## C1: actor de prueba con InventoryReceiver hijo directo, equivalente a como
## PlayerV2 expone la capacidad. Reemplaza el par pre-C1
## authority.set_inventory_receptor(inv) + wi.setup(authority).
func _actor_pickup(inventario: InventoryV2) -> Node:
	var actor := InventoryTestActor.crear(inventario, authority)
	add_child(actor)
	return actor
