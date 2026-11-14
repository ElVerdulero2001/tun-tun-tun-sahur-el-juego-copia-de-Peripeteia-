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
## toca los triángulos del modelo del tipo, con la pose de este objeto. El
## cuerpo físico no es lo que se agarra: un hueco del modelo sigue siendo hueco.
##
## Por qué la mano mueve el cuerpo con velocidades y no lo pone en su lugar:
## con Jolt, cambiar la velocidad en _integrate_forces es una fuerza acotada
## que el resolvedor de contactos sigue respetando. Contra una pared, el objeto
## empuja con a lo sumo Hold Accel Limit × su masa y se queda del lado de acá;
## no se teletransporta ni se desactivan sus choques. El giro se lleva igual,
## alrededor del punto agarrado (el centro de masa va adonde tiene que ir para
## que ese punto quede en su lugar con el giro pedido).

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
func begin_hold(anchor: Vector3) -> void:
	hold_active = true
	hold_anchor = anchor
	hold_target = global_transform * anchor
	hold_basis = global_basis
	hold_error = 0.0
	gravity_scale = 0.0
	sleeping = false


## Host: la mano lo deja. Sigue con la velocidad que tenía, sin impulso.
func end_hold() -> void:
	hold_active = false
	hold_error = 0.0
	gravity_scale = 1.0
	sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not simulated or not hold_active:
		return
	var step := maxf(state.step, 0.0001)
	var pose := state.transform
	var com_local := state.center_of_mass_local
	var com := pose * com_local
	hold_error = (pose * hold_anchor).distance_to(hold_target)
	# Donde tiene que estar el centro de masa para que el punto agarrado quede en
	# su lugar con el giro pedido.
	var wanted := hold_target - hold_basis * (hold_anchor - com_local)
	var follow := tuning.hold_follow_time if tuning != null else 0.08
	var move_limit := tuning.hold_move_limit if tuning != null else 12.0
	var accel_limit := tuning.hold_accel_limit if tuning != null else 80.0
	var turn_limit := deg_to_rad(tuning.hold_turn_limit if tuning != null else 720.0)
	var turn_accel := deg_to_rad(tuning.hold_turn_accel if tuning != null else 7200.0)
	var velocity := ((wanted - com) / follow).limit_length(move_limit)
	state.linear_velocity += (velocity - state.linear_velocity).limit_length(accel_limit * step)
	var error := Quaternion(hold_basis.orthonormalized()) * Quaternion(pose.basis.orthonormalized()).inverse()
	if error.w < 0.0:
		error = -error
	var angle := 2.0 * acos(clampf(error.w, -1.0, 1.0))
	var spin := Vector3.ZERO
	if angle > 0.0001:
		var axis := Vector3(error.x, error.y, error.z) / maxf(sin(angle * 0.5), 0.000001)
		spin = (axis.normalized() * angle / follow).limit_length(turn_limit)
	state.angular_velocity += (spin - state.angular_velocity).limit_length(turn_accel * step)
	state.sleeping = false
