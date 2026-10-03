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
