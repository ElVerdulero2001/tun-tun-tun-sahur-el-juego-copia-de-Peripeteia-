extends SceneTree

## Validación independiente (Claude), entrega 4 (criterios_entrega_5.md, parte A):
## productor real del giro (main.rotate_goal / HandRotation), canonización local,
## rechazos con aviso y coherencia de validadores. main.tscn en modo solo, sin red.
## No modifica main.gd ni runtime/.
## Uso: Godot --headless --path prototypes/objetos_red --script res://validation/hand_rotation_test.gd -- --out=<json> --trace=<jsonl>

const MainScene := preload("res://main.tscn")
const HandInput := preload("res://runtime/hand_input.gd")
const HandRotation := preload("res://runtime/hand_rotation.gd")
const Authority := preload("res://runtime/authority.gd")
const ROT_TOL := 0.000001 # rad, criterios_entrega_3.md §2

var main: Node
var results: Array = []
var out_path := ""
var trace_path := ""
var started := false
var frames_waited := 0
var finished := false
var expected_logs := {"invalid_local_target": 0, "invalid_local_rotation": 0}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_path = a.trim_prefix("--out=")
		elif a.begins_with("--trace="): trace_path = a.trim_prefix("--trace=")

func _process(_delta: float) -> bool:
	if not started:
		started = true
		main = MainScene.instantiate()
		root.add_child(main)
	elif not finished:
		frames_waited += 1
		if frames_waited >= 3:
			finished = true
			_run()
	return false

func check(id: String, ok, detail := "") -> void:
	results.append({"id": id, "ok": ok, "detail": str(detail)})

func sci(x: float) -> String:
	return String.num_scientific(x)

# Ángulo entre dos cuaterniones en doble precisión (igual que hand_input_test.gd).
func qang(a: Quaternion, b: Quaternion) -> float:
	var ax: float = a.x; var ay: float = a.y; var az: float = a.z; var aw: float = a.w
	var bx: float = b.x; var by: float = b.y; var bz: float = b.z; var bw: float = b.w
	var na := sqrt(ax * ax + ay * ay + az * az + aw * aw)
	var nb := sqrt(bx * bx + by * by + bz * bz + bw * bw)
	ax /= na; ay /= na; az /= na; aw /= na
	bx /= nb; by /= nb; bz /= nb; bw /= nb
	var rx := aw * bx - ax * bw - ay * bz + az * by
	var ry := aw * by + ax * bz - ay * bw - az * bx
	var rz := aw * bz - ax * by + ay * bx - az * bw
	var rw := aw * bw + ax * bx + ay * by + az * bz
	return 2.0 * atan2(sqrt(rx * rx + ry * ry + rz * rz), absf(rw))

func bang(a: Basis, b: Basis) -> float:
	return qang(a.orthonormalized().get_rotation_quaternion(), b.orthonormalized().get_rotation_quaternion())

func frame_of(t: Transform3D) -> Dictionary:
	return {"uid": 1, "epoch": 1, "session": 1, "tick": 0, "target": t}

func cmd_of(t: Transform3D) -> Dictionary:
	return {"op": "grab", "uid": 1, "epoch": 1, "session": 1, "action": 1, "tick": 1,
		"target": t, "anchor": Vector3(0, 0.2, 0), "direction": Vector3.ZERO}

func dx_of(i: int) -> float: return float(((i * 7) % 11) - 5)
func dy_of(i: int) -> float: return float(((i * 5) % 7) - 3)

# Cuaternión en doble precisión: [x, y, z, w].
func dq_mul(a: Array, b: Array) -> Array:
	return [a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
		a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
		a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
		a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]]
func dq_axis(ax: float, ay: float, az: float, ang: float) -> Array:
	var n := sqrt(ax * ax + ay * ay + az * az)
	var s := sin(ang * 0.5) / n
	return [ax * s, ay * s, az * s, cos(ang * 0.5)]
func dq_norm(q: Array) -> Array:
	var n := sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
	return [q[0] / n, q[1] / n, q[2] / n, q[3] / n]

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	check("P00_modo_solo_listo", main.ready_for_input == true and main.local_uid == 0, "ready %s, local_uid %d" % [main.ready_for_input, main.local_uid])
	_producer()
	_canonical()
	_coherence()
	_grab_paths()
	_finish(Time.get_ticks_msec() - t0)

# ------------------------------------------------------------------ P: productor
func _producer() -> void:
	var cam_right: Vector3 = main.camera.global_basis.x
	main.set_goal(Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.7, 0)))
	var first_bad := -1
	var bad_reason := ""
	var max_rt := 0.0
	var max_orth := 0.0
	for i in 20001:
		if not main.rotate_goal(Vector2(dx_of(i), dy_of(i)), cam_right):
			first_bad = i + 1
			bad_reason = "rotate_goal=false"
			break
		var t: Transform3D = main.target
		var b := t.basis
		var m := b * b.transposed()
		max_orth = maxf(max_orth, maxf((m.x - Vector3(1, 0, 0)).length(), maxf((m.y - Vector3(0, 1, 0)).length(), (m.z - Vector3(0, 0, 1)).length())))
		if not HandInput.valid_target(t) or not HandInput.valid(frame_of(t)):
			first_bad = i + 1
			bad_reason = "valid=false"
			break
		var pkt := HandInput.encode([frame_of(t)])
		var dec := HandInput.decode(pkt)
		if pkt.size() != 48 or dec.size() != 1:
			first_bad = i + 1
			bad_reason = "encode/decode"
			break
		max_rt = maxf(max_rt, bang(dec[0].target.basis, b))
	check("P01_productor_real_20001", first_bad == -1 and max_rt <= ROT_TOL,
		"%s; ida y vuelta máx %s rad; |B·Bᵀ−I| máx %s" % ["20.001 eventos válidos" if first_bad == -1 else "falla en %d (%s)" % [first_bad, bad_reason], sci(max_rt), sci(max_orth)])

	var rot := HandRotation.new()
	var bad2 := -1
	var ref := [0.0, 0.0, 0.0, 1.0]
	var drift_20001 := -1.0
	var right := Vector3(1, 0, 0)
	for i in 200000:
		if not rot.rotate_mouse(Vector2(dx_of(i), dy_of(i)), right):
			bad2 = i + 1
			break
		if not HandInput.valid_target(Transform3D(rot.basis(), Vector3.ZERO)):
			bad2 = i + 1
			break
		# Referencia en doble precisión con la misma composición pitch * yaw * q.
		var yaw := dq_axis(0, 1, 0, -dx_of(i) * 0.004)
		var pitch := dq_axis(1, 0, 0, -dy_of(i) * 0.004)
		ref = dq_norm(dq_mul(pitch, dq_mul(yaw, ref)))
		if i + 1 == 20001:
			drift_20001 = qang(rot.orientation, Quaternion(ref[0], ref[1], ref[2], ref[3]))
	var drift_end := qang(rot.orientation, Quaternion(ref[0], ref[1], ref[2], ref[3]))
	check("P02_hand_rotation_200000", bad2 == -1, "primer evento inválido: %d" % bad2)
	check("P03_deriva_contra_doble_precision", null, "a 20.001 eventos %s rad; a 200.000 %s rad" % [sci(drift_20001), sci(drift_end)])

	# Control negativo: la fórmula vieja (I16) sobre una base propia sigue fallando.
	var old := Basis.IDENTITY
	var old_bad := -1
	for i in 20000:
		old = Basis(Vector3.UP, -dx_of(i) * 0.004) * old
		old = Basis(Vector3(1, 0, 0), -dy_of(i) * 0.004) * old
		if not HandInput.valid(frame_of(Transform3D(old, Vector3.ZERO))):
			old_bad = i + 1
			break
	check("P04_control_negativo_formula_vieja", old_bad > 0, "la fórmula vieja deja de ser codificable en el evento %d" % old_bad)

# ------------------------------------------------------------------ C: canonización
func _set_and_expect(id: String, desired: Transform3D, accept: bool, ref_basis = null) -> void:
	var before: Transform3D = main.target
	var ok: bool = main.set_goal(desired)
	var after: Transform3D = main.target
	if accept:
		var detail := "aceptado %s; válido %s; origen igual %s" % [ok, HandInput.valid_target(after), after.origin == desired.origin]
		var good := ok and HandInput.valid_target(after) and HandInput.valid(frame_of(after)) and after.origin == desired.origin
		if ref_basis != null:
			var a := bang(after.basis, ref_basis)
			detail += "; ángulo a la rotación esperada %s rad" % sci(a)
			good = good and a <= ROT_TOL
		check(id, good, detail)
	else:
		expected_logs.invalid_local_target += 1
		check(id, not ok and after == before, "rechazado %s; objetivo anterior conservado %s" % [not ok, after == before])

func _canonical() -> void:
	var R := Basis(Vector3(0.3, 1.0, -0.2).normalized(), 0.7)
	var p := Vector3(-0.4, 0.8, 0.1)
	main.set_goal(Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.7, 0)))
	_set_and_expect("C01_rotacion_pura", Transform3D(R, p), true, R)
	_set_and_expect("C02_escala_uniforme_2", Transform3D(R.scaled_local(Vector3(2, 2, 2)), p), true, R)
	_set_and_expect("C03_escala_por_eje_1_2_3", Transform3D(R.scaled_local(Vector3(1, 2, 3)), p), true, R)
	var shear := Basis(Vector3(1, 0, 0), Vector3(0.3, 1, 0), Vector3(0, 0.2, 1))
	_set_and_expect("C04_cizalla", Transform3D(R * shear, p), true)
	_set_and_expect("C05_reflejo", Transform3D(R.scaled_local(Vector3(1, 1, -1)), p), false)
	_set_and_expect("C06_singular", Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3.ZERO), p), false)
	_set_and_expect("C07a_origen_nan", Transform3D(R, Vector3(NAN, 0, 0)), false)
	_set_and_expect("C07b_base_inf", Transform3D(Basis(Vector3(INF, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), p), false)
	_set_and_expect("C07c_base_nan", Transform3D(Basis(Vector3(NAN, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), p), false)
	_set_and_expect("C08a_escala_1e13_desborda", Transform3D(R.scaled_local(Vector3(1e13, 1e13, 1e13)), p), false)
	_set_and_expect("C08b_escala_1e12", Transform3D(R.scaled_local(Vector3(1e12, 1e12, 1e12)), p), true, R)
	_set_and_expect("C09a_escala_0_02", Transform3D(R.scaled_local(Vector3(0.02, 0.02, 0.02)), p), true, R)
	# Informativo: una rotación con escala uniforme 0,005 (det 1,25e-7) queda por debajo del umbral 1e-6.
	var before: Transform3D = main.target
	var small: bool = main.set_goal(Transform3D(R.scaled_local(Vector3(0.005, 0.005, 0.005)), p))
	if not small: expected_logs.invalid_local_target += 1
	check("C09b_escala_0_005", null, "aceptado %s; objetivo conservado %s (umbral de determinante 1e-6)" % [small, main.target == before])
	var near := Basis(Vector3(1, 0, 0), Vector3(1, 0.002, 0), Vector3(0, 0, 1))
	_set_and_expect("C10_casi_singular_det_2e-3", Transform3D(near, p), true)

	# rotate_goal y el setter de _goal_rotation.
	main.set_goal(Transform3D(R, p))
	var keep: Transform3D = main.target
	var r1: bool = main.rotate_goal(Vector2(NAN, 1), Vector3(1, 0, 0))
	var r2: bool = main.rotate_goal(Vector2(INF, 0), Vector3(1, 0, 0))
	var r3: bool = main.rotate_goal(Vector2(1, 1), Vector3.ZERO)
	expected_logs.invalid_local_rotation += int(not r1) + int(not r2) + int(not r3)
	check("C11_rotate_goal_rechaza", not r1 and not r2 and not r3 and main.target == keep,
		"nan %s, inf %s, eje cero %s; objetivo conservado %s" % [r1, r2, r3, main.target == keep])
	var r4: bool = main.rotate_goal(Vector2(1e30, -1e30), Vector3(0, 0, 5))
	check("C12_rotate_goal_delta_enorme", r4 and HandInput.valid_target(main.target), "aceptado %s; válido %s" % [r4, HandInput.valid_target(main.target)])
	var orient_before: Quaternion = main._rotation.orientation
	main._goal_rotation = Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3.ZERO)
	expected_logs.invalid_local_rotation += 1
	check("C13_setter_rechaza", main._rotation.orientation == orient_before, "orientación conservada %s" % (main._rotation.orientation == orient_before))

# ------------------------------------------------------------------ V: coherencia
func _coherence() -> void:
	var targets: Array = []
	var p := Vector3(0.2, 0.9, -0.3)
	for k in 40:
		var axis := Vector3(sin(k * 1.3), cos(k * 0.7), sin(k * 2.1) + 0.1).normalized()
		var R := Basis(axis, k * 0.37)
		targets.append(["rot%d" % k, Transform3D(R, p)])
		for s in [0.99, 0.999, 1.001, 1.01, 1.02]:
			targets.append(["rot%d_s%s" % [k, s], Transform3D(R.scaled_local(Vector3(s, s, s)), p)])
		for e in [0.000001, 0.00001, 0.0001, 0.001]:
			targets.append(["rot%d_shear%s" % [k, e], Transform3D(R * Basis(Vector3(1, 0, 0), Vector3(e, 1, 0), Vector3(0, 0, 1)), p)])
		targets.append(["rot%d_reflejo" % k, Transform3D(R.scaled_local(Vector3(1, 1, -1)), p)])
	var old := Basis.IDENTITY
	var marks := {0: true, 500: true, 1262: true, 1263: true, 1300: true, 5000: true, 19999: true}
	for i in 20000:
		old = Basis(Vector3.UP, -dx_of(i) * 0.004) * old
		old = Basis(Vector3(1, 0, 0), -dy_of(i) * 0.004) * old
		if marks.has(i): targets.append(["vieja_%d" % (i + 1), Transform3D(old, p)])
	targets.append(["nan", Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0))])
	var mismatch: Array = []
	var produced_bad: Array = []
	var strict_on_old := []
	for pair in targets:
		var t: Transform3D = pair[1]
		var a := HandInput.valid_target(t)
		var b := HandInput.valid(frame_of(t))
		var c := Authority.valid_command(cmd_of(t))
		if a != b or a != c: mismatch.append("%s (%s/%s/%s)" % [pair[0], a, b, c])
		if str(pair[0]).begins_with("vieja_"): strict_on_old.append("%s=%s" % [pair[0], a])
		var before: Transform3D = main.target
		var ok: bool = main.set_goal(t)
		if ok:
			var out: Transform3D = main.target
			if not (HandInput.valid_target(out) and HandInput.valid(frame_of(out)) and Authority.valid_command(cmd_of(out))):
				produced_bad.append(pair[0])
		else:
			expected_logs.invalid_local_target += 1
			if main.target != before: produced_bad.append(str(pair[0]) + " (cambió al rechazar)")
	check("V01_validadores_coinciden", mismatch.is_empty(), "%d objetivos; distintos: %s" % [targets.size(), mismatch.slice(0, 6)])
	check("V02_lo_producido_pasa_los_tres", produced_bad.is_empty(), "malos: %s" % [produced_bad.slice(0, 6)])
	check("V03_receptor_estricto_con_la_formula_vieja", null, ", ".join(strict_on_old))

# ------------------------------------------------------------------ G: agarre local
func _grab_paths() -> void:
	var na: int = main.next_action
	var pending: int = main._pending_grab
	var queued: int = main._local_commands.size()
	var R := Basis(Vector3(0, 1, 0), 0.4)
	main.request_grab(1, Vector3(0, 0.2, 0), Transform3D(R.scaled_local(Vector3(1, 1, -1)), Vector3(-0.5, 0.7, 0)))
	expected_logs.invalid_local_target += 1
	check("G01_agarre_con_reflejo_rechazado", main.next_action == na and main._pending_grab == pending and main._local_commands.size() == queued,
		"next_action %d→%d; pendiente %d; cola %d→%d" % [na, main.next_action, main._pending_grab, queued, main._local_commands.size()])
	main.request_grab(1, Vector3(NAN, 0.2, 0), Transform3D(R, Vector3(-0.5, 0.7, 0)))
	check("G02_agarre_con_punto_nan", null, "rechazado %s (sin aviso en el código: return directo)" % (main._pending_grab == pending and main.next_action == na))
	main.request_grab(1, Vector3(0, 0.2, 0), Transform3D(R.scaled_local(Vector3(2, 2, 2)), Vector3(-0.5, 0.7, 0)))
	var t: Transform3D = main.target
	check("G03_agarre_con_escala_canonizado", main._pending_grab != 0 and HandInput.valid_target(t) and bang(t.basis, R) <= ROT_TOL
		and t.origin == Vector3(-0.5, 0.7, 0),
		"pendiente %d; válido %s; ángulo %s rad" % [main._pending_grab, HandInput.valid_target(t), sci(bang(t.basis, R))])

func _finish(ms: int) -> void:
	root.remove_child(main)
	main.free()
	var tr: Array = []
	for line in FileAccess.get_file_as_string(trace_path).split("\n", false):
		var v = JSON.parse_string(line)
		if typeof(v) == TYPE_DICTIONARY: tr.append(v)
	var got := {"invalid_local_target": 0, "invalid_local_rotation": 0, "hand_input_encode_failed": 0}
	for r in tr:
		if got.has(r.get("kind", "")): got[r.kind] += 1
	check("C14_un_aviso_por_rechazo", got.invalid_local_target == expected_logs.invalid_local_target
		and got.invalid_local_rotation == expected_logs.invalid_local_rotation,
		"esperados %s; registrados %s" % [expected_logs, got])
	var fails := results.filter(func(r): return r.ok == false).size()
	var text := JSON.stringify({"schema": 1, "results": results, "fails": fails, "ms": ms}, "  ", false, true)
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	for r in results:
		print("%s %s %s" % ["PASS" if r.ok == true else ("FAIL" if r.ok == false else "INFO"), r.id, r.detail])
	print("HAND_ROTATION_DONE pass=%d fail=%d ms=%d" % [results.filter(func(r): return r.ok == true).size(), fails, ms])
	quit(0)
