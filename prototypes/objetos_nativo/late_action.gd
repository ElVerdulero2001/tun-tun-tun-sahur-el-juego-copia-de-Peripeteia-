extends "res://probe.gd"

## A fixed, prearranged hand timeline, not the game's actor/input adapter.
## Release is predicted at 46 but sent over real ENet at 74 and duplicated at 95.
## Authority applies it at its next safe step and sends a complete native state.
## Compare both worlds at physical tick 140, never at packet arrival time.
const FINAL_TICK := 140
var world
var running := false
var peer_id := 0
var pending_release := false
var release_tick := 0
var release_calls := 0
var duplicate_requests := 0
var duplicate_confirmations := 0
var authoritative_checkpoint := PackedByteArray()
var pending_checkpoint := PackedByteArray()
var pending_checkpoint_tick := 0
var reconciled := false
var replay_steps := 0
var state_at_final := PackedByteArray()
var reference_bytes := PackedByteArray()
var reference_sent := false

func _ready() -> void:
	started = Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		elif arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--ready="): ready_path = arg.trim_prefix("--ready=")
	if not ClassDB.class_exists("SahurObjectWorld"):
		check("extension_registered", false); finish(); return
	check("keeps_jolt", ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics")
	world = new_world(role == "late_client")
	facts["timeline"] = "prearranged_hand_goals_release_predicted_46_sent_74_duplicate_95"
	facts["transport"] = "real_ENet_localhost"
	var peer := ENetMultiplayerPeer.new()
	var err: int
	if role == "late_host":
		err = peer.create_server(port, 1)
		multiplayer.peer_connected.connect(_start_peer)
	else: err = peer.create_client("127.0.0.1", port)
	check("enet_start", err == OK)
	if err != OK: finish(); return
	multiplayer.multiplayer_peer = peer
	if role == "late_host":
		var marker := FileAccess.open(ready_path, FileAccess.WRITE)
		if marker != null: marker.store_string("ready"); marker.close()

func _start_peer(id: int) -> void:
	peer_id = id
	_start_world.rpc_id(id, world.snapshot_trusted())

@rpc("authority", "call_remote", "reliable", 0)
func _start_world(bytes: PackedByteArray) -> void:
	if role != "late_client": return
	check("initial_authority_checkpoint", world.restore_trusted(bytes))
	running = true
	# A declared fixture lead; production clock adaptation remains separate.
	for _i in 4: client_step()
	_client_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable", 0)
func _client_ready() -> void:
	if role == "late_host" and multiplayer.get_remote_sender_id() == peer_id: running = true

func _physics_process(_delta: float) -> void:
	if not running or done: return
	if role == "late_host": host_step()
	else: client_step()

func goals_for(n: int, predict_release: bool, replay := false) -> void:
	if n == 1:
		check("begin_hold", world.begin_hold(2, 1, Vector3.ZERO, at(-0.5, 0.7, 0)))
	if n >= 2 and n <= 45:
		var goal := Transform3D(Basis(Vector3.UP, float(n) * 0.01), Vector3(-0.5 + float(n) * 0.003, 0.7, 0))
		check("hand_goal", world.set_goal(2, 1, goal))
	if n == 46 and predict_release:
		check("predicted_release", world.release_body(2, 1, Vector3(1, 0.6, 0)))
		if not replay: release_calls += 1

func host_step() -> void:
	if world.get_tick() >= FINAL_TICK: return
	var n: int = world.get_tick() + 1
	goals_for(n, false)
	var applied := false
	if pending_release and release_tick == 0:
		check("authority_release", world.release_body(2, 1, Vector3(1, 0.6, 0)))
		pending_release = false
		release_tick = n
		release_calls += 1
		applied = true
	check("authority_step", world.step(DT))
	if applied:
		authoritative_checkpoint = world.snapshot_trusted()
		_authority_checkpoint.rpc_id(peer_id, release_tick, 46, 1, authoritative_checkpoint)
	if n == FINAL_TICK and not reference_sent:
		reference_sent = true
		reference_bytes = var_to_bytes(world.samples())
		_reference.rpc_id(peer_id, FINAL_TICK, reference_bytes)

func client_step() -> void:
	if world.get_tick() >= FINAL_TICK: try_compare(); return
	var n: int = world.get_tick() + 1
	goals_for(n, true)
	check("prediction_step", world.step(DT))
	if n == 74 or n == 95: _release_intent.rpc_id(1, 46, 1)
	try_reconcile()
	if world.get_tick() == FINAL_TICK:
		state_at_final = var_to_bytes(world.samples())
		try_compare()

@rpc("any_peer", "call_remote", "reliable", 0)
func _release_intent(requested_tick: int, action: int) -> void:
	if role != "late_host": return
	var valid: bool = multiplayer.get_remote_sender_id() == peer_id and requested_tick == 46 and action == 1
	check("release_request_identity", valid)
	if not valid: return
	if release_tick > 0:
		duplicate_requests += 1
		_authority_checkpoint.rpc_id(peer_id, release_tick, requested_tick, action, authoritative_checkpoint)
	else: pending_release = true

@rpc("authority", "call_remote", "reliable", 0)
func _authority_checkpoint(applied_tick: int, requested_tick: int, action: int, bytes: PackedByteArray) -> void:
	if role != "late_client": return
	check("confirmation_identity", action == 1 and requested_tick == 46 and applied_tick > requested_tick)
	if reconciled:
		duplicate_confirmations += 1
		return
	pending_checkpoint = bytes
	pending_checkpoint_tick = applied_tick
	try_reconcile()

func try_reconcile() -> void:
	if reconciled or pending_checkpoint.is_empty(): return
	# Ensure this fixture exercises actual replay even if process scheduling
	# temporarily put the client behind. This is not a production latency rule.
	if world.get_tick() < pending_checkpoint_tick + 2: return
	var target_tick: int = world.get_tick()
	check("restore_authority_for_late_action", world.restore_trusted(pending_checkpoint))
	check("checkpoint_tick_matches", world.get_tick() == pending_checkpoint_tick)
	for n in range(pending_checkpoint_tick + 1, target_tick + 1):
		goals_for(n, true, true)
		check("replay_step", world.step(DT))
		replay_steps += 1
	check("replay_reaches_previous_present", world.get_tick() == target_tick)
	reconciled = true
	facts["requested_release_tick"] = 46
	facts["authority_applied_tick"] = pending_checkpoint_tick
	facts["predicted_present_at_correction"] = target_tick
	facts["replayed_steps"] = replay_steps
	pending_checkpoint.clear()

@rpc("authority", "call_remote", "reliable", 0)
func _reference(tick: int, bytes: PackedByteArray) -> void:
	if role != "late_client": return
	check("reference_tick", tick == FINAL_TICK)
	reference_bytes = bytes
	try_compare()

func try_compare() -> void:
	if role != "late_client" or done or reference_bytes.is_empty() or state_at_final.is_empty(): return
	check("same_physical_tick_140_exact", state_at_final == reference_bytes)
	check("actually_replayed", reconciled and replay_steps >= 2)
	check("prediction_release_called_once", release_calls == 1)
	check("duplicate_confirmation_ignored", duplicate_confirmations >= 1)
	facts["compared_tick"] = FINAL_TICK
	facts["state_sha256"] = sha256(state_at_final)
	facts["duplicate_confirmations"] = duplicate_confirmations
	_audit_ack.rpc_id(1, sha256(state_at_final))
	running = false
	await get_tree().create_timer(0.1).timeout
	finish()

@rpc("any_peer", "call_remote", "reliable", 0)
func _audit_ack(hash_text: String) -> void:
	if role != "late_host": return
	check("same_tick_reference_ack", multiplayer.get_remote_sender_id() == peer_id and hash_text == sha256(reference_bytes))
	check("authority_release_called_once", release_calls == 1)
	check("release_actually_arrived_late", release_tick > 46)
	check("duplicate_request_did_not_release_again", duplicate_requests >= 1 and release_calls == 1)
	facts["requested_release_tick"] = 46
	facts["authority_applied_tick"] = release_tick
	facts["duplicate_requests"] = duplicate_requests
	facts["state_sha256"] = sha256(reference_bytes)
	finish()
