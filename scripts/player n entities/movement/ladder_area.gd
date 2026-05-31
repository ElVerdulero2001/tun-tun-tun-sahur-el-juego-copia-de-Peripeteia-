# ladder_area.gd
# Va directo en el StaticBody3D de la escalera.
# El grupo "ladder" también va en ese mismo nodo.
#
# SETUP:
#   1. Asignar este script al StaticBody3D de la escalera.
#   2. Agregar el grupo "ladder" al mismo nodo.
#   3. Ajustar ladder_top y ladder_bottom en el Inspector
#      usando el debug de coordenadas para saber los valores exactos.

extends Node

# Dirección de "subir" en esta escalera (world space).
# Por defecto Vector3.UP. Para escaleras en ángulo, ajustar.
@export var ladder_direction : Vector3 = Vector3.UP

# Multiplicador de velocidad de pulso. 1.0 = velocidad base.
@export var pulse_speed      : float   = 1.0

# Límites del riel en Y (world space).
# Ajustar con los valores exactos que muestra el debug de coordenadas.
@export var ladder_top       : float   = 5.0
@export var ladder_bottom    : float   = 0.0
