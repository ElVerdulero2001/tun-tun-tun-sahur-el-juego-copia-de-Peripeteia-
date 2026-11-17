extends Node3D

## Construction fixture. Independent verification remains Claude's responsibility.
## Binary artifacts here are locally generated/trusted, not a production decoder.
const DT := 1.0 / 60.0
var role := "local"
var artifact_path := ""
var result_path := ""
var port := 46231
var ready_path := ""
var checks: Array = []
var facts := {}
var started := 0
var sent_hash := ""
var sent_peer := 0
var artifact_bytes := PackedByteArray()
var done := false

func _ready() -> void:
	started = Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		elif arg.begins_with("--artifact="): artifact_path = arg.trim_prefix("--artifact=")
		elif arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--ready="): ready_path = arg.trim_prefix("--ready=")
	if not ClassDB.class_exists("SahurObjectWorld"):
		check("extension_registered", false)
		finish()
		return
	facts["engine"] = Engine.get_version_info().string
	facts["godot_backend"] = ProjectSettings.get_setting("physics/3d/physics_engine")
	check("keeps_jolt", facts.godot_backend == "Jolt Physics" and not ClassDB.class_exists("RapierPhysicsServer3D"))
	var sentinel := RigidBody3D.new()
	sentinel.position = Vector3(10, 4, 0)
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	sentinel.add_child(collision)
	add_child(sentinel)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var sentinel_before: Transform3D = PhysicsServer3D.body_get_state(sentinel.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	if role == "local":
		local_checks()
	elif role == "export" or role == "enet_export":
		artifact_bytes = make_artifact()
		if role == "export":
			var file := FileAccess.open(artifact_path, FileAccess.WRITE)
			check("artifact_file_open", file != null)
			if file != null: file.store_buffer(artifact_bytes); file.close()
	elif role == "import":
		artifact_bytes = FileAccess.get_file_as_bytes(artifact_path)
		import_artifact(artifact_bytes)
	var sentinel_after: Transform3D = PhysicsServer3D.body_get_state(sentinel.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	check("native_operations_leave_jolt_untouched", sentinel_before == sentinel_after)
	if role == "enet_export" or role == "enet_import":
		start_network()
	else: finish()

func _process(_delta: float) -> void:
	if not done and started > 0 and Time.get_ticks_usec() - started > 6_000_000:
		check("internal_deadline", false)
		finish()

func check(name: String, passed: bool, metric = null) -> void:
	checks.append({"name": name, "passed": passed, "metric": metric})
	if not passed: print("NATIVE_PROBE_FAIL " + name + " " + str(metric))

func new_world(reverse := false, sealed := true, wrong_size := false):
	var w = ClassDB.instantiate("SahurObjectWorld")
	check("create_floor", w.add_box(1, 1, Vector3(10, 0.2, 10), 0.0, at(0, -0.1, 0)))
	for uid in ([3, 2] if reverse else [2, 3]):
		var size := Vector3(0.5 if wrong_size and uid == 2 else 0.6, 0.4, 0.4)
		var p := at(0, 0.2, 0) if uid == 2 else Transform3D(Basis(Vector3(0, 0, 1), 0.2), Vector3(0.15, 1, 0))
		check("create_dynamic_" + str(uid), w.add_box(uid, 1, size, 2.0, p))
	if sealed: check("seal", w.seal_topology(1))
	return w

func at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))

func has_contact(sample: Dictionary, uid: int) -> bool:
	for other in sample.contacts:
		if other.uid == uid and other.epoch == 1: return true
	return false

func checkpoint_in_contact(w) -> int:
	for _i in 120:
		check("step_contact", w.step(DT))
		var a: Dictionary = w.sample(2, 1)
		var b: Dictionary = w.sample(3, 1)
		if has_contact(a, 3) and has_contact(b, 2) and b.lv.length() > 0.1:
			return w.cache_checkpoint()
	check("moving_contact_found", false)
	return -1

func simulate(w) -> Array:
	var history: Array = []
	for n in range(1, 361):
		if n == 30: check("impulse_A", w.apply_impulse(2, 1, Vector3(1.2, 0, 0)))
		if n == 240: check("impulse_B", w.apply_impulse(3, 1, Vector3(0.6, 0, 0)))
		check("step_replay", w.step(DT))
		history.append(w.samples())
	return history

func same(a, b) -> bool:
	return var_to_bytes(a) == var_to_bytes(b)

func local_checks() -> void:
	var mass_probe = ClassDB.instantiate("SahurObjectWorld")
	check("tiny_positive_mass_rejected", not mass_probe.add_box(1, 1, Vector3.ONE, 1.0e-300, at(0, 1, 0)))
	check("tiny_negative_mass_rejected", not mass_probe.add_box(1, 1, Vector3.ONE, -1.0e-300, at(0, 1, 0)))
	check("invalid_mass_keeps_world_empty", mass_probe.get_body_count() == 0)
	var w = new_world()
	facts["build"] = w.get_build_info()
	var cp := checkpoint_in_contact(w)
	facts["contact_tick"] = cp
	var initial = w.samples()
	var snapshot: PackedByteArray = w.snapshot_trusted()
	facts["snapshot_bytes"] = snapshot.size()
	check("snapshot_nonempty", snapshot.size() > 44)
	var reference := simulate(w)
	check("restore_cached", w.restore_cached(cp))
	check("restored_exact", same(initial, w.samples()))
	check("contact_replay_exact", same(reference, simulate(w)))
	var slept := false
	for samples_at in reference.slice(0, 239):
		if samples_at[1].sleeping and samples_at[2].sleeping: slept = true
	check("sleep_and_wake", slept and not reference[239][2].sleeping)
	var reversed = new_world(true)
	check("import_reverse_order", reversed.restore_trusted(snapshot))
	check("reverse_initial_exact", same(initial, reversed.samples()))
	check("reverse_replay_exact", same(reference, simulate(reversed)))
	var mismatch = new_world(false, true, true)
	var intact: PackedByteArray = mismatch.snapshot_trusted()
	check("shape_manifest_rejected", not mismatch.restore_trusted(snapshot))
	check("shape_rejection_atomic", intact == mismatch.snapshot_trusted())
	var other = new_world(false, false)
	var control = new_world(false, false)
	for world in [other, control]:
		check("create_X", world.add_box(100, 1, Vector3.ONE * 0.4, 1.0, at(2, 0.2, 0)))
		for _i in 30: check("other_step", world.step(DT))
	var other_before = other.samples()
	check("restore_with_other_live", w.restore_trusted(snapshot))
	check("other_unchanged", same(other_before, other.samples()))
	for world in [other, control]:
		check("create_Y", world.add_box(101, 1, Vector3.ONE * 0.4, 1.0, at(-2, 0.2, 0)))
		check("ray_identifies_X", world.cast_ray(Vector3(2, 3, 0), Vector3.DOWN, 5.0).get("uid") == 100)
		check("free_Y", world.remove_body(101, 1))
		check("ray_after_free_Y", world.cast_ray(Vector3(2, 3, 0), Vector3.DOWN, 5.0).get("uid") == 100)
		check("push_X", world.apply_impulse(100, 1, Vector3(3, 0, 0)))
	var initial_x: float = other.sample(100, 1).pose.origin.x
	var equal := true
	for _i in 120:
		other.step(DT); control.step(DT)
		equal = equal and same(other.samples(), control.samples())
	check("other_future_exact", equal)
	check("X_actually_moved", other.sample(100, 1).pose.origin.x > initial_x + 0.1)
	var before_invalid: PackedByteArray = w.snapshot_trusted()
	check("invalid_dt_rejected", not w.step(NAN))
	check("invalid_call_atomic", before_invalid == w.snapshot_trusted())

func make_artifact() -> PackedByteArray:
	var w = new_world()
	var cp := checkpoint_in_contact(w)
	var snapshot: PackedByteArray = w.snapshot_trusted()
	var initial = w.samples()
	var history := simulate(w)
	facts["export_tick"] = cp
	facts["snapshot_bytes"] = snapshot.size()
	return var_to_bytes({"schema": 1, "snapshot": snapshot, "initial": initial, "history": history})

func import_artifact(bytes: PackedByteArray) -> void:
	check("bounded_artifact", bytes.size() > 44 and bytes.size() <= 4_194_304)
	if bytes.is_empty() or bytes.size() > 4_194_304: return
	var artifact = bytes_to_var(bytes)
	check("artifact_schema", artifact is Dictionary and artifact.get("schema") == 1)
	if not artifact is Dictionary or artifact.get("schema") != 1: return
	var other = new_world(false, false)
	check("unrelated_object", other.add_box(100, 1, Vector3.ONE * 0.4, 1.0, at(2, 0.2, 0)))
	var before = other.samples()
	var destination = new_world(true)
	for _i in 40: check("advance_wrong_branch", destination.step(DT))
	check("different_branch", not same(destination.samples(), artifact.initial))
	check("import_trusted_checkpoint", destination.restore_trusted(artifact.snapshot))
	check("import_initial_exact", same(destination.samples(), artifact.initial))
	check("import_other_world_unchanged", same(before, other.samples()))
	check("import_replay_exact", same(simulate(destination), artifact.history))
	check("other_query_after_import", other.cast_ray(Vector3(2, 3, 0), Vector3.DOWN, 5.0).get("uid") == 100)
	facts["received_bytes"] = bytes.size()
	facts["received_sha256"] = sha256(bytes)

func sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()

func start_network() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err: int
	if role == "enet_export":
		err = peer.create_server(port, 1)
		multiplayer.peer_connected.connect(_send_artifact)
	else: err = peer.create_client("127.0.0.1", port)
	check("enet_start", err == OK)
	if err != OK: finish(); return
	multiplayer.multiplayer_peer = peer
	if role == "enet_export" and not ready_path.is_empty():
		var marker := FileAccess.open(ready_path, FileAccess.WRITE)
		if marker != null: marker.store_string("ready"); marker.close()

func _send_artifact(peer_id: int) -> void:
	sent_peer = peer_id
	sent_hash = sha256(artifact_bytes)
	facts["sent_bytes"] = artifact_bytes.size()
	facts["sent_sha256"] = sent_hash
	_receive_artifact.rpc_id(peer_id, artifact_bytes)

@rpc("authority", "call_remote", "reliable", 0)
func _receive_artifact(bytes: PackedByteArray) -> void:
	if role != "enet_import": return
	import_artifact(bytes)
	_received_ok.rpc_id(1, sha256(bytes))
	await get_tree().create_timer(0.1).timeout
	finish()

@rpc("any_peer", "call_remote", "reliable", 0)
func _received_ok(hash_text: String) -> void:
	if role != "enet_export": return
	check("enet_hash_ack", multiplayer.get_remote_sender_id() == sent_peer and hash_text == sent_hash)
	facts["acknowledged"] = true
	finish()

func finish() -> void:
	if done: return
	done = true
	var failures := checks.filter(func(c): return not c.passed).size()
	var result := {"schema": 1, "role": role, "status": "PASSED" if failures == 0 else "FAILED",
		"failures": failures, "checks": checks, "facts": facts,
		"seconds": float(Time.get_ticks_usec() - started) / 1_000_000.0,
		"scope": "construction_fixture_same_machine_fixed_topology_trusted_artifact"}
	if not result_path.is_empty():
		var file := FileAccess.open(result_path, FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(result, "  ")); file.close()
	print("NATIVE_OBJECT_RESULT role=%s status=%s failures=%d seconds=%.5f" % [role, result.status, failures, result.seconds])
	get_tree().quit(0 if failures == 0 else 1)
