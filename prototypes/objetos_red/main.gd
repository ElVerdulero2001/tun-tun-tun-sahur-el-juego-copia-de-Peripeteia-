extends Node3D

## Adaptador de demostración y traza. Las pruebas y los umbrales los mantiene
## Claude en validation/, sin modificar estos componentes para hacerlos pasar.
const State := preload("res://runtime/state.gd")
const Authority := preload("res://runtime/authority.gd")
const PhysicalBody := preload("res://runtime/body.gd")
const Presentation := preload("res://runtime/presentation.gd")
const Prediction := preload("res://runtime/prediction.gd")
const HandInput := preload("res://runtime/hand_input.gd")
const HandTimeline := preload("res://runtime/hand_timeline.gd")
const HandRotation := preload("res://runtime/hand_rotation.gd")
const RATE := 60
const DT := 1.0 / RATE
const BUFFER_TICKS := 6
const THROW_IMPULSE := 16.0

var role := "solo"
var mode := "prediction"
var port := 43171
var join_address := "127.0.0.1"
var tick := 0
var ready_for_input := false
var rtt_ms := 0.0
var rate_hz := RATE
var slow := 1.0
var objects := {}
var local_uid := 0
var local_session := 0
var next_action := 1
var target := Transform3D.IDENTITY
var camera_drives_goal := true
var camera: Camera3D
var label: Label
var trace_file: FileAccess
var network: ENetMultiplayerPeer
var _inbound: Array[Dictionary] = []
var _local_commands: Array[Dictionary] = []
var _dependent := ""
var _dependent_command := {}
var _pending_grab_uid := 0
var _pending_grab := 0
var _server_tick := 0
var _server_at_usec := 0
var _last_ping_usec := 0
var _next_ping_usec := 0
var _started_usec := 0
var _duration_ms := 0
var _trace_path := ""
var _rotation := HandRotation.new()
var _goal_rotation: Basis:
	get: return _rotation.basis()
	set(value):
		if not _rotation.reset_basis(value): _log("invalid_local_rotation", {})
var _hold_distance := 2.0
var _one_way_ms := 0
var _jitter_ms := 0
var _loss := 0.0
var _wire: Array[Dictionary] = []
var _reliable_due := {}
var _random := RandomNumberGenerator.new()
var _initialized_world := false
var _configuration_signature := ""
var _local_peer_id := 1
var _session_lost := false
var _hand_timeline := HandTimeline.new()
var _hand_history: Array = []

func _ready() -> void:
	_started_usec = Time.get_ticks_usec()
	_random.seed = 12345
	for argument in OS.get_cmdline_user_args():
		if argument == "--host": role = "host"
		elif argument.begins_with("--join="): role = "client"; join_address = argument.trim_prefix("--join=")
		elif argument.begins_with("--port="): port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--slow="): slow = float(argument.trim_prefix("--slow="))
		elif argument.begins_with("--duration-ms="): _duration_ms = int(argument.trim_prefix("--duration-ms="))
		elif argument.begins_with("--trace="): _trace_path = argument.trim_prefix("--trace=")
		elif argument.begins_with("--one-way-ms="): _one_way_ms = int(argument.trim_prefix("--one-way-ms="))
		elif argument.begins_with("--jitter-ms="): _jitter_ms = int(argument.trim_prefix("--jitter-ms="))
		elif argument.begins_with("--loss="): _loss = float(argument.trim_prefix("--loss="))
	if mode not in ["prediction", "reference"] or slow <= 0.0 or slow > 1.0 \
		or _loss < 0.0 or _loss > 0.5 or _one_way_ms < 0 or _jitter_ms < 0:
		push_error("Parámetros inválidos")
		get_tree().quit(2)
		return
	Engine.physics_ticks_per_second = RATE
	Engine.time_scale = slow
	if not _trace_path.is_empty():
		trace_file = FileAccess.open(_trace_path, FileAccess.WRITE)
		if trace_file == null:
			push_error("No se pudo abrir la traza: " + _trace_path)
			get_tree().quit(2)
			return
	_build_world()
	_configuration_signature = _build_fingerprint()
	if role != "solo":
		network = ENetMultiplayerPeer.new()
		var error := network.create_server(port, 2, 3) if role == "host" else network.create_client(join_address, port, 3)
		if error != OK:
			push_error("No se pudo abrir ENet: %d" % error)
			get_tree().quit(2)
			return
		multiplayer.multiplayer_peer = network
		multiplayer.peer_connected.connect(_connected)
		multiplayer.peer_disconnected.connect(_disconnected)
		multiplayer.connection_failed.connect(func():
			push_error("No se pudo conectar al host")
			get_tree().quit(2))
		multiplayer.server_disconnected.connect(func():
			_stop_local_session("server_disconnected"))
	ready_for_input = role != "client"
	_initialized_world = ready_for_input
	_log("boot", {"mode": mode, "slow": slow, "engine": Engine.get_version_info().string,
		"one_way_ms": _one_way_ms, "jitter_ms": _jitter_ms, "loss": _loss})
	print("OBJECT_PROTO_BOOT role=%s mode=%s port=%d" % [role, mode, port])

func _exit_tree() -> void:
	if trace_file != null:
		trace_file.flush()
		trace_file.close()
	if network != null:
		network.close()
	Engine.physics_ticks_per_second = RATE
	Engine.time_scale = 1.0

func _build_world() -> void:
	_static_box(Vector3(20, 0.2, 20), Vector3(0, -0.1, 0), Color(0.3, 0.34, 0.4))
	_static_box(Vector3(4, 3, 0.02), Vector3(0, 1.5, -3), Color(0.4, 0.5, 0.65))
	for uid in [1, 2]:
		var body = PhysicalBody.new()
		body.name = "Body%d" % uid
		body.position = Vector3(-0.5 if uid == 1 else 0.5, 0.02, 0)
		add_child(body)
		body.model.top_level = true
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.85, 0.25, 0.12) if uid == 1 else Color(0.2, 0.7, 0.4)
		body.model.material_override = material
		var auth = Authority.new()
		auth.state.uid = uid
		auth.state.pose = body.global_transform
		objects[uid] = {"body": body, "authority": auth, "view": Presentation.new(),
			"prediction": Prediction.new(), "state": auth.state.copy(),
			"predicted_state": auth.state.copy(),
			"goals": {}, "last_goal": -1, "hand_since_tick": 0, "last_snapshot": -1, "pending": 0}
		body.set_simulated(role != "client")
		_place_model(uid, body.global_transform)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 3)
	add_child(camera)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	add_child(light)
	var ambient := WorldEnvironment.new()
	ambient.environment = Environment.new()
	ambient.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambient.environment.ambient_light_color = Color.WHITE
	ambient.environment.ambient_light_energy = 0.6
	add_child(ambient)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(14, 12)
	canvas.add_child(label)

func _static_box(size: Vector3, position_at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = position_at
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	body.add_child(visual)
	add_child(body)

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _duration_ms > 0 and now - _started_usec >= _duration_ms * 1000:
		_log("duration_end", {})
		get_tree().quit()
		return
	if not _session_lost: _flush_wire(now)
	if role == "client" and not _session_lost and multiplayer.get_peers().has(1) and now >= _next_ping_usec:
		_last_ping_usec = now
		_next_ping_usec = now + 500_000
		_send(1, "_ping", [now], true)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_CTRL)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		camera.position += camera.global_basis * direction.limit_length(1.0) * delta * 3.0
	if local_uid != 0 and camera_drives_goal:
		target = Transform3D(_goal_rotation, camera.global_position - camera.global_basis.z * _hold_distance)
	if label != null:
		label.text = "%s | %s | tick %d | RTT %.0f ms | %d Hz\nClic derecho: agarrar/soltar · izquierdo: lanzar · rueda: distancia\nF1: capturar mouse · WASD/espacio/Ctrl: mover · central+mouse: girar\nPrototipo experimental: sin inventario ni validación del personaje" % [role, mode, tick, rtt_ms, rate_hz]
	for uid: int in objects:
		_present(uid)

func _physics_process(delta: float) -> void:
	if role == "client" and network != null \
		and network.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if ready_for_input: _stop_local_session("connection_closed")
		return
	# Leer el resultado ANTES de consumir eventos y preparar el paso siguiente.
	for uid: int in objects:
		_capture(uid, delta)
	_drain_inbound()
	if not ready_for_input:
		return
	tick += 1
	if role == "client":
		var desired := estimated_server_tick() + ceilf(rtt_ms * RATE / 2000.0) + 2.0
		rate_hz = clampi(roundi(RATE + (desired - tick) * 2.0), 57, 72)
		Engine.physics_ticks_per_second = rate_hz
		Engine.time_scale = float(rate_hz) / RATE * slow
	while not _local_commands.is_empty():
		_local_command(_local_commands.pop_front())
	if role == "client": _sync_proxies()
	for uid: int in objects:
		var o: Dictionary = objects[uid]
		if role != "client":
			_commit(uid)
			if o.authority.state.phase == State.Phase.HELD:
				var frame: Dictionary = _hand_timeline.consume(o.authority.state.owner, uid,
					o.authority.state.epoch, o.authority.state.session, tick,
					maxi(o.last_goal, int(o.hand_since_tick) - 1))
				if not frame.is_empty():
					o.body.goal = frame.target
					o.last_goal = frame.tick
				o.goals = _hand_timeline.pending_for(o.authority.state.owner, uid,
					o.authority.state.epoch, o.authority.state.session)
			else:
				o.goals = {}
		if uid == local_uid:
			o.body.goal = target
			o.last_goal = tick
			if role == "client":
				_hand_history.push_front({"uid": uid, "epoch": o.state.epoch,
					"session": local_session, "tick": tick, "target": target})
				while _hand_history.size() > HandInput.REDUNDANCY: _hand_history.pop_back()
		if not o.body.freeze:
			o.body.prepare(tick, DT * slow)
			if o.body.held:
				_log("controller", {"uid": uid, "input_tick": o.last_goal,
					"step_tick": tick, "fallback": o.last_goal != tick,
					"source": "hand_or_local" if o.last_goal >= 0 else "grab_command",
					"owner": o.authority.state.owner if role != "client" else _local_peer_id,
					"target": [o.body.goal.origin.x, o.body.goal.origin.y, o.body.goal.origin.z]})
	if role == "client" and not _hand_history.is_empty() \
		and tick - int(_hand_history.front().tick) <= HandInput.REDUNDANCY:
		# Repetir la cola durante seis pasos después de soltar evita que el
		# último input dependa de un único datagrama. Cada registro sigue
		# nombrando el tick y la sesión originales.
		var packet := HandInput.encode(_hand_history)
		if not packet.is_empty(): _send(1, "_hand_inputs", [packet], false)
		else: _log("hand_input_encode_failed", {"step_tick": tick, "uid": local_uid,
			"session": local_session, "frames": _hand_history.size()})

func _capture(uid: int, physics_delta: float) -> void:
	var o: Dictionary = objects[uid]
	if o.body.freeze or o.body.prepared_tick < 0 or o.last_snapshot == o.body.prepared_tick:
		return
	var sample = o.body.capture(o.authority.state if role != "client" else o.predicted_state)
	o.last_snapshot = sample.tick
	var contacts: int = o.body.get_contact_count()
	o.prediction.observe(sample, contacts)
	if role != "client":
		o.authority.state = sample
		o.state = sample.copy()
		if sample.tick % 2 == 0:
			for peer: int in multiplayer.get_peers():
				_send(peer, "_snapshot", [sample.encode()], false)
	var details: Dictionary = sample.trace()
	details.merge({"contacts": contacts, "impulses": o.body.impulse_count,
		"engine_frame": Engine.get_physics_frames(), "physics_delta": physics_delta,
		"native_dt": o.body.native_dt, "native_frame": o.body.native_frame,
		"native_callbacks": o.body.native_callbacks, "predicted": o.prediction.active})
	_log("physics", details)

func _drain_inbound() -> void:
	while not _inbound.is_empty():
		var event: Dictionary = _inbound.pop_front()
		match event.kind:
			"hello":
				if event.fingerprint != fingerprint() or event.states.size() != objects.size():
					push_error("Prototipos incompatibles")
					get_tree().quit(2)
					return
				var seen := {}
				for bytes: PackedByteArray in event.states:
					var sample = State.decode(bytes)
					if sample == null or not objects.has(sample.uid) or seen.has(sample.uid):
						push_error("Estado inicial inválido")
						get_tree().quit(2)
						return
					seen[sample.uid] = true
					objects[sample.uid].state = sample.copy()
					objects[sample.uid].view.accept(sample)
				_initialized_world = true
				_log("world_ready", {})
			"command": _receive_command(event.peer, event.command)
			"snapshot": _receive_snapshot(event.packet)
			"result": _receive_result(event.result)
			"hand_inputs":
				for frame: Dictionary in event.frames:
					if not objects.has(frame.uid) or frame.target.origin.length() > 20.0: continue
					var status: String = _hand_timeline.accept(event.peer, frame, tick + 1)
					_log("hand_input", {"peer": event.peer, "uid": frame.uid,
						"epoch": frame.epoch, "session": frame.session,
						"input_tick": frame.tick, "status": status})
			"pong":
				if event.sent != _last_ping_usec: continue
				rtt_ms = float(Time.get_ticks_usec() - int(event.sent)) / 1000.0
				_server_tick = event.server_tick
				_server_at_usec = Time.get_ticks_usec()
				if not ready_for_input and _initialized_world:
					tick = ceili(estimated_server_tick() + rtt_ms * RATE / 2000.0) + 2
					ready_for_input = true
					_log("clock_ready", {"local_tick": tick})
			"disconnect":
				_hand_timeline.drop_peer(event.peer)
				for uid: int in objects:
					var o: Dictionary = objects[uid]
					if o.authority.release_peer(event.peer, tick + 1):
						o.last_goal = -1
						o.body.release()
						_log("auto_release", {"uid": uid, "cause": "disconnect"})

func estimated_server_tick() -> float:
	if role != "client": return tick
	return _server_tick + rtt_ms * RATE / 2000.0 + float(Time.get_ticks_usec() - _server_at_usec) * RATE / 1_000_000.0

func request_grab(uid: int, point: Vector3, desired: Transform3D) -> void:
	if not ready_for_input or local_uid != 0 or _pending_grab != 0 or not objects.has(uid) or not point.is_finite(): return
	var canonical = HandRotation.rotation_only_target(desired)
	if canonical == null:
		_log("invalid_local_target", {"operation": "grab"})
		return
	local_session = next_action
	_hand_history.clear()
	camera_drives_goal = false
	target = canonical
	_goal_rotation = canonical.basis
	_pending_grab = next_action
	_pending_grab_uid = uid
	_queue_action("grab", uid, point, Vector3.ZERO)

func request_release() -> void:
	_request_exit("release", Vector3.ZERO)

func request_throw(direction: Vector3) -> void:
	if direction.is_finite() and direction.length_squared() > 0.000001:
		_request_exit("throw", direction.normalized())

func _request_exit(op: String, direction: Vector3) -> void:
	if not ready_for_input or not _dependent_command.is_empty(): return
	var uid := local_uid if local_uid != 0 else _pending_grab_uid
	if uid == 0: return
	# Una sola intención de salida puede estar encolada por sesión.
	for command: Dictionary in _local_commands:
		if command.uid == uid and command.op != "grab": return
	_queue_action(op, uid, Vector3.ZERO, direction)

func set_goal(desired: Transform3D) -> bool:
	var canonical = HandRotation.rotation_only_target(desired)
	if canonical == null:
		_log("invalid_local_target", {"operation": "set_goal"})
		return false
	camera_drives_goal = false
	target = canonical
	_goal_rotation = canonical.basis
	return true

func rotate_goal(delta: Vector2, camera_right: Vector3) -> bool:
	if not _rotation.rotate_mouse(delta, camera_right):
		_log("invalid_local_rotation", {})
		return false
	target.basis = _rotation.basis()
	return true

func _queue_action(op: String, uid: int, point: Vector3, direction: Vector3) -> void:
	var o: Dictionary = objects[uid]
	var command := {"op": op, "uid": uid, "epoch": o.state.epoch, "session": local_session,
		"action": next_action, "tick": maxi(tick, 0), "target": target,
		"anchor": point, "direction": direction}
	next_action += 1
	_local_commands.append(command)

func _local_command(command: Dictionary) -> void:
	var o: Dictionary = objects[command.uid]
	command.tick = maxi(tick - 1, 0)
	if role == "client" and mode == "prediction":
		if command.op == "grab":
			local_uid = command.uid
			var initial = o.state.copy()
			if o.view.initialized: initial.pose = o.view.shown
			o.body.reseed(initial)
			o.body.set_simulated(true)
			o.body.begin_hold(command.anchor, command.target)
			o.prediction.begin(tick)
		else:
			o.body.release(command.direction * THROW_IMPULSE if command.op == "throw" else Vector3.ZERO)
			local_uid = 0
		if command.op == "grab": o.predicted_state = o.state.copy()
		o.predicted_state.revision += 1
		o.predicted_state.phase = State.Phase.HELD if command.op == "grab" else State.Phase.FREE
		o.predicted_state.owner = _local_peer_id if command.op == "grab" else 0
		o.predicted_state.session = command.session if command.op == "grab" else 0
		o.predicted_state.action = command.action
		o.predicted_state.applied_tick = tick
		o.pending = command.action
	_log("request", {"uid": command.uid, "action": command.action, "op": command.op,
		"requested_tick": command.tick, "direction": [command.direction.x, command.direction.y, command.direction.z]})
	if command.op != "grab" and _pending_grab != 0:
		_dependent = command.op
		_dependent_command = command.duplicate(true)
		_log("dependent", {"uid": command.uid, "action": command.action,
			"parent_action": _pending_grab, "local_applied_tick": tick,
			"direction": [command.direction.x, command.direction.y, command.direction.z]})
		# Se transmite inmediatamente. La autoridad la mantiene dependiente del
		# grab de esa sesión; no depende del viaje de regreso de la concesión.
		if role == "client": _send(1, "_command", [command], true)
		else: _receive_command(1, command, tick)
		return
	if role == "client": _send(1, "_command", [command], true)
	else: _receive_command(1, command, tick)

func _receive_command(peer: int, command: Dictionary, boundary_tick := -1) -> void:
	if not Authority.valid_command(command) or not objects.has(command.uid): return
	var o: Dictionary = objects[command.uid]
	# Adaptador mínimo: zona acotada y punto dentro de la caja. La validación
	# de ojos/rayo del personaje real se conserva al integrar, no se finge aquí.
	if command.target.origin.length() > 20.0 or command.anchor.length() > 1.0: return
	if command.op == "grab":
		for other: int in objects:
			if other != command.uid and (objects[other].authority.state.owner == peer \
				or (not objects[other].authority.pending.is_empty() \
					and objects[other].authority.pending.peer == peer \
					and objects[other].authority.pending.command.op == "grab")):
				_reply(peer, {"status": "rejected", "reason": "already_holding", "action": command.action, "uid": command.uid})
				_retire_unbound_grab(peer, command, tick + 1)
				return
	# La bandeja se procesa antes de tick += 1; el input local, después.
	# Ambos nombran el mismo límite físico, sin añadir un tick al host.
	var now := tick + 1 if boundary_tick < 0 else boundary_tick
	var result: Dictionary = o.authority.request(peer, command, now)
	if result.status not in ["pending", "invalid"]:
		if result.status in ["rejected", "stale"] and command.op == "grab":
			_retire_unbound_grab(peer, command, now)
		result["uid"] = command.uid
		_reply(peer, result)

func _retire_unbound_grab(peer: int, command: Dictionary, now: int) -> void:
	var auth = objects[command.uid].authority
	var active: bool = auth.state.owner == peer and auth.state.session == command.session \
		and auth.state.epoch == command.epoch and auth.state.phase == State.Phase.HELD
	var waiting: bool = not auth.pending.is_empty() and auth.pending.peer == peer \
		and auth.pending.command.op == "grab" and auth.pending.command.session == command.session \
		and auth.pending.command.epoch == command.epoch
	if not active and not waiting:
		_hand_timeline.retire(peer, command.uid, command.epoch, command.session, now)

func _commit(uid: int) -> void:
	var o: Dictionary = objects[uid]
	# GRAB y su salida pueden pertenecer al mismo límite físico. Mantener el
	# orden de acciones sin inventar entre ellas un paso que el cliente no dio.
	for _attempt in 2:
		var job: Dictionary = o.authority.commit(tick)
		if job.is_empty(): return
		_apply_commit(uid, job)

func _apply_commit(uid: int, job: Dictionary) -> void:
	var o: Dictionary = objects[uid]
	var command: Dictionary = job.command
	if command.op == "grab":
		o.body.begin_hold(command.anchor, command.target)
		o.hand_since_tick = int(command.tick) + 1
		# El objetivo del GRAB es el respaldo inicial. No marcar como
		# consumido su tick: un input de ese mismo paso puede traer un
		# objetivo más reciente y debe poder reemplazarlo antes de Jolt.
		o.last_goal = -1
		if job.peer == 1:
			local_uid = uid
	else:
		_hand_timeline.retire(job.peer, uid, command.epoch, command.session, tick)
		o.last_goal = -1
		o.body.release(command.direction * THROW_IMPULSE if command.op == "throw" else Vector3.ZERO)
		if job.peer == 1: local_uid = 0
	var initial = o.body.capture(o.authority.state)
	initial.tick = maxi(tick - 1, 0)
	o.authority.state = initial
	o.state = initial.copy()
	var result: Dictionary = o.authority.remember_commit(job, initial.encode())
	result["uid"] = uid
	_log("applied", {"uid": uid, "action": command.action, "op": command.op,
		"requested_tick": command.tick, "applied_tick": tick, "late": job.late,
		"initial": initial.trace(), "impulses": o.body.impulse_count})
	_reply(job.peer, result)

func _reply(peer: int, result: Dictionary) -> void:
	if peer == 1: _receive_result(result)
	else: _send(peer, "_result", [result], true)

func _receive_result(result: Dictionary) -> void:
	if not Authority.valid_response(result):
		_log("discarded_result", {"cause": "invalid_response"})
		return
	var initial = null
	if result.status == "accepted":
		initial = State.decode(result.state)
		if initial == null or initial.uid != result.uid or initial.action != result.action:
			_log("discarded_result", {"cause": "invalid_initial_state", "action": result.action})
			return
	_log("result", {"uid": result.uid, "action": result.action, "status": result.status,
		"reason": result.get("reason", ""), "initial": initial.trace() if initial != null else {}})
	var uid: int = result.uid
	if not objects.has(uid): return
	var o: Dictionary = objects[uid]
	if result.status != "accepted":
		if result.action == _pending_grab:
			if not _dependent_command.is_empty():
				_log("dependent_cancelled", {"action": _dependent_command.action, "parent_action": _pending_grab})
			_pending_grab = 0
			_pending_grab_uid = 0
			_dependent = ""
			_dependent_command = {}
			local_uid = 0
			o.prediction.stop()
			o.body.set_simulated(role != "client")
			o.predicted_state = o.state.copy()
			o.pending = 0
		return
	var sample = initial
	_accept_authorized(o, sample)
	if result.action == _pending_grab:
		_pending_grab = 0
		_pending_grab_uid = 0
		if _dependent_command.is_empty():
			local_uid = uid
			if o.prediction.active:
				o.predicted_state.revision = sample.revision
		else:
			var deferred := _dependent_command
			_dependent_command = {}
			_dependent = ""
			local_uid = 0
			if o.prediction.active: o.predicted_state.revision = sample.revision + 1
			_log("dependent_confirmed", {"uid": uid, "action": deferred.action, "parent_action": result.action,
				"requested_tick": deferred.tick, "direction": [deferred.direction.x, deferred.direction.y, deferred.direction.z]})
			# Ya fue transmitida: no renumerar ni volver a lanzar al confirmar.
	elif o.prediction.active and result.action == o.predicted_state.action:
		o.predicted_state.revision = sample.revision
	if o.pending == result.action: o.pending = 0
	if sample.phase == State.Phase.FREE and uid == local_uid:
		local_uid = 0
	# No volver a ejecutar aquí el impulso predicho.

func _accept_authorized(o: Dictionary, sample) -> bool:
	var previous = o.state
	if sample.epoch < previous.epoch or (sample.epoch == previous.epoch and sample.revision < previous.revision):
		return false
	if sample.epoch == previous.epoch and sample.revision == previous.revision and sample.tick < previous.tick:
		return false
	o.state = sample.copy()
	o.view.accept(sample)
	return true

func _sync_proxies() -> void:
	for uid: int in objects:
		var o: Dictionary = objects[uid]
		if o.prediction.active: continue
		var sample = o.view.at(estimated_server_tick() - BUFFER_TICKS)
		var active := false
		if sample != null:
			for other: int in objects:
				if other != uid and objects[other].prediction.active \
					and objects[other].body.global_position.distance_to(sample.pose.origin) < 3.0:
					active = true
					break
		o.body.set_proxy(active, sample.pose if sample != null else o.body.global_transform)
		_log("proxy", {"uid": uid, "active": active,
			"source_tick": sample.tick if sample != null else -1,
			"render_tick": estimated_server_tick() - BUFFER_TICKS,
			"p": [o.body.global_position.x, o.body.global_position.y, o.body.global_position.z]})

func _receive_snapshot(packet: PackedByteArray) -> void:
	var sample = State.decode(packet)
	if sample == null or not objects.has(sample.uid):
		_log("discarded", {"cause": "invalid"})
		return
	var o: Dictionary = objects[sample.uid]
	if not _accept_authorized(o, sample):
		_log("discarded", {"uid": sample.uid, "source_tick": sample.tick,
			"revision": sample.revision, "cause": "old_tick_or_transition"})
		return
	_log("received", sample.trace())
	if o.prediction.active:
		var correction: Dictionary = o.prediction.reconcile(sample, o.body, tick + 1)
		correction["uid"] = sample.uid
		correction["source_tick"] = sample.tick
		_log("reconcile", correction)
		var remote_tick := estimated_server_tick() - BUFFER_TICKS
		var buffered = o.view.at(remote_tick)
		if o.pending == 0 and sample.phase == State.Phase.FREE and sample.sleeping \
			and o.view.can_handoff(buffered, o.body.sleeping, remote_tick):
			var moved: float = o.body.global_position.distance_to(buffered.pose.origin)
			var angle: float = o.body.global_basis.get_rotation_quaternion().angle_to(buffered.pose.basis.get_rotation_quaternion())
			if moved > 0.002 or angle > deg_to_rad(0.3):
				_log("handoff_blocked", {"uid": sample.uid, "source_tick": buffered.tick,
					"distance": moved, "angle": angle, "cause": "divergent_rest"})
				return
			# No reseed ni blend para esconder divergencias. Devolver únicamente
			# estados que ya coinciden dentro del criterio registrado por Claude.
			o.body.set_simulated(false)
			o.prediction.stop()
			_log("handoff", {"uid": sample.uid, "source_tick": buffered.tick, "distance": moved})
		else:
			_log("handoff_wait", {"uid": sample.uid, "pending_action": o.pending,
				"local_sleep": o.body.sleeping, "remote_sleep": sample.sleeping,
				"source_tick": buffered.tick if buffered != null else -1, "render_tick": remote_tick})

func _present(uid: int) -> void:
	var o: Dictionary = objects[uid]
	var pose: Transform3D
	if role != "client" or o.prediction.active:
		pose = o.view.predicted(o.body.global_transform, o.last_snapshot)
	else:
		var sample = o.view.remote(estimated_server_tick() - BUFFER_TICKS)
		if sample == null: return
		pose = sample.pose
	_place_model(uid, pose)
	var q := pose.basis.get_rotation_quaternion()
	_log("visual", {"uid": uid, "shown_tick": o.view.shown_tick,
		"p": [pose.origin.x, pose.origin.y, pose.origin.z], "q": [q.x, q.y, q.z, q.w],
		"physical_source_tick": o.last_snapshot if o.prediction.active else -1,
		"predicted": o.prediction.active})

func _place_model(uid: int, pose: Transform3D) -> void:
	var body = objects[uid].body
	body.model.global_transform = pose * Transform3D(Basis.IDENTITY, Vector3(0, body.size.y * 0.5, 0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) and local_uid != 0:
			rotate_goal(event.relative, camera.global_basis.x)
		else:
			camera.rotate_y(-event.relative.x * 0.003)
			camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.003, -1.4, 1.4)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if local_uid != 0 or _pending_grab != 0: request_release()
			else: _pick()
		elif event.button_index == MOUSE_BUTTON_LEFT: request_throw(-camera.global_basis.z)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: _hold_distance = minf(_hold_distance + 0.1, 2.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _hold_distance = maxf(_hold_distance - 0.1, 0.6)

func _pick() -> void:
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	# La selección de la réplica usa su modelo mostrado, no su cuerpo congelado.
	var closest := 4.0
	var selected := 0
	var point := Vector3.ZERO
	for uid: int in objects:
		var body = objects[uid].body
		var transform: Transform3D = body.model.global_transform
		var inverse := transform.affine_inverse()
		var box := AABB(-body.size * 0.5, body.size)
		var hit = box.intersects_ray(inverse * origin, inverse.basis * direction)
		if hit == null: continue
		var global_hit: Vector3 = transform * hit
		var distance := origin.distance_to(global_hit)
		if distance < closest:
			closest = distance
			selected = uid
			point = hit + Vector3(0, body.size.y * 0.5, 0)
	if selected != 0:
		_hold_distance = clampf(closest, 0.6, 2.5)
		request_grab(selected, point, Transform3D(objects[selected].view.shown.basis, origin + direction * _hold_distance))
		camera_drives_goal = true

func _connected(peer: int) -> void:
	if role == "client": _local_peer_id = multiplayer.get_unique_id()
	_log("connected", {"peer": peer})
	if role == "host":
		var states: Array[PackedByteArray] = []
		for uid: int in objects:
			var sample = objects[uid].body.capture(objects[uid].authority.state)
			states.append(sample.encode())
		_send(peer, "_hello", [fingerprint(), states], true)

func fingerprint() -> String:
	return _configuration_signature

func _build_fingerprint() -> String:
	var bodies: Array = []
	for uid: int in objects:
		bodies.append(objects[uid].body.configuration())
	var settings := {}
	for key in ["physics/3d/physics_engine", "physics/3d/default_gravity",
		"physics/3d/default_gravity_vector", "physics/3d/default_linear_damp",
		"physics/3d/default_angular_damp", "physics/jolt_physics_3d/simulation/penetration_slop"]:
		settings[key] = ProjectSettings.get_setting(key)
	var scripts := {}
	for path in ["res://main.gd", "res://runtime/body.gd", "res://runtime/authority.gd",
		"res://runtime/state.gd", "res://runtime/prediction.gd", "res://runtime/presentation.gd",
		"res://runtime/hand_input.gd", "res://runtime/hand_timeline.gd", "res://runtime/hand_rotation.gd"]:
		scripts[path] = FileAccess.get_file_as_string(path).sha256_text()
	return JSON.stringify({"version": State.VERSION, "slow": slow, "rate": RATE,
		"engine": Engine.get_version_info().string, "bodies": bodies,
		"settings": settings, "scripts": scripts}).sha256_text()

func _disconnected(peer: int) -> void:
	if role == "host": _inbound.append({"kind": "disconnect", "peer": peer})

func _stop_local_session(cause: String) -> void:
	if _session_lost: return
	_session_lost = true
	ready_for_input = false
	local_uid = 0
	_pending_grab = 0
	_pending_grab_uid = 0
	_dependent = ""
	_dependent_command.clear()
	_local_commands.clear()
	_hand_history.clear()
	_wire.clear()
	for uid: int in objects:
		objects[uid].prediction.stop()
		objects[uid].body.set_simulated(false)
	_log("session_closed", {"cause": cause})

@rpc("any_peer", "call_remote", "reliable", 0)
func _command(command: Dictionary) -> void:
	if role == "host" and Authority.valid_command(command):
		_inbound.append({"kind": "command", "peer": multiplayer.get_remote_sender_id(), "command": command})

@rpc("authority", "call_remote", "reliable", 0)
func _hello(signature: String, states: Array[PackedByteArray]) -> void:
	if role == "client": _inbound.append({"kind": "hello", "fingerprint": signature, "states": states})

@rpc("authority", "call_remote", "reliable", 0)
func _result(result: Dictionary) -> void:
	if role == "client": _inbound.append({"kind": "result", "result": result})

@rpc("authority", "call_remote", "unreliable", 2)
func _snapshot(packet: PackedByteArray) -> void:
	if role == "client" and packet.size() == State.BYTES:
		_inbound.append({"kind": "snapshot", "packet": packet})

@rpc("any_peer", "call_remote", "unreliable", 1)
func _hand_inputs(packet: PackedByteArray) -> void:
	if role != "host": return
	var frames: Array = HandInput.decode(packet)
	if frames.is_empty():
		_log("discarded", {"cause": "invalid_hand_inputs"})
		return
	_inbound.append({"kind": "hand_inputs", "peer": multiplayer.get_remote_sender_id(), "frames": frames})

@rpc("any_peer", "call_remote", "unreliable", 1)
func _ping(sent_usec: int) -> void:
	if role == "host": _send(multiplayer.get_remote_sender_id(), "_pong", [sent_usec, tick], false)

@rpc("authority", "call_remote", "unreliable", 1)
func _pong(sent_usec: int, server_tick: int) -> void:
	if role == "client": _inbound.append({"kind": "pong", "sent": sent_usec, "server_tick": server_tick})

func _send(peer: int, method: String, arguments: Array, reliable: bool) -> void:
	if not reliable and _random.randf() < _loss: return
	var delay := maxi(0, _one_way_ms + _random.randi_range(-_jitter_ms, _jitter_ms)) * 1000
	var due := Time.get_ticks_usec() + delay
	if reliable:
		due = maxi(due, int(_reliable_due.get(peer, 0)))
		_reliable_due[peer] = due
	_wire.append({"peer": peer, "method": method, "args": arguments.duplicate(true), "due": due})

func _flush_wire(now: int) -> void:
	var waiting: Array[Dictionary] = []
	for message in _wire:
		if message.due > now:
			waiting.append(message)
		elif multiplayer.get_peers().has(message.peer):
			var arguments: Array = [message.peer, message.method]
			arguments.append_array(message.args)
			callv("rpc_id", arguments)
	_wire = waiting

func _log(kind: String, fields: Dictionary) -> void:
	if trace_file == null: return
	var entry := {"schema": 1, "kind": kind, "role": role, "mode": mode,
		"usec": Time.get_ticks_usec() - _started_usec, "local_tick": tick,
		"rtt_ms": rtt_ms, "rate_hz": rate_hz, "slow": slow}
	entry.merge(fields, true)
	trace_file.store_line(JSON.stringify(entry))
	if kind not in ["physics", "visual", "received"]: trace_file.flush()
