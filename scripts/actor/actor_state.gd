class_name ActorState
extends RefCounted

## Estado completo de un actor al final de un tick.
##
## Regla de oro de la arquitectura: nada que influya en el movimiento futuro
## vive fuera de este objeto. Si algo queda afuera (un timer de nodo, una
## variable suelta en otro script), repetir ticks después de una corrección
## diverge.
##
## Al final de cada tick se cuantiza. Así host y cliente arrancan el tick
## siguiente desde los mismos números, y comparar dos estados es comparar
## sus bytes. La posición se cuantiza a 0,1 mm: alcanza para niveles de
## hasta unos 800 m desde el origen; más lejos, float32 pierde ese detalle.

enum Mode { GROUND, AIR }

const POSITION_STEP := 0.0001
const VELOCITY_STEP := 0.001
const NORMAL_STEP := 0.0001
const TIME_STEP := 0.0001
const YAW_STEPS := 65536
## Largo de to_bytes(). Lo que llega por red con otro largo se descarta.
const BYTE_SIZE := 51

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var facing_yaw := 0.0
var mode: int = Mode.AIR
## Salida del último movimiento. Se guarda acá porque is_on_floor() solo
## vale justo después de move_and_slide(), no después de restaurar.
var on_floor := false
var floor_normal := Vector3.UP
var coyote_left := 0.0
var jump_buffer_left := 0.0
## Último valor del contador de pulsaciones de salto que ya se procesó.
var jump_presses_seen := 0
## Época: cuántos eventos del host que cambian la simulación de este actor
## (un empujón, un teleport) ya están incluidos. Solo la sube el host; el motor
## no la toca. El host no adopta una afirmación con otra época: sería de un
## cliente que todavía no vio el evento.
var epoch := 0


func quantize() -> void:
	position = _q3(position, POSITION_STEP)
	velocity = _q3(velocity, VELOCITY_STEP)
	floor_normal = _q3(floor_normal, NORMAL_STEP)
	facing_yaw = quantize_yaw(facing_yaw)
	coyote_left = _q(coyote_left, TIME_STEP)
	jump_buffer_left = _q(jump_buffer_left, TIME_STEP)
	jump_presses_seen &= 0xFF
	epoch &= 0xFFFF


func copy() -> ActorState:
	return ActorState.from_bytes(to_bytes())


func to_bytes() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	_put3(b, position, POSITION_STEP)
	_put3(b, velocity, VELOCITY_STEP)
	_put3(b, floor_normal, NORMAL_STEP)
	b.put_u16(yaw_to_index(facing_yaw))
	b.put_u8(mode)
	b.put_u8(1 if on_floor else 0)
	b.put_32(roundi(coyote_left / TIME_STEP))
	b.put_32(roundi(jump_buffer_left / TIME_STEP))
	b.put_u8(jump_presses_seen & 0xFF)
	b.put_u16(epoch & 0xFFFF)
	return b.data_array


static func from_bytes(bytes: PackedByteArray) -> ActorState:
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var s := ActorState.new()
	s.position = _get3(b, POSITION_STEP)
	s.velocity = _get3(b, VELOCITY_STEP)
	s.floor_normal = _get3(b, NORMAL_STEP)
	s.facing_yaw = index_to_yaw(b.get_u16())
	s.mode = b.get_u8()
	s.on_floor = b.get_u8() == 1
	s.coyote_left = b.get_32() * TIME_STEP
	s.jump_buffer_left = b.get_32() * TIME_STEP
	s.jump_presses_seen = b.get_u8()
	s.epoch = b.get_u16()
	return s


func describe() -> String:
	return "modo=%s suelo=%s pos=%s vel=%s yaw=%.4f coyote=%.4f buffer=%.4f saltos=%d época=%d" % [
		Mode.keys()[mode], on_floor, position, velocity, facing_yaw,
		coyote_left, jump_buffer_left, jump_presses_seen, epoch,
	]


static func quantize_yaw(yaw: float) -> float:
	return index_to_yaw(yaw_to_index(yaw))


static func yaw_to_index(yaw: float) -> int:
	return posmod(roundi(yaw / TAU * YAW_STEPS), YAW_STEPS)


static func index_to_yaw(index: int) -> float:
	var yaw := index * TAU / YAW_STEPS
	return yaw - TAU if yaw >= PI else yaw


static func _q(value: float, step: float) -> float:
	return roundi(value / step) * step


static func _q3(v: Vector3, step: float) -> Vector3:
	return Vector3(_q(v.x, step), _q(v.y, step), _q(v.z, step))


static func _put3(b: StreamPeerBuffer, v: Vector3, step: float) -> void:
	b.put_32(roundi(v.x / step))
	b.put_32(roundi(v.y / step))
	b.put_32(roundi(v.z / step))


static func _get3(b: StreamPeerBuffer, step: float) -> Vector3:
	var x := b.get_32() * step
	var y := b.get_32() * step
	var z := b.get_32() * step
	return Vector3(x, y, z)
