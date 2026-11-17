extends "res://late_action.gd"
## Validación independiente (Claude), entrega 8: observador de la suelta tardía (criterios §5).
## No cambia el protocolo de late_action.gd: _release_intent, _authority_checkpoint, try_reconcile,
## host_step y client_step siguen siendo los de Codex. host_step/client_step se sobrescriben solo para
## llamar al original y anotar después. El mundo se envuelve en un registrador que reenvía cada llamada.
## --variant=codex: fixture y cronograma de Codex. --variant=push: mi fixture (A empuja a B, C agarrado).

const CC = preload("res://cv_common.gd")
var variant := "codex"
var trace_path := ""
var recorder
var events := {}
var trace_written := false

class Recorder extends RefCounted:
	const K = preload("res://cv_common.gd")
	var w
	var branch := 0
	var seq := 0
	var states: Array = []
	var ops: Array = []
	var restores: Array = []
	var goal_calls := 0
	func _init(native) -> void:
		w = native
	func rec(kind: String) -> void:
		var s: Array = w.samples()
		var bodies := {}
		for d in s:
			var n := K.body_numbers(d)
			var cs: Array = []
			for c in d.contacts: cs.append(c.uid)
			bodies[str(d.uid)] = {"n": n, "sleeping": d.sleeping, "held": d.held, "contacts": cs}
		states.append({"seq": seq, "kind": kind, "branch": branch, "tick": w.get_tick(), "sha": K.sha256(var_to_bytes(s)), "b": bodies})
		seq += 1
	func step(dt) -> bool:
		var ok: bool = w.step(dt)
		if ok: rec("step")
		else: ops.append({"op": "step", "ok": false, "tick": w.get_tick(), "error": w.get_last_error()})
		return ok
	func restore_trusted(bytes) -> bool:
		rec("pre_restore")
		var before: int = w.get_tick()
		var ok: bool = w.restore_trusted(bytes)
		ops.append({"op": "restore_trusted", "ok": ok, "tick_before": before, "tick_after": w.get_tick(), "bytes": bytes.size(), "branch_before": branch, "error": w.get_last_error()})
		if ok:
			branch += 1
			restores.append(bytes.duplicate())
			rec("post_restore")
		return ok
	func begin_hold(uid, epoch, anchor, goal) -> bool:
		var ok: bool = w.begin_hold(uid, epoch, anchor, goal)
		ops.append({"op": "begin_hold", "ok": ok, "uid": uid, "tick": w.get_tick(), "branch": branch})
		return ok
	func set_goal(uid, epoch, goal) -> bool:
		goal_calls += 1
		return w.set_goal(uid, epoch, goal)
	func release_body(uid, epoch, impulse) -> bool:
		var ok: bool = w.release_body(uid, epoch, impulse)
		ops.append({"op": "release_body", "ok": ok, "uid": uid, "tick": w.get_tick(), "branch": branch, "error": w.get_last_error()})
		return ok
	func apply_impulse(uid, epoch, impulse) -> bool:
		var ok: bool = w.apply_impulse(uid, epoch, impulse)
		ops.append({"op": "apply_impulse", "ok": ok, "uid": uid, "tick": w.get_tick(), "branch": branch})
		return ok
	func snapshot_trusted() -> PackedByteArray: return w.snapshot_trusted()
	func samples(): return w.samples()
	func sample(uid, epoch) -> Dictionary: return w.sample(uid, epoch)
	func get_tick() -> int: return w.get_tick()
	func get_last_error() -> String: return w.get_last_error()
	func add_box(uid, epoch, size, mass, initial) -> bool: return w.add_box(uid, epoch, size, mass, initial)
	func seal_topology(r) -> bool: return w.seal_topology(r)
	func cast_ray(o, d, dist) -> Dictionary: return w.cast_ray(o, d, dist)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
		elif arg.begins_with("--trace="): trace_path = arg.trim_prefix("--trace=")
	super()

# --- Fixtures -------------------------------------------------------------------------------
static func push_bodies() -> Array:
	return [[1, Vector3(10, 0.2, 10), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0))],
		[2, Vector3(0.6, 0.4, 0.4), 2.0, Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.2, 0))],
		[3, Vector3(0.4, 0.4, 0.4), 1.0, Transform3D(Basis.IDENTITY, Vector3(0.3, 0.2, 0))],
		[4, Vector3(0.3, 0.3, 0.3), 0.5, Transform3D(Basis.IDENTITY, Vector3(-2, 0.15, 0))]]

## Reescritura propia de la fixture de probe.gd (new_world), para la referencia del host.
static func codex_bodies() -> Array:
	return [[1, Vector3(10, 0.2, 10), 0.0, Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0))],
		[2, Vector3(0.6, 0.4, 0.4), 2.0, Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0))],
		[3, Vector3(0.6, 0.4, 0.4), 2.0, Transform3D(Basis(Vector3(0, 0, 1), 0.2), Vector3(0.15, 1, 0))]]

static func native_world(bodies: Array, reverse: bool):
	var w = ClassDB.instantiate("SahurObjectWorld")
	var list := bodies.duplicate()
	if reverse: list.reverse()
	for b in list: w.add_box(b[0], 1, b[1], b[2], b[3])
	w.seal_topology(1)
	return w

static func goal_a(n: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(-0.5 + 0.012 * float(n), 0.25, 0))

static func goal_c(n: int) -> Transform3D:
	var f := float(n)
	return Transform3D(Basis(Vector3.UP, 0.03 * f), Vector3(-2.0, 0.5 + 0.2 * sin(0.1 * f), 0.3 * cos(0.07 * f)))

func new_world(reverse := false, sealed := true, wrong_size := false):
	var native
	if variant == "push":
		native = ClassDB.instantiate("SahurObjectWorld")
		var list := push_bodies()
		if reverse: list.reverse()
		for b in list: check("create_" + str(b[0]), native.add_box(b[0], 1, b[1], b[2], b[3]))
		if sealed: check("seal", native.seal_topology(1))
	else:
		native = super(reverse, sealed, wrong_size)
	recorder = Recorder.new(native)
	return recorder

## Variante push: misma firma y mismo manejo de release_calls que goals_for de late_action.gd.
func goals_for(n: int, predict_release: bool, replay := false) -> void:
	if variant != "push":
		super(n, predict_release, replay)
		return
	push_goals(world, n, self)
	if n == 46 and predict_release:
		check("predicted_release", world.release_body(2, 1, Vector3(1, 0.6, 0)))
		if not replay: release_calls += 1

static func push_goals(w, n: int, owner = null, with_c := true) -> void:
	if n == 1:
		var ok_a: bool = w.begin_hold(2, 1, Vector3.ZERO, Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.25, 0)))
		var ok_c: bool = w.begin_hold(4, 1, Vector3.ZERO, goal_c(1))
		if owner != null:
			owner.check("begin_hold", ok_a); owner.check("begin_hold_C", ok_c)
	if n >= 2:
		if w.sample(2, 1).get("held", false):
			var ok: bool = w.set_goal(2, 1, goal_a(n))
			if owner != null: owner.check("hand_goal", ok)
		if with_c:
			var ok_c: bool = w.set_goal(4, 1, goal_c(n))
			if owner != null: owner.check("hand_goal_C", ok_c)

static func codex_goals(w, n: int) -> void:
	if n == 1:
		w.begin_hold(2, 1, Vector3.ZERO, Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.7, 0)))
	if n >= 2 and n <= 45:
		w.set_goal(2, 1, Transform3D(Basis(Vector3.UP, float(n) * 0.01), Vector3(-0.5 + float(n) * 0.003, 0.7, 0)))

# --- Anotación de eventos sin tocar el protocolo -------------------------------------------
func host_step() -> void:
	if pending_release and release_tick == 0 and not events.has("host_request_seen_before_step"):
		events["host_request_seen_before_step"] = world.get_tick() + 1
	if duplicate_requests > 0 and not events.has("host_duplicate_seen_after_tick"):
		events["host_duplicate_seen_after_tick"] = world.get_tick()
	super()

func client_step() -> void:
	if not pending_checkpoint.is_empty() and not events.has("client_confirmation_pending_at_tick"):
		events["client_confirmation_pending_at_tick"] = world.get_tick()
	if duplicate_confirmations > 0 and not events.has("client_duplicate_confirmation_seen_at_tick"):
		events["client_duplicate_confirmation_seen_at_tick"] = world.get_tick()
	super()

# --- Referencias propias ------------------------------------------------------------------
func reference(release_at: int, extra_at: int) -> Array:
	var bodies := push_bodies() if variant == "push" else codex_bodies()
	var w = native_world(bodies, false)
	var out: Array = []
	for n in range(1, FINAL_TICK + 1):
		if variant == "push": push_goals(w, n)
		else: codex_goals(w, n)
		if n == release_at: w.release_body(2, 1, Vector3(1, 0.6, 0))
		if extra_at >= 0 and n == extra_at + 1: w.apply_impulse(2, 1, Vector3(1, 0.6, 0))
		w.step(DT)
		var s: Array = w.samples()
		var nums := {}
		for d in s: nums[str(d.uid)] = CC.body_numbers(d)
		out.append({"tick": w.get_tick(), "sha": CC.sha256(var_to_bytes(s)), "n": nums})
	return out

func max_diff(a: Dictionary, b: Dictionary) -> float:
	var m := 0.0
	for uid in a:
		var x: Array = a[uid]
		var y: Array = b[uid]
		for i in x.size(): m = maxf(m, absf(x[i] - y[i]))
	return m

func host_reference() -> Dictionary:
	var hs := {}
	for s in recorder.states:
		if s.kind == "step": hs[int(s.tick)] = s
	var T: int = release_tick
	var D: int = events.get("host_duplicate_seen_after_tick", -1)
	var ref := reference(T, -1)
	var first_bad := -1
	for r in ref:
		var h = hs.get(int(r.tick))
		if h == null or h.sha != r.sha:
			first_bad = r.tick; break
	var at_final: Dictionary = {}
	for uid in hs[FINAL_TICK].b: at_final[uid] = hs[FINAL_TICK].b[uid].n
	var n46 := reference(46, -1)
	var out := {"T": T, "D": D, "ticks_compared": ref.size(), "first_mismatch_tick": first_bad,
		"neg_release_46_diff_140": max_diff(n46[FINAL_TICK - 1].n, at_final)}
	if D >= 0 and D < FINAL_TICK:
		var nd := reference(T, D)
		out["neg_double_impulse_diff_140"] = max_diff(nd[FINAL_TICK - 1].n, at_final)
	return out

func client_negative_c() -> Dictionary:
	if variant != "push" or recorder.restores.size() < 2: return {}
	var T: int = facts.get("authority_applied_tick", -1)
	var P: int = facts.get("predicted_present_at_correction", -1)
	var w = native_world(push_bodies(), true)
	var ok: bool = w.restore_trusted(recorder.restores[1])
	for n in range(T + 1, P + 1):
		push_goals(w, n, null, false)
		w.step(DT)
	var mine := {}
	for d in w.samples(): mine[str(d.uid)] = CC.body_numbers(d)
	var recorded := {}
	for s in recorder.states:
		if s.kind == "step" and s.branch == 2 and int(s.tick) == P:
			for uid in s.b: recorded[uid] = s.b[uid].n
	return {"restored": ok, "T": T, "P": P, "diff_without_C_goals": max_diff(mine, recorded) if not recorded.is_empty() else -1.0}

func finish() -> void:
	if done: return
	if not trace_written and not trace_path.is_empty() and recorder != null:
		trace_written = true
		var tr := {"schema": "cv8_late", "variant": variant, "role": role, "events": events,
			"codex_facts": facts.duplicate(true),
			"codex_vars": {"release_tick": release_tick, "release_calls": release_calls, "duplicate_requests": duplicate_requests,
				"duplicate_confirmations": duplicate_confirmations, "replay_steps": replay_steps, "reconciled": reconciled},
			"goal_calls": recorder.goal_calls, "ops": recorder.ops, "states": recorder.states,
			"restore_ok_count": recorder.ops.filter(func(o): return o.op == "restore_trusted" and o.ok).size()}
		if role == "late_host" and release_tick > 0 and recorder.states.size() >= FINAL_TICK:
			tr["reference"] = host_reference()
		if role == "late_client":
			tr["negative_c"] = client_negative_c()
		var f := FileAccess.open(trace_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(tr, "", true, true)); f.close()
	super()
