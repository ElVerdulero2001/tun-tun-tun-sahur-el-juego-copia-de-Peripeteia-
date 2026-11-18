extends "res://prototypes/objetos_adaptador/play_room.gd"

var result_path := ""
var phase := 0
var carry_until := 0
var carry_start := Vector3.ZERO
var movement := 0.0
var rotation_radians := 0.0
var approach := false
var results: Array = []
var deadline := 0
var release_velocity := Vector3.ZERO
var launch_velocity := Vector3.ZERO

func _ready() -> void:
	super._ready()
	var role := "host"
	var port := DEFAULT_PORT
	var target := "127.0.0.1"
	for arg in OS.get_cmdline_user_args():
		if arg == "--role=client": role = "guest"
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--address="): target = arg.trim_prefix("--address=")
		if arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
	deadline = Time.get_ticks_msec() + 6500
	if not start_session(role, target, port): _finish(false, "start_failed")

func _guest_input(tick: int) -> ActorInput:
	var sampled := super._guest_input(tick)
	if phase == 2 or phase == 3:
		sampled.move.x = 1.0
	if phase == 4 and approach:
		sampled.move.y = 1.0
	return sampled

func _after_tick(tick: int) -> void:
	super._after_tick(tick)
	if session == "host": return
	if not ready_to_play or not adapter.ready_for_input or pending_id != 0:
		return
	var box := _sample()
	match phase:
		0:
			if tick >= 30 and _try_action(false): phase = 1
		1:
			if box.held:
				carry_start = actor.position
				carry_until = tick + 28
				_look(Vector2(100, 52), true)
				phase = 2
		2:
			var basis: Basis = box.pose.basis
			rotation_radians = maxf(rotation_radians, basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY))
			if tick >= carry_until:
				movement = actor.position.distance_to(carry_start)
				_look(Vector2(0, -160), false)
				if _try_action(false): phase = 3
		3:
			if not box.held:
				release_velocity = box.lv
				phase = 4
		4:
			if not box.held:
				var offset: Vector3 = box.pose.origin - _eyes()
				approach = Vector2(offset.x, offset.z).length() > 1.4
				if _aim_and_grab(box): phase = 5
		5:
			if box.held and _try_action(true): phase = 6
		6:
			if not box.held:
				launch_velocity = box.lv
				phase = 7
				var passed := movement > 0.4 and rotation_radians > 0.08 and launch_velocity.length() > 0.4
				passed = passed and results == ["applied", "applied", "applied", "applied"]
				_complete_host.rpc_id(1, passed)
				_finish(passed, "guest_finished")

func _aim_and_grab(box: Dictionary) -> bool:
	var pose: Transform3D = box.pose
	var look := (pose.origin - _eyes()).normalized()
	yaw = atan2(-look.x, -look.z)
	pitch = asin(look.y)
	return _try_action(false)

@rpc("authority", "call_remote", "reliable", 0)
func _room_result(id: int, result: String, tick: int, reason: String) -> void:
	if id == pending_id:
		results.append(result)
	super._room_result(id, result, tick, reason)

func _send_result(result: Dictionary) -> void:
	results.append(result.status)
	super._send_result(result)

@rpc("any_peer", "call_remote", "reliable", 0)
func _complete_host(ok: bool) -> void:
	if session == "host" and multiplayer.get_remote_sender_id() == peer_id:
		_finish(ok and results == ["applied", "applied", "applied", "applied"], "host_finished")

func _process(delta: float) -> void:
	super._process(delta)
	if Time.get_ticks_msec() > deadline:
		_finish(false, status.text)

func _finish(ok: bool, message: String) -> void:
	deadline = 0x7fffffffffffffff
	var result := {"status": "PASSED" if ok else "FAILED", "message": message, "results": results, "phase": phase,
		"tick": clock.tick if clock != null else -1, "movement": movement, "rotation_radians": rotation_radians,
		"release_velocity": str(release_velocity),
		"launch_velocity": str(launch_velocity), "note": note,
		"last_authority": adapter.last_authority() if adapter != null else {},
		"rendered_box_delta": box_visual.position.distance_to(_sample().get("pose", Transform3D.IDENTITY).origin)}
	if not result_path.is_empty(): FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(result))
	print(JSON.stringify(result))
	await get_tree().create_timer(0.10, true, false, true).timeout
	get_tree().quit(0 if ok else 1)
