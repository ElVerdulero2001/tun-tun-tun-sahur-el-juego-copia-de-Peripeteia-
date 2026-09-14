# V3 — Propuesta: autoridad del movimiento físico

## Propósito

Definir una división inicial de responsabilidades para cuando una mecánica de parkour ya está ejecutándose. El modelo de lectura de intención y árbitro incluido más abajo conserva elementos provisionales; la regla de gatillo por certeza contextual está decidida explícitamente en su propia sección.

## Nivel del documento: concepto arquitectónico

Este documento define responsabilidades y flujo conceptual. No define la representación de una intención de movimiento en código: no fija tipos de solicitud, campos, APIs, operaciones de Godot ni modos de colisión. Esas decisiones pertenecen a prototipos técnicos posteriores y no modifican este fundamento por sí solas.

## 🚨 Nota para Claude: no completar huecos

Este documento no es una autorización para inferir decisiones desde V2, desde `v3_decisiones_abiertas.md` ni desde una recomendación previa. Si algo no aparece como decisión explícita acá, sigue abierto.

Está decidido que un core activo expresa intención de movimiento por tick físico; que sólo un core gobierna el movimiento físico a la vez; y que toda ejecución parte de `H0` y vuelve a `H0`.

No está decidido cómo se implementa temporalmente ese paso por `H0` entre dos ejecuciones: en particular, no se debe asumir un tick obligatorio de locomoción normal de H0, ni un *handoff* especial. Tampoco están decididos los tipos o campos del contrato físico, la API de Godot ni el modo de colisión. El modelo de árbitro que aparece abajo está en exploración: no debe tratarse como contrato final ni completarse con suposiciones externas.

No conviertas una pregunta pendiente en requisito de V3 sólo porque V2 lo implementaba de cierta manera o porque un documento anterior la enumeraba.

## Vocabulario usado

V3 usa **core** para una unidad de comportamiento propia: `H0`, `Hanging`, `Ladder`, `Mantle`, etc. No hay una jerarquía de “módulo que contiene un core”.

- `H0` es el core mínimo global del player. Gobierna el movimiento normal y capacidades base como salto o agacharse, y no se desactiva como conjunto.
- Los demás cores son configurables de forma independiente.
- Una submecánica es una capacidad dentro de su core. Puede desactivarse para gameplay, pero no necesita dejar de evaluarse para diagnóstico.

La cámara y las directivas de input son infraestructura compartida del player: no existen una cámara ni controles distintos para cada core. `H0` los usa durante el movimiento normal, y los demás cores acceden a los mismos datos cuando gobiernan el movimiento.

La cámara es una sola referencia continua del player, no una cámara por perspectiva ni por core. Su distancia puede variar gradualmente entre primera y tercera persona, con posiciones intermedias, sin que esa distancia altere la dirección de movimiento. Un cambio visual de distancia o perspectiva no emite movimiento físico, no rota ni reubica por sí mismo el body y no puede terminar o iniciar un core. El core que gobierna conserva su estado; por ejemplo, cambiar la cámara durante Hanging no saca al player de Hanging.

No se divide internamente un core entre una capa arquitectónica “indispensable” y otra “adicional”. Esa clasificación, si alguna vez hace falta para una mecánica concreta, se decidirá al diseñar ese core; no se presupone aquí.

## Decisión: contrato físico reactivo por tick

V3 usa una separación híbrida, con límites nítidos. El contrato físico elegido es reactivo: un core activo expresa su intención de movimiento en cada tick físico; la capa física común intenta aplicarla y devuelve el resultado real.

- Cada core es dueño de la lógica exclusiva de su mecánica: Hanging interpreta agarres, sostén, desplazamiento lateral y sus salidas; Ladder interpreta su propia lógica; Mantle, la suya.
- Una única capa física común es la autoridad que aplica el movimiento al cuerpo/collider real del player y devuelve el resultado físico.

```text
core activo decide su intención de movimiento
        ↓
capa física común intenta aplicar el movimiento al cuerpo
        ↓
estado físico real del body y sus contactos
        ↓
providers exponen esos hechos; el core los lee y continúa, ajusta o cancela
```

Un core no modifica el cuerpo/collider por su cuenta. Expresa una intención de movimiento para el tick en curso; la capa física la intenta aplicar dentro de las reglas de colisión. El estado posterior queda disponible como hechos físicos compartidos, no como un mensaje privado entre componentes.

Una mecánica puede conservar internamente fases, tiempos o un recorrido previsto —por ejemplo, Mantle—, pero no entrega una trayectoria física autónoma para que otra capa la ejecute durante varios ticks. El core sigue leyendo el resultado físico y emitiendo la intención del tick siguiente. Esto mantiene el movimiento reactivo frente a cambios del mundo.

## Decisión: H0 es el control físico por defecto

Durante el movimiento normal, `H0` gobierna el movimiento físico del player. Cuando cualquier otro core llega a ejecución física —`Hanging`, `Ladder`, `Mantle` u otro—, `H0` pausa su ejecución de movimiento físico y ese core pasa a ser el único que emite solicitudes físicas para el cuerpo mientras permanezca activo.

No se combinan solicitudes de movimiento de `H0` y del core activo, y `H0` no recibe información del otro core para decidir cómo ejecutarlo. La capa física común recibe la solicitud del core que tiene el control físico en ese momento y aplica una sola autoridad de movimiento.

La detección, generación de candidatos o diagnóstico de otro core no desplazan a `H0`: sólo lo hace la ejecución física. Cuando no hay otro core ejecutando movimiento físico, `H0` vuelve a ser quien lo controla normalmente. Esto expresa una exclusión simple de control físico; no presupone todavía un mecanismo concreto de *lease*, árbitro o máquina de estados.

La transición de control sólo cambia quién interpreta las directivas como movimiento físico. Cámara e input continúan siendo los mismos para todos los cores; no se crean versiones específicas de cámara o controles para Hanging, Mantle, H0 u otro core. Una orden de cambio de core no reinicia, reemplaza ni altera esas fuentes: siguen emitiendo el mismo estado según la cámara y las acciones del jugador. Por ejemplo, el mismo input de movimiento que H0 usa para locomoción normal puede ser interpretado por Hanging como desplazamiento lateral, si Hanging decide consumirlo.

Esto no significa que las capacidades físicas de H0 sigan ejecutándose: mientras otro core gobierna el cuerpo, salto, agacharse o movimiento normal de H0 no emiten solicitudes físicas por separado.

## Hipótesis provisional: lectura de intención y candidato preferido

Esta sección describe una idea en exploración. No autoriza a implementar un árbitro ni fija todavía fórmulas, desempates o su representación técnica. La excepción explícita es el gatillo conceptual de certeza contextual definido en la sección siguiente.

```text
datos neutrales de sondas
        ↓
cada core consumidor interpreta sólo sus datos relevantes
        ↓
si un core es físicamente posible, calcula su valor X
        ↓
el árbitro compara los X de candidatos posibles
        ↓
el X mayor queda marcado como candidato preferido
        ↓
todavía no se ejecuta ningún core
```

Una sonda se crea con un peso base asociado a su posición respecto del centro visual: una sonda más centrada aporta más a la predicción de intención que una más periférica. Cuando una medición debe distinguir lados opuestos de un valor de referencia, conserva también su signo o polo; no se reduce a una distancia absoluta que perdería esa diferencia. La escala concreta de pesos, el significado exacto de la referencia y las fórmulas de X siguen abiertos.

Cada core conserva la semántica de su mecánica: determina primero si puede activarse físicamente y sólo entonces calcula X a partir de los datos y pesos que consume. Un peso nunca vuelve posible un core físicamente inválido.

El árbitro no interpreta geometría de Hanging, Ladder o Mantle, no mueve el player y no ejecuta cores. Recibe candidatos posibles con sus X, los compara y expresa cuál representa mejor la intención probable del jugador. Que un candidato sea preferido no equivale todavía a ejecutar el core.

El debug de esta hipótesis debe permitir seguir la cadena completa: dato de sonda, peso y signo, contribución al X de cada core posible, comparación final y candidato preferido.

## Decisión: gatillo automático por certeza contextual

La certeza contextual no es por sí sola un permiso de entrada. Antes de participar en el gatillo, cada core debe aprobar sus propios **prerrequisitos de entrada**. Esos prerrequisitos pertenecen a la semántica del core, no a una regla genérica del árbitro: pueden incluir estado actual del player, movimiento, postura, caída, dirección de cámara u otras condiciones que esa mecánica realmente necesite.

Por ejemplo, un core puede requerir que el player esté cayendo, corriendo o agachado, o que la mirada tenga cierta relación con el entorno. Estos ejemplos no fijan todavía las reglas de Hanging, Mantle ni Ladder: sólo aclaran que una certeza alta nunca saltea las condiciones de entrada propias del core.

El estado de agacharse de `H0` y mantener `Ctrl` no son la misma regla, aunque compartan control. Agacharse es una acción persistente de H0: una pulsación alterna entre agachado y parado. Mantener `Ctrl` es una directiva compartida que, para los cores que la consumen, bloquea su entrada. Hanging, Mantle, Ladder y casi todos los cores contextuales que declaren ese consumidor quedan excluidos antes de calcular y repartir la certeza contextual mientras `Ctrl` esté mantenido. No les baja la certeza ni los transforma en candidatos débiles.

No es un bloqueo universal impuesto desde el árbitro: un core que no consume `Ctrl` no se ve afectado. Por ejemplo, Parry y otros cores cuya mecánica no necesita leer esa directiva pueden seguir usando sus propias condiciones de entrada. Cada core declara sólo los inputs que realmente necesita, incluido si `Ctrl` es una condición de bloqueo para él.

Los cores contextuales que compiten por gobernar el movimiento —por ejemplo, `Hanging`, `Mantle` y `Ladder`— no producen porcentajes independientes. Para una misma lectura contextual, sus certezas forman una distribución cerrada de `100`.

```text
Hanging: 92
Mantle:   5
Otros cores contextuales: 3
──────────────────────────
Total:  100
```

Por eso `Hanging = 92` ya expresa tanto que es el candidato preferido como que el contexto favorece fuertemente Hanging frente a las demás alternativas. No existe, para esa misma lectura, un segundo core con un `90` independiente que deba compararse después.

No existe un bolsón ni candidato artificial de “no activar” dentro de ese total de `100`. Un core que ya aprobó todos sus prerrequisitos y es el único candidato contextual puede recibir `100`; eso es correcto. Si el jugador no debía poder entrar a ese core en cierta situación, esa situación debe expresarse como un prerrequisito de entrada —por ejemplo, que ese core consuma `Ctrl` como bloqueo— y excluirlo antes de la distribución, no restarle certeza después.

El gatillo de los cores contextuales es automático, pero exige ambas cosas: prerrequisitos de entrada aprobados y certeza contextual de `90` o más para el core preferido. Recién entonces puede iniciar su ejecución desde `H0` y tomar el gobierno físico. Si ningún core reúne ambas condiciones, no se produce traspaso; `H0` sigue gobernando y la lectura se vuelve a evaluar. No se crea un botón separado para Hanging, Mantle o Ladder.

`90` es el **valor provisional explícito** del umbral: no es todavía su calibración definitiva, pero tampoco una incógnita que se deje como `X` hasta más adelante. Es el valor de referencia vigente para diseñar y prototipar el gatillo; podrá cambiarse cuando existan fórmula, debug y pruebas que justifiquen un ajuste.

```text
prerrequisitos propios del core aprobados
        ↓
distribución contextual de certeza (total 100)
        ↓
¿el core preferido alcanza 90?
   ├── sí → H0 cede el gobierno al core
   └── no → H0 continúa; no se ejecuta ningún core contextual
```

El valor se llama **certeza contextual** en este fundamento: representa la lectura relativa actual del sistema, no una probabilidad estadística ya calibrada. El ajuste posterior mediante pruebas y debug podrá revisar pesos y el valor provisional `90`, pero no debe inflar valores artificialmente sólo para forzar que una acción alcance el umbral.

### Cores fuera de la predicción contextual

No todos los cores participan de esa distribución. Cores como `Parry`, doble salto o deslizamiento/embestida no necesitan sondas del mundo para decidir su posibilidad principal. No deben restarle certeza a Hanging ni competir con Ladder dentro del mismo total de `100`.

El sprint actual no pertenece a ese grupo: es una submecánica de `H0` que por ahora sólo modifica su locomoción normal y no toma el gobierno como core separado.

Esos cores no contextuales se activan desde sus propias directivas de input y condiciones de estado o físicas pertinentes. Siguen siendo cores de V3 y siguen respetando la autoridad física cuando corresponda, pero su forma concreta de entrada se definirá al diseñar cada mecánica. Esta decisión sólo define el gatillo de los cores que compiten por contexto espacial del mundo.

## Decisión: bloqueo de voluntad antes de los cores

Cuando sea necesario impedir que la voluntad del jugador produzca movimiento o activaciones, el mecanismo vive antes de los cores: se desactiva la captura de la información de input del player. En ese estado, H0 y los demás cores no reciben nuevas directivas voluntarias desde el jugador. Esto no requiere que un árbitro conozca menús, escenas especiales o una lista de excepciones.

La muerte del player no es una excepción que el selector de cores deba resolver: el player pasa a ragdoll, fuera del sistema de cores. Cinemáticas u otros sistemas no implementados no definen requisitos para V3 en esta etapa.

## Decisión: H0 es la frontera obligatoria del ciclo

El player comienza en `H0`. Todo core distinto de `H0` sólo puede comenzar su ejecución desde `H0`, y todo core distinto de `H0` termina devolviendo el gobierno a `H0`.

```text
H0 → Hanging → H0 → Ladder → H0 → Mantle → H0
```

No existen excepciones ni transferencias directas entre cores. Un core no inicia a otro ni le entrega control: cada uno termina por completo en `H0`, y desde ahí puede comenzar una nueva ejecución si corresponde.

Esta regla define el origen y destino de cada ejecución. No introduce un *handoff* entre cores.

## Por qué

Si cada core mueve al player directamente, Hanging, Ladder y Mantle terminan repitiendo manejo de collider, colisiones, velocidad y fallos. Eso reproduce el problema de acumulación de V1.

Si una capa central conoce cómo funciona cada mecánica, esa capa termina conteniendo Hanging, Ladder, Mantle y las demás. Eso reproduce la concentración de responsabilidades que V3 busca evitar.

La separación propuesta conserva ambos límites:

- El core conserva la semántica de su comportamiento: sabe qué intenta hacer y por qué.
- La capa física conserva la autoridad del cuerpo: aplica movimiento, resuelve contacto y reporta la realidad física.

La capa física no decide que algo sea Hanging ni conoce la lógica de una trepada. Es infraestructura neutral, no un controlador de parkour con otro nombre.

## Relación con la simulación

La simulación tiene prioridad. Que un core quiera colgarse, trepar o avanzar no garantiza que ocurra: si la aplicación física encuentra una colisión o una condición inválida, el resultado real se reporta al core. Ninguna animación, cámara o efecto puede fabricar ese resultado.

## Consecuencia: ejecución metaestable

Un core en ejecución no trata las condiciones que lo sostienen como un permiso permanente obtenido al entrar. En cada tick físico vuelve a leer los hechos actuales que necesita para continuar.

Si cambia el entorno, cambian los datos expuestos por los providers; si esos datos dejan de sostener la ejecución, el core ajusta su comportamiento o termina y devuelve el gobierno a `H0`. Por ejemplo, si desaparece un borde o se pierde el soporte de Hanging, Hanging lo detecta a partir del estado actual del mundo y resuelve su propia salida. No hace falta un mecanismo separado de “eyección forzada” para cambios físicos que el sistema ya puede observar.

### Decisión: referencias de soporte metaestables

Toda coordenada que un core use como soporte —un borde, escalera, plataforma móvil, superficie de aterrizaje o piso— representa una relación válida sólo para el estado actual del mundo. No es una posición permanente obtenida al entrar al core.

En cada tick físico, el core debe volver a leer los hechos actuales de su soporte y su relación con él. Si el soporte se traslada, rota, cambia su geometría o desaparece, el core debe ajustar su intención usando la realidad actual o terminar y devolver el gobierno a `H0` si ya no puede sostener su mecánica.

Un core puede conservar una referencia interna a su soporte, pero no puede tratar una coordenada mundial guardada como verdad eterna. La capa física sigue siendo la única autoridad que aplica el movimiento real.

Esta decisión no fija cómo se representa técnicamente esa relación: ancla local, transform relativo, velocidad de plataforma u otra técnica quedan abiertos.

## Decisión: señales externas con dos efectos

Las señales externas al parkour pueden afectar al player de dos maneras distintas:

- **Interrupción obligatoria:** el core que gobierna debe terminar y devolver el gobierno a `H0`. Desde ahí, el estado externo correspondiente puede tomar al player si hace falta. El core puede limpiar su estado interno, pero no puede vetar la interrupción.
- **Modificador temporal:** no corta el core activo. Se publica como una condición externa actual que los cores interesados pueden consumir y tener en cuenta mientras siga vigente.

La clasificación de una señal como interrupción o modificador pertenece al sistema externo que la origina, no al árbitro ni a cada core individual. No se definen todavía las desventajas concretas, sus prioridades, su formato ni su implementación.

## Todavía abierto

Esta decisión no define aún el formato técnico exacto de la intención por tick. La representación, los tipos, los campos y el contrato concreto de respuesta pertenecen a exploraciones técnicas posteriores. Las restricciones no se adoptan como formato de solicitud hacia la capa física.

Todo core que deja de gobernar el movimiento físico devuelve ese gobierno a `H0`. No existen transferencias físicas directas de un core a otro: la ruta es siempre `core saliente → H0 → posible core siguiente`. La única regla adicional adoptada es que no haya dos cores emitiendo movimiento físico en el mismo tick.

Todavía no se decidió si `H0` debe ejecutar obligatoriamente un tick físico real antes de que otro core pueda entrar. La ruta de gobierno está definida; la duración efectiva de ese paso por `H0` no.

No existe aún un contrato de *handoff* ni se definió qué datos podría transportar. El estado físico actual del player —posición, velocidad y contactos resultantes— permanece disponible como información compartida del mundo; no debe confundirse con un mensaje directo entre cores.

El acuerdo propuesto aquí es únicamente la frontera de responsabilidad: **los cores deciden su mecánica; una capa física común mueve el cuerpo real**.
