class_name MotorSnapshot
extends RefCounted

## Estado de lectura del motor físico, expuesto vía PlayerMotor.snapshot()
## (doc de arquitectura V0.3, sección 5). Es una copia: leerlo no afecta al
## motor ni implica autoridad sobre él.

enum Stance { STANDING, CROUCHING }

var is_grounded: bool
var velocity: Vector3
var stance: Stance
var can_stand: bool


func _init(p_is_grounded: bool = false, p_velocity: Vector3 = Vector3.ZERO,
		p_stance: Stance = Stance.STANDING, p_can_stand: bool = true) -> void:
	is_grounded = p_is_grounded
	velocity = p_velocity
	stance = p_stance
	can_stand = p_can_stand
