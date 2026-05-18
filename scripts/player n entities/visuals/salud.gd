extends Node

@export var vida_maxima: float = 100.0
var vida_actual: float = 100.0

signal vida_cambiada(nueva_vida, vida_max)
signal murio

func _ready():
	vida_actual = vida_maxima

func recibir_daño(cantidad: float) -> void:
	vida_actual -= cantidad
	vida_actual = clamp(vida_actual, 0.0, vida_maxima)
	emit_signal("vida_cambiada", vida_actual, vida_maxima)
	if vida_actual <= 0:
		emit_signal("murio")

func curar(cantidad: float) -> void:
	vida_actual += cantidad
	vida_actual = clamp(vida_actual, 0.0, vida_maxima)
	emit_signal("vida_cambiada", vida_actual, vida_maxima)
