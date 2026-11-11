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
##   también entre dos números. La luz naranja de abajo avisa de lesiones:
##   desde el 2026-11-09, como en el concepto del usuario, parpadea mientras
##   alguna de las seis partes del cuerpo muestre 60 % o menos en el panel, y
##   se apaga del todo con todas arriba de eso (hasta ese día se prendía fija
##   con cualquier parte por debajo del 100 %). La salud y la integridad se
##   leen por separado: la aguja no cuenta el cuerpo.
## - Integridad corporal (desde el 2026-11-05): con el inventario abierto (Tab)
##   y sin una caja abierta, una silueta a la derecha de la grilla propia, en
##   el lugar de la caja, con el porcentaje de cada parte, verde completa y
##   cada vez más roja al bajar. Con una caja abierta, la caja tiene ese lugar,
##   y también mientras el host contesta una caja pedida con E (desde el
##   2026-11-08: antes el panel se veía hasta que llegaba la caja).
##   El panel y la luz muestran el estado del personaje propio, como la aguja
##   de la salud: en un cliente, lo predicho, sin esperar al host (desde el
##   2026-11-06 a la noche, pedido del usuario; antes, lo que confirmaba el
##   host, como decía el roadmap). Desde el 2026-11-06, con algo en la mano, la
##   parte bajo el cursor se marca (blanco si ese objeto la cura, rojo si no), y
##   la interfaz del inventario pregunta acá qué parte hay bajo un clic
##   (integrity_part_at) para curarla con un botiquín.
## - Estamina: de 0 a 200, la proporción de la reserva.
## - Termómetro: marca 100 fijo. No mide la luz: es el lugar del futuro sensor.
## - Luces: una por estado propio prendido (ActorPowers.LIST), las que sean.
##   Sin ninguno, no aparece nada. La cámara lenta que pidió otro jugador no
##   prende la luz propia. Desde el 2026-11-09 (pedido del usuario, como su
##   concepto) van arriba a la izquierda, en fila, y no se mueven al abrir el
##   inventario ni el selector. Se dibujan con los instrumentos, debajo del
##   inventario: abierto, la grilla propia (que empieza en esa esquina) las
##   tapa (2026-11-10, pedido del usuario al verlas encima del título).
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

@export_group("Luz naranja")
## Parpadea mientras alguna parte del cuerpo muestre este porcentaje o menos en
## el panel (el número entero, como se lee: 60,5 % dice 60 % y cuenta). Con
## todas arriba, se apaga del todo.
@export_range(0, 100, 1) var injury_light_percent := 60
## Cuánto dura prendida y cuánto apagada en cada parpadeo, en segundos reales.
@export_range(0.1, 2.0, 0.05) var injury_blink_seconds := 0.5

@export_group("Aviso de muerte")
## Cuánto dura el aviso, en segundos reales.
@export_range(0.5, 10.0, 0.1) var death_notice_seconds := 2.5
@export var death_text := "Moriste"
@export var death_detail := "Muerte de prueba: la salud y el cuerpo volvieron al máximo y se apagaron tus estados"

@export_group("Agotamiento")
## El sonido cuando la estamina llega a cero y se apagan los estados (de
## fábrica, `estados_apagados.wav`, dos notas cortas que bajan). Vacío, no suena.
@export var exhaustion_sound: AudioStream
@export_range(-40.0, 6.0, 0.5) var exhaustion_volume_db := -6.0

## Para las pruebas: cuántos avisos de muerte y sonidos de agotamiento salieron.
var deaths_shown := 0
var exhaustion_sounds := 0
## Para las pruebas: cuántas veces se dibujó el panel de integridad.
var integrity_draws := 0
var _actor: ActorBody
var _health_shown := 10.0
var _stamina_shown := 200.0
var _deaths_seen := 0
var _exhaustions_seen := 0
var _death_until_msec := 0
var _sound: AudioStreamPlayer
## Desde cuándo avisa la luz naranja (Time.get_ticks_msec), o -1: el parpadeo
## arranca prendido.
var _warning_since_msec := -1


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


## La integridad que muestran el panel y la luz: la del personaje propio, como
## la aguja de la salud (en un cliente, la predicha; desde el 2026-11-06 a la
## noche, pedido del usuario: antes era la que confirmó el host, un viaje de
## ida y vuelta después). Las seis partes, en centésimas de punto
## (ActorState.Part), o vacío sin personaje.
func integrity() -> PackedInt32Array:
	if not _active():
		return PackedInt32Array()
	return _actor.state.integrity


## Si la luz naranja avisa (parpadea): alguna parte muestra en el panel
## injury_light_percent o menos (desde el 2026-11-09; antes, cualquier parte
## por debajo del 100 %).
func injury_warning() -> bool:
	for value in integrity():
		@warning_ignore("integer_division")
		if value / ActorState.INTEGRITY_UNIT <= injury_light_percent:
			return true
	return false


## Si la luz naranja está encendida en este momento: avisando y en la mitad
## prendida del parpadeo, que arranca prendida al empezar el aviso.
func injury_lamp_lit() -> bool:
	if not injury_warning():
		return false
	var since := _warning_since_msec if _warning_since_msec >= 0 else Time.get_ticks_msec()
	var half := maxi(roundi(injury_blink_seconds * 1000.0), 1)
	@warning_ignore("integer_division")
	return ((Time.get_ticks_msec() - since) / half) % 2 == 0


## Dónde se dibuja el panel de integridad ahora, o un rectángulo vacío si no se
## ve (inventario cerrado o con una caja abierta).
func integrity_panel_rect() -> Rect2:
	if not _active() or inventory_ui == null:
		return Rect2()
	return inventory_ui.side_panel_rect()


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
	if not injury_warning():
		_warning_since_msec = -1
	elif _warning_since_msec < 0:
		_warning_since_msec = Time.get_ticks_msec()
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
const LAMP_ON := Color(1.0, 0.55, 0.08)
## Barrido de las escalas: de abajo a la izquierda, por arriba, hasta abajo a
## la derecha, simétrico (como el velocímetro del concepto), en grados desde
## arriba.
const SWEEP := 135.0


func _draw() -> void:
	if not _active():
		return
	var layout := _layout()
	_draw_instruments(layout)
	_draw_lights()
	var panel := integrity_panel_rect()
	if panel.has_area():
		integrity_draws += 1
		_draw_integrity(panel)
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
	return {"d": d, "plate": plate, "pad": pad}


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
	# La luz naranja va integrada abajo, donde el concepto tenía el RPM:
	# parpadea con alguna parte del cuerpo muy lastimada.
	var lamp := center + Vector2(0, face * 0.58)
	var lamp_r := face * 0.17
	var lit := injury_lamp_lit()
	if lit:
		for k in 3:
			draw_circle(lamp, lamp_r * (1.9 - k * 0.2), Color(LAMP_ON, 0.08 + k * 0.04))
	draw_circle(lamp, lamp_r * 1.25, Color(0.55, 0.56, 0.58))
	draw_circle(lamp, lamp_r * 1.08, Color(0.18, 0.18, 0.19))
	draw_circle(lamp, lamp_r, LAMP_ON if lit else Color(0.42, 0.22, 0.04))
	draw_circle(lamp + Vector2(-lamp_r * 0.32, -lamp_r * 0.35), lamp_r * 0.32,
			Color(1.0, 0.9, 0.7, 0.6) if lit else Color(0.75, 0.5, 0.25, 0.45))
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


## Dónde empieza la fila de luces: su esquina de arriba a la izquierda.
const LIGHTS_CORNER := Vector2(16.0, 14.0)


## Dónde va cada luz de los estados prendidos: arriba a la izquierda, en fila,
## en el orden de ActorPowers.LIST, siempre en el mismo lugar (con o sin el
## inventario o el selector abiertos). {"items": [[estado, centro, ancho]],
## "lamp": diámetro, "caption_px": alto del nombre, "rect": lo que ocupan}.
func _lights_layout() -> Dictionary:
	var lit := lit_powers()
	var lamp := clampf(size.y * 0.055, 32.0, 56.0)
	var caption_px := roundi(clampf(lamp * 0.3, 11.0, 15.0))
	var font := get_theme_default_font()
	var items := []
	var rect := Rect2()
	var x := LIGHTS_CORNER.x
	for power: Dictionary in lit:
		# Cada luz ocupa lo que mide ella o su nombre, lo que sea más ancho.
		var slot := maxf(lamp, font.get_string_size(power["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, caption_px).x + 8.0)
		items.append([power, Vector2(x + slot / 2.0, LIGHTS_CORNER.y + lamp / 2.0), slot])
		var used := Rect2(Vector2(x, LIGHTS_CORNER.y), Vector2(slot, lamp + 13.0 + caption_px))
		rect = used if items.size() == 1 else rect.merge(used)
		x += slot + lamp * 0.35
	return {"items": items, "lamp": lamp, "caption_px": caption_px, "rect": rect}


## Lo que ocupan en la pantalla las luces prendidas (con sus nombres), o un
## rectángulo vacío sin ninguna. El laboratorio baja su panel de texto para no
## taparlas; las pruebas miran que no se muevan.
func lights_rect() -> Rect2:
	return _lights_layout()["rect"] if _active() else Rect2()


## Las luces de arriba: una por estado propio prendido. Van con los
## instrumentos, antes que el inventario en el Hud: abierto, lo tapa la grilla.
func _draw_lights() -> void:
	var layout := _lights_layout()
	var r: float = layout["lamp"] / 2.0
	for item: Array in layout["items"]:
		var power: Dictionary = item[0]
		var center: Vector2 = item[1]
		for k in 4:
			draw_circle(center, r * (1.55 - k * 0.12), Color(LENS_ON, 0.06 + k * 0.03))
		draw_circle(center, r, Color(0.55, 0.57, 0.6))
		draw_circle(center, r * 0.86, Color(0.12, 0.13, 0.14))
		draw_circle(center, r * 0.78, LENS_ON)
		draw_circle(center + Vector2(-r * 0.25, -r * 0.3), r * 0.3, Color(0.85, 1.0, 0.85, 0.5))
		draw_icon(self, power["icon"], center, r * 0.5, Color(0.04, 0.25, 0.08))
		_draw_caption(center + Vector2(0, r + 13.0), power["name"], layout["caption_px"], Color.WHITE)


## El ícono de un estado (ActorPowers.LIST), de `s` de medio alto, dibujado en
## `canvas` mientras se dibuja. Lo usan las luces y el selector de habilidades.
static func draw_icon(canvas: CanvasItem, icon: StringName, center: Vector2, s: float, color: Color) -> void:
	match icon:
		&"bolt":
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(0.15, -1.0) * s, center + Vector2(-0.55, 0.12) * s, center + Vector2(-0.05, 0.12) * s,
				center + Vector2(-0.2, 1.0) * s, center + Vector2(0.55, -0.15) * s, center + Vector2(0.05, -0.15) * s,
			]), color)
		&"hourglass":
			var w := s * 0.62
			canvas.draw_line(center + Vector2(-w, -s), center + Vector2(w, -s), color, maxf(s * 0.16, 1.5))
			canvas.draw_line(center + Vector2(-w, s), center + Vector2(w, s), color, maxf(s * 0.16, 1.5))
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(-w * 0.85, -s * 0.85), center + Vector2(w * 0.85, -s * 0.85),
					center]), color)
			canvas.draw_colored_polygon(PackedVector2Array([center, center + Vector2(w * 0.85, s * 0.85),
					center + Vector2(-w * 0.85, s * 0.85)]), color)
		_:
			var font := ThemeDB.fallback_font
			var px := maxi(roundi(s * 1.4), 6)
			var letter := String(icon).left(1).to_upper()
			var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			canvas.draw_string(font, center + Vector2(-width / 2.0, s * 0.4 + px * 0.35), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


# --- Integridad corporal ------------------------------------------------------------

## La silueta, en una figura de 64 × 100, vista de atrás (tu izquierda queda a
## la izquierda, como ves a tu personaje en tercera persona): un rectángulo por
## parte, en el orden de ActorState.Part. La cabeza es el círculo inscripto.
const FIGURE := Vector2(64, 100)
const FIGURE_PARTS := [
	Rect2(24, 2, 16, 16),
	Rect2(20, 20, 24, 33),
	Rect2(7, 21, 11.5, 34),
	Rect2(45.5, 21, 11.5, 34),
	Rect2(20, 55, 11.5, 43),
	Rect2(32.5, 55, 11.5, 43),
]
const PART_NAMES := ["Cabeza", "Torso", "Brazo izquierdo", "Brazo derecho", "Pierna izquierda", "Pierna derecha"]
const PANEL_FILL := Color(0.07, 0.08, 0.1, 0.84)

var _part_boxes: Array[StyleBoxFlat] = []


## Lo que dice cada parte en el panel, en el orden de ActorState.Part: el
## porcentaje entero, para abajo (con algo menos del 100 % ya no dice 100).
func integrity_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for value in integrity():
		@warning_ignore("integer_division")
		texts.append("%d %%" % (value / ActorState.INTEGRITY_UNIT))
	return texts


## Verde con la parte completa, y cada vez más amarilla, naranja y roja al bajar.
static func integrity_color(fraction: float) -> Color:
	return Color.from_hsv(0.33 * clampf(fraction, 0.0, 1.0), 0.78, 0.8)


## Dónde se dibuja la silueta dentro del panel: [esquina de la figura, píxeles
## por unidad de la figura].
static func _figure_layout(panel: Rect2) -> Array:
	var area := Rect2(panel.position + Vector2(12, 74), panel.size - Vector2(24, 86))
	var unit := minf(area.size.x / FIGURE.x, area.size.y / FIGURE.y)
	return [area.position + (area.size - FIGURE * unit) / 2.0, unit]


## Dónde se ve una parte en la pantalla, con el panel en `panel`.
static func _part_rect(panel: Rect2, part: int) -> Rect2:
	var layout := _figure_layout(panel)
	var figure: Rect2 = FIGURE_PARTS[part]
	return Rect2(layout[0] + figure.position * layout[1], figure.size * layout[1])


## La parte del cuerpo que se ve bajo ese punto de la pantalla (ActorState.Part),
## o -1: con el panel cerrado, fuera de la silueta o entre dos partes. La usa la
## interfaz del inventario para soltar un botiquín sobre una parte (desde el
## 2026-11-06).
func integrity_part_at(point: Vector2) -> int:
	var panel := integrity_panel_rect()
	if not panel.has_point(point):
		return -1
	for part in ActorState.PARTS:
		var shown := _part_rect(panel, part)
		if part == ActorState.Part.HEAD:
			if point.distance_to(shown.get_center()) <= shown.size.x / 2.0:
				return part
		elif shown.has_point(point):
			return part
	return -1


## El nombre de una parte, para los avisos ("Pierna izquierda").
static func part_name(part: int) -> String:
	return PART_NAMES[part] if part >= 0 and part < PART_NAMES.size() else "?"


## Con algo en la mano sobre el panel: la parte bajo el cursor y si ese objeto
## la puede curar, [parte, sirve], o [-1, false].
func hovered_part() -> Array:
	if inventory_ui == null:
		return [-1, false]
	var def: InvItemDef = inventory_ui.held_def()
	if def == null:
		return [-1, false]
	var part := integrity_part_at(inventory_ui.pointer())
	if part < 0:
		return [-1, false]
	var use := def.ability_of(InvAbility.Kind.USE) as InvConsumable
	return [part, use != null and use.repairs_parts() and integrity()[part] < ActorState.INTEGRITY_FULL]


func _draw_integrity(panel: Rect2) -> void:
	draw_rect(panel, PANEL_FILL)
	_draw_text(panel.position + Vector2(10, 28), "Integridad corporal", 17, Color.WHITE)
	var hover := hovered_part()
	var hint := "Vista de atrás: tu izquierda, a la izquierda"
	if hover[0] >= 0:
		hint = "Clic: curar %s" % part_name(hover[0]).to_lower() if hover[1] else "Esto no cura esa parte"
	_draw_text(panel.position + Vector2(10, 48), hint, 12, Color(1, 1, 1, 0.6))
	var values := integrity()
	var texts := integrity_texts()
	var layout := _figure_layout(panel)
	var origin: Vector2 = layout[0]
	var unit: float = layout[1]
	var font_px := clampf(unit * 2.4, 11.0, 18.0)
	# Arriba de cada brazo, de qué lado es.
	_draw_caption(origin + Vector2(12.75, 19) * unit, "izq.", font_px * 0.8, Color(1, 1, 1, 0.65))
	_draw_caption(origin + Vector2(51.25, 19) * unit, "der.", font_px * 0.8, Color(1, 1, 1, 0.65))
	if _part_boxes.is_empty():
		for i in ActorState.PARTS:
			var box := StyleBoxFlat.new()
			box.set_border_width_all(2)
			_part_boxes.append(box)
	for part in ActorState.PARTS:
		var shown := _part_rect(panel, part)
		var fill := integrity_color(values[part] / float(ActorState.INTEGRITY_FULL))
		# Bajo el cursor con algo en la mano: borde blanco si lo cura, rojo si no.
		var edge := Color(0.02, 0.02, 0.03, 0.9)
		if hover[0] == part:
			edge = Color(1, 1, 1) if hover[1] else Color(1.0, 0.35, 0.3)
		if part == ActorState.Part.HEAD:
			draw_circle(shown.get_center(), shown.size.x / 2.0 + (4.0 if hover[0] == part else 2.0), edge)
			draw_circle(shown.get_center(), shown.size.x / 2.0, fill)
		else:
			var box := _part_boxes[part]
			box.bg_color = fill
			box.border_color = edge
			box.set_border_width_all(4 if hover[0] == part else 2)
			box.set_corner_radius_all(roundi(minf(shown.size.x, shown.size.y) * 0.3))
			draw_style_box(box, shown)
		_draw_caption(shown.get_center(), texts[part], font_px, Color.WHITE)


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
