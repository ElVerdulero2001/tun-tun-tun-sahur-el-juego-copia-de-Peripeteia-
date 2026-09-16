# V3 — Feedback sobre la detección compuesta de Hanging

Respuesta a `v3_hanging_deteccion_problema.md`. No decide nada — son
observaciones para que el autor resuelva las preguntas abiertas del
documento.

## En general

La división "hechos que hacen imposible el agarre" vs "evidencia que lo hace
más o menos probable" es la forma correcta de encarar esto. No es una idea
nueva a validar desde cero: ya existe un precedente exacto en el propio
código de V2. `landing_libre` en `_sondear_borde_en`
(`traversal_detector.gd:148-154`) se calcula y se guarda como **dato**, no
como gate — un candidato de HANGING no se descarta por falta de espacio
arriba; eso lo interpreta después quien evalúa mantle directo. Vale la pena
citar esto en el documento como el antecedente arquitectónico, en vez de
presentar la distinción como algo a inventar.

## Requisitos duros: qué incluiría y qué no

De la lista de "requisitos duros posibles" (sección homónima), dejaría como
duros sin negociación:

- **Pose física libre.** No es una preferencia, es imposibilidad física. Ya
  existe como `is_pose_clear`/`test_move` (`traversal_detector.gd:82-83`,
  Fase 5). No hace falta inventar nada, solo reusarlo.
- **Coherencia lateral pared/borde.** Ya está implementado como gate
  (`borde_tolerancia_lateral`, `traversal_detector.gd:134-137`): si el borde
  encontrado no está sobre la misma pared, no es un candidato, es ruido.
  Dejarlo duro tal cual está.
- **En aire.** Ya está, sin cambios.

El resto de la lista de "evidencia de certeza posible" la dejaría tal cual
está propuesta, con una excepción a marcar explícitamente:

- **Contacto físico reciente** lo bajaría a evidencia siempre, sin
  excepciones por ahora. La única situación donde podría justificarse como
  requisito duro es un re-grab/shimmy de continuación (viniendo ya de un
  segmento conocido), pero es un caso tan específico que no lo metería en el
  contrato general de Hanging — sería una regla local del resolver para ese
  escenario puntual, no parte de los requisitos duros de entrada.

## Pregunta 2 del doc: ShapeCast como bloqueante

El ejemplo de la columna que da el propio documento (línea 50) apunta, para
mí, a la conclusión contraria a la que insinúa: si un volumen frontal toca
una columna pero no hay borde coherente por rayos, el gate que ya lo
rechaza es la **coherencia lateral**, no el ShapeCast. Si el ShapeCast fuera
bloqueante, el primer caso que rompe es el propio ejemplo de la cornisa
angosta (línea 45): rayos precisos la ven, un volumen frontal amplio no la
toca, y quedaría rechazada aunque sea utilizable.

Recomendación: ShapeCast como evidencia pura, nunca como gate. Y como
primera fuente nueva a sumar en el laboratorio inicial, precisamente porque
es barata y apunta directo al falso positivo que preocupa al documento
(columnas, decoración), sin arriesgar el falso negativo de la cornisa.

## Pregunta 3 del doc: qué desacuerdo es "geometría incoherente"

La tolerancia lateral actual ya funciona como el gate duro de coherencia y
la dejaría así. No agregaría un segundo gate duro de "acuerdo entre pared,
tapa y volumen" — en vez de eso, el grado de acuerdo/desacuerdo entre
fuentes adicionales (ShapeCast, búsqueda inversa) debería modular la
certeza de forma continua, no binaria. Un desacuerdo grande baja mucho la
certeza; no hace falta un umbral duro nuevo mientras la tolerancia lateral
ya cubra los casos físicamente imposibles.

## Pregunta 1 del doc: alcance del primer laboratorio

No construiría todas las fuentes candidatas a la vez. Con lo que ya existe
(grilla de rayos + rayo descendente + coherencia lateral, todo en
`traversal_detector.gd`) más `is_pose_clear` como segundo gate duro, ya hay
una base de dos requisitos duros probada. Sumaría **una sola** fuente nueva
de evidencia para el primer laboratorio — ShapeCast frontal, por lo dicho
arriba — antes de tocar búsqueda inversa desde tapa o contacto físico
reciente. Así se prueba el mecanismo de agregación de certeza del resolver
con una sola variable nueva, no con cuatro a la vez.

## Pregunta 5 del doc: debug

Ya existe `TraversalDebug` como observador pasivo (Fase 7 de V2). Lo
extendería para listar, por fuente: nombre, si es duro o evidencia,
resultado (pass/fail, o peso aportado si es evidencia), y si fue un gate
duro el que rechazó el candidato, cuál exactamente. Es coherente con cómo
ya se expone `landing_libre` como dato explicable en vez de un booleano de
aceptación ciego.

## Conclusión

Nada de esto bloquea el documento — son respuestas concretas a las
preguntas que el propio autor dejó abiertas, no objeciones al enfoque
general. El punto con más peso es la pregunta 2: ShapeCast debería quedar
excluido de la lista de candidatos a requisito duro directamente, no solo
"a discutir".
