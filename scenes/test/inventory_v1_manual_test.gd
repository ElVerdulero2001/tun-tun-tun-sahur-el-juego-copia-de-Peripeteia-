extends Node3D

## ARNÉS MANUAL — NO ES PRODUCCIÓN. Inventory V1 · Paso 5.
##
## Para probar a mano InventoryGridView + InventoryManipulator con input real:
## abrir/cerrar la UI, agarrar, mover el ghost, rotar, soltar (válido / OOB /
## solapado), y cerrar con un ítem en la mano.
##
## Mitigación del conflicto con la UI legacy: ver _ready() y el informe del Paso 5.

@export var item_definition_test: ItemDefinition        # 2x1 can_rotate = true
@export var item_definition_no_rota: ItemDefinition     # 2x1 can_rotate = false

@onready var authority: LocalAuthority = $LocalAuthority
@onready var inv: InventoryV2 = $Inv
@onready var punto_spawn: Marker3D = $PuntoSpawnMundo
@onready var capa: CanvasLayer = $CanvasLayer
@onready var view: InventoryGridView = $CanvasLayer/InventoryGridView
@onready var manip: InventoryManipulator = $CanvasLayer/InventoryGridView/InventoryManipulator
@onready var status: Label = $CanvasLayer/Status

const CELL := 56


func _ready() -> void:
	# ── Mitigación mínima del conflicto con la UI legacy ──────────────
	# El autoload UiInventario (ui_inventario.gd:145) captura la acción
	# "toggle_inventario" SIN condición y abriría un overlay vacío de 15x20
	# + forzaría Input.set_mouse_mode en cada Tab. Solo en este arnés
	# silenciamos su _input mientras la escena está activa (no lo liberamos
	# ni lo ocultamos; es reversible y no toca ningún archivo compartido).
	var legacy := get_node_or_null("/root/UiInventario")
	if legacy != null:
		legacy.set_process_input(false)
		print("[ManualHarness] UiInventario.set_process_input(false) -> evita el overlay legacy y el robo de mouse_mode al usar TAB.")

	view.cell_size = CELL
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.position = Vector2(420, 150)
	manip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_sembrar()
	view.set_inventory(inv)
	view.size = Vector2(inv.grid_width * CELL, inv.grid_height * CELL)
	manip.setup(view, authority)

	manip.agarrado.connect(func(e: InventoryEntry) -> void:
		_status("AGARRADO %s  (el modelo NO cambió)" % e.item_instance))
	manip.preview_cambiado.connect(_status_preview)
	manip.soltado.connect(func(e: InventoryEntry, ok: bool) -> void:
		_status("SOLTADO %s -> %s" % [e.item_instance, "OK" if ok else "RECHAZADO (sigue en la mano, modelo idéntico)"]))
	manip.cancelado.connect(func(e: InventoryEntry) -> void:
		_status("CANCELADO %s  (modelo idéntico)" % e.item_instance))
	manip.rotacion_rechazada.connect(func(e: InventoryEntry) -> void:
		_status("ROTACIÓN RECHAZADA: %s tiene can_rotate=false" % e.item_instance))

	capa.visible = true
	manip.activar()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_status("UI abierta. TAB abre/cierra.  Clic: agarrar/soltar.  R: rotar.  ESC: cancelar.")

	print("\n================  INVENTORY V1 · PRUEBA MANUAL  ================")
	print(" TAB .......... abrir / cerrar la UI")
	print(" Clic izq ..... agarrar el ítem bajo el cursor / soltar en el ghost")
	print(" Mouse ........ mueve el ghost por la grilla (verde=válido, rojo=inválido)")
	print(" R ............ rota el ítem en la mano (si can_rotate)")
	print(" ESC .......... cancela: suelta el ítem donde estaba, sin cambios")
	print(" Ítems: 2 azules 2x1 (rotables) + 1 gris 2x1 (can_rotate=false)")
	print("==============================================================\n")


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
		capa.visible = not capa.visible
		if capa.visible:
			manip.activar()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_status("UI abierta.")
		else:
			manip.desactivar()   # cancela held + deja de procesar input
			_status("UI cerrada. Manipulator inerte; estado transitorio descartado; modelo intacto.")
		get_viewport().set_input_as_handled()


func _status(t: String) -> void:
	status.text = t
	print("[status] ", t)


func _status_preview() -> void:
	if not manip.esta_agarrando():
		return
	var d := manip.celda_destino_tentativa()
	_status("PREVIEW  destino=%s  rot_tentativa=%s  ->  %s" % [
		d, manip.rotacion_tentativa(),
		"VÁLIDO" if manip.destino_es_valido() else "INVÁLIDO"])
