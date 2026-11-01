class_name InvConsumable
extends InvAbility

## Consumible: al usarlo sube la vitalidad de prueba del jugador y gasta una
## unidad. El laboratorio no tiene salud: la vitalidad de prueba es un contador
## que se ve en la barra rápida, solo para comprobar que el uso pasó por el
## host (ver InvLoadout). Con la vitalidad al máximo no se puede usar, y no se
## gasta nada.

## Cuánto sube la vitalidad de prueba con cada unidad.
@export var vitality_gain := 25


func kind() -> int:
	return Kind.USE


func action_text(_loadout: InvLoadout, _stack: InvStack) -> String:
	return "Usar"


func check(loadout: InvLoadout, _stack: InvStack) -> String:
	if loadout.test_vitality >= InvLoadout.TEST_VITALITY_MAX:
		return "tu vitalidad de prueba ya está al máximo"
	return ""


func apply(loadout: InvLoadout, _stack: InvStack) -> int:
	loadout.test_vitality = mini(loadout.test_vitality + vitality_gain, InvLoadout.TEST_VITALITY_MAX)
	return 1


func describe() -> String:
	return "Al usarlo: +%d de vitalidad de prueba (gasta una unidad)" % vitality_gain


func fingerprint_text() -> String:
	return "%s %d" % [super(), vitality_gain]
