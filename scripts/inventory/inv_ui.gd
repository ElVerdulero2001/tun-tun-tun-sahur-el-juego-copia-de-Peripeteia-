class_name InvUI
extends Control

## Interfaz del inventario del jugador local: su grilla a la izquierda, la caja
## abierta a la derecha y la barra rápida abajo, con el mundo visible detrás.
## Sin caja abierta, a la derecha va la integridad corporal (desde el
## 2026-11-05: side_panel_rect, que dibuja el HUD). Abrir una caja con E entra
## directo en modo caja (desde el 2026-11-08, pedido del usuario: antes se veía
## la integridad hasta que contestaba el host): mientras el host contesta, el
## lado derecho queda reservado con el marco de la caja, de sus mismas medidas;
## si el host dice que no, todo vuelve a como estaba antes de E.
## Muestra lo que confirmó el host (InvReplica) y pide cambios: nunca escribe
## ese estado. Desde el 2026-11-04, lo que se recoge y los consumibles que se
## usan se ven al instante, sin esperar al host (InvReplica.shown_own): un
## consumible se usa desde el input del personaje (InvNet.queue_use), no con
## un pedido, y lo recogido se ve en la grilla mientras el host contesta.
##
## Un clic agarra un objeto y otro clic lo deja: no hay que mantener el botón.
## Tenerlo en la mano es una intención de esta máquina: el objeto sigue en su
## lugar hasta que el host contesta, aunque ese lugar se dibuja vacío. Con el objeto en la mano, cada clic derecho
## sobre una grilla deja una unidad (en un lugar libre o sobre una pila igual)
## y el resto sigue en la mano. Lo que se deja así sale de a un pedido por vez,
## porque cada uno necesita la versión que dejó el anterior; mientras tanto se
## ve marcado como pendiente.
##
## El mundo no se pausa: con el inventario abierto se sigue caminando con WASD.
## El mouse queda libre (LabCamera.hold_mouse) y la cámara no gira. Mientras
## se escribe una cantidad, el laboratorio no mueve al personaje (is_typing).
##
## Teclas (acciones del Mapa de entrada): Tab (toggle_inventario) abre y
## cierra; con una caja abierta (o pedida), Tab cierra solo la caja y el
## inventario sigue abierto, con la integridad a la derecha (desde el
## 2026-11-08, pedido del usuario: antes cerraba todo); Esc (ui_cancel) suelta lo que se tiene en la mano (vuelve a su
## lugar) o cierra el diálogo, después cierra el menú y por último el
## inventario; R (rotar_item) gira lo que se tiene en la mano, 90° por vez; E
## (interactuar) recoge o abre lo que se mira y, con una caja abierta, la
## cierra (con el inventario); 1 a 9 y 0 (acceso_rapido_N) usan o equipan lo
## del acceso. Con la mano vacía, el cursor sobre un objeto muestra su nombre.
##
## Lo que E elegiría en cada momento lo marca el indicador del HUD
## (InteractIndicator, desde el 2026-11-06): le pide a interaction_focus() la
## zona y el nombre, con el mismo selector y las mismas reglas que usa E
## (can_interact). Por eso encima de la barra ya no hay aviso de interacción.

signal opened
signal closed

const KEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
const SLOT_SIZE := 58.0
const SLOT_GAP := 6.0
const PAD := 10.0
const HEADER := 46.0
const TOAST_MSEC := 3500
const PANEL_COLOR := Color(0.07, 0.08, 0.1, 0.84)
const LINE_COLOR := Color(1, 1, 1, 0.09)
const VALID_COLOR := Color(0.25, 0.85, 0.35, 0.45)
const MERGE_COLOR := Color(0.25, 0.7, 0.95, 0.5)
const INVALID_COLOR := Color(0.95, 0.25, 0.2, 0.45)
const PENDING_COLOR := Color(1.0, 0.8, 0.2, 0.9)
const BOX_HINT := "Clic agarra y deja: pasá objetos entre las dos grillas"
## Si la caja pedida tarda más que esto en abrirse, su lugar dice "Abriendo…".
## Antes no: en el host contesta en un cuadro y el texto sería un parpadeo.
const BOX_WAIT_TEXT_MSEC := 150

## HOLD: un objeto en la mano. SLOT_HOLD: un acceso de la barra en la mano.
## SPLIT_PLACE: eligiendo dónde va la pila nueva de Dividir….
enum Mode { NONE, HOLD, SLOT_HOLD, SPLIT_PLACE }

@export var net: InvNet
@export var camera: LabCamera
## Lado de una celda en pantalla, en píxeles. Si la grilla no entra en la
## pantalla, se achica sola.
@export_range(16, 96) var cell_size := 40
@export_range(10, 28) var font_size := 15

## El personaje del jugador local. Lo pone el laboratorio.
var actor: ActorBody
## El panel de integridad corporal que va a la derecha (side_panel_rect), para
## soltar un consumible sobre una parte del cuerpo (desde el 2026-11-06). Lo
## pone el laboratorio: es el HUD (LabHud), y de él se usan
## integrity_part_at(punto) -> parte o -1, integrity() -> las seis partes como
## se ven, y part_name(parte). Sin él, el panel no cura.
var body_panel: Object
var is_open := false
var thumbnails: InvThumbnails

var _mode := Mode.NONE
## Lo que se tiene en la mano: {"src", "uid", "ver", "def", "rot", "grab",
## "cell", "start_rot"}; al dividir, también "qty" (lo que va a la pila nueva).
## "grab" es la celda del objeto por donde se agarró (contando desde su esquina
## de arriba a la izquierda, ya girado): el cursor queda en su centro.
var _hold := {}
var _slot_from := -1
## Lo que se dejó con el objeto en la mano y todavía no se pidió, en orden:
## {"src", "uid", "ver", "def", "rot", "grab", "mouse", "count", "all", "kind",
## "ref", "key", "rect"}. "all" es un clic izquierdo: va todo lo que quede.
var _placing: Array = []
## El pedido de esa fila que espera respuesta: {"seq", "uid", "uids", "count",
## "moves"}; "moves" es falso si solo asigna un acceso de la barra.
var _flight := {}
var _mouse := Vector2.ZERO
var _cs := 40.0
var _toast := ""
var _toast_until := 0
## Pedidos que esperan respuesta: número -> {"op", "ref", "rect", "uid"}; el
## de abrir una caja, {"op", "name"} y "cancelled" si se cerró antes de la
## respuesta.
var _sent := {}
## La caja pedida con E que el host todavía no abrió (desde el 2026-11-08):
## {"seq", "id", "name", "was_open" (si el inventario ya estaba abierto antes de
## E), "msec"}. Mientras tanto la interfaz ya está en modo caja: el lado
## derecho es suyo (_reserved_grid_rect) y no se ve la integridad.
var _box_wait := {}
var _menu: PanelContainer
var _menu_box: VBoxContainer
var _menu_uid := 0
var _dialog: PanelContainer
var _dialog_title: Label
var _dialog_error: Label
var _spin: SpinBox
var _dialog_ok: Button
var _dialog_kind := ""
var _dialog_item := {}
var _inspect: PanelContainer
var _inspect_text: Label
var _inspect_uid := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	thumbnails = InvThumbnails.new()
	thumbnails.name = "Miniaturas"
	add_child(thumbnails)
	thumbnails.thumbnail_ready.connect(func(_key: String) -> void: queue_redraw())
	_build_menu()
	_build_dialog()
	_build_inspect()
	if net != null:
		net.replica.changed.connect(_on_replica_changed)
		net.replica.world_changed.connect(queue_redraw)
		net.replica.answered.connect(_on_answered)
		net.replica.use_refused.connect(func(reason: String) -> void:
			_say("No se usó: %s" % reason)
			queue_redraw())
		net.container_closed.connect(_on_container_closed)


## El laboratorio la prende cuando aparece el personaje propio.
func activate(p_actor: ActorBody) -> void:
	actor = p_actor
	queue_redraw()


## Se cortó la conexión: se cierra todo lo de esta máquina, sin tocar lo
## confirmado (queda en el host).
func connection_lost() -> void:
	close()
	_placing.clear()
	_flight = {}
	_sent.clear()
	_box_wait = {}
	actor = null


func _active() -> bool:
	return net != null and net.started and is_instance_valid(actor)


func _r() -> InvReplica:
	return net.replica


# --- Abrir y cerrar -----------------------------------------------------------

## Tab. Con una caja abierta o pedida, cierra solo la caja (close_box); si no,
## abre o cierra el inventario.
func toggle() -> void:
	if is_open and has_box():
		close_box()
	elif is_open:
		close()
	else:
		open()


## Si hay una caja abierta, o pedida con E y sin respuesta del host.
func has_box() -> bool:
	return net != null and (_r().box_id != 0 or not _box_wait.is_empty())


## Cierra la caja abierta (o la pedida) y deja el inventario abierto: a la
## derecha vuelve la integridad (desde el 2026-11-08, pedido del usuario). Lo
## que se tenía en la mano desde la caja vuelve a su lugar, y lo que se iba a
## dejar en ella de a una unidad no se deja; lo de la grilla propia sigue en la
## mano (por ejemplo, para soltarlo sobre una parte del cuerpo). Lo ya pedido
## al host sigue su curso.
func close_box() -> void:
	var id := _r().box_id
	if id != 0:
		if _mode != Mode.NONE and _hold.get("src", InvProtocol.OWN) == id:
			_cancel_mode("")
		_placing = _placing.filter(func(entry: Dictionary) -> bool: return entry["src"] != id and entry["ref"] != id)
	_leave_box()
	queue_redraw()


## Deja la caja: se le pide al host que la cierre y deja de verse ya. Una
## pedida que el host todavía no contestó no aparece cuando llega (_on_answered),
## aunque mientras tanto el inventario se vuelva a abrir con Tab.
func _leave_box() -> void:
	if net == null:
		return
	if not _box_wait.is_empty():
		if _sent.has(_box_wait["seq"]):
			_sent[_box_wait["seq"]]["cancelled"] = true
		_box_wait = {}
	if _r().box_id != 0:
		_r().request(InvProtocol.Op.CLOSE, [_r().box_id])
		_r().forget_box()


func open() -> void:
	if is_open or not _active():
		return
	is_open = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if camera != null:
		camera.hold_mouse(self)
	opened.emit()
	queue_redraw()


## Cierra el inventario cancelando lo que era solo de esta máquina (lo que se
## tenía en la mano, el menú, los diálogos). Lo ya pedido al host sigue su curso.
func close() -> void:
	_cancel_mode("")
	_close_menu()
	_close_dialog()
	_inspect.hide()
	_leave_box()
	if not is_open:
		return
	is_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if camera != null:
		camera.release_mouse(self)
	closed.emit()
	queue_redraw()


## Mientras se escribe en un campo numérico: el laboratorio no mueve al personaje.
func is_typing() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and is_ancestor_of(focused) and focused is LineEdit


func _modal_open() -> bool:
	return _dialog.visible or _inspect.visible


# --- Teclado -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	# Tab y Esc van primero, también si un campo numérico tiene el foco.
	if event.is_action_pressed("toggle_inventario"):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _escape():
		get_viewport().set_input_as_handled()


## Esc: primero lo que se tiene en la mano o el diálogo, después el menú y por
## último el inventario. Sin nada de eso abierto, sigue de largo (la cámara
## suelta el mouse).
func _escape() -> bool:
	if _mode != Mode.NONE:
		_cancel_mode("")
		return true
	if _dialog.visible:
		_close_dialog()
		return true
	if _inspect.visible:
		_inspect.hide()
		return true
	if _menu.visible:
		_close_menu()
		return true
	if is_open:
		close()
		return true
	return false


## Lo demás va acá: después de que un campo numérico con foco tome sus teclas,
## y antes que el laboratorio y la cámara.
func _unhandled_key_input(event: InputEvent) -> void:
	if not _active() or not event is InputEventKey or not event.pressed or event.echo or event.alt_pressed:
		return
	if event.is_action_pressed("rotar_item") and (_mode == Mode.HOLD or _mode == Mode.SPLIT_PLACE):
		_rotate_held()
		get_viewport().set_input_as_handled()
		return
	# Con una caja abierta (o pedida), E la cierra junto con el inventario.
	if event.is_action_pressed("interactuar") and _e_closes_box():
		close()
		get_viewport().set_input_as_handled()
		return
	if _modal_open():
		return
	if event.is_action_pressed("interactuar"):
		_interact()
		get_viewport().set_input_as_handled()
		return
	for i in KEYS.size():
		if event.is_action_pressed("acceso_rapido_%s" % KEYS[i]):
			_press_slot(i)
			get_viewport().set_input_as_handled()
			return


func _interact() -> void:
	var target := _look_target()
	if target.is_empty():
		_say("Mirá lo que querés agarrar o abrir: tiene que estar cerca y a la vista")
		return
	if target["kind"] == "item":
		pick_up_world(target["id"], target["name"])
		return
	if _r().box_id == target["id"]:
		open()
		return
	open_box(target["id"], target["name"])


## Pedirle al host que abra esa caja (lo que hace E mirándola). El inventario
## se abre ya, directo en modo caja: el lado derecho queda reservado para ella
## hasta que el host conteste (_box_wait). Devuelve el número del pedido, o 0
## si no salió (ya hay una caja pedida, o todavía no llegó el inventario).
func open_box(id: int, shown_name := "") -> int:
	if _r().is_op_pending(InvProtocol.Op.OPEN):
		return 0
	var was_open := is_open
	var seq := _r().request(InvProtocol.Op.OPEN, [id])
	if seq == 0:
		return 0
	_sent[seq] = {"op": InvProtocol.Op.OPEN, "name": shown_name}
	# Antes de open(): el primer cuadro abierto ya es el de la caja.
	_box_wait = {"seq": seq, "id": id, "name": shown_name, "was_open": was_open, "msec": Time.get_ticks_msec()}
	open()
	return seq


## Si hay una caja pedida que el host todavía no abrió (el lado derecho está
## reservado para ella).
func is_waiting_box() -> bool:
	return not _box_wait.is_empty()


## La caja pedida dejó de esperar sin abrirse (el host dijo que no o no
## contestó a tiempo): todo vuelve a como estaba antes de E. Si el inventario
## estaba cerrado, se cierra; si estaba abierto con Tab, la integridad vuelve
## a la derecha.
func _box_wait_failed() -> void:
	var was_open: bool = _box_wait["was_open"]
	_box_wait = {}
	if not was_open:
		close()
	queue_redraw()


## Recoger un objeto del mundo. Se ve en la grilla ya, como lo va a meter el
## host (InvReplica.shown_own); si no entra, lo dice sin preguntarle. Si el
## host dice que no (otro lo agarró primero, por ejemplo), vuelve al piso y lo
## dice. Devuelve el número del pedido, o 0 si no salió.
func pick_up_world(uid: int, shown_name := "") -> int:
	var item: Dictionary = _r().world.get(uid, {})
	var grid := _r().shown_own()
	if item.is_empty() or grid == null:
		return 0
	var room := InvOps.insert(grid.copy(), (item["stack"] as InvStack).copy())
	if room["reason"] != "":
		_say(_sentence(room["reason"]))
		return 0
	var seq := _r().request(InvProtocol.Op.PICKUP, [uid], [uid])
	if seq != 0:
		_sent[seq] = {"op": InvProtocol.Op.PICKUP, "uid": uid, "name": shown_name}
	queue_redraw()
	return seq


## Lo que se está mirando con la cámara (InvNet.interaction_target), o vacío.
func _look_target() -> Dictionary:
	if camera == null or not _active():
		return {}
	var aim := camera.aim_ray()
	return net.interaction_target(actor, aim[0], aim[1], camera.third_person())


## Si E, en este momento, cierra la caja abierta (o pedida) en vez de
## recoger o abrir lo que se mira.
func _e_closes_box() -> bool:
	return is_open and not is_typing() and (_r().box_id != 0 or _r().is_op_pending(InvProtocol.Op.OPEN))


## Si E, en este momento, actuaría sobre lo que se mira: con el personaje
## propio, sin escribir en un campo, sin un diálogo abierto y sin una caja
## abierta (ahí E la cierra). Son las mismas reglas de _unhandled_key_input.
func can_interact() -> bool:
	return _active() and not is_typing() and not _modal_open() and not _e_closes_box()


## Lo que E elegiría ahora mismo (el mismo selector, _look_target), o vacío si
## no hay nada o si la interfaz no deja interactuar.
func interaction_target() -> Dictionary:
	return _look_target() if can_interact() else {}


## Para el indicador del HUD (InteractIndicator.source): la zona y el nombre de
## lo que E elegiría ahora, que aporta el propio objetivo (interact_focus), o
## null. El indicador lo pide en cada cuadro.
func interaction_focus() -> InteractFocus:
	var node: Object = interaction_target().get("node")
	if node == null or not is_instance_valid(node) or not node.has_method(&"interact_focus"):
		return null
	return node.call(&"interact_focus") as InteractFocus


func _press_slot(slot: int) -> void:
	var loadout := _r().loadout
	if loadout == null:
		return
	if loadout.hotbar[slot] == 0:
		_say("El acceso %s está vacío: hacé clic en un objeto de tu inventario y después en el acceso" % KEYS[slot])
		return
	var uid := loadout.hotbar[slot]
	# Como el host (InvAuthority._hotbar_press): hace la primera capacidad. Un
	# consumible se usa sin esperarlo; equipar sigue siendo un pedido.
	var def := _r().shown_own().def_of(uid) if _r().shown_own() != null else null
	if def != null:
		for ability in def.abilities:
			if ability != null:
				if ability.kind() == InvAbility.Kind.USE:
					use_item(uid)
					return
				break
	var seq := _r().request(InvProtocol.Op.HOTBAR_PRESS, [slot], [uid], [slot])
	if seq != 0:
		_sent[seq] = {"op": InvProtocol.Op.HOTBAR_PRESS}


# --- Mouse -----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
		if _mode != Mode.NONE:
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		_mouse = event.position
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_left_press()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_right_press()
		accept_event()
		queue_redraw()


## Clic: con algo en la mano lo deja; si no, agarra lo que haya bajo el cursor
## (un objeto o un acceso de la barra).
func _left_press() -> void:
	if _modal_open():
		return
	if _menu.visible:
		_close_menu()
		return
	match _mode:
		Mode.HOLD:
			_place_all()
			return
		Mode.SPLIT_PLACE:
			_place_split()
			return
		Mode.SLOT_HOLD:
			_place_slot()
			return
	var hit := _item_at(_mouse)
	if not hit.is_empty():
		_pick_up(hit[0], hit[1])
		return
	var slot := _slot_at(_mouse)
	if slot >= 0 and _r().loadout != null and _r().loadout.hotbar[slot] != 0:
		if _r().is_slot_pending(slot):
			_say("Ese acceso está esperando al host")
			return
		_mode = Mode.SLOT_HOLD
		_slot_from = slot


## Clic derecho: con un objeto en la mano deja una unidad; si no, abre el menú
## del objeto o vacía el acceso que haya bajo el cursor.
func _right_press() -> void:
	if _modal_open():
		return
	match _mode:
		Mode.HOLD:
			_place_one()
			return
		Mode.SLOT_HOLD, Mode.SPLIT_PLACE:
			_cancel_mode("")
			return
	var hit := _item_at(_mouse)
	if not hit.is_empty():
		_open_menu(hit[0], hit[1])
		return
	_close_menu()
	var slot := _slot_at(_mouse)
	if slot >= 0 and _r().loadout != null and _r().loadout.hotbar[slot] != 0:
		_r().request(InvProtocol.Op.HOTBAR_SET, [slot, 0], [], [slot])


## Un acceso en la mano: sobre otro acceso los intercambia; en cualquier otro
## lado no hace nada.
func _place_slot() -> void:
	var slot := _slot_at(_mouse)
	if slot >= 0 and slot != _slot_from:
		_r().request(InvProtocol.Op.HOTBAR_SWAP, [_slot_from, slot], [], [_slot_from, slot])
	_mode = Mode.NONE
	_slot_from = -1


# --- El objeto en la mano ------------------------------------------------------------

func _pick_up(ref: int, uid: int) -> void:
	var grid := _grid(ref)
	var stack := grid.get_stack(uid)
	# Con un uso sin confirmar se puede agarrar igual (desde el 2026-11-06 a la
	# noche), para soltarlo enseguida sobre otra parte del cuerpo; moverlo o
	# soltarlo en otro lado espera a que el host lo confirme (_place_all).
	if _waiting(uid):
		_say("Ese objeto está esperando al host")
		return
	var place := grid.placement(uid)
	var rect := _item_rect(ref, uid)
	var grab := Vector2i(((_mouse - rect.position) / _cs).floor()).clamp(Vector2i.ZERO, grid.rect_of(uid).size - Vector2i.ONE)
	_hold = {"src": ref, "uid": uid, "ver": stack.ver, "def": grid.def_of(uid), "rot": place.rot,
			"grab": grab, "cell": place.cell, "start_rot": place.rot}
	_mode = Mode.HOLD
	_close_menu()


## R con el objeto en la mano: lo gira 90° en el sentido del reloj alrededor
## del centro de la celda por donde se agarró, que sigue bajo el cursor.
## Cuatro veces vuelve a como estaba.
func _rotate_held() -> void:
	var def: InvItemDef = _hold["def"]
	if not def.can_rotate:
		_say("%s no se puede girar" % def.display_name)
		return
	var foot := def.footprint(_hold["rot"])
	var grab: Vector2i = _hold["grab"]
	_hold["grab"] = Vector2i(foot.y - 1 - grab.y, grab.x)
	_hold["rot"] = (_hold["rot"] + 1) % 4
	queue_redraw()


## Dónde queda el cursor dentro de lo que se tiene en la mano, en píxeles desde
## su esquina de arriba a la izquierda: el centro de la celda agarrada.
func _grab_offset(hold: Dictionary) -> Vector2:
	return (Vector2(hold["grab"]) + Vector2(0.5, 0.5)) * _cs


## Clic con el objeto en la mano: va todo lo que queda en la mano. Si ahí no se
## puede, lo dice y lo sigue teniendo.
func _place_all() -> void:
	var target := _drop_target(_hold, _mouse, "all", true)
	if target["kind"] == "invalid":
		_say(_sentence(target.get("reason", "")))
		return
	if target["kind"] == "part":
		_heal_part(target["part"])
		return
	var back: bool = target["kind"] == "move" and target["ref"] == _hold["src"] and target["cell"] == _hold["cell"] \
			and _hold["rot"] == _hold["start_rot"]
	if not back and _r().has_use(_hold["uid"]):
		_say("Esperá: ese objeto todavía espera al host")
		return
	if not back:
		_queue_placing(target, 0, true)
	_end_hold()


## Clic derecho con el objeto en la mano: deja una unidad en una grilla, en un
## lugar libre o sobre una pila igual. Lo demás sigue en la mano; con la
## última, la mano queda vacía.
func _place_one() -> void:
	var left := _held_quantity(_hold)
	var target := _drop_target(_hold, _mouse, "one", left <= 1)
	if target["kind"] == "invalid":
		_say(_sentence(target.get("reason", "")))
		return
	if _r().has_use(_hold["uid"]):
		_say("Esperá: ese objeto todavía espera al host")
		return
	_queue_placing(target, 1, false)
	if left <= 1:
		_end_hold()


## Un consumible de la mano soltado sobre una parte dañada del cuerpo (desde el
## 2026-11-06): sale como un uso, con la parte (InvNet.queue_use), y la mano
## queda vacía. Desde la noche no espera al host, como el uso normal: en el
## tick siguiente la parte se ve curada y hay una unidad menos, y se puede
## volver a agarrar enseguida para curar otra. El host cura y gasta juntos; si
## dice que no, la parte y la unidad vuelven a verse como estaban y lo dice.
func _heal_part(part: int) -> void:
	var stack := _r().shown_own().get_stack(_hold["uid"]) if _r().shown_own() != null else null
	if stack == null:
		_cancel_mode("Ese objeto ya no está")
		return
	if not net.queue_use(stack.uid, _hold["def"], part):
		_say("Esperá: hay muchos usos que el host todavía no confirmó")
		return
	_end_hold()
	if body_panel != null:
		_say("Parte curada: %s" % String(body_panel.call("part_name", part)).to_lower())


## Lo que se tiene en la mano, o null (para el panel de integridad).
func held_def() -> InvItemDef:
	return _hold.get("def") if _mode == Mode.HOLD and not _hold.is_empty() else null


## Dónde está el cursor, en las coordenadas de esta interfaz.
func pointer() -> Vector2:
	return _mouse


func _end_hold() -> void:
	_mode = Mode.NONE
	_hold = {}
	queue_redraw()


## Cuántas unidades quedan en la mano: la pila menos lo que ya se dejó con
## clic derecho y el host todavía no aplicó.
func _held_quantity(hold: Dictionary) -> int:
	if hold.has("qty"):
		return hold["qty"]
	return _staying(hold["src"], hold["uid"])


## Cuántas unidades de esa pila quedan donde están: menos lo que ya se dejó en
## otro lado y está en fila o esperando al host. Asignarla a la barra no la
## mueve. Lo soltado al piso ya no está en la grilla que se ve
## (InvReplica.shown_own): no se resta otra vez.
func _staying(ref: int, uid: int) -> int:
	var grid := _grid(ref)
	var stack := grid.get_stack(uid) if grid != null else null
	if stack == null:
		return 0
	var left := stack.quantity
	for entry: Dictionary in _placing:
		if entry["uid"] == uid and entry["kind"] != "slot":
			left -= stack.quantity if entry["all"] else entry["count"]
	if _flight.get("uid", 0) == uid and _flight["moves"] and not _flight.get("shown", false) and _r().pending.has(_flight["seq"]):
		left -= _flight["count"]
	return maxi(left, 0)


## Si ese objeto tiene algo pedido o en la fila que todavía no se ve hecho: se
## dibuja marcado como pendiente. Recoger, soltar y usar se ven hechos ya.
func _waiting(uid: int) -> bool:
	return _r().is_uid_waiting(uid) or _placing.any(func(entry: Dictionary) -> bool: return entry["uid"] == uid)


## Si ese objeto no se puede agarrar ni mover todavía: tiene algo pedido o en
## la fila, o un consumible usado que el host todavía no aplicó (un pedido que
## llegara antes que el uso encontraría otra versión). Usarlo otra vez sí se
## puede.
func _busy(uid: int) -> bool:
	return _waiting(uid) or _r().has_use(uid)


## A qué va lo que se tiene en la mano si se hace clic en `mouse`: {"kind":
## "move", "merge", "slot", "world" o "invalid", y lo que haga falta}. `how`:
## "all" (clic: va todo), "one" (clic derecho: unidades) o "split" (la pila
## nueva de Dividir…: solo a un lugar libre). `whole`: si se va la pila entera;
## si no, su lugar sigue ocupado por lo que queda.
func _drop_target(hold: Dictionary, mouse: Vector2, how: String, whole: bool) -> Dictionary:
	var def: InvItemDef = hold["def"]
	var foot := def.footprint(hold["rot"])
	for ref in _refs():
		var rect := _grid_rect(ref)
		var grid := _grid(ref)
		if rect.has_point(mouse):
			var own: bool = ref == hold["src"]
			var under := grid.uid_at(Vector2i(((mouse - rect.position) / _cs).floor()))
			var itself: bool = own and under == hold["uid"]
			if under != 0 and how != "split" and not itself:
				return _merge_target(hold, ref, under)
			if itself and not whole:
				return {"kind": "invalid", "reason": "ahí está lo que tenés en la mano: elegí otro lugar", "ref": ref}
			# La celda agarrada va a la celda bajo el cursor.
			var grab: Vector2i = hold["grab"]
			var cell := Vector2i(((mouse - rect.position) / _cs).floor()) - grab
			var reason := grid.why_not_fits(foot, cell, hold["uid"] if own and whole else 0)
			return {"kind": "move" if reason == "" else "invalid", "reason": reason, "ref": ref, "cell": cell, "foot": foot}
		if _panel_rect(ref).has_point(mouse):
			return {"kind": "invalid", "reason": "ahí no: dejalo sobre la grilla", "ref": ref}
	if _reserved_panel_rect().has_point(mouse):
		return {"kind": "invalid", "reason": "esperá a que se abra la caja"}
	if side_panel_rect().has_point(mouse):
		if how != "all":
			return {"kind": "invalid", "reason": "para curar una parte, clic izquierdo sobre ella"}
		return _part_target(hold, mouse)
	if how == "split":
		return {"kind": "invalid", "reason": "elegí un lugar libre en una grilla"}
	if how == "one":
		return {"kind": "invalid", "reason": "con clic derecho se deja una unidad sobre una grilla"}
	var slot := _slot_at(mouse)
	if slot >= 0:
		if hold["src"] != InvProtocol.OWN:
			return {"kind": "invalid", "reason": "en la barra solo van objetos de tu inventario"}
		return {"kind": "slot", "slot": slot}
	if _hotbar_rect().has_point(mouse) or _over_window(mouse):
		return {"kind": "invalid", "reason": "ahí no se puede soltar"}
	return {"kind": "world"}


## Soltar sobre el panel de integridad (desde el 2026-11-06): {"kind": "part",
## "part": parte} si lo que está en la mano cura esa parte, o "invalid" con el
## motivo, y entonces sigue en la mano. Nunca va al piso. Se mira con lo que
## muestra el panel (lo confirmado por el host); el host lo vuelve a mirar.
func _part_target(hold: Dictionary, mouse: Vector2) -> Dictionary:
	var part: int = body_panel.call("integrity_part_at", mouse) if body_panel != null else -1
	if part < 0:
		return {"kind": "invalid", "reason": "apuntá a una parte del cuerpo"}
	if hold["src"] != InvProtocol.OWN:
		return {"kind": "invalid", "reason": "primero pasalo a tu inventario"}
	var def: InvItemDef = hold["def"]
	var use := def.ability_of(InvAbility.Kind.USE) as InvConsumable if def != null else null
	if use == null or not use.repairs_parts():
		return {"kind": "invalid", "reason": "eso no cura partes del cuerpo"}
	var shown: PackedInt32Array = body_panel.call("integrity")
	if part >= shown.size() or shown[part] >= ActorState.INTEGRITY_FULL:
		return {"kind": "invalid", "reason": "esa parte ya está entera"}
	return {"kind": "part", "part": part}


func _merge_target(hold: Dictionary, ref: int, under: int) -> Dictionary:
	var grid := _grid(ref)
	var mine := _grid(hold["src"]).get_stack(hold["uid"])
	var other := grid.get_stack(under)
	var def: InvItemDef = hold["def"]
	var reason := ""
	if mine == null or other == null:
		reason = "ese objeto ya no está"
	elif mine.def_id != other.def_id:
		reason = "no se apilan: son objetos distintos"
	elif not InvStack.same_state(mine.state, other.state):
		reason = "no se apilan: tienen distinto estado"
	elif not def.stackable:
		reason = "este objeto no se apila"
	elif other.quantity >= def.stack_limit():
		reason = "esa pila ya está llena"
	elif _busy(under):
		reason = "esa pila está esperando al host"
	return {"kind": "merge" if reason == "" else "invalid", "reason": reason, "ref": ref, "target": under,
			"cell": grid.placement(under).cell, "foot": grid.footprint_of(under)}


## Pone en fila lo que se dejó con el objeto en la mano y manda lo primero.
## Clics derechos seguidos sobre el mismo lugar van en un solo pedido.
func _queue_placing(target: Dictionary, count: int, all: bool) -> void:
	var key := _target_key(target)
	if not all and not _placing.is_empty():
		var last: Dictionary = _placing.back()
		if not last["all"] and last["uid"] == _hold["uid"] and last["rot"] == _hold["rot"] and last["key"] == key:
			last["count"] += count
			queue_redraw()
			return
	_placing.append({"src": _hold["src"], "uid": _hold["uid"], "ver": _hold["ver"], "def": _hold["def"],
			"rot": _hold["rot"], "grab": _hold["grab"], "mouse": _mouse, "count": count, "all": all,
			"kind": target["kind"], "ref": target.get("ref", -1), "key": key, "rect": _target_rect(target)})
	_pump()


func _target_key(target: Dictionary) -> String:
	match target["kind"]:
		"move":
			return "m%d:%s" % [target["ref"], target["cell"]]
		"merge":
			return "g%d:%d" % [target["ref"], target["target"]]
		"slot":
			return "s%d" % target["slot"]
	return target["kind"]


func _target_rect(target: Dictionary) -> Rect2i:
	if not target.has("cell") or not target.has("foot"):
		return Rect2i()
	return Rect2i(target["cell"], target["foot"])


## Manda lo próximo de la fila si no hay otro pedido de la fila esperando
## respuesta. El lugar se vuelve a calcular con lo que hay ahora: un clic
## derecho sobre una unidad recién dejada la suma a esa pila.
func _pump() -> void:
	while _flight.is_empty() and not _placing.is_empty():
		_send_placing(_placing.pop_front())
	queue_redraw()


func _send_placing(entry: Dictionary) -> void:
	var grid := _grid(entry["src"])
	var stack := grid.get_stack(entry["uid"]) if grid != null else null
	if stack == null:
		return
	var uid := stack.uid
	var quantity: int = stack.quantity if entry["all"] else mini(entry["count"], stack.quantity)
	var whole := quantity >= stack.quantity
	var target := _drop_target(entry, entry["mouse"], "all" if entry["all"] else "one", whole)
	var kinds := ["move", "merge"]
	var same_place: bool = target.get("ref", -1) == entry["ref"] \
			and (target["kind"] == entry["kind"] or target["kind"] in kinds and entry["kind"] in kinds)
	if target["kind"] == "invalid" or not same_place:
		# El lugar cambió desde el clic (por ejemplo, se cerró la caja): no se
		# adivina otro, y lo que seguía en la fila con ese objeto se descarta.
		_say(_sentence(target.get("reason", "")) if target["kind"] == "invalid"
				else "Eso cambió antes de que saliera el pedido: no se movió")
		_drop_placing_of(uid)
		return
	var op := 0
	var args := []
	var uids := [uid]
	var slots := []
	match target["kind"]:
		"move":
			var cell: Vector2i = target["cell"]
			if not whole:
				op = InvProtocol.Op.SPLIT
				args = [entry["src"], uid, stack.ver, quantity, target["ref"], cell.x, cell.y, entry["rot"]]
			else:
				var place := grid.placement(uid)
				if target["ref"] == entry["src"] and cell == place.cell and entry["rot"] == place.rot:
					return
				op = InvProtocol.Op.MOVE
				args = [entry["src"], uid, stack.ver, target["ref"], cell.x, cell.y, entry["rot"]]
		"merge":
			op = InvProtocol.Op.MERGE
			args = [entry["src"], uid, stack.ver, target["ref"], target["target"], quantity]
			uids = [uid, target["target"]]
		"slot":
			op = InvProtocol.Op.HOTBAR_SET
			args = [target["slot"], uid]
			uids = []
			slots = [target["slot"]]
		"world":
			var spot: Variant = net.predict_drop_spot(actor)
			if spot == null:
				_say("No hay lugar cerca para soltarlo")
				_drop_placing_of(uid)
				return
			op = InvProtocol.Op.DROP_AT
			args = InvProtocol.drop_args(entry["src"], uid, stack.ver, quantity, spot)
	var seq := _r().request(op, args, uids, slots)
	if seq == 0:
		_say("Eso está esperando al host: no se movió")
		_drop_placing_of(uid)
		return
	# Lo soltado al piso ya se ve afuera de la grilla (InvReplica.shown_own).
	_flight = {"seq": seq, "uid": uid, "uids": uids, "count": quantity, "moves": target["kind"] != "slot",
			"shown": op == InvProtocol.Op.DROP_AT}
	_sent[seq] = {"op": op, "ref": target.get("ref", -1), "rect": _target_rect(target)}


func _drop_placing_of(uid: int) -> void:
	_placing = _placing.filter(func(entry: Dictionary) -> bool: return entry["uid"] != uid)


## Si el último paquete del host trae la respuesta del pedido de la fila que
## tocaba ese objeto: entonces el cambio es de esta máquina.
func _own_change(uid: int) -> bool:
	return not _flight.is_empty() and not _r().pending.has(_flight["seq"]) and uid in _flight["uids"]


## Un pedido de la fila dejó de esperar sin respuesta (venció): la fila sigue
## sin lo que dependía de él.
func _settle_flight(seq: int) -> void:
	if _flight.get("seq", 0) == seq:
		_flight = {}
		_placing.clear()
		_pump()


func _cancel_mode(reason: String) -> void:
	if _mode == Mode.NONE:
		return
	_mode = Mode.NONE
	_hold = {}
	_slot_from = -1
	if reason != "":
		_say(reason)
	queue_redraw()


## Llegó algo del host. Si otro jugador cambió lo que se tiene en la mano (lo
## movió o se lo llevó), se suelta: se muestra lo que hay ahora. Lo que cambió
## un pedido propio de la fila no lo suelta: sigue en la mano con lo que quede.
func _on_replica_changed() -> void:
	if _mode == Mode.HOLD or _mode == Mode.SPLIT_PLACE:
		var grid := _grid(_hold["src"])
		var stack := grid.get_stack(_hold["uid"]) if grid != null else null
		if stack == null:
			_cancel_mode("Ese objeto ya no está: se soltó")
		elif stack.ver != _hold["ver"]:
			if _mode == Mode.HOLD and _own_change(_hold["uid"]):
				_hold["ver"] = stack.ver
			else:
				_cancel_mode("Ese objeto cambió mientras lo tenías en la mano: se soltó")
	if not _flight.is_empty() and not _r().pending.has(_flight["seq"]):
		_settle_flight.call_deferred(_flight["seq"])
	if _menu.visible and _grid_of_uid(_menu_uid) == null:
		_close_menu()
	if _inspect.visible and _grid_of_uid(_inspect_uid) == null:
		_inspect.hide()
	if _dialog.visible and _grid_of_uid(_dialog_item.get("uid", 0)) == null:
		_close_dialog()
	queue_redraw()


func _on_answered(seq: int, ok: bool, reason: String) -> void:
	var sent: Dictionary = _sent.get(seq, {})
	_sent.erase(seq)
	if not ok:
		_say(_sentence(reason))
	elif sent.get("op", 0) == InvProtocol.Op.PICKUP and _r().world.has(sent["uid"]):
		var left: InvStack = _r().world[sent["uid"]]["stack"]
		_say("Solo entró una parte: quedan %d en el piso" % left.quantity)
	elif sent.get("op", 0) == InvProtocol.Op.OPEN and (not is_open or sent.get("cancelled", false)) and _r().box_id != 0:
		# Se cerró antes de que el host contestara: la caja también se cierra.
		_r().request(InvProtocol.Op.CLOSE, [_r().box_id])
		_r().forget_box()
	if _box_wait.get("seq", 0) == seq:
		# La caja ya llegó en este mismo paquete (ok), o no se abre.
		if ok:
			_box_wait = {}
		else:
			_box_wait_failed()
	if _flight.get("seq", 0) == seq:
		var uid: int = _flight["uid"]
		_flight = {}
		if not ok:
			# Lo que seguía en la fila con ese objeto contaba con este pedido.
			_drop_placing_of(uid)
		_pump()
	queue_redraw()


func _on_container_closed(id: int, reason: String) -> void:
	if _mode != Mode.NONE and _hold.get("src", InvProtocol.OWN) == id:
		_cancel_mode("")
	_placing = _placing.filter(func(entry: Dictionary) -> bool: return entry["src"] != id and entry["ref"] != id)
	_say(_sentence(reason))
	queue_redraw()


# --- División ----------------------------------------------------------------------

func _begin_split_place(ref: int, uid: int, ver: int, quantity: int) -> void:
	var grid := _grid(ref)
	var def := grid.def_of(uid) if grid != null else null
	if def == null:
		return
	var room := false
	for other in _refs():
		if not _grid(other).free_spot(def).is_empty():
			room = true
	if not room:
		_say("No hay lugar para la pila nueva: no se dividió")
		return
	_hold = {"src": ref, "uid": uid, "ver": ver, "def": def, "rot": 0, "grab": Vector2i.ZERO,
			"qty": quantity, "cell": Vector2i(-1, -1), "start_rot": 0}
	_mode = Mode.SPLIT_PLACE
	_say("Elegí dónde va la pila nueva (%d): clic en un lugar libre · R gira · Esc o clic derecho cancela" % quantity)


func _place_split() -> void:
	var target := _drop_target(_hold, _mouse, "split", false)
	if target["kind"] != "move":
		_say(_sentence(target.get("reason", "elegí un lugar libre")))
		return
	var hold := _hold
	_end_hold()
	var seq := _r().request(InvProtocol.Op.SPLIT, [hold["src"], hold["uid"], hold["ver"], hold["qty"], target["ref"],
			target["cell"].x, target["cell"].y, hold["rot"]], [hold["uid"]])
	if seq != 0:
		_sent[seq] = {"op": InvProtocol.Op.SPLIT, "ref": target["ref"], "rect": Rect2i(target["cell"], target["foot"])}


# --- Menú contextual ---------------------------------------------------------------

## Fondo sólido para el menú y las ventanas: el del tema por defecto deja ver
## la grilla y el mundo detrás, y no se lee.
func _window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.14, 0.97)
	style.border_color = Color(1, 1, 1, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	return style


func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.name = "Menu"
	_menu.hide()
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.add_theme_stylebox_override("panel", _window_style())
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 2)
	_menu.add_child(_menu_box)
	add_child(_menu)


func _open_menu(ref: int, uid: int) -> void:
	var grid := _grid(ref)
	var stack := grid.get_stack(uid)
	var def := grid.def_of(uid)
	if stack == null or def == null:
		return
	for child in _menu_box.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = def.display_name + (" ×%d" % stack.quantity if stack.quantity > 1 else "")
	title.add_theme_font_size_override("font_size", font_size + 1)
	_menu_box.add_child(title)
	var own := ref == InvProtocol.OWN
	var wait := "esperando al host" if _busy(uid) else ""
	var not_here := "" if own else "primero pasalo a tu inventario"
	var use := def.ability_of(InvAbility.Kind.USE)
	if use != null:
		var reason := _first("esperando al host" if _waiting(uid) else "", not_here,
				use.check(_r().loadout, stack, _vitals()) if _r().loadout != null else "")
		_add_action(use.action_text(_r().loadout, stack), reason, func() -> void: use_item(uid))
	var equip := def.ability_of(InvAbility.Kind.EQUIP)
	if equip != null:
		_add_action(equip.action_text(_r().loadout, stack), _first(wait, not_here),
				_request_item.bind(InvProtocol.Op.EQUIP, uid, stack.ver))
	_add_action("Inspeccionar", "", _show_inspect.bind(ref, uid))
	var split_reason := _first(wait, "" if def.stackable else "no se apila",
			"" if stack.quantity > 1 else "la pila tiene una sola unidad")
	_add_action("Dividir…", split_reason, _open_dialog.bind("split", ref, uid))
	_add_action("Soltar todo" if stack.quantity > 1 else "Soltar", wait,
			func() -> void: drop_item(ref, uid, stack.ver, stack.quantity))
	if stack.quantity > 1:
		_add_action("Soltar una cantidad…", wait, _open_dialog.bind("drop", ref, uid))
	var slot := _r().loadout.slot_of(uid) if own and _r().loadout != null else -1
	if slot >= 0:
		_add_action("Quitar del acceso %s" % KEYS[slot], "esperando al host" if _r().is_slot_pending(slot) else "",
				func() -> void: _r().request(InvProtocol.Op.HOTBAR_SET, [slot, 0], [], [slot]))
	_menu_uid = uid
	_menu.reset_size()
	_menu.show()
	_place_window.call_deferred(_menu, _mouse + Vector2(4, 4))


func _add_action(text: String, reason: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text if reason == "" else "%s  ·  %s" % [text, reason]
	button.disabled = reason != ""
	button.tooltip_text = reason
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(func() -> void:
		_close_menu()
		action.call())
	_menu_box.add_child(button)


## La salud y la estamina del personaje propio como se ven en esta máquina,
## solo para habilitar Usar en el menú: lo que vale lo vuelve a mirar el host.
func _vitals() -> ActorVitals:
	return ActorVitals.of(actor.state, net.tuning) if is_instance_valid(actor) and net.tuning != null else null


## Usa una unidad de un consumible propio sin esperar al host: se ve gastada
## ya, y el uso sale en el input del próximo tick (InvNet.queue_use), donde el
## host y esta máquina aplican el efecto a la vez. Antes se mira, con la salud
## y la estamina de esta máquina, lo mismo que mira el host; si el host igual
## no puede, la unidad vuelve a verse y se dice por qué. Devuelve si salió.
##
## Lo mismo para el menú y la barra: con algo pedido sobre ese objeto que
## todavía no se ve hecho (mover, juntar…), espera, como el botón del menú
## (auditoría del 2026-11-04, INV-02). Una capacidad que no se puede adelantar
## (InvAbility.predictable) sale como pedido y espera al host.
func use_item(uid: int) -> bool:
	var grid := _r().shown_own()
	var stack := grid.get_stack(uid) if grid != null else null
	var def := grid.def_of(uid) if stack != null else null
	var use := def.ability_of(InvAbility.Kind.USE) if def != null else null
	if use == null:
		return false
	if _waiting(uid):
		_say("Esperá: ese objeto todavía espera al host")
		return false
	var reason := use.check(_r().loadout, stack, _vitals())
	if reason != "":
		_say(_sentence(reason))
		return false
	if not use.predictable():
		var seq := _r().request(InvProtocol.Op.USE, [uid, stack.ver], [uid])
		if seq != 0:
			_sent[seq] = {"op": InvProtocol.Op.USE}
		queue_redraw()
		return seq != 0
	if not net.queue_use(uid, def):
		_say("Esperá: hay muchos usos que el host todavía no confirmó")
		return false
	queue_redraw()
	return true


## Soltar al piso desde una grilla (el menú o el diálogo de cantidad), sin
## esperar al host: esta máquina elige el lugar como lo haría el host, lo
## muestra ahí ya y se lo manda en el pedido (InvProtocol.Op.DROP_AT). Sin
## lugar, lo dice sin preguntarle. Devuelve el número del pedido, o 0.
func drop_item(ref: int, uid: int, ver: int, quantity: int) -> int:
	var spot: Variant = net.predict_drop_spot(actor)
	if spot == null:
		_say("No hay lugar cerca para soltarlo")
		return 0
	var seq := _r().request(InvProtocol.Op.DROP_AT, InvProtocol.drop_args(ref, uid, ver, quantity, spot), [uid])
	queue_redraw()
	return seq


func _request_item(op: int, uid: int, ver: int) -> void:
	var seq := _r().request(op, [uid, ver], [uid])
	if seq != 0:
		_sent[seq] = {"op": op}


func _close_menu() -> void:
	_menu.hide()
	_menu_uid = 0


func _first(a: String, b: String, c: String = "") -> String:
	return a if a != "" else b if b != "" else c


# --- Diálogo de cantidad ---------------------------------------------------------

func _build_dialog() -> void:
	_dialog = PanelContainer.new()
	_dialog.name = "Cantidad"
	_dialog.hide()
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog.add_theme_stylebox_override("panel", _window_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_dialog.add_child(box)
	_dialog_title = Label.new()
	_dialog_title.add_theme_font_size_override("font_size", font_size + 1)
	box.add_child(_dialog_title)
	_spin = SpinBox.new()
	_spin.min_value = 1
	_spin.step = 1
	_spin.rounded = true
	_spin.custom_minimum_size = Vector2(160, 0)
	_spin.get_line_edit().text_submitted.connect(func(_submitted: String) -> void: _accept_dialog())
	box.add_child(_spin)
	_dialog_error = Label.new()
	_dialog_error.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_dialog_error.add_theme_font_size_override("font_size", font_size - 1)
	box.add_child(_dialog_error)
	var row := HBoxContainer.new()
	box.add_child(row)
	_dialog_ok = Button.new()
	_dialog_ok.focus_mode = Control.FOCUS_NONE
	_dialog_ok.pressed.connect(_accept_dialog)
	row.add_child(_dialog_ok)
	var cancel := Button.new()
	cancel.text = "Cancelar (Esc)"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_close_dialog)
	row.add_child(cancel)
	add_child(_dialog)


func _open_dialog(kind: String, ref: int, uid: int) -> void:
	var grid := _grid(ref)
	var stack := grid.get_stack(uid) if grid != null else null
	var def := grid.def_of(uid) if grid != null else null
	if stack == null or def == null:
		return
	_dialog_kind = kind
	_dialog_item = {"ref": ref, "uid": uid, "ver": stack.ver, "max": stack.quantity - 1 if kind == "split" else stack.quantity}
	_spin.max_value = _dialog_item["max"]
	_spin.allow_greater = true
	_spin.allow_lesser = true
	if kind == "split":
		_dialog_title.text = "Dividir %s (%d): ¿cuántos van a la pila nueva? (1 a %d)" % [def.display_name, stack.quantity, _dialog_item["max"]]
		_dialog_ok.text = "Elegir lugar (Enter)"
		_spin.value = maxi(floori(stack.quantity / 2.0), 1)
	else:
		_dialog_title.text = "Soltar %s: ¿cuántos? (1 a %d)" % [def.display_name, _dialog_item["max"]]
		_dialog_ok.text = "Soltar (Enter)"
		_spin.value = stack.quantity
	_dialog_error.text = ""
	_dialog.reset_size()
	_dialog.show()
	_place_window.call_deferred(_dialog, (size - _dialog.size) / 2.0)
	var line := _spin.get_line_edit()
	line.grab_focus.call_deferred()
	line.select_all.call_deferred()


## Acepta la cantidad escrita solo si es un entero dentro del rango: si no, lo
## dice y el diálogo sigue abierto.
func _accept_dialog() -> void:
	var text := _spin.get_line_edit().text.strip_edges()
	var maximum: int = _dialog_item["max"]
	if not text.is_valid_int() or text.to_int() < 1 or text.to_int() > maximum:
		_dialog_error.text = "Tiene que ser un número entero entre 1 y %d" % maximum
		return
	var quantity := text.to_int()
	var item := _dialog_item
	var kind := _dialog_kind
	_close_dialog()
	if kind == "split":
		_begin_split_place(item["ref"], item["uid"], item["ver"], quantity)
	else:
		drop_item(item["ref"], item["uid"], item["ver"], quantity)


func _close_dialog() -> void:
	if _dialog.visible:
		_spin.get_line_edit().release_focus()
	_dialog.hide()
	_dialog_item = {}


# --- Inspección --------------------------------------------------------------------

func _build_inspect() -> void:
	_inspect = PanelContainer.new()
	_inspect.name = "Inspeccion"
	_inspect.hide()
	_inspect.mouse_filter = Control.MOUSE_FILTER_STOP
	_inspect.add_theme_stylebox_override("panel", _window_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_inspect.add_child(box)
	_inspect_text = Label.new()
	_inspect_text.add_theme_font_size_override("font_size", font_size)
	_inspect_text.custom_minimum_size = Vector2(420, 0)
	_inspect_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_inspect_text)
	var close_button := Button.new()
	close_button.text = "Cerrar (Esc)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(_inspect.hide)
	box.add_child(close_button)
	add_child(_inspect)


func _show_inspect(ref: int, uid: int) -> void:
	var grid := _grid(ref)
	var stack := grid.get_stack(uid) if grid != null else null
	var def := grid.def_of(uid) if grid != null else null
	if stack == null or def == null:
		return
	var lines := PackedStringArray([def.display_name.to_upper()])
	if def.description != "":
		lines.append(def.description)
	var place := grid.placement(uid)
	var foot := def.footprint(place.rot)
	lines.append("Tamaño: %d × %d celdas%s · %s" % [def.size.x, def.size.y,
			" (girado %d°: %d × %d)" % [place.rot * 90, foot.x, foot.y] if place.rot != 0 else "",
			"se puede girar" if def.can_rotate else "no se gira"])
	lines.append("Cantidad: %d%s" % [stack.quantity, " (pilas de hasta %d)" % def.stack_limit() if def.stackable else " · no se apila"])
	if not stack.state.is_empty():
		var parts := PackedStringArray()
		for key in stack.state:
			parts.append("%s: %s" % [key, stack.state[key]])
		lines.append("Estado: %s (solo se apila con otros de igual estado)" % ", ".join(parts))
	for ability in def.abilities:
		if ability != null and ability.describe() != "":
			lines.append(ability.describe())
	if ref == InvProtocol.OWN and _r().loadout != null:
		if _r().loadout.equipped_uid == uid:
			lines.append("Equipado")
		var slot := _r().loadout.slot_of(uid)
		if slot >= 0:
			lines.append("En el acceso rápido %s" % KEYS[slot])
	var box_name := ""
	if ref != InvProtocol.OWN:
		var box := net.container(ref)
		box_name = box.display_name if box != null else "una caja"
	lines.append("Está en: %s, celda (%d, %d)" % ["tu inventario" if ref == InvProtocol.OWN else box_name, place.cell.x + 1, place.cell.y + 1])
	lines.append("Id %d · versión %d" % [stack.uid, stack.ver])
	_inspect_text.text = "\n".join(lines)
	_inspect_uid = uid
	_inspect.reset_size()
	_inspect.show()
	_place_window.call_deferred(_inspect, (size - _inspect.size) / 2.0)


func _place_window(window: Control, at: Vector2) -> void:
	window.reset_size()
	window.position = Vector2(clampf(at.x, 8.0, maxf(size.x - window.size.x - 8.0, 8.0)),
			clampf(at.y, 8.0, maxf(size.y - window.size.y - 8.0, 8.0)))


func _over_window(point: Vector2) -> bool:
	for window in [_menu, _dialog, _inspect]:
		if window.visible and window.get_rect().has_point(point):
			return true
	return false


# --- Geometría -----------------------------------------------------------------------

func _grid(ref: int) -> InvGrid:
	if net == null:
		return null
	if ref == InvProtocol.OWN:
		return _r().shown_own()
	return _r().shown_box() if ref == _r().box_id and ref != 0 else null


## Las grillas que se ven: la propia y, si hay, la caja abierta.
func _refs() -> Array:
	var list := []
	if _r().shown_own() != null:
		list.append(InvProtocol.OWN)
	if _r().box != null and _r().box_id != 0:
		list.append(_r().box_id)
	return list


func _grid_of_uid(uid: int) -> InvGrid:
	for ref in _refs():
		if _grid(ref).has(uid):
			return _grid(ref)
	return null


func _layout() -> void:
	var rows := _r().shown_own().rows if _r().shown_own() != null else 16
	var waiting := _waiting_box()
	if _r().box != null:
		rows = maxi(rows, _r().box.rows)
	elif waiting != null:
		# La que se espera ya cuenta: al llegar, las celdas no cambian de tamaño.
		rows = maxi(rows, waiting.rows)
	var available := size.y - 24.0 - HEADER - PAD * 2.0 - SLOT_SIZE - 64.0
	_cs = clampf(floorf(available / rows), 16.0, float(cell_size))


func _grid_rect(ref: int) -> Rect2:
	var grid := _grid(ref)
	if grid == null:
		return Rect2()
	var origin := Vector2(24.0 + PAD, 24.0 + HEADER)
	if ref != InvProtocol.OWN and _r().shown_own() != null:
		origin.x += _r().shown_own().columns * _cs + PAD * 2.0 + 28.0
	return Rect2(origin, Vector2(grid.columns, grid.rows) * _cs)


func _panel_rect(ref: int) -> Rect2:
	return _frame_of(_grid_rect(ref))


## El panel que rodea una grilla: el borde y el lugar del título.
func _frame_of(rect: Rect2) -> Rect2:
	return Rect2(rect.position - Vector2(PAD, PAD + HEADER), rect.size + Vector2(PAD * 2.0, PAD * 2.0 + HEADER))


## La caja pedida que el host todavía no abrió, si se ve en la escena, o null.
func _waiting_box() -> InvContainer:
	if _box_wait.is_empty() or net == null or (_r().box != null and _r().box_id != 0):
		return null
	return net.container(_box_wait["id"])


## Dónde va a estar la grilla de la caja que se espera, con sus medidas (las
## de la caja en la escena, las mismas que manda el host), o vacío: el lugar
## reservado. Al llegar la caja, su grilla ocupa exactamente esto.
func _reserved_grid_rect() -> Rect2:
	var box := _waiting_box()
	if box == null or not is_open or _r().shown_own() == null:
		return Rect2()
	var origin := Vector2(24.0 + PAD, 24.0 + HEADER)
	origin.x += _r().shown_own().columns * _cs + PAD * 2.0 + 28.0
	return Rect2(origin, Vector2(box.columns, box.rows) * _cs)


func _reserved_panel_rect() -> Rect2:
	var rect := _reserved_grid_rect()
	return _frame_of(rect) if rect.has_area() else Rect2()


func _item_rect(ref: int, uid: int) -> Rect2:
	var grid := _grid(ref)
	var area := grid.rect_of(uid)
	return Rect2(_grid_rect(ref).position + Vector2(area.position) * _cs, Vector2(area.size) * _cs)


## [inventario, id] del objeto que se ve bajo ese punto, o vacío.
func _item_at(point: Vector2) -> Array:
	for ref in _refs():
		var rect := _grid_rect(ref)
		if rect.has_point(point):
			var uid := _grid(ref).uid_at(Vector2i(((point - rect.position) / _cs).floor()))
			return [ref, uid] if uid != 0 and _shown(ref, uid) else []
	return []


## Para el HUD (Hud/Instrumentos), que no tiene que tapar nada de esto:
## "grid_bottom", hasta dónde baja la grilla propia abierta en el peor caso (con
## una caja más alta las celdas se achican y baja menos), así los instrumentos
## entran debajo con el inventario abierto o cerrado; "panels_right", dónde
## terminan a la derecha las grillas abiertas (0 con el inventario cerrado); y
## "hotbar", la barra rápida.
func hud_limits() -> Dictionary:
	var rows := float(_r().shown_own().rows if net != null and _r().shown_own() != null else net.player_rows if net != null else 16)
	var available := size.y - 24.0 - HEADER - PAD * 2.0 - SLOT_SIZE - 64.0
	var cs := clampf(floorf(available / rows), 16.0, float(cell_size))
	var right := 0.0
	if is_open and net != null:
		for ref in _refs():
			right = maxf(right, _panel_rect(ref).end.x)
		right = maxf(right, side_panel_rect().end.x)
		right = maxf(right, _reserved_panel_rect().end.x)
	return {"grid_bottom": 24.0 + HEADER + rows * cs + PAD, "panels_right": right, "hotbar": _hotbar_rect()}


## El panel de la derecha de la interfaz del jugador (desde el 2026-11-05): al
## lado de la grilla propia, en el lugar de la caja y con su mismo alto. Hoy lo
## ocupa la integridad corporal, que dibuja el HUD (LabHud). Con una caja
## abierta, la caja tiene prioridad (para seguir pasando objetos) y el panel no
## se ve: vacío. También vacío con el inventario cerrado. Un clic con un
## objeto en la mano ahí no lo suelta al piso. Desde el 2026-11-08, también
## vacío con una caja pedida que el host todavía no abrió: ese lugar es de ella
## (is_waiting_box).
func side_panel_rect() -> Rect2:
	if not is_open or not _active() or _r().shown_own() == null or (_r().box != null and _r().box_id != 0) \
			or not _box_wait.is_empty():
		return Rect2()
	_layout()
	var own := _panel_rect(InvProtocol.OWN)
	var width := clampf(own.size.y * 0.55, 230.0, 360.0)
	return Rect2(Vector2(own.end.x + 28.0, own.position.y), Vector2(width, own.size.y))


func _hotbar_rect() -> Rect2:
	var width := KEYS.size() * SLOT_SIZE + (KEYS.size() - 1) * SLOT_GAP
	return Rect2(Vector2((size.x - width) / 2.0, size.y - SLOT_SIZE - 18.0), Vector2(width, SLOT_SIZE))


func _slot_rect(slot: int) -> Rect2:
	var bar := _hotbar_rect()
	return Rect2(bar.position + Vector2(slot * (SLOT_SIZE + SLOT_GAP), 0.0), Vector2(SLOT_SIZE, SLOT_SIZE))


func _slot_at(point: Vector2) -> int:
	for i in KEYS.size():
		if _slot_rect(i).has_point(point):
			return i
	return -1


# --- Dibujo ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _toast != "" and Time.get_ticks_msec() > _toast_until:
		_toast = ""
	if not _box_wait.is_empty() and net != null and not _r().pending.has(_box_wait["seq"]):
		# Sin respuesta a tiempo (InvReplica.expire_pending). Una respuesta
		# limpia _box_wait en el mismo paquete, antes de llegar acá.
		_say("El host no contestó: %s no se abrió" % (_box_wait["name"] if _box_wait["name"] != "" else "la caja"))
		_box_wait_failed()
	if _active():
		queue_redraw()


func _draw() -> void:
	if not _active():
		return
	_layout()
	if is_open:
		if not _r().has_state:
			_text(Vector2(34, 60), "Esperando el inventario del host…", font_size + 2, Color.WHITE)
		for ref in _refs():
			_draw_grid(ref)
		_draw_reserved_box()
		if _mode == Mode.HOLD or _mode == Mode.SPLIT_PLACE:
			_draw_hold()
	_draw_hotbar()
	_draw_prompt()
	_draw_hover()


func _draw_grid(ref: int) -> void:
	var grid := _grid(ref)
	var rect := _grid_rect(ref)
	var title := "Tu inventario"
	if ref != InvProtocol.OWN:
		var box := net.container(ref)
		title = _box_title(box.display_name if box != null else "Caja")
	var hint := "Clic agarra y deja · R gira · clic der.: menú, o una unidad" if ref == InvProtocol.OWN else BOX_HINT
	_draw_frame(rect, title, hint, grid.columns, grid.rows)
	for seq in _sent:
		var sent: Dictionary = _sent[seq]
		if sent.get("ref", -1) == ref and sent.has("rect") and sent["rect"].size != Vector2i.ZERO:
			_draw_pending_area(rect, sent["rect"], "")
	for entry: Dictionary in _placing:
		if entry["ref"] == ref and entry["rect"].size != Vector2i.ZERO:
			_draw_pending_area(rect, entry["rect"], "" if entry["all"] else "+%d" % entry["count"])
	for uid in grid.sorted_uids():
		if _shown(ref, uid):
			_draw_item(ref, uid)


## El fondo de una grilla: su panel, el título con las medidas, la ayuda y las
## líneas de las celdas, sin los objetos.
func _draw_frame(rect: Rect2, title: String, hint: String, columns: int, rows: int) -> void:
	draw_rect(_frame_of(rect), PANEL_COLOR)
	_text(rect.position + Vector2(0, -HEADER + 18), "%s · %d × %d" % [title, columns, rows], font_size + 2, Color.WHITE)
	_text(rect.position + Vector2(0, -8), hint, font_size - 3, Color(1, 1, 1, 0.6))
	draw_rect(rect, Color(0, 0, 0, 0.35))
	for x in columns + 1:
		draw_line(rect.position + Vector2(x * _cs, 0), rect.position + Vector2(x * _cs, rect.size.y), LINE_COLOR)
	for y in rows + 1:
		draw_line(rect.position + Vector2(0, y * _cs), rect.position + Vector2(rect.size.x, y * _cs), LINE_COLOR)


func _box_title(shown_name: String) -> String:
	return "%s (compartida)" % shown_name


## El lugar de la caja pedida mientras el host contesta (desde el 2026-11-08):
## el mismo panel, título y grilla vacía que va a tener, en el mismo lugar, así
## al llegar solo aparecen sus objetos. Si tarda (BOX_WAIT_TEXT_MSEC), dice
## "Abriendo…" en el medio.
func _draw_reserved_box() -> void:
	var rect := _reserved_grid_rect()
	if not rect.has_area():
		return
	var box := _waiting_box()
	_draw_frame(rect, _box_title(box.display_name), BOX_HINT, box.columns, box.rows)
	if Time.get_ticks_msec() - int(_box_wait["msec"]) >= BOX_WAIT_TEXT_MSEC:
		_text_center(rect.get_center() + Vector2(0, 6), "Abriendo…", font_size + 1, Color(1, 1, 1, 0.7))


## Un lugar que espera al host: el borde amarillo y, si hay, cuántos van.
func _draw_pending_area(grid_rect: Rect2, area: Rect2i, label: String) -> void:
	var shown := Rect2(grid_rect.position + Vector2(area.position) * _cs, Vector2(area.size) * _cs).grow(-2)
	draw_rect(shown, PENDING_COLOR, false, 2.0)
	if label != "":
		_text(shown.position + Vector2(4, 16), label, font_size - 2, PENDING_COLOR)


## Si un objeto se ve en su lugar. Lo que está en la mano no: su lugar queda
## vacío. Tampoco lo que ya se dejó entero en otro lado y espera al host: ahí
## se ve el borde amarillo.
func _shown(ref: int, uid: int) -> bool:
	if _mode == Mode.HOLD and _hold.get("uid", 0) == uid and _hold.get("src", -1) == ref:
		return false
	return _staying(ref, uid) > 0


func _draw_item(ref: int, uid: int) -> void:
	var grid := _grid(ref)
	var stack := grid.get_stack(uid)
	var def := grid.def_of(uid)
	var rect := _item_rect(ref, uid).grow(-2)
	_draw_visual(rect, def, grid.placement(uid).rot, 1.0)
	if stack.quantity > 1:
		_text_right(rect.end - Vector2(4, 4), "×%d" % stack.quantity, font_size - 1, Color.WHITE)
	if ref == InvProtocol.OWN and _r().loadout != null:
		var slot := _r().loadout.slot_of(uid)
		if slot >= 0:
			_badge(rect.position + Vector2(rect.size.x - 16, 2), KEYS[slot], Color(0.2, 0.45, 0.9))
		if _r().loadout.equipped_uid == uid:
			_badge(rect.position + Vector2(2, rect.size.y - 18), "EQ", Color(0.8, 0.45, 0.1))
	if _waiting(uid):
		draw_rect(rect, Color(PENDING_COLOR, 0.25))
		draw_rect(rect, PENDING_COLOR, false, 2.0)
		_text(rect.position + Vector2(4, 16), "esperando…", font_size - 3, PENDING_COLOR)


## La imagen del objeto en ese rectángulo, girada de a 90° en el sentido del
## reloj según `rot`. Sin imagen, un rectángulo de su color con el nombre.
func _draw_visual(rect: Rect2, def: InvItemDef, rot: int, alpha: float) -> void:
	var color := def.color if def != null else Color.GRAY
	draw_rect(rect, Color(color.darkened(0.55), 0.85 * alpha))
	draw_rect(rect, Color(color.lightened(0.2), 0.7 * alpha), false, 1.0)
	var texture := thumbnails.texture_for(def)
	if texture != null:
		InvThumbnails.draw_turned(self, texture, rect, rot, Color(1, 1, 1, alpha))
	else:
		var label := def.display_name if def != null else "?"
		draw_string(get_theme_default_font(), rect.position + Vector2(4, minf(rect.size.y / 2.0 + 5.0, rect.size.y - 4.0)), label,
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8.0, font_size - 3, Color(1, 1, 1, alpha))


func _draw_hold() -> void:
	var def: InvItemDef = _hold["def"]
	var split := _mode == Mode.SPLIT_PLACE
	var target := _drop_target(_hold, _mouse, "split" if split else "all", not split)
	if target.has("ref") and target.has("cell") and target.has("foot") and _grid(target["ref"]) != null:
		var origin := _grid_rect(target["ref"]).position
		var color: Color = VALID_COLOR if target["kind"] == "move" else MERGE_COLOR if target["kind"] == "merge" else INVALID_COLOR
		var area := Rect2(origin + Vector2(target["cell"]) * _cs, Vector2(target["foot"]) * _cs)
		draw_rect(area.intersection(_grid_rect(target["ref"])), color)
	var ghost := Rect2(_mouse - _grab_offset(_hold), Vector2(def.footprint(_hold["rot"])) * _cs).grow(-2)
	_draw_visual(ghost, def, _hold["rot"], 0.8)
	var quantity := _held_quantity(_hold)
	if quantity > 1:
		_text_right(ghost.end - Vector2(4, 4), "×%d" % quantity, font_size - 1, Color.WHITE)
	var label := ""
	match target["kind"]:
		"move":
			label = "clic derecho: deja una" if not split and quantity > 1 else ""
		"merge":
			label = "apilar · clic derecho: suma una" if quantity > 1 else "apilar"
		"slot":
			label = "al acceso %s" % KEYS[target["slot"]]
		"world":
			label = "soltar al piso"
		"part":
			label = "curar %s" % String(body_panel.call("part_name", target["part"])).to_lower()
		"invalid":
			label = target.get("reason", "")
	if label != "":
		_text(_mouse + Vector2(16, -10), label, font_size - 1,
				INVALID_COLOR.lightened(0.4) if target["kind"] == "invalid" else Color.WHITE)


func _draw_hotbar() -> void:
	var loadout := _r().loadout
	var bar := _hotbar_rect()
	draw_rect(bar.grow(6), Color(PANEL_COLOR, 0.6))
	for i in KEYS.size():
		var rect := _slot_rect(i)
		draw_rect(rect, Color(0, 0, 0, 0.5))
		var uid := loadout.hotbar[i] if loadout != null else 0
		var stack := _r().shown_own().get_stack(uid) if uid != 0 and _r().shown_own() != null else null
		if stack != null:
			var def := _r().shown_own().def_of(uid)
			_draw_visual(rect.grow(-3), def, 0, 0.45 if _mode == Mode.SLOT_HOLD and _slot_from == i else 1.0)
			if stack.quantity > 1:
				_text_right(rect.end - Vector2(4, 4), "%d" % stack.quantity, font_size - 1, Color.WHITE)
			if loadout.equipped_uid == uid:
				_badge(rect.position + Vector2(rect.size.x - 24, 2), "EQ", Color(0.8, 0.45, 0.1))
		var highlight := is_open and (_mode == Mode.HOLD or _mode == Mode.SLOT_HOLD) and _slot_at(_mouse) == i
		draw_rect(rect, Color(1, 1, 1, 0.9 if highlight else 0.35), false, 2.0 if highlight else 1.0)
		if _r().is_slot_pending(i):
			draw_rect(rect, PENDING_COLOR, false, 2.0)
		_text(rect.position + Vector2(4, 15), KEYS[i], font_size - 2, Color(1, 1, 1, 0.8))
	# A la izquierda de la barra van los instrumentos del HUD: lo de la barra
	# se escribe a la derecha. (Hasta el 2026-11-01, a la izquierda decía la
	# vitalidad de prueba, que ya no existe: ahora es la salud del HUD.)
	var y := bar.position.y + 16
	if loadout != null and loadout.equipped_uid != 0 and _r().shown_own() != null:
		var def := _r().shown_own().def_of(loadout.equipped_uid)
		_text(Vector2(bar.end.x + 14, y), "Equipado: %s" % (def.display_name if def != null else "?"), font_size - 1, Color(1.0, 0.75, 0.45))
		y += 20
	if is_open:
		_text(Vector2(bar.end.x + 14, y), "Clic en un objeto y después en un acceso", font_size - 3, Color(1, 1, 1, 0.6))
		_text(Vector2(bar.end.x + 14, y + 17), "Clic derecho en un acceso lo vacía", font_size - 3, Color(1, 1, 1, 0.6))


## Encima de la barra: el último aviso y, con el inventario cerrado, cómo
## abrirlo. Desde el 2026-11-06 no hay aviso de interacción ("E: recoger …",
## "E: abrir …", "E: cerrar …"): lo que E elegiría lo marca el indicador del
## HUD, junto al objetivo, solo con su nombre.
func _draw_prompt() -> void:
	var bar := _hotbar_rect()
	var y := bar.position.y - 20.0
	if _toast != "":
		_text_center(Vector2(size.x / 2.0, y), _toast, font_size + 1, Color(1.0, 0.85, 0.5))
		y -= 26.0
	if _modal_open() or _mode != Mode.NONE:
		return
	if not is_open:
		_text_center(Vector2(size.x / 2.0, y), "Tab: inventario", font_size - 2, Color(1, 1, 1, 0.5))


## El nombre de lo que está bajo el cursor (un objeto de una grilla o de un
## acceso de la barra), con la mano vacía y sin menús; si no, vacío.
func _hover_name() -> String:
	if not is_open or _mode != Mode.NONE or _menu.visible or _modal_open():
		return ""
	var def: InvItemDef = null
	var hit := _item_at(_mouse)
	if not hit.is_empty():
		def = _grid(hit[0]).def_of(hit[1])
	else:
		var slot := _slot_at(_mouse)
		var loadout := _r().loadout
		if slot >= 0 and loadout != null and loadout.hotbar[slot] != 0 and _r().shown_own() != null:
			def = _r().shown_own().def_of(loadout.hotbar[slot])
	return def.display_name if def != null else ""


## Un cartelito con el nombre, al lado del cursor y adentro de la pantalla.
func _draw_hover() -> void:
	var text := _hover_name()
	if text == "":
		return
	var font := get_theme_default_font()
	var box := Rect2(_mouse + Vector2(14, 18), font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + Vector2(12, 8))
	box.position = box.position.clamp(Vector2.ZERO, (size - box.size).max(Vector2.ZERO))
	draw_rect(box, Color(0.02, 0.02, 0.03, 0.92))
	draw_rect(box, Color(1, 1, 1, 0.35), false, 1.0)
	draw_string(font, box.position + Vector2(6, 4 + font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _badge(at: Vector2, text: String, color: Color) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 4).x + 6.0
	draw_rect(Rect2(at, Vector2(width, 16)), color)
	draw_string(font, at + Vector2(3, 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 4, Color.WHITE)


func _text(at: Vector2, text: String, font_px: int, color: Color) -> void:
	draw_string_outline(get_theme_default_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 4, Color(0, 0, 0, color.a * 0.8))
	draw_string(get_theme_default_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)


func _text_right(at: Vector2, text: String, font_px: int, color: Color) -> void:
	var width := get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	_text(at - Vector2(width, 0), text, font_px, color)


func _text_center(at: Vector2, text: String, font_px: int, color: Color) -> void:
	var width := get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	_text(at - Vector2(width / 2.0, 0), text, font_px, color)


func _say(text: String) -> void:
	_toast = text
	_toast_until = Time.get_ticks_msec() + TOAST_MSEC
	queue_redraw()


## Un motivo del host como oración: con mayúscula al principio.
func _sentence(reason: String) -> String:
	return reason.left(1).to_upper() + reason.substr(1) if reason != "" else reason


## Para las pruebas: el último aviso que se mostró.
func last_message() -> String:
	return _toast
