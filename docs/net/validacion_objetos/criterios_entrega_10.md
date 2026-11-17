# Criterios fijados antes de ejecutar: verificación de la entrega 10

2026-11-17. Validación independiente de Claude sobre `5fb0d1f`. Encargo: «Encargo de Claude: entrega 10» de `docs/net/entregas/revision_codex_entrega_9.md`. Se escribe y se guarda en el historial **antes** de compilar o correr nada.

## 0. Base y lectura del código

- **Copia:** avance directo `74deb0e` → `5fb0d1f`.
  - Los 77 archivos de `../entrega_10.json` coinciden; dos JSON de resultados coinciden solo en su versión LF.
  - No cambiaron mis instrumentos (`git diff 74deb0e HEAD` vacío en mis carpetas), ni `scripts/`, `scenes/` o `project.godot`.
- **Producción respecto del proyecto principal:**
  - `actor_input`, `actor_body`, `actor_motor`, `actor_tuning`, `base_registry`, `sim_clock`, `inv_authority`, `inv_hold_motion` y `actor.tscn` de la copia son iguales por SHA-256 al **árbol de trabajo actual** del proyecto principal;
  - `actor_input`, `actor_tuning` e `inv_authority` difieren de su último commit (`677086f`), e `inv_hold_motion` no está en ese commit. La "producción" es el trabajo sin commitear del usuario.
- **Núcleo:** `world.rs` compara ahora la pose fija con `to_bits`, y la prueba propia de Codex agrega el caso −0.
- **Adaptador (`clock_adapter.gd`), leído antes de correr:**
  - `capture` serializa el `ActorInput` con `write_to` y guarda los bytes.
  - En `tick_finished` lee `InvAuthority.eyes` del actor ya movido, toma `SimClock.world_dt(tick)` y arma el objetivo con `InvHoldMotion.target_of`. Después aplica la transición, da un paso y guarda un checkpoint en la caché del núcleo.
  - `reconcile_trusted` revisa duplicado, rango, Tuning, presupuesto (24) e historia, restaura un mundo candidato y repite los frames guardados. Solo reemplaza el mundo si termina.
  - `action_effect` se emite solo en `_after_tick`, nunca durante la repetición.
  - En la repetición usa el `tuning` vivo, protegido por una firma.
  - **Por código:**
    - `history_expired` no se puede alcanzar mientras la historia (120) supere al presupuesto (24) y nada la recorte antes;
    - el límite de 256 KiB del diario y el de 256 bytes por input no se alcanzan con inputs válidos;
    - un tramo de cámara lenta agregado **hacia atrás** no corrige el dt guardado (lo declara el README).

## 1. Qué decide

- **Igualdad en el mismo tick:** el SHA-256 de `var_to_bytes(samples())` debe ser igual, o sea, exacta por bits. Las diferencias numéricas se informan.
- **Controles negativos y sensibilidad:** deben separarse > 1e-3 (máxima diferencia absoluta en posición, base o velocidades).
- **Límites externos:** 8 s por proceso y 180 s por compilación.
- **Ritmo:**
  - mis modos corren con `--fixed-fps 60`. La lógica por tick es la misma, pero el ritmo no es tiempo real;
  - la reproducción de Codex corre como la entregó, en tiempo real.
- **Veredictos:** decide **sí**; **informativo** no decide; **no evaluable** si no se logra la condición previa.
- **No se repite** N3 exploratorio ni nada de `StateManager3D`.

## 2. Parte P: compilación y reproducción

| Id | Qué | Decide |
| --- | --- | --- |
| P1 | `CoreTests` y `Extension` del builder de Codex, con la caché compartida: código 0 y sin vencer | sí |
| P2 | ¿Mi DLL es igual por bytes a la de Codex (`d7761f5f…`)? | informativo |
| P3 | Todas las funciones que ejecuta `CoreTests` pasan (N3 sigue `ignored`) | sí |
| P4 | `run_object_native_probe.ps1 -Stages all`: 7 procesos `PASSED` | sí |
| P5 | `run_object_clock_probe.ps1`: importación y 7 modos con código 0, `PASSED`, sin errores y ≤ 8 s | sí |

## 3. Parte Q: regresión con mis instrumentos sin cambios

| Id | Qué | Decide |
| --- | --- | --- |
| Q1 | `run_claude_rust.ps1` y `cv_rust_report.mjs`: 0 FAIL, sin regresiones contra la entrega 9, SHA A6 `b4a53687…` | sí |
| Q2 | N1 y N2 (`claude_e9_*`, dentro de `CoreTests`): 0 falsos rechazos y continuaciones iguales. En N2, `piso_intacto_en_aceptadas` = 0 por bits en los dos ejecutables, sin pánicos y con rechazos atómicos | sí |
| Q3 | `run_native_claude.ps1` y `cv_native_compare.mjs`: 0 FAIL | sí |

## 4. Parte A: adaptador local, con instrumentos propios

`prototypes/objetos_adaptador/validacion_claude/`: `cv10_probe.gd` con 8 modos, `run_adapter_claude.ps1` y `cv10_report.mjs`.

El proyecto temporal se arma como el de Codex:
- copia de `scripts/`, `scenes/actor/actor.tscn`, el `project.godot` del prototipo nativo, la extensión y **mi** DLL;
- el adaptador de Codex sin cambios y mis archivos;
- importación previa para el registro de clases.

**Escena propia:**
- otro mundo nativo que el de Codex: un objeto de 0,45 × 0,35 × 0,55 m y 1,6 kg, más dos vecinos dinámicos;
- un **proveedor que varía cada tick** el movimiento, el yaw, agacharse (ticks 12–17), correr (40–46), el salto (desde 25) y el `hold` (pitch, distancia y giro). En `replay`, el `hold` queda vacío en 22–26;
- agarre en 6 (id 11) y suelta en 20 (id 12, impulso (1,2, 1,6, −0,8)).

**Mis referencias**, construidas sin leer el diario del adaptador:
- copio los bytes del input en el proveedor, y los ojos y el dt en mi propio manejador de `tick_finished`;
- aplico la transición y el paso según el README;
- **R_pura:** los mismos frames;
- **R_aut:** la "autoridad", con un impulso extra al vecino 3 antes del paso 5, que el adaptador no conoce. Sus snapshots son los checkpoints.

| Id | Qué | Decide |
| --- | --- | --- |
| A0 | Copias exactas. **(a)** Cada archivo copiado al proyecto temporal es igual por SHA-256 al del repositorio. **(b)** Dentro del motor, los scripts de `ActorInput`, `ActorBody`, `ActorMotor`, `ActorTuning`, `SimClock`, `InvAuthority`, `InvHoldMotion` y `BaseRegistry`, según la lista de clases globales, más `actor.tscn` y `clock_adapter.gd`, tienen el SHA-256 del repositorio | sí |
| A1 | El actor se mueve antes de tomar el objetivo: los ojos de cada frame son iguales a los que calculo en `tick_finished` y distintos de los de `tick_started` (antes del motor) en ≥ 80 % de los ticks. Desplazamiento total > 0,5 m. Informativo: la altura de los ojos cambia al agacharse | sí |
| A2 | El diario coincide en cada tick con lo mío: bytes del input, ojos, dt = `world_dt(t)` y acción | sí |
| A3 | Paso en vivo: el mundo del adaptador es igual a R_pura en cada tick antes de la primera corrección | sí |
| A4 | Restauración **anterior al agarre**: en el presente 29, `reconcile_trusted(5, R_aut@5)` repite **24** pasos, incluido el agarre en 6. Antes difiere de R_aut@29 > 1e-3; después es igual | sí |
| A5 | Restauración **anterior al lanzamiento**. Se perturba el mundo del adaptador en 31; en el presente 33, `reconcile(19, R_aut@19)` repite 14 pasos con la suelta en 20. Debe quedar igual a R_aut@33. **Controles:** sin la suelta, y con la suelta más un impulso igual en 21; los dos se separan > 1e-3 | sí |
| A6 | Durante A5, la repetición no consulta el presente. Se cambian el proveedor del reloj y el contador, se teletransporta el actor 50 m, se corrompen los `ActorInput` originales de 20–33 y se agrega un tramo de cámara lenta en 18–34 hacia atrás. Se restaura todo antes del tick siguiente. Exigencias: 0 llamadas al proveedor y la igualdad de A5 | sí |
| A7 | Después de la suelta, con una perturbación en 40: en el presente 45, `reconcile(21, R_aut@21)` repite exactamente 24 pasos y queda igual | sí |
| A8 | **Efectos:** `action_effect` da exactamente `[[11, grab], [12, release]]`, sin ninguno durante las correcciones; el agarre duplicado en el mismo tick no se ejecuta dos veces. **Final:** en 60, igual a R_aut | sí |
| S1 | **Modo `slow`** (tramo 10–34 a 0,42): el dt guardado es `world_dt`, con 24 ticks lentos. El mundo es igual a R_pura en cada tick antes de corregir | sí |
| S2 | En el presente 32, `reconcile(8, R_aut@8)` atraviesa el comienzo del tramo y queda igual a R_aut | sí |
| S3 | Tramo agregado hacia atrás (36–39 a 0,2) en el presente 40, con `reconcile(35)`: el resultado es igual a R_aut, porque usa el dt guardado, y se separa > 1e-3 de una rama que usa el dt nuevo. Muestra la falta declarada | informativo |
| Z1 | **Modo `pause`:** con el reloj en pausa no avanzan los ticks, el mundo ni el proveedor | sí |
| Z2 | `clock.step()` en pausa: exactamente un tick, un frame y un paso nativo | sí |
| Z3 | Una corrección durante la pausa queda igual a R_aut sin avanzar el reloj. Final igual a R_aut | sí |
| E1 | **Modo `errors`:** `queue_action` con tick pasado, tick + 3, tipo inválido, id 0 o mayor que 2³¹ − 1, ancla NaN o de 1001, o impulso de 2e5 → `false`, sin recuperación y con el mundo igual | sí |
| E2 | Dos acciones para el mismo tick → `action_capacity`. Un duplicado igual → `true` y una sola ejecución. Otro contenido con el mismo id → `action_identity_conflict` | sí |
| E3 | `reconcile` duplicado o viejo, posterior al presente, vacío, de más de 1 MiB, dañado, de otro manifiesto o con otro tick → `false` con su código; el mundo igual por bytes, `ready` en verdadero y sin efectos | sí |
| E4 | Repetición fallida (autoridad sin agarre y suelta en la ventana) → `replay_failed`, atómica. Después, una corrección válida funciona: la última autoridad aceptada no avanzó con los fallos | sí |
| L1 | **Modo `limits`:** se aceptan 256 acciones y la 257 → `action_capacity` sin recuperación. Un id ya usado con otro contenido → conflicto | sí |
| L2 | La historia, después de 258 ticks, tiene 120 frames, el más viejo es el 139 y ocupa ≤ 256 KiB | sí |
| L3 | Una corrección de 24 pasos se acepta e iguala. Una de 25 → `replay_budget` con recuperación, el mundo igual, y después sin pasos nativos, sin efectos y con las capturas rechazadas | sí |
| L4 | Tamaños máximos medidos de input y de frame, y si `history_expired` y los límites de bytes se pueden alcanzar | informativo |
| R1 | **Modo `resync`:** `hard_resynced` → recuperación `clock_resynced`, historia vacía y mundo igual. Después no hay pasos y se rechazan captura, acciones y correcciones | sí |
| T1 | **Modo `tuning`:** un Tuning de mano no soportado (`hold_follow_time` 0,09, o `hold_turn_accel` 7000) se rechaza al arrancar y ese adaptador no queda conectado | sí |
| T2 | Un cambio de `hold_min_distance` en 15 → en el tick 16, `tuning_changed` con recuperación; el mundo queda en 15 y no hay efectos después | sí |
| C1 | **Modo `capture`**, con cinco adaptadores extra en el mismo reloj: tick equivocado, captura duplicada, input imposible, yaw NaN y sesión de agarre distinta. Cada uno pide recuperación en su tick y su mundo queda en el tick anterior | sí |
| C2 | El adaptador principal del mismo reloj no se afecta y queda igual a R_pura al final | sí |
| M | Datos o API que faltan para una integración con red o inventario, sin inventarla | informativo |

## 5. Fuera de alcance

- ENet del adaptador, controles completos del juego, `InvHands`, `NetSync` y presentación.
- Dos PC y rendimiento.
- Formato hostil (N3) y `StateManager3D`.
