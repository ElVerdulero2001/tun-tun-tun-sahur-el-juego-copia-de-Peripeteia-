# V3 H0 — mapa técnico del laboratorio actual

## Para qué sirve este documento

Este documento describe **lo que el laboratorio H0 implementa hoy**: qué nodo tiene cada responsabilidad, qué datos se intercambian y en qué orden ocurre todo.

No redefine la arquitectura conceptual de V3 ni fija valores de gameplay. Por ejemplo, la distancia de caída que penaliza el salto existe hoy para probar el flujo, pero su valor no está decidido.

La escena del laboratorio es `scenes/test/v3_h0_lab.tscn`.

## Piezas que existen

```text
PlayerH0Lab/Body                         CharacterBody3D real
├─ InputSource                            Lee teclado
├─ CameraRig                              Lee/aplica orientación de cámara
├─ FallDamageState                        Traduce caída lesiva a restricción
├─ H0                                     Decide locomoción normal
├─ CollisionShape3D                       Collider real del player
└─ View/Camera3D                          Cámara compartida

DebugCanvas/H0Debug                      Sólo observa y muestra datos
```

| Pieza | Archivo | Hace | No hace |
|---|---|---|---|
| `InputSource` | `v3_input_source.gd` | Lee WASD, Espacio sostenido, Shift sostenido y la pulsación para alternar crouch. | No sabe qué es H0, salto, daño ni física. |
| `CameraRig` | `v3_camera_rig.gd` | Traduce mouse a orientación, publica direcciones planas y acompaña visualmente la postura física real. | No mueve al player ni decide parkour. |
| `H0` | `h0_core.gd` | Interpreta input, cámara, suelo, aire, crouch y la restricción de salto. Formula una intención física. | No escribe `velocity`, posición, collider ni llama `move_and_slide()`. |
| `V3PhysicsBody` | `v3_physics_body.gd` | Recibe una única intención, aplica velocidad/salto/postura, usa `move_and_slide()` y publica el resultado real. | No decide qué quiere hacer el jugador ni qué core debería gobernar. |
| `FallDamageState` | `v3_fall_damage_state.gd` | Lee la caída real al aterrizar y publica si el salto quedó penalizado. | No mueve al player, no calcula vida, no cura ni mata. |
| `H0Debug` | `v3_h0_debug_overlay.gd` | Muestra datos de todos los anteriores. | No cambia ningún dato de gameplay. |

## Orden real de un tick físico

Godot llama los `_physics_process()` por prioridad. No es una cadena de llamadas privadas en la que una pieza ejecuta a la otra.

```text
prioridad -200      InputSource
prioridad  -50      FallDamageState
prioridad    0      H0
prioridad  100      V3PhysicsBody
prioridad  200      CameraRig (postura visual después de física)
después, visual      H0Debug (_process)
```

En otras palabras: primero se lee input, luego se evalúa la penalización proveniente del resultado físico anterior, H0 decide, el body intenta mover el collider real y, sólo después, CameraRig acompaña el resultado físico de postura.

### Tick N, paso a paso

```text
1. InputSource lee WASD, Espacio sostenido, Shift sostenido y la pulsación de crouch.
             ↓
2. FallDamageState mira el aterrizaje publicado por el tick N-1.
   Si fue una caída que cruzó su umbral, conserva `jump_is_penalized = true`.
             ↓
3. H0 lee hechos físicos publicados en N-1:
   suelo, velocidad, desplazamiento, etc.
   También lee input, orientación de cámara y `jump_is_penalized`.
             ↓
4. H0 llama a `V3PhysicsBody.submit_motion_intent(...)`.
   Envía velocidad horizontal deseada, si solicita salto y la postura deseada.
             ↓
5. V3PhysicsBody es el único que escribe `velocity` y llama `move_and_slide()`.
   La simulación acepta, limita o rechaza el intento.
             ↓
6. V3PhysicsBody publica los hechos resultantes del tick N.
             ↓
7. CameraRig consume la postura física actual para ubicar la cámara compartida.
             ↓
8. En N+1, FallDamageState y H0 consumen esos hechos.
```

La consecuencia importante es que H0 no presupone que su pedido ocurrió. Ve el resultado real un tick después.

## Quién llama a quién

| Origen | Destino | Relación |
|---|---|---|
| Godot | Todos los nodos del laboratorio | Ejecuta sus ciclos físico/visual. |
| `H0` | `V3PhysicsBody.submit_motion_intent()` | Único llamado de control: H0 entrega una intención física. |
| `H0` | `V3PhysicsBody.get_physics_facts()` | Lectura de hechos físicos publicados. |
| `FallDamageState` | `V3PhysicsBody` | Lee el hecho `last_landing_fall_distance`; no lo modifica. |
| `H0` | `FallDamageState` | Lee `jump_is_penalized`; no calcula daño. |
| `CameraRig` | `V3PhysicsBody` | Lee postura/ancla aplicadas; sólo ajusta la vista compartida. |
| `H0Debug` | Todos | Sólo lecturas para mostrar datos. |
| `V3PhysicsBody` | `H0` | No lo llama ni le devuelve órdenes. Expone hechos que H0 leerá después. |

## Movimiento horizontal y cámara

`InputSource` publica un eje WASD. `CameraRig` publica adelante/derecha en el plano horizontal. H0 combina ambos:

```text
W + cámara mirando norte
        ↓
H0 solicita velocidad hacia norte
        ↓
V3PhysicsBody intenta mover el collider hacia norte
```

La cámara define la dirección que H0 interpreta. No aplica movimiento físico por sí misma.

## Sprint

`Shift` sostenido se publica como el hecho `sprint activo`. H0 lo consume únicamente como modificador de velocidad horizontal mientras la postura permite correr; no hay un core Sprint ni un segundo gobernador físico.

```text
Shift + movimiento en piso
        ↓
H0 solicita velocidad de sprint
        ↓
V3PhysicsBody intenta esa velocidad como cualquier otra intención H0
```

En aire, Shift sostenido conserva esa referencia de velocidad durante la ventana de control aéreo. Si se suelta, H0 desacelera gradualmente desde la velocidad real publicada hacia la locomoción normal. Cuando vuelve a tocar piso, H0 deja de mirar la inercia anterior y usa el Shift actual: sostenido continúa sprint; suelto vuelve a caminar.

En piso, el pasaje entre caminar y sprint tampoco es instantáneo: H0 interpola la velocidad solicitada durante `0.2 s`, tanto al acelerar como al soltar Shift. El cambio físico de crouch sigue siendo inmediato y no usa esta transición.

El laboratorio sólo implementa modo sostenido. La preferencia de sprint alternado pertenece a una futura fuente/configuración de input, no a H0.

## Salto sostenido

Espacio no se guarda como buffer temporal. Es una intención que existe mientras la tecla esté presionada.

```text
Espacio sostenido + H0 lee "en piso" + salto no penalizado
        ↓
H0 solicita salto
        ↓
V3PhysicsBody vuelve a comprobar "en piso"
        ↓
si sigue apoyado: aplica impulso vertical y publica "aceptado"
si ya no está apoyado: no aplica impulso y publica "rechazado"
```

Al aterrizar con Espacio todavía sostenido, H0 emitirá otro pedido de salto en el tick siguiente. Por eso se pueden encadenar saltos sin soltar la tecla.

No hay coyote time: haber estado apoyado antes no autoriza a saltar en el aire.

## Crouch físico

Una pulsación de `Ctrl` alterna la postura deseada de H0. No hace falta mantenerla para seguir agachado.

```text
H0 solicita agacharse estando en piso
        ↓
V3PhysicsBody reemplaza la cápsula por una más baja
        ↓
desplaza el centro de la cápsula hacia abajo
        ↓
los pies permanecen sobre el mismo punto físico
        ↓
CameraRig baja la cámara compartida para acompañar el collider real
```

En aire, no cambia el estado `agachado`; cambia el ancla de esa misma cápsula:

```text
H0 solicita agacharse estando en aire
        ↓
V3PhysicsBody reduce altura y conserva el centro de la cápsula
        ↓
la parte inferior sube
        ↓
CameraRig conserva su referencia de altura normal
```

Al aterrizar agachado, la capa reancla la cápsula al piso preservando primero su geometría real en el mundo. La cámara compensa internamente esa reubicación del root y después interpola a su altura de crouch de piso; así no da un salto visual. Esto no crea un segundo estado de crouch.

Para volver a pararse ocurre la operación inversa, pero no se aplica a ciegas:

```text
H0 solicita postura normal
        ↓
V3PhysicsBody consulta si la cápsula alta cabe en el espacio actual
        ↓
si cabe: restaura postura normal
si no cabe: permanece agachado y publica `stand_request_blocked`
        ↓
en el tick siguiente, H0 descarta esa orden fallida y vuelve a
guardar crouch como postura deseada
```

Por eso no alcanza con bajar la cápsula completa: debe cambiar de tamaño. Una cápsula alta desplazada hacia abajo seguiría ocupando la altura de un player parado y no entraría en huecos bajos.

Una orden de pararse bloqueada no es un buffer. No queda guardada para ejecutarse cuando el techo desaparezca: H0 la considera fallida. Al salir de la cobertura baja, el player sigue agachado hasta que una nueva pulsación pida volver a pararse.

El collider cambia en un único tick físico. La cámara compartida interpola su altura durante aproximadamente `0.17 s` para que la transición visual no se sienta instantánea; esa interpolación no retrasa ni modifica la postura física.

## Aire

Cuando el body deja el piso, H0 mantiene control horizontal durante una ventana de laboratorio. Después de esa ventana, reutiliza la velocidad horizontal real publicada por el body: deja de corregir la trayectoria hasta volver al suelo.

El temporizador pertenece al control aéreo, no al salto sostenido ni a la penalización de caída.

## Valores actuales del laboratorio

Estos números permiten probar el circuito; no son balance final de V3.

| Parámetro | Valor actual |
|---|---:|
| Velocidad normal | `5.0` |
| Velocidad agachado | `2.5` |
| Velocidad sprint | `8.0` |
| Transición caminar ↔ sprint en piso | `0.2 s` |
| Desaceleración aérea al soltar Shift | `8.0 m/s²` |
| Impulso de salto | `5.0` |
| Cápsula normal | `1.8 m` de alto |
| Cápsula agachada | `1.2 m` de alto |
| Ventana de control aéreo | `0.35 s` |
| Transición visual de cámara al crouch de piso | ~`0.17 s` |
| Umbral de caída que penaliza salto | `5.0 m` de laboratorio |

## Caída y penalización de salto

La capa física acumula sólo el descenso real mientras el body está en aire. No adivina alturas ni usa la intención de H0.

```text
body cae
        ↓
V3PhysicsBody suma los metros realmente descendidos
        ↓
body aterriza
        ↓
publica `last_landing_fall_distance` durante el tick siguiente
        ↓
FallDamageState compara esa distancia contra su umbral de laboratorio
        ↓
si la supera: publica `jump_is_penalized = true`
        ↓
H0 deja de pedir saltos aunque Espacio siga sostenido
```

`last_landing_fall_distance` es un hecho puntual: aparece al aterrizar y luego vuelve a cero. En cambio, `jump_is_penalized` es un estado persistente. No se quita por tiempo; en el laboratorio sólo se puede quitar mediante `clear_jump_penalty()`, pensado para que en el futuro lo invoque el sistema que resuelva recuperación, muerte o reinicio.

## Datos visibles en el debug

| Campo | Significado |
|---|---|
| `input crudo` | Eje WASD leído este tick. |
| `sprint: input` | Shift está sostenido en la fuente de input. |
| `sprint: aplicado` | H0 puede aplicar sprint; es falso si la postura actual lo impide en piso. |
| `sprint: vel` | Velocidad horizontal solicitada durante la transición de piso. |
| `sprint: transición` | Tiempo restante para llegar a la velocidad de caminar o sprint. |
| `salto: intención sostenida` | Espacio está presionado. |
| `salto: pedido` | H0 solicitó salto a la capa física. |
| `salto: aceptado` | La capa física verificó suelo y aplicó el impulso. |
| `agachado: deseado` | La postura que H0 solicitó con su estado persistente. |
| `agachado: físico` | La postura que la capa física pudo aplicar realmente. |
| `ancla` | `piso`: pies fijos; `aire`: centro fijo y pies elevados. |
| `pararse bloqueado` | H0 pidió volver a estar de pie, pero la cápsula alta no entra. |
| `caída: tramo actual` | Descenso acumulado de la caída que aún sigue en curso. |
| `caída: último aterrizaje` | Distancia descendida al aterrizar; es puntual, no histórica. |
| `lesión bloquea salto` | La condición persistente que impide a H0 solicitar salto. |
| `control aire` | Tiempo que queda de corrección horizontal libre en aire. |
| `intención H0` | Velocidad horizontal que H0 pidió. |
| `velocidad/desplazamiento real` | Lo que el collider logró después de simulación. |
| `en piso/contactos` | Hechos físicos posteriores a `move_and_slide()`. |

## Límites actuales del laboratorio

- Sólo existe H0; no hay Hanging, Ladder, Mantle ni árbitro.
- El umbral de caída que penaliza salto es una variable de prueba, no un valor de gameplay aprobado.
- La penalización no está conectada a vida, curación, animaciones ni muerte.
- La preferencia de sprint alternado, tercera persona e inclinación/orientación híbrida todavía no entraron en este laboratorio.
- El `FallDamageState` es una implementación mínima para probar una señal externa. No determina la arquitectura final del sistema de daño.

## Cobertura automática actual

`scenes/test/v3_h0_smoke_test.gd` verifica, sin tocar Player V2:

- apoyo inicial, desplazamiento y colisión contra pared;
- sprint con aceleración/frenado de `0.2 s` en piso, salto con Shift, inercia al soltarlo en aire y aterrizaje caminando;
- salto desde piso y aterrizaje;
- salto repetido al mantener Espacio;
- caída que activa penalización persistente de salto;
- crouch de piso, descenso de cámara y techo bajo;
- orden de pararse rechazada que no queda pendiente al salir de cobertura;
- crouch activado en aire, ancla aérea, retorno al ancla de piso al aterrizar y posterior vuelta a postura normal.
