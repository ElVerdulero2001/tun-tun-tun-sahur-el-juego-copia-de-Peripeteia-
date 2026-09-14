# Auditoría final de consistencia: `PARKOUR_SYSTEM_ARCHITECTURE.md` transmutado vs. V3

## Propósito y alcance

Esta auditoría compara el estado **ya transmutado** de `PARKOUR_SYSTEM_ARCHITECTURE.md` (raíz del repo) contra la autoridad conceptual `docs/parkour/v3_autoridad_movimiento_propuesta.md`. Es la auditoría posterior a la transmutación, distinta de `v3_auditoria_parkour_system_architecture.md` (que auditó el documento heredado *antes* de transmutarse).

No reescribe ningún documento, no propone APIs, clases, fórmulas, nodos de Godot, implementación ni soluciones a preguntas abiertas. Sólo audita si el documento transmutado es compatible con V3.

`v3_autoridad_movimiento_propuesta.md` tiene prioridad; sus decisiones explícitas prevalecen. No se usa V1, V2 ni documentos de decisiones abiertas como autoridad.

## Tipos de hallazgo

- **Contradicción real.**
- **Residuo heredado incompatible.**
- **Decisión V3 omitida o deformada.**
- **Detalle técnico presentado indebidamente como decisión.**
- **Sin problema.**

## Tabla de hallazgos

| Sección del documento transmutado | Tipo de hallazgo | Evidencia concreta | Relación con V3 | Gravedad |
|---|---|---|---|---|
| "Depuración, telemetría y pruebas" — ítem "peso, signo y contribución de datos a la certeza contextual" (línea ~156) | Detalle técnico presentado indebidamente como decisión | El bullet ata "peso" y "signo" (vocabulario exclusivo de la sección de V3 marcada como "hipótesis... en exploración", que calcula un valor `X`, no `certeza`) directamente a "certeza contextual" (el concepto de la sección de V3 marcada como `Decisión:`, cuya fórmula interna V3 deja explícitamente abierta: "la escala concreta de pesos... y las fórmulas de X siguen abiertos") | Funde dos niveles que V3 mantiene separados a propósito: una hipótesis exploratoria sin fórmula fijada, y una decisión ya tomada (distribución de 100, umbral 90) cuyo mecanismo interno de cálculo V3 nunca especificó como "peso+signo". El propio documento transmutado afirma en su línea 5 que no define "fórmulas de certeza", pero este bullet presupone una | Alta |
| "Superficies y puntos de interés" (líneas 49-63) | Detalle técnico presentado indebidamente como decisión | Enumera hechos concretos como "borde superior e inferior", "longitud y continuidad del borde", "espacio libre frente... y detrás", "velocidad propia de la superficie si pertenece a un objeto dinámico" | V3 no define ninguna taxonomía de hechos geométricos; sólo fija que "la forma concreta de agrupar esos hechos... sigue abierta". Esta lista concreta fija contenido de alcance que V3 dejó sin resolver, aunque se presente como "hecho neutral" y no como API | Media |
| Ausencia de sección equivalente a "Decisión: bloqueo de voluntad antes de los cores" (V3 líneas 138-143) | Decisión V3 omitida o deformada | No hay ninguna mención a desactivación de captura de input ni a que la muerte del player pase a ragdoll fuera del sistema de cores, en ningún punto del documento transmutado | Es una sección con encabezado `Decisión:` explícito en V3, no una idea abierta; el documento transmutado no la conserva ni la contradice, simplemente no aparece | Media |
| Ausencia de sección equivalente a "Decisión: señales externas con dos efectos" (V3 líneas 189-196) | Decisión V3 omitida o deformada | No hay mención a "interrupción obligatoria" vs "modificador temporal" para señales externas al parkour, en ningún punto del documento transmutado | Es otra sección con encabezado `Decisión:` explícito en V3, ausente por completo del texto transmutado | Media |
| Ausencia de la distinción de "submecánica" del Vocabulario V3 (línea 27: puede desactivarse para gameplay pero sigue evaluándose para diagnóstico) | Decisión V3 omitida o deformada | El documento transmutado no distingue "core" de "submecánica" en ningún punto | Detalle menor de vocabulario explícitamente fijado en V3, no reproducido | Baja |
| Resto del documento (flujo H0↔core, gatillo por certeza 90/100, `crouch` como exclusión previa, frontera H0 obligatoria, ejecución reactiva por tick, soportes metaestables incluidas plataformas móviles, cámara/input compartidos, Resources/red/guardado/Godot estacionados) | Sin problema | Coincide en contenido con las secciones `Decisión:` de V3, sólo con redacción propia o reordenada | Compatible, sin residuo heredado ni sobre-especificación | — |

## Veredicto

1. **¿Puede ya funcionar como arquitectura V3 de referencia?** No todavía sin ajuste: el resto del documento sí es fiel a V3, pero el hallazgo de "peso/signo → certeza contextual" introduce una premisa de cálculo que V3 nunca decidió y que el propio documento dice no estar decidiendo. Usar el documento tal cual para diseñar H0 arrastraría esa premisa como si fuera un hecho arquitectónico fijado.

2. **¿Hay conflicto a resolver antes de H0?** Sí, uno: el hallazgo de "peso/signo/certeza contextual". Es el único que toca directamente el mecanismo de gatillo que H0 necesita respetar (cuándo cede gobierno). Las dos omisiones de decisiones (bloqueo de voluntad/ragdoll, señales externas) no afectan el diseño interno de H0 en sí, pero sí a la completitud del documento como referencia.

3. **¿Qué queda correctamente estacionado?** Todo lo técnico de Godot (`CharacterBody3D`, raycasts, colisión), red/determinismo/guardado, formato de handoff/duración del paso por H0, autoría de datos (Resources/tags), técnica de anclas/momentum para plataformas móviles, tolerancias/asistencias como capa global, y la API concreta de providers — todos declarados explícitamente abiertos, en línea con V3.
