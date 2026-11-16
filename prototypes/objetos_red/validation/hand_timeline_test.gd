extends SceneTree

## Validación independiente (Claude), entrega 3: bandeja de entradas de mano
## (runtime/hand_timeline.gd) sola, sin main ni red. No modifica runtime/.
## Uso: Godot --headless --path prototypes/objetos_red --script res://validation/hand_timeline_test.gd -- --out=<ruta.json>
## Criterios: docs/net/validacion_objetos/criterios_entrega_3.md §4.2 (L01–L24).

const HandTimeline := preload("res://runtime/hand_timeline.gd")

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
	print("HAND_TIMELINE_DONE pass=%d fail=%d" % [results.filter(func(r): return r.ok == true).size(), fails])
	quit(0)

func check(id: String, ok, detail := "") -> void:
	results.append({"id": id, "ok": ok, "detail": detail})

func at(x: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, 1.0, 0.0))

func fr(uid: int, epoch: int, session: int, t: int, target := Transform3D.IDENTITY) -> Dictionary:
	if target == Transform3D.IDENTITY: target = at(float(t) * 0.001)
	return {"uid": uid, "epoch": epoch, "session": session, "tick": t, "target": target}

func tick_of(d: Dictionary) -> int:
	return int(d.get("tick", -1))

func _tests() -> void:
	# L01: antes de la concesión.
	var a := HandTimeline.new()
	var s01: String = a.accept(2, fr(1, 1, 5, 10), 5)
	var c01: Dictionary = a.consume(2, 1, 1, 5, 10, -1)
	check("L01_antes_de_la_concesion", s01 == "buffered" and tick_of(c01) == 10 and c01.get("target") == fr(1, 1, 5, 10).target,
		"accept %s; consume → %d" % [s01, tick_of(c01)])

	# L02: orden inverso.
	var b := HandTimeline.new()
	var st02 := [b.accept(2, fr(1, 1, 5, 105), 100), b.accept(2, fr(1, 1, 5, 104), 100), b.accept(2, fr(1, 1, 5, 103), 100)]
	var got02 := [tick_of(b.consume(2, 1, 1, 5, 103, 102)), tick_of(b.consume(2, 1, 1, 5, 104, 103)), tick_of(b.consume(2, 1, 1, 5, 105, 104))]
	check("L02_orden_inverso", st02 == ["buffered", "buffered", "buffered"] and got02 == [103, 104, 105], "%s → %s" % [st02, got02])

	# L03: la más reciente.
	var c := HandTimeline.new()
	for t in [101, 102, 103]: c.accept(2, fr(1, 1, 5, t), 100)
	var g03a := tick_of(c.consume(2, 1, 1, 5, 103, 100))
	var g03b := tick_of(c.consume(2, 1, 1, 5, 104, 103))
	check("L03_la_mas_reciente", g03a == 103 and g03b == -1, "consume(103) → %d; consume(104) → %d" % [g03a, g03b])

	# L04: nunca futura.
	var d := HandTimeline.new()
	d.accept(2, fr(1, 1, 5, 110), 100)
	var g04a := tick_of(d.consume(2, 1, 1, 5, 105, -1))
	var g04b := tick_of(d.consume(2, 1, 1, 5, 110, -1))
	check("L04_nunca_futura", g04a == -1 and g04b == 110, "consume(105) → %d; consume(110) → %d" % [g04a, g04b])

	# L05: nunca ya usada.
	var e := HandTimeline.new()
	e.accept(2, fr(1, 1, 5, 100), 100)
	var g05 := tick_of(e.consume(2, 1, 1, 5, 105, 100))
	check("L05_nunca_ya_usada", g05 == -1, "consume(105, último 100) → %d" % g05)

	# L06 y L07: duplicado y conflicto.
	var f := HandTimeline.new()
	var s06a: String = f.accept(2, fr(1, 1, 5, 50, at(0.5)), 50)
	var s06b: String = f.accept(2, fr(1, 1, 5, 50, at(0.5)), 50)
	var n06: int = f.pending_for(2, 1, 1, 5).size()
	check("L06_duplicado", s06a == "buffered" and s06b == "duplicate" and n06 == 1, "%s, %s; entradas %d" % [s06a, s06b, n06])
	var s07: String = f.accept(2, fr(1, 1, 5, 50, at(0.9)), 50)
	var c07: Dictionary = f.consume(2, 1, 1, 5, 50, -1)
	check("L07_conflicto", s07 == "conflicting_tick" and c07.get("target") == at(0.5),
		"%s; consume devuelve x = %s" % [s07, str(c07.target.origin.x) if c07.has("target") else "nada"])

	# L08: claves ajenas.
	var g := HandTimeline.new()
	g.accept(2, fr(1, 1, 5, 50), 50)
	var foreign := [g.consume(3, 1, 1, 5, 50, -1), g.consume(2, 2, 1, 5, 50, -1), g.consume(2, 1, 2, 5, 50, -1), g.consume(2, 1, 1, 6, 50, -1)]
	var g08 := tick_of(g.consume(2, 1, 1, 5, 50, -1))
	check("L08_claves_ajenas", foreign.all(func(x): return x.is_empty()) and g08 == 50,
		"peer/objeto/aparición/sesión ajenos → %s; clave correcta → %d" % [foreign.map(func(x): return tick_of(x)), g08])

	# L09: ventana.
	var h := HandTimeline.new()
	var st09 := [h.accept(2, fr(1, 1, 5, 80), 200), h.accept(2, fr(1, 1, 5, 79), 200), h.accept(2, fr(1, 1, 5, 260), 200), h.accept(2, fr(1, 1, 5, 261), 200)]
	check("L09_ventana", st09 == ["buffered", "outside_window", "buffered", "outside_window"], "80, 79, 260, 261 → %s" % [st09])

	# L10: caducidad.
	var i10 := HandTimeline.new()
	i10.accept(2, fr(1, 1, 5, 300), 300)
	i10.prune(420)
	var keep: bool = i10.pending_for(2, 1, 1, 5).has(300)
	i10.prune(421)
	var gone: bool = not i10.pending_for(2, 1, 1, 5).has(300)
	check("L10_caducidad", keep and gone, "en 420 sigue: %s; en 421 no está: %s" % [keep, gone])

	# L11, L13: capacidad de sesiones y liberación.
	var j := HandTimeline.new()
	var st11 := []
	for s in [1, 2, 3, 4, 5]: st11.append(j.accept(2, fr(1, 1, s, 500), 500))
	var s11b: String = j.accept(2, fr(1, 1, 1, 501), 500)
	check("L11_capacidad_de_sesiones", st11 == ["buffered", "buffered", "buffered", "buffered", "capacity"] and s11b == "buffered",
		"sesiones 1–5 → %s; otro tick de la sesión 1 → %s" % [st11, s11b])
	j.retire(2, 1, 1, 1, 500)
	var s13: String = j.accept(2, fr(1, 1, 5, 500), 500)
	check("L13_capacidad_liberada", s13 == "buffered", "después de retirar la sesión 1, sesión 5 → %s" % s13)

	# L12: capacidad de peers.
	var k := HandTimeline.new()
	var st12 := [k.accept(2, fr(1, 1, 5, 500), 500), k.accept(3, fr(1, 1, 5, 500), 500), k.accept(4, fr(1, 1, 5, 500), 500)]
	check("L12_capacidad_de_peers", st12 == ["buffered", "buffered", "capacity"], "peers 2, 3, 4 → %s" % [st12])

	# L14: retiro.
	var l := HandTimeline.new()
	l.accept(2, fr(1, 1, 5, 601), 600)
	l.accept(2, fr(1, 1, 6, 601), 600)
	l.retire(2, 1, 1, 5, 600)
	var s14: String = l.accept(2, fr(1, 1, 5, 602), 600)
	var c14 := tick_of(l.consume(2, 1, 1, 5, 602, -1))
	var s14b: String = l.accept(2, fr(1, 1, 6, 602), 600)
	var c14b := tick_of(l.consume(2, 1, 1, 6, 602, -1))
	check("L14_retiro", s14 == "retired" and c14 == -1 and s14b == "buffered" and c14b == 602,
		"retirada: %s, consume %d; otra sesión: %s, consume %d" % [s14, c14, s14b, c14b])

	# L15: caducidad del retiro.
	var m := HandTimeline.new()
	m.retire(2, 1, 1, 5, 700)
	var s15a: String = m.accept(2, fr(1, 1, 5, 820), 820)
	var s15b: String = m.accept(2, fr(1, 1, 5, 821), 821)
	check("L15_caducidad_del_retiro", null, "retirada en 700: en 820 → %s; en 821 → %s" % [s15a, s15b])

	# L16: límite de retirados.
	var n := HandTimeline.new()
	for s in range(1, 301): n.retire(2, 1, 1, s, 900)
	var size16: int = n._retired.size()
	var s16: String = n.accept(2, fr(1, 1, 1, 900), 900)
	check("L16_limite_de_retirados", size16 <= 256, "300 retiros → %d guardados; el primero vuelve a aceptarse: %s" % [size16, s16])

	# L17: desconexión.
	var o := HandTimeline.new()
	o.accept(2, fr(1, 1, 5, 1001), 1000)
	o.accept(3, fr(1, 1, 5, 1001), 1000)
	o.drop_peer(2)
	var c17a := tick_of(o.consume(2, 1, 1, 5, 1001, -1))
	var c17b := tick_of(o.consume(3, 1, 1, 5, 1001, -1))
	check("L17_desconexion", c17a == -1 and c17b == 1001, "peer 2 → %d; peer 3 → %d" % [c17a, c17b])

	# L18: inválidas.
	var p := HandTimeline.new()
	var missing := fr(1, 1, 5, 10)
	missing.erase("epoch")
	var st18 := [p.accept(0, fr(1, 1, 5, 10), 10), p.accept(-1, fr(1, 1, 5, 10), 10), p.accept(2, fr(0, 1, 5, 10), 10),
		p.accept(2, missing, 10), p.accept(2, fr(1, 1, 5, 10, Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0))), 10)]
	check("L18_invalidas", st18.all(func(x): return x == "invalid"), "peer 0, peer −1, objeto 0, sin aparición, NaN → %s" % [st18])

	# L19: reenvío de un tick ya usado.
	var q := HandTimeline.new()
	q.accept(2, fr(1, 1, 5, 103), 100)
	var c19 := tick_of(q.consume(2, 1, 1, 5, 103, 102))
	var s19: String = q.accept(2, fr(1, 1, 5, 103), 104)
	var c19b := tick_of(q.consume(2, 1, 1, 5, 104, 103))
	check("L19_reenvio_de_un_tick_usado_fisico", c19 == 103 and c19b == -1, "usado %d; después del reenvío, consume(104, último 103) → %d" % [c19, c19b])
	check("L19_reenvio_de_un_tick_usado_diagnostico", s19 == "duplicate", "estado del reenvío: %s (sin efecto físico)" % s19)

	# L20: objetivo contradictorio para un tick ya usado.
	var r := HandTimeline.new()
	r.accept(2, fr(1, 1, 5, 103, at(0.3)), 100)
	r.consume(2, 1, 1, 5, 103, 102)
	var s20: String = r.accept(2, fr(1, 1, 5, 103, at(0.7)), 104)
	var c20 := tick_of(r.consume(2, 1, 1, 5, 104, 103))
	check("L20_conflicto_de_un_tick_usado_fisico", c20 == -1, "consume(104, último 103) → %d" % c20)
	check("L20_conflicto_de_un_tick_usado_estado", null, "estado: %s" % s20)

	# L21: memoria acotada.
	var s := HandTimeline.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var now := 2000
	var max_keys := 0
	var max_ticks := 0
	var statuses := {}
	for i in 20000:
		if i % 100 == 0: now += rng.randi_range(0, 30)
		var st: String = s.accept(rng.randi_range(2, 5), fr(rng.randi_range(1, 3), rng.randi_range(1, 2), rng.randi_range(1, 10),
			rng.randi_range(now - 200, now + 100)), now)
		statuses[st] = statuses.get(st, 0) + 1
		max_keys = maxi(max_keys, s._slots.size())
		for slot: Dictionary in s._slots.values(): max_ticks = maxi(max_ticks, slot.frames.size())
	check("L21_memoria_acotada", max_keys <= 8 and max_ticks <= 181, "claves máx %d; ticks por clave máx %d; estados %s" % [max_keys, max_ticks, statuses])

	# L22: vista de inspección.
	var t22 := HandTimeline.new()
	t22.accept(2, fr(1, 1, 5, 50), 50)
	var view: Dictionary = t22.pending_for(2, 1, 1, 5)
	view.clear()
	var c22 := tick_of(t22.consume(2, 1, 1, 5, 50, -1))
	check("L22_vista_de_inspeccion", c22 == 50, "después de vaciar la vista, consume → %d" % c22)

	# L23: consumir borra lo pasado.
	var u := HandTimeline.new()
	for t in [101, 102, 103, 104, 105]: u.accept(2, fr(1, 1, 5, t), 100)
	u.consume(2, 1, 1, 5, 103, 100)
	var left: Array = u.pending_for(2, 1, 1, 5).keys()
	left.sort()
	check("L23_consumir_borra_lo_pasado", null, "después de consume(103) quedan %s" % [left])

	# L24: copia inmutable.
	var v := HandTimeline.new()
	var original := fr(1, 1, 5, 60, at(0.25))
	v.accept(2, original, 60)
	original.target = at(0.99)
	original.tick = 61
	var c24: Dictionary = v.consume(2, 1, 1, 5, 60, -1)
	check("L24_copia_inmutable", tick_of(c24) == 60 and c24.get("target") == at(0.25), "guardado: tick %d" % tick_of(c24))
