extends Node3D

## ARNES DE TEST — NO ES PRODUCCION.
##
## Reparacion de scenes/props/dinamic/granada_01.tscn: quedo estructuralmente
## invalida en 6ec7dca (perdio su script propietario V1 sin reemplazo al
## agregarsele un InteractionComponent legacy) y nunca estuvo instanciada en
## ninguna escena real. Ahora es un WorldItemV2 con `definition` =
## assets/data/items_v2/granada.tres, mismo patron que llave/sable/botella.
##
## Este arnes NO repite el ciclo completo (rotacion, drop-por-UI, re-pickup,
## identidad estable) que llave/sable/botella_v2_migration_test.gd ya cubren
## sobre el MISMO world_item.gd/InventoryV2/LocalAuthority — esos invariantes
## no son especificos de la granada. Se concentra solo en lo que esta
## reparacion puntual necesita demostrar:
##  - la raiz ES WorldItemV2;
##  - tiene exactamente UN InteractionComponentV2 hijo directo (el contrato
##    legacy InteractionComponent ya no existe como clase — la garantia de
##    ausencia es estructural, no requiere un chequeo negativo aparte);
##  - un pickup real entra a InventoryV2;
##  - el WorldItem desaparece del mundo tras el commit exitoso;
##  - Inventario (autoload V1) nunca interviene.

const GRANADA_PATH := "res://scenes/props/dinamic/granada_01.tscn"
const GRANADA_DEF_PATH := "res://assets/data/items_v2/granada.tres"
const GRANADA := preload(GRANADA_PATH)
const GRANADA_DEF := preload(GRANADA_DEF_PATH)
const PLAYER_V2 := preload("res://scenes/player_v2/player_v2.tscn")

var _fallos := 0
var _checks := 0


func _ready() -> void:
	print("\n===== Reparacion granada_01 -> WorldItemV2 + ItemDefinition =====")
	await _estructura_y_pickup_real()

	print("=================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: granada_01 reparada OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de reparacion de granada_01")
	get_tree().quit(_fallos)


func _estructura_y_pickup_real() -> void:
	print("-- carga fria + estructura --")
	var escena := ResourceLoader.load(GRANADA_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	_check(escena != null, "1: granada_01.tscn carga (IGNORE_DEEP) sin Parse Error")

	var g0 := GRANADA.instantiate()
	_check(g0 is WorldItemV2, "2: la raiz ES WorldItemV2")
	_check(g0.definition == GRANADA_DEF, "3: definition ES granada.tres (misma referencia cacheada)")

	var comps_v2 := 0
	for child in g0.get_children():
		if child is InteractionComponentV2:
			comps_v2 += 1
	_check(comps_v2 == 1, "4: exactamente UN InteractionComponentV2 hijo directo (encontrados: %d)" % comps_v2)

	add_child(g0)
	await get_tree().process_frame
	_check(g0.item_instance != null, "5: autoaprovisiono un ItemInstance")

	print("-- pickup real MUNDO -> InventoryV2 con PlayerV2 --")
	var pa := PLAYER_V2.instantiate()
	add_child(pa)
	await get_tree().process_frame
	var inv: InventoryV2 = pa.get_node("Inventory")

	var comp := g0.get_node("InteractionComponentV2") as InteractionComponentV2
	var ok: bool = comp.recibir_interaccion(Interaction.new(pa, &"usar"))
	await get_tree().process_frame
	_check(ok == true, "6: pickup real -> true")
	_check(inv.get_entries().size() == 1, "7: aparecio exactamente 1 entry en InventoryV2")
	_check(inv.get_entries()[0].item_instance.definition == GRANADA_DEF, "7: la entry es de definition == granada.tres")
	_check(not is_instance_valid(g0) or g0.is_queued_for_deletion(), "8: el WorldItem desaparecio del mundo tras el commit exitoso")

	var inventario_v1 := get_node_or_null("/root/Inventario")
	if inventario_v1 != null:
		_check((inventario_v1.get("items") as Array).is_empty(), "9: Inventario (autoload V1) sigue vacio, nunca intervino")


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
