extends CanvasLayer

## PlayerInventoryUI — capacidad de UI de inventario del Player LOCAL (SUA-1.3 C4-A).
##
## Hostea el InventoryPanel (componente de presentación REUSABLE) para ESTA
## entidad y lo cablea a SU InventoryV2 y SU LocalAuthority. Es un CanvasLayer
## porque InventoryPanel exige que el consumidor provea el CanvasLayer.
##
## ── Distinción vs InventoryPanel ──
##   InventoryPanel     = presentación genérica; la puede usar un NPC, un cofre,
##                        un vehículo. No conoce al jugador ni a TAB.
##   PlayerInventoryUI  = específico del Player local. Será dueño de la semántica
##                        de toggle_inventario / TAB, del Input.mouse_mode y de la
##                        coordinación de foco de input del Player.
##
## ── ALCANCE C4-A (solo composición estructural) ──
## Recibir InventoryV2 + LocalAuthority por @export, configurar el panel, dejarlo
## cerrado. NADA MÁS. Todavía NO: _unhandled_input / _input / toggle_inventario /
## Input.mouse_mode / gating de movimiento o de InteractionV2 / nada del sistema
## legacy (UiInventario). Eso es C4-B.
##
## Cableado: @export con node_paths en player_v2.tscn (mismo patrón que
## InventoryReceiver e Interaction). Sin grupos, sin get_node global, sin autoloads.

## InventoryV2 de ESTA entidad. Cableado por @export en player_v2.tscn.
@export var inventory: InventoryV2
## LocalAuthority de ESTA entidad. Cableado por @export en player_v2.tscn.
@export var authority: LocalAuthority

@onready var panel: InventoryPanel = $InventoryPanel


func _ready() -> void:
	assert(inventory != null, "PlayerInventoryUI: 'inventory' (InventoryV2 de esta entidad) sin cablear")
	assert(authority != null, "PlayerInventoryUI: 'authority' (LocalAuthority de esta entidad) sin cablear")

	panel.setup(inventory, authority)

	# InventoryPanel arranca cerrado por contrato: su _ready() hace visible=false,
	# _abierto=false, y el manipulator arranca inactivo; setup() no lo abre. No se
	# duplica cerrar() — solo un tripwire sobre su API pública.
	assert(not panel.esta_abierto(), "PlayerInventoryUI: se esperaba el panel CERRADO tras setup()")
