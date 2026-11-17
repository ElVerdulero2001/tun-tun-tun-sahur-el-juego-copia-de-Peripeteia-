extends Node
## Validacion independiente (Claude), entrega 15, parte E: action_expired. Un proceso, ticks
## manuales de SimClock, ActorMotor y la extension reales (fixture propio, como cv14_local).
## No cambia ningun modulo de Codex: solo llama su API publica y lee su estado.
const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const History = preload("res://prototypes/objetos_adaptador/history_bridge.gd")
const ACTOR = preload("res://scenes/actor/actor.tscn")
const LAST := 600
const D120 := {221: 101, 227: 107}
const D121 := {224: 103, 230: 109}
const LATE := {253: 103, 303: 103}

var result_path := ""
var checks: Array = []
var info := {}
var actor: ActorBody
var clock: SimClock
var tuning: ActorTuning
var adapter
var history
var prediction := ClientPrediction.new()
var revision := 0
var local_input: ActorInput
var next_id := 0
var lcg := 20261118
var expect_held := false
var ids := {}            # tick -> id
var orig := {}           # id -> {tick, kind}
var queue_rejected: Array = []
var effects := {}
var confirms := {}
var expiries: Array = []
var expiry_count_by_id := {}
var deliveries: Array = []
var ckpt := {}
var mem := {"w1": [0, 0, 0, 0], "w2": [0, 0, 0, 0]}
var cancelled_id := -1

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
	SimClock.clear_world_slow()
	tuning = ActorTuning.new(); add_child(tuning)
	var actors := Node3D.new(); add_child(actors)
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(12, 0.2, 12)
	shape.shape = box; floor_body.add_child(shape); add_child(floor_body); floor_body.position.y = -0.1
	actor = ACTOR.instantiate(); actor.owner_peer_id = 1; actor.state.position = Vector3(0, 0.02, 1.5); actors.add_child(actor)
	clock = SimClock.new(); clock.actors_root = actors; clock.tuning = tuning
	clock.paused = true; add_child(clock); clock.set_physics_process(false)
	clock.input_provider = provide
	adapter = Adapter.new(); add_child(adapter)
	check("setup_adapter", adapter.start(clock, actor, tuning, make_world, 2, 1, 1))
	history = History.new(); add_child(history)
	check("setup_history", history.start(adapter, prediction, step_actor))
	history.effect_ready.connect(func(id: int, _k: String): effects[id] = effects.get(id, 0) + 1)
	history.action_confirmed.connect(func(id: int, _k: String, _r: int, _a: int): confirms[id] = confirms.get(id, 0) + 1)
	history.action_expired.connect(on_expired)
	clock.tick_started.connect(tick_started)
	clock.tick_finished.connect(after_tick)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var t0 := Time.get_ticks_msec()
	for _i in LAST: clock._run_tick()
	evaluate()
	info.ms = Time.get_ticks_msec() - t0
	var failures := checks.filter(func(c): return not c.passed).size()
	var result := {"mode": "expiry", "status": "PASSED" if failures == 0 else "FAILED", "failures": failures,
		"checks": checks, "info": info, "adapter_error": adapter.last_error, "history_error": history.last_error,
		"clock_tick": clock.tick, "native_tick": adapter.world.get_tick(), "scope": "local_manual_ticks"}
	if not result_path.is_empty(): FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(result))
	print(JSON.stringify({"mode": "expiry", "status": result.status, "failures": failures, "checks": checks.size()}))
	get_tree().quit(0 if failures == 0 else 1)

func make_world():
	var w = ClassDB.instantiate("SahurObjectWorld")
	w.add_box(1, 1, Vector3(12, 0.2, 12), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)))
	w.add_box(2, 1, Vector3(0.5, 0.4, 0.5), 2.0, Transform3D(Basis.IDENTITY, Vector3(0, 0.7, -0.3)))
	w.seal_topology(1)
	return w

func step_actor(input: ActorInput) -> void:
	ActorMotor.step(actor, actor.state, input, tuning, SimClock.world_dt(input.tick))

func check(id: String, passed: bool) -> void:
	checks.append({"id": id, "passed": passed})
	if not passed: push_error("CHECK_FAILED: " + id)

func gap() -> int:
	lcg = (lcg * 1103515245 + 12345) % 2147483648
	return 1 + (lcg >> 16) % 9

func envelope(at_tick: int, snapshot: PackedByteArray, acks: Array) -> Dictionary:
	revision += 1
	var p: Dictionary = adapter.authority_scope()
	p.version = 1; p.revision = revision; p.tick = at_tick; p.snapshot = snapshot; p.acks = acks
	return p

func ack_of(t: int) -> Dictionary:
	var id: int = ids[t]
	return {"id": id, "kind": orig[id].kind, "requested_tick": t, "applied_tick": t}

func queue(tick: int) -> void:
	var kind := "release" if expect_held else "grab"
	next_id += gap()
	var st: Dictionary = history.queue_action(tick, next_id, kind)
	if st.status == "queued":
		ids[tick] = next_id; orig[next_id] = {"tick": tick, "kind": kind}; expect_held = not expect_held
	else:
		queue_rejected.append([tick, st])

func provide(_who: ActorBody, tick: int) -> ActorInput:
	var input := ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion.IDENTITY)
	if tick <= 400: queue(tick)
	if tick != 470: check("capture_%d" % tick, history.capture_input(input))  # 470: falta de captura (E9)
	local_input = input
	return input

func on_expired(id: int, kind: String, requested_tick: int) -> void:
	var ev := {"id": id, "kind": kind, "tick": requested_tick, "clock": clock.tick, "ready": adapter.ready_for_input}
	ev.clean = not history._known_actions.has(id) and not history._effects.has(id) \
		and not history._confirmed.has(id) and adapter.is_retired_action(id)
	var active_before: int = adapter.action_stats().active
	var st: Dictionary = history.queue_action(requested_tick, id, kind) # reentrada desde el callback
	ev.reentry = str(st.get("status", "")) + ":" + str(st.get("reason", ""))
	ev.reentry_atomic = adapter.action_stats().active == active_before
	expiries.append(ev)
	expiry_count_by_id[id] = expiry_count_by_id.get(id, 0) + 1

func tick_started(tick: int) -> void:
	if tick == 310:
		var before := expiries.size()
		var st := ActorState.from_bytes(prediction._states[306])
		st.position.x += 0.15
		var c0 := prediction.corrections
		var ok: bool = history.reconcile_actor(306, st.to_bytes(), 306, 310)
		check("E10_actor_correction", ok and prediction.corrections == c0 + 1 and not adapter.ready_for_input)
		check("E10_no_expiry_inside_correction_replay", expiries.size() == before)

func deliver(at: int, snap: PackedByteArray, acks: Array, label: String) -> bool:
	var before := expiries.size()
	var ok: bool = history.apply_authority_trusted(envelope(at, snap, acks))
	deliveries.append({"label": label, "clock": clock.tick, "tick": at, "ok": ok, "error": history.last_error,
		"new_expiries": expiries.size() - before})
	return ok

func after_tick(tick: int) -> void:
	prediction.record(tick, local_input, actor.state)
	var st: Dictionary = adapter.action_stats()
	var m := [st.active, history._known_actions.size(), history._effects.size(), history._confirmed.size()]
	for i in 4:
		if tick >= 130 and tick < 300: mem.w1[i] = maxi(mem.w1[i], m[i])
		if tick >= 300: mem.w2[i] = maxi(mem.w2[i], m[i])
	if tick in [276, 306]: ckpt[tick] = adapter.world.snapshot_trusted()
	if tick <= 270 and tick % 3 == 0 and ids.has(tick):
		check("C_confirm_%d" % tick, deliver(tick, adapter.world.snapshot_trusted(), [ack_of(tick)], "C"))
	if D120.has(tick): check("E4_d120_accepted", deliver(tick, adapter.world.snapshot_trusted(), [ack_of(D120[tick])], "d120"))
	if D121.has(tick): check("E5_d121_accepted", deliver(tick, adapter.world.snapshot_trusted(), [ack_of(D121[tick])], "d121"))
	if LATE.has(tick): check("E6_late_accepted", deliver(tick, adapter.world.snapshot_trusted(), [ack_of(LATE[tick])], "late"))
	if tick == 300:
		var expected := var_to_bytes(adapter.world.samples())
		var e0 := effects.duplicate()
		check("E10_positive_replay", deliver(276, ckpt[276], [], "replay24"))
		check("E10_replay_exact", var_to_bytes(adapter.world.samples()) == expected and effects == e0)
	if tick == 310:
		var e1 := effects.duplicate()
		check("E10_recovery_after_correction", deliver(306, ckpt[306], [], "recovery") and adapter.ready_for_input)
		check("E10_recovery_no_new_effects", effects == e1)
	if tick == 429:
		var kind := "release" if expect_held else "grab"
		next_id += gap()
		var q: Dictionary = history.queue_action(431, next_id, kind)
		check("E8_queued_before_suspension", q.status == "queued")
		if q.status == "queued": cancelled_id = next_id; orig[next_id] = {"tick": 431, "kind": kind}
	if tick == 430:
		adapter.invalidate_history_from(430, "actor")
		check("E8_suspended", not adapter.ready_for_input)

func evaluate() -> void:
	var confirmed_ids := confirms.keys()
	var known: Array = orig.keys()
	var expected := known.filter(func(id): return not confirms.has(id) and orig[id].tick + 121 <= LAST)
	var got := expiries.map(func(e): return e.id)
	var bad_identity := expiries.filter(func(e): return not orig.has(e.id) or orig[e.id].kind != e.kind or orig[e.id].tick != e.tick)
	var bad_time := expiries.filter(func(e): return e.clock != e.tick + 121)
	check("E1_identity", bad_identity.is_empty())
	check("E1_at_T_plus_121", bad_time.is_empty())
	check("E2_once", expiry_count_by_id.values().all(func(v): return v == 1))
	var exp_sorted := expected.duplicate(); exp_sorted.sort()
	var got_sorted := got.duplicate(); got_sorted.sort()
	check("E3_exact_set", exp_sorted == got_sorted)
	for t in D120.values(): check("E4_d120_confirmed_not_expired_%d" % t, confirms.get(ids[t], 0) == 1 and not expiry_count_by_id.has(ids[t]))
	for t in D121.values():
		check("E5_d121_expired_not_confirmed_%d" % t, expiry_count_by_id.get(ids[t], 0) == 1 and not confirms.has(ids[t]))
	var d121_rows := deliveries.filter(func(d): return d.label == "d121")
	check("E5_expiry_before_ack_same_tick", d121_rows.all(func(d): return d.new_expiries == 0) \
		and D121.keys().all(func(c): return expiries.any(func(e): return e.id == ids[D121[c]] and e.clock == c)))
	check("E6_late_no_confirm_no_second", not confirms.has(ids[103]) and expiry_count_by_id.get(ids[103], 0) == 1 \
		and deliveries.filter(func(d): return d.label == "late").all(func(d): return d.ok and d.new_expiries == 0))
	var c_ids := ids.keys().filter(func(t): return t <= 270 and t % 3 == 0).map(func(t): return ids[t])
	check("E7_confirmed_never_expire", c_ids.all(func(id): return confirms.get(id, 0) == 1 and not expiry_count_by_id.has(id)))
	check("E8_cancelled_expires_with_identity", cancelled_id > 0 and expiries.any(func(e): return e.id == cancelled_id and e.clock == 552 and e.tick == 431))
	check("E8_cancelled_no_effect", cancelled_id > 0 and not effects.has(cancelled_id))
	check("E9_missing_capture_tick_still_expires", ids.has(349) and expiries.any(func(e): return e.id == ids[349] and e.clock == 470))
	check("E10_no_expiry_in_authority_calls", deliveries.all(func(d): return d.new_expiries == 0))
	check("E11_clean_before_callback", expiries.all(func(e): return e.clean))
	var ready_rows := expiries.filter(func(e): return e.ready)
	check("E11_reentry_retired_when_ready", not ready_rows.is_empty() and ready_rows.all(func(e): return e.reentry == "rejected:retired_action" and e.reentry_atomic))
	for i in 4: check("E12_bounded_%d" % i, mem.w1[i] <= 123 and mem.w2[i] <= 123)
	for i in 4: check("E12_no_growth_%d" % i, mem.w2[i] <= mem.w1[i])
	var executed := ids.values()
	check("E13_one_effect_per_executed", executed.all(func(id): return effects.get(id, 0) == 1) and effects.keys().all(func(id): return executed.has(id)))
	var reentry_kinds := {}
	for e in expiries: reentry_kinds[e.reentry] = reentry_kinds.get(e.reentry, 0) + 1
	info.expiries = expiries.size(); info.expected = expected.size(); info.confirmed = confirmed_ids.size()
	info.known = known.size(); info.queue_rejected = queue_rejected; info.mem = mem
	info.deliveries = deliveries.filter(func(d): return d.label != "C")
	info.c_deliveries = deliveries.filter(func(d): return d.label == "C").size()
	info.c_delivery_failures = deliveries.filter(func(d): return d.label == "C" and not d.ok).size()
	info.reentry = reentry_kinds
	info.samples = expiries.filter(func(e): return e.clock in [222, 224, 230, 310, 470, 552] or e.tick in [103, 109])
	info.cancelled_id = cancelled_id
	info.final_stats = adapter.action_stats()
	info.history_sizes = [history._known_actions.size(), history._effects.size(), history._confirmed.size()]
