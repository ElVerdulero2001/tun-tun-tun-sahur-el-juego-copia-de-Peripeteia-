extends SceneTree

## Validación independiente (Claude), entrega 3: uso de la bandeja de mano en el
## adaptador (main.gd) sin red. Instancia main.tscn en modo solo y le inyecta en
## _inbound entradas y órdenes con la misma forma que dejan los RPC. No modifica
## main.gd ni runtime/.
##   Hook previo (prioridad física −10): inyecciones, antes de que main numere el paso.
##   Hook posterior (prioridad física +10): lee body.goal, last_goal y la autoridad.
##   Hook de proceso (prioridad −10): lee las respuestas en main._wire antes de que
##   main._process las descarte (en modo solo no hay peers).
## Uso: Godot --headless --path prototypes/objetos_red --script res://validation/hand_adapter_test.gd -- --out=<json> --trace=<jsonl>
## Criterios: docs/net/validacion_objetos/criterios_entrega_3.md §4.3 (A00–A14).

const MainScene := preload("res://main.tscn")
const State := preload("res://runtime/state.gd")
const Authority := preload("res://runtime/authority.gd")
const END_TICK := 140

class Hook extends Node:
	var on_physics: Callable
	var on_process: Callable
	func _physics_process(_d: float) -> void:
		if on_physics.is_valid(): on_physics.call()
	func _process(_d: float) -> void:
		if on_process.is_valid(): on_process.call()

var main: Node
var results: Array = []
var out_path := ""
var trace_path := ""
var started := false
var done := false
var finalized := false
var t_start := 0
var injected := {}
var batches: Array = []
var sent_grabs := {}
var wire_results: Array = []
var steps := {}
var post_notes := {}
var initial_goal1 := Transform3D.IDENTITY
var host_session := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_path = a.trim_prefix("--out=")
		elif a.begins_with("--trace="): trace_path = a.trim_prefix("--trace=")

func _process(_delta: float) -> bool:
	if not started:
		started = true
		_start()
	elif done and not finalized:
		finalized = true
		_finish()
	return false

func check(id: String, ok, detail := "") -> void:
	results.append({"id": id, "ok": ok, "detail": detail})

# ------------------------------------------------------------------ objetivos
func X(t: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(-0.5 + 0.001 * (t - 40), 0.7, 0.0))

func mark(d: Vector3) -> Callable:
	return func(t: int) -> Transform3D: return Transform3D(Basis.IDENTITY, X(t).origin + d)

func fixed(p: Vector3) -> Callable:
	return func(_t: int) -> Transform3D: return Transform3D(Basis.IDENTITY, p)

func cmd(op: String, uid: int, session: int, action: int, t: int, target := Vector3(-0.5, 0.65, 0.0)) -> Dictionary:
	return {"op": op, "uid": uid, "epoch": 1, "session": session, "action": action, "tick": t,
		"target": Transform3D(Basis.IDENTITY, target), "anchor": Vector3(0, 0.2, 0), "direction": Vector3.ZERO}

func inject(label: String, peer: int, uid: int, epoch: int, session: int, ticks: Array, target_of: Callable) -> void:
	var frames: Array = []
	for t: int in ticks:
		var target: Transform3D = target_of.call(t)
		frames.append({"uid": uid, "epoch": epoch, "session": session, "tick": t, "target": target})
		injected["%d:%d:%d:%d:%d" % [peer, uid, epoch, session, t]] = target
	main._inbound.append({"kind": "hand_inputs", "peer": peer, "frames": frames})
	batches.append({"label": label, "k": main.tick, "peer": peer, "uid": uid, "epoch": epoch, "session": session, "n": ticks.size()})

func command(peer: int, c: Dictionary) -> void:
	if c.op == "grab": sent_grabs["%d:%d" % [peer, c.session]] = c
	main._inbound.append({"kind": "command", "peer": peer, "command": c})

# ------------------------------------------------------------------ escenario
func _start() -> void:
	t_start = Time.get_ticks_msec()
	main = MainScene.instantiate()
	root.add_child(main)
	var pre := Hook.new()
	pre.process_physics_priority = -10
	pre.process_priority = -10
	pre.on_physics = _pre
	pre.on_process = _read_wire
	root.add_child(pre)
	var post := Hook.new()
	post.process_physics_priority = 10
	post.on_physics = _post
	root.add_child(post)
	initial_goal1 = main.objects[1].body.goal

func _pre() -> void:
	if done or finalized: return
	if Time.get_ticks_msec() - t_start > 15000:
		check("A99_tiempo", false, "el escenario no terminó en 15 s (tick %d)" % main.tick)
		done = true
		return
	var k: int = main.tick
	match k:
		20:
			inject("p2_s50_antes_del_inicio", 2, 1, 1, 50, [39, 40], mark(Vector3(0, 0.5, 0)))
			inject("p2_s50", 2, 1, 1, 50, range(41, 61), X)
			inject("p3_s50_peer_ajeno", 3, 1, 1, 50, range(41, 61), mark(Vector3(0, 0.3, 0)))
			inject("p2_s51_sesion_ajena", 2, 1, 1, 51, range(41, 61), mark(Vector3(0, 0, 0.3)))
			inject("p2_e2_aparicion_ajena", 2, 1, 2, 50, range(41, 61), mark(Vector3(0, 0, -0.3)))
		40:
			command(2, cmd("grab", 1, 50, 50, 40))
		45:
			main.request_grab(2, Vector3(0, 0.2, 0), Transform3D(Basis.IDENTITY, Vector3(0.5, 0.65, 0.0)))
		47:
			host_session = main.local_session
			inject("p2_caja_del_host", 2, 2, 1, host_session, range(48, 101), fixed(Vector3(0.5, 1.5, 0.0)))
			inject("p3_caja_del_host", 3, 2, 1, host_session, range(48, 101), fixed(Vector3(0.5, 1.6, 0.0)))
		62:
			inject("p2_s50_tardias", 2, 1, 1, 50, [61, 62], X)
		63:
			inject("p2_s50_resto", 2, 1, 1, 50, range(64, 111), X)
		70:
			inject("p3_s77_antes_del_rechazo", 3, 1, 1, 77, range(71, 91), mark(Vector3(0.2, 0, 0)))
		72:
			command(3, cmd("grab", 1, 77, 77, 72))
		75:
			inject("p3_s77_despues_del_rechazo", 3, 1, 1, 77, range(76, 81), mark(Vector3(0.2, 0, 0)))
		80:
			for i in 300: command(2, cmd("release", 1, 999, 1000 + i, 80))
		82:
			command(2, cmd("grab", 1, 50, 50, 40)) # repetición vieja del agarre activo
		86:
			inject("p2_s50_reenvio", 2, 1, 1, 50, range(105, 111), X)
		110:
			command(2, cmd("release", 1, 50, 1300, 110))
		112:
			inject("p2_s50_despues_de_soltar", 2, 1, 1, 50, range(113, 119), X)
		114:
			inject("p3_s200", 3, 1, 1, 200, range(116, 141), mark(Vector3(0.1, 0.1, 0)))
		116:
			command(3, cmd("grab", 1, 200, 200, 116))
		125:
			main._inbound.append({"kind": "disconnect", "peer": 3})
		128:
			inject("p3_s200_despues_de_desconectar", 3, 1, 1, 200, range(129, 136), mark(Vector3(0.1, 0.1, 0)))
		END_TICK:
			done = true

func _post() -> void:
	if finalized: return
	var s: int = main.tick
	var rec := {"target": main.target}
	for uid: int in main.objects:
		var o: Dictionary = main.objects[uid]
		var a = o.authority.state
		rec[uid] = {"held": o.body.held, "goal": o.body.goal, "lg": o.last_goal, "phase": a.phase,
			"owner": a.owner, "session": a.session, "epoch": a.epoch}
	steps[s] = rec
	if s == 73: post_notes["pending_77"] = main._hand_timeline.pending_for(3, 1, 1, 77).size()
	if s == 126 or s == 130:
		post_notes["slots_peer3_%d" % s] = main._hand_timeline._slots.keys().filter(func(x): return String(x).begins_with("3:"))

func _read_wire() -> void:
	if finalized or main == null: return
	for m: Dictionary in main._wire:
		if m.method == "_result": wire_results.append({"peer": m.peer, "result": m.args[0].duplicate(true)})

# ------------------------------------------------------------------ verificación
func _finish() -> void:
	root.remove_child(main)
	main.free() # _exit_tree cierra la traza
	var tr: Array = []
	for line in FileAccess.get_file_as_string(trace_path).split("\n", false):
		var v = JSON.parse_string(line)
		if typeof(v) == TYPE_DICTIONARY: tr.append(v)
	_checks(tr)
	var fails := 0
	for r in results:
		if r.ok == false: fails += 1
	var text := JSON.stringify({"schema": 1, "results": results, "fails": fails, "wire_results": wire_results.size(),
		"notes": post_notes}, "  ", false, true)
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	for r in results:
		print("%s %s %s" % ["PASS" if r.ok == true else ("FAIL" if r.ok == false else "INFO"), r.id, r.detail])
	print("HAND_ADAPTER_DONE pass=%d fail=%d" % [results.filter(func(r): return r.ok == true).size(), fails])
	quit(0)

func kind(tr: Array, k: String) -> Array:
	return tr.filter(func(r): return r.kind == k)

func batch_statuses(tr: Array, label: String) -> Array:
	var b: Dictionary = {}
	for x in batches:
		if x.label == label: b = x
	if b.is_empty(): return []
	var out: Array = []
	for r in kind(tr, "hand_input"):
		if int(r.peer) == b.peer and int(r.uid) == b.uid and int(r.epoch) == b.epoch \
			and int(r.session) == b.session and int(r.local_tick) == b.k:
			out.append(r.status)
	return out

func all_are(arr: Array, value: String) -> bool:
	return not arr.is_empty() and arr.all(func(x): return x == value)

func controller(tr: Array, uid: int, s: int) -> Dictionary:
	for r in kind(tr, "controller"):
		if int(r.uid) == uid and int(r.step_tick) == s: return r
	return {}

func applied(tr: Array, uid: int, action: int) -> Dictionary:
	for r in kind(tr, "applied"):
		if int(r.uid) == uid and int(r.action) == action: return r
	return {}

func goal_of(s: int, uid: int):
	return steps[s][uid].goal if steps.has(s) else null

func _checks(tr: Array) -> void:
	var ctrl1: Array = kind(tr, "controller").filter(func(r): return int(r.uid) == 1)

	# A00
	var st20: Array = kind(tr, "hand_input").filter(func(r): return int(r.local_tick) == 20).map(func(r): return r.status)
	check("A00_bandeja_previa", st20.size() == 82 and all_are(st20, "buffered"), "%d entradas en el tick 20; estados %s" % [st20.size(), _hist(st20)])

	# A01
	var bad01 := 0
	for s in range(1, 41):
		if not steps.has(s) or steps[s][1].held or steps[s][1].goal != initial_goal1: bad01 += 1
	var ctrl_before := ctrl1.filter(func(r): return int(r.step_tick) < 41).size()
	check("A01_libre_sin_efecto", bad01 == 0 and ctrl_before == 0, "pasos 1–40 con cambios %d; controller antes de 41: %d" % [bad01, ctrl_before])

	# A02
	var ap50 := applied(tr, 1, 50)
	var ok02: bool = not ap50.is_empty() and int(ap50.applied_tick) == 41 and ap50.late == false \
		and goal_of(41, 1) == X(41) and steps[41][1].lg == 41
	check("A02_primer_paso_concedido", ok02, "aplicado en %s (late %s); paso 41: último usado %s, objetivo = X(41): %s" % [
		ap50.get("applied_tick"), ap50.get("late"), steps.get(41, {}).get(1, {}).get("lg"), goal_of(41, 1) == X(41)])

	# A03
	var bad03 := []
	for s in range(41, 61) + range(64, 111):
		if goal_of(s, 1) != X(s): bad03.append(s)
	check("A03_solo_la_clave_concedida", bad03.is_empty(), "pasos con otro objetivo: %s (de %d)" % [bad03.slice(0, 10), 20 + 47])

	# A04
	var c61 := controller(tr, 1, 61)
	var c62 := controller(tr, 1, 62)
	var ok04: bool = goal_of(61, 1) == X(60) and goal_of(62, 1) == X(60) and steps[61][1].lg == 60 and steps[62][1].lg == 60 \
		and c61.get("fallback") == true and c62.get("fallback") == true and int(c61.get("input_tick", -9)) == 60 and int(c62.get("input_tick", -9)) == 60
	check("A04_respaldo", ok04, "61: usado %s fallback %s; 62: usado %s fallback %s" % [c61.get("input_tick"), c61.get("fallback"), c62.get("input_tick"), c62.get("fallback")])

	# A05
	var c63 := controller(tr, 1, 63)
	var ok05: bool = goal_of(63, 1) == X(62) and steps[63][1].lg == 62 and c63.get("fallback") == true
	check("A05_entrada_tardia", ok05, "paso 63: usa %s (llegaron tarde 61 y 62), fallback %s" % [c63.get("input_tick"), c63.get("fallback")])

	# A06
	var host_req: Array = kind(tr, "request").filter(func(r): return int(r.uid) == 2 and r.op == "grab")
	var ap_host: Dictionary = applied(tr, 2, int(host_req[0].action)) if not host_req.is_empty() else {}
	var ok06: bool = not ap_host.is_empty() and int(ap_host.requested_tick) == 45 and int(ap_host.applied_tick) == 46 and ap_host.late == false
	check("A06_accion_local_del_host", ok06, "pedido %s, aplicado %s, late %s" % [ap_host.get("requested_tick"), ap_host.get("applied_tick"), ap_host.get("late")])

	# A07
	var bad07 := []
	for s in range(48, END_TICK + 1):
		if not steps.has(s) or not steps[s][2].held or steps[s][2].goal != steps[s].target: bad07.append(s)
	check("A07_mano_ajena_sobre_caja_del_host", bad07.is_empty(), "pasos 48–%d con objetivo ajeno o sin agarre: %s" % [END_TICK, bad07.slice(0, 10)])

	# A08
	var st70 := batch_statuses(tr, "p3_s77_antes_del_rechazo")
	var st75 := batch_statuses(tr, "p3_s77_despues_del_rechazo")
	var rej77: Array = wire_results.filter(func(w): return w.peer == 3 and w.result.get("action") == 77)
	var ok08: bool = post_notes.get("pending_77", -1) == 0 and all_are(st70, "buffered") and all_are(st75, "retired") \
		and rej77.size() == 1 and rej77[0].result.status == "rejected" and rej77[0].result.get("uid") == 1
	check("A08_rechazo_retira", ok08, "antes %s; bandeja tras el rechazo %s; después %s; respuesta %s" % [_hist(st70), post_notes.get("pending_77"), _hist(st75), rej77.map(func(w): return w.result)])

	# A09
	var stale50: Array = wire_results.filter(func(w): return w.peer == 2 and w.result.get("action") == 50 and w.result.get("status") == "stale")
	var st86 := batch_statuses(tr, "p2_s50_reenvio")
	var ok09: bool = stale50.size() == 1 and all_are(st86, "duplicate")
	check("A09_repeticion_vieja_no_retira", ok09, "stale de la acción 50: %d; reenvío posterior %s" % [stale50.size(), _hist(st86)])

	# A10
	var invalid := wire_results.filter(func(w): return not Authority.valid_response(w.result))
	var ok10: bool = invalid.is_empty() and stale50.size() == 1 and stale50[0].result.get("uid") == 1
	check("A10_respuestas_bien_formadas", ok10, "%d respuestas; inválidas %d; stale 50 con objeto %s" % [wire_results.size(), invalid.size(),
		stale50[0].result.get("uid") if stale50.size() == 1 else "?"])

	# A11
	var ap1300 := applied(tr, 1, 1300)
	var st112 := batch_statuses(tr, "p2_s50_despues_de_soltar")
	var held11 := 0
	for s in range(111, 117):
		if steps.has(s) and steps[s][1].held: held11 += 1
	var ctrl11 := ctrl1.filter(func(r): return int(r.step_tick) >= 111 and int(r.step_tick) <= 116).size()
	check("A11_suelta_retira", not ap1300.is_empty() and int(ap1300.applied_tick) == 111 and all_are(st112, "retired") and held11 == 0 and ctrl11 == 0,
		"suelta aplicada en %s; entradas posteriores %s; pasos sostenidos 111–116: %d; controller %d" % [ap1300.get("applied_tick"), _hist(st112), held11, ctrl11])

	# A12
	var ap200 := applied(tr, 1, 200)
	var bad12 := []
	for s in range(117, 126):
		if goal_of(s, 1) != mark(Vector3(0.1, 0.1, 0)).call(s): bad12.append(s)
	check("A12_otro_dueno", not ap200.is_empty() and int(ap200.applied_tick) == 117 and bad12.is_empty(),
		"agarre aplicado en %s; pasos con otro objetivo %s" % [ap200.get("applied_tick"), bad12])

	# A13
	var ar: Array = kind(tr, "auto_release").filter(func(r): return int(r.uid) == 1)
	var bad13 := []
	for s in range(126, END_TICK + 1):
		if steps.has(s) and (steps[s][1].held or steps[s][1].phase != State.Phase.FREE or steps[s][1].owner != 0): bad13.append(s)
	var ctrl13 := ctrl1.filter(func(r): return int(r.step_tick) >= 126).size()
	var slots126: Array = post_notes.get("slots_peer3_126", ["?"])
	var st128 := batch_statuses(tr, "p3_s200_despues_de_desconectar")
	check("A13_desconexion", ar.size() == 1 and bad13.is_empty() and ctrl13 == 0 and slots126.is_empty(),
		"auto_release %d (tick %s); pasos no libres %s; controller %d; claves del peer 3 en 126: %s; entradas posteriores %s" % [
			ar.size(), ar[0].local_tick if ar.size() else "?", bad13.slice(0, 5), ctrl13, slots126, _hist(st128)])

	# A14
	var bad14 := []
	for s: int in steps:
		for uid in [1, 2]:
			var r: Dictionary = steps[s][uid]
			if not r.held: continue
			if r.owner == 1:
				if r.goal != steps[s].target: bad14.append("%d/%d host" % [s, uid])
				continue
			var grant: Dictionary = sent_grabs.get("%d:%d" % [r.owner, r.session], {})
			if grant.is_empty():
				bad14.append("%d/%d sin orden" % [s, uid])
			elif r.lg == -1:
				if r.goal != grant.target: bad14.append("%d/%d respaldo" % [s, uid])
			else:
				var key := "%d:%d:%d:%d:%d" % [r.owner, uid, r.epoch, r.session, r.lg]
				if not injected.has(key) or injected[key] != r.goal or r.lg <= int(grant.tick) or r.lg > s:
					bad14.append("%d/%d usado %d" % [s, uid, r.lg])
	check("A14_ningun_objetivo_inventado", bad14.is_empty(), "%d pasos registrados; inconsistentes %s" % [steps.size(), bad14.slice(0, 10)])

func _hist(arr: Array) -> Dictionary:
	var h := {}
	for x in arr: h[x] = h.get(x, 0) + 1
	return h
