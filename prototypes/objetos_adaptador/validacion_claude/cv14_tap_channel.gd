extends "res://prototypes/objetos_adaptador/authority_channel.gd"
## Diagnostico (Claude), entrega 14, agregado despues de la primera corrida de lanes: cuenta los
## controles que LLEGAN a cada carril, por remitente, y despues llama al metodo original sin
## cambiar nada. Sirve para separar "el latido no llego" (ENet lo tiro) de "llego y se rechazo".
## Mismos nombres de RPC que el original: la configuracion RPC es la misma en los tres procesos.
var heartbeats_in := {}
var heartbeat_at := {}
var closes_in := {}

@rpc("any_peer", "call_remote", "unreliable", 0)
func _heartbeat(data: PackedByteArray) -> void:
	var s := str(multiplayer.get_remote_sender_id())
	heartbeats_in[s] = heartbeats_in.get(s, 0) + 1
	if not heartbeat_at.has(s): heartbeat_at[s] = []
	if heartbeat_at[s].size() < 400: heartbeat_at[s].append(Time.get_ticks_msec())
	super._heartbeat(data)

@rpc("any_peer", "call_remote", "reliable", 0)
func _remote_close(data: PackedByteArray) -> void:
	var s := str(multiplayer.get_remote_sender_id())
	closes_in[s] = closes_in.get(s, 0) + 1
	super._remote_close(data)
