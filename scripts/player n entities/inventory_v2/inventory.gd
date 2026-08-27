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
## una matriz de ocupacion como estado independiente en V0 — se
## recalcula bajo demanda con _celda_ocupada(). Si en el futuro hace
## falta una cache por rendimiento, debe poder reconstruirse a partir
## de esta lista sin cambiar el contrato de este script.
##
## IMPORTANTE (INV-07/INV-08): este componente NUNCA debe ser mutado
## directamente desde afuera (UI, otros nodos). Las unicas dos formas
## validas de cambiar su contenido son los metodos _agregar_entry /
## _quitar_entry, y esos son de uso EXCLUSIVO de TransferOperation
## durante su commit(). Nombrarlos con guion bajo es la señal de esa
## restriccion: no son API publica.

@export var grid_width: int = 4
@export var grid_height: int = 4

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

## Solo para consulta/debug. No usar para mutar estado.
func get_entries() -> Array[InventoryEntry]:
	return _entries.duplicate()

func has_item(item_instance: ItemInstance) -> bool:
	for entry in _entries:
		if entry.item_instance == item_instance:
			return true
	return false

# ── API exclusiva de TransferOperation ──────────────────────────────
# No llamar desde ningun otro lugar. Ver nota de cabecera.

func _agregar_entry(entry: InventoryEntry) -> void:
	_entries.append(entry)

func _quitar_entry(item_instance: ItemInstance) -> InventoryEntry:
	for i in range(_entries.size()):
		if _entries[i].item_instance == item_instance:
			var entry := _entries[i]
			_entries.remove_at(i)
			return entry
	return null
