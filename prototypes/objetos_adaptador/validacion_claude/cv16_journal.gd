extends Node
## Validacion independiente (Claude), entrega 16, parte J: host_action_journal.gd de Codex.
## Un proceso, ticks manuales de SimClock, ActorMotor y la extension reales, clock_adapter real.
## Fixture propio (no hereda las pruebas de Codex). Modos: journal, journal_close,
## journal_inflight, journal_capture. Solo llama la API publica del registro y lee su estado.
const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const Journal = preload("res://prototypes/objetos_adaptador/host_action_journal.gd")
const ACTOR = preload("res://scenes/actor/actor.tscn")
const PEER := 7

var mode := "journal"
var result_path := ""
var checks: Array = []
var info := {}
var rows := {}
var actor: ActorBody
var clock: SimClock
var tuning: ActorTuning
var adapter
var journal
var next_id := 0
var lcg := 20261119
var held := false
var results := {}
var effects := {}
var actions := {}
var ids_by_tick := {}
var policy_rules := {}
var policy_calls := {}
var skip_prepare := {}
var skip_capture := {}
var double_prepare := {}
var hook_after := {}
var stop_inflight_at := -1
var prepare_log := {}
var conf_bad: Array = []
var mem := {"w1": 0, "w2": 0, "all": 0}
var blocked := {"tries": 0, "action_order": 0, "other": []}
var last_tick := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
	SimClock.clear_world_slow()
	tuning = ActorTuning.new(); add_child(tuning)
	var actors := Node3D.new(); add_child(actors)
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(12, 0.2, 12)
	shape.shape = box; floor_body.add_child(shape); add_child(floor_body); floor_body.position.y = -0.1
	actor = ACTOR.instantiate(); actor.owner_peer_id = PEER; actor.state.position = Vector3(0, 0.02, 1.5); actors.add_child(actor)
	clock = SimClock.new(); clock.actors_root = actors; clock.tuning = tuning
	clock.paused = true; add_child(clock); clock.set_physics_process(false)
	clock.input_provider = provide
	adapter = Adapter.new(); add_child(adapter)
	check("setup_adapter", adapter.start(clock, actor, tuning, make_world, 2, 1, 1))
	adapter.action_effect.connect(func(id: int, _k: String): effects[id] = effects.get(id, 0) + 1)
	journal = Journal.new(); add_child(journal)
	check("setup_journal", journal.start(adapter, PEER, policy))
	journal.action_resolved.connect(on_resolved)
	clock.tick_finished.connect(after_tick)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var t0 := Time.get_ticks_msec()
	var total: int = {"journal": 590, "journal_close": 30, "journal_inflight": 12, "journal_capture": 12}.get(mode, 0)
	if total == 0: check("unknown_mode", false)
	for t in total:
		between(clock.tick)
		clock._run_tick()
	finish_checks()
	info.ms = Time.get_ticks_msec() - t0
	var failures := checks.filter(func(c): return not c.passed).size()
	var result := {"mode": mode, "status": "PASSED" if failures == 0 else "FAILED", "failures": failures,
		"checks": checks, "info": info, "rows": rows, "journal_stats": journal.stats(), "journal_error": journal.last_error,
		"adapter_error": adapter.last_error, "clock_tick": clock.tick, "native_tick": adapter.world.get_tick()}
	if not result_path.is_empty(): FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(result))
	print(JSON.stringify({"mode": mode, "status": result.status, "failures": failures, "checks": checks.size()}))
	get_tree().quit(0 if failures == 0 else 1)

func make_world():
	var w = ClassDB.instantiate("SahurObjectWorld")
	w.add_box(1, 1, Vector3(12, 0.2, 12), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)))
	w.add_box(2, 1, Vector3(0.5, 0.4, 0.5), 2.0, Transform3D(Basis.IDENTITY, Vector3(0, 0.7, -0.3)))
	w.seal_topology(1)
	return w

func check(id: String, passed: bool) -> void:
	checks.append({"id": id, "passed": passed})
	if not passed: push_error("CHECK_FAILED: " + id)

func gap() -> int:
	lcg = (lcg * 1103515245 + 12345) % 2147483648
	return 1 + (lcg >> 16) % 9

func act(tick: int, kind: String, id := -1, impulse := Vector3.ZERO) -> Dictionary:
	if id < 0:
		next_id += gap(); id = next_id
	return {"id": id, "tick": tick, "kind": kind, "anchor": Vector3.ZERO, "impulse": impulse}

func ok_kind(state_held: bool) -> String:
	return "release" if state_held else "grab"

func req(a: Dictionary, peer := PEER) -> Dictionary:
	var st: Dictionary = journal.request(peer, a)
	if st.get("status", "") == "scheduled" and not actions.has(a.id):
		actions[a.id] = a.duplicate(true); ids_by_tick[st.scheduled_tick] = a.id
	return st

func snap() -> Array:
	return [journal.stats(), adapter.world.snapshot_trusted(), results.size(), effects.duplicate()]

func atomic(name: String, a: Dictionary, expect_reason: String, peer := PEER) -> Dictionary:
	var before := snap()
	var st: Dictionary = journal.request(peer, a)
	var after := snap()
	check("%s_reason" % name, st.get("status", "") == "rejected" and st.get("reason", "") == expect_reason)
	check("%s_atomic" % name, before == after)
	rows[name] = st
	return st

func policy(peer: int, a: Dictionary, tick: int):
	var id: int = a.id
	if not policy_calls.has(id): policy_calls[id] = []
	policy_calls[id].append({"peer": peer, "tick": tick, "clock": clock.tick, "world": adapter.world.get_tick()})
	match str(policy_rules.get(id, "allow")):
		"deny": return "denied"
		"revoked": return "revoked"
		"int": return 5
		"null": return null
		"stringname": return &"denied_as_stringname"
		"array": return []
		"mutate":
			a.kind = "grab" if a.kind == "release" else "release"
			a.anchor = Vector3(0.9, 0, 0); a.impulse = Vector3(50, 0, 0); a.id = 1; a.tick = 0
			return ""
	return ""

func on_resolved(r: Dictionary) -> void:
	if not results.has(r.id): results[r.id] = []
	results[r.id].append(r.duplicate(true))
	if r.status == "applied":
		check("G_applied_after_native_step_%d" % r.id, r.applied_tick == clock.tick and adapter.world.get_tick() == clock.tick \
			and effects.get(r.id, 0) == 1)
		held = r.kind == "grab"
	r.status = "forged_by_listener" # J5: modificar lo recibido no cambia lo guardado

func provide(_who: ActorBody, tick: int) -> ActorInput:
	var input := ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion.IDENTITY)
	if not skip_prepare.has(tick):
		prepare_log[tick] = [journal.before_capture(tick), journal.last_error]
		if double_prepare.has(tick):
			var before := [journal.stats(), results.size()]
			var ok2: bool = journal.before_capture(tick)
			rows.double_prepare = {"ok": ok2, "error": journal.last_error, "atomic": [journal.stats(), results.size()] == before}
		if tick == stop_inflight_at:
			rows.inflight_queued = adapter._queued.duplicate(true)
			journal.stop("closed_inflight")
	for c in journal.confirmations():
		if c.applied_tick >= tick: conf_bad.append(["before_step", tick, c])
	if not skip_capture.has(tick): adapter.capture(input)
	return input

func after_tick(tick: int) -> void:
	last_tick = tick
	var r: int = journal.stats().records
	mem.all = maxi(mem.all, r)
	if tick >= 100 and tick < 200: mem.w1 = maxi(mem.w1, r)
	if tick >= 200 and tick <= 300: mem.w2 = maxi(mem.w2, r)
	# confirmations(): solo aplicadas retenidas, <= 16 de id mayor, ordenadas, con tick real.
	var conf: Array = journal.confirmations()
	var retained: Array = results.keys().filter(func(id): return results[id][0].status == "applied" \
		and results[id][0].applied_tick >= tick - Journal.WINDOW)
	retained.sort()
	var expected: Array = retained.slice(maxi(0, retained.size() - 16)).map(func(id): return {"id": id,
		"kind": results[id][0].kind, "requested_tick": results[id][0].requested_tick, "applied_tick": results[id][0].applied_tick})
	if journal.stats().bound and conf != expected: conf_bad.append(["mismatch", tick, conf.size(), expected.size()])
	if not conf.is_empty():
		conf[0].applied_tick = -99; conf.append({}) # J5: el arreglo devuelto es una copia
		if journal.stats().bound and journal.confirmations() != expected: conf_bad.append(["copy", tick])
	if mode == "journal" and tick in [20, 21, 90, 91]:
		rows["frame_%d" % tick] = adapter.recorded_frame(tick).get("action", {}).duplicate(true)
	if hook_after.has(tick): hook_after[tick].call()

# ------------------------------------------------------------------ guion por modo

func between(now: int) -> void:
	match mode:
		"journal": between_journal(now)
		"journal_close", "journal_inflight", "journal_capture": between_short(now)

func between_journal(now: int) -> void:
	var nt := now + 1
	if now >= 1 and now <= 300 and ids_by_tick.has(now):
		# J2: duplicado de la accion recien resuelta (aplicada o negada) devuelve el resultado guardado.
		var prev: int = ids_by_tick[now]
		var d: Dictionary = journal.request(PEER, actions[prev].duplicate(true))
		check("J2_terminal_dup_%d" % now, results.has(prev) and d == results[prev][0])
		if now in [31, 32, 33, 34]: conflicts("J3_terminal_%d" % now, actions[prev])
	if now < 300:
		var a := act(nt, ok_kind(held))
		if nt % 10 == 0: policy_rules[a.id] = "deny"
		var special := {50: "int", 60: "null", 70: "stringname", 80: "array", 90: "mutate", 91: "mutate"}
		if special.has(nt): policy_rules[a.id] = special[nt]
		if nt == 91: a.impulse = Vector3(0.5, 1.0, 0.0) if a.kind == "release" else Vector3.ZERO
		if nt == 15: atomic("J4_wrong_peer", a, "invalid_peer", 8)
		var st := req(a)
		check("J1_scheduled_%d" % nt, st.get("status") == "scheduled" and st.scheduled_tick == nt and st.requested_tick == nt)
		var d2: Dictionary = journal.request(PEER, a.duplicate(true))
		check("J2_pending_dup_%d" % nt, d2.get("status") == "scheduled" and d2.get("scheduled_tick") == nt)
		d2.status = "forged"
		check("J5_returned_copy_%d" % nt, journal.request(PEER, a).get("status") == "scheduled")
		if nt in [11, 12, 13, 14]: conflicts("J3_pending_%d" % nt, a)
		if nt in [20, 21]:
			a.impulse = Vector3(7, 0, 0); a.anchor = Vector3(0.3, 0, 0) # J5: modificar el original despues del pedido
		return
	match now:
		300:
			var bad := act(301, "grab" if held else "release")
			check("J7_scheduled", req(bad).get("status") == "scheduled"); rows.j7 = bad.id
		301:
			var a8 := act(308, ok_kind(held)); check("J8_scheduled", req(a8).get("status") == "scheduled"); rows.j8 = a8.id
		306: policy_rules[rows.j8] = "revoked"
		309:
			var a9 := act(316, ok_kind(held)); check("J9_scheduled", req(a9).get("status") == "scheduled"); rows.j9 = a9.id
		317:
			var a := act(326, ok_kind(held)); check("J10_A", req(a).get("status") == "scheduled")
			var b := act(322, ok_kind(not held)); atomic("J10_B_order", b, "action_order")
			var c := act(327, ok_kind(not held)); check("J10_C", req(c).get("status") == "scheduled")
			rows.j10 = [a.id, b.id, c.id]
		328:
			atomic("J11_minus_121", act(now - 121, ok_kind(held), next_id + 1), "action_tick_window")
			atomic("J11_plus_121", act(now + 121, ok_kind(held), next_id + 1), "action_tick_window")
			var w := act(now + 120, ok_kind(held)); var st := req(w)
			check("J11_plus_120", st.get("status") == "scheduled" and st.scheduled_tick == now + 120); rows.j11 = w.id
			atomic("J11_blocked_plus_5", act(now + 5, ok_kind(not held), next_id + 1), "action_order")
		449:
			var l := act(now - 120, ok_kind(held)); var st := req(l)
			check("J12_late_scheduled", st.get("status") == "scheduled" and st.scheduled_tick == now + 1 and st.requested_tick == now - 120)
			rows.j12 = l.id
			atomic("J12_second_late_same_tick", act(now - 60, ok_kind(not held), next_id + 1), "action_capacity")
		451:
			var b1 := snap(); var ok1: bool = journal.before_capture(now); var e1: String = journal.last_error
			check("J13_between_ticks_now", not ok1 and e1 == "execution_phase" and snap() == b1)
			var b2 := snap(); var ok2: bool = journal.before_capture(now + 1); var e2: String = journal.last_error
			check("J13_between_ticks_next", not ok2 and e2 == "execution_phase" and snap() == b2)
			var a := act(453, ok_kind(held)); check("J13_scheduled", req(a).get("status") == "scheduled"); rows.j13 = a.id
			double_prepare[453] = true
			hook_after[453] = func():
				var b3 := snap(); var ok3: bool = journal.before_capture(clock.tick)
				rows.j13_in_finished = {"ok": ok3, "error": journal.last_error, "atomic": snap() == b3}
		454:
			var a := act(456, ok_kind(held)); check("J14_scheduled", req(a).get("status") == "scheduled"); rows.j14 = a.id
			skip_prepare[456] = true
		458:
			var k := held
			var j15: Array = []
			for i in range(1, 121):
				var a := act(now + i, ok_kind(k)); var st := req(a)
				check("J15_scheduled_%d" % i, st.get("status") == "scheduled" and st.scheduled_tick == now + i)
				j15.append(a.id); k = not k
			rows.j15 = j15; rows.j15_records_after_scheduling = journal.stats().records
		580: extremes(now)
		583:
			var mx := act(585, ok_kind(held), 0x7FFFFFFF); var st := req(mx)
			check("J19_max_scheduled", st.get("status") == "scheduled")
			atomic("J19_after_max", act(586, ok_kind(not held), 0x7FFFFFFE), "nonmonotonic_action_id")
	if now >= 329 and now <= 447:
		# J11: bloqueo medido mientras espera la de +120 (id sin consumir).
		var st2: Dictionary = journal.request(PEER, act(now + 1, ok_kind(held), next_id + 1))
		blocked.tries += 1
		if st2.get("reason", "") == "action_order": blocked.action_order += 1
		else: blocked.other.append([now, st2])

func conflicts(prefix: String, a: Dictionary) -> void:
	var variants := {"kind": "grab" if a.kind == "release" else "release", "tick": a.tick + 1,
		"anchor": Vector3(0.2, 0, 0), "impulse": Vector3(0, 3, 0)}
	for k in variants:
		var v := a.duplicate(true); v[k] = variants[k]
		atomic("%s_%s" % [prefix, k], v, "action_identity_conflict")

func extremes(now: int) -> void:
	var t := now + 2
	var base := act(t, ok_kind(held), next_id + 1)
	var cases := {"id_0": {"id": 0}, "id_minus_1": {"id": -1}, "id_0x80000000": {"id": 0x80000000}, "id_float": {"id": float(next_id + 1)},
		"tick_minus_1": {"tick": -1}, "tick_0x80000000": {"tick": 0x80000000}, "kind_throw": {"kind": "throw"},
		"anchor_1_01": {"anchor": Vector3(1.01, 0, 0)}, "impulse_100_01": {"impulse": Vector3(100.01, 0, 0)},
		"anchor_nan": {"anchor": Vector3(NAN, 0, 0)}}
	for name in cases:
		var v := base.duplicate(true)
		for k in cases[name]: v[k] = cases[name][k]
		atomic("J16_" + name, v, "invalid_action")
	var missing := base.duplicate(true); missing.erase("impulse"); atomic("J16_missing_key", missing, "invalid_action")
	var extra := base.duplicate(true); extra.extra = 1; atomic("J16_extra_key", extra, "invalid_action")
	# J17
	var stats: Dictionary = journal.stats()
	atomic("J17_retired_retry", actions[ids_by_tick[5]].duplicate(true), "retired_action")
	var below := unused_between(1, stats.retired_id)
	var above := unused_between(stats.retired_id + 1, stats.max_id)
	atomic("J17_gap_below_watermark", act(t, ok_kind(held), below), "retired_action")
	atomic("J17_gap_above_watermark", act(t, ok_kind(held), above), "nonmonotonic_action_id")
	rows.j17 = {"watermark": stats.retired_id, "max": stats.max_id, "below": below, "above": above}
	# J18: rechazado antes del registro no consume el id
	var x := act(now + 121, ok_kind(held))
	var r1: Dictionary = journal.request(PEER, x)
	x.tick = t
	var r2 := req(x)
	rows.j18 = {"first": r1, "second": r2}

func unused_between(lo: int, hi: int) -> int:
	var used := actions.keys()
	for id in range(maxi(lo, 1), hi + 1):
		if not used.has(id): return id
	return -1

func between_short(now: int) -> void:
	if now == 2:
		var g := act(3, "grab"); check("S_grab_scheduled", req(g).get("status") == "scheduled")
	if now == 4:
		var r := act(6 if mode != "journal_close" else 14, "release", -1, Vector3(0, 2, 0))
		var g2 := act(9 if mode != "journal_close" else 20, "grab")
		check("S_release_scheduled", req(r).get("status") == "scheduled")
		check("S_future_scheduled", req(g2).get("status") == "scheduled")
		rows.short_ids = [r.id, g2.id]
		if mode == "journal_inflight": stop_inflight_at = 6
		if mode == "journal_capture": skip_capture[6] = true
	if now == 9 and mode == "journal_close":
		rows.held_before_stop = adapter.world.sample(2, 1).held
		journal.stop("closed")
		var n := results.size(); journal.stop("closed_again")
		rows.second_stop_silent = results.size() == n

# ------------------------------------------------------------------ comprobaciones finales

func finish_checks() -> void:
	# Invariantes globales
	var registered := actions.keys()
	check("G_one_result_per_registered", registered.all(func(id): return results.has(id) and results[id].size() == 1) \
		and results.keys().all(func(id): return actions.has(id)))
	var applied := registered.filter(func(id): return results.has(id) and results[id][0].status == "applied")
	var not_applied := registered.filter(func(id): return not applied.has(id))
	var inflight_exception: Array = rows.get("short_ids", []).slice(0, 1) if mode == "journal_inflight" else []
	check("G_effects_only_applied", applied.all(func(id): return effects.get(id, 0) == 1) \
		and not_applied.filter(func(id): return not inflight_exception.has(id)).all(func(id): return not effects.has(id)))
	check("G_confirmations_ok", conf_bad.is_empty())
	info.counts = {"registered": registered.size(), "applied": applied.size(), "not_applied": not_applied.size(),
		"policy_called_ids": policy_calls.size()}
	info.mem = mem; info.blocked = blocked; info.conf_bad = conf_bad.slice(0, 5)
	info.statuses = {}
	for id in results:
		var key: String = results[id][0].status + ":" + results[id][0].reason
		info.statuses[key] = info.statuses.get(key, 0) + 1
	match mode:
		"journal": checks_journal(applied)
		"journal_close":
			var ids: Array = rows.short_ids
			check("C_both_cancelled_closed", ids.all(func(id): return results.has(id) and results[id].size() == 1 \
				and results[id][0].status == "cancelled" and results[id][0].reason == "closed"))
			check("C_second_stop_silent", rows.get("second_stop_silent", false))
			check("C_still_held_after_close", rows.get("held_before_stop", false) and adapter.world.sample(2, 1).held)
			check("C_not_bound", journal.request(PEER, act(clock.tick + 1, "release")).get("reason") == "not_bound" \
				and prepare_log.get(clock.tick, [true, ""])[1] == "not_bound")
			check("C_no_effects", ids.all(func(id): return not effects.has(id)))
		"journal_inflight":
			var r: int = rows.short_ids[0]
			rows.inflight = {"result": results.get(r, []), "effect": effects.get(r, 0), "held_after": adapter.world.sample(2, 1).held,
				"in_confirmations": journal.confirmations().any(func(c): return c.id == r), "queued_at_stop": rows.get("inflight_queued", {})}
			check("I_cancelled_once_without_ack", results.has(r) and results[r].size() == 1 and results[r][0].status == "cancelled" \
				and not rows.inflight.in_confirmations)
		"journal_capture":
			var ids2: Array = rows.short_ids
			check("K_both_cancelled_once", ids2.all(func(id): return results.has(id) and results[id].size() == 1 and results[id][0].status == "cancelled"))
			check("K_no_effects", ids2.all(func(id): return not effects.has(id)))
			check("K_world_stopped_before_step", adapter.world.get_tick() == 5 and not adapter.ready_for_input)
			check("K_journal_closed", not journal.stats().bound and journal.request(PEER, act(clock.tick + 1, "grab")).get("reason") == "not_bound")
			rows.capture_reasons = ids2.map(func(id): return results.get(id, [{}])[0].get("reason", ""))

func res(id: int) -> Dictionary:
	return results.get(id, [{}])[0]

func checks_journal(applied: Array) -> void:
	# J1
	var j1 := range(1, 301)
	var deny_ok := j1.filter(func(t): return t % 10 == 0).all(func(t): return res(ids_by_tick[t]).status == "rejected" \
		and res(ids_by_tick[t]).reason == "denied" and not effects.has(ids_by_tick[t]))
	check("J1_denied_every_10", deny_ok)
	var plain := j1.filter(func(t): return t % 10 != 0 and not t in [50, 60, 70, 80])
	check("J1_applied_at_requested_tick", plain.all(func(t): return res(ids_by_tick[t]).status == "applied" and res(ids_by_tick[t]).applied_tick == t))
	check("J1_records_bounded", mem.w1 <= 123 and mem.w2 <= 123 and mem.w2 <= mem.w1)
	# J5 originales modificados despues del pedido y politica que modifica su copia
	for t in [20, 21, 90, 91]:
		var o: Dictionary = actions[ids_by_tick[t]]
		var fa: Dictionary = rows.get("frame_%d" % t, {})
		var same: bool = not fa.is_empty() and fa.id == o.id and fa.kind == o.kind and fa.anchor == o.anchor and fa.impulse == o.impulse and fa.tick == t
		check("J5_executed_original_%d" % t, same and res(o.id).status == "applied")
	# J6
	for t in [50, 60, 70, 80]:
		check("J6_invalid_type_%d" % t, res(ids_by_tick[t]).status == "rejected" and res(ids_by_tick[t]).reason == "invalid_policy_result" and not effects.has(ids_by_tick[t]))
	var called_ok := true
	for id in policy_calls:
		var calls: Array = policy_calls[id]
		var sched: int = res(id).get("scheduled_tick", -1)
		if calls.size() != 1 or calls[0].tick != sched or calls[0].clock != sched or calls[0].world != sched - 1 or calls[0].peer != PEER: called_ok = false
	check("J6_policy_once_at_real_tick", called_ok)
	# J7
	check("J7_invalid_transition", res(rows.j7).status == "rejected" and res(rows.j7).reason == "invalid_hand_transition" \
		and not policy_calls.has(rows.j7) and not effects.has(rows.j7))
	# J8, J9, J10
	check("J8_revoked_at_execution", res(rows.j8).status == "rejected" and res(rows.j8).reason == "revoked" and res(rows.j8).scheduled_tick == 308 \
		and policy_calls.get(rows.j8, []).size() == 1 and not effects.has(rows.j8))
	check("J9_future_applied_on_tick", res(rows.j9).status == "applied" and res(rows.j9).applied_tick == 316)
	check("J10_A_C_applied", res(rows.j10[0]).applied_tick == 326 and res(rows.j10[2]).applied_tick == 327 and not results.has(rows.j10[1]))
	# J11, J12
	check("J11_plus_120_applied", res(rows.j11).status == "applied" and res(rows.j11).applied_tick == 448)
	check("J12_late_result", res(rows.j12).status == "applied" and res(rows.j12).requested_tick == 329 and res(rows.j12).applied_tick == 450)
	# J13
	check("J13_double_prepare", rows.has("double_prepare") and not rows.double_prepare.ok and rows.double_prepare.error == "execution_phase" and rows.double_prepare.atomic)
	check("J13_in_tick_finished", rows.has("j13_in_finished") and not rows.j13_in_finished.ok and rows.j13_in_finished.error == "execution_phase" and rows.j13_in_finished.atomic)
	check("J13_applied_once", res(rows.j13).status == "applied" and res(rows.j13).applied_tick == 453 and effects.get(rows.j13, 0) == 1)
	# J14
	check("J14_missed", res(rows.j14).status == "cancelled" and res(rows.j14).reason == "execution_tick_missed" and not effects.has(rows.j14) \
		and not policy_calls.has(rows.j14))
	# J15
	var j15: Array = rows.j15
	check("J15_all_applied_on_tick", j15.size() == 120 and range(120).all(func(i): return res(j15[i]).status == "applied" and res(j15[i]).applied_tick == 459 + i))
	# J18, J19
	check("J18_unconsumed_id_reused", rows.j18.first.get("reason") == "action_tick_window" and rows.j18.second.get("status") == "scheduled")
	check("J19_max_applied", res(0x7FFFFFFF).status == "applied" and res(0x7FFFFFFF).applied_tick == 585)
	check("J_no_policy_call_for_invalid_requests", not policy_calls.keys().any(func(id): return not actions.has(id)))
	rows.j15_max_records = mem.all
