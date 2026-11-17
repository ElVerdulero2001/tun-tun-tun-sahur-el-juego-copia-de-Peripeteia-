extends "res://cv_base.gd"
## Validación independiente (Claude), entrega 8: X1-X4, intercambio entre procesos por archivo
## (criterios §4.2). role=export escribe el artefacto; role=import lo restaura en otro proceso.

func _ready() -> void:
	started = Time.get_ticks_usec()
	a = C.args()
	if not ClassDB.class_exists("SahurObjectWorld"):
		not_evaluable("X0", "clase no registrada"); finish_cv(); return
	if a.get("role") == "export": export_role()
	else: import_role()
	finish_cv()

func export_role() -> void:
	var w = C.build([0, 1, 2, 3], [], true)
	var cp := C.rule_k(w)
	if cp < 0:
		not_evaluable("X0_regla_K", "sin contacto activo"); return
	var art := {"schema": "cv8_exchange", "checkpoint_tick": cp, "snapshot": w.snapshot_trusted(),
		"initial": var_to_bytes(w.samples()), "rays": C.grid_rays(w)}
	art["history"] = C.branch(w, 420)
	var bytes := var_to_bytes(art)
	var f := FileAccess.open(a.get("artifact", ""), FileAccess.WRITE)
	check("X0_archivo_escrito", f != null, a.get("artifact", ""), "abierto")
	if f == null: return
	f.store_buffer(bytes); f.close()
	facts["checkpoint_tick"] = cp
	facts["snapshot_bytes"] = (art.snapshot as PackedByteArray).size()
	facts["artifact_bytes"] = bytes.size()
	facts["artifact_sha256"] = C.sha256(bytes)

func import_role() -> void:
	var shift: Array = []
	for _i in 64:
		var n := Node3D.new(); add_child(n); shift.append(n.get_instance_id())
	facts["first_shift_instance_id"] = shift[0]
	# Vecino vivo con los mismos UID y su control en el mismo proceso.
	var other = C.build([0, 1, 2, 3], [], true)
	var control = C.build([0, 1, 2, 3], [], true)
	for _i in 25:
		other.step(C.DT); control.step(C.DT)
	var d = C.build([3, 0, 2, 1], [90, 91], true)
	for _i in 40: d.step(C.DT)
	facts["destination_instance_id"] = d.get_instance_id()
	var bytes := FileAccess.get_file_as_bytes(a.get("artifact", ""))
	facts["received_bytes"] = bytes.size()
	facts["received_sha256"] = C.sha256(bytes)
	var art = bytes_to_var(bytes) if bytes.size() > 0 else null
	if not art is Dictionary or art.get("schema") != "cv8_exchange":
		not_evaluable("X0_artefacto", "ilegible"); return
	var before_other := var_to_bytes(other.samples())
	var ok: bool = d.restore_trusted(art.snapshot)
	var same_init: bool = var_to_bytes(d.samples()) == art.initial
	var rays := C.grid_rays(d)
	var rays_ok := var_to_bytes(rays) == var_to_bytes(art.rays)
	var hist := C.branch(d, 420)
	var fd := C.first_diff(art.history, hist)
	check("X2_importado_igual", ok and same_init and rays_ok and fd == -1,
		{"restaurado": ok, "inicial": same_init, "rayos": rays_ok, "primer_paso_distinto": fd, "error": d.get_last_error()}, "bytes iguales: inicial, rayos y 420 pasos")
	var same_now := var_to_bytes(other.samples()) == before_other and before_other == var_to_bytes(control.samples())
	var oh: Array = []
	var ch: Array = []
	for _i in 420:
		other.step(C.DT); control.step(C.DT)
		oh.append(var_to_bytes(other.samples())); ch.append(var_to_bytes(control.samples()))
	check("X3_vecino_igual_a_su_control", same_now and C.first_diff(oh, ch) == -1, {"al_importar": same_now, "primer_paso_distinto": C.first_diff(oh, ch)}, "iguales")
	var mism = C.build([0, 1, 2, 3], [], true, {10: Vector3(0.51, 0.3, 0.7)})
	for _i in 5: mism.step(C.DT)
	var before: PackedByteArray = mism.snapshot_trusted()
	var rej: bool = mism.restore_trusted(art.snapshot)
	check("X4_otro_tamano_rechazado", not rej and mism.snapshot_trusted() == before, mism.get_last_error(), "false, sin cambios")
	for n in shift: instance_from_id(n).queue_free()
