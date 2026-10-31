# V3 Hanging — radiografía previa a la limpieza

> **Fecha de lectura:** 2026-09-18.
>
> Describe el runtime que existía antes de retirar cilindro/esfera, P, EntryLab y el snap
> temporal. Se conserva como evidencia de la ruta descartada; para el estado
> actual ver `v3_hanging_laboratorio_mapa_tecnico.md`.

## Resumen real

```text
H0 publica locomoción normal
  ↓
providers crudos: pared + tapa + volumen
  ↓
HangingCandidateEvaluator interpreta una candidata
  ↓
HangingCaptureProbe mide cilindro/esfera
  ↓
HangingEntryLab retiene P y solicita un snap
  ↓
V3PhysicsBody aplica el snap al tick siguiente
```

No existe un core Hanging activo. No hay árbitro, certeza contextual,
concesión de gobierno, salida a H0, soporte metaestable, shimmy, salto desde
Hanging ni movimiento colgado. La retención de P es un experimento conectado
que sí mueve al player.

## Archivos runtime

| Archivo | Clase / uso | Función actual |
| --- | --- | --- |
| `scenes/test/v3_hanging_detection_lab.tscn` | escena | Une H0, una cornisa y la cadena Hanging. |
| `v3_forward_wall_probe.gd` | `V3ForwardWallProbe` | Rayos frontales crudos. |
| `v3_top_surface_probe.gd` | `V3TopSurfaceProbe` | Rayos descendentes crudos. |
| `v3_front_volume_probe.gd` | `V3FrontVolumeProbe` | Colliders crudos de una caja frontal. |
| `v3_hanging_candidate_evaluator.gd` | `V3HangingCandidateEvaluator` | Interpreta los hechos para Hanging. |
| `v3_hanging_candidate.gd` | `V3HangingCandidate` | Resultado/rechazo nuevo por tick. |
| `v3_hanging_capture_probe.gd` | `V3HangingCaptureProbe` | Contacto cilindro/esfera y meshes de debug. |
| `v3_hanging_entry_lab.gd` | `V3HangingEntryLab` | Puente temporal de cilindro/esfera a snap/retención de P. |
| `v3_hanging_debug_overlay.gd` | `V3HangingDebugOverlay` | Texto sin autoridad. |
| `v3_physics_body.gd` | `V3PhysicsBody` | Único escritor del body y aplicador de snap. |
| `h0_core.gd` | `H0Core` | Sigue publicando locomoción normal. |
| `v3_input_source.gd` | `V3InputSource` | Input compartido que lee el evaluator. |
| `v3_camera_rig.gd` | `V3CameraRig` | Orientación compartida y presentación de cámara. |
| `scenes/test/v3_hanging_detection_smoke_test.tscn/.gd` | smoke test | Instancia el laboratorio y verifica la cadena actual. |

Los `.uid` son metadatos de recursos de Godot; no llevan lógica.

## Escena y conexiones

```text
V3HangingDetectionLab
├─ H0Lab (instancia de v3_h0_lab.tscn)
│  ├─ Floor, Wall, CrouchCeiling, luz y entorno
│  ├─ PlayerH0Lab/Body : V3PhysicsBody
│  │  ├─ CollisionShape3D          cápsula radio 0.30 / alto 1.80
│  │  ├─ CameraPivot/View/Camera3D
│  │  ├─ InputSource
│  │  ├─ CameraRig
│  │  ├─ FallDamageState
│  │  └─ H0
│  └─ DebugCanvas/H0Debug
├─ PracticeLedge : StaticBody3D
│  ├─ Mesh                         caja 3 × 1.5 × 0.6 m
│  └─ Collision                    centro (0, 0.75, 0)
├─ ForwardWallProbe
├─ TopSurfaceProbe
├─ FrontVolumeProbe
├─ HangingCandidateEvaluator
├─ HangingCaptureProbe : MeshInstance3D
│  └─ ShoulderSensor               creado en runtime
├─ HangingEntryLab
└─ HangingDebugCanvas/HangingDebug
```

```text
ForwardWallProbe           ← Body + CameraRig
TopSurfaceProbe            ← Body + ForwardWallProbe
FrontVolumeProbe           ← Body + ForwardWallProbe
HangingCandidateEvaluator  ← Body + InputSource + CameraRig + las 3 sondas
HangingCaptureProbe        ← Body + HangingCandidateEvaluator
HangingEntryLab            ← Body + evaluator + CaptureProbe
HangingDebug               ← evaluator + CaptureProbe
```

El único override de escena relevante es
`hanging_body_offset_from_edge_y = -1.5` en el evaluator. El resto son
defaults de script hasta que se guarden cambios desde el Inspector.

## Orden de ejecución

| Prioridad | Pieza | Resultado |
| ---: | --- | --- |
| -200 | `InputSource` | Movimiento, salto sostenido, flanco crouch y sprint. |
| -50 | `FallDamageState` | Estado de caída para H0. |
| 0 | `H0` | Envía intención de locomoción. |
| 100 | `V3PhysicsBody` | Aplica locomoción o snap pendiente. |
| 140 | `ForwardWallProbe` | Reemplaza impactos de pared. |
| 141 | `TopSurfaceProbe` | Reemplaza impactos de tapa. |
| 142 | `FrontVolumeProbe` | Reemplaza hits de volumen. |
| 150 | `HangingCandidateEvaluator` | Reemplaza candidata. |
| 175 | `HangingCaptureProbe` | Recalcula cilindro/esfera. |
| 176 | `HangingEntryLab` | Solicita snap temporal. |
| 200 | `CameraRig` | Presentación de cámara. |
| visual | `HangingDebug` | Sólo texto. |

Un contacto cilindro/esfera pedido en 176 se aplica en prioridad 100 del tick siguiente.
Tras entrar, EntryLab solicita ese mismo snap cada tick.

## Providers tontos

### `V3ForwardWallProbe`

Usa frente planar de cámara; si es nulo, frente planar del body. Lanza cinco
rayos a `0.3, 0.6, 0.9, 1.2, 1.5 m`, con alcance `0.85 m` y excluyendo el RID
del player. Publica:

```text
last_planar_forward
last_wall_samples[] = { height, origin, hit }
```

`hit` lo leen TopSurfaceProbe y evaluator; `last_planar_forward` lo leen
FrontVolumeProbe y evaluator. `height` y `origin` no tienen consumidor ni
visualización actual. La sonda no conoce Hanging ni bordes.

### `V3TopSurfaceProbe`

Por cada impacto de pared consulta hacia abajo desde `body.y + 1.8 m`, separado
`0.08 m` de la pared. Publica:

```text
last_surface_samples[] = { wall_sample_index, wall_hit, top_hit }
```

El evaluator consume `wall_hit` y `top_hit`; `wall_sample_index` no tiene
consumidor actual. No determina horizontalidad, coherencia ni alcance.

### `V3FrontVolumeProbe`

Consulta hasta 16 colliders en una caja `0.7 × 1.2 × 0.85 m` frente al body.
Publica `last_hits` de `intersect_shape()`. El evaluator cuenta esos hits y
ve si contienen el collider de la pared elegida. No tener hits no invalida la
candidata.

## Consumidor: `V3HangingCandidateEvaluator`

Cada tick crea un `V3HangingCandidate` nuevo. Para aceptar un par pared+tapa
descarta impactos ausentes, pared/tapa con inclinación mayor a `30°`, cámara
sin alineación frontal positiva, separación XZ mayor a `0.35 m` y borde fuera
de `0.5–1.5 m` de altura relativa. Entre los pares restantes elige el de mayor
alineación.

Con borde `E` y normal exterior `N` produce:

```text
C_ancla = E - UP × 0.20 m
P.origen = E + N × 0.68 m + UP × (-1.50 m)
```

La base de P mira hacia la pared. P es pose del root del body, no pose visual
ni de cámara. El evaluator guarda `pose_clear = can_occupy_pose(P)`, pero ese
resultado no vuelve inválida la candidata.

El input, relativo a cámara, se clasifica como neutro, compatible o
contradictorio. Sólo contradictorio rechaza la candidata; también se rechaza
por `en_piso`. La evidencia local es rayos `× .50`, alineación `× .25`,
volumen coincidente `× .15` e intención compatible `× .10`. Sólo llega al
debug: no es certeza contextual V3.

### Campos de `V3HangingCandidate`

| Campo | Consumidor actual |
| --- | --- |
| `is_valid` | CaptureProbe, EntryLab, debug y smoke test. |
| `rejection_reasons` | debug y smoke test. |
| `wall_hit_count` | debug, smoke test y evidencia. |
| `wall_normal` | cilindro/esfera, P y debug. |
| `edge_point` | construcción de C/P y debug. |
| `capture_point`, `has_capture_point` | CaptureProbe y debug. |
| `relative_edge_height`, `wall_alignment` | debug; alineación también evidencia. |
| `intent_class` | debug, smoke test y evidencia. |
| `shape_hit_count` | sólo debug. |
| `shape_supports_wall` | debug/evidencia; no modifica validez. |
| `pose`, `pose_clear` | EntryLab y debug; `pose_clear` no modifica validez. |
| `local_evidence_score` | sólo debug. |

## cilindro/esfera: `V3HangingCaptureProbe`

Es un `MeshInstance3D` sin `CollisionShape3D`: sus formas no colisionan con el mundo. Crea un cilindro rosa C y, como hijo, un mesh de esfera azul S.

Sólo se activa con candidata válida y `capture_point`:

```text
eje C       = normal de pared sin Y
centro C    = C_ancla + eje C × (largo C / 2)
centro S    = transform global body × (0, shoulder_height, 0)
```

Con radio/largo C `0.15/0.80 m`, radio S `0.10 m` y altura S `1.30 m`, calcula la distancia al cilindro finito. Si distancia <= radio S, publica que S entra.

Publica `last_zone_active`, centros cilindro/esfera, distancia, solapamiento y `last_sensor_enters_cylinder`. Reinicia todos esos campos cada tick; no guarda historial. Sus meshes, materiales y transforms son sólo visuales.

## Entrada temporal: `V3HangingEntryLab`

Antes de entrar requiere candidata válida, cilindro/esfera entrando ahora, `pose_clear` y `can_occupy_pose(P)` repetido en ese instante.

Si se cumple, copia P a `held_pose`, pone `is_holding_pose = true` y pide `submit_pose_snap()`. A partir de ahí no vuelve a leer candidata, cilindro/esfera, soporte ni P nueva: vuelve a pedir `held_pose` para siempre. No existe código que vuelva `is_holding_pose` a falso; reiniciar la escena es la única salida.

`last_entry_reason` se actualiza con la causa de espera/retención, pero nadie lo muestra, aserta ni consume.

## Efecto físico: `V3PhysicsBody`

`submit_pose_snap(source, target_pose)` guarda un snap pendiente. Si otro origen pide un snap diferente en el mismo tick, falla y advierte. Esta cola es separada de `submit_motion_intent()`.

En prioridad 100, con snap pendiente:

1. vuelve a llamar `can_occupy_pose(target_pose)`;
2. si falla, limpia la intención H0 y no mueve;
3. si pasa, hace `global_transform = target_pose` y `velocity = Vector3.ZERO`;
4. limpia la intención H0 y retorna sin `move_and_slide()`.

`can_occupy_pose()` usa `test_move(pose, Vector3.ZERO, ..., 0.001, true)`: comprueba ocupación estática, no la trayectoria hacia P. H0 sigue ejecutando y su intención desaparece porque el snap tiene prioridad práctica, no porque Hanging haya recibido gobierno formal.

## Infraestructura compartida que afecta Hanging

- `InputSource`: Hanging sólo consume `movement_axis` mediante el evaluator. No existe supresión por Ctrl ni corte general de input en esta ruta.
- `CameraRig`: la cámara entrega frente/derecha planares a H0 y evaluator. cilindro/esfera depende del body, no del pitch/yaw de cámara. El `CameraPivot` permite mirar sin necesariamente rotar body, pero no hay política propia de Hanging.
- `H0`: no conoce Hanging, cilindro/esfera ni EntryLab; envía caminar, sprint, salto y crouch en todos los ticks.

## Debug y prueba

`HangingDebug` muestra conteos, borde, normal, intención, evidencia, C, P y cilindro/esfera. No muestra `is_holding_pose`, `held_pose`, `last_entry_reason`, muestras individuales, snap pendiente/aplicado ni árbitro. El texto aún dice “detección solamente” y “sin movimiento colgado”, aunque la retención temporal existe.

El smoke test verifica: rechazo desde piso, validez en aire neutro, rechazo por `move_back`, entrada de S en C, activación de `is_holding_pose` y body en P al tick siguiente. Su comentario que afirma que P/snap están aislados es viejo: las aserciones confirman que siguen activos.

## Elementos sin uso, sólo visuales o históricos

| Elemento | Estado |
| --- | --- |
| `last_wall_samples[].height`, `.origin` | Publicados, sin consumidor ni visualización. |
| `last_surface_samples[].wall_sample_index` | Publicado, sin consumidor. |
| `local_evidence_score` | Sólo debug; no es certeza ni gatillo. |
| `shape_hit_count` | Sólo debug. |
| `shape_supports_wall` | Debug/evidencia; no cambia validez. |
| `last_entry_reason` | Se escribe; nadie lo lee. |
| meshes rosa/azul y materiales | Visuales, sin colisión física. |
| `v3_hanging_entrada_laboratorio_estado_actual.md` | Histórico desactualizado: dice que EntryLab no está instanciado. |
| `v3_hanging_deteccion_propuesta.md` | Propuesta; no refleja el snap conectado. |
| `v3_hanging_*_feedback.md` y `*_problema.md` | Registro de discusión, no runtime. |
| `v3_hanging_detector.gd` | Ya no existe: fue reemplazado por providers y evaluator. |

## Cierre

La detección ya separa lectura tonta e interpretación Hanging. Todo lo que ocurre después de candidata —cilindro/esfera, P, snap y retención— sigue siendo laboratorio temporal. Para los huecos de filosofía que bloquean volver a avanzar, ver `v3_hanging_auditoria_huecos_y_fallas_filosoficas.md`.
