# Criterios fijados antes de ejecutar: validación de la entrega 1

Escrito por Claude el 2026-11-16, **antes de correr cualquier caso**. Se commitea solo, sin resultados, para que quede registro de que las tolerancias no se adaptaron a lo observado. Base: `b86dda95d0171d9b027793e3a6c3cdee87c3e0de` (rama `objetos/validacion`). Proyecto ejecutado: `prototypes/objetos_red/project.godot`.

## 1. De dónde salen las tolerancias

| Magnitud | Valor | Origen |
| --- | --- | --- |
| Paso físico | `dt = slow / 60` s | `main.gd`: `RATE = 60`, el cliente compensa `time_scale` |
| Cuantización de posición | ≈ 1,2·10⁻⁷ m cerca de 1 m | float32 de Godot y del snapshot |
| Holgura de penetración de Jolt | 2 mm | `jolt_physics_3d/simulation/penetration_slop=0.002` |
| Píxel en pantalla | 1,4 mm a 1 m; 2,8 mm a 2 m | cámara de 75° vertical, 1080 px: `2·d·tan(37,5°)/1080`. La mano sostiene entre 0,6 y 2,5 m |
| **Umbral perceptible de posición** | **2 mm** | ≈ 1 px a 1,4 m en 1080p; igual a la holgura física: lo que exceda la holgura no es ruido de contacto |
| **Umbral perceptible de giro** | **0,3°** | giro que mueve 2 mm la esquina más lejana (media diagonal de la cara 0,6×0,4 ≈ 0,36 m) |
| Energía | **0,04 J** | `m·g·2 mm` con m = 2 kg: subir la caja 2 mm |
| Diferencia numérica sin red | 0,1 mm (solo diagnóstico, no aprueba ni falla) | 1000 veces la cuantización |
| Tick de primer contacto | ±1 tick | resolución temporal del paso |
| Cinemática de un paso | `|Δp − lv·dt| ≤ 10⁻⁵ m`; `|Δv_y + g·dt| ≤ 0,1·dt·|v| + 10⁻⁴` | 0,1 es la amortiguación lineal por defecto de Godot sumada en modo COMBINE; con dos pasos o con `dt` distinto el error sería del orden de `g·dt` (0,16 m/s) |

No se usa `--fixed-fps`. Los dos procesos corren en tiempo real, `--headless`, en esta PC, con el `Godot_v4.7.2.exe` del escritorio.

## 2. Qué se compara

- **Mismo instante físico:** registro `physics` del host y del invitado con el mismo `tick`. Ambos se capturan después del paso preparado con ese número. No se compara por línea de log ni por llegada de paquete.
- **Corrección:** el driver mide la pose del cuerpo después del `_physics_process` del adaptador (nodo `Post`, prioridad +10) y la compara con la captura `physics` de `tick − 1` del mismo proceso. Cualquier diferencia es un movimiento agregado por la reconciliación.
- **Dibujo:** el driver registra en cada cuadro, después de `_process` del adaptador, la transformación del modelo dibujado (posición y giro) y el instante que la presentación dice mostrar. Para asignar el instante físico real a un dibujo predicho se verifica contra las capturas del propio proceso, no se acepta la etiqueta sin comprobar.
- **Punto más bajo:** mínimo `y` de las 8 esquinas de la caja 0,6 × 0,4 × 0,4. Piso en `y = 0`. Pared: cara delantera `z = −2,99`, trasera `z = −3,01`, `x ∈ [−2, 2]`.
- **Elevación posterior** de una serie `y(t)`: desde el primer instante en que el punto más bajo llega a 3 mm de su altura final, `R = max_t [y(t) − min_{t0≤t'≤t} y(t')]`. Se calcula para el centro de masa y para el punto más bajo, en física del host, física del invitado y dibujo del invitado.
- **Ascenso artificial del dibujo (A1):** suma, cuadro a cuadro, de la subida del dibujo del invitado que no tiene la física del host en el mismo intervalo físico: `Σ max(0, Δy_dibujo − max(0, Δy_host))`. Si el instante mostrado retrocede, la referencia del host vale 0 en ese intervalo: volver a mostrar el pasado no es movimiento físico. Detecta una subida aunque la caja nunca se hunda en el piso.

## 3. Bloque 1: contrato y tiempo

### 3.1 Serialización (`contract_test.gd`, un proceso, sin red)

Éxito si se cumplen todas: 90 bytes; disposición verificada con bytes armados a mano en little-endian, sin usar `encode`; ida y vuelta conserva identidad, revisión, fase, reposo, IDs, giro (< 10⁻⁶ rad) y velocidades; aceptación de `MAX_ID` en todos los campos de 32 bits; rechazo de: tamaños 0, 1, 89 y 91; magia, versión o reservado distintos; NaN o infinito en posición, cuaternión, `lv` o `av`; cuaternión nulo o con `|q|² − 1| > 0,01`; fase 3; reposo 2; `HELD` sin dueño o sin sesión; `FREE` con dueño; IDs 0 y valores entre `2³¹` y `2³² − 1`; base con reflexión o escala. La revisión no vuelve a 1 después de soltar ni de una liberación por desconexión.

### 3.2 Idempotencia (`contract_test.gd` sobre `authority.gd`, y por red en `dup_throw`)

Éxito si: un duplicado antes del commit no crea un segundo trabajo; uno posterior recibe el mismo resultado guardado sin cambiar revisión; tras expulsar el resultado de la caché (256 entradas) el duplicado no se vuelve a ejecutar; una acción vieja, de otra sesión o de otro peer se rechaza; **cualquier** operación con tick mayor que `ahora + 60` se rechaza (plan §3.4: "Los ticks futuros fuera de la ventana se rechazan"). Por red: el contador de impulsos del host para la caja aumenta exactamente 1 por lanzamiento aunque se reenvíe el mismo comando antes y después del ACK y después de expulsarlo de la caché.

### 3.3 Correspondencia entre preparación y paso nativo

En todas las corridas, por rol, para cada par de capturas consecutivas despiertas: `native_frame == engine_frame`; `native_callbacks` aumenta exactamente 1; `native_dt` y `physics_delta` iguales a `slow/60` (error relativo ≤ 10⁻⁶); `tick` consecutivo y `engine_frame − tick` constante; cinemática de un paso según la tabla 1 en vuelo libre. Casos específicos:

- `drop050_stall`: el driver del invitado bloquea 150 ms el proceso 6 ticks después de soltar. Debe observarse ajuste de ritmo (`rate_hz ≠ 60`) y varios pasos físicos en un mismo cuadro; las comprobaciones anteriores se siguen cumpliendo y la divergencia física del mismo tick queda ≤ 2 mm.
- `drop050_slow03`: `--slow=0.3` en ambos. `dt = 0,005` en los dos lados y divergencia del mismo tick ≤ 2 mm antes del contacto.

### 3.4 Preparación del invitado

- `ready_gate`: el driver llama a `request_grab`, `set_goal`, `request_release` y `request_throw` en cada tick hasta `ready_for_input`. Éxito: `world_ready` antes de `clock_ready`; ningún `request` ni captura física del invitado antes de `clock_ready`; la primera acción posterior funciona.
- `fingerprint_mismatch`: host con `--slow=1`, invitado con `--slow=0.5`. Éxito: el invitado termina con código 2 y "Prototipos incompatibles", sin `world_ready`, `clock_ready` ni `request`, y el host no registra `applied`.

## 4. Bloque 2: el fallo del usuario

Driver del invitado: agarra la caja 1 por su centro de masa (`anchor = (0, 0,2, 0)`), la lleva a una pose con el punto más bajo a la altura `h` y la estabiliza. **Estable** = durante 20 ticks seguidos, en el cuerpo predicho y en la última muestra autorizada: centro de masa a ≤ 1 mm del objetivo, `|lv| < 5 mm/s` y, en el predicho, `|av| < 0,02 rad/s`. Después suelta sin impulso o lanza.

| Caso | Preparación |
| --- | --- |
| `drop020`, `drop050`, `drop100` | Caja en x = −0,5, z = 0; `h` = 0,2, 0,5 y 1 m; suelta quieta |
| `lateral050` | `h` = 0,5; el objetivo se mueve a 1,5 m/s hacia −x durante 24 ticks y se suelta en movimiento |
| `throw050` | `h` = 0,5; `request_throw(normalize(−1; 0,3; 0))` |

Cada caso corre dos veces: `clean` (sin degradación) y `degraded` (`--one-way-ms=100 --jitter-ms=40 --loss=0.05` en ambos procesos, semilla de aplicación 12345). Se registran RTT de la aplicación (`rtt_ms`) y RTT/pérdida de ENet (`ENetPacketPeer`).

| Id | Criterio | `clean` | `degraded` |
| --- | --- | --- | --- |
| C1 | Divergencia física del mismo tick antes del primer contacto del host: ≤ 2 mm y ≤ 0,3° | falla | se informa con su causa |
| C2 | Primer contacto: misma diferencia de ticks ≤ 1 | falla | se informa |
| C3 | Elevación posterior del invitado (física y dibujo) − la del host ≤ 2 mm, centro de masa y punto más bajo | falla | falla |
| C4 | Ascenso artificial A1 ≤ 2 mm | falla | falla |
| C5 | Ninguna corrección del cuerpo predicho > 2 mm o > 0,3° | falla | falla, con causa |
| C6 | Hay traspaso a réplica antes del final y su salto visible es ≤ 2 mm y ≤ 0,3°; el instante mostrado no retrocede | falla | falla |
| C7 | Impulsos: +1 en host e invitado por lanzamiento, 0 por suelta | falla | falla |
| C8 | Ninguna revisión retrocede en estado, vista o muestras aceptadas | falla | falla |
| C9 | Pose final dibujada contra la final del host ≤ 2 mm y ≤ 0,3° | falla | falla |
| C10 | Suelta aplicada en `requested + 1`, sin `late` | falla | se informa |
| C11 | Energía de la caja suelta: ningún aumento > 0,04 J en el invitado que no exista en el host | falla | falla |

C9 es necesaria pero no suficiente: una convergencia final no compensa fallar C3–C6.

## 5. Bloque 3: límites del modelo

| Caso | Qué hace | Éxito / fallo |
| --- | --- | --- |
| `stack` | Suelta la caja 1 desde 0,3 m sobre la caja 2 quieta | C1–C11; además se registra en qué instante remoto se colocó el proxy y su error contra el host en el tick del predictor |
| `push` | Con la caja 1 sostenida a 1,5 cm del piso, el objetivo avanza 1 m a 1 m/s contra la caja 2 y después se suelta | C3–C11; falla si hay ≥ 2 correcciones > 2 mm durante el contacto ("correcciones repetidas") o un aumento de energía > 0,04 J en el invitado ausente en el host |
| `moving` | El host mueve la caja 2 a 1 m/s por debajo de la caja 1; el invitado la suelta encima | igual que `push`; se mide el retraso del proxy en ticks y su error espacial |
| `wall` | La caja 1 (invitado) y la 2 (host) se aprietan contra la pared de 2 cm, giran 90° en contacto y se empujan hacia el rincón con el piso; luego se sueltan | Falla si: alguna esquina pasa `z < −3,01` o el centro de masa pasa `z < −2,99` (cruce); penetración física o dibujada > 2 mm en pared o piso; el dibujo interpolado de la caja 2 en el invitado penetra > 2 mm aunque el host no lo haga |
| `throw_wall` | Lanza la caja 1 contra la pared desde 1,3 m | cruce o penetración > 2 mm; C7 |
| `release_before_ack` (`clean` y `degraded`) | Agarra y pide soltar en el tick siguiente | Se cuantifica la espera hasta la suelta local. Criterio de respuesta inmediata: ≤ 1 tick. El README declara que no se cumple: se informa como pendiente, no se rebaja |
| `throw_before_ack` | Agarra y lanza en el tick siguiente con dirección `normalize(−1; 0,3; 0)` | La dirección aplicada en host e invitado difiere < 1° de la pedida; un dueño; un impulso |
| `late_release` | Invitado `--one-way-ms=150`, host 0, sin jitter ni pérdida: demora asimétrica dirigida del evento de salida. Caída de 0,5 m | Se mide el atraso aplicado. C3–C9 y C11 como en `degraded` |
| `dup_throw` | Lanzamiento; reenvío del mismo comando al tick siguiente, después del ACK y después de 300 rechazos que expulsan la caché | Impulsos del host = 1; revisión +1; el duplicado tardío no se ejecuta |
| `stale_snapshot` | El host reenvía tres veces un snapshot `HELD` previo a la suelta después de aplicarla | Ninguna revisión retrocede, ningún salto visible > 2 mm, ninguna reconciliación con esa muestra |
| `disconnect_holding` | El invitado cierra ENet mientras sostiene | El host libera una vez (`auto_release`), dueño 0, revisión +1, impulsos sin cambio, la caja cae y no recibe más objetivos |
| `grab_rejected` | El host sostiene y mueve la caja 2; el invitado intenta agarrarla | Rechazo; ningún predictor queda activo; durante el resto del agarre del host, el dibujo de la caja 2 en el invitado sigue la física del host (error ≤ 2 mm en el instante mostrado más el atraso de interpolación declarado); salto al rechazo ≤ 2 mm |

Clasificación de cada fallo: **bloquea el modelo** (requiere cambiar el modelo de predicción/corrección/traspaso), **bloquea la migración** (defecto de implementación corregible sin cambiar el modelo) o **prestación fuera de esta fixture** (límite declarado que el laboratorio ya cubre o que todavía no corresponde). Ninguno de estos casos cubre inventario, pilas, varias islas ni el catálogo.

### Agregado antes de ejecutar `late_release_hitch` (2026-11-16 11:45)

`late_release` con `asym` (invitado 150 ms, host 0) se aplicó a tiempo. No es un ajuste del criterio: el reloj del invitado fija `desired = est + ⌈RTT/2⌉ + 2`, con `est = tick_del_pong + RTT/2`; con demora invitado→host `c` y host→invitado `h`, el adelanto resulta `c + 2` ticks para cualquier `c`/`h`, así que una demora fija siempre llega 2 ticks antes. El caso dirigido pasa a `late_release_hitch`: sin degradación, el invitado se bloquea 200 ms en el nodo `Post` del mismo tick de la suelta, después de que el adaptador la ejecutó localmente y antes de su `_process`, que es donde envía. Mismos criterios que `late_release` (C3–C9 y C11 deciden; se mide el atraso aplicado).

## 6. Ejecución

- Un caso por corrida, host e invitado como procesos separados con `validation/run_case.ps1`. Límite externo de **20 s** desde el arranque del host; preparación ≤ 6 s (invitado listo) y ≤ 4 s (host arrancado). Al vencer: se terminan solo los PID propios, se informa y se corrige el driver o se reporta el runtime.
- Cada rol escribe su traza del adaptador y la del driver en `tmp/validacion_objetos/<corrida>/`. El verificador `validation/analyze.mjs` lee solo esos archivos.
- Si un criterio falla en la primera corrida, se investiga ese fallo antes de lanzar otra semilla o repetir la batería. No se cambian umbrales después de observar resultados.
