class_name InvThumbnails
extends Node

## Miniaturas de los objetos, hechas con su modelo 3D: lo encuadra entero en
## una cámara ortográfica, con la proporción de su huella en la grilla, fondo
## transparente y dos luces. Se hacen de a una, en cola, con un SubViewport que
## se crea para esa imagen y se borra apenas termina; la imagen queda guardada
## por apariencia (InvItemDef.appearance_key): todas las celdas, la barra y el
## arrastre de un mismo tipo usan la misma.
##
## Es presentación local: cada máquina hace las suyas y no viajan por red. Sin
## modelo, o si el render falla (por ejemplo, sin pantalla), no hay imagen y la
## interfaz dibuja un rectángulo con el nombre.

signal thumbnail_ready(key: String)

## Resolución por celda de la huella; el lado más largo no pasa de max_pixels.
@export var pixels_per_cell := 96
@export var max_pixels := 384
## Margen alrededor del modelo (1 es justo).
@export var padding := 1.12

## Cuántas se hicieron y cuántas fallaron (para las pruebas).
var rendered := 0
var failed := 0
var enabled := true

var _cache := {}  # clave -> Texture2D
var _failed := {}  # clave -> true
var _queued := {}  # clave -> true
var _queue: Array[InvItemDef] = []
var _busy := false


func _ready() -> void:
	# Sin pantalla no se dibuja nada: queda el rectángulo con el nombre.
	enabled = DisplayServer.get_name() != "headless"


## La miniatura de ese tipo, o null si todavía no está (queda pedida) o no
## puede haber una.
func texture_for(def: InvItemDef) -> Texture2D:
	if def == null or not InvVisuals.has_visual(def):
		return null
	var key := def.appearance_key()
	if _cache.has(key):
		return _cache[key]
	if not enabled or _failed.has(key):
		return null
	if not _queued.has(key):
		_queued[key] = true
		_queue.append(def)
	return null


func has_texture(def: InvItemDef) -> bool:
	return def != null and _cache.has(def.appearance_key())


func _process(_delta: float) -> void:
	if not _busy and not _queue.is_empty():
		_render(_queue.pop_front())


func _render(def: InvItemDef) -> void:
	_busy = true
	var key := def.appearance_key()
	var viewport := InvThumbnails.build_viewport(def, InvThumbnails.image_size(def, pixels_per_cell, max_pixels), padding)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(viewport):
		_busy = false
		return
	var image := viewport.get_texture().get_image()
	if image != null and not image.is_empty() and not viewport.get_meta(&"empty"):
		_cache[key] = ImageTexture.create_from_image(image)
		rendered += 1
	else:
		_failed[key] = true
		failed += 1
	viewport.queue_free()
	_queued.erase(key)
	_busy = false
	thumbnail_ready.emit(key)


## Para las pruebas: la imagen hecha para ese tipo, o null.
func image_for(def: InvItemDef) -> Image:
	var texture: Texture2D = _cache.get(def.appearance_key()) if def != null else null
	return texture.get_image() if texture != null else null


## Medidas de la imagen de ese tipo: la proporción de su huella, de a
## `per_cell` píxeles por celda, sin que el lado más largo pase de `max_side`.
static func image_size(def: InvItemDef, per_cell: int, max_side: int) -> Vector2i:
	var pixels := Vector2(def.size) * per_cell
	var longest := maxf(pixels.x, pixels.y)
	if longest > max_side:
		pixels *= max_side / longest
	return Vector2i(maxi(roundi(pixels.x), 8), maxi(roundi(pixels.y), 8))


## Un SubViewport con lo que ve la miniatura de ese tipo: su propio mundo,
## fondo transparente, dos luces, el modelo y la cámara que lo encuadra. Se
## dibuja una vez al entrar al árbol. Con la meta "empty", si no había mallas
## que encuadrar. Lo usa también la vista previa del panel Objetos del editor.
static func build_viewport(def: InvItemDef, size: Vector2i, margin: float) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "Miniatura"
	viewport.size = size
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.55
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	key_light.light_energy = 1.2
	viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	fill_light.light_energy = 0.45
	viewport.add_child(fill_light)
	var turn := Node3D.new()
	turn.name = "Giro"
	turn.add_child(InvVisuals.build(def))
	viewport.add_child(turn)
	var camera := Camera3D.new()
	camera.name = "Camara"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.01
	viewport.add_child(camera)
	camera.current = true
	frame(viewport, def, margin)
	return viewport


## Encuadra el modelo de una miniatura ya armada con build_viewport, según el
## tipo: su giro, acostado si hace falta, su zoom y su corrimiento. El panel
## Objetos lo vuelve a llamar mientras la acomodás con el mouse, sin rearmar el
## modelo. Deja la meta "empty" si no había mallas que encuadrar.
static func frame(viewport: SubViewport, def: InvItemDef, margin: float) -> void:
	# El modelo, girado como pide el tipo; si el lado largo no coincide con el
	# de la huella, se acuesta 90° (thumbnail_auto_align).
	var turn := viewport.get_node("Giro") as Node3D
	var model := turn.get_child(0) as Node3D
	model.rotation_degrees = def.thumbnail_rotation
	turn.rotation = Vector3.ZERO
	var box := model.transform * InvVisuals.bounds(model)
	if def.thumbnail_auto_align and def.size.x != def.size.y and (box.size.x > box.size.y) != (def.size.x > def.size.y):
		turn.rotation.z = PI / 2.0
		box = turn.transform * box
	var camera := viewport.get_node("Camara") as Camera3D
	var aspect := float(viewport.size.x) / viewport.size.y
	camera.size = maxf(maxf(box.size.y, box.size.x / aspect) * margin / maxf(def.thumbnail_zoom, 0.01), 0.001)
	var center := box.get_center()
	camera.far = box.size.z + 10.0
	# Correr el modelo a la derecha es correr la cámara a la izquierda; para
	# abajo, la cámara sube. En partes del cuadro: alto camera.size, ancho por aspecto.
	var shift := Vector2(-def.thumbnail_offset.x * camera.size * aspect, def.thumbnail_offset.y * camera.size)
	camera.position = Vector3(center.x + shift.x, center.y + shift.y, box.end.z + 2.0)
	viewport.set_meta(&"empty", box.size.length() <= 0.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Dibuja la miniatura en ese rectángulo, girada de a 90° en el sentido del
## reloj según `rot`, como en la grilla. Lo usan la interfaz y la vista previa
## del panel Objetos del editor.
static func draw_turned(canvas: CanvasItem, texture: Texture2D, rect: Rect2, rot: int, tint: Color) -> void:
	var turns := posmod(rot, 4)
	if turns == 0:
		canvas.draw_texture_rect(texture, rect, false, tint)
		return
	# La esquina de arriba a la izquierda de la imagen va a la esquina que le
	# toca con ese giro; girada 90° o 270°, se cambian ancho y alto.
	var corners := [Vector2.ZERO, Vector2(rect.size.x, 0.0), rect.size, Vector2(0.0, rect.size.y)]
	var drawn := rect.size if turns == 2 else Vector2(rect.size.y, rect.size.x)
	canvas.draw_set_transform(rect.position + corners[turns], turns * PI / 2.0, Vector2.ONE)
	canvas.draw_texture_rect(texture, Rect2(Vector2.ZERO, drawn), false, tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
