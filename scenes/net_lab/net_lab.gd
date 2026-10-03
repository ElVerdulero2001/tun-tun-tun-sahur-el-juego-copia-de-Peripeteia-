extends Node3D

## Laboratorio del esqueleto de red.
##
## Paso 1: aplica al arrancar los ajustes de tiempo del juego en red, sin tocar
## project.godot.
## Paso 2: actor con estado explícito; en modo local se maneja con el teclado.
## Paso 3: sesión de red, un actor por jugador y reloj de ticks compartido.
## Paso 4: el cliente manda su input, el host mueve a todos y devuelve el
## estado; el cliente muestra lo que recibe, todavía sin predicción.
## Paso 5: simulador de red, para que una LAN se comporte como internet.
##
## El rol se elige con el menú. Para pruebas automáticas también se puede pasar
## por argumentos: --local, --host o --client, --address=IP, --port=N,
## --bind=IP (solo host), --autoquit=SEGUNDOS (imprime un resumen y cierra),
## --report-after=SEGUNDOS (imprime el estado de cada actor),
## --test-input=walk (camina y salta solo, sin teclado) y, para simular red,
## --sim-rtt=MS, --sim-jitter=MS, --sim-loss=PORCENTAJE y --sim-seed=N.

const DEFAULT_PORT := 7777
## Niveles del simulador de red, con las teclas 1 a 4. La demora es de ida y vuelta.
const NET_PRESETS := [
	{"name": "sin simulación", "rtt": 0.0, "jitter": 0.0, "loss": 0.0},
	{"name": "internet buena", "rtt": 40.0, "jitter": 5.0, "loss": 0.0},
	{"name": "internet normal", "rtt": 120.0, "jitter": 20.0, "loss": 1.0},
	{"name": "internet mala", "rtt": 200.0, "jitter": 40.0, "loss": 5.0},
]

enum Role { LOCAL, HOST, CLIENT }

@export var tuning: ActorTuning

var role := Role.LOCAL
var host_address := "127.0.0.1"
var port := DEFAULT_PORT
var bind_address := ""
var autoquit_seconds := 0.0
var report_seconds := 0.0
var test_input := ""
## Simulación de red pedida por argumentos; si no hay, se usa la del menú.
var sim_from_args := false
var sim_rtt_ms := 0.0
var sim_jitter_ms := 0.0
var sim_loss_percent := 0.0
var sim_seed := 1
var _sim_preset_name := "sin simulación"
## Contador de pulsaciones de salto: se suma en cada evento, no en cada tick,
## para no perder dos pulsaciones que caigan entre dos ticks.
var jump_presses := 0
var max_actors_seen := 0
var _role_from_args := false
var _started := false
var _local_actor: ActorBody
## Ticks propios desde que arrancó la sesión; el input de prueba se guía por esto.
var _local_ticks := 0
## Cliente (paso 6): predicción del propio actor.
var _prediction := ClientPrediction.new()
## Cliente: input del tick en curso, el mismo que se manda, se simula y se guarda.
var _current_input: ActorInput
## Cliente: primer tick predicho desde la última sincronización. Los márgenes de
## inputs anteriores no sirven para ajustar el adelanto.
var _prediction_start_tick := 0

@onready var _clock: SimClock = $Clock
@onready var _session: NetSession = $Session
@onready var _net_sync: NetSync = $NetSync
@onready var _link: LinkSimulator = $LinkSimulator
@onready var _sim_option: OptionButton = $Hud/Menu/Box/SimRow/SimOption
@onready var _actors: Node3D = $Actors
@onready var _camera: LabCamera = $CameraRig
@onready var _info: Label = $Hud/Info
@onready var _menu: Control = $Hud/Menu
@onready var _lan_label: Label = $Hud/Menu/Box/LanAddress
@onready var _address_field: LineEdit = $Hud/Menu/Box/JoinRow/Address


func _enter_tree() -> void:
	# Va acá y no en _ready(): el _enter_tree() del padre corre antes de que
	# entren los hijos. Si la interpolación se activa con el nivel ya cargado,
	# Godot dibuja en el origen todo lo que nunca se mueve, luz incluida.
	# Cuando el esqueleto sea el juego, estos ajustes pasan a project.godot.
	get_tree().physics_interpolation = true
	Engine.physics_ticks_per_second = SimClock.TICK_RATE
	# Godot lo recomienda para juegos en red: los ticks quedan atados al reloj real.
	Engine.physics_jitter_fix = 0.0


func _ready() -> void:
	_read_launch_args()
	if tuning == null:
		tuning = ActorTuning.new()
	_clock.actors_root = _actors
	_clock.tuning = tuning
	_clock.input_provider = _input_for
	_clock.tick_started.connect(_on_tick_started)
	_clock.tick_finished.connect(_on_tick_finished)
	_clock.hard_resynced.connect(_on_hard_resynced)
	_clock.link = _link
	_net_sync.link = _link
	multiplayer.server_disconnected.connect(_link.clear)
	for preset in NET_PRESETS:
		_sim_option.add_item(preset["name"])
	if sim_from_args:
		_link.configure(sim_rtt_ms, sim_jitter_ms, sim_loss_percent, sim_seed)
		_sim_preset_name = "por argumentos"
	_session.status_changed.connect(func(text: String) -> void: print("[net_lab] %s" % text))
	_session.local_actor_spawned.connect(_on_local_actor_spawned)
	$Hud/Menu/Box/Solo.pressed.connect(_start.bind(Role.LOCAL))
	$Hud/Menu/Box/Host.pressed.connect(_start.bind(Role.HOST))
	$Hud/Menu/Box/JoinRow/Join.pressed.connect(_on_join_pressed)
	_address_field.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_lan_label.text = "Tu IP en la red local: %s" % _lan_addresses()
	if _role_from_args:
		_start(role)
	else:
		_info.visible = false
		_menu.visible = true
	if report_seconds > 0.0:
		get_tree().create_timer(report_seconds).timeout.connect(_print_actor_report)
	if autoquit_seconds > 0.0:
		get_tree().create_timer(autoquit_seconds).timeout.connect(_print_summary_and_quit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_presses = (jump_presses + 1) & 0xFF
	elif _started and event is InputEventKey and event.pressed and not event.echo:
		var index: int = [KEY_1, KEY_2, KEY_3, KEY_4].find(event.keycode)
		if index >= 0:
			_apply_net_preset(index)


func _process(_delta: float) -> void:
	max_actors_seen = maxi(max_actors_seen, _clock.sorted_actors().size())
	if _started:
		_update_hud()


func _start(new_role: Role) -> void:
	if _started:
		return
	_started = true
	role = new_role
	_menu.visible = false
	_info.visible = true
	_camera.start_capture()
	if not sim_from_args:
		_apply_net_preset(_sim_option.selected)
	match role:
		Role.HOST:
			_session.start_host(port, bind_address)
		Role.CLIENT:
			_session.start_client(host_address, port)
		_:
			_session.start_local()


## Cambia el nivel del simulador de red. Afecta solo a esta máquina: alcanza
## con activarlo en la PC que se une.
func _apply_net_preset(index: int) -> void:
	var preset: Dictionary = NET_PRESETS[clampi(index, 0, NET_PRESETS.size() - 1)]
	_link.configure(preset["rtt"], preset["jitter"], preset["loss"], sim_seed)
	_sim_preset_name = preset["name"]
	print("[net_lab] red simulada: %s" % _net_sim_text())


func _net_sim_text() -> String:
	if not _link.is_active():
		return "sin simulación"
	return "%s (+%d ms de ida y vuelta, ±%d ms, %d %% de pérdida)" % [
		_sim_preset_name, roundi(_link.added_rtt_ms), roundi(_link.jitter_ms), roundi(_link.loss_percent),
	]


func _on_join_pressed() -> void:
	var typed := _address_field.text.strip_edges()
	host_address = typed if typed != "" else "127.0.0.1"
	_start(Role.CLIENT)


## Input de cada actor para un tick, en el host o en modo local: el propio sale
## del teclado; el de cada cliente, de lo que mandó por red. Sin nada recibido,
## el actor queda quieto.
func _input_for(actor: ActorBody, tick: int) -> ActorInput:
	if actor == _local_actor:
		if _current_input != null and _current_input.tick == tick:
			return _current_input
		return _local_input(tick)
	var remote := _net_sync.input_for(actor.owner_peer_id, tick)
	if remote != null:
		return remote
	return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, actor.state.jump_presses_seen)


## Input de este jugador: del teclado, o del guion de prueba si se pidió.
func _local_input(tick: int) -> ActorInput:
	if test_input == "walk":
		# Camina 1,5 s hacia adelante, salta a los 0,5 s y después se queda quieto.
		var walking := _local_ticks < 90
		var presses := 1 if _local_ticks >= 30 else 0
		return ActorInput.make(tick, Vector2(0, 1) if walking else Vector2.ZERO, 0.0, 0, presses)
	var move := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	return ActorInput.make(tick, move, _camera.yaw, 0, jump_presses)


## Cliente, al empezar cada tick: primero corrige con el último snapshot, después
## manda el input de este tick. El reloj simula enseguida el propio actor con
## ese mismo input, y al terminar el tick se guarda el resultado.
func _on_tick_started(tick: int) -> void:
	if not _started:
		return
	_local_ticks += 1
	if role != Role.CLIENT or not _clock.client_sync:
		return
	_net_sync.apply_pending_snapshot(_actors, _on_own_state.bind(tick))
	if is_instance_valid(_local_actor) and _clock.synced:
		_local_actor.simulated = true
		_current_input = _local_input(tick)
		_net_sync.send_input(_current_input)


func _on_tick_finished(tick: int) -> void:
	if role == Role.HOST:
		_net_sync.send_snapshot(tick, _clock.sorted_actors())
	elif role == Role.CLIENT and is_instance_valid(_local_actor) and _local_actor.simulated \
			and _current_input != null and _current_input.tick == tick:
		_prediction.record(tick, _current_input, _local_actor.state)


## Cliente: llegó del host el estado del propio actor.
func _on_own_state(host_tick: int, state_bytes: PackedByteArray, used_input_tick: int, margin: int, current_tick: int) -> void:
	if used_input_tick >= _prediction_start_tick:
		_clock.report_input_margin(margin)
	if not is_instance_valid(_local_actor):
		return
	if not _local_actor.simulated:
		# Todavía sin predicción: se muestra tal cual lo manda el host.
		_local_actor.state = ActorState.from_bytes(state_bytes)
		_local_actor.global_position = _local_actor.state.position
		_local_actor.present(_local_actor.state)
		return
	_prediction.reconcile(_local_actor, host_tick, state_bytes, used_input_tick, current_tick, _step_local)


func _step_local(input: ActorInput) -> void:
	ActorMotor.step(_local_actor, _local_actor.state, input, tuning, SimClock.TICK_DT)


## Cliente: el reloj saltó de tick. Lo predicho hasta ahora ya no sirve.
func _on_hard_resynced() -> void:
	_prediction.clear()
	_prediction_start_tick = _clock.tick + 1


func _on_local_actor_spawned(actor: ActorBody) -> void:
	_local_actor = actor
	_camera.target = actor


## Lee los argumentos de lanzamiento. Se buscan tanto en los de usuario
## (después de "--") como en los generales, porque según cómo se lance la
## instancia pueden llegar por cualquiera de los dos lados.
func _read_launch_args() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg == "--local":
			role = Role.LOCAL
			_role_from_args = true
		elif arg == "--host":
			role = Role.HOST
			_role_from_args = true
		elif arg == "--client":
			role = Role.CLIENT
			_role_from_args = true
		elif arg.begins_with("--address="):
			host_address = arg.trim_prefix("--address=")
		elif arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--bind="):
			bind_address = arg.trim_prefix("--bind=")
		elif arg.begins_with("--autoquit="):
			autoquit_seconds = arg.trim_prefix("--autoquit=").to_float()
		elif arg.begins_with("--report-after="):
			report_seconds = arg.trim_prefix("--report-after=").to_float()
		elif arg.begins_with("--test-input="):
			test_input = arg.trim_prefix("--test-input=")
		elif arg.begins_with("--sim-rtt="):
			sim_rtt_ms = arg.trim_prefix("--sim-rtt=").to_float()
			sim_from_args = true
		elif arg.begins_with("--sim-jitter="):
			sim_jitter_ms = arg.trim_prefix("--sim-jitter=").to_float()
			sim_from_args = true
		elif arg.begins_with("--sim-loss="):
			sim_loss_percent = arg.trim_prefix("--sim-loss=").to_float()
			sim_from_args = true
		elif arg.begins_with("--sim-seed="):
			sim_seed = arg.trim_prefix("--sim-seed=").to_int()


## Direcciones IPv4 privadas de esta PC: la que hay que escribir en la otra PC
## para unirse.
func _lan_addresses() -> String:
	var found := PackedStringArray()
	for address in IP.get_local_addresses():
		var parts := address.split(".")
		if parts.size() != 4:
			continue
		var second := parts[1].to_int()
		if (parts[0] == "192" and parts[1] == "168") or parts[0] == "10" or (parts[0] == "172" and second >= 16 and second <= 31):
			found.append(address)
	return ", ".join(found) if not found.is_empty() else "no encontrada"


func _update_hud() -> void:
	var lines := PackedStringArray([
		_session.status,
		"tick %d   ·   actores: %s" % [_clock.tick, _actor_ids()],
		"red simulada: %s   ·   teclas 1 a 4 para cambiarla" % _net_sim_text(),
	])
	if role == Role.CLIENT:
		lines.append("reloj: ida y vuelta %.0f ms   ·   vas %.1f ticks adelante del host   ·   saltos de reloj %d" % [_clock.rtt_ms, _clock.lead_ticks, _clock.resyncs])
		lines.append("tu input le llega al host con %d ticks de anticipación, en el peor caso   ·   ajustes de un tick: +%d / -%d" % [_clock.worst_margin, _clock.speedups, _clock.slowdowns])
		lines.append("predicción: %d coincidencias, %d correcciones (%d por input tardío), última de %.2f m" % [_prediction.matches, _prediction.corrections, _prediction.corrections_late_input, _prediction.last_correction_meters])
		lines.append("snapshots que no llegaron a tiempo: %.1f %%" % _snapshot_loss_percent())
	if role == Role.HOST:
		for actor in _clock.sorted_actors():
			if actor != _local_actor:
				lines.append("jugador %d: su input llega con %d ticks de anticipación" % [actor.owner_peer_id, _net_sync.input_margin_ticks(actor.owner_peer_id, _clock.tick)])
	if is_instance_valid(_local_actor):
		var s := _local_actor.state
		lines.append("Modo: %s   ·   en suelo: %s" % [ActorState.Mode.keys()[s.mode], "sí" if s.on_floor else "no"])
		lines.append("Velocidad: %.2f m/s horizontal, %.2f m/s vertical" % [Vector2(s.velocity.x, s.velocity.z).length(), s.velocity.y])
		lines.append("Posición: (%.2f, %.2f, %.2f)" % [s.position.x, s.position.y, s.position.z])
	lines.append("")
	lines.append("WASD mover · Espacio saltar · mouse mirar · Esc suelta el mouse")
	_info.text = "\n".join(lines)


func _print_actor_report() -> void:
	for actor in _clock.sorted_actors():
		print("[net_lab] estado del actor %d: %s" % [actor.owner_peer_id, actor.state.describe()])


func _actor_ids() -> String:
	var ids: Array[int] = []
	for actor in _clock.sorted_actors():
		ids.append(actor.owner_peer_id)
	return str(ids)


func _snapshot_loss_percent() -> float:
	var expected := _net_sync.snapshots_received + _net_sync.snapshots_missing
	return 100.0 * _net_sync.snapshots_missing / expected if expected > 0 else 0.0


func _print_summary_and_quit() -> void:
	print("[net_lab] resumen: rol=%s tick=%d actores=%s máximo=%d sincronizado=%s ida_y_vuelta=%.1fms adelanto=%.1f peor_margen=%d ajustes=+%d/-%d saltos_de_reloj=%d coincidencias=%d correcciones=%d (input_tardío=%d) alineaciones=%d snapshots_perdidos=%.1f%% red=%s paquetes_perdidos_por_el_simulador=%d" % [
		Role.keys()[role], _clock.tick, _actor_ids(), max_actors_seen, _clock.synced,
		_clock.rtt_ms, _clock.lead_ticks, _clock.worst_margin, _clock.speedups, _clock.slowdowns, _clock.resyncs,
		_prediction.matches, _prediction.corrections, _prediction.corrections_late_input, _prediction.alignments,
		_snapshot_loss_percent(), _net_sim_text(), _link.dropped,
	])
	get_tree().quit()
