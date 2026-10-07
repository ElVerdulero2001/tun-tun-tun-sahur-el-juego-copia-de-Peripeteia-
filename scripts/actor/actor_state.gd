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

enum Mode { GROUND, AIR, SLIDE, LADDER }
## Postura: parado o agachado. Cada una tiene su forma de colisión preparada.
enum Stance { STANDING, CROUCHED }

const POSITION_STEP := 0.0001
const VELOCITY_STEP := 0.001
const NORMAL_STEP := 0.0001
const TIME_STEP := 0.0001
const YAW_STEPS := 65536
## Largo de to_bytes(). Lo que llega por red con otro largo se descarta.
const BYTE_SIZE := 67

## Con base, relativa a ella; sin base, en el mundo. Ver BaseRegistry.world_position().
var position := Vector3.ZERO
## Con base, la velocidad propia relativa a ella; la de la base no se guarda,
## se suma recién al dejarla.
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
## Id de red de la base sobre la que está parado (plataforma, balsa), o 0.
var base_id := 0
## Postura que pidieron el modo o el input en el último tick.
var stance_wanted: int = Stance.STANDING
## Postura concedida: la que cupo. Decide la forma de colisión activa.
var stance: int = Stance.STANDING
## Modos anclados: id de red del ancla (en Ladder, la escalera) y el parámetro
## sobre ella (en Ladder, la altura de los pies sobre la escalera, en metros).
var anchor_id := 0
var anchor_t := 0.0
## Bloqueo de reagarre: al soltar un ancla por un salto o un empujón, no se la
## puede volver a agarrar por este tiempo.
var regrab_id := 0
var regrab_left := 0.0


func quantize() -> void:
	position = _q3(position, POSITION_STEP)
	velocity = _q3(velocity, VELOCITY_STEP)
	floor_normal = _q3(floor_normal, NORMAL_STEP)
	facing_yaw = quantize_yaw(facing_yaw)
	coyote_left = _q(coyote_left, TIME_STEP)
	jump_buffer_left = _q(jump_buffer_left, TIME_STEP)
	jump_presses_seen &= 0xFF
	epoch &= 0xFFFF
	base_id &= 0xFFFF
	anchor_id &= 0xFFFF
	anchor_t = _q(anchor_t, POSITION_STEP)
	regrab_id &= 0xFFFF
	regrab_left = _q(regrab_left, TIME_STEP)


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
	b.put_u16(base_id & 0xFFFF)
	b.put_u8(stance_wanted)
	b.put_u8(stance)
	b.put_u16(anchor_id & 0xFFFF)
	b.put_32(roundi(anchor_t / POSITION_STEP))
	b.put_u16(regrab_id & 0xFFFF)
	b.put_32(roundi(regrab_left / TIME_STEP))
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
	s.base_id = b.get_u16()
	s.stance_wanted = b.get_u8()
	s.stance = b.get_u8()
	s.anchor_id = b.get_u16()
	s.anchor_t = b.get_32() * POSITION_STEP
	s.regrab_id = b.get_u16()
	s.regrab_left = b.get_32() * TIME_STEP
	return s


func describe() -> String:
	return "modo=%s postura=%s (pedida %s) suelo=%s base=%d ancla=%d t=%.4f reagarre=%d/%.4f pos=%s vel=%s yaw=%.4f coyote=%.4f buffer=%.4f saltos=%d época=%d" % [
		Mode.keys()[mode], Stance.keys()[stance], Stance.keys()[stance_wanted], on_floor, base_id,
		anchor_id, anchor_t, regrab_id, regrab_left,
		position, velocity, facing_yaw, coyote_left, jump_buffer_left, jump_presses_seen, epoch,
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
