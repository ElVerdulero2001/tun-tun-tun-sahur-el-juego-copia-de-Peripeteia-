extends Node

## Prueba del rayo de la mano para recoger y abrir (desde el 2026-11-11 a la
## noche, pedido del usuario: docs/net/problema_objeto_sobre_un_borde.md). La
## regla está en InvReach: un rayo desde los ojos del personaje, hacia donde
## apunta la mira, tiene que tocar el modelo del objeto (o la caja) antes que
## otra cosa, a no más de Interaction Range del Tuning, medido de los ojos al
## punto tocado. Con la caja abierta, la distancia de los ojos a su volumen. La
## usan igual el selector (lo que marca el indicador y elige E) y el host.
##
## No cambia ningún archivo: antes de que arranque el laboratorio, en memoria,
## suma a la zona de inventario dos cajas (una larga, de 3 m, y otra girada 37°
## y escalada), un estante alto (un cuerpo de la prueba, no del nivel) y
## objetos de prueba en dos lugares despejados del piso. Las distancias
## esperadas salen de una cuenta aparte, triángulo por triángulo del modelo
## dibujado (_ref_hit), no de InvReach.
##
## Sin argumentos, un proceso jugando solo:
##
## - los ojos: 1,65 m parado y 0,85 m agachado, sobre los pies;
## - un objeto chico, uno largo (su punta cercana sí, la lejana no) y una caja
##   (de costado, de punta, desde una esquina, girada y escalada), 1 cm adentro
##   y 1 cm afuera del alcance, medido hasta el punto tocado: el selector y el
##   host dicen lo mismo; abierta, la caja no se cierra sola;
## - parado y agachado, en el piso y en un estante alto, y desde una plataforma;
## - el caso del usuario: un cubito sobre un estante más alto que los ojos, del
##   que asoma 1 cm, se agarra apuntando a esa franja; apuntando 1 cm más abajo,
##   no; uno metido que no asoma, no; una varilla fina que sobresale 3 cm del
##   filo, por abajo; con la cámara de verdad, en primera y tercera persona;
## - lo que tapa: el nivel, una pared fina pegada al objeto, otro objeto suelto
##   y una caja (se elige lo primero, y el host rechaza lo de atrás);
## - la hitbox de agarre no ayuda: asomando de una pared con el modelo atrás, o
##   pasando 1 cm al lado del modelo, no; un marco con hitbox, por su hueco, no;
## - en tercera persona, una cámara que ve por encima de un murito que tapa los
##   ojos no deja agarrar;
## - el indicador, E y el host coinciden;
## - pedidos inválidos (sin dirección, NAN, INF, cero, largo 2, enteros) y con
##   la dirección hacia otra cosa;
## - la caja abierta, sin mirarla: se opera mientras los ojos están al alcance
##   de su volumen y se cierra al pasarlo (también la girada, junto a la
##   esquina vacía de la caja alineada al mundo que la encierra);
## - Interaction Range en vivo, la huella (los triángulos de cada tipo, sin
##   Pickup Aim Margin), y cuánto cuesta el selector.
##
##   --headless --fixed-fps 60 --path . --scene res://scenes/net_lab/inventario/pruebas/inv_alcance_test.tscn
##
## Con --alcance-pair=host o client, en dos procesos, con los argumentos de red
## del laboratorio (--host --bind=127.0.0.1 --port=N o --client
## --address=127.0.0.1 --port=N, y la internet simulada que se quiera), sin
## --fixed-fps: el cliente camina y apunta con su cámara; recoge una granada y
## la varilla que sobresale del estante con E (el host acepta); pide el cubito
## metido que no asoma, la tabla fuera de alcance y una dirección de largo 2
## (el host rechaza cada uno, como dijo su selector); abre la caja larga con E,
## deja de mirarla, mete la granada y camina hasta que el host se la cierra.
## Con --alcance-pair=host_rechaza y client_tuning (otro Interaction Range) o
## client_modelo (una granada 1 cm más grande), el host no lo deja entrar.
##
## Con --alcance-detalle escribe también cada comprobación que dio bien.

const Op := InvProtocol.Op
const Mano := preload("res://scenes/net_lab/inventario/pruebas/inv_mano_de_prueba.gd")
## Dónde está la zona de inventario (las cajas de prueba van adentro de ella).
const ZONE_ORIGIN := Vector3(37, 0, 13)
## El alcance con que se prueba (va en el Tuning de esta copia antes de la huella).
const REACH := 2.0
## Adentro y afuera del alcance, por esto.
const EDGE := 0.01
## Los ojos sobre los pies: el alto de la forma menos InvAuthority.EYES_BELOW_TOP.
const EYES_STANDING := 1.65
const EYES_CROUCHED := 0.85
## Lugares despejados del piso: x de 16 a 24 y z de 20 a 32 para las cajas; x de
## 24 a 32 y z de 4 a 16 para los objetos.
const BOXES_AREA := AABB(Vector3(16, 0.05, 20), Vector3(8, 2.5, 12))
const ITEMS_AREA := AABB(Vector3(24, 0.05, 4), Vector3(8, 2.5, 12))

const LONG_AT := Vector3(20, 0, 23.5)
const LONG_SIZE := Vector3(3.0, 0.8, 0.8)
const TURNED_AT := Vector3(20, 0, 29.0)
const TURNED_SIZE := Vector3(1.2, 0.8, 0.8)
const TURNED_DEGREES := 37.0
const TURNED_SCALE := Vector3(1.5, 1.0, 0.7)
## Una granada detrás de la caja larga, del otro lado.
const BEHIND_BOX_AT := Vector3(20.6, 0, 24.25)

const GRENADE_AT := Vector3(28, 0, 6)
const LOW_AT := Vector3(28, 0, 12.5)
const TABLE_AT := Vector3(26, 0, 10.5)
const TABLE_SIZE := Vector3(0.2, 0.04, 2.0)
const BIG_KEY_AT := Vector3(28, 0, 15)
const BIG_KEY_EXTRA := 0.6
## Un marco de 60 × 60 cm, con barras de 5 cm, acostado: un hueco de verdad.
## Su hitbox lo tapa entero.
const FRAME_AT := Vector3(25.5, 0, 6.0)
const FRAME_SIZE := 0.6
const FRAME_BAR := 0.05
const FRAME_HEIGHT := 0.03
## Un bloque de 30 cm de alto y, detrás, una granada.
const BLOCK_AT := Vector3(26.0, 0, 14.5)
const BLOCK_SIZE := Vector3(0.2, 0.3, 0.2)
const BEHIND_AT := Vector3(26.25, 0, 14.5)
## La granada de la tercera persona y la de la pared fina.
const THIRD_AT := Vector3(28, 0, 8.5)
const THIN_AT := Vector3(25.5, 0, 12.5)
const PLATFORM_AT := Vector3(30.5, 0, 13.0)
## Una plataforma de 30 cm: desde una de 1 m los ojos quedan a 2,65 m del piso
## y con 2 m de alcance no llegan a nada en el piso.
const PLATFORM_SIZE := Vector3(1.6, 0.3, 1.6)
const BELOW_AT := Vector3(29.5, 0, 13.0)
## El estante alto: su cara de arriba a 1,7 m (más alta que los ojos parado),
## el filo en x = 30,4; va de x 30,4 a 32 y de z 4,5 a 8,5, con 10 cm de espesor.
const SHELF_EDGE_X := 30.4
const SHELF_TOP := 1.7
const SHELF_BOX := AABB(Vector3(30.4, 1.6, 4.5), Vector3(1.6, 0.1, 4.0))
## Parado con los pies en x = 29,9 (50 cm antes del filo; en x = 30 hay una
## unión del piso con 2 mm de escalón), la línea desde los ojos que roza el
## filo sube 10 cm por metro: a 90 cm del filo pasa a 1,79 m. Un cubito de 10
## cm ahí asoma 1 cm.
const STAND_X := 29.9
const CUBE := 0.1
const STRIP := 0.01
const STRIP_AT := Vector3(SHELF_EDGE_X + (CUBE - STRIP) / ((SHELF_TOP - EYES_STANDING) / (SHELF_EDGE_X - STAND_X)) + CUBE / 2.0,
		SHELF_TOP, 5.2)
## Un cubito metido 1,25 m: no asoma desde ningún lugar delante del estante a
## menos de 62 cm del filo.
const HIDDEN_AT := Vector3(31.7, SHELF_TOP, 6.6)
## Una varilla de 1 m × 1,5 cm, perpendicular al filo, que sobresale 3 cm.
const ROD_SIZE := Vector3(1.0, 0.015, 0.015)
const ROD_AT := Vector3(SHELF_EDGE_X - 0.03 + 0.5, SHELF_TOP, 7.8)
## En pareja, cuánto adentro o afuera del alcance se para el cliente (camina, no
## se teletransporta).
const PAIR_MARGIN := 0.35

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
var long_box: InvContainer
var turned_box: InvContainer
var shelf: StaticBody3D
var grenade_def: InvItemDef
var table_def: InvItemDef
var big_key_def: InvItemDef
var frame_def: InvItemDef
var block_def: InvItemDef
var cube_def: InvItemDef
var rod_def: InvItemDef
var _answers := {}
var _checks := 0
var _failures := 0
var _finishing := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--alcance-pair="):
			role = arg.trim_prefix("--alcance-pair=")
		elif arg == "--alcance-detalle":
			verbose = true
	get_tree().create_timer(180.0, true, false, true).timeout.connect(func() -> void:
		_failures += 1
		_log("TIEMPO AGOTADO: el recorrido no terminó")
		_finish())
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	lab.set(&"test_tuning", {"interaction_range": REACH + (0.1 if role == "client_tuning" else 0.0)})
	_prepare()
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
		"client_tuning", "client_modelo":
			_client_refused()
		_:
			_log("--alcance-pair tiene que ser host, client, host_rechaza, client_tuning o client_modelo")
			get_tree().quit(3)


## Lo de la prueba, en memoria y antes de que arranque el inventario: así lo
## arman igual el host y el cliente, y la huella coincide. El estante es un
## cuerpo de esta prueba, fuera del nivel: lo tienen los dos procesos.
func _prepare() -> void:
	var zone := lab.get_node("ZonaDeInventario")
	long_box = _add_box(zone, "CajaLargaDePrueba", "Caja larga de prueba", LONG_AT, LONG_SIZE, 0.0, Vector3.ONE)
	turned_box = _add_box(zone, "CajaGiradaDePrueba", "Caja girada de prueba", TURNED_AT, TURNED_SIZE, TURNED_DEGREES,
			TURNED_SCALE)
	catalog = (lab.get_node("Inventario") as InvNet).catalog
	grenade_def = catalog.find(&"granada")
	if role == "client_modelo":
		grenade_def.world_size += 0.01
	table_def = _box_item(&"tabla_de_prueba", "Tabla de prueba", TABLE_SIZE, Vector2i(1, 4))
	big_key_def = _box_item(&"llave_de_hitbox_grande", "Llave de hitbox grande", Vector3(0.1, 0.03, 0.1), Vector2i.ONE)
	var hitbox := InvPickupHitbox.new()
	hitbox.kind = InvPickupHitbox.Kind.BOX
	hitbox.fit(InvPickupHitbox.model_bounds(big_key_def))
	hitbox.grow(BIG_KEY_EXTRA)
	big_key_def.pickup_hitbox = hitbox
	frame_def = _frame_def()
	block_def = _box_item(&"bloque_de_prueba", "Bloque de prueba", BLOCK_SIZE, Vector2i(2, 2))
	cube_def = _box_item(&"cubito_de_prueba", "Cubito de prueba", Vector3.ONE * CUBE, Vector2i.ONE)
	rod_def = _box_item(&"varilla_de_prueba", "Varilla de prueba", ROD_SIZE, Vector2i(1, 4))
	for def in [table_def, big_key_def, frame_def, block_def, cube_def, rod_def]:
		catalog.items.append(def)
	var level := lab.get_node("Level")
	_add_spawn(level, "GranadaDeAlcance", grenade_def, GRENADE_AT)
	_add_spawn(level, "GranadaEnElPiso", grenade_def, LOW_AT)
	_add_spawn(level, "TablaDePrueba", table_def, TABLE_AT)
	_add_spawn(level, "LlaveDeHitboxGrande", big_key_def, BIG_KEY_AT)
	_add_spawn(level, "MarcoHueco", frame_def, FRAME_AT)
	_add_spawn(level, "BloqueDelante", block_def, BLOCK_AT)
	_add_spawn(level, "GranadaDetras", grenade_def, BEHIND_AT)
	_add_spawn(level, "GranadaDeTercera", grenade_def, THIRD_AT)
	_add_spawn(level, "GranadaDeParedFina", grenade_def, THIN_AT)
	_add_spawn(level, "GranadaAbajo", grenade_def, BELOW_AT)
	_add_spawn(level, "GranadaDetrasDeLaCaja", grenade_def, BEHIND_BOX_AT)
	_add_spawn(level, "CubitoQueAsoma", cube_def, STRIP_AT)
	_add_spawn(level, "CubitoMetido", cube_def, HIDDEN_AT)
	_add_spawn(level, "VarillaQueSobresale", rod_def, ROD_AT)
	shelf = _body(SHELF_BOX.get_center(), SHELF_BOX.size)
	add_child(shelf)


## Un tipo con forma de caja de esas medidas (una BoxMesh): su modelo en el
## mundo mide eso justo, con el lado más largo como world_size.
func _box_item(id: StringName, shown: String, size: Vector3, cells: Vector2i) -> InvItemDef:
	var def := InvItemDef.new()
	def.id = id
	def.display_name = shown
	def.size = cells
	var mesh := BoxMesh.new()
	mesh.size = size
	def.mesh = mesh
	def.world_size = maxf(size.x, maxf(size.y, size.z))
	return def


## Un marco cuadrado acostado, de cuatro barras, con el hueco en el medio; su
## hitbox de agarre es su caja entera, 1 cm más grande: tapa el hueco.
func _frame_def() -> InvItemDef:
	var root := Node3D.new()
	root.name = "Marco"
	var long_bar := Vector3(FRAME_BAR, FRAME_HEIGHT, FRAME_SIZE)
	var short_bar := Vector3(FRAME_SIZE - 2.0 * FRAME_BAR, FRAME_HEIGHT, FRAME_BAR)
	var half := (FRAME_SIZE - FRAME_BAR) / 2.0
	for part: Array in [[long_bar, Vector3(-half, 0, 0)], [long_bar, Vector3(half, 0, 0)], [short_bar, Vector3(0, 0, -half)],
			[short_bar, Vector3(0, 0, half)]]:
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = part[0]
		bar.mesh = mesh
		bar.position = part[1]
		root.add_child(bar)
		bar.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	var def := InvItemDef.new()
	def.id = &"marco_hueco"
	def.display_name = "Marco hueco"
	def.size = Vector2i(2, 2)
	def.model = packed
	def.world_size = FRAME_SIZE
	var hitbox := InvPickupHitbox.new()
	hitbox.kind = InvPickupHitbox.Kind.BOX
	hitbox.fit(InvPickupHitbox.model_bounds(def))
	hitbox.grow(0.01)
	def.pickup_hitbox = hitbox
	return def


func _add_box(zone: Node, node_name: String, shown: String, at: Vector3, size: Vector3, degrees: float,
		scale: Vector3) -> InvContainer:
	var box: InvContainer = load("res://scenes/inventory/caja.tscn").instantiate()
	box.name = node_name
	box.display_name = shown
	box.box_size = size
	box.columns = 6
	box.rows = 4
	box.position = at - ZONE_ORIGIN
	box.rotation = Vector3(0.0, deg_to_rad(degrees), 0.0)
	box.scale = scale
	zone.add_child(box)
	return box


func _add_spawn(parent: Node, node_name: String, def: InvItemDef, spot: Vector3) -> void:
	var spawn := InvPickupSpawn.new()
	spawn.name = node_name
	spawn.item = def
	spawn.show_label = false
	# El nivel está en el origen: su posición es la del mundo.
	spawn.position = spot
	parent.add_child(spawn)


func _body(center: Vector3, size: Vector3, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var holder := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = size
	holder.shape = slab
	body.add_child(holder)
	body.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	return body


# --- Ayudas ---------------------------------------------------------------------

func _log(text: String) -> void:
	print("[inv_alcance%s] %s" % [":" + role if role != "" else "", text])


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
	Input.action_release("move_forward")
	Input.action_release("run")
	Input.action_release("crouch")
	_log("%d comprobaciones, %d fallas" % [_checks, _failures])
	if role.begins_with("client"):
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


## Un pedido con lo que se le pasa tal cual (si recoger o abrir trae solo el
## número, la mano apunta a lo pedido como un jugador: Mano.aimed).
func _req(op: int, args: Array, uids: Array = []) -> Array:
	args = Mano.aimed(net, lab._local_actor, op, args)
	var seq := net.replica.request(op, args, uids)
	if seq == 0:
		return [false, "no salió"]
	if not await _until(func() -> bool: return _answers.has(seq), 5.0):
		return [false, "sin respuesta"]
	return _answers[seq]


## Recoger con la mano en `direction`: [aceptado, motivo].
func _pick(uid: int, direction: Vector3) -> Array:
	return await _req(Op.PICKUP, InvProtocol.aimed_args(uid, direction), [uid])


## El host abre la caja con la mano en `direction` (y se la cierra enseguida):
## [abrió, motivo]. Si abrió, antes mira que siga abierta unos ticks: el rayo
## que la abrió deja los ojos al alcance de su volumen.
func _host_opens(box: InvContainer, direction: Vector3) -> Array:
	var r := await _req(Op.OPEN, InvProtocol.aimed_args(box.container_id, direction))
	if r[0]:
		await _ticks(5)
		r.append(net.replica.box_id == box.container_id)
		var seq := net.replica.leave_box()
		await _until(func() -> bool: return seq == 0 or _answers.has(seq), 5.0)
	return r


## Mueve al personaje propio de golpe (jugando solo), mirando hacia `toward`.
func _teleport(feet: Vector3, toward: Vector3) -> void:
	var state := actor.state
	state.position = feet
	state.velocity = Vector3.ZERO
	var flat := Vector3(toward.x - feet.x, 0.0, toward.z - feet.z)
	state.facing_yaw = atan2(-flat.x, -flat.z) if flat.length() > 0.001 else state.facing_yaw
	state.mode = ActorState.Mode.GROUND
	state.on_floor = true
	state.base_id = 0
	state.quantize()
	actor.apply_state(state)
	actor.teleported()
	await _ticks(3)
	await _frames(2)


## Se agacha o se para con la tecla, como un jugador, y espera a que cambie la postura.
func _crouch(on: bool) -> void:
	if on:
		Input.action_press("crouch")
	else:
		Input.action_release("crouch")
	var wanted := ActorState.Stance.CROUCHED if on else ActorState.Stance.STANDING
	await _until(func() -> bool: return actor.state.stance == wanted, 3.0)
	await _ticks(3)


func _eyes() -> Vector3:
	return InvAuthority.eyes(actor, actor.global_position)


func _space() -> PhysicsDirectSpaceState3D:
	return lab.get_world_3d().direct_space_state


func _uid_at(spot: Vector3) -> int:
	for uid in net.replica.world:
		if (net.replica.world[uid]["pos"] as Vector3).distance_to(spot) < 0.05 and not net.replica.is_taken(uid):
			return uid
	return 0


## Los triángulos del modelo dibujado de ese objeto suelto, en el mundo (del
## nodo que lo dibuja, no de InvReach).
func _drawn_faces(uid: int) -> PackedVector3Array:
	var view := net.world_view(uid)
	if view == null:
		return PackedVector3Array()
	var model := view.get_child(0) as Node3D
	return view.global_transform * model.transform * InvVisuals.faces(model)


## Lo primero que toca la línea desde `from` hacia `direction` (largo 1),
## hasta `length`, con otra cuenta que la de InvReach: el nivel con la física y
## los objetos sueltos dibujados triángulo por triángulo (con `only`, solo ese
## objeto). [número del objeto, 0 si es el nivel o -1 si nada, distancia].
func _ref_hit(from: Vector3, direction: Vector3, length: float, only := 0) -> Array:
	var best: Array = [-1, length]
	var hit := _space().intersect_ray(PhysicsRayQueryParameters3D.create(from, from + direction * length,
			InvAuthority.WORLD_MASK, [actor.get_rid()]))
	if not hit.is_empty():
		best = [0, from.distance_to(hit["position"])]
	for uid in net.replica.world:
		if net.replica.is_taken(uid) or (only != 0 and uid != only) or net.world_view(uid) == null:
			continue
		var view := net.world_view(uid)
		var drawn := view.interact_focus().bounds.grow(0.01)
		drawn.position += view.global_position
		if drawn.intersects_segment(from, from + direction * best[1]) == null:
			continue
		var faces := _drawn_faces(uid)
		for i in range(0, faces.size(), 3):
			var at: Variant = Geometry3D.segment_intersects_triangle(from, from + direction * best[1], faces[i], faces[i + 1],
					faces[i + 2])
			if at != null and from.distance_to(at) <= best[1]:
				best = [uid, from.distance_to(at)]
	return best


## El punto más alto del modelo de ese objeto, sobre su centro (una línea que
## baja sobre sus triángulos).
func _top_of(uid: int) -> Vector3:
	var view := net.world_view(uid)
	var box := view.interact_focus().bounds
	box.position += view.global_position
	var from := Vector3(box.get_center().x, box.end.y + 1.0, box.get_center().z)
	var faces := _drawn_faces(uid)
	var best := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	for i in range(0, faces.size(), 3):
		var at: Variant = Geometry3D.segment_intersects_triangle(from, from + Vector3.DOWN * 3.0, faces[i], faces[i + 1], faces[i + 2])
		if at != null and (at as Vector3).y > best.y:
			best = at
	return best


## Dónde pararse, sobre `anchor` (en el piso, o sobre una plataforma) y
## alejándose en la dirección `away`, para que el rayo desde los ojos (a
## `eye_height` sobre los pies) hacia `target` toque primero ese objeto a
## `distance`, según la cuenta aparte (_ref_hit).
func _feet_at(uid: int, target: Vector3, anchor: Vector3, away: Vector3, distance: float, eye_height: float) -> Vector3:
	var low := 0.0
	var high := 6.0
	for i in 40:
		var mid := (low + high) * 0.5
		var eyes := anchor + away * mid + Vector3.UP * eye_height
		var hit := _ref_hit(eyes, (target - eyes).normalized(), 10.0, uid)
		var reached: float = hit[1] if hit[0] == uid else eyes.distance_to(target)
		if reached < distance:
			low = mid
		else:
			high = mid
	return anchor + away * (low + high) * 0.5


## Lo que elige el selector con la mira desde `from` hacia `look`.
func _chosen(from: Vector3, look: Vector3, third := false) -> Dictionary:
	return net.interaction_target(actor, from, look, third)


func _picks(uid: int, from: Vector3, look: Vector3, third := false) -> bool:
	var seen := _chosen(from, look, third)
	return seen.get("kind", "") == "item" and seen.get("id", 0) == uid


func _picks_box(box: InvContainer, from: Vector3, look: Vector3) -> bool:
	var seen := _chosen(from, look)
	return seen.get("kind", "") == "box" and seen.get("id", 0) == box.container_id


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


## Si el indicador marca ese objeto y E elegiría ese mismo (con la cámara).
func _marks(uid: int) -> bool:
	var focus := indicator.marked_focus()
	var target := ui.interaction_target()
	return focus != null and focus.anchor == net.world_view(uid) and target.get("kind", "") == "item" \
			and target.get("id", 0) == uid


func _describe() -> String:
	var focus := indicator.marked_focus()
	return "marca «%s»; E elegiría %s" % [indicator.shown_name(), ui.interaction_target()] if focus != null \
			else "no marca nada; E elegiría %s" % [ui.interaction_target()]


func _press_e() -> void:
	var e_key := InputEventKey.new()
	e_key.physical_keycode = KEY_E
	e_key.pressed = true
	ui._unhandled_key_input(e_key)


## E sobre lo que marca el indicador: el host lo acepta y queda recogido (ya
## no está en el piso; si se apila con otro, deja de tener su número propio).
func _e_picks(uid: int, what: String) -> void:
	_check(_marks(uid), "%s: el indicador lo marca y E lo elegiría: %s" % [what, _describe()])
	var before := net.replica.pending.keys()
	_press_e()
	var sent := net.replica.pending.keys().filter(func(number: int) -> bool: return not number in before)
	var seq: int = sent[0] if not sent.is_empty() else 0
	var ok := seq != 0 and await _until(func() -> bool: return _answers.has(seq), 5.0)
	_check(ok and _answers[seq][0] and not net.replica.world.has(uid),
			"%s: E lo recoge y el host lo acepta: %s" % [what, _answers.get(seq, "no salió el pedido")])


func _wall(center: Vector3, size: Vector3, yaw := 0.0) -> StaticBody3D:
	var wall := _body(center, size, yaw)
	add_child(wall)
	await _ticks(3)
	await _frames(2)
	return wall


func _remove(wall: Node) -> void:
	wall.queue_free()
	await _ticks(3)
	await _frames(2)


func _clear(area: AABB) -> bool:
	var probe := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = area.size
	probe.shape = shape
	probe.collision_mask = InvAuthority.WORLD_MASK
	probe.transform = Transform3D(Basis.IDENTITY, area.get_center())
	probe.exclude = [long_box.get_rid(), turned_box.get_rid(), shelf.get_rid()]
	return _space().intersect_shape(probe, 1).is_empty()


## El punto de la caja más cercano a `point`, con otra cuenta que la de
## InvReach: el punto pasado al espacio de la caja, recortado a sus medidas y
## vuelto al mundo.
static func _ref_nearest(place: Transform3D, box: AABB, point: Vector3) -> Vector3:
	var local := place.affine_inverse() * point
	return place * local.clamp(box.position, box.end)


static func _volume(size: Vector3) -> AABB:
	return AABB(Vector3(-size.x / 2.0, 0.0, -size.z / 2.0), size)


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
	_check(is_equal_approx(net.interaction_range, REACH) and is_equal_approx(net.authority.interaction_range, REACH),
			"el alcance de la prueba está en el Tuning: %s m, igual para el selector y el host" % net.interaction_range)
	_check(_clear(BOXES_AREA) and _clear(ITEMS_AREA), "los dos lugares de la prueba están despejados")
	_check(long_box.container_id != 0 and turned_box.container_id != 0, "las dos cajas de prueba están numeradas")
	await _set_first_person(true)
	await _eyes_point()
	await _small_item()
	await _long_item()
	await _stance_and_height()
	await _over_the_edge()
	await _blockers()
	await _hitbox_does_not_help()
	await _hole()
	await _third_person_eyes()
	await _camera_views()
	await _invalid_requests()
	await _box_edges()
	await _open_without_aiming()
	await _turned_box_closes()
	await _tuning_live()
	await _cost()
	_finish(true)


func _eyes_point() -> void:
	await _teleport(Vector3(23, 0, 31), LONG_AT)
	var feet := actor.global_position
	_check(_eyes().is_equal_approx(feet + Vector3.UP * EYES_STANDING), "parado, los ojos están 1,65 m sobre los pies: %s" % (_eyes() - feet))
	await _crouch(true)
	feet = actor.global_position
	_check(actor.state.stance == ActorState.Stance.CROUCHED and _eyes().is_equal_approx(feet + Vector3.UP * EYES_CROUCHED),
			"agachado, bajan a 0,85 m: %s" % (_eyes() - feet))
	await _crouch(false)
	_check(actor.state.stance == ActorState.Stance.STANDING, "se vuelve a parar")


## Un objeto chico (la granada del catálogo, con su modelo): el rayo hacia su
## punto más alto lo toca 1 cm afuera del alcance (ni el selector ni el host) y
## 1 cm adentro (los dos).
func _small_item() -> void:
	var uid := _uid_at(GRENADE_AT)
	_check(uid != 0, "la granada de prueba está en el piso")
	if uid == 0:
		return
	var drawn := _drawn_faces(uid)
	var box := AABB(drawn[0], Vector3.ZERO)
	for point in drawn:
		box = box.expand(point)
	box.position -= GRENADE_AT
	var mesh := InvReach.item_mesh(grenade_def)
	var bounds := InvReach.item_bounds(grenade_def).grow(-0.001)
	_check(mesh != null and mesh.get_faces().size() == drawn.size() and bounds.position.distance_to(box.position) < 0.0005
			and bounds.size.distance_to(box.size) < 0.0005,
			"los triángulos del rayo son los del modelo como se dibuja, con su escala: %d y %d, %s y %s" % [
			mesh.get_faces().size() if mesh != null else 0, drawn.size(), bounds, box])
	await _edge_item(uid, Vector3(GRENADE_AT.x, 0.0, GRENADE_AT.z), Vector3.LEFT, "la granada, de frente")


## Lo de un objeto en el borde del alcance: el rayo desde los ojos hacia su
## punto más alto (o `target`), con los pies sobre `anchor` alejándose por
## `away`, lo toca 1 cm afuera (ni el selector ni el host) y 1 cm adentro (los
## dos, y queda recogido). La distancia que mide InvReach es la de la cuenta aparte.
func _edge_item(uid: int, anchor: Vector3, away: Vector3, what: String, target := Vector3.INF, eye_height := EYES_STANDING) -> void:
	var aim_at := _top_of(uid) if target == Vector3.INF else target
	for inside: bool in [false, true]:
		var distance := REACH - EDGE if inside else REACH + EDGE
		await _teleport(_feet_at(uid, aim_at, anchor, away, distance, eye_height), aim_at)
		var eyes := _eyes()
		var direction := (aim_at - eyes).normalized()
		var ref := _ref_hit(eyes, direction, 10.0)
		var hit := InvReach.first_hit(_space(), eyes, direction, 10.0, net.replica.world, catalog, InvReach.own_shapes(actor))
		_check(ref[0] == uid and hit.get("id", 0) == uid and absf(hit.get("distance", 0.0) - ref[1]) < 0.001
				and absf(ref[1] - distance) < 0.002,
				"%s, a %.2f m: el rayo lo toca a %.4f m; la cuenta aparte, a %.4f" % [what, distance, hit.get("distance", -1.0), ref[1]])
		_check(_picks(uid, eyes, direction) == inside, "%s, a %.2f m: el selector %s" % [what, distance,
				"lo elige" if inside else "no lo elige"])
		var r := await _pick(uid, direction)
		if inside:
			_check(r[0], "%s, a %.2f m: el host deja recogerlo: %s" % [what, distance, r[1]])
		else:
			_check(not r[0] and String(r[1]) == "estás muy lejos para agarrarlo", "%s, a %.2f m: el host no deja: %s" % [what, distance, r[1]])


## Un objeto largo (una tabla de 2 m): cuenta la parte tocada. Desde su punta,
## la parte cercana está al alcance y la lejana no; de costado, su medio sí.
func _long_item() -> void:
	var uid := _uid_at(TABLE_AT)
	_check(uid != 0, "la tabla está en el piso")
	if uid == 0:
		return
	var near_end := Vector3(TABLE_AT.x, TABLE_SIZE.y, TABLE_AT.z - TABLE_SIZE.z / 2.0 + 0.05)
	var far_end := Vector3(TABLE_AT.x, TABLE_SIZE.y, TABLE_AT.z + TABLE_SIZE.z / 2.0 - 0.05)
	await _teleport(Vector3(TABLE_AT.x, 0, TABLE_AT.z - TABLE_SIZE.z / 2.0 - 0.6), TABLE_AT)
	var eyes := _eyes()
	var to_far := (far_end - eyes).normalized()
	var far_hit := _ref_hit(eyes, to_far, 10.0)
	_check(far_hit[0] == uid and far_hit[1] > REACH + 0.3 and not _picks(uid, eyes, to_far),
			"de punta, apuntando a la punta lejana (a %.2f m): no se elige" % far_hit[1])
	var r := await _pick(uid, to_far)
	_check(not r[0] and String(r[1]) == "estás muy lejos para agarrarlo", "ni la deja el host: %s" % r[1])
	var to_near := (near_end - eyes).normalized()
	_check(_ref_hit(eyes, to_near, 10.0)[1] < REACH and _picks(uid, eyes, to_near), "apuntando a la punta cercana, sí")
	# De costado, a 1 cm afuera y adentro, apuntando a su medio.
	await _edge_item(uid, Vector3(TABLE_AT.x - TABLE_SIZE.x / 2.0, 0, TABLE_AT.z), Vector3.LEFT, "la tabla, de costado",
			Vector3(TABLE_AT.x - 0.05, TABLE_SIZE.y, TABLE_AT.z))


## Parado y agachado, y con diferencias de altura: en el piso, agachado se
## llega más lejos (los ojos bajan); desde una plataforma de 1 m, uno abajo.
func _stance_and_height() -> void:
	var low := _uid_at(LOW_AT)
	var below := _uid_at(BELOW_AT)
	_check(low != 0 and below != 0, "las granadas del piso y de abajo de la plataforma están")
	if low == 0 or below == 0:
		return
	var top := _top_of(low)
	await _teleport(_feet_at(low, top, Vector3(LOW_AT.x, 0, LOW_AT.z), Vector3.LEFT, REACH + 0.05, EYES_STANDING), top)
	var eyes := _eyes()
	var direction := (top - eyes).normalized()
	_check(not _picks(low, eyes, direction), "parado, 5 cm afuera, la del piso no se elige")
	var r := await _pick(low, direction)
	_check(not r[0] and String(r[1]) == "estás muy lejos para agarrarlo", "ni la deja el host: %s" % r[1])
	await _crouch(true)
	eyes = _eyes()
	direction = (top - eyes).normalized()
	var crouched: float = _ref_hit(eyes, direction, 10.0)[1]
	_check(crouched < REACH - 0.2 and _picks(low, eyes, direction),
			"agachado, en el mismo lugar, los ojos bajan, el rayo la toca a %.2f m y se elige" % crouched)
	r = await _pick(low, direction)
	_check(r[0], "y el host la deja recoger: %s" % r[1])
	await _crouch(false)
	# Desde una plataforma de 30 cm, una granada abajo, en el piso.
	var platform := await _wall(PLATFORM_AT + Vector3.UP * PLATFORM_SIZE.y / 2.0, PLATFORM_SIZE)
	var anchor := Vector3(PLATFORM_AT.x - PLATFORM_SIZE.x / 2.0 + 0.35, PLATFORM_SIZE.y, BELOW_AT.z)
	await _edge_item(below, anchor, Vector3.RIGHT, "desde una plataforma de 30 cm, la de abajo")
	_check(absf(actor.global_position.y - PLATFORM_SIZE.y) < 0.01, "(parado arriba de la plataforma: %s)" % actor.global_position)
	await _remove(platform)


## El caso del usuario: un estante más alto que los ojos. Del cubito metido
## asoma 1 cm por encima del filo: apuntando a esa franja se agarra; 1 cm más
## abajo, el rayo toca el estante. Agachado no asoma. Del cubito más metido no
## asoma nada: no se agarra apuntando a ningún lado. La varilla fina que
## sobresale 3 cm del filo se agarra por abajo; apuntando a la parte que queda
## arriba del estante, no.
func _over_the_edge() -> void:
	var strip := _uid_at(STRIP_AT)
	var hidden := _uid_at(HIDDEN_AT)
	var rod := _uid_at(ROD_AT)
	_check(strip != 0 and hidden != 0 and rod != 0, "los dos cubitos y la varilla están en el estante")
	if strip == 0 or hidden == 0 or rod == 0:
		return
	await _teleport(Vector3(STAND_X, 0, STRIP_AT.z), STRIP_AT)
	var near_face := STRIP_AT.x - CUBE / 2.0
	# Los ojos pueden quedar un par de milímetros más arriba o más abajo (el
	# personaje se asienta en el piso): se corre hasta que asome 1 cm desde los
	# ojos de verdad.
	for i in 4:
		var stand_x := SHELF_EDGE_X - (SHELF_TOP - _eyes().y) * (near_face - SHELF_EDGE_X) / (CUBE - STRIP)
		if absf(_eyes().x - stand_x) < 0.001:
			break
		await _teleport(Vector3(stand_x, 0, STRIP_AT.z), STRIP_AT)
	var eyes := _eyes()
	var over_edge := SHELF_TOP + (SHELF_TOP - eyes.y) / (SHELF_EDGE_X - eyes.x) * (near_face - SHELF_EDGE_X)
	var shows := SHELF_TOP + CUBE - over_edge
	_check(shows > STRIP * 0.5 and shows < STRIP * 1.5, "desde los ojos (en %s), del cubito asoma %.1f mm por encima del filo" % [
			eyes.snapped(Vector3.ONE * 0.001), shows * 1000.0])
	var on_strip := Vector3(near_face, SHELF_TOP + CUBE - shows / 2.0, STRIP_AT.z)
	var direction := (on_strip - eyes).normalized()
	var ref := _ref_hit(eyes, direction, 10.0)
	_check(ref[0] == strip and absf(eyes.distance_to(on_strip) - ref[1]) < 0.001,
			"la línea a la franja pasa el filo y toca el cubito a %.2f m" % ref[1])
	_check(_picks(strip, eyes, direction), "apuntando a la franja de 1 cm, el selector lo elige")
	var below := Vector3(near_face, over_edge - 0.01, STRIP_AT.z)
	var under := (below - eyes).normalized()
	_check(_ref_hit(eyes, under, 10.0)[0] == 0 and not _picks(strip, eyes, under), "1 cm más abajo, el rayo toca el estante: no")
	var r := await _pick(strip, under)
	_check(not r[0] and String(r[1]).begins_with("no lo ves desde ahí"), "ni lo deja el host: %s" % r[1])
	await _crouch(true)
	var low_eyes := _eyes()
	_check(not Mano.in_sight(net, actor, Op.PICKUP, strip), "agachado, los ojos bajan y no asoma: ninguna dirección lo toca primero")
	r = await _pick(strip, (on_strip - low_eyes).normalized())
	_check(not r[0] and String(r[1]).begins_with("no lo ves desde ahí"), "y el host no lo deja: %s" % r[1])
	await _crouch(false)
	r = await _pick(strip, direction)
	_check(r[0], "parado otra vez, con la mano hacia la franja, el host lo deja recoger: %s" % r[1])
	# El cubito más metido: no asoma.
	await _teleport(Vector3(STAND_X, 0, HIDDEN_AT.z), HIDDEN_AT)
	_check(not Mano.in_sight(net, actor, Op.PICKUP, hidden), "del cubito más metido no asoma nada: ninguna dirección lo toca primero")
	var to_center := (HIDDEN_AT + Vector3.UP * CUBE / 2.0 - _eyes()).normalized()
	_check(not _picks(hidden, _eyes(), to_center), "apuntando a su centro, no se elige")
	r = await _pick(hidden, to_center)
	_check(not r[0] and String(r[1]).begins_with("no lo ves desde ahí"), "ni lo deja el host: %s" % r[1])
	# La varilla que sobresale 3 cm del filo.
	await _teleport(Vector3(STAND_X, 0, ROD_AT.z), ROD_AT)
	eyes = _eyes()
	var tip := Vector3(SHELF_EDGE_X - 0.015, SHELF_TOP, ROD_AT.z)
	var to_tip := (tip - eyes).normalized()
	_check(_ref_hit(eyes, to_tip, 10.0)[0] == rod and _picks(rod, eyes, to_tip),
			"la varilla fina, por abajo de los 3 cm que sobresalen: se elige")
	var inner := Vector3(SHELF_EDGE_X + 0.3, SHELF_TOP + ROD_SIZE.y / 2.0, ROD_AT.z)
	var to_inner := (inner - eyes).normalized()
	_check(_ref_hit(eyes, to_inner, 10.0)[0] == 0 and not _picks(rod, eyes, to_inner),
			"apuntando a la parte que queda sobre el estante, el rayo toca el estante: no")
	r = await _pick(rod, to_inner)
	_check(not r[0] and String(r[1]).begins_with("no lo ves desde ahí"), "ni la deja el host: %s" % r[1])
	r = await _pick(rod, to_tip)
	_check(r[0], "por abajo, el host la deja recoger: %s" % r[1])


## Lo que tapa: una pared fina pegada al objeto; otro objeto suelto delante (se
## elige ese, y el de atrás no lo deja el host); una caja delante (se elige la
## caja). La pared, el objeto y la caja, primero que el objeto pedido.
func _blockers() -> void:
	var thin := _uid_at(THIN_AT)
	var block := _uid_at(BLOCK_AT)
	var behind := _uid_at(BEHIND_AT)
	var boxed := _uid_at(BEHIND_BOX_AT)
	_check(thin != 0 and block != 0 and behind != 0 and boxed != 0, "la granada de la pared fina, el bloque, la de atrás y la de atrás de la caja están")
	if thin == 0 or block == 0 or behind == 0 or boxed == 0:
		return
	# Una pared de 1 cm, a 1 cm de la granada.
	await _teleport(THIN_AT + Vector3(-1.2, 0, 0), THIN_AT)
	var top := _top_of(thin)
	var eyes := _eyes()
	var direction := (top - eyes).normalized()
	_check(_picks(thin, eyes, direction), "sin la pared, la granada se elige")
	var box := net.world_view(thin).interact_focus().bounds
	var wall := await _wall(Vector3(THIN_AT.x + box.position.x - 0.015, 0.6, THIN_AT.z), Vector3(0.01, 1.2, 0.6))
	_check(_ref_hit(eyes, direction, 10.0)[0] == 0 and not _picks(thin, eyes, direction),
			"con una pared de 1 cm a 1 cm de ella, el rayo toca la pared: no")
	var r := await _pick(thin, direction)
	_check(not r[0] and String(r[1]).begins_with("no lo ves desde ahí"), "ni la deja el host: %s" % r[1])
	await _remove(wall)
	r = await _pick(thin, direction)
	_check(r[0], "sin la pared, el host la deja: %s" % r[1])
	# El bloque delante de la granada: se elige el bloque.
	await _teleport(Vector3(BLOCK_AT.x - 0.9, 0, BLOCK_AT.z), BEHIND_AT)
	eyes = _eyes()
	var to_behind := (BEHIND_AT + Vector3.UP * 0.05 - eyes).normalized()
	var seen := _chosen(eyes, to_behind)
	_check(_ref_hit(eyes, to_behind, 10.0)[0] == block and seen.get("id", 0) == block,
			"apuntando a la granada a través del bloque, se elige el bloque, lo primero que toca: %s" % [seen])
	r = await _pick(behind, to_behind)
	_check(not r[0] and String(r[1]).begins_with("no lo ves desde ahí"), "pidiendo la granada de atrás con esa mano, el host no la deja: %s" % r[1])
	r = await _pick(block, to_behind)
	_check(r[0], "pidiendo el bloque, sí: %s" % r[1])
	_check(_picks(behind, eyes, to_behind), "sin el bloque, la misma mano elige la granada")
	# La caja larga delante de una granada: se elige la caja.
	await _teleport(Vector3(BEHIND_BOX_AT.x, 0, LONG_AT.z - LONG_SIZE.z / 2.0 - 0.6), BEHIND_BOX_AT)
	eyes = _eyes()
	var to_boxed := (BEHIND_BOX_AT + Vector3.UP * 0.08 - eyes).normalized()
	seen = _chosen(eyes, to_boxed)
	_check(seen.get("kind", "") == "box" and seen.get("id", 0) == long_box.container_id,
			"apuntando a la granada de atrás de la caja, se elige la caja: %s" % [seen])
	r = await _pick(boxed, to_boxed)
	_check(not r[0] and String(r[1]).begins_with("no lo ves desde ahí"), "y el host no deja agarrar la granada a través de ella: %s" % r[1])


## La llave con una hitbox 60 cm más grande que su modelo por cada lado: la
## hitbox no ayuda. Con una pared delante del modelo y la hitbox asomando de
## este lado, apuntando a la hitbox no se elige nada; sin la pared, pasando 1 cm
## al lado del modelo (adentro de la hitbox), tampoco; apuntando al modelo, sí.
func _hitbox_does_not_help() -> void:
	var uid := _uid_at(BIG_KEY_AT)
	_check(uid != 0 and big_key_def.pickup_hitbox != null and InvPickupHitbox.active(big_key_def) != null,
			"la llave de hitbox grande está en el piso, con su hitbox")
	if uid == 0:
		return
	var without := big_key_def.duplicate(true) as InvItemDef
	without.pickup_hitbox = null
	_check(InvReach.fingerprint_of(big_key_def) == InvReach.fingerprint_of(without)
			and InvReach.item_bounds(big_key_def) == InvReach.item_bounds(without), "la hitbox no cambia los triángulos que toca el rayo")
	var model := net.world_view(uid).interact_focus().bounds
	model.position += BIG_KEY_AT
	var hitbox := big_key_def.pickup_hitbox.bounds()
	hitbox.position += BIG_KEY_AT
	await _teleport(BIG_KEY_AT + Vector3(-1.0, 0, 0), BIG_KEY_AT)
	var wall_x := model.position.x - 0.3
	var wall := await _wall(Vector3(wall_x, 1.2, BIG_KEY_AT.z), Vector3(0.04, 2.4, 2.0))
	_check(hitbox.position.x < wall_x - 0.25, "la hitbox asoma %.2f m de este lado de la pared" % (wall_x - hitbox.position.x))
	var eyes := _eyes()
	var poke := Vector3(hitbox.position.x + 0.1, 0.3, BIG_KEY_AT.z)
	var to_poke := (poke - eyes).normalized()
	_check(_chosen(eyes, to_poke).is_empty(), "apuntando a la hitbox que asoma, no se elige nada")
	var r := await _pick(uid, to_poke)
	_check(not r[0], "ni la deja el host: %s" % r[1])
	var to_model := (model.get_center() - eyes).normalized()
	_check(not _picks(uid, eyes, to_model), "apuntando al modelo, detrás de la pared, tampoco")
	r = await _pick(uid, to_model)
	_check(not r[0] and String(r[1]).begins_with("no lo ves desde ahí"), "ni la deja el host: %s" % r[1])
	await _remove(wall)
	var beside := Vector3(model.position.x - 0.01, model.position.y + 0.01, BIG_KEY_AT.z)
	var to_beside := (beside - eyes).normalized()
	_check(not _picks(uid, eyes, to_beside), "sin la pared, pasando 1 cm al lado del modelo (adentro de la hitbox), no")
	to_model = (model.get_center() + Vector3.UP * model.size.y * 0.4 - eyes).normalized()
	_check(_picks(uid, eyes, to_model), "apuntando al modelo, sí")
	r = await _pick(uid, to_model)
	_check(r[0], "y el host la deja recoger: %s" % r[1])


## El marco hueco: el rayo pasa por su hueco y toca el piso; apuntando a una
## barra, se agarra. Su hitbox, que tapa el hueco, no cambia nada.
func _hole() -> void:
	var uid := _uid_at(FRAME_AT)
	_check(uid != 0, "el marco está en el piso")
	if uid == 0:
		return
	await _teleport(FRAME_AT + Vector3(-1.0, 0, 0), FRAME_AT)
	var eyes := _eyes()
	var hole := FRAME_AT
	var through := (hole - eyes).normalized()
	_check(_ref_hit(eyes, through, 10.0)[0] == 0 and not _picks(uid, eyes, through),
			"por el hueco, el rayo toca el piso: no se elige")
	var r := await _pick(uid, through)
	_check(not r[0], "ni lo deja el host: %s" % r[1])
	var bar := FRAME_AT + Vector3(-(FRAME_SIZE - FRAME_BAR) / 2.0, FRAME_HEIGHT, 0)
	var to_bar := (bar - eyes).normalized()
	_check(_ref_hit(eyes, to_bar, 10.0)[0] == uid and _picks(uid, eyes, to_bar), "apuntando a una barra, se elige")
	r = await _pick(uid, to_bar)
	_check(r[0], "y el host lo deja recoger: %s" % r[1])


## En tercera persona: una cámara que ve la granada por encima de un murito
## que tapa los ojos no deja agarrarla (el rayo desde los ojos toca el murito).
## Sin el murito, sí.
func _third_person_eyes() -> void:
	var uid := _uid_at(THIRD_AT)
	_check(uid != 0, "la granada de la tercera persona está")
	if uid == 0:
		return
	await _teleport(THIRD_AT + Vector3(-1.2, 0, 0), THIRD_AT)
	var top := _top_of(uid)
	var eyes := _eyes()
	var wall := await _wall(Vector3(THIRD_AT.x - 0.6, 0.5, THIRD_AT.z), Vector3(0.04, 1.0, 1.0))
	var high := eyes + Vector3.UP * 1.0
	var look := (top - high).normalized()
	_check(_ref_hit(high, look, 10.0)[0] == uid and _ref_hit(eyes, (top - eyes).normalized(), 10.0)[0] == 0,
			"desde 1 m más arriba de los ojos se ve la granada; desde los ojos, el murito la tapa")
	_check(_chosen(high, look, true).is_empty(), "con la cámara ahí, la mira la ve, pero no se elige")
	var r := await _pick(uid, (top - eyes).normalized())
	_check(not r[0] and String(r[1]).begins_with("no lo ves desde ahí"), "ni la deja el host: %s" % r[1])
	await _remove(wall)
	_check(_picks(uid, high, look, true), "sin el murito, la misma mira la elige")


## Con la cámara de verdad, en primera y en tercera persona: el indicador, E y
## el host coinciden. La granada de la tercera persona; y el cubito que asoma
## de un estante, desde donde la cámara (a 1,6 m, un poco más abajo que los
## ojos) ve 1 cm de él.
func _camera_views() -> void:
	for first: bool in [true, false]:
		var what := "primera persona" if first else "tercera persona"
		var uid := _uid_at(THIRD_AT) if first else _uid_at(LOW_AT)
		if uid == 0:
			# La de la tercera persona ya se recogió: se suelta una granada para la otra vista.
			uid = await _drop_grenade_near(THIRD_AT if first else LOW_AT)
		_check(uid != 0, "%s: hay una granada para mirar" % what)
		if uid == 0:
			continue
		var spot: Vector3 = net.replica.world[uid]["pos"]
		await _teleport(spot + Vector3(-1.3, 0, 0), spot)
		await _set_first_person(first)
		await _aim(_top_of(uid) + Vector3.DOWN * 0.03)
		await _e_picks(uid, "%s, la granada" % what)
	await _set_first_person(true)
	# El cubito del estante: se suelta uno igual sobre el estante, más metido.
	var strip_spot := Vector3(31.12, SHELF_TOP, 5.0)
	var cube := await _put_on_shelf(strip_spot)
	_check(cube != 0, "hay un cubito sobre el estante para mirar con la cámara")
	if cube == 0:
		return
	for first: bool in [true, false]:
		var what := "%s, el cubito del estante" % ("primera persona" if first else "tercera persona")
		await _teleport(Vector3(29.5, 0, strip_spot.z), strip_spot)
		await _set_first_person(first)
		await _frames(10)
		var from: Vector3 = camera.aim_ray()[0]
		var near_face := strip_spot.x - CUBE / 2.0
		var over_edge := SHELF_TOP + (SHELF_TOP - from.y) / (SHELF_EDGE_X - from.x) * (near_face - SHELF_EDGE_X)
		var shows := SHELF_TOP + CUBE - over_edge
		_check(shows > 0.004 and shows < 0.03, "%s: desde la mira asoman %.1f mm" % [what, shows * 1000.0])
		await _aim(Vector3(near_face, (over_edge + SHELF_TOP + CUBE) / 2.0, strip_spot.z))
		if first:
			_check(_marks(cube), "%s: apuntando a la franja, el indicador lo marca: %s" % [what, _describe()])
		else:
			await _e_picks(cube, what)
	await _set_first_person(true)


## Suelta una granada del inventario propio cerca de `near` (parado al lado):
## el número del objeto nuevo en el piso, o 0.
func _drop_grenade_near(near: Vector3) -> int:
	var own := net.replica.own.sorted_uids().filter(func(id: int) -> bool: return net.replica.own.stacks[id].def_id == &"granada")
	if own.is_empty():
		return 0
	await _teleport(near + Vector3(-1.0, 0, 0), near)
	var before := net.replica.world.keys()
	var uid: int = own[0]
	var r := await _req(Op.DROP, [0, uid, net.replica.own.get_stack(uid).ver, 1], [uid])
	await _ticks(4)
	if not r[0]:
		return 0
	for key: int in net.replica.world:
		if not before.has(key):
			return key
	return 0


## Pone un cubito sobre el estante: el host lo pone en el mundo como lo de un
## InvPickupSpawn. Devuelve su número.
func _put_on_shelf(spot: Vector3) -> int:
	var stack := InvStack.make(net.authority.alloc_uid(), cube_def.id, 1, {})
	net.authority._put_in_world(stack, spot, false)
	net.authority.flush({})
	await _ticks(3)
	await _frames(2)
	return stack.uid if net.replica.world.has(stack.uid) else 0


## Pedidos que el host no acepta: sin dirección, con NAN, INF, cero, largo 2 o
## enteros; con la dirección hacia otra cosa; y lo que InvProtocol descarta
## antes de llegar al host.
func _invalid_requests() -> void:
	var uid := _uid_at(GRENADE_AT)
	if uid == 0:
		uid = await _drop_grenade_near(GRENADE_AT)
	_check(uid != 0, "hay una granada para los pedidos inválidos")
	if uid == 0:
		return
	var spot: Vector3 = net.replica.world[uid]["pos"]
	await _teleport(spot + Vector3(-1.2, 0, 0), spot)
	var good := Mano.toward_item(net, actor, uid)
	_check(_picks(uid, _eyes(), good), "con la mano bien puesta, se elige")
	for case: Array in [["sin dirección", [uid]], ["con NAN", [uid, NAN, 0.0, 0.0, -1]], ["con INF", [uid, INF, 0.0, 0.0, -1]],
			["con la dirección en cero", [uid, 0.0, 0.0, 0.0, -1]],
			["con una dirección de largo 2", [uid, good.x * 2.0, good.y * 2.0, good.z * 2.0, -1]],
			["con enteros", [uid, 1, 0, 0, -1]], ["con un número de más", [uid, good.x, good.y, good.z, -1, 0.0]],
			["con el tick con decimales", [uid, good.x, good.y, good.z, 1.0]]]:
		var seq := net.replica.request(Op.PICKUP, case[1], [uid])
		await _until(func() -> bool: return _answers.has(seq), 5.0)
		var answer: Array = _answers.get(seq, [true, "sin respuesta"])
		_check(not answer[0] and String(answer[1]).begins_with("pedido inválido"), "%s, el host no lo acepta: %s" % [case[0], answer[1]])
		_check(InvProtocol.parse_request(InvProtocol.encode_request(9, Op.PICKUP, case[1])).is_empty() == (case[0] != "con NAN"
				and case[0] != "con INF" and case[0] != "con la dirección en cero" and case[0] != "con una dirección de largo 2"),
				"%s: de otra PC, %s" % [case[0], "llega al host (y el host la mira)" if case[0] in ["con NAN", "con INF",
				"con la dirección en cero", "con una dirección de largo 2"] else "ni llega: no tiene la forma de un pedido"])
	_check(net.replica.world.has(uid) and not net.replica.is_taken(uid), "la granada sigue en el piso")
	var r := await _pick(uid, -good)
	_check(not r[0] and String(r[1]) == "no lo estás mirando", "con la mano para el otro lado: %s" % r[1])
	var other := _uid_at(TABLE_AT)
	if other != 0:
		r = await _pick(other, good)
		_check(not r[0], "pidiendo otro objeto con la mano hacia la granada, el host no lo da: %s" % r[1])
	r = await _pick(uid, good)
	_check(r[0], "y con la mano bien puesta, sí: %s" % r[1])
	var again := net.replica.request(Op.PICKUP, InvProtocol.aimed_args(uid, good), [uid])
	await _until(func() -> bool: return _answers.has(again), 5.0)
	_check(not _answers.get(again, [true])[0] and String(_answers.get(again, [true, ""])[1]).begins_with("ya no está"),
			"pedida otra vez, ya no está: %s" % [_answers.get(again)])


## La caja larga y la girada en el borde del alcance: el rayo desde los ojos
## hacia el centro de la cara que da al personaje, 1 cm afuera (ni el selector
## ni el host) y 1 cm adentro (los dos; y abierta no se cierra sola).
func _box_edges() -> void:
	var place := long_box.global_transform
	var half := LONG_SIZE / 2.0
	await _edge_box(long_box, place * Vector3(0, LONG_SIZE.y / 2.0, -half.z), Vector3.FORWARD, "la caja larga, de costado")
	await _edge_box(long_box, place * Vector3(-half.x, LONG_SIZE.y / 2.0, 0), Vector3.LEFT, "la caja larga, de punta")
	await _edge_box(long_box, place * Vector3(-half.x + 0.05, LONG_SIZE.y / 2.0, -half.z), Vector3(-1, 0, -1).normalized(),
			"la caja larga, desde una esquina")
	# La punta lejana, con 3 m de largo, no se alcanza desde la otra punta.
	await _teleport(place * Vector3(-half.x - 0.5, 0, 0), long_box.center())
	var far := place * Vector3(half.x - 0.05, LONG_SIZE.y, 0)
	var to_far := (far - _eyes()).normalized()
	_check(not _picks_box(long_box, _eyes(), to_far), "apuntando a su punta lejana, a %.2f m: no" % _eyes().distance_to(far))
	var r := await _host_opens(long_box, to_far)
	_check(not r[0] and String(r[1]) == "estás muy lejos de la caja", "ni la abre el host: %s" % r[1])
	var turned := turned_box.global_transform
	var thalf := TURNED_SIZE / 2.0
	await _edge_box(turned_box, turned * Vector3(0, TURNED_SIZE.y / 2.0, -thalf.z), -turned.basis.z.normalized(),
			"la caja girada, de frente a su cara larga")
	await _edge_box(turned_box, turned * Vector3(-thalf.x, TURNED_SIZE.y / 2.0, 0), -turned.basis.x.normalized(), "la caja girada, de punta")


## Se para alejándose de `point` (en la cara de la caja) por `away`, con los
## ojos a REACH ± EDGE de él; apunta ahí.
func _edge_box(box: InvContainer, point: Vector3, away: Vector3, what: String) -> void:
	for inside: bool in [false, true]:
		var distance := REACH - EDGE if inside else REACH + EDGE
		var flat := Vector3(away.x, 0, away.z).normalized()
		var rise := EYES_STANDING - point.y
		var h := sqrt(maxf(distance * distance - rise * rise, 0.0))
		await _teleport(Vector3(point.x, 0, point.z) + flat * h, point)
		var eyes := _eyes()
		var direction := (point - eyes).normalized()
		var hit := InvReach.first_hit(_space(), eyes, direction, 10.0, net.replica.world, catalog, InvReach.own_shapes(actor))
		_check(hit.get("kind", "") == "box" and hit.get("id", 0) == box.container_id and absf(hit["distance"] - distance) < 0.002,
				"%s, a %.2f m: el rayo la toca a %.4f m" % [what, distance, hit.get("distance", -1.0)])
		_check(_picks_box(box, eyes, direction) == inside, "%s, a %.2f m: el selector %s" % [what, distance,
				"la elige" if inside else "no la elige"])
		var r := await _host_opens(box, direction)
		if inside:
			_check(r[0] and r.size() > 2 and r[2], "%s, a %.2f m: el host la abre y no se cierra sola: %s" % [what, distance, r])
		else:
			_check(not r[0] and String(r[1]) == "estás muy lejos de la caja", "%s, a %.2f m: el host no: %s" % [what, distance, r[1]])


## La caja abierta, sin mirarla: se opera mientras los ojos estén al alcance de
## su volumen y se cierra al pasarlo. El personaje mira para el otro lado.
func _open_without_aiming() -> void:
	var place := long_box.global_transform
	var volume := _volume(LONG_SIZE)
	var measure := func(eyes: Vector3) -> float: return _ref_nearest(place, volume, eyes).distance_to(eyes)
	var anchor := Vector3(LONG_AT.x, 0, LONG_AT.z - LONG_SIZE.z / 2.0)
	await _teleport(anchor + Vector3.FORWARD * 1.0, long_box.center())
	var r := await _req(Op.OPEN, [long_box.container_id])
	_check(r[0] and net.replica.box_id == long_box.container_id, "abre la caja larga: %s" % r[1])
	var closed := []
	var on_closed := func(id: int, reason: String) -> void: closed.append([id, reason])
	net.container_closed.connect(on_closed)
	var away_point := anchor + Vector3.FORWARD * 10.0
	await _teleport(_eyes_feet(anchor, Vector3.FORWARD, REACH - EDGE, measure), away_point)
	camera.yaw = actor.state.facing_yaw
	await _ticks(10)
	_check(closed.is_empty() and net.replica.box_id == long_box.container_id,
			"de espaldas, sin mirarla, con los ojos 1 cm adentro, sigue abierta (%.3f m)" % measure.call(_eyes()))
	var own := net.replica.own.sorted_uids()
	_check(not own.is_empty(), "tiene algo en el inventario para meter")
	if own.is_empty():
		net.container_closed.disconnect(on_closed)
		return
	var uid: int = own[0]
	var def := net.replica.own.def_of(uid)
	var spot: Array = net.replica.box.free_spot(def) if net.replica.box != null else []
	r = await _req(Op.MOVE, [InvProtocol.OWN, uid, net.replica.own.get_stack(uid).ver, long_box.container_id, spot[0].x, spot[0].y,
			spot[1]], [uid]) if not spot.is_empty() else [false, "no entra"]
	_check(r[0] and net.replica.box != null and net.replica.box.has(uid), "sin mirarla, mete %s en la caja: %s" % [def.id, r[1]])
	var back := net.replica.own.free_spot(def)
	r = await _req(Op.MOVE, [long_box.container_id, uid, net.replica.box.get_stack(uid).ver, InvProtocol.OWN, back[0].x,
			back[0].y, back[1]], [uid])
	_check(r[0] and net.replica.own.has(uid), "y lo vuelve a sacar: %s" % r[1])
	await _teleport(_eyes_feet(anchor, Vector3.FORWARD, REACH + EDGE, measure), away_point)
	await _until(func() -> bool: return not closed.is_empty(), 1.0)
	net.container_closed.disconnect(on_closed)
	_check(closed.size() == 1 and closed[0][0] == long_box.container_id and closed[0][1] == "te alejaste de la caja"
			and net.replica.box_id == 0, "con los ojos 1 cm afuera, el host la cierra: %s" % [closed])
	r = await _req(Op.MOVE, [InvProtocol.OWN, uid, net.replica.own.get_stack(uid).ver, long_box.container_id, 0, 0, 0], [uid])
	_check(not r[0], "y ya no se opera: %s" % r[1])


## Dónde pararse, sobre `anchor` y alejándose por `away`, para que los ojos
## (parado) queden a `distance` según `measure` (func(ojos) -> float).
func _eyes_feet(anchor: Vector3, away: Vector3, distance: float, measure: Callable) -> Vector3:
	var low := 0.0
	var high := 12.0
	for i in 60:
		var mid := (low + high) * 0.5
		if measure.call(anchor + away * mid + Vector3.UP * EYES_STANDING) < distance:
			low = mid
		else:
			high = mid
	return anchor + away * (low + high) * 0.5


## La caja girada y escalada, abierta: junto a la esquina vacía de la caja
## alineada al mundo que la encierra, con los ojos 15 cm adentro de esa caja y
## afuera de la de verdad, el host la cierra.
func _turned_box_closes() -> void:
	var place := turned_box.global_transform
	var volume := _volume(TURNED_SIZE)
	var thalf := TURNED_SIZE / 2.0
	var face := place * Vector3(0, TURNED_SIZE.y / 2.0, -thalf.z)
	await _teleport(Vector3(face.x, 0, face.z) - place.basis.z.normalized() * 1.0, face)
	var r := await _req(Op.OPEN, [turned_box.container_id])
	_check(r[0] and net.replica.box_id == turned_box.container_id, "abre la caja girada: %s" % r[1])
	var world := AABB(place * volume.get_endpoint(0), Vector3.ZERO)
	for i in 8:
		world = world.expand(place * volume.get_endpoint(i))
	var corners := [Vector3(world.position.x, 0, world.position.z), Vector3(world.end.x, 0, world.position.z),
			Vector3(world.position.x, 0, world.end.z), Vector3(world.end.x, 0, world.end.z)]
	var emptiest: Vector3 = corners[0]
	for corner: Vector3 in corners:
		var c: Vector3 = corner + Vector3.UP * EYES_STANDING
		var e: Vector3 = emptiest + Vector3.UP * EYES_STANDING
		if _ref_nearest(place, volume, c).distance_to(c) > _ref_nearest(place, volume, e).distance_to(e):
			emptiest = corner
	var away := Vector3(emptiest.x - world.get_center().x, 0, emptiest.z - world.get_center().z).normalized()
	var aligned := func(at: Vector3) -> float: return at.clamp(world.position, world.end).distance_to(at)
	var closed := []
	var on_closed := func(id: int, reason: String) -> void: closed.append([id, reason])
	net.container_closed.connect(on_closed)
	await _teleport(_eyes_feet(emptiest, away, REACH - 0.15, aligned), turned_box.center())
	await _until(func() -> bool: return not closed.is_empty(), 1.0)
	net.container_closed.disconnect(on_closed)
	var eyes := _eyes()
	var true_distance := InvReach.box_distance(eyes, turned_box)
	_check(aligned.call(eyes) < REACH and true_distance > REACH + 0.05 and absf(true_distance - _ref_nearest(place, volume, eyes).distance_to(eyes)) < 0.0005,
			"junto a la esquina vacía: los ojos a %.2f m de la caja alineada al mundo y a %.2f m de la de verdad" % [aligned.call(eyes), true_distance])
	_check(closed.size() == 1 and closed[0][1] == "te alejaste de la caja", "ahí el host la cierra: %s" % [closed])


## Interaction Range se lee en vivo, igual en el selector y en el host, y entra
## en la huella; también los triángulos de cada tipo. Pickup Aim Margin ya no está.
func _tuning_live() -> void:
	var place := long_box.global_transform
	var point := place * Vector3(0, LONG_SIZE.y / 2.0, -LONG_SIZE.z / 2.0)
	var rise := EYES_STANDING - point.y
	await _teleport(Vector3(point.x, 0, point.z) + Vector3.FORWARD * sqrt(2.3 * 2.3 - rise * rise), point)
	var direction := (point - _eyes()).normalized()
	_check(not _picks_box(long_box, _eyes(), direction), "a 2,3 m, con 2 m de alcance, el selector no la elige")
	var r := await _host_opens(long_box, direction)
	_check(not r[0], "ni el host la abre: %s" % r[1])
	var before_tuning := SimFingerprint.tuning_text(net.tuning)
	var before_inventory := net.fingerprint_text()
	net.tuning.interaction_range = 2.5
	_check(_picks_box(long_box, _eyes(), direction), "con 2,5 m, el selector la elige")
	r = await _host_opens(long_box, direction)
	_check(r[0], "y el host la abre: %s" % r[1])
	var tuning_text := SimFingerprint.tuning_text(net.tuning)
	_check(tuning_text != before_tuning and tuning_text.contains("interaction_range=2.5") and not tuning_text.contains("pickup_aim_margin")
			and not tuning_text.contains("pickup_range"), "Interaction Range entra en la huella del Tuning (y Pickup Aim Margin ya no está)")
	_check(net.fingerprint_text() != before_inventory and net.fingerprint_text().begins_with("jugador 12×16 alcance 2.5 "),
			"y en la del inventario: %s" % net.fingerprint_text().get_slice("\n", 0))
	net.tuning.interaction_range = REACH
	var text := grenade_def.fingerprint_text()
	_check(text.contains(" rayo 1546 ") and not text.contains(" vista "), "la huella de la granada lleva sus triángulos: …%s" % text.right(40))
	var bigger := grenade_def.duplicate(true) as InvItemDef
	bigger.world_size += 0.001
	_check(bigger.fingerprint_text() != text, "un modelo 1 mm más grande cambia la huella del catálogo")
	var changed := big_key_def.duplicate(true) as InvItemDef
	changed.pickup_hitbox.box_size.x += 0.001
	_check(InvReach.fingerprint_of(changed) == InvReach.fingerprint_of(big_key_def) and changed.fingerprint_text() != big_key_def.fingerprint_text(),
			"la hitbox no cambia los triángulos del rayo, pero sigue en la huella del tipo")


## Cuánto cuesta el selector por cuadro (lo pide el indicador en cada uno):
## mirando un objeto, mirando el piso y mirando la franja del estante. Y el
## rayo del host al recoger.
func _cost() -> void:
	var spot := Vector3(STAND_X, 0, STRIP_AT.z)
	await _teleport(spot, Vector3(31, 0, STRIP_AT.z))
	var eyes := _eyes()
	var cases := [["mirando el piso", (Vector3(27.0, 0.0, 5.0) - eyes).normalized()],
			["mirando el estante (el nivel)", (Vector3(SHELF_EDGE_X, SHELF_TOP - 0.05, 5.0) - eyes).normalized()],
			["mirando el cielo (nada)", Vector3(0.3, 1, 0).normalized()]]
	var cube := await _put_on_shelf(STRIP_AT)
	if cube != 0:
		cases.append(["mirando la franja de 1 cm de un cubito", (Vector3(STRIP_AT.x - CUBE / 2.0, SHELF_TOP + CUBE - STRIP / 2.0,
				STRIP_AT.z) - eyes).normalized()])
	var lines := PackedStringArray()
	for case: Array in cases:
		var begin := Time.get_ticks_usec()
		for i in 500:
			net.interaction_target(actor, eyes, case[1], false)
		lines.append("%s %.1f µs" % [case[0], (Time.get_ticks_usec() - begin) / 500.0])
	var start := Time.get_ticks_usec()
	for i in 500:
		InvReach.first_hit(_space(), eyes, cases[0][1], REACH + InvAuthority.FAR_LOOK, net.authority.world, catalog,
				InvReach.own_shapes(actor))
	lines.append("el rayo del host %.1f µs" % ((Time.get_ticks_usec() - start) / 500.0))
	_log("costo, con %d objetos sueltos en el mundo: %s" % [net.replica.world.size(), ", ".join(lines)])
	_check(true, "costo medido")


# --- En pareja (dos procesos) -------------------------------------------------------

func _pair_host() -> void:
	_check(await _until(func() -> bool: return net.authority != null and lab._local_actor != null and net.replica.own != null, 15.0),
			"el host arranca con su personaje")
	actor = lab._local_actor
	var found := {}
	_check(await _until(func() -> bool:
		for peer in net.authority.welcomed_peers():
			if peer != multiplayer.get_unique_id():
				found["peer"] = peer
		return found.has("peer"), 30.0), "entró el cliente: la huella, con las cajas y los objetos de prueba, coincide")
	var grenade := _uid_at(GRENADE_AT)
	var rod := _uid_at(ROD_AT)
	var hidden := _uid_at(HIDDEN_AT)
	var table := _uid_at(TABLE_AT)
	_check(await _until(func() -> bool: return multiplayer.get_peers().is_empty(), 150.0), "el cliente terminó y se fue")
	var other := net.authority.player_inventory(found.get("peer", -1))
	_check(not net.authority.world.has(grenade), "el host le dejó recoger la granada que su selector elegía")
	_check(not net.authority.world.has(rod), "y la varilla que sobresale del estante")
	_check(net.authority.world.has(hidden) and net.authority.world.has(table), "y no el cubito metido ni la tabla lejana")
	var in_box := long_box.inventory.grid.sorted_uids()
	_check(in_box.has(grenade), "la granada quedó en la caja larga, metida sin mirarla: %s" % [in_box])
	_check(other == null or not other.grid.has(grenade), "y ya no está en el inventario del cliente")
	_finish(true)


func _pair_client() -> void:
	_check(await _until(func() -> bool: return net.replica.has_state and lab._local_actor != null and net.replica.own != null, 20.0),
			"el cliente recibe el estado del host")
	actor = lab._local_actor
	if actor == null:
		_finish()
		return
	await _set_first_person(true)
	var grenade := _uid_at(GRENADE_AT)
	var rod := _uid_at(ROD_AT)
	var hidden := _uid_at(HIDDEN_AT)
	var table := _uid_at(TABLE_AT)
	_check(grenade != 0 and rod != 0 and hidden != 0 and table != 0, "el cliente ve la granada, la varilla, el cubito y la tabla")
	if grenade == 0 or rod == 0 or hidden == 0 or table == 0:
		_finish()
		return
	# La granada: 35 cm adentro del alcance, apunta con la cámara y E.
	var measure := _eyes_to(grenade)
	await _walk_near(measure, Vector3(GRENADE_AT.x, 0, GRENADE_AT.z), Vector3.LEFT, -PAIR_MARGIN, GRENADE_AT)
	await _aim(_top_of(grenade) + Vector3.DOWN * 0.03)
	await _e_picks(grenade, "a %.2f m, la granada" % measure.call(_eyes()))
	# La varilla que sobresale del estante: por abajo, con la cámara y E.
	await _walk_spot(Vector3(SHELF_EDGE_X - 0.5, 0, ROD_AT.z), ROD_AT)
	await _aim(Vector3(SHELF_EDGE_X - 0.015, SHELF_TOP, ROD_AT.z))
	await _e_picks(rod, "la varilla que sobresale del estante")
	# El cubito metido: el selector no lo elige y el host no lo deja.
	await _walk_spot(Vector3(SHELF_EDGE_X - 0.5, 0, HIDDEN_AT.z), HIDDEN_AT)
	var to_hidden := (HIDDEN_AT + Vector3.UP * CUBE / 2.0 - _eyes()).normalized()
	_check(not _picks(hidden, _eyes(), to_hidden), "el selector no elige el cubito metido")
	var r := await _pick(hidden, to_hidden)
	_check(not r[0] and String(r[1]).begins_with("no lo ves desde ahí"), "pedido igual, el host no lo deja: %s" % r[1])
	r = await _pick(hidden, Vector3(2, 0, 0))
	_check(not r[0] and String(r[1]).begins_with("pedido inválido"), "con una dirección de largo 2, el host no lo acepta: %s" % r[1])
	# La tabla, 35 cm afuera del alcance.
	measure = _eyes_to(table)
	await _walk_near(measure, Vector3(TABLE_AT.x - TABLE_SIZE.x / 2.0, 0, TABLE_AT.z), Vector3.LEFT, PAIR_MARGIN, TABLE_AT)
	var to_table := Mano.toward_item(net, actor, table)
	_check(not _picks(table, _eyes(), to_table), "a %.2f m, el selector no elige la tabla" % measure.call(_eyes()))
	r = await _pick(table, to_table)
	_check(not r[0] and String(r[1]) == "estás muy lejos para agarrarlo", "pedida igual, el host no la deja: %s" % r[1])
	# La caja larga: afuera no, adentro sí, con E.
	var place := long_box.global_transform
	var box_measure := func(eyes: Vector3) -> float: return _ref_nearest(place, _volume(LONG_SIZE), eyes).distance_to(eyes)
	var anchor := Vector3(LONG_AT.x, 0, LONG_AT.z - LONG_SIZE.z / 2.0)
	var face := place * Vector3(0, LONG_SIZE.y / 2.0, -LONG_SIZE.z / 2.0)
	await _walk_near(box_measure, anchor, Vector3.FORWARD, PAIR_MARGIN, long_box.center())
	await _aim(face)
	_check(ui.interaction_target().is_empty(), "a %.2f m, el selector no elige la caja" % box_measure.call(_eyes()))
	r = await _req(Op.OPEN, InvProtocol.aimed_args(long_box.container_id, (face - _eyes()).normalized()))
	_check(not r[0] and String(r[1]) == "estás muy lejos de la caja", "pedida igual, el host no la abre: %s" % r[1])
	await _walk_near(box_measure, anchor, Vector3.FORWARD, -PAIR_MARGIN - 0.1, long_box.center())
	await _aim(face)
	_check(ui.interaction_target().get("id", 0) == long_box.container_id, "a %.2f m, el selector elige la caja" % box_measure.call(_eyes()))
	_press_e()
	_check(await _until(func() -> bool: return net.replica.box_id == long_box.container_id, 5.0), "con E se abre")
	# Sin mirarla: la cámara para el otro lado, mete la granada.
	camera.yaw += PI
	camera.pitch = 0.0
	await _frames(3)
	var spot: Array = net.replica.box.free_spot(grenade_def) if net.replica.box != null else []
	r = await _req(Op.MOVE, [InvProtocol.OWN, grenade, net.replica.own.get_stack(grenade).ver, long_box.container_id, spot[0].x,
			spot[0].y, spot[1]], [grenade]) if not spot.is_empty() and net.replica.own.has(grenade) else [false, "no entra"]
	_check(r[0], "mirando para el otro lado, mete la granada en la caja: %s" % r[1])
	# Camina para donde mira, alejándose, hasta que el host se la cierra.
	var closed := {}
	net.container_closed.connect(func(_id: int, reason: String) -> void:
		if not closed.has("reason"):
			closed["reason"] = reason
			closed["distance"] = box_measure.call(_eyes()))
	var last_open := 0.0
	var limit := Time.get_ticks_msec() + 8000
	Input.action_press("move_forward")
	while Time.get_ticks_msec() < limit and not closed.has("reason"):
		if net.replica.box_id == long_box.container_id:
			last_open = box_measure.call(_eyes())
		await get_tree().physics_frame
	Input.action_release("move_forward")
	_check(closed.get("reason", "") == "te alejaste de la caja", "alejándose sin mirarla, el host la cierra: %s" % [closed])
	_check(last_open >= REACH - 0.05 and float(closed.get("distance", 0.0)) > REACH,
			"no se cerró antes de salir del alcance (abierta hasta %.2f m, cerrada a %.2f m, con la demora de la red)" % [
			last_open, closed.get("distance", 0.0)])
	await _ticks(30)
	_finish(true)


## La distancia de los ojos a la parte más cercana del modelo de ese objeto
## (su caja): para caminar hasta un lugar al alcance.
func _eyes_to(uid: int) -> Callable:
	var view := net.world_view(uid)
	var box := view.interact_focus().bounds
	box.position += view.global_position
	return func(eyes: Vector3) -> float: return eyes.clamp(box.position, box.end).distance_to(eyes)


## Camina hasta quedar con los ojos a `REACH + margin` (según `measure`) de lo
## que hay en `anchor`, llegando por `away`, y se queda mirando `look_at`.
func _walk_near(measure: Callable, anchor: Vector3, away: Vector3, margin: float, look_at: Vector3) -> void:
	await _walk_spot(_eyes_feet(anchor, away, REACH + margin, measure), look_at)


## Camina hasta `goal` (los pies) y se queda mirando `look_at`.
func _walk_spot(goal: Vector3, look_at: Vector3) -> void:
	# Con internet mala, una corrección del host puede dejarlo lejos de la meta
	# después de llegar (pasa también sin recoger nada): vuelve a caminar.
	var arrived := false
	var tries := 0
	while tries < 3:
		tries += 1
		arrived = await _walk_to(goal, 0.12)
		await _ticks(20)
		if Vector2(actor.global_position.x - goal.x, actor.global_position.z - goal.z).length() < 0.3:
			break
	var flat := Vector3(look_at.x - actor.global_position.x, 0, look_at.z - actor.global_position.z)
	camera.yaw = atan2(-flat.x, -flat.z)
	await _ticks(5)
	_check(arrived and actor == lab._local_actor and Vector2(actor.global_position.x - goal.x, actor.global_position.z - goal.z).length() < 0.3,
			"camina hasta %s: %s en %d intentos, queda en %s (hasta acá, %d correcciones, la última de %.2f m)" % [
			goal.snapped(Vector3.ONE * 0.01), "llega" if arrived else "no llega", tries, actor.global_position.snapped(Vector3.ONE * 0.01),
			lab._prediction.corrections, lab._prediction.last_correction_meters])


## Camina hasta ahí con W, girando la cámara hacia el lugar, como un jugador.
func _walk_to(goal: Vector3, tolerance := 0.3) -> bool:
	var limit := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < limit:
		var me := lab._local_actor as ActorBody
		if me != null:
			var flat := Vector3(goal.x - me.global_position.x, 0.0, goal.z - me.global_position.z)
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


## El host, con un cliente de otro alcance o con otra granada: no lo deja entrar.
func _host_refuses() -> void:
	_check(await _until(func() -> bool: return net.authority != null and lab._local_actor != null, 15.0), "el host arranca")
	var entered := await _until(func() -> bool:
		return net.authority.welcomed_peers().any(func(peer: int) -> bool: return peer != multiplayer.get_unique_id()), 20.0)
	_check(not entered, "en 20 s no entró nadie: el cliente distinto queda afuera")
	_finish(true)


func _client_refused() -> void:
	var said := {"text": ""}
	lab._session.status_changed.connect(func(text: String) -> void:
		if text.contains("no te deja entrar"):
			said["text"] = text)
	_check(await _until(func() -> bool: return said["text"] != "", 15.0), "el host no deja entrar al cliente")
	var part := "los valores del Tuning" if role == "client_tuning" else "el inventario"
	_check(String(said["text"]).contains(part) and not net.replica.has_state,
			"porque su copia difiere en %s: %s" % [part, String(said["text"]).get_slice("\n", 0)])
	_finish(true)
