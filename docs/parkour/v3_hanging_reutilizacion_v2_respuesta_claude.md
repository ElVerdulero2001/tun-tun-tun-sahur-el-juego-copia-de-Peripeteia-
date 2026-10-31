# Respuesta: reutilizar el contrato de Traversal V2 para Hanging V3

> Contesta punto por punto `v3_hanging_reutilizacion_v2_consulta_claude.md`. Mismo criterio: esto tampoco autoriza código por sí solo, es la decisión de diseño que destraba escribirlo.

## Veredicto sobre el riesgo señalado

El riesgo de integración que plantea la consulta es real y lo confirmé leyendo el código, no por intuición.

`V3PhysicsBody._physics_process()` (`scripts/player_v2/parkour_v3/v3_physics_body.gd:64-104`) corre **incondicionalmente** cada tick: aplica `_pending_horizontal_velocity` (sería `Vector3.ZERO` si nadie llamó `submit_motion_intent` ese tick), suma gravedad si `not is_on_floor()`, y llama `move_and_slide()` siempre. No tiene ningún gate de gobierno.

Comparado contra V2, `PlayerMotor.physics_tick()` (`scripts/player_v2/player_motor.gd:130-138`):

```gdscript
func physics_tick(delta: float) -> void:
    if _lease != null:
        if _lease_renovado_este_tick:
            _lease_renovado_este_tick = false
        else:
            _forzar_salida_traversal()

    if _lease == null:
        _locomocion_normal(delta)
```

V2 nunca tuvo el problema porque `PlayerMotor` es el mismo nodo que expone el contrato de lease y el que corre la locomoción normal: puede envolver su propio bloque con un `if`. `V3PhysicsBody` no tiene ese `if` hoy.

**Conclusión:** si `HangingCore` aplicara una pose guiada por su cuenta (`move_and_collide`), `V3PhysicsBody` igual correría después en el mismo frame, acumularía gravedad (colgado, `is_on_floor()` es false) y `move_and_slide()` pisaría la pose recién aplicada en el mismo tick. Doble movimiento confirmado. Cerrar solo el canal de `H0Core` (que deje de llamar `submit_motion_intent`) no alcanza — hace falta que `V3PhysicsBody` mismo sepa que está gobernado y se abstenga de su propio flujo normal.

## Respuestas a las preguntas concretas

**1. ¿La lectura del ciclo físico es correcta?**
Sí, confirmado contra el código (cita arriba).

**2. ¿Qué sucede exactamente si un core guiado mueve el cuerpo y V3PhysicsBody ejecuta después `move_and_slide()`?**
`V3PhysicsBody` suma gravedad (el cuerpo no está en piso mientras cuelga) y desplaza el body con esa velocidad vertical, invalidando la pose que Hanging acaba de fijar en el mismo tick.

**3. ¿Cuál debería ser el orden explícito por tick entre H0, HangingCore, evaluador y V3PhysicsBody?**
Hoy: `H0Core` prioridad 0 → `V3PhysicsBody` prioridad 100 → `V3HangingCandidateEvaluator` prioridad 150. El evaluador corriendo último está bien: lee hechos ya confirmados del tick, no intenciones.
Propuesta: `HangingCore` en una prioridad baja como H0 (ej. 10), para que ambos puedan intentar someter intención/pose antes de que `V3PhysicsBody` (100) decida qué aplicar ese tick. El evaluador sigue al final.

**4. ¿Cuál es el contrato V3 mínimo, sin anticipar un árbitro general?**
- `V3PhysicsBody` gana un segundo canal, port directo del algoritmo de `apply_traversal_pose` (incluida la revalidación por `test_move` en pose inmóvil y en rotación — dos bugs ya encontrados y resueltos en V2, no hace falta redescubrirlos):
  ```gdscript
  begin_governance(owner) -> lease
  apply_guided_pose(lease, pose) -> result   # OK | BLOCKED | REJECTED + last_safe_pose
  end_governance(lease, exit_velocity, reason)
  ```
- `V3PhysicsBody._physics_process()` se parte igual que `physics_tick()` de V2: si hay lease vigente, solo chequea renovación/forced-exit y `return`; si no, corre el flujo normal que ya tiene.
- `H0Core` no necesita saber nada del lease. Sigue llamando `submit_motion_intent` sin condicional — la guard de "dos autoridades" que ya existe en `submit_motion_intent` se extiende para rechazar cualquier intento mientras haya lease activo de otro dueño. Un solo lugar (`V3PhysicsBody`) sabe quién manda.
- Sin árbitro ponderado: el gate para pedir el lease es binario — candidata válida (`V3HangingCandidateEvaluator.last_candidate.is_valid`) + trigger (cayendo, o salto explícito). Nada de "certeza suma 100" todavía; eso se construye cuando exista un segundo core real compitiendo (mantle u otro), no antes.

**5. ¿Qué pruebas de regresión mínimas deben existir antes de usar el contrato?**
- Con lease activo, `V3PhysicsBody` no debe tocar velocity/gravedad/`move_and_slide()` propios — el bug central de esta nota, convertido en test. El más importante de la lista.
- Lease se cierra solo si nadie lo renueva en un tick (equivalente a `FORCED_NO_RENEWAL`).
- Pose inmóvil penetrada por geometría nueva (portado de V2).
- Segunda autoridad (H0 intentando someter intención mientras Hanging tiene el lease) queda rechazada sin pisar nada.
- Ciclo completo: candidata válida → grab → sostenido varios ticks → release por input → `V3PhysicsBody` retoma locomoción normal sin velocity contaminada.

## Qué portar, qué adaptar, qué descartar

| | Qué | Por qué |
| --- | --- | --- |
| **Portar tal cual** | Algoritmo completo de `apply_traversal_pose`, incluida la revalidación por `test_move` en pose inmóvil y en rotación | Es física pura, no depende de nombres de clase V2; son dos bugs reales ya resueltos |
| **Portar tal cual** | Los tests que ejercitan esos dos casos raros | Si no se portan, alguien redescubre el mismo bug a mano en V3 |
| **Adaptar** | La forma del lease (no los campos `yaw_arco_*` de `TraversalLease`, que son de feel de cámara V2) | El núcleo del contrato es dueño + pose_segura + válido/invalidado; V3 maneja cámara distinto en `V3CameraRig` |
| **Descartar** | `TraversalController` completo — estados de escalera, shimmy, mantle, lectura directa de `Input.*` | Es lógica de negocio de V2 que no aplica a la arquitectura de cores de V3 |

## Decisión

**Opción 1 (de las tres que planteaba la consulta): adaptar ahora el contrato de lease de V2 para V3**, con el gate explícito en `V3PhysicsBody` que esta nota señaló correctamente.

No es opción 3 (detectar incompatibilidad y rediseñar): no hay choque arquitectónico, es una laguna de especificación que se cierra extendiendo `V3PhysicsBody._physics_process()` con el mismo `if` que V2 ya tiene en `PlayerMotor.physics_tick()`.

No es opción 2 (mecanismo más chico y propio): un contrato "más chico" terminaría reinventando los mismos edge cases (renovación, pose inmóvil, doble autoridad) que V2 ya pagó el costo de encontrar — con el riesgo de no descubrirlos hasta que fallen en el playtest, no en un test.

## Orden de trabajo sugerido a partir de acá

1. Extender `V3PhysicsBody` con `begin_governance`/`apply_guided_pose`/`end_governance` + el gate en `_physics_process()`, portando el algoritmo y los tests de `apply_traversal_pose`.
2. Escribir los 5 tests de regresión de la sección anterior contra ese contrato solo, sin `HangingCore` todavía — confirmar que el gate funciona con un dueño de lease de prueba.
3. Recién ahí, `HangingCore`: gate binario (candidata válida + trigger) → pide lease → sostiene pose (reaplica la misma pose de `V3HangingCandidateEvaluator` cada tick) → suelta por input explícito o por `BLOCKED` tras revalidar.
4. Shimmy, mantle, árbitro ponderado general: después, y solo cuando haya un segundo core real para probar competencia contra algo, no contra un caso inventado.
