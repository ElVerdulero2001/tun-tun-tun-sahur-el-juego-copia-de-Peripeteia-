class_name V3HangingCaptureProbe
extends MeshInstance3D

## Laboratorio de entrada a Hanging. El cilindro rosa C nace en el borde y se
## proyecta hacia afuera usando su normal. La esfera azul S queda fija a la
## altura física de los hombros. Son sensores virtuales: no tienen colisión,
## no guardan historial y sólo informan si S entró en C este tick.
@export var hanging_detector: V3HangingDetector
@export var physics_body: V3PhysicsBody
@export_range(0.05, 1.0, 0.05) var capture_cylinder_radius := 0.15
@export_range(0.05, 2.0, 0.05) var capture_cylinder_length := 0.80
@export_range(0.02, 0.50, 0.01) var shoulder_sensor_radius := 0.10
@export_range(0.0, 2.0, 0.05) var shoulder_height := 1.30

var last_zone_active := false
var last_cylinder_center := Vector3.ZERO
var last_shoulder_center := Vector3.ZERO
var last_sensor_distance_to_cylinder := INF
var last_sensor_enters_cylinder := false
var last_overlap_depth := 0.0

var _shoulder_sensor_visual: MeshInstance3D


func _ready() -> void:

	process_physics_priority = 175
	mesh = _make_cylinder_mesh()
	material_override = _make_material(Color(1.0, 0.12, 0.52, 0.24), Color(0.8, 0.02, 0.22))
	_shoulder_sensor_visual = MeshInstance3D.new()
	_shoulder_sensor_visual.name = "ShoulderSensor"
	_shoulder_sensor_visual.mesh = _make_sphere_mesh(shoulder_sensor_radius)
	_shoulder_sensor_visual.material_override = _make_material(Color(0.12, 0.32, 1.0, 0.38), Color(0.03, 0.12, 0.85))
	add_child(_shoulder_sensor_visual)
	visible = false
	_shoulder_sensor_visual.visible = false


func _physics_process(_delta: float) -> void:

	_read_current_tick()


func _read_current_tick() -> void:

	last_zone_active = false
	last_cylinder_center = Vector3.ZERO
	last_shoulder_center = Vector3.ZERO
	last_sensor_distance_to_cylinder = INF
	last_sensor_enters_cylinder = false
	last_overlap_depth = 0.0
	visible = false
	if _shoulder_sensor_visual != null:
		_shoulder_sensor_visual.visible = false
	if hanging_detector == null or physics_body == null:
		return

	var candidate := hanging_detector.last_candidate
	if candidate == null or not candidate.is_valid or not candidate.has_capture_point:
		return

	var axis := candidate.wall_normal
	axis.y = 0.0
	if axis.length_squared() <= 0.000001:
		return
	axis = axis.normalized()
	last_zone_active = true
	last_cylinder_center = candidate.capture_point + axis * (capture_cylinder_length * 0.5)
	last_shoulder_center = physics_body.global_transform * (Vector3.UP * shoulder_height)
	last_sensor_distance_to_cylinder = _distance_to_cylinder(last_shoulder_center, last_cylinder_center, axis)
	last_overlap_depth = shoulder_sensor_radius - last_sensor_distance_to_cylinder
	last_sensor_enters_cylinder = last_overlap_depth >= 0.0
	global_transform = Transform3D(_basis_with_y_axis(axis), last_cylinder_center)
	visible = true
	if _shoulder_sensor_visual != null:
		_shoulder_sensor_visual.global_position = last_shoulder_center
		_shoulder_sensor_visual.visible = true


func _distance_to_cylinder(point: Vector3, cylinder_center: Vector3, axis: Vector3) -> float:

	var delta := point - cylinder_center
	var axial_distance := absf(delta.dot(axis))
	var radial_distance := (delta - axis * delta.dot(axis)).length()
	var axial_excess := maxf(axial_distance - capture_cylinder_length * 0.5, 0.0)
	var radial_excess := maxf(radial_distance - capture_cylinder_radius, 0.0)
	return sqrt(axial_excess * axial_excess + radial_excess * radial_excess)


func _make_cylinder_mesh() -> CylinderMesh:

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = capture_cylinder_radius
	cylinder.bottom_radius = capture_cylinder_radius
	cylinder.height = capture_cylinder_length
	return cylinder


func _make_sphere_mesh(radius: float) -> SphereMesh:

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	return sphere


func _basis_with_y_axis(axis: Vector3) -> Basis:

	var y_axis := axis.normalized()
	var helper := Vector3.UP if absf(y_axis.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	var x_axis := helper.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _make_material(color: Color, emission_color: Color) -> StandardMaterial3D:

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = emission_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material
