class_name InvInventory
extends Node

## Componente de inventario de una entidad: un jugador o una caja. Se pone como
## hijo de la entidad (la caja lo trae en su escena; al personaje se lo agrega
## el host cuando aparece). En el host guarda la grilla que vale; en un cliente
## queda vacío, porque lo que ese jugador ve le llega del host (InvReplica).

## Medidas de la grilla. Se leen al armarla, la primera vez que se usa.
@export_range(1, 64) var columns := 12
@export_range(1, 64) var rows := 16
## Los jugadores tienen barra rápida y equipo; las cajas no.
@export var has_loadout := false

var grid: InvGrid
var loadout: InvLoadout


## Host: arma la grilla vacía, si todavía no la tiene.
func setup(catalog: InvCatalog) -> void:
	if grid == null:
		grid = InvGrid.new(columns, rows, catalog)
	if has_loadout and loadout == null:
		loadout = InvLoadout.new()
