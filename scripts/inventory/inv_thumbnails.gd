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
	var pixels := Vector2(def.size) * pixels_per_cell
	var longest := maxf(pixels.x, pixels.y)
	if longest > max_pixels:
		pixels *= max_pixels / longest
	var viewport := SubViewport.new()
	viewport.name = "Miniatura"
	viewport.size = Vector2i(maxi(roundi(pixels.x), 8), maxi(roundi(pixels.y), 8))
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
	# El modelo, girado como pide el tipo; si el lado largo no coincide con el
	# de la huella, se acuesta 90° (thumbnail_auto_align).
	var turn := Node3D.new()
	var model := InvVisuals.build(def)
	model.rotation_degrees = def.thumbnail_rotation
	turn.add_child(model)
	var box := model.transform * InvVisuals.bounds(model)
	if def.thumbnail_auto_align and def.size.x != def.size.y and (box.size.x > box.size.y) != (def.size.x > def.size.y):
		turn.rotation.z = PI / 2.0
		box = turn.transform * box
	viewport.add_child(turn)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var aspect := float(viewport.size.x) / viewport.size.y
	camera.size = maxf(maxf(box.size.y, box.size.x / aspect) * padding / maxf(def.thumbnail_zoom, 0.01), 0.001)
	var center := box.get_center()
	camera.near = 0.01
	camera.far = box.size.z + 10.0
	camera.position = Vector3(center.x, center.y, box.end.z + 2.0)
	viewport.add_child(camera)
	camera.current = true
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(viewport):
		_busy = false
		return
	var image := viewport.get_texture().get_image()
	if image != null and not image.is_empty() and box.size.length() > 0.0:
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
