@tool
class_name InvBodyShape
extends InvPickupHitbox

## El cuerpo físico de un tipo de objeto suelto (desde el 2026-11-14): con qué
## forma choca con el nivel y con los demás objetos, cae y reposa. Va en
## InvItemDef.body_shape, se guarda con el resto del tipo y lo edita el panel
## Objetos (sección «Cuerpo físico»). Un tipo sin esto usa la forma automática.
##
## Son tres cosas distintas, cada una con lo suyo:
## - lo que se ve: el modelo (InvVisuals.world_model);
## - con qué se elige y se agarra: los triángulos de ese modelo (InvReach), que
##   no se tapan con esta forma: un hueco del modelo no se vuelve sólido para el
##   rayo de la mano, aunque el cuerpo lo tape;
## - con qué choca: esta forma (InvItemPhysics la arma una vez por tipo).
##
## Usa las mismas formas, medidas y lugar que la hitbox de agarre (de la que
## hereda), en el mismo espacio: el del objeto suelto, con el origen en el
## centro de su base, en metros. Con Kind.MODEL es la forma automática, armada
## con los triángulos del modelo: en `auto_parts` tajadas a lo largo de un eje
## (`auto_axis`), y en cada tajada una forma convexa por cada pedazo que no se
## toca con los demás (las patas de un banquito, los dos lados de un marco).
## Así un hueco del modelo, como el de un marco, no queda tapado por una sola
## forma convexa. Con 0 partes lo elige solo: ver InvItemPhysics.

enum Axis { AUTO, X, Y, Z }

## Lo más que se puede partir la forma automática.
const MAX_PARTS := 8

@export_group("Forma automática")
## En cuántas tajadas se parte la forma automática (solo con la forma del
## modelo). 0: las elige solo: una sola forma convexa para lo compacto, varias
## para lo largo o con huecos. Con 1, una sola forma convexa, que tapa los huecos.
@export_range(0, 8) var auto_parts := 0
## A lo largo de qué eje del objeto van las tajadas. AUTO: el que encuentra más
## huecos, o el más largo.
@export var auto_axis := Axis.AUTO

# Sin _init que cambie `kind`: Godot no guarda un valor igual al de fábrica de
# la variable (Kind.BOX, el de la hitbox), y al leer el archivo quedaría el que
# pusiera _init. El panel Objetos la crea con Kind.MODEL.


## Si tiene una forma propia o elige las tajadas de la automática.
func is_configured() -> bool:
	return kind != Kind.MODEL or auto_parts != 0 or auto_axis != Axis.AUTO


## El cuerpo físico que vale para un tipo: el suyo si sirve, o null (la forma
## automática con lo que elige sola).
static func active_body(def: InvItemDef) -> InvBodyShape:
	var shape := def.body_shape if def != null else null
	if shape == null or not shape.problems().is_empty():
		return null
	return shape


func problems() -> PackedStringArray:
	var found := super.problems()
	if auto_parts < 0 or auto_parts > MAX_PARTS:
		found.append("la forma automática se parte de 0 a %d veces." % MAX_PARTS)
	if auto_axis < Axis.AUTO or auto_axis > Axis.Z:
		found.append("el eje de las tajadas no es uno conocido (%s)." % auto_axis)
	return found


## Lo que va en la huella: la forma y lo que cuenta de ella.
func effective_text() -> String:
	if kind == Kind.MODEL:
		return "automática %d %d" % [auto_parts, auto_axis]
	return super.effective_text()
