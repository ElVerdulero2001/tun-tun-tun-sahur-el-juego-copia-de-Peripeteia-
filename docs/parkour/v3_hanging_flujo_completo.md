# V3 Hanging — flujo completo, de player a Hanging

## Propósito y autoridad

Este documento reúne en un recorrido único el diseño actual de entrada a
**Hanging**. Su objetivo es que se pueda entender el camino entero sin saltar
entre conversaciones ni reconstruirlo desde los documentos del laboratorio.

Es fuente de verdad para el **flujo conceptual actual**. No transforma en
decisiones vigentes los detalles históricos del laboratorio. Cuando algo no
está cerrado, se marca explícitamente como pendiente.

Documento de decisiones por pasos: `v3_hanging_rediseno_paso_a_paso.md`.

## La idea en una línea

```text
player en el aire
  → pared + superficie superior detectadas
  → borde/agarre válido
  → cilindro y esfera de captura aparecen
  → detector de contacto informa el primer toque o cruce
  → Hanging decide entrar
  → la física aplica el snap
  → estado HANGING
```

No hay una pieza que haga todo. Cada etapa entrega un hecho o una decisión a la
siguiente.

## Vocabulario

| Término | Significa | No significa |
| --- | --- | --- |
| **Sonda** | Algo que observa y publica datos crudos. | Una pieza que decide gameplay. |
| **Rayo horizontal** | Sonda hacia adelante que encuentra una cara de pared, su punto y su normal. | Una prueba de que esa pared tiene borde agarrable. |
| **Rayo vertical** | Tramo corto hacia abajo, junto a la pared, que encuentra superficies superiores por altura. | Un cálculo de Hanging o una decisión sobre qué superficie elegir. |
| **Borde / saliente** | La esquina superior frontal inferida de una pared y una superficie superior coherentes. | Un agarre ya aceptado automáticamente. |
| **Agarre candidato** | Un borde que superó las validaciones geométricas y de contexto necesarias para ofrecerse a Hanging. | El estado Hanging activo. |
| **Cilindro de pared** | Volumen imaginario de captura que sale desde un agarre válido. | Un collider de gameplay ni una orden de snap. |
| **Esfera del player** | Volumen imaginario de captura situado en la parte alta/frontal de la cápsula. | Un objeto que siga a la cámara. |
| **Detector de contacto** | Familia de actores que compara volúmenes o trayectorias de sondas y publica si hubo contacto. | Un core, una sonda o una autoridad de movimiento. |
| **`HangingCaptureContactDetector`** | Detector de contacto continuo concreto para Hanging. | El que decide entrar a Hanging o mueve el player. |
| **Snap** | Solicitud para colocar el body en la pose de Hanging calculada. | Una escritura directa de transform por parte del core. |

No se usa ninguna abreviatura para estas dos formas en este diseño: se dice
**cilindro/esfera** o se nombra la forma concreta.

## 1. Player, body y cámara

El player tiene un **body** que representa su realidad física: posición,
cápsula, velocidad, contacto con el piso y colisiones. `V3PhysicsBody` es la
única capa que puede escribir su transform o su velocidad y ejecutar el
movimiento físico.

La cámara está conectada a un pivote y puede rotar libremente sin forzar la
rotación del body. Esa separación evita que mirar hacia otro lado cambie por
sí solo dónde está físicamente el player o dónde queda un agarre.

Consecuencias importantes:

- La esfera de captura sigue al **body** y al lado del muro; nunca a la cámara.
- El cilindro se ubica desde el **muro/borde** y sigue el desplazamiento del
  player a lo largo de ese muro; nunca sigue la cámara.
- La cámara puede participar en input o presentación, pero no puede inventar
  una pared, un borde, un contacto ni un snap.

**Pendiente explícito:** fijar con qué referencia exacta apuntan los rayos
genéricos en cada situación (body, cámara o una dirección acordada). Esta
decisión no se infiere de la independencia de cámara de los volúmenes de
captura.

## 2. Las sondas genéricas leen el mundo

Por ahora hay dos familias de sondas genéricas. Son bobas: sólo adquieren y
publican datos. No construyen candidatos, no seleccionan agarres y no mueven
al player.

### Rayos horizontales: la cara de la pared

Una grilla vertical de rayos hacia adelante responde para cada muestra:

```text
¿hay una cara de pared aquí?
si la hay: punto de impacto + normal de la pared
```

Eso revela la **cara frontal** del obstáculo. No revela todavía dónde termina
esa pared arriba: una pared de un metro y una de diez metros pueden dar el
mismo impacto horizontal a la altura del pecho.

### Rayos verticales: la altura de la parte superior

Una fila continua de tramos cortos, pegada a la cara de la pared y apenas hacia
adentro, mira hacia abajo a lo largo de todo el rango alcanzable. Cada tramo
publica lo que tocó en su parte de altura.

Responde, en esencia:

```text
¿hay una superficie superior a esta altura junto a la pared?
si la hay: punto de superficie + normal de esa superficie
```

La fila continua existe para que no haya huecos entre muestras y para poder
ver, por ejemplo, el piso de una ranura con material por arriba. No decide si
esa superficie es útil; sólo la informa.

### Por qué se necesitan ambas

Vista lateral de una caja:

```text
             rayo vertical ↓
                   │
            ┌──────●──────  ← superficie superior, a cierta altura
            │      │
player ───→ ●      │          ← cara frontal de pared encontrada
            │      │
            └──────┘
```

El evaluador puede juntar estos dos hechos así:

```text
cara frontal de la pared + altura de la superficie superior
                        =
           esquina superior frontal de la caja
```

Esa esquina es el **borde/saliente candidato**. No es una intersección mágica
ni algo que calculen los rayos: es una relación que interpreta el evaluador.

## 3. Estar en el aire habilita la evaluación de Hanging

Cuando el player salta o cae, el hecho físico `en_piso` pasa a falso. El
evaluador de Hanging puede entonces considerar una entrada al sistema.

Las sondas genéricas pueden seguir observando aunque el player esté en el
piso; no conviene apagar su lectura para expresar una regla de gameplay. Lo
que ocurre estando en piso es que el evaluador publica el rechazo `en_piso` y
Hanging no puede entrar sólo por caminar contra una caja.

No se exige que el player esté cayendo: una captura puede ocurrir mientras aún
asciende después del salto, siempre que el resto de las condiciones sea válido.

## 4. El evaluador convierte datos en agarres candidatos

El **evaluador de candidatos de Hanging** es quien consume las muestras
horizontales y verticales. No es `HangingCore` y no es una sonda.

Para cada combinación que parezca pertenecer al mismo obstáculo, construye la
idea de un borde y comprueba que sea coherente. Entre sus validaciones están:

- la cara debe comportarse como pared usable;
- la superficie debe mirar hacia arriba y estar asociada coherentemente a esa
  pared;
- la altura debe estar dentro del rango alcanzable;
- debe existir el espacio libre mínimo acordado sobre el borde;
- el player debe estar en un contexto permitido, incluido no estar en piso;
- la pose propuesta de Hanging debe caber sin atravesar geometría.

La salida no es “entrá a Hanging”. La salida es uno o varios **agarres
candidatos**, cada uno con los datos que Hanging necesita, por ejemplo:

- punto del borde/saliente;
- punto y normal de la cara de pared;
- identidad del soporte/agarre;
- pose propuesta `P` para el body;
- motivos de rechazo si no resultó válido.

Puede haber varios agarres válidos, como en listones horizontales apilados. No
se elige uno por el orden accidental de una lista.

## 5. Árbitro: qué hay hoy y qué queda para después

V3 contempla que, cuando existan varios cores contextuales, un árbitro compare
sus candidatos. En ese futuro, si Hanging es el único core contextual capaz de
proponer una entrada, su certeza puede ser 100 porque no compite con otro core.

**Hoy no se diseña ni se implementa un árbitro real ni un switchboard.**
Hanging es temporalmente el único core contextual dentro de este alcance. Eso
no autoriza a usar orden de nodos o de listas como un árbitro escondido.

Los varios agarres de una misma pared tampoco se resuelven por árbitro: la
elección se concreta por el primer contacto real con el volumen del agarre
correspondiente.

## 6. Crear los volúmenes de captura

Sólo cuando el evaluador ya tiene un agarre válido aparecen las sondas de
captura. Antes de eso no existen como ventana de captura.

### Cilindro de pared

Se crea **un cilindro por cada agarre válido**.

- Es un cilindro acostado: su eje es perpendicular al muro.
- Nace en la cara del muro, no enterrado dentro de él, y sale hacia afuera.
- Su parte superior queda al ras del borde.
- Su longitud hacia afuera es 0.5 m; su radio queda editable.
- Sigue el desplazamiento tangencial del player a lo largo del muro, no la
  rotación de la cámara.

### Esfera del player

Se crea una esfera de captura dentro de la parte alta/frontal de la cápsula.

- Está del lado de la cápsula que mira al muro.
- Su posición se calcula desde el body y la dirección del muro, no desde la
  cámara ni desde la pose final `P`.
- Su radio y offset son parámetros editables.

El cilindro y la esfera no se siguen entre sí. Coinciden alrededor del mismo
contexto de agarre, pero cada uno tiene su propia referencia: muro/borde para
el cilindro, body/muro para la esfera.

Son volúmenes imaginarios de consulta. No se crean `Area3D`, colliders ni capas
de física de gameplay sólo para esta tarea.

## 7. El detector de contacto continuo

`HangingCaptureContactDetector` pertenece a la familia genérica **detectores
de contacto**. Es el actor nuevo que lee la esfera y todos los cilindros
activos. Su única pregunta es:

```text
¿la esfera tocó o cruzó un cilindro entre el tick anterior y éste?
Si sí: ¿qué cilindro/agarre fue?
```

Debe revisar dos casos:

1. **Contacto actual:** esfera y cilindro se solapan en la muestra presente.
2. **Contacto por barrido:** la esfera estaba antes de un cilindro y terminó
   después de él entre ticks, sin llegar a solaparlo en una muestra discreta.

El segundo caso evita perder un agarre cuando el player se mueve rápido.

Su salida es un hecho crudo, no una orden de gameplay:

```text
contacto: sí/no
tipo: contacto actual / cruce entre ticks
agarre: identidad del cilindro tocado
```

El detector no valida pared, intención, postura, poses, locks o prioridades.
No selecciona un core y no hace snap. Si dos cilindros fueran tocados de forma
indistinguible en el mismo instante, la regla exacta de desempate sigue
pendiente; nunca debe resolverse por el orden de una lista.

## 8. HangingCore decide, H0 cede y el body aplica

El evento del detector llega a `HangingCore` junto a la identidad del agarre.
El core consulta el candidato asociado y decide si la entrada todavía es
permitida. Como mínimo necesita que sigan siendo válidos:

- el agarre candidato y su pose `P`;
- el contexto aéreo;
- las reglas de postura/crouch;
- los locks de recaptura;
- cualquier gate contextual que pertenezca a Hanging.

Si algo falla, el contacto sigue siendo un dato ocurrido, pero no causa
Hanging. Si todo pasa, el core:

1. guarda la pose `P` y los datos del agarre elegido;
2. cambia su estado local hacia Hanging;
3. le indica a H0 que suspenda su publicación de locomoción en los ticks
   siguientes;
4. solicita un snap a `V3PhysicsBody`.

H0 no elige el borde, no interpreta el contacto y no aplica el snap. Su rol en
esta transición es dejar de gobernar la locomoción normal cuando Hanging tomó
la decisión.

`V3PhysicsBody` conserva la autoridad física. Recibe la solicitud, puede
verificar de nuevo que `P` sea ocupable y es quien aplica el snap. En el corte
de laboratorio, esa solicitud se consume en el tick físico siguiente; si se
acepta, fija la pose, detiene la velocidad correspondiente y separa el tramo de
caída anterior.

Sólo después de que la capa física acepta el snap, el player está oficialmente
en **HANGING**.

## 9. Orden conceptual por tick

El orden exacto de prioridades de nodos puede cambiar al implementar el
rediseño, pero la dependencia lógica no:

```text
hechos físicos previos e input
        ↓
sondas horizontales y verticales
        ↓
evaluador de candidatos
        ↓
cilindros y esfera de captura disponibles
        ↓
HangingCaptureContactDetector
        ↓
HangingCore
        ↓
solicitud a V3PhysicsBody
        ↓
aplicación física del snap
```

El body puede procesar una solicitud en el tick siguiente. Eso no es una
decisión tardía del detector: es la frontera normal entre decidir una acción y
aplicar el movimiento físico.

## 10. Responsabilidades, sin zonas grises

| Pieza | Hace | No hace |
| --- | --- | --- |
| Cámara/pivote | Presenta la vista y recibe su rotación propia. | Mover físicamente el body por mirar a otro lado. |
| `V3PhysicsBody` | Aplica movimiento, colisiones, velocidad y snap aceptado. | Elegir un agarre o decidir Hanging. |
| Rayos horizontales | Publican pared, punto y normal. | Inventar un borde. |
| Rayos verticales | Publican superficies superiores por altura. | Elegir una superficie o validar Hanging. |
| Evaluador de Hanging | Relaciona pared y superficie; construye candidatos y `P`. | Aplicar snap o detectar contacto esfera–cilindro. |
| Cilindro/esfera | Exponen los volúmenes de captura. | Calcular su contacto o decidir gameplay. |
| `HangingCaptureContactDetector` | Publica contacto continuo e identidad del agarre. | Validar entrada, suspender H0 o pedir snap. |
| `HangingCore` | Decide entrar/sostener/salir según sus reglas; solicita acción física. | Escribir transform o velocidad directamente. |
| H0 | Publica locomoción normal hasta que otro core la suspenda. | Ganar o perder Hanging por su cuenta. |

## 11. Lo que sigue abierto

Este documento no finge que el resto de Hanging ya esté cerrado. Siguen abiertos,
entre otros:

- valores concretos de radios, offsets, rango alcanzable, tramos verticales y
  espacio libre mínimo;
- dirección de referencia de las sondas genéricas;
- límite de cilindros simultáneos y su visualización de debug;
- desempate de dos contactos realmente simultáneos;
- contrato de árbitro cuando exista más de un core contextual;
- sostén, shimmy, esquinas, mantle, soporte móvil, animación y salida completa;
- **barrido entre ticks de los rayos horizontales:** riesgo de perder una pared
  a alta velocidad, abierto desde el inicio del diseño. Solo el detector de
  contacto tiene su barrido definido; los rayos horizontales no;
- **cámara y rayos horizontales:** el laboratorio actual apunta los rayos hacia
  la dirección plana de la cámara. Eso choca con la regla de que la cámara no
  inventa una pared (sección 1). Es el mismo pendiente de "dirección de
  referencia", con esta evidencia adicional;
- **contacto sostenido:** el detector publica el primer toque o cruce, pero no
  está escrito qué ocurre si la esfera sigue tocando el cilindro mientras el
  core rechaza la entrada (por ejemplo, Ctrl mantenido). En el laboratorio
  actual no hay captura tardía: hay que salir y volver a entrar. Falta decidir
  si eso se conserva y si el detector publica solo el flanco o también el estado
  sostenido;
- **quién crea y borra el cilindro y la esfera:** la sección 6 dice que
  "aparecen" con un agarre válido, pero la tabla de responsabilidades (sección
  10) no asigna esa tarea a ninguna pieza.

Nada de esos pendientes cambia el recorrido básico de detección → candidato →
contacto → decisión → snap que fija este documento.
