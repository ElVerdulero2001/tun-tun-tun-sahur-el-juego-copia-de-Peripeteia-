class_name InvConsumable
extends InvAbility

## Consumible: al usarlo cambia la salud y la estamina del personaje que lo usa
## y gasta una unidad. Desde el 2026-11-02 reemplaza a la vitalidad de prueba
## (InvLoadout.test_vitality, un contador del inventario que ya no existe): lo
## que curaba ese contador ahora cura salud.
##
## - Salud positiva cura y negativa daña. Curar no pasa del máximo; un daño
##   mayor que lo que queda mata (muerte de prueba, ver ActorVitals).
## - Estamina devuelve reserva, sin pasar del máximo.
## - Uno que solo cura no se usa ni se gasta con la salud completa; uno que
##   solo devuelve estamina, con la reserva llena. Uno que daña se usa siempre.
## - Daño en el tiempo (desde el 2026-11-02): quita damage_over_time puntos
##   en damage_seconds segundos, parejo, un poco en cada tick, hasta terminar o
##   hasta la muerte. Va con el tiempo del mundo: con la cámara lenta, más
##   despacio. Varios se acumulan, cada uno con su ritmo, hasta 4 a la vez
##   (ActorState.MAX_EFFECTS); con 4 encima, uno que daña en el tiempo no se
##   usa ni se gasta. Lo decidió el usuario; lo descuenta el motor
##   (ActorVitals.step), así se predice y se repite como el resto.
## - Con varios efectos, se usa si alguno hace algo, y se aplican juntos, en un
##   solo paso del host: primero la estamina, después la salud de golpe y
##   después el daño en el tiempo (si la salud de golpe mata, la estamina
##   ganada queda y el daño en el tiempo ya no se pone). Se gasta una unidad.
## - Partes del cuerpo (desde el 2026-11-06, pedido del usuario): uno con
##   part_repair, con Tab, se agarra de la grilla y se suelta sobre una parte
##   dañada del panel de integridad. Le devuelve part_repair puntos de
##   porcentaje (100: la deja entera), sin pasar del 100 %, y gasta una unidad.
##   No toca la salud ni las otras partes, y anda también con la salud
##   completa. Va como un uso en el input, con la parte (InvNet.queue_use):
##   desde el 2026-11-06 a la noche no espera al host (antes era un pedido,
##   HEAL_PART); la PC del jugador lo predice y el host valida y aplica todo
##   junto (InvAuthority._heal_part). Usarlo normal, desde el menú o la barra,
##   sigue haciendo solo lo de arriba.

## Cuánto cambia la salud con cada unidad, en puntos (la completa son 100, el
## health_max del Tuning): positivo cura, negativo daña.
@export_range(-10000, 10000) var health := 25
## Cuánta estamina devuelve cada unidad (la reserva completa son 200).
@export_range(0, 10000) var stamina := 0
@export_group("Daño en el tiempo")
## Cuánta salud quita en total, en puntos, de a poco: 0, nada.
@export_range(0, 10000) var damage_over_time := 0
## En cuántos segundos del mundo lo quita, parejo: 4 en 2 s son 2 por segundo.
@export_range(0.1, 600.0, 0.1) var damage_seconds := 2.0
@export_group("Partes del cuerpo")
## Soltándolo sobre una parte dañada del panel de integridad (con Tab), cuánto
## le devuelve, en puntos de porcentaje: 100 la deja entera; 30 la sube 30
## puntos, sin pasar del 100 %. 0: no cura partes. No cambia el uso normal.
@export_range(0.0, 100.0, 0.01) var part_repair := 0.0


## Hasta el 2026-11-01 el consumible tenía `vitality_gain`: un archivo viejo que
## lo traiga cura eso mismo de salud.
func _set(property: StringName, value: Variant) -> bool:
	if property == &"vitality_gain" and typeof(value) == TYPE_INT:
		health = value
		return true
	return false


func kind() -> int:
	return Kind.USE


## Sí: solo mira la salud y la estamina (y sus propios números), no la pila ni la barra.
func predictable() -> bool:
	return true


func action_text(_loadout: InvLoadout, _stack: InvStack) -> String:
	return "Usar"


func check(_loadout: InvLoadout, _stack: InvStack, vitals: ActorVitals) -> String:
	if vitals == null:
		return "no tenés personaje"
	if health == 0 and stamina <= 0 and damage_over_time <= 0:
		# Uno que solo cura partes (2026-11-06) no se usa ni se gasta así.
		return "se usa con Tab, soltándolo sobre una parte dañada del cuerpo" if repairs_parts() else "no hace nada"
	if damage_over_time > 0 and not vitals.has_room_for_effect():
		return "ya tenés %d daños en el tiempo encima" % ActorState.MAX_EFFECTS
	if health < 0 or damage_over_time > 0:
		return ""
	var heals := health > 0 and not vitals.health_full()
	var restores := stamina > 0 and not vitals.stamina_full()
	if heals or restores:
		return ""
	if health > 0 and stamina > 0:
		return "ya tenés la salud y la estamina completas"
	return "ya tenés la salud completa" if health > 0 else "ya tenés la estamina completa"


func apply(_loadout: InvLoadout, _stack: InvStack, vitals: ActorVitals) -> int:
	vitals.apply(health, maxi(stamina, 0), maxi(damage_over_time, 0), damage_seconds)
	return 1


## Si cura partes del cuerpo (soltándolo sobre el panel de integridad).
func repairs_parts() -> bool:
	return is_finite(part_repair) and part_repair > 0.0


## Lo que le devuelve a una parte, en centésimas de punto (ActorState.INTEGRITY_UNIT).
func part_repair_units() -> int:
	return clampi(roundi(part_repair * ActorState.INTEGRITY_UNIT), 0, ActorState.INTEGRITY_FULL) if repairs_parts() else 0


## Por qué no se puede usar sobre esa parte de ese estado, o vacío si se puede.
## Lo mira la interfaz, con lo que muestra el panel, y lo vuelve a mirar el host.
func check_part(state: ActorState, part: int) -> String:
	if not repairs_parts():
		return "eso no cura partes del cuerpo"
	if state == null:
		return "no tenés personaje"
	if part < 0 or part >= ActorState.PARTS:
		return "esa parte del cuerpo no existe"
	if state.integrity[part] >= ActorState.INTEGRITY_FULL:
		return "esa parte ya está entera"
	return ""


## Host: le devuelve a la parte lo suyo, sin pasar del 100 %. Solo esa parte:
## la salud y las demás quedan como estaban. Devuelve cuántas unidades gasta.
func apply_part(state: ActorState, part: int) -> int:
	state.integrity[part] = mini(state.integrity[part] + part_repair_units(), ActorState.INTEGRITY_FULL)
	return 1


func describe() -> String:
	var effects := PackedStringArray()
	if health > 0:
		effects.append("cura %d de salud" % health)
	elif health < 0:
		effects.append("quita %d de salud (si llega a 0, morís)" % -health)
	if stamina > 0:
		effects.append("recupera %d de estamina" % stamina)
	if damage_over_time > 0:
		effects.append("quita %d de salud de a poco, en %s s (%s por segundo; con la cámara lenta, más despacio)" % [
				damage_over_time, _number(damage_seconds), _number(damage_over_time / maxf(damage_seconds, 0.1))])
	var text := "Al usarlo: %s. Gasta una unidad" % " y ".join(effects)
	if effects.is_empty():
		text = "Usado normal no hace nada ni se gasta" if repairs_parts() else "Al usarlo: no hace nada"
	if repairs_parts():
		var repair := "la deja entera" if part_repair_units() >= ActorState.INTEGRITY_FULL \
				else "le devuelve %s %% (sin pasar del 100 %%)" % _number(part_repair)
		text += ". Con Tab, soltado sobre una parte dañada del cuerpo, %s y gasta una unidad, sin tocar la salud" % repair
	return text


func fingerprint_text() -> String:
	return "%s salud %d estamina %d en el tiempo %d en %s partes %s" % [super(), health, stamina, damage_over_time,
			snappedf(damage_seconds, 0.001), snappedf(part_repair, 0.01)]


## Un número con hasta dos decimales, con coma y sin ceros de más: 2, 2,5, 0,33.
static func _number(value: float) -> String:
	var rounded := snappedf(value, 0.01)
	if is_equal_approx(rounded, roundf(rounded)):
		return "%d" % roundi(rounded)
	return ("%.2f" % rounded).rstrip("0").replace(".", ",")
