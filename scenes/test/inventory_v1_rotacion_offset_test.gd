extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory V1 · Paso 5 (fix de offset).
##
## Cubre el drift del ghost al rotar: el punto de agarre debe seguir bajo el
## cursor después de rotar, en las dos orientaciones y sin acumular error.
##
## 1. agarrar un 2x1 desde la PRIMERA celda y rotar;
## 2. agarrarlo desde la SEGUNDA celda y rotar;
## 3. la celda interna agarrada se mantiene coherente con _celda_hover;
## 4. rotar de vuelta a la orientación original -> sin drift;
## 5. muchas rotaciones -> sin acumulación de desplazamiento.
## + bonus: ítem ya rotado al momento de agarrarlo.

@export var item_definition_test: ItemDefinition   # grid_width=2, grid_height=1, can_rotate

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv               # 4x4
@onready var inv_ang: InventoryV2 = $InvAngosto    # 1x4: fuerza rotación al pickear
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo
@onready var view: InventoryGridView = $CanvasLayer/InventoryGridView
@onready var manip: InventoryManipulator = $CanvasLayer/InventoryGridView/InventoryManipulator

const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

var _fallos := 0
var _checks := 0
var _W := 0
var _H := 0


func _ready() -> void:
	print("\n===== INVENTORY V1 · PASO 5 · FIX DEL OFFSET DE AGARRE AL ROTAR =====")
	_W = item_definition_test.grid_width
	_H = item_definition_test.grid_height

	var eN := _sembrar(inv, 1)[0]        # A en (0,0), SIN rotar (footprint 2x1)
	var eR := _sembrar(inv_ang, 1)[0]    # C en (0,0), ROTADA (footprint 1x2)

	view.set_inventory(inv)
	manip.setup(view, authority)

	_p1_primera_celda(eN)
	_p2_a_p5_segunda_celda(eN)
	_bonus_rotada_al_agarrar(eR)

	print("===================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: FIX OFFSET OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos del fix de offset")
	get_tree().quit(_fallos)


func _sembrar(inventario: InventoryV2, cantidad: int) -> Array[InventoryEntry]:
	var _actor := _actor_pickup(inventario)
	for i in range(cantidad):
		var wi: WorldItemV2 = item_definition_test.world_scene.instantiate()
		wi.item_instance = ItemInstance.new(item_definition_test)
		add_child(wi)
		wi.global_position = punto_spawn.global_position
		var ok: bool = wi._on_interact(Interaction.new(_actor, &"usar"))
		_check(ok, "siembra: pickup en %s" % inventario.name)
	return inventario.get_entries()


func _footprint(rotated: bool) -> Vector2i:
	return Vector2i(_H, _W) if rotated else Vector2i(_W, _H)


func _cursor_dentro_del_ghost() -> bool:
	var off := manip.offset_agarre_actual()
	var fp := _footprint(manip.rotacion_tentativa())
	return off.x >= 0 and off.y >= 0 and off.x < fp.x and off.y < fp.y


## Invariante central: el cursor está siempre sobre la MISMA celda física
## del ítem que se agarró -> offset dentro del footprint + coherencia
## celda_hover == destino + offset.
func _verificar_coherencia(etq: String) -> void:
	var off := manip.offset_agarre_actual()
	var destino := manip.celda_destino_tentativa()
	var hover := manip.celda_hover()
	_check(_cursor_dentro_del_ghost(), "%s: cursor DENTRO del ghost (offset %s, footprint %s)" % [etq, off, _footprint(manip.rotacion_tentativa())])
	_check(hover - destino == off, "%s: coherencia hover(%s) - destino(%s) == offset(%s)" % [etq, hover, destino, off])
	_check(hover == destino + off, "%s: el cursor cae sobre la celda agarrada" % etq)


func _p1_primera_celda(eN: InventoryEntry) -> void:
	print("-- 1. agarrar 2x1 desde la PRIMERA celda y rotar --")
	_check(manip.agarrar_en(Vector2i(0, 0)), "agarrar A en su primera celda (0,0)")
	_check(manip._agarre_rel_normal == Vector2i(0, 0), "canónico de agarre = (0,0)")
	manip.mover_hover_a(Vector2i(2, 2))
	_check(manip.celda_destino_tentativa() == Vector2i(2, 2), "sin rotar: offset (0,0) -> destino sigue al cursor")
	_verificar_coherencia("P1 sin rotar")

	manip.rotar_tentativo()
	_check(manip.rotacion_tentativa(), "rotado")
	_check(manip.offset_agarre_actual() == Vector2i(0, 0), "P1 rotado: offset (0,0) (primera celda -> tope del 1x2)")
	_check(manip._agarre_rel_normal == Vector2i(0, 0), "canónico intacto tras rotar")
	_verificar_coherencia("P1 rotado")

	manip.cancelar()


func _p2_a_p5_segunda_celda(eN: InventoryEntry) -> void:
	print("-- 2. agarrar desde la SEGUNDA celda y rotar --")
	_check(manip.agarrar_en(Vector2i(1, 0)), "agarrar A en su segunda celda (1,0)")
	_check(manip._agarre_rel_normal == Vector2i(1, 0), "canónico de agarre = (1,0)")
	manip.mover_hover_a(Vector2i(2, 2))
	_check(manip.celda_destino_tentativa() == Vector2i(1, 2), "sin rotar: offset (1,0) -> destino (1,2)")
	_verificar_coherencia("P2 sin rotar")

	manip.rotar_tentativo()
	_check(manip.offset_agarre_actual() == Vector2i(0, 1),
		"P2 rotado: offset (0,1) (punta derecha del 2x1 -> celda de abajo del 1x2)")
	_check(manip.celda_destino_tentativa() == Vector2i(2, 1), "P2 rotado: ghost arriba del cursor -> destino (2,1)")
	_verificar_coherencia("P2 rotado  <-- este era el caso que driftaba")

	print("-- 3. mover el mouse post-rotación mantiene la coherencia --")
	manip.mover_hover_a(Vector2i(3, 3))
	_check(manip.offset_agarre_actual() == Vector2i(0, 1), "P3: mover el mouse no cambia el offset")
	_check(manip.celda_destino_tentativa() == Vector2i(3, 2), "P3: destino = (3,3) - (0,1)")
	_verificar_coherencia("P3 tras mover")

	print("-- 4. rotar de vuelta a la orientación original -> sin drift --")
	manip.rotar_tentativo()
	_check(not manip.rotacion_tentativa(), "de vuelta a la orientación normal")
	_check(manip.offset_agarre_actual() == Vector2i(1, 0), "P4: offset EXACTAMENTE el original (1,0)")
	_verificar_coherencia("P4 de vuelta a normal")

	print("-- 5. muchas rotaciones -> sin acumulación --")
	var esperado := [Vector2i(1, 0), Vector2i(0, 1)]   # par -> (1,0), impar -> (0,1)
	var drift := false
	for i in range(1, 21):
		manip.rotar_tentativo()
		if manip.offset_agarre_actual() != esperado[i % 2] \
		or not _cursor_dentro_del_ghost() \
		or manip._agarre_rel_normal != Vector2i(1, 0):
			drift = true
			printerr("  [detalle] rotación #%d -> offset %s (esperado %s)" % [i, manip.offset_agarre_actual(), esperado[i % 2]])
	_check(not drift, "P5: 20 rotaciones, offset alterna (1,0)/(0,1) sin desviarse; canónico fijo en (1,0)")
	_check(manip.offset_agarre_actual() == Vector2i(1, 0), "P5: tras 20 rotaciones (par), offset == original (1,0)")
	_check(manip.celda_destino_tentativa() == manip.celda_hover() - Vector2i(1, 0), "P5: destino coherente al final")

	manip.cancelar()


func _bonus_rotada_al_agarrar(eR: InventoryEntry) -> void:
	print("-- bonus: agarrar un ítem que YA está rotado --")
	view.set_inventory(inv_ang)
	_check(eR.rotated, "la entry del inv angosto está rotada (footprint 1x2)")

	_check(manip.agarrar_en(Vector2i(0, 1)), "agarrar la celda de abajo (0,1) del 1x2")
	_check(manip._agarre_rel_normal == Vector2i(1, 0), "canónico: celda rotada (0,1) -> (1,0) en frame normal")
	_check(manip.rotacion_tentativa(), "arranca con rotación tentativa = true (como la entry)")
	_check(manip.offset_agarre_actual() == Vector2i(0, 1), "offset efectivo == celda agarrada original (0,1)")
	manip.mover_hover_a(Vector2i(0, 3))
	_check(manip.celda_destino_tentativa() == Vector2i(0, 2), "destino = (0,3) - (0,1)")
	_verificar_coherencia("bonus rotado")

	manip.rotar_tentativo()
	_check(not manip.rotacion_tentativa(), "ahora sin rotar")
	_check(manip.offset_agarre_actual() == Vector2i(1, 0), "offset normal == canónico (1,0)")

	manip.rotar_tentativo()
	_check(manip.offset_agarre_actual() == Vector2i(0, 1), "de vuelta a (0,1), sin drift")
	manip.cancelar()


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
