# Criterios fijados antes de ejecutar: verificación de la entrega 2

Escrito por Claude el 2026-11-16, **antes de correr cualquier caso de la entrega 2**. Se commitea solo, sin resultados ni código de prueba nuevo. Base: `3110cad160c5c3a2bc4102dfbb5c87ccff92a9b2`, incorporada a `objetos/validacion` por avance directo desde `5a5d92f` con `git fetch --no-tags ..\implementacion objetos/implementacion` y `git merge --ff-only FETCH_HEAD`. La entrega no modificó `validation/` ni los criterios de la entrega 1. Los hashes de los archivos de runtime coinciden con `..\entrega_2.json`.

Encargo: `docs/net/entregas/revision_codex_entrega_1.md`, sección "Encargo de revisión para Claude".

## 1. Qué no cambia

- **Tolerancias:** las de `criterios_entrega_1.md` §1, sin excepción: 2 mm, 0,3°, 0,04 J, ±1 tick, 10⁻⁵ m de cinemática de un paso.
- **Criterios de la entrega 1:** C1–C11, P1–P5, R1–R4, K1–K3, D1–D2, S1, X1, G1–G2, con el mismo código del verificador. Las comprobaciones nuevas se agregan, no reemplazan ninguna.
- **P5:** se deja como está. Su banda de amortiguación quedó reconocida como mal planteada en la entrega 1 (§5 del informe). Sus fallos se informan como error conocido del verificador y no deciden el dictamen, igual que en la entrega 1. No se corrige en esta verificación.
- **Casos que no se repiten:** `stack`, `push`, `moving`, `wall`, `throw_wall`, `drop020`, `drop100`, `lateral050`, `drop050_slow03`, `drop050_stall` y `late_release` no se vuelven a correr. Codex pidió no repetir las 29 corridas. Los proxies cinemáticos no cambiaron salvo el registro nuevo: su dictamen de la entrega 1 (modelo no aprobado) se mantiene por identidad de código. Se verifica con el diff de `_sync_proxies` y `set_proxy`, no con una corrida.

## 2. Qué se agrega al instrumento (antes de correr, sin mirar resultados)

- **Driver:** el registro `pp` suma el estado autorizado que guarda el adaptador en cada objeto: tick (`stk`), posición (`sp`), velocidad lineal (`slv`) y revisión del estado predicho (`psrev`). La operación `grab` admite `stall_post_ms`, igual que `release`. Hay tres casos nuevos (§4).
- **Verificador:** comprobaciones nuevas de §3. Las existentes no cambian.
- **Contrato:** `contract_test_e2.gd` (nuevo) ejercita los caminos nuevos de `authority.gd`. `fingerprint_test.gd` (nuevo) prueba que la huella dependa de la configuración real. `contract_test.gd` no se toca.

## 3. Criterios por hallazgo

### F2: el agarre respeta el tick pedido

| Id | Criterio | Decide |
| --- | --- | --- |
| `A10` (contrato original) | Un agarre con tick mayor que `ahora + 60` se rechaza | sí |
| `B01` | Un agarre a tiempo (tick 60, ahora 55) se aplica en 61, no antes; `late = false` | sí |
| `B02` | Un agarre con tick pasado se aplica ahora y se marca `late = true` | sí |
| `B03` | Tick `ahora + 60` queda pendiente; `ahora + 61` se rechaza con `future` | sí |
| `F2_agarre_alineado` | Host aplica el agarre en el mismo tick en que el invitado lo ejecuta: `applied_tick = local_tick = requested_tick + 1`, `late = false` | `clean`, salvo `late_grab_hitch` |
| `F2_marca_tarde_coherente` | Para toda acción aplicada: `late = (applied_tick > requested_tick + 1)` | siempre |
| `H1_agarre_mismo_tick` | Durante el agarre del invitado (desde el último de los dos ticks de inicio hasta el tick anterior a la salida), la física del host y la del invitado en el mismo tick difieren ≤ 2 mm y ≤ 0,3° (centro de masa y giro) | `clean`, salvo `late_grab_hitch` (se informa) |
| `H2_inicio_de_la_salida` | En el último tick sostenido antes de la salida, misma diferencia ≤ 2 mm y ≤ 0,3° | casos con `stable` antes de soltar, con o sin degradación |

Se informan, sin decidir: fracción de pasos del host sostenidos por el invitado con `input_tick = step_tick` en el registro `controller`, y conteo y máximo de `reconcile` con `model_blocked`.

**Motivo de H1/H2:** la entrega 2 retiró la corrección. Una divergencia durante el agarre ya no se mueve, así que no puede convertirse en "pasa" por dejar de corregir. Con la red limpia, el agarre tiene que ser el mismo en los dos lados desde el primer tick.

### F6: el estado guarda solo muestras autorizadas

| Id | Criterio | Decide |
| --- | --- | --- |
| `F6_estado_solo_autorizado` | Cada combinación (objeto, revisión, tick) que el invitado tiene en `state`, con el invitado listo, es una muestra del host: una captura `physics` o el `initial` de un `applied` del mismo objeto, tick y revisión, con posición igual ≤ 10⁻⁶ m. Si el host no registró ese tick, la combinación se cuenta aparte y se informa | siempre |
| `G1`, `G2` | Sin cambios (`grab_rejected`) | sí |
| `J1_rechazos` | `throw_rejected`: el agarre y el lanzamiento reciben `rejected`, se registra un `dependent_cancelled` y no hay capturas predichas de la caja 2 después del último rechazo | sí |
| `J2_host_sin_efecto` | `throw_rejected`: ningún `applied` del host para acciones del invitado; impulsos de la caja 2 en el host sin cambios; dueño de la caja 2 en el host siempre el host desde su agarre | sí |
| `J3_replica_sigue_al_host` | `throw_rejected`: misma medida que G2 sobre la caja 2 | sí |

Se informa, sin decidir: desplazamiento predicho de la caja 2 antes del rechazo (el salto de vuelta es propio de predecir un agarre disputado).

### F7: salida antes del ACK

En `release_before_ack` y `throw_before_ack`, `clean` y `degraded`:

| Id | Criterio | Decide |
| --- | --- | --- |
| `K1` | Ejecución local ≤ 1 tick después del pedido | siempre |
| `K2` | Dirección física del lanzamiento < 1° de la pedida, host e invitado | siempre |
| `K3` | Un solo dueño | siempre |
| `C1`–`C11` | Como en la entrega 1 (C1, C2 y C10 deciden solo en `clean`) | según tabla original |
| `F7_misma_accion` | La acción ejecutada localmente es la que registró el driver y la que aplica el host; su ID es el del agarre + 1 | siempre |
| `F7_dependencia_registrada` | Un `dependent` con la dirección pedida (diferencia ≤ 10⁻⁶) y después un `dependent_confirmed` con la misma acción; ningún `dependent_cancelled` | siempre |

### F10

| Id | Criterio | Decide |
| --- | --- | --- |
| `F10_ack_velocidad_de_salida` | Para cada lanzamiento aplicado: `initial.lv` del `applied` = `lv` de la captura del host en `applied_tick − 1` + (16 N·s / 2 kg)·dirección pedida, ≤ 10⁻⁴ m/s (término absoluto de P5; la resolución de float32 a 8 m/s es ~10⁻⁶). Si el invitado tuvo en `state` esa misma revisión y tick, su `slv` es igual ≤ 10⁻⁶ m/s; si no se observó, se informa | `throw050`, `throw_before_ack`, `dup_throw` |
| `F10_etiqueta_dibujo_predicho` | En todo dibujo predicho cuya pose coincide (≤ 10⁻⁷ m) con una captura del propio invitado, el instante declarado (`shown_tick`) es el tick de esa captura | casos con predicción |
| `F10_huella_*` | `fingerprint_test.gd`: dos instancias con la misma configuración dan la misma huella; cambiar en tiempo de ejecución, antes de instanciar, `physics/3d/default_gravity`, `physics/3d/default_linear_damp` o `physics/jolt_physics_3d/simulation/penetration_slop` da otra huella (cada uno decide) | sí |
| `R4` | Sin cambios (`fingerprint_mismatch`) | sí |
| `X1` | Sin cambios (`disconnect_holding`): incluye que el host no consuma objetivos después de la desconexión | sí |
| `D3_respuesta_al_duplicado_viejo` | `dup_throw`: después del duplicado posterior a la expulsión de la caché, el invitado recibe un `result` `stale` para la acción del lanzamiento y ningún `accepted` nuevo | sí |

### Revisiones, idempotencia y preparación sin debilitar

- `contract_test.gd` original: las 74 comprobaciones pasan.
- `contract_test_e2.gd`, además de B01–B03:
  - `B04`: una salida pedida mientras el agarre del mismo peer y sesión está pendiente queda pendiente. Se aplica después del agarre, en `max(ahora, tick + 1)`, con revisión +1 en cada paso y estado final libre.
  - `B05`: si el agarre y su salida vencen en el mismo tick, dos `commit` en ese tick devuelven primero el agarre y después la salida.
  - `B06`: se rechaza con `ownership` una salida de otro peer mientras hay un agarre pendiente.
  - `B07`: se rechaza con `ownership` una salida de otra sesión mientras hay un agarre pendiente.
  - `B08`: el mismo comando de salida reenviado mientras está pendiente responde `pending` sin crear un segundo trabajo. Una segunda salida distinta se rechaza con `pending`. El duplicado posterior al commit devuelve el resultado guardado sin cambiar la revisión.
  - `B09`: desconectar con agarre y salida pendientes vacía ambos sin cambiar la revisión, y ningún commit posterior aplica nada.
  - `B10`: después de un agarre rechazado (`occupied`), su salida se rechaza con `ownership` y no crea trabajo.
  - `B11`: se rechaza con `future` una salida pendiente de un agarre pero con tick mayor que `ahora + 60`.
  - `B12`: una salida con tick menor que el de su agarre nunca se aplica antes que el agarre.
  - `B13`: una acción vieja (ID ≤ último recibido) sigue siendo `stale` aunque haya trabajos pendientes.
- Por red: `C8` en todas las corridas, `D1`–`D3` en `dup_throw`, `S1` + `C8` en `stale_snapshot`, `R1`–`R3` en `ready_gate`, `P1`–`P4` en todas.

### Caso tardío

`late_release_hitch` (`clean`) corre una vez con los criterios originales. Si C1, C2 o C10 fallan, se registran como fallo: no se reinterpretan como aceptables porque el traspaso no salte. C4 y C6 se informan con su valor.

## 4. Casos nuevos

| Caso | Qué hace | Criterios que deciden |
| --- | --- | --- |
| `grab_move` | Agarra la caja 1 a 0,7 m y desde el tick siguiente mueve el objetivo a 1 m/s en +x durante 30 ticks; estabiliza y suelta | H1, H2, F2, C1–C11 (`clean`) |
| `late_grab_hitch` | Como `drop050`, pero el invitado se bloquea 200 ms en `Post` en el tick del agarre, después de ejecutarlo localmente y antes de enviarlo | `F2_marca_tarde_coherente` y agarre marcado `late`; H2; C1–C11 (`clean`); H1 se informa |
| `throw_rejected` | El host sostiene y mueve la caja 2 (mismo guion que `grab_rejected`); el invitado la agarra y lanza en el tick siguiente | J1–J3 |

## 5. Corridas previstas

Una por caso, en este orden, sin baterías paralelas: contrato original, `contract_test_e2`, `fingerprint_test`; `drop050` (`clean`, `degraded`), `grab_move`, `late_grab_hitch`, `throw050`, `release_before_ack` (`clean`, `degraded`), `throw_before_ack` (`clean`, `degraded`), `grab_rejected`, `throw_rejected`, `dup_throw`, `stale_snapshot`, `disconnect_holding`, `ready_gate`, `fingerprint_mismatch`, `late_release_hitch`. Degradación: `--one-way-ms=100 --jitter-ms=40 --loss=0.05`, semilla 12345. Límite externo de 20 s por caso, tiempo real, sin `--fixed-fps`.

Si un criterio falla, se investiga ese fallo con las trazas antes de repetir. Una segunda corrida del mismo caso solo se hace para separar un error del instrumento de uno del runtime, y las dos se informan.

### Agregado antes de ejecutar `grab_move_left` (2026-11-16 13:40)

En `grab_move` (`20261116_133351`) el objetivo termina en x = 0 y la caja 1 cae sobre la arista de la caja 2, que descansa en x = 0,5: los rangos en x se superponen 0,1 m. El caso pretendía una caída aislada, así que es un error de diseño del caso. Se conserva la corrida y sus fallos (C3, C4, C6, C9, C11), sin cambiar criterios. Para separar el agarre del contacto con la otra caja se agrega `grab_move_left`, igual a `grab_move` pero moviendo el objetivo hacia −x: la caja cae en x = −1, lejos de la caja 2 y de la pared. Lo deciden los mismos criterios que `grab_move`.
