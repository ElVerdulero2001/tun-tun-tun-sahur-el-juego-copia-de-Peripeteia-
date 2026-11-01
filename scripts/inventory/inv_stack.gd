class_name InvStack
extends RefCounted

## Una instancia concreta de un objeto, o una pila de ellos: su id, su tipo, su
## cantidad y su estado. No sabe dónde está: su lugar es la colocación en una
## InvGrid, o un objeto en el mundo.
##
## Compatibilidad para apilar: el mismo id de tipo y el mismo estado, clave por
## clave (por ejemplo la carga de una batería, la condición o el contenido). El
## nombre o el ícono no cuentan.

## Identificador estable, único entre todos los inventarios y el mundo. Lo da
## el host; 0 no es ningún objeto.
var uid := 0
var def_id := &""
var quantity := 1
var state := {}
## Sube con cada cambio de esta pila (cantidad, lugar, dueño). Con ella el host
## reconoce un pedido hecho sobre lo que el jugador veía antes de un cambio.
var ver := 0


static func make(p_uid: int, p_def_id: StringName, p_quantity: int, p_state: Dictionary) -> InvStack:
	var stack := InvStack.new()
	stack.uid = p_uid
	stack.def_id = p_def_id
	stack.quantity = p_quantity
	stack.state = p_state.duplicate(true)
	return stack


func compatible_with(other: InvStack) -> bool:
	return other != null and def_id == other.def_id and InvStack.same_state(state, other.state)


static func same_state(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or typeof(a[key]) != typeof(b[key]) or a[key] != b[key]:
			return false
	return true


func copy() -> InvStack:
	var stack := InvStack.make(uid, def_id, quantity, state)
	stack.ver = ver
	return stack


func to_array() -> Array:
	return [uid, String(def_id), quantity, state, ver]


## Desde lo que manda el host. null si no tiene la forma esperada.
static func from_array(data: Variant) -> InvStack:
	if not data is Array or data.size() != 5:
		return null
	var a: Array = data
	if typeof(a[0]) != TYPE_INT or typeof(a[1]) != TYPE_STRING or typeof(a[2]) != TYPE_INT \
			or typeof(a[3]) != TYPE_DICTIONARY or typeof(a[4]) != TYPE_INT:
		return null
	var stack := InvStack.make(a[0], StringName(a[1]), a[2], a[3])
	stack.ver = a[4]
	return stack
