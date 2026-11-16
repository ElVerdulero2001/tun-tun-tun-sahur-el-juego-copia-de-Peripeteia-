extends "res://validacion_claude/rv_common.gd"

## R3 (punto 3) y parte cruzada del punto 4: intercambio entre procesos.
##   --role=export  [--out-file=<ruta>] [--serve-port=<puerto>]
##   --role=import  --source=file:<ruta> | --source=enet:<puerto>
##                  [--noise=N] [--reverse] [--swap] [--second-first] [--post-create] [--no-import]
## El artefacto lleva variantes sin objetos (bytes del snapshot e historias de
## números). La historia de referencia viaja solo para comparar, no la usa el ensayo.
const SEARCH := 120
const H := 240
const SHOVE_J := 30
const WAIT_MS := 6000
var A: RigidBody3D
var B: RigidBody3D
var floor_body: StaticBody3D
var S: RigidBody3D
var floor_s: StaticBody3D
var second: SubViewport
var space: RID
var space_s := RID()
var manager: Node
var names := ["A", "B"]

func _ready() -> void:
	parse_args()
	if not rapier_ready():
		finish(2, {"reason": "backend_not_prepared"})
		return
	var role := str(args.get("role", ""))
	if args.has("second-first"): _build_second()
	if args.has("noise"): make_noise(self, int(args.noise))
	manager = make_manager(self)
	floor_body = make_floor(self, "Floor")
	# A y B tienen tamaño y masa distintos: con --swap cada nombre queda en el otro cuerpo.
	var spec_a := {"size": Vector3(0.6, 0.4, 0.4), "pos": Vector3(0, 0.2, 0), "mass": 2.0, "rot": Basis.IDENTITY}
	var spec_b := {"size": Vector3(0.5, 0.3, 0.3), "pos": Vector3(0.12, 1.0, 0), "mass": 1.0, "rot": Basis(Vector3(0, 0, 1), 0.2)}
	var name_a := "B" if args.has("swap") else "A"
	var name_b := "A" if args.has("swap") else "B"
	if args.has("reverse"):
		var b := make_box(self, name_b, spec_b.size, spec_b.pos, spec_b.mass, spec_b.rot)
		var a := make_box(self, name_a, spec_a.size, spec_a.pos, spec_a.mass, spec_a.rot)
		A = a if name_a == "A" else b
		B = b if name_b == "B" else a
	else:
		var a := make_box(self, name_a, spec_a.size, spec_a.pos, spec_a.mass, spec_a.rot)
		var b := make_box(self, name_b, spec_b.size, spec_b.pos, spec_b.mass, spec_b.rot)
		A = a if name_a == "A" else b
		B = b if name_b == "B" else a
	await get_tree().physics_frame
	await get_tree().physics_frame
	space = get_world_3d().space
	PhysicsServer3D.space_set_active(space, false)
	if second != null:
		space_s = second.find_world_3d().space
		PhysicsServer3D.space_set_active(space_s, false)
		flush(space_s)
	flush(space)
	if role == "export": _export()
	elif role == "import": _import()
	else: finish(3, {"reason": "missing_role"})

func _build_second() -> void:
	second = SubViewport.new()
	second.name = "Second"
	second.own_world_3d = true
	add_child(second)
	floor_s = make_floor(second, "FloorS")
	S = make_box(second, "S", Vector3(0.4, 0.4, 0.4), Vector3(0, 3.0, 0), 1.0)

func bodies() -> Dictionary:
	return {"A": A, "B": B}

func step_all() -> void:
	step(space)
	if space_s.is_valid(): step(space_s)

func run_branch(with_command: bool) -> Dictionary:
	var hist: Array = []
	var s_hist: Array = []
	for j in range(1, H + 1):
		if with_command and j == SHOVE_J: impulse(A, Vector3(1.2, 0, 0.4))
		step_all()
		hist.append(snap(bodies()))
		if S != null: s_hist.append(snap({"S": S}))
	return {"hist": hist, "s_hist": s_hist}

func ids_report() -> Dictionary:
	var objs := {"Floor": floor_body, "A": get_node_or_null("A"), "B": get_node_or_null("B")}
	if second != null:
		objs["FloorS"] = floor_s
		objs["S"] = S
	var r := {"global_id": global_id(), "space_A": rapier_id(space)}
	if space_s.is_valid(): r["space_S"] = rapier_id(space_s)
	for key: String in objs:
		var o: CollisionObject3D = objs[key]
		if o == null: continue
		r[key] = {"rid": o.get_rid().get_id(), "rapier": rapier_id(o.get_rid()),
			"shape_rapier": rapier_id(shape_rid(o)), "instance": o.get_instance_id()}
	return r

func live_rapier_ids(extra: Array = []) -> Dictionary:
	# id de Rapier -> lista de objetos vivos que dicen tenerlo.
	var owners := {}
	var entries: Array = [["space_A", space]]
	if space_s.is_valid(): entries.append(["space_S", space_s])
	var objs: Array = [floor_body, get_node_or_null("A"), get_node_or_null("B")]
	if second != null: objs += [floor_s, S]
	objs += extra
	for o in objs:
		if o == null: continue
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

# ------------------------------------------------------------------ exportar
func find_checkpoint() -> int:
	for s in range(1, SEARCH + 1):
		step_all()
		var r := snap(bodies())
		var speed := maxf(Vector3(r.A.lv[0], r.A.lv[1], r.A.lv[2]).length(), Vector3(r.B.lv[0], r.B.lv[1], r.B.lv[2]).length())
		if s >= 5 and "B" in r.A.hits and "A" in r.B.hits and not r.A.sl and not r.B.sl and speed >= 0.05:
			return s
	return -1

func _export() -> void:
	var c := find_checkpoint()
	if c < 0:
		facts["reason"] = "no_active_contact"
		finish(3)
		return
	var initial := snap(bodies())
	var ids := ids_report()
	var bytes = manager.call("export_state", space, "RustBincode")
	if typeof(bytes) != TYPE_PACKED_BYTE_ARRAY or bytes.is_empty():
		check("R3x_exportar", false, {"reason": "export_vacio"}, "bytes")
		finish(0)
		return
	var ref := run_branch(true)
	var artifact := {"schema": 1, "author": "Claude", "dependency": VERSION, "checkpoint_step": c,
		"initial": initial, "snapshot": bytes, "ref": ref.hist, "ids": ids}
	facts["checkpoint_step"] = c
	facts["snapshot_bytes"] = bytes.size()
	facts["snapshot_sha256"] = _sha(bytes)
	facts["ids"] = ids
	var payload := var_to_bytes(artifact)
	facts["artifact_bytes"] = payload.size()
	facts["artifact_sha256"] = _sha(payload)
	if args.has("out-file"):
		var f := FileAccess.open(str(args["out-file"]), FileAccess.WRITE)
		if f == null:
			check("R3x_exportar", false, {"reason": "no_se_pudo_escribir"}, "archivo")
			finish(0)
			return
		f.store_buffer(payload)
		f.close()
	if args.has("serve-port"):
		facts["enet"] = _serve(int(args["serve-port"]), payload)
	var ne := node_error(ref.hist, names)
	check("R3x_exportar", ne.pos <= EPS and ne.sleep_mismatch == 0 and (not args.has("serve-port") or facts.enet.get("acked", false)),
		{"node_error": ne, "enet": facts.get("enet", {})}, "nodo = servidor; con ENet, entrega confirmada")
	finish(0)

func _sha(b: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish().hex_encode()

func _serve(port: int, payload: PackedByteArray) -> Dictionary:
	var r := {"port": port, "sent": false, "acked": false, "bytes": payload.size()}
	var enet := ENetConnection.new()
	var err := enet.create_host_bound("127.0.0.1", port, 1, 1)
	if err != OK:
		r["error"] = err
		return r
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline and not r.acked:
		var ev: Array = enet.service(20)
		match ev[0]:
			ENetConnection.EVENT_CONNECT:
				(ev[1] as ENetPacketPeer).send(0, payload, ENetPacketPeer.FLAG_RELIABLE)
				r.sent = true
				r["sent_ms"] = Time.get_ticks_msec()
			ENetConnection.EVENT_RECEIVE:
				var pkt := (ev[1] as ENetPacketPeer).get_packet()
				if pkt.get_string_from_ascii() == "ok:" + _sha(payload):
					r.acked = true
			ENetConnection.EVENT_ERROR:
				r["service_error"] = true
	enet.flush()
	enet.destroy()
	return r

# ------------------------------------------------------------------ importar
func _receive() -> Dictionary:
	var src := str(args.get("source", ""))
	var out := {"source": src, "bytes": 0}
	var payload := PackedByteArray()
	if src.begins_with("file:"):
		var f := FileAccess.open(src.trim_prefix("file:"), FileAccess.READ)
		if f == null or f.get_length() > 4_000_000: return out
		payload = f.get_buffer(f.get_length())
		f.close()
	elif src.begins_with("enet:"):
		var enet := ENetConnection.new()
		enet.create_host(1, 1)
		var peer := enet.connect_to_host("127.0.0.1", int(src.trim_prefix("enet:")), 1)
		var deadline := Time.get_ticks_msec() + WAIT_MS
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() < deadline and payload.is_empty() and peer != null:
			var ev: Array = enet.service(20)
			if ev[0] == ENetConnection.EVENT_RECEIVE:
				payload = (ev[1] as ENetPacketPeer).get_packet()
				out["receive_ms"] = Time.get_ticks_msec() - t0
		if not payload.is_empty():
			peer.send(0, ("ok:" + _sha(payload)).to_ascii_buffer(), ENetPacketPeer.FLAG_RELIABLE)
			for i in 10: enet.service(10)
			peer.peer_disconnect()
			for i in 5: enet.service(10)
		enet.destroy()
	out.bytes = payload.size()
	out["sha256"] = _sha(payload) if not payload.is_empty() else ""
	var artifact = bytes_to_var(payload) if not payload.is_empty() else null
	if not artifact is Dictionary or artifact.get("schema") != 1 or artifact.get("dependency") != VERSION:
		return out
	out["artifact"] = artifact
	return out

func _import() -> void:
	var ids_before := ids_report()
	facts["ids_before"] = ids_before
	var wrong := run_branch(false)
	var got := _receive()
	if not got.has("artifact"):
		check("R3_recibir", false, {"source": got.source, "bytes": got.bytes}, "artefacto válido")
		finish(0)
		return
	var artifact: Dictionary = got.artifact
	facts["received"] = {"source": got.source, "bytes": got.bytes, "sha256": got.sha256, "receive_ms": got.get("receive_ms", -1)}
	facts["snapshot_sha256"] = _sha(artifact.snapshot)
	facts["source_ids"] = artifact.ids
	var s_before := snap({"S": S}) if S != null else {}
	var ray_before := ray(space_s, Vector3(S.global_position.x, 5, 0), Vector3(S.global_position.x, -1, 0)) if S != null else {}
	if args.has("no-import"):
		facts["import_skipped"] = true
	else:
		manager.call("import_state", space, artifact.snapshot)
		flush(space)
		if space_s.is_valid(): flush(space_s)
	var ids_after := ids_report()
	facts["ids_after"] = ids_after
	var restored := cmp([artifact.initial], [snap(bodies())], names, false)
	var wrong_err := cmp(artifact.ref, wrong.hist, names)
	var dup := live_rapier_ids()
	facts["live_ids_after_import"] = dup
	var exp_restore := not args.has("no-import") and not args.has("swap")
	if not args.has("no-import"):
		check("R3a_restaurado", within(restored) if not args.has("swap") else null, restored, "≤ EPS",
			"informativo con --swap" if args.has("swap") else "")
		check("R3b_rama_incorrecta_previa", wrong_err.pos > 0.0001, wrong_err, "> 0,1 mm (validez del instrumento)")
	check("R3c_ids_unicos_tras_importar", dup.duplicates.is_empty(), dup.duplicates, "ningún id de Rapier compartido entre objetos vivos")
	if S != null:
		var s_after := snap({"S": S})
		var es := cmp([s_before], [s_after], ["S"], false)
		check("R3d_segundo_espacio_intacto_al_importar", within(es), es, "≤ EPS")
		var ray_after := ray(space_s, Vector3(S.global_position.x, 5, 0), Vector3(S.global_position.x, -1, 0))
		facts["ray_S_before"] = ray_before
		facts["ray_S_after_import"] = ray_after
		check("R3e_consulta_identifica_S", ray_after.get("hit", false) and ray_after.get("collider", "") == "S"
			and ray_after.get("rid", -1) == S.get_rid().get_id(), ray_after, "el rayo sobre S devuelve S")
	var replay := run_branch(true)
	var err := cmp(artifact.ref, replay.hist, names)
	if not args.has("no-import"):
		check("R3f_repeticion_entre_procesos", within(err) if not args.has("swap") else null, err,
			"%d pasos ≤ EPS; reposo y contactos iguales" % H, "informativo con --swap" if args.has("swap") else "")
		var ne := node_error(replay.hist, names)
		check("R3g_nodos_y_servidor", ne.pos <= EPS and ne.sleep_mismatch == 0 if exp_restore else null, ne, "nodo = servidor ≤ EPS")
	if args.has("swap"):
		var shapes := {}
		for key in ["A", "B"]:
			var o: RigidBody3D = get_node(key)
			var col := o.get_node("Shape") as CollisionShape3D
			shapes[key] = {"resource_size": v3((col.shape as BoxShape3D).size),
				"server_data": str(PhysicsServer3D.shape_get_data(col.shape.get_rid())), "mass_node": o.mass}
		facts["swap_shapes"] = shapes
	if S != null: facts["s_hist"] = replay.s_hist
	if args.has("post-create") and second != null:
		var g := global_id()
		var n := make_box(second, "N", Vector3(0.4, 0.4, 0.4), Vector3(2, 0.2, 0), 1.0)
		await get_tree().process_frame
		var dup2 := live_rapier_ids([n])
		facts["post_create"] = {"global_id_before": g, "N": rapier_id(n.get_rid()), "N_shape": rapier_id(shape_rid(n)),
			"global_id_after": global_id(), "live_ids": dup2}
		check("R3h_creacion_posterior_ids_unicos", dup2.duplicates.is_empty(), dup2.duplicates, "N no repite un id vivo")
		step(space_s)
		var ray_s := ray(space_s, Vector3(S.global_position.x, 5, 0), Vector3(S.global_position.x, -1, 0))
		var ray_n := ray(space_s, Vector3(2, 5, 0), Vector3(2, -1, 0))
		facts["ray_after_post_create"] = {"S": ray_s, "N": ray_n}
		check("R3i_consultas_tras_crear", ray_s.get("collider", "") == "S" and ray_n.get("collider", "") == "N",
			{"S": ray_s, "N": ray_n}, "cada rayo devuelve su cuerpo")
	finish(0)
