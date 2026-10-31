# V3 — Comparación de cores para la frontera física reutilizable

## Propósito

Esta comparación extrae únicamente lo que ya comparten `H0`, Hanging,
Ladder y Mantle según los documentos vigentes de V3. No elige una API, no
crea un árbitro y no adopta el *lease* de V2 como solución técnica.

La pregunta que responde es: **¿qué debe ser infraestructura reutilizable y
qué debe seguir siendo decisión de cada core?**

## Fuentes y límite de autoridad

- `v3_autoridad_movimiento_propuesta.md` define la frontera conceptual:
  un core activo expresa una intención por tick, la capa física común mueve
  el cuerpo real y sólo un core gobierna a la vez.
- `v3_h0_prototipo_propuesta.md` define y valida el caso H0-only; aclara que
  su solicitud de velocidad no decide el formato de los demás cores.
- `v3_hanging_ciclo_propuesta.md` concreta Hanging estático a nivel de
  comportamiento, pero declara abierto el formato técnico de su intención.
- Ladder y Mantle todavía no tienen un contrato V3 específico. Esta nota no
  completa esos huecos por analogía con V2.

## Comparación por core

| Core | Qué decide el core | Qué necesita que haga la física en cada tick | Qué hechos debe poder leer después | Relación con el mundo que debe revalidar | Cómo deja de gobernar | Estado actual |
| --- | --- | --- | --- | --- | --- | --- |
| **H0** | Locomoción normal, salto y postura deseada a partir de input, cámara y hechos previos. | Interpretar su intención de velocidad, salto y postura; resolver colisiones una vez. | Desplazamiento, velocidad, piso, contactos, aceptación de salto y estado físico de postura. | Piso, colisiones y espacio para cambiar postura. | Cede cuando otro core comienza ejecución física; vuelve a ser el valor por defecto al terminar el otro core. | Implementado y probado como laboratorio H0-only. |
| **Hanging** | Si puede entrar, si sigue sostenido, la pose `P` actual y sus salidas. | Intentar ocupar o mantener la `P` recalculada este tick dentro de las reglas de colisión; informar si no puede. | Pose/desplazamiento resultante, contactos y resultado de aplicar o bloquear la intención. | Pared, borde, normal y relación cilindro/esfera; `P` nunca es una coordenada mundial congelada. | Soltar, salto, pérdida de soporte o bloqueo físico; todos retornan a H0. | Diseño de sostén estático propuesto; runtime actual sólo publica candidata. |
| **Ladder** | Todavía no definido para V3: entrada, subida, bajada, salida y salto son preguntas abiertas. | Sólo está decidido el principio: emitir una intención reactiva por tick a la capa física común. | Hechos físicos posteriores al intento. | Aún no decidido: soporte, extremos, orientación y relación con la escalera. | Debe terminar en H0; no hay transferencia directa desde Hanging u otro core. | No diseñado técnicamente ni implementado. |
| **Mantle** | Puede conservar fases o un recorrido previsto internamente, pero decide el intento del tick actual. | Intentar la solicitud emitida este tick, sin ejecutar una trayectoria autónoma recibida de otro sistema. | Hechos físicos posteriores al intento, incluidos bloqueos. | Aún no decidido: apoyo, trayectoria, aterrizaje y criterios de continuidad. | Debe terminar en H0; no hay transferencia directa desde otro core. | No diseñado técnicamente ni implementado. |

## Lo que sí es común y reutilizable

Éstas son reglas ya decididas por V3; no dependen de que el core se llame
Hanging, Ladder o Mantle:

1. **Un solo core gobierna el movimiento físico por tick.** H0 gobierna por
   defecto; un core sólo lo desplaza al iniciar ejecución física.
2. **La física común es la única escritora del `CharacterBody3D`.** Los cores
   no escriben posición, velocidad, collider ni llaman operaciones de
   movimiento directamente.
3. **El core activo emite una intención actual en cada tick.** No entrega un
   plan de varios ticks para que la física lo ejecute sola.
4. **La física intenta la intención y publica el resultado real.** El core no
   presume éxito y decide el tick siguiente desde hechos posteriores.
5. **El soporte es metaestable.** Si un core depende de borde, escalera,
   plataforma o aterrizaje, relee la relación actual; no trata una coordenada
   almacenada como verdad eterna.
6. **Todo core no-H0 vuelve a H0.** No existen transferencias físicas directas
   entre cores.
7. **La selección no puede depender del orden de nodos.** Detectar una
   candidata no equivale a tomar gobierno.

Estas siete reglas describen la frontera reutilizable. Son suficientes para
evaluar cualquier propuesta técnica posterior.

## Lo que debe permanecer específico de cada core

No debe entrar en una infraestructura genérica:

- Qué geometría, input y estado hacen posible la entrada.
- Qué significa soporte para esa mecánica.
- Qué intención concreta formula: velocidad en H0, pose recalculada en
  Hanging u otra forma futura para Ladder/Mantle.
- Qué resultado físico requiere para seguir, ajustar o salir.
- Sus salidas, impulsos, postura especial y política de cámara.
- Cualquier lectura de certeza contextual y cómo interpreta sus providers.

Por ejemplo, la infraestructura no debe tener un estado llamado `hanging`,
ni saber qué es una pared o un borde. Hanging es quien construye y revisa `P`;
la física sólo recibe una solicitud que todavía debe definirse técnicamente.

## Información que ya alcanza para diseñar el contrato técnico

La futura propuesta técnica debe demostrar que cumple las siete reglas
comunes y responder, como mínimo:

| Pregunta técnica pendiente | Debe resolverse sin asumir |
| --- | --- |
| ¿Cómo se representa cuál core gobierna? | Que deba ser un lease de V2, un booleano o un nodo árbitro. |
| ¿Cómo se entrega una intención física? | Que todos los cores pidan velocidad o todos pidan una pose. |
| ¿Qué resultado devuelve la física? | Que el formato de V2 (`OK/BLOCKED/REJECTED`) sea automáticamente el de V3. |
| ¿Cómo se evita que H0 y otro core emitan a la vez? | Que el orden de `_physics_process` funcione como árbitro implícito. |
| ¿Cómo se aplica una pose o desplazamiento con colisión? | Que una verificación de destino o un teletransporte sea suficiente. |
| ¿Qué postura puede pedir un core? | Que el collider actual de H0 sea válido para cada mecánica futura. |

V2 puede aportar evidencia de riesgos físicos y pruebas que vale la pena
considerar. No define las respuestas de esa tabla.

## Conclusión

La reutilización buscada no es un controlador universal de parkour ni un
port de V2. Es una **frontera física neutral** que aplica una única intención
del core gobernante y publica el resultado real. H0 ya es el primer ejemplo;
Hanging será el segundo y el primer caso que exige una intención distinta de
velocidad. Ladder y Mantle sirven como límites: obligan a que la solución no
lleve conceptos de Hanging dentro de la capa física.
