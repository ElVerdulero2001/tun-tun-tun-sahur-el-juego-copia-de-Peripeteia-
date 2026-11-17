# Criterios fijados antes de ejecutar: verificación de la entrega 11

2026-11-17. Validación independiente de Claude sobre `0aed621`. Encargo: «Encargo de Claude: entrega 11» de `docs/net/entregas/revision_codex_entrega_10.md`. Se escribe y se guarda en el historial **antes** de compilar o correr nada.

## 0. Base y lectura del código

- **Copia:** avance directo `b49d3ec` → `0aed621`.
  - Los 87 archivos de `../entrega_11.json` coinciden (tres JSON solo en LF).
  - No cambiaron mis instrumentos, la producción, el núcleo, `Cargo.lock` ni `Cargo.toml`.
- **API nueva de `clock_adapter.gd`, leída antes de correr:**
  - **`apply_authority_trusted(packet)`:**
    - valida el sobre: 11 claves exactas, tipos y rangos, `version` 1, el ámbito de seis etiquetas igual a `authority_scope()`, revisión creciente, tick no menor que la última autoridad, snapshot entre 1 B y 1 MiB, y hasta 16 `acks` de acciones propias con `requested_tick` igual al original y `applied` entre el pedido y el tick del paquete;
    - después revisa presente, Tuning, presupuesto e historia, y compara el dt guardado contra `SimClock.world_dt`. Si difiere, invalida con recuperación;
    - recién entonces crea el candidato. La revisión se consume solo si tiene éxito.
  - **Las confirmaciones no producen ningún efecto:** solo se validan. La política de suelta tardía surge de importar un estado con tick ≥ aplicado y repetir lo posterior.
  - **`invalidate_history_from(tick, causa)`:** borra los frames desde ese tick y pide recuperación con una nueva generación. Si ya estaba detenido, la vuelve a cambiar y emite otra vez. Un tick futuro no hace nada.
  - **`recover_authority_trusted(packet, frames, generation)`:** exige estar detenido, la generación vigente, la fase entre ticks, un paquete válido, un lote completo T+1..presente (≤ 24) y frames de 5 claves con tipos, dt igual al reloj actual, input con su sesión y tick, y acciones iguales a las originales. Reemplaza mundo, diario y firma solo si termina.
  - **Por código:**
    - al suspender se vacía la cola de acciones, pero sus IDs quedan reservados: un duplicado devuelve `true` sin ejecutarse;
    - si el lote corregido trae una acción que nunca llegó a ejecutarse localmente, se aplica físicamente **sin** emitir `action_effect`;
    - el mapa colisionador → nodo sigue sin revisarse en los colisionadores sin pares (ya visto en la 9);
    - `history_expired` sigue inalcanzable mientras la autoridad no pueda retroceder.

## 1. Qué decide

- **Igualdad en el mismo tick:** SHA-256 de `var_to_bytes(samples())`.
- **Controles negativos:** separación > 1e-3.
- **Atomicidad de un rechazo:** devuelve `false` con el código esperado, y no cambian el mundo (bytes del snapshot), la última autoridad (tick y revisión), la generación, `ready_for_input`, los efectos ni las recuperaciones. En los rechazos previos al candidato, **0 llamadas a la fábrica**.
- **Límites externos:** 8 s por proceso y 180 s por compilación.
- **Ritmo:** mis modos corren con `--fixed-fps 60`.
- **No se repite** N3, y S1 de la entrega 10 **no se modifica**.

## 2. Parte P: compilación y reproducción

| Id | Qué | Decide |
| --- | --- | --- |
| P1 | `CoreTests` y `Extension` del builder de Codex, con la caché compartida: código 0 | sí |
| P2 | `run_object_clock_probe.ps1`: importación y 11 modos `PASSED`, ≤ 8 s y sin errores | sí |
| P3 | `run_object_native_probe.ps1`: 7 procesos `PASSED` | sí |

## 3. Parte Q: regresión con mis instrumentos sin cambios

| Id | Qué | Decide |
| --- | --- | --- |
| Q1 | `run_claude_rust.ps1`: 0 FAIL, sin regresiones contra la entrega 10 y SHA A6 igual | sí |
| Q2 | `run_native_claude.ps1`: 0 FAIL | sí |
| Q3 | `run_adapter_claude.ps1` (entrega 10, sin cambios): todos los veredictos iguales a los de la entrega 10, salvo los que dependan de valores de tiempo. Las únicas FAIL permitidas son S1 y `G0_slow`, el error conocido del instrumento, que se informa aparte | sí |

## 4. Parte N: API nueva, con instrumentos propios

`prototypes/objetos_adaptador/validacion_claude/cv11_probe.gd` hereda de mi `cv10_probe.gd`. Reutiliza su escena, su proveedor variable, mi diario propio y mis referencias R_pura y R_aut. Agrega cinco modos y cuenta las llamadas a la fábrica. Lo corre `run_adapter_claude.ps1`, que copia todos mis `.gd` y `.tscn`; los modos nuevos se eligen con `-Modes` y un parámetro nuevo de escena.

| Id | Modo | Qué | Decide |
| --- | --- | --- | --- |
| K1 | `scope` | En el presente 20, contra un paquete válido (revisión 1, tick 15): conexión, contexto, uid, aparición o sesión distintos, o firma de otro valor o largo → `authority_scope`; `version` 2 → `authority_version`; revisión 0 o en punto flotante, tick −1, una clave de más o de menos → `invalid_authority_envelope`; snapshot de otro tipo, vacío o de más de 1 MiB → `invalid_checkpoint`; `acks` que no sea lista, con 17 elementos, id desconocido, otro tipo de acción, otro tick pedido, aplicado antes del pedido, aplicado después del paquete, repetido o con 5 claves → `invalid_action_confirmation`; tick 25 → `future_authority`. Todos atómicos y con 0 llamadas a la fábrica | sí |
| K2 | `scope` | Snapshot dañado → `checkpoint_rejected`; de otro tick → `checkpoint_tick_mismatch`. Atómicos, con 1 llamada a la fábrica | sí |
| K3 | `scope` | Después, el paquete válido con **revisión 1** se acepta (ningún rechazo la consumió) y queda igual a R_aut@20. `start` con conexión 0 → `invalid_context_binding` | sí |
| K4 | `late` | **Misma revisión y orden:** en el presente 40 se aceptan la revisión 3 en el tick 37 y después la **revisión 4 en el mismo tick 37**, con otro estado; queda igual a la rama de la revisión 4. La 4 otra vez → `duplicate_or_stale_revision`; la 3 → igual; la 5 en el tick 36 → `authority_tick_regression`; la 5 en el tick 41 → `future_authority`. Todos atómicos | sí |
| L1 | `late` | **Suelta tardía.** Predicha en el tick 30 (id 12); mi host H la aplica en el 34 y también tiene el impulso al vecino del tick 5. **(a)** En el presente 33, el estado H@32 con `ack` aplicado en 34 → `invalid_action_confirmation`, atómico. Después, H@32 sin `ack`, con la misma revisión, se acepta y queda igual a H@33: sigue agarrado | sí |
| L2 | `late` | **(b)** En el presente 37, H@34 con `ack {12, release, 30, 34}` se acepta y queda igual a H@37. Antes difiere > 1e-3. Controles: la rama de H@34 con otro impulso de suelta en 35, y la rama de H@33 sin soltar, se separan > 1e-3 | sí |
| L3 | `late` | Efectos: exactamente `[[11, grab], [12, release]]` en todo el modo; ninguno por las autoridades aplicadas | sí |
| W1 | `time` | En el presente 30 se anuncia un tramo hacia atrás (25–32 a 0,5). `apply` con autoridad en 24 → `false`, `timeline_invalidated:world_time` y recuperación; el mundo y la última autoridad sin cambios; generación + 1; el frame 25 borrado y el 24 conservado; 0 llamadas a la fábrica | sí |
| W2 | `time` | Un lote con el dt viejo → `invalid_recovery_frame`, atómico. Un lote con el dt nuevo → éxito, igual a mi rama R_nueva@30, que se separa > 1e-3 de la rama vieja | sí |
| W3 | `time` | La captura se reanuda y el mundo sigue igual a R_nueva hasta el 45 | sí |
| H1 | `actor` | Hay una suelta encolada en el 18 para el 19. En el 18, `invalidate_history_from(16, "actor")` → recuperación; el frame 16 borrado y el 15 conservado. En el 20 se repite la notificación: generación + 1 y señal otra vez. Un tick futuro → `true` sin cambios. Causa inválida → `invalid_history_change` | sí |
| H2 | `actor` | En el presente 24, después de 6 ticks suspendido con el actor moviéndose, se prueban lotes inválidos: generación vieja → `stale_recovery_generation`; 8 o 10 frames → `incomplete_recovery_frames`; orden cambiado, una clave de más, dt entero, dt de otro valor, ojos NaN, input que no es de bytes o un frame que no es diccionario → `invalid_recovery_frame`; input de otro tick o de otra sesión → `invalid_recovery_input`; acción desconocida → `unknown_recovery_action`; acción conocida con otro impulso, o en otro tick → `recovery_action_conflict`; paquete de otro ámbito → `authority_scope`; snapshot de otro tick → `checkpoint_tick_mismatch`. Llamada dentro de un tick (desde el proveedor del 24) → `recovery_phase`. Todos atómicos | sí |
| H3 | `actor` | Lote válido T = 15, con 16..24 y **ojos corregidos** por mi instrumento (+0,12 m en y) y la suelta en 19. Debe dar éxito y quedar igual a mi R_corr@24. No mueve el actor ni el reloj ni llama al proveedor. El diario 16..24 queda igual a mi lote, sin frames ≤ 15 | sí |
| H4 | `actor` | La captura se reanuda en el 25 y sigue igual a R_corr hasta el 44. `recover` estando activo → `recovery_not_needed`. La revisión 1 otra vez por `apply` → `duplicate_or_stale_revision` | sí |
| H5 | `actor` | En el 45, una invalidación. Un lote de 25 pasos → `replay_budget`, atómico; uno de 24 pasos (desde R_corr@21) → éxito, igual a R_corr@45 | sí |
| H6 | `actor` | La suelta cancelada al suspender y aplicada por el lote se ejecuta físicamente (el objeto no queda agarrado) **sin** emitir efecto (efectos `[[11, grab]]`). Volver a encolar el id 12 con el mismo contenido → `true` sin ejecución; con otro tick → conflicto | informativo |
| R1 | `resync` | Detenido por una invalidación en el 15, `hard_resynced` en el 17: generación + 1, señal `clock_resynced` e historia vacía. Un lote con la generación anterior → `stale_recovery_generation`. Un lote válido en el 18 (T = 12) → éxito, igual a R_aut@18 y hasta el 25 | sí |
| M | — | Qué sigue faltando para red, `NetSync` e inventario. Las etiquetas de ámbito **no autentican** | informativo |

## 5. Fuera de alcance

- ENet, `NetSync` real, inventario, presentación, dos PC y rendimiento.
- El formato hostil y N3.
