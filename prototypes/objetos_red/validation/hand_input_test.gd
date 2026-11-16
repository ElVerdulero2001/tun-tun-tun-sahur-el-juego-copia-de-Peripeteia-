extends SceneTree

## Validación independiente (Claude), entrega 3: formato binario de entradas de
## mano (runtime/hand_input.gd). Un proceso, sin red. No modifica runtime/.
## Bytes armados a mano: enteros u32 little-endian con desplazamientos de bits,
## float32 con PackedByteArray.encode_float.
## Uso: Godot --headless --path prototypes/objetos_red --script res://validation/hand_input_test.gd -- --out=<ruta.json>
## Criterios: docs/net/validacion_objetos/criterios_entrega_3.md §4.1 (I01–I16b).

const HandInput := preload("res://runtime/hand_input.gd")
const Authority := preload("res://runtime/authority.gd")

var results: Array = []
var out_path := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_path = a.trim_prefix("--out=")
	_tests()
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
	print("HAND_INPUT_DONE pass=%d fail=%d" % [results.filter(func(r): return r.ok == true).size(), fails])
	quit(0)

func check(id: String, ok, detail := "") -> void:
	results.append({"id": id, "ok": ok, "detail": detail})

# ------------------------------------------------------------------ bytes a mano
func u32(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)
	b.append((v >> 16) & 0xFF)
	b.append((v >> 24) & 0xFF)

func f32(b: PackedByteArray, v: float) -> void:
	var t := PackedByteArray()
	t.resize(4)
	t.encode_float(0, v)
	b.append_array(t)

func header(count: int, magic := 0x4849, version := 1) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(magic & 0xFF)
	b.append((magic >> 8) & 0xFF)
	b.append(version)
	b.append(count)
	return b

func rec(uid: int, epoch: int, session: int, t: int, pos: Vector3, q: Quaternion) -> PackedByteArray:
	var b := PackedByteArray()
	for v in [uid, epoch, session, t]: u32(b, v)
	for v in [pos.x, pos.y, pos.z, q.x, q.y, q.z, q.w]: f32(b, v)
	return b

func packet(recs: Array, count := -1) -> PackedByteArray:
	var b := header(recs.size() if count < 0 else count)
	for r in recs: b.append_array(r)
	return b

func fr(uid: int, epoch: int, session: int, t, basis: Basis, pos: Vector3) -> Dictionary:
	return {"uid": uid, "epoch": epoch, "session": session, "tick": t, "target": Transform3D(basis, pos)}

# Ángulo entre giros en doble precisión (no usa acos cerca de 1).
func qang(a: Quaternion, b: Quaternion) -> float:
	var ax: float = a.x; var ay: float = a.y; var az: float = a.z; var aw: float = a.w
	var bx: float = b.x; var by: float = b.y; var bz: float = b.z; var bw: float = b.w
	var na := sqrt(ax * ax + ay * ay + az * az + aw * aw)
	var nb := sqrt(bx * bx + by * by + bz * bz + bw * bw)
	ax /= na; ay /= na; az /= na; aw /= na
	bx /= nb; by /= nb; bz /= nb; bw /= nb
	# conj(a) * b
	var rx := aw * bx - ax * bw - ay * bz + az * by
	var ry := aw * by + ax * bz - ay * bw - az * bx
	var rz := aw * bz - ax * by + ay * bx - az * bw
	var rw := aw * bw + ax * bx + ay * by + az * bz
	return 2.0 * atan2(sqrt(rx * rx + ry * ry + rz * rz), absf(rw))

func rand_unit_q(rng: RandomNumberGenerator) -> Quaternion:
	var q := Quaternion(rng.randfn(), rng.randfn(), rng.randfn(), rng.randfn())
	while q.length_squared() < 1e-6:
		q = Quaternion(rng.randfn(), rng.randfn(), rng.randfn(), rng.randfn())
	return q.normalized()

func orthonormal(b: Basis) -> bool:
	return absf(b.determinant() - 1.0) < 1e-5 and b.is_equal_approx(b.orthonormalized())

# ------------------------------------------------------------------ pruebas
func _tests() -> void:
	var q0 := Quaternion(0.1, 0.2, 0.3, 0.9).normalized()
	var pos := Vector3(1.5, -2.25, 0.125)
	var r1 := rec(7, 3, 11, 1234, pos, q0)

	# I01: disposición de bytes del codificador.
	var enc: PackedByteArray = HandInput.encode([fr(7, 3, 11, 1234, Basis(q0), pos)])
	var expected_prefix := header(1)
	for v in [7, 3, 11, 1234]: u32(expected_prefix, v)
	var ok01 := enc.size() == 48 and enc.slice(0, 20) == expected_prefix
	var qd := Quaternion()
	if enc.size() == 48:
		ok01 = ok01 and enc.decode_float(20) == 1.5 and enc.decode_float(24) == -2.25 and enc.decode_float(28) == 0.125
		qd = Quaternion(enc.decode_float(32), enc.decode_float(36), enc.decode_float(40), enc.decode_float(44))
		ok01 = ok01 and qang(qd, q0) <= 1e-6
	# Corrección del instrumento (intento 1): GDScript no admite %e; se usa String.num_scientific.
	check("I01_disposicion", ok01, "size %d; prefijo %s; giro %s rad" % [enc.size(),
		enc.slice(0, 20).hex_encode(), String.num_scientific(qang(qd, q0) if enc.size() == 48 else -1.0)])

	# I02: decodifica bytes armados a mano.
	var d2: Array = HandInput.decode(packet([r1]))
	var ok02 := d2.size() == 1
	var ang2 := -1.0
	if ok02:
		var f: Dictionary = d2[0]
		ang2 = qang(f.target.basis.get_rotation_quaternion(), q0)
		ok02 = f.uid == 7 and f.epoch == 3 and f.session == 11 and f.tick == 1234 \
			and f.target.origin == pos and ang2 <= 1e-6
	check("I02_decodifica_bytes_a_mano", ok02, "registros %d; giro %s rad" % [d2.size(), String.num_scientific(ang2)])

	# I03: cantidades.
	var six: Array = []
	for i in 6: six.append(rec(7, 3, 11, 1000 + i, pos, q0))
	var seven: Array = six.duplicate()
	seven.append(rec(7, 3, 11, 1006, pos, q0))
	var c0: Array = HandInput.decode(header(0))
	var c1: Array = HandInput.decode(packet([r1]))
	var p6 := packet(six)
	var c6: Array = HandInput.decode(p6)
	var p7 := packet(seven)
	var c7: Array = HandInput.decode(p7)
	var c7b: Array = HandInput.decode(packet(six, 7))
	check("I03_cantidades", c0.is_empty() and c1.size() == 1 and p6.size() == 268 and c6.size() == 6
		and p7.size() == 312 and c7.is_empty() and c7b.is_empty(),
		"0→%d, 1→%d, 6 (%d B)→%d, 7 (%d B)→%d, cabecera 7 con 268 B→%d" % [c0.size(), c1.size(), p6.size(), c6.size(), p7.size(), c7.size(), c7b.size()])

	# I04: tamaños.
	var short := PackedByteArray([0x49, 0x48, 0x01])
	var p1 := packet([r1])
	var p47 := p1.slice(0, 47)
	var p49 := p1.duplicate()
	p49.append(0)
	var p2c := packet([r1], 2)
	var p269 := p6.duplicate()
	p269.append(0)
	var sizes := [HandInput.decode(short).size(), HandInput.decode(p47).size(), HandInput.decode(p49).size(),
		HandInput.decode(p2c).size(), HandInput.decode(p269).size()]
	check("I04_tamanios", sizes == [0, 0, 0, 0, 0], "3 B, 47 B, 49 B, cantidad 2 con 48 B, 269 B → %s" % [sizes])

	# I05: magia y versión.
	var bad_magic := header(1, 0x4948) + r1
	var v0 := header(1, 0x4849, 0) + r1
	var v2 := header(1, 0x4849, 2) + r1
	var mv := [HandInput.decode(bad_magic).size(), HandInput.decode(v0).size(), HandInput.decode(v2).size()]
	check("I05_magia_y_version", mv == [0, 0, 0], "magia invertida, versión 0, versión 2 → %s" % [mv])

	# I06: identificadores.
	var id_detail := []
	var ok06 := true
	for field in ["uid", "epoch", "session"]:
		for value in [0, 0x80000000, 0xFFFFFFFF, 0x7FFFFFFF]:
			var ids := {"uid": 7, "epoch": 3, "session": 11}
			ids[field] = value
			var out: Array = HandInput.decode(packet([rec(ids.uid, ids.epoch, ids.session, 1234, pos, q0)]))
			var want := 1 if value == 0x7FFFFFFF else 0
			var good: bool = out.size() == want and (want == 0 or out[0][field] == value)
			ok06 = ok06 and good
			id_detail.append("%s=%d→%d" % [field, value, out.size()])
	for value in [0, 0x7FFFFFFF, 0x80000000]:
		var out: Array = HandInput.decode(packet([rec(7, 3, 11, value, pos, q0)]))
		var want := 0 if value == 0x80000000 else 1
		var good: bool = out.size() == want and (want == 0 or out[0].tick == value)
		ok06 = ok06 and good
		id_detail.append("tick=%d→%d" % [value, out.size()])
	check("I06_identificadores", ok06, ", ".join(id_detail))

	# I07: posición no finita.
	var nf := []
	for axis in 3:
		for v in [NAN, INF, -INF]:
			var p := pos
			p[axis] = v
			nf.append(HandInput.decode(packet([rec(7, 3, 11, 1234, p, q0)])).size())
	check("I07_posicion_no_finita", nf.all(func(x): return x == 0), "9 casos → %s" % [nf])

	# I08: cuaterniones.
	var bad_q := [Quaternion(NAN, 0, 0, 1), Quaternion(INF, 0, 0, 1), Quaternion(0, 0, 0, 0),
		Quaternion(0, 0, 0, 2), Quaternion(0, 0, 0, 1.1)]
	var bq := []
	for q in bad_q: bq.append(HandInput.decode(packet([rec(7, 3, 11, 1234, pos, q)])).size())
	var unit_out: Array = HandInput.decode(packet([rec(7, 3, 11, 1234, pos, q0)]))
	var unit_ok := unit_out.size() == 1 and orthonormal(unit_out[0].target.basis)
	check("I08_cuaterniones", bq == [0, 0, 0, 0, 0] and unit_ok,
		"NaN, ∞, cero, (0,0,0,2), (0,0,0,1,1) → %s; unitario float32 aceptado y ortonormal: %s" % [bq, unit_ok])

	# I09: un registro inválido entre seis.
	var mixed := six.duplicate()
	mixed[3] = rec(0, 3, 11, 1003, pos, q0)
	var m9: Array = HandInput.decode(packet(mixed))
	check("I09_un_registro_invalido", m9.is_empty(), "→ %d registros" % m9.size())

	# I10: máximo de 268 bytes.
	var valid6: Array = []
	for i in 6: valid6.append(fr(7, 3, 11, 1000 + i, Basis(q0), pos))
	var e6: PackedByteArray = HandInput.encode(valid6)
	var e1: PackedByteArray = HandInput.encode([valid6[0]])
	check("I10_maximo", HandInput.MAX_PACKET_BYTES == 268 and e6.size() == 268 and e1.size() == 48,
		"MAX_PACKET_BYTES %d; 6 registros %d B; 1 registro %d B" % [HandInput.MAX_PACKET_BYTES, e6.size(), e1.size()])

	# I11: el codificador rechaza entradas inválidas.
	var ok_frame := fr(7, 3, 11, 1234, Basis(q0), pos)
	var bad_frames := {
		"NaN": fr(7, 3, 11, 1234, Basis(q0), Vector3(NAN, 0, 0)),
		"inf": fr(7, 3, 11, 1234, Basis(q0), Vector3(INF, 0, 0)),
		"escalada": fr(7, 3, 11, 1234, Basis.from_scale(Vector3(1.1, 1.1, 1.1)), pos),
		"det1_no_ortonormal": fr(7, 3, 11, 1234, Basis.from_scale(Vector3(2.0, 0.5, 1.0)), pos),
		"uid0": fr(0, 3, 11, 1234, Basis(q0), pos),
		"epoch0": fr(7, 0, 11, 1234, Basis(q0), pos),
		"session0": fr(7, 3, 0, 1234, Basis(q0), pos),
		"tick-1": fr(7, 3, 11, -1, Basis(q0), pos),
		"tick_float": fr(7, 3, 11, 2.5, Basis(q0), pos),
		"uid_grande": fr(0x80000000, 3, 11, 1234, Basis(q0), pos),
	}
	var missing := ok_frame.duplicate()
	missing.erase("session")
	bad_frames["falta_clave"] = missing
	var extra := ok_frame.duplicate()
	extra["foo"] = 1
	bad_frames["clave_de_mas"] = extra
	var accepted_bad := []
	for k in bad_frames:
		if not HandInput.encode([bad_frames[k]]).is_empty(): accepted_bad.append(k)
	var seven_frames: Array = valid6.duplicate()
	seven_frames.append(ok_frame)
	if not HandInput.encode([]).is_empty(): accepted_bad.append("vacia")
	if not HandInput.encode(seven_frames).is_empty(): accepted_bad.append("siete")
	if not HandInput.encode([5]).is_empty(): accepted_bad.append("no_diccionario")
	check("I11_codificador_rechaza", accepted_bad.is_empty() and not HandInput.encode([ok_frame]).is_empty(),
		"aceptadas por error: %s (de %d casos)" % [accepted_bad, bad_frames.size() + 3])

	# I12: ida y vuelta aleatoria.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261116
	var max_pos := 0.0
	var max_ang := 0.0
	var id_bad := 0
	var empty := 0
	for _set in 1000:
		var frames: Array = []
		for _i in rng.randi_range(1, 6):
			var p := Vector3(rng.randf_range(-20, 20), rng.randf_range(-20, 20), rng.randf_range(-20, 20))
			frames.append(fr(rng.randi_range(1, 0x7FFFFFFF), rng.randi_range(1, 0x7FFFFFFF),
				rng.randi_range(1, 0x7FFFFFFF), rng.randi_range(0, 0x7FFFFFFF), Basis(rand_unit_q(rng)), p))
		var out: Array = HandInput.decode(HandInput.encode(frames))
		if out.size() != frames.size():
			empty += 1
			continue
		for i in frames.size():
			var a: Dictionary = frames[i]
			var b: Dictionary = out[i]
			if a.uid != b.uid or a.epoch != b.epoch or a.session != b.session or a.tick != b.tick: id_bad += 1
			for axis in 3: max_pos = maxf(max_pos, absf(a.target.origin[axis] - b.target.origin[axis]))
			max_ang = maxf(max_ang, qang(a.target.basis.get_rotation_quaternion(), b.target.basis.get_rotation_quaternion()))
	check("I12_ida_y_vuelta", empty == 0 and id_bad == 0 and max_pos <= 1e-6 and max_ang <= 1e-6,
		"conjuntos perdidos %d; identificadores distintos %d; posición máx %s m; giro máx %s rad" % [empty, id_bad,
			String.num_scientific(max_pos), String.num_scientific(max_ang)])

	# I13: orden del paquete.
	var o13: Array = HandInput.decode(packet([rec(7, 3, 11, 5, pos, q0), rec(7, 3, 11, 3, pos, q0), rec(7, 3, 11, 4, pos, q0)]))
	check("I13_orden", null, "ticks decodificados %s (paquete 5, 3, 4)" % [o13.map(func(f): return f.tick)])

	# I14: tick repetido en un paquete.
	var o14: Array = HandInput.decode(packet([rec(7, 3, 11, 5, pos, q0), rec(7, 3, 11, 5, pos + Vector3(0, 1, 0), q0)]))
	check("I14_tick_repetido_en_un_paquete", null, "dos registros del tick 5 con objetivos distintos → %d registros" % o14.size())

	# I15: fuzz.
	var fz := RandomNumberGenerator.new()
	fz.seed = 777
	var inconsistent := 0
	var nonempty := 0
	for n in 6000:
		var bytes := PackedByteArray()
		if n < 3000:
			if n % 2 == 0:
				for _i in fz.randi_range(0, 300): bytes.append(fz.randi_range(0, 255))
			else:
				var count := fz.randi_range(0, 7)
				bytes = header(count)
				for _i in count * 44: bytes.append(fz.randi_range(0, 255))
		else:
			var recs: Array = []
			for i in fz.randi_range(1, 6):
				recs.append(rec(fz.randi_range(1, 1000), fz.randi_range(1, 10), fz.randi_range(1, 100), fz.randi_range(0, 100000),
					Vector3(fz.randf_range(-5, 5), fz.randf_range(-5, 5), fz.randf_range(-5, 5)), rand_unit_q(fz)))
			bytes = packet(recs)
			bytes[fz.randi_range(0, bytes.size() - 1)] = fz.randi_range(0, 255)
		var out: Array = HandInput.decode(bytes)
		if out.is_empty(): continue
		nonempty += 1
		var good := out.size() >= 1 and out.size() <= 6 and bytes.size() == 4 + 44 * out.size()
		for f in out: good = good and HandInput.valid(f)
		if not good: inconsistent += 1
	check("I15_fuzz", inconsistent == 0, "6000 entradas; %d decodificadas; %d inconsistentes" % [nonempty, inconsistent])

	# I16: rotación acumulada con la fórmula de main.gd _unhandled_input.
	var b := Basis.IDENTITY
	var cam_x := Vector3(1, 0, 0) # camera.global_basis.x de main.gd al arrancar (cámara sin girar)
	var first_fail := -1
	var events := 0
	for i in 200000:
		var dx := float(((i * 7) % 11) - 5)
		var dy := float(((i * 5) % 7) - 3)
		b = Basis(Vector3.UP, -dx * 0.004) * b
		b = Basis(cam_x, -dy * 0.004) * b
		events = i + 1
		if not HandInput.valid(fr(1, 1, 1, 0, b, Vector3(0, 1, 0))):
			first_fail = events
			break
	var det_err := absf(b.determinant() - 1.0)
	var cmd := {"op": "grab", "uid": 1, "epoch": 1, "session": 1, "action": 1, "tick": 0,
		"target": Transform3D(b, Vector3(0, 1, 0)), "anchor": Vector3(0, 0.2, 0), "direction": Vector3.ZERO}
	var bbt := b * b.transposed()
	var ortho_err := 0.0
	for r in 3:
		for c in 3: ortho_err = maxf(ortho_err, absf(bbt[c][r] - (1.0 if r == c else 0.0)))
	check("I16_rotacion_de_main_codificable", first_fail == -1 or first_fail > 20000,
		"primer evento no codificable: %s; al final |det−1| %s y máx |B·Bᵀ − I| %s; valid_command acepta esa base: %s" % [
			"ninguno en 200000" if first_fail == -1 else str(first_fail), String.num_scientific(det_err),
			String.num_scientific(ortho_err), Authority.valid_command(cmd)])

	# I16b: asimetría entre la orden de agarre y la mano.
	var sk := Basis.from_scale(Vector3(1.004, 1.0, 1.0 / 1.004))
	var cmd_b := cmd.duplicate()
	cmd_b.target = Transform3D(sk, Vector3(0, 1, 0))
	check("I16b_asimetria_con_la_orden", null, "base det %.6f no ortonormal: valid_command=%s, HandInput.valid=%s" % [
		sk.determinant(), Authority.valid_command(cmd_b), HandInput.valid(fr(1, 1, 1, 0, sk, Vector3(0, 1, 0)))])
