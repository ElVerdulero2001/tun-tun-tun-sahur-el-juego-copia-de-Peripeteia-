# Verificación independiente de la entrega 14

2026-11-17. Claude, sobre `c127cf8`.

- **Criterios:** [criterios_entrega_14.md](criterios_entrega_14.md), commit `f863ce5`, guardados antes de correr nada.
- **Instrumentos:** `f8ffddc`, commiteados antes de su primera corrida.
- **Correcciones después de la primera corrida:** `f6abb64`, rotuladas abajo.

## Veredicto

**Las tres correcciones hacen lo que dicen en todo lo que pude ejercitar, salvo una cosa: el plazo de ausencia puede cerrar un vínculo vivo.**

- **Cierre remoto:** pasa de los dos lados y de los dos a la vez, con aviso perdido y con caducidad de envío real. Los controles con ámbito viejo o de otro peer llegan y se rechazan.
- **Cliente atrasado:** aplica sobres antes de la final, nunca un tick futuro, y el fijado no se desplaza. Con un canal de prueba, el puente cumple los nueve casos (pausa, sucesor alcanzable, falta de base, corrección real del actor, rechazo y cierre), exacto contra una referencia.
- **Retiro de acciones:** más de 700 acciones con IDs salteados, memoria constante en 121, el borde exacto de 120 ticks, ACK inválidos rechazados de forma atómica, replay y recuperación de 24 pasos con acciones, y suspensión de 150 ticks.
- **FAIL — el plazo cierra vínculos vivos:** con los dos procesos vivos y sin publicar, el vínculo se cerró solo por `peer_idle_timeout` en 3 de 6 carriles en silencio (2 de 3 corridas de `lanes`).
  - En el carril que cerró de la tercera corrida, el host recibió **0 latidos** del cliente.
  - En el recorrido completo con NetSync no hubo cierres en 6 corridas, pero el host pasó **hasta 3,6 s** sin ninguna señal del cliente (plazo: 5 s).
  - **Causa medida:** el latido es no confiable y ENet lo descarta cuando estrangula ese sentido (`PEER_PACKET_THROTTLE` 0–1 de 32), lo mismo que vi en la entrega 13.
- **HALLAZGO (A3h):** una acción cuyo primer ACK llega 121 ticks o más después queda sin confirmar para siempre, y la API no da ninguna señal de vencimiento. Es la política declarada, pero la escena no puede distinguir «nunca confirmada» de «todavía no».

No apruebo integración del laboratorio, inventario, dos PC, memoria pico ni rendimiento.

## Base

- **Copia:** avance directo `f6d3af4` → `c127cf8`. Los 333 archivos de `../entrega_14.json` coinciden con mi copia (seis solo en LF).
- **Núcleo:** sin cambios. No recompilé ni corrí N3. Mi DLL `64679e73…` sale de las mismas fuentes que la de Codex (`d7761f5f…`).
- **Lectura:** la del código está en la sección 0 de los criterios. Las corridas la confirmaron punto por punto, incluido el borde del retiro.

## R: reproducción y regresión

- **R1 PASS:** `run_object_lifecycle_probe.ps1` de Codex, sin cambios, en mi copia y con mi DLL.
  - `net_future`, `net_close`, `net_timeout`, `net_lease` y `action_window` dan PASSED con código 0.
  - El proceso más largo dura 6,4 s (`net_lease`).
- **R2 (INFO):** mi `cv13` en `future`, `rpc` y `capacity`, sin cambios, para ver cómo quedan los criterios viejos con el contrato nuevo.
  - **`future`:** aplica 9 sobres antes de la final (en la 13 eran 0). La seguridad sigue en PASS.
  - **`rpc`:** `I_cierre_de_un_solo_lado` ahora da que el cliente **no** sigue vinculado. `R_cierre_cliente` da FAIL porque esperaba que el `stop()` propio del cliente emitiera `closed`, y el aviso del host ya lo había cerrado. `B1r` sigue en FAIL por falta de ventanas calificables, como en la 13.
  - **`capacity`:** se encolan las 270 acciones (14 por encima de 256). El viejo C1 da FAIL porque el tope ya no existe.
  - Los tres FAIL vienen del cambio de contrato o ya estaban en la 13. No los reescribí.

## A: acciones (`cv14_local`, modo `actions`) — PASS

Corrida única, un proceso: 1876 comprobaciones, 0 fallas, 437 ms de ticks manuales.

| Id | Resultado |
| --- | --- |
| A1 | 730 acciones encoladas (1–700 y 851–880), un efecto cada una, ningún `action_capacity`; id máximo 3534 antes de A10 |
| A2 | Máximo de [activas, conocidas, efectos, confirmadas, comandos] = [121, 121, 121, 3, 120], igual en 200–400 que en 400–700. `retired_before_tick` = tick − 120 en todos los ticks desde el 119. La marca nunca baja. |
| A3 | Primer ACK a d = 0, 24, 119 y 120: aceptado y confirmado. A d = 121, 122 y 200: sobre aceptado, **sin confirmación**. El borde es exactamente el de la lectura. |
| A3h | **HALLAZGO** (ver abajo) |
| A4 | El mismo ACK en 241, 242, 250, 290, 361, 362 y 490 da una sola confirmación, sin errores después del retiro |
| A5 | Los 11 casos inválidos dan `invalid_action_confirmation`. En cada uno quedan sin cambio el mundo, `last_authority`, las confirmaciones, los efectos, las activas y la cola. |
| A5i (INFO) | Un ACK de un **hueco nunca emitido** por debajo de la marca, y uno de una acción retirada **con el tipo cambiado**, se aceptan en silencio, sin callback. Es la lectura: el retiro no guarda el original. |
| A6 | Repetición idéntica de una activa: `known`, sin efecto nuevo. Otro contenido: `action_identity_conflict`. Retirada: `retired_action`. Hueco sobre la marca: `nonmonotonic_action_id`. Hueco bajo la marca: `retired_action`. 0, −1 y 0x80000000: `invalid_action`. Todos atómicos. |
| A7 | Replay positivo de 24 pasos con 24 acciones: exacto, sin efectos nuevos |
| A8 | Recuperación de 24 pasos con 24 acciones, con el adaptador detenido: exacta, sin efectos nuevos |
| A9 | 150 pedidos en suspensión, todos `rejected:not_ready`, sin efectos. Al final: 0 activas, registrador vacío, marca = máximo (3534). |
| A9b | Recuperación de 10 pasos desde la referencia, exacta. El ACK de una acción retirada nunca confirmada (tick 650) no da confirmación tardía. |
| A9c | 30 acciones nuevas después de la suspensión, un efecto cada una |
| A10 | 0x7FFFFFFF se encola y da un efecto. Después todo se rechaza (`nonmonotonic_action_id`, `invalid_action`): no hay wrap. |

## P: puente con un canal de prueba (`cv14_local`, modo `bridge`) — PASS

- **Corridas:** dos, con 269 comprobaciones y 0 fallas cada una.
- **Referencia:** un mundo que avanza solo y recibe 9 empujones en ticks fijos, así que el cliente difiere de él hasta que aplica un sobre.
- **Aplicados, como `tick@reloj`:** 60@60, 90@90, 100@100, 108@108, 109@109, 119@122, 128@133 y 146@146.
- **Exactitud:** después de cada aplicación, el mundo es igual a la referencia en ese tick (P9).

| Id | Resultado |
| --- | --- |
| P1 | El futuro 60 queda fijado durante 30 sucesores y se aplica en su tick; después, el último sucesor (90) en el suyo. Los 29 intermedios (61–89) nunca se aplican. |
| P2 | Nunca un tick futuro; como mucho dos sobres en el puente |
| P3 | Mismo tick con revisión nueva: se aplica la nueva (revisión 33, no 32) |
| P4 | 20 llamadas en pausa con 108 y 109 esperando: nada se aplica. Al seguir, 108 y 109 en su tick. |
| P5 | Sin base (`seam_`) llegan 116, 118 y 119. Nada se aplica sin base. Al volver la base en 122 gana el sucesor 119, y 116 y 118 nunca se aplican. |
| P6 | Corrección real con `reconcile_actor` (15 cm, tick 127, en el 131): el adaptador se detiene y la base queda lista. El sobre 128 se aplica en el 133 por recuperación con los cuadros 129–133, rehechos o grabados después de la corrección, y queda exacto. |
| P7 | Un pendiente con contexto equivocado se rechaza una vez (`authority_scope`) y después se aplica su sucesor 146 |
| P8 | Al cerrar: los dos slots vacíos, base inválida, adaptador detenido; no se aplica nada después |

## L: controles y plazos con tres procesos (`cv14_lanes`)

- **Corridas:** tres, con host, cliente e intruso.
  - **Corrida 1** (`run14_20261117_180518`): todavía sin el contador de llegadas.
  - **Corrida 2** (`run14_20261117_180844`) y **corrida 3** (`run14_20261117_180921`): con la subclase de diagnóstico (abajo), que cuenta los controles que llegan por remitente.
- **Tiempos:** son relativos al inicio común.

| Carril | Corrida 1 | Corrida 2 | Corrida 3 | Veredicto |
| --- | --- | --- | --- | --- |
| `notice` | PASS (1 ms) | PASS (7 ms) | PASS (4 ms) | **PASS**. El cliente cierra con `peer_closed` y `start` de nuevo da falso en las dos puntas. |
| `scope_close` | PASS | PASS | PASS | **PASS**. 9 avisos con ámbito viejo o largo equivocado, de cada lado, no cierran nada; el legítimo en 5,0 s sí. |
| `intruder_close` | PASS | PASS | PASS | **PASS**. Los avisos con el ámbito correcto desde un tercer peer (también reenviados por el servidor) no cierran; el `stop()` del cliente en 5,0 s cierra al host con `peer_closed` en 7–10 ms. |
| `good_heartbeat` (control) | **FAIL**: el cliente cerró por ausencia en 5,3 s | PASS: llegaron 52 de 52 | PASS: llegaron 52 de 52 | **FAIL** en la corrida 1, por la causa de H1 |
| `scope_heartbeat` | INSUFICIENTE (falló su control) | PASS: llegaron 52 con ámbito viejo, cierre 5003 ms después de la última actividad legítima | PASS: 52, 5002 ms | **PASS** con control válido (corridas 2 y 3) |
| `intruder_heartbeat` | PASS (sin conteo) | PASS: llegaron 52 del intruso, cierre a 5002 ms | PASS: 50, 5006 ms | **PASS**. Los latidos del intruso llegan y no renuevan. |
| `startup` | PASS (5002/5002 ms) | PASS (5003/5003) | PASS (5006/5003) | **PASS**. Cada punta cierra sola, sin `peer_closed`. |
| `send_timeout` | PASS (5001 ms) | PASS (5001) | PASS (5006) | **PASS**. Caducidad de envío real en tiempo real (no inducida por reloj), y el aviso cierra al cliente. |
| `both_close` | PASS | PASS | PASS | **PASS**: un `closed` por punta |
| `quiet` | **FAIL**: el cliente cerró por ausencia (5,31 s) y avisó al host | PASS (12 latidos por lado) | PASS de justo: el host recibió **1** latido; hueco de 1,2 s | **FAIL** |
| `quiet_idle` | **FAIL**: el host cerró por ausencia (5,51 s) | PASS | **FAIL**: el host cerró por ausencia (5,32 s) con **0** latidos recibidos | **FAIL** |

**Estrangulamiento de ENet** (muestras cada 100 ms):

| Corrida | Host → cliente | Cliente → host |
| --- | --- | --- |
| 1 | mínimo 0, ≤ 1 en 50 de 61 | ≤ 1 en 16 de 61 |
| 2 | 32 todo el tiempo | 32 todo el tiempo |
| 3 | mínimo 30 | ≤ 1 en 21 de 61, < 32 en 60 de 61 |

## N: recorrido completo de dos procesos (`cv14_net`, escena de Codex)

| Modo | Resultado |
| --- | --- |
| `close_host` | **PASS**: el cliente cierra con `peer_closed` en < 1 ms. Ver «Cierre en el cliente» abajo. |
| `close_client` | **PASS**: el host cierra con `peer_closed` 5 ms después; cierre del cliente como arriba |
| `close_both` | **PASS**: un `closed` por punta. El cliente, que va adelante, paró primero, y el host cerró por su aviso (`peer_closed`) antes de su propio `stop()`. |
| `lease_silent` | **PASS**: el cliente cierra con `peer_idle_timeout` 5002 ms después de su última actividad, que fue 16 ms antes del silencio del host. Mundo congelado en los 8 ticks medidos. |
| `quiet` ×6 | **PASS** en las 6: nadie cerró. Hueco máximo de actividad en el host: 505, 513, 3141, 3636, 3624 y 2518 ms. En el cliente, ≤ 512 ms en todas. En las 4 con hueco largo, el sentido cliente → host bajó a ≤ 1 de 32 en 10 a 15 de ~60 muestras. |
| `future` | **PASS**: 9 sobres aplicados antes del 240, ninguno futuro. Ocupación máxima 2, 0 desplazados, 25 cuadros de pausa sin aplicaciones. Espera máxima del fijado: 32 ticks. Final igual en el 240. |

**Cierre en el cliente:**

- los dos slots vacíos, el canal sin rearmado ni pendiente, base inválida y adaptador detenido;
- en los 30 ticks siguientes, el mundo nativo congelado (tick y SHA) y ningún sobre aplicado;
- `queue_action` da `not_ready`, y un `start` nuevo del canal y del puente da falso;
- en el host, `publish` da falso.

## Hallazgos

### H1. El plazo de ausencia cierra vínculos vivos (FAIL de `quiet` en L)

- **Qué pasa:** el host solo sabe que el cliente sigue ahí por su latido, que es no confiable, y el cliente lo mismo del host, cuando no hay transferencias. ENet descarta esos paquetes cuando estrangula un sentido. En loopback lo hace por tramos de segundos, también sin tráfico de objetos (entrega 13).
- **Medido:**
  - en 3 de 6 carriles en silencio, el vínculo se cerró con los dos procesos vivos;
  - en la corrida 3, el cliente mandó unos 12 latidos por carril, y el host recibió 0 en uno y 1 en el otro;
  - en el recorrido completo con NetSync, el host llegó a 3,6 s sin señal (72 % del plazo) en una ventana de silencio de unos 5,5 s, que es lo que permite el límite de 8 s por proceso.
- **Consecuencia:** se ejecuta el mismo camino que un cierre real (invalida base y predicción del objeto). Le pasaría a un objeto quieto que el host deja de publicar.
- **Alcance:** una PC, loopback. No medí con qué frecuencia pasa en una red real ni con Radmin.

### H2. Confirmación vencida sin señal (A3h, HALLAZGO)

- **Qué pasa:** con el primer ACK a 121 ticks o más, el sobre se acepta y la acción queda sin confirmar, sin ningún callback de vencimiento. Codex lo declara como política. Lo marco porque la escena no tiene cómo saber que esa acción ya no se va a confirmar.
- **Solo por cálculo, sin medir:**
  - el canal manda 8 fragmentos de 960 bytes por cuadro y espera el ACK de transferencia antes del siguiente sobre;
  - un estado de 614 KB (128 cuerpos, entrega 9) tarda unos 80 cuadros;
  - con un sobre esperando detrás de otro en vuelo, un ACK podría llegar después de los 120 ticks.

## Otros datos

- **Control de 0 bytes:** el `_remote_close` sin bytes lo rechaza el propio Godot («Method expected 1 argument(s), but called with 0») antes de llamar al método. Es la única línea de error que queda en `lanes` después de las correcciones y es esperada. Los de 51 y 53 bytes llegan al método y se rechazan.
- **Con la subclase de diagnóstico** (corridas 2 y 3), los controles falsos sí llegan, así que los PASS de ámbito y peer son por rechazo, no por pérdida.

## Correcciones de mis instrumentos después de la primera corrida (`f6abb64`)

1. **`cv14_lanes`:**
   - el cliente y el intruso pedían a ENet las estadísticas de peers que no tienen (61 líneas `!peers.has(p_id)` por proceso); ahora solo piden las del servidor;
   - se agregó `cv14_tap_channel.gd`, una subclase que cuenta los controles recibidos por remitente y llama al método original sin cambios.
2. **`cv14_local`:** el modo `bridge` liberaba mal un `NetSync` fuera del árbol (aviso de objetos sin liberar al salir).
3. **`cv14_report.mjs`:**
   - `scope_heartbeat` ahora queda INSUFICIENTE si falla su control, como dicen los criterios (antes daba PASS);
   - `intruder_heartbeat` exige que haya llegado al menos un latido del intruso, una regla agregada después de la primera corrida.

La primera corrida se conserva entera.

## Lo que no se certifica

Integración en `net_lab.gd`, objetos reales, InvHands, permisos, inventario o ledger, varias manos, presentación, dos PC o notebook, red real, rendimiento, memoria pico ni N3.

## Evidencia (en `tmp/`, sin versionar)

- `tmp/lifecycle_probe/20261117_210454_22a3c6`: R1
- `tmp/validacion_objetos/entrega_14/check14_20261117_180336`: verificación de sintaxis
- `tmp/validacion_objetos/entrega_14/run14_20261117_180518`: corrida 1 completa
- `tmp/validacion_objetos/entrega_14/run14_20261117_180844`: `bridge`, `lanes` y `quiet` ×3
- `tmp/validacion_objetos/entrega_14/run14_20261117_180921`: `lanes`
- `tmp/validacion_objetos/entrega_14/network13_20261117_181002`: R2

Cada carpeta tiene `runner.json` (hashes de las copias, códigos y líneas de error) y `cv14_report.json`.
