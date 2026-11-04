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
## Largo de write_to(): 12 hasta el 2026-11-04, cuando se sumó el uso de
## consumibles (use_presses y use_uid).
const BYTE_SIZE := 17

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
## Contador de usos de consumibles, igual que el de salto, y el objeto del
## último uso (su id en el inventario). Desde el 2026-11-04 un consumible se usa
## así, sin esperar al host: cuando el contador cambia, el cliente aplica el
## efecto en su predicción y el host, en el mismo tick, lo valida con el
## inventario de verdad y gasta la unidad (InvNet.use_before_step). Va un uso
## por tick.
var use_presses := 0
var use_uid := 0


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
	return move.length_squared() <= 1.01 and (buttons & ~ALL_BUTTONS) == 0


## Escribe el input en BYTE_SIZE bytes. Como ya está cuantizado, leerlo del
## otro lado da exactamente los mismos valores.
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
	b.put_u32(use_uid & 0xFFFFFFFF)


static func read_from(b: StreamPeerBuffer) -> ActorInput:
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
	input.use_uid = b.get_u32()
	return input
