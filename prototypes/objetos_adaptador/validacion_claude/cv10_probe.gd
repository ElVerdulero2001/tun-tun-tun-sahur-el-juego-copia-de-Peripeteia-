extends Node3D
## Validación independiente (Claude), entrega 10: adaptador local actor/reloj -> núcleo nativo.
## Criterios: docs/net/validacion_objetos/criterios_entrega_10.md §4. No modifica el adaptador:
## lo usa como Codex lo entregó, con el actor, el motor, el input y el reloj reales.
## Mis referencias (R_pura, R_aut) se arman con mis propias copias de bytes, ojos y dt.
## Salida: 0 sin FAIL, 2 con algún FAIL, 3 si una condición previa no se logró.

const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const ACTOR = preload("res://scenes/actor/actor.tscn")
const UID := 2
const ANCHOR := Vector3(0.05, 0.02, 0.0)
const RELEASE_IMPULSE := Vector3(1.2, 1.6, -0.8)
const AUTH_EVENT := Vector3(1.0, 0.0, 0.6)
const SENS := 0.001

var mode := "replay"
var result_path := ""
var trace_path := ""
var clock: SimClock
var actor: ActorBody
var tuning: ActorTuning
var adapter
var extra := {}          # nombre -> adaptador (modos tuning y capture)
var extra_rec := {}      # nombre -> [tick, motivo] de su pedido de recuperación
var r_pure
var r_auth
var r_nograb
var cp_pure := {}
var cp_auth := {}
var cp_nograb := {}
var my_frames := {}
var my_actions := {}
var inputs_obj := {}
var eyes_pre := {}
var checks: Array = []
var facts := {}
var trace: Array = []
var effects: Array = []
var effect_ticks: Array = []
var recoveries: Array = []
var provider_calls := 0
var in_reconcile := false
var provider_in_reconcile := 0
var poisoned_calls := 0
var refused_captures := 0
var moved_ticks := 0
var frames_compared := 0
var mism := {"bytes": [], "eyes": [], "dt": [], "action": []}
var live_mismatch: Array = []
var window_mismatch: Array = []
var done := false
var noeval := false
var started := 0
var pause_frames := -1
var pc_at_pause := 0
var start_pos := Vector3.ZERO
var end_tick := 60
var eye_h_min := INF
var eye_h_max := -INF

# --- utilidades -----------------------------------------------------------------------------
func check(id: String, ok: bool, metric = null, tol := "") -> bool:
	checks.append({"id": id, "verdict": "PASS" if ok else "FAIL", "metric": metric, "tol": tol})
	if not ok: print("CV10_FAIL ", id, " ", metric)
	return ok

func info(id: String, metric) -> void:
	checks.append({"id": id, "verdict": "INFO", "metric": metric, "tol": "se registra"})

func sha(bytes: PackedByteArray) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(bytes)
	return hc.finish().hex_encode()

func h(w) -> String:
	return sha(var_to_bytes(w.samples()))

func nums(s: Dictionary) -> Array:
	var t: Transform3D = s.pose
	var out := [t.origin.x, t.origin.y, t.origin.z]
	for i in 3: out.append_array([t.basis[i].x, t.basis[i].y, t.basis[i].z])
	out.append_array([s.lv.x, s.lv.y, s.lv.z, s.av.x, s.av.y, s.av.z])
	return out

func wdiff(a, b) -> float:
	var sa: Array = a.samples()
	var sb: Array = b.samples()
	var m := 0.0
	for i in mini(sa.size(), sb.size()):
		var x := nums(sa[i])
		var y := nums(sb[i])
		for k in x.size(): m = maxf(m, absf(x[k] - y[k]))
	return m

func make_world(bigger := false):
	var w = ClassDB.instantiate("SahurObjectWorld")
	w.add_box(1, 1, Vector3(12, 0.2, 12), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)))
	w.add_box(2, 1, Vector3(0.45, 0.35, 0.55), 1.6, Transform3D(Basis.IDENTITY, Vector3(0.1, 0.6, -0.2)))
	w.add_box(3, 1, Vector3(0.4, 0.4, 0.4), 1.0, Transform3D(Basis.IDENTITY, Vector3(0.6, 0.2, -0.6)))
	w.add_box(4, 1, Vector3(0.31 if bigger else 0.3, 0.6, 0.3), 0.8, Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.3, -0.4)))
	w.seal_topology(1)
	return w

## Mi paso de referencia, según el README: transición de mano y un solo paso con el dt guardado.
func my_apply(w, t: int, skip_kind := "", extra_at := -1, dt_override := -1.0) -> void:
	var f: Dictionary = my_frames[t]
	var s := StreamPeerBuffer.new()
	s.data_array = f.bytes
	var input := ActorInput.read_from(s)
	var goal := InvHoldMotion.target_of(f.eyes, input, tuning)
	var state: Dictionary = w.sample(UID, 1)
	var act: Dictionary = f.action
	var kind: String = act.get("kind", "")
	if kind == skip_kind: kind = ""
	if kind == "grab": w.begin_hold(UID, 1, act.anchor, goal)
	if (state.held or kind == "grab") and not input.hold.is_empty(): w.set_goal(UID, 1, goal)
	if kind == "release": w.release_body(UID, 1, act.impulse)
	if t == extra_at: w.apply_impulse(UID, 1, RELEASE_IMPULSE)
	w.step(f.dt if dt_override <= 0.0 else dt_override)

func branch_from(bytes: PackedByteArray, from_t: int, to_t: int, skip_kind := "", extra_at := -1, dt_of := {}):
	var w = make_world()
	w.restore_trusted(bytes)
	for k in range(from_t + 1, to_t + 1):
		my_apply(w, k, skip_kind, extra_at, dt_of.get(k, -1.0))
	return w

func q(t: int, id: int, kind: String, anchor := Vector3.ZERO, impulse := Vector3.ZERO) -> bool:
	var ok: bool = adapter.queue_action(t, id, kind, anchor, impulse)
	if ok and not my_actions.has(t):
		my_actions[t] = {"id": id, "kind": kind, "tick": t, "anchor": anchor, "impulse": impulse}
	return ok

func same_action(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty(): return a.is_empty() and b.is_empty()
	for k in ["id", "kind", "tick", "anchor", "impulse"]:
		if a.get(k) != b.get(k): return false
	return true

# --- escena ----------------------------------------------------------------------------------
func _ready() -> void:
	started = Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
		elif arg.begins_with("--trace="): trace_path = arg.trim_prefix("--trace=")
	facts["engine"] = Engine.get_version_info().string
	facts["cmdline"] = OS.get_cmdline_args()
	if not ClassDB.class_exists("SahurObjectWorld"):
		noeval = true; info("A0_extension", "no registrada"); finish(); return
	loaded_scripts()
	end_tick = {"replay": 60, "slow": 50, "pause": 40, "errors": 40, "limits": 266, "resync": 30, "tuning": 20, "capture": 30}.get(mode, 60)
	tuning = ActorTuning.new(); add_child(tuning)
	var actors := Node3D.new(); add_child(actors)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(12, 0.2, 12)
	shape.shape = box; floor_body.add_child(shape); add_child(floor_body)
	floor_body.position.y = -0.1
	actor = ACTOR.instantiate(); actor.owner_peer_id = 1
	actor.state.position = Vector3(0, 0.02, 1.5)
	actors.add_child(actor)
	start_pos = actor.state.position
	clock = SimClock.new(); clock.actors_root = actors; clock.tuning = tuning
	clock.input_provider = provide_input
	add_child(clock)
	if mode == "slow": SimClock.add_world_slow(10, 34, 0.42)
	clock.tick_started.connect(func(t: int): eyes_pre[t] = InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state)))
	if mode == "tuning": tuning_start_checks()
	adapter = Adapter.new(); add_child(adapter)
	adapter.action_effect.connect(_on_effect)
	adapter.recovery_required.connect(func(r: String): recoveries.append([clock.tick, r]))
	if not adapter.start(clock, actor, tuning, make_world, UID, 1, 1):
		noeval = true; info("A0_start", adapter.last_error); finish(); return
	if mode == "capture": capture_setup()
	r_pure = make_world(); r_auth = make_world(); r_nograb = make_world()
	clock.tick_finished.connect(after_tick)

func _on_effect(id: int, kind: String) -> void:
	effects.append([id, kind])
	effect_ticks.append(clock.tick)

func loaded_scripts() -> void:
	var want := ["ActorInput", "ActorBody", "ActorMotor", "ActorTuning", "SimClock", "InvAuthority", "InvHoldMotion", "BaseRegistry"]
	var found := {}
	for c in ProjectSettings.get_global_class_list():
		if c["class"] in want: found[c["class"]] = c["path"]
	var out := {}
	for n in want:
		var p: String = found.get(n, "")
		out[n] = {"path": p, "sha256": sha(FileAccess.get_file_as_bytes(p)) if p != "" else ""}
	for p in ["res://scenes/actor/actor.tscn", "res://prototypes/objetos_adaptador/clock_adapter.gd"]:
		out[p.get_file()] = {"path": p, "sha256": sha(FileAccess.get_file_as_bytes(p))}
	facts["loaded_scripts"] = out
	facts["actor_scene_path"] = ACTOR.resource_path

func provide_input(_who: ActorBody, t: int) -> ActorInput:
	provider_calls += 1
	if in_reconcile: provider_in_reconcile += 1
	var buttons := 0
	if t >= 12 and t <= 17: buttons |= ActorInput.BUTTON_CROUCH
	if t >= 40 and t <= 46: buttons |= ActorInput.BUTTON_RUN
	var input := ActorInput.make(t, Vector2(0.4 * sin(t * 0.17), 0.3 + 0.2 * cos(t * 0.11)), 0.02 * t + 0.15 * sin(t * 0.23), buttons, 1 if t >= 25 else 0)
	if not (mode == "replay" and t >= 22 and t <= 26):
		input.hold = ActorInput.pack_hold(1, -0.3 + 0.25 * sin(t * 0.09), 1.1 + 0.5 * sin(t * 0.05), Quaternion(Vector3(0.2, 1, 0.1).normalized(), t * 0.04))
	if adapter.ready_for_input: queue_for(t)
	var b := StreamPeerBuffer.new()
	input.write_to(b)
	my_frames[t] = {"bytes": b.data_array.duplicate()}
	inputs_obj[t] = input
	if adapter.ready_for_input:
		if not adapter.capture(input): info("captura_rechazada_%d" % t, adapter.last_error)
	elif not adapter.capture(input):
		refused_captures += 1
	if mode == "capture": capture_extra(t, input)
	return input

func queue_for(t: int) -> void:
	match mode:
		"errors": errors_queue(t)
		"limits": limits_queue(t)
		_:
			if t == 6:
				check("A8_agarre_en_cola", q(t, 11, "grab", ANCHOR), adapter.last_error, "true")
				check("A8_duplicado_mismo_tick_aceptado", q(t, 11, "grab", ANCHOR), adapter.last_error, "true sin otra ejecución")
			if t == 20 and mode in ["replay", "slow", "pause"]:
				check("A8_suelta_en_cola", q(t, 12, "release", Vector3.ZERO, RELEASE_IMPULSE), adapter.last_error, "true")

func after_tick(t: int) -> void:
	if done: return
	var eyes := InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state))
	var f: Dictionary = my_frames[t]
	f["eyes"] = eyes
	f["dt"] = SimClock.world_dt(t)
	f["action"] = my_actions.get(t, {})
	var eh: float = eyes.y - BaseRegistry.world_position(actor.state).y
	eye_h_min = minf(eye_h_min, eh)
	eye_h_max = maxf(eye_h_max, eh)
	var rec: Dictionary = adapter.recorded_frame(t)
	if not rec.is_empty():
		frames_compared += 1
		if rec.input != f.bytes: mism.bytes.append(t)
		if rec.eyes != eyes: mism.eyes.append(t)
		if rec.dt != f.dt: mism.dt.append(t)
		if not same_action(rec.action, f.action): mism.action.append(t)
	if eyes_pre.get(t) != eyes: moved_ticks += 1
	if t == 5: r_auth.apply_impulse(3, 1, AUTH_EVENT)
	my_apply(r_pure, t)
	my_apply(r_auth, t)
	if mode == "errors": my_apply(r_nograb, t, "grab")
	cp_pure[t] = r_pure.snapshot_trusted()
	cp_auth[t] = r_auth.snapshot_trusted()
	if mode == "errors": cp_nograb[t] = r_nograb.snapshot_trusted()
	var ha := h(adapter.world)
	var hp := h(r_pure)
	var hq := h(r_auth)
	trace.append({"tick": t, "dt": f.dt, "eyes": var_to_str(eyes), "eyes_pre": var_to_str(eyes_pre.get(t)), "actor": var_to_str(actor.state.position),
		"native_tick": adapter.world.get_tick(), "native": ha, "pure": hp, "auth": hq, "ready": adapter.ready_for_input})
	match mode:
		"replay": replay_tick(t, ha, hp, hq)
		"slow": slow_tick(t, ha, hp, hq)
		"pause": pause_tick(t, ha, hp, hq)
		"errors": errors_tick(t, ha, hp)
		"limits": limits_tick(t, ha, hp)
		"resync": resync_tick(t, ha, hp)
		"tuning": tuning_tick(t, ha, hp)
		"capture": capture_tick(t, ha, hp)
	if t >= end_tick and not done: common_end(); finish()

func common_end() -> void:
	var disp := (actor.state.position - start_pos).length()
	var ratio := float(moved_ticks) / maxf(1.0, float(my_frames.size()))
	var a1 := {"ticks_distintos_a_antes_del_motor": moved_ticks, "ticks": my_frames.size(), "desplazamiento_m": disp, "ojos_distintos_al_diario": mism.eyes.slice(0, 5)}
	if end_tick >= 40: check("A1_ojos_despues_del_motor", mism.eyes.is_empty() and ratio >= 0.8 and disp > 0.5, a1, "≥ 80 % y > 0,5 m")
	else: info("A1_ojos_despues_del_motor_modo_corto", a1)
	info("A1_altura_de_ojos_min_max_m", [eye_h_min, eye_h_max])
	check("A2_diario_igual_al_mio", frames_compared > 0 and mism.bytes.is_empty() and mism.dt.is_empty() and mism.action.is_empty(),
		{"frames_comparados": frames_compared, "bytes": mism.bytes.slice(0, 5), "dt": mism.dt.slice(0, 5), "accion": mism.action.slice(0, 5)}, "iguales en cada tick")

# --- modos ----------------------------------------------------------------------------------
func reconcile_logged(cp_tick: int, bytes: PackedByteArray) -> Dictionary:
	var s0: int = adapter.replayed_steps
	var e0 := effects.size()
	var p0 := provider_calls
	in_reconcile = true
	var ok: bool = adapter.reconcile_trusted(cp_tick, bytes)
	in_reconcile = false
	return {"ok": ok, "error": adapter.last_error, "steps": adapter.replayed_steps - s0, "effects": effects.size() - e0, "provider": provider_calls - p0}

func replay_tick(t: int, ha: String, hp: String, hq: String) -> void:
	if t < 29 and ha != hp: live_mismatch.append(t)
	if t == 30 or (t >= 34 and t <= 39) or t >= 46:
		if ha != hq: window_mismatch.append(t)
	match t:
		28: check("A3_paso_en_vivo_igual_a_R_pura", live_mismatch.is_empty(), {"distintos": live_mismatch}, "ticks 1..28 iguales")
		29:
			var before := wdiff(adapter.world, r_auth)
			var r := reconcile_logged(5, cp_auth[5])
			check("A4_antes_del_agarre_24_pasos", r.ok and h(adapter.world) == h(r_auth) and before > SENS and r.steps == 24 and r.effects == 0,
				{"antes": before, "resultado": r, "despues": wdiff(adapter.world, r_auth)}, "igual a R_aut@29, antes > 1e-3, 24 pasos, sin efectos")
		31: adapter.world.apply_impulse(4, 1, Vector3(0, 2.5, 0))
		33:
			var before := wdiff(adapter.world, r_auth)
			var saved_provider: Callable = clock.input_provider
			clock.input_provider = func(_a, _tt):
				poisoned_calls += 1
				return null
			var pos0: Vector3 = actor.state.position
			actor.state.position += Vector3(50, 0, 0)
			for k in range(20, 34):
				var o: ActorInput = inputs_obj[k]
				o.look_yaw = 2.0; o.move = Vector2(1, 0)
				if not o.hold.is_empty(): o.hold[2] = 60000
			SimClock.add_world_slow(18, 34, 0.25)
			var r := reconcile_logged(19, cp_auth[19])
			SimClock.clear_world_slow()
			actor.state.position = pos0
			clock.input_provider = saved_provider
			var equal := h(adapter.world) == h(r_auth)
			var no_rel = branch_from(cp_auth[19], 19, 33, "release")
			var double = branch_from(cp_auth[19], 19, 33, "", 21)
			var d_nr := wdiff(adapter.world, no_rel)
			var d_db := wdiff(adapter.world, double)
			check("A5_antes_de_la_suelta", r.ok and equal and before > SENS and r.steps == 14 and d_nr > SENS and d_db > SENS,
				{"antes": before, "resultado": r, "sin_suelta": d_nr, "doble_impulso": d_db}, "igual a R_aut@33; controles > 1e-3")
			check("A6_no_consulta_el_presente", equal and r.provider == 0 and provider_in_reconcile == 0 and poisoned_calls == 0,
				{"llamadas_al_proveedor": r.provider, "proveedor_envenenado": poisoned_calls, "igual_con_actor_movido_inputs_corruptos_y_tramo_lento": equal}, "0 llamadas e igualdad")
		40: adapter.world.apply_impulse(2, 1, Vector3(2, 0, 0))
		45:
			var before := wdiff(adapter.world, r_auth)
			var r := reconcile_logged(21, cp_auth[21])
			check("A7_despues_de_la_suelta_24_pasos", r.ok and h(adapter.world) == h(r_auth) and before > SENS and r.steps == 24,
				{"antes": before, "resultado": r}, "igual, 24 pasos")
		60:
			check("A8_efectos_y_final", ha == hq and window_mismatch.is_empty() and effects == [[11, "grab"], [12, "release"]] and effect_ticks == [6, 20] and recoveries.is_empty(),
				{"efectos": effects, "ticks_de_efecto": effect_ticks, "ventanas_distintas": window_mismatch, "recuperaciones": recoveries}, "igual a R_aut y dos efectos")

func slow_tick(t: int, ha: String, hp: String, hq: String) -> void:
	if t < 32 and ha != hp: live_mismatch.append(t)
	if t >= 33 and ha != hq: window_mismatch.append(t)
	match t:
		32:
			var slow := 0
			for k in my_frames:
				if my_frames[k].dt < SimClock.TICK_DT:
					slow += 1
			check("S1_dt_guardado_y_paso_en_vivo", slow == 24 and mism.dt.is_empty() and live_mismatch.is_empty(),
				{"frames_lentos": slow, "dt_distintos": mism.dt, "distintos_a_R_pura": live_mismatch}, "24 lentos, iguales")
			var before := wdiff(adapter.world, r_auth)
			var r := reconcile_logged(8, cp_auth[8])
			check("S2_correccion_que_cruza_el_tramo", r.ok and h(adapter.world) == hq and before > SENS and r.steps == 24, {"antes": before, "resultado": r}, "igual a R_aut")
		40:
			SimClock.add_world_slow(36, 39, 0.2)
			var dts := {}
			for k in range(36, 41): dts[k] = SimClock.world_dt(k)
			var r := reconcile_logged(35, cp_auth[35])
			var retro = branch_from(cp_auth[35], 35, 40, "", -1, dts)
			SimClock.clear_world_slow()
			SimClock.add_world_slow(10, 34, 0.42)
			info("S3_tramo_hacia_atras", {"resultado": r, "igual_a_R_aut_con_dt_guardado": h(adapter.world) == hq,
				"separacion_de_la_rama_con_dt_nuevo": wdiff(adapter.world, retro), "dt_nuevos": dts})
		50:
			check("S_final", ha == hq and window_mismatch.is_empty() and effects == [[11, "grab"], [12, "release"]] and recoveries.is_empty(),
				{"ventanas_distintas": window_mismatch, "efectos": effects}, "igual a R_aut")

func pause_tick(t: int, ha: String, hp: String, hq: String) -> void:
	if t < 15 and ha != hp: live_mismatch.append(t)
	if t == 15:
		check("Z0_en_vivo_hasta_la_pausa", live_mismatch.is_empty(), live_mismatch, "iguales")
		clock.paused = true
		pause_frames = 0
		pc_at_pause = provider_calls
	if t > 16 and ha != hq: window_mismatch.append(t)
	if t == 40:
		check("Z_final", ha == hq and window_mismatch.is_empty() and effects == [[11, "grab"], [12, "release"]], {"ventanas_distintas": window_mismatch, "efectos": effects}, "igual a R_aut")

func _process(_delta: float) -> void:
	if not done and Time.get_ticks_usec() - started > 7000000:
		check("interno_plazo", false, "7 s"); finish(); return
	if pause_frames < 0: return
	pause_frames += 1
	if pause_frames == 3 or pause_frames == 7:
		check("Z1_pausa_sin_avance_%d" % pause_frames, clock.tick == 15 and adapter.world.get_tick() == 15 and provider_calls == pc_at_pause and adapter.recorded_frame(16).is_empty(),
			{"tick": clock.tick, "mundo": adapter.world.get_tick(), "proveedor": provider_calls - pc_at_pause}, "nada avanza")
	if pause_frames == 5:
		var before := wdiff(adapter.world, r_auth)
		var r := reconcile_logged(10, cp_auth[10])
		check("Z3_correccion_en_pausa", r.ok and h(adapter.world) == h(r_auth) and clock.tick == 15 and before > SENS, {"antes": before, "resultado": r}, "igual a R_aut@15 sin avanzar")
	if pause_frames == 8: clock.step()
	if pause_frames == 14:
		check("Z2_un_paso_en_pausa", clock.tick == 16 and adapter.world.get_tick() == 16 and provider_calls == pc_at_pause + 1 and not adapter.recorded_frame(16).is_empty() and adapter.recorded_frame(17).is_empty() and h(adapter.world) == h(r_auth),
			{"tick": clock.tick, "mundo": adapter.world.get_tick(), "proveedor": provider_calls - pc_at_pause}, "exactamente un tick")
	if pause_frames == 20:
		clock.paused = false
		pause_frames = -1

func errors_queue(t: int) -> void:
	if t == 4:
		var before: PackedByteArray = adapter.world.snapshot_trusted()
		var cases := [[t - 1, 901, "grab", ANCHOR, Vector3.ZERO, "invalid_action_tick"], [t + 2, 902, "grab", ANCHOR, Vector3.ZERO, "invalid_action_tick"],
			[t, 903, "drop", ANCHOR, Vector3.ZERO, "invalid_action"], [t, 0, "grab", ANCHOR, Vector3.ZERO, "invalid_action"],
			[t, 2147483648, "grab", ANCHOR, Vector3.ZERO, "invalid_action"], [t, 904, "grab", Vector3(NAN, 0, 0), Vector3.ZERO, "invalid_action"],
			[t, 905, "grab", Vector3(1001, 0, 0), Vector3.ZERO, "invalid_action"], [t, 906, "release", Vector3.ZERO, Vector3(2e5, 0, 0), "invalid_action"]]
		var bad := []
		for c in cases:
			var ok: bool = adapter.queue_action(c[0], c[1], c[2], c[3], c[4])
			if ok or adapter.last_error != c[5] or not adapter.ready_for_input: bad.append([c[1], ok, adapter.last_error])
		check("E1_acciones_invalidas", bad.is_empty() and adapter.world.snapshot_trusted() == before and recoveries.is_empty(), {"casos": cases.size(), "problemas": bad}, "false, sin recuperación")
	if t == 6:
		var ok1 := q(t, 21, "grab", ANCHOR)
		var ok2: bool = adapter.queue_action(t, 22, "grab", ANCHOR, Vector3.ZERO)
		var e2: String = adapter.last_error
		var ok3: bool = adapter.queue_action(t, 21, "grab", ANCHOR, Vector3.ZERO)
		var ok4: bool = adapter.queue_action(t, 21, "grab", ANCHOR * 2.0, Vector3.ZERO)
		check("E2_una_por_tick_duplicado_y_conflicto", ok1 and not ok2 and e2 == "action_capacity" and ok3 and not ok4 and adapter.last_error == "action_identity_conflict" and adapter.ready_for_input,
			{"capacidad": e2, "conflicto": adapter.last_error}, "action_capacity, true, action_identity_conflict")
	if t == 20: q(t, 23, "release", Vector3.ZERO, RELEASE_IMPULSE)

func errors_tick(t: int, ha: String, hp: String) -> void:
	if ha != hp: live_mismatch.append(t)
	if t == 10:
		var r0 := reconcile_logged(8, cp_pure[8])
		var other = make_world(true)
		var big := PackedByteArray(); big.resize(1048621)
		var corrupt: PackedByteArray = cp_pure[9].duplicate(); corrupt[corrupt.size() - 1] ^= 1
		var cases := [[8, cp_pure[8], "duplicate_or_stale_authority"], [7, cp_pure[7], "duplicate_or_stale_authority"], [11, cp_pure[10], "invalid_checkpoint"],
			[9, PackedByteArray(), "invalid_checkpoint"], [9, big, "invalid_checkpoint"], [9, corrupt, "checkpoint_rejected"],
			[9, other.snapshot_trusted(), "checkpoint_rejected"], [9, cp_pure[7], "checkpoint_tick_mismatch"]]
		var bad := []
		for c in cases:
			var before: PackedByteArray = adapter.world.snapshot_trusted()
			var r := reconcile_logged(c[0], c[1])
			if r.ok or r.error != c[2] or adapter.world.snapshot_trusted() != before or not adapter.ready_for_input or r.effects != 0:
				bad.append([c[0], c[2], r])
		check("E3_correcciones_rechazadas", r0.ok and bad.is_empty() and recoveries.is_empty(), {"valida_previa": r0, "casos": cases.size(), "problemas": bad}, "false con su código, mundo igual")
	if t == 22:
		var before: PackedByteArray = adapter.world.snapshot_trusted()
		var r := reconcile_logged(19, cp_nograb[19])
		var atomic: bool = not r.ok and r.error.begins_with("replay_failed") and adapter.world.snapshot_trusted() == before and adapter.ready_for_input and r.effects == 0
		var r2 := reconcile_logged(19, cp_pure[19])
		check("E4_repeticion_fallida_atomica", atomic and r2.ok and h(adapter.world) == h(r_pure), {"fallida": r, "valida_despues": r2}, "replay_failed sin cambios; luego 19 se acepta")
	if t == 40:
		check("E_final", ha == hp and live_mismatch.is_empty() and effects == [[21, "grab"], [23, "release"]] and recoveries.is_empty(),
			{"distintos": live_mismatch, "efectos": effects}, "igual a R_pura")

func limits_queue(t: int) -> void:
	if t >= 2 and t <= 257:
		var kind := "grab" if t % 2 == 0 else "release"
		if not q(t, t - 1, kind, ANCHOR if kind == "grab" else Vector3.ZERO, Vector3(0, 0.5, 0) if kind == "release" else Vector3.ZERO):
			info("L1_accion_rechazada_%d" % t, adapter.last_error)
	if t == 258:
		var ok: bool = adapter.queue_action(t, 257, "grab", ANCHOR, Vector3.ZERO)
		check("L1_accion_257", not ok and adapter.last_error == "action_capacity" and adapter.ready_for_input, adapter.last_error, "action_capacity sin recuperación")
	if t == 259:
		var ok: bool = adapter.queue_action(t, 5, "grab", ANCHOR, Vector3.ZERO)
		check("L1_id_usado_con_otro_contenido", not ok and adapter.last_error == "action_identity_conflict", adapter.last_error, "action_identity_conflict")

func limits_tick(t: int, ha: String, hp: String) -> void:
	if t <= 260 and ha != hp: live_mismatch.append(t)
	if t == 258:
		var st: Dictionary = adapter.history_stats()
		check("L2_historia", st.ticks == 120 and st.oldest == 139 and st.latest == 258 and st.bytes <= adapter.HISTORY_BYTES and adapter.recorded_frame(138).is_empty() and not adapter.recorded_frame(139).is_empty(),
			st, "120 frames, el 139 primero, ≤ 256 KiB")
		var max_in := 0
		var max_frame := 0
		for k in range(139, 259):
			max_frame = maxi(max_frame, var_to_bytes(adapter.recorded_frame(k)).size())
			max_in = maxi(max_in, my_frames[k].bytes.size())
		info("L4_tamanos", {"input_max_bytes": max_in, "limite_input": adapter.MAX_INPUT_BYTES, "frame_max_bytes": max_frame,
			"frames_para_llenar_256KiB": adapter.HISTORY_BYTES / maxi(1, max_frame), "historia_ticks": adapter.HISTORY_TICKS, "presupuesto": adapter.MAX_REPLAY_STEPS})
		check("L1_256_acciones", effects.size() == 256 and adapter.ready_for_input, {"efectos": effects.size()}, "256 ejecutadas")
	if t == 260:
		var r := reconcile_logged(236, cp_pure[236])
		check("L3_24_pasos_aceptados", r.ok and r.steps == 24 and h(adapter.world) == hp and live_mismatch.is_empty(), {"resultado": r, "distintos": live_mismatch}, "igual a R_pura")
	if t == 262:
		var before: PackedByteArray = adapter.world.snapshot_trusted()
		var r := reconcile_logged(237, cp_pure[237])
		check("L3_25_pasos_recuperacion", not r.ok and r.error == "replay_budget" and not adapter.ready_for_input and adapter.world.snapshot_trusted() == before and recoveries.size() == 1,
			{"resultado": r, "recuperaciones": recoveries}, "replay_budget, mundo igual")
	if t == 266:
		check("L3_despues_sin_pasos", adapter.world.get_tick() == 262 and refused_captures == 4 and effects.size() == 256,
			{"tick_mundo": adapter.world.get_tick(), "capturas_rechazadas": refused_captures, "efectos": effects.size()}, "mundo en 262, 4 capturas rechazadas")

func resync_tick(t: int, ha: String, hp: String) -> void:
	if t < 20 and ha != hp: live_mismatch.append(t)
	if t == 20:
		var before: PackedByteArray = adapter.world.snapshot_trusted()
		clock.hard_resynced.emit()
		check("R1_resincronizacion", recoveries.size() == 1 and recoveries[0][1] == "clock_resynced" and adapter.history_stats().ticks == 0 and adapter.world.snapshot_trusted() == before and not adapter.ready_for_input and live_mismatch.is_empty(),
			{"recuperaciones": recoveries, "historia": adapter.history_stats()}, "clock_resynced, historia vacía, mundo igual")
	if t == 25:
		var qa: bool = adapter.queue_action(26, 30, "release", Vector3.ZERO, Vector3.ZERO)
		var rc: bool = adapter.reconcile_trusted(19, cp_pure[19])
		check("R1_rechaza_despues", not qa and not rc and adapter.last_error == "not_ready", adapter.last_error, "not_ready")
	if t == 30:
		check("R1_sin_pasos_despues", adapter.world.get_tick() == 20 and refused_captures == 10 and effects == [[11, "grab"]],
			{"tick_mundo": adapter.world.get_tick(), "capturas_rechazadas": refused_captures, "efectos": effects}, "mundo en 20")

func tuning_start_checks() -> void:
	var bad := []
	for change in [["hold_follow_time", 0.09], ["hold_turn_accel", 7000.0]]:
		var tb := ActorTuning.new(); add_child(tb)
		tb.set(change[0], change[1])
		var a = Adapter.new(); add_child(a)
		var ok: bool = a.start(clock, actor, tb, make_world, UID, 1, 1)
		if ok or a.last_error != "unsupported_hand_tuning" or a.clock != null or a.ready_for_input: bad.append([change, ok, a.last_error])
	check("T1_tuning_no_soportado", bad.is_empty(), bad, "unsupported_hand_tuning, sin conectar")

func tuning_tick(t: int, ha: String, hp: String) -> void:
	if t < 15 and ha != hp: live_mismatch.append(t)
	if t == 15: tuning.hold_min_distance += 0.05
	if t == 16:
		check("T2_cambio_de_tuning", recoveries == [[16, "tuning_changed"]] and adapter.world.get_tick() == 15 and not adapter.ready_for_input and live_mismatch.is_empty(),
			{"recuperaciones": recoveries, "tick_mundo": adapter.world.get_tick()}, "tuning_changed en 16, mundo en 15")
	if t == 20:
		check("T2_sin_pasos_despues", adapter.world.get_tick() == 15 and effects == [[11, "grab"]], {"tick_mundo": adapter.world.get_tick(), "efectos": effects}, "mundo en 15")

func capture_setup() -> void:
	for spec in [["tick", 1], ["dup", 1], ["impossible", 1], ["nan", 1], ["session", 2]]:
		var a = Adapter.new(); add_child(a)
		var n: String = spec[0]
		a.recovery_required.connect(func(r: String): extra_rec[n] = [clock.tick, r])
		if not a.start(clock, actor, tuning, make_world, UID, 1, spec[1]):
			noeval = true; info("C_inicio_" + n, a.last_error)
		extra[n] = a

func capture_extra(t: int, input: ActorInput) -> void:
	for n in extra:
		var a = extra[n]
		if not a.ready_for_input:
			continue
		if n == "tick" and t == 8:
			var other := ActorInput.make(t + 1, input.move, input.look_yaw, input.buttons, input.jump_presses)
			other.hold = input.hold.duplicate()
			a.capture(other)
		elif n == "dup" and t == 9:
			a.capture(input)
			a.capture(input)
		elif n == "impossible" and t == 10:
			var bad := ActorInput.make(t, input.move, input.look_yaw, 0, input.jump_presses)
			bad.buttons = 0x80
			bad.hold = input.hold.duplicate()
			a.capture(bad)
		elif n == "nan" and t == 11:
			var bad := ActorInput.make(t, input.move, input.look_yaw, input.buttons, input.jump_presses)
			bad.look_yaw = NAN
			bad.hold = input.hold.duplicate()
			a.capture(bad)
		else:
			a.capture(input)

func capture_tick(t: int, ha: String, hp: String) -> void:
	if ha != hp: live_mismatch.append(t)
	if t == 30:
		var want := {"tick": [8, "invalid_or_duplicate_input"], "dup": [9, "invalid_or_duplicate_input"], "impossible": [10, "invalid_or_duplicate_input"],
			"nan": [11, "invalid_or_duplicate_input"], "session": [1, "invalid_input_bytes"]}
		var bad := []
		for n in want:
			var a = extra[n]
			var got = extra_rec.get(n, [])
			if got != want[n] or a.world.get_tick() != want[n][0] - 1 or a.ready_for_input: bad.append([n, got, a.world.get_tick()])
		check("C1_capturas_invalidas", bad.is_empty(), {"esperado": want, "obtenido": extra_rec, "problemas": bad}, "recuperación en su tick, mundo en el anterior")
		check("C2_principal_no_afectado", live_mismatch.is_empty() and ha == hp and adapter.ready_for_input and effects == [[11, "grab"]], {"distintos": live_mismatch}, "igual a R_pura")

func finish() -> void:
	if done: return
	done = true
	if clock != null: clock.set_physics_process(false)
	SimClock.clear_world_slow()
	var fails := checks.filter(func(c): return c.verdict == "FAIL").size()
	var result := {"schema": "cv10", "mode": mode, "checks": checks, "facts": facts, "fails": fails, "noeval": noeval,
		"provider_calls": provider_calls, "effects": effects, "recoveries": recoveries,
		"seconds": float(Time.get_ticks_usec() - started) / 1e6}
	if adapter != null: result["replayed_steps"] = adapter.replayed_steps
	if not result_path.is_empty():
		var f := FileAccess.open(result_path, FileAccess.WRITE)
		if f != null: f.store_string(JSON.stringify(result, " ", true, true)); f.close()
	if not trace_path.is_empty():
		var f := FileAccess.open(trace_path, FileAccess.WRITE)
		if f != null: f.store_string(JSON.stringify(trace, "", true, true)); f.close()
	print("CV10_RESULT mode=%s fails=%d noeval=%s" % [mode, fails, noeval])
	get_tree().quit(2 if fails > 0 else (3 if noeval else 0))
