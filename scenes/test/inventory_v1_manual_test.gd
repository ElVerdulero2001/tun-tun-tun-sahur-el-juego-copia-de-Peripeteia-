extends Node3D

## ARNÉS MANUAL — NO ES PRODUCCIÓN. Inventory V1 · Paso 5.
## Migrado a InventoryPanel en Batch C2-b.
##
## Prueba a mano InventoryPanel con input real: abrir/cerrar (TAB), agarrar,
## mover el ghost, rotar (R), soltar (válido / OOB / solapado), cancelar (ESC),
## y cerrar con un ítem en la mano.
##
## El wiring vista + manipulator + abrir/cerrar + mouse_filter lo encapsula
## InventoryPanel. Este arnés solo hace lo específico de arnés: mitigar la UI
## legacy, manejar la acción toggle_inventario, el mouse_mode, mostrar el
## estado en labels, y ocultar/mostrar TODO el CanvasLayer con TAB (Fondo +
## Status + Ayuda incluidos) — eso es wiring del arnés, no del panel.

@export var item_definition_test: ItemDefinition        # 2x1 can_rotate = true
@export var item_definition_no_rota: ItemDefinition     # 2x1 can_rotate = false

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo
@onready var capa: CanvasLayer = $CanvasLayer
@onready var panel: InventoryPanel = $CanvasLayer/InventoryPanel
@onready var status: Label = $CanvasLayer/Status

const CELL := 56


func _ready() -> void:
	# ── Mitigación mínima del conflicto con la UI legacy ──────────────
	# El autoload UiInventario captura "toggle_inventario" SIN condición y
	# abriría un overlay legacy vacío + forzaría Input.set_mouse_mode en cada
	# Tab. Solo en este arnés silenciamos su _input mientras la escena está
	# activa (reversible, no toca ningún archivo compartido).
	var legacy := get_node_or_null("/root/UiInventario")
	if legacy != null:
		legacy.set_process_input(false)
		print("[ManualHarness] UiInventario.set_process_input(false) -> evita el overlay legacy y el robo de mouse_mode al usar TAB.")

	panel.cell_size = CELL
	panel.position = Vector2(420, 150)

	_sembrar()
	panel.setup(inv, authority)

	panel.agarrado.connect(func(e: InventoryEntry) -> void:
		_status("AGARRADO %s  (el modelo NO cambió)" % e.item_instance))
	panel.preview_cambiado.connect(_on_preview_cambiado)
	panel.soltado.connect(func(e: InventoryEntry, ok: bool) -> void:
		_status("SOLTADO %s -> %s" % [e.item_instance, "OK" if ok else "RECHAZADO (sigue en la mano, modelo idéntico)"]))
	panel.cancelado.connect(func(e: InventoryEntry) -> void:
		_status("CANCELADO %s  (modelo idéntico)" % e.item_instance))
	panel.rotacion_rechazada.connect(func(e: InventoryEntry) -> void:
		_status("ROTACIÓN RECHAZADA: %s tiene can_rotate=false" % e.item_instance))

	capa.visible = true          # wiring del arnés: TAB oculta/muestra TODO el CanvasLayer
	panel.abrir()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_status("UI abierta. TAB abre/cierra.  Clic: agarrar/soltar.  R: rotar.  ESC: cancelar.")

	print("\n================  INVENTORY V1 · PRUEBA MANUAL (InventoryPanel)  ================")
	print(" TAB .......... abrir / cerrar el panel")
	print(" Clic izq ..... agarrar el ítem bajo el cursor / soltar en el ghost")
	print(" Mouse ........ mueve el ghost por la grilla (verde=válido, rojo=inválido)")
	print(" R ............ rota el ítem en la mano (si can_rotate)")
	print(" ESC .......... cancela: suelta el ítem donde estaba, sin cambios")
	print(" Ítems: 2 azules 2x1 (rotables) + 1 gris 2x1 (can_rotate=false)")
	print("=============================================================================\n")


func _sembrar() -> void:
	authority.set_inventory_receptor(inv)
	for d: ItemDefinition in [item_definition_test, item_definition_test, item_definition_no_rota]:
		var wi: WorldItemV2 = d.world_scene.instantiate()
		wi.item_instance = ItemInstance.new(d)
		add_child(wi)
		wi.global_position = punto_spawn.global_position
		wi.setup(authority)
		wi._on_interact(Interaction.new(self, &"usar"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventario"):
		if panel.esta_abierto():
			# 1) el panel se desactiva/cancela; 2) recién entonces ocultamos el CanvasLayer.
			panel.cerrar()
			capa.visible = false
			_status("UI cerrada. Panel inerte; estado transitorio descartado; modelo intacto.")
		else:
			# 1) el CanvasLayer visible; 2) recién entonces abrimos/usamos la UI.
			capa.visible = true
			panel.abrir()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_status("UI abierta.")
		get_viewport().set_input_as_handled()


func _status(t: String) -> void:
	status.text = t
	print("[status] ", t)


func _on_preview_cambiado() -> void:
	_status("PREVIEW: moviendo el ghost (verde = válido / rojo = inválido).  Clic izq para soltar.")
