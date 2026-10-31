## Punto de partida

Con **Godot 4.x y un jugador como host**, recomiendo que el host sea el servidor autoritativo: cada cliente mueve inmediatamente su propio personaje mediante predicción, mientras el host valida las entradas y decide el estado real. Los demás jugadores se muestran con interpolación de estados recibidos. Esto responde rápido al control y evita que una animación o una posición enviada por un cliente se convierta por sí sola en una acción válida.

Uso la documentación de **Godot 4.5** como referencia concreta dentro de 4.x. La subversión exacta puede cambiar nombres o detalles de configuración; antes de implementar, habría que contrastar las llamadas con la documentación de la versión instalada. El modelo de movimiento y red propuesto no depende de una función exclusiva de 4.5.

### Qué está documentado y qué propongo

| Origen | Conclusión que sí sostiene |
|---|---|
| **Charla de Techland** | Bartosz Kulon presenta los problemas y soluciones de movimiento, carrera y trepada en primera persona de *Dying Light*. La ficha pública describe el alcance de la charla; **no permite atribuirle un algoritmo concreto de detección**. [GDC Vault: Parkour in First-Person Games](https://gdcvault.com/play/1025208/Parkour-How-to-Improve-Freedom) |
| **Charla de DICE** | La creación de un personaje de cuerpo completo creíble en primera persona exigió trabajo específico de animación y herramientas. La ficha tampoco documenta sus reglas internas de selección de obstáculos. [GDC Vault: Creating First Person Movement for Mirror’s Edge](https://www.gdcvault.com/play/1012172) |
| **Charla de Insomniac** | En traversal rápido, cámara y sensación de velocidad se diseñan junto al movimiento; las diapositivas explican, entre otras decisiones, el ajuste del campo de visión según la velocidad. [Concrete Jungle Gym, GDC 2019](https://media.gdcvault.com/gdc2019/presentations/Sheahan_Doug_ConcreteJungleGym.pdf) |
| **Godot** | `CharacterBody3D` ofrece movimiento con colisiones, suelo y paredes; las consultas de rayos y formas permiten comprobar geometría y espacio libre; `AnimationTree` admite mezclas y extracción de root motion. [CharacterBody3D](https://docs.godotengine.org/en/4.5/classes/class_characterbody3d.html), [PhysicsDirectSpaceState3D](https://docs.godotengine.org/en/4.5/classes/class_physicsdirectspacestate3d.html), [AnimationTree](https://docs.godotengine.org/en/4.5/tutorials/animation/animation_tree.html) |
| **Técnica de red documentada** | Predicción con entradas guardadas, corrección y repetición de entradas; interpolación de snapshots para entidades remotas. Son técnicas generales, no funciones automáticas del controlador de Godot. [Glenn Fiedler: Networked Physics](https://www.gafferongames.com/post/networked_physics_2004/), [Snapshot Interpolation](https://www.gafferongames.com/post/snapshot_interpolation/), [Unreal: Networked Movement](https://dev.epicgames.com/documentation/unreal-engine/understanding-networked-movement-in-the-character-movement-component-for-unreal-engine) |

**Mi inferencia:** un parkour arcade en red funciona mejor si el desplazamiento y las transiciones de acción tienen reglas numéricas compartidas por cliente y host, y las animaciones se adaptan a esas reglas. No afirmo que los juegos citados usen exactamente esta arquitectura.

## Movimiento y detección

Partiría de una **cápsula de `CharacterBody3D`**, simulada a paso fijo. El motor de movimiento conserva velocidad, aceleración, gravedad, estado de suelo, dirección de pared, acción actual y temporizadores. `move_and_slide()` es adecuado para correr, saltar y deslizarse, pero el comportamiento especial de cada acción debe programarse. Godot indica que se invoque durante el paso de física y que su `velocity` se exprese como velocidad, sin multiplicarla previamente por `delta`. [Documentación de CharacterBody3D](https://docs.godotengine.org/en/4.5/classes/class_characterbody3d.html)

La detección debe usar la **dirección de desplazamiento o de la intención de movimiento**, no depender sólo de hacia dónde mira la cámara:

1. Una consulta frontal baja localiza el obstáculo y su normal.
2. Una consulta frontal alta comprueba si la parte superior está libre.
3. Una consulta hacia abajo, desde delante y encima del obstáculo, encuentra su superficie superior y estima altura y profundidad.
4. Una barrida de la cápsula comprueba que cabe el cuerpo durante el recorrido y en el punto de llegada.
5. Para un borde, se comprueba además que haya pared bajo la arista, espacio para agarrarse y un destino válido para subir.
6. Para deslizarse, se comprueba el espacio con la cápsula reducida y, antes de levantarse, con la cápsula normal.

Los rayos son baratos y precisos para hallar superficies; las **barridas de formas** evitan aceptar un trayecto por el que no cabe el personaje. `ShapeCast3D` cuesta más que un rayo, por lo que usaría pocas barridas sobre candidatos prometedores, en vez de barrer todos los obstáculos cada frame. Las consultas inmediatas son útiles cuando el sensor cambia de posición en el mismo tick. [RayCast3D](https://docs.godotengine.org/en/4.5/classes/class_raycast3d.html), [ShapeCast3D](https://docs.godotengine.org/en/4.5/classes/class_shapecast3d.html)

Para la primera versión, haría **geometría estática con capas de colisión y superficies aptas explícitas**. Las paredes móviles y el parkour sobre otros jugadores aumentan mucho las discrepancias entre predicción y host. Cada superficie especial puede tener un identificador estable y metadatos de diseño —por ejemplo, permite carrera lateral—, pero el host siempre verifica colisión, distancia, ángulo y espacio libre. Un identificador de instancia local de Godot no sirve como identificador de red. [MultiplayerSynchronizer](https://docs.godotengine.org/en/4.5/classes/class_multiplayersynchronizer.html)

### Selección de acciones

Propongo un **selector con prioridades explícitas**, condiciones de entrada, duración mínima y reglas de cancelación. Así se evita que una pared válida para varias acciones produzca resultados arbitrarios:

| Acción | Condición principal | Regla para conservar fluidez |
|---|---|---|
| Salto | Pulsación, suelo válido o breve tolerancia tras abandonarlo | Guardar la pulsación unos pocos ticks antes de aterrizar; aplicar impulso en el primer tick válido. |
| *Vault* | Obstáculo bajo, borde superior y salida despejada | Conservar gran parte de la velocidad horizontal; permitir control limitado durante la acción. |
| Trepada | Superficie demasiado alta para *vault*, punto de apoyo y llegada despejada | Movimiento guiado hacia un ancla validada, con prueba de colisión durante el ascenso. |
| Deslizamiento | Velocidad mínima, entrada del jugador y altura reducida válida | Mantener inercia y fricción controlada; impedir levantarse bajo un techo. |
| Carrera por pared | En el aire, pared lateral válida, dirección y velocidad suficientes | Proyectar velocidad sobre la pared; límite de tiempo y salida clara con salto. |
| Agarre de borde | Caída o salto cerca de una arista alcanzable, con espacio para el cuerpo | Breve ventana de captura; opciones de soltar o subir. |

Las cifras de altura, ángulo, tiempo y velocidad son **parámetros de diseño**, no constantes tomadas de esos juegos. Usaría tolerancias pequeñas de entrada y de suelo, pero las mediría en ticks y las validaría igual en cliente y host. También conviene registrar *por qué* se rechazó cada candidato y dibujar sensores y anclas en un modo de depuración.

## Alternativas y costos

| Decisión | Ventaja | Límite y costo |
|---|---|---|
| **Geometría libre con rayos y barridas** | Más libertad para construir rutas | Casos difíciles en mallas irregulares, esquinas y objetos móviles; más consultas y pruebas. |
| **Marcadores o superficies etiquetadas** | Resultados previsibles, buenos para niveles cuidados y red | Trabajo de autoría; limita el movimiento donde faltan marcas. |
| **Híbrido — recomendado** | Detección geométrica general y etiquetas sólo para excepciones o rutas especiales | Dos sistemas que hay que mantener coherentes. |
| **Movimiento guiado por reglas, animación adaptada — recomendado** | Entrada inmediata y simulación de red más estable | Puede exigir ajuste visual de manos y pies. |
| **Root motion como autoridad del desplazamiento** | Contactos animados muy precisos | Cambiar, cancelar o repetir una acción tras una corrección de red se vuelve más complejo. Godot permite extraer root motion, pero eso no resuelve por sí solo la predicción. [AnimationTree](https://docs.godotengine.org/en/4.5/tutorials/animation/animation_tree.html) |

Para *vault* y trepada usaría una **trayectoria de movimiento definida por código**, con inicio y ancla validados, colisión durante el avance y animación ajustada a la duración. La animación puede aportar desplazamientos visuales y contactos de manos, pero no decide dónde queda la cápsula. En carrera, salto y pared, el motor de movimiento conserva el control continuo.

## Multijugador con host de jugador

En Godot, el servidor tiene por defecto la autoridad de red, y `ENetMultiplayerPeer` permite crear el servidor en el equipo del host y conectar clientes. Mantendría **la autoridad de los nodos de personaje en el host**; no transferiría `set_multiplayer_authority()` al dueño del control. El cliente puede enviar entradas mediante un RPC `any_peer`, pero el host comprueba que el emisor corresponde a ese personaje. La API de alto nivel no vuelve segura la lógica de juego automáticamente. [High-level multiplayer de Godot](https://docs.godotengine.org/en/4.5/tutorials/networking/high_level_multiplayer.html), [Node.set_multiplayer_authority](https://docs.godotengine.org/en/4.5/classes/class_node.html)

**Flujo recomendado:**

- **Jugador local cliente:** muestrea entrada en cada tick, simula enseguida, guarda entrada y estado previsto, y envía paquetes con número de tick o secuencia. Si se pierde un paquete, las pulsaciones únicas —salto, agarre, inicio de deslizamiento— deben seguir presentes en un pequeño historial de entradas hasta recibir acuse; no basta con enviar un evento una sola vez.
- **Host:** acepta sólo entradas del dueño, en orden lógico y dentro de límites de tiempo, magnitud y giro; simula su propio tick fijo; repite las consultas de parkour y decide si empieza, continúa o termina cada acción.
- **Corrección:** el host devuelve estado autoritativo y último tick de entrada procesado. El cliente restaura ese estado, repite las entradas pendientes y suaviza **sólo la representación visual** de una diferencia pequeña. Una diferencia grande o un cambio de acción exige corrección visible e inmediata.
- **Otros jugadores:** reciben estados con tick o tiempo del host y los muestran desde un pequeño búfer. Se interpola entre dos estados conocidos; la extrapolación, si se usa, debe ser breve. Godot también ofrece interpolación física de transforms, pero su documentación advierte que en multijugador por internet puede convenir una interpolación propia porque los snapshots no coinciden necesariamente con los ticks locales. [Interpolación física de Godot](https://docs.godotengine.org/en/4.5/tutorials/physics/interpolation/physics_interpolation_introduction.html), [Snapshot Interpolation](https://www.gafferongames.com/post/snapshot_interpolation/)

Empezaría probando **60 ticks de simulación por segundo** y **15–30 snapshots por segundo**; son valores iniciales para medir, no requisitos. Separaría los flujos de entradas, snapshots y mensajes fiables en canales apropiados; la documentación de Godot describe los modos fiable, no fiable y no fiable ordenado, así como sus costos. [Canales y RPC de Godot](https://docs.godotengine.org/en/4.5/tutorials/networking/high_level_multiplayer.html)

| Enviar por red | Calcular localmente |
|---|---|
| Cliente → host: tick, ejes de movimiento, orientación o intención de movimiento, botones mantenidos y pulsaciones identificables | Sensores para predicción, cámara, sacudidas, FOV, efectos y mezcla fina de animaciones |
| Host → jugadores: tick, posición, velocidad, orientación corporal, estado de movimiento, acción, inicio de acción, ancla o destino estable cuando corresponda, último input confirmado | Pose de esqueleto, contactos visuales, transición de `AnimationTree`, sonidos que se puedan deducir del estado |
| Host → jugadores: inicio, cancelación o resultado de acciones que no se reconstruyan sin ambigüedad de snapshots | Ninguna posición propuesta por el cliente se acepta como resultado autoritativo |

**Limitación importante:** la repetición de entradas con `CharacterBody3D` y consultas físicas puede divergir entre máquinas, sobre todo con plataformas móviles o colisiones entre personajes. No asumiría determinismo exacto. Mantendría inicialmente el entorno de traversal estático, mediría la frecuencia y magnitud de las correcciones y ajustaría la simulación. El host conserva ventaja de latencia y control sobre la partida; la migración de host sería una función posterior, con un protocolo específico.

## Escenas y componentes, sin singleton ni Autoload

```text
Main.tscn
├── MenuUI
└── MatchRoot                 # Instanciado al crear o unirse a una partida
    ├── NetworkSession        # Crea ENet peer; señales de conexión y desconexión
    ├── MatchController       # Ticks, reglas de partida, asociación peer → jugador
    ├── Level
    ├── PlayerSpawner         # MultiplayerSpawner
    └── Players
        └── Player.tscn       # Una instancia por participante
            ├── CharacterBody3D
            │   ├── CollisionShape3D
            │   ├── ParkourSensors
            │   ├── MovementMotor
            │   ├── ActionSelector
            │   ├── NetworkDriver
            │   └── Visuals
            │       ├── AnimationPlayer
            │       ├── AnimationTree
            │       └── ViewRig
            │           ├── FirstPersonCamera
            │           └── ThirdPersonCamera
```

`MatchRoot` pasa referencias a sus hijos al crearlos; los componentes del jugador se comunican con referencias locales y señales. `NetworkSession` vive dentro de la escena de partida, y `PlayerSpawner` crea los mismos nodos y nombres en todos los peers. `MultiplayerSpawner` documenta el alta y baja de escenas desde la autoridad; `MultiplayerSynchronizer` puede servir para propiedades sencillas, pero usaría un `NetworkDriver` propio para entradas con secuencia, reconciliación y búfer de snapshots. Evitaría que un sincronizador sobrescriba directamente el transform del jugador que está prediciendo. [MultiplayerSpawner](https://docs.godotengine.org/en/4.5/classes/class_multiplayerspawner.html), [MultiplayerSynchronizer](https://docs.godotengine.org/en/4.5/classes/class_multiplayersynchronizer.html)

## Primera y tercera persona

La **cápsula, sensores, acciones y reglas de red deben ser los mismos** en ambas vistas. Cambia el `ViewRig`: en primera persona, cámara cerca de la cabeza pero desacoplada de golpes bruscos del esqueleto, manos o cuerpo visibles según la acción y movimiento de cámara moderado para evitar mareo. En tercera persona, cámara con seguimiento, prueba de oclusión contra paredes, lectura clara de la silueta y animaciones de cuerpo completo. El campo de visión y la distancia de cámara pueden variar con la velocidad, como recurso visual documentado por Insomniac, pero no deben cambiar el alcance real de los sensores ni la validación del host. [Concrete Jungle Gym](https://media.gdcvault.com/gdc2019/presentations/Sheahan_Doug_ConcreteJungleGym.pdf)

## Prototipo mínimo y orden

1. **Movimiento local:** cápsula, aceleración, salto, control aéreo, deslizamiento, cámara intercambiable y sensores dibujados. Medir respuesta desde pulsación hasta movimiento.
2. **Obstáculos estáticos:** *vault*, agarre y trepada en una pista pequeña con tamaños variados; rechazo claro cuando falta espacio de salida.
3. **Red con dos instancias:** host y un cliente, entradas por tick, predicción, snapshots, acuse y reconciliación. Probar pérdida, latencia y cambios de dirección durante un *vault*.
4. **Acciones avanzadas:** carrera por pared, cancelaciones, esquinas, interacción con otras colisiones y animaciones completas.
5. **Pulido y escala:** interpolación de remotos, cámaras, efectos, presupuesto de consultas, más jugadores y métricas de correcciones.

El **MVP jugable** termina en la etapa 3: una pista corta en la que dos jugadores pueden correr, saltar, deslizarse y hacer *vault* con ambas cámaras, mientras el host y el cliente coinciden razonablemente tras latencia simulada.

### Pseudocódigo esencial

```text
physics_tick(input, state):
    intent = movement_direction(input.axes, input.view_yaw)
    observations = sensors.query(state.position, intent, state.velocity)

    candidate = action_selector.choose(
        input, state, observations,
        priority = [continue_current, ledge_grab, vault_or_climb,
                    wall_run, slide, jump, ordinary_motion]
    )
    state.action = validate_transition(state, candidate, observations)

    velocity = motor.apply_action_rules(state, input, fixed_delta)
    body.velocity = velocity
    body.move_and_slide()
    state = capture_body_and_action_state(body, state)
    return state
```

```text
cliente, cada tick:
    input = sample_input_with_tick()
    predicted_state = physics_tick(input, predicted_state)
    pending_inputs.push(input, predicted_state)
    send_recent_inputs_to_host()

host, cada tick:
    for player:
        input = take_valid_input_for_tick(player)  # emisor, secuencia y límites
        authoritative_state = physics_tick(input, authoritative_state)
    periodically_send_snapshot(states, last_processed_input)

cliente, al recibir corrección:
    restore(authoritative_state_at_ack)
    discard_inputs_through(ack)
    for input in pending_inputs:
        predicted_state = physics_tick(input, predicted_state)
    smooth_visual_offset_if_small()
```

En una acción guiada, `validate_transition` calcula y valida en el host el **ancla, recorrido y espacio final**; el estado transmite un identificador de acción y su tick de inicio. Cliente y host pueden así reproducir la misma intención, mientras la animación se sincroniza con el progreso autorizado. La prueba decisiva será cuántas veces esa reproducción discrepa con colisiones reales: ese dato debe guiar el ajuste del sistema, no sólo cómo se ve en una partida local.
