class_name V3H0DebugOverlay
extends Label

## Observación de solo lectura. No interviene en input, H0 ni física.
@export var input_source: V3InputSource
@export var h0: H0Core
@export var physics_body: V3PhysicsBody
@export var camera_rig: V3CameraRig
@export var fall_damage_state: Node


func _process(_delta: float) -> void:
	if input_source == null or h0 == null or physics_body == null or camera_rig == null or fall_damage_state == null:
		text = "V3 H0 debug: referencias incompletas"
		return

	var facts := physics_body.get_physics_facts()
	var camera_facts := camera_rig.get_camera_facts()
	text = (
		"V3 H0 — laboratorio\n"
		+ "input crudo: %s\n" % input_source.movement_axis
		+ "sprint: input %s | aplicado %s | vel %.2f | transición %.2fs\n" % [input_source.sprint_active, h0.last_sprint_active, h0.last_ground_speed_requested, h0.last_sprint_transition_remaining]
		+ "salto: intención sostenida %s | pedido %s | aceptado %s\n" % [input_source.jump_pressed, h0.last_jump_requested, facts["jump_accepted"]]
		+ "agachado: deseado %s | físico %s | ancla %s | pararse bloqueado %s\n" % [h0.wants_crouched, facts["is_crouched"], facts["crouch_anchor"], facts["stand_request_blocked"]]
		+ "caída: tramo actual %.2fm | último aterrizaje %.2fm | lesión bloquea salto: %s\n" % [facts["fall_distance_in_current_airtime"], facts["last_landing_fall_distance"], fall_damage_state.jump_is_penalized]
		+ "control aire: %.2fs\n" % h0.last_air_control_remaining
		+ "cámara pos: %s | distancia body: %.2f\n" % [camera_facts["position"], camera_facts["distance_to_body"]]
		+ "cámara forward: %s | yaw: %.1f° | pitch: %.1f°\n" % [camera_facts["planar_forward"], camera_facts["body_yaw_degrees"], camera_facts["view_pitch_degrees"]]
		+ "intención H0: %s\n" % h0.last_desired_horizontal_velocity
		+ "autoridad física: %s\n" % facts["intent_source"]
		+ "velocidad real: %s\n" % facts["actual_velocity"]
		+ "desplazamiento real: %s\n" % facts["displacement"]
		+ "en piso: %s | contactos: %s" % [facts["is_on_floor"], facts["collision_count"]]
	)
