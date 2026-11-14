class_name InvNet
extends Node3D

## El inventario en red. Usa la misma conexión del laboratorio y pasa por el
## mismo simulador de red (LinkSimulator), como NetSync, con mensajes propios:
##
## - El cliente manda pedidos numerados (InvProtocol). El host los ordena por
##   número, descarta los repetidos (les vuelve a mandar el resultado) y los
##   procesa en fila, uno por uno, en InvAuthority.
## - El host manda a cada jugador paquetes numerados con lo que cambió. El
##   cliente los aplica en orden en su InvReplica: el simulador de red puede
##   cambiarles el orden, el número lo arregla.
##
## Jugando solo, y para el jugador del host, es el mismo camino sin la red.
## También arma lo que se ve en el mundo en cada máquina: los objetos sueltos y
## lo que tiene equipado cada personaje.
##
## Sin esperar al host (desde el 2026-11-04, pedido del usuario):
##
## - Usar un consumible no es un pedido: viaja en el input del personaje, como
##   el salto o Kp 2 (ActorInput.use_presses y uses), uno nuevo por tick. Justo
##   antes de mover al personaje en ese tick (use_before_step), el host lo
##   valida con el inventario de verdad, aplica el efecto y gasta la unidad, y
##   el cliente aplica el mismo efecto en su predicción: la salud y la estamina
##   cambian al instante y sin corrección. Si el host no lo pudo usar, la
##   corrección del snapshot deshace el efecto y la unidad vuelve a verse.
## - Cada uso tiene su número y viaja en todos los inputs hasta que el host lo
##   contesta, con su resultado propio (desde la auditoría del 2026-11-04,
##   INV-01): si el host se pierde el tick en que salió, lo hace en el primero
##   que le llega, junto con los que vinieron después, en orden. Y como recoger
##   o soltar van por otro camino (pedidos), el host respeta el orden en que el
##   jugador hizo las cosas (INV-02): un uso espera a que el host procese el
##   último pedido hecho antes que él, y un pedido, al último uso hecho antes.
##   Lo que se ve no espera nada de eso.
## - Recoger sigue siendo un pedido, pero lo que se ve no lo espera: mientras
##   tanto la grilla propia se muestra con lo recogido adentro y el objeto deja
##   de verse en el piso (InvReplica.shown_own).
## - Soltar también: esta máquina elige el lugar con la misma regla que el host
##   (predict_drop_spot), lo dibuja ahí ya y se lo manda en el pedido
##   (InvProtocol.Op.DROP_AT). El host lo deja en ese lugar si sirve; si no,
##   elige él y el objeto aparece donde dice el host.
##
## Los inventarios son de cada entidad: al personaje el host le agrega un nodo
## InvInventory (INVENTORY_NODE) al aparecer; cada caja trae el suyo. Las cajas
## y los objetos iniciales se buscan en `world_root`, la zona de prueba.
##
## Objetos con física (desde el 2026-11-14): los objetos sueltos son cuerpos
## que simula el host (InvBodies, el nodo ObjetosSueltos) y se pueden sostener
## en el mundo con la mano (InvHands). Lo discreto (agarrar, soltar, lanzar,
## recoger, entrar y salir del mundo) va por los pedidos y paquetes de siempre,
## confiables y en orden; la pose de lo que se mueve, en paquetes de poses sin
## confiable (send_poses), 30 por segundo y solo de lo que se mueve; y lo que
## pide la mano mientras sostiene, en el input de cada tick (ActorInput.hold).

## Nombre del componente de inventario que el host le agrega a cada personaje.
const INVENTORY_NODE := &"Inventario"
## Nombre de lo equipado, dentro del dibujo de cada personaje.
const EQUIP_NODE := &"Equipado"
## Pedidos que pueden esperar a uno anterior que todavía no llegó.
const MAX_WAITING := 64
## Usos de consumibles sin confirmar en esta máquina (en fila o en viaje): con
## estos, no sale otro hasta que el host conteste alguno. Así el número de uso,
## que da la vuelta en 256, nunca se confunde (auditoría del 2026-11-04, INV-01).
const MAX_USES_WAITING := 32
## Host: cuánto puede esperar un uso al pedido anterior, o un pedido al uso
## anterior, antes de seguir sin él, en milisegundos. Lo normal es que llegue
## enseguida; esto es para que nada quede trabado para siempre.
const ORDER_WAIT_MSEC := 3000
## El alcance para recoger y abrir si no hay Tuning (interaction_range), en metros.
const DEFAULT_INTERACTION_RANGE := 2.0
## Host: cuántos ticks se recuerda dónde quedaron los ojos de cada personaje
## (record_aim_pose), para tirar el rayo de recoger o abrir desde los del tick
## en que el jugador apretó E aunque el pedido llegue después (auditoría del
## 2026-11-12, INT-01). Un segundo: lo normal es que el pedido llegue antes de
## que el host simule ese tick, o pocos ticks después; uno más viejo se hace
## con los ojos de ahora, como antes de este cambio.
const AIM_HISTORY_TICKS := 60

## Se abrió o se cerró la caja del jugador local (para la interfaz).
signal container_closed(id: int, reason: String)

@export var catalog: InvCatalog
@export var actors_root: Node3D
## Dónde están las cajas y los objetos iniciales (InvContainer, InvPickupSpawn).
@export var world_root: Node
## Rama adicional del mapa para objetos recogibles colocados en el editor.
@export var pickup_root: Node

@export_group("Alcances")
## A qué distancia adelante del personaje cae lo que se suelta.
@export var drop_distance := 1.0

@export_group("Mirar")
## En tercera persona, qué tan al costado del cuerpo puede estar lo que se
## agarra o se abre: grados a cada lado de hacia donde mira el personaje.
@export_range(10.0, 180.0, 1.0) var look_cone_degrees := 75.0

@export_group("Grilla del jugador")
@export_range(1, 64) var player_columns := 12
@export_range(1, 64) var player_rows := 16

## El simulador de red del laboratorio. Lo pone el laboratorio.
var link: LinkSimulator
## Los valores del laboratorio (el nodo Tuning): los consumibles los usan para
## los máximos de salud y estamina. Lo pone el laboratorio.
var tuning: ActorTuning
## Hasta qué distancia se recoge un objeto suelto o se abre una caja, en
## metros, de los ojos al punto que toca el rayo de la mano (InvReach): el del
## Tuning (interaction_range, grupo Recoger y abrir), o
## DEFAULT_INTERACTION_RANGE sin Tuning. Con la caja abierta, la distancia de
## los ojos a su volumen. Desde el 2026-11-11 reemplaza a pickup_range y al
## alcance de cada caja.
var interaction_range: float:
	get:
		return tuning.interaction_range if tuning != null else DEFAULT_INTERACTION_RANGE
var replica := InvReplica.new()
## Solo en el host.
var authority: InvAuthority
var started := false
## Solo para pruebas en un proceso: jugadores que se dan por conectados sin
## red (peer -> true).
var test_peers := {}
## Número del último uso de consumible del jugador local que salió en un
## input, de 0 a 255 y da la vuelta: el laboratorio lo pone en su input, con
## los usos que el host todavía no confirmó (fill_input).
var use_presses := 0

var _containers: Array[InvContainer] = []
var _spawns: Array[InvPickupSpawn] = []
var _inbox: Array = []  # host: [peer, número, operación, argumentos, uso anterior], en orden
var _in_expected := {}  # host: peer -> próximo número de pedido
var _in_waiting := {}  # host: peer -> {número: [número, operación, argumentos, uso anterior]}
var _done_seq := {}  # host: peer -> número del último pedido procesado
var _use_wait := {}  # host: peer -> [número de uso, desde cuándo en ms]: esperando un pedido anterior
var _request_wait := {}  # host: peer -> [número de pedido, desde cuándo en ms]: esperando un uso anterior
var _out_seq := {}  # host: peer -> último número de paquete mandado
var _commit_expected := 1
var _commit_waiting := {}
# Los objetos sueltos se dibujan en InvBodies (desde el 2026-11-14; antes,
# _world_views en esta capa).
var _world_layer: Node3D
var _use_counter := 0  # número del último uso puesto en fila en esta máquina
## Número de uso -> lo que hace falta para predecirlo, como estaba al usarlo:
## [InvItemDef, copia de la pila, la barra en snapshot, parte del cuerpo o -1].
## Se usa también al repetir ticks, siempre con copias nuevas (ARQ-01).
var _use_info := {}
var _use_tick := -1
## El tick del último input propio que armó esta máquina (fill_input): va en
## los pedidos de recoger y abrir (aim_tick).
var _input_tick := -1
## Host: peer -> {tick: [ojos de su personaje al terminar ese tick, si el host
## tuvo que repetir un input anterior porque el de ese tick no había llegado]},
## los últimos AIM_HISTORY_TICKS (record_aim_pose).
var _aim_poses := {}
## Host: peer -> el último tick anotado en _aim_poses.
var _aim_latest := {}
## Host, para las pruebas y el diagnóstico: el último pedido de recoger o abrir
## procesado. {"peer", "tick" (el del pedido, -1 sin tick), "eyes" (de dónde
## salió el rayo), "from" ("tick": los ojos al terminar ese tick; "ahora": los
## de ahora, porque el pedido no trae tick o ya no se recuerda), "guessed" (los
## de ese tick salieron de un input repetido)}.
var last_aim := {}
## Host: cuántos pedidos de recoger o abrir tiraron el rayo desde los ojos de
## su tick (de esos, cuántos llegaron cuando el host ya había simulado ticks
## después, y cuántos con los ojos de un tick sin su input) y cuántos desde los
## de ahora. Los imprime el resumen del laboratorio.
var aims_at_tick := 0
var aims_late := 0
var aims_guessed := 0
var aims_now := 0
## Los objetos sueltos con física (desde el 2026-11-14): sus cuerpos o copias.
var bodies: InvBodies
## La mano del jugador local (InvHands): lo que sostiene en el mundo. La pone
## el laboratorio.
var hands: Node
## El reloj de ticks del laboratorio. Lo pone el laboratorio.
var clock: SimClock


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	bodies = InvBodies.new()
	bodies.name = "ObjetosSueltos"
	bodies.net = self
	bodies.catalog = catalog
	bodies.tuning = tuning
	_world_layer = bodies
	add_child(bodies)
	replica.catalog = catalog
	replica.send = _send_request
	# Una vez por paquete del host o por pedido, y no por cada consumible usado
	# (auditoría del 2026-11-04, ESC-01).
	replica.world_view_changed.connect(_sync_world_views)
	replica.equipment_changed.connect(_sync_equipment)
	replica.container_closed.connect(func(id: int, reason: String) -> void: container_closed.emit(id, reason))
	for problem in catalog.problems() if catalog != null else PackedStringArray(["no tiene catálogo"]):
		push_warning("[inventario] catálogo: %s" % problem)
	if world_root != null:
		_collect(world_root)
	if pickup_root != null and pickup_root != world_root \
			and (world_root == null or not world_root.is_ancestor_of(pickup_root)):
		_collect(pickup_root, false)
	for i in _containers.size():
		_containers[i].container_id = i + 1
	if actors_root != null:
		actors_root.child_entered_tree.connect(_on_actor_entered)
		actors_root.child_exiting_tree.connect(_on_actor_exiting)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Los triángulos armados por tipo para el rayo de la mano (InvReach) son de
## este mundo: al irse, se olvidan, así no quedan retenidos tipos y modelos de
## un nivel o un catálogo que ya no está (como las formas para apuntar desde la
## auditoría del 2026-11-08, REND-01, que ya no existen).
func _exit_tree() -> void:
	InvReach.clear_cache()
	InvItemPhysics.clear_cache()


## Las cajas y los objetos iniciales, en el orden del árbol: el número de cada
## caja sale de ahí, igual en todas las máquinas.
func _collect(node: Node, include_containers := true) -> void:
	for child in node.get_children():
		if not include_containers and child == world_root:
			continue
		if child is InvContainer and include_containers:
			_containers.append(child)
		elif child is InvPickupSpawn:
			_spawns.append(child)
		_collect(child, include_containers)


## Arranca al elegir el rol. El host (y jugando solo) arma el estado del mundo
## y se manda a sí mismo el estado inicial; el cliente espera el del host.
func start(as_host: bool) -> void:
	started = true
	replica.reset()
	_commit_expected = 1
	_commit_waiting.clear()
	_in_expected.clear()
	_in_waiting.clear()
	_done_seq.clear()
	_use_wait.clear()
	_request_wait.clear()
	_out_seq.clear()
	_inbox.clear()
	_aim_poses.clear()
	_aim_latest.clear()
	bodies.tuning = tuning
	bodies.catalog = catalog
	bodies.reset()
	if clock != null and not clock.tick_started.is_connected(_on_tick_started):
		# Después de los del laboratorio, que se conectaron antes: en el cliente,
		# la interpolación ya avanzó; en el host, ya se adoptó lo que afirman.
		clock.tick_started.connect(_on_tick_started)
		clock.tick_finished.connect(_on_tick_finished)
	if not as_host:
		return
	authority = InvAuthority.new()
	authority.catalog = catalog
	authority.actors_root = actors_root
	authority.tuning = tuning
	authority.drop_distance = drop_distance
	authority.send = _send_commit
	authority.space.catalog = catalog
	authority.bodies = bodies
	authority.clock_tick = func() -> int: return clock.tick if clock != null else -1
	bodies.authority = authority
	for box in _containers:
		if box.inventory == null:
			push_warning("[inventario] %s no tiene inventario" % box.get_path())
			continue
		box.inventory.setup(catalog)
		authority.containers[box.container_id] = box
		box.tree_exiting.connect(authority.container_gone.bind(box.container_id))
	for spawn in _spawns:
		authority.add_spawn(spawn)
	for actor in actors_root.get_children():
		_attach_inventory.call_deferred(actor)
	authority.welcome(multiplayer.get_unique_id())


func is_host() -> bool:
	return authority != null


## Cliente: se cortó la conexión. Lo que sabía ya no vale; al volver, el host
## le manda todo de nuevo. Lo confirmado no se toca: queda en el host.
func connection_lost() -> void:
	replica.reset()
	_commit_expected = 1
	_commit_waiting.clear()
	bodies.reset()
	if hands != null:
		hands.call(&"drop_hold", "se cortó la conexión", false)


# --- Consumibles sin esperar al host --------------------------------------------

## Usa una unidad de ese objeto del inventario propio: le da su número y sale
## en el input del próximo tick libre (fill_input). Quien llama ya comprobó que
## se puede usar (InvUI.use_item). Desde ya se ve gastada (InvReplica.shown_own).
## Devuelve falso, sin hacer nada, si ya hay MAX_USES_WAITING sin confirmar.
## `part` (desde el 2026-11-06 a la noche): -1 el uso normal; una parte del
## cuerpo (ActorState.Part), soltado sobre ella en el panel de integridad. Así
## curar una parte tampoco espera al host: se predice como el uso normal y el
## host la valida y gasta la unidad.
func queue_use(uid: int, def: InvItemDef, part := -1) -> bool:
	if replica.uses_waiting() >= MAX_USES_WAITING:
		return false
	_use_counter = (_use_counter + 1) & 0xFF
	var shown := replica.shown_own()
	var stack := shown.get_stack(uid) if shown != null else null
	var bar: Variant = null
	if replica.loadout != null:
		bar = replica.loadout.snapshot()
	_use_info[_use_counter] = [def, stack.copy() if stack != null else null, bar, part]
	replica.add_use(uid, _use_counter, part)
	return true


## Pone en el input propio de este tick el número del último uso que salió y
## los que el host todavía no confirmó. Si hay uno esperando en fila, sale en
## este tick (uno nuevo por tick; otra vez en el mismo tick no saca otro), salvo
## que ya viajen ActorInput.MAX_USES sin confirmar. Lo llama el laboratorio al
## armar ese input.
func fill_input(input: ActorInput) -> void:
	_input_tick = input.tick
	if input.tick != _use_tick:
		var counter := replica.send_next_use(ActorInput.MAX_USES)
		if counter >= 0:
			_use_tick = input.tick
			use_presses = counter
	input.use_presses = use_presses
	input.uses = replica.uses_in_flight()
	# Lo que sostiene la mano (desde el 2026-11-14), si sostiene algo.
	input.hold = hands.call(&"hold_for_input") if hands != null else []


## El personaje propio apareció (al entrar o al volver de un corte): los
## números de uso siguen desde el último que procesó el host, así ninguno
## viejo parece nuevo.
func sync_use_counter(seen: int) -> void:
	use_presses = seen & 0xFF
	_use_counter = seen & 0xFF


## Dónde aparecería lo que suelta este personaje (un objeto de tipo `def`),
## como lo va a buscar el host (InvAuthority.find_drop_spot), con lo que esta
## máquina ve suelto, también lo que ya soltó y el host todavía no confirmó. El
## lugar y el giro (Transform3D), o null si no cabe en ningún lado.
func predict_drop_spot(actor: ActorBody, def: InvItemDef = null) -> Variant:
	if actor == null or not actor.is_inside_tree():
		return null
	var taken: Array = []
	for drop: Dictionary in replica.predicted_drops():
		taken.append([drop.get("xf", Transform3D(Basis.IDENTITY, drop["pos"])),
				catalog.find((drop["stack"] as InvStack).def_id)])
	var items := bodies.selector_space()
	items.catalog = catalog
	return InvAuthority.find_drop_spot(get_world_3d().direct_space_state, BaseRegistry.world_position(actor.state),
			actor.state.facing_yaw, drop_distance, def, InvAuthority.crowded_in.bind(items, taken))


## Antes de mover a un actor en un tick (SimClock.before_step, y al repetir
## ticks): hace, en orden, los usos que su input trae y que todavía no se
## hicieron (del siguiente al último visto, ActorState.use_presses_seen, hasta
## use_presses). Casi siempre es uno; son más si el host se perdió el tick en
## que salió alguno. En el host, y jugando solo, valen: cada uno se valida con
## el inventario y gasta la unidad (InvAuthority.use_from_input), pero no antes
## de procesar el último pedido que el jugador hizo antes de usarlo (si todavía
## no llegó, ese uso y los que siguen esperan al tick siguiente). En un cliente
## es la predicción del propio: el mismo efecto, con lo que se usó, sin tocar
## el inventario, que lo cambia el host. Un input sin usos no cuenta: así uno
## armado sin ellos (las pruebas con guion) no hace nada.
func use_before_step(actor: ActorBody, input: ActorInput) -> void:
	# Lo que pide la mano en este tick (desde el 2026-11-14): en el host lo
	# guarda InvBodies para llevar el objeto; en un cliente no hace nada (al
	# repetir ticks no se mueve ningún objeto).
	if authority != null:
		bodies.hold_input(actor, input)
	if input.uses.is_empty():
		return
	var state := actor.state
	var count := (input.use_presses - state.use_presses_seen) & 0xFF
	# Uno que va atrás de lo ya hecho (un input viejo) no hace nada.
	if count == 0 or count >= 128:
		return
	if authority == null:
		for i in count:
			state.use_presses_seen = (state.use_presses_seen + 1) & 0xFF
			_predict_use(state, state.use_presses_seen)
		return
	var peer := actor.owner_peer_id
	var carried := input.uses.size()
	var answered := false
	for i in count:
		var number := (state.use_presses_seen + 1) & 0xFF
		var index := carried - 1 - ((input.use_presses - number) & 0xFF)
		if index < 0:
			# No viene en el input: con un jugador de este juego no pasa, porque
			# cada uso viaja hasta que el host lo contesta.
			state.use_presses_seen = number
			authority.use_refused(peer, number, "se perdió en el camino: probá de nuevo")
			answered = true
			continue
		var use: Array = input.uses[index]
		if not _request_done(peer, use[1]):
			if not _waited_too_long(_use_wait, peer, number):
				break
			push_warning("[inventario] el uso %d del jugador %d esperó demasiado al pedido %d" % [number, peer, use[1]])
			state.use_presses_seen = number
			authority.use_refused(peer, number, "no llegó a tiempo lo que hiciste antes")
			answered = true
			continue
		_use_wait.erase(peer)
		state.use_presses_seen = number
		authority.use_from_input(peer, state, use[0], number, use[2] if use.size() > 2 else -1)
		answered = true
	if answered:
		authority.flush({})


## Cliente: el efecto de un uso propio en la predicción, con el tipo, la pila y
## la barra como estaban al usarlo (copias nuevas cada vez: al repetir ticks se
## vuelve a aplicar igual). Solo lo que la capacidad dice que se puede predecir.
## Sobre una parte del cuerpo, lo mismo que va a hacer el host: si la parte
## sigue dañada en este tick, la cura (InvConsumable.check_part y apply_part).
func _predict_use(state: ActorState, number: int) -> void:
	var info: Array = _use_info.get(number, [])
	var def: InvItemDef = info[0] if not info.is_empty() else null
	var ability := def.ability_of(InvAbility.Kind.USE) if def != null else null
	if ability == null or not ability.predictable() or tuning == null:
		return
	var part: int = info[3] if info.size() > 3 else -1
	if part >= 0:
		var heal := ability as InvConsumable
		if heal != null and heal.check_part(state, part) == "":
			heal.apply_part(state, part)
		return
	var stack: InvStack = info[1].copy() if info[1] != null else null
	var loadout := InvLoadout.from_snapshot(info[2]) if info[2] != null else null
	var vitals := ActorVitals.of(state, tuning)
	vitals.host_event = false
	if ability.check(loadout, stack, vitals) == "":
		ability.apply(loadout, stack, vitals)


## Host: si ya se procesó el pedido `seq` de ese jugador (0 o menos: ninguno).
func _request_done(peer: int, seq: int) -> bool:
	return seq <= 0 or _done_seq.get(peer, 0) >= seq


## Host: si ese jugador ya hizo el uso `number` (-1: ninguno). Sin personaje,
## no hay uso que esperar.
func _use_done(peer: int, number: int) -> bool:
	if number < 0:
		return true
	var actor := authority.actor_of(peer)
	return actor == null or ((actor.state.use_presses_seen - number) & 0xFF) < 128


## Host: el uso o el pedido `what` de ese jugador, trabado esperando a otro,
## lleva más de ORDER_WAIT_MSEC así. La primera vez anota desde cuándo (en
## `table`: _use_wait o _request_wait).
func _waited_too_long(table: Dictionary, peer: int, what: int) -> bool:
	var now := Time.get_ticks_msec()
	var wait: Array = table.get(peer, [])
	if wait.is_empty() or wait[0] != what:
		table[peer] = [what, now]
		return false
	return now - wait[1] > ORDER_WAIT_MSEC


func container(id: int) -> InvContainer:
	return _containers[id - 1] if id >= 1 and id <= _containers.size() and is_instance_valid(_containers[id - 1]) else null


func containers() -> Array[InvContainer]:
	var list: Array[InvContainer] = []
	for box in _containers:
		if is_instance_valid(box) and box.is_inside_tree():
			list.append(box)
	return list


## Lo que el jugador está mirando, si lo puede agarrar o abrir: {"kind": "box"
## o "item", "id", "name", "node", "direction"}, o {} si no hay nada. "node" es
## lo que se ve de ese objetivo en esta máquina (la InvContainer o la
## InvWorldItem): de ahí sale lo que marca el indicador (interact_focus, desde
## el 2026-11-06). "direction" es la de la mano, la que va en el pedido al host
## (InvProtocol.aimed_args): el host tira su propio rayo con ella.
##
## Desde el 2026-11-11 a la noche (pedido del usuario), con la regla de
## InvReach, la misma que usa el host:
##
## 1. La mira es la línea que sale de la cámara por el centro de la pantalla,
##    desde `from` (la cámara, o en tercera persona el punto a la altura de la
##    cabeza: lo que queda entre la cámara y el personaje no se elige) hacia
##    `look`, de largo aim_length. Lo primero que toca (un objeto, una caja o
##    el nivel) es adonde apunta el jugador (InvReach.aim_direction).
## 2. Desde los ojos del personaje sale un rayo hacia ese punto, de largo
##    interaction_range (InvReach.first_hit). Lo primero que toca decide: el
##    modelo de un objeto suelto (sus triángulos tal como se ven, no su hitbox
##    de agarre), la colisión de una caja, o el nivel, que tapa. Si desde los
##    ojos lo primero es otra cosa que lo que vio la cámara, gana eso: lo que
##    marca el indicador es lo que pasa al apretar E.
## 3. En tercera persona, además, tiene que estar adelante del cuerpo: a no más
##    de look_cone_degrees de hacia donde mira el personaje (su punto de apoyo,
##    o el centro de la caja).
##
## Lo que esta máquina recogió y el host todavía no confirmó ya no se ve: el
## rayo lo atraviesa. Lo soltado sin confirmar no está en la lista del host:
## tampoco se toca. Hasta ese día la mira elegía entre las formas que tocaba
## (con un margen o la hitbox de agarre) y aparte se medía la distancia del
## torso a la caja del modelo y una vista con pocos puntos.
##
## Es solo lo que elige esta máquina: el host vuelve a tirar el rayo con lo suyo.
##
## Desde el 2026-11-14 los objetos se mueven y giran: el rayo los toca en la
## pose en que se dibujan en esta máquina (InvBodies.selector_space, con su
## índice espacial: no recorre todos). Uno que sostiene otro jugador tapa,
## pero no se marca ni se agarra. Mientras el jugador sostiene algo, E elige lo
## que sostiene, mire donde mire: lo guarda.
func interaction_target(actor: ActorBody, from: Vector3, look: Vector3, third_person: bool) -> Dictionary:
	if actor == null or not actor.is_inside_tree() or look.length_squared() < 0.0001 or not look.is_finite() \
			or not from.is_finite():
		return {}
	var held: int = hands.call(&"held_uid") if hands != null else 0
	if held != 0 and replica.world.has(held) and bodies.view(held) != null:
		return _item_target(held, look.normalized(), {})
	var space := get_world_3d().direct_space_state
	var feet := actor.global_position
	var eyes := InvAuthority.eyes(actor, feet)
	var own := InvReach.own_shapes(actor)
	var items := bodies.selector_space()
	items.catalog = catalog
	var direction := InvReach.aim_direction(space, eyes, from, look.normalized(), aim_length(from, eyes), items,
			catalog, own, _not_shown)
	return _target_of(InvReach.first_hit(space, eyes, direction, interaction_range, items, catalog, own, _not_shown),
			actor, third_person, direction)


## El objetivo que corresponde a lo que tocó el rayo de la mano, o {} si no se
## puede agarrar ni abrir (el nivel, nada, lo que sostiene otro jugador, o
## atrás del cuerpo en tercera persona). De un objeto, también "point" (dónde
## lo tocó), "place" (su pose en esta máquina) y "distance" (de los ojos).
func _target_of(hit: Dictionary, actor: ActorBody, third_person: bool, direction: Vector3) -> Dictionary:
	var feet := actor.global_position
	var forward := Vector3.FORWARD.rotated(Vector3.UP, actor.state.facing_yaw)
	var cone := cos(deg_to_rad(look_cone_degrees))
	var in_front := func(point: Vector3) -> bool:
		var flat := Vector3(point.x - feet.x, 0.0, point.z - feet.z)
		return not third_person or flat.length() < 0.3 or flat.normalized().dot(forward) >= cone
	match hit.get("kind", ""):
		"item":
			var uid: int = hit["id"]
			var view := bodies.view(uid)
			var item: Dictionary = replica.world.get(uid, {})
			if view == null or item.is_empty() or not in_front.call(view.global_position):
				return {}
			var holder: int = item.get("holder", 0)
			if holder != 0 and holder != multiplayer.get_unique_id():
				return {}
			return _item_target(uid, direction, hit)
		"box":
			var box: InvContainer = hit["node"]
			if not in_front.call(box.center()):
				return {}
			return {"kind": "box", "id": box.container_id, "name": box.display_name, "node": box, "direction": direction}
	return {}


func _item_target(uid: int, direction: Vector3, hit: Dictionary) -> Dictionary:
	var item: Dictionary = replica.world[uid]
	var view := bodies.view(uid)
	var stack: InvStack = item["stack"]
	var def := catalog.find(stack.def_id)
	var target := {"kind": "item", "id": uid, "name": (def.display_name if def != null else String(stack.def_id)) +
			(" ×%d" % stack.quantity if stack.quantity > 1 else ""), "node": view, "direction": direction,
			"place": bodies.selector_space().transform_of(uid)}
	if not hit.is_empty():
		target["point"] = hit["point"]
		target["distance"] = hit["distance"]
	return target


## El tick del host de lo que muestra esta máquina de los objetos, para los
## pedidos de recoger y agarrar (InvProtocol.aimed_args): en un cliente, el
## que se interpola (el de los demás jugadores); en el host, -1 (lo de ahora).
func view_tick() -> float:
	if authority != null or not bodies.render_tick.is_valid():
		return -1.0
	return bodies.render_tick.call()


## El tick que va en los pedidos de recoger y abrir (InvProtocol.aimed_args):
## el del último input propio que armó esta máquina. Al apretar E, el
## personaje que se ve es el de después de ese tick. El host tira el rayo
## desde los ojos que tenía su personaje al terminar ese mismo tick
## (record_aim_pose), sin creerle ninguna posición al jugador: si el pedido
## llega antes, espera a simularlo; si llega después, usa los que anotó.
##
## Hasta el 2026-11-12 (auditoría, INT-01) el host esperaba solo a haber
## empezado ese tick y tiraba el rayo desde los ojos de ese momento: un pedido
## que llegaba unos ticks tarde usaba al personaje ya movido (caminando de
## costado, un objeto chico se rechazaba), y un tick simulado sin su input
## contaba como si hubiera llegado.
func aim_tick() -> int:
	return _input_tick


## Host, al terminar cada tick y después de adoptar lo que afirman los
## clientes (net_lab._on_tick_finished): anota dónde quedaron los ojos del
## personaje (InvAuthority.eyes, con su postura). Con lo adoptado, son los
## mismos que tenía el personaje en la máquina del jugador en ese tick.
## `guessed`: el host lo movió en ese tick repitiendo un input anterior, porque
## el de ese tick no había llegado (NetSync.used_input_tick). Esos ojos
## valen igual: son donde el host dice que estaba, como el resto del
## movimiento; casi siempre coinciden y, si no, el pedido se rechaza y la
## máquina del jugador recibe la corrección.
func record_aim_pose(actor: ActorBody, tick: int, guessed: bool) -> void:
	if authority == null or actor == null or not actor.is_inside_tree():
		return
	var peer := actor.owner_peer_id
	var poses: Dictionary = _aim_poses.get_or_add(peer, {})
	poses[tick] = [InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state)), guessed]
	_aim_latest[peer] = maxi(_aim_latest.get(peer, tick), tick)
	poses.erase(tick - AIM_HISTORY_TICKS)
	if poses.size() > AIM_HISTORY_TICKS:
		for old: int in poses.keys():
			if old <= _aim_latest[peer] - AIM_HISTORY_TICKS:
				poses.erase(old)


## Host: los ojos desde donde se tira el rayo de un pedido de recoger o abrir
## hecho en el tick `aimed`: los anotados al terminar ese tick, o null (los de
## ahora) si el pedido no trae tick o ese tick ya no se recuerda (más de
## AIM_HISTORY_TICKS atrás, o el personaje recién aparece). Lo anota en last_aim.
func _aim_eyes(peer: int, aimed: int) -> Variant:
	var pose: Array = _aim_poses.get(peer, {}).get(aimed, []) if aimed >= 0 else []
	last_aim = {"peer": peer, "tick": aimed, "eyes": pose[0] if not pose.is_empty() else null,
			"from": "tick" if not pose.is_empty() else "ahora", "guessed": pose[1] if not pose.is_empty() else false}
	if pose.is_empty():
		aims_now += 1
		return null
	aims_at_tick += 1
	aims_late += 1 if _aim_latest.get(peer, aimed) > aimed else 0
	aims_guessed += 1 if pose[1] else 0
	return pose[0]


## Si el rayo de la mano atraviesa ese objeto en esta máquina: lo que ya se
## recogió acá y el host todavía no confirmó, o lo que todavía no se dibuja.
func _not_shown(uid: int) -> bool:
	return replica.is_taken(uid) or bodies.view(uid) == null


## Hasta dónde llega la línea de la cámara, desde `from` (donde arranca) con
## los ojos del personaje en `eyes_at`: lo que hay de `from` a los ojos (en
## tercera persona, la mira arranca a la altura de la cabeza y puede ir corrida
## al costado del cuerpo) más el alcance. Lo que toca más allá tampoco lo
## alcanza el rayo de la mano. Hasta el 2026-11-11 eran 6 m o el alcance más
## 2 m; ese día, desde el torso, sumando lo más grande que se podía elegir.
func aim_length(from: Vector3, eyes_at: Vector3) -> float:
	return from.distance_to(eyes_at) + interaction_range


# --- Personajes ---------------------------------------------------------------

func _on_actor_entered(node: Node) -> void:
	# Al entrar todavía no corrió su _ready: se le agrega lo suyo después.
	_attach_inventory.call_deferred(node)
	_sync_equipment.call_deferred()


func _on_actor_exiting(node: Node) -> void:
	var actor := node as ActorBody
	if actor != null and authority != null:
		authority.actor_left(actor.owner_peer_id)


## Host: el inventario del personaje, si todavía no lo tiene (al volver de un
## corte trae el de su actor anterior: ver actor_replaced).
func _attach_inventory(node: Node) -> void:
	var actor := node as ActorBody
	if authority == null or actor == null or not is_instance_valid(actor) or actor.is_queued_for_deletion() \
			or actor.has_node(NodePath(INVENTORY_NODE)):
		return
	var inventory := InvInventory.new()
	inventory.name = INVENTORY_NODE
	inventory.columns = player_columns
	inventory.rows = player_rows
	inventory.has_loadout = true
	inventory.setup(catalog)
	actor.add_child(inventory)
	authority.inventory_attached(actor.owner_peer_id)


## Host: un jugador volvió después de un corte (NetSession.actor_replaced).
func actor_replaced(old_actor: ActorBody, new_actor: ActorBody) -> void:
	if authority != null:
		authority.actor_replaced(old_actor, new_actor)


# --- Red ----------------------------------------------------------------------

func _on_peer_connected(peer: int) -> void:
	if authority == null:
		return
	_forget_order(peer)
	# Después de que la sesión le dé su actor (o le devuelva el de antes).
	authority.welcome.call_deferred(peer)


func _on_peer_disconnected(peer: int) -> void:
	if authority == null:
		return
	authority.forget_peer(peer)
	_forget_order(peer)
	_inbox = _inbox.filter(func(item: Array) -> bool: return item[0] != peer)


## Host: los números de pedido de ese jugador empiezan de nuevo.
func _forget_order(peer: int) -> void:
	_out_seq.erase(peer)
	_in_expected.erase(peer)
	_in_waiting.erase(peer)
	_done_seq.erase(peer)
	_use_wait.erase(peer)
	_request_wait.erase(peer)
	_aim_poses.erase(peer)
	_aim_latest.erase(peer)


## Host: cuando la sesión corta a alguien por silencio (NetSession), Godot no
## siempre avisa peer_disconnected. Quien ya no figura entre los conectados se
## olvida igual: sus suscripciones y lo que tenía en fila.
func _forget_gone_peers() -> void:
	var connected := multiplayer.get_peers()
	var local := multiplayer.get_unique_id()
	for peer in authority.welcomed_peers():
		if peer != local and not peer in connected and not test_peers.has(peer):
			_on_peer_disconnected(peer)


func _send_request(seq: int, op: int, args: Array, after_use := -1) -> void:
	if authority != null:
		# El jugador del host: sin red, pero por la misma fila y el mismo control de repetidos.
		_queue_request(multiplayer.get_unique_id(), [seq, op, args, after_use])
		return
	var data := InvProtocol.encode_request(seq, op, args, after_use)
	_send_reliable(func() -> void: _inv_request.rpc_id(1, data))


@rpc("any_peer", "call_remote", "reliable")
func _inv_request(data: PackedByteArray) -> void:
	if authority == null:
		return
	_receive_reliable(_accept_request.bind(multiplayer.get_remote_sender_id(), data))


## Host: pone en fila un pedido, en el orden de sus números. Uno que ya pasó es
## un repetido: no se vuelve a hacer, se le contesta lo mismo.
func _accept_request(peer: int, data: PackedByteArray) -> void:
	if authority == null or not peer in multiplayer.get_peers() or not authority.is_welcomed(peer):
		return
	var parsed := InvProtocol.parse_request(data)
	if parsed.is_empty():
		authority.rejected += 1
		return
	_queue_request(peer, parsed)


func _queue_request(peer: int, parsed: Array) -> void:
	var seq: int = parsed[0]
	var expected: int = _in_expected.get(peer, 1)
	if seq < expected:
		authority.repeat_result(peer, seq)
		return
	if seq >= expected + MAX_WAITING:
		return
	if not _in_waiting.has(peer):
		_in_waiting[peer] = {}
	var waiting: Dictionary = _in_waiting[peer]
	if waiting.has(seq):
		authority.repeated += 1
		return
	waiting[seq] = parsed
	while waiting.has(expected):
		_inbox.append([peer] + waiting[expected])
		waiting.erase(expected)
		expected += 1
	_in_expected[peer] = expected


## Host: procesa los pedidos en fila. Va en el cuadro de física porque soltar
## algo consulta el espacio físico. Un pedido hecho después de usar un
## consumible espera a que el host haga ese uso (llega por el input, por otro
## camino): ese pedido y los que siguen del mismo jugador quedan en la fila
## para el cuadro siguiente; los de los demás jugadores siguen. Si espera más
## de ORDER_WAIT_MSEC, se procesa igual.
func _physics_process(_delta: float) -> void:
	if authority == null:
		return
	_forget_gone_peers()
	var space := get_world_3d().direct_space_state
	var held := {}  # peer -> true: tiene un pedido esperando un uso
	var kept: Array = []
	var queue := _inbox
	_inbox = []
	for item: Array in queue:
		var peer: int = item[0]
		var after_use: int = item[4] if item.size() > 4 else -1
		if held.has(peer):
			kept.append(item)
			continue
		if not _use_done(peer, after_use):
			if not _waited_too_long(_request_wait, peer, item[1]):
				held[peer] = true
				kept.append(item)
				continue
			push_warning("[inventario] el pedido %d del jugador %d esperó demasiado al uso %d" % [item[1], peer, after_use])
		# Recoger y abrir: el rayo sale de los ojos que tenía el personaje al
		# terminar el tick en que el jugador apretó E (aim_tick). Si el host
		# todavía no lo simuló (el pedido llegó antes que los últimos inputs, los
		# pasos de frenar, por ejemplo), espera; si ya pasó, usa los anotados
		# (record_aim_pose; desde el 2026-11-12, INT-01).
		var aimed := InvProtocol.aimed_tick_of(item[2], item[3])
		if aimed >= 0 and _aim_latest.has(peer) and _aim_latest[peer] < aimed:
			if not _waited_too_long(_request_wait, peer, item[1]):
				held[peer] = true
				kept.append(item)
				continue
			push_warning("[inventario] el pedido %d del jugador %d esperó demasiado al tick %d (el host va por el %d)" % [item[1],
					peer, aimed, _aim_latest[peer]])
		_request_wait.erase(peer)
		var aimed_op: bool = item[2] == InvProtocol.Op.PICKUP or item[2] == InvProtocol.Op.OPEN
		authority.handle(peer, item[1], item[2], item[3], space, _aim_eyes(peer, aimed) if aimed_op else null)
		_done_seq[peer] = maxi(_done_seq.get(peer, 0), item[1])
	# Lo que llegó mientras tanto va después de lo que quedó esperando.
	_inbox = kept + _inbox
	authority.watch_access()


func _process(_delta: float) -> void:
	if started:
		for seq in replica.expire_pending():
			push_warning("[inventario] el pedido %d no tuvo respuesta del host" % seq)


## Host: un paquete para un jugador, con su número. Al propio se lo entrega
## acá mismo, por el mismo camino (copiado, como si hubiera viajado).
func _send_commit(peer: int, payload: Dictionary) -> void:
	var seq: int = _out_seq.get(peer, 0) + 1
	_out_seq[peer] = seq
	payload["s"] = seq
	var data := var_to_bytes(payload)
	if peer == multiplayer.get_unique_id():
		_accept_commit(data)
		return
	# Uno que se acaba de ir (o que volvió con otra conexión) ya no tiene a quién mandarle.
	if not peer in multiplayer.get_peers():
		return
	_send_reliable(func() -> void:
		if peer in multiplayer.get_peers():
			_inv_commit.rpc_id(peer, data))


@rpc("authority", "call_remote", "reliable")
func _inv_commit(data: PackedByteArray) -> void:
	_receive_reliable(_accept_commit.bind(data))


func _accept_commit(data: PackedByteArray) -> void:
	var payload: Variant = bytes_to_var(data)
	if not payload is Dictionary or typeof(payload.get("s")) != TYPE_INT:
		return
	var seq: int = payload["s"]
	if seq < _commit_expected:
		return
	_commit_waiting[seq] = payload
	while _commit_waiting.has(_commit_expected):
		var next: Dictionary = _commit_waiting[_commit_expected]
		_commit_waiting.erase(_commit_expected)
		_commit_expected += 1
		replica.apply_commit(next)


func _send_reliable(packet: Callable) -> void:
	var guarded := func() -> void:
		if multiplayer.has_multiplayer_peer() \
				and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			packet.call()
	if link != null:
		link.deliver_reliable(guarded)
	else:
		guarded.call()


func _receive_reliable(packet: Callable) -> void:
	if link != null:
		link.deliver_reliable(packet)
	else:
		packet.call()


# --- Lo que se ve en el mundo ---------------------------------------------------

## Lo que se ve suelto en el mundo: lo que dice el host, menos lo que esta
## máquina ya recogió entero y el host todavía no confirmó, más lo que ya soltó
## y el host todavía no confirmó (con un número negativo, el de su pedido).
## Desde el 2026-11-14 lo arma InvBodies: en el host, los cuerpos; en un
## cliente, las copias, que toman la pose de cada paquete confiable como una
## muestra más (con su tick) y después siguen con los paquetes de poses.
func _sync_world_views() -> void:
	if authority == null:
		for uid: int in replica.world:
			var item: Dictionary = replica.world[uid]
			var newest := bodies.newest_sample(uid)
			if item.get("t", -1) >= 0 and (newest.is_empty() or newest[0] < item["t"]):
				bodies.add_sample(uid, item["t"], item["xf"], item.get("lv", Vector3.ZERO), item.get("sleep", true),
						item.get("holder", 0) != 0)
			elif newest.is_empty():
				bodies.add_sample(uid, 0, item["xf"], Vector3.ZERO, true)
	bodies.sync_views(replica)
	if hands != null:
		hands.call(&"world_changed")


# --- Los ticks y las poses (desde el 2026-11-14) ------------------------------

## Al empezar cada tick. Host: lee la pose de los cuerpos que se movieron.
## Cliente: coloca las copias en el tick del host que se muestra.
func _on_tick_started(tick: int) -> void:
	if not started:
		return
	if authority != null:
		bodies.on_tick_started(tick)
	else:
		bodies.place_copies(hands.call(&"predicted_uid") if hands != null else -1)


## Al terminar cada tick, con los personajes ya movidos. Host: lleva lo que se
## sostiene y manda las poses. En las dos, la mano propia coloca lo que sostiene.
func _on_tick_finished(tick: int) -> void:
	if not started:
		return
	if authority != null:
		bodies.on_tick_finished(tick)
	if hands != null:
		hands.call(&"after_tick", tick)


## Host: un paquete de poses (InvBodies.encode_poses) a cada cliente, sin
## confiable (si se pierde, llega el siguiente) y por el simulador de red.
func send_poses(data: PackedByteArray) -> void:
	for peer in multiplayer.get_peers():
		if authority.is_welcomed(peer):
			var to: int = peer
			var send := func() -> void:
				if to in multiplayer.get_peers():
					_inv_poses.rpc_id(to, data)
			if link != null:
				link.deliver(send)
			else:
				send.call()


@rpc("authority", "call_remote", "unreliable")
func _inv_poses(data: PackedByteArray) -> void:
	var accept := func() -> void: bodies.accept_poses(data)
	if link != null:
		link.deliver(accept)
	else:
		accept.call()


func _sync_equipment() -> void:
	if actors_root == null:
		return
	for node in actors_root.get_children():
		var actor := node as ActorBody
		if actor == null or actor.is_queued_for_deletion() or actor.visual_root() == null:
			continue
		var view := actor.visual_root().get_node_or_null(NodePath(EQUIP_NODE)) as InvEquipView
		if view == null:
			view = InvEquipView.new()
			view.name = EQUIP_NODE
			view.setup(actor)
			actor.visual_root().add_child(view)
		var def_id: String = replica.equipment.get(actor.owner_peer_id, "")
		view.show_def(catalog.find(StringName(def_id)) if def_id != "" else null)


## Host: cuántos pedidos esperan en fila o a que llegue uno anterior.
func queued_requests() -> int:
	var count := _inbox.size()
	for peer in _in_waiting:
		count += _in_waiting[peer].size()
	return count


## Lo que se ve de un objeto suelto: su cuerpo en el host, su copia en un
## cliente; null si no se ve (en el host, lo que su jugador ya recogió y todavía
## no se procesó queda con el cuerpo, escondido).
func world_view(uid: int) -> InvWorldItem:
	var view := bodies.view(uid)
	return view if view != null and view.visible else null


## Dónde está un objeto suelto en esta máquina (lo que se ve), o null.
func item_transform(uid: int) -> Variant:
	var items := bodies.selector_space()
	if not items.has(uid):
		return null
	return items.transform_of(uid)


## Lo que tiene que ser igual en el host y en los clientes (SimFingerprint):
## los valores de acá, el catálogo, las cajas y los objetos iniciales (su tipo,
## cantidad, estado y lugar). Los demás valores de cada InvPickupSpawn, como el
## cartel (show_label), entran por el texto de la zona que suma el
## laboratorio (SimFingerprint.level_text).
func fingerprint_text() -> String:
	# La versión de los pedidos y paquetes (desde el 2026-11-14).
	var text := "protocolo %d jugador %d×%d alcance %s soltar %s\n" % [InvProtocol.VERSION, player_columns, player_rows,
			snappedf(interaction_range, 0.0001), snappedf(drop_distance, 0.0001)]
	text += catalog.fingerprint_text() if catalog != null else "sin catálogo"
	# De cada caja, también su volumen para el alcance con su lugar, giro y
	# escala (desde el 2026-11-11; antes, su alcance propio y solo su posición).
	for box in _containers:
		var place := box.global_transform
		text += "\ncaja %d %s %d×%d volumen %s %s en %s %s %s %s" % [box.container_id, box.display_name, box.columns,
				box.rows, box.reach_box().position.snapped(Vector3.ONE * 0.0001), box.box_size.snapped(Vector3.ONE * 0.0001),
				place.origin.snapped(Vector3.ONE * 0.0001), place.basis.x.snapped(Vector3.ONE * 0.0001),
				place.basis.y.snapped(Vector3.ONE * 0.0001), place.basis.z.snapped(Vector3.ONE * 0.0001)]
	for spawn in _spawns:
		# Desde el 2026-11-14, también su giro: el objeto arranca girado como el marcador.
		var place := spawn.spawn_transform()
		text += "\nobjeto %s ×%d %s en %s giro %s %s %s" % [String(spawn.item.id) if spawn.item != null else "?",
				spawn.quantity, var_to_str(spawn.initial_state()), place.origin.snapped(Vector3.ONE * 0.0001),
				place.basis.x.snapped(Vector3.ONE * 0.0001), place.basis.y.snapped(Vector3.ONE * 0.0001),
				place.basis.z.snapped(Vector3.ONE * 0.0001)]
	return text
