extends Node

## Prueba de la hitbox de agarre (InvPickupHitbox, desde el 2026-11-07), dentro
## del laboratorio de verdad, con su cámara, su indicador y E. Desde el
## 2026-11-11 a la noche (el rayo de la mano, InvReach) la hitbox se guarda, se
## valida y entra en la huella, pero en el juego no elige ni deja agarrar: el
## rayo desde los ojos tiene que tocar el modelo. Esta prueba lo comprueba.
##
## No cambia ningún archivo: al arrancar, en memoria, le pone a la llave
## (llave.tres) una caja apenas más grande que su modelo, suma al catálogo dos
## «marcos de prueba» alargados con un hueco en el medio (uno con caja y otro
## sin hitbox, con el origen del modelo lejos de lo que se ve) y los coloca con
## InvPickupSpawn en un lugar despejado del piso, junto a una granada (sin
## hitbox) pegada a la llave.
##
## Sin argumentos, un proceso jugando solo:
##
## - los datos: la huella con números estables, una copia da lo mismo, cambiar
##   1 mm la cambia; las formas que no sirven se rechazan; una forma convexa
##   propia se arma bien (la usa la vista previa del panel Objetos);
## - lo que se arma en el mundo: ninguna forma para apuntar, y el indicador
##   enmarca el modelo;
## - la línea de la mira: dentro de la hitbox y fuera del modelo, no se elige;
##   por el modelo, sí; la granada, a 3 mm, tampoco (no hay margen);
## - con dos objetos cerca, gana el primero que toca el rayo;
## - el marco: por el hueco, la mira llega al piso y no se elige (tampoco el
##   que no tiene hitbox); por una barra, sí; con una pared en el medio no, y
##   el host no deja recogerlo; con una pared que cruza el marco, la barra de
##   este lado sí y la de atrás no; E lo recoge, y soltado, igual;
## - la llave con la cámara, en primera persona: al costado (en su hitbox) no;
##   por el modelo, marcada con el marco del modelo; E la recoge, y la soltada
##   igual;
## - en tercera persona, lo mismo con la otra llave y el marco;
## - las hitbox de otros objetos delante no tapan (AG-02).
##
##   --headless --fixed-fps 60 --scene res://scenes/net_lab/inventario/pruebas/inv_hitbox_test.tscn
##
## Con --hitbox-pair=host o client, en dos procesos, con los argumentos de red
## del laboratorio (--host --bind=127.0.0.1 --port=N o --client
## --address=127.0.0.1 --port=N): el cliente camina hasta el marco, no lo
## marca por el hueco, lo marca por una barra y lo recoge con E; el host lo
## valida, y mientras tanto marca y recoge la llave por su modelo, en tercera
## persona. Sin --fixed-fps.
##
## Con --hitbox-pair=host_rechaza y client_distinto, el cliente le pone a la
## llave una hitbox 1 mm más ancha: la huella no coincide, el host no lo deja
## entrar y el aviso dice que difiere en el inventario.
##
## Con --hitbox-detalle escribe también cada comprobación que dio bien.

const Op := InvProtocol.Op
## Recoger y abrir llevan la dirección de la mano (desde el 2026-11-11 a la noche).
const Mano := preload("res://scenes/net_lab/inventario/pruebas/inv_mano_de_prueba.gd")
## Un lugar despejado del piso grande del nivel, lejos de las pistas.
const BASE := Vector3(18.0, 0.0, 22.0)
const KEY_SPOT := BASE
## La granada, 30 cm detrás de la llave mirando hacia +x.
const GRENADE_SPOT := BASE + Vector3(0.3, 0.0, 0.0)
const FRAME_SPOT := BASE + Vector3(0.0, 0.0, 3.0)
const PLAIN_FRAME_SPOT := BASE + Vector3(0.0, 0.0, 5.0)
const KEY2_SPOT := BASE + Vector3(0.0, 0.0, 7.0)
## Cuánto más grande que el modelo es la hitbox de la llave, por cada lado.
const KEY_EXTRA := 0.015
## El marco, acostado: largo (z), ancho (x), alto (y) y ancho de sus barras.
const FRAME_LENGTH := 0.8
const FRAME_WIDTH := 0.24
const FRAME_HEIGHT := 0.03
const FRAME_BAR := 0.04
## Cuánto más grande que el modelo es la hitbox del marco, por cada lado.
const FRAME_EXTRA := 0.01
## Dónde tiene el origen el modelo del marco, respecto de lo que se ve: lejos.
const FRAME_ORIGIN := Vector3(2.5, 1.2, -1.7)
## Una capa libre, para probar una forma propia sin que la vea la mira.
const SPARE_LAYER := 1 << 9
## Dónde se para, respecto de lo que mira: en primera persona, atrás; en
## tercera, atrás y al costado, para que el cuerpo no lo tape.
const NEAR_FIRST := Vector3(-1.1, 0, 0)
const NEAR_THIRD := Vector3(-1.45, 0, -0.65)
## Lo de la auditoría del 2026-11-08, solo jugando solo: un bloque que su
## modelo llena justo (una caja de 30 × 15 × 30 cm). Hasta el 2026-11-11 un
## bloque así servía también para AG-01 (la esfera del margen que ya toca al
## salir); sin margen, esa prueba no tiene sentido y se sacó.
const BLOCK_SIZE := Vector3(0.3, 0.15, 0.3)
## AG-02: en dos carriles, un bloque al alcance y más allá PLATES láminas de
## objetos que quedan lejos (fuera del alcance), con la hitbox adelantada 2 m:
## tapan la línea entre el personaje y el bloque. Son más que las 8 que antes
## alcanzaban para que la mira no llegara a lo de atrás. En un carril el bloque
## se elige por su modelo; en el otro, por su hitbox (como las láminas: el caso
## en que antes no se elegía).
const TARGET_SPOT := BASE + Vector3(-0.5, 0.0, 4.0)
const PLATE_SPOT := BASE + Vector3(1.0, 0.0, 4.0)
const BOXED_SPOT := BASE + Vector3(-0.5, 0.0, 6.0)
const BOXED_PLATE_SPOT := BASE + Vector3(1.0, 0.0, 6.0)
const PLATES := 9
const PLATE_REACH := -2.0

var role := ""
var verbose := false
var lab: Node3D
var net: InvNet
var ui: InvUI
var camera: LabCamera
var view_camera: Camera3D
var indicator: InteractIndicator
var actor: ActorBody
var catalog: InvCatalog
var key_def: InvItemDef
var grenade_def: InvItemDef
var frame_def: InvItemDef
var plain_frame_def: InvItemDef
var block_def: InvItemDef
var boxed_def: InvItemDef
var plate_def: InvItemDef
var _answers := {}
var _checks := 0
var _failures := 0
var _finishing := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--hitbox-pair="):
			role = arg.trim_prefix("--hitbox-pair=")
		elif arg == "--hitbox-detalle":
			verbose = true
	get_tree().create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		_failures += 1
		_log("TIEMPO AGOTADO: el recorrido no terminó")
		_finish())
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	_prepare_items()
	add_child(lab)
	net = lab.get_node("Inventario")
	ui = lab.get_node("Hud/InventarioUI")
	camera = lab.get_node("CameraRig")
	view_camera = camera.get_node("SpringArm/Camera")
	indicator = lab.get_node_or_null("Hud/Indicador") as InteractIndicator
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	match role:
		"":
			_solo()
		"host":
			_pair_host()
		"client":
			_pair_client()
		"host_rechaza":
			_host_refuses()
		"client_distinto":
			_client_refused()
		_:
			_log("--hitbox-pair tiene que ser host o client")
			get_tree().quit(3)


## Lo de la prueba, en memoria y antes de que arranque el inventario (así lo
## hacen igual el host y el cliente, y la huella coincide).
func _prepare_items() -> void:
	catalog = (lab.get_node("Inventario") as InvNet).catalog
	key_def = catalog.find(&"llave")
	grenade_def = catalog.find(&"granada")
	var key_hitbox := InvPickupHitbox.new()
	key_hitbox.kind = InvPickupHitbox.Kind.BOX
	key_hitbox.fit(InvPickupHitbox.model_bounds(key_def))
	key_hitbox.grow(KEY_EXTRA)
	if role == "client_distinto":
		key_hitbox.box_size.x += 0.001
	key_def.pickup_hitbox = key_hitbox
	frame_def = _frame_def(&"marco_de_prueba", "Marco de prueba", true)
	plain_frame_def = _frame_def(&"marco_sin_hitbox", "Marco sin hitbox", false)
	catalog.items.append(frame_def)
	catalog.items.append(plain_frame_def)
	var level := lab.get_node("Level")
	_add_spawn(level, "LlaveDePrueba", key_def, KEY_SPOT, false)
	_add_spawn(level, "GranadaDePrueba", grenade_def, GRENADE_SPOT, true)
	_add_spawn(level, "MarcoDePrueba", frame_def, FRAME_SPOT, true)
	_add_spawn(level, "MarcoSinHitbox", plain_frame_def, PLAIN_FRAME_SPOT, true)
	_add_spawn(level, "OtraLlaveDePrueba", key_def, KEY2_SPOT, true)
	# Lo de la auditoría del 2026-11-08 (AG-01, AG-02), solo jugando solo: en
	# pareja la huella tiene que coincidir con lo de siempre.
	if role == "":
		block_def = InvItemDef.new()
		block_def.id = &"bloque_de_prueba"
		block_def.display_name = "Bloque de prueba"
		var block := BoxMesh.new()
		block.size = BLOCK_SIZE
		block_def.mesh = block
		block_def.world_size = maxf(BLOCK_SIZE.x, maxf(BLOCK_SIZE.y, BLOCK_SIZE.z))
		plate_def = InvItemDef.new()
		plate_def.id = &"lamina_lejana"
		plate_def.display_name = "Lámina lejana"
		var chip := BoxMesh.new()
		chip.size = Vector3.ONE * 0.04
		plate_def.mesh = chip
		plate_def.world_size = 0.04
		var plate := InvPickupHitbox.new()
		plate.kind = InvPickupHitbox.Kind.BOX
		plate.box_size = Vector3(0.01, 0.8, 0.4)
		plate.offset = Vector3(PLATE_REACH, 0.4, 0.0)
		plate_def.pickup_hitbox = plate
		boxed_def = InvItemDef.new()
		boxed_def.id = &"bloque_con_hitbox"
		boxed_def.display_name = "Bloque con hitbox"
		boxed_def.mesh = block
		boxed_def.world_size = block_def.world_size
		var boxed := InvPickupHitbox.new()
		boxed.kind = InvPickupHitbox.Kind.BOX
		boxed.fit(InvPickupHitbox.model_bounds(boxed_def))
		boxed.grow(0.01)
		boxed_def.pickup_hitbox = boxed
		catalog.items.append(block_def)
		catalog.items.append(boxed_def)
		catalog.items.append(plate_def)
		_add_spawn(level, "BloqueDetrasDeLaminas", block_def, TARGET_SPOT, true)
		_add_spawn(level, "BloqueConHitboxDetrasDeLaminas", boxed_def, BOXED_SPOT, true)
		for i in PLATES:
			_add_spawn(level, "LaminaLejana%d" % i, plate_def, PLATE_SPOT + Vector3(0.02 * i, 0.0, 0.0), false)
			_add_spawn(level, "OtraLaminaLejana%d" % i, plate_def, BOXED_PLATE_SPOT + Vector3(0.02 * i, 0.0, 0.0), false)


## Un marco alargado con un hueco en el medio: cuatro barras, con el origen del
## modelo lejos de ellas. Con `with_hitbox`, una caja ajustada a él y 1 cm más
## grande por cada lado, que tapa el hueco.
func _frame_def(id: StringName, shown: String, with_hitbox: bool) -> InvItemDef:
	var root := Node3D.new()
	root.name = "Marco"
	var long_bar := Vector3(FRAME_BAR, FRAME_HEIGHT, FRAME_LENGTH)
	var short_bar := Vector3(FRAME_WIDTH - 2.0 * FRAME_BAR, FRAME_HEIGHT, FRAME_BAR)
	for part: Array in [[long_bar, Vector3(-(FRAME_WIDTH - FRAME_BAR) / 2.0, 0, 0)], [long_bar, Vector3((FRAME_WIDTH - FRAME_BAR) / 2.0, 0, 0)],
			[short_bar, Vector3(0, 0, -(FRAME_LENGTH - FRAME_BAR) / 2.0)], [short_bar, Vector3(0, 0, (FRAME_LENGTH - FRAME_BAR) / 2.0)]]:
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		bar.mesh = mesh
		bar.position = FRAME_ORIGIN + part[1]
		root.add_child(bar)
		bar.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	var def := InvItemDef.new()
	def.id = id
	def.display_name = shown
	def.size = Vector2i(1, 3)
	def.model = packed
	def.world_size = FRAME_LENGTH
	if with_hitbox:
		var hitbox := InvPickupHitbox.new()
		hitbox.kind = InvPickupHitbox.Kind.BOX
		hitbox.fit(InvPickupHitbox.model_bounds(def))
		hitbox.grow(FRAME_EXTRA)
		def.pickup_hitbox = hitbox
	return def


func _add_spawn(parent: Node, node_name: String, def: InvItemDef, spot: Vector3, show_label: bool) -> void:
	var spawn := InvPickupSpawn.new()
	spawn.name = node_name
	spawn.item = def
	spawn.show_label = show_label
	# El nivel está en el origen: su posición es la del mundo.
	spawn.position = spot
	parent.add_child(spawn)


# --- Ayudas ---------------------------------------------------------------------

func _log(text: String) -> void:
	print("[inv_hitbox%s] %s" % [":" + role if role != "" else "", text])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		_log("FALLA: %s" % what)
	elif role != "" or verbose:
		_log("ok: %s" % what)


## Sale bien solo si el recorrido llegó al final, con alguna comprobación y sin fallas.
func _finish(completed := false) -> void:
	if _finishing:
		return
	_finishing = true
	if not completed:
		_failures += 1
		_log("FALLA: el recorrido no llegó al final")
	_log("%d comprobaciones, %d fallas" % [_checks, _failures])
	if role == "client":
		lab._session.say_goodbye()
	for i in 10:
		await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _until(condition: Callable, seconds: float) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < limit:
		if condition.call():
			return true
		await get_tree().physics_frame
	return false


func _req(op: int, args: Array, uids: Array = []) -> Array:
	args = Mano.aimed(net, lab._local_actor, op, args)
	var seq := net.replica.request(op, args, uids)
	if seq == 0:
		return [false, "no salió"]
	if not await _until(func() -> bool: return _answers.has(seq), 5.0):
		return [false, "sin respuesta"]
	return _answers[seq]


## Mueve al personaje propio de golpe (jugando solo o en el host, que es la autoridad).
func _teleport(position: Vector3, yaw: float) -> void:
	var state := actor.state
	state.position = position
	state.velocity = Vector3.ZERO
	state.facing_yaw = yaw
	state.mode = ActorState.Mode.GROUND
	state.on_floor = true
	state.base_id = 0
	if role == "host":
		state.epoch += 1
	state.quantize()
	actor.apply_state(state)
	actor.teleported()
	await _ticks(3)
	await _frames(2)


## Se para en `point + offset` (sobre el piso), mirando hacia `point`.
func _stand_by(point: Vector3, offset: Vector3) -> void:
	var feet := Vector3(point.x + offset.x, 0.0, point.z + offset.z)
	var toward := point - feet
	await _teleport(feet, atan2(-toward.x, -toward.z))


func _set_first_person(first: bool) -> void:
	camera._wanted_zoom = 0.0 if first else 1.0
	camera._zoom = camera._wanted_zoom
	await _frames(3)


## Gira la cámara para que el centro de la pantalla pase por ese punto.
func _aim(point: Vector3) -> void:
	for i in 6:
		var from := camera.global_position if i == 0 else view_camera.global_position
		var direction := (point - from).normalized()
		camera.yaw = atan2(-direction.x, -direction.z)
		camera.pitch = asin(clampf(direction.y, -1.0, 1.0))
		await _frames(2)


func _world_uid(def_id: StringName) -> int:
	var keys := net.replica.world.keys()
	keys.sort()
	for uid in keys:
		if net.replica.world[uid]["stack"].def_id == def_id and not net.replica.is_taken(uid):
			return uid
	return 0


## El objeto suelto que está en ese lugar, o 0.
func _uid_at(spot: Vector3) -> int:
	for uid in net.replica.world:
		if (net.replica.world[uid]["pos"] as Vector3).distance_to(spot) < 0.05 and not net.replica.is_taken(uid):
			return uid
	return 0


## La caja del modelo de ese objeto suelto, en el mundo: la que enmarca el indicador.
func _model_box(uid: int) -> AABB:
	var view := net.world_view(uid)
	var box := view.interact_focus().bounds
	box.position += view.global_position
	return box


## La caja de su hitbox de agarre, en el mundo.
func _hitbox_box(uid: int, def: InvItemDef) -> AABB:
	var box := def.pickup_hitbox.bounds()
	box.position += net.world_view(uid).global_position
	return box


## Lo que elegiría la mira (y E) con esa línea, en primera persona.
func _chosen(from: Vector3, direction: Vector3) -> int:
	var seen := net.interaction_target(actor, from, direction, false)
	return seen.get("id", 0) if seen.get("kind", "") == "item" else 0


## Si el segmento toca algún triángulo del modelo de ese objeto suelto.
func _touches_model(uid: int, from: Vector3, to: Vector3) -> bool:
	var view := net.world_view(uid)
	var model := view.get_child(0) as Node3D
	var faces := view.global_transform * model.transform * InvVisuals.faces(model)
	for i in range(0, faces.size(), 3):
		if Geometry3D.segment_intersects_triangle(from, to, faces[i], faces[i + 1], faces[i + 2]) != null:
			return true
	return false


## Dónde toca el piso (o lo primero del nivel) la línea, o `from + direction * 6`.
func _floor_point(from: Vector3, direction: Vector3) -> Vector3:
	var space := lab.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + direction * 6.0, InvAuthority.WORLD_MASK))
	return from + direction * 6.0 if hit.is_empty() else hit["position"]


## Si el indicador marca ese objeto suelto y E elegiría ese mismo.
func _marks(uid: int) -> bool:
	var focus := indicator.marked_focus()
	var target := ui.interaction_target()
	return focus != null and focus.anchor == net.world_view(uid) and target.get("kind", "") == "item" \
			and target.get("id", 0) == uid and indicator.marked_frame().has_area()


func _describe() -> String:
	var focus := indicator.marked_focus()
	return "marca «%s» en %s; E elegiría %s" % [indicator.shown_name(), indicator.marked_frame(), ui.interaction_target()] \
			if focus != null else "no marca nada; E elegiría %s" % [ui.interaction_target()]


func _hidden() -> bool:
	return indicator.marked_focus() == null and not indicator.marked_frame().has_area() and indicator.shown_name() == ""


## El marco que corresponde a una caja (en el espacio de `focus.anchor`) con la
## cámara como está ahora: las ocho esquinas proyectadas, el margen y el
## tamaño mínimo del indicador.
func _expected_frame(anchor: Node3D, box: AABB) -> Rect2:
	var frame := _projected(anchor, box).grow(indicator.margin)
	var missing := (Vector2.ONE * indicator.min_size - frame.size).max(Vector2.ZERO) / 2.0
	return frame.grow_individual(missing.x, missing.y, missing.x, missing.y)


## Lo que ocupa en pantalla esa caja, sin el margen ni el tamaño mínimo.
func _projected(anchor: Node3D, box: AABB) -> Rect2:
	var place := anchor.get_global_transform_interpolated()
	var points := PackedVector2Array()
	for i in 8:
		points.append(view_camera.unproject_position(place * box.get_endpoint(i)))
	var low := points[0]
	var high := points[0]
	for point in points:
		low = low.min(point)
		high = high.max(point)
	return Rect2(low, high - low)


## Que el indicador enmarque el modelo visible, no la hitbox, y diga su nombre.
func _frames_model(def: InvItemDef, what: String) -> void:
	var focus := indicator.marked_focus()
	if focus == null:
		_check(false, "%s: no hay marco" % what)
		return
	var frame := indicator.marked_frame()
	var expected := _expected_frame(focus.anchor, focus.bounds)
	var model_size := _projected(focus.anchor, focus.bounds).size
	var hitbox_size := _projected(focus.anchor, def.pickup_hitbox.bounds()).size
	_check(focus.bounds.is_equal_approx(InvPickupHitbox.model_bounds(def)) and frame.position.distance_to(expected.position) < 0.5
			and frame.size.distance_to(expected.size) < 0.5, "%s: el marco es el del modelo (%s, esperado %s)" % [what, frame, expected])
	_check(hitbox_size.x > model_size.x + 1.0 and hitbox_size.y > model_size.y + 1.0,
			"%s: en pantalla la hitbox mide %s y el modelo %s: el marco no sigue a la hitbox" % [what, hitbox_size, model_size])
	_check(indicator.shown_name() == def.display_name, "%s: con su nombre, «%s»" % [what, indicator.shown_name()])


func _press_e() -> void:
	var e_key := InputEventKey.new()
	e_key.physical_keycode = KEY_E
	e_key.pressed = true
	ui._unhandled_key_input(e_key)


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var holder := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = size
	holder.shape = slab
	wall.add_child(holder)
	add_child(wall)
	wall.global_position = center
	await _ticks(3)
	await _frames(2)
	return wall


## Suelta uno de ese tipo del inventario propio: el número del objeto nuevo en
## el piso, o 0.
func _drop_own(def_id: StringName) -> int:
	var own := net.replica.own.sorted_uids().filter(func(id: int) -> bool: return net.replica.own.stacks[id].def_id == def_id)
	if own.is_empty():
		return 0
	var before := net.replica.world.keys()
	var uid: int = own[0]
	var r := await _req(Op.DROP, [0, uid, net.replica.own.get_stack(uid).ver, 1], [uid])
	await _ticks(4)
	if not r[0]:
		return 0
	for key: int in net.replica.world:
		if not before.has(key) and net.replica.world[key]["stack"].def_id == def_id:
			return key
	return 0


## Un punto justo afuera del costado de su modelo (`side`: −z o −x), adentro
## de la hitbox, cerca del piso: así la mira llega sin tocar el modelo.
func _beside(uid: int, side: Vector3) -> Vector3:
	var model := _model_box(uid)
	var center := model.get_center()
	var low := model.position.y + 0.002
	if side == Vector3.FORWARD:
		return Vector3(center.x, low, model.position.z - 0.012)
	return Vector3(model.position.x - 0.012, low, center.z)


# --- Jugando solo ----------------------------------------------------------------

func _solo() -> void:
	await get_tree().process_frame
	lab._start(0)
	for i in 120:
		await get_tree().physics_frame
		if net.replica.own != null and is_instance_valid(lab._local_actor):
			break
	actor = lab._local_actor
	_check(actor != null and net.replica.has_state and indicator != null, "jugando solo, con el personaje, el inventario y el indicador")
	if actor == null or indicator == null:
		_finish()
		return
	_check(_clear_area(), "el lugar de la prueba está despejado, con piso")
	await _data()
	_built()
	await _lateral_lines()
	_first_along_aim()
	await _hole()
	await _key_with_camera()
	await _third_person()
	await _many_discarded()
	_finish(true)


func _clear_area() -> bool:
	var space := lab.get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.0, 10.0)
	probe.shape = box
	probe.collision_mask = InvAuthority.WORLD_MASK
	probe.transform = Transform3D(Basis.IDENTITY, BASE + Vector3(-0.5, 1.1, 3.5))
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(BASE + Vector3.UP, BASE + Vector3.DOWN, InvAuthority.WORLD_MASK))
	return space.intersect_shape(probe, 1).is_empty() and not floor_hit.is_empty() and absf(floor_hit["position"].y) < 0.01


## Los datos: la huella, lo que se rechaza y lo que vale.
func _data() -> void:
	var text := key_def.fingerprint_text()
	_check(text.contains("agarre caja ") and text.contains(" en ") and text.contains(" giro "),
			"la huella de la llave lleva su hitbox: …%s" % text.right(80))
	_check(text == key_def.duplicate(true).fingerprint_text() and text == key_def.fingerprint_text(),
			"y da igual otra vez y en una copia")
	var numbers := text.substr(text.find("agarre "), text.find(" rayo ") - text.find("agarre ")).split(" ", false)
	var four_decimals := true
	for word in numbers.slice(2):
		for part in word.split(","):
			if part.is_valid_float() and part.get_slice(".", 1).length() != 4:
				four_decimals = false
	_check(four_decimals, "sus números van con cuatro decimales, sin depender de cómo se escriban: %s" % " ".join(numbers))
	var changed := key_def.duplicate(true) as InvItemDef
	changed.pickup_hitbox.box_size.x += 0.001
	_check(changed.fingerprint_text() != text, "1 mm más ancha, cambia la huella")
	_check(grenade_def.fingerprint_text().contains(" agarre modelo "), "la granada, sin hitbox: «agarre modelo»")
	var as_model := key_def.duplicate(true) as InvItemDef
	as_model.pickup_hitbox.kind = InvPickupHitbox.Kind.MODEL
	var without := key_def.duplicate(true) as InvItemDef
	without.pickup_hitbox = null
	_check(as_model.fingerprint_text() == without.fingerprint_text() and without.fingerprint_text().contains(" agarre modelo "),
			"con «Forma del modelo», la huella es la misma que sin hitbox")
	# Lo que no sirve.
	var cases := []
	var nan_box := InvPickupHitbox.new()
	nan_box.box_size = Vector3(0.1, NAN, 0.1)
	cases.append(["una caja con un alto que no es un número", nan_box])
	var zero := InvPickupHitbox.new()
	zero.kind = InvPickupHitbox.Kind.SPHERE
	zero.sphere_radius = 0.0
	cases.append(["una esfera de radio 0", zero])
	var negative := InvPickupHitbox.new()
	negative.kind = InvPickupHitbox.Kind.CYLINDER
	negative.cylinder_height = -0.1
	cases.append(["un cilindro de alto negativo", negative])
	var far := InvPickupHitbox.new()
	far.offset = Vector3(0, INF, 0)
	cases.append(["un desplazamiento infinito", far])
	var empty := InvPickupHitbox.new()
	empty.kind = InvPickupHitbox.Kind.CUSTOM
	cases.append(["una forma personalizada sin recurso", empty])
	var hollow := InvPickupHitbox.new()
	hollow.kind = InvPickupHitbox.Kind.CUSTOM
	hollow.custom_shape = ConvexPolygonShape3D.new()
	cases.append(["una forma convexa vacía", hollow])
	var flat := InvPickupHitbox.new()
	flat.kind = InvPickupHitbox.Kind.CUSTOM
	var plane := ConvexPolygonShape3D.new()
	plane.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(0.1, 0, 0), Vector3(0, 0, 0.1), Vector3(0.1, 0, 0.1)])
	flat.custom_shape = plane
	cases.append(["una forma convexa plana", flat])
	var concave := InvPickupHitbox.new()
	concave.kind = InvPickupHitbox.Kind.CUSTOM
	var triangles := ConcavePolygonShape3D.new()
	triangles.set_faces(BoxMesh.new().get_faces())
	concave.custom_shape = triangles
	cases.append(["una forma cóncava", concave])
	for case: Array in cases:
		var hitbox: InvPickupHitbox = case[1]
		var def := InvItemDef.new()
		def.id = &"prueba_que_no_sirve"
		def.mesh = BoxMesh.new()
		def.pickup_hitbox = hitbox
		var problems := hitbox.problems()
		_check(not problems.is_empty() and InvPickupHitbox.active(def) == null and def.fingerprint_text().contains(" agarre modelo "),
				"%s se rechaza (%s): en la huella queda como «Forma del modelo»" % [case[0], " ".join(problems)])
	var broken := InvCatalog.new()
	var broken_def := InvItemDef.new()
	broken_def.id = &"prueba_que_no_sirve"
	broken_def.pickup_hitbox = empty
	broken.items.append(broken_def)
	_check(" ".join(broken.problems()).contains("hitbox de agarre"), "el catálogo avisa de la que no sirve: %s" % [broken.problems()])
	# Una forma convexa propia: un tetraedro de 30 cm, corrido y girado.
	var tetra := ConvexPolygonShape3D.new()
	tetra.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(0.3, 0, 0), Vector3(0, 0, 0.3), Vector3(0, 0.3, 0)])
	var custom := InvPickupHitbox.new()
	custom.kind = InvPickupHitbox.Kind.CUSTOM
	custom.custom_shape = tetra
	custom.offset = Vector3(0.05, 0.0, -0.05)
	custom.rotation_degrees = Vector3(0, 30, 0)
	var custom_def := InvItemDef.new()
	custom_def.id = &"prueba_convexa"
	custom_def.mesh = BoxMesh.new()
	custom_def.pickup_hitbox = custom
	_check(custom.problems().is_empty() and custom_def.fingerprint_text().contains("agarre propia ConvexPolygonShape3D"),
			"una forma convexa propia sirve: %s" % custom_def.fingerprint_text().right(60))
	# Armada como la arma la vista previa del panel (build_shape en
	# local_transform), en un Area3D de esta prueba, en una capa libre.
	var spot := BASE + Vector3(-6, 0, 0)
	var area := Area3D.new()
	area.collision_layer = SPARE_LAYER
	area.collision_mask = 0
	var holder := CollisionShape3D.new()
	holder.shape = custom.build_shape()
	area.add_child(holder)
	add_child(area)
	area.global_transform = Transform3D(Basis.IDENTITY, spot) * custom.local_transform()
	_check(holder.shape == tetra, "se arma con esa forma, tal cual")
	await _ticks(2)
	var space := lab.get_world_3d().direct_space_state
	var inside := spot + custom.local_transform() * Vector3(0.05, 0.05, 0.05)
	var outside := spot + custom.local_transform() * Vector3(0.2, 0.2, 0.2)
	var ray_to := func(point: Vector3) -> bool:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point, SPARE_LAYER)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		return not space.intersect_ray(query).is_empty()
	_check(ray_to.call(inside) and not ray_to.call(outside), "una línea que baja hasta adentro del tetraedro lo toca; hasta afuera, no")
	area.free()


## Lo que se arma en el mundo para cada tipo. Desde el 2026-11-11 a la noche,
## nada para apuntar: el objeto suelto es solo dibujo (InvWorldItem), y el rayo
## de la mano toca los triángulos del modelo del tipo (InvReach). Hasta ese
## día llevaba un Area3D con la hitbox (capa 5) o con el modelo (capa 4).
func _built() -> void:
	var key := _uid_at(KEY_SPOT)
	var key2 := _uid_at(KEY2_SPOT)
	var grenade := _uid_at(GRENADE_SPOT)
	var frame := _uid_at(FRAME_SPOT)
	var plain := _uid_at(PLAIN_FRAME_SPOT)
	_check(key != 0 and key2 != 0 and grenade != 0 and frame != 0 and plain != 0,
			"los cinco recogibles de prueba, colocados con InvPickupSpawn, están en el mundo")
	if key == 0 or key2 == 0 or grenade == 0 or frame == 0 or plain == 0:
		return
	for pair: Array in [[key, key_def], [frame, frame_def], [grenade, grenade_def], [plain, plain_frame_def]]:
		var view := net.world_view(pair[0])
		var def: InvItemDef = pair[1]
		var shapes := view.find_children("*", "CollisionObject3D", true, false)
		_check(shapes.is_empty() and InvReach.item_mesh(def) != null,
				"%s: en el mundo no lleva ninguna forma para apuntar; el rayo usa los triángulos de su modelo" % def.id)
		var model := InvPickupHitbox.model_bounds(def)
		_check(view.interact_focus().bounds.is_equal_approx(model), "%s: el indicador enmarca el modelo (%s)" % [def.id, model])
	for def: InvItemDef in [key_def, frame_def]:
		var model := InvPickupHitbox.model_bounds(def)
		var hitbox := def.pickup_hitbox.bounds()
		_check(InvPickupHitbox.active(def) != null and hitbox.encloses(model) and not model.encloses(hitbox),
				"%s: su hitbox sigue guardada y lo encierra con algo más (%s), pero el juego no la usa" % [def.id, hitbox])
	var frame_model := InvPickupHitbox.model_bounds(frame_def)
	_check(frame_model.get_center().distance_to(Vector3(0, FRAME_HEIGHT / 2.0, 0)) < 0.0005 and frame_model.size.is_equal_approx(
			Vector3(FRAME_WIDTH, FRAME_HEIGHT, FRAME_LENGTH)), "el marco, con el origen del modelo lejos, queda centrado y apoyado: %s" % frame_model)


## Líneas de costado, a la altura de la llave: dentro de la hitbox y fuera del
## modelo, no se elige (hasta el 2026-11-11, sí); por el modelo, sí. La
## granada: a 3 mm, no (sin margen); por el modelo, sí.
func _lateral_lines() -> void:
	var key := _uid_at(KEY_SPOT)
	var grenade := _uid_at(GRENADE_SPOT)
	if key == 0 or grenade == 0:
		return
	await _teleport(KEY_SPOT + NEAR_FIRST, -PI / 2.0)
	var model := _model_box(key)
	var y := model.get_center().y
	var along := func(x: float) -> int:
		return _chosen(Vector3(x, y, model.get_center().z - 0.6), Vector3.BACK)
	var inside := model.end.x + KEY_EXTRA * 0.5
	_check(along.call(inside) != key,
			"una línea que pasa a %.1f mm del modelo, adentro de la hitbox, no elige la llave: la hitbox no cuenta" % ((inside - model.end.x) * 1000.0))
	_check(along.call(model.get_center().x) == key, "una línea por el modelo, sí")
	var grenade_box := _model_box(grenade)
	var beside := Vector3(grenade_box.end.x + 0.003, grenade_box.get_center().y, grenade_box.get_center().z - 0.6)
	_check(_chosen(beside, Vector3.BACK) != grenade, "la granada, pasando a 3 mm de su caja, no: no hay margen")
	_check(_chosen(Vector3(grenade_box.get_center().x, grenade_box.get_center().y, grenade_box.get_center().z - 0.6), Vector3.BACK) == grenade,
			"por su modelo, sí")


## Dos objetos cerca: gana el primero que toca el rayo.
func _first_along_aim() -> void:
	var key := _uid_at(KEY_SPOT)
	var grenade := _uid_at(GRENADE_SPOT)
	if key == 0 or grenade == 0:
		return
	var key_box := _model_box(key)
	var grenade_box := _model_box(grenade)
	var y := key_box.get_center().y
	var z := key_box.get_center().z
	_check(_chosen(Vector3(key_box.position.x - 0.6, y, z), Vector3.RIGHT) == key, "desde el lado de la llave, la toca primero a ella")
	_check(_chosen(Vector3(grenade_box.end.x + 0.6, y, z), Vector3.LEFT) == grenade, "desde el lado de la granada, la toca primero a ella")
	# De arriba de la granada, bajando hasta la llave: pasa a 1,5 cm de la granada
	# antes de llegar a la llave. Sin margen, la granada no se toca.
	var over := Vector3(grenade_box.get_center().x, grenade_box.end.y + 0.015, z)
	var into := Vector3(key_box.get_center().x, y, z)
	var direction := (into - over).normalized()
	_check(_chosen(over - direction * 0.5, direction) == key, "bajando a 1,5 cm por arriba de la granada hacia la llave, gana la llave")


## El marco con un hueco: por el hueco, el rayo llega al piso y no se elige,
## aunque la hitbox lo tape (hasta el 2026-11-11, sí); por una barra, sí.
func _hole() -> void:
	var frame := _uid_at(FRAME_SPOT)
	var plain := _uid_at(PLAIN_FRAME_SPOT)
	if frame == 0 or plain == 0:
		return
	await _stand_by(FRAME_SPOT, NEAR_FIRST)
	await _set_first_person(true)
	await _aim(FRAME_SPOT)
	var aim := camera.aim_ray()
	var floor_at := _floor_point(aim[0], aim[1])
	_check(floor_at.distance_to(FRAME_SPOT) < 0.02 and not _touches_model(frame, aim[0], floor_at),
			"primera persona, la mira apunta al piso por el hueco del marco, sin tocar el modelo")
	_check(_hidden() and ui.interaction_target().is_empty(), "y no se elige, aunque la hitbox tape el hueco: %s" % _describe())
	var near_bar := _bar(frame, -1.0)
	await _aim(near_bar)
	_check(_marks(frame), "apuntando a la barra cercana, se elige: %s" % _describe())
	_frames_model(frame_def, "el marco por una barra")
	_check(ui.interaction_target().get("node") == net.world_view(frame), "E y el indicador usan el mismo selector")
	await _stand_by(PLAIN_FRAME_SPOT, NEAR_FIRST)
	await _aim(PLAIN_FRAME_SPOT)
	_check(_hidden() and ui.interaction_target().is_empty(), "el marco sin hitbox, por el hueco, tampoco: %s" % _describe())
	await _aim(_bar(plain, -1.0))
	_check(_marks(plain), "y por una barra, sí: %s" % _describe())
	await _stand_by(FRAME_SPOT, NEAR_FIRST)
	# Una pared entera en el medio.
	var wall: StaticBody3D = await _wall(FRAME_SPOT + Vector3(-0.5, 1.2, 0), Vector3(0.1, 2.4, 1.4))
	await _aim(near_bar)
	_check(_hidden() and ui.interaction_target().is_empty(), "con una pared en el medio, no se elige: %s" % _describe())
	_press_e()
	await _ticks(4)
	_check(net.replica.world.has(frame) and not net.replica.is_taken(frame), "y E no lo recoge")
	var r := await _req(Op.PICKUP, [frame], [frame])
	_check(not r[0] and String(r[1]).contains("no lo ves"), "pedido igual, el host no deja: %s" % r[1])
	wall.queue_free()
	await _ticks(3)
	# Una pared que cruza el marco entre su barra cercana y el resto: la barra
	# cercana queda de este lado y se agarra; la lejana, no.
	var crossing := FRAME_SPOT + Vector3(-0.05, 1.2, 0)
	wall = await _wall(crossing, Vector3(0.04, 2.4, 1.4))
	var model := _model_box(frame)
	_check(model.position.x + 0.04 < crossing.x - 0.02, "la barra cercana del marco queda de este lado de la pared")
	await _aim(near_bar)
	_check(_marks(frame), "apuntando a la barra cercana, se elige: %s" % _describe())
	await _aim(_bar(frame, 1.0))
	_check(not _marks(frame), "apuntando a la lejana, detrás de la pared, no: %s" % _describe())
	wall.queue_free()
	await _ticks(3)
	await _frames(2)
	# Sin paredes: E lo recoge por una barra, y soltado se elige igual.
	await _aim(near_bar)
	_check(_marks(frame), "sin paredes, vuelve a marcarse")
	_press_e()
	await _ticks(6)
	_check(net.replica.own.has(frame) or not net.replica.world.has(frame), "E lo recoge por una barra")
	var dropped := await _drop_own(&"marco_de_prueba")
	_check(dropped != 0 and net.world_view(dropped) != null, "soltado desde el inventario, vuelve al piso")
	if dropped == 0:
		return
	var spot: Vector3 = net.replica.world[dropped]["pos"]
	await _stand_by(spot, NEAR_FIRST)
	await _aim(spot)
	_check(not _marks(dropped), "el soltado, por el hueco, no se marca: %s" % _describe())
	await _aim(_bar(dropped, -1.0))
	_check(_marks(dropped), "por una barra, sí: %s" % _describe())


## Un punto arriba de la barra de un marco que va a lo largo (z), la de este
## lado (`side` −1, x más chica) o la de allá (+1), a mitad de su largo.
func _bar(uid: int, side: float) -> Vector3:
	var model := _model_box(uid)
	var x := model.get_center().x + side * (FRAME_WIDTH - FRAME_BAR) / 2.0
	return Vector3(x, model.end.y - 0.002, model.get_center().z)


## La llave con la cámara, en primera persona: apuntando al costado, adentro
## de su hitbox, no se marca; apuntando al modelo, sí, con el marco del
## modelo; E la recoge, y la soltada también se marca por su modelo.
func _key_with_camera() -> void:
	var key := _uid_at(KEY_SPOT)
	if key == 0:
		return
	await _teleport(KEY_SPOT + Vector3(0.0, 0.0, -1.1), PI)
	await _set_first_person(true)
	var model := _model_box(key)
	var point := _beside(key, Vector3.FORWARD)
	await _aim(point)
	var aim := camera.aim_ray()
	_check(not _touches_model(key, aim[0], _floor_point(aim[0], aim[1])), "la mira pasa al lado de la llave, sin tocar el modelo")
	_check(not _marks(key), "y no la marca, aunque pase por su hitbox: %s" % _describe())
	var top := Vector3(model.get_center().x, model.end.y - 0.001, model.get_center().z)
	await _aim(top)
	_check(_marks(key), "apuntando al modelo, la marca: %s" % _describe())
	_frames_model(key_def, "la llave")
	_press_e()
	await _ticks(6)
	_check(net.replica.own.has(key) or not net.replica.world.has(key), "E la recoge")
	var dropped := await _drop_own(&"llave")
	_check(dropped != 0, "la llave soltada está en el piso")
	if dropped == 0:
		return
	var spot: Vector3 = net.replica.world[dropped]["pos"]
	await _stand_by(spot, NEAR_FIRST)
	await _aim(_beside(dropped, Vector3.LEFT))
	_check(not _marks(dropped), "la soltada, al costado, no: %s" % _describe())
	var dropped_box := _model_box(dropped)
	await _aim(Vector3(dropped_box.get_center().x, dropped_box.end.y - 0.001, dropped_box.get_center().z))
	_check(_marks(dropped), "por su modelo, sí: %s" % _describe())


## En tercera persona: la otra llave por su modelo (al costado, no) y el marco
## soltado por una barra (por el hueco, no).
func _third_person() -> void:
	var key := _uid_at(KEY2_SPOT)
	if key == 0:
		return
	await _stand_by(KEY2_SPOT, NEAR_THIRD)
	await _set_first_person(false)
	_check(camera.third_person(), "la cámara está en tercera persona")
	await _aim(_beside(key, Vector3.FORWARD))
	_check(not _marks(key), "tercera persona: al costado de la llave, adentro de su hitbox, no la marca: %s" % _describe())
	var model := _model_box(key)
	await _aim(Vector3(model.get_center().x, model.end.y - 0.001, model.get_center().z))
	_check(_marks(key), "tercera persona: apuntando al modelo, sí: %s" % _describe())
	_frames_model(key_def, "tercera persona, la llave")
	var frame := _world_uid(&"marco_de_prueba")
	if frame == 0:
		_check(false, "está el marco soltado")
		return
	var spot: Vector3 = net.replica.world[frame]["pos"]
	await _stand_by(spot, Vector3(-0.65, 0, -1.45))
	await _aim(spot)
	_check(not _marks(frame), "tercera persona: el marco, por el hueco, no: %s" % _describe())
	await _aim(_bar(frame, -1.0))
	_check(_marks(frame), "tercera persona: por una barra, sí: %s" % _describe())
	_press_e()
	await _ticks(6)
	_check(net.replica.own.has(frame) or not net.replica.world.has(frame), "y E lo recoge")


## AG-02 (auditoría del 2026-11-08), con el rayo de la mano: nueve láminas de
## objetos lejanos con la hitbox adelantada 2 m cruzan la línea hasta un
## bloque. Hasta ese día tapaban la lista de la mira; desde el 2026-11-11 a la
## noche las hitbox no están en el mundo y no tapan nada. En los dos carriles:
## un bloque sin hitbox y uno con hitbox (que tampoco cuenta). Con una pared
## delante del bloque, no se elige.
func _many_discarded() -> void:
	await _discarded_lane(TARGET_SPOT, "sin hitbox")
	await _discarded_lane(BOXED_SPOT, "con hitbox")


func _discarded_lane(spot: Vector3, what: String) -> void:
	var target := _uid_at(spot)
	var plates: Array = net.replica.world.keys().filter(func(id: int) -> bool:
			return net.replica.world[id]["stack"].def_id == &"lamina_lejana" and absf(net.replica.world[id]["pos"].z - spot.z) < 0.01)
	_check(target != 0 and plates.size() == PLATES, "AG-02 (%s): el bloque y las %d láminas están en el piso (%d)" % [what, PLATES, plates.size()])
	if target == 0 or plates.size() != PLATES:
		return
	await _stand_by(spot, NEAR_FIRST)
	await _set_first_person(true)
	var eyes := InvAuthority.eyes(actor, actor.global_position)
	var center := _model_box(target).get_center()
	var direction := (center - eyes).normalized()
	var crossed := plates.filter(func(id: int) -> bool:
		var box := plate_def.pickup_hitbox.bounds()
		box.position += net.replica.world[id]["pos"]
		return box.intersects_segment(eyes, center) != null)
	_check(crossed.size() == PLATES, "AG-02 (%s): antes del bloque, la línea cruza las %d hitbox de las láminas (%d)" % [what, PLATES, crossed.size()])
	_check(_chosen(eyes, direction) == target, "AG-02 (%s): igual se elige el bloque: las hitbox no tapan" % what)
	await _aim(center)
	_check(_marks(target), "AG-02 (%s): con la cámara, el indicador lo marca y E elegiría el mismo: %s" % [what, _describe()])
	var wall := await _wall(Vector3(_model_box(target).position.x - 0.05, 1.2, spot.z), Vector3(0.04, 2.4, 1.2))
	_check(_chosen(eyes, direction) == 0 and _hidden(), "AG-02 (%s): con una pared delante del bloque, no se elige nada: %s" % [what, _describe()])
	wall.queue_free()
	await _ticks(3)
	await _frames(2)
	_check(_chosen(eyes, direction) == target, "AG-02 (%s): sin la pared, otra vez el bloque" % what)


# --- En pareja (dos procesos) -------------------------------------------------------

func _pair_host() -> void:
	_check(await _until(func() -> bool: return net.authority != null and lab._local_actor != null and net.replica.own != null, 15.0),
			"el host arranca con su personaje")
	actor = lab._local_actor
	if actor == null or indicator == null:
		_finish()
		return
	var found := {}
	_check(await _until(func() -> bool:
		for peer in net.authority.welcomed_peers():
			if peer != multiplayer.get_unique_id():
				found["peer"] = peer
		return found.has("peer"), 30.0), "entró el cliente: la huella, con las hitbox, coincide")
	var frame := _uid_at(FRAME_SPOT)
	var key := _uid_at(KEY2_SPOT)
	_check(frame != 0 and key != 0 and InvPickupHitbox.active(key_def) != null, "en el host están el marco y la llave, con su hitbox")
	# El host, en tercera persona: al costado de la llave (en su hitbox) no la
	# marca; por su modelo, sí, y la recoge con E.
	await _stand_by(KEY2_SPOT, NEAR_THIRD)
	await _set_first_person(false)
	await _aim(_beside(key, Vector3.FORWARD))
	_check(not _marks(key), "el host, en tercera persona, al costado de la llave no la marca: %s" % _describe())
	var model := _model_box(key)
	await _aim(Vector3(model.get_center().x, model.end.y - 0.001, model.get_center().z))
	_check(_marks(key), "por su modelo, sí: %s" % _describe())
	_press_e()
	_check(await _until(func() -> bool: return not net.replica.world.has(key), 3.0) and net.replica.own.has(key), "y la recoge con E")
	_check(await _until(func() -> bool: return not net.replica.world.has(frame), 50.0), "el cliente recogió el marco")
	var other := net.authority.player_inventory(found.get("peer", -1))
	_check(other != null and other.grid.has(frame), "el host lo validó: está en el inventario del cliente")
	_check(await _until(func() -> bool: return multiplayer.get_peers().is_empty(), 30.0), "el cliente terminó y se fue")
	_finish(true)


func _pair_client() -> void:
	_check(await _until(func() -> bool: return net.replica.has_state and lab._local_actor != null and net.replica.own != null, 20.0),
			"el cliente recibe el estado del host")
	actor = lab._local_actor
	if actor == null or indicator == null:
		_finish()
		return
	var frame := _uid_at(FRAME_SPOT)
	_check(frame != 0 and net.world_view(frame) != null and InvPickupHitbox.active(frame_def) != null,
			"el cliente ve el marco, con su hitbox en su propia definición")
	if frame == 0:
		_finish()
		return
	_check(await _walk_to(FRAME_SPOT + NEAR_FIRST), "el cliente camina hasta el marco")
	await _set_first_person(true)
	await _aim(FRAME_SPOT)
	var aim := camera.aim_ray()
	_check(not _touches_model(frame, aim[0], _floor_point(aim[0], aim[1])), "el cliente apunta por el hueco, sin tocar el modelo")
	_check(not _marks(frame), "y no lo marca: %s" % _describe())
	await _aim(_bar(frame, -1.0))
	_check(_marks(frame), "apuntando a una barra, sí, desde su cámara: %s" % _describe())
	_press_e()
	_check(await _until(func() -> bool:
		for uid in net.replica.own.sorted_uids():
			if net.replica.own.stacks[uid].def_id == &"marco_de_prueba":
				return not net.replica.world.has(frame) and net.replica.pending.is_empty()
		return false, 10.0), "con E lo recoge, y el host lo confirma")
	_finish(true)


## El host, con un cliente cuya hitbox de la llave difiere en 1 mm: no lo deja entrar.
func _host_refuses() -> void:
	_check(await _until(func() -> bool: return net.authority != null and lab._local_actor != null, 15.0), "el host arranca")
	var entered := await _until(func() -> bool:
		return net.authority.welcomed_peers().any(func(peer: int) -> bool: return peer != multiplayer.get_unique_id()), 20.0)
	_check(not entered, "en 20 s no entró nadie: el cliente con otra hitbox queda afuera")
	_finish(true)


func _client_refused() -> void:
	var said := {"text": ""}
	lab._session.status_changed.connect(func(text: String) -> void:
		if text.contains("no te deja entrar"):
			said["text"] = text)
	_check(await _until(func() -> bool: return said["text"] != "", 15.0), "el host no deja entrar al cliente")
	_check(String(said["text"]).contains("inventario") and not net.replica.has_state,
			"porque su copia difiere en el inventario (la hitbox de la llave): %s" % String(said["text"]).get_slice("\n", 0))
	_finish(true)


## Camina hasta ahí con W, girando la cámara hacia el lugar, como un jugador.
func _walk_to(target: Vector3, tolerance := 0.3) -> bool:
	var limit := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < limit:
		var me := lab._local_actor as ActorBody
		if me != null:
			var flat := Vector3(target.x - me.global_position.x, 0.0, target.z - me.global_position.z)
			if flat.length() < tolerance:
				Input.action_release("move_forward")
				Input.action_release("run")
				await _ticks(20)
				return true
			camera.yaw = atan2(-flat.x, -flat.z)
			Input.action_press("move_forward")
			if flat.length() > 3.0:
				Input.action_press("run")
			else:
				Input.action_release("run")
		await get_tree().physics_frame
	Input.action_release("move_forward")
	Input.action_release("run")
	return false
