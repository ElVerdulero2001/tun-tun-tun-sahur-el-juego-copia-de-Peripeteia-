class_name V3HangingDetector
extends Node

## Provider compuesto del primer laboratorio de Hanging. Publica la lectura de
## pared/borde, la corroboración volumétrica y una pose hipotética. No conoce
## el árbitro, no interrumpe H0 y no mueve el CharacterBody3D.
@export var physics_body: V3PhysicsBody
@export var input_source: V3InputSource
@export var camera_rig: V3CameraRig
@export var probe_heights: PackedFloat32Array = [0.3, 0.6, 0.9, 1.2, 1.5]
@export var detection_distance := 0.85
@export var min_edge_height := 0.5
@export var max_edge_height := 1.5
@export var max_surface_tilt_degrees := 30.0
@export var lateral_coherence_tolerance := 0.35
@export var hang_wall_gap := 0.68
@export var hang_root_offset_y := -0.55
@export var shape_width := 0.7
@export var shape_height := 1.2
@export var intent_alignment_threshold := 0.2

var last_candidate := V3HangingCandidate.new()
var last_wall_hits: Array[Dictionary] = []
var last_probe_forward := Vector3.FORWARD
var last_shape_hit_count := 0

var _volume_shape: BoxShape3D


func _ready() -> void:

	# Lee los hechos después de que la capa física común haya terminado el tick.
	process_physics_priority = 150
	_volume_shape = BoxShape3D.new()
	_volume_shape.size = Vector3(shape_width, shape_height, detection_distance)


func _physics_process(_delta: float) -> void:

	_observe()


func _observe() -> void:

	last_candidate = V3HangingCandidate.new()
	last_wall_hits.clear()
	last_shape_hit_count = 0
	if physics_body == null or input_source == null or camera_rig == null:
		last_candidate.reject("referencias_incompletas")
		return

	var world := physics_body.get_world_3d()
	if world == null:
		last_candidate.reject("mundo_fisico_ausente")
		return

	var space := world.direct_space_state
	last_probe_forward = camera_rig.get_planar_forward()
	if last_probe_forward.length_squared() <= 0.000001:
		last_probe_forward = -physics_body.global_transform.basis.z
		last_probe_forward.y = 0.0
		last_probe_forward = last_probe_forward.normalized()

	var shape_results := _query_front_volume(space, last_probe_forward)
	last_shape_hit_count = shape_results.size()
	var best_geometry: Dictionary = {}
	for height in probe_heights:
		var wall_hit := _query_wall(space, last_probe_forward, height)
		if wall_hit.is_empty():
			continue
		last_wall_hits.append(wall_hit)
		var geometry := _find_edge_for_wall(space, wall_hit, last_probe_forward)
		if geometry.is_empty():
			continue
		if best_geometry.is_empty() or float(geometry["alignment"]) > float(best_geometry["alignment"]):
			best_geometry = geometry

	last_candidate.wall_hit_count = last_wall_hits.size()
	last_candidate.shape_hit_count = last_shape_hit_count
	if best_geometry.is_empty():
		last_candidate.reject("sin_pared_y_borde_coherentes")
		return

	_apply_geometry(best_geometry, shape_results)
	var facts := physics_body.get_physics_facts()
	if bool(facts["is_on_floor"]):
		last_candidate.reject("en_piso")

	last_candidate.intent_class = _classify_intent(last_candidate.wall_normal, last_probe_forward)
	if last_candidate.intent_class == "contradictoria":
		last_candidate.reject("intencion_contradictoria")

	last_candidate.pose = _make_hang_pose(last_candidate.edge_point, last_candidate.wall_normal)
	last_candidate.pose_clear = physics_body.can_occupy_pose(last_candidate.pose)
	if not last_candidate.pose_clear:
		last_candidate.reject("pose_bloqueada")

	last_candidate.local_evidence_score = _calculate_local_evidence()
	last_candidate.is_valid = last_candidate.rejection_reasons.is_empty()


func _query_wall(space: PhysicsDirectSpaceState3D, forward: Vector3, height: float) -> Dictionary:

	var origin := physics_body.global_position + Vector3.UP * height
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + forward * detection_distance,
		physics_body.collision_mask,
		[physics_body.get_rid()])
	return space.intersect_ray(query)


func _find_edge_for_wall(space: PhysicsDirectSpaceState3D, wall_hit: Dictionary, forward: Vector3) -> Dictionary:

	var wall_normal: Vector3 = wall_hit["normal"]
	var max_tilt_sine := sin(deg_to_rad(max_surface_tilt_degrees))
	if absf(wall_normal.y) > max_tilt_sine:
		return {}
	var alignment := forward.dot(-wall_normal)
	if alignment <= 0.0:
		return {}

	var wall_point: Vector3 = wall_hit["position"]
	var edge_from := Vector3(
		wall_point.x,
		physics_body.global_position.y + max_edge_height + 0.3,
		wall_point.z) - wall_normal * 0.08
	var edge_to := Vector3(wall_point.x, wall_point.y, wall_point.z) - wall_normal * 0.08
	var edge_query := PhysicsRayQueryParameters3D.create(
		edge_from,
		edge_to,
		physics_body.collision_mask,
		[physics_body.get_rid()])
	var edge_hit := space.intersect_ray(edge_query)
	if edge_hit.is_empty():
		return {}

	var edge_point: Vector3 = edge_hit["position"]
	var edge_normal: Vector3 = edge_hit["normal"]
	var wall_xz := Vector2(wall_point.x, wall_point.z)
	var edge_xz := Vector2(edge_point.x, edge_point.z)
	if wall_xz.distance_to(edge_xz) > lateral_coherence_tolerance:
		return {}
	if edge_normal.dot(Vector3.UP) < cos(deg_to_rad(max_surface_tilt_degrees)):
		return {}

	var relative_height := edge_point.y - physics_body.global_position.y
	if relative_height < min_edge_height or relative_height > max_edge_height:
		return {}

	return {
		"wall_point": wall_point,
		"wall_normal": wall_normal,
		"edge_point": edge_point,
		"edge_normal": edge_normal,
		"relative_height": relative_height,
		"alignment": alignment,
		"wall_collider": wall_hit.get("collider"),
	}


func _query_front_volume(space: PhysicsDirectSpaceState3D, forward: Vector3) -> Array[Dictionary]:

	if _volume_shape == null:
		return []
	_volume_shape.size = Vector3(shape_width, shape_height, detection_distance)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _volume_shape
	query.transform = Transform3D(
		_basis_facing(forward),
		physics_body.global_position + Vector3.UP * (shape_height * 0.5) + forward * (detection_distance * 0.5))
	query.collision_mask = physics_body.collision_mask
	query.exclude = [physics_body.get_rid()]
	return space.intersect_shape(query, 16)


func _apply_geometry(geometry: Dictionary, shape_results: Array[Dictionary]) -> void:

	last_candidate.wall_point = geometry["wall_point"]
	last_candidate.wall_normal = geometry["wall_normal"]
	last_candidate.edge_point = geometry["edge_point"]
	last_candidate.edge_normal = geometry["edge_normal"]
	last_candidate.relative_edge_height = geometry["relative_height"]
	last_candidate.wall_alignment = geometry["alignment"]
	var wall_collider: Object = geometry["wall_collider"]
	for result in shape_results:
		if result.get("collider") == wall_collider:
			last_candidate.shape_supports_wall = true
			break


func _classify_intent(wall_normal: Vector3, forward: Vector3) -> String:

	var intent := camera_rig.get_planar_right() * input_source.movement_axis.x
	intent += forward * -input_source.movement_axis.y
	if intent.length_squared() <= 0.000001:
		return "neutra"
	intent = intent.normalized()
	var toward_wall := -wall_normal
	toward_wall.y = 0.0
	if toward_wall.length_squared() <= 0.000001:
		return "neutra"
	var alignment := intent.dot(toward_wall.normalized())
	if alignment > intent_alignment_threshold:
		return "compatible"
	if alignment < -intent_alignment_threshold:
		return "contradictoria"
	return "neutra"


func _make_hang_pose(edge_point: Vector3, wall_normal: Vector3) -> Transform3D:

	var forward_to_wall := -wall_normal
	forward_to_wall.y = 0.0
	forward_to_wall = forward_to_wall.normalized()
	var origin := edge_point + wall_normal * hang_wall_gap + Vector3.UP * hang_root_offset_y
	return Transform3D(_basis_facing(forward_to_wall), origin)


func _calculate_local_evidence() -> float:

	var ray_support := float(last_candidate.wall_hit_count) / maxf(float(probe_heights.size()), 1.0)
	var score := ray_support * 0.5 + last_candidate.wall_alignment * 0.25
	if last_candidate.shape_supports_wall:
		score += 0.15
	if last_candidate.intent_class == "compatible":
		score += 0.10
	return clampf(score, 0.0, 1.0)


func _basis_facing(forward: Vector3) -> Basis:

	var normalized_forward := forward.normalized()
	var z_axis := -normalized_forward
	var x_axis := Vector3.UP.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)
