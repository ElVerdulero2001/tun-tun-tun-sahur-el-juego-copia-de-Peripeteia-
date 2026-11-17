# Criterios fijados antes de ejecutar: verificación de la entrega 15

2026-11-17. Validación independiente de Claude sobre `76a71bb`. Encargo: «Encargo para Claude: entrega 15» de `docs/net/entregas/revision_codex_entrega_14.md`. Se escribe y se guarda en el historial **antes** de correr nada, incluido el runner de Codex.

## 0. Base y lectura del código

- **Copia:** avance directo `8073085` → `76a71bb`. Los 348 archivos de `../entrega_15.json` coinciden (seis solo en LF). Mis instrumentos de las entregas 10 a 14 no cambiaron.
- **Sin cambios:** núcleo nativo, `scripts/`, `scenes/` y `project.godot`. No se recompila ni se repite N3. Mi DLL sigue siendo `64679e73…`.
- **`authority_channel.gd`:** solo cambia `_heartbeat` de `unreliable` a `reliable`, en el mismo canal 0 que `_remote_close`. El intervalo (500 ms), el plazo (5000 ms), el ámbito y el remitente no cambian.
- **`history_bridge.gd`:**
  - nueva señal `action_expired(id, kind, requested_tick)`, emitida en `_trim()` para cada acción conocida que el adaptador retiró sin confirmación, **después** de borrarla de `_known_actions`, `_effects` y `_confirmed`;
  - `_trim()` ahora corre también al principio de `_tick_finished`, antes de mirar si hubo captura; también corre en `_finish_replay`;
  - **borde por lectura:** el adaptador retira en `_after_tick(N)` las acciones con tick `< N − 120`, y el registrador emite en el mismo tick. El vencimiento sale con el reloj en `T + 121`. Un ACK a `T + 120` confirma, y uno a `T + 121` llega después del vencimiento de ese mismo tick (el puente aplica sobres después del registrador) y se ignora;
  - una acción encolada que nunca se ejecutó (cola borrada al suspender) sigue en el registro del adaptador hasta su retiro, así que también vence.
- **Instrumentos míos afectados:** `cv14_tap_channel.gd` redeclara `_heartbeat` como `unreliable`. Los carriles de `cv14_lanes` **no prueban** el canal nuevo. Se conservan sin cambios y no se usan para aprobar nada. En esta entrega cumplen solo el papel de control negativo (abajo).

## 1. Qué decide

- **Etiquetas, igualdad y tiempos:** como en la entrega 14 (`run_`, `rpc_`, `seam_`, `local_`). SHA de `samples()` sin tolerancia; reloj del sistema entre procesos.
- **Límite:** 8 s por proceso.
- **Categorías:** PASS/FAIL deciden. INSUFICIENTE: el caso no tuvo poder (por ejemplo, no hubo estrangulamiento que lo pusiera a prueba) o falló su control. HALLAZGO e INFO, como antes.
- **El plazo sigue siendo 5000 ms.** Un PASS de silencio no vale si el plazo cambió (se lee `TIMEOUT_MS` en cada corrida).

## 2. Parte R: reproducción y regresión

| Id | Qué | Decide |
| --- | --- | --- |
| R1 | `tools/testing/run_object_lifecycle_probe.ps1` de Codex sin cambios, en mi copia con mi DLL: los 6 modos (incluido `net_quiet`) PASSED, código 0, < 8 s | sí |
| R2 | Mi `cv14_local` sin cambios: `actions` (1876 comprobaciones) y `bridge` (269) sin fallas. A3h del calificador de la 14 es texto fijo: queda reemplazado por la parte E. | sí |
| R3 | Mi `cv14_net` sin cambios (usa el canal base, sin subclase): `close_host`, `close_client`, `close_both`, `lease_silent` y `future` con los mismos criterios de la entrega 14 | sí |
| R4 | `cv14_net` `quiet` ×4, NetSync andando: nadie cierra, y **hueco máximo de actividad < 1000 ms en las dos puntas**. En la 14 llegó a 3636 ms en el host. | sí |

## 3. Parte E: vencimiento de acciones (`cv15_local`, modo `expiry`)

Fixture propio de un proceso, como `cv14_local`: actor, piso, `SimClock` con ticks manuales, `clock_adapter`, `history_bridge` y `ClientPrediction` reales.

**Recorrido:**

- **Ticks 1–400:** una acción por tick (agarrar en impares, soltar en pares), con IDs crecientes y saltos de 1 a 9.
- **Confirmación inmediata (grupo C):** las acciones de ticks múltiplos de 3 **hasta el 270** reciben su ACK en el mismo tick, en un sobre de cero pasos. Desde el 271 no hay sobres, para que el replay del 300 y la recuperación del 310 no tengan un sobre posterior a su checkpoint.
- **Confirmaciones especiales:**
  - ACK a d = 120 para las acciones de los ticks 101 y 107;
  - ACK a d = 121 para las de 103 y 109;
  - ACK repetido a d = 150 y 200 para la de 103.
- **Replay positivo** de 24 pasos en el 300.
- **Corrección real del actor** (`reconcile_actor`) en el 310, y recuperación desde el checkpoint del 306.
- **Acción cancelada:** en el 429 se encola una acción para el 431, y en el 430 se suspende el adaptador hasta el final, así que esa acción nunca se ejecuta.
- **Falta de captura:** en el 470, durante la suspensión, no se captura el input.
- **Fin:** se corre hasta el 600.

| Id | Qué | Esperado | Decide |
| --- | --- | --- | --- |
| E1 | Identidad y momento | Cada `action_expired` trae el id, el tipo y el tick pedido originales, y sale con el reloj en `T + 121` | sí |
| E2 | Una sola señal | Ningún id vence dos veces | sí |
| E3 | Completitud | Los ids vencidos son exactamente las acciones encoladas y nunca confirmadas con `T + 121 ≤ 600` | sí |
| E4 | ACK a d = 120 | Confirmada; nunca vence | sí |
| E5 | ACK a d = 121 | El vencimiento sale en `T + 121`. El sobre con el ACK se acepta, sin confirmación. | sí |
| E6 | ACK tardío repetido (d = 150 y 200) | Sin confirmación ni un segundo vencimiento | sí |
| E7 | Confirmadas que se retiran (grupo C, d = 120) | Ninguna vence | sí |
| E8 | Acción cancelada por la suspensión | Vence en `431 + 121 = 552` con su identidad. Nunca tuvo efecto. | sí |
| E9 | Falta de captura en el 470 | El vencimiento que toca en el 470 sale en el 470 | sí |
| E10 | Replay positivo y recuperación tras corrección | Las dos se aceptan. No emiten vencimientos repetidos ni fuera de su tick. Ningún efecto nuevo. | sí |
| E11 | Limpieza antes del callback, dentro del callback | El id ya no está en `_known_actions`, `_effects` ni `_confirmed`, y `is_retired_action(id)` es verdadero. Un `queue_action` del mismo id y contenido da `retired_action`, sin cambiar las activas. | sí |
| E12 | Memoria | Activas, conocidas, efectos y confirmadas ≤ 123 en todo el recorrido. El máximo de 300–600 no supera al de 130–300. | sí |
| E13 | Efectos | Un efecto por acción ejecutada; la cancelada no tiene ninguno | sí |

## 4. Parte L: tres procesos con el canal nuevo (`cv15_lanes`)

Copia de `cv14_lanes` (que no se toca) con dos cambios:

- **Subclase nueva de conteo, `cv15_tap_channel.gd`:** redeclara `_heartbeat` y `_remote_close` con la misma configuración RPC que el canal base (confiable, canal 0), cuenta llegadas por remitente y llama al original.
  - **Al arrancar, cada proceso compara `get_rpc_config()`** de la subclase con la del canal base para esos dos métodos. Si difieren, la corrida queda inválida (FAIL del instrumento).
- **Carriles nuevos:**
  - `quiet_base` y `quiet_base_2`: **canal base sin subclase**, publican en 0,3 s y después callan;
  - `quiet_unrel` y `quiet_unrel_2`: la subclase **vieja** `cv14_tap_channel.gd` (latido no confiable), con el mismo silencio. Son el **control negativo**: miden si en esa corrida ENet tiró latidos no confiables.

| Id | Qué | Esperado | Decide |
| --- | --- | --- | --- |
| L0 | Configuración RPC de la subclase nueva = canal base (`_heartbeat`, `_remote_close`) en los tres procesos. La vieja difiere en `_heartbeat`. | Igual / distinta | sí (invalida la corrida) |
| L1 | `notice`, `scope_close`, `intruder_close`, `startup`, `send_timeout`, `both_close` | Los mismos criterios de la entrega 14 | sí |
| L2 | `good_heartbeat` (control), `scope_heartbeat` e `intruder_heartbeat` | Como en la 14. Con latido confiable, los latidos falsos deben llegar todos (se cuentan) y no renovar. | sí |
| L3 | Silencio con canal nuevo: `quiet`, `quiet_idle` (subclase nueva), `quiet_base` y `quiet_base_2` (base) | Nadie cierra. Hueco máximo de actividad < 1000 ms en cada punta. | sí: un cierre es FAIL |
| L4 | Poder de la corrida | Hay **estrés** si algún carril `quiet_unrel*` recibió ≤ 6 latidos en alguna punta o cerró por ausencia. Se anotan el estrangulamiento (`PEER_PACKET_THROTTLE`) y las llegadas. | — |
| L5 | Veredicto de H1 | PASS si ningún carril con canal nuevo cerró en ninguna corrida **y** al menos una corrida tuvo estrés. FAIL si alguno cerró. INSUFICIENTE si ninguna tuvo estrés. | sí |

**Corridas:**

- `lanes15` ×4;
- `lanes15_stress` ×2: igual, pero cada proceso llama `throttle_configure(100, 0, 32)` sobre sus peers ENet al empezar. Es un intento de estrangulamiento rotulado: puede no sostenerse, porque ENet lo vuelve a 32 cuando la ida y vuelta es menor que su variación.

## 5. Lo que no se certifica

Integración en `net_lab.gd`, inventario o ledger, política de suelta sin confirmar, varias manos, presentación, dos PC, red real o con pérdida real, rendimiento, memoria pico ni N3. `action_expired` no se usa como prueba de transacciones.
