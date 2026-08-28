class_name InventoryV2
extends Node

## Componente de inventario. Se agrega como hijo de CUALQUIER entidad que
## necesite guardar items (jugador, NPC, caja, vehiculo...), igual que
## MovementController o TraversalController son hijos de Player.
##
## INV-01: no es Singleton ni Autoload. No existe un InventoryManager
## global; el estado vive aca, colgado de la entidad dueña.
##
## INV-05: la ocupacion por celda es informacion DERIVADA. La fuente de
## verdad son las entries: item, posicion, orientacion. No se mantiene
## una matriz de ocupacion como estado independiente — se recalcula bajo
## demanda (entry_en_celda / posicion_valida / celdas_ocupadas_por). Si en
## el futuro hace falta una cache por rendimiento, debe poder reconstruirse
## a partir de esta lista sin cambiar el contrato de este script.
## (Lista completa de consultas: docs/inventory_system_v0_v1.md seccion 8.)
##
## IMPORTANTE (INV-07/INV-08): este componente NUNCA debe ser mutado
## directamente desde afuera (UI, otros nodos). Las unicas tres formas
## validas de cambiar su contenido son los metodos _agregar_entry /
## _quitar_entry / _reubicar_entry, y esos son de uso EXCLUSIVO de
## TransferOperation durante su commit(). Nombrarlos con guion bajo es la
## señal de esa restriccion: no son API publica.
##
## Cada uno de esos tres metodos emite `contenido_cambiado` exactamente una
## vez cuando efectivamente muta el estado, para que la vista de V1 pueda
## refrescar sin hacer polling de get_entries().

@export var grid_width: int = 4
@export var grid_height: int = 4

## Se emite una vez por cada mutacion efectiva de _entries (alta, baja o
## reubicacion in-place). Consumidor previsto: la vista de inventario de V1.
signal contenido_cambiado

var _entries: Array[InventoryEntry] = []

## Busca la primera posicion (sin rotar, luego rotada si el item lo
## permite) donde el item entraria sin superponerse con ninguna entry
## existente. Devuelve null si no hay lugar.
## Metodo de SOLO CONSULTA: no modifica el inventario. Usado por
## TransferOperation.validate(), nunca por un solicitante directamente.
func find_valid_placement(definition: ItemDefinition) -> InventoryEntry:
	for intentar_rotado in [false, true]:
		if intentar_rotado and not definition.can_rotate:
			continue
		var footprint := Vector2i(definition.grid_height, definition.grid_width) if intentar_rotado \
			else Vector2i(definition.grid_width, definition.grid_height)
		if footprint.x > grid_width or footprint.y > grid_height:
			continue
		for fila in range(grid_height - footprint.y + 1):
			for col in range(grid_width - footprint.x + 1):
				var pos := Vector2i(col, fila)
				if _cabe_en(pos, footprint):
					# El item_instance real se completa en TransferOperation;
					# esta entry es un resultado de consulta, todavia no
					# esta agregada a _entries.
					return InventoryEntry.new(null, pos, intentar_rotado)
	return null

func _cabe_en(pos: Vector2i, footprint: Vector2i) -> bool:
	if pos.x < 0 or pos.y < 0:
		return false
	if pos.x + footprint.x > grid_width or pos.y + footprint.y > grid_height:
		return false
	for entry in _entries:
		if _se_superponen(pos, footprint, entry.position, entry.get_footprint()):
			return false
	return true

func _se_superponen(pos_a: Vector2i, size_a: Vector2i, pos_b: Vector2i, size_b: Vector2i) -> bool:
	var sin_solapar := (
		pos_a.x + size_a.x <= pos_b.x
		or pos_b.x + size_b.x <= pos_a.x
		or pos_a.y + size_a.y <= pos_b.y
		or pos_b.y + size_b.y <= pos_a.y
	)
	return not sin_solapar

## Devuelve SNAPSHOTS (copias detached) de las entries, en orden de _entries.
## Mutar una snapshot NO afecta al modelo. El item_instance de cada snapshot
## ES la misma referencia (identidad logica compartida). NO se garantiza
## identidad de objeto InventoryEntry entre dos llamadas: eso dejo de ser
## contrato publico (la entry viva no se entrega — D1).
func get_entries() -> Array[InventoryEntry]:
	var out: Array[InventoryEntry] = []
	for entry in _entries:
		out.append(entry.snapshot())
	return out

func has_item(item_instance: ItemInstance) -> bool:
	for entry in _entries:
		if entry.item_instance == item_instance:
			return true
	return false

# ── Consultas read-only para manipulacion dentro del inventario (V1) ─
# Ninguna de estas tres funciones muta el inventario. Son analogas a
# find_valid_placement()/get_entries(): informacion DERIVADA de _entries,
# calculada bajo demanda (INV-05). Uso previsto: la capa de UI/manipulacion
# de V1, que consulta pero NUNCA escribe.

## Devuelve una SNAPSHOT (copia detached) de la entry cuyo footprint cubre
## `celda`, o null si la celda esta libre. NUNCA la entry viva. Si hubiera
## solapamiento (no deberia, por invariante) devuelve la primera en orden.
func entry_en_celda(celda: Vector2i) -> InventoryEntry:
	for entry in _entries:
		var fp := entry.get_footprint()
		if celda.x >= entry.position.x and celda.x < entry.position.x + fp.x \
		and celda.y >= entry.position.y and celda.y < entry.position.y + fp.y:
			return entry.snapshot()
	return null

## Celdas (Vector2i) que ocupa `entry` segun su posicion y orientacion
## actual. Geometria pura: no valida que `entry` pertenezca a este inventario.
func celdas_ocupadas_por(entry: InventoryEntry) -> Array[Vector2i]:
	var celdas: Array[Vector2i] = []
	var fp := entry.get_footprint()
	for dy in range(fp.y):
		for dx in range(fp.x):
			celdas.append(entry.position + Vector2i(dx, dy))
	return celdas

## Indica si `item_instance` puede quedar colocado en `pos` con orientacion
## `rotated` sin salirse de la grilla y sin solapar ninguna entry existente.
## `excluir_item`: ItemInstance cuya entry se ignora en el chequeo de
## solapamiento (tipicamente el item que se esta moviendo, para que no choque
## consigo mismo). null = no excluir ninguno. Se excluye por ItemInstance
## (no por InventoryEntry) porque afuera ya no circulan entries vivas.
## SOLO CONSULTA: no muta, y NO chequea definition.can_rotate (eso es
## responsabilidad de la operacion, no de esta geometria).
func posicion_valida(item_instance: ItemInstance, pos: Vector2i, rotated: bool, excluir_item: ItemInstance = null) -> bool:
	var def := item_instance.definition
	var footprint := Vector2i(def.grid_height, def.grid_width) if rotated \
		else Vector2i(def.grid_width, def.grid_height)
	if pos.x < 0 or pos.y < 0:
		return false
	if pos.x + footprint.x > grid_width or pos.y + footprint.y > grid_height:
		return false
	for entry in _entries:
		if entry.item_instance == excluir_item:
			continue
		if _se_superponen(pos, footprint, entry.position, entry.get_footprint()):
			return false
	return true

# ── API exclusiva de TransferOperation ──────────────────────────────
# No llamar desde ningun otro lugar. Ver nota de cabecera.

func _agregar_entry(entry: InventoryEntry) -> void:
	_entries.append(entry)
	contenido_cambiado.emit()

func _quitar_entry(item_instance: ItemInstance) -> InventoryEntry:
	for i in range(_entries.size()):
		if _entries[i].item_instance == item_instance:
			var entry := _entries[i]
			_entries.remove_at(i)
			contenido_cambiado.emit()
			return entry
	return null

## Reubica la entry de `item_instance` DENTRO de este inventario: cambia su
## posicion y orientacion IN-PLACE, sobre la MISMA InventoryEntry (INV-09).
## No crea ni destruye entries: _entries.size() y el orden de la lista no
## cambian (INV-10). Es un mutador "tonto": NO valida limites ni solapamiento
## (eso lo hace TransferOperation.validate() antes de llamar aca).
## Devuelve la entry mutada, o null si el item no estaba en este inventario.
func _reubicar_entry(item_instance: ItemInstance, nueva_pos: Vector2i, nuevo_rotated: bool) -> InventoryEntry:
	for entry in _entries:
		if entry.item_instance == item_instance:
			entry._reubicar(nueva_pos, nuevo_rotated)
			contenido_cambiado.emit()
			return entry
	return null
