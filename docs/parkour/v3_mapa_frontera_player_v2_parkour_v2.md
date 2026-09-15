# V3 — Mapa de frontera: Player V2 y Parkour V2

## Propósito

Este mapa separa el **host Player V2**, que se conserva, del **Parkour V2**, que será reemplazado por V3. Es un inventario de dependencias actuales; no autoriza a borrar, mover ni reescribir componentes por sí solo.

La conclusión de partida es importante: no se crea un “Player V3”. El player actual conserva sus sistemas ajenos al parkour y V3 sustituye únicamente la porción de parkour.

## Estado de implementación actual

Ya existe un laboratorio H0 aislado, pero **no está integrado todavía en Player V2**:

```text
scenes/test/v3_h0_lab.tscn
scripts/player_v2/parkour_v3/
```

Ese laboratorio valida la frontera `H0 → capa física → hechos publicados` con locomoción, sprint, salto, caída, crouch y debug propios. No instancia `PlayerV2.tscn`, no importa `traversal/` y no modifica `player_motor.gd`. Por lo tanto, Player V2 y Parkour V2 siguen siendo el flujo activo del proyecto hasta una integración futura y deliberada.

## Host Player V2 que se conserva

La escena `scenes/player_v2/player_v2.tscn` contiene estas piezas que no son Parkour V2 en sí mismas:

```text
PlayerV2 (Node3D)
├── Inventory / InventoryAuthority / InventoryReceiver
├── ItemDropper
├── PlayerInventoryUI
└── Body (CharacterBody3D)
    ├── CollisionShape3D
    ├── DropPoint
    ├── View
    │   └── Camera3D
    └── Interaction
```

Inventario, UI, interacción, punto para soltar ítems, cuerpo físico, collider, vista y cámara forman parte del host reutilizable. Sus scripts no deben clasificarse como basura de Parkour V2 sólo porque cuelguen de `player_v2`.

Los niveles `levels/movement_test.tscn` y `levels/test_level.tscn` instancian este player. El primero es además la escena principal actual del proyecto.

## Parkour V2 explícito dentro de la escena del player

La misma escena agrega dos nodos exclusivamente de Parkour V2 debajo de `Body`:

```text
Body
├── TraversalDetector   → scripts/player_v2/traversal/traversal_detector.gd
└── TraversalController → scripts/player_v2/traversal/traversal_controller.gd
```

`TraversalDetector` consulta candidatos de borde y escalera V2. `TraversalController` ejecuta la máquina V2 de Hanging, Mantle, Ladder y sus salidas. Estos dos nodos son la unión visible entre el host y Parkour V2.

## `player_motor.gd`: archivo mixto

`scripts/player_v2/player_motor.gd` no debe archivarse completo ni conservarse sin revisión: contiene dos responsabilidades mezcladas.

| Zona actual | Qué contiene | Clasificación para V3 |
| --- | --- | --- |
| Inicio hasta `_puede_pararse()` | Input directo, mouse-look, caminar, correr, salto, caída, crouch, collider y `move_and_slide()` | Locomoción/base del player. El comportamiento actual no se hereda automáticamente: V3 lo reemplaza por H0 + capa física, pero el body, collider y referencias de escena se conservan. |
| `snapshot()` | Expone suelo, velocidad, postura y posibilidad de pararse mediante `MotorSnapshot` | Puente V2. La idea de publicar hechos sirve para V3, pero `MotorSnapshot` es un tipo de Parkour V2 y no debe convertirse en contrato V3 por inercia. |
| `_lease`, `begin_traversal`, `apply_traversal_pose`, `activar_yaw_arco`, `end_traversal` y helpers | Exclusión mediante lease, poses guiadas, arco de cámara y salidas de traversal | Parkour V2 puro. Se reemplaza por la autoridad física reactiva de V3; no se adapta como contrato de V3. |
| Rama de `physics_tick()` que pausa locomoción con un lease | Alternancia entre locomoción normal y TraversalController | Parkour V2 puro. V3 deberá aplicar su propia regla de un solo core gobernador. |

La consecuencia práctica: V3 puede reutilizar el `CharacterBody3D` de Player V2, pero no puede declarar que el `PlayerMotor` actual ya sea la capa física V3. Primero hay que extraer o reemplazar sus decisiones de locomoción/traversal sin tocar los sistemas ajenos al parkour.

## Árbol de Parkour V2 a aislar

El directorio `scripts/player_v2/traversal/` es Parkour V2. Contiene:

```text
traversal_controller.gd   traversal_detector.gd   traversal_resolver.gd
traversal_state.gd        traversal_decision.gd   traversal_context.gd
traversal_intent.gd       traversal_opportunities.gd
traversal_lease.gd        traversal_move_result.gd
traversal_exit_reason.gd  traversal_debug.gd
traversal_segment.gd      segment_progress.gd
ledge_candidate.gd        ladder_candidate.gd    motor_snapshot.gd
```

No es un módulo reutilizable de V3: contiene un resolver central, contratos de segmento de escena, leases, candidatos específicos y ejecución por poses de V2. Puede conservarse como archivo histórico o referencia, pero no como dependencia activa del prototipo H0-only.

## Escenas, props y pruebas afectadas

### Parkour V2 puro

- `scenes/test/parkour_playground.tscn`
- `scenes/test/v2_comparison_p0.tscn`
- `scenes/test/traversal_controller_test.*`
- `scenes/test/traversal_detector_test.*`
- `scenes/test/traversal_resolver_test.*`
- `scenes/test/traversal_debug_test.*`
- `scenes/props/static/escalera_fea_v_1.tscn`

La escena de escalera depende de `TraversalSegment`; las escaleras instanciadas en `levels/movement_test.tscn` son por lo tanto contenido de Parkour V2, aunque el nivel y sus demás props no lo sean.

### Mixto o dependiente del host

- `scenes/player_v2/player_v2.tscn`: conserva el host, pero deberá dejar de instanciar los dos nodos V2 cuando V3 los reemplace.
- `scripts/player_v2/player_motor.gd`: mezcla base reutilizable y Parkour V2; requiere separación, no traslado completo.
- `scenes/test/player_motor_test.*`: prueba tanto locomoción como el contrato de lease V2; no puede considerarse una prueba limpia de H0.
- `levels/movement_test.tscn`: conserva mundo, props, inventario e interacción, pero hoy contiene Player V2 con Parkour V2 y escaleras V2.
- `levels/test_level.tscn`: instancia Player V2; hereda los dos nodos V2 a través de esa escena, aunque no declare traversal por separado.

### No clasificar como Parkour V2

Los sistemas de inventario, interacción, UI, ítems, props generales, transporte y assets no son Parkour V2. Algunas búsquedas mencionan `PlayerMotor` o `TraversalController` sólo en comentarios históricos; eso no constituye una dependencia de ejecución.

## Dependencias directas verificadas

Los únicos recursos de escena que cargan directamente scripts del directorio `traversal/` son el player, las pruebas de traversal, el playground/comparación y la prop de escalera. La relación central actual es:

```text
PlayerV2.tscn
  └── Body / PlayerMotor
        ├── TraversalDetector
        └── TraversalController
              └── APIs V2 de PlayerMotor y tipos de traversal/

movement_test.tscn y test_level.tscn
  └── instancian PlayerV2.tscn
```

## Implicación para la limpieza y la migración

No corresponde mover `player_v2/` entero. La secuencia segura será:

1. Crear Parkour V3 junto al host, sin importar `traversal/`.
2. Reemplazar en `PlayerV2.tscn` los dos nodos de Parkour V2 por los componentes V3 cuando H0 tenga una rebanada funcional.
3. Separar de `player_motor.gd` las APIs y tipos exclusivos de traversal V2, sin afectar Body, inventario, interacción o cámara compartida.
4. Sólo cuando no queden referencias activas, archivar las escenas, pruebas, props y scripts de Parkour V2.

Mientras esa sustitución no exista, archivar `traversal/` o las escenas V2 rompería la escena principal actual. Por eso este mapa no ejecuta todavía una limpieza física.
