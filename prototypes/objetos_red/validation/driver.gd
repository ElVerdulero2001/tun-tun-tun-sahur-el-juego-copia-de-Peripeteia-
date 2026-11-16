extends Node

## Driver de validación independiente (Claude). Instancia main.tscn sin
## modificarlo, ejecuta un caso y registra mediciones propias en otro archivo.
##
## Orden por paso físico (registrado en driver_boot):
##   1. este nodo, process_physics_priority = -10: acciones del caso;
##   2. ObjectSyncPrototype (main.gd), prioridad 0: captura, eventos, tick += 1, prepare;
##   3. nodo Post, prioridad +10: mide la pose después de correcciones y antes del paso.
## Una acción pedida aquí se ejecuta en el MISMO tick que main numera a continuación.
## Por cuadro, Post._process (prioridad +10) mide el modelo ya colocado por main._process.
##
## Argumentos propios después de `--`: --case=NOMBRE --dlog=RUTA [--prep-ms=6000] [--limit-ms=17000]
## Los de main.gd (--host, --join, --trace, --slow, red...) pasan sin cambios.

const MainScene := preload("res://main.tscn")
const State := preload("res://runtime/state.gd")
const DRIVER_PRIORITY := -10
const POST_PRIORITY := 10
const ANCHOR := Vector3(0, 0.2, 0) # centro de masa: el objetivo es el centro de masa
const THROW_DIR := Vector3(-1, 0.3, 0)

class Post extends Node:
	var driver
	func _physics_process(_delta: float) -> void:
		driver.post_physics()
	func _process(_delta: float) -> void:
		driver.post_process()

var main: Node
var post: Node
var role := "solo"
var case_name := ""
var slow := 1.0
var log_file: FileAccess
var t0 := 0
var prep_ms := 6000
var limit_ms := 17000
var steps: Array = []
var step_i := 0
var step_ticks := 0
var finished := false
var peer_id := 0
var peer_left := false
var stable_count := 0
var goal := Transform3D.IDENTITY
var commands := {} # etiqueta -> diccionario del comando (referencia, main completa el tick)
var actions := {} # etiqueta -> id de acción
var pred_seen := {}
var held_bytes := {} # host: uid -> último estado HELD codificado
var last_free_rev := {}
var _frame_physics := 0
var post_stall_ms := 0

func _ready() -> void:
	t0 = Time.get_ticks_usec()
	process_physics_priority = DRIVER_PRIORITY
	var dlog := ""
	for a in OS.get_cmdline_user_args():
		if a == "--host": role = "host"
		elif a.begins_with("--join="): role = "client"
		elif a.begins_with("--case="): case_name = a.trim_prefix("--case=")
		elif a.begins_with("--dlog="): dlog = a.trim_prefix("--dlog=")
		elif a.begins_with("--slow="): slow = float(a.trim_prefix("--slow="))
		elif a.begins_with("--prep-ms="): prep_ms = int(a.trim_prefix("--prep-ms="))
		elif a.begins_with("--limit-ms="): limit_ms = int(a.trim_prefix("--limit-ms="))
	if dlog.is_empty():
		push_error("driver: falta --dlog")
		get_tree().quit(5)
		return
	log_file = FileAccess.open(dlog, FileAccess.WRITE)
	if log_file == null:
		push_error("driver: no se pudo abrir " + dlog)
		get_tree().quit(5)
		return
	main = MainScene.instantiate()
	add_child(main)
	post = Post.new()
	post.name = "Post"
	post.driver = self
	post.process_physics_priority = POST_PRIORITY
	post.process_priority = POST_PRIORITY
	add_child(post)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	steps = _build_case()
	dl("driver_boot", {"case": case_name, "role": main.role, "mode": main.mode, "slow": slow,
		"driver_physics_priority": process_physics_priority, "main_physics_priority": main.process_physics_priority,
		"post_physics_priority": post.process_physics_priority, "post_process_priority": post.process_priority,
		"order": "driver(-10) -> main(0) -> post(+10)", "steps": steps.size(),
		"engine": Engine.get_version_info().string, "args": OS.get_cmdline_user_args()})
	if steps.is_empty():
		push_error("driver: caso desconocido " + case_name)
		finish("unknown_case", 5)

func _on_peer_connected(id: int) -> void:
	peer_id = id
	dl("peer_connected", {"peer": id})

func _on_peer_disconnected(id: int) -> void:
	peer_left = true
	dl("peer_disconnected", {"peer": id})

func _exit_tree() -> void:
	if log_file != null:
		log_file.flush()
		log_file.close()
		log_file = null

func dl(kind: String, fields := {}) -> void:
	if log_file == null: return
	var e := {"k": kind, "usec": Time.get_ticks_usec() - t0, "f": Engine.get_physics_frames(),
		"pf": Engine.get_process_frames(), "tick": main.tick if main != null else -1}
	e.merge(fields, true)
	log_file.store_line(JSON.stringify(e, "", false, true))
	if kind not in ["pp", "dr"]: log_file.flush()

func finish(reason: String, code: int) -> void:
	if finished: return
	finished = true
	dl("end", {"reason": reason, "code": code, "step": step_i, "steps": steps.size(),
		"step_op": steps[step_i].op if step_i < steps.size() else ""})
	if log_file != null: log_file.flush()
	get_tree().quit(code)

# ------------------------------------------------------------------ casos
func s(op: String, fields := {}) -> Dictionary:
	var d := {"op": op}
	d.merge(fields, true)
	return d

func _hold_steps(h: float, x := -0.5, z := 0.0) -> Array:
	return [s("ready"), s("grab", {"uid": 1, "at": Vector3(x, h + 0.2, z)}), s("stable", {"uid": 1})]

func _after_release() -> Array:
	return [s("handoff", {"uid": 1}), s("wait", {"n": 60}), s("end")]

func _build_case() -> Array:
	if role == "host":
		match case_name:
			"moving":
				return [s("ready"), s("wait_remote_held_stable", {"uid": 1, "near": Vector3(0.3, 1.0, 0.0)}),
					s("grab", {"uid": 2, "at": Vector3(1.1, 0.25, 0.0)}), s("stable", {"uid": 2}),
					s("move", {"vel": Vector3(-1, 0, 0), "n": 150}), s("host_end")]
			"wall":
				return [s("ready"), s("grab", {"uid": 2, "at": Vector3(1.0, 0.5, -2.0)}), s("stable", {"uid": 2}),
					s("move", {"vel": Vector3(0, 0, -1), "n": 60}), s("wait", {"n": 30}),
					s("rotate", {"axis": Vector3(1, 0, 0), "deg": 90.0, "n": 60}), s("wait", {"n": 30}),
					s("move", {"vel": Vector3(0, -1, 0), "n": 30}), s("wait", {"n": 30}),
					s("release"), s("host_end")]
			"grab_rejected", "throw_rejected":
				return [s("ready"), s("grab", {"uid": 2, "at": Vector3(0.5, 0.6, 0.0)}), s("stable", {"uid": 2}),
					s("move", {"vel": Vector3(0, 0, 0.5), "n": 300}), s("host_end")]
			"stale_snapshot":
				return [s("ready"), s("inject_old_after_release", {"uid": 1}), s("host_end")]
			"disconnect_holding":
				return [s("ready"), s("host_end", {"after": 180})]
			_:
				return [s("ready"), s("host_end")]
	match case_name:
		"drop020": return _hold_steps(0.2) + [s("release")] + _after_release()
		"drop050", "drop050_slow03", "stale_snapshot", "late_release":
			return _hold_steps(0.5) + [s("release")] + _after_release()
		"late_release_hitch":
			return _hold_steps(0.5) + [s("release", {"stall_post_ms": 200})] + _after_release()
		"drop100": return _hold_steps(1.0) + [s("release")] + _after_release()
		"drop050_stall":
			return _hold_steps(0.5) + [s("release"), s("wait", {"n": 6}), s("stall", {"ms": 150})] + _after_release()
		"lateral050":
			return _hold_steps(0.5) + [s("move", {"vel": Vector3(-1.5, 0, 0), "n": 24}), s("release")] + _after_release()
		"throw050": return _hold_steps(0.5) + [s("throw", {"dir": THROW_DIR})] + _after_release()
		"ready_gate":
			return [s("hammer"), s("grab", {"uid": 1, "at": Vector3(-0.5, 0.5, 0.0)}), s("stable", {"uid": 1}),
				s("release"), s("wait", {"n": 30}), s("end")]
		"fingerprint_mismatch":
			return [s("ready"), s("end")]
		"stack":
			return _hold_steps(0.7) + [s("goal_to", {"at": Vector3(0.5, 0.9, 0.0)}), s("stable", {"uid": 1}),
				s("release")] + _after_release()
		"push":
			return _hold_steps(0.015) + [s("move", {"vel": Vector3(1, 0, 0), "n": 60}), s("release")] + _after_release()
		"moving":
			return _hold_steps(0.8) + [s("goal_to", {"at": Vector3(0.3, 1.0, 0.0)}), s("stable", {"uid": 1}),
				s("wait_remote_moving", {"uid": 2, "x_below": 0.85}), s("release")] + _after_release()
		"wall":
			return _hold_steps(0.3, -1.0, -2.0) + [s("move", {"vel": Vector3(0, 0, -1), "n": 60}), s("wait", {"n": 30}),
				s("rotate", {"axis": Vector3.UP, "deg": 90.0, "n": 60}), s("wait", {"n": 30}),
				s("move", {"vel": Vector3(0, -1, 0), "n": 30}), s("wait", {"n": 30}), s("release")] + _after_release()
		"throw_wall":
			return _hold_steps(0.5, -0.5, -1.5) + [s("throw", {"dir": Vector3(0, 0, -1)})] + _after_release()
		"release_before_ack":
			return [s("ready"), s("grab", {"uid": 1, "at": Vector3(-0.5, 0.7, 0.0)}), s("release")] + _after_release()
		"throw_before_ack":
			return [s("ready"), s("grab", {"uid": 1, "at": Vector3(-0.5, 0.7, 0.0)}), s("throw", {"dir": THROW_DIR})] + _after_release()
		"dup_throw":
			return _hold_steps(0.5) + [s("throw", {"dir": THROW_DIR}), s("dup", {"label": "throw"}),
				s("wait_result", {"label": "throw"}), s("dup", {"label": "throw"}), s("handoff", {"uid": 1}),
				s("wait", {"n": 20}), s("flood", {"uid": 1, "n": 300}), s("wait", {"n": 30}),
				s("dup", {"label": "throw"}), s("wait", {"n": 60}), s("end")]
		"disconnect_holding":
			return _hold_steps(0.5) + [s("wait", {"n": 10}), s("disconnect"), s("wait", {"n": 5}), s("end")]
		"grab_rejected":
			return [s("ready"), s("wait_remote_held", {"uid": 2}), s("wait", {"n": 30}), s("grab_shown", {"uid": 2}),
				s("wait_reject"), s("wait", {"n": 150}), s("end")]
		# Casos nuevos de la entrega 2 (criterios_entrega_2.md §4).
		"grab_move":
			return [s("ready"), s("grab", {"uid": 1, "at": Vector3(-0.5, 0.7, 0.0)}),
				s("move", {"vel": Vector3(1, 0, 0), "n": 30}), s("stable", {"uid": 1}), s("release")] + _after_release()
		"grab_move_left":
			# Agregado 13:40: grab_move termina sobre la arista de la caja 2 (x = 0,5).
			return [s("ready"), s("grab", {"uid": 1, "at": Vector3(-0.5, 0.7, 0.0)}),
				s("move", {"vel": Vector3(-1, 0, 0), "n": 30}), s("stable", {"uid": 1}), s("release")] + _after_release()
		"late_grab_hitch":
			return [s("ready"), s("grab", {"uid": 1, "at": Vector3(-0.5, 0.7, 0.0), "stall_post_ms": 200}),
				s("stable", {"uid": 1}), s("release")] + _after_release()
		"throw_rejected":
			return [s("ready"), s("wait_remote_held", {"uid": 2}), s("wait", {"n": 30}), s("grab_shown", {"uid": 2}),
				s("throw", {"dir": THROW_DIR}), s("wait_reject"), s("wait", {"n": 150}), s("end")]
	return []

# ------------------------------------------------------------------ ejecución
func _physics_process(_delta: float) -> void:
	if finished or main == null: return
	var elapsed_ms := (Time.get_ticks_usec() - t0) / 1000
	if elapsed_ms > limit_ms:
		finish("case_timeout", 4)
		return
	if step_i == 0 and elapsed_ms > prep_ms and steps.size() > 0 and steps[0].op in ["ready", "hammer"]:
		finish("prep_timeout", 3)
		return
	if step_i >= steps.size(): return
	var st: Dictionary = steps[step_i]
	var done := _exec(st)
	step_ticks += 1
	if done:
		dl("step_done", {"i": step_i, "op": st.op, "ticks": step_ticks})
		step_i += 1
		step_ticks = 0
		stable_count = 0

func _o(uid: int) -> Dictionary:
	return main.objects[uid]

func _com(t: Transform3D) -> Vector3:
	return t * ANCHOR

func _timeout(base_ticks: int) -> bool:
	return step_ticks > int(base_ticks / slow)

func _exec(st: Dictionary) -> bool:
	match st.op:
		"ready":
			if role == "host": return peer_id != 0
			return main.ready_for_input
		"hammer":
			if main.ready_for_input: return true
			main.request_grab(1, ANCHOR, Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.5, 0)))
			main.set_goal(Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.6, 0)))
			main.request_release()
			main.request_throw(THROW_DIR)
			dl("hammer", {"ready": main.ready_for_input, "pending_grab": main._pending_grab, "local_uid": main.local_uid})
			return false
		"grab":
			goal = Transform3D(Basis.IDENTITY, st.at)
			main.request_grab(st.uid, ANCHOR, goal)
			var accepted: bool = main._pending_grab != 0
			if accepted and not main._local_commands.is_empty(): commands["grab"] = main._local_commands.back()
			actions["grab"] = main._pending_grab
			dl("drv_grab", {"uid": st.uid, "action": main._pending_grab, "queued": accepted, "goal": _v(st.at)})
			if not accepted:
				finish("grab_ignored", 4)
			# Entrega 2 (late_grab_hitch): tirón después de que main ejecutó el agarre
			# local y antes de su _process, igual que en la suelta.
			post_stall_ms = int(st.get("stall_post_ms", 0))
			return true
		"grab_shown":
			# Agarra la réplica en la pose que el jugador ve, como _pick().
			var shown: Transform3D = _o(st.uid).view.shown
			goal = Transform3D(Basis.IDENTITY, _com(shown) + Vector3(0, 0.1, 0))
			main.request_grab(st.uid, ANCHOR, goal)
			actions["grab"] = main._pending_grab
			dl("drv_grab", {"uid": st.uid, "action": main._pending_grab, "queued": main._pending_grab != 0, "goal": _v(goal.origin)})
			return true
		"stable":
			return _stable(st.uid)
		"goal_to":
			goal = Transform3D(goal.basis, st.at)
			main.set_goal(goal)
			dl("drv_goal", {"goal": _v(goal.origin)})
			return true
		"move":
			goal.origin += st.vel * (1.0 / 60.0) * slow
			main.set_goal(goal)
			return step_ticks + 1 >= st.n
		"rotate":
			goal.basis = Basis(st.axis, deg_to_rad(st.deg) / st.n) * goal.basis
			main.set_goal(goal)
			return step_ticks + 1 >= st.n
		"release":
			var before: int = main.next_action
			main.request_release()
			_record_action("release", before)
			# Tirón del invitado DESPUÉS de que main ejecutó la suelta local y antes de
			# su _process: el pedido queda en main._wire hasta que termine el tirón.
			post_stall_ms = int(st.get("stall_post_ms", 0))
			return true
		"throw":
			var before: int = main.next_action
			main.request_throw(st.dir)
			_record_action("throw", before, st.dir)
			return true
		"wait":
			return step_ticks + 1 >= int(st.n / slow)
		"stall":
			dl("drv_stall_begin", {"ms": st.ms})
			OS.delay_msec(st.ms)
			dl("drv_stall_end", {"ms": st.ms})
			return true
		"handoff":
			var o := _o(st.uid)
			if o.prediction.active: pred_seen[st.uid] = true
			if pred_seen.get(st.uid, false) and not o.prediction.active:
				dl("drv_handoff_seen", {"uid": st.uid})
				return true
			if _timeout(600):
				dl("drv_handoff_timeout", {"uid": st.uid, "pred": o.prediction.active})
				return true
			return false
		"wait_result":
			var o := _o(1)
			if o.pending == 0 and step_ticks > 0: return true
			return _timeout(300)
		"dup":
			var c: Dictionary = commands.get(st.label, {})
			if c.is_empty():
				dl("drv_dup_missing", {"label": st.label})
				return true
			main.rpc_id(1, "_command", c.duplicate(true))
			dl("drv_dup", {"label": st.label, "action": c.action, "cmd_tick": c.tick})
			return true
		"flood":
			var base: int = main.next_action + 10000
			for i in st.n:
				var bogus := {"op": "release", "uid": st.uid, "epoch": 1, "session": 999999, "action": base + i,
					"tick": main.tick, "target": Transform3D.IDENTITY, "anchor": Vector3.ZERO, "direction": Vector3.ZERO}
				main.rpc_id(1, "_command", bogus)
			dl("drv_flood", {"uid": st.uid, "n": st.n, "first_action": base})
			return true
		"disconnect":
			dl("drv_disconnect", {"local_uid": main.local_uid})
			main.network.close()
			return true
		"end":
			finish("ok", 0)
			return true
		"host_end":
			if peer_left:
				if not st.has("_left_at"): st["_left_at"] = step_ticks
				if step_ticks - int(st["_left_at"]) >= int(st.get("after", 30)):
					finish("ok", 0)
			return false
		"wait_remote_held_stable":
			var a = _o(st.uid).authority.state
			var b: RigidBody3D = _o(st.uid).body
			var near_ok: bool = _com(b.global_transform).distance_to(st.near) < 0.005
			if a.phase == State.Phase.HELD and a.owner != 1 and near_ok and b.linear_velocity.length() < 0.005:
				stable_count += 1
			else:
				stable_count = 0
			return stable_count >= 20 or (_timeout(600) and _log_timeout(st))
		"wait_remote_held":
			var smp = _o(st.uid).state
			return (smp != null and smp.phase == State.Phase.HELD and _o(st.uid).view.initialized and step_ticks > 30) \
				or (_timeout(600) and _log_timeout(st))
		"wait_remote_moving":
			var v = _o(st.uid).view
			if v.samples.is_empty(): return _timeout(600) and _log_timeout(st)
			var last = v.samples.back()
			# Primero tiene que llegar a la derecha (x > 1,05): al levantarla desde
			# x = 0,5 también pasa por x < 0,85 (error de la corrida 11:44).
			if last.phase == State.Phase.HELD and last.pose.origin.x > 1.05: st["_right"] = true
			return (st.get("_right", false) and last.phase == State.Phase.HELD and last.pose.origin.x < st.x_below) \
				or (_timeout(600) and _log_timeout(st))
		"wait_reject":
			return (main._pending_grab == 0 and main.local_uid == 0) or (_timeout(300) and _log_timeout(st))
		"inject_old_after_release":
			var auth = _o(st.uid).authority.state
			if auth.phase == State.Phase.HELD:
				held_bytes[st.uid] = auth.encode()
				return false
			if held_bytes.has(st.uid) and peer_id != 0:
				if not st.has("_sent"): st["_sent"] = 0
				if step_ticks % 5 == 0 and int(st["_sent"]) < 3:
					var old = State.decode(held_bytes[st.uid])
					main.rpc_id(peer_id, "_snapshot", held_bytes[st.uid])
					st["_sent"] = int(st["_sent"]) + 1
					dl("drv_inject_old", {"uid": st.uid, "old_rev": old.revision, "old_tick": old.tick,
						"old_phase": old.phase, "current_rev": auth.revision, "n": st["_sent"]})
				return int(st["_sent"]) >= 3
			return false
	push_error("driver: paso desconocido " + str(st.op))
	finish("unknown_step", 5)
	return true

func _log_timeout(st: Dictionary) -> bool:
	dl("drv_step_timeout", {"op": st.op})
	finish("step_timeout_" + str(st.op), 4)
	return true

func _record_action(label: String, before: int, direction := Vector3.ZERO) -> void:
	var queued: bool = main.next_action > before
	if queued and not main._local_commands.is_empty():
		commands[label] = main._local_commands.back()
		actions[label] = commands[label].action
	dl("drv_" + label, {"queued_now": queued, "action": actions.get(label, 0), "dependent": main._dependent,
		"pending_grab": main._pending_grab, "local_uid": main.local_uid, "dir": _v(direction)})

func _stable(uid: int) -> bool:
	var o := _o(uid)
	var body: RigidBody3D = o.body
	var local_ok: bool = main.local_uid == uid and main._pending_grab == 0 \
		and _com(body.global_transform).distance_to(goal.origin) < 0.001 \
		and body.linear_velocity.length() < 0.005 and body.angular_velocity.length() < 0.02
	var auth_ok := true
	if role == "client":
		var smp = o.state
		auth_ok = smp != null and smp.phase == State.Phase.HELD and o.pending == 0 \
			and _com(smp.pose).distance_to(goal.origin) < 0.001 and smp.lv.length() < 0.005
	if local_ok and auth_ok: stable_count += 1
	else: stable_count = 0
	if stable_count >= 20:
		dl("drv_stable", {"uid": uid, "com": _v(_com(body.global_transform)), "goal": _v(goal.origin)})
		return true
	# Plazo de preparación, no tolerancia: con red degradada las correcciones del
	# agarre oscilan varios segundos (ver drop100_degraded del 2026-11-16 11:37).
	if _timeout(600):
		dl("drv_stable_timeout", {"uid": uid, "local_ok": local_ok, "auth_ok": auth_ok,
			"com": _v(_com(body.global_transform)), "goal": _v(goal.origin)})
		finish("stable_timeout", 4)
		return true
	return false

# ------------------------------------------------------------------ medición
func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _q(b: Basis) -> Array:
	var q := b.orthonormalized().get_rotation_quaternion()
	return [q.x, q.y, q.z, q.w]

func _enet() -> Dictionary:
	var out := {}
	if main.network == null: return out
	for id in multiplayer.get_peers():
		var p: ENetPacketPeer = main.network.get_peer(id)
		if p == null: continue
		out[str(id)] = {"rtt": p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
			"rtt_var": p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE),
			"loss": p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / 65536.0,
			"throttle": p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)}
	return out

func post_physics() -> void:
	if main == null or log_file == null: return
	_frame_physics += 1
	var objs := []
	for uid: int in main.objects:
		var o: Dictionary = main.objects[uid]
		var b: RigidBody3D = o.body
		var rec := {"uid": uid, "p": _v(b.global_position), "q": _q(b.global_basis),
			"lv": _v(b.linear_velocity), "av": _v(b.angular_velocity), "frz": b.freeze,
			"lay": b.collision_layer, "slp": b.sleeping, "pt": b.prepared_tick, "pred": o.prediction.active,
			"pend": o.pending, "imp": b.impulse_count, "held": b.held,
			"srev": o.state.revision if o.state != null else -1, "sph": o.state.phase if o.state != null else -1,
			"vrev": o.view.latest_revision, "vn": o.view.samples.size()}
		# Entrega 2: estado autorizado que guarda el adaptador (F6) y revisión del predicho.
		if o.state != null:
			rec["stk"] = o.state.tick
			rec["sp"] = _v(o.state.pose.origin)
			rec["slv"] = _v(o.state.lv)
		var ps = o.get("predicted_state")
		if ps != null: rec["psrev"] = ps.revision
		if role == "host":
			var a = o.authority.state
			rec["arev"] = a.revision
			rec["aph"] = a.phase
			rec["aown"] = a.owner
			rec["lg"] = o.last_goal
			rec["ng"] = o.goals.size()
		objs.append(rec)
	var e := {"rate": main.rate_hz, "tps": Engine.physics_ticks_per_second, "ts": Engine.time_scale,
		"rtt": main.rtt_ms, "ready": main.ready_for_input, "luid": main.local_uid, "pg": main._pending_grab,
		"dep": main._dependent, "objs": objs}
	if role == "client" and main.ready_for_input:
		e["est"] = main.estimated_server_tick()
	if _frame_physics % 15 == 0:
		e["enet"] = _enet()
	dl("pp", e)
	if post_stall_ms > 0:
		dl("drv_post_stall_begin", {"ms": post_stall_ms, "wire": main._wire.size()})
		OS.delay_msec(post_stall_ms)
		dl("drv_post_stall_end", {"ms": post_stall_ms})
		post_stall_ms = 0

func post_process() -> void:
	if main == null or log_file == null or role != "client": return
	var objs := []
	for uid: int in main.objects:
		var o: Dictionary = main.objects[uid]
		var b: RigidBody3D = o.body
		var m: Transform3D = b.model.global_transform
		objs.append({"uid": uid, "m": _v(m.origin), "mq": _q(m.basis), "st": o.view.shown_tick,
			"pred": o.prediction.active, "bp": _v(b.global_position), "bq": _q(b.global_basis), "pt": b.prepared_tick,
			"vlast": o.view.samples.back().tick if not o.view.samples.is_empty() else -1})
	var e := {"objs": objs}
	if main.ready_for_input: e["est"] = main.estimated_server_tick()
	dl("dr", e)
