extends Node3D
## Validación independiente (Claude), entrega 8: base de mis escenas Godot.
## Código de salida: 0 todo evaluado y sin FAIL, 2 algún FAIL, 3 condición previa no lograda.

const C = preload("res://cv_common.gd")
var a := {}
var checks: Array = []
var facts := {}
var started := 0
var finished := false
var noeval := false

func check(id: String, ok: bool, metric = null, tol := "") -> bool:
	checks.append({"id": id, "verdict": "PASS" if ok else "FAIL", "metric": metric, "tol": tol})
	if not ok: print("CV_FAIL " + id + " " + str(metric))
	return ok

func info(id: String, metric) -> void:
	checks.append({"id": id, "verdict": "INFO", "metric": metric, "tol": "se registra"})

func not_evaluable(id: String, why) -> void:
	noeval = true
	checks.append({"id": id, "verdict": "NOEVAL", "metric": why, "tol": "condición previa"})

func finish_cv(extra := {}) -> void:
	if finished: return
	finished = true
	var fails := checks.filter(func(c): return c.verdict == "FAIL").size()
	var result := {"schema": "cv8", "role": a.get("role", ""), "checks": checks, "facts": facts,
		"seconds": float(Time.get_ticks_usec() - started) / 1e6}
	result.merge(extra)
	var path: String = a.get("result", "")
	if not path.is_empty():
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(result, " ", true, true))
			f.close()
	print("CV_RESULT role=%s fails=%d noeval=%s" % [a.get("role", ""), fails, noeval])
	get_tree().quit(2 if fails > 0 else (3 if noeval else 0))
