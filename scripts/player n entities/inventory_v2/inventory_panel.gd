class_name InventoryPanel
extends Control

## Componente reusable de produccion: encapsula el wiring V1 entre
## InventoryGridView e InventoryManipulator (deuda D5;
## docs/inventory_system_v0_v1.md seccion 17). Composicion PURA sobre las
## APIs publicas existentes: NO tiene logica de modelo.
##
## Uso:
##   panel.setup(inventory, authority)   # cablea vista + manipulator
##   panel.abrir()                       # visible + input activo
##   panel.cerrar()                      # input inactivo + oculto
##
## InventoryPanel NO:
##  - maneja la accion toggle_inventario (eso es del consumidor);
##  - agrega un CanvasLayer (lo provee el consumidor);
##  - busca/crea InventoryV2 ni LocalAuthority;
##  - toca InventoryV2, LocalAuthority ni TransferOperation directamente;
##  - agrega features (equip/hotbar/cofres/stacks/...).
##
## request -> validate -> commit queda intacto: toda reubicacion real la
## sigue haciendo InventoryManipulator -> LocalAuthority.
##
## El estado de manipulacion (held / preview / rotacion tentativa) vive en
## InventoryManipulator; este panel NO lo duplica. Solo lleva dos flags de
## composicion: si esta configurado y si esta abierto.

## Reenviadas 1:1 desde el InventoryManipulator interno. Las conexiones se
## hacen UNA sola vez en _ready() sobre nodos internos estables -> re-llamar
## setup() no las duplica.
signal agarrado(entry: InventoryEntry)
signal soltado(entry: InventoryEntry, exito: bool)
signal preview_cambiado()
signal cancelado(entry: InventoryEntry)
signal rotacion_rechazada(entry: InventoryEntry)
## Intencion: el usuario solto el item held fuera de la grilla. El panel solo la
## reenvia; NO conoce ItemDropper, ni el mundo, ni PlayerV2, ni posiciones 3D.
signal drop_fuera_solicitado(item_instance: ItemInstance)

## Tamano de celda en pixeles. Proxy REAL de grid_view.cell_size: conserva el
## valor, lo aplica en _ready(), y lo propaga en cada cambio posterior.
@export var cell_size: int = 40:
	set(value):
		cell_size = value
		if is_node_ready():
			grid_view.cell_size = value

@onready var grid_view: InventoryGridView = $InventoryGridView
@onready var manipulator: InventoryManipulator = $InventoryGridView/InventoryManipulator

var _configurado: bool = false
var _abierto: bool = false


func _ready() -> void:
	visible = false                       # arranca cerrado
	grid_view.cell_size = cell_size       # aplica el valor exportado / por defecto
	manipulator.agarrado.connect(_reenviar_agarrado)
	manipulator.soltado.connect(_reenviar_soltado)
	manipulator.preview_cambiado.connect(_reenviar_preview_cambiado)
	manipulator.cancelado.connect(_reenviar_cancelado)
	manipulator.rotacion_rechazada.connect(_reenviar_rotacion_rechazada)
	manipulator.drop_fuera_solicitado.connect(_reenviar_drop_fuera_solicitado)


## Cablea vista + manipulator a `inventory` / `authority`. Re-llamable: cambiar
## inventory/authority es una operacion deliberada, asi que si el panel esta
## abierto se cierra primero (descarta cualquier grab en curso via cerrar()).
func setup(inventory: InventoryV2, authority: LocalAuthority) -> void:
	assert(is_node_ready(), "InventoryPanel.setup() requiere el panel ya en el arbol")
	assert(inventory != null and authority != null, "InventoryPanel.setup(): inventory/authority nulos")
	if _abierto:
		cerrar()
	grid_view.set_inventory(inventory)            # idempotente
	manipulator.setup(grid_view, authority)
	_configurado = true


## Abre el panel. IDEMPOTENTE:
##  - sin setup() previo   -> no-op;
##  - ya abierto           -> no-op (NO re-llama activar(): activar() resetea el
##                            estado transitorio y cancelaria un grab en curso);
##  - cerrado + configurado -> visible + manipulator.activar().
func abrir() -> void:
	if not _configurado:
		return
	if _abierto:
		return
	visible = true
	manipulator.activar()
	_abierto = true


## Cierra el panel. Seguro de llamar sin abrir()/setup() previos. Si habia un
## item agarrado, manipulator.desactivar() -> cancelar() lo descarta (emite
## cancelado, modelo y custodia intactos - INV-12) ANTES de ocultar.
func cerrar() -> void:
	manipulator.desactivar()
	visible = false
	_abierto = false


func esta_abierto() -> bool:
	return _abierto


func esta_configurado() -> bool:
	return _configurado


# ── Reenvio de señales del manipulator (conexiones unicas, ver _ready) ──
func _reenviar_agarrado(entry: InventoryEntry) -> void:
	agarrado.emit(entry)

func _reenviar_soltado(entry: InventoryEntry, exito: bool) -> void:
	soltado.emit(entry, exito)

func _reenviar_preview_cambiado() -> void:
	preview_cambiado.emit()

func _reenviar_cancelado(entry: InventoryEntry) -> void:
	cancelado.emit(entry)

func _reenviar_rotacion_rechazada(entry: InventoryEntry) -> void:
	rotacion_rechazada.emit(entry)

func _reenviar_drop_fuera_solicitado(item_instance: ItemInstance) -> void:
	drop_fuera_solicitado.emit(item_instance)
