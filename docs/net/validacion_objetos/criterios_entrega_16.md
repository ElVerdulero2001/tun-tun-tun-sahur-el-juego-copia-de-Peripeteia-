# Criterios fijados antes de ejecutar: verificación de la entrega 16

2026-11-17. Validación independiente de Claude sobre `61d4061`. Encargo: «Encargo de Claude: entrega 16» de `docs/net/entregas/revision_codex_entrega_15.md`. Se escribe y se guarda en el historial **antes** de correr nada, incluido el runner de Codex.

## 0. Base y lectura del código

- **Copia:** avance directo `422884f` → `61d4061`. Los 364 archivos de `../entrega_16.json` coinciden (seis solo en LF). Mis instrumentos de las entregas 10 a 15 no cambiaron.
- **Sin cambios:** núcleo, canal, adaptador, `history_bridge`, `probe_network.gd`, `scripts/` y `scenes/`. No se recompila, no se repite N3 ni la batería de latidos (encargo, punto 6).
- **Nuevo:** `host_action_journal.gd` (136 líneas), `probe_host_journal.gd`, `probe_journal_network.gd`, y dos modos más en el runner de Codex.

### Lectura de `host_action_journal.gd`

- **`request`:**
  - **orden de los rechazos:** vínculo → peer → forma (`size == 5` y `Channel._valid_action`) → retiro de registros viejos → duplicado (contenido igual: devuelve **una copia** del resultado guardado; distinto: `action_identity_conflict`) → `retired_action` (id ≤ marca) → `nonmonotonic_action_id` (id ≤ máximo) → adaptador listo y mismo ámbito → ventana ±120 → `action_capacity` (tick ocupado o 256 registros) → `action_order`;
  - **dónde se programa:** en `max(pedido, reloj + 1)`;
  - **qué consume el ID:** un rechazo antes del registro no consume el id, así que puede volver a pedirse;
  - **`action_order`:** todo pedido nuevo debe programarse **después** del último programado. Uno en `reloj + 120` deja sin lugar a los pedidos anteriores a ese tick hasta que se ejecute (por lectura; se mide);
  - **mismo tick:** dos pedidos tardíos en el mismo tick chocan en el mismo tick de ejecución, y el segundo da `action_capacity`.
- **`before_capture(tick)`:**
  - **fase:** exige `tick == reloj == mundo + 1` y nada en vuelo;
  - **ticks perdidos:** cancela los programados en ticks anteriores con `execution_tick_missed`;
  - **chequeos al ejecutar, en orden:** objeto; transición (agarrar sostenido o soltar libre: rechazo **sin consultar la política**); política, con una copia (un String que no está vacío rechaza con ese motivo, y otro tipo, con `invalid_policy_result`); `adapter.queue_action`.
- **`_after_tick`:** conectado después del adaptador. Marca `applied` solo si el adaptador sigue listo y el mundo está en ese tick.
- **`stop`:** cancela todo lo no terminado, una vez. `recovery_required` del adaptador lo llama.
  - **Por lectura:** si `stop` corre **entre** `before_capture` y el paso, la acción ya está en la cola del adaptador y se ejecuta igual, mientras el registro la da por cancelada sin ACK. Se mide como INFO.
  - **Cerrar no suelta** un cuerpo sostenido.
- **`confirmations()`:** las ≤ 16 aplicadas de id mayor, ordenadas y copiadas.
- **Retiro:** a los 120 ticks del resultado terminal, con marca de id.
- **Capacidad:** con una acción por tick, como mucho hay unos 121 terminados y 120 futuros, así que **256 parece inalcanzable** (se mide).

## 1. Qué decide

- **Etiquetas, igualdad y tiempos:** como antes. `local_`: un proceso con ticks manuales de `SimClock`, `ActorMotor` y la extensión reales.
- **Atómico:** un rechazo no cambia las estadísticas del registro, el snapshot del mundo ni la acción válida ya programada (que después se ejecuta igual).
- **Invariantes globales en todos los modos locales:**
  - cada id registrado tiene **exactamente un** resultado terminal;
  - un `applied` sale con reloj = mundo = `applied_tick`;
  - el adaptador da **un** efecto por id aplicado y **ninguno** por rechazado o cancelado (salvo el caso de `journal_inflight`, que es INFO);
  - `confirmations()` contiene solo aplicadas, ≤ 16, de id mayor, ordenadas, con su tick real, y nunca la acción del tick antes de su paso.
- **Categorías:** como antes. Lo declarado por Codex como límite se informa como INFO, salvo que contradiga su contrato.

## 2. Parte R

| Id | Qué | Decide |
| --- | --- | --- |
| R1 | `run_object_lifecycle_probe.ps1` de Codex sin cambios, en mi copia con mi DLL: los 8 modos (`net_future`, `net_close`, `net_timeout`, `net_lease`, `net_quiet`, `action_window`, `host_journal`, `net_journal`) PASSED, código 0, < 8 s | sí |

## 3. Parte J: registro local (`cv16_journal`)

- **Fixture propio:** actor del peer 7, piso, reloj con ticks manuales, `clock_adapter` real y `host_action_journal` real.
- **Proveedor:** llama `before_capture` y después `adapter.capture`.
- **Política configurable por id:** permitir, negar, devolver otro tipo, o modificar su copia y permitir. Anota cada llamada.

### Modo `journal`

| Id | Qué | Esperado | Decide |
| --- | --- | --- | --- |
| J1 | Ticks 1–300: un pedido por tick para el siguiente, con ids crecientes y saltos de 1 a 9; tipo según el estado de la mano; cada 10 ticks la política niega | Se programa en el tick pedido. Aplicadas un efecto; negadas `rejected` con el motivo, sin efecto ni ACK. Registros estables ≤ 123, sin crecer entre 100–200 y 200–300. | sí |
| J2 | Duplicados: igual pendiente, igual aplicado, igual negado | Devuelven el resultado guardado (`scheduled`, o igual al emitido), sin ejecutar otra vez | sí |
| J3 | Mismo id con otro contenido (tipo, tick, ancla, impulso), pendiente y terminado | `action_identity_conflict`, atómico | sí |
| J4 | Peer equivocado con una acción válida nueva; después la misma desde el peer correcto | `invalid_peer`, atómico; después `scheduled` | sí |
| J5 | Copias: modificar el resultado devuelto, el resultado recibido por la señal, la acción original después del pedido y el arreglo de `confirmations()` | Nada de eso cambia lo guardado ni lo ejecutado (la acción del cuadro grabado del adaptador es la original) | sí |
| J6 | Política: devuelve 5, `null`, un `StringName`, un `Array`; modifica su copia (tipo, ancla, impulso, id, tick) y permite | Otro tipo: `invalid_policy_result`, sin efecto. Copia modificada: se ejecuta la original. Una sola llamada, en el tick real, con mundo = tick − 1 y peer 7. | sí |
| J7 | Transición inválida (agarrar sostenido) | `invalid_hand_transition`, **sin llamar a la política**, sin efecto | sí |
| J8 | Revocación: programada 7 ticks antes con permiso, negada 2 ticks antes de ejecutar | `rejected` con el motivo de la política en su tick, sin efecto | sí |
| J9 | Futuro: pedido para 7 ticks después | Se aplica en ese tick | sí |
| J10 | Orden: A en +9; después B (id mayor) en +5 → `action_order`; C (id mayor) en +10 → `scheduled` | Como se indica; A y C se aplican en su tick | sí |
| J11 | Ventana: +121 y −121 → `action_tick_window`; +120 → programada en +120; después uno en +5 → `action_order` (bloqueo medido en ticks) | Como se indica. La de +120 se aplica en su tick. | sí; el bloqueo es INFO |
| J12 | Tardío: pedido −120 → programado en reloj + 1 con `requested_tick` original; un segundo tardío en el mismo tick → `action_capacity` | Resultado con pedido −120 y aplicado en reloj + 1 | sí |
| J13 | Fase errónea: `before_capture(reloj)` entre ticks, `before_capture(reloj + 1)` entre ticks, `before_capture` en `tick_finished`, segunda llamada en el mismo proveedor con una acción en vuelo | `false` con `execution_phase`, atómico; la acción en vuelo se aplica una vez | sí |
| J14 | Tick de ejecución omitido (el proveedor no llama `before_capture` en ese tick, pero captura) | `cancelled` con `execution_tick_missed` en el tick siguiente; sin efecto ni ACK | sí |
| J15 | 120 pedidos futuros de una vez (+1 … +120) | Todos programados y aplicados en su tick. Se anota el máximo de registros; 256 no se alcanza (INFO). | sí |
| J16 | Extremos e inválidos: id 0, −1, 0x80000000, id `float`; tick −1 y 0x80000000; falta una clave o sobra una; tipo `throw`; ancla de 1,01; impulso de 100,01; ancla NaN | `invalid_action`, atómico | sí |
| J17 | Retiro: reintento de un id retirado; hueco por debajo de la marca; hueco entre la marca y el máximo | `retired_action`, `retired_action`, `nonmonotonic_action_id` | sí |
| J18 | Id rechazado antes del registro (ventana) y después pedido válido con el mismo id | Se acepta (INFO: el id no se consume) | INFO |
| J19 | 0x7FFFFFFF se aplica; después 0x7FFFFFFE | `scheduled` y aplicada; luego `nonmonotonic_action_id`, sin wrap | sí |

### Otros modos

| Modo | Qué | Esperado | Decide |
| --- | --- | --- | --- |
| `journal_close` | Caja agarrada; soltar programado en +10 y otro futuro; `stop("closed")` entre ticks; se corren 20 ticks más | Las dos `cancelled`, motivo `closed`, una vez. Un segundo `stop` no emite nada. `request` y `before_capture` dan `not_bound`. **La caja sigue agarrada** (cerrar no suelta). Ningún efecto de esas acciones. | sí |
| `journal_inflight` | `stop` dentro del proveedor, después de que `before_capture` encoló la acción del tick | El registro da `cancelled` sin ACK. Se informa si el adaptador igual la ejecutó (efecto y cambio físico). | INFO |
| `journal_capture` | Acción en vuelo y otra futura; el proveedor no captura | Las dos `cancelled` una vez; sin efectos ni `applied`; mundo en el tick anterior; el registro queda cerrado (`not_bound`) | sí |

## 4. Parte N: ENet y NetSync reales (`cv16_net`, ×3)

- **Base:** hereda `probe_journal_network.gd` de Codex sin cambiar su protocolo (agarrar en 3, soltar desde 38 con 250 ms de demora y pedido repetido, final en 80).
- **Agrego, por RPC real del cliente:**
  - en el 60, la suelta repetida (ya aplicada) y una variante con otro impulso;
  - en el 60, un pedido 3 de soltar con la caja libre, que el host tiene que rechazar al ejecutar, sin predecirlo en el cliente;
  - en el 70, el 3 repetido.
- **Mi `receive_action`** anota cada resultado en vez de exigir `scheduled`. El registro de la escena solo guarda los ids 1 y 2, como antes.

| Id | Qué | Esperado | Decide |
| --- | --- | --- | --- |
| N1 | Resultados del host por pedido | 1: `scheduled` + duplicado `scheduled`/`applied`. 2: igual, y en el 60 el duplicado devuelve `applied` con los mismos ticks y la variante da `action_identity_conflict`. 3: `scheduled`, después `rejected`/`invalid_hand_transition` al ejecutar, y su duplicado devuelve ese mismo resultado. | sí |
| N2 | Efectos | En el adaptador del host, uno para 1 y para 2 y ninguno para 3. En el cliente, `[[1, grab], [2, release]]`. | sí |
| N3 | Suelta tardía | `requested_tick` del host = tick pedido por el cliente. `applied_tick` = `scheduled_tick` > pedido. La confirmación del cliente para 2 trae esos mismos ticks. | sí |
| N4 | Sin ACK de rechazos | Ningún sobre publicado por el host trae el 3; el cliente no rechaza ningún sobre | sí |
| N5 | Mismo tick tras replay | Cada sobre aplicado en el cliente con `C < T` se compara con el host en `T`. Califica si los cuadros `C+1..T` (tick, dt, ojos, input sin `held_claim` y acción) son iguales en las dos puntas. Toda comparación calificada debe tener el mismo SHA. | sí: una diferencia es FAIL; con < 3 calificadas en total, INSUFICIENTE |
| N5r | Comparación calificada con `C` ≥ tick aplicado de la suelta | Al menos una en las tres corridas | INSUFICIENTE si no hay |
| N6 | Comprobaciones de la escena de Codex (final igual, confirmaciones únicas, comparación intermedia) | PASS | sí |

## 5. Lo que no se certifica

Permisos o alcance reales, InvAuthority, InvHands, inventario o ledger, rechazos enviados al cliente y su predicción, varias manos u objetos, catálogo, presentación, política de suelta sin confirmar, dos PC, red real, rendimiento, memoria pico ni N3. Que un `stop` no suelte el cuerpo se documenta: no es un error del registro.
