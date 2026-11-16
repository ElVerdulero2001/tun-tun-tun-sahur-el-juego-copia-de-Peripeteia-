extends Node3D

## Validación independiente (Claude), entrega 5: base común de los ensayos con
## Rapier. No modifica probe.gd ni exchange_probe.gd de Codex: estos ensayos se
## copian junto a la fixture en una carpeta nueva de tmp/ (run_rapier.ps1).
## Criterios: docs/net/validacion_objetos/criterios_entrega_5.md, parte B.
## Códigos de salida: 0 = el ensayo terminó (las decisiones están en "checks");
## 2 = Rapier no está preparado; 3 = no se cumplió la condición del escenario.
const VERSION := "v0.36.0"
const DT := 1.0 / 60.0
const EPS := 0.00001

var args := {}
var result_path := ""
var started_usec := 0
var checks: Array = []
var facts := {}
var _finished := false

func parse_args() -> void:
	started_usec = Time.get_ticks_usec()
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"): continue
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	result_path = str(args.get("result", ""))

func rapier_ready() -> bool:
	return ProjectSettings.get_setting("physics/3d/physics_engine") == "Rapier3D" \
		and ClassDB.class_exists("RapierPhysicsServer3D") and ClassDB.class_exists("StateManager3D")

func make_manager(root_node: Node) -> Node:
	var m: Node = ClassDB.instantiate("StateManager3D")
	m.name = "StateManager"
	add_child(m)
	m.set("root_node", root_node)
	return m

# ------------------------------------------------------------------ servidor
func step(space: RID) -> void:
	ClassDB.class_call_static("RapierPhysicsServer3D", "space_step", space, DT)
	ClassDB.class_call_static("RapierPhysicsServer3D", "space_flush_queries", space)

func flush(space: RID) -> void:
	ClassDB.class_call_static("RapierPhysicsServer3D", "space_flush_queries", space)

func global_id() -> int:
	return int(ClassDB.class_call_static("RapierPhysicsServer3D", "get_global_id"))

func rapier_id(rid: RID) -> int:
	return int(ClassDB.class_call_static("RapierPhysicsServer3D", "get_rapier_id", rid))

func impulse(body: RigidBody3D, v: Vector3) -> void:
	PhysicsServer3D.body_apply_central_impulse(body.get_rid(), v)

# ------------------------------------------------------------------ escena
func make_floor(parent: Node, node_name: String, size := Vector3(10, 0.2, 10), y := -0.1) -> StaticBody3D:
	var f := StaticBody3D.new()
	f.name = node_name
	f.position.y = y
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = shape
	f.add_child(col)
	parent.add_child(f)
	return f

func make_box(parent: Node, node_name: String, size: Vector3, pos: Vector3, mass := 2.0, rot := Basis.IDENTITY) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = node_name
	body.transform = Transform3D(rot, pos)
	body.mass = mass
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 16
	var mat := PhysicsMaterial.new()
	mat.friction = 0.8
	mat.bounce = 0.05
	body.physics_material_override = mat
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body

func shape_rid(obj: CollisionObject3D) -> RID:
	var col := obj.get_node_or_null("Shape") as CollisionShape3D
	return col.shape.get_rid() if col != null and col.shape != null else RID()

func make_noise(parent: Node, n: int) -> void:
	# Cambia la historia de asignación (RIDs e ids de Rapier) sin dejar objetos vivos.
	for i in n:
		var noise := StaticBody3D.new()
		var col := CollisionShape3D.new()
		col.shape = BoxShape3D.new()
		noise.add_child(col)
		parent.add_child(noise)
		noise.free()

# ------------------------------------------------------------------ lectura
func v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func read_body(b: RigidBody3D) -> Dictionary:
	var rid := b.get_rid()
	var t: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
	var lv: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var av: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var sl: bool = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING)
	var hits: Array = []
	for other in b.get_colliding_bodies(): hits.append(str(other.name))
	hits.sort()
	return {"p": v3(t.origin), "b": v3(t.basis.x) + v3(t.basis.y) + v3(t.basis.z), "lv": v3(lv), "av": v3(av),
		"sl": sl, "node_err": b.global_position.distance_to(t.origin), "node_sl": b.sleeping, "hits": hits}

func snap(bodies: Dictionary) -> Dictionary:
	var r := {}
	for key: String in bodies: r[key] = read_body(bodies[key])
	return r

static func _dist(a: Array, b: Array, from: int, n: int) -> float:
	var s := 0.0
	for i in n: s += (float(a[from + i]) - float(b[from + i])) ** 2
	return sqrt(s)

## Compara dos historias (listas de snap) cuerpo por cuerpo. Con hits=false no
## compara la lista de contactos informados (solo para la verificación inmediata
## después de restaurar, cuando todavía no hubo un paso).
func cmp(a: Array, b: Array, names: Array, hits := true) -> Dictionary:
	var e := {"len_a": a.size(), "len_b": b.size(), "pos": 0.0, "basis": 0.0, "vel": 0.0,
		"sleep_mismatch": 0, "hits_mismatch": 0, "first_bad_step": -1, "exact": true}
	var n := mini(a.size(), b.size())
	for i in n:
		var bad := false
		for key: String in names:
			var x: Dictionary = a[i][key]
			var y: Dictionary = b[i][key]
			var dp := _dist(x.p, y.p, 0, 3)
			var db := maxf(_dist(x.b, y.b, 0, 3), maxf(_dist(x.b, y.b, 3, 3), _dist(x.b, y.b, 6, 3)))
			var dv := maxf(_dist(x.lv, y.lv, 0, 3), _dist(x.av, y.av, 0, 3))
			e.pos = maxf(e.pos, dp)
			e.basis = maxf(e.basis, db)
			e.vel = maxf(e.vel, dv)
			if dp != 0.0 or db != 0.0 or dv != 0.0: e.exact = false
			if x.sl != y.sl:
				e.sleep_mismatch += 1
				bad = true
			if hits and x.hits != y.hits:
				e.hits_mismatch += 1
				bad = true
			if dp > EPS or db > EPS or dv > EPS: bad = true
		if bad and e.first_bad_step < 0: e.first_bad_step = i
	return e

func within(e: Dictionary) -> bool:
	return e.len_a == e.len_b and e.pos <= EPS and e.basis <= EPS and e.vel <= EPS \
		and e.sleep_mismatch == 0 and e.hits_mismatch == 0

func node_error(hist: Array, names: Array) -> Dictionary:
	var e := {"pos": 0.0, "sleep_mismatch": 0}
	for rec: Dictionary in hist:
		for key: String in names:
			e.pos = maxf(e.pos, float(rec[key].node_err))
			if rec[key].node_sl != rec[key].sl: e.sleep_mismatch += 1
	return e

func ray(space: RID, from: Vector3, to: Vector3) -> Dictionary:
	var st := PhysicsServer3D.space_get_direct_state(space)
	if st == null: return {"hit": false, "error": "no_direct_state"}
	var r := st.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if r.is_empty(): return {"hit": false}
	var col = r.get("collider")
	return {"hit": true, "rid": (r.rid as RID).get_id(), "collider": str(col.name) if is_instance_valid(col) else "<ninguno>",
		"collider_id": int(r.get("collider_id", 0))}

# ------------------------------------------------------------------ salida
func check(id: String, ok, metric, tol: String, note := "") -> void:
	checks.append({"id": id, "ok": ok, "metric": metric, "tol": tol, "note": note})

func finish(code := 0, extra := {}) -> void:
	if _finished: return
	_finished = true
	var failed := checks.filter(func(c): return c.ok == false).size()
	var passed := checks.filter(func(c): return c.ok == true).size()
	var result := {"schema": 1, "author": "Claude", "dependency": VERSION, "engine": Engine.get_version_info().string,
		"backend_class": PhysicsServer3D.get_class(), "args": args, "exit_intended": code,
		"seconds": float(Time.get_ticks_usec() - started_usec) / 1_000_000.0,
		"passed": passed, "failed": failed, "checks": checks, "facts": facts}
	result.merge(extra, true)
	var text := JSON.stringify(result, "  ", false, true)
	if not result_path.is_empty():
		var f := FileAccess.open(result_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	print("RV_RESULT passed=%d failed=%d code=%d" % [passed, failed, code])
	get_tree().quit(code)
