class_name InvAbility
extends Resource

## Una capacidad de un tipo de objeto: lo que se puede hacer con él desde el
## menú contextual o la barra rápida. Cada tipo lista las suyas en
## InvItemDef.abilities; el menú y el host las preguntan, sin mirar el nombre
## del objeto. Las aplica solo el host.
##
## `vitals` es la salud y la estamina del personaje que la usa (ActorVitals),
## o null si no tiene: en el host, las que valen; en la interfaz, las que se
## ven, solo para saber si el botón va habilitado. Es todo lo que una
## capacidad ve del personaje.

enum Kind { USE, EQUIP }


func kind() -> int:
	return Kind.USE


## Texto del botón del menú, según el estado del jugador.
func action_text(_loadout: InvLoadout, _stack: InvStack) -> String:
	return "Usar"


## Por qué no se puede hacer ahora, o vacío si se puede. Lo pregunta el menú
## para deshabilitar el botón y lo vuelve a preguntar el host antes de aplicar.
func check(_loadout: InvLoadout, _stack: InvStack, _vitals: ActorVitals) -> String:
	return ""


## Host: lo aplica, todo junto: o se aplica entero o nada. Devuelve cuántas
## unidades de la pila se gastan.
func apply(_loadout: InvLoadout, _stack: InvStack, _vitals: ActorVitals) -> int:
	return 0


## Una línea para la ventana de inspección.
func describe() -> String:
	return ""


## Lo que tiene que ser igual en el host y en los clientes (SimFingerprint).
func fingerprint_text() -> String:
	return get_script().resource_path
