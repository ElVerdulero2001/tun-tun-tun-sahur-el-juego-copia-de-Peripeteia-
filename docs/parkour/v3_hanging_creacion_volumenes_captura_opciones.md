# V3 — Hanging: ¿quién crea y borra el cilindro y la esfera de captura?

## Estado

**Sin decidir (2026-09-20).** Documento aparte para llevar la pregunta a
consulta. Deriva del punto pendiente de la sección 11 de
`v3_hanging_flujo_completo.md`.

## Contexto

- **Regla del usuario:** las sondas solo adquieren y muestran datos. No
  calculan, no procesan, no computan. Cada core que necesita un dato lo
  consume.
- **Sondas de captura:** el cilindro de pared y la esfera del player. Aparecen
  solo cuando el evaluador ya tiene un agarre válido. Solo sirven para marcar el
  momento del snap.
- **Cilindro de pared:** acostado, con eje perpendicular al muro, sale 0.5 m de
  la cara, tope al ras del borde, radio editable. **Uno por cada agarre
  válido.**
- **Esfera del player:** una sola, en la parte alta de la cápsula, del lado que
  mira al muro, sin depender de la cámara.
- Son **volúmenes imaginarios**: no son `Area3D`, colliders ni capas de física.
  El motor de física no sabe nada de ellos.
- **Piezas existentes:** el evaluador de candidatos (relaciona pared y
  superficie superior, construye agarres y la pose `P`), el detector de
  contacto `HangingCaptureContactDetector` (¿la esfera tocó o cruzó un
  cilindro entre ticks? ¿cuál?), `HangingCore` (decide entrar, sostener o
  salir) y `V3PhysicsBody` (aplica el snap).

## El problema

El flujo dice que el cilindro y la esfera "aparecen" cuando hay un agarre
válido, pero la tabla de responsabilidades (sección 10 del flujo completo) no
asigna esa tarea a ninguna pieza. Falta decidir:

1. ¿Quién produce el cilindro de cada agarre y la esfera del player?
2. ¿Qué pasa cuando un agarre deja de ser válido? ¿Quién lo retira?
3. ¿Quién los mantiene al día, ya que el cilindro sigue al player a lo largo
   del muro?

Requisitos que cualquier opción debe cumplir:

- **Respetar la regla de sondas bobas.** Las sondas no deciden ni calculan.
- **No mezclar trabajos.** El evaluador evalúa, el core decide, el body aplica.
- **Permitir el barrido entre ticks.** El detector de contacto necesita comparar
  la posición anterior con la actual del mismo cilindro, así que un agarre debe
  poder reconocerse de un tick al siguiente.
- **Un cilindro por agarre válido**, y ninguno si no hay agarres.
- **La esfera** aparece junto con los cilindros y no existe sin ellos.

## Idea que cambia el planteo

Como los volúmenes son imaginarios, "crear y borrar" no tiene por qué significar
crear y borrar objetos del juego. Pueden ser **una lista de datos que cambia
cada tick**. Esa idea es la base de la Opción 3.

## Opción 1: lo hace el evaluador de candidatos

Al publicar un agarre válido, el evaluador publica también su cilindro, y la
esfera.

A favor:
- Ya tiene todos los datos del agarre (borde, pared, normal, pose).
- No agrega piezas nuevas.

En contra:
- Le suma un trabajo que no es evaluar. Mezcla dos responsabilidades.
- El evaluador pasaría a producir cosas además de interpretar datos.

## Opción 2: lo hace `HangingCore`

El core mantiene los volúmenes mientras existan agarres válidos.

A favor:
- Los volúmenes son cosas propias de Hanging.

En contra:
- El core tendría que gestionar volúmenes aun sin estar en Hanging, mientras
  todavía es H0 quien gobierna.
- Su trabajo es decidir, no fabricar volúmenes.
- Crea una dependencia circular: el core decide en función de un contacto que
  detecta sobre volúmenes que él mismo mantiene.

## Opción 3 (recomendada): las sondas de captura publican una lista, sin crear ni borrar nada

Cada tick, las sondas de captura leen los agarres válidos y publican un cilindro
por cada uno, más la esfera. La lista sale directamente del dato del agarre. Si
no hay agarres válidos, la lista está vacía. Nadie crea ni destruye objetos.

A favor:
- Respeta que las sondas solo muestran datos: la lista es un reflejo de los
  agarres, sin decisión propia.
- No agrega piezas nuevas.
- No hay ciclo de vida que gestionar: nada nace, nada se borra, ningún cilindro
  queda huérfano.
- Encaja con el laboratorio actual, donde la sonda de captura ya muestra o
  esconde sus volúmenes según haya candidata válida.

En contra:
- Exige que el agarre tenga una **identidad estable entre ticks**, para que el
  detector pueda comparar la posición anterior con la actual y hacer el barrido.
  Eso pasa a ser un requisito del evaluador.
- Hay que definir qué identidad usar (por ejemplo, el soporte más la altura del
  borde) y qué pasa si el agarre cambia de identidad entre dos ticks.

## Opción 4: una pieza aparte que gestiona los volúmenes

Un gestor dedicado a crear, actualizar y borrar los volúmenes de captura.

A favor:
- Una sola responsabilidad bien aislada.
- Deja a las sondas totalmente pasivas.

En contra:
- Es otra pieza más, con su nombre y su lugar en el orden de ejecución, para
  algo que la Opción 3 resuelve sin ella.
- Sigue necesitando la identidad estable del agarre.

## Comparación

| | 1: evaluador | 2: core | 3: sondas publican lista | 4: gestor aparte |
| --- | --- | --- | --- | --- |
| ¿Pieza nueva? | No | No | No | Sí |
| ¿Mezcla responsabilidades? | Sí (evaluar y producir) | Sí (decidir y fabricar) | No | No |
| ¿Hay ciclo de vida que gestionar? | Sí | Sí | No | Sí |
| ¿Respeta "sondas bobas"? | Sí | Sí | Sí | Sí |
| Riesgo principal | Evaluador con dos trabajos | Dependencia circular | Identidad estable del agarre | Una pieza más |

## Requisito común a todas las opciones

Para que el detector de contacto haga su barrido entre ticks, un agarre debe
tener una **identidad estable de un tick al siguiente**. Hoy el laboratorio
identifica el soporte con el `instance_id` del collider de pared, que no
distingue entre varios agarres de una misma pared (por ejemplo, listones). Hay
que definir una identidad que sí los distinga.

## Preguntas para la consulta

1. ¿Una lista de datos que cambia cada tick cuenta como "sondas bobas" o es
   procesar?
2. ¿Quién debe garantizar la identidad estable del agarre entre ticks?
3. ¿Qué identidad distingue a dos agarres de una misma pared?
4. Si un agarre cambia de identidad entre dos ticks, ¿se descarta el barrido de
   ese tick o se busca la correspondencia?
