extends "res://prototypes/objetos_adaptador/validacion_claude/cv10_probe.gd"
## Validación independiente (Claude), entrega 11: API de autoridad con ámbito/revisión,
## suelta tardía, invalidación histórica y recuperación (criterios_entrega_11.md §4).
## Hereda escena, proveedor variable, diario propio y referencias de cv10_probe.gd sin cambiarlos.
## Modos: scope, late, time, actor, resync. El "proveedor de ojos corregidos" es este instrumento.

var factory_calls := 0
var r_host
var cp_host := {}
var r_new
var r_corr
var cp_corr := {}
var corr_eyes := {}
var gen_marks := {}
var live11: Array = []
var alt_ref

func make_world(bigger := false):
	factory_calls += 1
	return super(bigger)

func _ready() -> void:
	super()
	if done: return
	end_tick = {"scope": 22, "late": 42, "time": 46, "actor": 50, "resync": 26}.get(mode, 30)
	if mode == "late": r_host = make_world()

# --- utilidades -----------------------------------------------------------------------------
func packet(rev: int, tick: int, snap: PackedByteArray, acks := []) -> Dictionary:
	var p: Dictionary = adapter.authority_scope().duplicate()
	p["version"] = 1
	p["revision"] = rev
	p["tick"] = tick
	p["snapshot"] = snap
	p["acks"] = acks
	return p

func frames_for(from_t: int, to_t: int, eyes_of := {}, dt_of := {}) -> Array:
	var out: Array = []
	for t in range(from_t, to_t + 1):
		var f: Dictionary = my_frames[t]
		out.append({"tick": t, "dt": dt_of.get(t, f.dt), "eyes": eyes_of.get(t, f.eyes), "input": f.bytes, "action": f.action.duplicate(true)})
	return out

func apply_frame_with(w, t: int, eyes: Vector3, dt: float, act: Dictionary, extra_at := -1) -> void:
	var s := StreamPeerBuffer.new()
	s.data_array = my_frames[t].bytes
	var input := ActorInput.read_from(s)
	var goal := InvHoldMotion.target_of(eyes, input, tuning)
	var state: Dictionary = w.sample(UID, 1)
	var kind: String = act.get("kind", "")
	if kind == "grab": w.begin_hold(UID, 1, act.anchor, goal)
	if (state.held or kind == "grab") and not input.hold.is_empty(): w.set_goal(UID, 1, goal)
	if kind == "release": w.release_body(UID, 1, act.impulse)
	if t == extra_at: w.apply_impulse(UID, 1, RELEASE_IMPULSE)
	w.step(dt)

## Llama y mide qué cambió. Un rechazo correcto no toca nada.
func attempt(call: Callable) -> Dictionary:
	var w0: PackedByteArray = adapter.world.snapshot_trusted()
	var la0: Dictionary = adapter.last_authority()
	var g0: int = adapter.recovery_generation()
	var rd0: bool = adapter.ready_for_input
	var f0 := factory_calls
	var e0 := effects.size()
	var rc0 := recoveries.size()
	var ok: bool = call.call()
	return {"ok": ok, "error": adapter.last_error, "world_same": adapter.world.snapshot_trusted() == w0,
		"authority_same": adapter.last_authority() == la0, "gen_same": adapter.recovery_generation() == g0,
		"ready_same": adapter.ready_for_input == rd0, "factory": factory_calls - f0, "effects": effects.size() - e0, "recoveries": recoveries.size() - rc0}

func atomic(r: Dictionary, expected: String, factory := 0) -> bool:
	return not r.ok and r.error == expected and r.world_same and r.authority_same and r.gen_same and r.ready_same \
		and r.effects == 0 and r.recoveries == 0 and r.factory == factory

func run_cases(id: String, cases: Array) -> void:
	var bad: Array = []
	for c in cases:
		var r := attempt(c[1])
		if not atomic(r, c[2], c[3] if c.size() > 3 else 0): bad.append([c[0], c[2], r])
	check(id, bad.is_empty(), {"casos": cases.size(), "problemas": bad}, "false con su código, atómico")

func ack_variant(base: Dictionary, ack_ok: Dictionary, changes: Dictionary) -> Dictionary:
	var d := ack_ok.duplicate()
	d.merge(changes, true)
	return with(base, "acks", [d])

func frames_mod(good: Array, i: int, key: String, value) -> Array:
	var fr: Array = good.duplicate(true)
	fr[i][key] = value
	return fr

func with(p: Dictionary, key: String, value) -> Dictionary:
	var q2 := p.duplicate(true)
	q2[key] = value
	return q2

# --- hooks ----------------------------------------------------------------------------------
func queue_for(t: int) -> void:
	super(t)
	if mode == "late" and t == 30:
		check("L0_suelta_predicha_en_cola", q(t, 12, "release", Vector3.ZERO, RELEASE_IMPULSE), adapter.last_error, "true")
	if mode == "actor" and t == 18:
		var ok: bool = adapter.queue_action(19, 12, "release", Vector3.ZERO, RELEASE_IMPULSE)
		if ok: my_actions[19] = {"id": 12, "kind": "release", "tick": 19, "anchor": Vector3.ZERO, "impulse": RELEASE_IMPULSE}
		check("H0_suelta_encolada_para_19", ok, adapter.last_error, "true")

func provide_input(who: ActorBody, t: int) -> ActorInput:
	var input := super(who, t)
	if mode == "actor" and t == 24 and not done:
		var g: int = adapter.recovery_generation()
		var r := attempt(func(): return adapter.recover_authority_trusted(packet(1, 15, cp_auth[15]), frames_for(16, 23), g))
		check("H2_dentro_del_tick_recovery_phase", atomic(r, "recovery_phase"), r, "recovery_phase, atómico")
	return input

func after_tick(t: int) -> void:
	if done: return
	super(t)
	if done: return
	match mode:
		"scope": scope_tick(t)
		"late": late_tick(t)
		"time": time_tick(t)
		"actor": actor_tick(t)
		"resync": resync11_tick(t)

# --- scope ----------------------------------------------------------------------------------
func scope_tick(t: int) -> void:
	if t != 20: return
	var base := packet(1, 15, cp_auth[15])
	var ack_ok := {"id": 11, "kind": "grab", "requested_tick": 6, "applied_tick": 6}
	var big := PackedByteArray(); big.resize(1048621)
	var many: Array = []
	for i in 17: many.append(ack_ok.duplicate())
	var extra_key := base.duplicate(true); extra_key["x"] = 1
	var missing := base.duplicate(true); missing.erase("acks")
	var a := func(p): return func(): return adapter.apply_authority_trusted(p)
	var ack5 := ack_ok.duplicate(); ack5["extra"] = 0
	run_cases("K1_rechazos_sin_candidato", [
		["conexion", a.call(with(base, "connection", 2)), "authority_scope"],
		["contexto", a.call(with(base, "context", 2)), "authority_scope"],
		["uid", a.call(with(base, "uid", 3)), "authority_scope"],
		["aparicion", a.call(with(base, "epoch", 2)), "authority_scope"],
		["sesion", a.call(with(base, "hold_session", 2)), "authority_scope"],
		["firma_otra", a.call(with(base, "hand_signature", "0".repeat(64))), "authority_scope"],
		["firma_largo", a.call(with(base, "hand_signature", "abc")), "authority_scope"],
		["version", a.call(with(base, "version", 2)), "authority_version"],
		["revision_0", a.call(with(base, "revision", 0)), "invalid_authority_envelope"],
		["revision_float", a.call(with(base, "revision", 1.0)), "invalid_authority_envelope"],
		["tick_negativo", a.call(with(base, "tick", -1)), "invalid_authority_envelope"],
		["clave_de_mas", a.call(extra_key), "invalid_authority_envelope"],
		["clave_de_menos", a.call(missing), "invalid_authority_envelope"],
		["snapshot_texto", a.call(with(base, "snapshot", "texto")), "invalid_checkpoint"],
		["snapshot_vacio", a.call(with(base, "snapshot", PackedByteArray())), "invalid_checkpoint"],
		["snapshot_grande", a.call(with(base, "snapshot", big)), "invalid_checkpoint"],
		["acks_no_lista", a.call(with(base, "acks", "no")), "invalid_action_confirmation"],
		["acks_17", a.call(with(base, "acks", many)), "invalid_action_confirmation"],
		["ack_id_desconocido", a.call(ack_variant(base, ack_ok, {"id": 99})), "invalid_action_confirmation"],
		["ack_otro_tipo", a.call(ack_variant(base, ack_ok, {"kind": "release"})), "invalid_action_confirmation"],
		["ack_otro_tick_pedido", a.call(ack_variant(base, ack_ok, {"requested_tick": 7})), "invalid_action_confirmation"],
		["ack_aplicado_antes", a.call(ack_variant(base, ack_ok, {"applied_tick": 5})), "invalid_action_confirmation"],
		["ack_aplicado_despues_del_paquete", a.call(ack_variant(base, ack_ok, {"applied_tick": 16})), "invalid_action_confirmation"],
		["ack_repetido", a.call(with(base, "acks", [ack_ok.duplicate(), ack_ok.duplicate()])), "invalid_action_confirmation"],
		["ack_5_claves", a.call(with(base, "acks", [ack5])), "invalid_action_confirmation"],
		["tick_futuro", a.call(with(base, "tick", 25)), "future_authority"],
	])
	var corrupt: PackedByteArray = cp_auth[15].duplicate(); corrupt[corrupt.size() - 1] ^= 1
	run_cases("K2_rechazos_con_candidato", [
		["snapshot_danado", a.call(with(base, "snapshot", corrupt)), "checkpoint_rejected", 1],
		["snapshot_de_otro_tick", a.call(with(base, "snapshot", cp_auth[14])), "checkpoint_tick_mismatch", 1],
	])
	var before := wdiff(adapter.world, r_auth)
	var r := attempt(a.call(with(base, "acks", [ack_ok.duplicate()])))
	var b = Adapter.new(); add_child(b)
	var okb: bool = b.start(clock, actor, tuning, make_world, UID, 1, 1, 0, 1)
	check("K3_revision_1_intacta", r.ok and h(adapter.world) == h(r_auth) and adapter.last_authority() == {"tick": 15, "revision": 1} and before > SENS and r.effects == 0
		and not okb and b.last_error == "invalid_context_binding" and b.clock == null,
		{"antes": before, "resultado": r, "autoridad": adapter.last_authority(), "inicio_conexion_0": b.last_error}, "aceptada, igual a R_aut@20")

# --- late -----------------------------------------------------------------------------------
func host_step(t: int) -> void:
	if t == 5: r_host.apply_impulse(3, 1, AUTH_EVENT)
	var f: Dictionary = my_frames[t]
	var act: Dictionary = f.action
	if t == 30: act = {}
	if t == 34:
		act = my_actions[30].duplicate(true)
		act["tick"] = 34
	apply_frame_with(r_host, t, f.eyes, f.dt, act)
	cp_host[t] = r_host.snapshot_trusted()

func host_branch(from_t: int, to_t: int, extra_at := -1, never_release := false, pre_impulse := {}):
	var w = make_world()
	w.restore_trusted(cp_host[from_t])
	for k in range(from_t + 1, to_t + 1):
		var act: Dictionary = {} if (never_release or k != 34) else my_actions[30].duplicate(true)
		if pre_impulse.has(k): w.apply_impulse(4, 1, pre_impulse[k])
		apply_frame_with(w, k, my_frames[k].eyes, my_frames[k].dt, act, extra_at)
	return w

func late_tick(t: int) -> void:
	host_step(t)
	if alt_ref != null:
		apply_frame_with(alt_ref, t, my_frames[t].eyes, my_frames[t].dt, {})
	match t:
		33:
			var ack := {"id": 12, "kind": "release", "requested_tick": 30, "applied_tick": 34}
			var r1 := attempt(func(): return adapter.apply_authority_trusted(packet(1, 32, cp_host[32], [ack])))
			var before := wdiff(adapter.world, r_host)
			var r2 := attempt(func(): return adapter.apply_authority_trusted(packet(1, 32, cp_host[32])))
			check("L1_estado_sin_la_accion", atomic(r1, "invalid_action_confirmation") and r2.ok and h(adapter.world) == h(r_host) and before > SENS and adapter.world.sample(UID, 1).held,
				{"con_ack_aplicado_34": r1, "antes": before, "sin_ack": r2}, "rechazo atómico; luego igual a H@33 y agarrado")
		37:
			var before := wdiff(adapter.world, r_host)
			var ack := {"id": 12, "kind": "release", "requested_tick": 30, "applied_tick": 34}
			var r := attempt(func(): return adapter.apply_authority_trusted(packet(2, 34, cp_host[34], [ack])))
			var double = host_branch(34, 37, 35, true)
			var never = host_branch(33, 37, -1, true)
			var d_db := wdiff(adapter.world, double)
			var d_nv := wdiff(adapter.world, never)
			check("L2_suelta_tardia", r.ok and h(adapter.world) == h(r_host) and before > SENS and d_db > SENS and d_nv > SENS and r.effects == 0 and not adapter.world.sample(UID, 1).held,
				{"antes": before, "resultado": r, "doble_impulso": d_db, "nunca_suelta": d_nv}, "igual a H@37; controles > 1e-3")
		40:
			var r3 := attempt(func(): return adapter.apply_authority_trusted(packet(3, 37, cp_host[37])))
			var ok3: bool = r3.ok and h(adapter.world) == h(r_host)
			var alt = host_branch(36, 37, -1, true, {37: Vector3(0, 2.0, 0)})
			var alt_snap: PackedByteArray = alt.snapshot_trusted()
			var r4 := attempt(func(): return adapter.apply_authority_trusted(packet(4, 37, alt_snap)))
			for k in range(38, 41): apply_frame_with(alt, k, my_frames[k].eyes, my_frames[k].dt, {})
			var ok4: bool = r4.ok and h(adapter.world) == h(alt)
			alt_ref = alt
			check("K4_misma_revision_tick", ok3 and ok4 and wdiff(alt, r_host) > SENS and adapter.last_authority() == {"tick": 37, "revision": 4},
				{"rev3": r3, "rev4_mismo_tick": r4, "separacion_de_las_dos_ramas": wdiff(alt, r_host)}, "las dos aceptadas; queda la rama de la revisión 4")
			var a := func(p): return func(): return adapter.apply_authority_trusted(p)
			run_cases("K4_duplicados_y_viejos", [
				["rev4_otra_vez", a.call(packet(4, 37, alt_snap)), "duplicate_or_stale_revision"],
				["rev3_vieja", a.call(packet(3, 37, cp_host[37])), "duplicate_or_stale_revision"],
				["rev5_tick_36", a.call(packet(5, 36, cp_host[36])), "authority_tick_regression"],
				["rev5_tick_41", a.call(packet(5, 41, cp_host[40])), "future_authority"],
			])
		41:
			check("L3_efectos", effects == [[11, "grab"], [12, "release"]] and effect_ticks == [6, 30] and h(adapter.world) == h(alt_ref),
				{"efectos": effects, "ticks": effect_ticks}, "agarre y suelta una vez cada uno")

# --- time -----------------------------------------------------------------------------------
func time_tick(t: int) -> void:
	if r_new != null and t > 30:
		apply_frame_with(r_new, t, my_frames[t].eyes, my_frames[t].dt, my_frames[t].action)
		if h(adapter.world) != h(r_new): live11.append(t)
	if t == 30:
		var old_dt := {}
		for k in range(25, 31): old_dt[k] = my_frames[k].dt
		SimClock.add_world_slow(25, 33, 0.5)
		var new_dt := {}
		for k in range(25, 31): new_dt[k] = SimClock.world_dt(k)
		r_new = make_world()
		r_new.restore_trusted(cp_auth[24])
		for k in range(25, 31): apply_frame_with(r_new, k, my_frames[k].eyes, new_dt[k], my_frames[k].action)
		var g0: int = adapter.recovery_generation()
		var r := attempt(func(): return adapter.apply_authority_trusted(packet(1, 24, cp_auth[24])))
		check("W1_detecta_dt_viejo", not r.ok and r.error == "timeline_invalidated:world_time" and r.world_same and r.authority_same and r.recoveries == 1 and not adapter.ready_for_input
			and adapter.recovery_generation() == g0 + 1 and adapter.recorded_frame(25).is_empty() and not adapter.recorded_frame(24).is_empty() and r.factory == 0,
			r, "invalidación con recuperación, mundo y autoridad iguales")
		var g: int = adapter.recovery_generation()
		var r_old := attempt(func(): return adapter.recover_authority_trusted(packet(1, 24, cp_auth[24]), frames_for(25, 30, {}, old_dt), g))
		var r_ok := attempt(func(): return adapter.recover_authority_trusted(packet(1, 24, cp_auth[24]), frames_for(25, 30, {}, new_dt), g))
		var sens := wdiff(r_new, r_auth)
		check("W2_lote_viejo_y_nuevo", atomic(r_old, "invalid_recovery_frame") and r_ok.ok and h(adapter.world) == h(r_new) and adapter.ready_for_input and sens > SENS and r_ok.effects == 0,
			{"dt_viejo": r_old, "dt_nuevo": r_ok, "rama_nueva_vs_vieja": sens}, "rechazo atómico; luego igual a R_nueva@30")
	if t == 45:
		check("W3_reanuda", live11.is_empty() and adapter.ready_for_input and h(adapter.world) == h(r_new), {"distintos": live11}, "igual a R_nueva 31..45")

# --- actor ----------------------------------------------------------------------------------
func corr_step(t: int) -> void:
	apply_frame_with(r_corr, t, corr_eyes.get(t, my_frames[t].eyes), my_frames[t].dt, my_frames[t].action)
	cp_corr[t] = r_corr.snapshot_trusted()

func actor_tick(t: int) -> void:
	if r_corr != null and t > 24:
		corr_step(t)
		if adapter.ready_for_input and h(adapter.world) != h(r_corr): live11.append(t)
	match t:
		18:
			var g0: int = adapter.recovery_generation()
			var ok: bool = adapter.invalidate_history_from(16, "actor")
			gen_marks["g1"] = adapter.recovery_generation()
			check("H1_invalida_desde_16", ok and not adapter.ready_for_input and adapter.recovery_generation() == g0 + 1 and recoveries.size() == 1
				and recoveries[0][1] == "timeline_invalidated:actor" and adapter.recorded_frame(16).is_empty() and not adapter.recorded_frame(15).is_empty(),
				{"recuperaciones": recoveries, "generacion": adapter.recovery_generation()}, "detenido, 16 borrado, 15 conservado")
		20:
			var g1: int = adapter.recovery_generation()
			var ok: bool = adapter.invalidate_history_from(17, "actor")
			var g2: int = adapter.recovery_generation()
			var ok_future: bool = adapter.invalidate_history_from(1000, "actor")
			var g_future: int = adapter.recovery_generation()
			var rc := recoveries.size()
			var ok_bad: bool = adapter.invalidate_history_from(10, "red")
			check("H1_notificaciones_repetidas", ok and g2 == g1 + 1 and recoveries.size() == 2 and ok_future and g_future == g2 and not ok_bad and adapter.last_error == "invalid_history_change" and rc == 2,
				{"generaciones": [g1, g2, g_future], "recuperaciones": recoveries}, "otra generación y otra señal; futuro sin cambios; causa inválida")
		24:
			for k in range(16, 25): corr_eyes[k] = my_frames[k].eyes + Vector3(0, 0.12, 0)
			r_corr = make_world()
			r_corr.restore_trusted(cp_auth[15])
			cp_corr[15] = cp_auth[15]
			for k in range(16, 25): corr_step(k)
			var g: int = adapter.recovery_generation()
			var good := frames_for(16, 24, corr_eyes)
			var pk := packet(1, 15, cp_auth[15])
			var rec := func(p, fr, gg): return func(): return adapter.recover_authority_trusted(p, fr, gg)
			var swapped: Array = good.duplicate(true); var tmp = swapped[0]; swapped[0] = swapped[1]; swapped[1] = tmp
			var extra_key: Array = good.duplicate(true); extra_key[0]["x"] = 1
			var non_dict: Array = good.duplicate(true); non_dict[0] = 5
			var other_session := ActorInput.make(16, Vector2(0.1, 0.2), 0.3, 0, 0)
			other_session.hold = ActorInput.pack_hold(2, 0.0, 1.0, Quaternion.IDENTITY)
			var sb := StreamPeerBuffer.new(); other_session.write_to(sb)
			var act19: Dictionary = good[3].action.duplicate(true)
			var act_conflict := act19.duplicate(true); act_conflict["impulse"] = Vector3(0, 9, 0)
			run_cases("H2_lotes_invalidos", [
				["generacion_vieja", rec.call(pk, good, gen_marks["g1"]), "stale_recovery_generation"],
				["8_frames", rec.call(pk, good.slice(0, 8), g), "incomplete_recovery_frames"],
				["10_frames", rec.call(pk, good + [good[8].duplicate(true)], g), "incomplete_recovery_frames"],
				["orden_cambiado", rec.call(pk, swapped, g), "invalid_recovery_frame"],
				["clave_de_mas", rec.call(pk, extra_key, g), "invalid_recovery_frame"],
				["dt_entero", rec.call(pk, frames_mod(good, 0, "dt", 1), g), "invalid_recovery_frame"],
				["dt_otro", rec.call(pk, frames_mod(good, 0, "dt", 0.02), g), "invalid_recovery_frame"],
				["ojos_nan", rec.call(pk, frames_mod(good, 0, "eyes", Vector3(NAN, 0, 0)), g), "invalid_recovery_frame"],
				["input_lista", rec.call(pk, frames_mod(good, 0, "input", [1, 2]), g), "invalid_recovery_frame"],
				["frame_no_diccionario", rec.call(pk, non_dict, g), "invalid_recovery_frame"],
				["input_de_otro_tick", rec.call(pk, frames_mod(good, 0, "input", my_frames[17].bytes), g), "invalid_recovery_input"],
				["input_de_otra_sesion", rec.call(pk, frames_mod(good, 0, "input", sb.data_array), g), "invalid_recovery_input"],
				["accion_desconocida", rec.call(pk, frames_mod(good, 4, "action", {"id": 99, "kind": "grab", "tick": 20, "anchor": Vector3.ZERO, "impulse": Vector3.ZERO}), g), "unknown_recovery_action"],
				["accion_otro_impulso", rec.call(pk, frames_mod(good, 3, "action", act_conflict), g), "recovery_action_conflict"],
				["accion_otro_tick", rec.call(pk, frames_mod(good, 4, "action", act19), g), "recovery_action_conflict"],
				["paquete_otro_ambito", rec.call(with(pk, "uid", 3), good, g), "authority_scope"],
				["snapshot_de_otro_tick", rec.call(with(pk, "snapshot", cp_auth[14]), good, g), "checkpoint_tick_mismatch", 1],
			])
			var pos0: Vector3 = actor.state.position
			var tick0: int = clock.tick
			var pc0 := provider_calls
			var r := attempt(rec.call(pk, good, g))
			var hist_ok: bool = adapter.recorded_frame(15).is_empty()
			for i in good.size():
				var f: Dictionary = adapter.recorded_frame(16 + i)
				if f.is_empty() or f.eyes != good[i].eyes or f.input != good[i].input or f.dt != good[i].dt or not same_action(f.action, good[i].action): hist_ok = false
			check("H3_recuperacion_con_ojos_corregidos", r.ok and h(adapter.world) == h(r_corr) and adapter.ready_for_input and actor.state.position == pos0 and clock.tick == tick0
				and provider_calls == pc0 and hist_ok and r.effects == 0 and adapter.last_authority() == {"tick": 15, "revision": 1},
				{"resultado": r, "diario_igual_al_lote": hist_ok, "suspendido_desde": 19}, "igual a R_corr@24, sin mover actor ni reloj")
			info("H6_suelta_cancelada_y_aplicada_por_el_lote", {"agarrado_despues": adapter.world.sample(UID, 1).held, "efectos": effects})
		26:
			var dup: bool = adapter.queue_action(19, 12, "release", Vector3.ZERO, RELEASE_IMPULSE)
			var conf: bool = adapter.queue_action(27, 12, "release", Vector3.ZERO, RELEASE_IMPULSE)
			info("H6_reencolar_id_12", {"mismo_contenido": dup, "otro_tick": conf, "error": adapter.last_error})
		44:
			var r1 := attempt(func(): return adapter.recover_authority_trusted(packet(2, 40, cp_corr[40]), frames_for(41, 44), adapter.recovery_generation()))
			var r2 := attempt(func(): return adapter.apply_authority_trusted(packet(1, 15, cp_auth[15])))
			check("H4_reanuda_y_rechaza", live11.is_empty() and atomic(r1, "recovery_not_needed") and atomic(r2, "duplicate_or_stale_revision") and h(adapter.world) == h(r_corr),
				{"distintos_25_44": live11, "recover_activo": r1, "revision_1_otra_vez": r2}, "igual a R_corr; rechazos atómicos")
		45:
			adapter.invalidate_history_from(44, "actor")
			var g: int = adapter.recovery_generation()
			var r25 := attempt(func(): return adapter.recover_authority_trusted(packet(2, 20, cp_corr[20]), frames_for(21, 45, corr_eyes), g))
			var r24 := attempt(func(): return adapter.recover_authority_trusted(packet(2, 21, cp_corr[21]), frames_for(22, 45, corr_eyes), g))
			check("H5_presupuesto", atomic(r25, "replay_budget") and r24.ok and h(adapter.world) == h(r_corr) and adapter.ready_for_input,
				{"25_pasos": r25, "24_pasos": r24}, "25 rechazado atómico; 24 aceptado e igual")
		49:
			check("H_final", h(adapter.world) == h(r_corr) and live11.is_empty() and adapter.ready_for_input and effects == [[11, "grab"]], {"efectos": effects, "distintos": live11}, "igual a R_corr@49")

# --- resync ---------------------------------------------------------------------------------
func resync11_tick(t: int) -> void:
	if t > 18 and h(adapter.world) != h(r_auth): live11.append(t)
	match t:
		15:
			adapter.invalidate_history_from(12, "actor")
			gen_marks["g1"] = adapter.recovery_generation()
		17:
			clock.hard_resynced.emit()
			check("R1_resincronizacion_detenido", adapter.recovery_generation() == gen_marks["g1"] + 1 and recoveries.size() == 2 and recoveries[1][1] == "clock_resynced"
				and adapter.history_stats().ticks == 0 and not adapter.ready_for_input, {"recuperaciones": recoveries, "historia": adapter.history_stats()}, "otra generación, señal, historia vacía")
		18:
			var stale := attempt(func(): return adapter.recover_authority_trusted(packet(1, 12, cp_auth[12]), frames_for(13, 18), gen_marks["g1"]))
			var r := attempt(func(): return adapter.recover_authority_trusted(packet(1, 12, cp_auth[12]), frames_for(13, 18), adapter.recovery_generation()))
			check("R1_lote_viejo_y_valido", atomic(stale, "stale_recovery_generation") and r.ok and h(adapter.world) == h(r_auth) and adapter.ready_for_input, {"viejo": stale, "valido": r}, "igual a R_aut@18")
		25:
			check("R1_reanuda", live11.is_empty() and h(adapter.world) == h(r_auth), {"distintos": live11}, "igual a R_aut 19..25")
