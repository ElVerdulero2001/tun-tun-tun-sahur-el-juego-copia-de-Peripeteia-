extends "res://prototypes/objetos_adaptador/history_bridge.gd"

## El registro de la historia del personaje de la entrega 16 (history_bridge.gd)
## para el invitado de la pista de objetos, con dos cambios para el laboratorio:
##
## 1. Lo que se guarda de cada input es la copia para objetos
##    (PistaPiloto.object_input): sin los usos de consumibles ni lo que afirma
##    de un objeto del inventario, y con la intención de la mano de la pista.
##    Así un tick repetido (ClientPrediction) guarda lo mismo que el tick
##    original, aunque el input del laboratorio lleve otras cosas.
## 2. replay_actor_from: repetir ticks del personaje desde uno anterior (una
##    cámara lenta o un empujón que llegaron tarde) avisando al mundo de
##    objetos, como apply_world_slow, sin tocar los tramos de cámara lenta (eso
##    lo hace el laboratorio, que además lleva sus propias cuentas).

## func(ActorInput) -> ActorInput: la copia para objetos. La pone PistaPiloto.
var normalize: Callable


func _intent_bytes(input: ActorInput) -> PackedByteArray:
	if input == null or not normalize.is_valid():
		return PackedByteArray()
	return super._intent_bytes(normalize.call(input))


## Repite los ticks del personaje desde `first` hasta el anterior al presente,
## con el paso del laboratorio, y rehace la historia del mundo de objetos desde
## `first`. `cause`: "actor" (un empujón) o "world_time" (cámara lenta).
func replay_actor_from(first: int, current_tick: int, cause: String) -> bool:
	if clock == null or _replaying or current_tick != clock.tick or first < 0 or first >= current_tick \
			or cause not in ["actor", "world_time"]:
		return _fail("invalid_replay")
	_setup_replay(first, first, -1, cause)
	_begin_rebuild()
	var ok := prediction.replay_from(actor, first, current_tick, _step_replay)
	_finish_replay(current_tick - 1, ok)
	return ok
