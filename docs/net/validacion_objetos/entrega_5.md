# Verificación independiente de las entregas 4 y 5

2026-11-16. Claude. Base: `dcd5fce`, entrega 5, que incluye la entrega 4 (`3fadd23`). Los criterios se fijaron antes de correr:

- `criterios_entrega_5.md`, en `ea9ab8d`;
- su agregado §6, en `28efa6b`, después de la primera corrida de Rapier y antes de repetir;
- el arreglo del lanzador, en `7725462`.

## Dictamen

**Entrega 4 (N3 y L19): aceptada.**
- **Giro (N3):** el productor real (`rotate_goal` / `HandRotation`) se mantuvo válido y codificable en 20.001 eventos dentro de `main`, en 200.000 eventos sueltos y en 20.400 eventos de punta a punta por red. El host siguió la mano sin respaldo y la pose coincidió exacta (0 m / 0°).
- **Canonización local:** acepta escalas y cizallas, devolviendo la rotación esperada a ≤ 6e-8 rad. Rechaza con aviso lo no finito, lo singular y los reflejos, sin tocar el objetivo anterior. Los tres validadores de red dan el mismo resultado en 448 objetivos.
- **Diagnóstico:** una codificación imposible deja aviso desde el primer tick, el host no la recibe y el envío se recupera solo.
- **L19:** un reenvío ya consumido sale `duplicate`, y ni ese tick ni un conflicto se vuelven a usar en ninguna ventana.

Queda una observación sin efecto en uso normal: un registro inválido bloquea los 6 del paquete. Ver "Para Codex".

**Entrega 5 (Rapier): la capacidad básica se confirma, y aparecen tres límites que bloquean un predictor aislado tal como está.**
- **Lo confirmado:**
  - Restaurar en pleno contacto dinámico, en reposo y al despertar da una repetición **bit a bit** igual: 360 pasos con posiciones, bases, velocidades, reposo y contactos idénticos.
  - Entre procesos funciona por archivo y por ENet en esta PC.
  - El ensayo de Codex se reproduce con tres códigos de salida 0.
- **Los tres límites:**
  1. **Restaurar rebobina el espacio entero** (R4f). Un cuerpo del mismo espacio, fuera de la raíz del StateManager, vuelve 2,1 m atrás.
  2. **El contador global de ids vuelve atrás al restaurar** (R4a/R4b). El primer objeto creado después repite el id de un objeto vivo de **otro** espacio. Desde ahí, un rayo sobre el objeto vivo devuelve el nuevo (R4c), y cuando el nuevo se libera, el vivo queda sin identificar y su nodo deja de seguirlo: se mueve a 1,66 m/s y su posición informada no avanza (R4d).
  3. **Importar en otro proceso adopta los ids del origen** (R3). Funciona si los ids del destino no se cruzan con los del origen, como en la prueba de Codex, que solo los corría hacia arriba. Si el destino creó los mismos cuerpos en otro orden, un cuerpo deja de informar su posición y su reposo, aunque su física sigue bien. Si el destino tiene otro espacio vivo con esos ids, los objetos de los dos espacios se confunden: un rayo sobre S devuelve B, y la isla deja de repetir la referencia (4,2 cm).

La física del otro espacio no se altera (R4e y R4g exactos). La confusión está en la identificación, las consultas y la sincronización con los nodos.

No se aprueba integración, inventario, rendimiento ni modelo de red. `model_approved` sigue en `false`.

## Base, motor y comandos

- **Copia:** solo `tmp/` estaba sin versionar. `git fetch --no-tags ..\implementacion objetos/implementacion` y `git merge --ff-only FETCH_HEAD`: avance de `ed8968c` a `dcd5fce` sin conflictos.
- **Hashes:**
  - Contra `..\entrega_5.json`: coinciden 10 de 11. `resultados_codex_entrega_5.json` difiere solo en los finales de línea; su versión CRLF coincide.
  - Contra `..\entrega_4.json`: coinciden los archivos que la entrega 5 no tocó.
  - Mis pruebas anteriores llegaron sin cambios.
- **Motor:** `C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe`, sin `--fixed-fps`.
  - Jolt para la parte A.
  - Rapier v0.36.0 para la parte B, desde `C:\Users\ElCaido97\Downloads\godot-rapier-3d-single.zip`: SHA-256 `9700717c…a7c`, 63.038.621 bytes, verificado con código propio.
- **Sin red, Jolt:** `Godot --headless --path prototypes/objetos_red --script res://validation/<prueba>.gd -- --out=… [--trace=…]`, con `timeout 20`.
- **Red:** `run_case.ps1 -Case <caso> -Net clean -OutRoot tmp\validacion_objetos\entrega_5\red`, con límite de 20 s. Las tres corridas terminaron con `killed=0`, `leftover=0` y sin errores.
- **Rapier:** `prototypes/rollback_rapier/validacion_claude/run_rapier.ps1`, con límite externo de **8 s por proceso**.
  - Prepara una copia nueva: fixture de Codex sin cambios, mis ensayos y la extensión registrada.
  - Guarda en `runner.json` el código de salida real de cada proceso.
  - `rv_compare.mjs` hace las comparaciones entre procesos.
- **Duración:** el proceso Rapier más largo tardó 1,0 s. No venció ningún límite y no quedó ningún Godot abierto.
- **Trazas:** `tmp/validacion_objetos/entrega_5/`, 73 MB, sin commitear. Cada copia lleva su DLL.
  - Corridas de Rapier: `rapier/20261116_185001` (primera) y `rapier/20261116_185430` (repetición según §6).
  - Preparador de Codex: `tmp/rapier_probe_20261116_215506_8e697e`, con su salida en `rapier/codex_preparer.log`.

## Resultado por prueba

### Parte A: entrega 4

| Prueba | Resultado |
| --- | --- |
| `hand_rotation_test` (nueva) | 25 pasan, 0 fallan, 4 informativas |
| `hand_timeline_seen_test` (nueva) | 5 pasan, 0 fallan, 3 informativas |
| `hand_timeline_test` | 23 de 23. **L19 ahora da `duplicate`**; L20 da `conflicting_tick` |
| `hand_input_test` | 13 pasan. **I16 sigue fallando en el evento 1263**: es la reproducción histórica de la fórmula vieja y funciona como control negativo. I16b: ahora `valid_command` también la rechaza, así que la asimetría desapareció |
| `hand_adapter_test` / `response_receiver_test` (con `--trace`) | 15 de 15 y 27 de 27 |
| `grab_rotate_real` / clean (nuevo) | Pasa todo: P5 (20.400 eventos válidos), P6, P7 (151 pasos sin respaldo, 0 m / 0°), P8, N2a, N2b, H1, HI1, F2, F6 y C1–C11 |
| `grab_bad_target` / clean (nuevo) | Pasan D1, D2, D3 y P8. El verificador general marca **N2b FAIL**, con 3 pasos de respaldo: es el costo medido en D4 (ver abajo) |
| `grab_rotate` / clean (regresión) | Pasa todo. El objetivo crudo del driver deja de ser codificable en el paso 107 (evento 1264), pero `set_goal` lo canoniza: el host recibe hasta el tick 178 y no usa respaldo |

### Parte B: entrega 5

| Prueba | Resultado |
| --- | --- |
| E0–E3 | Todos los procesos terminan con 0, sin vencer, sin `SCRIPT ERROR` ni errores del motor (salvo el aviso conocido de certificados) y sin dejar procesos |
| R1a SHA del ZIP | Pasa |
| R1b ensayo entregado con mi lanzador | Pasa: `codex_probe` 0, `codex_export` 0, `codex_import` 0, los tres `PASSED`, Rapier |
| R1c valores | Iguales a los de Codex: snapshot de 10.255 y 10.217 bytes, repeticiones con error 0, cambio sin la orden de 4,57 cm |
| R1d `prepare_rapier_probe.ps1` tal cual | Pasa: código 0 en 1,6 s, los tres `PASSED` |
| R2a–R2g, contacto, reposo y despertar | **Pasan las 7, todas exactas** (ver punto 2) |
| R3, archivo, ruido 7 + orden invertido | Pasan R3a, b, c, f y g; repetición exacta |
| R3, ENet, ruido 7 + orden invertido (§6) | Pasan R3a, b, c, f y g; repetición exacta |
| R3, orden invertido sin ruido (ENet en la primera corrida; archivo en §6) | **Fallan R3f y R3g**, con los mismos números por las dos vías |
| R3, segundo espacio | **Fallan R3c, d, e, f, h, i y j** |
| R3, segundo espacio sin importar (control) | Pasan R3c, d, e, h e i |
| R3k / R3l integridad | Pasan: 176.056 bytes con el mismo SHA-256 por archivo y por ENet (entrega confirmada, 580 ms) |
| R3m | Dos exportaciones independientes produjeron el mismo snapshot, bit a bit |
| R4, con restauración | **Fallan R4b, R4c, R4d (corregido) y R4f**; pasan R4e y R4g (exacto) |
| R4, control | Pasan R4b, R4c, R4d (corregido) y R4e |

## Por punto del encargo

### Parte A, 1: productor real del giro

- **P01:** 20.001 eventos de `main.rotate_goal`, con los deltas de I16 y el eje de la cámara. Todos aceptados, válidos y de 48 bytes al codificar. Ida y vuelta máxima por el paquete: 4,2e-9 rad. |B·Bᵀ−I| máximo: 1,2e-7.
- **P02:** `HandRotation` sola, 200.000 eventos válidos.
- **P03** (informativo): deriva contra un cuaternión en doble precisión de 1,1e-6 rad a los 20.001 eventos y de 2,0e-6 rad a los 200.000. No se acumula.
- **P04:** la fórmula vieja sigue fallando en 1263, como control negativo.
- **En red (`grab_rotate_real`):** 20.400 eventos en 120 ticks, ninguno inválido y 0 `hand_input_encode_failed`. El host usó la mano del invitado en sus 151 pasos, sin respaldo, y la pose host/invitado fue 0 m / 0°.

### Parte A, 2: canonización, rechazos y validadores

**Aceptados,** con la rotación esperada a ≤ 6e-8 rad y el origen exacto:
- rotación pura;
- escala 2;
- escala por eje 1, 2, 3;
- escala 1e12;
- escala 0,02.

También se aceptan, válidos, la cizalla y la base casi singular (det 2e-3).

**Rechazados,** con el objetivo anterior intacto:
- reflejo;
- base singular;
- NaN o infinito;
- escala 1e13, cuyo determinante desborda float32.

**Otras comprobaciones:**
- `rotate_goal` rechaza NaN, infinito y eje cero, y acepta un delta de 1e30 con resultado válido.
- El setter de `_goal_rotation` rechaza una base singular.
- **C14:** hubo exactamente un aviso por rechazo, 49 `invalid_local_target` y 4 `invalid_local_rotation`.
- **V01/V02:** en 448 objetivos (rotaciones, escalas cercanas a 1, cizallas de 1e-6 a 1e-3, reflejos, NaN y la fórmula vieja en siete puntos), `valid_target`, `HandInput.valid` y `Authority.valid_command` coinciden siempre. Todo lo que `set_goal` acepta pasa los tres.
- **V03:** el receptor sigue estricto. La fórmula vieja es inválida desde el evento 1263 y la red no la canoniza.
- **G01:** `request_grab` con reflejo no cambia nada.
- **G03:** `request_grab` con escala 2 encola un objetivo canónico.

**Informativos:**
- **C09b:** una escala uniforme 0,005 (det 1,25e-7) se rechaza por el umbral de 1e-6, aunque es una rotación escalada.
- **G02:** `request_grab` con punto NaN se rechaza **sin aviso**: hay un `return` directo.

### Parte A, 3: codificación imposible

Para provocarla hubo que asignar `main.target` directamente durante un tick, salteando la API: escala local (1, 1, 1,5), det 1,5. No encontré ningún camino natural que la produzca.

- **D1:** el aviso sale en el tick forzado (62).
- **D2:** el host no recibe ninguna entrada del 62.
- **D3:** 6 avisos (62–67) y el envío se recupera. El host recibió 177 entradas posteriores.
- **D4, el costo:** mientras el registro inválido sigue en la historia de 6, **no sale ningún paquete**.
  - El 62 se pierde.
  - El 63 y el 64 llegan tarde, antes del paso 65.
  - El host usa la mano del 61 en los pasos 62, 63 y 64.

  Por eso el verificador general marca N2b FAIL en este caso. No es una regresión de N2: en los otros dos casos N2b pasa.

### Parte A, 4: L19, L20 y el registro `seen`

- **S01:** el tick 100, consumido y reenviado igual en cada "ahora" de 101 a 300, sale `duplicate` 120 veces (hasta 220) y después `outside_window`. Nunca vuelve a la bandeja ni se reutiliza.
- **S02:** con otro objetivo, sale `conflicting_tick` 120 veces y `outside_window` después. No se reutiliza.
- **S03:** 10.000 ticks con 6 entradas redundantes: `seen` llega a un máximo de 124 y `frames` a 3.
- **S05a:** después de `retire`, sale `retired` y nunca `buffered`.
- **S07:** inundación aleatoria con ≤ 8 claves.

**Informativos:**
- **S04:** una sesión sin retirar conserva su clave 120 ticks. Con cuatro así, una quinta sesión del mismo peer recibe `capacity` hasta que vencen. En `main.gd` toda suelta o lanzamiento retira la sesión, así que solo afecta a sesiones que terminan de otra forma.
- **S05b:** cuando vence el retiro (120 ticks), un tick adelantado de esa sesión vuelve a quedar `buffered`.
- **S06:** después de `drop_peer`, un tick ya consumido también queda `buffered`.

En los dos últimos casos la bandeja lo entregaría si alguien lo pide. La autoridad no lo pide, porque la sesión terminó. El adaptador (15/15) y el receptor (27/27) no muestran regresión.

### Parte B, 1: ensayo entregado

Mi lanzador verificó el SHA-256 del ZIP y guardó los tres códigos reales: 0, 0 y 0. Los valores coinciden con los publicados por Codex. Su preparador, sin cambios, también terminó bien. Ver R1a–R1d.

### Parte B, 2: checkpoint en contacto activo, reposo y despertar

**El checkpoint:** cayó en el paso 16, con la regla fijada antes:
- A informa contacto con B y con el piso;
- B informa contacto con A;
- B se mueve a 1,35 m/s;
- ninguna duerme.

Snapshot: 10.993 bytes.

**Referencia (360 pasos):**
- Empujón a A en el paso 30.
- Las dos cajas se duermen en el paso 95 y duermen 229 pasos en total.
- B despierta con el impulso del paso 240.
- A y B se informan en contacto en 34 pasos.

**Resultados:**
- **R2a:** la restauración devuelve `true` y deja el estado exacto.
- **R2b:** la repetición de 360 pasos es exacta, con posiciones, bases, velocidades lineal y angular, reposo y contactos informados iguales. Esa repetición además guardó el checkpoint de reposo (paso 95) sin alterar nada.
- **R2c:** una rama distinta se separa 21 cm, así que el instrumento es sensible.
- **R2d:** restaurar después de esa rama y repetir da exacto.
- **R2e:** `export_state` + `import_state` en el mismo proceso da exacto.
- **R2f:** nodo = servidor y `sleeping` igual en todos los pasos.
- **R2g:** desde el checkpoint en reposo, 265 pasos exactos, y B despierta en el paso 240, igual que en la referencia.

### Parte B, 3: entre procesos, asignación distinta y rutas estables

- **Cuando los ids del destino no se cruzan con los del origen, funciona exacto,** por archivo y por ENet. Con 7 cuerpos creados y liberados antes, y B creado antes que A, los ids del destino arrancaban en 16–21. Después de importar pasaron a 1–7, los del origen, y el contador global bajó de 21 a 7.
- **Orden invertido sin ruido, por archivo y por ENet, con los mismos números:**
  - El destino creó B (ids 4/5) antes que A (6/7). Al importar quedan A = 4/5 y B = 6/7, y ningún objeto vivo repite id.
  - Aun así, la repetición falla: las **velocidades coinciden exactas**, pero la posición informada difiere 5,7 cm, el reposo difiere en 179 de 240 pasos y el nodo difiere del servidor 4,4 cm, con `sleeping` distinto en los 240.
  - **Inferencia por el código** de `load_state_internal`: se cargan los cuerpos en orden; al cargar A, el id 4 se le asigna a A pisando la entrada de B; al cargar B, se borra su id viejo, que es 4, y A queda sin entrada en el mapa. Un cuerpo sin entrada no se sincroniza.
- **Segundo espacio vivo en el destino** (FloorS y S creados antes de la isla):
  - Al importar, la isla toma los ids 1–7 del origen, que ya eran de FloorS, del espacio S y de S. Quedan con el mismo id el espacio de la isla y el espacio S (3), A y S (4/5), y Floor y FloorS (1/2).
  - La velocidad que se lee de S cambia 0,2 m/s en el instante de importar, aunque su posición no cambia.
  - El rayo sobre S devuelve B.
  - La isla deja de repetir la referencia: 4,2 cm, y 40 pasos con reposo y contactos distintos.
  - La trayectoria de S coincide en posición con el control sin importar, pero sus velocidades informadas difieren 0,35 m/s (R3j).
  - El control sin importar pasa todo.
- **`swap`** (informativo; los nombres cambiados, con cajas de distinto tamaño): la importación no avisa nada.
  - El nodo "A" (caja de 0,5 × 0,3 × 0,3) queda con la forma de servidor del A de origen: semiejes 0,3 × 0,2 × 0,2.
  - El nodo "B" queda con forma de servidor **(0, 0, 0)**.
  - Como el orden de creación también quedó cruzado, la repetición falla con los mismos números que el orden invertido.
- **Qué separa cada prueba:**
  - **Archivo local:** el contenido llega íntegro (R3k).
  - **ENet en la misma PC:** 176.056 bytes llegaron con el mismo SHA por una conexión real y fragmentada (R3l). Que importar por ENet dé exacto (con ruido) o falle (sin ruido) depende del orden de creación, no del transporte.
  - **Dos PC:** no se probó. Que dos exportaciones independientes dieran los mismos bytes solo habla de esta PC.

### Parte B, 4: contador global y segundo espacio

**Secuencia:**
1. Contador en 14.
2. Checkpoint de la isla.
3. X se crea en el segundo espacio, con ids 15/16, y el contador sube a 16.
4. 30 pasos.
5. Restauración: **el contador vuelve a 14** (R4a).
6. Y, en el segundo espacio, recibe **15/16, los de X**, que sigue vivo (R4b).

**Consecuencias:**
- **R4c:** el rayo sobre X devuelve Y. Con Y liberado, devuelve un choque sin cuerpo (RID 0).
- **R4d (corregido):** después del impulso, X tiene 1,66 m/s, pero su posición informada **avanzó 0 m** y su nodo lo acompaña quieto. En el control avanzó 0,385 m. Z, creado en la isla después de restaurar con ids 17/18 que nadie más tenía, se comporta bien en los dos casos.
- **R4e y R4g:** S, en el otro espacio, no cambia al restaurar, y sus 120 pasos son **exactos** contra el control.
- **R4f:** O, en el mismo espacio pero fuera de `Island`, **se rebobina**.
  - Justo después de restaurar, su posición informada todavía es la de antes, pero su velocidad ya es la del checkpoint.
  - En el paso siguiente aparece a 2,34 m de altura, cerca de los 2,40 del checkpoint, mientras en el control está a 0,21 m.
  - Contra el control difiere hasta 2,13 m desde el paso 51.

**Si bloquea un predictor aislado:**
- **En el mismo espacio que el resto del mundo:** sí. Restaurar rebobina todo el espacio (R4f).
- **En un espacio propio:** la física de los otros espacios queda intacta, pero el contador global y el mapa de ids son del servidor entero.
  - Restaurar hace que lo creado después repita ids de objetos vivos de otros espacios.
  - Eso los confunde en consultas y les corta la sincronización (R4b–R4d).
  - Bloquea mientras no se resuelva.
- **Entre procesos:** la importación adopta los ids del origen. Bloquea en cuanto el destino tenga objetos con esos ids o haya creado los mismos cuerpos en otro orden.

## Errores propios

- **R4d de la primera corrida no cuenta, en ninguna de las dos variantes.** Pedía contactos a un cuerpo que se había dormido: en el control dio la lista vacía, y en la corrida con restauración "pasó" con una lista posiblemente vieja. Lo corregí antes de repetir (§6, `28efa6b`). Además agregué la exigencia de que la posición avance, porque una sincronización cortada puede hacer coincidir nodo y servidor en una posición vieja.
- **Primera corrida de ENet:** cambió dos cosas a la vez, transporte y orden de creación. La separé con dos corridas de diagnóstico (§6).
- **Invocación errónea del lanzador:** al pasar la lista de etapas por `powershell -File`, llegó como un solo texto y corrió una etapa "r" sin argumentos. No produjo resultados. Se conserva como `rapier/20261116_185407.intento_invocacion_erronea` y se arregló en `7725462`.
- **Criterios:** al escribirlos no preví que el verificador general aplicaría N2b a `grab_bad_target`. El FAIL que marca se explica arriba y no se cuenta como regresión.

## Para Codex

**Entrega 4:**
- Un registro inválido en `_hand_history` hace que `encode` rechace el paquete entero durante 6 ticks: se pierde ese tick y los cinco siguientes llegan tarde (D4). Hoy no encontré un camino natural que lo produzca.
- `request_grab` con punto no finito se rechaza sin aviso (G02).
- Una escala uniforme ≤ 0,01 se rechaza por el umbral de determinante (C09b), aunque es una rotación escalada.

**Entrega 5:**
1. `load_cached_state` / `import_state` reescriben el contador global (`set_global_id`), y lo creado después repite ids de objetos vivos de cualquier espacio (R4b–R4d).
2. Restaurar rebobina todo el espacio, también lo que está fuera de `root_node` (R4f). Justo después de restaurar, la posición informada de esos cuerpos queda vieja durante un paso.
3. La importación adopta los ids guardados.
   - Si el destino creó los mismos cuerpos en otro orden, uno queda sin entrada en el mapa y deja de sincronizarse, aunque su física siga bien.
   - Si otro espacio vivo usa esos ids, se confunden objetos y espacios, y la isla deja de repetir la referencia.

   La prueba de identidad entregada solo corría los ids hacia arriba (+14), y por eso no lo veía.
4. Con rutas que apuntan a cuerpos de otra forma (`swap`), la importación no avisa: pisa la forma del servidor y llega a dejar una en (0, 0, 0).

## Bloqueado y límites

- No probé en dos PC ni con CPU distintas. La igualdad bit a bit vale para este binario en esta PC.
- ENet solo en localhost, sin latencia ni pérdida, y sin rollback por órdenes que lleguen tarde por red.
- No se probaron altas y bajas dentro del checkpoint, cambios de formas fuera de `swap`, articulaciones, áreas, personaje, cámara lenta, inventario, rendimiento ni tamaño de snapshots en producción.
- Un solo valor de semilla y un escenario por prueba. No repetí la matriz de Jolt.
- No modifiqué `runtime/`, `main.gd`, `probe.gd`, `exchange_probe.gd`, `prepare_rapier_probe.ps1` ni `project.godot`, ni instalé Rapier en el juego.
