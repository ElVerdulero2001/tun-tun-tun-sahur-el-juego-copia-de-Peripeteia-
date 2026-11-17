extends "res://prototypes/objetos_adaptador/probe_lifecycle.gd"
## Real base channel (no RPC override). Quiet after traffic, for > one lease.
var quiet_start := -1
var activity_seen := 0
var max_gap := 0
var min_throttle := 32
var checked := false
var client_checked := false

func after_tick(tick: int) -> void:
	super.after_tick(tick)
	if tick == 20:
		clock.paused = true
		quiet_start = Time.get_ticks_msec()
		activity_seen = channel._last_peer_activity

func _process(_delta: float) -> void:
	if done: return
	var now := Time.get_ticks_msec()
	if now - started > 7200:
		check("quiet_deadline", false); finish(); return
	if quiet_start < 0: return
	if checked:
		if role == "host" and client_checked:
			_quiet_end.rpc_id(peer_id)
			finish()
		return
	max_gap = maxi(max_gap, now - channel._last_peer_activity)
	var peer = multiplayer.multiplayer_peer.get_peer(peer_id if role == "host" else 1)
	if peer != null: min_throttle = mini(min_throttle, int(peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)))
	if now - quiet_start < 5500: return
	check("quiet_for_more_than_lease", now - quiet_start > Channel.TIMEOUT_MS)
	check("live_channel_remains_bound", channel.stats().bound and close_count == 0)
	check("peer_activity_received_while_quiet", channel._last_peer_activity > activity_seen)
	check("heartbeat_gap_below_lease", max_gap < Channel.TIMEOUT_MS)
	print("QUIET_DIAGNOSTIC=" + JSON.stringify({"role": role, "min_throttle": min_throttle, "max_activity_gap_ms": max_gap}))
	checked = true
	if role == "client": _quiet_result.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _quiet_result() -> void:
	if role == "host" and multiplayer.get_remote_sender_id() == peer_id: client_checked = true

@rpc("authority", "call_remote", "reliable")
func _quiet_end() -> void:
	if role == "client" and checked: finish()
