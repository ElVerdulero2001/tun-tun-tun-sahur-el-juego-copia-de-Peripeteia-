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
## Paso 6: el cliente predice su propio actor y mantiene el adelanto sobre el host.
## Paso 7: con cada input viaja lo que el cliente predijo (la afirmación) y el
## host la adopta si es creíble. En el host, E empuja a los demás jugadores (un
## evento del host, que sube su época) y Q prende o apaga la adopción.
## Paso 8: los demás jugadores se ven interpolados unos 100 ms en el pasado,
## las correcciones del propio se suavizan y el host manda 30 snapshots por
## segundo. Quien cae del mapa reaparece en su lugar.
##
## El rol se elige con el menú. Para pruebas automáticas también se puede pasar
## por argumentos: --local, --host o --client, --address=IP, --port=N,
## --bind=IP (solo host), --autoquit=SEGUNDOS (imprime un resumen y cierra),
## --report-after=SEGUNDOS (imprime el estado de cada actor), --trace (el
## cliente imprime su adelanto cada medio segundo), --test-input=walk (camina y
## salta solo, sin teclado) o --test-input=zigzag (cambia de dirección cada
## medio segundo durante 25 s), --no-adoption y --test-push-at=S1,S2 (solo
## host: empuja a los demás a esos segundos) y, para simular red,
## --sim-rtt=MS, --sim-jitter=MS, --sim-loss=PORCENTAJE, --sim-seed=N, los
## tirones con --sim-stall-every=MS y --sim-stall=MS y, si la red simulada
## tiene que empezar o terminar en plena partida, --sim-after=SEGUNDOS y
## --sim-until=SEGUNDOS.

const DEFAULT_PORT := 7777
## Empujón de la tecla E: velocidad hacia arriba y hacia afuera del host, en m/s.
const PUSH_UP_SPEED := 5.0
const PUSH_AWAY_SPEED := 4.0
## Más abajo que esto, el actor cayó del mapa y reaparece.
const FALL_LIMIT := -30.0
## Niveles del simulador de red, con las teclas 1 a 5. La demora es de ida y
## vuelta; los tirones traban la conexión stall ms cada stall_every ms.
const NET_PRESETS := [
	{"name": "sin simulación", "rtt": 0.0, "jitter": 0.0, "loss": 0.0},
	{"name": "internet buena", "rtt": 40.0, "jitter": 5.0, "loss": 0.0},
	{"name": "internet normal", "rtt": 120.0, "jitter": 20.0, "loss": 1.0},
	{"name": "internet mala", "rtt": 200.0, "jitter": 40.0, "loss": 5.0},
	{"name": "Wi-Fi con tirones", "rtt": 20.0, "jitter": 5.0, "loss": 0.0, "stall_every": 3000.0, "stall": 150.0},
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
var sim_stall_every_ms := 0.0
var sim_stall_ms := 0.0
## Segundos tras los que se activa y se apaga la red pedida por argumentos (0 = desde el inicio, nunca).
var sim_after_seconds := 0.0
var sim_until_seconds := 0.0
var trace := false
## Segundos a los que el host empuja a los demás, pedidos por argumentos.
var test_push_seconds := PackedFloat64Array()
var _ready_msec := 0
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
## Host (paso 7): adopción de lo que afirman los clientes.
var _adoption := ClaimAdoption.new()
## Host: empujones pedidos, que se aplican al empezar el próximo tick.
var _push_requested := false
var pushes := 0
var respawns := 0
## Cliente (paso 8): los demás jugadores, interpolados entre snapshots.
var _interpolation := RemoteInterpolation.new()
## Cliente: cuánto se traban en pantalla los demás jugadores. Un tick cuenta
## como tirón si el actor se movió menos de un cuarto o más del doble de lo
## que corresponde a su velocidad.
var remote_ticks_measured := 0
var remote_stutters := 0
var _remote_last_positions := {}  # peer -> Vector3

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
	SimClock.apply_tick_rate(SimClock.TICK_RATE)
	# Godot lo recomienda para juegos en red: los ticks quedan atados al reloj real.
	Engine.physics_jitter_fix = 0.0


func _ready() -> void:
	_ready_msec = Time.get_ticks_msec()
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
	multiplayer.peer_disconnected.connect(_interpolation.forget)
	for preset in NET_PRESETS:
		_sim_option.add_item(preset["name"])
	if sim_from_args:
		_sim_preset_name = "por argumentos"
		if sim_after_seconds > 0.0:
			_real_timer(sim_after_seconds, _apply_sim_from_args)
		else:
			_apply_sim_from_args()
		if sim_until_seconds > 0.0:
			_real_timer(sim_until_seconds, _apply_net_preset.bind(0))
	if trace:
		_real_timer(0.5, _print_trace)
	for seconds in test_push_seconds:
		_real_timer(seconds, func() -> void: _push_requested = true)
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
		_real_timer(report_seconds, _print_actor_report)
	if autoquit_seconds > 0.0:
		_real_timer(autoquit_seconds, _print_summary_and_quit)


## Temporizador en segundos reales: el cliente cambia time_scale al ajustar su
## ritmo, y eso no tiene que adelantar ni atrasar las pruebas.
func _real_timer(seconds: float, callback: Callable) -> void:
	get_tree().create_timer(seconds, true, false, true).timeout.connect(callback)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_presses = (jump_presses + 1) & 0xFF
	elif _started and event is InputEventKey and event.pressed and not event.echo:
		var index: int = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5].find(event.keycode)
		if index >= 0:
			_apply_net_preset(index)
		elif role == Role.HOST and event.keycode == KEY_E:
			_push_requested = true
		elif role == Role.HOST and event.keycode == KEY_Q:
			_adoption.enabled = not _adoption.enabled
			print("[net_lab] adopción %s" % ("prendida" if _adoption.enabled else "apagada"))


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
	_link.configure(preset["rtt"], preset["jitter"], preset["loss"], sim_seed, preset.get("stall_every", 0.0), preset.get("stall", 0.0))
	_sim_preset_name = preset["name"]
	print("[net_lab] red simulada: %s" % _net_sim_text())


func _apply_sim_from_args() -> void:
	_link.configure(sim_rtt_ms, sim_jitter_ms, sim_loss_percent, sim_seed, sim_stall_every_ms, sim_stall_ms)
	print("[net_lab] red simulada: %s" % _net_sim_text())


func _net_sim_text() -> String:
	if not _link.is_active():
		return "sin simulación"
	var text := "%s (+%d ms de ida y vuelta, ±%d ms, %d %% de pérdida" % [
		_sim_preset_name, roundi(_link.added_rtt_ms), roundi(_link.jitter_ms), roundi(_link.loss_percent),
	]
	if _link.stall_ms > 0.0:
		text += ", se traba %d ms cada %.1f s" % [roundi(_link.stall_ms), _link.stall_every_ms / 1000.0]
	return text + ")"


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
	if test_input == "zigzag":
		# Un cuadrado que cambia de lado cada medio segundo y un salto cada dos:
		# como el input cambia seguido, un input tardío se nota en las correcciones.
		# A los 25 s se queda quieto, para comparar el estado final en las dos PCs.
		var moving := _local_ticks < 1500
		var sides := [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]
		var move: Vector2 = sides[(_local_ticks / 30) % sides.size()] if moving else Vector2.ZERO
		var zigzag_presses := (mini(_local_ticks, 1500) / 120) & 0xFF
		return ActorInput.make(tick, move, 0.0, 0, zigzag_presses)
	var move := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	return ActorInput.make(tick, move, _camera.yaw, 0, jump_presses)


## Al empezar cada tick. Host: aplica los eventos (reapariciones y empujones)
## antes de mover a nadie. Cliente: primero corrige con el último snapshot y
## ubica a los demás en su pose interpolada, después arma el input de este
## tick; el reloj simula enseguida el propio actor con ese input.
func _on_tick_started(tick: int) -> void:
	if not _started:
		return
	_local_ticks += 1
	if role != Role.CLIENT:
		_respawn_fallen()
	if role == Role.HOST and _push_requested:
		_push_requested = false
		_push_others()
	if role != Role.CLIENT or not _clock.client_sync:
		return
	_net_sync.apply_pending_snapshot(_on_own_state.bind(tick), _interpolation.add)
	_interpolation.advance()
	for actor in _clock.sorted_actors():
		if _is_remote(actor):
			_interpolation.place(actor)
	if is_instance_valid(_local_actor) and _clock.synced:
		_local_actor.simulated = true
		_current_input = _local_input(tick)


## Al terminar cada tick. Host: decide qué afirmaciones adopta y después manda
## el snapshot. Cliente: guarda lo predicho y se lo manda al host con el input.
func _on_tick_finished(tick: int) -> void:
	if role == Role.HOST:
		for actor in _clock.sorted_actors():
			if _is_remote(actor):
				_adoption.consider(actor, _net_sync.claim_for(actor.owner_peer_id, tick))
		_net_sync.send_snapshot(tick, _clock.sorted_actors())
	elif role == Role.CLIENT and is_instance_valid(_local_actor) and _local_actor.simulated \
			and _current_input != null and _current_input.tick == tick:
		_prediction.record(tick, _current_input, _local_actor.state)
		_net_sync.send_ticks(_prediction.recent(NetSync.INPUT_REDUNDANCY))
	if role == Role.CLIENT:
		_measure_remote_smoothness()


## Cliente: mide, tick a tick, si los demás jugadores se mueven parejo en pantalla.
func _measure_remote_smoothness() -> void:
	for actor in _clock.sorted_actors():
		if not _is_remote(actor):
			continue
		var peer := actor.owner_peer_id
		var last: Variant = _remote_last_positions.get(peer)
		_remote_last_positions[peer] = actor.global_position
		var speed := Vector2(actor.state.velocity.x, actor.state.velocity.z).length()
		if last == null or speed < 1.0:
			continue
		var expected := speed / _clock.rate_hz
		var moved := Vector2(actor.global_position.x - last.x, actor.global_position.z - last.z).length()
		remote_ticks_measured += 1
		if moved < expected * 0.25 or moved > expected * 2.0:
			remote_stutters += 1


## Host: empuja a los demás actores, hacia arriba y lejos del propio. Es un
## evento inmediato: cada cliente se entera con el snapshot y se corrige. Sube
## la época del empujado, así el host no adopta las afirmaciones que ese
## cliente predijo sin saber del empujón.
func _push_others() -> void:
	for actor in _clock.sorted_actors():
		if not _is_remote(actor):
			continue
		var away := Vector3.BACK
		if is_instance_valid(_local_actor):
			var offset := actor.state.position - _local_actor.state.position
			offset.y = 0.0
			if offset.length_squared() > 0.0001:
				away = offset.normalized()
		ActorMotor.push(actor.state, away * PUSH_AWAY_SPEED + Vector3.UP * PUSH_UP_SPEED)
		actor.state.epoch += 1
	pushes += 1
	print("[net_lab] empujón %d en el tick %d" % [pushes, _clock.tick])


## Host o modo local: quien cayó del mapa reaparece en su lugar, quieto y
## apoyado. Es un evento del host (sube la época) y un teleport.
func _respawn_fallen() -> void:
	for actor in _clock.sorted_actors():
		if actor.state.position.y > FALL_LIMIT:
			continue
		var fresh := ActorState.new()
		fresh.position = _session.spawn_position(actor.owner_peer_id)
		fresh.mode = ActorState.Mode.GROUND
		fresh.on_floor = true
		# Las pulsaciones ya vistas se conservan: si no, la próxima parece un salto nuevo.
		fresh.jump_presses_seen = actor.state.jump_presses_seen
		fresh.epoch = actor.state.epoch + 1
		fresh.quantize()
		actor.state = fresh
		actor.apply_state(fresh)
		actor.teleported()
		respawns += 1
		print("[net_lab] reapareció el jugador %d en el tick %d" % [actor.owner_peer_id, _clock.tick])


## Si el actor es de otro jugador. Se mira el dueño y no _local_actor, que se
## asigna un frame después de aparecer.
func _is_remote(actor: ActorBody) -> bool:
	return actor.owner_peer_id != multiplayer.get_unique_id()


## Cliente: llegó del host el estado del propio actor.
func _on_own_state(host_tick: int, state_bytes: PackedByteArray, used_input_tick: int, margin: int, current_tick: int) -> void:
	if used_input_tick >= _prediction_start_tick:
		_clock.report_input_margin(host_tick, margin)
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
	# La cámara sigue lo que se ve, con el desvío de las correcciones incluido.
	_camera.target = actor.visual_root()


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
		elif arg.begins_with("--sim-stall-every="):
			sim_stall_every_ms = arg.trim_prefix("--sim-stall-every=").to_float()
			sim_from_args = true
		elif arg.begins_with("--sim-stall="):
			sim_stall_ms = arg.trim_prefix("--sim-stall=").to_float()
			sim_from_args = true
		elif arg.begins_with("--sim-after="):
			sim_after_seconds = arg.trim_prefix("--sim-after=").to_float()
		elif arg.begins_with("--sim-until="):
			sim_until_seconds = arg.trim_prefix("--sim-until=").to_float()
		elif arg == "--trace":
			trace = true
		elif arg == "--no-adoption":
			_adoption.enabled = false
		elif arg.begins_with("--test-push-at="):
			for seconds in arg.trim_prefix("--test-push-at=").split(","):
				test_push_seconds.append(seconds.to_float())


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
		"red simulada: %s   ·   teclas 1 a 5 para cambiarla" % _net_sim_text(),
	])
	if role == Role.CLIENT:
		lines.append("reloj: ida y vuelta %.0f ms   ·   vas %.1f ticks adelante del host   ·   saltos de reloj %d" % [_clock.rtt_ms, _clock.lead_ticks, _clock.resyncs])
		lines.append("tu input le llega al host con %.1f ticks de anticipación, en el peor caso   ·   ritmo: %d ticks por segundo (ganados +%.1f / perdidos -%.1f)" % [_clock.worst_margin, _clock.rate_hz, _clock.ticks_gained, _clock.ticks_shed])
		lines.append("predicción: %d coincidencias, %d correcciones (la última de %.2f m), %d esperas por input tardío" % [_prediction.matches, _prediction.corrections, _prediction.last_correction_meters, _prediction.waits_late_input])
		lines.append("snapshots que no llegaron a tiempo: %.1f %%" % _snapshot_loss_percent())
		lines.append("los demás se ven %d ms en el pasado   ·   %d ticks esperando un snapshot   ·   tirones: %.1f %%" % [
			roundi(RemoteInterpolation.DELAY_TICKS * SimClock.TICK_DT * 1000.0), _interpolation.starved,
			100.0 * remote_stutters / maxi(remote_ticks_measured, 1),
		])
	if role == Role.HOST:
		lines.append("adopción: %s   ·   empujones: %d   ·   reapariciones: %d" % ["prendida" if _adoption.enabled else "apagada", pushes, respawns])
		for actor in _clock.sorted_actors():
			if actor != _local_actor:
				var peer := actor.owner_peer_id
				lines.append("jugador %d: su input llega con %d ticks de anticipación   ·   época %d" % [peer, _net_sync.input_margin_ticks(peer, _clock.tick), actor.state.epoch])
				lines.append("      afirmaciones: %d adoptadas (la más lejana a %.2f m), rechazadas %d por época, %d por distancia, %d por pose" % [
					_adoption.count(peer, ClaimAdoption.Result.ADOPTED), _adoption.max_difference(peer),
					_adoption.count(peer, ClaimAdoption.Result.WRONG_EPOCH), _adoption.count(peer, ClaimAdoption.Result.TOO_FAR),
					_adoption.count(peer, ClaimAdoption.Result.BAD_POSE),
				])
	if is_instance_valid(_local_actor):
		var s := _local_actor.state
		lines.append("Modo: %s   ·   en suelo: %s   ·   época: %d" % [ActorState.Mode.keys()[s.mode], "sí" if s.on_floor else "no", s.epoch])
		lines.append("Velocidad: %.2f m/s horizontal, %.2f m/s vertical" % [Vector2(s.velocity.x, s.velocity.z).length(), s.velocity.y])
		lines.append("Posición: (%.2f, %.2f, %.2f)" % [s.position.x, s.position.y, s.position.z])
	lines.append("")
	lines.append("WASD mover · Espacio saltar · mouse mirar · Esc suelta el mouse")
	if role == Role.HOST:
		lines.append("E empuja a los demás jugadores · Q prende o apaga la adopción")
	_info.text = "\n".join(lines)


func _print_actor_report() -> void:
	for actor in _clock.sorted_actors():
		print("[net_lab] estado del actor %d: %s" % [actor.owner_peer_id, actor.state.describe()])


## Prueba: cada medio segundo, cómo viene el adelanto del cliente.
func _print_trace() -> void:
	if role == Role.CLIENT and _clock.synced:
		print("[net_lab] traza %.1fs tick=%d adelanto=%.1f peor_margen=%.1f ritmo=%d correcciones=%d esperas=%d alineaciones=%d época=%d" % [
			(Time.get_ticks_msec() - _ready_msec) / 1000.0, _clock.tick, _clock.lead_ticks, _clock.worst_margin,
			_clock.rate_hz, _prediction.corrections, _prediction.waits_late_input, _prediction.alignments,
			_local_actor.state.epoch if is_instance_valid(_local_actor) else -1,
		])
	_real_timer(0.5, _print_trace)


func _actor_ids() -> String:
	var ids: Array[int] = []
	for actor in _clock.sorted_actors():
		ids.append(actor.owner_peer_id)
	return str(ids)


func _snapshot_loss_percent() -> float:
	var expected := _net_sync.snapshots_received + _net_sync.snapshots_missing
	return 100.0 * _net_sync.snapshots_missing / expected if expected > 0 else 0.0


func _print_summary_and_quit() -> void:
	print("[net_lab] resumen: rol=%s tick=%d actores=%s máximo=%d sincronizado=%s ida_y_vuelta=%.1fms adelanto=%.1f peor_margen=%.1f ritmo=%d ganados=+%.1f perdidos=-%.1f saltos_de_reloj=%d coincidencias=%d correcciones=%d esperas_input_tardío=%d alineaciones=%d snapshots_perdidos=%.1f%% red=%s paquetes_perdidos_por_el_simulador=%d" % [
		Role.keys()[role], _clock.tick, _actor_ids(), max_actors_seen, _clock.synced,
		_clock.rtt_ms, _clock.lead_ticks, _clock.worst_margin, _clock.rate_hz, _clock.ticks_gained, _clock.ticks_shed, _clock.resyncs,
		_prediction.matches, _prediction.corrections, _prediction.waits_late_input, _prediction.alignments,
		_snapshot_loss_percent(), _net_sim_text(), _link.dropped,
	])
	if role == Role.CLIENT:
		print("[net_lab] los demás en pantalla: %d tirones en %d ticks medidos (%.1f %%), %d ticks esperando un snapshot" % [
			remote_stutters, remote_ticks_measured, 100.0 * remote_stutters / maxi(remote_ticks_measured, 1), _interpolation.starved,
		])
	if respawns > 0:
		print("[net_lab] reapariciones: %d" % respawns)
	for peer in _adoption.peers():
		print("[net_lab] adopción del jugador %d: prendida=%s empujones=%d iguales=%d adoptadas=%d (máx %.3f m) rechazadas: época=%d distancia=%d pose=%d apagada=%d sin_afirmación=%d" % [
			peer, _adoption.enabled, pushes,
			_adoption.count(peer, ClaimAdoption.Result.SAME),
			_adoption.count(peer, ClaimAdoption.Result.ADOPTED), _adoption.max_difference(peer),
			_adoption.count(peer, ClaimAdoption.Result.WRONG_EPOCH),
			_adoption.count(peer, ClaimAdoption.Result.TOO_FAR),
			_adoption.count(peer, ClaimAdoption.Result.BAD_POSE),
			_adoption.count(peer, ClaimAdoption.Result.OFF),
			_adoption.count(peer, ClaimAdoption.Result.NO_CLAIM),
		])
	get_tree().quit()
