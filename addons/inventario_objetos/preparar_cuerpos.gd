extends SceneTree

## Prepara el cuerpo físico de los ítems de un catálogo (desde el 2026-11-15,
## docs/net/prompt_claude_revision_objetos_fisicos.md): para cada uno sin cuerpo
## preparado, elige uno (InvItemPhysics.suggest: una caja ajustada si el modelo
## es una caja, una forma convexa si es compacto, varias si tiene huecos), arma
## las formas del modelo con la herramienta de Godot (InvItemPhysics.generate) y
## guarda el .tres del ítem. Es lo mismo que hace el panel Objetos al guardar,
## para todos a la vez, y da siempre lo mismo con el mismo modelo.
##
## No toca un cuerpo que ya sirve: una caja, esfera, cilindro o forma propia, o
## las formas del modelo ya preparadas y al día. Si algo no se puede generar, lo
## dice y no guarda ese ítem.
##
## Se corre con el Godot del editor (la descomposición en varias formas solo
## está en el editor), con el proyecto cerrado:
##
##   Godot_v4.7.2.exe --headless --path . --script res://addons/inventario_objetos/preparar_cuerpos.gd
##
## Con `-- --catalogo=res://otro_catalogo.tres`, otro catálogo; con `-- --probar`,
## dice lo que haría sin guardar nada.

const DEFAULT_CATALOG := "res://scenes/net_lab/inventario/catalogo_de_prueba.tres"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog_path := DEFAULT_CATALOG
	var dry := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--catalogo="):
			catalog_path = arg.trim_prefix("--catalogo=")
		elif arg == "--probar":
			dry = true
	var catalog := load(catalog_path) as InvCatalog
	if catalog == null:
		printerr("[preparar_cuerpos] no se pudo leer el catálogo %s" % catalog_path)
		quit(1)
		return
	var saved := 0
	var kept := 0
	var failed := 0
	for def: InvItemDef in catalog.items:
		if def == null:
			continue
		var name := "%s (%s)" % [def.display_name, def.resource_path.get_file()]
		var body := def.body_shape
		if body != null and body.problems().is_empty() and (body.kind != InvPickupHitbox.Kind.MODEL
				or InvItemPhysics.status_of(def) == "preparado"):
			print("[preparar_cuerpos] %s: ya tiene cuerpo (%s), no se toca" % [name, body.effective_text()])
			kept += 1
			continue
		var chosen := body if body != null and body.problems().is_empty() else InvItemPhysics.suggest(def)
		var t0 := Time.get_ticks_msec()
		var notes := PackedStringArray()
		if chosen.kind == InvPickupHitbox.Kind.MODEL:
			var result := InvItemPhysics.generate(def, chosen)
			if not result["ok"]:
				printerr("[preparar_cuerpos] %s: no se pudo generar (%s); no se guarda" % [name, result["problem"]])
				failed += 1
				continue
			notes = result["notes"]
		def.body_shape = chosen
		InvItemPhysics.clear_cache()
		var parts := InvItemPhysics.parts(def)
		var area := InvItemPhysics.body_bounds(def)
		print("[preparar_cuerpos] %s: %s, %d %s en %d ms; ocupa %s (el modelo, %s)%s" % [name, chosen.effective_text(), parts.size(),
				"forma" if parts.size() == 1 else "formas", Time.get_ticks_msec() - t0, _cm(area.size), _cm(InvReach.item_bounds(def).size),
				(". " + " ".join(notes)) if not notes.is_empty() else ""])
		if dry:
			continue
		# El identificador (UID) del archivo, para que lo que lo nombra por él (el
		# catálogo, las escenas) lo siga encontrando: sin el editor abierto, Godot
		# guarda sin él.
		var uid := _uid_of(def.resource_path)
		var error := ResourceSaver.save(def, def.resource_path)
		if error == OK and uid != "" and _uid_of(def.resource_path) != uid:
			error = _put_uid(def.resource_path, uid)
		if error != OK:
			printerr("[preparar_cuerpos] %s: no se pudo guardar (%s)" % [name, error_string(error)])
			failed += 1
			continue
		saved += 1
	print("[preparar_cuerpos] listo: %d guardados, %d sin tocar, %d con problemas%s" % [saved, kept, failed,
			" (solo probando: no se guardó nada)" if dry else ""])
	quit(1 if failed > 0 else 0)


## El uid="uid://…" de la cabecera de un .tres, o "".
static func _uid_of(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var head := file.get_line()
	var at := head.find(" uid=\"")
	if at < 0:
		return ""
	var start := at + 6
	return head.substr(start, head.find("\"", start) - start)


## Le vuelve a poner a la cabecera del .tres su uid.
static func _put_uid(path: String, uid: String) -> Error:
	var text := FileAccess.get_file_as_string(path)
	var end := text.find("]")
	if not text.begins_with("[gd_resource") or end < 0:
		return ERR_FILE_CORRUPT
	var head := text.substr(0, end)
	var at := head.find(" uid=\"")
	if at >= 0:
		head = head.substr(0, at) + head.substr(head.find("\"", at + 6) + 1)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(head + " uid=\"%s\"" % uid + text.substr(end))
	return OK


static func _cm(size: Vector3) -> String:
	return "%.1f × %.1f × %.1f cm" % [size.x * 100.0, size.y * 100.0, size.z * 100.0]
