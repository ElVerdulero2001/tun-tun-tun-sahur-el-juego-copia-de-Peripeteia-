# V3 Hanging — captura por sondas implementada

## Estado

> **Decisión vigente:** **Switchboard = descartado.** No existe como
> infraestructura futura de V3 ni como dependencia, capacidad o tema pendiente
> de Hanging. Ningún diseño posterior debe proponerlo, simularlo o reservarle
> compuertas.

**Laboratorio implementado y verificado el 2026-09-19.** Este documento fija
el corte concreto que deriva de `v3_hanging_captura_sondas_borrador.md`.
No convierte sus temas abiertos en decisiones globales: no implementa mantle,
esquinas, soporte móvil ni animación.

La escena es `scenes/test/v3_hanging_detection_lab.tscn` y sigue aislada de
`PlayerV2` legacy.

## Regla de entrada que quedó en runtime

```text
probes de pared/tapa + body en aire + intención compatible + pose P libre
    → candidata Hanging válida
    → se muestra el disco C y se actualiza la esfera S
    → S toca o cruza C entre ticks
    → HangingCore toma H0 y pide snap a P
    → V3PhysicsBody aplica el snap en el tick siguiente
```

Una candidata sola no captura. cilindro/esfera no mueve ni arbitra: es la única señal de
tiempo que `HangingCore` acepta para entrar. La latencia de un tick entre la
orden y el snap es intencional y visible en la telemetría.

## Sondas

`V3HangingCaptureProbe` vive entre el evaluator y el core (prioridad física
155; core en 160). Sus referencias son explícitas al `V3PhysicsBody` y al
`V3HangingCandidateEvaluator`.

### Disco de pared C

- Es un cilindro bajo de eje vertical; su cara superior queda al nivel del
  borde y su espesor baja desde ahí.
- Su punto más interno queda en la cara real de la pared; el sólido se
  desplaza sólo hacia la normal exterior. No invade el muro.
- Sigue la coordenada tangencial del body sobre ese muro; no queda congelado
  en la muestra lateral que originó la candidata.
- En el laboratorio sus exports son `capture_disk_radius = 0.18 m` y
  `capture_disk_thickness = 0.25 m`.

### Esfera del player S

- Su centro es `body.global_transform * player_sensor_local_offset`; no
  depende de cámara, pivote ni collider por separado.
- Posición y radio se ajustan de forma independiente a P: deciden **cuándo**
  se captura, no dónde termina el body.
- Valores actuales: `player_sensor_local_offset = (0, 1.30, 0)` y radio
  `0.10 m`.

La visualización rosa/azul es sólo debug y no introduce colliders de gameplay.

## Contacto continuo

Cada tick calcula la distancia exacta de S al sólido del cilindro. Además
guarda la muestra anterior de S y C mientras pertenecen al mismo soporte. Si
el segmento relativo entre ambas muestras pasa por el cilindro, también
publica contacto: no pierde una captura porque el body cruce el disco entre
dos ticks rápidos.

Una candidata inválida reinicia ese historial. Si cambia `support_id`, la
muestra anterior no se usa para el barrido y se sustituye por la del soporte
actual; por lo tanto, el barrido nunca mezcla la posición anterior de una
cornisa con la zona de captura de otra.

`last_contact_event` sólo es verdadero en el primer contacto (actual o por
barrido). Un solapamiento que se mantiene no dispara una entrada tardía si,
por ejemplo, antes estaba bloqueada por crouch.

## Entrada y autoridad

`V3HangingCore` conserva el ciclo local H0 → Hanging → H0. Para entrar exige:

1. candidata válida, incluida la pose P ocupable;
2. ningún lock de reenganche;
3. `Ctrl` no mantenido y body no agachado;
4. `last_contact_event` de cilindro/esfera.

No hay un umbral de velocidad vertical: la misma entrada acepta caída o
ascenso. Mientras Ctrl bloquea, H0 sigue publicando locomoción y el debug
explica `entrada_bloqueada_por_crouch`; la candidata no se oculta.

`V3PhysicsBody` sigue siendo el único nodo que escribe transform, velocidad y
llama `move_and_slide()`. Al aceptar un snap reinicia el tramo de caída
acumulado, por lo que un aterrizaje posterior no puede causar daño por la
caída que el agarre interrumpió.

## Sostén, salidas y capacidades pendientes

El corte mantiene el sostén, shimmy recto, salida con atrás/Ctrl y protección
contra reenganche que ya estaban funcionando en el laboratorio. El
switchboard todavía no existe, por lo que esas capacidades no tienen gates
configurables todavía; no se simuló uno con condiciones dispersas.

Espacio desde Hanging pide un lanzamiento en la dirección completa de cámara,
incluido pitch. Si su dirección horizontal apunta hacia el muro que sostiene
al player, se reemplaza por un salto vertical para no lanzarlo contra el
soporte. La velocidad se regula con `jump_exit_speed`.

## Cobertura automática

`v3_hanging_detection_smoke_test.gd` cubre:

1. rechazo explícito desde piso;
2. candidata aérea sin contacto que no captura;
3. contacto bloqueado por Ctrl/crouch;
4. captura mientras el body asciende;
5. reset de la caída interrumpida;
6. retención, shimmy y límite lateral;
7. salida a H0, lock y nueva captura tras abandonar el disco;
8. salida vertical al mirar el muro y salida dirigida por cámara con pitch.

Se verificó con Godot 4.6.3 en modo headless.

## Mapa exacto de lo implementado

Esta sección es la radiografía del cambio de runtime hecho para este corte.
No describe una arquitectura futura ni convierte los borradores abiertos en
decisiones de sistema.

| Archivo | Cambio concreto | Con quién se comunica |
| --- | --- | --- |
| `v3_hanging_capture_probe.gd` | Implementa cilindro/esfera, visuales, distancia al disco y barrido entre ticks. | Lee `V3HangingCandidateEvaluator` y `V3PhysicsBody`; publica hechos para core/debug. |
| `v3_hanging_candidate.gd` | Agrega `wall_point` y `support_id`. | El evaluator los publica; la sonda los usa para no mezclar barridos entre soportes. |
| `v3_hanging_candidate_evaluator.gd` | Conserva el punto real de pared, identifica su collider, rechaza pose bloqueada y registra `en_piso` aun si la cornisa no alcanza la altura temporal. | Lee providers/body/input/cámara; entrega la candidata a sonda, core y debug. |
| `v3_input_source.gd` | Agrega `crouch_pressed`, además del flanco ya existente. | H0 y Hanging leen la misma fuente de input. |
| `v3_hanging_core.gd` | Reemplaza la entrada automática por un gate de evento cilindro/esfera; elimina el límite de ascenso; agrega salida dirigida por cámara. | Lee candidata, sonda, input y cámara; suspende/reactiva H0 y pide órdenes a Body. |
| `v3_camera_rig.gd` | Expone `get_view_forward()`. | Sólo Hanging lo consume para el salto; conserva cámara como fuente compartida. |
| `v3_physics_body.gd` | Reinicia el tramo de caída al aceptar un snap. | Evita que `V3FallDamageState` atribuya a un aterrizaje una caída que Hanging ya interrumpió. |
| `v3_hanging_debug_overlay.gd` | Añade estado de cilindro/esfera, tipo de contacto y distancia del último snap. | Observa; no toma decisiones ni altera física. |
| `v3_hanging_detection_lab.tscn` | Inserta `HangingCaptureProbe` y conecta sus referencias por `NodePath`. | Orden físico: evaluator 150 → probe 155 → core 160. |
| `v3_hanging_detection_smoke_test.gd` | Sustituye el supuesto de autoenganche por casos de contacto explícito. | Ejecuta el laboratorio real de punta a punta. |

## Detalle por pieza

### `V3HangingCaptureProbe`

No tiene collider ni llama a ninguna API de movimiento. Su salida pública es
una lectura de observación:

```text
last_zone_active             hay candidata válida, por lo que cilindro/esfera existen
last_sensor_touches_disk     S solapa C en esta muestra
last_swept_contact           el recorrido anterior→actual cruzó C
last_contact_event           primer contacto actual o barrido
last_contact_kind            actual / barrido / sostenido
```

La distancia se calcula contra el sólido de un cilindro finito vertical. Para
el barrido, se mide el mínimo de la distancia sobre el segmento relativo
`(S_anterior - C_anterior) → (S_actual - C_actual)`. Eso incluye que C se
mueva lateralmente con el player. Sólo se usa la muestra anterior si el
`support_id` del collider de pared no cambió; al perder candidata se borra el
historial y al cambiar soporte se inhibe ese barrido para ese tick.

El radio, espesor, offset local y radio de S son exports separados. Mover S
ajusta el momento de captura; cambiar `hang_body_offset_from_wall` o
`hang_body_offset_from_edge_y` en el evaluator ajusta P. Ninguno de esos dos
ajustes muta el otro.

### Evaluator y candidata

La candidata mantiene la separación V3 entre hechos y decisión:

```text
ForwardWallProbe / TopSurfaceProbe
        ↓ impactos crudos
HangingCandidateEvaluator
        ↓ candidata válida + P + wall_point + support_id
CaptureProbe / HangingCore / Debug
```

`wall_point` se toma del raycast frontal, no de la tapa desplazada hacia el
interior. Por eso el disco puede tocar la cara exterior sin empezar embutido
en la geometría. `support_id` es el `instance_id` del collider de pared de la
muestra elegida; es identidad de laboratorio, no un contrato de soporte móvil.

El evaluator ahora agrega `pose_de_agarre_bloqueada` si P no cabe. La sonda
por tanto sólo aparece si siguen cumpliéndose los prerrequisitos duros. El
rechazo `en_piso` se registra antes de buscar pared+tapa: si una cornisa queda
demasiado alta para el rango temporal estando en piso, debug muestra tanto la
causa de estado correcta como la falta geométrica secundaria.

### `V3HangingCore`

La entrada activa es exactamente:

```text
INACTIVE
  ├─ lock de recaptura                 → espera
  ├─ sin candidata/P válida            → espera
  ├─ Ctrl mantenido o body agachado    → H0 conserva gobierno
  ├─ sin last_contact_event            → espera contacto cilindro/esfera
  └─ contacto                          → guarda P, suspende H0, pide snap
```

No hay condición sobre `velocity.y`: una esfera que entra al disco durante
un ascenso puede capturar igual que una que cae. El core conserva el snap
físico diferido de un tick para no escribir el body directamente.

Durante HANGING no se reemplazó el ciclo que ya funcionaba: sostiene la pose,
permite shimmy sobre una cara recta y libera con atrás o Ctrl. Esas partes no
pretenden cerrar todavía el contrato de soporte móvil, esquinas ni mantle.

Para Espacio, `get_view_forward()` da la dirección tridimensional de cámara.
Si su proyección horizontal mira hacia el muro almacenado, el core usa
`Vector3.UP`; en otro caso normaliza la dirección completa y la multiplica por
`jump_exit_speed`. `last_jump_exit_velocity` permite observar exactamente qué
solicitud recibió la capa física.

### `V3PhysicsBody` y daño de caída

Al aceptar `submit_pose_snap`, el body ya ponía velocidad en cero. Ahora
también pone `fall_distance_in_current_airtime` en cero. No borra una lesión
que ya hubiera decidido un sistema externo; simplemente separa los dos tramos
físicos de caída para que el aterrizaje posterior mida sólo desde la salida de
Hanging.

## Orden de tick resultante

| Prioridad | Nodo | Hecho u orden |
| ---: | --- | --- |
| -200 | `InputSource` | Lee movimiento, salto y crouch mantenido/flanco. |
| 0 | `H0` | Publica locomoción salvo que Hanging ya lo suspendió. |
| 100 | `V3PhysicsBody` | Consume snap, lanzamiento o locomoción; publica resultados. |
| 140–142 | Providers | Publican pared, tapa y volumen frontal crudos. |
| 150 | `HangingCandidateEvaluator` | Publica candidata y P. |
| 155 | `HangingCaptureProbe` | Publica cilindro/esfera y evento de contacto. |
| 160 | `HangingCore` | Decide entrar, sostener o salir. |
| 200 | `CameraRig` | Actualiza sólo la presentación de cámara. |

Una orden de Hanging en 160 se consume en 100 del tick siguiente. Esto es el
motivo de que el debug y el smoke test diferencien “contacto aceptado” de
“snap aplicado”.

## Qué no se hizo deliberadamente

- No se creó switchboard ni booleanos locales que lo suplanten. Capture,
  shimmy, salto y reenganche siguen activos según el corte actual; el futuro
  switchboard debe consultar las fronteras de transición, no apagar nodos.
- No se implementó Marker3D para geometría no identificable.
- No hay animación, interpolación de snap, manos, mantle, esquinas, soporte
  dinámico ni integración con `PlayerV2` legacy.
- No se introdujo certeza compartida ni árbitro entre cores: Hanging continúa
  siendo el único core contextual del laboratorio.
- El sostén sigue usando la pose retenida actual. Releer soporte y P en cada
  tick es una decisión de diseño V3 posterior, no algo que este cambio finge
  haber resuelto.

## Resultado de la prueba

El smoke test pasó con el mensaje:

```text
V3 Hanging smoke test: captura por sondas, bloqueo, retención,
salida y retorno a H0 OK
```

La prueba cubre contacto actual. El algoritmo de barrido quedó implementado y
visible en debug, pero todavía no tiene una fixture dedicada que fuerce un
cruce completo entre dos ticks; ésa es una prueba puntual útil para el próximo
ajuste de laboratorio, no una afirmación de que ya fue medida a velocidad de
juego.

## Alcance y procedencia de esta bitácora

Éste no es un documento de intención futura: registra **todo el corte que se
añadió o se adaptó para esta intervención**, y diferencia expresamente lo que
ya estaba en el laboratorio. El pedido original fue diseñar el Hanging a partir
del borrador; una vez que se materializó el experimento, este archivo conserva
esa implementación en vez de descartarla. No pretende presentar el resultado
como la versión final de V3.

El contexto consultado para tomar las decisiones fue el siguiente, con sus
papeles delimitados:

| Fuente | Uso en este corte |
| --- | --- |
| `docs/parkour/v3_hanging_captura_sondas_borrador.md` | Fuente del mecanismo cilindro/esfera y de sus preguntas abiertas. Es un borrador, no un contrato que cierre por sí solo Marker3D, switchboard, valores finales ni soporte móvil. |
| `docs/parkour/v3_hanging_ciclo_propuesta.md` | Ciclo local H0 → Hanging → H0 y salidas que debían conservarse. |
| `docs/parkour/v3_hanging_implementacion_minima_actual.md` y `docs/parkour/v3_hanging_radiografia_implementacion_actual.md` | Qué ciclo y laboratorio ya existían, para no atribuirlos a la sonda ni reemplazar la frontera física. |
| `docs/parkour/v3_hanging_plan_funcional_minimo_revision.md`, `docs/parkour/v3_hanging_veredicto_implementacion_actual.md` y `docs/parkour/v3_hanging_auditoria_huecos_y_fallas_filosoficas.md` | Límites y huecos que no se debían declarar resueltos. |
| `docs/parkour/v3_hanging_reutilizacion_v2_consulta_claude.md` y `docs/parkour/v3_hanging_reutilizacion_v2_respuesta_claude.md` | Delimitación con el hanging legacy/V2; no se integró ni reutilizó como autoridad del laboratorio V3. |
| `docs/parkour/v3_mapa_de_ruta_desde_deteccion.md`, `docs/parkour/v3_comparacion_cores_frontera_fisica.md` y `docs/parkour/v3_hanging_laboratorio_mapa_tecnico.md` | Separación V3 entre providers, candidato, core y body, además de orden de tick/laboratorio. |
| `docs/parkour/switchboard_sistema_pruebas.md` | Confirma que el switchboard es una capacidad futura no implementada y que no debía suplantarse con flags locales. |
| Escena, scripts, smoke tests, historial Git y resúmenes accesibles de tareas previas del proyecto | Estado efectivo del árbol de trabajo, decisiones ya probadas y límites de los cambios preexistentes. Se usó para conservar la autoridad física existente y no reintroducir el detector/ciclo legacy eliminado del laboratorio. |

Los documentos anteriores son evidencia de diseño y de decisiones previas; no
son instrucciones que reemplacen el alcance del usuario. Cuando el borrador
dejaba algo abierto, el estado de abajo dice exactamente si se resolvió de
forma provisional o si quedó pendiente.

## Qué ya existía y qué cambió en este corte

| Área | Antes de este corte | Cambio de este corte |
| --- | --- | --- |
| Laboratorio V3 | Ya existían H0, `V3PhysicsBody`, providers, evaluator, una escena aislada y un `HangingCore` con sostén/shimmy/salidas locales. | Se preservaron esas fronteras y se cambió solamente la condición de entrada y los datos necesarios para cilindro/esfera. |
| Autoridad física | El body ya era la única capa que aplicaba `move_and_slide`, snap y launch. | Hanging continúa enviando solicitudes; no escribe transform ni velocidad directamente. |
| Captura | Una candidata válida podía derivar en autoenganche dentro del laboratorio. | Se sustituyó por el evento de primer contacto entre C y S. Candidata sin contacto ya no captura. |
| Candidata | Describía pared, borde y P. | Conserva además `wall_point` y `support_id`; P bloqueada invalida la candidata. |
| Input/cámara | Había flanco de crouch y acceso planar de cámara. | Se añadió crouch mantenido y dirección 3D completa de cámara, únicamente para las reglas nuevas. |
| Daño de caída | El body acumulaba el tramo aéreo hasta tocar el piso. | Un snap aceptado corta ese tramo para que la caída previa al agarre no reaparezca al aterrizar después. |
| Depuración/pruebas | Había overlay y smoke de Hanging para el ciclo previo. | Muestran y prueban cilindro/esfera, su bloqueo, ascenso, reset de caída y salto por cámara. |

Esta tabla también marca una frontera importante: no se atribuyen a este corte
la creación de H0, del body, de providers, del laboratorio ni del ciclo local
original. Se reutilizaron y se conservaron.

## Resolución de cada punto abierto del borrador

| Punto que quedaba abierto | Resolución actual | Estado |
| --- | --- | --- |
| ¿La captura sustituye al autoenganche? | Sí, en esta escena V3: sólo el flanco `last_contact_event` de cilindro/esfera permite entrar. | Implementado. |
| ¿En qué momento existe C? | Sólo mientras el evaluator publica una candidata válida; si la pierde, se oculta y borra historial. | Implementado. |
| ¿Dónde se apoya C? | Usa `wall_point` real, alinea su altura con `edge_point`, sigue sólo la tangente del player y se desplaza hacia afuera por la normal. | Implementado. |
| ¿Cómo se evita atravesarlo entre ticks? | Contacto actual más mínimo de distancia sobre el barrido relativo de 24 iteraciones. | Implementado; falta fixture específica de alta velocidad. |
| ¿Puede entrar ascendiendo o cayendo? | No hay filtro de `velocity.y`. | Implementado y cubierto por smoke. |
| ¿Qué significa Ctrl/crouch? | `crouch_pressed` o `body.is_crouched` bloquea la entrada; la candidata y cilindro/esfera siguen observables. | Implementado. |
| ¿Qué ocurre si Ctrl se libera dentro del mismo solapamiento? | No hay entrada tardía: el evento sólo ocurre al primer contacto; debe salir y volver a entrar en C. | Implementado. |
| ¿Cómo sale con Espacio? | Dirección 3D de cámara; si el plano apunta al muro retenido con dot ≥ 0.5, salto vertical. | Implementado con valor provisional. |
| ¿Debe haber Marker3D para soporte no identificable? | No se añadió. | Pendiente de diseño. |
| ¿El snap debe ocurrir en el mismo tick? | No: la orden del core se consume en el body el tick siguiente. | Decisión explícita del laboratorio. |
| ¿Qué flag nombra el bloqueo/switchboard? | Ninguno: no hay switchboard ni flag provisional local. | Pendiente de infraestructura V3. |

## Inventario de API, datos y constantes nuevos o modificados

### Candidata y evaluator

`V3HangingCandidate` conserva los hechos `is_valid`, `rejection_reasons`,
`wall_hit_count`, `wall_normal`, `edge_point`, altura relativa, alineación,
clase de intención y P. Este corte añade:

```text
wall_point : Vector3    punto del impacto en la cara real de la pared
support_id : int        instance_id del collider de pared elegido, o 0
```

El evaluator mantiene estos ajustes existentes de la geometría y P:

```text
min_edge_height = 0.5 m          max_edge_height = 1.5 m
max_surface_tilt_degrees = 30    lateral_coherence_tolerance = 0.35 m
intent_alignment_threshold = 0.2
hang_body_offset_from_wall = 0.68 m
hang_body_offset_from_edge_y = -1.5 m
```

Además de los rechazos que ya publicaba, el recorrido relevante ahora puede
mostrar exactamente: `referencias_incompletas`, `en_piso`,
`sin_pared_y_borde_coherentes`, `intencion_contradictoria` y
`pose_de_agarre_bloqueada`. `en_piso` se añade antes de la búsqueda; el
evaluator aún inspecciona geometría para que los motivos acumulados sigan
siendo útiles en debug. `is_valid` sólo se calcula al final desde la lista de
rechazos.

`_support_id_for()` toma el `instance_id` del collider de la muestra frontal;
no almacena un `NodePath`, `RID`, transform ni vínculo de seguimiento. Por
ello identifica correctamente el soporte estático actual del laboratorio,
pero no resuelve plataformas móviles, colliders recreados ni hand-off entre
soportes.

### `V3HangingCaptureProbe`

Sus exports y defaults completos son:

```text
candidate_evaluator : V3HangingCandidateEvaluator
physics_body        : V3PhysicsBody
capture_disk_radius = 0.18 m        rango de inspector: 0.05–1.50
capture_disk_thickness = 0.25 m     rango de inspector: 0.02–1.00
player_sensor_local_offset = (0, 1.30, 0)
player_sensor_radius = 0.10 m       rango de inspector: 0.02–0.50
process_physics_priority = 155
```

Y su telemetría completa es:

```text
last_zone_active                 candidata válida durante este tick
last_disk_center                 centro mundial de C
last_sensor_center               centro mundial de S
last_sensor_distance_to_disk     distancia de S al sólido C, INF si no hay zona
last_overlap_depth               radio de S menos esa distancia
last_sensor_touches_disk         contacto de la muestra actual
last_swept_contact               contacto detectado entre muestras
last_contact_event               flanco de primer contacto
last_contact_kind                sin_contacto / contacto_actual /
                                 contacto_sostenido / barrido_entre_ticks
```

La geometría exacta de `_make_disk_center()` es:

```text
wall_face = wall_point, con Y reemplazada por edge_point.Y
wall_face += tangente_de_pared * proyección_tangencial_del_body
centro_C = wall_face + normal_horizontal * radio - UP * (espesor / 2)
```

Así la tapa superior de C queda a la altura de borde y su punto más cercano al
muro toca la cara exterior; no se desplaza hacia dentro. `_distance_to_vertical_disk()`
usa exceso radial y vertical contra el cilindro finito. `_swept_sensor_touches_disk()`
minimiza esa distancia en el segmento relativo mediante 24 iteraciones de
búsqueda ternaria. No crea `Area3D`, `CollisionShape3D`, señal de física ni
otro collider. Los dos `MeshInstance3D` que crea al arrancar son visuales
translúcidos sin profundidad (C rosa, S azul) y sólo se ven cuando hay zona.

El histórico interno contiene muestra anterior de ambos centros, `support_id`
anterior y si hubo contacto. Se borra al no haber candidata válida o al perder
referencias. Si el soporte cambia, sólo se inhibe el sweep contra la muestra
anterior y luego se almacena la nueva; no se fabrica un flanco de contacto por
ese cambio. El evento se calcula antes de actualizar el histórico, por lo que
`last_contact_event` dura un tick y un contacto sostenido no vuelve a ser
flanco.

### Input, cámara, core y body

`V3InputSource` lee ahora `Input.is_action_pressed("crouch")` en
`crouch_pressed`, además de conservar `crouch_just_pressed`. El core usa ambos
de forma distinta: el mantenido bloquea **entrada**; el flanco de crouch libera
**durante HANGING**. Esto mantiene el toggle físico existente de H0 sin hacer
que soltar Ctrl dentro de C sea una captura nueva.

`V3CameraRig.get_view_forward()` devuelve el eje `-Z` mundial de `camera`
(normalizado), incluido pitch; si no hay cámara devuelve `Vector3.FORWARD`.
No reemplaza los helpers planares que usan los providers/evaluator.

Los parámetros relevantes de `V3HangingCore` son:

```text
back_exit_threshold = 0.2                    existente, conservado
lateral_speed = 2.0 m/s                      existente, conservado
lateral_support_probe_height = 1.0 m         existente, conservado
lateral_support_probe_distance = 1.0 m       existente, conservado
lateral_support_normal_threshold = 0.8       existente, conservado
jump_exit_speed = 5.0 m/s                    usado para la salida nueva
wall_facing_jump_threshold = 0.5             rango inspector: 0.0–1.0
```

Las razones observables de entrada son `sin_entrada`,
`recaptura_bloqueada`, `sin_candidata_valida`,
`pose_de_agarre_bloqueada`, `entrada_bloqueada_por_crouch`,
`espera_contacto_sondas`, `contacto_sondas_capturado` y
`snap_de_entrada_rechazado`. Las salidas que registra este camino son
`salida_voluntaria`, `salida_con_salto_por_camara` y
`snap_de_retencion_rechazado`.

Al capturar, el core guarda `held_pose`, borde y normal de pared, mide
`last_entry_snap_distance`, suspende H0 y pide `submit_pose_snap`. Al saltar,
guarda `last_jump_exit_velocity`, reactiva H0 y pide `submit_launch`. Al soltar
voluntariamente activa `recapture_locked`; tocar el piso o pulsar salto vuelve
a limpiarlo. El lock es del ciclo existente y evita que soltar con atrás/Ctrl
reenganche en el mismo volumen.

El único cambio de `V3PhysicsBody` se ubica en la aceptación de
`submit_pose_snap`: junto con la velocidad cero, fija
`fall_distance_in_current_airtime = 0.0`. No modifica las reglas de daño, no
lanza por sí mismo ni borra `last_landing_fall_distance` de una caída que ya
hubiera terminado antes.

## Integración de escena y compatibilidad de carga

La escena crea `HangingCaptureProbe` como `Node3D` y le enlaza
`HangingCandidateEvaluator` y `H0Lab/PlayerH0Lab/Body`. `HangingCore` recibe
además `CameraRig` y `HangingCaptureProbe`; el overlay también recibe la sonda.
Los tres enlaces están declarados como `NodePath` en
`v3_hanging_detection_lab.tscn`, no son búsquedas por grupo, singleton ni
ruta calculada en runtime.

Los exports `capture_probe` de `V3HangingCore` y de
`V3HangingDebugOverlay` se tipan intencionalmente como `Node`, aunque la
instancia concreta es `V3HangingCaptureProbe`. Godot puede cargar la escena
antes de que el editor haya reindexado el `class_name` recién creado; usar el
tipo amplio evita romper esa carga. El core/overlay solamente leen la API
pública de la sonda. Es una compatibilidad de loader, no una nueva capa de
abstracción ni permiso para reemplazar la sonda por un objeto arbitrario.

El overlay agrega una línea con zona, contacto actual, evento, clase de
contacto, distancia y solapamiento cilindro/esfera, y la línea del core incluye la
distancia de snap de entrada. Es diagnóstico pasivo: no solicita movimiento,
no cambia flags y no interviene en el orden físico.

## Prueba: casos, calibración y evidencia reproducible

El smoke usa la escena real, no dobles de provider/core/body. Sus posiciones
de fixture con la `PracticeLedge` son deliberadamente de test: `z = 1.00` deja
la candidata aérea fuera de C y `z = 0.70` provoca contacto. No son valores de
calibración de gameplay ni se exportan al runtime.

El caso de daño fija `fall_distance_in_current_airtime = 4.0` antes de entrar
para simular una caída que ya venía acumulada; luego confirma que el snap la
corta. El caso de ascenso entra con `velocity = (0, 5, 0)`, por eso verifica
de forma directa que no sobrevive ningún tope de velocidad vertical. El caso
de nueva captura sale de C, permite que se limpie el lock en piso, y vuelve a
entrar: no confunde solapamiento sostenido con flanco nuevo.

También se corrigió el harness para esperar
`get_tree().physics_frame` en vez de un `physics_frame` sin resolver desde el
nodo de prueba. Es un ajuste de ejecución de la prueba, no un cambio del
contrato de Hanging.

La verificación ejecutada fue:

```powershell
& 'C:\Godot\4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path . --scene res://scenes/test/v3_hanging_detection_smoke_test.tscn --log-file tmp/v3-hanging-run.log
```

Con Godot 4.6.3 produjo el mensaje de éxito transcrito arriba. El log fue un
artefacto temporal de verificación y se eliminó después; no forma parte del
proyecto. Si se vuelve a ejecutar, debe crearse de nuevo o usarse otro destino
temporal.

## Límites que siguen siendo reales

Además de lo enumerado en “Qué no se hizo deliberadamente”, estos límites son
importantes para no sobreinterpretar el experimento:

- La ocupación P se valida al formar la candidata; durante la retención se
  conserva esa pose y se comprueba el lateral para shimmy, pero no hay
  revalidación integral de P, borde o soporte cada tick.
- C sigue la coordenada tangencial del body sólo sobre una pared estática. No
  actualiza por transformación de plataforma, rotación de soporte ni cambio de
  identidad de collider durante un agarre.
- La entrada de cilindro/esfera usa candidata ya válida, incluido el rango temporal de
  altura e intención. Por eso cilindro/esfera no es un detector geométrico independiente:
  decide el instante, no relaja los prerrequisitos de V3.
- El barrido está razonado sobre el cilindro convexo y expuesto en telemetría,
  pero aún falta la prueba que demuestre un cruce rápido completo con una
  fixture controlada.
- El salto por cámara es una regla de laboratorio: el umbral 0.5 y 5 m/s son
  exports provisionales que requieren playtest; no expresan una capacidad del
  switchboard ni una política final de parkour.
- No se tocaron los cambios ajenos que ya estaban presentes en el árbol de
  trabajo (legacy, assets, otros documentos y laboratorios). Este archivo sólo
  documenta el corte V3 de Hanging enumerado arriba.
