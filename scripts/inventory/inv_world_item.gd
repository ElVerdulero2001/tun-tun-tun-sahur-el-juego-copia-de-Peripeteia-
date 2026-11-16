class_name InvWorldItem
extends RigidBody3D

## Un objeto suelto en el mundo: su modelo, un cartel con su nombre y cantidad,
## y, desde el 2026-11-14, su cuerpo físico. Lo arma InvBodies en cada máquina.
##
## - **En el host** (y jugando solo) es el cuerpo de verdad (`simulated`): un
##   RigidBody3D de Jolt con las formas de su tipo (InvItemPhysics), en la capa
##   de los objetos sueltos (choca con el nivel, las cajas, las escaleras y los
##   demás objetos, no con los personajes), con la masa común del Tuning y CCD.
##   Cae, choca, reposa y se duerme solo. Mientras alguien lo sostiene, la mano
##   lo lleva con velocidades acotadas (hold_*, en _integrate_forces).
## - **En un cliente** es una copia congelada, sin formas ni capas: la coloca
##   InvBodies con lo que manda el host (interpolado) o, si lo sostiene el
##   jugador de esa máquina, un poco adelantado.
## - **Lo soltado que el host todavía no confirmó** también es una copia
##   congelada, en el lugar donde va a aparecer.
##
## El cartel se puede apagar desde el InvPickupSpawn que lo pone en el mapa
## (show_label, desde el 2026-11-06): sin cartel, el objeto es solo su modelo.
## Para el indicador de lo que se mira (desde el 2026-11-06), aporta su
## InteractFocus: el nombre visible del tipo y la caja de su modelo, que sigue
## al cuerpo al moverse y girar.
##
## Para agarrarlo no hace falta nada de acá: el rayo de la mano (InvReach)
## toca la hitbox de agarre del tipo o, sin una, los triángulos de su modelo,
## con la pose de este objeto. El cuerpo físico no es lo que se agarra.
##
## Por qué la mano mueve el cuerpo con velocidades y no lo pone en su lugar:
## con Jolt, la velocidad con que arranca un paso es una fuerza acotada que el
## resolvedor de contactos sigue respetando. Contra una pared, el objeto empuja
## con a lo sumo Hold Accel Limit × su masa y se queda del lado de acá; no se
## teletransporta ni se desactivan sus choques. Desde el 2026-11-15 las
## velocidades las pone InvBodies al terminar cada tick, con las cuentas de
## InvHoldMotion (las mismas que predice la máquina del jugador), antes del paso
## de Jolt de ese mismo tick; hasta ese día iban en _integrate_forces, que Jolt
## llama antes del tick, y la mano usaba el pedido del tick anterior.
##
## El centro de masa es el de InvItemPhysics.center_of_mass (el mismo en todas
## las máquinas, para que la mano se prediga con el mismo). Mientras se
## sostiene, no tiene gravedad ni freno (la mano decide su velocidad) y avisa
## sus choques (contact_monitor), para que el host no adopte lo que afirma el
## cliente si en ese paso tocó algo.

var uid := 0
var def: InvItemDef
## Si es el cuerpo que simula esta máquina (el host).
var simulated := false

## Sostenido (solo el host): el punto agarrado, en el espacio del objeto; a
## dónde lo lleva la mano, en el mundo; y con qué giro. Los pone InvBodies en
## cada tick.
var hold_active := false
var hold_anchor := Vector3.ZERO
var hold_target := Vector3.ZERO
var hold_basis := Basis.IDENTITY
## Cuánto le falta al punto agarrado para llegar, en el último paso de física.
var hold_error := 0.0
var tuning: ActorTuning

## El cartel de arriba, o null si este objeto va sin cartel.
var _label: Label3D
var _shown := ""
var _focus: InteractFocus

static var _material: PhysicsMaterial


func setup(p_def: InvItemDef, stack: InvStack, show_label := true, p_simulated := false, p_tuning: ActorTuning = null) -> void:
	uid = stack.uid
	def = p_def
	simulated = p_simulated
	tuning = p_tuning
	var size := def.world_size if def != null else 0.4
	add_child(InvVisuals.world_model(def))
	if show_label:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 32
		_label.pixel_size = 0.004
		_label.outline_size = 8
		_label.no_depth_test = false
		# El cartel no gira con el objeto: va arriba de su centro, en el mundo.
		_label.top_level = true
		_label.position = Vector3.UP * (size + 0.25)
		add_child(_label)
	_focus = InteractFocus.new("", self, InteractFocus.mesh_bounds(self), _label)
	if simulated:
		collision_layer = InvItemPhysics.LAYER
		collision_mask = InvItemPhysics.MASK
		for part: Array in InvItemPhysics.parts(def):
			var holder := CollisionShape3D.new()
			holder.shape = part[0]
			holder.transform = part[1]
			add_child(holder)
		mass = InvItemPhysics.mass_of(def, tuning)
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = InvItemPhysics.center_of_mass(def)
		physics_material_override = material_for(tuning)
		angular_damp = tuning.item_angular_damp if tuning != null else 2.0
		continuous_cd = true
		can_sleep = true
	else:
		collision_layer = 0
		collision_mask = 0
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
	refresh(def, stack)


## El material común (roce y rebote del Tuning), uno solo para todos.
static func material_for(p_tuning: ActorTuning) -> PhysicsMaterial:
	var friction := p_tuning.item_friction if p_tuning != null else 0.8
	var bounce := p_tuning.item_bounce if p_tuning != null else 0.05
	if _material == null or _material.friction != friction or _material.bounce != bounce:
		_material = PhysicsMaterial.new()
		_material.friction = friction
		_material.bounce = bounce
	return _material


func refresh(p_def: InvItemDef, stack: InvStack) -> void:
	var text := p_def.display_name if p_def != null else String(stack.def_id)
	_focus.display_name = text
	if stack.quantity > 1:
		text += " ×%d" % stack.quantity
	if text != _shown:
		_shown = text
		if _label != null:
			_label.text = text


func _process(_delta: float) -> void:
	if _label != null:
		var size := def.world_size if def != null else 0.4
		_label.global_position = get_global_transform_interpolated().origin + Vector3.UP * (size + 0.25)


## Si este objeto lleva el cartel de arriba.
func has_label() -> bool:
	return _label != null


## Lo que marca el indicador cuando E elegiría este objeto: su modelo y el
## nombre visible del tipo, sin la cantidad. Mientras está marcado, el
## indicador oculta el cartel de arriba.
func interact_focus() -> InteractFocus:
	return _focus


## Una copia (cliente o lo soltado sin confirmar): la pone en `place`. Con
## `jump`, sin interpolar desde donde estaba (apareció o saltó lejos).
func place(where: Transform3D, jump := false) -> void:
	global_transform = where
	if jump:
		reset_physics_interpolation()


## Host: empieza a llevarlo la mano, por `anchor` (en el espacio del objeto).
## Sin gravedad ni freno (la velocidad la decide la mano en cada tick), sin
## dormirse y avisando sus choques.
func begin_hold(anchor: Vector3) -> void:
	hold_active = true
	hold_anchor = anchor
	hold_target = global_transform * anchor
	hold_basis = global_basis
	hold_error = 0.0
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	sleeping = false


## Host: la mano lo deja. Sigue con la velocidad que tenía, sin impulso, con su
## gravedad y su freno de siempre.
func end_hold() -> void:
	hold_active = false
	hold_error = 0.0
	gravity_scale = 1.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_COMBINE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_COMBINE
	angular_damp = tuning.item_angular_damp if tuning != null else 2.0
	can_sleep = true
	contact_monitor = false
	max_contacts_reported = 0
	sleeping = false


## Host: cuántos cuerpos tocó en el último paso de física (solo sostenido).
func touching() -> int:
	return get_colliding_bodies().size() if contact_monitor else 0
