class_name InvProtocol
extends RefCounted

## Forma de los pedidos que un jugador le hace al host. Viajan como
## [número de pedido, operación, argumentos, uso anterior], solo con números
## enteros: nunca nodos, recursos ni rutas. El host descarta lo que no tenga
## exactamente esta forma.
##
## El uso anterior (desde la auditoría del 2026-11-04, INV-02 e INV-03) es el
## número del último consumible que ese jugador usó antes de hacer el pedido
## (ActorInput.use_presses), o -1 si no usó ninguno desde que se conectó: el
## host no procesa el pedido antes de procesar ese uso. Así los pedidos y los
## usos, que viajan por caminos distintos, se hacen en el host en el mismo
## orden en que los hizo el jugador.
##
## Un inventario se nombra con un número: 0 es el propio (el host sabe de quién
## es por la conexión), uno positivo es una caja, y uno negativo sería el de
## otro jugador, que el host siempre rechaza. El giro va de 0 a 3, de a 90° en
## el sentido del reloj.

enum Op {
	MOVE = 1,  ## [origen, id, versión, destino, x, y, giro]
	MERGE,  ## [origen, id, versión, destino, id de la pila de destino, cantidad]
	SPLIT,  ## [origen, id, versión, cantidad, destino, x, y, giro]
	DROP,  ## [origen, id, versión, cantidad]: al piso, desde el inventario propio o una caja abierta
	## Desde el 2026-11-11 a la noche, recoger y abrir llevan la dirección en
	## que el jugador estira la mano desde los ojos (InvReach.aim_direction), de
	## largo 1, y el tick del último input de esa máquina (o -1): el host espera
	## a haber movido a ese personaje hasta ese tick, tira su propio rayo desde
	## sus ojos, con su estado, en esa dirección (InvReach.first_hit), y lo
	## primero que toca tiene que ser ese objeto o esa caja, al alcance. Hasta
	## ese día iba solo el número.
	PICKUP,  ## [id del objeto del mundo, x, y, z, tick]
	USE,  ## [id, versión]
	EQUIP,  ## [id, versión]: equipa o desequipa
	HOTBAR_SET,  ## [acceso, id] (id 0 lo vacía)
	HOTBAR_SWAP,  ## [acceso, acceso]
	HOTBAR_PRESS,  ## [acceso]: usa o equipa lo que tiene
	OPEN,  ## [id de la caja, x, y, z, tick]
	CLOSE,  ## [id de la caja]
	## Desde el 2026-11-04: como DROP, con el lugar donde esta máquina ya lo
	## muestra en el piso, en milímetros. El host lo deja ahí si ese lugar sirve
	## (InvAuthority.drop_spot_ok); si no, elige él, como en DROP.
	DROP_AT,  ## [origen, id, versión, cantidad, x, y, z]
	# Del 2026-11-06 a la tarde hubo HEAL_PART [id, versión, parte]: curar una
	# parte del cuerpo esperaba al host. Desde la noche va como un uso en el
	# input, con la parte (ActorInput.uses, InvNet.queue_use).
}

const OWN := 0
## Un pedido más largo que esto no es de este juego.
const MAX_REQUEST_BYTES := 512

const ARGS := {
	Op.MOVE: [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT],
	Op.MERGE: [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT],
	Op.SPLIT: [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT],
	Op.DROP: [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT],
	Op.PICKUP: [TYPE_INT, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT],
	Op.USE: [TYPE_INT, TYPE_INT],
	Op.EQUIP: [TYPE_INT, TYPE_INT],
	Op.HOTBAR_SET: [TYPE_INT, TYPE_INT],
	Op.HOTBAR_SWAP: [TYPE_INT, TYPE_INT],
	Op.HOTBAR_PRESS: [TYPE_INT],
	Op.OPEN: [TYPE_INT, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT],
	Op.CLOSE: [TYPE_INT],
	Op.DROP_AT: [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT],
}

## El lugar de DROP_AT viaja en milímetros.
const DROP_STEP := 0.001
## Cuánto puede diferir de 1 el largo de la dirección de PICKUP u OPEN.
const DIRECTION_SLACK := 0.01


## Los argumentos de PICKUP u OPEN: el número, la dirección de la mano y el
## tick del último input de esta máquina (InvNet.aim_tick; -1: no esperar).
static func aimed_args(id: int, direction: Vector3, tick := -1) -> Array:
	return [id, direction.x, direction.y, direction.z, tick]


## La dirección de la mano de un PICKUP u OPEN, de largo 1, o null si no
## sirve: si no tiene la forma de aimed_args, si algún número no es finito (NAN
## o INF) o si su largo no es 1 (con DIRECTION_SLACK). El host la mira siempre:
## el pedido de su propio jugador no pasa por parse_request.
static func direction_of(args: Array) -> Variant:
	if args.size() != 5 or typeof(args[4]) != TYPE_INT:
		return null
	for i in range(1, 4):
		if typeof(args[i]) != TYPE_FLOAT:
			return null
	var direction := Vector3(args[1], args[2], args[3])
	if not direction.is_finite() or absf(direction.length() - 1.0) > DIRECTION_SLACK:
		return null
	return direction.normalized()


## El tick hasta el que el host tiene que haber movido al personaje antes de
## hacer un PICKUP u OPEN (-1: ninguno, o si el pedido no es de esos).
static func aimed_tick_of(op: int, args: Array) -> int:
	if (op == Op.PICKUP or op == Op.OPEN) and args.size() == 5 and typeof(args[4]) == TYPE_INT:
		return args[4]
	return -1


static func drop_args(ref: int, uid: int, ver: int, quantity: int, spot: Vector3) -> Array:
	return [ref, uid, ver, quantity, roundi(spot.x / DROP_STEP), roundi(spot.y / DROP_STEP), roundi(spot.z / DROP_STEP)]


static func drop_spot_of(args: Array) -> Vector3:
	return Vector3(args[4], args[5], args[6]) * DROP_STEP


static func encode_request(seq: int, op: int, args: Array, after_use := -1) -> PackedByteArray:
	return var_to_bytes([seq, op, args, after_use])


## [número, operación, argumentos, uso anterior], o vacío si no tiene la forma
## esperada.
static func parse_request(data: PackedByteArray) -> Array:
	if data.size() < 4 or data.size() > MAX_REQUEST_BYTES:
		return []
	# Sin objetos: bytes_to_var no los arma, así que un pedido no puede traer uno.
	var value: Variant = bytes_to_var(data)
	if not value is Array or value.size() != 4 or typeof(value[0]) != TYPE_INT or typeof(value[1]) != TYPE_INT \
			or not value[2] is Array or typeof(value[3]) != TYPE_INT or value[3] < -1 or value[3] > 0xFF:
		return []
	var op: int = value[1]
	if value[0] <= 0 or not ARGS.has(op):
		return []
	var args: Array = value[2]
	var types: Array = ARGS[op]
	if args.size() != types.size():
		return []
	for i in types.size():
		if typeof(args[i]) != types[i]:
			return []
	return [value[0], op, args, value[3]]
