extends RigidBody3D

## Cuerpo nativo compartido por host y predictor. No integra caídas a mano.
## prepare() se llama una vez en _physics_process, después de capturar el
## resultado del paso anterior y antes del siguiente paso de Jolt.
const State := preload("res://runtime/state.gd")

var prepared_tick := -1
var held := false
var anchor := Vector3.ZERO
var goal := Transform3D.IDENTITY
var impulse_count := 0
var native_callbacks := 0
var native_dt := 0.0
var native_frame := -1
var size := Vector3(0.6, 0.4, 0.4)
var model: MeshInstance3D
var collider: CollisionShape3D

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mass = 2.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, size.y * 0.5, 0)
	continuous_cd = true
	collision_layer = 8
	collision_mask = 1 | 4 | 8
	contact_monitor = true
	max_contacts_reported = 16
	angular_damp = 2.0
	var material := PhysicsMaterial.new()
	material.friction = 0.8
	material.bounce = 0.05
	physics_material_override = material
	var shape := BoxShape3D.new()
	shape.size = size
	collider = CollisionShape3D.new()
	collider.name = "PhysicalShape"
	collider.shape = shape
	collider.position.y = size.y * 0.5
	add_child(collider)
	model = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	model.mesh = mesh
	model.position.y = size.y * 0.5
	add_child(model)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Observación del callback, sin simular pasos extra ni etiquetarlo como el
	# input que todavía no leyó _physics_process.
	native_callbacks += 1
	native_dt = state.step
	native_frame = Engine.get_physics_frames()

func capture(record):
	var out = record.copy()
	out.tick = maxi(prepared_tick, 0)
	out.pose = global_transform
	out.lv = linear_velocity
	out.av = angular_velocity
	out.sleeping = sleeping
	return out

func set_simulated(active: bool) -> void:
	freeze = not active
	collision_layer = 8 if active else 0
	collision_mask = (1 | 4 | 8) if active else 0
	if active:
		sleeping = false

func set_proxy(active: bool, pose: Transform3D) -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 8 if active else 0
	collision_mask = 8 if active else 0
	if active:
		global_transform = pose

func begin_hold(point: Vector3, target: Transform3D) -> void:
	held = true
	anchor = point
	goal = target
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	can_sleep = false
	sleeping = false

func release(impulse := Vector3.ZERO) -> void:
	held = false
	gravity_scale = 1.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_COMBINE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_COMBINE
	angular_damp = 2.0
	can_sleep = true
	sleeping = false
	if impulse.length_squared() > 0.0:
		apply_central_impulse(impulse)
		impulse_count += 1

func prepare(tick: int, dt: float) -> void:
	assert(tick > prepared_tick, "Un paso físico no admite dos preparaciones")
	prepared_tick = tick
	if freeze or not held:
		return
	var basis := goal.basis.orthonormalized()
	var wanted := goal.origin - basis * (anchor - center_of_mass)
	var com := global_transform * center_of_mass
	var desired := ((wanted - com) / 0.08).limit_length(12.0)
	linear_velocity += (desired - linear_velocity).limit_length(80.0 * dt)
	var error := Quaternion(basis) * Quaternion(global_basis.orthonormalized()).inverse()
	if error.w < 0.0:
		error = -error
	var angle := 2.0 * acos(clampf(error.w, -1.0, 1.0))
	var desired_spin := Vector3.ZERO
	if angle > 0.0001:
		var axis := Vector3(error.x, error.y, error.z).normalized()
		desired_spin = (axis * angle / 0.08).limit_length(deg_to_rad(720.0))
	angular_velocity += (desired_spin - angular_velocity).limit_length(deg_to_rad(7200.0) * dt)

func reseed(sample) -> void:
	# Solo aparición/recuperación explícita, no escritura del dibujo por frame.
	global_transform = sample.pose
	linear_velocity = sample.lv
	angular_velocity = sample.av
	sleeping = sample.sleeping
	reset_physics_interpolation()

func safe_correction(delta: Transform3D, velocity_delta: Vector3, spin_delta: Vector3) -> bool:
	var target := delta * global_transform
	var motion := PhysicsTestMotionParameters3D.new()
	motion.from = global_transform
	motion.motion = target.origin - global_position
	motion.margin = 0.001
	if PhysicsServer3D.body_test_motion(get_rid(), motion):
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = target * collider.transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	global_transform = target
	linear_velocity += velocity_delta
	angular_velocity += spin_delta
	return true
