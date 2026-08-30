# Postmortem — InventoryV2

> **Qué es este documento.** Reconstrucción de *por qué* el sistema de inventario nuevo (`InventoryV2`)
> terminó teniendo la forma que tiene. No es un manual de uso — para eso están `docs/inventory_system_v0_v1.md`
> (foto V0/V1) y `docs/player_v2_inventory_integration_c0_c3.md` (foto C0–C3). Este documento cubre **toda**
> la evolución, hasta `HEAD = b3e8ee5` (`SUA-1.6 D` + cierre funcional).
>
> **UNTRACKED por ahora.** Puede pensarse como documentación permanente, pero no se agrega a git todavía.
>
> **No es propaganda.** Donde una decisión tiene tradeoffs, están escritos. Donde algo quedó sobrediseñado,
> lo dice. Donde algo funcionó por las restricciones actuales y no porque sea correcto en general, se distingue.
>
> Fuentes: historial git (`1505ed5` … `b3e8ee5`), `docs/inventory_context_checkpoint.md`, los ~24 tests,
> el código actual, las escenas de integración, y el inventario legacy como referencia histórica.

---

## 1. Resumen ejecutivo

El proyecto tenía un inventario legacy funcional — grilla 15×20, autoload global, pickup/drop/throw, UI —
construido como prototipo en ~11 commits chicos a principios de 2026. Servía, pero su estado vivía en un
Autoload (`Inventario.items`): un solo inventario para todo el proceso, sin noción de *ownership*, imposible
de aislar por entidad o de testear.

`InventoryV2` se construyó de cero al lado del legacy, sin tocarlo. Se hizo en tres grandes tramos:

1. **V0/V1** (`1505ed5` → `2893a70`): el modelo de datos (`ItemDefinition` / `ItemInstance` / `InventoryEntry`),
   el componente-nodo `InventoryV2`, la operación atómica `TransferOperation`, la frontera `LocalAuthority`,
   el mundo↔inventario, y la UI de grilla (`InventoryGridView` + `InventoryManipulator` + `InventoryPanel`).
2. **Integración PlayerV2** (`8bb5420` → `d9a0084`, fases C0–C5): inventario por instancia de entidad,
   routing de pickup por `interaction.actor`, autoridad *stateless*, UI por TAB, y drop de gameplay.
3. **Assets reales** (`feb42f1` → `b3e8ee5`, SUA-1.6 B/C/D): migrar botella, sable y llave del legacy al
   patrón V2. La botella reveló un ciclo de recursos de Godot; el sable demostró que el patrón se repetía sin
   tocar el core; la llave forzó una auditoría que descubrió que la relación "llave → puerta" nunca existió.

Estado final: **`INVENTORYV2 FUNCTIONAL CLOSURE = APPROVED`**. V2 cubre todo lo que el inventario legacy
realmente usaba. El legacy quedó **funcionalmente inerte** pero **deliberadamente conservado en paralelo**,
para retirarlo recién cuando se auditen sus consumidores dentro de sus propios dominios.

Evidencia: gate 459/0 · botella 45/0 · sable 32/0 · llave 36/0 · tripwire de identidad 22/0 · pruebas manuales
aprobadas en cada fase · cero dependencia interna de V2 hacia el legacy (verificado por `grep`).

---

## 2. Contexto

El juego es un proyecto en Godot 4.6.3, un solo desarrollador, con varios sistemas construidos por tramos
(vehículos guiados por path, traversal/parkour, hacking de terminales, inventario). El estilo de trabajo:
commits chicos, pruebas manuales frecuentes, y —cuando un sistema se estabiliza— un documento de arquitectura
o postmortem. Ya existía precedente de postmortem (el sistema de vehículos: `af2480b`, `bdca875`).

Al empezar `InventoryV2` había:

- un inventario legacy jugable (grilla, pickup, throw, UI);
- un sistema de interacción genérico (`Interaction` + `InteractionComponent` + `raycast_interaccion.gd`)
  reconstruido en `6ec7dca`, compartido por puertas, terminales e items;
- un `PlayerV2` que todavía no existía (llegó en `1b9f897`) — el desarrollo apuntaba a reemplazar el
  Player V1 sin hacerlo de golpe.

`InventoryV2` se numeró internamente "V0/V1" en su propia línea, y "SUA-1.3 … 1.6" al integrarse con PlayerV2.
La numeración es confusa a propósito registrarla: **"V0" no significa un primer intento descartado**, significa
la primera versión funcional del sistema nuevo.

---

## 3. Qué tenía el sistema legacy

El inventario legacy (`scripts/player n entities/inventory/`) se construyó entre `2283a43` y `f88f274`
(más `e6a2fb8`, el hacking terminal↔puerta). Piezas:

| Pieza | Qué hacía |
|---|---|
| `Inventario` (autoload) | `items: Array[ItemInstancia]`, grilla 15×20, `agregar_item`, `devolver_item`, placement first-fit |
| `UiInventario` (autoload) | UI de grilla (221 líneas): render, tooltip, pick/place/swap/rotate, drop-fuera-de-la-grilla |
| `Catalogo` (autoload) | dicts `prefabs{int→escena}` + `formas{int→matriz}`, claves 1–4 |
| `TirarItem` (nodo en `player.tscn`) | throw con carga (tecla T): impulso + spin, apuntado por la cámara |
| `Item.gd` | script de root de props recogibles: `_on_interact` → `Inventario.agregar_item` |
| `ItemData` (Resource) | datos por tipo: 11 campos (`nombre`, `peso`, `municion`, `vida`, `item_id`, `fuerza_lanzamiento`, …) |
| `ItemInstancia` (RefCounted) | datos por instancia: 11 campos (`data`, `grid_col/fila`, `municion_actual`, `color` random, …) |

### Por qué probablemente tenía sentido como prototipo

Shipeó un inventario de grilla **jugable** en ~11 commits chicos. Grilla visible, formas de items, rotación,
swap, drop, throw con física. Para un prototipo eso es un buen resultado: cada commit agregaba una cosa
visible y probable a mano. El autoload global era la vía de menor fricción para "que haya un inventario ya".

### Por qué dejó de ser adecuado

**Problemas de arquitectura:**

- **Estado global.** `Inventario.items` = un solo inventario para todo el proceso. "¿De quién es este item?"
  no tiene respuesta. Dos entidades con inventario (dos jugadores, un cofre, un NPC) no pueden coexistir
  sin contaminarse. Imposible aislar por instancia en un test.
- **Responsabilidades mezcladas.** `UiInventario` es presentación + input + máquina de estados de manipulación
  + lógica de drop + acceso al modelo, todo en un archivo. `Inventario` mezcla estado + placement + validación
  + notificación a la UI (`if UiInventario.visible: grilla_sucia = true` — el modelo conoce la vista).
- **Acoplamientos.** `TirarItem` busca al jugador por grupo (`get_first_node_in_group("player")`), toma su
  cámara por path hardcodeado (`player.get_node("Camera3D")`), y saca el prefab de `Catalogo` por `int` id.
- **`Catalogo` como fuente de verdad paralela.** El tipo de un item vivía en dos lados: el `.tres` de `ItemData`
  y el dict de `Catalogo` (forma + prefab), enlazados por un `int item_id`. Desincronizables.

**Limitaciones:**

- Grilla 15×20 hardcodeada (dos constantes duplicadas en `inventario.gd` y `ui_inventario.gd`).
- Sin `request → validate → commit`: `ui_inventario.gd` muta `instancia.grid_col` directo; si algo falla a
  mitad, el estado queda inconsistente.
- Identidad de instancia difusa: `ItemInstancia` mezcla identidad lógica con placement (`grid_col`, `grid_fila`).

**Decisiones de prototipo que no había que conservar:**

- El `color` random por instancia (para teñir celdas) — placeholder de debug, no un color real de item.
- El freeze de movimiento con el inventario abierto (`player.gd`) — decisión de gameplay que V2 revirtió.

**Features que parecían existir pero no estaban usadas:**

- **Footprints no rectangulares.** `Catalogo.formas` acepta matrices arbitrarias (`[[1,0],[1,1]]`); `_caben_todas`
  las itera. **Todas las formas del repo eran rectángulos** (`[[1,1]]×N`). La capacidad existía y nunca se ejerció.
- **`ItemData` de combate** (`municion`, `vida`, `se_puede_romper`, `fuerza_lanzamiento`, `velocidad_angular`).
  `municion`/`vida` se copian a `ItemInstancia._init` **y nunca se leen**. `fuerza_lanzamiento`/`velocidad_angular`
  solo los lee `TirarItem` (que estaba inerte). `peso` **no lo lee nadie**.
- **`ItemInstancia` runtime** (`equipado`, `bloqueado`, `cantidad`): campos por defecto, sin lógica en ningún lado.
- **"llave → puerta".** `puerta.gd._toggle()` recorre `Inventario.items` buscando `item_id == id_llave`. En la
  única puerta real, `id_llave` nunca se configuró (queda `0`) y la única llave es `item_id 1` → el chequeo no
  puede pasar nunca. Y el sistema de puerta que **sí** funciona (terminal + contraseña) saltea ese chequeo.
  **La feature "abrir una puerta con una llave física" nunca estuvo integrada.** (Ver §7.)

---

## 4. Objetivos de InventoryV2

Del mensaje de commit de V0 (`1505ed5`) y la conversación de diseño:

- Un `ItemInstance` existe **o en el mundo 3D** (cuerpo físico recogible) **o en un inventario de grilla**,
  y pasa de un contexto al otro **sin perder identidad lógica**.
- **Custodia XOR**: en todo momento `World = 1 / Inventory = 0` **XOR** `World = 0 / Inventory = 1`. Nunca
  `1/1` (doble custodia) ni `0/0` (item perdido).
- Todas las transiciones **validadas y atómicas** (`request → validate → commit`; si `validate` falla, nada cambia).
- Inventario **por entidad**, no global. Un mundo puede tener N inventarios independientes.
- Autoridad **explícita**: un único punto corre `validate()/commit()`; todo lo demás *solicita*.

**Fuera de alcance desde el día 1** (declarado en `e2e406d`): inventario↔inventario, cofres, equipamiento,
hotbar, stacks, peso, crafting, persistencia/save-load, multiplayer. Esto importa: **casi nada de lo que la
gente llamaría "deuda técnica de InventoryV2" estaba en el alcance.** (Ver §13.)

---

## 5. Evolución cronológica

Fechas reales del historial. Cada fase = un commit con regresión completa.

### Tramo A — V0/V1 (modelo + UI de grilla), 2026-08-27/28

| Commit | Fecha | Qué |
|---|---|---|
| `1505ed5` | 08-27 | **V0.** `ItemDefinition` / `ItemInstance` / `InventoryEntry` / `InventoryV2` / `TransferOperation` (`MUNDO_A_INVENTARIO`, `INVENTARIO_A_MUNDO`) / `LocalAuthority` / `WorldItemV2`. Mundo↔inventario con placement first-fit. 835 líneas, 22 chequeos negativos + prueba manual (6+ ciclos). |
| `e2e406d` | 08-27 | **V1.** UI de grilla: `InventoryGridView` (vista pura read-only), `InventoryManipulator` (máquina de estados held/preview/ghost/rotación). `TransferOperation.REUBICAR_EN_INVENTARIO`. 2843 líneas, 328 chequeos. **Dos bugs encontrados a mano** (§7.3, §7.4). |
| `2871f87` | 08-28 | Doc de arquitectura V0/V1. |
| `43fc2f4` | 08-28 | **Batch B.** `InventoryEntry` con snapshots: `get_entries()` deja de devolver la referencia viva → barrera **estructural**, no por convención de `_`. |
| `29adfa3` | 08-28 | **Batch B.2.** Contrato de identidad de `ItemInstance` (D8) + tripwire test. GDScript no tiene `private`; se acepta convención + tripwire. |
| `51d106f` | 08-28 | **Batch C1.** `InventoryPanel` reusable: encapsula el wiring `GridView + Manipulator` (que se duplicaba en cada consumidor). |
| `cff09fe`, `2893a70`, `b652bbe` | 08-28 | **Batch C2.** Mover la escena del `GridView` a `components/`, migrar el arné manual a `InventoryPanel`, cerrar la deuda V1. |

### Tramo B — Integración PlayerV2 (C0–C5), 2026-08-28/29

| Commit | Fase | Qué |
|---|---|---|
| `1b9f897` | SUA-1.1/1.2 | `PlayerV2` (locomoción) + `InteractionV2`, aislado del Player V1. |
| `8bb5420` | **C0** | `player_v2.tscn` gana `Inventory` / `InventoryAuthority` / `InventoryReceiver` por instancia, cableados por `@export`. `InventoryReceiver` nace inerte. Test de aislamiento A≠B. |
| `2d22cd5` | **C1** | Routing real: `interaction.actor → InventoryReceiver (hijo directo) → LocalAuthority → InventoryV2`. 13 arneses del gate migrados a un actor de prueba. Gate **459/0 idéntico**. |
| `4d05e4c` | **C2** | `LocalAuthority` *stateless*: se borran `_inventory_receptor` / `set_inventory_receptor()` / `_encontrar_inventory_receptor()`; cada operación recibe su `InventoryV2` explícito. `WorldItemV2` neutral (se borran `_authority` / `setup()`). **Cambio neto: −47 líneas.** `TransferOperation` intacto. |
| `61eba68` | **C3** | Sandbox e2e con raycast + input reales. Validado a mano. |
| `f2aa456` | **C4-A** | `PlayerInventoryUI` (`CanvasLayer`) hostea el `InventoryPanel`. Estructural. |
| `4451a5c` | **C4-B0** | Hibernar el `_input` del `UiInventario` legacy: `set_process_input(false)` en su `_ready` (11 líneas). Paso transitorio explícito. |
| `bf09c5b` | **C4-B** | `PlayerInventoryUI` dueño de TAB / ESC-con-panel-abierto, vía `_shortcut_input` (no `_unhandled_input` — §7.5). |
| `eb2381f` | **C4-C** | Sacar de `player_v2.gd` el toggle de `mouse_mode` con ESC (sin reemplazo). |
| `ac05cba` | **C5-A** | `ItemDropper` (capacidad inventario→mundo). **Sin consumidor.** |
| `cfe4ede` | **C5-B** | `InventoryManipulator` emite `drop_fuera_solicitado(item_instance)` al soltar fuera de la grilla. **Señal sin consumidor.** |
| `f27484c` | **C5-B2** | Zona neutra `drop_neutral_margin_px = 24.0`: anillo alrededor de la grilla donde soltar es NO-OP (evita drops accidentales). |
| `d9a0084` | **C5-C** | Conectar `InventoryPanel.drop_fuera_solicitado → PlayerInventoryUI → ItemDropper.soltar`. Ciclo mundo↔inventario cerrado. |

### Tramo C — Assets reales + cierre, 2026-08-30

| Commit | Fase | Qué |
|---|---|---|
| — | **SUA-1.6 A** | Auditoría de migración (sin commit). Censo de props/items/consumidores. |
| `feb42f1` | **1.6 B — botella** | Primer asset real. **Descubre el ciclo de recursos** (§7.1). `ItemDefinition.world_scene` (`PackedScene`) → `world_scene_path` (`String`) + `get_world_scene()` lazy + `world_scene` alias de compat. `WorldItemV2` gana `@export definition` + autoaprovisionamiento. Hole de leak cerrado. 45/0. |
| `8dbfe5b` | **1.6 C — sable** | El patrón se repite. **Cero cambios al core.** Footprint 1×4 (el legacy 2×10 no entra en 4×4). 32/0. |
| `b3e8ee5` | **1.6 D — llave** | Footprint 1×1, `can_rotate=false`. Auditoría que descubre que "llave → puerta" **nunca fue una feature** (§7.2). 36/0. |
| — | auditoría puerta/monitor | terminal→puerta = sistema funcional real; llave→puerta = prototipo roto. Sin commit. |
| — | auditoría profunda legacy + **cierre funcional** | InventoryV2 declarado funcionalmente completo. Legacy = inerte pero conservado en paralelo. Sin commit. |

---

## 6. Decisiones arquitectónicas

Para cada una: contexto · opciones · decisión · razón · resultado · coste · ¿la repetiríamos?

### 6.1 — `InventoryV2` es componente-nodo, NO Autoload

- **Contexto:** el legacy era `Inventario` autoload → un inventario global.
- **Opciones:** (a) autoload nuevo mejor hecho; (b) un `InventoryManager` que mapea entidad→inventario;
  (c) `InventoryV2 extends Node`, hijo de la entidad dueña.
- **Decisión:** (c).
- **Razón:** "¿de quién es este item?" solo tiene respuesta si el estado cuelga de la entidad. Permite N
  inventarios simultáneos y testear aislamiento.
- **Resultado:** el test de aislamiento (C0) instancia dos PlayerV2 y verifica `A.Inventory != B.Inventory`
  byte a byte. La auditoría de cierre pudo afirmar "cero dependencia global" limpiamente.
- **Coste:** cada consumidor necesita cablear su `InventoryV2` explícitamente. Un poco más de `@export`.
- **¿La repetiríamos?** **Sí, sin cambios.** Es la decisión más claramente correcta de todo el sistema.

### 6.2 — Autoridad explícita (`LocalAuthority`)

- **Contexto:** hace falta un único punto que corra `validate()/commit()`.
- **Opciones:** (a) que cada componente llame a `TransferOperation` directo; (b) una frontera `LocalAuthority`
  que todos *soliciten*.
- **Decisión:** (b).
- **Razón declarada:** "el día de mañana una autoridad remota (servidor) podría ocupar ese rol sin reescribir
  `InventoryV2` / `WorldItemV2` / `TransferOperation`".
- **Resultado:** funciona; es el único caller de `validate()/commit()` en todo el repo.
- **Coste:** **a HEAD, `LocalAuthority` es casi un passthrough.** No valida nada por sí mismo (delega en
  `TransferOperation`), su único estado es `_log_habilitado`. Agrega una capa
  (`receiver → authority → operation`) para una feature (multiplayer / arbitraje de N inventarios) **que no
  existe y puede no existir nunca.** Son ~90 líneas de ceremonia si el juego se queda singleplayer.
- **¿La repetiríamos?** **Con cambios.** Empezaría con `InventoryReceiver` / `ItemDropper` llamando a
  `TransferOperation` directo, e introduciría la capa de autoridad **cuando haya una segunda autoridad real**
  (NPC que arbitra, servidor). Sacarla después es fácil; construirla "por si acaso" fue infraestructura
  especulativa. Contra-argumento honesto: es barata, es el chokepoint del invariante de custodia, y la
  disciplina "todo *solicita*, nada ejecuta" se instaló temprano y se mantuvo.

### 6.3 — `TransferOperation` como objeto `request → validate → commit`

- **Contexto:** cambiar custodia debe ser atómico.
- **Opciones:** (a) funciones sueltas (`try_pickup(...) -> bool`); (b) una clase por transferencia con
  `validate()` y `commit()` separados.
- **Decisión:** (b), 3 tipos (`MUNDO_A_INVENTARIO`, `INVENTARIO_A_MUNDO`, `REUBICAR_EN_INVENTARIO`).
- **Razón:** separar "¿se puede?" de "hacelo" hace la atomicidad explícita y testeable; un `validate()` que
  falla garantiza que `commit()` no corre.
- **Resultado:** **cero bugs de estado a medio-transferir** en toda la historia del sistema. Los tests
  negativos verifican "validate falla → modelo idéntico" para los 3 tipos.
- **Coste:** para `MUNDO_A_INVENTARIO` la lógica real son ~15 líneas envueltas en un objeto con 12 campos
  (muchos `null` según el tipo). Mild overdesign — pero de bajo costo.
- **¿La repetiríamos?** **Sí.** La atomicidad explícita valió la pena; nunca tuvimos que debuggear un
  item duplicado o perdido. Si las operaciones fueran más simples (sin devolución de mundo, sin reubicación)
  bastaría una función.

### 6.4 — `ItemDefinition` vs `ItemInstance` vs `InventoryEntry` (tres clases)

- **Contexto:** el legacy mezclaba tipo, instancia y placement en `ItemData` + `ItemInstancia`.
- **Opciones:** (a) una clase con todo; (b) dos (tipo + instancia); (c) tres (tipo + instancia + placement).
- **Decisión:** (c). `ItemDefinition` (Resource, tipo) · `ItemInstance` (RefCounted, esta copia) ·
  `InventoryEntry` (RefCounted, dónde está colocada en ESTE inventario).
- **Razón:** cambian a ritmos distintos. El tipo nunca cambia en la partida. La identidad de la instancia
  nunca cambia. El placement cambia cada vez que se mueve. Y **el mismo `ItemInstance` que está en el mundo
  no tiene `position` ni `rotated`** — las coordenadas de grilla no pertenecen a la instancia.
- **Resultado:** el ciclo mundo→inventario→mundo→inventario preserva la MISMA referencia `ItemInstance` en
  los 3 assets reales; el `InventoryEntry` se crea y destruye alrededor.
- **Coste:** tres clases para lo que el legacy hacía con dos. Un poco más de indirección al leer.
- **¿La repetiríamos?** **Sí.** "Separar identidad de ubicación" resultó ser uno de los principios más
  reutilizables (§14). El legacy `ItemInstancia` tenía `grid_col`/`grid_fila` encima — eso es exactamente
  lo que no hay que hacer.

### 6.5 — Identidad por REFERENCIA, no por id

- **Contexto:** hace falta saber "¿este `ItemInstance` es el mismo que estaba en el mundo?".
- **Opciones:** (a) un `id` (int/UUID) como clave de identidad; (b) la referencia del objeto (`==`).
- **Decisión:** (b). `instance_id` existe pero **solo como aid de logs/tests** (contador `static` por proceso).
- **Razón:** en GDScript los `RefCounted` se comparan por referencia gratis; un id agrega una fuente de
  verdad que hay que mantener sincronizada.
- **Resultado:** todos los tests afirman identidad con `==`. `instance_id` se degradó explícitamente en
  `29adfa3` (C-D8.3): "ninguna rama de lógica de producción depende de su valor".
- **Coste:** `instance_id` es un `static` mutable global de proceso. No persiste, no es estable entre corridas.
- **¿La repetiríamos?** **Sí para singleplayer.** Save/load o red obligarían a introducir un id estable
  aparte — pero eso es un problema real cuando exista, no ahora. La regla escrita: "no introducir UUID para esto".

### 6.6 — Custodia XOR como invariante explícita

- **Contexto:** un item no puede estar en dos lados ni en ninguno.
- **Decisión:** invariante `World=1/Inv=0 XOR World=0/Inv=1`, verificada por los tests negativos ("nunca 1/1
  ni 0/0") y por helpers `_custodia()` en los tests de assets reales.
- **Razón/Resultado:** hace que "item duplicado" y "item perdido" sean condiciones que un test detecta, no
  bugs que aparecen en gameplay.
- **Coste:** casi nulo — es una propiedad, no código.
- **¿La repetiríamos?** **Sí.** Invariante barata y potente. Reutilizable en cualquier sistema con transferencia
  de custodia (equipamiento, cofres).

### 6.7 — `WorldItemV2` neutral

- **Contexto:** en V0 el `WorldItemV2` guardaba una `_authority` inyectada por `setup()`.
- **Decisión (C2):** el `WorldItemV2` **no guarda actor, inventario ni autoridad**. Quién lo recoge se
  resuelve SOLO en el momento de la interacción (`interaction.actor → InventoryReceiver`).
- **Razón:** un item en el suelo no "pertenece" a nadie hasta que alguien lo levanta. Pre-atarlo a una
  autoridad impide que otra entidad lo recoja.
- **Resultado:** los `WorldItemV2` que crea un drop nacen neutrales; cualquier actor con `InventoryReceiver`
  los puede levantar. Los tests verifican "sin campo `_authority`".
- **Coste:** −24 líneas en `world_item.gd` (C2). Negativo.
- **¿La repetiríamos?** **Sí.** V0 lo hizo mal (pre-binding) y C2 lo corrigió; el estado final es el correcto.

### 6.8 — Root `PlayerV2` sin script

- **Contexto:** ¿dónde vive el "conocimiento del Player"?
- **Opciones:** (a) un script coordinador en el root que sabe de todo; (b) nada en el root, cada capacidad
  es un componente cableado por `@export`.
- **Decisión:** (b). El root `PlayerV2` (`Node3D`) no tiene script. `Body` (`CharacterBody3D`) tiene la
  locomoción y **no conoce** el inventario.
- **Razón:** evitar el god-object. El root es identidad lógica, no un controlador.
- **Resultado:** `player_v2.gd` no referencia inventario/autoridad/receiver. El cableado es 4 líneas de
  `node_paths` en la escena. Auditar dependencias es un `grep`.
- **Coste:** el cableado vive en la escena, no en código — menos visible en un diff, más frágil ante renombres
  de nodos.
- **¿La repetiríamos?** **Sí.** Es la misma filosofía que "cada sistema dueño de su dominio". Un god-object
  en el Player habría absorbido inventario + interacción + UI + daño + audio.

### 6.9 — `InventoryReceiver` (mundo → inventario)

- **Contexto:** ¿cómo encuentra un `WorldItemV2` el `InventoryV2` del actor que lo levanta, sin ruta rígida,
  grupo global ni coordinador en el root?
- **Opciones:** (a) `get_node("../Inventory")` desde el world item; (b) un grupo `"inventory"`; (c) un
  Service Locator; (d) un componente `InventoryReceiver` hijo directo del actor, que el world item resuelve
  igual que `InteractionV2` resuelve un `InteractionComponent` hijo del collider.
- **Decisión:** (d).
- **Razón:** simetría estructural con el sistema de interacción ya existente. Sin nombres de nodo, sin grupos,
  sin globals.
- **Resultado:** `WorldItemV2._resolver_receiver(actor)` escanea los hijos directos del actor. Funciona para
  N entidades. Es lo que permite que el core no tenga ninguna referencia a "Player".
- **Coste:** un componente más en la escena de cada entidad con inventario. Y el nombre chocó con
  `LocalAuthority._inventory_receptor` (resuelto por documentación, no renombrando — decisión discutible).
- **¿La repetiríamos?** **Sí.** El patrón "capacidad = componente hijo directo, resuelto por escaneo de tipo"
  es reutilizable y consistente con lo que ya había.

### 6.10 — `ItemDropper` separado; drop ≠ throw

- **Contexto:** el legacy tenía `TirarItem` (throw con impulso). PlayerV2 necesitaba sacar items al mundo.
- **Opciones:** (a) `ItemDropper` hace drop Y throw; (b) `ItemDropper` solo drop, throw es otra capacidad.
- **Decisión:** (b). `ItemDropper.soltar()` deja el item en un `DropPoint` (Marker3D bajo el Body, sin
  impulso, sin apuntado). Throw quedó como `ItemThrower` futuro.
- **Razón:** son intenciones distintas. Drop = "lo dejo al lado mío". Throw = "lo arrojo hacia donde miro,
  con fuerza". Mezclarlas obliga a que el drop conozca la cámara y la carga.
- **Resultado:** `ItemDropper` es ~65 líneas, sabe solo de `DropPoint` y `LocalAuthority`. Throw se difiere
  limpio, sin contaminar.
- **Coste:** throw sigue sin existir en PlayerV2 (existía inerte en el legacy).
- **¿La repetiríamos?** **Sí.** "Separar intención de ejecución" y "no meter throw en drop porque comparten
  la palabra 'tirar'" — el usuario lo pidió explícitamente y fue correcto.

### 6.11 — UI desacoplada (`GridView` / `Manipulator` / `Panel` / `PlayerInventoryUI`)

- **Contexto:** el legacy `UiInventario` era un archivo con todo.
- **Decisión:** cuatro piezas. `InventoryGridView` (vista pura read-only, nunca muta). `InventoryManipulator`
  (máquina de estados de manipulación; toda reubicación pasa por `LocalAuthority`). `InventoryPanel`
  (composición reusable de las dos, reenvía señales 1:1, cero lógica de modelo). `PlayerInventoryUI`
  (input/foco del Player local: TAB, `mouse_mode`).
- **Razón:** que un NPC o un cofre puedan usar `InventoryPanel` sin arrastrar la lógica de TAB del jugador.
- **Resultado:** `InventoryPanel` tiene su propio test (56/0). `PlayerInventoryUI` es específico del Player.
- **Coste:** cuatro archivos para lo que el legacy hacía en uno. Y **`InventoryManipulator` quedó con mucha
  superficie de test white-box** (los tests tocan `_agarre_rel_normal`, `_unhandled_input`, `_region_de_drop`).
  Refactorizar el manipulator rompe tests que afirman internals.
- **¿La repetiríamos?** **Con cambios.** La separación GridView/Manipulator/Panel está bien. Reduciría el
  acoplamiento de los tests a los internals del manipulator — algunos de esos tests (offset de rotación, 50
  chequeos) valen mucho porque guardan un bug real; otros prueban plumbing.

### 6.12 — Zona neutra de drop (24 px)

- **Contexto:** al soltar un item held justo afuera del borde de la grilla, se disparaba un drop accidental.
- **Decisión (C5-B2):** un anillo de `drop_neutral_margin_px = 24.0` alrededor de la grilla donde soltar es
  **NO-OP absoluto** (el item sigue held). GRILLA → reubicar; ZONA NEUTRA → nada; EXTERIOR → intención de drop.
- **Razón:** UX. Soltar el mouse 3 px afuera de la grilla no debería tirar tu item al mundo.
- **Resultado:** `_region_de_drop(pos_local)` clasifica en 3 regiones con geometría real en píxeles.
  Aprobado en prueba manual. El valor 24 se ajustó por sensación, no está atado a `cell_size`.
- **Coste:** ~30 líneas más en el manipulator, un `@export` más, y una convención de bordes de `Rect2` que
  hay que documentar (sup-izq inclusive, inf-der exclusive).
- **¿La repetiríamos?** **Sí, pero es un detalle de pulido, no de arquitectura.** Vale registrar que apareció
  de una prueba manual — no lo habríamos previsto de un diseño en papel.

### 6.13 — Capa de interacción compartida legacy ↔ V2

- **Contexto:** `InteractionComponent` + `Interaction` ya existían (reconstruidos en `6ec7dca`), usados por
  puertas, terminales e items legacy.
- **Decisión:** **no** hacer una capa de interacción nueva para V2. `WorldItemV2` implementa el mismo contrato
  `_on_interact(interaction) -> Variant`.
- **Razón:** la interacción es infraestructura compartida; el *significado* de cada interacción es del dueño.
- **Resultado:** cero migración de interacción para los props. `InteractionV2` (PlayerV2) resuelve el
  `InteractionComponent` como hijo directo del collider; el legacy sube por ancestros. Ambos funcionan.
- **Coste:** ninguno — fue una decisión de *no* construir algo.
- **¿La repetiríamos?** **Sí.** Es el ejemplo más limpio del principio "compartimos infraestructura, no
  significado".

### 6.14 — `world_scene_path` lazy (rompe el ciclo de recursos)

- **Contexto:** ver §7.1. Un prop tipado referencia su `ItemDefinition`, y el `ItemDefinition` referenciaba
  la escena del prop como `@export var world_scene: PackedScene` → ciclo duro de recursos que Godot no
  resuelve en carga fría.
- **Opciones:** (a) el prop no referencia su `ItemDefinition` (algo externo lo inyecta); (b) el `ItemDefinition`
  guarda un `String` path y resuelve lazy; (c) `world_scene` apunta a una escena distinta de la del prop
  (rompe "el item droppeado ES el prop autor"); (d) capturar la escena de origen en el `ItemInstance`.
- **Decisión:** (b). `@export_file("*.tscn") var world_scene_path: String` + `get_world_scene()` que hace
  `load()` lazy. Se mantiene `world_scene` como **alias de solo lectura** (`get:` sin `set:`) para no tocar
  19 arneses de test que leen `definition.world_scene`.
- **Razón:** el path como `String` no es una arista de `ext_resource` → el parser no ve el ciclo. El ciclo
  *semántico* sigue existiendo (y está bien); el de *dependencias del parser* no.
- **Resultado:** los 3 assets reales cargan en frío sin `Parse Error`. `TransferOperation` usa
  `get_world_scene()` y no sabe que hay un String detrás.
- **Coste real:** **dos nombres para la misma cosa** (`world_scene` y `get_world_scene()`). El alias de compat
  se etiquetó "opcional / no urgente" — lo que probablemente lo hace permanente. Es exactamente el tipo de
  "dos formas de hacer lo mismo" que la política del proyecto desaprueba. Deuda que elegimos a conciencia.
- **¿La repetiríamos?** **Sí la solución, no el camino.** Si hubiéramos probado con un asset real en V0, el
  ciclo aparece 15 commits antes y `world_scene` es un path desde el principio, sin alias.

### 6.15 — Autoaprovisionamiento de `WorldItemV2`

- **Contexto:** un `WorldItemV2` colocado directamente en una escena (un prop en un nivel) no tiene quién le
  inyecte su `ItemInstance` — en los tests/sandboxes lo hacía el arné.
- **Decisión:** `@export var definition: ItemDefinition` + `_ready()`: `if item_instance == null and
  definition != null: item_instance = ItemInstance.new(definition)`. Un `item_instance` inyectado siempre gana.
- **Razón:** que "poner el prop en la escena" sea suficiente, sin un paso de inyección.
- **Resultado:** los 3 assets reales se autoaprovisionan; los tests que inyectan siguen andando.
- **Coste:** `WorldItemV2` gana un `@export` y un `_ready`. Y un fail-fast local en `_solicitar_pickup`
  (`if item_instance == null: return false`) que técnicamente es redundante con la validación de
  `TransferOperation` — se agregó por localidad/claridad.
- **¿La repetiríamos?** **Sí.** Es aditivo y no toca la neutralidad del world item.

### 6.16 — Legacy congelado en paralelo (en vez de retirarlo)

- **Contexto:** tras B/C/D el inventario legacy quedó **funcionalmente inerte** (ningún item entra a
  `Inventario.items`; `UiInventario.visible` nunca es `true`; `TirarItem` no tiene nada que tirar). La
  auditoría propuso una secuencia de retiro (E→F→G: neutralizar consumidores → borrar scripts → borrar autoloads).
- **Opciones:** (a) ejecutar el retiro escalonado; (b) dejar el legacy congelado en paralelo.
- **Decisión:** (b). El usuario cambió la estrategia: el retiro obligaría a **modificar sistemas vecinos
  (`player.gd`, `puerta.gd`, `Item.gd`, HUD) solo para facilitar la limpieza del inventario** — y esos
  archivos pertenecen a otros dominios que se revisarán cuando les toque.
- **Razón:** "no modificar un sistema vecino solo porque mantiene una referencia muerta". Se prefiere deuda
  explícita/congelada antes que generar híbridos nuevos.
- **Resultado:** `INVENTORYV2 FUNCTIONAL CLOSURE = APPROVED` sin tocar nada fuera del inventario. El legacy
  queda como referencia histórica ejecutable.
- **Coste:** el proyecto carga 3 autoloads inertes (`Inventario`, `UiInventario`, `Catalogo`) + ~500 líneas
  de código muerto. Un dev nuevo puede confundirse ("¿cuál inventario es el bueno?"). Los `.tres` de
  `ItemData` huérfanos quedan en el árbol.
- **¿La repetiríamos?** **Sí.** Es probablemente la conclusión más importante del postmortem (§10, §14).

---

## 7. Qué salió mal

### 7.1 — El ciclo duro de recursos `.tscn → .tres → PackedScene → .tscn`

- **Qué creíamos:** que un prop podía referenciar su `ItemDefinition` de forma tipada (`@export definition`)
  y el `ItemDefinition` referenciar la escena del prop (`@export world_scene: PackedScene`), porque los
  `.tres` de test (`item_definition_test.tres`) ya referenciaban `test_item_v0.tscn` sin problema.
- **Qué observamos:** al instanciar `botella_standar_1.tscn` en frío (headless), Godot tiraba
  `Parse Error: [ext_resource] referenced non-existent resource` en **ambas** direcciones,
  `Failed loading resource: botella.tres`, y `botella.definition` llegaba `null` → crash al interactuar.
  **El pase de importación del editor NO reportaba nada** — el fallo aparecía solo al cargar la escena de verdad.
- **Qué era realmente:** `item_definition_test.tres` era **unidireccional** — el `.tres` apuntaba a la escena,
  pero `test_item_v0.tscn` **nunca apuntaba de vuelta**. `botella` fue el primer par **bidireccional**. El
  parser de texto de Godot, al cargar A, debe resolver cada `ext_resource` antes de terminar A; si B también
  referencia A (no terminado), lo marca "non-existent".
- **Cómo lo solucionamos:** un lado deja de ser una arista de recurso. `ItemDefinition` guarda el path como
  `String` y resuelve la `PackedScene` con `load()` lazy en runtime, cuando ya no hay ciclo. Hubo **dos
  correcciones de rumbo dentro de la misma fase**: primero propuse poner el path en `WorldItemV2`; el usuario
  pidió una variante más limpia (path en `ItemDefinition`); al implementarla descubrí que eliminar `world_scene`
  rompía 19 arneses de test → el usuario eligió mantener `world_scene` como getter de compat.
- **Cómo detectar algo parecido antes:** **probar con un asset real, no con un fixture, lo antes posible.**
  Un fixture minimalista (`test_item_v0`) no ejerció la relación bidireccional. Regla: si dos archivos de
  recurso se van a referenciar mutuamente, uno de los dos lados es lazy (path/uid + `load()`), y eso se decide
  antes de crear el segundo archivo.

### 7.2 — Asumir que "llave → puerta" era un consumidor funcional

- **Qué creíamos:** la auditoría SUA-1.6 A dijo "migrar la llave junto con la puerta" porque
  `puerta.gd` recorre `Inventario.items` buscando `item_id == id_llave`. Se registró como un consumidor
  externo funcional del inventario legaco.
- **Qué observamos:** cuando llegó el turno (SUA-1.6 D), el usuario corrigió: esa feature nunca estuvo
  integrada. Al investigar: `door_rust_01` en `movement_test` tiene `requiere_llave = true` pero **`id_llave`
  nunca se configuró** (queda `0`), y la única llave es `item_id = 1` → el chequeo no puede pasar nunca. El
  sistema de puerta que **sí** funciona es monitor/terminal + contraseña (`e6a2fb8`, meses antes), y ese
  camino **saltea** el chequeo de llave (`desbloquear()` pone `desbloqueada = true` antes de `_toggle()`).
- **Qué era realmente:** código de prototipo abandonado. `puerta.gd` tiene la *forma* de un gate de llave,
  pero la única puerta real nunca fue cableada para usarlo. Cero tests, cero prueba manual, cero nivel donde
  el jugador recoja la llave y abra la puerta.
- **Cómo lo solucionamos:** migrar la llave como un `WorldItemV2` cualquiera, **sin tocar `puerta.gd`**. Una
  feature "llave → puerta" real quedó registrada como trabajo NUEVO de dominio puerta.
- **Cómo detectar algo parecido antes:** **"hay una función que hace X" ≠ "X es una feature integrada".**
  Para cada consumidor, verificar la cadena completa: ¿está cableado en una escena real? ¿es alcanzable?
  ¿hay una prueba (aunque sea manual) de que produce el efecto? La auditoría profunda del §9.6 del checkpoint
  agregó exactamente esas columnas (`¿cableado? ¿alcanzable? ¿usado? ¿funciona?`).

### 7.3 — Offset del punto de agarre al rotar (bug de V1, encontrado a mano)

- **Síntoma:** un item 2×1 agarrado desde la segunda celda quedaba visualmente desplazado al rotar a 1×2;
  el cursor caía fuera del ghost.
- **Causa:** el offset de agarre se calculaba al agarrar como `celda - entry.position`, expresado en el
  footprint de ese momento; al rotar solo cambiaba `_rotacion_tentativa`.
- **Solución:** guardar el offset en un **frame canónico** (siempre orientación normal, `_agarre_rel_normal`)
  y derivar el offset efectivo bajo demanda con transformaciones 90° que son inversas exactas → sin drift
  acumulado al alternar la rotación N veces.
- **Cómo detectar antes:** solo apareció en la **prueba manual del Paso 5**. Un test automático no lo
  encontró porque la geometría del ghost es visual. Lección: los aspectos visuales/de feel necesitan prueba
  manual; el test de regresión (`inventory_v1_rotacion_offset_test`, 50 chequeos) se escribió **después**,
  para el frame canónico.

### 7.4 — Input con la UI cerrada (bug de V1, encontrado a mano)

- **Síntoma:** con la UI cerrada, clicks sobre la zona de la grilla seguían seleccionando/moviendo/rotando
  items; al reabrir aparecía un item en la mano.
- **Causa:** `CanvasLayer.visible = false` oculta el render pero **no** frena `_input`. El `InventoryManipulator`
  seguía procesando `_unhandled_input`.
- **Solución:** estado explícito `_activo` + `activar()`/`desactivar()` + `set_process_unhandled_input()`;
  `desactivar()` cancela cualquier held.
- **Cómo detectar antes:** de nuevo, prueba manual. La regla que salió: **"ocultar ≠ desactivar" en Godot** —
  cualquier componente con `_input`/`_unhandled_input` necesita un gate de activación explícito.

### 7.5 — `_unhandled_input` vs `_shortcut_input` para TAB/ESC (C4-B)

- **Qué creíamos:** que `PlayerInventoryUI` manejaría TAB/ESC en `_unhandled_input`, como cualquier UI.
- **Qué observamos:** en el orden reverse-tree de propagación (`Interaction → Body/player_v2.gd →
  InventoryManipulator → PlayerInventoryUI`), `player_v2.gd` (más profundo, en el `Body`) recibiría el ESC
  **antes**. Con `_unhandled_input`, ESC-con-panel-abierto haría que PlayerV2 recapture el mouse **antes** de
  que el panel se cierre → estado inválido (panel abierto + mouse capturado, y el manipulator necesita cursor
  libre).
- **Qué era realmente:** un malentendido del orden de propagación de input de Godot.
- **Cómo lo solucionamos:** `PlayerInventoryUI` usa `_shortcut_input`, que corre **antes de TODO
  `_unhandled_input`**. Consume TAB siempre + ESC-cuando-el-panel-está-abierto, marca handled, y `player_v2.gd`
  nunca los ve.
- **Cómo detectar antes:** escribir el orden de propagación explícito para la escena antes de decidir dónde
  va cada handler. (El checkpoint lo documenta ahora.)

### 7.6 — Bugs de los propios arneses de test

Varios, ninguno de arquitectura, todos de autoría de tests:

- **C0:** un lambda `func(): contador += 1` con `contador` local → GDScript captura locales **por valor**,
  el contador nunca incrementaba. Fix: promover a variable miembro.
- **C4-B:** eventos de teclado sintéticos con solo `physical_keycode`. `ui_cancel` (built-in) bindea por
  `keycode` → no lo reconocía. Fix: setear ambos.
- **C5-B:** un `Edit` que reemplazó el bloque de señales pero **olvidó la línea `signal
  drop_fuera_solicitado(...)`** → parse error. Fix: agregarla.
- **botella:** `_ready()` llamaba a tres funciones con `await` adentro sin `await` en la llamada → las tres
  corrían "en paralelo" y `get_tree().quit()` se disparaba a mitad. Fix: `await _funcion()`.
- **botella:** una aserción `b1.item_instance.definition == ...` sin guardar `item_instance != null` → cuando
  el ciclo de recursos dejaba `definition` nulo, el test **crasheaba** en vez de reportar la falla.

**Lección:** los tests contractuales valen mucho, pero **los tests también tienen bugs**, y un test que
crashea al diagnosticar una falla es peor que uno que la reporta. Guardar siempre los dereferences en las
aserciones.

### 7.7 — Near-miss de proceso: `project.godot` modificado por accidente

Durante una prueba manual de C5-B2, el editor cambió `run/main_scene` (F5 "Run Project" en vez de F6 "Run
Current Scene"). Lo detectó la instrucción permanente del usuario "si aparece un cambio inesperado, frená y
reportá". Se revirtió con `git checkout -- project.godot` antes del commit. **No llegó a un commit**, pero
muestra que el editor de Godot puede tocar archivos versionados sin que uno lo pida.

### 7.8 — Supuestos del legacy que descubrimos que NO había que conservar

| Supuesto | Realidad |
|---|---|
| "Los campos de combate de `ItemData` (`peso`, `municion`, `vida`) necesitan equivalente en V2" | Todos muertos o de otros dominios (encumbrance, armas, durabilidad). Ninguno se lee. **No portar.** |
| "`Catalogo` hay que decidir su destino" | Es peso muerto puro. Solo sirve código muerto. Muere con el resto del legacy. |
| "El footprint legacy del item es la especificación" | El legacy usaba 15×20; V2 usa 4×4. Botella 2×5 y sable 2×10 **no entran**. Hubo que re-decidir footprints por proporción física. **No agrandar la grilla para conservar el legacy.** |
| "Los footprints no rectangulares son una capacidad a preservar" | Nunca se usó una sola forma no rectangular en todo el repo. |
| "El inventario legacy inmoviliza al jugador con la UI abierta, replicar eso" | Decisión de gameplay que V2 revirtió a propósito: el inventario **no** inmoviliza (WASD/salto siguen). |

---

## 8. Qué salió bien

- **Tests contractuales/negativos desde el día 1.** V0 shipeó con 22 chequeos negativos ("pickup sin espacio →
  el item queda en el mundo"; "custodia nunca 1/1 ni 0/0"). V1 con 328. El gate acumulado (459/0) se mantuvo
  **idéntico** a través de ~13 commits de integración PlayerV2 — cualquier regresión habría cambiado un conteo.
- **`validate/commit` atómico.** Cero bugs de "item a medio transferir" en toda la historia del sistema.
- **Identidad por referencia.** Sobrevivió cada fase, cada asset. `instance_id` se degradó explícitamente a
  aid de logs. El ciclo mundo↔inventario↔mundo preserva la MISMA referencia en botella, sable y llave.
- **Cableado explícito (`@export` node_paths).** No hay lookups mágicos. Auditar "¿V2 depende del legacy?"
  fue un `grep` que devolvió **solo comentarios**.
- **Integración incremental con regresión por commit.** Cada fase C0–C5 y B/C/D: un commit, gate completo,
  reporte. Reversible de a poco.
- **Escenas de integración reales + prueba manual obligatoria por fase.** El sandbox de C3 y los
  `*_integration.tscn` de B/C/D. La prueba manual encontró el ciclo de recursos, el bug de input-con-UI-cerrada
  y el offset de rotación — **tres cosas que ningún test automático encontró.**
- **Congelar el core después de la botella.** SUA-1.6 C (sable) y D (llave) tocaron **cero archivos de core** —
  commits de 8 archivos, todos aditivos (nueva escena + nuevo `.tres` + nuevo test + escena de integración).
  Eso *demostró* que el patrón era reutilizable, no solo lo afirmó.
- **Usar sable y llave para probar reutilización, no solo para tener más items.** El sable validó "el patrón
  se repite sin core changes". La llave validó "1×1 no rotable" + forzó la auditoría puerta.
- **Auditar antes de migrar consumidores.** La auditoría puerta/monitor evitó una reescritura de `puerta.gd`
  para una feature que no existía.
- **Legacy en paralelo en vez de contaminar V2.** El cierre pudo afirmar "cero dependencia interna V2→legacy"
  sin asteriscos.

---

## 9. El punto de inflexión: assets reales

Hasta SUA-1.6 B, todo se probó con `test_item_v0.tscn` — un `WorldItemV2` minimalista: `RigidBody3D` +
`BoxShape3D` + `BoxMesh` + `InteractionComponent`, sin `@export definition`, con el `ItemInstance` inyectado
por el arné. Funcionaba perfecto. Y ocultaba tres cosas:

1. **El ciclo de recursos.** `test_item_v0` nunca referenció su `ItemDefinition` de vuelta (el `.tres` lo
   referenciaba a él, unidireccional). La botella — un prop real que necesita saber su propio tipo — cerró
   el ciclo. **Sin un asset real, esto no aparece.** Y cuando apareció, fue un cambio de contrato del core
   (`world_scene` → `world_scene_path`) que hubo que hacer con la migración ya en curso.

2. **El autoaprovisionamiento.** `test_item_v0` siempre recibía su `ItemInstance` de un arné. Un prop en un
   nivel no tiene arné. Hasta la botella, "¿de dónde saca su `ItemInstance` un prop colocado en el editor?"
   era una pregunta sin responder porque nunca se había planteado.

3. **La geometría real como decisión de contenido.** `test_item_v0` es 2×1 arbitrario. La botella (cilindro
   de 1.1 m), el sable (hoja de 1.82 m) y la llave (0.38 m) tienen proporciones reales que **no entran** en
   la grilla 4×4 con sus footprints legacy (2×5, 2×10, 2×1). Cada uno forzó una decisión: ¿1×3? ¿1×4? ¿1×1?
   `can_rotate` sí/no. Eso es diseño de item, y solo aparece con items de verdad.

**Por qué fue arquitectónicamente importante:** un fixture minimalista prueba que las piezas *encajan*. Un
asset real prueba que el sistema *sirve para lo que existe*. El fixture pasó por alto un ciclo de dependencias,
un contrato faltante y tres decisiones de contenido. La regla que sale: **meter un asset real (aunque sea
uno) lo antes posible, no al final.**

El sable y la llave, en cambio, salieron bien justamente **porque** la botella ya había pagado el costo. El
sable no tocó el core. La llave tampoco. Eso es la señal de que el patrón estaba listo — y la razón para
congelar el core en ese punto.

---

## 10. Auditoría del legacy y cambio de estrategia

La postura sobre el legacy evolucionó en tres etapas:

**Etapa 1 — "migrar / retirar el legacy".** El encuadre inicial de SUA-1.6 era "integrar el inventario nuevo
y eliminar finalmente el legacy basado en Autoload". Implícito: el legacy es una especificación que hay que
portar, y su presencia es un problema a resolver ya.

**Etapa 2 — "auditar qué hace realmente cada pieza".** La auditoría profunda (§9.6 del checkpoint) encontró
que tras B/C/D el inventario legacy quedó **funcionalmente inerte**: ningún item entra a `Inventario.items`
(los props recogibles migraron; los no recogibles nunca llamaban a `agregar_item`), `UiInventario.visible`
nunca se pone `true`, `TirarItem` no tiene nada que tirar. Y campo por campo, casi todo `ItemData`/`ItemInstancia`
era código muerto o pertenecía a dominios que no existen.

**Etapa 3 — la decisión final.** El usuario cambió la estrategia de cierre: **no** ejecutar la secuencia de
retiro (E→F→G), porque eso obligaría a modificar `player.gd`, `puerta.gd`, `Item.gd`, `hud.gd` — **sistemas
vecinos** — únicamente para facilitar la limpieza del inventario. Eso contradice la política arquitectónica.

**Conclusión (una de las principales del postmortem):**

> El legacy es **referencia ejecutable, NO especificación obligatoria.**
>
> Un sistema viejo puede: **portarse · reescribirse · rescatarse parcialmente · descartarse · diferirse.**
>
> Y puede **permanecer congelado en paralelo** hasta que llegue el turno de auditar sus consumidores dentro
> de sus propios dominios. Se elimina recién cuando (1) sus consumidores externos fueron auditados en sus
> dominios, (2) sus dependencias tienen contratos nuevos estables, (3) se puede borrar **sin adaptadores
> temporales ni contaminar el sistema nuevo.**
>
> **Deuda explícita/congelada > híbrido permanente.**

---

## 11. Arquitectura final

```
                        ┌─────────────────────────────────────────────┐
   MUNDO 3D             │  InventoryV2 (por entidad)                   │
   ┌──────────────┐     │  ┌───────────────┐   ┌────────────────────┐  │
   │ WorldItemV2  │     │  │ InventoryV2   │   │ LocalAuthority     │  │
   │ (RigidBody3D)│     │  │  _entries[]   │◄──│  único caller de   │  │
   │ + definition │     │  │  grid W×H     │   │  validate/commit   │  │
   │ + Interaction│     │  └───────────────┘   └─────────┬──────────┘  │
   │   Component  │     │         ▲                      │             │
   └──────┬───────┘     │         │           ┌──────────▼──────────┐  │
          │             │  ┌──────┴────────┐  │ TransferOperation   │  │
   E ►────┤             │  │ InventoryEntry│  │  request→validate→  │  │
   InteractionV2        │  │  position     │  │  commit (atómico)   │  │
          │             │  │  rotated      │  │  3 tipos            │  │
          ▼             │  └───────────────┘  └─────────────────────┘  │
   _on_interact(&"usar")│                                              │
          │             │  ┌─────────────────────────────────────────┐ │
          ▼             │  │ UI (desacoplada)                        │ │
   InventoryReceiver ───┼─►│  GridView (read-only) ◄─ Manipulator    │ │
   (hijo directo        │  │        ▲                (held/preview/   │ │
    del actor)          │  │        │                 rotación/drop) │ │
          │             │  │  InventoryPanel (composición, señales 1:1)│ │
          ▼             │  │        ▲                                │ │
   solicitar_pickup ────┘  │  PlayerInventoryUI (TAB, mouse_mode,    │ │
                           │   puente drop_fuera_solicitado→Dropper) │ │
   ItemDropper ◄───────────┼──────────────┘                         │ │
   (inventario→mundo,      └─────────────────────────────────────────┘ │
    spawn en DropPoint)  └───────────────────────────────────────────────┘

   ItemDefinition (.tres)  ──world_scene_path (String)──►  la escena del prop
   (tipo; runtime-inmutable por convención + tripwire)     (resuelto lazy por get_world_scene())
```

**Piezas y sus dueños de dominio:**

| Pieza | Dueña de |
|---|---|
| `InteractionV2` | qué es interactuable (raycast, rango, oclusión) |
| `InventoryReceiver` | traducir `interaction.actor` → `InventoryV2` concreto (mundo→inventario) |
| `ItemDropper` | dónde reaparece un item soltado (inventario→mundo) |
| `InventoryManipulator` | interacción de la grilla; **emite intención, no ejecuta** |
| `InventoryPanel` | presentación/composición; reenvía señales 1:1; cero lógica de modelo |
| `PlayerInventoryUI` | input/foco de UI del Player local; puente UI↔drop |
| `LocalAuthority` | frontera de autoridad *stateless*; único caller de `validate/commit` |
| `TransferOperation` | la transferencia atómica |
| `WorldItemV2` | carcasa física neutral de un `ItemInstance` en el mundo |
| `ItemDefinition` | qué representación mundial le corresponde a un TIPO |
| `ItemInstance` | esta copia concreta (identidad = la referencia) |

**Lo que NO hay** (ausencia deliberada): Service Locator · EventBus global · `get_first_node_in_group("player")`
para ownership · Autoload para el inventario de una entidad · script coordinador en el root `PlayerV2` ·
`ItemManager` / `CatalogoV2` / registry global.

---

## 12. Qué quedó deliberadamente fuera

Nunca estuvo en el alcance de InventoryV2 (declarado en `e2e406d`):

inventario↔inventario · cofres · equipamiento · hotbar · stacks · peso/encumbrance · crafting ·
persistencia/save-load · multiplayer · durabilidad · munición/armas · throw.

Además, quedaron fuera por decisión posterior:

- **Retiro del legacy** (§10) — diferido hasta auditar consumidores por dominio.
- **Feature "llave → puerta"** — trabajo NUEVO de dominio puerta, no migración.
- **Migración de Player V1 / `movement_test.tscn`** a PlayerV2 — track propio; **no bloquea** nada del inventario.
- **Tooltip de nombre al hover** en `InventoryPanel` — backlog opcional de UI.
- **`mesa` / `osciloscopio`** — NO son items (props físicos con interacción no-op). No convertir a `WorldItemV2`.
- **`granada_01`** — asset roto (root sin script). Una granada arrojadiza es un sistema de gameplay entero.

---

## 13. Deuda técnica real

Distinguir **deuda que importa** de **cosas simplemente diferidas**.

### Deuda real (tiene un costo ahora o va a molestar)

| Deuda | Costo |
|---|---|
| **`world_scene` alias de compat** — dos nombres para lo mismo, etiquetado "no urgente" → probablemente permanente | confusión menor; contradice la política del proyecto de "una sola forma de hacer las cosas" |
| **Assets migrados inertes y SILENCIOSOS en `movement_test`** — Player V1 no tiene `InventoryReceiver`, así que `_solicitar_pickup` devuelve `false` sin error | un dev/jugador que corre la main scene y mira el sable: nada pasa, ningún feedback. Y el HUD `[E] <nombre>` está roto para ellos (leen `.data.nombre`, que `WorldItemV2` no tiene) |
| **Tests white-box acoplados a internals de `InventoryManipulator`** (`_agarre_rel_normal`, `_unhandled_input`, `_region_de_drop`) | refactorizar el manipulator rompe tests que no prueban comportamiento sino plumbing |
| **`LocalAuthority` + `TransferOperation` como ceremonia SI el juego se queda singleplayer** | carrying-cost de ~150 líneas de abstracción para una feature que puede no llegar (§6.2, §6.3) |
| **3 autoloads inertes + ~500 líneas de código muerto** (`Inventario`/`UiInventario`/`Catalogo` + `.tres` huérfanos) | un dev nuevo no sabe cuál inventario es el bueno. Aceptado a conciencia (§6.16) como preferible a modificar vecinos |

### Solo diferido (NO es deuda — nunca fue alcance)

`ItemThrower` · tooltip · stacks · encumbrance · ammo · durability · equipment · feature llave→puerta ·
limpieza `ItemData`/`Item.gd`/display-name del HUD · retiro final del legacy · Player V1 → PlayerV2.

**Ninguno de estos fue prometido.** Llamarlos "deuda técnica de InventoryV2" sería inventar alcance
retroactivamente. Son features futuras que llegarán cuando su dominio lo requiera.

### Limitaciones aceptadas a conciencia (documentadas, con triggers de revisión)

- **`ItemDefinition` runtime-inmutable por convención + un tripwire, no enforced** (D8). GDScript no tiene
  `private`; un segundo dev o un plugin podría hacer `ii.definition.grid_width = 99` y romper todas las
  instancias del tipo. Cerrarlo de verdad exige handles opacos (otro Batch de churn) o migrar a C# (fuerza
  build .NET). **Trigger de revisión:** UI/gameplay nuevo que sostenga un `ItemInstance` vivo; persistencia;
  segundo equipo.
- **`instance_id` es un `static` global de proceso.** No persiste. **Trigger:** save/load o red.
- **Footprints como `Vector2i`** — no representa formas en L. **Trigger:** un item real que las necesite.

---

## 14. Principios reutilizables

Sacados de lo que efectivamente funcionó. **No son dogmas** — cada uno tiene un "cuándo podría no aplicar".

| Principio | De dónde salió | Cuándo NO aplica |
|---|---|---|
| **"Cada sistema es dueño de las reglas de su dominio. Compartimos infraestructura cuando conviene; no compartimos significado."** | `InteractionComponent` (infra compartida) vs `_on_interact` (significado por dueño) | concerns genuinamente transversales (logging, tiempo de juego, input mapping) donde compartir el significado ES el punto |
| **No migrar código solo porque existe.** El legacy es referencia ejecutable, no especificación. | `Catalogo`, campos de `ItemData`, llave→puerta | cuando el legacy SÍ codifica una decisión de diseño validada que querés conservar — entonces sí es especificación |
| **No tocar consumidores antes de estabilizar sus dependencias.** Legacy congelado en paralelo > híbrido. | la decisión de §10 | cuando el consumidor bloquea de verdad (no una ref muerta) y no hay forma de aislarlo |
| **Probar con assets reales temprano, no al final.** | el ciclo de recursos que un fixture ocultó 15 commits | prototipos exploratorios donde todavía no sabés qué asset vas a tener |
| **Separar identidad de ubicación.** | `ItemInstance` (identidad) vs `InventoryEntry` (placement) | objetos que genuinamente SON su ubicación (un tile de un mapa) |
| **Separar intención de ejecución.** | `drop_fuera_solicitado` (intención UI) vs `ItemDropper.soltar` (ejecución 3D) | operaciones triviales donde el indirection no compra nada |
| **Evitar globals como mecanismo de ownership.** | `Inventario` autoload → sin respuesta a "¿de quién es?" | recursos verdaderamente únicos por proceso (el `SceneTree`, config) |
| **Validar antes de mutar; atomicidad explícita.** | `TransferOperation.validate/commit`, cero half-states | mutaciones triviales sin invariante que proteger |
| **Mantener invariantes explícitas y testeadas.** | custodia XOR ("nunca 1/1 ni 0/0") | — casi siempre aplica; el costo es bajo |
| **Congelar el core cuando el patrón empieza a repetirse.** | core congelado tras botella; sable/llave = 0 core changes | antes de que el patrón se repita — congelar temprano petrifica un diseño no validado |
| **Deuda explícita/congelada > híbrido permanente.** | §10, §16 | cuando el híbrido es genuinamente transitorio y tiene fecha de retiro |
| **"Ocultar ≠ desactivar" (Godot).** Todo `_input`/`_unhandled_input` necesita gate de activación. | bug 7.4 | — es específico de Godot y casi siempre aplica ahí |
| **Los tests también tienen bugs.** Guardar los dereferences en las aserciones; un test que crashea al diagnosticar es peor que uno que reporta. | bug 7.6 | — siempre aplica |

---

## 15. Qué haríamos distinto si empezáramos hoy

- **Meter un asset real (o un stand-in realista) en V0**, no `test_item_v0`. El ciclo de recursos aparece 15
  commits antes y `world_scene` es un path desde el principio, sin alias de compat.
- **No construir `LocalAuthority` hasta que haya una segunda autoridad.** Shipear `TransferOperation` llamado
  directo por `InventoryReceiver`/`ItemDropper`; introducir la capa de autoridad cuando multiplayer o
  arbitraje-por-NPC sea real. Sacarla después es fácil; construirla "por si acaso" fue infraestructura
  especulativa que a HEAD no compra nada.
- **Auditar los consumidores del legacy (el análisis del §9.6) ANTES de empezar la migración**, no después de
  4 fases. Habría reencuadrado todo desde el arranque como "InventoryV2 ya reemplaza esto; el legacy es
  inerte; no migres consumidores" — y ahorrado el falso arranque de "llave→puerta".
- **Decidir la representación de `ItemDefinition.world_scene` (path vs PackedScene) una sola vez, upfront**,
  conociendo la restricción del ciclo.
- **Quizás no separar C5-A/B/C en tres commits.** Shipear el drop como uno. Dos commits intermedios
  (`ac05cba`, `cfe4ede`) tienen código muerto (una capacidad sin caller, una señal sin consumidor); un
  `git bisect` que caiga ahí ve algo inalcanzable.
- **Menos tests estructurales de "la escena está cableada"** (`player_v2_inventory_ui_test`,
  `player_v2_inventory_sandbox_test`) — el archivo de escena ya garantiza eso. Más tests de comportamiento.

**Lo que NO cambiaríamos:** el modelo de 3 clases, identidad por referencia, custodia XOR, inventario por
entidad, cableado explícito, integración incremental con regresión por commit, prueba manual obligatoria,
congelar el core tras el primer asset real, y legacy en paralelo.

---

## 16. Estado final / evidencia

| Métrica | Valor |
|---|---|
| HEAD | `b3e8ee5` — `SUA-1.6 D: migrate key to InventoryV2` |
| Commits de la línea InventoryV2/PlayerV2 | 20 (`1505ed5` … `b3e8ee5`), + los docs |
| Adelante de `origin/main` | 17 commits, sin push |
| Gate InventoryV2 (12 escenas) | **459 / 0** — invariable a través de toda la integración PlayerV2 |
| Tests PlayerV2 | C0 25/0 · C1 21/0 · C3 19/0 · C4-A 20/0 · C4-B/C 31/0 · C5-A 24/0 · C5-B/B2 62/0 · C5-C 42/0 |
| Migración assets reales | botella **45/0** · sable **32/0** · llave **36/0** |
| Tripwire de identidad (D8) | **22 / 0** — nunca modificado |
| Assets reales migrados | 3 (botella, sable, llave) — cero dependencia de `Item.gd`/`ItemData`/`Inventario`/`Catalogo` |
| Dependencia interna V2 → legacy | **0** (verificado: `grep` en `inventory_v2/` + `player_v2/` → solo comentarios) |
| Pruebas manuales | aprobadas en V0, V1, C3, C4-B, C4-C, C5-B2, C5-C, 1.6 B, 1.6 C, 1.6 D |
| Cambios al core en sable + llave | **0 archivos** (commits de 8 archivos, todos aditivos) |

Commits clave (hash · mensaje):

```
1505ed5  Inventory V0: sistema mundo<->inventario + arnes de pruebas
e2e406d  Inventory V1: manipulacion de la grilla (UI + mover/rotar) sobre InventoryV2
43fc2f4  Inventory V1 debt: isolate InventoryEntry state with snapshots
29adfa3  Inventory V1 debt: harden ItemInstance identity contract
51d106f  Inventory V1 debt: add reusable InventoryPanel
8bb5420  SUA-1.3 C0: add per-instance PlayerV2 inventory
2d22cd5  SUA-1.3 C1: route pickups through actor inventory
4d05e4c  SUA-1.3 C2: make inventory authority routing stateless
61eba68  SUA-1.3 C3: validate PlayerV2 inventory pickup end-to-end
f2aa456  SUA-1.4 C4-A: attach InventoryPanel to PlayerV2
4451a5c  SUA-1.4 C4-B0: hibernate legacy inventory UI input
bf09c5b  SUA-1.4 C4-B: add PlayerV2 inventory UI controls
eb2381f  SUA-1.4 C4-C: remove PlayerV2 escape mouse toggle
ac05cba  SUA-1.5 C5-A: add PlayerV2 item drop capability
cfe4ede  SUA-1.5 C5-B: add inventory drop intent
f27484c  SUA-1.5 C5-B2: add inventory drop neutral zone
d9a0084  SUA-1.5 C5-C: connect inventory drop to PlayerV2
feb42f1  SUA-1.6 B: migrate bottle to InventoryV2       ← ciclo de recursos + world_scene_path
8dbfe5b  SUA-1.6 C: migrate saber to InventoryV2        ← patrón repetido, 0 core
b3e8ee5  SUA-1.6 D: migrate key to InventoryV2          ← auditoría llave→puerta
```

---

## 17. Conclusión

InventoryV2 salió bien en lo que importa: el modelo de datos es limpio, la identidad es sólida, las
transferencias son atómicas, y el patrón de autoría se demostró reutilizable con tres assets reales sin tocar
el core. El gate 459/0 sobrevivió veinte commits.

Salió *sobrediseñado* en un punto: `LocalAuthority` es infraestructura para un multiplayer que no existe. Es
barato y sacable, pero es honesto decir que se construyó para un "algún día".

El error más caro fue **probar demasiado tiempo con un fixture** (`test_item_v0`): ocultó el ciclo de
recursos hasta que la migración ya estaba en marcha, y forzó un cambio de contrato del core a mitad de camino
más un alias de compat que probablemente quede para siempre.

Y la lección más transferible a otros sistemas del juego no es técnica: **el legacy es referencia ejecutable,
no especificación.** Casi lo migramos entero antes de auditar qué hacía de verdad. Cuando auditamos,
resultó que el inventario legacy no producía ningún comportamiento observable — y que la forma correcta de
"terminar" no era retirarlo, sino declararlo inerte, congelarlo en paralelo, y no tocar los sistemas vecinos
solo para limpiar una referencia muerta.

---

### Trabajo futuro registrado (NO parte de este postmortem)

- **"Guía práctica de autoría de `WorldItemV2`"** — un tutorial corto, orientado a *"quiero crear un objeto
  agarrable nuevo, ¿qué archivos creo y qué campos lleno?"*, usando botella/sable/llave como ejemplos. **No
  explica la arquitectura interna** — para eso está este documento. Se escribirá más adelante.
