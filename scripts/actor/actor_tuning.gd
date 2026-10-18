class_name ActorTuning
extends Node

## Parámetros de movimiento del actor. Son valores de partida, a calibrar.
##
## Es el nodo Tuning de la escena del laboratorio (net_lab.tscn): los valores
## se cambian ahí, en el Inspector, y todos los actores se mueven con ellos.
##
## Host y clientes tienen que tener exactamente los mismos valores: si
## difieren, la predicción diverge sin que nada lo avise. Por eso se cambian
## con el juego cerrado, y las dos máquinas tienen que tener la misma versión
## de la escena.

## Escena del nodo Tuning que usa el juego.
const SCENE_PATH := "res://scenes/net_lab/net_lab.tscn"

@export_group("Suelo")
@export var walk_speed := 5.0
## Aceleración hacia la velocidad pedida, en m/s².
@export var ground_accel := 45.0
## Frenado cuando no hay input, en m/s².
@export var ground_decel := 60.0
## Distancia de snap al piso mientras el modo es Suelo, en metros.
@export var floor_snap_length := 0.3
## Velocidad corriendo; solo con postura parada.
@export var sprint_speed := 8.0
## Velocidad con postura agachada.
@export var crouch_speed := 2.5
## Escalón más alto que sube caminando, en metros. Igual al snap, así sube y
## baja los mismos escalones. 0 lo apaga.
@export var step_height := 0.3

@export_group("Deslizamiento")
## Rapidez horizontal mínima para empezar a deslizarse desde Suelo, en m/s.
@export var slide_entry_speed := 6.0
## Por debajo de esta rapidez el deslizamiento termina y vuelve a Suelo.
@export var slide_min_speed := 2.5
@export var slide_max_speed := 12.0
## Frenado por rozamiento, en m/s².
@export var slide_friction := 4.0
## Cuánto puede girar la dirección del deslizamiento, en radianes por segundo.
@export var slide_turn_rate := 1.5

@export_group("Escalera")
## Velocidad de trepada, en m/s.
@export var climb_speed := 2.5
## Aceleración sobre el eje de la escalera, en m/s².
@export var climb_accel := 20.0
## Al saltar de la escalera mirando a otro lado (a más de climb_look_angle de
## ella): velocidad hacia donde mira, sin la parte que iría contra la pared, y
## hacia arriba, en m/s.
@export var ladder_jump_out := 3.0
@export var ladder_jump_up := 3.5
## Al saltar de la escalera mirándola (a menos de climb_look_angle): salta
## derecho para arriba, y los pies suben este tanto más que en un salto desde
## el piso, en metros.
@export var ladder_jump_extra := 1.0
## Al soltar un ancla por un salto o un empujón, cuánto tiempo no se la puede
## volver a agarrar, en segundos de tiempo del actor.
@export var regrab_block_time := 0.4
## Al salir por arriba, con un saltito sobre el borde: cuánto suben los pies
## por encima del tope, en metros, y la velocidad hacia adentro, en m/s.
@export var ladder_top_hop_height := 0.2
@export var ladder_top_hop_speed := 2.5

@export_group("Borde")
## Colgado: altura del filo sobre los pies, que es también la altura de las
## manos al buscar un borde, y distancia del centro del cuerpo a la pared.
@export var hang_height := 1.95
@export var hang_distance := 0.4
## Distancia máxima del snap al agarrarse, en metros.
@export var hang_snap_max := 0.35
## Subiendo, agarra recién cuando las manos llegan al filo: la pose de colgado
## no puede quedar más que esto por encima de los pies, en metros. Así no tira
## del cuerpo para arriba.
@export var hang_rise_reach := 0.1
## Desplazarse colgado, en m/s.
@export var shimmy_speed := 1.5
## Saltar colgado: velocidad hacia donde mira y hacia arriba, en m/s.
@export var hang_jump_out := 4.0
@export var hang_jump_up := 4.0
## Bloqueo de reagarre de bordes al soltarse o saltar, en segundos.
@export var hang_regrab_time := 0.3
## Colgado, Espacio salta derecho para arriba (para subir al borde con el
## control aéreo) si la mirada está a menos de este ángulo de la pared; si no,
## salta hacia donde mira.
@export var climb_look_angle := deg_to_rad(60.0)
## Ese salto para arriba lleva los pies hasta este tanto por encima del filo,
## en metros: el margen para pasar arriba del borde con el control aéreo.
@export var hang_climb_clearance := 0.2
## En ese salto el cuerpo se encoge este tanto desde abajo, en metros: la
## cabeza queda donde estaba y suben los pies. Así los pies pasan el filo con
## más margen sin que se salte más alto. Vuelve a su alto al tocar el piso o
## al agarrarse de algo. 0 lo apaga.
@export_range(0.0, 1.0, 0.01) var hang_climb_tuck := 0.2
## Colgado, al doblar un rincón (una esquina por adentro) el cuerpo hace una
## curva de este radio, en metros: empieza a doblar este tanto antes de llegar
## al rincón, y a mitad de la curva queda un poco más lejos de las paredes.
## Con 0,4 la curva es tan larga como la vuelta a una esquina por afuera.
@export_range(0.05, 1.0, 0.01) var hang_corner_radius := 0.4

@export_group("Cable")
## Colgado de un cable, el cuerpo cuelga hang_height por debajo de las manos, de
## frente al cable. Las teclas se toman según la cámara, como caminando, y lo
## mueven a lo largo del cable hacia donde apuntan, a shimmy_speed (grupo
## Borde): mirando a lo largo del cable, W y S; mirándolo de costado, A y D.
## Sin teclas se queda quieto, esté como esté inclinado el cable.
##
## Se agarra sin tecla si en un tick el cable toca la parte de arriba del
## cuerpo (ver cable_grab_body) o las manos, a no más de esto del eje del
## cuerpo, en metros: el radio del cilindro que detecta el cable. El cuerpo
## tiene 0,35; con 0,4 el cilindro sobresale 5 cm alrededor.
@export_range(0.05, 1.0, 0.01) var cable_reach := 0.4
## Qué parte del cuerpo de parado, desde la cabeza para abajo, agarra el cable:
## con 0,5, de la mitad para arriba; con 0,3, el 30 % de arriba. Lo de arriba
## no cambia: siempre cuenta hasta las manos, 15 cm por encima de la cabeza. El
## cuerpo queda colgado de las manos, así que si el cable lo toca más abajo, el
## cuerpo baja de golpe hasta que las manos llegan al cable: con 0,5, hasta
## 1,05 m; con 0,3, hasta 0,69 m. Más chico se ve mejor pero hay que caer más
## justo.
@export_range(0.0, 1.0, 0.01) var cable_grab_body := 0.5
## Si el cable está más inclinado que esto, las teclas hacia donde baja lo
## hacen deslizarse.
@export_range(0.0, 89.0, 0.1, "radians_as_degrees") var cable_slide_angle := deg_to_rad(15.0)
## Las teclas mueven por el cable si apuntan (según la cámara) a menos de
## este ángulo del cable, para un lado o para el otro; más de costado, no
## hacen nada. Con 60°: mirando a menos de 60° del cable sirven W y S, y a
## menos de 60° de mirarlo de costado, A y D; en el medio, todas.
@export_range(1.0, 90.0, 0.1, "radians_as_degrees") var cable_move_angle := deg_to_rad(60.0)
## Deslizándose, la velocidad a la que llega es esta por el seno de la
## inclinación, en m/s: a 25°, unos 5 m/s; a 45°, unos 8,5 m/s. Acelera con la
## gravedad sobre el cable.
@export var cable_slide_speed := 12.0
## En un cable más inclinado que cable_slide_angle, las teclas hacia arriba lo
## suben a esta velocidad, en m/s: más lento que en uno plano.
@export var cable_climb_speed := 0.75
## Frenado al dejar de deslizarse (soltar las teclas, apretar las de para
## arriba, o que el cable se aplane), en m/s²: con 12, de 5 m/s queda quieto en
## unos 0,4 s. Apretando las de para arriba, después de frenar sube.
@export var cable_brake := 12.0

@export_group("Compañero")
## Colgarse de un compañero que está agarrado de un borde, de una escalera o de
## un cable (modo Enganchado). Las manos van a la cintura: esta altura sobre
## sus pies, en metros. El cuerpo cuelga hang_height por debajo de las manos.
@export var hook_height := 1.0
## Distancia de centro a centro, de espaldas a la pared: los dos cuerpos quedan
## tocándose.
@export var hook_distance := 0.7
## Alcance: hasta dónde llega el agarre, como distancia máxima del snap. De un
## compañero en un cable, se usa hook_cable_reach.
@export var hook_reach := 1.0
## De un compañero en un cable, que es como un cilindro: te agarrás de
## cualquier lado, sin mirarlo, si tus manos pasan a no más de esto de su eje,
## en horizontal, entre hook_min_height y hook_max_height sobre sus pies. El
## cuerpo va a la cintura (hook_height), del lado por el que llegaste.
@export var hook_cable_reach := 1.0
## Colgado de un compañero en un cable: hasta dónde bajan y suben tus manos con
## S y W, sobre sus pies (de los pies a los hombros). Es también la franja en
## la que te agarrás.
@export var hook_min_height := 0.0
@export var hook_max_height := 1.5
## Colgado de un compañero en un cable: a qué velocidad suben y bajan tus manos
## con W y S, y a qué velocidad girás alrededor de él con A y D (sobre el
## círculo de hook_distance), en m/s.
@export var hook_climb_speed := 1.5
@export var hook_turn_speed := 1.5

@export_group("Cámara lenta")
## Escala de tiempo de la cámara lenta del mundo. La prende y la apaga
## cualquier jugador con el 1 del teclado numérico.
@export var slow_scale := 0.3

@export_group("Súper salto y velocidad")
## Lo prende y lo apaga cada jugador para sí mismo con el 2 del teclado
## numérico. Cuánto más alto llegan los pies en un salto desde el piso, en
## metros, además de la altura de siempre.
@export var boost_jump_extra := 1.5
## Por cuánto se multiplica la velocidad en el piso: caminando, corriendo y
## agachado.
@export var boost_speed_scale := 1.5
## Como jump_max_speed (grupo Salto), pero con el súper prendido: el salto
## dura 1,5 s en el aire, así que se avanza más o menos esto por 1,5.
@export var boost_jump_max_speed := 6.5

@export_group("Agarre")
## Cuánta fuerza externa resiste cada modo antes de soltarse (escala de 0 a 5).
## Los modos libres (Suelo, Aire, Deslizamiento) tienen agarre 0.
@export var ladder_grip := 3
@export var hang_grip := 3
@export var hook_grip := 3
@export var cable_grip := 3
## Con un compañero colgado, el agarre del que lo sostiene baja este tanto
## (el modificador de carga de la arquitectura).
@export var hook_load_grip_drop := 1

@export_group("Aire")
## Aceleración hacia la velocidad pedida en el aire, en m/s².
@export var air_accel := 12.0
@export var gravity := 9.8
@export var max_fall_speed := 40.0

@export_group("Salto")
@export var jump_velocity := 4.8
## Velocidad horizontal máxima al saltar desde el piso, en m/s: si venías más
## rápido (corriendo, deslizándote), el salto sale con esta. Cuánto se avanza
## en un salto es más o menos esto por el tiempo en el aire (1 s en un salto
## normal). Bajalo y se salta menos lejos. Es la velocidad propia: sobre una
## plataforma que se mueve, la de la plataforma se suma aparte.
@export var jump_max_speed := 6.0
## Salto en el aire: cayendo sin haber saltado desde que dejó el piso o algo
## de donde estaba agarrado (se cayó de un borde, se soltó, lo empujaron),
## Espacio salta una vez más. Velocidad para arriba, en m/s: con la misma que
## jump_velocity sube lo mismo que un salto desde el piso; con el súper salto
## y velocidad, los pies suben boost_jump_extra más.
@export var air_jump_velocity := 4.8
## Sale hacia donde mira la cámara, con la velocidad horizontal que traía
## pero no menos que esta, en m/s (con el súper, por boost_speed_scale), ni
## más que el tope del salto (jump_max_speed, o boost_jump_max_speed).
@export var air_jump_speed := 5.0
## Ventana para saltar después de dejar el piso, en segundos de tiempo del actor.
@export var coyote_time := 0.1
## Cuánto se recuerda una pulsación de salto antes de tocar el piso, en segundos.
@export var jump_buffer_time := 0.12


## Un nodo nuevo con los valores del nodo Tuning de esa escena, leídos del
## archivo sin instanciarla: los que no se cambiaron en el Inspector quedan con
## el valor por defecto del script, como en el juego. Lo usan las pruebas, para
## probar los mismos valores que se juegan.
static func from_scene(path := SCENE_PATH) -> ActorTuning:
	var tuning := ActorTuning.new()
	var script: Script = tuning.get_script()
	var state := (load(path) as PackedScene).get_state()
	for i in state.get_node_count():
		var values := {}
		for j in state.get_node_property_count(i):
			values[state.get_node_property_name(i, j)] = state.get_node_property_value(i, j)
		if values.get("script") != script:
			continue
		for property: String in values:
			if property != "script":
				tuning.set(property, values[property])
		return tuning
	push_error("No hay un nodo Tuning en %s: quedan los valores por defecto." % path)
	return tuning
