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
## **Lo que se ve:** en el host, el cuerpo de verdad. En un cliente, desde el
## 2026-11-15 (docs/net/prompt_claude_revision_objetos_fisicos.md), lo que
## sostiene se predice acá, tick por tick, sin esperar al host:
##
## 1. En cada tick T (predict), con el personaje propio ya movido: el target
##    de la mano con el input de ese tick y las velocidades con las cuentas de
##    InvHoldMotion, las mismas que usa el host, desde lo predicho para T - 1.
## 2. El paso, como Jolt sin choques, después de mirar el nivel, las cajas y
##    las escaleras con las mismas reglas que el host (InvHoldMotion.guard: en
##    pasos de 1 cm de cualquier punto, también al girar sin moverse; si se
##    mete, se desliza por los ejes libres, gira solo o se queda). Los demás
##    objetos sueltos no tienen forma acá: eso lo decide el host.
## 3. Lo predicho se cuantiza como viaja y sale como afirmación con el input
##    de ese tick (claim_for, ActorInput.held_claim). Se guarda una historia de
##    HISTORY_TICKS ticks: lo predicho, el target y lo que ya se afirmó.
## 4. Cuando llega una pose del host del tick H (InvBodies, ya con su tick
##    verdadero y la versión de la sujeción), se compara con lo predicho para
##    H, el mismo instante (_reconcile). Con la misma versión no se corrige: el
##    host adopta o coincide con lo afirmado, y si difiere es que le faltó un
##    input y la afirmación todavía viaja (se cuenta en held_waits). Con otra
##    versión (el host rechazó una afirmación o pasó STALE_TICKS sin acuerdo),
##    se parte de lo del host en H y se repiten los ticks hasta el presente con
##    los targets guardados; lo que se ve va del lugar viejo al nuevo en
##    SMOOTH_TICKS.
##
## «No se ve» (desde la segunda prueba del usuario, 2026-11-15) lo decide esta
## máquina después de predecir cada tick (_check_hidden): tapado más de Hold
## Hidden Time, se suelta como con el botón.
##
## Al soltarlo o lanzarlo (_free), sigue adelantado: cae o sale lanzado desde
## donde estaba en la mano (con el impulso del lanzamiento), y cuando llegan las
## poses del host se corrige igual, llevándolas al presente; al quedar quieto
## (o a los FREE_TICKS) vuelve a verse como los demás objetos. Así no salta para
## atrás, a una pose vieja.
##
## Hasta ese día se dibujaba donde lo pedía la mano, corrido por la diferencia
## entre lo que hizo el host y lo que pidió la mano en un tick viejo (unos
## 100 ms), que no es el mismo instante, y sin mirar los giros sin
## desplazamiento: se atrasaba y se pasaba al parar
## (docs/net/problemas_objetos_fisicos_2026-11-14.md, punto 1).

## Un cuarto de segundo para volver de lo adelantado a lo que manda el host.
const BLEND_MSEC := 250
## Ticks que se recuerdan de la predicción de lo sostenido.
const HISTORY_TICKS := 120
## Lo que se acepta de diferencia con el host sin corregir (elegido por Claude
## el 2026-11-15): en el centro de masa y en el punto agarrado, en metros, y en
## el giro, en grados.
const CORRECT_POS := 0.01
const CORRECT_ANGLE := 1.5
## Una afirmación que salió y el host adoptó coincide con lo del host hasta acá.
const ADOPTED_POS := 0.002
const ADOPTED_ANGLE := 0.2
## En cuántos ticks lo que se ve va de lo viejo a lo corregido.
const SMOOTH_TICKS := 6
## Lo soltado se sigue adelantando como mucho esto, en ticks.
const FREE_TICKS := 120
## Como mucho, cuántos ticks se lleva una pose del host al presente.
const MAX_CATCH_UP := 30

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
## Para las pruebas: cuántas veces esta máquina soltó lo sostenido porque no se veía.
var hidden_releases := 0

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
var _shown := Transform3D.IDENTITY
var _blend_uid := 0
var _blend_from := Transform3D.IDENTITY
var _blend_msec := 0
var _deaths := -1
var _hidden := 0.0  # cliente: cuánto lleva tapado el punto agarrado (_check_hidden)

## Para medir (pruebas, panel): lo que pasó al comparar con el host.
var held_matches := 0
var held_version_resets := 0
var held_adopted_old := 0
## Poses del host que diferían con la misma versión: se esperó (no se corrigió).
var held_waits := 0
var max_held_correction := 0.0
var last_held_correction := 0.0

var _pred := {}  # tick -> [Transform3D, velocidad, velocidad de giro], cuantizado
var _goals := {}  # tick -> el target de la mano en ese tick
var _claims := {}  # tick -> lo que salió como afirmación de ese tick (bytes)
var _sent := {}  # tick -> [[Transform3D, velocidad, velocidad de giro], ...] afirmados
var _version := 0
var _checked := -1  # el último tick del host comparado
var _start_tick := -1  # el tick en que empezó a predecir esta sujeción
var _done_tick := -1  # el último tick predicho (predict)
var _smooth_pos := Vector3.ZERO
var _smooth_turn := Quaternion.IDENTITY
var _smooth_left := 0
## Lo soltado que se sigue adelantando: {"uid", "state" ([xf, lv, av]), "tick",
## "since" (tick en que se soltó), "checked"}, o vacío.
var _free := {}


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
	if not _free.is_empty():
		return _free["uid"]
	return _blend_uid if _blend_uid != 0 else -1


func _active() -> bool:
	# El cliente muestra al personaje antes de sincronizar su reloj. Hasta que
	# lo simula no manda inputs: dejar agarrar antes iniciaba una sujeción en el
	# host sin objetivos ni afirmaciones, y la copia se movía solo en el cliente.
	return net != null and net.started and is_instance_valid(actor) and actor.is_inside_tree() and actor.simulated \
			and (net.clock == null or not net.clock.client_sync or net.clock.synced)


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
	# Por donde tocó la forma de selección (la hitbox o el modelo), aunque caiga
	# en un hueco del modelo: un anclaje virtual (desde el 2026-11-15).
	_anchor = place.affine_inverse() * (target["point"] as Vector3)
	_distance = clampf(target["distance"], _min_distance(), _max_distance())
	_rotation = (Basis(Vector3.UP, camera.yaw).inverse() * place.basis.orthonormalized()).get_rotation_quaternion()
	_shown = place
	_blend_uid = 0
	_free = {}
	_pred.clear()
	_goals.clear()
	_sent.clear()
	_version = 0
	_checked = -1
	_start_tick = -1
	_smooth_left = 0
	return true


## Lo suelta sin impulso.
func release() -> void:
	if _uid == 0:
		return
	net.replica.request(InvProtocol.Op.RELEASE, InvProtocol.release_args(_uid, _session, net.aim_tick()))
	releases += 1
	_end_local()


## Lo suelta y lo lanza hacia donde mira la cámara.
func throw_held() -> void:
	if _uid == 0:
		return
	var direction: Vector3 = (camera.aim_ray()[1] as Vector3).normalized()
	net.replica.request(InvProtocol.Op.THROW, InvProtocol.throw_args(_uid, _session, direction, net.aim_tick()))
	throws += 1
	var copy := net.world_view(_uid) if net != null else null
	var impulse := direction * InvItemPhysics.throw_impulse_of(copy.def if copy != null else null, tuning)
	_end_local(impulse / InvItemPhysics.mass_of(copy.def if copy != null else null, tuning))


## Deja de sostener: con `send`, le pide al host que lo suelte (sin impulso).
## Con `reason`, lo avisa.
func drop_hold(reason: String, send: bool) -> void:
	if _uid == 0:
		return
	if send and net != null and net.started:
		net.replica.request(InvProtocol.Op.RELEASE, InvProtocol.release_args(_uid, _session, net.aim_tick()))
		releases += 1
	if reason != "" and ui != null:
		ui.say(reason)
	_end_local()


## Deja de sostener acá. En un cliente, lo soltado se sigue adelantando desde
## lo predicho (_free), con `push` sumado a su velocidad si se lanzó; si no hay
## predicción (el host todavía no lo agarraba), vuelve a lo del host en
## BLEND_MSEC.
func _end_local(push := Vector3.ZERO) -> void:
	var released: InvWorldItem = net.world_view(_uid) if net != null and _uid != 0 else null
	if released != null and not net.is_host():
		var last: Array = _pred.get(_done_tick, [])
		if _confirmed and not last.is_empty():
			_free = {"uid": _uid, "state": [last[0], (last[1] as Vector3) + push, last[2]], "tick": _done_tick,
					"since": _done_tick, "checked": _checked}
			_blend_uid = 0
		else:
			_blend_uid = _uid
			_blend_from = _shown
			_blend_msec = Time.get_ticks_msec()
	_uid = 0
	_session = 0
	_confirmed = false
	_rotating = false
	_hidden = 0.0
	_pred.clear()
	_goals.clear()
	_sent.clear()
	if released != null and not _free.is_empty():
		# Soltar cambia el controlador y el pivote, no la pose que se veía.
		# Cancelar el suavizado acá hacía saltar al estado crudo en el primer
		# tick de caída si todavía quedaba una corrección de la mano pendiente.
		_start_smoothing(_shown, _free["state"][0], InvItemPhysics.center_of_mass(released.def))
	else:
		_smooth_left = 0


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

## Al terminar cada tick, con el personaje propio ya movido. En un cliente, si
## predict() no corrió en este tick (el laboratorio lo llama antes de mandar el
## input), lo hace acá con un input armado con la cámara de ahora.
func after_tick(tick: int) -> void:
	if net == null or net.is_host() or not is_instance_valid(actor):
		_blend_uid = 0
		_free = {}
		return
	if _done_tick != tick:
		predict(tick, null)


## Cliente, en el tick `tick`: predice lo sostenido con el input de ese tick
## (`input`, el que sale al host; null: uno con la cámara de ahora), lo
## compara con lo último del host, deja su afirmación para claim_for y lo
## coloca. Lo soltado que se sigue adelantando y lo que vuelve a lo del host,
## también. Una vez por tick.
func predict(tick: int, input: ActorInput) -> void:
	if not _active() or net.is_host() or _done_tick == tick:
		return
	_done_tick = tick
	if _uid != 0:
		_predict_held(tick, input)
	elif not _free.is_empty():
		_predict_free(tick)
	elif _blend_uid != 0:
		_place_blend()
	_forget_before(tick - HISTORY_TICKS)


## En una línea, cómo le fue a la predicción de lo sostenido (panel y pruebas).
func prediction_text() -> String:
	return "coincidió %d, afirmación vieja adoptada %d, esperó %d, corregida por versión nueva %d (la corrección más grande %.3f m)" % [
			held_matches, held_adopted_old, held_waits, held_version_resets, max_held_correction]


## Lo que esta máquina afirmó de lo que sostenía después del tick `tick`
## (InvHoldMotion.pack_claim), o vacío. Lo pone el laboratorio en el input de
## ese tick (ActorInput.held_claim) cada vez que lo manda: si una corrección
## cambió lo predicho, sale lo nuevo.
func claim_for(tick: int) -> PackedByteArray:
	return _claims.get(tick, PackedByteArray())


func _predict_held(tick: int, input: ActorInput) -> void:
	var copy := net.world_view(_uid)
	if copy == null:
		return
	var def := copy.def
	var com := InvItemPhysics.center_of_mass(def)
	if input == null or input.hold.size() != 7:
		input = ActorInput.make(tick, Vector2.ZERO, camera.yaw, 0, 0)
		input.hold = hold_for_input()
	if _start_tick < 0:
		# Empieza donde se ve, quieto (lo de antes del agarre lo corrige el host).
		_start_tick = tick
		_pred[tick - 1] = InvHoldMotion.quantize(_shown, Vector3.ZERO, Vector3.ZERO)
	_reconcile(tick, def, com)
	var eyes := InvAuthority.eyes(actor, BaseRegistry.world_position(actor.state))
	var goal := InvHoldMotion.target_of(eyes, input, tuning)
	_goals[tick] = goal
	var before: Array = _pred.get(tick - 1, [])
	if before.is_empty():
		before = InvHoldMotion.quantize(_shown, Vector3.ZERO, Vector3.ZERO)
	var state := _advance(before, goal, def, com, SimClock.world_dt(tick))
	_pred[tick] = state
	_claim(tick, state)
	_show(copy, state, _anchor)
	_check_hidden(tick, eyes, def, state[0])


## Cliente: «no se ve» lo decide esta máquina, sin esperar al host (desde la
## segunda prueba del usuario, 2026-11-15: con el host tardaba Hold Break Time
## más la demora de la red). Si el punto agarrado, con lo predicho para este
## tick, queda tapado por el nivel o una caja más de Hold Hidden Time (de
## fábrica, 0: en el primer tick tapado), se suelta como con el botón: el
## pedido dice que lo sostuvo hasta este tick, y lo predicho sigue cayendo
## desde acá (_free). La misma mirada que usa el host (InvReach.held_visible).
func _check_hidden(tick: int, eyes: Vector3, def: InvItemDef, place: Transform3D) -> void:
	if InvReach.held_visible(actor.get_world_3d().direct_space_state, eyes, def, place, _anchor):
		_hidden = 0.0
		return
	_hidden += SimClock.world_dt(tick)
	if _hidden > (tuning.hold_hidden_time if tuning != null else 0.0):
		hidden_releases += 1
		drop_hold("Se te soltó: no se ve", true)


## Un tick de la mano desde `before` ([pose, velocidad, velocidad de giro])
## hacia `goal`: las velocidades y el paso de InvHoldMotion (velocities y
## guard, que no deja meterse en el nivel, tampoco girando sin moverse), los
## mismos que da el host antes de Jolt. Devuelve lo nuevo, cuantizado.
func _advance(before: Array, goal: Transform3D, def: InvItemDef, com: Vector3, dt: float) -> Array:
	var from: Transform3D = before[0]
	var speeds := InvHoldMotion.velocities(from, com, before[1], before[2], _anchor, goal, tuning, dt)
	var step := InvHoldMotion.guard(actor.get_world_3d().direct_space_state, def, from, com, speeds[0], speeds[1], dt,
			InvAuthority.WORLD_MASK)
	return InvHoldMotion.quantize(step[2], step[0], step[1])


func _claim(tick: int, state: Array) -> void:
	_claims[tick] = InvHoldMotion.pack_claim(_uid, _session, _version, state[0], state[1], state[2])
	(_sent.get_or_add(tick, []) as Array).append(state)


## Compara lo último que llegó del host de lo sostenido con lo predicho para
## ese mismo tick y, si hace falta, parte de lo del host y repite hasta el
## presente (ver la cabecera, punto 4).
func _reconcile(tick: int, def: InvItemDef, com: Vector3) -> void:
	var newest := net.bodies.newest_sample(_uid)
	if not _confirmed or newest.size() < 7 or not newest[4] or newest[6] < 0:
		return
	var host_tick: int = newest[0]
	if host_tick <= _checked or host_tick < _start_tick - 1:
		return
	_checked = host_tick
	var host := InvHoldMotion.quantize(newest[1], newest[2], newest[5])
	var version: int = newest[6]
	var mine: Array = _pred.get(host_tick, [])
	if version == _version:
		# Con la misma versión, el host adopta o coincide con lo que afirma esta
		# máquina, o sube la versión (InvBodies._judge_holds). Si difiere es
		# porque le faltó un input (lo simuló con el anterior) y la afirmación
		# todavía viaja: corregir ahora sería corregir dos veces, como con el
		# personaje (ClientPrediction.waits_late_input).
		if not mine.is_empty():
			var diff := InvHoldMotion.difference(mine[0], host[0], com, _anchor)
			if diff[0] <= CORRECT_POS and diff[1] <= CORRECT_ANGLE:
				held_matches += 1
			else:
				var adopted := false
				for old: Array in _sent.get(host_tick, []):
					var seen := InvHoldMotion.difference(old[0], host[0], com, _anchor)
					adopted = adopted or (seen[0] <= ADOPTED_POS and seen[1] <= ADOPTED_ANGLE)
				if adopted:
					held_adopted_old += 1
				else:
					held_waits += 1
		return
	held_version_resets += 1
	_version = version
	var old_last: Array = _pred.get(tick - 1, [])
	_pred[host_tick] = host
	for t in range(host_tick + 1, tick):
		var goal: Variant = _goals.get(t)
		var prev: Array = _pred[t - 1]
		_pred[t] = _advance(prev, goal, def, com, SimClock.world_dt(t)) if goal != null else prev
		if goal != null:
			_claim(t, _pred[t])
	if not old_last.is_empty() and _pred.has(tick - 1):
		var new_last: Transform3D = _pred[tick - 1][0]
		var moved := InvHoldMotion.difference(old_last[0], new_last, com, _anchor)
		last_held_correction = moved[0]
		max_held_correction = maxf(max_held_correction, moved[0])
		# Puede seguir pendiente el suavizado de otra corrección. Se conserva
		# lo que se DIBUJÓ, no la pose cruda anterior: usar old_last borraba
		# aquel desplazamiento y hacía saltar el objeto en cada corrección.
		_start_smoothing(_shown, new_last, _anchor)


## Lo que se ve va de `old` a `new` en SMOOTH_TICKS, girando alrededor de `pivot`
## (en el espacio del objeto).
func _start_smoothing(old: Transform3D, new: Transform3D, pivot: Vector3) -> void:
	_smooth_pos = old * pivot - new * pivot
	_smooth_turn = (Quaternion(old.basis.orthonormalized()) * Quaternion(new.basis.orthonormalized()).inverse()).normalized()
	_smooth_left = SMOOTH_TICKS


## Coloca la copia en lo predicho, con lo que quede del suavizado (alrededor de
## `pivot`). El recorrido visual también respeta el nivel: si el suavizado
## intenta entrar al piso o cruzar una pared, avanza solo hasta el contacto.
## Descartarlo entero y mostrar la pose cruda producía otro salto.
func _show(copy: InvWorldItem, state: Array, pivot: Vector3) -> void:
	var place: Transform3D = state[0]
	if _smooth_left > 0:
		var weight := float(_smooth_left) / SMOOTH_TICKS
		_smooth_left -= 1
		var basis := Basis(Quaternion.IDENTITY.slerp(_smooth_turn, weight)) * place.basis
		var pivot_at := place * pivot + _smooth_pos * weight
		place = Transform3D(basis, pivot_at - basis * pivot)
	place = _visual_step(copy.def, place)
	copy.place(place)
	net.bodies.shown.move(copy.uid, place)
	_shown = place


## No salta a la pose cruda al fallar el suavizado. Se conserva el prefijo
## libre del camino desde lo que realmente se dibujó (también al terminar el
## suavizado). Comprobar solo el destino dejaba saltar de un lado a otro de
## una pared fina con ambos extremos libres. Ocho bisecciones, solo cuando el
## recorrido se traba; en el aire basta la primera consulta.
func _visual_step(def: InvItemDef, wanted: Transform3D) -> Transform3D:
	var space := actor.get_world_3d().direct_space_state
	if InvHoldMotion.path_free(space, def, _shown, wanted, InvAuthority.WORLD_MASK, [], 0.01, 64):
		return wanted
	var low := 0.0
	var high := 1.0
	for i in 8:
		var middle := (low + high) * 0.5
		var tried := _shown.interpolate_with(wanted, middle)
		if InvHoldMotion.path_free(space, def, _shown, tried, InvAuthority.WORLD_MASK, [], 0.01, 64):
			low = middle
		else:
			high = middle
	return _shown.interpolate_with(wanted, low)


## Lo soltado: sigue adelantado desde lo último predicho en la mano, cayendo
## (con la gravedad y el freno de siempre) y sin meterse en el nivel. Las poses
## del host de después de soltarlo lo corrigen, llevadas al presente. Al quedar
## quieto en el host (o a los FREE_TICKS) se lo deja a InvBodies, que lo
## dibuja como a los demás.
func _predict_free(tick: int) -> void:
	var uid: int = _free["uid"]
	var copy := net.world_view(uid)
	if copy == null or tick - int(_free["since"]) > FREE_TICKS:
		_end_free(copy)
		return
	var def := copy.def
	var com := InvItemPhysics.center_of_mass(def)
	var state: Array = _free["state"]
	var newest := net.bodies.newest_sample(uid)
	if newest.size() >= 7 and not newest[4] and newest[0] > int(_free["checked"]) and newest[0] >= int(_free["since"]):
		_free["checked"] = newest[0]
		if newest[3]:
			# Quieto en el host: ya se ve igual en el presente y en el pasado.
			_end_free(copy)
			return
		state = InvHoldMotion.quantize(newest[1], newest[2], newest[5])
		for t in range(newest[0] + 1, mini(tick, newest[0] + 1 + MAX_CATCH_UP)):
			state = _fall(state, def, com, SimClock.world_dt(t))
		_start_smoothing(_shown, state[0], com)
	state = _fall(state, def, com, SimClock.world_dt(tick))
	_free["state"] = state
	_show(copy, state, com)


## Un tick de caída libre, como Jolt: la gravedad del proyecto y el freno de los
## objetos sueltos (el del proyecto más Item Angular Damp para el giro), con el
## mismo paso que la mano (InvHoldMotion.guard): contra el piso se queda, contra
## una pared se desliza, y si la pose del host lo trae un poco metido no se
## hunde más. Hasta el 2026-11-15, algo que arrancaba metido seguía cayendo a
## través del piso hasta que el host lo dormía (lo encontró el usuario en la
## notebook: soltado de más de medio metro, se hundía unos 800 ms).
func _fall(state: Array, def: InvItemDef, com: Vector3, dt: float) -> Array:
	var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN) \
			* float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var lv: Vector3 = (state[1] as Vector3) + gravity * dt
	lv *= maxf(1.0 - float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1)) * dt, 0.0)
	var av: Vector3 = state[2]
	av *= maxf(1.0 - (float(ProjectSettings.get_setting("physics/3d/default_angular_damp", 0.1))
			+ (tuning.item_angular_damp if tuning != null else 2.0)) * dt, 0.0)
	var step := InvHoldMotion.guard(actor.get_world_3d().direct_space_state, def, state[0], com, lv, av, dt,
			InvAuthority.WORLD_MASK)
	return InvHoldMotion.quantize(step[2], step[0], step[1])


## Deja de adelantar lo soltado: vuelve a lo del host en BLEND_MSEC.
func _end_free(copy: InvWorldItem) -> void:
	if copy != null:
		_blend_uid = copy.uid
		_blend_from = _shown
		_blend_msec = Time.get_ticks_msec()
	_free = {}


func _forget_before(tick: int) -> void:
	for table: Dictionary in [_pred, _goals, _claims, _sent]:
		for t: int in table.keys():
			if t < tick:
				table.erase(t)


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
