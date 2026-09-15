# Sistema de parkour V3: fundamento arquitectónico

Este documento transfiere el valor recuperable de la arquitectura heredada al modelo V3. Su autoridad conceptual complementaria es `docs/parkour/v3_autoridad_movimiento_propuesta.md`; si existe conflicto, prevalecen las decisiones explícitas de V3.

No define APIs, clases, campos, operaciones concretas de Godot, formatos de solicitud física, red, guardado ni fórmulas de certeza. Esas partes siguen estacionadas hasta que un prototipo o el diseño de un core las requiera.

El objetivo es permitir nuevos cores sin concentrar su lógica en un controlador central, sin que ningún core mueva el cuerpo real por su cuenta, sin atravesar geometría y sin dejar al player en condiciones físicas inválidas.

## Principio de diseño

El parkour no es una colección de animaciones ni una serie de raycasts independientes. Es un conjunto de **cores** que interpretan hechos físicos actuales y expresan intención de movimiento de manera reactiva.

Cada core conserva la semántica exclusiva de su mecánica. La capa física común conserva la autoridad sobre el cuerpo/collider real. La simulación siempre es la autoridad: animación, cámara, sonido y VFX reaccionan al resultado físico; no deciden qué core es válido ni fabrican movimiento.

```text
inputs y mundo físico actual
  → providers exponen hechos neutrales
  → cada core consume sólo lo que necesita
  → el core aprueba o rechaza sus propios prerrequisitos
  → los cores contextuales habilitados calculan certeza
  → el árbitro contextual compara la distribución resultante
  → H0 cede gobierno sólo si corresponde
  → el core activo expresa intención para este tick
  → la capa física aplica el resultado real
  → providers exponen la nueva realidad para el tick siguiente
```

## Módulos y responsabilidades

| Unidad | Responsabilidad | No debe hacer |
| --- | --- | --- |
| `H0` | Core mínimo global: locomoción normal y capacidades base. Gobierna el cuerpo cuando ningún otro core ejecuta movimiento físico. | Ejecutar simultáneamente con otro core. |
| Cores contextuales | Interpretar su propia mecánica, aprobar prerrequisitos y, cuando aplica, calcular certeza a partir de sus datos. | Mover directamente el cuerpo/collider o decidir la semántica de otros cores. |
| Cores no contextuales | Activarse desde sus propias directivas y condiciones pertinentes, sin contaminar la competencia espacial. | Competir artificialmente en la distribución contextual si no usan ese contexto. |
| Providers | Exponer hechos físicos y de input neutrales, incluidos soportes actuales. | Conocer qué core puede activarse o tomar gobierno. |
| Árbitro contextual | Comparar las certezas de cores contextuales ya habilitados y expresar el candidato preferido. | Interpretar geometría, validar la semántica de un core, mover el player o decidir cores no contextuales. |
| Capa física común | Aplicar la intención del único core que gobierna en el tick y publicar el resultado físico real. | Conocer cómo funciona Hanging, Ladder, Mantle u otro core. |
| Presentación | Reaccionar a hechos confirmados mediante animación, cámara, sonido y VFX. | Autorizar física o crear posibilidades inexistentes. |
| Debug y telemetría | Mostrar hechos, consumidores, prerrequisitos, certeza, gobierno y resultado físico. | Alterar la lógica de gameplay. |

No hay una jerarquía de “módulo que contiene un core”. La separación es una regla de responsabilidad: cada core es dueño de su mecánica; los providers, la capa física, la presentación y el debug son infraestructura compartida con límites explícitos.

Una submecánica es una capacidad interna de su core. Puede desactivarse para gameplay sin que deba dejar de evaluarse para diagnóstico. No se presupone una división interna universal entre partes “indispensables” y “adicionales”: esa organización pertenece al diseño de cada core.

## Hechos del entorno y lectura compartida

Los providers exponen hechos actuales de input, locomoción, contactos, orientación, superficies y soportes. Cada core consume sólo el conjunto que necesita: que un dato sea público no implica que se difunda ni que sea relevante para todos.

La forma concreta de agrupar esos hechos —snapshot inmutable, consultas bajo demanda u otra representación— sigue abierta. Lo que sí queda fijado es que una lectura no se convierte en verdad permanente: describe el mundo actual y debe actualizarse o revalidarse cuando el core la vuelva a necesitar.

## Superficies y puntos de interés

Los providers geométricos no conocen conceptos como “vault”, “mantle” o “hanging”. Pueden describir hechos neutrales del siguiente tipo; esta lista es orientativa y no constituye una taxonomía obligatoria de V3:

- plano impactado, normal y material;
- borde superior e inferior;
- altura relativa al cuerpo;
- longitud y continuidad del borde;
- espacio libre frente a la superficie y detrás de ella;
- superficie de aterrizaje, pendiente y estabilidad;
- velocidad propia de la superficie si pertenece a un objeto dinámico.

Una coordenada de borde, escalera, plataforma, aterrizaje o piso es una referencia de soporte metaestable: no representa una verdad mundial eterna. Si el objeto se traslada, rota, cambia o desaparece, los providers deben exponer el estado actual para que el core ajuste su intención o vuelva a H0 si perdió el soporte.

Raycasts, shapecasts, barridos, el collider consultado y la API concreta son decisiones técnicas posteriores. El principio ya adoptado es que los datos expuestos sean neutrales y que el movimiento físico real se compruebe durante la ejecución, no sólo al detectar una posibilidad.

## Candidatos contextuales

Detectar una posibilidad nunca mueve al player. Un core contextual sólo participa como candidato después de aprobar sus prerrequisitos propios; esos prerrequisitos pueden incluir los hechos de mundo, postura, caída, movimiento, cámara o directivas que ese core necesite.

Los candidatos contextuales no producen porcentajes independientes. Para una misma lectura, sus certezas forman una distribución cerrada de `100`. El árbitro compara esa distribución sin reinterpretar la geometría de los cores.

```text
prerrequisitos del core aprobados
        ↓
core contextual calcula su certeza
        ↓
árbitro compara la distribución total 100
        ↓
si el preferido alcanza el umbral provisional 90, puede iniciar desde H0
```

No existe una estructura universal de “acción candidata” con trayectoria, fases, prioridad o ancla obligatorias. Un core puede conservar la información interna que su mecánica necesite, pero no puede entregar una trayectoria autónoma para que otra capa la ejecute durante varios ticks.

Los cores sin competencia espacial —por ejemplo, Parry o doble salto cuando no consumen sondas de mundo— usan sus propias condiciones de entrada y no restan certeza a los candidatos contextuales.

## Validación y realidad física

Cada core decide qué condiciones significan que su mecánica puede comenzar o continuar. Por ejemplo, sólo ese core sabe qué constituye soporte, alcance, postura o salida válida para su comportamiento. Un peso o una certeza nunca vuelven posible un core que no aprobó esas condiciones.

La capa física común es la única que aplica la intención de movimiento sobre el cuerpo/collider real. El core no escribe transformaciones ni resuelve colisiones por su cuenta. En cada tick, la capa física intenta aplicar la intención del core que gobierna y publica el resultado real; el core lee ese resultado para continuar, ajustar o terminar.

No se adopta un validador central que aprueba por adelantado el recorrido completo de toda maniobra. Un core puede anticipar y comprobar lo que su mecánica requiera, pero la realidad se vuelve a comprobar mientras la acción está activa. Soportes, plataformas y geometría siguen siendo metaestables.

## Selección y gobierno del movimiento

El árbitro no es un controlador universal de parkour. Sólo compara las certezas de cores contextuales que ya aprobaron sus prerrequisitos. No consulta geometría, no decide qué significa Hanging/Ladder/Mantle, no mueve al player y no participa en la entrada de cores no contextuales.

El gatillo contextual es automático y deliberado: el core contextual preferido puede tomar gobierno sólo si alcanza una certeza de `90` o más. `90` es un valor provisional explícito para diseñar y prototipar; no es todavía una calibración final. Si ningún core reúne prerrequisitos y umbral, no hay traspaso y H0 continúa.

Agacharse es un estado persistente de H0: una pulsación de su control alterna entre agachado y parado. No debe confundirse con mantener `Ctrl`.

Mantener `Ctrl` es una directiva compartida de supresión para los cores que la consumen. Mientras esté mantenida, esos cores quedan excluidos antes de la distribución de certeza; no pierden puntos artificialmente. Un core que no consume esa directiva no se ve afectado.

H0 es la frontera obligatoria de toda ejecución física:

```text
H0 → core activo → H0 → posible core siguiente
```

No existe una máquina de estados jerárquica global ni transferencias directas core → core. Sólo un core gobierna el movimiento físico a la vez. La duración técnica del paso por H0 y la representación de ese cambio de gobierno siguen abiertas.

## Bloqueo de voluntad y estados fuera de cores

Cuando sea necesario impedir que la voluntad del jugador produzca movimiento o activaciones, se desactiva la captura de directivas de input antes de que lleguen a H0 o a otros cores. No es una tarea del árbitro ni una lista de excepciones dentro de cada core.

La muerte del player no es una decisión del selector de cores: el player pasa a ragdoll y queda fuera de este sistema. Cinemáticas u otros estados no implementados no definen requisitos adicionales hasta que existan en el alcance del proyecto.

## Ejecución reactiva de cada core

Un core puede conservar internamente fases, tiempos o un recorrido previsto si su mecánica lo necesita. No existe, sin embargo, una secuencia universal ni un ejecutor que recorra una trayectoria por su cuenta. El core activo vuelve a expresar intención en cada tick y ajusta su siguiente decisión a partir de los hechos físicos actuales.

Si una condición de sostén cambia —por ejemplo, un borde desaparece o una plataforma se mueve—, el core resuelve su propia continuidad o salida dentro de su semántica. Cuando deja de gobernar el movimiento, lo devuelve a H0; no enlaza directamente otro core ni teletransporta el cuerpo para forzar una presentación visual.

## Señales externas al parkour

Las señales externas pueden tener dos efectos distintos sobre un core activo:

- **Interrupción obligatoria:** el core debe terminar y devolver el gobierno a H0. Puede limpiar su estado interno, pero no vetar la interrupción.
- **Modificador temporal:** el core sigue activo; la condición se publica como un hecho actual que los cores interesados pueden consumir mientras exista.

La clasificación corresponde al sistema externo que origina la señal, no al árbitro. Efectos concretos, prioridades, formato y técnica de implementación siguen abiertos.

## Trayectorias, velocidad y plataformas móviles

Esta sección conserva problemas reales de gameplay, pero no fija todavía su solución técnica.

Un core puede mantener internamente una trayectoria, una velocidad prevista o fases propias si le sirven para interpretar el tick siguiente. No se adopta una curva, spline, perfil temporal ni fórmula de momentum universal; tampoco se entrega ese plan a otra capa para que lo ejecute de forma autónoma.

Las plataformas móviles son parte prevista del gameplay. Todo soporte referido por un core es metaestable: borde, escalera, piso, punto de aterrizaje o plataforma deben leerse según su estado actual. Si se mueven, rotan, cambian o desaparecen, el core ajusta su intención o termina hacia H0 si ya no puede sostener su mecánica.

Anclas locales, transforms relativos, velocidades de plataforma, conservación de momentum y técnicas de revalidación son decisiones técnicas abiertas. No se infieren aquí desde la arquitectura heredada.

## Animación, cámara y presentación

La presentación consume hechos confirmados por la simulación. Puede expresar el core activo, su fase interna si existe, dirección, velocidad, contactos y eventos confirmados, pero nunca convierte una mecánica inválida en válida ni mueve el cuerpo real.

La cámara y las directivas de input son infraestructura compartida del player. No existen una cámara ni controles distintos por core; un core puede leer las mismas fuentes y darles su propia interpretación. La cámara es una referencia continua cuya distancia puede variar entre primera y tercera persona sin alterar la dirección de movimiento. Ese cambio visual no inicia o termina cores, ni puede mover, rotar o reubicar físicamente al player por sí mismo: por ejemplo, cambiar de perspectiva durante Hanging no interrumpe Hanging. Los ajustes visuales de cámara, IK, root warping y eventos de animación se decidirán más adelante y no pueden alterar la realidad física.

## Tolerancias y asistencias

Buffers de input, coyote time, snaps, tolerancias de ángulo o distancia y otras asistencias no son todavía una capa global de V3. Podrán ser reglas de cores concretos cuando se diseñen sus mecánicas.

Si un core incorpora una asistencia, debe ser observable en debug y no puede reemplazar la validación física ni forzar al body a una condición inexistente. Sus límites, datos y forma de implementación siguen abiertos.

## Red, determinismo y guardado

V3 no toma todavía decisiones de multijugador, serialización, replay, determinismo de red ni guardado. No son requisitos de este fundamento mientras el alcance de proyecto no los demande.

La necesidad ya adoptada es más acotada: el debug debe permitir entender y reproducir decisiones mediante hechos observados, consumidores, certeza, gobierno y resultados físicos. Si el proyecto luego exige red o replay, se diseñará ese contrato transversal sin usar este texto heredado como especificación automática.

## Datos y autoría de diseño

La forma de autorar datos de cores y de nivel queda abierta. Resources, perfiles editables, tags, materiales o componentes pueden resultar útiles, pero no están adoptados por este fundamento.

Cuando existan, los datos del mundo deben evitar adjudicar semántica de un core sin que haya una decisión explícita. Un material o condición física puede ser un hecho neutral para los providers; etiquetas como `vault_only` ya imponen una mecánica concreta y no se heredan automáticamente. La autoría específica se resolverá al diseñar el core y el flujo técnico que realmente la necesiten.

## Depuración, telemetría y pruebas

El debug es infraestructura de primera clase y de sólo lectura. Debe poder mostrar, según corresponda:

- hechos crudos expuestos por providers, su origen y momento de actualización;
- receptor/core consumidor de cada dato;
- prerrequisitos aprobados o rechazados y su motivo;
- peso, signo y contribución de datos al valor `X` de cada core contextual, cuando ese modelo de cálculo aplique;
- distribución final, core preferido, umbral vigente y razón de traspaso o continuidad de H0;
- core que gobierna el movimiento, intención emitida y resultado físico real;
- soporte actual y cambios de una plataforma u otra geometría metaestable;
- fases o recorrido interno de un core sólo si ese core los usa.

Debe existir un área de pruebas propia de parkour, no una reutilización accidental de otras escenas. Incluirá posibilidades normales y límite: alturas, pendientes, techos bajos, esquinas, escalones, huecos, colisiones dinámicas, plataformas móviles y cambios bruscos de input o entorno. La técnica para registrar/reproducir casos queda abierta, pero el debug debe permitir diagnosticar cómo el sistema interpreta el mundo 3D.

## Implementación en Godot

Esta arquitectura no decide todavía cómo se implementa V3 en Godot. `CharacterBody3D`, `PhysicsDirectSpaceState3D`, RayCast/ShapeCast, Resources, API de colisión y contrato de solicitudes físicas serán materia de prototipos técnicos posteriores.

La única frontera ya fijada es conceptual: los cores deciden su mecánica e intención; una capa física común aplica el movimiento real y publica sus resultados.

El primer prototipo técnico existe de forma aislada en `scenes/test/v3_h0_lab.tscn`. Valida H0 y una capa física común con `CharacterBody3D`, pero no convierte esa integración ni sus valores actuales en contrato general de V3. Su funcionamiento actual está documentado en `docs/parkour/v3_h0_laboratorio_mapa_tecnico.md`.

La regla que gobierna todo el sistema es:

> Exponer hechos neutrales, habilitar cores por sus propios prerrequisitos, comparar certeza contextual cuando corresponda, transferir el gobierno desde H0, aplicar intención física por tick y volver a H0 cuando el core ya no gobierna.
