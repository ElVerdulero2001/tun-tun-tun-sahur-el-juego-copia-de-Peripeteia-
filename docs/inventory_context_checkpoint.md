# Inventory / PlayerV2 — CONTEXT CHECKPOINT (handoff)

> **Archivo de CONTEXTO OPERATIVO.** No es documentación arquitectónica formal ni
> postmortem. Escrito para una instancia futura de Claude que va a retomar el
> trabajo **con el contexto de esta conversación comprimido/reiniciado**.
>
> **UNTRACKED a propósito.** No agregar a git. Se puede borrar/reescribir.
>
> **Fuente de verdad = el repo actual** (`HEAD = b3e8ee5`). Este archivo puede
> quedar desactualizado; si contradice el código, gana el código.
>
> Doc arquitectónica formal (foto C0–C3, ya no es el estado actual completo):
> `docs/player_v2_inventory_integration_c0_c3.md`.
> Doc del modelo V0/V1 (foto en `2893a70`, con marcas SUPERSEDED):
> `docs/inventory_system_v0_v1.md`.
>
> Generado tras **SUA-1.6 D + CIERRE FUNCIONAL de InventoryV2** (`b3e8ee5`), 2026-08-30.
> `INVENTORYV2 FUNCTIONAL CLOSURE = APPROVED` — ver §13.

---

## 1. ESTADO GIT

- **Repo:** `origin` → `https://github.com/ElVerdulero2001/tun-tun-tun-sahur-el-juego-copia-de-Peripeteia-.git`
- **Ruta local:** `C:\Users\ElCaido97\Documents\tun-tun-tun-sahur`
- **Rama:** `main`
- **HEAD:** `b3e8ee5` — *SUA-1.6 D: migrate key to InventoryV2*
- **Adelante de `origin/main`:** **17 commits. SIN PUSH** (todo el trabajo PlayerV2 + migración es local).
- **Working tree (tracked):** LIMPIO tras el commit SUA-1.6 D.
- **Untracked ajenos (NO tocar, NO `git add`):** `assets/models/collectibles/**` y
  `assets/models/no_collectibles/**` (~puñado de `.webp/.jpg/.png` + `.import`).
- **Este archivo** (`docs/inventory_context_checkpoint.md`) permanece **UNTRACKED**.
- **Godot:** 4.6.3 stable. Binario headless:
  `/c/Godot/4.6.3/Godot_v4.6.3-stable_win64_console.exe` (Git Bash). NO está en PATH.
  Import: `--headless --editor --quit` (tarda ~1-2 min; correrlo tras agregar/renombrar scripts o `.tres`).

### Commits desde PlayerV2 (del más viejo al más nuevo)

```
1b9f897  SUA-1.2: PlayerV2 locomotion and interaction
8bb5420  SUA-1.3 C0: add per-instance PlayerV2 inventory
2d22cd5  SUA-1.3 C1: route pickups through actor inventory
4d05e4c  SUA-1.3 C2: make inventory authority routing stateless
61eba68  SUA-1.3 C3: validate PlayerV2 inventory pickup end-to-end
7bc1f78  docs: checkpoint PlayerV2 inventory integration C0-C3
f2aa456  SUA-1.4 C4-A: attach InventoryPanel to PlayerV2
4451a5c  SUA-1.4 C4-B0: hibernate legacy inventory UI input
bf09c5b  SUA-1.4 C4-B: add PlayerV2 inventory UI controls
eb2381f  SUA-1.4 C4-C: remove PlayerV2 escape mouse toggle
ac05cba  SUA-1.5 C5-A: add PlayerV2 item drop capability
cfe4ede  SUA-1.5 C5-B: add inventory drop intent
f27484c  SUA-1.5 C5-B2: add inventory drop neutral zone
d9a0084  SUA-1.5 C5-C: connect inventory drop to PlayerV2
feb42f1  SUA-1.6 B: migrate bottle to InventoryV2
8dbfe5b  SUA-1.6 C: migrate saber to InventoryV2
b3e8ee5  SUA-1.6 D: migrate key to InventoryV2                <- HEAD
```

`SUA-1.6 A` (auditoría de migración) y la **auditoría puerta/monitor/llave** + la **auditoría profunda
del inventario legacy** (esta) NO tienen commit propio: son análisis puro, sin cambios de archivo salvo este checkpoint.

`1b9f897` también congela SUA-1.1 (locomoción, no commiteada aparte).
**SUA-1.6 A** (auditoría de migración) NO tiene commit propio: fue análisis puro, sin cambios de archivo.

### Incidente resuelto (histórico)
Durante la prueba manual de C5-B2 el editor cambió `project.godot` `run/main_scene` al sandbox
(F5 accidental). **Revertido** con `git checkout -- project.godot`. `project.godot` está intacto
respecto de HEAD (ni C5-C ni SUA-1.6 B lo tocaron; `run/main_scene` sigue `movement_test.tscn`).

---

## 2. ARQUITECTURA PlayerV2 ACTUAL

Escena `scenes/player_v2/player_v2.tscn` (`load_steps=9`):

```
PlayerV2 (Node3D)  [SIN script — identidad lógica]
├── Inventory            [Node, InventoryV2]            grid 4x4 (default)
├── InventoryAuthority   [Node, LocalAuthority]
├── InventoryReceiver    [Node, InventoryReceiver]      mundo -> inventario
├── ItemDropper          [Node, ItemDropper]            inventario -> mundo (C5-A)
├── PlayerInventoryUI    [CanvasLayer, player_inventory_ui.gd]
│   └── InventoryPanel   (instancia scenes/components/inventory/inventory_panel.tscn, offset 560,280, cell_size 56)
│       └── InventoryGridView
│           └── InventoryManipulator
└── Body (CharacterBody3D)  [player_v2.gd]   transform (0, 1.5, 0)
    ├── CollisionShape3D   (CapsuleShape3D r=0.3 h=1.8, offset y=0.9)
    ├── DropPoint          [Marker3D]   transform local (0, 1.0, -1.2)   (C5-A)
    ├── View (Node3D)      offset y=1.6
    │   └── Camera3D       current=true
    └── Interaction (Node) [interaction.gd = InteractionV2]
```

### Wiring explícito (`@export` con `node_paths` en `player_v2.tscn`)

| Componente | `@export` | apunta a |
|---|---|---|
| **Interaction** | `actor` / `physics_body` / `aim_source` | `../..` (PlayerV2 root) / `..` (Body) / `../View/Camera3D` |
| **InventoryReceiver** | `inventory` / `authority` | `../Inventory` / `../InventoryAuthority` |
| **ItemDropper** | `inventory` / `authority` / `spawn_source` | `../Inventory` / `../InventoryAuthority` / `../Body/DropPoint` |
| **PlayerInventoryUI** | `inventory` / `authority` / `dropper` | `../Inventory` / `../InventoryAuthority` / `../ItemDropper` |

> El ciclo mundo↔inventario de PlayerV2 está CERRADO y validado end-to-end (C5-C), y ahora
> también validado con un **asset real** (botella, SUA-1.6 B — ver §9).

### Capa de interacción — COMPARTIDA legacy ↔ V2 (hallazgo SUA-1.6 A)

`scripts/player n entities/InteractionComponent.gd` + `Interaction.gd` sirven **a los dos mundos**:
- Legacy: `raycast_interaccion.gd` (Player V1) resuelve `InteractionComponent` subiendo por ancestros.
- V2: `interaction.gd` (InteractionV2) lo resuelve como **hijo directo del collider**.
- Contrato `_on_interact(interaction) -> Variant`: lo implementan `WorldItemV2`, `Item.gd`, `puerta.gd`, `terminal.gd`.

**No hay migración de interacción pendiente** para los props reales: ya llevan `InteractionComponent`
hijo directo del body y InteractionV2 los detecta. Lo único que se migra por prop es el **modelo de inventario**.

### Archivos de producción

`scripts/player_v2/`: `player_v2.gd`, `interaction.gd` (InteractionV2), `player_inventory_ui.gd`, `item_dropper.gd`,
`botella_integration.gd` (arné de integración SUA-1.6 B, debug-only).
`scripts/player n entities/inventory_v2/`: `inventory.gd` (InventoryV2), `local_authority.gd`, `inventory_receiver.gd`,
`world_item.gd`, `transfer_operation.gd`, `item_definition.gd`, `item_instance.gd`, `inventory_entry.gd`,
`inventory_grid_view.gd`, `inventory_manipulator.gd`, `inventory_panel.gd`, `inventory_v0_test_scene.gd` (arné manual).

---

## 3. PRINCIPIOS ARQUITECTÓNICOS CERRADOS

> **"Cada sistema es dueño de las reglas que definen su dominio.
> Compartimos infraestructura cuando conviene; no compartimos significado."**

| Sistema | Dueño de |
|---|---|
| **InteractionV2** (`interaction.gd`) | qué es **interactuable**: raycast propio, 2.5 m, closest hit, oclusión, resolver `InteractionComponent` hijo directo del collider |
| **InventoryReceiver** | capacidad **mundo → inventario**: traduce `Interaction.actor` → `InventoryV2` concreto |
| **ItemDropper** | capacidad **inventario → mundo**: dónde y bajo qué parent reaparece el item (semántica espacial) |
| **InventoryManipulator** | interacción de la **grilla**: held/preview/rotación tentativa; clasifica el drop en 3 regiones; **emite intención, no ejecuta** |
| **InventoryPanel** | **presentación / composición** de `GridView` + `Manipulator`; reenvía señales 1:1; cero lógica de modelo |
| **PlayerInventoryUI** | **input / foco de UI** del Player local: TAB, `Input.mouse_mode`, ESC-con-panel-abierto; y (C5-C) **puente** entre la intención de drop de la UI y el `ItemDropper` de la entidad — delega, NO implementa reglas espaciales |
| **LocalAuthority** | **frontera de autoridad STATELESS**: único que corre `TransferOperation.validate()/commit()`; cada operación recibe su `InventoryV2` explícito |
| **TransferOperation** | ejecutar la transferencia **atómica** `request → validate → commit` |
| **WorldItemV2** | carcasa **física neutral** de un `ItemInstance` en el mundo; se autoaprovisiona un `ItemInstance` desde su `definition` si nadie se lo inyectó (SUA-1.6 B) |
| **ItemDefinition** | **qué tipo de objeto es** y **qué representación mundial le corresponde a ese TIPO** (`world_scene_path` + `get_world_scene()`) |
| **ItemInstance** | esta copia concreta (identidad = la referencia). NO sabe de qué escena física vino |

**NO hay / NO usar:** Service Locator, EventBus global, `get_first_node_in_group("player")` para ownership,
Autoload/singleton para el inventario de una entidad, script coordinador en el root `PlayerV2`,
`ItemManager` / `Catalogo V2` / registry global.

---

## 4. IDENTIDAD / OWNERSHIP ESPACIAL

| Nodo | Rol |
|---|---|
| **PlayerV2 root** | identidad lógica. **NO usar como posición física.** |
| **Body** | autoridad física (velocity, move_and_slide, yaw, colisión) |
| **View** | pitch (mouse-look vertical) |
| **Camera3D** | mirada; reservada para un futuro throw/aim |
| **DropPoint** | fuente espacial de **SOLTAR**. `Marker3D` bajo `Body`, local `(0, 1.0, -1.2)` (sigue posición + yaw del Body, sin pitch) |

`ItemDropper.soltar()`:
- `world_parent = get_tree().current_scene as Node3D` (validado; si no es `Node3D` → `push_warning` + `null`). **Aceptado por ahora. Sin `world_parent_override`.**
- `position = spawn_source.global_position`

---

## 5. FLUJO PICKUP COMPLETO (C1/C2, validado C3, manual OK, + botella real SUA-1.6 B)

```
Camera3D  →  InteractionV2._physics_process (raycast propio, 2.5m, closest hit, oclusión,
                                             exclude Body por RID, mask=3)
   →  hit.collider (WorldItemV2, layer 2)  →  InteractionComponent hijo directo
   →  al pulsar "interactuar":  InteractionV2.try_interact()  →  Interaction.new(actor = PlayerV2 root, &"usar")
   →  WorldItemV2._on_interact(interaction)  →  _solicitar_pickup(interaction.actor)
       ├─ actor == null            → false
       ├─ item_instance == null    → false   (fail-fast local, SUA-1.6 B)
       └─ _resolver_receiver(actor): primer InventoryReceiver entre los HIJOS DIRECTOS del actor (sin → false)
   →  InventoryReceiver.recibir_pickup(world_item)
   →  LocalAuthority.solicitar_pickup(world_item, inventory)          ← inventario EXPLÍCITO
   →  TransferOperation.crear_mundo_a_inventario → validate() → commit()
   →  InventoryV2._agregar_entry(...)  --emit--> contenido_cambiado ; world_item.queue_free()
```

### WorldItemV2 — autoaprovisionamiento (SUA-1.6 B)

```gdscript
class_name WorldItemV2 extends RigidBody3D
@export var definition: ItemDefinition       # opcional; para props colocados directo en una escena
var item_instance: ItemInstance

func _ready() -> void:
    if item_instance == null and definition != null:
        item_instance = ItemInstance.new(definition)
```
- `item_instance` **inyectado** (tests, sandboxes, restore futuro) → SIEMPRE gana, `_ready()` no lo pisa.
- `item_instance == null` + `definition` válida → crea **exactamente una** `ItemInstance`.
- ambos null → el nodo existe, no crashea; el pickup falla limpio (fail-fast local + `TransferOperation.validate`).
- `definition` NO agrega autoridad / inventario / lookup de Player / grupos. `WorldItemV2` **sigue neutral**.

**Firmas actuales:**
```gdscript
LocalAuthority.solicitar_pickup(world_item: WorldItemV2, inventory: InventoryV2) -> bool
LocalAuthority.solicitar_devolucion(item_instance: ItemInstance, inventory: InventoryV2, parent: Node3D, position: Vector3) -> WorldItemV2
LocalAuthority.solicitar_reubicacion(item_instance: ItemInstance, inventory: InventoryV2, nueva_pos: Vector2i, nuevo_rotated: bool) -> bool
InventoryReceiver.recibir_pickup(world_item: WorldItemV2) -> bool
```
`WorldItemV2` **no tiene** `_authority` ni `setup()` (borrados en C2). `LocalAuthority` **no tiene**
`_inventory_receptor` / `set_inventory_receptor()` / `_encontrar_inventory_receptor()` (borrados en C2).

**Garantías (tests):** mismo `ItemInstance` (referencia), custodia XOR mundo/inventario, `WorldItemV2` neutral,
dos PlayerV2 con inventarios aislados, atomicidad `validate→commit`.

---

## 6. FLUJO DROP — CAPACIDAD (C5-A) — **IMPLEMENTADA Y CONECTADA (C5-C)**

```gdscript
class_name ItemDropper extends Node
@export var inventory: InventoryV2
@export var authority: LocalAuthority
@export var spawn_source: Node3D

func soltar(item_instance: ItemInstance) -> WorldItemV2:
    #  item null / refs sin cablear → null
    #  world_parent = get_tree().current_scene as Node3D  (null → push_warning + null)
    #  return authority.solicitar_devolucion(item_instance, inventory, world_parent, spawn_source.global_position)
```

```
ItemDropper.soltar(ii)  →  LocalAuthority.solicitar_devolucion(ii, inventory, current_scene, DropPoint.global_position)
   →  TransferOperation.crear_inventario_a_mundo
        → validate  (has_item, definition.get_world_scene() != null, parent válido)   ← get_world_scene(), SUA-1.6 B
        → commit
            var escena := item_instance.definition.get_world_scene()   # resuelto UNA vez, en local
            var nodo := escena.instantiate()
            si (nodo as WorldItemV2) == null:  push_error + nodo.free()  + return null   ← hole cerrado, SUA-1.6 B
            parent.add_child(nuevo) → global_position = spawn_position → inventory._quitar_entry(ii)
   →  devuelve el WorldItemV2 NEUTRAL (misma referencia ItemInstance)
```

**Quién lo llama:** `PlayerInventoryUI._on_drop_fuera_solicitado(item_instance)` — conectado en C5-C a
`InventoryPanel.drop_fuera_solicitado`. Handler de 1 línea: `dropper.soltar(item_instance)`.
Sin lógica espacial en `PlayerInventoryUI`.

**Hole preexistente — CERRADO (SUA-1.6 B):** si `get_world_scene().instantiate()` produce un nodo que
NO es `WorldItemV2` (o `instantiate()` falla), `_commit_inventario_a_mundo` ahora hace
`if nodo != null: nodo.free()` + `return null`. El `_quitar_entry` va **después** → el item queda en
`InventoryV2`, sin nodo huérfano, sin pérdida ni duplicación. Cubierto por `botella_v2_migration_test` caso "M".

---

## 7. FLUJO INTENCIÓN DE DROP (C5-B / C5-B2) — **IMPLEMENTADO Y CONSUMIDO (C5-C)**

`InventoryManipulator`, con un item **held**, al hacer click izquierdo clasifica la posición del cursor
(`_view.get_local_mouse_position()`, píxeles local-space de `InventoryGridView`) en 3 regiones:

```gdscript
enum RegionDrop { GRILLA, ZONA_NEUTRA, EXTERIOR }
@export var drop_neutral_margin_px: float = 24.0     # APROBADO manualmente

_region_de_drop(pos_local):
    grid_rect := Rect2(0, 0, grid_width*cell_size, grid_height*cell_size)
    grid_rect.has_point(pos)            -> GRILLA
    grid_rect.grow(margin).has_point()  -> ZONA_NEUTRA
    else                                -> EXTERIOR
```

| Región | Acción |
|---|---|
| **GRILLA** | `soltar()` → reubicación (destino inválido → rechazada → sigue held). |
| **ZONA_NEUTRA** (anillo 24 px) | **NO-OP absoluto** (`pass`). Item sigue held. NO cancela, NO limpia held, NO señal, NO toca `InventoryV2`. |
| **EXTERIOR** | `descartar_fuera()`: captura la ref, limpia held **LOCAL** (sin `cancelado.emit`), `queue_redraw()`, emite `drop_fuera_solicitado(item_instance)`. NO toca `InventoryV2` ni `LocalAuthority`. |

`InventoryPanel` reenvía `drop_fuera_solicitado(item_instance)` **1:1**.

**Cadena completa (C5-C, VALIDADA):**
```
InventoryManipulator.descartar_fuera()  --emit-->  drop_fuera_solicitado(ii)
   →  InventoryPanel._reenviar_drop_fuera_solicitado (1:1)
   →  PlayerInventoryUI._on_drop_fuera_solicitado(ii)   (conexión única en _ready)
   →  ItemDropper.soltar(ii)  →  LocalAuthority.solicitar_devolucion  →  TransferOperation  →  WorldItemV2
```

**Ante fallo del drop:** el manipulator YA limpió su held LOCAL antes de emitir; `validate()` rechaza y
NO quita la entry → el `ItemInstance` sigue en `InventoryV2` en su celda original. Sin rollback manual.
El `InventoryPanel` **NO se cierra** tras el drop.

Método testeable: `_resolver_click_held(pos_local: Vector2)` (los tests lo llaman con posiciones explícitas —
headless no posiciona el mouse real).

---

## 8. UI / INPUT ACTUAL (C4 + C5-C)

**`PlayerInventoryUI` (`CanvasLayer`)** — usa `_shortcut_input` (NO `_unhandled_input`):
- **TAB** → abre/cierra `InventoryPanel` + `set_input_as_handled()`. abrir → `mouse_mode = VISIBLE`; cerrar → `CAPTURED`.
- **ESC con panel abierto** → lo consume: `panel.cerrar()` (→ `desactivar()` → `cancelar()`) + `mouse_mode = CAPTURED` + handled.
- **ESC con panel cerrado** → NO lo consume (`player_v2.gd` ya NO togglea mouse con ESC — C4-C).
- **(C5-C) `@export var dropper: ItemDopper`** + `panel.drop_fuera_solicitado.connect(_on_drop_fuera_solicitado)` (única, en `_ready`).

**Por qué `_shortcut_input`:** en reverse-tree `player_v2.gd` recibiría el ESC ANTES; `_shortcut_input` corre antes de TODO `_unhandled_input`.

**Decisión de gameplay CERRADA (mecánica intencional, NO deuda):** con el inventario abierto → WASD,
salto y física/mundo continúan; **mouse-look detenido** (por `mouse_mode == VISIBLE`). El inventario **NO** inmoviliza al jugador.

**E / InteractionV2 con inventario abierto:** permitido por ahora. Aún NO definitivo.

---

## 9. SUA-1.6 — MIGRACIÓN DE ASSETS REALES A InventoryV2

### 9.1 SUA-1.6 A — auditoría de migración — **COMPLETADA** (sin commit; análisis puro)

Censo completo de props / items / consumidores de inventario del repo. Hallazgos clave:

- **La capa `InteractionComponent` / `Interaction` ya sirve a legacy Y a V2** (ver §2). Cero migración de interacción pendiente para props reales.
- **Items legacy migrables:** `botella_standar_1` (✅ hecho en B), `sable_san_martin_1` (NEXT, §13), `llave_comun_1` (junto con puerta).
- **`puerta.gd`** = consumidor legacy de inventario: `_toggle()` recorre `Inventario.items` buscando `item_id == id_llave`.
- **`Catalogo`** (Autoload) = registro estático `int → (forma, prefab)`. **Esencialmente reemplazable por `ItemDefinition`** (footprint + `world_scene_path`). No cumple ninguna función extra.
- **`mesa_standar_1` / `osciloscopio_01`** NO son items (`Item.gd` con `es_recogible = false`; solo exponen `data.nombre` al HUD). No convertir en `WorldItemV2`.
- **`granada_01.tscn`** está **incompleta/rota** (root sin script → el `InteractionComponent` hijo falla el assert). Separada; NO se toca en la migración de items.
- **Player V1** (`movement_test.tscn`, main scene) sigue siendo consumidor legacy.
- **Decisión H.1:** NO hibridizar Player V1 con InventoryV2, NO migrar `movement_test.tscn` todavía.
  Los assets migrados se validan en **escenas de integración con PlayerV2** (opción C).
- Objetos huérfanos detectados (NO borrar): `municion_9mm.tres`, `granada.tres` (solo referida por el dict de `Catalogo`), `levels/test_level.tscn` (sin referencias).

### 9.2 Cambio de contrato: `ItemDefinition.world_scene_path` (descubierto en la integración real)

**Problema:** un prop tipado referencia su `ItemDefinition` (`botella.tscn --@export definition--> botella.tres`).
Si `ItemDefinition` guardara `@export var world_scene: PackedScene` apuntando de vuelta a la escena, se forma
un **ciclo DURO de recursos** que el parser de texto de Godot NO resuelve en carga fría:
`Parse Error: [ext_resource] referenced non-existent resource` → `definition` llega `null`.
(El import del editor lo tolera/difiere; el fallo aparece al **instanciar la escena de verdad**.)

**Contrato final adoptado (`scripts/player n entities/inventory_v2/item_definition.gd`):**

```gdscript
@export_file("*.tscn") var world_scene_path: String = ""    # ÚNICA fuente de verdad

var world_scene: PackedScene:                               # alias SOLO LECTURA (sin setter)
    get:
        return get_world_scene()

func get_world_scene() -> PackedScene:                      # API CANÓNICA
    if world_scene_path.is_empty():
        return null
    return load(world_scene_path) as PackedScene            # resolución LAZY vía ResourceLoader
```

- `world_scene_path` = **única fuente de verdad**. `world_scene` es propiedad **computada de lectura**,
  **sin setter**, no guarda estado → **nadie puede desincronizarla**. NO es una segunda fuente de verdad.
- El alias existe **exclusivamente** para no tocar **19 arneses de test históricos** que leen `definition.world_scene`
  directamente. Código nuevo / de producción usa `definition.get_world_scene()`.
- **Deuda técnica futura OPCIONAL (no urgente):** migrar esos 19 tests a `get_world_scene()` y retirar el alias.
- Doc en el script explica **por qué** es un path (romper el ciclo) y prohíbe volver a `@export PackedScene`.
- `get_world_scene()` NO instancia, NO conoce InventoryV2 / TransferOperation / Player / autoridad, NO muta
  estado runtime, NO cachea en campo propio (confía en el cache de `ResourceLoader`).
- El ciclo **SEMÁNTICO** escena↔definición sigue existiendo (y está bien); el ciclo de **dependencias del
  parser** ya no.

`TransferOperation` (ruta INVENTARIO → MUNDO) usa `definition.get_world_scene()` en `_validar_inventario_a_mundo`
y `_commit_inventario_a_mundo`. **NO sabe** que la definición guarda un String / cómo funciona el loader.

### 9.3 SUA-1.6 B / C / D — items reales migrados — **TODOS CERRADOS (auto + manual + commit)**

Mismo patrón para los tres: `RigidBody3D` + `world_item.gd` (`WorldItemV2`), `@export definition` → un
`.tres` en `assets/data/items_v2/`, `InteractionComponent` hijo directo, mesh/collider/física/transform
intactos, `collision_layer=10 mask=9` sin cambios (capa 2 ∈ 10 → InteractionV2 los detecta), autoaprovisionamiento.
Ninguno depende ya de `Item.gd` / `ItemData` / `Inventario` / `Catalogo`.

| Fase | Commit | Escena | `.tres` (id) | footprint | `can_rotate` | test |
|---|---|---|---|---|---|---|
| **B** botella | `feb42f1` | `botella_standar_1.tscn` | `botella.tres` (`&"botella_standar"`) | **1×3** | true | `botella_v2_migration_test` **45/0** |
| **C** sable | `8dbfe5b` | `sable_san_martin_1.tscn` | `sable.tres` (`&"sable_san_martin"`) | **1×4** | true | `sable_v2_migration_test` **32/0** |
| **D** llave | `b3e8ee5` | `llave_comun_1.tscn` | `llave.tres` (`&"llave_comun"`) | **1×1** | **false** | `llave_v2_migration_test` **36/0** |

Footprints = **decisión de contenido** (el legacy no entra en la grilla 4×4): botella `Catalogo.formas[2]` era
2×5; sable `formas[3]` era 2×10 → se eligieron 1×3 / 1×4 por proporción física (cilindro alto, hoja larga).
Llave: collider `(0.38, 0.085, 0.135)` → objeto chico y compacto → **1×1**, `can_rotate=false` (rotar un
cuadrado 1×1 es no-op; el test verifica que se rechaza en `LocalAuthority` y en `manipulator.rotar_tentativo`).

Cada fase agregó: `assets/data/items_v2/<item>.tres`, `scenes/player_v2/<item>_integration.{tscn,gd,gd.uid}`
(arné PlayerV2, NO inyecta `ItemInstance`), `scenes/test/<item>_v2_migration_test.{gd,gd.uid,tscn}`.
B además: migró los 2 `.tres` de test a `world_scene_path`, y agregó `scenes/test/fixtures/not_a_world_item.tscn`.

### 9.4 Legacy NO tocado por B/C/D

`Inventario`, `UiInventario`, `Catalogo`, `TirarItem`, `Item.gd`, `ItemData`, `ItemInstancia`, `puerta.gd`,
`terminal.gd`, `ui_hacking.gd`, `player.gd`, `movement_test.tscn`, `granada`, `mesa`, `osciloscopio`,
`project.godot`, InputMap, core InventoryV2/PlayerV2, los 19 arneses históricos.
`Catalogo.gd` conserva refs **stale** por string a `llave/botella/sable` scenes (`prefabs[1/2/3]`) — inofensivas
(solo las consumen rutas legacy sobre `Inventario.items`, donde ningún item migrado entra). NO corregir todavía.

### 9.5 Auditoría PUERTA / MONITOR / LLAVE — **COMPLETADA** (análisis puro)

- **`monitor/terminal → puerta` = sistema FUNCIONAL real** (clase A, implementado y usado). Cadena en
  `movement_test.tscn`: E sobre `monitor_01` (`terminal.gd`, `class_name Terminal`) → `UIHacking.abrir()` (autoload)
  → tipear `"1234"` (`Terminal.contrasena`) → `terminal.get_node(Terminal.objetivo)` (`NodePath` `"../puertas/door_rust_01"`)
  → `puerta.desbloquear()` → `desbloqueada = true` + `_toggle()` → la puerta se abre. **Cero inventario.**
- **`llave → puerta` = rama PROTOTIPO ROTA** (clase D). `door_rust_01` en `movement_test` tiene `requiere_llave = true`
  pero **`id_llave` nunca se configuró** (queda `0`); `key.tres` es `item_id = 1` → el chequeo
  `for instancia in Inventario.items: if instancia["data"].item_id == id_llave` **no puede pasar nunca**. Además
  `desbloquear()` (del terminal) **saltea** ese chequeo. Cero tests, cero manual. Nunca fue una feature.
- **Decisiones:** NO migrar `puerta.gd` a InventoryV2 por esa rama. Una feature `llave→puerta` real sería
  **trabajo NUEVO de dominio puerta** (la puerta consulta el `InventoryV2` del actor por un `ItemDefinition.id`).
  `puerta` / `terminal` / `UIHacking` quedan **fuera de esta etapa**.
- Cruft detectado (NO tocar): `UIHacking` está DUPLICADO (autoload + instancia en `player.tscn/hudnscreen/UIHacking`
  — solo el autoload se usa); `door_01.tres` (`ItemData` en la puerta) casi-muerto (solo alimenta el label `[E]` del HUD V1).

### 9.6 Auditoría PROFUNDA del inventario legacy — **COMPLETADA** (análisis puro)

**Hallazgo central: tras B/C/D el inventario legacy quedó FUNCIONALMENTE INERTE en el juego real.**
- **`Inventario.agregar_item()` no tiene ningún caller que tenga éxito.** botella/sable/llave migraron;
  `mesa`/`osciloscopio` usan `Item.gd` pero con `es_recogible = false` → `_recoger()` retorna antes de llamar a `Inventario`.
  → `Inventario.items` **siempre vacío** en `movement_test`.
- **`UiInventario.visible` siempre `false`** (`_input` hibernado C4-B0, nunca se togglea) → `player.gd` líneas 35/56
  (`if UiInventario.visible: freeze`) = **ramas muertas**; `tirar_item.gd:21` = rama muerta.
- **`TirarItem` (tecla T)** = `_input` alcanzable pero `Inventario.items` vacío → `if size() > 0` siempre false → **inerte**.
- **`Catalogo`**: TODOS sus callers (`inventario.gd`, `ui_inventario.gd`, `tirar_item.gd`) son rutas legacy muertas.
- `.tres` legacy de `ItemData` **huérfanos** (0 refs) tras B/C/D: `key.tres`, `collectibles/consumables/botella.tres`,
  `collectibles/weapons/sable.tres`, `granada.tres`, `municion_9mm.tres`. Siguen referenciados: `mesa.tres`,
  `osciloscopio.tres`, `door_01.tres`.

**¿InventoryV2 reemplaza conceptualmente al inventario legacy? → SÍ**, para todo lo que el legacy realmente USABA
(pickup, store, identidad, grid, footprints rectangulares, rotación, reubicación, drop-a-mundo, datos por tipo,
datos por instancia, UI, conversión world↔inv). V2 lo hace igual o mejor (transferencias validadas, custodia XOR,
por-entidad, componente reusable, feedback de validez, zona neutra).

**Capacidades legacy NO cubiertas por V2 — y qué hacer:**
| Capacidad | Estado legacy | Decisión |
|---|---|---|
| **throw** (carga + impulso + spin, apuntado por cámara) — `tirar_item.gd` | implementado, hoy INERTE (sin items) | **B. REESCRIBIR** como capacidad `ItemThrower` separada (hermana de `ItemDropper`, NO dentro de él). Los valores `fuerza_lanzamiento`/`velocidad_angular` sirven de arranque. Deferido a su propio lote. |
| footprints NO rectangulares (`Catalogo.formas` = matrices arbitrarias) | capacidad existía, **NUNCA usada** (todas las formas eran rectángulos) | **D. DESCARTAR** salvo que aparezca un item con forma en L |
| tooltip nombre al hover | `ui_inventario._actualizar_tooltip` | **C. RESCATAR PARCIAL** — agregar a `InventoryPanel` más adelante (UX menor) |
| freeze de movimiento con inventario abierto | `player.gd` | **D. DESCARTAR** — V2 decidió explícitamente que el inventario NO inmoviliza |
| `Inventario` global (singleton) | autoload | **D. DESCARTAR** — anti-patrón; V2 es por-entidad a propósito |
| stacks (`ItemInstancia.cantidad`) | campo por defecto `1`, sin lógica | **E. DIFERIR** — feature real, tampoco existía en legacy |

**Campos `ItemData` — dueño semántico (ninguno vale la pena portar tal cual):**
`nombre` → `ItemDefinition.nombre` (ya existe); `es_recogible` → NO es dato, el *tipo de escena* lo responde (WorldItemV2 o no);
`item_id` (int) → superado por referencia directa al `.tres` + `ItemDefinition.id: StringName`;
`fuerza_lanzamiento` / `velocidad_angular` → **dominio throw** (futuro `ItemThrower` / un `ThrowProfile`), NO inventario;
`peso` → dominio *encumbrance/carga* futuro, NO inventario (además **nunca se lee**);
`municion` / `vida` / `se_puede_romper` → dominios *armas/durabilidad* futuros (además **nunca se leen**; solo se copian a `ItemInstancia._init`);
`descripcion` / `tipo` → **descartar** (nunca se leen).

**Campos `ItemInstancia` — 11 campos, de los cuales:** `data` → `ItemInstance.definition` (V2 lo tiene);
`grid_col/fila/rotacion/forma_rotada` → V2 los movió a `InventoryEntry` (separación correcta: la instancia no sabe dónde está);
`municion_actual/durabilidad_actual/equipado/bloqueado/cantidad` → **muertos** (set en `_init`, nunca leídos);
`color` (random) → leído solo por `ui_inventario` para teñir celdas = **placeholder de debug**, descartar (UI real usa iconos).
→ El `ItemInstance` mínimo de V2 (`instance_id` + `definition`) **NO es regresión**: solo tiró campos muertos.

**Blockers para retirar el inventario legacy** (todos LOW/MED; NO requieren migrar Player V1):
- **B1** `Item.gd` (mesa/osciloscopio) referencia `Inventario` (línea muerta) + `ItemData` → vaciar `Item.gd._recoger` o dar a los 2 props un script trivial.
- **B2** `player.gd` líneas 35/56 leen `UiInventario.visible` (2 ramas muertas) → borrarlas.
- **B3** `TirarItem` node en `player.tscn` + `tirar_item.gd` referencian `Inventario`/`UiInventario`/`Catalogo` → sacar el nodo; throw se reescribe aparte.
- **B4** `puerta.gd:25` lee `Inventario.items` (rama prototipo rota) → vaciar la rama o decidir la feature futura.
- **B5** `inventario.gd`/`ui_inventario.gd` se referencian entre sí y a `Catalogo` → trivial una vez B1–B4.
- **B6** 3 autoloads en `project.godot` (`Inventario`, `UiInventario`, `Catalogo`) → borrar 3 líneas tras B1–B5.
- **B7** `hud.gd`/`raycast_interaccion.gd` leen `objeto_mirado.data.nombre` (label `[E] <nombre>`) — funciona para mesa/osciloscopio/door, **roto para los WorldItemV2 migrados** (no tienen `.data`). Concern de HUD/interacción, no de inventario. Para matar `ItemData` del todo hace falta rehacer cómo el HUD obtiene el nombre. MED.
- **B8** `inventory_v1_manual_test.gd` hace `get_node_or_null("/root/UiInventario")` (defensivo, degrada bien).
- **B9** Player V1 sigue siendo la main scene — pero **NO bloquea** retirar el inventario legacy (V1 ya no lo usa funcionalmente).

---

## 10. LEGACY (SIGUE VIVO PERO INERTE — NO ELIMINAR TODAVÍA)

> **Tras B/C/D el inventario legacy no produce ningún comportamiento observable en `movement_test`** (§9.6).
> Todo lo de abajo es código alcanzable pero muerto en runtime. Retirarlo = §13.

| Elemento | Estado runtime | Reemplazo V2 |
|---|---|---|
| **`Inventario`** (Autoload, `inventario.gd`) | `items` SIEMPRE vacío (ningún caller de `agregar_item` tiene éxito). `devolver_item`/`mostrar_inventario` sin callers. | `InventoryV2` por entidad — **cubre todo lo usado** |
| **`UiInventario`** (Autoload, `ui_inventario.gd`) | `_input` HIBERNADO (C4-B0). `visible` SIEMPRE `false`. 221 líneas de UI de grilla inertes. | `InventoryPanel` + `InventoryGridView` + `InventoryManipulator` + `PlayerInventoryUI` — **cubre todo salvo tooltip** |
| **`Catalogo`** (Autoload, `catalogo.gd`) | dicts `prefabs`/`formas` por `int` (ids 1–4). TODOS los callers son rutas muertas. Refs stale a llave/botella/sable scenes. | `ItemDefinition` (`world_scene_path` + `grid_width/height`) |
| **`TirarItem`** + `tirar_item.gd` | nodo en `player.tscn/hudnscreen`. Tecla T alcanzable pero `Inventario.items` vacío → inerte. `lanzar_desde_inventario` con ruta rota. | **throw = capacidad NUEVA `ItemThrower`** (reescribir, §9.6) — distinta de `ItemDropper` |
| **`Item.gd`** | root de `mesa` / `osciloscopio` (botella/sable/llave YA migradas). `_recoger()` retorna false (no recogibles). Línea `Inventario.agregar_item` nunca se ejecuta. | `world_item.gd` para items reales; mesa/osciloscopio NO son items |
| **`ItemData`** / **`ItemInstancia`** (`class_name`) | usados por legacy + `mesa.tres`/`osciloscopio.tres`/`door_01.tres` + `puerta.@export data` + `Item.@export data`. Casi todos los campos muertos (§9.6). | `ItemDefinition` / `ItemInstance` (V2 tiró solo campos muertos) |
| **`puerta.gd`** (`door_rust_01.tscn`) | `_toggle()` lee `Inventario.items` (vacío) → chequeo de llave nunca pasa. **Rama prototipo rota.** Sistema funcional = terminal (§9.5). | NADA por ahora; feature `llave→puerta` = trabajo futuro de dominio puerta |
| **Player V1** (`player.gd`, `player.tscn`, `raycast_interaccion.gd`) | main scene. `if UiInventario.visible:` = 2 ramas muertas. **V1 ya NO usa el inventario funcionalmente.** | PlayerV2 (migración de nivel = track aparte; NO bloquea retirar el inventario legacy) |

**Huérfanos tras B/C/D (0 refs — NO borrar todavía):** `assets/data/collectibles/consumables/key.tres` +
`.../consumables/botella.tres` + `.../weapons/sable.tres` + `.../weapons/granada.tres` + `.../ammo/municion_9mm.tres`;
`levels/test_level.tscn`. **NO son items:** `mesa_standar_1`, `osciloscopio_01`. **Rota/aparte:** `granada_01` (root sin script).

`levels/movement_test.tscn` carga con 4× `ERROR: Viewport Texture must be set to use it` — **pre-existentes**, ajenos.
Tras B/C/D: los `WorldItemV2` migrados (sable + 2 llaves están en `movement_test`) son **inertes ahí** — Player V1
no tiene `InventoryReceiver`, así que `_solicitar_pickup` devuelve false. Esperado (se validan en escenas PlayerV2).

`project.godot [autoload]`: `Catalogo`, `Inventario`, `UIHacking`, `UiInventario`, `DebugDraw`. **NO tocar todavía.**
(`UIHacking` = sistema terminal FUNCIONAL, se queda. `DebugDraw` = debug, ajeno.)

---

## 11. TESTS / BASELINES (tras SUA-1.6 D, HEAD `b3e8ee5`)

Correr headless: `"$GODOT" --headless "res://scenes/test/<nombre>.tscn"`. Cada uno hace
`assert(_fallos == 0)` + `get_tree().quit(_fallos)`. (Si un `assert` falla → halt antes del `quit()` → cuelga → matar por timeout; exit 0 == todo verde.)

| Test | Chequeos | Fase |
|---|---|---|
| `player_v2_inventory_isolation_test` | **25 / 0** | C0 |
| `player_v2_pickup_c1_test` | **21 / 0** | C1 |
| `player_v2_inventory_sandbox_test` | **19 / 0** | C3 |
| `player_v2_inventory_ui_test` | **20 / 0** | C4-A |
| `player_v2_inventory_ui_toggle_test` | **31 / 0** | C4-B/C |
| `player_v2_item_dropper_test` | **24 / 0** | C5-A |
| `inventory_v1_drop_intent_test` | **62 / 0** | C5-B / C5-B2 |
| `player_v2_drop_c5c_test` | **42 / 0** | C5-C |
| `botella_v2_migration_test` | **45 / 0** | **SUA-1.6 B** — carga fría + autoaprovisionamiento + pickup/drop/re-pickup + identidad + escena real + caso "M" (escena inválida) |
| `sable_v2_migration_test` | **32 / 0** | **SUA-1.6 C** — patrón reutilizado; footprint 1×4, rotación 1×4↔4×1 |
| `llave_v2_migration_test` | **36 / 0** | **SUA-1.6 D** — patrón reutilizado; footprint 1×1, `can_rotate=false` (rotación rechazada) |

**Gate InventoryV2 (12 escenas) = 459 / 0** — conteos IDÉNTICOS a la baseline histórica (B/C/D no cambiaron ninguno):
```
inventory_panel_test 56       inventory_v1_manipulator_test 57
inventory_v1_identity_contract_test 22   inventory_v1_rotacion_offset_test 50
inventory_v1_entry_readonly_test 29      inventory_v1_activacion_test 40
inventory_v0_negatives_test 22           inventory_v1_negatives_test 65
inventory_v1_consultas_test 32           inventory_v1_reubicar_test 26
inventory_v1_operacion_reubicar_test 31  inventory_v1_vista_test 29
```
**Tripwire D8** (`inventory_v1_identity_contract_test`, 22/0): **NO modificado**. `ref_def.world_scene == def_scene0`
sigue estable — el getter devuelve `load(world_scene_path)`, que devuelve la misma `PackedScene` cacheada por `ResourceLoader`.

`inventory_v1_manual_test` / `inventory_v0_test` = manuales (no cuentan). Cero `SCRIPT ERROR`/`WARNING`/`push_error` nuevos.
(Único `push_error` esperado: el del caso "M" de `botella_v2_migration_test`, deliberado.)

Sandboxes/nivel que deben cargar exit 0: `player_v2_sandbox.tscn`, `player_v2_inventory_sandbox.tscn`,
`botella_integration.tscn`, `sable_integration.tscn`, `llave_integration.tscn`, `levels/movement_test.tscn`.

### Ciclo E2E con ASSETS REALES — VALIDADO (B / C / D)

```
<ITEM REAL> EN MUNDO  →  InventoryV2  →  <ITEM REAL> EN MUNDO  →  InventoryV2   (misma referencia ItemInstance)
```
para botella, sable y llave. En cada uno: carga fría `CACHE_MODE_IGNORE_DEEP` con **0** `Parse Error` /
`Failed loading` / `SCRIPT ERROR`; custodia XOR en cada paso; el `WorldItemV2` droppeado ES la escena real
(mesh + collider + `InteractionComponent` + `definition`); **prueba manual APROBADA** en cada fase
(rotación / reubicaciones / múltiples ciclos / `VALIDATE ok` / `COMMIT exito`).

---

## 12. DECISIONES CERRADAS

### C5 (drop)
- `ItemDropper` = capacidad hija directa del root, simétrica a `InventoryReceiver`.
- `DropPoint` `Marker3D` bajo `Body`, local `(0, 1.0, -1.2)`.
- UX de drop: arrastrar el held **fuera del anillo neutro** y soltar. Tecla `T` / impulso / `Camera3D` / anti-wall: **NO** todavía.
- `world_parent = get_tree().current_scene` (sin `world_parent_override`).
- `drop_fuera_solicitado(item_instance)` = **intención, NO éxito**.
- `drop_neutral_margin_px = 24.0` (aprobado manual; `0` = sin zona neutra).
- Puente UI→drop en `PlayerInventoryUI` (handler de 1 línea, sin lógica espacial, panel NO se cierra).

### SUA-1.6 (migración)
- **`ItemDefinition.world_scene_path: String`** = única fuente de verdad. `@export var world_scene: PackedScene` **eliminado**.
- `world_scene` = alias computado de solo lectura (compat con 19 tests). API canónica = `get_world_scene()`.
- `WorldItemV2.@export definition` + autoaprovisionamiento en `_ready()` (inyección gana). Fail-fast local en pickup.
- Hole "escena que no instancia WorldItemV2" **cerrado** (`nodo.free()` + item queda en inventario).
- Footprints de contenido: botella **1×3**, sable **1×4** (`can_rotate=true`), llave **1×1** (`can_rotate=false`).
  El legacy no entra en 4×4; se eligen por proporción física. **NO agrandar la grilla para conservar el legacy.**
- **NO hibridizar Player V1** con InventoryV2. Validar assets en escenas de integración PlayerV2 (opción C).
- `.tres` de `ItemDefinition` de producción viven en `assets/data/items_v2/`.

### Auditoría del inventario legacy (§9.6) + CIERRE — política

- El legacy es **referencia ejecutable, NO especificación**. No adaptar V2 para conservar decisiones malas.
- **InventoryV2 reemplaza CONCEPTUAL Y FUNCIONALMENTE al inventario legacy** para todo lo que el legacy usaba y
  queremos conservar (ver §13 — CIERRE FUNCIONAL).
- **throw ≠ drop.** throw = capacidad NUEVA `ItemThrower` (reescribir), hermana de `ItemDropper`, NO dentro de él.
  DEFERIDO. NO agregar `fuerza_lanzamiento` / `velocidad_angular` a `ItemDefinition` core.
- `peso`/`municion`/`vida`/`durabilidad`/`equipado` NO son responsabilidad del inventario → dominios futuros.

**POLÍTICA — legacy en paralelo (adoptada tras la auditoría):**
Un sistema legacy **puede permanecer en paralelo aunque esté inerte**. Su presencia NO obliga a eliminarlo ya.
**NO se modifica un sistema vecino solo para borrar una referencia muerta al inventario legacy.**
El inventario legacy se elimina recién cuando: (1) sus consumidores externos hayan sido auditados **dentro de
SUS dominios**; (2) sus dependencias tengan contratos nuevos estables; (3) se pueda borrar **sin adaptadores
temporales ni contaminar V2**. Se prefiere **deuda explícita/congelada** antes que generar híbridos nuevos.
→ **NO se ejecuta la secuencia SUA-1.6 E→F→G** (retiro escalonado). Queda descartada como "next inmediato".

---

## 13. InventoryV2 — FUNCIONALMENTE CERRADO ✅

**`INVENTORYV2 FUNCTIONAL CLOSURE = APPROVED`** (2026-08-30, HEAD `b3e8ee5`).

InventoryV2 se considera **conceptual Y funcionalmente completo** respecto del inventario legacy. La auditoría
profunda (§9.6) + la auditoría final de cierre lo confirmaron con 5 preguntas → **NO / NO / NO / SÍ / SÍ**:

1. ¿Capacidad REAL del inventario legacy, usada, que queramos conservar, NO cubierta por V2? → **NO**.
2. ¿Bug conocido de InventoryV2 que impida cerrarlo? → **NO** (único detalle: ghosting cosmético no-bloqueante
   del preview del manipulator con mouse rápido — aceptado).
3. ¿Dependencia INTERNA de V2/PlayerV2 hacia `Inventario`/`UiInventario`/`Catalogo`/`Item.gd`/`ItemData`/`ItemInstancia`? → **NO** (solo comentarios: `world_item.gd`, `player_inventory_ui.gd`, `sandbox_interactable.gd` — cero código).
4. ¿Los 3 assets reales migrados son independientes del legacy? → **SÍ** (`botella/sable/llave_*.tscn` → 0 refs legacy).
5. ¿Puede el desarrollo nuevo usar SOLO InventoryV2 sin agregar callers al legacy? → **SÍ** (item nuevo = nueva `.tscn` + nueva `.tres`, autocontenido).

### Qué queda registrado como CERRADO

- botella (B, `feb42f1`) · sable (C, `8dbfe5b`) · llave (D, `b3e8ee5`) — migradas a `WorldItemV2` + `ItemDefinition`.
- tests automáticos verdes: gate 459/0, 8 PlayerV2, botella 45/0, sable 32/0, llave 36/0, tripwire D8 22/0.
- pruebas manuales aprobadas en las 3 fases.
- patrón real repetido en **tres** assets sin rediseño de arquitectura.
- capacidades de inventario cubiertas: pickup · almacenamiento · identidad de instancia · grid · footprint ·
  rotación · reubicación · drop · world↔inventory · datos de tipo · datos de instancia · UI · manipulación.
- inventario legacy **INERTE** (§9.6) pero **deliberadamente conservado EN PARALELO** (política §12).
- retiro del legacy **DIFERIDO** hasta revisar sus consumidores externos por dominio (política §12).

### Backlog / DEFERIDOS (sin orden fijado — cada uno llega cuando le toque su dominio)

| Ítem | Dominio futuro |
|---|---|
| **`ItemThrower`** (throw: carga + impulso + spin, apuntado por `Camera3D`) | capacidad de PlayerV2, hermana de `ItemDropper` |
| tooltip de nombre al hover | Inventory UI (mejora UX menor, backlog opcional) |
| stacks (`cantidad`) | feature de inventario futura |
| `peso` → carga transportable | **encumbrance / carga** |
| `municion` / `municion_actual` | **armas / ammo** |
| `vida` / `durabilidad_actual` | **durabilidad** |
| `equipado` | **equipamiento** |
| feature `llave → puerta` real | **dominio puerta** (consulta el `InventoryV2` del actor por `ItemDefinition.id`) |
| limpieza `ItemData` / `Item.gd` / display-name del HUD | **revisión interacción / HUD / props** (mesa, osciloscopio) |
| eliminación final `Inventario` / `UiInventario` / `Catalogo` / `TirarItem` + autoloads + `.tres` huérfanos | retiro legacy (recién tras auditar consumidores por dominio) |
| Player V1 → PlayerV2 / migrar `movement_test.tscn` | track propio |

**Ninguno de estos es blocker del cierre de InventoryV2.** Ninguno se implementa sin instrucción explícita.

---

## 14. PROMPT DE REANUDACIÓN

> Copiar a una conversación nueva:

```
Leé docs/inventory_context_checkpoint.md completo antes de hacer nada.
Después: git status, git log --oneline -17, confirmá HEAD == b3e8ee5 y 17 commits ahead de origin/main.
Confirmá que entendés:
 - PlayerV2: inventario por instancia (C0), pickup real (C1), autoridad stateless (C2), UI TAB (C4),
   drop ItemDropper (C5-A), intención de drop con zona neutra 24px (C5-B/B2), puente UI->ItemDropper (C5-C).
 - Ciclo MUNDO<->INVENTARIO IMPLEMENTADO/CONECTADO/VALIDADO con 3 ASSETS REALES: botella (B), sable (C), llave (D).
 - ItemDefinition: world_scene_path (String) = única fuente de verdad; world_scene = alias de lectura
   compatibility-only (sin setter); API canónica get_world_scene(). NO volver a @export PackedScene (ciclo de parser).
 - WorldItemV2 autoaprovisiona su ItemInstance desde @export definition si nadie lo inyectó.
 - botella/sable/llave_*.tscn YA son WorldItemV2 + ItemDefinition; no dependen de Item.gd/ItemData/Inventario/Catalogo.
 - Baselines: gate 459/0; botella 45/0, sable 32/0, llave 36/0; tests PlayerV2 ver seccion 11; tripwire D8 22/0 sin modificar.
 - InventoryV2 = FUNCIONALMENTE CERRADO (§13, `INVENTORYV2 FUNCTIONAL CLOSURE = APPROVED`). Cubre todo lo que
   el inventario legacy usaba y queremos conservar. 5 preguntas de cierre → NO/NO/NO/SÍ/SÍ.
 - El inventario legacy (Inventario/UiInventario/Catalogo/TirarItem) quedó FUNCIONALMENTE INERTE tras B/C/D (§9.6),
   pero se CONSERVA EN PARALELO deliberadamente (política §12). NO se toca un sistema vecino solo para borrar una
   ref muerta. Retiro legacy DIFERIDO hasta auditar sus consumidores por dominio. NO ejecutar SUA-1.6 E→F→G.
 - monitor/terminal->puerta = sistema funcional real (§9.5), sin inventario. NO tocar. llave->puerta = prototipo roto.
NO hay un "next" técnico automático de inventario. Los deferidos (§13: ItemThrower, tooltip, stacks, encumbrance,
ammo, durability, equipment, llave->puerta, limpieza ItemData/HUD, retiro legacy, Player V1->PlayerV2) llegan
cada uno cuando le toque su dominio. El usuario decide qué sigue. No cambies archivos hasta que te lo pida.
```

---

## 15. VERIFICACIÓN DEL CHECKPOINT

Datos que un futuro Claude debe re-verificar leyendo el repo:
- `git rev-parse HEAD` == `b3e8ee5…` ; `git status` tracked limpio ; 17 commits sobre `origin/main`.
- `git log --oneline -3` → `b3e8ee5 SUA-1.6 D`, `8dbfe5b SUA-1.6 C`, `feb42f1 SUA-1.6 B`.
- `git show b3e8ee5 --stat` (D: `llave_comun_1.tscn`, `llave.tres`, `llave_integration.{tscn,gd,gd.uid}`, `llave_v2_migration_test.{gd,gd.uid,tscn}`).
- `scripts/player n entities/inventory_v2/item_definition.gd` — `@export_file("*.tscn") var world_scene_path`,
  `var world_scene: PackedScene:` con solo `get:`, `func get_world_scene() -> PackedScene`. **NO** `@export var world_scene: PackedScene`.
- `scripts/player n entities/inventory_v2/world_item.gd` — `@export var definition`, `_ready()` autoaprovisiona, fail-fast en `_solicitar_pickup`.
- `scenes/props/dinamic/{botella_standar_1,sable_san_martin_1,llave_comun_1}.tscn` — `script = world_item.gd`,
  `definition = ExtResource(items_v2/<x>.tres)`, SIN `Item.gd` / `ItemData` legacy.
- `assets/data/items_v2/{botella,sable,llave}.tres` — `world_scene_path` (no `world_scene`); 1×3 / 1×4 / 1×1.
- **INERCIA LEGACY (§9.6):** `grep -rn "Inventario.agregar_item" --include=*.gd` → solo `Item.gd:22`, y ese path
  no se ejecuta (mesa/osciloscopio son `es_recogible=false`). `UiInventario.visible` nunca se pone `true`.
- **CIERRE (§13):** `grep -rn "Inventario\b\|UiInventario\|Catalogo\b\|ItemData\b\|ItemInstancia" "scripts/player n entities/inventory_v2/" scripts/player_v2/`
  → **solo comentarios** (`world_item.gd:10`, `player_inventory_ui.gd:38`, `sandbox_interactable.gd:6`, `inventory_v0_test_scene.gd` comments). **Cero código.**
- Los 3 `.tscn` migrados → `grep -nE "Item\.gd|item_data|collectibles/(consumables|weapons|ammo)"` = 0.
- Los 19 arneses que leen `definition.world_scene` **NO** deben tener cambios en `git show feb42f1/8dbfe5b/b3e8ee5`.
- Correr el gate + los 8 tests PlayerV2 + `botella_v2_migration_test` (45) + `sable_v2_migration_test` (32) +
  `llave_v2_migration_test` (36) → los conteos de §11.
