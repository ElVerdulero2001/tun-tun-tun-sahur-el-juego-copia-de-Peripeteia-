extends "res://prototypes/objetos_adaptador/authority_channel.gd"
## Diagnostico (Claude), entrega 15. Reemplaza a cv14_tap_channel.gd para el canal nuevo: la
## entrega 15 hizo CONFIABLE a _heartbeat, y la subclase vieja lo redeclaraba no confiable (sus
## carriles median otro canal). Esta redeclara _heartbeat y _remote_close con la MISMA
## configuracion RPC que el canal base (confiable, canal 0), cuenta llegadas por remitente y llama
## al metodo original sin cambiar nada. cv15_lanes compara get_rpc_config() de esta subclase con
## la del canal base al arrancar e invalida la corrida si difieren.
var heartbeats_in := {}
var heartbeat_at := {}
var closes_in := {}

@rpc("any_peer", "call_remote", "reliable", 0)
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
