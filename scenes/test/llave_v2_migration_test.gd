extends Node3D

## ARNES DE TEST — NO ES PRODUCCION. SUA-1.6 D.
##
## Tercer ASSET REAL migrado: scenes/props/dinamic/llave_comun_1.tscn ahora es un
## WorldItemV2 con `definition` = assets/data/items_v2/llave.tres.
## Mismo patron que botella (B) y sable (C). Este test se concentra en:
##  - carga sin Parse Error;
##  - autoaprovisionamiento;
##  - footprint 1x1 y can_rotate = FALSE (la rotacion se rechaza);
##  - ciclo real MUNDO -> INVENTARIO -> MUNDO -> INVENTARIO con identidad estable;
##  - el WorldItemV2 devuelto ES llave_comun_1 (mesh + collider + InteractionComponentV2).
##
## NO prueba "la llave abre la puerta": esa feature SÍ existe desde la
## migración de door_rust_01 a InteractionComponentV2 (puerta.gd consulta
## InventoryV2 vía InventoryReceiver), pero no hay todavía un arnés
## automatizado dedicado a la puerta — se verificó manualmente/headless
## fuera de esta suite.
##
## Root Node3D a proposito: get_tree().current_scene = este nodo (ItemDropper valida Node3D).

const LLAVE_PATH := "res://scenes/props/dinamic/llave_comun_1.tscn"
const LLAVE_DEF_PATH := "res://assets/data/items_v2/llave.tres"
const LLAVE := preload(LLAVE_PATH)
const LLAVE_DEF := preload(LLAVE_DEF_PATH)
const PLAYER_V2 := preload("res://scenes/player_v2/player_v2.tscn")

var _fallos := 0
var _checks := 0
var _rechazos_rotacion := 0


func _ready() -> void:
	print("\n===== SUA-1.6 D · llave real -> WorldItemV2 + ItemDefinition =====")
	await _carga_y_autoaprovisionamiento()
	await _ciclo_real()

	print("=================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: SUA-1.6 D (llave real migrada) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de SUA-1.6 D")
	get_tree().quit(_fallos)


func _carga_y_autoaprovisionamiento() -> void:
	print("-- carga fria + autoaprovisionamiento --")
	var escena := ResourceLoader.load(LLAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	_check(escena != null, "carga: llave_comun_1.tscn carga (IGNORE_DEEP) sin Parse Error")
	if escena == null:
		return

	var k0 := LLAVE.instantiate() as WorldItemV2
	_check(k0 != null, "root ES WorldItemV2")
	_check(k0 != null and k0.definition == LLAVE_DEF, "definition ES llave.tres (misma referencia cacheada)")
	_check(k0 != null and k0.item_instance == null, "sin ItemInstance ANTES de add_child")
	add_child(k0)
	await get_tree().process_frame
	_check(k0.item_instance != null and k0.item_instance is ItemInstance, "autoaprovisiono EXACTAMENTE un ItemInstance")
	var ref0 := k0.item_instance
	await get_tree().process_frame
	_check(k0.item_instance == ref0, "no se recrea frame a frame")
	_check(k0.item_instance.definition == LLAVE_DEF, "item_instance.definition ES llave.tres")
	_check(LLAVE_DEF.grid_width == 1 and LLAVE_DEF.grid_height == 1, "footprint definido 1x1")
	_check(LLAVE_DEF.can_rotate == false, "can_rotate = false")
	k0.queue_free()
	await get_tree().process_frame


func _ciclo_real() -> void:
	print("-- ciclo real MUNDO <-> INVENTARIO con PlayerV2 --")
	var pa := PLAYER_V2.instantiate()
	add_child(pa)
	await get_tree().process_frame
	var inv: InventoryV2 = pa.get_node("Inventory")
	var authority: LocalAuthority = pa.get_node("InventoryAuthority")
	var ui: CanvasLayer = pa.get_node("PlayerInventoryUI")
	var panel: InventoryPanel = ui.panel
	var manip: InventoryManipulator = panel.manipulator
	var dp: Marker3D = pa.get_node("Body/DropPoint")

	var llave_mundo := LLAVE.instantiate() as WorldItemV2
	add_child(llave_mundo)
	await get_tree().process_frame
	var ii: ItemInstance = llave_mundo.item_instance
	_check(ii != null, "(setup) llave en el mundo autoaprovisiono su ItemInstance")

	# pickup real
	var ok: bool = llave_mundo._on_interact(Interaction.new(pa, &"usar"))
	await get_tree().process_frame
	_check(ok and inv.has_item(ii), "pickup real MUNDO -> InventoryV2")
	_check(inv.get_entries().size() == 1, "1 entry")

	# footprint 1x1 sin rotar
	var e := inv.get_entries()[0]
	_check(e.get_footprint() == Vector2i(1, 1) and not e.rotated, "entry ocupa 1x1 (sin rotar)")

	# can_rotate = false: rotacion RECHAZADA por LocalAuthority/TransferOperation
	var snap_pos := inv.get_entries()[0].position
	var ok_rot: bool = authority.solicitar_reubicacion(ii, inv, snap_pos, true)
	_check(not ok_rot, "reubicacion CON rotacion -> false (can_rotate=false)")
	_check(not inv.get_entries()[0].rotated, "la entry NO se rotó")
	# can_rotate = false: rotar_tentativo() del manipulator tambien devuelve false
	panel.abrir()
	_check(manip.agarrar_en(inv.get_entries()[0].position), "(setup) manipulator agarro la llave")
	var rechazo_lambda := func(_ent: InventoryEntry) -> void: _rechazos_rotacion += 1
	manip.rotacion_rechazada.connect(rechazo_lambda)
	_check(not manip.rotar_tentativo(), "manipulator.rotar_tentativo() -> false")
	_check(_rechazos_rotacion == 1, "emitio rotacion_rechazada exactamente 1 vez")
	manip.rotacion_rechazada.disconnect(rechazo_lambda)

	# movimiento valido SIN rotar (dentro de la grilla) funciona
	_check(inv.get_entries()[0].item_instance == ii, "misma referencia ItemInstance tras el intento de rotar")
	manip.cancelar()
	var ok_mov: bool = authority.solicitar_reubicacion(ii, inv, Vector2i(3, 3), false)
	_check(ok_mov and inv.get_entries()[0].position == Vector2i(3, 3), "reubicacion valida sin rotar a (3,3) -> ok")
	authority.solicitar_reubicacion(ii, inv, Vector2i(0, 0), false)

	# drop real por la cadena de UI real
	_check(manip.agarrar_en(inv.get_entries()[0].position), "(setup) manipulator agarro la llave (para drop)")
	var world0 := _contar_world_items()
	var dp_esperado := dp.global_position
	manip._resolver_click_held(Vector2(5000, 5000))
	var wi := _world_item_de(ii)
	_check(wi != null, "drop real InventoryV2 -> MUNDO produjo un WorldItemV2")
	_check(_contar_world_items() == world0 + 1, "exactamente 1 WorldItemV2 nuevo")
	_check(not inv.has_item(ii) and inv.get_entries().is_empty(), "la llave dejo el InventoryV2")
	_check(wi != null and wi.global_position.is_equal_approx(dp_esperado), "aparecio en el DropPoint (%s)" % dp_esperado)
	panel.cerrar()

	# el WorldItemV2 devuelto ES llave_comun_1, misma ItemInstance, neutral, estructura
	_check(wi != null and wi.scene_file_path == LLAVE_PATH, "la escena reaparecida ES llave_comun_1.tscn")
	_check(wi != null and wi.item_instance == ii, "MISMA referencia ItemInstance")
	_check(wi != null and wi.definition == LLAVE_DEF, "el WorldItemV2 nuevo trae definition = llave.tres")
	_check(wi != null and not ("_authority" in wi), "el WorldItemV2 sigue NEUTRAL")
	_check(wi != null and wi.get_node_or_null("llave2") != null, "conserva el mesh (llave2)")
	_check(wi != null and _tiene(wi, "CollisionShape3D"), "conserva su collider")
	_check(wi != null and _tiene_interaction_component_v2(wi), "conserva su InteractionComponentV2 hijo directo")

	# re-pickup real
	var ok2: bool = wi._on_interact(Interaction.new(pa, &"usar"))
	await get_tree().process_frame
	_check(ok2 and inv.has_item(ii), "re-pickup real MUNDO -> InventoryV2")
	_check(inv.get_entries()[0].item_instance == ii, "la entry conserva la MISMA referencia ItemInstance")
	_check(not is_instance_valid(wi) or wi.is_queued_for_deletion(), "el WorldItemV2 droppeado fue consumido")

	# identidad estable de punta a punta
	_check(inv.get_entries()[0].item_instance == ii,
		"identidad estable: MUNDO -> INV -> MUNDO -> INV, misma referencia ItemInstance")


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


func _tiene(nodo: Node, clase: String) -> bool:
	for child in nodo.get_children():
		if child.get_class() == clase:
			return true
	return false


func _tiene_interaction_component_v2(nodo: Node) -> bool:
	for child in nodo.get_children():
		if child is InteractionComponentV2:
			return true
	return false


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
