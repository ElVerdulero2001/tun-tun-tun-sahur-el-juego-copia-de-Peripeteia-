class_name InvBodies
extends Node3D

## Los objetos sueltos del mundo con física (desde el 2026-11-14): cuerpos en
## el host, copias en los clientes, y lo que viaja entre ellos. Es el nodo
## «ObjetosSueltos» de InvNet. Lo que es de cada objeto (su pila, quién lo
## sostiene, si está en el mundo) sigue siendo de InvAuthority, en el host, y
## de InvReplica, en cada máquina: acá está su cuerpo y su pose.
##
## **En el host** (y jugando solo):
##
## - Un InvWorldItem simulado por objeto del mundo. Lo crea y lo borra
##   InvAuthority al ponerlo o sacarlo del mundo (spawn, despawn).
## - Al empezar cada tick (on_tick_started) lee la pose de los que se mueven
##   (los despiertos, que avisa Jolt; los dormidos no se tocan) y la anota en
##   InvAuthority.world y en su InvItemSpace, con su historia, como del tick
##   anterior (Jolt los movió en el paso de física de ese tick).
## - Al terminar cada tick (on_tick_finished), con los personajes ya movidos,
##   lleva lo que sostiene cada uno: el punto agarrado va a los ojos del
##   personaje más la dirección de su cámara por la distancia pedida, con el
##   giro pedido relativo a su yaw (lo trae su input: ActorInput.hold). Si se
##   traba, si el personaje se aleja, muere o no está, lo suelta
##   (InvAuthority.auto_release).
## - Cada SNAPSHOT_TICKS manda a cada cliente, sin confiable, la pose de lo que
##   se movió, de lo que se acaba de dormir (varias veces, por si se pierde) y
##   de un dormido por vez, para corregir cualquier diferencia. Lo que entra,
##   sale, se agarra o se suelta va por el camino confiable del inventario
##   (los paquetes de InvAuthority), con su pose.
##
## **En un cliente:** una copia congelada por objeto, colocada en cada tick en
## la pose interpolada del tick del host que se muestra de los demás
## (RemoteInterpolation.shown_tick): los objetos y los otros jugadores se ven
## en el mismo instante. Lo que sostiene el jugador de esa máquina lo coloca
## InvHands, adelantado. `shown` es lo que ve esa máquina, con su índice: lo
## consulta el rayo de la mano.
##
## La cámara lenta frena a Jolt sola (Engine.time_scale): acá no se escala
## nada aparte. Al repetir ticks en un cliente no se simula nada: los objetos
## no tienen física ahí.

## Cada cuántos ticks sale un paquete de poses: como los snapshots de los
## personajes (NetSync.SNAPSHOT_INTERVAL_TICKS), 30 por segundo.
const SNAPSHOT_TICKS := 2
## Lo que se acaba de dormir se sigue mandando este tiempo, en ticks.
const SLEEP_TAIL_TICKS := 30
## Como mucho, cuántos objetos van en un paquete; si hay más, van en varios.
const PER_PACKET := 32
## Cuántas muestras se guardan de cada objeto en un cliente.
const MAX_SAMPLES := 24
## Más que esto entre dos muestras seguidas no se interpola: es un salto.
const JUMP_DISTANCE := 4.0
## Debajo de esto, un objeto se cayó del mapa: vuelve a donde reposó por última vez.
const FALL_LIMIT := -30.0
## Pasos de la cuantización del giro y de las velocidades en los paquetes.
const QUAT_STEPS := 32767.0
const VELOCITY_STEP := 0.01

var net: InvNet
## Solo en el host.
var authority: InvAuthority
var catalog: InvCatalog
var tuning: ActorTuning
## Cliente: el tick del host que se muestra (func() -> float). Lo pone el laboratorio.
var render_tick: Callable
## Lo que se ve en esta máquina, para el rayo (en el host, InvAuthority.space).
var shown := InvItemSpace.new()
## Para las pruebas y el panel: cuántas poses salieron y cuántas llegaron.
var poses_sent := 0
var poses_received := 0
var packets_sent := 0
var resets := 0

var _views := {}  # número -> InvWorldItem (los negativos: lo soltado sin confirmar)
var _awake := {}  # host: número -> true
var _changed := {}  # host: número -> true, desde el último paquete
var _slept := {}  # host: número -> tick en que se durmió
var _rest := {}  # host: número -> última pose en reposo
var _holds := {}  # host: número -> {"peer", "session", "anchor", "distance", "rotation", "pitch", "deaths", "stuck"}
var _hold_inputs := {}  # host: peer -> [ActorInput.hold, look_yaw]
var _refresh := 0  # host: por dónde va la ronda de los dormidos
var _last_tick := -1
var _paused := false
var _frozen := {}  # host, en pausa: número -> [velocidad, giro]
var _samples := {}  # cliente: número -> [[tick, Transform3D, velocidad, dormido, sostenido], ...]
var _moving := {}  # cliente: número -> true, los que todavía hay que interpolar
var _sleep_next := {}  # host: número -> true, a dormir en el próximo cuadro de física
var _born_asleep := {}  # host: número -> true, nació dormido y todavía no se despertó


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	shown.catalog = catalog


## Duerme a los que nacieron dormidos, en el primer cuadro de física después
## del que los creó (comprobado con Jolt 4.7.2: dormido antes, en el mismo
## cuadro, el primer paso lo despierta igual). Si se crearon en medio de un
## cuadro de física, ese paso ya los movió un poco (2,7 mm en el aire; apoyados,
## nada): su pose nueva se anota y sale una vez.
func _physics_process(_delta: float) -> void:
	if _sleep_next.is_empty():
		return
	var frame := Engine.get_physics_frames()
	for uid: int in _sleep_next.keys():
		if _sleep_next[uid] >= frame:
			continue
		_sleep_next.erase(uid)
		var body: InvWorldItem = _views.get(uid)
		if body == null or body.hold_active or not _born_asleep.has(uid):
			continue
		body.sleeping = true
		var item: Dictionary = authority.world.get(uid, {}) if authority != null else {}
		if not item.is_empty() and not (item["xf"] as Transform3D).is_equal_approx(body.global_transform):
			_read(uid, body, _last_tick)
			item["sleep"] = true
			_rest[uid] = body.global_transform
			_changed[uid] = true


func is_host() -> bool:
	return authority != null


## La vista (el cuerpo en el host, la copia en un cliente) de un objeto, o null.
func view(uid: int) -> InvWorldItem:
	return _views.get(uid)


func views() -> Dictionary:
	return _views


## Lo que consulta el rayo de la mano en esta máquina.
func selector_space() -> InvItemSpace:
	return authority.space if authority != null else shown


## Se olvida todo (al empezar o al cortarse la conexión).
func reset() -> void:
	for uid in _views.keys():
		_views[uid].queue_free()
	_views.clear()
	_awake.clear()
	_changed.clear()
	_slept.clear()
	_rest.clear()
	_holds.clear()
	_hold_inputs.clear()
	_samples.clear()
	_moving.clear()
	_frozen.clear()
	_sleep_next.clear()
	_born_asleep.clear()
	shown.clear()
	shown.catalog = catalog
	_last_tick = -1


# --- Host: cuerpos ---------------------------------------------------------------

## Host: arma el cuerpo de un objeto que InvAuthority acaba de poner en el
## mundo, con lo que dice su entrada (pose, velocidades, si duerme).
func spawn(uid: int) -> void:
	var item: Dictionary = authority.world.get(uid, {})
	if item.is_empty():
		return
	despawn(uid)
	var stack: InvStack = item["stack"]
	var body := InvWorldItem.new()
	body.name = "Objeto%d" % uid
	body.setup(catalog.find(stack.def_id), stack, item.get("label", true), true, tuning)
	# En su lugar, con su velocidad y dormido o no, antes de entrar al mundo
	# físico: moverlo o tocarle la velocidad después lo despertaría, y un objeto
	# colocado en el mapa tiene que quedar quieto donde está hasta que algo lo toque.
	body.transform = global_transform.affine_inverse() * (item["xf"] as Transform3D)
	body.linear_velocity = item.get("lv", Vector3.ZERO)
	body.angular_velocity = item.get("av", Vector3.ZERO)
	var asleep: bool = item.get("sleep", false)
	body.sleeping = asleep
	add_child(body)
	# Con Jolt (4.7.2), un cuerpo dormido al crearlo se despierta en su primer
	# paso de física igual (comprobado con cuerpos sueltos): se lo vuelve a
	# dormir en el cuadro de física siguiente, antes de ese paso (_physics_process).
	if asleep:
		_sleep_next[uid] = Engine.get_physics_frames()
		# Ya viaja con su pose en el paquete confiable: al dormirlo no hace falta
		# mandarlo varias veces por si se pierde (_on_sleep_changed).
		_born_asleep[uid] = true
	body.reset_physics_interpolation()
	body.sleeping_state_changed.connect(_on_sleep_changed.bind(uid))
	_views[uid] = body
	_rest[uid] = item["xf"]
	if not asleep:
		_awake[uid] = true
		_changed[uid] = true
	if _paused:
		_freeze(uid, body)


func despawn(uid: int) -> void:
	var body: InvWorldItem = _views.get(uid)
	if body != null:
		body.queue_free()
	_views.erase(uid)
	_awake.erase(uid)
	_changed.erase(uid)
	_slept.erase(uid)
	_rest.erase(uid)
	_holds.erase(uid)
	_frozen.erase(uid)
	_sleep_next.erase(uid)
	_born_asleep.erase(uid)


func _on_sleep_changed(uid: int) -> void:
	var body: InvWorldItem = _views.get(uid)
	if body == null:
		return
	if body.sleeping and not body.hold_active:
		# Godot no avisa cuando el sueño lo cambia uno (al crearlo, al agarrarlo):
		# uno que nació dormido y nunca se despertó no estuvo en _awake.
		var quiet := _born_asleep.has(uid) and not _awake.has(uid)
		_born_asleep.erase(uid)
		_awake.erase(uid)
		_rest[uid] = body.global_transform
		if quiet:
			return
		_slept[uid] = _last_tick
		_read(uid, body, _last_tick)
		_changed[uid] = true
	elif not _sleep_next.has(uid):
		# (Si todavía no se lo durmió, es el primer paso, que lo despierta igual.)
		_born_asleep.erase(uid)
		_awake[uid] = true


## Host: el cambio de cantidad o de cartel de un objeto que sigue en el mundo.
func refresh_view(uid: int) -> void:
	var item: Dictionary = authority.world.get(uid, {}) if authority != null else net.replica.world.get(uid, {})
	var body: InvWorldItem = _views.get(uid)
	if body != null and not item.is_empty():
		body.refresh(catalog.find((item["stack"] as InvStack).def_id), item["stack"])


## Pausa (jugando solo, G): los cuerpos se congelan donde están y al seguir
## recuperan su velocidad. Avanzar un tick en pausa (F) no los mueve.
func set_paused(on: bool) -> void:
	if on == _paused or authority == null:
		return
	_paused = on
	for uid: int in _views:
		if uid > 0:
			if on:
				_freeze(uid, _views[uid])
			elif _frozen.has(uid):
				var body: InvWorldItem = _views[uid]
				body.freeze = false
				body.linear_velocity = _frozen[uid][0]
				body.angular_velocity = _frozen[uid][1]
	if not on:
		_frozen.clear()


func _freeze(uid: int, body: InvWorldItem) -> void:
	_frozen[uid] = [body.linear_velocity, body.angular_velocity]
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true


## Host, al empezar el tick `tick`: lee la pose de lo que se movió en el paso
## de física del tick anterior.
func on_tick_started(tick: int) -> void:
	if authority == null:
		return
	_last_tick = tick - 1
	for uid: int in _awake.keys():
		var body: InvWorldItem = _views.get(uid)
		if body == null:
			_awake.erase(uid)
			continue
		if body.global_position.y < FALL_LIMIT:
			_reset_fallen(uid, body)
			continue
		_read(uid, body, tick - 1)
		_changed[uid] = true


func _read(uid: int, body: InvWorldItem, tick: int) -> void:
	var item: Dictionary = authority.world.get(uid, {})
	if item.is_empty():
		return
	var place := body.global_transform
	item["xf"] = place
	item["pos"] = place.origin
	item["lv"] = body.linear_velocity
	item["av"] = body.angular_velocity
	item["sleep"] = body.sleeping
	item["t"] = tick
	authority.space.move(uid, place, tick)
	# El jugador del host ve el mundo del host: su copia del mundo va igual.
	var mine: Dictionary = net.replica.world.get(uid, {})
	if not mine.is_empty():
		mine["xf"] = place
		mine["pos"] = place.origin


## Se cayó del mapa: vuelve, quieto, a donde reposó por última vez.
func _reset_fallen(uid: int, body: InvWorldItem) -> void:
	resets += 1
	if _holds.has(uid):
		authority.auto_release(uid, "se cayó del mapa")
	var back: Transform3D = _rest.get(uid, body.global_transform)
	body.global_transform = back
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.reset_physics_interpolation()
	body.sleeping = true
	# Dormido a mano: Godot no avisa (_on_sleep_changed), se anota acá.
	_awake.erase(uid)
	_slept[uid] = _last_tick
	_read(uid, body, _last_tick)
	_changed[uid] = true
	push_warning("[inventario] el objeto %d se cayó del mapa: volvió a %s" % [uid, back.origin])


## Host, al terminar el tick: lleva lo que se sostiene y, cada SNAPSHOT_TICKS,
## manda las poses.
func on_tick_finished(tick: int) -> void:
	if authority == null:
		return
	_carry(tick)
	if tick % SNAPSHOT_TICKS == 0:
		_send_poses(tick)


# --- Host: sostener ---------------------------------------------------------------

## Host: el input de un personaje en este tick (InvNet.use_before_step), con
## lo que pide su mano.
func hold_input(actor: ActorBody, input: ActorInput) -> void:
	if authority == null or actor == null:
		return
	_hold_inputs[actor.owner_peer_id] = [input.hold.duplicate(), input.look_yaw]


## Host: el yaw de la cámara del input más nuevo de ese jugador, o NAN.
func look_yaw_of(peer: int) -> float:
	var wanted: Array = _hold_inputs.get(peer, [])
	return wanted[1] if wanted.size() == 2 else NAN


## Host: `peer` empieza a sostener el objeto por `anchor` (en su espacio), a
## `distance` de los ojos y con `rotation` (su giro relativo al yaw de la
## cámara) hasta que su input diga otra cosa.
func begin_hold(uid: int, peer: int, session: int, anchor: Vector3, distance: float, turn: Quaternion,
		pitch: float) -> void:
	var body: InvWorldItem = _views.get(uid)
	if body == null:
		return
	if _frozen.has(uid):
		body.freeze = false
		_frozen.erase(uid)
	var actor := authority.actor_of(peer)
	_holds[uid] = {"peer": peer, "session": session, "anchor": anchor, "distance": distance, "rotation": turn,
			"pitch": pitch, "deaths": actor.state.deaths if actor != null else 0, "stuck": 0.0}
	body.begin_hold(anchor)
	_awake[uid] = true
	_changed[uid] = true


## Host: deja de sostenerlo. Con `impulse`, además, lo lanza (una vez).
func end_hold(uid: int, impulse := Vector3.ZERO) -> void:
	_holds.erase(uid)
	var body: InvWorldItem = _views.get(uid)
	if body == null:
		return
	body.end_hold()
	if impulse != Vector3.ZERO:
		body.apply_central_impulse(impulse)
	_awake[uid] = true
	_changed[uid] = true


func holds() -> Dictionary:
	return _holds


## Lo que se sostiene, con los personajes en este tick.
func _carry(tick: int) -> void:
	for uid: int in _holds.keys():
		var hold: Dictionary = _holds[uid]
		var body: InvWorldItem = _views.get(uid)
		var actor := authority.actor_of(hold["peer"])
		if body == null:
			_holds.erase(uid)
			continue
		if actor == null or not actor.is_inside_tree():
			authority.auto_release(uid, "tu personaje ya no está")
			continue
		if actor.state.deaths != hold["deaths"]:
			authority.auto_release(uid, "moriste")
			continue
		var wanted: Array = _hold_inputs.get(hold["peer"], [])
		var yaw: float = wanted[1] if wanted.size() == 2 else actor.state.facing_yaw
		var asked: Array = wanted[0] if wanted.size() == 2 else []
		if asked.size() == 7 and asked[0] == hold["session"]:
			var input := ActorInput.new()
			input.hold = asked
			hold["distance"] = input.hold_distance()
			hold["rotation"] = input.hold_rotation()
			hold["pitch"] = input.hold_pitch()
		var low := tuning.hold_min_distance if tuning != null else 0.6
		var high := tuning.hold_max_distance if tuning != null else 2.5
		var distance := clampf(hold["distance"], low, maxf(high, low))
		var eyes := InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state))
		var look := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, hold["pitch"]) * Vector3.FORWARD
		body.hold_target = eyes + look * distance
		body.hold_basis = Basis(Vector3.UP, yaw) * Basis(hold["rotation"] as Quaternion)
		var limit := tuning.hold_break_distance if tuning != null else 0.8
		var dt := SimClock.world_dt(tick)
		hold["stuck"] = hold["stuck"] + dt if body.hold_error > limit else 0.0
		var anchor_world := body.global_transform * (hold["anchor"] as Vector3)
		if hold["stuck"] > (tuning.hold_break_time if tuning != null else 0.5):
			authority.auto_release(uid, "se trabó")
		elif eyes.distance_to(anchor_world) > high + limit:
			authority.auto_release(uid, "quedó muy lejos")


# --- Host: lo que sale -----------------------------------------------------------

## Las poses que van en este paquete: lo que cambió, lo que se acaba de dormir
## y un dormido de la ronda.
func _send_poses(tick: int) -> void:
	var list: Array[int] = []
	for uid: int in _changed:
		if _views.has(uid):
			list.append(uid)
	_changed.clear()
	for uid: int in _slept.keys():
		if tick - _slept[uid] > SLEEP_TAIL_TICKS or not _views.has(uid):
			_slept.erase(uid)
		elif not uid in list:
			list.append(uid)
	var all := _views.keys().filter(func(uid: int) -> bool: return uid > 0)
	if not all.is_empty():
		all.sort()
		_refresh = (_refresh + 1) % all.size()
		var extra: int = all[_refresh]
		if not extra in list:
			list.append(extra)
	if list.is_empty() or net == null:
		return
	list.sort()
	for from in range(0, list.size(), PER_PACKET):
		var data := encode_poses(tick, list.slice(from, from + PER_PACKET))
		poses_sent += mini(PER_PACKET, list.size() - from)
		packets_sent += 1
		net.send_poses(data)


## Un paquete de poses: [tick del host (4), cuántos (2)] y por cada uno [número
## (4), si duerme y si alguien lo sostiene (1), lugar (3 × 4), giro (4 × 2),
## velocidad (3 × 2), velocidad de giro (3 × 2)]: 37 bytes por objeto.
func encode_poses(tick: int, uids: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(tick)
	b.put_u16(uids.size())
	for uid: int in uids:
		var item: Dictionary = authority.world.get(uid, {})
		var place: Transform3D = item.get("xf", Transform3D.IDENTITY)
		var q := place.basis.orthonormalized().get_rotation_quaternion()
		if q.w < 0.0:
			q = -q
		var linear: Vector3 = item.get("lv", Vector3.ZERO)
		var angular: Vector3 = item.get("av", Vector3.ZERO)
		b.put_u32(uid)
		b.put_u8((1 if item.get("sleep", false) else 0) | (2 if item.get("holder", 0) != 0 else 0))
		b.put_float(place.origin.x)
		b.put_float(place.origin.y)
		b.put_float(place.origin.z)
		for value in [q.x, q.y, q.z, q.w]:
			b.put_16(clampi(roundi(value * QUAT_STEPS), -32767, 32767))
		for value in [linear.x, linear.y, linear.z, angular.x, angular.y, angular.z]:
			b.put_16(clampi(roundi(value / VELOCITY_STEP), -32767, 32767))
	return b.data_array


# --- Cliente: lo que llega ---------------------------------------------------------

## Cliente: un paquete de poses del host. Lo que no tiene la forma esperada se
## descarta; lo que llega desordenado se acomoda por tick.
func accept_poses(data: PackedByteArray) -> void:
	if authority != null or data.size() < 6:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var tick := b.get_u32()
	var count := b.get_u16()
	if count > PER_PACKET or b.get_available_bytes() < count * 37:
		return
	for i in count:
		var uid := b.get_u32()
		var flags := b.get_u8()
		var origin := Vector3(b.get_float(), b.get_float(), b.get_float())
		var q := Quaternion(b.get_16() / QUAT_STEPS, b.get_16() / QUAT_STEPS, b.get_16() / QUAT_STEPS, b.get_16() / QUAT_STEPS)
		var linear := Vector3(b.get_16(), b.get_16(), b.get_16()) * VELOCITY_STEP
		var _angular := Vector3(b.get_16(), b.get_16(), b.get_16()) * VELOCITY_STEP
		if not origin.is_finite() or q.length_squared() < 0.25:
			continue
		poses_received += 1
		add_sample(uid, tick, Transform3D(Basis(q.normalized()), origin), linear, flags & 1 != 0, flags & 2 != 0)


## Cliente: una pose del host de ese objeto en ese tick (de un paquete de
## poses o de un paquete confiable del inventario). Va ordenada por tick; una
## repetida o muy vieja no cambia nada. `held`: en ese tick alguien lo sostenía.
func add_sample(uid: int, tick: int, place: Transform3D, linear: Vector3, asleep: bool, held := false) -> void:
	var list: Array = _samples.get_or_add(uid, [])
	var at := list.size()
	while at > 0 and list[at - 1][0] > tick:
		at -= 1
	if at > 0 and list[at - 1][0] == tick:
		list[at - 1] = [tick, place, linear, asleep, held]
	else:
		list.insert(at, [tick, place, linear, asleep, held])
	while list.size() > MAX_SAMPLES:
		list.pop_front()
	_moving[uid] = true
	var item: Dictionary = net.replica.world.get(uid, {})
	if not item.is_empty() and list[-1][0] == tick:
		item["xf"] = place
		item["pos"] = place.origin
		item["sleep"] = asleep


## Cliente: la pose de un objeto en el tick del host `at` (con decimales):
## entre las dos muestras que lo rodean; antes de la primera, la primera;
## después de la última, la última. [pose, salto (no interpolar)], o vacío si
## no hay ninguna.
func sample_at(uid: int, at: float) -> Array:
	var list: Array = _samples.get(uid, [])
	if list.is_empty():
		return []
	if at <= list[0][0]:
		return [list[0][1], false]
	for i in range(list.size() - 1, 0, -1):
		var from: Array = list[i - 1]
		if from[0] <= at:
			var to: Array = list[i]
			if at >= to[0]:
				return [to[1], false]
			var a: Transform3D = from[1]
			var b: Transform3D = to[1]
			if a.origin.distance_to(b.origin) > JUMP_DISTANCE:
				return [b if at - from[0] > (to[0] - from[0]) * 0.5 else a, true]
			var weight := clampf((at - from[0]) / maxf(to[0] - from[0], 0.0001), 0.0, 1.0)
			return [a.interpolate_with(b, weight), false]
	return [list[-1][1], false]


## Cliente: la muestra más nueva de un objeto: [tick, pose, velocidad, dormido,
## sostenido], o vacío.
func newest_sample(uid: int) -> Array:
	var list: Array = _samples.get(uid, [])
	return list[-1] if not list.is_empty() else []


## Cliente, en cada tick: coloca las copias en el tick del host que se
## muestra. Lo que sostiene el propio jugador lo coloca InvHands (`skip`).
func place_copies(skip := -1) -> void:
	if authority != null:
		return
	var at: float = render_tick.call() if render_tick.is_valid() else -1.0
	for uid: int in _moving.keys():
		var copy: InvWorldItem = _views.get(uid)
		var list: Array = _samples.get(uid, [])
		if copy == null or list.is_empty():
			if copy == null and not net.replica.world.has(uid):
				_moving.erase(uid)
				_samples.erase(uid)
			continue
		if uid == skip:
			continue
		var pose := sample_at(uid, at if at >= 0.0 else float(list[-1][0]))
		copy.place(pose[0], pose[1])
		shown.move(uid, pose[0])
		# Quieto del todo: ya llegó a la última muestra y esa dice que duerme.
		if at >= list[-1][0] and list[-1][3]:
			_moving.erase(uid)


# --- Lo que se ve ------------------------------------------------------------------

## Pone al día lo que se ve con lo que dice el inventario de esta máquina:
## lo confirmado por el host (menos lo que esta máquina ya recogió entero) y lo
## soltado sin confirmar, que se ve donde va a aparecer. En el host, los
## cuerpos ya están (los arma InvAuthority): acá solo se esconde lo recogido.
func sync_views(replica: InvReplica) -> void:
	var ghosts := {}
	for drop: Dictionary in replica.predicted_drops():
		ghosts[drop["key"]] = drop
	for uid: int in _views.keys():
		if uid < 0 and not ghosts.has(uid):
			_views[uid].queue_free()
			_views.erase(uid)
	for key: int in ghosts:
		var drop: Dictionary = ghosts[key]
		var ghost: InvWorldItem = _views.get(key)
		var place: Transform3D = drop.get("xf", Transform3D(Basis.IDENTITY, drop["pos"]))
		if ghost == null:
			ghost = InvWorldItem.new()
			ghost.name = "Soltando%d" % -key
			var stack: InvStack = drop["stack"]
			ghost.setup(catalog.find(stack.def_id), stack, true, false)
			add_child(ghost)
			_views[key] = ghost
			ghost.place(place, true)
		else:
			ghost.place(place)
	if authority != null:
		for uid: int in _views:
			if uid > 0:
				_views[uid].visible = not replica.is_taken(uid)
		return
	for uid: int in _views.keys():
		if uid > 0 and (not replica.world.has(uid) or replica.is_taken(uid)):
			_views[uid].queue_free()
			_views.erase(uid)
			shown.remove(uid)
	for uid: int in replica.world:
		if replica.is_taken(uid):
			continue
		var item: Dictionary = replica.world[uid]
		var stack: InvStack = item["stack"]
		var def := catalog.find(stack.def_id)
		var copy: InvWorldItem = _views.get(uid)
		if copy == null:
			copy = InvWorldItem.new()
			copy.name = "Objeto%d" % uid
			copy.setup(def, stack, item.get("label", true), false)
			add_child(copy)
			_views[uid] = copy
			var start: Array = sample_at(uid, render_tick.call() if render_tick.is_valid() else -1.0)
			var place: Transform3D = start[0] if not start.is_empty() else item.get("xf", Transform3D(Basis.IDENTITY, item["pos"]))
			copy.place(place, true)
			shown.put(uid, stack, place)
		else:
			copy.refresh(def, stack)
			shown.set_stack(uid, stack)
