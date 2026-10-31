# V3.1 — Problema de autoridad del control aéreo

> **Decisión posterior vigente:** H0 usa una única ventana de control aéreo de
> `0.75 s` en todas sus entradas. Hanging ya no define ni reinicia una ventana
> especial al salir. El resto de este documento conserva el análisis histórico
> del problema descartado; no describe el contrato actual.

## Decisión que se quiere preservar

Se quieren cumplir simultáneamente estas reglas:

    1. Cada core posee sus propias configuraciones.
    2. Un core no escribe variables internas de otro core.
    3. Sólo un core gobierna el player por tick.
    4. H0 usa 0.35 s de control aéreo.
    5. El salto que sale de Hanging necesita 0.75 s para que el player pueda acomodarse.

La regla 2 prohíbe esta forma:

    V3HangingCore
    → h0.air_control_time = 0.75

Eso es inyección directa de un dato de Hanging dentro del estado de H0.

## Valores que se quieren unificar

La intención es que el concepto tenga el mismo nombre en todos los cores:

    H0Core.air_control_time = 0.35
    V3HangingCore.air_control_time = 0.75

Cada valor pertenece a su core. No son dos nombres distintos para un mismo
contador mutable de H0.

## El conflicto

Al presionar Espacio en Hanging, la implementación actual hace:

    V3HangingCore sale
    → H0Core vuelve a estar activo de inmediato
    → Body recibe el launch
    → Body lo aplica en el tick siguiente

Si H0 toma gobierno inmediatamente, la política que corresponde es la de H0:

    H0Core.air_control_time = 0.35

Por lo tanto, no se pueden sostener estas dos frases a la vez sin introducir
otra pieza de diseño:

    “H0 gobierna inmediatamente después de Espacio.”
    “El control aéreo de 0.75 pertenece a Hanging.”

Una vez que Hanging deja de gobernar, su valor de 0.75 ya no puede modificar el
comportamiento de H0 sin que exista una transferencia de dato entre cores.

## Lo que no se debe hacer

    V3HangingCore modifica air_control_time de H0.
    H0 adivina qué core anterior lo soltó mirando nombres de nodos.
    El Body decide arbitrariamente una política de control aéreo que no le pertenece.
    Dos cores publican movimiento en el mismo tick.

## Alternativas coherentes

### A. H0 toma control inmediatamente

    Espacio
    → Hanging solicita launch
    → H0 retoma gobierno
    → H0 usa 0.35 s

Ventaja: flujo corto y una autoridad clara.

Costo: no existe la ventana especial de 0.75 s para el salto desde Hanging.

### B. Hanging conserva gobierno durante 0.75 s

    Espacio
    → Hanging solicita launch
    → Hanging entra en una salida aérea propia
    → Hanging gobierna el aire durante 0.75 s
    → Hanging devuelve autoridad a H0
    → H0 aplica desde entonces su propio 0.35 s

Ventaja: el 0.75 s pertenece realmente a V3HangingCore. No hay inyección de
datos y cada core conserva su política.

Costo: Hanging necesita un estado de salida aérea explícito y reglas propias de
control durante ese intervalo.

### C. Una autoridad de transición separada

    Espacio
    → Hanging comunica “salida por salto”
    → una autoridad de transición posee la política de 0.75 s
    → al terminar, H0 recupera su política de 0.35 s

Ventaja: la política de transición no pertenece artificialmente ni a H0 ni a
Hanging.

Costo: agrega una pieza nueva al sistema, que no existe en el laboratorio actual.

## Planteo de salida acordado

La secuencia obligatoria se conserva sin una frontera o un core intermedio:

    H0 → V3HangingCore → payload de salida → H0

Un payload de salida está dirigido a H0. No es una transferencia directa de
gobierno desde Hanging a otro core, ni un nodo adicional entre ambos.

### Payload para salir con salto

    ExitPayload
      reason = HANGING_JUMP
      launch_velocity = dirección de salida ya calculada

Hanging comunica el hecho semántico de su salida y la orden física que necesita
el body. No incluye un campo air_control_time ni ningún override de duración.

### Responsabilidad de cada lado

    V3HangingCore
    → decide que su salida es HANGING_JUMP
    → construye el payload
    → deja de gobernar

    H0Core
    → recibe el payload dirigido a H0
    → recupera gobierno
    → interpreta reason según su propia política de entrada
    → escribe su propio air_control_time

La política pertenece a H0 porque H0 es quien gobernará el aire después de la
salida:

    reason = HANGING_JUMP  → H0.air_control_time = 0.75
    cualquier otra entrada → H0.air_control_time = 0.35

El 0.75 no es un valor donado por Hanging. Es una política de entrada de H0
para el motivo HANGING_JUMP.

### Invariantes que conserva

    1. H0 → core activo → H0 se mantiene intacto.
    2. Hanging no escribe campos internos de H0.
    3. Hanging no entrega una duración ni un override a H0.
    4. H0 es el único que modifica su air_control_time.
    5. Sólo un core gobierna el movimiento por tick.
    6. No existe un nodo/frontera/autoridad de transición adicional.

## Preguntas abiertas sobre el planteo acordado

El planteo de arriba resuelve el cruce de límite entre cores (Hanging no le
entrega ningún dato de duración a H0). Quedan sin definir dos comportamientos
internos de H0 que no dependen del payload, sino del ciclo de vida propio de
`air_control_time` una vez que H0 ya lo escribió:

### 1. Reentrada mientras la ventana de HANGING_JUMP sigue activa

Escenario:

    1. Hanging sale por salto → payload reason = HANGING_JUMP
       → H0.air_control_time = 0.75, arranca la ventana.
    2. A los 0.3 s (ventana todavía activa, no expiró ni aterrizó),
       el jugador es recapturado por Hanging.
    3. Hanging vuelve a soltarlo por salto → nuevo payload
       reason = HANGING_JUMP.

¿Qué pasa con el resto de la ventana anterior (los 0.45 s que quedaban) al
llegar el segundo payload? ¿La nueva entrada la reinicia limpia desde 0.75 s
(sin acumular, sin arrastrar el remanente), o hay alguna otra regla?

### 2. Disparador exacto del reset a 0.35 s

Una vez que H0 gobierna con `air_control_time = 0.75` por HANGING_JUMP,
¿qué evento puntual dispara la vuelta a su valor base de 0.35 s?

    ¿Expiración del contador únicamente?
    ¿Contacto con superficie (is_on_floor) aunque el contador no haya expirado?
    ¿Ambos, el que ocurra primero?

Y en ese caso, ¿es el mismo sensor/mecanismo que H0 ya usa para terminar su
propio ciclo normal de control aéreo, o hace falta uno nuevo específico para
la salida HANGING_JUMP?

## Ciclo de vida de air_control_time tras la entrada

Resuelve las dos preguntas abiertas de arriba. La confusión previa venía de
tratar `air_control_time` como un solo campo que a la vez era la política de
duración y el reloj corriendo — son dos cosas distintas y H0 es dueño de
ambas.

### Separación de config y estado runtime

    H0Core
      air_control_base = 0.35          (config fija, dueño H0)
      air_control_policy[reason]       (config fija, dueño H0)
                                        HANGING_JUMP → 0.75
      air_control_active               (estado runtime, vive y muere en H0)
      air_control_remaining            (estado runtime, cuenta regresiva)

`air_control_active` es el valor que efectivamente gobierna el control aéreo
en este instante. `air_control_base` y `air_control_policy` nunca cambian por
sí solos; solo se leen para decidir a qué valor se setea `active`.

### Entrada (accept_exit)

    H0.accept_exit(ticket)
    → air_control_active = policy[ticket.reason] si existe, si no base
    → air_control_remaining = air_control_active

### Respuesta a la pregunta 1 — reentrada mid-ventana

Un segundo `accept_exit(ticket)` no acumula ni promedia con la ventana
anterior: simplemente vuelve a ejecutar la asignación de arriba, que pisa
`active` y `remaining` sin importar cuánto quedaba. No hace falta una regla
especial de "aniquilar la anterior" — es el comportamiento normal de asignar
un valor nuevo a una variable.

### Respuesta a la pregunta 2 — disparador del reset a base

Cada tick, dentro del propio ciclo de H0:

    air_control_remaining -= delta
    si air_control_remaining <= 0 o is_on_floor():
        air_control_active = air_control_base

Es el mismo sensor de contacto que H0 ya usa para su ciclo normal de control
aéreo — no se agrega un sensor nuevo para HANGING_JUMP. El reset ocurre
enteramente dentro de H0, sin que ningún otro core lo dispare ni lo conozca.

### Por qué no rompe las invariantes

`air_control_active` y `air_control_remaining` son estado 100% interno de H0,
tan propio de H0 como su velocidad o su gravedad. Ningún dato cruza el límite
entre cores en este ciclo de vida — el cruce ya había terminado en
`accept_exit`. Las 6 invariantes del planteo acordado quedan intactas.

## Estado actual del código frente a este planteo

El código contiene aún la solución provisional:

    h0.reset_air_control(jump_exit_air_control_duration)

Esa llamada entrega una duración desde Hanging a H0 y no coincide con el
planteo de payload semántico. Se conserva como evidencia del estado actual;
no debe tomarse como contrato de arquitectura.

## Propuesta de integración mínima en V3

> Propuesta de diseño. No existe aún en el código y no autoriza una
> implementación por sí sola.

La integración conserva la secuencia obligatoria:

    H0 → core activo → ticket de salida dirigido a H0 → H0

No agrega un nodo, árbitro ni autoridad intermedia.

### 1. Contrato único de salida

Crear una pieza de datos explícita, por ejemplo CoreExitTicket, con campos
cerrados y tipados:

    origin
    reason
    launch_velocity, sólo cuando la salida necesita launch

El contrato debe usar enums, no strings de debug:

    origin: HANGING, LADDER, ...
    reason: HANGING_JUMP, HANGING_RELEASE, CORE_FAILURE, ...

El ticket no contiene air_control_time, configuraciones de H0 ni referencias
al core que salió.

### 2. Una única entrada a H0 desde una salida contextual

Agregar a futuro una API pública de H0 con una responsabilidad única:

    H0.accept_exit(ticket)

Al recibirlo, H0:

    1. valida que puede retomar gobierno;
    2. interpreta reason con su propia política de entrada;
    3. escribe su propio air_control_time;
    4. queda habilitado como core activo;
    5. si el ticket trae launch_velocity, solicita el launch al body.

H0 es el único que escribe su estado y el body sigue siendo el único que
aplica movimiento físico.

### 3. Migración de las salidas de Hanging

Salida con Espacio:

    V3HangingCore calcula launch_velocity desde cámara
    → construye ticket { origin = HANGING, reason = HANGING_JUMP, launch_velocity }
    → entrega el ticket a H0.accept_exit(ticket)
    → deja de gobernar

Salida con Ctrl/S:

    V3HangingCore construye ticket { origin = HANGING, reason = HANGING_RELEASE }
    → entrega el ticket a H0.accept_exit(ticket)
    → deja de gobernar

Hanging deja de llamar directamente a reset_air_control, a
set_locomotion_suspended(false) y a submit_launch durante sus salidas.

### 4. Política de entrada que pertenece a H0

    HANGING_JUMP    → H0.air_control_time = 0.75
    HANGING_RELEASE → H0.air_control_time = 0.35
    CORE_FAILURE    → H0.air_control_time = 0.35

La lista exacta de reasons se amplía cuando aparezcan Ladder u otros cores,
pero el contrato no cambia: el core saliente comunica un hecho; H0 decide su
propio comportamiento de entrada.

### 5. Orden físico esperado

    tick T
    Hanging construye/entrega ticket
    → H0 acepta y encola launch si corresponde

    tick T + 1
    V3PhysicsBody consume launch pendiente
    → aplica velocity
    → move_and_slide()

### 6. Pruebas mínimas al implementarlo

    Hanging + Espacio
    → H0 recibe HANGING_JUMP
    → air_control_time queda en 0.75
    → body aplica launch en T + 1

    Hanging + Ctrl/S
    → H0 recibe HANGING_RELEASE
    → air_control_time queda en 0.35
    → no hay launch

    Salida inválida o ticket incompatible
    → H0 conserva un estado explicable y no permite dos autoridades activas.
