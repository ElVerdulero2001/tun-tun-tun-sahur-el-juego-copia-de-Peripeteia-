extends SceneTree

## Validación independiente (Claude), entrega 2: caminos nuevos de authority.gd
## (agarre programado por tick y salida dependiente de un agarre pendiente).
## Un proceso, sin red. No modifica runtime/. contract_test.gd queda sin cambios.
## Uso: Godot --headless --path prototypes/objetos_red --script res://validation/contract_test_e2.gd -- --out=<ruta.json>
## Criterios: docs/net/validacion_objetos/criterios_entrega_2.md (B01–B13).

const State := preload("res://runtime/state.gd")
const Authority := preload("res://runtime/authority.gd")

var results: Array = []
var out_path := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_path = a.trim_prefix("--out=")
	_tests()
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
	print("CONTRACT_E2_DONE pass=%d fail=%d" % [results.size() - fails, fails])
	quit(0)

func check(id: String, ok: bool, detail := "") -> void:
	results.append({"id": id, "ok": ok, "detail": detail})

func cmd(op: String, action: int, tick: int, session := 1, uid := 1) -> Dictionary:
	return {"op": op, "uid": uid, "epoch": 1, "session": session, "action": action, "tick": tick,
		"target": Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), "anchor": Vector3(0, 0.2, 0),
		"direction": Vector3(1, 0, 0) if op == "throw" else Vector3.ZERO}

func free_authority():
	var a = Authority.new()
	a.state.uid = 1
	return a

func held_by(peer: int):
	var a = free_authority()
	a.request(peer, cmd("grab", 1, 10), 11)
	a.remember_commit(a.commit(11), a.state.encode())
	return a

## Como main._commit: hasta dos commits por tick, en orden. Devuelve
## [{t, op, action, rev, late}] de todo lo aplicado en [from, to].
func run_commits(a, from: int, to: int) -> Array:
	var out := []
	for t in range(from, to + 1):
		for _attempt in 2:
			var job: Dictionary = a.commit(t)
			if job.is_empty(): break
			a.remember_commit(job, a.state.encode())
			out.append({"t": t, "op": job.command.op, "action": job.command.action, "rev": a.state.revision, "late": job.late})
	return out

func _tests() -> void:
	# B01: agarre a tiempo, en requested + 1.
	var b1 = free_authority()
	var r1: Dictionary = b1.request(5, cmd("grab", 1, 60), 55)
	var j1 := run_commits(b1, 55, 64)
	check("B01_on_time_grab_at_requested_plus_one", r1.status == "pending" and j1.size() == 1 and j1[0].t == 61 and not j1[0].late,
		"%s %s" % [r1.status, str(j1)])
	# B02: agarre con tick pasado, ahora y marcado tarde.
	var b2 = free_authority()
	b2.request(5, cmd("grab", 1, 5), 50)
	var j2 := run_commits(b2, 50, 50)
	check("B02_past_grab_applied_now_marked_late", j2.size() == 1 and j2[0].t == 50 and j2[0].late and b2.state.applied_tick == 50,
		str(j2))
	# B03: borde de la ventana futura para el agarre.
	var b3a = free_authority()
	var at_edge: Dictionary = b3a.request(5, cmd("grab", 1, 160), 100)
	var b3b = free_authority()
	var beyond: Dictionary = b3b.request(5, cmd("grab", 1, 161), 100)
	check("B03_grab_window_edge", at_edge.status == "pending" and beyond.status == "rejected" and beyond.get("reason", "") == "future",
		"%s / %s %s" % [at_edge.status, beyond.status, beyond.get("reason", "")])
	# B04: salida dependiente de un agarre pendiente del mismo peer y sesión.
	var b4 = free_authority()
	var rev0: int = b4.state.revision
	var g4: Dictionary = b4.request(5, cmd("grab", 1, 60), 55)
	var x4: Dictionary = b4.request(5, cmd("release", 2, 61), 56)
	var j4 := run_commits(b4, 55, 66)
	check("B04_dependent_exit_after_grab", g4.status == "pending" and x4.status == "pending" and j4.size() == 2 \
		and j4[0].op == "grab" and j4[0].t == 61 and j4[0].rev == rev0 + 1 \
		and j4[1].op == "release" and j4[1].t == 62 and j4[1].rev == rev0 + 2 \
		and b4.state.phase == State.Phase.FREE and b4.state.owner == 0 and b4.state.session == 0,
		"%s/%s %s" % [g4.status, x4.status, str(j4)])
	# B05: agarre y salida vencidos en el mismo tick: dos commits, en orden.
	var b5 = free_authority()
	var rev5: int = b5.state.revision
	b5.request(5, cmd("grab", 1, 5), 50)
	var x5: Dictionary = b5.request(5, cmd("throw", 2, 6), 50)
	var j5 := run_commits(b5, 50, 50)
	check("B05_same_tick_grab_then_exit", x5.status == "pending" and j5.size() == 2 and j5[0].op == "grab" and j5[1].op == "throw" \
		and j5[0].t == 50 and j5[1].t == 50 and j5[1].rev == rev5 + 2 and j5[0].late and j5[1].late,
		str(j5))
	# B06: salida de otro peer mientras el agarre está pendiente.
	var b6 = free_authority()
	b6.request(5, cmd("grab", 1, 60), 55)
	var x6: Dictionary = b6.request(6, cmd("release", 2, 61), 56)
	check("B06_other_peer_exit_rejected", x6.status == "rejected" and x6.get("reason", "") == "ownership",
		"%s %s" % [x6.status, x6.get("reason", "")])
	# B07: salida de otra sesión del mismo peer.
	var b7 = free_authority()
	b7.request(5, cmd("grab", 1, 60, 1), 55)
	var x7: Dictionary = b7.request(5, cmd("release", 2, 61, 2), 56)
	check("B07_other_session_exit_rejected", x7.status == "rejected" and x7.get("reason", "") == "ownership",
		"%s %s" % [x7.status, x7.get("reason", "")])
	# B08: duplicado de la salida pendiente, segunda salida distinta y duplicado posterior al commit.
	var b8 = free_authority()
	b8.request(5, cmd("grab", 1, 60), 55)
	var x8: Dictionary = b8.request(5, cmd("release", 2, 61), 56)
	var d8: Dictionary = b8.request(5, cmd("release", 2, 61), 57)
	var y8: Dictionary = b8.request(5, cmd("throw", 3, 61), 57)
	var j8 := run_commits(b8, 55, 66)
	var rev8: int = b8.state.revision
	var after8: Dictionary = b8.request(5, cmd("release", 2, 61), 70)
	var again8 := run_commits(b8, 70, 72)
	check("B08_exit_duplicate_and_second_exit", x8.status == "pending" and d8.status == "pending" \
		and y8.status == "rejected" and y8.get("reason", "") == "pending" and j8.size() == 2 \
		and after8.get("status", "") == "accepted" and again8.is_empty() and b8.state.revision == rev8,
		"%s/%s/%s %s; commits %d; post-commit %s" % [x8.status, d8.status, y8.status, y8.get("reason", ""), j8.size(), after8.get("status", "")])
	# B09: desconexión con agarre y salida pendientes.
	var b9 = free_authority()
	var rev9: int = b9.state.revision
	b9.request(5, cmd("grab", 1, 60), 55)
	b9.request(5, cmd("release", 2, 61), 56)
	var freed: bool = b9.release_peer(5, 57)
	var j9 := run_commits(b9, 57, 70)
	check("B09_disconnect_clears_grab_and_exit", not freed and b9.pending.is_empty() and b9.pending_exit.is_empty() \
		and j9.is_empty() and b9.state.revision == rev9 and b9.state.phase == State.Phase.FREE,
		"freed=%s commits=%d rev %d->%d" % [freed, j9.size(), rev9, b9.state.revision])
	# B10: agarre rechazado por ocupado; su salida no crea trabajo.
	var b10 = held_by(6)
	var g10: Dictionary = b10.request(5, cmd("grab", 1, 60), 55)
	var x10: Dictionary = b10.request(5, cmd("release", 2, 61), 56)
	check("B10_exit_after_rejected_grab", g10.status == "rejected" and g10.get("reason", "") == "occupied" \
		and x10.status == "rejected" and x10.get("reason", "") == "ownership" \
		and b10.pending.is_empty() and b10.pending_exit.is_empty() and run_commits(b10, 55, 70).is_empty(),
		"%s %s / %s %s" % [g10.status, g10.get("reason", ""), x10.status, x10.get("reason", "")])
	# B11: salida futura mientras el agarre está pendiente.
	var b11 = free_authority()
	b11.request(5, cmd("grab", 1, 60), 55)
	var x11: Dictionary = b11.request(5, cmd("release", 2, 55 + 61), 55)
	check("B11_future_dependent_exit_rejected", x11.status == "rejected" and x11.get("reason", "") == "future",
		"%s %s" % [x11.status, x11.get("reason", "")])
	# B12: salida con tick menor que el de su agarre.
	var b12 = free_authority()
	b12.request(5, cmd("grab", 1, 60), 55)
	var x12: Dictionary = b12.request(5, cmd("release", 2, 50), 56)
	var j12 := run_commits(b12, 56, 66)
	check("B12_exit_never_before_its_grab", x12.status == "pending" and j12.size() == 2 and j12[0].op == "grab" \
		and j12[1].op == "release" and j12[1].t >= j12[0].t,
		"%s %s" % [x12.status, str(j12)])
	# B13: acción vieja con trabajos pendientes.
	var b13 = free_authority()
	b13.request(5, cmd("grab", 5, 60), 55)
	var old13: Dictionary = b13.request(5, cmd("release", 3, 61), 56)
	check("B13_old_action_stale_with_pending", old13.status == "stale" and b13.pending_exit.is_empty(),
		"%s" % old13.status)
