extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory · Batch B.2 (deuda D8).
##
## TRIPWIRE del contrato de identidad de ItemInstance / ItemDefinition.
##
## GDScript 4.6.3 no tiene privacidad real: un consumidor que sostiene un
## ItemInstance puede hacer `ii.definition = otra`, `ii.definition.grid_width =
## 99`, `ii.instance_id = x`. La auditoría de Batch B.2 confirmó que NINGÚN
## consumidor del repo lo hace y que las cuatro reglas de contrato se cumplen
## de facto (docs/inventory_system_v0_v1.md sección 17, D8):
##
##   C-D8.1  definition se fija en _init() y no se reasigna;
##   C-D8.2  ItemDefinition es config de tipo, inmutable en runtime;
##   C-D8.3  instance_id se fija en _init(), solo aid de logs/tests;
##   C-D8.4  _siguiente_id es detalle de construcción.
##
## Este test recorre el ciclo completo pickup -> reubicación -> devolución y
## verifica que, de punta a punta:
##   - es la MISMA referencia de ItemInstance;
##   - es la MISMA referencia de ItemDefinition (el .tres compartido);
##   - instance_id es estable;
##   - los campos estructurales de definition no cambiaron.
##
## NO ejercita la mutación prohibida (D8 es limitación deliberada): el contrato
## se cumple porque nadie lo viola, no porque esté bloqueado. Cero ERROR /
## printerr intencionales; no imprime nada sobre D8 en el gate.

@export var item_definition_test: ItemDefinition   # 2x1 can_rotate

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv               # 4x4
@onready var mundo: Node3D = $Mundo
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo

const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== INVENTORY · BATCH B.2 · CONTRATO DE IDENTIDAD (D8) =====")
	# C1: actor de prueba con InventoryReceiver hijo directo (reemplaza el par
	# pre-C1 authority.set_inventory_receptor(inv) + wi.setup(authority)).
	var _actor := InventoryTestActor.crear(inv, authority)
	add_child(_actor)

	# ── construir la instancia y CAPTURAR referencias + valores estructurales ──
	var wi: WorldItemV2 = item_definition_test.world_scene.instantiate()
	var ii := ItemInstance.new(item_definition_test)
	wi.item_instance = ii
	add_child(wi)
	wi.global_position = punto_spawn.global_position

	var ref_ii := ii
	var ref_def := ii.definition
	var id0 := ii.instance_id
	var def_id0 := ref_def.id
	var def_nombre0 := ref_def.nombre
	var def_scene0 := ref_def.world_scene
	var def_w0 := ref_def.grid_width
	var def_h0 := ref_def.grid_height
	var def_rot0 := ref_def.can_rotate

	_check(ref_def == item_definition_test, "setup: definition == el .tres compartido")

	# ── 1. PICKUP: mundo -> inventario ──
	print("-- 1. pickup (mundo -> inventario) --")
	var ok_pick: bool = wi._on_interact(Interaction.new(_actor, &"usar"))
	_check(ok_pick, "1: pickup exitoso")
	await get_tree().process_frame
	var e1 := _snap_de(ref_ii)
	_check(e1 != null, "1: A quedó bajo custodia del inventario")
	_check(e1 != null and e1.item_instance == ref_ii, "1: la entry lleva la MISMA referencia ItemInstance")
	_check(e1 != null and e1.item_instance.definition == ref_def, "1: y la MISMA referencia ItemDefinition")
	_check(ref_ii.instance_id == id0, "1: instance_id estable (#%d)" % id0)

	# ── 2. REUBICACIÓN dentro del inventario (mover + rotar) ──
	print("-- 2. reubicación dentro del inventario (mover + rotar) --")
	var ok_re: bool = authority.solicitar_reubicacion(ref_ii, inv, Vector2i(2, 1), true)
	_check(ok_re, "2: reubicación a (2,1) rotado -> true")
	var e2 := _snap_de(ref_ii)
	_check(e2 != null and e2.item_instance == ref_ii, "2: sigue la MISMA referencia ItemInstance")
	_check(e2 != null and e2.item_instance.definition == ref_def, "2: sigue la MISMA referencia ItemDefinition")
	_check(ref_ii.instance_id == id0, "2: instance_id estable")
	_check(e2 != null and e2.position == Vector2i(2, 1) and e2.rotated, "2: la entry se movió/rotó (placement OK)")

	# ── 3. DEVOLUCIÓN: inventario -> mundo ──
	print("-- 3. devolución (inventario -> mundo) --")
	var wi2: WorldItemV2 = authority.solicitar_devolucion(ref_ii, inv, mundo, punto_spawn.global_position)
	await get_tree().process_frame
	_check(wi2 != null, "3: devolución produjo un WorldItemV2")
	_check(wi2 != null and wi2.item_instance == ref_ii, "3: el WorldItem lleva la MISMA referencia ItemInstance de todo el ciclo")
	_check(wi2 != null and wi2.item_instance.definition == ref_def, "3: y la MISMA referencia ItemDefinition")
	_check(ref_ii.instance_id == id0, "3: instance_id estable de punta a punta (#%d)" % id0)
	_check(not inv.has_item(ref_ii), "3: A ya no está en el inventario")

	# ── 4. ItemDefinition: campos estructurales INTACTOS tras todo el ciclo ──
	print("-- 4. campos estructurales de ItemDefinition sin cambios --")
	_check(ref_def == item_definition_test, "4: definition sigue siendo el mismo .tres compartido")
	_check(ref_def.id == def_id0, "4: definition.id sin cambios (%s)" % ref_def.id)
	_check(ref_def.nombre == def_nombre0, "4: definition.nombre sin cambios")
	_check(ref_def.world_scene == def_scene0, "4: definition.world_scene sin cambios")
	_check(ref_def.grid_width == def_w0 and ref_def.grid_height == def_h0,
		"4: definition.grid_width/height sin cambios (%dx%d)" % [ref_def.grid_width, ref_def.grid_height])
	_check(ref_def.can_rotate == def_rot0, "4: definition.can_rotate sin cambios (%s)" % ref_def.can_rotate)

	# NOTA (D8 — docs/inventory_system_v0_v1.md sección 17): GDScript 4.6.3 NO
	# impide `ref_ii.definition = otra` ni `ref_ii.definition.grid_width = 99`
	# desde un consumidor. Este test NO lo ejercita: verifica que el contrato
	# C-D8.1..4 se cumple porque NINGÚN código lo viola, no porque esté
	# bloqueado. Es una limitación deliberada; no se imprime nada al respecto.

	print("=============================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: CONTRATO DE IDENTIDAD (D8) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Falló el contrato de identidad de ItemInstance/ItemDefinition")
	get_tree().quit(_fallos)


## Snapshot ACTUAL de la entry de `ii` en el inventario (o null).
func _snap_de(ii: ItemInstance) -> InventoryEntry:
	for e in inv.get_entries():
		if e.item_instance == ii:
			return e
	return null


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
