# Comparación V1/V2 con mecánicas aisladas — nota de metodología

> Este documento registra un acuerdo de trabajo, no una implementación. Nada de lo que describe está
> hecho todavía — queda pendiente de confirmación antes de tocar ningún script.

## El problema que esto resuelve

Trabajar con V1 y V2 al mismo tiempo, con todas las mecánicas de parkour activas en los dos, mete
demasiadas variables sueltas: si algo se siente distinto entre uno y otro, no se sabe si es por la
locomoción de base, por el hanging, por el mantle, por la escalera, o por la combinación de varias a la
vez. No se puede aislar la causa.

## La idea acordada

Apagar el parkour en los dos sistemas (V1 y V2) y dejar activo solo lo mínimo: caminar, correr, saltar,
agacharse. Con esa base "limpia" comparada uno a uno, después se reactiva **una sola mecánica a la vez**
(por ejemplo: "reactivá el hanging en V1 y V2") para compararla en aislamiento, sin ruido de las demás.
Se repite mecánica por mecánica.

## Por qué no alcanza con "simplemente no activarlo"

En ninguno de los dos sistemas el hanging/mantle/ladder se dispara con una tecla dedicada — se activa
solo por contexto (estar en el aire cerca de un borde válido, etc.). No hay ninguna tecla que uno pueda
"no apretar" para evitarlo. La única forma de garantizar que esas mecánicas no interrumpan una prueba de
locomoción pura es cortarlas a nivel código, con un interruptor explícito.

## El punto sin resolver — PlayerV2

Esto implica tocar el código real de V2 (`scripts/player_v2/traversal/...`), algo que hasta ahora se
venía evitando a propósito toda la sesión. Puntualmente pisa la regla explícita del propio
`Parkour V2 - V0.5.1`: *"R1 no modifica PlayerV2"*, y la instrucción directa dada antes: *"Pausa toda
implementación de V2. No cambies scripts de gameplay."*

**Todavía no está confirmado si se cruza esa línea a propósito para esto.** Antes de tocar cualquier
archivo de `scripts/player_v2/`, hace falta una confirmación explícita.

## Diseño mínimo propuesto (si se confirma)

Si se aprueba, la forma menos invasiva sería un solo export booleano por controller, en cada sistema:

- Un flag (por ejemplo `parkour_habilitado: bool = true` por default) que, si se apaga, bloquea la
  entrada a HANGING / MANTLE / DIRECT_MANTLE / LADDER (o sus equivalentes de estado en V1) antes de que
  arranquen — no cambia ninguna constante, no reescribe ninguna lógica existente, solo agrega un gate al
  principio de la decisión de entrar a esos estados.
- Reversible con un solo cambio de valor. La locomoción base (movement/movement_controller en ambos
  sistemas) no se toca en absoluto.
- Se prendería/apagaría mecánica por mecánica según qué se esté comparando en cada momento.

## Estado actual

Pendiente de confirmación para avanzar. No se tocó ningún script de `PlayerV2` ni del V1 histórico para
esto todavía.
