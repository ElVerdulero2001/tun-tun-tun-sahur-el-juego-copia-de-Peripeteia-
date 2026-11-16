extends SceneTree

## Validación independiente (Claude), entrega 4 (criterios_entrega_5.md, parte A):
## registro "seen" de hand_timeline.gd después de consumir, su caducidad y sus
## límites, sin reutilización física. Prueba pura, sin escena ni red.
## Uso: Godot --headless --path prototypes/objetos_red --script res://validation/hand_timeline_seen_test.gd -- --out=<json>

const Timeline := preload("res://runtime/hand_timeline.gd")
var results: Array = []
var out_path := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_path = a.trim_prefix("--out=")
	var t0 := Time.get_ticks_msec()
	_s01_duplicate_window()
	_s02_conflict_window()
	_s03_bounded()
	_s04_slot_lifetime()
	_s05_retire()
	_s06_drop_peer()
	_s07_flood()
	_finish(Time.get_ticks_msec() - t0)

func check(id: String, ok, detail := "") -> void:
	results.append({"id": id, "ok": ok, "detail": str(detail)})

func fr(tick: int, x := 0.0, session := 50, uid := 1, epoch := 1) -> Dictionary:
	return {"uid": uid, "epoch": epoch, "session": session, "tick": tick, "target": Transform3D(Basis.IDENTITY, Vector3(x, 0.7, 0))}

func hist(arr: Array) -> Dictionary:
	var h := {}
	for x in arr: h[x] = h.get(x, 0) + 1
	return h

# S01: tick 100 consumido; reenviado igual en cada "ahora" de 101 a 300.
func _s01_duplicate_window() -> void:
	var tl := Timeline.new()
	tl.accept(2, fr(100, 0.1), 100)
	var used := tl.consume(2, 1, 1, 50, 100, 99)
	var statuses: Array = []
	var reused := 0
	var buffered_at: Array = []
	for now in range(101, 301):
		var st: String = tl.accept(2, fr(100, 0.1), now)
		statuses.append(st)
		if st == "buffered": buffered_at.append(now)
		var c := tl.consume(2, 1, 1, 50, now, 100)
		if not c.is_empty() and c.tick == 100: reused += 1
	var h := hist(statuses)
	var dup_until := -1
	for i in statuses.size():
		if statuses[i] == "duplicate": dup_until = 101 + i
	check("S01_duplicado_tras_consumir", used.get("tick", -1) == 100 and buffered_at.is_empty() and reused == 0
		and h.keys().all(func(k): return k in ["duplicate", "outside_window"]),
		"estados %s; último duplicate en ahora=%d; vuelve a bandeja en %s; reutilizado %d" % [h, dup_until, buffered_at, reused])

# S02: lo mismo con otro objetivo.
func _s02_conflict_window() -> void:
	var tl := Timeline.new()
	tl.accept(2, fr(100, 0.1), 100)
	tl.consume(2, 1, 1, 50, 100, 99)
	var statuses: Array = []
	var reused := 0
	for now in range(101, 301):
		statuses.append(tl.accept(2, fr(100, 0.9), now))
		var c := tl.consume(2, 1, 1, 50, now, 100)
		if not c.is_empty() and c.tick == 100: reused += 1
	var h := hist(statuses)
	check("S02_conflicto_tras_consumir", reused == 0 and not h.has("buffered") and h.keys().all(func(k): return k in ["conflicting_tick", "outside_window"]),
		"estados %s; reutilizado %d" % [h, reused])

# S03: una sesión durante 10.000 ticks, seis entradas redundantes por tick.
func _s03_bounded() -> void:
	var tl := Timeline.new()
	var max_seen := 0
	var max_frames := 0
	var used := 0
	var last := 0
	for now in range(1, 10001):
		for k in 6:
			var t := now + 3 - k
			if t > 0: tl.accept(2, fr(t, t * 0.001), now)
		var c := tl.consume(2, 1, 1, 50, now, last)
		if not c.is_empty():
			used += 1
			last = c.tick
		for slot: Dictionary in tl._slots.values():
			max_seen = maxi(max_seen, slot.seen.size())
			max_frames = maxi(max_frames, slot.frames.size())
	check("S03_seen_acotado", max_seen <= 181 and max_frames <= 181, "máx seen %d, máx frames %d, consumidos %d" % [max_seen, max_frames, used])

# S04: una sesión sin retirar que deja de recibir.
func _s04_slot_lifetime() -> void:
	var tl := Timeline.new()
	for t in range(1, 11): tl.accept(2, fr(t), t)
	tl.consume(2, 1, 1, 50, 10, 0)
	var alive: Array = []
	for now in [11, 129, 130, 131, 140]:
		tl.prune(now)
		alive.append("%d:%d" % [now, tl._slots.size()])
	# Capacidad: cuatro sesiones del mismo peer, todas consumidas y sin retirar.
	var tl2 := Timeline.new()
	for s in range(1, 5):
		tl2.accept(2, fr(100, 0, s), 100)
		tl2.consume(2, 1, 1, s, 100, 99)
	var fifth: Array = []
	for now in [101, 160, 220, 221]:
		fifth.append("%d:%s" % [now, tl2.accept(2, fr(now, 0, 5), now)])
	check("S04_vida_de_una_sesion_sin_retirar", null, "claves vivas (ahora:claves) %s; quinta sesión del mismo peer %s" % [alive, fifth])

# S05: retirar borra seen; caducidad del retiro.
func _s05_retire() -> void:
	var tl := Timeline.new()
	for t in range(95, 101): tl.accept(2, fr(t), t)
	tl.consume(2, 1, 1, 50, 100, 94)
	tl.retire(2, 1, 1, 50, 100)
	var at_101: String = tl.accept(2, fr(100), 101)
	var statuses: Array = []
	for now in range(101, 260):
		statuses.append(tl.accept(2, fr(100), now))
	var h := hist(statuses)
	check("S05a_retirado_tras_consumir", at_101 == "retired" and not h.has("buffered"), "en 101 %s; estados del tick 100 de 101 a 259: %s" % [at_101, h])
	# Entradas posteriores al tick del retiro (el invitado va adelantado).
	var tl2 := Timeline.new()
	tl2.retire(2, 1, 1, 60, 100)
	var late: Array = []
	for now in [150, 220, 221, 222]:
		late.append("%d:%s" % [now, tl2.accept(2, fr(now + 10, 0, 60), now)])
	var c := tl2.consume(2, 1, 1, 60, 260, 0)
	check("S05b_retiro_vencido", null, "tick adelantado 10 de una sesión retirada en 100 (ahora:estado) %s; la bandeja lo entrega si se pide %s" % [late, not c.is_empty()])

# S06: desconexión.
func _s06_drop_peer() -> void:
	var tl := Timeline.new()
	tl.accept(2, fr(100), 100)
	tl.consume(2, 1, 1, 50, 100, 99)
	tl.drop_peer(2)
	var st: String = tl.accept(2, fr(100), 101)
	check("S06_desconexion", null, "tick consumido reenviado después de drop_peer: %s" % st)

# S07: inundación aleatoria (como L21), mirando seen.
func _s07_flood() -> void:
	var tl := Timeline.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261116
	var now := 1000
	var max_keys := 0
	var max_seen := 0
	var st: Array = []
	for i in 20000:
		if i % 5 == 0: now += 1
		var f := fr(now + rng.randi_range(-200, 100), rng.randf(), rng.randi_range(1, 10), rng.randi_range(1, 3), rng.randi_range(1, 2))
		st.append(tl.accept(rng.randi_range(2, 5), f, now))
		if i % 7 == 0: tl.consume(rng.randi_range(2, 5), rng.randi_range(1, 3), rng.randi_range(1, 2), rng.randi_range(1, 10), now, now - 3)
		max_keys = maxi(max_keys, tl._slots.size())
		for slot: Dictionary in tl._slots.values(): max_seen = maxi(max_seen, slot.seen.size())
	check("S07_inundacion", max_keys <= 8 and max_seen <= 181, "máx claves %d; máx seen %d; estados %s" % [max_keys, max_seen, hist(st)])

func _finish(ms: int) -> void:
	var fails := results.filter(func(r): return r.ok == false).size()
	var text := JSON.stringify({"schema": 1, "results": results, "fails": fails, "ms": ms}, "  ", false, true)
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	for r in results:
		print("%s %s %s" % ["PASS" if r.ok == true else ("FAIL" if r.ok == false else "INFO"), r.id, r.detail])
	print("HAND_TIMELINE_SEEN_DONE pass=%d fail=%d ms=%d" % [results.filter(func(r): return r.ok == true).size(), fails, ms])
	quit(0)
