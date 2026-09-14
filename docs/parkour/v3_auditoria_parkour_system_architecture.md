# Auditoría V3 de `PARKOUR_SYSTEM_ARCHITECTURE.md`

## Propósito y alcance

Esta auditoría compara el documento heredado `PARKOUR_SYSTEM_ARCHITECTURE.md` con las decisiones explícitas de `v3_autoridad_movimiento_propuesta.md`.

No reescribe el documento heredado, no define implementación ni completa preguntas abiertas. Su función es separar qué se puede conservar de qué debe transmutarse antes de que el documento heredado pueda convivir con V3.

## Criterio de lectura

- **Se conserva:** compatible con V3 como principio.
- **Se adapta:** la intención sirve, pero la responsabilidad o el flujo deben cambiar.
- **Se descarta:** contradice una decisión explícita de V3.
- **Se estaciona:** puede ser valioso, pero V3 no lo decidió todavía o pertenece al diseño futuro de un core concreto.

`v3_autoridad_movimiento_propuesta.md` tiene prioridad. Este informe no convierte los contenidos de V1/V2 ni las recomendaciones del documento heredado en requisitos de V3.

## Resultado ejecutivo

El documento heredado contiene tres aportes rescatables: prioridad de la simulación sobre lo visual, exigencia de observabilidad/debug y preocupación por que el movimiento real respete colisiones y cambios del entorno.

Su conflicto principal con V3 es estructural: organiza parkour como una cadena central de módulos que detecta, genera, valida, selecciona y ejecuta maniobras completas. V3 organiza parkour como cores autónomos que interpretan sólo sus datos necesarios, deciden su propia semántica y expresan intención por tick a una capa física común. Por ello el documento no puede adoptarse tal cual; debe transformarse sección por sección.

## Auditoría por sección

| Sección heredada | Estado | Lectura frente a V3 |
|---|---|---|
| Propósito y principio de diseño | **Se adapta** | Conserva que la simulación manda y que el sistema debe ser depurable. Debe abandonar la idea de una única planificación central de maniobras físicas completas. En V3 los cores producen y ajustan intención por tick; no hay una trayectoria autónoma central que se planifica y ejecuta de punta a punta. |
| Módulos y responsabilidades | **Se adapta / descarta partes** | `LocomotionController` pasa a ser `H0`, no un módulo separado de la arquitectura. Providers reemplazan a un `ParkourSensor` con significado de parkour. Un `ParkourActionGenerator`, `TrajectoryValidator` y `ParkourExecutor` universales contradicen que cada core conserva su semántica. La capa física común, presentación y debug sí tienen lugar, pero con responsabilidades reescritas. |
| Snapshot del entorno | **Se adapta** | Es útil que los hechos leídos durante un tick sean coherentes y observables. No se adopta un `ParkourContext` central fijo ni su lista de campos: los providers exponen datos neutrales y cada core consume sólo los que necesita. Formato, frecuencia y representación siguen abiertos. |
| Superficies y puntos de interés | **Se conserva como principio; técnica estacionada** | La lectura neutral de geometría encaja con los providers tontos de V3. Raycasts, shapecasts, combinación exacta, materiales, plataformas y el formato de los resultados son decisiones técnicas o de core aún abiertas. |
| Acción candidata | **Se adapta** | V3 conserva que detectar una posibilidad no mueve al player. Pero una candidata no tiene por qué contener una trayectoria, fases, prioridad o transformaciones universales. Los cores contextuales que superaron prerrequisitos calculan certeza y el árbitro compara esa distribución; otros cores no participan de ese circuito. |
| Validación física de extremo a extremo | **Se adapta** | Se conserva la exigencia de no atravesar geometría y de comprobar soporte/colisión reales. Se descarta imponer un validador universal que aprueba por adelantado toda trayectoria. Cada core valida su significado y la capa física aplica el movimiento real por tick; las condiciones se vuelven a leer durante la ejecución metaestable. |
| Selección y transiciones | **Se adapta / descarta partes** | El árbitro de V3 compara certezas de candidatos contextuales ya habilitados; no interpreta geometría ni ejecuta. La regla vigente es prerrequisitos + distribución cerrada a 100 + umbral provisional 90. La jerarquía `Locomotion → Parkour → estados` no es vocabulario V3: existen cores con `H0` como control por defecto. La transición directa `LedgeHang → Mantle` contradice la ruta obligatoria `core → H0 → posible core`. |
| Ejecución por fases | **Se adapta** | Un core puede tener fases, tiempos o recorrido previsto propios. No se adopta la secuencia universal `Approach → Commit → Traverse → Exit → Recover`, ni un ejecutor que enlace una acción posterior. Si un core termina, devuelve gobierno a H0; la capa física no ejecuta una maniobra autónoma durante varios ticks. |
| Trayectorias, velocidad y plataformas móviles | **Se estaciona / adapta** | Un core puede usar una trayectoria o plan interno, pero V3 no permite que otra capa la ejecute ciegamente. La forma de expresar intención física, conservar momentum, tratar plataformas móviles y validar anclas no está decidida. Sólo queda vigente que los hechos del mundo cambian y que un core debe reaccionar a ellos. |
| Animación, cámara y presentación | **Se conserva como límite; se adapta en detalle** | Se conserva que animación, cámara, sonido y VFX no autorizan física. V3 además fija que cámara e input son fuentes compartidas, no sistemas por core. IK, root warping, límites de cámara y eventos sincronizados son posibilidades técnicas/visuales, no decisiones de V3. |
| Tolerancia controlada | **Se estaciona** | Buffers, coyote time, snaps y grace windows podrían existir dentro de cores concretos, pero V3 no los adopta aún como regla general ni define su formato. No deben convertirse en una capa universal por herencia. |
| Red, determinismo y guardado | **Se estaciona** | V3 no tomó decisiones de multijugador, serialización, replay ni determinismo. La disciplina de reproducir bugs es compatible con el valor de debug, pero las reglas de red no se incorporan ahora. |
| Datos y autoría de diseño | **Se estaciona** | Resources, tags de nivel y perfiles editables pueden resultar útiles, pero son decisiones de autoría e implementación futuras. Tampoco se puede presuponer que toda mecánica sea una `ParkourActionDefinition` porque V3 trabaja con cores, no con maniobras homogéneas. |
| Depuración, telemetría y pruebas | **Se conserva y se adapta** | Es plenamente compatible que exista un área de pruebas de parkour con casos límite y que el debug sea de primera clase. Debe ampliarse con hechos crudos de providers, consumidor, peso, signo, contribución a certeza, prerrequisitos aprobados/rechazados, distribución final y razón de traspaso o no traspaso. Trayectorias/fases sólo se muestran cuando pertenezcan al core evaluado. |
| Implementación en Godot | **Se estaciona** | `CharacterBody3D`, `PhysicsDirectSpaceState3D`, `ShapeCast3D`, `Resource` y nombres concretos de controladores son decisiones técnicas. Algunas podrán ser útiles en un prototipo posterior, pero este fundamento no las autoriza ni las rechaza todavía. |
| Regla final del documento heredado | **Se adapta** | Debe pasar de “detectar → proponer maniobra → validar recorrido completo → comprometer → ejecutar” a “providers exponen hechos → core habilitado interpreta sus datos → árbitro compara certeza contextual cuando aplica → H0 cede gobierno → core activo expresa intención por tick → capa física informa resultado real → core continúa, ajusta o vuelve a H0”. |

## Conflictos fundamentales que no se deben conservar

### 1. Cadena central de maniobras

El documento heredado concentra el comportamiento en un sensor, generador, validador, árbitro y ejecutor universales. En V3, esa concentración volvería a crear un componente que termina sabiendo cómo funciona Hanging, Ladder, Mantle y los demás cores.

La adaptación correcta no es renombrar esos módulos: es mover la interpretación y la validación semántica a cada core, dejando comunes sólo los hechos neutrales, la capa física y el debug.

### 2. Maniobra preplanificada de punta a punta

El heredado valida y ejecuta una trayectoria completa por fases. V3 acepta que un core tenga un plan interno, pero el core debe expresar intención en cada tick y releer la realidad física para el siguiente. No se debe heredar una trayectoria central que continúe por sí sola pese a cambios del mundo.

### 3. Máquina de estados y transiciones directas

La jerarquía `Locomotion/Parkour` y los saltos directos entre estados no representan el modelo V3. V3 usa H0 como frontera obligatoria: ningún core entrega gobierno directamente a otro.

### 4. Acción candidata universal

En V3 una candidata contextual es el resultado de un core que aprobó sus prerrequisitos y puede computar certeza. No todos los cores son contextuales ni todos necesitan trayectoria, prioridad, ancla o fases. Un formato universal de `ParkourAction` impondría propiedades que no pertenecen a todos.

## Material heredable valioso

- La simulación manda; lo visual sólo reacciona.
- Las lecturas de geometría no deben decidir por sí mismas qué core se activa.
- La colisión y el soporte reales importan tanto al entrar como durante la acción.
- Las decisiones deben ser observables, reproducibles y explicables en debug.
- Hace falta un área de pruebas con geometría límite, cambios de entorno y situaciones de fallo.

## Estacionado: no transformar todavía en requisito de V3

- Forma concreta de las solicitudes físicas y de sus resultados.
- Raycasts, shapecasts, snapshots y APIs de Godot.
- Trayectorias, perfiles de velocidad, momentum y plataformas móviles.
- Fases internas de cada core.
- Buffers, tolerancias, coyote time, snaps y recuperación.
- Resources de autoría, tags del nivel, guardado, red y determinismo.
- Prerrequisitos específicos de Hanging, Ladder, Mantle u otro core.

## Secuencia segura para adaptar el documento heredado

1. Mantener esta auditoría como mapa; no editar aún `PARKOUR_SYSTEM_ARCHITECTURE.md` de punta a punta.
2. Reescribir primero su propósito, vocabulario y responsabilidades para que hablen de cores, providers, capa física, H0 y debug.
3. Tratar selección/gatillo contextual como una sección V3 separada, sin importar la máquina de estados heredada.
4. Dejar las secciones estacionadas como referencias técnicas, no como contrato arquitectónico.
5. Sólo después diseñar un core concreto —empezando por H0— y decidir las partes técnicas que ese prototipo realmente necesite.
