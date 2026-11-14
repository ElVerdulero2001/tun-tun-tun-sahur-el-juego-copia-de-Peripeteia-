class_name ActorInput
extends RefCounted

## Input de un tick: lo único que el jugador aporta a la simulación.
##
## Se cuantiza al crearlo. Así lo que se simula, lo que se guarda para repetir
## ticks y lo que viaja por red (desde el paso 4) es exactamente lo mismo.

const BUTTON_JUMP := 1 << 0
const BUTTON_CROUCH := 1 << 1
const BUTTON_RUN := 1 << 2
## No es una tecla: la cámara está en tercera persona (lo bastante lejos de la
## cabeza como para que se dibuje el cuerpo). El motor lo usa al salir por
## arriba de una escalera (ver ActorMotor.straight_exit).
const BUTTON_THIRD_PERSON := 1 << 3
const ALL_BUTTONS := BUTTON_JUMP | BUTTON_CROUCH | BUTTON_RUN | BUTTON_THIRD_PERSON
const AXIS_STEPS := 127.0
## Largo de write_to() sin usos de consumibles: 12 hasta el 2026-11-04, cuando
## se sumó el uso (17, con un solo objeto); 14 desde la auditoría de ese mismo
## día (el contador y cuántos usos van), más USE_BYTES por cada uso que va; 15
## desde el 2026-11-14 (si sostiene algo), más HOLD_BYTES si sostiene.
const BYTE_SIZE := 15
## Lo que sostiene: la sesión (4), hacia dónde mira la cámara para arriba o
## para abajo (2), la distancia (2) y el giro pedido (8).
const HOLD_BYTES := 16
const PITCH_STEPS := 32767.0
const ROTATION_STEPS := 32767.0
## Cada uso: el objeto (4), el último pedido antes (4) y, desde el 2026-11-06 a
## la noche, la parte del cuerpo sobre la que se soltó (1: 0 es el uso normal,
## de 1 a 6 una de ActorState.Part).
const USE_BYTES := 9
## Como mucho, cuántos usos sin confirmar viajan en un input. La interfaz no
## deja más de InvNet.MAX_USES_WAITING sin confirmar, y de esos salen a lo sumo
## estos; los demás esperan a que el host confirme alguno.
const MAX_USES := 8

var tick := 0
## Ejes de movimiento: x hacia la derecha, y hacia adelante, cada uno de -1 a 1.
var move := Vector2.ZERO
## Hacia dónde mira la cámara, en radianes; 0 mira hacia -Z.
var look_yaw := 0.0
## Botones mantenidos, en bits.
var buttons := 0
## Contador de pulsaciones de salto, de 0 a 255 y da la vuelta. Si se pierde
## el tick exacto en que se apretó, el contador igual cambió.
var jump_presses := 0
## Contador de pulsaciones de la tecla de cámara lenta del mundo (1 del
## teclado numérico), igual que el de salto. Desde el 2026-11-02 lo usa el
## motor (ActorPowers): prende o apaga el pedido de cámara lenta de este
## jugador, que gasta su estamina. El host prende la del mundo mientras alguno
## la pida.
var ability_presses := 0
## Contador de pulsaciones del súper salto y velocidad (2 del teclado
## numérico), igual que el de salto. Lo usa el motor: cada jugador lo activa
## para sí mismo, sin esperar al host.
var power_presses := 0
## Contador de usos de consumibles, igual que el de salto: el número del uso
## más nuevo que salió. Desde el 2026-11-04 un consumible se usa así, sin
## esperar al host: cuando el contador cambia, el cliente aplica el efecto en
## su predicción y el host lo valida con el inventario de verdad y gasta la
## unidad (InvNet.use_before_step). Sale un uso nuevo por tick.
var use_presses := 0
## Los usos que el host todavía no confirmó, del más viejo al más nuevo: el
## último es el del número use_presses, el anterior el de use_presses - 1, y
## así. Cada uno es [id del objeto, número del último pedido al host hecho
## antes de usarlo, parte del cuerpo]: la parte es -1 en el uso normal, o una
## de ActorState.Part si se soltó sobre ella en el panel de integridad (desde
## el 2026-11-06 a la noche: antes era un pedido que esperaba al host,
## HEAL_PART). Hasta el 2026-11-04 iba solo el último uso; si el host se
## salteaba el tick del anterior, ese uso se perdía (auditoría, INV-01). Ahora
## cada uso viaja en todos los inputs hasta que el host lo confirma, y el host
## no lo valida antes de procesar ese pedido (INV-02: lo recogido justo antes).
var uses: Array = []
## Lo que el jugador sostiene con la mano en el mundo (desde el 2026-11-14),
## vacío si nada: [sesión del agarre (InvProtocol.Op.GRAB), pitch de la cámara
## (en pasos de PITCH_STEPS sobre 90°), distancia de los ojos al punto agarrado
## (en milímetros), y el giro pedido relativo al yaw de la cámara (cuatro
## números en pasos de ROTATION_STEPS)]. Es una intención: el host lleva el
## objeto hacia ahí con su física y sus límites (InvBodies). No lo usa el
## motor del personaje, y al repetir ticks en el cliente no hace nada.
var hold: Array = []


static func make(p_tick: int, p_move: Vector2, p_look_yaw: float, p_buttons: int, p_jump_presses: int, p_ability_presses: int = 0, p_power_presses: int = 0) -> ActorInput:
	var input := ActorInput.new()
	input.tick = p_tick
	var m := p_move.limit_length(1.0)
	var x := roundi(m.x * AXIS_STEPS)
	var y := roundi(m.y * AXIS_STEPS)
	# Redondeado, el largo puede pasar apenas de 1 (0,976 y -0,236 dan 1,0045):
	# armar el input otra vez con ese movimiento lo achicaría y daría otro paso.
	# El host lo hace con lo que recibe, así que se achica acá el eje más
	# largo, de a un paso, hasta que el largo no pase de 1.
	var steps := roundi(AXIS_STEPS)
	while x * x + y * y > steps * steps:
		if absi(x) >= absi(y):
			x -= signi(x)
		else:
			y -= signi(y)
	input.move = Vector2(x / AXIS_STEPS, y / AXIS_STEPS)
	input.look_yaw = ActorState.quantize_yaw(p_look_yaw)
	input.buttons = p_buttons
	input.jump_presses = p_jump_presses & 0xFF
	input.ability_presses = p_ability_presses & 0xFF
	input.power_presses = p_power_presses & 0xFF
	return input


func is_held(button: int) -> bool:
	return (buttons & button) != 0


## Lo que va en `hold`, cuantizado: así lo que usa esta máquina es lo mismo que
## lee el host. `pitch` en radianes (positivo mira para arriba), `distance` en
## metros y `rotation` relativo al yaw de la cámara.
static func pack_hold(session: int, pitch: float, distance: float, rotation: Quaternion) -> Array:
	var q := rotation.normalized() if rotation.is_finite() and rotation.length_squared() > 0.0001 else Quaternion.IDENTITY
	if q.w < 0.0:
		q = -q
	return [session, clampi(roundi(pitch / (PI / 2.0) * PITCH_STEPS), -32767, 32767),
			clampi(roundi(distance * 1000.0), 0, 65535),
			roundi(q.x * ROTATION_STEPS), roundi(q.y * ROTATION_STEPS), roundi(q.z * ROTATION_STEPS), roundi(q.w * ROTATION_STEPS)]


func hold_session() -> int:
	return hold[0] if not hold.is_empty() else 0


func hold_pitch() -> float:
	return hold[1] / PITCH_STEPS * (PI / 2.0) if not hold.is_empty() else 0.0


func hold_distance() -> float:
	return hold[2] / 1000.0 if not hold.is_empty() else 0.0


func hold_rotation() -> Quaternion:
	if hold.is_empty():
		return Quaternion.IDENTITY
	var q := Quaternion(hold[3] / ROTATION_STEPS, hold[4] / ROTATION_STEPS, hold[5] / ROTATION_STEPS, hold[6] / ROTATION_STEPS)
	return q.normalized() if q.length_squared() > 0.25 else Quaternion.IDENTITY


## Hacia dónde mira la cámara de este input, con el yaw y el pitch de lo que
## sostiene (sin sostener, el pitch es 0).
func hold_look() -> Vector3:
	return Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, hold_pitch()) * Vector3.FORWARD


## Si pudo salir de make(): ejes dentro del círculo (con el redondeo de la
## cuantización) y solo botones que existen. Lo que llega por red y no lo
## cumple no es de este juego.
func is_possible() -> bool:
	return move.length_squared() <= 1.01 and (buttons & ~ALL_BUTTONS) == 0 and uses.size() <= MAX_USES \
			and uses.all(func(use: Array) -> bool: return use.size() < 3 or (use[2] >= -1 and use[2] < ActorState.PARTS)) \
			and (hold.is_empty() or (hold.size() == 7 and hold[0] >= 1 and absi(hold[1]) <= 32767 and hold[2] >= 0
					and hold[2] <= 65535))


## Escribe el input en BYTE_SIZE bytes, más USE_BYTES por cada uso. Como ya
## está cuantizado, leerlo del otro lado da exactamente los mismos valores.
func write_to(b: StreamPeerBuffer) -> void:
	b.put_32(tick)
	b.put_8(roundi(move.x * AXIS_STEPS))
	b.put_8(roundi(move.y * AXIS_STEPS))
	b.put_u16(ActorState.yaw_to_index(look_yaw))
	b.put_u8(buttons)
	b.put_u8(jump_presses)
	b.put_u8(ability_presses & 0xFF)
	b.put_u8(power_presses & 0xFF)
	b.put_u8(use_presses & 0xFF)
	var count := mini(uses.size(), MAX_USES)
	b.put_u8(count)
	for i in range(uses.size() - count, uses.size()):
		b.put_u32(uses[i][0] & 0xFFFFFFFF)
		b.put_u32(uses[i][1] & 0xFFFFFFFF)
		b.put_u8(((uses[i][2] if uses[i].size() > 2 else -1) + 1) & 0xFF)
	b.put_u8(1 if hold.size() == 7 else 0)
	if hold.size() == 7:
		b.put_u32(hold[0] & 0xFFFFFFFF)
		b.put_16(hold[1])
		b.put_u16(hold[2])
		for i in range(3, 7):
			b.put_16(hold[i])


## El input que escribió write_to(), o null si no tiene esa forma (más usos de
## los que pueden ir, o cortado).
static func read_from(b: StreamPeerBuffer) -> ActorInput:
	if b.get_available_bytes() < BYTE_SIZE:
		return null
	var input := ActorInput.new()
	input.tick = b.get_32()
	var x := b.get_8() / AXIS_STEPS
	var y := b.get_8() / AXIS_STEPS
	input.move = Vector2(x, y)
	input.look_yaw = ActorState.index_to_yaw(b.get_u16())
	input.buttons = b.get_u8()
	input.jump_presses = b.get_u8()
	input.ability_presses = b.get_u8()
	input.power_presses = b.get_u8()
	input.use_presses = b.get_u8()
	var count := b.get_u8()
	if count > MAX_USES or b.get_available_bytes() < count * USE_BYTES:
		return null
	for i in count:
		var uid := b.get_u32()
		var after := b.get_u32()
		var part := b.get_u8() - 1
		if part >= ActorState.PARTS:
			return null
		input.uses.append([uid, after, part])
	if b.get_available_bytes() < 1:
		return null
	var holding := b.get_u8()
	if holding > 1 or (holding == 1 and b.get_available_bytes() < HOLD_BYTES):
		return null
	if holding == 1:
		input.hold = [b.get_u32(), b.get_16(), b.get_u16(), b.get_16(), b.get_16(), b.get_16(), b.get_16()]
	return input
