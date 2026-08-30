class_name WorldItemV2
extends RigidBody3D

## Carcasa fisica y visual TEMPORAL de un ItemInstance mientras existe en
## el mundo (docs/inventory_system_v0_v1.md seccion 3). Puede crearse y destruirse sin destruir
## la identidad logica del objeto (INV-02): item_instance sigue siendo el
## mismo ItemInstance # aunque este nodo se destruya y se cree otro nuevo
## al devolver el item al mundo.
##
## Analogo a Item.gd (legacy), pero sin llamar al autoload Inventario.
## En vez de mutar nada directamente, SOLICITA un pickup: resuelve la
## capacidad InventoryReceiver de la ENTIDAD que realizo la interaccion
## (Interaction.actor) y le delega (INV-07/INV-08).
##
## NEUTRAL respecto de autoridad: un WorldItemV2 en el mundo —recien
## spawneado o creado por una devolucion— no guarda actor, inventario ni
## LocalAuthority. Quien lo recoge se determina SOLO en el momento de la
## interaccion.
##
## ── AUTOAPROVISIONAMIENTO (SUA-1.6 B) ──
## Un WorldItemV2 colocado DIRECTAMENTE en una escena (un prop real en un nivel)
## no tiene quien le inyecte su ItemInstance. Si trae un `definition` exportado y
## nadie le fijo `item_instance` antes de entrar al arbol, se crea UNA en _ready().
## Prioridad: un `item_instance` ya inyectado (tests, sandboxes, o —a futuro— un
## objeto restaurado desde estado externo) SIEMPRE gana; _ready() no lo pisa.
## Sin `definition` y sin `item_instance`: el nodo existe, no crashea, y cualquier
## pickup falla limpio por los contratos existentes (TransferOperation.validate).
## `definition` NO agrega autoridad, inventario, ni conocimiento del Player: el
## WorldItemV2 sigue neutral.

## Tipo de item que representa este prop cuando se coloca directo en una escena.
## Opcional: los WorldItemV2 spawneados por TransferOperation o por un arnes
## reciben su ItemInstance por inyeccion y no necesitan este campo.
@export var definition: ItemDefinition

var item_instance: ItemInstance


func _ready() -> void:
	if item_instance == null and definition != null:
		item_instance = ItemInstance.new(definition)

## Contrato de InteractionComponent: _on_interact(interaction) -> Variant
func _on_interact(interaction: Interaction) -> Variant:
	match interaction.accion:
		&"usar":
			return _solicitar_pickup(interaction.actor)
		_:
			return false

## SOLICITA que este WorldItem pase al inventario de la ENTIDAD que realizo la
## interaccion. NO conoce PlayerV2, ni Body, ni InventoryV2, ni LocalAuthority,
## ni nombres de nodos, ni grupos: solo la capacidad InventoryReceiver. Este
## metodo SOLICITA — no agrega el item a ningun inventario, no se destruye a si
## mismo, no decide el resultado (INV-07/INV-08).
func _solicitar_pickup(actor: Node) -> bool:
	if actor == null:
		return false
	# Fail-fast local: un WorldItemV2 sin ItemInstance (ni inyectado ni
	# autoaprovisionado por falta de `definition`) es un error de contenido, no
	# algo recogible. TransferOperation.validate() igual lo rechazaria aguas
	# abajo ("item_instance nulo"); cortar aca evita el roundtrip
	# actor -> receiver -> authority -> operation y deja la razon en el borde.
	# Semantica sin cambios: _on_interact devuelve false, nada se mueve.
	if item_instance == null:
		return false
	var receiver := _resolver_receiver(actor)
	if receiver == null:
		return false
	return receiver.recibir_pickup(self)

## Primer InventoryReceiver entre los hijos DIRECTOS de `actor`, o null.
## Mismo patron con que InteractionV2 resuelve un InteractionComponent como
## hijo directo del collider: sin walk por ancestros, sin busqueda por nombre,
## sin grupos.
func _resolver_receiver(actor: Node) -> InventoryReceiver:
	for child in actor.get_children():
		if child is InventoryReceiver:
			return child
	return null
