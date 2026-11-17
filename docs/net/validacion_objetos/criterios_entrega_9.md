# Criterios fijados antes de ejecutar: verificación de la entrega 9

2026-11-17 (hora argentina). Validación independiente de Claude sobre `db4b6e0` (entrega 9). Encargo: «Encargo acotado para Claude: entrega 9» de `docs/net/entregas/revision_codex_entrega_8.md`.

Este documento se escribe y se guarda en el historial **antes** de compilar o correr nada. Hasta ahora solo se actualizó la copia y se leyó el código.

## 0. Base

- **Copia actualizada:** `25d97f8` → `db4b6e0`, con fetch local y avance directo, sin conflictos.
  - Los 47 archivos de `../entrega_9.json` coinciden en SHA-256.
  - `resultados_codex_entrega_9.json` coincide solo en su versión normalizada a LF.
  - Mis instrumentos no cambiaron (`git diff 25d97f8 HEAD` vacío en mis carpetas).
- **No se copia ningún binario de la implementación.** Compilo los míos.
- **No modifico** el núcleo, el enlace, las fixtures, los runners de Codex ni ninguna tolerancia.
- **Trazas:** en `tmp/validacion_objetos/entrega_9/`, sin commitear.

## 1. Revisión del código, hecha antes de correr

- **R1, vista serde.** `snapshot_graph.rs` copia `Node {weight, next: [u32; 2]}`, `Edge {weight, next, prev, node}` y `Graph {nodes, edges}`. Coincide campo por campo con `rapier3d-0.36.0/src/data/graph.rs`, donde `EdgeIndex` y `NodeIndex` son `u32` envueltos. La versión está fijada dos veces: `=0.36.0` en `Cargo.toml` y `Cargo.lock`.
  - Si Rapier cambia el formato y el tamaño, la decodificación falla y **se rechaza todo**: falla cerrada y visible.
  - Si cambia el orden de campos del mismo tamaño, puede leer mal en silencio.
  - La prueba de Codex arma un grafo a mano; los grafos reales los ejercita N1.
- **R2, qué comprueba:**
  - límites;
  - colisionadores vivos y únicos;
  - extremos en rango, sin autoaristas y con pares únicos;
  - que `collider1`/`collider2` del par coincidan con los extremos, y `rigid()` (nulo solo entre blandos);
  - listas de adyacencia con `prev`/`next` coherentes, sin ciclos y con cada arista una vez por lado;
  - grafo de intersecciones **vacío**: cualquier sensor futuro sería rechazado.
- **R3, qué no comprueba:**
  - el mapa colisionador → nodo (`graph_indices`) se verifica solo contando pares incidentes y mirando que cada par devuelto incluya al colisionador. Un colisionador **sin pares** puede apuntar a cualquier nodo, incluso fuera de rango;
  - el índice hacia el grafo de intersecciones no se revisa;
  - fuera de los grafos, los demás datos internos siguen sin revisarse, como Codex declara.
- **R4, pose fija:** compara por igualdad exacta `pack_pose(body.position())` con `fixed_pose`, y exige `is_fixed()`. Un cuerpo fijo no se mueve, así que no debería haber falsos rechazos; N1 lo comprueba con poses giradas en ángulos arbitrarios.
- **R5, costo:**
  - cada restauración vuelve a serializar y deserializar los dos grafos, hasta 1 MiB;
  - además cuenta pares por objeto, del orden de objetos × aristas: hasta 128 × 8.128;
  - también lo pagan `restore_cached` y cada rollback local. N4 lo mide.

## 2. Qué no cambia y qué decide

- **Sin cambios:** EPS = 0,00001, sensibilidad > 1e-3, 8 s por proceso de prueba y 180 s por compilación.
- **Qué decide:**
  - decide cada comprobación marcada **sí**;
  - **informativo** se registra y no decide;
  - un error de un instrumento propio invalida solo ese caso, y el intento se conserva.

## 3. Parte P: compilación y reproducción

| Id | Qué | Decide |
| --- | --- | --- |
| P1 | `build_object_native.ps1 -Stage CoreTests` y `-Stage Extension` con `-CargoCachePath '..\implementacion\tmp\native_toolchain\cargo'`: código 0 y sin vencer. Ahora `CoreTests` corre también mis pruebas | sí |
| P2 | ¿Mi DLL es igual por bytes a la de Codex (`8f1d8be4…`)? | informativo |
| P3 | Todas las funciones de prueba que ejecuta `CoreTests` pasan; se informa cuántas son | sí |
| P4 | `run_object_native_probe.ps1 -Stages all`: 7 procesos con código 0, `PASSED`, sin errores | sí |

## 4. Parte Q: mis instrumentos originales, sin cambios (regresión)

`run_claude_rust.ps1` se corre **antes** de agregar archivos nuevos, porque exige exactamente 5 ejecutables `claude_*` sin contar los de diagnóstico.

| Id | Qué | Decide |
| --- | --- | --- |
| Q1 | `run_claude_rust.ps1` y `cv_rust_report.mjs`: 0 FAIL, y toda comprobación que pasó en la entrega 8 vuelve a pasar | sí |
| Q1a | D18b: 0 pánicos al restaurar y 0 al muestrear lo aceptado; 0 rechazos que cambian el destino | sí |
| Q1b | D18b: la clase aceptada `pose_del_cuerpo_fijo` vale 0 | sí |
| Q1c | Historia intacta: el SHA de la trayectoria A6 es igual en dos procesos **y** al de la entrega 8 (`b4a53687…7668`) | sí |
| Q1d | Rechazos atómicos D01–D17 y caché E1–E6, todos PASS | sí |
| Q2 | Diagnóstico `claude_diag_d18`: lista de pánicos y de cambios del piso | informativo (se espera vacío) |
| Q3 | `run_native_claude.ps1` y `cv_native_compare.mjs`, con todas las etapas: 0 FAIL | sí |

Q3 es una **regresión** sobre el mismo cronograma preacordado. No aprueba el controlador real, el input, `SimClock` ni la presentación.

## 5. Parte N: verificadores nuevos

Archivos nuevos `native/objetos_core/tests/claude_e9_*.rs` y runner `prototypes/objetos_nativo/validacion_claude/run_claude_rust_e9.ps1`, con 8 s por ejecutable. Después de correr Q1, el filtro de `run_claude_rust.ps1` también excluirá `claude_e9_*`, como ya excluye `claude_diag_*`. Ese cambio va en un commit propio.

### N1. Falsos rechazos (decide)

Snapshots **genuinos**, cada uno restaurado con `restore_trusted` en un gemelo nuevo con el mismo manifiesto. Exigencias:
- devuelve `Ok`;
- las muestras restauradas son iguales por bits a las del origen;
- cada 25 ticks, el gemelo avanza 30 pasos más con el mismo cronograma y queda igual por bits al origen en t + 30.

| Escena | Contenido | Snapshots |
| --- | --- | --- |
| S1 | Fixture F con impulsos en 30 y 330 | ticks 1..600, todos |
| S2 | Agarre de C con objetivos, giro y suelta (como F1) | ticks 1..180, todos |
| S3 | 128 cuerpos apilados | ticks 0..120, cada 4 |
| S4 | Historial de altas y bajas antes de sellar (uid 90, 91 y 92 intercalados), dos rampas y una pared fijas con giros arbitrarios y coordenadas no redondas, seis cajas que caen y se deslizan | ticks 1..400, todos |
| S5 | Pares que nacen y mueren: tres cajas con rebote 0,9 y fricción 0,1, más una caja rápida (CCD) lanzada a 20 m/s contra una pared fija | ticks 1..300, todos |
| S6 | 24 cuerpos fijos con poses pseudoaleatorias (LCG fijo) y 3 dinámicos | ticks 1..60, todos |
| S7 | Camino de caché: S1 guarda los últimos 120 ticks y `restore_cached` se aplica a cada uno, del más nuevo al más viejo | 120 |

Si una escena no llega a tener pares de contacto (aristas), su parte de grafos queda **no ejercitada**. Se informa la cantidad máxima de contactos listados.

### N2. Barrido de todos los bits (decide)

Misma fuente que D18: fixture F en el tick 19. Se altera cada bit de cada byte del payload (8 por byte) y se recalcula la suma. Se reparte en dos ejecutables: bits 0–3 y bits 4–7.

**Decide:**
- 0 pánicos en `restore_trusted`;
- todo rechazo deja el destino igual por bytes;
- ninguna mutación aceptada cambia la pose del piso (bits iguales a los del origen);
- 0 pánicos en `samples()` y en la grilla de rayos sobre lo aceptado.

**Informativo:** códigos de rechazo y clases de lo aceptado.

### N3. Un paso después de aceptar (informativo)

Mismas mutaciones que D18 (un bit por byte). Por cada aceptada:
- se da un paso con `catch_unwind`;
- se registran pánicos, errores y si el piso se movió después del paso (indicio de tipo cambiado);
- el progreso se imprime para ubicar un cuelgue si vence el límite de 8 s.

Es para registrar los límites ante datos alterados, no para aprobar datos hostiles.

### N4. Costo adicional (informativo)

- Tiempo de `restore_trusted` con el snapshot de F (8 KB, 3.000 repeticiones) y el de la pila de 128 (614 KB, 40 repeticiones), y de `restore_cached` de la pila (40).
- Se mide en dos binarios: el actual (`db4b6e0`) y el anterior (`aeee009`). El anterior lo compilo yo, desde mi propio historial, en un worktree temporal con otro directorio de compilación y el mismo archivo de prueba.
- Se corren tres veces alternadas y se informan mediana y p90.
- Es perfil dev con optimización 1, en esta PC. **No es una medida de rendimiento ni la aprueba.**

### N5. Acoplamiento (informativo)

Lo de R1 a R3, más lo que N1 y N2 muestren sobre grafos reales y alterados.

## 6. Orden

1. Este documento, al historial.
2. P1–P4.
3. Q1–Q3, con los instrumentos sin tocar.
4. Instrumentos N y el cambio de filtro, al historial antes de correrlos.
5. N1–N4.
6. Informe `entrega_9.md`.

## 7. Fuera de alcance

- Los ensayos de `StateManager3D` y la matriz de Jolt.
- La integración, el laboratorio, el controlador real, `SimClock` y la presentación.
- Dos PC.
- Datos hostiles y rendimiento: solo se registran límites.
