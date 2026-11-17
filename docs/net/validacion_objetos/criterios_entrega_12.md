# Criterios fijados antes de ejecutar: verificación de la entrega 12

2026-11-17. Validación independiente de Claude sobre `c1359d2`. Encargo: «Encargo de Claude: entrega 12» de `docs/net/entregas/revision_codex_entrega_11.md`. Se escribe y se guarda en el historial **antes** de compilar o correr nada.

## 0. Base y lectura del código

- **Copia:** avance directo `b4aa90c` → `c1359d2`.
  - Los 303 archivos de `../entrega_12.json` coinciden (cuatro JSON solo en LF).
  - Mis instrumentos no cambiaron. El núcleo tampoco.
- **Único cambio de producción:** `scripts/net/client_prediction.gd`, con un argumento final opcional, `replay_matching_state = false`.
  - El único otro llamador del juego, `scenes/net_lab/net_lab.gd:2344`, usa 6 argumentos, o sea, el valor por defecto.
  - **Dato aparte:** el árbol de trabajo del proyecto principal (fuera de las copias) tiene ese mismo archivo modificado, con la versión nueva y la misma hora (11:59:26), y además `prototypes/`, `native/` y scripts de `tools/testing/` sin commitear. No los toco; lo informo.
- **`history_bridge.gd`, leído antes de correr:**
  - `capture_input` guarda una **copia** de la intención sin `held_claim` y le pasa al adaptador otra copia. Un reintento con los mismos bytes es idempotente; otros bytes → `input_conflict`, que invalida y pide autoridad.
  - En `tick_finished` guarda ojos, dt, estado del actor y acción, también con el adaptador detenido.
  - `reconcile_actor` y `apply_world_slow` delegan en `ClientPrediction.reconcile` y `replay_from` reales, envolviendo el paso de la escena. Después de **cada** paso real guardan los ojos y el estado, y guardan un ancla desde el estado del host.
  - **Hueco:** con un input faltante en `ClientPrediction` o sin historia, la base queda inválida y se pide autoridad.
  - `apply_authority_trusted` arma el lote con su propio diario, incluidos los ticks suspendidos.
  - **Efectos:** `effect_ready` sale una vez por id, sea en vivo o desde la primera confirmación; `action_confirmed` sale una vez por id. `queue_action` informa `queued`, `known` o `rejected`.
- **`clock_adapter.gd`:** detenido, `invalidate_history_from` toma como presente el último tick terminado del reloj; ya no lo trata como futuro.
- **Por código:**
  - con el adaptador detenido, `bridge.queue_action` devuelve `rejected` (`not_ready`): durante la suspensión no se pueden encolar acciones;
  - una acción encolada antes de suspender sigue en el diario del puente, se aplica en la recuperación y su efecto espera la confirmación.

## 1. Qué decide

- **Igualdad en el mismo tick:** SHA-256 de `var_to_bytes(samples())`.
- **Frames:** comparados campo por campo con los míos.
- **Estados del actor:** bytes iguales.
- **Controles:** separación > 1e-3.
- **Atomicidad:** como en la entrega 11 (mundo, autoridad, generación, `ready`, efectos).
- **Límites externos:** 8 s por proceso y 180 s por compilación.
- **Ritmo:** mis modos con `--fixed-fps 60`.
- **Sin cambios:** no se repite N3, y no se modifica S1 (entrega 10).

## 2. Parte P: compilación y reproducción

| Id | Qué | Decide |
| --- | --- | --- |
| P1 | `CoreTests` y `Extension` con la caché compartida: código 0 | sí |
| P2 | `run_object_clock_probe.ps1`: importación y 16 modos `PASSED`, sin errores y ≤ 8 s | sí |
| P3 | `run_object_native_probe.ps1`: 7 `PASSED` | sí |

## 3. Parte Q: regresión con mis instrumentos sin cambios

| Id | Qué | Decide |
| --- | --- | --- |
| Q1 | Rust: sin cambios de veredicto contra la entrega 11 | sí |
| Q2 | Godot nativo: sin cambios de veredicto | sí |
| Q3 | Adaptador de la entrega 10: sin cambios de veredicto; S1 y `G0_slow` siguen como error conocido | sí |
| Q4 | Adaptador de la entrega 11 (5 modos): sin cambios de veredicto | sí |

## 4. Parte B: puente con `ClientPrediction` real (instrumentos propios)

`prototypes/objetos_adaptador/validacion_claude/cv12_probe.gd` es una escena nueva, independiente de la de Codex, con su runner `run_adapter_claude_e12.ps1`. Tiene:
- un proveedor que varía movimiento, yaw, agacharse, salto, correr y el `hold`, con un `held_claim` de 41 bytes en cada input original;
- mi propio paso de escena: `ActorMotor.step` real, que anota los ticks llamados y los ojos y estados **después de cada paso**;
- mi diario propio de la verdad y mi referencia nativa, que rehago desde un checkpoint cuando la verdad cambia por una corrección real;
- `cv12_client_prediction_e11.gd`: copia de `client_prediction.gd` de `b4aa90c` (SHA LF `3614d2b7…`) **sin** la línea `class_name`, para comparar el comportamiento anterior. No es producción.

| Id | Modo | Qué | Decide |
| --- | --- | --- | --- |
| B0 | todos | Dentro del motor, las clases `ClientPrediction`, `ActorMotor`, `SimClock` y demás, y los scripts `history_bridge.gd`, `clock_adapter.gd` y mi copia vieja, tienen el SHA del repositorio. El `ClientPrediction` usado es `res://scripts/net/client_prediction.gd` | sí |
| B1 | todos | **Grabación:** cada frame en vivo del puente es igual a mi verdad (tick, dt, ojos después del motor, intención sin claim y acción), y su estado es igual al del actor. El input original no cambia: sus bytes con claim y el claim de 41 bytes siguen iguales. El reintento idéntico de captura (tick 8) → `true` | sí |
| B2 | `actor` | En el comienzo del tick 26, `reconcile_actor(15, host)`, con velocidad +1,5 m/s y x +0,05. Mi paso se llama exactamente para 16..25. Los frames 16..25 del puente son iguales a lo que observé dentro de cada paso real; el 15 es igual al estado del host. Las diferencias de ojos contra los anteriores **no son una traslación fija** (dispersión > 1e-3). No se llama al proveedor. El objeto queda detenido | sí |
| B3 | `actor` | Durante 26–28, suspendido, el puente sigue grabando y el mundo nativo no avanza. En el 29, `bridge.apply_authority_trusted` (T = 14) recupera, igual a mi referencia rehecha. No mueve el actor ni el reloj, no llama al proveedor ni a mi paso, y el diario del adaptador es igual a mi verdad | sí |
| B4 | `actor` | Suelta en vivo en 35 (id 22): efecto provisional una vez. Confirmación en 38 → `action_confirmed` una vez, sin otro efecto. Otra revisión con la misma confirmación → nada nuevo. `queue_action` del 22 → `known`, con efecto y confirmación en verdadero. Final igual a la referencia | sí |
| B5 | `time` | En el comienzo del 30, `apply_world_slow(18, 34, 0,5)` → `true`. Mi paso se llama para 18..29 con el dt nuevo. Los frames del puente tienen ese dt y los ojos de los pasos reales, que difieren de los viejos sin ser una traslación fija. El objeto se detiene en el anuncio. Recuperación en 31 (T = 17), igual; sigue igual hasta el 45 | sí |
| B6 | `gap` | Con `ClientPrediction` vacío en el 30, `apply_world_slow` → `false`, base inválida y pedido `actor_history_unavailable`. Recuperar → `actor_baseline_required`, atómico | sí |
| B7 | `gap` | Un lote "en vuelo" preparado en 31 con la generación de entonces. En el 34, `reconcile_actor(30)` con el estado **coincidente** fuerza 3 pasos reales (31..33) y deja la base válida. La generación avanza aunque 30 sea posterior al mundo congelado. El lote en vuelo → `stale_recovery_generation`. Recuperación en 34 (T = 30), igual | sí |
| B8 | `gap` | Sin captura en el 40 → `input_not_captured` y objeto detenido. En el 43, el estado coincidente del 39 rehace 40..42; el frame 40 queda igual a mi verdad. Recuperación en 43 (T = 38), igual | sí |
| B9 | `gap` | Sin `record` de `ClientPrediction` en el 46. En el 49, una corrección del 45 → hueco de repetición, base inválida, pedido `actor_replay_gap`; recuperar → `actor_baseline_required`. Recuperar desde el proveedor (dentro de un tick) → `authority_phase` | sí |
| B10 | `effect` | En el comienzo del 30 se encola la suelta 32 para el 31 (`queued`) y se corrige el actor desde el 20. En el 31, volver a encolarla → `rejected` (`not_ready`, informativo). El puente graba el frame 31 con la acción. Recuperación en 35 (T = 19): igual a la referencia, el objeto suelto y **ningún** efecto del 32. `queue_action` del 32 → `known` sin efecto ni confirmación | sí |
| B11 | `effect` | Confirmación del 32 en 37 → primer efecto y primera confirmación. La revisión 3 con la misma confirmación → nada nuevo. Confirmación del 31 (agarre ejecutado en vivo) → confirmación sí, efecto no. `known` del 32 → efecto y confirmación en verdadero. Final igual | sí |
| G1 | `guards` | `ClientPrediction` nueva **sin** el argumento contra la copia vieja, con los mismos datos y el mismo actor (restaurado entre corridas). En cinco casos (coincide, afirmación vieja después de una corrección, input tardío, corrección y alineación) deben coincidir contadores, ticks llamados, estado final del actor y estados guardados | sí |
| G2 | `guards` | Nueva **con** `replay_matching_state = true`: si coincide, repite 13..19 y termina en el mismo estado; las guardas de afirmación vieja e input tardío se mantienen (sin llamadas, con su contador) | sí |
| M | — | Qué falta: recepción real de `NetSync`, transporte, el laboratorio sin instalar, el inventario y los permisos | informativo |

## 5. Fuera de alcance

- Red, recepción real de `NetSync` y laboratorio migrado.
- Dos PC y rendimiento.
- N3 y el formato hostil.
