# Verificación independiente de la entrega 3

Claude, 2026-11-16. Encargo: [revisión de Codex y encargo de la entrega 3](../entregas/revision_codex_entrega_2.md), sección "Encargo acotado para Claude".

Los criterios se fijaron y commitearon antes de correr, en [`criterios_entrega_3.md`](criterios_entrega_3.md):

- `b4ed00b`, 15:12:27: criterios e instrumentos.
- `acae132`, 15:16:42: agregado §7, `grab_rotate`, antes de correrlo.

## Dictamen

**La entrega 3 corrige N1 y N2 tal como declara. La bandeja y el formato cumplen su contrato, salvo un detalle de diagnóstico. Hay un defecto nuevo, N3: girar la caja durante unos 1260 movimientos de mouse hace que el invitado deje de mandar la mano, sin registrarlo. El modelo sigue sin aprobar y no habilita la migración.**

- **Confirmado:**
  - **N1:** la respuesta a la repetición vieja nombra la acción y el objeto. Hay un solo impulso y ningún error de script. Las 300 órdenes falsas reciben sus 300 rechazos con el objeto correcto. El receptor descarta, sin efecto, 23 formas de respuesta malformada.
  - **N2:** el host usa la entrada del invitado desde el primer tick del agarre. En `grab_move_left`, los 79 pasos usan el mismo objetivo en los dos lados (0 m) y la caja es idéntica (0 m), frente a los 14,2 mm de la entrega 2.
  - **Pérdida sin jitter:** con 5 % de pérdida y 100 ms, la redundancia cubre todo. Hubo ticks recibidos solo 4 o 5 veces de 6, pero ningún paso sin entrada, y la diferencia es 0 m.
  - **Acción propia del host:** se aplica un tick después del pedido, en el mismo paso y sin marca de tarde. En la entrega 2 eran dos ticks y quedaba marcada.
  - **Sin regresión:** F6 y F7 se mantienen, también con 220 ms de ida y vuelta. El contrato anterior sigue en 74/74, 13/13 y 5/5.
  - **Adaptador:** recibir entradas nunca permite mover una caja sin la concesión exacta. Se probó con otro peer, otra sesión, otra aparición, ticks anteriores al agarre y la caja del propio host.
- **Fallo registrado, sin ampliar tolerancias:** con jitter de ±40 ms, 5 de 90 entradas llegaron un tick tarde. El host usó la anterior y la caja se separó 7,3 mm. El reloj del invitado deja 2 ticks (33 ms) de margen y el jitter llega a 40 ms. La suelta también llegó 2 ticks tarde (C4: 4,95 mm de ascenso aparente).
- **Nuevo, bloquea la migración:**
  - **N3:** el giro de `main.gd` acumula error de redondeo. A los 1263 eventos de mouse, el objetivo ya no pasa `HandInput.valid`. Desde ahí `encode` devuelve vacío y `main.gd` deja de enviar la mano entera (posición y giro) sin ningún registro.
  - Comprobado de punta a punta con `grab_rotate`: el host recibió la mano por última vez en el tick 107 y sostuvo 72 pasos con la entrada vieja. La caja quedó 0,65° distinta y no hubo traspaso.
- **Diagnóstico (sin efecto físico):** si llega otra vez un tick ya consumido, la bandeja lo informa como `buffered` y no como `duplicate`. Físicamente no se reutiliza.
- **Sigue abierto, sin repetir:** suelta tardía (F3), contactos dinámicos (F4/F5) y presentación (F8/F9). La entrega no tocó ese código.

Este dictamen vale para una corrida por caso, en una PC, por localhost y con semilla 12345 (ver Límites).

## Base, motor y comandos

- **Actualización de la copia,** como indica la revisión. Antes, solo `tmp/` estaba sin versionar. Luego `git fetch --no-tags ..\implementacion objetos/implementacion` y `git merge --ff-only FETCH_HEAD`: avance de `8a81339` a `d3471012d3ccb44a8ef081d312b2cabb7fcf3e83`, sin conflictos.
- **Hashes contra `..\entrega_3.json`:** coinciden 15 de 16. `docs/net/entregas/resultados_codex_entrega_3.json` difiere solo en los finales de línea (CRLF en la copia de Codex, LF en Git). Mis instrumentos llegaron sin cambios.
- **Motor:** `C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe` (Jolt), `--headless`, tiempo real, sin `--fixed-fps`.
- **Red:** `run_case.ps1 -Case <caso> -Net clean|lossy|degraded -OutRoot tmp\validacion_objetos\entrega_3`, con límite externo de 20 s.
  - `degraded`: `--one-way-ms=100 --jitter-ms=40 --loss=0.05`.
  - `lossy` (nuevo): lo mismo sin jitter.
  - Todas las corridas terminaron con `killed=0`, `leftover=0` y sin errores.
- **Sin red:** `Godot --headless --path prototypes/objetos_red --script res://validation/<prueba>.gd -- --out=<json> [--trace=<jsonl>]`, con `timeout 20`.
- **Trazas:** `tmp/validacion_objetos/entrega_3/`, 19 MB, sin commitear. Ningún proceso de Godot quedó abierto.
- **Instrumentos nuevos:** `hand_input_test.gd`, `hand_timeline_test.gd`, `hand_adapter_test.gd` y `response_receiver_test.gd`.
- **Instrumentos cambiados:**
  - `run_case.ps1`: perfil `lossy`.
  - `analyze.mjs`: bloque "entrega 3", informe de `grab_rotate` y opción `--out`.
  - `driver.gd`: operación `rotate_main` y caso `grab_rotate`.
  - `contract_test.gd`, `contract_test_e2.gd` y `fingerprint_test.gd` quedan iguales.

**Control negativo del verificador:** antes de las corridas nuevas, el bloque nuevo se corrió con `--out` sobre las trazas de la entrega 2 (`dup_throw` 133622 y `grab_move_left` 133521). Su `analysis.json` quedó intacto: se comprobó el hash antes y después. Resultado:

- D5 falla con "acción 0, objeto undefined" (N1).
- N2a falla con `input_tick −1` en el primer paso (N2).
- M1 mide 14,18 mm, el mismo valor del informe anterior.

D4 y D6 también fallan, pero en parte porque el registro viejo no anotaba `uid`. El detector real de N1 es D5. Salidas en `tmp/validacion_objetos/entrega_3/control_verificador/`.

## Resultado por prueba

| Prueba | Red | Pasan | Fallan | Informativos |
| --- | --- | --- | --- | --- |
| `contract_test.gd` (original) | — | 74 | — | — |
| `contract_test_e2.gd` | — | 13 | — | — |
| `fingerprint_test.gd` | — | 5 | — | — |
| `hand_input_test.gd` (2.º intento) | — | 13 | **I16** | I13, I14, I16b |
| `hand_timeline_test.gd` | — | 22 | **L19 diagnóstico** | L15, L20 estado, L23 |
| `hand_adapter_test.gd` | — | 15 | — | — |
| `response_receiver_test.gd` | — | 27 | — | — |
| `151408` `dup_throw` | clean | 39 | — | 4 |
| `151415` `grab_move_left` | clean | 32 | — | 4 |
| `151430` `grab_move_left` | lossy | 29 | — | 7 |
| `151435` `grab_move_left` | degraded | 24 | **M1, M2**, C4 | 9 |
| `151503` `grab_rejected` | clean | 18 | — | — |
| `151511` `throw_before_ack` | clean | 37 | — | 4 |
| `151515` `throw_before_ack` | degraded | 32 | — | 9 |
| `151647` `grab_rotate` (§7) | clean | 26 | **H1, N2b**, C1, C6, C9 | 5 |

El primer intento de `hand_input_test.gd` es un error del instrumento (ver Errores propios). Se conserva como `contrato/hand_input_test.intento1_error_del_instrumento.*`.

## Por punto del encargo

### 1. N1 con `dup_throw`: confirmado

- La única respuesta posterior a la última repetición (tick 245, después de 300 órdenes que expulsan la caché) es `stale`, con acción 2 y objeto 1, los del lanzamiento (D3, D5).
- Las 300 órdenes falsas reciben 300 `rejected`, todos con el objeto 1 (D6). Los 304 resultados del invitado nombran objeto y acción, y no hay `discarded_result` (D4).
- Un solo impulso y un solo `applied` (D1, D2). No hay errores de script.
- **Ejemplo de ACK con la velocidad posterior al impulso:** acción 2, aplicada en el tick 86, estado inicial del tick 85, revisión 3. La velocidad pasa de (−7,5·10⁻⁷; 1,2·10⁻⁵; ~0) a (−7,662611; 2,298795; ~0) m/s, con error 0 frente a `lv(85) + 8·dir`. El `result` del invitado ahora trae ese estado inicial, y su `state` lo guarda igual (error 0).

**Receptor con respuestas malformadas (`response_receiver_test.gd`, 27/27):**

- Antes de las pruebas se fijó un agarre pendiente artificial.
- Las 23 respuestas malformadas dejan la huella del adaptador igual. Cada una deja un `discarded_result`: 19 por forma inválida y 4 por estado inicial inválido.
  - Sin identificadores, como la respuesta de N1.
  - Con `action` o `uid` en 0, negativos, de más de 31 bits, float o texto.
  - Con estado `pending` o numérico.
  - `accepted` sin `state`, con `state` vacío, de 89 bytes, de ceros, de la otra caja, de otra acción, como Array o con un cuaternión NaN.
  - Con `reason` numérico o `late` de texto.
- Una respuesta bien formada para un objeto inexistente se registra y no cambia nada.
- Los dos controles positivos sí cambian la huella: un rechazo legítimo cancela el agarre pendiente y un `accepted` coherente sube la revisión. La traza tiene los 26 registros en el orden esperado.

No se probó la capa RPC con un argumento que no sea diccionario: Godot lo rechazaría antes de `_result`. Hace falta red y no estaba en el encargo.

### 2. N2 con `grab_move_left / clean`: confirmado desde el primer tick

- El agarre se pidió en 26, y el invitado y el host lo aplicaron en 27, sin marca de tarde.
- El primer `controller` del host está en 27, con `input_tick` 27 (N2a): usó la entrada que llegó antes de la concesión y reemplazó el objetivo del GRAB.
- En los 79 pasos comunes, el host nunca usó respaldo, y su objetivo es el del invitado en el mismo paso con 0 m de diferencia (N2b).
- La caja difiere 0 m y 0° (H1, H2).
- Las entradas llegaron entre 2 y 3 ticks antes de su paso.

### 3. Formato `hand_input.gd`: cumple, con la excepción N3

- **Bytes armados a mano:** la cabecera `49 48 01 01` y los u32 LE quedan en sus desplazamientos. La posición es exacta, y el giro difiere 1,0·10⁻⁷ rad codificando y 6,2·10⁻⁸ rad decodificando (I01, I02).
- **Cantidades:** 0 → nada, 1 → 1, 6 → 6 (268 bytes) y 7 → nada, con 312 bytes o con 268 y cabecera 7 (I03).
- **Rechazos:** tamaños inconsistentes, magia invertida y versiones 0 y 2 (I04, I05).
- **Identificadores:** se rechazan en 0 y por encima de `0x7FFFFFFF`, y se aceptan en `0x7FFFFFFF`; el tick acepta 0 (I06).
- **Valores no finitos:** NaN y ±∞ en la posición se rechazan. También los cuaterniones NaN, ∞, cero, de largo 2 y de largo 1,1. El unitario de float32 se acepta y da una base ortonormal (I07, I08).
- **Paquete con un registro inválido entre seis:** se rechaza entero (I09).
- **Máximo:** 268 bytes; `encode` de 1 registro da 48 (I10).
- **El codificador rechaza los 15 casos inválidos (I11).**
- **Ida y vuelta de 1000 conjuntos aleatorios:** identificadores exactos, posición 0 m y giro ≤ 3,6·10⁻⁷ rad (I12).
- **Fuzz de 6000 entradas:** 2317 se decodificaron, todas consistentes (I15).
- **Informativo:** `decode` conserva el orden del paquete y devuelve los dos registros de un tick repetido; la bandeja decide (I13, I14).

**N3 (I16 falla):**

- Con la fórmula de `main.gd` `_unhandled_input` y deltas fijos de ±5/±3, el objetivo deja de ser codificable en el evento 1263. Para entonces, |B·Bᵀ − I| llega a 2,0·10⁻⁵ y |det − 1| a 6,7·10⁻⁶.
- El umbral fijado era 20.000 eventos (20 s a 1000 Hz dentro de un agarre). 1263 eventos son 1,3 s con un mouse de 1000 Hz, o 10 s con uno de 125 Hz.
- `Authority.valid_command` sigue aceptando esa base, porque solo mira el determinante. `HandInput.valid` exige además que sea ortonormal con la tolerancia de `is_equal_approx`.
- I16b, informativo: lo mismo ocurre con una base de determinante 1 que no es ortonormal.

**Prueba de punta a punta (`grab_rotate`, §7):**

- El invitado gira la caja con la misma fórmula, 16 eventos por tick. Desde el paso 108 (evento 1264) el objetivo no es codificable.
- El host recibió la mano por última vez en el tick 107 y usó esa entrada en los 72 pasos restantes del agarre (N2b: 72 con respaldo).
- La caja quedó 0,65° distinta en cada lado (H1) y siguió así después de soltar (C9). No hubo traspaso (C6).
- El invitado no registró nada. La suelta sí llegó, porque viaja por el canal confiable.
- En esta corrida la mano no se movía. Si se moviera, el host la seguiría manteniendo en el último objetivo recibido, porque el registro que falta es la entrada entera: posición y giro.

### 4. Bandeja `hand_timeline.gd`: cumple, con un detalle de diagnóstico

**Pruebas sin `main` (22 de 23):**

- **Uso de entradas:** acepta entradas antes de la concesión (L01) y en orden inverso (L02). Usa la más reciente (L03), nunca una futura (L04) ni una ya usada (L05).
- **Duplicados y conflictos:** el duplicado se informa como `duplicate` (L06). El conflicto en el mismo tick se informa como `conflicting_tick` y gana el primer objetivo (L07).
- **Claves ajenas:** otro peer, objeto, aparición o sesión no consumen la entrada (L08).
- **Ventana y caducidad:** la ventana va exactamente de −120 a +60 (L09), y las entradas caducan en 121 (L10).
- **Capacidad:** cuatro sesiones y dos peers; la capacidad se libera al retirar una sesión (L11–L13).
- **Retiro y desconexión:** el retiro afecta solo su sesión (L14), la lista de retirados no supera 256 (L16), y la desconexión borra solo al peer que se fue (L17).
- **Inválidas:** se rechazan (L18).
- **Memoria:** acotada con 20.000 entradas aleatorias (L21).
- **Copias:** la vista de inspección es una copia (L22) y lo guardado no cambia si se modifica el original (L24).

**L19, falla el diagnóstico:**

- Si se consume el tick 103 y vuelve a llegar el 103, la bandeja responde `buffered`, no `duplicate`. Con un objetivo distinto pasa lo mismo (L20).
- Físicamente no se reutiliza: `consume` lo excluye porque es ≤ al último usado (L19 y L20 físicos pasan).
- Efecto en las trazas de red: la mayoría de los `buffered` son copias redundantes de ticks ya usados. En `grab_move_left / clean` hay 293 `buffered` para 79 ticks necesarios. Para M3 se usó la primera recepción de cada tick, no el estado.
- Informativo: el retiro caduca en 121 ticks y después la sesión vuelve a aceptar (L15). Consumir borra todo lo ≤ ahora (L23).

**En el adaptador (`hand_adapter_test.gd`, 15/15, `main.tscn` en modo solo):**

- Las 82 entradas previas al agarre quedan guardadas. Con la caja libre no cambian nada (A00, A01).
- **Agarre del peer 2:** pedido en 40 y aplicado en 41. Ese mismo paso usa la entrada X(41), recibida antes. Nunca se usaron las del peer 3, la sesión 51, la aparición 2 ni los ticks ≤ 40 (A02, A03).
- **Respaldo y entradas tardías:** sin entradas para 61 y 62, el objetivo queda en X(60) con respaldo. Cuando 61 y 62 llegan tarde, el paso 63 usa la 62, marcada como respaldo: la entrada tardía se aplica un paso después y no se inventa ninguna (A04, A05).
- **Agarre propio del host:** pedido en 45 y aplicado en 46 sin marca de tarde. Las entradas de los peers 2 y 3 con la sesión del host nunca movieron esa caja (A06, A07).
- **Rechazo:** el agarre rechazado del peer 3 retira su sesión: la bandeja queda vacía y lo posterior da `retired` (A08).
- **Repetición vieja:** recibe `stale` con acción 50 y objeto 1, y no retira la sesión activa; el reenvío da `duplicate`. Las 305 respuestas del host están bien formadas (A09, A10).
- **Suelta y otro dueño:** la suelta retira la sesión (A11). Un agarre posterior del peer 3 usa sus propias entradas (A12).
- **Desconexión:** libera la caja y borra las claves del peer 3. Lo que llega después queda `buffered` y nunca se usa (A13).
- **En los 141 pasos,** todo objetivo usado es el del GRAB o una entrada recibida de la clave concedida (A14).

### 5. Movimiento con pérdida, entradas tardías y acciones del host

**`grab_move_left / lossy` (100 ms, 5 % de pérdida, sin jitter):** pasan M1 (0 m) y M2 (0 pasos con respaldo de 92).

- Hubo pérdida real: de los ticks necesarios, 5 llegaron 4 veces y 29 llegaron 5 veces, de las 6 esperadas. Ninguno faltó.
- El margen de llegada fue de 1 a 3 ticks. La ida y vuelta de la aplicación promedió 230 ms.

**`grab_move_left / degraded` (con ±40 ms de jitter): fallan M1 y M2. Es un fallo registrado, no se amplía ninguna tolerancia.**

- Llegaron un tick tarde los ticks 47, 54, 56, 58 y 107. El margen fue de −1 a 4 ticks, con promedio 1,5, y ninguno dejó de llegar.
- En esos 5 pasos el host usó la entrada anterior. Con la mano a 1 m/s, el objetivo difiere 16,7 mm y la caja llega a 7,28 mm en el tick 58, con 0°.
- La entrada tardía se descarta, porque en el paso siguiente ya está la más reciente.
- El agarre se aplicó a tiempo (40 = 40). La suelta, pedida en 129, se aplicó en 131 con marca de tarde. Por eso C4 mide 4,95 mm de ascenso aparente, que da 0 con el host corrido 1 tick.
- Codex midió 4,836 mm en su corrida de este caso. La diferencia es de tiempos, no de criterio.
- Causa observada: el reloj del invitado apunta a `estimado + ida/2 + 2` ticks (`main.gd`, `_physics_process`). Ese margen de 2 ticks (33 ms) es menor que los 40 ms de jitter.

**Acción propia del host (HL):**

- En `grab_rejected / clean`, el host pidió agarrar la caja 2 en 20 y se aplicó en 21, en el mismo paso y sin marca de tarde. En la entrega 2 se aplicaba en pedido + 2 y quedaba marcada.
- Lo mismo en el adaptador (A06).

**F6/F7 sin regresión:**

- F6 pasa en las 8 corridas en red: entre 123 y 285 combinaciones, todas muestras del host.
- En `throw_before_ack`, con red limpia y degradada:
  - K1: respuesta en 1 tick.
  - K2: dirección a 0,015° de la pedida.
  - K3: un solo dueño.
  - F7: misma acción, dependencia registrada y confirmada.
  - F10: ACK con error 0.
- G1/G2 pasan en `grab_rejected`, con 1,69 mm de error de réplica. Las 15 entradas del agarre rechazado quedaron `retired`.
- Ninguna corrida tuvo entradas `invalid`, `conflicting_tick` ni `capacity`, ni paquetes descartados (HI1).
- La cola de seis envíos después de soltar llega y se retira (HI2: 18 `retired` en cada `grab_move_left`).

## Errores propios

1. **`hand_input_test.gd`, primer intento:** usé `%.3e` en cuatro textos, y GDScript no admite ese formato. Salieron 4 líneas `ERROR` y los detalles de I01, I02, I12 e I16 quedaron sin formatear. Por la regla que fijé (cualquier `ERROR` invalida la prueba), el intento no cuenta.
   - Se conserva como `contrato/hand_input_test.intento1_error_del_instrumento.*`.
   - Corregí el formato con `String.num_scientific` y agregué al texto de I16 la medida de ortonormalidad. El criterio no cambió.
   - El segundo intento dio los mismos resultados booleanos: 13 pasan e I16 falla.
2. **Errores de sintaxis antes de commitear:** dos scripts tenían errores (una lambda partida en dos líneas y un tipo no inferible). Los detectó `--check-only` antes del commit de criterios. No produjeron resultados.
3. **Alcance de L21:** el aluvión aleatorio chocó casi siempre con la capacidad (11.390 de 20.000). El máximo de ticks por clave quedó en 8, así que no puso a prueba el tope de 181. Ese tope lo cubren L09 y L10.
4. **D4 sobre trazas viejas:** falla también porque el registro viejo no anotaba `uid`. No lo uso como prueba de N1; para eso está D5.

## Para Codex

- **N3, bloquea:**
  - El objetivo de mano que produce `main.gd` deja de ser codificable con un giro sostenido, y el envío se saltea sin registro.
  - Reproducción sin red: `hand_input_test.gd` I16, evento 1263. De punta a punta: `grab_rotate`, desde el paso 108.
  - `Authority.valid_command` y `HandInput.valid` no aceptan las mismas bases (I16b).
- **L19, diagnóstico:** el reenvío de un tick ya consumido responde `buffered`. Es contrario a "distingue duplicado" de la revisión, aunque sin efecto físico.
- **Jitter:** el margen de llegada de las entradas (2 ticks) es menor que el jitter del perfil degradado. Las entradas tardías se registran y no se corrigen, como declara la revisión.
- **Instrumentación nueva que usé:** `controller` con objetivo y origen en los dos roles, `hand_input` con identidad y estado, y `result` con estado inicial. Alcanzó; no pido más campos.
- No pedí cambios de contrato; mis instrumentos no tocan `runtime/` ni `main.gd`.

## Lo que sigue bloqueado y límites

- **Bloquean la migración:** N3, la suelta y las entradas tardías con jitter (F3), los contactos dinámicos (F4/F5) y la presentación (F8/F9). No volví a correr los casos de contacto ni de suelta tardía, porque ese código no cambió.
- **Límites:**
  - Una corrida por caso, una semilla (12345), una PC y localhost.
  - Pérdida y jitter son simulados por la aplicación, no congestión real de ENet.
  - Sin prueba en dos PC, sin dos invitados y sin desconexión brusca en red. La desconexión se probó solo en el adaptador.
  - Deltas de mouse fijos en I16 y `grab_rotate`: el evento exacto de falla puede variar con otros movimientos. El orden de magnitud lo da el error de redondeo de float32.
  - Sin RPC malformado a nivel de red.
- **No se hizo:** push, merge ni cambios fuera de `validation/` y `docs/net/validacion_objetos/` en la copia de validación.
