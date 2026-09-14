# Parkour V3 — fundamento de diseño

## Estado y propósito

Este documento fundamenta por qué existe V3 y qué aprendizajes toma de V1 y V2. No es la especificación completa de V3, no autoriza código y no resuelve todavía la API de movimiento, los módulos concretos ni el orden de implementación.

La hipótesis de trabajo es simple: **V1 conserva información valiosa sobre comportamiento; V2 conserva información valiosa sobre arquitectura; V3 debe usar ambas sin copiar el código ni el modelo completo de ninguno.**

## 1. V3 no es una continuación de V1 ni de V2

V1 y V2 cumplen papeles distintos para V3.

- V1 es una radiografía de comportamiento. Su código, sus mediciones y los playtests sirven para identificar qué respuesta espera el jugador: locomoción ágil, entradas contextuales a un borde, hanging, salidas y demás resultados observables.
- V2 es una fuente de aprendizaje arquitectónico. Separó mejor el motor físico, la detección, las decisiones y los estados activos que V1.

Ninguno de los dos debe migrarse como bloque. Copiar V1 arrastraría escritura física dispersa y estados frágiles. Seguir expandiendo V2 arrastraría un modelo de traversal ya formado que no produjo el comportamiento ni el flujo de trabajo buscados.

Por eso V3 parte de una arquitectura nueva. Su objetivo no es declarar que V1 o V2 fueron inútiles: es conservar de cada uno aquello que quedó demostrado como útil y rechazar aquello que produjo deuda o contradicciones.

## 2. Qué enseña V1

### Hechos observados

La radiografía de V1 muestra que traversal escribía directamente `body.global_position` y anulaba `velocity` durante SNAPPING, HANGING, CLIMBING y LADDER. Esos estados no pasaban por `move_and_slide()`, `move_and_collide()` ni una validación de ocupación equivalente. También existe evidencia de doble ejecución del traversal, que altera la velocidad efectiva de snap, shimmy y timeouts.

Al mismo tiempo, V1 contiene comportamientos que no deben descartarse por el desorden de su implementación: la locomoción y el control aéreo tienen un perfil concreto; el borde común se detecta mediante probes; el hanging depende del contexto aéreo; y el shimmy explora continuidad geométrica en lugar de exigir una ruta authorizada para cada borde normal.

### Consecuencia para V3

V1 será una fuente de evidencia, no una plantilla de código.

V3 puede recuperar un resultado observable de V1 sólo después de identificarlo como hecho o medirlo en playtest. No hereda automáticamente sus escrituras directas de transform, su doble procesamiento, sus rutas de debug desconectadas ni sus faltas de validación física.

Esto separa dos preguntas que V1 mezcla: “¿qué se sentía bien?” y “¿cómo estaba programado?”. La primera puede ser un contrato de V3; la segunda no tiene autoridad por sí sola.

## 3. Qué enseña V2

### Avances que se conservan

V2 demuestra varias separaciones de responsabilidad que V3 debe preservar como principios:

- `PlayerMotor` concentra velocity, postura, collider y la aplicación física de movimiento.
- `TraversalDetector` hace consultas físicas y produce candidatos sin leer input, cambiar estado ni mover el cuerpo.
- `TraversalResolver` arbitra candidatos desde un contexto tipado sin consultar la escena ni mover al player.
- `TraversalLease` identifica un dueño exclusivo, guarda una última pose segura y sólo puede ser invalidado por el motor.

Estas piezas responden a problemas reales de V1: más de una autoridad física, decisiones mezcladas con probes y dificultad para reproducir por qué una acción se activó o falló.

### Límites que V3 no replica

La implementación actual de V2 reúne Hanging, Mantling, Direct Mantle, Ladder, shimmy, cooldowns, lectura de input y políticas de cámara dentro de `TraversalController`. Además, Direct Mantle necesita una ruta propia fuera del resolver y el detector vincula shimmy de borde a `TraversalSegment.Type.LEDGE`.

Eso no invalida las piezas anteriores; muestra que una buena separación inicial puede perderse si las mecánicas siguen acumulándose en un controlador central y si se agregan excepciones para resolver casos particulares.

### Consecuencia para V3

V3 conserva las responsabilidades bien separadas de V2, pero no su composición final de traversal. Los comportamientos de parkour se diseñarán como módulos con estados y reglas propios, sobre infraestructura física, lectura de mundo, arbitraje y telemetría compartidas.

Esta afirmación no decide todavía cómo un módulo solicita movimiento al motor, qué módulos existen primero ni si Mantle pertenece a Hanging, Vault o a otro módulo. Esas son decisiones posteriores y deben justificarse por separado.

## Fuentes de este fundamento

- `docs/parkour/v1_behavioral_reference.md`
- `docs/parkour/v1_forensic_technical_map.md`
- `scripts/player_v2/player_motor.gd`
- `scripts/player_v2/traversal/traversal_detector.gd`
- `scripts/player_v2/traversal/traversal_resolver.gd`
- `scripts/player_v2/traversal/traversal_lease.gd`
- `scripts/player_v2/traversal/traversal_controller.gd`
