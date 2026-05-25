# debug_draw.gd
# AUTOLOAD. Sistema de visualización 3D para debugging.
# Cualquier script puede pedirle que dibuje rayos, puntos y esferas.
# Los dibujos se acumulan durante el frame y se limpian al final de cada frame físico.
#
# Para registrarlo: Project Settings → Autoload → agregar este script como "DebugDraw".
#
# Uso desde cualquier script:
#   DebugDraw.ray(origen, destino, Color.RED)
#   DebugDraw.point(posicion, Color.GREEN)
#   DebugDraw.sphere(posicion, radio, Color.YELLOW)

extends Node

# ── Toggle global ─────────────────────────────────────────────────
var enabled : bool = true

# ── Freeze ────────────────────────────────────────────────────────
# Cuando está congelado, deja de aceptar dibujos nuevos y mantiene
# en pantalla el último frame dibujado. Útil para inspeccionar.
var frozen : bool = false

# ── Listas de primitivas a dibujar este frame ─────────────────────
var _rays    : Array = []   # cada uno: { from, to, color }
var _points  : Array = []   # cada uno: { pos, color, size }
var _spheres : Array = []   # cada uno: { pos, radius, color }

# ── Nodo de rendering ─────────────────────────────────────────────
var _mesh_instance : MeshInstance3D
var _immediate     : ImmediateMesh
var _material      : StandardMaterial3D

# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Crear el MeshInstance que va a dibujar todo
	_immediate = ImmediateMesh.new()

	_material = StandardMaterial3D.new()
	_material.shading_mode          = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test         = true   # se ve a través de paredes
	_material.transparency          = BaseMaterial3D.TRANSPARENCY_ALPHA

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh             = _immediate
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow      = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Se agrega a la escena cuando el árbol esté listo
	call_deferred("_attach_to_scene")

func _attach_to_scene() -> void:
	var root = get_tree().current_scene
	if root:
		root.add_child(_mesh_instance)

# ─────────────────────────────────────────────────────────────────
# ── API PÚBLICA ──────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func ray(from: Vector3, to: Vector3, color: Color = Color.WHITE) -> void:
	if not enabled or frozen:
		return
	_rays.append({ "from": from, "to": to, "color": color })

func point(pos: Vector3, color: Color = Color.WHITE, size: float = 0.06) -> void:
	if not enabled or frozen:
		return
	_points.append({ "pos": pos, "color": color, "size": size })

func sphere(pos: Vector3, radius: float = 0.2, color: Color = Color.WHITE) -> void:
	if not enabled or frozen:
		return
	_spheres.append({ "pos": pos, "radius": radius, "color": color })

func toggle() -> void:
	enabled = not enabled

func toggle_freeze() -> void:
	frozen = not frozen

# ─────────────────────────────────────────────────────────────────
# ── RENDERING ────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	# Volver a re-attach si cambió la escena (ej: reload tras morir)
	if _mesh_instance and not _mesh_instance.is_inside_tree():
		_attach_to_scene()

	# Permitir togglear el freeze con una tecla.
	if Input.is_action_just_pressed("toggle_debug_freeze"):
		toggle_freeze()

	# Solo dibuja. El clear lo hace _physics_process.
	# Por qué: los rayos del shimmy se agregan en _physics_process.
	# Si limpiamos acá, pueden borrarse antes de que este frame los dibuje.
	# Separar los dos loops garantiza que lo que se agregó en physics
	# siempre llega al frame visual siguiente.
	_redraw()

func _physics_process(_delta: float) -> void:
	# Si está congelado, NO limpiar — mantener el último frame en pantalla.
	if frozen:
		return

	_rays.clear()
	_points.clear()
	_spheres.clear()

func _redraw() -> void:
	if not _immediate:
		return

	_immediate.clear_surfaces()

	if _rays.is_empty() and _points.is_empty() and _spheres.is_empty():
		return

	_immediate.surface_begin(Mesh.PRIMITIVE_LINES)

	# ── Rayos ─────────────────────────────────────────────────────
	for r in _rays:
		_immediate.surface_set_color(r["color"])
		_immediate.surface_add_vertex(r["from"])
		_immediate.surface_set_color(r["color"])
		_immediate.surface_add_vertex(r["to"])

	# ── Puntos (cruces de 3 ejes) ─────────────────────────────────
	for p in _points:
		var s = p["size"]
		var c = p["color"]
		var pos = p["pos"]
		_add_cross(pos, s, c)

	# ── Esferas (wireframe simple: 3 círculos) ────────────────────
	for sp in _spheres:
		_add_sphere_wire(sp["pos"], sp["radius"], sp["color"])

	_immediate.surface_end()

# ─────────────────────────────────────────────────────────────────
func _add_cross(pos: Vector3, size: float, color: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		_immediate.surface_set_color(color)
		_immediate.surface_add_vertex(pos - axis * size)
		_immediate.surface_set_color(color)
		_immediate.surface_add_vertex(pos + axis * size)

func _add_sphere_wire(center: Vector3, radius: float, color: Color) -> void:
	var segments := 16
	# Tres círculos: XY, XZ, YZ
	_add_circle(center, radius, color, segments, 0)
	_add_circle(center, radius, color, segments, 1)
	_add_circle(center, radius, color, segments, 2)

func _add_circle(center: Vector3, radius: float, color: Color, segments: int, plane: int) -> void:
	var prev := Vector3.ZERO
	for i in range(segments + 1):
		var ang = TAU * float(i) / float(segments)
		var x = cos(ang) * radius
		var y = sin(ang) * radius
		var pt : Vector3
		match plane:
			0: pt = Vector3(x, y, 0.0)    # XY
			1: pt = Vector3(x, 0.0, y)    # XZ
			_: pt = Vector3(0.0, x, y)    # YZ
		pt += center
		if i > 0:
			_immediate.surface_set_color(color)
			_immediate.surface_add_vertex(prev)
			_immediate.surface_set_color(color)
			_immediate.surface_add_vertex(pt)
		prev = pt
