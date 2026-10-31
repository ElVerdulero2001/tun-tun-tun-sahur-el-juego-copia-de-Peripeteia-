# V3 Hanging — revisión del plan funcional mínimo

Revisión de `v3_hanging_plan_funcional_minimo.md` contrastada con el código actual del laboratorio (`V3PhysicsBody`, `H0Core`, `V3HangingCandidateEvaluator`, `v3_hanging_detection_lab.tscn`).

**Veredicto:** el plan es viable para el objetivo de "que exista". La frontera (body como único escritor, compuerta local en H0, NodePaths, sin autoloads) encaja con el código. Antes de implementar hay que incorporar las correcciones de abajo.

## Correcciones al plan

### 1. Recaptura inmediata al soltar

- **Problema:** al soltar en el aire frente a la pared, la intención pasa a neutra. La candidata vuelve a ser válida y, como el personaje cae, el core lo reagarra en el mismo tick.
- **Decisión del usuario:**
  - Si sale con crouch (Ctrl) o con `move_back`, no puede reagarrar hasta pulsar salto de nuevo (`jump_just_pressed`).
  - Si sale con salto (espacio), no hay restricción y puede reengancharse.
  - Tocar piso limpia cualquier bloqueo.
- **Consecuencia:** `V3InputSource` hoy no expone `jump_just_pressed`; hay que agregarlo.

### 2. La retención no debe depender de `last_candidate`

- **Problema:** la pose de agarre deja al body a 1.5 m bajo el borde, igual que `max_edge_height = 1.5`. Con ruido de float el jugador se suelta sin motivo. Además, `intencion_contradictoria` invalida la candidata y mezclaría "atrás" con "pérdida de borde".
- **Propuesta:** en `HANGING`, validar solo con `can_occupy_pose(held_pose)` más un raycast corto al `edge_point` guardado, o subir `max_edge_height` a ~1.7.
- **Decisión:** criterio del implementador (es un experimento).

### 3. `can_occupy_pose`

- **Problema:** `test_move(pose, Vector3.ZERO)` puede no detectar solape inicial de forma fiable.
- **Propuesta:** `PhysicsDirectSpaceState3D.intersect_shape` con la cápsula, o `test_move` con un desplazamiento mínimo. Si entra agachado en el aire, probar y aplicar la forma de pie.
- **Decisión:** criterio del implementador.

### 4. Fuente de intención durante el colgado

- **Problema:** el snap no pasa por `submit_motion_intent`, así que `last_intent_source_name` quedaría en "ninguno" y el smoke test (paso 5) fallaría.
- **Propuesta:** el body registra el nombre de la fuente del snap.
- **Decisión:** criterio del implementador.

## Aclaraciones menores

- El origen del body está en los pies (la cápsula se centra en `height*0.5`). `top_pose` debería ser `edge_point - wall_normal*margen + UP*epsilon`, no `altura_del_root`.
- En `HANGING` el body debe saltarse `move_and_slide` y la gravedad, no solo poner la velocidad a cero.
- Prioridades: H0 = 0, body = 100, evaluator = 150, core = 160. Funciona, con el snap aplicado un tick después, como el plan ya asume.
- El yaw vive en `CameraPivot`, no en el Body. El snap solo debe escribir posición y base del body sin arrastrar la cámara.

## Estado

Solo hubo lectura y análisis; no se modificó código. La implementación no arranca hasta que el usuario dé el visto bueno.
