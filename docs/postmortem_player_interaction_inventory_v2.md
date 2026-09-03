# Postmortem — Player / Interaction / Inventory V2

> Checkpoint arquitectónico posterior a `bd38e49` ("refactor: remove legacy
> interaction and inventory systems"). Documenta **decisiones y estado final**,
> no la crónica de cada commit. Si algo acá contradice el código, gana el código.

## 1. Qué problema resolvíamos

Hasta `bd38e49` convivían dos generaciones completas del actor y sus sistemas
de soporte: PlayerV1/PlayerV2, Interaction V1/V2, Inventario V1/InventoryV2.
Parte de los interactuables reales ya estaban en V2; otra parte seguía en V1;
algunos tests y fixtures mantenían con vida infraestructura vieja que ningún
gameplay real usaba. El costo no era solo código duplicado: era que **no se
podía responder con confianza "cuál es la arquitectura vigente"** sin leer
cada caso a mano — un autoload legacy, un `is InteractionComponent`, o un
`@export var data: ItemData` vestigial podían seguir vivos por pura inercia
de parseo (Godot resuelve autoloads e identificadores en tiempo de
compilación, no de ejecución), bloqueando cualquier demolición limpia.

El trabajo fue: identificar qué era arquitectura viva, demoler lo que no lo
era, y no dejar puentes de compatibilidad V1/V2 como atajo.

## 2. Arquitectura final — Interacción

```
Player
  → InteractionV2        (scripts/player_v2/interaction.gd)
  → InteractionComponentV2   (scripts/player_v2/interaction_component_v2.gd)
  → propietario._on_interact(Interaction)
```

**InteractionV2** vive en el Player. Cada frame físico determina, por
raycast, qué está mirando dentro de rango y sin oclusión; al recibir el
input de interacción arma un `Interaction(actor, &"usar")` y se lo entrega
al componente apuntado. La responsabilidad de *detectar* es del Player, no
del objeto interactuable.

**InteractionComponentV2** es un marcador/contrato, no lógica de gameplay:
se agrega como **hijo directo** del nodo interactuable, y en `_ready()`
verifica (vía `assert`) que su padre implemente `_on_interact(interaction) ->
Variant`. `recibir_interaccion()` simplemente delega y devuelve lo que el
propietario resolvió.

**Resolución por hijo directo, no ancestor-walk**: tanto
`InteractionV2._resolver_componente()` como
`WorldItemV2._resolver_receiver()` recorren únicamente los hijos directos
del nodo relevante. Sin walk por ancestros, sin búsqueda por nombre, sin
grupos.

**El actor viaja en el mensaje, no en el contrato**: `Interaction` lleva
`actor`, pero ni `InteractionComponentV2` ni los interactuables están
obligados a saber qué *es* ese actor concretamente — ver Regla 2 (§10).

**Sin compatibilidad V1**: `InteractionComponentV2` extiende `Node` a
secas, deliberadamente sin heredar de `InteractionComponent` (V1). El
motivo documentado en el propio archivo: Godot resuelve `is` por cadena de
herencia, y compartir esa cadena habría hecho que código V1 reconociera
objetos V2 sin que nadie lo pidiera. `InteractionComponent` V1 ya no existe
en el repo — no hay fallback, adapter ni bridge.

## 3. Arquitectura final — World items / inventario

```
WorldItemV2
  → InteractionComponentV2
  → interaction.actor
  → InventoryReceiver
  → LocalAuthority
  → TransferOperation
  → InventoryV2
```

| Pieza | Responsabilidad |
|---|---|
| `ItemDefinition` (Resource, `.tres`) | Datos estáticos del *tipo* (footprint, `can_rotate`, `world_scene_path`). Runtime-inmutable por convención + tripwire de test, no por lenguaje. |
| `ItemInstance` | Identidad runtime de *esta copia*. `definition` e `instance_id` se fijan en `_init()` y no se reasignan; la identidad real es la referencia del objeto. |
| `InventoryEntry` | Posición + rotación de un `ItemInstance` dentro de un `InventoryV2` concreto. Vive aparte de `ItemInstance` porque solo tiene sentido mientras está colocado. |
| `InventoryV2` | Estado lógico de la grilla de una entidad. |
| `InventoryReceiver` | Capacidad del actor: "puedo recibir un `WorldItemV2`". Traduce `Interaction.actor` a un `InventoryV2` + `LocalAuthority` concretos sin que el mundo los conozca. |
| `LocalAuthority` | Único punto con permiso para llamar `TransferOperation.validate()`/`commit()`. Sin memoria de routing — cada solicitud dice explícitamente sobre qué inventario opera. |
| `TransferOperation` | request → validate() → commit(), atómica. Si `validate()` falla, nada cambia. Transitoria: una instancia por transferencia. |
| `WorldItemV2` | Representación física temporal de un `ItemInstance` en el mundo. `NEUTRAL`: no guarda actor, inventario ni autoridad hasta el momento de la interacción. |

Esta cadena es la razón concreta por la que un `WorldItemV2` **no conoce**:
un `PlayerV2` concreto, el grupo `"player"`, el autoload `Inventario`, la UI,
ni el layout interno de la grilla. Solo conoce la capacidad
`InventoryReceiver` del actor, resuelta como hijo directo — el mismo patrón
de resolución que usa `InteractionV2`.

## 4. WorldItems reales migrados

`llave` (`llave_comun_1.tscn`), `sable` (`sable_san_martin_1.tscn`),
`botella` (`botella_standar_1.tscn`) y `granada` (`granada_01.tscn`) siguen
el mismo patrón, verificado en escena:

```
RigidBody3D
  + world_item.gd        (script raíz, define = ItemDefinition)
  + ItemDefinition        (.tres en assets/data/items_v2/)
  + InteractionComponentV2 (hijo directo)
```

**Nota sobre la granada**: quedó estructuralmente rota por un refactor
incompleto (perdió su script propietario V1 sin reemplazo) y nunca estuvo
instanciada en ninguna escena real. Se reparó **únicamente como collectible
V2** — mismo patrón que los otros tres. Explosión, daño y lanzamiento
cargado **no se restauraron**; no eran parte de este trabajo y no existe
hoy ningún sistema V2 al que portarlos.

## 5. Puerta

```
InteractionV2 → puerta → interaction.actor → InventoryReceiver
  → InventoryV2 → ItemDefinition (llave_requerida)
```

`puerta.gd` resuelve si el actor tiene la llave buscando un
`InventoryReceiver` como hijo directo de `interaction.actor` y comparando
`entry.item_instance.definition == llave_requerida` contra las entries de
`receiver.inventory`. Semántica:

- **Primera apertura** con `requiere_llave = true`: exige la llave; si la
  tiene, `desbloqueada = true` de por vida para esa instancia.
- **Después de desbloqueada**: no vuelve a consultar el inventario, aunque
  el actor pierda la llave.
- La llave es **credencial, no consumible** — nunca se toca `InventoryV2`
  para removerla.
- `puerta.desbloquear()` es la API pública que usa la terminal (§6) para
  abrir sin llave.

La puerta ya no depende de `Inventario` V1, `ItemData`, un `Player`
concreto, ni del grupo `"player"` — `door_rust_01.tscn` no tiene más
`@export var data`.

## 6. Terminal

```
InteractionV2 → InteractionComponentV2 → Terminal
  → UIHacking → objetivo.desbloquear() → puerta
```

`Terminal._on_interact()` solo llama a `UIHacking.abrir(self)`. La
resolución de contraseña vive en `UIHacking`, que al acertar llama
`objetivo.desbloquear()` sobre lo que apunte `Terminal.objetivo`
(`NodePath`) — hoy, la puerta. La terminal en sí es agnóstica de qué actor
la usó.

**Deuda aceptada — `UIHacking`**: sigue siendo legacy y no se tocó en esta
migración. Concretamente:
- es autoload (singleton global, no capacidad de entidad);
- pausa `SceneTree` entero (`get_tree().paused = true/false`), no solo la
  cámara/input del actor;
- corre con `process_mode = ALWAYS` para sobrevivir a la pausa que él mismo
  provoca;
- mantiene un único `terminal_actual` — no soporta dos terminales abiertas
  a la vez, ni multi-actor;
- no gestiona `Input.mouse_mode` como sí lo hace la UI V2 de inventario;
- una futura muerte o reload de escena mientras el árbol está pausado
  **debe garantizar** restaurar `paused = false`, o el juego queda
  congelado — no hay guard para eso hoy.

Se aceptó conscientemente porque **funciona correctamente** y no justificaba
bloquear la migración contractual de la terminal a `InteractionComponentV2`.
No se propone rework acá.

## 7. Vehículos y botones

```
VehicleButton / CallButton → InteractionComponentV2 → GuidedVehicle
```

`VehicleButton._on_interact()` y `CallButton._on_interact()` ignoran por
completo `interaction.actor` — solo llaman
`vehiculo.solicitar_destino(stop_destino)`. Ambos botones son agnósticos
del actor; el transporte no depende del Player. `GuidedVehicle` en sí queda
fuera de alcance de este documento.

## 8. Sistemas eliminados

**PlayerV1** — arquitectura completa del actor viejo (escena, movimiento,
traversal, visuales, HUD propio) eliminada.

**Interaction V1** — eliminados `InteractionComponent.gd`,
`raycast_interaccion.gd`/`.tscn`, y la infraestructura de test
`inventory_v0_test` asociada exclusivamente a ese sistema.

**Inventario V1** — eliminados `Inventario`, `Catalogo`, `UiInventario`,
`ItemInstancia` (autoloads + clases), `Item.gd`, `ItemData` y los 9
recursos `.tres` que dependían de esa clase.

No quedan consumidores funcionales/runtime de ninguna de las tres. La
documentación histórica (`docs/postmortem_inventory_v2.md`,
`docs/inventory_context_checkpoint.md`) puede seguir mencionándolas — no
forman parte del sistema vivo.

## 9. Decisiones que deben preservarse

1. **No reintroducir compatibilidad V1/V2** — ni fallback, ni adapter, ni
   herencia cruzada. Costó una demolición completa sacarla; no vale la
   pena por conveniencia de corto plazo.
2. **Los interactuables no deben conocer un `Player` concreto** salvo
   necesidad real y explícita.
3. **Preferir capacidades del actor** (`InventoryReceiver` resuelto como
   hijo directo) **antes que** `actor is PlayerV2` o
   `actor.is_in_group("player")`.
4. **`InteractionComponentV2` es contrato, no lógica de gameplay.** Si
   empieza a decidir cosas, la lógica se está yendo al lugar equivocado.
5. **`InteractionV2` detecta y entrega; el objeto decide qué significa la
   interacción.** La separación es a propósito.
6. **`WorldItemV2` nunca muta `InventoryV2` directamente.** Toda
   transferencia pasa por `LocalAuthority` → `TransferOperation`.
7. **No migrar metadata legacy de `ItemData` a `ItemDefinition` "porque
   existe".** Campos como `peso`, `munición`, `vida`, `daño`, `fuerza de
   lanzamiento` se auditaron sin consumidores vivos. Si un sistema futuro
   los necesita de verdad, se diseñan en ese momento, para ese sistema.
8. **No convertir sistemas sanos en `XxxV2` solo por antigüedad.**
   Puerta, terminal y botones sobrevivieron intactos (con ajustes de
   cableado, no de lógica) porque su comportamiento seguía siendo correcto.

## 10. Qué aprendimos

- Un test en verde no prueba que la escena real esté migrada: algunos
  arneses llaman `_on_interact()` directamente, sin pasar por la escena
  instanciada tal cual vive en el nivel.
- El nombre `inventory_v1_*` de un test no implica que pruebe arquitectura
  legacy — varios de esos nombres prueban `InventoryV2` desde antes de que
  existiera un V2 explícito de interacción.
- Código funcionalmente muerto puede seguir bloqueando una demolición:
  GDScript falla en tiempo de *parseo* si una referencia a un autoload
  desaparecido queda en un script, aunque esa línea nunca se ejecute
  (`Item.gd` → `Inventario` fue el caso concreto).
- Antes de borrar infraestructura hace falta distinguir explícitamente
  entre consumidor funcional, dependencia estructural (de tipo/parseo),
  test, y comentario/documentación — tratarlos igual lleva a bloqueos
  sorpresa o a borrados prematuros.
- Demoler por fronteras pequeñas (una isla a la vez, verificando después
  de cada una) permitió detectar el bloqueo de `Item.gd` **antes** de
  dejar el repo sin compilar, en vez de después.

## 11. Estado actual / siguiente frontera

```
Player actual
├─ movimiento/traversal
├─ InteractionV2
├─ InventoryV2
└─ (próxima capacidad, sin definir todavía)
```

Interacción e Inventario quedan considerados **cerrados arquitectónicamente**
por ahora. Cualquier capacidad nueva que se agregue al Player debe poder
evolucionar sin reabrir compatibilidad con V1. Cuál es esa próxima
capacidad no se decide en este documento.
