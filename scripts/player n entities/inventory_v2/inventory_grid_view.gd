class_name InventoryGridView
extends Control

## Vista PURA de un InventoryV2 (Inventory V1, Paso 4).
##
## Dibuja la grilla grid_width x grid_height y un rectangulo por cada
## InventoryEntry, ubicado segun su position y su footprint (que ya
## contempla `rotated` via InventoryEntry.get_footprint()).
##
## ESTRICTAMENTE READ-ONLY. Esta clase:
##  - NUNCA llama _agregar_entry / _quitar_entry / _reubicar_entry;
##  - NUNCA llama a LocalAuthority ni a TransferOperation;
##  - solo lee get_entries(), grid_width, grid_height y se suscribe a la
##    señal contenido_cambiado para re-renderizar.
##
## No maneja input de mover/rotar: eso es el InventoryManipulator (Paso 5).

@export var cell_size: int = 40
@export var color_celda: Color = Color(0.12, 0.12, 0.14)
@export var color_borde: Color = Color(0.25, 0.25, 0.3)
@export var color_entry: Color = Color(0.35, 0.55, 0.85, 0.85)
@export var color_entry_borde: Color = Color(0.6, 0.8, 1.0)

## Diagnostico/observabilidad: cuantas veces se re-renderizo la vista
## (una al asignar inventario, y una por cada contenido_cambiado recibido).
var refrescos: int = 0

var _inventory: InventoryV2 = null


## Asigna (o cambia) el InventoryV2 que representa esta vista. Se conecta a
## su señal contenido_cambiado y desconecta la del inventario anterior.
func set_inventory(inv: InventoryV2) -> void:
	if _inventory == inv:
		return
	if _inventory != null and _inventory.contenido_cambiado.is_connected(_on_contenido_cambiado):
		_inventory.contenido_cambiado.disconnect(_on_contenido_cambiado)
	_inventory = inv
	if _inventory != null:
		_inventory.contenido_cambiado.connect(_on_contenido_cambiado)
	_refrescar()


func get_inventory() -> InventoryV2:
	return _inventory


func _on_contenido_cambiado() -> void:
	_refrescar()


func _refrescar() -> void:
	refrescos += 1
	if _inventory != null:
		custom_minimum_size = Vector2(
			_inventory.grid_width * cell_size,
			_inventory.grid_height * cell_size
		)
	queue_redraw()


# ── Consulta de layout (geometria que dibuja _draw, tambien para tests) ──
# Funciones puras: no mutan nada.

## Cantidad total de celdas de grilla a dibujar (grid_width * grid_height).
func cantidad_celdas() -> int:
	if _inventory == null:
		return 0
	return _inventory.grid_width * _inventory.grid_height


## Rect en pixeles locales de una celda de grilla.
func rect_de_celda(celda: Vector2i) -> Rect2:
	return Rect2(celda.x * cell_size, celda.y * cell_size, cell_size, cell_size)


## Rect en pixeles locales que ocupa una entry, segun position y footprint
## (el footprint ya contempla la orientacion via get_footprint()).
func rect_de_entry(entry: InventoryEntry) -> Rect2:
	var fp := entry.get_footprint()
	return Rect2(
		entry.position.x * cell_size,
		entry.position.y * cell_size,
		fp.x * cell_size,
		fp.y * cell_size
	)


## Layout de todas las entries visibles, POR VALOR (no filtra ninguna entry
## viva del modelo). Cada elemento:
## { item_instance, position: Vector2i, rotated: bool, footprint: Vector2i, rect: Rect2 }
func layout_entries() -> Array:
	var out: Array = []
	if _inventory == null:
		return out
	for entry in _inventory.get_entries():   # snapshots
		out.append({
			"item_instance": entry.item_instance,
			"position": entry.position,
			"rotated": entry.rotated,
			"footprint": entry.get_footprint(),
			"rect": rect_de_entry(entry),
		})
	return out


func _draw() -> void:
	if _inventory == null:
		return
	for fila in range(_inventory.grid_height):
		for col in range(_inventory.grid_width):
			var r := rect_de_celda(Vector2i(col, fila))
			draw_rect(r, color_celda, true)
			draw_rect(r, color_borde, false, 1.0)
	for entry in _inventory.get_entries():
		var re := rect_de_entry(entry)
		draw_rect(re, color_entry, true)
		draw_rect(re, color_entry_borde, false, 2.0)
