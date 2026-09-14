class_name V3PhysicsBody
extends CharacterBody3D

## Capa física común del primer prototipo V3.
## Recibe una sola intención de velocidad por tick y es la única que escribe
## velocity o llama move_and_slide(). El resultado queda expuesto como hecho.
var _intent_source: Object = null
var _pending_horizontal_velocity := Vector3.ZERO

var last_requested_horizontal_velocity := Vector3.ZERO
var last_actual_velocity := Vector3.ZERO
var last_displacement := Vector3.ZERO
var last_collision_count := 0
var last_intent_source_name := "ninguno"


func _ready() -> void:
	process_physics_priority = 100


func submit_motion_intent(source: Object, desired_horizontal_velocity: Vector3) -> bool:
	if source == null:
		return false
	if _intent_source != null and _intent_source != source:
		push_warning("V3PhysicsBody recibió dos autoridades de movimiento en el mismo tick.")
		return false

	_intent_source = source
	_pending_horizontal_velocity = Vector3(desired_horizontal_velocity.x, 0.0, desired_horizontal_velocity.z)
	return true


func _physics_process(delta: float) -> void:
	var previous_position := global_position
	last_requested_horizontal_velocity = _pending_horizontal_velocity
	last_intent_source_name = _intent_source.name if _intent_source != null else "ninguno"

	velocity.x = _pending_horizontal_velocity.x
	velocity.z = _pending_horizontal_velocity.z
	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()

	last_actual_velocity = velocity
	last_displacement = global_position - previous_position
	last_collision_count = get_slide_collision_count()

	_intent_source = null
	_pending_horizontal_velocity = Vector3.ZERO


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
	}
