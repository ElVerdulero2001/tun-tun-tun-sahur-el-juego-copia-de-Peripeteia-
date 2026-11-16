extends "res://probe.gd"

## Local, trusted artifact exchange between two fresh engine processes.
## This is deliberately not a network decoder or an approved protocol.
var _export_path := ""
var _import_path := ""
var _identity_noise := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--export-checkpoint="): _export_path = arg.trim_prefix("--export-checkpoint=")
		if arg.begins_with("--import-checkpoint="): _import_path = arg.trim_prefix("--import-checkpoint=")
		if arg == "--identity-noise": _identity_noise = true
	super._ready()

func _build() -> void:
	# Change allocation history without changing the topology being imported.
	if _identity_noise:
		for i in 7:
			var noise := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			noise.add_child(shape)
			add_child(noise)
			noise.free()
	super._build()
	for child in get_children():
		if child is StaticBody3D: child.name = "Floor"
	for i in _bodies.size(): _bodies[i].name = "Body%d" % i

func _run() -> void:
	if not _manager.has_method("import_state"):
		_finish("BLOCKED", {"reason": "missing_import_api"}, 2)
		return
	if not _export_path.is_empty():
		_export_checkpoint()
	elif not _import_path.is_empty():
		_import_checkpoint()
	else:
		_finish("FAILED", {"reason": "missing_exchange_mode"}, 1)

func _export_checkpoint() -> void:
	var initial := _read()
	var binary = _manager.call("export_state", _space, "RustBincode")
	if typeof(binary) != TYPE_PACKED_BYTE_ARRAY or binary.is_empty():
		_finish("FAILED", {"reason": "empty_export"}, 1)
		return
	var expected := _simulate(true, false)
	var artifact := {"schema": 1, "dependency": VERSION, "initial": initial,
		"snapshot": binary, "history": expected.history, "body_ids": _body_ids()}
	var file := FileAccess.open(_export_path, FileAccess.WRITE)
	if file == null:
		_finish("FAILED", {"reason": "export_file_failed"}, 1)
		return
	file.store_var(artifact)
	file.close()
	var passed: bool = expected.dynamic_contact and expected.node_error <= EPS
	_finish("PASSED" if passed else "FAILED", {"exchange_role": "export",
		"scope": "two_processes_fixed_topology_trusted_file_only",
		"body_ids": _body_ids(), "snapshot_bytes": binary.size(), "dynamic_contact": expected.dynamic_contact,
		"node_error": expected.node_error}, 0 if passed else 1)

func _import_checkpoint() -> void:
	var file := FileAccess.open(_import_path, FileAccess.READ)
	if file == null or file.get_length() > 1_000_000:
		_finish("FAILED", {"reason": "missing_or_oversized_local_artifact"}, 1)
		return
	var artifact = file.get_var(false)
	file.close()
	if not artifact is Dictionary or artifact.get("schema") != 1 or artifact.get("dependency") != VERSION:
		_finish("FAILED", {"reason": "invalid_local_artifact"}, 1)
		return
	var ids_before := _body_ids()
	var wrong_branch := _simulate(false, false)
	var wrong := _compare(artifact.history, wrong_branch.history)
	# import_state returns void. Verify the state, never infer success from return.
	_manager.call("import_state", _space, artifact.snapshot)
	_flush()
	var restored := _compare([artifact.initial], [_read()])
	if not _within(restored):
		_finish("FAILED", {"reason": "import_not_restored", "error": restored}, 1)
		return
	var replay := _simulate(true, false)
	var error := _compare(artifact.history, replay.history)
	var distinct: bool = ids_before != artifact.body_ids
	var passed: bool = _within(error) and wrong.position > 0.0001 and distinct \
		and _identity_noise and replay.dynamic_contact and replay.node_error <= EPS and _effect_ledger.size() == 1
	_finish("PASSED" if passed else "FAILED", {"exchange_role": "import", "identity_noise": _identity_noise,
		"scope": "two_processes_fixed_topology_trusted_file_only",
		"source_body_ids": artifact.body_ids, "destination_body_ids": ids_before, "distinct_ids": distinct,
		"restored": restored, "cross_process_replay": error, "wrong_branch": wrong,
		"dynamic_contact": replay.dynamic_contact, "node_error": replay.node_error,
		"external_effects": _effect_ledger.size(), "native_impulses": _native_impulses}, 0 if passed else 1)

func _body_ids() -> Array:
	var ids: Array = []
	for body in _bodies:
		ids.append({"instance": body.get_instance_id(), "rid": body.get_rid().get_id()})
	return ids
