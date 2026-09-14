# Referencia de comportamiento — Parkour V1 (histórico)

> **Qué es este documento.** Especificación de comportamiento *observable* del sistema de parkour V1,
> tal como existía en el commit `bd38e49^` (el padre inmediato de `bd38e49`, "refactor: remove legacy
> interaction and inventory systems" — el commit que borró estos scripts). No es una propuesta de
> arquitectura, no es una comparación con V2, no sugiere fixes ni ports. Es la foto de qué hacía V1,
> para poder decidir después, con esta referencia en mano, qué conservar.
>
> **Método.** Cada afirmación cita archivo y función de V1, y la constante o condición exacta tal como
> aparece en el código. Se etiqueta cada dato como:
> - **HECHO** — se lee directo del código, sin inferencia.
> - **INFERENCIA** — se deduce combinando código con física/matemática estándar (ej. "esto converge
>   exponencialmente porque es un lerp aplicado cada tick"), pero nadie lo *jugó* para confirmarlo acá.
> - **PENDIENTE DE VALIDACIÓN EMPÍRICA** — no se puede saber con certeza leyendo el código; requiere
>   abrir el editor y probarlo (o no es reconstruible en absoluto porque depende de un input humano
>   específico, timing de red, o similar).
>
> Nada de este documento usa V2 para completar huecos. Donde el código de V1 no alcanza para saber algo,
> queda marcado como pendiente, no inventado.
>
> **Fuentes**: `git show bd38e49^:"scripts/player n entities/movement/player.gd"`, `movement_controller.gd`,
> `parkour_detector.gd`, `traversal_controller.gd`, `traversal_segment.gd` (todos bajo esa misma carpeta).
> Archivos auxiliares revisados y descartados por no ser relevantes al parkour: `kick_controller.gd`
> (golpear objetos, no interactúa con traversal), `visuals/free_camera.gd` (cámara de debug desconectada
> del jugador real), `visuals/debug_ui.gd` y `visuals/debug_traversal.gd` (overlays de texto, solo lectura),
> `visuals/marco_enfoque.gd` (UI 2D de interacción, no traversal).

---

## 1. Locomoción

Fuente: `scripts/player n entities/movement/movement_controller.gd` (nodo `MovementController`,
hijo de `player.gd`) y `scripts/player n entities/movement/player.gd`.

### 1.1 Constantes

| Constante | Valor | HECHO/INFERENCIA |
|---|---|---|
| `SPEED` | 5.0 | HECHO |
| `RUN_SPEED` | 9.0 | HECHO |
| `CROUCH_SPEED` | 2.5 | HECHO |
| `JUMP_VELOCITY` | 4.5 | HECHO |
| `ACCELERATION` | 14.0 | HECHO |
| `CROUCH_TRANSITION` | 8.0 | HECHO |
| `AIR_CONTROL_FAST` | 0.3 | HECHO |
| `AIR_CONTROL_SLOW` | 1.5 | HECHO |
| `AIR_FRICTION` | 0.8 | HECHO |
| `FALL_FRICTION` | 3.0 | HECHO |
| `MOUSE_SENSITIVITY` (`player.gd`) | 0.003 | HECHO |
| `floor_max_angle` (`player.gd:_ready()`) | `deg_to_rad(46)` | HECHO |
| `floor_snap_length` (`player.gd:_ready()`) | 0.5 | HECHO |

### 1.2 Orden de proceso por tick (`movement_controller.gd:process()`)

```
_update_jump_state() → _apply_gravity() → _handle_jump() → _update_crouch() → _update_speed() → _apply_movement()
```
HECHO — ese orden literal, llamado desde `player.gd:_physics_process()` solo cuando `not traversal.is_active()`.

### 1.3 Gravedad

`_apply_gravity(delta)`: si `on_platform` es true, `velocity.y = 0.0` (gravedad suspendida — mecánica de
plataformas móviles, sin relación con parkour). Si no está en el piso (`not body.is_on_floor()`),
`velocity += get_gravity() * delta` (gravedad del proyecto, no una constante propia). HECHO.

### 1.4 Salto

`_handle_jump()`:
```gdscript
if Input.is_action_pressed("jump") and body.is_on_floor() and not is_crouching:
    body.velocity.y = JUMP_VELOCITY
    _jumped = true
```
HECHO. Nótese: usa `is_action_pressed` (tecla sostenida), no `is_action_just_pressed` — no hay guarda de
flanco explícita en esta función. En la práctica no se puede "doble saltar" sosteniendo la tecla porque
`body.is_on_floor()` pasa a `false` apenas se aplica la velocidad — el propio piso actúa como guarda.
`_jumped` se resetea a `false` en `_update_jump_state()` apenas `body.is_on_floor()` vuelve a ser `true`.
No se puede saltar agachado (`not is_crouching`). HECHO.

### 1.5 Agachado (crouch)

`_update_crouch(delta)`: interpola con `lerp(..., CROUCH_TRANSITION*delta)` tanto la altura del collider
(`target_height = 0.8` agachado / `2.0` de pie) como la altura Y de la cámara local
(`target_camera_y = 0.4` agachado / `0.706` de pie). HECHO. Es decir, la altura de pie real de V1 es
**2.0**, no un valor menor — dato relevante para cualquier cálculo de clearance que use la cápsula real.

`_update_speed(delta)`: `target_speed = CROUCH_SPEED` solo si `is_crouching and body.is_on_floor()`;
si no, `RUN_SPEED` con `run` presionado, si no `SPEED`. El resultado se aproxima con
`current_speed = lerp(current_speed, target_speed, ACCELERATION*delta)` — es decir, la velocidad objetivo
en sí misma es un valor suavizado, no un salto discreto. HECHO.

### 1.6 Movimiento en el piso

`_apply_movement()`, rama `if body.is_on_floor() or on_platform`:
```gdscript
body.velocity.x = lerp(body.velocity.x, direction.x * current_speed, ACCELERATION * delta)
body.velocity.z = lerp(body.velocity.z, direction.z * current_speed, ACCELERATION * delta)
# clamp posterior: si la horizontal resultante supera current_speed, se renormaliza a current_speed
```
HECHO. Mismo `ACCELERATION` (14.0) para acelerar y frenar (no hay input → el target es `Vector3.ZERO`
implícito vía `direction`, que ya viene en cero desde `player.gd:_get_input_direction()`).

### 1.7 Movimiento en el aire — control asimétrico según velocidad e impulso

`_apply_movement()`, rama `else` (no en el piso):
```gdscript
if direction != Vector3.ZERO:
    var vel_h = Vector2(body.velocity.x, body.velocity.z).length()
    var air_control = AIR_CONTROL_FAST if vel_h > 7.0 else AIR_CONTROL_SLOW
    body.velocity.x = lerp(body.velocity.x, direction.x * current_speed, air_control * delta)
    body.velocity.z = lerp(body.velocity.z, direction.z * current_speed, air_control * delta)
else:
    var friction = AIR_FRICTION if _jumped else FALL_FRICTION
    body.velocity.x = lerp(body.velocity.x, 0.0, friction * delta)
    body.velocity.z = lerp(body.velocity.z, 0.0, friction * delta)
```
HECHO, y es el dato más denso de esta sección:

- **Con input direccional en el aire**: la autoridad de control depende de qué tan rápido vas *ya*
  horizontalmente. Por encima de 7.0 m/s, el control cae a 0.3 (muy poca capacidad de redirigir). Por
  debajo, sube a 1.5 (más margen para corregir). No hay transición suave entre ambos — es un salto
  discreto de 0.3 a 1.5 exactamente en 7.0 m/s. HECHO.
- **Sin input en el aire**: la fricción depende de si el vuelo se originó en un salto propio (`_jumped`,
  `AIR_FRICTION=0.8`, decae lento — se conserva el arco) o en una caída pasiva (borde, empujón, etc.;
  `FALL_FRICTION=3.0`, decae rápido). HECHO.
- **INFERENCIA**: esta asimetría hace que un salto corrido a más de 7 m/s sea difícil de redirigir a
  mitad de vuelo (protege el impulso horizontal), mientras que caerse sin haber saltado frena mucho más
  rápido la inercia horizontal que quedaba. No se verificó jugando; es lectura directa de la fórmula.
- Ninguna de estas dos ramas hace clamp de velocidad máxima — a diferencia de la rama de piso, en el aire
  la velocidad horizontal puede superar `current_speed` indefinidamente si algo la puso ahí (esta función
  nunca la introduce por sí sola, dado que `direction.x * current_speed` es el techo del lerp, pero no hay
  ningún renormalizado forzado como en el piso). HECHO (ausencia de clamp verificada por lectura).

### 1.8 Cámara y mouse-look — sin relación con el estado de traversal

`player.gd:_input()`:
```gdscript
if event is InputEventMouseMotion:
    rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
    camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
    camera.rotation.x = clamp(camera.rotation.x, -PI / 2, PI / 2)
```
HECHO. Se ejecuta **siempre** que llega un `InputEventMouseMotion`, sin condicionar por
`traversal.is_active()` ni por ningún estado. Único gate: `if UiInventario.visible: return` al principio
de `_input()` (inventario abierto bloquea *todo* el input de este método, mouse incluido). Ver sección 6
para el desarrollo completo de cámara.

---

## 2. Detección contextual

Fuente: `scripts/player n entities/movement/parkour_detector.gd` (nodo `ParkourDetector`).

### 2.1 Cuándo corre

`process(delta)`:
```gdscript
if _cooldown_timer > 0.0:
    _cooldown_timer -= delta
    _clear_candidate(); _clear_ladder_candidate()
    return
if body.is_on_floor():
    _clear_candidate()
else:
    _process_ledge()
_process_ladder()
```
HECHO. Tres consecuencias directas, sin inferencia:
1. Con cooldown activo, ni ledge ni ladder se evalúan en absoluto — se limpian ambos candidatos.
2. **La detección de borde (ledge) está completamente apagada mientras el jugador está en el piso.**
   No hay ninguna rama de "en el piso, avanzando" — el candidato se limpia y no se busca uno nuevo.
3. La detección de escalera (`_process_ladder()`) corre siempre que no haya cooldown, **sin importar si
   está en el piso o no** — la condición de piso para escaleras vive en `_has_ladder_intent()` (2.3), no acá.

Además, `player.gd:_physics_process()` solo llama a `parkour_detector.process(delta)` cuando
`not traversal.is_active()` — mientras el jugador está colgado/trepando/en escalera, el detector no corre
en absoluto (ni siquiera para limpiar candidatos: simplemente no se lo invoca). HECHO.

### 2.2 Borde (ledge) — probes, alcance, orden

`_find_best_candidate()`: itera `PROBE_HEIGHTS = [0.3, 0.6, 0.9, 1.2, 1.5]`, un raycast horizontal por
altura desde `body.global_position + Vector3.UP*offset`, y se queda con el de mayor **score** (no el
primero que golpea algo). HECHO.

`_probe_at(space, origin, facing)`, en orden:
1. Raycast pared: `origin → origin + facing*detection_distance` (`detection_distance=0.85`). Sin hit,
   descarta. HECHO.
2. Filtro de inclinación de pared: `abs(wall_normal.y) > sin(deg_to_rad(max_surface_tilt_deg))`
   (`max_surface_tilt_deg=30.0`) descarta — una pared "casi piso o casi techo" no cuenta. HECHO.
3. Raycast de borde: desde `(wall_point.x, body.y + max_edge_height + 0.3, wall_point.z) - wall_normal*0.08`
   hacia abajo hasta `(wall_point.x, wall_point.y, wall_point.z) - wall_normal*0.08` (`max_edge_height=1.5`).
   Sin hit, descarta. HECHO.
4. Coherencia lateral: la proyección XZ del punto de pared y del punto de borde no puede diferir más de
   `0.35` (hardcodeado, no exportado). Si difieren más, se asume que el borde encontrado pertenece a otra
   superficie y se descarta. HECHO.
5. Superficie del borde debe ser razonablemente horizontal:
   `edge_normal.dot(UP) < cos(deg_to_rad(max_surface_tilt_deg))` descarta. HECHO.
6. Altura relativa: `height_diff = edge_point.y - body.global_position.y`, debe estar en
   `[min_edge_height, max_edge_height] = [0.5, 1.5]`. Fuera de rango, descarta. HECHO.
7. Clearance (2.4). Sin espacio, descarta el candidato **por completo** (no hay concepto de "válido para
   colgarse pero no para trepar" — si no hay clearance, no hay candidato de ningún tipo). HECHO.

Mientras tanto, `_process_ledge()` aplica dos filtros adicionales sobre el mejor candidato ya encontrado:
- `best["score"] < min_score` (`min_score=0.35`) descarta. HECHO.
- Zona de exclusión espacial (2.6). HECHO.

### 2.3 Escalera — probes, alcance, condición de intención contextual

`_process_ladder()`: `intersect_shape` con una `SphereShape3D` de radio `ladder_detection_radius=1.0`
centrada en `body.global_position`. Para cada resultado: sube hasta 4 niveles de jerarquía
(`_find_segment`, `for _i in range(4)`) buscando un nodo en el grupo `"ladder"`; descarta si no tiene
`start_marker`/`end_marker` asignados; valida volumen (`_is_within_segment_volume`: progreso proyectado
en `[0,1]` y distancia lateral `<= ladder_detection_radius`); y por último **valida intención**:

```gdscript
func _has_ladder_intent(_segment: Node) -> bool:
    if body.is_on_floor():
        return false
    if Input.is_action_pressed("crouch"):
        return false
    return true
```
HECHO. **Esto es más restrictivo de lo que podría asumirse**: una escalera detectada geométricamente NO
se activa si el jugador está en el piso — hace falta estar en el aire (mismo criterio que el borde) y no
estar agachado. Es decir: pararse quieto o caminar frente a una escalera *estando en el piso* nunca la
activa en V1, sea cual sea el input de movimiento. Solo se puede "entrar" a una escalera saltando o
cayendo cerca de ella.

Emisión: solo si `not ladder_detected() or _last_ladder_candidate.get("area") != segment` — evita
re-emitir la misma señal para el mismo segmento en cada frame. HECHO.

### 2.4 Clearance

`_check_clearance(space, edge_point)`: `intersect_shape` con `CapsuleShape3D(radius=clearance_radius,
height=clearance_height)` = **(0.25, 1.2)**, centrada en `edge_point + UP*(clearance_height*0.5 + 0.1)`.
Vacío ⇒ hay espacio. HECHO. Dato relevante: la cápsula real de pie de V1 mide 2.0 de alto
(`movement_controller.gd:_update_crouch`, sección 1.5) — el chequeo de clearance usa una cápsula **más
chica** que el jugador real de pie (1.2 vs 2.0; radio no comparable directo porque V1 no expone el radio
real del collider en estos archivos — PENDIENTE DE VALIDACIÓN EMPÍRICA el radio exacto del
`CapsuleShape3D` del jugador, no aparece en ninguno de los scripts leídos).

### 2.5 Score

`_score_candidate(c)`:
```gdscript
wall_dot = facing.dot(-c.wall_normal)
if wall_dot < 0.3: return 0.0
score = wall_dot * 0.35

if vel_h.length() > 0.5:
    score += clamp(vel_dir.dot(-c.wall_normal), 0, 1) * 0.30

cam_dot = cam_forward(horizontal).dot(-c.wall_normal)
score += clamp(cam_dot, 0, 1) * 0.20

dist_score = 1 - clamp(dist / (detection_distance*2.5), 0, 1)
score += dist_score * 0.15

return clamp(score, 0, 1)
```
HECHO, con `facing = -body.transform.basis.z` (frente del cuerpo, no de la cámara) para el primer término,
y `cam_forward` explícitamente horizontal (`cam_forward.y = 0` antes de normalizar) para el tercero. La
velocidad y la cámara son términos *aditivos* opcionales — si no se cumple su condición mínima, simplemente
no suman (no hay penalización). Umbral de aceptación final: `min_score = 0.35` (ver 2.2).

### 2.6 Zona de exclusión espacial tras soltar (ledge)

`_process_ledge()`:
```gdscript
if traversal and traversal.last_hanging_pos != Vector3.ZERO:
    var last = traversal.last_hanging_pos
    if best["edge_point"].distance_to(last) < 2.0: _clear_candidate(); return
    if body.global_position.distance_to(last) < 2.0: _clear_candidate(); return
```
HECHO. Radio fijo `2.0`, no exportado. Aplica solo a bordes, no a escaleras. `last_hanging_pos` solo lo
setea `traversal_controller.gd` en un camino específico — ver sección 4.6, no es universal a toda salida
de HANGING.

### 2.7 Cooldown de detección

`@export var detection_cooldown : float = 0.8`. Activado por `traversal_controller.gd` vía
`detector.start_cooldown()` en la mayoría (no todas, ver 4.6/4.7) de las salidas de estado. Mientras está
activo, bloquea ledge y ladder por igual (2.1). HECHO.

---

## 3. Máquina de estados

Fuente: `scripts/player n entities/movement/traversal_controller.gd`.

`enum State { IDLE, SNAPPING, HANGING, CLIMBING, LADDER }`. HECHO.

**Regla de escritura común a SNAPPING, HANGING, CLIMBING, LADDER**: las cuatro empiezan su función de
tick con `body.velocity = Vector3.ZERO` y escriben `body.global_position` (o lo dejan en lo último
asignado) directo, sin pasar nunca por `move_and_slide()` ni `move_and_collide()`. HECHO — ningún estado
de traversal en V1 hace una sola llamada de movimiento con colisión real. Ver sección 7 para las
consecuencias de esto.

**Rotación**: ningún estado (`_state_snapping`, `_state_hanging`, `_state_climbing`, `_state_ladder`)
escribe `body.rotation` ni `camera.rotation` en ningún momento. HECHO (confirmado por lectura completa
del archivo, 613 líneas).

**Collider**: ningún estado de traversal cambia el collider (altura/forma) — eso solo lo toca
`movement_controller.gd:_update_crouch()`, que no corre mientras `traversal.is_active()` (`player.gd`
delega a `movement.process()` solo en la rama `else`). HECHO. Es decir: si el jugador entra a un estado de
traversal estando agachado, el collider queda congelado en el tamaño que tenía en ese instante (ni sigue
achicándose ni vuelve a agrandarse) hasta volver a IDLE.

### 3.1 IDLE

Entrada: estado inicial, o llegada desde `_release()` de cualquier otro estado. HECHO.

Durante IDLE, `_physics_process()` (líneas 130-140) gestiona el reset de `last_hanging_pos`:
```gdscript
if body.is_on_floor():
    last_hanging_pos = Vector3.ZERO
    _last_hang_clear_timer = 0.0
elif _last_hang_clear_timer > 0.0:
    _last_hang_clear_timer -= delta
    if _last_hang_clear_timer <= 0.0:
        last_hanging_pos = Vector3.ZERO
```
HECHO. Aterrizar limpia la zona de exclusión al instante; si sigue en el aire, se agota con el timer.

Salida: `_on_candidate_found()` (borde) → SNAPPING, o `_on_ladder_candidate_found()` (escalera) → LADDER
directo (sin paso intermedio). Ambas señales las emite el detector; ambas solo se conectan una vez en
`setup()`. `_on_candidate_found` tiene guarda explícita `if state != State.IDLE: return` — un candidato
nuevo nunca interrumpe un estado activo. HECHO.

### 3.2 SNAPPING

Entrada: única, desde `_on_candidate_found()`. Calcula
`_hang_position = Vector3(edge.x, edge.y + HANG_OFFSET_Y, edge.z) - _hang_normal * HANG_WALL_GAP`
(`HANG_OFFSET_Y=-0.55`, `HANG_WALL_GAP=-0.68`, con lo que en la práctica se **suma** `_hang_normal*0.68`
porque se resta un negativo). HECHO.

Tick (`_state_snapping`):
- `Input.is_action_just_pressed("jump")` → `_release(Vector3.UP * jump_force)` (`jump_force=6.5`, un pop
  puramente vertical, distinto del salto normal de 4.5). HECHO.
- Si `_snap_timer > SNAP_TIMEOUT` (1.0s), `push_warning` + `_release(_hang_normal * 2.0)` (empujón
  horizontal alejándose de la pared, sin componente vertical). HECHO.
- Si no, `body.global_position = body.global_position.lerp(_hang_position, snap_speed*delta)`
  (`snap_speed=14.0`) — **INFERENCIA**: convergencia exponencial/proporcional a la distancia restante, no
  lineal ni de duración fija.
- Umbral de llegada: `distance_to(_hang_position) < snap_threshold` (0.2) → posición exacta + cambio a
  HANGING. HECHO.

Ninguna otra tecla (crouch, back, escalera) hace nada durante SNAPPING — no están escuchadas en esta
función. HECHO.

### 3.3 HANGING

Entrada: única, desde SNAPPING al llegar dentro del umbral.

Tick (`_state_hanging`), en este orden exacto:
1. `Input.is_action_just_pressed("jump")` → CLIMBING (sin verificar nada más). HECHO.
2. `Input.is_action_just_pressed("move_back")` → `_release(_hang_normal*3.5 + UP*1.0)` (empujón fuerte
   alejándose de la pared + hop). HECHO.
3. `Input.is_action_just_pressed("crouch")` → guarda `last_hanging_pos`/`_last_hang_clear_timer`, marca
   `is_crouch_blocked_after_drop = true`, `_release(Vector3.ZERO)` (caída pasiva, velocidad cero). HECHO.
4. Si ninguna de las anteriores, shimmy (sección 4).

`is_crouch_blocked_after_drop` lo consulta `player.gd:_input()` para impedir agacharse/pararse
inmediatamente después de soltarse por crouch — se desarma en `_physics_process` de IDLE apenas
`not Input.is_action_pressed("crouch")`. HECHO.

### 3.4 CLIMBING (equivalente a mantle)

Entrada: única, desde HANGING vía jump.

Tick (`_state_climbing`):
```gdscript
target = _hang_position + Vector3.UP * 2.2 - _hang_normal * 0.4
body.global_position = body.global_position.lerp(target, climb_speed * delta)  # climb_speed=4.0
if body.global_position.distance_to(target) < 0.12:
    body.global_position = target
    _release(-_hang_normal * 1.5)
```
HECHO. `target` es un **offset fijo** relativo a `_hang_position`/`_hang_normal` en el instante en que
arrancó CLIMBING — no hay ningún raycast, ninguna validación de superficie de aterrizaje, ninguna
comprobación de que haya piso ahí arriba. **HECHO, no inferencia**: esta función no contiene una sola
llamada a `intersect_ray`/`intersect_shape`/`test_move`. Salida siempre con un empujón hacia adelante
(`-_hang_normal*1.5`, hacia la pared/superficie) al llegar dentro de 0.12 unidades del target.
**INFERENCIA**: convergencia exponencial (mismo tipo de lerp que SNAPPING), no de duración fija.

No hay forma de cancelar CLIMBING una vez iniciado — la función no escucha ningún input propio.

### 3.5 LADDER

Entrada: única, desde IDLE vía `_on_ladder_candidate_found()` (nunca desde HANGING/CLIMBING). Calcula el
progreso inicial proyectando la posición del jugador sobre el segmento (`clamp(dot/seg_len, 0, 1)`).

Tick (`_state_ladder`), en este orden:
1. `Input.is_action_just_pressed("jump")` → `_release(cam_fwd_horizontal*4.0 + UP*5.0)` (impulso en la
   dirección horizontal de la cámara, no del cuerpo). HECHO.
2. `Input.is_action_just_pressed("crouch")` → `_release(Vector3.ZERO, false)` — **el segundo argumento es
   `false`**: a diferencia de cualquier otra salida de este archivo, **esta NO arma el cooldown del
   detector**. HECHO, verificado por lectura — es la única llamada a `_release()` en todo el archivo con
   `use_cooldown` explícito en `false`.
3. Si no hay input de avance/retroceso puro (`pressing_up == pressing_down`, incluye "ninguno de los dos"
   y "ambos"), el progreso NO avanza — se resetea el timer de pulso y se reconstruye la posición desde el
   progreso actual sin cambios. HECHO.
4. Si hay avance neto, sistema de **pulso discreto**, no continuo:
   - `pulse_time = ladder_pulse_time` (0.18s), dividido por `_current_segment.move_speed` si el segmento
     lo define (multiplicador por segmento).
   - Se acumula `_ladder_pulse_timer += delta`; recién cuando supera `pulse_time`, se resta `pulse_time`
     del acumulador y se aplica **un solo paso** de progreso:
     `progress_step = ladder_pulse_speed * pulse_time / seg_len` (`ladder_pulse_speed=0.8`).
   - Es decir, el jugador NO se mueve de forma continua por la escalera: avanza en saltos discretos cada
     ~0.18s (ajustado por `move_speed`), no en cada frame físico. HECHO.
5. Transición de segmento: si `new_progress > 1.0` y existe `neighbour_up`, cambia de segmento y arrastra
   el remanente (`new_progress - 1.0`); si no hay vecino, clampea en 1.0. Simétrico hacia abajo con
   `neighbour_down`. HECHO.
6. Reconstrucción final: `body.global_position = _current_segment.get_position_at(_current_progress)`
   (lerp lineal entre `start_marker`/`end_marker`, `traversal_segment.gd:get_position_at()`). HECHO.

`ladder_snap_strength = 0.3` está declarado (comentario: "atracción al centro XZ al entrar") pero
**no se usa en ninguna parte del archivo** — HECHO, confirmado por búsqueda exhaustiva. Es un export
muerto; documentado en la sección 7.

### 3.6 Transición IDLE↔activo

`_change_state()`: si se pasa de inactivo a activo, `movement.freeze()` (pone `velocity.x/z` en 0 en
`MovementController`, sin afectar Y) y emite `traversal_started`; si se pasa de activo a inactivo, emite
`traversal_ended`. Si el nuevo estado no es HANGING, resetea `_can_go_left/_can_go_right/_shimmy_dir` a
sus valores neutros. HECHO. Estas señales no se consumen en ninguno de los archivos revisados —
PENDIENTE DE VALIDACIÓN EMPÍRICA si algún otro sistema (UI, sonido) las escuchaba.

---

## 4. Hanging y shimmy

Fuente: `traversal_controller.gd`, funciones `_state_hanging`, `_update_shimmy_probes`,
`_calculate_tangent`, `_apply_virtual_normal`, `_edge_continues`.

### 4.1 Entrada al borde (snap)

Ver 3.2. El punto de destino se fija una única vez al detectar el candidato
(`_hang_position_target = _hang_position`, ambos iguales al entrar) y no vuelve a recalcularse durante
SNAPPING — solo cambia si el shimmy lo mueve más tarde, ya en HANGING. HECHO.

### 4.2 Movimiento lateral en bordes "normales" (sin marcador ni segmento de shimmy)

**Este es el punto central de la sección shimmy: no depende de ningún dato de autor.** Cada tick de
HANGING llama `_update_shimmy_probes()`, que a su vez llama `_edge_continues()` dos veces (izquierda y
derecha) — dos raycasts por lado (pared + borde, mismo patrón geométrico que `_probe_at()` del detector,
sección 2.2), evaluados en vivo contra la geometría física real, sin memoria de ningún segmento:

```gdscript
func _edge_continues(lateral_dir, dist=-1.0) -> Dictionary:
    probe_dist = dist if dist > 0 else shimmy_max_dist   # 0.5
    probe = (_hang_position + UP*edge_y_offset) + lateral_dir * probe_dist
    wall_hit = raycast(probe - hang_normal*0.2  →  probe + hang_normal_inverso*1.0... )
    # (from = probe + to_wall*-0.2, to = probe + to_wall*1.0, to_wall = -_hang_normal)
    if no wall_hit or wall tilt > 30°: return {}
    edge_from = wall_hit.position + UP*0.4 - hang_normal*0.05
    edge_to   = edge_from + DOWN*0.7
    edge_hit  = raycast(edge_from, edge_to)
    if no edge_hit: return {}
    return { wall_normal, wall_point }
```
HECHO (transcripción fiel de `_edge_continues`, líneas 506-542). `_can_go_left`/`_can_go_right` son
simplemente "¿esta función devolvió algo no vacío?". El input (`move_left`/`move_right`, sostenido, no
flanco) solo puede mover si el probe correspondiente encontró borde:
```gdscript
if pressing_left and _can_go_left: dir = -1.0
elif pressing_right and _can_go_right: dir = 1.0
```
El paso lateral en sí: `step = _along_wall * dir * shimmy_speed * delta` (`shimmy_speed=2.5`), sumado
directo a `_hang_position` y `_hang_position_target`. Es decir, **velocidad constante** durante el shimmy
en curso (no hay aceleración/frenado propio) — la suavidad viene enteramente de que se reevalúa cada
frame físico. HECHO.

### 4.3 Reacción al borde (feedback de bloqueo)

Cuando se presiona una dirección de shimmy y el probe correspondiente NO encuentra borde, se registra un
log distinto por única vez (`_shimmy_dir` se pone en el centinela `-99.0`/`99.0` para no repetir el log
cada frame) — HECHO. No hay ningún efecto físico ni de cámara asociado a este bloqueo más allá de que el
jugador simplemente no se mueve — no hay un "tope duro" con rebote, ni un sonido o vibración documentado en
este archivo. PENDIENTE DE VALIDACIÓN EMPÍRICA si había feedback sonoro/visual en otro sistema no
recuperado (UI, audio) — no aparece en ninguno de los scripts de movimiento.

### 4.4 Transición en esquinas y cambio de normal

Dentro de `_update_shimmy_probes()`, si el probe del lado hacia el que se está shimmyeando devuelve un
`wall_normal` **distinto** del actual (`new_normal != _hang_normal`), se lo adopta:
```gdscript
_hang_normal = new_normal
_along_wall  = UP.cross(_hang_normal).normalized()
_hang_position_target = Vector3(ref_point.x, _hang_position.y, ref_point.z) - _hang_normal*HANG_WALL_GAP
_transitioning_face = true
```
HECHO. Es decir, doblar una esquina (pasar de una cara de pared a otra, con normales distintas) es
**detectado automáticamente por el propio probe lateral**, sin ningún marcador de "vecino" ni conexión
autorada entre las dos caras — a diferencia de las escaleras (3.5), que sí usan `neighbour_up/down`
explícitos.

Con `_transitioning_face` activo, mientras se sigue shimmyeando (`dir != 0`), la posición se ajusta con
un lerp propio y más lento hacia el nuevo target:
```gdscript
smooth_x = lerp(_hang_position.x, _hang_position_target.x, 4.0*delta)
smooth_z = lerp(_hang_position.z, _hang_position_target.z, 4.0*delta)
```
(constante `4.0` hardcodeada, no exportada) hasta que la distancia XZ al target cae debajo de `0.01`.
Si el jugador SUELTA el input de shimmy en medio de una transición de cara (`dir == 0.0`), la transición
NO se completa gradualmente: se corta y se llama `_apply_virtual_normal()` de inmediato. HECHO.

Adicionalmente, `_calculate_tangent()` corre cada tick de shimmy activo (`_shimmy_dir != 0`) y recalcula
`_along_wall` promediando 6 probes internos (`PROBE_OFFSETS_INNER = [-0.7,-0.4,-0.1,0.1,0.4,0.7]`),
sacando un centroide de los puntos de pared a cada lado y usando la diferencia como tangente objetivo,
suavizada con `_along_wall.lerp(target_tangent, 0.15)` (constante `0.15` hardcodeada, sin `delta` — es una
fracción fija por FRAME, no por segundo; a distinto framerate este suavizado converge a distinta
velocidad real). HECHO — esto es lo que le permite a V1 seguir superficies con curvatura o ángulo variable
sin que el jugador note un "salto" de orientación.

### 4.5 `_apply_virtual_normal()` — asentamiento al soltar el shimmy

Cuando se suelta el input de shimmy en medio de una transición de cara, se promedian hasta 6 raycasts
(mismos `PROBE_OFFSETS_INNER`) para fijar una normal/posición "de compromiso":
```gdscript
avg_normal, avg_position = promedio de los raycasts válidos
_hang_normal = avg_normal
_along_wall  = UP.cross(_hang_normal).normalized()
_hang_position = Vector3(avg_position.x - avg_normal.x*HANG_WALL_GAP, _hang_position.y, avg_position.z - avg_normal.z*HANG_WALL_GAP)
```
HECHO. Si los 6 probes no encuentran nada (`count == 0`), la función retorna sin cambiar nada — el
jugador se queda exactamente donde estaba. HECHO.

### 4.6 Final de borde (límite físico, no autorado)

No existe un concepto de "extremo del segmento" en HANGING — el límite es, en cada tick, simplemente
"`_edge_continues()` no encontró nada a esa distancia". Como el probe usa `shimmy_max_dist=0.5` fijo
(salvo que se pase `dist` explícito, cosa que no ocurre en ningún call site de este archivo), el jugador
se detiene como máximo a 0.5 unidades del punto donde la pared/borde deja de ser válida geométricamente
— **no hay ningún dato de autor definiendo dónde termina un borde**, es enteramente producto de la
geometría de colisión real.

### 4.7 Salida de HANGING y caída

Ver 3.3 para los tres caminos de salida (jump→CLIMBING, back→release con empujón, crouch→release pasivo).
Solo el camino de **crouch** setea `last_hanging_pos`/`_last_hang_clear_timer` (sección 2.6/3.1) — soltar
con "atrás" no deja zona de exclusión espacial, solo el cooldown temporal plano del detector
(`detector.start_cooldown()`, 0.8s, HECHO por default `use_cooldown=true` en `_release()`).

### 4.8 Salto hacia mantle desde HANGING

Ver 3.3 punto 1 y 3.4 — sin condición adicional más allá del flanco de jump. No hay verificación de que
"realmente convenga" trepar (altura disponible, superficie arriba) antes de arrancar CLIMBING — eso solo
se resuelve (mal, sección 3.4) al llegar al target fijo.

---

## 5. Mantle y escaleras

### 5.1 Mantle (CLIMBING)

Ya cubierto en 3.4. Resumen de qué se resuelve físicamente vs. por datos fijos:
- **Dato de autor / fijo**: el propio offset `UP*2.2 - hang_normal*0.4` — un número inventado una vez,
  igual para cualquier borde, sin relación con la altura real de lo que hay arriba.
- **Física real**: ninguna, en el sentido de colisión — la función nunca llama a una query de física. Sí
  usa `_hang_normal`, que a su vez SÍ viene de un raycast real (el que originó el hang).
- **HECHO, no inferencia**: no existe ningún concepto de "mantle bloqueado" o "aterrizaje inválido" en V1
  — el CLIMBING siempre llega a destino, porque nunca comprueba si el destino es válido.

### 5.2 Escaleras — markers como excepción, no como regla

`traversal_segment.gd`: el propio comentario de cabecera lo declara — "Va directo en el StaticBody3D de
la escalera (o cuerda, cable, etc.)"; `enum SegmentType { LADDER, ROPE, CABLE, CHAIN }` (solo `LADDER`
tiene lógica de estado implementada en `traversal_controller.gd`; ROPE/CABLE/CHAIN existen en el enum pero
sin ningún `_state_*` propio — **HECHO**, no se encontró código para ellos en ninguno de los archivos
revisados). El propio diseño de V1 reserva el marcador explícito (`StartMarker`/`EndMarker`) para
geometría donde no hay una "pared + borde horizontal" que un probe de ledge pueda encontrar — exactamente
el mismo criterio que se pidió preservar: cajas, paredes y bordes comunes en V1 **nunca** pasan por
marcador, solo escaleras (y, en el enum, cuerdas/cables/cadenas si algún día se implementaban).

Condición de entrada — ya cubierta en 2.3 — es **contextual y más estricta de lo esperado**: exige estar
en el aire (`not body.is_on_floor()`) y no estar agachado. Pararse quieto o caminar frente a una escalera
estando en el piso nunca la activa por sí solo en V1 — hace falta abordarla saltando o cayendo.

Trayectoria y timing de escalera: progreso discreto por pulsos (`ladder_pulse_time=0.18s`,
`ladder_pulse_speed=0.8`), ver 3.5 — no continuo, no basado en velocidad por frame.

Restricciones: el volumen de validación es un radio fijo (`ladder_detection_radius=1.0`) proyectado sobre
el segmento, más `progress ∈ [0,1]` sin tolerancia (a diferencia de V1 en bordes, acá no hay margen fuera
de `[0,1]` documentado en `_is_within_segment_volume`). HECHO.

---

## 6. Cámara

### 6.1 Comportamiento normal (fuera de traversal)

`player.gd:_input()` — yaw sin límite (`rotate_y`, ninguna normalización ni clamp en ningún punto del
archivo), pitch con clamp universal `±PI/2` (exactamente 90°) aplicado en la MISMA línea/evento en que se
escribe la rotación (`camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)`, ejecutado inmediatamente
después de `camera.rotate_x(...)`, sin ninguna ventana de un tick entre escribir y corregir). HECHO.

### 6.2 Comportamiento durante traversal

**HECHO, verificado por lectura completa de `traversal_controller.gd` (613 líneas, las 4 funciones de
estado): ningún estado de traversal (SNAPPING, HANGING, CLIMBING, LADDER) escribe `body.rotation` ni
`camera.rotation` en ningún momento.** El mouse-look de `player.gd:_input()` sigue corriendo exactamente
igual, sin ninguna condición sobre `traversal.is_active()` — no existe ningún mecanismo, explícito ni
indirecto, que limite el yaw durante ningún estado de parkour. El único límite presente durante traversal
es el mismo clamp de pitch universal de 6.1, porque nunca se desactiva.

**No hay distinción de límites entre HANGING, CLIMBING y LADDER** — los tres comparten exactamente el
mismo comportamiento de cámara (el de FREE, sin cambios) porque ninguno de los tres lo toca.

**No existe una cámara "atada al borde"** en ningún momento del sistema — no hay `look_at`, no hay
`Basis.looking_at`, no hay ninguna orientación forzada hacia la pared en todo el archivo.

---

## 7. Casos límite y rarezas (sin corregir, sin juzgar)

- **Cero colisión durante traversal.** SNAPPING, HANGING, CLIMBING y LADDER escriben
  `body.global_position` directo, sin `move_and_slide()`/`move_and_collide()`. El jugador puede atravesar
  geometría libremente mientras estos estados están activos — nada en el código lo impide. HECHO.
- **`ladder_snap_strength` es un export muerto.** Declarado, documentado en un comentario ("atracción al
  centro XZ al entrar"), nunca leído en ninguna función. HECHO.
- **El salto durante SNAPPING da más impulso vertical que un salto normal.** `jump_force=6.5` vs
  `JUMP_VELOCITY=4.5` del salto de piso — cancelar un snap con salto propulsa más alto que saltar parado.
  HECHO.
- **Soltar una escalera con crouch nunca arma el cooldown de detección**; soltar un hang con crouch sí.
  Es la única llamada a `_release()` de todo el archivo con `use_cooldown=false` explícito. En teoría,
  esto permite re-enganchar la MISMA escalera de inmediato tras soltarla agachado, sin ningún bloqueo
  temporal ni espacial (la zona de exclusión de 2.0 unidades tampoco aplica a escaleras, sección 2.6).
  HECHO por lectura; el resultado jugable exacto (¿se re-engancha de inmediato en la práctica, dado que
  también hace falta estar en el aire para la intención de escalera?) queda PENDIENTE DE VALIDACIÓN
  EMPÍRICA.
- **Dos mecanismos de anti-reenganche que se solapan pero no son iguales**: el cooldown plano del
  detector (0.8s, bloquea TODO) y la zona espacial de 2.0 unidades alrededor de `last_hanging_pos`
  (bloquea solo bordes, solo si se soltó por crouch, y se resetea antes de tiempo si el jugador aterriza
  en el piso). Ambos comparten la misma duración nominal (0.8s) pero se resetean por condiciones
  distintas — aterrizar limpia la zona espacial al instante aunque el cooldown temporal siga corriendo.
  HECHO por lectura de `_physics_process` (IDLE) + `parkour_detector._process_ledge()`.
  PENDIENTE DE VALIDACIÓN EMPÍRICA si esta interacción produce algún caso observable donde un borde se
  vuelve agarrable *antes* de que ambos timers terminen, o *después* de lo esperado.
- **El mantle (CLIMBING) nunca falla.** No hay concepto de "mantle bloqueado" — si el offset fijo
  `hang_position + UP*2.2 - hang_normal*0.4` cae dentro de geometría sólida, el jugador probablemente
  termina incrustado o atraviesa la superficie (consecuencia directa de la ausencia de colisión señalada
  arriba). PENDIENTE DE VALIDACIÓN EMPÍRICA el resultado visual/físico exacto en ese caso — no se puede
  saber sin probarlo si Godot lo resuelve de alguna forma al volver a IDLE y recuperar `move_and_slide()`,
  o si el jugador queda atascado.
- **El shimmy puede cambiar de pared en medio de un input sostenido sin que el jugador suelte la tecla**
  (sección 4.4) — no hay ninguna confirmación ni "click" de aceptación del nuevo ángulo, ocurre
  automáticamente apenas el probe detecta una normal distinta.
- **Doble suavizado con distinta base temporal en la transición de cara**: la posición usa
  `lerp(..., 4.0*delta)` (por segundo) pero la tangente usa `lerp(..., 0.15)` sin `delta` (por frame,
  sección 4.4) — a un framerate más alto, la orientación converge más rápido en tiempo real que la
  posición, proporcionalmente distinto de a un framerate más bajo. HECHO por lectura; el efecto jugable
  concreto a distintos framerates es PENDIENTE DE VALIDACIÓN EMPÍRICA.
- **`_has_ladder_intent` ignora completamente al segmento que recibe como parámetro** (`_segment` con
  guión bajo, no usado en el cuerpo) — la "intención" es idéntica para cualquier escalera, no hay
  variación por tipo/config de segmento pese a que la firma sugeriría que sí. HECHO.

---

## 8. Escenarios observables

| Situación inicial | Input del jugador | Resultado exacto esperado en V1 | Fuente |
|---|---|---|---|
| Parado en el piso, de frente a una caja con un borde válido en altura/ángulo | Ninguno (quieto) | Nada — el detector no evalúa ledges en el piso (`parkour_detector.process()`: `is_on_floor() → _clear_candidate()`) | `parkour_detector.gd:process()` |
| Parado en el piso, de frente a una caja con borde válido | Camina hacia adelante, sigue en el piso | Nada — sigue sin evaluarse mientras `is_on_floor()` sea true, sin importar el input | `parkour_detector.gd:process()` |
| Cayendo (en el aire), pasa cerca de un borde válido en altura/ángulo/score | Ninguno | Detecta candidato, `_on_candidate_found` → SNAPPING → converge (`lerp`, `snap_speed=14`) → dentro de `snap_threshold=0.2` pasa a HANGING, posición exacta | `parkour_detector.gd:_process_ledge()`, `traversal_controller.gd:_on_candidate_found/_state_snapping` |
| En SNAPPING, a mitad de la convergencia | Presiona salto | Cancela: `_release(UP*6.5)`, vuelve a IDLE con impulso vertical puro, arma cooldown de detección (0.8s) | `traversal_controller.gd:_state_snapping()` |
| En SNAPPING, sin soltar tecla de salto ni llegar a destino | Pasa más de 1.0s | Timeout: `push_warning`, `_release(hang_normal*2.0)`, vuelve a IDLE empujado horizontalmente lejos de la pared | `traversal_controller.gd:_state_snapping()` |
| Colgado (HANGING), borde recto y largo | Sostiene move_left o move_right | Se desplaza a `shimmy_speed=2.5` mientras `_edge_continues()` siga encontrando pared+borde a 0.5 unidades por delante en esa dirección | `traversal_controller.gd:_state_hanging/_update_shimmy_probes/_edge_continues` |
| Colgado, shimmyeando hacia una esquina donde la pared cambia de cara | Sostiene la tecla de shimmy a través de la esquina | La normal se actualiza sola apenas el probe lateral detecta un `wall_normal` distinto; posición se realinea con un lerp propio (`4.0*delta`) hasta la nueva cara, sin soltar el hang | `traversal_controller.gd:_update_shimmy_probes()` |
| Colgado, llega al final físico del borde (el probe de 0.5 unidades ya no encuentra pared/borde) | Sigue sosteniendo la tecla de shimmy | No se mueve más allá de ese punto; log único de "shimmy bloqueado — sin borde"; sigue colgado, no suelta | `traversal_controller.gd:_state_hanging()` |
| Colgado | Presiona salto (flanco) | Pasa a CLIMBING sin ninguna otra condición | `traversal_controller.gd:_state_hanging()` |
| En CLIMBING | (sin input — no escucha ninguno) | Converge (`lerp`, `climb_speed=4.0`) hacia `hang_position + UP*2.2 - hang_normal*0.4`; a menos de 0.12 unidades, snap exacto + `_release(-hang_normal*1.5)`, vuelve a IDLE con impulso hacia adelante | `traversal_controller.gd:_state_climbing()` |
| Colgado | Presiona atrás (move_back, flanco) | `_release(hang_normal*3.5 + UP*1.0)`, suelta con empujón fuerte alejándose de la pared + hop, cooldown de detección armado | `traversal_controller.gd:_state_hanging()` |
| Colgado | Presiona agacharse (crouch, flanco) | `_release(Vector3.ZERO)` — caída pasiva desde velocidad cero; además guarda `last_hanging_pos` y arma `is_crouch_blocked_after_drop` | `traversal_controller.gd:_state_hanging()` |
| En el aire, cerca (radio 1.0) y alineado con un segmento de escalera válido | Ninguno (cae pasivo, sin apretar nada) | Detecta intención igual (`_has_ladder_intent` no exige tecla de movimiento, solo "no estar en el piso" y "no crouch") → entra a LADDER directo desde IDLE | `parkour_detector.gd:_has_ladder_intent()`, `traversal_controller.gd:_on_ladder_candidate_found()` |
| Parado en el piso, junto a una escalera alineada | Cualquier input, incluido caminar hacia ella | Nada — `_has_ladder_intent()` descarta por `is_on_floor()==true` antes de mirar cualquier otra cosa | `parkour_detector.gd:_has_ladder_intent()` |
| En LADDER | Sostiene move_forward | Avanza en pulsos discretos cada `ladder_pulse_time=0.18s` (ajustado por `move_speed` del segmento), no de forma continua por frame | `traversal_controller.gd:_state_ladder()` |
| En LADDER, `_current_progress` llega a más de 1.0 y el segmento tiene `neighbour_up` | Sigue sosteniendo move_forward | Transición automática al segmento vecino, arrastrando el progreso sobrante | `traversal_controller.gd:_state_ladder()` |
| En LADDER, en el extremo sin vecino | Sostiene move_forward más allá del límite | El progreso queda clampeado en 1.0, sin salir del estado | `traversal_controller.gd:_state_ladder()` |
| En LADDER | Presiona salto (flanco) | `_release(cam_fwd_horizontal*4.0 + UP*5.0)` — impulso en la dirección horizontal de la CÁMARA, no del cuerpo | `traversal_controller.gd:_state_ladder()` |
| En LADDER | Presiona agacharse (flanco) | `_release(Vector3.ZERO, false)` — suelta pasivo, y a diferencia de cualquier otra salida del archivo, **no arma el cooldown de detección** | `traversal_controller.gd:_state_ladder()` |
| Corriendo en el piso a más de 7 m/s horizontales, salta | Mueve el stick/WASD lateral en pleno vuelo | Autoridad de redirección baja (`AIR_CONTROL_FAST=0.3`) — el impulso original se conserva en gran medida | `movement_controller.gd:_apply_movement()` |
| Caminando lento (<7 m/s), salta | Mueve el stick/WASD lateral en pleno vuelo | Autoridad de redirección alta (`AIR_CONTROL_SLOW=1.5`) — se puede corregir la dirección con más libertad | `movement_controller.gd:_apply_movement()` |
| Salta sin soltar dirección, luego suelta toda tecla en el aire | — | Fricción lenta (`AIR_FRICTION=0.8`, `_jumped==true`) — conserva velocidad horizontal por más tiempo | `movement_controller.gd:_apply_movement()` |
| Se cae de un borde/plataforma sin haber saltado, suelta toda tecla en el aire | — | Fricción rápida (`FALL_FRICTION=3.0`, `_jumped==false`) — pierde velocidad horizontal más rápido que si hubiera saltado | `movement_controller.gd:_apply_movement()` |
| Mirando alrededor durante cualquier estado de traversal | Mueve el mouse libremente, incluida una vuelta completa en yaw | Yaw sin ningún límite (nunca se toca durante traversal); pitch sigue clampeado a ±90° exactos, igual que fuera de traversal | `player.gd:_input()`, ausencia de escritura de rotación en `traversal_controller.gd` |

---

## Puntos que requieren prueba manual en V1 (no reconstruibles solo con el código)

1. Resultado físico/visual exacto cuando CLIMBING termina con el target incrustado en geometría sólida
   (sección 7) — sin colisión en ese estado, no se puede saber desde el código si Godot lo resuelve al
   volver a `move_and_slide()` en IDLE o si el jugador queda atascado.
2. Interacción real entre el cooldown temporal del detector (0.8s) y la zona espacial de `last_hanging_pos`
   cuando NO coinciden en el tiempo (por ejemplo, aterrizar en el piso un instante antes de que venza el
   cooldown temporal) — ambos existen en el código pero su efecto combinado observable no es trivial de
   derivar sin jugarlo.
3. Sensación real de reenganchar una escalera inmediatamente después de soltarla con crouch (sin cooldown
   armado) — depende de si en la práctica el jugador sigue en el aire en ese instante (condición que
   además exige `_has_ladder_intent`).
4. Efecto perceptible del suavizado de tangente en `_calculate_tangent()` a distinto framerate (basado en
   frame, no en `delta`) — si el proyecto corría con vsync variable, esto pudo sentirse distinto en
   máquinas distintas.
5. Si `traversal_started`/`traversal_ended` (señales emitidas por `_change_state()`) tenían algún
   consumidor (sonido, UI, cámara) en otro sistema no recuperado en esta auditoría.
