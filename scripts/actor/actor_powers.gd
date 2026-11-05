class_name ActorPowers
extends RefCounted

## Estados activos de un actor (el súper salto y velocidad, la cámara lenta) y
## su gasto de estamina. Los prende y los apaga el jugador con su tecla; los
## guarda ActorState.powers, un bit por estado, así viajan, se predicen y se
## repiten como el resto del estado.
##
## Reglas (decididas por el usuario, 2026-11-02):
## - Mientras un estado está prendido gasta estamina, a su costo por segundo
##   del Tuning; con varios prendidos, los costos se suman.
## - Con la reserva en cero no se prende ninguno.
## - Si la reserva llega a cero, se apagan todos juntos, una sola vez
##   (ActorState.exhaustions sube, para el sonido del HUD).
## - La estamina no vuelve sola: solo con consumibles (ActorVitals).
##
## El reloj del gasto (elección de Claude, no del usuario) es el tick: cada
## tick cobra el costo por segundo dividido 60 (SimClock.TICK_RATE). Siguen
## siendo 60 ticks por segundo real también con la cámara lenta del mundo, así
## que un estado cuesta lo mismo por segundo real con o sin ella. No usa el dt
## del motor, que es tiempo del mundo (con la cámara lenta, 0,3 de un tick):
## así la cámara lenta no se abarata sola. Tampoco depende de los cuadros por
## segundo: el motor corre una vez por tick, y al repetir ticks se parte del
## estado guardado, así que un tick no se cobra dos veces.
##
## Para sumar un estado nuevo (la invisibilidad, por ejemplo): un bit y una
## fila en LIST, su costo en el Tuning, su tecla en el Mapa de entrada con su
## contador en ActorInput y ActorState, y su efecto donde corresponda. El HUD
## dibuja una luz por cada fila prendida.

const BOOST := 1 << 0
const SLOW := 1 << 1
const ALL := BOOST | SLOW

## Cada estado: su bit, su nombre en el HUD, su ícono (lo dibuja el HUD) y el
## valor del Tuning con su costo en estamina por segundo.
const LIST := [
	{"bit": BOOST, "name": "Súper", "icon": &"bolt", "cost": &"boost_stamina_cost"},
	{"bit": SLOW, "name": "Cámara lenta", "icon": &"hourglass", "cost": &"slow_stamina_cost"},
]

## La estamina se guarda en enteros: una unidad de estamina son STAMINA_UNIT.
## Así un costo por segundo con hasta tres decimales se cobra exacto por tick
## (1 por segundo = 1000 por tick) y no se acumulan errores de redondeo.
const STAMINA_UNIT := 60000
## STAMINA_UNIT / SimClock.TICK_RATE: lo que cobra por tick un costo de 1 por segundo.
const STAMINA_PER_TICK := 1000


## Al empezar el paso del motor (etapa 3, eventos): cada pulsación nueva del 2
## del teclado numérico prende o apaga el súper y cada una del 1, el pedido de
## cámara lenta propio; dos que caen entre dos ticks se anulan. Después cobra
## el tick y, si la reserva se acaba, apaga todo.
##
## `died`: el actor murió en este tick, antes de llegar acá (un consumible justo
## antes del motor, o el daño en el tiempo de la etapa 1). La muerte gana: las
## pulsaciones de este tick se cuentan como vistas, pero no prenden nada, así
## el tick termina con todo apagado como dice la regla de la muerte. Una
## pulsación del tick siguiente ya vale (auditoría del 2026-11-04, INV-04).
static func step(state: ActorState, input: ActorInput, tuning: ActorTuning, died := false) -> void:
	var power_presses := (input.power_presses - state.power_presses_seen) & 0xFF
	state.power_presses_seen = input.power_presses
	var ability_presses := (input.ability_presses - state.ability_presses_seen) & 0xFF
	state.ability_presses_seen = input.ability_presses
	if died:
		state.powers = 0
		return
	if power_presses % 2 == 1:
		_toggle(state, BOOST)
	if ability_presses % 2 == 1:
		_toggle(state, SLOW)
	_charge(state, tuning)


## Prende o apaga un estado. Con la reserva en cero no se prende.
static func _toggle(state: ActorState, bit: int) -> void:
	if state.powers & bit:
		state.powers &= ~bit
	elif state.stamina > 0:
		state.powers |= bit


static func _charge(state: ActorState, tuning: ActorTuning) -> void:
	if state.powers == 0:
		return
	var cost := tick_cost(state.powers, tuning)
	if cost <= 0:
		return
	state.stamina = maxi(state.stamina - cost, 0)
	if state.stamina == 0:
		state.powers = 0
		state.exhaustions = (state.exhaustions + 1) & 0xFF


## Cuánto cobra un tick con esos estados prendidos, en unidades internas.
static func tick_cost(powers: int, tuning: ActorTuning) -> int:
	var total := 0
	for power: Dictionary in LIST:
		if powers & power["bit"]:
			total += cost_per_tick(tuning.get(power["cost"]))
	return total


## Un costo por segundo en unidades internas por tick: redondeado a milésimas,
## y nunca negativo (un costo negativo no puede devolver reserva).
static func cost_per_tick(per_second: float) -> int:
	if not is_finite(per_second) or per_second <= 0.0:
		return 0
	return roundi(per_second * STAMINA_PER_TICK)


## Gasto por segundo con esos estados prendidos, en estamina visible.
static func cost_per_second(powers: int, tuning: ActorTuning) -> float:
	return tick_cost(powers, tuning) * SimClock.TICK_RATE / float(STAMINA_UNIT)


## Los apaga todos sin contar un agotamiento: al morir, al cortarse la
## conexión. No suena nada.
static func retire(state: ActorState) -> void:
	state.powers = 0


## Los nombres de los estados prendidos, para el panel del laboratorio.
static func names(powers: int) -> PackedStringArray:
	var list := PackedStringArray()
	for power: Dictionary in LIST:
		if powers & power["bit"]:
			list.append(power["name"])
	return list
