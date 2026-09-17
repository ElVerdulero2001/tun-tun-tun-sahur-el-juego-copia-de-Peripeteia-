class_name V3HangingDebugOverlay
extends Label

## Observador de solo lectura del detector experimental de Hanging.
@export var hanging_detector: V3HangingDetector


func _process(_delta: float) -> void:

	if hanging_detector == null:
		text = "V3 Hanging debug: detector ausente"
		return
	var candidate := hanging_detector.last_candidate
	if candidate == null:
		text = "V3 Hanging debug: sin lectura"
		return

	text = (
		"V3 Hanging — detección solamente\n"
		+ "rayos pared: %d | volumen: %d | respalda pared: %s\n" % [candidate.wall_hit_count, candidate.shape_hit_count, candidate.shape_supports_wall]
		+ "borde: %s | normal pared: %s | altura relativa: %.2f\n" % [candidate.edge_point, candidate.wall_normal, candidate.relative_edge_height]
		+ "intención: %s | alineación pared: %.2f | evidencia local: %.2f\n" % [candidate.intent_class, candidate.wall_alignment, candidate.local_evidence_score]
		+ "pose propuesta: %s | cabe: %s\n" % [candidate.pose.origin, candidate.pose_clear]
		+ "candidato Hanging: %s | rechazo: %s\n"
		% ["VÁLIDO" if candidate.is_valid else "RECHAZADO", candidate.rejection_summary()]
		+ "sin árbitro ni entrada física todavía"
	)
