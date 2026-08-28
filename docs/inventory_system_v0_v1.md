# Inventory System — V0 + V1

> Documentación técnica del sistema de inventario `scripts/player n entities/inventory_v2/`.
> Describe **lo que existe hasta HEAD `29adfa3`** (V0 + V1 + saldo de deuda técnica Batch A/B/B.2). No describe planes de V2.
>
> Baseline:
> - **V0** — `1505ed514378c58d420b20f9e145c0c5c26b98da` — *"Inventory V0: sistema mundo<->inventario + arnes de pruebas"* (2026-08-27)
> - **V1** — `e2e406da2f209489af637366d956882a28ff7e90` — *"Inventory V1: manipulacion de la grilla (UI + mover/rotar) sobre InventoryV2"* (2026-08-27)
> - **Deuda técnica** — `7463866` (Batch A) → `43fc2f4` (Batch B, D1) → `29adfa3` (Batch B.2, D8). Ver sección 2 y sección 17.
> - Este `.md` se creó en `2871f87`, que es **anterior** a Batch A. V2 no iniciado.

---

## 1. Propósito del sistema

### Qué problema resuelve

Permitir que un objeto del juego (un `ItemInstance`) exista **o bien en el mundo 3D** (como cuerpo físico recogible) **o bien dentro de un inventario de grilla**, y pueda pasar de un contexto al otro **sin perder su identidad lógica**, con todas las transiciones validadas y atómicas.

- **V0** implementó el ciclo *Mundo → Inventario → Mundo* (pickup y devolución), con colocación automática (first-fit) en la grilla.
- **V1** hizo *manipulable por el jugador* el contenido de un `InventoryV2` ya poblado: UI visual de la grilla, agarrar un ítem, moverlo a otra celda, rotarlo si su definición lo permite, con rechazo limpio de posiciones inválidas.

### Concepto de custodia World / Inventory

En todo momento un `ItemInstance` está bajo **exactamente una** custodia:

```
World = 1  /  Inventory = 0        (está en el mundo como WorldItemV2)
        XOR
World = 0  /  Inventory = 1        (está colocado en un InventoryV2)
```

Nunca `1/1` (doble custodia) ni `0/0` (item perdido). Ver sección 5.

### Por qué `ItemDefinition`, `ItemInstance` e `InventoryEntry` están separados

Tres cosas distintas que cambian a ritmos distintos:

| Clase | Qué es | Analogía | Cambia cuando… |
|---|---|---|---|
| `ItemDefinition` | El **tipo** de objeto | "AK-74" en abstracto | nunca durante la partida (es un `Resource` `.tres`) |
| `ItemInstance` | **Esta copia concreta** | "esta AK-74 con 17 balas" | su identidad no cambia nunca; su estado interno (a futuro) sí |
| `InventoryEntry` | Dónde y cómo está colocada **esta copia en ESTE inventario** | la posición y rotación en la grilla | cada vez que se mueve/rota dentro del inventario |

Las coordenadas de grilla **no** viven en `ItemInstance`: solo tienen sentido mientras la instancia está en un inventario, así que viven en `InventoryEntry`. El mismo `ItemInstance` que está en el mundo no tiene `position` ni `rotated`.

### Por qué `InventoryV2` es componente-nodo y no Autoload (INV-01)

`InventoryV2 extends Node` y se agrega como **hijo de cualquier entidad** que necesite guardar items (jugador, NPC, caja, vehículo…), igual que `MovementController` o `TraversalController` son hijos de `Player`.

No existe un `InventoryManager` global. El estado de cada inventario vive en su propio nodo, colgado de la entidad dueña. Un mundo puede tener N inventarios independientes al mismo tiempo.

### Compatibilidad con autoridades futuras / multiplayer

`LocalAuthority` existe como **frontera de autoridad explícita** (INV-08): es el único que invoca `TransferOperation.validate()/commit()`. Todo componente que quiera mover un ítem le **solicita** a la autoridad; nunca ejecuta la operación por su cuenta.

El objetivo declarado (en los comentarios de `local_authority.gd`) es que **el día de mañana** una autoridad remota (servidor) pueda ocupar ese mismo rol sin reescribir `InventoryV2`, `WorldItemV2` ni `TransferOperation`.

**En HEAD no hay nada de red.** `LocalAuthority` es deliberadamente el nodo más "tonto" posible, local, sin transporte. La compatibilidad con multiplayer es una *intención de diseño*, no una capacidad existente.

---

## 2. Estado por versiones

### V0 — commit `1505ed5`

Introdujo exactamente:

| Pieza | Qué es |
|---|---|
| `ItemDefinition` (`Resource`) | tipo de ítem: `id`, `nombre`, `world_scene`, `grid_width`, `grid_height`, `can_rotate` |
| `ItemInstance` (`RefCounted`) | copia concreta: `instance_id` (autoincremental estático), `definition` |
| `InventoryEntry` (`RefCounted`) | `item_instance` + `position: Vector2i` + `rotated: bool`, con `get_footprint()` |
| `InventoryV2` (`Node`) | componente de inventario, grilla `grid_width × grid_height` (default 4×4), lista privada `_entries` |
| `TransferOperation` (`RefCounted`) | contrato `request → validate() → commit()` atómico; tipos `MUNDO_A_INVENTARIO`, `INVENTARIO_A_MUNDO` |
| `LocalAuthority` (`Node`) | frontera de autoridad; `solicitar_pickup()`, `solicitar_devolucion()` |
| `WorldItemV2` (`RigidBody3D`) | carcasa física temporal de un `ItemInstance` en el mundo |
| **Flujo World → Inventory** | `WorldItemV2._on_interact(&"usar")` → `LocalAuthority.solicitar_pickup()` → `TransferOperation` (`MUNDO_A_INVENTARIO`) → validate → commit (agrega entry, `queue_free()` del world item) |
| **Flujo Inventory → World** | `LocalAuthority.solicitar_devolucion()` → `TransferOperation` (`INVENTARIO_A_MUNDO`) → validate → commit (instancia `world_scene`, `add_child`, quita la entry) |
| **Auto-placement** | `InventoryV2.find_valid_placement(definition)` — first-fit: barre columnas/filas, prueba sin rotar y luego rotado si `can_rotate`; devuelve la primera posición libre o `null` |
| **Custodia** | mantenida por la atomicidad del commit (ver sección 5) |
| **request → validate → commit** | si `validate()` falla, `commit()` no se llama y NADA cambia |

Arnés V0: `inventory_v0_test.tscn` (manual, raycast) + `inventory_v0_negatives_test.tscn` (automático, 22 chequeos).

### V1 — commit `e2e406d`

Agregó exactamente:

| Pieza | Archivo | Detalle |
|---|---|---|
| Consultas de grilla read-only | `inventory.gd` | `entry_en_celda(celda)`, `celdas_ocupadas_por(entry)` |
| `posicion_valida(item_instance, pos, rotated, excluir_item)` | `inventory.gd` | límites + solapamiento, ignorando la entry de `excluir_item` (el item que se mueve). **No** chequea `can_rotate`. (El 4º param se llamaba `excluir: InventoryEntry` en `e2e406d`; renombrado a `excluir_item: ItemInstance` en `43fc2f4`.) |
| `_reubicar_entry(item_instance, nueva_pos, nuevo_rotated)` | `inventory.gd` | tercer mutador exclusivo; muta la entry **in-place** |
| `signal contenido_cambiado` | `inventory.gd` | emitido por los 3 mutadores cuando efectivamente mutan |
| `Tipo.REUBICAR_EN_INVENTARIO` | `transfer_operation.gd` | tercer tipo de operación + `crear_reubicar` / `_validar_reubicar` / `_commit_reubicar` / `_buscar_entry` |
| `solicitar_reubicacion(...)` | `local_authority.gd` | mismo patrón que `solicitar_pickup` |
| `InventoryGridView` (`Control`) | `inventory_grid_view.gd` | vista **pura read-only** de un `InventoryV2` |
| `InventoryManipulator` (`Control`) | `inventory_manipulator.gd` | máquina de estados: selección / held / preview / ghost / rotación tentativa / drop / cancel |
| Held / preview / ghost | `inventory_manipulator.gd` | el ghost lo dibuja el manipulator en su propio `_draw()`; el preview **no** toca el modelo |
| Rotación tentativa | `inventory_manipulator.gd` | `_rotacion_tentativa` local; `entry.rotated` real solo cambia en el commit |
| Gate abrir/cerrar | `inventory_manipulator.gd` | `_activo` + `activar()` / `desactivar()` + `set_process_unhandled_input()` |
| Fix del punto de agarre al rotar | `inventory_manipulator.gd` | `_agarre_rel_normal` (frame canónico) + `_rel_normal_a_rotada` / `_rel_rotada_a_normal` (ver sección 11) |

Los caminos V0 `MUNDO_A_INVENTARIO` / `INVENTARIO_A_MUNDO` **no cambiaron de comportamiento**: en `transfer_operation.gd` solo se agregó un `match` arm por método y variables de contexto nuevas.

Arnés V1: 8 tests automáticos (`consultas`, `reubicar`, `operacion_reubicar`, `vista`, `manipulator`, `rotacion_offset`, `activacion`, `negatives`) + `inventory_v1_manual_test.tscn` (manual).

### Deuda técnica saldada tras V1

Orden de commits (del más viejo al más nuevo): `e2e406d` (V1) → `2871f87` (**este documento**, primera foto de V0+V1) → `7463866` (Batch A) → `43fc2f4` (Batch B) → `29adfa3` (Batch B.2). Es decir, **la primera versión del doc es ANTERIOR a Batch A**; este documento se actualiza ahora para reflejar hasta `29adfa3`.

| Commit | Batch | Qué cambió |
|---|---|---|
| `7463866` | **A** | Solo comentarios `##` en `inventory_v2/*.gd`: corrige D3 (método inexistente citado) y D7 (referencias a un doc no versionado → apuntan acá), aclara D2/D6. Cero comportamiento. |
| `43fc2f4` | **B** | **D1 PAGADA** por barrera *estructural*: `InventoryV2` conserva las `InventoryEntry` vivas en `_entries`; `get_entries()` y `entry_en_celda()` devuelven **snapshots detached** (`InventoryEntry.snapshot()`). Mutar una snapshot no toca el modelo. `posicion_valida` excluye por `ItemInstance` (param `excluir_item`). INV-09 "misma `InventoryEntry`" pasó a invariante **interna** (white-box). Test nuevo `inventory_v1_entry_readonly_test` (29). |
| `29adfa3` | **B.2** | **D8** (identidad `ItemInstance`/`ItemDefinition` mutable desde una referencia viva) registrada como **LIMITACIÓN DELIBERADA** + contrato explícito C-D8.1..4 en comentarios + tripwire `inventory_v1_identity_contract_test` (22). `InventoryGridView.layout_entries()` dejó de exponer `ItemInstance`. |

---

## 3. Arquitectura actual

Todos los archivos de producción están en `scripts/player n entities/inventory_v2/`.
(`inventory_v0_test_scene.gd` también vive ahí pero es **arnés de prueba**, no producción — ver sección 14.)

### `item_definition.gd` — `class_name ItemDefinition extends Resource`
- **Responsabilidad:** describir el *tipo* de objeto. Inmutable en partida (INV-02).
- **Campos** (`@export`): `id: StringName`, `nombre: String` (solo logs/debug), `world_scene: PackedScene`, `grid_width: int = 1`, `grid_height: int = 1`, `can_rotate: bool = true` (INV-04).
- **Puede leer / mutar:** es un dato pasivo; no lee ni muta nada. **RUNTIME-INMUTABLE (C-D8.2):** una vez cargado del `.tres` (o construido), ningún consumidor debe escribir sus campos — lo comparten todas las instancias de ese tipo y suele estar respaldado por un `.tres` en disco. Auditoría Batch B.2: 0 mutaciones runtime en el repo. GDScript no lo impide; es limitación deliberada (sección 17, D8).
- **NO debería:** contener estado por-instancia (balas, durabilidad); eso es de `ItemInstance` a futuro.
- **Relaciones:** referenciado por `ItemInstance.definition` y por `InventoryEntry.get_footprint()`.

### `item_instance.gd` — `class_name ItemInstance extends RefCounted`
- **Responsabilidad:** representar *esta copia concreta*. Conserva identidad lógica entre contextos (INV-02, INV-06).
- **Campos:** `instance_id: int` (asignado en `_init` desde `static var _siguiente_id`, que arranca en 1 y se autoincrementa **por proceso**), `definition: ItemDefinition`.
- **Puede leer:** su `definition`. **Muta:** solo en `_init`.
- **Contrato de identidad (C-D8.1..4; sección 17, D8):** `definition` se fija en `_init` y **no se reasigna**; `instance_id` se fija en `_init` y es **solo** aid de logs/tests (ninguna rama de producción depende de su valor — la identidad es la **referencia**); `_siguiente_id` es detalle de construcción. Las 4 reglas se cumplen de facto en todo el repo; GDScript 4.6.3 **no** puede imponerlas (no hay `private`, `set()`/`call()` dinámicos alcanzan todo). Se sostienen por convención + el tripwire `inventory_v1_identity_contract_test`. Es limitación deliberada, no agujero desconocido.
- **NO debería:** saber dónde está (mundo/inventario/celda). No lo sabe: solo QUÉ es y QUIÉN es.
- **Relaciones:** creado por el arnés/gameplay al spawnear un `WorldItemV2`; referenciado por `WorldItemV2.item_instance` y `InventoryEntry.item_instance`. La identidad es la **referencia del objeto** (comparaciones `==`); `instance_id` es solo un aid legible.

### `inventory_entry.gd` — `class_name InventoryEntry extends RefCounted`
- **Responsabilidad:** ligar un `ItemInstance` a su `position: Vector2i` y `rotated: bool` **dentro de UN inventario concreto**.
- **Dos usos, misma clase:** *VIVA* — la que `InventoryV2` guarda en `_entries` (fuente de verdad); *SNAPSHOT* — copia detached que devuelven `get_entries()` / `entry_en_celda()`. Mutar una snapshot NO afecta al modelo (no comparte estado con la viva). `item_instance` **sí** es la misma referencia (identidad lógica compartida).
- **Campos:** `item_instance`, `position`, `rotated` (plain `var`).
- **`snapshot() -> InventoryEntry`:** `InventoryEntry.new(item_instance, position, rotated)` — misma ref de `ItemInstance`, `position`/`rotated` por valor.
- **`_reubicar(p_position, p_rotated)`:** escribe `position`/`rotated`. **SOLO lo llama `InventoryV2._reubicar_entry`** (marcador de legibilidad; sin enforcement — GDScript no lo permite).
- **`get_footprint() -> Vector2i`:** `(grid_width, grid_height)` normal, `(grid_height, grid_width)` si `rotated`.
- **Puede leer:** su `item_instance.definition`.
- **NO debería:** ser creada/mutada por la UI directamente. La barrera de D1 es que `InventoryV2` **nunca entrega la entry viva**, no que los campos estén protegidos (sección 17, D1).
- **Relaciones:** las vivas viven en `InventoryV2._entries`. `find_valid_placement()` devuelve una entry "de consulta" (con `item_instance = null`) que `TransferOperation` usa solo como portador de `position`/`rotated`.

### `inventory.gd` — `class_name InventoryV2 extends Node` (INV-01)
- **Responsabilidad:** guardar el contenido de un inventario de grilla. Componente colgado de una entidad.
- **Campos:** `grid_width`/`grid_height` (`@export`, default 4), `signal contenido_cambiado`, `var _entries: Array[InventoryEntry]` (privado).
- **Puede leer:** su propia `_entries` (fuente de verdad).
- **Puede mutar:** `_entries` **solo** vía `_agregar_entry` / `_quitar_entry` / `_reubicar_entry` (ver sección 7). Cada uno emite `contenido_cambiado` cuando muta.
- **NO debería:** ser mutado desde afuera (UI, otros nodos). No mantiene matriz de ocupación: la ocupación es **derivada** (INV-05).
- **Consultas read-only:** `get_entries()` (**snapshots detached**, una `InventoryEntry.new(...)` por elemento — ver sección 8), `has_item()`, `find_valid_placement()`, `entry_en_celda()` (snapshot), `celdas_ocupadas_por()`, `posicion_valida(item_instance, pos, rotated, excluir_item)`. Geometría privada: `_cabe_en()`, `_se_superponen()`.
- **Relaciones:** los mutadores son "API exclusiva de `TransferOperation`". `find_valid_placement()` la usa `_validar_mundo_a_inventario()`; `posicion_valida()` la usa `_validar_reubicar()`. `contenido_cambiado` lo consume `InventoryGridView`.

### `transfer_operation.gd` — `class_name TransferOperation extends RefCounted` (INV-07)
- **Responsabilidad:** la **única** forma válida de cambiar la custodia de un `ItemInstance` (mundo↔inventario) y — desde V1 — de reubicarlo dentro de un mismo `InventoryV2`. Objeto **transitorio**: se crea para UNA operación y se descarta.
- **Contrato:** `crear_*()` (factory) → `validate()` → `commit()`. Si `validate()` falla, `commit()` no debe llamarse y NADA cambia.
- **Tipos (`enum Tipo`):** `MUNDO_A_INVENTARIO`, `INVENTARIO_A_MUNDO`, `REUBICAR_EN_INVENTARIO`.
- **Puede leer:** todo lo que necesite para validar (`inventory.has_item`, `find_valid_placement`, `posicion_valida`, `get_entries`, `definition`, `is_instance_valid`). `_buscar_entry` devuelve una **snapshot** (vía `get_entries()`); `_validar_reubicar` solo lee su `.rotated`.
- **Puede mutar (solo en `commit()`):** llama a `inventory._agregar_entry` / `_quitar_entry` / `_reubicar_entry`, `world_item.queue_free()`, `world_scene.instantiate()` + `add_child`. En `_commit_mundo_a_inventario` **construye la entry completa** (`InventoryEntry.new(item_instance, _placement_valido.position, _placement_valido.rotated)`) — `_placement_valido` de `find_valid_placement` es solo un portador de `position`/`rotated`; `item_instance` nunca se muta post-construcción.
- **NO debería:** decidir "quién tiene permiso" (eso es `LocalAuthority`); persistir; ser reutilizado para otra operación.
- **Relaciones:** creado y ejecutado **solo** por `LocalAuthority`. `_commit_*` delega en los mutadores de `InventoryV2`.

### `local_authority.gd` — `class_name LocalAuthority extends Node` (INV-08)
- **Responsabilidad:** frontera de autoridad. **El único** que invoca `TransferOperation.validate()/commit()`. Loguea `[LocalAuthority] SOLICITUD/VALIDATE/COMMIT …`.
- **API pública:** `solicitar_pickup(world_item) -> bool`, `solicitar_devolucion(item, inventory, parent, position) -> WorldItemV2`, `solicitar_reubicacion(item, inventory, nueva_pos, nuevo_rotated) -> bool`, `set_inventory_receptor(inventory)`.
- **Puede leer:** `_inventory_receptor` (para pickup), lo que le pasan por parámetro.
- **Puede mutar:** nada directamente; construye y ejecuta la `TransferOperation`. En devolución exitosa hace `nuevo_world_item.setup(self)` (se re-inyecta).
- **NO debería:** contener lógica de gameplay/targeting ("cuál jugador", "qué inventario"); ni transporte de red.
- **Relaciones:** inyectado vía `setup()` en `WorldItemV2` y `InventoryManipulator`. En V0 se le fija UN inventario receptor (`set_inventory_receptor`) — deuda conocida, ver sección 17.

### `world_item.gd` — `class_name WorldItemV2 extends RigidBody3D` (INV-02)
- **Responsabilidad:** carcasa **física y visual TEMPORAL** de un `ItemInstance` mientras existe en el mundo. Puede crearse/destruirse sin destruir la identidad lógica.
- **Campos:** `item_instance: ItemInstance` (plain `var`, **no** `@export`), `_authority: Node` (inyectado por `setup()`).
- **`_on_interact(interaction) -> Variant`:** contrato de `InteractionComponent` (gameplay) — acción `&"usar"` → `_solicitar_pickup()`.
- **`_solicitar_pickup()`:** **solo solicita**. `return _authority.solicitar_pickup(self)`. No agrega el item a ningún inventario, no se destruye a sí mismo, no decide el resultado (INV-07/INV-08).
- **Puede leer:** su `item_instance`, su `_authority`.
- **Puede mutar:** nada del sistema. (Godot lo `queue_free()` desde `TransferOperation._commit_mundo_a_inventario`.)
- **NO debería:** llamar mutadores de `InventoryV2` ni `TransferOperation` directamente.
- **Relaciones:** su `world_scene` (en `ItemDefinition`) es la escena que se re-instancia al devolver el item al mundo.

### `inventory_grid_view.gd` — `class_name InventoryGridView extends Control` (V1)
- **Responsabilidad:** dibujar la grilla `grid_width × grid_height` y un rect por cada `InventoryEntry`. Ver sección 9.
- **Estrictamente READ-ONLY:** solo lee `get_entries()`, `grid_width`, `grid_height`; se suscribe a `contenido_cambiado`.
- **Campos:** `cell_size` (`@export`, default 40), colores (`@export`), `refrescos: int` (contador de diagnóstico), `_inventory` (privado).
- **API:** `set_inventory(inv)` (conecta/desconecta `contenido_cambiado`), `get_inventory()`, consultas de layout puras `cantidad_celdas()`, `rect_de_celda()`, `rect_de_entry()`, `layout_entries()`. `layout_entries()` devuelve `{position, rotated, footprint, rect}` por elemento — **sin `ItemInstance` ni ningún id** (la vista no maneja identidad; sección 9 y sección 17, D8).
- **NO debería:** llamar a `LocalAuthority`, `TransferOperation` ni a los mutadores. Nunca lo hace.
- **Relaciones:** el `InventoryManipulator` lee `_view.cell_size`, `_view.get_inventory()`, `_view.get_local_mouse_position()`.

### `inventory_manipulator.gd` — `class_name InventoryManipulator extends Control` (V1)
- **Responsabilidad:** máquina de estados de manipulación. Traduce input (clic / mouse / `rotar_item` / `ui_cancel`) a transiciones; dibuja el ghost/preview del destino tentativo. Ver secciones 10–12.
- **NO muta `InventoryV2` NUNCA.** Toda reubicación real pasa por `LocalAuthority.solicitar_reubicacion()`.
- **Campos transitorios:** `_activo`, `_seleccionada` (**una SNAPSHOT** de `entry_en_celda`, no la entry viva), `_rotacion_tentativa`, `_celda_hover`, `_agarre_rel_normal`. `_view`, `_authority` inyectados por `setup()`.
- **Señales:** `agarrado(entry)`, `soltado(entry, exito)`, `preview_cambiado()`, `cancelado(entry)`, `rotacion_rechazada(entry)`.
- **API pública (transiciones):** `activar()`, `desactivar()`, `agarrar_en(celda)`, `mover_hover_a(celda)`, `rotar_tentativo()`, `soltar()`, `cancelar()` + consultas (`esta_activo`, `esta_agarrando`, `entry_agarrada` — devuelve la snapshot, `item_agarrado` — la referencia real de `ItemInstance`, `rotacion_tentativa`, `celda_hover`, `celda_destino_tentativa`, `destino_es_valido`, `offset_agarre_actual`).
- **`_unhandled_input`:** solo corre si `_activo`. Es fino: traduce y delega en las transiciones (que también usan los tests como caja blanca).
- **NO debería:** llamar mutadores de `InventoryV2`; mutar `entry.position`/`entry.rotated`; depender de `visible` para saber si está activo.
- **Relaciones:** en el arnés se agrega como **hijo `Control` del `InventoryGridView`** (mismas coordenadas locales), con `mouse_filter = IGNORE`.

### Diagrama de flujo — V0 (pickup, mundo → inventario)

```
WorldItemV2._on_interact(&"usar")            [InteractionComponent en gameplay / directo en tests]
        |
        v
WorldItemV2._solicitar_pickup()
        |
        v
LocalAuthority.solicitar_pickup(world_item)   [_inventory_receptor debe estar seteado]
        |
        v
TransferOperation.crear_mundo_a_inventario(world_item, inventory)
        |
   validate()  -> _validar_mundo_a_inventario()   (no muta)
        |  (si falla: return false, nada cambia)
   commit()    -> _commit_mundo_a_inventario():
        |          entry = InventoryEntry.new(item, placement.position, placement.rotated)
        |          inventory._agregar_entry(entry)  --emit--> contenido_cambiado
        |          world_item.queue_free()
        v
   InventoryV2._entries  (item ahora bajo custodia Inventory)
```

### Diagrama de flujo — V0 (devolución, inventario → mundo)

```
[disparador de debug: inventory_v0_test_scene._solicitar_devolucion_debug() / test]
        |
        v
LocalAuthority.solicitar_devolucion(item, inventory, parent, spawn_pos)
        |
   TransferOperation.crear_inventario_a_mundo(...)
        |
   validate()  -> _validar_inventario_a_mundo()   (chequea world_scene != null, parent válido)
        |
   commit()    -> _commit_inventario_a_mundo():
        |          nuevo = definition.world_scene.instantiate()  (debe ser WorldItemV2)
        |          nuevo.item_instance = item                    (MISMO ItemInstance)
        |          parent.add_child(nuevo); nuevo.global_position = spawn_pos
        |          inventory._quitar_entry(item)  --emit--> contenido_cambiado
        v
   LocalAuthority: nuevo.setup(self)   (re-inyecta la autoridad en el world item nuevo)
```

### Diagrama de flujo — V1 (reubicación dentro del mismo inventario)

```
Input real (clic izq / movimiento de mouse / tecla rotar_item / ui_cancel)
        |
        v
InventoryManipulator._unhandled_input(event)      [SOLO si _activo == true]
        |
   agarrar_en / mover_hover_a / rotar_tentativo / cancelar   (estado transitorio, NO toca el modelo)
   soltar():
        |
        v
LocalAuthority.solicitar_reubicacion(item, inv, celda_destino_tentativa(), rotacion_tentativa)
        |
   TransferOperation.crear_reubicar(...)
        |
   validate()  -> _validar_reubicar():
        |          - item bajo custodia de inv       (_buscar_entry -> snapshot)
        |          - si cambia rotacion: can_rotate   (INV-15)
        |          - inv.posicion_valida(item, ..., excluir_item = item)   (INV-11)
        |  (si falla: return false, sigue "held", modelo idéntico, sin emisión)
   commit()    -> _commit_reubicar():
        |          inv._reubicar_entry(item, nueva_pos, nuevo_rotated)   (in-place, MISMA entry viva)
        |             --emit--> contenido_cambiado                        (exactamente 1 vez)
        v
InventoryV2._entries  (misma InventoryEntry viva, misma ItemInstance, size igual)
        |
        v
contenido_cambiado  ->  InventoryGridView._on_contenido_cambiado()  ->  _refrescar()  ->  queue_redraw()
```

---

## 4. Modelo de datos

### `ItemDefinition` vs `ItemInstance` vs `InventoryEntry`

- **`ItemDefinition`** — el molde. Un `.tres` compartido. No hay identidad de instancia acá.
- **`ItemInstance`** — la identidad lógica. **La identidad ES la referencia del objeto**: `entry.item_instance == otro_item` compara referencia. `instance_id` (int) es la "fuente de verdad de identidad para logs y pruebas". Se asigna en `_init` desde `static var _siguiente_id` (arranca en 1). **Por proceso**: en cada corrida los ids arrancan de 1; no persisten, no son únicos entre corridas.
- **`InventoryEntry`** — el "dónde y cómo" dentro de UN inventario. `position: Vector2i` (esquina superior-izquierda en celdas), `rotated: bool` (2 orientaciones: normal 0° y 90°).

### Campos clave

| Campo | Vive en | Significado |
|---|---|---|
| `instance_id` | `ItemInstance` | int autoincremental (por proceso). Identidad para logs/tests. |
| `position` | `InventoryEntry` | celda superior-izquierda dentro del inventario dueño de esa entry. |
| `rotated` | `InventoryEntry` | `false` = orientación normal; `true` = 90°. |
| `footprint` | derivado (`InventoryEntry.get_footprint()`) | `(grid_width, grid_height)` si `not rotated`; `(grid_height, grid_width)` si `rotated`. |
| `can_rotate` | `ItemDefinition` | si la instancia puede rotar 90° dentro del inventario (INV-04). Se valida en la operación, no en la geometría. |
| `world_scene` | `ItemDefinition` | `PackedScene` a instanciar cuando el item vuelve al mundo; su raíz debe ser un `WorldItemV2`. |
| `grid_width` / `grid_height` (de `ItemDefinition`) | `ItemDefinition` | huella del item en orientación normal (default 1×1). |
| `grid_width` / `grid_height` (de `InventoryV2`) | `InventoryV2` | dimensiones de la grilla del inventario (default 4×4). |

Datos de prueba en `assets/data/test_inventory_v2/`:
- `item_definition_test.tres` — `id=&"test_item_v0"`, 2×1, `can_rotate=true`, `world_scene = test_item_v0.tscn`.
- `item_definition_no_rota_test.tres` — `id=&"test_item_no_rota"`, 2×1, `can_rotate=false`, mismo `world_scene`.

---

## 5. Custodia

**Invariante (INV-16, chequeada en `inventory_v1_negatives_test`):** para cualquier `ItemInstance` en juego,

```
(World == 1  AND  Inventory == 0)   XOR   (World == 0  AND  Inventory == 1)
```

Nunca `1/1`, nunca `0/0`.

- **World count** = cantidad de `WorldItemV2` en el árbol (no `queue_for_deletion`) cuyo `item_instance` es ese.
- **Inventory count** = cantidad de `InventoryEntry` en `_entries` (de cualquier `InventoryV2`) cuyo `item_instance` es ese.

### Cómo pickup lo mantiene

`_commit_mundo_a_inventario()` hace, en un solo `commit()`:
1. `inventory._agregar_entry(InventoryEntry.new(item, _placement_valido.position, _placement_valido.rotated))` — Inventory pasa de 0 a 1.
2. `world_item.queue_free()` — el world item queda marcado para borrar → deja de contar como World=1 (el conteo ignora `is_queued_for_deletion()`).

No hay punto intermedio observable: la transición es atómica dentro del `commit()`. Si `validate()` había fallado, `commit()` no se ejecuta y el world item sigue vivo (World=1/Inv=0).

### Cómo devolución lo mantiene

`_commit_inventario_a_mundo()`:
1. instancia + `add_child` del nuevo `WorldItemV2` con el **mismo** `ItemInstance` — World pasa a 1.
2. `inventory._quitar_entry(item)` — Inventory pasa a 0.

Si `validate()` falla (sin `world_scene`, `parent` inválido, item no está en ese inventario), no se crea nada y el item sigue Inv=1.

### Reubicación (V1) y custodia

`REUBICAR_EN_INVENTARIO` **no cambia la custodia**: el item ya estaba Inv=1 y sigue Inv=1 (solo cambian `position`/`rotated` de su entry). El conteo World/Inventory es invariante ante una reubicación, exitosa o fallida.

---

## 6. Operaciones autoritativas

Los tres tipos de `TransferOperation`. Todos: `crear_*()` → `validate()` → `commit()`, atómicos, con `get_resultado_validacion()` explicando el rechazo.

### `MUNDO_A_INVENTARIO` (pickup)
- **request:** `crear_mundo_a_inventario(world_item, inventory)`.
- **validate (`_validar_mundo_a_inventario`):** rechaza si — `item_instance == null`; `world_item` inválido; `inventory_destino == null`; el item **ya** está en ese inventario (doble custodia); `find_valid_placement(definition) == null` (sin espacio). Guarda `_placement_valido`.
- **commit (`_commit_mundo_a_inventario`):** `inventory._agregar_entry(InventoryEntry.new(item, _placement_valido.position, _placement_valido.rotated))`; `world_item.queue_free()`. Devuelve `true`. (`_placement_valido` es solo portador de `position`/`rotated`; el `ItemInstance` va directo al constructor.)
- **éxito cambia:** el item entra a `_entries` en la posición del first-fit; el world item se destruye; `contenido_cambiado` emitido.
- **fallo NO cambia:** nada. El world item sigue en el mundo.

### `INVENTARIO_A_MUNDO` (devolución)
- **request:** `crear_inventario_a_mundo(item_instance, inventory, parent, position)`.
- **validate (`_validar_inventario_a_mundo`):** rechaza si — `item_instance == null`; `inventory_origen == null`; el item **no** está bajo custodia de ese inventario; `definition == null` o `definition.world_scene == null`; `world_scene_parent` inválido.
- **commit (`_commit_inventario_a_mundo`):** instancia `world_scene` (debe producir un `WorldItemV2`, si no `push_error` + `null`); `nuevo.item_instance = item` (MISMO); `parent.add_child`; `global_position = spawn`; `inventory._quitar_entry(item)`. Devuelve el `WorldItemV2` nuevo.
- **éxito cambia:** aparece un `WorldItemV2` nuevo con el mismo `ItemInstance`; la entry sale de `_entries`; `contenido_cambiado` emitido; `LocalAuthority` re-inyecta la autoridad en el nodo nuevo.
- **fallo NO cambia:** nada. El item sigue en el inventario.

### `REUBICAR_EN_INVENTARIO` (mover/rotar dentro del mismo inventario) — V1
- **request:** `crear_reubicar(item_instance, inventory, nueva_pos, nuevo_rotated)`.
- **validate (`_validar_reubicar`):** rechaza si — `item_instance == null`; `inventory_reubicar == null`; el item **no** está bajo custodia de ese inventario (`_buscar_entry` devuelve `null` — busca una **snapshot** vía `get_entries()`); `nuevo_rotated != _entry_snapshot.rotated` **y** `not definition.can_rotate` (INV-15); `not inventory.posicion_valida(item, nueva_pos, nuevo_rotated, excluir_item = item)` (fuera de límites o solapamiento, INV-11).
- **commit (`_commit_reubicar`):** `inventory._reubicar_entry(item, nueva_pos, nuevo_rotated)`. Devuelve `true`.
- **éxito cambia:** `entry.position` y `entry.rotated` (in-place, **misma `InventoryEntry`**, INV-09); `_entries.size()` y orden de lista **no** cambian (INV-10); `contenido_cambiado` emitido **exactamente 1 vez**; `instance_id` intacto.
- **fallo NO cambia:** nada — `position`, `rotated`, la identidad de la entry, `_entries.size()`, y **no** se emite `contenido_cambiado` (INV-13).

### Por qué `LocalAuthority` es el único caller de `validate()/commit()` (INV-08)

`TransferOperation` sabe *validar y aplicar* una operación, pero **no** sabe "quién tiene permiso". Separar la frontera de autoridad (quién autoriza) de la mecánica (qué se aplica) permite que:
- un solo lugar loguee y arbitre todas las transferencias;
- a futuro una **autoridad remota** (servidor) ocupe ese rol sin tocar `InventoryV2` / `WorldItemV2` / `TransferOperation`;
- ningún componente de interacción (UI, `WorldItemV2`) pueda saltarse la validación.

En HEAD la autoridad es local y "tonta". No hay red.

---

## 7. Mutación de `InventoryV2`

`_entries` es **privado** y **solo** se muta por estos tres métodos (comentario de cabecera de `inventory.gd`: *"Las unicas tres formas validas de cambiar su contenido"*):

| Método | Qué hace | Emite `contenido_cambiado` |
|---|---|---|
| `_agregar_entry(entry)` | `_entries.append(entry)` | sí, siempre (append siempre muta) |
| `_quitar_entry(item_instance)` | busca por `item_instance`, `remove_at`, devuelve la entry | sí, **solo si encontró** algo que quitar; si no, `return null` sin emitir |
| `_reubicar_entry(item_instance, nueva_pos, nuevo_rotated)` | busca por `item_instance` en `_entries` (vivas), llama `entry._reubicar(nueva_pos, nuevo_rotated)` **in-place** sobre la MISMA `InventoryEntry`, devuelve esa entry | sí, **solo si encontró**; si no, `return null` sin emitir |

Reglas:
- **El resto del sistema NO debe mutar `_entries` directamente.** Los `_` de los nombres son la señal de que no son API pública, **pero `_` no es una barrera** en GDScript 4.6.3. La barrera real (D1, `43fc2f4`) es que las consultas públicas **nunca entregan una `InventoryEntry` viva** — devuelven snapshots detached. El único caller legítimo de los mutadores es `TransferOperation` durante su `commit()`.
- **`_reubicar_entry` es un mutador "tonto":** no valida límites ni solapamiento ni `can_rotate`. La validación ocurre **antes**, en `TransferOperation._validar_reubicar()`. Si alguien llama `_reubicar_entry` con una posición inválida, la aplica igual (los tests white-box lo hacen a propósito).
- **`contenido_cambiado` se emite solo desde mutaciones reales**, para que la vista refresque sin hacer polling de `get_entries()`.

---

## 8. Consultas y geometría

Todas read-only, no mutan `_entries`.

| Función | Devuelve | Notas |
|---|---|---|
| `get_entries()` | `Array[InventoryEntry]` | **snapshots detached**: una `entry.snapshot()` (`= InventoryEntry.new(...)`) por elemento, en orden de `_entries`. Mutar una snapshot NO afecta al modelo. `item_instance` de cada snapshot **es la misma referencia** (identidad compartida). **NO se garantiza identidad de objeto `InventoryEntry` entre dos llamadas** — dejó de ser contrato público (D1, `43fc2f4`). |
| `has_item(item_instance)` | `bool` | ¿alguna entry tiene ese `item_instance`? (compara por referencia). |
| `find_valid_placement(definition)` | `InventoryEntry` o `null` | **first-fit**: barre `fila`/`col`, prueba `rotated=false` y luego `rotated=true` si `can_rotate`. Devuelve una entry de consulta con `item_instance = null` — solo portadora de `position`/`rotated`, nunca se guarda. Solo la usa `_validar_mundo_a_inventario`. |
| `entry_en_celda(celda)` | `InventoryEntry` o `null` | hit-test: **snapshot** de la entry cuyo footprint (rotación incluida) cubre `celda`. NUNCA la entry viva. Si hubiera solape (no debería), la primera en orden de `_entries`. |
| `celdas_ocupadas_por(entry)` | `Array[Vector2i]` | geometría pura: itera el footprint desde `entry.position`. **No** valida que `entry` pertenezca a este inventario. Acepta snapshot o viva indistintamente. |
| `posicion_valida(item_instance, pos, rotated, excluir_item = null)` | `bool` | ¿`item_instance` entra en `pos` con orientación `rotated`, dentro de la grilla y sin solapar ninguna entry — **salvo la de `excluir_item`** (se excluye por `ItemInstance`, no por `InventoryEntry`, porque afuera ya no circulan entries vivas)? **No** chequea `can_rotate` (eso es de la operación). |

Geometría interna:
- **Footprint normal / rotado:** `(w, h)` vs `(h, w)`. Único cálculo, repetido en `InventoryEntry.get_footprint()`, `InventoryV2.posicion_valida`/`find_valid_placement`, `InventoryManipulator._footprint_de`.
- **Límites:** `pos.x < 0 or pos.y < 0` → inválido; `pos.x + fp.x > grid_width or pos.y + fp.y > grid_height` → inválido.
- **Solapamiento (`_se_superponen`):** AABB en celdas — no se solapan si uno termina antes de que el otro empiece en X o en Y.

### Por qué `excluir` es necesario al mover una entry existente

`_cabe_en()` (usado por `find_valid_placement`) chequea contra **todas** las entries — correcto para colocar un item **nuevo**. Pero al **mover** una entry que ya está en `_entries`, esa misma entry está en la lista: sin exclusión, el item "choca consigo mismo" y ninguna posición que se superponga con su lugar actual (ni el lugar actual mismo) sería válida. `posicion_valida(..., excluir_item = item_instance)` salta la entry de ese `ItemInstance` en el chequeo de solape. `_cabe_en` **no** se tocó (sigue chequeando contra todas), para no afectar a `find_valid_placement`.

---

## 9. `InventoryGridView`

- **Read-only:** solo lee `get_entries()`, `grid_width`, `grid_height`. **Nunca** llama a `LocalAuthority`, `TransferOperation` ni a los mutadores.
- **Tamaño de grilla:** de `_inventory.grid_width` / `grid_height`. En `_refrescar()` setea `custom_minimum_size = (grid_width * cell_size, grid_height * cell_size)`. El `cell_size` (`@export`, default 40) lo fija quien arma la escena.
- **Representación de entries:** en `_draw()` pinta la grilla (`grid_width × grid_height` `draw_rect`) y luego un rect por entry en `rect_de_entry(entry)` = `Rect2(position * cell_size, footprint * cell_size)`, con `footprint` ya rotación-aware vía `get_footprint()`.
- **`contenido_cambiado`:** `set_inventory()` conecta la señal del inventario nuevo y **desconecta** la del anterior. `_on_contenido_cambiado` → `_refrescar()` → `refrescos += 1` + `queue_redraw()`.
- **Consultas de layout puras** (mismas que usa `_draw`, expuestas para tests): `cantidad_celdas()`, `rect_de_celda()`, `rect_de_entry()`, `layout_entries()` — lista de `{position: Vector2i, rotated: bool, footprint: Vector2i, rect: Rect2}`, **por valor, sin `ItemInstance` ni id** (`43fc2f4`+`29adfa3`: la vista no maneja identidad y no se promueve `instance_id` a contrato público — sección 17, D8). Los consumidores que necesitaban distinguir una entry lo hacen por `position` (tests) o por la referencia de `ItemInstance` de `get_entries()`.
- **`refrescos`** es un contador de diagnóstico/observabilidad (arranca en 0; +1 por `_refrescar`).
- Su escena `inventory_grid_view.tscn` (un `Control` con el script) vive en `scenes/test/` — ver deuda sección 17.

---

## 10. `InventoryManipulator`

### Máquina de estados real

| Estado | `_activo` | `_seleccionada` | Qué acepta |
|---|---|---|---|
| **inactive** | `false` | `null` | nada por `_unhandled_input` (early-return). Las transiciones públicas siguen siendo llamables (tests). |
| **active, sin held** | `true` | `null` | clic izq → `agarrar_en(celda_bajo_mouse)`; movimiento de mouse actualiza `_celda_hover` pero no dibuja ghost. |
| **held** | `true` | `entry` | movimiento de mouse → `mover_hover_a` (actualiza preview, emite `preview_cambiado`); `rotar_item` → `rotar_tentativo`; clic izq → `soltar`; `ui_cancel` → `cancelar`. |
| **preview** | (sub-estado de *held*) | — | `celda_destino_tentativa()` = `_celda_hover - _offset_efectivo()`; `destino_es_valido()` = `inv.posicion_valida(_seleccionada.item_instance, ..., excluir_item = _seleccionada.item_instance)`; `_draw()` pinta el ghost verde/rojo. |
| **tentative rotation** | (sub-estado de *held*) | — | `_rotacion_tentativa = not _rotacion_tentativa` (solo si `can_rotate`; si no, `rotacion_rechazada`). No toca `entry.rotated` real. |
| **drop** | — | — | `soltar()` → `LocalAuthority.solicitar_reubicacion(...)`. Éxito: vuelve a *active, sin held* y limpia el estado transitorio. Fallo: **sigue held**, modelo idéntico. |
| **cancel** | — | — | `cancelar()` limpia `_seleccionada` / `_rotacion_tentativa` / `_agarre_rel_normal`, emite `cancelado`. Modelo idéntico. También lo llama `desactivar()`. |

### Variables transitorias

Todas **solo en el manipulator**, nunca en `InventoryV2`:

| Var | Significado |
|---|---|
| `_activo: bool` | si se procesa input (ver sección 12). |
| `_seleccionada: InventoryEntry` | la entry "en la mano" — una **SNAPSHOT detached** (de `entry_en_celda`), no la entry viva. Mutarla no afecta al modelo. Válida durante todo el grab porque la entry real no se reubica mientras hay un grab. Su `item_instance` **sí** es la referencia real (se usa para pedirle a la autoridad la reubicación). `null` = nada held. |
| `_rotacion_tentativa: bool` | orientación del ghost. Independiente de `entry.rotated` real hasta el commit. Arranca `= entry.rotated` al agarrar. |
| `_celda_hover: Vector2i` | celda bajo el cursor. |
| `_agarre_rel_normal: Vector2i` | celda de agarre relativa a `entry.position`, en **frame canónico** (orientación normal). Ver sección 11. |

### Flujo: seleccionar → held → preview → LocalAuthority → commit/reject

1. Clic izq sin held → `agarrar_en(celda)`: si `entry_en_celda(celda) != null` → `_seleccionada = entry`, `_rotacion_tentativa = entry.rotated`, guarda `_agarre_rel_normal`, emite `agarrado`. **El modelo NO cambia**: la entry sigue en `_entries` en su `position`/`rotated` reales.
2. Movimiento de mouse → `mover_hover_a(celda)` → `preview_cambiado`. El ghost se redibuja en `celda_destino_tentativa()` con color según `destino_es_valido()`. **Solo preview, sin modelo.**
3. `rotar_item` → `rotar_tentativo()`: alterna `_rotacion_tentativa` (si `can_rotate`). **`entry.rotated` real no se toca.**
4. Clic izq con held → `soltar()` → `LocalAuthority.solicitar_reubicacion(entry.item_instance, inv, celda_destino_tentativa(), _rotacion_tentativa)`:
   - **éxito:** `_seleccionada = null`, `_rotacion_tentativa = false`, `_agarre_rel_normal = ZERO`. Emite `soltado(entry, true)`. El modelo cambió **vía la operación autorizada**.
   - **fallo:** `_seleccionada` sigue siendo la entry (**sigue held**). Emite `soltado(entry, false)`. Modelo idéntico, sin emisión de `contenido_cambiado`.
5. `ui_cancel` o cerrar la UI → `cancelar()`: limpia el estado transitorio, emite `cancelado`. **La entry nunca se movió del modelo.**

**Explícito: el preview NO mueve la entry real.** Lo único que se escribe en `InventoryEntry` es en el `commit()` de una `TransferOperation` validada.

---

## 11. Rotación y punto de agarre

### El bug (encontrado en la prueba manual del Paso 5)

Un ítem 2×1 agarrado **desde su segunda celda** quedaba desplazado al rotarlo a 1×2. El ghost seguía al mouse pero dibujado corrido, con el cursor fuera del rectángulo.

**Causa:** el offset de agarre se guardaba una vez, al agarrar, como `celda - entry.position` — es decir, **en coordenadas del footprint que el ítem tenía en ese momento**. Al rotar solo cambiaba `_rotacion_tentativa` (y con eso la forma del footprint), pero el offset seguía valiendo `(1,0)` — una celda que en el footprint rotado `1×2` (ancho 1) **no existe**. Resultado: ghost dibujado a la izquierda del cursor.

Sin rotación, o agarrando la primera celda (offset `(0,0)`), el problema no se veía: por eso *no* era un problema de coordenadas entre Controls.

### La solución actual

El punto de agarre se guarda **una sola vez, en un frame canónico fijo** (la orientación NORMAL del ítem) y el offset efectivo se **deriva** según la rotación tentativa:

- `_agarre_rel_normal: Vector2i` — celda agarrada relativa a `entry.position`, **siempre** en frame no-rotado. Si la entry ya estaba rotada al agarrar, la celda se convierte a canónico con `_rel_rotada_a_normal`.
- `_offset_efectivo()` — si `not _rotacion_tentativa`: devuelve `_agarre_rel_normal` tal cual. Si rotado: `_rel_normal_a_rotada(_agarre_rel_normal, def)`.
- `celda_destino_tentativa()` = `_celda_hover - _offset_efectivo()`.

Transformación 90° horaria e inversa exacta (footprint normal `W×H` ↔ rotado `H×W`, con `W = grid_width`, `H = grid_height`):

```
_rel_normal_a_rotada(c) = (H - 1 - c.y,  c.x)
_rel_rotada_a_normal(c) = (c.y,  H - 1 - c.x)
```

**Por qué no acumula drift:** `_agarre_rel_normal` se fija al agarrar y **nunca se muta**. `_offset_efectivo()` es función pura de `(_agarre_rel_normal, _rotacion_tentativa)`. Alternar la rotación N veces siempre da exactamente `_agarre_rel_normal` (par) o su rotado (impar), sin estado intermedio. El offset efectivo siempre cae dentro del footprint tentativo → el cursor nunca "sale" del ghost.

**Test de regresión:** `inventory_v1_rotacion_offset_test` (50 chequeos): agarre desde 1ª y 2ª celda, rotar ida/vuelta, mover el mouse rotado, 20 rotaciones seguidas, ítem ya rotado al agarrar.

---

## 12. Activación / UI abierta-cerrada

### El bug (encontrado en la prueba manual del Paso 5)

Con la UI "cerrada" (`CanvasLayer.visible = false`), un clic donde virtualmente estaba un ítem lo dejaba *seleccionado/held*; al reabrir aparecía en la mano. También se podía mover/rotar con la UI cerrada.

**Causa:** `CanvasLayer.visible = false` oculta el **render**, no frena `_input` / `_unhandled_input`. El `InventoryManipulator` seguía en el árbol con `is_processing_unhandled_input() == true`. Su `_unhandled_input` solo se guardaba contra `_view == null` — que nunca pasa al cerrar. `_celda_bajo_mouse()` (usa `_view.get_local_mouse_position()`) sigue calculando una celda aunque la vista esté oculta. El arnés al reabrir solo hacía `visible = true` sin resetear el manipulator.

### La solución

Estado explícito de activación **+** habilitar/deshabilitar el procesamiento de input:

- `var _activo: bool = false` (arranca inactivo; `_ready()` hace `set_process_unhandled_input(false)`).
- `activar()` — al ABRIR la UI: `cancelar()` (estado limpio) + `_celda_hover = ZERO` + `_activo = true` + `set_process_unhandled_input(true)`.
- `desactivar()` — al CERRAR la UI: `cancelar()` (cancela cualquier held) + `_activo = false` + `set_process_unhandled_input(false)`.
- `_unhandled_input` arranca con `if not _activo: return` — gate único común a **todos** los eventos.

El arnés (`inventory_v1_manual_test.gd`) llama `manip.activar()` al abrir y `manip.desactivar()` al cerrar.

**Regla funcional:** con el inventario cerrado — ningún clic selecciona; el mouse no actualiza held/preview; `R` no rota; ningún drop ocurre; no se genera ninguna interacción. Al cerrar, cualquier held se cancela y el manipulator queda inerte. Al abrir, arranca limpio.

**Test de regresión:** `inventory_v1_activacion_test` (40 chequeos), con eventos sintéticos pasados a `manip._unhandled_input(...)`.

### Mitigación del `UiInventario` legacy en el arnés manual

`inventory_v1_manual_test.gd._ready()` hace `get_node_or_null("/root/UiInventario").set_process_input(false)`. Motivo: el autoload legacy `UiInventario` (`ui_inventario.gd:145`) captura la acción `toggle_inventario` **sin condición** → si no se silencia, al apretar Tab en el arné aparece un overlay vacío de 15×20 y se fuerza `Input.set_mouse_mode`.

**Esto es una particularidad del arné de prueba, no arquitectura de V1.** V1 no depende de la UI legacy (ver sección 16). El manipulator **no** usa `toggle_inventario` — el abrir/cerrar lo maneja el arné a nivel pantalla.

---

## 13. Invariantes

Numeración recuperada del código y los tests. **Hay huecos históricos: `INV-03` e `INV-14` no están definidas en ningún archivo del repo — no se inventan.** `INV-01`–`INV-08` provienen de un documento de diseño de V0 ("el encargo" / "doc V0 seccion N") citado en los comentarios pero **no versionado en el repo**; este documento es la primera referencia técnica commiteada.

| INV | Enunciado (según los comentarios de código / tests) | Respaldo |
|---|---|---|
| **INV-01** | `InventoryV2` no es Singleton ni Autoload; el estado vive colgado de la entidad dueña. | `inventory.gd:8` |
| **INV-02** | `ItemInstance` conserva su identidad lógica aunque cambie de contexto (mundo ↔ inventario). `ItemDefinition` inmutable durante la partida. Reforzado por el contrato C-D8.1..4 (sección 17, D8): `definition` set-once, `ItemDefinition` runtime-inmutable, `instance_id` solo aid. | `item_definition.gd`, `item_instance.gd`, `world_item.gd`; tripwire `inventory_v1_identity_contract_test` |
| **INV-04** | `can_rotate`: si la instancia puede rotar 90° dentro del inventario. | `item_definition.gd:24` |
| **INV-05** | La ocupación por celda es **información derivada** de `_entries`; se recalcula bajo demanda. No hay matriz de ocupación como estado independiente. | `inventory.gd:11, 93` |
| **INV-06** | `ItemInstance` conserva identidad entre mundo, inventario u otros contextos futuros. | `item_instance.gd:6` |
| **INV-07** | `TransferOperation` es la **única forma válida** de cambiar la custodia de un `ItemInstance` (V1: también de reubicar dentro del mismo `InventoryV2`). Centralización por transacción, no por singleton. | `transfer_operation.gd:5, 17`, `inventory.gd:18`, `world_item.gd:12, 33` |
| **INV-08** | `LocalAuthority` es la frontera de autoridad: **el único** con permiso de invocar `validate()`/`commit()`. Los componentes SOLICITAN, no ejecutan. | `local_authority.gd:4`, `inventory.gd:18`, `world_item.gd:12, 33` |
| **INV-09** | Una reubicación se aplica **in-place sobre la MISMA `InventoryEntry`** y conserva el **MISMO `ItemInstance`** (y su `instance_id`). Desde `43fc2f4` la parte "misma `InventoryEntry`" es invariante **INTERNA** (las consultas públicas devuelven snapshots): se verifica **white-box** sobre `inv._entries` en `inventory_v1_reubicar_test` / `operacion_reubicar_test` / `manipulator_test` / `entry_readonly_test`. La identidad pública es la **referencia de `ItemInstance`**. | `inventory.gd` (`_reubicar_entry`), `transfer_operation.gd` (`_commit_reubicar`) |
| **INV-10** | Una reubicación **no** cambia `_entries.size()` ni el orden de la lista. | `inventory.gd:158`, `transfer_operation.gd:211` |
| **INV-11** | La posición destino de una reubicación debe ser válida: dentro de la grilla y sin solapar otra entry (**excluyendo la propia**). | `transfer_operation.gd:138`, `inventory.gd` (`posicion_valida`) |
| **INV-12** | Abrir/cerrar la UI **no muta el modelo**. | test `inventory_v1_negatives_test.gd` |
| **INV-13** | Si `validate()` falla, `commit()` no corre y el modelo queda **byte-idéntico** (sin aplicación parcial); **no** se emite `contenido_cambiado`. | test `inventory_v1_negatives_test.gd`; comportamiento de `transfer_operation.gd` (contrato de cabecera) |
| **INV-15** | Si una reubicación cambia la orientación, `ItemDefinition.can_rotate` debe permitirlo. Gate en la **operación**, no en la geometría. | `transfer_operation.gd:137, 152` |
| **INV-16** | Custodia: un `ItemInstance` **nunca** está simultáneamente en el mundo y en un inventario (World+Inventory nunca `1/1`, nunca `0/0`). | test `inventory_v1_negatives_test.gd` |

Invariantes transversales sin número explícito pero verificadas: *toda reubicación real pasa por `LocalAuthority`* (por diseño, `InventoryManipulator` nunca llama mutadores); *la vista nunca muta el modelo* (`InventoryGridView` read-only); *las consultas públicas de `InventoryV2` nunca entregan una `InventoryEntry` viva* (`43fc2f4` — snapshots detached; `inventory_v1_entry_readonly_test`).

**Contrato de identidad C-D8.1..4** (limitación deliberada, no invariante forzada — sección 17, D8): `ItemInstance.definition` set-once; `ItemDefinition` runtime-inmutable; `instance_id` set-once y solo aid de logs/tests; `_siguiente_id` detalle de construcción. Se cumplen de facto en todo el repo; GDScript no los impone. Tripwire: `inventory_v1_identity_contract_test`.

---

## 14. Tests

Ubicación: `scenes/test/`. Los `.gd` de arnés terminan con `assert(_fallos == 0)` y `get_tree().quit(_fallos)` (salvo el manual). Todos siembran el inventario **por la ruta V0** (spawn `WorldItemV2` + `_on_interact(&"usar")` → `LocalAuthority.solicitar_pickup`), sin backdoors de mutación — salvo los chequeos white-box de INV-09, que a propósito trabajan sobre `inv._entries` (entries vivas): `inventory_v1_reubicar_test` (`_sembrar` devuelve `_entries.duplicate()` y llama `_reubicar_entry`/`_quitar_entry` directo), y helpers puntuales en `operacion_reubicar_test` / `manipulator_test` / `entry_readonly_test`.

| Test | Tipo | Chequeos | Qué prueba | Invariantes que protege |
|---|---|---|---|---|
| `inventory_v0_test` | manual (raycast + input) | — | ciclo Mundo→Inventario→Mundo con `interactuar` (E) y `ui_accept`; identidad `#1` estable | INV-02, INV-06, INV-16 |
| `inventory_v0_negatives_test` | automático | 22 | pickup sin espacio → falla; pickup fallido → item sigue en el mundo; devolución no completable → item sigue en inventario; custodia tras cada operación | INV-13, INV-16 |
| `inventory_v1_consultas_test` | automático | 32 | `entry_en_celda` (snapshot), `celdas_ocupadas_por`, `posicion_valida(..., excluir_item)`; footprint normal/rotado; las consultas no mutan | INV-05, INV-11 |
| `inventory_v1_reubicar_test` | automático | 26 | `_reubicar_entry` cambia `position`/`rotated` in-place; conserva `InventoryEntry`/`ItemInstance`/`instance_id`; `_entries.size()` constante; `contenido_cambiado` 1 vez por mutación (0 si el item no está) | INV-09, INV-10 |
| `inventory_v1_operacion_reubicar_test` | automático | 31 | `solicitar_reubicacion` → `TransferOperation` (`REUBICAR_EN_INVENTARIO`) → validate/commit; positivos (mover, rotar+mover) y negativos (item ajeno, solapamiento, fuera de límites, `can_rotate=false`, rotación geométricamente válida pero prohibida); validate falla → modelo idéntico, sin emisión | INV-09, INV-10, INV-11, INV-13, INV-15 |
| `inventory_v1_vista_test` | automático | 29 | `InventoryGridView`: cantidad de celdas, rect de entries, footprint normal/rotado, re-render tras `contenido_cambiado`, la vista no muta el modelo | INV-05, INV-12 (vista) |
| `inventory_v1_manipulator_test` | automático | 57 | máquina de estados vía transiciones públicas: preview no muta ni emite; rotación tentativa no toca `entry.rotated`; drop válido conserva entry/`instance_id`/size y emite 1 vez; drop solapado/OOB → sigue held, modelo idéntico; `rotar` `can_rotate=false` → `rotacion_rechazada`; `cancelar` con held → modelo idéntico; `item_agarrado()`; INV-09 white-box | INV-09, INV-10, INV-13, INV-15 |
| `inventory_v1_entry_readonly_test` | automático | 29 | `43fc2f4` — barrera estructural de D1: `get_entries()`/`entry_en_celda()` devuelven snapshots (mutarlas no toca el modelo); dos snapshots = objetos distintos, mismo `ItemInstance`; ninguna mutación de snapshot emite `contenido_cambiado`; custodia intacta; reubicación autorizada muta la entry viva in-place (white-box); pickup+devolución preservan `ItemInstance`; 0 ERROR intencionales | INV-09 (interna), INV-16 |
| `inventory_v1_identity_contract_test` | automático | 22 | `29adfa3` — tripwire D8: ciclo pickup → reubicación → devolución conserva la MISMA referencia de `ItemInstance` y de `ItemDefinition`, `instance_id` estable, campos estructurales de `definition` sin cambios; 0 ERROR/printerr intencionales; no imprime nada sobre D8 en el gate | INV-02 / C-D8.1..4 |
| `inventory_v1_rotacion_offset_test` | automático | 50 | fix del punto de agarre al rotar: agarre 1ª/2ª celda, rotar ida/vuelta, mover mouse rotado, 20 rotaciones sin drift, ítem ya rotado al agarrar | (regresión del bug de offset) |
| `inventory_v1_activacion_test` | automático | 40 | gate de activación: inactivo tras `_ready`; cerrado → click/R/mouse no interactúan; cerrar con held → cancela + inerte; reabrir → limpio + procesa input; 10 ciclos abrir/cerrar + spam | INV-12 |
| `inventory_v1_negatives_test` | automático | 65 | suite de aceptación end-to-end a través del manipulator: N1 solapamiento, N2 fuera de límites, N3 `can_rotate=false`, N4 rotar+drop inválido, N5 cerrar con held, N6 invariante de custodia en una sesión, N7 stress; P5 abrir/cerrar sin mutar; P6 reubicar en V1 + devolver al mundo (identidad end-to-end) | INV-09, INV-10, INV-11, INV-12, INV-13, INV-15, INV-16 |
| `inventory_v1_manual_test` | manual (input real) | — | abrir/cerrar UI, agarrar, mover ghost, rotar, soltar (válido/OOB/solapado), `can_rotate=false`, cerrar con held; incluye la mitigación del `UiInventario` legacy | (verificación humana de todo lo anterior) |

### Estado final validado (gate tras Batch B.2, HEAD `29adfa3`)

```
V1 automático (comportamiento):  32 + 26 + 31 + 29 + 57 + 50 + 40 + 65  =  330 chequeos, 0 fallas
Deuda (barrera D1 + tripwire D8): 29 (entry_readonly) + 22 (identity_contract)  =  51 chequeos, 0 fallas
V0:                               22 negativos (0 fallas)  +  ruta feliz (carga OK, 0 errores)
Total: 403 chequeos, 0 fallas. Godot 4.6.3, --headless. Sin warnings de parseo. 0 líneas ERROR: intencionales.
```

El conteo de comportamiento V1 pasó de 328 (`e2e406d`) a 330: `+2` en `inventory_v1_manipulator_test` (chequeo white-box INV-09 + `item_agarrado`). El resto de los conteos no cambió — Batch B/B.2 no alteraron comportamiento.

Además hubo **stress manual** en V1 (mover/rotar/soltar, rechazos, `can_rotate=false`, cerrar con held, gate de UI cerrada, spam de input y de abrir/cerrar) — aprobado sin comportamiento raro.

---

## 15. Bugs encontrados manualmente

### 15.1 — Offset del punto de agarre al rotar
- **Síntoma:** un 2×1 agarrado desde la segunda celda quedaba visualmente desplazado al pasar a 1×2; el cursor caía fuera del ghost. Sin rotación, o agarrando la primera celda, no se veía.
- **Causa:** `_offset_agarre` se calculaba al agarrar como `celda - entry.position` y quedaba expresado en el footprint anterior; al rotar solo cambiaba `_rotacion_tentativa`, no el offset.
- **Solución:** frame canónico (`_agarre_rel_normal`, siempre orientación normal) + `_rel_normal_a_rotada` / `_rel_rotada_a_normal` (90° horario, inversas exactas); el offset efectivo se deriva bajo demanda. No acumula drift (ver sección 11).
- **Test de regresión:** `inventory_v1_rotacion_offset_test` (50 chequeos).

### 15.2 — Input con la UI cerrada
- **Síntoma:** con la UI cerrada, clicks/mouse/R sobre la zona de la grilla seleccionaban/movían/rotaban ítems; al reabrir aparecía un ítem en la mano.
- **Causa:** `CanvasLayer.visible = false` oculta el render pero **no** frena `_input`. El `InventoryManipulator` seguía con `is_processing_unhandled_input() == true` y su `_unhandled_input` solo se guardaba contra `_view == null`.
- **Solución:** estado explícito `_activo` + `activar()`/`desactivar()` + `set_process_unhandled_input()`; `_unhandled_input` con `if not _activo: return`; `desactivar()` cancela cualquier held. El arné llama `activar()`/`desactivar()` en open/close (ver sección 12).
- **Test de regresión:** `inventory_v1_activacion_test` (40 chequeos).

### 15.3 — Ghosting al mover el mouse muy rápido
- **Detalle visual conocido, NO bloqueante.** Al mover el mouse muy rápido se aprecia un leve ghosting/trailing del preview.
- También presente en la UI legacy. No afecta la posición lógica, la validación ni el commit.
- **No es un bug lógico. No se investiga ni se corrige ahora.** (También registrado en la memoria del proyecto.)

---

## 16. Legacy / compatibilidad

- Existe una **UI de inventario legacy** anterior a V0: autoload `UiInventario` → `scenes/components/ui_inventario.tscn` (`CanvasLayer` + `scripts/player n entities/inventory/ui_inventario.gd`). Respaldada por los autoloads `Inventario` y `Catalogo`, que usan clases legacy propias (`ItemInstancia`, etc.), **no** las de `inventory_v2/`.
- Autoloads presentes en toda escena (`project.godot`): `Catalogo`, `Inventario`, `UIHacking`, `UiInventario`, `DebugDraw`.
- `ui_inventario.gd` tiene un `_input` que captura la acción **`toggle_inventario` sin condición** (togglea su `visible` + `Input.set_mouse_mode`). `rotar_item` lo captura solo si su UI está `visible` (arranca `false`).
- **Mitigación en el arné de prueba:** `inventory_v1_manual_test.gd` hace `UiInventario.set_process_input(false)` en `_ready`. Es reversible, solo dura esa escena, no toca ningún archivo compartido.
- **V1 no depende arquitectónicamente de la UI legacy.** El `InventoryManipulator` no usa `toggle_inventario`; el abrir/cerrar lo maneja el arné a nivel pantalla. La arquitectura legacy y la de V0/V1 son sistemas separados que hoy conviven en el proyecto sin integrarse.
- El sistema de interacción genérico (`Interaction`, `InteractionComponent`, `raycast_interaccion.gd`, en `scripts/player n entities/`) **sí** lo usa V0: `WorldItemV2._on_interact` es el contrato de `InteractionComponent`. Los arneses de test lo invocan directamente para sembrar.

---

## 17. Deuda / riesgos conocidos

Deuda **realmente observada** en el código/tests. Estado a HEAD `29adfa3`.

### DEUDA SALDADA

1. **~~`get_entries()` devuelve referencias compartidas~~ — PAGADA (`43fc2f4`, Batch B).** Antes: `_entries.duplicate()` shallow → código externo podía `entry.position = …` y saltarse `LocalAuthority`. Ahora la barrera es **estructural**: `InventoryV2` conserva las `InventoryEntry` vivas en `_entries` y `get_entries()` / `entry_en_celda()` devuelven **snapshots detached** (`InventoryEntry.snapshot()`). Mutar una snapshot no toca el modelo. `_` no era barrera en GDScript; no entregar la referencia viva sí lo es. `TransferOperation._buscar_entry` ahora usa una snapshot (solo lee `.rotated`); la exclusión en `posicion_valida` es por `ItemInstance` (`excluir_item`). "Misma `InventoryEntry`" (INV-09) pasó a invariante interna, verificada white-box.
3. **~~Comentario de cabecera de `inventory.gd` desactualizado~~ — PAGADA (`7463866`, Batch A).** Los comentarios `_celda_ocupada()` inexistente / enmarcado "V0" se corrigieron; solo comentarios `##`.
7. **~~Referencias a un documento de diseño no versionado~~ — PAGADA (`7463866`, Batch A).** Los comentarios que citaban "el encargo" / "doc V0 seccion N" ahora apuntan a este archivo.

### DEUDA CONOCIDA (pendiente)

2. **`LocalAuthority` inyectado manualmente, receptor único.** Se pasa vía `setup()` en cada arné, y el inventario receptor de pickup se fija con `set_inventory_receptor()` (un solo `_inventory_receptor`). No hay targeting real ("a qué inventario / de qué entidad"). Documentado como deliberado en `local_authority.gd`. Se paga cuando exista gameplay concreto de pickup; **no** requiere multiplayer.
4. **Escena de un componente de producción bajo `scenes/test/`.** `inventory_grid_view.tscn` (escena del `Control` `InventoryGridView`, que es producción) vive en `scenes/test/`. Lo instancian ~6 escenas de test. Reubicar + actualizar los `ext_resource path=` (el `uid` no cambia). Planeado para Batch C2, junto con D5.
5. **El manipulator debe cablearse manualmente en cada consumidor.** Depende de ser un hijo `Control` del `InventoryGridView`, alineado, con `mouse_filter = IGNORE` en ambos y `set_input_as_handled()` para `toggle_inventario` en el arné. No está encapsulado en una escena reutilizable. Dirección prevista: un `InventoryPanel` que encapsule solo el wiring V1 existente (Batch C1).
6. **`ItemInstance._siguiente_id` es `static` global de proceso.** Los `instance_id` son únicos por corrida, no persisten, no son por-inventario. **Formalizado en `29adfa3` como C-D8.3/C-D8.4:** `instance_id` es solo aid de logs/tests, ninguna lógica de producción depende de su valor; los tests afirman identidad por **referencia**. Se vuelve deuda real solo si aparece persistencia/red (fuera de alcance). No introducir UUID para esto.
8. **Identidad `ItemInstance` / `ItemDefinition` mutable desde una referencia viva — LIMITACIÓN DELIBERADA (`29adfa3`, Batch B.2).** GDScript 4.6.3 no tiene `private`/`protected`; un consumidor que sostiene un `ItemInstance` puede hacer `ii.definition = otra`, `ii.definition.grid_width = 99`, `ii.instance_id = x`. Auditoría Batch B.2: **0 consumidores en el repo lo hacen** y las 4 reglas de contrato (C-D8.1..4) se cumplen de facto. El filo grave es `ii.definition` (mutar el `.tres` compartido rompería footprint/render/validación para todas las instancias del tipo a la vez). Los tenedores de `ItemInstance` vivo restantes (`WorldItemV2`, `LocalAuthority`, `TransferOperation`) son el core controlado, no puntos de extensión. Cerrarlo de verdad exigiría un registro de handles opacos (≈ otro Batch B de churn) o migrar el modelo a C# (fuerza build .NET en todo el proyecto + CI; descartado). **Se acepta el contrato por convención + tripwire (`inventory_v1_identity_contract_test`).** Hardening ya aplicado en B.2: contrato en comentarios de `item_instance.gd`/`item_definition.gd`; `InventoryGridView.layout_entries()` dejó de exponer `ItemInstance`. **Triggers para revisar:** UI/gameplay nuevo que sostenga un `ItemInstance` más allá de la vista pura; persistencia/save-load o networking; consumidores externos al módulo / segundo equipo.

### Numeración de invariantes con huecos
- `INV-03` e `INV-14` no aparecen en ningún archivo (código ni tests). Probablemente `INV-03` existía en el "encargo" original; `INV-14` fue mencionada en conversaciones de diseño pero nunca llegó a código/tests (la propiedad de custodia acabó siendo **INV-16**). No se rellenan.

### FUERA DE ALCANCE (no es deuda — ver sección 18)

Lo que V0/V1 no implementan a propósito. No falta "arreglarlo": simplemente no es parte de estas versiones.

---

## 18. Fuera de alcance actual

V0/V1 **no** implementan:

- Inventory ↔ Inventory (transferir entre dos inventarios).
- Cofres / contenedores.
- Equipamiento.
- Hotbar.
- Stacks (apilar ítems).
- Peso.
- Crafting.
- Persistencia / save-load.
- Multiplayer / network replication.

Que estén listados acá **no significa que V2 vaya a implementarlos todos**. Es el límite explícito de lo que hoy existe.

---

## 19. Reglas para futuros cambios — "NO ROMPER"

- **El modelo (`InventoryV2._entries`) se muta SOLO vía `TransferOperation.commit()`** (→ `_agregar_entry`/`_quitar_entry`/`_reubicar_entry`). `get_entries()` / `entry_en_celda()` devuelven **snapshots**: mutarlas es inofensivo, pero no cambian nada. No volver a devolver una `InventoryEntry` viva desde una consulta pública.
- **No mutar `ItemInstance` ni `ItemDefinition` desde una referencia viva.** `instance.definition` no se reasigna; los campos de `ItemDefinition` no se escriben en runtime (C-D8.1..4). GDScript no lo impide — es contrato (sección 17, D8). No usar `instance_id` como identidad: la identidad es la **referencia**.
- **No saltarse `LocalAuthority`.** Ningún componente invoca `TransferOperation.validate()/commit()` salvo `LocalAuthority` (INV-08).
- **No hacer `commit()` si `validate()` falló.** El contrato es `request → validate → commit`; un `commit()` sin validate exitoso hace `push_error` y aborta.
- **No crear un `ItemInstance` nuevo durante una reubicación.** La reubicación conserva la misma instancia y la misma `InventoryEntry` (INV-09).
- **No usar visibilidad como sustituto de activación de input.** Ocultar un `CanvasLayer`/`Control` no frena `_input`. Usar `_activo` + `set_process_unhandled_input()` (sección 12).
- **No asumir que el offset de agarre es igual entre footprints rotados.** Guardarlo en frame canónico y transformarlo (sección 11).
- **Re-correr los tests de V0 como regresión** al tocar `TransferOperation`, `InventoryV2` o `LocalAuthority`. Los caminos `MUNDO_A_INVENTARIO` / `INVENTARIO_A_MUNDO` no deben cambiar de comportamiento.
- **`InventoryGridView` es read-only.** Si algo de la vista necesita "escribir", va por el manipulator → autoridad, o no va.

---

## 20. Estado actual

```
HEAD : 29adfa3   (este documento describe hasta acá)

V0        1505ed5  cerrado y pusheado
V1        e2e406d  cerrado y pusheado
Docs      2871f87  primera foto de V0+V1 (ANTERIOR a Batch A)
Batch A   7463866  comentarios: D3, D7, aclara D2/D6
Batch B   43fc2f4  D1 pagada (snapshots detached)
Batch B.2 29adfa3  D8 limitación deliberada + contrato + tripwire + layout sin ItemInstance
V2                 no iniciado, alcance no decidido

Pendiente: Batch C1 (InventoryPanel), Batch C2 (mover inventory_grid_view.tscn + migración selectiva de tests).
```

Al momento de este commit documental, `43fc2f4`, `29adfa3` y el commit de este `.md` están **por delante de `origin/main`** (aún sin push) o recién pusheados según el paso siguiente del plan. Cualquier cambio posterior debe actualizar las secciones afectadas.
