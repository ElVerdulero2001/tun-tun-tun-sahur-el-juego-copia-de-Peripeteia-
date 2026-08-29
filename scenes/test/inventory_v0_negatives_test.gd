extends Node3D

## ARNÉS DE TEST — NO ES PRODUCCIÓN.
##
## Cubre los criterios de aceptación NEGATIVOS de Inventory V0:
##   1. pickup cuando el inventario no tiene espacio -> falla.
##   2. tras un pickup fallido, el WorldItem sigue en el mundo.
##   3. devolución al mundo que no puede completarse -> el item permanece
##      bajo custodia del inventario.
##   4. tras CADA operación (completada o abortada) se verifica la
##      custodia del ItemInstance:
##        (World=1, Inventory=0)  XOR  (World=0, Inventory=1)
##        nunca 1/1, nunca 0/0.
##
## Toda la lógica se maneja programáticamente a través de LocalAuthority,
## exactamente igual que el arnés de ruta feliz (inventory_v0_test_scene.gd
## -> _solicitar_devolucion_debug). No se toca WorldItemV2, TransferOperation,
## InventoryEntry ni la generación de IDs: solo se los EJERCITA.
##
## La instrumentación (contador de custodia recorriendo el árbol, ItemDefinition
## construida en memoria sin world_scene) es exclusiva de test.

@export var item_definition_test: ItemDefinition

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inventario_lleno: InventoryV2 = $InventarioLleno      # grid 1x1: nada entra
@onready var inventario_normal: InventoryV2 = $InventarioNormal    # grid 4x4
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo

const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

var _fallos: int = 0
var _checks: int = 0


func _ready() -> void:
	print("\n========== INVENTORY V0 — CRITERIOS DE ACEPTACIÓN NEGATIVOS ==========")
	await _caso_1_y_2_pickup_sin_espacio()
	await _caso_3_devolucion_no_completable()
	await _caso_4_ciclo_completo_invariante()
	print("=====================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: TODOS LOS CRITERIOS NEGATIVOS OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron criterios negativos de Inventory V0")
	get_tree().quit(_fallos)


## ── Caso 1 + 2 ──────────────────────────────────────────────────────
## Pickup contra un inventario 1x1: el item de prueba (2x1, rotable a 1x2)
## no entra ni rotado. El pickup debe fallar y el WorldItem debe seguir
## exactamente donde estaba, en el mundo.
func _caso_1_y_2_pickup_sin_espacio() -> void:
	print("\n-- Caso 1+2: pickup sin espacio; el objeto debe permanecer en el mundo --")
	var actor := _actor_pickup(inventario_lleno)

	var wi := _spawn_world_item(item_definition_test)
	var item: ItemInstance = wi.item_instance
	await _verificar_custodia("caso1 pre-pickup", item, inventario_lleno, 1, 0)

	var resultado: bool = wi._on_interact(Interaction.new(actor, &"usar"))

	_check(resultado == false, "Caso 1: el pickup devuelve false (inventario 1x1 sin espacio)")
	_check(inventario_lleno.get_entries().is_empty(), "Caso 1: el inventario 1x1 sigue vacío")
	_check(
		is_instance_valid(wi) and wi.is_inside_tree() and not wi.is_queued_for_deletion(),
		"Caso 2: el WorldItem sigue vivo y dentro del árbol del mundo"
	)

	await _verificar_custodia("caso1 post-pickup-fallido", item, inventario_lleno, 1, 0)

	wi.queue_free()
	await get_tree().process_frame


## ── Caso 3 ──────────────────────────────────────────────────────────
## El item entra bien al inventario 4x4. Luego se intenta devolverlo al
## mundo con una definición cuya world_scene es null: TransferOperation
## .validate() falla en la guarda "sin world_scene valida para instanciar"
## y commit() no se llama. El item debe quedar bajo custodia del inventario.
func _caso_3_devolucion_no_completable() -> void:
	print("\n-- Caso 3: devolución imposible (definición sin world_scene); el item permanece en inventario --")
	var actor := _actor_pickup(inventario_normal)

	var def_sin_escena := ItemDefinition.new()
	def_sin_escena.id = &"test_item_sin_world_scene"
	def_sin_escena.nombre = "Item sin world_scene (solo test)"
	def_sin_escena.grid_width = 1
	def_sin_escena.grid_height = 1
	# world_scene queda null a propósito.

	# El caparazón físico se toma de la definición válida; el ItemInstance
	# lleva la definición defectuosa, que es lo que se está probando.
	var wi: WorldItemV2 = item_definition_test.world_scene.instantiate()
	wi.item_instance = ItemInstance.new(def_sin_escena)
	add_child(wi)
	wi.global_position = punto_spawn.global_position
	var item: ItemInstance = wi.item_instance

	var ok_pickup: bool = wi._on_interact(Interaction.new(actor, &"usar"))
	_check(ok_pickup, "Caso 3 (setup): pickup del item 1x1 al inventario 4x4 exitoso")
	await _verificar_custodia("caso3 post-pickup", item, inventario_normal, 0, 1)

	var devuelto: Variant = authority.solicitar_devolucion(
		item, inventario_normal, self, punto_spawn.global_position
	)

	_check(devuelto == null, "Caso 3: solicitar_devolucion devuelve null (world_scene == null)")
	_check(inventario_normal.has_item(item), "Caso 3: el item permanece bajo custodia del inventario")

	await _verificar_custodia("caso3 post-devolución-fallida", item, inventario_normal, 0, 1)


## ── Caso 4 ──────────────────────────────────────────────────────────
## Ciclo completo (mundo -> inventario -> mundo) con verificación explícita
## de custodia después de cada operación COMPLETADA.
func _caso_4_ciclo_completo_invariante() -> void:
	print("\n-- Caso 4: ciclo completo, invariante de custodia tras cada operación --")
	var actor := _actor_pickup(inventario_normal)

	var wi := _spawn_world_item(item_definition_test)
	var item: ItemInstance = wi.item_instance
	await _verificar_custodia("caso4 inicial (en el mundo)", item, inventario_normal, 1, 0)

	var ok_pickup: bool = wi._on_interact(Interaction.new(actor, &"usar"))
	_check(ok_pickup, "Caso 4: pickup exitoso")
	await _verificar_custodia("caso4 tras pickup", item, inventario_normal, 0, 1)

	var nuevo: Variant = authority.solicitar_devolucion(
		item, inventario_normal, self, punto_spawn.global_position
	)
	_check(nuevo != null, "Caso 4: devolución exitosa")
	await _verificar_custodia("caso4 tras devolución", item, inventario_normal, 1, 0)


## ── Instrumentación de test ─────────────────────────────────────────

func _spawn_world_item(definicion: ItemDefinition) -> WorldItemV2:
	var wi: WorldItemV2 = definicion.world_scene.instantiate()
	wi.item_instance = ItemInstance.new(definicion)
	add_child(wi)
	wi.global_position = punto_spawn.global_position
	return wi


## C1: actor de prueba con InventoryReceiver hijo directo, equivalente a como
## PlayerV2 expone la capacidad. Reemplaza el par pre-C1
## authority.set_inventory_receptor(inv) + wi.setup(authority).
func _actor_pickup(inventario: InventoryV2) -> Node:
	var actor := InventoryTestActor.crear(inventario, authority)
	add_child(actor)
	return actor


## Cuenta cuántos WorldItemV2 del árbol representan a ESTE ItemInstance.
## Ignora los que ya fueron marcados con queue_free().
func _contar_en_mundo(item: ItemInstance) -> int:
	var n := 0
	var pila: Array[Node] = [get_tree().root]
	while not pila.is_empty():
		var nodo: Node = pila.pop_back()
		if nodo is WorldItemV2 and not nodo.is_queued_for_deletion():
			if (nodo as WorldItemV2).item_instance == item:
				n += 1
		pila.append_array(nodo.get_children())
	return n


func _contar_en_inventario(item: ItemInstance, inventario: InventoryV2) -> int:
	var n := 0
	for entry in inventario.get_entries():
		if entry.item_instance == item:
			n += 1
	return n


func _verificar_custodia(
	etiqueta: String, item: ItemInstance, inventario: InventoryV2,
	esperado_mundo: int, esperado_inv: int
) -> void:
	# Deja que queue_free()/add_child() de la operación previa se asienten.
	await get_tree().process_frame

	var w := _contar_en_mundo(item)
	var i := _contar_en_inventario(item, inventario)

	_check(
		w == esperado_mundo and i == esperado_inv,
		"%s -> custodia World=%d / Inventory=%d (esperado %d/%d)" % [etiqueta, w, i, esperado_mundo, esperado_inv]
	)
	_check(
		(w == 1 and i == 0) or (w == 0 and i == 1),
		"%s -> invariante de custodia: ni 1/1 ni 0/0 (World=%d / Inventory=%d)" % [etiqueta, w, i]
	)


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
