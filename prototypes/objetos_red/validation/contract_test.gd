extends SceneTree

## Validación independiente (Claude): contrato de estado y acciones.
## Un proceso, sin red. No modifica runtime/: solo lo carga y lo ejercita.
## Uso: Godot --headless --path prototypes/objetos_red --script res://validation/contract_test.gd -- --out=<ruta.json>
## Criterios: docs/net/validacion_objetos/criterios_entrega_1.md, sección 3.1 y 3.2.

const State := preload("res://runtime/state.gd")
const Authority := preload("res://runtime/authority.gd")
const MAX_ID := 0x7FFFFFFF

var results: Array = []
var out_path := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_path = a.trim_prefix("--out=")
	_state_tests()
	_authority_tests()
	var fails := 0
	for r in results:
		if not r.ok: fails += 1
	var text := JSON.stringify({"schema": 1, "results": results, "fails": fails}, "  ", false, true)
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	for r in results:
		print("%s %s %s" % ["PASS" if r.ok else "FAIL", r.id, r.detail])
	print("CONTRACT_DONE pass=%d fail=%d" % [results.size() - fails, fails])
	quit(0)

func check(id: String, ok: bool, detail := "") -> void:
	results.append({"id": id, "ok": ok, "detail": detail})

## Ángulo entre dos rotaciones por diferencia de columnas (≈ ángulo en rad para
## ángulos chicos). Quaternion.angle_to calcula acos(≈1) en float32 y no resuelve
## menos de ~5e-4 rad; con él la prueba medía su propio redondeo.
func rot_diff(a: Basis, b: Basis) -> float:
	var x := a.orthonormalized()
	var y := b.orthonormalized()
	return maxf((x.x - y.x).length(), maxf((x.y - y.y).length(), (x.z - y.z).length()))

# --- bytes armados a mano (little-endian), independientes de State.encode ---
func raw(fields := {}) -> PackedByteArray:
	var v := {"magic": 0x4F32, "version": 1, "reserved": 0, "uid": 7, "epoch": 3, "revision": 5,
		"tick": 1234, "owner": 0, "session": 0, "action": 9, "applied_tick": 1200, "phase": 0,
		"sleep": 0, "p": [1.5, 0.25, -2.0], "q": [0.0, 0.0, 0.0, 1.0], "lv": [0.5, -1.0, 0.25],
		"av": [0.0, 0.125, -0.5]}
	v.merge(fields, true)
	var b := PackedByteArray()
	b.resize(90)
	b.encode_u16(0, v.magic)
	b.encode_u8(2, v.version)
	b.encode_u8(3, v.reserved)
	var i := 4
	for k in ["uid", "epoch", "revision", "tick", "owner", "session", "action", "applied_tick"]:
		b.encode_u32(i, int(v[k]) & 0xFFFFFFFF)
		i += 4
	b.encode_u8(36, v.phase)
	b.encode_u8(37, v.sleep)
	i = 38
	for k in ["p", "q", "lv", "av"]:
		for x in v[k]:
			b.encode_float(i, x)
			i += 4
	return b

func parse(b: PackedByteArray) -> Dictionary:
	var d := {"magic": b.decode_u16(0), "version": b.decode_u8(2), "reserved": b.decode_u8(3)}
	var i := 4
	for k in ["uid", "epoch", "revision", "tick", "owner", "session", "action", "applied_tick"]:
		d[k] = b.decode_u32(i)
		i += 4
	d.phase = b.decode_u8(36)
	d.sleep = b.decode_u8(37)
	i = 38
	for k in ["p", "q", "lv", "av"]:
		var n := 4 if k == "q" else 3
		var arr := []
		for j in n:
			arr.append(b.decode_float(i))
			i += 4
		d[k] = arr
	return d

func valid_state():
	var s = State.new()
	s.uid = 7; s.epoch = 3; s.revision = 5; s.tick = 1234; s.action = 9; s.applied_tick = 1200
	s.pose = Transform3D(Basis(Vector3(0.3, 1, -0.2).normalized(), 2.1), Vector3(1.5, 0.25, -2.0))
	s.lv = Vector3(0.5, -1.0, 0.25)
	s.av = Vector3(0.0, 0.125, -0.5)
	return s

func _state_tests() -> void:
	var s = valid_state()
	var bytes: PackedByteArray = s.encode()
	check("S01_size_90", bytes.size() == 90, "size=%d" % bytes.size())
	# Disposición: parseo propio de lo que codifica la implementación.
	var d := parse(bytes)
	var q: Quaternion = s.pose.basis.orthonormalized().get_rotation_quaternion()
	var layout_ok: bool = d.magic == 0x4F32 and d.version == 1 and d.reserved == 0 and d.uid == 7 \
		and d.epoch == 3 and d.revision == 5 and d.tick == 1234 and d.owner == 0 and d.session == 0 \
		and d.action == 9 and d.applied_tick == 1200 and d.phase == 0 and d.sleep == 0 \
		and is_equal_approx(d.p[0], 1.5) and is_equal_approx(d.p[1], 0.25) \
		and absf(d.q[0] - q.x) < 1e-6 and absf(d.q[3] - q.w) < 1e-6 and is_equal_approx(d.av[2], -0.5)
	check("S02_layout_encode_by_independent_parser", layout_ok, JSON.stringify(d))
	# Decodificación de bytes armados a mano.
	var h = State.decode(raw())
	var hand_ok: bool = h != null and h.uid == 7 and h.epoch == 3 and h.revision == 5 and h.tick == 1234 \
		and h.action == 9 and h.applied_tick == 1200 and h.phase == 0 and not h.sleeping \
		and h.pose.origin.is_equal_approx(Vector3(1.5, 0.25, -2.0)) and h.lv.is_equal_approx(Vector3(0.5, -1.0, 0.25))
	check("S03_decode_handmade_bytes", hand_ok)
	# Ida y vuelta.
	var r = State.decode(bytes)
	var ang: float = rot_diff(r.pose.basis, s.pose.basis) if r != null else 99.0
	check("S04_roundtrip_identity_and_rotation", r != null and r.uid == s.uid and r.epoch == s.epoch \
		and r.revision == s.revision and r.tick == s.tick and r.action == s.action \
		and r.applied_tick == s.applied_tick and ang < 1e-6 and r.pose.origin.distance_to(s.pose.origin) < 1e-6 \
		and r.lv.distance_to(s.lv) < 1e-6 and r.av.distance_to(s.av) < 1e-6, "angle=" + String.num_scientific(ang))
	# HELD con dueño/sesión.
	var held = valid_state()
	held.phase = State.Phase.HELD; held.owner = 123456789; held.session = 42; held.sleeping = true
	var hr = State.decode(held.encode())
	check("S05_roundtrip_held_owner_session_sleep", hr != null and hr.phase == State.Phase.HELD \
		and hr.owner == 123456789 and hr.session == 42 and hr.sleeping)
	# Límites.
	var top = raw({"uid": MAX_ID, "epoch": MAX_ID, "revision": MAX_ID, "tick": MAX_ID, "action": MAX_ID,
		"applied_tick": MAX_ID, "owner": MAX_ID, "session": MAX_ID, "phase": 1})
	check("S06_accept_MAX_ID_all_fields", State.decode(top) != null)
	for k in ["uid", "epoch", "revision", "tick", "action", "applied_tick"]:
		check("S07_reject_%s_2^31" % k, State.decode(raw({k: 0x80000000})) == null)
		check("S07_reject_%s_2^32-1" % k, State.decode(raw({k: 0xFFFFFFFF})) == null)
	for k in ["uid", "epoch", "revision"]:
		check("S08_reject_%s_zero" % k, State.decode(raw({k: 0})) == null)
	check("S08_accept_tick_zero", State.decode(raw({"tick": 0, "applied_tick": 0})) != null)
	# Tamaño y cabecera.
	var full := raw()
	for n in [0, 1, 89]:
		check("S09_reject_truncated_%d" % n, State.decode(full.slice(0, n)) == null)
	var longer := full.duplicate()
	longer.append(0)
	check("S09_reject_size_91", State.decode(longer) == null)
	var zeros := PackedByteArray()
	zeros.resize(90)
	check("S09_reject_90_zero_bytes", State.decode(zeros) == null)
	check("S10_reject_magic", State.decode(raw({"magic": 0x4F33})) == null)
	check("S10_reject_version_0", State.decode(raw({"version": 0})) == null)
	check("S10_reject_version_2", State.decode(raw({"version": 2})) == null)
	check("S10_reject_reserved_1", State.decode(raw({"reserved": 1})) == null)
	# Valores no finitos.
	var nan := NAN
	var inf := INF
	check("S11_reject_nan_position", State.decode(raw({"p": [nan, 0.0, 0.0]})) == null)
	check("S11_reject_inf_position", State.decode(raw({"p": [0.0, inf, 0.0]})) == null)
	check("S11_reject_nan_quat", State.decode(raw({"q": [nan, 0.0, 0.0, 1.0]})) == null)
	check("S11_reject_nan_lv", State.decode(raw({"lv": [0.0, nan, 0.0]})) == null)
	check("S11_reject_inf_av", State.decode(raw({"av": [0.0, 0.0, -inf]})) == null)
	var bad = valid_state()
	bad.lv = Vector3(nan, 0, 0)
	check("S11_encode_refuses_nan", bad.encode().is_empty())
	# Giro.
	check("S12_reject_zero_quat", State.decode(raw({"q": [0.0, 0.0, 0.0, 0.0]})) == null)
	check("S12_reject_quat_len2_1.21", State.decode(raw({"q": [0.0, 0.0, 0.0, 1.1]})) == null)
	var nearly = State.decode(raw({"q": [0.0, 0.0, 0.0, 1.002]}))
	check("S12_accept_and_normalize_quat_len2_1.004", nearly != null and nearly.pose.basis.is_equal_approx(Basis.IDENTITY))
	var neg = State.decode(raw({"q": [0.0, -0.70710678, 0.0, -0.70710678]}))
	var pos = State.decode(raw({"q": [0.0, 0.70710678, 0.0, 0.70710678]}))
	check("S12_q_and_minus_q_same_rotation", neg != null and pos != null \
		and rot_diff(neg.pose.basis, pos.pose.basis) < 1e-6)
	var refl = valid_state()
	refl.pose = Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3.ZERO)
	check("S12_encode_refuses_reflection", refl.encode().is_empty())
	var scaled = valid_state()
	scaled.pose = Transform3D(Basis.IDENTITY.scaled(Vector3(1.01, 1.01, 1.01)), Vector3.ZERO)
	check("S12_encode_refuses_scaled_basis", scaled.encode().is_empty())
	var worst := 0.0
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(1, 1, 1).normalized(), Vector3(-0.2, 0.9, 0.4).normalized()]:
		for deg in [0.0, 0.01, 1.0, 90.0, 179.99, 180.0]:
			var t = valid_state()
			t.pose = Transform3D(Basis(axis, deg_to_rad(deg)), Vector3(3.25, 1.0, -7.5))
			var back = State.decode(t.encode())
			var e: float = 99.0 if back == null else rot_diff(back.pose.basis, t.pose.basis)
			worst = maxf(worst, e)
	check("S12_rotation_roundtrip_worst_below_1e-6_rad", worst < 1e-6, "worst=" + String.num_scientific(worst) + " rad")
	# Fase y reposo.
	check("S13_reject_phase_3", State.decode(raw({"phase": 3})) == null)
	check("S13_reject_held_without_owner", State.decode(raw({"phase": 1, "owner": 0, "session": 5})) == null)
	check("S13_reject_held_without_session", State.decode(raw({"phase": 1, "owner": 5, "session": 0})) == null)
	check("S13_reject_free_with_owner", State.decode(raw({"phase": 0, "owner": 5, "session": 0})) == null)
	check("S13_reject_free_with_session", State.decode(raw({"phase": 0, "owner": 0, "session": 5})) == null)
	check("S13_accept_removed_without_owner", State.decode(raw({"phase": 2})) != null)
	check("S13_reject_sleep_byte_2", State.decode(raw({"sleep": 2})) == null)
	# copy() de un estado inválido devuelve null: capture() lo usa sin comprobar.
	var invalid = valid_state()
	invalid.uid = 0
	check("S14_copy_of_invalid_returns_null_observed", invalid.copy() == null,
		"capture()/observe() llaman copy() sin comprobar null")

func cmd(op: String, action: int, tick: int, session := 1, uid := 1, epoch := 1, direction := Vector3.ZERO) -> Dictionary:
	return {"op": op, "uid": uid, "epoch": epoch, "session": session, "action": action, "tick": tick,
		"target": Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), "anchor": Vector3(0, 0.2, 0),
		"direction": direction if op == "throw" and direction != Vector3.ZERO else (Vector3(1, 0, 0) if op == "throw" else direction)}

func held_authority(peer := 5):
	var a = Authority.new()
	a.state.uid = 1
	var r: Dictionary = a.request(peer, cmd("grab", 1, 10, 1), 11)
	var job: Dictionary = a.commit(11)
	a.remember_commit(job, a.state.encode())
	return a

func _authority_tests() -> void:
	# Revisión persistente.
	var a = Authority.new()
	a.state.uid = 1
	var r0: int = a.state.revision
	a.request(5, cmd("grab", 1, 10), 11)
	var j1: Dictionary = a.commit(11)
	a.remember_commit(j1, a.state.encode())
	var r1: int = a.state.revision
	a.request(5, cmd("release", 2, 20), 21)
	var j2: Dictionary = a.commit(21)
	a.remember_commit(j2, a.state.encode())
	var r2: int = a.state.revision
	var dec = State.decode(a.state.encode())
	check("A01_revision_persists_after_release", r1 == r0 + 1 and r2 == r0 + 2 and dec != null and dec.revision == r2 \
		and a.state.phase == State.Phase.FREE, "rev %d->%d->%d" % [r0, r1, r2])
	var b = held_authority(5)
	var before: int = b.state.revision
	var freed: bool = b.release_peer(5, 30)
	check("A02_revision_persists_after_disconnect_release", freed and b.state.revision == before + 1 \
		and b.state.owner == 0 and b.state.phase == State.Phase.FREE)
	# Duplicado antes del commit.
	var c = held_authority(5)
	var rq1: Dictionary = c.request(5, cmd("throw", 2, 50), 40)
	var rq2: Dictionary = c.request(5, cmd("throw", 2, 50), 41)
	var commits := 0
	var accepted_result := {}
	for t in range(41, 60):
		var job: Dictionary = c.commit(t)
		if not job.is_empty():
			commits += 1
			accepted_result = c.remember_commit(job, c.state.encode())
	check("A03_duplicate_before_commit_single_job", rq1.status == "pending" and rq2.status == "pending" and commits == 1,
		"%s/%s commits=%d" % [rq1.status, rq2.status, commits])
	# Duplicado después del commit.
	var rev_after: int = c.state.revision
	var rq3: Dictionary = c.request(5, cmd("throw", 2, 50), 70)
	var again: Dictionary = c.commit(71)
	check("A04_duplicate_after_commit_returns_cached", rq3.get("status", "") == "accepted" and again.is_empty() \
		and c.state.revision == rev_after and rq3.get("state", PackedByteArray()) == accepted_result.get("state", null),
		"status=%s" % rq3.get("status", ""))
	# Expulsión de la caché: 300 rechazos de otro peer.
	for i in 300:
		c.request(9, cmd("release", 1000 + i, 80, 77), 80)
	var rq4: Dictionary = c.request(5, cmd("throw", 2, 50), 90)
	var again2: Dictionary = c.commit(91)
	check("A05_duplicate_after_cache_eviction_not_reexecuted", rq4.get("status", "") != "accepted" \
		and rq4.get("status", "") != "pending" and again2.is_empty() and c.state.revision == rev_after,
		"status=%s (no se reenvía resultado: el adaptador no responde a stale)" % rq4.get("status", ""))
	# Acción vieja.
	var e = held_authority(5)
	e.request(5, cmd("release", 10, 20), 21)
	var job_e: Dictionary = e.commit(21)
	e.remember_commit(job_e, e.state.encode())
	var old: Dictionary = e.request(5, cmd("grab", 4, 22), 23)
	check("A06_old_action_stale", old.status == "stale", old.status)
	# Sesión ajena y peer ajeno.
	var f = held_authority(5)
	var foreign: Dictionary = f.request(5, cmd("release", 2, 20, 99), 21)
	var other_peer: Dictionary = f.request(6, cmd("release", 2, 20, 1), 21)
	check("A07_foreign_session_rejected", foreign.status == "rejected" and foreign.get("reason", "") == "ownership",
		"%s %s" % [foreign.status, foreign.get("reason", "")])
	check("A07_foreign_peer_rejected", other_peer.status == "rejected" and other_peer.get("reason", "") == "ownership",
		"%s %s" % [other_peer.status, other_peer.get("reason", "")])
	# Identidad.
	var g = held_authority(5)
	var wrong_epoch: Dictionary = g.request(5, cmd("release", 3, 20, 1, 1, 2), 21)
	check("A08_wrong_epoch_rejected_identity", wrong_epoch.status == "rejected" and wrong_epoch.get("reason", "") == "identity")
	# Peticiones futuras.
	var h = held_authority(5)
	var fut: Dictionary = h.request(5, cmd("release", 2, 100 + 61), 100)
	check("A09_future_release_rejected", fut.status == "rejected" and fut.get("reason", "") == "future",
		"%s %s" % [fut.status, fut.get("reason", "")])
	var edge = held_authority(5)
	var at_edge: Dictionary = edge.request(5, cmd("release", 2, 100 + 60), 100)
	check("A09_release_at_window_edge_pending", at_edge.status == "pending", at_edge.status)
	var free_a = Authority.new()
	free_a.state.uid = 1
	var fut_grab: Dictionary = free_a.request(5, cmd("grab", 1, 1_000_000), 100)
	var fut_job: Dictionary = free_a.commit(100)
	check("A10_future_grab_rejected", fut_grab.get("status", "") == "rejected",
		"status=%s, commit_inmediato=%s: el agarre ignora el tick pedido" % [fut_grab.get("status", ""), not fut_job.is_empty()])
	# Suelta tardía: tick ya pasado se aplica ahora y se marca tarde.
	var l = held_authority(5)
	l.request(5, cmd("release", 2, 5), 50)
	var lj: Dictionary = l.commit(50)
	check("A11_past_release_applied_now_marked_late", not lj.is_empty() and lj.late and l.state.applied_tick == 50)
	# Suelta a tiempo: se programa en requested + 1.
	var o = held_authority(5)
	o.request(5, cmd("release", 2, 60), 55)
	var early_jobs := []
	for t in range(55, 62):
		var oj: Dictionary = o.commit(t)
		if not oj.is_empty(): early_jobs.append(t)
	check("A12_on_time_release_at_requested_plus_one", early_jobs == [61], str(early_jobs))
	# Dos agarres simultáneos.
	var s2 = Authority.new()
	s2.state.uid = 1
	var ga: Dictionary = s2.request(5, cmd("grab", 1, 10, 1), 11)
	var gb: Dictionary = s2.request(6, cmd("grab", 1, 10, 1), 11)
	check("A13_simultaneous_grab_single_owner", ga.status == "pending" and gb.status == "rejected" \
		and gb.get("reason", "") == "occupied", "%s / %s %s" % [ga.status, gb.status, gb.get("reason", "")])
	# Desconexión con pedido pendiente.
	var p = held_authority(5)
	p.request(5, cmd("release", 2, 40), 30)
	p.release_peer(5, 31)
	check("A14_disconnect_clears_pending", p.pending.is_empty() and p.commit(45).is_empty())
	# Validación de forma del comando.
	check("A15_throw_requires_unit_direction", not Authority.valid_command(cmd("throw", 3, 1, 1, 1, 1, Vector3(2, 0, 0))))
	var extra := cmd("release", 3, 1)
	extra["x"] = 1
	check("A15_extra_key_rejected", not Authority.valid_command(extra))
	var ftick := cmd("release", 3, 1)
	ftick["tick"] = 1.0
	check("A15_float_tick_rejected", not Authority.valid_command(ftick))
	check("A15_action_zero_rejected", not Authority.valid_command(cmd("release", 0, 1)))
	check("A15_session_zero_rejected", not Authority.valid_command(cmd("release", 3, 1, 0)))
	var nan_target := cmd("release", 3, 1)
	nan_target["target"] = Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0))
	check("A15_nan_target_rejected", not Authority.valid_command(nan_target))
