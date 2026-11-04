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
## host la adopta si es creíble. En el host, Y empuja a los demás jugadores (un
## evento del host, que sube su época) y Q prende o apaga la adopción. (Hasta
## el 2026-10-31 eran E y R; E pasó a interactuar, para el inventario.)
## Paso 8: los demás jugadores se ven interpolados unos 100 ms en el pasado,
## las correcciones del propio se suavizan y el host manda 30 snapshots por
## segundo. Quien cae del mapa reaparece en su lugar.
## Punto 6 de la validación: colgarse de la cintura de un compañero agarrado de
## un borde o de una escalera. El cliente predice su actor colgado, con la pose
## que da el compañero tal como lo ve: como el compañero queda quieto, da lo
## mismo que en el host, y soltarse o saltar responden al instante. Lo que haga
## el compañero (soltarse, que lo empujen, irse) llega como corrección.
## Punto 7: cámara lenta del mundo. La prende y la apaga cualquiera con el 1
## del teclado numérico (desde el 2026-11-02, cada uno pide la suya y va
## mientras alguno la pida); el host programa el tick en que empieza y el tick en
## que termina para todos con anticipación, como un empujón programado, y en
## esos ticks todas las máquinas cambian juntas de escala. Al que se conecta,
## el host le cuenta todos los tramos que hubo, también el que sigue prendido:
## las plataformas van por el tiempo del mundo. Los poderes van en el teclado
## numérico, como acciones del Mapa de entrada del proyecto. (Hubo también una
## cámara lenta personal, que el host les daba a los demás; se sacó el
## 2026-10-12: el usuario había pedido una sola.)
## Súper salto y velocidad: cada jugador lo prende y lo apaga para sí mismo
## con el 2 del teclado numérico. Viaja en el input como el salto: su PC lo
## predice al instante y el host hace la misma cuenta, sin eventos.
## Reconexión: si se corta la conexión, el cliente reintenta solo y el host
## deja su actor en el mundo, quieto, hasta que vuelve (ver NetSession). Al
## volver sigue donde estaba. Una copia con otro Tuning, otro código u otro
## nivel no entra: el host dice qué parte es distinta (SimFingerprint).
## Salud, estamina y estados (2026-11-02): cada jugador tiene salud (100
## puntos) y una reserva de estamina (200) que no vuelve sola. El súper y la
## cámara lenta pasan a ser estados de cada jugador (ActorPowers): gastan su
## estamina mientras están prendidos y se apagan juntos si se acaba. La cámara
## lenta del mundo va mientras al menos uno la pida (_follow_world_slow_holders):
## cada uno prende o suelta su pedido y paga el suyo. Los consumibles del
## inventario curan, dañan o devuelven estamina (ActorVitals); con la salud en
## cero hay una muerte de prueba. El HUD (Hud/Instrumentos) muestra la salud,
## la estamina, el termómetro y una luz por cada estado propio prendido.
## Inventario de grilla (2026-10-31): cada jugador tiene el suyo y las cajas de
## la zona de inventario se comparten. Lo valida el host (nodo Inventario,
## InvNet) y la interfaz es del jugador local (Hud/InventarioUI). Tab lo abre,
## E recoge o abre una caja y 1 a 9 y 0 son la barra rápida; por eso la
## simulación de internet pasó a Alt + 1 a 5.
##
## El rol se elige con el menú. Para pruebas automáticas también se puede pasar
## por argumentos: --local, --host o --client, --address=IP, --port=N,
## --bind=IP (solo host), --autoquit=SEGUNDOS (imprime un resumen y cierra),
## --report-after=SEGUNDOS (imprime el estado de cada actor), --trace (el
## cliente imprime su adelanto cada medio segundo), --test-input=walk (camina y
## salta solo, sin teclado), --test-input=zigzag (cambia de dirección cada
## medio segundo durante 25 s), --test-input=ride:ID (se sube a esa base y
## salta arriba cada 3 s), --test-input=stand:ID (se sube a esa base y se queda
## quieto), --test-input=hop:ID (se sube y después salta afuera
## y adentro cada 2,5 s), --test-input=edge:ID (igual, pero salta hacia el
## borde), --test-input=walkoff:ID (sale y entra caminando, sin saltar),
## --test-input=tunnel (se desliza en el túnel largo y sale agachado),
## --test-input=crouchjump (salta frente a la pared de medidas y se agacha
## en el aire), --test-input=ladder (sube y baja por la escalera de la torre)
## o --test-input=laddertop (la sube y sale al techo de la torre),
## --test-input=laddertop:back (igual, pero en tercera persona y con la cámara
## mirando para atrás: al salir sigue con W sola, que lo lleva derecho, y
## después toca D), --test-input=laddertop:stop (igual que laddertop, pero
## suelta W en la salida por arriba con el cuerpo ya sobre el techo: termina
## la escalera ahí),
## --test-input=cable (sube a la plataforma alta de la pista de cables, se
## agarra de la tirolesa, se desliza con W hasta abajo, frenando una vez a
## mitad de camino, sube un poco con S y se suelta),
## --test-spawn-at=X,Z (solo host), --test-pause-at=TICK (jugando solo: se
## pone la pausa en ese tick), --no-adoption y
## --test-push-at=S1,S2 y --test-scheduled-push-at=S1,S2 (solo host: empuja a
## los demás a esos segundos, inmediato o programado), --test-push-force=N
## (fuerza de esos empujones, de 0 a 5; 4 si no se pide), --test-schedule-ticks=N
## (el programado se fija N ticks adelante, para probar uno que llega tarde),
## --test-input=ladderhold (sube la escalera de la torre a 1,5 m y se queda;
## con ladderhold:drop, se suelta con Ctrl medio segundo después de que alguien
## se cuelga de él, y al soltar Ctrl se vuelve a agarrar),
## --test-input=ladderdrop (en la escalera de la torre, por turnos: se suelta
## con Ctrl y se vuelve a agarrar solo al soltarlo; salta mirándola y se vuelve
## a agarrar solo al bajar),
## --test-input=hookwall (se agarra del muro alto desde el cajón y se corre al
## medio; con hookwall:drop, se suelta medio segundo después de que alguien se
## cuelga de él), --test-input=hook:wall o hook:ladder (se cuelga del
## compañero que está en el muro alto o en la escalera, y después se suelta,
## salta para arriba o salta hacia atrás, por turnos),
## --test-quit-hooked=TICKS (con alguien colgado de él, o colgado de alguien,
## cierra el juego a los tantos ticks, como si se cortara; con
## --test-cut-hooked, en vez de cerrar corta la red una vez),
## --test-world-slow-at=S1,S2 (esta máquina aprieta el 1 del teclado
## numérico a esos segundos: prende y apaga la cámara lenta del mundo),
## --test-power-at=S1,S2 (lo mismo con el 2: el súper salto y velocidad),
## --test-harm-at=S1,S2 (solo host: a esos segundos les quita 1000 de salud a
## los demás, como la cápsula letal: muerte de prueba),
## --test-poison-at=S:PUNTOS:SEGUNDOS,… (solo host: a esos segundos les pone a
## los demás un daño en el tiempo; sin puntos ni segundos, 20 en 4 s),
## --test-relay=PUERTO (cliente: se conecta a través de un relevo en ese
## puerto), --test-cut-at=S1,S2 (a esos segundos se corta el relevo,
## como un cable; sin relevo, esta máquina deja de atender la red, como si se
## trabara), --test-cut-for=SEGUNDOS (cuánto dura cada corte; 10 si no se
## pide), --reconnect-wait=SEGUNDOS (cuánto espera el host a un jugador
## cortado), --test-tuning=NOMBRE=VALOR (cambia un valor del Tuning, para
## probar que el host no deja entrar a una copia distinta) y,
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
## Cliente: si hace más que esto que no llega nada del host, en ms reales, el
## actor propio queda quieto donde está hasta que vuelvan los snapshots. Del
## otro lado el host lo deja quieto igual (NetSync.STALE_INPUT_TICKS), así al
## volver los dos lo tienen en el mismo lugar.
const HOST_SILENCE_MSEC := 500
## Cliente: mientras no predice (todavía no sincronizó, o quieto sin noticias
## del host), cada cuántos ticks le avisa al host que sigue ahí.
const HEARTBEAT_TICKS := 15
## Niveles del simulador de red, con Alt + 1 a 5. La demora es de ida y
## vuelta; los tirones traban la conexión stall ms cada stall_every ms.
const NET_PRESETS := [
	{"name": "sin simulación", "rtt": 0.0, "jitter": 0.0, "loss": 0.0},
	{"name": "internet buena", "rtt": 40.0, "jitter": 5.0, "loss": 0.0},
	{"name": "internet normal", "rtt": 120.0, "jitter": 20.0, "loss": 1.0},
	{"name": "internet mala", "rtt": 200.0, "jitter": 40.0, "loss": 5.0},
	{"name": "Wi-Fi con tirones", "rtt": 20.0, "jitter": 5.0, "loss": 0.0, "stall_every": 3000.0, "stall": 150.0},
]

enum Role { LOCAL, HOST, CLIENT }

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
## Lo mismo para la cámara lenta del mundo (1 del teclado numérico). Viaja en
## el input.
var ability_presses := 0
## Lo mismo para el súper salto y velocidad (2 del teclado numérico). Viaja en
## el input y lo lee el motor.
var power_presses := 0
## Segundos a los que esta máquina pide la cámara lenta del mundo, y a los que
## aprieta el súper salto y velocidad, pedidos por argumentos.
var test_world_slow_seconds := PackedFloat64Array()
var test_power_seconds := PackedFloat64Array()
## Prueba, solo host: a esos segundos les quita 1000 de salud a los demás
## jugadores, por el mismo camino que la cápsula letal (ActorVitals).
var test_harm_seconds := PackedFloat64Array()
## Prueba, solo host: [segundos, puntos, duración]: a esos segundos les pone
## a los demás un daño en el tiempo, como un consumible (ActorVitals).
var test_poisons: Array = []
## Host: si la cámara lenta del mundo está pedida, según los pedidos de los
## jugadores (ActorPowers.SLOW en su estado) al empezar el tick, y quiénes la
## piden.
var _world_slow_held := false
var _world_slow_holders: Array = []
## Ticks en que la cámara lenta del mundo empieza o termina: ahí se sube la
## época de todos (host) o la del propio actor (cliente).
var _world_slow_changes := {}
## Host: cambios en los pedidos (de nadie a alguno o de alguno a nadie) y
## tramos prendidos y apagados. Cliente: cambios que llegaron a tiempo, tarde
## (se repitió desde su tick) y demasiado tarde.
var world_slow_requests := 0
var world_slow_started := 0
var world_slow_stopped := 0
var world_slow_on_time := 0
var world_slow_late := 0
var world_slow_too_late := 0
## Prueba: ticks corridos con la escala del mundo por debajo de 1, y por
## jugador, ticks terminados con el súper y con su pedido de cámara lenta
## (peer -> [súper, cámara lenta]), en esta máquina.
var slow_ticks_seen := 0
var _power_ticks := {}
## Prueba de reconexión: a esos segundos esta máquina deja de atender la red
## durante test_cut_seconds, como si se cortara el cable.
var test_cut_seconds_at := PackedFloat64Array()
var test_cut_seconds := 10.0
## Prueba de reconexión, cliente: si es mayor que cero, se conecta al host a
## través de un relevo en este puerto (TestUdpRelay), y los cortes cortan el
## relevo, como un cable. Sin relevo, un corte deja de atender la red: es una
## máquina trabada, que todavía manda algunas cosas.
var test_relay_port := 0
var _relay: TestUdpRelay
## Prueba de compatibilidad: valores del Tuning cambiados por argumentos, por
## nombre, como si esta copia tuviera otros en el Inspector.
var test_tuning := {}
## Cliente: veces que el actor propio quedó quieto por no tener noticias del host.
var host_silences := 0
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
## Prueba `stand`: si ya se quedó quieto sobre la base.
var _standing := false
## Prueba `tunnel`: tramo del recorrido y ticks en que quedó parado bajo el techo.
var _tunnel_phase := 0
var _tunnel_standing_under_roof := 0
## Prueba `crouchjump`: tick local en que llegó frente a la pared de medidas.
var _crouch_jump_start := -1
## Prueba `ladder`: hacia dónde trepa (1 sube, -1 baja) y, en `laddertop`, si
## ya llegó arriba.
var _ladder_direction := 1.0
var _ladder_top_done := false
## Prueba `laddertop:back`: tick local en que llegó arriba de la escalera.
var _ladder_top_tick := -1
## Prueba `airjump`: sube la escalera de la torre, se cae por el costado y,
## cayendo, salta en el aire hacia donde mira la cámara. Tramo, ticks cayendo,
## pulsaciones de salto propias y cuántos saltos en el aire hizo.
var _air_phase := 0
var _air_since := 0
var _air_presses := 0
var air_jumps := 0
## Prueba `cable`: tramo del ciclo, ticks en el tramo, desde dónde subió, a qué
## punto del camino de vuelta va, y cuántas veces se agarró, frenó a mitad de
## camino al soltar W, llegó abajo deslizándose y cuánto subió en total.
var _cable_phase := 0
var _cable_ticks := 0
var _cable_climb_from := 0.0
var _cable_waypoint := 0
var cable_grabs := 0
var cable_slides := 0
var cable_stops := 0
var cable_climbed := 0.0
## Prueba `hang`: tramo del ciclo, ticks en el tramo, vuelta del ciclo,
## pulsaciones de salto propias y cuántas veces se agarró y subió.
var _hang_phase := 0
var _hang_since := 0
var _hang_cycle := 0
var _hang_presses := 0
var hang_grabs := 0
var hang_climbs := 0
## Prueba `hangcorner`: la misma, pero colgado se mueve 2,5 s para cada lado,
## así da la vuelta a las dos esquinas del bloque y vuelve. Ticks que se mueve
## para cada lado, esquinas que empezó a doblar por afuera y si estaba doblando.
## Prueba `hanginner`: lo mismo contra el rincón de la pista de bordes; está
## detrás de la primera fila, y se llega rodeándola por x = _hang_detour_x.
const INNER_CORNER_FACE := Vector3(26.5, 0.0, -18.0)
## Prueba `cable`: la escalera de la plataforma alta y la tirolesa de la pista
## de cables (el nodo, por su nombre: los cables se numeran solos), y el camino
## de vuelta desde abajo hasta el pie de la escalera, por detrás de la plataforma.
const CABLE_LADDER_NAME := &"EscaleraTirolesa"
## La escalera de la torre chica, la de las pruebas de escalera y de colgarse
## de un compañero (por su nombre: las escaleras se numeran solas).
const TOWER_LADDER_NAME := &"TowerLadder"
const CABLE_ZIPLINE_NAME := &"Tirolesa"
const CABLE_RETURN := [Vector3(16.0, 0.0, 27.5), Vector3(9.35, 0.0, 27.5)]
## Prueba `cablehold`: a qué altura del cable deja de deslizarse. Frenando
## queda un poco más abajo; desde el piso, se llega saltando a su cintura.
const CABLE_HOLD_HEIGHT := 3.9
## Prueba `hook:cable`: a qué distancia del compañero salta hacia él, y por
## dónde pasa desde donde se aparece, para no chocar con la torre chica.
const HOOK_CABLE_START := 1.0
const HOOK_CABLE_DETOUR := Vector3(20.0, 0.0, 9.0)
var _hang_face := Vector3.INF
var _hang_detour_x := 0.0
var _hang_shimmy := 30
var hang_corners := 0
var hang_corners_inside := 0
var _hang_turning := false
## Prueba `hang`: a qué distancia de la cara salta, del centro del cuerpo. Hasta
## el 2026-10-25 era 1,3 m: con el mantle, desde ahí llega con las manos por
## encima del filo del bloque de 2 m y se sube, en vez de colgarse.
const HANG_JUMP_DISTANCE := 0.5
## Prueba `mantle`: tramo del ciclo, ticks en el tramo, vueltas, pulsaciones de
## salto propias, cuántos mantles empezó y cuántos terminaron arriba.
var _mantle_phase := 0
var _mantle_since := 0
var _mantle_presses := 0
var mantle_starts := 0
var mantle_tops := 0
var mantle_cycles := 0
## Prueba `steps`: punto del recorrido al que va, ticks desde que lo empezó y
## la altura más alta de los pies.
var _steps_index := 0
var _steps_since := 0
var _steps_max_height := 0.0
## Cuánto se separa en pantalla quien cuelga de este jugador de la pose que le
## daría el cuerpo de este jugador, como máximo.
var hooked_gap_max := 0.0
## Prueba de desconexión: con un compañero colgado de él (o colgado de uno),
## cierra el juego después de tantos ticks. 0 = nunca. Con test_cut_when_hooked,
## en vez de cerrar corta la red una vez.
var test_quit_hooked := 0
var test_cut_when_hooked := false
var _hooked_cut_done := false
## Host: cambios de quién cuelga de quién (eventos que suben la época) y
## colgados que se soltaron porque otro se colgó del mismo en el mismo tick.
var hook_events := 0
var hook_kicks := 0
## Host: quién colgaba de quién al empezar el tick (peer -> peer del
## compañero), y cuántas veces un compañero soltó al que colgaba de él.
var _hooked_at_start := {}
var hooks_released := 0
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
## Prueba `hook:cable`: cuántas veces quedó del lado que no buscaba, cuánto
## giró con D en total (en grados) y cuánto subió con W (en metros), y la
## altura de las manos y el ángulo al empezar a girar.
var hook_wrong_side := 0
var hook_turned := 0.0
var hook_climbed := 0.0
var _hook_turn_from := 0.0
var _hook_climb_from := 0.0
## Pruebas `hook`: cuántas veces, después de saltar desde él, se volvió a
## agarrar de él al caer.
var hook_regrabs := 0
## Pruebas `ladderdrop` y `ladderhold:drop`: tramo, ticks en el tramo,
## pulsaciones de salto propias, ticks de Ctrl que faltan y cuántas veces se
## soltó con Ctrl, saltó mirándola y se volvió a agarrar solo después de cada cosa.
var _ladder_drop_phase := 0
var _ladder_drop_since := 0
var _ladder_drop_presses := 0
var _ladder_ctrl_left := 0
var _ladder_dropped := false
var ladder_drops := 0
var ladder_drop_returns := 0
var ladder_jumps := 0
var ladder_jump_returns := 0
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

## Valores de movimiento: el nodo Tuning de esta escena. Todos los actores se
## mueven con estos mismos valores.
@onready var tuning: ActorTuning = $Tuning
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
@onready var _inventory: InvNet = $Inventario
@onready var _inventory_ui: InvUI = $Hud/InventarioUI
@onready var _hud: LabHud = $Hud/Instrumentos
## Si el panel estaba a la vista al abrir el inventario: al cerrarlo vuelve así.
var _info_before_inventory := true


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
	for property in test_tuning:
		tuning.set(property, test_tuning[property])
	# Antes del primer tick: después las plataformas y la balsa ya se movieron.
	_session.compatibility = SimFingerprint.compute(tuning, SimFingerprint.level_text($Level),
			SimFingerprint.actor_text(NetSession.ACTOR_SCENE),
			_inventory.fingerprint_text() + "\n" + SimFingerprint.level_text($ZonaDeInventario))
	print("[net_lab] huella de compatibilidad: %s" % _session.compatibility.hex_encode())
	_clock.actors_root = _actors
	_clock.tuning = tuning
	_clock.input_provider = _input_for
	_clock.before_step = _inventory.use_before_step
	_clock.tick_started.connect(_on_tick_started)
	_clock.tick_finished.connect(_on_tick_finished)
	_clock.hard_resynced.connect(_on_hard_resynced)
	_clock.link = _link
	_net_sync.link = _link
	_net_sync.clock = _clock
	_session.net_sync = _net_sync
	_inventory.link = _link
	_inventory.tuning = tuning
	_session.actor_replaced.connect(_inventory.actor_replaced)
	# Con el inventario abierto, el panel de valores se oculta: tapa la grilla.
	_inventory_ui.opened.connect(func() -> void:
		_info_before_inventory = _info.visible
		_info.visible = false)
	_inventory_ui.closed.connect(func() -> void: _info.visible = _info_before_inventory)
	multiplayer.server_disconnected.connect(_link.clear)
	multiplayer.peer_disconnected.connect(_interpolation.forget)
	multiplayer.peer_connected.connect(_announce_world_slow_to)
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
	for seconds in test_world_slow_seconds:
		_real_timer(seconds, func() -> void: ability_presses = (ability_presses + 1) & 0xFF)
	for seconds in test_power_seconds:
		_real_timer(seconds, func() -> void: power_presses = (power_presses + 1) & 0xFF)
	for seconds in test_harm_seconds:
		_real_timer(seconds, _harm_others)
	for poison: Array in test_poisons:
		_real_timer(poison[0], _poison_others.bind(poison[1], poison[2]))
	for seconds in test_cut_seconds_at:
		_real_timer(seconds, _cut_network)
	_session.status_changed.connect(func(text: String) -> void: print("[net_lab] %s" % text))
	_session.local_actor_spawned.connect(_on_local_actor_spawned)
	_session.connection_lost.connect(_on_connection_lost)
	_session.connection_restored.connect(func() -> void: _flash("Volviste a conectarte: seguís donde estabas"))
	_session.player_waiting.connect(_on_player_waiting)
	$Hud/Menu/Box/Solo.pressed.connect(_start.bind(Role.LOCAL))
	$Hud/Menu/Box/Host.pressed.connect(_start.bind(Role.HOST))
	$Hud/Menu/Box/JoinRow/Join.pressed.connect(_on_join_pressed)
	_address_field.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_lan_label.text = "Tu IP para que se unan:\n%s" % _lan_addresses()
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
	# Los poderes van en el teclado numérico, con acciones del Mapa de entrada.
	elif _started and event.is_action_pressed("camara_lenta_mundo"):
		ability_presses = (ability_presses + 1) & 0xFF
	elif _started and event.is_action_pressed("super_salto_velocidad"):
		power_presses = (power_presses + 1) & 0xFF
	elif _started and event is InputEventKey and event.pressed and not event.echo:
		var index: int = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5].find(event.keycode)
		if event.keycode == KEY_F1:
			# Oculta o muestra el panel, para mirar o capturar el juego sin él
			# (pedido del usuario, 2026-10-19).
			_info.visible = not _info.visible
		elif index >= 0 and event.alt_pressed:
			# Con Alt: la fila de arriba sin Alt es la barra rápida del inventario.
			_apply_net_preset(index)
		elif role == Role.HOST and (event.keycode == KEY_Y or event.keycode == KEY_U):
			var force := PUSH_FORCE_WEAK if event.shift_pressed else PUSH_FORCE_STRONG
			_push_requests.append([event.keycode == KEY_U, force])
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
	# Antes de la sesión: el host arma el mundo del inventario y el cliente
	# queda esperando el estado que le mande el host.
	_inventory.start(role != Role.CLIENT)
	match role:
		Role.HOST:
			_session.start_host(port, bind_address)
		Role.CLIENT:
			# Las balsas las simula solo el host: acá pasan a ser copias que mueve la interpolación.
			for base in BaseRegistry.all():
				if base is HostRaft:
					base.become_copy()
			if test_relay_port > 0:
				_relay = TestUdpRelay.new()
				add_child(_relay)
				var err := _relay.start(test_relay_port, host_address, port)
				print("[net_lab] relevo de prueba en el puerto %d hacia %s:%d (error %d)" % [test_relay_port, host_address, port, err])
				_session.start_client("127.0.0.1", test_relay_port)
			else:
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
		var own := _local_input(tick)
		_add_player_presses(own, tick)
		return own
	var remote := _net_sync.input_for(actor.owner_peer_id, tick)
	if remote != null:
		return remote
	var still := ActorInput.make(tick, Vector2.ZERO, 0.0, 0, actor.state.jump_presses_seen, actor.state.ability_presses_seen,
			actor.state.power_presses_seen)
	still.use_presses = actor.state.use_presses_seen
	return still


## Lo que va en el input propio sea cual sea la prueba que arma el resto: los
## poderes (Kp 1 y Kp 2) y, desde el 2026-11-04, el uso de un consumible, uno
## por tick (InvNet.take_use).
func _add_player_presses(input: ActorInput, tick: int) -> void:
	input.ability_presses = ability_presses
	input.power_presses = power_presses
	_inventory.take_use(tick)
	input.use_presses = _inventory.use_presses
	input.use_uid = _inventory.use_uid


## Input de este jugador: del teclado, o del guion de prueba si se pidió.
func _local_input(tick: int) -> ActorInput:
	if test_input == "walk":
		# Camina 1,5 s hacia adelante, salta a los 0,5 s y después se queda quieto.
		var walking := _local_ticks < 90
		var presses := 1 if _local_ticks >= 30 else 0
		return ActorInput.make(tick, Vector2(0, 1) if walking else Vector2.ZERO, 0.0, 0, presses)
	if test_input.begins_with("stand:"):
		return _stand_input(tick, test_input.trim_prefix("stand:").to_int())
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
	if test_input == "mantle" or test_input.begins_with("mantle:"):
		return _mantle_input(tick, test_input.trim_prefix("mantle:").to_int() if test_input.begins_with("mantle:") else 0)
	if test_input == "hangcorner":
		_hang_shimmy = 150
		return _hang_input(tick, 0)
	if test_input == "hanginner":
		_hang_shimmy = 150
		_hang_face = INNER_CORNER_FACE
		_hang_detour_x = 29.6
		return _hang_input(tick, 0)
	if test_input == "airjump":
		return _air_jump_input(tick)
	if test_input == "cable" or test_input == "cablehold":
		return _cable_input(tick, test_input == "cablehold")
	if test_input == "ladder" or test_input == "laddertop" or test_input == "laddertop:back" or test_input == "laddertop:stop":
		return _ladder_input(tick, test_input != "ladder", TOWER_LADDER_NAME, test_input == "laddertop:back", test_input == "laddertop:stop")
	if test_input == "ladderhold" or test_input == "ladderhold:drop":
		return _ladder_hold_input(tick, test_input == "ladderhold:drop")
	if test_input == "ladderdrop":
		return _ladder_drop_input(tick)
	if test_input == "hookwall" or test_input == "hookwall:drop":
		return _hook_wall_input(tick, test_input == "hookwall:drop")
	if test_input == "hook:cable":
		return _hook_cable_input(tick)
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
	if _inventory_ui.is_typing():
		# Escribiendo una cantidad en el inventario, las teclas son del campo.
		move = Vector2.ZERO
		buttons = 0
	if _camera.third_person():
		buttons |= ActorInput.BUTTON_THIRD_PERSON
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


## Prueba de quedarse quieto: llega a la base como `ride` y, a menos de 1 m de
## su centro, se queda parado ahí sin moverse ni saltar.
func _stand_input(tick: int, base_id: int) -> ActorInput:
	var base = BaseRegistry.find(base_id)
	if not _standing and base != null and is_instance_valid(_local_actor) and _local_actor.state.base_id == base_id:
		var me := BaseRegistry.world_position(_local_actor.state)
		var center: Vector3 = base.base_origin()
		if Vector2(me.x - center.x, me.z - center.z).length() < 1.0:
			_standing = true
			print("[net_lab] quieto sobre la base %d en el tick %d" % [base_id, tick])
	if _standing:
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _ride_presses)
	return _ride_input(tick, base_id)


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
			# Mantiene Ctrl sin moverse: soltarlo cortaría el deslizamiento antes
			# del túnel. Frena solo, ya bajo el techo.
			buttons |= ActorInput.BUTTON_CROUCH
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


## La escalera con ese nombre, o null.
func _ladder_named(ladder_name: StringName) -> Ladder:
	for ladder: Ladder in Ladder.all():
		if ladder.name == ladder_name:
			return ladder
	return null


## Prueba de escalera: va al pie de la escalera de la torre (u otra, por su nombre), se agarra
## caminando hacia ella y sube y baja entre 0,5 y 2 m. Si la suelta (un
## empujón fuerte), vuelve. Con `to_top`, sube hasta arriba, sale al techo de
## la torre y se queda ahí.
## Con `look_back`, trepa en tercera persona con la cámara mirando para atrás
## y, al salir por arriba, sigue 30 ticks con W sola (va derecho, hacia adentro
## del techo), toca D 6 ticks y se queda quieto.
## Con `stop_on_exit`, suelta W apenas pasó medio metro del alto (en la
## salida por arriba, con el centro del cuerpo ya sobre el techo).
func _ladder_input(tick: int, to_top: bool, ladder_name := TOWER_LADDER_NAME, look_back := false, stop_on_exit := false) -> ActorInput:
	var ladder := _ladder_named(ladder_name)
	if ladder == null or not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	var s := _local_actor.state
	var facing := atan2(ladder.outward().x, ladder.outward().z)
	var look := facing + PI if look_back else facing
	var view := ActorInput.BUTTON_THIRD_PERSON if look_back else 0
	if s.mode == ActorState.Mode.LADDER:
		if to_top:
			if s.anchor_t >= ladder.height - 0.01:
				_ladder_top_done = true
			if stop_on_exit and s.anchor_t >= ladder.height + 0.5:
				return ActorInput.make(tick, Vector2.ZERO, look, view, 0)
			return ActorInput.make(tick, Vector2(0, 1), look, view, 0)
		if s.anchor_t >= 2.0:
			_ladder_direction = -1.0
		elif s.anchor_t <= 0.5:
			_ladder_direction = 1.0
		return ActorInput.make(tick, Vector2(0, _ladder_direction), facing, 0, 0)
	if to_top and _ladder_top_done and look_back:
		if _ladder_top_tick < 0:
			_ladder_top_tick = tick
		var after := tick - _ladder_top_tick
		var keys := Vector2(0, 1) if after < 30 else Vector2(1, 0) if after < 36 else Vector2.ZERO
		return ActorInput.make(tick, keys, look, view, 0)
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


## Prueba del salto en el aire, en ciclos: sube la escalera de la torre (2,5 m),
## camina hacia +X hasta caerse por el costado y, a los 0,25 s de caer, gira
## la cámara hacia -Z y salta en el aire sin teclas: sale hacia la cámara y
## cae delante de la torre, cerca de la escalera, para empezar otra vuelta.
func _air_jump_input(tick: int) -> ActorInput:
	if not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _air_presses)
	var s := _local_actor.state
	match _air_phase:
		0:  # sube la escalera hasta el techo
			if _ladder_top_done and s.mode == ActorState.Mode.GROUND and BaseRegistry.world_position(s).y > 2.0:
				_air_phase = 1
			var climb := _ladder_input(tick, true)
			climb.jump_presses = _air_presses
			return climb
		1:  # camina hacia +X hasta caerse
			if s.mode == ActorState.Mode.AIR:
				_air_phase = 2
				_air_since = 0
			return ActorInput.make(tick, Vector2(0, 1), -PI * 0.5, 0, _air_presses)
		2:  # cayendo: salta en el aire mirando a -Z
			_air_since += 1
			if _air_since == 15:
				_air_presses = (_air_presses + 1) & 0xFF
			elif _air_since == 17 and s.velocity.y > 3.0:
				air_jumps += 1
			elif _air_since > 17 and s.mode == ActorState.Mode.GROUND:
				_air_phase = 0
				_ladder_top_done = false
			return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _air_presses)
	return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _air_presses)


## Prueba de cables, en ciclos, en la tirolesa de la pista de cables: sube la
## escalera de la plataforma alta, camina hacia +X hasta caerse por el borde y
## agarrarse del cable, se desliza con W mirando hacia abajo (a la mitad suelta
## W medio segundo y frena), sube 1,5 s con S (mirando para abajo, S es para
## arriba), se suelta con Ctrl y vuelve a la escalera por detrás de la
## plataforma.
##
## Prueba `cablehold` (con `hold`): se desliza hasta que el cable queda a
## CABLE_HOLD_HEIGHT y ahí suelta W y se queda colgado, para que otro se
## cuelgue de él (prueba `hook:cable`).
func _cable_input(tick: int, hold := false) -> ActorInput:
	if not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	var s := _local_actor.state
	var me := BaseRegistry.world_position(s)
	var cable: Cable = null
	for each: Cable in Cable.all():
		if each.name == CABLE_ZIPLINE_NAME:
			cable = each
	var phase := _cable_phase
	var input := ActorInput.make(tick, Vector2.ZERO, -PI * 0.5, 0, 0)
	match _cable_phase:
		0:  # sube la escalera hasta la plataforma
			if _ladder_top_done and s.mode == ActorState.Mode.GROUND and me.y > 5.0:
				_cable_phase = 1
			input = _ladder_input(tick, true, CABLE_LADDER_NAME)
		1:  # camina hacia +X hasta caerse por el borde y agarrarse
			if s.mode == ActorState.Mode.CABLE:
				cable_grabs += 1
				_cable_phase = 2
				_cable_ticks = 0
			elif s.mode == ActorState.Mode.GROUND and me.y < 1.0:
				_cable_phase = 4
				_cable_waypoint = 0
			else:
				input = ActorInput.make(tick, Vector2(0, 1), -PI * 0.5, 0, 0)
		2:  # se desliza con W mirando hacia abajo; a mitad de camino suelta W y frena
			_cable_ticks += 1
			if s.mode != ActorState.Mode.CABLE or cable == null:
				_cable_phase = 4
				_cable_waypoint = 0
			elif hold:
				var low_enough := s.anchor_point.y <= CABLE_HOLD_HEIGHT
				input = ActorInput.make(tick, Vector2.ZERO if low_enough else Vector2(0, 1), -PI * 0.5, 0, 0)
			elif _cable_ticks > 60 and s.velocity.length() < 0.001 and s.anchor_t >= cable.length() - 1.0:
				cable_slides += 1
				_cable_phase = 3
				_cable_ticks = 0
				_cable_climb_from = s.anchor_t
			else:
				var resting := _cable_ticks > 40 and _cable_ticks <= 70
				if _cable_ticks == 70 and s.velocity.length() < 0.001:
					cable_stops += 1
				input = ActorInput.make(tick, Vector2.ZERO if resting else Vector2(0, 1), -PI * 0.5, 0, 0)
		3:  # sube 1,5 s con S y se suelta con Ctrl
			_cable_ticks += 1
			if s.mode != ActorState.Mode.CABLE or cable == null:
				_cable_phase = 4
				_cable_waypoint = 0
			elif _cable_ticks <= 90:
				input = ActorInput.make(tick, Vector2(0, -1), -PI * 0.5, 0, 0)
			else:
				cable_climbed += _cable_climb_from - s.anchor_t
				input = ActorInput.make(tick, Vector2.ZERO, -PI * 0.5, ActorInput.BUTTON_CROUCH, 0)
				_cable_phase = 4
				_cable_waypoint = 0
		4:  # vuelve a la escalera por detrás de la plataforma
			if s.mode == ActorState.Mode.GROUND:
				if _cable_waypoint < CABLE_RETURN.size():
					var target: Vector3 = CABLE_RETURN[_cable_waypoint]
					if Vector2(target.x - me.x, target.z - me.z).length() < 0.4:
						_cable_waypoint += 1
					input = ActorInput.make(tick, _walk_to(me, target), 0.0, 0, 0)
				else:
					_cable_phase = 0
					_ladder_top_done = false
	if phase != _cable_phase:
		print("[net_lab] cable: tramo %d en %s, %s" % [_cable_phase, me, s.describe()])
	return input


## Prueba de Hanging, en ciclos, contra la cara de un bloque de 2 m de la pista
## de bordes (o el de una base, si se pide su id): se aleja 2,2 m de la cara,
## corre hacia ella, salta cerca de la cara y se agarra. Colgado se mueve a la derecha y
## a la izquierda y después, según la vuelta: salta para arriba mirando a la
## pared, aprieta W en la punta del salto para quedar arriba del borde (el
## bloque tiene 1 m de fondo) y se baja por delante; se suelta con Ctrl; o salta
## hacia atrás.
func _hang_input(tick: int, base_id: int) -> ActorInput:
	if not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _hang_presses)
	var face := _hang_face if _hang_face != Vector3.INF else Vector3(13.5, 0.0, -10.0)
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
			if _hang_detour_x != 0.0 and me.z > face.z + 4.5:
				# Detrás de otra fila: primero hasta x = _hang_detour_x, después la pasa en z.
				to = Vector2(_hang_detour_x - me.x, 0.0) if absf(me.x - _hang_detour_x) > 0.3 \
						else Vector2(0.0, face.z + 4.0 - me.z)
			if to.length() < 0.3 and s.mode == ActorState.Mode.GROUND:
				_hang_phase = 1
			elif absf(to.x) > 0.3:
				move = Vector2(signf(to.x), 0.0)
			else:
				move = Vector2(to.x, -to.y).limit_length(1.0)
		1:  # corre hacia la cara y salta cerca (HANG_JUMP_DISTANCE)
			move = Vector2(0, 1)
			if me.z - face.z < HANG_JUMP_DISTANCE:
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
			var shimmy := _hang_shimmy
			if s.mode == ActorState.Mode.HANGING and s.anchor_t != 0.0 and not _hang_turning:
				hang_corners += 1
				if s.corner_inside:
					hang_corners_inside += 1
			_hang_turning = s.mode == ActorState.Mode.HANGING and s.anchor_t != 0.0
			if s.mode != ActorState.Mode.HANGING:
				_hang_phase = 4 if _hang_cycle % 3 == 0 and _hang_since > 30 + 2 * shimmy else 0
			elif _hang_since < 20:
				pass
			elif _hang_since < 20 + shimmy:
				move = Vector2(1, 0)
			elif _hang_since < 20 + 2 * shimmy:
				move = Vector2(-1, 0)
			elif _hang_since == 30 + 2 * shimmy:
				match _hang_cycle % 3:
					0:
						_hang_presses = (_hang_presses + 1) & 0xFF
					2:
						yaw = PI
						_hang_presses = (_hang_presses + 1) & 0xFF
			elif _hang_since >= 30 + 2 * shimmy and _hang_since < 35 + 2 * shimmy and _hang_cycle % 3 == 1:
				buttons = ActorInput.BUTTON_CROUCH
			elif _hang_since > 140 + 2 * shimmy:
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
				# Cayendo por delante sigue mirando para atrás: mirando el bloque, las
				# manos lo agarrarían desde arriba (hang_reach_down) y la prueba se
				# quedaba colgada ahí.
				yaw = PI
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


## Prueba del mantle (2026-10-25), en ciclos, contra la misma cara que `hang`
## (el bloque de 2 m de la pista de bordes, o el de una base, si se pide su id):
## se aleja 2,2 m de la cara, camina hacia ella y salta a 1,3 m; el mantle lo
## sube arriba, una vuelta de cada dos derecho y la otra en diagonal, con D.
## Después se da vuelta y se baja por delante.
func _mantle_input(tick: int, base_id: int) -> ActorInput:
	if not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _mantle_presses)
	var face := Vector3(13.5, 0.0, -10.0)
	if base_id != 0:
		var base = BaseRegistry.find(base_id)
		if base == null:
			return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _mantle_presses)
		face = base.base_origin() + Vector3(0.0, -1.0, 0.5)
	var s := _local_actor.state
	var me := BaseRegistry.world_position(s)
	_mantle_since += 1
	var move := Vector2.ZERO
	var yaw := 0.0
	match _mantle_phase:
		0:  # a 2,2 m de la cara
			var to := Vector2(face.x - me.x, face.z + 2.2 - me.z)
			if to.length() < 0.3 and s.mode == ActorState.Mode.GROUND:
				_mantle_phase = 1
			elif absf(to.x) > 0.3:
				move = Vector2(signf(to.x), 0.0)
			else:
				move = Vector2(to.x, -to.y).limit_length(1.0)
		1:  # camina hacia la cara y salta a 1,3 m
			move = Vector2(0, 1)
			if me.z - face.z < 1.3:
				_mantle_presses = (_mantle_presses + 1) & 0xFF
				_mantle_phase = 2
				_mantle_since = 0
		2:  # en el aire: el mantle lo sube; una vuelta de cada dos, con D pasa arriba en diagonal
			if s.mode == ActorState.Mode.MANTLE and mantle_cycles % 2 == 1:
				move = Vector2(1, 0)
			if s.mode == ActorState.Mode.MANTLE and _mantle_since < 1000:
				mantle_starts += 1
				_mantle_since = 1000
			if s.mode == ActorState.Mode.GROUND and me.y > face.y + 1.5:
				mantle_tops += 1
				_mantle_phase = 3
				_mantle_since = 0
			elif s.mode == ActorState.Mode.GROUND and (_mantle_since > 20 and _mantle_since < 1000 or _mantle_since > 1100):
				_mantle_phase = 0
		3:  # arriba: se da vuelta y se baja por delante
			yaw = PI
			if _mantle_since > 20:
				move = Vector2(0, 1)
			if s.mode == ActorState.Mode.GROUND and me.y < face.y + 0.5:
				mantle_cycles += 1
				_mantle_phase = 0
	return ActorInput.make(tick, move, yaw, 0, _mantle_presses)


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
const HOOK_DROP_TICKS := 30
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
## Con `drop`, HOOK_DROP_TICKS después de que alguien se colgó de él se suelta
## con Ctrl 10 ticks (se caen los dos) y, al soltar Ctrl, se vuelve a agarrar.
func _ladder_hold_input(tick: int, drop := false) -> ActorInput:
	var ladder := _ladder_named(TOWER_LADDER_NAME)
	if ladder == null or not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	var s := _local_actor.state
	var facing := atan2(ladder.outward().x, ladder.outward().z)
	if _ladder_ctrl_left > 0:
		_ladder_ctrl_left -= 1
		return ActorInput.make(tick, Vector2.ZERO, facing, ActorInput.BUTTON_CROUCH, 0)
	if _ladder_dropped:
		_ladder_dropped = false
		if s.mode == ActorState.Mode.AIR:
			_ladder_ctrl_left = -2
	elif _ladder_ctrl_left < 0:
		# Dos ticks después de soltar Ctrl: tiene que estar agarrado otra vez.
		_ladder_ctrl_left += 1
		if _ladder_ctrl_left == 0 and s.mode == ActorState.Mode.LADDER:
			ladder_drop_returns += 1
	if drop and s.mode == ActorState.Mode.LADDER and s.hooked_by != 0:
		_hook_loaded_ticks += 1
		if _hook_loaded_ticks >= HOOK_DROP_TICKS:
			_hook_loaded_ticks = 0
			hook_drops += 1
			_ladder_ctrl_left = 9
			_ladder_dropped = true
			return ActorInput.make(tick, Vector2.ZERO, facing, ActorInput.BUTTON_CROUCH, 0)
	elif s.mode == ActorState.Mode.LADDER:
		_hook_loaded_ticks = 0
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


## Prueba `ladderdrop`, en ciclos, en la escalera de la torre: sube a 2 m; con
## Ctrl se suelta 15 ticks y, al soltarlo, se tiene que volver a agarrar solo;
## baja a 1,5 m y salta mirándola: pasa por encima del final (2,5 m) y se tiene
## que agarrar solo al bajar, arriba de todo.
func _ladder_drop_input(tick: int) -> ActorInput:
	var ladder := _ladder_named(TOWER_LADDER_NAME)
	if ladder == null or not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _ladder_drop_presses)
	var s := _local_actor.state
	var facing := atan2(ladder.outward().x, ladder.outward().z)
	_ladder_drop_since += 1
	var move := Vector2.ZERO
	var buttons := 0
	match _ladder_drop_phase:
		0, 3:  # hasta la escalera, y a 2 m (para soltarse) o a 1,5 m (para saltar)
			var target := 2.0 if _ladder_drop_phase == 0 else 1.5
			if s.mode != ActorState.Mode.LADDER:
				var me := BaseRegistry.world_position(s)
				var local := ladder.global_transform.affine_inverse() * me
				if absf(local.x) < 0.3 and local.z < 1.8 and local.y < 0.5:
					move = Vector2(0, 1)
				else:
					return ActorInput.make(tick, _walk_to(me, ladder.pose_at(0.0) + ladder.outward() * 1.2), 0.0, 0, _ladder_drop_presses)
			elif absf(s.anchor_t - target) > 0.05:
				move = Vector2(0, signf(target - s.anchor_t))
			elif _ladder_drop_phase == 0:
				_set_ladder_drop_phase(1)
				ladder_drops += 1
				buttons = ActorInput.BUTTON_CROUCH
			else:
				_ladder_drop_presses = (_ladder_drop_presses + 1) & 0xFF
				ladder_jumps += 1
				_set_ladder_drop_phase(4)
		1:  # con Ctrl, 15 ticks
			if _ladder_drop_since < 15:
				buttons = ActorInput.BUTTON_CROUCH
			else:
				_set_ladder_drop_phase(2)
		2:  # soltó Ctrl: a los dos ticks tiene que estar agarrado
			if _ladder_drop_since >= 2:
				if s.mode == ActorState.Mode.LADDER:
					ladder_drop_returns += 1
				_set_ladder_drop_phase(3)
		4:  # saltó: espera agarrarse otra vez, o el piso si falló
			if s.mode == ActorState.Mode.LADDER and _ladder_drop_since > 2:
				ladder_jump_returns += 1
				_set_ladder_drop_phase(0)
			elif s.mode == ActorState.Mode.GROUND and _ladder_drop_since > 2:
				_set_ladder_drop_phase(0)
	return ActorInput.make(tick, move, facing, buttons, _ladder_drop_presses)


func _set_ladder_drop_phase(phase: int) -> void:
	_ladder_drop_phase = phase
	_ladder_drop_since = 0


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
				# Soltándose con Ctrl, lo mantiene hasta el piso: al soltarlo, todavía
				# al alcance, se volvería a agarrar (como en la escalera, desde el
				# 2026-10-18).
				if _hook_cycle % 3 == 0 and _hook_since > HOOK_HOLD_TICKS:
					_set_hook_phase(7)
				else:
					_set_hook_phase(4 if _hook_cycle % 3 == 1 and _hook_since > HOOK_HOLD_TICKS else 6)
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
			elif s.mode == ActorState.Mode.HOOKED:
				hook_regrabs += 1
				_set_hook_phase(7)
			elif s.mode == ActorState.Mode.LADDER:
				_set_hook_phase(6)
			elif s.velocity.y <= 0.0:
				move = Vector2(0, 1)
		5:  # vuelve al lugar
			_hook_cycle += 1
			_set_hook_phase(0)
		6:  # saltó o se agarró de otra cosa: de la escalera baja alejándose; de un
			# borde, se suelta; si se volvió a agarrar de él, lo cuenta y se suelta
			yaw = to_wall
			if s.mode == ActorState.Mode.LADDER:
				move = Vector2(0, -1)
			elif s.mode == ActorState.Mode.HANGING:
				buttons = ActorInput.BUTTON_CROUCH
			elif s.mode == ActorState.Mode.HOOKED:
				hook_regrabs += 1
				_set_hook_phase(7)
			elif s.mode == ActorState.Mode.GROUND:
				_set_hook_phase(5)
		7:  # Ctrl hasta tocar el piso
			yaw = to_wall
			buttons = ActorInput.BUTTON_CROUCH
			if s.mode == ActorState.Mode.GROUND:
				_set_hook_phase(5)
	return ActorInput.make(tick, move, yaw, buttons, _hook_presses)


## Prueba `hook:cable`, en ciclos: espera a que haya un compañero quieto en un
## cable, se para a HOOK_CABLE_START de él, de su espalda, de su frente o de un
## costado (cambia en cada vuelta), salta hacia él y se cuelga. Colgado gira
## con D y sube con W, y a los HOOK_HOLD_TICKS, por turnos como en `hook:wall`,
## se suelta con Ctrl, salta para arriba mirándolo o salta hacia el otro lado.
## Soltándose con Ctrl, lo mantiene hasta tocar el piso; después de saltar, si
## se vuelve a agarrar de él al caer (como en la escalera), lo cuenta y se
## suelta igual. Si se agarra del cable, se suelta con Ctrl. Después vuelve.
func _hook_cable_input(tick: int) -> ActorInput:
	if not is_instance_valid(_local_actor):
		return ActorInput.make(tick, Vector2.ZERO, 0.0, 0, _hook_presses)
	var s := _local_actor.state
	var me := BaseRegistry.world_position(s)
	var mate: ActorBody = null
	for each in _local_actor.teammates():
		if each.state.mode == ActorState.Mode.CABLE:
			mate = each
	# Desde dónde salta, alrededor de él: su espalda, su frente y sus costados.
	var around: float = [0.0, PI, PI * 0.5, -PI * 0.5][_hook_cycle % 4]
	var to_mate := 0.0
	if mate != null:
		var to := mate.global_position - me
		to_mate = atan2(-to.x, -to.z)
	_hook_since += 1
	var move := Vector2.ZERO
	var yaw := 0.0
	var buttons := 0
	var phase := _hook_phase
	match _hook_phase:
		0:  # espera al compañero quieto en el cable y va a su espalda o a su frente
			if mate != null and mate.state.hooked_by == 0 and mate.state.velocity.length() < 0.001:
				var out := Vector3.BACK.rotated(Vector3.UP, mate.state.facing_yaw + around)
				var spot := mate.global_position + out * HOOK_CABLE_START
				# Desde donde se aparece, primero por delante de la torre chica.
				move = _walk_to(me, HOOK_CABLE_DETOUR if me.x < HOOK_CABLE_DETOUR.x - 0.5 and me.z < 15.0 else spot)
				if Vector2(me.x - spot.x, me.z - spot.z).length() < 0.15 and s.mode == ActorState.Mode.GROUND \
						and _horizontal(s) < 0.1:
					_hook_presses = (_hook_presses + 1) & 0xFF
					_set_hook_phase(1)
		1:  # en el aire, hacia él
			move = Vector2(0, 1)
			yaw = to_mate
			if s.mode == ActorState.Mode.HOOKED:
				hook_grabs += 1
				if mate == null or absf(angle_difference(around, ActorMotor.hook_angle(s, mate))) > 0.5:
					hook_wrong_side += 1
				_set_hook_phase(3)
			elif s.mode == ActorState.Mode.CABLE:
				hook_other_grabs += 1
				_set_hook_phase(6)
			elif s.mode == ActorState.Mode.GROUND and _hook_since > 20:
				_set_hook_phase(5)
		3:  # colgado del compañero
			yaw = to_mate
			if s.mode != ActorState.Mode.HOOKED:
				if _hook_since <= HOOK_HOLD_TICKS:
					hook_fell_with_mate += 1
					print("[net_lab] compañero: se cayó con él en el tick %d, %d ticks después de colgarse (%s)" % [
						tick, _hook_since, mate.state.describe() if mate != null else "el compañero ya no está en el cable"])
				# Soltándose con Ctrl, lo mantiene hasta el piso: al soltarlo, todavía
				# al alcance, se volvería a agarrar (como en la escalera).
				_set_hook_phase(7 if _hook_cycle % 3 == 0 else 6)
			elif _hook_since <= 25:
				# Gira con D, después sube con W.
				if _hook_since == 1 and mate != null:
					_hook_turn_from = ActorMotor.hook_angle(s, mate)
				move = Vector2(1, 0)
			elif _hook_since <= 40:
				if _hook_since == 26 and mate != null:
					hook_turned += rad_to_deg(angle_difference(_hook_turn_from, ActorMotor.hook_angle(s, mate)))
					_hook_climb_from = s.anchor_t
				move = Vector2(0, 1)
			elif _hook_since == 41:
				hook_climbed += s.anchor_t - _hook_climb_from
			elif _hook_since == HOOK_HOLD_TICKS:
				match _hook_cycle % 3:
					0:
						hook_releases += 1
					1:
						hook_jumps_up += 1
						_hook_presses = (_hook_presses + 1) & 0xFF
					2:
						hook_jumps_away += 1
						yaw = to_mate + PI
						_hook_presses = (_hook_presses + 1) & 0xFF
			if _hook_cycle % 3 == 0 and _hook_since >= HOOK_HOLD_TICKS:
				buttons = ActorInput.BUTTON_CROUCH
		5:  # vuelve a empezar
			_hook_cycle += 1
			_set_hook_phase(0)
		6:  # saltó: si se vuelve a agarrar de él, lo cuenta; de él o del cable, se suelta
			if s.mode == ActorState.Mode.HOOKED:
				hook_regrabs += 1
				_set_hook_phase(7)
			elif s.mode == ActorState.Mode.CABLE:
				_set_hook_phase(7)
			elif s.mode == ActorState.Mode.GROUND:
				_set_hook_phase(5)
		7:  # Ctrl hasta tocar el piso
			buttons = ActorInput.BUTTON_CROUCH
			if s.mode == ActorState.Mode.GROUND:
				_set_hook_phase(5)
	if phase != _hook_phase:
		print("[net_lab] colgarse del cable: tramo %d en %s, %s" % [_hook_phase, me, s.describe()])
	return ActorInput.make(tick, move, yaw, buttons, _hook_presses)


## Prueba de desconexión con alguien colgado: imprime el estado y cierra el
## juego sin despedirse, como si se cortara. Con --test-cut-hooked corta la red
## una sola vez, en vez de cerrar.
func _quit_while_hooked() -> void:
	if test_cut_when_hooked:
		if not _hooked_cut_done:
			_hooked_cut_done = true
			_cut_network()
		return
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
		_follow_world_slow_holders(tick)
		_change_world_slow(tick)
		_update_hooks()
	if role != Role.CLIENT or not _clock.client_sync:
		return
	_take_scheduled_events(tick)
	_take_world_slow(tick)
	_net_sync.apply_pending_snapshot(_on_own_state.bind(tick), _interpolation.add, _interpolation.add_base)
	_interpolation.advance()
	_update_platform_lag(tick)
	for actor in _clock.sorted_actors():
		if _is_remote(actor):
			_interpolation.place(actor)
	if is_instance_valid(_local_actor) and _clock.synced:
		if _host_silent():
			# Sin noticias del host: el actor propio queda quieto donde está. Lo
			# predicho hasta acá ya no se va a poder comparar.
			if _local_actor.simulated:
				_local_actor.simulated = false
				_prediction.clear()
				host_silences += 1
				print("[net_lab] sin noticias del host desde hace %d ms, en el tick %d: el actor propio queda quieto en %s" % [
					Time.get_ticks_msec() - _net_sync.last_snapshot_msec, tick, BaseRegistry.world_position(_local_actor.state)])
			return
		if not _local_actor.simulated:
			# Empieza (o vuelve) a predecir: los márgenes de inputs anteriores no
			# sirven para ajustar el adelanto.
			_prediction_start_tick = tick
		_local_actor.simulated = true
		_current_input = _local_input(tick)
		_add_player_presses(_current_input, tick)
		_apply_client_events(_local_actor.state, tick)


## Al terminar cada tick. Host: decide qué afirmaciones adopta y después manda
## el snapshot. Cliente: guarda lo predicho y se lo manda al host con el input.
func _on_tick_finished(tick: int) -> void:
	if role == Role.LOCAL and tick == test_pause_tick:
		_set_paused(true)
		print("[net_lab] pausa en el tick %d: %s" % [tick, _local_actor.state.describe() if is_instance_valid(_local_actor) else "sin actor"])
	if SimClock.world_scale(tick) < 1.0:
		slow_ticks_seen += 1
	for actor in _clock.sorted_actors():
		if actor.simulated and actor.state.powers != 0:
			var counted: Array = _power_ticks.get_or_add(actor.owner_peer_id, [0, 0])
			counted[0] += 1 if actor.state.powers & ActorPowers.BOOST else 0
			counted[1] += 1 if actor.state.powers & ActorPowers.SLOW else 0
	if role == Role.HOST:
		_mark_hooks_released()
		for actor in _clock.sorted_actors():
			if _is_remote(actor):
				_adoption.consider(actor, _net_sync.claim_for(actor.owner_peer_id, tick), tuning)
		var rafts := BaseRegistry.all().filter(func(base) -> bool: return base is HostRaft and base.simulated)
		_net_sync.send_snapshot(tick, _clock.sorted_actors(), rafts)
	elif role == Role.CLIENT and is_instance_valid(_local_actor) and _local_actor.simulated \
			and _current_input != null and _current_input.tick == tick:
		if test_perturb_mm > 0.0:
			_perturb(_local_actor)
		_prediction.record(tick, _current_input, _local_actor.state)
		_net_sync.send_ticks(_prediction.recent(NetSync.INPUT_REDUNDANCY), _clock.rtt_ms)
	elif role == Role.CLIENT and _clock.client_sync and tick % HEARTBEAT_TICKS == 0:
		# Sin predicción no sale ningún input: el host no tiene que creer que se cortó.
		_net_sync.send_ticks([], _clock.rtt_ms)
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
		# Con cámara lenta, cada tick avanza menos tiempo del mundo.
		var expected := speed / _clock.rate_hz * SimClock.world_scale(floori(_interpolation.shown_tick()))
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
		var expected := ActorMotor.hooked_pose(actor.state, _local_actor, tuning)
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
		var at := _scheduled_tick([peer])
		_host_events.append([at, peer, impulse, force])
		_net_sync.send_scheduled_event(peer, at, impulse, force)
	if scheduled:
		scheduled_pushes += 1
	else:
		pushes += 1
	print("[net_lab] empujón %s de fuerza %d en el tick %d" % ["programado" if scheduled else "inmediato", force, _clock.tick])


## Host: el tick para un evento programado que tiene que llegar a tiempo a
## estos jugadores: lo que tarda su input en llegar, más la ida y vuelta, más un
## colchón; con varios, el del más lejano.
func _scheduled_tick(peers: Array) -> int:
	var ahead := 0
	for peer in peers:
		var margin := maxi(_net_sync.input_margin_ticks(peer, _clock.tick), 0)
		var rtt_ticks := ceili(_net_sync.peer_rtt_ms(peer) * SimClock.TICK_RATE / 1000.0)
		ahead = maxi(ahead, margin + rtt_ticks)
	if test_schedule_ticks > 0:
		return _clock.tick + test_schedule_ticks
	return _clock.tick + ahead + SCHEDULE_BUFFER_TICKS


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
				_apply_event(actor.state, event[2], event[3])
				_log_push(actor, event[3], "programado")
	_host_events = waiting


## Un empujón programado sobre un estado, igual en el host y en el cliente.
func _apply_event(state: ActorState, impulse: Vector3, force: int) -> void:
	ActorMotor.apply_impulse(state, impulse, force, tuning)
	state.epoch += 1


## Host (y modo local): la cámara lenta del mundo va mientras al menos un
## jugador la pida (ActorPowers.SLOW en su estado, que prende y apaga su
## tecla, y que se apaga si se queda sin estamina, muere, se le corta la
## conexión o se va). Mira los pedidos al empezar cada tick y, solo cuando pasa
## de nadie a alguno o de alguno a nadie, la prende o la apaga para todos. Así
## dos pedidos no se anulan ni se suman: la escala es una sola, y un pedido que
## se retira no la corta si queda otro (hasta el 2026-11-01 cada pulsación de
## cualquiera prendía o apagaba el mismo tramo).
func _follow_world_slow_holders(tick: int) -> void:
	var holders := []
	for actor in _clock.sorted_actors():
		if not actor.is_queued_for_deletion() and actor.state.powers & ActorPowers.SLOW:
			holders.append(actor.owner_peer_id)
	if holders != _world_slow_holders:
		print("[net_lab] piden la cámara lenta del mundo en el tick %d: %s" % [tick, str(holders) if not holders.is_empty() else "nadie"])
		_world_slow_holders = holders
	var held := not holders.is_empty()
	if held == _world_slow_held:
		return
	_world_slow_held = held
	world_slow_requests += 1
	_schedule_world_slow(tick, held)


## Host: prende o apaga la cámara lenta del mundo para todos, con anticipación
## suficiente para el jugador más lejano, y lo anuncia. Apagar le pone fin al
## tramo abierto (si todavía no empezó, queda vacío). Prender abre un tramo
## nuevo que empieza después del fin del anterior; pero si ese fin todavía no
## llegó y se puede avisar a tiempo (otro la pidió justo cuando el anterior la
## soltaba), el tramo anterior se vuelve a abrir: un fin viejo no corta la
## cámara lenta, ni siquiera un tick. Como los pedidos se siguen de a un cambio
## por vez, nunca hay dos tramos abiertos ni superpuestos.
func _schedule_world_slow(tick: int, on: bool) -> void:
	var peers := []
	for actor in _clock.sorted_actors():
		if _is_remote(actor):
			peers.append(actor.owner_peer_id)
	var at := _scheduled_tick(peers)
	var spans := SimClock.world_slow_spans()
	var last: Array = spans[-1] if not spans.is_empty() else []
	var open: bool = not last.is_empty() and last[1] == SimClock.OPEN_END
	if on == open:
		return
	if not on:
		var end := maxi(at, last[0])
		SimClock.add_world_slow(last[0], end, last[2])
		_world_slow_changes[end] = true
		_net_sync.send_world_slow(last[0], end, NetSync.scale_to_steps(last[2]))
		world_slow_stopped += 1
		print("[net_lab] cámara lenta del mundo: ya nadie la pide en el tick %d; termina en el tick %d" % [tick, end])
		return
	if not last.is_empty() and last[1] >= at:
		SimClock.add_world_slow(last[0], SimClock.OPEN_END, last[2])
		_net_sync.send_world_slow(last[0], SimClock.OPEN_END, NetSync.scale_to_steps(last[2]))
		world_slow_started += 1
		print("[net_lab] cámara lenta del mundo: la piden %s en el tick %d; sigue el tramo del tick %d, que iba a terminar en el %d" % [
				_world_slow_holders, tick, last[0], last[1]])
		return
	var start := maxi(at, last[1] if not last.is_empty() else 0)
	var steps := NetSync.scale_to_steps(tuning.slow_scale)
	SimClock.add_world_slow(start, SimClock.OPEN_END, NetSync.steps_to_scale(steps))
	_world_slow_changes[start] = true
	_net_sync.send_world_slow(start, SimClock.OPEN_END, steps)
	world_slow_started += 1
	print("[net_lab] cámara lenta del mundo: la piden %s en el tick %d; empieza en el tick %d" % [_world_slow_holders, tick, start])


## Prueba, host: a los demás jugadores les quita 1000 de salud, como una
## cápsula letal (el mismo ActorVitals.apply): muerte de prueba.
func _harm_others() -> void:
	if role != Role.HOST:
		return
	for actor in _clock.sorted_actors():
		if _is_remote(actor):
			var died := ActorVitals.of(actor.state, tuning).apply(-1000, 0)
			print("[net_lab] prueba: daño de 1000 al jugador %d en el tick %d (%s)" % [actor.owner_peer_id, _clock.tick,
					"muerte de prueba" if died else "no murió"])


## Prueba, host: a los demás jugadores les pone un daño en el tiempo de
## `points` en `seconds`, como un consumible (el mismo ActorVitals.apply).
func _poison_others(points: int, seconds: float) -> void:
	if role != Role.HOST:
		return
	for actor in _clock.sorted_actors():
		var vitals := ActorVitals.of(actor.state, tuning)
		if _is_remote(actor) and vitals.has_room_for_effect():
			vitals.apply(0, 0, points, seconds)
			print("[net_lab] prueba: daño en el tiempo de %d en %.1f s al jugador %d en el tick %d" % [points, seconds,
					actor.owner_peer_id, _clock.tick])


## Host: a un jugador se le cortó la conexión y se lo espera (NetSession). Se
## le apagan los estados, como un evento del host: mientras no está no gasta
## estamina ni sostiene la cámara lenta de los demás. Al volver, sigue con su
## salud y su estamina, y prende lo que quiera con sus teclas (elección de
## Claude: el pedido no dice qué pasa en un corte).
func _on_player_waiting(peer_id: int) -> void:
	for actor in _clock.sorted_actors():
		if actor.owner_peer_id == peer_id and actor.state.powers != 0:
			ActorPowers.retire(actor.state)
			actor.state.epoch += 1
			print("[net_lab] al jugador %d se le cortó la conexión: se le apagan los estados" % peer_id)


## Host: al que se conecta le anuncia todos los tramos anotados, también los
## que ya pasaron. Las plataformas guionadas van por el tiempo del mundo: sin
## un tramo de antes de que llegara, las vería corridas para siempre.
func _announce_world_slow_to(peer_id: int) -> void:
	if role != Role.HOST:
		return
	for span in SimClock.world_slow_spans():
		_net_sync.send_world_slow(span[0], span[1], NetSync.scale_to_steps(span[2]), peer_id)


## Host: en el tick en que la cámara lenta empieza o termina, sube la época de
## todos. Un cliente que no se enteró a tiempo calculó esos ticks con la escala
## de antes, y su afirmación no se puede adoptar.
func _change_world_slow(tick: int) -> void:
	if not _world_slow_changes.has(tick):
		return
	for actor in _clock.sorted_actors():
		actor.state.epoch += 1
	print("[net_lab] %s la cámara lenta del mundo en el tick %d" % ["empieza" if SimClock.world_scale(tick) < 1.0 else "termina", tick])


## Cliente: anota los tramos de cámara lenta del mundo que anunció el host, y
## los fines de los que estaban prendidos. Si el tick del cambio ya se predijo
## (llegó tarde), repite desde ahí; si ya ni eso se puede, lo arregla la
## corrección del snapshot.
func _take_world_slow(tick: int) -> void:
	for span in _net_sync.received_world_slow:
		var changes := SimClock.add_world_slow(span[0], span[1], span[2])
		if changes.is_empty():
			continue
		for at in changes:
			_world_slow_changes[at] = true
		var first: int = changes.min()
		if first >= tick or not is_instance_valid(_local_actor) or not _local_actor.simulated:
			world_slow_on_time += 1
		elif _prediction.replay_from(_local_actor, first, tick, _step_local):
			world_slow_late += 1
		else:
			world_slow_too_late += 1
	_net_sync.received_world_slow.clear()


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


## Cliente: aplica a un estado los eventos programados de un tick, como el
## host: empujones y, si en ese tick empieza o termina la cámara lenta del
## mundo, la época. Va antes del paso de ese tick, también al repetir ticks.
func _apply_client_events(state: ActorState, tick: int) -> void:
	for event in _client_events.get(tick, []):
		_apply_event(state, event[0], event[1])
	if _world_slow_changes.has(tick):
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
		# Las pulsaciones ya vistas se conservan: si no, la próxima parece una
		# nueva. Lo que el jugador prendió sigue prendido, y la salud y la
		# estamina siguen igual.
		fresh.keep_player_state(actor.state)
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
		_local_actor.global_position = BaseRegistry.world_position(_local_actor.state)
		_local_actor.present(_local_actor.state)
		return
	_prediction.reconcile(_local_actor, host_tick, state_bytes, used_input_tick, current_tick, _step_local)


## Cliente: repite un tick del propio actor, igual que SimClock: los eventos
## del host, el uso de un consumible y el motor.
func _step_local(input: ActorInput) -> void:
	_apply_client_events(_local_actor.state, input.tick)
	_inventory.use_before_step(_local_actor, input)
	ActorMotor.step(_local_actor, _local_actor.state, input, tuning, SimClock.world_dt(input.tick))


## Host: quién cuelga de quién (ActorMotor.assign_hooks). Corre al empezar el
## tick, antes de mover a nadie. Anota también quién colgaba de quién al
## empezar, para _mark_hooks_released.
func _update_hooks() -> void:
	var result := ActorMotor.assign_hooks(_clock.sorted_actors(), tuning)
	hook_events += result[0]
	hook_kicks += result[1]
	_hooked_at_start.clear()
	for actor in _clock.sorted_actors():
		if actor.state.mode == ActorState.Mode.HOOKED:
			_hooked_at_start[actor.owner_peer_id] = actor.state.anchor_id


## Host, al terminar el tick y antes de adoptar: a quien el compañero soltó en
## este tick (se soltó él, lo empujaron o se fue) se le sube la época, como a un
## empujón. Su PC ve al compañero en el pasado y sigue afirmando que cuelga
## hasta enterarse. Sin esto, si el compañero se volvía a agarrar enseguida
## (Ctrl en la escalera), el host adoptaba esas afirmaciones atrasadas: lo
## volvía a colgar y dejaba quieto al compañero (2026-10-17).
func _mark_hooks_released() -> void:
	for actor in _clock.sorted_actors():
		var mate_id: int = _hooked_at_start.get(actor.owner_peer_id, 0)
		if mate_id != 0 and ActorMotor.hook_released_by_mate(actor, mate_id):
			actor.state.epoch += 1
			hooks_released += 1


## Cliente: el reloj saltó de tick. Lo predicho hasta ahora ya no sirve.
func _on_hard_resynced() -> void:
	_prediction.clear()
	_prediction_start_tick = _clock.tick + 1


func _on_local_actor_spawned(actor: ActorBody) -> void:
	_local_actor = actor
	# La cámara sigue lo que se ve, con el desvío de las correcciones incluido.
	_camera.target = actor.visual_root()
	_inventory_ui.activate(actor)
	_hud.activate(actor)
	if role == Role.CLIENT:
		# El contador de saltos arranca donde lo dejó el host: si se apretó
		# Espacio mientras estaba cortado, al volver no salta solo.
		jump_presses = actor.state.jump_presses_seen
		power_presses = actor.state.power_presses_seen
		ability_presses = actor.state.ability_presses_seen
		_inventory.use_presses = actor.state.use_presses_seen
	if _session.reconnects > 0:
		print("[net_lab] de vuelta, el actor propio es el %d en el tick %d: %s" % [actor.owner_peer_id, _clock.tick, actor.state.describe()])


## Cliente: hace más de HOST_SILENCE_MSEC que no llega ningún snapshot.
func _host_silent() -> bool:
	return _net_sync.last_snapshot_msec > 0 \
			and Time.get_ticks_msec() - _net_sync.last_snapshot_msec > HOST_SILENCE_MSEC


## Cliente: se cortó la conexión con el host. Lo predicho y lo recibido ya no
## sirven; la sesión reintenta sola y, al volver, todo arranca como al unirse.
func _on_connection_lost() -> void:
	_link.clear()
	_prediction.clear()
	_current_input = null
	_net_sync.reset_client()
	_interpolation.clear()
	_client_events.clear()
	_remote_last_positions.clear()
	# Primero el inventario: así la interfaz, al cerrarse, no le pide nada al host.
	_inventory.connection_lost()
	_inventory_ui.connection_lost()
	_hud.connection_lost()
	_flash("Se cortó la conexión con el host: reconectando…")


## Prueba de reconexión: con relevo, se corta el relevo, como un cable. Sin
## relevo, esta máquina deja de atender la red: lo que llega no se lee y lo
## confiable no sale, como una PC trabada.
func _cut_network() -> void:
	print("[net_lab] corte de red de prueba (%s) por %.1f s en el tick %d: %s" % [
			"cable" if _relay != null else "máquina trabada", test_cut_seconds, _clock.tick,
			_local_actor.state.describe() if is_instance_valid(_local_actor) else "sin actor propio"])
	if _relay != null:
		_relay.cut = true
	else:
		get_tree().multiplayer_poll = false
	_real_timer(test_cut_seconds, func() -> void:
		if _relay != null:
			_relay.cut = false
		else:
			get_tree().multiplayer_poll = true
		print("[net_lab] vuelve la red de prueba en el tick %d" % _clock.tick))


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
		elif arg.begins_with("--test-world-slow-at="):
			for seconds in arg.trim_prefix("--test-world-slow-at=").split(","):
				test_world_slow_seconds.append(seconds.to_float())
		elif arg.begins_with("--test-harm-at="):
			for seconds in arg.trim_prefix("--test-harm-at=").split(","):
				test_harm_seconds.append(seconds.to_float())
		elif arg.begins_with("--test-poison-at="):
			for item in arg.trim_prefix("--test-poison-at=").split(","):
				var parts := item.split(":")
				test_poisons.append([parts[0].to_float(), parts[1].to_int() if parts.size() > 1 else 20,
						parts[2].to_float() if parts.size() > 2 else 4.0])
		elif arg.begins_with("--test-power-at="):
			for seconds in arg.trim_prefix("--test-power-at=").split(","):
				test_power_seconds.append(seconds.to_float())
		elif arg.begins_with("--test-cut-at="):
			for seconds in arg.trim_prefix("--test-cut-at=").split(","):
				test_cut_seconds_at.append(seconds.to_float())
		elif arg.begins_with("--test-tuning="):
			var pair := arg.trim_prefix("--test-tuning=").split("=")
			test_tuning[pair[0]] = str_to_var(pair[1])
		elif arg.begins_with("--test-relay="):
			test_relay_port = arg.trim_prefix("--test-relay=").to_int()
		elif arg == "--test-cut-hooked":
			test_cut_when_hooked = true
		elif arg.begins_with("--test-cut-for="):
			test_cut_seconds = arg.trim_prefix("--test-cut-for=").to_float()
		elif arg.begins_with("--reconnect-wait="):
			_session.reconnect_wait = arg.trim_prefix("--reconnect-wait=").to_float()
		elif arg.begins_with("--test-pause-at="):
			test_pause_tick = arg.trim_prefix("--test-pause-at=").to_int()
		elif arg.begins_with("--test-spawn-at="):
			var xz := arg.trim_prefix("--test-spawn-at=").split(",")
			_session.host_spawn_override = Vector3(xz[0].to_float(), 0.0, xz[1].to_float())


## Direcciones IPv4 de esta PC que hay que escribir en la otra para unirse, una
## por renglón y con el nombre de su conexión: las de la red local (en la misma
## casa) y las de Tailscale (100.64 a 100.127) y Radmin VPN (26), para jugar
## cada uno desde su casa.
func _lan_addresses() -> String:
	var found := PackedStringArray()
	for interface in IP.get_local_interfaces():
		for address: String in interface["addresses"]:
			var parts := address.split(".")
			if parts.size() != 4:
				continue
			var second := parts[1].to_int()
			if (parts[0] == "192" and parts[1] == "168") or parts[0] == "10" or (parts[0] == "172" and second >= 16 and second <= 31) \
					or (parts[0] == "100" and second >= 64 and second <= 127) or parts[0] == "26":
				found.append("%s: %s" % [interface["friendly"], address])
	return "\n".join(found) if not found.is_empty() else "no encontrada"


func _update_hud() -> void:
	var lines := PackedStringArray([
		_session.status,
		"tick %d   ·   actores: %s" % [_clock.tick, _actor_ids()],
		"red simulada: %s   ·   Alt + 1 a 5 para cambiarla" % _net_sim_text(),
	])
	if role == Role.CLIENT and _session.reconnecting:
		lines.append("SIN CONEXIÓN CON EL HOST   ·   reintenta solo   ·   se rinde en %d s" % maxi(ceili(_session.give_up_left()), 0))
	elif role == Role.CLIENT and _clock.client_sync and _host_silent():
		lines.append("SIN NOTICIAS DEL HOST hace %.1f s   ·   tu personaje queda quieto hasta que vuelvan" % [
				(Time.get_ticks_msec() - _net_sync.last_snapshot_msec) / 1000.0])
	if role == Role.CLIENT:
		lines.append("reloj: ida y vuelta %.0f ms   ·   vas %.1f ticks adelante del host   ·   saltos de reloj %d" % [_clock.rtt_ms, _clock.lead_ticks, _clock.resyncs])
		lines.append("tu input le llega al host con %.1f ticks de anticipación, en el peor caso   ·   ritmo: %d ticks por segundo (ganados +%.1f / perdidos -%.1f)" % [_clock.worst_margin, _clock.rate_hz, _clock.ticks_gained, _clock.ticks_shed])
		lines.append("predicción: %d coincidencias, %d correcciones (la última de %.2f m), %d esperas por input tardío" % [_prediction.matches, _prediction.corrections, _prediction.last_correction_meters, _prediction.waits_late_input])
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
				var left := _session.waiting_left(peer)
				if left >= 0.0:
					lines.append("jugador %d: se le cortó la conexión   ·   queda quieto y lo espero %d s más" % [peer, ceili(left)])
					continue
				lines.append("jugador %d: su input llega con %d ticks de anticipación   ·   época %d" % [peer, _net_sync.input_margin_ticks(peer, _clock.tick), actor.state.epoch])
				lines.append("      afirmaciones: %d adoptadas (la más lejana a %.2f m), rechazadas %d por época, %d por distancia, %d por pose, %d por datos imposibles" % [
					_adoption.count(peer, ClaimAdoption.Result.ADOPTED), _adoption.max_difference(peer),
					_adoption.count(peer, ClaimAdoption.Result.WRONG_EPOCH), _adoption.count(peer, ClaimAdoption.Result.TOO_FAR),
					_adoption.count(peer, ClaimAdoption.Result.BAD_POSE), _adoption.count(peer, ClaimAdoption.Result.BAD_VALUES),
				])
	var world_slow := _world_slow_text()
	if world_slow != "":
		lines.append(world_slow)
	if is_instance_valid(_local_actor):
		var s := _local_actor.state
		if _clock.paused:
			lines.append("EN PAUSA (tick %d)   ·   G sigue   ·   F avanza un tick" % _clock.tick)
		var vitals := ActorVitals.of(s, tuning)
		var spending := ActorPowers.cost_per_second(s.powers, tuning)
		lines.append("Salud %.1f / %d   ·   estamina %.1f / %d%s   ·   muertes de prueba %d" % [vitals.health(), vitals.health_max(),
				vitals.stamina(), vitals.stamina_max(),
				"   ·   gastando %.1f por segundo (%s)" % [spending, ", ".join(ActorPowers.names(s.powers))] if s.powers != 0 else "",
				s.deaths])
		var effects := vitals.effects_left()
		if effects[2] > 0:
			lines.append("DAÑO EN EL TIEMPO: %d encima   ·   quitan %.1f de salud más   ·   el más largo termina en %.1f s del mundo" % [
					effects[2], effects[0], effects[1]])
		if s.boosted:
			lines.append("SÚPER SALTO Y VELOCIDAD: prendido   ·   2 del teclado numérico lo apaga")
		lines.append("Modo: %s   ·   en suelo: %s   ·   época: %d" % [ActorState.Mode.keys()[s.mode], "sí" if s.on_floor else "no", s.epoch])
		if s.ladder_return != 0:
			var back_to := Ladder.find(s.ladder_return)
			lines.append("Volvés solo a la escalera %s al bajar, frente a ella   ·   no con Ctrl; A o D la cancelan" % (String(back_to.name) if back_to != null else str(s.ladder_return)))
		if s.straight_out:
			lines.append("Saliste de la escalera mirando atrás: derecho con W sola   ·   soltar W, A, S, D o girar la cámara lo corta")
		if s.mode == ActorState.Mode.AIR:
			lines.append("Salto en el aire: %s" % ("ya saltaste: vuelve al tocar el piso o agarrarte de algo" if s.jumped
					else "listo, Espacio cayendo" if s.velocity.y <= 0.0 else "listo cuando empieces a caer"))
		var stance_names := ["parado", "agachado", "encogido"]
		lines.append("Postura: %s%s" % [stance_names[s.stance],
				"   ·   pedida: %s (no hay lugar)" % stance_names[s.stance_wanted] if s.stance_wanted != s.stance else ""])
		if s.mode == ActorState.Mode.LADDER:
			var ladder := Ladder.find(s.anchor_id)
			lines.append("Escalera %s   ·   pies a %.2f m sobre su base" % [String(ladder.name) if ladder != null else str(s.anchor_id), s.anchor_t])
		elif s.mode == ActorState.Mode.HANGING:
			lines.append("Colgado del borde: filo a %.2f m de altura%s" % [BaseRegistry.origin(s.anchor_id).y + s.anchor_point.y,
					"   ·   sobre la base %d" % s.anchor_id if s.anchor_id != 0 else ""])
		elif s.mode == ActorState.Mode.MANTLE:
			lines.append("Mantle: subiendo al borde, filo a %.2f m de altura%s%s" % [BaseRegistry.origin(s.anchor_id).y + s.anchor_point.y,
					"   ·   agachado: arriba no cabés parado" if s.stance == ActorState.Stance.CROUCHED else "",
					"   ·   sobre la base %d" % s.anchor_id if s.anchor_id != 0 else ""])
		elif s.mode == ActorState.Mode.HOOKED:
			var mate := _local_actor.teammate(s.anchor_id) if is_instance_valid(_local_actor) else null
			if mate != null:
				var where := "en un cable: girás todo alrededor" if mate.state.mode == ActorState.Mode.CABLE \
						else "en %s: girás hasta %.0f° por lado" % ["una escalera" if mate.state.mode == ActorState.Mode.LADDER else "un borde",
						rad_to_deg(tuning.hook_turn_limit)]
				lines.append("Colgado del jugador %d, %s   ·   manos a %.2f m sobre sus pies   ·   a %.0f° de su espalda   ·   W/S suben y bajan, A/D giran" % [
						s.anchor_id, where, s.anchor_t, rad_to_deg(ActorMotor.hook_angle(s, mate))])
			else:
				lines.append("Colgado del jugador %d" % s.anchor_id)
		elif s.mode == ActorState.Mode.CABLE:
			var cable := Cable.find(s.anchor_id)
			var slope := absf(rad_to_deg(asin(clampf(cable.tangent_at(s.anchor_t).y, -1.0, 1.0)))) if cable != null else 0.0
			lines.append("Colgado del cable %s   ·   a %.2f m de su punta   ·   inclinación %.0f°%s" % [String(cable.name) if cable != null else str(s.anchor_id), s.anchor_t, slope,
					("   ·   te deslizás: soltá las teclas para frenar" if s.velocity.length() > tuning.cable_speed + 0.01
					else "   ·   las teclas hacia abajo te deslizan") if slope >= rad_to_deg(tuning.cable_slide_angle) else ""])
		elif s.regrab_left > 0.0 and s.regrab_id == ActorState.REGRAB_CABLES:
			lines.append("Recién soltó un cable: no puede agarrar otro ni colgarse de un compañero por %.2f s" % s.regrab_left)
		elif s.regrab_left > 0.0 and s.regrab_id == ActorState.REGRAB_EDGES:
			lines.append("Recién soltó un borde: no puede agarrar otro ni un cable por %.2f s" % s.regrab_left)
		elif s.regrab_left > 0.0 and s.regrab_id == ActorState.REGRAB_TEAMMATES:
			lines.append("Recién se soltó de un compañero: no se puede colgar de otro ni agarrar un cable por %.2f s" % s.regrab_left)
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
	lines.append("WASD mover · Espacio saltar · Shift correr · Ctrl agacharse (corriendo: deslizarse, mientras lo mantengas)")
	lines.append("Mouse mirar · rueda acerca la cámara, hasta primera persona · Esc suelta el mouse")
	lines.append("Escalera: W sube y S baja, mire donde mire · Espacio mirándola salta para arriba y te volvés a agarrar al bajar, mirando a otro lado salta hacia allá")
	lines.append("Escalera: al salir por arriba seguís derecho con W sola · Ctrl te suelta: caés mientras lo tengas y al soltarlo te agarrás")
	lines.append("Colgado: A y D de costado · Espacio mirando a la pared salta para arriba (con W pasás arriba), mirando a otro lado salta hacia allá · Ctrl se suelta")
	lines.append("Mantle: subiendo en un salto, mirando un borde con el filo entre %.1f y %.1f m sobre tus pies, subís solo, hacia donde apuntan las teclas · Ctrl te suelta" % [
			tuning.mantle_min_height, tuning.mantle_max_height])
	lines.append("Cable: te agarrás solo · teclas según la cámara · hacia abajo en uno inclinado te deslizás, soltar frena · Espacio salta hacia donde mirás · Ctrl se suelta")
	lines.append("Cayendo sin haber saltado (te caíste, te soltaste, te empujaron): Espacio salta en el aire, una vez, hacia donde mira la cámara")
	lines.append("Compañero colgado de un borde, una escalera o un cable: tocándolo te colgás de él · Espacio y Ctrl, igual que colgado")
	lines.append("Colgado de un compañero: W/S suben y bajan, A/D giran alrededor (en borde y escalera, solo por su espalda)")
	lines.append("1 del teclado numérico: pedís o soltás la cámara lenta del mundo (va lenta mientras alguno la pida) · 2 del teclado numérico: tu súper salto y velocidad · los dos gastan tu estamina")
	if role == Role.HOST:
		lines.append("Y empuja a los demás ya · U los empuja programado · con Shift, empujón débil · Q prende o apaga la adopción")
	if role == Role.LOCAL:
		lines.append("G pausa y congela · F avanza un tick en pausa")
	lines.append("Tab abre el inventario · E recoge un objeto o abre una caja · 1 a 9 y 0: barra rápida (usa o equipa)")
	lines.append("F12 guarda una captura en el Escritorio · F1 oculta este panel y lo vuelve a mostrar")
	if Time.get_ticks_msec() < _flash_until_msec:
		lines.insert(0, ">> %s" % _flash_text)
	_info.text = "\n".join(lines)


## La línea del panel de la cámara lenta del mundo: andando, por empezar o nada.
func _world_slow_text() -> String:
	var tick := _clock.tick
	for span in SimClock.world_slow_spans():
		if tick >= span[0] and tick < span[1]:
			var mine: bool = is_instance_valid(_local_actor) and (_local_actor.state.powers & ActorPowers.SLOW) != 0
			if span[1] == SimClock.OPEN_END:
				return "CÁMARA LENTA DEL MUNDO: al %d %%   ·   %s" % [roundi(span[2] * 100.0),
						"la pedís vos: el 1 del teclado numérico la suelta" if mine else "la pide otro jugador: el 1 del teclado numérico la pide también"]
			return "CÁMARA LENTA DEL MUNDO: al %d %%   ·   se apaga en %.2f s" % [roundi(span[2] * 100.0), (span[1] - tick) * SimClock.TICK_DT]
		if tick < span[0] and span[0] < span[1]:
			return "Cámara lenta del mundo en %.2f s" % ((span[0] - tick) * SimClock.TICK_DT)
	return ""


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
		print("[net_lab] traza %.1fs actor: base=%d mundo=%s rel=%s vel=%s modo=%s postura=%s suelo=%s ancla=%d t=%.3f época=%d escala_mundo=%.2f" % [
			(Time.get_ticks_msec() - _ready_msec) / 1000.0, s.base_id, BaseRegistry.world_position(s),
			s.position, s.velocity, ActorState.Mode.keys()[s.mode], ActorState.Stance.keys()[s.stance], s.on_floor,
			s.anchor_id, s.anchor_t, s.epoch, SimClock.world_scale(_clock.tick),
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
	print("[net_lab] resumen: rol=%s tick=%d actores=%s máximo=%d sincronizado=%s ida_y_vuelta=%.1fms adelanto=%.1f peor_margen=%.1f ritmo=%d ganados=+%.1f perdidos=-%.1f saltos_de_reloj=%d coincidencias=%d correcciones=%d esperas_input_tardío=%d alineaciones=%d afirmaciones_viejas_adoptadas=%d snapshots_perdidos=%.1f%% red=%s paquetes_perdidos_por_el_simulador=%d" % [
		Role.keys()[role], _clock.tick, _actor_ids(), max_actors_seen, _clock.synced,
		_clock.rtt_ms, _clock.lead_ticks, _clock.worst_margin, _clock.rate_hz, _clock.ticks_gained, _clock.ticks_shed, _clock.resyncs,
		_prediction.matches, _prediction.corrections, _prediction.waits_late_input, _prediction.alignments, _prediction.adopted_old_claims,
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
	if not test_cut_seconds_at.is_empty() or _session.reconnects > 0 or _session.players_back > 0 or _session.players_dropped > 0:
		print("[net_lab] reconexión: el cliente volvió %d veces (%d intentos en el último corte, reconectando=%s, quieto sin noticias del host %d veces); en el host, %d jugadores volvieron y %d no volvieron a tiempo" % [
			_session.reconnects, _session.reconnect_attempts, _session.reconnecting, host_silences, _session.players_back, _session.players_dropped])
	if _relay != null:
		print("[net_lab] relevo de prueba: %d paquetes pasaron, %d se tiraron en los cortes" % [_relay.forwarded, _relay.dropped])
	if test_input == "airjump":
		print("[net_lab] salto en el aire: %d saltos" % air_jumps)
	if test_input.begins_with("laddertop") and is_instance_valid(_local_actor):
		print("[net_lab] escalera: termina en %s" % _local_actor.state.describe())
	if test_input == "cable" or test_input == "cablehold":
		print("[net_lab] cable: %d agarres, %d frenadas a mitad de camino, %d bajadas hasta la punta, subió %.2f m en total; tramo %d" % [cable_grabs, cable_stops, cable_slides, cable_climbed, _cable_phase])
	if test_input == "tunnel":
		print("[net_lab] túnel: llegó al tramo %d; ticks parado bajo el techo: %d" % [_tunnel_phase, _tunnel_standing_under_roof])
	if test_input == "steps":
		print("[net_lab] escalones: punto %d de %d; pies a %.2f m como máximo" % [_steps_index, STEPS_ROUTE.size(), _steps_max_height])
	if test_input == "hang" or test_input == "hangcorner" or test_input == "hanginner" or test_input.begins_with("hang:"):
		print("[net_lab] colgar: %d agarres, %d subidas al borde, %d vueltas del ciclo, %d esquinas dobladas (%d por adentro)" % [
				hang_grabs, hang_climbs, _hang_cycle, hang_corners, hang_corners_inside])
	if test_input == "mantle" or test_input.begins_with("mantle:"):
		print("[net_lab] mantle: %d empezados, %d terminaron arriba, %d vueltas bajándose por delante" % [mantle_starts, mantle_tops, mantle_cycles])
	if test_input.begins_with("hook:"):
		print("[net_lab] compañero: %d se colgó, %d se soltó con Ctrl, %d saltó para arriba (%d se agarró del borde después, %d llegó arriba), %d saltó hacia atrás, %d se cayó con el compañero, %d se agarró de otra cosa, %d se volvió a agarrar de él después de saltar" % [
			hook_grabs, hook_releases, hook_jumps_up, hook_edges_after, hook_tops, hook_jumps_away, hook_fell_with_mate, hook_other_grabs, hook_regrabs])
	if test_input == "hook:cable":
		print("[net_lab] compañero en un cable: %d vueltas, %d del lado que no buscaba; colgado giró %.0f° con D y subió %.2f m con W, en total; %d veces se volvió a agarrar de él después de saltar; tramo %d" % [
			_hook_cycle, hook_wrong_side, hook_turned, hook_climbed, hook_regrabs, _hook_phase])
	if test_input == "ladderdrop" or test_input == "ladderhold:drop":
		print("[net_lab] escalera: se soltó %d veces con Ctrl (%d con alguien colgado) y se volvió a agarrar solo %d; saltó mirándola %d veces y se volvió a agarrar solo %d" % [
				ladder_drops + hook_drops, hook_drops, ladder_drop_returns, ladder_jumps, ladder_jump_returns])
	if test_input.begins_with("hookwall"):
		print("[net_lab] compañero de arriba: tramo %d, se soltó %d veces con alguien colgado" % [_hook_phase, hook_drops])
	if role != Role.CLIENT and (hook_events > 0 or hook_kicks > 0):
		print("[net_lab] host: %d cambios de quién cuelga de quién, %d soltados por colgarse dos del mismo, %d soltados por el compañero (época nueva)" % [hook_events, hook_kicks, hooks_released])
	if world_slow_requests > 0 or world_slow_on_time + world_slow_late + world_slow_too_late > 0:
		print("[net_lab] cámara lenta del mundo: %d pedidas, %d veces prendida, %d apagada; en el cliente, %d cambios a tiempo, %d tarde (repetido desde su tick), %d demasiado tarde" % [
			world_slow_requests, world_slow_started, world_slow_stopped, world_slow_on_time, world_slow_late, world_slow_too_late])
	if not SimClock.world_slow_spans().is_empty():
		print("[net_lab] tramos de cámara lenta del mundo [inicio, fin, escala]: %s" % [SimClock.world_slow_spans()])
		# Con una sola escala, el tiempo del mundo es los ticks menos lo que
		# frenaron los ticks lentos: si se descontara dos veces, no daría.
		print("[net_lab] tiempo del mundo: %.2f ticks en %d ticks, %d de ellos lentos (con una sola escala, %.2f)" % [
				SimClock.world_ticks(_clock.tick), _clock.tick, slow_ticks_seen,
				_clock.tick - slow_ticks_seen * (1.0 - NetSync.steps_to_scale(NetSync.scale_to_steps(tuning.slow_scale)))])
	for actor in _clock.sorted_actors():
		var counted: Array = _power_ticks.get(actor.owner_peer_id, [0, 0])
		print("[net_lab] estados del jugador %d: salud %.3f, daño en el tiempo %s, estamina %.3f, prendidos %s, muertes %d, agotamientos %d; ticks con el súper %d, con su pedido de cámara lenta %d" % [
				actor.owner_peer_id, actor.state.health / float(ActorState.HEALTH_UNIT), actor.state.effect_total,
				actor.state.stamina / float(ActorPowers.STAMINA_UNIT),
				ActorPowers.names(actor.state.powers), actor.state.deaths, actor.state.exhaustions, counted[0], counted[1]])
	print("[net_lab] HUD: %d avisos de muerte, %d sonidos de agotamiento, luces prendidas al final: %s" % [_hud.deaths_shown,
			_hud.exhaustion_sounds, _hud.lit_powers().map(func(power: Dictionary) -> String: return power["name"])])
	if hooked_gap_max > 0.0 or test_input.begins_with("hookwall") or test_input.begins_with("ladderhold"):
		print("[net_lab] el que cuelga de este jugador se dibujó a %.3f m como máximo de la pose que le da el cuerpo de este jugador" % hooked_gap_max)
	if role == Role.CLIENT:
		print("[net_lab] correcciones: la más grande de %.3f m" % _prediction.max_correction_meters)
	for peer in _adoption.peers():
		print("[net_lab] adopción del jugador %d: prendida=%s empujones=%d iguales=%d adoptadas=%d (máx %.3f m) rechazadas: época=%d distancia=%d pose=%d datos_imposibles=%d apagada=%d sin_afirmación=%d" % [
			peer, _adoption.enabled, pushes,
			_adoption.count(peer, ClaimAdoption.Result.SAME),
			_adoption.count(peer, ClaimAdoption.Result.ADOPTED), _adoption.max_difference(peer),
			_adoption.count(peer, ClaimAdoption.Result.WRONG_EPOCH),
			_adoption.count(peer, ClaimAdoption.Result.TOO_FAR),
			_adoption.count(peer, ClaimAdoption.Result.BAD_POSE),
			_adoption.count(peer, ClaimAdoption.Result.BAD_VALUES),
			_adoption.count(peer, ClaimAdoption.Result.OFF),
			_adoption.count(peer, ClaimAdoption.Result.NO_CLAIM),
		])
	# Cerrar al final de la prueba es irse a propósito, como cerrar la ventana.
	_session.say_goodbye()
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
