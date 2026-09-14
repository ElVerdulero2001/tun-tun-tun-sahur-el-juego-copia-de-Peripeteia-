# Bloque 1 - conversión operativa de movimiento V1 a PlayerMotor V2

## Para qué sirve

Esto no es otro diseño ni una propuesta de feel. Es la lista cerrada de cambios
para hacer que `PlayerMotor` recupere la locomoción observable de V1, sin tocar
detector, hanging, mantle, escalera ni cámara de traversal.

Fuentes:

- `docs/parkour/v1_forensic_technical_map.md`, secciones 4.2 y 10.1 a 10.4.
- `scripts/player_v2/player_motor.gd`, estado actual del worktree.
- `output/pdf/Parkour_V2_Diseno_de_Arquitectura_V0_4.pdf`, bloque 1.

## Contrato que se migra

| Comportamiento | V1 verificado | V2 actual | Cambio necesario en PlayerMotor |
|---|---|---|---|
| Caminar | Objetivo `5.0`; `lerp` horizontal a `14.0 * delta`. | `5.0`; mismo perfil de `lerp`. | Conservar. |
| Correr | Objetivo `9.0`. | Objetivo `8.0`. | Cambiar `RUN_SPEED` a `9.0`. |
| Agacharse en suelo | Objetivo `2.5`; sólo reduce velocidad si está en suelo. | `2.5`; reduce velocidad también en aire. | Hacer que crouch sólo elija `CROUCH_SPEED` cuando `is_on_floor()`. |
| Salto normal | Tecla sostenida + suelo + no crouch; `velocity.y = 4.5`; marca `_jumped = true`. | Flanco de tecla + suelo; `4.5`; no marca equivalente. | Mantener `4.5`, permitir tecla sostenida, bloquear salto agachado y guardar una marca de salto propio. |
| Gravedad | Sólo fuera del suelo; `get_gravity() * delta`. | Igual. | Conservar. |
| Control aéreo con dirección | Si rapidez horizontal `> 7.0`: `0.3`; si no: `1.5`. No hay clamp aéreo. | Siempre `14.0 * 0.3 = 4.2`; no distingue rapidez. | Reemplazar por dos coeficientes V1 (`0.3` / `1.5`) y umbral `7.0`. |
| Fricción aérea sin dirección | Salto propio: `0.8`; caída pasiva: `3.0`. | Siempre `14.0 * 0.3 = 4.2`. | Reemplazar por `0.8` / `3.0`, usando la marca de salto propio. |
| Clamp horizontal | En piso/plataforma, limita la velocidad a `current_speed`. En aire no limita. | No limita explícitamente en ningún caso. | Clampear sólo en piso al `current_speed`; no clamplear en aire. |
| Aceleración de objetivo | `current_speed` también interpola a su objetivo con `14.0 * delta`. | El objetivo cambia instantáneamente. | Introducir `current_speed` y actualizarlo antes de mover. |
| Postura/collider | Toggle de crouch; altura interpola `2.0` ↔ `0.8` a tasa `8.0`; cámara `0.706` ↔ `0.4`. | Crouch sostenido; altura instantánea `1.8` ↔ `0.9`; cámara no se ajusta. | No mezclar esta corrección con el primer cambio de impulso: requiere una decisión explícita sobre preservar el contrato de input de V2 o equivaler el toggle V1. |

## Orden exacto de implementación

1. Añadir estado interno `current_speed` y `jumped`.
2. Cambiar el cálculo de objetivo de velocidad y el movimiento de piso para que sean el de V1.
3. Separar la rama aérea: control con input y fricción sin input, incluidos sus cuatro valores V1.
4. Ajustar el guard de salto para crouch y actualizar/resetear `jumped` al despegar/aterrizar.
5. Actualizar tests del motor con los números de V1 antes de tocar postura.
6. Jugar únicamente el circuito de salto/carrera de `v2_comparison_p0.tscn` y comparar: correr debe recuperar el alcance V1 de referencia (aprox. 6 m; pendiente de confirmar manualmente).

## Exclusiones deliberadas

- No cambiar `STANDING_HEIGHT`, `CROUCH_HEIGHT`, ni la semántica sostenida de Ctrl en esta tanda. Son diferencias reales, pero forman un sub-bloque de postura y pueden invalidar pruebas de techo existentes.
- No cambiar yaw/pitch aquí. El yaw libre de V1 se resuelve junto al estado activo de traversal, no en locomoción libre.
- No alterar `TraversalDetector`, `TraversalResolver`, `TraversalController`, `TraversalSegment`, escenas de playground ni tests de traversal.
- No "arreglar" rarezas V1. Si una rareza se recupera, se etiqueta como equivalencia y se negocia después.

## Cierre del bloque

El bloque queda listo para playtest sólo si los tests reflejan los contratos anteriores y la carrera a `9.0`, el salto a `4.5` y el control aéreo asimétrico se sienten contra el mismo circuito. No se pasa a detector hasta entonces.
