class_name GuidedVehicle
extends AnimatableBody3D

## Vehículo guiado por Path3D.
## Contiene toda la lógica de navegación, movimiento, estados y re-targeting.
## Es el único propietario de _progress_actual.
## Los RoutePoints (StopPoints y TransitionPoints) son referencias estáticas:
## nunca toman decisiones, nunca mueven el vehículo.

# ---------------------------------------------------------------------------
# Enumeración de estados
# ---------------------------------------------------------------------------

enum Estado {
	STOPPED,
	ACCELERATING,
	CRUISING,
	BRAKING,
}

# ---------------------------------------------------------------------------
# Constantes internas
# ---------------------------------------------------------------------------

## Límite de encadenamientos de estado dentro de un mismo frame (ver D1:
## detección de cruce de transition robusta ante delta grande). Si un frame
## con delta muy grande cruza más transitions de las que este límite permite
## procesar en cadena, el sobrante se descarta con push_error en vez de
## encadenar sin cota.
const LIMITE_ENCADENAMIENTO_ESTADO: int = 2

# ---------------------------------------------------------------------------
# Exports — configurables desde el Inspector
# ---------------------------------------------------------------------------

@export var path: Path3D
@export var stop_inicial: StopPoint
@export var velocidad_crucero: float = 10.0
@export var epsilon: float = 0.01
@export var curva_velocidad: Curve

# ---------------------------------------------------------------------------
# Variables persistentes — fuente de verdad del sistema
# ---------------------------------------------------------------------------

var _progress_actual: float = 0.0
var _progress_objetivo: float = 0.0
var _direccion: int = 1
var _estado_actual: Estado = Estado.STOPPED
var _factor: float = 0.0

# ---------------------------------------------------------------------------
# Variables temporales — cachés de viaje, se invalidan en re-targeting
# ---------------------------------------------------------------------------

var _stop_destino: StopPoint = null
var _stop_origen_viaje: StopPoint = null   # Stop desde el cual arrancó la fase
											# ACCELERATING del viaje actual (ver E1/E2).
var _transition_salida: TransitionPoint = null   # Se asigna al salir desde STOPPED.
												# Se recalcula en _retarget() SOLO si
												# la dirección cambia durante ACCELERATING
												# (ver E1/E2); en el resto de los casos
												# de re-targeting no se toca.
var _transition_llegada: TransitionPoint = null
var progress_inicio_aceleracion: float = 0.0
var distancia_total_aceleracion: float = 0.0
var distancia_total_frenado: float = 0.0

# ---------------------------------------------------------------------------
# Flag de inicialización diferida
# ---------------------------------------------------------------------------

var _initialized: bool = false

# ---------------------------------------------------------------------------
# _ready — no inicializa nada; el árbol puede no estar listo
# ---------------------------------------------------------------------------

func _ready() -> void:
	pass

# ---------------------------------------------------------------------------
# _physics_process — punto de entrada principal
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _initialized:
		_inicializar()
		return

	match _estado_actual:
		Estado.STOPPED:
			_estado_stopped()
		Estado.ACCELERATING:
			_estado_accelerating(delta)
		Estado.CRUISING:
			_estado_cruising(delta)
		Estado.BRAKING:
			_estado_braking(delta)

	_actualizar_posicion_fisica()

# ---------------------------------------------------------------------------
# Inicialización diferida
# ---------------------------------------------------------------------------

func _inicializar() -> void:
	assert(path != null, "GuidedVehicle: falta asignar 'path' en el Inspector.")
	assert(stop_inicial != null, "GuidedVehicle: falta asignar 'stop_inicial' en el Inspector.")
	assert(curva_velocidad != null, "GuidedVehicle: falta asignar 'curva_velocidad' en el Inspector.")
	assert(path.curve != null and path.curve.get_baked_length() > 0.0,
		"GuidedVehicle: 'path' no tiene un Curve3D válido (curve es null o de longitud cero).")

	if not _stop_pertenece_a_path(stop_inicial):
		push_error("GuidedVehicle: 'stop_inicial' (%s) fue rechazado porque no pertenece al Path3D asignado en 'path' (%s)." % [stop_inicial.name, path.name])
		return

	_progress_actual   = stop_inicial.progress
	_progress_objetivo = stop_inicial.progress
	_stop_destino      = stop_inicial
	_factor            = 0.0
	_estado_actual     = Estado.STOPPED

	_actualizar_posicion_fisica()
	_initialized = true

# ---------------------------------------------------------------------------
# Posicionamiento físico — derivado exclusivamente de _progress_actual
# ---------------------------------------------------------------------------

func _actualizar_posicion_fisica() -> void:
	var longitud: float = path.curve.get_baked_length()
	var t: float = clampf(_progress_actual / longitud, 0.0, 1.0)
	var pos: Vector3 = path.curve.sample_baked(t * longitud)
	global_position = path.global_transform * pos

# ---------------------------------------------------------------------------
# API pública — consulta de velocidad (usada por objetos que se apoyan en el vehículo)
# ---------------------------------------------------------------------------

func get_velocidad_actual() -> Vector3:
	var longitud: float = path.curve.get_baked_length()
	var epsilon_tangente := 0.05
	var p0: float = clampf(_progress_actual, 0.0, longitud)
	var p1: float = clampf(_progress_actual + epsilon_tangente * _direccion, 0.0, longitud)

	if is_equal_approx(p0, p1):
		return Vector3.ZERO

	var pos0: Vector3 = path.curve.sample_baked(p0)
	var pos1: Vector3 = path.curve.sample_baked(p1)
	var tangente_local: Vector3 = (pos1 - pos0).normalized()
	var tangente_global: Vector3 = path.global_transform.basis * tangente_local

	return tangente_global * (velocidad_crucero * _factor)

# ---------------------------------------------------------------------------
# API pública — solicitar destino
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# API pública — solicitar destino
# ---------------------------------------------------------------------------

func solicitar_destino(nuevo_stop: StopPoint) -> void:
	assert(nuevo_stop != null, "GuidedVehicle: solicitar_destino recibió un StopPoint nulo.")

	if not _stop_pertenece_a_path(nuevo_stop):
		push_error("GuidedVehicle: solicitar_destino() rechazó '%s' porque no pertenece al Path3D asignado en 'path' (%s)." % [nuevo_stop.name, (path.name as String) if path != null else "null"])
		return

	var nuevo_progress_objetivo: float = nuevo_stop.progress

	# Orden redundante: ya estamos en el destino solicitado.
	if abs(_progress_actual - nuevo_progress_objetivo) < epsilon:
		return

	match _estado_actual:
		Estado.STOPPED:
			_planificar_desde_stop(nuevo_stop, nuevo_progress_objetivo)
		Estado.ACCELERATING, Estado.CRUISING, Estado.BRAKING:
			_retarget(nuevo_stop, nuevo_progress_objetivo)
		_:
			push_error("GuidedVehicle: solicitar_destino() recibió un _estado_actual (%d) no contemplado en este match. La orden fue descartada silenciosamente sin este error." % _estado_actual)

# ---------------------------------------------------------------------------
# Planificación completa desde STOPPED
# Calcula: _direccion, _transition_salida, _transition_llegada.
# _transition_salida pertenece al stop de origen (donde está parado el vehículo).
# _transition_llegada pertenece al stop destino.
# ---------------------------------------------------------------------------

func _planificar_desde_stop(nuevo_stop: StopPoint, nuevo_progress_obj: float) -> void:
	var nueva_direccion: int = _calcular_direccion(nuevo_progress_obj)

	var nueva_transition_salida: TransitionPoint = _seleccionar_transition_salida(
		_stop_destino, nueva_direccion
	)
	if nueva_transition_salida == null:
		push_error("GuidedVehicle: no se pudo determinar _transition_salida para el stop origen.")
		return

	var nueva_transition_llegada: TransitionPoint = _seleccionar_transition_llegada(
		nuevo_stop, nueva_direccion
	)
	if nueva_transition_llegada == null:
		push_error("GuidedVehicle: no se pudo determinar _transition_llegada para el stop destino.")
		return

	if not _transition_pertenece_a_path(nueva_transition_salida):
		push_error("GuidedVehicle: la _transition_salida resuelta ('%s') no pertenece al Path3D asignado en 'path'." % nueva_transition_salida.name)
		return
	if not _transition_pertenece_a_path(nueva_transition_llegada):
		push_error("GuidedVehicle: la _transition_llegada resuelta ('%s') no pertenece al Path3D asignado en 'path'." % nueva_transition_llegada.name)
		return

	# Commit
	_stop_origen_viaje  = _stop_destino
	_stop_destino       = nuevo_stop
	_progress_objetivo  = nuevo_progress_obj
	_direccion          = nueva_direccion
	_transition_salida  = nueva_transition_salida
	_transition_llegada = nueva_transition_llegada

	_entrar_accelerating()

# ---------------------------------------------------------------------------
# Re-targeting desde movimiento (ACCELERATING, CRUISING, BRAKING)
# La fase de salida ya ocurrió: _transition_salida NO se recalcula.
# Se recalculan: _direccion, _progress_objetivo, _transition_llegada.
# ACCELERATING no puede regenerarse desde movimiento.
# Estado resultante: CRUISING o BRAKING según posición relativa al nuevo destino.
# ---------------------------------------------------------------------------

func _retarget(nuevo_stop: StopPoint, nuevo_progress_obj: float) -> void:
	# Si el destino es el mismo que el actual, ignorar la orden.
	if nuevo_stop == _stop_destino:
		return

	var nueva_direccion: int = _calcular_direccion(nuevo_progress_obj)

	var nueva_transition_llegada: TransitionPoint = _seleccionar_transition_llegada(
		nuevo_stop, nueva_direccion
	)
	if nueva_transition_llegada == null:
		push_error("GuidedVehicle: no se pudo determinar _transition_llegada en re-targeting.")
		return

	if not _transition_pertenece_a_path(nueva_transition_llegada):
		push_error("GuidedVehicle: la _transition_llegada resuelta ('%s') en re-targeting no pertenece al Path3D asignado en 'path'." % nueva_transition_llegada.name)
		return

	# E1/E2: si el re-target ocurre durante ACCELERATING y la dirección cambia,
	# _transition_salida quedó calculada para la dirección vieja y ya no es
	# geométricamente válida para la nueva. Hay que recalcularla usando el
	# mismo stop de origen desde el cual arrancó esta fase ACCELERATING.
	# Fuera de este caso exacto (CRUISING, BRAKING, o ACCELERATING sin cambio
	# de dirección) _transition_salida permanece intacta, sin excepciones.
	var nueva_transition_salida: TransitionPoint = _transition_salida
	if _estado_actual == Estado.ACCELERATING and nueva_direccion != _direccion:
		if _stop_origen_viaje == null:
			push_error("GuidedVehicle: re-targeting con cambio de dirección durante ACCELERATING, pero _stop_origen_viaje es null. No se puede recalcular _transition_salida.")
			return

		var transition_salida_recalculada: TransitionPoint = _seleccionar_transition_salida(
			_stop_origen_viaje, nueva_direccion
		)
		if transition_salida_recalculada == null:
			push_error("GuidedVehicle: no se pudo recalcular _transition_salida para el stop de origen del viaje ('%s') con la nueva dirección." % _stop_origen_viaje.name)
			return
		if not _transition_pertenece_a_path(transition_salida_recalculada):
			push_error("GuidedVehicle: la _transition_salida recalculada ('%s') no pertenece al Path3D asignado en 'path'." % transition_salida_recalculada.name)
			return

		nueva_transition_salida = transition_salida_recalculada

	# Commit
	_stop_destino       = nuevo_stop
	_progress_objetivo  = nuevo_progress_obj
	_direccion          = nueva_direccion
	_transition_salida  = nueva_transition_salida
	_transition_llegada = nueva_transition_llegada

	# Determinar estado resultante según posición relativa a la nueva zona de frenado.
	# dist_a_llegada > 0: la zona de frenado está adelante → CRUISING.
	# dist_a_llegada <= 0: ya estamos dentro o pasamos la zona de frenado → BRAKING.
	var dist_a_llegada: float = (_transition_llegada.progress - _progress_actual) * _direccion
	if dist_a_llegada > 0.0:
		_entrar_cruising()
	else:
		_entrar_braking()

# ---------------------------------------------------------------------------
# Helpers de selección de TransitionPoints
# ---------------------------------------------------------------------------

## Transition de salida: el que está DEL LADO HACIA DONDE VA el vehículo.
## Dirección 1  → transition con mayor progress (adelante en la ruta).
## Dirección -1 → transition con menor progress (atrás en la ruta).
func _seleccionar_transition_salida(stop: StopPoint, dir: int) -> TransitionPoint:
	if stop == null:
		return null

	var ta: TransitionPoint = stop.transition_a
	var tb: TransitionPoint = stop.transition_b

	if ta != null and tb != null:
		if dir == 1:
			return ta if ta.progress > tb.progress else tb
		else:
			return ta if ta.progress < tb.progress else tb
	elif ta != null:
		return ta
	elif tb != null:
		return tb

	return null

## Transition de llegada: el que está DEL LADO DESDE DONDE LLEGA el vehículo.
## Dirección 1  → transition con menor progress (antes del stop en la ruta).
## Dirección -1 → transition con mayor progress (después del stop en la ruta).
func _seleccionar_transition_llegada(stop: StopPoint, dir: int) -> TransitionPoint:
	if stop == null:
		return null

	var ta: TransitionPoint = stop.transition_a
	var tb: TransitionPoint = stop.transition_b

	if ta != null and tb != null:
		if dir == 1:
			return ta if ta.progress < tb.progress else tb
		else:
			return ta if ta.progress > tb.progress else tb
	elif ta != null:
		return ta
	elif tb != null:
		return tb

	return null

func _calcular_direccion(nuevo_progress_obj: float) -> int:
	return 1 if nuevo_progress_obj > _progress_actual else -1

# ---------------------------------------------------------------------------
# Helpers de validación de pertenencia al Path3D
# Un StopPoint o TransitionPoint solo es válido para este vehículo si está
# anidado (en cualquier profundidad) bajo el mismo Path3D asignado en 'path'.
# ---------------------------------------------------------------------------

## Recorre la cadena de padres de 'nodo' buscando el Path3D asignado al vehículo.
## Devuelve false si 'path' no está asignado, si 'nodo' es null, o si se llega
## a la raíz del árbol sin encontrar 'path' entre los ancestros.
func _nodo_pertenece_a_path(nodo: Node) -> bool:
	if path == null or nodo == null:
		return false

	var actual: Node = nodo.get_parent()
	while actual != null:
		if actual == path:
			return true
		actual = actual.get_parent()

	return false

func _stop_pertenece_a_path(stop: StopPoint) -> bool:
	return _nodo_pertenece_a_path(stop)

func _transition_pertenece_a_path(transition: TransitionPoint) -> bool:
	return _nodo_pertenece_a_path(transition)

# ---------------------------------------------------------------------------
# Entradas de estado
# ---------------------------------------------------------------------------

func _entrar_accelerating() -> void:
	assert(_transition_salida != null,
		"GuidedVehicle: _transition_salida es null al entrar en ACCELERATING.")
	progress_inicio_aceleracion = _progress_actual
	distancia_total_aceleracion = abs(_transition_salida.progress - progress_inicio_aceleracion)
	assert(distancia_total_aceleracion > epsilon,
		"GuidedVehicle: distancia_total_aceleracion <= epsilon. Revisá la posición del TransitionPoint de salida.")
	_estado_actual = Estado.ACCELERATING

func _entrar_cruising() -> void:
	_factor        = 1.0
	_estado_actual = Estado.CRUISING

func _entrar_braking() -> void:
	assert(_transition_llegada != null,
		"GuidedVehicle: _transition_llegada es null al entrar en BRAKING.")
	var inicio_frenado: float = _calcular_inicio_frenado()
	distancia_total_frenado = abs(_progress_objetivo - inicio_frenado)
	assert(distancia_total_frenado > epsilon,
		"GuidedVehicle: distancia_total_frenado <= epsilon. Revisá la posición del TransitionPoint de llegada.")
	_estado_actual = Estado.BRAKING

## Determina desde qué punto comienza efectivamente el frenado para este viaje.
## Criterio puramente geométrico: si _transition_llegada está por delante del vehículo
## en la dirección actual, el frenado empieza ahí. Si ya quedó atrás, empieza
## desde _progress_actual.
func _calcular_inicio_frenado() -> float:
	var dist_a_llegada: float = (_transition_llegada.progress - _progress_actual) * _direccion
	if dist_a_llegada > 0.0:
		return _transition_llegada.progress
	else:
		return _progress_actual

func _entrar_stopped() -> void:
	_progress_actual = _progress_objetivo
	_factor          = 0.0
	_estado_actual   = Estado.STOPPED

# ---------------------------------------------------------------------------
# Lógica por estado
# ---------------------------------------------------------------------------

func _estado_stopped() -> void:
	pass  # Inmóvil. Solo solicitar_destino() puede sacarlo de aquí.

func _estado_accelerating(delta: float, profundidad: int = 0) -> void:
	var distancia_recorrida: float = abs(_progress_actual - progress_inicio_aceleracion)
	var t: float = clampf(distancia_recorrida / distancia_total_aceleracion, 0.0, 1.0)
	_factor = curva_velocidad.sample(t)

	var progress_inicial_frame: float = _progress_actual
	var dist_antes: float = (_transition_salida.progress - _progress_actual) * _direccion
	_progress_actual += velocidad_crucero * _factor * _direccion * delta
	var dist_despues: float = (_transition_salida.progress - _progress_actual) * _direccion

	if dist_antes > 0.0 and dist_despues <= 0.0:
		var distancia_total_intentada: float = abs(_progress_actual - progress_inicial_frame)
		var delta_sobrante: float = 0.0

		if distancia_total_intentada > epsilon:
			var distancia_hasta_transition: float = abs(_transition_salida.progress - progress_inicial_frame)
			var fraccion_usada: float = clampf(distancia_hasta_transition / distancia_total_intentada, 0.0, 1.0)
			delta_sobrante = delta * (1.0 - fraccion_usada)

		_progress_actual = _transition_salida.progress
		_entrar_cruising()

		if delta_sobrante > epsilon:
			if profundidad + 1 <= LIMITE_ENCADENAMIENTO_ESTADO:
				_estado_cruising(delta_sobrante, profundidad + 1)
			else:
				push_error("GuidedVehicle: se alcanzó el límite de encadenamiento de estados (%d) en el mismo frame. Delta sobrante descartado." % LIMITE_ENCADENAMIENTO_ESTADO)

func _estado_cruising(delta: float, profundidad: int = 0) -> void:
	var progress_inicial_frame: float = _progress_actual
	var dist_antes: float = (_transition_llegada.progress - _progress_actual) * _direccion
	_progress_actual += velocidad_crucero * _direccion * delta
	var dist_despues: float = (_transition_llegada.progress - _progress_actual) * _direccion

	if dist_antes > 0.0 and dist_despues <= 0.0:
		var distancia_total_intentada: float = abs(_progress_actual - progress_inicial_frame)
		var delta_sobrante: float = 0.0

		if distancia_total_intentada > epsilon:
			var distancia_hasta_transition: float = abs(_transition_llegada.progress - progress_inicial_frame)
			var fraccion_usada: float = clampf(distancia_hasta_transition / distancia_total_intentada, 0.0, 1.0)
			delta_sobrante = delta * (1.0 - fraccion_usada)

		_progress_actual = _transition_llegada.progress
		_entrar_braking()

		if delta_sobrante > epsilon:
			if profundidad + 1 <= LIMITE_ENCADENAMIENTO_ESTADO:
				_estado_braking(delta_sobrante, profundidad + 1)
			else:
				push_error("GuidedVehicle: se alcanzó el límite de encadenamiento de estados (%d) en el mismo frame. Delta sobrante descartado." % LIMITE_ENCADENAMIENTO_ESTADO)

func _estado_braking(delta: float, _profundidad: int = 0) -> void:
	var distancia_restante: float = abs(_progress_objetivo - _progress_actual)
	var t: float = clampf(distancia_restante / distancia_total_frenado, 0.0, 1.0)
	_factor = curva_velocidad.sample(t)
	_progress_actual += velocidad_crucero * _factor * _direccion * delta

	# Invariante: _progress_actual nunca puede quedar más allá de _progress_objetivo
	# en la dirección de viaje. Se aplica antes de cualquier cálculo que dependa
	# de _progress_actual para que el resto del estado siempre vea un valor válido.
	if _direccion == 1:
		_progress_actual = minf(_progress_actual, _progress_objetivo)
	else:
		_progress_actual = maxf(_progress_actual, _progress_objetivo)

	if abs(_progress_actual - _progress_objetivo) < epsilon:
		_entrar_stopped()
