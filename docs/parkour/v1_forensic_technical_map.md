# Mapa técnico forense — Parkour / Locomoción V1

> **Propósito.** Deconstrucción a nivel de código del sistema de locomoción y parkour V1, tal como
> existe en el commit `bd38e49^` (`860a999f2c5ada8fc01ab74179a3442f887883d3`). Este documento está
> pensado para **mantener, depurar y eventualmente reconstruir V1 sin volver a abrir su código**. No
> es una síntesis de diseño, no compara con V2, no propone fixes.
>
> **Etiquetas de evidencia** (obligatorias en cada afirmación):
> - `HECHO VERIFICADO` — se lee directo del código citado.
> - `INFERENCIA FUNDADA` — hipótesis apoyada en código concreto + semántica estándar de Godot/física.
> - `DESCONOCIDO` — no puede demostrarse con el código disponible en el worktree.
> - `PENDIENTE EMPÍRICO` — requiere abrir el editor y jugar V1 para confirmar.
>
> **Formato de cita:** `bd38e49^:<ruta>:<línea>`. La carpeta principal tiene un espacio en el nombre
> (`scripts/player n entities/`); se cita textual.

---

## 1. Alcance, commit y metodología

### 1.1 Commit exacto

| Dato | Valor |
|---|---|
| Commit de referencia | `860a999f2c5ada8fc01ab74179a3442f887883d3` |
| Alias | `bd38e49^` (padre inmediato de `bd38e49` "refactor: remove legacy interaction and inventory systems") |
| Mensaje del commit | `docs: add InventoryV2 postmortem` |
| Worktree físico inspeccionado | `C:\Users\ElCaido97\Documents\tun-tun-tun-sahur-v1-reference` |
| HEAD del worktree | `860a999…` (== `bd38e49^`, VERIFICADO con `git rev-parse`) |
| Estado de los archivos de movimiento en el worktree | Sin modificar respecto al commit (`git status` no marca `M` en `scripts/player n entities/movement/`) — los archivos leídos **son** los del commit. |
| Motor | Godot `4.6` (`bd38e49^:project.godot:15`, `config/features=PackedStringArray("4.6", "Forward Plus")`). Nota: `docs/parkour/v1_manual_validation.md` (doc previo, no versionado) menciona editor `4.6.3`. |
| Motor de física | Jolt Physics (`bd38e49^:project.godot:117`, `3d/physics_engine="Jolt Physics"`). |
| Driver de render | `d3d12` en Windows (`bd38e49^:project.godot:121`). |

`HECHO VERIFICADO` — todo lo anterior.

### 1.2 Historia de construcción del sistema (contexto, no se usa para inferir comportamiento)

`git log` sobre `scripts/player n entities/movement/` (commits ancestros de `860a999`), del más nuevo al
más viejo. Los mensajes son notas de desarrollo en español rioplatense; se transcriben porque varios
**explican por qué existe un valor concreto** (se citan en §7 y §8). `HECHO VERIFICADO` que estos
mensajes existen; las afirmaciones *dentro* de cada mensaje son del autor y quedan como
`PENDIENTE EMPÍRICO` salvo que el código las confirme.

| Commit | Fecha | Mensaje |
|---|---|---|
| `d6cf156` | 2026-06-14 | sistema precario de plataformas |
| `5ca2d70` | 2026-06-03 | se soluciono el tema de meterse en el ladder desde cualquier lado, era porque no se estaba usando la funcion `_is_within_segment_volume()`, se reconecto con el resto del script |
| `53df531` | 2026-06-02 | ya se soluciono el tema de las escaleras… la perdida de informacion en la transicion de un stopmarker y un startmarker, ahora es instantaneo y sin el micro stop |
| `0340960` | 2026-06-02 | se resume todo en `ladder_max_distance`… el collisionshape de la escalera debe de medir lo mismo o parecido que la distancia entre los dos markers |
| `3bba9a7` | 2026-06-01 | todavia se puede meter en el hanging mientras se encuentra en el path de los dos marker, el control no es perfecto, es una loteria que funcione correctamente |
| `e6bb0ed` | 2026-05-31 | sistema de escaleras con `traversal_segment` implementado |
| `99d3766` | 2026-05-28 | se soluciono el tema de saltar de un un borde a otro, solo habia que poner el `max_edge_height` en 1.5 |
| `8ae5b1a` | 2026-05-28 | lo de agarrarse en curvas y hacer tp a la siguiente normal esta casi que solucionado, pero como nadie lo va a notar, por ahora esta terminado |
| `63082dd` | 2026-05-27 | el `transver_controller` funciona… no explota como antes, lo que si, es que mantiene el momentum al final, todo gracias al `lerp` |
| `0c056ec` | 2026-05-26 | sistema de Shimmy: multi-probe system + debug toggles medianamente desarrollado |
| `3840e4a` | 2026-05-26 | ya no hay rebotes al desplazarse por el anillo |
| `e446aff` | 2026-05-25 | ahora funciona la deteccion de paredes con una inclinacion y no las atraviesa |
| `541b519` | 2026-05-24 | logre implementar el sistema de states de movimiento, por lo menos lo basico y necesario |

Rango de construcción: 2026-05-24 → 2026-06-14. `HECHO VERIFICADO`.

### 1.3 Archivos inspeccionados

**Núcleo de movimiento/parkour** (`bd38e49^:scripts/player n entities/movement/`):

| Archivo | Líneas | Rol |
|---|---|---|
| `player.gd` | 87 | Coordinador `CharacterBody3D`; input de cámara/crouch; despacho de física. |
| `movement_controller.gd` | 111 | Locomoción a pie: gravedad, salto, crouch, velocidad, control aéreo. |
| `parkour_detector.gd` | 363 | Detección de candidatos (ledge + ladder); scoring; cooldown. Solo detecta y emite señales. |
| `traversal_controller.gd` | 612 | Máquina de estados SNAPPING/HANGING/CLIMBING/LADDER; shimmy; releases. |
| `traversal_segment.gd` | 85 | Componente de escalera/cuerda: markers, progreso, vecinos para stacking. |
| `kick_controller.gd` | 83 | Patada a `RigidBody3D` usando el raycast de interacción. |

**Autoloads relevantes** (`bd38e49^:project.godot:18-24`):

| Autoload | Recurso | Relevancia a locomoción |
|---|---|---|
| `DebugDraw` | `scripts/player n entities/visuals/debug_draw.gd` (146 líneas) | Todas las funciones de probe dibujan acá; `traversal_controller` llama `DebugDraw.clear()` cada tick (§3, §8). |
| `UiInventario` | `scenes/components/ui_inventario.tscn` → `scripts/player n entities/inventory/ui_inventario.gd` (221) | `player.gd` compuerta `_input` y `_physics_process` con `UiInventario.visible` (§8: siempre `false`). |
| `UIHacking` | `scenes/components/ui_hacking.tscn` → `scripts/enviroment/ui_hacking.gd` (63) | `abrir()` hace `get_tree().paused = true` — congela toda la física del jugador (§9). |
| `Catalogo`, `Inventario` | scripts de inventario legacy | Sin relación con locomoción; no inspeccionados a fondo. |

**Visuales / debug del jugador** (`bd38e49^:scripts/player n entities/visuals/`):

| Archivo | Líneas | Estado |
|---|---|---|
| `debug_draw.gd` | 146 | ACTIVO (autoload). |
| `debug_ui.gd` | 44 | ACTIVO — overlay de texto siempre visible; lee `velocity`, `is_on_floor`, `traversal.get_state_name()`. |
| `debug_traversal.gd` | 185 | **INERTE por bug de path** (§8). |
| `debug_trail.gd` | 40 | **NUNCA INSTANCIADO** en ninguna escena (§8). |
| `free_camera.gd` | 94 | ACTIVO — cámara libre de debug, tecla `F`. |
| `hud.gd` | 26 | ACTIVO — label de interacción; no toca locomoción. |
| `marco_enfoque.gd` | 58 | ACTIVO — marco 2D sobre el objeto mirado; no toca locomoción. |
| `raycast_interaccion.gd` | 72 | ACTIVO — raycast de cámara; `kick_controller` consume su `objeto_mirado`. |
| `salud.gd` | 23 | ACTIVO — `signal murio` → `player._on_murio` → `reload_current_scene()`. `recibir_daño` **nunca se llama** (§9). |

**Escenas** (`bd38e49^:`):

| Escena | Rol |
|---|---|
| `levels/movement_test.tscn` | **Escena principal del proyecto** (`project.godot:14`, `run/main_scene="uid://cq3xs5ly2b4v0"`). Playground de parkour. |
| `levels/test_level.tscn` | Playground mínimo secundario (piso + 2 plataformas + player). No es main scene; sin consumidor conocido. |
| `scenes/components/player.tscn` | Scaffold del jugador. **NO tiene `player.gd` asignado** — el script lo pone la escena que la instancia (§2). |
| `scenes/components/traversal_ui.tscn` | `CanvasLayer` + `Label` con `debug_traversal.gd` (inerte). Instanciada en `player.tscn`. |
| `scenes/components/debug_ui.tscn` | `Node3D` > `CanvasLayer(DebugUI)` + `Label`. Instanciada en `player.tscn`. |
| `scenes/components/hud.tscn` | `CanvasLayer(HUD)` + `Label` + `marco_enfoque`. Instanciada en `player.tscn`. |
| `scenes/components/salud.tscn` | `Node3D(Salud)` con `salud.gd`. Instanciada en `player.tscn`. |
| `scenes/components/raycast_interaccion.tscn` | `Node3D(raycast_interaccion)` grupo `["raycast"]` con `raycast_interaccion.gd`. Instanciada bajo `player/Camera3D`. |
| `scenes/components/debug_trail.tscn` | `Node3D(DebugTrail)` con `debug_trail.gd`. **Sin instanciar en ningún lado.** |
| `scenes/props/static/escalera_fea_v_1.tscn` | `StaticBody3D` grupo `["ladder"]` + `traversal_segment.gd` + `carcasa` (BoxShape3D) + `StartMarker`/`EndMarker` (Marker3D). Instanciada ×5 en `movement_test`. |
| `scenes/props/static/circulo_circuloso.tscn` | `StaticBody3D` + `ConcavePolygonShape3D` (anillo dodecagonal, r≈6, alto 1). Objeto de prueba de shimmy/esquinas ("anillo" del commit `3840e4a`). |
| `scenes/props/static/banquitobrutalista_01.tscn` | `StaticBody3D` + `BoxShape3D(3.375, 0.845, 0.855)`. Banco bajo — prueba de altura de mantle. |
| `scenes/props/static/caja_doblada.tscn` | `StaticBody3D` + 4 `CollisionShape3D`. **Sin instanciar en `movement_test`.** |
| `scenes/props/dinamic/mesa_standar_1.tscn`, `osciloscopio_01.tscn` | `RigidBody3D` con `Item.gd` (`extends RigidBody3D`) — objetivos válidos de `kick_controller`. |
| `scenes/props/static/monitor_01.tscn` | `StaticBody3D` con `terminal.gd` → `UIHacking.abrir()` → pausa el árbol (§9). |

**`bd38e49^:project.godot`** — autoloads, InputMap completo, física, display. Inspeccionado.

### 1.4 Archivos excluidos y motivo

| Archivo / grupo | Motivo de exclusión |
|---|---|
| `scenes/test/v1_comparison_p0.tscn`, `scenes/test/v1_reference_playground.tscn` | **Untracked** en el worktree V1-ref al inicio de esta tarea — son trabajo P0 pausado del usuario, NO parte del V1 histórico versionado. Referencian `player.gd` pero no pertenecen al commit. |
| `docs/parkour/v1_manual_validation.md`, `v1_playtest_checklist.md` (worktree V1-ref) | Untracked; docs previos del usuario. Se citan solo en §11 como "hallazgo empírico previo", nunca como fuente de `HECHO VERIFICADO`. |
| `docs/parkour/v1_behavioral_reference.md` (worktree main) | Doc de comportamiento previo. Complementario, no fuente de código. Este mapa es su contraparte técnica. |
| `scripts/player n entities/systems/transport/guided_vehicle.gd` (1648 líneas), `stop_point.gd`, `transition_point.gd`, `world_button.gd`, `vehicle_button.gd`, `scriptdelcilindro.gd` | Sistema de teleférico/vehículo guiado. `grep` confirma: **no lee ni escribe `velocity`, `transform`, collider, estado ni señales de traversal del jugador** (`guided_vehicle.gd` solo asigna su propio `global_position`, línea 371; comentario en línea 1353: "no hay reparenting dinámico"). El jugador lo monta, si acaso, vía física de plataforma del motor (`move_and_slide`), no vía código V1. Adyacente, no núcleo. |
| `scripts/player n entities/inventory/*` (excepto `ui_inventario.gd`) | Inventario legacy. `ui_inventario.gd` se incluye solo por la compuerta `UiInventario.visible` de `player.gd`. |
| `assets/models/stairs/*.glb` + `.import` | Modelos de rampa/escalera-peldaño. `escalera_grande2.glb.import` tiene `"generate/physics": true` → generan colisión estática caminable. No tienen lógica. |
| `assets/models/no_collectibles/escalera pedorra3.glb.import` | Modelo visual de la escalera-ladder. **Sin `generate/physics`** → solo visual; la colisión de la ladder es el `carcasa` BoxShape3D explícito. |
| `kick_controller.gd` | **NO excluido** — se documenta completo (§4) por estar en la carpeta de movimiento y consumir el raycast del jugador, aunque no interactúa con traversal. |

### 1.5 Limitaciones de evidencia

1. `PENDIENTE EMPÍRICO` transversal: **ningún estado de traversal usa `move_and_slide`/`move_and_collide`**
   (§5, §8). El resultado físico exacto de escribir `global_position` dentro de geometría sólida sólo se
   ve jugando. Godot/Jolt resuelve la penetración al volver a IDLE — el "cómo" exacto es empírico.
2. `DESCONOCIDO`: **radio y altura exactos del `CapsuleShape3D` del jugador**. `bd38e49^:scenes/components/player.tscn:16`
   declara `[sub_resource type="CapsuleShape3D" id="CapsuleShape3D_u8vuu"]` **sin propiedades** → usa los
   defaults de Godot 4.6. `INFERENCIA FUNDADA`: `radius = 0.5`, `height = 2.0` (defaults documentados del
   engine). La **altura** además queda fijada en `2.0` de pie por código (`movement_controller.gd:71`,
   lerp hacia `2.0`), así que el default de altura es irrelevante en la práctica; el **radio** no aparece
   en ningún script.
3. `DESCONOCIDO`: si existieron consumidores de `traversal_started`/`traversal_ended`, `candidate_lost`,
   `ladder_candidate_lost` **fuera del worktree V1-ref** (audio, cámara cinemática, UI de otro branch). En
   este worktree no hay ninguno (§9). El worktree es aislado y podría no contener todo el proyecto
   histórico de otras ramas.
4. `PENDIENTE EMPÍRICO`: el efecto de gameplay concreto de la **doble ejecución de `_physics_process`**
   del `TraversalController` (§3.4, §8.1). El mecanismo está `HECHO VERIFICADO`; la magnitud percibida
   (velocidad de shimmy, timeout de snap, ritmo de escalera) requiere medición en editor.
5. No se ejecutó Godot. No se corrieron tests (no existen tests de movimiento V1 — §9.6). Todo es
   lectura estática + `git`.

---

## 2. Topología real en escena

### 2.1 `player.tscn` — el scaffold (sin script propio)

`bd38e49^:scenes/components/player.tscn`. Árbol tal como está en el archivo:

```
Node3D ("Node3D")                                    [raíz, unique_id 189769782]
├── player  (CharacterBody3D)   groups=["player"]    [uid 629727262]   ← SIN script en este archivo
│   ├── CollisionShape3D  (CollisionShape3D)         shape = CapsuleShape3D_u8vuu (sin props)
│   ├── MeshInstance3D    (MeshInstance3D)           mesh = CapsuleMesh_3vyb7 (sin props)
│   ├── Camera3D          (Camera3D)                 transform y=0.8, z=-0.285 ; fov=81.0
│   │   └── raycast_interaccion  (instancia raycast_interaccion.tscn)   groups=["raycast"]
│   ├── movement          (Node)
│   │   ├── MovementController   (Node)  script = movement_controller.gd
│   │   ├── TraversalController  (Node)  script = traversal_controller.gd
│   │   ├── ParkourDetector      (Node)  script = parkour_detector.gd
│   │   ├── traversal_ui         (instancia traversal_ui.tscn)
│   │   │   └── CanvasLayer      script = debug_traversal.gd
│   │   │       └── Label
│   │   └── KickController       (Node)  script = kick_controller.gd
│   └── hudnscreen        (Node)
│       ├── HUD           (instancia hud.tscn)       raycast = NodePath("../../Camera3D/raycast_interaccion")
│       ├── DebugUI       (instancia debug_ui.tscn ; raíz Node3D renombrada "DebugUI")
│       │   └── DebugUI   (CanvasLayer)  script = debug_ui.gd
│       │       └── Label
│       ├── UIHacking     (instancia ui_hacking.tscn)      [además hay autoload UIHacking — dos instancias]
│       ├── Salud         (instancia salud.tscn)   script = salud.gd
│       └── TirarItem     (instancia tirar_item.tscn)
└── Camera3D  (Camera3D)   script = free_camera.gd    ← cámara libre, HERMANA de "player", no hija
```

`HECHO VERIFICADO`.

**Hechos críticos de esta escena:**

- `HECHO VERIFICADO` (`bd38e49^:scenes/components/player.tscn:22-28`): el nodo `player` NO tiene línea
  `script =`. `player.tscn` por sí sola **no es el jugador de parkour** — es un scaffold. El script
  `player.gd` se asigna por override en la escena que la instancia (§2.3).
- `HECHO VERIFICADO` (`:22`): `collision_layer = 4`, `collision_mask = 9`. Layer 4 = bit 2 (tercera capa).
  Mask 9 = `0b1001` = capas 1 y 4. El jugador colisiona con capa 1 (geometría estática default) y capa 4
  (otros players / sí mismo, irrelevante).
- `HECHO VERIFICADO` (`:22`): propiedades `CharacterBody3D` puestas en la escena:
  `wall_min_slide_angle = 0.0`, `floor_block_on_wall = false`, `floor_snap_length = 0.5`. `player.gd:_ready`
  vuelve a fijar `floor_snap_length = 0.5` (redundante) y agrega `floor_stop_on_slope = true`,
  `floor_max_angle = deg_to_rad(46)` (§4.1).
- `HECHO VERIFICADO` (`:16`, `:18`): `CapsuleShape3D_u8vuu` y `CapsuleMesh_3vyb7` **sin propiedades** →
  defaults del engine. `INFERENCIA FUNDADA`: cápsula r=0.5, h=2.0.
- `HECHO VERIFICADO` (`:36-38`): la `Camera3D` del jugador está en `transform` local `(0, 0.8, -0.285)`
  con `fov = 81.0`. El `-0.285` en Z la adelanta respecto del centro del cuerpo (hacia el frente, −Z).
  Su `position.y` inicial (0.8) NO coincide con el target de `_update_crouch` (0.706 de pie) — al primer
  tick de física la cámara baja de 0.8→0.706 por lerp (`INFERENCIA FUNDADA`: micro-caída de cámara al
  spawn; `PENDIENTE EMPÍRICO` si es perceptible).
- `HECHO VERIFICADO` (`:73-74`): hay una **segunda `Camera3D`** en la raíz de `player.tscn` (hermana de
  `player`), con `free_camera.gd`. `free_camera._ready` (`bd38e49^:.../visuals/free_camera.gd:30`) la pone
  `current = false`.
- `HECHO VERIFICADO`: la `raycast_interaccion` está bajo `player/Camera3D`, no bajo `player`.
- `HECHO VERIFICADO`: `debug_traversal.gd` corre en `player/movement/traversal_ui/CanvasLayer`.
- `HECHO VERIFICADO`: **no hay ningún bloque `[connection]` en `player.tscn`.** Todo el cableado de
  señales es por código (§2.4).

### 2.2 `escalera_fea_v_1.tscn` — el componente de escalera

`bd38e49^:scenes/props/static/escalera_fea_v_1.tscn`:

```
escalera fea v1  (StaticBody3D)  groups=["ladder"]  script = traversal_segment.gd
├── escalera pedorra3   (instancia GLB, solo visual)   transform y=0.062
├── carcasa             (CollisionShape3D)  shape = BoxShape3D(1.39, 8.77, 0.28)  transform y=4.385
├── StartMarker         (Marker3D)  transform (0, 0.9999223, 0.80568457)
└── EndMarker           (Marker3D)  transform (0, 8.2,        0.806)
```

`HECHO VERIFICADO`.

- La colisión es un cajón de **1.39 (ancho) × 8.77 (alto) × 0.28 (fondo)**, centrado a y=4.385 local
  → ocupa y∈[0, 8.77] local.
- `StartMarker` local: y≈1.0, z≈+0.806. `EndMarker` local: y=8.2, z≈+0.806. El eje de trepada va de
  y≈1.0 a y=8.2 (**7.2 unidades** de recorrido), desplazado **+0.806 en Z** respecto del plano de la
  colisión → el jugador cuelga ~0.8 m adelante de la cara de la escalera. `HECHO VERIFICADO`.
- `StaticBody3D` sin `collision_layer` explícito → default **capa 1**. El shape-query del detector usa
  `body.collision_mask` (=9, incluye capa 1) → la escalera es detectable. `HECHO VERIFICADO`
  (`parkour_detector.gd:118`).
- `traversal_segment.gd:_ready` resuelve `StartMarker`/`EndMarker` por nombre exacto con
  `get_node_or_null` (`:45-46`). Si faltan, `push_warning` y el segmento queda inválido (el detector lo
  descarta en `_process_ladder`, `:134-137`). `HECHO VERIFICADO`.

### 2.3 `movement_test.tscn` — la escena principal / playground

`bd38e49^:levels/movement_test.tscn` (uid `cq3xs5ly2b4v0`, main scene).

**Cadena de instanciación del jugador** (`:737-754`):

```
MovementTest  (Node3D)  groups=["raycast"]                        ← sin script; grupo sin consumidor (§9.3)
└── entities  (Node3D)
    └── player  (Node3D)                          transform x = -3.7168937
        └── player  (instancia player.tscn ; raíz "Node3D" renombrada "player")   transform y = 0.17427588
            └── player  (el CharacterBody3D interno, index 0)
                script = res://scripts/player n entities/movement/player.gd     ← AQUÍ se asigna el script
                ├── Camera3D            current = true                          ← override
                │   └── raycast_interaccion   mostrar_raycast = false ; capa_interaccion = 3   ← overrides
                └── movement/KickController   kick_force = 40.0                  ← override (default 8.0)
```

`HECHO VERIFICADO` (`:740-754`).

**Overrides de la escena sobre `player.tscn`:**

| Nodo | Propiedad | Valor en `movement_test` | Default en `player.tscn` |
|---|---|---|---|
| `.../player` (CharacterBody3D) | `script` | `player.gd` | (ninguno) |
| `.../player/Camera3D` | `current` | `true` | (no seteado) |
| `.../raycast_interaccion` | `mostrar_raycast` | `false` | `true` |
| `.../raycast_interaccion` | `capa_interaccion` | `3` (capas 1+2) | `2` (capa 2) |
| `.../movement/KickController` | `kick_force` | `40.0` | `8.0` |

`HECHO VERIFICADO`.

**Posición de spawn del jugador:** composición de transforms
`(-3.7168937, 0, 0) · (0, 0.17427588, 0) · (0, 1, 0)` = **`(-3.717, 1.174, 0)`** en mundo.
`INFERENCIA FUNDADA` (multiplicación de los 3 transforms anidados; el `y=1` viene de
`player.tscn:23`, no overrideado).

**Geometría de parkour presente en `movement_test`** (`HECHO VERIFICADO`, selección relevante):

| Nodo(s) | Forma / tamaño | Posición aprox. | Para qué sirve |
|---|---|---|---|
| `world/.../piso/StaticBody3D` | BoxMesh/Shape `300 × 1 × 300` | (0, -0.52, 0) | Piso infinito. |
| `world/.../piso_piedra` | Box `15 × 0.5 × 20` | (22.76, -0.15, 0) | Plataforma secundaria. |
| `escalera_grande2`, `escalear_largalarga2`, `escalera_xlarga`, `escalera_xlarga2` (GLB) | Rampas/escaleras con colisión generada | z≈8.5, x∈[-10.6, 5.5] | Rampas caminables. |
| `bloques/StaticBody3D` | Box `40 × 0.2 × 50` | (-4.74, 0, 0) | Plataforma grande elevada. |
| `bloques/StaticBody3D2` | Box escalado `10 × 1 × 3` (roll 45°) | (0, 2.98, -5.52) | Rampa inclinada 45°. |
| `bloques/StaticBody3D3` | Box `12 × 12 × 12` | (0, 6.37, -14.71) | Torre-cubo. |
| `bloques/StaticBody3D4` | Box `12 × 12 × 12` (tilt ~13°) | (14.48, 8.97, -15.30) | Cubo inclinado — prueba de pared inclinada (commit `e446aff`). |
| `bloques/StaticBody3D5` | Box escalado `6 × 3 × 1` | (5.02, 1.62, -5.75) | Muro. |
| `bloques/StaticBody3D6` | Box `5 × 2 × 1` | (11.57, 2.05, -5.88) | Muro/cornisa. |
| `bloques/cubo prueba` | Box `1.5³` | (2.25, 0.83, 0) | Cubo bajo. |
| `bloques/cuboprueba 1` | Box `3³` | (6.31, 1.57, 0) | Cubo. |
| `bloques/peldaños verticales/peldaños` | Box `2 × 1 × 2` | (5.84, 5.88, 0) | "Peldaños verticales". |
| `plataformas/muros/StaticBody3D` | Box `3 × 3 × 0.2` | ~(-15.1, 1.62, -6.6) | Muro fino. |
| `circulo circuloso` | ConcavePolygon dodecagonal r≈6, alto 1 | (8.789, 4.644, 8.406) | **Anillo de shimmy** (esquinas cóncavas/convexas, commits `3840e4a`, `8ae5b1a`). |
| `banquitobrutalista_01` | Box `3.375 × 0.845 × 0.855` | (28.87, 0.13, -4.83), rot | Banco bajo — mantle de poca altura. |
| `escaleras/escalera 1..5` | Instancias `escalera_fea_v_1.tscn` | ver §2.4 abajo | Escaleras-ladder con stacking. |
| `varios/torre`, `varios/torre_1` | Cilindros r10 h100 / r4 h60 | (120, 48.9, 0) / (21.7, 23.6, -38) | Torres lejanas. |
| `platfoms/elevador_prueba/plataforma_prueba` | `AnimatableBody3D` + `elevator_platform.gd` inline | (-4.13, 0.65, 4.21) | **INERTE** — sin `detect_area`, nadie llama `go_to_station()` (§8.6). |
| `paths/teleferico_prueba/*` + `edificio_02` | Path3D + `guided_vehicle` | z≈5, x∈[-38, 35] | Teleférico (fuera de alcance, §1.4). |
| `monitor_01` (terminal) + `door_rust_01` | StaticBody + `terminal.gd` / puerta | (-8.7, 1.28, -2.95) / (-10.3, 0.32, -3.6) | Hacking → pausa el árbol (§9). |
| `mesa_standar_1`, `osciloscopio_01` | `RigidBody3D` | (-12.1, 0.1, 2.25) / (-8.8, 1.49, 1.14) | Objetivos de patada. |

### 2.4 Configuración de las 5 escaleras en `movement_test`

`HECHO VERIFICADO` (`bd38e49^:levels/movement_test.tscn:462-497`):

| Instancia | Transform (pos) | Rotación | Overrides de markers / escala | `neighbour_up` | `neighbour_down` |
|---|---|---|---|---|---|
| `escalera 1` | (-10.33, 4.80, -9.64) | yaw 90° | (default: Start y≈1.0, End y=8.2) | `../escalera 3` | — |
| `escalera 2` | (-4.035, -1.61, -8.60) | ninguna | `escalera pedorra3` y `carcasa` escalados ×4 en Y; `carcasa` a y=17.32; **StartMarker (0, 2.816892, 0.80568457)**, **EndMarker (0, 34.867695, 0.80599976)** | — | — |
| `escalera 3` | (-10.66, 12.41, -9.64) | yaw 90° + **tilt ~24°** (basis Y = (0.403, 0.915, 0)) | default markers | — | `../escalera 1` |
| `escalera 4` | (-15.07, 0.10, -6.40) | ninguna | default markers | `../escalera 5` | — |
| `escalera 5` | (-15.07, 7.30, -6.41) | ninguna | **EndMarker (0, 9, 0.806)** (Start default) | — | `../escalera 4` |

- Cadena de stacking A: `escalera 1` ⇆ `escalera 3` (bidireccional). `escalera 3` está **inclinada ~24°**
  respecto de la vertical → prueba de segmento no vertical. `HECHO VERIFICADO`.
- Cadena de stacking B: `escalera 4` ⇆ `escalera 5` (bidireccional).
- `escalera 2` es **standalone, 4× de alto** (~32 unidades de recorrido de marker a marker) — prueba de
  escalera muy larga sin vecinos.
- `escalera 5`: EndMarker a y=9 local pero `carcasa` sin re-escalar (tope de colisión a y≈8.77 local).
  `INFERENCIA FUNDADA`: pequeña imprecisión de autoría (marker levemente por encima de la colisión).

### 2.5 `test_level.tscn` — playground mínimo

`bd38e49^:levels/test_level.tscn` (uid `cv5ym8d32f5mp`). No es main scene, sin consumidor conocido.

```
Node3D
├── StaticBody3D    piso Box 40×0.2×40 (escalado por transform del CollisionShape3D)   y=-0.1
├── player  (instancia player.tscn)
│   └── player  (index 0)   script = player.gd            ← mismo patrón que movement_test
├── DirectionalLight3D
├── WorldEnvironment
├── StaticBody3D2   Box 5×0.2×3     (0, 1.2, 7.73)         ← plataforma
├── StaticBody3D3   Box (default)   (0.035, 2.6, -2.353)   ← plataforma
└── Node3D          (instancia debug_ui.tscn)
```

`HECHO VERIFICADO`. Diferencias con `movement_test`: **no** setea `Camera3D.current`, **no** setea
`KickController.kick_force` (usa default 8.0), **no** setea `raycast_interaccion` overrides (usa
`capa_interaccion = 2`). `DESCONOCIDO` qué cámara queda activa aquí al arranque (dos `Camera3D` en el
árbol, ninguna `current` explícita; `free_camera._ready` pone la suya en `false`; la del jugador queda a
merced del auto-current de Godot).

### 2.6 Nodos obligatorios (romper el sistema si faltan)

`player.gd:_ready` (`bd38e49^:scripts/player n entities/movement/player.gd:9-16`) hace `@onready` sobre
rutas fijas. Si alguna no existe, `player.gd` **crashea en `_ready`** (acceso a `null`):

| Ruta (`$` relativo al `player` CharacterBody3D) | Se usa para |
|---|---|
| `$Camera3D` | mouse-look, se pasa a todos los controllers, `_hay_techo` no la usa pero sí `movement`/`kick`. |
| `$CollisionShape3D` | `movement._update_crouch` escribe `.shape.height`; `player._hay_techo` lee `.shape.height`. |
| `$hudnscreen/Salud` | `salud.murio.connect(_on_murio)`. |
| `$movement/MovementController` | `movement.setup/process/freeze`. |
| `$movement/ParkourDetector` | `parkour_detector.setup/process/start_cooldown`. |
| `$movement/TraversalController` | `traversal.setup/process/is_active/is_crouch_blocked_after_drop`. |
| `$movement/KickController` | `kick.setup/process`. |
| `$Camera3D/raycast_interaccion` | se pasa a `kick.setup` (kick lee `raycast.objeto_mirado`). |

`HECHO VERIFICADO`. Además:

- `parkour_detector.gd:154-155`, `_process_ladder` llama `DebugDraw.sphere/ray` sin guarda → si el
  autoload `DebugDraw` no existe, crashea. Igual `traversal_controller`, `kick_controller`. `HECHO VERIFICADO`.
- `player.gd:35,56` accede `UiInventario.visible` sin guarda → si el autoload `UiInventario` no existe,
  crashea en el primer `_input`/`_physics_process`. `HECHO VERIFICADO`.
- `debug_ui.gd:9` hace `player.get_node("movement/MovementController")` con `get_node` (no `_or_null`) →
  crashea si falta. `debug_ui.gd:16` idem `get_node("Camera3D")`. `HECHO VERIFICADO`.
- El nodo `player` **debe** estar en el grupo `"player"` (`player.tscn:22`) o todos los visuales
  (`debug_ui`, `hud`, `free_camera`, `raycast_interaccion`, `debug_trail`, `debug_traversal`) fallan al
  resolver `get_tree().get_first_node_in_group("player")`. `HECHO VERIFICADO`.
- Una escalera **debe** tener el grupo `"ladder"` en el mismo `StaticBody3D` que el script, con hijos
  `StartMarker` y `EndMarker`, o el detector nunca la reconoce (`parkour_detector.gd:175`, `134-137`).
  `HECHO VERIFICADO`.

### 2.7 Referencias exportadas y su origen

`player.gd` **no tiene `@export`**. Los parámetros exportados viven en los controllers:

| Nodo | Export | Default (código) | Override en `movement_test` |
|---|---|---|---|
| `ParkourDetector` | `detection_distance`, `edge_probe_up`, `min_edge_height`, `max_edge_height`, `clearance_height`, `clearance_radius`, `min_score`, `max_surface_tilt_deg`, `ladder_detection_radius`, `detection_cooldown` | ver §7 | **ninguno** — todos quedan en default. |
| `TraversalController` | `snap_speed`, `snap_threshold`, `climb_speed`, `shimmy_speed`, `shimmy_max_dist`, `jump_force`, `ladder_pulse_speed`, `ladder_pulse_time`, `ladder_snap_strength` | ver §7 | **ninguno**. |
| `KickController` | `kick_force`, `kick_upward` | 8.0 / 0.2 | `kick_force = 40.0`. |
| `TraversalSegment` (cada escalera) | `segment_type`, `move_speed`, `neighbour_up`, `neighbour_down` | LADDER / 1.0 / "" / "" | `neighbour_up`/`neighbour_down` según §2.4. |
| `raycast_interaccion` | `mostrar_raycast`, `distancia_interaccion`, `color_rayo`, `capa_interaccion` | true / 2.5 / GREEN / 2 | `mostrar_raycast=false`, `capa_interaccion=3`. |
| `free_camera` (Camera3D raíz) | `move_speed`, `fast_multiplier`, `mouse_sensitivity`, `toggle_action` | 8.0 / 3.0 / 0.003 / "toggle_free_cam" | ninguno. |
| `hud` (HUD) | `raycast` | null | `NodePath("../../Camera3D/raycast_interaccion")` (en `player.tscn`). |
| `salud` (Salud) | `vida_maxima` | 100.0 | ninguno. |

`HECHO VERIFICADO`. **Todos los parámetros de detección y de traversal corren en su valor default de
código en el playground** — no hay tuning por escena.

---

## 3. Orden temporal completo

### 3.1 Callbacks del ciclo de vida de Godot presentes

`HECHO VERIFICADO` (grep exhaustivo sobre movimiento + visuales):

| Script | `_enter_tree` | `_ready` | `_input` | `_process` | `_physics_process` |
|---|:-:|:-:|:-:|:-:|:-:|
| `player.gd` | — | ✔ | ✔ | — | ✔ |
| `movement_controller.gd` | — | — | — | — | — (solo método manual `process`) |
| `parkour_detector.gd` | — | — | — | — | — (solo método manual `process`) |
| `traversal_controller.gd` | — | — | — | — | **✔ (auto) + se llama manual vía `process()`** |
| `traversal_segment.gd` | — | ✔ | — | — | — |
| `kick_controller.gd` | — | — | — | — | — (solo método manual `process`) |
| `debug_draw.gd` (autoload) | — | ✔ | — | ✔ | — |
| `debug_ui.gd` | — | — | — | ✔ | — |
| `debug_traversal.gd` | — | ✔ | — | ✔ | — |
| `free_camera.gd` | — | ✔ | ✔ | ✔ | — |
| `hud.gd` | — | ✔ | — | ✔ | — |
| `marco_enfoque.gd` | — | — | — | ✔ | — |
| `raycast_interaccion.gd` | — | ✔ | ✔ | ✔ | — |
| `salud.gd` | — | ✔ | — | — | — |
| `ui_inventario.gd` (autoload) | — | ✔ | ✔ (DESACTIVADO en `_ready`) | ✔ (no-op) | — |
| `ui_hacking.gd` (autoload + instancia) | — | ✔ | ✔ | ✔ | — |

### 3.2 `_ready` — orden de inicialización

Godot llama `_ready` **de hijos a padres** (bottom-up). Autoloads primero (son hijos de `/root` antes que
la escena). Secuencia relevante:

1. **Autoloads** `_ready` (orden de `project.godot`): `Catalogo`, `Inventario`, `UIHacking`, `UiInventario`,
   `DebugDraw`.
   - `ui_inventario.gd:_ready` (`:17-30`): `visible = false`; `_construir_grilla()`; **`set_process_input(false)`**
     (hibernación, §8.3). `HECHO VERIFICADO`.
   - `debug_draw.gd:_ready` (`:27-41`): crea `ImmediateMesh` + `StandardMaterial3D` (unshaded, sin
     depth-test, alpha) + `MeshInstance3D`; `call_deferred("_attach_to_scene")`. `HECHO VERIFICADO`.
2. **Escena `movement_test`**, bottom-up. Entre otros:
   - `traversal_segment.gd:_ready` (cada una de las 5 escaleras): resuelve `StartMarker`/`EndMarker`.
   - `salud.gd:_ready`: `vida_actual = vida_maxima` (100).
   - `raycast_interaccion.gd:_ready`: crea su `ImmediateMesh` de línea.
   - `hud.gd:_ready`: `marco.raycast = raycast`.
   - `free_camera.gd:_ready`: `current = false`; cachea `_player_camera = player.get_node_or_null("Camera3D")`.
   - `debug_traversal.gd:_ready` (`:40-47`): `_traversal = player.get_node_or_null("TraversalController")`
     → **devuelve `null`** porque el nodo real está en `player/movement/TraversalController` (§8.2);
     `visible = false`.
   - `player.gd:_ready` (`:18-28`) — **el último relevante**, ya con todos los hijos listos:
     1. `Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)`
     2. `floor_stop_on_slope = true`
     3. `floor_max_angle = deg_to_rad(46)`  (≈ 0.8029 rad)
     4. `floor_snap_length = 0.5`
     5. `movement.setup(self, camera, collision)`
     6. `parkour_detector.setup(self, camera, traversal)`
     7. `traversal.setup(self, camera, movement, parkour_detector)` → **acá se conectan las señales**
        `detector.candidate_found → _on_candidate_found` y `detector.ladder_candidate_found → _on_ladder_candidate_found`
        (`traversal_controller.gd:89-90`).
     8. `kick.setup(self, camera, raycast)`
     9. `salud.murio.connect(_on_murio)`
   `HECHO VERIFICADO`.
3. `debug_draw.gd:_attach_to_scene` (deferred, después de todos los `_ready`): `get_tree().current_scene`
   → `root.add_child(_mesh_instance)`. `HECHO VERIFICADO`.

`INFERENCIA FUNDADA`: no hay carrera peligrosa — todos los `setup()` corren en `player._ready`, y el
primer `_physics_process`/`_process` de cualquier nodo ocurre después de que **todos** los `_ready`
terminaron (garantía de Godot para nodos presentes al cargar la escena). Por lo tanto `traversal.body`
etc. están seteados antes del primer tick.

### 3.3 `_input` — orden por evento

`_input` se dispara al llegar cada `InputEvent`, antes del tick de física. Nodos con `_input` en el
árbol (orden de árbol; ninguno llama `set_input_as_handled()`, así que todos ven el evento):

1. `player.gd:_input` (`:34-52`):
   - `if UiInventario.visible: return` — **nunca corta** (§8.3). `HECHO VERIFICADO`.
   - `InputEventMouseMotion` → `rotate_y(-rel.x * 0.003)` sobre el cuerpo; `camera.rotate_x(-rel.y * 0.003)`;
     `camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)`. **Sin condición de `traversal.is_active()`** —
     el mouse-look corre en todo momento. `HECHO VERIFICADO`.
   - `ui_cancel` (Esc) → `Input.set_mouse_mode(MOUSE_MODE_VISIBLE)`.
   - `crouch` (Ctrl):
     - `if traversal.is_active() or traversal.is_crouch_blocked_after_drop: return` — durante traversal,
       Ctrl no togglea el crouch de locomoción (lo maneja `traversal`).
     - `elif movement.is_crouching and _hay_techo(): pass` — agachado con techo encima: no se para.
     - `else: movement.set_crouching(!movement.is_crouching)` — togglea.
   `HECHO VERIFICADO`.
2. `raycast_interaccion.gd:_input` (`:63-72`): `interactuar` (E) → si hay `componente_mirado`,
   `componente_mirado.recibir_interaccion(Interaction.new(player, &"usar"))`. Es lo que abre el terminal
   de hacking (§9). `HECHO VERIFICADO`.
3. `free_camera.gd:_input` (`:37-48`): `toggle_free_cam` (F) → `_toggle()`. Si `_active` y
   `InputEventMouseMotion` → mueve `_yaw`/`_pitch` de la free cam. `HECHO VERIFICADO`.
4. `debug_trail.gd:_input`: `toggle_trail` (K) → `activo = !activo`. **Nunca corre** (nodo sin
   instanciar, §8.4). `HECHO VERIFICADO`.
5. `ui_inventario.gd:_input`: `toggle_inventario` (Tab), `rotar_item` (R), clicks. **`set_process_input(false)`
   en `_ready`** → nunca corre (§8.3). `HECHO VERIFICADO`.
6. `ui_hacking.gd:_input` (`:61-63`): `ui_cancel` (Esc) → `cerrar()` si `visible`. `HECHO VERIFICADO`.

**Nota de solapamiento:** con la free cam activa, el mouse mueve **la free cam** (`free_camera._input`)
**y también rota el cuerpo del jugador** (`player._input` no chequea la free cam). `INFERENCIA FUNDADA`
(ambos `_input` procesan el mismo `InputEventMouseMotion` sin marcarlo handled).

### 3.4 `_physics_process` — el orden real por tick (CRÍTICO)

En cada tick de física, Godot recorre el árbol **de ancestros a descendientes**. Los nodos con
`_physics_process` en la escena del jugador son sólo dos: `player` (ancestro) y `TraversalController`
(descendiente). Por lo tanto:

```
TICK DE FÍSICA
│
├─(A)─ player._physics_process(delta)                     [bd38e49^:.../player.gd:55-70]
│      │
│      ├── if UiInventario.visible:      ← SIEMPRE FALSO (§8.3)
│      │      velocity.x/z → lerp(·, 0, 14*delta) ; move_and_slide() ; return      [RAMA MUERTA]
│      │
│      ├── if traversal.is_active():                       (state != IDLE)
│      │      traversal.process(delta)                     ← PASADA MANUAL nº1 de _physics_process
│      │        └─ traversal._physics_process(delta)  [.../traversal_controller.gd:95-96 → 127]
│      │
│      └── else:                                            (state == IDLE)
│             direction = _get_input_direction()            [.../player.gd:73-79]
│             movement.process(delta, direction)            [.../movement_controller.gd:32-38]
│               ├─ _update_jump_state()
│               ├─ _apply_gravity(delta)
│               ├─ _handle_jump()
│               ├─ _update_crouch(delta)                    ← escribe collision.shape.height y camera.position.y
│               ├─ _update_speed(delta)
│               └─ _apply_movement(delta, direction)        ← escribe body.velocity.x/z
│             parkour_detector.process(delta)               [.../parkour_detector.gd:61-73]
│               ├─ (cooldown) o
│               ├─ is_on_floor() → _clear_candidate()   |   else → _process_ledge()   ← DIBUJA en DebugDraw
│               └─ _process_ladder()                        ← DIBUJA en DebugDraw
│             move_and_slide()                              ← ÚNICA llamada de movimiento con colisión real
│
│      (fin del if/else)
│      kick.process(delta)                                  [.../kick_controller.gd:36-40]   ← SIEMPRE, activo o no
│
├─(B)─ TraversalController._physics_process(delta)          [AUTO — callback de Godot, .../traversal_controller.gd:127]
│      │   ← corre SIEMPRE, todos los ticks, independientemente de player.gd
│      ├── DebugDraw.clear()                                ← BORRA lo que el detector dibujó en (A)
│      ├── if state == IDLE:
│      │      housekeeping de last_hanging_pos / _last_hang_clear_timer / is_crouch_blocked_after_drop
│      │      return
│      └── else:                                             ← PASADA nº2 (cuando activo): re-ejecuta el estado
│             match state: _state_snapping/_state_hanging/_state_climbing/_state_ladder (delta)
│             _draw_debug()
│
└─ (no hay más nodos con _physics_process en el subárbol del jugador)
```

**Consecuencias `HECHO VERIFICADO` (estructura de código + semántica documentada de Godot; no hay
ningún `set_physics_process(false)` en el worktree):**

- **CD-1. `TraversalController._physics_process` se auto-ejecuta cada tick.** El método se llama
  `_physics_process` (prefijo `_`) → Godot lo registra como callback automático al entrar al árbol. El
  wrapper `func process(delta): _physics_process(delta)` (`:95-96`) NO lo vuelve manual; solo agrega una
  **segunda** ruta de invocación.
- **CD-2. Cuando `state == IDLE`:** `_physics_process` corre **una vez** por tick (solo la pasada auto B).
  `player.gd` no lo llama. Esa única pasada es la que hace el housekeeping de IDLE (§5.2) — **es
  load-bearing**: si el callback no corriera, `last_hanging_pos` nunca se limpiaría y
  `is_crouch_blocked_after_drop` nunca se desarmaría.
- **CD-3. Cuando `state != IDLE`:** `_physics_process` corre **dos veces** por tick — pasada manual A
  (dentro de `player._physics_process`) **y** pasada auto B. La lógica de estado (`_state_*`,
  `_update_shimmy_probes`, timers) se ejecuta **dos veces con el mismo `delta`**.
  `INFERENCIA FUNDADA` de los efectos (aritmética directa; magnitud percibida = `PENDIENTE EMPÍRICO`):
  - `_snap_timer += delta` ×2 → `SNAP_TIMEOUT` de 1.0 s se alcanza en ~0.5 s de tiempo real.
  - `_hang_position += _along_wall * dir * shimmy_speed * delta` ×2 → shimmy avanza a ~2× `shimmy_speed`.
  - `_ladder_pulse_timer += delta` ×2 → la escalera pulsa a ~2× el ritmo nominal.
  - `body.global_position.lerp(target, snap_speed*delta)` ×2 → converge más rápido (SNAPPING, CLIMBING).
  - `_log(...)` puede duplicar entradas del log de eventos por transición.
- **CD-4. Orden A→B:** `player` es ancestro de `TraversalController` → la pasada A corre antes que la B
  en el mismo tick. Entre A y B corre `kick.process(delta)`.
- **CD-5. Supresión del debug del detector en free-roam.** En IDLE: en (A) el detector llena los arrays
  de `DebugDraw` (rayos de pared, esferas de borde, esfera cian del candidato); en (B),
  `DebugDraw.clear()` **los borra en el mismo tick, antes del render**. `ParkourDetector` nunca llama
  `DebugDraw.clear()` por su cuenta (viola el contrato del header de `debug_draw.gd:10-12`).
  `INFERENCIA FUNDADA`: las líneas de debug del detector son **invisibles o parpadean** mientras el
  jugador está en IDLE (libre / cayendo / saltando). `PENDIENTE EMPÍRICO`: confirmar en editor (esto
  explicaría por qué `docs/parkour/v1_playtest_checklist.md` no lograba ver las líneas de las Zonas D/F).

### 3.5 `_process` (frame de render) — orden

Autoloads primero, luego escena (orden de árbol). Relevantes:

1. `debug_draw.gd:_process` (`:81-88`): si `_mesh_instance` salió del árbol → re-attach;
   `if Input.is_action_just_pressed("toggle_debug_freeze"): toggle_freeze()` (tecla G); `_redraw()` →
   re-emite las primitivas acumuladas en `_rays`/`_points`/`_spheres` como `ImmediateMesh`. `HECHO VERIFICADO`.
2. `ui_hacking.gd:_process`: si `visible` y el campo de texto no tiene foco → `grab_focus()`.
3. Escena: `raycast_interaccion.gd:_process` (`:27-48`) — raycast de cámara
   (`origen = camera.global_position`, `destino = origen - camera.basis.z * 2.5`, `mask = capa_interaccion`,
   `exclude = [player]`); setea `objeto_mirado` / `componente_mirado`; dibuja su línea si `mostrar_raycast`.
4. `debug_ui.gd:_process` — lee `player.velocity`, `is_on_floor()`, `Camera3D.rotation.x`,
   `player.rotation.y`, `movement.is_crouching`, `traversal.get_state_name()`; arma el label.
5. `hud.gd:_process`, `marco_enfoque.gd:_process` — leen `raycast.objeto_mirado`.
6. `debug_traversal.gd:_process` (`:50-68`): `toggle_debug_traversal` (F12) togglea `_enabled`; luego
   `if _traversal == null or not _enabled: visible = false; return` → **siempre corta acá** (`_traversal`
   es `null`, §8.2). `HECHO VERIFICADO`.
7. `free_camera.gd:_process` — si `_active`, mueve la free cam con I/K/J/L/U/O (`_get_move_input`).
8. `debug_trail.gd:_process` — **nunca** (sin instanciar).

**Interacción temporal `_process` ↔ `_physics_process`:** un frame de render puede tener 0..N ticks de
física antes. `raycast_interaccion` corre en `_process`; `kick_controller.process()` (en `_physics_process`)
lee `raycast.objeto_mirado` **del frame de render anterior** → el objetivo de la patada puede estar
1 frame desfasado. `INFERENCIA FUNDADA`.

### 3.6 Qué corre y qué NO cuando `traversal.is_active()`

`HECHO VERIFICADO` (`bd38e49^:scripts/player n entities/movement/player.gd:62-70`):

| Subsistema | IDLE (traversal inactivo) | Traversal activo (SNAPPING/HANGING/CLIMBING/LADDER) |
|---|---|---|
| `movement_controller.process()` | **Sí** (gravedad, salto, crouch, velocidad, movimiento) | **No** — `player.gd` no lo llama. Gravedad, crouch, control aéreo, todo suspendido. |
| `movement._update_crouch()` (collider + cámara Y) | Sí, cada tick | **No** — el collider queda **congelado** en el tamaño que tenía al entrar a traversal. |
| `parkour_detector.process()` | **Sí** | **No** — el detector no corre (ni para limpiar candidatos). |
| `move_and_slide()` | **Sí** (única colisión real del jugador) | **No** — ningún estado de traversal la llama (§5, §8.5). |
| `traversal.process()` (pasada manual) | No | **Sí** |
| `traversal._physics_process()` (pasada auto) | Sí (housekeeping IDLE + `DebugDraw.clear`) | Sí (**segunda** ejecución del estado — CD-3) |
| `kick.process()` | **Sí** | **Sí** — se llama siempre (`player.gd:70`, fuera del if/else). |
| `player._input` mouse-look | Sí | **Sí** — nunca se condiciona por estado. |

---

## 4. Inventario exhaustivo de funciones

> Formato por función: **L** = líneas · **Firma** · **Llama** = quién la invoca · **Cuándo** ·
> **Lee** · **Escribe** · **Efectos** físicos/visuales · **Señales** · **Guards / returns** ·
> **Constantes** · **Deps externas** · **Consumidores del resultado** · **Evidencia**.
> Todas las citas son `bd38e49^:<ruta>`. Helpers incluidos sin excepción.

### 4.1 `scripts/player n entities/movement/player.gd`

#### `_ready()` — L18-28
- **Firma:** `func _ready() -> void`
- **Llama:** Godot (al entrar la escena).
- **Cuándo:** una vez, tras `_ready` de todos los hijos.
- **Lee:** los `@onready` (`$Camera3D`, `$CollisionShape3D`, `$hudnscreen/Salud`, `$movement/MovementController`,
  `$movement/ParkourDetector`, `$movement/TraversalController`, `$movement/KickController`,
  `$Camera3D/raycast_interaccion`).
- **Escribe:** `Input` mouse mode; propiedades `CharacterBody3D`: `floor_stop_on_slope=true`,
  `floor_max_angle=deg_to_rad(46)`, `floor_snap_length=0.5`.
- **Efectos:** captura el mouse; configura el "piso" del motor para pendientes.
- **Señales:** conecta `salud.murio → _on_murio` (`:28`).
- **Guards / returns:** ninguno.
- **Constantes:** `deg_to_rad(46)` (≈0.8029 rad), `0.5`.
- **Deps externas:** `Input`, y los 4 `setup()` de los controllers (`movement`, `parkour_detector`,
  `traversal`, `kick`). El orden de `setup` importa: `traversal.setup` conecta las señales del detector.
- **Consumidores del resultado:** todo el sistema depende de que esto corra sin crash.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_on_murio()` — L30-31
- **Firma:** `func _on_murio() -> void`
- **Llama:** señal `salud.murio`.
- **Cuándo:** cuando `salud.vida_actual <= 0` (`salud.gd:16-17`). **`salud.recibir_daño` no se llama en
  ningún lado** (§9.5) → en la práctica **nunca**.
- **Lee:** —. **Escribe:** —.
- **Efectos:** `get_tree().reload_current_scene()`.
- **Guards / returns:** ninguno.
- **Deps externas:** `SceneTree`.
- **Evidencia:** `HECHO VERIFICADO` (que existe y está conectada). `INFERENCIA FUNDADA`: nunca se dispara.

#### `_input(event)` — L34-52
- **Firma:** `func _input(event: InputEvent) -> void`
- **Llama:** Godot (propagación de input).
- **Cuándo:** cada `InputEvent`.
- **Lee:** `UiInventario.visible`; `event` (`InputEventMouseMotion`, acciones `ui_cancel`, `crouch`);
  `traversal.is_active()`, `traversal.is_crouch_blocked_after_drop`; `movement.is_crouching`;
  `_hay_techo()`.
- **Escribe:** rotación del cuerpo (`rotate_y`), `camera.rotation.x` (+ clamp); `Input` mouse mode;
  vía `movement.set_crouching(...)`.
- **Efectos:** mouse-look (yaw sin límite en el cuerpo, pitch clamp ±π/2 en la cámara); libera mouse con
  Esc; togglea crouch.
- **Señales:** —.
- **Guards / returns:**
  - `:35-36` `if UiInventario.visible: return` — **rama muerta** (§8.3).
  - `:47-48` `if traversal.is_active() or traversal.is_crouch_blocked_after_drop: return` — corta el
    manejo de `crouch` durante traversal y justo después de soltarse por crouch.
  - `:49-50` `if movement.is_crouching and _hay_techo(): pass` — no permite pararse con techo encima.
- **Constantes:** `MOUSE_SENSITIVITY = 0.003` (`:7`); `PI/2` (clamp de pitch).
- **Deps externas:** `Input`, `UiInventario` (autoload), `traversal`, `movement`.
- **Consumidores del resultado:** el `wall`/`facing` del cuerpo (rotación) lo consumen
  `parkour_detector._probe_at/_score_candidate` (`-body.transform.basis.z`) y
  `player._get_input_direction` (`transform.basis`).
- **Evidencia:** `HECHO VERIFICADO`.

#### `_physics_process(delta)` — L55-70
- **Firma:** `func _physics_process(delta: float) -> void`
- **Llama:** Godot (callback automático).
- **Cuándo:** cada tick de física.
- **Lee:** `UiInventario.visible`; `traversal.is_active()`; `_get_input_direction()`.
- **Escribe (rama muerta `:56-60`):** `velocity.x/z = lerp(·, 0.0, 14.0*delta)` y `move_and_slide()`.
- **Escribe (rama activa):** delega a `traversal.process(delta)`.
- **Escribe (rama IDLE):** delega a `movement.process`, `parkour_detector.process`, luego `move_and_slide()`.
- **Siempre:** `kick.process(delta)` (`:70`).
- **Efectos:** despacha todo el movimiento del frame. `move_and_slide()` es la **única** integración de
  colisión del jugador y **solo** ocurre en la rama IDLE (o en la muerta).
- **Guards / returns:** `:56-60` `if UiInventario.visible:` → `return` tras dampear velocidad — **muerto**.
- **Constantes:** `14.0` (factor de damping, rama muerta).
- **Deps externas:** `UiInventario`, `traversal`, `movement`, `parkour_detector`, `kick`.
- **Evidencia:** `HECHO VERIFICADO`. Ver §3.4 (CD-1…CD-5) para la interacción con la pasada auto de
  `traversal._physics_process`.

#### `_get_input_direction()` — L73-79 (helper)
- **Firma:** `func _get_input_direction() -> Vector3`
- **Llama:** `player._physics_process` (rama IDLE, `:65`).
- **Cuándo:** cada tick IDLE.
- **Lee:** acciones `move_forward/move_back/move_left/move_right` (`Input.is_action_pressed`);
  `transform.basis.z`, `transform.basis.x` (base del cuerpo, **no de la cámara**).
- **Escribe:** —.
- **Retorno:** `Vector3` **normalizado** (dir. horizontal deseada en espacio mundo) o `Vector3.ZERO`.
- **Guards / returns:** ninguno (normaliza siempre; `ZERO.normalized()` = `ZERO`).
- **Constantes:** —.
- **Consumidores:** `movement.process(delta, direction)` → `_apply_movement`.
- **Evidencia:** `HECHO VERIFICADO`. Nota: `forward = -transform.basis.z`, `right = +transform.basis.x`
  (`:75-78`). No hay componente Y (movimiento puramente horizontal en espacio del cuerpo).

#### `_hay_techo()` — L81-87 (helper)
- **Firma:** `func _hay_techo() -> bool`
- **Llama:** `player._input` (`:49`), en el manejo de `crouch`.
- **Cuándo:** al presionar `crouch` estando ya agachado y sin traversal activo.
- **Lee:** `global_position`; `collision.shape.height` (**altura viva del collider**, puede estar a
  mitad de lerp); `get_world_3d().direct_space_state`.
- **Escribe:** —.
- **Efectos:** raycast vertical `origen = global_position` → `destino = global_position + UP*(collision.shape.height + 0.6)`,
  `exclude = [self]`. Retorna `true` si golpea algo.
- **Guards / returns:** retorna `intersect_ray(query).size() > 0`.
- **Constantes:** `0.6` (margen sobre la altura del collider). **Sin máscara explícita** → usa el default
  de `PhysicsRayQueryParameters3D` (todas las capas).
- **Deps externas:** `PhysicsRayQueryParameters3D`, `direct_space_state`.
- **Consumidores:** `player._input` decide `pass` (no pararse) vs togglear crouch.
- **Evidencia:** `HECHO VERIFICADO`. `INFERENCIA FUNDADA`: como el origen es `global_position` (centro de
  la cápsula, ~1.0 sobre los pies), el rayo mide desde el centro, no desde la cabeza; con `height≈2.0` de
  pie el rayo llega a `y_centro + 2.6`.

---

### 4.2 `scripts/player n entities/movement/movement_controller.gd`

Variables de estado: `current_speed` (float, init `SPEED`), `is_crouching` (bool), `on_platform` (bool),
`_jumped` (bool). Propiedad `jumped` (getter de `_jumped`, L24-25) — **sin consumidores** en el worktree
(`grep` no encuentra lecturas de `.jumped`). `HECHO VERIFICADO`.

#### `setup(p_body, p_camera, p_collision)` — L27-30
- **Firma:** `func setup(p_body: CharacterBody3D, p_camera: Camera3D, p_collision: CollisionShape3D) -> void`
- **Llama:** `player._ready` (`:24`). **Cuándo:** una vez.
- **Escribe:** `body`, `camera`, `collision_shape` (refs internas).
- **Guards / returns:** ninguno. **Evidencia:** `HECHO VERIFICADO`.

#### `process(delta, direction)` — L32-38
- **Firma:** `func process(delta: float, direction: Vector3) -> void`
- **Llama:** `player._physics_process` rama IDLE (`:66`). **Cuándo:** cada tick con `not traversal.is_active()`.
- **Lee:** `direction` (de `_get_input_direction`).
- **Efectos:** ejecuta en orden fijo: `_update_jump_state()` → `_apply_gravity(delta)` → `_handle_jump()`
  → `_update_crouch(delta)` → `_update_speed(delta)` → `_apply_movement(delta, direction)`.
- **Guards / returns:** ninguno. **Evidencia:** `HECHO VERIFICADO` (orden literal `:33-38`).

#### `freeze()` — L40-42
- **Firma:** `func freeze() -> void`
- **Llama:** `traversal._change_state` (`:571`), sólo en la transición inactivo→activo.
- **Cuándo:** al entrar a cualquier estado de traversal desde IDLE.
- **Escribe:** `body.velocity.x = 0.0`, `body.velocity.z = 0.0` (**NO toca `velocity.y`**).
- **Guards / returns:** ninguno.
- **Consumidores del resultado:** el `_state_*` que entra normalmente pone `body.velocity = Vector3.ZERO`
  igual en su primer tick, así que `freeze()` sólo cubre el gap entre `_change_state` y el primer tick de
  estado. `HECHO VERIFICADO`. `INFERENCIA FUNDADA`: `velocity.y` residual se descarta igual en el primer
  tick del estado (`body.velocity = Vector3.ZERO`).
- **Evidencia:** `HECHO VERIFICADO`.

#### `set_crouching(value)` — L44-45
- **Firma:** `func set_crouching(value: bool) -> void` → `is_crouching = value`.
- **Llama:** `player._input` (`:52`). **Cuándo:** al togglear crouch fuera de traversal.
- **Escribe:** `is_crouching`. **Guards:** ninguno. **Evidencia:** `HECHO VERIFICADO`.

#### `set_on_platform(value)` — L47-51
- **Firma:** `func set_on_platform(value: bool) -> void`
- **Llama:** `elevator_platform.gd` inline (`movement_test.tscn:269,276`). **Nunca en la práctica** — el
  elevador está inerte (§8.6). `HECHO VERIFICADO`.
- **Escribe:** `on_platform = value`; si `value` → `body.velocity.y = 0.0`.
- **Efectos:** `on_platform` suspende la gravedad en `_apply_gravity` y activa la rama "piso" de
  `_apply_movement` aunque el jugador no esté en el piso.
- **Guards / returns:** ninguno. **Evidencia:** `HECHO VERIFICADO`.

#### `_update_jump_state()` — L53-55 (helper)
- **Llama:** `process` (primero). **Lee:** `body.is_on_floor()`. **Escribe:** `_jumped = false` si en piso.
- **Efectos:** resetea la marca de "salté yo" al tocar piso → afecta la fricción aérea (`_apply_movement`).
- **Evidencia:** `HECHO VERIFICADO`.

#### `_apply_gravity(delta)` — L57-63 (helper)
- **Llama:** `process`. **Lee:** `on_platform`, `body.is_on_floor()`, `body.get_gravity()`.
- **Escribe:** `body.velocity.y` (`= 0.0` si `on_platform`; `+= get_gravity()*delta` si no está en piso).
- **Guards / returns:** `if on_platform: velocity.y = 0.0; return`. Si `is_on_floor()` → no aplica nada.
- **Constantes:** ninguna propia — usa `body.get_gravity()` (gravedad de proyecto; `DESCONOCIDO` el
  valor exacto, no aparece en `project.godot`; `INFERENCIA FUNDADA`: default Godot `-9.8` m/s² en Y).
- **Evidencia:** `HECHO VERIFICADO`.

#### `_handle_jump()` — L65-68 (helper)
- **Llama:** `process`. **Lee:** acción `jump` (**`is_action_pressed`**, sostenida, no flanco);
  `body.is_on_floor()`; `is_crouching`.
- **Escribe:** `body.velocity.y = JUMP_VELOCITY`; `_jumped = true`.
- **Guards / returns:** condición `Input.is_action_pressed("jump") and body.is_on_floor() and not is_crouching`.
- **Constantes:** `JUMP_VELOCITY = 4.5`.
- **Evidencia:** `HECHO VERIFICADO`. `INFERENCIA FUNDADA`: no hay doble-salto por tecla sostenida porque
  `is_on_floor()` pasa a `false` el tick siguiente; el piso es la guarda de facto. No hay coyote-time ni
  buffer de salto.

#### `_update_crouch(delta)` — L70-78 (helper)
- **Llama:** `process`. **Lee:** `is_crouching`; `collision_shape.shape.height`; `camera.position.y`.
- **Escribe:** `collision_shape.shape.height = lerp(·, target_height, CROUCH_TRANSITION*delta)`;
  `camera.position.y = lerp(·, target_camera_y, CROUCH_TRANSITION*delta)`.
- **Constantes:** `target_height = 0.8` (agachado) / `2.0` (de pie); `target_camera_y = 0.4` / `0.706`;
  `CROUCH_TRANSITION = 8.0`.
- **Efectos:** encoge/estira la cápsula y baja/sube la cámara **cada tick** (aunque no cambie `is_crouching`,
  sigue lerpeando hacia el target — converge y se queda). **Muta el sub-resource `CapsuleShape3D`
  compartido** (`INFERENCIA FUNDADA`: si `player.tscn` se instanciara ≥2 veces sin `resource_local_to_scene`,
  compartirían el shape; hay un solo jugador, así que no importa en la práctica).
- **Guards / returns:** ninguno — **no corre durante traversal** (§3.6): el collider queda congelado.
- **Consumidores:** `player._hay_techo` lee `collision.shape.height`; `parkour_detector` **no** usa el
  collider real (usa cápsula fija de clearance, §6).
- **Evidencia:** `HECHO VERIFICADO`. La altura de pie real de V1 es **2.0**.

#### `_update_speed(delta)` — L80-88 (helper)
- **Llama:** `process`. **Lee:** `is_crouching`, `body.is_on_floor()`, acción `run` (`is_action_pressed`).
- **Escribe:** `current_speed = lerp(current_speed, target_speed, ACCELERATION*delta)`.
- **Constantes:** `target_speed` ∈ {`CROUCH_SPEED=2.5` si `is_crouching and is_on_floor()`,
  `RUN_SPEED=9.0` si `run`, `SPEED=5.0` si no}; `ACCELERATION = 14.0`.
- **Efectos:** la velocidad objetivo también se suaviza (no es escalón). Crouch sólo baja la velocidad
  **en el piso**.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_apply_movement(delta, direction)` — L90-111 (helper)
- **Llama:** `process` (último). **Lee:** `body.is_on_floor()`, `on_platform`, `body.velocity`,
  `current_speed`, `direction`, `_jumped`.
- **Escribe:** `body.velocity.x`, `body.velocity.z`.
- **Rama piso/plataforma (`:91-101`):**
  - `velocity.x = lerp(velocity.x, direction.x*current_speed, ACCELERATION*delta)` (idem z).
  - Clamp: si `Vector2(velocity.x, velocity.z).length() > current_speed` → renormaliza a `current_speed`.
- **Rama aire (`:102-111`):**
  - con `direction != ZERO`: `air_control = AIR_CONTROL_FAST (0.3) if vel_h > 7.0 else AIR_CONTROL_SLOW (1.5)`;
    `velocity.x/z = lerp(·, direction.x/z * current_speed, air_control*delta)`. **Sin clamp de máximo.**
  - sin `direction`: `friction = AIR_FRICTION (0.8) if _jumped else FALL_FRICTION (3.0)`;
    `velocity.x/z = lerp(·, 0.0, friction*delta)`.
- **Constantes:** `ACCELERATION=14.0`, `AIR_CONTROL_FAST=0.3`, `AIR_CONTROL_SLOW=1.5` (umbral `7.0` m/s
  hardcodeado), `AIR_FRICTION=0.8`, `FALL_FRICTION=3.0`.
- **Efectos:** define toda la sensación de aceleración/control aéreo. El umbral 7.0 es un **escalón duro**
  (sin interpolación entre 0.3 y 1.5).
- **Evidencia:** `HECHO VERIFICADO`.

---

### 4.3 `scripts/player n entities/movement/parkour_detector.gd`

Señales: `candidate_found(Dictionary)`, `candidate_lost()`, `ladder_candidate_found(Dictionary)`,
`ladder_candidate_lost()` (L13-16). Estado interno: `_last_candidate` (Dict), `_has_candidate` (bool),
`_has_ladder_candidate` (bool), `_last_ladder_candidate` (Dict), `_cooldown_timer` (float).

#### `setup(p_body, p_camera, p_traversal=null)` — L52-55
- **Llama:** `player._ready` (`:25`). **Escribe:** `body`, `camera`, `traversal` (ref).
- **Nota:** `traversal` se pasa para leer `traversal.last_hanging_pos` en `_process_ledge`. `HECHO VERIFICADO`.

#### `start_cooldown()` — L57-58
- **Firma:** `func start_cooldown() -> void` → `_cooldown_timer = detection_cooldown`.
- **Llama:** `traversal._release` (`:553`) — en toda salida de estado **con `use_cooldown=true`**
  (default). **NO** se llama en la salida de LADDER por crouch (`_release(Vector3.ZERO, false)`, §8.7).
- **Escribe:** `_cooldown_timer`. **Constante:** `detection_cooldown = 0.8` (export).
- **Consumidores:** `process()` (bloquea toda detección mientras `> 0`).
- **Evidencia:** `HECHO VERIFICADO`.

#### `process(delta)` — L61-73
- **Llama:** `player._physics_process` rama IDLE (`:67`). **Cuándo:** cada tick con `not traversal.is_active()`.
- **Lee:** `_cooldown_timer`; `body.is_on_floor()`.
- **Escribe:** `_cooldown_timer -= delta`.
- **Flujo:**
  - `:62-66` si `_cooldown_timer > 0.0` → decrementa, `_clear_candidate()`, `_clear_ladder_candidate()`, `return`.
  - `:68-71` si `body.is_on_floor()` → `_clear_candidate()` (ledge apagado en el piso); si no → `_process_ledge()`.
  - `:73` `_process_ladder()` — **siempre** (si no hay cooldown), en piso o no.
- **Guards / returns:** el `return` del cooldown.
- **Evidencia:** `HECHO VERIFICADO`. Consecuencia clave: **la detección de borde NO corre mientras el
  jugador está en el piso** — no hay rama "en piso avanzando".

#### `_process_ledge()` — L79-97
- **Llama:** `process` (si no en piso). **Lee:** resultado de `_find_best_candidate()`;
  `traversal.last_hanging_pos`; `best["edge_point"]`, `best["score"]`; `body.global_position`.
- **Escribe:** `_last_candidate`, `_has_candidate`.
- **Señales:** `candidate_found.emit(best)` (`:97`).
- **Guards / returns:**
  - `:82-84` `if best.is_empty() or best["score"] < min_score:` → `_clear_candidate()`, `return`.
  - `:86-93` si `traversal.last_hanging_pos != ZERO`: si `best.edge_point.distance_to(last) < 2.0` →
    clear+return; si `body.global_position.distance_to(last) < 2.0` → clear+return. **Zona de exclusión
    espacial** (§6.5, §8.8).
- **Constantes:** `min_score = 0.35`; `2.0` (radio de exclusión, hardcodeado).
- **Consumidores del resultado:** `traversal._on_candidate_found` (conectado en `setup`).
- **Evidencia:** `HECHO VERIFICADO`.

#### `get_current_candidate()` — L99-100 · `has_candidate()` — L102-103 (helpers/getters)
- Retornan `_last_candidate` / `_has_candidate`. **Sin consumidores** en el worktree (`grep`). `HECHO VERIFICADO`.

#### `_process_ladder()` — L109-168
- **Llama:** `process`. **Cuándo:** cada tick sin cooldown (piso o no).
- **Lee:** `body.get_world_3d().direct_space_state`; `body.global_position`; `body.collision_mask`;
  `segment.start_marker/end_marker`; resultado de `_is_within_segment_volume`, `_has_ladder_intent`;
  `_last_ladder_candidate`.
- **Escribe:** `_last_ladder_candidate`, `_has_ladder_candidate`.
- **Efectos:** `intersect_shape` con `SphereShape3D(radius = ladder_detection_radius)` en
  `body.global_position`, `exclude=[body]`, `collision_mask = body.collision_mask` (=9). Por cada
  colisión: `_find_segment` (sube ≤4 padres buscando grupo `"ladder"`). Dibuja markers en `DebugDraw`
  (esferas verde/rojo, rayo naranja, `:154-160`).
- **Señales:** `ladder_candidate_found.emit(candidate)` (`:165`) — **sólo si**
  `not ladder_detected() or _last_ladder_candidate.get("area") != segment` (evita re-emitir por frame).
- **Guards / returns por cada resultado:**
  - `collider == null` → `continue`.
  - `_find_segment(collider) == null` → `continue`.
  - `segment.get("start_marker") == null or ... end_marker == null` (dos chequeos, `:134-137`) → `continue`.
  - `not _is_within_segment_volume(segment)` → `continue`.
  - `not _has_ladder_intent(segment)` → `continue`.
  - tras emitir (o si ya estaba) → `return` (procesa **un solo** segmento por tick).
  - si el `for` termina sin `return` → `_clear_ladder_candidate()`.
- **Constantes:** `ladder_detection_radius = 1.0`.
- **Candidato emitido:** `{ "type": "ladder", "area": <nodo segmento> }`.
- **Consumidores:** `traversal._on_ladder_candidate_found`.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_find_segment(node)` — L170-178 (helper)
- **Firma:** `func _find_segment(node: Node) -> Node`
- **Llama:** `_process_ladder`. **Lee:** `node`, cadena de `get_parent()`, `is_in_group("ladder")`.
- **Efectos:** `for _i in range(4)`: si `current.is_in_group("ladder")` → retorna `current`; si no,
  `current = current.get_parent()`. Retorna `null` si no encuentra en 4 niveles.
- **Constantes:** `4` (profundidad máxima de ascenso).
- **Evidencia:** `HECHO VERIFICADO`. `INFERENCIA FUNDADA`: 4 niveles alcanzan `carcasa (CollisionShape3D)
  → StaticBody3D` (1 nivel); el margen es para jerarquías con nodos intermedios.

#### `_has_ladder_intent(_segment)` — L180-188 (helper)
- **Firma:** `func _has_ladder_intent(_segment: Node) -> bool` — **el parámetro `_segment` se ignora**
  (prefijo `_`, no se usa en el cuerpo). §8.
- **Llama:** `_process_ladder`. **Lee:** `body.is_on_floor()`; acción `crouch` (`is_action_pressed`).
- **Retorno:** `false` si `is_on_floor()`; `false` si `crouch` presionado; `true` si no.
- **Evidencia:** `HECHO VERIFICADO`. Consecuencia: **una escalera nunca se activa desde el piso**; hay
  que estar en el aire y sin agacharse. No requiere tecla de movimiento.

#### `_is_within_segment_volume(segment)` — L190-209 (helper)
- **Llama:** `_process_ladder`. **Lee:** `segment.start_marker/end_marker` (`.global_position`);
  `body.global_position`.
- **Cálculo:** `seg_vec = end - start`; `seg_len = |seg_vec|`; si `< 0.001` → `false`.
  `progress = (body.pos - start)·seg_dir / seg_len`. Si `progress < 0.0 or > 1.0` → `false`.
  `projected = start + seg_dir * (progress * seg_len)`;
  `lateral_dist = body.pos.distance_to(projected)`. Retorna `lateral_dist <= ladder_detection_radius`.
- **Constantes:** `0.001` (epsilon), `ladder_detection_radius = 1.0`.
- **Evidencia:** `HECHO VERIFICADO`. Commit `5ca2d70`: esta función **había estado desconectada** y se
  "reconectó" para arreglar "meterse en el ladder desde cualquier lado".

#### `ladder_detected()` — L211-212 · `get_current_ladder_candidate()` — L214-215 (getters)
- Retornan `_has_ladder_candidate` / `_last_ladder_candidate`. `ladder_detected()` se usa internamente en
  `_process_ladder`. `get_current_ladder_candidate` **sin consumidores** (`grep`). `HECHO VERIFICADO`.

#### `_clear_ladder_candidate()` — L217-221 (helper)
- **Llama:** `process` (cooldown) y `_process_ladder` (fin del `for`).
- **Escribe:** si `_has_ladder_candidate` → `false`, `_last_ladder_candidate = {}`,
  `ladder_candidate_lost.emit()`.
- **Señales:** `ladder_candidate_lost` — **sin consumidores conectados** (§9.2).
- **Evidencia:** `HECHO VERIFICADO`.

#### `_find_best_candidate()` — L227-253
- **Llama:** `_process_ledge`. **Lee:** `body.get_world_3d().direct_space_state`;
  `-body.transform.basis.z` (`facing`); `body.global_position`.
- **Efectos:** por cada `probe_offset` en `PROBE_HEIGHTS = [0.3, 0.6, 0.9, 1.2, 1.5]`:
  `origin = body.global_position + UP*probe_offset`; `candidate = _probe_at(space, origin, facing)`;
  si no vacío → `score = _score_candidate(candidate)`, `candidate["score"] = score`;
  dibuja `DebugDraw.point/sphere` en `edge_point` con color según score (`:242-244`); se queda con el de
  mayor `score` (**no** el primero). Al final dibuja esfera cian en el mejor (`:250-251`).
- **Retorno:** el `Dictionary` de mayor score, o `{}`.
- **Constantes:** `PROBE_HEIGHTS` (5 alturas).
- **Evidencia:** `HECHO VERIFICADO`.

#### `_probe_at(space, origin, facing)` — L255-307
- **Llama:** `_find_best_candidate` (1× por altura de probe).
- **Lee:** `space` (`direct_space_state`); `origin`, `facing`; `body.global_position.y`.
- **Efectos / secuencia** (detalle geométrico completo en §6.1):
  1. Raycast pared: `origin → origin + facing*detection_distance` (`0.85`). Dibuja (`gris`/`blanco`).
     Sin hit → `{}`.
  2. `wall_normal`, `wall_point` del hit.
  3. `max_normal_y = sin(deg_to_rad(max_surface_tilt_deg))` (`sin30° ≈ 0.5`); si `abs(wall_normal.y) > max_normal_y` → `{}`.
  4. `search_top = body.global_position.y + max_edge_height + 0.3` (= y + 1.8).
  5. Raycast borde (hacia abajo): `edge_search_origin = (wall_point.x, search_top, wall_point.z) - wall_normal*0.08`
     → `edge_search_end = (wall_point.x, wall_point.y, wall_point.z) - wall_normal*0.08`. Dibuja
     (`gris`/`aqua`). Sin hit → `{}`.
  6. `edge_point = edge_hit.position`.
  7. Coherencia lateral XZ: `Vector2(wall_point.xz).distance_to(Vector2(edge_point.xz)) > 0.35` → `{}`.
  8. `edge_normal.dot(UP) < cos(deg_to_rad(30°))` (`cos30° ≈ 0.866`) → `{}`.
  9. `height_diff = edge_point.y - body.global_position.y`; si `< min_edge_height (0.5)` o `> max_edge_height (1.5)` → `{}`.
  10. `_check_clearance(space, edge_point)` falso → `{}`.
- **Retorno:** `{ "type":"ledge", "wall_normal", "wall_point", "edge_point", "height_diff", "score":0.0 }`.
- **Constantes:** `detection_distance=0.85`, `max_surface_tilt_deg=30.0`, `max_edge_height=1.5`, `0.3`
  (sobre-altura de búsqueda), `0.08` (offset del rayo de borde hacia la pared), `0.35` (tolerancia
  lateral), `min_edge_height=0.5`.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_score_candidate(c)` — L309-334
- **Llama:** `_find_best_candidate`. **Lee:** `-body.transform.basis.z` (`facing`); `c["wall_normal"]`;
  `body.velocity.x/z`; `camera.global_transform.basis.z`; `body.global_position`; `c["edge_point"]`.
- **Cálculo:**
  - `wall_dot = facing.dot(-c.wall_normal)`; si `< 0.3` → `return 0.0`; si no `score += wall_dot * 0.35`.
  - si `Vector2(velocity.x, velocity.z).length() > 0.5`: `vel_dir = normalize(vx,0,vz)`;
    `score += clamp(vel_dir.dot(-c.wall_normal), 0, 1) * 0.30`.
  - `cam_forward = -camera.basis.z`; `cam_forward.y = 0`; normalizado;
    `score += clamp(cam_forward.dot(-c.wall_normal), 0, 1) * 0.20`.
  - `dist = body.global_position.distance_to(c.edge_point)`;
    `dist_score = 1.0 - clamp(dist / (detection_distance * 2.5), 0, 1)` (denominador `2.125`);
    `score += dist_score * 0.15`.
  - `return clamp(score, 0.0, 1.0)`.
- **Constantes:** `0.3` (umbral de `wall_dot`), pesos `0.35 / 0.30 / 0.20 / 0.15` (suman 1.0), `0.5`
  (umbral de velocidad para el término de velocidad), `2.5` (multiplicador de rango de distancia).
- **Evidencia:** `HECHO VERIFICADO`. `facing` para `wall_dot` = **frente del cuerpo**; el término de
  cámara es aparte y sólo suma.

#### `_raycast(space, from, to)` — L340-343 (helper)
- **Firma:** `func _raycast(space, from: Vector3, to: Vector3) -> Dictionary`
- **Llama:** `_probe_at` (×2: pared y borde).
- **Efectos:** `PhysicsRayQueryParameters3D.create(from, to)`; `query.exclude = [body]`;
  `return space.intersect_ray(query)`.
- **Constantes:** **sin `collision_mask` explícita** → default (todas las capas).
- **Evidencia:** `HECHO VERIFICADO`.

#### `_check_clearance(space, edge_point)` — L345-357 (helper)
- **Llama:** `_probe_at` (paso 10). **Lee:** `edge_point`; `body.collision_mask`.
- **Efectos:** `CapsuleShape3D(radius = clearance_radius, height = clearance_height)` = **(0.25, 1.2)**;
  `intersect_shape` en `Transform3D(IDENTITY, edge_point + UP*(clearance_height*0.5 + 0.1))` (= `edge_point + UP*0.7`);
  `exclude=[body]`, `collision_mask = body.collision_mask`. Retorna `results.is_empty()`.
- **Constantes:** `clearance_radius = 0.25`, `clearance_height = 1.2`, `0.1` (offset extra), `0.5`
  (mitad de altura).
- **Evidencia:** `HECHO VERIFICADO`. La cápsula de clearance (0.25 × 1.2) es **más chica** que la del
  jugador de pie (r≈0.5 × 2.0).

#### `_clear_candidate()` — L359-363 (helper)
- **Llama:** `process`, `_process_ledge`. **Escribe:** si `_has_candidate` → `false`, `_last_candidate = {}`,
  `candidate_lost.emit()`.
- **Señales:** `candidate_lost` — **sin consumidores conectados** (§9.2).
- **Evidencia:** `HECHO VERIFICADO`.

---

### 4.4 `scripts/player n entities/movement/traversal_controller.gd`

Señales: `traversal_started()`, `traversal_ended()` (L14-15) — **sin consumidores conectados** (§9.1).
`enum State { IDLE, SNAPPING, HANGING, CLIMBING, LADDER }` (L18). Variable `state` init `IDLE`.

**Variables de estado interno** (L44-65):

| Var | Tipo | Init | Para qué |
|---|---|---|---|
| `_hang_position` | Vector3 | ZERO | posición mundial de agarre (la que se escribe a `body.global_position`). |
| `_hang_position_target` | Vector3 | ZERO | destino de la transición de cara (shimmy en esquina). |
| `_transitioning_face` | bool | false | hay una transición de cara en curso. |
| `_hang_normal` | Vector3 | ZERO | normal de la pared agarrada (apunta **fuera** de la pared, hacia el jugador). |
| `_along_wall` | Vector3 | ZERO | tangente lateral del borde (`UP × _hang_normal`). |
| `_can_go_left` / `_can_go_right` | bool | false | el probe lateral encontró borde de ese lado. |
| `last_hanging_pos` | Vector3 | ZERO | **público** — lo lee `parkour_detector._process_ledge`. Zona de exclusión. |
| `_last_hang_clear_timer` | float | 0.0 | cuenta atrás para limpiar `last_hanging_pos` en el aire. |
| `is_crouch_blocked_after_drop` | bool | false | **público** — lo lee `player._input`. |
| `_shimmy_dir` | float | 0.0 | -1/+1 moviéndose, 0 quieto, -99/+99 bloqueado (centinela para no repetir log). |
| `_current_segment` | Node | null | segmento de escalera activo. |
| `_current_progress` | float | 0.0 | progreso 0..1 sobre el segmento. |
| `_ladder_pulse_timer` | float | 0.0 | acumulador del pulso rítmico. |
| `_ladder_dir` | float | 0.0 | -1/+1/0 dirección de trepada. |
| `_event_log` | Array | [] | log circular de eventos (máx `LOG_MAX = 12`). |
| `_snap_timer` | float | 0.0 | cuenta el tiempo en SNAPPING para el timeout. |

**Constantes** (L35, L68, L78-80): `PROBE_OFFSETS_INNER = [-0.7, -0.4, -0.1, 0.1, 0.4, 0.7]`;
`LOG_MAX = 12`; `HANG_OFFSET_Y = -0.55`; `HANG_WALL_GAP = -0.68`; `SNAP_TIMEOUT = 1.0`.

#### `_log(msg)` — L71-75 (helper)
- **Firma:** `func _log(msg: String) -> void`
- **Llama:** casi todas las funciones de estado y transición.
- **Escribe:** `_event_log.append({ "t": Time.get_ticks_msec()/1000.0, "msg": msg })`; recorta a `LOG_MAX`.
- **Consumidores:** `traversal.get_event_log()` → sólo lo lee `debug_traversal.gd` (**inerte**, §8.2). En
  la práctica el log **se llena pero nunca se muestra**. `HECHO VERIFICADO`.
- **Deps externas:** `Time`.

#### `setup(p_body, p_camera, p_movement, p_detector)` — L84-90
- **Llama:** `player._ready` (`:26`). **Cuándo:** una vez.
- **Escribe:** `body`, `camera`, `movement`, `detector` (refs).
- **Señales:** **conecta** `detector.candidate_found → _on_candidate_found` y
  `detector.ladder_candidate_found → _on_ladder_candidate_found` (`:89-90`). **NO conecta**
  `candidate_lost` ni `ladder_candidate_lost`.
- **Evidencia:** `HECHO VERIFICADO`.

#### `is_active()` — L92-93 · `get_state_name()` — L98-99 · `get_event_log()` — L123-124 (getters)
- `is_active()` → `state != State.IDLE`. **Consumidores:** `player._input` (`:47`), `player._physics_process`
  (`:62`). Crítico.
- `get_state_name()` → `State.keys()[state]`. **Consumidores:** `debug_ui.gd:25`, y `get_debug_state`.
- `get_event_log()` → `_event_log`. **Consumidor:** `debug_traversal.gd` (inerte).
- **Evidencia:** `HECHO VERIFICADO`.

#### `process(delta)` — L95-96 (wrapper)
- **Firma:** `func process(delta: float) -> void` → cuerpo: `_physics_process(delta)`.
- **Llama:** `player._physics_process` rama activa (`:63`).
- **Efecto:** ejecuta `_physics_process` **una vez más** (pasada manual). Ver §3.4 CD-1/CD-3.
- **Evidencia:** `HECHO VERIFICADO`.

#### `get_debug_state()` — L102-121 (getter)
- Retorna un `Dictionary` con `state`, `active`, `hang_pos`, `hang_normal`, `along_wall`, `can_go_left`,
  `can_go_right`, `shimmy_dir`, `snap_timer`, `snap_dist` (`body.global_position.distance_to(_hang_position)`),
  `ladder_dir`, `ladder_progress`, e `in_left/in_right/in_fwd/in_back/in_jump` (lecturas crudas de
  `Input.is_action_pressed`).
- **Consumidor:** `debug_traversal.gd:59` (inerte). **Evidencia:** `HECHO VERIFICADO`.

#### `_physics_process(delta)` — L127-148  ⚠ CALLBACK AUTO + PASADA MANUAL (§3.4)
- **Llama:** (A) Godot cada tick; (B) `player._physics_process` vía `process()` cuando `is_active()`.
- **Lee:** `state`; `is_crouch_blocked_after_drop`; acción `crouch` (`is_action_pressed`);
  `body.is_on_floor()`; `_last_hang_clear_timer`.
- **Escribe:** `is_crouch_blocked_after_drop`, `last_hanging_pos`, `_last_hang_clear_timer`.
- **Efectos:**
  - `:128` `DebugDraw.clear()` — **incondicional, cada tick** (borra lo del detector, §3.4 CD-5).
  - `:130-140` rama `state == IDLE`: desarma `is_crouch_blocked_after_drop` si `not crouch`; si
    `is_on_floor()` → `last_hanging_pos = ZERO`, `_last_hang_clear_timer = 0.0`; elif `_last_hang_clear_timer > 0.0`
    → decrementa, y al llegar a `<= 0` → `last_hanging_pos = ZERO`. Luego `return`.
  - `:142-146` `match state:` → `_state_snapping / _state_hanging / _state_climbing / _state_ladder (delta)`.
  - `:148` `_draw_debug()`.
- **Guards / returns:** `return` en la rama IDLE.
- **Evidencia:** `HECHO VERIFICADO`. La rama IDLE es load-bearing y sólo funciona por la pasada auto (CD-2).

#### `_on_candidate_found(candidate)` — L154-168
- **Llama:** señal `detector.candidate_found`.
- **Cuándo:** cada vez que el detector emite (puede ser todos los frames mientras haya candidato válido).
- **Lee:** `state`; `candidate["wall_normal"]`, `candidate["edge_point"]`.
- **Escribe:** `_hang_normal`, `_along_wall` (`= UP.cross(_hang_normal).normalized()`), `_hang_position`,
  `_hang_position_target` (`= _hang_position`), `_snap_timer = 0.0`.
- **Cálculo de `_hang_position`:** `Vector3(edge.x, edge.y + HANG_OFFSET_Y, edge.z)` luego
  `-= _hang_normal * HANG_WALL_GAP`. Con `HANG_OFFSET_Y=-0.55` baja 0.55; con `HANG_WALL_GAP=-0.68`,
  `- normal * (-0.68) = + normal * 0.68` → aleja 0.68 de la pared (§6.6).
- **Señales:** consume `candidate_found`.
- **Guards / returns:** `:155-156` `if state != State.IDLE: return` — **un candidato nuevo nunca
  interrumpe un estado activo**.
- **Efectos:** `_log("candidato aceptado — snap iniciado")`; `_change_state(State.SNAPPING)`.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_on_ladder_candidate_found(candidate)` — L175-202
- **Llama:** señal `detector.ladder_candidate_found`.
- **Lee:** `candidate["area"]` (nodo segmento); `_current_segment.start_marker/end_marker.global_position`;
  `body.global_position`.
- **Escribe:** `_current_segment`; `_current_progress` (`= clamp((body.pos - seg_start)·seg_dir / seg_len, 0, 1)`,
  o `0.0` si `seg_len <= 0.001`); `_ladder_pulse_timer = 0.0`; `_ladder_dir = 0.0`.
- **Señales:** consume `ladder_candidate_found`.
- **Guards / returns:** **NINGUNO** — ⚠ a diferencia de `_on_candidate_found`, **no chequea
  `state != IDLE`**. Ver §8.
- **Efectos:** `_log("escalera — entrada …")`; `_change_state(State.LADDER)`.
- **Evidencia:** `HECHO VERIFICADO`. `INFERENCIA FUNDADA`: si el detector emite este candidato mientras
  el estado es SNAPPING/HANGING/CLIMBING, entraría a LADDER pisando el estado — pero el detector **no
  corre durante traversal** (`player.gd` no lo llama), así que en la práctica sólo llega desde IDLE.
  La falta de guarda es una bomba latente, no un bug activo en este flujo.

#### `_state_snapping(delta)` — L207-225
- **Llama:** `_physics_process` (`match`). **Cuándo:** cada tick (×2, CD-3) mientras `state == SNAPPING`.
- **Lee:** acción `jump` (`is_action_just_pressed`); `_snap_timer`; `body.global_position`; `_hang_position`.
- **Escribe:** `body.velocity = Vector3.ZERO` (cada tick); `_snap_timer += delta`; `body.global_position`.
- **Flujo:**
  - `body.velocity = Vector3.ZERO`.
  - `:210-211` `if is_action_just_pressed("jump")` → `_release(Vector3.UP * jump_force)` (pop vertical de
    **6.5**, ≠ salto normal 4.5); `return`.
  - `:214-219` `_snap_timer += delta`; si `> SNAP_TIMEOUT` (1.0) → `push_warning(...)`,
    `_log("SNAP abortado — TIMEOUT")`, `_release(_hang_normal * 2.0)` (empujón horizontal), `return`.
  - `:221` `body.global_position = body.global_position.lerp(_hang_position, snap_speed * delta)`
    (`snap_speed = 14.0`).
  - `:223-225` si `distance_to(_hang_position) < snap_threshold` (0.2) → snap exacto + `_change_state(HANGING)`.
- **Señales:** vía `_release`/`_change_state`.
- **Guards / returns:** el de `jump`, el de timeout.
- **Constantes:** `jump_force = 6.5`, `SNAP_TIMEOUT = 1.0`, `snap_speed = 14.0`, `snap_threshold = 0.2`,
  `2.0` (empujón de timeout).
- **Efectos físicos:** convergencia tipo lerp hacia `_hang_position`. `INFERENCIA FUNDADA`: exponencial
  (proporcional a la distancia restante), no lineal ni de duración fija. Con CD-3, converge ~2× más rápido.
- **Inputs ignorados:** crouch, back, move_left/right, escalera — no escuchados.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_state_hanging(delta)` — L231-290
- **Llama:** `_physics_process`. **Cuándo:** cada tick (×2, CD-3) mientras `state == HANGING`.
- **Lee:** acciones `jump`, `move_back`, `crouch` (todas `is_action_just_pressed`); `move_left`, `move_right`
  (`is_action_pressed`); `_can_go_left`, `_can_go_right`, `_shimmy_dir`; `_along_wall`; `_transitioning_face`;
  `_hang_position`, `_hang_position_target`; `detector.detection_cooldown`.
- **Escribe:** `body.velocity = ZERO`; `_shimmy_dir`; `_hang_position` (+= paso lateral y/o smooth);
  `_hang_position_target`; `_transitioning_face`; `last_hanging_pos`; `_last_hang_clear_timer`;
  `is_crouch_blocked_after_drop`; `body.global_position = _hang_position` (al final, `:290`).
- **Flujo (orden exacto):**
  1. `body.velocity = Vector3.ZERO`.
  2. `:234-237` `jump` (flanco) → `_log("hanging → CLIMBING")`, `_change_state(CLIMBING)`, `return`.
  3. `:239-242` `move_back` (flanco) → `_release(_hang_normal*3.5 + UP*1.0)`, `return`.
  4. `:244-250` `crouch` (flanco) → `last_hanging_pos = _hang_position`,
     `_last_hang_clear_timer = detector.detection_cooldown` (0.8), `is_crouch_blocked_after_drop = true`,
     `_release(Vector3.ZERO)`, `return`.
  5. `:252` `_update_shimmy_probes()`.
  6. `:254-270` calcula `dir`: `-1` si `move_left and _can_go_left`; `+1` si `move_right and _can_go_right`.
     Si se presiona un lado sin `_can_go_*` → setea `_shimmy_dir` centinela (`-99`/`99`) y loguea 1 vez;
     si no, `_shimmy_dir = dir`.
  7. `:272-275` si `dir != 0.0`: `step = _along_wall * dir * shimmy_speed * delta`;
     `_hang_position += step`; `_hang_position_target += step`.
  8. `:277-288` si `_transitioning_face`: si `dir == 0.0` → `body.velocity = ZERO`, `_apply_virtual_normal()`,
     `_transitioning_face = false`; si `dir != 0.0` → `_hang_position.x/z = lerp(·, target.x/z, 4.0*delta)`,
     y si la dist XZ al target `< 0.01` → `_transitioning_face = false`.
  9. `:290` `body.global_position = _hang_position`.
- **Señales:** vía `_release`/`_change_state`.
- **Guards / returns:** los 3 de salida (jump/back/crouch).
- **Constantes:** `shimmy_speed = 2.5`, `4.0` (lerp de transición de cara, hardcodeado), `0.01`
  (umbral de fin de transición), `-99.0`/`99.0` (centinelas), `detector.detection_cooldown` (0.8).
- **Efectos físicos:** desplazamiento lateral a velocidad constante (con CD-3, ~2×); realineación en
  esquinas.
- **Inputs ignorados:** `move_forward` no hace nada en HANGING.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_state_climbing(delta)` — L296-304
- **Llama:** `_physics_process`. **Cuándo:** cada tick (×2, CD-3) mientras `state == CLIMBING`.
- **Lee:** `_hang_position`, `_hang_normal`; `body.global_position`.
- **Escribe:** `body.velocity = ZERO`; `body.global_position` (lerp).
- **Flujo:**
  - `body.velocity = Vector3.ZERO`.
  - `target = _hang_position + Vector3.UP * 2.2 - _hang_normal * 0.4` — **offset fijo**, calculado a
    partir del `_hang_position`/`_hang_normal` del momento en que arrancó CLIMBING.
  - `body.global_position = body.global_position.lerp(target, climb_speed * delta)` (`climb_speed = 4.0`).
  - si `distance_to(target) < 0.12` → snap exacto + `_release(-_hang_normal * 1.5)` (empujón **hacia** la
    superficie).
- **Guards / returns:** ninguno — **no escucha ningún input, no se puede cancelar**.
- **Constantes:** `2.2` (subida vertical del target), `0.4` (retroceso desde la normal), `climb_speed = 4.0`,
  `0.12` (umbral de llegada), `1.5` (empujón de salida).
- **Efectos físicos:** `HECHO VERIFICADO` — **la función no contiene ninguna query de física**
  (`intersect_ray/shape`, `test_move`). No verifica que arriba haya piso. Siempre llega al target.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_state_ladder(delta)` — L312-384
- **Llama:** `_physics_process`. **Cuándo:** cada tick (×2, CD-3) mientras `state == LADDER`.
- **Lee:** acciones `jump`, `crouch` (`is_action_just_pressed`); `move_forward`, `move_back`
  (`is_action_pressed`); `camera.global_transform.basis.z`; `_current_segment` (`.get("move_speed")`,
  `.move_speed`, `.get_length()`, `.get_position_at()`, `.get_neighbour_up()`, `.get_neighbour_down()`);
  `_current_progress`; `_ladder_pulse_timer`; `_ladder_dir`.
- **Escribe:** `body.velocity = ZERO`; `_ladder_dir`; `_ladder_pulse_timer`; `_current_progress`;
  `_current_segment` (en transición); `body.global_position` (reconstruida cada tick).
- **Flujo:**
  1. `body.velocity = Vector3.ZERO`.
  2. `:317-323` `jump` (flanco) → `cam_fwd = -camera.basis.z` aplanado y normalizado;
     `_release(cam_fwd*4.0 + UP*5.0)`, `return`.
  3. `:326-329` `crouch` (flanco) → `_release(Vector3.ZERO, false)` — **`use_cooldown = false`** (único
     en el archivo, §8.7), `return`.
  4. `:332-343` `pressing_up = move_forward`, `pressing_down = move_back`. Si `up and not down` →
     `_ladder_dir = 1.0`; elif `down and not up` → `-1.0`; **else** (ninguno o ambos) → `_ladder_dir = 0.0`,
     `_ladder_pulse_timer = 0.0`, `body.global_position = _current_segment.get_position_at(_current_progress)`,
     `return`.
  5. `:346-348` `pulse_time = ladder_pulse_time` (0.18); si `_current_segment.get("move_speed")` (truthy)
     → `pulse_time /= max(_current_segment.move_speed, 0.1)`.
  6. `:350-381` `_ladder_pulse_timer += delta`; si `>= pulse_time`: resta `pulse_time`;
     `seg_len = _current_segment.get_length()`;
     `progress_step = ladder_pulse_speed * pulse_time / max(seg_len, 0.001)` (`ladder_pulse_speed = 0.8`);
     `new_progress = _current_progress + _ladder_dir * progress_step`.
     - si `new_progress > 1.0`: `neighbour = get_neighbour_up()`; si `!= null` →
       `_current_segment = neighbour`, `_current_progress = new_progress - 1.0`; si no → `_current_progress = 1.0`.
     - si `new_progress < 0.0`: simétrico con `get_neighbour_down()` (`_current_progress = 1.0 + new_progress`).
     - si no → `_current_progress = new_progress`.
     - `_log("escalera — progress: …")`.
  7. `:384` `body.global_position = _current_segment.get_position_at(_current_progress)`.
- **Señales:** vía `_release`.
- **Guards / returns:** jump, crouch, y el `return` de "sin input de avance".
- **Constantes:** `4.0` (jump fwd), `5.0` (jump up), `ladder_pulse_time = 0.18`, `0.1` (piso de
  `move_speed`), `ladder_pulse_speed = 0.8`, `0.001` (epsilon de `seg_len`).
- **Efectos físicos:** avance discreto (pulsos) sobre `progress`; posición mundial reconstruida por
  `get_position_at` (lerp lineal marker↔marker). Con CD-3, ~2× el ritmo de pulso.
- **Inputs ignorados:** `move_left`/`move_right` no hacen nada en LADDER.
- **`ladder_snap_strength` (export, 0.3):** **NO se usa en esta función ni en ninguna** (§8). El
  comentario `:32` dice "atracción al centro XZ al entrar" pero no hay código.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_update_shimmy_probes()` — L390-424
- **Llama:** `_state_hanging` (`:252`), cada tick de HANGING.
- **Lee:** `_along_wall`; `_shimmy_dir`; `_hang_normal`; `_hang_position`; resultados de `_edge_continues`
  (izq/der) y `_calculate_tangent`.
- **Escribe:** `_can_go_left`, `_can_go_right`; `_hang_normal`, `_along_wall` (si cambia la cara);
  `_hang_position_target`, `_transitioning_face`.
- **Flujo:**
  - `result_left = _edge_continues(_along_wall * -1.0)`; `result_right = _edge_continues(_along_wall * 1.0)`.
  - `_can_go_left = not result_left.is_empty()`; idem derecha.
  - Si `_shimmy_dir < 0.0 and _can_go_left` → `new_normal = result_left["wall_normal"]`; elif
    `_shimmy_dir > 0.0 and _can_go_right` → `new_normal = result_right["wall_normal"]`.
  - Si `new_normal != ZERO and new_normal != _hang_normal`:
    - `_log("normal cambia: …")`; `_hang_normal = new_normal`; `_along_wall = UP.cross(_hang_normal).normalized()`.
    - elige `ref_point` (wall_point del lado activo, con fallbacks `:409-417`).
    - `_hang_position_target = Vector3(ref_point.x, _hang_position.y, ref_point.z) - _hang_normal * HANG_WALL_GAP`;
      `_transitioning_face = true`.
  - `_calculate_tangent()`.
- **Guards / returns:** ninguno explícito (varias ramas condicionales).
- **Constantes:** `HANG_WALL_GAP = -0.68`.
- **Efectos:** detecta esquinas por diferencia de `wall_normal` del probe lateral — **sin marcadores**,
  a diferencia de la escalera. Commit `8ae5b1a` ("agarrarse en curvas y hacer tp a la siguiente normal").
- **Evidencia:** `HECHO VERIFICADO`.

#### `_calculate_tangent()` — L426-462
- **Llama:** `_update_shimmy_probes` (`:424`). **Cuándo:** cada tick de HANGING.
- **Lee:** `_shimmy_dir`; `_along_wall`; resultados de `_edge_continues` en 6 offsets.
- **Escribe:** `_along_wall` (suavizado hacia la tangente medida).
- **Flujo:**
  - `:427-428` si `_shimmy_dir == 0.0` → `return` (sólo recalcula si se está shimmyeando).
  - Para cada `offset` en `PROBE_OFFSETS_INNER = [-0.7,-0.4,-0.1,0.1,0.4,0.7]`: `r = _edge_continues(_along_wall * offset)`;
    acumula `r["wall_point"]` en centroide izquierdo (offset<0) o derecho (offset>0), con contadores.
  - Si `count_left == 0 or count_right == 0` → `return`.
  - `centroid_left/right /= count`; `raw_tangent = centroid_right - centroid_left`; `raw_tangent.y = 0`;
    si `|raw_tangent| < 0.001` → `return`; `target_tangent = normalize(raw_tangent)`.
  - `_along_wall = _along_wall.lerp(target_tangent, 0.15)`; `_along_wall.y = 0`;
    si `|_along_wall| < 0.001` → `return`; `_along_wall = normalize(_along_wall)`.
- **Constantes:** `PROBE_OFFSETS_INNER` (6 offsets), `0.15` (**lerp SIN `delta`** — fracción fija por
  frame, no por segundo, §8), `0.001` (epsilons).
- **Efectos:** permite seguir superficies curvas/con ángulo variable sin salto de orientación.
- **Evidencia:** `HECHO VERIFICADO`. `INFERENCIA FUNDADA`: al ser lerp por frame (no por tiempo), a
  mayor FPS `_along_wall` converge más rápido en tiempo real (dependencia de framerate).

#### `_apply_virtual_normal()` — L464-504
- **Llama:** `_state_hanging` (`:280`), sólo cuando se suelta el input de shimmy en medio de una
  transición de cara (`_transitioning_face and dir == 0.0`).
- **Lee:** `_hang_position`; `_along_wall`; `_hang_normal`; `body.get_world_3d().direct_space_state`.
- **Escribe:** `_hang_normal`, `_along_wall`, `_hang_position` (todo "de compromiso" promediado).
- **Flujo:**
  - `edge_y_offset = abs(HANG_OFFSET_Y) - 0.15` (= 0.40); `probe_origin = _hang_position + (0, 0.40, 0)`.
  - Para cada `offset` en `PROBE_OFFSETS_INNER`: `probe = probe_origin + _along_wall*offset`;
    `to_wall = -_hang_normal`; raycast `probe + to_wall*-0.2` → `probe + to_wall*1.0`, `exclude=[body]`.
    Si hit y `abs(normal.y) <= sin(deg_to_rad(30°))` → acumula `hit.normal` y `hit.position`.
  - Si `count == 0` → `return` (el jugador se queda donde estaba).
  - `avg_normal = normalize(sum_normal / count)`; `avg_position = sum_position / count`.
  - `_hang_normal = avg_normal`; `_along_wall = UP.cross(_hang_normal).normalized()`;
    `_hang_position = Vector3(avg_position.x - avg_normal.x*HANG_WALL_GAP, _hang_position.y, avg_position.z - avg_normal.z*HANG_WALL_GAP)`.
- **Constantes:** `HANG_OFFSET_Y = -0.55`, `0.15` (resta), `0.2`/`1.0` (extensión del rayo),
  `sin(deg_to_rad(30.0))`, `HANG_WALL_GAP = -0.68`.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_edge_continues(lateral_dir, dist=-1.0)` — L506-542
- **Firma:** `func _edge_continues(lateral_dir: Vector3, dist: float = -1.0) -> Dictionary`
- **Llama:** `_update_shimmy_probes` (2×), `_calculate_tangent` (6×). **`dist` explícito nunca se pasa**
  en ningún call site → siempre usa `shimmy_max_dist`.
- **Lee:** `_hang_position`; `_hang_normal`; `body.get_world_3d().direct_space_state`.
- **Escribe:** —.
- **Flujo (geometría completa en §6.2):**
  - `probe_dist = dist if dist > 0.0 else shimmy_max_dist` (0.5).
  - `edge_y_offset = abs(HANG_OFFSET_Y) - 0.15` (= 0.40).
  - `probe_origin = _hang_position + (0, 0.40, 0)`; `probe = probe_origin + lateral_dir * probe_dist`.
  - `to_wall = -_hang_normal`; `wall_from = probe + to_wall*-0.2`; `wall_to = probe + to_wall*1.0`.
  - `wall_hit = intersect_ray(wall_from → wall_to)`, `exclude=[body]`. Dibuja (`azul`/`gris`).
  - si vacío → `{}`.
  - si `abs(wall_hit.normal.y) > sin(deg_to_rad(30°))` → dibuja `rojo`, `{}`.
  - `edge_from = wall_hit.position + UP*0.4 - _hang_normal*0.05`; `edge_to = edge_from + DOWN*0.7`.
  - `edge_hit = intersect_ray(edge_from → edge_to)`, `exclude=[body]`. Dibuja (`verde`/`rojo`).
  - si vacío → `{}`.
  - retorna `{ "wall_normal": wall_hit.normal, "wall_point": wall_hit.position }`.
- **Constantes:** `shimmy_max_dist = 0.5`, `HANG_OFFSET_Y = -0.55`, `0.15`, `0.2`/`1.0` (rayo de pared),
  `sin30°`, `0.4`/`0.05` (rayo de borde), `0.7` (largo del rayo de borde hacia abajo).
- **Retorno consumido por:** `_update_shimmy_probes` (`_can_go_*`, cambio de normal),
  `_calculate_tangent` (centroides).
- **Evidencia:** `HECHO VERIFICADO`.

#### `_release(exit_velocity, use_cooldown=true)` — L548-555
- **Firma:** `func _release(exit_velocity: Vector3, use_cooldown: bool = true) -> void`
- **Llama:** `_state_snapping` (2×), `_state_hanging` (2×), `_state_climbing` (1×), `_state_ladder` (2×).
- **Escribe:** `body.velocity = exit_velocity`; `_current_segment = null`.
- **Efectos:** si `use_cooldown` → `detector.start_cooldown()` (0.8 s). `_change_state(State.IDLE)`.
- **Guards / returns:** ninguno.
- **Llamadas concretas (todas `HECHO VERIFICADO`):**
  | Origen | `exit_velocity` | `use_cooldown` |
  |---|---|---|
  | SNAPPING + jump | `UP * 6.5` | true |
  | SNAPPING + timeout | `_hang_normal * 2.0` | true |
  | HANGING + move_back | `_hang_normal * 3.5 + UP * 1.0` | true |
  | HANGING + crouch | `Vector3.ZERO` | true |
  | CLIMBING (llegó al target) | `-_hang_normal * 1.5` | true |
  | LADDER + jump | `cam_fwd_horizontal * 4.0 + UP * 5.0` | true |
  | LADDER + crouch | `Vector3.ZERO` | **false** |
- **Evidencia:** `HECHO VERIFICADO`. La `velocity` que setea `_release` **sí** se integra porque el
  siguiente tick el estado es IDLE y `player.gd` vuelve a llamar `move_and_slide()`.

#### `_change_state(new_state)` — L557-574
- **Llama:** `_on_candidate_found`, `_on_ladder_candidate_found`, `_state_snapping`, `_state_hanging`,
  `_release` (todas las transiciones).
- **Lee:** `state` (previo); `is_active()` antes y después.
- **Escribe:** `state = new_state`; si `new_state != HANGING` → `_can_go_left = false`, `_can_go_right = false`,
  `_shimmy_dir = 0.0`.
- **Efectos / señales:**
  - `_log("%s → %s")`.
  - si `not was_active and now_active` → `movement.freeze()` + `traversal_started.emit()`.
  - si `was_active and not now_active` → `traversal_ended.emit()`.
- **Guards / returns:** ninguno.
- **Señales:** emite `traversal_started` / `traversal_ended` — **sin consumidores** (§9.1).
- **Evidencia:** `HECHO VERIFICADO`.

#### `_draw_debug()` — L579-613 (helper)
- **Llama:** `_physics_process` (`:148`), tras el `match`, sólo si no es IDLE.
- **Lee:** `state`; `_hang_position`, `_hang_normal`, `_along_wall`; `_can_go_left/right`;
  `_current_segment` (markers, `get_position_at`).
- **Escribe:** —. **Efectos:** primitivas en `DebugDraw` (magenta/amarillo para hang/along;
  verde/rojo para probes de shimmy; naranja/verde/rojo para el segmento de escalera).
- **Guards / returns:** `:580-581` `if state == State.IDLE: return`.
- **Evidencia:** `HECHO VERIFICADO`.

---

### 4.5 `scripts/player n entities/movement/traversal_segment.gd`

`extends Node` (no `Node3D`) — asignado a un `StaticBody3D`. `enum SegmentType { LADDER, ROPE, CABLE, CHAIN }`
(L24); sólo `LADDER` tiene lógica en `traversal_controller` — `ROPE/CABLE/CHAIN` **no tienen ningún
`_state_*`** (`HECHO VERIFICADO` por búsqueda). Exports: `segment_type` (LADDER), `move_speed` (1.0),
`neighbour_up` (NodePath ""), `neighbour_down` (NodePath ""). Vars: `start_marker` (Node3D, null),
`end_marker` (Node3D, null).

#### `_ready()` — L44-51
- **Llama:** Godot. **Escribe:** `start_marker = get_node_or_null("StartMarker")`,
  `end_marker = get_node_or_null("EndMarker")`.
- **Efectos:** `push_warning` si falta alguno. **Guards:** ninguno.
- **Consumidores:** `parkour_detector._process_ladder` chequea que no sean null.
- **Evidencia:** `HECHO VERIFICADO`.

#### `get_position_at(progress)` — L56-59
- **Firma:** `func get_position_at(progress: float) -> Vector3`
- **Llama:** `traversal._state_ladder` (`:342`, `:384`), `traversal._draw_debug` (`:599`).
- **Lee:** `start_marker.global_position`, `end_marker.global_position`.
- **Retorno:** `start.global_position.lerp(end.global_position, progress)` — **lerp lineal**, sin clamp del
  `progress` acá (el clamp lo hace el caller). Si falta un marker → `Vector3.ZERO`.
- **Guards / returns:** `if start_marker == null or end_marker == null: return Vector3.ZERO`.
- **Evidencia:** `HECHO VERIFICADO`. `INFERENCIA FUNDADA`: si el caller pasara `progress` fuera de [0,1]
  extrapolaría; los callers siempre lo mantienen clampeado.

#### `get_direction_at(_progress)` — L64-67
- **Firma:** `func get_direction_at(_progress: float) -> Vector3` — **parámetro `_progress` ignorado**.
- **Llama:** **NADIE** (`grep` no encuentra call sites). Función muerta.
- **Retorno:** `(end.global_position - start.global_position).normalized()`, o `Vector3.UP` si falta marker.
- **Evidencia:** `HECHO VERIFICADO` (existe, sin consumidor).

#### `get_length()` — L70-73
- **Llama:** `traversal._state_ladder` (`:357`). **Retorno:** `start.distance_to(end)`, o `1.0` si falta
  marker. **Evidencia:** `HECHO VERIFICADO`.

#### `get_neighbour_up()` — L76-79 · `get_neighbour_down()` — L82-85
- **Llama:** `traversal._state_ladder` (`:363`, `:371`).
- **Retorno:** `null` si el `NodePath` es `""`; si no, `get_node_or_null(neighbour_up/down)`.
- **Evidencia:** `HECHO VERIFICADO`. Resuelve el `NodePath` **relativo al segmento**, cada vez que se
  llama (no cachea).

---

### 4.6 `scripts/player n entities/movement/kick_controller.gd`

`extends Node`. Exports: `kick_force` (8.0 → **40.0** en `movement_test`), `kick_upward` (0.2). Var:
`_kicked_this_frame` (bool). **No interactúa con traversal, detector ni movement.**

#### `setup(p_body, p_camera, p_raycast)` — L30-33
- **Llama:** `player._ready` (`:27`). **Escribe:** `body`, `camera`, `raycast` (ref a `raycast_interaccion`).
- **Evidencia:** `HECHO VERIFICADO`.

#### `process(_delta)` — L36-40
- **Firma:** `func process(_delta: float) -> void` — **`_delta` ignorado**.
- **Llama:** `player._physics_process` (`:70`) — **siempre**, activo o no.
- **Lee:** acción `kick` (`is_action_just_pressed`).
- **Escribe:** `_kicked_this_frame = false` (reset).
- **Efectos:** si `kick` (flanco) → `_execute_kick()`.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_execute_kick()` — L43-66
- **Llama:** `process`. **Lee:** `_kicked_this_frame`; `camera.global_transform.basis.z`;
  `raycast.objeto_mirado`; `body.global_position`.
- **Escribe:** `_kicked_this_frame = true`.
- **Flujo:**
  - `:44-46` si `_kicked_this_frame` → `return` (guarda de re-entrada en el mismo frame).
  - `facing = -camera.global_transform.basis.z`; `facing.y = 0`; normalizado.
  - `objetivo = raycast.objeto_mirado` (del frame de render anterior).
  - dibuja `DebugDraw.ray(body.global_position + UP*0.1, +facing*1.0, YELLOW)`.
  - `:63-64` si `objetivo == null` → `return`.
  - `_resolve_impact(objetivo, facing)`.
- **Constantes:** `0.1` (altura del origen del debug ray), `1.0` (largo del debug ray).
- **Deps externas:** `raycast_interaccion.objeto_mirado`.
- **Evidencia:** `HECHO VERIFICADO`. La detección de qué golpea NO es un raycast propio — reutiliza el
  del sistema de interacción (máscara `capa_interaccion`, = 3 en `movement_test`).

#### `_resolve_impact(collider, direction)` — L74-76 (helper)
- **Llama:** `_execute_kick`. **Efectos:** `if collider is RigidBody3D: _push_rigidbody(collider, direction)`.
  Comentario `:71-72`: "Cuando haya enemigos con salud, agregar un elif acá" → no hay.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_push_rigidbody(rb, direction)` — L78-83 (helper)
- **Llama:** `_resolve_impact`. **Escribe:** `rb.apply_central_impulse(impulse)`.
- **Cálculo:** `impulse = direction * kick_force`; `impulse.y += kick_force * kick_upward`.
- **Efectos:** empuja el `RigidBody3D`; dibuja esfera roja en `rb.global_position`.
- **Constantes:** `kick_force` (40.0 en `movement_test`), `kick_upward` (0.2).
- **Evidencia:** `HECHO VERIFICADO`.

---

### 4.7 `scripts/player n entities/visuals/debug_draw.gd` (autoload `DebugDraw`)

`extends Node`. Vars: `enabled` (bool, true), `frozen` (bool, false), `_rays`/`_points`/`_spheres`
(Array), `_mesh_instance` (MeshInstance3D), `_immediate` (ImmediateMesh), `_material` (StandardMaterial3D).

#### `_ready()` — L27-41
- Crea `ImmediateMesh`; `StandardMaterial3D` (`SHADING_MODE_UNSHADED`, `vertex_color_use_as_albedo`,
  `no_depth_test = true`, `TRANSPARENCY_ALPHA`); `MeshInstance3D` (`cast_shadow = OFF`);
  `call_deferred("_attach_to_scene")`.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_attach_to_scene()` — L43-46 (helper)
- **Llama:** `_ready` (deferred), `_process` (si salió del árbol).
- **Efectos:** `root = get_tree().current_scene`; si existe → `root.add_child(_mesh_instance)`.
- **Evidencia:** `HECHO VERIFICADO`. `INFERENCIA FUNDADA`: al hacer `reload_current_scene()` (muerte del
  jugador — que no pasa) o cambio de escena, `_mesh_instance` queda huérfano y `_process` lo re-adjunta.

#### `clear()` — L50-55
- **Llama:** `traversal_controller._physics_process` (`:128`) **cada tick**. **NADIE MÁS** llama `clear()`
  (`HECHO VERIFICADO` — `parkour_detector` no la llama, violando el contrato del header `:10-12`).
- **Escribe:** vacía `_rays`, `_points`, `_spheres`.
- **Guards / returns:** `if frozen: return`.
- **Evidencia:** `HECHO VERIFICADO`. Ver §3.4 CD-5.

#### `ray(from, to, color=WHITE)` — L57-60 · `point(pos, color=WHITE, size=0.06)` — L62-65 · `sphere(pos, radius=0.2, color=WHITE)` — L67-70
- **Llama:** `parkour_detector` (`_probe_at`, `_find_best_candidate`, `_process_ladder`),
  `traversal_controller` (`_edge_continues`, `_draw_debug`), `kick_controller` (`_execute_kick`, `_push_rigidbody`).
- **Escribe:** appendea a `_rays` / `_points` / `_spheres`.
- **Guards / returns:** `if not enabled or frozen: return`.
- **Constantes:** `size` default `0.06`, `radius` default `0.2`.
- **Evidencia:** `HECHO VERIFICADO`.

#### `toggle()` — L72-73 · `toggle_freeze()` — L75-76
- `toggle()` → `enabled = not enabled`. **Sin consumidores** (`grep`).
- `toggle_freeze()` → `frozen = not frozen`. **Llama:** `_process` con `toggle_debug_freeze` (tecla G).
- **Evidencia:** `HECHO VERIFICADO`.

#### `_process(_delta)` — L81-88
- **Efectos:** si `_mesh_instance and not is_inside_tree()` → `_attach_to_scene()`; si
  `Input.is_action_just_pressed("toggle_debug_freeze")` → `toggle_freeze()`; `_redraw()`.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_redraw()` — L90-113 (helper)
- **Efectos:** `_immediate.clear_surfaces()`; si los 3 arrays vacíos → `return`;
  `surface_begin(PRIMITIVE_LINES)`; agrega rays (2 vértices c/u), points (`_add_cross`), spheres
  (`_add_sphere_wire`); `surface_end()`.
- **Evidencia:** `HECHO VERIFICADO`.

#### `_add_cross(pos, size, color)` — L115-120 · `_add_sphere_wire(center, radius, color)` — L122-126 · `_add_circle(center, radius, color, segments, plane)` — L128-145 (helpers)
- Dibujan primitivas de línea: cruz de 3 ejes; esfera wireframe de 3 círculos (16 segmentos c/u).
- **Constantes:** `segments := 16`; `TAU` para los ángulos.
- **Evidencia:** `HECHO VERIFICADO`.

---

### 4.8 Scripts de soporte (visuales) — contrato y funciones relevantes a locomoción

#### `debug_ui.gd` — L1-44 (ACTIVO)
- `_process(_delta)` (L6-44): resuelve `player = get_first_node_in_group("player")`;
  `movement = player.get_node("movement/MovementController")` (**`get_node`, crashea si falta**);
  lee `player.velocity.x/y/z`, `player.is_on_floor()`, `player.get_node("Camera3D").rotation.x`,
  `player.rotation.y`, `movement.is_crouching`; `traversal = player.get_node_or_null("movement/TraversalController")`
  → `traversal.get_state_name()` (**path correcto**, a diferencia de `debug_traversal`). Arma el label
  de texto (vel h/v, vel x/z, ángulos, agachado, en piso, estado traversal, pos x/y/z).
- **Escribe:** sólo `label.text`. **No toca locomoción.** `HECHO VERIFICADO`.

#### `debug_traversal.gd` — L1-185 (INERTE)
- `_ready` (L40-47): `player = get_first_node_in_group("player")`;
  `_traversal = player.get_node_or_null("TraversalController")` → **`null`** (el nodo está en
  `player/movement/TraversalController`, no `player/TraversalController`); `visible = false`.
- `_process` (L50-68): `toggle_debug_traversal` (F12) togglea `_enabled`; luego
  `if _traversal == null or not _enabled: visible = false; return` → **siempre corta acá**.
- **Consecuencia:** el panel contextual de traversal (estado frame a frame, input crudo, log de eventos)
  **nunca se muestra**. `_build_text`, `_append_snapping/hanging/climbing`, `_yn`, `_v3`, `_shimmy_label`
  son código muerto en la práctica. `HECHO VERIFICADO` (path incorrecto) + `INFERENCIA FUNDADA` (nunca
  visible).

#### `debug_trail.gd` — L1-40 (NUNCA INSTANCIADO)
- `_ready` crea un `ImmediateMesh` rojo; `_input` togglea `activo` con `toggle_trail` (K); `_process`
  appendea `player.global_position` (con `y -= 1.0`) a `puntos` y dibuja una polilínea.
- **Estado:** `debug_trail.tscn` **no está instanciada en ninguna escena** (`grep`), y `player.tscn` no
  lo incluye. → **el script nunca corre**; la acción `toggle_trail` (K) no hace nada. `HECHO VERIFICADO`.

#### `free_camera.gd` — L1-94 (ACTIVO)
- Cámara `Camera3D` suelta en la raíz de `player.tscn` (hermana del `player`). `_ready`: `current = false`,
  cachea `_player_camera`. `_input`: `toggle_free_cam` (F) → `_toggle()`; si `_active` y mouse motion →
  rota la free cam.
- `_toggle` (L65-80): `_active = not _active`; al activar, copia `global_transform` de `_player_camera`,
  `current = true`; al desactivar, `current = false` y `_player_camera.current = true`.
- `_process` (L51-62): si `_active`, mueve con I/K/J/L/U/O (`_get_move_input`, L85-93) a `move_speed`
  (8.0, ×`fast_multiplier` 3.0 con Shift).
- **Interacción con locomoción:** el jugador **sigue corriendo su física** con la free cam activa
  (`player._physics_process` no la chequea); además el mouse **sigue rotando el cuerpo del jugador**
  (`player._input` no la chequea). `HECHO VERIFICADO`.

#### `raycast_interaccion.gd` — L1-72 (ACTIVO — consumido por kick)
- `_process` (L27-48): raycast `camera.global_position` → `- camera.basis.z * distancia_interaccion`
  (2.5), `mask = capa_interaccion` (**3** en `movement_test`), `exclude = [player]`. Setea
  `objeto_mirado` (= `componente_mirado.get_parent()` o null) y `componente_mirado` (busca
  `InteractionComponent` subiendo padres, `_buscar_interaction_component` L54-61).
- `_input` (L63-72): `interactuar` (E) → `componente_mirado.recibir_interaccion(Interaction.new(player, &"usar"))`.
- **Consumidores:** `kick_controller._execute_kick` lee `objeto_mirado`; `hud.gd`/`marco_enfoque.gd`
  también. `HECHO VERIFICADO`.

#### `salud.gd` — L1-23 (ACTIVO — sin uso real)
- `_ready`: `vida_actual = vida_maxima` (100). `recibir_daño(cantidad)` (L12-17): resta vida, clamp,
  emite `vida_cambiada`, y si `<= 0` emite `murio`. `curar(cantidad)` (L19-22).
- **`recibir_daño` y `curar` NO se llaman en ningún lado del worktree** (`grep`). → **no hay daño de
  caída, no hay ningún daño**. `signal murio` → `player._on_murio` → `reload_current_scene()`, pero
  nunca se dispara. `HECHO VERIFICADO`.

#### `hud.gd` — L1-26 · `marco_enfoque.gd` — L1-58 (ACTIVOS — sólo UI de interacción)
- `hud._process`: lee `raycast.componente_mirado`/`objeto_mirado`; setea `label.text` a `"[E] <nombre>"`.
- `marco_enfoque._process`: proyecta el AABB del objeto mirado a pantalla y posiciona 4 esquinas.
- **No tocan locomoción ni traversal.** `HECHO VERIFICADO`.

---

### 4.9 `elevator_platform.gd` — inline en `movement_test.tscn` (L141-281)

`extends AnimatableBody3D`. Script embebido en el nodo `plataforma_prueba`. **Único punto de código de
toda la escena que llama `movement_controller.set_on_platform()`.** Estado en `movement_test`: **inerte**
(§8.6). Se documenta porque es el único consumidor del contrato `on_platform` del `MovementController`.

- **Exports:** `move_speed` (5.0 en escena), `accel_distance` (1.0), `decel_distance` (1.0), `stations`
  (3 Node3D), `detect_area` (**no seteado en la escena → `null`**).
- `_ready` (L165-169): si `detect_area` → conecta `body_entered`/`body_exited`; `call_deferred("_init_position")`.
  Con `detect_area == null`, **no conecta nada**.
- `_init_position` (L171-176): `global_position = stations[0].global_position`.
- `_physics_process` (L177-189): si `_state == IDLE` → `return` (init state es IDLE); si MOVING, mueve y
  arrastra al pasajero: `_passenger.global_position += platform_delta`.
- `go_to_station(index)` (L190-215): setea el viaje y `_state = MOVING`. **NADIE la llama** (`grep`).
- `_on_body_entered(body)` (L260-270): si `CharacterBody3D` y sin pasajero → `_passenger = body`;
  `movement_node = body.get_node_or_null("movement/MovementController")`; si existe →
  `_movement_ctrl.set_on_platform(true)`.
- `_on_body_exited(body)` (L272-280): `_movement_ctrl.set_on_platform(false)`.
- **Evidencia:** `HECHO VERIFICADO`. Como `detect_area` es `null` y nadie llama `go_to_station`, en
  `movement_test` la plataforma **nunca se mueve y `set_on_platform` nunca se dispara** → toda la
  mecánica `on_platform` de `movement_controller.gd` (`_apply_gravity` línea 59-61, `_apply_movement`
  rama `on_platform`) es **código inalcanzable en esta escena**.

---

## 5. Estados y transiciones

### 5.1 Enum y estado inicial

`bd38e49^:scripts/player n entities/movement/traversal_controller.gd:18-19`:

```gdscript
enum State { IDLE, SNAPPING, HANGING, CLIMBING, LADDER }   # valores 0,1,2,3,4
var state : State = State.IDLE
```

`HECHO VERIFICADO`. Estado inicial: `IDLE`. `is_active()` == `state != IDLE`.

### 5.2 Diagrama textual de la máquina de estados

```
                         detector.candidate_found
                         (state==IDLE, score>=0.35,
                          fuera de zona de exclusión)
              ┌──────────────────────────────────────────────► SNAPPING
              │                                                   │
              │                          jump(flanco) ────────────┤► IDLE   [_release(UP*6.5), cooldown]
              │                          _snap_timer>1.0 ─────────┤► IDLE   [_release(hang_normal*2.0), cooldown, push_warning]
              │                          dist<0.2 ────────────────┼──────► HANGING
              │                                                   │
   IDLE ──────┤                                                   ▼
    ▲ ▲ ▲     │                                        ┌──────► HANGING ◄────┐ (shimmy no cambia de estado)
    │ │ │     │                                        │          │          │
    │ │ │     │                       jump(flanco) ────┤          │  move_left/right + _can_go_* :
    │ │ │     │                                        │          │  shimmy lateral (sigue en HANGING)
    │ │ │     │                                        ▼          │
    │ │ │     │                                     CLIMBING      │
    │ │ │     │                    (sin input; lerp a offset fijo)│
    │ │ │     │                     dist<0.12 ──────────┐         │
    │ │ │     └────────────────────────────────────────┐│         │
    │ │ │                                              ▼▼         │
    │ │ └──────────  _release(-hang_normal*1.5), cooldown  ◄──────┘
    │ │
    │ │            move_back(flanco): _release(hang_normal*3.5 + UP*1.0), cooldown
    │ │            crouch(flanco):    _release(ZERO), cooldown, + last_hanging_pos + is_crouch_blocked_after_drop
    │ │
    │ │      detector.ladder_candidate_found  (NO chequea state; en la práctica sólo desde IDLE)
    │ └──────────────────────────────────────────────────────────► LADDER
    │                                                                │
    │                        jump(flanco):  _release(cam_fwd*4.0 + UP*5.0), cooldown
    └────────────────────────  crouch(flanco): _release(ZERO, use_cooldown=FALSE)  ◄── única salida sin cooldown
                               (avance: pulsos discretos sobre progress; stacking por neighbour_up/down)
```

`HECHO VERIFICADO` (todas las aristas trazadas al código).

### 5.3 Transiciones permitidas (matriz)

| Desde \ Hacia | IDLE | SNAPPING | HANGING | CLIMBING | LADDER |
|---|:-:|:-:|:-:|:-:|:-:|
| **IDLE** | — | `candidate_found` | — | — | `ladder_candidate_found` |
| **SNAPPING** | jump / timeout | — | `dist<snap_threshold` | — | — |
| **HANGING** | move_back / crouch | — | — | jump | — |
| **CLIMBING** | llega al target | — | — | — | — |
| **LADDER** | jump / crouch | — | — | — | — |

`HECHO VERIFICADO`. Notas:
- **No hay** SNAPPING→LADDER, HANGING→LADDER, LADDER→HANGING, CLIMBING→cualquier-cosa-salvo-IDLE.
- **No hay** transición directa IDLE→HANGING (siempre pasa por SNAPPING) ni IDLE→CLIMBING.
- `_on_candidate_found` tiene guarda `state != IDLE → return`. `_on_ladder_candidate_found` **no**
  (§4.4, §8).

### 5.4 Por estado: inputs escuchados / ignorados / efecto en cuerpo, cámara, collider

| | **IDLE** (no traversal) | **SNAPPING** | **HANGING** | **CLIMBING** | **LADDER** |
|---|---|---|---|---|---|
| Inputs escuchados | move_*, jump (sostenido), run, crouch (toggle), mouse, kick, interactuar, esc | `jump` (flanco); mouse; kick | `jump`/`move_back`/`crouch` (flanco), `move_left`/`move_right` (sostenido); mouse; kick | **ninguno** propio; mouse; kick | `jump`/`crouch` (flanco), `move_forward`/`move_back` (sostenido); mouse; kick |
| Inputs ignorados | — | crouch, back, move_*, run | move_forward, run | todos | move_left/right, run, jump-sostenido |
| `body.velocity` | integrada por `movement` + `move_and_slide()` | `= ZERO` cada tick | `= ZERO` cada tick | `= ZERO` cada tick | `= ZERO` cada tick |
| `body.global_position` | por `move_and_slide()` (colisión real) | `= lerp(pos, _hang_position, 14*delta)` | `= _hang_position` (directo) | `= lerp(pos, target_fijo, 4*delta)` | `= segment.get_position_at(progress)` |
| `body.rotation` | por mouse-look (`player._input`) | por mouse-look | por mouse-look | por mouse-look | por mouse-look |
| `camera.rotation` | pitch por mouse-look (clamp ±π/2); `camera.position.y` lerp por `_update_crouch` | pitch por mouse-look; **`camera.position.y` NO se toca** | idem SNAPPING | idem | idem |
| collider (`shape.height`) | lerp por `_update_crouch` (→2.0 o →0.8) | **congelado** (no corre `_update_crouch`) | **congelado** | **congelado** | **congelado** |
| colisión con geometría | **sí** (`move_and_slide`) | **NO** | **NO** | **NO** | **NO** |
| gravedad | sí (`_apply_gravity`) | no | no | no | no |

`HECHO VERIFICADO` (lectura completa de las 4 funciones de estado + `player.gd:62-70`).

### 5.5 Timers, timeouts, cooldowns, abortos

| Mecanismo | Valor | Dónde vive | Efecto | Reset |
|---|---|---|---|---|
| `_snap_timer` | acumula `delta`; timeout a `SNAP_TIMEOUT = 1.0` | `traversal_controller` | en SNAPPING, si `> 1.0` → aborto: `push_warning`, `_release(_hang_normal*2.0)` | `= 0.0` en `_on_candidate_found` |
| `detector._cooldown_timer` | `detection_cooldown = 0.8` | `parkour_detector` | mientras `> 0`, bloquea ledge + ladder | decrementa por `delta` en `process`; se arma con `start_cooldown()` |
| `_last_hang_clear_timer` | `= detector.detection_cooldown` (0.8) al soltarse por crouch | `traversal_controller` | cuenta atrás en IDLE aéreo; al llegar a `<= 0` limpia `last_hanging_pos` | `= 0.0` al tocar piso en IDLE |
| `_ladder_pulse_timer` | acumula `delta`; pulso a `pulse_time` (0.18 / `move_speed`) | `traversal_controller` | dispara 1 paso de `progress` por pulso | `= 0.0` en `_on_ladder_candidate_found` y cuando no hay input de avance |
| aborto de SNAPPING por jump | inmediato | `_state_snapping:210` | `_release(UP*6.5)` | — |
| "aborto" de CLIMBING | **no existe** — no se puede cancelar | — | — | — |

`HECHO VERIFICADO`. **Con la doble ejecución (§3.4 CD-3), `_snap_timer` y `_ladder_pulse_timer`
acumulan `2*delta` por frame** → `SNAP_TIMEOUT` efectivo ≈ 0.5 s, pulso de escalera ≈ 2× ritmo.
`INFERENCIA FUNDADA`.

### 5.6 Rutas que dejan datos residuales

`HECHO VERIFICADO`:

| Ruta | Qué queda seteado | Quién lo limpia |
|---|---|---|
| HANGING → IDLE **por crouch** | `last_hanging_pos = _hang_position` (≠ ZERO); `_last_hang_clear_timer = 0.8`; `is_crouch_blocked_after_drop = true` | `last_hanging_pos`: al tocar piso, o al agotarse el timer en el aire. `is_crouch_blocked_after_drop`: en IDLE cuando se suelta `crouch`. |
| HANGING → IDLE por move_back | (nada residual salvo el cooldown plano del detector) | cooldown del detector (0.8 s) |
| SNAPPING → IDLE (jump o timeout) | `_hang_position`, `_hang_normal`, `_along_wall` quedan con el último valor (no se limpian) | se sobrescriben en el próximo `_on_candidate_found` |
| CLIMBING → IDLE | `_hang_position`, `_hang_normal` quedan con el último valor | idem |
| LADDER → IDLE **por crouch** | `_current_segment = null` (lo hace `_release`); **NO** arma cooldown (§8.7); no toca `last_hanging_pos` | — |
| LADDER → IDLE por jump | `_current_segment = null`; cooldown armado | — |
| cualquier `_change_state` a no-HANGING | `_can_go_left = _can_go_right = false`, `_shimmy_dir = 0.0` | — |

`_event_log` **nunca se limpia** (sólo se recorta a `LOG_MAX = 12`). `HECHO VERIFICADO`.

---

## 6. Detección y probes

Todas las queries usan `body.get_world_3d().direct_space_state`. Sistema de coordenadas Godot: **−Z es
"adelante"**, **+Y es "arriba"**.

### 6.1 Probe de ledge — `parkour_detector._probe_at` (L255-307) + `_find_best_candidate` (L227-253)

**Bucle exterior** (`_find_best_candidate`): 5 probes, uno por altura.

| Parámetro | Valor exacto | Significado geométrico |
|---|---|---|
| Alturas de probe | `PROBE_HEIGHTS = [0.3, 0.6, 0.9, 1.2, 1.5]` | offset en `+Y` desde `body.global_position` (centro de cápsula). Cubre de 0.3 a 1.5 sobre el centro. |
| `origin` (por altura) | `body.global_position + Vector3.UP * probe_offset` | origen del rayo horizontal de pared. |
| `facing` | `-body.transform.basis.z` | **frente del CUERPO** (no de la cámara). El probe siempre apunta a donde "mira" el cuerpo. |
| Selección | mayor `score` de los 5 (no el primero que golpea) | — |

**Query 1 — rayo de pared** (`_raycast`, L340-343):

| Campo | Valor |
|---|---|
| `from` | `origin` |
| `to` | `origin + facing * detection_distance` = `origin + facing * 0.85` |
| Longitud | `0.85` |
| `collision_mask` | **default** (todas las capas — `_raycast` no setea máscara) |
| `exclude` | `[body]` |
| Descartes | sin hit → `{}`; `abs(wall_normal.y) > sin(deg_to_rad(30°))` (≈ 0.5) → `{}` (pared demasiado horizontal, "casi piso/techo") |
| Debug | rayo `gris` si no golpea / `blanco` si golpea |
| Consume | `wall_normal`, `wall_point` |

**Query 2 — rayo de borde (hacia abajo)** (`_raycast`):

| Campo | Valor | Por qué |
|---|---|---|
| `search_top` | `body.global_position.y + max_edge_height + 0.3` = `y + 1.5 + 0.3` = `y + 1.8` | empieza a buscar el borde bien por encima del máximo agarrable. |
| `edge_search_origin` | `Vector3(wall_point.x, search_top, wall_point.z) - wall_normal * 0.08` | sobre el punto de pared, corrido `0.08` **hacia adentro** de la pared (`- wall_normal`, y `wall_normal` apunta hacia afuera). |
| `edge_search_end` | `Vector3(wall_point.x, wall_point.y, wall_point.z) - wall_normal * 0.08` | baja hasta la altura del hit de pared, misma corrección `0.08` hacia adentro. |
| Dirección | `DOWN` (de `search_top` a `wall_point.y`) | busca la primera superficie horizontal desde arriba = el filo superior. |
| `collision_mask` | default | — |
| `exclude` | `[body]` | — |
| Descartes | sin hit → `{}` | no hay filo → no es un borde agarrable. |
| Debug | rayo `gris`/`aqua` | — |
| Consume | `edge_point = edge_hit.position`, `edge_normal = edge_hit.normal` | — |

**Filtros post-query** (en `_probe_at`, orden exacto):

| # | Condición de descarte | Valor | Significado |
|---|---|---|---|
| 7 | `Vector2(wall_point.x, wall_point.z).distance_to(Vector2(edge_point.x, edge_point.z)) > 0.35` | `0.35` | coherencia lateral: pared y filo deben pertenecer a la misma esquina (proyección XZ cercana). |
| 8 | `edge_normal.dot(Vector3.UP) < cos(deg_to_rad(30°))` (≈ 0.866) | `30°` | la superficie del filo debe ser ~horizontal (pisable). |
| 9 | `height_diff < min_edge_height` **o** `height_diff > max_edge_height` | `[0.5, 1.5]` | `height_diff = edge_point.y - body.global_position.y` — **medido desde el centro de la cápsula**, no desde los pies. |
| 10 | `not _check_clearance(space, edge_point)` | ver 6.3 | tiene que haber lugar para el cuerpo sobre el filo. |

**Resultado:** `{ "type":"ledge", "wall_normal", "wall_point", "edge_point", "height_diff", "score":0.0 }`
→ consumido por `_score_candidate` y luego `_process_ledge` → señal `candidate_found` →
`traversal._on_candidate_found`.

`HECHO VERIFICADO` todo lo anterior.

### 6.2 Probe de continuación de borde (shimmy) — `traversal._edge_continues` (L506-542)

Mismo patrón "pared + filo" que el detector, pero lateral y anclado a `_hang_position`.

| Parámetro | Valor exacto | Significado |
|---|---|---|
| `probe_dist` | `dist if dist > 0.0 else shimmy_max_dist` → **siempre `0.5`** (nunca se pasa `dist`) | cuán adelante (lateral) se testea que el borde siga. |
| `edge_y_offset` | `abs(HANG_OFFSET_Y) - 0.15` = `0.55 - 0.15` = `0.40` | altura del origen del probe **sobre `_hang_position`** → `0.15` por debajo del filo real (porque `_hang_position` está `0.55` bajo el filo). |
| `probe_origin` | `_hang_position + Vector3(0, 0.40, 0)` | — |
| `probe` | `probe_origin + lateral_dir * probe_dist` | `lateral_dir` = `_along_wall * ±1.0` (o `_along_wall * offset` en `_calculate_tangent`). |
| `to_wall` | `-_hang_normal` | apunta **hacia adentro** de la pared. |
| rayo de pared `from` | `probe + to_wall * -0.2` = `probe + _hang_normal * 0.2` | 0.2 hacia afuera del probe (lado jugador). |
| rayo de pared `to` | `probe + to_wall * 1.0` = `probe - _hang_normal * 1.0` | 1.0 hacia adentro. Longitud total **1.2**. |
| `exclude` | `[body]` | — |
| máscara | default | — |
| descarte pared | sin hit → `{}`; `abs(wall_hit.normal.y) > sin(deg_to_rad(30°))` → `{}` (dibuja `rojo`) | pared ausente o demasiado inclinada. |
| rayo de filo `from` | `wall_hit.position + Vector3.UP * 0.4 - _hang_normal * 0.05` | 0.4 arriba del hit de pared, 0.05 hacia adentro. |
| rayo de filo `to` | `edge_from + Vector3.DOWN * 0.7` | baja 0.7. |
| descarte filo | sin hit → `{}` (dibuja `rojo`) | no hay filo horizontal → borde no continúa. |
| Debug | rayo de pared `azul`/`gris`; rayo de filo `verde`/`rojo` | — |
| Resultado | `{ "wall_normal", "wall_point" }` | — |

**Consumidores:** `_update_shimmy_probes` (`_can_go_left/right` = ¿resultado no vacío?; cambio de
`_hang_normal` si la normal difiere); `_calculate_tangent` (centroides de `wall_point`).

`HECHO VERIFICADO`.

### 6.3 Clearance — `parkour_detector._check_clearance` (L345-357)

| Parámetro | Valor | Significado |
|---|---|---|
| Shape | `CapsuleShape3D`, `radius = clearance_radius = 0.25`, `height = clearance_height = 1.2` | volumen de test — **más chico que el jugador de pie (r≈0.5 × 2.0)**. |
| `transform` | `Transform3D(Basis.IDENTITY, edge_point + Vector3.UP * (clearance_height * 0.5 + 0.1))` = `edge_point + UP * 0.7` | centro de la cápsula a 0.7 sobre el filo (mitad de 1.2 + 0.1 de margen). |
| `exclude` | `[body]` | — |
| `collision_mask` | `body.collision_mask` (= 9, capas 1 y 4) | — |
| Resultado | `results.is_empty()` → `true` = hay lugar | si algo intersecta, el candidato se descarta **entero** (no hay "válido para hang pero no para mantle"). |

`HECHO VERIFICADO`.

### 6.4 Detección de escalera — `parkour_detector._process_ladder` (L109-168) + helpers

**Query — shape query esférica:**

| Parámetro | Valor | Significado |
|---|---|---|
| Shape | `SphereShape3D`, `radius = ladder_detection_radius = 1.0` | radio de "cercanía" a la escalera. |
| `transform` | `Transform3D(Basis.IDENTITY, body.global_position)` | centrada en el jugador. |
| `exclude` | `[body]` | — |
| `collision_mask` | `body.collision_mask` (= 9) | incluye capa 1 (donde está la escalera). |

**Filtros por resultado** (orden exacto, todos `continue` = descartan ese collider):

| # | Función / condición | Detalle |
|---|---|---|
| 1 | `collider == null` | — |
| 2 | `_find_segment(collider)` (L170-178) | sube ≤ 4 padres buscando `is_in_group("ladder")`. `null` → descarta. |
| 3 | `segment.get("start_marker") == null or segment.get("end_marker") == null` **y** `segment.start_marker == null or segment.end_marker == null` | doble chequeo (property + valor). |
| 4 | `_is_within_segment_volume(segment)` (L190-209) | proyecta `body.global_position` sobre el eje `start→end`; `progress` debe estar en `[0, 1]` (**sin tolerancia**); `lateral_dist = body.pos.distance_to(projected)` debe ser `<= ladder_detection_radius` (1.0). |
| 5 | `_has_ladder_intent(segment)` (L180-188) | `false` si `body.is_on_floor()`; `false` si `Input.is_action_pressed("crouch")`; el parámetro `segment` **se ignora**. |

**Emisión:** `ladder_candidate_found.emit({ "type":"ladder", "area": segment })` sólo si
`not ladder_detected() or _last_ladder_candidate.get("area") != segment`. Tras emitir → `return`
(un segmento por tick). Dibuja: esfera `verde` en `start_marker`, `roja` en `end_marker`, rayo `naranja`
entre ambos.

`HECHO VERIFICADO`.

### 6.5 Zona de exclusión espacial de ledge — `parkour_detector._process_ledge` (L86-93)

```gdscript
if traversal and traversal.last_hanging_pos != Vector3.ZERO:
    var last = traversal.last_hanging_pos
    if best["edge_point"].distance_to(last) < 2.0:            _clear_candidate(); return
    if body.global_position.distance_to(last) < 2.0:          _clear_candidate(); return
```

| Parámetro | Valor | Significado |
|---|---|---|
| radio | `2.0` (hardcodeado, no exportado) | ni el filo candidato ni el jugador pueden estar a < 2.0 de `last_hanging_pos`. |
| `last_hanging_pos` | lo setea `traversal._state_hanging` **sólo** en la salida por crouch (L246) | no aplica a salida por move_back ni a CLIMBING ni a LADDER. |
| Aplica a | **sólo ledges** | las escaleras no tienen zona de exclusión (§8.8). |

`HECHO VERIFICADO`.

### 6.6 Significado geométrico de cada vector

`HECHO VERIFICADO` salvo donde se indique:

| Vector | Definición en código | Apunta hacia | Uso |
|---|---|---|---|
| `facing` (detector) | `-body.transform.basis.z` | frente del **cuerpo** (yaw del jugador) | dirección del rayo de pared; término `wall_dot` del score. |
| `cam_forward` (score) | `-camera.global_transform.basis.z`, con `.y = 0`, normalizado | frente **horizontal** de la cámara | término de cámara del score (peso 0.20). |
| `cam_fwd` (LADDER jump) | `-camera.global_transform.basis.z`, `.y = 0`, normalizado | idem | dirección del salto al bajarse de la escalera. |
| `wall_normal` / `_hang_normal` | `hit["normal"]` del rayo de pared | **fuera** de la pared, hacia el lado del jugador | base de `_hang_position`, `_along_wall`, releases. |
| `-c["wall_normal"]` / `-_hang_normal` / `to_wall` | negación de la anterior | **hacia adentro** de la pared | `wall_dot` (¿el jugador encara la pared?); dirección de los rayos laterales de shimmy. |
| `_along_wall` | `Vector3.UP.cross(_hang_normal).normalized()` | tangente horizontal del borde (perpendicular a la normal y a UP) | dirección del paso lateral de shimmy; refinada por `_calculate_tangent`. |
| `_along_wall * dir` con `dir = -1` (move_left) | — | un sentido de la tangente | paso lateral izquierdo. `INFERENCIA FUNDADA`: con `_hang_normal = +Z`, `_along_wall = +X`; `dir=+1` (move_right) = `+X` = derecha del jugador que encara `-Z`. |
| `Vector3.UP` | `(0,1,0)` | arriba mundo | offset vertical del hang, del target de mantle, de los orígenes de probe; componente de los releases con hop. |
| `HANG_OFFSET_Y` (`-0.55`) sumado a `edge.y` | baja el hang **0.55** bajo el filo | abajo | el jugador cuelga por debajo del filo. |
| `- _hang_normal * HANG_WALL_GAP` con `HANG_WALL_GAP = -0.68` | `= + _hang_normal * 0.68` | **fuera** de la pared | separa el cuerpo `0.68` de la cara de la pared (para que la cápsula no se incruste). El **doble negativo** (restar un negativo) es la fuente de confusión: efectivamente **suma**. |
| `Vector3.UP * 2.2` (CLIMBING target) | sube **2.2** desde `_hang_position` | arriba | destino vertical del mantle — **fijo, sin relación con la geometría de arriba**. |
| `- _hang_normal * 0.4` (CLIMBING target) | `0.4` hacia la pared | adentro | mete el destino del mantle `0.4` sobre la superficie (para caer "adentro" del borde). |
| `- _hang_normal * 1.5` (release de CLIMBING) | `1.5` hacia la pared/superficie | adentro | empujón final para asentar al jugador sobre el filo tras el mantle. |
| `_hang_normal * 3.5 + UP * 1.0` (release move_back) | 3.5 fuera de la pared + 1.0 arriba | afuera + arriba | salto hacia atrás soltándose. |
| `_hang_normal * 2.0` (release timeout SNAPPING) | 2.0 fuera de la pared | afuera | empujón sin componente vertical. |
| `UP * 6.5` (release jump SNAPPING) | 6.5 arriba | arriba | pop vertical puro (`jump_force`, ≠ salto normal 4.5). |
| `cam_fwd * 4.0 + UP * 5.0` (release jump LADDER) | 4.0 al frente de cámara + 5.0 arriba | frente-cámara + arriba | salto fuerte hacia afuera de la escalera. |
| `raw_tangent = centroid_right - centroid_left` (`_calculate_tangent`) | de los puntos de pared izquierdos a los derechos, `.y = 0` | tangente medida de la superficie | objetivo del suavizado de `_along_wall` (lerp 0.15/frame). |
| `edge_from = wall_hit.position + UP*0.4 - _hang_normal*0.05` | 0.4 arriba del hit, 0.05 adentro | — | origen del rayo hacia abajo que confirma el filo lateral. |

---

## 7. Inventario de valores puestos a dedo

> Cada número por separado. "Riesgo" = qué se rompe / cambia si se toca, según lectura del código.
> Todos `HECHO VERIFICADO` en cuanto a valor y ubicación; la columna "Posible razón" es
> `INFERENCIA FUNDADA` salvo cita de commit.

### 7.1 `player.gd`

| Valor | Dónde | Efecto directo | Posible razón | Evidencia | Riesgo al cambiarlo |
|---|---|---|---|---|---|
| `0.003` | `MOUSE_SENSITIVITY` (`:7`), usado en `_input` | factor de yaw/pitch por pixel de mouse | sensibilidad estándar para 1600×900 | `bd38e49^:.../player.gd:7,39-40` | sólo feel de cámara; no afecta física. |
| `46` | `floor_max_angle = deg_to_rad(46)` (`:21`) | pendiente máxima que el motor trata como "piso" | permitir rampas empinadas (`StaticBody3D2` es 45°) | `:21` | > : el jugador "resbala" en menos rampas; < : deja de poder pararse en la rampa de 45°. |
| `0.5` | `floor_snap_length` (`:22`) **y** `player.tscn:29` | distancia de snap al piso al bajar rampas/escalones | evitar despegue en escaleras GLB | `:22`, `scenes/components/player.tscn:29` | > : se "pega" a salientes lejanas; < : rebota bajando escaleras. |
| `true` | `floor_stop_on_slope` (`:20`) | no desliza parado en pendiente | quietud en rampas | `:20` | `false` → el jugador resbala solo en toda rampa. |
| `0.6` | `_hay_techo` (`:84`), `collision.shape.height + 0.6` | margen del rayo anti-pararse sobre la altura del collider | holgura para detectar techo apenas encima de la cabeza | `:84` | > : bloquea pararse con techos altos; < : deja pararse dentro de un techo bajo. |
| `PI/2` | clamp de `camera.rotation.x` (`:41`) | límite de pitch ±90° exactos | evitar dar vuelta la cámara | `:41` | cambia el rango de mirada vertical. |
| `14.0` | damping de `velocity.x/z` en la rama `UiInventario.visible` (`:57-58`) | frenaría al jugador con inventario abierto | — | `:57-58` | **RAMA MUERTA** (§8.3) — cambiarlo no tiene efecto. |

### 7.2 `movement_controller.gd` — constantes de locomoción

| Valor | Constante / línea | Efecto directo | Posible razón | Riesgo al cambiarlo |
|---|---|---|---|---|
| `5.0` | `SPEED` (`:4`) | velocidad base a pie | — | toda la sensación base de caminar; afecta alcance de salto (velocidad horizontal al despegar). |
| `9.0` | `RUN_SPEED` (`:5`) | velocidad con `run` | — | alcance de salto corrido; el detector usa `vel_h > 7.0` internamente (score) → cambiar esto cruza/no cruza ese umbral. |
| `2.5` | `CROUCH_SPEED` (`:6`) | velocidad agachado **en piso** | — | sólo feel agachado. |
| `4.5` | `JUMP_VELOCITY` (`:7`) | `velocity.y` al saltar | — | altura/alcance de salto; interactúa con `min_edge_height`/`max_edge_height` del detector (a qué bordes llegás en el aire). |
| `14.0` | `ACCELERATION` (`:8`) | rapidez del lerp de velocidad en piso (accel Y frenado) **y** clamp de velocidad | — | > : más "digital"; < : más "patinoso". También es el factor del clamp de `_apply_movement`. |
| `8.0` | `CROUCH_TRANSITION` (`:9`) | rapidez del lerp de altura de collider y de cámara | — | velocidad de agacharse/pararse; afecta cuánto tarda el collider en cambiar (y por ende `_hay_techo`). |
| `0.3` | `AIR_CONTROL_FAST` (`:10`) | autoridad de redirección aérea **con `vel_h > 7.0`** | proteger el momentum de un salto corrido | poco control aéreo a alta velocidad; subirlo hace el salto corrido "flotante". |
| `1.5` | `AIR_CONTROL_SLOW` (`:11`) | autoridad de redirección aérea **con `vel_h <= 7.0`** | permitir corregir saltos lentos | bajarlo hace difícil ajustar saltos de precisión. |
| `0.8` | `AIR_FRICTION` (`:12`) | fricción horizontal en el aire **si `_jumped`** (sin input) | conservar el arco de salto | subirlo mata el momentum de salto sin input. |
| `3.0` | `FALL_FRICTION` (`:13`) | fricción horizontal en el aire **si NO `_jumped`** (caída pasiva) | frenar rápido al caerse de un borde | bajarlo hace que caerse conserve inercia lateral (relevante para re-enganches). |
| `7.0` | umbral `vel_h` en `_apply_movement` (`:105`) | escalón duro entre `AIR_CONTROL_FAST` y `SLOW` | ~entre `SPEED` (5) y `RUN_SPEED` (9) | mover el umbral cambia a qué velocidad "se traba" el control aéreo. |
| `0.8` | `target_height` agachado (`:71`) | altura del `CapsuleShape3D` agachado | pasar por huecos bajos | cambia por dónde cabe el jugador agachado. |
| `2.0` | `target_height` de pie (`:71`) | **altura real de la cápsula de pie de V1** | — | afecta `_hay_techo`, colisión con techos, y todo cálculo de clearance que use el collider real (el detector NO lo usa; usa su cápsula fija). |
| `0.4` | `target_camera_y` agachado (`:72`) | altura local de cámara agachado | — | sólo punto de vista. |
| `0.706` | `target_camera_y` de pie (`:72`) | altura local de cámara de pie | — | sólo punto de vista. **No coincide con el `0.8` del `.tscn`** → micro-lerp al spawn. |
| `0.1` | `max(_current_segment.move_speed, 0.1)` — *(esto es de traversal_controller, ver 7.4)* | — | — | — |

`INFERENCIA FUNDADA` (`_apply_gravity`): la gravedad usa `body.get_gravity()` (proyecto), **no** una
constante de este archivo. `project.godot` no define `physics/3d/default_gravity` → default Godot
(`9.8` m/s² hacia `-Y`). `DESCONOCIDO` si algún `Area3D` override la gravedad en la escena (no se
detectó ninguno relevante).

### 7.3 `parkour_detector.gd` — parámetros de detección (todos en default, sin override en escena)

| Valor | Export / const / línea | Efecto directo | Posible razón (cita si hay) | Riesgo al cambiarlo |
|---|---|---|---|---|
| `0.85` | `detection_distance` (`:19`) | largo del rayo horizontal de pared | alcanzar la pared desde ~1 cuerpo de distancia | > : engancha paredes lejanas; < : hay que estar pegado. También es la base de `dist_score` (`/ (0.85*2.5)`). |
| `0.15` | `edge_probe_up` (`:20`) | — | — | **EXPORT MUERTO** — declarado, nunca leído (§8). Cambiarlo no hace nada. |
| `0.5` | `min_edge_height` (`:22`) | `height_diff` mínimo (medido desde el **centro** de la cápsula) | descartar escalones triviales | subirlo ignora bordes bajos; bajarlo engancha cordones de vereda. |
| `1.5` | `max_edge_height` (`:23`) | `height_diff` máximo | commit `99d3766`: "se soluciono el tema de saltar de un un borde a otro, solo habia que poner el `max_edge_height` en 1.5" | **este valor existe para permitir saltos borde-a-borde** (`HECHO VERIFICADO` vía commit). Bajarlo rompe esa mecánica. Subirlo engancha muros altos que deberían requerir escalera. |
| `1.2` | `clearance_height` (`:24`) | altura de la cápsula de clearance | menor que el jugador de pie (2.0) — sólo pide "medio cuerpo" libre | subirlo rechaza más bordes por techo; bajarlo permite enganchar donde no cabe el cuerpo entero. |
| `0.25` | `clearance_radius` (`:25`) | radio de la cápsula de clearance | menor que el radio del jugador (≈0.5) | idem: es un test permisivo. |
| `0.35` | `min_score` (`:26`) | score mínimo para aceptar candidato en `_process_ledge` | filtro de calidad | subirlo exige encarar mejor la pared; bajarlo engancha de reojo. |
| `30.0` | `max_surface_tilt_deg` (`:27`) | tolerancia de inclinación: pared (`abs(normal.y) > sin30°`) y filo (`edge_normal·UP < cos30°`) | commit `e446aff`: "ahora funciona la deteccion de paredes con una inclinacion" | subirlo engancha rampas como si fueran paredes; bajarlo rechaza paredes levemente inclinadas. |
| `1.0` | `ladder_detection_radius` (`:29`) | radio de la esfera de detección de escalera **y** tolerancia lateral en `_is_within_segment_volume` | commit `0340960`: "el collisionshape de la escalera debe de medir lo mismo o parecido que la distancia entre los dos markers" (contexto: era `ladder_max_distance`, valor ~800, se "resumió" a esto) | subirlo detecta escaleras de lejos; bajarlo exige estar casi tocándola. |
| `0.8` | `detection_cooldown` (`:48`) | duración del cooldown que bloquea toda detección tras salir de un estado | evitar re-enganche instantáneo | subirlo alarga la ventana sin enganche tras soltarse; bajarlo permite re-enganche casi inmediato. |
| `0.3` | `PROBE_HEIGHTS[0]` (`:32`) | 1ª altura de probe de pared (sobre el centro de cápsula) | cubrir a la altura del pecho/abdomen | quitar/mover una altura cambia qué bordes se detectan según la Y del jugador en el aire. |
| `0.6` | `PROBE_HEIGHTS[1]` | 2ª altura de probe | — | idem. |
| `0.9` | `PROBE_HEIGHTS[2]` | 3ª altura de probe | — | idem. |
| `1.2` | `PROBE_HEIGHTS[3]` | 4ª altura de probe | — | idem. |
| `1.5` | `PROBE_HEIGHTS[4]` | 5ª altura de probe (la más alta) | tope alineado con `max_edge_height` | idem. |
| `4` | `range(4)` en `_find_segment` (`:172`) | niveles de padre a subir buscando grupo `"ladder"` | margen sobre `CollisionShape3D → StaticBody3D` | bajarlo puede no encontrar el segmento con jerarquías profundas. |
| `0.001` | epsilon de `seg_len` en `_is_within_segment_volume` (`:196`) | evita división por cero con markers coincidentes | — | prácticamente sin riesgo. |
| `0.0` / `1.0` | límites de `progress` en `_is_within_segment_volume` (`:203`) | **sin tolerancia** fuera del segmento | — | agregar tolerancia permitiría enganchar la escalera un poco antes/después de los markers. |
| `2.0` | radio de exclusión en `_process_ledge` (`:88`, `:91`) — **dos usos** (filo y jugador) | zona muerta alrededor de `last_hanging_pos` | evitar re-enganche del mismo borde tras soltarse por crouch | subirlo agranda la zona muerta; bajarlo permite re-enganche cercano. |
| `0.3` | `search_top = ... + max_edge_height + 0.3` en `_probe_at` (`:271`) | sobre-altura del origen del rayo de borde | asegurar que el rayo empiece por encima del filo más alto posible | prácticamente sin riesgo si es > 0. |
| `0.08` | offset `- wall_normal * 0.08` en `edge_search_origin` y `edge_search_end` (`:272-273`) | corre el rayo de borde levemente **hacia adentro** de la pared | pegarle al filo y no a la cara vertical | subirlo puede pasar de largo el filo; bajarlo puede pegarle a la cara vertical. |
| `0.35` | coherencia lateral XZ pared↔filo en `_probe_at` (`:286`) | descarta si el filo está lejos (XZ) del punto de pared | evitar tomar un filo de otra superficie | bajarlo rechaza esquinas redondeadas; subirlo toma filos que no corresponden. |
| `0.3` | umbral de `wall_dot` en `_score_candidate` (`:314`) | si encarás la pared con `dot < 0.3` → score 0 | exigir mirar hacia la pared | subirlo exige encarar más de frente. |
| `0.35` | peso de `wall_dot` en el score (`:316`) | contribución del encare del cuerpo | — | rebalancea el score; suma con los otros 3 pesos = 1.0. |
| `0.30` | peso del término de velocidad en el score (`:322`) | contribución de moverse hacia la pared | — | idem. |
| `0.20` | peso del término de cámara en el score (`:328`) | contribución de mirar hacia la pared | — | idem. |
| `0.15` | peso del término de distancia en el score (`:332`) | contribución de cercanía al filo | — | idem. |
| `0.5` | umbral `vel_h.length() > 0.5` en el score (`:319`) | por debajo, el término de velocidad no suma | ignorar ruido de velocidad | subirlo exige moverse claro hacia la pared para sumar ese término. |
| `2.5` | `detection_distance * 2.5` en `dist_score` (`:331`) | rango en el que la distancia deja de penalizar (= 2.125 m) | — | agranda/achica el rango "cercano" para el score. |
| `0.5` | `clearance_height * 0.5` en `_check_clearance` (`:352`) | mitad de la altura para centrar la cápsula | — | sin riesgo si es 0.5. |
| `0.1` | `+ 0.1` extra en el centro de la cápsula de clearance (`:352`) | levanta la cápsula 0.1 sobre el filo | evitar que la base de la cápsula toque el filo mismo | subirlo puede dejar pasar obstrucciones al ras del filo. |
| `-1.0` | `best_score` init en `_find_best_candidate` (`:231`) | sentinela para "ningún candidato aún" | — | sin riesgo. |
| `0.12` | `DebugDraw.point(edge_point, col, 0.12)` (`:243`) | tamaño de la cruz de debug del candidato | — | sólo visual. |
| `0.15` | `DebugDraw.sphere(edge_point, 0.15, col)` (`:244`) | radio de la esfera de debug por probe | — | sólo visual. |
| `0.28` | `DebugDraw.sphere(best["edge_point"], 0.28, CYAN)` (`:251`) | radio de la esfera cian del mejor candidato | — | sólo visual. |
| `0.15` | `DebugDraw.sphere(start/end_marker, 0.15, ...)` en `_process_ladder` (`:154-155`) | radio de esferas de debug de markers | — | sólo visual. |
| `Color(1.0 - score, score, 0.0)` | color por score en `_find_best_candidate` (`:242`) | rojo→verde según score | — | sólo visual. |

### 7.4 `traversal_controller.gd` — parámetros de traversal (todos en default)

| Valor | Export / const / línea | Efecto directo | Posible razón (cita) | Riesgo al cambiarlo |
|---|---|---|---|---|
| `14.0` | `snap_speed` (`:22`) | factor del lerp de posición en SNAPPING | commit `63082dd`: "mantiene el momentum al final, todo gracias al `lerp`" | > : snap más brusco/instantáneo; < : fase de acercamiento más larga y visible. **Con la doble ejecución (§8.1) el snap converge ~2× más rápido de lo que este número sugiere.** |
| `0.2` | `snap_threshold` (`:23`) | distancia a `_hang_position` para pasar a HANGING | — | > : "salta" a HANGING desde más lejos; < : puede quedar orbitando si nunca baja de 0.2. |
| `4.0` | `climb_speed` (`:24`) | factor del lerp de posición en CLIMBING | — | velocidad del mantle. Doble ejecución → ~2×. |
| `2.5` | `shimmy_speed` (`:25`) | `m/s` del paso lateral: `_along_wall * dir * 2.5 * delta` | — | **con doble ejecución, el shimmy real ≈ 5.0 m/s** (§8.1). Bajarlo compensaría; subirlo acelera aún más. |
| `0.5` | `shimmy_max_dist` (`:26`) | distancia lateral del probe `_edge_continues` (siempre; `dist` explícito nunca se pasa) | detectar el fin del borde ~medio paso adelante | > : se detiene más lejos del fin real del borde; < : se detiene demasiado pronto. |
| `6.5` | `jump_force` (`:27`) | `velocity` del pop al saltar durante SNAPPING (`UP * 6.5`) | — | **es mayor que `JUMP_VELOCITY` (4.5)** → cancelar un snap con salto propulsa más alto que un salto parado (§8). |
| `0.8` | `ladder_pulse_speed` (`:30`) | `progress_step = 0.8 * pulse_time / seg_len` | "cuánto avanza progress por segundo" (comentario `:30`) | velocidad de trepada. Doble ejecución → ~2×. |
| `0.18` | `ladder_pulse_time` (`:31`) | segundos entre pulsos de progreso (ritmo "a tirones") | "el ritmo" (comentario `:31`) | > : escalera más "a saltos"; < : más continua. Doble ejecución → pulso efectivo ~0.09 s. |
| `0.3` | `ladder_snap_strength` (`:32`) | — | "atracción al centro XZ al entrar" (comentario `:32`) | **EXPORT MUERTO** — nunca leído (§8). Cambiarlo no hace nada. |
| `-0.7` | `PROBE_OFFSETS_INNER[0]` (`:35`) | offset lateral del probe interno más a la izquierda (en `_calculate_tangent`, `_apply_virtual_normal`) | muestrear la superficie a ±0.7 del centro | quitar/mover offsets cambia la "suavidad" del seguimiento de curva. |
| `-0.4` | `PROBE_OFFSETS_INNER[1]` | idem | — | idem. |
| `-0.1` | `PROBE_OFFSETS_INNER[2]` | idem (cerca del centro, lado izquierdo) | — | idem. |
| `0.1` | `PROBE_OFFSETS_INNER[3]` | idem (cerca del centro, lado derecho) | — | idem. |
| `0.4` | `PROBE_OFFSETS_INNER[4]` | idem | — | idem. |
| `0.7` | `PROBE_OFFSETS_INNER[5]` | idem (más a la derecha) | — | idem. |
| `12` | `LOG_MAX` (`:68`) | tamaño del log circular de eventos | — | sólo debug (que además no se muestra, §8.2). |
| `-0.55` | `HANG_OFFSET_Y` (`:78`) | el hang cuelga 0.55 **bajo** el filo | altura de brazos extendidos | subirlo (menos negativo) sube al jugador respecto del filo; bajarlo lo cuelga más abajo. También define `edge_y_offset = abs(-0.55) - 0.15 = 0.40` en los probes de shimmy. |
| `-0.68` | `HANG_WALL_GAP` (`:79`) | separa el cuerpo 0.68 de la pared (doble negativo: `- normal * (-0.68) = + normal * 0.68`) | radio de cápsula (≈0.5) + margen | bajar la separación incrusta la cápsula en la pared; subirla deja al jugador "flotando" lejos del muro. |
| `1.0` | `SNAP_TIMEOUT` (`:80`) | segundos en SNAPPING antes de abortar | red de seguridad si el destino es inalcanzable | **con doble ejecución `_snap_timer` sube 2×/frame → aborto real a ~0.5 s** (§8.1). |
| `2.0` | release por timeout de SNAPPING: `_hang_normal * 2.0` (`:218`) | empujón horizontal alejándose de la pared | — | fuerza del "rebote" al fallar el snap. |
| `3.5` | release por move_back en HANGING: `_hang_normal * 3.5` (`:241`) | componente horizontal del salto hacia atrás | — | qué tan lejos saltás al soltarte hacia atrás. |
| `1.0` | release por move_back en HANGING: `Vector3.UP * 1.0` (`:241`) | hop vertical del salto hacia atrás | — | altura del hop al soltarte. |
| `2.2` | CLIMBING target: `Vector3.UP * 2.2` (`:299`) | **subida vertical fija** del mantle desde `_hang_position` | número inventado una vez | **no tiene relación con la geometría de arriba** (§8.5). Cambiarlo cambia dónde aterriza *todo* mantle. |
| `0.4` | CLIMBING target: `- _hang_normal * 0.4` (`:299`) | mete el destino 0.4 sobre la superficie (hacia adentro del borde) | caer "adentro" y no al filo | subirlo aterriza más adentro; bajarlo aterriza al borde (riesgo de recaer). |
| `0.12` | umbral de llegada en CLIMBING (`:302`) | distancia al target para snap + release | — | > : termina el mantle desde más lejos; < : puede orbitar. |
| `1.5` | release de CLIMBING: `- _hang_normal * 1.5` (`:304`) | empujón **hacia la superficie** al terminar el mantle | asentar al jugador sobre el filo | bajarlo puede dejarlo caer del borde recién trepado. |
| `4.0` | release por jump en LADDER: `cam_fwd * 4.0` (`:322`) | componente horizontal del salto fuera de la escalera | — | alcance del salto al bajarse. |
| `5.0` | release por jump en LADDER: `Vector3.UP * 5.0` (`:322`) | componente vertical del salto fuera de la escalera | — | altura del salto al bajarse (mayor que `JUMP_VELOCITY` 4.5). |
| `0.1` | `max(_current_segment.move_speed, 0.1)` en `_state_ladder` (`:348`) | piso del divisor de `pulse_time` | evitar división por ~0 con `move_speed` mal seteado | sin riesgo real. |
| `0.001` | `max(seg_len, 0.001)` en `_state_ladder` (`:358`) | piso del divisor de `progress_step` | evitar división por cero | sin riesgo real. |
| `4.0` | lerp de `_transitioning_face` en `_state_hanging` (`:283-284`) | velocidad de realineación XZ al doblar una esquina | — | > : reajuste más brusco al girar; < : arrastre más largo hacia la nueva cara. |
| `0.01` | umbral de fin de transición de cara (`:287`) | dist XZ para dar por terminada la transición | — | < : puede no terminar nunca; > : corta la transición antes. |
| `-99.0` | centinela `_shimmy_dir` "izquierda bloqueada" (`:264`) | evita re-loguear el bloqueo cada frame | valor imposible como dirección real | debe seguir siendo un valor que `dir` nunca tome (`dir ∈ {-1,0,1}`). |
| `99.0` | centinela `_shimmy_dir` "derecha bloqueada" (`:267`) | idem | idem | idem. |
| `0.15` | `_along_wall.lerp(target_tangent, 0.15)` en `_calculate_tangent` (`:458`) | suavizado de la tangente **por frame, SIN `delta`** | — | **dependiente de framerate** (§8): a más FPS converge más rápido en tiempo real. Cambiarlo cambia la "rigidez" del seguimiento de curva de forma no lineal con los FPS. |
| `0.001` | epsilons de `raw_tangent`/`_along_wall` en `_calculate_tangent` (`:454`, `:460`) | evitan normalizar vectores nulos | — | sin riesgo. |
| `0.15` | `abs(HANG_OFFSET_Y) - 0.15` = `edge_y_offset` (0.40) en `_apply_virtual_normal` (`:470`) y `_edge_continues` (`:508`) | pone el origen de los probes 0.15 bajo el filo | — | subirlo acerca los probes al filo (riesgo de fallar la pared); bajarlo los aleja hacia abajo. |
| `0.2` | `to_wall * -0.2` (rayo de pared `from`) en `_apply_virtual_normal` (`:476`) y `_edge_continues` (`:515`) | arranca el rayo 0.2 hacia el lado del jugador | — | subirlo arranca desde más lejos (puede fallar paredes cercanas). |
| `1.0` | `to_wall * 1.0` (rayo de pared `to`) en `_apply_virtual_normal` (`:477`) y `_edge_continues` (`:516`) | el rayo penetra 1.0 en la pared | — | bajarlo puede no alcanzar la pared; subirlo puede pegarle a geometría detrás. |
| `sin(deg_to_rad(30.0))` | filtro de inclinación de pared en `_apply_virtual_normal` (`:484`) y `_edge_continues` (`:526`) | mismo criterio que el detector (30°) | consistencia con `max_surface_tilt_deg` | cambiarlo desincroniza el shimmy del criterio de detección. |
| `0.4` | `wall_hit.position + Vector3.UP * 0.4` (rayo de filo `from`) en `_edge_continues` (`:531`) | arranca el rayo de filo 0.4 sobre el hit de pared | — | subirlo puede pasar de largo filos bajos; bajarlo puede no despegarse de la cara. |
| `0.05` | `- _hang_normal * 0.05` en `edge_from` de `_edge_continues` (`:531`) | corre el rayo de filo 0.05 hacia adentro | pegarle al filo, no a la cara | análogo al `0.08` del detector. |
| `0.7` | `edge_from + Vector3.DOWN * 0.7` (rayo de filo `to`) en `_edge_continues` (`:532`) | el rayo de filo baja 0.7 | — | subirlo detecta filos más profundos; bajarlo exige que el filo esté casi a la altura del origen. |
| `1000.0` | `Time.get_ticks_msec() / 1000.0` en `_log` (`:72`) | ms → s para el timestamp del log | — | sólo formato de log. |
| `0.2` / `0.8` / `0.5` / `0.1` / `0.06` / `0.2` / `0.15` | radios/largos de primitivas de `DebugDraw` en `_draw_debug` (`:584-612`) | tamaño de esferas/rayos de debug del estado | — | sólo visual. |

### 7.5 `traversal_segment.gd`

| Valor | Dónde | Efecto | Riesgo |
|---|---|---|---|
| `SegmentType.LADDER` (=0) | `segment_type` default (`:25`) | — | **EXPORT MUERTO** — nunca leído. `ROPE/CABLE/CHAIN` del enum tampoco tienen lógica. |
| `1.0` | `move_speed` default (`:29`) | multiplicador de ritmo de escalera (`pulse_time /= move_speed`) | 2.0 → escalera 2× más rápida; 0.5 → mitad. |
| `1.0` | fallback de `get_length()` sin markers (`:72`) | evita división por cero | sin riesgo. |
| `Vector3.UP` | fallback de `get_direction_at()` sin markers (`:66`) | — | **función muerta** (`get_direction_at` no se llama). |

### 7.6 `kick_controller.gd`

| Valor | Dónde | Efecto | Riesgo |
|---|---|---|---|
| `8.0` | `kick_force` default (`:16`) — **override a `40.0` en `movement_test`** | magnitud del impulso al `RigidBody3D` | 40.0 es el valor real jugado; 8.0 es lo que verías en `test_level`. |
| `0.2` | `kick_upward` default (`:19`) | fracción de `kick_force` que va en `+Y` | 0 = patada plana; subirlo hace "volar" los objetos. |
| `0.1` | `body.global_position + Vector3.UP * 0.1` (origen del debug ray, `:59`) | — | sólo visual. |
| `1.0` | `origen + facing * 1.0` (largo del debug ray, `:60`) | — | sólo visual. |

### 7.7 `debug_draw.gd`

| Valor | Dónde | Efecto | Riesgo |
|---|---|---|---|
| `true` | `enabled` init (`:16`) | dibujo activado al arrancar | `false` → nada de debug hasta togglear (no hay input mapeado a `toggle()`). |
| `false` | `frozen` init (`:17`) | no congelado | — |
| `0.06` | `size` default de `point()` (`:62`) | tamaño de cruz | sólo visual. |
| `0.2` | `radius` default de `sphere()` (`:67`) | radio de esfera | sólo visual. |
| `16` | `segments` en `_add_sphere_wire` (`:123`) | resolución del wireframe de esfera | sólo visual/perf. |

### 7.8 Valores en escenas (`.tscn`) y `project.godot`

| Valor | Dónde | Efecto | Evidencia |
|---|---|---|---|
| `40.0` | `KickController.kick_force` override | patada real del playground | `movement_test.tscn:754` |
| `3` | `raycast_interaccion.capa_interaccion` override (capas 1+2) | qué golpea la patada / interacción | `movement_test.tscn:751` |
| `true` | `Camera3D.current` override (cámara del jugador) | cámara activa al arrancar | `movement_test.tscn:747` |
| `false` | `raycast_interaccion.mostrar_raycast` override | oculta la línea de raycast de interacción | `movement_test.tscn:750` |
| `81.0` | `Camera3D.fov` (player.tscn) | campo de visión | `player.tscn:38` |
| `(0, 0.8, -0.285)` | transform local de `Camera3D` (player.tscn) | altura y adelanto de cámara; `y=0.8` ≠ target `0.706` de `_update_crouch` | `player.tscn:37` |
| `4` | `player.collision_layer` (capa 3) | en qué capa está el jugador | `player.tscn:24` |
| `9` | `player.collision_mask` (capas 1+4) | con qué colisiona el jugador y qué detectan sus shape-queries de traversal | `player.tscn:25` |
| `0.0` | `player.wall_min_slide_angle` | permite deslizar contra cualquier pared | `player.tscn:26` |
| `false` | `player.floor_block_on_wall` | no bloquea el piso al tocar pared | `player.tscn:27` |
| `(1.39, 8.77, 0.28)` | `carcasa` BoxShape3D de la escalera base | tamaño de la colisión de la escalera | `escalera_fea_v_1.tscn:7` |
| `(0, 0.9999223, 0.80568457)` | `StartMarker` local de la escalera base | inicio del recorrido de trepada; `z≈0.8` = separación del hang respecto de la cara | `escalera_fea_v_1.tscn:20` |
| `(0, 8.2, 0.806)` | `EndMarker` local de la escalera base | fin del recorrido (7.2 unidades) | `escalera_fea_v_1.tscn:23` |
| `(0, 2.816892, 0.80568457)` / `(0, 34.867695, 0.80599976)` | markers de `escalera 2` (override) | recorrido de ~32 unidades | `movement_test.tscn:477-481` |
| `(0, 9, 0.806)` | `EndMarker` de `escalera 5` (override) | recorrido de 8 unidades (colisión no re-escalada → marker levemente por encima) | `movement_test.tscn:495-496` |
| `0.2` | `deadzone` de **todas** las acciones de InputMap | umbral de zona muerta (relevante sólo para ejes analógicos; teclado es binario) | `project.godot:35,40,45,...` |
| `1600 × 900` | `window/size/viewport_width/height` | resolución base; `_construir_grilla` de inventario escala por `viewport.y / 648.0` (irrelevante acá) | `project.godot:28-29` |
| `"viewport"` | `window/stretch/mode` | modo de estirado | `project.godot:30` |

---

## 8. Guards, rarezas y código aparentemente extraño

### 8.1 ⚠ Doble ejecución de `traversal_controller._physics_process` cuando el traversal está activo

- **Condición exacta:** el método `traversal_controller.gd:127` se llama `_physics_process` (prefijo `_`)
  → Godot lo registra como callback automático de física al entrar al árbol. **No hay
  `set_physics_process(false)` en ningún lado del worktree** (`grep` `HECHO VERIFICADO`). Además,
  `traversal_controller.gd:95-96` define `func process(delta): _physics_process(delta)`, y
  `player.gd:63` llama `traversal.process(delta)` cuando `traversal.is_active()`.
- **Qué produce:**
  - `state == IDLE`: `_physics_process` corre **1×/tick** (sólo el callback auto). `player.gd` no lo llama.
  - `state != IDLE`: corre **2×/tick** — la pasada manual dentro de `player._physics_process` **y** la
    pasada auto de Godot. Orden: manual primero (player es ancestro), luego `kick.process`, luego auto.
- **Qué depende de esto (load-bearing):** el housekeeping de la rama IDLE (`_physics_process:130-140` —
  limpieza de `last_hanging_pos`, decremento de `_last_hang_clear_timer`, desarme de
  `is_crouch_blocked_after_drop`). **Sólo funciona porque el callback auto corre en IDLE.** Si alguien
  "arreglara" el doble-call agregando `set_physics_process(false)` y dejando sólo `process()`, la rama
  IDLE dejaría de correr (porque `player.gd` no llama `traversal.process()` en IDLE) → `last_hanging_pos`
  nunca se limpiaría, `is_crouch_blocked_after_drop` nunca se desarmaría → **el crouch quedaría trabado
  tras el primer drop y el borde quedaría permanentemente excluido**.
- **Qué se rompe / cambia si el bug persiste (que es el estado actual):** `INFERENCIA FUNDADA`
  (aritmética directa; magnitud = `PENDIENTE EMPÍRICO`):
  - `_snap_timer += delta` ×2 → `SNAP_TIMEOUT = 1.0` se alcanza en **~0.5 s reales**.
  - `_hang_position += _along_wall * dir * shimmy_speed * delta` ×2 → shimmy a **~5.0 m/s** reales (no 2.5).
  - `_ladder_pulse_timer += delta` ×2 → escalera pulsa a **~2×** el ritmo (`pulse_time` efectivo ~0.09 s).
  - `body.global_position.lerp(target, k*delta)` ×2 en SNAPPING y CLIMBING → convergencia más rápida.
  - `_log(...)` puede duplicar entradas por transición (el log igual no se muestra, §8.2).
  - `DebugDraw.clear()` corre 1×/tick igual (el resultado no cambia por correr 2×).
  - `_state_ladder` reconstruye `body.global_position` 2× (idempotente).
- **Explicación explícita:** no hay. El comentario de cabecera (`:3`) dice "REESCRITURA COMPLETA — sin
  parches acumulados"; el wrapper `process()` sugiere que el autor **cree** haber hecho el método manual.
- **Experimento para confirmar:** en editor, `print(Engine.get_physics_frames())` + contador dentro de
  `_physics_process`; o medir el tiempo real hasta el timeout de SNAPPING (colgarse mal de un borde y
  cronometrar el `push_warning`); o medir m/s de shimmy sobre la Zona B con `_hang_position` logueado.
- **Evidencia:** `HECHO VERIFICADO` (estructura + ausencia de `set_physics_process(false)` + semántica
  documentada de Godot: los scripts con `_physics_process` definido lo tienen auto-habilitado).

### 8.2 `debug_traversal.gd` — panel permanentemente inerte por ruta incorrecta

- **Condición:** `debug_traversal.gd:44` — `_traversal = player.get_node_or_null("TraversalController")`.
  En la escena real el nodo está en `player/movement/TraversalController` (`player.tscn:47`) → devuelve
  `null`.
- **Qué evita:** nada — es un bug, no una guarda.
- **Qué se rompe si se "arregla":** nada malo; recién ahí el panel contextual (estado frame a frame,
  input crudo L/R/ADEL/ATRAS/SALTO, log de eventos) se mostraría al togglear `toggle_debug_traversal`
  (F12).
- **Consecuencia actual:** `_process` (`:55-57`) corta con `if _traversal == null … : visible = false; return`
  **todos los frames**. El log de eventos de `traversal_controller` (`_event_log`, `_log`) se llena pero
  **nunca se ve**. `_build_text`, `_append_snapping/hanging/climbing`, `_shimmy_label` (que documenta los
  centinelas -99/99) son código muerto de facto.
- **Explicación explícita:** no. `INFERENCIA FUNDADA`: el `traversal_ui.tscn` fue diseñado como
  autoload/CanvasLayer suelto ("Lo buscamos por grupo, igual que hace tu debug_ui.gd", comentario `:32`)
  pero se instanció anidado bajo `player/movement/` y nunca se ajustó la ruta.
- **Experimento:** togglear F12 en editor y ver si aparece algo (no debería).
- **Evidencia:** `HECHO VERIFICADO` (ruta) + `INFERENCIA FUNDADA` (nunca visible).

### 8.3 `UiInventario.visible` es permanentemente `false`

- **Condición:** `ui_inventario.gd:18` (`visible = false` en `_ready`) + `:30` (`set_process_input(false)`).
  El comentario `:21-29` lo explica textual: *"su procesamiento de input queda HIBERNADO… `visible` sigue
  en false… solo deja de capturar `toggle_inventario` / mouse motion / …"*. **Nada más en el worktree
  setea `UiInventario.visible = true`** (`grep` `HECHO VERIFICADO`: los únicos usos son lecturas
  `if UiInventario.visible`).
- **Qué evita:** las ramas de `player.gd` que compuertan input/física con inventario abierto.
- **Consecuencia:** `player.gd:35-36` (`_input`: `if UiInventario.visible: return`) y `player.gd:56-60`
  (`_physics_process`: dampea `velocity.x/z` y `return`) son **ramas muertas** en `bd38e49^`.
- **Qué se rompe si se elimina:** en este commit, nada (nunca se ejecutan). Pero borrarlas rompería la
  compatibilidad si `UiInventario` volviera a activarse.
- **Evidencia:** `HECHO VERIFICADO`.

### 8.4 `debug_trail.gd` / `debug_trail.tscn` — sin instanciar

- **Condición:** `grep` no encuentra `debug_trail.tscn` ni su script en ninguna escena; `player.tscn` no
  lo incluye.
- **Consecuencia:** el script nunca corre. La acción de InputMap `toggle_trail` (tecla `K`,
  `project.godot:69-73`) **no hace nada**.
- **Evidencia:** `HECHO VERIFICADO`. `INFERENCIA FUNDADA`: herramienta de debug que se desconectó (o
  nunca se conectó) en `movement_test`.

### 8.5 Cero colisión real en todos los estados de traversal

- **Condición:** SNAPPING, HANGING, CLIMBING, LADDER escriben `body.global_position` directo (lerp o
  asignación) y ninguno llama `move_and_slide()` / `move_and_collide()` / `test_move()`. `player.gd:62-63`
  delega a `traversal.process()` sin `move_and_slide()` después. `HECHO VERIFICADO` (lectura completa,
  búsqueda de `move_and_` y `test_move` en el archivo: 0 resultados).
- **Qué evita:** que el motor empuje al jugador fuera de la geometría durante el traversal (lo cual
  sería deseable, pero el sistema lo omite).
- **Qué produce:** el jugador **puede atravesar geometría** mientras cualquier estado de traversal está
  activo. En CLIMBING el `target` es un offset fijo (`_hang_position + UP*2.2 - _hang_normal*0.4`) que no
  se valida contra nada — si cae dentro de un techo/pared, el jugador se incrusta hasta que vuelve a
  IDLE y `player.gd` retoma `move_and_slide()`.
- **Qué depende:** el shimmy fluido y el snap suave dependen de NO tener colisión (si `move_and_slide`
  corriera, la cápsula chocaría con la pared que está agarrando).
- **Experimento:** `PENDIENTE EMPÍRICO` — hacer un mantle contra un techo bajo y observar
  (`docs/parkour/v1_manual_validation.md`, Zona F2, reporta empíricamente: *el jugador se incrusta en el
  bloque y al volver a IDLE Godot lo expulsa hacia abajo; no es softlock*).
- **Evidencia:** `HECHO VERIFICADO` (ausencia de colisión) + `PENDIENTE EMPÍRICO` (resultado exacto).

### 8.6 El elevador de `movement_test` está inerte — mecánica `on_platform` inalcanzable

- **Condición:** `movement_test.tscn` node `plataforma_prueba` tiene `script`, `move_speed`,
  `accel/decel_distance`, `stations` seteados, pero **NO `detect_area`** (`grep` confirma: la única
  mención de `detect_area` es la declaración del export y su uso guardado con `if detect_area:`).
  Además **nadie llama `go_to_station()`** (`grep`).
- **Consecuencia:** `_ready` del elevador no conecta señales (Area3D nula); `_physics_process` retorna en
  `IDLE`; `set_on_platform` nunca se dispara. Toda la lógica `on_platform` de `movement_controller.gd`
  (`_apply_gravity:59-61` suspensión de gravedad; `_apply_movement:91` rama "piso" en el aire;
  `set_on_platform:47-51`) es **código inalcanzable en `bd38e49^` / `movement_test`**.
- **Contexto:** commit `d6cf156` "sistema **precario** de plataformas".
- **Evidencia:** `HECHO VERIFICADO`.

### 8.7 `_release` desde LADDER por crouch es la única salida SIN cooldown

- **Condición:** `_state_ladder:328` → `_release(Vector3.ZERO, false)`. Es la **única** de las 7 llamadas
  a `_release` en el archivo con `use_cooldown = false` explícito (`HECHO VERIFICADO`, ver tabla §4.4).
- **Qué evita:** normalmente `_release` llama `detector.start_cooldown()` (0.8 s) → bloquea re-detección.
  Acá no.
- **Qué produce:** tras soltarse de una escalera con `crouch`, **no hay bloqueo temporal ni espacial**
  para re-enganchar (la zona de exclusión de 2.0 unidades sólo aplica a ledges, no a escaleras — §8.8).
  En teoría se puede re-enganchar la misma escalera de inmediato.
- **Restricción que lo modera:** `_has_ladder_intent` exige `not is_on_floor()` y `not crouch` → hay que
  seguir en el aire y haber soltado el crouch en el frame exacto de re-detección.
- **Experimento:** `PENDIENTE EMPÍRICO` (`docs/parkour/v1_manual_validation.md` Zona G y
  `v1_playtest_checklist.md:62` reportan: *"Soltar con Ctrl y saltar de nuevo al toque → sí, vuelve a
  engancharse"*).
- **Evidencia:** `HECHO VERIFICADO` (el `false`) + `PENDIENTE EMPÍRICO` (sensación real).

### 8.8 Dos mecanismos de anti-re-enganche, distintos y solapados

- **Cooldown plano** (`detector._cooldown_timer`, `detection_cooldown = 0.8`): bloquea **ledge y ladder**;
  se arma en toda salida de estado con `use_cooldown=true` (todas menos LADDER+crouch); se descuenta por
  `delta` en `process()`.
- **Zona de exclusión espacial** (`last_hanging_pos`, radio `2.0`): bloquea **sólo ledges**; se arma
  **sólo** en HANGING→IDLE por crouch (`_state_hanging:246`); se limpia al tocar piso (instantáneo) o al
  agotarse `_last_hang_clear_timer` (que arranca en `0.8`) en el aire.
- **Rareza:** ambos nominalmente duran `0.8 s` pero se resetean por condiciones distintas. Aterrizar
  limpia la zona espacial al instante mientras el cooldown temporal sigue corriendo → hay una ventana
  donde el borde ya no está espacialmente excluido pero el cooldown plano todavía lo bloquea (o
  viceversa según el timing).
- **Explicación explícita:** no. `INFERENCIA FUNDADA`: dos parches acumulados para el mismo problema
  ("no re-enganchar el borde del que me acabo de soltar"), agregados en momentos distintos.
- **Experimento:** `PENDIENTE EMPÍRICO` (`v1_behavioral_reference.md` "punto pendiente #4").
- **Evidencia:** `HECHO VERIFICADO` (ambos mecanismos, sus condiciones) + `PENDIENTE EMPÍRICO`
  (interacción observable).

### 8.9 `_on_ladder_candidate_found` no tiene guarda de estado

- **Condición:** `_on_candidate_found:155-156` tiene `if state != State.IDLE: return`.
  `_on_ladder_candidate_found:175` **no tiene ninguna guarda** — cambia a LADDER pase lo que pase.
- **Qué evita:** nada (es una omisión).
- **Qué produce en teoría:** si el detector emitiera `ladder_candidate_found` mientras el estado es
  SNAPPING/HANGING/CLIMBING/LADDER, entraría (de nuevo) a LADDER pisando el estado actual y recalculando
  `_current_progress`.
- **Por qué no explota hoy:** `player.gd:62-67` **no llama `parkour_detector.process()` mientras
  `traversal.is_active()`** → el detector no emite nada durante traversal. La falta de guarda es una
  bomba latente, no un bug activo.
- **Escenario límite real (mismo frame desde IDLE):** en `process()`, `_process_ledge()` corre **antes**
  que `_process_ladder()` (`:71,73`). Si en un frame ambos encuentran candidato válido (jugador aéreo,
  cerca del **tope** de una escalera larga, encarando su cara, dentro del volumen del segmento):
  `candidate_found` emite → `_on_candidate_found` → `state = SNAPPING`; de vuelta en `process()`,
  `ladder_candidate_found` emite → `_on_ladder_candidate_found` (sin guarda) → `state = LADDER`.
  **Resultado neto: LADDER gana.** `INFERENCIA FUNDADA` (orden de líneas + señales síncronas de Godot);
  `PENDIENTE EMPÍRICO` reproducirlo. Relacionado con el commit `3bba9a7` ("todavia se puede meter en el
  hanging mientras se encuentra en el path de los dos marker … es una loteria que funcione
  correctamente") — al `bd38e49^` `_is_within_segment_volume` ya está reconectado (commit `5ca2d70`),
  pero el solapamiento ledge/ladder cerca del tope sigue siendo posible por código.
- **Evidencia:** `HECHO VERIFICADO` (ausencia de guarda; orden de `_process_ledge`/`_process_ladder`).

### 8.10 `jump_force` (6.5) en SNAPPING > `JUMP_VELOCITY` (4.5) del salto normal

- **Condición:** `_state_snapping:211` → `_release(Vector3.UP * jump_force)` con `jump_force = 6.5`.
- **Qué produce:** cancelar un snap saltando propulsa al jugador **más alto** que un salto parado.
  `INFERENCIA FUNDADA`: side-effect no intencional (o intencional para "escapar" del snap con fuerza).
- **Evidencia:** `HECHO VERIFICADO`.

### 8.11 CLIMBING nunca falla — offset fijo, sin validación

- **Condición:** `_state_climbing:299` `target = _hang_position + Vector3.UP*2.2 - _hang_normal*0.4`.
  La función no contiene ninguna query de física. Siempre converge (`lerp`) y siempre hace `_release`.
- **Qué evita:** nada — no hay concepto de "mantle bloqueado" ni "aterrizaje inválido".
- **Qué produce:** si `target` cae dentro de geometría sólida, el jugador se incrusta (§8.5). Si arriba
  no hay piso, el jugador termina el mantle "flotando" en el aire y cae al retomar `move_and_slide()`.
- **Explicación explícita:** no.
- **Experimento:** `PENDIENTE EMPÍRICO` (ver §8.5; `v1_manual_validation.md` Zona F2 lo reporta).
- **Evidencia:** `HECHO VERIFICADO`.

### 8.12 `_calculate_tangent` suaviza con `lerp(·, ·, 0.15)` SIN `delta`

- **Condición:** `_calculate_tangent:458` — `_along_wall = _along_wall.lerp(target_tangent, 0.15)`.
  Es el único suavizado del sistema que **no** multiplica por `delta` (los de `_state_hanging:283-284`
  usan `4.0 * delta`; los de SNAPPING/CLIMBING usan `speed * delta`).
- **Qué produce:** la orientación tangencial converge una fracción **fija por frame**, no por segundo →
  **dependiente de framerate**: a 120 FPS `_along_wall` se alinea el doble de rápido (en tiempo real) que
  a 60 FPS. `INFERENCIA FUNDADA`. Sumado a la doble ejecución (§8.1), a framerate normal corre 2×/frame
  → converge aún más rápido.
- **Explicación explícita:** no.
- **Experimento:** `PENDIENTE EMPÍRICO` — shimmyear el `circulo circuloso` limitando FPS (30/60/144) y
  comparar cuán "pegado" sigue la curvatura.
- **Evidencia:** `HECHO VERIFICADO` (ausencia de `delta`).

### 8.13 Doble suavizado con distinta base temporal en la transición de cara

- **Condición:** al doblar una esquina (`_transitioning_face = true`), la **posición** se realinea con
  `lerp(·, ·, 4.0 * delta)` (por segundo, `_state_hanging:283-284`) pero la **tangente** (`_along_wall`)
  se realinea con `lerp(·, ·, 0.15)` (por frame, `_calculate_tangent`).
- **Qué produce:** a distinto framerate, orientación y posición convergen a ritmos relativos distintos.
- **Evidencia:** `HECHO VERIFICADO`.

### 8.14 `_has_ladder_intent(_segment)` ignora su parámetro

- **Condición:** `parkour_detector.gd:180` — firma `func _has_ladder_intent(_segment: Node) -> bool`;
  el cuerpo nunca usa `_segment` (prefijo `_`).
- **Qué produce:** la "intención" es idéntica para toda escalera; la firma sugiere variación por
  segmento que no existe.
- **Evidencia:** `HECHO VERIFICADO`.

### 8.15 Código / exports / funciones muertas (inventario completo)

`HECHO VERIFICADO` (declarado + `grep` sin consumidor):

| Elemento | Ubicación | Estado |
|---|---|---|
| `edge_probe_up` (export, 0.15) | `parkour_detector.gd:20` | declarado, **nunca leído**. |
| `ladder_snap_strength` (export, 0.3) | `traversal_controller.gd:32` | declarado + comentado, **nunca leído**. |
| `segment_type` (export) + `SegmentType.ROPE/CABLE/CHAIN` | `traversal_segment.gd:24-25` | declarados, **sin lógica** (sólo LADDER tiene `_state_*`). |
| `jumped` (propiedad getter) | `movement_controller.gd:24-25` | **sin lectura externa**. |
| `get_direction_at(_progress)` | `traversal_segment.gd:64-67` | **nunca se llama**; ignora su parámetro. |
| `get_current_candidate()` / `has_candidate()` | `parkour_detector.gd:99-103` | **sin consumidores**. |
| `get_current_ladder_candidate()` | `parkour_detector.gd:214-215` | **sin consumidores**. |
| `DebugDraw.toggle()` | `debug_draw.gd:72-73` | **sin consumidores** (no hay input mapeado). |
| señal `candidate_lost` | `parkour_detector.gd:14` | emitida, **nunca conectada**. |
| señal `ladder_candidate_lost` | `parkour_detector.gd:16` | emitida, **nunca conectada**. |
| señal `traversal_started` | `traversal_controller.gd:14` | emitida, **nunca conectada** (§9.1). |
| señal `traversal_ended` | `traversal_controller.gd:15` | emitida, **nunca conectada** (§9.1). |
| rama `if UiInventario.visible` en `player.gd` (`_input`, `_physics_process`) | `player.gd:35,56` | **inalcanzable** (§8.3). |
| `debug_trail.gd` + `debug_trail.tscn` | — | **sin instanciar** (§8.4). |
| `debug_traversal.gd` (todo el panel) | — | **inerte** por ruta (§8.2). |
| grupo `"raycast"` (en `MovementTest` y en `raycast_interaccion`) | `movement_test.tscn:302`, `raycast_interaccion.tscn:5` | **sin consumidor de código** (§9.3). |
| mecánica `on_platform` de `movement_controller` | `:17,47-51,59-61,91` | **inalcanzable** en `movement_test` (§8.6). |
| `caja_doblada.tscn` | `scenes/props/static/` | **sin instanciar** en `movement_test`. |

### 8.16 Guardas explícitas y su función

| Guarda | Ubicación | Qué evita | Qué se rompe si se elimina |
|---|---|---|---|
| `if state != State.IDLE: return` | `_on_candidate_found:155` | que un candidato nuevo interrumpa SNAPPING/HANGING/etc. | el detector podría re-disparar SNAPPING cada frame mientras el candidato siga válido → jitter / re-snap. (Mitigado en parte porque el detector no corre en traversal, pero SÍ podría dispararse en el mismo frame de entrada.) |
| `if traversal.is_active() or traversal.is_crouch_blocked_after_drop: return` | `player._input:47` | togglear el crouch de locomoción durante traversal o justo después de un drop por crouch | el jugador se agacharía/pararía a media escalada; tras un drop por crouch, el mismo hold de Ctrl togglearía el crouch al caer al piso. |
| `if movement.is_crouching and _hay_techo(): pass` | `player._input:49` | pararse dentro de un techo bajo | la cápsula crecería a 2.0 dentro de geometría → el motor lo expulsa de forma abrupta. |
| `is_crouch_blocked_after_drop` (flag) | seteada en `_state_hanging:248`, leída en `player._input:47`, desarmada en `_physics_process:131-132` | que el mismo evento de Ctrl que te soltó del hang te agache al aterrizar | doble acción de un solo input. |
| `if _cooldown_timer > 0.0: … return` | `parkour_detector.process:62` | detectar candidatos durante el cooldown | re-enganche instantáneo tras soltarse. |
| `if body.is_on_floor(): _clear_candidate()` | `parkour_detector.process:68` | detección de borde en el piso | el jugador engancharía bordes caminando (V1 sólo engancha en el aire). |
| `if best.is_empty() or best["score"] < min_score` | `_process_ledge:82` | aceptar candidatos de baja calidad | enganches "de reojo" a paredes que apenas mirás. |
| zona de exclusión `< 2.0` de `last_hanging_pos` | `_process_ledge:88,91` | re-enganchar el borde del que te soltaste con crouch | oscilación colgarse/soltarse en el mismo borde. |
| `if not _is_within_segment_volume(segment): continue` | `_process_ladder:140` | enganchar la escalera desde fuera de su volumen | commit `5ca2d70`: "meterse en el ladder desde cualquier lado". Reconectada explícitamente. |
| `if _has_ladder_intent(segment)` (no piso, no crouch) | `_process_ladder:144` | activar la escalera parado en el piso | pararte frente a una escalera te subiría sin querer. |
| `if _snap_timer > SNAP_TIMEOUT` | `_state_snapping:215` | quedarse atascado en SNAPPING si el destino es inalcanzable | softlock si el `_hang_position` calculado nunca se alcanza. |
| `if count == 0: return` | `_apply_virtual_normal:492` | fijar una normal/posición promedio de cero probes válidos | escribir `NaN`/vector cero en `_hang_normal` → el jugador "desaparece" de la pared. |
| `if _shimmy_dir == 0.0: return` | `_calculate_tangent:427` | recalcular la tangente cuando no te estás moviendo | jitter de orientación en HANGING quieto. |
| `if seg_len < 0.001: return false` | `_is_within_segment_volume:196` | división por cero con markers coincidentes | crash / `NaN`. |
| `if _kicked_this_frame: return` | `kick_controller._execute_kick:44` | doble patada en el mismo frame | doble impulso. |
| `if frozen: return` / `if not enabled or frozen: return` | `debug_draw.gd:51,58,63,68` | dibujar cuando el debug está congelado/apagado | — (sólo debug). |

### 8.17 Otras rarezas menores (todas `HECHO VERIFICADO`)

- **`parkour_detector` nunca llama `DebugDraw.clear()`** — viola el contrato del header de `debug_draw.gd`
  (`:10-12`: "Cada sistema que dibuja es responsable de llamar `clear()` al inicio de su
  `physics_process`"). El clear lo hace `traversal_controller._physics_process` (§3.4 CD-5). Consecuencia:
  las primitivas del detector se acumulan hasta que el clear de traversal las borra — y como ese clear
  corre **después** del detector en el mismo tick, en IDLE el debug del detector se borra antes de
  renderizar. `INFERENCIA FUNDADA`: por eso las líneas de probe son difíciles/imposibles de ver en
  free-roam.
- **`_raycast` del detector (`:340-343`) y `_hay_techo` (`player.gd:85`) no setean `collision_mask`** →
  usan todas las capas. En cambio los shape-queries (`_check_clearance`, `_process_ladder`) sí usan
  `body.collision_mask`. Inconsistencia: los raycasts pueden pegarle a capas que el jugador ignora.
- **`movement._update_crouch` corre cada tick IDLE** aunque `is_crouching` no cambie — lerpea el
  `shape.height` y `camera.position.y` hacia el target y se queda ahí. Muta el sub-resource
  `CapsuleShape3D` (compartido si hubiera múltiples jugadores; hay uno solo).
- **Cámara: `player.tscn:37` pone `Camera3D.position.y = 0.8`, pero `_update_crouch` target de pie es
  `0.706`** → al primer tick la cámara baja ~0.094 unidades por lerp. Micro-caída al spawn.
- **`movement._handle_jump` usa `Input.is_action_pressed("jump")` (sostenido), no `just_pressed`** — pero
  los estados de traversal usan `is_action_just_pressed("jump")` (flanco). Inconsistencia deliberada:
  saltar a pie tolera mantener la tecla; saltar en traversal exige re-presionar.
- **`_process_ladder` procesa sólo el primer segmento válido y hace `return`** (`:166`) — si hay dos
  escaleras solapadas en el radio de 1.0, sólo se considera una (la primera del `intersect_shape`).
- **`_score_candidate` retorna `0.0` en `wall_dot < 0.3` antes de evaluar los otros 3 términos**
  (`:314-315`) — un candidato mal encarado nunca puede compensar con velocidad/cámara/distancia.
- **`escalera 5` (movement_test): `EndMarker` a y=9 local, pero la colisión `carcasa` no se re-escaló**
  (tope a y≈8.77) → el marker final queda ~0.23 por encima de la colisión. `INFERENCIA FUNDADA`:
  imprecisión de autoría; el jugador podría "trepar" el último tramo fuera de la colisión.
- **`free_camera` activa: el mouse sigue rotando el cuerpo del jugador** (`player._input` no chequea la
  free cam) — mover el mouse en modo free-cam desorienta el yaw del jugador real.
- **`test_level.tscn` no setea `Camera3D.current`** ni los overrides de kick/raycast → comportamiento de
  cámara al arranque `DESCONOCIDO` (dos cámaras, ninguna `current` explícita).
- **`_change_state` llama `movement.freeze()` sólo en inactivo→activo**, y `freeze()` sólo pone
  `velocity.x/z = 0` — pero el primer tick del estado hace `body.velocity = Vector3.ZERO` completo igual.
  `freeze()` sólo cubre el gap de un frame.
- **`traversal._physics_process` en IDLE hace `DebugDraw.clear()` y después el housekeeping** — si el
  jugador nunca entró a traversal, igual se llama `clear()` cada tick (borra lo del detector).

---

## 9. Señales, grupos e integración externa

### 9.1 Señales emitidas por el sistema

| Señal | Declarada en | Emitida en | Conexiones encontradas | Consumidores |
|---|---|---|---|---|
| `traversal_started()` | `traversal_controller.gd:14` | `_change_state:572` (inactivo→activo) | **NINGUNA** (`grep` en todo el worktree) | ninguno. |
| `traversal_ended()` | `traversal_controller.gd:15` | `_change_state:574` (activo→inactivo) | **NINGUNA** | ninguno. |
| `candidate_found(Dictionary)` | `parkour_detector.gd:13` | `_process_ledge:97` | `traversal_controller.gd:89` (`_on_candidate_found`) | `traversal` (SNAPPING). |
| `candidate_lost()` | `parkour_detector.gd:14` | `_clear_candidate:363` | **NINGUNA** | ninguno. |
| `ladder_candidate_found(Dictionary)` | `parkour_detector.gd:15` | `_process_ladder:165` | `traversal_controller.gd:90` (`_on_ladder_candidate_found`) | `traversal` (LADDER). |
| `ladder_candidate_lost()` | `parkour_detector.gd:16` | `_clear_ladder_candidate:221` | **NINGUNA** | ninguno. |
| `salud.vida_cambiada(nueva, max)` | `salud.gd:6` | `recibir_daño`/`curar` | **NINGUNA** (`grep`) | ninguno. |
| `salud.murio` | `salud.gd:7` | `recibir_daño:17` (si vida ≤ 0) | `player.gd:28` (`_on_murio`) | `player` (`reload_current_scene`). **Nunca se dispara** (`recibir_daño` no se llama). |
| `arrived_at_station(index)` | `elevator_platform.gd:163` (inline) | `_arrive:252` | **NINGUNA** | ninguno (elevador inerte). |

`HECHO VERIFICADO`. **Todas las conexiones del sistema de traversal se hacen por código en
`traversal_controller.setup()` (`:89-90`), no hay `[connection]` en ningún `.tscn`.**

`DESCONOCIDO`: si `traversal_started`/`traversal_ended`/`candidate_lost`/`ladder_candidate_lost` tenían
consumidores en ramas del proyecto no presentes en este worktree aislado (audio, cámara cinemática, UI
de otro branch). En `bd38e49^` no hay ninguno.

### 9.2 Señales consumidas por el sistema

- `traversal_controller` consume `detector.candidate_found` y `detector.ladder_candidate_found` (conectadas
  en `setup`). **No consume** `candidate_lost` ni `ladder_candidate_lost` → cuando el detector "pierde"
  un candidato, el `traversal` no se entera (y no le importa, porque el detector no corre durante
  traversal de todos modos).
- `player` consume `salud.murio`.
- `HECHO VERIFICADO`.

### 9.3 Grupos

| Grupo | Nodos en el grupo | Consumidores de código |
|---|---|---|
| `"player"` | el `CharacterBody3D` `player` (`player.tscn:22`) | `debug_ui.gd:4`, `debug_traversal.gd:33`, `debug_trail.gd:23`, `free_camera.gd:32`, `raycast_interaccion.gd:9`, `hud.gd` (indirecto vía export), `tirar_item.gd:43`, `ui_inventario.gd:178` — todos con `get_tree().get_first_node_in_group("player")`. **Crítico.** |
| `"ladder"` | el `StaticBody3D` raíz de `escalera_fea_v_1.tscn` (`:9`) | `parkour_detector.gd:175` (`_find_segment`: `current.is_in_group("ladder")`). **Crítico para escaleras.** |
| `"raycast"` | `MovementTest` (raíz de `movement_test.tscn:302`) **y** `raycast_interaccion` (`raycast_interaccion.tscn:5`) | **NINGUNO** (`grep '"raycast"'` en `.gd` = 0 resultados). Grupo vestigial. `INFERENCIA FUNDADA`: resto de una arquitectura de interacción anterior. |

`HECHO VERIFICADO`.

### 9.4 Búsquedas de ancestros / nodos

| Búsqueda | Dónde | Qué busca |
|---|---|---|
| `for _i in range(4): current.is_in_group("ladder"); current = current.get_parent()` | `parkour_detector._find_segment` | el `StaticBody3D` de la escalera desde el collider golpeado. |
| `while actual != null: for hijo in actual.get_children(): if hijo is InteractionComponent` | `raycast_interaccion._buscar_interaction_component` | el `InteractionComponent` del objeto mirado (para interacción/patada indirecta). |
| `get_tree().current_scene` → `add_child` | `debug_draw._attach_to_scene` | dónde colgar el `MeshInstance3D` de debug. Se re-ejecuta si el mesh sale del árbol. |
| `player.get_node_or_null("TraversalController")` | `debug_traversal._ready` | **falla** (ruta incorrecta, §8.2). |
| `player.get_node("movement/MovementController")` / `get_node_or_null("movement/TraversalController")` | `debug_ui._process` | correcto. |
| `body.get_node_or_null("movement/MovementController")` | `elevator_platform._on_body_entered` | el `MovementController` del pasajero (elevador inerte). |

`HECHO VERIFICADO`.

### 9.5 Autoloads y su relación con locomoción

| Autoload | Relación |
|---|---|
| `DebugDraw` | consumido por `parkour_detector`, `traversal_controller`, `kick_controller` (dibujo). `traversal._physics_process` lo `clear()`ea cada tick. `_process` escucha `toggle_debug_freeze` (G). Si falta → crash. |
| `UiInventario` | `player.gd` lee `.visible` (siempre `false`, §8.3). Si falta → crash en `_input`/`_physics_process`. |
| `UIHacking` | `terminal.gd:23` → `UIHacking.abrir(self)` → `get_tree().paused = true` → **congela toda la física del jugador**. `cerrar()` → `paused = false`. El nodo escena `ui_hacking.tscn` tiene `process_mode = 3` (ALWAYS) para seguir aceptando input con el árbol pausado. `HECHO VERIFICADO`. |
| `Catalogo` / `Inventario` | inventario legacy; sin relación con locomoción. |

### 9.6 UI / audio / cámara / debug que reacciona al traversal

| Sistema | Reacciona a | Verificado |
|---|---|---|
| `debug_ui.gd` | lee `traversal.get_state_name()` cada `_process` y lo muestra en el label de texto | `HECHO VERIFICADO` (activo). |
| `debug_traversal.gd` | **debería** mostrar estado + input + log, pero está **inerte** (§8.2) | `HECHO VERIFICADO`. |
| `DebugDraw` (vía `traversal._draw_debug`) | dibuja hang pos / normal / along_wall / probes / segmento por estado | `HECHO VERIFICADO`. |
| Audio | **NADA** — no hay ningún nodo de audio en `player.tscn` ni consumidor de las señales de traversal | `HECHO VERIFICADO` (en este worktree). |
| Cámara | **NADA toca la cámara según el estado de traversal** — ni `look_at`, ni FOV, ni shake, ni cambio de `position` (salvo el lerp de crouch que **no corre** en traversal). El mouse-look es idéntico en todos los estados. | `HECHO VERIFICADO` (búsqueda de `look_at`/`Basis.looking_at`/`rotation`/`fov` en `traversal_controller.gd`: 0). |
| Salud / daño | **NADA** — `salud.recibir_daño` no se llama nunca; no hay daño de caída ni de nada | `HECHO VERIFICADO`. |

### 9.7 Sin tests

`HECHO VERIFICADO`: no existe ningún test automatizado de `player.gd`, `movement_controller.gd`,
`parkour_detector.gd`, `traversal_controller.gd`, `traversal_segment.gd` ni `kick_controller.gd` en
`bd38e49^`. `grep` sobre `scenes/test/` sólo encuentra los dos `.tscn` **untracked** de P0 (excluidos,
§1.4). El sistema de parkour V1 tiene **cero cobertura de test**.

---

## 10. Contrato observable por mecánica

> Descripción de **qué hace V1**, con enlace a las funciones y valores que lo producen. No es diseño de
> V2. Etiqueta por afirmación.

### 10.1 Locomoción a pie

- **Produce:** `movement_controller.process()` → `_apply_movement` (rama piso `:91-101`).
- Velocidad base `SPEED = 5.0`, corriendo `RUN_SPEED = 9.0` (con `run` sostenido), agachado en piso
  `CROUCH_SPEED = 2.5`. La velocidad objetivo se suaviza con `lerp(·, ·, ACCELERATION*delta)`
  (`ACCELERATION = 14.0`), y la velocidad horizontal se **clampea** a `current_speed` si lo supera.
  `HECHO VERIFICADO`.
- Dirección: `_get_input_direction()` en espacio del **cuerpo** (`transform.basis`), horizontal,
  normalizada.
- Gravedad: `body.get_gravity()` (proyecto) integrada en `_apply_gravity` cuando `not is_on_floor()`.
- Integración: `player._physics_process` → `move_and_slide()` (rama IDLE únicamente).
- `PENDIENTE EMPÍRICO`: sensación exacta de aceleración/frenado; alcance real de salto a cada velocidad.

### 10.2 Salto

- **Produce:** `movement_controller._handle_jump` (`:65-68`).
- `Input.is_action_pressed("jump")` (sostenido) `and body.is_on_floor() and not is_crouching` →
  `velocity.y = JUMP_VELOCITY (4.5)`, `_jumped = true`.
- Sin doble-salto (el piso es la guarda), sin coyote-time, sin buffer. `_jumped` se resetea al tocar
  piso (`_update_jump_state`) y gobierna la fricción aérea. `HECHO VERIFICADO`.
- **Saltos "especiales" desde traversal** (todos vía `_release`, §4.4): SNAPPING+jump `UP*6.5`;
  HANGING+jump → CLIMBING (no es salto); HANGING+move_back `hang_normal*3.5 + UP*1.0`;
  LADDER+jump `cam_fwd*4.0 + UP*5.0`.
- `PENDIENTE EMPÍRICO`: altura/arco reales; si el `UP*6.5` del cancel de SNAPPING se siente como "salto
  con boost".

### 10.3 Crouch

- **Produce:** `player._input` (`:46-52`) + `movement_controller._update_crouch` (`:70-78`) +
  `_update_speed` (`:80-88`).
- Toggle (no sostenido): `set_crouching(!is_crouching)`, salvo `traversal.is_active()` /
  `is_crouch_blocked_after_drop` (return) o (agachado + `_hay_techo()` → `pass`, no se para).
- Collider: `shape.height` lerp a `0.8` (agachado) / `2.0` (de pie) con `CROUCH_TRANSITION = 8.0`.
  Cámara local Y lerp a `0.4` / `0.706`.
- Velocidad reducida a `CROUCH_SPEED` **sólo en piso**.
- **No corre durante traversal** → collider congelado (§3.6, §5.4).
- `Ctrl` en traversal: HANGING → drop pasivo + zona de exclusión; LADDER → drop sin cooldown; SNAPPING/
  CLIMBING → ignorado.
- `HECHO VERIFICADO`. `PENDIENTE EMPÍRICO`: si el crouch mid-air hace algo raro (el código lo permite
  fuera de traversal — `_handle_jump` sólo bloquea saltar, no agacharse).

### 10.4 Control aéreo

- **Produce:** `_apply_movement` rama aire (`:102-111`).
- Con input: `air_control = 0.3` si `vel_h > 7.0`, si no `1.5` (**escalón duro**, sin interpolar).
- Sin input: fricción `0.8` si `_jumped`, `3.0` si caída pasiva.
- Sin clamp de velocidad máxima en el aire (a diferencia del piso).
- `HECHO VERIFICADO`. `PENDIENTE EMPÍRICO`: cuánto se puede corregir un salto de precisión vs uno corrido.

### 10.5 Detección de borde

- **Produce:** `parkour_detector.process` → `_process_ledge` → `_find_best_candidate` → `_probe_at` (×5
  alturas) → `_score_candidate`.
- Sólo corre **en el aire** (`not is_on_floor()`), sin cooldown activo, y sólo mientras
  `not traversal.is_active()`.
- Rayo de pared `facing` (cuerpo) `× 0.85`; rayo de borde hacia abajo desde `body.y + 1.8`; filtros de
  inclinación (30°), coherencia lateral (0.35), altura `[0.5, 1.5]` (desde el **centro** de la cápsula),
  clearance (cápsula 0.25×1.2). Score con pesos `0.35/0.30/0.20/0.15`, umbral `min_score = 0.35`.
- Emite `candidate_found` → `traversal._on_candidate_found` (si IDLE) → SNAPPING.
- Debug: rayos gris/blanco (pared), gris/aqua (borde), esferas rojo→verde por score, cian el mejor —
  **pero probablemente invisibles en free-roam** por §3.4 CD-5.
- `HECHO VERIFICADO` la mecánica; `PENDIENTE EMPÍRICO` la ventana real de enganche al saltar.

### 10.6 Snapping

- **Produce:** `_state_snapping` (`:207-225`).
- `body.velocity = ZERO` cada tick; `body.global_position = lerp(pos, _hang_position, snap_speed*delta)`
  (`snap_speed = 14.0`); llega a HANGING con `dist < snap_threshold (0.2)`.
- Aborta: jump (flanco) → `_release(UP*6.5)`; `_snap_timer > 1.0` → `_release(hang_normal*2.0)` +
  `push_warning`.
- **Doble ejecución (§8.1): converge ~2× más rápido y el timeout real es ~0.5 s.**
- `INFERENCIA FUNDADA`: convergencia exponencial (lerp), no lineal. `PENDIENTE EMPÍRICO`: si la fase de
  acercamiento se percibe o el agarre se siente instantáneo (`v1_playtest_checklist.md:65` reporta:
  *"instantáneo desde que el probe da válido"*).

### 10.7 Hanging

- **Produce:** `_state_hanging` (`:231-290`).
- `body.velocity = ZERO`; `body.global_position = _hang_position` (directo, sin colisión).
- `_hang_position` = filo `+ HANG_OFFSET_Y (-0.55)` en Y, `+ _hang_normal * 0.68` fuera de la pared.
- Escucha (flanco): jump→CLIMBING, move_back→release, crouch→release+exclusión. Escucha (sostenido):
  move_left/right→shimmy. Ignora move_forward, run.
- `HECHO VERIFICADO`.

### 10.8 Shimmy

- **Produce:** `_state_hanging` (`:252-288`) + `_update_shimmy_probes` + `_edge_continues` + `_calculate_tangent`.
- Paso lateral: `_hang_position += _along_wall * dir * shimmy_speed (2.5) * delta` sólo si el probe
  lateral de ese lado (`_edge_continues`, `0.5` adelante) encontró pared+filo.
- Sin aceleración/frenado propio — velocidad constante. **Con doble ejecución, ~5.0 m/s reales (§8.1).**
- Fin de borde: el probe deja de encontrar pared/filo → el jugador se detiene ~0.5 unidades antes del
  fin geométrico real; log único "shimmy bloqueado" (`_shimmy_dir` centinela ±99). No se suelta.
- `HECHO VERIFICADO`. `PENDIENTE EMPÍRICO`: fluidez real; velocidad medida.

### 10.9 Esquinas (cambio de cara sin marcadores)

- **Produce:** `_update_shimmy_probes` (`:397-423`) + `_calculate_tangent` + `_apply_virtual_normal`.
- Si el probe lateral del lado hacia el que shimmyeás devuelve un `wall_normal` **distinto** →
  `_hang_normal` se adopta solo, `_along_wall` se recalcula, `_hang_position_target` apunta a la nueva
  cara, `_transitioning_face = true`.
- Con `_transitioning_face`: posición realinea con `lerp(·, ·, 4.0*delta)` hasta dist XZ `< 0.01`.
- Si soltás el shimmy a mitad de transición (`dir == 0`): corte inmediato + `_apply_virtual_normal`
  (promedio de ≤6 raycasts → normal/posición de compromiso; si 0 hits, no cambia nada).
- `_calculate_tangent` (lerp `0.15` **sin delta**, framerate-dependiente) suaviza `_along_wall` hacia la
  tangente medida por 6 probes internos → permite seguir curvas (el `circulo circuloso`).
- Commits `8ae5b1a` ("agarrarse en curvas y hacer tp a la siguiente normal"), `3840e4a` ("ya no hay
  rebotes al desplazarse por el anillo").
- `HECHO VERIFICADO` la mecánica; `PENDIENTE EMPÍRICO`: si dobla esquinas de 90° reales (el
  `v1_playtest_checklist.md:20-27` reporta que **no** doblaba una esquina en L de dos cajas rectas —
  atribuido a geometría de prueba, no al mecanismo).

### 10.10 Mantle (CLIMBING)

- **Produce:** `_state_climbing` (`:296-304`).
- `body.velocity = ZERO`; `body.global_position = lerp(pos, target, climb_speed (4.0) * delta)`;
  `target = _hang_position + UP*2.2 - _hang_normal*0.4` — **offset fijo, sin query de física, sin
  validar el aterrizaje**.
- Llega con `dist < 0.12` → snap exacto + `_release(-_hang_normal*1.5)` (empujón hacia la superficie).
- No se puede cancelar (no escucha input).
- Si `target` cae en geometría sólida → el jugador se incrusta hasta volver a IDLE (§8.5, §8.11).
- `HECHO VERIFICADO`. `PENDIENTE EMPÍRICO`: aterrizaje exacto; caso "target dentro de un techo"
  (`v1_manual_validation.md` Zona F2: Godot lo expulsa hacia abajo, no softlock).

### 10.11 Soltar

- **Produce:** `_release(exit_velocity, use_cooldown)` (`:548-555`) + `_change_state`.
- `body.velocity = exit_velocity`; `_current_segment = null`; si `use_cooldown` → `detector.start_cooldown()`
  (0.8 s); `_change_state(IDLE)`. La `exit_velocity` se integra el siguiente tick (IDLE → `move_and_slide`).
- Tabla de las 7 salidas en §4.4. **Única sin cooldown:** LADDER + crouch.
- **Única que arma zona de exclusión espacial:** HANGING + crouch (`last_hanging_pos`,
  `is_crouch_blocked_after_drop`).
- `HECHO VERIFICADO`.

### 10.12 Cooldown

- **Produce:** `detector.start_cooldown()` (`_cooldown_timer = detection_cooldown = 0.8`) + guarda en
  `parkour_detector.process:62-66`.
- Mientras `> 0`: bloquea ledge **y** ladder; limpia ambos candidatos. Se descuenta por `delta`.
- Se arma en toda salida de estado salvo LADDER+crouch.
- Paralelo (y distinto): zona espacial `last_hanging_pos` radio `2.0`, sólo ledges, sólo por crouch, se
  limpia al aterrizar (§6.5, §8.8).
- `HECHO VERIFICADO`. `PENDIENTE EMPÍRICO`: casos observables de la interacción de los dos temporizadores.

### 10.13 Escalera

- **Produce:** `parkour_detector._process_ladder` + `traversal._on_ladder_candidate_found` +
  `_state_ladder` + `traversal_segment.gd`.
- Detección: esfera radio `1.0` en el jugador; sube ≤4 padres buscando grupo `"ladder"`; valida markers,
  volumen (`progress ∈ [0,1]`, lateral `≤ 1.0`), e **intención** (`not is_on_floor()`, `not crouch`).
  **Nunca se activa desde el piso.**
- Entrada: **directo IDLE→LADDER**, sin SNAPPING. `_current_progress` = proyección inicial del jugador
  sobre el segmento, clampeada.
- Movimiento: **pulsos discretos** — `_ladder_pulse_timer` acumula `delta`; cada `pulse_time` (`0.18 /
  move_speed`) aplica **un** paso `progress_step = ladder_pulse_speed (0.8) * pulse_time / seg_len`.
  Sensación "a tirones". **Con doble ejecución, ~2× el ritmo (§8.1).**
- Sin input de avance neto (`up == down`): `_ladder_dir = 0`, timer a 0, posición reconstruida sin
  cambio.
- Posición mundial: `segment.get_position_at(progress)` = `start_marker.pos.lerp(end_marker.pos, progress)`
  — lerp lineal, sirve para segmentos inclinados (`escalera 3`).
- Stacking: `progress > 1.0` con `neighbour_up` → cambia de segmento arrastrando el remanente; simétrico
  con `neighbour_down`. Sin vecino → clampea en 1.0 / 0.0. Commit `53df531` ("sin el micro stop").
- Salida: jump (flanco) → `_release(cam_fwd*4.0 + UP*5.0)`, cooldown; crouch (flanco) →
  `_release(ZERO, false)`, **sin cooldown**.
- `move_left`/`move_right` no hacen nada en LADDER.
- `HECHO VERIFICADO`. `PENDIENTE EMPÍRICO`: cuán "a tirones" se siente; re-enganche inmediato tras
  crouch; transición de segmento en `escalera 3` (inclinada).

### 10.14 Cámara

- **Produce:** `player._input` (`:38-41`) exclusivamente. Yaw en el **cuerpo** (`rotate_y`, sin límite,
  sin normalización); pitch en la **cámara** (`camera.rotate_x` + clamp `±PI/2` en la misma línea).
- **Ningún estado de traversal toca `body.rotation` ni `camera.rotation`** (`HECHO VERIFICADO`, búsqueda
  completa). No hay cámara "atada al borde", no hay `look_at`, no hay cambio de FOV/shake.
- `camera.position.y` la lerpea `_update_crouch` — **que no corre en traversal** → durante traversal la
  cámara queda a la altura que tenía al entrar.
- El mouse-look funciona **idéntico** en IDLE / SNAPPING / HANGING / CLIMBING / LADDER.
- `free_camera` (tecla F) es una cámara de debug separada; con ella activa el jugador sigue su física y
  el mouse **sigue rotando el cuerpo del jugador**.
- `HECHO VERIFICADO`.

---

## 11. Preguntas abiertas para playtest

> Lo que el código solo no puede responder. Se marca `[prev: …]` cuando un doc previo no versionado
> (`docs/parkour/v1_manual_validation.md` / `v1_playtest_checklist.md`, worktree V1-ref) ya registró un
> hallazgo empírico — a confirmar de nuevo, no es fuente de código.

**Sobre la doble ejecución (§8.1) — lo más urgente de medir:**

1. ¿Cuántas veces por tick corre realmente `traversal._physics_process` con el estado activo? (contador +
   `Engine.get_physics_frames()`).
2. Velocidad **real** del shimmy en la Zona B / borde largo (m/s medidos). ¿Es ~2.5 o ~5.0?
3. Tiempo **real** hasta el `push_warning` de timeout de SNAPPING (colgarse mal a propósito). ¿1.0 s o
   ~0.5 s?
4. Ritmo **real** de pulsos de escalera (pulsos/segundo con `W` sostenido). ¿~5.5/s o ~11/s?
5. ¿La convergencia de SNAPPING/CLIMBING se siente instantánea o con fase de acercamiento?
   `[prev: "instantáneo desde que el probe da válido"]`.

**Colisión ausente en traversal (§8.5, §8.11):**

6. Mantle con el `target` fijo cayendo dentro de un techo sólido: ¿el jugador se incrusta y Godot lo
   expulsa al volver a IDLE, atraviesa, o se atasca? `[prev: se incrusta, Godot lo expulsa hacia abajo,
   no softlock; además el cooldown de 0.8 s impide re-enganchar la cornisa durante la caída]`.
7. Shimmy/hanging: ¿el jugador puede atravesar geometría cercana (una columna, otra pared) mientras
   cuelga, dado que no hay `move_and_slide`?
8. SNAPPING hacia un `_hang_position` que quedó dentro de un objeto: ¿qué pasa al llegar a HANGING?

**Detección y debug (§3.4 CD-5, §8.17):**

9. ¿Las líneas de debug del detector (rayos de pared, esferas de score, esfera cian) son visibles en
   free-roam, o el `DebugDraw.clear()` de `traversal._physics_process` las borra antes de renderizar?
   `[prev: el checklist no lograba verlas para las Zonas D/F]`.
10. ¿La esfera cian del "mejor candidato" aparece en algún momento al saltar contra una pared?

**Escaleras (§8.7, §8.9, §10.13):**

11. Soltar la escalera con `Ctrl` y volver a saltar hacia ella de inmediato: ¿se re-engancha?
    `[prev: sí, se re-engancha]`.
12. Escalera inclinada (`escalera 3`, ~24°): ¿la trepada y la transición de segmento
    `escalera 1 → escalera 3` funcionan sin salto de posición?
13. `escalera 2` (32 unidades, sin vecinos): ¿al llegar al tope el `progress` clampea limpio en 1.0 sin
    tirón?
14. `escalera 5`: ¿el jugador puede "trepar" el tramo entre el tope de la colisión (y≈8.77) y el
    `EndMarker` (y=9)?
15. ¿Se puede entrar a LADDER desde el aire cerca del **tope** de una escalera larga cuando también hay
    un candidato de ledge válido en su filo superior (§8.9)? ¿Gana LADDER?

**Locomoción / salto (§10.1-10.4):**

16. Alcance real de salto a `SPEED (5.0)` y a `RUN_SPEED (9.0)` — ¿cuántos metros de pozo cruza?
    `[prev: corriendo cruza 6 m, caminando no]`.
17. El escalón duro de control aéreo en `vel_h = 7.0`: ¿se nota al pasar de caminar a correr y saltar?
18. `_hay_techo`: ¿bloquea pararse correctamente bajo los techos de `movement_test`?
19. Agacharse en el aire (el código lo permite): ¿tiene algún efecto útil o raro?

**Esquinas / curvas (§10.9):**

20. Doblar una esquina cóncava y una convexa del `circulo circuloso` shimmyeando sin soltar: ¿la
    adopción de normal es fluida?
21. `_calculate_tangent` (lerp sin `delta`): ¿el seguimiento de curva se siente distinto a 30 / 60 / 144
    FPS? `[prev: no probado — sin forma cómoda de cambiar FPS]`.
22. Soltar el input de shimmy a mitad de una transición de cara: ¿`_apply_virtual_normal` deja al
    jugador en una pose de compromiso razonable o "salta"?

**Cámara (§10.14):**

23. Yaw sin límite durante HANGING/LADDER: ¿se puede dar una vuelta completa mirando y el cuerpo rota
    con la cámara? ¿Se ve raro?
24. Free cam activa + mover el mouse: ¿desorienta el yaw del jugador real al volver?

**Integración externa (§9):**

25. `DESCONOCIDO` sin acceso a otras ramas: ¿`traversal_started`/`traversal_ended` tuvieron alguna vez
    consumidores (audio de "agarre", UI, cámara)? En `bd38e49^` no hay ninguno.
26. Interactuar con `monitor_01` (hacking) mientras se está en HANGING/LADDER: `get_tree().paused = true`
    congela el traversal — ¿al despausar retoma el estado limpio?
27. Teleférico (`guided_vehicle`): ¿el jugador es transportado al pararse encima (física de plataforma
    del motor) o se queda quieto mientras el vehículo se va?

**Muerte / daño (§9.6):**

28. Confirmar que **no hay daño de caída** (caer desde `varios/torre`, y≈100, al piso) — el código no
    tiene ninguna llamada a `recibir_daño`.

---

## 12. Checklist de cobertura

### 12.1 Archivos inspeccionados (todos leídos completos salvo indicación)

**Núcleo de movimiento (100%):**
- [x] `bd38e49^:scripts/player n entities/movement/player.gd` (87 L)
- [x] `bd38e49^:scripts/player n entities/movement/movement_controller.gd` (111 L)
- [x] `bd38e49^:scripts/player n entities/movement/parkour_detector.gd` (363 L)
- [x] `bd38e49^:scripts/player n entities/movement/traversal_controller.gd` (612 L)
- [x] `bd38e49^:scripts/player n entities/movement/traversal_segment.gd` (85 L)
- [x] `bd38e49^:scripts/player n entities/movement/kick_controller.gd` (83 L)

**Autoloads / soporte (100% de los relevantes):**
- [x] `bd38e49^:scripts/player n entities/visuals/debug_draw.gd` (146 L)
- [x] `bd38e49^:scripts/player n entities/visuals/debug_ui.gd` (44 L)
- [x] `bd38e49^:scripts/player n entities/visuals/debug_traversal.gd` (185 L)
- [x] `bd38e49^:scripts/player n entities/visuals/debug_trail.gd` (40 L)
- [x] `bd38e49^:scripts/player n entities/visuals/free_camera.gd` (94 L)
- [x] `bd38e49^:scripts/player n entities/visuals/hud.gd` (26 L)
- [x] `bd38e49^:scripts/player n entities/visuals/marco_enfoque.gd` (58 L)
- [x] `bd38e49^:scripts/player n entities/visuals/raycast_interaccion.gd` (72 L)
- [x] `bd38e49^:scripts/player n entities/visuals/salud.gd` (23 L)
- [x] `bd38e49^:scripts/player n entities/inventory/ui_inventario.gd` (221 L) — sólo por la compuerta `UiInventario.visible`
- [x] `bd38e49^:scripts/enviroment/ui_hacking.gd` (63 L) — sólo por `get_tree().paused`
- [x] `bd38e49^:scripts/enviroment/terminal.gd` (parcial: la parte que llama `UIHacking.abrir`)

**Escenas (100% de las relevantes):**
- [x] `bd38e49^:levels/movement_test.tscn` (773 L, main scene) — incluye el script inline `elevator_platform.gd`
- [x] `bd38e49^:levels/test_level.tscn` (84 L)
- [x] `bd38e49^:scenes/components/player.tscn`
- [x] `bd38e49^:scenes/components/traversal_ui.tscn`
- [x] `bd38e49^:scenes/components/debug_ui.tscn`
- [x] `bd38e49^:scenes/components/hud.tscn`
- [x] `bd38e49^:scenes/components/salud.tscn`
- [x] `bd38e49^:scenes/components/debug_trail.tscn`
- [x] `bd38e49^:scenes/components/raycast_interaccion.tscn`
- [x] `bd38e49^:scenes/props/static/escalera_fea_v_1.tscn`
- [x] `bd38e49^:scenes/props/static/circulo_circuloso.tscn`
- [x] `bd38e49^:scenes/props/static/banquitobrutalista_01.tscn`
- [x] `bd38e49^:scenes/props/static/caja_doblada.tscn` (sin instanciar, revisada igual)
- [x] `bd38e49^:scenes/props/dinamic/mesa_standar_1.tscn` (parcial: tipo de nodo)
- [x] `bd38e49^:scenes/props/dinamic/osciloscopio_01.tscn` (parcial: tipo de nodo)
- [x] `bd38e49^:scenes/props/static/monitor_01.tscn` (parcial: script `terminal.gd`)
- [x] `bd38e49^:scenes/components/ui_inventario.tscn` / `ui_hacking.tscn` (headers)

**Config:**
- [x] `bd38e49^:project.godot` (autoloads, InputMap completo, física, display)
- [x] `.uid` de los 6 scripts de movimiento; `.import` de `escalera_grande2.glb` y `escalera pedorra3.glb`

**Transporte (revisados y descartados — §1.4):**
- [x] `guided_vehicle.gd` (1648 L — `grep` de player/velocity/passenger: sin interacción con locomoción)
- [x] `stop_point.gd`, `transition_point.gd`, `world_button.gd`, `vehicle_button.gd`, `scriptdelcilindro.gd`

**`git`:**
- [x] `git log` de los 6 archivos de movimiento (13 commits, 2026-05-24 → 2026-06-14)
- [x] `git status` de ambos worktrees (baseline capturado)

### 12.2 Funciones documentadas (§4)

`player.gd` (6/6): `_ready`, `_on_murio`, `_input`, `_physics_process`, `_get_input_direction`, `_hay_techo`.

`movement_controller.gd` (11 funcs + 1 prop): `setup`, `process`, `freeze`, `set_crouching`,
`set_on_platform`, `_update_jump_state`, `_apply_gravity`, `_handle_jump`, `_update_crouch`,
`_update_speed`, `_apply_movement`, prop `jumped`.

`parkour_detector.gd` (19/19): `setup`, `start_cooldown`, `process`, `_process_ledge`,
`get_current_candidate`, `has_candidate`, `_process_ladder`, `_find_segment`, `_has_ladder_intent`,
`_is_within_segment_volume`, `ladder_detected`, `get_current_ladder_candidate`, `_clear_ladder_candidate`,
`_find_best_candidate`, `_probe_at`, `_score_candidate`, `_raycast`, `_check_clearance`, `_clear_candidate`.

`traversal_controller.gd` (21/21): `_log`, `setup`, `is_active`, `process`, `get_state_name`,
`get_debug_state`, `get_event_log`, `_physics_process`, `_on_candidate_found`, `_on_ladder_candidate_found`,
`_state_snapping`, `_state_hanging`, `_state_climbing`, `_state_ladder`, `_update_shimmy_probes`,
`_calculate_tangent`, `_apply_virtual_normal`, `_edge_continues`, `_release`, `_change_state`, `_draw_debug`.

`traversal_segment.gd` (6/6): `_ready`, `get_position_at`, `get_direction_at`, `get_length`,
`get_neighbour_up`, `get_neighbour_down`.

`kick_controller.gd` (5/5): `setup`, `process`, `_execute_kick`, `_resolve_impact`, `_push_rigidbody`.

`debug_draw.gd` (13/13): `_ready`, `_attach_to_scene`, `clear`, `ray`, `point`, `sphere`, `toggle`,
`toggle_freeze`, `_process`, `_redraw`, `_add_cross`, `_add_sphere_wire`, `_add_circle`.

Scripts de soporte (contrato + funciones relevantes): `debug_ui.gd`, `debug_traversal.gd`
(`_ready`/`_process` + helpers muertos), `debug_trail.gd`, `free_camera.gd` (`_ready`/`_input`/`_process`/
`_toggle`/`_get_move_input`), `hud.gd`, `marco_enfoque.gd`, `raycast_interaccion.gd`
(`_ready`/`_process`/`_input`/`_buscar_interaction_component`), `salud.gd`
(`recibir_daño`/`curar`), `elevator_platform.gd` inline (`_ready`/`_init_position`/`_physics_process`/
`go_to_station`/`_get_speed`/`_update_journey`/`_arrive`/`_apply_position`/`_on_body_entered`/`_on_body_exited`).

### 12.3 Valores no explicados (sin razón de diseño documentada — la mayoría)

`INFERENCIA FUNDADA` en la columna "posible razón" de §7, **sin confirmación del autor** salvo los que
tienen cita de commit. Los que **sí** tienen origen documentado (commit):
- `max_edge_height = 1.5` ← commit `99d3766`.
- `max_surface_tilt_deg = 30.0` ← commit `e446aff` (contexto).
- `ladder_detection_radius = 1.0` ← commit `0340960` (era `ladder_max_distance ~800`).
- `snap_speed = 14.0` / uso de `lerp` ← commit `63082dd` (contexto: "mantiene el momentum").
- Reconexión de `_is_within_segment_volume` ← commit `5ca2d70`.
- Carryover de `progress` en stacking ← commit `53df531`.

**Sin ninguna explicación (ni comentario ni commit) — quedan como `INFERENCIA FUNDADA` o `DESCONOCIDO`:**
`HANG_OFFSET_Y = -0.55`, `HANG_WALL_GAP = -0.68`, `SNAP_TIMEOUT = 1.0`, `snap_threshold = 0.2`,
`climb_speed = 4.0`, `shimmy_speed = 2.5`, `shimmy_max_dist = 0.5`, `jump_force = 6.5`,
`ladder_pulse_speed = 0.8`, `ladder_pulse_time = 0.18`, CLIMBING `UP*2.2` y `-normal*0.4` y `0.12` y
`-normal*1.5`, releases `2.0`/`3.5`/`1.0`/`4.0`/`5.0`, `_transitioning_face` lerp `4.0`, `_calculate_tangent`
lerp `0.15`, `PROBE_OFFSETS_INNER` (6 valores), `PROBE_HEIGHTS` (5 valores), score pesos `0.35/0.30/0.20/0.15`,
score umbrales `0.3`/`0.5`, `detection_distance = 0.85`, `min_edge_height = 0.5`, `min_score = 0.35`,
`clearance` `0.25×1.2`, coherencia lateral `0.35`, offsets de rayo `0.08`/`0.05`/`0.4`/`0.7`/`0.2`/`1.0`,
`detection_cooldown = 0.8`, zona de exclusión `2.0`, `AIR_CONTROL_*` `0.3`/`1.5`, umbral aéreo `7.0`,
`AIR_FRICTION 0.8` / `FALL_FRICTION 3.0`, `CROUCH_TRANSITION 8.0`, `ACCELERATION 14.0`, alturas de crouch
`0.8`/`2.0`, cámara `0.4`/`0.706`/`0.8(escena)`, `floor_max_angle 46°`, `_hay_techo` margen `0.6`,
`kick_upward 0.2`.

### 12.4 Consumidores NO confirmados

| Elemento | Estado |
|---|---|
| `traversal_started` / `traversal_ended` | Sin consumidor en `bd38e49^`. `DESCONOCIDO` si los hubo en otras ramas del proyecto. |
| `candidate_lost` / `ladder_candidate_lost` | Sin consumidor. `HECHO VERIFICADO` (no conectadas en `setup`). |
| `salud.vida_cambiada` | Sin consumidor (`grep`). |
| grupo `"raycast"` | Sin consumidor de código. `HECHO VERIFICADO`. |
| `get_current_candidate` / `has_candidate` / `get_current_ladder_candidate` / `get_direction_at` / `DebugDraw.toggle` / prop `jumped` | Sin consumidor. `HECHO VERIFICADO`. |
| `movement.set_on_platform` | Único caller (`elevator_platform.gd`) inerte en `movement_test`. |

### 12.5 Hipótesis pendientes (todas requieren jugar V1)

Ver §11 (28 preguntas). Las de mayor impacto para una reconstrucción:
1. **Magnitud real de la doble ejecución de `_physics_process`** (§8.1) — afecta shimmy, snap timeout,
   ritmo de escalera, convergencia de climb/snap. Sin esto, cualquier "port" de los valores de §7 saldría
   ~2× de lo intencionado.
2. **Comportamiento del jugador sin colisión en traversal** (§8.5) — especialmente mantle contra
   geometría (`[prev: Godot lo expulsa, no softlock]`).
3. **Visibilidad real del debug del detector** (§3.4 CD-5) — si está suprimido, cualquier ajuste de
   detección "a ojo" fue a ciegas.
4. **Dependencia de framerate de `_calculate_tangent`** (§8.12).
5. **Solapamiento ledge/ladder cerca del tope de una escalera** (§8.9).

### 12.6 Estado de cobertura

**No se declara "auditoría completa" en sentido absoluto:** quedan como `DESCONOCIDO` (a) el radio exacto
del `CapsuleShape3D` del jugador, (b) el valor de gravedad del proyecto (default asumido), (c) posibles
consumidores de señales en ramas del proyecto fuera de este worktree aislado. Todo lo demás —cada script
de movimiento/parkour, cada función, cada valor a dedo, cada señal, cada grupo, cada nodo requerido, cada
guarda, cada rama muerta, la escena principal y las de soporte— fue rastreado y está documentado arriba.

---

## Apéndice A — Referencias rápidas de archivo:línea

| Tema | Cita |
|---|---|
| Despacho de física | `bd38e49^:scripts/player n entities/movement/player.gd:55-70` |
| Doble `_physics_process` | `bd38e49^:scripts/player n entities/movement/traversal_controller.gd:95-96` + `:127` + `player.gd:63` |
| `DebugDraw.clear()` por tick | `bd38e49^:scripts/player n entities/movement/traversal_controller.gd:128` |
| Enum de estados | `bd38e49^:scripts/player n entities/movement/traversal_controller.gd:18` |
| Cálculo de `_hang_position` | `bd38e49^:scripts/player n entities/movement/traversal_controller.gd:158-165` |
| Target fijo de mantle | `bd38e49^:scripts/player n entities/movement/traversal_controller.gd:299` |
| Pulso de escalera | `bd38e49^:scripts/player n entities/movement/traversal_controller.gd:346-358` |
| Salida LADDER sin cooldown | `bd38e49^:scripts/player n entities/movement/traversal_controller.gd:328` |
| Probe de ledge | `bd38e49^:scripts/player n entities/movement/parkour_detector.gd:255-307` |
| Score de candidato | `bd38e49^:scripts/player n entities/movement/parkour_detector.gd:309-334` |
| Intención de escalera | `bd38e49^:scripts/player n entities/movement/parkour_detector.gd:180-188` |
| Zona de exclusión | `bd38e49^:scripts/player n entities/movement/parkour_detector.gd:86-93` |
| Constantes de locomoción | `bd38e49^:scripts/player n entities/movement/movement_controller.gd:4-13` |
| Control aéreo asimétrico | `bd38e49^:scripts/player n entities/movement/movement_controller.gd:102-111` |
| InputMap | `bd38e49^:project.godot:32-113` |
| Autoloads | `bd38e49^:project.godot:18-24` |
| Escena principal | `bd38e49^:project.godot:14` → `bd38e49^:levels/movement_test.tscn` |
| Árbol del jugador | `bd38e49^:scenes/components/player.tscn` |
| Escaleras del playground | `bd38e49^:levels/movement_test.tscn:462-497` |

## Apéndice B — InputMap completo (`bd38e49^:project.godot:32-113`)

| Acción | Tecla física | Consumidor(es) |
|---|---|---|
| `move_forward` | W (87) | `player._get_input_direction`; `traversal._state_ladder` (subir); `traversal.get_debug_state` |
| `move_back` | S (83) | `player._get_input_direction`; `traversal._state_hanging` (soltar); `traversal._state_ladder` (bajar) |
| `move_left` | A (65) | `player._get_input_direction`; `traversal._state_hanging` (shimmy) |
| `move_right` | D (68) | `player._get_input_direction`; `traversal._state_hanging` (shimmy) |
| `jump` | Espacio (32) | `movement._handle_jump` (sostenido); `traversal._state_snapping/_state_hanging/_state_ladder` (flanco) |
| `run` | Shift (4194325) | `movement._update_speed` |
| `crouch` | Ctrl (4194326) | `player._input` (toggle); `parkour_detector._has_ladder_intent`; `traversal._state_hanging/_state_ladder` (flanco); `traversal._physics_process` IDLE |
| `kick` | C (67) | `kick_controller.process` (flanco) |
| `toggle_trail` | K (75) | `debug_trail._input` — **nodo sin instanciar (§8.4)** |
| `toggle_free_cam` | F (70) | `free_camera._input` |
| `toggle_debug_freeze` | G (71) | `debug_draw._process` |
| `toggle_debug_traversal` | F12 (4194332) | `debug_traversal._process` — **panel inerte (§8.2)** |
| `ui_cancel` | Esc | `player._input` (liberar mouse); `ui_hacking._input` (cerrar) |
| `interactuar` | E (69) | `raycast_interaccion._input` |
| `toggle_inventario` | Tab (4194306) | `ui_inventario._input` — **input desactivado (§8.3)** |
| `tirar_item` | T (84) | inventario legacy |
| `rotar_item` | R (82) | `ui_inventario._input` — desactivado |

Todas con `"deadzone": 0.2` (irrelevante para teclado). `HECHO VERIFICADO`.
