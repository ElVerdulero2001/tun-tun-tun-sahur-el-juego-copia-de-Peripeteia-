extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory V1 · Paso 3.
##
## Verifica la operación autoritativa de reubicación dentro del mismo
## InventoryV2:  LocalAuthority.solicitar_reubicacion(...)  ->
## TransferOperation (tipo REUBICAR_EN_INVENTARIO)  ->  validate() -> commit().
##
## LocalAuthority es el ÚNICO que llama validate()/commit(); este arnés solo
## llama a solicitar_reubicacion(), como haría la UI del Paso 5.
##
## Inventario poblado SOLO por la ruta V0 (spawn WorldItemV2 + pickup).

@export var item_definition_test: ItemDefinition        # 2x1, can_rotate = true
@export var item_definition_no_rota: ItemDefinition     # 2x1, can_rotate = false

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv_normal: InventoryV2 = $InvNormal       # 4x4
@onready var inv_norota: InventoryV2 = $InvNoRota       # 4x4

@onready var punto_spawn: Marker3D = $PuntoSpawnMundo

var _fallos := 0
var _checks := 0
var _emis_normal := 0
var _emis_norota := 0


func _ready() -> void:
	print("\n===== INVENTORY V1 · PASO 3 · OPERACIÓN DE REUBICACIÓN =====")

	inv_normal.contenido_cambiado.connect(func() -> void: _emis_normal += 1)
	inv_norota.contenido_cambiado.connect(func() -> void: _emis_norota += 1)

	var normal := _sembrar(inv_normal, item_definition_test, 2)     # A -> (0,0), B -> (2,0)
	var norota := _sembrar(inv_norota, item_definition_no_rota, 1)  # C -> (0,0)

	_test_positivos(normal)
	_test_negativos(normal, norota)

	print("===========================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: PASO 3 OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos del Paso 3 de V1")
	get_tree().quit(_fallos)


func _sembrar(inventario: InventoryV2, definicion: ItemDefinition, cantidad: int) -> Array[InventoryEntry]:
	authority.set_inventory_receptor(inventario)
	for i in range(cantidad):
		var wi: WorldItemV2 = definicion.world_scene.instantiate()
		wi.item_instance = ItemInstance.new(definicion)
		add_child(wi)
		wi.global_position = punto_spawn.global_position
		wi.setup(authority)
		var ok: bool = wi._on_interact(Interaction.new(self, &"usar"))
		_check(ok, "siembra: pickup #%d en %s exitoso" % [i + 1, inventario.name])
	return inventario.get_entries()


func _test_positivos(normal: Array[InventoryEntry]) -> void:
	print("-- POSITIVOS --")
	var iiA: ItemInstance = normal[0].item_instance
	var idA := iiA.instance_id
	var size0 := inv_normal.get_entries().size()
	# white-box: el objeto InventoryEntry vivo de A, para chequear INV-09.
	var vivo_A := _entry_viva(inv_normal, iiA)

	# 1. mover a una posición válida
	var base := _emis_normal
	var ok1: bool = authority.solicitar_reubicacion(iiA, inv_normal, Vector2i(0, 2), false)
	_check(ok1, "P1: mover A a (0,2) -> true")
	_check(_entry_de(inv_normal, iiA).position == Vector2i(0, 2) and not _entry_de(inv_normal, iiA).rotated, "P1: A queda en (0,2) sin rotar")
	_check(_emis_normal == base + 1, "P1: contenido_cambiado emitido exactamente 1 vez")

	# 2. rotar y mover cuando can_rotate = true
	base = _emis_normal
	var ok2: bool = authority.solicitar_reubicacion(iiA, inv_normal, Vector2i(2, 1), true)
	_check(ok2, "P2: rotar + mover A a (2,1) rotado -> true")
	var eA2 := _entry_de(inv_normal, iiA)
	_check(eA2.position == Vector2i(2, 1) and eA2.rotated, "P2: A queda en (2,1) ROTADO")
	_check(_emis_normal == base + 1, "P2: contenido_cambiado emitido exactamente 1 vez")

	# 3. conserva ItemInstance / instance_id + INV-09 white-box (misma InventoryEntry viva)
	_check(inv_normal.has_item(iiA), "P3: A sigue bajo custodia")
	_check(_entry_de(inv_normal, iiA).item_instance == iiA and iiA.instance_id == idA, "P3: mismo ItemInstance / instance_id (#%d)" % idA)
	_check(_entry_viva(inv_normal, iiA) == vivo_A, "P3 white-box: la MISMA InventoryEntry viva se reubicó in-place (INV-09)")

	# 4. conserva _entries.size()
	_check(inv_normal.get_entries().size() == size0, "P4: _entries.size() sin cambios (%d)" % size0)

	# dejar A en (0,0) para los negativos
	var vuelta: bool = authority.solicitar_reubicacion(iiA, inv_normal, Vector2i(0, 0), false)
	var eA3 := _entry_de(inv_normal, iiA)
	_check(vuelta and eA3.position == Vector2i(0, 0) and not eA3.rotated, "P-setup: A restaurada a (0,0) sin rotar")


func _test_negativos(normal: Array[InventoryEntry], norota: Array[InventoryEntry]) -> void:
	print("-- NEGATIVOS (cada uno: validate falla -> modelo idéntico, sin emisión) --")
	var iiA := normal[0].item_instance
	var iiC := norota[0].item_instance

	# N1: item que no pertenece al inventario
	var ajeno := ItemInstance.new(item_definition_test)
	var s := _snap(inv_normal)
	var b := _emis_normal
	var r1: bool = authority.solicitar_reubicacion(ajeno, inv_normal, Vector2i(0, 2), false)
	_check(not r1, "N1: item ajeno al inventario -> false")
	_verificar_sin_cambios("N1", inv_normal, s, b, _emis_normal)

	# N2: solapamiento con otra entry (A sobre B en (2,0))
	s = _snap(inv_normal)
	b = _emis_normal
	var r2: bool = authority.solicitar_reubicacion(iiA, inv_normal, Vector2i(2, 0), false)
	_check(not r2, "N2: solapar con la entry B -> false")
	_verificar_sin_cambios("N2", inv_normal, s, b, _emis_normal)

	# N3: fuera de límites (se sale por derecha; y x negativo)
	s = _snap(inv_normal)
	b = _emis_normal
	var r3a: bool = authority.solicitar_reubicacion(iiA, inv_normal, Vector2i(3, 0), false)
	var r3b: bool = authority.solicitar_reubicacion(iiA, inv_normal, Vector2i(-1, 0), false)
	_check(not r3a and not r3b, "N3: (3,0) y (-1,0) con footprint 2x1 -> false")
	_verificar_sin_cambios("N3", inv_normal, s, b, _emis_normal)

	# N4: rotación no permitida (C.can_rotate == false, se pide rotar en su lugar)
	s = _snap(inv_norota)
	b = _emis_norota
	var r4: bool = authority.solicitar_reubicacion(iiC, inv_norota, Vector2i(0, 0), true)
	_check(not r4, "N4: rotar un item con can_rotate=false -> false")
	_verificar_sin_cambios("N4", inv_norota, s, b, _emis_norota)

	# N5: rotación que SÍ cabría geométricamente, pero prohibida por can_rotate
	#     (0,2) rotado 1x2 -> celdas (0,2),(0,3): libres. Igual se rechaza.
	s = _snap(inv_norota)
	b = _emis_norota
	var r5: bool = authority.solicitar_reubicacion(iiC, inv_norota, Vector2i(0, 2), true)
	_check(not r5, "N5: rotación geométricamente válida pero can_rotate=false -> false")
	_verificar_sin_cambios("N5", inv_norota, s, b, _emis_norota)

	# Control: mover C SIN rotar sí se permite (can_rotate=false no bloquea el movimiento)
	b = _emis_norota
	var rc: bool = authority.solicitar_reubicacion(iiC, inv_norota, Vector2i(0, 2), false)
	_check(rc, "control: mover C sin rotar -> true")
	_check(_emis_norota == b + 1, "control: contenido_cambiado emitido 1 vez")


## ── Instrumentación ────────────────────────────────────────────────

## Snapshot ACTUAL de la entry de `ii` (o null).
func _entry_de(inv: InventoryV2, ii: ItemInstance) -> InventoryEntry:
	for e in inv.get_entries():
		if e.item_instance == ii:
			return e
	return null

## white-box: el objeto InventoryEntry VIVO de `ii` en inv._entries (o null).
func _entry_viva(inv: InventoryV2, ii: ItemInstance) -> InventoryEntry:
	for e in inv._entries:
		if e.item_instance == ii:
			return e
	return null


func _snap(inv: InventoryV2) -> Array:
	var s := []
	for e in inv.get_entries():
		s.append([e.item_instance, e.position, e.rotated, e.item_instance.instance_id])
	return s


func _verificar_sin_cambios(etq: String, inv: InventoryV2, snap: Array, emis_antes: int, emis_ahora: int) -> void:
	var live := inv.get_entries()
	var ok := live.size() == snap.size()
	for i in range(min(live.size(), snap.size())):
		var r: Array = snap[i]
		if live[i].item_instance != r[0] \
		or live[i].position != r[1] \
		or live[i].rotated != r[2] \
		or live[i].item_instance.instance_id != r[3]:
			ok = false
	_check(ok, "%s: posición / rotación / identidad / _entries.size() EXACTAMENTE iguales" % etq)
	_check(emis_ahora == emis_antes, "%s: contenido_cambiado NO se emitió en el fallo" % etq)


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
