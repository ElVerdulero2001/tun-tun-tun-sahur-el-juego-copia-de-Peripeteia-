class_name V3PhysicsBody
extends CharacterBody3D

enum CrouchAnchor { GROUND, AIR }

## Capa física común del primer prototipo V3.
## Recibe una sola intención de velocidad por tick y es la única que escribe
## velocity o llama move_and_slide(). El resultado queda expuesto como hecho.
var _intent_source: Object = null
var _pending_horizontal_velocity := Vector3.ZERO
var _pending_jump := false
var _pending_crouched := false

var last_requested_horizontal_velocity := Vector3.ZERO
var last_actual_velocity := Vector3.ZERO
var last_displacement := Vector3.ZERO
var last_collision_count := 0
var last_intent_source_name := "ninguno"
var last_jump_requested := false
var last_jump_accepted := false
var fall_distance_in_current_airtime := 0.0
var last_landing_fall_distance := 0.0
var is_crouched := false
var last_crouch_requested := false
var last_stand_request_blocked := false
var crouch_anchor := CrouchAnchor.GROUND
var stance_anchor_revision := 0
var last_stance_anchor_rebase_delta := 0.0
@export var jump_velocity := 5.0
@export var collision_shape: CollisionShape3D
@export var crouched_height := 1.2

var _standing_shape: CapsuleShape3D
var _crouched_shape: CapsuleShape3D
var _standing_height := 0.0


func _ready() -> void:
	process_physics_priority = 100
	if collision_shape == null or not collision_shape.shape is CapsuleShape3D:
		push_error("V3PhysicsBody necesita un CollisionShape3D con CapsuleShape3D para usar crouch.")
		return
	_standing_shape = (collision_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	_standing_height = _standing_shape.height
	_crouched_shape = _standing_shape.duplicate() as CapsuleShape3D
	_crouched_shape.height = maxf(crouched_height, _crouched_shape.radius * 2.0)
	_apply_crouched_shape(false, CrouchAnchor.GROUND)


func submit_motion_intent(source: Object, desired_horizontal_velocity: Vector3, jump_requested := false, crouch_requested := false) -> bool:
	if source == null:
		return false
	if _intent_source != null and _intent_source != source:
		push_warning("V3PhysicsBody recibió dos autoridades de movimiento en el mismo tick.")
		return false

	_intent_source = source
	_pending_horizontal_velocity = Vector3(desired_horizontal_velocity.x, 0.0, desired_horizontal_velocity.z)
	_pending_jump = _pending_jump or jump_requested
	_pending_crouched = crouch_requested
	return true


func _physics_process(delta: float) -> void:
	var previous_position := global_position
	var was_on_floor := is_on_floor()
	last_requested_horizontal_velocity = _pending_horizontal_velocity
	last_intent_source_name = _intent_source.name if _intent_source != null else "ninguno"
	last_jump_requested = _pending_jump
	last_jump_accepted = false
	last_landing_fall_distance = 0.0
	last_crouch_requested = _pending_crouched
	last_stand_request_blocked = false
	_apply_requested_stance(was_on_floor)

	velocity.x = _pending_horizontal_velocity.x
	velocity.z = _pending_horizontal_velocity.z
	if _pending_jump and is_on_floor():
		velocity.y = jump_velocity
		last_jump_accepted = true
	elif not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()

	var movement_displacement := global_position - previous_position
	var is_on_floor_after_move := is_on_floor()
	if movement_displacement.y < 0.0 and not was_on_floor:
		fall_distance_in_current_airtime += -movement_displacement.y
	if is_on_floor_after_move:
		if not was_on_floor:
			last_landing_fall_distance = fall_distance_in_current_airtime
		fall_distance_in_current_airtime = 0.0
	_sync_crouch_anchor(is_on_floor_after_move)

	last_actual_velocity = velocity
	last_displacement = global_position - previous_position
	last_collision_count = get_slide_collision_count()

	_intent_source = null
	_pending_horizontal_velocity = Vector3.ZERO
	_pending_jump = false
	_pending_crouched = false


func get_physics_facts() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"is_on_floor": is_on_floor(),
		"collision_count": last_collision_count,
		"requested_horizontal_velocity": last_requested_horizontal_velocity,
		"actual_velocity": last_actual_velocity,
		"displacement": last_displacement,
		"intent_source": last_intent_source_name,
		"jump_requested": last_jump_requested,
		"jump_accepted": last_jump_accepted,
		"fall_distance_in_current_airtime": fall_distance_in_current_airtime,
		"last_landing_fall_distance": last_landing_fall_distance,
		"is_crouched": is_crouched,
		"crouch_requested": last_crouch_requested,
		"stand_request_blocked": last_stand_request_blocked,
		"crouch_anchor": "piso" if crouch_anchor == CrouchAnchor.GROUND else "aire",
	}


## Consulta física hipotética para cores: responde si el collider actual del
## player podría ocupar una pose sin penetrar. No mueve ni cambia velocity.
func can_occupy_pose(pose: Transform3D) -> bool:
	return not test_move(pose, Vector3.ZERO, null, 0.001, true)


func _apply_requested_stance(is_on_floor_now: bool) -> void:
	if collision_shape == null or _standing_shape == null or _crouched_shape == null:
		return
	if _pending_crouched:
		_apply_crouched_shape(true, _anchor_for_support(is_on_floor_now))
	elif is_crouched:
		if _can_stand():
			_apply_crouched_shape(false, CrouchAnchor.GROUND)
		else:
			last_stand_request_blocked = true


func _apply_crouched_shape(should_crouch: bool, anchor: CrouchAnchor) -> void:
	if collision_shape == null:
		return
	is_crouched = should_crouch
	crouch_anchor = anchor
	var active_shape := _crouched_shape if is_crouched else _standing_shape
	collision_shape.shape = active_shape
	collision_shape.position.y = _crouch_center_for_anchor(anchor) if is_crouched else _standing_height * 0.5


func _sync_crouch_anchor(is_on_floor_after_move: bool) -> void:
	if not is_crouched:
		return
	var desired_anchor := _anchor_for_support(is_on_floor_after_move)
	if desired_anchor == crouch_anchor:
		return

	var previous_center := collision_shape.position.y
	var new_center := _crouch_center_for_anchor(desired_anchor)
	last_stance_anchor_rebase_delta = 0.0
	if desired_anchor == CrouchAnchor.GROUND:
		# Al aterrizar, reubicamos el root para conservar exactamente la misma
		# cápsula en el mundo mientras cambia su referencia local al piso.
		last_stance_anchor_rebase_delta = previous_center - new_center
		global_position.y += last_stance_anchor_rebase_delta
	collision_shape.position.y = new_center
	crouch_anchor = desired_anchor
	stance_anchor_revision += 1


func _anchor_for_support(is_on_floor_now: bool) -> CrouchAnchor:
	return CrouchAnchor.GROUND if is_on_floor_now else CrouchAnchor.AIR


func _crouch_center_for_anchor(anchor: CrouchAnchor) -> float:
	if anchor == CrouchAnchor.GROUND:
		# En piso, la base queda fija y baja sólo la parte superior.
		return _crouched_shape.height * 0.5
	# En aire, el centro físico queda en su referencia normal: la cápsula se
	# encoge alrededor de él y los pies suben sin mover la cámara.
	return _standing_height * 0.5


func _can_stand() -> bool:
	# No consultamos la cápsula alta completa: al estar apoyada puede considerar
	# el contacto válido con el piso como una obstrucción. En cambio, probamos
	# desplazar la cápsula agachada sólo hacia arriba por la altura que falta.
	# Ese barrido cubre exactamente el volumen nuevo que ocuparía al pararse y
	# no confunde el suelo actual con un techo.
	var extra_height := _standing_height - _crouched_shape.height
	return not test_move(global_transform, Vector3.UP * extra_height)
