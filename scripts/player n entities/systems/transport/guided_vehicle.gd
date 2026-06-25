class_name GuidedVehicle
extends AnimatableBody3D

## Vehículo guiado por Path3D.
## Contiene toda la lógica de navegación, movimiento, estados y re-targeting.
## Es el único propietario de progress_actual.
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

var progress_actual: float = 0.0
var progress_objetivo: float = 0.0
var direccion: int = 1
var estado_actual: Estado = Estado.STOPPED
var factor: float = 0.0

# ---------------------------------------------------------------------------
# Variables temporales — cachés de viaje, se invalidan en re-targeting
# ---------------------------------------------------------------------------

var stop_destino: StopPoint = null
var transition_salida: TransitionPoint = null   # Se asigna SOLO al salir desde STOPPED.
												# No se recalcula en re-targeting.
var transition_llegada: TransitionPoint = null
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

	match estado_actual:
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

	progress_actual   = stop_inicial.progress
	progress_objetivo = stop_inicial.progress
	stop_destino      = stop_inicial
	factor            = 0.0
	estado_actual     = Estado.STOPPED

	_actualizar_posicion_fisica()
	_initialized = true
	print("PATH_INFO | curve_length: ", path.curve.get_baked_length(),
		" | stop_inicial: ", stop_inicial.name,
		" | stop_inicial.progress: ", stop_inicial.progress)

# ---------------------------------------------------------------------------
# Posicionamiento físico — derivado exclusivamente de progress_actual
# ---------------------------------------------------------------------------

func _actualizar_posicion_fisica() -> void:
	var longitud: float = path.curve.get_baked_length()
	var t: float = clampf(progress_actual / longitud, 0.0, 1.0)
	var pos: Vector3 = path.curve.sample_baked(t * longitud)
	global_position = path.global_transform * pos

# ---------------------------------------------------------------------------
# API pública — solicitar destino
# ---------------------------------------------------------------------------

func solicitar_destino(nuevo_stop: StopPoint) -> void:
	assert(nuevo_stop != null, "GuidedVehicle: solicitar_destino recibió un StopPoint nulo.")

	var nuevo_progress_objetivo: float = nuevo_stop.progress

	# Orden redundante: ya estamos en el destino solicitado.
	if abs(progress_actual - nuevo_progress_objetivo) < epsilon:
		return

	print("NUEVO_DESTINO | stop: ", nuevo_stop.name,
		" | stop.progress: ", nuevo_stop.progress,
		" | progress_actual: ", snappedf(progress_actual, 0.0001),
		" | progress_objetivo_anterior: ", snappedf(progress_objetivo, 0.0001),
		" | estado_actual: ", Estado.keys()[estado_actual])
	match estado_actual:
		Estado.STOPPED:
			_planificar_desde_stop(nuevo_stop, nuevo_progress_objetivo)
		Estado.ACCELERATING, Estado.CRUISING, Estado.BRAKING:
			_retarget(nuevo_stop, nuevo_progress_objetivo)

# ---------------------------------------------------------------------------
# Planificación completa desde STOPPED
# Calcula: direccion, transition_salida, transition_llegada.
# transition_salida pertenece al stop de origen (donde está parado el vehículo).
# transition_llegada pertenece al stop destino.
# ---------------------------------------------------------------------------

func _planificar_desde_stop(nuevo_stop: StopPoint, nuevo_progress_obj: float) -> void:
	var nueva_direccion: int = _calcular_direccion(nuevo_progress_obj)

	var nueva_transition_salida: TransitionPoint = _seleccionar_transition_salida(
		stop_destino, nueva_direccion
	)
	if nueva_transition_salida == null:
		push_error("GuidedVehicle: no se pudo determinar transition_salida para el stop origen.")
		return

	var nueva_transition_llegada: TransitionPoint = _seleccionar_transition_llegada(
		nuevo_stop, nueva_direccion
	)
	if nueva_transition_llegada == null:
		push_error("GuidedVehicle: no se pudo determinar transition_llegada para el stop destino.")
		return

	# Commit
	stop_destino       = nuevo_stop
	progress_objetivo  = nuevo_progress_obj
	direccion          = nueva_direccion
	transition_salida  = nueva_transition_salida
	transition_llegada = nueva_transition_llegada

	print("PLANIFICAR_VIAJE | origen: ", stop_destino.name if stop_destino else "null",
		" | destino: ", nuevo_stop.name,
		" | progress_actual: ", snappedf(progress_actual, 0.0001),
		" | progress_objetivo: ", snappedf(progress_objetivo, 0.0001),
		" | direccion: ", nueva_direccion)
	_entrar_accelerating()

# ---------------------------------------------------------------------------
# Re-targeting desde movimiento (ACCELERATING, CRUISING, BRAKING)
# La fase de salida ya ocurrió: transition_salida NO se recalcula.
# Se recalculan: direccion, progress_objetivo, transition_llegada.
# ACCELERATING no puede regenerarse desde movimiento.
# Estado resultante: CRUISING o BRAKING según posición relativa al nuevo destino.
# ---------------------------------------------------------------------------

func _retarget(nuevo_stop: StopPoint, nuevo_progress_obj: float) -> void:
	# Si el destino es el mismo que el actual, ignorar la orden.
	if nuevo_stop == stop_destino:
		return

	var nueva_direccion: int = _calcular_direccion(nuevo_progress_obj)

	var nueva_transition_llegada: TransitionPoint = _seleccionar_transition_llegada(
		nuevo_stop, nueva_direccion
	)
	if nueva_transition_llegada == null:
		push_error("GuidedVehicle: no se pudo determinar transition_llegada en re-targeting.")
		return

	# Commit — transition_salida permanece intacta
	var progress_objetivo_anterior: float = progress_objetivo
	stop_destino       = nuevo_stop
	progress_objetivo  = nuevo_progress_obj
	direccion          = nueva_direccion
	transition_llegada = nueva_transition_llegada
	print("RETARGET | progress_actual: ", snappedf(progress_actual, 0.0001),
		" | progress_objetivo_anterior: ", snappedf(progress_objetivo_anterior, 0.0001),
		" | progress_objetivo_nuevo: ", snappedf(progress_objetivo, 0.0001),
		" | direccion: ", nueva_direccion,
		" | estado_actual: ", Estado.keys()[estado_actual])

	# Determinar estado resultante según posición relativa a la nueva zona de frenado.
	# dist_a_llegada > 0: la zona de frenado está adelante → CRUISING.
	# dist_a_llegada <= 0: ya estamos dentro o pasamos la zona de frenado → BRAKING.
	var dist_a_llegada: float = (transition_llegada.progress - progress_actual) * direccion
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
	return 1 if nuevo_progress_obj > progress_actual else -1

# ---------------------------------------------------------------------------
# Entradas de estado
# ---------------------------------------------------------------------------

func _entrar_accelerating() -> void:
	assert(transition_salida != null,
		"GuidedVehicle: transition_salida es null al entrar en ACCELERATING.")
	progress_inicio_aceleracion = progress_actual
	distancia_total_aceleracion = abs(transition_salida.progress - progress_inicio_aceleracion)
	assert(distancia_total_aceleracion > epsilon,
		"GuidedVehicle: distancia_total_aceleracion <= epsilon. Revisá la posición del TransitionPoint de salida.")
	estado_actual = Estado.ACCELERATING

func _entrar_cruising() -> void:
	factor        = 1.0
	estado_actual = Estado.CRUISING

func _entrar_braking() -> void:
	assert(transition_llegada != null,
		"GuidedVehicle: transition_llegada es null al entrar en BRAKING.")
	var inicio_frenado: float = _calcular_inicio_frenado()
	distancia_total_frenado = abs(progress_objetivo - inicio_frenado)
	assert(distancia_total_frenado > epsilon,
		"GuidedVehicle: distancia_total_frenado <= epsilon. Revisá la posición del TransitionPoint de llegada.")
	estado_actual = Estado.BRAKING
	print("ENTRADA_BRAKING | progress_actual: ", snappedf(progress_actual, 0.0001),
		" | progress_objetivo: ", snappedf(progress_objetivo, 0.0001),
		" | inicio_frenado: ", snappedf(inicio_frenado, 0.0001),
		" | distancia_total_frenado: ", snappedf(distancia_total_frenado, 0.0001),
		" | direccion: ", direccion)

## Determina desde qué punto comienza efectivamente el frenado para este viaje.
## Criterio puramente geométrico: si transition_llegada está por delante del vehículo
## en la dirección actual, el frenado empieza ahí. Si ya quedó atrás, empieza
## desde progress_actual.
func _calcular_inicio_frenado() -> float:
	var dist_a_llegada: float = (transition_llegada.progress - progress_actual) * direccion
	if dist_a_llegada > 0.0:
		return transition_llegada.progress
	else:
		return progress_actual

func _entrar_stopped() -> void:
	progress_actual = progress_objetivo
	factor          = 0.0
	estado_actual   = Estado.STOPPED
	print("VEHICULO_DETENIDO | stop: ", stop_destino.name if stop_destino else "null",
		" | progress_actual: ", snappedf(progress_actual, 0.0001),
		" | progress_objetivo: ", snappedf(progress_objetivo, 0.0001))

# ---------------------------------------------------------------------------
# Lógica por estado
# ---------------------------------------------------------------------------

func _estado_stopped() -> void:
	pass  # Inmóvil. Solo solicitar_destino() puede sacarlo de aquí.

func _estado_accelerating(delta: float) -> void:
	var distancia_recorrida: float = abs(progress_actual - progress_inicio_aceleracion)
	var t: float = clampf(distancia_recorrida / distancia_total_aceleracion, 0.0, 1.0)
	factor = curva_velocidad.sample(t)
	var dist_antes: float = (transition_salida.progress - progress_actual) * direccion
	progress_actual += velocidad_crucero * factor * direccion * delta
	var dist_despues: float = (transition_salida.progress - progress_actual) * direccion

	if dist_antes > 0.0 and dist_despues <= 0.0:
		progress_actual = transition_salida.progress
		_entrar_cruising()

func _estado_cruising(delta: float) -> void:
	var dist_antes: float = (transition_llegada.progress - progress_actual) * direccion
	progress_actual += velocidad_crucero * direccion * delta
	var dist_despues: float = (transition_llegada.progress - progress_actual) * direccion

	if dist_antes > 0.0 and dist_despues <= 0.0:
		progress_actual = transition_llegada.progress
		_entrar_braking()

func _estado_braking(delta: float) -> void:
	var distancia_restante: float = abs(progress_objetivo - progress_actual)
	var t: float = clampf(distancia_restante / distancia_total_frenado, 0.0, 1.0)
	factor = curva_velocidad.sample(t)
	var velocidad_resultante: float = velocidad_crucero * factor
	var desplazamiento_frame: float = velocidad_resultante * delta
	progress_actual += desplazamiento_frame * direccion

	# Invariante: progress_actual nunca puede quedar más allá de progress_objetivo
	# en la dirección de viaje. Se aplica antes de cualquier cálculo que dependa
	# de progress_actual para que el resto del estado siempre vea un valor válido.
	if direccion == 1:
		progress_actual = minf(progress_actual, progress_objetivo)
	else:
		progress_actual = maxf(progress_actual, progress_objetivo)

	var condicion_salida: bool = abs(progress_actual - progress_objetivo) < epsilon

	if distancia_restante < 0.5:
		print("======================")
		print("ULTIMOS 0.5 METROS")
		print("======================")

	print("BRAKING_FRAME | progress_actual: ", snappedf(progress_actual, 0.0001),
		" | progress_objetivo: ", snappedf(progress_objetivo, 0.0001),
		" | distancia_restante: ", snappedf(distancia_restante, 0.0001),
		" | distancia_total_frenado: ", snappedf(distancia_total_frenado, 0.0001),
		" | t: ", snappedf(t, 0.0001),
		" | factor: ", snappedf(factor, 0.0001),
		" | velocidad_resultante: ", snappedf(velocidad_resultante, 0.0001),
		" | desplazamiento_frame: ", snappedf(desplazamiento_frame, 0.0001),
		" | epsilon: ", epsilon,
		" | condicion_salida: ", condicion_salida)

	if condicion_salida:
		_entrar_stopped()
