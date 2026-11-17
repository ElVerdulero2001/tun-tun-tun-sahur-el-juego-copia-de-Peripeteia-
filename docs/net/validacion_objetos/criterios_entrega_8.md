# Criterios fijados antes de ejecutar: verificación de la entrega 8 (núcleo nativo)

2026-11-16 (hora argentina). Validación independiente de Claude sobre `aeee009` (entrega 8). Encargo: apartado «Encargo de Claude» de `docs/net/entregas/entrega_8_nucleo_nativo.md`.

Estos criterios se escriben y se guardan en el historial **antes** de correr cualquier cosa, también antes de reproducir los ensayos de Codex. Hasta ahora solo se actualizó la copia y se leyó el código.

## 0. Base

- **Copia actualizada:** `637fa91` → `aeee009`, con fetch local y avance directo, sin conflictos.
  - Los 23 archivos del manifiesto `../entrega_8.json` tienen el mismo SHA-256, tanto crudo como normalizado a LF.
  - Mis instrumentos y mis informes anteriores no cambiaron (`git diff 637fa91 aeee009` vacío en esas carpetas).
- **Lectura del código:**
  - `world.rs`: cada `ObjectWorld` tiene su propio `PhysicsWorld` y sus propios `objects`, `retired`, `tick` y caché.
  - El checkpoint serializa todo el `State` y lo envuelve en un sobre de 44 bytes: `SOBJW001` + largo + SHA-256.
  - `restore_impl` decodifica y valida un candidato antes de reemplazar el estado.
    - Si la restauración es local, borra la caché de los ticks mayores al restaurado.
    - Si es una importación, la borra entera.
  - **Lo que el validador compara:**
    - modelo (constante de texto);
    - contexto;
    - el mismo conjunto de claves;
    - `spec` y `fixed_pose` del manifiesto;
    - asociación cuerpo–colisionador–`user_data`;
    - forma cúbica;
    - velocidades finitas;
    - `dt`.
  - **Por código, no compara:**
    - que la pose real de un cuerpo fijo coincida con su `fixed_pose`;
    - los demás parámetros de integración;
    - los materiales del colisionador.
  - Eso se mide como dato (D18), no se da por defecto de antemano.
- **Solo agrego archivos en:**
  - `native/objetos_core/tests/claude_*.rs`;
  - `prototypes/objetos_nativo/validacion_claude/`;
  - `docs/net/validacion_objetos/`.
- **No modifico** el núcleo, el enlace, los runners, las fixtures de Codex ni sus tolerancias.
- **Trazas:** en `tmp/validacion_objetos/entrega_8/`, sin commitear.

## 1. Qué no cambia y qué decide

- **EPS = 0,00001.** Es el mismo de los ensayos actuales y del contrato. Se aplica a:
  - posición (m);
  - cada eje de la base, o cada componente del cuaternión;
  - velocidad lineal (m/s) y angular (rad/s).
- **Igualdad estricta:** el reposo, el agarre y la lista de contactos (identidades públicas) deben ser **iguales**.
- **Exactitud por bits:** se informa, pero no decide. La exigencia del contrato es EPS.
- **Sensibilidad:** cada control negativo debe separarse **> 1e-3** (100 × EPS) en alguna magnitud. Si no se separa, la comparación correspondiente no prueba nada y queda **no evaluable**.
- **Rayos:** distancia contra la geometría conocida ≤ 1e-5 m. Igualdad exacta de identidad y distancia entre mundos equivalentes.
- **Límites externos:**
  - 8 s por proceso de prueba, tanto ejecutable Rust como Godot;
  - 180 s por compilación (límite del builder de Codex).
- **Qué decide:**
  - Decide cada comprobación marcada **sí**.
  - **Informativo** se registra y no aprueba ni rechaza.
  - Si un instrumento no logra su condición previa (por ejemplo, no hay reposo antes del despertar), la prueba queda **no evaluable**. Lo anoto con la hora y no ajusto la fixture en silencio.
  - Un error de script o de compilación de mis instrumentos invalida solo ese caso. Se conserva el intento.

## 2. Parte P: base y reproducción del ensayo entregado

| Id | Qué | Decide |
| --- | --- | --- |
| P1 | `build_object_native.ps1 -Stage CoreTests` y `-Stage Extension` con `-CargoCachePath '..\implementacion\tmp\native_toolchain\cargo'` terminan con código 0, sin vencer. Se registran duración, SHA-256 y tamaño de la DLL | sí |
| P2 | ¿La DLL propia es igual por bytes a la de Codex (`6ac3c3cc…`)? | informativo |
| P3 | Las 9 pruebas Rust de Codex pasan. Su ejecutable termina en ≤ 8 s | sí |
| P4 | `run_object_native_probe.ps1 -Stages all`, sin cambios: 7 procesos con código 0, `PASSED`, sin vencer, sin errores de carga ni de script. `remaining_own_processes` = 0 | sí |
| P5 | Hechos de la reproducción: tick de contacto, bytes del checkpoint, tick aplicado de la suelta tardía, pasos repetidos y SHA del tick 140 | informativo |

P1 se corre antes de agregar mis pruebas Rust. Así, la primera compilación reproduce solo las de Codex.

## 3. Parte A: núcleo en Rust (`tests/claude_*.rs`)

Las corre mi runner propio (`run_claude_rust.ps1`), un ejecutable por vez con límite externo de 8 s. También quedan dentro de `CoreTests`.

### 3.1 Fixture propia F

Es distinta de la de Codex: otros tamaños, masas, giros y UID.

| Cuerpo | Uid | Tamaño (m) | Masa | Pose inicial |
| --- | --- | --- | --- | --- |
| Piso | 1 | 8 × 0,2 × 8 | fijo | (0, −0,1, 0) |
| A | 10 | 0,5 × 0,3 × 0,7 | 1,5 kg | (0,05, 0,15, −0,1), giro 0,3 rad en Y |
| B | 20 | 0,4 × 0,4 × 0,4 | 1 kg | (0,1, 0,9, 0,05), giro 0,35 rad sobre (1, 0, 1)/√2 |
| C | 30 | 0,3 × 0,3 × 0,3 | 0,5 kg | (−0,7, 0,15, 0,2) |

- **dt** = 1/60.
- **Regla K (checkpoint en contacto dinámico activo):** es el primer paso `s`, con 5 ≤ `s` ≤ 120, en que:
  - A y B se listan **mutuamente** como contacto;
  - los dos están despiertos;
  - su velocidad relativa |v_B − v_A| ≥ 0,05 m/s.
  - Si no existe ese paso, toda la parte A queda no evaluable.
- **Rama de referencia (H = 420 pasos desde el checkpoint):**
  - paso 30: impulso a A de (1,0, 0, 0,3);
  - paso 330: impulso a B de (0, 0, 0,6), el despertar;
  - después de cada paso se toman las muestras de todos los cuerpos.
- **Condiciones previas sobre la referencia:**
  - **V1:** algún paso entre 31 y 329 tiene A, B y C dormidos;
  - **V2:** en el paso 330, B está despierto.
  - Si falla V1 o V2, A3 queda no evaluable.

### 3.2 Contacto activo, reposo y despertar

| Id | Qué | Decide |
| --- | --- | --- |
| A1 | `restore_cached(cp)` en el mismo mundo: las muestras igualan a las del checkpoint, y la repetición de 420 pasos iguala a la referencia (≤ EPS, reposo y contactos iguales en todos los pasos) | sí |
| A2 | `snapshot()` en el tick del checkpoint, restaurado con `restore_trusted` en otros destinos dentro del proceso. Mismas exigencias que A1 en cada uno: **D1**, orden inverso (C, B, A, piso); **D2**, cuerpos 90 y 91 creados y retirados antes de sellar, y después C, A, piso, B (otra asignación interna); **D3**, D1 avanzado 50 pasos antes de importar (otra caché de contactos y del solver) | sí |
| A3 | Checkpoint dormido: snapshot en el primer paso de la referencia con A, B y C dormidos, importado en un destino con orden inverso. La repetición hasta 420 iguala a la referencia. B se despierta en el mismo paso (330) | sí |
| A4 | Control negativo: desde el checkpoint, impulso (1,0, 0, 0,31) en el paso 30 en lugar de (1,0, 0, 0,3). Debe separarse > 1e-3 de la referencia | sí (sensibilidad) |
| A5 | ¿Exacta por bits en A1 a A3? | informativo |
| A6 | SHA-256 de la referencia (bits de pose, velocidades, reposo y contactos). Se corre el mismo ejecutable dos veces, en dos procesos: los SHA deben ser iguales | sí |

### 3.3 Identidad con orden y asignación distintos

| Id | Qué | Decide |
| --- | --- | --- |
| B1 | Después de importar en D1, D2 y D3, `sample(key)` de cada clave iguala a la del origen. Una grilla de 9 rayos verticales y 3 horizontales devuelve la misma identidad y la misma distancia que en el origen, y "nada" donde el origen no toca nada | sí |
| B2 | Distancia de un rayo vertical sobre el piso, en un mundo con el piso solo: 3 − 0 = 3 m ≤ 1e-5. Distancia sobre la cara superior de C recién creada, sin pasos: 3 − 0,3 = 2,7 m ≤ 1e-5 | sí |
| B3 | Origen con (20, 3), después de crear y retirar (20, 1) y (20, 2) antes de sellar. Un destino con (20, 3) directo importa y repite igual. Un destino con (20, 1) es rechazado con `snapshot_identity` y queda sin cambios | sí |
| B4 | Después de importar, el mapa de retirados del destino es el del origen | informativo |

### 3.4 Aislamiento entre instancias, rayos y altas o bajas ajenas

- **Referencia R_I:** la isla I (fixture F) sola en el proceso, sin otros mundos creados, desde el tick 0 hasta cp + 420.
- **Ensayo:** se crean tres mundos:
  - I′, igual a I;
  - W2, con **los mismos UID** que F, sellado;
  - W3, sin sellar, con F más X (uid 100, cubo de 0,4 m y 1 kg en (2, 0,2, 0)).
- **Pasos intercalados:** cada paso de I′ va seguido de uno de W2 y uno de W3, también antes del checkpoint.
- **En cp:** caché en I′, 30 pasos más de los tres, y `restore_cached(cp)` en I′.

| Id | Qué | Decide |
| --- | --- | --- |
| C1 | Las muestras de W2 y W3 no cambian al restaurar I′ (igualdad de bytes de las muestras y del snapshot de W2) | sí |
| C2 | En W3, después de la restauración: se crea Y (uid 101, en (−2, 0,2, 0)); el rayo sobre X devuelve X; se libera Y; el rayo devuelve X otra vez; impulso (3, 0, 0) a X. En I′, un rayo en la posición de X no devuelve X | sí |
| C3 | Siguen 420 pasos intercalados. I′ iguala a R_I. W2 y W3 igualan a sus controles W2c y W3c, simulados solos con las mismas operaciones | sí |
| C4 | X avanza ≥ 0,1 m y está despierto después del impulso. Así se descarta una igualdad entre dos estados congelados | sí |
| C5 | Un mundo W4 creado **después** de la restauración (nuevo, mismos UID) iguala a su control W4c en 120 pasos | sí |

### 3.5 Controlador de mano dentro del checkpoint

- **Agarre de C:**
  - empieza en el tick 1, con ancla local (0,05, 0, 0);
  - objetivo inicial (−0,7, 0,5, 0,2);
  - del tick 2 al 60, el objetivo es (−0,7 + 0,01 n, 0,5 + 0,002 n, 0,2) con giro 0,02 n en Y.
- **Suelta** en el tick 61, con impulso (0,3, 0,2, 0).
- **Checkpoint** en el tick 25, con C agarrado y en movimiento.
- **Total:** 180 ticks.

| Id | Qué | Decide |
| --- | --- | --- |
| F1 | Repetición desde `restore_cached(25)`, y desde `restore_trusted` en un mundo con orden inverso, con los objetivos 26–60 y la suelta 61: iguala a la referencia en todos los ticks (≤ EPS, agarre igual) | sí |
| F2 | Control negativo: la misma repetición sin los objetivos 26–60 se separa > 1e-3 | sí (sensibilidad) |
| F3 | Recién restaurado en 25: `begin_hold(C)` es rechazado con `invalid_hold_transition` (el agarre viene en el checkpoint). Después de la suelta en 61, una segunda suelta es rechazada con `not_held` y no cambia nada | sí |
| F4 | Un checkpoint posterior a la suelta, importado en un mundo que todavía agarra C, deja `held = false`, y `set_goal` es rechazado con `not_held` | sí |

### 3.6 Rechazos atómicos

- **Método de gemelos:** el mundo T y el control K se construyen igual. La operación inválida se aplica solo a T.
- **Exigencias:**
  - devuelve el error esperado;
  - el snapshot de T es igual por bytes al de K (en un mundo sin sellar: muestras iguales y, después de sellar los dos, snapshot igual);
  - `cache_stats` es igual;
  - siguen 30 pasos idénticos.

| Id | Operación inválida → error esperado |
| --- | --- |
| D01 | `step` con dt 0, −1/60, NaN, +inf, el f32 siguiente a 1/30 y 0,1 → `invalid_dt`. Informativo: dt = 1/30 exacto se acepta |
| D02 | `add_box` después de sellar → `sealed_topology` |
| D03 | `add_box` con un uid en uso y otra aparición → `identity_in_use` |
| D04 | `add_box` de un uid retirado con la misma aparición, o con una menor → `retired_identity` |
| D05 | Tamaño 0, negativo, NaN o 1001 → `invalid_box`. Masa −1, 0,0005, 2e6 o NaN → `invalid_box`. Cuaternión no unitario, NaN o \|p\| > 1e6 → `invalid_pose` |
| D06 | Cuerpo 129 → `body_capacity`. El 128 se acepta |
| D07 | `remove` después de sellar → `sealed_topology`. `remove` de una identidad desconocida → `unknown_identity` |
| D08 | Retirados: se aceptan 512; el retiro 513 → `retired_capacity` y el cuerpo sigue |
| D09 | `seal(0)` → `invalid_context`. Sellar con otra revisión → `sealed_topology`. Informativo: volver a sellar con la misma |
| D10 | `begin_hold` sobre fijo o ya agarrado → `invalid_hold_transition`; sobre desconocido → `unknown_identity`; con ancla NaN o > 1000 → `invalid_anchor`; con objetivo inválido → `invalid_pose` |
| D11 | `set_goal` sin agarre → `not_held`. Objetivo inválido sobre un cuerpo agarrado → `invalid_pose`, y el objetivo anterior sigue |
| D12 | `release` sin agarre → `not_held`. Impulso NaN o 1e6 sobre un cuerpo agarrado → `invalid_impulse`, y sigue agarrado |
| D13 | `impulse` sobre fijo → `fixed_body`; sobre desconocido → `unknown_identity`; NaN, inf o 1e6 → `invalid_impulse` |
| D14 | Rayo con origen NaN, dirección nula, distancia 0, −1, NaN o 1e6 → `invalid_ray` |
| D15 | `restore_cached` de un tick nunca guardado → `checkpoint_expired` |
| D16 | `snapshot` sin sellar → `unsealed_topology` |
| D17 | `restore_trusted`. **Sobre:** vacío, 43 bytes, otra marca, largo declarado distinto, un byte de más, uno de menos, más de 1 MiB + 44 → `invalid_snapshot_envelope` o `snapshot_checksum`. **Suma:** un byte del payload o de la suma alterado → `snapshot_checksum`. **Decodificación:** payload basura con suma recalculada → `snapshot_decode`. **Modelo** alterado con suma recalculada, destino con contexto 2 o destino sin sellar → `snapshot_model_or_context`. **Manifiesto:** otro tamaño, otra masa u otra pose del piso → `snapshot_manifest`. **Topología:** un cuerpo menos o uno más → `snapshot_topology`. **Identidad:** igual cantidad con otro uid u otra aparición → `snapshot_identity`. Además de lo común, un rechazo **no** vacía la caché: el checkpoint guardado antes sigue restaurable |
| D18 | Barrido de mutaciones. **(a)** Un bit alterado por byte en todo el sobre y el payload, sin recalcular la suma: todos rechazados y sin cambios. **(b)** Un bit por byte del payload, con suma recalculada: decide que no haya pánico y que todo rechazo deje el destino sin cambios. Informativo: cuántas se aceptan, clasificadas por lo que cambian (pose del cuerpo fijo, dinámico, tick, nada visible) y por código de error. No se da un paso después de aceptar: un parámetro de integración alterado podría colgar el proceso |

### 3.7 Caché: límites, caducidad y descartes

| Id | Qué | Decide |
| --- | --- | --- |
| E1 | Guardar 135 ticks seguidos deja 120: los últimos 120. El más viejo devuelve `checkpoint_expired` y el mundo no cambia | sí |
| E2 | `cache_stats().bytes` es igual a la suma de los largos de los snapshots retenidos, calculada por mi cuenta, también después de guardar dos veces el mismo tick | sí |
| E3 | 128 cuerpos apilados en contacto: el snapshot funciona, y se registran su tamaño y su distancia al límite de 1 MiB. Con la regla de expulsión simulada por mi cuenta, cantidad y bytes retenidos coinciden y bytes ≤ 16 MiB. Si 120 × tamaño < 16 MiB, el límite de bytes queda **no ejercitado** | sí / no ejercitado |
| E4 | `restore_cached(t)` conserva los ≤ t y quita los > t: la cantidad y los bytes coinciden con mi cálculo, `t + 1` devuelve `checkpoint_expired` y `t` sigue restaurable | sí |
| E5 | Importar con `restore_trusted` deja la caché en (0, 0) y todo tick viejo devuelve `checkpoint_expired`. Una predicción nueva que vuelve a guardar los **mismos números de tick** restaura la rama nueva, no la vieja | sí |
| E6 | Un rechazo de `restore_trusted` o de `restore_cached` no toca la caché | sí |

## 4. Parte G: a través del enlace de Godot (`prototypes/objetos_nativo/validacion_claude/`)

Lo corre mi runner propio (`run_native_claude.ps1`): copia nueva del proyecto de Codex, mi DLL, AppData aislado y 8 s por proceso. Mis escenas terminan con código 0 si todo se evaluó, 2 si falló una comprobación y 3 si el instrumento no logró su condición previa.

### 4.1 Enlace, en un proceso (`cv_binding`)

| Id | Qué | Decide |
| --- | --- | --- |
| H1 | Clase registrada, Jolt seleccionado, sin `RapierPhysicsServer3D`. `get_build_info` informa lo documentado | sí |
| H2 | Jolt intacto **en movimiento**: un `RigidBody3D` de Jolt cae sobre un piso durante 90 cuadros físicos, mientras en esos cuadros se crean, avanzan, guardan y restauran mundos nativos. Su trayectoria iguala por bits a la de dos procesos de control sin trabajo nativo. Si los dos controles no son iguales entre sí, H2 queda no evaluable | sí |
| H3 | `Transform3D` con escala 1,001, cizalla, reflejo (det −1), NaN, inf o \|origen\| > 1e6 → `false` y `invalid_pose`, sin cambiar la cantidad de cuerpos | sí |
| H4 | uid −1, 0, 2³¹ o 2³², o aparición 0 → `invalid_identity`. Masa 1e-300, −1e-300, NaN, 2e6 o 0,0005, o tamaño (0, 1, 1) → `invalid_box` | sí |
| H5 | `get_last_error` vacío después de un éxito. Un rayo que no toca nada devuelve `{}` y error vacío; un rayo inválido devuelve `{}` y `invalid_ray`. `restore_cached(−1)` → `invalid_tick` | sí |
| H6 | El diccionario de muestra trae las claves documentadas. La pose devuelta después de `add_box` y antes de un paso iguala a la dada (≤ 1e-6) y su base es ortonormal (≤ 1e-6) | sí |
| H7 | Por el enlace: checkpoint con la regla K, importación en orden inverso, repetición de 200 pasos igual (bytes de `var_to_bytes` de las muestras), aislamiento con los mismos UID y pasos intercalados, rayos con alta y baja ajenas | sí |
| H8 | `restore_trusted` con datos truncados, vacíos o de otro manifiesto → `false`; snapshot y caché sin cambios. Una segunda suelta → `false` con `not_held` | sí |

### 4.2 Intercambio entre procesos por archivo (`cv_exchange`)

**Exportación:** fixture F, checkpoint con la regla K. Se escriben el snapshot, las muestras iniciales, la historia de 420 pasos y los resultados de los rayos.

**Importación**, en otro proceso. Antes de importar se preparan:
- 64 objetos de Godot creados para correr los InstanceID;
- un mundo "vecino" vivo con los mismos UID, que avanza antes y después;
- un destino con orden C, piso, B, A y los uid 90 y 91 creados y retirados, avanzado 40 pasos.

| Id | Qué | Decide |
| --- | --- | --- |
| X1 | El archivo leído tiene el mismo SHA-256 que el escrito | sí |
| X2 | Después de importar: muestras iniciales iguales, rayos iguales y 420 pasos de repetición iguales (bytes) | sí |
| X3 | El vecino iguala a su control, en el mismo proceso, antes y después de la importación | sí |
| X4 | Un destino con el tamaño de A cambiado (0,51) rechaza el archivo y queda sin cambios | sí |

## 5. Parte L: suelta tardía por ENet

Se distinguen dos cosas:
- **lo que se valida:** el núcleo restaura el estado de la autoridad y repite hasta el presente;
- **lo que es instrumentación de construcción:** el driver preacordado de Codex (objetivos por tick, ventaja de 4 pasos, envío demorado a 74 y espera de 2 pasos).

No se valida el input real del actor, `SimClock`, el reloj del juego ni la presentación. El runtime del juego no usa el núcleo nativo, y **no se instrumenta**.

### 5.1 Observador

`cv_late_observer.gd` hace `extends "res://late_action.gd"` y **no cambia** su protocolo:
- no se tocan `_release_intent`, `_authority_checkpoint`, `try_reconcile`, `host_step` ni `client_step`;
- `host_step` y `client_step` se sobrescriben solo para llamar al original y anotar después;
- envuelve el mundo en un registrador que reenvía cada llamada sin cambiarla. Anota cada operación y, después de cada paso, el estado (SHA de `var_to_bytes(samples())` y los números de cada cuerpo), con la rama: cada `restore_trusted` exitoso abre una.

Dos variantes:
- **`codex`:** la fixture y el cronograma de Codex sin cambios.
- **`push`:** mi fixture, con el mismo protocolo.
  - A (uid 2, 0,6 × 0,4 × 0,4 m, 2 kg) agarrado empuja a B (uid 3, cubo de 0,4 m, 1 kg) sobre el piso. El objetivo de A avanza 0,012 m por tick en x, a 0,25 m de altura, mientras A esté agarrado.
  - La predicción suelta en 46; el host suelta cuando llega el pedido.
  - C (uid 4, cubo de 0,3 m, 0,5 kg) queda agarrado hasta el tick 140, con un objetivo que cambia en cada tick. Así la repetición tiene que volver a aplicar entradas.

Al terminar, el host construye **mi propia referencia**:
- es un mundo nuevo con el cronograma reescrito por mí y la suelta aplicada **una sola vez**, en el tick que el host realmente aplicó (T);
- hay dos controles negativos: la suelta en 46, y la suelta en T más un impulso igual en el tick en que llegó el duplicado.

### 5.2 Comprobaciones

| Id | Qué | Decide |
| --- | --- | --- |
| L1 | Los dos procesos de cada variante terminan con código 0 dentro de 8 s, sin errores de script, y los chequeos propios de `late_action.gd` dan `PASSED` | sí |
| L2 | **Mismo tick:** para cada tick t entre T y 140, el estado del invitado en su rama final (el restaurado en T, cada paso repetido y cada paso posterior) es igual por SHA al del host en t | sí |
| L3 | **Un solo impulso físico:** el host hace exactamente una `release_body` exitosa y ninguna `apply_impulse`. Su historia, en los 140 ticks, iguala por SHA a mi referencia con una suelta en T. Los dos controles negativos se separan > 1e-3 al tick 140 | sí |
| L4 | **Duplicado:** el host recibe ≥ 1 pedido repetido sin una segunda suelta. El invitado recibe la confirmación repetida y no restaura otra vez: hay exactamente 2 `restore_trusted` exitosos, el inicial y la corrección | sí |
| L5 | **Vecinos dinámicos, variante `push`:** **(a)** antes de la corrección, B del invitado se separa > 1e-3 m del B del host en el mismo tick, porque la suelta tardía afecta al vecino; **(b)** después, B queda igual en todos los ticks; **(c)** en la ventana repetida, B está despierto, con \|v\| ≥ 0,05 m/s y en contacto con A en algún paso; si no, (c) queda no ejercitado; **(d)** C sigue agarrado y es igual; un control que repite sin los objetivos de C se separa > 1e-3 | sí (c: sí / no ejercitado) |
| L6 | Variante `codex`: estado de B en la ventana repetida y su separación antes de la corrección | informativo |
| L7 | Ticks reales: llegada del pedido, T, presente P en la corrección, pasos repetidos, llegada del duplicado y salto de cada cuerpo en la corrección (antes y después en P) | informativo |

## 6. Orden

1. Este documento, al historial.
2. P1 a P4 con los scripts de Codex, antes de agregar mis pruebas Rust.
3. Instrumentos A a F, G y L, y su revisión de compilación.
4. Runner Rust, runner Godot y comparadores.
5. Informe `entrega_8.md`.

## 7. Fuera de alcance

- La matriz de Jolt.
- Integración al laboratorio, inventario y catálogo real.
- Formas convexas o propias, centros de masa desplazados, apoyos móviles y topología variable.
- Dos PC o CPU distintas.
- Latencia y pérdida reales.
- Rendimiento y presupuesto.

Ningún resultado de esta verificación aprueba la migración ni el modelo completo.
