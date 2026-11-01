class_name InvEquipView
extends Node3D

## Lo que un jugador tiene equipado, dibujado en su personaje para que lo vean
## todos. Va dentro del dibujo del personaje (ActorBody.visual_root()), así gira
## con él y se esconde con él en primera persona. Agachado baja con la cabeza.
## Solo presentación: lo actualiza InvNet con el equipo que cuenta el host.

var _def_id := &""
var _model: Node3D
var _offset := Vector3.ZERO
var _actor: ActorBody


func setup(actor: ActorBody) -> void:
	_actor = actor
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT


func show_def(def: InvItemDef) -> void:
	var def_id := def.id if def != null else &""
	if def_id == _def_id:
		return
	_def_id = def_id
	if _model != null:
		_model.queue_free()
		_model = null
	var equip := def.ability_of(InvAbility.Kind.EQUIP) as InvEquippable if def != null else null
	if equip == null:
		return
	_model = InvVisuals.fitted(def, equip.hold_size, false) if InvVisuals.has_visual(def) \
			else InvVisuals.placeholder(def, equip.hold_size)
	_model.rotation_degrees = equip.hold_rotation
	_offset = equip.hold_offset
	add_child(_model)
	_place()


func equipped_id() -> StringName:
	return _def_id


func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	if _model == null:
		return
	var height := 1.0
	if is_instance_valid(_actor):
		var standing := _actor.stance_height(ActorState.Stance.STANDING)
		height = _actor.stance_height(_actor.state.stance) / standing if standing > 0.0 else 1.0
	_model.position = Vector3(_offset.x, _offset.y * height, _offset.z)
