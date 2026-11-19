class_name PistaPiloto
extends Node

signal diagnostic_event(event: String, fields: Dictionary)

## Primera integración piloto del sistema de objetos nuevo en el laboratorio
## (desde el 2026-11-18). Une la sala de objetos aprobada
## (prototypes/objetos_adaptador/play_room.gd, entrega 17) con el laboratorio:
## el personaje, el reloj, la sesión de red, NetSync, ClientPrediction e
## InvHands son los de siempre; la caja de la pista (PistaObjetos) vive en un
## mundo Rapier propio con el adaptador, el registro del host y el canal de la
## entrega 16.
##
## **Quién hace qué.** El host tiene el mundo de la caja (el de verdad) y decide
## agarrar, soltar y lanzar con el registro de acciones (host_action_journal):
## comprueba distancia, línea libre y el límite del impulso en el tick en que se
## ejecuta. El invitado vinculado pide esas acciones por el canal de la pista y
## espera la respuesta; mientras sostiene, mueve la caja con predicción: cada
## estado del host se restaura y se repiten los ticks propios con la mano de
## cada input (ActorInput.hold, sesión HOLD_SESSION). Es la misma política de la
## sala: un pedido por vez, y otra acción recién cuando llegó un estado del host
## que incluye la anterior.
##
## **Alcance del piloto.** Una caja y un invitado (el primero que entra). El
## jugador del host ve la caja pero no la agarra. Los objetos del inventario, el
## catálogo y los choques entre varios objetos quedan para las entregas que
## siguen. Si el invitado se va, el host suelta la caja y la deja caer; si
## vuelve (o entra otro), se vincula de nuevo desde el estado de ese momento.
##
## **Lo que se ve** sale de la sala aprobada (_present_box y sus ayudas): en el
## host, el mundo de verdad suavizado; en el invitado, la caja en mano junto a
## la meta local de la mano, la caja suelta con las poses del host en orden y
## el apoyo sobre el piso y el bloque. Lo dibuja un solo nodo (box_visual), sin
## la interpolación de física del motor.

const Adapter = preload("res://prototypes/objetos_adaptador/clock_adapter.gd")
const Journal = preload("res://prototypes/objetos_adaptador/host_action_journal.gd")
const Channel = preload("res://scenes/net_lab/pista_objetos/pista_canal.gd")
const History = preload("res://scenes/net_lab/pista_objetos/pista_historia.gd")
const OffsetWorld = preload("res://scenes/net_lab/pista_objetos/pista_mundo.gd")

## Sesión de la mano de la pista en ActorInput.hold. InvHands numera las suyas
## desde 1 y nunca llega acá; el host del inventario (InvBodies) ignora una
## sesión que no es la de un agarre suyo.
const HOLD_SESSION := InvHands.PILOT_HOLD_SESSION
## Mano por defecto en la copia para objetos cuando el input no trae la de la
## pista (como el host de la sala).
const DEFAULT_PITCH := -0.60
const DEFAULT_DISTANCE := 1.8
## Reglas de la sala aprobada.
const REACH := 2.5
const MAX_ACTION_LEAD := 15
const THROW_IMPULSE := 5.0
const SNAPSHOT_EVERY := 4
## También versiona los RPC que enlazan la caja entre estas dos copias.
const PILOT_PROTOCOL_REVISION := 102
const PENDING_TIMEOUT_MS := 2500
## Cuántos ticks puede rehacer el invitado al recibir un estado del host. El
## atraso con que llega un estado es lo que el invitado va adelantado más el
## viaje desde el host: crece con la latencia de las dos PC. Con 32 (hasta el
## 2026-11-18), los dos en Alt+4 en dos notebooks dieron estados de 35 ticks de
## mediana y 40 como máximo, y el invitado quedaba recuperando el 75 % del
## tiempo con la caja en la mano.
const GUEST_AUTHORITY_REPLAY_LIMIT := 48
## Lo dibujado (sala aprobada, play_room.gd).
const HOLD_VISUAL_MAX_OFFSET := 0.12
const HOLD_VISUAL_MAX_ANGLE := PI / 18.0
const HOLD_VISUAL_IDLE_OFFSET := 0.008
const HOLD_VISUAL_IDLE_ANGLE := PI / 300.0
const GRAB_PREVIEW_MAX_OFFSET := 0.18
const GRAB_HANDOFF_TIME := 0.075
const FREE_DRAW_BUFFER_TICKS := 4.0
const MAX_FREE_DRAW_SAMPLES := 24
const FREE_SUPPORT_MAX_DEPTH := 0.08
## Lo que miran las consultas del dibujo: el nivel, las cajas y lo que solo
## frena a la caja (la barrera de la puerta y el techo).
const VIEW_MASK := 1 | 4 | PistaObjetos.OBJECT_ONLY_LAYER

enum Role { NONE, HOST, GUEST }

# Lo pone el laboratorio.
var pista: PistaObjetos
var clock: SimClock
var sync: NetSync
var prediction: ClientPrediction
var tuning: ActorTuning
var link: LinkSimulator
var hands: InvHands
var ui: InvUI
var camera: LabCamera
var actors_root: Node3D
## func(ActorInput): el paso del personaje propio del laboratorio (_step_local).
var step_local: Callable
## func() -> ActorBody: el personaje propio del laboratorio.
var local_actor: Callable

var role := Role.NONE
## En el host: esta partida usa la pista. En el invitado: el host la ofreció.
var active := false
var note := ""

# --- Host ---------------------------------------------------------------------
var _world  # el mundo de la caja del host, para toda la partida (OffsetWorld)
var _world_base := 0
var _peer := 0
var _connection := 0
var _adapter
var _journal
var _channel
var _publishing := false
var _revision := 0
var _applied_tick := -1
var _factory_first = null

# --- Invitado -----------------------------------------------------------------
var _history
var _base := 0
var _g0 := -1
var _initial_base := -1
var _wants_bind := false
var _requested_msec := 0
var _ready_to_play := false
var _serial := 0
var _pending_id := 0
var _pending_kind := ""
var _pending_since := 0
var _guest_applied_tick := -1
## Una suelta pedida mientras el agarre esperaba la respuesta del host: impulso
## (Vector3) o null. Sale cuando llega el estado con el agarre; si el agarre se
## rechaza, se cancela.
var _deferred_release = null
var _recovery_view_world
var _recovery_view_sample := {}
var _pend := {}
var _latest := {}

# --- Lo que se ve (sala aprobada) ----------------------------------------------
var box_visual: MeshInstance3D
var _box_view_query := PhysicsShapeQueryParameters3D.new()
var _box_view_shape := BoxShape3D.new()
var _grab_preview_shape := BoxShape3D.new()
var _shown_pose_ready := false
var _grab_preview := false
var _grab_preview_anchor := Vector3.ZERO
var _grab_handoff_from := Transform3D.IDENTITY
var _grab_handoff_remaining := 0.0
var _free_draw_samples: Array[Dictionary] = []
var _free_draw_tick := -1.0
var _free_supports: Array[AABB] = []
var _drew_box_held := false
var _loose_draw_from := Transform3D.IDENTITY
var _loose_draw_remaining := 0.0
## El último cuadro dibujó la caja en la mano propia mientras recuperaba.
var _recovery_drew_hand := false

# --- Mediciones (panel y pruebas) ---------------------------------------------
var bindings := 0
var recoveries := 0
var authorities_applied := 0
var authorities_rejected := 0
var authorities_skipped_old := 0
## Corrección física de la caja del invitado: cuánto cambió la caja del presente
## al aplicar un estado del host (lo predicho contra lo repetido desde el host).
var box_corrections := 0
var box_correction_max := 0.0
var box_correction_sum := 0.0
var last_box_correction := 0.0
var results := {"applied": 0, "rejected": 0, "cancelled": 0, "expired": 0}
var deferred_releases := 0
var far_releases := 0
var last_recovery_reason := ""
## Por qué no salió el último agarre (para las pruebas y la consola).
var last_refusal := ""
## Cuánto tarda aplicar un estado del host (restaurar y repetir los ticks propios).
var apply_usec_max := 0
var apply_usec_sum := 0
var apply_steps_max := 0
## Host: ticks con la caja en mano (o con una acción) simulados con un input repetido del invitado.
var inputs_repeated_with_box := 0

static var _default_hold: Array = []


func _ready() -> void:
	_box_view_shape.size = PistaObjetos.BOX_SIZE
	# Un margen chico deja levantar con la anticipación una caja apoyada (sala).
	_grab_preview_shape.size = PistaObjetos.BOX_SIZE - Vector3.ONE * 0.012
	_box_view_query.shape = _box_view_shape
	_box_view_query.collision_mask = VIEW_MASK
	_box_view_query.margin = 0.005


static func has_native_world() -> bool:
	return ClassDB.class_exists("SahurObjectWorld")


## La copia del input para el mundo de objetos: lo mismo que mueve al personaje
## y la mano de la pista. Sin los usos de consumibles ni lo que afirma de un
## objeto del inventario. Si no trae la mano de la pista, lleva la de por
## defecto: en el host y en el invitado da lo mismo, porque se arma igual.
static func object_input(input: ActorInput) -> ActorInput:
	var b := StreamPeerBuffer.new()
	input.write_to(b)
	b.seek(0)
	var copy := ActorInput.read_from(b)
	if copy == null:
		return null
	copy.uses = []
	copy.use_presses = 0
	copy.held_claim = PackedByteArray()
	if copy.hold.size() != 7 or copy.hold[0] != HOLD_SESSION:
		if _default_hold.is_empty():
			_default_hold = ActorInput.pack_hold(HOLD_SESSION, DEFAULT_PITCH, DEFAULT_DISTANCE, Quaternion.IDENTITY)
		copy.hold = _default_hold.duplicate()
	return copy


# --- Arranque ----------------------------------------------------------------------

## Host: esta partida usa la pista. Crea el mundo de la caja con el tick de ahora.
## Jugando solo ( falso) la caja se ve y cae, pero nadie la agarra.
func start_host(networked := true) -> bool:
	if not has_native_world() or pista == null:
		note = "Falta la extensión de objetos (bin/sahur_object_world.dll): la pista no se activa."
		return false
	role = Role.HOST
	_world_base = clock.tick
	_world = _new_world(_world_base)
	if _world == null:
		note = "No se pudo crear el mundo de la caja."
		return false
	active = true
	_free_supports = pista.supports()
	_make_box_visual()
	clock.tick_finished.connect(_host_free_step)
	multiplayer.peer_connected.connect(_offer_to)
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		if id == _peer:
			_unbind_host("el invitado se fue"))
	if networked:
		note = "Pista de objetos activa: esperando un invitado."
	else:
		note = "Pista de objetos: la caja la mueve un invitado; jugando solo, solo se ve."
	return true


## Invitado: espera que el host ofrezca la pista.
func start_guest() -> void:
	role = Role.GUEST
	if pista != null:
		_free_supports = pista.supports()


## Host: un jugador que vuelve después de un corte (NetSession lo espera).
func player_waiting(peer_id: int) -> void:
	if role == Role.HOST and peer_id == _peer:
		_unbind_host("se le cortó la conexión al invitado")


func _new_world(base: int):
	var native = ClassDB.instantiate("SahurObjectWorld")
	if native == null or not native.enable_direct_hand():
		return null
	for part in pista.native_parts():
		if not native.add_box(part[0], 1, part[1], 0.0, part[2]):
			return null
	if not native.add_box(PistaObjetos.BOX_ID, 1, PistaObjetos.BOX_SIZE, PistaObjetos.BOX_MASS, pista.box_start()):
		return null
	if not native.seal_topology(PistaObjetos.MODEL_REVISION):
		return null
	return OffsetWorld.new(native, base)


## Lo que le pasa el adaptador a su fábrica: el primer mundo es el que ya
## existe (host: el de la partida; invitado: uno nuevo en el tick de su reloj);
## los que siguen son mundos nuevos para restaurar un estado del host.
func _make_world():
	if _factory_first != null:
		var first = _factory_first
		_factory_first = null
		return first
	var base := _base if role == Role.GUEST else _world_base
	if _initial_base >= 0:
		base = _initial_base
		_initial_base = -1
	return _new_world(base)


func _make_box_visual() -> void:
	if box_visual != null:
		return
	box_visual = _mesh(PistaObjetos.BOX_SIZE, Color("#dc8c42"))
	box_visual.name = "CajaPiloto"
	box_visual.top_level = true
	# La dibuja este nodo cuadro a cuadro: sin la interpolación del motor encima.
	box_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	pista.add_child(box_visual)
	var stripe := _mesh(Vector3(0.11, 0.006, PistaObjetos.BOX_SIZE.z * 0.86), Color("#493321"))
	stripe.position = Vector3(-0.11, PistaObjetos.BOX_SIZE.y * 0.5, 0)
	box_visual.add_child(stripe)
	var nose := _mesh(Vector3(PistaObjetos.BOX_SIZE.x * 0.84, 0.085, 0.005), Color("#493321"))
	nose.position = Vector3(0, 0.07, PistaObjetos.BOX_SIZE.z * 0.5)
	box_visual.add_child(nose)
	box_visual.global_transform = pista.box_start()
	box_visual.visible = role == Role.HOST


func _mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var model := BoxMesh.new()
	model.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	model.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = model
	return instance


## Lo que llega por red pasa por el simulador del laboratorio, como lo demás.
func _later(packet: Callable) -> void:
	if link != null:
		link.deliver_reliable(packet)
	else:
		packet.call()


# --- Host: vínculo con el invitado ----------------------------------------------

func _offer_to(peer_id: int) -> void:
	if role != Role.HOST or not active:
		return
	_offer.rpc_id(peer_id, PILOT_PROTOCOL_REVISION)


@rpc("authority", "call_remote", "reliable")
func _offer(revision: int) -> void:
	_later(func() -> void:
		if role != Role.GUEST:
			return
		if revision != PILOT_PROTOCOL_REVISION:
			note = "La pista de objetos del host es de otra versión: usá la misma copia en las dos PC."
			return
		if not has_native_world():
			note = "Falta la extensión de objetos (bin/sahur_object_world.dll): no podés usar la caja."
			return
		active = true
		_wants_bind = true
		_requested_msec = 0
		note = "Pista de objetos: preparando la caja…")


@rpc("any_peer", "call_remote", "reliable")
func _request() -> void:
	var sender := multiplayer.get_remote_sender_id()
	_later(func() -> void:
		if role != Role.HOST or not active or not sender in multiplayer.get_peers():
			return
		if _peer != 0 and _peer != sender:
			_refuse.rpc_id(sender, "La caja de la pista ya la usa otro invitado (el piloto es para uno).")
			return
		if _peer == sender:
			_unbind_host("el invitado volvió a pedir la caja")
		_bind_host(sender))


@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	_later(func() -> void:
		if role == Role.GUEST:
			_wants_bind = false
			note = reason)


func _bind_host(peer_id: int) -> void:
	var actor := actors_root.get_node_or_null("Actor%d" % peer_id) as ActorBody
	if actor == null or actor.is_queued_for_deletion():
		return
	_catch_up_world()
	_connection = randi_range(1, 0x7fffffff)
	_adapter = Adapter.new()
	_adapter.name = "Adaptador"
	add_child(_adapter)
	_factory_first = _world
	if not _adapter.start(clock, actor, tuning, _make_world, PistaObjetos.BOX_ID, 1, HOLD_SESSION, _connection,
			PistaObjetos.MODEL_REVISION):
		note = "No se pudo vincular la caja: %s" % _adapter.last_error
		_factory_first = null
		_free_node(_adapter)
		_adapter = null
		return
	_channel = Channel.new()
	_channel.name = "Canal"
	_channel.link = link
	add_child(_channel)
	if not _channel.start(_adapter.authority_scope(), peer_id):
		note = "No se pudo abrir el canal de la caja: %s" % _channel.last_error
		_drop_binding_nodes()
		return
	_journal = Journal.new()
	_journal.name = "Registro"
	add_child(_journal)
	if not _journal.start(_adapter, peer_id, _authorize):
		note = "No se pudo iniciar el registro del host."
		_drop_binding_nodes()
		return
	_peer = peer_id
	_publishing = false
	_revision = 0
	_applied_tick = -1
	bindings += 1
	_channel.closed.connect(func() -> void:
		if _peer == peer_id:
			_unbind_host.call_deferred("se cerró el canal (%s)" % _channel.last_error if _channel != null else "se cerró el canal"))
	_channel.action_requested.connect(_request_host_action)
	_journal.action_resolved.connect(_send_result)
	_adapter.recovery_required.connect(func(reason: String) -> void:
		last_recovery_reason = reason
		_diagnose("box_recovery", {"reason": reason})
		_unbind_host.call_deferred("el host perdió el input del invitado (%s)" % reason))
	# Después del adaptador y del registro: publica el tick ya simulado.
	clock.tick_finished.connect(_host_publish)
	note = "Pista de objetos: vinculando al jugador %d…" % peer_id
	print("[pista] host: vínculo %d con el jugador %d en el tick %d (base del mundo %d)" % [_connection, peer_id, clock.tick, _world_base])
	_diagnose("box_bound", {"guest_peer": peer_id, "base_tick": _world_base})
	_prepare.rpc_id(peer_id, _connection, PILOT_PROTOCOL_REVISION, _world_base)


@rpc("any_peer", "call_remote", "reliable")
func _guest_ready() -> void:
	var sender := multiplayer.get_remote_sender_id()
	_later(func() -> void:
		if role == Role.HOST and sender == _peer and _adapter != null:
			_publishing = true
			note = "Pista de objetos: el jugador %d tiene la caja." % sender)


func _unbind_host(reason: String) -> void:
	if role != Role.HOST or _peer == 0:
		return
	var peer := _peer
	_peer = 0
	_publishing = false
	if _journal != null:
		_journal.stop("unbound")
	if _channel != null and _channel.stats().bound:
		_channel.stop()
	if clock.tick_finished.is_connected(_host_publish):
		clock.tick_finished.disconnect(_host_publish)
	_drop_binding_nodes()
	# Lo que tenía en la mano se suelta y cae: el host no deja la caja en el aire.
	_catch_up_world()
	var sample: Dictionary = _world.sample(PistaObjetos.BOX_ID, 1)
	if not sample.is_empty() and sample.held:
		_world.release_body(PistaObjetos.BOX_ID, 1, Vector3.ZERO)
	note = "Pista de objetos: sin invitado (%s)." % reason
	print("[pista] host: fin del vínculo con el jugador %d en el tick %d: %s" % [peer, clock.tick, reason])
	_diagnose("box_unbound", {"guest_peer": peer, "reason": reason})
	# Si sigue conectado, puede volver a vincularse desde el estado de ahora.
	if peer in multiplayer.get_peers():
		_offer_to(peer)


func _drop_binding_nodes() -> void:
	if _adapter != null:
		for connection in [[clock.tick_finished, _adapter._after_tick], [clock.hard_resynced, _adapter._hard_resynced]]:
			if (connection[0] as Signal).is_connected(connection[1]):
				(connection[0] as Signal).disconnect(connection[1])
	if _journal != null and clock.tick_finished.is_connected(_journal._after_tick):
		clock.tick_finished.disconnect(_journal._after_tick)
	for node in [_journal, _channel, _adapter]:
		_free_node(node)
	_journal = null
	_channel = null
	_adapter = null


func _free_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()


## Host, sin vínculo: el mundo de la caja sigue al reloj (la caja cae y se duerme).
func _host_free_step(tick: int) -> void:
	if _adapter != null and _adapter.ready_for_input:
		return
	_catch_up_world(tick)


func _catch_up_world(until := -1) -> void:
	if _world == null:
		return
	var target := clock.tick if until < 0 else until
	var guard := 0
	while _world.get_tick() < target and guard < 600:
		_world.step(SimClock.world_dt(_world.get_tick() + 1))
		guard += 1
	if _world.get_tick() < target:
		push_warning("[pista] el mundo de la caja quedó atrasado %d ticks" % (target - _world.get_tick()))


## Host: el input del invitado vinculado para este tick, antes de su paso (lo
## llama el laboratorio desde el proveedor de inputs del reloj). El registro
## programa la acción del tick y el adaptador guarda la copia para objetos.
func host_capture(actor: ActorBody, input: ActorInput, tick: int) -> void:
	if role != Role.HOST or _adapter == null or actor != _adapter.actor or input == null:
		return
	_journal.before_capture(tick)
	var copy := object_input(input)
	var repeated := sync.used_input_tick(actor.owner_peer_id) != tick
	if _journal.stats().inflight != 0 or repeated and _world.sample(PistaObjetos.BOX_ID, 1).get("held", false):
		inputs_repeated_with_box += int(repeated)
		if _journal.stats().inflight != 0:
			print("[pista] host: acción en el tick %d con el input %s (distancia de la mano %.3f m)" % [tick,
					"repetido del tick %d" % sync.used_input_tick(actor.owner_peer_id) if repeated else "de ese tick", copy.hold_distance()])
	if copy == null or not _adapter.capture(copy):
		last_recovery_reason = _adapter.last_error
		_unbind_host.call_deferred("no se pudo guardar el input del invitado (%s)" % _adapter.last_error)


func _host_publish(tick: int) -> void:
	if not _publishing or _adapter == null or _channel == null:
		return
	if tick % SNAPSHOT_EVERY != 0 and _applied_tick != tick:
		return
	_revision += 1
	var packet: Dictionary = _adapter.authority_scope()
	packet.merge({"version": 1, "tick": tick, "revision": _revision,
		"snapshot": _world.snapshot_trusted(), "acks": []})
	if not _channel.publish(packet):
		_unbind_host.call_deferred("no se pudo mandar el estado (%s)" % _channel.last_error)


func _request_host_action(action: Dictionary) -> void:
	if _journal == null:
		return
	_diagnose("host_action_received", {"id": action.id, "kind": action.kind, "requested_tick": action.tick})
	if action.tick > clock.tick + MAX_ACTION_LEAD:
		_diagnose("host_action_result", {"id": action.id, "status": "rejected", "reason": "action_tick_ahead"})
		_result.rpc_id(_peer, action.id, "rejected", -1, "El pedido se adelantó al reloj.")
		return
	var result: Dictionary = _journal.request(_peer, action)
	if result.status != "scheduled":
		_diagnose("host_action_result", result)
		_result.rpc_id(_peer, action.id, result.status, result.get("applied_tick", -1), result.reason)


## Host, en el tick en que se ejecuta la acción: lo mismo que la sala aprobada.
func _authorize(id: int, action: Dictionary, _tick: int) -> String:
	if id != _peer:
		return "Ese jugador no tiene la caja."
	if action.kind == "release":
		if action.impulse.length() > THROW_IMPULSE + 0.001:
			return "Impulso fuera de rango."
		return ""
	var bounds := AABB(-PistaObjetos.BOX_SIZE * 0.5, PistaObjetos.BOX_SIZE).grow(0.005)
	if not bounds.has_point(action.anchor) or action.impulse != Vector3.ZERO:
		return "Punto de agarre inválido."
	var pose: Transform3D = _world.sample(PistaObjetos.BOX_ID, 1).pose
	var point: Vector3 = pose * action.anchor
	var eyes := InvAuthority.eyes(_adapter.actor, BaseRegistry.world_position(_adapter.actor.state))
	if eyes.distance_to(point) > REACH + 0.25:
		return "La caja quedó fuera de alcance."
	if not _clear_path(eyes, point):
		return "Hay una pared entre vos y la caja."
	return ""


func _send_result(result: Dictionary) -> void:
	_diagnose("host_action_result", result)
	if result.status == "applied":
		_applied_tick = result.applied_tick
	if _peer != 0 and _peer in multiplayer.get_peers():
		_result.rpc_id(_peer, result.id, result.status, result.applied_tick, result.reason)


# --- Invitado: vínculo ----------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _prepare(connection: int, revision: int, base: int) -> void:
	_later(func() -> void: _bind_guest(connection, revision, base))


func _bind_guest(connection: int, revision: int, base: int) -> void:
	if role != Role.GUEST or revision != PILOT_PROTOCOL_REVISION:
		return
	_unbind_guest("")
	var actor: ActorBody = local_actor.call() if local_actor.is_valid() else null
	if actor == null or not actor.simulated or not clock.synced:
		# Todavía no: se vuelve a pedir cuando esté listo.
		_wants_bind = true
		_requested_msec = 0
		return
	_g0 = clock.tick
	_initial_base = _g0
	_base = base
	_adapter = Adapter.new()
	_adapter.authority_replay_limit = GUEST_AUTHORITY_REPLAY_LIMIT
	_adapter.name = "Adaptador"
	add_child(_adapter)
	if not _adapter.start(clock, actor, tuning, _make_world, PistaObjetos.BOX_ID, 1, HOLD_SESSION, connection,
			PistaObjetos.MODEL_REVISION):
		note = "No se pudo preparar la caja: %s" % _adapter.last_error
		_drop_guest_nodes()
		return
	_adapter.recovery_required.connect(func(reason: String) -> void:
		recoveries += 1
		last_recovery_reason = reason
		_diagnose("box_recovery", {"reason": reason, "count": recoveries}))
	_adapter.authority_sample_applied.connect(_on_authority_box_sample)
	_channel = Channel.new()
	_channel.name = "Canal"
	_channel.link = link
	add_child(_channel)
	if not _channel.start(_adapter.authority_scope(), 1):
		note = "No se pudo abrir el canal de la caja: %s" % _channel.last_error
		_drop_guest_nodes()
		return
	_history = History.new()
	_history.name = "Historia"
	_history.normalize = object_input
	add_child(_history)
	if not _history.start(_adapter, prediction, step_local):
		note = "No se pudo iniciar la predicción de la caja: %s" % _history.last_error
		_drop_guest_nodes()
		return
	_channel.closed.connect(func() -> void:
		_unbind_guest.call_deferred("se cerró el canal de la caja (%s)" % _channel.last_error if _channel != null else ""))
	# Después del adaptador y del registro de historia (los conectó start).
	clock.tick_finished.connect(_guest_after_tick)
	_connection = connection
	_ready_to_play = false
	_pend = {}
	_latest = {}
	_free_draw_samples.clear()
	_free_draw_tick = -1.0
	_shown_pose_ready = false
	_make_box_visual()
	box_visual.visible = false
	bindings += 1
	note = "Pista de objetos: esperando el primer estado de la caja…"
	print("[pista] invitado: vínculo %d en el tick %d (base del host %d)" % [connection, _g0, base])
	_diagnose("box_bound", {"base_tick": base})
	_guest_ready.rpc_id(1)


func _unbind_guest(reason: String) -> void:
	if role != Role.GUEST:
		return
	var had := _adapter != null
	if clock.tick_finished.is_connected(_guest_after_tick):
		clock.tick_finished.disconnect(_guest_after_tick)
	if _channel != null and _channel.stats().bound:
		_channel.stop()
	_drop_guest_nodes()
	_ready_to_play = false
	_clear_pending()
	_deferred_release = null
	_recovery_view_world = null
	_recovery_view_sample = {}
	if hands != null and hands.is_pilot_holding():
		hands.pilot_ended("")
	if box_visual != null:
		box_visual.visible = false
	if had and reason != "":
		note = "Pista de objetos: %s." % reason
		print("[pista] invitado: fin del vínculo en el tick %d: %s" % [clock.tick, reason])
		_diagnose("box_unbound", {"reason": reason})


func _drop_guest_nodes() -> void:
	if _adapter != null:
		for connection in [[clock.tick_finished, _adapter._after_tick], [clock.hard_resynced, _adapter._hard_resynced]]:
			if (connection[0] as Signal).is_connected(connection[1]):
				(connection[0] as Signal).disconnect(connection[1])
	if _history != null:
		for connection in [[clock.tick_finished, _history._tick_finished], [clock.hard_resynced, _history._reset_history]]:
			if (connection[0] as Signal).is_connected(connection[1]):
				(connection[0] as Signal).disconnect(connection[1])
	for node in [_history, _channel, _adapter]:
		_free_node(node)
	_history = null
	_channel = null
	_adapter = null


## Invitado: se cortó la conexión con el host (lo llama el laboratorio).
func connection_lost() -> void:
	_wants_bind = false
	active = false
	_unbind_guest("se cortó la conexión")


func guest_bound() -> bool:
	return role == Role.GUEST and _adapter != null and _history != null


## Invitado, al armar el input de este tick (antes del paso del personaje).
func guest_capture(input: ActorInput) -> void:
	if guest_bound() and input != null:
		if not _history.capture_input(input) and _history.last_error not in ["", "pending_input_capacity"]:
			last_recovery_reason = "captura: " + _history.last_error


## Invitado: llegó del host el estado del personaje propio. Con la pista
## vinculada, la corrección pasa por el registro de historia, que avisa al
## mundo de la caja. Devuelve si lo hizo (si no, lo hace el laboratorio).
func guest_reconcile(host_tick: int, state: PackedByteArray, used_tick: int, current_tick: int) -> bool:
	if not guest_bound() or host_tick >= current_tick:
		return false
	_history.reconcile_actor(host_tick, state, used_tick, current_tick)
	return true


## Invitado: repetir ticks del personaje desde uno anterior (un evento o una
## cámara lenta que llegaron tarde), avisando al mundo de la caja. Devuelve
## null si la pista no está vinculada (lo hace el laboratorio).
func guest_replay_from(first: int, current_tick: int, cause: String) -> Variant:
	if not guest_bound():
		return null
	return _history.replay_actor_from(first, current_tick, cause)


## Invitado, al terminar cada tick, después del adaptador y de la historia: lo
## de scene_network_bridge.after_actor_tick, más los pedidos pendientes.
func _guest_after_tick(tick: int) -> void:
	if not guest_bound():
		return
	var packet: Dictionary = _channel.take_packet()
	if not packet.is_empty():
		if packet.tick < _g0:
			# Anterior al vínculo: no hay historia propia para repetir desde ahí.
			authorities_skipped_old += 1
		elif _pend.is_empty() or packet.tick == _pend.tick:
			_pend = packet
		else:
			_latest = packet
	if not _pend.is_empty() and clock.tick == _history.stats().actor_tick:
		if not _latest.is_empty() and _latest.tick <= clock.tick:
			_pend = _latest
			_latest = {}
		if _pend.tick <= clock.tick and _history.actor_baseline_ready:
			var applying := _pend
			_pend = _latest
			_latest = {}
			var was_ready: bool = _adapter.ready_for_input
			var before: Dictionary = _adapter.world.sample(PistaObjetos.BOX_ID, 1) if was_ready else {}
			var started := Time.get_ticks_usec()
			var steps: int = clock.tick - int(applying.tick)
			var applied: bool = _history.apply_authority_trusted(applying)
			var spent := Time.get_ticks_usec() - started
			if applied:
				_recovery_view_sample = {}
				authorities_applied += 1
				apply_usec_max = maxi(apply_usec_max, spent)
				apply_usec_sum += spent
				apply_steps_max = maxi(apply_steps_max, steps)
				if not before.is_empty():
					var after: Dictionary = _adapter.world.sample(PistaObjetos.BOX_ID, 1)
					if not after.is_empty() and int(after.tick) == int(before.tick):
						last_box_correction = (before.pose as Transform3D).origin.distance_to((after.pose as Transform3D).origin)
						box_corrections += 1
						box_correction_sum += last_box_correction
						box_correction_max = maxf(box_correction_max, last_box_correction)
			else:
				authorities_rejected += 1
				last_recovery_reason = "estado rechazado: " + _history.last_error
				if _history.last_error == "replay_budget":
					_update_recovery_view(applying)
			if diagnostic_event.has_connections():
				_diagnose("box_snapshot", {
					"authority_tick": applying.tick, "revision": applying.revision,
					"age_ticks": steps, "replay_limit": _adapter.authority_replay_limit,
					"applied": applied, "apply_usec": spent,
					"reason": "" if applied else _history.last_error,
					"ready_before": was_ready, "ready_after": _adapter.ready_for_input,
				})
	if clock.tick != _history.stats().actor_tick:
		return
	if not _ready_to_play and _adapter.last_authority().tick >= 0:
		_ready_to_play = true
		note = ""
	var confirmed_tick: int = _adapter.last_authority().tick
	if _pending_kind == "release" and not _recovery_view_sample.get("held", true):
		confirmed_tick = maxi(confirmed_tick, _recovery_view_sample.tick)
	if _pending_id != 0 and _guest_applied_tick >= 0 and confirmed_tick >= _guest_applied_tick:
		_diagnose("guest_action_confirmed", {
			"id": _pending_id, "kind": _pending_kind, "host_tick": _guest_applied_tick,
			"wait_ms": Time.get_ticks_msec() - _pending_since,
		})
		_clear_pending()
	_flush_deferred_release()
	_check_hand(tick)


## Invitado: la mano de InvHands y la caja de este mundo tienen que decir lo
## mismo. Si la caja ya no está en la mano (el host la soltó), la mano la deja.
## Si quedó muy lejos de los ojos (se trabó en la puerta), se pide soltarla.
func _check_hand(_tick: int) -> void:
	if not _ready_to_play or _pending_id != 0 or not _adapter.ready_for_input:
		return
	var sample: Dictionary = _adapter.world.sample(PistaObjetos.BOX_ID, 1)
	if sample.is_empty():
		return
	if hands != null and hands.is_pilot_holding() and not sample.held:
		hands.pilot_ended("Se te soltó la caja")
		return
	if sample.held and hands != null and not hands.is_pilot_holding() and _deferred_release == null:
		# Se soltó en la mano mientras no se podía pedir: se pide ahora.
		_send_release(Vector3.ZERO)
		return
	if sample.held and hands != null and hands.is_pilot_holding():
		var values := hands.pilot_hold_values()
		var high := maxf(tuning.hold_max_distance, tuning.hold_min_distance)
		var anchor_world: Vector3 = (sample.pose as Transform3D) * _grab_preview_anchor
		var eyes := InvAuthority.eyes(_adapter.actor, BaseRegistry.world_position(_adapter.actor.state))
		if eyes.distance_to(anchor_world) > high + tuning.hold_break_distance and values.size() == 2:
			far_releases += 1
			hands.pilot_ended("Se te soltó la caja: quedó muy lejos")
			_send_release(Vector3.ZERO)


func _clear_pending() -> void:
	_pending_id = 0
	_pending_kind = ""
	_guest_applied_tick = -1


@rpc("authority", "call_remote", "reliable")
func _result(id: int, status: String, tick: int, reason: String) -> void:
	_later(func() -> void: _on_result(id, status, tick, reason))


func _on_result(id: int, status: String, tick: int, reason: String) -> void:
	_diagnose("guest_action_result", {
		"id": id, "status": status, "host_tick": tick, "reason": reason, "matches_pending": id == _pending_id,
	})
	if role != Role.GUEST or id != _pending_id:
		return
	results[status] = results.get(status, 0) + 1
	if status == "applied":
		_guest_applied_tick = tick
		note = ""
		_flush_deferred_release()
		return
	var kind := _pending_kind
	_clear_pending()
	_settle_grab_preview()
	note = "Pedido rechazado: " + reason
	if kind == "grab":
		_deferred_release = null
		if hands != null and hands.is_pilot_holding():
			hands.pilot_ended("No se agarró la caja: " + reason)


# --- Invitado: lo que pide InvHands ------------------------------------------------

## Si la mano de este jugador usa la mano de la pista en su input.
func hold_input_active() -> bool:
	return guest_bound()


## Si la caja ocupa la mano (pedido en viaje o en la mano): la mano no agarra
## otra cosa del inventario mientras tanto.
func busy() -> bool:
	if not guest_bound():
		return false
	if _pending_id != 0 or _deferred_release != null:
		return true
	var sample: Dictionary = _adapter.world.sample(PistaObjetos.BOX_ID, 1)
	return not sample.is_empty() and sample.held


## La mano apunta: si la mira pasa por la caja dibujada, se ocupa la pista.
## {}: no la mira (sigue el inventario). {"ok": false, "reason"}: la mira pero
## no se puede. {"ok": true, "distance", "rotation"}: salió el pedido.
func try_grab(from: Vector3, look: Vector3) -> Dictionary:
	var answer := _try_grab(from, look)
	last_refusal = answer.get("reason", "") if not answer.get("ok", true) else ""
	if last_refusal != "":
		_diagnose("guest_action_blocked", {"kind": "grab", "reason": last_refusal})
	return answer


func _try_grab(from: Vector3, look: Vector3) -> Dictionary:
	if not active or box_visual == null or not box_visual.visible:
		return {}
	var pose := box_visual.global_transform
	var inverse := pose.affine_inverse()
	var local_box := AABB(-PistaObjetos.BOX_SIZE * 0.5, PistaObjetos.BOX_SIZE)
	var hit: Variant = local_box.intersects_segment(inverse * from, inverse * (from + look.normalized() * (REACH + 4.0)))
	if hit == null:
		return {}
	var anchor: Vector3 = hit
	var point := pose * anchor
	if role != Role.GUEST:
		return {"ok": false, "reason": "La caja de la pista la mueve el invitado (piloto)."}
	if not guest_bound() or not _ready_to_play:
		return {"ok": false, "reason": "La caja todavía no está lista."}
	var eyes := _view_eyes()
	if eyes.distance_to(point) > REACH:
		return {"ok": false, "reason": "Acercate más a la caja."}
	if not _clear_path(eyes, point):
		return {"ok": false, "reason": "Hay algo entre vos y la caja."}
	if _pending_id != 0 or _deferred_release != null or not _adapter.ready_for_input:
		return {"ok": false, "reason": "Esperando al host…"}
	var sample: Dictionary = _adapter.world.sample(PistaObjetos.BOX_ID, 1)
	if sample.is_empty() or sample.held:
		return {"ok": false, "reason": "Esperando al host…"}
	if not _send_action("grab", anchor, Vector3.ZERO):
		return {"ok": false, "reason": note}
	_grab_preview = true
	_grab_preview_anchor = anchor
	_grab_handoff_remaining = 0.0
	_loose_draw_remaining = 0.0
	note = "Agarrando…"
	var yaw := camera.yaw if camera != null else 0.0
	return {"ok": true, "distance": clampf(eyes.distance_to(point), tuning.hold_min_distance, tuning.hold_max_distance),
		"rotation": (Basis(Vector3.UP, -yaw) * pose.basis).get_rotation_quaternion()}


## La mano suelta (`direction` cero) o lanza hacia `direction`. Si el agarre
## todavía espera la respuesta del host, la suelta queda pendiente de él.
func release(direction: Vector3, throwing: bool) -> void:
	if not guest_bound() or (_pending_id != 0 and _pending_kind != "grab"):
		return
	_deferred_release = direction.normalized() * THROW_IMPULSE if throwing and direction != Vector3.ZERO else Vector3.ZERO
	_flush_deferred_release()


func _flush_deferred_release() -> void:
	if _deferred_release == null or (_pending_id != 0 and (_pending_kind != "grab" or _guest_applied_tick < 0)):
		return
	var grab_id := _pending_id
	if _send_release(_deferred_release):
		_deferred_release = null
		if grab_id != 0:
			deferred_releases += 1
			_diagnose("guest_grab_followed_by_release", {"grab_id": grab_id, "release_id": _pending_id})


func _send_release(impulse: Vector3) -> bool:
	# El host valida la suelta aun si el invitado está recuperando su predicción.
	if not _send_action("release", Vector3.ZERO, impulse):
		return false
	note = "Esperando al host."
	return true


func _send_action(kind: String, anchor: Vector3, impulse: Vector3) -> bool:
	_serial += 1
	# El tick que sigue en el reloj de este jugador, el de la mano que va a llevar
	# el input. Como mucho MAX_ACTION_LEAD ticks por delante del presente del host
	# (el reloj sabe cuánto va adelante). En la sala se acotaba contra el último
	# estado aplicado del host: con 100 ms o más de ida y vuelta ese tick ya había
	# pasado acá, y el host agarraba con la mano de antes del clic (la caja salía
	# disparada unos 80 cm y volvía) y soltaba antes de lo pedido.
	var host_now := clock.tick - ceili(maxf(clock.lead_ticks, 0.0))
	var tick: int = mini(clock.tick + 1, host_now + MAX_ACTION_LEAD)
	var action := {"id": _serial, "tick": tick, "kind": kind, "anchor": anchor, "impulse": impulse}
	if not _channel.request_action(action):
		note = _channel.last_error
		return false
	_pending_id = _serial
	_pending_kind = kind
	_guest_applied_tick = -1
	_pending_since = Time.get_ticks_msec()
	_diagnose("guest_action_sent", {
		"id": _serial, "kind": kind, "requested_tick": tick, "throw": impulse != Vector3.ZERO,
	})
	return true


func _clear_path(eyes: Vector3, point: Vector3) -> bool:
	if eyes.distance_squared_to(point) < 0.0001:
		return true
	var space := pista.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(eyes, point, InvAuthority.WORLD_MASK)).is_empty()


## Los ojos con el personaje como se dibuja (el desvío de las correcciones y la
## interpolación incluidos), como la cámara del laboratorio.
func _view_eyes() -> Vector3:
	var actor: ActorBody = _adapter.actor if _adapter != null else (local_actor.call() if local_actor.is_valid() else null)
	if actor == null:
		return Vector3.ZERO
	return InvAuthority.eyes(actor, actor.visual_root().get_global_transform_interpolated().origin)


# --- Lo que se ve ------------------------------------------------------------------

func _process(delta: float) -> void:
	if role == Role.GUEST:
		_guest_process()
	if box_visual == null:
		return
	var sample := {}
	if role == Role.HOST and _world != null:
		sample = _world.sample(PistaObjetos.BOX_ID, 1)
	elif guest_bound() and not _recovery_view_sample.is_empty():
		sample = _recovery_view_sample
	elif guest_bound() and _ready_to_play:
		sample = _adapter.world.sample(PistaObjetos.BOX_ID, 1)
	if sample.is_empty():
		return
	box_visual.visible = true
	_present_box(sample, delta)


func _guest_process() -> void:
	if _wants_bind and not guest_bound():
		var actor: ActorBody = local_actor.call() if local_actor.is_valid() else null
		var now := Time.get_ticks_msec()
		if actor != null and actor.simulated and clock.synced and (_requested_msec == 0 or now - _requested_msec > 3000):
			_requested_msec = now
			_request.rpc_id(1)
	if guest_bound() and _pending_id != 0 and Time.get_ticks_msec() - _pending_since > PENDING_TIMEOUT_MS:
		var kind := _pending_kind
		_diagnose("guest_action_timeout", {"id": _pending_id, "kind": kind})
		_clear_pending()
		results.expired += 1
		_settle_grab_preview()
		note = "Se venció el pedido. Mirá la caja antes de reintentar."
		if kind == "grab":
			_deferred_release = null
			if hands != null and hands.is_pilot_holding():
				hands.pilot_ended("No se agarró la caja: el host no respondió")


func _diagnose(event: String, fields: Dictionary) -> void:
	if diagnostic_event.has_connections():
		diagnostic_event.emit(event, fields.merged({"connection": _connection}))


func diagnostic_state() -> Dictionary:
	return {
		"connection": _connection if _adapter != null else 0,
		"ready": _adapter != null and _adapter.ready_for_input,
		"pending_id": _pending_id, "pending_kind": _pending_kind,
		"deferred_release": _deferred_release != null,
		"recovery_view_tick": _recovery_view_sample.get("tick", -1),
		"recovery_view_held": _recovery_view_sample.get("held", false),
		"recovery_hand": _recovery_drew_hand,
		"published_revision": _revision,
		"applied": authorities_applied, "rejected": authorities_rejected,
		"skipped_old": authorities_skipped_old, "recoveries": recoveries,
		"last_recovery_reason": last_recovery_reason,
		"last_correction_m": last_box_correction,
		"repeated_inputs": inputs_repeated_with_box,
		"transport": _channel.stats() if _channel != null else {},
	}


## Una línea para el panel del laboratorio.
func status_text() -> String:
	if not active and note == "":
		return ""
	var line := "Pista de objetos: "
	match role:
		Role.HOST:
			line += "host, %s" % ("invitado %d vinculado" % _peer if _peer != 0 else "sin invitado")
		Role.GUEST:
			if not guest_bound():
				line += "sin vincular"
			elif not _ready_to_play:
				line += "esperando el primer estado de la caja"
			elif not _adapter.ready_for_input:
				line += "recuperando el estado de la caja"
				if not _recovery_view_sample.is_empty():
					line += " (en el host: %s)" % ("en mano" if _recovery_view_sample.held else "libre")
			else:
				var sample: Dictionary = _adapter.world.sample(PistaObjetos.BOX_ID, 1)
				line += "caja en mano" if sample.get("held", false) else "caja libre"
			line += "   ·   estados del host %d (corrección de la caja: última %.3f m, máx. %.3f m)   ·   recuperaciones %d" % [
				authorities_applied, last_box_correction, box_correction_max, recoveries]
	if note != "":
		line += "\n" + note
	return line


func _present_box(sample: Dictionary, delta: float) -> void:
	var pose: Transform3D = sample.pose
	if not _shown_pose_ready:
		box_visual.global_transform = pose
		_shown_pose_ready = true
		return
	var guest := role == Role.GUEST
	var held_locally: bool = guest and sample.held and _adapter.ready_for_input
	# Recuperando, con la caja en la mano en el host: se dibuja en la mano propia,
	# no donde la tenía el host (más de medio segundo atrás con red mala).
	var held_recovering: bool = guest and sample.held and not _adapter.ready_for_input
	_recovery_drew_hand = held_recovering
	var follow_rate := 35.0
	var draw_free_from_host: bool = guest and not sample.held and not _free_draw_samples.is_empty()
	if _grab_preview and (held_locally or not _adapter.ready_for_input):
		_settle_grab_preview()
	if draw_free_from_host:
		pose = _free_box_view_pose(delta)
	if held_recovering:
		pose = _recovery_hand_pose(box_visual.global_transform)
		follow_rate = 100.0
	elif _grab_preview or (held_locally and (sample.contacts as Array).is_empty()):
		var goal := _live_held_box_pose()
		var offset := goal.origin - pose.origin
		var spin := (goal.basis * pose.basis.transposed()).get_rotation_quaternion()
		pose = _held_view_pose(pose, offset, spin, _grab_preview)
		follow_rate = 65.0
		if held_locally:
			follow_rate = 100.0
	var shown := box_visual.global_transform
	if held_locally and _grab_handoff_remaining <= 0.0:
		if pose.origin.distance_squared_to(shown.origin) < HOLD_VISUAL_IDLE_OFFSET ** 2 \
				and pose.basis.get_rotation_quaternion().angle_to(shown.basis.get_rotation_quaternion()) < HOLD_VISUAL_IDLE_ANGLE:
			_drew_box_held = true
			return
	if draw_free_from_host and not _grab_preview:
		if _drew_box_held:
			_loose_draw_from = shown
			_loose_draw_remaining = GRAB_HANDOFF_TIME
		if _loose_draw_remaining > 0.0:
			var progress := 1.0 - _loose_draw_remaining / GRAB_HANDOFF_TIME
			pose = _loose_draw_from.interpolate_with(pose, smoothstep(0.0, 1.0, progress))
			_loose_draw_remaining = maxf(0.0, _loose_draw_remaining - delta)
	elif sample.held:
		_loose_draw_remaining = 0.0
	_drew_box_held = sample.held
	if _grab_handoff_remaining > 0.0:
		_grab_handoff_remaining = maxf(0.0, _grab_handoff_remaining - delta)
		var progress := 1.0 - _grab_handoff_remaining / GRAB_HANDOFF_TIME
		pose = _grab_handoff_from.interpolate_with(pose, smoothstep(0.0, 1.0, progress))
	elif not draw_free_from_host or _grab_preview:
		pose = shown.interpolate_with(pose, 1.0 - exp(-delta * follow_rate))
	if draw_free_from_host and not _grab_preview:
		pose = _free_box_contact_pose(pose)
	box_visual.global_transform = pose


## Invitado recuperando con la caja en la mano del host: la meta de la mano
## propia (la cámara de ahora), sin atravesar el nivel. La caja se lleva desde
## los ojos hacia la meta y se frena en lo primero que toca, como cuando la
## mano la aprieta contra el piso o una pared. Si ya en los ojos tocaría algo
## (pegado a una pared), va a la meta solo si ahí hay lugar. No simula la caja:
## los choques que solo pasan en el host se ven cuando vuelve la predicción.
func _recovery_hand_pose(shown: Transform3D) -> Transform3D:
	var goal := _live_held_box_pose()
	var space := pista.get_world_3d().direct_space_state
	_box_view_query.shape = _box_view_shape
	_box_view_query.margin = 0.0
	_box_view_query.motion = Vector3.ZERO
	var start := Transform3D(goal.basis, _view_eyes())
	_box_view_query.transform = start
	if not space.intersect_shape(_box_view_query, 1).is_empty():
		_box_view_query.transform = goal
		return goal if space.intersect_shape(_box_view_query, 1).is_empty() else shown
	var motion := goal.origin - start.origin
	if motion.is_zero_approx():
		return start
	_box_view_query.motion = motion
	var fraction: float = space.cast_motion(_box_view_query)[0]
	_box_view_query.motion = Vector3.ZERO
	return Transform3D(goal.basis, start.origin + motion * fraction)


func _live_held_box_pose() -> Transform3D:
	var values := hands.pilot_hold_values() if hands != null else [DEFAULT_DISTANCE, Quaternion.IDENTITY]
	var yaw := camera.yaw if camera != null else 0.0
	var pitch := camera.pitch if camera != null else DEFAULT_PITCH
	var goal := InvHoldMotion.target(_view_eyes(), yaw, pitch, values[0], values[1], tuning)
	goal.origin -= goal.basis * _grab_preview_anchor
	return goal


func _on_authority_box_sample(sample: Dictionary) -> void:
	if sample.held:
		_free_draw_samples.clear()
		_free_draw_tick = -1.0
		return
	if not _free_draw_samples.is_empty() and sample.tick <= _free_draw_samples[-1].tick:
		return
	_free_draw_samples.append(sample)
	if _free_draw_samples.size() > MAX_FREE_DRAW_SAMPLES:
		_free_draw_samples.pop_front()


## Un estado demasiado viejo para repetir la simulación todavía puede
## dibujar la caja. Este mundo se usa solo para leer la pose del host.
func _update_recovery_view(packet: Dictionary) -> void:
	if packet.tick <= _recovery_view_sample.get("tick", -1):
		return
	if _recovery_view_world == null:
		_recovery_view_world = _new_world(_base)
	if _recovery_view_world == null or not _recovery_view_world.restore_trusted(packet.snapshot):
		return
	if _recovery_view_world.get_tick() != packet.tick:
		return
	var sample: Dictionary = _recovery_view_world.sample(PistaObjetos.BOX_ID, 1)
	if not sample.is_empty():
		_recovery_view_sample = sample
		_on_authority_box_sample(sample)


func _free_box_view_pose(delta: float) -> Transform3D:
	var first: int = _free_draw_samples[0].tick
	var latest: int = _free_draw_samples[-1].tick
	var desired := maxf(first, latest - FREE_DRAW_BUFFER_TICKS)
	var rate := clampf(1.0 + (desired - _free_draw_tick) * 0.1, 0.75, 1.25)
	_free_draw_tick = clampf(_free_draw_tick + delta * SimClock.TICK_RATE * rate, first, latest)
	while _free_draw_samples.size() > 1 and float(_free_draw_samples[1].tick) <= _free_draw_tick:
		_free_draw_samples.pop_front()
	var from: Transform3D = _free_draw_samples[0].pose
	if _free_draw_samples.size() < 2:
		return from
	var to: Transform3D = _free_draw_samples[1].pose
	var fraction: float = (_free_draw_tick - _free_draw_samples[0].tick) / (_free_draw_samples[1].tick - _free_draw_samples[0].tick)
	return from.interpolate_with(to, clampf(fraction, 0.0, 1.0))


func _free_box_contact_pose(pose: Transform3D) -> Transform3D:
	var vertical_axes := Vector3(pose.basis.x.y, pose.basis.y.y, pose.basis.z.y)
	var bottom := pose.origin.y - vertical_axes.abs().dot(PistaObjetos.BOX_SIZE * 0.5)
	var lift := 0.0
	for support in _free_supports:
		var depth := support.end.y - bottom
		# Solo contactos superficiales con la cara de arriba: una caja que cae
		# junto al bloque puede pasar por su costado.
		if depth > 0.0 and depth <= FREE_SUPPORT_MAX_DEPTH:
			lift = maxf(lift, _box_support_lift(pose, support, depth))
	pose.origin.y += lift
	return pose


func _box_support_lift(pose: Transform3D, support: AABB, lift: float) -> float:
	var world_axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var box_axes := [pose.basis.x, pose.basis.y, pose.basis.z]
	var axes := world_axes + box_axes
	for world_axis: Vector3 in world_axes:
		for box_axis: Vector3 in box_axes:
			axes.append(world_axis.cross(box_axis))
	# Ejes de separación de las dos cajas: por cada solapamiento, cuánto hay que
	# subir para separarlas en ese eje; queda la salida más corta.
	var center_offset := pose.origin - support.get_center()
	var half_support := support.size * 0.5
	var inverse_basis := pose.basis.transposed()
	for axis: Vector3 in axes:
		if axis.length_squared() < 0.00000001:
			continue
		var radius := half_support.dot(axis.abs()) + (PistaObjetos.BOX_SIZE * 0.5).dot((inverse_basis * axis).abs())
		var separation := center_offset.dot(axis)
		if absf(separation) >= radius:
			return 0.0
		if absf(axis.y) > 0.0001:
			lift = minf(lift, (radius - separation * signf(axis.y)) / absf(axis.y))
	return lift


func _settle_grab_preview() -> void:
	if not _grab_preview:
		return
	_grab_preview = false
	_grab_handoff_from = box_visual.global_transform
	_grab_handoff_remaining = GRAB_HANDOFF_TIME


func _held_view_pose(pose: Transform3D, offset: Vector3, spin: Quaternion, preview := false) -> Transform3D:
	var turn := spin.angle_to(Quaternion.IDENTITY)
	if offset.length_squared() < 0.000001 and turn < 0.001:
		return pose
	var space := pista.get_world_3d().direct_space_state
	_box_view_query.shape = _grab_preview_shape if preview else _box_view_shape
	_box_view_query.margin = 0.0 if preview else 0.005
	_box_view_query.transform = pose
	_box_view_query.motion = Vector3.ZERO
	if not space.intersect_shape(_box_view_query, 1).is_empty():
		return pose
	var limit := GRAB_PREVIEW_MAX_OFFSET if preview else HOLD_VISUAL_MAX_OFFSET
	var limited := offset.limit_length(limit)
	_box_view_query.motion = limited
	if not limited.is_zero_approx():
		var fraction := space.cast_motion(_box_view_query)[0]
		if fraction < 1.0:
			return pose
	if turn > HOLD_VISUAL_MAX_ANGLE:
		spin = Quaternion.IDENTITY.slerp(spin, HOLD_VISUAL_MAX_ANGLE / turn)
	var predicted := Transform3D(Basis(spin) * pose.basis, pose.origin + limited)
	_box_view_query.transform = predicted
	_box_view_query.motion = Vector3.ZERO
	return predicted if space.intersect_shape(_box_view_query, 1).is_empty() else pose


## Para las pruebas: la caja de este mundo ahora (invitado: la predicha; host:
## la de verdad), o vacío.
func box_sample() -> Dictionary:
	if role == Role.HOST and _world != null:
		return _world.sample(PistaObjetos.BOX_ID, 1)
	if guest_bound():
		return _adapter.world.sample(PistaObjetos.BOX_ID, 1)
	return {}


func ready_to_play() -> bool:
	return _ready_to_play and guest_bound() and _adapter.ready_for_input


func pending() -> bool:
	return _pending_id != 0 or _deferred_release != null
