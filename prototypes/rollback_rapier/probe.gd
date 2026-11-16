extends Node3D

## Ensayo de capacidad, no implementación de red. Se valida la API de la
## versión fijada v0.36.0: StateManager3D (sin prefijo Rapier), no se infiere
## desde los nombres de la documentación de versiones posteriores.
const VERSION := "v0.36.0"
const DT := 1.0 / 60.0
const STEPS := 90
const EPS := 0.00001
var _bodies: Array[RigidBody3D] = []
var _space: RID
var _manager: Node
var _result_path := ""
var _started := 0
var _native_impulses := 0
var _effect_ledger := {}

func _ready() -> void:
	_started = Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="): _result_path = arg.trim_prefix("--result=")
	if ProjectSettings.get_setting("physics/3d/physics_engine") != "Rapier3D" \
		or not ClassDB.class_exists("RapierPhysicsServer3D") or not ClassDB.class_exists("StateManager3D"):
		_finish("BLOCKED", {"reason": "backend_not_prepared"}, 2)
		return
	for method in ["space_step", "space_flush_queries"]:
		if not ClassDB.class_has_method("RapierPhysicsServer3D", method):
			_finish("BLOCKED", {"reason": "missing_api", "method": method}, 2)
			return
	_manager = ClassDB.instantiate("StateManager3D")
	add_child(_manager)
	_manager.set("root_node", self)
	for method in ["cache_state", "ordered_cache_tags", "load_cached_state", "export_state"]:
		if not _manager.has_method(method):
			_finish("BLOCKED", {"reason": "missing_state_api", "method": method}, 2)
			return
	_build()
	# Dejar que Godot registre los cuerpos y sus callbacks antes del ensayo.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = get_world_3d().space
	PhysicsServer3D.space_set_active(_space, false)
	_flush()
	_run()

func _build() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.1
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(10, 0.2, 10)
	var floor_collision := CollisionShape3D.new()
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	add_child(floor_body)
	for position_at in [Vector3(0, 1.4, 0), Vector3(0, 0.2, 0)]:
		var body := RigidBody3D.new()
		body.position = position_at
		body.mass = 2.0
		body.continuous_cd = true
		body.contact_monitor = true
		body.max_contacts_reported = 16
		var material := PhysicsMaterial.new()
		material.friction = 0.8
		material.bounce = 0.05
		body.physics_material_override = material
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.6, 0.4, 0.4)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		_bodies.append(body)

func _run() -> void:
	var initial := _read()
	_manager.call("cache_state", _space, "initial")
	var tags: Array = _manager.call("ordered_cache_tags")
	var index := tags.find("initial")
	var binary = _manager.call("export_state", _space, "RustBincode")
	if index < 0 or typeof(binary) != TYPE_PACKED_BYTE_ARRAY or binary.is_empty():
		_finish("FAILED", {"reason": "snapshot_not_created"}, 1)
		return
	var expected := _simulate(true, false)
	if not _restore(index, initial): return
	var repeated := _simulate(true, true)
	var same := _compare(expected.history, repeated.history)
	if not _restore(index, initial): return
	var predicted_without_input := _simulate(false, false)
	if not _restore(index, initial): return
	var corrected_late := _simulate(true, true)
	var late := _compare(expected.history, corrected_late.history)
	var changed := _compare(expected.history, predicted_without_input.history)
	var moved := _compare([initial], [expected.history.back()])
	var passed: bool = _within(same) and _within(late) and changed.position > 0.0001 \
		and moved.position > 0.0001 and expected.dynamic_contact and _effect_ledger.size() == 1 \
		and expected.node_error <= EPS and repeated.node_error <= EPS and corrected_late.node_error <= EPS
	_finish("PASSED" if passed else "FAILED", {"snapshot_bytes": binary.size(), "steps_per_branch": STEPS,
		"same_replay": same, "late_replay": late, "change_without_command": changed,
		"actual_motion": moved, "dynamic_contact": expected.dynamic_contact,
		"node_error": maxf(expected.node_error, maxf(repeated.node_error, corrected_late.node_error)),
		"native_impulse_applications": _native_impulses, "external_effects": _effect_ledger.size()}, 0 if passed else 1)

func _restore(index: int, expected: Array) -> bool:
	var loaded = _manager.call("load_cached_state", _space, index)
	_flush()
	var error := _compare([expected], [_read()])
	if loaded != true or not _within(error):
		_finish("FAILED", {"reason": "restore_not_verified", "return_value": loaded, "error": error}, 1)
		return false
	return true

func _simulate(with_command: bool, replay: bool) -> Dictionary:
	var history: Array = []
	var dynamic_contact := false
	var node_error := 0.0
	for step in range(1, STEPS + 1):
		if with_command and step == 20:
			PhysicsServer3D.body_apply_central_impulse(_bodies[0].get_rid(), Vector3(1, 0, 0))
			_native_impulses += 1
			if not replay: _effect_ledger["action_1"] = true
		ClassDB.class_call_static("RapierPhysicsServer3D", "space_step", _space, DT)
		_flush()
		var sample := _read()
		history.append(sample)
		for i in _bodies.size():
			node_error = maxf(node_error, _bodies[i].global_position.distance_to(sample[i].pose.origin))
		dynamic_contact = dynamic_contact or _bodies[0].get_colliding_bodies().has(_bodies[1])
	return {"history": history, "dynamic_contact": dynamic_contact, "node_error": node_error}

func _flush() -> void:
	ClassDB.class_call_static("RapierPhysicsServer3D", "space_flush_queries", _space)

func _read() -> Array:
	var states: Array = []
	for body in _bodies:
		var rid := body.get_rid()
		states.append({"pose": PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM),
			"lv": PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY),
			"av": PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY),
			"sleep": PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING)})
	return states

func _compare(a: Array, b: Array) -> Dictionary:
	var error := {"position": 0.0, "basis": 0.0, "velocity": 0.0, "sleep_mismatches": 0}
	if a.size() != b.size():
		error.position = INF
		return error
	for step in a.size():
		for body in _bodies.size():
			var x: Dictionary = a[step][body]
			var y: Dictionary = b[step][body]
			error.position = maxf(error.position, x.pose.origin.distance_to(y.pose.origin))
			for axis in 3: error.basis = maxf(error.basis, (x.pose.basis[axis] - y.pose.basis[axis]).length())
			error.velocity = maxf(error.velocity, maxf(x.lv.distance_to(y.lv), x.av.distance_to(y.av)))
			if x.sleep != y.sleep: error.sleep_mismatches += 1
	return error

func _within(error: Dictionary) -> bool:
	return error.position <= EPS and error.basis <= EPS and error.velocity <= EPS and error.sleep_mismatches == 0

func _finish(status: String, fields: Dictionary, code: int) -> void:
	var result := {"schema": 1, "status": status, "dependency": VERSION,
		"engine": Engine.get_version_info().string, "backend_class": PhysicsServer3D.get_class(),
		"seconds": float(Time.get_ticks_usec() - _started) / 1_000_000.0,
		"scope": fields.get("scope", "single_process_fixed_topology_capability_only")}
	result.merge(fields)
	if not _result_path.is_empty():
		var file := FileAccess.open(_result_path, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(result, "  "))
	print("ROLLBACK_CAPABILITY " + JSON.stringify(result))
	get_tree().quit(code)
