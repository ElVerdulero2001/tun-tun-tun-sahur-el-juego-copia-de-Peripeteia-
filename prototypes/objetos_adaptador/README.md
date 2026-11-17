# Adaptador local de objetos al actor y al reloj — entrega 10

Experimento separado del laboratorio. Usa sin cambios `ActorInput`, `ActorBody`, `ActorMotor`, `ActorTuning`, `SimClock`, `InvAuthority.eyes` e `InvHoldMotion.target_of` del proyecto. El núcleo físico sigue siendo la GDExtension de mundos Rapier propios; Jolt mueve al actor.

**Alcance:** un actor, una mano y un objeto vinculado, con vecinos dinámicos libres y contexto fijo de cajas centradas. El driver inyecta inputs de prueba durante la captura. No se han conectado los botones de `InvHands`, `NetSync`, el protocolo de inventario, dos manos activas ni el catálogo. No hay transporte ni presentador en este experimento. No equivale a aprobar la condición 4 completa ni a migrar el juego.

## Orden de un tick

1. El proveedor existente crea el `ActorInput` cuantizado del tick. Llama a `adapter.capture(input)` y devuelve ese mismo input al reloj.
2. El `SimClock` real ejecuta `ActorMotor` y presenta el actor.
3. En `tick_finished`, el adaptador lee los ojos del actor ya movido y obtiene el objetivo con `InvHoldMotion.target_of`.
4. Aplica la transición de mano y exactamente un paso nativo con `SimClock.world_dt(tick)`. Guarda los bytes del input, ojos, dt y acción del tick. El objetivo no sale de una pose visual suavizada.

El adaptador debe ser el único que avanza su mundo nativo. Los observadores leen muestras; no llaman `step()` ni mueven los cuerpos. Una discontinuidad de ticks se detecta y detiene esta predicción.

## Uso de la API local

Crear un nodo con `clock_adapter.gd`. `start(clock, actor, tuning, world_factory, uid, epoch, session)` requiere un mundo sellado compatible y el mismo tick inicial que el reloj. La factory debe devolver una instancia nueva con la misma topología/contexto. No añade autoloads ni cambia el reloj o el input del personaje.

El proveedor de inputs de la escena llama `capture(input)` **antes** de devolverlo a `SimClock`. Las acciones son explícitas: `queue_action(tick, id, "grab", anchor)` o `queue_action(tick, id, "release", Vector3.ZERO, impulse)`. Solo caben una transición por tick y dos ticks de cola; un ID repetido con el mismo contenido no ejecuta otra acción, y con contenido distinto se rechaza. Se conservan hasta 256 identidades de acción por sesión; agotar ese límite requiere otra sesión, no reutilizar IDs.

Esta API no concede permisos: las validaciones de alcance, dueño, sesión, inventario y concesiones del host deberán precederla al integrar. Ningún RPC nuevo recibe estas llamadas. Los controles reales de agarre/suelta siguen usando el sistema anterior del laboratorio.

La primera versión nativa tiene constantes de controlador conocidas. El adaptador rechaza valores de rigidez/límites de Tuning incompatibles, y detecta cambios de sus parámetros después de arrancar. Las distancias mínima/máxima sí proceden del Tuning para calcular el objetivo.

## Historia y corrección

- Diario: hasta 120 ticks y 256 KiB de contenido serializado, además del costo de los objetos/contenedores de GDScript. No es una cota de memoria total del proceso.
- Pasos de repetición por corrección: como máximo 24. Es una cota provisional de trabajo, **no** un presupuesto de tiempo validado en la notebook.
- El núcleo conserva su propia caché: hasta 120 checkpoints dentro de 16 MiB; la pila de 128 cuerpos solo retiene 27. La historia de inputs es independiente de esa caché.
- `reconcile_trusted(tick, bytes)` comprueba historia y presupuesto antes de construir el candidato. Restaura un snapshot de autoridad confiable, exige que su tick coincida y repite únicamente los registros posteriores disponibles. No consulta el proveedor actual ni repite el actor o el reloj.
- Un lanzamiento vuelve a ejecutarse físicamente en esa rama. La señal `action_effect` solo se emite en la ejecución local original: no vuelve a emitir sonido, transacción u otro efecto externo durante replay.
- El mundo activo solo se sustituye tras completar la repetición. Un rechazo del snapshot o un replay fallido conserva ese mundo. En el caso válido se invalida la caché vieja mediante la importación y se construyen checkpoints de la rama nueva.
- Un duplicado o una muestra anterior a la última autoridad aceptada se ignoran. Falta la identidad/revisión de protocolo definitiva: el tick solo se usa dentro de esta sesión/contexto fijo.
- Presupuesto excedido, historia ausente, input faltante, cambio de Tuning o resincronización piden recuperación y desactivan la predicción. Una resincronización también descarta el diario. No hay recuperación automática ni mezcla a réplica todavía; el integrador deberá reconstruir el contexto y la sesión con otro adaptador.

La sustitución temporal mantiene dos mundos vivos y puede duplicar transitoriamente la memoria de sus cachés. Falta medir costo y memoria con el catálogo y la notebook. La coherencia de ojos/dt deberá actualizarse o invalidarse si la futura integración corrige la historia del actor o los tramos de cámara lenta; eso todavía no está conectado a `NetSync`.

`trusted` conserva su significado: solo bytes generados por la autoridad correcta, después de una frontera externa de protocolo. Longitud, manifiesto y checksum no autentican al emisor ni protegen frente a todas las mutaciones de estructuras nativas. El ensayo N3 de Claude demuestra cuelgues y abortos fuera de ese uso; no se declara resuelto.

## Reproducción

Desde `implementacion`, tras compilar la extensión:

```powershell
& .\tools\testing\run_object_clock_probe.ps1
```

El runner crea un proyecto temporal con copias exactas de los scripts de producción y de `scenes/actor/actor.tscn`, genera su registro de clases e instala la DLL solo en esa copia. Guarda hashes de las fuentes copiadas. Cada importación y proceso tiene límite externo de 8 s. `-Modes normal,slow` permite acotar casos.

Los siete modos son `normal`, `slow`, `pause`, `resync`, `budget`, `tuning` e `history`. En todos, el actor se mueve con el motor real; se guardan inputs cuantizados y ojos por tick. Una referencia nativa separada consume solo los frames ya capturados.

Se introduce un impulso externo como control negativo. Restaurar el tick 15 en el presente 24 repite nueve pasos con objetivos guardados y vuelve exactamente a la referencia. Después se restaura el tick 27 en el presente 35: repite ocho pasos que incluyen el lanzamiento del 30, sin emitir otra señal externa. Se corrompen los objetos `ActorInput` originales ya utilizados para verificar que la historia conserva bytes propios.

Otros casos comprueban la pausa real del reloj, un tramo de cámara lenta con dt guardado, duplicados de acciones/confirmaciones, rechazo atómico de un checkpoint dañado y recuperación sin alterar el mundo nativo. `resync` inyecta la señal real del reloj; no simula una resincronización de red. `history` llega al tick 150 y comprueba la expulsión de los primeros 30 frames.

Las entradas siguen siendo inyectadas por un driver local y los checkpoints salen de una referencia local. Estos resultados no sustituyen al ensayo de ENet con input real ni a la validación independiente de Claude.
