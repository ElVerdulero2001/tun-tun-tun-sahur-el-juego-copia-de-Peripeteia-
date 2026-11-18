extends Node3D
## One guest controls the actor and the box. Host observes and owns both simulations.
const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const History = preload("res://prototypes/objetos_adaptador/history_bridge.gd")
const Channel = preload("res://prototypes/objetos_adaptador/authority_channel.gd")
const Bridge = preload("res://prototypes/objetos_adaptador/scene_network_bridge.gd")
const Journal = preload("res://prototypes/objetos_adaptador/host_action_journal.gd")
const ActorScene = preload("res://scenes/actor/actor.tscn")
const BOX_ID := 2
const BOX_SIZE := Vector3(0.52, 0.45, 0.58)
const BOX_START := Vector3(0, 0.24, -1.15)
const SPAWN := Vector3(0, 0.02, 0.95)
const REACH := 2.5
const MAX_ACTION_LEAD := 15
const THROW_IMPULSE := 5.0
const DEFAULT_PORT := 29471
const HOLD_VISUAL_LEAD := 0.035
const HOLD_VISUAL_MAX_OFFSET := 0.18
const HOLD_VISUAL_MAX_ANGLE := PI / 18.0
const HOLD_VISUAL_IDLE_OFFSET := 0.008
const HOLD_VISUAL_IDLE_ANGLE := PI / 300.0
const ROOM := [
	[1, Vector3(12, 0.25, 12), Vector3(0, -0.125, 0)],
	[3, Vector3(12, 3, 0.25), Vector3(0, 1.5, -6)],
	[4, Vector3(12, 3, 0.25), Vector3(0, 1.5, 6)],
	[5, Vector3(0.25, 3, 12), Vector3(-6, 1.5, 0)],
	[6, Vector3(0.25, 3, 12), Vector3(6, 1.5, 0)],
	[7, Vector3(2.1, 0.5, 0.8), Vector3(2.5, 0.25, -2.75)],
]

var camera: Camera3D
var box_visual: MeshInstance3D
var menu: PanelContainer
var address: LineEdit
var port_input: SpinBox
var status: Label
var reticle: Label
var host_button: Button
var join_button: Button
var session := ""
var ended := false
var peer_id := 0
var connection := 0
var clock: SimClock
var sync: NetSync
var actor: ActorBody
var tuning: ActorTuning
var adapter
var channel
var history
var bridge
var journal
var prediction := ClientPrediction.new()
var current_input: ActorInput
var yaw := 0.0
var pitch := -0.60
var hold_distance := 1.8
var box_rotation := Quaternion.IDENTITY
var jump_presses := 0
var serial := 0
var revision := 0
var pending_id := 0
var applied_tick := -1
var pending_since := 0
var ready_to_play := false
var connect_deadline := 0
var transport_connected := false
var join_target := ""
var note := ""
var shown_pose_ready := false
var box_view_query := PhysicsShapeQueryParameters3D.new()

func _ready() -> void:
	_build_room()
	_build_menu()
	var box_shape := BoxShape3D.new()
	box_shape.size = BOX_SIZE
	box_view_query.shape = box_shape
	box_view_query.collision_mask = 1
	box_view_query.margin = 0.005
	if not ClassDB.class_exists("SahurObjectWorld"):
		status.text = "Falta la extensión física. Abrí la sala con el lanzador de la entrega."

func _build_room() -> void:
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(4.1, 3.1, 4.6)
	camera.look_at(Vector3(0, 0.35, -0.7))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.shadow_enabled = true
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#273841")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#a7c7d3")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	for part in ROOM:
		var size: Vector3 = part[1]
		var part_position: Vector3 = part[2]
		var body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.position = part_position
		body.add_child(collider)
		add_child(body)
		body.add_child(_mesh(size, Color("#4d6470") if part[0] == 1 else Color("#324651")))
	# Floor markings make sliding and the position at release easier to judge.
	for i in range(-5, 6):
		var line := _mesh(Vector3(0.018, 0.002, 11.5), Color("#263943"))
		line.position = Vector3(i, 0.002, 0)
		add_child(line)
		var cross := _mesh(Vector3(11.5, 0.002, 0.018), Color("#263943"))
		cross.position = Vector3(0, 0.003, i)
		add_child(cross)
	box_visual = _mesh(BOX_SIZE, Color("#dc8c42"))
	box_visual.position = BOX_START
	add_child(box_visual)
	var stripe := _mesh(Vector3(0.11, 0.006, BOX_SIZE.z * 0.86), Color("#493321"))
	stripe.position = Vector3(-0.11, BOX_SIZE.y * 0.5, 0)
	box_visual.add_child(stripe)
	var nose := _mesh(Vector3(BOX_SIZE.x * 0.84, 0.085, 0.005), Color("#493321"))
	nose.position = Vector3(0, 0.07, BOX_SIZE.z * 0.5)
	box_visual.add_child(nose)

func _mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var model := BoxMesh.new()
	model.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	model.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = model
	return instance

func _build_menu() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	status = Label.new()
	status.position = Vector2(16, 14)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 5)
	ui.add_child(status)
	reticle = Label.new()
	reticle.text = "+"
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.offset_left = -10
	reticle.offset_right = 10
	reticle.offset_top = -10
	reticle.offset_bottom = 10
	reticle.hide()
	menu = PanelContainer.new()
	ui.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -190
	menu.offset_top = -88
	menu.offset_right = 190
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	menu.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "Sala de objetos"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var caption := Label.new()
	caption.text = "El anfitrión observa. El invitado mueve la caja."
	column.add_child(caption)
	var row := HBoxContainer.new()
	column.add_child(row)
	address = LineEdit.new()
	address.placeholder_text = "IP del anfitrión"
	address.tooltip_text = "Usá 127.0.0.1 solo para dos ventanas en la misma PC."
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(address)
	port_input = SpinBox.new()
	port_input.min_value = 1024
	port_input.max_value = 65535
	port_input.value = DEFAULT_PORT
	row.add_child(port_input)
	host_button = Button.new()
	host_button.text = "Alojar"
	host_button.pressed.connect(func(): start_session("host", "", int(port_input.value)))
	row.add_child(host_button)
	join_button = Button.new()
	join_button.text = "Conectar"
	join_button.pressed.connect(func(): start_session("guest", address.text.strip_edges(), int(port_input.value)))
	row.add_child(join_button)
	var help := Label.new()
	help.text = "WASD · ratón · clic derecho para agarrar o soltar\nClic izquierdo para lanzar · rueda para acercar o alejar\nMantené el botón del medio para girar la caja"
	column.add_child(help)
	var restart := Button.new()
	restart.text = "Volver al inicio"
	restart.pressed.connect(_restart)
	column.add_child(restart)

func start_session(role: String, ip: String, port: int) -> bool:
	if not session.is_empty() or not ClassDB.class_exists("SahurObjectWorld"):
		return false
	if role == "guest" and ip.is_empty():
		status.text = "Ingresá la IP que muestra el anfitrión. En esta misma PC usá 127.0.0.1."
		return false
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 1, 2) if role == "host" else peer.create_client(ip, port, 2)
	if error != OK:
		status.text = "No se pudo abrir UDP %d. %s" % [port, error_string(error)]
		return false
	session = role
	sync = NetSync.new()
	sync.name = "ActorSync"
	add_child(sync)
	channel = Channel.new()
	channel.name = "ObjectAuthority"
	add_child(channel)
	if session == "host":
		multiplayer.peer_connected.connect(_prepare_host)
		multiplayer.peer_disconnected.connect(func(_id): _end_session("El invitado salió."))
		status.text = _hosting_status(port)
		print(status.text)
	else:
		join_target = "%s:%d" % [ip, port]
		multiplayer.connected_to_server.connect(_on_transport_connected)
		multiplayer.connection_failed.connect(func(): _end_session(_no_host_reply()))
		multiplayer.server_disconnected.connect(func(): _end_session("Se perdió al anfitrión."))
		status.text = "Conectando a %s por UDP…" % join_target
		print(status.text)
		connect_deadline = Time.get_ticks_msec() + 10000
	multiplayer.multiplayer_peer = peer
	host_button.disabled = true
	join_button.disabled = true
	menu.hide()
	return true

func _hosting_status(port: int) -> String:
	var ipv4 := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.is_valid_ip_address() and not ip.contains(":") and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			ipv4.append(ip)
	ipv4.sort()
	var message := "Anfitrión · UDP %d · Esperando al invitado" % port
	if not ipv4.is_empty():
		message += "\nDesde otra PC: " + "  /  ".join(ipv4)
	return message + "\nDesde esta PC: 127.0.0.1"

func _on_transport_connected() -> void:
	transport_connected = true
	connect_deadline = Time.get_ticks_msec() + 5000
	status.text = "Conectado a %s. Preparando la escena…" % join_target
	print(status.text)

func _no_host_reply() -> String:
	return "Sin respuesta de %s por UDP. Revisá la IP del anfitrión, el puerto y el firewall." % join_target

func _prepare_host(id: int) -> void:
	if ended or clock != null:
		return
	transport_connected = true
	status.text = "Invitado conectado. Preparando la escena…"
	print(status.text)
	connection = randi_range(1, 0x7fffffff)
	if _setup(id):
		connect_deadline = Time.get_ticks_msec() + 5000
		_prepare_guest.rpc_id(id, connection)

@rpc("authority", "call_remote", "reliable", 0)
func _prepare_guest(epoch: int) -> void:
	if session != "guest" or clock != null or epoch < 1:
		return
	connection = epoch
	if _setup(multiplayer.get_unique_id()):
		_guest_ready.rpc_id(1)

func _setup(id: int) -> bool:
	peer_id = id
	tuning = ActorTuning.new()
	add_child(tuning)
	var actors := Node3D.new()
	add_child(actors)
	actor = ActorScene.instantiate()
	actor.owner_peer_id = id
	actor.state.position = SPAWN
	actors.add_child(actor)
	actor.position = SPAWN
	clock = SimClock.new()
	clock.name = "Clock"
	clock.paused = true
	clock.actors_root = actors
	clock.tuning = tuning
	clock.input_provider = _provide_input
	add_child(clock)
	sync.clock = clock
	adapter = Adapter.new()
	add_child(adapter)
	if not adapter.start(clock, actor, tuning, _make_world, BOX_ID, 1, 1, connection, 1):
		_end_session("No se pudo iniciar el mundo de objetos.")
		return false
	if session == "guest":
		adapter.recovery_required.connect(func(reason: String):
			print("Sala de objetos: recuperación en tick %d (%s)" % [clock.tick, reason]))
	if not channel.start(adapter.authority_scope(), id if session == "host" else 1):
		_end_session("No se pudo abrir el canal de objetos: %s." % channel.last_error)
		return false
	channel.closed.connect(func(): _end_session("Canal cerrado: %s" % channel.last_error))
	if session == "host":
		journal = Journal.new()
		add_child(journal)
		if not journal.start(adapter, id, _authorize):
			_end_session("No se pudo iniciar el registro del anfitrión.")
			return false
		channel.action_requested.connect(_request_host_action)
		journal.action_resolved.connect(_send_result)
	else:
		actor.get_node("Visual").hide()
		history = History.new()
		add_child(history)
		if not history.start(adapter, prediction, _replay_actor):
			_end_session("No se pudo iniciar la predicción.")
			return false
		bridge = Bridge.new()
		add_child(bridge)
		if not bridge.start(history, sync, channel, func(_id, _tick, _state): pass, func(_id, _tick, _pos, _vel): pass):
			_end_session("No se pudo iniciar la sincronización.")
			return false
		clock.tick_started.connect(bridge.before_actor_tick)
		# This room starts both clocks at zero. Enable rate correction without
		# a second initial jump; subsequent corrections use SimClock normally.
		clock.client_sync = true
		clock.synced = true
		clock.hard_resynced.connect(prediction.clear)
	clock.tick_finished.connect(_after_tick)
	return true

@rpc("any_peer", "call_remote", "reliable", 0)
func _guest_ready() -> void:
	if session != "host" or clock == null or not clock.paused or multiplayer.get_remote_sender_id() != peer_id:
		return
	_ready_to_run.rpc_id(peer_id)
	connect_deadline = 0
	clock.paused = false

@rpc("authority", "call_remote", "reliable", 0)
func _ready_to_run() -> void:
	if session != "guest" or clock == null:
		return
	connect_deadline = 0
	clock.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	reticle.show()

func _make_world():
	var world = ClassDB.instantiate("SahurObjectWorld")
	for part in ROOM:
		if not world.add_box(part[0], 1, part[1], 0.0, Transform3D(Basis.IDENTITY, part[2])):
			return null
	if not world.add_box(BOX_ID, 1, BOX_SIZE, 2.0, Transform3D(Basis.IDENTITY, BOX_START)):
		return null
	return world if world.seal_topology(1) else null

func _provide_input(_who: ActorBody, tick: int) -> ActorInput:
	if session == "host":
		current_input = sync.input_for(peer_id, tick)
		if current_input == null:
			current_input = ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
		if current_input.hold_session() != 1:
			current_input.hold = ActorInput.pack_hold(1, -0.60, 1.8, Quaternion.IDENTITY)
		journal.before_capture(tick)
		if not adapter.capture(current_input):
			_end_session.call_deferred(adapter.last_error)
	else:
		current_input = _guest_input(tick)
		history.capture_input(current_input)
	return current_input

func _guest_input(tick: int) -> ActorInput:
	var axes := Vector2.ZERO
	var buttons := 0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		axes.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		axes.y = float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		if Input.is_physical_key_pressed(KEY_CTRL): buttons |= ActorInput.BUTTON_CROUCH
		if Input.is_physical_key_pressed(KEY_SHIFT): buttons |= ActorInput.BUTTON_RUN
		if Input.is_physical_key_pressed(KEY_SPACE): buttons |= ActorInput.BUTTON_JUMP
	var sampled := ActorInput.make(tick, axes, yaw, buttons, jump_presses)
	sampled.hold = ActorInput.pack_hold(1, pitch, hold_distance, box_rotation)
	return sampled

func _after_tick(tick: int) -> void:
	if session == "host":
		sync.send_snapshot(tick, [actor], [])
		if tick % 4 == 0 or applied_tick == tick:
			revision += 1
			var packet: Dictionary = adapter.authority_scope()
			packet.merge({"version": 1, "tick": tick, "revision": revision,
				"snapshot": adapter.world.snapshot_trusted(), "acks": []})
			if not channel.publish(packet):
				_end_session.call_deferred(channel.last_error)
	else:
		prediction.record(tick, current_input, actor.state)
		sync.send_ticks(prediction.recent(NetSync.INPUT_REDUNDANCY), clock.rtt_ms)
		if clock.tick != history.stats().actor_tick:
			return
		ready_to_play = adapter.last_authority().tick >= 0
		if pending_id != 0 and applied_tick >= 0 and adapter.last_authority().tick >= applied_tick:
			pending_id = 0
			applied_tick = -1

func _replay_actor(input: ActorInput) -> void:
	ActorMotor.step(actor, actor.state, input, tuning, SimClock.world_dt(input.tick))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and session != "":
		if session == "guest" and not menu.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			_restart()
		return
	if session != "guest" or clock == null or clock.paused:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventKey and event.physical_keycode == KEY_SPACE and event.pressed and not event.echo:
		jump_presses += 1
	if event is InputEventMouseMotion:
		_look(event.relative, Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE))
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT: _try_action(false)
			MOUSE_BUTTON_LEFT: _try_action(true)
			MOUSE_BUTTON_WHEEL_UP: hold_distance = minf(hold_distance + 0.15, tuning.hold_max_distance)
			MOUSE_BUTTON_WHEEL_DOWN: hold_distance = maxf(hold_distance - 0.15, tuning.hold_min_distance)

func _look(motion: Vector2, rotating: bool) -> void:
	if rotating and _sample().get("held", false):
		box_rotation = (Quaternion(Vector3.UP, -motion.x * 0.008) *
			Quaternion(Vector3.RIGHT, -motion.y * 0.008) * box_rotation).normalized()
		return
	yaw = wrapf(yaw - motion.x * 0.0025, -PI, PI)
	pitch = clampf(pitch - motion.y * 0.0025, -1.5, 1.5)

func _try_action(throwing: bool) -> bool:
	if not ready_to_play or pending_id != 0 or not adapter.ready_for_input:
		return false
	var sample := _sample()
	if sample.is_empty():
		return false
	var held: bool = sample.held
	if throwing and not held:
		return false
	var eyes := _eyes()
	var forward := Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3.FORWARD
	var anchor := Vector3.ZERO
	if not held:
		var pose: Transform3D = sample.pose
		var inverse := pose.affine_inverse()
		var local_box := AABB(-BOX_SIZE * 0.5, BOX_SIZE)
		var hit: Variant = local_box.intersects_segment(inverse * eyes, inverse * (eyes + forward * REACH))
		if hit == null or not _clear_path(eyes, pose * (hit as Vector3)):
			note = "Apuntá a la caja desde más cerca."
			return false
		anchor = hit
		hold_distance = clampf(eyes.distance_to(pose * anchor), tuning.hold_min_distance, tuning.hold_max_distance)
		box_rotation = (Basis(Vector3.UP, -yaw) * pose.basis).get_rotation_quaternion()
	serial += 1
	var tick: int = mini(clock.tick + 1, adapter.last_authority().tick + MAX_ACTION_LEAD)
	var action := {"id": serial, "tick": tick, "kind": "release" if held else "grab", "anchor": anchor,
		"impulse": forward * THROW_IMPULSE if throwing else Vector3.ZERO}
	if not channel.request_action(action):
		note = channel.last_error
		return false
	pending_id = serial
	pending_since = Time.get_ticks_msec()
	note = "Esperando al anfitrión…"
	return true

func _request_host_action(action: Dictionary) -> void:
	if action.tick > clock.tick + MAX_ACTION_LEAD:
		_room_result.rpc_id(peer_id, action.id, "rejected", -1, "El pedido se adelantó al reloj.")
		return
	var result: Dictionary = journal.request(peer_id, action)
	if result.status != "scheduled":
		_room_result.rpc_id(peer_id, action.id, result.status, result.get("applied_tick", -1), result.reason)

func _authorize(id: int, action: Dictionary, _tick: int) -> String:
	if id != peer_id:
		return "Ese jugador no tiene la caja."
	if action.kind == "release":
		if action.impulse.length() > THROW_IMPULSE + 0.001:
			return "Impulso fuera de rango."
		return ""
	var bounds := AABB(-BOX_SIZE * 0.5, BOX_SIZE).grow(0.005)
	if not bounds.has_point(action.anchor) or action.impulse != Vector3.ZERO:
		return "Punto de agarre inválido."
	var sample := _sample()
	var pose: Transform3D = sample.pose
	var point: Vector3 = pose * action.anchor
	var eyes := _eyes()
	if eyes.distance_to(point) > REACH + 0.25:
		return "La caja quedó fuera de alcance."
	if not _clear_path(eyes, point):
		return "Hay una pared entre vos y la caja."
	return ""

func _clear_path(eyes: Vector3, point: Vector3) -> bool:
	if eyes.distance_squared_to(point) < 0.0001:
		return true
	var query := PhysicsRayQueryParameters3D.create(eyes, point, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _eyes() -> Vector3:
	return InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state))

func _sample() -> Dictionary:
	return {} if adapter == null else adapter.world.sample(BOX_ID, 1)

func _send_result(result: Dictionary) -> void:
	if result.status == "applied":
		applied_tick = result.applied_tick
		note = "Caja agarrada" if result.kind == "grab" else "Caja soltada"
	if peer_id in multiplayer.get_peers():
		_room_result.rpc_id(peer_id, result.id, result.status, result.applied_tick, result.reason)

@rpc("authority", "call_remote", "reliable", 0)
func _room_result(id: int, result: String, tick: int, reason: String) -> void:
	if session != "guest" or id != pending_id:
		return
	if result == "applied":
		applied_tick = tick
		note = ""
	else:
		pending_id = 0
		applied_tick = -1
		note = "Pedido rechazado: " + reason

func _process(delta: float) -> void:
	if connect_deadline != 0 and Time.get_ticks_msec() > connect_deadline:
		if transport_connected:
			_end_session("La conexión UDP se abrió, pero la escena no terminó de iniciar. Verificá que ambas PC usen el mismo ZIP.")
		else:
			_end_session(_no_host_reply())
	if clock == null or clock.paused:
		return
	var sample := _sample()
	if sample.is_empty():
		return
	_present_box(sample, delta)
	if session == "host":
		status.text = "Anfitrión · Vista de la sala · Esc para volver\n" + note
		return
	camera.position = _eyes()
	camera.rotation = Vector3(pitch, yaw, 0)
	if pending_id != 0 and Time.get_ticks_msec() - pending_since > 2500:
		pending_id = 0
		applied_tick = -1
		note = "Se venció el pedido. Mirá el estado de la caja antes de reintentar."
	var state := "Caja en mano" if sample.held else "Caja libre"
	if not ready_to_play: state = "Esperando el primer estado de la caja…"
	if not adapter.ready_for_input: state = "Recuperando el estado de la caja…"
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: state = "Clic para retomar · Esc para volver"
	status.text = "Invitado · " + state + "\n" + note

func _present_box(sample: Dictionary, delta: float) -> void:
	var pose: Transform3D = sample.pose
	if not shown_pose_ready:
		box_visual.transform = pose
		shown_pose_ready = true
		return
	var held_locally: bool = session == "guest" and sample.held and adapter.ready_for_input
	var follow_rate := 35.0
	if held_locally:
		var lv: Vector3 = sample.lv
		var av: Vector3 = sample.av
		var offset := lv * HOLD_VISUAL_LEAD
		var spin := Quaternion.IDENTITY
		if av.length_squared() > 0.000001:
			spin = Quaternion(av.normalized(), minf(av.length() * HOLD_VISUAL_LEAD, HOLD_VISUAL_MAX_ANGLE))
		if current_input != null and not current_input.hold.is_empty():
			var eyes := _eyes()
			var tick_goal := InvHoldMotion.target_of(eyes, current_input, tuning)
			var live_goal := InvHoldMotion.target(eyes, yaw, pitch, hold_distance, box_rotation, tuning)
			offset += live_goal.origin - tick_goal.origin
			var live_turn := (live_goal.basis * tick_goal.basis.transposed()).get_rotation_quaternion()
			spin = (live_turn * spin).normalized()
		var shown := box_visual.transform
		if offset.length_squared() < HOLD_VISUAL_IDLE_OFFSET ** 2 and spin.angle_to(Quaternion.IDENTITY) < HOLD_VISUAL_IDLE_ANGLE:
			if pose.origin.distance_squared_to(shown.origin) < HOLD_VISUAL_IDLE_OFFSET ** 2 \
					and pose.basis.get_rotation_quaternion().angle_to(shown.basis.get_rotation_quaternion()) < HOLD_VISUAL_IDLE_ANGLE:
				return
		# Keep the normal draw path at walls and during recovery. Only the
		# local held box gets ahead of the last completed physics tick.
		if sample.contacts.is_empty():
			pose = _held_view_pose(pose, offset, spin)
			follow_rate = 100.0
	box_visual.transform = box_visual.transform.interpolate_with(pose, 1.0 - exp(-delta * follow_rate))

func _held_view_pose(pose: Transform3D, offset: Vector3, spin: Quaternion) -> Transform3D:
	var turn := spin.angle_to(Quaternion.IDENTITY)
	if offset.length_squared() < 0.000001 and turn < 0.001:
		return pose
	var space := get_world_3d().direct_space_state
	box_view_query.transform = pose
	box_view_query.motion = Vector3.ZERO
	if not space.intersect_shape(box_view_query, 1).is_empty():
		return pose
	var limited := offset.limit_length(HOLD_VISUAL_MAX_OFFSET)
	box_view_query.motion = limited
	if not limited.is_zero_approx():
		var fraction := space.cast_motion(box_view_query)[0]
		if fraction < 1.0:
			return pose
	if turn > HOLD_VISUAL_MAX_ANGLE:
		spin = Quaternion.IDENTITY.slerp(spin, HOLD_VISUAL_MAX_ANGLE / turn)
	var predicted := Transform3D(Basis(spin) * pose.basis, pose.origin + limited)
	box_view_query.transform = predicted
	box_view_query.motion = Vector3.ZERO
	return predicted if space.intersect_shape(box_view_query, 1).is_empty() else pose

func _end_session(message: String) -> void:
	if ended:
		return
	ended = true
	connect_deadline = 0
	ready_to_play = false
	if clock != null: clock.paused = true
	if journal != null: journal.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	reticle.hide()
	status.text = message + " Volvé al inicio para reconectar."
	print(status.text)
	menu.show()
	_close_peer.call_deferred()

func _close_peer() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

func _restart() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_close_peer()
	get_tree().reload_current_scene()
