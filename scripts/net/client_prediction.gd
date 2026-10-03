class_name ClientPrediction
extends RefCounted

## Paso 6: el cliente simula su propio actor por adelantado y lo corrige con lo
## que dice el host.
##
## Por cada tick predicho guarda el input usado y el estado resultante. Cuando
## llega el estado del host para un tick S, lo compara con lo guardado para S:
## si coincide, no hace nada; si no, restaura S y repite los ticks siguientes
## con los inputs guardados. Solo se repite este actor: el mundo no se rebobina.
##
## Paso 7: lo guardado también es lo que viaja al host. Cada paquete lleva los
## últimos inputs junto con el estado predicho de ese tick (la afirmación), ya
## corregido si hubo una repetición.

## Veces que el host coincidió byte a byte con lo predicho.
var matches := 0
## Veces que no coincidió y hubo que restaurar y repetir.
var corrections := 0
## Estados del host calculados repitiendo un input viejo porque el nuestro no
## había llegado. No se corrige con ellos: es probable que el host adopte la
## afirmación del tick siguiente, y corregir ahora sería corregir dos veces.
var waits_late_input := 0
## Cuánto se movió el actor en la última corrección, en metros.
var last_correction_meters := 0.0
## Estados del host sin predicción guardada para comparar (al empezar a predecir).
var alignments := 0

var _inputs := {}  # tick -> ActorInput
var _states := {}  # tick -> estado después del tick, en bytes


func record(tick: int, input: ActorInput, state: ActorState) -> void:
	_inputs[tick] = input
	_states[tick] = state.to_bytes()


func clear() -> void:
	_inputs.clear()
	_states.clear()


## Los últimos `count` ticks predichos que el host todavía no confirmó, del más
## viejo al más nuevo: [ActorInput, estado en bytes] por tick.
func recent(count: int) -> Array:
	var ticks := _inputs.keys()
	var list := []
	for i in range(maxi(ticks.size() - count, 0), ticks.size()):
		list.append([_inputs[ticks[i]], _states[ticks[i]]])
	return list


## Compara el estado del host para host_tick con lo predicho y corrige si hace
## falta. Se llama al empezar el tick current_tick, así que lo predicho llega
## hasta current_tick - 1. `step` mueve el actor un tick con un input.
func reconcile(actor: ActorBody, host_tick: int, host_state: PackedByteArray, used_input_tick: int, current_tick: int, step: Callable) -> void:
	var predicted: Variant = _states.get(host_tick)
	if predicted != null and predicted == host_state:
		matches += 1
		_forget_up_to(host_tick)
		return
	if used_input_tick != host_tick:
		waits_late_input += 1
		_forget_up_to(host_tick)
		return
	if predicted == null:
		alignments += 1
	else:
		corrections += 1
	var before := BaseRegistry.world_position(actor.state)
	var seen := actor.seen_position()
	actor.state = ActorState.from_bytes(host_state)
	actor.apply_state(actor.state)
	for t in range(host_tick + 1, current_tick):
		var input: ActorInput = _inputs.get(t)
		if input == null:
			continue
		step.call(input)
		_states[t] = actor.state.to_bytes()
	# Paso 8: el cuerpo saltó, pero lo que se ve arranca desde donde se veía.
	actor.smooth_from(seen)
	if predicted != null:
		last_correction_meters = before.distance_to(BaseRegistry.world_position(actor.state))
	_forget_up_to(host_tick)


func _forget_up_to(tick: int) -> void:
	for t in _states.keys():
		if t <= tick:
			_states.erase(t)
			_inputs.erase(t)
