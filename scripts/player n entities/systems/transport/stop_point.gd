class_name StopPoint
extends PathFollow3D

## Marcador de parada sobre un Path3D.
## No contiene lógica de navegación, estados ni movimiento.
## Su única responsabilidad es almacenar referencias a sus dos TransitionPoints
## y exponer su progress como referencia geométrica estática.

@export var transition_a: TransitionPoint
@export var transition_b: TransitionPoint
