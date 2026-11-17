extends Node
## Validacion independiente (Claude), entrega 14. Un proceso, ticks manuales de SimClock,
## ActorMotor y la extension reales, como el fixture de 900 acciones de Codex (sin usarlo).
## Modos: actions (parte A de los criterios) y bridge (parte P, con un canal de prueba).
## No cambia ningun modulo de Codex: solo llama su API publica y lee su estado.
const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const History = preload("res://prototypes/objetos_adaptador/history_bridge.gd")
const NetworkBridge = preload("res://prototypes/objetos_adaptador/scene_network_bridge.gd")
const ACTOR = preload("res://scenes/actor/actor.tscn")

## seam_: reemplaza SOLO el transporte. Entrega un sobre por llamada, cuando el instrumento quiere.
class StubChannel extends Node:
	signal closed
	var next := {}
	var bound := true
	var takes := 0
	func take_packet() -> Dictionary:
		takes += 1
		var p := next
		next = {}
		return p
	func stats() -> Dictionary:
		return {"bound": bound}
	func close() -> void:
		bound = false
		next = {}
		closed.emit()

var mode := "actions"
var result_path := ""
var checks: Array = []
var info := {}
var bodies := 2
var actor: ActorBody
var clock: SimClock
var tuning: ActorTuning
var adapter
var history
var prediction := ClientPrediction.new()
var revision := 0
var local_input: ActorInput

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
	bodies = 3 if mode == "bridge" else 2
	SimClock.clear_world_slow()
	tuning = ActorTuning.new(); add_child(tuning)
	var actors := Node3D.new(); add_child(actors)
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(12, 0.2, 12)
	shape.shape = box; floor_body.add_child(shape); add_child(floor_body); floor_body.position.y = -0.1
	actor = ACTOR.instantiate(); actor.owner_peer_id = 1; actor.state.position = Vector3(0, 0.02, 1.5); actors.add_child(actor)
	clock = SimClock.new(); clock.actors_root = actors; clock.tuning = tuning
	clock.paused = true; add_child(clock); clock.set_physics_process(false)
	clock.input_provider = provide_actions if mode == "actions" else provide_bridge
	adapter = Adapter.new(); add_child(adapter)
	check("setup_adapter", adapter.start(clock, actor, tuning, make_world, 2, 1, 1))
	history = History.new(); add_child(history)
	check("setup_history", history.start(adapter, prediction, step_actor))
	# Jolt instala el actor y el piso antes de las primeras consultas.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var t0 := Time.get_ticks_msec()
	if mode == "actions": run_actions()
	elif mode == "bridge": run_bridge()
	else: check("unknown_mode", false)
	info.ms = Time.get_ticks_msec() - t0
	var failures := checks.filter(func(c): return not c.passed).size()
	var result := {"mode": mode, "status": "PASSED" if failures == 0 else "FAILED", "failures": failures,
		"checks": checks, "info": info, "adapter_error": adapter.last_error, "history_error": history.last_error,
		"clock_tick": clock.tick, "native_tick": adapter.world.get_tick(), "scope": "local_manual_ticks"}
	if not result_path.is_empty(): FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(result))
	print(JSON.stringify({"mode": mode, "status": result.status, "failures": failures, "checks": checks.size()}))
	get_tree().quit(0 if failures == 0 else 1)

func make_world():
	var w = ClassDB.instantiate("SahurObjectWorld")
	w.add_box(1, 1, Vector3(12, 0.2, 12), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)))
	w.add_box(2, 1, Vector3(0.5, 0.4, 0.5), 2.0, Transform3D(Basis.IDENTITY, Vector3(0, 0.7, -0.3)))
	if bodies == 3:
		w.add_box(3, 1, Vector3(0.4, 0.4, 0.4), 1.0, Transform3D(Basis.IDENTITY, Vector3(0.6, 0.2, -1.2)))
	w.seal_topology(1)
	return w

func step_actor(input: ActorInput) -> void:
	ActorMotor.step(actor, actor.state, input, tuning, SimClock.world_dt(input.tick))

func check(id: String, passed: bool) -> void:
	checks.append({"id": id, "passed": passed})
	if not passed: push_error("CHECK_FAILED: " + id)

func world_hash(w) -> String:
	return var_to_bytes(w.samples()).hex_encode().sha256_text()

func envelope(at_tick: int, snapshot: PackedByteArray, acks: Array) -> Dictionary:
	revision += 1
	var p: Dictionary = adapter.authority_scope()
	p.version = 1; p.revision = revision; p.tick = at_tick; p.snapshot = snapshot; p.acks = acks
	return p

# ---------------------------------------------------------------- parte A: acciones

var ids := {}            # tick -> id
var kinds := {}          # tick -> kind
var next_id := 0
var lcg := 20261117
var effects := {}        # id -> veces
var confirms := {}       # id -> veces
var effects_total := 0
var suspended := false
var ref                  # mundo de referencia durante la suspension
var ref_840 := PackedByteArray()
var ckpt := {}
var mem_max := {"w1": [0, 0, 0, 0, 0], "w2": [0, 0, 0, 0, 0], "all": [0, 0, 0, 0, 0]}
var last_watermark := 0
var a3_rows: Array = []
var a4_rows: Array = []
var a5_rows: Array = []
var a6_rows: Array = []
var susp_status := {}
var a1_queued := 0
var a1_bad: Array = []
var retire_tick_bad := 0

const A3_PLAN := {201: 201, 227: 203, 324: 205, 327: 207, 330: 209, 333: 211, 413: 213}
const A4_TICK := 241
const A4_AT := [241, 242, 250, 290, 361, 362, 490]

func want_action(tick: int) -> bool:
	return (tick >= 1 and tick <= 700) or (tick >= 701 and tick <= 850) or (tick >= 851 and tick <= 880)

func gap() -> int:
	lcg = (lcg * 1103515245 + 12345) % 2147483648
	return 1 + (lcg >> 16) % 9

func provide_actions(_who: ActorBody, tick: int) -> ActorInput:
	var input := ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion.IDENTITY)
	if want_action(tick):
		var kind := "grab" if tick % 2 == 1 else "release"
		next_id += gap()
		var st: Dictionary = history.queue_action(tick, next_id, kind)
		if tick >= 701 and tick <= 850:
			var key: String = st.status + ":" + str(st.get("reason", ""))
			susp_status[key] = susp_status.get(key, 0) + 1
		elif st.status == "queued":
			ids[tick] = next_id; kinds[tick] = kind; a1_queued += 1
		else:
			a1_bad.append([tick, st])
	check("capture_%d" % tick, history.capture_input(input))
	return input

func ack_of(t: int) -> Dictionary:
	return {"id": ids[t], "kind": kinds[t], "requested_tick": t, "applied_tick": t}

func run_actions() -> void:
	history.effect_ready.connect(func(id: int, _k: String):
		effects[id] = effects.get(id, 0) + 1; effects_total += 1)
	history.action_confirmed.connect(func(id: int, _k: String, _r: int, _a: int):
		confirms[id] = confirms.get(id, 0) + 1)
	clock.tick_finished.connect(after_actions)
	for _i in 884:
		clock._run_tick()
	# A1 / A9c / A10
	check("A1_all_queued_1_700", a1_bad.filter(func(r): return r[0] <= 700).is_empty() and ids.keys().filter(func(t): return t <= 700).size() == 700)
	var multi := effects.keys().filter(func(id): return effects[id] != 1)
	check("A1_one_effect_per_id", multi.is_empty())
	var missing := ids.keys().filter(func(t): return effects.get(ids[t], 0) != 1)
	check("A1_every_queued_action_has_effect", missing.is_empty())
	check("A1_no_action_capacity", a1_bad.filter(func(r): return str(r[1]).contains("action_capacity")).is_empty())
	check("A9c_new_actions_after_suspension", ids.keys().filter(func(t): return t >= 851 and t <= 880).size() == 30)
	info.a1 = {"queued": a1_queued, "bad": a1_bad.slice(0, 10), "max_id": adapter.action_stats().max_id,
		"effects_total": effects_total, "distinct_effect_ids": effects.size(), "multi": multi.slice(0, 10), "missing": missing.slice(0, 10)}
	info.a2 = mem_max
	var cap := 123
	for k in ["all"]:
		for v in mem_max[k]: check("A2_bounded_%s" % k, v <= cap)
	for i in 5:
		check("A2_no_growth_%d" % i, mem_max.w2[i] <= mem_max.w1[i])
	check("A2_retired_before_tick_follows_present", retire_tick_bad == 0)
	info.a3 = a3_rows; info.a4 = a4_rows; info.a5 = a5_rows; info.a6 = a6_rows; info.a9_status = susp_status
	info.final_stats = adapter.action_stats()
	info.confirms_total = confirms.size()

func after_actions(tick: int) -> void:
	# --- A2 memoria y marca
	var st: Dictionary = adapter.action_stats()
	var mem := [st.active, history._known_actions.size(), history._effects.size(), history._confirmed.size(), history._commands.size()]
	for i in 5:
		mem_max.all[i] = maxi(mem_max.all[i], mem[i])
		if tick >= 200 and tick < 400: mem_max.w1[i] = maxi(mem_max.w1[i], mem[i])
		if tick >= 400 and tick <= 700: mem_max.w2[i] = maxi(mem_max.w2[i], mem[i])
	if tick >= 119 and st.retired_before_tick != tick - 120: retire_tick_bad += 1
	check("A2_watermark_monotonic_%d" % tick, st.retired_id >= last_watermark)
	last_watermark = st.retired_id
	if tick in [496, 536]: ckpt[tick] = adapter.world.snapshot_trusted()
	# --- A3 primera confirmacion tardia
	if A3_PLAN.has(tick):
		var t: int = A3_PLAN[tick]
		var before: int = confirms.get(ids[t], 0)
		var ok: bool = history.apply_authority_trusted(envelope(tick, adapter.world.snapshot_trusted(), [ack_of(t)]))
		var row := {"action_tick": t, "delay": tick - t, "accepted": ok, "confirmed": confirms.get(ids[t], 0) > before,
			"retired_at_delivery": adapter.is_retired_action(ids[t]), "error": history.last_error}
		a3_rows.append(row)
		check("A3_packet_accepted_d%d" % (tick - t), ok)
		check("A3_confirm_iff_d_le_120_d%d" % (tick - t), row.confirmed == (tick - t <= 120))
	# --- A4 el mismo ACK repetido
	if tick in A4_AT:
		var ok4: bool = history.apply_authority_trusted(envelope(tick, adapter.world.snapshot_trusted(), [ack_of(A4_TICK)]))
		a4_rows.append({"at": tick, "accepted": ok4, "confirms": confirms.get(ids[A4_TICK], 0), "error": history.last_error})
		check("A4_repeat_accepted_%d" % tick, ok4)
		check("A4_single_confirmation_%d" % tick, confirms.get(ids[A4_TICK], 0) == 1)
	if tick == 450: invalid_acks(tick)
	if tick == 452: silent_ack(tick, "A5i_gap_id_below_watermark")
	if tick == 454: silent_ack(tick, "A5i_retired_wrong_kind")
	if tick == 460: retries(tick)
	# --- A7 replay positivo de 24 pasos con acciones
	if tick == 520:
		var expected := var_to_bytes(adapter.world.samples())
		var e0 := effects_total; var steps0: int = adapter.replayed_steps
		var ok7: bool = history.apply_authority_trusted(envelope(496, ckpt[496], []))
		check("A7_positive_replay_accepted", ok7 and adapter.ready_for_input)
		check("A7_positive_replay_exact", var_to_bytes(adapter.world.samples()) == expected)
		check("A7_no_new_effects", effects_total == e0)
		info.a7 = {"replayed": adapter.replayed_steps - steps0, "error": history.last_error,
			"actions_in_window": range(497, 521).filter(func(t): return ids.has(t)).size()}
	# --- A8 recuperacion de 24 pasos con acciones
	if tick == 560:
		var expected8 := var_to_bytes(adapter.world.samples())
		var e8 := effects_total
		adapter.invalidate_history_from(537, "actor")
		var stopped: bool = not adapter.ready_for_input
		var ok8: bool = history.apply_authority_trusted(envelope(536, ckpt[536], []))
		check("A8_stopped_before_recovery", stopped)
		check("A8_recovery_accepted", ok8 and adapter.ready_for_input)
		check("A8_recovery_exact", var_to_bytes(adapter.world.samples()) == expected8)
		check("A8_no_new_effects", effects_total == e8)
		info.a8 = {"error": history.last_error, "actions_in_window": range(537, 561).filter(func(t): return ids.has(t)).size()}
	# --- A9 suspension de 150 ticks
	if tick == 700:
		check("A9_last_action_is_release", kinds.get(700, "") == "release")
		ref = make_world(); check("A9_reference_restore", ref.restore_trusted(adapter.world.snapshot_trusted()))
		adapter.invalidate_history_from(700, "actor")
		check("A9_suspended", not adapter.ready_for_input)
		info.a9_effects_before = effects_total
	elif tick > 700 and tick <= 850:
		ref.step(SimClock.TICK_DT)
		if tick == 840: ref_840 = ref.snapshot_trusted()
		if tick == 850:
			var s: Dictionary = adapter.action_stats()
			check("A9_no_effects_while_suspended", effects_total == info.a9_effects_before)
			check("A9_all_requests_not_ready", susp_status.keys() == ["rejected:not_ready"] and susp_status["rejected:not_ready"] == 150)
			check("A9_zero_active", s.active == 0 and history._known_actions.is_empty() and history._effects.is_empty() and history._confirmed.is_empty())
			check("A9_watermark_is_max", s.retired_id == s.max_id)
			info.a9_stats = s
			var c0 := confirms.size()
			var ok9: bool = history.apply_authority_trusted(envelope(840, ref_840, [ack_of(650), ack_of(A4_TICK)]))
			check("A9b_recovers", ok9 and adapter.ready_for_input)
			check("A9b_exact_with_reference", world_hash(adapter.world) == world_hash(ref))
			check("A9b_no_late_confirmation", confirms.size() == c0 and confirms.get(ids[A4_TICK], 0) == 1 and not confirms.has(ids[650]))
			info.a9b = {"error": history.last_error, "replayed_from": 840}
	# --- A10 id maximo
	if tick == 880:
		var st10: Dictionary = history.queue_action(882, 0x7FFFFFFF, "grab")
		check("A10_max_id_queued", st10.status == "queued")
		var after_max: Dictionary = history.queue_action(881, 0x7FFFFFFE, "grab")
		check("A10_lower_after_max_rejected", after_max.status == "rejected")
		info.a10 = {"max": st10, "after": after_max}
	if tick == 884:
		check("A10_max_id_effect_once", effects.get(0x7FFFFFFF, 0) == 1)
		var later: Dictionary = history.queue_action(885, 0x7FFFFFFE, "release")
		var over: Dictionary = history.queue_action(885, 0x80000000, "release")
		check("A10_no_wrap", later.status == "rejected" and over.status == "rejected")
		info.a10.later = later; info.a10.over = over

func atomic_snapshot() -> Array:
	return [adapter.world.snapshot_trusted(), adapter.last_authority(), confirms.duplicate(), effects_total,
		adapter.action_stats().active, adapter._queued.size(), history._known_actions.size()]

func invalid_acks(tick: int) -> void:
	var t := tick - 1
	var a := ack_of(t)
	var wrong_kind := a.duplicate(); wrong_kind.kind = "release" if a.kind == "grab" else "grab"
	var wrong_req := a.duplicate(); wrong_req.requested_tick = t - 1
	var app_lt := a.duplicate(); app_lt.applied_tick = t - 1
	var app_gt := a.duplicate(); app_gt.applied_tick = tick + 1
	var retired := ack_of(300); retired.requested_tick = 335; retired.applied_tick = 335
	var seventeen: Array = []
	for k in range(tick - 17, tick): seventeen.append(ack_of(k))
	var never := {"id": adapter.action_stats().max_id + 1, "kind": "grab", "requested_tick": t, "applied_tick": t}
	var neg := a.duplicate(); neg.id = -5
	var throw := a.duplicate(); throw.kind = "throw"
	var zero := a.duplicate(); zero.id = 0
	var cases := {"id_0": [zero], "id_above_max": [never], "active_wrong_kind": [wrong_kind],
		"active_wrong_requested": [wrong_req], "applied_lt_requested": [app_lt], "applied_gt_packet": [app_gt],
		"duplicate_in_packet": [a, a.duplicate()], "retired_requested_in_window": [retired],
		"seventeen": seventeen, "negative_id": [neg], "kind_throw": [throw]}
	for name in cases:
		var before := atomic_snapshot()
		var ok: bool = history.apply_authority_trusted(envelope(tick, adapter.world.snapshot_trusted(), cases[name]))
		var after := atomic_snapshot()
		a5_rows.append({"case": name, "accepted": ok, "error": adapter.last_error, "atomic": before == after})
		check("A5_rejected_" + name, not ok)
		check("A5_atomic_" + name, before == after)

func unused_id(lo_tick: int, hi_tick: int) -> int:
	for t in range(lo_tick + 1, hi_tick + 1):
		if ids.has(t) and ids.has(t - 1) and ids[t] - ids[t - 1] >= 2: return ids[t] - 1
	return -1

func silent_ack(tick: int, name: String) -> void:
	var acks: Array
	if name == "A5i_gap_id_below_watermark":
		acks = [{"id": unused_id(150, 300), "kind": "grab", "requested_tick": 200, "applied_tick": 200}]
	else:
		var r := ack_of(300); r.kind = "release" if r.kind == "grab" else "grab"
		acks = [r]
	var c0 := confirms.size()
	var ok: bool = history.apply_authority_trusted(envelope(tick, adapter.world.snapshot_trusted(), acks))
	a5_rows.append({"case": name, "accepted": ok, "error": adapter.last_error, "confirmed": confirms.size() != c0, "ack": acks[0]})
	check(name + "_no_callback", confirms.size() == c0)

func retries(tick: int) -> void:
	var s: Dictionary = adapter.action_stats()
	var watermark_tick := -1
	for t in ids: if ids[t] == s.retired_id: watermark_tick = t
	var above := unused_id(watermark_tick + 1, tick - 1)
	var below := unused_id(150, watermark_tick - 1)
	var flipped := "release" if kinds[tick] == "grab" else "grab"
	var cases := [
		["dup_identical_active", tick, ids[tick], kinds[tick], "known", ""],
		["same_id_other_content", tick, ids[tick], flipped, "rejected", "action_identity_conflict"],
		["retired_identical_retry", 300, ids[300], kinds[300], "rejected", "retired_action"],
		["gap_above_watermark", tick + 1, above, "grab", "rejected", "nonmonotonic_action_id"],
		["gap_below_watermark", tick + 1, below, "grab", "rejected", "*"],
		["id_0", tick + 1, 0, "grab", "rejected", "invalid_action"],
		["id_minus_1", tick + 1, -1, "grab", "rejected", "invalid_action"],
		["id_0x80000000", tick + 1, 0x80000000, "grab", "rejected", "invalid_action"]]
	var e_dup: int = effects.get(ids[tick], 0)
	for c in cases:
		var before := atomic_snapshot()
		var st: Dictionary = history.queue_action(c[1], c[2], c[3])
		var after := atomic_snapshot()
		a6_rows.append({"case": c[0], "id": c[2], "status": st, "atomic": before == after})
		check("A6_status_" + c[0], st.status == c[4] and (c[5] == "" or c[5] == "*" or st.get("reason", "") == c[5]))
		check("A6_atomic_" + c[0], before == after)
	check("A6_dup_no_new_effect", effects.get(ids[tick], 0) == e_dup)
	info.a6_ids = {"watermark": s.retired_id, "watermark_tick": watermark_tick, "above": above, "below": below, "max": s.max_id}

# ---------------------------------------------------------------- parte P: puente

var stub
var network
var ref_snaps := {}
var ref_hashes := {}
var applied: Array = []
var rejected: Array = []
var occupancy_max := 0
var future_applied := 0
var exact_bad: Array = []
var corrections_seen := 0
var last_input_by_tick := {}
const KICKS := {1: Vector3(0.8, 2.0, 0.3), 25: Vector3(-0.6, 1.6, 0.0), 75: Vector3(0.5, 1.8, -0.4),
	98: Vector3(0.0, 1.5, 0.6), 103: Vector3(-0.4, 1.4, 0.0), 112: Vector3(0.7, 1.9, 0.0),
	126: Vector3(-0.5, 1.7, 0.2), 136: Vector3(0.6, 1.5, -0.3), 148: Vector3(-0.3, 1.6, 0.4)}

func provide_bridge(_who: ActorBody, tick: int) -> ActorInput:
	var input := ActorInput.make(tick, Vector2(0.25, 0.1), float(tick) * 0.003, 0, 0)
	check("P_capture_%d" % tick, history.capture_input(input))
	local_input = input
	return input

func env_ref(t: int, context_shift := 0) -> Dictionary:
	var p := envelope(t, ref_snaps[t], [])
	p.context += context_shift
	return p

func run_bridge() -> void:
	# Referencia "host": avanza sola, sin mano, con empujones en ticks fijos a la caja 3.
	var r = make_world()
	for t in 201:
		if KICKS.has(t): check("P_kick_%d" % t, r.apply_impulse(3, 1, KICKS[t]))
		ref_snaps[t] = r.snapshot_trusted(); ref_hashes[t] = world_hash(r)
		r.step(SimClock.TICK_DT)
	stub = StubChannel.new(); add_child(stub)
	var sync := NetSync.new(); sync.clock = clock
	network = NetworkBridge.new(); add_child(network)
	check("P_bridge_start", network.start(history, sync, stub, func(_a, _b, _c): pass, func(_a, _b, _c, _d): pass))
	network.object_authority_applied.connect(func(t: int, rev: int):
		applied.append({"tick": t, "revision": rev, "clock": clock.tick})
		if t > clock.tick: future_applied += 1)
	network.object_authority_rejected.connect(func(reason: String): rejected.append({"reason": reason, "clock": clock.tick}))
	clock.tick_started.connect(bridge_tick_started)
	clock.tick_finished.connect(bridge_after)
	var plan := {30: [60]}
	for k in range(31, 61): plan[k] = [k + 30]               # P1: 30 sucesores 61..90
	plan[95] = [100]; plan[96] = [100]                        # P3: mismo tick, revision nueva
	plan[105] = [108]                                         # P4: futuro antes de la pausa
	plan[116] = [116]; plan[118] = [118]; plan[119] = [119]   # P5: sin base
	plan[133] = [128]                                         # P6: tras la correccion del actor
	plan[138] = [140, 1]; plan[139] = [146]                   # P7: pendiente rechazado + sucesor
	plan[150] = [158]; plan[151] = [160]                      # P8: cierre
	var rev_of := {}
	for tick in range(1, 171):
		if plan.has(tick):
			var spec: Array = plan[tick]
			stub.next = env_ref(spec[0], spec[1] if spec.size() > 1 else 0)
			rev_of[tick] = stub.next.revision
		if tick == 115: history.actor_baseline_ready = false   # seam_: falta de base
		if tick == 122: history.actor_baseline_ready = true
		clock._run_tick()
		if tick == 105: pause_phase()
		if tick == 152:
			stub.close()
			check("P8_slots_empty_after_close", network._pending.is_empty() and network._latest.is_empty())
			check("P8_baseline_invalid", not history.actor_baseline_ready)
			check("P8_adapter_stopped", not adapter.ready_for_input)
			info.p8_applied_at_close = applied.size()
	info.applied = applied; info.rejected = rejected; info.rev_of = rev_of
	info.occupancy_max = occupancy_max; info.exact_bad = exact_bad
	var by_tick := func(t: int) -> Array: return applied.filter(func(a): return a.tick == t)
	# P1
	var p1: Array = applied.filter(func(a): return a.tick >= 60 and a.tick <= 90)
	check("P1_pinned_applied_at_its_tick", by_tick.call(60).size() == 1 and by_tick.call(60)[0].clock == 60 and by_tick.call(60)[0].revision == rev_of[30])
	check("P1_last_successor_applied", by_tick.call(90).size() == 1 and by_tick.call(90)[0].revision == rev_of[60] and by_tick.call(90)[0].clock == 90)
	check("P1_intermediates_never_applied", p1.size() == 2)
	# P2
	check("P2_never_future", future_applied == 0)
	check("P2_at_most_two_slots", occupancy_max <= 2)
	# P3
	check("P3_same_tick_newer_revision", by_tick.call(100).size() == 1 and by_tick.call(100)[0].revision == rev_of[96])
	# P4
	check("P4_applied_after_pause_in_tick", by_tick.call(108).size() == 1 and by_tick.call(108)[0].clock == 108)
	# P5
	check("P5_successor_wins", by_tick.call(119).size() == 1 and by_tick.call(119)[0].clock == 122)
	check("P5_old_pending_never", by_tick.call(116).is_empty() and by_tick.call(118).is_empty())
	# P6
	check("P6_recovered_after_actor_correction", by_tick.call(128).size() == 1 and by_tick.call(128)[0].clock == 133)
	# P7
	check("P7_one_rejection", rejected.size() == 1 and rejected[0].clock == 140)
	check("P7_successor_after_rejection", by_tick.call(146).size() == 1 and by_tick.call(146)[0].clock == 146)
	# P8
	check("P8_nothing_after_close", applied.size() == info.p8_applied_at_close and by_tick.call(158).is_empty() and by_tick.call(160).is_empty())
	check("P8_still_stopped", not adapter.ready_for_input and network._pending.is_empty() and network._latest.is_empty())
	# P9
	check("P9_exact_after_each_application", exact_bad.is_empty())
	info.corrections = prediction.corrections; info.replay_callbacks = history.replay_callbacks

func pause_phase() -> void:
	clock.paused = true
	var before := applied.size()
	for i in 20:
		if i == 5: stub.next = env_ref(109)
		network.after_actor_tick()
		occupancy_max = maxi(occupancy_max, int(not network._pending.is_empty()) + int(not network._latest.is_empty()))
	check("P4_nothing_applied_in_pause", applied.size() == before)
	check("P4_two_slots_in_pause", not network._pending.is_empty() and not network._latest.is_empty())
	info.p4_pending = [network._pending.get("tick", -1), network._latest.get("tick", -1)]
	clock.paused = false

func bridge_tick_started(tick: int) -> void:
	if tick == 131:
		# Correccion REAL del actor por el camino de la escena (reconcile_actor), con un estado
		# del host desplazado 15 cm. ClientPrediction la reproduce y el registrador invalida.
		var st := ActorState.from_bytes(prediction._states[127])
		st.position.x += 0.15
		var c0 := prediction.corrections
		var ok: bool = history.reconcile_actor(127, st.to_bytes(), 127, 131)
		corrections_seen = prediction.corrections - c0
		check("P6_actor_corrected", ok and corrections_seen == 1)
		check("P6_adapter_stopped_by_correction", not adapter.ready_for_input)
		check("P6_baseline_ready_after_replay", history.actor_baseline_ready)

func bridge_after(tick: int) -> void:
	prediction.record(tick, local_input, actor.state)
	occupancy_max = maxi(occupancy_max, int(not network._pending.is_empty()) + int(not network._latest.is_empty()))
	if not applied.is_empty() and applied[-1].clock == tick and adapter.ready_for_input:
		if world_hash(adapter.world) != ref_hashes[tick]: exact_bad.append(tick)
	if tick >= 61 and tick < 90:
		check("P1_pinned_successor_waiting_%d" % tick, network._pending.get("tick", -1) == 90 or network._latest.is_empty())
	if tick >= 31 and tick < 60:
		check("P1_pinned_not_displaced_%d" % tick, network._pending.get("tick", -1) == 60)
	if tick >= 116 and tick < 122:
		check("P5_nothing_without_base_%d" % tick, applied.filter(func(a): return a.clock == tick).is_empty())
