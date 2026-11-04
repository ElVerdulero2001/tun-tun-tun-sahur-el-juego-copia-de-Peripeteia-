@tool
extends EditorPlugin

## Suma al editor el panel "Objetos", al lado del Inspector, para crear y
## editar ítems del inventario de grilla y contenedores, con vista previa, y
## colocarlos en la zona de prueba (objetos_panel.gd). Se activa una vez en
## Project → Project Settings → Plugins. Al desactivarlo se saca el panel con
## todo lo suyo (su vista previa y sus conexiones).

const ObjetosPanel := preload("objetos_panel.gd")

var _dock: EditorDock


func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "Objetos"
	_dock.layout_key = "inventario_objetos"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	var panel := ObjetosPanel.new()
	panel.name = "PanelObjetos"
	panel.undo_redo = get_undo_redo()
	_dock.add_child(panel)
	add_dock(_dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null
