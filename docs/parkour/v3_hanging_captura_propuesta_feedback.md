# V3 — Feedback sobre la propuesta de captura de entrada a Hanging

Respuesta a `v3_hanging_captura_propuesta.md`. No modifica la propuesta —
son observaciones para que el autor decida antes de cerrarla.

## En general

El documento respeta bien la frontera que el contrato de Hanging
(`v3_hanging_contrato_borrador.md`) y la propuesta de detección
(`v3_hanging_deteccion_propuesta.md`) ya habían dejado abierta explícitamente:
"la forma del snap de entrada" y "la validación física que se haga durante
él". No se adelanta a decidir árbitro, snap visual, movimiento colgado ni
salidas — coincide con la sección "Fuera de alcance" del propio documento.

## Lo que quedó bien resuelto

- **Separar la pose `P` del punto crudo de borde** (líneas 42-45). Responde
  bien al riesgo obvio de medir contra el borde: agarrar cuando las manos
  están cerca pero el cuerpo todavía no encaja en la pose final.
- **Entrada por cruce de segmento, no solo distancia en el tick** (líneas
  65-82). A velocidad alta un body puede cruzar la esfera entre dos frames
  sin que ningún tick lo encuentre adentro — el mismo tipo de razonamiento
  swept que ya usa el resto del sistema (`move_and_collide`/`test_move` en
  vez de comparar posiciones puntuales).
- **Revalidar `P` justo antes del snap** (condición 5, líneas 61-63) reusa
  exactamente el patrón que Fase 5 de Parkour V2 ya aplicó para el bloqueo de
  mantle: revalidar en el instante en vez de confiar en la validación de
  entrada, porque el candidato puede haber cambiado desde el tick en que se
  detectó. Buena señal de consistencia arquitectónica con lo ya construido,
  no es una regla nueva inventada para este caso.
- **Cámara excluida de decidir distancia o pose de captura** (líneas
  100-108) es coherente con la regla ya fijada en la propuesta de detección:
  la cámara aporta certeza/intención, no gobierna la física de la captura.

## Lo que dejaría marcado antes de avanzar

### 1. Dueño y ciclo de vida de la "posición de referencia anterior" de la cápsula

La condición B (líneas 76-78) exige comparar la posición actual contra la
posición de referencia del tick anterior. Eso es estado que persiste entre
ticks, y el documento no dice quién lo guarda ni cuándo se resetea.

Falta específicamente: **¿qué pasa si el candidato ganador cambia de
identidad de un tick a otro** (el jugador estaba cerca del borde A y en el
siguiente tick el borde B pasa a ser el candidato válido)? Si la posición
anterior no se resetea al cambiar de candidato, un cruce podría terminar
midiéndose contra la esfera de un candidato distinto del que la generó.

Es el mismo tipo de ambigüedad de "dueño del estado" que ya costó una ronda
de revisión completa en Fase 4/5 de Parkour V2 (lease, `last_safe_pose`,
progreso de segmento) — ver memoria `parkour-v2-rework`. No bloquea el
documento, pero conviene resolverlo en texto antes de implementar el
laboratorio, no descubrirlo por un bug de reenganche cruzado.

**Sugerencia:** una frase que fije que la posición de referencia anterior es
propia de un candidato/pose activo, y que un cambio de candidato reinicia el
rastreo (equivalente a no tener aún una posición anterior válida ese tick).

### 2. "El body está del lado libre de la pared" no tiene ni una definición conceptual

La condición 2 (líneas 54-56) dice que la normal de pared del candidato
"define cuál es el lado externo", pero no dice ni a nivel de idea cómo se
deriva esa pertenencia (por ejemplo, signo del producto punto entre la
normal de pared y el vector cuerpo→pared). El resto del documento es
cuidadoso en dejar fuera los números pero igual anclar el concepto (como
hace con la esfera o con el cruce de segmento); acá el concepto mismo queda
implícito.

**Sugerencia:** una línea que diga en qué se apoya el chequeo de lado
(aunque sea "signo de un producto punto contra la normal de pared, sin fijar
tolerancia todavía"), para que no quede a criterio de quien implemente.

## Conclusión

Ninguno de los dos puntos bloquea el documento — son huecos de definición,
no errores de enfoque. El de mayor peso es el primero: es estado que vive
entre ticks y necesita una regla explícita de reset, o puede reproducir
exactamente el tipo de bug de enganche cruzado que el proyecto ya encontró y
corrigió en fases anteriores.
