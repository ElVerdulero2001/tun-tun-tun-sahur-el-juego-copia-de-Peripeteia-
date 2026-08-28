class_name TransferOperation
extends RefCounted

## Unica forma valida de cambiar la custodia de un ItemInstance entre
## contextos (mundo <-> inventario) (INV-07, doc V0 seccion 6), y —desde
## V1— tambien de reubicar un ItemInstance DENTRO de un mismo InventoryV2
## (tipo REUBICAR_EN_INVENTARIO). El contrato request->validate->commit y
## la atomicidad valen igual para los tres tipos.
##
## Contrato: request -> validate() -> commit().
## Si validate() falla, commit() no debe llamarse y NADA cambia: el
## ItemInstance permanece exactamente donde estaba.
## Si commit() se llama, aplica TODOS los cambios de ambos extremos en
## un unico paso atomico: nunca queda un resultado intermedio.
##
## Esta clase es transitoria: se crea para UNA transferencia y se
## descarta. No es un manager global (ver aclaracion de INV-07: la
## centralizacion es por transaccion, no por singleton).
##
## Quien puede invocar validate()/commit() es responsabilidad de
## LocalAuthority, no de esta clase. TransferOperation no sabe nada de
## "quien tiene permiso"; solo sabe validar y aplicar UNA transferencia
## concreta ya autorizada.

enum Tipo { MUNDO_A_INVENTARIO, INVENTARIO_A_MUNDO, REUBICAR_EN_INVENTARIO }

var tipo: Tipo
var item_instance: ItemInstance

# Contexto MUNDO_A_INVENTARIO
var world_item: WorldItemV2
var inventory_destino: InventoryV2

# Contexto INVENTARIO_A_MUNDO
var inventory_origen: InventoryV2
var world_scene_parent: Node3D
var spawn_position: Vector3

# Contexto REUBICAR_EN_INVENTARIO
var inventory_reubicar: InventoryV2
var nueva_pos: Vector2i
var nuevo_rotated: bool

var _placement_valido: InventoryEntry = null
var _entry_actual: InventoryEntry = null
var _validado: bool = false
var _resultado_validacion: String = ""

static func crear_mundo_a_inventario(p_world_item: WorldItemV2, p_inventory: InventoryV2) -> TransferOperation:
	var op := TransferOperation.new()
	op.tipo = Tipo.MUNDO_A_INVENTARIO
	op.world_item = p_world_item
	op.item_instance = p_world_item.item_instance
	op.inventory_destino = p_inventory
	return op

static func crear_inventario_a_mundo(p_item_instance: ItemInstance, p_inventory: InventoryV2, p_parent: Node3D, p_position: Vector3) -> TransferOperation:
	var op := TransferOperation.new()
	op.tipo = Tipo.INVENTARIO_A_MUNDO
	op.item_instance = p_item_instance
	op.inventory_origen = p_inventory
	op.world_scene_parent = p_parent
	op.spawn_position = p_position
	return op

## Reubicacion dentro del mismo inventario (V1): mover y/o rotar la entry
## de `p_item_instance`, que ya esta bajo custodia de `p_inventory`.
static func crear_reubicar(p_item_instance: ItemInstance, p_inventory: InventoryV2, p_nueva_pos: Vector2i, p_nuevo_rotated: bool) -> TransferOperation:
	var op := TransferOperation.new()
	op.tipo = Tipo.REUBICAR_EN_INVENTARIO
	op.item_instance = p_item_instance
	op.inventory_reubicar = p_inventory
	op.nueva_pos = p_nueva_pos
	op.nuevo_rotated = p_nuevo_rotated
	return op

## Valida TODO antes de que se aplique ningun cambio. No muta nada.
## Devuelve true si la operacion puede completarse.
func validate() -> bool:
	_validado = false
	_resultado_validacion = ""

	match tipo:
		Tipo.MUNDO_A_INVENTARIO:
			_validado = _validar_mundo_a_inventario()
		Tipo.INVENTARIO_A_MUNDO:
			_validado = _validar_inventario_a_mundo()
		Tipo.REUBICAR_EN_INVENTARIO:
			_validado = _validar_reubicar()

	return _validado

func _validar_mundo_a_inventario() -> bool:
	if item_instance == null:
		_resultado_validacion = "item_instance nulo"
		return false
	if world_item == null or not is_instance_valid(world_item):
		_resultado_validacion = "world_item invalido"
		return false
	if inventory_destino == null:
		_resultado_validacion = "inventory_destino nulo"
		return false
	if inventory_destino.has_item(item_instance):
		_resultado_validacion = "el item ya esta en este inventario (doble custodia)"
		return false

	_placement_valido = inventory_destino.find_valid_placement(item_instance.definition)
	if _placement_valido == null:
		_resultado_validacion = "sin espacio valido en el inventario"
		return false

	_resultado_validacion = "ok"
	return true

func _validar_inventario_a_mundo() -> bool:
	if item_instance == null:
		_resultado_validacion = "item_instance nulo"
		return false
	if inventory_origen == null:
		_resultado_validacion = "inventory_origen nulo"
		return false
	if not inventory_origen.has_item(item_instance):
		_resultado_validacion = "el item no esta bajo custodia de este inventario"
		return false
	if item_instance.definition == null or item_instance.definition.world_scene == null:
		_resultado_validacion = "sin world_scene valida para instanciar"
		return false
	if world_scene_parent == null or not is_instance_valid(world_scene_parent):
		_resultado_validacion = "world_scene_parent invalido"
		return false

	_resultado_validacion = "ok"
	return true

## Reubicacion dentro del mismo inventario. No muta nada: solo comprueba
##  - que el item este realmente bajo custodia de ese InventoryV2;
##  - que si cambia la orientacion, ItemDefinition.can_rotate lo permita (INV-15);
##  - que la posicion destino sea valida excluyendo la propia entry (INV-11).
func _validar_reubicar() -> bool:
	if item_instance == null:
		_resultado_validacion = "item_instance nulo"
		return false
	if inventory_reubicar == null:
		_resultado_validacion = "inventory_reubicar nulo"
		return false

	_entry_actual = _buscar_entry(inventory_reubicar, item_instance)
	if _entry_actual == null:
		_resultado_validacion = "el item no esta bajo custodia de este inventario"
		return false

	if nuevo_rotated != _entry_actual.rotated and not item_instance.definition.can_rotate:
		_resultado_validacion = "la definicion del item no permite rotar"
		return false

	if not inventory_reubicar.posicion_valida(item_instance, nueva_pos, nuevo_rotated, _entry_actual):
		_resultado_validacion = "posicion destino invalida (fuera de limites o solapamiento)"
		return false

	_resultado_validacion = "ok"
	return true

## Busca (solo lectura) la entry de `item` en `inventory`, usando la API
## publica get_entries(). La entry devuelta es la MISMA referencia que vive
## en _entries (get_entries() duplica el Array, no las entries).
func _buscar_entry(inventory: InventoryV2, item: ItemInstance) -> InventoryEntry:
	for entry in inventory.get_entries():
		if entry.item_instance == item:
			return entry
	return null

## Aplica la transferencia completa en un unico paso. Solo debe llamarse
## si validate() devolvio true. Devuelve el resultado (bool, o el
## WorldItemV2 recien creado en el caso inventario->mundo) segun tipo.
func commit() -> Variant:
	if not _validado:
		push_error("TransferOperation.commit() llamado sin validate() previo exitoso — abortado")
		return null

	match tipo:
		Tipo.MUNDO_A_INVENTARIO:
			return _commit_mundo_a_inventario()
		Tipo.INVENTARIO_A_MUNDO:
			return _commit_inventario_a_mundo()
		Tipo.REUBICAR_EN_INVENTARIO:
			return _commit_reubicar()
	return null

func _commit_mundo_a_inventario() -> bool:
	_placement_valido.item_instance = item_instance
	inventory_destino._agregar_entry(_placement_valido)
	world_item.queue_free()
	return true

func _commit_inventario_a_mundo() -> WorldItemV2:
	var nodo: Node = item_instance.definition.world_scene.instantiate()
	var nuevo_world_item := nodo as WorldItemV2
	if nuevo_world_item == null:
		push_error("world_scene de %s no produjo un WorldItemV2" % item_instance)
		return null

	nuevo_world_item.item_instance = item_instance
	world_scene_parent.add_child(nuevo_world_item)
	nuevo_world_item.global_position = spawn_position

	inventory_origen._quitar_entry(item_instance)
	return nuevo_world_item

## Delega en el mutador tonto: _validar_reubicar() ya garantizo que esto es
## legal. Reutiliza la MISMA InventoryEntry y el MISMO ItemInstance (INV-09);
## _entries.size() no cambia (INV-10); _reubicar_entry emite contenido_cambiado
## exactamente una vez.
func _commit_reubicar() -> bool:
	inventory_reubicar._reubicar_entry(item_instance, nueva_pos, nuevo_rotated)
	return true

func get_resultado_validacion() -> String:
	return _resultado_validacion
