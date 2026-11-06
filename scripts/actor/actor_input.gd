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
## día (el contador y cuántos usos van), más USE_BYTES por cada uso que va.
const BYTE_SIZE := 14
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


## Si pudo salir de make(): ejes dentro del círculo (con el redondeo de la
## cuantización) y solo botones que existen. Lo que llega por red y no lo
## cumple no es de este juego.
func is_possible() -> bool:
	return move.length_squared() <= 1.01 and (buttons & ~ALL_BUTTONS) == 0 and uses.size() <= MAX_USES \
			and uses.all(func(use: Array) -> bool: return use.size() < 3 or (use[2] >= -1 and use[2] < ActorState.PARTS))


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
	return input
