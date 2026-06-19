extends AnimatableBody3D

@export var velocidad_crucero: float = 5.0
@export var velocidad_frenado: float = 2.0

enum VehicleState {
	CRUISING,
	BRAKING,
	STOPPED
}

var _estado: VehicleState = VehicleState.CRUISING

var _curva: Curve3D
var _longitud: float

var _progress_actual: float = 0.0
var _velocidad_actual: float = 5.0

var _routepoints: Array[PathFollow3D] = []
var _indice_actual: int = 0

var _progress_objetivo: float = 0.0
var _terminado: bool = false


func _ready() -> void:

	var path := get_parent() as Path3D

	if path == null:
		push_error("Vehicle debe ser hijo de un Path3D")
		return

	_curva = path.curve
	_longitud = _curva.get_baked_length()

	_velocidad_actual = velocidad_crucero

	_construir_lista()

	if _routepoints.is_empty():
		push_error("No se encontraron RoutePoints")
		return

	_seleccionar_objetivo(0)


func _construir_lista() -> void:

	_routepoints.clear()

	var path := get_parent() as Path3D

	for child in path.get_children():

		if child is PathFollow3D:
			_routepoints.append(child)

	_routepoints.sort_custom(
		func(a: PathFollow3D, b: PathFollow3D) -> bool:
			return a.progress < b.progress
	)

	print("")
	print("===== LISTA DE ROUTEPOINTS =====")

	for i in range(_routepoints.size()):

		var rp := _routepoints[i]

		print(
			"#",
			i,
			" | ",
			rp.name,
			" | Progress: ",
			rp.progress,
			"m"
		)

	print("===============================")
	print("")


func _seleccionar_objetivo(indice: int) -> void:

	if indice >= _routepoints.size():

		print("")
		print("===================================")
		print("FIN DE LA RUTA")
		print("===================================")
		print("")

		_terminado = true
		return

	_indice_actual = indice

	var rp := _routepoints[_indice_actual]

	_progress_objetivo = rp.progress

	print("")
	print("Nuevo objetivo: ", rp.name)
	print("Progress objetivo: ", _progress_objetivo)
	print("")


func _procesar_routepoint(rp: PathFollow3D) -> void:

	match rp.point_type:

		rp.RoutePointType.BRAKE:

			_estado = VehicleState.BRAKING
			_velocidad_actual = velocidad_frenado

			print("")
			print(">>> ESTADO = BRAKING")
			print(">>> VELOCIDAD = ", _velocidad_actual)
			print("")

		rp.RoutePointType.STOP:

			_estado = VehicleState.STOPPED
			_velocidad_actual = 0.0

			print("")
			print(">>> ESTADO = STOPPED")
			print(">>> VELOCIDAD = ", _velocidad_actual)
			print("")

		rp.RoutePointType.CRUISE:

			_estado = VehicleState.CRUISING
			_velocidad_actual = velocidad_crucero

			print("")
			print(">>> ESTADO = CRUISING")
			print(">>> VELOCIDAD = ", _velocidad_actual)
			print("")


func _physics_process(delta: float) -> void:

	if _curva == null:
		return

	if _terminado:
		return

	_progress_actual += _velocidad_actual * delta

	if _progress_actual >= _progress_objetivo:

		_progress_actual = _progress_objetivo

		var rp := _routepoints[_indice_actual]

		print("")
		print("===================================")
		print("LLEGUÉ A: ", rp.name)
		print("Progress: ", rp.progress)
		print("===================================")
		print("")

		_procesar_routepoint(rp)

		_seleccionar_objetivo(_indice_actual + 1)

	var posicion_local: Vector3 = _curva.sample_baked(
		_progress_actual
	)

	var posicion_global: Vector3 = (
		get_parent() as Path3D
	).to_global(posicion_local)

	move_and_collide(
		posicion_global - global_position
	)
