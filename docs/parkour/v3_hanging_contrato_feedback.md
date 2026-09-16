# V3 — Feedback sobre el contrato de entrada de Hanging (borrador)

Respuesta a `v3_hanging_contrato_borrador.md`. No modifica el contrato — son
observaciones para que el autor decida.

## En general

El documento mantiene la misma disciplina que ya se usó en V2: frontera clara
entre "publicar candidato" y "tomar control", explícitamente fuera de alcance
lo numérico, invariantes conceptuales antes que implementación.

## Lo que funciona bien

- **Requisito 5** (la pose no puede nacer ni atravesar geometría) es
  exactamente la garantía que ya se construyó para V2 con
  `is_pose_clear`/`test_move` (Fase 5, ver `parkour-v2-rework` en memoria) —
  se puede reusar sin inventar nada nuevo cuando llegue la implementación.
- La separación explícita Hanging/Mantle en el punto final ("no hay espacio
  para pararse arriba no invalida Hanging") evita repetir la confusión que
  hubo que resolver a mano en la Fase 5 de V2 entre "hang válido" y
  "aterrizaje válido".
- Que el candidato lleve "hechos y motivos que lo validaron o rechazaron" es
  coherente con cómo ya se diseñó `TraversalDebug` como observador pasivo —
  este contrato es debuggeable por construcción, no como un agregado
  posterior.

## Preguntas antes de cerrarlo

### 1. Ausencia de gate duro de intención de input

Los requisitos 1-5 no incluyen ningún gate de intención de input como
condición dura. Cámara/input solo entran "cuando sean relevantes para su
certeza" — es decir, un peso, no un filtro.

Esto es un cambio real respecto a V2: ahí el resolver exigía avance
específicamente frontal (`move_axis.y < 0`) como condición dura para
enganchar un borde, precisamente para que retroceder o strafear cerca de un
borde válido *no* enganche. Es la misma clase de bug que en V1 causaba
"entrada magnética" a escaleras por sola proximidad (ver
`parkour-v1-forensic-map` en memoria: `_on_ladder_candidate_found` sin
guarda de estado).

Si en V3 esto pasa a ser puramente un peso de certeza (arbitrado, no
filtrado), hay que asumir que el árbitro + el umbral mínimo de certeza son
suficientes para evitar el enganche no deseado al caer de espaldas cerca de
una pared.

**¿Es una decisión consciente de aflojar esa regla, o se escapó al escribir
el contrato?**

### 2. Comparabilidad de "certeza" entre cores distintos

No queda del todo claro qué significa "certeza" a nivel contrato cuando hay
más de un core en juego. Si Hanging calcula su certeza con su propia fórmula
(abierta, eso está bien) pero el árbitro va a comparar candidatos de
*distintos* cores entre sí, en algún momento esa certeza tiene que vivir en
una escala comparable entre cores.

No hace falta resolverlo en este documento, pero valdría una línea que diga
explícitamente que la comparabilidad entre certezas de distintos cores es
responsabilidad del árbitro (o de un contrato aparte), para que no quede
dado por sentado.

### 3. H0 en el diagrama (menor)

El diagrama pone `árbitro → H0 → Hanging`. Se entiende la intención (H0 es
la capa física común desde la que cualquier core gobernado asume control),
pero convendría una frase que ate esto explícitamente al H0 que ya se está
armando en el laboratorio de la rama `codex/parkour-v3-h0-lab` — así el doc
no queda ambiguo sobre si "H0" acá es un concepto nuevo o el mismo que ya
tiene código real.

## Conclusión

Nada de esto bloquea el documento — son huecos de decisión, no errores. Si
el punto 1 es intencional, se puede dejar igual; si no, conviene poner el
avance frontal (o al menos "input no contradictorio") como requisito duro
en vez de dejarlo todo en manos de la certeza.
