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
##
## Usar sin esperar al host (desde el 2026-11-04): si predictable() dice que
## sí, el cliente aplica el efecto en su predicción, desde el input
## (InvNet.use_before_step), con una copia de la pila y de la barra tal como
## estaban cuando la usó: en el host la pila y la barra son las de verdad en
## el tick en que le llega. Una capacidad que dependa de algo de la pila o de
## la barra que pueda cambiar en el medio (una carga, una munición) tiene que
## decir que no: entonces sale como pedido (InvProtocol.Op.USE) y espera al
## host (auditoría del 2026-11-04, ARQ-01).

enum Kind { USE, EQUIP }


func kind() -> int:
	return Kind.USE


## Si el cliente puede aplicar el efecto sin esperar al host (ver arriba). Por
## las dudas, no: cada capacidad nueva lo dice.
func predictable() -> bool:
	return false


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
