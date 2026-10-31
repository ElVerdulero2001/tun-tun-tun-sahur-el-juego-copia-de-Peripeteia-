# Feedback — H0 V3 perfiles de control aéreo en reentrada

**Sobre:** `v3_h0_perfiles_control_aereo_reentrada.md`
**Estado:** revisión de diseño, sin implementar. Los cuatro huecos quedaron resueltos; queda una nota de consistencia con decisiones previas (ver punto 4).

## Lo que ya funciona

- Límite de autoridad correcto: H0 no necesita conocer Hanging ni Ladder, solo consume una clase de reentrada. Evita el acoplamiento que ya se vio romperse en el legacy (`LadderCandidate` interrumpiendo `HANGING` sin pasar por `_release()`).
- Separación en tres capas (tabla fija / perfil activo / contador vivo) es consistente con el patrón de ownership ya usado en V2 (`TraversalLease`: el core no inyecta datos crudos, pasa una credencial y el dueño real resuelve).
- No caer a `NORMAL` en pleno aire al llegar a cero es una buena decisión de feel — evita un cambio de comportamiento sorpresivo a mitad de vuelo.

## Huecos — estado tras la actualización del doc

### 1. El pilar 2 podía estar defendiendo un caso inalcanzable — ✅ RESUELTO

"Solo puede existir un contexto pendiente... debe rechazarse explícitamente o resolverse con una prioridad definida" no decía cuál de las dos, y no quedaba claro si el caso podía ocurrir. Como un solo core de traversal está activo a la vez (regla ya establecida en V2: "un estado activo tiene prioridad"), dos contextos de reentrada antes de que H0 consuma el primero en T+1 no podían llegar nunca.

**Cómo se resolvió:** el doc sacó el pilar completo. Ya no habla de "Tres pilares" sino de "Dos reglas del contrato" (consumo único + cierre del perfil temporal). Correcto — la defensa contra un caso inalcanzable desapareció en vez de quedar como lógica muerta.

### 2. El tick T+1→T+2 no es gratis como dice el doc — ✅ RESUELTO

"Un tick teórico de diferencia no cambia el gameplay" quedaba como una afirmación sin decisión explícita detrás. Si el contador de 0.75s se carga en T+1 y empieza a descontarse ese mismo tick, mientras Body todavía prioriza el launch pendiente y el jugador no tiene control horizontal real hasta T+2, se pierde ese primer tick de ventana útil. Mismo tipo de detalle que costó horas de debugging en Fase 4/5 de V2 (orden Controller→Motor).

**Cómo se resolvió:** el doc agregó "Decisión cerrada — inicio del contador": el contador arranca deliberadamente en T+1, aunque el primer control horizontal efectivo llegue en T+2, con la razón explícita (evitar acoplar H0 a una confirmación de `launch` es más simple y estable que el tick perdido). Ya no es una afirmación implícita — es una decisión con trade-off nombrado. `h0_core.gd:64-70` (`reset_air_control()`) sigue siendo el mecanismo de un solo perfil; el handshake de dos perfiles todavía no está implementado, pero el punto de diseño ya no está abierto.

### 3. "Launch pendiente" no estaba definido — ✅ RESUELTO

V2 tiene un mecanismo de salida con velocidad (`end_traversal(lease, exit_velocity, reason)`), y las decisiones de diseño de Hanging V3 dicen que el salto de salida apunta hacia la cámara. No quedaba claro si "launch pendiente" era ese mismo `exit_velocity` reusado o un concepto nuevo paralelo.

**Cómo se resolvió:** el doc agregó "`launch` es el comando de lanzamiento propio de `V3PhysicsBody`". Confirmado contra código, no es aspiracional: `v3_physics_body.gd:88` ya tiene `submit_launch(source, launch_velocity)` con consumo único (`_has_pending_launch`). Es un mecanismo propio de V3, separado del `exit_velocity` de `TraversalLease` de V2 — arquitecturas distintas, no hay duplicación real.

### 4. Frontera de switchboard sin mencionar — ✅ RESUELTO, con una nota de consistencia

Las decisiones de diseño de Hanging V3 dicen que el switchboard "se consulta en la frontera de cada transición". Esta reentrada ES una frontera de transición (Hanging→H0). El doc no lo mencionaba.

**Cómo se resolvió:** el doc agregó "Fuera del diseño: switchboard" — pero no dice que esta transición está exenta del switchboard, dice que **el switchboard fue descartado por completo y ya no forma parte de la arquitectura**. Eso es un alcance más amplio que la pregunta original.

**Nota de consistencia (confirmada 2026-09-22):** el usuario confirmó que el switchboard ya no existe como concepto, en ninguna forma — no es una excepción para esta transición puntual, es un descarte total de la arquitectura. Pendiente real: `docs/parkour/switchboard_sistema_pruebas.md` y `docs/parkour/v3_hanging_captura_sondas_implementada.md` (y cualquier otro doc que asuma `hanging.shimmy`/`hanging.jump_exit`/reenganche vía switchboard) quedaron desactualizados y no se corrigieron todavía — señalar la inconsistencia si se retoma alguno de esos docs.

## Cómo aplicar

Los cuatro puntos dejaron de bloquear el diseño de este doc puntual. Única tarea pendiente real: al retomar `switchboard_sistema_pruebas.md` o la captura de Hanging por sondas, actualizarlos para que no sigan asumiendo un switchboard vigente.
