# Verificación independiente de la entrega 16

2026-11-17. Claude, sobre `61d4061`.

- **Criterios:** [criterios_entrega_16.md](criterios_entrega_16.md), commit `b8603a2`, guardados antes de correr nada.
- **Instrumentos:** `9b87baa`, commiteados antes de su primera corrida.
- **Correcciones de tres expectativas mías después de la primera corrida:** `264dc9e`, rotuladas abajo.
- **Instrumentos anteriores:** no cambiaron.

## Veredicto

**`host_action_journal.gd` cumple su contrato en todo lo que pude ejercitar: corrida final con 0 FAIL y 0 INSUFICIENTE.**

- **Registro local, fuera de los IDs de la fixture:**
  - 431 ids registrados con saltos y cada uno con un solo resultado terminal;
  - duplicados en los tres estados, cada campo en conflicto, peer equivocado y 12 formas inválidas, todos atómicos;
  - bordes exactos de ±120 ticks y tardío con el tick pedido original;
  - política consultada una sola vez en el tick real, que no puede alterar el pedido por su copia y rechaza los tipos equivocados;
  - fase errónea, tick omitido, falta de captura, cierre y extremos de ID.
- **ENet y NetSync reales (3 corridas):**
  - pedidos duplicados por RPC real devuelven el resultado guardado, y la variante en conflicto se rechaza;
  - la suelta pedida en 38 se aplica en 46–47 con esos ticks en el ACK del cliente;
  - un pedido rechazado al ejecutar no produce efecto ni ACK;
  - 13 comparaciones en el mismo tick, calificadas por cuadros, todas iguales (4 después de la suelta).
- **INFO:**
  - un `stop` llamado **dentro** del tick, después de `before_capture`, deja que el adaptador ejecute igual la acción (efecto y caja soltada) mientras el registro la da por cancelada sin ACK;
  - un pedido a +120 bloquea los anteriores durante 2 s;
  - el tope de 256 no se alcanza (máximo medido: 124).

No apruebo permisos o alcance reales, InvAuthority, inventario, rechazos remotos, varias manos, presentación, dos PC ni rendimiento. La política de la escena de red es una concesión fija de fixture.

## Base

- **Copia:** avance directo `422884f` → `61d4061`. Los 364 archivos de `../entrega_16.json` coinciden (seis solo en LF).
- **Sin cambios:** núcleo, canal, adaptador, `history_bridge`, `probe_network.gd`, `scripts/` y `scenes/`. No recompilé ni corrí N3 ni la batería de latidos (encargo, punto 6).
- **Mi DLL:** sigue siendo `64679e73…`.

## R1: reproducción — PASS

`run_object_lifecycle_probe.ps1` de Codex, sin cambios, con mi DLL. Los 8 modos (`net_future`, `net_close`, `net_timeout`, `net_lease`, `net_quiet`, `action_window`, `host_journal` y `net_journal`) dan PASSED, código 0. El más largo dura 7,3 s (`net_quiet`).

## J: registro local (`cv16_journal`) — PASS

### Modo `journal`

- **Tamaño:** 590 ticks manuales y 1870 comprobaciones.
- **Resultados:** 431 ids registrados, cada uno con un solo resultado:
  - 399 `applied`;
  - 25 `denied`;
  - 4 `invalid_policy_result`;
  - 1 `invalid_hand_transition`;
  - 1 `revoked`;
  - 1 `execution_tick_missed`.
- **Efectos:** uno por aplicada y ninguno por las demás.
- **ACK:** `confirmations()` coincidió en cada tick con las ≤ 16 aplicadas retenidas de id mayor, con su tick real. Nunca incluyó la acción del tick antes de su paso, y modificar el arreglo devuelto no cambió la llamada siguiente.

| Id | Resultado |
| --- | --- |
| J1 | 300 pedidos con saltos, programados en el tick pedido. Las negadas dan `rejected:denied`, sin efecto. Registros estables en 121 (100–200 y 200–300). |
| J2 | Duplicado pendiente: `scheduled`. Duplicado terminado (aplicado o negado): igual al resultado emitido, en 300 de 300. |
| J3 | Mismo id con otro tipo, tick, ancla o impulso: `action_identity_conflict`, atómico, pendiente (16 casos) y terminado (16) |
| J4 | Peer 8: `invalid_peer`, atómico; la misma acción del peer 7 se programa después |
| J5 | Modificar el resultado devuelto o el de la señal no cambia lo guardado. Modificar la acción original después del pedido (21, 22) no cambia lo ejecutado: el cuadro grabado del adaptador trae la original. |
| J6 | La política que devuelve 5, `null`, `StringName` o `Array` da `invalid_policy_result`, sin efecto. La que modifica su copia (tipo, ancla, impulso, id y tick) y permite (90, 91): se ejecuta la original. Una sola llamada por acción, en su tick, con mundo = tick − 1 y peer 7 (429 ids). |
| J7 | Agarrar sostenido: `invalid_hand_transition`, **sin llamar a la política**, sin efecto |
| J8 | Programada en 301 para 308, revocada en 306: `rejected:revoked` en 308, una llamada, sin efecto |
| J9 | Pedido para 7 ticks después: aplicado en 316 |
| J10 | A en 326 programada; B (id mayor) en 322: `action_order`, atómico; C en 327 programada. A y C se aplican en su tick. |
| J11 | −121 y +121: `action_tick_window`. +120: programada en 448 y aplicada ahí. Después, uno en +5: `action_order`. |
| J12 | Pedido −120 (tick 329) programado y aplicado en 450 con `requested_tick` 329. Un segundo tardío en el mismo tick: `action_capacity`. |
| J13 | `before_capture` entre ticks (dos variantes), dentro de `tick_finished` y por segunda vez en el mismo proveedor: `false` con `execution_phase`, atómico. La acción en vuelo se aplica una vez. |
| J14 | Sin `before_capture` en 456 (con captura): `cancelled:execution_tick_missed` en 457, sin política, efecto ni ACK |
| J15 | 120 pedidos futuros de una vez: todos programados y aplicados en 459…578 |
| J16 | Id 0, −1, 0x80000000 y `float`; tick −1 y 0x80000000; tipo `throw`; ancla de 1,01; impulso de 100,01; ancla NaN; clave faltante o de más: `invalid_action`, atómico (12 casos) |
| J17 | Reintento de un id retirado y hueco por debajo de la marca: `retired_action`. Hueco entre la marca (1506) y el máximo (2073): `nonmonotonic_action_id`. |
| J18 (INFO) | Un id rechazado por ventana antes del registro se acepta después con un tick válido: el id no se consume, como declara Codex |
| J19 | 0x7FFFFFFF se programa y se aplica en 585; después 0x7FFFFFFE: `nonmonotonic_action_id` |

### Otros modos

- **`journal_close` — PASS (14/14):**
  - con la caja agarrada, un soltar en +10 y un agarrar en +16, un `stop("closed")` entre ticks cancela los dos una vez, y un segundo `stop` no emite nada;
  - después, `request` y `before_capture` dan `not_bound`;
  - **la caja sigue agarrada** 20 ticks después: cerrar el registro no la suelta, como declara Codex.
- **`journal_capture` — PASS (13/13):** sin captura en el tick con un soltar en vuelo, las dos acciones quedan `cancelled:prediction_stopped` una vez, sin efectos. El mundo queda en el 5 y el registro, cerrado.
- **`journal_inflight` (INFO):** `stop` dentro del proveedor, después de que `before_capture` encoló el soltar del tick 6.
  - El registro da `cancelled:closed_inflight` una vez, sin ACK.
  - **El adaptador igual lo ejecutó:** hubo efecto y la caja quedó suelta.
  - Por lectura, `channel.closed` y `recovery_required` (con paso fallido) no llegan en ese momento, así que solo pasa si la escena llama `stop` dentro del tick.
- **Medidas (INFO):**
  - con la acción de +120 esperando, 118 de 119 pedidos de los ticks siguientes dieron `action_order`, y el del tick 448 dio `action_capacity`;
  - el máximo de registros fue 124 (4 terminados más 120 futuros), lejos de 256.

## N: ENet y NetSync reales (`cv16_net`, ×3) — PASS

| Id | Resultado en las 3 corridas |
| --- | --- |
| N1 | 1: `scheduled` y duplicado `scheduled`. 2: `scheduled`, duplicado `scheduled`; la repetición mandada en el 60 del cliente (53–54 del host) devuelve `applied` con los mismos ticks, y la variante da `action_identity_conflict`. 3: `scheduled`, después `rejected:invalid_hand_transition` en su tick (62), y su repetición (63–64 del host) devuelve ese resultado. |
| N2 | Efectos del host `{1: 1, 2: 1}`; del cliente `[[1, grab], [2, release]]` |
| N3 | Suelta pedida en 38, programada y aplicada en 47, 47 y 46. La confirmación del cliente trae los mismos ticks. |
| N4 | De 20 sobres por corrida, ninguno trae el 3; el cliente no rechazó ningún sobre |
| N5 | 19 comparaciones por corrida, 13 calificadas en total (2, 6 y 5), **0 distintas**. 4 calificadas con checkpoint posterior a la suelta. Las no calificadas difieren en cuadros (entradas u ojos), como en la entrega 13. |
| N6 | Las comprobaciones de la escena de Codex dan PASSED (comparación intermedia 48 → 55–59) |

## Correcciones de mis expectativas después de la primera corrida (`264dc9e`)

1. **J1:** el tick 90 es múltiplo de 10, pero lo destiné a la política que modifica su copia y permite. Mi chequeo de «negada cada 10» lo incluía. El registro hizo lo correcto: lo aplicó.
2. **J5:** había elegido el tick 20 para modificar la acción original después del pedido, pero el 20 lo niega la política y no se ejecuta. Lo pasé a 21 y 22.
3. **N1:** el calificador buscaba la repetición de la suelta con el reloj del host ≥ 55, un umbral mal elegido: llega en el 53–54 del host. Ahora la identifica por orden. Recalificada, la primera corrida de red pasa igual.

La primera corrida (`run16_20261117_193619`) se conserva. Sus únicas fallas son esas tres expectativas, y el resto de sus 1870 comprobaciones locales pasó.

## Lo que no se certifica

- **Política:** la de la escena de red concede siempre una caja a un cliente; no es alcance, InvAuthority ni inventario.
- **Rechazos:** quedan locales en el host; el cliente no se entera, y su predicción de una acción rechazada no se resuelve.
- **Fuera del alcance:** ledger persistente, varias manos u objetos, catálogo, presentación, política de suelta sin confirmar, dos PC, red real, rendimiento, memoria pico y N3.

## Evidencia (en `tmp/`, sin versionar)

- `tmp/lifecycle_probe/20261117_223545_838691`: R1
- `tmp/validacion_objetos/entrega_16/check16_20261117_193512`: verificación que encontró un `:=` con Variant en `cv16_journal.gd`, corregido antes del commit de los instrumentos
- `tmp/validacion_objetos/entrega_16/check16_20261117_193528`: verificación limpia
- `tmp/validacion_objetos/entrega_16/run16_20261117_193619`: primera corrida
- `tmp/validacion_objetos/entrega_16/run16_20261117_193717`: corrida final, 10 procesos, código 0, sin líneas de error, con `cv16_report.json`
