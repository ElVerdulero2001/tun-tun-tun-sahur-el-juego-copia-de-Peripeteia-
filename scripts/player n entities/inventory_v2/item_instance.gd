class_name ItemInstance
extends RefCounted

## Representa ESTA copia concreta de un objeto. Conserva su identidad
## logica aunque cambie de contexto entre mundo, inventario u otros
## contextos futuros (INV-02, INV-06; docs/inventory_system_v0_v1.md seccion 4).
##
## La representacion fisica (WorldItem) y la colocacion en un inventario
## (InventoryEntry) son ambas EXTERNAS a este objeto: este objeto no sabe
## donde esta, solo QUE es y QUIEN es.
##
## La identidad real es la REFERENCIA del objeto (comparaciones ==).
## instance_id es solo un aid legible para logs y asserts de tests: un
## contador static por proceso (arranca en 1). NO es persistente, NO es
## estable entre corridas, NO es un id de red. No usarlo como clave de
## save/serializacion ni de replicacion; si eso hiciera falta, se
## introduce un id estable aparte (docs/inventory_system_v0_v1.md seccion 17, D6).

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
