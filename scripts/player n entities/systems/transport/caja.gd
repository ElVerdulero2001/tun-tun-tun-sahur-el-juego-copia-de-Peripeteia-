extends AnimatableBody3D

@export var velocidad: float = 5.0

var _curva: Curve3D = null
var _longitud: float = 0.0
var _progreso: float = 0.0

func _ready() -> void:
	_curva = (get_parent() as Path3D).curve
	_longitud = _curva.get_baked_length()

func _physics_process(delta: float) -> void:
	_progreso += (velocidad * delta) / _longitud
	if _progreso > 1.0:
		_progreso -= 1.0

	var pos_local = _curva.sample_baked(_progreso * _longitud)
	var pos_global = get_parent().to_global(pos_local)
	move_and_collide(pos_global - global_position)
