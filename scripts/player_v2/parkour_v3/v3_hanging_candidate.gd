class_name V3HangingCandidate
extends RefCounted

## Resultado explicable de la observación de Hanging. Expresa una posibilidad;
## no mueve el body ni solicita todavía el traspaso de gobierno.
var is_valid := false
var rejection_reasons: PackedStringArray = []
var wall_hit_count := 0
var wall_point := Vector3.ZERO
var wall_normal := Vector3.ZERO
var edge_point := Vector3.ZERO
var edge_normal := Vector3.ZERO
var relative_edge_height := 0.0
var wall_alignment := 0.0
var intent_class := "sin_borde"
var shape_hit_count := 0
var shape_supports_wall := false
var pose := Transform3D.IDENTITY
var pose_clear := false
var local_evidence_score := 0.0


func reject(reason: String) -> void:

	if not rejection_reasons.has(reason):
		rejection_reasons.append(reason)


func rejection_summary() -> String:

	return "ninguno" if rejection_reasons.is_empty() else ", ".join(rejection_reasons)
