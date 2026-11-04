class_name LabHud
extends Control

## HUD del jugador local (2026-11-02): abajo a la izquierda, la salud (de 0 a
## 10), la estamina (de 0 a 200) y el termómetro (de 0 a 100); arriba, una luz
## por cada estado propio prendido. Sigue el concepto del usuario
## (`otro proyecto bobo/texuras/hud/hud 3.png`) con sus correcciones: todo
## dibujado acá, sin fotos, marcas ni textos de RPM o km/h.
##
## Solo muestra: lee el estado del personaje propio (ActorState, el predicho en
## un cliente y el que vale en el host) y nunca lo cambia. No toma el mouse ni
## el teclado.
##
## - Salud: la aguja marca la proporción de la salud en la escala de 0 a 10,
##   también entre dos números. La luz naranja de abajo queda apagada:
##   reservada para la integridad del cuerpo, que todavía no existe.
## - Estamina: de 0 a 200, la proporción de la reserva.
## - Termómetro: marca 100 fijo. No mide la luz: es el lugar del futuro sensor.
## - Luces: una por estado propio prendido (ActorPowers.LIST), las que sean.
##   Sin ninguno, no aparece nada. La cámara lenta que pidió otro jugador no
##   prende la luz propia.
## - Muerte de prueba: un aviso en el medio de la pantalla, sin pausar ni
##   bloquear nada, cuando sube ActorState.deaths.
## - Agotamiento: un sonido leve, una vez, cuando sube ActorState.exhaustions.
##
## Los dos avisos salen de contadores del estado y no de cuántas veces se ve
## un valor: repetir ticks o corregir no los repite, y al entrar tarde o volver
## de un corte se toma el número que haya, sin avisar lo de antes. Un
## agotamiento predicho que el host corrige (por ejemplo, porque un consumible
## llegó justo antes) ya sonó; si después se agota de verdad con el mismo
## número, no vuelve a sonar.

## Para ubicar los instrumentos y las luces sin tapar la grilla ni la barra.
@export var inventory_ui: InvUI
## Los máximos de salud y estamina.
@export var tuning: ActorTuning

@export_group("Tamaño")
## Por cuánto se multiplica el tamaño que se calcula solo para la pantalla.
## Más grande no pasa del lugar que hay debajo de la grilla del inventario.
@export_range(0.5, 1.5, 0.05) var size_scale := 1.0

@export_group("Agujas")
## Qué tan rápido sigue la aguja al valor, por segundo. Es solo dibujo: el valor
## no cambia, y con la reserva en cero la aguja termina en cero.
@export_range(2.0, 60.0, 0.5) var needle_follow := 14.0

@export_group("Aviso de muerte")
## Cuánto dura el aviso, en segundos reales.
@export_range(0.5, 10.0, 0.1) var death_notice_seconds := 2.5
@export var death_text := "Moriste"
@export var death_detail := "Muerte de prueba: la salud volvió al máximo y se apagaron tus estados"

@export_group("Agotamiento")
## El sonido cuando la estamina llega a cero y se apagan los estados (de
## fábrica, `estados_apagados.wav`, dos notas cortas que bajan). Vacío, no suena.
@export var exhaustion_sound: AudioStream
@export_range(-40.0, 6.0, 0.5) var exhaustion_volume_db := -6.0

## Para las pruebas: cuántos avisos de muerte y sonidos de agotamiento salieron.
var deaths_shown := 0
var exhaustion_sounds := 0

var _actor: ActorBody
var _health_shown := 10.0
var _stamina_shown := 200.0
var _deaths_seen := 0
var _exhaustions_seen := 0
var _death_until_msec := 0
var _sound: AudioStreamPlayer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_sound = AudioStreamPlayer.new()
	_sound.name = "Agotamiento"
	add_child(_sound)


## El laboratorio la prende cuando aparece el personaje propio (también al
## volver de un corte, con su actor nuevo). Toma los contadores como están.
func activate(actor: ActorBody) -> void:
	_actor = actor
	_deaths_seen = actor.state.deaths
	_exhaustions_seen = actor.state.exhaustions
	_death_until_msec = 0
	_health_shown = _health_target()
	_stamina_shown = _stamina_target()
	queue_redraw()


func connection_lost() -> void:
	_actor = null
	_death_until_msec = 0
	queue_redraw()


func is_showing_death() -> bool:
	return Time.get_ticks_msec() < _death_until_msec


## Los estados propios prendidos, en el orden de ActorPowers.LIST.
func lit_powers() -> Array:
	if not _active():
		return []
	return ActorPowers.LIST.filter(func(power: Dictionary) -> bool: return _actor.state.powers & power["bit"])


## Lo que marcan las agujas ahora: [salud de 0 a 10, estamina de 0 a 200].
func needles() -> Array:
	return [_health_shown, _stamina_shown]


func _active() -> bool:
	return is_instance_valid(_actor) and tuning != null


func _health_target() -> float:
	return 10.0 * clampf(_actor.state.health / float(ActorVitals.max_health(tuning) * ActorState.HEALTH_UNIT), 0.0, 1.0)


func _stamina_target() -> float:
	var full := float(maxi(tuning.stamina_max, 1) * ActorPowers.STAMINA_UNIT)
	return 200.0 * clampf(_actor.state.stamina / full, 0.0, 1.0)


func _process(delta: float) -> void:
	if not _active():
		return
	var state := _actor.state
	var died := (state.deaths - _deaths_seen) & 0xFF
	if died != 0 and died < 128:
		_deaths_seen = state.deaths
		_death_until_msec = Time.get_ticks_msec() + roundi(death_notice_seconds * 1000.0)
		deaths_shown += 1
	var exhausted := (state.exhaustions - _exhaustions_seen) & 0xFF
	if exhausted != 0 and exhausted < 128:
		_exhaustions_seen = state.exhaustions
		exhaustion_sounds += 1
		if exhaustion_sound != null:
			_sound.stream = exhaustion_sound
			_sound.volume_db = exhaustion_volume_db
			_sound.play()
	# El delta de _process va con time_scale (la cámara lenta, el ritmo del
	# cliente): las agujas siguen al reloj real.
	var real := delta / maxf(Engine.time_scale, 0.01)
	_health_shown = _follow(_health_shown, _health_target(), 10.0, real)
	_stamina_shown = _follow(_stamina_shown, _stamina_target(), 200.0, real)
	queue_redraw()


## La aguja va hacia el valor rápido y llega en un tiempo finito: con la
## reserva en cero, termina en cero.
func _follow(shown: float, target: float, full: float, real_delta: float) -> float:
	var speed := maxf(absf(target - shown) * needle_follow, full * 0.6)
	return move_toward(shown, target, speed * real_delta)


# --- Dibujo ------------------------------------------------------------------------

const INK_DARK := Color(0.08, 0.08, 0.09)
const INK_LIGHT := Color(0.93, 0.93, 0.9)
const NEEDLE := Color(0.95, 0.33, 0.08)
const PLATE := Color(0.13, 0.14, 0.15, 0.92)
const PLATE_EDGE := Color(0.32, 0.34, 0.36, 0.95)
const LENS_ON := Color(0.3, 0.95, 0.4)
## Barrido de las escalas: de abajo a la izquierda, por arriba, hasta abajo a
## la derecha, simétrico (como el velocímetro del concepto), en grados desde
## arriba.
const SWEEP := 135.0


func _draw() -> void:
	if not _active():
		return
	var layout := _layout()
	_draw_instruments(layout)
	_draw_lights(layout)
	if is_showing_death():
		_draw_death()


## Dónde va cada cosa, según la pantalla y la interfaz del inventario: los
## instrumentos en el hueco entre el borde izquierdo, la barra rápida y lo más
## bajo que llega la grilla propia abierta, así no se tapan abierto ni cerrado.
func _layout() -> Dictionary:
	var limits := inventory_ui.hud_limits() if inventory_ui != null else {}
	var bar: Rect2 = limits.get("hotbar", Rect2(size.x / 2.0 - 317.0, size.y - 76.0, 634.0, 58.0))
	var top: float = limits.get("grid_bottom", size.y - 160.0) + 8.0
	var margin := 14.0
	var height := size.y - margin - top
	var width := bar.position.x - margin * 2.0
	# Placa: relleno, dos esferas de diámetro d, el termómetro (0,26 d) y dos huecos (0,07 d).
	var pad := 8.0
	var d := minf(height - pad * 2.0, (width - pad * 2.0) / 2.4)
	d = clampf(d * size_scale, 80.0, minf(height - pad * 2.0, 240.0))
	var plate := Rect2(margin, size.y - margin - d - pad * 2.0, d * 2.4 + pad * 2.0, d + pad * 2.0)
	return {"d": d, "plate": plate, "pad": pad, "panels_right": limits.get("panels_right", 0.0)}


func _draw_instruments(layout: Dictionary) -> void:
	var d: float = layout["d"]
	var plate: Rect2 = layout["plate"]
	var pad: float = layout["pad"]
	draw_rect(plate, PLATE)
	draw_rect(plate, PLATE_EDGE, false, 2.0)
	for corner in [plate.position + Vector2(6, 6), Vector2(plate.end.x - 6, plate.position.y + 6),
			Vector2(plate.position.x + 6, plate.end.y - 6), plate.end - Vector2(6, 6)]:
		draw_circle(corner, 2.5, Color(0.45, 0.47, 0.5))
		draw_line(corner - Vector2(1.6, 1.6), corner + Vector2(1.6, 1.6), Color(0.2, 0.21, 0.22), 1.0)
	var r := d / 2.0
	var health_center := plate.position + Vector2(pad + r, pad + r)
	var stamina_center := health_center + Vector2(d + d * 0.07, 0.0)
	_draw_health(health_center, r)
	_draw_stamina(stamina_center, r)
	var thermo := Rect2(Vector2(stamina_center.x + r + d * 0.07, plate.position.y + pad), Vector2(d * 0.26, d))
	_draw_thermometer(thermo)


## Bisel de metal, como el aro cromado del concepto.
func _draw_bezel(center: Vector2, r: float) -> void:
	draw_circle(center, r, Color(0.2, 0.21, 0.23))
	draw_circle(center, r * 0.985, Color(0.62, 0.64, 0.67))
	draw_arc(center, r * 0.95, deg_to_rad(200.0), deg_to_rad(340.0), 24, Color(0.88, 0.9, 0.92, 0.9), r * 0.03)
	draw_circle(center, r * 0.92, Color(0.3, 0.31, 0.33))


func _draw_health(center: Vector2, r: float) -> void:
	_draw_bezel(center, r)
	var face := r * 0.9
	draw_circle(center, face, INK_LIGHT)
	# Números de 0 a 10 y marcas sin número entre ellos, como una regla: de a
	# décimas si la esfera es grande, si no de a dos décimas.
	if face >= 62.0:
		_draw_scale(center, face, 10.0, 0.1, 5, 10, INK_DARK, 0.2)
	else:
		_draw_scale(center, face, 10.0, 0.2, 0, 5, INK_DARK, 0.2)
	_draw_caption(center + Vector2(0, face * 0.25), "SALUD", face * 0.12, Color(INK_DARK, 0.7))
	# La luz naranja va integrada abajo, donde el concepto tenía el RPM: apagada.
	var lamp := center + Vector2(0, face * 0.58)
	var lamp_r := face * 0.17
	draw_circle(lamp, lamp_r * 1.25, Color(0.55, 0.56, 0.58))
	draw_circle(lamp, lamp_r * 1.08, Color(0.18, 0.18, 0.19))
	draw_circle(lamp, lamp_r, Color(0.42, 0.22, 0.04))
	draw_circle(lamp + Vector2(-lamp_r * 0.32, -lamp_r * 0.35), lamp_r * 0.32, Color(0.75, 0.5, 0.25, 0.45))
	_draw_needle(center, face, _health_shown / 10.0, INK_DARK)


func _draw_stamina(center: Vector2, r: float) -> void:
	_draw_bezel(center, r)
	var face := r * 0.9
	draw_circle(center, face, Color(0.04, 0.04, 0.05))
	# Un número cada 20, como el concepto, con marcas de a 5 y de a 10. Con la
	# esfera chica no entran: un número cada 40, con marcas de a 5 y de a 20.
	if face >= 85.0:
		_draw_scale(center, face, 200.0, 5.0, 2, 4, INK_LIGHT, 0.15)
	else:
		_draw_scale(center, face, 200.0, 5.0, 4, 8, INK_LIGHT, 0.17)
	_draw_caption(center + Vector2(0, face * 0.3), "ESTAMINA", face * 0.11, Color(INK_LIGHT, 0.7))
	_draw_needle(center, face, _stamina_shown / 200.0, Color(0.85, 0.85, 0.85))


## Una escala de 0 a `full` con una marca chica cada `step`: cada `mid` marcas,
## una mediana (0: ninguna), y cada `numbered` marcas, una larga con su
## número, derecho, de `digits` de la esfera de alto.
func _draw_scale(center: Vector2, face: float, full: float, step: float, mid: int, numbered: int, ink: Color, digits: float) -> void:
	var steps := roundi(full / step)
	for i in steps + 1:
		var value := i * step
		var direction := _direction(value / full)
		var long := i % numbered == 0
		var medium := not long and mid > 0 and i % mid == 0
		var outer := face * 0.94
		var inner := face * (0.79 if long else 0.85 if medium else 0.89)
		var width := face * (0.035 if long else 0.022 if medium else 0.012)
		draw_line(center + direction * inner, center + direction * outer, ink, maxf(width, 1.0), true)
		if long:
			_draw_caption(center + direction * face * 0.63, "%d" % roundi(value), maxf(face * digits, 9.0), ink)


func _draw_needle(center: Vector2, face: float, fraction: float, cap: Color) -> void:
	var direction := _direction(clampf(fraction, 0.0, 1.0))
	var side := Vector2(-direction.y, direction.x)
	var tip := center + direction * face * 0.86
	var tail := center - direction * face * 0.16
	draw_colored_polygon(PackedVector2Array([tip, center + side * face * 0.035, tail, center - side * face * 0.035]), NEEDLE)
	draw_circle(center, face * 0.09, cap)
	draw_circle(center, face * 0.05, Color(0.15, 0.15, 0.16))


## Hacia dónde apunta una fracción de la escala: 0 abajo a la izquierda, 0,5
## arriba y 1 abajo a la derecha.
func _direction(fraction: float) -> Vector2:
	var angle := deg_to_rad(lerpf(-SWEEP, SWEEP, fraction))
	return Vector2(sin(angle), -cos(angle))


func _draw_thermometer(rect: Rect2) -> void:
	draw_rect(rect, Color(0.62, 0.5, 0.26))
	draw_rect(rect.grow(-rect.size.x * 0.08), Color(0.92, 0.91, 0.86))
	var w := rect.size.x
	var tube_x := rect.position.x + w * 0.32
	var top := rect.position.y + rect.size.y * 0.12
	var bottom := rect.end.y - rect.size.y * 0.13
	var tube_w := maxf(w * 0.14, 3.0)
	draw_rect(Rect2(tube_x - tube_w / 2.0, top, tube_w, bottom - top), Color(0.82, 0.86, 0.9))
	# Marca 100 fijo: todavía no hay un sensor de luz.
	var level := 100.0
	var fill_top := lerpf(bottom, top, level / 100.0)
	draw_rect(Rect2(tube_x - tube_w * 0.32, fill_top, tube_w * 0.64, bottom - fill_top), Color(0.15, 0.3, 0.85))
	draw_circle(Vector2(tube_x, bottom + tube_w * 0.6), tube_w * 0.95, Color(0.15, 0.3, 0.85))
	var font_px := clampf(w * 0.24, 8.0, 15.0)
	for value in range(0, 101, 10):
		var y := lerpf(bottom, top, value / 100.0)
		var long := value % 20 == 0
		draw_line(Vector2(tube_x + tube_w * 0.7, y), Vector2(tube_x + tube_w * (1.6 if long else 1.2), y), INK_DARK, 1.0)
		if long:
			_draw_text(Vector2(tube_x + tube_w * 1.8, y + font_px * 0.35), "%d" % value, font_px, INK_DARK)
	_draw_caption(Vector2(rect.position.x + w * 0.5, rect.position.y + rect.size.y * 0.06), "°C", font_px, Color(INK_DARK, 0.8))


## Las luces de arriba: una por estado propio prendido. Arriba al medio; con
## el inventario abierto, arriba a la derecha, lejos de sus grillas (el título
## de una caja puede salirse de su panel).
func _draw_lights(layout: Dictionary) -> void:
	var lit := lit_powers()
	if lit.is_empty():
		return
	var lamp := clampf(size.y * 0.055, 32.0, 56.0)
	var caption_px := roundi(clampf(lamp * 0.3, 11.0, 15.0))
	var font := get_theme_default_font()
	# Cada luz ocupa lo que mide ella o su nombre, lo que sea más ancho.
	var slots: Array[float] = []
	var width := 0.0
	for power: Dictionary in lit:
		var slot := maxf(lamp, font.get_string_size(power["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, caption_px).x + 8.0)
		slots.append(slot)
		width += slot
	width += (lit.size() - 1) * lamp * 0.35
	var x := (size.x - width) / 2.0
	if layout["panels_right"] > 0.0:
		x = size.x - 16.0 - width
	var y := 12.0
	for i in lit.size():
		var power: Dictionary = lit[i]
		var center := Vector2(x + slots[i] / 2.0, y + lamp / 2.0)
		x += slots[i] + lamp * 0.35
		var r := lamp / 2.0
		for k in 4:
			draw_circle(center, r * (1.55 - k * 0.12), Color(LENS_ON, 0.06 + k * 0.03))
		draw_circle(center, r, Color(0.55, 0.57, 0.6))
		draw_circle(center, r * 0.86, Color(0.12, 0.13, 0.14))
		draw_circle(center, r * 0.78, LENS_ON)
		draw_circle(center + Vector2(-r * 0.25, -r * 0.3), r * 0.3, Color(0.85, 1.0, 0.85, 0.5))
		_draw_icon(power["icon"], center, r * 0.5, Color(0.04, 0.25, 0.08))
		_draw_caption(center + Vector2(0, r + 13.0), power["name"], caption_px, Color.WHITE)


func _draw_icon(icon: StringName, center: Vector2, s: float, color: Color) -> void:
	match icon:
		&"bolt":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0.15, -1.0) * s, center + Vector2(-0.55, 0.12) * s, center + Vector2(-0.05, 0.12) * s,
				center + Vector2(-0.2, 1.0) * s, center + Vector2(0.55, -0.15) * s, center + Vector2(0.05, -0.15) * s,
			]), color)
		&"hourglass":
			var w := s * 0.62
			draw_line(center + Vector2(-w, -s), center + Vector2(w, -s), color, maxf(s * 0.16, 1.5))
			draw_line(center + Vector2(-w, s), center + Vector2(w, s), color, maxf(s * 0.16, 1.5))
			draw_colored_polygon(PackedVector2Array([center + Vector2(-w * 0.85, -s * 0.85), center + Vector2(w * 0.85, -s * 0.85),
					center]), color)
			draw_colored_polygon(PackedVector2Array([center, center + Vector2(w * 0.85, s * 0.85),
					center + Vector2(-w * 0.85, s * 0.85)]), color)
		_:
			_draw_caption(center + Vector2(0, s * 0.4), String(icon).left(1).to_upper(), s * 1.4, color)


func _draw_death() -> void:
	var left := (_death_until_msec - Time.get_ticks_msec()) / 1000.0
	var alpha := clampf(left / 0.4, 0.0, 1.0)
	var big := clampf(size.y * 0.09, 40.0, 96.0)
	var band := Rect2(0.0, size.y * 0.36, size.x, big * 2.0)
	draw_rect(band, Color(0.18, 0.0, 0.0, 0.88 * alpha))
	draw_rect(Rect2(band.position, Vector2(band.size.x, 2.0)), Color(1.0, 0.35, 0.3, 0.8 * alpha))
	draw_rect(Rect2(band.position + Vector2(0.0, band.size.y - 2.0), Vector2(band.size.x, 2.0)), Color(1.0, 0.35, 0.3, 0.8 * alpha))
	_draw_caption(Vector2(size.x / 2.0, band.position.y + big * 1.05), death_text, big, Color(1.0, 0.35, 0.3, alpha))
	_draw_caption(Vector2(size.x / 2.0, band.position.y + big * 1.65), death_detail, clampf(big * 0.28, 13.0, 22.0),
			Color(1, 1, 1, 0.9 * alpha))


## Un texto centrado en `at` (en x; `at.y` es la línea de base, corrida medio
## alto hacia abajo para que quede centrado).
func _draw_caption(at: Vector2, text: String, font_px: float, color: Color) -> void:
	var font := get_theme_default_font()
	var px := maxi(roundi(font_px), 6)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_draw_text(at + Vector2(-width / 2.0, px * 0.35), text, px, color)


func _draw_text(at: Vector2, text: String, font_px: float, color: Color) -> void:
	var font := get_theme_default_font()
	var px := maxi(roundi(font_px), 6)
	if color.v > 0.5:
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(roundi(px / 5.0), 2), Color(0, 0, 0, color.a * 0.7))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
