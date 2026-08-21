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
# TramoMovimiento / PlanDeViaje — estructuras internas del sistema híbrido.
#
# NOTA (Commit 1 del plan de implementación): estas clases se declaran acá
# como andamiaje. Todavía NO son leídas ni escritas por ninguna función del
# vehículo. _entrar_accelerating(), _entrar_braking(), _estado_accelerating(),
# _estado_cruising() y _estado_braking() siguen operando exactamente igual
# que antes de este commit, sobre _transition_salida / _transition_llegada /
# progress_inicio_aceleracion / distancia_total_aceleracion /
# distancia_total_frenado. Este commit no cambia ningún comportamiento
# observable del vehículo.
#
# StopPoint sigue siendo el destino real.
# TransitionPoint sigue siendo el marcador geométrico real.
# TramoMovimiento es la fase ejecutable: su fin (progress_fin) es un valor
# propio calculado una vez al construir el tramo, no una lectura en vivo de
# un nodo. Los TransitionPoint/StopPoint reales sirven de insumo para
# calcular ese valor, pero dejan de ser la fuente que el movimiento consulta
# cuadro a cuadro.
# PlanDeViaje agrupa la secuencia de tramos que llevan hasta un StopPoint
# real.
# ---------------------------------------------------------------------------

## Origen de un TramoMovimiento. Uso exclusivamente informativo (debug /
## trazabilidad) — ninguna decisión de comportamiento depende de este valor.
enum OrigenTramo {
	VIAJE_NORMAL,          # Construido por _planificar_desde_stop() desde STOPPED.
	RETARGET_MISMA_DIR,    # Construido por _retarget() sin cambio de dirección.
	FRENADO_INVERSION,     # Construido al detectar retarget con dirección opuesta.
	LLEGADA_CORTA,         # Construido cuando el destino cae dentro de una zona
							# StopPoint-TransitionPoint corta (ver escenario L).
}

## Representa una única fase de movimiento con límites propios en progress,
## independientes de si esos límites provienen de un nodo real o de un punto
## arbitrario del Path3D (como el punto donde el vehículo frena al invertir).
class TramoMovimiento extends RefCounted:
	enum Tipo {
		ACELERACION,
		CRUCERO,
		FRENADO,
		FRENADO_INVERSION,
		LLEGADA_CORTA,
	}

	var tipo: Tipo
	var progress_inicio: float = 0.0
	var progress_fin: float = 0.0
	var direccion: int = 1

	var factor_inicio: float = 0.0
	var factor_fin: float = 0.0

	# Distancias de referencia para el cálculo de factor_permitido (ver
	# Commit 4 del plan: fórmula de distancia insuficiente). El estado no
	# debe adivinar estos denominadores: el planner los escribe acá al
	# construir el tramo.
	var distancia_aceleracion_ref: float = 0.0
	var distancia_frenado_ref: float = 0.0

	var destino_final: StopPoint = null
	var origen: OrigenTramo = OrigenTramo.VIAJE_NORMAL

## Agrupa la secuencia de TramoMovimiento que llevan hasta un StopPoint real.
class PlanDeViaje extends RefCounted:
	var destino_final: StopPoint = null
	var tramos: Array[TramoMovimiento] = []
	var indice_actual: int = 0

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

# Commit 2 del plan de implementación del híbrido: _plan_actual se construye
# y se guarda en paralelo al viaje normal, pero todavía NO es leída por
# _estado_accelerating() / _estado_cruising() / _estado_braking(). Esas
# funciones siguen usando _transition_salida / _transition_llegada /
# progress_inicio_aceleracion / distancia_total_aceleracion /
# distancia_total_frenado exactamente igual que antes de este commit. Este
# campo existe para poder verificar, antes del Commit 3, que el planner
# calcula los mismos números que el sistema viejo.
var _plan_actual: PlanDeViaje = null

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

	# Commit 2 del híbrido: se construye el PlanDeViaje en paralelo, con los
	# mismos nodos ya validados arriba. Todavía no lo usa nadie para mover
	# el vehículo — ver nota en la declaración de _plan_actual.
	_plan_actual = _construir_plan_normal(
		nuevo_stop, nueva_direccion, nueva_transition_salida, nueva_transition_llegada
	)

	_entrar_accelerating()

# ---------------------------------------------------------------------------
# TravelPlanner — construcción de PlanDeViaje (Commit 2 del híbrido)
#
# _construir_plan_normal() arma los tres tramos de un viaje STOPPED → STOPPED
# (ACELERACION, CRUCERO, FRENADO) a partir de los mismos StopPoint/
# TransitionPoint que ya calculó y validó _planificar_desde_stop(). No
# recalcula ni revalida nada por su cuenta: recibe los nodos ya resueltos
# para no duplicar lógica de selección/validación.
#
# progress_fin de cada tramo es el valor que, a partir del Commit 3, va a
# reemplazar la lectura en vivo de _transition_salida.progress /
# _transition_llegada.progress / _stop_destino.progress dentro de los
# _estado_*(). Acá todavía es solo un dato calculado y guardado, sin
# consumidor.
# ---------------------------------------------------------------------------

func _construir_plan_normal(
	destino: StopPoint,
	direccion: int,
	transition_salida: TransitionPoint,
	transition_llegada: TransitionPoint
) -> PlanDeViaje:
	var plan := PlanDeViaje.new()
	plan.destino_final = destino
	plan.indice_actual = 0

	var progress_origen: float = _progress_actual

	var tramo_aceleracion := TramoMovimiento.new()
	tramo_aceleracion.tipo = TramoMovimiento.Tipo.ACELERACION
	tramo_aceleracion.progress_inicio = progress_origen
	tramo_aceleracion.progress_fin = transition_salida.progress
	tramo_aceleracion.direccion = direccion
	tramo_aceleracion.factor_inicio = 0.0
	tramo_aceleracion.factor_fin = 1.0
	tramo_aceleracion.distancia_aceleracion_ref = abs(transition_salida.progress - progress_origen)
	tramo_aceleracion.distancia_frenado_ref = 0.0
	tramo_aceleracion.destino_final = destino
	tramo_aceleracion.origen = OrigenTramo.VIAJE_NORMAL

	var tramo_crucero := TramoMovimiento.new()
	tramo_crucero.tipo = TramoMovimiento.Tipo.CRUCERO
	tramo_crucero.progress_inicio = transition_salida.progress
	tramo_crucero.progress_fin = transition_llegada.progress
	tramo_crucero.direccion = direccion
	tramo_crucero.factor_inicio = 1.0
	tramo_crucero.factor_fin = 1.0
	tramo_crucero.distancia_aceleracion_ref = 0.0
	tramo_crucero.distancia_frenado_ref = 0.0
	tramo_crucero.destino_final = destino
	tramo_crucero.origen = OrigenTramo.VIAJE_NORMAL

	var tramo_frenado := TramoMovimiento.new()
	tramo_frenado.tipo = TramoMovimiento.Tipo.FRENADO
	tramo_frenado.progress_inicio = transition_llegada.progress
	tramo_frenado.progress_fin = destino.progress
	tramo_frenado.direccion = direccion
	tramo_frenado.factor_inicio = 1.0
	tramo_frenado.factor_fin = 0.0
	tramo_frenado.distancia_aceleracion_ref = 0.0
	tramo_frenado.distancia_frenado_ref = abs(destino.progress - transition_llegada.progress)
	tramo_frenado.destino_final = destino
	tramo_frenado.origen = OrigenTramo.VIAJE_NORMAL

	plan.tramos = [tramo_aceleracion, tramo_crucero, tramo_frenado]
	return plan

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

	# Corrección al Commit 3 del híbrido: _plan_actual pertenece al viaje que
	# estaba en curso ANTES de este retarget. Si se deja como está, un
	# _plan_actual con un tramo del mismo tipo (por ejemplo FRENADO) que el
	# que corresponde ahora puede pasar la guarda de tipo en _entrar_braking()
	# / _entrar_accelerating() por pura coincidencia, y el sistema termina
	# leyendo progress_fin de un stop viejo en vez del destino real de este
	# retarget (bug confirmado con log real: indice_actual quedaba pegado en
	# el último tramo de un plan viejo tras varios retargets sucesivos).
	#
	# Se invalida acá, después de confirmar que el destino cambia de verdad
	# (ya pasamos la guarda de redundancia al principio de la función) y
	# antes de decidir el estado resultante. _entrar_accelerating() /
	# _entrar_braking() / _entrar_cruising() ya saben reconstruir un tramo
	# de reemplazo cuando _plan_actual es null (fallback agregado en el
	# Commit 3). Esto NO reconstruye un PlanDeViaje real para el retarget —
	# eso es trabajo del Commit 6. Solo evita que un plan viejo contamine
	# el viaje nuevo.
	_plan_actual = null

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

	# Commit 3 del híbrido: distancia_total_aceleracion se lee del tramo de
	# ACELERACION en vez de recalcularse en vivo desde _transition_salida.
	# progress_inicio_aceleracion se sigue fijando acá, en el instante de
	# entrar al estado (no en el instante en que se construyó el plan),
	# tal como hacía el sistema antes de este commit.
	#
	# _retarget() (sin tocar en este commit) todavía no actualiza
	# _plan_actual, así que acá no se puede asumir que _plan_actual está
	# sincronizado con este viaje. Si no lo está, se reconstruye al vuelo
	# un tramo de ACELERACION equivalente usando las mismas variables que
	# ya existían antes del híbrido (_transition_salida), preservando
	# exactamente el mismo resultado numérico que el sistema tenía.
	#
	# AVISO para el Commit 5 (inversión) y el Commit 6 (retarget completo):
	# cuando _retarget() empiece a mantener _plan_actual actualizado, este
	# fallback deja de ser necesario para esos caminos, pero conviene
	# dejarlo como resguardo en vez de asumir sincronización perfecta.
	progress_inicio_aceleracion = _progress_actual

	if _plan_actual == null or _plan_actual.indice_actual >= _plan_actual.tramos.size() \
			or _plan_actual.tramos[_plan_actual.indice_actual].tipo != TramoMovimiento.Tipo.ACELERACION:
		var tramo_fallback := TramoMovimiento.new()
		tramo_fallback.tipo = TramoMovimiento.Tipo.ACELERACION
		tramo_fallback.progress_inicio = progress_inicio_aceleracion
		tramo_fallback.progress_fin = _transition_salida.progress
		tramo_fallback.direccion = _direccion
		# Corrección al Commit 4: el fallback debe llenar
		# distancia_aceleracion_ref igual que _construir_plan_normal(), o
		# _calcular_factor_permitido() trata este tramo como "sin
		# restricción de salida" (limite_salida=1.0) en vez de aplicar la
		# curva real (bug confirmado con log: divergencia en BRAKING por
		# el mismo motivo, distancia_frenado_ref sin asignar).
		tramo_fallback.distancia_aceleracion_ref = abs(_transition_salida.progress - progress_inicio_aceleracion)
		tramo_fallback.distancia_frenado_ref = 0.0
		tramo_fallback.destino_final = _stop_destino
		tramo_fallback.origen = OrigenTramo.RETARGET_MISMA_DIR

		var plan_fallback := PlanDeViaje.new()
		plan_fallback.destino_final = _stop_destino
		plan_fallback.tramos = [tramo_fallback]
		plan_fallback.indice_actual = 0
		_plan_actual = plan_fallback

	var tramo_aceleracion: TramoMovimiento = _plan_actual.tramos[_plan_actual.indice_actual]
	distancia_total_aceleracion = abs(tramo_aceleracion.progress_fin - progress_inicio_aceleracion)
	assert(distancia_total_aceleracion > epsilon,
		"GuidedVehicle: distancia_total_aceleracion <= epsilon. Revisá la posición del TransitionPoint de salida.")
	_estado_actual = Estado.ACCELERATING

func _entrar_cruising() -> void:
	_factor        = 1.0
	_estado_actual = Estado.CRUISING

	# Corrección al Commit 3 del híbrido: _entrar_cruising() solo avanzaba
	# el índice de un _plan_actual que ya existiera — no tenía fallback
	# propio como _entrar_accelerating()/_entrar_braking(). Con la
	# invalidación de _plan_actual agregada en _retarget(), esto dejaba
	# _plan_actual en null al entrar acá, y _estado_cruising() explotaba en
	# el primer cuadro (Invalid access to property 'tramos' on Nil).
	#
	# OJO: acá el chequeo correcto es sobre el PRÓXIMO tramo del plan, no
	# sobre el tramo actual. En el viaje normal, cuando _entrar_cruising()
	# se llama desde _estado_accelerating(), _plan_actual.indice_actual
	# sigue apuntando al tramo ACELERACION recién completado — el tramo
	# CRUCERO es el siguiente en la lista, todavía no el actual. Comparar
	# contra el tramo actual (en vez del próximo) disparaba el fallback
	# también en el viaje normal, rompiendo el avance de índice que ya
	# funcionaba.
	var hay_proximo_cruero: bool = _plan_actual != null \
		and _plan_actual.indice_actual + 1 < _plan_actual.tramos.size() \
		and _plan_actual.tramos[_plan_actual.indice_actual + 1].tipo == TramoMovimiento.Tipo.CRUCERO

	if hay_proximo_cruero:
		# Viaje normal: el tramo CRUCERO es el siguiente en el plan ya
		# construido por _construir_plan_normal(). Avanzamos el índice.
		_plan_actual.indice_actual += 1
	else:
		# _plan_actual es null (retarget lo invalidó), o no tiene un tramo
		# CRUCERO esperando en la posición siguiente (plan de un solo tramo
		# de un fallback anterior, por ejemplo). Se reconstruye un tramo
		# CRUCERO mínimo usando _transition_llegada.progress — la misma
		# fuente que el sistema ya usaba antes del híbrido.
		var tramo_fallback := TramoMovimiento.new()
		tramo_fallback.tipo = TramoMovimiento.Tipo.CRUCERO
		tramo_fallback.progress_inicio = _progress_actual
		tramo_fallback.progress_fin = _transition_llegada.progress
		tramo_fallback.direccion = _direccion
		tramo_fallback.destino_final = _stop_destino
		tramo_fallback.origen = OrigenTramo.RETARGET_MISMA_DIR

		var plan_fallback := PlanDeViaje.new()
		plan_fallback.destino_final = _stop_destino
		plan_fallback.tramos = [tramo_fallback]
		plan_fallback.indice_actual = 0
		_plan_actual = plan_fallback

func _entrar_braking() -> void:
	assert(_transition_llegada != null,
		"GuidedVehicle: _transition_llegada es null al entrar en BRAKING.")

	# Commit 3 del híbrido: distancia_total_frenado se lee del tramo de
	# FRENADO en vez de recalcularse en vivo desde _progress_objetivo.
	# _calcular_inicio_frenado() no se toca: sigue siendo el criterio
	# geométrico que decide desde dónde arranca el frenado este viaje.
	#
	# Corrección al Commit 3 (mismo motivo que en _entrar_cruising()): el
	# chequeo correcto es sobre el PRÓXIMO tramo del plan, no sobre el
	# tramo actual. En el viaje normal, cuando _entrar_braking() se llama
	# desde _estado_cruising(), _plan_actual.indice_actual todavía apunta
	# al tramo CRUCERO recién completado — el tramo FRENADO es el
	# siguiente, todavía no el actual.
	var inicio_frenado: float = _calcular_inicio_frenado()

	var hay_proximo_frenado: bool = _plan_actual != null \
		and _plan_actual.indice_actual + 1 < _plan_actual.tramos.size() \
		and _plan_actual.tramos[_plan_actual.indice_actual + 1].tipo == TramoMovimiento.Tipo.FRENADO

	if hay_proximo_frenado:
		# Viaje normal: el tramo FRENADO es el siguiente en el plan ya
		# construido por _construir_plan_normal(). Avanzamos el índice.
		_plan_actual.indice_actual += 1
	else:
		# _plan_actual es null (retarget lo invalidó, o venimos directo de
		# BRAKING→BRAKING vía retarget sin pasar por CRUISING), o no tiene
		# un tramo FRENADO esperando en la posición siguiente. Se
		# reconstruye un tramo FRENADO mínimo contra _progress_objetivo —
		# la misma fuente que el sistema ya usaba antes del híbrido.
		var tramo_fallback := TramoMovimiento.new()
		tramo_fallback.tipo = TramoMovimiento.Tipo.FRENADO
		tramo_fallback.progress_inicio = inicio_frenado
		tramo_fallback.progress_fin = _progress_objetivo
		tramo_fallback.direccion = _direccion
		# Corrección al Commit 4 (bug confirmado con log real): el fallback
		# debe llenar distancia_frenado_ref igual que
		# _construir_plan_normal(), o _calcular_factor_permitido() trata
		# este tramo como "sin restricción de llegada" (limite_llegada=1.0)
		# en vez de aplicar la curva real. En el log, esto se veía como
		# _factor bajando por la curva de frenado mientras
		# factor_permitido se quedaba fijo en 1.0 — divergencia real, no
		# un falso positivo del diagnóstico.
		tramo_fallback.distancia_aceleracion_ref = 0.0
		tramo_fallback.distancia_frenado_ref = abs(_progress_objetivo - inicio_frenado)
		tramo_fallback.destino_final = _stop_destino
		tramo_fallback.origen = OrigenTramo.RETARGET_MISMA_DIR

		var plan_fallback := PlanDeViaje.new()
		plan_fallback.destino_final = _stop_destino
		plan_fallback.tramos = [tramo_fallback]
		plan_fallback.indice_actual = 0
		_plan_actual = plan_fallback

	var tramo_frenado: TramoMovimiento = _plan_actual.tramos[_plan_actual.indice_actual]
	distancia_total_frenado = abs(tramo_frenado.progress_fin - inicio_frenado)
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

# ---------------------------------------------------------------------------
# Commit 4 del híbrido: factor_permitido — fórmula de distancia insuficiente.
#
# _calcular_factor_permitido() no reemplaza el cálculo de _factor que ya
# hacen _estado_accelerating() / _estado_braking() — es un LÍMITE adicional,
# pensado para tramos donde aceleración y frenado se solapan en el mismo
# espacio (tramos cortos/compuestos, todavía no construidos por ningún
# planner hasta el Commit 5/6). El resultado de esta función debe usarse
# como cota superior de _factor, nunca como el valor directo.
#
# Un TramoMovimiento del viaje normal solo trae UNA de las dos referencias
# activa (ACELERACION trae distancia_aceleracion_ref, FRENADO trae
# distancia_frenado_ref; CRUCERO no trae ninguna). Cuando una referencia es
# <= epsilon, ese lado no aplica ninguna restricción — se trata como
# "límite 1.0", no como error ni como división por cero.
#
# Verificado con logs reales en dos rondas: primera ronda encontró 455
# divergencias, todas en BRAKING, causadas por los tramos de fallback
# (Commit 3) que no llenaban distancia_aceleracion_ref/
# distancia_frenado_ref — corregido en ambos fallbacks. Segunda ronda:
# 0 divergencias en accel/cruise/braking, tanto en viaje normal como en
# retarget con fallback. Con eso confirmado, factor_permitido ya está
# conectado como límite real (min() sobre _factor) en
# _estado_accelerating() y _estado_braking(). En CRUCERO no hace falta
# aplicarlo — _factor ya vale 1.0 y ese estado no lo recalcula por frame.
# En tramos largos (viaje normal) el límite es matemáticamente un no-op.
# Solo limita de verdad en tramos cortos/compuestos, todavía no
# construidos por ningún planner hasta el Commit 5/6.
# ---------------------------------------------------------------------------

func _calcular_factor_permitido(tramo: TramoMovimiento, progress_actual: float) -> float:
	var limite_salida: float = 1.0
	if tramo.distancia_aceleracion_ref > epsilon:
		var dist_desde_inicio: float = abs(progress_actual - tramo.progress_inicio)
		var t_salida: float = clampf(dist_desde_inicio / tramo.distancia_aceleracion_ref, 0.0, 1.0)
		limite_salida = curva_velocidad.sample(t_salida)

	var limite_llegada: float = 1.0
	if tramo.distancia_frenado_ref > epsilon:
		var dist_hasta_fin: float = abs(tramo.progress_fin - progress_actual)
		var t_llegada: float = clampf(dist_hasta_fin / tramo.distancia_frenado_ref, 0.0, 1.0)
		limite_llegada = curva_velocidad.sample(t_llegada)

	return minf(limite_salida, limite_llegada)

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
	# Commit 3 del híbrido: progress_fin_tramo reemplaza la lectura en vivo
	# de _transition_salida.progress. La aritmética que sigue (dist_antes,
	# dist_despues, distancia_total_intentada, fraccion_usada,
	# delta_sobrante, el encadenamiento con LIMITE_ENCADENAMIENTO_ESTADO) es
	# exactamente la misma que existía antes de este commit — solo cambia
	# de dónde sale el número contra el que se compara.
	var tramo: TramoMovimiento = _plan_actual.tramos[_plan_actual.indice_actual]
	var progress_fin_tramo: float = tramo.progress_fin

	var distancia_recorrida: float = abs(_progress_actual - progress_inicio_aceleracion)
	var t: float = clampf(distancia_recorrida / distancia_total_aceleracion, 0.0, 1.0)
	_factor = curva_velocidad.sample(t)

	# Commit 4 del híbrido: factor_permitido aplicado como límite superior
	# real. Verificado con logs (viaje normal: 0 divergencias en accel/
	# cruise/braking; retarget con fallback: 455 divergencias detectadas y
	# corregidas — los fallbacks no llenaban distancia_aceleracion_ref/
	# distancia_frenado_ref; segunda ronda de logs: 0 divergencias). En
	# tramos largos (viaje normal) esto es un no-op matemático. Solo limita
	# de verdad en tramos cortos/compuestos (todavía no construidos hasta
	# el Commit 5/6).
	_factor = minf(_factor, _calcular_factor_permitido(tramo, _progress_actual))

	var progress_inicial_frame: float = _progress_actual
	var dist_antes: float = (progress_fin_tramo - _progress_actual) * _direccion
	_progress_actual += velocidad_crucero * _factor * _direccion * delta
	var dist_despues: float = (progress_fin_tramo - _progress_actual) * _direccion

	if dist_antes > 0.0 and dist_despues <= 0.0:
		var distancia_total_intentada: float = abs(_progress_actual - progress_inicial_frame)
		var delta_sobrante: float = 0.0

		if distancia_total_intentada > epsilon:
			var distancia_hasta_transition: float = abs(progress_fin_tramo - progress_inicial_frame)
			var fraccion_usada: float = clampf(distancia_hasta_transition / distancia_total_intentada, 0.0, 1.0)
			delta_sobrante = delta * (1.0 - fraccion_usada)

		_progress_actual = progress_fin_tramo
		_entrar_cruising()

		if delta_sobrante > epsilon:
			if profundidad + 1 <= LIMITE_ENCADENAMIENTO_ESTADO:
				_estado_cruising(delta_sobrante, profundidad + 1)
			else:
				push_error("GuidedVehicle: se alcanzó el límite de encadenamiento de estados (%d) en el mismo frame. Delta sobrante descartado." % LIMITE_ENCADENAMIENTO_ESTADO)

func _estado_cruising(delta: float, profundidad: int = 0) -> void:
	# Commit 3 del híbrido: progress_fin_tramo reemplaza la lectura en vivo
	# de _transition_llegada.progress. Misma nota que en
	# _estado_accelerating(): la aritmética no cambia, solo la fuente.
	var tramo: TramoMovimiento = _plan_actual.tramos[_plan_actual.indice_actual]
	var progress_fin_tramo: float = tramo.progress_fin

	# Commit 4 del híbrido: en CRUCERO no hace falta aplicar
	# factor_permitido — _factor ya vale 1.0 (fijado por _entrar_cruising())
	# y este estado no lo recalcula por frame, mueve _progress_actual con
	# velocidad_crucero directo. Verificado con logs: factor_permitido da
	# 1.0 también acá (ambas distancias de referencia en 0 para CRUCERO),
	# así que no hay nada que limitar.

	var progress_inicial_frame: float = _progress_actual
	var dist_antes: float = (progress_fin_tramo - _progress_actual) * _direccion
	_progress_actual += velocidad_crucero * _direccion * delta
	var dist_despues: float = (progress_fin_tramo - _progress_actual) * _direccion

	if dist_antes > 0.0 and dist_despues <= 0.0:
		var distancia_total_intentada: float = abs(_progress_actual - progress_inicial_frame)
		var delta_sobrante: float = 0.0

		if distancia_total_intentada > epsilon:
			var distancia_hasta_transition: float = abs(progress_fin_tramo - progress_inicial_frame)
			var fraccion_usada: float = clampf(distancia_hasta_transition / distancia_total_intentada, 0.0, 1.0)
			delta_sobrante = delta * (1.0 - fraccion_usada)

		_progress_actual = progress_fin_tramo
		_entrar_braking()

		if delta_sobrante > epsilon:
			if profundidad + 1 <= LIMITE_ENCADENAMIENTO_ESTADO:
				_estado_braking(delta_sobrante, profundidad + 1)
			else:
				push_error("GuidedVehicle: se alcanzó el límite de encadenamiento de estados (%d) en el mismo frame. Delta sobrante descartado." % LIMITE_ENCADENAMIENTO_ESTADO)

func _estado_braking(delta: float, _profundidad: int = 0) -> void:
	# Commit 3 del híbrido: progress_fin_tramo reemplaza la lectura en vivo
	# de _progress_objetivo. El invariante de clamp que sigue (nunca superar
	# el objetivo en la dirección de viaje) se mantiene igual, ahora
	# aplicado contra el mismo valor que ya se usa para distancia_restante.
	var tramo: TramoMovimiento = _plan_actual.tramos[_plan_actual.indice_actual]
	var progress_fin_tramo: float = tramo.progress_fin

	var distancia_restante: float = abs(progress_fin_tramo - _progress_actual)
	var t: float = clampf(distancia_restante / distancia_total_frenado, 0.0, 1.0)
	_factor = curva_velocidad.sample(t)

	# Commit 4 del híbrido: factor_permitido aplicado como límite superior
	# real. Verificado con logs (primera ronda: 455 divergencias por
	# fallback sin distancia_frenado_ref asignada, corregido; segunda
	# ronda: 0 divergencias). En tramos largos (viaje normal) es un no-op
	# matemático. Solo limita de verdad en tramos cortos/compuestos
	# (todavía no construidos hasta el Commit 5/6).
	_factor = minf(_factor, _calcular_factor_permitido(tramo, _progress_actual))

	_progress_actual += velocidad_crucero * _factor * _direccion * delta

	# Invariante: _progress_actual nunca puede quedar más allá de progress_fin_tramo
	# en la dirección de viaje. Se aplica antes de cualquier cálculo que dependa
	# de _progress_actual para que el resto del estado siempre vea un valor válido.
	if _direccion == 1:
		_progress_actual = minf(_progress_actual, progress_fin_tramo)
	else:
		_progress_actual = maxf(_progress_actual, progress_fin_tramo)

	if abs(_progress_actual - progress_fin_tramo) < epsilon:
		_entrar_stopped()
