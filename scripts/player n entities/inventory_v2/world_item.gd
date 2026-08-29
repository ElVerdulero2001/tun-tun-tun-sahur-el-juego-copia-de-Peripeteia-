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

var item_instance: ItemInstance

## Autoridad inyectada. Desde C1 (SUA-1.3) el flujo de pickup NO la lee: el
## pickup se resuelve desde Interaction.actor -> InventoryReceiver de esa
## entidad. Sigue existiendo SOLO porque LocalAuthority.solicitar_devolucion()
## la re-inyecta en el WorldItemV2 que crea al devolver un item al mundo
## (local_authority.gd) — y ese contrato no se toca en C1. Estado vestigial
## pendiente de limpieza cuando se pueda revisar LocalAuthority (deuda C2).
var _authority: Node

func setup(authority: Node) -> void:
	_authority = authority

## Contrato de InteractionComponent: _on_interact(interaction) -> Variant
func _on_interact(interaction: Interaction) -> Variant:
	match interaction.accion:
		&"usar":
			return _solicitar_pickup(interaction.actor)
		_:
			return false

## SOLICITA que este WorldItem pase al inventario de la ENTIDAD que realizo la
## interaccion. NO conoce PlayerV2, ni Body, ni InventoryV2, ni la LocalAuthority
## concreta del actor, ni nombres de nodos, ni grupos: solo la capacidad
## InventoryReceiver. Este metodo SOLICITA — no agrega el item a ningun
## inventario, no se destruye a si mismo, no decide el resultado (INV-07/INV-08).
func _solicitar_pickup(actor: Node) -> bool:
	if actor == null:
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
