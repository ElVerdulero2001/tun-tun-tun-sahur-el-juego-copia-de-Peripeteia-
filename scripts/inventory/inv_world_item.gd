class_name InvWorldItem
extends Node3D

## Cómo se ve un objeto suelto en el mundo: su modelo apoyado en el piso y un
## cartel con su nombre y cantidad. Es solo presentación: lo arma InvNet en
## cada máquina con lo que cuenta el host, y no choca con nada.
##
## Para el indicador de lo que se mira (desde el 2026-11-06), aporta su
## InteractFocus: el nombre visible del tipo y la caja de su modelo.

var uid := 0
var _label: Label3D
var _shown := ""
var _focus: InteractFocus


func setup(def: InvItemDef, stack: InvStack) -> void:
	uid = stack.uid
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var size := def.world_size if def != null else 0.4
	var model := InvVisuals.fitted(def, size, true) if InvVisuals.has_visual(def) else InvVisuals.placeholder(def, size)
	add_child(model)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 32
	_label.pixel_size = 0.004
	_label.outline_size = 8
	_label.no_depth_test = false
	_label.position = Vector3.UP * (size + 0.25)
	add_child(_label)
	_focus = InteractFocus.new("", self, InteractFocus.mesh_bounds(self), _label)
	refresh(def, stack)


func refresh(def: InvItemDef, stack: InvStack) -> void:
	var text := def.display_name if def != null else String(stack.def_id)
	_focus.display_name = text
	if stack.quantity > 1:
		text += " ×%d" % stack.quantity
	if text != _shown:
		_shown = text
		_label.text = text


## Lo que marca el indicador cuando E elegiría este objeto: su modelo y el
## nombre visible del tipo, sin la cantidad. Mientras está marcado, el
## indicador oculta el cartel de arriba.
func interact_focus() -> InteractFocus:
	return _focus
