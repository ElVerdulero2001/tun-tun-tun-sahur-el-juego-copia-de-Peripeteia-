extends Node
## Validacion independiente (Claude), entrega 15, parte L. Copia de cv14_lanes.gd (que no se toca)
## para el canal nuevo de Codex (latido confiable). Tres procesos ENet reales: host, cliente e
## intruso. Cada carril es un nodo en la misma ruta en los tres procesos:
##  - la mayoria usa cv15_tap_channel.gd (misma configuracion RPC que el canal base, cuenta llegadas);
##  - quiet_base y quiet_base_2 usan el canal base de Codex SIN subclase;
##  - quiet_unrel y quiet_unrel_2 usan la subclase VIEJA cv14_tap_channel.gd (latido no confiable):
##    control negativo que mide si en esta corrida ENet tiro latidos no confiables.
## Con --stress=1 cada proceso llama throttle_configure(100, 0, 32) en sus peers ENet (intento de
## estrangulamiento, rotulado). Los sobres son opacos (4 KB) y nunca llegan a un deserializador.
const Channel = preload("res://prototypes/objetos_adaptador/authority_channel.gd")
const Tap15 = preload("res://prototypes/objetos_adaptador/validacion_claude/cv15_tap_channel.gd")
const TapOld = preload("res://prototypes/objetos_adaptador/validacion_claude/cv14_tap_channel.gd")
const LANES := ["notice", "scope_close", "scope_heartbeat", "good_heartbeat", "intruder_close",
	"intruder_heartbeat", "startup", "send_timeout", "both_close", "quiet", "quiet_idle",
	"quiet_base", "quiet_base_2", "quiet_unrel", "quiet_unrel_2"]
const END_S := 6.3
const FIELDS := ["connection", "context", "uid", "epoch", "hold_session"]

var role := "host"
var port := 29471
var result_path := ""
var stress := false
var lanes := {}
var kinds := {}
var scopes := {}
var rec := {}
var client_id := 0
var intruder_id := 0
var t0 := 0.0
var begun := false
var done := false
var offset_ms := 0.0
var last_forge := 0
var last_sample := 0
var throttle: Array = []
var forged := {"close": 0, "heartbeat": 0}
var fired := {}
var infos := {}
var rpc_guard := {}
var started_ms := Time.get_ticks_msec()

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
		elif arg == "--stress=1": stress = true
	offset_ms = unix_ms() - Time.get_ticks_msec()
	var scripts: Array[Script] = [Channel, Tap15, TapOld]
	var base_cfg = scripts[0].get_rpc_config()
	var t15_cfg = scripts[1].get_rpc_config()
	var old_cfg = scripts[2].get_rpc_config()
	rpc_guard.types = [typeof(base_cfg), typeof(t15_cfg), typeof(old_cfg)]
	if typeof(base_cfg) != TYPE_DICTIONARY: base_cfg = {}
	if typeof(t15_cfg) != TYPE_DICTIONARY: t15_cfg = {}
	if typeof(old_cfg) != TYPE_DICTIONARY: old_cfg = {}
	rpc_guard.merge({"base": {"_heartbeat": base_cfg.get("_heartbeat"), "_remote_close": base_cfg.get("_remote_close")},
		"tap15": {"_heartbeat": t15_cfg.get("_heartbeat"), "_remote_close": t15_cfg.get("_remote_close")},
		"tap14": {"_heartbeat": old_cfg.get("_heartbeat")}})
	rpc_guard.ok = base_cfg.get("_heartbeat") != null and str(base_cfg.get("_heartbeat")) == str(t15_cfg.get("_heartbeat")) \
		and str(base_cfg.get("_remote_close")) == str(t15_cfg.get("_remote_close")) \
		and str(base_cfg.get("_heartbeat")) != str(old_cfg.get("_heartbeat"))
	for i in LANES.size():
		var name: String = LANES[i]
		var kind := "base" if name.begins_with("quiet_base") else ("tap14_unreliable" if name.begins_with("quiet_unrel") else "tap15")
		var lane = Channel.new() if kind == "base" else (TapOld.new() if kind == "tap14_unreliable" else Tap15.new())
		lane.name = "Lane_" + name; add_child(lane)
		lanes[name] = lane; kinds[name] = kind
		scopes[name] = {"connection": 21, "context": 3, "uid": 100 + i, "epoch": 2, "hold_session": 4,
			"hand_signature": ("lane_%s" % name).sha256_text()}
		rec[name] = {"kind": kind, "closes": [], "start_ok": false, "start_msec": -1, "silence_unix": -1.0, "stop_unix": -1.0,
			"act_prev": -1, "act_max_gap": 0, "act_updates": 0, "tx_started_msec": -1, "restart_ok": null}
		lane.closed.connect(_on_closed.bind(name))
	var peer := ENetMultiplayerPeer.new()
	if role == "host":
		infos.listen = peer.create_server(port, 2, 2)
	else:
		infos.connect = peer.create_client("127.0.0.1", port, 2)
		multiplayer.connected_to_server.connect(func(): _hello.rpc_id(1, role))
	multiplayer.multiplayer_peer = peer

func unix_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0

func rel() -> float:
	return (unix_ms() / 1000.0) - t0

@rpc("any_peer", "call_remote", "reliable")
func _hello(r: String) -> void:
	if role != "host": return
	var id := multiplayer.get_remote_sender_id()
	if r == "client": client_id = id
	elif r == "intruder": intruder_id = id
	if client_id != 0 and intruder_id != 0 and not begun:
		_begin.rpc_id(client_id, intruder_id)
		_begin.rpc_id(intruder_id, client_id)
		begin()

@rpc("authority", "call_remote", "reliable")
func _begin(other: int) -> void:
	if role == "intruder": client_id = other
	else: intruder_id = other
	begin()

func peer_ids() -> Array:
	return multiplayer.get_peers() if role == "host" else [1]

func begin() -> void:
	t0 = unix_ms() / 1000.0
	begun = true
	if stress:
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		for id in peer_ids():
			var pp := enet.get_peer(id)
			if pp != null: pp.throttle_configure(100, 0, 32) # seam_: intento de estrangulamiento
	if role == "intruder": return
	for name in LANES:
		var target := client_id if role == "host" else 1
		rec[name].start_ok = lanes[name].start(scopes[name], target)
		rec[name].start_msec = Time.get_ticks_msec()
	if role == "client":
		# seam_: el cliente rechaza todo sobre de este carril (revision vieja), sin mandar ACK.
		lanes.send_timeout._last_revision = 0x7FFFFF00

func scope_bytes(scope: Dictionary) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	Channel._write_scope(b, scope)
	return b.data_array

func old_variants(name: String) -> Array:
	var out: Array = []
	for f in FIELDS:
		var s: Dictionary = scopes[name].duplicate(); s[f] -= 1
		out.append(scope_bytes(s))
	var h: Dictionary = scopes[name].duplicate()
	var sig: String = h.hand_signature
	h.hand_signature = ("f" if sig[0] != "f" else "e") + sig.substr(1)
	out.append(scope_bytes(h))
	return out

func size_variants(name: String) -> Array:
	var good := scope_bytes(scopes[name])
	var longer := good.duplicate(); longer.append(0)
	return [PackedByteArray(), good.slice(0, 51), longer]

func once(key: String) -> bool:
	if fired.has(key): return false
	fired[key] = true
	return true

func publish(name: String) -> void:
	var p: Dictionary = scopes[name].duplicate()
	p.version = 1; p.revision = 1; p.tick = 0; p.acks = []
	var opaque := PackedByteArray(); opaque.resize(4096); opaque.fill(7)
	p.snapshot = opaque # opaco: queda en el canal del receptor, nunca se deserializa
	rec[name].publish_ok = lanes[name].publish(p)

func _process(_dt: float) -> void:
	if not begun or done: return
	var t := rel()
	var now := Time.get_ticks_msec()
	observe(now)
	if role == "host": host_schedule(t, now)
	elif role == "client": client_schedule(t)
	else: intruder_schedule(t, now)
	if t >= END_S: finish()

func observe(now: int) -> void:
	for name in LANES:
		var lane = lanes[name]
		if role == "intruder" or not lane._bound: continue
		var a: int = lane._last_peer_activity
		var r: Dictionary = rec[name]
		if r.act_prev >= 0 and a != r.act_prev:
			r.act_max_gap = maxi(r.act_max_gap, a - r.act_prev); r.act_updates += 1
		r.act_prev = a
		if role == "host" and r.tx_started_msec < 0 and not lane._tx.is_empty(): r.tx_started_msec = lane._tx.started
	if now - last_sample >= 100:
		last_sample = now
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		for id in peer_ids():
			var pp := enet.get_peer(id)
			if pp == null: continue
			throttle.append([snappedf(rel(), 0.001), id, pp.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE),
				pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), pp.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)])

func host_schedule(t: float, now: int) -> void:
	if t >= 0.3 and once("publish"):
		for name in LANES: if name != "startup": publish(name)
	if t >= 1.0 and once("h1"):
		rec.notice.stop_unix = unix_ms() / 1000.0; lanes.notice.stop()
		for b in old_variants("scope_close") + size_variants("scope_close"):
			lanes.scope_close._remote_close.rpc_id(client_id, b); forged.close += 1
		for name in ["scope_heartbeat", "good_heartbeat"]:
			rec[name].silence_unix = unix_ms() / 1000.0; lanes[name].stop(false)
		rec.both_close.stop_unix = unix_ms() / 1000.0; lanes.both_close.stop()
	if t >= 1.0 and now - last_forge >= 100:
		last_forge = now
		var variants := old_variants("scope_heartbeat")
		lanes.scope_heartbeat._heartbeat.rpc_id(client_id, variants[forged.heartbeat % variants.size()])
		lanes.good_heartbeat._heartbeat.rpc_id(client_id, scope_bytes(scopes.good_heartbeat))
		forged.heartbeat += 1
	if t >= 1.5 and once("h_restart"):
		rec.notice.restart_ok = lanes.notice.start(scopes.notice, client_id)
	if t >= 5.0 and once("h5"):
		rec.scope_close.stop_unix = unix_ms() / 1000.0; lanes.scope_close.stop()

func client_schedule(t: float) -> void:
	if t >= 1.0 and once("c1"):
		for b in old_variants("scope_close") + size_variants("scope_close"):
			lanes.scope_close._remote_close.rpc_id(1, b); forged.close += 1
		rec.intruder_heartbeat.silence_unix = unix_ms() / 1000.0; lanes.intruder_heartbeat.stop(false)
		rec.both_close.stop_unix = unix_ms() / 1000.0; lanes.both_close.stop()
	if t >= 1.5 and once("c_restart"):
		rec.notice.restart_ok = lanes.notice.start(scopes.notice, 1)
	if t >= 5.0 and once("c5"):
		rec.intruder_close.stop_unix = unix_ms() / 1000.0; lanes.intruder_close.stop()

func intruder_schedule(t: float, now: int) -> void:
	if t >= 1.0 and once("i1"):
		var good := scope_bytes(scopes.intruder_close)
		lanes.intruder_close._remote_close.rpc_id(1, good)
		lanes.intruder_close._remote_close.rpc_id(client_id, good) # reenviado por el servidor
		forged.close += 2
	if t >= 1.0 and now - last_forge >= 100:
		last_forge = now
		lanes.intruder_heartbeat._heartbeat.rpc_id(1, scope_bytes(scopes.intruder_heartbeat))
		forged.heartbeat += 1

func _on_closed(name: String) -> void:
	if done: return
	var lane = lanes[name]
	rec[name].closes.append({"unix": unix_ms() / 1000.0, "rel": snappedf(rel(), 0.001), "msec": Time.get_ticks_msec(),
		"error": lane.last_error, "last_activity_msec": lane._last_peer_activity,
		"last_activity_unix": (lane._last_peer_activity + offset_ms) / 1000.0})

func finish() -> void:
	if done: return
	done = true
	var lane_out := {}
	for name in LANES:
		var lane = lanes[name]
		var r: Dictionary = rec[name].duplicate(true)
		r.bound_at_end = lane._bound
		r.stats = lane.stats()
		r.last_error = lane.last_error
		r.peer_active = lane._peer_active
		if r.tx_started_msec >= 0: r.tx_started_unix = (r.tx_started_msec + offset_ms) / 1000.0
		r.start_unix = (r.start_msec + offset_ms) / 1000.0 if r.start_msec >= 0 else -1.0
		if lane.get("heartbeats_in") != null:
			r.heartbeats_in = lane.heartbeats_in
			r.closes_in = lane.closes_in
			r.heartbeat_at_unix = {}
			for s in lane.heartbeat_at:
				r.heartbeat_at_unix[s] = lane.heartbeat_at[s].map(func(m): return (m + offset_ms) / 1000.0)
		lane_out[name] = r
	var result := {"role": role, "t0": t0, "offset_ms": offset_ms, "client_id": client_id, "intruder_id": intruder_id,
		"lanes": lane_out, "throttle": throttle, "forged": forged, "infos": infos, "stress": stress,
		"rpc_guard": rpc_guard, "timeout_ms": Channel.TIMEOUT_MS, "heartbeat_ms": Channel.HEARTBEAT_MS,
		"process_ms": Time.get_ticks_msec() - started_ms, "server_relay": (multiplayer as SceneMultiplayer).server_relay}
	if not result_path.is_empty(): FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(result, "", false))
	print(JSON.stringify({"role": role, "done": true, "rpc_guard_ok": rpc_guard.ok}))
	await get_tree().create_timer(0.15, true, false, true).timeout
	multiplayer.multiplayer_peer.close()
	get_tree().quit(0)
