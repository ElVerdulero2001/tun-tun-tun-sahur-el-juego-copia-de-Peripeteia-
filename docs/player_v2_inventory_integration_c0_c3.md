# PlayerV2 ↔ InventoryV2 — checkpoint de integración (C0–C3)

> **Qué es este documento.** Checkpoint arquitectónico del trabajo que conectó
> **PlayerV2 / InteractionV2** con el sistema de inventario nuevo
> (`scripts/player n entities/inventory_v2/`). Cubre las fases **C0 → C3** de
> **SUA-1.3**. Es una referencia de por qué existen las piezas actuales y de qué
> decisiones quedaron cerradas.
>
> **No** es el postmortem final de toda la migración de inventario: la UI (TAB /
> `InventoryPanel`), el drop de gameplay, la migración de contenido y props, y la
> eliminación de los Autoloads legacy **todavía no se hicieron** (ver §10).
>
> **Fuente de verdad = el repo actual.** Ante contradicción con documentación
> histórica, gana el código.
>
> Documentos relacionados:
> - `docs/inventory_system_v0_v1.md` — sistema de inventario V0/V1 (foto en
>   `2893a70`, **anterior** a PlayerV2). Las secciones sobre `LocalAuthority` y
>   `WorldItemV2` de ese doc están marcadas como superseded por C2 → apuntan acá.
> - `docs/inventory_context_checkpoint.md` — handoff de la deuda técnica V1
>   (untracked a propósito, puede estar desactualizado).

Commits de esta línea de trabajo:

| Commit | Fase | Qué |
|---|---|---|
| `1b9f897` | SUA-1.1 + SUA-1.2 | PlayerV2 (locomoción) + InteractionV2, aislado de Player V1 |
| `8bb5420` | **C0** | PlayerV2 posee `Inventory` / `InventoryAuthority` / `InventoryReceiver` por instancia |
| `2d22cd5` | **C1** | routing real de pickup: `interaction.actor → InventoryReceiver → LocalAuthority → InventoryV2` |
| `4d05e4c` | **C2** | `LocalAuthority` sin estado de routing; `WorldItemV2` neutral; APIs vestigiales eliminadas |
| `61eba68` | **C3** | integración end-to-end validada con raycast + input reales en un sandbox |

---

## 1. Motivación

El sistema de inventario legacy guardaba el estado en un **Autoload global**
(`Inventario.items`). Un único inventario para todo el proceso. Esto impide:

- que dos entidades (dos jugadores, un jugador y un NPC, un cofre) tengan
  inventarios distintos sin contaminarse;
- razonar sobre **ownership**: "¿de quién es este item?" no tiene respuesta si el
  inventario es global;
- probar aislamiento por instancia.

El objetivo de C0–C3 fue **integrar el inventario nuevo (per-entidad) con
PlayerV2** y dejar la costura lista para retirar el legacy progresivamente, **sin
introducir un singleton nuevo** que reemplace al viejo y **sin estado global
mutable**.

Principios que se mantuvieron (vienen de los chats *"Análisis de dependencias
player.tscn"* y *"Análisis de inventario legacy"*):

- PlayerV2 es la **identidad lógica** de la entidad; `Body` es su autoridad
  física.
- Cada sistema es dueño de las reglas de **su** dominio (ver §11).
- Dependencias explícitas, contratos chicos.
- Nada de Service Locator, EventBus global, Autoloads para estado de entidad,
  `get_first_node_in_group` como sustituto de ownership, ni rutas rígidas entre
  árboles.

---

## 2. Arquitectura final (C3)

Árbol de `scenes/player_v2/player_v2.tscn`:

```
PlayerV2 (Node3D)                       ← identidad lógica / actor de interacción; SIN script
├── Inventory            [InventoryV2]        ← estado de inventario de ESTA entidad
├── InventoryAuthority   [LocalAuthority]     ← frontera de autoridad de ESTA entidad
├── InventoryReceiver    [InventoryReceiver]  ← capacidad "puedo recibir un WorldItem"
│         inventory  = ../Inventory           (@export, node_paths en el .tscn)
│         authority  = ../InventoryAuthority  (@export, node_paths en el .tscn)
└── Body (CharacterBody3D)  [player_v2.gd]    ← autoridad física y espacial
    ├── CollisionShape3D
    ├── View (Node3D)
    │   └── Camera3D
    └── Interaction (Node)  [interaction.gd = InteractionV2]
              actor         = ../..            → PlayerV2  (NO Body)
              physics_body  = ..               → Body
              aim_source    = ../View/Camera3D → Camera3D
```

| Nodo | Rol | Base |
|---|---|---|
| **PlayerV2** | Identidad lógica de la entidad. Es lo que viaja como `Interaction.actor`. No tiene script coordinador. | `Node3D` |
| **Body** | Autoridad física: `velocity`, `move_and_slide()`, yaw, colisión. No conoce el inventario. | `CharacterBody3D` |
| **Inventory** | Estado de inventario de la entidad: lista privada `_entries`. **No es Autoload** (INV-01). | `InventoryV2 : Node` |
| **InventoryAuthority** | Frontera de autoridad: único punto que corre `TransferOperation.validate()/commit()` (INV-08). **Sin estado de routing** (C2). | `LocalAuthority : Node` |
| **InventoryReceiver** | Capacidad de dominio: "esta entidad puede recibir un `WorldItemV2` en un `InventoryV2` concreto". Traduce identidad-de-actor → `InventoryV2` concreto. | `InventoryReceiver : Node` |
| **Interaction** | InteractionV2: query física propia por frame, resuelve el `InteractionComponent` apuntado, entrega `Interaction(actor, &"usar")` al pulsar `"interactuar"`. | `Node` |

**Decisión de topología:** una `LocalAuthority` **por entidad** (1 PlayerV2 → 1
`Inventory` → 1 `InventoryAuthority` → 1 `InventoryReceiver`). No se considera
"autoridad compartida vs per-entidad" una pregunta abierta salvo que aparezca una
razón concreta.

---

## 3. Flujo completo de pickup (C1/C2, validado en C3)

```
Camera3D  (aim_source)
   │  InteractionV2._physics_process: raycast propio
   │    origen = Camera3D.global_position
   │    dir    = -Camera3D.global_transform.basis.z
   │    largo  = INTERACTION_RANGE (2.5 m)
   │    mask   = interaction_ray_mask (3 = layer 1 oclusores + layer 2 interactuables)
   │    exclude = [Body.get_rid()]
   │    → hit MÁS CERCANO (oclusión real; sin segunda query "para buscar detrás")
   ▼
hit.collider  == un WorldItemV2 (RigidBody3D, layer 2)
   │  InteractionV2._resolver_componente: primer InteractionComponent entre los
   │  HIJOS DIRECTOS del collider
   ▼
InteractionComponent  (hijo directo del WorldItemV2)
   │  al pulsar "interactuar":  InteractionV2.try_interact()
   │    → Interaction.new(actor = PlayerV2, &"usar")
   │    → InteractionComponent.recibir_interaccion(interaction)
   ▼
WorldItemV2._on_interact(interaction)          [contrato de InteractionComponent]
   │  match &"usar": return _solicitar_pickup(interaction.actor)
   │
   │  _resolver_receiver(actor): primer InventoryReceiver entre los HIJOS
   │  DIRECTOS de interaction.actor (== PlayerV2)
   │    - actor == null            → return false
   │    - sin InventoryReceiver    → return false
   ▼
InventoryReceiver.recibir_pickup(world_item)
   │  return authority.solicitar_pickup(world_item, inventory)   ← inventario EXPLÍCITO
   ▼
LocalAuthority.solicitar_pickup(world_item, inventory)           [INV-08]
   │  op = TransferOperation.crear_mundo_a_inventario(world_item, inventory)
   │  op.validate()   → _validar_mundo_a_inventario()   (no muta; si falla, nada cambia)
   │  op.commit()     → _commit_mundo_a_inventario():
   │                      entry = InventoryEntry.new(item_instance, pos, rotated)
   │                      inventory._agregar_entry(entry)  --emit--> contenido_cambiado
   │                      world_item.queue_free()
   ▼
InventoryV2._entries   (el ItemInstance ahora está bajo custodia de ESTE Inventory)
```

Nadie en este camino llama `WorldItemV2._on_interact` / `recibir_pickup` /
`solicitar_pickup` "a mano": el disparador real es mirar el item y pulsar la
acción `"interactuar"` (E). InteractionV2 no fue adaptado al inventario — el
`WorldItemV2` se adapta al contrato existente de InteractionV2
(`InteractionComponent` como hijo directo del collider).

**Firmas actuales (repo):**

```gdscript
# world_item.gd
func _on_interact(interaction: Interaction) -> Variant
func _solicitar_pickup(actor: Node) -> bool
func _resolver_receiver(actor: Node) -> InventoryReceiver

# inventory_receiver.gd
@export var inventory: InventoryV2
@export var authority: LocalAuthority
func recibir_pickup(world_item: WorldItemV2) -> bool      # → authority.solicitar_pickup(world_item, inventory)

# local_authority.gd
func solicitar_pickup(world_item: WorldItemV2, inventory: InventoryV2) -> bool
func solicitar_devolucion(item_instance: ItemInstance, inventory: InventoryV2, parent: Node3D, position: Vector3) -> WorldItemV2
func solicitar_reubicacion(item_instance: ItemInstance, inventory: InventoryV2, nueva_pos: Vector2i, nuevo_rotated: bool) -> bool
```

---

## 4. Decisiones arquitectónicas cerradas

| # | Decisión | Dónde se ve en el código |
|---|---|---|
| 1 | **`interaction.actor` es PlayerV2 (el `Node3D` raíz), NO `Body`.** El actor de una interacción representa la entidad que actúa, no su cuerpo físico. | `player_v2.tscn`: `Interaction.actor = NodePath("../..")` |
| 2 | **`InventoryV2` pertenece a una instancia de entidad.** No hay `InventoryManager` global; el estado cuelga de la entidad. | `inventory.gd` INV-01; `player_v2.tscn` nodo `Inventory` |
| 3 | **`Body` no conoce `Inventory`.** `player_v2.gd` no referencia inventario, autoridad ni receiver. | `player_v2.gd` |
| 4 | **El nodo raíz `PlayerV2` sigue sin script.** No hay coordinador que "sepa todo del Player". El cableado es por `@export` con `node_paths` en la escena. | `player_v2.tscn` (nodo `PlayerV2` sin `script =`) |
| 5 | **`InventoryReceiver` es hijo DIRECTO del actor.** Análogo estructural a `InteractionComponent` como hijo directo del collider. | `player_v2.tscn`; `world_item.gd::_resolver_receiver` |
| 6 | **`WorldItemV2` busca `InventoryReceiver` SOLO entre los hijos directos de `interaction.actor`.** Sin walk por ancestros, sin `get_node` por nombre, sin grupos. | `world_item.gd::_resolver_receiver` |
| 7 | **`LocalAuthority` no guarda estado de routing.** No tiene `_inventory_receptor`. Su único estado es `_log_habilitado`. | `local_authority.gd` (C2) |
| 8 | **Cada operación de autoridad recibe su `InventoryV2` explícitamente por parámetro.** Las tres (`solicitar_pickup` / `solicitar_devolucion` / `solicitar_reubicacion`) son uniformes. | `local_authority.gd` |
| 9 | **`WorldItemV2` es neutral respecto de autoridad.** No guarda actor, inventario ni `LocalAuthority`. Ver §8. | `world_item.gd` (C2: sin `_authority` / `setup()`) |
| 10 | No Service Locator, no EventBus global, no `get_first_node_in_group` para ownership, no singleton para estado de inventario de entidad. | (ausencia deliberada en todo `inventory_v2/` + `player_v2/`) |

---

## 5. Evolución C0 → C3

### C0 — `8bb5420` — ownership por instancia (estructural, sin gameplay)

- Se agregaron a `player_v2.tscn` los nodos `Inventory` (`InventoryV2`),
  `InventoryAuthority` (`LocalAuthority`) e `InventoryReceiver` (clase nueva),
  cableados por `@export`.
- `InventoryReceiver` en C0 era **inerte**: solo validaba sus dos dependencias en
  `_ready()`; `recibir_pickup()` existía como contrato pero devolvía `false`.
- Test nuevo `player_v2_inventory_isolation_test`: dos `player_v2.tscn`
  instanciados → `A.Inventory != B.Inventory`, `@export` de cada receiver apunta
  solo a su entidad, una operación válida sobre `InventoryA` deja `InventoryB`
  byte-idéntico.

### C1 — `2d22cd5` — routing por `interaction.actor`

- `WorldItemV2._on_interact` pasa `interaction.actor` a
  `_solicitar_pickup(actor)`; nuevo `_resolver_receiver(actor)`.
- `InventoryReceiver` pasa a ser el **bridge funcional**: delega en su
  `LocalAuthority`.
- El pre-binding de autoridad en el `WorldItem` (`_authority` / `setup()`) dejó de
  ser la ruta de pickup — quedó vestigial (se elimina en C2).
- Los 13 arneses de test que sembraban con
  `authority.set_inventory_receptor(inv)` + `wi.setup(authority)` +
  `Interaction.new(self, ...)` se migraron a un actor de prueba con
  `InventoryReceiver` hijo directo (`scenes/test/helpers/inventory_test_actor.gd`,
  TEST-ONLY). El gate quedó **459/0 idéntico**.
- Test nuevo `player_v2_pickup_c1_test` (21/0): dos PlayerV2 + un `WorldItemV2`;
  pickup por `_on_interact` real, A recibe, B intacto, custodia XOR, actor sin
  receiver → `false`, `actor == null` → `false`.

### C2 — `4d05e4c` — `LocalAuthority` stateless, `WorldItemV2` neutral

Eliminados (cero callers runtime en todo el repo):

- `LocalAuthority._inventory_receptor`
- `LocalAuthority.set_inventory_receptor()`
- `LocalAuthority._encontrar_inventory_receptor()`
- `WorldItemV2._authority`
- `WorldItemV2.setup()`
- `LocalAuthority.solicitar_devolucion()::nuevo_world_item.setup(self)` (el
  `WorldItemV2` de una devolución ya nace neutral)

`solicitar_pickup` pasó de `(world_item)` a `(world_item, inventory)`.
`solicitar_devolucion` / `solicitar_reubicacion` **sin cambio de firma** (ya
recibían el inventario). `TransferOperation` **intacto**. Cambio neto: **−47
líneas**. Único arné tocado: `inventory_v0_test_scene.gd` (borró 2 llamadas
obsoletas).

### C3 — `61eba68` — integración end-to-end (aditivo puro)

- `scenes/player_v2/player_v2_inventory_sandbox.tscn` +
  `scripts/player_v2/player_v2_inventory_sandbox.gd` (**DEBUG-ONLY**).
- 3 instancias de `scenes/test/test_item_v0.tscn` (`WorldItemV2` real,
  `collision_layer = 2`), `freeze = true`, bajo un nodo `Items`.
- El coordinador del sandbox asigna un `ItemInstance` a cada `WorldItemV2` en
  `_ready()` y muestra un readout: target de InteractionV2 + cantidad de entries +
  `instance_id`s.
- `ParedOclusora` (pared) + `ItemOculto` detrás; `CajaMuda` (geometría sin
  `InteractionComponent`). Todos `collision_layer = 1`.
- Test nuevo `player_v2_inventory_sandbox_test` (19/0): **estructural** — instancia
  el sandbox y verifica que las piezas están conectadas (no simula raycast/input).
- **Validado a mano** (input + mouse + raycast reales): detección, E → pickup, el
  item desaparece, `entries` incrementa, rango (2.5 m), oclusión por pared, la
  geometría no interactuable bloquea, segundo E sobre el vacío no duplica ni
  genera errores. Log: 3× `SOLICITUD → VALIDATE ok → COMMIT exito=true`.

---

## 6. Garantías conservadas

C0–C3 **no** modificaron `TransferOperation` ni los mutadores de `InventoryV2`.
Se conservan todas las garantías de V0/V1:

- **`request → validate → commit`**: `TransferOperation` se crea, valida y recién
  entonces commitea. Si `validate()` falla, `commit()` no corre y **nada cambia**
  (modelo byte-idéntico, sin emitir `contenido_cambiado`).
- **Atomicidad**: `commit()` aplica todos los cambios de ambos extremos en un solo
  paso; nunca queda un estado intermedio.
- **Custodia XOR mundo/inventario**: un `ItemInstance` está `World=1/Inv=0` **XOR**
  `World=0/Inv=1`. Nunca `1/1`, nunca `0/0` (INV-16).
- **Identidad de `ItemInstance` por referencia**: la identidad lógica ES la
  referencia del objeto; `instance_id` es solo aid de logs/tests (INV-02, INV-06,
  C-D8.x).
- **No duplicación / no pérdida**: pickup mueve la custodia (no copia); un pickup
  fallido deja el `WorldItemV2` intacto en el mundo.
- **Aislamiento entre entidades**: agregar/recoger con `PlayerV2_A` no toca el
  `InventoryV2` de `PlayerV2_B` (demostrado en C0 y C1).

---

## 7. Tests / evidencia

| Test | Chequeos | Qué cubre |
|---|---|---|
| `player_v2_inventory_isolation_test` (**C0**) | **25 / 0** | nodos de inventario por instancia; `@export` de cada receiver a su propia entidad; operación válida sobre A no toca B |
| `player_v2_pickup_c1_test` (**C1**) | **21 / 0** | routing real `actor → InventoryReceiver → LocalAuthority → InventoryV2`; A recibe / B intacto; custodia XOR; actor sin receiver → `false`; `actor == null` → `false` |
| `player_v2_inventory_sandbox_test` (**C3**) | **19 / 0** | integración estructural del sandbox real: cada `WorldItemV2` con `InteractionComponent` hijo directo + `ItemInstance` válido; PlayerV2 con `InventoryReceiver` bien cableado |
| Gate InventoryV2 (12 escenas) | **459 / 0** | comportamiento V0/V1 sin cambios (conteos idénticos a la baseline `2893a70`) |

- Todo headless, Godot 4.6.3, `--headless`. Cero `SCRIPT ERROR` / `ERROR` /
  `WARNING` / `push_error`.
- **C3 fue validado manualmente** con input + mouse + raycast reales (ver §5, C3).
- Cómo correr el gate rápido: ver `docs/inventory_system_v0_v1.md §14`.

---

## 8. `WorldItemV2` neutral (importante para drop y multi-entidad)

Un `WorldItemV2` **no pertenece** a la autoridad ni a la entidad que lo creó o lo
tiró. Mientras está en el mundo:

- **no tiene dueño de inventario**;
- no guarda `actor`, `inventory` ni `LocalAuthority` (C2 borró `_authority` /
  `setup()`);
- su único estado es `item_instance` (el objeto de identidad lógica).

Su destino se decide **en el momento de la interacción**:
`interaction.actor → InventoryReceiver → InventoryV2 de ese actor`.

Consecuencias:

- **Drop (futuro):** un item soltado por A al mundo puede ser recogido después por
  B sin ningún re-cableado. `LocalAuthority.solicitar_devolucion()` ya devuelve un
  `WorldItemV2` neutral.
- **Multi-entidad:** dos PlayerV2 pueden mirar el mismo `WorldItemV2`; cada uno lo
  recoge en **su** inventario porque el receiver se resuelve desde **su**
  `interaction.actor`.
- **Items presentes en la escena al cargar** (spawneados en el `.tscn`): no
  necesitan setup — se les asigna `item_instance` (en el sandbox lo hace el
  coordinador; en gameplay real será responsabilidad de quien puebla el nivel) y
  ya son recogibles.

---

## 9. Estado del legacy (sigue activo)

**Siguen cargados** (`project.godot` `[autoload]`), **sin tocar**:

- `Inventario` — `scripts/player n entities/inventory/inventario.gd` — estado
  global `items: Array[ItemInstancia]`.
- `UiInventario` — `scenes/components/ui_inventario.tscn` — overlay legacy;
  captura la acción `toggle_inventario` **sin condición**.
- `Catalogo` — diccionarios `prefabs` / `formas` por `int` id.

El flujo nuevo (C3) **no depende de ninguno de ellos**:
`InteractionV2 → WorldItemV2 → InventoryReceiver → LocalAuthority → InventoryV2`
no toca `Inventario`, `UiInventario` ni `Catalogo`.

**Convivencia conocida:** en el sandbox de PlayerV2, pulsar **TAB** todavía abre
el overlay de `UiInventario` legacy (el Autoload sigue vivo y su `_input` captura
`toggle_inventario`). No se usa en C3. La acción `"interactuar"` (E) no se ve
afectada. **El legacy NO está eliminado** — esa es una fase posterior (§10).

Consumidores runtime del legacy que siguen vivos (para referencia de la migración
futura): `scripts/player n entities/Item.gd` (props → `Inventario.agregar_item`),
`scripts/enviroment/puerta.gd` (lee `Inventario.items` para llaves),
`scripts/player n entities/inventory/tirar_item.gd` (drop de Player V1),
`scripts/player n entities/movement/player.gd` (Player V1: chequea
`UiInventario.visible`).

---

## 10. Próxima etapa — trabajo NO hecho todavía

- **`InventoryPanel` dentro de PlayerV2** — UI del inventario V2 conectada al
  `InventoryV2` de la entidad (`InventoryPanel.setup(inventory, authority)` ya
  existe y recibe el modelo por parámetro).
- **TAB V2** — abrir/cerrar el panel del PlayerV2; ownership del input de UI
  (hoy `UiInventario` legacy se queda con `toggle_inventario`).
- **Drop de gameplay** — un disparador explícito
  `InventoryV2 del actor → solicitar drop → WorldItemV2` (el tipo de operación
  `INVENTARIO_A_MUNDO` ya existe en `TransferOperation`; falta el disparador con
  dueño de dominio claro).
- **Migración `ItemData → ItemDefinition`** — los `.tres` de
  `assets/data/collectibles/**` son `ItemData` (legacy). El sistema nuevo solo
  tiene 2 `.tres` de `ItemDefinition` de test.
- **Migración de props reales** — `llave_comun_1`, `botella_standar_1`,
  `sable_san_martin_1`, `osciloscopio_01`, `mesa_standar_1` usan `Item.gd`.
- **Puertas / llaves** — `puerta.gd` consulta `Inventario.items`.
- **Sustitución de Player V1** donde corresponda (la escena principal
  `levels/movement_test.tscn` usa Player V1).
- **Eliminar el Autoload `Inventario`** — solo cuando ningún runtime real dependa
  de él.
- **Eliminar `UiInventario` legacy** — si queda sin consumidores.
- **Decidir sobre `Catalogo`** según su responsabilidad (conocimiento estático
  compartido ≠ estado mutable de entidad; su globalidad puede ser correcta).

Ninguno de estos ítems es parte de C0–C3.

---

## 11. Principio arquitectónico general

> **Cada sistema es dueño de las reglas que definen su dominio.
> Compartimos infraestructura cuando conviene; no compartimos significado.**

Cómo se aplica en esta costura:

| Sistema | De qué es dueño |
|---|---|
| **InteractionV2** (`interaction.gd`) | Qué significa **interactuable**: query física, rango, oclusión, resolución del `InteractionComponent`. |
| **InventoryReceiver** | Qué significa que **una entidad puede recibir un item**: traduce identidad-de-actor → `InventoryV2` concreto de esa entidad. |
| **LocalAuthority** | **Autorizar** operaciones: es el único que corre `TransferOperation.validate()/commit()`. No sabe de gameplay, targeting ni red. |
| **InventoryV2** | **Poseer estado**: la lista de entries y su geometría derivada. |
| **TransferOperation** | **Ejecutar** la transferencia atómica (`request → validate → commit`). No sabe quién tiene permiso. |
| **WorldItemV2** | Ser la **carcasa física temporal** de un `ItemInstance` en el mundo. No decide nada más allá de "pedir pickup". |

Infraestructura compartida: la clase `Interaction` (actor + acción + resultado) y
el contrato `InteractionComponent._on_interact`. Significado compartido: **ninguno**
— ni InteractionV2 conoce el inventario, ni `WorldItemV2` conoce `PlayerV2` /
`Body` / `LocalAuthority`.

---

## 12. Referencia rápida de archivos

Producción (`scripts/player n entities/inventory_v2/`):

| Archivo | Clase | Rol |
|---|---|---|
| `inventory.gd` | `InventoryV2 : Node` | estado (`_entries`), consultas read-only, mutadores exclusivos de `TransferOperation` |
| `local_authority.gd` | `LocalAuthority : Node` | frontera de autoridad, stateless (C2) |
| `inventory_receiver.gd` | `InventoryReceiver : Node` | bridge actor → `InventoryV2` concreto (C0/C1/C2) |
| `world_item.gd` | `WorldItemV2 : RigidBody3D` | carcasa física, neutral (C2) |
| `transfer_operation.gd` | `TransferOperation : RefCounted` | transferencia atómica — **intacto en C0–C3** |
| `item_definition.gd` / `item_instance.gd` / `inventory_entry.gd` | — | modelo — **intacto en C0–C3** |
| `inventory_grid_view.gd` / `inventory_manipulator.gd` / `inventory_panel.gd` | — | UI V1 — **intacto en C0–C3, todavía no integrada con PlayerV2** |

Producción (`scripts/player_v2/`): `player_v2.gd` (locomoción), `interaction.gd`
(InteractionV2) — **intactos en C0–C3**.

Sandboxes / arneses:

| Archivo | Qué |
|---|---|
| `scenes/player_v2/player_v2_sandbox.tscn` | referencia de InteractionV2 (SUA-1.2) — sin inventario |
| `scenes/player_v2/player_v2_inventory_sandbox.tscn` + `scripts/player_v2/player_v2_inventory_sandbox.gd` | **C3** — integración end-to-end, DEBUG-ONLY |
| `scenes/test/player_v2_inventory_{isolation,pickup_c1,sandbox}_test.*` | tests C0 / C1 / C3 |
| `scenes/test/helpers/inventory_test_actor.gd` | TEST-ONLY — actor con `InventoryReceiver` hijo, reemplaza el par pre-C1 en los arneses del gate |
| `scripts/player n entities/inventory_v2/inventory_v0_test_scene.gd` + `scenes/test/inventory_v0_test.tscn` | arné manual V0 (raycast + input); migrado en C1/C2 |
