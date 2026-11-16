# Criterios fijados antes de ejecutar: verificación de las entregas 4 y 5

2026-11-16. Validación independiente de Claude sobre `dcd5fce` (entrega 5), que incluye la entrega 4 (`3fadd23`). Encargos: "Encargo acotado para Claude" de `docs/net/entregas/revision_codex_entrega_3.md` (parte A) y "Siguiente verificación independiente de Claude" de `docs/net/entregas/ensayo_rollback_rapier_entrega_5.md` (parte B).

Estos criterios se escriben y se guardan en el historial **antes** de correr cualquier prueba nueva. Los instrumentos ya pasaron solo la revisión de sintaxis (`--check-only`, `node --check`), sin producir resultados.

## 1. Qué no cambia

- **Tolerancias anteriores:**
  - 2 mm y 0,3° entre host e invitado.
  - Igualdad de objetivo de mano ≤ 1e-6 m.
  - Ida y vuelta de una rotación por el paquete ≤ 1e-6 rad (`criterios_entrega_3.md` §2).
- **Rapier:** se usa el `EPS = 0,00001` de Codex, sin aflojarlo. Se aplica a posición (m), a cada eje de la base (sin unidad) y a las velocidades lineal (m/s) y angular (rad/s). El reposo (`sleeping`) y la lista de contactos informados deben ser **iguales**. Además se informa si la igualdad es exacta, sin que eso decida.
- **Límites externos:**
  - 20 s por caso de red y por prueba sin red con Jolt.
  - **8 s por proceso con Rapier.**
- **No se modifica:** `runtime/`, `main.gd`, `project.godot`, `probe.gd`, `exchange_probe.gd` ni `prepare_rapier_probe.ps1`. Tampoco se instala Rapier en el juego.
- **Trazas:** en `tmp/validacion_objetos/entrega_5/`, sin commitear. Un intento con error del instrumento se conserva como `*.intento1_error_del_instrumento.*` y no cuenta.
- **Qué decide:** decide una comprobación marcada "sí". "Informativo" se registra y no aprueba ni rechaza. Si un instrumento no logra su condición previa (código 3 en Rapier), la prueba queda **no evaluable**: no es aprobada ni fallada.

## 2. Parte A: entrega 4 (N3 y L19)

### 2.1 Lectura del código antes de probar

- `rotate_goal` → `HandRotation.rotate_mouse`. Compone un cuaternión, lo normaliza en cada evento y escribe `target.basis`.
- `set_goal` y `request_grab` pasan por `rotation_only_target`: rechazan lo no finito o con determinante ≤ 1e-6 y ortonormalizan lo demás.
- La red sigue estricta: `valid_target` es común a `HandInput.valid` y a `Authority.valid_command`.
- `hand_input_encode_failed` se registra solo en el invitado, en cada tick en que `encode` devuelve vacío.
- **Por código:** un objetivo inválido dentro de la historia de 6 bloquea el paquete entero durante 6 ticks. D4 mide ese costo.
- `grab_rotate` (entrega 3) aplica la fórmula vieja en el driver y llama a `set_goal`. Ahora `set_goal` canoniza, así que **ya no prueba el productor real**: queda como regresión. El productor real lo prueba el caso nuevo `grab_rotate_real`.

### 2.2 Instrumentos nuevos o cambiados

- `validation/hand_rotation_test.gd` (nuevo): `main.tscn` en modo solo, con `--trace`.
- `validation/hand_timeline_seen_test.gd` (nuevo): prueba pura.
- `validation/driver.gd`: operaciones nuevas `rotate_real`, `force_raw_target` y `goal_keep`; casos nuevos `grab_rotate_real` y `grab_bad_target`. Lo anterior no cambia.
- `validation/analyze.mjs`: bloque "entrega 4" agregado al final. Los bloques anteriores no cambian.

### 2.3 Productor del giro (`hand_rotation_test.gd`)

| Id | Qué | Decide |
| --- | --- | --- |
| P00 | `main` en modo solo, listo y sin caja agarrada | sí (validez) |
| P01 | 20.001 eventos de `main.rotate_goal`, con los deltas de I16 y el eje x de la cámara. En cada evento: aceptado, `valid_target`, `HandInput.valid`, `encode` de 48 bytes que `decode` devuelve, e ida y vuelta ≤ 1e-6 rad | sí |
| P02 | `HandRotation` sola, 200.000 eventos, siempre `valid_target`. Motivo: un agarre puede durar minutos | sí |
| P03 | Deriva contra un cuaternión en doble precisión con la misma composición | informativo |
| P04 | Control negativo: la fórmula vieja deja de ser codificable antes del evento 20.000 | sí (validez) |

### 2.4 Canonización y rechazos (`hand_rotation_test.gd`)

Un objetivo **aceptado** debe:
- pasar `valid_target` y `HandInput.valid`;
- conservar el origen exacto;
- quedar a ≤ 1e-6 rad de la rotación esperada, si la hay.

Un objetivo **rechazado** debe:
- devolver `false`;
- dejar `main.target` sin cambios.

| Id | Caso | Esperado | Decide |
| --- | --- | --- | --- |
| C01 | Rotación pura | aceptado, = R | sí |
| C02 | R con escala uniforme 2 | aceptado, = R | sí |
| C03 | R con escala por eje 1, 2, 3 (columnas) | aceptado, = R | sí |
| C04 | Cizalla | aceptado y válido | sí |
| C05 | Reflejo (det −1) | rechazado | sí |
| C06 | Base singular | rechazado | sí |
| C07a/b/c | NaN en el origen; infinito o NaN en la base | rechazado | sí |
| C08a | Escala 1e13 (el determinante desborda float32) | rechazado | sí |
| C08b | Escala 1e12 | aceptado, = R | sí |
| C09a | Escala 0,02 | aceptado, = R | sí |
| C09b | Escala 0,005 (det 1,25e-7) | se informa | informativo |
| C10 | Casi singular, det 2e-3 | aceptado y válido | sí |
| C11 | `rotate_goal` con NaN, infinito o eje cero | `false`, objetivo conservado | sí |
| C12 | `rotate_goal` con delta 1e30 | aceptado y válido | sí |
| C13 | Asignar a `_goal_rotation` una base singular | orientación conservada | sí |
| C14 | Exactamente un aviso por rechazo en la traza: `invalid_local_target` / `invalid_local_rotation` | igual a lo esperado | sí |
| G01 | `request_grab` con reflejo | no cambia `next_action`, ni el pendiente, ni la cola | sí |
| G02 | `request_grab` con punto NaN | se informa si avisa | informativo |
| G03 | `request_grab` con escala 2 | encolado, objetivo canónico = R, origen exacto | sí |

### 2.5 Coherencia de validadores (`hand_rotation_test.gd`)

| Id | Qué | Decide |
| --- | --- | --- |
| V01 | Unos 450 objetivos: rotaciones; escalas 0,99 a 1,02; cizallas de 1e-6 a 1e-3; reflejos; NaN; la fórmula vieja en los eventos 1, 501, 1263, 1264, 1301, 5001 y 20.000. `valid_target`, `HandInput.valid` y `Authority.valid_command` dan el mismo resultado | sí |
| V02 | Todo lo que `set_goal` acepta pasa los tres. Lo que rechaza deja el objetivo igual | sí |
| V03 | Qué dice el receptor de la fórmula vieja: debe seguir estricto, sin canonizar | informativo |

### 2.6 En red (`run_case.ps1`, perfil `clean`)

**`grab_rotate_real`:**
- Agarre.
- 120 ticks con 170 eventos de `rotate_goal` cada uno: 20.400 eventos. La cantidad por tick no cambia la propiedad, porque cada evento normaliza; pasa el mínimo pedido de 20.001 dentro de los 20 s.
- Espera de 30, suelta, espera de 60.

| Id | Qué | Decide |
| --- | --- | --- |
| P5 | ≥ 20.001 eventos; todos los ticks aceptados, válidos y codificables | sí |
| P6 | 0 `hand_input_encode_failed` | sí |
| P7 | Host durante el agarre: 0 pasos con respaldo y pose host/invitado ≤ 2 mm / 0,3° | sí en `clean` |
| P8 | 0 `invalid_local_*` en host e invitado | sí |

También deciden los criterios anteriores del verificador que se apliquen a este caso: E0, N2a, N2b, H1, HI1 y HL.

**`grab_bad_target`:**
- Agarre y 30 ticks.
- Un tick con `main.target` asignado directamente, sin pasar por `set_goal`, con escala local (1, 1, 1,5) y determinante 1,5. Es la única forma de provocar una codificación imposible.
- Luego `set_goal` con el objetivo anterior, 30 ticks, suelta y 60 ticks.

| Id | Qué | Decide |
| --- | --- | --- |
| D1 | El primer `hand_input_encode_failed` sale en el tick forzado | sí |
| D2 | El host no recibe ninguna entrada de ese tick | sí |
| D3 | A lo sumo 6 avisos, todos dentro de los 6 ticks de la ventana, y el host vuelve a recibir entradas después | sí |
| D4 | Costo en la ventana: cuándo llegan los ticks forzado+1 a +5 y los pasos del host con respaldo | informativo |
| P8 | Sin `invalid_local_*` | sí |

**`grab_rotate`:** se repite una vez en `clean` como regresión, con sus criterios de la entrega 3 y P8.

### 2.7 Registro `seen` (`hand_timeline_seen_test.gd`)

| Id | Qué | Decide |
| --- | --- | --- |
| S01 | Se consume el tick 100 y se reenvía igual en cada "ahora" de 101 a 300. Solo puede salir `duplicate` u `outside_window`, nunca `buffered`, y `consume` nunca lo vuelve a dar | sí |
| S02 | Lo mismo con otro objetivo: solo `conflicting_tick` u `outside_window`; nunca reutilizado | sí |
| S03 | 10.000 ticks con seis entradas redundantes por tick: `seen` y `frames` ≤ 181 por clave | sí |
| S04 | Vida de una sesión sin retirar, y una quinta sesión del mismo peer con cuatro sin retirar | informativo |
| S05a | Después de `retire`, el tick consumido sale `retired` y nunca `buffered` | sí |
| S05b | Ticks adelantados de una sesión retirada, después de que vence el retiro | informativo |
| S06 | Reenvío después de `drop_peer` | informativo |
| S07 | Inundación aleatoria (semilla fija): ≤ 8 claves y `seen` ≤ 181 | sí |

### 2.8 Repeticiones sin cambios de instrumento

- `hand_timeline_test.gd`: deben pasar las 23. **L19 ahora debe dar `duplicate`.**
- `hand_input_test.gd`: I16 **debe seguir fallando** (reproducción histórica y control negativo); las otras 13 pasan.
- `hand_adapter_test.gd` y `response_receiver_test.gd`, con `--trace`: no puede haber regresiones.

## 3. Parte B: entrega 5 (Rapier v0.36.0)

### 3.1 Lectura del código de v0.36.0 (hechos a confirmar, no supuestos)

- Cada objeto (espacio, cuerpo, forma, articulación) recibe un id de Rapier de un contador global (`next_id`). Un mapa global id → RID resuelve colisionadores, contactos y consultas.
- `cache_state` / `export_state` guardan el valor del contador. `load_cached_state` / `import_state` lo vuelven a escribir con `set_global_id`.
- El estado de cada objeto incluye su id. Al cargar se borra el id viejo del mapa y se inserta el guardado; si otro objeto vivo tenía ese id, su entrada se pisa.
- Se restaura el mundo nativo completo del espacio. Los nodos se emparejan por ruta relativa a `root_node`.

### 3.2 Instrumentos

Están en `prototypes/rollback_rapier/validacion_claude/`:
- `run_rapier.ps1`:
  - verifica el SHA-256 del ZIP;
  - arma una copia nueva con la fixture de Codex sin cambios y mis ensayos;
  - corre cada proceso con 8 s y guarda código, stdout, stderr y resultado.
- `rv_common.gd`, `rv_contact.gd`, `rv_exchange.gd` y `rv_spaces.gd`.
- `rv_compare.mjs`: comparaciones entre procesos.

### 3.3 Procesos

| Id | Qué | Decide |
| --- | --- | --- |
| E0 | Cada proceso termina con 0, sin vencer los 8 s y con resultado | sí |
| E1 | Ningún `SCRIPT ERROR` (validez de los instrumentos) | sí |
| E2 | Errores del motor por proceso | informativo; se examina cada uno |
| E3 | No queda ningún proceso abierto | sí |

### 3.4 R1: ensayo entregado (punto 1)

| Id | Qué | Decide |
| --- | --- | --- |
| R1a | SHA-256 propio del ZIP igual al fijado | sí |
| R1b | `codex_probe`, `codex_export` y `codex_import` con mi lanzador: tres códigos 0 guardados, `PASSED`, Rapier, sin errores | sí |
| R1c | Valores contra los publicados por Codex | informativo |
| R1d | `prepare_rapier_probe.ps1` tal como se entregó, una vez: termina y aprueba | sí |

### 3.5 R2: checkpoint durante un contacto dinámico activo (punto 2)

**Escena:**
- Piso.
- Caja A (0,6 × 0,4 × 0,4 m, 2 kg), apoyada.
- Caja B igual, que cae girada 0,2 rad y corrida 15 cm sobre A.

**Regla del checkpoint (fija):** el primer paso ≥ 5, dentro de 120, en que:
- A informa contacto con B y B con A;
- ninguna duerme;
- alguna se mueve a ≥ 0,05 m/s.

Si no aparece, el ensayo es no evaluable.

**Referencia (H = 360 pasos):**
- En el paso 30, impulso (1,2; 0; 0,4) a A.
- En el paso 240, impulso (0; 0; 0,8) a B, para despertarla.

| Id | Qué | Decide |
| --- | --- | --- |
| R2a | `load_cached_state` devuelve `true` y el estado queda ≤ EPS del checkpoint | sí |
| R2b | La repetición desde el checkpoint es igual a la referencia en los 360 pasos: ≤ EPS, mismo reposo, mismos contactos. Esta repetición guarda además un segundo checkpoint en el primer paso en que A y B duermen, entre 30 y 240 | sí |
| R2c | Una rama distinta difiere > 1 cm de la referencia (sensibilidad) | sí (validez) |
| R2d | Restaurar después de esa rama y repetir da la referencia | sí |
| R2e | `export_state` + `import_state` en el mismo proceso, y repetir, da la referencia | sí |
| R2f | Nodo = servidor (≤ EPS) y `sleeping` igual en todos los pasos registrados | sí |
| R2g | Desde el checkpoint en reposo: igual a la referencia y despierta en el mismo paso | sí; no evaluable si la referencia no duerme entre 30 y 240 o no despierta después |

### 3.6 R3: entre procesos (punto 3 y parte cruzada del punto 4)

**Escena:** como R2, pero B mide 0,5 × 0,3 × 0,3 m y pesa 1 kg, para que cambiar los nombres tenga consecuencias físicas. Misma regla de checkpoint. H = 240, con impulso a A en el paso 30.

**Variantes:**
- **Exportador:** un proceso que escribe el artefacto en un archivo local.
- **Importadores por archivo:**
  - `noise_reverse`: 7 cuerpos creados y liberados antes, y B creado antes que A, con las mismas rutas.
  - `swap`: los nombres A y B cambiados (control: se informa qué pasa).
  - `second`: segundo espacio con FloorS y S creados **antes** de la isla, y un cuerpo N creado después de importar.
  - `second_control`: lo mismo sin `import_state`.
- **ENet en localhost:** exportador e importador concurrentes; el importador usa `reverse`.

Cada importador corre 40 pasos de una rama incorrecta antes de recibir.

**Separación de lo que se prueba:**
- **Archivo local:** confiabilidad del contenido.
- **ENet en la misma PC:** los bytes llegan íntegros por una conexión real, fragmentada y confiable. **No** prueba latencia, pérdida ni orden de red.
- **Dos PC:** no se prueba (§5).

| Id | Qué | Decide |
| --- | --- | --- |
| R3a | Estado importado ≤ EPS del inicial | sí; informativo con `swap` |
| R3b | La rama incorrecta previa difiere > 0,1 mm | sí (validez) |
| R3c | Después de importar, ningún id de Rapier lo comparten dos objetos vivos (cuerpos, formas, espacios) | sí |
| R3d | Con segundo espacio: S no cambia al importar (≤ EPS) | sí |
| R3e | Con segundo espacio: un rayo sobre S devuelve S, con su RID | sí |
| R3f | Repetición entre procesos igual a la referencia en 240 pasos | sí; informativo con `swap` |
| R3g | Nodo = servidor en la repetición | sí, salvo `swap` |
| R3h | Con `post-create`: N no repite un id vivo | sí |
| R3i | Con `post-create`: los rayos sobre S y N devuelven cada uno su cuerpo | sí |
| R3j | La trayectoria de S en `second` es igual a la de `second_control` | sí |
| R3k | Cada importador por archivo recibió el mismo SHA-256 que se exportó | sí |
| R3l | ENet: mismo SHA-256 y entrega confirmada | sí |
| R3m | Dos exportaciones independientes producen el mismo snapshot (mismos bytes) | informativo |
| swap | Datos de la forma: recurso Godot contra servidor | informativo |

### 3.7 R4: contador global y segundo espacio en un proceso (punto 4)

**Escena:**
- La raíz del StateManager es `Island`, con su piso, A y B.
- O está en el **mismo espacio**, fuera de la raíz, y cae desde 3 m.
- S está en otro espacio (SubViewport con mundo propio) y cae desde 4 m.

**Secuencia (20 + 30 + resto, hasta 120 pasos):**
1. 20 pasos y checkpoint.
2. X se crea en el segundo espacio y queda vivo.
3. 30 pasos.
4. `load_cached_state`, salvo con `--control`.
5. Se crean Y en el segundo espacio y Z en la isla.
6. 10 pasos y consultas.
7. Se libera Y.
8. 10 pasos y consultas.
9. Los pasos restantes.

| Id | Qué | Decide |
| --- | --- | --- |
| R4a | Valores del contador antes del checkpoint, después de X, después de restaurar y después de Y/Z | informativo (confirma §3.1) |
| R4b | Después de crear Y y Z, ningún id compartido entre objetos vivos | sí |
| R4c | Los rayos sobre X, Y y Z devuelven cada uno su cuerpo y su RID, también después de liberar Y | sí |
| R4d | Contactos informados: X e Y con FloorS, Z con FloorA, antes y después de liberar Y | sí |
| R4e | S no cambia al restaurar la isla (≤ EPS) | sí |
| R4f | O (mismo espacio, fuera de la raíz) conserva su estado al restaurar | sí |
| R4g | S es igual al control en los 120 pasos | sí |
| R4h | O contra el control | informativo |
| R4i | Ids de X, Y y Z y el contador, contra el control | informativo |

### 3.8 Cómo se lee el resultado para "un predictor aislado"

Ningún resultado de esta parte aprueba la integración, el inventario, el rendimiento ni un modelo de red.

| Si falla | Significa |
| --- | --- |
| R4f | Restaurar la isla rebobina también lo que comparte su espacio. **Restricción confirmada:** un predictor no puede compartir espacio con cuerpos que no deben retroceder |
| R4b, R4c o R4d | La restauración del contador hace que objetos creados después repitan ids vivos. Consultas o contactos confunden objetos. Afecta a un predictor **aun en su propio espacio**, porque el contador y el mapa son globales del servidor |
| R3c, R3e, R3h o R3i | Lo mismo al importar en otro proceso |
| R4e, R4g o R3j | La restauración altera la física de otro espacio |

Se informa cuál de estos casos ocurre. No se ocultan excluyendo cuerpos.

## 4. Orden de las corridas

1. Sin red, Jolt: `hand_rotation_test`, `hand_timeline_seen_test`, `hand_timeline_test`, `hand_input_test`, `hand_adapter_test` y `response_receiver_test`.
2. En red: `grab_rotate_real`, `grab_bad_target` y `grab_rotate`, en `clean`.
3. Rapier:
   - `run_rapier.ps1` con todas las etapas y luego `rv_compare.mjs`;
   - después, una vez, `prepare_rapier_probe.ps1` como se entregó (R1d).

Si algo falla por un error de mis instrumentos, se conserva el intento y se repite solo ese instrumento.

## 5. Fuera de alcance o no cubierto

- Diferencia entre máquinas: se usa el mismo binario en esta PC. La determinación entre CPU distintas queda sin probar.
- Latencia y pérdida reales con rollback.
- Altas y bajas dentro del checkpoint, y cambios de formas.
- Inventario, articulaciones, áreas, personaje, cámara lenta, rendimiento y tamaño de snapshots en producción.
- La convivencia de Rapier y Jolt en un mismo proceso, y abrir escenas Rapier en el editor.

## 6. Agregado después de la primera corrida de Rapier, antes de repetir (la hora real es la del commit que lo agrega)

La corrida `tmp/validacion_objetos/entrega_5/rapier/20261116_185001` se conserva entera. Sobre ella:

- **R4d era un error del instrumento.** Pedía que X informara contacto con FloorS 40 pasos después de apoyarse, y un cuerpo dormido no informa contactos. Por eso el control falló, con la lista vacía. En la corrida con restauración "pasó" con una lista que pudo haber quedado vieja. **Ese R4d no cuenta en ninguna de las dos corridas.** Corrección, decidida antes de repetir:
  1. Después de las consultas de R4c, sin cambiarlas, se da un impulso (3; 0; 0) a X (segundo espacio) y a Z (isla).
  2. Se dan 10 pasos.
  3. **R4d (corregido) decide:**
     - X y Z despiertos;
     - cada uno avanza ≥ 0,1 m según la posición informada (lo esperado son unos 0,39 m, con fricción 0,8);
     - X informa FloorS y Z informa FloorA;
     - nodo = servidor ≤ EPS, y `sleeping` igual.

  El avance es necesario porque, si la sincronización de un cuerpo se corta, nodo y servidor pueden coincidir en una posición vieja. Se repiten solo `r4_spaces` y `r4_spaces_control`.
- **Diagnóstico de R3** (no son criterios nuevos; sirven para separar causas). En la primera corrida, `r3_enet_import` cambió dos cosas a la vez: el transporte (ENet) y el orden de creación (invertido sin ruido). Se agregan:
  - `r3_import_reverse_only`: archivo, orden invertido, sin ruido.
  - `r3_enet_import` con `--noise=7`: ENet, orden invertido, con ruido.

  Esto también requiere repetir `r3_export` y `r3_enet_export` en la copia nueva. Se aplican los mismos R3a a R3g y R3k/R3l.
