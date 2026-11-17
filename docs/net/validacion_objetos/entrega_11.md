# Verificación independiente de la entrega 11: autoridad con ámbito e historia corregida

2026-11-17. Claude. Base: `0aed621`.

**Orden de los commits:**
- Criterios en `criterios_entrega_11.md` (`5a49a81`, 11:27). Se escribieron después de leer la API nueva y antes de compilar o correr nada.
- Instrumentos en `890c553` (11:33), antes de correrlos.
- `6f915bc`, que cambia el nombre de un modo; ver "Errores propios".

## Dictamen

**La API nueva hace lo que el README describe, en el alcance local probado:**
- **Ámbito y revisión:**
  - 26 paquetes con etiquetas, tipos, versión, revisión, snapshot o confirmaciones incompatibles se rechazan **sin crear el candidato** (0 llamadas a la fábrica) y sin tocar nada;
  - dos snapshots inválidos se rechazan después de crearlo, también sin efecto;
  - ninguno consume la revisión: la revisión 1 se acepta después;
  - una revisión nueva corrige el **mismo tick** con otro estado;
  - duplicados, revisiones viejas, ticks hacia atrás y ticks futuros se rechazan.
- **Suelta tardía:**
  - una confirmación cuyo snapshot todavía no contiene la acción se rechaza;
  - el estado del host posterior a aplicarla deja el mundo igual por bits a mi host en el mismo tick;
  - no hay segundo impulso: los controles "doble impulso" y "nunca suelta" se separan 1,0 y 1,2 m;
  - los efectos salen una sola vez.
- **Historia corregida:**
  - un tramo de cámara lenta anunciado hacia atrás se **detecta** y se pide recuperación; un lote con el dt viejo se rechaza y uno con el dt nuevo deja el mundo igual a mi rama corregida;
  - una invalidación del actor, con mis ojos corregidos (+12 cm), se recupera después de **6 ticks suspendido** sin mover el actor ni el reloj ni llamar al proveedor; el diario queda exactamente con el lote entregado;
  - 17 lotes inválidos, una llamada dentro de un tick, una generación vieja y un lote de 25 pasos se rechazan de forma atómica;
  - las notificaciones repetidas cambian la generación y vuelven a avisar, y una resincronización estando detenido también;
  - la captura se reanuda y sigue igual a la referencia.
- **Sin regresiones:**
  - mi Rust da 135/0, mi Godot nativo 79/0 y mi adaptador de la entrega 10, 80/2;
  - los dos fallos del adaptador son S1 y su proceso, el error conocido de mi instrumento, que no toqué;
  - los veredictos son idénticos a los de la entrega 10.

**Dos observaciones de diseño (informativas):**
- una suelta encolada, cancelada al suspender y aplicada después por el lote corregido, se ejecuta físicamente pero **no emite su efecto**;
- volver a encolar ese id con el mismo contenido devuelve `true` sin ejecutar nada.

**Lo que no se certifica:**
- las etiquetas de ámbito **no autentican al emisor**;
- el "proveedor de ojos corregidos" es mi instrumento, no `NetSync`;
- no hay transporte, inventario ni presentación;
- no se probó en dos PC ni se midió rendimiento.

`model_approved` sigue en `false`.

## Base, compilación y corridas

- **Copia:**
  - Avance directo `b49d3ec` → `0aed621`. Los 87 archivos de `..\entrega_11.json` coinciden (tres JSON solo en LF).
  - No cambiaron mis instrumentos, la producción, el núcleo, `Cargo.lock` ni `Cargo.toml`.
- **Compilación:**
  - `CoreTests`: 15 ejecutables con código 0 y 29 funciones; N3 sigue `ignored`.
  - `Extension`: sin recompilar. Mi DLL `64679e73…` es la misma de la entrega 10.
- **Reproducción de Codex:**
  - `run_object_native_probe.ps1`: 7 `PASSED`.
  - `run_object_clock_probe.ps1`: importación y 11 modos `PASSED`, incluidos `api_authority`, `api_scope`, `api_time` y `api_recovery`. El más largo fue la importación, con 3,68 s.
- **Mis corridas, en `tmp/validacion_objetos/entrega_11/`:**
  - `rust_20261117_112831`;
  - `godot_20261117_112833`;
  - `adapter_20261117_112845`, el adaptador de la entrega 10;
  - **corrida oficial de los modos nuevos:** `adapter11_20261117_113408`;
  - corrida anterior con el modo mal nombrado: `adapter11_20261117_113317.intento1_resync_heredado`;
  - repetición de `resync11` solo: `adapter11_20261117_113352`;
  - revisiones de sintaxis: `check_20261117_113247`, la que encontró errores, y `check_20261117_113301`.
- **Reproducción de Codex, en las carpetas de su runner:** `tmp/native_probe/20261117_142752_2cd9e3` y `tmp/clock_probe/20261117_142756_913362`.
- **Límites y cierre:**
  - 8 s por proceso. No venció ninguno y no quedó ningún Godot abierto.
  - Mis modos usan `--fixed-fps 60`.

## Resultado por prueba

| Parte | Resultado |
| --- | --- |
| P1–P3 | Pasan |
| Q1 Rust | 135 pasan, 0 fallan, 23 informativas, 1 no evaluable; sin cambios contra la entrega 10 |
| Q2 Godot nativo | 79 pasan, 0 fallan, 4 informativas; sin cambios |
| Q3 adaptador de la entrega 10 | 80 pasan, 2 fallan, 13 informativas. Solo fallan S1 y `G0_slow`, el error conocido del instrumento. Veredictos idénticos a la entrega 10 |
| K1, K2, K3 (`scope`) | Pasan |
| K4, L1, L2, L3 (`late`) | Pasan |
| W1, W2, W3 (`time`) | Pasan |
| H1–H5 (`actor`) | Pasan; H6 informativo |
| R1 (`resync11`) | Pasa |

En la corrida oficial de los modos nuevos: 55 pasan, 0 fallan y 9 informativas, más las copias (225 iguales) y los scripts cargados (10 con el SHA del repositorio) en cada modo.

## Por punto del encargo

### 1. Actualización y DLL

Hecha. El núcleo no cambió y mi DLL sigue siendo la misma.

### 2. Contrato y criterios

`criterios_entrega_11.md`, con la lectura del código antes de correr. Los instrumentos están en `prototypes/objetos_adaptador/validacion_claude/`:
- `cv11_probe.gd` hereda de mi `cv10_probe.gd` sin modificarlo;
- `run_adapter_claude_e11.ps1` es una copia del runner de la entrega 10, que queda sin cambios.

### 3. Ámbito y revisión

**K1, sin crear candidato (26 casos):**
- conexión, contexto, uid, aparición o sesión distintos, o firma de otro valor o largo → `authority_scope`;
- `version` 2 → `authority_version`;
- revisión 0 o en punto flotante, tick −1, una clave de más o de menos → `invalid_authority_envelope`;
- snapshot de texto, vacío o de más de 1 MiB → `invalid_checkpoint`;
- `acks` que no es lista, con 17 elementos, id desconocido, otro tipo, otro tick pedido, aplicado antes del pedido, aplicado después del paquete, repetido o con 5 claves → `invalid_action_confirmation`;
- tick futuro → `future_authority`.

En todos: el mundo, la última autoridad, la generación, `ready`, los efectos y las recuperaciones sin cambios, y 0 llamadas a la fábrica.

**K2:** snapshot dañado → `checkpoint_rejected`; snapshot del tick 14 rotulado 15 → `checkpoint_tick_mismatch`. Las dos con una llamada a la fábrica y sin cambios.

**K3:** después, el paquete válido con **revisión 1** se acepta y queda igual a R_aut@20; antes estaba a 0,071. `start` con conexión 0 → `invalid_context_binding`, sin conectarse al reloj.

**K4, mismo tick:**
- en el presente 40, la revisión 3 en el tick 37 se acepta, y la **revisión 4 en el tick 37**, con un estado distinto (separado 1,83), también;
- queda igual a la rama de la revisión 4, y la última autoridad es tick 37, revisión 4;
- la revisión 4 otra vez y la 3 → `duplicate_or_stale_revision`; la 5 en el tick 36 → `authority_tick_regression`; la 5 en el 41 → `future_authority`. Todas atómicas.

**Lo que esto no es:** son comprobaciones de coherencia de metadatos acordados por la escena. No autentican al emisor; esa frontera sigue a cargo del transporte, que todavía no existe.

### 4. Suelta tardía

El escenario:
- la predicción suelta en 30 (id 12);
- mi host H la aplica en 34;
- H tiene además el impulso al vecino del tick 5, que el adaptador nunca vio.

**L1 (presente 33):** H@32 con la confirmación `{12, release, 30, 34}` → `invalid_action_confirmation`, atómico y sin fábrica. Después, H@32 sin confirmación y con la **misma revisión 1** se acepta: queda igual a H@33 y el objeto sigue agarrado, porque el host todavía no soltó. Antes de corregir estaba a 1,52.

**L2 (presente 37):** H@34 con la confirmación aplicada en 34 se acepta y queda igual a H@37; el objeto ya está suelto. Antes estaba a 1,22.

| Control | Separación |
| --- | --- |
| Desde H@34, otro impulso de suelta en 35 | 0,995 |
| Desde H@33, sin soltar nunca | 1,221 |

**L3:** los efectos son exactamente `[[11, grab], [12, release]]`, en los ticks 6 y 30. Ninguna autoridad aplicada emitió otro.

### 5. Historia corregida, notificaciones, lotes y recuperación

**Tiempo (`time`):**
- **W1:** en el presente 30 anuncio el tramo 25–32 a 0,5. `apply` con autoridad en 24 → `timeline_invalidated:world_time`, con recuperación. El mundo y la última autoridad no cambian, la generación sube 1, el frame 25 se borra y el 24 se conserva, sin fábrica.
- **W2:** un lote 25..30 con el dt viejo → `invalid_recovery_frame`, atómico. Con el dt nuevo → éxito, igual a mi rama R_nueva@30, que está a 1,92 de la rama vieja.
- **W3:** la captura se reanuda y queda igual a R_nueva de 31 a 45, incluidos los dos ticks lentos que todavía faltaban.

**Actor (`actor`):**
- **H1, invalidaciones:**
  - en 18, `invalidate_history_from(16, "actor")` → detenido, el 16 borrado y el 15 conservado;
  - en 20, otra notificación → generación + 1 y otra señal;
  - un tick futuro → `true` sin cambios;
  - causa `"red"` → `invalid_history_change`.
- **H2, rechazos atómicos:**
  - llamada desde el proveedor del tick 24 → `recovery_phase`;
  - en el presente 24, 17 lotes inválidos, cada uno con su código y sin cambios: generación vieja, 8 y 10 frames, orden cambiado, una clave de más, dt entero, dt de otro valor, ojos NaN, input en lista, frame que no es diccionario, input de otro tick o de otra sesión, acción desconocida, acción con otro impulso o en otro tick, paquete de otro ámbito, snapshot de otro tick.
- **H3, recuperación (presente 24, suspendido desde el 19):**
  - lote T = 15 con 16..24, ojos corregidos +0,12 m y la suelta del 19 → éxito, igual a mi R_corr@24;
  - no cambiaron la posición del actor, el tick del reloj ni las llamadas al proveedor;
  - el diario 16..24 es exactamente el lote, sin frames ≤ 15;
  - no hubo efectos.
- **H4:**
  - la captura se reanuda en 25 y queda igual a R_corr de 25 a 44;
  - `recover` estando activo → `recovery_not_needed`;
  - la revisión 1 otra vez por `apply` → `duplicate_or_stale_revision`.
- **H5:** con una invalidación en 45, un lote de 25 pasos → `replay_budget`, atómico; uno de 24 (desde R_corr@21) se acepta e iguala. El final en 49 es igual a R_corr.
- **H6, informativo:**
  - la suelta encolada en el 18 para el 19 se canceló al suspender;
  - el lote corregido la incluyó y se aplicó físicamente: el objeto no quedó agarrado;
  - pero `action_effect` nunca la emitió: los efectos son solo `[[11, grab]]`;
  - volver a encolar el id 12 con el mismo contenido devuelve `true` sin ejecutar nada, y con otro tick → `action_identity_conflict`.

**Resincronización (`resync11`):**
- detenido por una invalidación en 15, `hard_resynced` en 17 sube la generación, emite `clock_resynced` y vacía la historia;
- un lote con la generación anterior → `stale_recovery_generation`, atómico;
- un lote válido en 18 (T = 12) se acepta, igual a R_aut@18, y sigue igual hasta el 25.

### 6. Regresiones y S1

Corrí mis tres runners anteriores sin cambios y comparé sus `report.json` y `compare.json` con los de la entrega 10: **0 veredictos distintos y 0 comprobaciones nuevas o faltantes.** S1 y `G0_slow` siguen fallando por el conteo de mi instrumento (23 en el tick 32, cuando el tramo tiene 24); no lo modifiqué. No repetí N3.

### 7. Límites

8 s por proceso. Este informe está en `docs/net/validacion_objetos/entrega_11.md`.

## Qué falta para red, `NetSync` e inventario

1. **Ojos corregidos:** en estos ensayos los entrega mi instrumento. No hay un punto de conexión con `NetSync` que los produzca, ni que llame a `invalidate_history_from` cuando corrige al actor.
2. **Recuperación:** quien la pide tiene que tener la historia completa de los ticks suspendidos (input, ojos y dt). Hoy no hay quién la guarde mientras el adaptador está detenido.
3. **Tiempo hacia atrás:** se detecta recién en el próximo `apply`. Entre el anuncio y ese paquete, la predicción sigue con el dt viejo.
4. **Confirmaciones:** solo se validan; no resuelven nada. Una acción que se ejecuta por primera vez dentro de una recuperación (H6) no tiene efecto externo, y un duplicado de una acción cancelada devuelve `true`. La resolución de dominio, como sonido o transacción, queda para la autoridad futura, como dice el README.
5. **Transporte:** no hay autenticación ni transporte; las etiquetas no lo reemplazan.
6. **Sin tocar en esta entrega:** `history_expired` sigue sin poder alcanzarse, y el mapa colisionador → nodo para colisionadores sin pares sigue sin revisarse (entrega 9).

## Errores propios

1. **Modo mal nombrado.** Llamé `resync` a mi modo nuevo, y ese nombre activa también el modo `resync` heredado de mi escena de la entrega 10. Esa prueba vieja volvió a resincronizar en el tick 20, después de mi recuperación, y la primera corrida dio 3 FAIL que no eran del adaptador.
   - Cambié el nombre a `resync11` (`6f915bc`), marqué esa corrida como `intento1_resync_heredado` y repetí los cinco modos; todos pasan.
   - Mis dos comprobaciones propias de ese modo ya habían pasado en el intento.
2. **Tres errores de tipos en GDScript** (`ok3`, `ok4`, `hist_ok`). Los detectó `-CheckOnly` antes de correr (`check_20261117_113247`).
3. **Una métrica engañosa.** `H1_invalida_desde_16` muestra la lista completa de recuperaciones del modo (3), porque la lista se escribe al final. La comprobación se evaluó en el tick 18, con 1.

## Límites

- Una PC y perfil dev.
- Mis modos con `--fixed-fps 60`.
- Entradas, ojos corregidos y autoridad generados localmente por mi instrumento.
- Sin red, sin `NetSync` real, sin inventario y sin dos PC.
