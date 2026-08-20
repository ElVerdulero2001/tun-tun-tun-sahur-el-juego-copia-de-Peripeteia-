extends Node

## [E1E2Test]
## Prueba manual, temporal y removible para validar E1/E2: revalidación de
## _transition_salida cuando un re-target durante ACCELERATING invierte la
## dirección de viaje, antes de haber cruzado la transition de salida.
##
## Cómo funciona: pide un primer destino lejano. Muy poco después —todavía
## en ACCELERATING, antes de cruzar transition_salida— pide un SEGUNDO
## destino en la dirección CONTRARIA. Esto ejercita exactamente el camino
## de código que E1/E2 corrige: _retarget() con _estado_actual == ACCELERATING
## y una nueva_direccion opuesta a la original.
##
## Qué mirar en los logs:
## - Si E1/E2 funciona: no debería aparecer ningún push_error de
##   "_transition_salida" ni comportamiento errático (posición saltando de
##   forma incoherente, o velocidad quedándose en 0 sin motivo). El vehículo
##   debería invertir suavemente y dirigirse hacia el nuevo destino.
## - Si E1/E2 fallara: podrían aparecer errores de Godot no capturados por
##   este script (ej. si _transition_salida quedara apuntando a un punto
##   incoherente y algún cálculo posterior fallara), o el vehículo podría
##   quedarse en un estado visualmente extraño (sin avanzar, oscilando, etc).
##
## Qué NO hace esta prueba:
## - No accede a ninguna variable interna de GuidedVehicle. Solo usa la
##   API pública: solicitar_destino() y get_velocidad_actual().
## - No modifica nada de forma permanente. No hace commits. No toca escenas.
## - No garantiza por sí sola que el segundo pedido llegue exactamente
##   durante ACCELERATING — eso depende de qué tan rápido acelera tu
##   vehículo y de 'segundos_despues_de_arrancar'. Mirá los logs (el campo
##   de velocidad) para confirmar en qué momento se pidió el segundo destino.
## - El primer movimiento puede tardar en aparecer (varios segundos) si algo
##   en tu escena retrasa el arranque del vehículo — este test ya no asume
##   un tiempo fijo, espera a detectar velocidad real antes de contar el
##   margen de 'segundos_despues_de_arrancar'.

const PREFIX := "[E1E2Test]"

# ---------------------------------------------------------------------------
# Referencias a asignar manualmente desde el Inspector
# ---------------------------------------------------------------------------

## El vehículo a probar. Obligatorio.
@export var vehiculo: GuidedVehicle

## Primer destino: tiene que quedar lejos, para darle tiempo al vehículo de
## seguir en ACCELERATING cuando llegue el segundo pedido. Obligatorio.
@export var stop_destino_inicial: StopPoint

## Segundo destino: tiene que estar en la dirección CONTRARIA al primero
## (por ejemplo, si el primero está "adelante" en el Path3D, este debería
## estar "atrás" respecto a la posición de arranque del vehículo).
## Obligatorio.
@export var stop_destino_contrario: StopPoint

## Segundos de espera DESPUÉS de que el vehículo empiece a moverse de verdad
## (velocidad detectada distinta de cero) antes de pedir el re-target.
## Tiene que ser chico, para pescar al vehículo todavía en ACCELERATING —
## mirá el valor de 'progress_inicio_aceleracion' / la duración típica de
## tu curva de aceleración para calibrar esto. Si tu vehículo acelera muy
## rápido, puede que necesites un valor bien chico (0.1-0.3s).
## Ojo: esto ya NO se cuenta desde _ready() — el vehículo puede tardar en
## arrancar a moverse por motivos ajenos a este test (otro sistema que lo
## dispara, timing de inicialización, etc), así que el test ahora espera a
## detectar movimiento real antes de empezar a contar este margen.
@export var segundos_despues_de_arrancar: float = 0.3

# ---------------------------------------------------------------------------
# Estado interno de la prueba
# ---------------------------------------------------------------------------

var _fallo_critico: bool = false
var _tiempo_acumulado: float = 0.0
var _tiempo_desde_arranque: float = 0.0
var _arranque_detectado: bool = false
var _retarget_ya_pedido: bool = false
var _frame_num: int = 0

func _ready() -> void:
	print(PREFIX, " ================================================")
	print(PREFIX, " Iniciando smoke test de E1/E2 (re-target con cambio de")
	print(PREFIX, " dirección durante ACCELERATING)")
	print(PREFIX, " ================================================")

	if not _verificar_referencias():
		_fallo_critico = true
		return

	print(PREFIX, " Referencias OK. Solicitando primer destino: ", stop_destino_inicial.name)
	vehiculo.solicitar_destino(stop_destino_inicial)
	print(PREFIX, " Esperando a que el vehículo empiece a moverse de verdad")
	print(PREFIX, " (puede tardar unos segundos según tu escena). El re-target")
	print(PREFIX, " contrario se va a pedir ", segundos_despues_de_arrancar,
		"s después de detectar el primer movimiento.")

func _verificar_referencias() -> bool:
	var ok := true
	if vehiculo == null:
		push_error(PREFIX + " Falta asignar 'vehiculo' en el Inspector.")
		ok = false
	if stop_destino_inicial == null:
		push_error(PREFIX + " Falta asignar 'stop_destino_inicial' en el Inspector.")
		ok = false
	if stop_destino_contrario == null:
		push_error(PREFIX + " Falta asignar 'stop_destino_contrario' en el Inspector.")
		ok = false
	if ok and (not vehiculo.has_method("solicitar_destino") or not vehiculo.has_method("get_velocidad_actual")):
		push_error(PREFIX + " El vehículo no expone la API pública esperada.")
		ok = false
	return ok

func _physics_process(delta: float) -> void:
	if _fallo_critico:
		return

	_frame_num += 1
	_tiempo_acumulado += delta

	var velocidad: Vector3 = vehiculo.get_velocidad_actual()
	var posicion: Vector3 = vehiculo.global_position

	# Log frame a frame durante toda la prueba: es una ventana corta
	# (pocos segundos una vez que arranca), así que no hace falta filtrar
	# como en pruebas más largas — ver cada frame ayuda a confirmar en qué
	# momento exacto ocurrió el re-target respecto a la aceleración.
	print(PREFIX, " [frame ", _frame_num, ", t=", "%.3f" % _tiempo_acumulado,
		"s] posición: ", posicion, " | velocidad: ", velocidad)

	if not _arranque_detectado:
		if velocidad.length() > 0.001:
			_arranque_detectado = true
			print(PREFIX, " ------------------------------------------------")
			print(PREFIX, " Movimiento real detectado en t=", "%.3f" % _tiempo_acumulado, "s.")
			print(PREFIX, " El re-target se pedirá en ", segundos_despues_de_arrancar, "s más.")
			print(PREFIX, " ------------------------------------------------")
		return

	_tiempo_desde_arranque += delta

	if not _retarget_ya_pedido and _tiempo_desde_arranque >= segundos_despues_de_arrancar:
		_retarget_ya_pedido = true
		print(PREFIX, " ------------------------------------------------")
		print(PREFIX, " Pidiendo destino CONTRARIO: ", stop_destino_contrario.name)
		print(PREFIX, " (velocidad en el momento del pedido: ", velocidad, ")")
		vehiculo.solicitar_destino(stop_destino_contrario)
		print(PREFIX, " solicitar_destino(stop_destino_contrario) retornó sin excepción.")
		print(PREFIX, " Revisá arriba/abajo si apareció algún push_error mencionando")
		print(PREFIX, " '_transition_salida' o 'no pertenece al Path3D'.")
		print(PREFIX, " ------------------------------------------------")

	if _retarget_ya_pedido and _tiempo_desde_arranque > segundos_despues_de_arrancar + 3.0 and not has_meta("_cierre_impreso"):
		set_meta("_cierre_impreso", true)
		print(PREFIX, " ================================================")
		print(PREFIX, " Ventana de observación cerrada.")
		print(PREFIX, " Revisá manualmente:")
		print(PREFIX, " 1) Que NO haya aparecido ningún push_error mencionando")
		print(PREFIX, "    '_transition_salida', 'recalcular' o 'no pertenece al Path3D'")
		print(PREFIX, "    (salvo que sea justamente el caso de _stop_origen_viaje null,")
		print(PREFIX, "    que solo debería pasar si el primer viaje NUNCA arrancó)")
		print(PREFIX, " 2) Que la posición y velocidad muestren al vehículo invirtiendo")
		print(PREFIX, "    de forma coherente (velocidad cambiando de signo, sin saltos")
		print(PREFIX, "    de posición incoherentes con el Path3D).")
		print(PREFIX, " ================================================")
