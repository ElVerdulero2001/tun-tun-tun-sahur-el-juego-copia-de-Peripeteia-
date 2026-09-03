extends Node3D

## ARNES DE TEST — NO ES PRODUCCION. SUA-1.6 B.
##
## Primer ASSET REAL migrado: scenes/props/dinamic/botella_standar_1.tscn ahora es
## un WorldItemV2 con `definition` = assets/data/items_v2/botella.tres, y
## ItemDefinition resuelve su escena mundial LAZY via world_scene_path (rompe el
## ciclo de parser prop.tscn <-> ItemDefinition.tres).
##
## El root es Node3D a proposito: get_tree().current_scene es este nodo y
## ItemDropper.soltar() valida current_scene as Node3D.
##
## Instancia botella_standar_1.tscn DIRECTAMENTE (nunca test_item_v0). Verifica:
##  - carga EN FRIO sin Parse Error (el ciclo del parser ya no existe);
##  - autoaprovisionamiento del ItemInstance en _ready();
##  - inyeccion previa tiene prioridad;
##  - ciclo real MUNDO -> INVENTARIO -> MUNDO -> INVENTARIO con PlayerV2;
##  - identidad estable de ItemInstance;
##  - la botella droppeada sigue siendo botella_standar_1 (no otro prefab);
##  - WorldItemV2 sigue neutral.

const BOTELLA_PATH := "res://scenes/props/dinamic/botella_standar_1.tscn"
const BOTELLA_DEF_PATH := "res://assets/data/items_v2/botella.tres"
const BOTELLA := preload(BOTELLA_PATH)
const BOTELLA_DEF := preload(BOTELLA_DEF_PATH)
const PLAYER_V2 := preload("res://scenes/player_v2/player_v2.tscn")
const TEST_ITEM_V0 := preload("res://scenes/test/test_item_v0.tscn")
const NOT_A_WORLD_ITEM_PATH := "res://scenes/test/fixtures/not_a_world_item.tscn"
const InventoryTestActor := preload("res://scenes/test/helpers/inventory_test_actor.gd")

var _fallos := 0
var _checks := 0
var _emis := 0


func _ready() -> void:
	print("\n===== SUA-1.6 B · botella real -> WorldItemV2 + ItemDefinition =====")

	await _carga_en_frio()
	await _autoaprovisionamiento()
	await _ciclo_real()
	await _hole_escena_no_world_item()

	print("=================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: SUA-1.6 B (botella real migrada) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de SUA-1.6 B")
	get_tree().quit(_fallos)


## Prueba de carga EN FRIO (BLOQUEANTE): fuerza re-parse profundo de la escena y
## TODAS sus dependencias (incluida botella.tres) -> si el ciclo del parser
## siguiera existiendo, aca aparecerian "Parse Error / Failed loading resource"
## y `definition` llegaria null.
func _carga_en_frio() -> void:
	print("-- carga EN FRIO (CACHE_MODE_IGNORE_DEEP): el ciclo del parser ya no existe --")

	var escena := ResourceLoader.load(BOTELLA_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	_check(escena != null, "1: ResourceLoader.load(botella_standar_1.tscn, IGNORE_DEEP) -> PackedScene valida")
	if escena == null:
		return

	var wf := escena.instantiate() as WorldItemV2
	_check(wf != null, "2: instantiate() -> WorldItemV2")
	if wf == null:
		return
	_check(wf.definition != null, "3: WorldItemV2.definition != null tras carga fria")
	_check(wf.definition != null and wf.definition.resource_path == BOTELLA_DEF_PATH, "4: definition ES botella.tres (por resource_path)")
	_check(wf.definition != null and wf.definition.id == &"botella_standar", "4: definition.id == &\"botella_standar\"")

	add_child(wf)
	await get_tree().process_frame
	_check(wf.item_instance != null, "5: entrar al arbol autoaprovisiono un ItemInstance")
	_check(wf.item_instance != null and wf.item_instance.definition == wf.definition, "6: ItemInstance.definition ES esa misma definicion (misma referencia)")

	var ws := wf.definition.get_world_scene() if wf.definition else null
	_check(ws != null and ws is PackedScene, "7: definition.get_world_scene() -> PackedScene valida")
	var wf2 := ws.instantiate() as WorldItemV2 if ws else null
	_check(wf2 != null, "8-9: esa PackedScene instancia y la instancia ES WorldItemV2")
	_check(wf2 != null and wf2.definition != null and wf2.definition.resource_path == BOTELLA_DEF_PATH, "10: la nueva instancia tambien trae definition = botella.tres")

	wf.queue_free()
	if wf2 != null:
		wf2.free()   # nunca entro al arbol
	await get_tree().process_frame


func _autoaprovisionamiento() -> void:
	print("-- A/B/C/D. autoaprovisionamiento (recursos cacheados) --")

	var b1 := BOTELLA.instantiate() as WorldItemV2
	_check(b1.item_instance == null, "A: sin ItemInstance ANTES de add_child")
	_check(b1.definition == BOTELLA_DEF, "B: definition exportado ES botella.tres (misma referencia cacheada)")
	add_child(b1)
	await get_tree().process_frame
	_check(b1.item_instance != null and b1.item_instance is ItemInstance, "A: tiene un ItemInstance tras entrar al arbol")
	_check(b1.item_instance != null and b1.item_instance.definition == BOTELLA_DEF, "B: item_instance.definition ES botella.tres")
	var ref1: ItemInstance = b1.item_instance
	await get_tree().process_frame
	_check(b1.item_instance == ref1, "C: una sola ItemInstance (no se recrea frame a frame)")

	# D. inyeccion previa gana
	var inyectada := ItemInstance.new(BOTELLA_DEF)
	var b2 := BOTELLA.instantiate() as WorldItemV2
	b2.item_instance = inyectada
	add_child(b2)
	await get_tree().process_frame
	_check(b2.item_instance == inyectada, "D: _ready NO reemplaza un ItemInstance inyectado")

	b1.queue_free()
	b2.queue_free()
	await get_tree().process_frame


func _ciclo_real() -> void:
	print("-- E..K. ciclo real MUNDO <-> INVENTARIO con PlayerV2 --")
	var pa := PLAYER_V2.instantiate()
	add_child(pa)
	await get_tree().process_frame
	var inv: InventoryV2 = pa.get_node("Inventory")
	var ui: CanvasLayer = pa.get_node("PlayerInventoryUI")
	var panel: InventoryPanel = ui.panel
	var manip: InventoryManipulator = panel.manipulator
	var dp: Marker3D = pa.get_node("Body/DropPoint")
	inv.contenido_cambiado.connect(func() -> void: _emis += 1)

	var botella_mundo := BOTELLA.instantiate() as WorldItemV2
	add_child(botella_mundo)
	await get_tree().process_frame
	var ii: ItemInstance = botella_mundo.item_instance
	_check(ii != null, "E: (setup) botella en el mundo autoaprovisiono su ItemInstance")

	# E. pickup real
	var ok: bool = botella_mundo._on_interact(Interaction.new(pa, &"usar"))
	await get_tree().process_frame
	_check(ok and inv.has_item(ii), "E: pickup real MUNDO -> InventoryV2 de A")
	_check(inv.get_entries().size() == 1, "E: exactamente 1 entry")
	_check(inv.get_entries()[0].item_instance.definition == BOTELLA_DEF, "E: la entry conserva botella.tres")
	_check(_custodia(ii, inv) == Vector2i(0, 1), "E: custodia XOR World=0 / Inv=1")

	# F. drop real por la cadena de UI real (manipulator -> panel -> PlayerInventoryUI -> ItemDropper)
	panel.abrir()
	_check(manip.agarrar_en(inv.get_entries()[0].position), "F: (setup) manipulator agarro la botella")
	var world0 := _contar_world_items()
	var dp_esperado := dp.global_position
	manip._resolver_click_held(Vector2(5000, 5000))
	var wi := _world_item_de(ii)
	_check(wi != null, "F: drop real InventoryV2 -> MUNDO produjo un WorldItemV2")
	_check(_contar_world_items() == world0 + 1, "F: exactamente 1 WorldItemV2 nuevo bajo la escena")
	_check(not inv.has_item(ii) and inv.get_entries().is_empty(), "F: la botella dejo el InventoryV2")
	_check(wi != null and wi.global_position.is_equal_approx(dp_esperado), "F: aparecio en el DropPoint de A (%s)" % dp_esperado)
	panel.cerrar()

	# G. misma ItemInstance
	_check(wi != null and wi.item_instance == ii, "G: WorldItemV2 resultante == MISMA referencia ItemInstance")

	# J. sigue siendo botella_standar_1 (no test_item_v0 ni otro prefab)
	_check(wi != null and wi.scene_file_path == BOTELLA_PATH, "J: la escena droppeada ES botella_standar_1.tscn (%s)" % (wi.scene_file_path if wi else "-"))
	_check(wi != null and wi.get_node_or_null("botella_horrible4") != null, "J: conserva el mesh de la botella")
	_check(wi != null and _tiene_collision_shape(wi), "J: conserva su collider")
	_check(wi != null and _tiene_interaction_component_v2(wi), "J: conserva su InteractionComponentV2 hijo directo")
	_check(wi != null and wi.definition == BOTELLA_DEF, "J: el WorldItemV2 nuevo tambien trae definition = botella.tres")

	# K. neutral
	_check(wi != null and not ("_authority" in wi), "K: el WorldItemV2 sigue NEUTRAL (sin _authority)")

	# H. re-pickup real
	var ok2: bool = wi._on_interact(Interaction.new(pa, &"usar"))
	await get_tree().process_frame
	_check(ok2 and inv.has_item(ii), "H: re-pickup real MUNDO -> InventoryV2 de A")
	_check(inv.get_entries().size() == 1, "H: 1 entry de nuevo")
	_check(inv.get_entries()[0].item_instance == ii, "H: la entry conserva la MISMA referencia ItemInstance")
	_check(_custodia(ii, inv) == Vector2i(0, 1), "H: custodia XOR World=0 / Inv=1")
	_check(not is_instance_valid(wi) or wi.is_queued_for_deletion(), "H: el WorldItemV2 droppeado fue consumido")

	# I. identidad estable en TODO el ciclo
	print("-- I. identidad estable: escena real -> Inv -> escena real -> Inv --")
	_check(inv.get_entries()[0].item_instance == ii, "I: el ItemInstance final ES el que autoaprovisiono la botella del mundo")


## M. Hole preexistente: si la world_scene de un tipo instancia un nodo que NO es
## WorldItemV2, el commit INVENTARIO->MUNDO debe: liberar el nodo huerfano,
## dejar el item en el inventario, y devolver null (sin duplicar ni corromper).
func _hole_escena_no_world_item() -> void:
	print("-- M. world_scene que NO instancia un WorldItemV2 --")
	var inv := InventoryV2.new()
	var authority := LocalAuthority.new()
	add_child(inv)
	add_child(authority)
	var actor: Node = InventoryTestActor.crear(inv, authority)
	add_child(actor)
	await get_tree().process_frame

	# definicion cuya escena mundial es un Node3D pelado (no WorldItemV2)
	var def_mala := ItemDefinition.new()
	def_mala.id = &"def_escena_no_world_item"
	def_mala.nombre = "def con world_scene invalida"
	def_mala.world_scene_path = NOT_A_WORLD_ITEM_PATH
	def_mala.grid_width = 1
	def_mala.grid_height = 1

	# meterla al inventario por la ruta real: un WorldItemV2 (test_item_v0) que
	# lleva un ItemInstance de esa definicion mala
	var wi_seed := TEST_ITEM_V0.instantiate() as WorldItemV2
	var ii_mala := ItemInstance.new(def_mala)
	wi_seed.item_instance = ii_mala
	add_child(wi_seed)
	var seeded: bool = wi_seed._on_interact(Interaction.new(actor, &"usar"))
	await get_tree().process_frame
	_check(seeded and inv.has_item(ii_mala), "M: (setup) item con definicion mala en el inventario")

	var w0 := _contar_world_items()
	var devuelto: Variant = authority.solicitar_devolucion(ii_mala, inv, self, Vector3.ZERO)

	_check(devuelto == null, "M: solicitar_devolucion devuelve null (la escena no produjo un WorldItemV2)")
	_check(inv.has_item(ii_mala), "M: el item SIGUE en el inventario (custodia preservada)")
	_check(inv.get_entries().size() == 1, "M: el inventario no cambio de tamano")
	_check(_contar_world_items() == w0, "M: NO aparecio ningun WorldItemV2 nuevo")
	_check(_contar_nodos_llamados("NotAWorldItem") == 0, "M: el nodo huerfano fue liberado (0 'NotAWorldItem' en el arbol)")

	inv.queue_free()
	authority.queue_free()
	actor.queue_free()
	await get_tree().process_frame


func _contar_nodos_llamados(nombre: String) -> int:
	var n := 0
	var pila: Array[Node] = [get_tree().root]
	while not pila.is_empty():
		var nodo: Node = pila.pop_back()
		if nodo.name == nombre:
			n += 1
		pila.append_array(nodo.get_children())
	return n


## (World, Inventory) para `ii` contra UN inventario.
func _custodia(ii: ItemInstance, inv: InventoryV2) -> Vector2i:
	var w := 0
	for wi in _todos_world_items():
		if wi.item_instance == ii:
			w += 1
	var i := 0
	for e in inv.get_entries():
		if e.item_instance == ii:
			i += 1
	return Vector2i(w, i)


func _world_item_de(ii: ItemInstance) -> WorldItemV2:
	for wi in _todos_world_items():
		if wi.item_instance == ii:
			return wi
	return null


func _contar_world_items() -> int:
	return _todos_world_items().size()


func _todos_world_items() -> Array[WorldItemV2]:
	var res: Array[WorldItemV2] = []
	var pila: Array[Node] = [get_tree().root]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is WorldItemV2 and not n.is_queued_for_deletion():
			res.append(n)
		pila.append_array(n.get_children())
	return res


func _tiene_interaction_component_v2(nodo: Node) -> bool:
	for child in nodo.get_children():
		if child is InteractionComponentV2:
			return true
	return false


func _tiene_collision_shape(nodo: Node) -> bool:
	for child in nodo.get_children():
		if child is CollisionShape3D:
			return true
	return false


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
