class_name V3FallDamageState
extends Node

## Estado de gameplay externo a H0. Convierte el hecho físico de una caída
## fuerte en la restricción "no puede saltar". No resuelve vida ni curación.
@export var physics_body: V3PhysicsBody
@export var jump_penalty_fall_distance := 5.0

var jump_is_penalized := false
var last_observed_landing_distance := 0.0


func _physics_process(_delta: float) -> void:
	if physics_body == null:
		return

	last_observed_landing_distance = physics_body.last_landing_fall_distance
	if last_observed_landing_distance >= jump_penalty_fall_distance:
		jump_is_penalized = true


## La recuperación/muerte aún no está diseñada. Quien la resuelva podrá
## quitar esta condición explícitamente; nunca vence por tiempo.
func clear_jump_penalty() -> void:
	jump_is_penalized = false
