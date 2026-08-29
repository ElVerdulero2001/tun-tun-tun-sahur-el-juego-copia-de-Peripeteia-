extends CanvasLayer

## PlayerInventoryUI — capacidad de UI de inventario del Player LOCAL (SUA-1.4).
##
## Hostea el InventoryPanel (componente de presentación REUSABLE) para ESTA
## entidad, lo cablea a SU InventoryV2 y SU LocalAuthority, y es DUEÑO de:
##  - la accion toggle_inventario (TAB) para ESTA entidad;
##  - abrir/cerrar el InventoryPanel;
##  - Input.mouse_mode mientras el panel esta abierto/cerrado.
##
## Es un CanvasLayer porque InventoryPanel exige que el consumidor provea el
## CanvasLayer.
##
## ── Distincion vs InventoryPanel ──
##   InventoryPanel     = presentacion generica; la puede usar un NPC, un cofre,
##                        un vehiculo. No conoce al jugador ni a TAB.
##   PlayerInventoryUI  = especifico del Player local; dueño de TAB / mouse_mode.
##
## ── Por que _shortcut_input y NO _unhandled_input (razon concreta) ──
## player_v2.gd maneja ui_cancel (ESC) en su _unhandled_input y, en el orden
## reverse-tree de propagacion, corre ANTES que este nodo (Interaction -> Body
## -> InventoryManipulator -> PlayerInventoryUI). Con _unhandled_input, ESC con
## el panel ABIERTO haria que PlayerV2 recapture el mouse ANTES de que este
## componente cierre el panel -> estado invalido (panel abierto + mouse
## CAPTURED, y el InventoryManipulator necesita cursor libre).
## _shortcut_input corre antes de TODO _unhandled_input y solo recibe eventos de
## teclado -> este componente consume TAB / (ESC con panel abierto) primero, los
## marca handled, y player_v2.gd nunca los ve. Con el panel CERRADO NO consume
## ESC -> PlayerV2 conserva su toggle de mouse actual.
##
## ── Primer corte (SUA-1.4 C4-B) ──
## Con el panel abierto: mouse-look se detiene solo (player_v2.gd lo guarda con
## mouse_mode == CAPTURED). WASD, salto e InteractionV2/E SIGUEN funcionando —
## sin gating, sin InputManager, sin señales globales.
##
## Cableado: @export con node_paths en player_v2.tscn (mismo patron que
## InventoryReceiver e Interaction). Sin grupos, sin get_node global, sin
## autoloads. NO conoce UiInventario legacy (hibernado aparte, C4-B0).

## InventoryV2 de ESTA entidad. Cableado por @export en player_v2.tscn.
@export var inventory: InventoryV2
## LocalAuthority de ESTA entidad. Cableado por @export en player_v2.tscn.
@export var authority: LocalAuthority

@onready var panel: InventoryPanel = $InventoryPanel


func _ready() -> void:
	assert(inventory != null, "PlayerInventoryUI: 'inventory' (InventoryV2 de esta entidad) sin cablear")
	assert(authority != null, "PlayerInventoryUI: 'authority' (LocalAuthority de esta entidad) sin cablear")

	panel.setup(inventory, authority)
	assert(not panel.esta_abierto(), "PlayerInventoryUI: se esperaba el panel CERRADO tras setup()")


## Dueño de toggle_inventario (siempre) y de ui_cancel (solo con el panel abierto)
## para ESTA entidad. Ver nota de cabecera sobre _shortcut_input.
func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventario"):
		_toggle()
		get_viewport().set_input_as_handled()
	elif panel.esta_abierto() and event.is_action_pressed("ui_cancel"):
		# ESC con el panel abierto: cerrar. panel.cerrar() -> manipulator.desactivar()
		# -> cancelar() descarta cualquier item agarrado (modelo/custodia intactos,
		# INV-12). PlayerV2 no ve el ESC -> no hace un segundo toggle de mouse.
		_cerrar()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	if panel.esta_abierto():
		_cerrar()
	else:
		_abrir()


func _abrir() -> void:
	panel.abrir()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _cerrar() -> void:
	panel.cerrar()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
