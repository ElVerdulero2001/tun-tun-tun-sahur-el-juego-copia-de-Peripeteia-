# H0 V3 — perfiles de control aéreo en reentrada

**Estado:** decisión de diseño. No implementado por este documento.

## Problema

H0 tiene dos necesidades reales de control aéreo:

| Perfil de H0 | Duración |
| --- | ---: |
| `NORMAL` | `0.35 s` |
| `REENTRADA_TRAVERSAL` | `0.75 s` |

`NORMAL` es el control aéreo de un salto o una salida de piso ordinaria. `REENTRADA_TRAVERSAL` es el margen que recibe el jugador cuando H0 recupera la locomoción después de que un core de traversal la estuvo gobernando. Hanging y Ladder pertenecen a esta segunda categoría.

El `0.75` no es un valor propiedad de Hanging ni de Ladder. Es una política propia de H0 para ese tipo de reentrada.

## Contrato

Un core de traversal puede publicar una única clase de reentrada, por ejemplo:

```text
REENTRADA_TRAVERSAL
```

No publica una duración, no escribe variables de H0 y no modifica Body. H0 es el único que traduce esa clase a una configuración:

```text
NORMAL                -> 0.35 s
REENTRADA_TRAVERSAL   -> 0.75 s
```

El nombre concreto del dato, su tipo y el sitio donde se almacenará quedan abiertos. Lo relevante es el límite de autoridad: los cores externos describen el tipo de reentrada; H0 posee la tabla de valores y el contador vivo.

## Paquete de reentrada y Body

Cuando Hanging termina, le deja a H0 un paquete mínimo de información:

```text
{ reentrada: TRAVERSAL }
```

Hanging ya posee una referencia a H0 para suspenderlo y reactivarlo; el paquete se publica por esa misma relación. Reactivar H0 y publicar el paquete son dos acciones de la salida de Hanging.

En `T+1`, H0 consume el paquete, consulta su tabla y carga `0.75 s` en **su propio contador aéreo**. Luego descarta el paquete. El valor `0.75` nunca se envía a Body.

Body sólo recibe órdenes físicas:

```text
launch                         -> velocidad inicial de salida
intención horizontal de H0     -> corrección del aire según input
```

El contador interno de H0 decide durante cuánto tiempo H0 continúa enviando la segunda orden. No es un valor que Body necesite conocer.

## Ciclo de una salida de Hanging

```text
T:   Hanging recibe la orden de salida.
     Publica REENTRADA_TRAVERSAL, reactiva H0 y encola el launch en Body.

T+1: H0 consume el contexto una sola vez.
     Selecciona REENTRADA_TRAVERSAL y carga su contador aéreo con 0.75 s.
     Body todavía da prioridad al launch pendiente.

T+2: No queda launch pendiente.
     La intención aérea de H0 pasa a Body y H0 gobierna el horizontal.
```

`launch` es el comando de lanzamiento propio de `V3PhysicsBody`: Body le da prioridad durante `T+1`.

**Decisión cerrada — inicio del contador:** la ventana se inicia deliberadamente en `T+1`, aunque el primer control horizontal efectivo de H0 llegue en `T+2`. No se espera una confirmación de Body ni se agrega un estado intermedio. Ese posible tick menos de control útil no es relevante para gameplay; evitar el acoplamiento H0↔confirmación de `launch` es la opción de motor más simple y estable.

## Dos reglas del contrato

1. **Consumo único.** El contexto describe sólo esta reentrada; H0 lo consume en `T+1` y lo limpia. No puede contaminar una reentrada futura.
2. **Cierre del perfil temporal.** El contador de traversal se descuenta hasta cero. Al llegar a cero no se carga `NORMAL` en pleno aire: H0 conserva la inercia sin control aéreo. Al aterrizar o volver a suspenderse, se descarta el perfil temporal; la siguiente salida normal de piso carga `NORMAL` (`0.35 s`).

## Fuente de verdad y protección contra reescrituras

H0 separa tres conceptos:

```text
tabla de perfiles       datos fijos: NORMAL=0.35, TRAVERSAL=0.75
perfil activo           cuál de esos perfiles fue seleccionado
contador restante       único estado que cambia cada tick
```

Durante el vuelo no se vuelve a consultar ni se modifica la tabla. H0 sólo descuenta el contador. La selección o recarga de un perfil sólo puede ocurrir en una transición autorizada:

- salida normal de piso: selecciona `NORMAL`;
- reentrada guiada consumida: selecciona `REENTRADA_TRAVERSAL`;
- aterrizaje o nueva suspensión: descarta el perfil temporal.

Por lo tanto, `0.75` no es un valor inyectado a Body ni un override que otros cores puedan mantener. Es un valor fijo de H0 copiado una vez a su contador interno.

## Después de cargar el contador

Una vez que H0 cargó el contador, el perfil que originó el valor deja de importar para el vuelo actual. H0 no pregunta si el valor era `0.35`, `0.75`, si venía de Hanging ni si venía de Ladder. Sólo ejecuta su regla aérea habitual:

```text
¿contador aéreo > 0?
  sí -> H0 permite corregir el movimiento horizontal según el input
  no -> H0 conserva la inercia horizontal actual
```

En cada tick aéreo el contador baja. La única diferencia entre los perfiles es cuánto tarda en llegar a cero. No existe una conducta adicional llamada “Traversal” durante esos `0.75 s`: `REENTRADA_TRAVERSAL` fue únicamente la etiqueta que permitió a H0 elegir el número inicial.

## Fuera del diseño: switchboard

El switchboard fue descartado y no forma parte de esta arquitectura. Esta reentrada no consulta ni publica capacidades en un switchboard: el core de traversal termina, publica la clase de reentrada y H0 consume su política interna. No hay una frontera de switchboard pendiente de definir.

## Límite de complejidad

H0 no debe conocer Hanging, Ladder ni la lógica de sus salidas. Sólo conoce clases reutilizables de reentrada. Por ahora existen dos perfiles y no hace falta inventar más:

```text
NORMAL
REENTRADA_TRAVERSAL
```

Sólo se agrega otra categoría si aparece una experiencia de juego que requiera una política de locomoción genuinamente distinta.
