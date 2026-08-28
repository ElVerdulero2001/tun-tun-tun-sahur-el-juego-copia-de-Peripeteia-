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
##
## ── CONTRATO DE IDENTIDAD (D8; docs/inventory_system_v0_v1.md seccion 17) ──
## Estas cuatro reglas se cumplen HOY en todo el repo (0 violaciones en la
## auditoria de Batch B.2). GDScript 4.6.3 NO las puede imponer: no hay
## private/protected y set()/call() dinamicos alcanzan cualquier campo. Se
## sostienen por convencion + el tripwire inventory_v1_identity_contract_test.
## D8 es una LIMITACION DELIBERADA, no un agujero desconocido.
##
##  C-D8.1  `definition` se fija en _init() y NUNCA se reasigna. Una instancia
##          es "una copia concreta de UN tipo"; cambiarle el tipo a mitad de
##          vida romperia footprint / can_rotate / world_scene de lo ya colocado.
##  C-D8.2  `ItemDefinition` es configuracion de tipo compartida e inmutable en
##          runtime (ver item_definition.gd). Ningun consumidor debe escribir
##          `instance.definition.<campo> = ...`.
##  C-D8.3  `instance_id` se fija en _init() y NO se reasigna. Es SOLO aid de
##          logs/tests: ninguna rama de logica de produccion depende de su
##          valor (la identidad es la REFERENCIA, no este entero).
##  C-D8.4  `_siguiente_id` es detalle de construccion. Nadie lo lee ni lo
##          escribe fuera de _init().

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
