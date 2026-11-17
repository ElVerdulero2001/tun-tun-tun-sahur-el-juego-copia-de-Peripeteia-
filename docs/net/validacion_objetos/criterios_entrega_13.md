# Criterios fijados antes de ejecutar: verificación de la entrega 13

2026-11-17. Validación independiente de Claude sobre `c090b7d`. Encargo: «Encargo de Claude: entrega 13» de `docs/net/entregas/revision_codex_entrega_12.md`. Se escribe y se guarda en el historial **antes** de correr nada, incluidos los runners de Codex.

## 0. Base y lectura del código

- **Copia:** avance directo `1356cee` → `c090b7d`. Los 318 archivos de `../entrega_13.json` coinciden (cinco JSON solo en LF). Mis instrumentos no cambiaron.
- **Núcleo y producción:** entre `c1359d2` y `c090b7d` no cambia nada en `native/` salvo `native/objetos_core/README.md`, ni en `scripts/`, `scenes/`, `project.godot` o `prototypes/objetos_nativo/`. No se recompila ni se repite Rust; mi DLL sigue siendo `64679e73…` (la de Codex, `d7761f5f…`).
- **`authority_channel.gd`, leído antes de correr:**
  - El receptor solo acepta del servidor 1 con el vínculo vivo; la cabecera (magic, conexión, tamaños, índice, cantidad, largo exacto del dato) se valida **antes** de reservar el rearmado.
  - Un id menor que el máximo visto, o igual con el rearmado vacío, es `stale_transfer`. Un id nuevo descarta el rearmado anterior.
  - Un conflicto de total/cantidad/digest o un fragmento repetido distinto descartan el rearmado, pero el máximo visto queda en ese id: los fragmentos siguientes de la misma transferencia ya son `stale_transfer`.
  - El ACK de transferencia sale solo si el sobre completo pasa digest, formato/ámbito y orden de revisión/tick. **Cualquier rechazo deja al emisor esperando ese ACK hasta su caducidad de 5 s, que detiene el vínculo del emisor.**
  - El emisor no avisa al receptor cuando se detiene: **el cierre es de un solo lado** (lectura de código; se prueba en el modo `rpc`).
  - `decode_packet` no usa `bytes_to_var` y revalida con `encode_packet`.
- **`scene_network_bridge.gd`:** guarda un único sobre pendiente y lo **reemplaza** por el más nuevo. Un sobre futuro espera. Por lectura, con un cliente detrás del host por más de un intervalo de publicación, cada sobre nuevo reemplaza al futuro que esperaba: **posible inanición**, a medir en el modo `future`.
- **Canales:** el canal de objetos usa el canal ENet 1; NetSync usa los suyos (snapshots no confiables, cámara lenta confiable). Entre ellos no hay orden garantizado: el sobre de un tick con cámara lenta puede llegar antes que el anuncio.
- **`ClientPrediction.replay_from`** necesita el estado del tick anterior al tramo; los ticks ya confirmados se olvidan. Un anuncio pasado puede dejar la base del actor inválida hasta la próxima corrección (camino de la entrega 12).

## 1. Qué decide

- **Igualdad en el mismo tick:** SHA-256 de `var_to_bytes(samples())`, igual que en entregas anteriores. Sin tolerancia: los dos procesos usan la misma DLL y, cuando se cumple la condición previa de abajo, los mismos datos; cualquier diferencia es FAIL.
- **Condición previa de una comparación** (se fija ahora y no se ajusta a los resultados): para un sobre aplicado en el tick `T` con checkpoint `C < T`, los cuadros grabados del cliente `C+1..T` (tick, dt, ojos, bytes de input, acción) son iguales a los cuadros del host para esos ticks. Si se cumple, la comparación **se califica**; si no, se informa cuál campo y tick difieren y no se califica.
- **Procedencia:** se registra en el cliente con una subclase propia de `LinkSimulator` puesta en `NetSync.link` (API pública del simulador del laboratorio). Por defecto entrega en el acto, como el simulador inactivo. Lee el método y los argumentos ligados de cada `Callable` que NetSync le pasa al recibir un RPC. No modifica NetSync.
- **Etiquetas:** cada comprobación lleva prefijo `run_` (recorrido real de dos procesos), `rpc_` (mensaje RPC real fabricado por mi instrumento) o `seam_` (punto local sobre un nodo).
- **Límites:** 8 s por proceso desde fuera y 7 s de plazo interno. Ritmo real, sin `--fixed-fps`, como el runner de Codex: los dos procesos dependen del reloj real.
- **Sin cambios:** no se repite N3 y no se modifica S1 (entrega 10), que sigue anulado por el conteo conocido.

## 2. Parte R: reproducción con instrumentos originales

| Id | Qué | Decide |
| --- | --- | --- |
| R1 | `run_object_network_probe.ps1` de Codex: `net_plain` y `net_time`, host y cliente PASSED, código 0, sin líneas de error, cada proceso < 8 s | sí |
| R2 | `run_object_clock_probe.ps1`, los 16 modos: mismos veredictos que en la entrega 12 | sí |
| R3 | Mi `cv12` (60/0/1), `cv11` (55/0/9) y `cv10` (80/2, con S1 FAIL y G0_slow código 2 por el error conocido): mismos veredictos | sí |
| R4 | Hashes del núcleo sin cambios y DLL no anterior a las fuentes | sí |

## 3. Parte B: dos procesos ENet con fuentes reales (`cv13`)

En todos los modos el host simula al actor con `NetSync.input_for`, manda snapshots con `NetSync.send_snapshot` y publica estados nativos con `channel.publish`. El cliente usa `history_bridge`, `scene_network_bridge`, `ClientPrediction.record` y `NetSync.send_ticks`. Hay una perturbación local de 12 cm en el tick 18 del cliente.

### Comprobaciones comunes a cada modo

| Id | Qué | Decide |
| --- | --- | --- |
| B0a | Cada snapshot que aceptó NetSync llegó por mi derivación desde `_accept_snapshot` dentro de un RPC del peer 1. Los bytes del estado propio de cada snapshot son iguales a los del actor del host en ese tick. El puente recibió al menos un estado propio. | sí |
| B0b | Cada tramo de cámara lenta que consumió el puente llegó por `_accept_world_slow` dentro de un RPC del peer 1 y es igual al anunciado por el host | sí, en los modos de tiempo |
| B0c | Cada sobre aplicado por el puente coincide en revisión, tick y SHA del snapshot con un sobre publicado por el host. `completed` del cliente es igual a los ACK de transferencia del host. | sí |
| B0d | Cada pedido de acción que el host programó llegó por `action_requested` del canal real con remitente igual al cliente | sí |
| B1 | Toda comparación **calificada** (sección 1) en `T > C` da el mismo SHA que el host en `T` | sí: una diferencia es FAIL; con menos de 3 calificadas, el modo queda INSUFICIENTE |
| B1r | Hay al menos una comparación calificada con `C` mayor o igual al tick aplicado de la suelta, antes de la final | sí, salvo `future` |
| B2 | Final: el último sobre (tick final) se aplica con `T == C`, y el SHA es igual al del host | sí |
| B3 | `effect_ready` y `action_confirmed` una vez por id. El tick aplicado de la confirmación es el del host. La confirmación física de la suelta llega con el primer sobre aplicado que la trae, no con un ACK de transferencia: hubo ACK de transferencia de sobres posteriores al pedido que no la traían. | sí |
| B4 | Emisor, en cada cuadro: una sola transferencia en vuelo; con transferencia activa, ACK de transferencia = id − 1; mientras espera el ACK no manda fragmentos; bytes del emisor ≤ 2 × `MAX_BYTES`; fragmento ≤ 1012 bytes | sí |
| B5 | Receptor, en cada cuadro: rearmado ≤ `MAX_BYTES`, un único sobre en el canal y en el puente, diario del puente ≤ 120 ticks y ≤ 262144 bytes, diario del adaptador ≤ 120, tramos recibidos de NetSync vaciados en cada tick. Host: `_inputs` por peer ≤ 241. Se anotan los máximos de cada estructura. | sí |

### Modos

| Modo | Variación | Esperado | Decide |
| --- | --- | --- | --- |
| `base` | Como `net_plain`, hasta el tick 200. Suelta demorada 250 ms y mandada tres veces (dos juntas y una después de confirmada). ACK de transferencia falsos por RPC real del cliente: id 0, un id ya confirmado y uno lejano. | Comunes. Los ACK falsos no cambian el conteo: ACK del host = sobres completos del cliente. Las estructuras de B5 no crecen entre la primera y la segunda mitad. | sí |
| `delay` | En el cliente, NetSync con 60 ms de ida y vuelta y ±25 ms de variación; el host publica cada sobre 6 ticks tarde; suelta demorada 500 ms | Comunes. Se informa cuántos snapshots llegaron desordenados (INFO). | sí |
| `time_order` | Cámara lenta 18–34 al 50 %, anunciada en el tick 26 del host. Mi derivación retiene el anuncio hasta que el cliente aplicó un sobre con tick ≥ 24 (el sobre gana al anuncio). | Invalidación por tiempo, recuperación y comparaciones calificadas iguales después | sí |
| `time_old` | El mismo tramo anunciado en el tick 44 del host (inicio más viejo que el presupuesto de 24 pasos). Durante la suspensión, el cliente intenta una acción nueva. | Recuperación con un sobre posterior. La acción nueva es `rejected` (`not_ready`). | sí |
| `conflict_pause` | Conflicto de captura en el tick 22 del cliente. Segunda perturbación de 12 cm en el 46. Pausa de 80 ms del cliente en el 56, llamando `after_actor_tick()` en cada cuadro de pausa. | `input_conflict`, suspensión, recuperación; comparaciones calificadas iguales. Sobres aplicados en pausa: INFO. | sí |
| `future` | El cliente arranca 150 ms después que el host (va detrás) | Seguridad: nunca se aplica un sobre con tick mayor que el reloj; final igual. Vivacidad: cuántos sobres se aplicaron antes de la final y cuánto esperó el pendiente (INFO; si no se aplica ninguno, se informa como hallazgo). | seguridad sí |
| `big` | Mundo propio con cajas de más para que el sobre ocupe más de 8 fragmentos. El host publica en **cada** tick. | Transferencias de varios cuadros; rearmado parcial visto entre cuadros; revisiones recibidas crecientes y con saltos (reemplazo del pendiente); comunes | sí |
| `rpc` | Recorrido hasta el 80 y después mensajes fabricados por RPC real y cierre | Sección siguiente | sí |

### Modo `rpc`: mensajes reales y cierre

Después de la comparación final, sin más sobres reales:

- **Host → cliente, por `_receive_chunk` real:** magic equivocado, conexión vieja (12), fragmento corto (≤ 52), fragmento de más de 1012 bytes, total mayor que `MAX_BYTES`, cantidad inconsistente, índice fuera de rango, largo de dato equivocado, id 0, id viejo, transferencia completa con digest equivocado, con ámbito equivocado y con revisión repetida (snapshot real del host), y fragmento repetido conflictivo.
  - Para cada uno: rechazo con el error esperado, rearmado en 0 después, canal sin sobre pendiente, `authorities_applied` sin cambio y SHA nativo sin cambio.
  - Ningún buffer de prueba llega al deserializador: los casos completos están diseñados para rechazarse antes, y el único sobre aceptable usa bytes reales del host.
- **Cliente → host, por `_submit_action` real:** 84 y 86 bytes, conexión y firma de mano equivocadas, tipo 0 y 3, ancla NaN, ancla de largo 1,01, impulso de 100,01, id 0, id y tick 0x80000000, y un control válido. Exactamente una emisión de `action_requested` (el control).
- **Cliente → host, `_transfer_ack` real sin transferencia activa:** sin cambio en el conteo.
- **Cierre de un solo lado:** el host detiene su canal y avisa por un RPC propio. Se anota si el canal del cliente sigue vinculado (INFO, esperado sí por lectura).
- **Cierre del cliente:** `stop()` emite `closed` una vez. El puente descarta lo pendiente, la base del actor queda inválida y el adaptador se detiene. `history.queue_action` nueva → `rejected` (`not_ready`). `start` → falso. Un fragmento real posterior → `unbound_sender`. `request_action` → falso. En el host, después de su `stop()`: `publish` y `start` → falso.

### Puntos locales (`seam_`, en el modo `rpc`)

En un nodo aparte vinculado a la conexión viva, sin puente:

- **Formato:** 16 ACK sí y 17 no; ids repetidos; aplicado < pedido; aplicado > tick; snapshot vacío; snapshot de 1 048 620 sí y de 1 048 621 no; sobre truncado; byte de más; versión 2; revisión 0 y 0x80000000.
- **Rearmado:** transferencia del tamaño máximo admitido rearmada fuera de orden; cantidad > `MAX_CHUNKS`; caducidad del rearmado; liberación después de completar, conflicto, caducidad y `stop`.
- **Emisor** (nodo con `_process` apagado): un inválido no reemplaza al pendiente; mismo tick con revisión mayor sí; tick menor no; `stop` vacía envío y pendiente.

## 3b. Añadido al construir los instrumentos, antes de correrlos

Se agregó durante la construcción, antes de la primera ejecución de `cv13` (los runners de Codex y mis regresiones ya habían corrido; ver el informe).

- **Lectura:** en `clock_adapter.gd`, `_actions` solo crece. El adaptador rechaza con `action_capacity` cuando llega a `MAX_ACTIONS` (256), y nada lo recorta. En `history_bridge.gd`, `_known_actions`, `_effects` y `_confirmed` tampoco se recortan. Es acumulación fuera de las estructuras del canal.
- **Modo `capacity`** (un proceso, sin red, `--fixed-fps 60`): una acción nueva por tick, alternando agarrar y soltar, del 1 al 270.
  - Se confirma la lectura si entran 1..256, desde la 257 todas dan `action_capacity`, y al final el registrador conserva 256 ids con su diario ≤ 120 ticks.
  - Si se confirma, se informa como **HALLAZGO**, no como FAIL de la entrega: el README no promete acciones ilimitadas. Si el comportamiento es otro, FAIL de mi lectura.
- **Categoría HALLAZGO:** también para `I_cierre_de_un_solo_lado` (si el cliente sigue vinculado tras el `stop()` del host) y para la vivacidad de `future` si no se aplica ningún sobre antes de la final. Son comportamientos medidos que el informe debe destacar, sin cambiar el veredicto de seguridad.
- **Comparación de veredictos de regresión:** contra las corridas de la entrega 12, id por id.

## 4. Lo que no se certifica

Integración en `net_lab.gd`, inventario o permisos reales, dos PC, rendimiento o memoria pico del proceso, ataques de un tercer proceso, ni deserialización de snapshots hostiles (N3). La demora de ENet en sí no se simula: la demora y el desorden se introducen en NetSync (simulador) y en el momento de publicar del host.
