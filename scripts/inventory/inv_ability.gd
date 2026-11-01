class_name InvAbility
extends Resource

## Una capacidad de un tipo de objeto: lo que se puede hacer con él desde el
## menú contextual o la barra rápida. Cada tipo lista las suyas en
## InvItemDef.abilities; el menú y el host las preguntan, sin mirar el nombre
## del objeto. Las aplica solo el host.

enum Kind { USE, EQUIP }


func kind() -> int:
	return Kind.USE


## Texto del botón del menú, según el estado del jugador.
func action_text(_loadout: InvLoadout, _stack: InvStack) -> String:
	return "Usar"


## Por qué no se puede hacer ahora, o vacío si se puede. Lo pregunta el menú
## para deshabilitar el botón y lo vuelve a preguntar el host antes de aplicar.
func check(_loadout: InvLoadout, _stack: InvStack) -> String:
	return ""


## Host: lo aplica. Devuelve cuántas unidades de la pila se gastan.
func apply(_loadout: InvLoadout, _stack: InvStack) -> int:
	return 0


## Una línea para la ventana de inspección.
func describe() -> String:
	return ""


## Lo que tiene que ser igual en el host y en los clientes (SimFingerprint).
func fingerprint_text() -> String:
	return get_script().resource_path
