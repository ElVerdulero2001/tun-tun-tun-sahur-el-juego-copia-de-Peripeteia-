# Criterios fijados antes de ejecutar: verificación de la entrega 3

Escrito por Claude el 2026-11-16, **antes de correr cualquier prueba de la entrega 3**. Se commitea junto con los instrumentos nuevos, sin resultados.

Base: `d3471012d3ccb44a8ef081d312b2cabb7fcf3e83`. Se incorporó a `objetos/validacion` por avance directo desde `8a81339`, con `git fetch --no-tags ..\implementacion objetos/implementacion` y `git merge --ff-only FETCH_HEAD`. Antes, solo `tmp/` estaba sin versionar y no había cambios de código pendientes.

Contra `..\entrega_3.json` coinciden 15 de 16 hashes. El otro es `docs/net/entregas/resultados_codex_entrega_3.json`: la copia de Codex tiene CRLF y la de Git, LF (`eol: lf`), y el contenido es idéntico al normalizar los finales de línea. La entrega no modificó `driver.gd`, `analyze.mjs`, `contract_test_e2.gd` ni `fingerprint_test.gd`: sus hashes coinciden con los de `8a81339`.

Encargo: `docs/net/entregas/revision_codex_entrega_2.md`, sección "Encargo acotado para Claude".

## 1. Qué no cambia

- **Tolerancias:** las de `criterios_entrega_1.md` §1 y `criterios_entrega_2.md`: 2 mm, 0,3°, 0,04 J, ±1 tick, 10⁻⁴ m/s.
- **Criterios anteriores:** todas las comprobaciones existentes del verificador siguen igual. Las nuevas se agregan.
- **P5:** sigue como error conocido del verificador; no decide.
- **Casos que no se repiten:** los de contacto entre cajas, pared y suelta tardía. La entrega 3 no cambió ese código, así que su dictamen se mantiene: suelta tardía con fallo registrado y contactos dinámicos sin aprobar.

## 2. Tolerancias nuevas, derivadas de la resolución

- **Igualdad de objetivo de mano entre host e invitado:** ≤ 10⁻⁶ m por componente de posición. El objetivo viaja como float32 y el host lo acepta hasta 20 m del origen. Ahí un ULP de float32 vale 2⁻¹⁹ m ≈ 1,9·10⁻⁶ m, y el redondeo es medio ULP: ≈ 9,5·10⁻⁷ m.
- **Ida y vuelta del giro por el formato:** ≤ 10⁻⁶ rad entre el giro original y el decodificado. El cuaternión viaja en float32 (ε ≈ 1,2·10⁻⁷ por componente); el ángulo resultante queda por debajo de unos 5·10⁻⁷ rad con las conversiones base↔cuaternión.
- **Igualdad dentro del proceso:** las pruebas sin red comparan objetivos con igualdad exacta. La bandeja guarda una copia del valor recibido; no hay cálculo intermedio que justifique otra tolerancia.

## 3. Instrumentos nuevos o cambiados (antes de correr, sin mirar resultados)

- **`validation/hand_input_test.gd` (nuevo):** formato binario, con bytes armados a mano (§4.1).
- **`validation/hand_timeline_test.gd` (nuevo):** la bandeja sola (§4.2).
- **`validation/hand_adapter_test.gd` (nuevo):** `main.tscn` en modo solo, sin red, con entradas y órdenes inyectadas en `_inbound` como lo hace el RPC (§4.3).
- **`validation/response_receiver_test.gd` (nuevo):** el receptor de respuestas con respuestas malformadas (§4.4).
- **`validation/run_case.ps1`:** perfil nuevo `lossy`: `--one-way-ms=100 --loss=0.05` en los dos procesos, sin jitter. Es `degraded` sin jitter, para separar pérdida de llegada tardía. Los otros perfiles no cambian.
- **`validation/analyze.mjs`:** un bloque nuevo "entrega 3" (§5) y la opción `--out=<archivo>`, para analizar trazas viejas sin sobrescribir su `analysis.json`. Lo anterior no cambia.

Todas corren con el Godot 4.7.2 del escritorio, `--headless`, tiempo real, sin `--fixed-fps` y con un límite externo de 20 s. Cualquier línea `SCRIPT ERROR` o `ERROR` en la salida (salvo el aviso conocido de certificados raíz) es un fallo de la prueba.

## 4. Pruebas sin red

### 4.1 `hand_input.gd`

Los bytes se arman a mano. Los enteros van en little-endian con desplazamientos de bits; los float32 se escriben con `PackedByteArray.encode_float`.

| Id | Criterio | Decide |
| --- | --- | --- |
| `I01_disposicion` | `encode` de un registro da 48 bytes: cabecera `49 48 01 01`; objeto, aparición, sesión y tick en u32 LE en los desplazamientos 4–19; posición float32 en 20–31; cuaternión en 32–47, igual al giro (con signo libre) | sí |
| `I02_decodifica_bytes_a_mano` | Un paquete armado a mano se decodifica con los mismos identificadores y la misma posición (valores representables exactos) y un giro a ≤ 10⁻⁶ rad | sí |
| `I03_cantidades` | Cantidad 0 → `[]`; 1 → 1 registro; 6 (268 bytes) → 6; 7 con 312 bytes → `[]`; cabecera que dice 7 con 268 bytes → `[]` | sí |
| `I04_tamanios` | 3 bytes, 47 y 49 bytes para cantidad 1, cantidad 2 con 48 bytes y 269 bytes → `[]` | sí |
| `I05_magia_y_version` | Magia con los bytes invertidos, versión 0 o versión 2 → `[]` | sí |
| `I06_identificadores` | Objeto, aparición o sesión en 0, `0x80000000` o `0xFFFFFFFF` → `[]`; en `0x7FFFFFFF` → aceptado. Tick 0 y `0x7FFFFFFF` → aceptados; `0x80000000` → `[]` | sí |
| `I07_posicion_no_finita` | NaN, +∞ o −∞ en cualquiera de los tres ejes → `[]` | sí |
| `I08_cuaterniones` | NaN, ∞, cero, (0,0,0,2) y (0,0,0,1,1) → `[]`. Un unitario con redondeo de float32 se acepta, y la base que resulta es ortonormal | sí |
| `I09_un_registro_invalido` | Seis registros con uno inválido → `[]` entero | sí |
| `I10_maximo` | `MAX_PACKET_BYTES = 268`, `encode` de 6 registros da 268 bytes y `encode` de 1 da 48 | sí |
| `I11_codificador_rechaza` | `encode` devuelve vacío para: lista vacía, 7 registros, NaN, ∞, base escalada, base de determinante 1 no ortonormal, objeto/aparición/sesión 0, tick −1, tick float, identificador > `0x7FFFFFFF`, clave faltante, clave de más y elemento que no es diccionario | sí |
| `I12_ida_y_vuelta` | 1000 conjuntos aleatorios válidos (1 a 6 registros, posición en ±20 m): identificadores y ticks exactos, posición ≤ 10⁻⁶ m, giro ≤ 10⁻⁶ rad | sí |
| `I13_orden` | `decode` conserva el orden del paquete | informativo |
| `I14_tick_repetido_en_un_paquete` | Qué hace `decode` con dos registros del mismo tick | informativo |
| `I15_fuzz` | 3000 arreglos aleatorios (0 a 300 bytes) y 3000 paquetes válidos con un byte cambiado: sin errores, y toda salida no vacía tiene de 1 a 6 registros que pasan `valid()` | sí |
| `I16_rotacion_de_main_codificable` | Se aplica a una base, empezando por la identidad, la misma fórmula de `main.gd` `_unhandled_input` (rueda central más mouse): `Basis(UP, −dx·0,004) * B` y luego `Basis(eje_x_cámara, −dy·0,004) * B`, con deltas fijos. Durante 20.000 eventos el objetivo sigue siendo codificable (`HandInput.valid`). Motivo: 20 s de rotación continua a 1000 Hz dentro de un mismo agarre. Si `encode` lo rechaza, `main.gd` deja de enviar la mano sin registrarlo | sí |
| `I16b_asimetria_con_la_orden` | Una base de determinante 1 que no es ortonormal: qué dicen `Authority.valid_command` (agarre) y `HandInput.valid` (mano). Se informa también el primer evento en que I16 falla, si falla, hasta 200.000 | informativo |

### 4.2 `hand_timeline.gd`

| Id | Criterio | Decide |
| --- | --- | --- |
| `L01_antes_de_la_concesion` | Una entrada sin agarre concedido queda `buffered`; `consume` con la clave exacta la devuelve | sí |
| `L02_orden_inverso` | Llegan 105, 104 y 103; `consume` en 103, 104 y 105 (último usado = anterior) devuelve 103, 104 y 105 | sí |
| `L03_la_mas_reciente` | Con 101, 102 y 103, `consume(103, último 100)` devuelve 103; 101 y 102 no aparecen después | sí |
| `L04_nunca_futura` | Con 110, `consume(105)` → vacío; `consume(110)` → 110 | sí |
| `L05_nunca_ya_usada` | Con 100, `consume(105, último 100)` → vacío | sí |
| `L06_duplicado` | El mismo tick con el mismo objetivo → `duplicate`, una sola entrada | sí |
| `L07_conflicto` | El mismo tick con otro objetivo → `conflicting_tick`; `consume` devuelve el primero | sí |
| `L08_claves_ajenas` | Otro peer, objeto, aparición o sesión no consumen la entrada; la clave correcta sí | sí |
| `L09_ventana` | Con ahora 200: 80 y 260 → `buffered`; 79 y 261 → `outside_window` | sí |
| `L10_caducidad` | Una entrada del tick 300 sigue en 420 y no está en 421 | sí |
| `L11_capacidad_de_sesiones` | Cuatro sesiones del peer 2 → `buffered`; la quinta → `capacity`; otro tick de una sesión existente → `buffered` | sí |
| `L12_capacidad_de_peers` | Peers 2 y 3 → `buffered`; peer 4 → `capacity` | sí |
| `L13_capacidad_liberada` | Retirar una de las cuatro sesiones deja entrar la quinta | sí |
| `L14_retiro` | Después de `retire`: `accept` → `retired` y `consume` → vacío; otra sesión del mismo peer no se afecta | sí |
| `L15_caducidad_del_retiro` | Retirado en 700: en 820 sigue `retired` y en 821 se acepta otra vez | informativo |
| `L16_limite_de_retirados` | Con 300 retiros, la lista de retirados no supera 256 | sí (el primer retirado expulsado se informa) |
| `L17_desconexion` | `drop_peer(2)` borra lo del peer 2 y no lo del peer 3 | sí |
| `L18_invalidas` | Peer 0 o −1, objeto 0, clave faltante o NaN → `invalid` | sí |
| `L19_reenvio_de_un_tick_usado` | Se consume 103 y vuelve a llegar 103 con el mismo objetivo. Físico: `consume(104, último 103)` no lo devuelve. Diagnóstico: el estado es `duplicate`, como dice el contrato ("distingue duplicado") | ambos sí; el diagnóstico se informa aparte como "sin efecto físico" |
| `L20_conflicto_de_un_tick_usado` | Lo mismo con otro objetivo: físico, no se devuelve. Se informa su estado | físico sí; estado informativo |
| `L21_memoria_acotada` | 20.000 entradas aleatorias (peers 2–5, objetos 1–3, aparición 1–2, sesiones 1–10, ticks de ahora−200 a ahora+100, el reloj avanza): nunca más de 8 claves ni más de 181 ticks por clave | sí |
| `L22_vista_de_inspeccion` | Vaciar el diccionario de `pending_for` no cambia la bandeja | sí |
| `L23_consumir_borra_lo_pasado` | Después de `consume(103)`, `pending_for` solo tiene ticks > 103 | informativo |
| `L24_copia_inmutable` | Cambiar el diccionario original después de `accept` no cambia lo guardado | sí |

### 4.3 Adaptador en `main.gd` (modo solo, sin red)

Un nodo de prioridad −10 inyecta antes de cada paso. Las entradas van a `main._inbound` como `{"kind": "hand_inputs", "peer", "frames"}`, igual que el RPC después de decodificar. Las órdenes van como `{"kind": "command"}`, la desconexión como `{"kind": "disconnect"}`. Otro nodo de prioridad +10 lee `body.goal`, `last_goal`, el estado de la autoridad, la bandeja y las respuestas que quedan en `main._wire`. Caja 1 y caja 2, aparición 1. Los objetivos inyectados son distintos entre sí: X(t) para el peer 2 en la sesión 50, y otras marcas para cada clave ajena.

| Id | Criterio | Decide |
| --- | --- | --- |
| `A00_bandeja_previa` | Todas las entradas inyectadas antes del agarre quedan `buffered` | sí |
| `A01_libre_sin_efecto` | Con la caja libre, nada cambia `body.goal` ni se registra `controller` | sí |
| `A02_primer_paso_concedido` | Agarre del peer 2 pedido en 40: se aplica en 41 y ese mismo paso usa X(41), recibida antes de la concesión. Así se reemplaza el objetivo del GRAB | sí |
| `A03_solo_la_clave_concedida` | En los pasos sostenidos, `body.goal` es siempre X(t) del peer 2, sesión 50, aparición 1. Nunca las entradas del peer 3, de la sesión 51, de la aparición 2 ni de los ticks ≤ 40 | sí |
| `A04_respaldo` | Sin entradas para 61 y 62: el objetivo sigue en X(60), `fallback = true` | sí |
| `A05_entrada_tardia` | Llegan tarde 61 y 62: el paso 63 usa la más reciente (62), con `fallback = true`; no se inventa ningún objetivo | sí (registra el comportamiento de una entrada tardía) |
| `A06_accion_local_del_host` | Agarre propio del host pedido en 45: `applied_tick = 46`, `late = false` | sí |
| `A07_mano_ajena_sobre_caja_del_host` | Entradas de los peers 2 y 3 con la sesión del host sobre la caja 2: nunca cambian su objetivo, que sigue siendo `main.target` | sí |
| `A08_rechazo_retira` | El agarre del peer 3 rechazado (caja ocupada) retira su sesión: `pending_for` queda vacío, sus entradas posteriores dan `retired`, y la caja 1 sigue con X(t) | sí |
| `A09_repeticion_vieja_no_retira` | 300 órdenes falsas expulsan de la caché el agarre 50. Su repetición recibe `stale` y la sesión activa sigue: las entradas reenviadas dan `duplicate` (no `retired`) y el objetivo sigue con X(t) | sí |
| `A10_respuestas_bien_formadas` | Toda respuesta que el host deja en `_wire` cumple `Authority.valid_response`. La respuesta a la repetición vieja nombra la acción 50 y el objeto 1 | sí |
| `A11_suelta_retira` | Suelta del peer 2 en 110, aplicada en 111: caja libre, entradas posteriores `retired`, sin `controller` | sí |
| `A12_otro_dueno` | Agarre del peer 3 (sesión 200) aplicado en 117: usa sus entradas V(t) | sí |
| `A13_desconexion` | Desconexión del peer 3: caja libre en 126, la bandeja sin claves del peer 3, sin `controller` después. Se informa el estado de sus entradas posteriores | sí |
| `A14_ningun_objetivo_inventado` | En cada paso sostenido de cualquier caja, `body.goal` es el objetivo del agarre (último usado −1) o una entrada recibida de la clave concedida, con tick = último usado ∈ (tick pedido, paso] | sí |

### 4.4 Receptor de respuestas (`main._receive_result`, modo solo)

Antes, se fijan en el adaptador un agarre pendiente artificial (`_pending_grab = 999`, caja 1, `pending = 999`). Se toma una huella del estado: pendientes, `local_uid`, dependiente y, por caja, estado, predicho, `pending`, predicción, agarre e impulsos. Por respuesta se compara la huella antes y después. Al final se cierra `main` y se leen los registros de la traza en orden.

| Id | Criterio | Decide |
| --- | --- | --- |
| `M01`–`M23` | Cada respuesta malformada no cambia la huella y deja un `discarded_result` (ningún `result`). Son: vacía; `{"status": "stale"}` (la de N1); sin `uid`; sin `action`; `action` 0, −1, float, texto; `uid` 0, `0x80000000`, float; estado `pending` o numérico; `accepted` sin `state`, con `state` vacío, de 89 bytes, de 90 ceros, de la caja 2, con otra acción o como Array; `reason` numérico; `late` de texto; estado con cuaternión NaN | sí |
| `V1_objeto_inexistente` | Bien formada para el objeto 99: se registra `result` y la huella no cambia | sí |
| `P1_control_rechazo` | Bien formada `rejected` de la acción 999 de la caja 1: el agarre pendiente pasa a 0. Demuestra que la huella detecta efectos | sí (control) |
| `P2_control_aceptado` | `accepted` coherente (caja 1, acción y revisión nuevas): `state.revision` cambia | sí (control) |
| `E0_sin_errores` | La salida del proceso no tiene `SCRIPT ERROR` ni `ERROR` | sí |

### 4.5 Contrato anterior sobre el hash final

`contract_test.gd`, `contract_test_e2.gd` y `fingerprint_test.gd`, sin cambios, sobre `d347101`. Esperado: 74, 13 y 5 aprobados.

## 5. Comprobaciones nuevas en red (`analyze.mjs`, bloque entrega 3)

U es la caja del agarre del invitado. La ventana común son los pasos en que hay `controller` del host para U con dueño ≠ 1 y `controller` del invitado para U.

| Id | Criterio | Decide |
| --- | --- | --- |
| `D4_respuestas_identificadas` | Todo `result` del invitado tiene `uid` ∈ {1, 2} y `action` ≥ 1; cero `discarded_result` en el invitado | todas las corridas |
| `D5_stale_con_accion_y_objeto` | `dup_throw`: después del último duplicado hay ≥ 1 `stale`, todos con la acción y el objeto del lanzamiento | sí |
| `D6_respuestas_a_la_inundacion` | `dup_throw`: las 300 órdenes falsas reciben 300 `rejected`, todas con el objeto 1 | sí |
| `N2a_entrada_desde_el_primer_tick` | El primer `controller` del host para el agarre del invitado está en el tick en que el host aplicó el agarre, y su `input_tick` es ese mismo tick | `clean` y `lossy` |
| `N2b_mismo_objetivo_mismo_tick` | En la ventana común: el host no usa respaldo (`input_tick = step_tick`) y su objetivo es el del invitado en el mismo paso, ≤ 10⁻⁶ m | `clean` y `lossy` |
| `M1_agarre_con_red` | La misma medida que H1 (2 mm / 0,3°), decidiendo con red degradada | `lossy` y `degraded` |
| `M2_sin_respaldo_con_red` | Cero pasos del host con respaldo en la ventana común | `lossy` y `degraded` |
| `M3_entradas_tardias` | Por tick de la sesión del agarre: primera recepción en el host; tardía si `input_tick ≤ local_tick` al recibirla (su paso ya corrió). Cantidad, atraso máximo y recepciones por tick | informativo |
| `HI1_entradas_validas` | Ningún `discarded` con `invalid_hand_inputs` en el host. Ningún estado `invalid`, `conflicting_tick` ni `capacity` | todas las corridas con entradas |
| `HI2_estados_y_cola` | Cantidad de cada estado de la bandeja, y de `retired` después de la salida | informativo |
| `HL_accion_local_del_host` | Cada acción propia del host (su `request` y su `applied`, emparejados por objeto, operación, acción y tick pedido): `applied_tick = requested_tick + 1`, `late = false` y el mismo paso que el pedido | todas las corridas con acciones del host |

Los fallos de M1/M2 con `degraded` se registran como fallos. No se amplía ninguna tolerancia porque las entradas lleguen tarde.

**Control del verificador antes de las corridas nuevas:** el bloque nuevo se corre con `--out` sobre las trazas de la entrega 2 (`dup_throw` 133622 y `grab_move_left` 133521), sin tocar su `analysis.json`. Tiene que detectar N1 (D4/D5 fallan) y N2 (N2a falla). N2b y HI1 no tienen datos en esas trazas y se informan sin decidir.

## 6. Corridas

En este orden, sin repetir las anteriores:

1. `dup_throw / clean`: N1.
2. `grab_move_left / clean`: N2.
3. `grab_move_left / lossy`: pérdida sin jitter.
4. `grab_move_left / degraded`: pérdida con jitter; entradas tardías.
5. `grab_rejected / clean`: acción local del host (HL), G1/G2 y F6.
6. `throw_before_ack / clean` y `throw_before_ack / degraded`: F6/F7 sin regresión.

`grab_move` hacia la caja 2 no se usa para el movimiento libre. Una corrida que falle por error del instrumento se conserva, se explica y se repite una vez. Una que falle por el modelo no se repite.

## 7. Agregado antes de correrlo: `grab_rotate` (la hora real es la del commit que lo agrega)

`I16` falló sin red: con la fórmula de giro de `main.gd`, el objetivo deja de ser codificable al evento 1263. Por código, `main.gd` saltea el envío cuando `encode` devuelve vacío. Esa consecuencia no se probó: este caso la prueba de punta a punta antes de afirmarla.

- **Driver:** operación nueva `rotate_main`. Cada tick aplica `per_tick` eventos con la misma fórmula y los mismos deltas que `I16`. El eje es `main.camera.global_basis.x`. Después llama a `main.set_goal` con el objetivo nuevo, que es lo que haría `_unhandled_input`. Registra `drv_rot` con los eventos acumulados y si el objetivo es codificable (`HandInput.valid`).
- **Caso `grab_rotate` (invitado):** listo; agarre de la caja 1 en (−0,5; 0,7; 0); `rotate_main` con 16 eventos por tick (mouse de 1000 Hz a 60 Hz) durante 120 ticks, unos 1920 eventos; espera de 30; suelta; espera de 60; fin. El host corre el caso por defecto.
- **Criterios, sin cambios:** deciden `N2b_mismo_objetivo_mismo_tick` y `H1_agarre_mismo_tick` (2 mm / 0,3°) en `clean`. Se informan el primer tick del invitado con objetivo no codificable, el último tick de la sesión recibido por el host y los pasos del host con respaldo.
- **Corrida:** `grab_rotate / clean`, una vez.
