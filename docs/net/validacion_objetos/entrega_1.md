# Validación independiente de la entrega 1: objetos en red

Claude, 2026-11-16. Copia `validacion_claude`, rama `objetos/validacion`. **No se modificó `runtime/`, `main.gd`, el proyecto, el runner de carga ni recursos.** Criterios y tolerancias fijados antes de ejecutar: [criterios_entrega_1.md](criterios_entrega_1.md) (commits `c5fcd87` y `b4fee32`).

## Dictamen

**Requiere revisar el modelo.** La base funciona: el mismo cuerpo Jolt en los dos lados, con pasos alineados por tick, da trayectorias de suelta y lanzamiento iguales en host e invitado (≤ 21 µm), también con ajuste de ritmo del reloj, 8 pasos por cuadro y cámara lenta. Lo que no supera la puerta de viabilidad del plan (etapa 1) son tres políticas:

1. **Corrección por traslado de la diferencia:** durante el agarre oscila sola, con saltos de ±18 cm sin degradación y de hasta ±39 cm con 200 ms de RTT, aunque el host tenga la caja quieta (F1).
2. **Suelta o lanzamiento tardíos:** el host los aplica tarde y la corrección convierte ese desfase temporal en un salto de posición. Con un tirón de 200 ms del invitado, la caja que ya caía **sube 20,8 cm** de golpe; con jitter de 40 ms, un lanzamiento se mueve 13 cm a mitad de vuelo (F3).
3. **Proxies cinemáticos en el reloj remoto:** van 9 ticks atrasados con red limpia y no pueden ser empujados. Empujar la otra caja termina en un salto de 16,8 cm en el traspaso; caer sobre la otra caja en movimiento termina con 82 cm de diferencia y la caja dada vuelta (F4).

Además hay defectos de implementación corregibles sin cambiar el modelo (F2, F5–F7, F10). Ningún resultado de esta entrega valida la reconstrucción, el inventario, las pilas ni el catálogo.

## 1. Base, motor, comandos y archivos

| Dato | Valor |
| --- | --- |
| Base | `b86dda95d0171d9b027793e3a6c3cdee87c3e0de` (coincide con `delivery_commit` de `entrega_1.json`); original `677086f`, checkpoint `674a0e5` |
| Motor | `C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe`, 4.7.2.stable.official.ed1daf0bf, Jolt, `--headless`, tiempo real, sin `--fixed-fps` |
| Máquina | Una PC, host e invitado como dos procesos por `127.0.0.1` |
| Semilla de aplicación | 12345 (fija en `main.gd`), una corrida por caso |

Comandos:

```bash
powershell -ExecutionPolicy Bypass -File prototypes\objetos_red\validation\run_case.ps1 -Case drop050 -Net degraded
```

```bash
"C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe" --headless --path prototypes\objetos_red --script res://validation/contract_test.gd -- --out=tmp/validacion_objetos/contract.json
```

`run_case.ps1` lanza el host, espera a que su driver arranque (≤ 4 s), lanza el invitado, mata solo sus PID si se superan 20 s y llama al verificador. Cada `run.json` guarda la línea exacta de ambos procesos; por ejemplo, el invitado de `drop050 degraded`:

```text
Godot_v4.7.2.exe --headless --path …\prototypes\objetos_red --log-file …/client.godot.log --scene res://validation/driver.tscn -- --join=127.0.0.1 --port=43211 --case=drop050 --trace=…/client.jsonl --dlog=…/client.driver.jsonl --duration-ms=18000 --slow=1 --one-way-ms=100 --jitter-ms=40 --loss=0.05
```

Perfiles: `clean` (sin degradación), `degraded` (`--one-way-ms=100 --jitter-ms=40 --loss=0.05` en ambos), `asym` (solo invitado `--one-way-ms=150`), `mismatch` (invitado `--slow=0.5`).

Archivos nuevos (todos fuera de `runtime/`):

| Archivo | Qué es |
| --- | --- |
| `prototypes/objetos_red/validation/contract_test.gd` | Prueba de un proceso: 74 comprobaciones de `state.gd` y `authority.gd`, con bytes armados a mano |
| `prototypes/objetos_red/validation/driver.gd`, `driver.tscn` | Driver de red. Instancia `main.tscn`, actúa con prioridad −10 (antes del adaptador) y mide con un nodo `Post` a +10 |
| `prototypes/objetos_red/validation/run_case.ps1` | Corre un caso con límite externo |
| `prototypes/objetos_red/validation/analyze.mjs` | Verificador (Node 24): lee solo las trazas y escribe `analysis.json` |
| `docs/net/validacion_objetos/criterios_entrega_1.md` | Criterios previos |
| `tmp/validacion_objetos/<fecha>_<caso>_<red>/` | Trazas de ambos roles, logs y análisis. **No commiteado** (74 MB) |

## 2. Resultados por caso

Todas las corridas terminaron dentro del límite, sin procesos sobrantes y sin errores de script; la única excepción es `fingerprint_mismatch`, donde el error está esperado. Evidencia: carpeta `tmp/validacion_objetos/20261116_<hora>_<caso>_<red>`.

### Bloque 1: contrato y tiempo

| Caso | Resultado | Métrica | Tolerancia | Evidencia |
| --- | --- | --- | --- | --- |
| Serialización (S01–S14) | **Pasa** | 90 bytes; disposición little-endian verificada con parser propio; rechazo de truncados, magia, versión, reservado, NaN/inf, cuaternión nulo o no unitario, fase 3, reposo 2, HELD sin dueño, IDs 0 y ≥ 2³¹; error de giro ida y vuelta 1,8·10⁻⁷ rad | §3.1 | `contract.json` |
| Idempotencia en `authority.gd` (A01–A15) | **Falla 1 de 21** | A10: un agarre con tick 1.000.000 se acepta y se aplica en el tick siguiente; el resto pasa (duplicado antes/después del commit, tras expulsión de caché, viejo, sesión/peer ajenos, suelta futura, simultáneos, desconexión) | rechazar futuro | `contract.json` |
| Idempotencia por red | **Pasa** | `dup_throw`: 1 impulso y 1 `applied`; duplicado en espera sin respuesta; tras el ACK, respuesta guardada (`accepted@103`); tras 300 rechazos, no se reejecuta ni responde | 1 impulso | `114137_dup_throw_clean` |
| Paso nativo ↔ captura (P1–P4) | **Pasa** en las 29 corridas, ambos roles | `native_frame == engine_frame`, 1 callback por tick, `dt = slow/60`, `engine_frame − tick` constante | §3.3 | todas |
| Cinemática de un paso (P5) | Pasa en 26; **falla en 3 por criterio mal planteado** (ver §5) | amortiguación 0,1 aplicada a la velocidad previa; error de posición 1,4·10⁻⁴ relativo a 8 m/s | §3.3 | `114124`, `114129`, `114443` |
| Ajuste de ritmo (`drop050_stall`) | **Pasa** | bloqueo de 150 ms: 8 pasos en un cuadro, ritmo hasta 72 Hz (`time_scale` 1,2), `dt` sin cambio, divergencia del mismo tick 10 µm | 2 mm | `114018_drop050_stall_clean` |
| Cámara lenta 0,3 en ambos | **Pasa** | `dt = 0,005` en los dos lados; divergencia 3 µm; mismo tick de contacto | 2 mm | `114023_drop050_slow03_clean_slow0.3` |
| `ready_gate` | **Pasa** | 7 intentos antes de estar listo, 0 acciones y 0 capturas; `world_ready` (21,6 ms) antes de `clock_ready` (42,3 ms); el primer agarre posterior se acepta | 0 | `114033_ready_gate_clean` |
| `fingerprint_mismatch` | **Pasa** | invitado sale con código 2 y "Prototipos incompatibles"; sin `world_ready`, `clock_ready` ni `request`; host sin `applied` | código 2 | `114036_fingerprint_mismatch_mismatch` |

### Bloque 2: caída, suelta y lanzamiento

Sin degradación (`clean`), la suelta y la caída coinciden: C1 ≤ 21 µm, mismo tick de contacto, elevación posterior igual, C4 ≤ 18 µm, un impulso en la dirección pedida (error < 10⁻⁵ °), pose final idéntica. Fallan C5 (por el levantamiento, F1) y C6 (el instante mostrado retrocede ~7 ticks en el traspaso, sin salto visible: F5).

| Caso | Red | Fallan | Datos principales |
| --- | --- | --- | --- |
| `drop020` | clean | C5, C6 | 7 correcciones > 2 mm al levantar, máx. 8,5 cm |
| `drop050` | clean | C5, C6 | 7 correcciones, máx. 18,5 cm (+18,5 / −10,4 / +5,7 / −3,1 / +1,2 / −0,65 / +0,25 / −0,13 cm) |
| `drop100` | clean | C5, C6 | 8 correcciones, máx. 26,7 cm |
| `lateral050` | clean | C5, C6 | 5 correcciones, máx. 13,7 cm; suelta a 1,5 m/s idéntica |
| `throw050` | clean | C5, C6 | 6 correcciones, máx. 18,5 cm; lanzamiento idéntico |
| `drop020` | degraded | C4, C5, C6 | suelta aplicada 1 tick tarde; C4 = 4,0 mm, pero con el host corrido 1 tick queda en 6 µm (mismo rebote físico, un tick antes) |
| `drop050` | degraded | C4, C5, C6 | 1 tick tarde; corrección de 5,4 mm a mitad de caída; el invitado no se hunde y queda en y = 0, el host en −2 mm; salto de traspaso 2,001 mm |
| `drop100` | degraded | C5, C6 | suelta a tiempo; **16 correcciones en el agarre, máx. 38,9 cm** |
| `lateral050` | degraded | C5, C6 | suelta a tiempo; 9 correcciones en el agarre, máx. 22,3 cm |
| `throw050` | degraded | C4, C5, C6, C11 | 1 tick tarde; en vuelo, corrección de 13,1 cm (12,7 hacia atrás, 3,3 hacia abajo) y otra de +3,8 cm; +0,54 J; C4 con host corrido = 3,1 mm |

Red degradada medida: RTT de aplicación 193–228 ms de media (150–269 ms); RTT de ENet 6–8 ms, todo el retraso lo agrega el simulador. Muestras aceptadas: 75–80 % con 5 % de pérdida configurada (F9). Pérdida de ENet: 0.

### Bloque 3: límites del modelo

| Caso | Resultado | Métrica | Tolerancia | Evidencia |
| --- | --- | --- | --- | --- |
| `late_release` asym | No provocó atraso | adelanto medido 11–13 ticks = `c + 2` (§3, F3) | — | `114117_late_release_asym` |
| `late_release_hitch` | **Falla** C1, C4, C5, C6, C10, C11 | aplicada 11 ticks tarde; **la caja que caía sube 20,8 cm**; +0,23 J sobre el host; después coincide bit a bit (C9 pasa) | 2 mm | `114403_late_release_hitch_clean` |
| `release_before_ack` clean | **Falla** K1, C1, C4, C5, C6, C11 | espera 2 ticks (14 ms); divergencia 33 cm, correcciones de 20,7 y 12,6 cm, +16 J | ≤ 1 tick | `114124_release_before_ack_clean` |
| `release_before_ack` degraded | **Falla** K1, C3, C4, C5, C6, C11 | espera **12 ticks (187 ms)**; divergencia 9,9 cm; subida del invitado 2,7 mm sin subida en el host | ≤ 1 tick | `114129_release_before_ack_degraded` |
| `throw_before_ack` | **Falla** K2, K1, C1, C4, C5, C6, C11 | **sale a 90° de la dirección pedida** en host e invitado (usa la cámara) | < 1° | `114133_throw_before_ack_clean` |
| `dup_throw` | **Pasa** D1, D2 | ver bloque 1 | 1 impulso | `114137_dup_throw_clean` |
| `stale_snapshot` | **Pasa** S1, C8 | 3 snapshots HELD con rev. 2 enviados después de la rev. 3: ignorados, ningún retroceso ni salto | 0 | `114143_stale_snapshot_clean` |
| `disconnect_holding` | **Falla** X1 por un detalle | 1 `auto_release`, dueño 0, sin impulso, cae al piso; el host aplica después los 2 objetivos que ya estaban encolados (sin efecto físico) | sin objetivos | `114148_disconnect_holding_clean` |
| `grab_rejected` | **Falla** G2 | rechazo `occupied` sin predictor huérfano; **la réplica de la caja 2 queda congelada 144 ticks, error 1,25 m** | 2 mm | `114154_grab_rejected_clean` |
| `stack` (caja quieta) | **Falla** C6, C9 | proxy 9,1 ticks atrás; el predicho no se duerme sobre el proxy y no hay traspaso en 10 s; 4,3 mm de diferencia permanente | 2 mm | `114407_stack_clean` |
| `push` (caja quieta empujada) | **Falla** C6 | proxy 9,1 ticks atrás, error 16 cm; 39 `contact_recovery_required`; **salto de traspaso 16,8 cm** | 2 mm | `114422_push_clean` |
| `moving` (caja en movimiento) | **Falla** C3, C4, C5, C6, C9, C11 | proxy 8,4–9,5 ticks atrás (hasta 48,6 cm); **final 82 cm y 176° distinto**; +2,5 J contra +1,0 J; sin traspaso | 2 mm | `114734_moving_clean` |
| `wall` | **Falla** W2 (física compartida) | sin cruce; caja apretada: 9,2 mm dentro de la pared y 10,6 mm del piso en host e invitado; dibujo interpolado de la caja 2: 0,15 mm (sin penetración agregada); diferencia del mismo tick ≤ 3 µm al apretar, girar y en el rincón (ticks 120–360) | 2 mm | `114434_wall_clean` |
| `throw_wall` | **Falla** W1, W2 (física compartida) | a 8 m/s la cara llega a z = −3,0212 en el tick 124: 11 mm del otro lado de la pared de 20 mm, y rebota; igual en ambos | sin cruce | `114443_throw_wall_clean` |

Corrida inválida: `114427_moving_clean`, por un error del driver (§5). Se conserva porque muestra un caso no planeado: la caja 2 barrió la réplica en reposo y el dibujo la siguió con ≤ 2,6 mm de error en el instante mostrado.

### Pendientes (no ejecutados)

Material con restitución nula contra material real; modo `reference`; desconexión abrupta (ENet tarda > 30 s en notarla y supera el límite de 20 s); dos agarres simultáneos de dos invitados (requiere un tercer proceso); volver a agarrar después del traspaso; pared y caja móvil con red degradada; varias semillas; congestión real de ENet; prueba en dos PC; rendimiento.

## 3. Problemas distintos: primer fallo reproducible

### F1. La corrección oscila durante el agarre — bloquea el modelo

**Primer fallo:** `113137_drop050_clean`, ticks 34–75. **Más fuerte:** `113959_drop100_degraded`.

Hechos (trazas `client.jsonl`, `client.driver.jsonl` y `host.jsonl`):

| Tick inv. | y del host | y del invitado antes → después | Corrección |
| --- | --- | --- | --- |
| 34 | 0,4552 | 0,3860 → 0,5707 | +18,5 cm (fuente 28: host 0,3181, historia 0,1333) |
| 40 | 0,4890 | 0,5186 → 0,4141 | −10,4 cm |
| 46 | 0,4973 | 0,4788 → 0,5358 | +5,7 cm |
| 51 | 0,4992 | 0,5111 → 0,4801 | −3,1 cm |
| 58 … 75 | ≈ 0,5000 | | +1,2 / −0,65 / +0,25 / −0,13 cm |

En `113959_drop100_degraded` el host tiene la caja **quieta en y = 1,000 desde el tick 74**, y aun así el invitado recibe +33,3, −36,7, +38,9, −33,7, +21,3, −12,8, +7,9, −5,7, +3,4, −2,1 … cm entre los ticks 58 y 299. La primera corrida de ese caso (11:37, carpeta borrada por error) mostró la misma secuencia con +44/−46 cm. Las oscilaciones aparecen en 23 de las 29 corridas; las 6 restantes no tienen un levantamiento libre de contacto (huella, rechazo, empuje a 1,5 cm del piso y agarres soltados antes del ACK).

Análisis, separando hechos de hipótesis:
- **Hecho:** la diferencia que se traslada se mide en el tick de la muestra (18,5 cm), pero en el presente la diferencia real era 5,7 cm, porque las dos trayectorias convergían hacia el mismo objetivo. La corrección se pasa de largo y la siguiente tiene el signo contrario (cociente ≈ −0,56 sin red).
- **Hecho:** las correcciones siguen cuando el host está inmóvil. La historia que se compara ya contiene la corrección anterior y la respuesta del controlador de la mano.
- **Hipótesis:** trasladar una diferencia sin volver a simular es inestable cuando hay un controlador activo y la latencia supera su tiempo de respuesta (0,08 s). No probé otro controlador.

Es el caso "correcciones perceptibles repetidas en un caso ordinario" de la puerta de decisión del plan. El disparador sin red es F2.

### F2. El agarre se aplica en `now`, no en el tick pedido — bloquea la migración

**Primer fallo:** `113137_drop050_clean`: invitado ejecuta en 26 (pedido 25), host aplica en 23. En todas las corridas `host_applied − client_exec` está entre −2 y −4. `authority.request` usa `due = now` para `grab` y no aplica `MAX_FUTURE` (prueba A10). La suelta sí usa `requested + 1` y por eso coincide.

### F3. Suelta o lanzamiento tardíos se corrigen como posición — bloquea el modelo

**Primer fallo dirigido:** `114403_late_release_hitch_clean`. Pedido en 82, aplicado en 94 (`late=true`). Mismo tick:

| Tick | Host y / vy | Invitado y / vy |
| --- | --- | --- |
| 84 | 0,5000 / 0 | 0,4918 / −0,326 |
| 92 | 0,5000 / 0 | 0,3510 / −1,621 |
| 94 | 0,4973 / −0,163 | 0,2890 / −1,942 |
| 95 | corrección: **+20,8 cm hacia arriba** | |
| 96 … 112 | 0,4837 … −0,0121 | idénticos al host |

**Con jitter** (`113715_throw050_degraded`): aplicado 1 tick tarde. En el tick 241, desde la muestra 226, el cuerpo se mueve (+12,7; −3,3; 0) cm y gana +0,17 m/s vertical; en el 258 sube +3,8 cm. Energía +0,54 J. En 3 de 5 casos degradados la suelta llegó 1 tick tarde.

- **Hecho:** el desfase es temporal: la misma trayectoria, k ticks después. La corrección lo trata como diferencia de posición. Con k = 11 sube la caja hasta la mano (después coincide exactamente); en una parábola aplica un desplazamiento tomado en otro punto de la curva.
- **Hecho:** con contacto posterior no hay corrección (`contact_recovery_required`): `drop020`/`drop050` degradados llegan al piso un tick antes y la diferencia se resuelve en el traspaso (2,001 mm en `drop050`).
- **Hecho:** el reloj fija un adelanto de `c + 2` ticks (c = demora invitado→host), así que una demora fija siempre llega 2 ticks antes (`asym`: adelanto 11–13 ticks). El atraso aparece por variación: jitter, cola detrás de un `_ping` confiable, o un tirón del proceso.
- **Hipótesis:** es el mecanismo que mejor coincide con "la trayectoria cambia" y "sube" del informe del usuario. Este prototipo no prueba el sistema anterior.

La política "aplicarla en el siguiente límite seguro y declararla tardía" (plan §3.4), junto con el traslado de la diferencia, produce siempre un salto visible igual al movimiento ocurrido durante el atraso.

### F4. Proxies cinemáticos en el reloj remoto — bloquea el modelo

**Primer fallo:** `114422_push_clean`. El proxy se coloca en `estimated_server_tick − 6`, 9,1 ticks detrás del predictor con red limpia (13,6–15,3 ticks con 170–230 ms de RTT), y es inamovible. La caja propia choca contra donde estaba la caja 2 y queda 16 cm detrás de la del host; por el contacto no se corrige nunca, y en el traspaso salta 16,8 cm.

| Tick | Host: caja 1 x / caja 2 x | Invitado: caja 1 x / proxy x |
| --- | --- | --- |
| 100 | 0,041 / 0,641 | −0,114 / 0,503 |
| 130 | 0,482 / 1,094 | 0,315 / 1,004 |
| 165 | 0,482 / 1,095 | 0,315 / 1,095 |

En `114734_moving_clean`, la caja 1 cae sobre la caja 2 movida a 1 m/s. En el host queda arriba (y = 0,424); en el invitado el proxy está 15 cm corrido, la caja cae del borde (y = 0,29) y termina 82 cm lejos y 176° girada. En `114407_stack_clean` la diferencia es de 4,3 mm, pero el predicho no se duerme nunca sobre el proxy (`|v| = 2·10⁻⁶`, despierto) y no hay traspaso en 10 s.

Es el caso del plan §3.5: "si mueve artificialmente al predictor … se evalúa esa alternativa". El costo de la alternativa no se midió.

### F5. Traspaso — bloquea la migración

- Exige reposo local: con proxy en contacto nunca ocurre (`stack`, `moving`).
- Diferencias < 5 mm se consideran `same` y no se corrigen; quedan hasta el traspaso y saltan ahí (2,001 mm en `drop050_degraded`; 4,3 mm permanentes en `stack`).
- El instante mostrado retrocede en todos los traspasos: 7 ticks con red limpia, 13–16 con red degradada. En reposo no se ve, pero contradice "conserva continuidad temporal" (plan §3.6).

### F6. Un agarre rechazado congela la réplica — bloquea la migración

**Primer fallo:** `114154_grab_rejected_clean`. La predicción del agarre sube `o.state.revision` de 2 a 3; el rechazo no la restaura (`_receive_result`). Desde ahí `_receive_snapshot` descarta todo lo de revisión 2: la caja 2 queda quieta en el invitado mientras el host la mueve (1,25 m de error, 144 ticks). Se arregla sola recién cuando el host cambia de revisión.

### F7. Soltar o lanzar antes del ACK — bloquea la migración, más el pendiente declarado

- `throw_before_ack`: `_dependent` guarda solo `"throw"` y al llegar el ACK usa `-camera.global_basis.z`. Sale a 90° de lo pedido.
- Espera hasta la ejecución local: 2 ticks (14 ms) sin red y 12 ticks (187 ms) con red degradada. Es el límite 6 del README: queda pendiente, el criterio no cambia.
- El primer pedido toma un número de acción (2) y se descarta sin registro; se crea otro (3).
- Combinado con F2, soltar a mitad del levantamiento diverge 33 cm (+16 J en el invitado).

### F8. Penetración física compartida — no es de sincronización, pero bloquea la aprobación de pared y caída

- Piso: la caja entra 11 mm (0,2 m), 12 mm (0,5 m) y 14 mm (1 m) en el impacto y sube 9–12 mm en ~20 ticks con velocidad registrada 0 (depenetración). Es igual en host e invitado.
- Pared: a 8 m/s, 11 mm del otro lado durante un tick; apretada con la mano, 9 mm.
- **Hipótesis:** a 2–5 cm por tick, el contacto especulativo y el CCD de Jolt no evitan la penetración inicial. No verifiqué los ajustes de Jolt.

### F9. Presentación remota y simulador de red — prestación y artefacto de prueba

Con 200 ms de RTT, el búfer fijo de 6 ticks (100 ms) es menor que la demora de ida (100 ± 40 ms): entre el 80 y el 93 % de los cuadros remotos muestran la última muestra sin interpolar. Se aceptó solo el 75–80 % de los snapshots con 5 % de pérdida configurada: el simulador aplica jitter independiente a cada paquete, así que los paquetes llegan desordenados, y `view.accept` descarta los ticks viejos. Un desorden de esa magnitud es poco habitual en una red real.

### F10. Contrato y datos

- La confirmación del lanzamiento lleva la velocidad *anterior* al impulso: `throw050` confirma `lv ≈ 0` y el host tiene `(−7,65; 2,13; 0)` después del paso.
- El dibujo predicho muestra el estado de `prepared_tick − 1` y no el de `prepared_tick`, que es lo que dice `visual.shown_tick` (306 de 324 cuadros en `drop050`). Godot sincroniza el cuerpo con el nodo al empezar el cuadro físico siguiente.
- `fingerprint()` es un texto fijo: solo cambia `slow`. Masa, materiales o ajustes de Jolt distintos no se detectan.
- Después de `auto_release`, el host consume los objetivos encolados del que se fue (2 ticks en `disconnect_holding`, sin efecto porque la caja ya está suelta).
- Un duplicado posterior a la expulsión de caché no recibe respuesta (`stale` no se responde).

## 4. Lo que sí quedó demostrado

- La correspondencia preparación → paso nativo → captura se cumple en los dos roles, incluso con 8 pasos por cuadro, ritmo variable entre 57 y 72 Hz y `slow = 0,3`.
- Con la suelta aplicada en el tick pedido, la caída y el lanzamiento en Jolt son reproducibles entre procesos: suelta quieta, en movimiento lateral, lanzamiento con vuelco y apriete contra pared y rincón (≤ 21 µm).
- Serialización, revisiones, idempotencia de suelta y lanzamiento, snapshot viejo, huella incompatible y espera de `world_ready`/`clock_ready` funcionan como dice el README.
- La desconexión libera una sola vez y sin impulso.

## 5. Errores de mis pruebas y cómo se corrigieron

| Error | Efecto | Corrección |
| --- | --- | --- |
| `%.3e` en GDScript y giro medido con `angle_to` (acos en float32, resolución ~5·10⁻⁴ rad) | 2 falsos fallos en S12 | medición por diferencia de columnas; tolerancia sin cambio |
| Precedencia de la coma en PowerShell | primera corrida sin `--dlog` (host salió con código 5, sin datos) | paréntesis; carpeta borrada |
| Verificador emparejaba `applied` solo por número de acción | `wall` leyó la suelta del host sobre la caja 2 | emparejar por caja y operación |
| Disparo de `moving` | `114427` soltó al levantar la caja 2, no al volver | exige pasar antes por x > 1,05; repetida en `114734` |
| C9 comparaba contra el último registro del host | en `114427`, 1,37 m de "diferencia" que en realidad era tiempo | comparación en el instante mostrado |
| P5: banda de amortiguación con la velocidad posterior y tolerancia absoluta de posición | 3 FALLAS registradas | se dejan registradas; los datos (cociente 0,104, error 1,4·10⁻⁴ relativo) confirman un paso por tick |
| A1 cuenta movimiento físico desfasado | `drop020`/`drop050` degradados | diagnóstico agregado después, sin cambiar el veredicto: con el host corrido k ticks, 6 µm y 0 |
| Plazo de estabilización de 240 ticks | `drop100_degraded` (11:37) terminó con código 4 | plazo de preparación de 600 ticks. **Borré esa carpeta por error**; la repetición `113959` reproduce el fenómeno |
| `asym` no provocó atraso | sin suelta tardía | variante `late_release_hitch`, registrada antes de correrla (`b4fee32`) |

## 6. Instrumentación que falta

Todo lo siguiente lo medí desde el driver, sin tocar el runtime. Tendría que estar en la traza del adaptador:

1. Proxies: por tick, activo o no, tick remoto usado y pose.
2. `reconcile`: vector de corrección (pose y velocidad), tick de historia y tick de aplicación.
3. `received`: también las muestras descartadas, con su causa (tick viejo, revisión vieja, inválida).
4. `visual`: giro (`q`) e instante físico real del dibujo predicho (`prepared_tick − 1`).
5. Host: tick del objetivo del invitado usado en cada paso (`last_goal`).
6. Acciones dependientes: el pedido descartado, su número y su dirección.
7. Traspaso pendiente: qué condición falta (reposo local, reposo remoto, búfer).
8. Huella calculada con los valores reales (cuerpo, materiales, amortiguación, Jolt, ritmo).

## 7. Cambios de contrato que debe resolver Codex

No los implementé. Son decisiones de diseño o de implementación que quedan abiertas:

1. **Política de corrección (F1, F3):** el traslado de la diferencia no sirve con controlador activo ni para atrasos temporales. Hay que elegir otra política, y probarla primero con estos mismos casos.
2. **Suelta tardía (F3):** el plan propone aplicarla en el siguiente límite seguro. Las pruebas muestran que eso implica un salto igual al movimiento ocurrido durante el atraso.
3. **Contactos dinámicos (F4):** decidir el tiempo y la masa de los proxies, o la alternativa con costo acotado del plan §3.5.
4. **Agarre (F2, A10):** semántica del tick pedido y rechazo de ticks futuros.
5. **Rechazo (F6):** la predicción no debería modificar la revisión autorizada, o tiene que restaurarla al recibir el rechazo.
6. **Intención dependiente (F7):** guardar los parámetros (dirección) y no descartar números de acción sin registro.
7. **Traspaso (F5):** condición sin reposo local cuando hay proxy, qué pasa con diferencias por debajo del umbral `same`, y si se acepta que el instante retroceda.
8. **Confirmación del lanzamiento (F10):** si incluye la velocidad posterior al impulso.
9. **Desconexión:** vaciar los objetivos del peer que se fue. Definir si un duplicado tardío recibe respuesta.

## 8. Límites de esta validación

Una sola PC por loopback; degradación simulada en la aplicación (el RTT de ENet fue 6–13 ms) con desorden exagerado de paquetes; una semilla y una corrida por caso (no hay frecuencias estimadas: el atraso por jitter apareció en 3 de 5 casos); sin congestión real de ENet; headless, sin percepción visual en pantalla; dos cajas iguales; sin rendimiento ni prueba en dos PC. Los umbrales de 2 mm y 0,3° salen de la resolución de pantalla y de la holgura de Jolt, no de una prueba con jugadores. Nada de esto alcanza para afirmar cobertura de inventario, pilas o catálogo.
