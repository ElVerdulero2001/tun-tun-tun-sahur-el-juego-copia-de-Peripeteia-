extends SceneTree

## Validación independiente (Claude), entrega 3: el receptor de respuestas
## (main._receive_result) con respuestas malformadas. Modo solo, sin red. No
## modifica main.gd ni runtime/. Se fija un agarre pendiente artificial y se
## compara una huella del estado del adaptador antes y después de cada respuesta.
## Uso: Godot --headless --path prototypes/objetos_red --script res://validation/response_receiver_test.gd -- --out=<json> --trace=<jsonl>
## Criterios: docs/net/validacion_objetos/criterios_entrega_3.md §4.4 (M01–M23, V1, P1, P2).

const MainScene := preload("res://main.tscn")
const State := preload("res://runtime/state.gd")

var results: Array = []
var out_path := ""
var trace_path := ""
var _done := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_path = a.trim_prefix("--out=")
		elif a.begins_with("--trace="): trace_path = a.trim_prefix("--trace=")

## En _initialize la raíz todavía no está en el árbol (fingerprint_test, 2026-11-16).
func _process(_delta: float) -> bool:
	if _done: return false
	_done = true
	_run()
	return false

func check(id: String, ok, detail := "") -> void:
	results.append({"id": id, "ok": ok, "detail": detail})

func snap(m: Node) -> String:
	var parts: Array = [m._pending_grab, m._pending_grab_uid, m.local_uid, m._dependent, m._dependent_command]
	for uid: int in m.objects:
		var o: Dictionary = m.objects[uid]
		parts.append_array([o.state.encode(), o.predicted_state.encode(), o.pending, o.prediction.active,
			o.body.held, o.body.impulse_count])
	return var_to_str(parts)

func _run() -> void:
	var m: Node = MainScene.instantiate()
	root.add_child(m)
	# Agarre pendiente artificial: lo que un rechazo legítimo cancelaría.
	m._pending_grab = 999
	m._pending_grab_uid = 1
	m.objects[1].pending = 999

	var s1 = m.objects[1].state.copy()
	var good1 = s1.copy()
	good1.revision += 1
	good1.action = 1234
	var good1_bytes: PackedByteArray = good1.encode()
	var other = m.objects[2].state.copy()
	other.revision += 1
	other.action = 1234
	var other_bytes: PackedByteArray = other.encode()
	var nan_bytes := good1_bytes.duplicate()
	nan_bytes.encode_float(54, NAN) # primer componente del cuaternión (4 + 8·4 + 2 + 3·4 = 50 → x en 50; 54 = y)
	var zeros := PackedByteArray()
	zeros.resize(90)

	var malformed := [
		["M01_vacia", {}],
		["M02_stale_sin_identificadores", {"status": "stale"}],
		["M03_sin_uid", {"status": "rejected", "reason": "occupied", "action": 999}],
		["M04_sin_action", {"status": "rejected", "reason": "occupied", "uid": 1}],
		["M05_action_0", {"status": "rejected", "reason": "occupied", "action": 0, "uid": 1}],
		["M06_action_negativa", {"status": "rejected", "reason": "occupied", "action": -1, "uid": 1}],
		["M07_action_float", {"status": "rejected", "reason": "occupied", "action": 999.0, "uid": 1}],
		["M08_action_texto", {"status": "rejected", "reason": "occupied", "action": "999", "uid": 1}],
		["M09_uid_0", {"status": "rejected", "reason": "occupied", "action": 999, "uid": 0}],
		["M10_uid_grande", {"status": "rejected", "reason": "occupied", "action": 999, "uid": 0x80000000}],
		["M11_uid_float", {"status": "rejected", "reason": "occupied", "action": 999, "uid": 1.0}],
		["M12_status_pending", {"status": "pending", "action": 999, "uid": 1}],
		["M13_status_numerico", {"status": 3, "action": 999, "uid": 1}],
		["M14_accepted_sin_state", {"status": "accepted", "action": 1234, "uid": 1, "late": false}],
		["M15_state_vacio", {"status": "accepted", "action": 1234, "uid": 1, "late": false, "state": PackedByteArray()}],
		["M16_state_89_bytes", {"status": "accepted", "action": 1234, "uid": 1, "late": false, "state": good1_bytes.slice(0, 89)}],
		["M17_state_ceros", {"status": "accepted", "action": 1234, "uid": 1, "late": false, "state": zeros}],
		["M18_state_de_otra_caja", {"status": "accepted", "action": 1234, "uid": 1, "late": false, "state": other_bytes}],
		["M19_state_de_otra_accion", {"status": "accepted", "action": 1235, "uid": 1, "late": false, "state": good1_bytes}],
		["M20_state_array", {"status": "accepted", "action": 1234, "uid": 1, "late": false, "state": Array(good1_bytes)}],
		["M21_reason_numerico", {"status": "rejected", "reason": 5, "action": 999, "uid": 1}],
		["M22_late_texto", {"status": "accepted", "action": 1234, "uid": 1, "late": "no", "state": good1_bytes}],
		["M23_state_cuaternion_nan", {"status": "accepted", "action": 1234, "uid": 1, "late": false, "state": nan_bytes}],
	]
	var expected_kinds: Array = []
	for item in malformed:
		var before := snap(m)
		m._receive_result(item[1])
		var after := snap(m)
		expected_kinds.append(["discarded_result", item[0]])
		check(item[0], before == after, "huella %s" % ("igual" if before == after else "CAMBIÓ"))

	# V1: bien formada para un objeto que no existe.
	var b_v1 := snap(m)
	m._receive_result({"status": "rejected", "reason": "occupied", "action": 5, "uid": 99})
	expected_kinds.append(["result", "V1_objeto_inexistente"])
	check("V1_objeto_inexistente", b_v1 == snap(m), "huella igual: %s" % (b_v1 == snap(m)))

	# P1: control con efecto (rechazo del agarre pendiente).
	m._receive_result({"status": "rejected", "reason": "occupied", "action": 999, "uid": 1})
	expected_kinds.append(["result", "P1_control_rechazo"])
	check("P1_control_rechazo", m._pending_grab == 0 and m._pending_grab_uid == 0 and m.objects[1].pending == 0,
		"agarre pendiente después: %d" % m._pending_grab)

	# P2: control con efecto (aceptado coherente).
	var rev_before: int = m.objects[1].state.revision
	m._receive_result({"status": "accepted", "action": 1234, "uid": 1, "late": false, "state": good1_bytes})
	expected_kinds.append(["result", "P2_control_aceptado"])
	check("P2_control_aceptado", m.objects[1].state.revision == good1.revision and rev_before != good1.revision,
		"revisión %d → %d" % [rev_before, m.objects[1].state.revision])

	root.remove_child(m)
	m.free() # cierra la traza
	var kinds: Array = []
	for line in FileAccess.get_file_as_string(trace_path).split("\n", false):
		var v = JSON.parse_string(line)
		if typeof(v) == TYPE_DICTIONARY and v.kind in ["result", "discarded_result"]: kinds.append(v)
	var seq_ok := kinds.size() == expected_kinds.size()
	var mismatches := []
	for i in mini(kinds.size(), expected_kinds.size()):
		if kinds[i].kind != expected_kinds[i][0]:
			seq_ok = false
			mismatches.append("%s: %s" % [expected_kinds[i][1], kinds[i].kind])
	check("M00_traza_en_orden", seq_ok, "%d registros, esperados %d; distintos %s; causas %s" % [kinds.size(), expected_kinds.size(), mismatches,
		_hist(kinds.filter(func(k): return k.kind == "discarded_result").map(func(k): return k.cause))])

	var fails := 0
	for r in results:
		if r.ok == false: fails += 1
	var text := JSON.stringify({"schema": 1, "results": results, "fails": fails}, "  ", false, true)
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	for r in results:
		print("%s %s %s" % ["PASS" if r.ok == true else ("FAIL" if r.ok == false else "INFO"), r.id, r.detail])
	print("RESPONSE_RECEIVER_DONE pass=%d fail=%d" % [results.filter(func(r): return r.ok == true).size(), fails])
	quit(0)

func _hist(arr: Array) -> Dictionary:
	var h := {}
	for x in arr: h[x] = h.get(x, 0) + 1
	return h
