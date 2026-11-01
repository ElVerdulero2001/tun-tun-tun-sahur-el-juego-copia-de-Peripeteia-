class_name InvPickupSpawn
extends Marker3D

## Dónde empieza un objeto en el mundo, para recogerlo con E. Al arrancar, el
## host crea ahí el objeto (con un id nuevo) y se lo cuenta a todos; el
## marcador en sí no se ve en el juego. Va apoyado en el piso: su lugar es la
## base del objeto.

@export var item: InvItemDef
## Si pasa de lo que entra en una pila, se recorta y se avisa.
@export_range(1, 9999) var quantity := 1
## Lo que cambia del estado de fábrica del tipo, por ejemplo {"carga": 40}.
@export var state_override := {}


func initial_state() -> Dictionary:
	var state := item.default_state.duplicate(true) if item != null else {}
	state.merge(state_override, true)
	return state
