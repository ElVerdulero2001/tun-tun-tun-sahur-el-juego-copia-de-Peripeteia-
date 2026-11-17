# Verificación independiente de la entrega 8: núcleo nativo de objetos

2026-11-16. Claude. Base: `aeee009`, entrega 8.

**Orden de los commits:**
- Criterios en `criterios_entrega_8.md` (`c36eb5b`, 22:40). Se escribieron antes de compilar, reproducir o correr nada.
- Instrumentos Rust en `7812932` (22:49), antes de correrlos.
- Instrumentos Godot y diagnóstico D18 en `4b607bd` (22:57), antes de correrlos.

## Dictamen

**Las tres primeras condiciones de la puerta de aceptación del contrato se cumplen en esta PC, con instrumentos propios, y con igualdad exacta por bits en todos los casos:**
1. Checkpoint en contacto activo, en reposo y al despertar.
2. Dos mundos vivos, con restauración de uno y altas, bajas y rayos en el otro.
3. Importación con otro orden de creación, otra asignación interna y otro proceso, con rechazo atómico de los incompatibles.

Las fallas de `StateManager3D` que encontré en la entrega 5 (R3/R4) no aparecen en las versiones adaptadas a esta API:
- **Aislamiento:** restaurar una instancia no cambia otra.
- **Identidad:** los rayos devuelven el cuerpo correcto, el cuerpo empujado avanza y nada se congela.
- **Importación:** no adopta identidades ajenas.

**La suelta tardía por ENet se valida en el mismo tick**, tanto con la fixture de Codex como con una variante mía, en la que el vecino dinámico está siendo empujado y una segunda mano sigue activa durante la repetición:
- del tick aplicado (72) al 140, host e invitado tienen el mismo SHA en cada tick;
- hay una sola suelta física;
- el duplicado no produce ni una segunda suelta ni una segunda restauración.

Esto vale para un **cronograma preacordado**. No es el input, el reloj ni la presentación del juego, y la condición 4 del contrato ("controlador real") sigue abierta.

**Un defecto demostrado, fuera del uso declarado:**
- con un snapshot alterado y su suma recalculada, 22 mutaciones de un bit pasan la validación y después `sample()` entra en pánico dentro de Rapier;
- otras 25 aceptan un piso movido aunque el manifiesto coincida.

Hacen falta datos que no vengan de un host correcto, así que no invalida el uso `trusted`. Pero confirma, con un caso concreto, que `restore_trusted` no puede ser la frontera de la red.

**Una observación de capacidad:** con 128 cuerpos apilados, el snapshot pesa 614 KB y la caché de 16 MiB guarda **27** checkpoints, no 120.

No se aprueba integración, migración, inventario, catálogo, dos PC ni rendimiento. `model_approved` sigue en `false`.

## Base, compilación y comandos

- **Copia:**
  - Solo `tmp/` estaba sin versionar.
  - `git fetch --no-tags ..\implementacion objetos/implementacion` y `git merge --ff-only FETCH_HEAD`: avance de `637fa91` a `aeee009` sin conflictos.
  - Los 23 archivos de `..\entrega_8.json` coinciden en SHA-256, crudo y normalizado a LF.
  - Mis instrumentos y mis informes anteriores llegaron sin cambios.
- **Compilación:** con el builder de Codex sin cambios, `-CargoCachePath '..\implementacion\tmp\native_toolchain\cargo'`. No hizo falta `-ToolchainBin`.
  - `CoreTests`: 68,7 s.
  - `Extension`: 37,6 s.
  - Evidencias en `tmp/native_build/20261117_014027_CoreTests_76fb12` y `…_014142_Extension_78f64a`.
- **DLL propia:** 5.698.048 bytes, SHA-256 `bf20eb2a…79a4`.
  - No es igual por bytes a la de Codex (`6ac3c3cc…5bca`, mismo tamaño).
  - Calcula lo mismo: el artefacto de intercambio de Codex sale idéntico, `3fde86a0…6967`, 371.712 bytes.
- **Motor:** `C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe`, sin `--fixed-fps`, con Jolt seleccionado.
- **Mis runners, todos con límite externo de 8 s por proceso:**
  - `prototypes/objetos_nativo/validacion_claude/run_claude_rust.ps1`: compila con el mismo entorno que el builder y corre cada ejecutable `claude_*`.
  - `run_native_claude.ps1`: copia nueva del proyecto de Codex, mi DLL y AppData aislado.
  - Los resúmenes salen de `cv_rust_report.mjs` y `cv_native_compare.mjs`.
- **Corridas:**
  - **Reproducción de Codex:** `tmp/native_probe/20261117_014225_8871a7`. El proceso más largo tardó 2,76 s.
  - **Rust propias:** `tmp/validacion_objetos/entrega_8/rust_20261116_225003`. 6 procesos; el más largo, 0,61 s.
  - **Diagnóstico D18:** `…/diag_d18_20261116_225113`.
  - **Godot propias:** `…/godot_20261116_225743`. 9 procesos; el más largo, 2,85 s.
- **Cierre:** ningún proceso venció y no quedó ningún Godot abierto. Las trazas (13,5 MB entre las dos carpetas) no se commitean.

## Resultado por prueba

| Parte | Resultado |
| --- | --- |
| P1 compilación (builder de Codex) | Pasa: dos etapas con código 0 |
| P3 pruebas Rust de Codex | 9 pasan, en 0,15 s |
| P4 siete procesos de Codex | 7 con código 0 y `PASSED`, sin errores; `remaining_own_processes` 0 |
| A, B, C, E, F (Rust propias) | Todas pasan; B4 no evaluable |
| D01–D17 rechazos | Todos pasan |
| D18 barrido | (a) pasa; (b) **falla**: 22 pánicos al muestrear estados aceptados |
| H1–H8 enlace | 46 pasan |
| X1–X4 archivo entre procesos | Pasan |
| L1–L5 suelta tardía | Pasan en las dos variantes; L5c ejercitado |

En números:
- **Rust:** 134 pasan, 1 falla (D18b), 23 informativas y 1 no evaluable.
- **Godot:** 79 pasan, 0 fallan y 4 informativas.

## Por punto del encargo

### 1. Actualización

Hecha por avance directo, conservando pruebas y trazas. Los hashes se detallan en "Base".

### 3. Compilación en mi copia

Con la caché compartida no se descargó nada. Los resultados quedaron en `tmp/native_target` y `tmp/native_build` de mi copia.

### 4. Comprobaciones independientes del núcleo

**Contacto activo (A1, A2):**
- Fixture F propia, con otros tamaños, masas, giros y UID que la de Codex.
- Checkpoint en el tick 16, con B cayendo sobre A: velocidad relativa 1,35 m/s, contacto mutuo y los dos despiertos. Pesa 8.103 bytes.
- Repetición de 420 pasos, **exacta por bits**, en cuatro casos:
  - en el mismo mundo (`restore_cached`);
  - en un destino con orden inverso;
  - en uno que creó y retiró los uid 90 y 91 antes de cargar en otro orden;
  - en uno con orden inverso avanzado 50 pasos, con otra caché de contactos y otro estado del solver.
- Rapier no serializa sus espacios de trabajo (`physics_pipeline`, `collision_pipeline`, `ccd_solver`). Restaurar con esos espacios nuevos no cambió nada.

**Reposo y despertar (A3):**
- Todos los dinámicos duermen en el paso 70.
- Un snapshot dormido, importado en orden inverso, repite exacto hasta el 420.
- B duerme en el 329 y despierta en el 330, igual que en la referencia.

**Sensibilidad y procesos (A4, A6):**
- El control negativo (impulso 0,31 en lugar de 0,3) se separa 4,4e-3 m/s.
- El SHA de la referencia es igual en dos procesos: `b4a53687…7668`.

**Identidad (B1–B3):**
- En los tres destinos, 12 rayos devuelven la misma identidad y la misma distancia, por bits, que el origen (11 aciertos y 1 vacío).
- Distancias contra la geometría: 3,0 m sobre el piso y 2,6999998 m sobre C recién creada, sin pasos.
- **Apariciones:** un origen con (20, 3), con dos apariciones retiradas antes, importa igual en un destino sin esa historia. Un destino con (20, 1) se rechaza con `snapshot_identity`, sin cambios.
- **B4, no evaluable:** el mapa de retirados no se ve por la API una vez sellada la topología.

**Aislamiento entre instancias (C1–C5, H7):**
- Hay tres mundos intercalados paso a paso, y W2 tiene **los mismos UID** que la isla. Restaurar la isla no cambia ni las muestras ni el snapshot de los otros.
- En W3, después de esa restauración, se crea Y. El rayo sobre X devuelve X; se libera Y, y el rayo vuelve a devolver X. En la isla, el mismo rayo da su propio piso a 3 m.
- X avanza 0,56 m, despierto desde el primer paso.
- En 420 pasos, la isla, W2, W3 y un mundo creado después igualan, por bits, a sus controles simulados solos.
- Por el enlace de Godot (H7) da lo mismo.

**Controlador dentro del checkpoint (F1–F4):**
- Agarre de C con ancla desplazada, objetivos que se mueven y giran, y checkpoint en el tick 25, en pleno movimiento.
- La repetición con los objetivos 26–60 y la suelta en 61 es exacta, en el mismo mundo y en orden inverso.
- Sin esos objetivos se separa 0,43 m.
- **Después de restaurar:** volver a agarrar C da `invalid_hold_transition` (el agarre viene en el checkpoint), y una segunda suelta da `not_held`.
- Importar un checkpoint posterior a la suelta en un mundo que todavía agarra deja `held = false`.

**Rechazos atómicos (D01–D17):**
- Método de gemelos: snapshot, caché y 30 pasos idénticos a un control sin la operación inválida.
- Pasan todos los casos de `step`, alta, baja, sellado, agarre, objetivo, suelta, impulso, rayo y caché, cada uno con el código esperado.
- Pasan también 24 casos de `restore_trusted`, entre sobres, sumas, decodificación, modelo, contexto, manifiesto, topología e identidad.
- Un rechazo de `restore_trusted` no vacía la caché: el checkpoint anterior sigue restaurable.
- Los límites se cumplen en el borde: el cuerpo 128 entra y el 129 no; 512 retirados entran y el 513 no.

**Barrido de mutaciones (D18):**
- **(a) Sin recalcular la suma:** las 8.099 mutaciones se rechazan (8 por el sobre y 8.091 por la suma), sin cambios.
- **(b) Con la suma recalculada:** de 8.055 mutaciones,
  - 2.569 se rechazan sin cambios, la mayoría por decodificación (1.976);
  - 5.464 se aceptan;
  - **22 se aceptan y después hacen fallar `samples()`.**
- **Los 22 pánicos, según el diagnóstico:** todos son `index out of bounds` en `rapier3d-0.36.0/src/geometry/interaction_graph.rs:166`. Vienen de índices del grafo de contactos, en los bytes 1925–1932, 2771–2778 y 3674–3680 del payload.
- **25 aceptadas cambian la pose del piso fijo,** en los bytes 4989–5016. Por ejemplo, su altura pasa de −0,1 a −2,3e-11, o sea, el piso sube 10 cm, mientras `fixed_pose` del manifiesto sigue igual. El mundo avanza sin error.
- **5.167 aceptadas no cambian nada visible** en las muestras: son datos internos que el validador no revisa.

**Caché, caducidad y descartes (E1–E6):**
- Guardar 135 ticks deja exactamente los últimos 120. El más viejo devuelve `checkpoint_expired`, sin cambios.
- Los bytes de la caché coinciden con mi suma, también después de guardar dos veces el mismo tick.
- `restore_cached(100)` deja 85 entradas (16–100); el 101 queda vencido y el 100 sigue restaurable.
- Importar autoridad deja (0, 0). Una rama nueva que vuelve a guardar el tick 103 restaura la rama nueva, que es distinta de la vieja.
- **E3, con 128 cuerpos y 490 contactos listados:**
  - el snapshot pesa 614.284 bytes, el 59 % del límite de 1 MiB;
  - la expulsión por bytes deja **27** entradas (16.585.668 bytes);
  - coincide con mi simulación de la regla.

**Enlace de Godot (H1–H8):**
- Clase registrada, Jolt seleccionado, sin `RapierPhysicsServer3D`, y `get_build_info` como dice el README.
- **H2:** un cuerpo de Jolt que cae 1,64 m, mientras en los mismos cuadros se crean, avanzan, guardan y restauran mundos nativos, sigue **por bits** la trayectoria de dos procesos de control, que también son iguales entre sí.
- Se rechazan escala, cizalla, reflejo, NaN, inf y origen enorme, tanto en altas como en objetivos.
- Se rechazan identidades y masas fuera de rango.
- Los errores se informan bien y el diccionario trae las claves documentadas. La pose devuelta iguala a la dada (base ≤ 6,7e-8).

**Archivo entre procesos (X1–X4):**
- El artefacto de 593.456 bytes llega íntegro.
- **Antes de importar,** el proceso que importa:
  - crea 64 nodos de Godot para correr los InstanceID;
  - tiene un vecino vivo con los mismos UID;
  - usa un destino que retiró los uid 90 y 91, cargó en otro orden y avanzó 40 pasos.
- Las muestras iniciales, los rayos y 420 pasos son iguales por bytes.
- El vecino iguala a su control.
- Un destino con A de 0,51 m rechaza el archivo sin cambios.

### 5. Suelta tardía por ENet

**Cómo se observó:**
- `cv_late_observer.gd` hereda de `late_action.gd` sin tocar su protocolo.
- Envuelve el mundo en un registrador que anota cada operación y cada estado.
- Después de la corrida, construye en el host **mi propia referencia**: reescribí el cronograma y apliqué la suelta una sola vez, en el tick que el host realmente aplicó.

| | Codex | Push (mía) |
| --- | --- | --- |
| Pedido visto por el host antes del paso / suelta aplicada (T) | 72 / 72 | 72 / 72 |
| Presente del invitado al corregir (P) y pasos repetidos | 75, 3 | 75, 3 |
| L2: ticks T..140 con igual SHA | 69 de 69 | 69 de 69 |
| L3: sueltas en el host, impulsos extra | 1, 0 | 1, 0 |
| L3: host igual a mi referencia, 140 ticks | sí | sí |
| L3: control "suelta en 46" / "doble impulso" al tick 140 | 0,106 / 0,039 | 0,312 / 0,023 |
| L4: pedido repetido visto en el host / suelta extra / restauraciones del invitado | 92 / no / 2 | 92 / no / 2 |
| Salto de A y B en la corrección | 0,351 m / 0,011 m | 0,268 m / 0,246 m |

**Vecinos dinámicos:**
- **Variante push (L5):**
  - antes de corregir, B del invitado está a 0,246 m del B del host: la suelta tardía cambió el empuje;
  - después, B es igual en todos los ticks;
  - en los tres pasos repetidos, B está despierto, a 0,83–0,94 m/s y en contacto con A y con el piso;
  - C, agarrado con un objetivo que cambia en cada tick, sigue agarrado e igual;
  - el control que repite sin los objetivos de C se separa 0,91 m, así que **la repetición vuelve a aplicar esas entradas**.
- **Variante de Codex (L6):** también hay contacto con A durante la repetición, con B a 0,11–0,13 m/s, y la separación de B antes de corregir es de 1,1 cm.

**Qué distinguir:**
- En los dos casos, el invitado **no vuelve a simular la suelta**. Restaura el estado del host tomado *después* de aplicarla y avanza 3 pasos.
- Volver a aplicar entradas en la repetición queda probado con C (push) y con F1 en Rust.
- El reloj es la planificación real de dos procesos. T fue 72 en mis tres corridas (la del runner de Codex y las dos del observador); Codex obtuvo 73 y 71. Por eso el SHA del tick 140 cambia entre corridas (`ffdd…` acá, `be29…` en Codex), pero coincide entre host e invitado dentro de cada una.
- Con el mismo T, la variante de Codex da el mismo SHA del tick 140 con el observador y sin él (`ffdda0f4…5bfd`). El registrador no altera la física.
- La ventaja de 4 pasos, el envío en 74 y la espera de 2 pasos son del driver de Codex, no reglas del juego.

**Datos que faltan para validar esto contra el juego.** No los fabriqué instrumentando el runtime:
1. Una grabación por tick de las acciones reales de agarre, objetivo y suelta del actor, tal como entrarían al adaptador.
2. La política de `SimClock`: ventaja del invitado, en qué tick aplica el host una acción vieja y hasta cuántos ticks hacia atrás.
3. Cómo se presenta una corrección como la medida: 35 cm de A en la fixture de Codex.
4. Cómo viajan snapshots de 6 a 614 KB con latencia y pérdida reales.

Nada de eso existe todavía. El adaptador es el paso siguiente de Codex.

### 6. Límites del encargo

- Cada proceso tuvo un límite externo de 8 s.
- No repetí Jolt, `StateManager3D` ni mis R3/R4 viejos, que siguen siendo antecedentes válidos.
- No declaro aprobadas la migración ni el rendimiento.

## Errores propios

1. **El resumen de Rust perdía la primera comprobación de cada prueba,** porque libtest escribe `test nombre ... ` en la misma línea. Lo corregí en `cv_rust_report.mjs` y volví a leer los mismos registros, sin correr de nuevo.
   - Pasó de 126/1/20/1 a 134/1/23/1 (pasan / fallan / informativas / no evaluables).
   - No cambió ningún veredicto.
2. **`run_claude_rust.ps1` exigía exactamente 5 ejecutables.** Al agregar el diagnóstico excluí `claude_diag_*`. Fue después de la corrida, y no la afecta.
3. **`cv_exchange.gd` tenía un error de tipos.** Lo detectó `--check-only` antes de correr.
4. **En H4,** los rótulos de las masas 1e-300 y −1e-300 salen como `0.0` y `-0.0`, por cómo GDScript convierte a texto. Los casos son los correctos.

## Para Codex

1. **D18b (defecto, fuera del uso `trusted`):**
   - `validate_candidate` no revisa el grafo de contactos del `NarrowPhase`.
   - Con la fixture F en el tick 19, un bit alterado en los bytes 1925–1932, 2771–2778 o 3674–3680 del payload, con la suma recalculada, se acepta, y `sample` entra en pánico en `interaction_graph.rs:166`.
   - Lo reproducen `tests/claude_mutations.rs` y `tests/claude_diag_d18.rs`.
   - No probé qué hace ese pánico a través del enlace de Godot.
2. **Pose real de los cuerpos fijos:** el validador compara `fixed_pose` del manifiesto, pero no la pose del cuerpo en el mundo restaurado (bytes 4989–5016). Importa cuando el contexto estático venga de la geometría preparada del nivel.
3. **`claude_mutations` termina con código 101 por D18b.** Si incorporás mis pruebas, `build_object_native.ps1 -Stage CoreTests` se detiene en el primer ejecutable que falla. Los siguientes no corren en esa invocación. `run_claude_rust.ps1` los corre todos por separado.
4. **E3:** a capacidad completa, la historia local es de 27 ticks (0,45 s a 60 Hz) y cada snapshot pesa 614 KB. El límite de "120 checkpoints" solo se alcanza en escenas chicas.
5. **El caso tardío por ENet** prueba restaurar el estado ya aplicado por la autoridad y adelantar hasta el presente. No prueba volver a simular la acción del invitado desde antes de aplicarla.

## Bloqueado y límites

- Una sola PC y un solo binario por lado. Lo exacto entre procesos no vale para dos PC ni para otra CPU.
- Datos de snapshot confiables, topología fija y cajas centradas.
- Sin catálogo, formas convexas, centros de masa desplazados, apoyos móviles ni inventario.
- Sin input real, `SimClock`, cámara lenta ni presentación.
- Sin latencia ni pérdida reales.
- Tiempos de perfil dev con optimización 1: no son medidas de rendimiento.
