@tool
extends VBoxContainer

## Vista previa del panel Objetos: muestra el borrador, no lo guardado, y no
## escribe nada. Tiene su propio mundo 3D (un SubViewport) y dibuja solo
## cuando algo cambia o lo girás arrastrando con el mouse. Usa las mismas
## reglas del juego: el objeto en el piso como InvWorldItem, en la mano como
## InvEquipView, la miniatura con InvThumbnails y la caja con InvContainer.look.

const Destinos := preload("destinos.gd")
const Guardado := preload("guardado.gd")
const Huella := preload("huella.gd")

enum View { FLOOR, HAND }

var _viewport_box: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _content: Node3D
var _view_pick: OptionButton
var _note: Label
var _footprint: Huella
var _thumbnail: SubViewport
var _generation := 0
var _def: Resource
var _box := {}
var _pending := false
var _yaw := 30.0
var _pitch := -22.0
var _distance := 1.5
var _target := Vector3.ZERO
var _dragging := false
var _headless := false
## Las mallas del personaje (sin su script), para la vista en la mano y el
## alcance de las cajas: [[malla, lugar], …].
var _actor_parts: Array = []
## Cómo hace sus miniaturas el juego (los valores de InvThumbnails).
var _per_cell := 96
var _max_pixels := 384
var _padding := 1.12


func _init() -> void:
	add_theme_constant_override("separation", 4)
	_view_pick = OptionButton.new()
	_view_pick.add_item("En el piso", View.FLOOR)
	_view_pick.add_item("En la mano (como lo ven los demás)", View.HAND)
	_view_pick.fit_to_longest_item = false
	_view_pick.clip_text = true
	_view_pick.item_selected.connect(func(_i: int) -> void: _schedule())
	add_child(_view_pick)
	_viewport_box = SubViewportContainer.new()
	_viewport_box.stretch = true
	_viewport_box.custom_minimum_size = Vector2(120, 190)
	_viewport_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_box.tooltip_text = "Arrastrá para girar; la rueda acerca y aleja."
	_viewport_box.gui_input.connect(_on_view_input)
	_viewport_box.resized.connect(_render_once)
	add_child(_viewport_box)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport_box.add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.15, 0.16, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.55
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)
	# Las mismas dos luces de la miniatura.
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	key_light.light_energy = 1.2
	_viewport.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-15.0, 150.0, 0.0)
	fill_light.light_energy = 0.45
	_viewport.add_child(fill_light)
	_camera = Camera3D.new()
	_camera.near = 0.01
	_camera.fov = 35.0
	_viewport.add_child(_camera)
	_camera.current = true
	_content = Node3D.new()
	_viewport.add_child(_content)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 200
	_note.modulate = Color(1, 0.85, 0.5)
	add_child(_note)
	_footprint = Huella.new()
	_footprint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_footprint)


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	var script: Script = InvThumbnails
	_per_cell = int(script.get_property_default_value(&"pixels_per_cell"))
	_max_pixels = int(script.get_property_default_value(&"max_pixels"))
	_padding = float(script.get_property_default_value(&"padding"))


func _exit_tree() -> void:
	# Lo que esté esperando un cuadro deja de valer.
	_generation += 1


## Muestra ese ítem (el borrador: se vuelve a leer en cada cambio).
func show_item(def: Resource) -> void:
	_def = def
	_box = {}
	_schedule()


## Muestra un contenedor con esos valores.
func show_box(values: Dictionary) -> void:
	_def = null
	_box = values.duplicate()
	_schedule()


func clear() -> void:
	_def = null
	_box = {}
	_schedule()


## Si la miniatura de la vista previa está hecha (para las pruebas).
func has_thumbnail() -> bool:
	return _footprint.texture != null


func _schedule() -> void:
	if not _pending:
		_pending = true
		_refresh.call_deferred()


func _refresh() -> void:
	_pending = false
	_generation += 1
	for child in _content.get_children():
		_content.remove_child(child)
		child.free()
	if is_instance_valid(_thumbnail):
		_thumbnail.queue_free()
	_thumbnail = null
	_footprint.texture = null
	_note.text = ""
	if _def != null:
		_build_item()
	elif not _box.is_empty():
		_build_box()
	else:
		_view_pick.visible = false
		_footprint.show_grid(0, 0)
	if _headless:
		_note.text = "Sin pantalla no se dibuja la vista previa."
	_note.visible = _note.text != ""
	_place_camera()


func _build_item() -> void:
	var def := _def
	var equip: Resource = null
	for ability: Resource in def.get(&"abilities"):
		if Guardado.ability_kind(ability) == "equipable":
			equip = ability
			break
	_view_pick.visible = equip != null
	var in_hand := equip != null and _view_pick.get_selected_id() == View.HAND
	var shows_model := InvVisuals.has_visual(def)
	if shows_model:
		var probe := InvVisuals.build(def)
		if probe.get_child_count() == 0 or InvVisuals.bounds(probe).size.length() <= 0.0:
			shows_model = false
			_note.text = "Este modelo no tiene mallas que se vean: en el juego no se vería en el piso (solo el cartel) y su miniatura sería un rectángulo con el nombre. Acá se muestra una caja de su color."
		probe.free()
	var world_size := float(def.get(&"world_size"))
	if in_hand:
		_add_actor(Transform3D.IDENTITY)
		var hold := float(equip.get(&"hold_size"))
		var model := InvVisuals.fitted(def, hold, false) if shows_model else InvVisuals.placeholder(def, hold)
		model.rotation_degrees = equip.get(&"hold_rotation")
		model.position = equip.get(&"hold_offset")
		_content.add_child(model)
		_target = Vector3(0, 1.0, 0)
		_distance = 4.4
	else:
		_add_floor(maxf(world_size * 1.3, 0.3))
		_content.add_child(InvVisuals.fitted(def, world_size, true) if shows_model else InvVisuals.placeholder(def, world_size))
		# El cartel, como el de InvWorldItem.
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 32
		label.pixel_size = 0.004
		label.outline_size = 8
		label.position = Vector3.UP * (world_size + 0.25)
		label.text = String(def.get(&"display_name"))
		_content.add_child(label)
		_target = Vector3(0, world_size * 0.6, 0)
		_distance = maxf(world_size, 0.25) * 3.6
	_footprint.show_item(def.get(&"size"), def.get(&"can_rotate"), null, def.get(&"color"), String(def.get(&"display_name")))
	if shows_model and not _headless:
		_render_thumbnail(def)


func _build_box() -> void:
	_view_pick.visible = false
	var size: Vector3 = _box["box_size"]
	var reach := float(_box["access_range"])
	if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		_note.text = "Las medidas de la caja no sirven."
		return
	_add_floor(reach + 0.4)
	for part in InvContainer.look(String(_box["display_name"]), size, _box["color"]):
		_content.add_child(part)
	# El alcance: con los pies adentro del círculo, se abre.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(reach - 0.03, 0.01)
	torus.outer_radius = reach + 0.03
	torus.rings = 48
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.8, 0.2)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = material
	ring.mesh = torus
	ring.scale = Vector3(1, 0.05, 1)
	_content.add_child(ring)
	# El personaje en el borde del alcance, mirando la caja.
	var stand := maxf(reach - 0.15, size.x / 2.0 + Guardado.ACTOR_RADIUS)
	_add_actor(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(stand, 0, 0)))
	# Qué es el círculo amarillo lo explica la burbujita de la sección (objetos_panel.gd).
	_target = Vector3(0, maxf(size.y, 1.0) * 0.5, 0)
	_distance = maxf(maxf(reach * 3.4, maxf(size.x, size.z) * 3.0), 3.5)
	_footprint.show_grid(int(_box["columns"]), int(_box["rows"]))


func _add_floor(radius: float) -> void:
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.01
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.46, 0.52)
	disc.material = material
	floor_mesh.mesh = disc
	floor_mesh.position = Vector3.DOWN * 0.005
	_content.add_child(floor_mesh)


## El cuerpo del personaje (sus mallas visibles, sin su script ni su física).
func _add_actor(place: Transform3D) -> void:
	if _actor_parts.is_empty():
		var scene := load(Destinos.ACTOR_PATH) as PackedScene
		var actor := scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if scene != null else null
		var visual := actor.get_node_or_null("Visual") if actor != null else null
		if visual != null:
			for child in visual.get_children():
				if child is MeshInstance3D and (child as MeshInstance3D).visible:
					_actor_parts.append([(child as MeshInstance3D).mesh, (child as MeshInstance3D).transform])
		if actor != null:
			actor.free()
	var body := Node3D.new()
	body.transform = place
	for part: Array in _actor_parts:
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = part[0]
		mesh_node.transform = part[1]
		body.add_child(mesh_node)
	_content.add_child(body)


func _place_camera() -> void:
	var turn := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0))
	_camera.far = _distance * 4.0 + 10.0
	_camera.position = _target + turn * Vector3(0, 0, _distance)
	_camera.look_at_from_position(_camera.position, _target)
	_render_once()


func _render_once() -> void:
	if _viewport != null and not _headless:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_viewport_box.queue_redraw()


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_distance *= 0.9 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
			_place_camera()
			_viewport_box.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.5
		_pitch = clampf(_pitch - motion.relative.y * 0.5, -85.0, 10.0)
		_place_camera()


## La miniatura como la hace el juego, en un SubViewport que vive dos cuadros.
## Si mientras tanto cambió el borrador, esta imagen se descarta.
func _render_thumbnail(def: Resource) -> void:
	var generation := _generation
	var viewport := InvThumbnails.build_viewport(def, InvThumbnails.image_size(def, _per_cell, _max_pixels), _padding)
	_thumbnail = viewport
	add_child(viewport)
	for i in 2:
		# El editor dibuja solo cuando algo cambia: se le pide un cuadro.
		_footprint.queue_redraw()
		await RenderingServer.frame_post_draw
		if not is_instance_valid(viewport) or generation != _generation:
			return
	var image := viewport.get_texture().get_image()
	if image != null and not image.is_empty() and not viewport.get_meta(&"empty"):
		_footprint.texture = ImageTexture.create_from_image(image)
		_footprint.queue_redraw()
	viewport.queue_free()
	_thumbnail = null
