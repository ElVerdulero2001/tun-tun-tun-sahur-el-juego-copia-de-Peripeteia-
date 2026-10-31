# Consulta: reutilizar el contrato de Traversal V2 para Hanging V3

## Propósito

Esta nota no propone implementar todavía ni da por aprobada una solución. Su objetivo es contrastar una posible reutilización de V2 con la arquitectura real de V3 y definir, si corresponde, un contrato mínimo para continuar.

## Hechos observados

### V2 ya resuelve un contrato de gobierno físico

`PlayerMotor` en V2 expone un contrato de propiedad exclusiva sobre el cuerpo:

```gdscript
begin_traversal(owner) -> TraversalLease
apply_traversal_pose(lease, target_pose) -> TraversalMoveResult
end_traversal(lease, exit_velocity, reason)
```

- El `TraversalLease` es una credencial por identidad de referencia; no un booleano que cualquier sistema pueda activar.
- Sólo el dueño del lease vigente puede aplicar una pose guiada o cerrar el tramo.
- Cada aplicación válida de una pose renueva el lease. Si el dueño deja de renovarlo, `PlayerMotor` fuerza una salida segura.
- El movimiento guiado usa colisión real (`move_and_collide`), no teletransporte.
- El resultado distingue `OK`, `BLOCKED` y `REJECTED`, y conserva la última pose confirmada como segura.
- V2 revalida una pose sin desplazamiento y una rotación nueva mediante `test_move`; esto cubre la posibilidad de que aparezca geometría sobre un jugador que está colgado e inmóvil.

Referencias:

- `scripts/player_v2/traversal/traversal_lease.gd`
- `scripts/player_v2/traversal/traversal_move_result.gd`
- `scripts/player_v2/player_motor.gd` (`physics_tick`, `begin_traversal`, `apply_traversal_pose`, `end_traversal`)

### V3 ya tiene una separación inicial de responsabilidades

- `H0Core` calcula locomoción y publica una intención mediante `submit_motion_intent`.
- `V3PhysicsBody` es quien actualmente escribe velocidad y ejecuta `move_and_slide()`.
- `V3HangingCandidateEvaluator` produce una candidata de borde; no toma el control físico.
- La cámara vive separada en `V3CameraRig`.

Referencias:

- `scripts/player_v2/parkour_v3/h0_core.gd`
- `scripts/player_v2/parkour_v3/v3_physics_body.gd`
- `scripts/player_v2/parkour_v3/v3_hanging_candidate_evaluator.gd`

## Hipótesis a contrastar

En vez de copiar el sistema de traversal V2 completo, V3 podría **adaptar el contrato genérico** de gobierno temporal del cuerpo:

- Un core activo solicita una credencial exclusiva.
- Sólo ese core puede mandar poses guiadas con colisión.
- Si no renueva la credencial, el cuerpo vuelve automáticamente a la locomoción normal.
- `HangingCore` sería el primer consumidor del contrato; mantle u otros cores podrían usarlo más adelante.

Esto **no** implica copiar `TraversalController`, estados de escaleras, shimmy, mantle ni los nombres de las clases de V2. Tampoco presupone que el algoritmo se pueda trasladar sin cambios: V3 tiene su propio cuerpo, postura crouch, cámara y orden de ejecución.

## Riesgo de integración a revisar

Actualmente, que H0 deje de publicar `submit_motion_intent` no parece suficiente para ceder control:

1. Un `HangingCore` aplicaría una pose con `move_and_collide()`.
2. `V3PhysicsBody` sigue ejecutando su flujo normal de gravedad y `move_and_slide()` en el mismo tick.
3. El segundo movimiento podría alterar o invalidar la pose guiada recién aplicada.

Si el análisis es correcto, el contrato V3 necesitaría que `V3PhysicsBody` suspenda su integración normal mientras exista un lease vigente y renovado. Esa conclusión debe validarse contra el orden real de `_physics_process` y las prioridades de cada nodo.

## Preguntas concretas para revisar

1. ¿La lectura anterior del ciclo físico es correcta? ¿Qué sucede exactamente si un core guiado mueve el cuerpo y `V3PhysicsBody` ejecuta después `move_and_slide()`?
2. ¿Qué elementos de V2 conviene portar como comportamiento o pruebas, cuáles adaptar y cuáles descartar por estar acoplados a V2?
3. ¿Cuál debería ser el orden explícito por `physics tick` entre H0, `HangingCore`, evaluador de candidatas y `V3PhysicsBody`?
4. ¿Cuál es el contrato V3 mínimo para este primer caso, sin anticipar un árbitro general o múltiples cores competitivos?
5. ¿Qué pruebas de regresión mínimas deben existir antes de usar el contrato para Hanging?

## Resultado esperado de esta revisión

Una decisión breve entre estas opciones:

1. Adaptar ahora el contrato de lease de V2 para V3.
2. Mantener V3 sin lease y resolver Hanging con un mecanismo más chico, especificando cómo evita doble movimiento y estados retenidos.
3. Detectar una incompatibilidad concreta que justifique rediseñar el contrato antes de implementarlo.
