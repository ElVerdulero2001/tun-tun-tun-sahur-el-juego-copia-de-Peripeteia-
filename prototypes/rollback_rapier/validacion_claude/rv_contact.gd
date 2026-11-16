extends "res://validacion_claude/rv_common.gd"

## R2 (punto 2 del encargo): restauración desde un checkpoint tomado durante un
## contacto dinámico activo, con trayectorias, velocidades, contactos
## informados, reposo y despertar. Un proceso, un espacio.
const SEARCH := 120
const H := 360
const SHOVE_J := 30
const WAKE_J := 240
var A: RigidBody3D
var B: RigidBody3D
var space: RID
var manager: Node
var names := ["A", "B"]

func _ready() -> void:
	parse_args()
	if not rapier_ready():
		finish(2, {"reason": "backend_not_prepared"})
		return
	manager = make_manager(self)
	make_floor(self, "Floor")
	A = make_box(self, "A", Vector3(0.6, 0.4, 0.4), Vector3(0, 0.2, 0), 2.0)
	B = make_box(self, "B", Vector3(0.6, 0.4, 0.4), Vector3(0.15, 1.0, 0), 2.0, Basis(Vector3(0, 0, 1), 0.2))
	await get_tree().physics_frame
	await get_tree().physics_frame
	space = get_world_3d().space
	PhysicsServer3D.space_set_active(space, false)
	flush(space)
	_run()

func bodies() -> Dictionary:
	return {"A": A, "B": B}

func commands(j: int, branch: String) -> void:
	if branch == "ref":
		if j == SHOVE_J: impulse(A, Vector3(1.2, 0, 0.4))
		if j == WAKE_J: impulse(B, Vector3(0, 0, 0.8))
	elif branch == "div":
		if j == 10: impulse(B, Vector3(0.3, 4.0, 0))
		if j == WAKE_J: impulse(A, Vector3(0, 0, -0.8))

func run_branch(branch: String, j0: int, cache_sleep := false) -> Dictionary:
	var hist: Array = []
	var sleep_index := -1
	var sleep_j := -1
	for j in range(j0 + 1, H + 1):
		commands(j, branch)
		step(space)
		var rec := snap(bodies())
		hist.append(rec)
		if cache_sleep and sleep_index < 0 and j > SHOVE_J and j < WAKE_J and rec.A.sl and rec.B.sl:
			manager.call("cache_state", space, "sleep")
			sleep_index = (manager.call("ordered_cache_tags") as Array).find("sleep")
			sleep_j = j
	return {"hist": hist, "sleep_index": sleep_index, "sleep_j": sleep_j}

func restore(index: int, expected: Dictionary) -> Dictionary:
	var loaded = manager.call("load_cached_state", space, index)
	flush(space)
	var e := cmp([expected], [snap(bodies())], names, false)
	e["return_value"] = loaded
	return e

func _run() -> void:
	# Búsqueda del checkpoint con la regla fijada antes de correr.
	var c := -1
	for s in range(1, SEARCH + 1):
		step(space)
		var r := snap(bodies())
		var speed := maxf(Vector3(r.A.lv[0], r.A.lv[1], r.A.lv[2]).length(), Vector3(r.B.lv[0], r.B.lv[1], r.B.lv[2]).length())
		if s >= 5 and "B" in r.A.hits and "A" in r.B.hits and not r.A.sl and not r.B.sl and speed >= 0.05:
			c = s
			facts["checkpoint_speed"] = speed
			break
	if c < 0:
		facts["reason"] = "no_active_contact_in_%d_steps" % SEARCH
		finish(3)
		return
	facts["checkpoint_step"] = c
	var cp := snap(bodies())
	facts["checkpoint_state"] = cp
	manager.call("cache_state", space, "contact")
	var idx: int = (manager.call("ordered_cache_tags") as Array).find("contact")
	var bytes = manager.call("export_state", space, "RustBincode")
	facts["snapshot_bytes"] = bytes.size() if typeof(bytes) == TYPE_PACKED_BYTE_ARRAY else -1

	var ref := run_branch("ref", 0)
	var r1 := restore(idx, cp)
	check("R2a_restaurar_en_contacto", r1.return_value == true and within(r1), r1, "true; ≤ EPS; reposo igual")
	var rep1 := run_branch("ref", 0, true)
	var e1 := cmp(ref.hist, rep1.hist, names)
	check("R2b_repeticion_en_contacto", within(e1), e1, "%d pasos ≤ EPS; reposo y contactos iguales" % H)

	var r2 := restore(idx, cp)
	var div := run_branch("div", 0)
	var ed := cmp(ref.hist, div.hist, names)
	check("R2c_control_sensible", ed.pos > 0.01, ed, "rama distinta > 1 cm (validez del instrumento)")
	var r3 := restore(idx, cp)
	var rep2 := run_branch("ref", 0)
	var e2 := cmp(ref.hist, rep2.hist, names)
	check("R2d_repeticion_tras_rama_distinta", r2.return_value == true and within(r2) and r3.return_value == true and within(r3) and within(e2),
		{"restore_before_div": r2, "restore_after_div": r3, "replay": e2}, "≤ EPS; reposo y contactos iguales")

	var e3 := {}
	if typeof(bytes) == TYPE_PACKED_BYTE_ARRAY and not bytes.is_empty():
		manager.call("import_state", space, bytes)
		flush(space)
		var ri := cmp([cp], [snap(bodies())], names, false)
		var rep3 := run_branch("ref", 0)
		e3 = cmp(ref.hist, rep3.hist, names)
		check("R2e_import_mismo_proceso", within(ri) and within(e3), {"restored": ri, "replay": e3}, "≤ EPS")
	else:
		check("R2e_import_mismo_proceso", false, {"reason": "export_vacio"}, "≤ EPS")

	var ne := node_error(ref.hist + rep1.hist + rep2.hist, names)
	check("R2f_nodos_y_servidor", ne.pos <= EPS and ne.sleep_mismatch == 0, ne, "nodo = servidor ≤ EPS; sleeping igual")

	# Reposo y despertar en la referencia.
	var both_sleep: Array = []
	var wake_j := -1
	var contact_steps := 0
	for i in ref.hist.size():
		var rec: Dictionary = ref.hist[i]
		if rec.A.sl and rec.B.sl: both_sleep.append(i + 1)
		if "B" in rec.A.hits: contact_steps += 1
		if wake_j < 0 and i + 1 >= WAKE_J and i >= 1 and ref.hist[i - 1].B.sl and not rec.B.sl: wake_j = i + 1
	facts["ref_both_sleeping_first"] = both_sleep[0] if both_sleep.size() else -1
	facts["ref_both_sleeping_steps"] = both_sleep.size()
	facts["ref_wake_step"] = wake_j
	facts["ref_contact_steps"] = contact_steps
	facts["ref_last"] = ref.hist.back()
	facts["sleep_checkpoint_step"] = rep1.sleep_j
	if rep1.sleep_index >= 0 and wake_j > rep1.sleep_j:
		var expected: Dictionary = ref.hist[rep1.sleep_j - 1]
		var rs := restore(rep1.sleep_index, expected)
		var reps := run_branch("ref", rep1.sleep_j)
		var es := cmp(ref.hist.slice(rep1.sleep_j), reps.hist, names)
		var wake_rep := -1
		for i in reps.hist.size():
			var prev: Dictionary = expected if i == 0 else reps.hist[i - 1]
			if wake_rep < 0 and prev.B.sl and not reps.hist[i].B.sl: wake_rep = rep1.sleep_j + i + 1
		facts["replay_wake_step"] = wake_rep
		check("R2g_desde_reposo_y_despertar", rs.return_value == true and within(rs) and within(es) and wake_rep == wake_j,
			{"restored": rs, "replay": es, "wake_ref": wake_j, "wake_replay": wake_rep}, "≤ EPS; despierta en el mismo paso")
	else:
		check("R2g_desde_reposo_y_despertar", null, {"sleep_checkpoint": rep1.sleep_j, "wake_ref": wake_j},
			"no evaluable", "la referencia no durmió entre %d y %d o no despertó después" % [SHOVE_J, WAKE_J])
	finish(0)
