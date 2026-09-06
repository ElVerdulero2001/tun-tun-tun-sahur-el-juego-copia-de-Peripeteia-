class_name TraversalSegment
extends StaticBody3D

## Contrato V2 de segmento guiado — componente de mundo, independiente del
## jugador y del input (doc de arquitectura V0.3, sección 10). Pensado
## inicialmente para escaleras; el enum Type deja lugar a cuerdas/cables a
## futuro sin cambiar el contrato.
##
## El recorrido no usa el eje Y directamente — se mueve sobre "progress":
##   0.0 = inicio (start_marker)
##   1.0 = final  (end_marker)
## La posición mundial se reconstruye interpolando entre los dos markers.
##
## Referencias EXPLÍCITAS, nada por nombre de nodo ni por grupo: start_marker,
## end_marker, neighbour_up y neighbour_down se asignan en el Inspector.
## TraversalDetector reconoce un segmento haciendo un cast directo del
## collider físico a TraversalSegment (`resultado.collider as TraversalSegment`)
## — el script vive en el mismo StaticBody3D que la forma de colisión, así
## que no hace falta grupo ni búsqueda por ancestros.
##
## Fase 6 agrega LEDGE: el mismo contrato (start/end/neighbours/progreso)
## sirve para el recorrido lateral (shimmy) de un borde, no solo para
## escaleras — un borde con TraversalSegment asociado permite desplazarse a
## lo largo de él en HANGING; sin uno, el borde funciona exactamente como
## antes (sin shimmy). TraversalDetector distingue el tipo para no confundir
## un segmento de borde con uno de escalera en sus respectivas queries.

enum Type { LADDER, ROPE, CABLE, CHAIN, LEDGE }

@export var segment_type: Type = Type.LADDER

@export var start_marker: Marker3D
@export var end_marker: Marker3D

## Vecinos para stacking: si el jugador llega a progress >= 1.0 y existe
## neighbour_up, el Controller (Fase 6) puede transicionar a ese segmento.
## Idem neighbour_down en progress <= 0.0. Referencia directa tipada, no
## NodePath ni búsqueda: un valor no nulo YA es otro TraversalSegment válido
## por construcción del sistema de tipos.
@export var neighbour_up: TraversalSegment
@export var neighbour_down: TraversalSegment

## Multiplicador de velocidad para ESTE segmento en particular. La velocidad
## base la calculará el Controller (Fase 6) a partir de get_length() real,
## no de una constante mágica — esto ajusta el feel de un segmento puntual
## (ej. "esta escalera es más lenta"), no reemplaza ese cálculo.
@export var move_speed_multiplier: float = 1.0

const _LONGITUD_MINIMA := 0.01


func _ready() -> void:
	_reportar_problemas()


## Contrato mínimo para que un consumidor (TraversalDetector, tests) sepa si
## este segmento se puede usar sin tener que releer cada condición suelta.
func is_valid() -> bool:
	return (
		start_marker != null
		and end_marker != null
		and get_length() > _LONGITUD_MINIMA
		and neighbour_up != self
		and neighbour_down != self
	)


## Posición mundial para un progress dado (0.0 a 1.0). Interpolación lineal
## entre start_marker y end_marker. Fuera de [0,1] extrapola — queda a
## criterio del consumidor si eso es válido para su caso.
func get_position_at(progress: float) -> Vector3:
	if start_marker == null or end_marker == null:
		return global_position
	return start_marker.global_position.lerp(end_marker.global_position, progress)


## Dirección de avance en este punto del segmento. Para segmentos lineales
## (escaleras) es siempre la misma; a futuro, para cuerdas/cables curvas, se
## derivaría de progress.
func get_direction_at(_progress: float) -> Vector3:
	if start_marker == null or end_marker == null:
		return Vector3.UP
	var vector := end_marker.global_position - start_marker.global_position
	if vector.length() < _LONGITUD_MINIMA:
		return Vector3.UP
	return vector.normalized()


## Longitud real del segmento en unidades de mundo. La velocidad de
## recorrido futura se basa en esto, no en una constante fija.
func get_length() -> float:
	if start_marker == null or end_marker == null:
		return 0.0
	return start_marker.global_position.distance_to(end_marker.global_position)


func get_neighbour_up() -> TraversalSegment:
	return neighbour_up


func get_neighbour_down() -> TraversalSegment:
	return neighbour_down


## Progreso CRUDO (no clampeado a [0,1]) del punto dado, proyectado sobre la
## línea del segmento. Deliberadamente sin clampear: quien llama decide si
## un progreso levemente fuera de rango todavía es aceptable (p. ej.
## TraversalDetector permite una tolerancia de aproximación antes de
## clampear) o si corresponde clampear de una (p. ej. un desplazamiento
## guiado que ya cruzó a un vecino, ver advance_progress()).
func get_progress_along(point: Vector3) -> float:
	if start_marker == null or end_marker == null:
		return 0.0
	var vector_segmento := end_marker.global_position - start_marker.global_position
	var longitud := vector_segmento.length()
	if longitud < _LONGITUD_MINIMA:
		return 0.0
	var direccion := vector_segmento / longitud
	var hacia_punto := point - start_marker.global_position
	return hacia_punto.dot(direccion) / longitud


## Avanza progreso a lo largo de un segmento resolviendo el cruce a un
## vecino explícito (Fase 6, sección 10): shimmy (borde, dentro de HANGING)
## y escalera (LADDER) comparten esta mecánica, así que vive acá una sola
## vez en vez de duplicarse en TraversalController para cada caso. Función
## pura: no toca la escena ni ningún estado — solo combina los datos
## tipados que ya expone el contrato (get_length(), is_valid(),
## get_neighbour_up/down()).
##
## Si el desplazamiento excede el extremo y hay un vecino válido ahí, la
## distancia "sobrante" (medida en unidades reales, no en progreso — los
## segmentos pueden tener longitudes distintas) se traslada al comienzo
## correspondiente del vecino, para que el movimiento se sienta continuo en
## vez de frenar en seco en el borde y arrancar de cero el tick siguiente.
## Sin vecino, el progreso queda clampeado a [0,1] — el extremo del
## segmento es un límite real, no un error.
##
## No resuelve más de un cruce de vecino por llamada: a velocidades y
## framerates razonables un solo tick no debería avanzar más de la longitud
## de un segmento entero, así que esta simplificación es deliberada, no un
## descuido.
##
## El vecino solo se cruza si además es del MISMO segment_type que el
## segmento de origen (ver _es_vecino_cruzable()) — un cruce entre tipos
## distintos (p. ej. una LADDER enlazada por error a un LEDGE de shimmy, o
## viceversa) no tiene sentido físico (shimmy y escalera avanzan por ejes
## conceptualmente distintos, y una CHAIN o ROPE futuras tampoco deberían
## mezclarse con ninguna de las dos) y sería un error de configuración en
## el Inspector, no un caso de uso real. Sin un vecino cruzable, el
## progreso simplemente clampea en el extremo actual, exactamente igual que
## sin vecino — nunca fuerza una salida ni un cambio de estado: eso es
## responsabilidad de quien llama, no de esta función pura.
static func advance_progress(from_segment: TraversalSegment, from_progress: float, delta_progress: float) -> SegmentProgress:
	if from_segment == null:
		return SegmentProgress.new(null, from_progress)

	var segmento := from_segment
	var progreso := from_progress + delta_progress

	if progreso > 1.0:
		var vecino := segmento.get_neighbour_up()
		if _es_vecino_cruzable(segmento, vecino):
			var distancia_sobrante := (progreso - 1.0) * segmento.get_length()
			segmento = vecino
			progreso = distancia_sobrante / segmento.get_length()
		else:
			progreso = 1.0
	elif progreso < 0.0:
		var vecino := segmento.get_neighbour_down()
		if _es_vecino_cruzable(segmento, vecino):
			var distancia_sobrante := -progreso * segmento.get_length()
			segmento = vecino
			progreso = 1.0 - (distancia_sobrante / segmento.get_length())
		else:
			progreso = 0.0

	return SegmentProgress.new(segmento, clampf(progreso, 0.0, 1.0))


## Un vecino es cruzable si es válido (contrato ya existente) Y del mismo
## segment_type que el segmento de origen. Centralizado acá (no en
## TraversalController) para que CUALQUIER consumidor futuro de
## advance_progress() — no solo shimmy y escalera — herede la misma regla
## sin tener que repetirla.
static func _es_vecino_cruzable(origen: TraversalSegment, vecino: TraversalSegment) -> bool:
	return vecino != null and vecino.is_valid() and vecino.segment_type == origen.segment_type


func _reportar_problemas() -> void:
	if start_marker == null:
		push_error("TraversalSegment '%s': falta start_marker." % name)
	if end_marker == null:
		push_error("TraversalSegment '%s': falta end_marker." % name)
	if start_marker != null and end_marker != null and get_length() <= _LONGITUD_MINIMA:
		push_error("TraversalSegment '%s': longitud nula o casi nula (%.4f)." % [name, get_length()])
	if neighbour_up == self:
		push_error("TraversalSegment '%s': neighbour_up apunta a si mismo." % name)
	if neighbour_down == self:
		push_error("TraversalSegment '%s': neighbour_down apunta a si mismo." % name)
	if neighbour_up != null and neighbour_up.neighbour_down != self:
		push_warning("TraversalSegment '%s': neighbour_up no apunta de vuelta con neighbour_down (enlace unidireccional, ¿intencional?)." % name)
	if neighbour_down != null and neighbour_down.neighbour_up != self:
		push_warning("TraversalSegment '%s': neighbour_down no apunta de vuelta con neighbour_up (enlace unidireccional, ¿intencional?)." % name)
