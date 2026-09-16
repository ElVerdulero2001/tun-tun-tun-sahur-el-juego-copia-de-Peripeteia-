# V3 — Feedback sobre la propuesta inicial de detección de Hanging

Respuesta a `v3_hanging_deteccion_propuesta.md`. No modifica la propuesta —
son observaciones para que el autor decida antes de cerrarla.

## En general

El documento resuelve bien la discusión previa (`v3_hanging_deteccion_problema.md`
y su feedback): el conjunto de cuatro piezas es justo el recomendado —
agrega ShapeCast como única fuente nueva sobre lo que ya existía en V2, sin
tocar todavía búsqueda inversa ni contacto físico reciente. El alcance
excluido (sección final) coincide en las cinco cosas que quedarían fuera del
primer laboratorio.

## Lo que quedó bien resuelto

- **ShapeCast como evidencia, nunca como sustituto de un requisito duro**
  (líneas 89-90). Resuelve directamente la pregunta 2 del documento de
  detección tal como quedó planteada: ni bloquea una cornisa angosta ni dejsa
  pasar una columna sin coherencia geométrica de fondo.
- **"Fuentes compartidas del player"** es una aclaración nueva y útil que no
  se había discutido antes: Hanging no recibe datos ya filtrados por H0,
  consume las mismas fuentes crudas que H0. Evita una capa de indirección
  innecesaria y deja claro por qué la transferencia de gobierno no interrumpe
  cámara ni input.
- El conjunto de requisitos duros reusa lo que ya existe en el código de V2
  (`is_pose_clear`, tolerancia lateral pared/borde) en vez de reinventarlo.

## Lo que dejaría marcado antes de avanzar

### 1. Requisito duro 5 — "la intención compartida no es contradictoria con entrar al borde"

Esto es la respuesta a algo señalado en el feedback del *contrato de entrada*
(`v3_hanging_contrato_feedback.md`, pregunta 1): la ausencia de un gate duro
de intención de input. Que haya vuelto como requisito duro está bien, pero
tal como está escrito es demasiado vago para funcionar como gate real: "no
contradictoria" no dice qué input específico lo cumple o lo rompe.

Es exactamente el tipo de ambigüedad que en V1 producía enganche magnético a
escaleras por sola cercanía (`_on_ladder_candidate_found` sin guarda de
estado — ver memoria `parkour-v1-forensic-map`). Sin una definición mínima,
"no contradictoria" queda librado a cómo lo interprete quien implemente, y
se puede repetir el mismo bug.

**Sugerencia:** agregar una frase que ate esto a algo concreto, aunque sea
sin números todavía — por ejemplo, "el jugador no se está alejando
activamente de la pared" — para que el requisito sea verificable en vez de
puramente descriptivo.

### 2. Requisito duro 4 vs. componente 4 (validación de pose)

El requisito 4 ("el borde queda dentro del rango alcanzable de la pose") y
el requisito 6 ("la pose cabe sin penetración") suenan a dos chequeos
distintos, pero el documento no aclara si el 4 es un prefiltro barato antes
de invocar la validación física del 6, o si es redundante con ella.

Si es un prefiltro (tiene sentido: evita pedirle al motor una query cara —
`test_move` — para candidatos absurdamente lejanos), valdría una línea que
lo diga explícitamente. Si no se aclara, alguien podría implementarlos como
el mismo chequeo hecho dos veces.

## Conclusión

Ninguno de los dos puntos bloquea el documento — son huecos de definición,
no errores de enfoque. El de mayor peso es el primero: un requisito
etiquetado como "duro" necesita ser verificable, y "no contradictoria" todavía
no lo es.
