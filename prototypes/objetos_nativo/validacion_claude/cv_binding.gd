extends "res://cv_base.gd"
## Validación independiente (Claude), entrega 8: H1-H8 por el enlace (criterios §4.1).
## role=binding: trabajo nativo durante los cuadros físicos. role=control: solo Jolt (H2).

const FRAMES := 90
var sentinel: RigidBody3D
var jolt: Array = []
var frame := 0
var bg  # mundo nativo que avanza en cada cuadro (binding)
var bg_cp := -1

func _ready() -> void:
	started = Time.get_ticks_usec()
	a = C.args()
	var floor := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	fs.shape = BoxShape3D.new()
	(fs.shape as BoxShape3D).size = Vector3(20, 1, 20)
	floor.add_child(fs)
	floor.position = Vector3(0, -0.5, 0)
	add_child(floor)
	sentinel = RigidBody3D.new()
	var ss := CollisionShape3D.new()
	ss.shape = BoxShape3D.new()
	(ss.shape as BoxShape3D).size = Vector3(0.5, 0.3, 0.7)
	sentinel.add_child(ss)
	sentinel.position = Vector3(0, 2.0, 0)
	sentinel.rotation = Vector3(0.3, 0.2, 0.1)
	sentinel.angular_velocity = Vector3(1.5, 0.4, -0.8)
	add_child(sentinel)

func _physics_process(_delta: float) -> void:
	if finished: return
	frame += 1
	if a.get("role") == "binding":
		if frame == 3: all_checks()
		native_load()
	var t: Transform3D = PhysicsServer3D.body_get_state(sentinel.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var row := [t.origin.x, t.origin.y, t.origin.z]
	for i in 3: row.append_array([t.basis[i].x, t.basis[i].y, t.basis[i].z])
	jolt.append(row)
	if frame >= FRAMES:
		facts["engine"] = Engine.get_version_info().string
		finish_cv({"jolt_history": jolt})

## Trabajo nativo durante los cuadros: avanzar, guardar y restaurar cada 10 cuadros.
func native_load() -> void:
	if bg == null:
		bg = C.build([0, 1, 2, 3], [], true)
	for _i in 4: bg.step(C.DT)
	if frame % 10 == 0: bg_cp = bg.cache_checkpoint()
	if frame % 10 == 5 and bg_cp >= 0: bg.restore_cached(bg_cp)
	var other = C.build([3, 2, 1, 0], [], true)
	other.restore_trusted(bg.snapshot_trusted())

func all_checks() -> void:
	# H1
	var bi: Dictionary = ClassDB.instantiate("SahurObjectWorld").get_build_info() if ClassDB.class_exists("SahurObjectWorld") else {}
	check("H1_clase_y_jolt", ClassDB.class_exists("SahurObjectWorld") and ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics" and not ClassDB.class_exists("RapierPhysicsServer3D"),
		{"backend": ProjectSettings.get_setting("physics/3d/physics_engine"), "rapier_server": ClassDB.class_exists("RapierPhysicsServer3D")}, "registrada, Jolt, sin RapierPhysicsServer3D")
	check("H1_build_info", bi.get("global_physics_server") == false and bi.get("single_thread") == true and bi.get("max_bodies") == 128 and bi.get("max_snapshot_bytes") == 1048576 and bi.get("rapier") == "0.36.0", bi, "lo documentado en el README")
	# H3
	var w = C.build([0, 1, 2, 3], [], false)
	var n0: int = w.get_body_count()
	var bad := {
		"escala_1_001": C.at(1, 0.15, 1, Basis.IDENTITY.scaled(Vector3(1.001, 1, 1))),
		"cizalla": Transform3D(Basis(Vector3(1, 0, 0), Vector3(0.01, 1, 0), Vector3(0, 0, 1)), Vector3(1, 0.15, 1)),
		"reflejo": C.at(1, 0.15, 1, Basis.IDENTITY.scaled(Vector3(-1, 1, 1))),
		"origen_NaN": C.at(NAN, 0.15, 1),
		"origen_inf": C.at(INF, 0.15, 1),
		"origen_mayor_1e6": C.at(1.1e6, 0.15, 1),
	}
	for k in bad:
		var ok: bool = w.add_box(40, 1, Vector3(0.3, 0.3, 0.3), 1.0, bad[k])
		check("H3_alta_" + k, not ok and w.get_last_error() == "invalid_pose" and w.get_body_count() == n0, w.get_last_error(), "false, invalid_pose, sin alta")
	var hw = C.build([0, 1, 2, 3], [], true)
	check("H3_agarre_previo", hw.begin_hold(30, 1, Vector3.ZERO, C.at(-0.7, 0.5, 0.2)), hw.get_last_error(), "true")
	var snap_h: PackedByteArray = hw.snapshot_trusted()
	for k in bad:
		var ok: bool = hw.set_goal(30, 1, bad[k])
		check("H3_objetivo_" + k, not ok and hw.get_last_error() == "invalid_pose" and hw.snapshot_trusted() == snap_h, hw.get_last_error(), "false, invalid_pose, sin cambios")
	# H4
	for uid in [-1, 0, 2147483648, 4294967296]:
		var ok: bool = w.add_box(uid, 1, Vector3(0.3, 0.3, 0.3), 1.0, C.at(1, 0.15, 1))
		check("H4_uid_" + str(uid), not ok and w.get_last_error() == "invalid_identity" and w.get_body_count() == n0, w.get_last_error(), "invalid_identity")
	var ok_e: bool = w.add_box(40, 0, Vector3(0.3, 0.3, 0.3), 1.0, C.at(1, 0.15, 1))
	check("H4_aparicion_0", not ok_e and w.get_last_error() == "invalid_identity", w.get_last_error(), "invalid_identity")
	for m in [1.0e-300, -1.0e-300, NAN, 2.0e6, 0.0005]:
		var ok: bool = w.add_box(40, 1, Vector3(0.3, 0.3, 0.3), m, C.at(1, 0.15, 1))
		check("H4_masa_" + str(m), not ok and w.get_last_error() == "invalid_box" and w.get_body_count() == n0, w.get_last_error(), "invalid_box")
	var ok_s: bool = w.add_box(40, 1, Vector3(0, 1, 1), 1.0, C.at(1, 0.15, 1))
	check("H4_tamano_0", not ok_s and w.get_last_error() == "invalid_box", w.get_last_error(), "invalid_box")
	# H5
	var ok_add: bool = w.add_box(41, 1, Vector3(0.3, 0.3, 0.3), 1.0, C.at(1.5, 0.15, 1.5))
	check("H5_error_vacio_tras_exito", ok_add and w.get_last_error() == "", w.get_last_error(), "vacío")
	var miss: Dictionary = w.cast_ray(Vector3(3.9, 3, 3.9), Vector3.UP, 5.0)
	check("H5_rayo_sin_acierto", miss.is_empty() and w.get_last_error() == "", [miss, w.get_last_error()], "{} y vacío")
	var inv: Dictionary = w.cast_ray(Vector3(0, 3, 0), Vector3.ZERO, 5.0)
	check("H5_rayo_invalido", inv.is_empty() and w.get_last_error() == "invalid_ray", [inv, w.get_last_error()], "{} e invalid_ray")
	check("H5_restore_cached_negativo", not hw.restore_cached(-1) and hw.get_last_error() == "invalid_tick", hw.get_last_error(), "invalid_tick")
	check("H5_restore_cached_desconocido", not hw.restore_cached(999) and hw.get_last_error() == "checkpoint_expired", hw.get_last_error(), "checkpoint_expired")
	# H6
	var given := C.at(0.05, 0.15, -0.1, Basis(Vector3.UP, 0.3))
	var s: Dictionary = w.sample(10, 1)
	var keys := ["uid", "epoch", "tick", "pose", "lv", "av", "sleeping", "held", "contacts"]
	var has_all := keys.all(func(k): return s.has(k))
	var t: Transform3D = s.get("pose", Transform3D())
	var err_o := (t.origin - given.origin).length()
	var err_b := 0.0
	var ortho := 0.0
	for i in 3:
		err_b = maxf(err_b, (t.basis[i] - given.basis[i]).length())
		ortho = maxf(ortho, absf(t.basis[i].length() - 1.0))
		for j in range(i + 1, 3): ortho = maxf(ortho, absf(t.basis[i].dot(t.basis[j])))
	check("H6_diccionario_y_pose", has_all and err_o <= 1e-6 and err_b <= 1e-6 and ortho <= 1e-6, {"claves": s.keys(), "origen": err_o, "base": err_b, "ortonormal": ortho}, "claves documentadas, ≤ 1e-6")
	h7_checks()
	h8_checks()

func h7_checks() -> void:
	var r = C.build([0, 1, 2, 3], [], true)
	var cp := C.rule_k(r)
	if cp < 0:
		not_evaluable("H7", "sin contacto activo")
		return
	var initial := var_to_bytes(r.samples())
	var snap: PackedByteArray = r.snapshot_trusted()
	var ref := C.branch(r, 200)
	facts["H7_checkpoint_tick"] = cp
	facts["H7_snapshot_bytes"] = snap.size()
	var d = C.build([3, 2, 1, 0], [90, 91], true)
	for _i in 30: d.step(C.DT)
	var ok: bool = d.restore_trusted(snap)
	var same_init := var_to_bytes(d.samples()) == initial
	var rep := C.branch(d, 200)
	check("H7_importar_orden_inverso", ok and same_init and C.first_diff(ref, rep) == -1, {"restaurado": ok, "inicial": same_init, "primer_paso_distinto": C.first_diff(ref, rep)}, "bytes iguales, 200 pasos")
	# Aislamiento intercalado con los mismos UID (W2) y altas/bajas en W3.
	var w2c = C.build([0, 1, 2, 3], [], true)
	var r2: Array = []
	for _i in cp + 30 + 200:
		w2c.step(C.DT)
		r2.append(var_to_bytes(w2c.samples()))
	var w3c = C.build([0, 1, 2, 3], [], false)
	w3c.add_box(100, 1, Vector3(0.4, 0.4, 0.4), 1.0, C.at(2, 0.2, 0))
	var r3: Array = []
	for _i in cp + 30:
		w3c.step(C.DT)
		r3.append(var_to_bytes(w3c.samples()))
	w3_ops(w3c)
	for _i in 200:
		w3c.step(C.DT)
		r3.append(var_to_bytes(w3c.samples()))
	var ip = C.build([0, 1, 2, 3], [], true)
	var w2 = C.build([0, 1, 2, 3], [], true)
	var w3 = C.build([0, 1, 2, 3], [], false)
	w3.add_box(100, 1, Vector3(0.4, 0.4, 0.4), 1.0, C.at(2, 0.2, 0))
	var h2: Array = []
	var h3: Array = []
	for _i in cp + 30:
		ip.step(C.DT); w2.step(C.DT); w3.step(C.DT)
		h2.append(var_to_bytes(w2.samples())); h3.append(var_to_bytes(w3.samples()))
		if ip.get_tick() == cp: ip.cache_checkpoint()
	var b2 := var_to_bytes(w2.samples())
	var b3 := var_to_bytes(w3.samples())
	var ok_r: bool = ip.restore_cached(cp)
	check("H7_otros_sin_cambios", ok_r and b2 == var_to_bytes(w2.samples()) and b3 == var_to_bytes(w3.samples()), ok_r, "iguales")
	var rays := w3_ops(w3)
	var ri: Dictionary = ip.cast_ray(Vector3(2, 3, 0), Vector3.DOWN, 5.0)
	check("H7_rayos_ajenos", rays[0].get("uid") == 100 and rays[1].get("uid") == 100 and ri.get("uid") == 1, [rays, ri], "X, X; en I' el piso propio")
	var hi := C.branch(ip, 200)
	for _i in 200:
		w2.step(C.DT); w3.step(C.DT)
		h2.append(var_to_bytes(w2.samples())); h3.append(var_to_bytes(w3.samples()))
	check("H7_isla_igual", C.first_diff(ref, hi) == -1, C.first_diff(ref, hi), "-1")
	check("H7_W2_igual_a_control", C.first_diff(r2, h2) == -1, C.first_diff(r2, h2), "-1")
	check("H7_W3_igual_a_control", C.first_diff(r3, h3) == -1, C.first_diff(r3, h3), "-1")

func w3_ops(w) -> Array:
	w.add_box(101, 1, Vector3(0.4, 0.4, 0.4), 1.0, C.at(-2, 0.2, 0))
	var r1: Dictionary = w.cast_ray(Vector3(2, 3, 0), Vector3.DOWN, 5.0)
	w.remove_body(101, 1)
	var r2: Dictionary = w.cast_ray(Vector3(2, 3, 0), Vector3.DOWN, 5.0)
	w.apply_impulse(100, 1, Vector3(3, 0, 0))
	return [r1, r2]

func h8_checks() -> void:
	var w = C.build([0, 1, 2, 3], [], true)
	for _i in 10: w.step(C.DT)
	var t0: int = w.cache_checkpoint()
	w.step(C.DT)
	var good: PackedByteArray = w.snapshot_trusted()
	var stats: Dictionary = w.get_cache_stats()
	var mism = C.build([0, 1, 2, 3], [], true, {10: Vector3(0.51, 0.3, 0.7)})
	mism.step(C.DT)
	var other_snap: PackedByteArray = mism.snapshot_trusted()
	var cases := {"vacio": PackedByteArray(), "truncado": good.slice(0, good.size() - 1), "otro_manifiesto": other_snap}
	for k in cases:
		var ok: bool = w.restore_trusted(cases[k])
		var same: bool = w.snapshot_trusted() == good and w.get_cache_stats() == stats
		check("H8_rechazo_" + k, not ok and same, [w.get_last_error(), same], "false, sin cambios")
	check("H8_checkpoint_previo", w.restore_cached(t0), w.get_last_error(), "restaurable")
	check("H8_agarre", w.begin_hold(30, 1, Vector3.ZERO, C.at(-0.7, 0.5, 0.2)), w.get_last_error(), "true")
	w.step(C.DT)
	check("H8_primera_suelta", w.release_body(30, 1, Vector3(0.3, 0.2, 0)), w.get_last_error(), "true")
	var before: PackedByteArray = w.snapshot_trusted()
	var second: bool = w.release_body(30, 1, Vector3(0.3, 0.2, 0))
	check("H8_segunda_suelta", not second and w.get_last_error() == "not_held" and w.snapshot_trusted() == before, w.get_last_error(), "false, not_held, sin cambios")
