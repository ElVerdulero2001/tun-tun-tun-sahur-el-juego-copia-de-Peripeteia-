extends "res://validacion_claude/rv_common.gd"

## R4 (punto 4): contador global y segundo espacio con cuerpos vivos, en un
## proceso. El StateManager tiene como raíz el nodo Island (A, B y su piso).
## O vive en el MISMO espacio pero fuera de esa raíz; S vive en otro espacio
## (SubViewport con mundo propio). X se crea después del checkpoint y sigue
## vivo; Y (segundo espacio) y Z (espacio de la isla) se crean después de
## restaurar. --control hace todo igual salvo load_cached_state.
const PRE := 20
const MID := 30
const TOTAL := 120
var island: Node3D
var outside: Node3D
var second: SubViewport
var floor_a: StaticBody3D
var floor_s: StaticBody3D
var A: RigidBody3D
var B: RigidBody3D
var O: RigidBody3D
var S: RigidBody3D
var X: RigidBody3D
var Y: RigidBody3D
var Z: RigidBody3D
var space_a: RID
var space_s: RID
var manager: Node
var step_n := 0
var o_hist: Array = []
var s_hist: Array = []
var ab_hist: Array = []

func _ready() -> void:
	parse_args()
	if not rapier_ready():
		finish(2, {"reason": "backend_not_prepared"})
		return
	island = Node3D.new()
	island.name = "Island"
	add_child(island)
	outside = Node3D.new()
	outside.name = "Outside"
	add_child(outside)
	second = SubViewport.new()
	second.name = "Second"
	second.own_world_3d = true
	add_child(second)
	manager = make_manager(island)
	floor_a = make_floor(island, "FloorA")
	A = make_box(island, "A", Vector3(0.6, 0.4, 0.4), Vector3(0, 0.2, 0), 2.0)
	B = make_box(island, "B", Vector3(0.6, 0.4, 0.4), Vector3(0.15, 1.0, 0), 2.0, Basis(Vector3(0, 0, 1), 0.2))
	O = make_box(outside, "O", Vector3(0.4, 0.4, 0.4), Vector3(3, 3.0, 0), 1.0)
	floor_s = make_floor(second, "FloorS")
	S = make_box(second, "S", Vector3(0.4, 0.4, 0.4), Vector3(0, 4.0, 0), 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	space_a = get_world_3d().space
	space_s = second.find_world_3d().space
	facts["distinct_spaces"] = space_a != space_s
	PhysicsServer3D.space_set_active(space_a, false)
	PhysicsServer3D.space_set_active(space_s, false)
	flush(space_a)
	flush(space_s)
	_run()

func step_all(n := 1) -> void:
	for i in n:
		step(space_a)
		step(space_s)
		step_n += 1
		o_hist.append(snap({"O": O}))
		s_hist.append(snap({"S": S}))
		ab_hist.append(snap({"A": A, "B": B}))

func ids_of(o: CollisionObject3D) -> Dictionary:
	return {"rid": o.get_rid().get_id(), "rapier": rapier_id(o.get_rid()), "shape_rapier": rapier_id(shape_rid(o))}

func live_ids() -> Dictionary:
	var owners := {}
	var entries: Array = [["space_A", space_a], ["space_S", space_s]]
	for o in [floor_a, A, B, O, floor_s, S, X, Y, Z]:
		if o == null or not is_instance_valid(o): continue
		entries.append([str(o.name), (o as CollisionObject3D).get_rid()])
		entries.append([str(o.name) + "/shape", shape_rid(o)])
	for e in entries:
		var id := rapier_id(e[1])
		if not owners.has(id): owners[id] = []
		owners[id].append(e[0])
	var dup := {}
	for id in owners:
		if id != 0 and owners[id].size() > 1: dup[str(id)] = owners[id]
	return {"owners": owners, "duplicates": dup, "unknown": owners.get(0, [])}

func _run() -> void:
	var control := args.has("control")
	facts["control"] = control
	step_all(PRE)
	var g0 := global_id()
	var o_cp := snap({"O": O})
	var s_cp := snap({"S": S})
	manager.call("cache_state", space_a, "cp")
	var idx: int = (manager.call("ordered_cache_tags") as Array).find("cp")
	X = make_box(second, "X", Vector3(0.4, 0.4, 0.4), Vector3(2, 0.2, 0), 1.0)
	var g1 := global_id()
	facts["X"] = ids_of(X)
	step_all(MID)
	var o_pre := snap({"O": O})
	var s_pre := snap({"S": S})
	var loaded = null
	if not control:
		loaded = manager.call("load_cached_state", space_a, idx)
		flush(space_a)
		flush(space_s)
	var o_post := snap({"O": O})
	var s_post := snap({"S": S})
	var g2 := global_id()
	Y = make_box(second, "Y", Vector3(0.4, 0.4, 0.4), Vector3(-2, 0.2, 0), 1.0)
	Z = make_box(island, "Z", Vector3(0.4, 0.4, 0.4), Vector3(-3, 0.2, 0), 1.0)
	var g3 := global_id()
	facts["Y"] = ids_of(Y)
	facts["Z"] = ids_of(Z)
	facts["global_id"] = {"before_checkpoint": g0, "after_X": g1, "after_load": g2, "after_Y_Z": g3}
	facts["load_return"] = loaded
	var live := live_ids()
	facts["live_ids_after_creation"] = live
	step_all(10)
	var q1 := {"X": ray(space_s, Vector3(2, 3, 0), Vector3(2, -1, 0)), "Y": ray(space_s, Vector3(-2, 3, 0), Vector3(-2, -1, 0)),
		"Z": ray(space_a, Vector3(-3, 3, 0), Vector3(-3, -1, 0)),
		"X_hits": read_body(X).hits, "Y_hits": read_body(Y).hits, "Z_hits": read_body(Z).hits}
	Y.free()
	Y = null
	step_all(10)
	var q2 := {"X": ray(space_s, Vector3(2, 3, 0), Vector3(2, -1, 0)), "X_hits": read_body(X).hits,
		"Z": ray(space_a, Vector3(-3, 3, 0), Vector3(-3, -1, 0)), "Z_hits": read_body(Z).hits}
	# R4d corregido (criterios §6): X y Z despiertos y deslizándose antes de mirar
	# contactos y si el nodo sigue al cuerpo. El primer intento no consideraba el reposo.
	var p0 := {"X": read_body(X).p, "Z": read_body(Z).p}
	impulse(X, Vector3(3, 0, 0))
	impulse(Z, Vector3(3, 0, 0))
	step_all(10)
	var d := {"X": read_body(X), "Z": read_body(Z)}
	d.X["moved"] = Vector3(d.X.p[0] - p0.X[0], d.X.p[1] - p0.X[1], d.X.p[2] - p0.X[2]).length()
	d.Z["moved"] = Vector3(d.Z.p[0] - p0.Z[0], d.Z.p[1] - p0.Z[1], d.Z.p[2] - p0.Z[2]).length()
	facts["after_impulse"] = d
	step_all(TOTAL - step_n)
	facts["queries_after_creation"] = q1
	facts["queries_after_free_Y"] = q2
	facts["O"] = {"checkpoint": o_cp, "before_load": o_pre, "after_load": o_post}
	facts["S"] = {"checkpoint": s_cp, "before_load": s_pre, "after_load": s_post}

	# Decisiones dentro del proceso (las comparaciones con el control las hace rv_compare.mjs).
	if not control:
		check("R4a_contador_vuelve_al_checkpoint", null, facts.global_id, "se registra", "hecho de código, ver criterios")
	check("R4b_ids_unicos_tras_crear", live.duplicates.is_empty(), live.duplicates, "ningún id de Rapier compartido entre objetos vivos")
	var q_ok: bool = q1.X.get("collider", "") == "X" and q1.X.get("rid", -1) == X.get_rid().get_id() \
		and q1.Y.get("collider", "") == "Y" and q1.Z.get("collider", "") == "Z" \
		and q2.X.get("collider", "") == "X" and q2.X.get("rid", -1) == X.get_rid().get_id() and q2.Z.get("collider", "") == "Z"
	check("R4c_consultas_identifican_objetos", q_ok, {"after_creation": q1, "after_free_Y": q2}, "cada rayo devuelve su cuerpo y su RID")
	var c_ok: bool = not d.X.sl and not d.Z.sl and d.X.hits == ["FloorS"] and d.Z.hits == ["FloorA"] \
		and d.X.node_err <= EPS and d.Z.node_err <= EPS and d.X.node_sl == d.X.sl and d.Z.node_sl == d.Z.sl \
		and d.X.moved >= 0.1 and d.Z.moved >= 0.1
	check("R4d_contactos_y_nodos_tras_liberar_Y", c_ok, d, "X y Z despiertos y avanzan ≥ 0,1 m; X → FloorS, Z → FloorA; nodo = servidor ≤ EPS",
		"corregido (§6); contactos antes del impulso, informativos: %s" % str({"after_creation": [q1.X_hits, q1.Y_hits, q1.Z_hits], "after_free_Y": [q2.X_hits, q2.Z_hits]}))
	var es := cmp([s_pre], [s_post], ["S"], false)
	check("R4e_segundo_espacio_intacto_al_restaurar", within(es), es, "≤ EPS")
	var eo := cmp([o_pre], [o_post], ["O"], false)
	var eo_cp := cmp([o_cp], [o_post], ["O"], false)
	facts["O_post_vs_pre"] = eo
	facts["O_post_vs_checkpoint"] = eo_cp
	if not control:
		check("R4f_mismo_espacio_fuera_de_la_raiz", within(eo), {"post_vs_pre": eo, "post_vs_checkpoint": eo_cp},
			"O conserva su estado al restaurar la isla", "si falla: restaurar la isla rebobina también lo que comparte su espacio")
	finish(0, {"o_hist": o_hist, "s_hist": s_hist, "ab_hist": ab_hist})
