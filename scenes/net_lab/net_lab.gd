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
## Punto 6 de la validación: colgarse de la cintura de un compañero agarrado de
## un borde o de una escalera. Colgado así, el cliente no predice su actor
## (cambio de línea): lo muestra relativo al compañero tal como lo ve y sigue
## mandando su input; cuando el host dice que se soltó, vuelve a predecir.
##
## El rol se elige con el menú. Para pruebas automáticas también se puede pasar
## por argumentos: --local, --host o --client, --address=IP, --port=N,
## --bind=IP (solo host), --autoquit=SEGUNDOS (imprime un resumen y cierra),
## --report-after=SEGUNDOS (imprime el estado de cada actor), --trace (el
## cliente imprime su adelanto cada medio segundo), --test-input=walk (camina y
## salta solo, sin teclado), --test-input=zigzag (cambia de dirección cada
## medio segundo durante 25 s), --test-input=ride:ID (se sube a esa base y
## salta arriba cada 3 s), --test-input=hop:ID (se sube y después salta afuera
## y adentro cada 2,5 s), --test-input=edge:ID (igual, pero salta hacia el
## borde), --test-input=walkoff:ID (sale y entra caminando, sin saltar),
## --test-input=tunnel (se desliza en el túnel largo y sale agachado),
## --test-input=crouchjump (salta frente a la pared de medidas y se agacha
## en el aire), --test-input=ladder (sube y baja por la escalera de la torre)
## o --test-input=laddertop (la sube y sale al techo de la torre),
## --test-spawn-at=X,Z (solo host), --test-pause-at=TICK (jugando solo: se
## pone la pausa en ese tick), --no-adoption y
## --test-push-at=S1,S2 y --test-scheduled-push-at=S1,S2 (solo host: empuja a
## los demás a esos segundos, inmediato o programado), --test-push-force=N
## (fuerza de esos empujones, de 0 a 5; 4 si no se pide), --test-schedule-ticks=N
## (el programado se fija N ticks adelante, para probar uno que llega tarde),
## --test-input=ladderhold (sube la escalera de la torre a 1,5 m y se queda),
## --test-input=hookwall (se agarra del muro alto desde el cajón y se corre al
## medio; con hookwall:drop, se suelta 2 s después de que alguien se cuelga de
## él), --test-input=hook:wall o hook:ladder (se cuelga del compañero que está
## en el muro alto o en la escalera, y después se suelta, salta para arriba o
## salta hacia atrás, por turnos) y,
## para simular red,
## --sim-rtt=MS, --sim-jitter=MS, --sim-loss=PORCENTAJE, --sim-seed=N, los
## tirones con --sim-stall-every=MS y --sim-stall=MS y, si la red simulada
## tiene que empezar o terminar en plena partida, --sim-after=SEGUNDOS y
## --sim-until=SEGUNDOS.

const DEFAULT_PORT := 7777
## Empujón de la tecla E: velocidad hacia arriba y hacia afuera del host, en m/s.
const PUSH_UP_SPEED := 5.0
const PUSH_AWAY_SPEED := 4.0
## Fuerza de los empujones (escala de 0 a 5 contra el agarre de cada modo). El
## fuerte saca de una escalera (agarre 3); el débil, con Shift, no.
const PUSH_FORCE_STRONG := 4
const PUSH_FORCE_WEAK := 2
## Empujón programado: además de lo que tarda en llegar, este colchón en ticks.
const SCHEDULE_BUFFER_TICKS := 4
## Más abajo que esto, el actor cayó del mapa y reaparece.
const FALL_LIMIT := -30.0
## Cliente: a menos de esta distancia del actor propio, en metros, una
## plataforma guionada se ve en el tick propio; a más de PLATFORM_FAR, en el
## mismo pasado que los demás jugadores; en el medio, pasa de a poco.
const PLATFORM_NEAR := 1.5
const PLATFORM_FAR := 6.0
## Cuánto dura un aviso arriba del panel, en milisegundos.
const FLASH_MSEC := 3000
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
## Segundos a los que el host empuja a los demás, pedidos por argumentos:
## inmediato o programado, con la fuerza de test_push_force.
var test_push_seconds := PackedFloat64Array()
var test_scheduled_push_seconds := PackedFloat64Array()
var test_push_force := PUSH_FORCE_STRONG
## Para probar un empujón programado que llega tarde: si es mayor que cero, el
## host lo programa para dentro de esta cantidad fija de ticks.
var test_schedule_ticks := 0
## Jugando solo: tick en que se pone la pausa sola, para probarla. 0 = nunca.
var test_pause_tick := 0
## Prueba de divergencia: el cliente corre su estado predicho este tanto, en
## milímetros y al azar, en cada tick, como si Jolt calculara distinto.
var test_perturb_mm := 0.0
var _perturb_rng := RandomNumberGenerator.new()
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
## Host: empujones pedidos, que se aplican al empezar el próximo tick, como
## [programado, fuerza].
var _push_requests: Array = []
## Host: empujones programados que todavía no llegaron a su tick, como
## [tick, peer, impulso, fuerza].
var _host_events: Array = []
var pushes := 0
var scheduled_pushes := 0
var respawns := 0
## Cliente: empujones programados que le anunció el host, por tick: [impulso, fuerza].
var _client_events := {}
## Cliente: empujones programados que llegaron antes de su tick, los que
## llegaron tarde y se repitió desde su tick, y los que llegaron tan tarde que
## los tuvo que arreglar la corrección del snapshot.
var events_on_time := 0
var events_late := 0
var events_too_late := 0
## Cliente (paso 8): los demás jugadores, interpolados entre snapshots.
var _interpolation := RemoteInterpolation.new()
## Prueba de bases: contador de saltos de los inputs de prueba `ride` y `hop`.
var _ride_presses := 0
## Prueba `hop`: tick local en que llegó a la base por primera vez.
var _hop_start := -1
## Prueba `tunnel`: tramo del recorrido y ticks en que quedó parado bajo el techo.
var _tunnel_phase := 0
var _tunnel_standing_under_roof := 0
## Prueba `crouchjump`: tick local en que llegó frente a la pared de medidas.
var _crouch_jump_start := -1
## Prueba `ladder`: hacia dónde trepa (1 sube, -1 baja) y, en `laddertop`, si
## ya llegó arriba.
var _ladder_direction := 1.0
var _ladder_top_done := false
## Prueba `hang`: tramo del ciclo, ticks en el tramo, vuelta del ciclo,
## pulsaciones de salto propias y cuántas veces se agarró y subió.
var _hang_phase := 0
var _hang_since := 0
var _hang_cycle := 0
var _hang_presses := 0
var hang_grabs := 0
var hang_climbs := 0
## Prueba `steps`: punto del recorrido al que va, ticks desde que lo empezó y
## la altura más alta de los pies.
var _steps_index := 0
var _steps_since := 0
var _steps_max_height := 0.0
## Cliente, cambio de línea: si el actor propio cuelga de un compañero (no se
## predice) y desde qué tick; los estados del host anteriores a ese tick no
## cuentan para salir. Cambios de línea, de ida y de vuelta.
var _hooked_line := false
var _hooked_since := -1
var line_changes := 0
## Cliente: lo que se veía al entrar a la línea del host por un snapshot, para
## mezclarlo cuando el cuerpo ya esté en su pose nueva.
var _line_blend_from: Variant = null
## Cliente: cuánto saltó el cuerpo en el cambio de línea más grande, al entrar
## y al salir (lo reparte la mezcla de 0,2 s).
var line_jump_in_max := 0.0
var line_jump_out_max := 0.0
## Cuánto se separa en pantalla quien cuelga de este jugador de la pose que le
## daría el cuerpo de este jugador, como máximo.
var hooked_gap_max := 0.0
## Prueba de desconexión: con un compañero colgado de él (o colgado de uno),
## cierra el juego después de tantos ticks. 0 = nunca.
var test_quit_hooked := 0
## Host: cambios de quién cuelga de quién (eventos que suben la época) y
## colgados que se soltaron porque otro se colgó del mismo en el mismo tick.
var hook_events := 0
var hook_kicks := 0
## Pruebas `hook` y `hookwall`: tramo, ticks en el tramo, vuelta del ciclo,
## pulsaciones de salto propias y lo que pasó.
var _hook_phase := 0
var _hook_since := 0
var _hook_cycle := 0
var _hook_presses := 0
var hook_grabs := 0
var hook_releases := 0
var hook_jumps_up := 0
var hook_jumps_away := 0
var hook_fell_with_mate := 0
var hook_edges_after := 0
var hook_tops := 0
var hook_drops := 0
var hook_other_grabs := 0
## Aviso que se muestra arriba del panel hasta _flash_until_msec.
var _flash_text := ""
var _flash_until_msec := 0
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
		_real_timer(seconds, func() -> void: _push_requests.append([false, test_push_force]))
	for seconds in test_scheduled_push_seconds:
		_real_timer(seconds, func() -> void: _push_requests.append([true, test_push_force]))
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
	if event.is_action_pressed("captura"):
		_save_capture()
	elif event.is_action_pressed("jump"):
		jump_presses = (jump_presses + 1) & 0xFF
	elif _started and role == Role.LOCAL and event.is_action_pressed("toggle_debug_freeze"):
		_set_paused(not _clock.paused)
	elif _started and role == Role.LOCAL and _clock.paused and event.is_action_pressed("avanzar_tick"):
		_clock.step()
	elif _started and event is InputEventKey and event.pressed and not event.echo:
		var index: int = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5].find(event.keycode)
		if index >= 0:
			_apply_net_preset(index)
		elif role == Role.HOST and (event.keycode == KEY_E or event.keycode == KEY_R):
			var force := PUSH_FORCE_WEAK if event.shift_pressed else PUSH_FORCE_STRONG
			_push_requests.append([event.keycode == KEY_R, force])
		elif role == Role.HOST and event.keycode == KEY_Q:
			_adoption.enabled = not _adoption.enabled
			print("[net_lab] adopción %s" % ("prendida" if _adoption.enabled else "apagada"))


## Captura de pantalla (F12, acción `captura`): guarda en el Escritorio lo que
## se ve, con el panel. Anda aunque haya otras teclas apretadas, como Ctrl para
## agacharse. Espera a que termine de dibujarse el cuadro.
func _save_capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_flash("No se pudo tomar la captura")
		return
	var stamp := Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var file_name := "captura_lab_%s_%03d.png" % [stamp, Time.get_ticks_msec() % 1000]
	var path := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join(file_name)
	var error := image.save_png(path)
	print("[net_lab] captura: %s (error %d)" % [path, error])
	_flash("Captura guardada en el Escritorio: %s" % file_name if error == OK
			else "No se pudo guardar la captura (error %d)" % error)


## Muestra un aviso arriba del panel durante unos segundos.
func _flash(text: String) -> void:
	_flash_text = text
	_flash_until_msec = Time.get_ticks_msec() + FLASH_MSEC


## Jugando solo: congela la simulación donde está, para mirarla. La balsa la
## mueve la física y no el reloj, así que se congela aparte.
func _set_paused(on: bool) -> void:
	_clock.paused = on
	for base in BaseRegistry.all():
		if base is HostRaft and base.simulated:
			base.freeze = on


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
			# Las balsas las simula solo el host: acá pasan a ser copias que mueve la interpolación.
			for base in BaseRegistry.all():
				if base is HostRaft:
					base.become_copy()
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
	if test_input.begins_with("ride:"):
		return _ride_input(tick, test_input.trim_prefix("ride:").to_int())
	if test_input.begins_with("hop:"):
		return _hop_input(tick, test_input.trim_prefix("hop:").to_int(), 3.2, true)
	if test_input.begins_with("edge:"):
		return _hop_input(tick, test_input.trim_prefix("edge:").to_int(), 1.4, true)
	if test_input.begins_with("walkoff:"):
		return _hop_input(tick, test_input.trim_prefix("walkoff:").to_int(), 2.5, false)
	if test_input == "tunnel":
		return _tunnel_input(tick)
	if test_input == "steps":
		return _steps_input(tick)
	if test_input == "crouchjump":
		return _crouch_jump_input(tick)
	if test_input == "hang" or test_input.begins_with("hang:"):
		return _hang_input(tick, test_input.trim_prefix("hang:").to_int() if test_input.begins_with("hang:") else 0)
	if test_input == "ladder" or test_input == "laddertop":
		return _ladder_input(tick, test_input == "laddertop")
	if test_input == "ladderhold":
		return _ladder_hold_input(tick)
	if test_input == "hookwall" or test_input == "hookwall:drop":
		return _hook_wall_input(tick, test_input == "hookwall:drop")
	if test_input.begins_with("hook:"):
		return _hook_input(tick, test_input.trim_prefix("hook:"))
	if test_input == "zigzag":
		# Un cuadrado que cambia de lado cada medio segundo y un salto cada dos:
		# como el input cambia seguido, un input tardío se nota en las correcciones.
		# A los 25 s se queda quieto, para comparar el estado final en las dos PCs.
		var moving := _local_ticks < 1500
		var sides := [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]
		@warning_ignore("integer_division")
		var side: Vector2 = sides[(_local_ticks / 30) % sides.size()] if moving else Vector2.ZERO
		@warning_ignore("integer_division")
		var zigzag_presses := (mini(_local_ticks, 1500) / 120) & 0xFF
		return ActorInput.make(tick, side, 0.0, 0, zigzag_presses)
	var move := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var buttons := 0
	if Input.is_action_pressed("crouch"):
		buttons |= ActorInput.BUTTON_CROUCH
	if Input.is_action_pressed("run"):
		buttons |= ActorInput.BUTTON_RUN
	return ActorInput.make(tick, move, _camera.yaw, buttons, jump_presses)


## Prueba de bases: va hasta la base pedida y se queda arriba, dando vueltas
## cerca del centro y saltando cada 3 s. Si la base está más alta que los pies,
## salta para subirse; si está muy alta (un ascensor arriba), la espera afuera.
func _ride_input(tick: int, base_id: int) -> ActorInput:
	var base = BaseRegistry.find(base_id)
	if base == null or not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _ride_presses)
	var state := _local_actor.state
	var me := BaseRegistry.world_position(state)
	var center: Vector3 = base.base_origin()
	var target := center
	if state.base_id == base_id:
		var angle := _local_ticks * TAU / 240.0
		target = center + Vector3(cos(angle), 0.0, sin(angle)) * 0.8
		if _local_ticks % 180 == 0:
			_ride_presses = (_ride_presses + 1) & 0xFF
	elif center.y > me.y + 0.5:
		target = me
	elif absf(center.z - me.z) > 1.5 and absf(center.x - me.x) > 1.0:
		# Primero en x y después en z, para rodear la pared del laboratorio.
		target = Vector3(center.x, me.y, me.z)
	elif center.y > me.y + 0.1 and state.on_floor and Vector2(center.x - me.x, center.z - me.z).length() < 2.2 \
			and _local_ticks % 30 == 0:
		_ride_presses = (_ride_presses + 1) & 0xFF
	var to := Vector2(target.x - me.x, target.z - me.z)
	var move := Vector2(to.x, -to.y).limit_length(1.0) if to.length() > 0.15 else Vector2.ZERO
	return ActorInput.make(tick, move, 0.0, 0, _ride_presses)


## Prueba de subir y bajar: llega a la base como `ride` y después, cada 2,5 s,
## va hasta `side` metros al costado del centro de la base o vuelve al centro,
## saltando al empezar cada tramo si `jump`.
func _hop_input(tick: int, base_id: int, side: float, jump: bool) -> ActorInput:
	var base = BaseRegistry.find(base_id)
	if base == null or not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _ride_presses)
	if _hop_start < 0:
		if _local_actor.state.base_id != base_id:
			return _ride_input(tick, base_id)
		_hop_start = _local_ticks
	var elapsed := _local_ticks - _hop_start
	if jump and elapsed % 150 == 0:
		_ride_presses = (_ride_presses + 1) & 0xFF
	var me := BaseRegistry.world_position(_local_actor.state)
	var target: Vector3 = base.base_origin()
	@warning_ignore("integer_division")
	if (elapsed / 150) % 2 == 0:
		target += Vector3(0.0, 0.0, side)
	var to := Vector2(target.x - me.x, target.z - me.z)
	var move := Vector2(to.x, -to.y).limit_length(1.0) if to.length() > 0.15 else Vector2.ZERO
	return ActorInput.make(tick, move, 0.0, 0, _ride_presses)


## Prueba de escalones en la pista (origen en x -4, z 12): cruza los escalones
## sueltos de 10, 20 y 30 cm, choca contra el de 40 hasta que se le acaba el
## tiempo, y sube y baja las dos escaleras, la sin rampa y la con rampa. Cada
## punto es [x, z, ticks como máximo para llegar].
const STEPS_ROUTE := [
	[-4.0, 10.5, 300], [-4.0, 15.0, 240], [-6.5, 15.0, 240], [-6.5, 10.5, 240],
	[-9.0, 10.5, 240], [-9.0, 15.0, 240], [-9.0, 10.5, 240], [-11.5, 10.5, 240],
	[-11.5, 15.0, 90], [-15.25, 10.5, 240], [-15.25, 15.5, 240], [-15.25, 10.5, 240],
	[-18.25, 10.5, 240], [-18.25, 15.5, 240], [-18.25, 10.5, 240],
]


func _steps_input(tick: int) -> ActorInput:
	if not is_instance_valid(_local_actor) or _steps_index >= STEPS_ROUTE.size():
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	var me := BaseRegistry.world_position(_local_actor.state)
	_steps_max_height = maxf(_steps_max_height, me.y)
	var point: Array = STEPS_ROUTE[_steps_index]
	var to := Vector2(point[0] - me.x, point[1] - me.z)
	_steps_since += 1
	if to.length() < 0.3 or _steps_since > point[2]:
		_steps_index += 1
		_steps_since = 0
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	return ActorInput.make(tick, Vector2(to.x, -to.y).limit_length(1.0), 0.0, 0, 0)


## Prueba de postura en el túnel largo (techo a 1,2 m, de z 14 a z 24): se
## alinea con la entrada, corre y se agacha a 3 m para deslizarse adentro,
## suelta agacharse mientras se desliza, sale caminando por la otra punta (se
## tiene que parar solo al salir) y vuelve agachado por adentro.
func _tunnel_input(tick: int) -> ActorInput:
	if not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	var s := _local_actor.state
	var me := BaseRegistry.world_position(s)
	if s.stance == ActorState.Stance.STANDING and absf(me.x) < 2.35 and me.z > 13.65 and me.z < 24.35:
		_tunnel_standing_under_roof += 1
	var target := me
	var buttons := 0
	var phase := _tunnel_phase
	match _tunnel_phase:
		0:
			target = Vector3(0.0, 0.0, 9.0)
			if Vector2(me.x, me.z - 9.0).length() < 0.2 and _horizontal(s) < 0.5:
				_tunnel_phase = 1
		1:
			target = Vector3(0.0, 0.0, 30.0)
			buttons |= ActorInput.BUTTON_RUN
			if me.z > 11.0:
				buttons |= ActorInput.BUTTON_CROUCH
			if s.mode == ActorState.Mode.SLIDE:
				_tunnel_phase = 2
		2:
			if s.mode != ActorState.Mode.SLIDE:
				_tunnel_phase = 3
		3:
			target = Vector3(0.0, 0.0, 27.0)
			if me.z > 26.5:
				_tunnel_phase = 4
		4:
			target = Vector3(0.0, 0.0, 11.0)
			buttons |= ActorInput.BUTTON_CROUCH
			if me.z < 12.0:
				_tunnel_phase = 5
	if phase != _tunnel_phase:
		print("[net_lab] túnel: tramo %d en z=%.2f, %s" % [_tunnel_phase, me.z, s.describe()])
	var to := Vector2(target.x - me.x, target.z - me.z)
	var move := Vector2(to.x, -to.y).limit_length(1.0) if to.length() > 0.15 else Vector2.ZERO
	return ActorInput.make(tick, move, 0.0, buttons, 0)


## Prueba de agacharse en el aire frente a la pared de medidas: llega frente a
## la pared, salta parado 20 ticks después y se agacha a los 10 ticks del salto.
func _crouch_jump_input(tick: int) -> ActorInput:
	if not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	var me := BaseRegistry.world_position(_local_actor.state)
	if _crouch_jump_start < 0:
		var to := Vector2(-6.0 - me.x, 5.9 - me.z)
		if to.length() > 0.1 or _horizontal(_local_actor.state) > 0.1:
			var move := Vector2(to.x, -to.y).limit_length(1.0) if to.length() > 0.1 else Vector2.ZERO
			return ActorInput.make(tick, move, 0.0, 0, 0)
		_crouch_jump_start = _local_ticks
	var elapsed := _local_ticks - _crouch_jump_start
	var buttons := ActorInput.BUTTON_CROUCH if elapsed >= 30 else 0
	var state := _local_actor.state
	if elapsed == 20 or elapsed == 30:
		print("[net_lab] salto agachado: tick %d, %s" % [tick, "salta" if elapsed == 20 else "se agacha (pies antes: %.3f)" % me.y])
	if elapsed == 31:
		print("[net_lab] salto agachado: tick %d, postura %s, pies %.3f, cabeza %.3f" % [
			tick, ActorState.Stance.keys()[state.stance], me.y, me.y + _local_actor.stance_height(state.stance)])
	return ActorInput.make(tick, Vector2.ZERO, 0.0, buttons, 1 if elapsed >= 20 else 0)


## Prueba de escalera: va al pie de la escalera de la torre, se agarra
## caminando hacia ella y sube y baja entre 0,5 y 2 m. Si la suelta (un
## empujón fuerte), vuelve. Con `to_top`, sube hasta arriba, sale al techo de
## la torre y se queda ahí.
func _ladder_input(tick: int, to_top: bool) -> ActorInput:
	var ladder := Ladder.find(1)
	if ladder == null or not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	var s := _local_actor.state
	var facing := atan2(ladder.outward().x, ladder.outward().z)
	if s.mode == ActorState.Mode.LADDER:
		if to_top:
			if s.anchor_t >= ladder.height - 0.01:
				_ladder_top_done = true
			return ActorInput.make(tick, Vector2(0, 1), facing, 0, 0)
		if s.anchor_t >= 2.0:
			_ladder_direction = -1.0
		elif s.anchor_t <= 0.5:
			_ladder_direction = 1.0
		return ActorInput.make(tick, Vector2(0, _ladder_direction), facing, 0, 0)
	if to_top and _ladder_top_done:
		return ActorInput.make(tick, Vector2.ZERO, facing, 0, 0)
	var me := BaseRegistry.world_position(s)
	var local := ladder.global_transform.affine_inverse() * me
	if absf(local.x) < 0.3 and local.z < 1.8 and local.y < 0.5:
		# Alineado delante de la escalera: camina hacia ella hasta agarrarse.
		return ActorInput.make(tick, Vector2(0, 1), facing, 0, 0)
	var foot := ladder.pose_at(0.0) + ladder.outward() * 1.2
	var to := Vector2(foot.x - me.x, foot.z - me.z)
	return ActorInput.make(tick, Vector2(to.x, -to.y).limit_length(1.0), 0.0, 0, 0)


## Prueba de Hanging, en ciclos, contra la cara de un bloque de 2 m de la pista
## de bordes (o el de una base, si se pide su id): se aleja 2,2 m de la cara,
## corre hacia ella, salta y se agarra. Colgado se mueve a la derecha y
## a la izquierda y después, según la vuelta: salta para arriba mirando a la
## pared, aprieta W en la punta del salto para quedar arriba del borde (el
## bloque tiene 1 m de fondo) y se baja por delante; se suelta con Ctrl; o salta
## hacia atrás.
func _hang_input(tick: int, base_id: int) -> ActorInput:
	if not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _hang_presses)
	var face := Vector3(13.5, 0.0, -10.0)
	if base_id != 0:
		var base = BaseRegistry.find(base_id)
		if base == null:
			return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _hang_presses)
		face = base.base_origin() + Vector3(0.0, -1.0, 0.5)
	var s := _local_actor.state
	var me := BaseRegistry.world_position(s)
	_hang_since += 1
	var move := Vector2.ZERO
	var yaw := 0.0
	var buttons := 0
	match _hang_phase:
		0:  # a 2,2 m de la cara: primero en x y después en z, para rodear el muro
			var to := Vector2(face.x - me.x, face.z + 2.2 - me.z)
			if to.length() < 0.3 and s.mode == ActorState.Mode.GROUND:
				_hang_phase = 1
			elif absf(to.x) > 0.3:
				move = Vector2(signf(to.x), 0.0)
			else:
				move = Vector2(to.x, -to.y).limit_length(1.0)
		1:  # corre hacia la cara y salta a 1,3 m
			move = Vector2(0, 1)
			if me.z - face.z < 1.3:
				_hang_presses = (_hang_presses + 1) & 0xFF
				_hang_phase = 2
				_hang_since = 0
		2:  # en el aire, hacia la pared
			move = Vector2(0, 1)
			if s.mode == ActorState.Mode.HANGING:
				hang_grabs += 1
				_hang_phase = 3
				_hang_since = 0
			elif s.mode == ActorState.Mode.GROUND and _hang_since > 20:
				_hang_phase = 0
		3:  # colgado
			if s.mode != ActorState.Mode.HANGING:
				_hang_phase = 4 if _hang_cycle % 3 == 0 and _hang_since > 90 else 0
			elif _hang_since < 20:
				pass
			elif _hang_since < 50:
				move = Vector2(1, 0)
			elif _hang_since < 80:
				move = Vector2(-1, 0)
			elif _hang_since == 90:
				match _hang_cycle % 3:
					0:
						_hang_presses = (_hang_presses + 1) & 0xFF
					2:
						yaw = PI
						_hang_presses = (_hang_presses + 1) & 0xFF
			elif _hang_since >= 90 and _hang_since < 95 and _hang_cycle % 3 == 1:
				buttons = ActorInput.BUTTON_CROUCH
			elif _hang_since > 200:
				_hang_phase = 0
			if _hang_phase != 3:
				_hang_cycle += 1
				_hang_since = 0
		4:  # saltó para arriba: W hacia la pared recién cuando deja de subir, y arriba se baja por delante
			if s.mode == ActorState.Mode.GROUND and me.y > face.y + 1.5:
				if _hang_since < 1000:
					hang_climbs += 1
					_hang_since = 1000
				yaw = PI
				move = Vector2(0, 1)
			elif _hang_since >= 1000:
				if s.mode == ActorState.Mode.GROUND:
					_hang_phase = 0
			elif s.mode == ActorState.Mode.HANGING:
				_hang_phase = 3  # no llegó arriba y se volvió a agarrar
				_hang_since = 0
			elif s.mode == ActorState.Mode.GROUND:
				_hang_phase = 0  # no llegó arriba y cayó: vuelve a empezar
			elif s.velocity.y <= 0.0:
				move = Vector2(0, 1)
	return ActorInput.make(tick, move, yaw, buttons, _hang_presses)


## Pruebas de colgarse de un compañero. El muro alto está en la pista de bordes
## (fila 3): cara en z = -26, de x = 10,5 a 16,5, 3,6 m de alto, con un cajón
## de 0,6 m delante de su punta izquierda. Se llega por el pasillo entre los
## bloques de las filas 1 y 2, en x = 11,75.
const HOOK_WALL_FACE_Z := -26.0
const HOOK_WALL_RIGHT_X := 16.5
const HOOK_WALL_TOP := 3.6
const HOOK_BOX_X := 11.1
const HOOK_MIDDLE_X := 13.5
const HOOK_CORRIDOR_X := 11.75
## Cuántos ticks se queda colgado del compañero antes de soltarse o saltar, y
## cuántos sostiene el de arriba antes de soltarse con `hookwall:drop`.
const HOOK_HOLD_TICKS := 60
const HOOK_DROP_TICKS := 120
var _hook_loaded_ticks := 0


## Prueba `hookwall`: llega delante del cajón, se sube saltando, salta desde
## el cajón y se agarra del muro alto subiendo, y se corre colgado hasta el
## medio, donde se queda para que otro se cuelgue de él. Con `drop`, se suelta
## HOOK_DROP_TICKS después de que alguien se colgó de él (se caen los dos) y
## vuelve a empezar.
func _hook_wall_input(tick: int, drop: bool) -> ActorInput:
	if not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _hook_presses)
	var s := _local_actor.state
	var me := BaseRegistry.world_position(s)
	_hook_since += 1
	var move := Vector2.ZERO
	var buttons := 0
	match _hook_phase:
		0:  # delante del cajón
			var target := Vector3(HOOK_BOX_X, 0.0, -23.6)
			move = _wall_route(me, target)
			if Vector2(me.x - target.x, me.z - target.z).length() < 0.3 and s.mode == ActorState.Mode.GROUND:
				_set_hook_phase(1)
		1:  # camina hacia el cajón y salta para subirse
			move = Vector2(0, 1)
			if me.z < -24.2:
				_hook_presses = (_hook_presses + 1) & 0xFF
				_set_hook_phase(2)
		2:  # arriba del cajón, contra el muro: salta y se agarra subiendo
			move = Vector2(0, 1)
			if s.mode == ActorState.Mode.HANGING:
				_set_hook_phase(3)
			elif s.mode == ActorState.Mode.GROUND and me.y > 0.4 and _hook_since > 15:
				_hook_presses = (_hook_presses + 1) & 0xFF
				_hook_since = 0
			elif s.mode == ActorState.Mode.GROUND and me.y < 0.3 and _hook_since > 30:
				_set_hook_phase(0)
		3:  # colgado: se corre hasta el medio y se queda
			if s.mode != ActorState.Mode.HANGING:
				_set_hook_phase(0)
			elif me.x < HOOK_MIDDLE_X - 0.02:
				move = Vector2(1, 0)
			elif s.hooked_by != 0 and test_quit_hooked > 0:
				_hook_loaded_ticks += 1
				if _hook_loaded_ticks == test_quit_hooked:
					_quit_while_hooked()
			elif drop and s.hooked_by != 0:
				_hook_loaded_ticks += 1
				if _hook_loaded_ticks >= HOOK_DROP_TICKS:
					buttons = ActorInput.BUTTON_CROUCH
					if _hook_loaded_ticks == HOOK_DROP_TICKS:
						hook_drops += 1
			else:
				_hook_loaded_ticks = 0
	return ActorInput.make(tick, move, 0.0, buttons, _hook_presses)


## Prueba `ladderhold`: sube la escalera de la torre hasta 1,5 m y se queda.
func _ladder_hold_input(tick: int) -> ActorInput:
	var ladder := Ladder.find(1)
	if ladder == null or not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	var s := _local_actor.state
	var facing := atan2(ladder.outward().x, ladder.outward().z)
	if s.mode == ActorState.Mode.LADDER:
		var side := 0.0
		if s.anchor_t < 1.49:
			side = 1.0
		elif s.anchor_t > 1.51:
			side = -1.0
		return ActorInput.make(tick, Vector2(0, side), facing, 0, 0)
	var me := BaseRegistry.world_position(s)
	var local := ladder.global_transform.affine_inverse() * me
	if absf(local.x) < 0.3 and local.z < 1.8 and local.y < 0.5:
		return ActorInput.make(tick, Vector2(0, 1), facing, 0, 0)
	var foot := ladder.pose_at(0.0) + ladder.outward() * 1.2
	return ActorInput.make(tick, _walk_to(me, foot), 0.0, 0, 0)


## Prueba `hook:wall` o `hook:ladder`, en ciclos: espera delante del muro alto
## (o de la escalera de la torre) a que haya un compañero agarrado ahí, corre
## hacia él, salta y se cuelga de su cintura. Colgado HOOK_HOLD_TICKS, por
## turnos: se suelta con Ctrl; salta para arriba mirando a la pared (aprieta W
## al caer, se agarra del borde y desde ahí salta y sube arriba); o salta hacia
## atrás. Después vuelve.
func _hook_input(tick: int, where: String) -> ActorInput:
	if not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _hook_presses)
	var wall := where == "wall"
	# Mirando a la pared: en el muro alto, hacia -z; en la torre, hacia +z.
	var to_wall := 0.0 if wall else PI
	# En la escalera salta antes: si llega a 0,9 m de ella sin haber alcanzado
	# la cintura del compañero, se agarra de la escalera.
	var spot := Vector3(HOOK_MIDDLE_X, 0.0, -23.8) if wall else Vector3(8.0, 0.0, 9.9)
	var top := HOOK_WALL_TOP - 0.6 if wall else 2.0
	var s := _local_actor.state
	var me := BaseRegistry.world_position(s)
	_hook_since += 1
	var move := Vector2.ZERO
	var yaw := 0.0
	var buttons := 0
	match _hook_phase:
		0:  # en el lugar, espera al compañero
			move = _wall_route(me, spot) if wall else _tower_route(me, spot)
			if Vector2(me.x - spot.x, me.z - spot.z).length() < 0.3 and s.mode == ActorState.Mode.GROUND \
					and _hook_mate_ready(spot):
				_set_hook_phase(1)
		1:  # corre hacia la pared y salta
			move = Vector2(0, 1)
			yaw = to_wall
			if (wall and me.z < -24.0) or (not wall and me.z > 10.45):
				_hook_presses = (_hook_presses + 1) & 0xFF
				_set_hook_phase(2)
		2:  # en el aire, hacia la pared
			move = Vector2(0, 1)
			yaw = to_wall
			if s.mode == ActorState.Mode.HOOKED:
				hook_grabs += 1
				_set_hook_phase(3)
			elif s.mode == ActorState.Mode.LADDER or s.mode == ActorState.Mode.HANGING:
				# Se agarró de otra cosa (la escalera o un borde): se baja.
				hook_other_grabs += 1
				_set_hook_phase(6)
			elif s.mode == ActorState.Mode.GROUND and _hook_since > 20:
				_set_hook_phase(0)
		3:  # colgado del compañero
			yaw = to_wall
			if s.mode != ActorState.Mode.HOOKED:
				if _hook_since <= HOOK_HOLD_TICKS:
					hook_fell_with_mate += 1
					var mates := _local_actor.teammates()
					print("[net_lab] compañero: se cayó con él en el tick %d, %d ticks después de colgarse (%s)" % [
						tick, _hook_since, mates[0].state.describe() if not mates.is_empty() else "el compañero ya no está"])
				_set_hook_phase(4 if _hook_cycle % 3 == 1 and _hook_since > HOOK_HOLD_TICKS else 5)
			elif test_quit_hooked > 0:
				if _hook_since == test_quit_hooked:
					_quit_while_hooked()
			elif _hook_since == HOOK_HOLD_TICKS:
				match _hook_cycle % 3:
					0:
						hook_releases += 1
					1:
						hook_jumps_up += 1
						_hook_presses = (_hook_presses + 1) & 0xFF
					2:
						hook_jumps_away += 1
						yaw = to_wall + PI
						_hook_presses = (_hook_presses + 1) & 0xFF
			if _hook_cycle % 3 == 0 and _hook_since >= HOOK_HOLD_TICKS:
				buttons = ActorInput.BUTTON_CROUCH
		4:  # saltó para arriba: W al caer, se agarra del borde y desde ahí sube
			yaw = to_wall
			if s.mode == ActorState.Mode.HANGING:
				if _hook_since < 1000:
					hook_edges_after += 1
					_hook_since = 1000
				elif _hook_since == 1020:
					_hook_presses = (_hook_presses + 1) & 0xFF
			elif s.mode == ActorState.Mode.GROUND:
				if me.y > top:
					hook_tops += 1
				_set_hook_phase(5)
			elif s.velocity.y <= 0.0:
				move = Vector2(0, 1)
		5:  # vuelve al lugar
			_hook_cycle += 1
			_set_hook_phase(0)
		6:  # se agarró de otra cosa: de la escalera baja alejándose; de un borde, se suelta
			yaw = to_wall
			if s.mode == ActorState.Mode.LADDER:
				move = Vector2(0, -1)
			elif s.mode == ActorState.Mode.HANGING:
				buttons = ActorInput.BUTTON_CROUCH
			elif s.mode == ActorState.Mode.GROUND:
				_set_hook_phase(5)
	return ActorInput.make(tick, move, yaw, buttons, _hook_presses)


## Prueba de desconexión con alguien colgado: imprime el estado y cierra el
## juego sin despedirse, como si se cortara.
func _quit_while_hooked() -> void:
	print("[net_lab] desconexión de prueba en el tick %d: %s" % [_clock.tick, _local_actor.state.describe()])
	get_tree().quit()


func _set_hook_phase(phase: int) -> void:
	_hook_phase = phase
	_hook_since = 0
	_hook_loaded_ticks = 0


## Si hay un compañero agarrado frente al lugar, sin nadie colgado de él.
func _hook_mate_ready(spot: Vector3) -> bool:
	for mate in _local_actor.teammates():
		var holding := mate.state.mode == ActorState.Mode.HANGING or mate.state.mode == ActorState.Mode.LADDER
		if holding and mate.state.hooked_by == 0 and absf(mate.global_position.x - spot.x) < 0.3:
			return true
	return false


## Camino hasta un punto delante del muro alto. Desde donde se aparece, por el
## pasillo entre los bloques; desde arriba del muro, se baja por atrás; desde
## atrás, lo rodea por la derecha.
func _wall_route(me: Vector3, target: Vector3) -> Vector2:
	if me.y > HOOK_WALL_TOP - 0.3:
		return _walk_to(me, Vector3(me.x, 0.0, me.z - 3.0))
	if me.z < HOOK_WALL_FACE_Z - 0.6:
		if me.x < HOOK_WALL_RIGHT_X + 1.0:
			return _walk_to(me, Vector3(HOOK_WALL_RIGHT_X + 1.4, 0.0, me.z))
		return _walk_to(me, Vector3(me.x, 0.0, -23.0))
	if me.z > -20.5:
		if absf(me.x - HOOK_CORRIDOR_X) > 0.3:
			return _walk_to(me, Vector3(HOOK_CORRIDOR_X, 0.0, me.z))
		return _walk_to(me, Vector3(HOOK_CORRIDOR_X, 0.0, -21.0))
	return _walk_to(me, target)


## Camino hasta un punto delante de la escalera de la torre. Desde arriba de la
## torre, se baja por atrás; desde atrás o el costado, la rodea por la derecha.
func _tower_route(me: Vector3, target: Vector3) -> Vector2:
	if me.y > 2.0:
		return _walk_to(me, Vector3(me.x, 0.0, me.z + 3.0))
	if me.z > 12.0 and me.x < 10.5:
		return _walk_to(me, Vector3(10.9, 0.0, me.z))
	if me.z > 11.0:
		return _walk_to(me, Vector3(10.5, 0.0, 10.0))
	return _walk_to(me, target)


## Input de movimiento hacia un punto, con la cámara mirando hacia -z.
static func _walk_to(me: Vector3, target: Vector3) -> Vector2:
	var to := Vector2(target.x - me.x, target.z - me.z)
	return Vector2(to.x, -to.y).limit_length(1.0) if to.length() > 0.15 else Vector2.ZERO


static func _horizontal(state: ActorState) -> float:
	return Vector2(state.velocity.x, state.velocity.z).length()


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
	if role == Role.HOST:
		for request in _push_requests:
			_push_others(request[0], request[1])
		_push_requests.clear()
		_apply_host_events(tick)
	if role != Role.CLIENT:
		_update_hooks()
	if role != Role.CLIENT or not _clock.client_sync:
		return
	_take_scheduled_events(tick)
	_net_sync.apply_pending_snapshot(_on_own_state.bind(tick), _interpolation.add, _interpolation.add_base)
	_interpolation.advance()
	_update_platform_lag(tick)
	for actor in _clock.sorted_actors():
		if _is_remote(actor):
			_interpolation.place(actor)
	if is_instance_valid(_local_actor) and _clock.synced:
		_current_input = _local_input(tick)
		# Cambio de línea: colgado de un compañero, el actor propio no se
		# predice. Entra cuando su propio paso lo colgó (o una repetición); sale
		# cuando el host dice que ya no cuelga (_on_own_state).
		var hooked := _local_actor.state.mode == ActorState.Mode.HOOKED
		if hooked and not _hooked_line:
			_hooked_line = true
			_hooked_since = tick - 1
			line_changes += 1
		_local_actor.simulated = not _hooked_line
		if _hooked_line:
			_show_hooked_local()
		else:
			_apply_client_events(_local_actor.state, tick)


## Al terminar cada tick. Host: decide qué afirmaciones adopta y después manda
## el snapshot. Cliente: guarda lo predicho y se lo manda al host con el input.
func _on_tick_finished(tick: int) -> void:
	if role == Role.LOCAL and tick == test_pause_tick:
		_set_paused(true)
		print("[net_lab] pausa en el tick %d: %s" % [tick, _local_actor.state.describe() if is_instance_valid(_local_actor) else "sin actor"])
	if role == Role.HOST:
		for actor in _clock.sorted_actors():
			if _is_remote(actor):
				_adoption.consider(actor, _net_sync.claim_for(actor.owner_peer_id, tick), tuning)
		var rafts := BaseRegistry.all().filter(func(base) -> bool: return base is HostRaft and base.simulated)
		_net_sync.send_snapshot(tick, _clock.sorted_actors(), rafts)
	elif role == Role.CLIENT and is_instance_valid(_local_actor) and (_local_actor.simulated or _hooked_line) \
			and _current_input != null and _current_input.tick == tick:
		if test_perturb_mm > 0.0 and _local_actor.simulated:
			_perturb(_local_actor)
		# Colgado de un compañero, el tick no se predijo: viaja el input sin afirmación.
		_prediction.record(tick, _current_input, _local_actor.state if _local_actor.simulated else null)
		_net_sync.send_ticks(_prediction.recent(NetSync.INPUT_REDUNDANCY), _clock.rtt_ms)
	if role == Role.CLIENT:
		# La balsa del host se coloca para el tick que viene, en la pose que se
		# va a mostrar entonces: un tick del cliente son 60/ritmo ticks del host.
		_interpolation.place_bases(float(SimClock.TICK_RATE) / _clock.rate_hz)
		_measure_remote_smoothness()
	_measure_hooked_gap()


## Cliente: cuánto más atrás se dibuja cada plataforma guionada. El actor
## propio la necesita en su tick, que va por delante del host; los demás
## jugadores se ven en el pasado. Lejos del actor propio se la dibuja en ese
## mismo pasado, así quien se sube o se baja se ve donde corresponde.
func _update_platform_lag(tick: int) -> void:
	var shown := _interpolation.shown_tick()
	var gap := maxf(float(tick) - shown, 0.0) if shown >= 0.0 else 0.0
	for base in BaseRegistry.all():
		if not (base is ScriptedPlatform):
			continue
		var near := 1.0
		if is_instance_valid(_local_actor) and _local_actor.state.base_id != base.base_id:
			var distance: float = base.distance_to(BaseRegistry.world_position(_local_actor.state))
			near = 1.0 - smoothstep(PLATFORM_NEAR, PLATFORM_FAR, distance)
		base.visual_lag = gap * (1.0 - near)


## Cliente: mide, tick a tick, si los demás jugadores se mueven parejo en pantalla.
func _measure_remote_smoothness() -> void:
	for actor in _clock.sorted_actors():
		if not _is_remote(actor):
			continue
		var peer := actor.owner_peer_id
		var seen := actor.seen_position()
		var last: Variant = _remote_last_positions.get(peer)
		_remote_last_positions[peer] = seen
		# Lo que se ve es el movimiento en el mundo: sobre una base, el propio
		# más el de la base.
		var velocity := actor.state.velocity + BaseRegistry.visual_velocity(actor.state.base_id)
		var speed := Vector2(velocity.x, velocity.z).length()
		if last == null or speed < 1.0:
			continue
		var expected := speed / _clock.rate_hz
		var moved := Vector2(seen.x - last.x, seen.z - last.z).length()
		remote_ticks_measured += 1
		if moved < expected * 0.25 or moved > expected * 2.0:
			remote_stutters += 1


## Cuánto se separa en pantalla quien se ve colgado de este jugador de la pose
## que le daría el cuerpo de este jugador tal como se lo ve acá. En el host es
## cero: los dos están en el presente. En un cliente, el propio va adelantado y
## el otro se ve en el pasado: mientras el de arriba está quieto da lo mismo,
## pero si se suelta, cae enseguida y al de abajo se lo sigue viendo colgado.
func _measure_hooked_gap() -> void:
	if not is_instance_valid(_local_actor):
		return
	for actor in _clock.sorted_actors():
		if actor == _local_actor or actor.state.mode != ActorState.Mode.HOOKED \
				or actor.state.anchor_id != _local_actor.owner_peer_id:
			continue
		var expected := ActorMotor.hook_pose(_local_actor, tuning)
		hooked_gap_max = maxf(hooked_gap_max, actor.global_position.distance_to(expected))


## Host: empuja a los demás actores, hacia arriba y lejos del propio, con una
## fuerza de 0 a 5 contra el agarre del modo en que estén.
##
## Inmediato: se aplica en este tick; cada cliente se entera con el snapshot y
## se corrige. Programado: se fija para un tick que el cliente todavía no
## simuló (lo que tarda su input en llegar, más la ida y vuelta, más un
## colchón) y se le anuncia ya, por el canal confiable; el cliente lo aplica
## en ese mismo tick y no recibe corrección. En los dos casos el host sube la
## época del empujado en el tick en que lo aplica, así no adopta afirmaciones
## de ticks en que el cliente no sabía del empujón.
func _push_others(scheduled: bool, force: int) -> void:
	for actor in _clock.sorted_actors():
		if not _is_remote(actor):
			continue
		var away := Vector3.BACK
		if is_instance_valid(_local_actor):
			var offset := BaseRegistry.world_position(actor.state) - BaseRegistry.world_position(_local_actor.state)
			offset.y = 0.0
			if offset.length_squared() > 0.0001:
				away = offset.normalized()
		var impulse := NetSync.quantize_impulse(away * PUSH_AWAY_SPEED + Vector3.UP * PUSH_UP_SPEED)
		if not scheduled:
			_log_push(actor, force, "inmediato")
			ActorMotor.apply_impulse(actor.state, impulse, force, tuning)
			actor.state.epoch += 1
			continue
		var peer := actor.owner_peer_id
		var margin := maxi(_net_sync.input_margin_ticks(peer, _clock.tick), 0)
		var rtt_ticks := ceili(_net_sync.peer_rtt_ms(peer) * SimClock.TICK_RATE / 1000.0)
		var at := _clock.tick + margin + rtt_ticks + SCHEDULE_BUFFER_TICKS
		if test_schedule_ticks > 0:
			at = _clock.tick + test_schedule_ticks
		_host_events.append([at, peer, impulse, force])
		_net_sync.send_scheduled_event(peer, at, impulse, force)
	if scheduled:
		scheduled_pushes += 1
	else:
		pushes += 1
	print("[net_lab] empujón %s de fuerza %d en el tick %d" % ["programado" if scheduled else "inmediato", force, _clock.tick])


## Host: aplica los empujones programados que tocan en este tick, igual que
## los aplica el empujado en su predicción. Sube su época.
func _apply_host_events(tick: int) -> void:
	var waiting: Array = []
	for event in _host_events:
		if event[0] > tick:
			waiting.append(event)
			continue
		for actor in _clock.sorted_actors():
			if actor.owner_peer_id == event[1]:
				_log_push(actor, event[3], "programado")
				ActorMotor.apply_impulse(actor.state, event[2], event[3], tuning)
				actor.state.epoch += 1
	_host_events = waiting


## Prueba: a quién agarró un empujón que estaba colgado de un compañero o
## con un compañero colgado.
func _log_push(actor: ActorBody, force: int, kind: String) -> void:
	var s := actor.state
	if s.mode == ActorState.Mode.HOOKED or s.hooked_by != 0:
		print("[net_lab] empujón %s de fuerza %d al jugador %d, %s" % [kind, force, actor.owner_peer_id,
				"colgado de un compañero" if s.mode == ActorState.Mode.HOOKED else "con un compañero colgado de él (%s)" % ActorState.Mode.keys()[s.mode]])


## Cliente: toma los empujones programados que anunció el host y los anota
## para su tick. Si su tick ya se predijo (llegó tarde), repite desde ahí con
## el empujón; si ya ni eso se puede, lo arregla la corrección del snapshot.
func _take_scheduled_events(tick: int) -> void:
	for event in _net_sync.received_events:
		var at: int = event[0]
		_client_events.get_or_add(at, []).append([event[1], event[2]])
		if at >= tick or not is_instance_valid(_local_actor) or not _local_actor.simulated:
			events_on_time += 1
		elif _prediction.replay_from(_local_actor, at, tick, _step_local):
			events_late += 1
		else:
			events_too_late += 1
	_net_sync.received_events.clear()
	for at in _client_events.keys():
		if at < tick - 600:
			_client_events.erase(at)


## Cliente: aplica a un estado los empujones programados de un tick, como el
## host. Va antes del paso de ese tick, también al repetir ticks.
func _apply_client_events(state: ActorState, tick: int) -> void:
	for event in _client_events.get(tick, []):
		ActorMotor.apply_impulse(state, event[0], event[1], tuning)
		state.epoch += 1


## Host o modo local: quien cayó del mapa reaparece en su lugar, quieto y
## apoyado. Es un evento del host (sube la época) y un teleport.
func _respawn_fallen() -> void:
	for actor in _clock.sorted_actors():
		if BaseRegistry.world_position(actor.state).y > FALL_LIMIT:
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
	if not _local_actor.simulated and not _hooked_line:
		# Todavía sin predicción: se muestra tal cual lo manda el host.
		_local_actor.state = ActorState.from_bytes(state_bytes)
		_local_actor.global_position = BaseRegistry.world_position(_local_actor.state)
		_local_actor.present(_local_actor.state)
		return
	var host_state := ActorState.from_bytes(state_bytes)
	if _hooked_line:
		# Colgado de un compañero: lo de antes de colgarse ya no importa.
		if host_tick < _hooked_since:
			return
		_prediction.forget_up_to(host_tick)
		if host_state.mode == ActorState.Mode.HOOKED:
			_local_actor.state = host_state
			return
		# El host dice que ya no cuelga: se vuelve a predecir desde su estado,
		# repitiendo los inputs guardados, y lo que se ve pasa a la pose
		# predicha en 0,2 s.
		var seen := _local_actor.seen_position()
		_prediction.resume(_local_actor, host_tick, state_bytes, current_tick, _step_local)
		_hooked_line = false
		_local_actor.simulated = true
		line_jump_out_max = maxf(line_jump_out_max, seen.distance_to(_local_actor.global_position))
		_local_actor.blend_line_from(seen)
		line_changes += 1
		return
	if host_state.mode == ActorState.Mode.HOOKED:
		# El host lo colgó de un compañero y acá no se había predicho: pasa a la
		# línea del host. La mezcla se hace cuando el cuerpo ya está en la pose.
		_line_blend_from = _local_actor.seen_position()
		_local_actor.state = host_state
		_hooked_line = true
		_hooked_since = host_tick
		_local_actor.simulated = false
		_prediction.forget_up_to(host_tick)
		line_changes += 1
		return
	_prediction.reconcile(_local_actor, host_tick, state_bytes, used_input_tick, current_tick, _step_local)


## Repite o predice un tick del actor propio. Colgado de un compañero no se
## predice (cambio de línea): devuelve falso y no lo simula.
func _step_local(input: ActorInput) -> bool:
	if _local_actor.state.mode == ActorState.Mode.HOOKED:
		return false
	_apply_client_events(_local_actor.state, input.tick)
	ActorMotor.step(_local_actor, _local_actor.state, input, tuning, SimClock.TICK_DT)
	return true


## Cliente, colgado de un compañero: el cuerpo va a la pose que da el
## compañero tal como se lo ve acá (en el pasado, interpolado), así los dos se
## ven juntos. El estado es el último que mandó el host.
func _show_hooked_local() -> void:
	var mate := _local_actor.teammate(_local_actor.state.anchor_id)
	# Al entrar a la línea, cuánto salta el cuerpo: si se colgó en su propio
	# paso, de la pose que predijo a la que da el compañero visto acá; si lo
	# colgó el host, de lo que se veía a esa pose.
	var entering := _line_blend_from != null or _hooked_since == _clock.tick - 1
	var before: Vector3 = _line_blend_from if _line_blend_from != null else _local_actor.global_position
	if mate != null:
		_local_actor.global_position = ActorMotor.hook_pose(mate, tuning)
	if entering:
		line_jump_in_max = maxf(line_jump_in_max, before.distance_to(_local_actor.global_position))
	_local_actor.present(_local_actor.state)
	if _line_blend_from != null:
		_local_actor.blend_line_from(_line_blend_from)
		_line_blend_from = null
	_local_actor.decay_visual_offset(SimClock.TICK_DT)


## Host: quién cuelga de quién (ActorMotor.assign_hooks). Corre al empezar el
## tick, antes de mover a nadie.
func _update_hooks() -> void:
	var result := ActorMotor.assign_hooks(_clock.sorted_actors(), tuning)
	hook_events += result[0]
	hook_kicks += result[1]


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
		elif arg.begins_with("--test-scheduled-push-at="):
			for seconds in arg.trim_prefix("--test-scheduled-push-at=").split(","):
				test_scheduled_push_seconds.append(seconds.to_float())
		elif arg.begins_with("--test-push-force="):
			test_push_force = arg.trim_prefix("--test-push-force=").to_int()
		elif arg.begins_with("--test-schedule-ticks="):
			test_schedule_ticks = arg.trim_prefix("--test-schedule-ticks=").to_int()
		elif arg.begins_with("--test-perturb-mm="):
			test_perturb_mm = arg.trim_prefix("--test-perturb-mm=").to_float()
		elif arg.begins_with("--test-quit-hooked="):
			test_quit_hooked = arg.trim_prefix("--test-quit-hooked=").to_int()
		elif arg.begins_with("--test-pause-at="):
			test_pause_tick = arg.trim_prefix("--test-pause-at=").to_int()
		elif arg.begins_with("--test-spawn-at="):
			var xz := arg.trim_prefix("--test-spawn-at=").split(",")
			_session.host_spawn_override = Vector3(xz[0].to_float(), 0.0, xz[1].to_float())


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
		lines.append("línea: %s   ·   cambios de línea: %d" % [
				"la del host (colgado de un compañero, no se predice)" if _hooked_line else "predicha", line_changes])
		lines.append("snapshots que no llegaron a tiempo: %.1f %%" % _snapshot_loss_percent())
		lines.append("empujones programados: %d llegaron a tiempo, %d tarde (se repitió desde su tick), %d demasiado tarde" % [
				events_on_time, events_late, events_too_late])
		lines.append("los demás se ven %d ms en el pasado   ·   %d ticks esperando un snapshot   ·   tirones: %.1f %%" % [
			roundi(RemoteInterpolation.DELAY_TICKS * SimClock.TICK_DT * 1000.0), _interpolation.starved,
			100.0 * remote_stutters / maxi(remote_ticks_measured, 1),
		])
	if role == Role.HOST:
		lines.append("adopción: %s   ·   empujones: %d inmediatos, %d programados   ·   reapariciones: %d" % [
				"prendida" if _adoption.enabled else "apagada", pushes, scheduled_pushes, respawns])
		for actor in _clock.sorted_actors():
			if actor != _local_actor:
				var peer := actor.owner_peer_id
				lines.append("jugador %d: su input llega con %d ticks de anticipación   ·   época %d" % [peer, _net_sync.input_margin_ticks(peer, _clock.tick), actor.state.epoch])
				lines.append("      afirmaciones: %d adoptadas (la más lejana a %.2f m), rechazadas %d por época, %d por distancia, %d por pose   ·   %d sin adoptar porque colgaba de un compañero" % [
					_adoption.count(peer, ClaimAdoption.Result.ADOPTED), _adoption.max_difference(peer),
					_adoption.count(peer, ClaimAdoption.Result.WRONG_EPOCH), _adoption.count(peer, ClaimAdoption.Result.TOO_FAR),
					_adoption.count(peer, ClaimAdoption.Result.BAD_POSE), _adoption.count(peer, ClaimAdoption.Result.NOT_PREDICTED),
				])
	if is_instance_valid(_local_actor):
		var s := _local_actor.state
		if _clock.paused:
			lines.append("EN PAUSA (tick %d)   ·   G sigue   ·   F avanza un tick" % _clock.tick)
		lines.append("Modo: %s   ·   en suelo: %s   ·   época: %d" % [ActorState.Mode.keys()[s.mode], "sí" if s.on_floor else "no", s.epoch])
		var stance_names := ["parado", "agachado"]
		lines.append("Postura: %s%s" % [stance_names[s.stance],
				"   ·   pedida: %s (no hay lugar)" % stance_names[s.stance_wanted] if s.stance_wanted != s.stance else ""])
		if s.mode == ActorState.Mode.LADDER:
			lines.append("Escalera %d   ·   pies a %.2f m sobre su base" % [s.anchor_id, s.anchor_t])
		elif s.mode == ActorState.Mode.HANGING:
			lines.append("Colgado del borde: filo a %.2f m de altura%s" % [BaseRegistry.origin(s.anchor_id).y + s.anchor_point.y,
					"   ·   sobre la base %d" % s.anchor_id if s.anchor_id != 0 else ""])
		elif s.mode == ActorState.Mode.HOOKED:
			lines.append("Colgado de la cintura del jugador %d" % s.anchor_id)
		elif s.regrab_left > 0.0 and s.regrab_id == ActorState.REGRAB_EDGES:
			lines.append("Recién soltó un borde: no puede agarrar otro por %.2f s" % s.regrab_left)
		elif s.regrab_left > 0.0 and s.regrab_id == ActorState.REGRAB_TEAMMATES:
			lines.append("Recién se soltó de un compañero: no se puede colgar de otro por %.2f s" % s.regrab_left)
		elif s.regrab_left > 0.0:
			lines.append("Recién soltó la escalera %d: no la puede volver a agarrar por %.2f s" % [s.regrab_id, s.regrab_left])
		if s.hooked_by != 0:
			lines.append("El jugador %d cuelga de tu cintura: quedás quieto   ·   Ctrl te suelta y se caen los dos" % s.hooked_by)
		var world := BaseRegistry.world_position(s)
		var base = BaseRegistry.find(s.base_id)
		lines.append("Velocidad%s: %.2f m/s horizontal, %.2f m/s vertical" % [" (sobre la base)" if base != null else "", Vector2(s.velocity.x, s.velocity.z).length(), s.velocity.y])
		lines.append("Pies en (%.3f, %.3f, %.3f)   ·   cabeza a %.3f m de altura   ·   base: %s" % [
				world.x, world.y, world.z, world.y + _local_actor.stance_height(s.stance),
				"%s (%d)" % [base.name, s.base_id] if base != null else "ninguna"])
	lines.append("")
	lines.append("WASD mover · Espacio saltar · Shift correr · Ctrl agacharse (corriendo: deslizarse) · mouse mirar · Esc suelta el mouse")
	lines.append("Colgado: A y D de costado · Espacio mirando a la pared salta para arriba (con W pasás arriba), mirando a otro lado salta hacia allá · Ctrl se suelta")
	lines.append("Saltando hacia un compañero colgado de un borde o en una escalera, te colgás de su cintura: ahí Espacio y Ctrl andan igual que colgado")
	if role == Role.HOST:
		lines.append("E empuja a los demás ya · R los empuja programado · con Shift, empujón débil · Q prende o apaga la adopción")
	if role == Role.LOCAL:
		lines.append("G pausa y congela · F avanza un tick en pausa")
	lines.append("F12 guarda una captura en el Escritorio")
	if Time.get_ticks_msec() < _flash_until_msec:
		lines.insert(0, ">> %s" % _flash_text)
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
	if is_instance_valid(_local_actor):
		var s := _local_actor.state
		print("[net_lab] traza %.1fs actor: base=%d mundo=%s rel=%s vel=%s modo=%s postura=%s suelo=%s ancla=%d t=%.3f época=%d" % [
			(Time.get_ticks_msec() - _ready_msec) / 1000.0, s.base_id, BaseRegistry.world_position(s),
			s.position, s.velocity, ActorState.Mode.keys()[s.mode], ActorState.Stance.keys()[s.stance], s.on_floor,
			s.anchor_id, s.anchor_t, s.epoch,
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
		print("[net_lab] empujones programados: %d a tiempo, %d tarde (repetido desde su tick), %d demasiado tarde" % [
			events_on_time, events_late, events_too_late])
		print("[net_lab] los demás en pantalla: %d tirones en %d ticks medidos (%.1f %%), %d ticks esperando un snapshot" % [
			remote_stutters, remote_ticks_measured, 100.0 * remote_stutters / maxi(remote_ticks_measured, 1), _interpolation.starved,
		])
	if respawns > 0:
		print("[net_lab] reapariciones: %d" % respawns)
	if test_input == "tunnel":
		print("[net_lab] túnel: llegó al tramo %d; ticks parado bajo el techo: %d" % [_tunnel_phase, _tunnel_standing_under_roof])
	if test_input == "steps":
		print("[net_lab] escalones: punto %d de %d; pies a %.2f m como máximo" % [_steps_index, STEPS_ROUTE.size(), _steps_max_height])
	if test_input == "hang" or test_input.begins_with("hang:"):
		print("[net_lab] colgar: %d agarres, %d subidas al borde, %d vueltas del ciclo" % [hang_grabs, hang_climbs, _hang_cycle])
	if test_input.begins_with("hook:"):
		print("[net_lab] compañero: %d se colgó, %d se soltó con Ctrl, %d saltó para arriba (%d se agarró del borde después, %d llegó arriba), %d saltó hacia atrás, %d se cayó con el compañero, %d se agarró de otra cosa" % [
			hook_grabs, hook_releases, hook_jumps_up, hook_edges_after, hook_tops, hook_jumps_away, hook_fell_with_mate, hook_other_grabs])
	if test_input.begins_with("hookwall"):
		print("[net_lab] compañero de arriba: tramo %d, se soltó %d veces con alguien colgado" % [_hook_phase, hook_drops])
	if role != Role.CLIENT and (hook_events > 0 or hook_kicks > 0):
		print("[net_lab] host: %d cambios de quién cuelga de quién, %d soltados por colgarse dos del mismo" % [hook_events, hook_kicks])
	if hooked_gap_max > 0.0 or test_input.begins_with("hookwall") or test_input == "ladderhold":
		print("[net_lab] el que cuelga de este jugador se dibujó a %.3f m como máximo de la pose que le da el cuerpo de este jugador" % hooked_gap_max)
	if role == Role.CLIENT:
		print("[net_lab] cambio de línea: %d cambios, %d veces volvió a predecir; el cuerpo saltó %.3f m como máximo al entrar y %.3f m al salir (los reparte la mezcla de 0,2 s)" % [
			line_changes, _prediction.resumes, line_jump_in_max, line_jump_out_max])
		print("[net_lab] correcciones: la más grande de %.3f m" % _prediction.max_correction_meters)
	for peer in _adoption.peers():
		print("[net_lab] adopción del jugador %d: prendida=%s empujones=%d iguales=%d adoptadas=%d (máx %.3f m) rechazadas: época=%d distancia=%d pose=%d apagada=%d sin_afirmación=%d colgado_no_predicho=%d" % [
			peer, _adoption.enabled, pushes,
			_adoption.count(peer, ClaimAdoption.Result.SAME),
			_adoption.count(peer, ClaimAdoption.Result.ADOPTED), _adoption.max_difference(peer),
			_adoption.count(peer, ClaimAdoption.Result.WRONG_EPOCH),
			_adoption.count(peer, ClaimAdoption.Result.TOO_FAR),
			_adoption.count(peer, ClaimAdoption.Result.BAD_POSE),
			_adoption.count(peer, ClaimAdoption.Result.OFF),
			_adoption.count(peer, ClaimAdoption.Result.NO_CLAIM),
			_adoption.count(peer, ClaimAdoption.Result.NOT_PREDICTED),
		])
	get_tree().quit()


## Prueba de divergencia: corre el estado predicho y el cuerpo, al azar pero
## siempre igual para la misma semilla.
func _perturb(actor: ActorBody) -> void:
	if _perturb_rng.seed != sim_seed:
		_perturb_rng.seed = sim_seed
	var push := Vector3(_perturb_rng.randf_range(-1.0, 1.0), _perturb_rng.randf_range(-1.0, 1.0),
			_perturb_rng.randf_range(-1.0, 1.0)).normalized() * test_perturb_mm * 0.001
	actor.state.position += push
	actor.state.quantize()
	actor.global_position = BaseRegistry.world_position(actor.state)
