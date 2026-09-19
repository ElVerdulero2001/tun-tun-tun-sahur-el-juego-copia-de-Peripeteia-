# V3 Hanging — plan funcional mínimo

> **Objetivo:** conseguir un ciclo completo y jugable de Hanging en el
> laboratorio V3: detectar un borde, capturarlo, retener al personaje,
> soltarlo o subirlo, y devolver siempre la locomoción a H0.
>
> **Prioridad:** funcionamiento observable por encima de pureza arquitectónica.
> Se aceptan snaps, poses de valores fijos y asistencias de captura. La única
> restricción de integración es no usar autoloads ni singletons.

## Resultado esperado

En `v3_hanging_detection_lab.tscn`, el jugador debe poder saltar hacia la
cornisa de práctica y obtener este ciclo:

```text
H0 controla el aire
  → se detecta borde válido
  → Hanging toma control y hace snap a la pose de agarre
  → el jugador queda retenido
  → atrás/crouch: suelta y vuelve a H0
  → adelante/salto: intenta subir y vuelve a H0 arriba
```

No se requiere shimmy, animación, soporte móvil perfecto, interpolación ni
integración todavía con `PlayerV2` legacy.

## Alcance y frontera

La implementación queda encerrada en el laboratorio V3. Se reutilizan los
providers existentes y el evaluator; no se modifican escenas de gameplay ni
se introduce estado global.

```text
V3InputSource ─┐
H0Core ────────┼──> V3PhysicsBody <── V3HangingCore
               │          ^
providers ──> Evaluator ──┘
```

Las dependencias serán `@export` con `NodePath` desde
`v3_hanging_detection_lab.tscn`:

- `V3HangingCore` conoce directamente `H0Core`, `V3PhysicsBody`,
  `V3InputSource` y `V3HangingCandidateEvaluator`.
- `H0Core` no conoce Hanging; sólo expone una compuerta local para suspender
  su publicación de locomoción.
- `V3PhysicsBody` sigue siendo el único escritor de `global_transform`,
  `velocity` y el único que llama a `move_and_slide()`.

No habrá `autoload`, `get_node("/root/...")`, grupos usados como bus de
mensajes ni estado estático compartido.

## Estado actual reutilizable

Se conserva la cadena ya presente:

```text
ForwardWallProbe + TopSurfaceProbe + FrontVolumeProbe
  → V3HangingCandidateEvaluator
  → V3HangingCandidate válido o rechazado
```

El evaluator ya entrega pared, normal, punto de borde, altura relativa,
alineación e intención. Es suficiente para una primera captura automática.
No es necesario volver a introducir C/S para cerrar el ciclo funcional.

## Cambios de implementación

### 1. Candidata con pose de agarre

Extender `V3HangingCandidate` con:

- `has_hang_pose: bool`
- `hang_pose: Transform3D`
- `hang_pose_clear: bool`
- `support_collider: Object` u otro identificador de debug si está
  disponible en el impacto.

`V3HangingCandidateEvaluator` construirá una pose temporal a partir del borde
aceptado:

```text
P.origen = edge_point + wall_normal * 0.68 + UP * -1.50
P.basis  = orientación cuyo frente mira hacia la pared
```

Los valores son deliberadamente fijos porque ya fueron usados en el
laboratorio anterior. Deben ser exports del evaluator para poder ajustarlos
en Inspector sin rediseñar la mecánica.

El evaluator consulta a física si `P` es ocupable y publica el resultado. Una
candidata geométricamente válida puede seguir existiendo aunque la pose no
quepa; el core de Hanging simplemente no podrá capturarla.

### 2. Snap local en la capa física

Agregar a `V3PhysicsBody`:

```gdscript
func can_occupy_pose(target_pose: Transform3D) -> bool
func submit_pose_snap(source: Object, target_pose: Transform3D) -> bool
```

`submit_pose_snap()` guarda una solicitud para el siguiente `_physics_process`
del body. Al procesarla:

1. vuelve a comprobar `can_occupy_pose(target_pose)`;
2. si cabe, asigna `global_transform = target_pose` y `velocity = Vector3.ZERO`;
3. limpia la intención H0 pendiente y no ejecuta locomoción normal en ese tick;
4. si no cabe, no mueve y expone un hecho de fallo para debug.

La validación puede ser sólo estática con `test_move(target_pose, Vector3.ZERO)`.
No se exige barrido de trayectoria para esta versión: el snap es una asistencia
de captura intencional.

El body debe rechazar dos snaps incompatibles de fuentes distintas dentro del
mismo tick. En este laboratorio sólo `V3HangingCore` será fuente de snaps.

### 3. Compuerta explícita de H0

Agregar a `H0Core` una bandera local, por ejemplo
`locomotion_suspended := false`, y una API pequeña:

```gdscript
func set_locomotion_suspended(value: bool) -> void
```

Si está suspendido, H0 no llama a `submit_motion_intent()`. Puede conservar sus
campos de debug; no necesita reinicializar todo su estado interno.

Esto permite que Hanging tome el control de forma visible y elimina el caso en
que H0 sigue emitiendo movimiento y el snap gana sólo por prioridad.

### 4. Core local de Hanging

Crear `scripts/player_v2/parkour_v3/v3_hanging_core.gd`.

Su estado mínimo es:

```gdscript
enum State { INACTIVE, HANGING }
```

Campos de telemetría recomendados:

- `state`
- `held_pose`
- `last_entry_reason`
- `last_exit_reason`
- `last_snap_accepted`

Orden de proceso propuesto: prioridad `160`, inmediatamente después del
evaluator (`150`). El snap solicitado ahí se aplica en la física del tick
siguiente, lo cual es aceptable y predecible.

#### Entrada

En `INACTIVE`, entrar si se cumplen todos estos requisitos:

1. `candidate.is_valid`;
2. `candidate.has_hang_pose`;
3. `candidate.hang_pose_clear`;
4. el personaje está en aire;
5. el personaje cae o no asciende rápido (`velocity.y <= umbral_exportado`).

Al entrar, el core guarda `held_pose = candidate.hang_pose`, suspende H0 y
solicita `submit_pose_snap(self, held_pose)`.

La captura es automática y deliberadamente tolerante. La sonda frontal ya
limita la distancia y la intención contraria ya invalida la candidata. Si el
resultado se siente demasiado magnético, C/S puede agregarse después como
otra condición, sin modificar el gobierno ni las salidas.

#### Retención

En `HANGING`:

1. solicita el snap a `held_pose` cada tick;
2. conserva H0 suspendido;
3. fuerza velocidad cero a través del snap;
4. comprueba que la pose siga siendo ocupable y que exista una geometría de
   borde compatible.

Para la primera versión se permite retener la pose mundial guardada. La
reconstrucción respecto de plataformas móviles queda explícitamente fuera de
alcance; perder la candidata o no poder ocupar la pose provoca salida segura.

### 5. Salidas

Las salidas son parte obligatoria del primer corte; no puede quedar un latch
que sólo se rompa reiniciando la escena.

| Entrada | Resultado |
| --- | --- |
| `move_back` o crouch | Suelta: cambia a `INACTIVE`, reactiva H0 y no pide más snaps. |
| Pérdida de borde o pose bloqueada | Suelta automática con el mismo retorno a H0. |
| `move_forward` o salto | Intenta subir a una pose de pie sobre la tapa. |

La pose de salida superior puede calcularse de forma cruda desde el borde:

```text
top_pose.origen = edge_point + wall_normal * margen + UP * altura_del_root
```

Sólo se aplica si `can_occupy_pose(top_pose)` es verdadero. Si falla, el core
continúa colgado; no teletransporta dentro de una obstrucción.

Tras una subida exitosa, primero se ejecuta el snap superior y luego se
reactiva H0. Tras soltar, se reactiva H0 de inmediato y la gravedad de H0/body
vuelve a gobernar el siguiente tick.

## Integración de escena

Modificar sólo `scenes/test/v3_hanging_detection_lab.tscn`:

1. declarar el recurso externo de `v3_hanging_core.gd`;
2. agregar un nodo `HangingCore`;
3. cablear sus NodePaths al Body, H0, InputSource y evaluator;
4. conservar providers y overlay existentes;
5. opcionalmente agregar al overlay la referencia al core.

No se añade el core a `scenes/player_v2/player_v2.tscn` durante esta etapa.

## Debug obligatorio

Actualizar `v3_hanging_debug_overlay.gd` para mostrar al menos:

- candidata válida y sus rechazos;
- `HangingCore.state`;
- pose de agarre retenida;
- motivo de última entrada/salida;
- última fuente de intención y si H0 está suspendido;
- snap solicitado, aplicado o rechazado.

El texto debe describir el runtime real: no decir “detección solamente” cuando
ya haya captura y retención activas.

## Verificación

Extender `v3_hanging_detection_smoke_test.gd` para comprobar ejecución real,
no sólo detección:

1. desde piso, hay pared pero no se entra;
2. en aire frente al borde, se publica candidata válida;
3. se entra a `HANGING` y H0 queda suspendido;
4. el body alcanza `held_pose` en el tick físico siguiente;
5. durante varios ticks, el body permanece retenido y el intent source es
   Hanging, no H0;
6. `move_back` o crouch termina Hanging y H0 vuelve a publicar movimiento;
7. una salida superior sólo ocurre si la pose de arriba cabe;
8. retirar/bloquear la geometría de prueba suelta al personaje sin dejar H0
   suspendido.

La prueba se ejecuta en Godot headless junto a los smoke tests V3 existentes.

## Orden de trabajo

1. Añadir pose y ocupación a candidata/evaluator.
2. Añadir API de snap y hechos de resultado a `V3PhysicsBody`.
3. Añadir la compuerta de suspensión a H0.
4. Implementar `V3HangingCore` con entrada, retención y soltado.
5. Cablear el core en el laboratorio.
6. Implementar subida cruda sobre la tapa.
7. Actualizar overlay y smoke test.
8. Ajustar sólo los offsets exportados tras ejecutar la escena.

## Criterio de cierre

El corte está terminado cuando, sin singletons ni autoloads, una escena nueva
del laboratorio permite agarrar la cornisa, permanecer colgado sin movimiento
H0 residual, salir voluntariamente, perder el agarre de forma segura y volver
siempre a locomoción normal.

