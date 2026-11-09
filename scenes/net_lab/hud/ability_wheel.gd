class_name AbilityWheel
extends Control

## Selector radial de habilidades (punto 2 del roadmap, 2026-11-08). Mientras
## se mantiene Q (acción `selector_habilidades` del Mapa de entrada) aparece un
## círculo en el medio de la pantalla con un sector por habilidad: a la
## izquierda velocidad y salto, a la derecha cámara lenta (decisión del usuario,
## 2026-11-08), con los mismos íconos que las luces del HUD.
##
## - Mientras está abierto, el movimiento del mouse mueve el indicador y no la
##   cámara (se queda con el movimiento antes que LabCamera). El mundo sigue
##   corriendo y se sigue caminando, saltando y usando la barra rápida.
## - El indicador sale del centro hacia donde se movió el mouse desde que se
##   apretó Q y marca el sector de esa dirección, aunque el mouse se haya ido
##   más allá del círculo. Mientras no se mueva `dead_zone` píxeles, queda en el
##   centro y no marca nada.
## - Al soltar Q se cierra. Con un sector marcado, avisa cuál (`chosen`) y el
##   laboratorio lo prende o lo apaga con el mismo contador que el 1 o el 2 del
##   teclado numérico, que siguen andando: viaja en el input, se predice y lo
##   cuenta el host como siempre, con el costo y el agotamiento de siempre. En
##   el centro no cambia nada.
##
## Elecciones de Claude (no del usuario): con el inventario abierto, Q no abre
## el selector; abrir el inventario con el selector abierto, perder el
## foco de la ventana o cortarse la conexión lo cierran sin cambiar nada; cada
## sector dice si su habilidad está prendida; mientras está abierto, el
## laboratorio oculta su panel de texto (como con el inventario).
##
## Para sumar una habilidad: una fila en SECTORS con su bit de ActorPowers (y su
## ícono en ActorPowers.LIST); el círculo se reparte solo en partes iguales.

## Avisa la habilidad elegida al soltar Q: su bit de ActorPowers.
signal chosen(bit: int)

const ACTION := &"selector_habilidades"
## Cada sector: su habilidad (bit de ActorPowers), su nombre y hacia dónde queda
## su centro, en grados (0 a la derecha, 90 arriba, 180 a la izquierda). Cada uno
## ocupa la misma porción del círculo; gana el que tenga el centro más cerca de
## la dirección del mouse.
const SECTORS := [
	{"bit": ActorPowers.BOOST, "name": "Velocidad y salto", "angle": 180.0},
	{"bit": ActorPowers.SLOW, "name": "Cámara lenta", "angle": 0.0},
]

## Con el inventario abierto, Q no abre el selector; si se abre el inventario,
## el selector se cierra sin cambiar nada.
@export var inventory_ui: InvUI

@export_group("Mouse")
## Cuánto hay que mover el mouse desde que se apretó Q, en píxeles, para marcar
## un sector. Menos que eso es el centro: soltar Q ahí no cambia nada.
@export_range(4.0, 200.0, 1.0) var dead_zone := 40.0
## Hasta dónde se junta el movimiento, en zonas muertas: más allá no suma, así
## que para pasar al otro lado alcanza con volver un poco más que eso.
@export_range(1.5, 6.0, 0.1) var reach := 2.5

@export_group("Tamaño")
## Por cuánto se multiplica el tamaño que se calcula solo para la pantalla.
@export_range(0.5, 1.5, 0.05) var size_scale := 1.0

var is_open := false
## Para las pruebas: cuántas veces se abrió y cuántas se eligió algo.
var opens := 0
var choices := 0
var _actor: ActorBody
## Cuánto se movió el mouse desde que se apretó Q, en píxeles.
var _pointer := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	if inventory_ui != null:
		inventory_ui.opened.connect(cancel)


## El laboratorio lo prende cuando aparece el personaje propio.
func activate(actor: ActorBody) -> void:
	_actor = actor
	cancel()


func connection_lost() -> void:
	cancel()
	_actor = null


## Lo cierra sin cambiar nada.
func cancel() -> void:
	if not is_open:
		return
	is_open = false
	queue_redraw()


## El movimiento del mouse que va juntando el indicador desde que se apretó Q.
func pointer() -> Vector2:
	return _pointer


## El sector que se elegiría al soltar Q ahora (su índice en SECTORS), o -1 en el
## centro o con el selector cerrado.
func hovered_sector() -> int:
	if not is_open or _pointer.length() < dead_zone:
		return -1
	# En la pantalla y crece hacia abajo: se da vuelta para que 90° sea arriba.
	var angle := atan2(-_pointer.y, _pointer.x)
	var best := -1
	var best_gap := INF
	for i in SECTORS.size():
		var gap := absf(angle_difference(angle, deg_to_rad(SECTORS[i]["angle"])))
		if gap < best_gap:
			best_gap = gap
			best = i
	return best


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		if _can_open():
			is_open = true
			_pointer = Vector2.ZERO
			opens += 1
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif event.is_action_released(ACTION):
		if is_open:
			_confirm()
			get_viewport().set_input_as_handled()
	elif is_open and event is InputEventMouseMotion:
		_pointer = (_pointer + event.relative).limit_length(dead_zone * reach)
		queue_redraw()
		# La cámara no lo recibe: no gira mientras el selector está abierto.
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	if is_open or not is_instance_valid(_actor) or not _actor.is_inside_tree():
		return false
	return inventory_ui == null or not inventory_ui.is_open


## Soltar Q: cierra y, si había un sector marcado, avisa su habilidad.
func _confirm() -> void:
	var sector := hovered_sector()
	is_open = false
	queue_redraw()
	if sector >= 0:
		choices += 1
		chosen.emit(SECTORS[sector]["bit"])


func _notification(what: int) -> void:
	# Sin foco, el soltar Q no llega: se cierra sin cambiar nada.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel()


# --- Dibujo ------------------------------------------------------------------------

const BACK := Color(0.07, 0.08, 0.1, 0.8)
const SECTOR_FILL := Color(0.16, 0.17, 0.19, 0.9)
const SECTOR_HOVER := Color(0.36, 0.3, 0.22, 0.95)
const EDGE := Color(0.32, 0.34, 0.36, 0.95)
const EDGE_HOVER := Color(0.95, 0.55, 0.15)
const NEEDLE := Color(0.95, 0.33, 0.08)
const ON := Color(0.3, 0.95, 0.4)
const OFF := Color(0.93, 0.93, 0.9)
## Lo que se deja sin pintar entre dos sectores, en grados de cada lado.
const GAP_DEGREES := 1.5


## El tamaño del círculo en la pantalla: [radio de afuera, radio del centro].
func radii() -> Array:
	var outer := clampf(size.y * 0.2, 110.0, 240.0) * size_scale
	return [outer, outer * 0.3]


func _draw() -> void:
	if not is_open:
		return
	var center := size / 2.0
	var r: Array = radii()
	var outer: float = r[0]
	var inner: float = r[1]
	var hovered := hovered_sector()
	draw_circle(center, outer + 8.0, BACK)
	var span := 360.0 / SECTORS.size()
	for i in SECTORS.size():
		var sector: Dictionary = SECTORS[i]
		var from := deg_to_rad(sector["angle"] - span / 2.0 + GAP_DEGREES)
		var to := deg_to_rad(sector["angle"] + span / 2.0 - GAP_DEGREES)
		var points := PackedVector2Array()
		var steps := 32
		for k in steps + 1:
			points.append(center + _dir(lerpf(from, to, k / float(steps))) * outer)
		for k in steps + 1:
			points.append(center + _dir(lerpf(to, from, k / float(steps))) * inner)
		var marked := i == hovered
		draw_colored_polygon(points, SECTOR_HOVER if marked else SECTOR_FILL)
		points.append(points[0])
		draw_polyline(points, EDGE_HOVER if marked else EDGE, 3.0 if marked else 1.5, true)
		var on: bool = is_instance_valid(_actor) and (_actor.state.powers & sector["bit"]) != 0
		var middle := center + _dir(deg_to_rad(sector["angle"])) * (inner + outer) / 2.0
		var icon_size := outer * 0.15
		LabHud.draw_icon(self, _icon_of(sector["bit"]), middle - Vector2(0, outer * 0.1), icon_size, ON if on else OFF)
		var font_px := clampf(outer * 0.085, 11.0, 17.0)
		_caption(middle + Vector2(0, outer * 0.16), sector["name"], font_px, Color.WHITE)
		_caption(middle + Vector2(0, outer * 0.16 + font_px * 1.3), "Prendida" if on else "Apagada",
				font_px * 0.85, ON if on else Color(1, 1, 1, 0.55))
	# El centro: soltar acá no cambia nada.
	draw_circle(center, inner - 4.0, Color(0.11, 0.12, 0.13, 0.95))
	draw_arc(center, inner - 4.0, 0.0, TAU, 48, EDGE, 1.5, true)
	_draw_indicator(center, outer, inner, hovered >= 0)
	_caption(center + Vector2(0, outer + 30.0),
			"Mové el mouse hacia una habilidad y soltá Q · en el centro no cambia nada",
			clampf(outer * 0.075, 11.0, 15.0), Color(1, 1, 1, 0.8))


## La aguja sale del centro hacia donde se movió el mouse: hasta el borde si
## marca un sector, y dentro del centro mientras no pase la zona muerta.
func _draw_indicator(center: Vector2, outer: float, inner: float, marked: bool) -> void:
	var length := _pointer.length()
	if length > 0.5:
		var direction := _pointer / length
		var reach_px := outer * 0.96 if marked else (inner - 6.0) * clampf(length / dead_zone, 0.0, 1.0)
		var side := Vector2(-direction.y, direction.x) * maxf(outer * 0.03, 3.0)
		var tip := center + direction * reach_px
		draw_colored_polygon(PackedVector2Array([tip, center + side, center - direction * outer * 0.06, center - side]),
				NEEDLE if marked else Color(NEEDLE, 0.55))
	draw_circle(center, maxf(outer * 0.05, 5.0), Color(0.85, 0.85, 0.85))
	draw_circle(center, maxf(outer * 0.028, 3.0), Color(0.15, 0.15, 0.16))


## Hacia dónde queda un ángulo en la pantalla (0 a la derecha, π/2 arriba).
static func _dir(angle: float) -> Vector2:
	return Vector2(cos(angle), -sin(angle))


static func _icon_of(bit: int) -> StringName:
	for power: Dictionary in ActorPowers.LIST:
		if power["bit"] == bit:
			return power["icon"]
	return &"?"


func _caption(at: Vector2, text: String, font_px: float, color: Color) -> void:
	var font := get_theme_default_font()
	var px := maxi(roundi(font_px), 6)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var base := at + Vector2(-width / 2.0, px * 0.35)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(roundi(px / 5.0), 2), Color(0, 0, 0, color.a * 0.7))
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
