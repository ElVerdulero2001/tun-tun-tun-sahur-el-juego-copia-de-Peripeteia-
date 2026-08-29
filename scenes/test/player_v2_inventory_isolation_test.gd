extends Node3D

## ARNES DE TEST — NO ES PRODUCCION. PlayerV2 · FASE C0.
##
## Demuestra que el estado de inventario de PlayerV2 es ENTERAMENTE por
## instancia, ANTES de integrar el routing real de pickup (C1).
##
## Instancia DOS player_v2.tscn independientes y verifica:
##   1. cada entidad tiene su propio InventoryV2 / LocalAuthority /
##      InventoryReceiver (objetos distintos, nunca compartidos);
##   2. las @export de cada InventoryReceiver apuntan SOLO a los nodos de su
##      propia entidad (nunca cruzadas);
##   3. una operacion valida mundo->inventario sobre A (via WorldItemV2 ->
##      LocalAuthority de A -> TransferOperation, la infraestructura normal
##      de V2) agrega la entry en A y deja B BYTE-IDENTICO: 0 entries,
##      0 emisiones de contenido_cambiado.
##
## Headless / llamadas directas. SIN input real: dos PlayerV2 comparten hoy
## el InputMap y no estamos probando input ownership todavia.
##
## NOTA: NO usa InventoryReceiver.recibir_pickup() — ese metodo no tiene
## routing hasta C1. El pickup del punto 3 usa el MISMO patron que _sembrar()
## en los tests V2 ya en verde: auth.set_inventory_receptor(inv) (afordancia
## de arnes documentada en local_authority.gd) + wi._on_interact(...).

const PLAYER_V2 := preload("res://scenes/player_v2/player_v2.tscn")

@export var item_definition_test: ItemDefinition   # 2x1, world_scene = test_item_v0

var _fallos := 0
var _checks := 0

# Contadores de senal. MIEMBROS (no locales): los lambdas de GDScript capturan
# las locales POR VALOR — un contador local nunca veria el incremento. Mismo
# patron que _emis_inv en inventory_panel_test.gd.
var _emisiones_a := 0
var _emisiones_b := 0


func _ready() -> void:
	print("\n===== PLAYERV2 · FASE C0 · aislamiento de inventario por instancia =====")

	var pa := PLAYER_V2.instantiate()
	var pb := PLAYER_V2.instantiate()
	add_child(pa)
	add_child(pb)

	var inv_a: InventoryV2 = pa.get_node("Inventory")
	var inv_b: InventoryV2 = pb.get_node("Inventory")
	var auth_a: LocalAuthority = pa.get_node("InventoryAuthority")
	var auth_b: LocalAuthority = pb.get_node("InventoryAuthority")
	var recv_a: InventoryReceiver = pa.get_node("InventoryReceiver")
	var recv_b: InventoryReceiver = pb.get_node("InventoryReceiver")

	# ── 1. nodos por instancia, nunca compartidos ─────────────────────
	print("-- 1. cada PlayerV2 tiene sus propios nodos de inventario --")
	_check(inv_a != null and inv_b != null, "1: ambos Inventory (InventoryV2) resueltos")
	_check(auth_a != null and auth_b != null, "1: ambos InventoryAuthority (LocalAuthority) resueltos")
	_check(recv_a != null and recv_b != null, "1: ambos InventoryReceiver resueltos")
	_check(inv_a != inv_b, "1: A.Inventory != B.Inventory")
	_check(auth_a != auth_b, "1: A.InventoryAuthority != B.InventoryAuthority")
	_check(recv_a != recv_b, "1: A.InventoryReceiver != B.InventoryReceiver")

	# ── 2. @export de cada receiver -> SOLO su propia entidad ─────────
	print("-- 2. las @export de cada InventoryReceiver apuntan a su propia entidad --")
	_check(recv_a.inventory == inv_a, "2: ReceiverA.inventory == InventoryA")
	_check(recv_a.authority == auth_a, "2: ReceiverA.authority == AuthorityA")
	_check(recv_b.inventory == inv_b, "2: ReceiverB.inventory == InventoryB")
	_check(recv_b.authority == auth_b, "2: ReceiverB.authority == AuthorityB")
	_check(recv_a.inventory != inv_b, "2: ReceiverA.inventory NO cruza a InventoryB")
	_check(recv_a.authority != auth_b, "2: ReceiverA.authority NO cruza a AuthorityB")
	_check(recv_b.inventory != inv_a, "2: ReceiverB.inventory NO cruza a InventoryA")
	_check(recv_b.authority != auth_a, "2: ReceiverB.authority NO cruza a AuthorityA")

	# ── 3. operacion valida sobre A; B queda byte-identico ────────────
	print("-- 3. pickup mundo->A no toca B --")
	inv_a.contenido_cambiado.connect(func() -> void: _emisiones_a += 1)
	inv_b.contenido_cambiado.connect(func() -> void: _emisiones_b += 1)

	_check(inv_a.get_entries().size() == 0, "3: A arranca vacio")
	_check(inv_b.get_entries().size() == 0, "3: B arranca vacio")

	auth_a.set_inventory_receptor(inv_a)   # afordancia de arnes (local_authority.gd), NO el wiring de C1
	var ii := ItemInstance.new(item_definition_test)
	var wi: WorldItemV2 = item_definition_test.world_scene.instantiate()
	wi.item_instance = ii
	add_child(wi)
	wi.setup(auth_a)
	var ok: bool = wi._on_interact(Interaction.new(self, &"usar"))

	_check(ok, "3: pickup mundo->A reporto exito")
	_check(inv_a.get_entries().size() == 1, "3: A tiene exactamente 1 entry")
	_check(inv_a.has_item(ii), "3: la entry de A ES el ItemInstance recogido")
	_check(_emisiones_a == 1, "3: A emitio contenido_cambiado exactamente 1 vez")

	_check(inv_b.get_entries().size() == 0, "3: B SIGUE vacio (sin contaminacion)")
	_check(_emisiones_b == 0, "3: B NO emitio contenido_cambiado")
	_check(not inv_b.has_item(ii), "3: B no tiene el ItemInstance de A")

	await get_tree().process_frame        # asienta el queue_free() del WorldItemV2 consumido

	_check(inv_a.get_entries().size() == 1, "3: A sigue con 1 entry tras asentar el frame")
	_check(inv_b.get_entries().size() == 0, "3: B sigue vacio tras asentar el frame")

	print("=======================================================================")
	print("Chequeos: %d | Fallas: %d" % [_checks, _fallos])
	if _fallos == 0:
		print("RESULTADO: FASE C0 (aislamiento PlayerV2 <-> InventoryV2) OK")
	else:
		printerr("RESULTADO: %d CHEQUEO(S) FALLARON" % _fallos)
	assert(_fallos == 0, "Fallaron chequeos de aislamiento C0")
	get_tree().quit(_fallos)


func _check(condicion: bool, mensaje: String) -> void:
	_checks += 1
	if condicion:
		print("  [OK]    ", mensaje)
	else:
		_fallos += 1
		printerr("  [FALLA] ", mensaje)
