class_name V3HangingDebugOverlay
extends Label

## Observador de solo lectura del detector experimental de Hanging.
@export var hanging_detector: V3HangingDetector
@export var capture_probe: V3HangingCaptureProbe


func _process(_delta: float) -> void:

	if hanging_detector == null:
		text = "V3 Hanging debug: detector ausente"
		return
	var candidate := hanging_detector.last_candidate
	if candidate == null:
		text = "V3 Hanging debug: sin lectura"
		return

	var capture_line := "captura laboratorio: sonda ausente\n"
	if capture_probe != null:
		var contact_text := "zona inactiva"
		if capture_probe.last_zone_active:
			contact_text = "entra: %s | solapamiento: %.2fm" % [capture_probe.last_sensor_enters_cylinder, capture_probe.last_overlap_depth]
		capture_line = (
			"captura laboratorio: cilindro rosa C %s | esfera azul S %s\n" % [capture_probe.last_cylinder_center, capture_probe.last_shoulder_center]
			+ "radio C %.2fm | largo C %.2fm | radio S %.2fm | distancia a C: %.2fm | %s\n"
			% [capture_probe.capture_cylinder_radius, capture_probe.capture_cylinder_length, capture_probe.shoulder_sensor_radius, capture_probe.last_sensor_distance_to_cylinder, contact_text]
			+ "C/S es lectura actual; el snap siguiente es sólo una prueba de pose\n")
	text = (
		"V3 Hanging — detección solamente\n"
		+ "rayos pared: %d | volumen: %d | respalda pared: %s\n" % [candidate.wall_hit_count, candidate.shape_hit_count, candidate.shape_supports_wall]
		+ "borde: %s | normal pared: %s | altura relativa: %.2f\n" % [candidate.edge_point, candidate.wall_normal, candidate.relative_edge_height]
		+ "intención: %s | alineación pared: %.2f | evidencia local: %.2f\n" % [candidate.intent_class, candidate.wall_alignment, candidate.local_evidence_score]
		+ "ancla captura C: %s\n" % candidate.capture_point
		+ "pose propuesta: %s | cabe: %s\n" % [candidate.pose.origin, candidate.pose_clear]
		+ "candidato Hanging: %s | rechazo: %s\n"
		% ["VÁLIDO" if candidate.is_valid else "RECHAZADO", candidate.rejection_summary()]
		+ capture_line
		+ "sin árbitro final ni movimiento colgado todavía"
	)
