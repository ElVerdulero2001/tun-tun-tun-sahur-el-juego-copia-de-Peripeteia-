class_name TraversalLease
extends RefCounted

## Token de propiedad exclusiva sobre el movimiento físico de PlayerMotor
## durante un tramo de traversal (doc de arquitectura V0.3, sección 9). Lo
## emite PlayerMotor.begin_traversal() y es la ÚNICA credencial que aceptan
## apply_traversal_pose()/end_traversal(). No es un booleano: PlayerMotor
## compara identidad de referencia (==) contra el lease que sostiene, así
## que nadie puede fabricar uno ni "adivinar" que tiene permiso.
##
## Solo PlayerMotor invalida un lease (al cerrarlo, explícito o forzado).
## Un lease inválido no debe reutilizarse — quien lo sostenga debe pedir uno
## nuevo con begin_traversal().
##
## Guarda también la última pose confirmada como físicamente válida
## (sección 9.1: "TraversalMoveResult debe conservar last_safe_pose").
## Vive ACÁ, no en PlayerMotor, porque es un dato del tramo de traversal en
## curso — nace con el lease (la pose de arranque siempre es válida, ya
## estaba ahí) y muere con él. Solo PlayerMotor la actualiza, y solo cuando
## de verdad hay una pose nueva confirmada sin penetración — nunca con una
## pose inmóvil que resultó penetrada por geometría nueva.

var owner: Object
var _valido: bool = true
var _pose_segura: Transform3D


func _init(p_owner: Object, p_pose_inicial: Transform3D) -> void:
	owner = p_owner
	_pose_segura = p_pose_inicial


func is_valid() -> bool:
	return _valido


func get_pose_segura() -> Transform3D:
	return _pose_segura


## Autorizado SOLO para PlayerMotor al cerrar este lease.
func _invalidar() -> void:
	_valido = false


## Autorizado SOLO para PlayerMotor, y SOLO con una pose ya confirmada sin
## penetración (ver apply_traversal_pose en player_motor.gd).
func _actualizar_pose_segura(pose: Transform3D) -> void:
	_pose_segura = pose
