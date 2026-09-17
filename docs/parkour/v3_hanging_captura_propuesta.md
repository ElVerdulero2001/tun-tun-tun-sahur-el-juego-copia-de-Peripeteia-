# V3 — Propuesta de captura de entrada a Hanging

## Propósito

La detección actual puede publicar un candidato de Hanging válido. Eso no debe
producir un agarre inmediato desde cualquier distancia: un candidato describe
una posibilidad, no el momento físico exacto de capturar al player.

Esta propuesta define una capa intermedia de **captura de entrada**. Su tarea
es responder:

> Dado un candidato válido, ¿el player llegó suficientemente cerca y por el
> lado correcto como para hacer snap a la pose de Hanging?

No define todavía el árbitro final, el snap visual, el movimiento colgado ni
las salidas de Hanging.

## Idea central

Cada candidato válido ya contiene una pose física propuesta `P`: la posición y
orientación donde debería terminar el body al quedar colgado.

Se crea una **esfera virtual de captura** centrada en `P`. No es un collider,
no participa en la física del mundo y no la ve otro core. Es una referencia
temporal del candidato actual para medir la relación entre el body real y la
pose final.

```text
candidato válido
        ↓
pose propuesta P
        ↓
esfera virtual centrada en P
        ↓
body entra o cruza la esfera
        ↓
revalidación física de P
        ↓
snap permitido
```

La esfera se centra en la **pose**, no en el punto bruto del borde. El borde
representa dónde se encuentra el agarre; `P` representa dónde debe quedar la
cápsula real del player. Medir contra el borde podría capturar al player cuando
sus manos están cerca, pero su cuerpo todavía está mal posicionado.

## Condiciones de captura

La esfera no es suficiente por sí sola. Un snap sólo se permite si se cumplen
todas estas condiciones:

1. **El candidato sigue válido.** Pared, borde, altura, intención y demás
   requisitos duros se vuelven a observar tick a tick.
2. **El body está del lado libre de la pared.** No puede capturarse desde
   detrás ni a través de la geometría. La normal de pared del candidato define
   cuál es el lado externo.
3. **La intención no contradice la entrada.** Mantener una dirección de
   alejamiento sigue bloqueando Hanging aunque el body esté cerca.
4. **El body entra o cruza la esfera de captura.** Se mide contra una
   referencia coherente de la cápsula real, no contra la cámara.
5. **La pose `P` vuelve a caber físicamente.** Justo antes del snap, la capa
   física consulta otra vez si el collider puede ocupar la pose. El candidato
   puede haber cambiado desde el tick que se detectó.

## Entrada y cruce

No alcanza con mirar solamente la distancia en el tick actual. Con velocidad
alta, el body puede pasar de un lado de la esfera al otro entre dos ticks sin
que ningún frame lo encuentre dentro.

Por eso la captura debe aceptar cualquiera de estas dos situaciones:

```text
A. la referencia de la cápsula está dentro de la esfera en este tick;

B. el segmento entre su posición de referencia anterior y la actual
   intersecta la esfera durante este tick.
```

La condición B evita perder agarres válidos al caer o moverse rápido. No crea
un teletransporte desde lejos: sigue exigiendo que la trayectoria real haya
atravesado la zona alrededor de `P`.

## Relación con la cápsula real

El radio de captura no se decide como un número suelto. Debe partir del tamaño
de la cápsula real del player y sumar una tolerancia de laboratorio. Así la
zona expresa “el cuerpo está lo bastante cerca de su pose final”, no “el
origen abstracto del node está cerca”.

Todavía queda por decidir qué referencia exacta de la cápsula se mide:

- su centro físico;
- el root del `CharacterBody3D`;
- u otro punto explícito de la futura pose de Hanging.

El primer prototipo debe elegir una sola referencia y mostrarla en debug. No
debe alternar según cámara ni según animación.

## Cámara

La cámara no decide la distancia de captura ni la posición de snap. Esto evita
que primera y tercera persona tengan agarres físicamente distintos sólo por
alejar, acercar u orbitar la cámara.

La cámara puede seguir contribuyendo a la certeza e intención del candidato,
como ya hace el diseño de detección. Una vez que existe un candidato válido,
la captura se resuelve entre body, pose y geometría.

## Regla temporal del laboratorio

Mientras Hanging sea el único core contextual implementado, el laboratorio
puede usar esta regla provisional:

```text
candidato válido + condiciones de captura cumplidas
→ aceptar Hanging para probar el traspaso H0 → Hanging
```

No es el árbitro definitivo ni define qué ocurrirá cuando existan Ladder,
Mantle u otros candidatos. Sólo permite probar que el candidato, la captura y
la transferencia física se conectan sin inventar una competencia inexistente.

## Por qué esfera primero

Una esfera es simétrica, simple de calcular y fácil de visualizar. Permite
medir el feeling de captura sin fijar todavía una forma más específica.

Su límite conocido es que tolera aproximaciones parecidas desde todas las
direcciones. Las guardias de candidato válido, lado externo, intención y pose
libre reducen ese riesgo en la primera rebanada.

Si el playtest muestra capturas extrañas desde arriba o los costados, la
evolución prevista es reemplazar la esfera por un elipsoide o cápsula
**orientados según la normal de pared**. Ese reemplazo no cambia el contrato:
seguirían existiendo candidato válido, volumen de captura, cruce de trayectoria
y revalidación física.

## Debug necesario

El laboratorio debe poder mostrar:

- centro y radio de la esfera virtual;
- referencia actual y anterior de la cápsula;
- distancia actual a la esfera;
- si hubo entrada directa o cruce durante el tick;
- resultado de lado externo, intención y revalidación de pose;
- motivo por el que la captura quedó habilitada o rechazada.

El debug observa. No es quien autoriza el snap.

## Fuera de alcance

- radio numérico, tolerancias y referencia definitiva de cápsula;
- forma final de la zona de captura;
- formato exacto de la solicitud de pose a la capa física;
- interpolación, duración o cancelación del snap;
- arbitraje final entre varios cores;
- comportamiento de Hanging después del snap.
