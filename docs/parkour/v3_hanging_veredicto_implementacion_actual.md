# V3 Hanging — veredicto sobre la implementación actual

> **Fecha:** 2026-09-18.
>
> Responde a la pregunta de si la implementación actual de Hanging (ver
> `v3_hanging_radiografia_implementacion_actual.md`) es reusable o hay que
> tirarla. No autoriza borrar nada todavía: la decisión declarada es esperar.

## Resumen

La mitad sensores→evaluator es una base razonable. La mitad
captura→retención→snap es un experimento cableado a producción sin
arbitraje, sin salida y con un debug que miente sobre lo que hace. Cuando
llegue el momento de construir el core real de Hanging, conviene conservar
la primera mitad y descartar la segunda entera.

## Lo reusable

Los tres providers (`V3ForwardWallProbe`, `V3TopSurfaceProbe`,
`V3FrontVolumeProbe`) y el `V3HangingCandidateEvaluator` separan bien lectura
cruda de interpretación, siguiendo el mismo patrón ya validado en Traversal
V2 (detector/resolver separados). La geometría de `C_ancla` y `P` (borde +
normal, offsets fijos) es matemática real, no relleno.

## Lo que está podrido

### 1. `V3HangingEntryLab` es un latch sin salida

Una vez `is_holding_pose = true`, el lab deja de leer candidata, cilindro/esfera,
soporte o pose nueva: vuelve a pedir `held_pose` para siempre. No existe
código que lo devuelva a `false`. La única salida es reiniciar la escena.
No es que falte terminar shimmy/salida — falta el apagador mismo.

### 2. No hay gobierno, hay una carrera ganada por accidente

`H0` sigue mandando intención de movimiento en cada tick sin enterarse de
que existe Hanging. El snap "gana" sólo porque `V3PhysicsBody` lo procesa en
prioridad 100 y descarta la intención de H0 después. `submit_pose_snap` ya
anticipa el conflicto entre orígenes (falla + advierte si dos piden snaps
distintos en el mismo tick) pero no lo resuelve: es detección de choque, no
arbitraje.

### 3. Lógica de decisión fantasma

`pose_clear`, `shape_supports_wall` y `local_evidence_score` se calculan
con criterio real (pesos, umbrales) pero no gatillan nada: sólo llegan al
overlay de debug. Parece que hay un scoring gate que valida candidatas y no
lo hay.

### 4. `can_occupy_pose()` no valida el trayecto

Usa `test_move(pose, Vector3.ZERO, ...)`: chequea que el destino P esté
libre, no que el camino desde la posición actual hasta P —que cruza la
cornisa que se está agarrando— esté libre. Es un bug de colisión latente,
no una limitación de scope.

### 5. El debug miente

El overlay todavía dice "detección solamente, sin movimiento colgado"
mientras la retención de P ya mueve al player en runtime. El comentario del
smoke test tiene el mismo problema: afirma que P/snap están aislados
cuando las propias aserciones prueban que están activos.

### 6. Telemetría sin consumidor

`last_wall_samples[].height/.origin`, `wall_sample_index` y
`last_entry_reason` se publican y nunca se leen. Señal de un plan que
cambió varias veces sin barrer los campos viejos.

## Veredicto

| Pieza | Estado | Acción sugerida a futuro |
| --- | --- | --- |
| `V3ForwardWallProbe` / `V3TopSurfaceProbe` / `V3FrontVolumeProbe` | Sano | Conservar |
| `V3HangingCandidateEvaluator` | Sano, con campos muertos | Conservar; conectar `pose_clear`/`shape_supports_wall`/`local_evidence_score` a gates reales |
| `V3HangingCaptureProbe` | Cosmético, sin colisión física | Revisar si el gate geométrico (S entra en C) alcanza para el core real |
| `V3HangingEntryLab` | Latch sin salida, sin arbitraje | Descartar; reemplazar por árbitro con gobierno real y salida a H0 |
| Snap directo en `V3PhysicsBody` | Gana por orden de ejecución, no por diseño | Descartar junto con EntryLab |
| `HangingDebug` | Texto desactualizado/engañoso | Reescribir junto con el core nuevo |

## Referencias

- `v3_hanging_radiografia_implementacion_actual.md`: la radiografía que
  origina este veredicto.
- `v3_hanging_auditoria_huecos_y_fallas_filosoficas.md`: huecos de
  filosofía pendientes (árbitro, certeza contextual, gobierno) — leer antes
  de diseñar el core real.
