# Verificación independiente de la entrega 15

2026-11-17. Claude, sobre `76a71bb`.

- **Criterios:** [criterios_entrega_15.md](criterios_entrega_15.md), commit `3fea888`, guardados antes de correr nada.
- **Instrumentos:** `a81a497`, commiteados antes de su primera corrida.
- **Instrumentos de la 14:** no cambiaron.

## Veredicto

**Las dos correcciones funcionan en todo lo que pude ejercitar: 0 FAIL, 0 INSUFICIENTE.**

- **H1 (plazo que cerraba vínculos vivos): resuelto en loopback.**
  - En 6 corridas de tres procesos, ningún carril con el canal nuevo cerró. El hueco máximo de actividad fue de 504–511 ms en todas.
  - **La prueba tuvo poder:** en 3 corridas ENet tiró latidos no confiables. En dos de ellas, los carriles de control con el latido viejo (no confiable) **se cerraron solos** en la misma corrida: el host recibió 1 latido de 12. Los carriles con el canal nuevo, uno al lado del otro, recibieron 12 de 12.
  - **En el recorrido completo con NetSync:** el host no pasó de 510 ms sin señal en 4 corridas (en la 14 llegaba a 3,6 s), con el sentido cliente → host estrangulado hasta en 45 de 59 muestras.
  - **El plazo sigue en 5000 ms** y el latido en 500 ms (leído en cada corrida).
- **H2 (confirmación vencida sin señal): resuelto.** `action_expired` sale una sola vez por acción, en `T + 121`, con su identidad original:
  - 308 vencimientos, exactamente los esperados;
  - también para una acción cancelada por la suspensión y en un tick sin captura;
  - nunca para una confirmada, ni dentro de un replay o una recuperación;
  - con la limpieza hecha antes del callback.
- **Regresiones:** el puente y los cierres siguen en PASS.

No apruebo integración del laboratorio, inventario, dos PC, red real, memoria pico ni rendimiento.

## Base

- **Copia:** avance directo `8073085` → `76a71bb`. Los 348 archivos de `../entrega_15.json` coinciden (seis solo en LF).
- **Núcleo, `scripts/` y `scenes/`:** sin cambios. No recompilé ni corrí N3. Mi DLL sigue siendo `64679e73…`.
- **Código leído:**
  - `_heartbeat` pasa de `unreliable` a `reliable`, en el canal 0;
  - `history_bridge` agrega `action_expired` en `_trim()`, que ahora también corre al principio de `_tick_finished`.

## Override de latidos

Mi `cv14_tap_channel.gd` redeclaraba `_heartbeat` como `unreliable`, así que los carriles de `cv14_lanes` medían el canal viejo. Lo resolví sin tocar los originales:

- **`cv15_tap_channel.gd`:** redeclara `_heartbeat` y `_remote_close` con la configuración del canal base, cuenta llegadas por remitente y llama al original.
- **Chequeo de configuración:** cada proceso de `cv15_lanes` compara al arrancar `get_rpc_config()` de esa subclase con la del canal base. Coincidieron en los 18 procesos:

  | Script | `_heartbeat` |
  | --- | --- |
  | Canal base | `transfer_mode` 2 (confiable), canal 0 |
  | Subclase nueva | igual |
  | Subclase vieja | `transfer_mode` 0 (no confiable) |

- **Dos carriles con el canal base sin subclase** (`quiet_base`, `quiet_base_2`), para que el resultado no dependa de mi subclase.
- **Dos carriles con la subclase vieja** (`quiet_unrel`, `quiet_unrel_2`) como control negativo: miden si en esa corrida ENet tiró latidos no confiables.

## R: reproducción y regresión — PASS

- **R1:** `run_object_lifecycle_probe.ps1` de Codex, sin cambios, en mi copia con mi DLL. Los 6 modos (`net_future`, `net_close`, `net_timeout`, `net_lease`, `net_quiet` y `action_window`) dan PASSED, código 0. El más largo dura 6,8 s.
- **R2:** mi `cv14_local` sin cambios.
  - `actions`: 1876 comprobaciones, 0 fallas.
  - `bridge`: 269 comprobaciones, 0 fallas (P1–P9).
  - La fila A3h del calificador de la 14 sigue diciendo «ninguna señal de vencimiento»: es texto fijo, porque ese instrumento no escucha la señal nueva. Queda reemplazada por la parte E.
- **R3:** mi `cv14_net` sin cambios, que usa el canal base.
  - `close_host`: el cliente cierra con `peer_closed` en 6 ms.
  - `close_client`: el host cierra con `peer_closed`.
  - `close_both`: un cierre por punta.
  - `lease_silent`: el cliente cierra con `peer_idle_timeout` 5003 ms después de su última actividad.
  - `future`: 10 sobres antes del 240, ninguno futuro, ocupación máxima 2, 0 desplazados, final igual.
- **R4:** `quiet` ×4 con NetSync andando. Nadie cerró, con estos huecos máximos de actividad:

  | Corrida | Host | Cliente | Cliente → host en ≤ 1 de 32 |
  | --- | --- | --- | --- |
  | 1 | 510 ms | 506 ms | 0 de 63 muestras |
  | 2 | 510 ms | 505 ms | 16 de 63 |
  | 3 | 505 ms | 505 ms | 45 de 59 |
  | 4 | 505 ms | 504 ms | 11 de 63 |

## E: vencimiento de acciones (`cv15_local`, modo `expiry`) — PASS

Un proceso, 600 ticks manuales, 731 comprobaciones, 0 fallas.

| Id | Resultado |
| --- | --- |
| E1 | Los 308 vencimientos traen el id, el tipo y el tick pedido originales, y salen con el reloj en `T + 121` |
| E2 | Ningún id vence dos veces |
| E3 | El conjunto de vencidas es exactamente el de las conocidas y nunca confirmadas: 308 de 308 |
| E4 | ACK a d = 120 (acciones 101 y 107): confirmadas, nunca vencen |
| E5 | Acciones 103 y 109: vencen en 224 y 230. El sobre con su ACK, en ese mismo tick, se acepta sin confirmar y sin vencimientos nuevos: el vencimiento sale antes que el sobre. |
| E6 | ACK repetido de la 103 a d = 150 y 200: aceptado, sin confirmación ni segundo vencimiento |
| E7 | Las 90 confirmadas al instante y las de d = 120 nunca vencen |
| E8 | La acción encolada en el 429 para el 431 y cancelada por la suspensión del 430 vence en el 552 con su identidad, y nunca tuvo efecto |
| E9 | En el 470, sin captura y con el adaptador suspendido, la acción del 349 vence igual en el 470 |
| E10 | Replay positivo de 24 pasos (300 desde 276), exacto. Corrección real del actor en el 310 y recuperación desde el 306. Ninguna emite vencimientos ni efectos nuevos. |
| E11 | Dentro del callback, el id ya no está en `_known_actions`, `_effects` ni `_confirmed`, y figura como retirado. Un `queue_action` del mismo id y contenido da `retired_action` en los 217 casos con el adaptador listo, sin cambiar las activas. |
| E12 | Máximo de [activas, conocidas, efectos, confirmadas]: [121, 121, 121, 40] en 130–300 y [121, 121, 121, 31] en 300–600. No crece. |
| E13 | Un efecto por acción ejecutada; la cancelada no tiene ninguno |

**INFO:** en los 91 vencimientos con el adaptador suspendido, el `queue_action` de reentrada da `not_ready`, porque el adaptador mira primero si está listo. Es correcto por lectura: igual rechaza.

## L: tres procesos con el canal nuevo (`cv15_lanes`) — PASS

- **Corridas:** seis.
  - Cuatro normales: `lanes15` a `lanes15_4`.
  - Dos con un intento de estrangulamiento rotulado (`lanes15_stress`): cada proceso llama `throttle_configure(100, 0, 32)` sobre sus peers ENet.

| Id | Resultado en las 6 corridas |
| --- | --- |
| L0 | Configuración RPC de la subclase nueva = canal base en los 18 procesos; plazo 5000 ms y latido 500 ms |
| L1 | `notice`, `scope_close`, `intruder_close`, `startup`, `send_timeout` y `both_close` como en la 14: cierre en ms, avisos falsos ignorados, caducidades a 5002–5007 ms, caducidad de envío real y un cierre por punta |
| L2 | El control `good_heartbeat` sigue vinculado (llegaron 51–52 de 52). `scope_heartbeat` e `intruder_heartbeat` cierran a 5002–5007 ms de la última actividad legítima, con 51–52 latidos falsos **llegados** y rechazados. |
| L3 | `quiet` y `quiet_idle` (subclase nueva) y `quiet_base` y `quiet_base_2` (canal base): ningún cierre; huecos de 504–511 ms en las dos puntas; 12 de 12 latidos llegados en cada sentido donde hay conteo |

**L4, el poder de cada corrida:**

| Corrida | Latidos del control no confiable que llegaron al host | Cierre del control | Estrangulamiento medido |
| --- | --- | --- | --- |
| `lanes15` | 12/12 | no | sin estrangulamiento |
| `lanes15_2` | **5/5** | no | cliente → host en ≤ 1 en 21 de 62 muestras |
| `lanes15_3` | 8/9 | no | cliente → host en ≤ 1 en 11 de 61 |
| `lanes15_4` | 9/8 | no | cliente → host en ≤ 1 en 11 de 61 |
| `lanes15_stress` | **1/1** | **cerró solo** (`peer_idle_timeout`) | cliente → host en ≤ 1 en 52 de 61 |
| `lanes15_stress_2` | **1/1** | **cerró solo** | cliente → host en ≤ 1 en 52 de 61; host → cliente mínimo 0, en ≤ 1 en 31 de 61 |

- Hay **estrés** por el umbral fijado (≤ 6 llegadas o cierre) en 3 de las 6 corridas.
- En esas tres, los cuatro carriles con canal nuevo no cerraron y tuvieron huecos ≤ 511 ms.
- **L5, H1: PASS.**

## Lo que no se certifica

- **Red real:** la prueba es en loopback, sin red real ni pérdida real.
- **Por lectura, sin medir:** con estrangulamiento bajo y una ida y vuelta real, ENet también achica la ventana de datos confiables en vuelo. No medí si eso alarga las transferencias grandes hacia su caducidad de 5 s.
- **Fuera del alcance:** integración en `net_lab.gd`, InvHands, permisos, inventario o ledger, política de suelta sin confirmar, varias manos, presentación, dos PC, notebook, rendimiento, memoria pico ni N3.
- `action_expired` no se usó como prueba de transacciones.

## Evidencia (en `tmp/`, sin versionar)

- `tmp/lifecycle_probe/20261117_215919_805787`: R1
- `tmp/validacion_objetos/entrega_15/check15_20261117_185846`: verificación de sintaxis que encontró un error de análisis en `cv15_lanes.gd` (`get_rpc_config()` sobre la clase). Lo corregí antes del commit de los instrumentos; esa verificación no corre pruebas.
- `tmp/validacion_objetos/entrega_15/check15_20261117_185903`: verificación limpia
- `tmp/validacion_objetos/entrega_15/run15_20261117_185948`: la corrida completa, con 39 procesos, ninguno vencido, código 0 y solo la línea esperada del control de 0 bytes. Tiene `cv15_report.json` y `cv14_report.json`.
