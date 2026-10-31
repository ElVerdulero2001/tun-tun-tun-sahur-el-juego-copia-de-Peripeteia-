# V3 Hanging — implementación mínima actual

> **Estado:** implementación detenida a pedido del usuario.
>
> **Propósito de este documento:** describir exactamente el circuito que quedó
> funcionando en el laboratorio V3: sus scripts, conexiones, orden de tick,
> entradas, salidas y límites. No es una propuesta de arquitectura futura.

## Qué existe

El laboratorio permite:

1. detectar una pared con borde superior mientras el player está en aire;
2. construir una pose de agarre fija;
3. capturar al player mediante un snap físico;
4. suspender H0 mientras Hanging gobierna;
5. mantener la pose colgada;
6. desplazarse lateralmente con `A/D` sin pasar los extremos del muro;
7. soltar con `S`/`move_back` o Ctrl;
8. salir con Espacio mediante un salto estrictamente vertical;
9. devolver siempre la locomoción a H0.

No existen aún animaciones, mantle/subida a la tapa, shimmy sobre geometría
móvil, interpolación, soporte persistente asociado a un collider ni integración
con `PlayerV2` legacy.

## Escena que contiene el experimento

Archivo: `scenes/test/v3_hanging_detection_lab.tscn`.

```text
V3HangingDetectionLab
├─ H0Lab (instancia de v3_h0_lab.tscn)
│  └─ PlayerH0Lab/Body : V3PhysicsBody
│     ├─ InputSource : V3InputSource
│     ├─ CameraRig : V3CameraRig
│     └─ H0 : H0Core
├─ PracticeLedge : StaticBody3D
├─ ForwardWallProbe : V3ForwardWallProbe
├─ TopSurfaceProbe : V3TopSurfaceProbe
├─ FrontVolumeProbe : V3FrontVolumeProbe
├─ HangingCandidateEvaluator : V3HangingCandidateEvaluator
├─ HangingCore : V3HangingCore
└─ HangingDebug : V3HangingDebugOverlay
```

`PracticeLedge` es una caja de `3 × 1.5 × 0.6 m`; es la cornisa de prueba.
Los `NodePath` de cada nodo están guardados en la escena. Hanging no usa
autoloads, singletons, grupos como bus de mensajes ni búsquedas desde `/root`.

## Flujo completo

```text
InputSource
  ↓
H0 publica locomoción normal ───────────┐
  ↓                                     │
V3PhysicsBody aplica movimiento H0      │
  ↓                                     │
probes leen pared/tapa/volumen           │
  ↓                                     │
CandidateEvaluator publica candidata     │
  ↓                                     │
HangingCore entra y suspende H0          │
  ↓                                     │
V3PhysicsBody aplica snap o lanzamiento ←┘
```

Mientras Hanging está activo, el flujo normal de H0 se corta antes de que H0
llame a `submit_motion_intent()`. `V3PhysicsBody` sigue siendo el único nodo
que escribe `global_transform`, `velocity` o llama a `move_and_slide()`.

## Orden de ejecución físico

| Prioridad | Nodo | Responsabilidad |
| ---: | --- | --- |
| -200 | `V3InputSource` | Lee acciones de input. |
| 0 | `H0Core` | Publica movimiento normal si no fue suspendido. |
| 100 | `V3PhysicsBody` | Ejecuta movimiento, snap o lanzamiento pendiente. |
| 140 | `V3ForwardWallProbe` | Publica impactos crudos contra pared. |
| 141 | `V3TopSurfaceProbe` | Publica impactos descendentes hacia la tapa. |
| 142 | `V3FrontVolumeProbe` | Publica volumen frontal de debug. |
| 150 | `V3HangingCandidateEvaluator` | Publica la candidata de Hanging. |
| 160 | `V3HangingCore` | Entra, retiene, mueve lateralmente o sale. |
| 200 | `V3CameraRig` | Actualiza presentación de cámara. |

Una orden emitida por `HangingCore` en prioridad 160 se consume por el body en
prioridad 100 del tick siguiente. Es intencional: evita que Hanging escriba el
body directamente.

## Scripts y responsabilidades

### `v3_input_source.gd` — `V3InputSource`

Lee y publica los datos voluntarios compartidos:

- `movement_axis`: movimiento con WASD;
- `jump_pressed`: Espacio sostenido;
- `jump_just_pressed`: flanco de Espacio;
- `crouch_just_pressed`: flanco de Ctrl;
- `sprint_active`: Shift.

No conoce Hanging ni H0. `jump_just_pressed` se agregó para distinguir una
pulsación nueva de salto de una tecla mantenida.

### `h0_core.gd` — `H0Core`

Mantiene la locomoción normal de piso/aire. Se añadió:

```gdscript
var locomotion_suspended := false
func set_locomotion_suspended(value: bool) -> void
```

Si `locomotion_suspended` es verdadero, H0 no publica una intención física.
`HangingCore` llama a esta API local al entrar y salir. H0 no tiene una
referencia inversa a Hanging.

### `v3_forward_wall_probe.gd` — `V3ForwardWallProbe`

Lanza cinco rayos hacia el frente planar de cámara. Publica `last_wall_samples`
y `last_planar_forward`. Es una sonda cruda; no decide si el borde es usable.

### `v3_top_surface_probe.gd` — `V3TopSurfaceProbe`

Para cada pared detectada, lanza un rayo hacia abajo desde una altura fija.
Publica pares `wall_hit`/`top_hit`. Es una sonda cruda; no crea poses.

### `v3_front_volume_probe.gd` — `V3FrontVolumeProbe`

Publica colisiones de un volumen frontal. En el corte actual se conserva para
debug y observación; no interviene en la decisión de entrada.

### `v3_hanging_candidate.gd` — `V3HangingCandidate`

Es el resultado nuevo de cada tick. Además de pared, borde, altura, alineación
e intención, ahora contiene:

- `hang_pose`: `Transform3D` de agarre;
- `has_hang_pose`: confirma que se pudo construir;
- `hang_pose_clear`: confirma que la cápsula actual cabe en ese destino.

No mueve el player ni guarda estado de una captura anterior.

### `v3_hanging_candidate_evaluator.gd` — `V3HangingCandidateEvaluator`

Consume input, cámara, body y los providers de pared/tapa. Acepta una candidata
si encuentra una pared vertical, una tapa suficientemente horizontal, ambas
lecturas son coherentes en XZ, el borde está entre `0.5` y `1.5 m`, el player
no está en piso y el input no expresa una intención contraria.

Luego calcula la pose P del laboratorio:

```text
P.origen = edge_point
         + wall_normal * 0.68
         + UP * -1.50
P.basis  = la -Z local mira hacia la pared
```

Los offsets son exports:

- `hang_body_offset_from_wall = 0.68`;
- `hang_body_offset_from_edge_y = -1.50`.

Finalmente llama a `physics_body.can_occupy_pose(P)` y guarda el resultado en
`hang_pose_clear`. La pose bloqueada no invalida la geometría; simplemente
impide que Hanging entre.

### `v3_physics_body.gd` — `V3PhysicsBody`

Es la capa física compartida y el único escritor del `CharacterBody3D`.
Recibe tres tipos de comando local:

| API | Emisor actual | Efecto en el tick físico siguiente |
| --- | --- | --- |
| `submit_motion_intent(...)` | H0 | Movimiento normal, salto de piso y crouch. |
| `submit_pose_snap(...)` | Hanging | Si la pose cabe, asigna `global_transform`, pone velocidad cero y no llama a `move_and_slide()`. |
| `submit_launch(...)` | Hanging | Aplica una velocidad inicial y llama a `move_and_slide()`. |

La prioridad física interna es snap, luego lanzamiento y finalmente movimiento
normal. Al consumir un snap o lanzamiento, el body limpia la intención H0 que
pudiera haber quedado pendiente.

`can_occupy_pose(pose)` usa:

```gdscript
not test_move(pose, Vector3.ZERO, null, 0.001, true)
```

Es una comprobación estática de destino. No hace barrido entre la posición
actual y la pose; es un atajo aceptado para este laboratorio.

Para diagnóstico, `get_physics_facts()` publica ahora el tipo de orden,
autoridad, y si el último snap o lanzamiento fue pedido/aceptado.

### `v3_hanging_core.gd` — `V3HangingCore`

Es el nodo nuevo que implementa el ciclo. Recibe por `@export`:

- `h0: H0Core`;
- `physics_body: V3PhysicsBody`;
- `input_source: V3InputSource`;
- `candidate_evaluator: V3HangingCandidateEvaluator`.

Tiene dos estados:

```text
INACTIVE = 0
HANGING  = 1
```

Su estado visible incluye `held_pose`, `held_edge_point`, `held_wall_normal`,
`recapture_locked`, motivos de última entrada/salida y
`last_lateral_blocked`.

#### Entrada

En `INACTIVE`, entra si:

1. no hay bloqueo de recaptura;
2. el evaluator produjo una candidata válida con pose;
3. `hang_pose_clear` es verdadero;
4. el player no está ascendiendo con velocidad mayor a `0.5 m/s`.

Al entrar copia la pose, borde y normal de candidata; cambia a `HANGING`, llama
`h0.set_locomotion_suspended(true)` y solicita el snap de P.

#### Retención

En `HANGING`, pide `submit_pose_snap(self, held_pose)` cada tick. Si el body
reporta que el snap anterior fue rechazado, libera Hanging y devuelve H0.

La retención usa la pose mundial guardada. No reconstruye una relación con una
plataforma móvil y no vuelve a usar `last_candidate` para decidir si continúa;
esto evita que input lateral o atrás provoque una falsa pérdida de agarre.

#### Movimiento lateral

`movement_axis.x` mueve la pose a `lateral_speed = 2.0 m/s` sobre
`held_pose.basis.x`. La base del body mira hacia la pared, por lo que su eje X
es tangente a ella.

Antes de aceptar el destino lateral, `_has_lateral_wall_support()` lanza un
rayo desde `1.0 m` sobre el root hacia la pared durante `1.0 m`. Sólo acepta
el desplazamiento si:

1. el rayo encuentra una superficie;
2. la normal encontrada coincide con la normal guardada (`dot >= 0.8`);
3. `can_occupy_pose()` confirma que la cápsula cabe.

Si la pared termina, el rayo deja de encontrar la cara frontal y el shimmy se
detiene. El estado no sale de Hanging; `last_lateral_blocked` queda en `true`
para el debug.

#### Salida con atrás o Ctrl

`move_back` (eje Y positivo mayor a `0.2`) o Ctrl llaman a `_release()`:

- el estado vuelve a `INACTIVE`;
- H0 se reactiva;
- `recapture_locked` se vuelve verdadero.

El bloqueo evita que, al soltar frente al mismo muro, el player sea capturado
otra vez automáticamente. Se limpia al tocar piso o con `jump_just_pressed`.

#### Salida con Espacio

Si Espacio se pulsa estando en `HANGING`:

- el estado vuelve a `INACTIVE`;
- H0 se reactiva;
- no se activa bloqueo de recaptura;
- el core pide `submit_launch(self, Vector3.UP * 5.0)`.

El lanzamiento no tiene componente X/Z: el salto es exclusivamente vertical.

### `v3_hanging_debug_overlay.gd` — `V3HangingDebugOverlay`

Muestra proveedores, candidata, si P está libre, estado del core, bloqueo de
recaptura, motivo de última entrada/salida y si el movimiento lateral fue
bloqueado. La referencia a `HangingCore` se guarda como `Node` sin tipo global
para que Godot pueda cargar la escena aunque el script nuevo todavía no esté
indexado en su caché de clases.

## Controles actuales

| Entrada | Fuera de Hanging | En Hanging |
| --- | --- | --- |
| `W/A/S/D` | Movimiento H0 | `A/D`: desplazamiento lateral; `S`: soltar. |
| Ctrl | Crouch H0 | Soltar y bloquear recaptura automática. |
| Espacio | Salto H0 en piso | Salida vertical de Hanging. |

No hay subida a la tapa con `W` o Espacio en este corte.

## Prueba automatizada

Archivo: `scenes/test/v3_hanging_detection_smoke_test.gd`, instanciado por
`scenes/test/v3_hanging_detection_smoke_test.tscn`.

El smoke test ejecuta y verifica:

1. el borde es visible pero no se entra desde piso;
2. una candidata aérea entra a Hanging;
3. H0 queda suspendido y el body acepta el snap;
4. la pose se retiene varios ticks;
5. `A/D` desplaza el player;
6. el límite lateral de la cornisa bloquea el desplazamiento sin soltar;
7. atrás suelta, devuelve H0 y bloquea recaptura;
8. un salto nuevo rearma la captura;
9. Espacio en Hanging sale con un lanzamiento vertical sin velocidad X/Z.

Se ejecutó en Godot headless con:

```powershell
& 'C:\Godot\4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path . `
  --scene scenes/test/v3_hanging_detection_smoke_test.tscn
```

El test terminó con código `0` después de cada cambio descrito.

## Límites conocidos del corte

- El snap es teletransporte al destino; no valida su trayectoria.
- `held_edge_point` se conserva como telemetría, pero no gobierna aún soporte
  dinámico ni plataformas móviles.
- El raycast lateral confirma pared, no una geometría de borde compleja.
- Llegar a una esquina bloquea el desplazamiento; no gira alrededor de ella.
- No existe animación ni ajuste visual de manos.
- No existe salida de mantle/subida a la superficie.
- El contenido no fue conectado a la escena legacy `PlayerV2`.

Estas limitaciones son deliberadas: el objetivo de este corte fue hacer
observable la secuencia completa de eventos de Hanging dentro del laboratorio.
