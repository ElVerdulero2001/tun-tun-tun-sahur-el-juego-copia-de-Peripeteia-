class_name TraversalMoveResult
extends RefCounted

## Resultado de PlayerMotor.apply_traversal_pose() (doc de arquitectura V0.3,
## secciones 5 y 9). status distingue si el movimiento guiado se aplicó
## completo (OK), quedó bloqueado por colisión a mitad de camino (BLOCKED),
## o fue rechazado por lease inválido/no vigente (REJECTED) — este último
## no mueve el cuerpo.
##
## last_safe_pose es siempre una pose sin penetración (el punto alcanzado
## antes de cualquier bloqueo, o la pose actual si fue REJECTED).
## TraversalController la usará en fases futuras para recuperación ante
## bloqueo inesperado (sección 9.1); en Fase 2 solo se calcula y expone.

enum Status { OK, BLOCKED, REJECTED }

var status: Status
var last_safe_pose: Transform3D
var blocked_reason: String


func _init(p_status: Status, p_last_safe_pose: Transform3D, p_blocked_reason: String = "") -> void:
	status = p_status
	last_safe_pose = p_last_safe_pose
	blocked_reason = p_blocked_reason
