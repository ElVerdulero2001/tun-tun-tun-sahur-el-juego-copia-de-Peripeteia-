# Verificación independiente de la entrega 12: puente de historia con `ClientPrediction` real

2026-11-17. Claude. Base: `c1359d2`.

**Orden de los commits:**
- Criterios en `criterios_entrega_12.md` (`461ad90`, 13:09). Se escribieron después de leer el puente y el argumento nuevo, y antes de compilar o correr nada.
- Instrumentos en `b72dbdd` (13:15), antes de la corrida oficial.

## Dictamen

**El puente hace lo que el README describe, en el alcance local probado.**

**Se usa el `ClientPrediction` real:** el de `res://scripts/net/client_prediction.gd`, con el SHA del repositorio, y la misma instancia que usa el puente.

**Los frames salen de pasos reales:**
- cada frame repetido es igual a lo que observé **dentro** de cada paso real de `ActorMotor` que llamó `ClientPrediction`;
- mis llamadas fueron exactamente los ticks esperados (16..25, 18..29, 31..33, 40..42 y 21..29), sin llamar al proveedor;
- el frame ancla tiene los ojos del estado del host.

**Grabación:**
- en vivo, también con el objeto detenido, cada frame del puente es igual a mi verdad: tick, dt, ojos después del motor, intención sin claim y acción;
- el estado del actor es igual por bytes;
- el input original no se modifica: 73 bytes con el claim de 41, contra una intención de 32;
- el reintento idéntico se acepta.

**Recuperación:** todas las recuperaciones dejan el mundo nativo igual por bits a mi referencia en el mismo tick, sin mover el actor ni el reloj, y sin llamar al proveedor ni a mi paso.

**Casos difíciles:**
- falta de historia → bloqueo;
- un estado coincidente fuerza 3 pasos reales y repone la base;
- la generación avanza aunque el tick sea posterior al mundo congelado, y el lote en vuelo se rechaza;
- un tick sin captura se rehace;
- un hueco en `ClientPrediction` deja la base inválida;
- una recuperación dentro de un tick se rechaza.

**Efectos y confirmaciones:**
- una suelta cancelada al suspender se aplica en la recuperación **sin** efecto;
- su primera confirmación emite el efecto una vez;
- la misma confirmación en otra revisión no repite nada;
- confirmar un agarre ya ejecutado en vivo da la confirmación sin otro efecto;
- `known` distingue "registrado" de "ejecutado".

**`ClientPrediction` sin el argumento nuevo** se comporta **igual que la versión anterior** (`b4aa90c`) en cinco casos: contadores, llamadas, estado final del actor y estados guardados. Con el argumento repite el caso coincidente y conserva las guardas de afirmación vieja e input tardío.

**Sin regresiones:**
- Rust 135/0, Godot nativo 79/0, adaptador de la entrega 10 80/2 (solo el S1 conocido) y adaptador de la entrega 11 55/0;
- todos con veredictos idénticos a la entrega 11.

**Mi corrida:** 60 pasan, 0 fallan, 1 informativa.

**Lo que no se certifica:** la recepción real de `NetSync`, ENet, el laboratorio migrado, el inventario y los permisos, dos PC y el rendimiento. Los estados de autoridad y del actor que disparan las correcciones los inyecta mi instrumento.

`model_approved` sigue en `false`.

## Un dato del proyecto principal

Fuera de las copias, el árbol de trabajo del proyecto principal (`C:\Users\ElCaido97\Documents\tun-tun-tun-sahur`) tiene **`scripts/net/client_prediction.gd` modificado con la versión de esta entrega**: el mismo SHA `53f88c37…` y la misma hora (17/11, 11:59:26) que en la copia de Codex.

- Su último commit (`677086f`) conserva la versión anterior (`3614d2b7…`).
- También hay, sin commitear, `prototypes/` (con mis instrumentos), `native/` y scripts de `tools/testing/` de la colaboración.
- `net_sync.gd` también está modificado, pero desde el 15/11, antes de la colaboración: es trabajo propio y no viene de Codex.

No toqué nada de eso. Lo informo porque el cambio de producción ya está en el árbol del juego, aunque sin commit.

## Base, compilación y corridas

- **Copia:**
  - Avance directo `b4aa90c` → `c1359d2`. Los 303 archivos de `..\entrega_12.json` coinciden (4 JSON solo en LF).
  - No cambiaron mis instrumentos.
  - El único cambio de producción es `client_prediction.gd`. El núcleo no cambió.
- **Compilación:** `CoreTests` con 15 ejecutables en código 0; `Extension` sin recompilar, con la misma DLL (`64679e73…`).
- **Reproducción de Codex:**
  - `run_object_native_probe.ps1`: 7 `PASSED`.
  - `run_object_clock_probe.ps1`: importación y 16 modos `PASSED`, incluidos los 5 `hist_*`. El más largo fue la importación, con 3,68 s.
- **Mis corridas, en `tmp/validacion_objetos/entrega_12/`:**
  - regresiones: `rust_20261117_131015`, `godot_20261117_131017`, `adapter_20261117_131028` y `adapter11_20261117_131040`;
  - **corrida oficial de los modos nuevos:** `adapter12_20261117_131545`;
  - revisión de sintaxis: `check_20261117_131529`.
- **Reproducción de Codex, en las carpetas de su runner:** `tmp/native_probe/20261117_160928_93ad32` y `tmp/clock_probe/20261117_160932_93807c`.
- **Límites y cierre:**
  - 8 s por proceso. No venció ninguno y no quedó ningún Godot abierto.
  - Mis modos usan `--fixed-fps 60`.

## Por punto del encargo

### 1. Actualización

Hecha, con la misma DLL.

### 2. Lectura y criterios

`criterios_entrega_12.md`. Mis instrumentos están en `prototypes/objetos_adaptador/validacion_claude/`:
- `cv12_probe.gd`, una escena propia que no hereda de Codex;
- `run_adapter_claude_e12.ps1` y `cv12_report.mjs`, copias de mis versiones anteriores con modos y escena nuevos;
- `cv12_client_prediction_e11.gd`, la versión anterior de `ClientPrediction` sin la línea `class_name`. Es solo para comparar.

### 3. `ClientPrediction` real y frames de pasos reales

**B0:** dentro del motor, `ClientPrediction` y las otras 8 clases, `actor.tscn`, `clock_adapter.gd`, `history_bridge.gd` y mi copia vieja tienen el SHA del repositorio. El puente usa la misma instancia que creé.

**B2, corrección del actor (`actor`):**
- en el comienzo del 26, `reconcile_actor(15)` con +1,5 m/s y +5 cm en x;
- mi paso se llamó para 16..25;
- los frames 16..25 son iguales a mis observaciones dentro de cada paso, y el 15 al estado del host;
- no se llamó al proveedor y el objeto quedó detenido;
- la dispersión de las diferencias de ojos fue de 4,2 mm, **chica pero mayor que 1e-3**: el motor recalcula la velocidad desde el input, así que el cambio se diluye pronto.

**B5, tiempo hacia atrás (`time`):**
- en el comienzo del 30, `apply_world_slow(18, 34, 0,5)` repite 18..29 con dt a la mitad;
- los frames tienen ese dt y los ojos reales, con una dispersión de **17 cm**, que descarta una traslación fija;
- el objeto se detiene en el anuncio.

**Variaciones:** el proveedor cambia en cada tick el movimiento, el yaw, agacharse (12–17), correr (40–46), el salto (desde 25) y el `hold`. Las correcciones cambian velocidad y posición, y el tramo de tiempo es pasado.

### 4. Suspensión, huecos y capturas

- **B3, durante la suspensión (26–28):** el puente sigue grabando (frames presentes) y el mundo nativo no avanza. La recuperación en 29 (T = 14, 15 frames) queda igual a mi referencia rehecha, sin tocar el actor, el reloj, el proveedor ni mi paso. El diario del adaptador es igual a mi verdad.
- **B6, falta de historia:** con `ClientPrediction` vaciado, `apply_world_slow` → `false`, base inválida y pedido `actor_history_unavailable`. Recuperar → `actor_baseline_required`, atómico.
- **B7, estado coincidente y generación:**
  - con el mundo congelado en 29, `reconcile_actor(30)` con el estado **coincidente** fuerza 3 pasos reales (31..33), iguales a lo grabado en vivo, y repone la base;
  - la generación pasa de 2 a 3 aunque 30 sea posterior al mundo congelado (el arreglo de esta entrega);
  - un lote preparado con la generación 2 → `stale_recovery_generation`, atómico;
  - la recuperación en 34 queda igual.
- **B8, tick sin captura:** sin captura en 40 → `input_not_captured` y objeto detenido. En 43, el estado coincidente del 39 rehace 40..42, iguales a lo vivo, y el frame 40 queda igual a mi verdad. La recuperación en 43 queda igual.
- **B9, hueco y fase:**
  - sin `record` en 46, una corrección del 45 en el 49 repite solo 47 y 48 → base inválida y pedido `actor_replay_gap`. Recuperar → `actor_baseline_required`, atómico;
  - recuperar desde el proveedor (dentro del tick 36) → `authority_phase`, atómico.
- **Captura (B1):**
  - el reintento idéntico se acepta;
  - el input original conserva sus bytes y su claim en todos los ticks;
  - el diario del adaptador nunca recibe el claim;
  - el conflicto con otros bytes del mismo tick no lo ejercité en mi escena; lo cubre el código leído (§0 de los criterios).
- **El replay nativo no vuelve a simular al actor:** en cada recuperación, el estado del actor, el tick, las llamadas al proveedor y las de mi paso no cambian.

### 5. Efectos y confirmaciones (`effect`)

- **B10, la suelta cancelada:**
  - en el comienzo del 30, la suelta 32 para el 31 queda `queued`, y una corrección real desde el 20 detiene el objeto;
  - en el 31, volver a encolarla → `rejected` (`not_ready`), informativo;
  - el puente graba el frame 31 con la acción;
  - la recuperación en 35 (T = 19) queda igual a mi referencia: el objeto se soltó en 31 y **no** hubo efecto del 32;
  - `known` del 32: sin efecto y sin confirmación.
- **B11, las confirmaciones:**
  - la confirmación `{32, release, 31, 31}` en 37 da el primer efecto y la primera confirmación;
  - la revisión siguiente con la misma confirmación no repite nada;
  - la confirmación del agarre 21, ya ejecutado en vivo, agrega su confirmación sin otro efecto;
  - `known` del 32 ya tiene efecto y confirmación;
  - el adaptador solo emitió en vivo el agarre.

**Separación:** el efecto provisional sale en la ejecución en vivo, y la confirmación sale aparte. No hay sonidos, transacciones ni permisos, y no los certifico.

### 6. Comportamiento anterior y guardas (`guards`)

**G1:** para cada caso, la versión nueva **sin** el argumento y mi copia de la anterior, con los mismos registros y el mismo actor (restaurado entre corridas), dan los mismos contadores, las mismas llamadas, el mismo estado final y los mismos estados guardados.

| Caso | Resultado común |
| --- | --- |
| Coincide | 1 coincidencia, sin llamadas |
| Afirmación vieja después de una corrección | 1 afirmación adoptada, sin llamadas |
| Input tardío | 1 espera, sin llamadas |
| Corrección | 1 corrección, llamadas 12..19 |
| Alineación | 1 alineación, llamadas 1..19 |

**G2, con `replay_matching_state = true`:**
- si coincide, repite 13..19 y termina exactamente en el estado del 19 grabado;
- la afirmación vieja y el input tardío conservan su guarda, sin llamadas.

El único llamador del juego, `net_lab.gd:2344`, usa 6 argumentos, o sea, el valor por defecto.

**Regresiones:** las cuatro dan los mismos veredictos que en la entrega 11. S1 sigue anulado por el conteo de mi instrumento y no lo modifiqué. No repetí N3.

### 7. Límites

8 s por proceso. Informe en este archivo.

## Qué falta

1. **Laboratorio:** el puente no está instalado en `net_lab.gd`. La recepción real de estados del actor por `NetSync` y la de objetos por ENet no llegan a estos puntos de conexión.
2. **Acciones durante la suspensión:** se rechazan (`not_ready`). La escena tiene que decidir qué hacer con un pedido del jugador mientras tanto.
3. **Inventario:** las confirmaciones no resuelven permisos ni transacciones, y un id `known` no garantiza nada del inventario.
4. **Memoria:** durante una corrección hay dos mundos, más la historia de `ClientPrediction`. No se midió en la notebook.

## Errores propios

1. **Métricas que muestran listas finales.** Varias métricas guardaron la lista misma y no una copia, así que el JSON muestra su contenido final y no el del momento de la comprobación: en B7 y B8, "llamadas" muestra [47, 48]; los "pedidos", "efectos" y "confirmaciones" de B6, B8, B10 y B11 incluyen entradas posteriores. Las comprobaciones se evaluaron en su momento, con los valores correctos, y pasaron. Es solo la presentación.
2. **La dispersión de B10 dio 1,2e-7:** una traslación casi fija. No estaba entre sus exigencias. La prueba fuerte de que vienen de pasos reales es la comparación paso a paso y B5.
3. **El conflicto de captura** del encargo no lo ejercité en la escena (ver §4).

## Límites

- Una PC, perfil dev.
- Mis modos con `--fixed-fps 60`.
- Estados de actor y de autoridad inyectados por mi instrumento.
- Sin red, sin `NetSync` real, sin inventario y sin dos PC.
