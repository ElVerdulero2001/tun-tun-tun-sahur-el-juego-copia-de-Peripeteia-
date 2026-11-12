extends Node

## Prueba con ventana (no anda sin pantalla): arma un inventario con objetos,
## abre la caja compartida y saca capturas de la interfaz, del arrastre, del
## menú, de la inspección y del mundo con lo equipado y lo soltado. Comprueba
## que las miniaturas salgan del modelo, con fondo transparente. No toma el
## mouse. Las capturas van a --out=CARPETA (si no, a user://).
##
## --path . --scene res://scenes/net_lab/inventario/pruebas/inv_visual_test.tscn -- --out=C:/carpeta

const ZONE := Vector3(37, 0, 13)
const Op := InvProtocol.Op
## Recoger y abrir llevan la dirección de la mano (desde el 2026-11-11 a la noche).
const Mano := preload("res://scenes/net_lab/inventario/pruebas/inv_mano_de_prueba.gd")
const Items := preload("inv_items_de_prueba.gd")

var lab: Node3D
var net: InvNet
var ui: InvUI
var actor: ActorBody
var out_dir := "user://"
var _answers := {}
var _checks := 0
var _failures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[inv_visual_test] TIEMPO AGOTADO")
		get_tree().quit(2))
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	# La miniatura alargada y el encuadre de la barra se miden con una barra de
	# prueba en memoria, de valores conocidos, y no con el machete, que es
	# contenido que se edita (PRU-01).
	var bar_def := Items.add_bar(lab)
	add_child(lab)
	net = lab.get_node("Inventario")
	ui = lab.get_node("Hud/InventarioUI")
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	await get_tree().process_frame
	# Que la cámara no le tome el mouse a quien esté usando la PC.
	lab._camera.hold_mouse(self)
	lab._start(0)
	for i in 120:
		await get_tree().physics_frame
		if net.replica.own != null and is_instance_valid(lab._local_actor):
			break
	actor = lab._local_actor
	for def_id in [&"botella", &"machete", &"linterna", &"banquito", &"caja_de_herramientas", &"tornillos", &"bateria", &"granada", &"llave",
			Items.BAR_ID]:
		for uid in _world_uids(def_id):
			# Desde el 2026-11-11 a la noche los objetos sueltos tapan a los de
			# atrás (el rayo de la mano toca lo primero): se para del lado desde el
			# que se lo ve.
			for side: Vector3 in [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0)]:
				await _teleport(net.replica.world[uid]["pos"] + side)
				if Mano.in_sight(net, actor, Op.PICKUP, uid):
					break
			await _req(Op.PICKUP, [uid], [uid])
	var machete := _own(&"machete")
	await _req(Op.EQUIP, [machete, net.replica.own.get_stack(machete).ver], [machete])
	await _req(Op.HOTBAR_SET, [0, _own(&"botella")])
	await _req(Op.HOTBAR_SET, [1, _own(&"linterna")])
	await _req(Op.HOTBAR_SET, [2, machete])
	var bar := _own(Items.BAR_ID)
	await _req(Op.HOTBAR_SET, [3, bar])
	var torch := _own(&"linterna")
	var place := _free(Vector2i(2, 1))
	await _req(Op.MOVE, [0, torch, net.replica.own.get_stack(torch).ver, 0, place.x, place.y, 1], [torch])
	var crate := net.container(1)
	await _teleport(crate.global_position + Vector3(-1.3, 0, 0.4), deg_to_rad(-60.0))
	await _req(Op.OPEN, [1])
	var bench := _own(&"banquito")
	await _req(Op.MOVE, [0, bench, net.replica.own.get_stack(bench).ver, 1, 1, 1, 0], [bench])
	var bottle := _own(&"botella")
	await _req(Op.DROP, [0, bottle, net.replica.own.get_stack(bottle).ver, 1], [bottle])
	ui.open()
	# Las miniaturas se hacen de a una: se espera a que estén todas.
	var limit := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < limit and (ui.thumbnails._busy or not ui.thumbnails._queue.is_empty()
			or ui.thumbnails.rendered < 6):
		await get_tree().process_frame
	print("[inv_visual_test] miniaturas hechas %d, fallidas %d" % [ui.thumbnails.rendered, ui.thumbnails.failed])
	_check(ui.thumbnails.rendered >= 6 and ui.thumbnails.failed == 0, "las miniaturas se hicieron con el modelo")
	for def_id in [&"botella", &"linterna", &"machete", &"caja_de_herramientas", Items.BAR_ID]:
		var image := ui.thumbnails.image_for(net.catalog.find(def_id))
		if image == null:
			_check(false, "hay miniatura de %s" % def_id)
			continue
		image.convert(Image.FORMAT_RGBA8)
		var corner := image.get_pixel(1, 1).a
		var covered := 0
		for y in range(0, image.get_height(), 4):
			for x in range(0, image.get_width(), 4):
				if image.get_pixel(x, y).a > 0.5:
					covered += 1
		var samples := ceili(image.get_height() / 4.0) * ceili(image.get_width() / 4.0)
		_check(corner < 0.05 and covered > samples * 0.02, "%s: fondo transparente (%.2f) y modelo visible (%d de %d)" % [
				def_id, corner, covered, samples])
		image.save_png(out_dir.path_join("miniatura_%s.png" % def_id))
	ui._layout()
	var icon_rect := ui._slot_rect(3).grow(-3)
	# La barra de prueba: 1 × 3, con la miniatura de fábrica y sin encuadre
	# propio en la barra rápida (PRU-01).
	var bar_image := ui.thumbnails.image_for(bar_def)
	_check(bar_image != null and bar_image.get_height() > bar_image.get_width(), "la barra de prueba tiene su miniatura alargada")
	if bar_image != null:
		var pixels := Vector2(bar_image.get_size())
		var icon := InvThumbnails.fit_rect(icon_rect, pixels)
		_check(icon_rect.encloses(icon) and icon.get_center().is_equal_approx(icon_rect.get_center())
				and is_equal_approx(icon.size.aspect(), pixels.aspect()),
				"el ícono alargado entra centrado y sin deformarse en la barra rápida")
	await _shot("1_inventario_y_caja")
	# Que las dos sean null también da "iguales": primero, que haya textura.
	var shared := ui.thumbnails.texture_for(bar_def, true)
	_check(not bar_def.custom_hotbar_thumbnail and shared != null and shared == ui.thumbnails.texture_for(bar_def),
			"sin un encuadre propio, la barra comparte la textura de la grilla (y la hay)")
	bar_def.custom_hotbar_thumbnail = true
	bar_def.hotbar_thumbnail_rotation = Vector3(0, 0, -45)
	bar_def.hotbar_thumbnail_offset = Vector2(0.05, -0.03)
	ui.queue_redraw()
	var icon_deadline := Time.get_ticks_msec() + 5000
	var custom_icon: Image
	while custom_icon == null and Time.get_ticks_msec() < icon_deadline:
		await get_tree().process_frame
		custom_icon = ui.thumbnails.image_for(bar_def, true)
	_check(custom_icon != null and custom_icon.get_width() == custom_icon.get_height()
			and ui.thumbnails.texture_for(bar_def, true) != ui.thumbnails.texture_for(bar_def)
			and bar_image != null and bar_image.get_data() == ui.thumbnails.image_for(bar_def).get_data(),
			"la barra genera un ícono cuadrado propio, con otra textura, y la imagen de la grilla sigue igual")
	await _shot("1b_miniatura_propia_en_la_barra")
	# En la mano, girada 90° sobre un lugar libre (verde), después 180° y 270°,
	# y sobre otro objeto (rojo).
	var tools := _own(&"caja_de_herramientas")
	ui._mouse = ui._item_rect(0, tools).position + Vector2(ui._cs * 0.5, ui._cs * 0.5)
	ui._pick_up(0, tools)
	ui._rotate_held()
	var free := _free(Vector2i(2, 3))
	ui._mouse = ui._grid_rect(0).position + (Vector2(free) + Vector2(1.5, 0.5)) * ui._cs
	await _shot("2_en_la_mano_girado_90")
	ui._rotate_held()
	await _shot("2b_girado_180")
	ui._rotate_held()
	await _shot("2c_girado_270")
	ui._rotate_held()
	ui._rotate_held()
	ui._mouse = ui._item_rect(0, machete).get_center()
	await _shot("3_en_la_mano_sobre_otro")
	ui._mouse = ui._grid_rect(1).position + Vector2(5.5, 5.5) * ui._cs
	await _shot("4_en_la_mano_sobre_la_caja")
	ui._cancel_mode("")
	# Tres clics derechos sobre un lugar libre: una pila de 3 y el resto en la mano.
	var screws := _own(&"tornillos")
	var screws_before := net.replica.own.get_stack(screws).quantity
	ui._mouse = ui._item_rect(0, screws).get_center()
	ui._pick_up(0, screws)
	var spot := _free(Vector2i.ONE)
	ui._mouse = ui._grid_rect(0).position + (Vector2(spot) + Vector2(0.5, 0.5)) * ui._cs
	for i in 3:
		ui._right_press()
	for i in 20:
		await get_tree().physics_frame
	var left_behind := net.replica.own.uid_at(spot)
	_check(left_behind != 0 and net.replica.own.get_stack(left_behind).quantity == 3
			and net.replica.own.get_stack(screws).quantity == screws_before - 3 and ui._mode == InvUI.Mode.HOLD,
			"tres clics derechos dejan 3 y el resto sigue en la mano")
	ui._mouse += Vector2(ui._cs * 2.5, ui._cs * 1.5)
	await _shot("10_clic_derecho_tres")
	ui._cancel_mode("")
	# Con la mano vacía, el cursor sobre un objeto muestra su nombre.
	ui._mouse = ui._item_rect(0, _own(&"bateria")).get_center()
	_check(ui._hover_name() == net.replica.own.def_of(_own(&"bateria")).display_name, "el cursor sobre la batería muestra su nombre")
	await _shot("11_nombre_al_pasar")
	ui._mouse = ui._item_rect(0, _own(&"tornillos")).get_center()
	ui._open_menu(0, _own(&"tornillos"))
	await _shot("5_menu_contextual")
	ui._close_menu()
	ui._show_inspect(0, _own(&"bateria"))
	await _shot("6_inspeccion")
	ui._inspect.hide()
	ui._open_dialog("split", 0, _own(&"tornillos"))
	await _shot("7_dividir")
	ui._close_dialog()
	ui.close()
	lab._info.visible = false
	lab._camera.pitch = -0.25
	lab._camera.yaw = actor.state.facing_yaw - PI / 2.0
	await _shot("8_mundo_equipado_derecha")
	lab._camera.yaw = actor.state.facing_yaw + PI * 0.8
	await _shot("9_mundo_equipado_frente")
	print("[inv_visual_test] %d comprobaciones, %d fallas · capturas en %s" % [_checks, _failures, ProjectSettings.globalize_path(out_dir)])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("[inv_visual_test] %s: %s" % ["ok" if ok else "FALLA", what])


func _shot(file_name: String) -> void:
	var mouse := ui._mouse
	for i in 6:
		ui._mouse = mouse
		ui.queue_redraw()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(out_dir.path_join("%s.png" % file_name))


func _req(op: int, args: Array, uids: Array = []) -> Array:
	args = Mano.aimed(net, lab._local_actor, op, args)
	var seq := net.replica.request(op, args, uids)
	if seq == 0:
		return [false, "no salió"]
	for i in 30:
		if _answers.has(seq):
			return _answers[seq]
		await get_tree().physics_frame
	return [false, "sin respuesta"]


func _teleport(position: Vector3, yaw := 0.0) -> void:
	var state := actor.state
	state.position = position
	state.velocity = Vector3.ZERO
	state.facing_yaw = yaw
	state.mode = ActorState.Mode.GROUND
	state.on_floor = true
	state.base_id = 0
	state.quantize()
	actor.apply_state(state)
	actor.teleported()
	for i in 3:
		await get_tree().physics_frame


func _world_uids(def_id: StringName) -> Array:
	var list := []
	for uid in net.replica.world:
		if net.replica.world[uid]["stack"].def_id == def_id:
			list.append(uid)
	list.sort()
	return list


func _own(def_id: StringName) -> int:
	for uid in net.replica.own.sorted_uids():
		if net.replica.own.stacks[uid].def_id == def_id:
			return uid
	return 0


func _free(foot: Vector2i) -> Vector2i:
	for y in net.replica.own.rows:
		for x in net.replica.own.columns:
			if net.replica.own.fits(foot, Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i.ZERO
