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
##
## **Desde el 2026-11-15** (docs/net/prompt_claude_revision_objetos_fisicos.md):
##
## - **La mano** pone las velocidades de lo sostenido al terminar el tick, con
##   las cuentas de InvHoldMotion, antes del paso de Jolt de ese mismo tick.
## - **El instante de cada pose:** lo que se lee al empezar el tick T es lo que
##   quedó después del paso de física del tick T - 1, y así viaja: el paquete de
##   poses que sale al terminar el tick T dice T - 1 (hasta ese día decía T).
## - **Adopción de lo sostenido:** la máquina del jugador predice lo que
##   sostiene y manda, con el input de cada tick, cómo le quedó (ActorInput.
##   held_claim). Al empezar el tick T + 1, el host compara la afirmación del
##   tick T con su propio resultado del tick T y la adopta solo si es creíble
##   (_judge_claim: misma sesión y versión, velocidades posibles, cerca de lo
##   del host, sin haber tocado otro objeto, y con todo el recorrido libre). Si
##   no, se queda con lo suyo y sube la versión de esa sujeción: lo que la
##   máquina del jugador afirmó con la versión vieja ya no se adopta, y al ver
##   la versión nueva en las poses se corrige con lo del host.
## - **Soltar y lanzar** esperan al último tick en que el jugador lo sostuvo
##   (schedule_release).
## - **Despertar:** al sacar un objeto del mundo, los que se apoyaban en él se
##   despiertan (despawn con `wake_neighbors`, wake): Jolt no lo hace solo.

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
const QUAT_STEPS := InvHoldMotion.QUAT_STEPS
const VELOCITY_STEP := InvHoldMotion.VELOCITY_STEP
## Bytes por objeto en un paquete de poses.
const POSE_BYTES := 38

## La adopción de lo sostenido (elegido por Claude el 2026-11-15, ver
## _judge_claim). Menos que esto entre lo que afirma el cliente y lo del host
## (en el centro de masa y en el punto agarrado, en metros; en el giro, en
## grados; en las velocidades, en m/s y rad/s) es lo mismo: no se toca nada.
const SAME_POS := 0.0005
const SAME_ANGLE := 0.05
const SAME_SPEED := 0.02
## Lo más que puede diferir para adoptarlo: lo que cambia un input que llegó
## tarde girando rápido (unos 2 a 4 cm con el Tuning de fábrica), con margen.
const ADOPT_POS := 0.06
const ADOPT_ANGLE := 8.0
## La primera afirmación después de agarrar: la máquina del jugador empezó a
## llevarlo antes de que el host lo agarrara, así que puede estar más lejos.
const START_POS := 0.35
## Margen sobre los límites de la mano del Tuning para las velocidades y el
## movimiento de un tick: ×1,1 y esto (m/s o rad/s).
const LIMIT_SLACK := 0.1
## Cuántos ticks puede esperar un soltar (la máquina del jugador va adelantada).
const MAX_RELEASE_WAIT := 60
## Lo más largo que puede ser el camino por afirmaciones (_claim_path), en
## ticks: los inputs viajan de a INPUT_REDUNDANCY (6), así que uno que llegó
## tarde casi siempre llega en los siguientes.
const MAX_CHAIN := 8
## Cuánto se agranda la caja de un objeto que sale del mundo para buscar los
## que se apoyaban en él, en metros: lo que Jolt deja entre dos formas que se
## tocan, con margen.
const WAKE_MARGIN := 0.05
## Ticks sin acuerdo (sin afirmaciones que sirvan) después de los que el host
## sube la versión igual, para que la máquina del jugador se corrija (elegido
## por Claude el 2026-11-15: medio segundo, más que una ida y vuelta mala).
const STALE_TICKS := 30
## Los motivos de rechazo que suben la versión de la sujeción.
const BUMPS := ["tocó otro objeto", "valores imposibles", "muy lejos", "movimiento imposible", "se mete"]
## Cuántas veces se escribe en la consola cada motivo de rechazo, por jugador.
const LOG_EACH := 3
## El rescate de lo que Jolt duerme metido en el nivel (_unstick): hasta dónde
## se lo busca sacar y cuántas veces por objeto (elegido por Claude el 2026-11-15).
const UNSTICK_MAX := 0.1
const UNSTICK_TRIES := 3
## Lo que se acepta de más sobre la tolerancia de Jolt antes de rescatar, y lo
## metido que puede quedar después de sacarlo, en metros.
const UNSTICK_MARGIN := 0.005

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
## Host: lo que afirma el jugador de lo que sostiene en un tick
## (func(peer, tick) -> PackedByteArray: NetSync.held_claim_for). Lo pone el
## laboratorio; sin él, el host se queda siempre con lo suyo.
var claim_source: Callable
## Host: si adopta lo que afirman los clientes de lo que sostienen (F2 apaga la
## adopción del personaje y esta a la vez).
var adoption_enabled := true
## Host: por jugador, cuántas afirmaciones de lo sostenido tuvieron cada
## resultado (_judge_claim) y "max", la diferencia más grande adoptada (m).
var adoption := {}
## Host: cuántos objetos se despertaron por perder el apoyo.
var wakes := 0
## Cliente, para las pruebas: cuántos objetos que sacó el host se siguieron
## dibujando hasta su tick, y cuántos que recogió esta máquina esperaron al
## host porque algo se apoyaba en ellos (_waits_for_fall).
var held_back := 0
var pickups_waited := 0
## Host: cuántos objetos dormidos metidos en el nivel se sacaron (_unstick).
var unstuck := 0

var _views := {}  # número -> InvWorldItem (los negativos: lo soltado sin confirmar)
var _awake := {}  # host: número -> true
var _changed := {}  # host: número -> true, desde el último paquete
var _slept := {}  # host: número -> tick en que se durmió
var _rest := {}  # host: número -> última pose en reposo
var _holds := {}  # host: número -> {"peer", "session", "anchor", "distance", "rotation", "pitch", "deaths", "stuck", "hidden",
		# "version", "fresh", "prev" (pose después del tick anterior), "goal" (el target de este tick), "since",
		# "checkpoint" ([tick, pose] de la última coincidencia o corrección),
		# "release_at" e "impulse" (un soltar que espera)}
var _logged := {}  # host: "jugador motivo" -> veces escritas
var _unstuck := {}  # host: número -> veces que se lo sacó del nivel
var _hold_inputs := {}  # host: peer -> [ActorInput.hold, look_yaw]
var _refresh := 0  # host: por dónde va la ronda de los dormidos
var _last_tick := -1
var _paused := false
var _frozen := {}  # host, en pausa: número -> [velocidad, giro]
var _samples := {}  # cliente: número -> [[tick, Transform3D, velocidad, dormido, sostenido], ...]
var _moving := {}  # cliente: número -> true, los que todavía hay que interpolar
var _leaving := {}  # cliente: número -> tick del host en que se deja de dibujar (INF: esperando al host)
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
	_leaving.clear()
	_frozen.clear()
	_sleep_next.clear()
	_born_asleep.clear()
	_unstuck.clear()
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


## Host: saca el cuerpo de un objeto. Con `wake_neighbors` (InvAuthority, al
## sacarlo del mundo de verdad: recogido con E), antes despierta a los que
## podían apoyarse en él (_wake_around), mientras todavía está en el índice. El
## cuerpo sale del mundo físico en el acto (no al final del cuadro), así en el
## próximo paso de Jolt ya no sostiene a nadie y lo de arriba empieza a caer.
## Recoger una parte de una pila no llama a esto: el cuerpo sigue.
func despawn(uid: int, wake_neighbors := false) -> void:
	var body: InvWorldItem = _views.get(uid)
	if body != null:
		if wake_neighbors and authority != null and body.simulated:
			_wake_around(uid, body)
		if body.get_parent() == self:
			remove_child(body)
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
	_unstuck.erase(uid)


## Host: despierta a los objetos cuyo cuerpo toca la caja del de `uid`
## agrandada WAKE_MARGIN: los busca en el índice del rayo (la caja de cada uno
## ya está anotada ahí) y mira su caja de verdad. Alguno de más se despierta y
## se vuelve a dormir solo; no se despierta nada lejos.
func _wake_around(uid: int, body: InvWorldItem) -> void:
	var box := (body.global_transform * InvItemPhysics.body_bounds(body.def)).grow(WAKE_MARGIN)
	for other: int in authority.space.index.near(box):
		if other == uid:
			continue
		var near_body: InvWorldItem = _views.get(other)
		if near_body == null or not near_body.simulated or near_body.hold_active:
			continue
		if (near_body.global_transform * InvItemPhysics.body_bounds(near_body.def)).intersects(box):
			wake(other)


## Host: despierta un objeto (el único lugar donde se despierta uno a mano).
## Cambiar `sleeping` no hace que Godot avise (sleeping_state_changed), así que
## acá se pone al día todo lo que dependía de eso: que se lea su pose en cada
## tick y salga en los paquetes (_awake, _changed), que su entrada del mundo ya
## no diga que duerme, y que no lo vuelva a dormir el arreglo de lo que nació
## dormido (_sleep_next, _born_asleep). Cuando Jolt lo duerma de nuevo, Godot sí
## avisa (_on_sleep_changed). En pausa queda congelado hasta seguir.
func wake(uid: int) -> void:
	var body: InvWorldItem = _views.get(uid)
	if authority == null or body == null or not body.simulated:
		return
	_sleep_next.erase(uid)
	_born_asleep.erase(uid)
	_slept.erase(uid)
	if not _frozen.has(uid):
		body.sleeping = false
	_awake[uid] = true
	_changed[uid] = true
	var item: Dictionary = authority.world.get(uid, {})
	if not item.is_empty():
		item["sleep"] = false
	wakes += 1


## Host: si Jolt durmió un objeto metido en el nivel más que su tolerancia de
## penetración (2 mm en project.godot; 2 cm de fábrica) y UNSTICK_MARGIN (con
## una forma convexa fina, como la llave, soltada contra una pared, quedaba 4 cm
## adentro del piso; medido el 2026-11-15, con la caja del mismo tamaño no
## pasa), lo saca por el camino más corto (de a 1 cm, hasta UNSTICK_MAX, para
## arriba, a los costados o para abajo) y lo despierta, para que caiga y se
## apoye bien. Como mucho UNSTICK_TRIES veces por objeto. Devuelve si lo sacó.
func _unstick(uid: int, body: InvWorldItem) -> bool:
	var space := body.get_world_3d().direct_space_state
	var place := body.global_transform
	# Lo que Jolt deja meterse a propósito (su tolerancia de penetración) no se
	# toca: debajo de eso no lo corrige él tampoco, y sacarlo solo haría que
	# vuelva a caer igual.
	var allowed := float(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/penetration_slop", 0.02)) + UNSTICK_MARGIN
	if _penetration(space, body, place) <= allowed:
		return false
	var tries: int = _unstuck.get(uid, 0)
	if tries >= UNSTICK_TRIES:
		return false
	_unstuck[uid] = tries + 1
	for step in range(1, roundi(UNSTICK_MAX / 0.01) + 1):
		for direction: Vector3 in [Vector3.UP, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]:
			var moved := place.translated(direction * step * 0.01)
			if _penetration(space, body, moved) <= UNSTICK_MARGIN:
				body.global_transform = moved
				body.linear_velocity = Vector3.ZERO
				body.angular_velocity = Vector3.ZERO
				body.reset_physics_interpolation()
				wake(uid)
				unstuck += 1
				if unstuck <= LOG_EACH:
					print("[inventario] el objeto %d (%s, en %s) quedó dormido metido en %s: el host lo sacó %d cm%s" % [uid,
							str(body.def.id) if body.def != null else "?", place.origin.snapped(Vector3.ONE * 0.01), _touching_name(space, body, place), step,
							" (no se vuelve a escribir)" if unstuck == LOG_EACH else ""])
				return true
	return false


## Cuánto está metido un objeto en el nivel en `place`, en metros.
func _penetration(space: PhysicsDirectSpaceState3D, body: InvWorldItem, place: Transform3D) -> float:
	return InvItemPhysics.depth(space, body.def, place, InvAuthority.WORLD_MASK)


## Con qué del nivel se mete un objeto en `place` (para la consola).
func _touching_name(space: PhysicsDirectSpaceState3D, body: InvWorldItem, place: Transform3D) -> String:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = InvAuthority.WORLD_MASK
	query.margin = 0.0
	for part: Array in InvItemPhysics.inset_parts(body.def):
		query.shape = part[0]
		query.transform = place * (part[1] as Transform3D)
		for hit: Dictionary in space.intersect_shape(query, 1):
			var node := hit.get("collider") as Node
			return str(node.get_path()) if node != null else "el nivel"
	return "el nivel"


func _on_sleep_changed(uid: int) -> void:
	var body: InvWorldItem = _views.get(uid)
	if body == null:
		return
	if body.sleeping and not body.hold_active and _unstick(uid, body):
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


## Host, al empezar el tick `tick`: lo sostenido (lo que afirma su jugador del
## tick anterior y los soltar que esperaban ese tick) y la pose de lo que se
## movió en el paso de física del tick anterior.
func on_tick_started(tick: int) -> void:
	if authority == null:
		return
	_last_tick = tick - 1
	_judge_holds(tick - 1)
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
## cámara) hasta que su input diga otra cosa. `since`: el tick en que lo agarró
## en su máquina (para la consola).
func begin_hold(uid: int, peer: int, session: int, anchor: Vector3, distance: float, turn: Quaternion,
		pitch: float, since := -1) -> void:
	var body: InvWorldItem = _views.get(uid)
	if body == null:
		return
	if _frozen.has(uid):
		body.freeze = false
		_frozen.erase(uid)
	var actor := authority.actor_of(peer)
	_sleep_next.erase(uid)
	_born_asleep.erase(uid)
	_holds[uid] = {"peer": peer, "session": session, "anchor": anchor, "distance": distance, "rotation": turn,
			"pitch": pitch, "deaths": actor.state.deaths if actor != null else 0, "stuck": 0.0, "hidden": 0.0, "version": 0, "fresh": true,
			"prev": body.global_transform, "since": since, "bumped": _last_tick,
			"checkpoint": [_last_tick, body.global_transform]}
	body.begin_hold(anchor)
	_awake[uid] = true
	_changed[uid] = true


## Host: un soltar o lanzar que pidió el jugador después de sostenerlo en el
## tick `last_tick` (InvProtocol.release_args). Si ese tick todavía no se
## simuló, lo sigue llevando hasta entonces y lo suelta al empezar el tick
## siguiente, después de considerar lo que afirmó el jugador de ese tick: true.
## Si ya se simuló (o el tick no es creíble), false: se suelta ya.
func schedule_release(uid: int, last_tick: int, impulse: Vector3) -> bool:
	var hold: Dictionary = _holds.get(uid, {})
	if hold.is_empty() or last_tick <= _last_tick or last_tick > _last_tick + MAX_RELEASE_WAIT:
		return false
	hold["release_at"] = last_tick
	hold["impulse"] = impulse
	return true


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


## Host: en una línea, lo que pasó con lo que afirmó ese jugador de lo que
## sostiene (para el panel y los resúmenes de las pruebas), o "" si nada.
func adoption_text(peer: int) -> String:
	var stats: Dictionary = adoption.get(peer, {})
	if stats.is_empty():
		return ""
	var parts := PackedStringArray()
	for key: String in ["adoptada", "igual", "sin afirmación", "otra sesión", "versión vieja", "apagada", "sin acuerdo"] + BUMPS:
		if stats.get(key, 0) > 0:
			parts.append("%s %d" % [key, stats[key]])
	return "%s (la adoptada más lejana a %.3f m)" % [", ".join(parts), stats.get("max", 0.0)]


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
		var high := maxf(tuning.hold_max_distance if tuning != null else 2.5, tuning.hold_min_distance if tuning != null else 0.6)
		var eyes := InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state))
		var goal := InvHoldMotion.target(eyes, yaw, hold["pitch"], hold["distance"], hold["rotation"], tuning)
		hold["goal"] = goal
		body.hold_target = goal.origin
		body.hold_basis = goal.basis
		var dt := SimClock.world_dt(tick)
		if not _frozen.has(uid):
			# Las mismas cuentas que predice la máquina del jugador, antes del paso de
			# Jolt de este tick (desde el 2026-11-15; ver InvHoldMotion).
			var com := InvItemPhysics.center_of_mass(body.def)
			var speeds := InvHoldMotion.velocities(body.global_transform, com, body.linear_velocity, body.angular_velocity,
					hold["anchor"], goal, tuning, dt)
			var step := InvHoldMotion.guard(body.get_world_3d().direct_space_state, body.def, body.global_transform, com, speeds[0],
					speeds[1], dt, InvAuthority.WORLD_MASK, [body.get_rid()])
			body.linear_velocity = step[0]
			body.angular_velocity = step[1]
		var limit := tuning.hold_break_distance if tuning != null else 0.8
		var break_time := tuning.hold_break_time if tuning != null else 0.5
		hold["stuck"] = hold["stuck"] + dt if body.hold_error > limit else 0.0
		# Tapado por el nivel (desde el 2026-11-15, pedido por el usuario): el punto
		# agarrado no se ve desde los ojos (InvReach.held_visible), con la pose de
		# después del tick anterior, la misma que usa la mano. Lo del jugador del
		# host se suelta a los Hold Hidden Time (de fábrica, en el primer tick).
		# Lo de un cliente lo suelta su máquina (InvHands._check_hidden) con un
		# soltar común; acá se espera además Hold Break Time, por si no lo hizo
		# (su predicción no lo veía tapado, o se cortó).
		var seen := InvReach.held_visible(body.get_world_3d().direct_space_state, eyes, body.def, body.global_transform,
				hold["anchor"])
		hold["hidden"] = 0.0 if seen else float(hold.get("hidden", 0.0)) + dt
		var hidden_time := tuning.hold_hidden_time if tuning != null else 0.0
		if hold["peer"] != multiplayer.get_unique_id():
			hidden_time = maxf(hidden_time, break_time)
		var anchor_world := body.global_transform * (hold["anchor"] as Vector3)
		if hold["stuck"] > break_time:
			authority.auto_release(uid, "se trabó")
		elif eyes.distance_to(anchor_world) > high + limit:
			authority.auto_release(uid, "quedó muy lejos")
		elif hold["hidden"] > hidden_time:
			authority.auto_release(uid, "no se ve")


## Host, al empezar el tick siguiente a `stepped` (ya dado su paso de Jolt):
## cuánto le faltó a cada sostenido para llegar a su target, lo que afirma su
## jugador de ese tick (_judge_claim), la pose de partida para el tick que
## viene y los soltar que esperaban ese tick.
func _judge_holds(stepped: int) -> void:
	for uid: int in _holds.keys():
		var hold: Dictionary = _holds[uid]
		var body: InvWorldItem = _views.get(uid)
		if body == null:
			continue
		if hold.has("goal"):
			body.hold_error = (body.global_transform * (hold["anchor"] as Vector3)).distance_to((hold["goal"] as Transform3D).origin)
		if hold["peer"] == multiplayer.get_unique_id():
			# El jugador del host no afirma nada: lo suyo es el cuerpo de verdad.
			hold["prev"] = body.global_transform
			if int(hold.get("release_at", -1)) >= 0 and stepped >= int(hold["release_at"]):
				authority.finish_release(uid, hold.get("impulse", Vector3.ZERO), true)
			continue
		if body.contact_monitor and body.get_colliding_bodies().any(func(other: Node) -> bool: return other is RigidBody3D):
			hold["touched"] = stepped
		var result := _judge_claim(uid, hold, body, stepped)
		var checkpoint: Array = hold["checkpoint"]
		if result != "adoptada" and result != "igual" and not result in BUMPS \
				and stepped - maxi(int(checkpoint[0]), int(hold.get("bumped", -1))) > STALE_TICKS:
			# Sin acuerdo hace rato (las afirmaciones no llegan, o son de otra
			# versión): con la misma versión la máquina del jugador no se corrige,
			# así que se le avisa subiéndola.
			result = "sin acuerdo"
		var stats: Dictionary = adoption.get_or_add(hold["peer"], {"max": 0.0})
		stats[result] = stats.get(result, 0) + 1
		if result == "adoptada" or result == "igual":
			hold["checkpoint"] = [stepped, body.global_transform]
		if result in BUMPS or result == "sin acuerdo":
			hold["version"] = (int(hold["version"]) + 1) & 0xFF
			hold["bumped"] = stepped
			# La nueva versión obliga al cliente a partir de esta respuesta física.
			# Es también el comienzo de su nuevo camino: un contacto anterior ya
			# está incorporado. Conservar el acuerdo de la versión vieja rechazaba
			# indefinidamente por aquel choque, aun después de alejarse del objeto.
			hold["checkpoint"] = [stepped, body.global_transform]
			_changed[uid] = true
			var key := "%d %s" % [hold["peer"], result]
			var times: int = _logged.get(key, 0)
			if times < LOG_EACH:
				_logged[key] = times + 1
				print("[inventario] no se adoptó lo que afirma el jugador %d del objeto %d en el tick %d: %s (versión %d)%s" % [
						hold["peer"], uid, stepped, result, hold["version"], " (no se vuelve a escribir)" if times + 1 == LOG_EACH else ""])
		hold["prev"] = body.global_transform
		if int(hold.get("release_at", -1)) >= 0 and stepped >= int(hold["release_at"]):
			authority.finish_release(uid, hold.get("impulse", Vector3.ZERO), true)


## Si el host adopta lo que afirma el jugador que lo sostiene de cómo quedó el
## objeto después del tick `stepped`, y si sí, lo adopta. Devuelve el resultado:
##
## - "sin afirmación": no llegó (o el jugador es el del host);
## - "otra sesión" / "versión vieja": de otro agarre, o de antes de la última
##   corrección del host (no cuenta: ya se corrigió);
## - "igual": casi lo mismo que lo del host (SAME_*): no se toca nada;
## - "apagada": la adopción está apagada (F2);
## - "tocó otro objeto": desde la última coincidencia o corrección tocó otro cuerpo
##   que se mueve (los objetos sueltos, otro sostenido): el host
##   tiene la respuesta del choque, y adoptar la borraría en este y la dejaría
##   en el otro;
## - "valores imposibles": velocidades más altas que los límites de la mano;
## - "muy lejos": más de ADOPT_POS o ADOPT_ANGLE de lo del host por cada tick del
##   camino (START_POS en la primera, que puede ir adelantada);
## - "movimiento imposible": en algún tick del camino (_claim_path: desde la
##   última coincidencia o corrección, por lo afirmado de cada tick) hay más de lo que
##   la mano mueve o gira en un tick;
## - "se mete": en algún punto del recorrido (al moverse o al girar, en pasos de
##   1 cm) se mete en el nivel, una caja, una escalera u otro objeto, con las
##   formas achicadas INSET (InvHoldMotion.path_free: si ya arrancaba metido,
##   que no se meta más);
## - "sin acuerdo" (lo pone _judge_holds, no esta función): STALE_TICKS sin
##   adoptar ni coincidir, sin un rechazo que haya subido la versión: la sube;
## - "adoptada": queda en la pose y con las velocidades que afirmó. No se lo
##   teletransporta a ciegas: el lugar está libre y el camino también, así Jolt
##   no tiene nada que separar (no hay impulso), y es una diferencia acotada.
func _judge_claim(uid: int, hold: Dictionary, body: InvWorldItem, stepped: int) -> String:
	if not claim_source.is_valid():
		return "sin afirmación"
	var data: PackedByteArray = claim_source.call(hold["peer"], stepped)
	if data.is_empty():
		return "sin afirmación"
	var claim := InvHoldMotion.unpack_claim(data)
	if claim.is_empty():
		return "valores imposibles"
	if claim["uid"] != uid or claim["session"] != hold["session"]:
		return "otra sesión"
	if claim["version"] != hold["version"]:
		return "versión vieja"
	var fresh: bool = hold.get("fresh", false)
	hold["fresh"] = false
	var def := body.def
	var com := InvItemPhysics.center_of_mass(def)
	var here := body.global_transform
	var claimed: Transform3D = claim["xf"]
	var diff := InvHoldMotion.difference(claimed, here, com, hold["anchor"])
	if diff[0] <= SAME_POS and diff[1] <= SAME_ANGLE and (claim["lv"] as Vector3).distance_to(body.linear_velocity) <= SAME_SPEED \
			and (claim["av"] as Vector3).distance_to(body.angular_velocity) <= SAME_SPEED:
		return "igual"
	if not adoption_enabled:
		return "apagada"
	var checkpoint: Array = hold["checkpoint"]
	if int(hold.get("touched", -1)) > int(checkpoint[0]):
		return "tocó otro objeto"
	var move_limit := (tuning.hold_move_limit if tuning != null else 12.0) * 1.1 + LIMIT_SLACK
	var turn_limit := deg_to_rad(tuning.hold_turn_limit if tuning != null else 720.0) * 1.1 + LIMIT_SLACK
	if (claim["lv"] as Vector3).length() > move_limit or (claim["av"] as Vector3).length() > turn_limit:
		return "valores imposibles"
	# El camino: desde la última coincidencia o corrección del host,
	# por lo que afirmó el jugador de cada tick hasta este. Normalmente es un solo
	# tick (desde lo del host en el anterior); si un input llegó tarde, el host
	# simuló ese tick con el anterior y quedó corrido, y el camino va por las
	# afirmaciones de esos ticks, que llegaron después (cada input viaja varias
	# veces). Si falta alguna, desde lo del host en el tick anterior.
	var path := _claim_path(hold, checkpoint, stepped, uid)
	path.append(claimed)
	var ticks := path.size() - 1
	var far := START_POS if fresh else minf(ADOPT_POS * ticks, START_POS)
	if diff[0] > far or (not fresh and diff[1] > minf(ADOPT_ANGLE * ticks, 30.0)):
		return "muy lejos"
	var space := body.get_world_3d().direct_space_state
	for i in ticks:
		if not fresh:
			var dt := SimClock.world_dt(stepped - ticks + 1 + i)
			var moved := InvHoldMotion.difference(path[i], path[i + 1], com, com)
			if moved[0] > move_limit * dt + 0.002 or deg_to_rad(moved[1]) > turn_limit * dt + 0.002:
				return "movimiento imposible"
		if not InvHoldMotion.path_free(space, def, path[i], path[i + 1], InvItemPhysics.MASK, [body.get_rid()]):
			return "se mete"
	body.global_transform = claimed
	body.linear_velocity = claim["lv"]
	body.angular_velocity = claim["av"]
	var stats: Dictionary = adoption.get_or_add(hold["peer"], {"max": 0.0})
	stats["max"] = maxf(stats["max"], diff[0])
	return "adoptada"



## El comienzo del camino de una afirmación del tick `stepped` (_judge_claim):
## [la pose de la última coincidencia o corrección, lo afirmado en cada tick de ahí hasta el
## anterior a `stepped`], si están todas y son de esta sujeción y su versión, y
## son a lo sumo MAX_CHAIN ticks; si no, [lo del host en el tick anterior].
func _claim_path(hold: Dictionary, checkpoint: Array, stepped: int, uid: int) -> Array:
	var prev: Transform3D = hold.get("prev", checkpoint[1])
	var from_tick: int = checkpoint[0]
	if from_tick >= stepped - 1 or stepped - from_tick > MAX_CHAIN:
		return [prev]
	var path: Array = [checkpoint[1]]
	for t in range(from_tick + 1, stepped):
		var claim := InvHoldMotion.unpack_claim(claim_source.call(hold["peer"], t))
		if claim.is_empty() or claim["uid"] != uid or claim["session"] != hold["session"] or claim["version"] != hold["version"]:
			return [prev]
		path.append(claim["xf"])
	return path

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
		# Las poses son las que se leyeron al empezar este tick: las de después
		# del paso de física del tick anterior (desde el 2026-11-15; hasta ese día
		# salían con el número de este tick).
		var data := encode_poses(tick - 1, list.slice(from, from + PER_PACKET))
		poses_sent += mini(PER_PACKET, list.size() - from)
		packets_sent += 1
		net.send_poses(data)


## Un paquete de poses: [tick del host de esas poses (4), cuántos (2)] y por
## cada uno [número (4), si duerme y si alguien lo sostiene (1), la versión de
## la sujeción (1; 0 si nadie lo sostiene), lugar (3 × 4), giro (4 × 2),
## velocidad (3 × 2), velocidad de giro (3 × 2)]: POSE_BYTES por objeto.
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
		b.put_u8(int(_holds[uid]["version"]) & 0xFF if _holds.has(uid) else 0)
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
	if count > PER_PACKET or b.get_available_bytes() < count * POSE_BYTES:
		return
	for i in count:
		var uid := b.get_u32()
		var flags := b.get_u8()
		var version := b.get_u8()
		var origin := Vector3(b.get_float(), b.get_float(), b.get_float())
		var q := Quaternion(b.get_16() / QUAT_STEPS, b.get_16() / QUAT_STEPS, b.get_16() / QUAT_STEPS, b.get_16() / QUAT_STEPS)
		var linear := Vector3(b.get_16(), b.get_16(), b.get_16()) * VELOCITY_STEP
		var angular := Vector3(b.get_16(), b.get_16(), b.get_16()) * VELOCITY_STEP
		if not origin.is_finite() or q.length_squared() < 0.25:
			continue
		poses_received += 1
		add_sample(uid, tick, Transform3D(Basis(q.normalized()), origin), linear, flags & 1 != 0, flags & 2 != 0, angular,
				version)


## Cliente: una pose del host de ese objeto en ese tick (de un paquete de
## poses o de un paquete confiable del inventario). Va ordenada por tick; una
## repetida o muy vieja no cambia nada. `held`: en ese tick alguien lo sostenía,
## con esa `version` de la sujeción (la de los paquetes de poses; -1 si no se sabe).
func add_sample(uid: int, tick: int, place: Transform3D, linear: Vector3, asleep: bool, held := false,
		angular := Vector3.ZERO, version := -1) -> void:
	var list: Array = _samples.get_or_add(uid, [])
	var at := list.size()
	while at > 0 and list[at - 1][0] > tick:
		at -= 1
	var sample := [tick, place, linear, asleep, held, angular, version]
	if at > 0 and at == list.size() and list[at - 1][3] and not asleep and tick - int(list[at - 1][0]) > 1:
		# Se despertó: lo que dormía no recibe poses (salvo un repaso cada tanto),
		# así que la última puede ser de hace mucho. Sigue quieto ahí hasta el tick
		# anterior a esta; si no, se interpolaba desde esa pose vieja y empezaba a
		# moverse antes de tiempo (desde la segunda prueba del usuario, 2026-11-15).
		var rest: Array = list[at - 1]
		list.insert(at, [tick - 1, rest[1], Vector3.ZERO, true, rest[4], Vector3.ZERO, rest[6]])
		at += 1
	if at > 0 and list[at - 1][0] == tick:
		list[at - 1] = sample
	else:
		list.insert(at, sample)
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
	# Lo que salió del mundo se deja de dibujar al llegar al tick en que salió
	# (_waits_for_fall).
	for uid: int in _leaving.keys():
		if at >= float(_leaving[uid]):
			_leaving.erase(uid)
			if _views.has(uid) and (not net.replica.world.has(uid) or net.replica.is_taken(uid)):
				_free_view(uid)


## Cliente: deja de dibujar un objeto del mundo.
func _free_view(uid: int) -> void:
	_leaving.erase(uid)
	var copy: InvWorldItem = _views.get(uid)
	if copy != null:
		copy.queue_free()
	_views.erase(uid)
	shown.remove(uid)


## Cliente: si un objeto que ya no está en el mundo, o que esta máquina
## recogió, se sigue dibujando un rato (true) o se deja de dibujar ya (false).
## Los objetos sueltos se dibujan unos ticks en el pasado (render_tick, unos
## 100 ms), y lo que el host sacaba se borraba apenas llegaba el aviso: lo que
## se apoyaba en él quedaba en el aire hasta que llegaba su caída (segunda
## prueba del usuario, 2026-11-15, con una torre). Desde ese día:
##
## - Lo sacó el host (lo recogió otro jugador, o esta máquina y el host ya
##   contestó): se sigue dibujando, sin poder mirarlo, hasta que lo que se
##   muestra llega al tick en que salió (InvReplica.gone_ticks), el mismo en
##   que empieza la caída de lo de arriba. Sin ese tick, se va ya.
## - Lo recogió esta máquina y el host todavía no contestó: si algo se apoya en
##   él o lo toca (_has_neighbors: lo mismo que despierta el host al sacarlo),
##   se espera la respuesta y después su tick, como arriba; si no, se va en el
##   acto, como desde el 2026-11-04. Lo eligió el usuario ese día: lo de abajo
##   de una torre se va junto con la caída (medido: 0,22 s después de apretar E
##   sin red simulada, 0,44 s con internet mala); el inventario igual se pone
##   al día en el acto.
func _waits_for_fall(uid: int, gone: bool, gone_tick: int) -> bool:
	var at: float = render_tick.call() if render_tick.is_valid() else -1.0
	if at < 0.0:
		return false
	if gone:
		if gone_tick < 0 or at >= float(gone_tick):
			return false
		_leaving[uid] = float(gone_tick)
		shown.remove(uid)
		held_back += 1
		return true
	if _leaving.has(uid):
		return true
	if not _has_neighbors(uid):
		return false
	_leaving[uid] = INF
	pickups_waited += 1
	return true


## Cliente: si otro objeto suelto toca la caja de este, agrandada WAKE_MARGIN,
## tal como se dibujan acá: los que el host despierta al sacarlo (_wake_around).
func _has_neighbors(uid: int) -> bool:
	var copy: InvWorldItem = _views.get(uid)
	if copy == null or copy.def == null:
		return false
	var box := (copy.global_transform * InvItemPhysics.body_bounds(copy.def)).grow(WAKE_MARGIN)
	for other: int in shown.index.near(box):
		var near_copy: InvWorldItem = _views.get(other)
		if other == uid or near_copy == null or near_copy.def == null:
			continue
		if (near_copy.global_transform * InvItemPhysics.body_bounds(near_copy.def)).intersects(box):
			return true
	return false


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
		if uid <= 0:
			continue
		var gone := not replica.world.has(uid)
		if not gone and not replica.is_taken(uid):
			_leaving.erase(uid)
			continue
		if not _waits_for_fall(uid, gone, replica.gone_ticks.get(uid, -1)):
			_free_view(uid)
	replica.gone_ticks.clear()
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
