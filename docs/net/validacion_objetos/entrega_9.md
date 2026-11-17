# Verificación independiente de la entrega 9: validación de grafos y pose fija

2026-11-17. Claude. Base: `db4b6e0`, entrega 9.

**Orden de los commits:**
- Criterios en `criterios_entrega_9.md` (`100f19f`, 08:43). Se escribieron después de revisar el código y antes de compilar o correr nada.
- Cambio de filtro del runner original en `107b210`, después de correrlo sin tocar.
- Verificadores nuevos en `6ee58be` (08:48), antes de correrlos.
- Dos arreglos del runner nuevo, `719d775` y `0d0768d`, sin que llegara a correr ninguna prueba.
- Después de correr: `#[ignore]` en N3, en un commit propio. El diagnóstico va junto con este informe.

## Dictamen

**La corrección hace lo que dice, dentro del uso `trusted`:**
- **D18:** mi barrido original (8.055 mutaciones con la suma recalculada) ya no produce pánicos ni acepta pisos movidos. Las 22 de antes ahora se rechazan, y las 25 del piso también.
- **Ampliado a todos los bits** (64.440 mutaciones): 0 pánicos al restaurar, al muestrear y al lanzar rayos, y todos los rechazos son atómicos.
- **Falsos rechazos:** ninguno en 1.692 restauraciones de snapshots genuinos, en siete escenas que incluyen la pila de 128 cuerpos (490 contactos), rampas fijas con giros arbitrarios, altas y bajas antes de sellar, rebotes, CCD y la caché.
- **Historia intacta:**
  - el SHA de mi trayectoria de referencia es el mismo que en la entrega 8;
  - los artefactos de intercambio de Codex y míos son idénticos por bytes a los de la entrega 8;
  - mis 135 comprobaciones Rust y 79 de Godot originales pasan.

**Una falla de mi criterio, sin efecto físico medido:**
- N2 exigía que el piso aceptado fuera igual **por bits**. Se aceptan 5 mutaciones que solo cambian el signo de un cero (0 → −0) en la pose del piso.
- La validación compara con `!=` de punto flotante, donde −0 = 0. La trayectoria de 300 pasos es numéricamente idéntica.

**Límites registrados, no aprobados:** con datos alterados y la suma recalculada, el validador sigue aceptando parámetros internos que rompen `step()`:
- **cuelgues:** los contadores de iteraciones del solver, `num_solver_iterations` y siguientes, en los bytes 156–187 del payload;
- **aborto del proceso entero:** un pedido de memoria de 137 GB en los bytes 274–276;
- **273 pánicos dentro de `step()`.**

Codex ya declara que la API no es una frontera para datos arbitrarios. Esto muestra con casos concretos qué pasa si lo fuera.

**Costo:** restaurar la pila de 128 tarda ahora 4,2 ms contra 1,9 ms antes (×2,25), y `restore_cached` 4,3 ms contra 2,1 ms. El snapshot chico pasa de 26 a 37 µs. Es perfil dev con optimización 1: **no es una medida de rendimiento**.

**La regresión de Godot no aprueba el controlador real:** es el mismo cronograma preacordado.

`model_approved` sigue en `false`, y el laboratorio no está migrado.

## Base, compilación y comandos

- **Copia:**
  - Solo `tmp/` estaba sin versionar.
  - Fetch local y avance directo `25d97f8` → `db4b6e0`.
  - Los 47 archivos de `..\entrega_9.json` coinciden; `resultados_codex_entrega_9.json` coincide en su versión LF.
  - Mis instrumentos llegaron sin cambios.
  - No copié binarios de la implementación.
- **Compilación:** con el builder de Codex sin cambios, `-CargoCachePath '..\implementacion\tmp\native_toolchain\cargo'`.
  - `CoreTests`: 24 s, 8 ejecutables y 23 funciones que pasan: 2 nuevas de Codex, 9 de Codex y 12 mías.
  - `Extension`: 12,5 s.
  - **DLL propia:** 5.720.064 bytes, `0537a27d…98c4`. No es igual por bytes a la de Codex (`8f1d8be4…`), mismo tamaño.
- **Corridas, todas en `tmp/validacion_objetos/entrega_9/` salvo la primera:**
  - **Reproducción de Codex:** `tmp/native_probe/20261117_114411_89e2ca`.
  - **Rust original:** `rust_20261117_084425`.
  - **Godot original:** `godot_20261117_084443`.
  - **Verificadores nuevos:** `e9_20261117_085052`, más `n3_recorrido/` dentro de esa carpeta.
  - **Diagnóstico:** `diag_e9_*`.
  - **Intentos fallidos del runner nuevo,** conservados y sin contar: `e9_…_084853.intento1_error_del_instrumento` y `e9_…_084924.intento2_error_del_instrumento`.
  - **Primer intento de completar N3:** `e9_20261117_085052/n3_completo_salteando_156_187`, abortado en el byte 274.
- **Cierre:** no quedó ningún Godot abierto ni ningún worktree registrado.

## Resultado por prueba

| Parte | Resultado |
| --- | --- |
| P1 compilación | Pasa: dos etapas con código 0 |
| P3 funciones de `CoreTests` | 23 pasan |
| P4 siete procesos de Codex | 7 con código 0 y `PASSED`, sin errores. Suelta tardía en T = 71, 4 pasos repetidos |
| Q1 Rust original | 135 pasan, 0 fallan, 23 informativas, 1 no evaluable. Ninguna regresión; D18b pasa de FAIL a PASS |
| Q1a/Q1b D18 | 0 pánicos, 0 rechazos con cambios, 0 pisos aceptados distintos (comparación numérica de D18) |
| Q1c historia | SHA A6 `b4a53687…7668`, igual en dos procesos y al de la entrega 8 |
| Q3 Godot original | 79 pasan, 0 fallan, 4 informativas. ENet: Codex T = 71, push T = 72; mismo SHA en cada tick |
| N1 falsos rechazos | Las 7 escenas pasan: 1.692 restauraciones y 55 continuaciones iguales por bits |
| N2 todos los bits | Pasan: pánicos, atomicidad, muestras y rayos. **Falla** "piso intacto por bits": 5 casos de −0 |
| N3 paso tras aceptar | Informativo: 4.937 normales, 273 pánicos en el paso, 3 abortos y cuelgues en 156–187 |
| N4 costo | Informativo: ×1,39 (F), ×2,25 (pila), ×2,02 (pila en caché) |

## Por punto del encargo

### 1. Actualización

Hecha. Los hashes se detallan en "Base". Mis pruebas y trazas anteriores quedaron intactas.

### 2. Revisión antes de ejecutar

Está en `criterios_entrega_9.md` §1, guardada en el historial antes de compilar.

**Vista serde (R1):**
- `Node`, `Edge` (con `prev`) y `Graph` coinciden campo por campo con `rapier3d-0.36.0/src/data/graph.rs`.
- La versión está fijada en `Cargo.toml` (`=0.36.0`) y en `Cargo.lock`.

**Lo que no se comprueba (R3):**
- que un colisionador **sin pares** apunte a su propio nodo en `graph_indices`;
- el índice hacia el grafo de intersecciones;
- los demás datos internos, como los parámetros de integración.

N3 muestra el efecto de esto último.

### 3. Compilación, runner Rust y analizador

- Resultados en la tabla de arriba.
- La comparación con el `report.json` de la entrega 8 da 0 regresiones y 0 comprobaciones faltantes. El único cambio es D18b.
- **D18b ahora rechaza 241 mutaciones que antes aceptaba:**
  - 184 por `snapshot_contact_graph`, 32 por `snapshot_contact_mapping` y 25 por `snapshot_fixed_pose`;
  - incluyen las 22 que provocaban pánico y las 104 que cambiaban contactos o reposo.
- **Rechazos atómicos:** D01–D17 y E1–E6 pasan igual que antes.

### 4. Runner Godot y analizador originales

- Pasan todas las etapas:
  - el enlace, con Jolt intacto por bits contra dos controles;
  - el archivo entre procesos, con el artefacto `0eaaf960…` idéntico al de la entrega 8;
  - las dos variantes de ENet.
- En la variante push con T = 72, todos los números coinciden con la entrega 8. B se separó 0,245892 m antes de corregir; los saltos fueron 0,268 m y 0,246 m.
- Esto es una **regresión** sobre el cronograma preacordado. No valida el controlador real, `SimClock` ni la presentación.

### 5. Acoplamiento, falsos rechazos y costo

**Acoplamiento:**
- **Fuerte:** la vista copia el formato privado de Rapier 0.36.0.
- **Si cambia el tamaño** de un campo, la decodificación falla y se rechaza **todo** snapshot. La falla es cerrada y la detecta enseguida cualquier prueba como N1.
- **Si cambia el orden** de campos del mismo tamaño, podría leer mal en silencio.
- **Lo que muestra N1:** los grafos reales de las siete escenas se decodifican y validan sin rechazos, con hasta 490 contactos listados y snapshots de hasta 616 KB.
- **Una consecuencia:** el grafo de intersecciones tiene que estar vacío, así que un sensor futuro haría rechazar el snapshot.

**Falsos rechazos (N1):** ninguno.

| Escena | Restauraciones | Continuaciones | Máximo de contactos listados |
| --- | --- | --- | --- |
| S1 fixture F | 600 | 22 | 6 |
| S2 agarre | 180 | 6 | 6 |
| S3 pila de 128 | 31 | 1 | 490 |
| S4 rampas giradas y bajas antes de sellar | 400 | 14 | 18 |
| S5 rebotes y CCD a 20 m/s | 300 | 10 | 8 |
| S6 24 fijos con poses pseudoaleatorias | 61 | 2 | 8 |
| S7 caché (`restore_cached`) | 120 | — | — |

- Todas las muestras restauradas son iguales por bits a las del origen.
- La comparación exacta de la pose fija no rechazó ningún snapshot genuino, ni siquiera con giros arbitrarios ni con coordenadas como 1,234567.

**Barrido de todos los bits (N2):**
- 64.440 mutaciones (8 bits × 8.055 bytes): se aceptan 41.990 y se rechazan 22.450.
- Entre los rechazos: 1.472 por el grafo, 256 por el mapa y 191 por la pose fija.
- 0 pánicos en `restore_trusted`, `samples()` o rayos, y 0 rechazos con cambios.
- **Falla de mi criterio "piso intacto por bits":**
  - las mutaciones (4992,7), (4996,7), (5000,7), (5008,7) y (5016,7) ponen −0 en qx, qy, qz, x y z del piso;
  - el diagnóstico (`claude_diag_e9`) muestra 300 pasos con diferencia 0 en posición, giro y velocidad, reposo y contactos iguales; solo cambia el signo de algunos ceros;
  - no tiene efecto físico medido en esta fixture.

**Un paso después de aceptar (N3, informativo).** Usé las mismas 8.055 mutaciones de D18:

| Resultado del paso | Casos | Bytes del payload |
| --- | --- | --- |
| Normal | 4.937 | — |
| Pánico dentro de `step()`, capturado | 273 | por ejemplo 151 y 229–233 |
| **Proceso abortado**: falló un pedido de 137 GB, 70 TB y 36 PB de memoria | 3 | 274, 275 y 276 |
| **Cuelgue de más de 8 s** | 6 vistos (159–163 y 167) | `num_solver_iterations` está en 156–163 (vale 4) y `num_internal_pgs_iterations` en 164–171 (vale 1). Un bit alto los lleva a unas 2³¹ iteraciones |

- El recorrido salteó 156–187 (los contadores del solver) y 274–276.
- Un aborto no lo atrapa `catch_unwind`. Dentro de Godot terminaría el proceso del juego.

**Costo (N4):**
- Compilé `claude_e9_cost.rs` sobre `db4b6e0` y, en un worktree temporal desde mi historial, sobre `aeee009`. Usé otro directorio de compilación, y el worktree ya se quitó.
- Hice tres rondas alternadas; las cifras son medianas de medianas.

| Caso | Bytes | Entrega 8 | Entrega 9 | Relación |
| --- | --- | --- | --- | --- |
| `restore_trusted` del snapshot de F | 8.099 | 26,4 µs | 36,8 µs | 1,39 |
| `restore_trusted` de la pila de 128 | 614.284 | 1,86 ms | 4,18 ms | 2,25 |
| `restore_cached` de la pila de 128 | 614.284 | 2,13 ms | 4,30 ms | 2,02 |

En la pila, la validación agrega unos 2,3 ms por restauración. Todo rollback local lo paga, porque `restore_cached` pasa por la misma validación. Es perfil dev con optimización 1 y no es una medida para la notebook.

### 6. Informe y límites

- Este archivo.
- No repetí `StateManager3D`.
- No declaro migrado el laboratorio ni aprobados los datos hostiles o el rendimiento.

## Errores propios

1. **Runner nuevo, intento 1:** git escribe "Preparing worktree" por stderr, y PowerShell 5.1 con `Stop` lo convirtió en error. No corrió ninguna prueba. Lo arreglé en `719d775`.
2. **Runner nuevo, intento 2:** con un solo ejecutable de base, PowerShell desarmó la lista y `[0]` tomó otra cosa. La base había compilado (73 s), pero no corrió ninguna prueba. Lo arreglé en `0d0768d`.
3. **La reanudación de N3 en el runner era insuficiente.** Saltaba un índice por intento, con 6 intentos de 8 s, y los cuelgues son un bloque de bytes seguidos. Completé N3 fuera del runner con un recorrido acotado: 4 procesos más, cada uno con 8 s, salteando 156–187. Está en `n3_recorrido/`.
   - Por eso el `R0_procesos` del resumen sale FAIL: lo vencido son los intentos de N3, que es informativo.
   - Los procesos que deciden (N1, N2 y costo) terminaron dentro del límite. `claude_e9_sweep_hi` termina con 101 por el FAIL de N2.
4. **El diagnóstico `claude_diag_e9` calculó mal la palabra afectada.** Alineó a 8 bytes desde el comienzo del payload, y en la línea `DIAG_E9_cuelgues` eso da números equivocados. La lectura correcta sale de los bytes 140–179 de la misma línea: el campo empieza en 156.
5. **`claude_diag_e9.rs` se corrió antes de guardarse en el historial.** Es solo diagnóstico y no decide; va en el mismo commit que este informe.
6. **Cambio después de correr:** `claude_e9_step_after` quedó como `#[ignore]` y mi runner lo llama con `--ignored`, porque si no, el `CoreTests` de Codex se colgaría o abortaría en ese ejecutable. Comprobé que sin `--ignored` termina enseguida con "1 ignored". No cambia nada de lo medido.

## Para Codex

1. **Signo del cero (N2).** `pack_pose(..) != fixed_pose` acepta −0 por 0. Si se quiere identidad estricta, se puede comparar con `to_bits()`. No encontré efecto físico.
2. **Datos alterados con la suma recalculada (N3).**
   - `validate_candidate` solo revisa `dt` de los parámetros de integración. Los contadores del solver cuelgan `step()`, y hay un campo en los bytes 274–276 cuyo valor alterado hace pedir 137 GB y aborta el proceso.
   - Lo reproduce `tests/claude_e9_step_after.rs` con `CLAUDE_STEP_SKIP`. Los bytes son de la fixture F en el tick 19.
   - Confirma que la frontera de red debe autenticar y acotar antes de llegar al núcleo.
3. **Mapa colisionador → nodo (R3).**
   - Un colisionador sin pares puede apuntar a cualquier nodo.
   - El índice hacia el grafo de intersecciones no se revisa.
   - No lo aislé en un caso; puede estar entre los 273 pánicos de N3.
4. **Costo.** La validación duplica, con creces, el costo de cada restauración grande, también la local. Conviene medirlo en la notebook antes de fijar presupuestos de rollback.
5. **Instrumentos.**
   - `run_claude_rust.ps1` ahora excluye `claude_e9_*` y `claude_diag_*`, y sigue corriendo los mismos 5 ejecutables.
   - Los verificadores nuevos tienen su propio runner, `run_claude_rust_e9.ps1`.
   - Si se incorporan, `CoreTests` también correrá `claude_e9_sweep_hi`, que termina con 101 por la falla de N2, y el builder se detiene en el primer ejecutable que falla.
   - `claude_e9_step_after` está marcado `#[ignore]`: no corre salvo con `--ignored`, porque sin `CLAUDE_STEP_SKIP` cuelga o aborta.

## Límites

- Una PC y binarios propios.
- Datos de snapshot confiables, topología fija y cajas centradas.
- Sin controlador real, `SimClock`, presentación, latencia o pérdida reales, ni dos PC.
- Los tiempos son de perfil dev y no son medidas de rendimiento.
