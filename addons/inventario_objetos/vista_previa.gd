@tool
extends VBoxContainer

## Vista previa del panel Objetos: muestra el borrador, no lo guardado, y no
## escribe nada. Tiene su propio mundo 3D (un SubViewport) y dibuja solo
## cuando algo cambia o lo girás arrastrando con el mouse. Usa las mismas
## reglas del juego: el objeto en el piso como InvWorldItem, en la mano como
## InvEquipView, la miniatura con InvThumbnails y la caja con InvContainer.look.
##
## En el piso, desde el 2026-11-07, también la hitbox de agarre, si tiene una
## forma (InvPickupHitbox.build_shape), en su lugar del espacio del objeto
## suelto, en celeste. El contorno se ve a través del modelo; el relleno es
## translúcido. Se oculta con su casilla. Desde el 2026-11-11 a la noche el
## juego no la usa para recoger (se recoge apuntando al modelo, InvReach).

## El color de la hitbox de agarre.
const HITBOX_COLOR := Color(0.35, 0.85, 1.0)
const HITBOX_NODE := &"HitboxDeAgarre"

const Destinos := preload("destinos.gd")
const Guardado := preload("guardado.gd")
const Huella := preload("huella.gd")

enum View { FLOOR, HAND }

var _hitbox_only: bool
var _viewport_box: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _content: Node3D
var _view_pick: OptionButton
var _hitbox_toggle: CheckBox
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
var _zoom := 1.0
var _target := Vector3.ZERO
var _pan := Vector3.ZERO
var _dragging := false
var _headless := false
## Las mallas del personaje (sin su script), para la vista en la mano y al
## lado de las cajas: [[malla, lugar], …].
var _actor_parts: Array = []
## Cómo hace sus miniaturas el juego (los valores de InvThumbnails).
var _per_cell := 96
var _max_pixels := 384
var _padding := 1.12


func _init(hitbox_only := false) -> void:
	_hitbox_only = hitbox_only
	add_theme_constant_override("separation", 4)
	_view_pick = OptionButton.new()
	_view_pick.add_item("En el piso", View.FLOOR)
	_view_pick.add_item("En la mano (como lo ven los demás)", View.HAND)
	_view_pick.fit_to_longest_item = false
	_view_pick.clip_text = true
	_view_pick.item_selected.connect(func(_i: int) -> void:
		_reset_camera_frame()
		_schedule())
	add_child(_view_pick)
	_hitbox_toggle = CheckBox.new()
	_hitbox_toggle.text = "Ver la hitbox de agarre"
	_hitbox_toggle.tooltip_text = "En celeste: la hitbox de agarre guardada. Hoy el juego no la usa para recoger: se recoge apuntando al modelo."
	_hitbox_toggle.button_pressed = true
	_hitbox_toggle.visible = false
	_hitbox_toggle.toggled.connect(func(_on: bool) -> void: _schedule())
	add_child(_hitbox_toggle)
	_viewport_box = SubViewportContainer.new()
	_viewport_box.stretch = true
	_viewport_box.custom_minimum_size = Vector2(120, 170 if _hitbox_only else 190)
	_viewport_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_box.tooltip_text = "Arrastrá con clic izquierdo para girar. Shift + arrastre izquierdo desplaza la cámara. La rueda acerca y aleja."
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
	_camera.near = 0.001 if _hitbox_only else 0.01
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
	_footprint.visible = not _hitbox_only
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
	if def != _def:
		_reset_camera_frame()
	_def = def
	_box = {}
	_schedule()


## Muestra un contenedor con esos valores.
func show_box(values: Dictionary) -> void:
	if not is_same(values, _box):
		_reset_camera_frame()
	_def = null
	_box = values
	_schedule()


func clear() -> void:
	_reset_camera_frame()
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
	_hitbox_toggle.visible = false
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
	if not _hitbox_only:
		for ability: Resource in def.get(&"abilities"):
			if Guardado.ability_kind(ability) == "equipable":
				equip = ability
				break
	_view_pick.visible = equip != null
	var in_hand := equip != null and _view_pick.get_selected_id() == View.HAND
	var shows_model := InvVisuals.has_visual(def)
	if def.model != null and InvVisuals.has_scripts(def.model):
		_note.text = "Este modelo tiene scripts (lógica): en el juego no se usa como apariencia, porque al armarlo correría esa lógica. Se ve una caja de su color. Usá un modelo sin scripts (un .glb, por ejemplo)."
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
		var model := InvVisuals.fitted(def, world_size, true) if shows_model else InvVisuals.placeholder(def, world_size)
		var floor_radius := maxf(world_size * 1.3, 0.3)
		_target = Vector3(0, world_size * 0.6, 0)
		_distance = maxf(world_size, 0.25) * 3.6
		var framing := InvVisuals.bounds(model) if _hitbox_only else AABB()
		var hitbox := def.get(&"pickup_hitbox") as InvPickupHitbox
		if hitbox != null and hitbox.is_configured():
			_hitbox_toggle.visible = true
			var overlay := hitbox_overlay(hitbox) if _hitbox_toggle.button_pressed else null
			if overlay != null:
				_content.add_child(overlay)
				# Que entre también la hitbox, si es más grande que el objeto.
				var area := hitbox.bounds()
				if _hitbox_only:
					framing = framing.merge(area)
				var reach := Vector2(absf(area.position.x), absf(area.position.z)).max(Vector2(absf(area.end.x), absf(area.end.z)))
				floor_radius = maxf(floor_radius, reach.length() * 1.15)
				_distance = maxf(_distance, area.size.length() * 2.4)
			elif _hitbox_toggle.button_pressed:
				_note.text = " ".join(PackedStringArray([_note.text, "La hitbox de agarre no se puede mostrar: %s" % " ".join(hitbox.problems())])).strip_edges()
		_add_floor(floor_radius)
		_content.add_child(model)
		if _hitbox_only:
			_target = framing.get_center()
			_distance = maxf(framing.size.length() * 2.4, 0.025)
			return
		# El cartel, como el de InvWorldItem.
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 32
		label.pixel_size = 0.004
		label.outline_size = 8
		label.position = Vector3.UP * (world_size + 0.25)
		label.text = String(def.get(&"display_name"))
		_content.add_child(label)
	_footprint.show_item(def.get(&"size"), def.get(&"can_rotate"), null, def.get(&"color"), String(def.get(&"display_name")))
	if shows_model and not _headless:
		_render_thumbnail(def)


func _build_box() -> void:
	_view_pick.visible = false
	var size: Vector3 = _box["box_size"]
	if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		_note.text = "Las medidas de la caja no sirven."
		return
	# Hasta el 2026-11-11 había un círculo amarillo con el alcance de la caja:
	# desde ese día el alcance es común (Interaction Range del Tuning): se abre
	# con un rayo desde los ojos y abierta se mide hasta su parte más cercana.
	_add_floor(maxf(size.x, size.z) * 0.5 + 1.2)
	for part in InvContainer.look(String(_box["display_name"]), size, _box["color"]):
		_content.add_child(part)
	# El personaje al lado de la caja, mirándola: para ver su tamaño.
	_add_actor(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(size.x / 2.0 + Guardado.ACTOR_RADIUS + 0.3, 0, 0)))
	_target = Vector3(0, maxf(size.y, 1.0) * 0.5, 0)
	_distance = maxf(maxf(size.x, size.z) * 3.0, 3.5)
	_footprint.show_grid(int(_box["columns"]), int(_box["rows"]))


## La hitbox de agarre guardada: su forma (build_shape) en su lugar
## (local_transform), en el espacio del objeto suelto. El contorno
## es el dibujo de depuración de Godot de esa forma, encima de todo; el relleno,
## translúcido. null si no tiene forma o la forma no sirve.
static func hitbox_overlay(hitbox: InvPickupHitbox) -> Node3D:
	if hitbox == null or not hitbox.is_configured() or not hitbox.problems().is_empty():
		return null
	var shape := hitbox.build_shape()
	if shape == null:
		return null
	var holder := Node3D.new()
	holder.name = HITBOX_NODE
	holder.transform = hitbox.local_transform()
	var lines := StandardMaterial3D.new()
	lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.albedo_color = HITBOX_COLOR
	lines.no_depth_test = true
	lines.render_priority = 1
	var fill := StandardMaterial3D.new()
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.albedo_color = Color(HITBOX_COLOR, 0.16)
	fill.cull_mode = BaseMaterial3D.CULL_DISABLED
	var debug := shape.get_debug_mesh()
	var outline := MeshInstance3D.new()
	outline.name = "Contorno"
	outline.mesh = debug
	var filled := false
	for i in debug.get_surface_count():
		var lined := debug.surface_get_primitive_type(i) in [Mesh.PRIMITIVE_LINES, Mesh.PRIMITIVE_LINE_STRIP]
		filled = filled or not lined
		outline.set_surface_override_material(i, lines if lined else fill)
	holder.add_child(outline)
	if not filled:
		var solid: Mesh = null
		if shape is BoxShape3D:
			solid = BoxMesh.new()
			(solid as BoxMesh).size = (shape as BoxShape3D).size
		elif shape is SphereShape3D:
			solid = SphereMesh.new()
			(solid as SphereMesh).radius = (shape as SphereShape3D).radius
			(solid as SphereMesh).height = (shape as SphereShape3D).radius * 2.0
		elif shape is CylinderShape3D:
			solid = CylinderMesh.new()
			(solid as CylinderMesh).top_radius = (shape as CylinderShape3D).radius
			(solid as CylinderMesh).bottom_radius = (shape as CylinderShape3D).radius
			(solid as CylinderMesh).height = (shape as CylinderShape3D).height
		elif shape is CapsuleShape3D:
			solid = CapsuleMesh.new()
			(solid as CapsuleMesh).radius = (shape as CapsuleShape3D).radius
			(solid as CapsuleMesh).height = (shape as CapsuleShape3D).height
		if solid != null:
			var inside := MeshInstance3D.new()
			inside.name = "Relleno"
			inside.mesh = solid
			inside.material_override = fill
			holder.add_child(inside)
	return holder


## La hitbox que se ve ahora en la vista previa, o null (para las pruebas).
func shown_hitbox() -> Node3D:
	return _content.get_node_or_null(NodePath(HITBOX_NODE)) as Node3D


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


func _reset_camera_frame() -> void:
	_pan = Vector3.ZERO
	_zoom = 1.0


func _place_camera() -> void:
	var turn := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0))
	var distance := _distance * _zoom
	_camera.far = distance * 4.0 + 10.0
	var center := _target + _pan
	_camera.look_at_from_position(center + turn * Vector3(0, 0, distance), center)
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
			var factor := 0.9 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
			_zoom = clampf(_zoom * factor, 0.2, 5.0)
			_place_camera()
			_viewport_box.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		if motion.shift_pressed:
			# Un píxel de arrastre en el plano que pasa por el centro de la órbita.
			var view_height := 2.0 * _distance * _zoom * tan(deg_to_rad(_camera.fov) * 0.5)
			var meters_per_pixel := view_height / maxf(_viewport_box.size.y, 1.0)
			_pan += (_camera.basis.y * motion.relative.y - _camera.basis.x * motion.relative.x) * meters_per_pixel
		else:
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
