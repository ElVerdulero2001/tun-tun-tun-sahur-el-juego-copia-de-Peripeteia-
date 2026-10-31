# V3 — Hanging: ¿quién detecta el contacto cilindro ↔ esfera?

## Estado

**Resuelto (2026-09-20).** Se elige la dirección de la opción A: un actor
nuevo y chico, `HangingCaptureContactDetector`, dedicado al contacto continuo.
El documento maestro es `v3_hanging_rediseno_paso_a_paso.md`; esta nota
conserva las alternativas que se consideraron.

`HangingCaptureContactDetector` pertenece a la familia genérica **detectores
de contacto**. Un detector de contacto compara volúmenes o trayectorias de
sondas y publica el hecho crudo de contacto; no decide gameplay.

## Contexto

- **Regla del usuario:** las sondas solo adquieren y muestran datos. No
  calculan, no procesan, no computan. Cada core que necesita un dato lo
  consume.
- **Dos grupos de sondas.** Detección (rayos horizontales y verticales) y
  captura (cilindro de pared y esfera del player). Las de captura aparecen solo
  cuando V3 ya determinó que la pared sirve para Hanging, y solo sirven para
  marcar el momento del snap.
- **Cilindro de pared:** acostado, con eje perpendicular al muro, sale 0.5 m de
  la cara, tope al ras del borde, radio editable. Hay **uno por cada agarre
  válido**.
- **Esfera del player:** parte alta de la cápsula, del lado que mira al muro,
  sin depender de la cámara.
- El cilindro y la esfera son **volúmenes imaginarios**. El motor de física no
  sabe nada de ellos. Un rayo, en cambio, le pregunta al motor y este responde.

## El problema

Alguien tiene que responder, en cada tick:

> ¿La esfera tocó algún cilindro, o lo cruzó entre dos ticks? ¿Cuál?

Eso es geometría (distancia y barrido del camino de la esfera entre ticks). Si
lo hace la sonda, la sonda calcula y rompe la regla. Si lo hace el core, el
core carga con una cuenta que no es suya. Y el evaluador de candidatos no es
el lugar: su trabajo es evaluar si la pared sirve para Hanging.

Requisitos que cualquier opción debe cumplir:

1. Detectar el contacto actual.
2. No perder un contacto por velocidad (cruce entre ticks).
3. Decir **qué cilindro** fue tocado.
4. Publicarlo como hecho crudo. Decidir Hanging y pedir el snap es del core; la
   capa física lo aplica.

## Opción A: una pieza nueva y chica, aparte de todo lo demás

Un detector de contacto con **un solo trabajo**: leer las posiciones del
cilindro y de la esfera y publicar "hubo contacto" y "fue este cilindro".

- No es sonda, ni core, ni el evaluador de candidatos.
- Las sondas de captura quedan bobas: solo muestran dónde están y su tamaño.
- El barrido entre ticks vive en esta pieza.
- El core consume el hecho publicado, valida sus condiciones y pide el snap.

Flujo:

```text
sondas de captura (posiciones y tamaños)
        ↓
detector de contacto (único trabajo: ¿se tocaron? ¿cuál?)
        ↓
core de Hanging (valida y pide el snap)
        ↓
capa física (aplica)
```

A favor:
- Cumple la regla al pie de la letra: las sondas no calculan.
- Cada pieza hace una sola cosa. Es el mismo patrón que ya usa V3 (los rayos
  publican crudo y otra pieza interpreta).
- No depende de montar física nueva.
- Encaja con el laboratorio actual: la cuenta ya existe, solo cambia de lugar.

En contra:
- Es una pieza más, con su nombre y su lugar en el orden de ejecución.
- Si otro core usara el mismo tipo de captura, habría que reutilizar el
  detector o repetirlo.

## Opción B: que lo haga el motor de física

El cilindro pasa a ser un **objeto físico real**, en una capa que solo ve la
esfera, sin interactuar con el gameplay. La esfera se consulta como una forma
que se desplaza desde su posición anterior a la actual, igual que un rayo. El
motor hace la geometría y el barrido, y dice qué objeto tocó.

- Las sondas solo leen lo que el motor responde. Ninguna pieza extra calcula.
- El "qué cilindro fue" sale directo de lo que el motor devuelve.
- El core consume el hecho y pide el snap, igual que en la opción A.

A favor:
- Es lo más fiel a "sondas bobas": el contacto es un dato adquirido del motor,
  como un impacto de rayo.
- No hace falta una pieza intermedia.
- El barrido lo resuelve el motor.

En contra:
- Hay que montar capas de colisión propias para estos volúmenes.
- Hay que crear y borrar un objeto físico por cada agarre válido, en cada
  cambio de candidato.
- El laboratorio actual evitó deliberadamente crear colliders o áreas para
  estas sondas; habría que revisar esa decisión.
- Riesgo de efectos secundarios si las capas no quedan bien aisladas del
  gameplay.

## Comparación

| | A: pieza aparte | B: motor de física |
| --- | --- | --- |
| Quién calcula el contacto | Detector de contacto | El motor |
| ¿Las sondas calculan? | No | No |
| ¿Pieza nueva? | Sí | No (pero sí objetos físicos nuevos) |
| Barrido entre ticks | En el detector | Consulta de forma desplazada |
| "Qué cilindro" | Lo publica el detector | Lo devuelve el motor |
| Cambio respecto del laboratorio | Mueve la cuenta existente | Reemplaza la cuenta por física |
| Riesgo principal | Una pieza más | Capas y ciclo de vida de los objetos |

## Otras respuestas consideradas

- **El core hace la cuenta:** las sondas quedan bobas, pero el core carga con
  geometría que no es suya.
- **La sonda de captura lo hace (respuesta de GPT):** trata "se tocaron" como
  un hecho del mundo, no como una decisión. Coincide con el laboratorio actual
  y da "qué cilindro" con claridad, pero exige una excepción a la regla "las
  sondas no calculan".

## Resolución

- Los cilindros y la esfera permanecen como sondas bobas que exponen datos.
- `HangingCaptureContactDetector` es un actor nuevo: detecta toque/cruce entre
  ticks y publica el cilindro o agarre tocado. No interpreta gameplay.
- Se ubica después de las sondas de captura y antes de `HangingCore`.
- `HangingCore` decide la entrada y solicita el snap; `V3PhysicsBody` lo
  aplica.
- La opción B queda descartada por ahora: no se crearán colliders, áreas ni
  capas de física para volúmenes de captura imaginarios.
