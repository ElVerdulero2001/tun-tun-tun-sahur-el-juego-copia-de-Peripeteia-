# Verificación independiente de la entrega 2

Claude, 2026-11-16. Encargo: [revisión de Codex y encargo de la entrega 2](../entregas/revision_codex_entrega_1.md). Criterios fijados y commiteados antes de correr: [`criterios_entrega_2.md`](criterios_entrega_2.md) (`6910447`, 13:28:02; agregado `9e11148`, 13:35:16).

## Dictamen

**La entrega 2 corrige lo que declara en F6 y F7, y la mayor parte de F2 y F10. Hay dos defectos nuevos de implementación (N1 y N2). El modelo sigue sin aprobar y no habilita la migración.**

- **Confirmado:**
  - El agarre y la salida se aplican en el tick pedido.
  - El estado del invitado contiene solo muestras del host.
  - Soltar o lanzar antes del ACK funciona en el mismo cuadro, también con 216 ms de ida y vuelta.
  - El ACK lleva la velocidad posterior al impulso.
  - El instante del dibujo predicho está bien declarado.
  - La huella depende de la configuración real.
  - Con la mano quieta, el agarre es idéntico en los dos lados (0 m).
  - No se debilitaron revisiones, idempotencia ni preparación: 74/74 del contrato original, 13/13 de los caminos nuevos, y C8, D1, D2, S1, R1–R4 y P1–P4 pasan en todas las corridas.
- **Nuevo, bloquea la migración:**
  - **N1:** la respuesta al duplicado viejo sale sin número de acción y produce un error de script en el invitado.
  - **N2:** el host descarta los objetivos de mano de los primeros 3–5 ticks de cada agarre. Con la mano en movimiento, el agarre diverge 14,2 mm y ya nada lo corrige.
- **Sigue fallando, como pidió Codex que se registre:**
  - Suelta tardía (F3): 10 ticks, 39 cm en el mismo tick.
  - Contactos dinámicos (F4): no se repitieron, y el código de los proxies no cambió.
- **Consecuencia medida de retirar la corrección:** cuando el reposo final difiere, el traspaso queda bloqueado para siempre. En `grab_move` la caja del invitado quedó 1 cm corrida y nunca volvió a réplica.

Este dictamen vale para una corrida por caso, en una PC, por localhost y con semilla 12345 (ver Límites).

## Base, motor y comandos

- **Actualización de la copia**, tal como indica la revisión: `git fetch --no-tags ..\implementacion objetos/implementacion` y `git merge --ff-only FETCH_HEAD`. El avance fue de `5a5d92f` a `3110cad160c5c3a2bc4102dfbb5c87ccff92a9b2`, sin conflictos. Antes solo había `tmp/` sin versionar. La entrega no tocó `validation/` ni los criterios. Los hashes de `main.gd`, `runtime/*` y `validation/*` coinciden con `..\entrega_2.json`.
- **Motor:** `C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe` (Jolt), `--headless`, tiempo real, sin `--fixed-fps`.
- **Red:** `run_case.ps1 -Case <caso> -Net clean|degraded|mismatch -OutRoot tmp\validacion_objetos\entrega_2`. La degradación es `--one-way-ms=100 --jitter-ms=40 --loss=0.05` en los dos procesos, semilla 12345. Límite externo de 20 s. Todas las corridas terminaron con `killed=0` y `leftover=0`: en esta PC el control final con `Get-CimInstance` funciona, a diferencia del entorno de Codex.
- **Contrato:** `Godot --headless --path prototypes/objetos_red --script res://validation/<prueba>.gd -- --out=<json>`, con `timeout 20`.
- **Trazas:** `tmp/validacion_objetos/entrega_2/` (no commiteadas). Ningún proceso de Godot quedó abierto.
- **Pruebas cambiadas** (solo en `validation/`):
  - `contract_test_e2.gd` y `fingerprint_test.gd`, nuevos.
  - `driver.gd`: cuatro campos nuevos en `pp`, tirón opcional en `grab` y casos `grab_move`, `grab_move_left`, `late_grab_hitch` y `throw_rejected`.
  - `analyze.mjs`: bloque "entrega 2" agregado al final. Las comprobaciones de la entrega 1 no se tocaron.
  - `contract_test.gd` y `run_case.ps1` quedan iguales.

**Control negativo:** antes de correr, el bloque nuevo del verificador se ejecutó sobre copias de trazas de la entrega 1 (en un directorio temporal, sin tocar las corridas guardadas). Señala los defectos viejos:

- agarre del host 2–3 ticks antes;
- agarre con 20,4 cm de divergencia;
- ningún `dependent`;
- ACK con 8 m/s de error, porque es la velocidad previa al impulso;
- etiqueta de dibujo correcta en solo 31 de 306 cuadros;
- duplicado viejo sin respuesta.

## Resultado por corrida

| Corrida | Caso | Red | Pasan | Fallan |
| --- | --- | --- | --- | --- |
| contrato | `contract_test.gd` (original) | — | 74 | — |
| contrato | `contract_test_e2.gd` | — | 13 | — |
| contrato | `fingerprint_test.gd` (2.º intento) | — | 5 | — (el 1.º intento fue error del instrumento, ver Errores propios) |
| `133334` | `drop050` | clean | 28 | — |
| `133346` | `drop050` | degraded | 23 (+5 informativos) | — |
| `133351` | `grab_move` | clean | 22 | **H1**; C3, C4, C6, C9, C11 por caer sobre la caja 2 (F4) |
| `133521` | `grab_move_left` | clean | 27 | **H1** |
| `133405` | `late_grab_hitch` | clean | 27 (+2 informativos) | — |
| `133526` | `throw050` | clean | 30 | — |
| `133531` | `release_before_ack` | clean | 29 | P5 ×2 (error conocido del verificador) |
| `133542` | `release_before_ack` | degraded | 24 (+5) | P5 ×2 (ídem) |
| `133546` | `throw_before_ack` | clean | 33 | — |
| `133551` | `throw_before_ack` | degraded | 28 (+5) | — |
| `133607` | `grab_rejected` | clean | 15 | — (reanalizada, ver Errores propios) |
| `133614` | `throw_rejected` | clean | 16 | — (reanalizada) |
| `133622` | `dup_throw` | clean | 31 | **E0, D3** (N1) |
| `133731` | `stale_snapshot` | clean | 29 | — |
| `133736` | `disconnect_holding` | clean | 17 | — |
| `133741` | `ready_gate` | clean | 21 | — |
| `133744` | `fingerprint_mismatch` | mismatch | 6 | — |
| `133746` | `late_release_hitch` | clean | 24 | **C1, C2, C4, C10** (F3, esperado) |

Las corridas se nombran por su hora (`20261116_HHMMSS_<caso>_<red>`). Con red degradada, el RTT de aplicación fue de 172–269 ms (media ≈ 216 ms), frente a 6–7 ms de RTT de ENet: la demora simulada no pasa por ENet. El adelanto del invitado fue de 12–19 ticks y llegaron el 76–80 % de los snapshots.

## Por hallazgo

### F2: agarre en el tick pedido. Confirmado para la acción; incompleto para los objetivos (N2)

- **Contrato:** A10 (agarre futuro rechazado), B01 (a tiempo, en pedido + 1), B02 (pasado, aplicado ahora y marcado tarde) y B03 (borde de la ventana): pasan.
- **Por red:** en las 11 corridas `clean` donde el agarre del invitado se aceptó a tiempo (todas menos `late_grab_hitch`), el host aplica el agarre en el mismo tick que el invitado: `applied = local = pedido + 1`, `late = false`. En las 3 con degradación también se alinea. `F2_marca_tarde_coherente` pasa en todas.
- **Agarre realmente tardío (`late_grab_hitch`):** el invitado se trabó 200 ms después de ejecutar el agarre. El host lo aplicó 9 ticks después de pedido + 1 y lo marcó `late = true`. Durante esos ticks el invitado ya levantaba la caja y el host no, así que el mismo tick difiere hasta 40,6 cm. Como los dos controladores persiguen el mismo objetivo fijo, convergen: 1 µm en el último tick sostenido. La caída posterior es idéntica (C1: 3 µm).

**N2: el host descarta los objetivos de los primeros ticks del agarre.** El host acepta un objetivo de mano solo si el invitado ya es el dueño (`main.gd`, rama `"goal"` de `_drain_inbound`). Los objetivos de los primeros ticks llegan antes de que el agarre se aplique, porque el invitado va adelantado, y se descartan. El host sostiene esos pasos con el objetivo que traía el pedido de agarre. Se ve en el registro `controller` de todas las corridas con agarre del invitado: `input_tick = −1` en los pasos 26–29 o 26–30 (`clean`) y 40–42 (`degraded`). Con la mano quieta no tiene efecto. Con la mano en movimiento sí (`grab_move_left`, 1 m/s hacia −x desde el tick siguiente al agarre):

| Tick | x invitado | x host | `input_tick` del host | Diferencia del mismo tick |
| --- | --- | --- | --- | --- |
| 26 | −0,5000 | −0,5000 | −1 | 0,0 mm |
| 27 | −0,5010 | −0,5000 | −1 | 1,0 mm |
| 28 | −0,5048 | −0,5000 | −1 | 4,8 mm |
| 29 | −0,5142 | −0,5000 | −1 | 14,2 mm |
| 30 | −0,5251 | −0,5139 | 30 | 11,2 mm |
| 31 | −0,5372 | −0,5284 | 31 | 8,9 mm |
| 33 | −0,5641 | −0,5586 | 33 | 5,6 mm |

(Capturas `physics` de los dos roles y registro `controller` del host, corrida `133521`. `grab_move`, hacia +x, da los mismos valores con signo opuesto en x.)

- **Hechos:**
  - Con el agarre aplicado en el tick 26 en los dos lados, la diferencia del mismo tick llega a 14,2 mm.
  - El invitado la detecta como `model_blocked` desde el tick 33 (6 registros, hasta 11,2 mm) y no la corrige.
  - Se cierra recién cuando la mano se detiene: 0 m en el último tick sostenido, y la caída sale idéntica.
- **Hipótesis no probada:** con pérdida y mano en movimiento, los objetivos perdidos a mitad del agarre (README, límite 7) agregarían divergencias del mismo tipo. `degraded` solo se corrió con la mano quieta.
- **Clasificación:** bloquea la migración. Es un defecto de implementación del contrato de entradas, no del modelo.

### F6: el estado guarda solo muestras autorizadas. Confirmado

- **`F6_estado_solo_autorizado`** pasa en las 17 corridas con invitado listo, sin excepción. Cada combinación (objeto, revisión, tick) que el invitado guardó en `state` es una captura del host o el `initial` de un `applied`, con la misma posición. Ejemplos: 750/750 en `grab_move` y 285/285 en `dup_throw`.
- **`grab_rejected`:**
  - G1: rechazo `occupied`, sin capturas predichas después.
  - G2: la réplica sigue al host con 1,69 mm de error y 0,03 ticks detrás del buffer (en la entrega 1: 1,25 m y 144 ticks).
- **`throw_rejected`** (agarre disputado y lanzamiento dependiente):
  - J1: el agarre se rechaza (`occupied`) y el lanzamiento también (`ownership`); hay un `dependent_cancelled` y ninguna captura predicha después.
  - J2: el host no aplica nada del invitado; impulsos 0 → 0 y dueño siempre el host.
  - J3: la réplica sigue al host con 0,11 mm de error.
  - Informativo: antes del rechazo, el invitado dibujó su predicción de la caja 2 hasta 8,3 cm lejos del host y después volvió. Es propio de predecir un agarre de un objeto ocupado. Si se predice o no ese agarre es una decisión de diseño, no un criterio de esta prueba.

### F7: salida antes del ACK. Confirmado, también con degradación

| Caso | Red | Ejecución local | Host aplica | Mismo tick (C1) | Dirección (K2) | Acción | Dependencia |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `release_before_ack` | clean | mismo cuadro (0,52 ms) | pedido + 1 | 0 m | — | 2 = agarre + 1 | 1 `dependent`, 1 `confirmed` |
| `release_before_ack` | degraded (RTT 216 ms) | mismo cuadro (0,40 ms) | pedido + 1 | 0 m | — | ídem | ídem |
| `throw_before_ack` | clean | mismo cuadro (0,57 ms) | pedido + 1 | 0 m | 0,0153° host e invitado | ídem | dirección guardada con error 0 |
| `throw_before_ack` | degraded (RTT 223 ms) | mismo cuadro (0,49 ms) | pedido + 1 | 0 m | ídem | ídem | ídem |

- En los cuatro casos pasan C3, C4, C6 (traspaso sin salto ni retroceso), C7 (un impulso por lado en el lanzamiento), C9, C11 y K3.
- K1 informa "1 tick" porque el driver registra con el tick anterior, pero es el mismo cuadro físico: 0,4–0,6 ms. En la entrega 1 era 12 ticks / 187 ms con degradación.
- **Límite:** las salidas tempranas viajan con el agarre por el canal confiable y ordenado, así que no llegaron tarde. Una salida dependiente que llegue tarde queda en el caso F3.

### F10

- **ACK con velocidad de salida.** Pasa en `throw050`, `throw_before_ack` (clean y degraded) y `dup_throw`. Ejemplo guardado, `dup_throw` `133622`:
  - Host antes del impulso (captura del tick 85): `lv = (−7,5·10⁻⁷; 1,19·10⁻⁵; −3,8·10⁻¹¹)` m/s.
  - ACK (`applied` del tick 86, `initial` del tick 85, revisión 3): `lv = (−7,662611; 2,298795; −3,8·10⁻¹¹)` m/s.
  - Esperado: velocidad previa + 8 m/s · `normalize(−1; 0,3; 0)` = `(−7,662611; 2,298795; 0)`. Error: 0 m/s.
  - El invitado guardó en `state` esa misma revisión y tick con `lv = (−7,66261100769043; 2,298794984817505; …)`. Diferencia: 0.
- **Instante del dibujo predicho:** en todas las corridas, cada dibujo predicho declara el tick de la captura que muestra. Ejemplos: 400/400 en `throw050` y 337/337 en `grab_move_left`. En la entrega 1 estaba corrido un tick.
- **Huella:**
  - `fingerprint_test`: misma configuración, misma huella. Cambiar en tiempo de ejecución `default_gravity` (9,8 → 10,78), `default_linear_damp` (0,1 → 0,1101) o `penetration_slop` (0,002 → 0,0023) da otra huella; restaurar devuelve la original.
  - R4: el invitado con otro `slow` termina con código 2, sin estado.
- **Objetivos después de desconectar:** X1 pasa. Hay una sola `auto_release` en el tick de la desconexión, sin impulso ni objetivos posteriores, y la caja cae al piso. El invitado registra `session_closed` y sale con código 0.

**N1: la respuesta al duplicado viejo no lleva acción y rompe el manejador del invitado.** En `dup_throw` (`133622`):

- El driver reenvía el lanzamiento (acción 2) en el tick 243, después de 300 rechazos que lo expulsan de la caché.
- El host responde, como anuncia la entrega, pero `authority.gd:27` devuelve `{"status": "stale"}` sin `action`, y `_receive_command` solo agrega `uid`.
- El invitado registra `result` con `action = 0`, `status = stale` en el tick 245. Después falla en `_receive_result` (`main.gd:453`, `result.action`): `SCRIPT ERROR: Invalid access to property or key 'action' on a base object of type 'Dictionary'`.

**Hechos:** no se ejecutó nada de nuevo (D1: un impulso; D2: ningún `accepted` nuevo; C8: sin retrocesos). El error interrumpe el manejador antes de cambiar estado. **Efecto:** el invitado no puede asociar la respuesta a su acción (D3 falla) y cada duplicado viejo deja un error de script (E0 falla). **Clasificación:** bloquea la migración. Corregirlo no requiere cambiar el modelo.

### Agarre sin corrección (F1 retirado)

- Con la mano quieta, la física del mismo tick es idéntica durante todo el agarre (H1 = 0 m) en `drop050`, `throw050`, `dup_throw`, `stale_snapshot`, `disconnect_holding`, `ready_gate` y `late_release_hitch`, y también en `drop050` degraded.
- Al soltar, la diferencia es ≤ 1 µm en todos los casos con estabilización (H2), incluido `late_grab_hitch`.
- C5 da 0 correcciones en todas las corridas: ya no hay teletransporte.
- **La retirada de la corrección no rompió el caso común. Tampoco aporta convergencia:** lo que diverge (N2, F3, F4) queda divergido hasta que la física lo cierra sola o no lo cierra nunca.

### F3: suelta tardía. Sigue fallando

`late_release_hitch` (`133746`), con el invitado trabado 200 ms en el tick de la suelta:

- Suelta pedida en 85; el host la aplica en 96, 10 ticks después de pedido + 1, con `late = true`.
- La diferencia en el mismo tick antes del contacto llega a 39,0 cm.
- Primer contacto: host 115, invitado 105.
- C4: 9,9 mm de ascenso aparente. Con el host corrido 10 ticks da 0: es la misma caída y el mismo rebote de 1 cm, mostrados 10 ticks antes.
- Sin correcciones (C5 0) y traspaso sin salto (C6). Pose final y energía iguales.

Coincide con lo que informó Codex (9 ticks, 36,3 cm). **Clasificación:** bloquea el modelo, sin cambios respecto de la entrega 1.

### F4 y F5: contactos y traspaso

- **No se repitieron** `stack`, `push`, `moving`, `wall` ni `throw_wall`. El diff de la entrega no toca `set_proxy` ni la lógica de `_sync_proxies`, salvo el registro nuevo, así que el dictamen de la entrega 1 (modelo no aprobado) sigue en pie.
- **`grab_move` lo reprodujo sin querer**, con la caja 2 quieta (error de diseño del caso, ver Errores propios):
  - La caja 1 cayó sobre la arista de la caja 2.
  - El proxy estaba en el lugar correcto: 0,35 mm del host. Aun así la respuesta al contacto difirió, porque en el invitado la caja 2 es cinemática y en el host dinámica.
  - Después del contacto, el mismo tick llegó a 2,2 cm y 3,8°. En el invitado la caja entró 14,6 mm en el piso (2,2 mm en el host) y ganó 0,066 J que el host no tiene.
- **Consecuencia nueva (F5):**
  - La caja terminó en reposo a 9,5–10 mm de la del host. El traspaso se bloqueó 280 veces (`handoff_blocked`, `divergent_rest`) hasta el final de la corrida.
  - El invitado sigue mostrando su propia caja, 1 cm corrida, sin volver a réplica. Codex lo anticipó ("puede permanecer sin traspaso"); queda medido.
  - En todas las demás corridas con traspaso, el salto fue ≤ 1 µm y el instante mostrado no retrocedió: en la entrega 1 retrocedía 7–16 ticks.

### Sin cambios

- **F8:** penetración de Jolt al caer, 10 mm de rebote en los dos lados.
- **F9:** snapshots aceptados 76–80 % con degradación. Ahora quedan registrados como `discarded` (20–26 por corrida). Buffer remoto sin muestras nuevas en el 82–96 % de los cuadros.
- **P5:** mismas dos fallas conocidas de la banda de amortiguación (exceso de 1,75·10⁻⁴ m/s en `release_before_ack`, igual que en la verificación de Codex). No se corrigió. Sigue sin decidir el dictamen; no hacía falta corregirla para esta verificación.

## Errores propios

1. **`fingerprint_test`, primer intento:** el trabajo estaba en `_initialize()`, donde la raíz todavía no está en el árbol. `main._ready()` no corrió y las huellas salieron vacías: 4 fallos falsos. Los archivos quedan en `contrato/intento1_error_del_instrumento.*`. Se corrigió pasándolo al primer `_process`; el segundo intento pasa 5/5.
2. **Verificador en `grab_rejected` y `throw_rejected`:** emparejó el agarre rechazado del invitado con el agarre propio del host, que tiene el mismo número de acción, y dio F2 y H1 fallados de forma falsa. Es la misma trampa que el caso `wall` de la entrega 1. Se corrigió: solo cuenta un `applied` si el invitado recibió `accepted` para esa acción. Se reanalizaron las mismas trazas, sin volver a correr. El primer análisis queda en `analysis.intento1_error_del_verificador.json`.
3. **Diseño de `grab_move`:** el objetivo terminaba en x = 0 y la caja cayó sobre la caja 2. La corrida y sus fallos se conservan. La variante `grab_move_left` quedó registrada (`9e11148`, 13:35:16) antes de correrla (13:35:21). El encabezado del agregado dice "13:40" por error; vale la hora del commit.
4. `--log-file` con ruta relativa en las pruebas de contrato no abrió el log de Godot. La salida y los errores quedaron en `*.stdout.log` y `*.stderr.log`.

## Para Codex: cambios de contrato e instrumentación

- **N1:** toda respuesta a un comando lleva su `action` y su `uid`, también `stale`. El manejador del invitado no debe acceder a claves que una respuesta válida puede no traer.
- **N2:** los objetivos de mano de un agarre aceptado no pueden perderse por llegar antes de que el agarre se aplique. Contrato: el host usa en el paso T el objetivo que el invitado usó en su paso T, desde el primer tick del agarre. Hoy los ticks 26–29 usan `input_tick = −1`.
- **Observación sin criterio:** las acciones propias del host se aplican en pedido + 2 y salen marcadas `late` (en `grab_rejected`: pedido 18, aplicado 20). Son un tick de demora de entrada para quien juega en el host; no produce divergencia, porque el host no predice.
- **Instrumentación:**
  - El registro `controller` del invitado siempre dice `input_tick = −1`, porque solo el host actualiza `last_goal`. Registrar el tick del objetivo usado en los dos roles permitiría comparar entradas por tick sin pasar por la física.
  - `result` no registra el estado recibido: el ACK del invitado lo leí desde el driver (`state` en `pp`). Registrarlo en la traza del adaptador lo haría verificable sin driver.

## Lo que sigue bloqueado y límites

- **Modelo no aprobado:**
  - F3: suelta tardía.
  - F4: contactos dinámicos.
  - F1/F5: no hay política de convergencia; un reposo distinto deja el traspaso bloqueado para siempre.
  - F8: penetración.
  - F9: búfer y orden.
  La puerta técnica de rollback de isla que propone Codex no se evaluó: no existe todavía y no corresponde a esta verificación.
- **Cobertura:**
  - Una corrida por caso, semilla 12345, localhost, una PC.
  - Sin mano en movimiento con pérdida.
  - Sin desconexión abrupta, dos invitados, prueba en dos PC ni congestión real de ENet.
  - Sin repetir las 29 corridas de la entrega 1, como pidió la revisión.
- **Commits:** todo quedó en commits locales de `objetos/validacion`, sin push, merge ni cambios en `runtime/`, `main.gd`, el proyecto o el runner.
