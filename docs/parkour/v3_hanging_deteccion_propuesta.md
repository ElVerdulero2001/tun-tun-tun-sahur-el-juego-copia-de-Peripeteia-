# V3 — Propuesta inicial de detección para Hanging

## Propósito

Esta propuesta define el primer conjunto de información para detectar un
candidato de entrada a **Hanging**. Aplica el contrato de entrada y resuelve
la discusión sobre detección compuesta sin fijar todavía cantidades de probes,
distancias, pesos, APIs de Godot ni umbrales numéricos.

El objetivo no es que una sonda "adivine Hanging". El objetivo es reunir
hechos distintos, cruzarlos de forma explicable y descartar únicamente lo que
sea físicamente imposible.

## Fuentes compartidas del player

Hanging no recibe datos desde H0. Tanto H0 como Hanging consumen las mismas
fuentes comunes del player:

- **capa física:** posición, velocidad, orientación, contactos y `en_piso`;
- **input:** dirección e intención expresada por el jugador;
- **cámara:** dirección de observación compartida;
- **observadores geométricos:** impactos, puntos, normales y volúmenes del
  mundo.

Por eso, al transferirse el gobierno `H0 → Hanging`, no se reinician ni se
interrumpen la cámara, los controles ni los hechos físicos. Sólo cambia el
core que interpreta esas fuentes para producir una directiva de movimiento.

## Conjunto inicial de observación

El primer laboratorio usa cuatro piezas con responsabilidades diferentes.

### 1. Grilla de rayos hacia adelante

Una serie vertical de rayos horizontales delante del player publica posibles
impactos de pared a distintas alturas. Cada resultado expone al menos su punto
de impacto y normal.

No declara que exista Hanging. Sólo responde: “en esta altura encontré esta
superficie”.

### 2. Rayos descendentes desde los impactos

Para cada pared candidata, un rayo desde arriba busca una superficie superior.
Hanging contrasta ambos resultados para comprobar que pared y tapa describen
el mismo borde, no dos objetos cercanos encontrados por accidente.

La relación pared + borde es una condición estructural: si no es coherente,
no existe candidato Hanging.

### 3. `ShapeCast` o volumen frontal

Un volumen frontal publica si también existe geometría con volumen frente al
cuerpo. Sirve como corroboración adicional contra lecturas aisladas de rayos,
columnas finas, decoraciones o geometría irregular.

Su resultado es **evidencia de certeza**, no un requisito duro. Una cornisa
delgada puede ser agarrable aunque un volumen frontal amplio no la toque; no
debe perderse un agarre válido sólo por esa ausencia.

### 4. Validación de pose física

Cuando Hanging ya tiene una pose propuesta bajo el borde, consulta al motor de
forma hipotética:

> ¿La cápsula física real del player cabe en esta posición y orientación sin
> empezar dentro de geometría ni atravesarla?

Esta consulta no mueve al player, no anima nada y no descubre bordes. Es una
validación final de seguridad. Evita aceptar, por ejemplo, un borde que los
rayos ven correctamente pero cuya pose de colgado intersectaría un saliente,
una baranda o cualquier obstáculo no representado por las lecturas iniciales.

La pose libre es requisito duro: si no cabe, Hanging no publica una entrada
válida.

## Requisitos duros de entrada

Un candidato de Hanging sólo puede ser válido si se cumplen todos estos
hechos:

1. `en_piso: false`.
2. Hay pared vertical alcanzable y borde superior razonablemente horizontal.
3. El punto de pared y el borde son geométricamente coherentes entre sí.
4. El borde queda dentro del rango alcanzable de la pose.
5. La intención direccional compartida no es contradictoria con entrar al
   borde.
6. La pose física propuesta cabe sin penetración.

El requisito 4 es un prefiltro geométrico: compara la altura y distancia del
borde con el rango desde el que Hanging puede siquiera proponer una pose. Un
borde demasiado alto, bajo o lejano se descarta antes de consultar al motor.

El requisito 6 responde una pregunta distinta y posterior: una vez propuesta
una pose dentro de ese rango, comprueba si la cápsula física real cabe allí.
Un borde puede ser alcanzable y aun así tener un saliente, baranda u obstáculo
que vuelva imposible ocupar la pose. Por eso ambos chequeos son necesarios y
no son la misma validación repetida.

Para el requisito 5, Hanging compara la intención direccional compartida con
la dirección hacia el borde propuesto. No interpreta teclas crudas como `W` o
`S`, que dependen de la cámara y de la perspectiva. El resultado debe quedar
clasificado de forma visible:

- **neutra:** no hay dirección activa; no bloquea Hanging ni le aporta certeza
  por sí sola;
- **compatible:** la dirección activa acerca al player al borde; aporta
  certeza;
- **contradictoria:** la dirección activa aleja al player del borde; rechaza
  la entrada como condición dura.

Los límites técnicos que separan esas tres clases quedan para el laboratorio,
pero la consecuencia de cada una ya está definida.

El `ShapeCast`, la cantidad de rayos coincidentes, la velocidad, la dirección
de cámara y el contacto reciente no sustituyen ninguno de esos requisitos.

## Evidencia y certeza contextual

Una vez que existe un candidato físicamente posible, Hanging construye su
certeza contextual con evidencia como:

- cantidad y consistencia de impactos de rayos sobre la misma pared;
- respaldo o ausencia del volumen frontal;
- velocidad y dirección reales de acercamiento;
- orientación de cámara respecto del borde;
- coincidencia entre la intención del jugador y la entrada propuesta;
- contacto físico reciente, si existe.

Esta evidencia no activa Hanging. Produce un valor comparable dentro de la
distribución contextual común de V3; el árbitro decide si Hanging gana frente
a otros candidatos que también aprobaron sus condiciones duras.

## Flujo completo

```text
fuentes físicas, input y cámara publican hechos compartidos
probes de rayos publican pared, borde y normales
ShapeCast publica corroboración volumétrica
→ Hanging agrupa los hechos alrededor de un borde propuesto
→ Hanging comprueba aire, coherencia estructural e intención
→ Hanging descarta bordes fuera del rango alcanzable
→ Hanging valida la pose física propuesta
→ Hanging publica candidato + motivos + certeza contextual
→ árbitro selecciona el candidato ganador
→ traspaso de gobierno: H0 → Hanging
→ capa física común aplica la entrada real
```

Si la validación de pose falla, si el borde deja de ser coherente o si cambia
el entorno antes de aplicar la entrada, el candidato se rechaza o pierde
certeza en el siguiente tick. No se conserva como una verdad estática.

## Debug obligatorio

El laboratorio debe mostrar, por fuente:

- qué leyó y dónde;
- si se trató de un requisito duro o evidencia;
- el resultado, peso o motivo de rechazo;
- la pared, borde y pose que Hanging intentó asociar;
- la clasificación de intención: neutra, compatible o contradictoria;
- la certeza final de Hanging y el motivo por el que ganó o perdió.

El debug no participa de las decisiones. Es la radiografía necesaria para
detectar falsos positivos, falsos negativos y desacuerdos entre fuentes.

## Fuera del primer laboratorio

Quedan fuera por ahora:

- búsqueda inversa desde una superficie superior;
- usar contacto físico reciente como algo más que evidencia;
- probes laterales para shimmy, extremos y esquinas;
- valores concretos de cantidad, ubicación o frecuencia de las sondas;
- fórmula exacta de pesos, certeza y umbral de activación;
- snap de entrada, movimiento colgado, soltar, salto y mantle.

Estas exclusiones permiten probar primero una sola cosa: detectar, explicar y
validar físicamente un borde de Hanging antes de implementar su ejecución.
