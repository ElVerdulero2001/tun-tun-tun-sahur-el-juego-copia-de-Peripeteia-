extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory V1 · Paso 4.
##
## Verifica InventoryGridView como vista PURA de un InventoryV2:
##   1. cantidad de celdas (grid_width * grid_height);
##   2. posición visual de las entries (rect en píxeles);
##   3. footprint normal y rotado;
##   4. la vista se re-renderiza al recibir contenido_cambiado;
##   5. usar/abrir la vista NO muta el modelo.
##
## El inventario se puebla SOLO por la ruta V0. Los movimientos del test 4
## se hacen por la vía autorizada (LocalAuthority.solicitar_reubicacion),
## nunca tocando el modelo desde la vista.

@export var item_definition_test: ItemDefinition

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv_normal: InventoryV2 = $InvNormal       # 4x4
@onready var inv_angosto: InventoryV2 = $InvAngosto     # 1x4: fuerza rotación

@onready var punto_spawn: Marker3D = $PuntoSpawnMundo
@onready var view: InventoryGridView = $CanvasLayer/InventoryGridView

const CELL := 32

const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

var _fallos := 0
var _checks := 0
var _emis_normal := 0
var _emis_angosto := 0


func _ready() -> void:
	print("\n===== INVENTORY V1 · PASO 4 · VISTA PURA (InventoryGridView) =====")
	view.cell_size = CELL

	var normal := _sembrar(inv_normal, 2)      # A -> (0,0), B -> (2,0)
	var angosto := _sembrar(inv_angosto, 1)    # C -> (0,0) rotada

	# Spies DESPUÉS de sembrar -> baseline 0.
	inv_normal.contenido_cambiado.connect(func() -> void: _emis_normal += 1)
	inv_angosto.contenido_cambiado.connect(func() -> void: _emis_angosto += 1)

	var snap_normal := _snap(inv_normal)
	var snap_angosto := _snap(inv_angosto)

	_test_cantidad_celdas()
	_test_posicion_entries(normal)
	_test_footprint_normal_y_rotado()
	_test_no_muta_el_modelo(snap_normal, snap_angosto)
	_test_actualiza_tras_contenido_cambiado(normal)

	print("================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: PASO 4 OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos del Paso 4 de V1")
	get_tree().quit(_fallos)


func _sembrar(inventario: InventoryV2, cantidad: int) -> Array[InventoryEntry]:
	var _actor := _actor_pickup(inventario)
	for i in range(cantidad):
		var wi: WorldItemV2 = item_definition_test.world_scene.instantiate()
		wi.item_instance = ItemInstance.new(item_definition_test)
		add_child(wi)
		wi.global_position = punto_spawn.global_position
		var ok: bool = wi._on_interact(Interaction.new(_actor, &"usar"))
		_check(ok, "siembra: pickup #%d en %s exitoso" % [i + 1, inventario.name])
	return inventario.get_entries()


func _test_cantidad_celdas() -> void:
	print("-- 1. cantidad de celdas --")
	view.set_inventory(inv_normal)
	_check(view.cantidad_celdas() == 16, "inv 4x4 -> 16 celdas (%d)" % view.cantidad_celdas())
	_check(view.custom_minimum_size == Vector2(4 * CELL, 4 * CELL),
		"custom_minimum_size 4x4 = %s" % view.custom_minimum_size)
	view.set_inventory(inv_angosto)
	_check(view.cantidad_celdas() == 4, "inv 1x4 -> 4 celdas (%d)" % view.cantidad_celdas())
	_check(view.custom_minimum_size == Vector2(1 * CELL, 4 * CELL),
		"custom_minimum_size 1x4 = %s" % view.custom_minimum_size)


func _test_posicion_entries(normal: Array[InventoryEntry]) -> void:
	print("-- 2. posición visual de entries --")
	view.set_inventory(inv_normal)
	var eA := normal[0]   # (0,0) 2x1
	var eB := normal[1]   # (2,0) 2x1
	_check(view.rect_de_entry(eA) == Rect2(0, 0, 2 * CELL, 1 * CELL),
		"entryA @ (0,0) -> %s" % view.rect_de_entry(eA))
	_check(view.rect_de_entry(eB) == Rect2(2 * CELL, 0, 2 * CELL, 1 * CELL),
		"entryB @ (2,0) -> %s" % view.rect_de_entry(eB))
	_check(view.rect_de_celda(Vector2i(2, 1)) == Rect2(2 * CELL, 1 * CELL, CELL, CELL),
		"celda (2,1) -> %s" % view.rect_de_celda(Vector2i(2, 1)))


func _test_footprint_normal_y_rotado() -> void:
	print("-- 3. footprint normal y rotado --")
	view.set_inventory(inv_normal)
	var la_n := view.layout_entries()
	_check(la_n.size() == 2, "inv_normal: layout con 2 entries (%d)" % la_n.size())
	_check(la_n[0]["footprint"] == Vector2i(2, 1) and not la_n[0]["rotated"], "entryA footprint 2x1 sin rotar")
	_check(la_n[0]["rect"].size == Vector2(2 * CELL, 1 * CELL), "entryA rect size = %s" % la_n[0]["rect"].size)

	view.set_inventory(inv_angosto)
	var la_a := view.layout_entries()
	_check(la_a.size() == 1, "inv_angosto: layout con 1 entry (%d)" % la_a.size())
	_check(la_a[0]["rotated"], "entryC rotada")
	_check(la_a[0]["footprint"] == Vector2i(1, 2), "entryC footprint 1x2 (rotado)")
	_check(la_a[0]["rect"] == Rect2(0, 0, 1 * CELL, 2 * CELL), "entryC rect = %s" % la_a[0]["rect"])


func _test_no_muta_el_modelo(snap_normal: Array, snap_angosto: Array) -> void:
	print("-- 5. usar la vista NO muta el modelo --")
	view.set_inventory(inv_normal)
	view.cantidad_celdas()
	view.layout_entries()
	view.rect_de_celda(Vector2i(0, 0))
	view.rect_de_celda(Vector2i(3, 3))
	view.set_inventory(inv_angosto)
	view.layout_entries()
	view.set_inventory(inv_normal)

	_check(_emis_normal == 0, "inv_normal: contenido_cambiado NO se emitió por la vista (%d)" % _emis_normal)
	_check(_emis_angosto == 0, "inv_angosto: contenido_cambiado NO se emitió por la vista (%d)" % _emis_angosto)
	_check(_igual_al_snap(inv_normal, snap_normal), "inv_normal: entries / posición / rotación / instance_id / size intactos")
	_check(_igual_al_snap(inv_angosto, snap_angosto), "inv_angosto: entries / posición / rotación / instance_id / size intactos")


## Rect que la vista dibuja para la entry ubicada AHORA en `pos`. layout_entries()
## ya no expone identidad (D8): se localiza por position, que es exactamente lo
## que este test controla al mover A a celdas conocidas (B no se mueve nunca).
func _rect_de_pos(pos: Vector2i) -> Rect2:
	for d in view.layout_entries():
		if d["position"] == pos:
			return d["rect"]
	return Rect2()


func _test_actualiza_tras_contenido_cambiado(normal: Array[InventoryEntry]) -> void:
	print("-- 4. la vista se re-renderiza al recibir contenido_cambiado --")
	view.set_inventory(inv_normal)
	var iiA: ItemInstance = normal[0].item_instance
	var r0 := view.refrescos
	_check(_rect_de_pos(Vector2i(0, 0)) == Rect2(0, 0, 2 * CELL, 1 * CELL), "pre: entryA en (0,0)")

	var ok1: bool = authority.solicitar_reubicacion(iiA, inv_normal, Vector2i(0, 2), false)
	_check(ok1, "mover A a (0,2) -> true")
	_check(view.refrescos == r0 + 1, "la vista se re-renderizó 1 vez (%d -> %d)" % [r0, view.refrescos])
	_check(_rect_de_pos(Vector2i(0, 2)) == Rect2(0, 2 * CELL, 2 * CELL, 1 * CELL), "post: rect de A refleja (0,2) = %s" % _rect_de_pos(Vector2i(0, 2)))

	var ok2: bool = authority.solicitar_reubicacion(iiA, inv_normal, Vector2i(2, 1), true)
	_check(ok2, "rotar + mover A a (2,1) -> true")
	_check(view.refrescos == r0 + 2, "otra re-renderización (%d)" % view.refrescos)
	_check(_rect_de_pos(Vector2i(2, 1)) == Rect2(2 * CELL, 1 * CELL, 1 * CELL, 2 * CELL), "rect de A rotado = %s" % _rect_de_pos(Vector2i(2, 1)))

	# Al cambiar de inventario, la vista se desengancha del anterior.
	view.set_inventory(inv_angosto)
	var r_ang := view.refrescos
	authority.solicitar_reubicacion(iiA, inv_normal, Vector2i(0, 0), false)
	_check(view.refrescos == r_ang, "tras cambiar de inventario la vista ya NO reacciona a inv_normal (%d)" % view.refrescos)


func _snap(inv: InventoryV2) -> Array:
	var s: Array = []
	for e in inv.get_entries():
		s.append([e.item_instance, e.position, e.rotated, e.item_instance.instance_id])
	return s


func _igual_al_snap(inv: InventoryV2, snap: Array) -> bool:
	var live := inv.get_entries()
	if live.size() != snap.size():
		return false
	for i in range(live.size()):
		var r: Array = snap[i]
		if live[i].item_instance != r[0] \
		or live[i].position != r[1] \
		or live[i].rotated != r[2] \
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


## C1: actor de prueba con InventoryReceiver hijo directo, equivalente a como
## PlayerV2 expone la capacidad. Reemplaza el par pre-C1
## authority.set_inventory_receptor(inv) + wi.setup(authority).
func _actor_pickup(inventario: InventoryV2) -> Node:
	var actor := InventoryTestActor.crear(inventario, authority)
	add_child(actor)
	return actor
