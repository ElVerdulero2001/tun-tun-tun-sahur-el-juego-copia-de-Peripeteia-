class_name ActorInput
extends RefCounted

## Input de un tick: lo único que el jugador aporta a la simulación.
##
## Se cuantiza al crearlo. Así lo que se simula, lo que se guarda para repetir
## ticks y lo que viaja por red (desde el paso 4) es exactamente lo mismo.

const BUTTON_JUMP := 1 << 0
const BUTTON_CROUCH := 1 << 1
const BUTTON_RUN := 1 << 2
const AXIS_STEPS := 127.0

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


static func make(p_tick: int, p_move: Vector2, p_look_yaw: float, p_buttons: int, p_jump_presses: int) -> ActorInput:
	var input := ActorInput.new()
	input.tick = p_tick
	var m := p_move.limit_length(1.0)
	input.move = Vector2(roundi(m.x * AXIS_STEPS) / AXIS_STEPS, roundi(m.y * AXIS_STEPS) / AXIS_STEPS)
	input.look_yaw = ActorState.quantize_yaw(p_look_yaw)
	input.buttons = p_buttons
	input.jump_presses = p_jump_presses & 0xFF
	return input


func is_held(button: int) -> bool:
	return (buttons & button) != 0


## Escribe el input en 10 bytes. Como ya está cuantizado, leerlo del otro lado
## da exactamente los mismos valores.
func write_to(b: StreamPeerBuffer) -> void:
	b.put_32(tick)
	b.put_8(roundi(move.x * AXIS_STEPS))
	b.put_8(roundi(move.y * AXIS_STEPS))
	b.put_u16(ActorState.yaw_to_index(look_yaw))
	b.put_u8(buttons)
	b.put_u8(jump_presses)


static func read_from(b: StreamPeerBuffer) -> ActorInput:
	var input := ActorInput.new()
	input.tick = b.get_32()
	var x := b.get_8() / AXIS_STEPS
	var y := b.get_8() / AXIS_STEPS
	input.move = Vector2(x, y)
	input.look_yaw = ActorState.index_to_yaw(b.get_u16())
	input.buttons = b.get_u8()
	input.jump_presses = b.get_u8()
	return input
