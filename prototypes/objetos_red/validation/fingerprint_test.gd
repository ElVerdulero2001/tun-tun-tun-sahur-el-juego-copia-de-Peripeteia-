extends SceneTree

## Validación independiente (Claude), entrega 2: la huella depende de la
## configuración real de arranque. Instancia main.tscn en modo solo (sin red),
## lee fingerprint() y repite cambiando ajustes físicos en tiempo de ejecución,
## antes de instanciar. No modifica project.godot ni runtime/.
## Uso: Godot --headless --path prototypes/objetos_red --script res://validation/fingerprint_test.gd -- --out=<ruta.json>
## Criterios: docs/net/validacion_objetos/criterios_entrega_2.md (F10_huella_*).

const MainScene := preload("res://main.tscn")

var results: Array = []
var out_path := ""
var _done := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_path = a.trim_prefix("--out=")

## En _initialize la raíz todavía no está en el árbol y main._ready() no corre
## (primer intento del 2026-11-16: huellas vacías, error del instrumento).
func _process(_delta: float) -> bool:
	if _done: return true
	_done = true
	_run()
	return true

func _run() -> void:
	var base := _fingerprint()
	var same := _fingerprint()
	check("F10_huella_igual_misma_configuracion", base == same and base.length() == 64, "%s / %s" % [base, same])
	for key in ["physics/3d/default_gravity", "physics/3d/default_linear_damp",
		"physics/jolt_physics_3d/simulation/penetration_slop"]:
		var original = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, float(original) * 1.1 + 0.0001)
		var changed := _fingerprint()
		ProjectSettings.set_setting(key, original)
		check("F10_huella_cambia_" + key.get_file(), changed != base and changed.length() == 64,
			"%s: %s -> %s; %s" % [key, str(original), str(float(original) * 1.1 + 0.0001), changed])
	var restored := _fingerprint()
	check("F10_huella_restaurada", restored == base, restored)
	var fails := 0
	for r in results:
		if not r.ok: fails += 1
	var text := JSON.stringify({"schema": 1, "results": results, "fails": fails}, "  ", false, true)
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	for r in results:
		print("%s %s %s" % ["PASS" if r.ok else "FAIL", r.id, r.detail])
	print("FINGERPRINT_DONE pass=%d fail=%d" % [results.size() - fails, fails])
	quit(0)

func check(id: String, ok: bool, detail := "") -> void:
	results.append({"id": id, "ok": ok, "detail": detail})

func _fingerprint() -> String:
	var m: Node = MainScene.instantiate()
	root.add_child(m)
	var value: String = m.fingerprint()
	root.remove_child(m)
	m.free()
	return value
