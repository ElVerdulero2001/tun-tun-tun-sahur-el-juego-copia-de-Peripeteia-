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
##
## Cambio de línea (punto 6): colgado de un compañero, el actor no se predice.
## Esos ticks se guardan con el input y sin estado: el input sigue viajando
## (para soltarse o saltar) y no hay afirmación. Cuando el host dice que ya no
## cuelga, resume() restaura su estado y repite los inputs hasta el presente.
## `step` devuelve si simuló el tick: colgado no lo simula.

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
## La corrección más grande, en metros.
var max_correction_meters := 0.0
## Estados del host sin predicción guardada para comparar (al empezar a predecir).
var alignments := 0
## Veces que se volvió a predecir después de colgar de un compañero.
var resumes := 0

var _inputs := {}  # tick -> ActorInput
var _states := {}  # tick -> estado después del tick, en bytes (vacío si no se predijo)


## Guarda un tick. `state` es null si el tick no se predijo (colgado de un compañero).
func record(tick: int, input: ActorInput, state: ActorState) -> void:
	_inputs[tick] = input
	_states[tick] = state.to_bytes() if state != null else PackedByteArray()


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
		forget_up_to(host_tick)
		return
	if used_input_tick != host_tick:
		waits_late_input += 1
		forget_up_to(host_tick)
		return
	if predicted == null:
		alignments += 1
	else:
		corrections += 1
	var before := BaseRegistry.world_position(actor.state)
	var seen := actor.seen_position()
	_restore_and_replay(actor, host_tick, host_state, current_tick, step)
	# Paso 8: el cuerpo saltó, pero lo que se ve arranca desde donde se veía.
	actor.smooth_from(seen)
	if predicted != null:
		last_correction_meters = before.distance_to(BaseRegistry.world_position(actor.state))
		max_correction_meters = maxf(max_correction_meters, last_correction_meters)
	forget_up_to(host_tick)


## Fin del cambio de línea: el host dice que en host_tick el actor ya no cuelga
## de un compañero (se soltó, saltó o lo soltaron). Se restaura ese estado y se
## repiten los inputs guardados hasta el presente, como en una corrección,
## aunque el host haya usado un input repetido: del cliente no hay afirmación
## que adoptar. La mezcla de lo que se ve la hace quien llama.
func resume(actor: ActorBody, host_tick: int, host_state: PackedByteArray, current_tick: int, step: Callable) -> void:
	resumes += 1
	_restore_and_replay(actor, host_tick, host_state, current_tick, step)
	forget_up_to(host_tick)


## Un evento programado llegó cuando ya se había predicho su tick: se
## restaura lo predicho para el tick anterior y se repite desde ahí, ahora con
## el evento (`step` lo aplica en su tick). Devuelve falso si ese tick ya se
## olvidó o no se predijo; entonces lo arregla la corrección del snapshot.
func replay_from(actor: ActorBody, tick: int, current_tick: int, step: Callable) -> bool:
	var before: PackedByteArray = _states.get(tick - 1, PackedByteArray())
	if before.is_empty():
		return false
	var seen := actor.seen_position()
	_restore_and_replay(actor, tick - 1, before, current_tick, step)
	actor.smooth_from(seen)
	return true


## Pone el actor en `state` (el del tick `tick`) y repite los ticks siguientes
## hasta current_tick - 1 con los inputs guardados.
func _restore_and_replay(actor: ActorBody, tick: int, state: PackedByteArray, current_tick: int, step: Callable) -> void:
	actor.state = ActorState.from_bytes(state)
	actor.apply_state(actor.state)
	for t in range(tick + 1, current_tick):
		var input: ActorInput = _inputs.get(t)
		if input == null:
			continue
		var stepped: bool = step.call(input)
		_states[t] = actor.state.to_bytes() if stepped else PackedByteArray()


## Olvida lo guardado hasta `tick` inclusive: el host ya lo confirmó o lo reemplazó.
func forget_up_to(tick: int) -> void:
	for t in _states.keys():
		if t <= tick:
			_states.erase(t)
			_inputs.erase(t)
