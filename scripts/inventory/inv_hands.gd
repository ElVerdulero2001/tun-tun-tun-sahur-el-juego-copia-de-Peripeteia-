class_name InvHands
extends Node

## La mano del jugador local (desde el 2026-11-14): sostener un objeto suelto
## en el mundo, acercarlo, alejarlo, girarlo, soltarlo y lanzarlo. Sostener no
## es llevar algo con el cursor dentro del inventario (eso es de InvUI): el
## objeto sigue en el mundo, con su cuerpo, y no entra al inventario. Para
## guardarlo, E, como siempre.
##
## **Botones** (InvHandPrefs, panel Opciones con F3). Son acciones del Mapa de
## entrada, no números fijos:
##
## | Esquema | Agarra y suelta | Lanza |
## | --- | --- | --- |
## | Principales (de fábrica) | `objeto_agarrar` (botón derecho) | `objeto_lanzar` (izquierdo) |
## | Laterales | `objeto_agarrar_lateral` (lateral trasero, cerca de la palma: MOUSE_BUTTON_XBUTTON1) | `objeto_lanzar_lateral` (lateral delantero, cerca del cable: MOUSE_BUTTON_XBUTTON2) |
##
## Lo que Windows y Logitech llaman «Mouse 4» y «Mouse 5» son esos laterales
## (en Godot, XBUTTON1 = 8 y XBUTTON2 = 9); los números 4 y 5 de Godot son la
## rueda (MOUSE_BUTTON_WHEEL_UP y _DOWN). En Opciones se ve qué número llega al
## apretar cada botón.
##
## **Sostener:** alternar (de fábrica): un clic agarra y otro del mismo botón
## suelta sin lanzar. Mantener: agarra al apretar y suelta al soltar el botón.
## Lanzar suelta y lanza una vez; después, soltar el botón de agarrar (en
## mantener) no hace nada, y no se agarra otra cosa hasta otra pulsación.
##
## Mientras sostiene algo: `objeto_alejar` (rueda para arriba) lo aleja y
## `objeto_acercar` (rueda para abajo) lo acerca, de a Hold Wheel Step, entre
## Hold Min Distance y Hold Max Distance (Tuning; Hold Wheel Inverted lo da
## vuelta); `objeto_rotar` (botón central) mantenido hace que el mouse gire el
## objeto en vez de la cámara: de costado, alrededor del eje vertical de la
## vista; para arriba o abajo, del horizontal; con Shift de costado, del que va
## hacia adelante (Hold Rotate Sensitivity grados por píxel). Al soltarlo, el
## mouse vuelve a mirar. La rueda no hace zoom y el botón central no hace otra
## cosa, con o sin objeto. Sin objeto, la rueda hace zoom como siempre.
##
## **Prioridad**, explícita: primero las interfaces (inventario, Opciones,
## selector de la Q, menú, diálogos, un campo con el foco, el mouse suelto),
## después esta mano y después la cámara y el juego. La mano lee el mouse en
## _input, antes de que nada lo use (la cámara solo mira _unhandled_input), y
## se queda con lo que usa. Si una interfaz toma el mouse mientras sostiene, lo
## suelta sin lanzar antes de cederlo; también al perder la ventana, al morir,
## al cortarse la conexión y al cambiar las preferencias.
##
## **Lo que se ve:** en el host, el cuerpo de verdad. En un cliente, lo que
## sostiene se dibuja adelantado: donde lo pide la mano ahora, corrido por la
## diferencia que el host tenía en el último tick que contó (si allá está
## trabado contra una pared, acá también), y sin meterlo en una pared. Al
## soltarlo vuelve en un cuarto de segundo a lo que manda el host. Con mucha
## demora, al agarrar el objeto espera hasta que el host empieza a llevarlo.

## Un cuarto de segundo para volver de lo adelantado a lo que manda el host.
const BLEND_MSEC := 250
## Cuánto de la diferencia con el host se toma por tick (suaviza).
const CORRECTION_RATE := 0.25
## Ticks de la mano adelantada que se recuerdan, para comparar con lo del host.
const TARGET_TICKS := 240

var net: InvNet
var ui: InvUI
var camera: LabCamera
var tuning: ActorTuning
## Interfaces que, abiertas, se quedan con el mouse: func() -> bool. Las suma
## el laboratorio (el selector de la Q, Opciones, el menú).
var blockers: Array[Callable] = []
var actor: ActorBody
var prefs := InvHandPrefs.new()
## Dónde se guardan (las pruebas usan otro archivo, para no tocar el tuyo).
var prefs_path := InvHandPrefs.PATH
## Para las pruebas sin ventana (el mouse no se puede capturar): no mira si
## el mouse está capturado.
var ignore_mouse_mode := false
## Para las pruebas: cuántos eventos del mouse se quedó la mano.
var taken := 0
## Para las pruebas: cuántos pedidos salieron y cuántos agarres rechazó el host.
var grabs := 0
var releases := 0
var throws := 0
var refused := 0

var _uid := 0
var _session := 0
var _session_counter := 0
var _seq := 0
var _anchor := Vector3.ZERO
var _distance := 1.0
var _rotation := Quaternion.IDENTITY
var _confirmed := false
var _grab_session := 0  # mantener: la sesión que agarró el botón que sigue apretado
var _rotating := false
var _targets := {}  # tick -> pose pedida por la mano adelantada
var _offset := Vector3.ZERO
var _turn := Quaternion.IDENTITY
var _shown := Transform3D.IDENTITY
var _blend_uid := 0
var _blend_from := Transform3D.IDENTITY
var _blend_msec := 0
var _deaths := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if net != null:
		net.replica.answered.connect(_on_answered)
		net.replica.grabbed.connect(_on_grabbed)
		net.replica.hold_lost.connect(_on_hold_lost)
	if ui != null:
		ui.opened.connect(func() -> void: drop_hold("", true))


func activate(p_actor: ActorBody) -> void:
	actor = p_actor
	_deaths = actor.state.deaths if actor != null else -1
	drop_hold("", false)


## Lo que sostiene ahora (0: nada).
func held_uid() -> int:
	return _uid


func is_holding() -> bool:
	return _uid != 0


func is_rotating() -> bool:
	return _rotating


## En un cliente, lo que coloca esta mano y no InvBodies (lo sostenido, o lo
## que vuelve a lo del host); -1 nada.
func predicted_uid() -> int:
	if net == null or net.is_host():
		return -1
	if _uid != 0:
		return _uid
	return _blend_uid if _blend_uid != 0 else -1


func _active() -> bool:
	return net != null and net.started and is_instance_valid(actor) and actor.is_inside_tree()


## Si una interfaz tiene el mouse (o no se está jugando): la mano no hace nada.
func blocked() -> bool:
	if not _active() or (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not ignore_mouse_mode):
		return true
	if ui != null and (ui.is_open or ui.is_typing()):
		return true
	for blocker in blockers:
		if blocker.is_valid() and blocker.call():
			return true
	return false


## Cambia las preferencias (Opciones): lo sostenido se suelta antes, y se guardan.
func set_prefs(fresh: InvHandPrefs) -> void:
	drop_hold("", true)
	prefs = fresh
	_grab_session = 0
	_rotating = false
	prefs.save(prefs_path)


# --- Entrada ----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if blocked():
		return
	var actions := prefs.actions()
	var grab_action: StringName = actions[0]
	var throw_action: StringName = actions[1]
	if event is InputEventMouseMotion:
		if _rotating and _uid != 0:
			_rotate_by(event.relative, event.shift_pressed)
			_take()
		return
	# El botón central es solo para girar: con o sin objeto no hace otra cosa.
	if event.is_action(&"objeto_rotar"):
		_rotating = event.is_pressed() and _uid != 0
		_take()
		return
	if event.is_action_pressed(grab_action):
		if _uid != 0:
			if prefs.mode == InvHandPrefs.Mode.TOGGLE:
				release()
			_take()
		elif try_grab():
			_grab_session = _session if prefs.mode == InvHandPrefs.Mode.HOLD else 0
			_take()
		return
	if event.is_action_released(grab_action):
		if prefs.mode == InvHandPrefs.Mode.HOLD and _uid != 0 and _grab_session == _session:
			release()
			_take()
		_grab_session = 0
		return
	if event.is_action_pressed(throw_action):
		if _uid != 0:
			throw_held()
			_take()
		return
	if _uid != 0 and (event.is_action_pressed(&"objeto_alejar") or event.is_action_pressed(&"objeto_acercar")):
		var steps: float = event.factor if event.factor > 0.0 else 1.0
		var away := 1.0 if event.is_action_pressed(&"objeto_alejar") else -1.0
		if tuning != null and tuning.hold_wheel_inverted:
			away = -away
		var step := tuning.hold_wheel_step if tuning != null else 0.1
		_distance = clampf(_distance + away * step * steps, _min_distance(), _max_distance())
		_take()
		return
	# Mientras sostiene algo, ningún otro botón del mouse llega a la cámara.
	if _uid != 0 and event is InputEventMouseButton:
		_take()


## Gira lo que sostiene con el mouse: alrededor de los ejes de la vista.
func _rotate_by(motion: Vector2, third_axis: bool) -> void:
	var sensitivity := deg_to_rad(tuning.hold_rotate_sensitivity if tuning != null else 0.25)
	var yaw := Basis(Vector3.UP, camera.yaw)
	var view := yaw * Basis(Vector3.RIGHT, camera.pitch)
	var turn := Basis.IDENTITY
	if third_axis:
		turn = Basis(-view.z, motion.x * sensitivity)
	else:
		turn = Basis(view.x, -motion.y * sensitivity) * Basis(view.y, -motion.x * sensitivity)
	_rotation = (yaw.inverse() * turn * yaw * Basis(_rotation)).orthonormalized().get_rotation_quaternion()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Sin la ventana no se sabe qué botones siguen apretados: se suelta.
		drop_hold("", true)
		_rotating = false
		_grab_session = 0


func _process(_delta: float) -> void:
	if _uid != 0 and blocked():
		drop_hold("", true)
	if is_instance_valid(actor):
		if _deaths >= 0 and actor.state.deaths != _deaths and _uid != 0:
			drop_hold("Se te soltó: moriste", true)
		_deaths = actor.state.deaths
	if _uid == 0:
		_rotating = false


# --- Agarrar, soltar y lanzar -------------------------------------------------------

## Agarra lo que marca el rayo de la mano, si es un objeto suelto (no una caja)
## al alcance: el punto que toca es por donde se agarra. Sale el pedido al host
## y, mientras tanto, ya se ve en la mano. Devuelve si salió.
func try_grab() -> bool:
	if _uid != 0 or blocked() or camera == null:
		return false
	var aim := camera.aim_ray()
	var target := net.interaction_target(actor, aim[0], aim[1], camera.third_person())
	if target.get("kind", "") != "item" or not target.has("point"):
		return false
	var uid: int = target["id"]
	var place: Transform3D = target["place"]
	_session_counter += 1
	var session := _session_counter
	var seq := net.replica.request(InvProtocol.Op.GRAB, InvProtocol.grab_args(uid, target["direction"], net.aim_tick(),
			net.view_tick(), session), [uid])
	if seq == 0:
		return false
	grabs += 1
	_seq = seq
	_uid = uid
	_session = session
	_confirmed = false
	_anchor = place.affine_inverse() * (target["point"] as Vector3)
	_distance = clampf(target["distance"], _min_distance(), _max_distance())
	_rotation = (Basis(Vector3.UP, camera.yaw).inverse() * place.basis.orthonormalized()).get_rotation_quaternion()
	_targets.clear()
	_offset = Vector3.ZERO
	_turn = Quaternion.IDENTITY
	_shown = place
	_blend_uid = 0
	return true


## Lo suelta sin impulso.
func release() -> void:
	if _uid == 0:
		return
	net.replica.request(InvProtocol.Op.RELEASE, [_uid, _session])
	releases += 1
	_end_local()


## Lo suelta y lo lanza hacia donde mira la cámara.
func throw_held() -> void:
	if _uid == 0:
		return
	var direction: Vector3 = camera.aim_ray()[1]
	net.replica.request(InvProtocol.Op.THROW, InvProtocol.throw_args(_uid, _session, direction.normalized()))
	throws += 1
	_end_local()


## Deja de sostener: con `send`, le pide al host que lo suelte (sin impulso).
## Con `reason`, lo avisa.
func drop_hold(reason: String, send: bool) -> void:
	if _uid == 0:
		return
	if send and net != null and net.started:
		net.replica.request(InvProtocol.Op.RELEASE, [_uid, _session])
		releases += 1
	if reason != "" and ui != null:
		ui.say(reason)
	_end_local()


func _end_local() -> void:
	if _uid != 0 and net != null and not net.is_host() and net.world_view(_uid) != null:
		_blend_uid = _uid
		_blend_from = _shown
		_blend_msec = Time.get_ticks_msec()
	_uid = 0
	_session = 0
	_confirmed = false
	_rotating = false
	_targets.clear()


## Lo que va en el input de este tick (ActorInput.hold): vacío si no sostiene.
func hold_for_input() -> Array:
	if _uid == 0 or camera == null:
		return []
	return ActorInput.pack_hold(_session, camera.pitch, clampf(_distance, _min_distance(), _max_distance()), _rotation)


func _min_distance() -> float:
	return tuning.hold_min_distance if tuning != null else 0.6


func _max_distance() -> float:
	return maxf(tuning.hold_max_distance if tuning != null else 2.5, _min_distance())


func _on_answered(seq: int, ok: bool, reason: String) -> void:
	if seq != _seq or seq == 0:
		return
	_seq = 0
	if not ok:
		refused += 1
		if _uid != 0 and not _confirmed:
			# El host dijo que no: deja de verse en la mano (nunca la tuvo).
			if ui != null:
				ui.say("No se agarró: %s" % reason)
			_end_local()


func _on_grabbed(answer: Array) -> void:
	if answer[0] != _uid or answer[1] != _session:
		return
	_confirmed = true
	# El punto por donde agarró el host (con su copia del objeto): el mismo acá.
	_anchor = Vector3(answer[2], answer[3], answer[4])


func _on_hold_lost(uid: int, reason: String) -> void:
	if uid == _uid:
		if ui != null:
			ui.say("Se te soltó: %s" % reason)
		_end_local()


## Cambió lo que se ve del mundo (InvNet): si lo sostenido ya no está (se
## recogió, otro lo tiene), se deja. Si se recogió entero con E, además se le
## pide al host que lo suelte, después del pedido de recoger: si el host no lo
## deja recoger (no entra), queda suelto y cae, en vez de quedar en el aire.
func world_changed() -> void:
	if _uid == 0:
		return
	var item: Dictionary = net.replica.world.get(_uid, {})
	if item.is_empty():
		_end_local()
	elif net.replica.is_taken(_uid):
		drop_hold("", true)
	elif _confirmed and item.get("holder", 0) != multiplayer.get_unique_id():
		_end_local()


# --- Lo que se ve -------------------------------------------------------------------

## Al terminar cada tick, con el personaje propio ya movido: en un cliente,
## coloca lo que sostiene donde lo pide la mano (corrido por lo que dice el
## host) y lo que acaba de soltar, de vuelta a lo del host.
func after_tick(tick: int) -> void:
	if net == null or net.is_host() or not is_instance_valid(actor):
		_blend_uid = 0
		return
	if _uid != 0:
		_place_held(tick)
	elif _blend_uid != 0:
		_place_blend()


func _place_held(tick: int) -> void:
	var copy := net.world_view(_uid)
	if copy == null:
		return
	var wanted := _wanted_pose()
	_targets[tick] = wanted
	_targets.erase(tick - TARGET_TICKS)
	var newest := net.bodies.newest_sample(_uid)
	# Lo que el host hizo en un tick, comparado con lo que pidió esta mano en ese
	# mismo tick: si allá quedó trabado, la diferencia se lleva al presente.
	if newest.size() >= 5 and newest[4] and _targets.has(newest[0]):
		var asked: Transform3D = _targets[newest[0]]
		var real: Transform3D = newest[1]
		_offset = _offset.lerp(real * _anchor - asked * _anchor, CORRECTION_RATE)
		var turn := real.basis.orthonormalized().get_rotation_quaternion() \
				* asked.basis.orthonormalized().get_rotation_quaternion().inverse()
		_turn = _turn.slerp(turn.normalized(), CORRECTION_RATE)
	var basis := Basis(_turn) * wanted.basis
	var anchor_at := wanted * _anchor + _offset
	var shown := Transform3D(basis, anchor_at - basis * _anchor)
	var from: Transform3D = newest[1] if not newest.is_empty() else copy.global_transform
	shown = _keep_out_of_walls(from, shown, copy.def)
	copy.place(shown)
	net.bodies.shown.move(_uid, shown)
	_shown = shown


## Donde pide la mano que esté el objeto ahora: el punto agarrado en los ojos
## más la vista por la distancia, con el giro pedido sobre el yaw de la cámara.
## Con los mismos números redondeados que van en el input (los que usa el host).
func _wanted_pose() -> Transform3D:
	var input := ActorInput.make(0, Vector2.ZERO, camera.yaw, 0, 0)
	input.hold = hold_for_input()
	var eyes := InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state))
	var basis := Basis(Vector3.UP, input.look_yaw) * Basis(input.hold_rotation())
	var anchor_at := eyes + input.hold_look() * input.hold_distance()
	return Transform3D(basis, anchor_at - basis * _anchor)


## De `from` (lo que dice el host, que no está adentro de nada) hasta `to`: si
## en el camino hay una pared o una caja, se queda antes. Si ya arranca tocando
## algo (apoyado), vale `to` si `to` está libre.
func _keep_out_of_walls(from: Transform3D, to: Transform3D, def: InvItemDef) -> Transform3D:
	var motion := to.origin - from.origin
	if motion.length() < 0.001:
		return to
	var space := actor.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = InvAuthority.WORLD_MASK
	query.motion = motion
	var safe := 1.0
	var stuck := false
	for part: Array in InvItemPhysics.parts(def):
		query.shape = part[0]
		query.transform = Transform3D(to.basis, from.origin) * (part[1] as Transform3D)
		var result := space.cast_motion(query)
		if result.size() == 2:
			if result[0] <= 0.0 and result[1] <= 0.0:
				stuck = true
			else:
				safe = minf(safe, result[0])
	if stuck and safe >= 1.0:
		return to if InvItemPhysics.fits(space, def, to, InvAuthority.WORLD_MASK) else Transform3D(to.basis, from.origin)
	return Transform3D(to.basis, from.origin + motion * safe)


func _place_blend() -> void:
	var copy := net.world_view(_blend_uid)
	var t := (Time.get_ticks_msec() - _blend_msec) / float(BLEND_MSEC)
	if copy == null or t >= 1.0:
		_blend_uid = 0
		return
	var at: float = net.bodies.render_tick.call() if net.bodies.render_tick.is_valid() else -1.0
	var pose := net.bodies.sample_at(_blend_uid, at)
	if pose.is_empty():
		_blend_uid = 0
		return
	var shown := _blend_from.interpolate_with(pose[0], clampf(t, 0.0, 1.0))
	copy.place(shown)
	net.bodies.shown.move(_blend_uid, shown)


## Se queda con el evento: no llega a la cámara ni al juego.
func _take() -> void:
	taken += 1
	get_viewport().set_input_as_handled()
