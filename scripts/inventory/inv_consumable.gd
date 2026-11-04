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


## Hasta el 2026-11-01 el consumible tenía `vitality_gain`: un archivo viejo que
## lo traiga cura eso mismo de salud.
func _set(property: StringName, value: Variant) -> bool:
	if property == &"vitality_gain" and typeof(value) == TYPE_INT:
		health = value
		return true
	return false


func kind() -> int:
	return Kind.USE


func action_text(_loadout: InvLoadout, _stack: InvStack) -> String:
	return "Usar"


func check(_loadout: InvLoadout, _stack: InvStack, vitals: ActorVitals) -> String:
	if vitals == null:
		return "no tenés personaje"
	if health == 0 and stamina <= 0 and damage_over_time <= 0:
		return "no hace nada"
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
	if effects.is_empty():
		return "Al usarlo: no hace nada"
	return "Al usarlo: %s. Gasta una unidad" % " y ".join(effects)


func fingerprint_text() -> String:
	return "%s salud %d estamina %d en el tiempo %d en %s" % [super(), health, stamina, damage_over_time,
			snappedf(damage_seconds, 0.001)]


## Un número con hasta dos decimales, con coma y sin ceros de más: 2, 2,5, 0,33.
static func _number(value: float) -> String:
	var rounded := snappedf(value, 0.01)
	if is_equal_approx(rounded, roundf(rounded)):
		return "%d" % roundi(rounded)
	return ("%.2f" % rounded).rstrip("0").replace(".", ",")
