class_name ActorTuning
extends Resource

## Parámetros de movimiento del actor. Son valores de partida, a calibrar.
##
## Host y clientes tienen que usar exactamente el mismo recurso: si difieren,
## la predicción diverge sin que nada lo avise.

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
## Al saltar de la escalera: velocidad hacia afuera y hacia arriba, en m/s.
@export var ladder_jump_out := 3.0
@export var ladder_jump_up := 3.5
## Al soltar un ancla por un salto o un empujón, cuánto tiempo no se la puede
## volver a agarrar, en segundos de tiempo del actor.
@export var regrab_block_time := 0.4
## Al salir por arriba: cuánto avanza sobre el borde, en metros.
@export var ladder_top_step := 0.7

@export_group("Agarre")
## Cuánta fuerza externa resiste cada modo antes de soltarse (escala de 0 a 5).
## Los modos libres (Suelo, Aire, Deslizamiento) tienen agarre 0.
@export var ladder_grip := 3

@export_group("Aire")
## Aceleración hacia la velocidad pedida en el aire, en m/s².
@export var air_accel := 12.0
@export var gravity := 9.8
@export var max_fall_speed := 40.0

@export_group("Salto")
@export var jump_velocity := 4.8
## Ventana para saltar después de dejar el piso, en segundos de tiempo del actor.
@export var coyote_time := 0.1
## Cuánto se recuerda una pulsación de salto antes de tocar el piso, en segundos.
@export var jump_buffer_time := 0.12
