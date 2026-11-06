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

## HOOKED es el modo Enganchado de la arquitectura: colgado de un compañero.
## CABLE es colgado de un cable (la Tirolesa de la arquitectura).
## MANTLE es subirse a un borde bajo sin colgarse (desde el 2026-10-25; hasta
## entonces estaba fuera del alcance): ver ActorMotor.mantle_check.
enum Mode { GROUND, AIR, SLIDE, LADDER, HANGING, HOOKED, CABLE, MANTLE }
## Postura: parado, agachado o encogido. Cada una tiene su forma de colisión.
## Encogido es parado con los pies más arriba (hang_climb_tuck): lo usa el
## salto para arriba desde el colgado, y solo existe en el aire.
enum Stance { STANDING, CROUCHED, TUCKED }

const POSITION_STEP := 0.0001
const VELOCITY_STEP := 0.001
const NORMAL_STEP := 0.0001
const TIME_STEP := 0.0001
const YAW_STEPS := 65536
## Largo de to_bytes(). Lo que llega por red con otro largo se descarta. Hasta
## el 2026-11-01 eran 93: la salud, la estamina y lo demás del jugador van al
## final, así los primeros 93 bytes siguen siendo los del movimiento. Desde el
## 2026-11-02 a la tarde, con el daño en el tiempo, 152; desde el 2026-11-04,
## con el contador de usos de consumibles, 153; desde el 2026-11-05, con la
## integridad corporal, 165. Por red viaja con su largo en un byte: no puede
## pasar de 255.
const BYTE_SIZE := 165
## La salud se guarda en milésimas de punto: así el daño en el tiempo la baja
## un poquito en cada tick, parejo, sin saltos de a un punto.
const HEALTH_UNIT := 1000
## Cuántos daños en el tiempo puede tener encima a la vez (se acumulan).
const MAX_EFFECTS := 4
## Integridad corporal (desde el 2026-11-05): seis partes independientes, en
## este orden. Cada una va de 0 a 100 %, guardada en centésimas de punto
## (INTEGRITY_UNIT por punto): así una caída que se reparte entre las dos
## piernas les quita lo mismo a cada una, sin redondeos.
enum Part { HEAD, TORSO, ARM_LEFT, ARM_RIGHT, LEG_LEFT, LEG_RIGHT }
const PARTS := 6
const INTEGRITY_UNIT := 100
const INTEGRITY_FULL := 100 * INTEGRITY_UNIT
## Salud y estamina de un estado nuevo: los máximos de fábrica del Tuning
## (health_max y stamina_max). Al aparecer, el actor nace con los del Tuning
## (NetSession); estos son para las pruebas que arman un estado a mano.
const START_HEALTH := 100 * HEALTH_UNIT
const START_STAMINA := 200 * ActorPowers.STAMINA_UNIT
## regrab_id de un bloqueo de bordes (Hanging), distinto de cualquier escalera.
## También bloquea los cables: si no, uno al alcance de las manos atrapa al
## que salta del borde, y desde el cable el salto vuelve al borde (pedido del
## usuario, 2026-10-18).
const REGRAB_EDGES := 0xFFFF
## regrab_id de un bloqueo de compañeros (Enganchado): no se puede volver a
## colgar de ninguno por un rato. También bloquea los cables, y el de cables
## bloquea también a los compañeros: si no, del compañero colgado de un cable
## el salto pasa al cable, y desde el cable vuelve al compañero, una y otra vez
## (pedido del usuario, 2026-10-19).
const REGRAB_TEAMMATES := 0xFFFE
## regrab_id de un bloqueo de cables: no se puede volver a agarrar de ninguno
## por un rato, ni colgarse de un compañero (ver REGRAB_TEAMMATES).
const REGRAB_CABLES := 0xFFFD

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
## Modos anclados: id de red del ancla y el parámetro sobre ella.
## - Ladder: la escalera, y la altura de los pies sobre ella, en metros.
## - Hanging: la base que lleva el borde (0 si es geometría fija); anchor_t
##   vale 0, salvo doblando una esquina (por afuera o por adentro, ver
##   corner_inside): cuánto giró la normal desde la cara
##   donde empezó, en radianes, con signo (ver ActorMotor._hang).
## - Hooked: el id de red (peer) del compañero del que cuelga, y la altura de
##   las manos sobre sus pies, en metros: al agarrarse, la cintura
##   (hook_height); después, la que dejaron W y S. De qué lado cuelga lo dice
##   facing_yaw, que mira hacia él: mirando hacia donde mira él, de su espalda
##   (ver ActorMotor.hook_check).
## - Cable: el cable, y la distancia sobre él desde su origen, en metros.
## - Mantle: como Hanging, la base que lleva el borde (0 si es geometría
##   fija); anchor_t es hacia dónde mira la normal del borde (un giro, como
##   facing_yaw), porque al pasar arriba el cuerpo mira hacia donde va y no a
##   la pared. Cuánto subió y avanzó sale de dónde está el cuerpo respecto del
##   filo.
var anchor_id := 0
var anchor_t := 0.0
## Hanging y Mantle: el punto del filo, relativo al origen de la base del ancla
## (en el mundo si es geometría fija); doblando, la esquina. Colgado, la normal
## del borde no se guarda: es la contraria a facing_yaw, que mira a la pared (en
## el mantle va en anchor_t).
## Hooked: dónde están las manos sobre el compañero, en el mundo. Cable: dónde
## están las manos sobre el cable, en el mundo. Los dos los usa la presentación;
## la simulación los vuelve a calcular cada tick.
var anchor_point := Vector3.ZERO
## Id de red (peer) del compañero que cuelga de este actor, o 0. Lo escribe solo
## el host, como un evento que sube la época; el motor lo borra cuando este
## actor deja de estar agarrado.
var hooked_by := 0
## Bloqueo de reagarre: al soltar un ancla por un salto o un empujón, no se la
## puede volver a agarrar por este tiempo. Para Hanging, regrab_id vale
## REGRAB_EDGES y bloquea todos los bordes, porque un borde no tiene id propio,
## y también todos los cables.
var regrab_id := 0
var regrab_left := 0.0
## Estados activos del jugador, un bit por estado (ActorPowers): el súper
## salto y velocidad y su pedido de cámara lenta del mundo. Los prende y los
## apaga su tecla (la misma), y gastan estamina mientras están prendidos.
var powers := 0
## Súper salto y velocidad: si está prendido. Es el bit ActorPowers.BOOST.
var boosted: bool:
	get:
		return (powers & ActorPowers.BOOST) != 0
	set(value):
		powers = (powers | ActorPowers.BOOST) if value else (powers & ~ActorPowers.BOOST)
## El último valor del contador de pulsaciones del súper (2 del teclado
## numérico) que ya se procesó, y el del de la cámara lenta (1).
var power_presses_seen := 0
var ability_presses_seen := 0
## El último valor del contador de usos de consumibles (ActorInput.use_presses)
## que ya se procesó, desde el 2026-11-04 (InvNet.use_before_step).
var use_presses_seen := 0
## Salud, en milésimas de punto (HEALTH_UNIT por punto): de 0 al máximo del
## Tuning (health_max, 100 puntos). No vuelve sola. La cambian los consumibles
## (ActorVitals: desde el 2026-11-04 se usan desde el input, igual en el host y
## en la predicción), los eventos del host y el daño en el tiempo, que
## descuenta el motor; al llegar a cero, muerte de prueba y vuelve al máximo.
var health := START_HEALTH
## Daños en el tiempo encima (consumibles, desde el 2026-11-02), hasta
## MAX_EFFECTS a la vez, cada uno con su ritmo: cuánto quita en total, en
## milésimas de punto; cuánto dura y cuánto lleva, en tiempo del mundo, en
## milésimas de tick (con la cámara lenta corre más despacio). Con el total y
## lo que lleva, cada tick quita justo lo que le toca, sin atrasos de redondeo.
## Un lugar con duración 0 está libre. Los descuenta ActorVitals.step.
var effect_total := PackedInt32Array([0, 0, 0, 0])
var effect_duration := PackedInt32Array([0, 0, 0, 0])
var effect_elapsed := PackedInt32Array([0, 0, 0, 0])
## Estamina, en unidades internas (ActorPowers.STAMINA_UNIT por unidad): de 0 a
## stamina_max del Tuning (200). No vuelve sola: la gastan los estados
## prendidos (ActorPowers) y la devuelven los consumibles.
var stamina := START_STAMINA
## Contadores para avisar una sola vez, de 0 a 255 y dan la vuelta: muertes de
## prueba (las sube el host) y agotamientos (la reserva llegó a cero con algún
## estado prendido; los sube el motor). El HUD avisa cuando cambian; repetir
## ticks da el mismo número, así que no avisa dos veces.
var deaths := 0
var exhaustions := 0
## Integridad de cada parte del cuerpo (Part), en centésimas de punto: de 0 a
## INTEGRITY_FULL. Es aparte de la salud. Por ahora la baja solo una caída
## (ActorVitals.land, que la calcula el motor igual en el host y en la
## predicción) y la devuelve entera la muerte de prueba (reglas provisorias del
## laboratorio, 2026-11-05). Desde el 2026-11-06 también la sube un consumible
## soltado sobre una parte del panel de integridad: un uso del input, que la
## PC del jugador predice y el host valida (InvNet.queue_use con la parte,
## InvAuthority._heal_part; hasta la noche del 2026-11-06, un evento del host).
var integrity := PackedInt32Array([INTEGRITY_FULL, INTEGRITY_FULL, INTEGRITY_FULL, INTEGRITY_FULL,
		INTEGRITY_FULL, INTEGRITY_FULL])
## Hanging, doblando (anchor_t distinto de 0): si es un rincón, por adentro.
var corner_inside := false
## Si saltó (desde el piso, una escalera, un borde o un compañero, o en el
## aire) desde que dejó el piso o algo de donde estaba agarrado. Cayendo sin
## haber saltado tiene el salto en el aire, y desde el 2026-10-25 no hay
## mantle (ver ActorMotor.mantle_check).
var jumped := false
## Salió por arriba de una escalera con W, en tercera persona y mirando para
## atrás: mientras siga así y apretando W sola, va derecho hacia donde subía
## (facing_yaw). Soltar W, tocar A, S o D, pasar a primera persona o girar la
## cámara hacia adelante lo corta, y también agarrarse de algo.
var straight_out := false
## Escalera a la que vuelve solo, o 0: la que dejó saltando mirándola o con
## Ctrl. Bajando frente a ella y sin Ctrl, se agarra sin teclas (si el salto
## pasó por encima del final, al volver a bajar hasta ella). Se borra al
## apoyarse o agarrarse de algo, y con A o D (desde el 2026-10-20).
var ladder_return := 0
## Se cayó de un borde sin saltar (se quedó sin piso caminando o
## deslizándose, en un piso fijo): mientras no salte, en el aire sin teclas
## frena (desde el 2026-10-22). Se borra al apoyarse o agarrarse de algo, y
## con un empujón.
var walked_off := false


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
	anchor_id &= 0xFFFFFFFF
	anchor_t = _q(anchor_t, POSITION_STEP)
	anchor_point = _q3(anchor_point, POSITION_STEP)
	regrab_id &= 0xFFFF
	regrab_left = _q(regrab_left, TIME_STEP)
	hooked_by &= 0xFFFFFFFF
	power_presses_seen &= 0xFF
	ladder_return &= 0xFFFF
	powers &= 0xFF
	ability_presses_seen &= 0xFF
	use_presses_seen &= 0xFF
	health = clampi(health, 0, 0x7FFFFFFF)
	stamina = clampi(stamina, 0, 0x7FFFFFFF)
	deaths &= 0xFF
	exhaustions &= 0xFF
	for i in MAX_EFFECTS:
		effect_total[i] = maxi(effect_total[i], 0)
		effect_duration[i] = maxi(effect_duration[i], 0)
		effect_elapsed[i] = clampi(effect_elapsed[i], 0, effect_duration[i])
	for i in PARTS:
		integrity[i] = clampi(integrity[i], 0, INTEGRITY_FULL)


## Lo que es del jugador y no del movimiento: los contadores de pulsaciones
## (si se pierden, la próxima parece una pulsación nueva), los estados
## prendidos, la salud, los daños en el tiempo, la estamina, la integridad del
## cuerpo y los contadores de avisos. Lo usa quien arma un estado nuevo para el
## mismo jugador (al reaparecer).
func keep_player_state(from: ActorState) -> void:
	jump_presses_seen = from.jump_presses_seen
	power_presses_seen = from.power_presses_seen
	ability_presses_seen = from.ability_presses_seen
	use_presses_seen = from.use_presses_seen
	powers = from.powers
	health = from.health
	effect_total = from.effect_total.duplicate()
	effect_duration = from.effect_duration.duplicate()
	effect_elapsed = from.effect_elapsed.duplicate()
	stamina = from.stamina
	integrity = from.integrity.duplicate()
	deaths = from.deaths
	exhaustions = from.exhaustions


## Si alguna parte del cuerpo tiene menos del 100 %: lo que prende la luz naranja.
func injured() -> bool:
	for value in integrity:
		if value < INTEGRITY_FULL:
			return true
	return false


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
	b.put_u32(anchor_id & 0xFFFFFFFF)
	b.put_32(roundi(anchor_t / POSITION_STEP))
	b.put_u16(regrab_id & 0xFFFF)
	b.put_32(roundi(regrab_left / TIME_STEP))
	_put3(b, anchor_point, POSITION_STEP)
	b.put_u32(hooked_by & 0xFFFFFFFF)
	# Donde iba `boosted` (1 o 0): con solo el súper, el mismo byte que antes.
	b.put_u8(powers & 0xFF)
	b.put_u8(power_presses_seen & 0xFF)
	b.put_u8(1 if corner_inside else 0)
	b.put_u8(1 if jumped else 0)
	b.put_u8(1 if straight_out else 0)
	b.put_u16(ladder_return & 0xFFFF)
	b.put_u8(1 if walked_off else 0)
	b.put_u8(ability_presses_seen & 0xFF)
	b.put_32(clampi(health, 0, 0x7FFFFFFF))
	b.put_32(clampi(stamina, 0, 0x7FFFFFFF))
	b.put_u8(deaths & 0xFF)
	b.put_u8(exhaustions & 0xFF)
	for i in MAX_EFFECTS:
		b.put_32(maxi(effect_total[i], 0))
		b.put_32(maxi(effect_duration[i], 0))
		b.put_32(maxi(effect_elapsed[i], 0))
	b.put_u8(use_presses_seen & 0xFF)
	for i in PARTS:
		b.put_u16(clampi(integrity[i], 0, INTEGRITY_FULL))
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
	s.anchor_id = b.get_u32()
	s.anchor_t = b.get_32() * POSITION_STEP
	s.regrab_id = b.get_u16()
	s.regrab_left = b.get_32() * TIME_STEP
	s.anchor_point = _get3(b, POSITION_STEP)
	s.hooked_by = b.get_u32()
	s.powers = b.get_u8()
	s.power_presses_seen = b.get_u8()
	s.corner_inside = b.get_u8() == 1
	s.jumped = b.get_u8() == 1
	s.straight_out = b.get_u8() == 1
	s.ladder_return = b.get_u16()
	s.walked_off = b.get_u8() == 1
	s.ability_presses_seen = b.get_u8()
	s.health = b.get_32()
	s.stamina = b.get_32()
	s.deaths = b.get_u8()
	s.exhaustions = b.get_u8()
	for i in MAX_EFFECTS:
		s.effect_total[i] = b.get_32()
		s.effect_duration[i] = b.get_32()
		s.effect_elapsed[i] = b.get_32()
	s.use_presses_seen = b.get_u8()
	for i in PARTS:
		s.integrity[i] = b.get_u16()
	return s


func describe() -> String:
	return "modo=%s postura=%s (pedida %s) suelo=%s base=%d ancla=%d t=%.4f filo=%s cuelga_de_él=%d reagarre=%d/%.4f rincón=%s súper=%s/%d lenta=%s/%d pos=%s vel=%s yaw=%.4f coyote=%.4f buffer=%.4f saltos=%d saltó=%s derecho=%s vuelve=%d cayó_del_borde=%s salud=%.3f daño_en_el_tiempo=%s estamina=%.3f integridad=%s usos=%d muertes=%d agotamientos=%d época=%d" % [
		Mode.keys()[mode], Stance.keys()[stance], Stance.keys()[stance_wanted], on_floor, base_id,
		anchor_id, anchor_t, anchor_point, hooked_by, regrab_id, regrab_left, "sí" if corner_inside else "no",
		"sí" if boosted else "no", power_presses_seen, "sí" if powers & ActorPowers.SLOW else "no", ability_presses_seen,
		position, velocity, facing_yaw, coyote_left, jump_buffer_left, jump_presses_seen, "sí" if jumped else "no", "sí" if straight_out else "no", ladder_return, "sí" if walked_off else "no",
		health / float(HEALTH_UNIT), effect_total, stamina / float(ActorPowers.STAMINA_UNIT), integrity, use_presses_seen, deaths, exhaustions, epoch,
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
