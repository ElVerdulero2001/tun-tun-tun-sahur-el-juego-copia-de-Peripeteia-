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
##
## ── Drop desde la UI (SUA-1.5 C5-C) ──
## Este componente es el PUENTE entre la INTENCION de drop que nace en la UI
## (InventoryPanel.drop_fuera_solicitado, C5-B/B2) y la EJECUCION gameplay/3D
## (ItemDropper.soltar, C5-A). NO implementa reglas espaciales: no calcula
## posiciones, no busca current_scene, no usa DropPoint, no llama a
## LocalAuthority. Solo delega en SU ItemDropper.

## InventoryV2 de ESTA entidad. Cableado por @export en player_v2.tscn.
@export var inventory: InventoryV2
## LocalAuthority de ESTA entidad. Cableado por @export en player_v2.tscn.
@export var authority: LocalAuthority
## ItemDropper de ESTA entidad (capacidad inventario -> mundo). Cableado por
## @export en player_v2.tscn. Unico destino de la intencion de drop de la UI.
@export var dropper: ItemDropper

@onready var panel: InventoryPanel = $InventoryPanel


func _ready() -> void:
	assert(inventory != null, "PlayerInventoryUI: 'inventory' (InventoryV2 de esta entidad) sin cablear")
	assert(authority != null, "PlayerInventoryUI: 'authority' (LocalAuthority de esta entidad) sin cablear")
	assert(dropper != null, "PlayerInventoryUI: 'dropper' (ItemDropper de esta entidad) sin cablear")

	panel.setup(inventory, authority)
	assert(not panel.esta_abierto(), "PlayerInventoryUI: se esperaba el panel CERRADO tras setup()")

	# Conexion UNICA (panel es un nodo interno estable): la intencion de drop de
	# la UI se ejecuta pidiendosela a SU ItemDropper.
	panel.drop_fuera_solicitado.connect(_on_drop_fuera_solicitado)


## Handler de la intencion de drop de la UI. Delega TAL CUAL en el ItemDropper
## de esta entidad: sin logica espacial, sin tocar el modelo. Si el drop no se
## concreta (dropper.soltar() -> null) NO hay rollback: el ItemInstance sigue en
## InventoryV2 en su entry original (ni el manipulator ni TransferOperation lo
## movieron) y reaparece normalmente en la vista. El panel NO se cierra: el
## jugador puede seguir con el inventario abierto y moviendose.
func _on_drop_fuera_solicitado(item_instance: ItemInstance) -> void:
	dropper.soltar(item_instance)


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
