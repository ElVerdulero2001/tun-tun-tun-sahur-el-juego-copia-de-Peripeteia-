class_name InvProtocol
extends RefCounted

## Forma de los pedidos que un jugador le hace al host. Viajan como
## [número de pedido, operación, argumentos, uso anterior], con números enteros
## (ids, versiones, cantidades, celdas, ticks), salvo la dirección de la mano de
## recoger y abrir: tres números con decimales (TYPE_FLOAT; con enteros, el
## pedido se descarta). Nunca nodos, recursos ni rutas. El host descarta lo que
## no tenga exactamente la forma de ARGS. (Hasta el 2026-11-11 eran solo
## enteros; este texto se corrigió tras la auditoría del 2026-11-12, DOC-02.)
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
	## Desde el 2026-11-14 (los objetos se mueven), también el tick del host
	## que esa máquina estaba mostrando de los objetos, en centésimas de tick
	## (-1: el de ahora): el host los pone donde estaban entonces para su rayo
	## (InvItemSpace.pose_at). Ver view_tick_of.
	PICKUP,  ## [id del objeto del mundo, x, y, z, tick, tick de lo que se veía]
	USE,  ## [id, versión]
	EQUIP,  ## [id, versión]: equipa o desequipa
	HOTBAR_SET,  ## [acceso, id] (id 0 lo vacía)
	HOTBAR_SWAP,  ## [acceso, acceso]
	HOTBAR_PRESS,  ## [acceso]: usa o equipa lo que tiene
	OPEN,  ## [id de la caja, x, y, z, tick, tick de lo que se veía]
	CLOSE,  ## [id de la caja]
	## Desde el 2026-11-04: como DROP, con el lugar donde esta máquina ya lo
	## muestra, en milímetros. El host lo deja ahí si ese lugar sirve
	## (InvAuthority.drop_spot_ok); si no, elige él, como en DROP. Desde el
	## 2026-11-14 lleva también el giro (el yaw del personaje, como en
	## ActorState.yaw_to_index) y el lugar ya no es el piso: el objeto aparece
	## ahí, a la altura del pecho, y cae.
	DROP_AT,  ## [origen, id, versión, cantidad, x, y, z, yaw]
	# Del 2026-11-06 a la tarde hubo HEAL_PART [id, versión, parte]: curar una
	# parte del cuerpo esperaba al host. Desde la noche va como un uso en el
	# input, con la parte (ActorInput.uses, InvNet.queue_use).
	## Desde el 2026-11-14, sostener un objeto suelto en el mundo (no entra al
	## inventario). Agarrar va como recoger: el host tira su rayo y lo primero
	## que toca tiene que ser ese objeto; el punto tocado es por donde se agarra.
	## La sesión la numera el jugador (de 1 en adelante, cada agarre una más):
	## soltar y lanzar la nombran, y lo que llegue de una sesión vieja no hace
	## nada. El seguimiento de la mano (distancia, giro) no es un pedido: va en
	## el input de cada tick (ActorInput.hold).
	GRAB,  ## [id del objeto, x, y, z, tick, tick de lo que se veía, sesión]
	RELEASE,  ## [id del objeto, sesión]: lo suelta sin impulso
	THROW,  ## [id del objeto, sesión, x, y, z]: lo suelta y lo lanza hacia ahí
}

## La versión de estos pedidos y de los paquetes del host. Entra en la huella
## del inventario (InvNet.fingerprint_text): una copia con otra no se conecta.
## 2: desde el 2026-11-14, los objetos con física (sostener, lanzar, el giro,
## las velocidades y lo que se veía). Antes no había número: era la 1.
const VERSION := 2

const OWN := 0
## Un pedido más largo que esto no es de este juego.
const MAX_REQUEST_BYTES := 512

const ARGS := {
	Op.MOVE: [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT],
	Op.MERGE: [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT],
	Op.SPLIT: [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT],
	Op.DROP: [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT],
	Op.PICKUP: [TYPE_INT, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_INT],
	Op.USE: [TYPE_INT, TYPE_INT],
	Op.EQUIP: [TYPE_INT, TYPE_INT],
	Op.HOTBAR_SET: [TYPE_INT, TYPE_INT],
	Op.HOTBAR_SWAP: [TYPE_INT, TYPE_INT],
	Op.HOTBAR_PRESS: [TYPE_INT],
	Op.OPEN: [TYPE_INT, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_INT],
	Op.CLOSE: [TYPE_INT],
	Op.DROP_AT: [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT],
	Op.GRAB: [TYPE_INT, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_INT, TYPE_INT],
	Op.RELEASE: [TYPE_INT, TYPE_INT],
	Op.THROW: [TYPE_INT, TYPE_INT, TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT],
}

## Los pedidos que llevan la dirección de la mano en los lugares 1 a 3, el tick
## del input en el 4 y el tick de lo que se veía en el 5.
const AIMED := [Op.PICKUP, Op.OPEN, Op.GRAB]
## El lugar de DROP_AT viaja en milímetros.
const DROP_STEP := 0.001
## Cuánto puede diferir de 1 el largo de la dirección de la mano o del lanzamiento.
const DIRECTION_SLACK := 0.01
## El tick de lo que se veía viaja en centésimas de tick.
const VIEW_TICK_STEPS := 100.0
## Lo más alto que puede llegar a ser un número de sesión de agarre.
const MAX_SESSION := 0x7FFFFFFF


## Los argumentos de PICKUP u OPEN: el número, la dirección de la mano, el
## tick del último input de esta máquina (InvNet.aim_tick; -1: no esperar) y
## el tick del host de lo que esta máquina mostraba de los objetos
## (InvNet.view_tick; -1: el de ahora).
static func aimed_args(id: int, direction: Vector3, tick := -1, view_tick := -1.0) -> Array:
	return [id, direction.x, direction.y, direction.z, tick,
			roundi(view_tick * VIEW_TICK_STEPS) if view_tick >= 0.0 and is_finite(view_tick) else -1]


## Los de GRAB: como aimed_args, más la sesión.
static func grab_args(id: int, direction: Vector3, tick: int, view_tick: float, session: int) -> Array:
	return aimed_args(id, direction, tick, view_tick) + [session]


## Los de THROW: el número, la sesión y hacia dónde.
static func throw_args(id: int, session: int, direction: Vector3) -> Array:
	return [id, session, direction.x, direction.y, direction.z]


## La dirección de la mano de un PICKUP, OPEN o GRAB, de largo 1, o null si no
## sirve: si no tiene esa forma, si algún número no es finito (NAN o INF) o si
## su largo no es 1 (con DIRECTION_SLACK). El host la mira siempre: el pedido
## de su propio jugador no pasa por parse_request.
static func direction_of(args: Array) -> Variant:
	if args.size() < 6 or args.size() > 7 or typeof(args[4]) != TYPE_INT or typeof(args[5]) != TYPE_INT:
		return null
	return direction_at(args, 1)


## Tres números con decimales desde `first`, de largo 1: o null.
static func direction_at(args: Array, first: int) -> Variant:
	if args.size() < first + 3:
		return null
	for i in range(first, first + 3):
		if typeof(args[i]) != TYPE_FLOAT:
			return null
	var direction := Vector3(args[first], args[first + 1], args[first + 2])
	if not direction.is_finite() or absf(direction.length() - 1.0) > DIRECTION_SLACK:
		return null
	return direction.normalized()


## El tick hasta el que el host tiene que haber movido al personaje antes de
## hacer un PICKUP, OPEN o GRAB (-1: ninguno, o si el pedido no es de esos).
static func aimed_tick_of(op: int, args: Array) -> int:
	if op in AIMED and args.size() >= 6 and typeof(args[4]) == TYPE_INT:
		return args[4]
	return -1


## El tick del host (con decimales) de lo que mostraba esa máquina al pedir, o
## -1 (el de ahora).
static func view_tick_of(op: int, args: Array) -> float:
	if op in AIMED and args.size() >= 6 and typeof(args[5]) == TYPE_INT and args[5] >= 0:
		return args[5] / VIEW_TICK_STEPS
	return -1.0


static func drop_args(ref: int, uid: int, ver: int, quantity: int, spot: Vector3, yaw := 0.0) -> Array:
	return [ref, uid, ver, quantity, roundi(spot.x / DROP_STEP), roundi(spot.y / DROP_STEP), roundi(spot.z / DROP_STEP),
			ActorState.yaw_to_index(yaw)]


static func drop_spot_of(args: Array) -> Vector3:
	return Vector3(args[4], args[5], args[6]) * DROP_STEP


## El lugar y el giro de un DROP_AT, como lo arma drop_args.
static func drop_place_of(args: Array) -> Transform3D:
	var yaw := ActorState.index_to_yaw(args[7]) if args.size() > 7 else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), drop_spot_of(args))


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
	if value[0] <= 0 or not args_ok(op, value[2]):
		return []
	return [value[0], op, value[2], value[3]]


## Si los argumentos tienen exactamente la forma de ARGS para esa operación.
## Desde el 2026-11-14 el host lo mira también en los pedidos de su propio
## jugador, que no pasan por parse_request.
static func args_ok(op: int, args: Variant) -> bool:
	if not ARGS.has(op) or not args is Array:
		return false
	var types: Array = ARGS[op]
	if (args as Array).size() != types.size():
		return false
	for i in types.size():
		if typeof(args[i]) != types[i]:
			return false
	return true
