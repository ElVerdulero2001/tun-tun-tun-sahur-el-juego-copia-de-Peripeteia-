# Verificación independiente de la entrega 13: canal ENet y `NetSync` reales en dos procesos

2026-11-17. Claude. Base: `c090b7d`.

**Orden de los commits:**
- Criterios en `criterios_entrega_13.md` (`5bd5bef`, 14:49:28). Se escribieron después de leer el README de red, `authority_channel.gd` y `scene_network_bridge.gd`, y antes de correr nada (la primera corrida, la de red de Codex, empezó a las 14:49:33).
- Añadido 3b de los criterios e instrumentos en `89a07fc` (15:07), antes de la primera corrida de mis instrumentos.
- Correcciones de mis instrumentos después de correr: `0b15593` (15:12) y `c3daeb0` (15:15). Se detallan en «Errores propios». Las corridas anteriores se conservan.

## Dictamen

**La entrega hace lo que describe, en dos procesos ENet de una PC.**

**Procedencia:** en todos los modos y en las dos corridas completas,
- cada estado propio del actor llegó por el RPC de snapshot de `NetSync` desde el peer 1, y sus bytes son iguales a los del actor del host en ese tick;
- el tramo de cámara lenta llegó por el RPC de `NetSync` y es el anunciado;
- cada sobre aplicado coincide en revisión, tick y SHA del snapshot con uno publicado por el host, y los sobres completos del cliente son iguales a los ACK de transferencia del host;
- los dos pedidos de acción llegaron por `_submit_action` del canal real, con el cliente como remitente.

**Mismo tick después de replay positivo:** 113 comparaciones calificadas en las dos corridas, **0 distintas**:
- 43 con la caja agarrada e inputs idénticos;
- 68 con la caja suelta;
- 2 que cruzan la suelta.

La restauración final sin replay (`T == C`) da igual en todos los modos.

**Canal:**
- 18 mensajes fabricados del host al cliente por el RPC real `_receive_chunk` y 13 del cliente al host por `_submit_action`: todos rechazados con el error esperado, salvo los dos controles válidos. Rearmado en 0, nada aplicado y mundo igual.
- 46 puntos locales (`seam_`) sobre nodos aparte: todos pasan.
- Ningún buffer de prueba llegó al deserializador nativo. No se repitió N3.

**Control de flujo,** en unos 1860 cuadros observados del emisor real:
- una sola transferencia en vuelo;
- ACK de transferencia = id − 1 en cada cuadro con transferencia activa;
- ningún fragmento enviado mientras espera el ACK;
- fragmento ≤ 1012 bytes.

Con publicación en cada tick (`big`, sobres de hasta 64 KB): 80 publicados, 23 recibidos, revisiones crecientes con saltos, transferencias de hasta 9 cuadros y rearmado parcial visto en 184 cuadros.

**ACK de transferencia separado de la confirmación física:** en todos los modos hubo transferencias completas y confirmadas por ACK después del pedido de suelta que no traían su confirmación. La confirmación física llegó con el primer sobre aplicado que la traía. `effect_ready` y `action_confirmed` salen una vez por id.

**Suspensión:**
- una acción nueva durante la suspensión → `rejected` (`not_ready`);
- el conflicto de captura que faltaba en la entrega 12 → `input_conflict`, suspensión y recuperación uno o dos ticks después;
- un anuncio de cámara lenta 33–34 ticks atrás (más que el presupuesto de 24) se recupera.

**Tres hallazgos (no contradicen el README, pero importan para el laboratorio):**
1. **Cierre de un solo lado:** si el host detiene su canal, el cliente sigue vinculado sin enterarse, y su predicción del objeto no se invalida. Medido con `stop()`; por lectura, pasa lo mismo con la caducidad de envío.
2. **Inanición con estado futuro:** con el cliente detrás del host, cada sobre nuevo reemplaza al futuro que esperaba. Antes del final no se aplicó **ninguno**: 18 reemplazos y 1,3 s de espera continua.
3. **Tope de 256 acciones por vínculo:** el registro de acciones del adaptador y los del registrador no se recortan. Desde la acción 257 todo `queue_action` da `action_capacity`, aunque el diario sigue en 120 ticks.

**Un dato del entorno, no de la entrega:** ENet estrangula el envío no confiable del cliente (`PEER_PACKET_THROTTLE` hasta 0–1 de 32) en algunas corridas. Los inputs de `NetSync` se pierden por tramos de hasta 17 ticks y el host repite el último. Pasa igual **sin ningún tráfico de objetos** (modo de control `quiet`). Eso deja comparaciones sin calificar y explica los FAIL de B1r.

**Números:**
- **Corrida final:** 143 PASS, 2 FAIL, 2 INSUFICIENTE, 3 HALLAZGO, 3 INFO. Los dos FAIL:
  - `big` B1r: ninguna comparación calificable después de la suelta, por el estrangulamiento; 0 distintas;
  - `time_old`, acción durante la suspensión: no se ejercitó, porque la suspensión duró menos de un tick.
- **Primera corrida** (con las tres correcciones del informe): 133 PASS, 6 FAIL, 6 INSUFICIENTE, 3 HALLAZGO, 3 INFO. Los 6 FAIL son B1r por la misma causa; 0 distintas.

**Reproducción:**
- runners de Codex: red 2/2 modos y reloj 16/16, en verde;
- mis regresiones de las entregas 10–12: veredictos idénticos id por id; S1 sigue anulado.

**Lo que no se certifica:** el laboratorio migrado, inventario y permisos, dos PC, rendimiento y memoria pico, ataques de un tercer proceso, demora o pérdida de ENet en sí, y N3.

`model_approved` sigue en `false`.

## Base, reproducción y corridas

- **Copia:**
  - avance directo `1356cee` → `c090b7d`; los 318 archivos de `../entrega_13.json` coinciden;
  - entre `c1359d2` y `c090b7d`, en `native/` solo cambia `native/objetos_core/README.md`; `scripts/`, `scenes/`, `project.godot` y `prototypes/objetos_nativo/` no cambian;
  - DLL: la mía, `64679e73…` (la de Codex es `d7761f5f…`), no anterior a las fuentes;
  - las 239 copias de cada corrida de `cv13` son iguales al repositorio.
- **Reproducción de Codex** (R1, R2), en las carpetas de sus runners:
  - `tmp/network_probe/20261117_174933_b43a08`: `net_plain` y `net_time`, PASSED en host y cliente (170 y 121–122 comprobaciones), unos 2,3 s por proceso;
  - `tmp/clock_probe/20261117_174955_4beba4`: los 16 modos PASSED.
- **Mis regresiones** (R3), en `tmp/validacion_objetos/entrega_13/`:
  - `adapter12_20261117_145035`: 60/0/1;
  - `adapter11_20261117_145045`: 55/0/9;
  - `adapter_20261117_145054`: 80/2, con el S1 conocido y G0_slow código 2;
  - los tres con 61, 64 y 95 veredictos idénticos a la entrega 12. No se recompiló ni se repitió Rust (R4).
- **Mis corridas de `cv13`,** en la misma carpeta:
  - `network13_20261117_150711`: primera corrida completa, instrumento `89a07fc`. Junto a su `report.json` corregido queda `report.intento1_reporte_original.json`;
  - `network13_20261117_151231.diagnostico_rpc_aviso_final_perdido`: diagnóstico de ENet con `quiet`, `rpc`, `base` y `big`;
  - `network13_20261117_151434.rpc_aviso_final_perdido_reproducido`: `rpc` solo;
  - `network13_20261117_151551`: **corrida final**, instrumento `c3daeb0`, los 10 modos. Tiene `report.txt`, `report.json` y `diag.json`.
- **Tiempos:** en la corrida final, todos los procesos terminan con código 0, sin líneas de error. El más largo es `base`, con 4,3 s.

## Por punto del encargo

### 1. Actualización y criterios

Hecho como se describe arriba. Los criterios se fijaron antes de correr; lo que se agregó al construir los instrumentos (el modo `capacity` y la categoría HALLAZGO) quedó guardado antes de la primera corrida de `cv13`.

### 2. Revisión e instrumentos

**Instrumentos nuevos** en `prototypes/objetos_adaptador/validacion_claude/`:
- `cv13_probe.gd` y `.tscn`: la escena de prueba. Un par host/cliente por modo, más el modo `capacity` de un proceso.
- `cv13_tap_link.gd`: subclase de `LinkSimulator` puesta en `NetSync.link`. Anota método, argumentos ligados y remitente de cada RPC que recibe `NetSync`; puede demorar o retener.
- `run_network_claude_e13.ps1`: el runner, con 8 s por proceso, puerto libre por par e importación previa.
- `cv13_report.mjs`: el informe, que califica entre procesos.
- `cv13_diag.mjs`: el diagnóstico de ENet.

**Lectura del código:**
- **Confirmado al correr:** después de un conflicto, el máximo visto queda en ese id, y los fragmentos restantes de esa transferencia son `stale_transfer` (6 en `rpc`).
- **Solo por lectura:** un rechazo del receptor no manda ACK, y el emisor queda esperando hasta su caducidad de 5 s, que detiene su vínculo. Mis rechazos por RPC real se hicieron sin una transferencia real en vuelo, así que no lo ejercitan.

### 3. Dos procesos con fuentes reales

**Procedencia, B0a a B0d:** PASS en los 8 modos de pares, en las dos corridas.
- `base`, primera corrida: 100 snapshots por RPC, todos del peer 1. Mi réplica de la regla de aceptación da los mismos 100 que `snapshots_received`. 96 estados propios llegaron al puente, sin ningún snapshot aplicado que no pasara por la derivación.
- `delay`, primera corrida: 40 RPC entrantes y 38 ejecutados al terminar; la réplica coincide con los 36 aceptados.

**Comparaciones del mismo tick (B1):** cada sobre aplicado con `T > C` se compara con el host en `T`. Se califica solo si los cuadros `C+1..T` (tick, dt, ojos, input, acción) son iguales a los del host.

| Corrida | Calificadas | Distintas | Sin calificar: mundo igual / distinto |
| --- | --- | --- | --- |
| primera | 39 (17 agarrada, 21 suelta, 1 cruza) | 0 | 58 / 63 |
| final | 74 (26 agarrada, 47 suelta, 1 cruza) | 0 | 33 / 57 |

**Por qué quedan sin calificar:**
- la perturbación de 12 cm del tick 18, hasta que llega la corrección;
- dt distinto antes de conocer el tramo lento;
- la acción predicha en 38 contra la aplicada en 46–62;
- y, sobre todo, los ticks en que el host repitió el input (sección de ENet).

Con la caja suelta, los inputs de la mano ya no mueven el mundo nativo. Por eso muchas comparaciones sin calificar dan igual.

**B2:** la restauración final sin replay da igual en los 8 modos, en las dos corridas.

**Comparación intermedia de Codex:** se hace después de confirmar la suelta, cuando la mano ya no mueve la caja. En mis corridas del mismo guion, el host repitió inputs en los ticks 56–58 en varios modos, y su comparación cae ahí (T 56, C 48 en mi reproducción). Su igualdad es real, pero no muestra un replay con inputs idénticos de la caja agarrada. No lo medí en su corrida. Mis 43 comparaciones con la caja agarrada sí lo muestran.

### 4. Variaciones

- **Demora y orden** (`delay`):
  - `NetSync` del cliente con 60 ms de ida y vuelta y ±25 ms de variación: 1 snapshot desordenado y 8 perdidos por `NetSync`, que se queda con el más nuevo (INFO);
  - el host publica cada sobre 8 ticks tarde;
  - suelta demorada 500 ms: pedida en 38, aplicada en 62;
  - 5 calificadas iguales.
- **Cámara lenta pasada:**
  - `time_order`: el sobre con ticks lentos se aplicó antes del anuncio, sin necesidad de retenerlo. Al llegar el anuncio: invalidación `world_time`, `actor_history_unavailable`, y recuperación en el tick 36 con el sobre 28; 11 calificadas iguales.
  - `time_old`: anuncio con inicio 33–34 ticks atrás. En la corrida final, base y objeto se recuperaron dentro del mismo tick 51 (sobre 44); 10 calificadas iguales.
- **Correcciones del personaje:** hubo en todos los modos (12 cm en el 18, y además en el 46 en `conflict_pause`).
- **Suelta tardía:** 250 ms y 500 ms.
  - Antes de la confirmación, los sobres con checkpoint entre la suelta predicha y la aplicada no traen la suelta del host en los cuadros del cliente. El mundo del cliente difiere del host en esas ventanas: en `rpc` de la primera corrida, T 48 y 52, contra el host, que soltó en 47.
  - Por lectura, en el replay del cliente la caja vuelve a la mano hasta el sobre que confirma. No lo medí visualmente.
- **Pedidos y ACK duplicados** (`base`):
  - la suelta se mandó tres veces: el host la programó una vez y marcó dos como duplicado idéntico;
  - 6 ACK de transferencia falsos por RPC real (id 0, uno ya confirmado y 100000) no cambian el conteo: 50 completos, 50 ACK;
  - cada sobre repite las confirmaciones, y `action_confirmed` sale una vez.
- **Estado futuro** (`future`, el cliente arranca 150 ms después):
  - **seguridad:** en 190 cuadros con un sobre futuro pendiente, nunca se aplicó uno con tick mayor que el reloj, y no hubo `future_authority`;
  - **vivacidad:** hallazgo 2;
  - el final igual.
- **Pausa** (`conflict_pause`): 80 ms en el tick 56, con `after_actor_tick()` en cada uno de los 13 cuadros de pausa. Se aplicó un sobre durante la pausa y se reanudó en el 56.
- **ACK de transferencia contra confirmación física (B3):** PASS en los 8 modos. En `base` de la corrida final, las transferencias 8 a 11 se confirmaron por ACK después del pedido sin traer la suelta, y la confirmación física llegó con el sobre 12. Los efectos no se usaron como prueba de transacciones del inventario.

### 5. Límites del canal y acumulación

**Mensajes reales del host al cliente,** por `_receive_chunk` (`rpc`):

| Caso | Error |
| --- | --- |
| magic | `chunk_header` |
| conexión 12 | `chunk_header` |
| 52 bytes | `chunk_size` |
| 1013 bytes | `chunk_size` |
| total > `MAX_BYTES` | `chunk_header` |
| cantidad inconsistente | `chunk_header` |
| índice fuera de rango | `chunk_header` |
| largo de dato | `chunk_header` |
| id 0 | `chunk_header` |
| id 0x80000000 | `chunk_header` |
| id viejo | `stale_transfer` |
| digest | `transfer_digest` |
| ámbito (contexto 2) | `packet_format_or_scope` |
| revisión repetida | `stale_authority` |
| fragmento repetido conflictivo | `chunk_conflict` |
| sus fragmentos siguientes | 6 × `stale_transfer` |
| total/digest conflictivo | `transfer_conflict` |
| control con bytes reales del host | aceptado; el ACK al host se ignora porque no hay transferencia activa |

En cada caso: rearmado en 0, `authorities_applied` sin cambio y SHA nativo igual.

**Mensajes reales del cliente al host,** por `_submit_action`:
- 84 y 86 bytes, conexión 12, firma de mano cambiada, tipo 0 y 3, ancla NaN, ancla de 1,01, impulso de 100,01, id 0, id 0x80000000 y tick 0x80000000;
- solo el control emitió `action_requested`;
- 4 ACK de transferencia falsos no cambiaron el conteo.

**Cierre:**
- **Host:** `stop()` emite `closed` una vez. `publish` y `start` dan falso, y no quedan bytes.
- **Cliente, después del `stop()` del host:** sigue vinculado (hallazgo 1).
- **Cliente, después de su propio `stop()`:**
  - `closed` una vez;
  - libera el sobre pendiente de 6175 bytes;
  - el puente queda vacío, la base inválida y el adaptador detenido (`timeline_invalidated:actor`);
  - una acción nueva → `rejected` (`not_ready`);
  - `start` y `request_action` dan falso;
  - un fragmento real posterior → `unbound_sender`.

**Puntos locales** (37 en el cliente y 9 en el host):
- **Formato:**
  - 16 ACK sí y 17 no;
  - id repetido, aplicado < pedido, aplicado > tick y snapshot vacío: rechazados;
  - snapshot de 1 048 620 bytes sí y de 1 048 621 no;
  - versión 2, revisiones 0 y 0x80000000, y tick −1: rechazados;
  - al decodificar, se rechazan: truncado, byte de más, versión, 17 ACK, largo de snapshot, revisión 0, tipo de ACK, aplicado < pedido y contexto.
- **Rearmado:**
  - transferencia del tamaño máximo admitido (1 048 894 bytes, 1093 fragmentos) en orden inverso, con el rearmado ≤ `MAX_BYTES` y liberado al completar;
  - cantidad > 1094 rechazada;
  - la caducidad libera y no resucita;
  - un conflicto o un digest malo liberan;
  - fuera de orden con duplicado idéntico idempotente;
  - `stop` libera y el nodo detenido no se reutiliza.
- **Emisor:** un sobre inválido no reemplaza al pendiente; mismo tick con revisión mayor sí; tick menor, revisión repetida, fragmentos y pedidos se rechazan; `stop` vacía todo y no reinicia.

**Acumulación:**
- **B5,** en los 8 modos: diarios ≤ 120 ticks y ≤ 262 144 bytes, un único pendiente en canal y puente, tramos de `NetSync` vaciados en cada tick, y `_inputs` y `_claims` del host ≤ 241.
- **200 ticks de `base`:** ninguna estructura sin cota crece de la primera mitad a la segunda (entradas pendientes, comandos, `ClientPrediction`, eventos, tramos, cola del enlace, pendientes del adaptador, registros de acciones).
- **Objetos de Godot** (INFO): 1622 → 1620 en el cliente; en el host, 1713 → 1728, lo que acompaña el llenado de la ventana de inputs.
- **Fuera de esas estructuras:** el hallazgo 3.

### 6. Suspensión, conflicto de captura y tipos de prueba

- **Acción nueva suspendido:**
  - `conflict_pause`, en las dos corridas: `rejected` (`not_ready`);
  - `time_old`, primera corrida: también;
  - `time_old`, corrida final: no se ejercitó (FAIL registrado; ver «Errores propios»).
- **Conflicto de captura,** con una segunda captura distinta en el tick 22: `input_conflict`, base inválida, adaptador detenido, pedido `input_conflict`, recuperación con el sobre 16 en el tick 23–24, y comparaciones calificadas iguales después.
- **Tipos de prueba:** cada comprobación lleva su prefijo:
  - `run_` es el recorrido real;
  - `rpc_` y los casos R son mensajes RPC reales fabricados por mi instrumento entre los dos procesos;
  - `seam_` son llamadas locales a nodos aparte.

### 7. Reproducción

Hecha (sección «Base»). S1 sigue anulado y sin modificar.

## Hallazgos

1. **Cierre de un solo lado.**
   - **Medido en `rpc`:** después del `stop()` del host, el cliente sigue vinculado (`client_bound_after_host_stop = true`). Su predicción del objeto sigue sin autoridad y sin invalidarse.
   - **Por lectura:** lo mismo pasa con la caducidad de envío de 5 s, que también la dispara cualquier rechazo del receptor, porque no se manda ACK.
2. **Inanición con estado futuro.**
   - El puente y el canal guardan un único sobre y lo reemplazan por el más nuevo.
   - Si el cliente va detrás del host por más que el intervalo de publicación, el sobre que espera siempre es reemplazado por otro también futuro.
   - Medido en `future`: 0 aplicados antes del final, 18 reemplazos y 1302 ms de espera continua; solo se aplicó el último, porque el host dejó de publicar.
3. **Tope de acciones por vínculo.**
   - En `capacity`, del 1 al 256 se encolan.
   - Desde el 257, todos dan `action_capacity`; el adaptador sigue listo, con el diario en 120 ticks.
   - El registrador conserva 256 ids conocidos y 256 efectos.
   - Agarrar y soltar 128 veces en una misma sesión agota el vínculo.

## Observación del entorno: estrangulamiento de ENet

- **El patrón:** en tramos periódicos, el margen de input que informa `NetSync` baja de a un tick por tick durante unos 16 ticks y vuelve a saltar. Durante esos tramos el host usa el input repetido (`used_input_tick < tick`).
- **Lo que no es:** el cliente no se traba; procesa snapshots cada 28–35 ms.
- **Lo que muestran las estadísticas** del peer ENet del cliente: en las corridas donde aparece, `PEER_PACKET_THROTTLE` baja hasta 0–1 de 32 (casi siempre desde el tick 18–20), con pérdida 0 e ida y vuelta ≤ 12 ms.
- **Control `quiet`,** sin ningún sobre de objetos: el mismo patrón (24–26, 33–49, 56–58, 65–73).
- **Varía entre corridas:** en la corrida final no apareció en `delay`, `time_*`, `conflict_pause` ni `rpc`, y sí en `big`, `quiet`, `future` y en `base` desde el tick 111.
- **No es de esta entrega:** el laboratorio crea ENet con la misma configuración por defecto, y su prueba `inv_hold_contact_test.gd` ya anota el «throttle mínimo ENet».
- **Efecto aquí:** deja sin calificar las ventanas en que el host repitió inputs.

## Errores propios

1. **Informe, tres errores** (corregidos en `0b15593`; el informe original se conserva):
   - exigía archivo de resultado a la importación;
   - clasificaba `_claims` de `NetSync` como «sin cota», pero se recorta como `_inputs`: 73 → 99, cota 241;
   - en `delay` exigía 6 ticks de demora también al vaciado final, que publica el sobre del 76 en el 80 por diseño de mi instrumento.
2. **`chunk()` lento:** recalculaba el SHA del sobre entero en cada fragmento, porque el valor por defecto de `Dictionary.get()` se evalúa siempre. Los puntos locales del sobre de 1 MB llevaban `rpc` a 5,7–7,9 s.
   - En 2 de 3 corridas de `rpc`, el último aviso del cliente se perdió al cerrar ENet y el host llegó a su plazo interno, con todos los casos ya evaluados.
   - Corregido en `c3daeb0` con un SHA por transferencia y un saludo final. `rpc` pasó a 2,4 s.
   - Las dos corridas quedan con sufijo.
3. **`time_old`, acción durante la suspensión:** mi instrumento mira al final de cada tick. En la corrida final la suspensión empezó y terminó dentro del tick 51, así que no se intentó la acción. Queda FAIL como se registró.
4. **B1r:** como se fijó, exige una ventana calificable después de la suelta. Con el estrangulamiento de ENet puede no haberla. Queda FAIL en esos modos y no se ajustó: ninguna comparación calificada dio distinta.

## Qué falta

- **ENet en sí:** demora, pérdida y desorden reales (no hay retransmisor). Por eso tampoco hay caducidad de envío o de rearmado en tiempo real: solo puntos locales y la lectura de que cualquier rechazo detiene al emisor a los 5 s.
- **Atacantes:** un tercer proceso, o un invitado que llama métodos `authority`; eso lo rechaza Godot y no lo probé.
- **Medición visual** de la caja que vuelve a la mano con la suelta tardía.
- **Lo que tampoco cubre la entrega:** varias manos o actores, inventario y permisos, migración del laboratorio, dos PC, memoria pico y rendimiento.

## Límites

- Una PC, loopback y ritmo real. Las corridas dependen del reloj, así que algunos números cambian entre corridas, en especial el estrangulamiento de ENet.
- Los resultados por modo son de dos corridas completas; no es una muestra estadística.
- Los bytes nativos siguen siendo `trusted`: el SHA y el ámbito no los vuelven seguros ante un host hostil.
