extends RefCounted
## Validación independiente (Claude), entrega 8: utilidades de los instrumentos Godot.
## Criterios: docs/net/validacion_objetos/criterios_entrega_8.md §4.

const DT := 1.0 / 60.0
const EPS := 0.00001

static func args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var i := a.find("=")
			out[a.substr(2, i - 2)] = a.substr(i + 1)
	return out

static func at(x: float, y: float, z: float, basis := Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, Vector3(x, y, z))

## Fixture F (criterios §3.1) por el enlace. order: índices de [piso, A, B, C].
static func fixture_f() -> Array:
	return [
		[1, Vector3(8, 0.2, 8), 0.0, at(0, -0.1, 0)],
		[10, Vector3(0.5, 0.3, 0.7), 1.5, at(0.05, 0.15, -0.1, Basis(Vector3.UP, 0.3))],
		[20, Vector3(0.4, 0.4, 0.4), 1.0, at(0.1, 0.9, 0.05, Basis(Vector3(1, 0, 1).normalized(), 0.35))],
		[30, Vector3(0.3, 0.3, 0.3), 0.5, at(-0.7, 0.15, 0.2)],
	]

static func build(order: Array, removed: Array, sealed: bool, change := {}) -> Object:
	var w = ClassDB.instantiate("SahurObjectWorld")
	var i := 0
	for uid in removed:
		w.add_box(uid, 1, Vector3(0.2, 0.2, 0.2), 0.3, at(3.0 + i, 0.1, 3.0))
		w.remove_body(uid, 1)
		i += 1
	var bodies := fixture_f()
	for k in order:
		var b: Array = bodies[k]
		var size: Vector3 = change.get(b[0], b[1])
		if not w.add_box(b[0], 1, size, b[2], b[3]):
			push_error("fixture: " + str(w.get_last_error()))
	if sealed: w.seal_topology(1)
	return w

static func has_contact(s: Dictionary, uid: int) -> bool:
	for c in s.contacts:
		if c.uid == uid and c.epoch == 1: return true
	return false

## Regla K: primer paso 5..120 con contacto mutuo A-B, ambos despiertos y |vB - vA| >= 0,05.
static func rule_k(w) -> int:
	for s in range(1, 121):
		w.step(DT)
		if s < 5: continue
		var a: Dictionary = w.sample(10, 1)
		var b: Dictionary = w.sample(20, 1)
		if has_contact(a, 20) and has_contact(b, 10) and not a.sleeping and not b.sleeping and (b.lv - a.lv).length() >= 0.05:
			return w.get_tick()
	return -1

static func branch(w, h: int) -> Array:
	var out: Array = []
	for j in range(1, h + 1):
		if j == 30: w.apply_impulse(10, 1, Vector3(1.0, 0, 0.3))
		if j == 330: w.apply_impulse(20, 1, Vector3(0, 0, 0.6))
		w.step(DT)
		out.append(var_to_bytes(w.samples()))
	return out

static func grid_rays(w) -> Array:
	var out: Array = []
	for x in [-0.7, 0.05, 0.1]:
		for z in [-0.1, 0.05, 0.2]:
			out.append(w.cast_ray(Vector3(x, 3, z), Vector3.DOWN, 5.0))
	for yz in [[0.1, -0.1], [0.25, 0.05], [2.5, 0.0]]:
		out.append(w.cast_ray(Vector3(-3, yz[0], yz[1]), Vector3.RIGHT, 6.0))
	return out

static func sha256(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()

## Primer índice distinto entre dos listas de bytes (-1 si son iguales y del mismo largo).
static func first_diff(a: Array, b: Array) -> int:
	if a.size() != b.size(): return mini(a.size(), b.size())
	for i in a.size():
		if a[i] != b[i]: return i
	return -1

static func body_numbers(s: Dictionary) -> Array:
	var t: Transform3D = s.pose
	var out := [t.origin.x, t.origin.y, t.origin.z]
	for r in 3:
		out.append_array([t.basis[r].x, t.basis[r].y, t.basis[r].z])
	out.append_array([s.lv.x, s.lv.y, s.lv.z, s.av.x, s.av.y, s.av.z])
	return out
