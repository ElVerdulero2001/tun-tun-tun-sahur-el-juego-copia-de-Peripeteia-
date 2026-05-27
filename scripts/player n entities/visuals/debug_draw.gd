# debug_draw.gd
# AUTOLOAD. Sistema de visualización 3D para debugging.
#
# Uso desde cualquier script:
#   DebugDraw.clear()                          <- limpiar antes de dibujar
#   DebugDraw.ray(origen, destino, Color.RED)
#   DebugDraw.point(posicion, Color.GREEN)
#   DebugDraw.sphere(posicion, radio, Color.YELLOW)
#
# Cada sistema que dibuja es responsable de llamar clear() al inicio
# de su physics_process, antes de agregar sus primitivas. Asi el orden
# del arbol no importa — cada uno limpia y redibuja lo suyo.

extends Node

var enabled : bool = false
var frozen  : bool = false

var _rays    : Array = []
var _points  : Array = []
var _spheres : Array = []

var _mesh_instance : MeshInstance3D
var _immediate     : ImmediateMesh
var _material      : StandardMaterial3D

func _ready() -> void:
	_immediate = ImmediateMesh.new()

	_material = StandardMaterial3D.new()
	_material.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test              = true
	_material.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh              = _immediate
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	call_deferred("_attach_to_scene")

func _attach_to_scene() -> void:
	var root = get_tree().current_scene
	if root:
		root.add_child(_mesh_instance)

# ── API PÚBLICA ───────────────────────────────────────────────────

func clear() -> void:
	if frozen:
		return
	_rays.clear()
	_points.clear()
	_spheres.clear()

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

# ── RENDERING ─────────────────────────────────────────────────────
# Solo dibuja. El clear lo hace cada sistema antes de agregar sus datos.

func _process(_delta: float) -> void:
	if _mesh_instance and not _mesh_instance.is_inside_tree():
		_attach_to_scene()

	if Input.is_action_just_pressed("toggle_debug_freeze"):
		toggle_freeze()

	_redraw()

func _redraw() -> void:
	if not _immediate:
		return

	_immediate.clear_surfaces()

	if _rays.is_empty() and _points.is_empty() and _spheres.is_empty():
		return

	_immediate.surface_begin(Mesh.PRIMITIVE_LINES)

	for r in _rays:
		_immediate.surface_set_color(r["color"])
		_immediate.surface_add_vertex(r["from"])
		_immediate.surface_set_color(r["color"])
		_immediate.surface_add_vertex(r["to"])

	for p in _points:
		_add_cross(p["pos"], p["size"], p["color"])

	for sp in _spheres:
		_add_sphere_wire(sp["pos"], sp["radius"], sp["color"])

	_immediate.surface_end()

func _add_cross(pos: Vector3, size: float, color: Color) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		_immediate.surface_set_color(color)
		_immediate.surface_add_vertex(pos - axis * size)
		_immediate.surface_set_color(color)
		_immediate.surface_add_vertex(pos + axis * size)

func _add_sphere_wire(center: Vector3, radius: float, color: Color) -> void:
	var segments := 16
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
			0: pt = Vector3(x, y, 0.0)
			1: pt = Vector3(x, 0.0, y)
			2: pt = Vector3(0.0, x, y)
		pt += center
		if i > 0:
			_immediate.surface_set_color(color)
			_immediate.surface_add_vertex(prev)
			_immediate.surface_set_color(color)
			_immediate.surface_add_vertex(pt)
		prev = pt
