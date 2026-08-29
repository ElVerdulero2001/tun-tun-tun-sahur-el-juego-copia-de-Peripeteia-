extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN. Inventory V1 · Paso 2.
##
## Verifica el mutador exclusivo nuevo `_reubicar_entry` y la señal
## `contenido_cambiado` de inventory.gd.
##
## Este arnés llama `_reubicar_entry` / `_quitar_entry` DIRECTAMENTE y trabaja
## con las InventoryEntry VIVAS (inv._entries) a propósito: es un test
## WHITE-BOX del mutador, no del flujo de gameplay. Acá se conserva la
## verificación de INV-09 "misma InventoryEntry viva" (que dejó de ser
## contrato público — get_entries() devuelve snapshots).
##
## El inventario se puebla SOLO por la ruta V0 (spawn WorldItemV2 + pickup).

@export var item_definition_test: ItemDefinition

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv_normal: InventoryV2 = $InventarioNormal      # 4x4
@onready var inv_angosto: InventoryV2 = $InventarioAngosto    # 1x4: fuerza rotación

@onready var punto_spawn: Marker3D = $PuntoSpawnMundo

const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

var _fallos := 0
var _checks := 0

var _emis_normal := 0
var _emis_angosto := 0


func _ready() -> void:
	print("\n===== INVENTORY V1 · PASO 2 · _reubicar_entry + contenido_cambiado =====")

	# Conectar contadores ANTES de sembrar, para contar también los
	# emits de _agregar_entry.
	inv_normal.contenido_cambiado.connect(func() -> void: _emis_normal += 1)
	inv_angosto.contenido_cambiado.connect(func() -> void: _emis_angosto += 1)

	var normal := _sembrar(inv_normal, 2)      # entries -> (0,0) y (2,0)
	var angosto := _sembrar(inv_angosto, 1)    # entry rotada -> (0,0)

	_test_agregar_emite_una_vez_por_alta()
	_test_reubicar_in_place(normal)
	_test_reubicar_conserva_entry_e_item(normal)
	_test_reubicar_no_cambia_size_ni_orden(normal)
	_test_reubicar_emite_una_vez_por_mutacion(normal)
	_test_reubicar_item_ausente(normal)
	_test_quitar_emite_una_vez(normal)
	_test_rotacion_via_reubicar(angosto)

	print("=====================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: PASO 2 OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos del Paso 2 de V1")
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
	return inventario._entries.duplicate()   # white-box: entries VIVAS


func _test_agregar_emite_una_vez_por_alta() -> void:
	print("-- _agregar_entry emite 1 vez por alta --")
	_check(_emis_normal == 2, "2 pickups en inv_normal -> 2 emisiones (%d)" % _emis_normal)
	_check(_emis_angosto == 1, "1 pickup en inv_angosto -> 1 emisión (%d)" % _emis_angosto)


func _test_reubicar_in_place(normal: Array[InventoryEntry]) -> void:
	print("-- _reubicar_entry cambia posición/rotación in-place --")
	var e0 := normal[0]
	inv_normal._reubicar_entry(e0.item_instance, Vector2i(0, 2), false)
	_check(e0.position == Vector2i(0, 2) and not e0.rotated, "movida a (0,2) sin rotar")
	inv_normal._reubicar_entry(e0.item_instance, Vector2i(2, 2), true)
	_check(e0.position == Vector2i(2, 2) and e0.rotated, "movida a (2,2) y rotada")
	# volver al origen para no ensuciar el resto
	inv_normal._reubicar_entry(e0.item_instance, Vector2i(0, 0), false)
	_check(e0.position == Vector2i(0, 0) and not e0.rotated, "vuelta a (0,0) sin rotar")


func _test_reubicar_conserva_entry_e_item(normal: Array[InventoryEntry]) -> void:
	print("-- _reubicar_entry conserva InventoryEntry, ItemInstance e instance_id --")
	var e0 := normal[0]
	var ii0 := e0.item_instance
	var id0 := ii0.instance_id

	var ret := inv_normal._reubicar_entry(ii0, Vector2i(0, 3), false)

	_check(ret == e0, "devuelve la MISMA InventoryEntry viva")
	_check(inv_normal._entries[0] == e0, "en _entries sigue la misma InventoryEntry viva (misma ref) — INV-09 white-box")
	_check(e0.item_instance == ii0, "misma ItemInstance (misma ref)")
	_check(e0.item_instance.instance_id == id0, "mismo instance_id (#%d)" % id0)

	inv_normal._reubicar_entry(ii0, Vector2i(0, 0), false)  # restaurar


func _test_reubicar_no_cambia_size_ni_orden(normal: Array[InventoryEntry]) -> void:
	print("-- _reubicar_entry no cambia _entries.size() ni el orden --")
	var size_antes := inv_normal.get_entries().size()
	var e0 := normal[0]
	var e1 := normal[1]

	inv_normal._reubicar_entry(e0.item_instance, Vector2i(1, 3), true)

	var ahora := inv_normal._entries
	_check(ahora.size() == size_antes, "size sin cambios (%d)" % ahora.size())
	_check(ahora[0] == e0 and ahora[1] == e1, "orden de _entries (vivas) sin cambios")

	inv_normal._reubicar_entry(e0.item_instance, Vector2i(0, 0), false)  # restaurar


func _test_reubicar_emite_una_vez_por_mutacion(normal: Array[InventoryEntry]) -> void:
	print("-- _reubicar_entry emite contenido_cambiado exactamente 1 vez por llamada --")
	var base := _emis_normal
	inv_normal._reubicar_entry(normal[0].item_instance, Vector2i(0, 2), false)
	_check(_emis_normal == base + 1, "1ra reubicación -> +1 emisión (%d)" % (_emis_normal - base))
	inv_normal._reubicar_entry(normal[0].item_instance, Vector2i(0, 0), false)
	_check(_emis_normal == base + 2, "2da reubicación -> +1 emisión (%d)" % (_emis_normal - base))


func _test_reubicar_item_ausente(normal: Array[InventoryEntry]) -> void:
	print("-- _reubicar_entry con item ausente: null, sin emisión, sin cambios --")
	var ajeno := ItemInstance.new(item_definition_test)  # nunca fue pickeado
	var base := _emis_normal
	var size_antes := inv_normal.get_entries().size()

	var ret := inv_normal._reubicar_entry(ajeno, Vector2i(3, 3), false)

	_check(ret == null, "devuelve null (item no está en el inventario)")
	_check(_emis_normal == base, "no emite contenido_cambiado (%d)" % (_emis_normal - base))
	_check(inv_normal.get_entries().size() == size_antes, "_entries.size() sin cambios")


func _test_quitar_emite_una_vez(normal: Array[InventoryEntry]) -> void:
	print("-- _quitar_entry: emite 1 vez y baja size; item ausente no emite --")
	var base := _emis_normal
	var size_antes := inv_normal.get_entries().size()

	var ajeno := ItemInstance.new(item_definition_test)
	inv_normal._quitar_entry(ajeno)
	_check(_emis_normal == base, "quitar item ausente -> sin emisión")
	_check(inv_normal.get_entries().size() == size_antes, "quitar item ausente -> size sin cambios")

	inv_normal._quitar_entry(normal[1].item_instance)
	_check(_emis_normal == base + 1, "quitar item real -> +1 emisión")
	_check(inv_normal.get_entries().size() == size_antes - 1, "quitar item real -> size -1")


func _test_rotacion_via_reubicar(angosto: Array[InventoryEntry]) -> void:
	print("-- _reubicar_entry sobre entry ya rotada (inv_angosto) --")
	var e := angosto[0]
	_check(e.rotated, "entry angosta arranca rotada")
	inv_angosto._reubicar_entry(e.item_instance, Vector2i(0, 2), true)
	_check(e.position == Vector2i(0, 2) and e.rotated, "movida a (0,2), sigue rotada")
	var celdas := inv_angosto.celdas_ocupadas_por(e)
	_check(celdas.has(Vector2i(0, 2)) and celdas.has(Vector2i(0, 3)), "ocupa (0,2),(0,3) -> %s" % [celdas])


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
