class_name ItemInstance
extends RefCounted

## Representa ESTA copia concreta de un objeto. Conserva su identidad
## logica aunque cambie de contexto entre mundo, inventario u otros
## contextos futuros (INV-02, INV-06, doc V0 seccion 3.2).
##
## La representacion fisica (WorldItem) y la colocacion en un inventario
## (InventoryEntry) son ambas EXTERNAS a este objeto: este objeto no sabe
## donde esta, solo QUE es y QUIEN es.
##
## instance_id es la unica fuente de verdad de identidad para los logs
## y las pruebas de V0 (ver seccion "Observabilidad" del encargo).

static var _siguiente_id: int = 1

var instance_id: int
var definition: ItemDefinition

func _init(p_definition: ItemDefinition) -> void:
	definition = p_definition
	instance_id = _siguiente_id
	_siguiente_id += 1

func _to_string() -> String:
	var nombre_def := definition.nombre if definition else "???"
	return "ItemInstance(#%d, %s)" % [instance_id, nombre_def]
