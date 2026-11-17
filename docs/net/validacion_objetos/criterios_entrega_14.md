# Criterios fijados antes de ejecutar: verificación de la entrega 14

2026-11-17. Validación independiente de Claude sobre `c127cf8`. Encargo: «Encargo de Claude: entrega 14» de `docs/net/entregas/revision_codex_entrega_13.md`. Se escribe y se guarda en el historial **antes** de correr nada, incluido el runner de Codex.

## 0. Base y lectura del código

- **Copia:** avance directo `f6d3af4` → `c127cf8`. Los 333 archivos de `../entrega_14.json` coinciden (seis solo en LF). Mis instrumentos anteriores no cambiaron.
- **Núcleo y producción:** entre `f6d3af4` y `c127cf8` no cambia nada en `native/` salvo su README, ni en `scripts/` o `scenes/`. No se recompila ni se repite Rust. Mi DLL sigue siendo `64679e73…` (la de Codex, `d7761f5f…`, de las mismas fuentes). No se corre N3.
- **Cambios leídos:** `authority_channel.gd` (+46), `scene_network_bridge.gd` (+13), `clock_adapter.gd` (+35), `history_bridge.gd` (+5).

### Lectura de `authority_channel.gd`

- `stop(notify_peer = true)` manda `_remote_close` (RPC confiable, canal ENet 0) solo si el peer ya estuvo activo y la conexión sigue viva. Después vacía `_rx`, `_tx`, `_pending` y `_next_packet` y emite `closed`. Un segundo `stop` no hace nada.
- `_remote_close` y `_heartbeat` son `any_peer`. Los dos exigen el vínculo vivo, remitente igual a `_peer` y exactamente 52 bytes iguales al ámbito propio (conexión, contexto, uid, época, sesión y firma de mano). `_remote_close` cierra con `stop(false)`, sin reenviar el aviso.
- **El latido es no confiable** (`unreliable`, canal 0) y sale cada 500 ms después del primer tráfico de cada punta.
- **Actividad del peer:**
  - **en el host**, solo la renuevan el latido del cliente, el ACK de transferencia que espera y un pedido de acción;
  - **en el cliente**, la renuevan los fragmentos del host y su latido.
- Si pasan más de 5000 ms sin actividad, el vínculo cierra con `peer_idle_timeout` y avisa al otro lado (si estuvo activo). El plazo se cuenta desde `start` aunque nunca haya habido tráfico.
- **Consecuencia que mido:** si el host deja de publicar, **la única señal de vida del cliente que recibe el host es un paquete no confiable**. En la entrega 13 ENet tiró casi todos los envíos no confiables del cliente por tramos (`PEER_PACKET_THROTTLE` 0–1 de 32), también sin tráfico de objetos. Por lectura, con el host callado y ese estrangulamiento, el host puede caducar un vínculo vivo.
- `send_timeout` sigue contando 5 s desde el inicio de la transferencia. Con el cliente callado, la caducidad por ausencia suele llegar antes: la última actividad es el ACK anterior, recibido justo antes de empezar la transferencia siguiente.

### Lectura de `scene_network_bridge.gd`

- Un sobre nuevo va a `_pending` si está vacío o tiene el mismo tick. Si no, va a `_latest`, que se reemplaza siempre por el último.
- Si `_latest` ya es alcanzable, reemplaza a `_pending`. Se aplica `_pending` solo si su tick ≤ reloj y hay base del actor. Al consumirlo, `_latest` pasa a `_pending`.
- El cierre vacía los dos, invalida la base y detiene al adaptador.
- El canal ya rechaza ticks menores, así que `_latest.tick ≥ _pending.tick`.

### Lectura de `clock_adapter.gd` y `history_bridge.gd`

- **Retiro:** en cada `_after_tick(N)` y en cada `queue_action` se retiran las acciones con tick `< N − 120`.
  - La marca `_retired_action_id` guarda el mayor id retirado.
  - `is_retired_action(id)` es verdadero para **todo id ≤ marca** que no esté activo, **incluidos ids que nunca se usaron** (huecos).
- **IDs:** un id nuevo debe ser mayor que el máximo. Un hueco por encima de la marca da `nonmonotonic_action_id`; uno por debajo, `retired_action`.
- **ACK:**
  - un ACK con id retirado y tick pedido menor que `_retired_before_tick` se acepta **sin validar tipo ni tick contra el original** (que ya no existe) y no emite nada;
  - si el tick pedido no es menor, el sobre entero se rechaza.
- **Borde esperado por lectura:** el registrador procesa los sobres después de `_after_tick(N)`. Una acción del tick `T` se retira cuando `N ≥ T + 121`. Una primera confirmación entregada a `T + 120` sale; a `T + 121`, no.
- **Política declarada:** un ACK retirado no da efecto ni primera confirmación tardía, y **no hay ninguna señal** de que una acción venció sin confirmarse.
- **Recuperación:** exige que cada acción de sus cuadros siga activa. Como recupera a lo sumo 24 pasos, no choca con los 120.
- **Durante la suspensión,** `queue_action` da `not_ready`.

## 1. Qué decide

- **Etiquetas:**
  - `run_`: recorrido real entre procesos;
  - `rpc_`: RPC real fabricado por mi instrumento desde un proceso real (host, cliente o intruso);
  - `seam_`: estado local inyectado, siempre rotulado con lo que se inyectó;
  - `local_`: un proceso con ticks manuales de `SimClock`, `ActorMotor` y la extensión, como el fixture de 900 acciones de Codex.
- **Igualdad:** SHA-256 de `var_to_bytes(samples())`, sin tolerancia (misma DLL y mismos datos).
- **Tiempos entre procesos:** reloj del sistema (`Time.get_unix_time_from_system()`). Tiempos dentro de un proceso: `Time.get_ticks_msec()`, el mismo reloj que usa el canal.
- **Límites:** 8 s por proceso, contados desde fuera, y plazo interno menor. Ritmo real en los modos de red; ticks manuales en los locales.
- **Categorías:** PASS/FAIL deciden. INSUFICIENTE: el caso no se pudo ejercitar o su control falló. HALLAZGO: comportamiento medido que contradice una propiedad que el contrato necesita, sin ser un FAIL de un criterio declarado por Codex. INFO: dato.

## 2. Parte R: reproducción y regresión

| Id | Qué | Decide |
| --- | --- | --- |
| R1 | `tools/testing/run_object_lifecycle_probe.ps1` de Codex, sin cambios, en mi copia y con mi DLL: `net_future`, `net_close`, `net_timeout`, `net_lease` y `action_window` PASSED, código 0, sin líneas de error, cada proceso < 8 s | sí |
| R2 | Mi `cv13` en `future`, `rpc` y `capacity`, sin cambios, para registrar cómo quedan los criterios viejos con el contrato nuevo | no: INFO, comparado con la corrida final de la 13. Lo esperado por lectura: `future` aplica sobres antes de la final; en `capacity`, desde la 257 ya no hay `action_capacity`; en `rpc`, el cliente se entera del cierre. |

## 3. Parte A: acciones (`cv14_local`, modo `actions`)

Fixture propio de un proceso: actor real, piso, `SimClock` con ticks manuales, `clock_adapter`, `history_bridge` y `ClientPrediction` reales. Las autoridades usan el snapshot del propio mundo en el tick presente (cero pasos), salvo en A6.

- Una acción por tick desde el 1, en el proveedor de inputs. Agarrar en ticks impares y soltar en pares, con intención de mano.
- IDs crecientes con saltos pseudoaleatorios de 1 a 9 (semilla fija).
- Sin confirmaciones, salvo las de las pruebas.

| Id | Qué | Esperado | Decide |
| --- | --- | --- | --- |
| A1 | Más de 700 acciones en el mismo vínculo, sin confirmaciones generales | Todas `queued`. Un `effect_ready` por id, ninguno repetido. Ningún `action_capacity`. | sí |
| A2 | Memoria en cada tick: activas del adaptador, `_known_actions`, `_effects`, `_confirmed` y `_commands` | Cada una ≤ 123 (121 ticks de ventana + 2 en cola). El máximo de 400–700 no supera al de 200–400. `retired_before_tick == tick − 120`. Marca de retiro no decreciente. | sí |
| A3 | Primera confirmación tardía: la acción del tick `T` recibe su primer ACK a `T + d`, con d = 0, 24, 119, 120, 121, 122 y 200, en un sobre válido del presente | El sobre se acepta. `action_confirmed` sale solo con d ≤ 120 (borde por lectura). | sí: cualquier otro borde es FAIL de mi lectura o de la política |
| A3h | Si con d ≥ 121 la acción nunca se confirmó y no hubo ninguna señal de vencimiento | HALLAZGO si se confirma: la escena no distingue «confirmada tarde» de «nunca confirmada» | HALLAZGO |
| A4 | El mismo ACK repetido en sobres de `T`, `T+1`, `T+9`, `T+49`, `T+120`, `T+121` y `T+249` | Una sola confirmación. Sin error, también después del retiro. | sí |
| A5 | ACK inválidos, uno por sobre, con un snapshot válido: id 0; id mayor que el máximo emitido; tipo distinto en activa; tick pedido distinto en activa; aplicado < pedido; aplicado > tick del sobre; id repetido en el mismo sobre; id retirado con tick pedido ≥ `_retired_before_tick`; 17 ACK; id negativo; tipo `throw` | Sobre rechazado. Mundo, `last_authority`, confirmaciones y efectos sin cambio. | sí |
| A5i | ACK de un hueco nunca emitido por debajo de la marca, con tick viejo; ACK retirado con tipo cambiado | Se informa si se aceptan en silencio (por lectura, sí) | INFO |
| A6 | Reintentos: repetición idéntica de una activa; mismo id con otro contenido; reintento idéntico de una retirada; hueco por encima de la marca; hueco por debajo; id 0, −1 y 0x80000000 | `known` sin efecto nuevo; `action_identity_conflict`; `retired_action`; `nonmonotonic_action_id`; rechazo (se anota el motivo); `invalid_action`. Cada rechazo es atómico: mundo y activas sin cambio. | sí |
| A7 | Replay positivo de 24 pasos con una acción en cada tick: checkpoint propio 24 ticks atrás, con el adaptador listo | Mundo igual al de antes del replay. Ningún efecto nuevo. | sí |
| A8 | Recuperación de 24 pasos con acciones: invalidar desde `C+1` y aplicar el checkpoint de `C`, con el adaptador detenido | Recupera. Mundo igual al de antes. Ningún efecto nuevo. | sí |
| A9 | Suspensión de 150 ticks, con un pedido de acción por tick durante la suspensión | Todos `rejected` por `not_ready`, sin efectos. Al final, 0 activas, registrador vacío y marca = máximo. | sí |
| A9b | Después: autoridad del presente desde un mundo de referencia que avanzó solo, más un ACK retirado nunca confirmado | Recupera. Mundo igual al de referencia. Sin confirmación tardía. | sí |
| A9c | Después: 30 acciones nuevas con ids mayores | Encoladas, un efecto cada una | sí |
| A10 | Id 0x7FFFFFFF y después otra acción | La primera se encola. La siguiente se rechaza, sin wrap. | sí |

## 4. Parte P: puente con un canal de prueba (`cv14_local`, modo `bridge`)

- **Puente:** `scene_network_bridge.gd` real con `history_bridge`, `clock_adapter` y el actor reales.
- **Canal de prueba:** un nodo mío con `take_packet()`, `stats()` y la señal `closed`, que entrega los sobres en el tick que fijo. Es un `seam_`: reemplaza solo el transporte, que ya se prueba en las partes L y N.
- **Sobres:** del mundo de referencia «host», que avanza sin mano con `step(TICK_DT)`. El cliente no agarra nada, así que después de aplicar un sobre su mundo debe ser **igual al de referencia en el mismo tick** (control de exactitud).

| Id | Qué | Esperado | Decide |
| --- | --- | --- | --- |
| P1 | Sobre futuro, seguido de 30 sucesores mientras espera | El primero no se desplaza y se aplica al alcanzarlo. Después se aplica el último sucesor, en su tick. Los intermedios nunca se aplican. | sí |
| P2 | Ocupación en cada tick y en cada llamada | Como mucho dos sobres en el puente. Ningún tick aplicado mayor que el reloj. | sí |
| P3 | Mismo tick con revisión nueva mientras espera | Reemplaza al pendiente; se aplica la revisión nueva | sí |
| P4 | Pausa: reloj detenido y `after_actor_tick()` llamado 20 veces con sobres futuros | Nada se aplica en pausa. Al seguir, se aplica en su tick. | sí |
| P5 | Falta de base inyectada (`actor_baseline_ready = false`, `seam_`) mientras llegan un pendiente alcanzable y dos sucesores | Nada se aplica sin base. Al volver la base, el sucesor ya alcanzable gana y el pendiente viejo no se aplica. | sí |
| P6 | Corrección real del actor con `reconcile_actor` (estado del host desplazado), con un sobre alcanzable esperando | El adaptador se detiene por la corrección. El sobre se aplica por el camino de recuperación con los cuadros corregidos. Queda listo, igual a la referencia. | sí |
| P7 | Pendiente que se rechaza (contexto equivocado) con un sucesor futuro | Un `object_authority_rejected`. Después se aplica el sucesor. | sí |
| P8 | Cierre del canal con pendiente futuro y sucesor | Los dos slots vacíos, base inválida, adaptador detenido. No se aplica nada después. | sí |
| P9 | Exactitud después de cada aplicación | Mundo igual a la referencia en el mismo tick | sí |

## 5. Parte L: controles y plazos con tres procesos (`cv14_lanes`)

- **Procesos:** host (servidor ENet que acepta dos clientes), cliente e intruso. El host vincula cada carril al cliente, que se identifica con un saludo.
- **Carriles:** son nodos `authority_channel.gd` sin cambios, en la misma ruta en los tres procesos. Cada uno tiene su propio ámbito y corren en paralelo.
- **Sobres opacos de 4 KB:** quedan en el canal del receptor y nunca llegan a un deserializador nativo.
- **Tiempos:** `t0` es el inicio común, avisado por el host.
- **Ámbito viejo:** cada campo menos 1 (conexión, contexto, uid, época, sesión) y la firma de mano con un byte cambiado.

| Carril | Qué | Esperado | Decide |
| --- | --- | --- | --- |
| `notice` | Publica en 0,3 s; el host hace `stop()` en 1,0 s. Después, `start` de nuevo en las dos puntas. | El cliente cierra una vez con `peer_closed` antes de 0,5 s; el host una vez. Los dos `start` dan falso. | sí |
| `scope_close` | Publica en 0,3 s. En 1,0 s, `_remote_close` real con ámbito viejo (6 variantes) y con 0, 51 y 53 bytes, del host al cliente y del cliente al host. En 5,0 s, `stop()` legítimo del host. | Nadie cierra antes de 5,0 s; el cierre legítimo sí llega (control) | sí |
| `scope_heartbeat` | Publica en 0,3 s; en 1,0 s el host hace `stop(false)` (aviso perdido). Desde ahí, latidos reales del host con ámbito viejo cada 100 ms. | El cliente cierra con `peer_idle_timeout`. Su última actividad es ≤ silencio + 0,25 s. Cierra entre 5000 y 5150 ms después de esa actividad. | sí |
| `good_heartbeat` | Igual, pero los latidos llevan el ámbito correcto | El cliente sigue vinculado al final (≥ 5,3 s de silencio legítimo). Es el control de que los latidos sí renuevan. | sí, si falla `scope_heartbeat` queda INSUFICIENTE |
| `intruder_close` | Publica en 0,3 s. En 1,0 s el intruso manda `_remote_close` con el ámbito **correcto** al host y al cliente (reenviado por el servidor). En 5,0 s, `stop()` legítimo **del cliente**. | Nadie cierra antes de 5,0 s; después el host cierra con `peer_closed` (cierre desde el cliente) | sí |
| `intruder_heartbeat` | Publica en 0,3 s; en 1,0 s el cliente hace `stop(false)`. El intruso manda latidos con el ámbito correcto al host cada 100 ms. | El host cierra con `peer_idle_timeout`, con su última actividad ≤ silencio del cliente + 0,25 s | sí |
| `startup` | Vinculados sin tráfico | Las dos puntas cierran con `peer_idle_timeout`, entre 5000 y 5150 ms después de su `start`. El cliente **no** cierra por `peer_closed`. | sí |
| `send_timeout` | `seam_`: al cliente le pongo `_last_revision = 0x7FFFFF00`, así rechaza todo sobre y no manda ACK. El host publica en 0,3 s. | El host cierra con `send_timeout` entre 5000 y 5150 ms después del inicio de la transferencia, en tiempo real, y el cliente cierra con `peer_closed`. Si el host cierra con `peer_idle_timeout`, se anota como pérdida de latidos. | sí (INSUFICIENTE si cierra por ausencia) |
| `both_close` | Las dos puntas hacen `stop()` en 1,0 s | Un `closed` por punta | sí |
| `quiet` | Publica en 0,3 s y después nada, con las dos puntas vivas hasta el final | Nadie cierra. Se anota el hueco máximo entre actividades de cada punta. | sí |
| `quiet_idle` | Igual que `quiet` | Duplicado de `quiet` para tener dos muestras por corrida | sí |

En los tres procesos se anota cada 100 ms el `PEER_PACKET_THROTTLE` de ENet hacia cada peer (INFO).

## 6. Parte N: recorrido completo de dos procesos (`cv14_net`)

Hereda la escena `probe_network.gd` de Codex sin cambiar su protocolo: NetSync real, actor, `history_bridge`, `scene_network_bridge`, publicación cada 4 ticks, agarre en 3 y suelta desde 38. Solo agrego observación y el momento de cada evento.

| Modo | Variación | Esperado | Decide |
| --- | --- | --- | --- |
| `close_host` | `stop()` del host en su tick 40, con transferencias en vuelo; los relojes siguen 60 ticks | Ver «Cierre» abajo. El cliente cierra con `peer_closed` antes de 0,5 s. | sí |
| `close_client` | `stop()` del cliente en su tick 40 | El host cierra con `peer_closed` antes de 0,5 s. Cierre en el cliente. | sí |
| `close_both` | `stop()` de las dos puntas en su tick 40 | Un `closed` por punta; cierre en el cliente | sí |
| `lease_silent` | `stop(false)` del host en su tick 40 | El cliente cierra con `peer_idle_timeout`, entre 5000 y 5150 ms después de su última actividad. Cierre en el cliente. | sí |
| `quiet` (×3) | El host publica hasta su tick 40 y después no; NetSync sigue en las dos puntas hasta 6,3 s después del arranque | **Nadie cierra.** Se anotan el hueco máximo entre actividades y el estrangulamiento de ENet. | sí: un cierre por ausencia con los dos vivos es FAIL |
| `future` | El cliente arranca 0,5 s tarde y se pausa 25 cuadros en su tick 100. El host publica hasta su tick 240. | No se aplica ningún tick futuro, tampoco en pausa. Como mucho dos sobres en el puente en cada cuadro. El fijado no se desplaza. Se aplican ≥ 3 sobres antes de la final. Final igual en el tick 240. | sí |

**Cierre en el cliente** (después de que cierra, con el reloj andando):

- un solo `closed`;
- canal sin rearmado ni pendiente; los dos slots del puente vacíos; base inválida; adaptador detenido;
- en los ticks siguientes, el tick y el SHA del mundo nativo no cambian, y no se aplica ningún sobre;
- `history.queue_action` da `not_ready`;
- un `start` nuevo del canal y del puente da falso.

En el host:

- un solo `closed`;
- envío y pendiente vacíos;
- `publish` da falso.

## 7. Lo que no se certifica

Integración en `net_lab.gd`, inventario o permisos reales, ledger de inventario, dos PC, rendimiento, memoria pico del proceso, pérdida real de red, ni deserialización de snapshots hostiles (N3). Los efectos y confirmaciones de acciones no se usan como prueba de transacciones.
