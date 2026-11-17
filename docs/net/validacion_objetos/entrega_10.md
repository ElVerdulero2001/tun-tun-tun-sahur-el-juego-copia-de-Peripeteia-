# Verificación independiente de la entrega 10: −0 del piso y adaptador local actor/reloj

2026-11-17. Claude. Base: `5fb0d1f`.

**Orden de los commits:**
- Criterios en `criterios_entrega_10.md` (`2a101ea`, 09:46). Se escribieron después de leer el adaptador y antes de compilar o correr nada.
- Instrumentos del adaptador en `09e8a8e` (09:54), antes de la corrida oficial.
- Una corrida no planeada ocurrió antes de ese commit; está en "Errores propios" y no cuenta.

## Dictamen

**El cambio de signo del cero queda verificado:**
- en N2 (64.440 mutaciones), 0 pisos aceptados distintos por bits en los dos ejecutables;
- se rechazan 10 mutaciones más por `snapshot_fixed_pose`: las 5 −0 de la pose real y otras 5 equivalentes en el manifiesto;
- N1 sigue con 0 falsos rechazos en sus 1.692 restauraciones;
- la historia está intacta (SHA A6 `b4a53687…` igual);
- mis regresiones dan 135/0 en Rust y 79/0 en Godot.

**El adaptador local hace lo que describe, en el alcance probado.** Lo probé con el actor, el motor, el codec de input y el reloj reales, con entradas que varían en cada tick, y contra referencias mías:
- **Diario:** guarda exactamente los bytes del input, los ojos del actor **ya movido** (en todos los ticks distintos de los de antes del motor), el dt del mundo y la acción. Coincide con mi copia en los 517 frames comparados de 8 modos.
- **Restaurar antes del agarre y antes del lanzamiento** vuelve a ejecutar físicamente esas acciones y deja el mundo igual por bits a mi "autoridad" en el mismo tick. Sin la suelta, o con un impulso doble, el resultado se separa entre 0,98 y 7,8 m.
- **Señales de efecto:** salen una sola vez por acción (`[[11, grab], [12, release]]`) y ninguna durante las 9 correcciones aceptadas.
- **La repetición no consulta el presente.** Durante una corrección cambié el proveedor del reloj, moví el actor 50 m, corrompí los `ActorInput` originales y agregué un tramo de cámara lenta hacia atrás. Hubo 0 llamadas al proveedor y el mismo resultado.
- **Funcionan** la cámara lenta, la pausa (incluido un `step()` suelto y una corrección en pausa), los duplicados, 17 rechazos atómicos, los límites (256 acciones, 120 frames, 24 pasos), la resincronización, el cambio de Tuning y 5 capturas inválidas en adaptadores paralelos.

**Una falla, del instrumento:** S1 esperaba 24 ticks lentos en el tick 32, cuando a esa altura habían pasado 23. La traza completa confirma 24 (del 10 al 33) con el dt correcto. S1 queda anulado.

**No se certifica:**
- ENet del adaptador, el input real de jugadores, `InvHands`, `NetSync` ni la presentación;
- dos PC ni rendimiento;
- el formato hostil (N3 no se repitió).

`model_approved` sigue en `false`.

## Base, compilación y corridas

- **Copia:**
  - Avance directo `74deb0e` → `5fb0d1f`. Los 77 archivos de `..\entrega_10.json` coinciden (dos JSON solo en LF).
  - No cambiaron mis instrumentos, ni `scripts/`, `scenes/` o `project.godot`.
- **Producción:**
  - Los 9 archivos que usa el adaptador son iguales por SHA-256 al **árbol de trabajo actual** del proyecto principal.
  - `actor_input`, `actor_tuning` e `inv_authority` difieren de su último commit (`677086f`), e `inv_hold_motion` no está en ese commit. Lo que se prueba es el trabajo sin commitear.
- **Compilación:** builder de Codex con la caché compartida.
  - `CoreTests`: 16 s, 15 ejecutables y 29 funciones que pasan; N3 sigue `ignored`.
  - `Extension`: 8,7 s.
  - **DLL propia:** `64679e73…339e`, 5.720.064 bytes. No es igual por bytes a la de Codex (`d7761f5f…`).
- **Reproducción de Codex:**
  - `run_object_native_probe.ps1`: 7 procesos `PASSED`.
  - `run_object_clock_probe.ps1`: importación y 7 modos `PASSED`, sin errores; el más largo, la importación, tardó 3,57 s.
  - Sus 219 copias de producción son iguales al repositorio.
- **Corridas, en `tmp/validacion_objetos/entrega_10/`:**
  - `rust_20261117_094743`;
  - `godot_20261117_094745`;
  - adaptador: `adapter_20261117_095415`;
  - revisión de sintaxis: `check_20261117_095400`;
  - la corrida no planeada: `adapter_20261117_095331.intento1_corrida_antes_del_commit`.
- **Reproducción de Codex, en las carpetas de su runner:** `tmp/native_probe/20261117_124654_a8e19e` y `tmp/clock_probe/20261117_124659_e88be4`.
- **Límites y cierre:**
  - Todos los procesos con límite externo de 8 s. No venció ninguno y no quedó ningún Godot abierto.
  - Mis modos usan `--fixed-fps 60`: la lógica por tick es la misma, pero no corren a ritmo real.

## Resultado por prueba

| Parte | Resultado |
| --- | --- |
| P1, P3 compilación y funciones | Pasan: 29 funciones, 1 ignorada |
| P4, P5 reproducción de Codex | Pasan |
| Q1 Rust original | 135 pasan, 0 fallan, 23 informativas, 1 no evaluable. Sin regresiones contra la entrega 9 |
| Q2 N1/N2 | Pasan; piso por bits 0 y 0 |
| Q3 Godot original | 79 pasan, 0 fallan. ENet: T = 71 en las dos variantes; mismo SHA en cada tick |
| A0 copias y scripts cargados | 221 copias iguales. Dentro del motor, las 8 clases, `actor.tscn` y `clock_adapter.gd` tienen el SHA del repositorio en los 8 modos |
| A1–A8 (`replay`) | Pasan |
| S1 (`slow`) | **Anulado**: error del instrumento. La traza confirma lo pedido |
| S2, S final | Pasan; S3 informativo |
| Z0–Z3 (`pause`) | Pasan |
| E1–E4 (`errors`) | Pasan |
| L1–L3 (`limits`) | Pasan; L4 informativo |
| R1 (`resync`) | Pasa |
| T1, T2 (`tuning`) | Pasan |
| C1, C2 (`capture`) | Pasan |

En el resumen del adaptador: 80 pasan, 2 fallan (S1 y el código de salida de `slow`, por S1) y 13 informativas.

## Por punto del encargo

### 1. Actualización y DLL propia

Hecho, con mi propia DLL compilada en la copia de validación.

### 2. Signo del cero (N1 y N2 originales)

- **N2, bits 0–3:** 0 aceptadas con piso distinto y 101 rechazos por `snapshot_fixed_pose`, igual que antes.
- **N2, bits 4–7:** 0 aceptadas con piso distinto, antes eran 5. Los rechazos por `snapshot_fixed_pose` pasan de 90 a 100: las 5 del −0 en la pose real y otras 5 del −0 en el manifiesto, que antes se aceptaban sin efecto visible.
- **En ambos:** 0 pánicos y 0 rechazos con cambios.
- **N1:** las 7 escenas pasan sin rechazos, con continuaciones iguales por bits.

No repetí N3 y no declaro resuelto el formato hostil.

### 3. Copias exactas y actor que se mueve antes del objetivo

- **Copias:** las 221 copias del proyecto temporal son iguales a sus originales.
- **Dentro del motor:** la lista de clases globales apunta a los archivos copiados, y su SHA-256 coincide con el repositorio para `ActorInput`, `ActorBody`, `ActorMotor`, `ActorTuning`, `SimClock`, `InvAuthority`, `InvHoldMotion` y `BaseRegistry`, más `actor.tscn` y `clock_adapter.gd`.
- **Ojos después del motor:**
  - en mi `tick_started`, antes del motor, tomo los ojos, y en `tick_finished`, después;
  - los ojos del diario son siempre los de después;
  - los de antes difieren en el 100 % de los ticks (60/60 en `replay`, 266/266 en `limits`);
  - el actor se desplazó entre 1,0 y 1,6 m en los modos largos;
  - la altura de los ojos pasó de 1,65 a 0,85 m al agacharse, así que el objetivo sigue la postura real.

### 4. Instrumentos propios: captura, repetición y casos

**Entradas variadas al capturar:** el movimiento, el yaw, agacharse, correr, el contador de salto y el `hold` (pitch, distancia y giro) cambian en cada tick, y el `hold` queda vacío en 22–26.

**Diario igual al mío (A2):** los bytes, el dt, la acción y los ojos coinciden en 60, 50, 40, 40, 262, 20, 15 y 30 frames, según el modo.

**Paso en vivo (A3):** el mundo del adaptador es igual por bits a mi R_pura en cada tick antes de la primera corrección (28 ticks en `replay`).

**La repetición no consulta el presente (A6):** se comprobó con 0 llamadas al proveedor, 0 al proveedor envenenado y la igualdad final, como se describe en el dictamen.

**Cámara lenta (`slow`, tramo 10–33 a 0,42):**
- el dt guardado es igual a `world_dt` en los 50 frames, con 24 lentos;
- en el presente 32, una corrección de 24 pasos que cruza el comienzo del tramo queda igual a R_aut;
- **S3, informativo:** en el presente 40 anuncié un tramo hacia atrás (36–38 a 0,2) y corregí desde el 35. El adaptador repite con el dt guardado: queda igual a R_aut y a 0,398 m de una rama que usa el dt nuevo. Es la falta que el README declara.

**Pausa:**
- en pausa no avanzan el tick, el mundo ni el proveedor (comprobado en los cuadros 3 y 7);
- una corrección en pausa queda igual a R_aut@15 sin mover el reloj;
- `clock.step()` produce exactamente un tick, un frame y un paso;
- al reanudar, el final es igual.

**Errores (`errors`):**
- 8 `queue_action` inválidas → `false`, sin recuperación y con el mundo igual;
- una segunda acción en el mismo tick → `action_capacity`; un duplicado → `true` y una sola ejecución; el mismo id con otro ancla → `action_identity_conflict`;
- 8 `reconcile` inválidas (duplicada, vieja, futura, vacía, de más de 1 MiB, dañada, de otro manifiesto, con otro tick) → su código, con el mundo igual por bytes, `ready` en verdadero y sin efectos;
- una repetición imposible (la autoridad nunca agarró y hay una suelta en la ventana) → `replay_failed:invalid_hand_transition`, atómica. Después, la corrección del tick 19 se acepta: los fallos no adelantaron la última autoridad aceptada.

**Límites (`limits`, 266 ticks):**
- 256 acciones ejecutadas, con 256 efectos; la 257 → `action_capacity` sin recuperación; un id usado con otro contenido → conflicto;
- historia: 120 frames, el primero es el 139 y ocupan 34.672 bytes;
- una corrección de 24 pasos se acepta e iguala; una de 25 → `replay_budget`, con recuperación y el mundo igual; después, 4 capturas rechazadas y el mundo detenido en 262;
- **L4, informativo:** el input máximo pesa 32 bytes (límite 256) y el frame máximo 292 bytes. Llenar 256 KiB pediría unos 897 frames, más que los 120 de la historia. `history_expired` no se alcanza mientras la historia (120) supere al presupuesto (24). Esos tres límites no se pueden ejercitar con datos válidos.

**Resincronización:** `clock_resynced`, historia vacía y mundo igual. Después se rechazan captura, acciones y correcciones con `not_ready`, y el mundo queda en 20 durante 10 ticks.

**Tuning:**
- `hold_follow_time` 0,09 y `hold_turn_accel` 7000 se rechazan al arrancar (`unsupported_hand_tuning`), sin conectarse al reloj;
- un cambio de `hold_min_distance` en 15 → `tuning_changed` en el tick 16, con el mundo detenido en 15 y sin efectos después.

**Capturas inválidas (`capture`):** cinco adaptadores en el mismo reloj, cada uno con un error: tick equivocado (8), duplicado (9), input imposible (10), yaw NaN (11) y sesión de agarre distinta (1). Cada uno pide recuperación en su tick y su mundo queda en el anterior. El principal sigue igual a R_pura.

### 5. Restauración anterior al lanzamiento, controles y efectos

| Corrección | Presente | Desde | Pasos | Incluye | Antes | Después | Controles |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A4 | 29 | R_aut@5 | 24 | agarre en 6 | 0,071 | igual | — |
| A5 | 33 | R_aut@19 | 14 | suelta en 20 | 2,79 (perturbado en 31) | igual | sin suelta: 7,82; doble impulso: 0,98 |
| A7 | 45 | R_aut@21 | 24 | después de la suelta | 1,24 (perturbado en 40) | igual | — |

- "Antes" es la máxima diferencia absoluta contra R_aut en el mismo tick.
- R_aut tiene un impulso al vecino 3 antes del paso 5 que el adaptador nunca vio. Así la corrección tiene que traer un estado realmente distinto.
- Los efectos salieron una vez, en los ticks 6 y 20, y ninguno durante las correcciones.

**Datos y API que faltan para integrar red o inventario.** No los inventé:
1. **Acción que llega tarde:** `queue_action` solo acepta el tick siguiente o el posterior. No hay forma de insertar una acción confirmada en un tick pasado y repetir desde antes. La política temporal sigue pendiente.
2. **Historia que cambia hacia atrás:** no hay API para corregir o invalidar ojos y dt guardados cuando cambia la historia del actor (correcciones de `NetSync`) o la de los tramos de cámara lenta (S3: 0,398 m en 5 ticks).
3. **Identidad del checkpoint:** solo se usa el tick dentro de la sesión. Falta una revisión de sesión o contexto en los datos de autoridad.
4. **Recuperación:** después de pedirla, el adaptador queda inutilizado. No hay camino para reconstruirlo desde un estado autorizado.
5. **Inventario:** una mano y un objeto por adaptador. Las acciones son intenciones locales, sin permisos, sin `InvHands` y sin conexión con el protocolo de inventario.
6. **Presentación:** las correcciones se ven como saltos de decenas de centímetros a metros en estos ensayos perturbados. No hay suavizado ni traspaso.
7. **Memoria:** durante una corrección viven dos mundos con sus cachés; no está medido.

### 6. Sin modificaciones

No toqué el adaptador, el núcleo, el driver, los runners de Codex, la producción ni las tolerancias. Mis archivos están en `prototypes/objetos_adaptador/validacion_claude/`.

### 7. Lo que no se certifica

ENet del adaptador, los controles completos del juego, la presentación, dos PC y el rendimiento.

## Errores propios

1. **Corrida antes del commit.** Quise agregar al lanzador el parámetro `-CheckOnly` con un script, y el reemplazo no se aplicó porque se perdieron las barras invertidas. Al llamarlo con `-CheckOnly`, PowerShell ignoró el parámetro y **corrió los 8 modos** antes de que guardara los instrumentos en el historial.
   - Esa carpeta queda como `adapter_20261117_095331.intento1_corrida_antes_del_commit` y no cuenta.
   - Arreglé el parámetro, revisé la sintaxis con `-CheckOnly`, guardé todo en el historial (`09e8a8e`) y repetí la corrida oficial sin cambiar nada más.
2. **S1 mal contado.** Pedí 24 ticks lentos en el tick 32, pero a esa altura solo habían pasado 23 del tramo 10–33. Queda anulado; la traza completa muestra 24.
3. **Un intento de leer los resultados de Codex falló** por una barra invertida en el comando. No afecta ninguna medición.

## Para Codex

1. **Cámara lenta hacia atrás (S3).** El adaptador repite con el dt guardado. Si la autoridad anuncia un tramo que empieza en el pasado, la predicción no lo incorpora y se separa (0,398 m en 5 ticks en este ensayo). Hace falta decidir si se invalida la historia o se corrige el dt.
2. **Límites que no se alcanzan con datos válidos.** `HISTORY_BYTES` (256 KiB) e `input` de 256 bytes no se alcanzan: los frames pesan hasta 292 bytes y los inputs 32. `history_expired` tampoco se alcanza mientras `HISTORY_TICKS` > `MAX_REPLAY_STEPS`. No son defectos, pero esas ramas no tienen prueba que las ejercite.
3. **Una captura duplicada termina la predicción** (recuperación). Es coherente con el diseño, pero un proveedor que reintente la misma captura deja inutilizado al adaptador.
4. **Sin cambios:** `CoreTests` incluye mis `claude_e9_*` y pasa entero; N3 sigue ignorada.

## Límites

- Una PC, perfil dev.
- Mis modos con `--fixed-fps 60`.
- Entradas inyectadas por mi proveedor y "autoridad" local.
- Sin red, sin input real de jugadores y sin dos PC.
