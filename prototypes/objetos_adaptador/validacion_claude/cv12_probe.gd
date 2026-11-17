extends Node3D
## Validación independiente (Claude), entrega 12: history_bridge + ClientPrediction real.
## Criterios: docs/net/validacion_objetos/criterios_entrega_12.md §4. Escena propia (no hereda de Codex).
## Mi paso de escena llama a ActorMotor real y anota ojos/estado DESPUÉS de cada paso; mi diario de
## verdad y mi referencia nativa se rehacen desde un checkpoint cuando una corrección real cambia la verdad.
## Modos: actor, time, gap, effect, guards. Salida: 0 sin FAIL, 2 con FAIL, 3 si no se pudo evaluar.

const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const Bridge = preload("res://prototypes/objetos_adaptador/history_bridge.gd")
const OldPrediction = preload("res://prototypes/objetos_adaptador/validacion_claude/cv12_client_prediction_e11.gd")
const ACTOR = preload("res://scenes/actor/actor.tscn")
const UID := 2
const ANCHOR := Vector3(0.05, 0.02, 0.0)
const IMP := Vector3(1.2, 1.6, -0.8)
const SENS := 0.001

var mode := "actor"
var result_path := ""
var trace_path := ""
var clock: SimClock
var actor: ActorBody
var tuning: ActorTuning
var adapter
var bridge
var prediction := ClientPrediction.new()
var checks: Array = []
var facts := {}
var trace: Array = []
var done := false
var noeval := false
var started := 0
var end_tick := 45
var provider_calls := 0
var step_calls: Array = []
var obs := {}
var obs_pre := {}
var obs_pre_taken := false
var live := {}
var truth := {}
var commands := {}
var inputs_obj := {}
var hist := {}
var r_ref
var cp_ref := {}
var rev := 0
var effects: Array = []
var adapter_effects: Array = []
var confirmations: Array = []
var requests: Array = []
var frame_mism: Array = []
var state_mism: Array = []
var adapter_input_mism: Array = []
var input_mutated: Array = []
var live_mismatch: Array = []
var skip_capture := {}
var skip_record := {}
var marks := {}
var case_calls: Array = []
var frozen := -1
var suspended_ok := true

# --- utilidades -----------------------------------------------------------------------------
func check(id: String, ok: bool, metric = null, tol := "") -> bool:
	checks.append({"id": id, "verdict": "PASS" if ok else "FAIL", "metric": metric, "tol": tol})
	if not ok: print("CV12_FAIL ", id, " ", metric)
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

func make_world():
	var w = ClassDB.instantiate("SahurObjectWorld")
	w.add_box(1, 1, Vector3(12, 0.2, 12), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)))
	w.add_box(2, 1, Vector3(0.45, 0.35, 0.55), 1.6, Transform3D(Basis.IDENTITY, Vector3(0.1, 0.6, -0.2)))
	w.add_box(3, 1, Vector3(0.4, 0.4, 0.4), 1.0, Transform3D(Basis.IDENTITY, Vector3(0.6, 0.2, -0.6)))
	w.add_box(4, 1, Vector3(0.3, 0.6, 0.3), 0.8, Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.3, -0.4)))
	w.seal_topology(1)
	return w

func eyes_now() -> Vector3:
	return InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state))

func raw_bytes(input: ActorInput) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	input.write_to(b)
	return b.data_array

## Mi propia copia de la intención: el input sin held_claim.
func intent_mine(input: ActorInput) -> PackedByteArray:
	var s := StreamPeerBuffer.new()
	s.data_array = raw_bytes(input)
	var copy := ActorInput.read_from(s)
	copy.held_claim = PackedByteArray()
	var o := StreamPeerBuffer.new()
	copy.write_to(o)
	return o.data_array

func same_action(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty(): return a.is_empty() and b.is_empty()
	for k in ["id", "kind", "tick", "anchor", "impulse"]:
		if a.get(k) != b.get(k): return false
	return true

func frame_eq(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty(): return false
	return a.tick == b.tick and a.dt == b.dt and a.eyes == b.eyes and a.input == b.input and same_action(a.action, b.action)

func apply_frame(w, f: Dictionary) -> void:
	var s := StreamPeerBuffer.new()
	s.data_array = f.input
	var input := ActorInput.read_from(s)
	var goal := InvHoldMotion.target_of(f.eyes, input, tuning)
	var state: Dictionary = w.sample(UID, 1)
	var kind: String = f.action.get("kind", "")
	if kind == "grab": w.begin_hold(UID, 1, f.action.anchor, goal)
	if (state.held or kind == "grab") and not input.hold.is_empty(): w.set_goal(UID, 1, goal)
	if kind == "release": w.release_body(UID, 1, f.action.impulse)
	w.step(f.dt)

func rebuild_ref(base: int, upto: int) -> void:
	var w = make_world()
	w.restore_trusted(cp_ref[base])
	for t in range(base + 1, upto + 1):
		apply_frame(w, truth[t])
		cp_ref[t] = w.snapshot_trusted()
	r_ref = w

func packet(tick: int, snap: PackedByteArray, acks := []) -> Dictionary:
	rev += 1
	var p: Dictionary = adapter.authority_scope().duplicate()
	p["version"] = 1
	p["revision"] = rev
	p["tick"] = tick
	p["snapshot"] = snap
	p["acks"] = acks
	return p

func ack(id: int, kind: String, req: int, app: int) -> Dictionary:
	return {"id": id, "kind": kind, "requested_tick": req, "applied_tick": app}

func attempt(call: Callable) -> Dictionary:
	var w0: PackedByteArray = adapter.world.snapshot_trusted()
	var la0: Dictionary = adapter.last_authority()
	var g0: int = adapter.recovery_generation()
	var rd0: bool = adapter.ready_for_input
	var e0 := effects.size()
	var ok: bool = call.call()
	return {"ok": ok, "bridge_error": bridge.last_error, "adapter_error": adapter.last_error, "world_same": adapter.world.snapshot_trusted() == w0,
		"authority_same": adapter.last_authority() == la0, "gen_same": adapter.recovery_generation() == g0, "ready_same": adapter.ready_for_input == rd0, "effects": effects.size() - e0}

func atomic(r: Dictionary) -> bool:
	return not r.ok and r.world_same and r.authority_same and r.gen_same and r.ready_same and r.effects == 0

func recover(base: int, acks := []) -> Dictionary:
	var before := [actor.state.to_bytes(), clock.tick, provider_calls, step_calls.size()]
	var ok: bool = bridge.apply_authority_trusted(packet(base, cp_ref[base], acks))
	var after := [actor.state.to_bytes(), clock.tick, provider_calls, step_calls.size()]
	var diary := true
	for t in range(base + 1, clock.tick + 1):
		if not frame_eq(adapter.recorded_frame(t), truth[t]): diary = false
	return {"ok": ok, "error": bridge.last_error, "equal": h(adapter.world) == h(r_ref), "actor_clock_provider_step_untouched": before == after, "diary_equal_truth": diary}

func begin_obs() -> void:
	obs.clear()
	step_calls.clear()
	obs_pre = {}
	obs_pre_taken = false

## Mi paso de escena: ActorMotor real. ClientPrediction lo llama en sus repeticiones.
func step_local(input: ActorInput) -> void:
	if not obs_pre_taken:
		obs_pre = {"eyes": eyes_now(), "state": actor.state.to_bytes()}
		obs_pre_taken = true
	ActorMotor.step(actor, actor.state, input, tuning, SimClock.world_dt(input.tick))
	step_calls.append(input.tick)
	obs[input.tick] = {"eyes": eyes_now(), "state": actor.state.to_bytes(), "dt": SimClock.world_dt(input.tick)}

func spread(old_eyes: Dictionary, ticks: Array) -> float:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for t in ticks:
		var o: Vector3 = obs[t].eyes - old_eyes[t]
		lo = Vector3(minf(lo.x, o.x), minf(lo.y, o.y), minf(lo.z, o.z))
		hi = Vector3(maxf(hi.x, o.x), maxf(hi.y, o.y), maxf(hi.z, o.z))
	var d := hi - lo
	return maxf(d.x, maxf(d.y, d.z))

## Compara lo que el puente guardó con lo que observé dentro de cada paso real, y actualiza la verdad.
func adopt_replay(anchor_tick: int, ticks: Array, host_bytes: PackedByteArray) -> Array:
	var bad: Array = []
	if anchor_tick >= 0:
		var a: Dictionary = bridge.recorded_frame(anchor_tick)
		if a.is_empty() or a.eyes != obs_pre.get("eyes") or bridge.actor_state_at(anchor_tick) != host_bytes: bad.append(["ancla", anchor_tick])
		truth[anchor_tick].eyes = obs_pre.get("eyes")
		live[anchor_tick].state = host_bytes
	for t in ticks:
		var f: Dictionary = bridge.recorded_frame(t)
		if f.is_empty() or f.eyes != obs[t].eyes or f.dt != obs[t].dt or bridge.actor_state_at(t) != obs[t].state or f.input != truth[t].input or not same_action(f.action, truth[t].action):
			bad.append(t)
		truth[t].eyes = obs[t].eyes
		truth[t].dt = obs[t].dt
		live[t].state = obs[t].state
	return bad

func correct_actor(host_tick: int, current: int, dv: Vector3, dx: float) -> Dictionary:
	var host := ActorState.from_bytes(live[host_tick].state)
	host.velocity += dv
	host.position.x += dx
	host.quantize()
	var host_bytes := host.to_bytes()
	var old_eyes := {}
	for t in range(host_tick, current): old_eyes[t] = truth[t].eyes
	begin_obs()
	var pc0 := provider_calls
	var ok: bool = bridge.reconcile_actor(host_tick, host_bytes, host_tick, current)
	var ticks: Array = range(host_tick + 1, current)
	var calls_ok := step_calls == ticks
	var sp := spread(old_eyes, ticks) if calls_ok else -1.0
	var bad := adopt_replay(host_tick, ticks, host_bytes)
	rebuild_ref(host_tick - 1, current - 1)
	frozen = adapter.world.get_tick()
	return {"ok": ok, "calls_ok": calls_ok, "calls": step_calls.duplicate(), "bad": bad, "provider_same": provider_calls == pc0,
		"stopped": not adapter.ready_for_input, "spread": sp, "baseline": bridge.actor_baseline_ready}

# --- escena ---------------------------------------------------------------------------------
func _ready() -> void:
	started = Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
		elif arg.begins_with("--trace="): trace_path = arg.trim_prefix("--trace=")
	facts["engine"] = Engine.get_version_info().string
	facts["cmdline"] = OS.get_cmdline_args()
	if not ClassDB.class_exists("SahurObjectWorld"):
		noeval = true; info("B0_extension", "no registrada"); finish(); return
	end_tick = {"actor": 45, "time": 46, "gap": 50, "effect": 41, "guards": 25}.get(mode, 45)
	if mode == "gap":
		skip_capture[40] = true
		skip_record[46] = true
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
	clock = SimClock.new(); clock.actors_root = actors; clock.tuning = tuning
	clock.input_provider = provide_input
	add_child(clock)
	clock.tick_started.connect(_on_tick_started)
	adapter = Adapter.new(); add_child(adapter)
	adapter.action_effect.connect(_on_adapter_effect)
	if not adapter.start(clock, actor, tuning, make_world, UID, 1, 1):
		noeval = true; info("B0_adaptador", adapter.last_error); finish(); return
	bridge = Bridge.new(); add_child(bridge)
	if not bridge.start(adapter, prediction, step_local):
		noeval = true; info("B0_puente", bridge.last_error); finish(); return
	bridge.effect_ready.connect(_on_effect)
	bridge.action_confirmed.connect(_on_confirm)
	bridge.authority_needed.connect(_on_needed)
	r_ref = make_world()
	cp_ref[0] = r_ref.snapshot_trusted()
	loaded_scripts()
	clock.tick_finished.connect(after_tick)

func _on_effect(id: int, kind: String) -> void:
	effects.append([id, kind])

func _on_adapter_effect(id: int, kind: String) -> void:
	adapter_effects.append([id, kind])

func _on_confirm(id: int, kind: String, r: int, a: int) -> void:
	confirmations.append([id, kind, r, a])

func _on_needed(reason: String) -> void:
	requests.append([clock.tick, reason])

func loaded_scripts() -> void:
	var want := ["ActorInput", "ActorBody", "ActorMotor", "ActorTuning", "SimClock", "InvAuthority", "InvHoldMotion", "BaseRegistry", "ClientPrediction"]
	var found := {}
	for c in ProjectSettings.get_global_class_list():
		if c["class"] in want: found[c["class"]] = c["path"]
	var out := {}
	for n in want:
		var p: String = found.get(n, "")
		out[n] = {"path": p, "sha256": sha(FileAccess.get_file_as_bytes(p)) if p != "" else ""}
	for p in ["res://scenes/actor/actor.tscn", "res://prototypes/objetos_adaptador/clock_adapter.gd", "res://prototypes/objetos_adaptador/history_bridge.gd",
			"res://prototypes/objetos_adaptador/validacion_claude/cv12_client_prediction_e11.gd"]:
		out[p.get_file()] = {"path": p, "sha256": sha(FileAccess.get_file_as_bytes(p))}
	facts["loaded_scripts"] = out
	facts["prediction_script"] = prediction.get_script().resource_path
	facts["bridge_prediction_same_instance"] = bridge.prediction == prediction
	check("B0_client_prediction_real", prediction.get_script().resource_path == "res://scripts/net/client_prediction.gd" and bridge.prediction == prediction,
		facts["prediction_script"], "res://scripts/net/client_prediction.gd, la misma instancia que usa el puente")

func provide_input(_who: ActorBody, t: int) -> ActorInput:
	provider_calls += 1
	var buttons := 0
	if t >= 12 and t <= 17: buttons |= ActorInput.BUTTON_CROUCH
	if t >= 40 and t <= 46: buttons |= ActorInput.BUTTON_RUN
	var input := ActorInput.make(t, Vector2(0.4 * sin(t * 0.17), 0.3 + 0.2 * cos(t * 0.11)), 0.02 * t + 0.15 * sin(t * 0.23), buttons, 1 if t >= 25 else 0)
	input.hold = ActorInput.pack_hold(1, -0.3 + 0.25 * sin(t * 0.09), 1.1 + 0.5 * sin(t * 0.05), Quaternion(Vector3(0.2, 1, 0.1).normalized(), t * 0.04))
	input.held_claim.resize(InvHoldMotion.CLAIM_BYTES)
	input.held_claim.fill((t * 7) % 251)
	inputs_obj[t] = input
	var before := raw_bytes(input)
	queue_for(t)
	if not skip_capture.has(t):
		if not bridge.capture_input(input): info("captura_rechazada_%d" % t, bridge.last_error)
		if t == 8: check("B1_reintento_identico", bridge.capture_input(input), bridge.last_error, "true")
	if mode == "gap" and t == 36:
		var r := attempt(func(): return bridge.apply_authority_trusted(packet(35, cp_ref[35])))
		check("B9_dentro_del_tick_authority_phase", atomic(r) and r.bridge_error == "authority_phase", r, "authority_phase, atómico")
	if raw_bytes(input) != before or input.held_claim.size() != InvHoldMotion.CLAIM_BYTES: input_mutated.append(t)
	return input

func queue_for(t: int) -> void:
	if t == 4:
		var st: Dictionary = bridge.queue_action(4, 21, "grab", ANCHOR)
		if st.status == "queued": commands[4] = {"id": 21, "kind": "grab", "tick": 4, "anchor": ANCHOR, "impulse": Vector3.ZERO}
		check("B1_agarre_queued", st.status == "queued", st, "queued")
	if mode == "actor" and t == 35:
		var st: Dictionary = bridge.queue_action(35, 22, "release", Vector3.ZERO, IMP)
		if st.status == "queued": commands[35] = {"id": 22, "kind": "release", "tick": 35, "anchor": Vector3.ZERO, "impulse": IMP}
		check("B4_suelta_queued", st.status == "queued", st, "queued")
	if mode == "effect" and t == 31:
		info("B10_reencolar_suspendido", bridge.queue_action(31, 32, "release", Vector3.ZERO, IMP))

func _on_tick_started(t: int) -> void:
	if done: return
	match mode:
		"actor":
			if t == 26:
				var r := correct_actor(15, 26, Vector3(1.5, 0, 0), 0.05)
				check("B2_correccion_real", r.ok and r.calls_ok and r.bad.is_empty() and r.provider_same and r.stopped and r.spread > SENS and r.baseline, r, "16..25, frames = pasos reales, no traslación fija")
		"time":
			if t == 30:
				var old_eyes := {}
				for k in range(18, 30): old_eyes[k] = truth[k].eyes
				begin_obs()
				var ok: bool = bridge.apply_world_slow(18, 34, 0.5, 30)
				var ticks: Array = range(18, 30)
				var dt_ok := true
				for k in ticks:
					if not obs.has(k) or obs[k].dt != SimClock.TICK_DT * 0.5:
						dt_ok = false
				var sp := spread(old_eyes, ticks) if step_calls == ticks else -1.0
				var bad := adopt_replay(-1, ticks, PackedByteArray())
				rebuild_ref(17, 29)
				check("B5_tramo_pasado_real", ok and step_calls == ticks and dt_ok and bad.is_empty() and sp > SENS and not adapter.ready_for_input and bridge.actor_baseline_ready,
					{"ok": ok, "llamadas": step_calls, "dt_nuevo": dt_ok, "distintos": bad, "dispersion": sp}, "18..29 con dt nuevo, detenido")
		"gap":
			if t == 30:
				prediction.clear()
				var ok: bool = bridge.apply_world_slow(20, 35, 0.5, 30)
				var asked := requests.any(func(r): return r[1] == "actor_history_unavailable")
				check("B6_sin_historia", not ok and not bridge.actor_baseline_ready and asked and not adapter.ready_for_input, {"ok": ok, "pedidos": requests}, "false, base inválida, pedido")
			if t == 34:
				var g0: int = adapter.recovery_generation()
				begin_obs()
				var ok: bool = bridge.reconcile_actor(30, live[30].state, 30, 34)
				var ticks: Array = range(31, 34)
				var calls_ok := step_calls == ticks
				var same_live := calls_ok and ticks.all(func(k): return obs[k].eyes == live[k].eyes and obs[k].state == live[k].state)
				var bad := adopt_replay(30, ticks, live[30].state)
				rebuild_ref(29, 33)
				var g1: int = adapter.recovery_generation()
				var stale := attempt(func(): return adapter.recover_authority_trusted(packet(30, cp_ref[30]), frames_of(31, 33), marks.inflight))
				check("B7_estado_coincidente_y_generacion", ok and calls_ok and bad.is_empty() and bridge.actor_baseline_ready and g1 > g0 and g1 > marks.inflight
					and atomic(stale) and stale.adapter_error == "stale_recovery_generation",
					{"ok": ok, "llamadas": step_calls, "distintos": bad, "generaciones": [marks.inflight, g0, g1], "lote_en_vuelo": stale, "mundo_congelado_en": adapter.world.get_tick(), "repeticion_igual_a_lo_vivo": same_live}, "3 pasos reales, generación nueva, lote viejo rechazado")
			if t == 43:
				begin_obs()
				var ok: bool = bridge.reconcile_actor(39, live[39].state, 39, 43)
				var ticks: Array = range(40, 43)
				var same_live := step_calls == ticks and ticks.all(func(k): return obs[k].eyes == live[k].eyes and obs[k].state == live[k].state)
				var bad := adopt_replay(39, ticks, live[39].state)
				rebuild_ref(38, 42)
				check("B8_rehace_el_tick_sin_captura", ok and step_calls == ticks and bad.is_empty() and frame_eq(bridge.recorded_frame(40), truth[40]) and bridge.actor_baseline_ready,
					{"ok": ok, "llamadas": step_calls, "distintos": bad, "repeticion_igual_a_lo_vivo": same_live}, "40 rehecho igual a mi verdad")
			if t == 49:
				begin_obs()
				var host := ActorState.from_bytes(live[45].state)
				host.velocity += Vector3(1.0, 0, 0)
				host.quantize()
				var ok: bool = bridge.reconcile_actor(45, host.to_bytes(), 45, 49)
				var asked := requests.any(func(r): return r[1] == "actor_replay_gap")
				check("B9_hueco_de_repeticion", not bridge.actor_baseline_ready and asked and step_calls == [47, 48] and not adapter.ready_for_input,
					{"ok": ok, "llamadas": step_calls, "pedidos": requests}, "base inválida y pedido actor_replay_gap")
		"effect":
			if t == 30:
				var st: Dictionary = bridge.queue_action(31, 32, "release", Vector3.ZERO, IMP)
				if st.status == "queued": commands[31] = {"id": 32, "kind": "release", "tick": 31, "anchor": Vector3.ZERO, "impulse": IMP}
				var r := correct_actor(20, 30, Vector3(-1.2, 0, 0.6), -0.04)
				check("B10_encolada_y_corregida", st.status == "queued" and r.ok and r.calls_ok and r.bad.is_empty() and r.stopped, {"cola": st, "correccion": r}, "queued; corrección real 21..29")
		"guards":
			if t == 20: guards_cases()

func frames_of(a: int, b: int) -> Array:
	var out: Array = []
	for t in range(a, b + 1): out.append(truth[t].duplicate(true))
	return out

func after_tick(t: int) -> void:
	if done: return
	var input: ActorInput = inputs_obj[t]
	if not skip_record.has(t): prediction.record(t, input, actor.state)
	hist[t] = [input, actor.state.to_bytes()]
	var eyes := eyes_now()
	live[t] = {"eyes": eyes, "state": actor.state.to_bytes()}
	truth[t] = {"tick": t, "dt": SimClock.world_dt(t), "eyes": eyes, "input": intent_mine(input), "action": commands.get(t, {}).duplicate(true)}
	if not skip_capture.has(t):
		if not frame_eq(bridge.recorded_frame(t), truth[t]): frame_mism.append(t)
		if bridge.actor_state_at(t) != live[t].state: state_mism.append(t)
	var af: Dictionary = adapter.recorded_frame(t)
	if not af.is_empty() and af.input != truth[t].input: adapter_input_mism.append(t)
	apply_frame(r_ref, truth[t])
	cp_ref[t] = r_ref.snapshot_trusted()
	if adapter.ready_for_input and h(adapter.world) != h(r_ref): live_mismatch.append(t)
	trace.append({"tick": t, "dt": truth[t].dt, "eyes": var_to_str(eyes), "ready": adapter.ready_for_input, "gen": adapter.recovery_generation(),
		"native_tick": adapter.world.get_tick(), "native": h(adapter.world), "ref": h(r_ref), "baseline": bridge.actor_baseline_ready})
	match mode:
		"actor": actor_tick(t)
		"time": time_tick(t)
		"gap": gap_tick(t)
		"effect": effect_tick(t)
	if t >= end_tick and not done:
		common_end()
		finish()

func actor_tick(t: int) -> void:
	if t >= 26 and t <= 28:
		if bridge.recorded_frame(t).is_empty() or adapter.world.get_tick() != frozen or adapter.ready_for_input: suspended_ok = false
	if t == 29:
		var r := recover(14)
		check("B3_recuperacion_desde_el_puente", suspended_ok and r.ok and r.equal and r.actor_clock_provider_step_untouched and r.diary_equal_truth and bridge.actor_baseline_ready,
			{"suspendido_26_28_grabado_y_mundo_quieto": suspended_ok, "recuperacion": r}, "igual a mi referencia sin tocar actor ni reloj")
	if t == 38:
		var r := recover(37, [ack(22, "release", 35, 35)])
		check("B4_confirmacion_de_suelta_en_vivo", r.ok and r.equal and confirmations == [[22, "release", 35, 35]] and effects == [[21, "grab"], [22, "release"]],
			{"recuperacion": r, "confirmaciones": confirmations, "efectos": effects}, "una confirmación, sin otro efecto")
	if t == 39:
		var r := recover(38, [ack(22, "release", 35, 35)])
		var st: Dictionary = bridge.queue_action(35, 22, "release", Vector3.ZERO, IMP)
		check("B4_misma_confirmacion_otra_revision", r.ok and r.equal and confirmations.size() == 1 and effects.size() == 2 and st.status == "known" and st.effect_emitted and st.confirmed,
			{"recuperacion": r, "known": st}, "nada nuevo; known con efecto y confirmación")
	if t == 44:
		check("B4_final", live_mismatch.is_empty() and h(adapter.world) == h(r_ref), {"distintos": live_mismatch}, "igual a mi referencia")

func time_tick(t: int) -> void:
	if t == 31:
		var r := recover(17)
		check("B5_recuperacion", r.ok and r.equal and r.actor_clock_provider_step_untouched and r.diary_equal_truth, r, "igual")
	if t == 45:
		check("B5_final", live_mismatch.is_empty() and h(adapter.world) == h(r_ref), {"distintos": live_mismatch}, "igual 32..45")

func gap_tick(t: int) -> void:
	if t == 30:
		var r := attempt(func(): return bridge.apply_authority_trusted(packet(29, cp_ref[29])))
		check("B6_recuperacion_bloqueada", atomic(r) and r.bridge_error == "actor_baseline_required", r, "actor_baseline_required, atómico")
	if t == 31: marks["inflight"] = adapter.recovery_generation()
	if t == 34:
		var r := recover(30)
		check("B7_recuperacion", r.ok and r.equal and r.actor_clock_provider_step_untouched, r, "igual")
	if t == 40:
		var asked := requests.any(func(q): return q[0] == 40 and q[1] == "input_not_captured")
		check("B8_sin_captura", asked and not adapter.ready_for_input and bridge.recorded_frame(40).is_empty() and not bridge.actor_baseline_ready, {"pedidos": requests}, "input_not_captured, detenido")
	if t == 43:
		var r := recover(38)
		check("B8_recuperacion", r.ok and r.equal and r.actor_clock_provider_step_untouched and r.diary_equal_truth, r, "igual")
	if t == 49:
		var r := attempt(func(): return bridge.apply_authority_trusted(packet(44, cp_ref[44])))
		check("B9_recuperacion_bloqueada", atomic(r) and r.bridge_error == "actor_baseline_required", r, "actor_baseline_required, atómico")

func effect_tick(t: int) -> void:
	if t == 35:
		var r := recover(19)
		var st: Dictionary = bridge.queue_action(31, 32, "release", Vector3.ZERO, IMP)
		check("B10_aplicada_en_la_recuperacion_sin_efecto", r.ok and r.equal and r.diary_equal_truth and not adapter.world.sample(UID, 1).held and effects == [[21, "grab"]]
			and st.status == "known" and not st.effect_emitted and not st.confirmed, {"recuperacion": r, "efectos": effects, "known": st}, "suelta física, sin efecto, known sin efecto")
	if t == 37:
		var r := recover(36, [ack(32, "release", 31, 31)])
		check("B11_primer_efecto_por_confirmacion", r.ok and r.equal and effects == [[21, "grab"], [32, "release"]] and confirmations == [[32, "release", 31, 31]],
			{"recuperacion": r, "efectos": effects, "confirmaciones": confirmations}, "un efecto y una confirmación")
	if t == 38:
		var r := recover(37, [ack(32, "release", 31, 31)])
		check("B11_misma_confirmacion_sin_repetir", r.ok and r.equal and effects.size() == 2 and confirmations.size() == 1, {"recuperacion": r}, "nada nuevo")
	if t == 39:
		var r := recover(38, [ack(21, "grab", 4, 4)])
		var st: Dictionary = bridge.queue_action(31, 32, "release", Vector3.ZERO, IMP)
		check("B11_confirmacion_sin_efecto_de_lo_provisional", r.ok and r.equal and effects == [[21, "grab"], [32, "release"]] and confirmations == [[32, "release", 31, 31], [21, "grab", 4, 4]]
			and st.status == "known" and st.effect_emitted and st.confirmed, {"recuperacion": r, "confirmaciones": confirmations, "known": st}, "confirmación del agarre sin otro efecto")
	if t == 40:
		check("B11_final", h(adapter.world) == h(r_ref) and adapter_effects == [[21, "grab"]], {"efectos_del_adaptador": adapter_effects}, "igual; el adaptador solo emitió el agarre en vivo")

# --- guards: ClientPrediction nueva vs. la copia de b4aa90c ----------------------------------
func case_step(input: ActorInput) -> void:
	case_calls.append(input.tick)
	ActorMotor.step(actor, actor.state, input, tuning, SimClock.world_dt(input.tick))

func fresh(kind: String):
	var p = OldPrediction.new() if kind == "old" else ClientPrediction.new()
	for t in range(1, 20): p.record(t, hist[t][0], ActorState.from_bytes(hist[t][1]))
	return p

func modified(t: int, dv: Vector3, dx := 0.0) -> PackedByteArray:
	var s := ActorState.from_bytes(hist[t][1])
	s.velocity += dv
	s.position.x += dx
	s.quantize()
	return s.to_bytes()

func prep_old_claim(p) -> void:
	p.recent(10)
	p.reconcile(actor, 10, modified(10, Vector3(1.0, 0, 0)), 10, 20, Callable(self, "case_step"))

func run_case(p, host_tick: int, host_state: PackedByteArray, used: int, flag: String, prep := false) -> Dictionary:
	var saved := actor.state.to_bytes()
	case_calls = []
	if prep: prep_old_claim(p)
	var counters0 := [p.matches, p.corrections, p.alignments, p.waits_late_input, p.adopted_old_claims]
	case_calls = []
	if flag == "omit": p.reconcile(actor, host_tick, host_state, used, 20, Callable(self, "case_step"))
	else: p.reconcile(actor, host_tick, host_state, used, 20, Callable(self, "case_step"), flag == "true")
	var states := []
	for k in p._states.keys(): states.append([k, (p._states[k] as PackedByteArray).hex_encode()])
	var res := {"delta": [p.matches - counters0[0], p.corrections - counters0[1], p.alignments - counters0[2], p.waits_late_input - counters0[3], p.adopted_old_claims - counters0[4]],
		"calls": case_calls.duplicate(), "actor": actor.state.to_bytes().hex_encode(), "states": states}
	actor.state = ActorState.from_bytes(saved)
	actor.apply_state(actor.state)
	return res

func guards_cases() -> void:
	var cases := {
		"coincide": [12, hist[12][1], 12, false],
		"afirmacion_vieja_tras_correccion": [14, hist[14][1], 14, true],
		"input_tardio": [13, modified(13, Vector3(1.0, 0, 0)), 12, false],
		"correccion": [11, modified(11, Vector3(1.5, 0, 0), 0.05), 11, false],
		"alineacion": [0, hist[1][1], 0, false],
	}
	var diff := []
	var detail := {}
	for name in cases:
		var c: Array = cases[name]
		var a := run_case(fresh("old"), c[0], c[1], c[2], "omit", c[3])
		var b := run_case(fresh("new"), c[0], c[1], c[2], "omit", c[3])
		detail[name] = {"delta": b.delta, "llamadas": b.calls}
		if var_to_bytes(a) != var_to_bytes(b): diff.append(name)
	check("G1_sin_el_argumento_igual_a_la_version_anterior", diff.is_empty(), {"distintos": diff, "casos": detail}, "contadores, llamadas, actor y estados iguales")
	var m := run_case(fresh("new"), 12, hist[12][1], 12, "true")
	var o := run_case(fresh("new"), 14, hist[14][1], 14, "true", true)
	var l := run_case(fresh("new"), 13, modified(13, Vector3(1.0, 0, 0)), 12, "true")
	check("G2_con_el_argumento", m.calls == range(13, 20) and m.actor == (hist[19][1] as PackedByteArray).hex_encode() and m.delta[1] == 1
		and o.calls.is_empty() and o.delta[4] == 1 and l.calls.is_empty() and l.delta[3] == 1,
		{"coincide": {"llamadas": m.calls, "delta": m.delta}, "afirmacion_vieja": o.delta, "input_tardio": l.delta}, "repite si coincide; guardas intactas")

func common_end() -> void:
	check("B1_grabacion", frame_mism.is_empty() and state_mism.is_empty() and input_mutated.is_empty() and adapter_input_mism.is_empty(),
		{"frames_distintos": frame_mism, "estados_distintos": state_mism, "inputs_originales_cambiados": input_mutated, "diario_adaptador_con_claim": adapter_input_mism,
		"bytes_input_original": raw_bytes(inputs_obj[1]).size(), "bytes_intencion": truth[1].input.size()}, "iguales a mi verdad; input original intacto")
	facts["provider_calls"] = provider_calls
	facts["stats"] = bridge.stats()

func _process(_delta: float) -> void:
	if not done and Time.get_ticks_usec() - started > 7000000:
		check("interno_plazo", false, "7 s")
		finish()

func finish() -> void:
	if done: return
	done = true
	if clock != null: clock.set_physics_process(false)
	SimClock.clear_world_slow()
	var fails := checks.filter(func(c): return c.verdict == "FAIL").size()
	var result := {"schema": "cv12", "mode": mode, "checks": checks, "facts": facts, "fails": fails, "noeval": noeval,
		"effects": effects, "confirmations": confirmations, "requests": requests, "seconds": float(Time.get_ticks_usec() - started) / 1e6}
	if not result_path.is_empty():
		var f := FileAccess.open(result_path, FileAccess.WRITE)
		if f != null: f.store_string(JSON.stringify(result, " ", true, true)); f.close()
	if not trace_path.is_empty():
		var f := FileAccess.open(trace_path, FileAccess.WRITE)
		if f != null: f.store_string(JSON.stringify(trace, "", true, true)); f.close()
	print("CV12_RESULT mode=%s fails=%d noeval=%s" % [mode, fails, noeval])
	get_tree().quit(2 if fails > 0 else (3 if noeval else 0))
