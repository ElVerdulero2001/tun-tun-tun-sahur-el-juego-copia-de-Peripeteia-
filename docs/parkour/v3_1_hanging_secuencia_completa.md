# V3.1 — Hanging: secuencia completa del runtime actual

> Consolida los nueve cuadros de la entrada a Hanging que existe en
> scenes/test/v3_hanging_detection_lab.tscn. No propone comportamiento futuro
> ni modifica la implementación.

## Cadena corta

    H0 mueve al player
    → player queda en aire
    → rayos encuentran pared y tapa
    → evaluator crea candidata y pose P
    → aparecen cilindro C y esfera S
    → primer contacto C/S
    → Hanging encola snap
    → Body aplica snap a P en el tick siguiente

## Actores y orden de un tick físico

| Prioridad | Actor | Publica o aplica |
| ---: | --- | --- |
| -200 | V3InputSource | Input actual. |
| 0 | H0Core | Intención de locomoción, si no está suspendido. |
| 100 | V3PhysicsBody | Movimiento, gravedad, snap o launch pendientes. |
| 140 | V3ForwardWallProbe | Muestras de pared. |
| 141 | V3TopSurfaceProbe | Pares pared/tapa. |
| 142 | V3FrontVolumeProbe | Debug solamente. |
| 150 | V3HangingCandidateEvaluator | Candidata y pose P. |
| 155 | V3HangingCaptureProbe | Cilindro, esfera y contacto. |
| 160 | V3HangingCore | Entrada, retención o salida. |
| 200 | V3CameraRig | Presentación de cámara. |

Cuando H0 cede locomoción a un core contextual, reinicia
air_control_time a su duración base de 0.35 s. Una decisión de Hanging en prioridad 160 sólo puede ser aplicada por el body,
en prioridad 100, durante el tick físico siguiente.

## Cuadro 1 — H0 en piso

    is_on_floor = true

| Parte | Información |
| --- | --- |
| Actúa | H0Core._physics_process(), luego V3PhysicsBody._physics_process(). |
| Consume | Input, dirección de cámara y physics_body.get_physics_facts(). |
| Hace | H0 publica submit_motion_intent(...); el body aplica locomoción normal. |
| Produce | Hechos físicos actuales, incluido is_on_floor. |
| Para seguir | Hay que salir del piso. El evaluator agrega rechazo en_piso. |

Las sondas ya existen y corren. Piso no las desactiva; sólo bloquea que Hanging
acepte la candidata.

## Cuadro 2 — Acercamiento

    H0 activo
    is_on_floor = true

| Parte | Información |
| --- | --- |
| Actúa | V3InputSource → H0Core → V3PhysicsBody. |
| Consume | movement_axis, adelante y derecha planos de cámara. |
| Hace | H0 calcula velocidad horizontal y el body llama move_and_slide(). |
| Produce | Nueva posición frente al muro. |
| Para seguir | Acercarse no alcanza: el body debe quedar en aire. |

## Cuadro 3 — Salto o caída

    is_on_floor = false

| Parte | Información |
| --- | --- |
| Actúa | H0 y body. |
| Consume | jump_pressed, is_on_floor y penalización de daño por caída. |
| Hace | Si H0 pidió salto desde piso, el body usa velocity.y = jump_velocity; fuera de piso aplica gravedad. |
| Produce | El hecho relevante pasa a ser is_on_floor = false. |
| Para seguir | La geometría puede llegar a ser candidata. No hace falta caer: captura también puede pasar subiendo. |

## Cuadro 4 — Rayos horizontales de pared

    V3ForwardWallProbe._physics_process()
    prioridad 140; mismo tick, después del movimiento del body

### Datos que consume

    physics_body.global_position
    camera_rig.get_planar_forward()
    probe_heights = [0.3, 0.6, 0.9, 1.2, 1.5]
    detection_distance = 0.85 m
    collision_mask del body
    RID del body, excluido para no chocarse a sí mismo

### Consulta a Godot

Por cada altura:

    origin = physics_body.global_position + Vector3.UP * height
    end = origin + last_planar_forward * detection_distance
    hit = world.direct_space_state.intersect_ray(query)

Godot calcula la intersección de cada rayo con los colliders del mundo.

### Resultado

    last_planar_forward
    last_wall_samples = [
      { height, origin, hit },
      ...
    ]

Cuando hay impacto, hit contiene position, normal y collider. “Pared detectada”
equivale a que uno o más hit no estén vacíos. Todavía no hay tapa, candidata,
edge_point ni movimiento de Hanging.

## Cuadro 5 — Rayo vertical de tapa

    V3TopSurfaceProbe._physics_process()
    prioridad 141; mismo tick, después de WallProbe

| Parte | Información |
| --- | --- |
| Consume | Cada wall_hit, posición del body, normal de pared, máscara y RID. |
| Cálculo | Por cada pared tira un rayo vertical desde body.y + 1.8 hasta la altura del impacto, con offset -wall_normal * 0.08. |
| Consulta a Godot | Otro world.direct_space_state.intersect_ray(query). |
| Produce | last_surface_samples[] = { wall_hit, top_hit }. |
| Para seguir | Debe existir una pareja pared/tapa que el evaluator acepte. |

    from = Vector3(wall_point.x, body.y + 1.8, wall_point.z) - wall_normal * 0.08
    to   = Vector3(wall_point.x, wall_point.y,       wall_point.z) - wall_normal * 0.08
    top_hit = world.direct_space_state.intersect_ray(query)

top_hit.position es la intersección rayo vertical–collider. Godot no descubre
una arista matemática: devuelve un punto de la tapa, apenas hacia su interior.

## Cuadro 6 — Candidata, edge_point y pose P

    V3HangingCandidateEvaluator._physics_process()
    prioridad 150; mismo tick

| Parte | Información |
| --- | --- |
| Consume | Hechos del body, last_wall_samples, last_surface_samples, dirección de cámara e input de movimiento. |
| Descarta | Sin pared/tapa, pared o tapa demasiado inclinada, cámara no orientada hacia la pared, distancia XZ > 0.35 m, altura fuera de [0.5, 1.5] m, player en piso, intención opuesta o P bloqueada. |
| Elige | Entre las parejas válidas, la de mayor alineación con la cámara. |
| Produce | Pared, normal, soporte, edge_point, pose P y razones de rechazo. |
| Para seguir | candidate.is_valid = true. P sólo es un dato: no mueve al player. |

    candidate.edge_point = top_hit.position
    candidate.wall_point = wall_hit.position
    candidate.wall_normal = wall_hit.normal
    candidate.support_id = collider.get_instance_id()

Por lo tanto, edge_point es el top_hit.position que Godot devolvió para el rayo
vertical y que el evaluator adopta como borde del candidato. No es una
intersección entre el rayo horizontal y el vertical.

La pose de agarre se forma así:

    P.origin = edge_point + wall_normal * 0.68 + Vector3.UP * -1.5
    P.basis = Basis.looking_at(-wall_normal, Vector3.UP)
    candidate.hang_pose_clear = physics_body.can_occupy_pose(P)

## Cuadro 7 — Cilindro C y esfera S

    V3HangingCaptureProbe._physics_process()
    prioridad 155; mismo tick

Sólo corre como zona de captura si candidate.is_valid = true.

| Parte | Información |
| --- | --- |
| Consume | wall_point, edge_point, wall_normal, support_id y transform del body. |
| Calcula | C: cilindro de captura del muro, radio 0.18 m y altura 0.25 m. S: esfera alta del player, radio 0.10 m. |
| Produce | Centro de C/S, distancia, profundidad de solapamiento y estado de contacto. |
| Visual | Las mallas se crean ocultas en _ready(); se vuelven visibles aquí. |
| Para seguir | C y S deben tocarse o cruzarse entre ticks. Visibilidad sola no entra a Hanging. |

    S = body.global_transform * Vector3(0, 1.30, 0)

## Cuadro 8 — Contacto y decisión

    CaptureProbe: prioridad 155
    HangingCore: prioridad 160
    mismo tick físico

CaptureProbe calcula contacto actual y, cuando las dos muestras pertenecen al
mismo support_id, barrido entre ticks:

    contact_seen = last_sensor_touches_disk or last_swept_contact
    last_contact_event = contact_seen and not _contact_was_seen

Un contacto sostenido no vuelve a producir evento; sólo el primer toque o
cruce produce last_contact_event = true.

### Gates de V3HangingCore._try_enter()

    recapture_locked = false
    candidata válida y con pose
    P libre
    Ctrl no mantenido y body no agachado
    last_contact_event = true

Si pasan:

    held_pose = candidate.hang_pose
    held_edge_point = candidate.edge_point
    held_wall_normal = candidate.wall_normal
    state = HANGING
    h0.set_locomotion_suspended(true)
    # H0 guarda una ventana base de control aéreo de 0.35 s
    physics_body.submit_pose_snap(self, held_pose)

El core cambia su estado local y encola una orden. Todavía no escribe el
transform del player.

## Cuadro 9 — Snap físico: Hanging

    V3PhysicsBody._physics_process()
    prioridad 100 del tick físico siguiente

| Parte | Información |
| --- | --- |
| Consume | Snap pendiente con target_pose = held_pose = P. |
| Consulta | Repite can_occupy_pose(P). |
| Hace si acepta | Asigna global_transform = P, pone velocidad cero y reinicia la caída. |
| No hace | No llama move_and_slide() durante ese snap. |
| Después | Limpia órdenes H0 pendientes. Hanging retiene P en ticks posteriores hasta una salida. |

    global_transform = P
    velocity = Vector3.ZERO
    fall_distance_in_current_airtime = 0.0
    last_snap_accepted = true

Si el body rechaza P, Hanging detecta el snap rechazado en su ciclo posterior,
libera el estado y H0 vuelve a tomar locomoción.

## Salida con Espacio — retorno a la política única de H0

Hanging no reinicia ni configura el control aéreo al salir. Sólo devuelve la
locomoción a H0 y solicita el launch:

    h0.set_locomotion_suspended(false)
    physics_body.submit_launch(self, last_jump_exit_velocity)

`H0.air_control_duration` es `0.75 s` para todas las entradas y salidas. El
body aplica el launch en el tick siguiente; desde allí H0 gobierna con esa
única ventana, sin excepción específica de Hanging.

## Fuera de estos nueve cuadros

    FrontVolumeProbe: sólo debug; no habilita ni bloquea entrada.
    Shimmy: comportamiento posterior a la captura; no participa en esta entrada.
    Mantle/subida: no implementado.
    Animación/IK/manos: no implementados.
    PlayerV2 legacy: el laboratorio no está integrado allí.

## Fuentes de verdad

    scenes/test/v3_hanging_detection_lab.tscn
    scripts/player_v2/parkour_v3/v3_input_source.gd
    scripts/player_v2/parkour_v3/h0_core.gd
    scripts/player_v2/parkour_v3/v3_physics_body.gd
    scripts/player_v2/parkour_v3/v3_camera_rig.gd
    scripts/player_v2/parkour_v3/v3_forward_wall_probe.gd
    scripts/player_v2/parkour_v3/v3_top_surface_probe.gd
    scripts/player_v2/parkour_v3/v3_hanging_candidate_evaluator.gd
    scripts/player_v2/parkour_v3/v3_hanging_capture_probe.gd
    scripts/player_v2/parkour_v3/v3_hanging_core.gd
