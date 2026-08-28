class_name WorldItemV2
extends RigidBody3D

## Carcasa fisica y visual TEMPORAL de un ItemInstance mientras existe en
## el mundo (docs/inventory_system_v0_v1.md seccion 3). Puede crearse y destruirse sin destruir
## la identidad logica del objeto (INV-02): item_instance sigue siendo el
## mismo ItemInstance # aunque este nodo se destruya y se cree otro nuevo
## al devolver el item al mundo.
##
## Analogo a Item.gd (legacy), pero sin llamar al autoload Inventario.
## En vez de mutar nada directamente, solicita un pickup a traves de
## InteractionComponent -> LocalAuthority (INV-07/INV-08).

var item_instance: ItemInstance
## Referencia a la autoridad local que arbitra las transferencias en esta
## escena de prueba. Se inyecta desde la escena de prueba via setup(),
## siguiendo el mismo patron que Player.setup() en los controllers.
var _authority: Node

func setup(authority: Node) -> void:
	_authority = authority

## Contrato de InteractionComponent: _on_interact(interaction) -> Variant
func _on_interact(interaction: Interaction) -> Variant:
	match interaction.accion:
		&"usar":
			return _solicitar_pickup()
		_:
			return false

## Este metodo SOLICITA. No agrega el item a ningun inventario, no se
## destruye a si mismo, no decide el resultado. Eso es exactamente lo
## que INV-07/INV-08 prohiben que haga un componente de interaccion.
func _solicitar_pickup() -> bool:
	if _authority == null:
		push_warning("WorldItemV2: sin autoridad local asignada, no se puede solicitar pickup")
		return false
	return _authority.solicitar_pickup(self)
