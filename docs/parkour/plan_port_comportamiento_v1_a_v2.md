# Propuesta para Claude — Porteo de comportamiento V1 al sistema V2

## 1. Encargo

Portar al Parkour V2 el **comportamiento y la sensación esenciales** del Parkour V1, conservando la arquitectura de V2 como base de producción.

No es un pedido de copiar scripts, constantes o accidentes del V1 de manera literal. Tampoco es un pedido de detener el desarrollo hasta completar una campaña forense total. El mapa forense existente se usa como fuente técnica cuando haga falta entender una conducta; el resultado de cada fase debe ser una mejora jugable y verificable en V2.

Referencias:

- V1 histórico/oráculo: `860a999f2c5ada8fc01ab74179a3442f887883d3` (`bd38e49^`).
- Mapa técnico V1: `docs/parkour/v1_forensic_technical_map.md`.
- V2 actual: arquitectura de `PlayerMotor`, `TraversalDetector`, `TraversalResolver`, `TraversalController` y contratos tipados.

## 2. Principios no negociables

1. **V1 define el efecto; V2 define la implementación.** No se trasplantan scripts V1 ni se degrada V2 a `Dictionary`, ownership ambiguo o transformaciones sin contrato.
2. **Input expresa intención; contexto determina posibilidad.** Caminar cerca de una caja no activa mantle ni hanging. El espacio/intención sólo habilita una acción si probes, geometría, movimiento y estado la hacen válida.
3. **Bordes normales se resuelven por probes.** Cubos, paredes, bordes y cornisas normales no reciben `Marker3D` ni `TraversalSegment(LEDGE)` como muleta.
4. **Markers/segmentos sólo para geometría que los requiere.** Escaleras verticales y objetos finos/especializados —cable, cuerda, cornisa demasiado delgada para probes normales— pueden aportar datos authored.
5. **No copiar accidentes sin entender su efecto.** Por ejemplo, V1 ejecuta traversal dos veces por tick durante estados activos. Si eso aporta respuesta perceptible, V2 expresa el efecto con una regla temporal explícita y testeable; no duplica callbacks accidentalmente.
6. **La sensación se valida temprano.** Cada fase termina en una porción jugable del playground y requiere playtest humano antes de ampliar alcance.
7. **Los cambios son incrementales y reversibles.** No hacer una reescritura total del traversal ni mezclar varias mecánicas en una única entrega.

## 3. Contrato de compatibilidad buscado

Al finalizar, V2 debe recuperar estas propiedades perceptibles de V1:

- locomoción rápida y responsiva, sin inercia aceitosa;
- control aéreo permisivo y útil;
- entrada a hanging contextual desde salto o caída, nunca por simple proximidad estando en suelo;
- snap prácticamente inmediato, sin una animación que rompa el encadenado;
- cámara libre durante hanging, dentro del límite de cámara acordado para V2;
- shimmy sobre geometría normal, extremos y esquinas, sin datos authored en superficies comunes;
- mantle contextual desde hanging e intención de salto, con superficie superior y espacio de cuerpo validados;
- bloques bajos que se resuelven con salto normal, no con un agarre artificial;
- escaleras contextuales y encadenables, usando markers sólo como dato especializado;
- salidas y anti-reenganche que no conviertan el sistema en lento, tosco o pegajoso.

El contrato no obliga a heredar fallos de seguridad o colisión del V1. Si V1 atraviesa una plataforma al hacer mantle o llega a una posición geométricamente inválida, V2 puede resolverlo de forma segura siempre que conserve el propósito y la respuesta percibida.

## 4. Mapa de responsabilidades: V1 hacia V2

| Conducta histórica V1 | Responsabilidad V2 | Regla |
|---|---|---|
| Probes de borde y cálculo de candidato | `TraversalDetector` | Consultas físicas y candidatos tipados; sin iniciar estados. |
| Reglas de admisión, intención y prioridad | `TraversalResolver` | Decide qué acción es válida entre candidatos existentes. |
| Snap, hanging, shimmy, mantle, escalera y salidas | `TraversalController` | Único dueño del estado activo y de la transición espacial. |
| Gravedad, carrera, salto y control aéreo | `PlayerMotor` | Autoridad de locomoción base, suspendida/cedida mediante contrato explícito. |
| Candidato de borde | Contratos tipados | Ningún `Dictionary` como interfaz de traversal. |
| Datos de escalera | Segmento/datos especializados | Permitidos sólo para escalera/objeto fino que no admite solución por probes. |
| Debug V1 improvisado | Debug V2 observador | Visualiza probes, candidato, estado y motivo de rechazo; no decide gameplay. |

## 5. Plan de ejecución

### Fase A — Alinear contrato y preparar el vertical slice

**Objetivo:** dejar V2 listo para implementar una sola cadena completa de borde, sin activar mantle directo ni meter sistemas nuevos ajenos.

Tareas:

1. Revisar el mapa forense sólo en las secciones de locomoción, probes de borde, snap, hanging, cámara y salidas.
2. Identificar qué partes actuales de V2 bloquean el flujo contextual o dependen de `TraversalSegment(LEDGE)` para un borde normal.
3. Congelar Direct Mantle actual como experimento fuera de este flujo: no borrarlo ni extenderlo; impedir que participe en el vertical slice.
4. Crear/ajustar una zona pequeña de prueba V2 con suelo, un borde normal, una variación de altura y techo opcional. No usar markers ni segmentos de ledge.
5. Definir los criterios de aceptación de la Fase B antes de implementar.

**No hacer:** diseñar perfiles P0–P6 completos, modificar valores de producción de forma masiva, implementar escalera o mantle, ni escribir un sistema predictivo de pesos.

**Salida:** un plan técnico corto para el flujo de borde V2, con archivos previstos, invariantes preservadas y riesgos. No código de mecánicas todavía si el flujo no está claro.

### Fase B — Vertical slice: entrada, snap, hanging y salida

**Objetivo:** conseguir el circuito mínimo jugable:

`salto o caída → probes → candidato válido → resolver → snap breve → hanging → saltar o soltar`

Tareas:

1. Recuperar en `TraversalDetector` los probes contextuales necesarios para un borde normal, tomando V1 como referencia conductual, no como código para copiar.
2. Emitir un candidato tipado que contenga toda la información que requieren resolver y controller: normal, punto de borde, clearance, contexto de movimiento/estado y motivo de validez/rechazo.
3. Hacer que `TraversalResolver` admita hanging sólo bajo contexto válido: nunca por caminar frente a una caja desde suelo.
4. Ejecutar el snap y hanging desde `TraversalController` con ownership de movimiento inequívoco y una transición temporal explícita.
5. Mantener cámara del jugador bajo el control normal de input; aplicar sólo el límite V2 acordado, sin forzar `look_at`, bloquear yaw ni crear vibración al llegar al tope.
6. Implementar salidas mínimas: salto y soltar, con una protección contra reenganche que no bloquee encadenados legítimos.
7. Exponer debug útil: probes relevantes, candidato aceptado/rechazado, estado, motivo de rechazo y temporizador de protección.
8. Añadir tests para contratos/decisión y una prueba de integración de transición básica; el playtest humano valida la sensación final.

**Criterios de aceptación:**

- Desde suelo, caminar hacia la caja no genera hanging ni mantle.
- Desde salto/caída con un borde alcanzable, el player puede engancharse de forma consistente.
- El snap se percibe breve/directo, no como animación lenta.
- Cámara responde sin bloqueo ni temblor inducido por traversal.
- Salto y soltar devuelven la autoridad al motor sin estado colgado.
- No hay marker ni segmento authored para el borde normal.

**Salida:** build jugable V2 para playtest humano. No se inicia la siguiente fase sin feedback explícito sobre sensación.

### Fase C — Shimmy contextual y esquinas

**Objetivo:** recuperar la libertad lateral del V1 sin obligar a authoring de cada borde.

Tareas:

1. Usar probes durante hanging para confirmar continuidad lateral del borde y superficie de apoyo; no asumir una ruta preescrita.
2. Resolver finales físicos y esquinas mediante datos de geometría (normales, continuidad y clearance).
3. Hacer explícita y dependiente de `delta` la velocidad/suavizado temporal de shimmy.
4. Validar bordes rectos, extremos y esquinas de 90° en ambos sentidos.
5. Mantener el borde común libre de markers/segmentos.

**Criterios de aceptación:**

- Shimmy funciona sobre geometría común continua.
- El player no atraviesa/teletransporta en una esquina ni queda bloqueado sin motivo claro.
- Los extremos se comportan de forma previsible.
- El desplazamiento es estable con el tick de física definido.

**Salida:** playground jugable de bordes rectos y esquinas, listo para playtest.

### Fase D — Mantle contextual y seguro

**Objetivo:** permitir subir desde hanging sólo cuando el contexto físico y la intención lo justifican.

Tareas:

1. Resolver mantle desde hanging + intención de salto; no desde FREE por proximidad.
2. Validar superficie superior, clearance del cuerpo y destino de aterrizaje antes de iniciar transición.
3. Distinguir bloque bajo para salto normal de borde que requiere hanging + mantle.
4. Ejecutar una transición rápida, sin animación obligatoria que introduzca latencia perceptible.
5. Rechazar con motivo visible techo bajo, plataforma corta, destino ocupado o geometría inválida.
6. Dejar Direct Mantle como experimento aislado y fuera de la ruta de producción mientras se compara con este flujo.

**Criterios de aceptación:**

- Caminar junto a una caja jamás provoca mantle/hanging.
- El mantle sólo parte de contexto válido de hanging y salto.
- El player termina sobre una superficie válida, sin clipping ni caída inesperada.
- Un obstáculo bajo admite salto normal sin captura artificial.

**Salida:** casos de mantle y rechazo visibles en playground; playtest humano obligatorio.

### Fase E — Escaleras especializadas y encadenadas

**Objetivo:** integrar escaleras sin contaminar la solución contextual de bordes normales.

Tareas:

1. Conservar markers/segmentos como contrato especializado de escalera.
2. Exigir contexto de caída y la intención definida; estar parado frente a la escalera no debe activarla.
3. Implementar entrada, subida, bajada, salto/salida y protección contra reenganche.
4. Resolver encadenamiento de segmentos cercanos sin sensación de dos escaleras pegadas.
5. Definir prioridad explícita si coinciden un candidato de borde y uno de escalera.

**Criterios de aceptación:**

- Escalera no se activa por proximidad desde suelo.
- La entrada desde caída es intencional y consistente.
- Segmentos continuos se sienten como una sola escalera.
- Salidas no dejan estados, leases ni candidato residual.

**Salida:** escalera funcional en playground y test de transición/prioridad.

### Fase F — Afinado y regresión integrados

**Objetivo:** recuperar la sensación total sin perder reglas ni arquitectura.

Orden de afinado:

1. Aceleración, frenado, carrera y control aéreo.
2. Ventanas de probes: alcance horizontal/vertical, clearance y score.
3. Snap, shimmy y salida: duración, velocidad y protección de reenganche.
4. Cámaras y límites acordados.
5. Combinaciones: salto → hanging → shimmy → mantle → caída → escalera.

Para cada ajuste: indicar comportamiento objetivo, variable tocada, caso de playground y resultado de playtest. No ajustar una constante solamente por intuición.

**Salida:** suite de tests de contratos/transiciones, debug operable, casos de playground y una lista corta de diferencias V1/V2 aceptadas deliberadamente.

## 6. Forma de trabajo y checkpoints

Cada fase se trabaja en este ciclo:

1. Claude propone el cambio técnico acotado y los tests que protegen la arquitectura.
2. Implementa sólo esa fase; no adelanta las siguientes.
3. Ejecuta los tests oficiales disponibles y comunica resultados, archivos modificados y cualquier limitación.
4. El usuario hace playtest humano en el playground y describe respuesta/sensación.
5. Se ajusta la misma fase hasta que su comportamiento sea aceptable; recién entonces se avanza.

Si aparece una conducta V1 desconocida que cambie una decisión de diseño, se consulta el mapa forense y se prepara un caso de reproducción pequeño. No se detiene el proyecto para documentar todo V1 de nuevo.

## 7. Límites de alcance

- No reescribir todo V2 en una sola rama/turno.
- No implementar pesos predictivos de intención; ese sistema fue una idea futura de V1, no comportamiento histórico probado.
- No habilitar Direct Mantle como solución de producción.
- No exigir `Marker3D` para bordes normales.
- No borrar cambios WIP preexistentes ni hacer commits sin instrucción explícita.
- No declarar una fase completa sólo porque los tests pasan: requiere el playtest humano correspondiente.

## 8. Pedido de respuesta a Claude antes de implementar

Antes de modificar código, responder a este documento con:

1. Evaluación de viabilidad por fase y dependencias reales en el V2 actual.
2. Riesgos técnicos concretos de la Fase B, con archivos/nodos involucrados.
3. Qué invariantes de arquitectura V2 deben protegerse con tests durante Fase B.
4. Propuesta acotada de implementación para Fase A y Fase B, separando hechos del repositorio de inferencias.
5. Cualquier contradicción entre este plan, el mapa forense y el V2 actual.

No implementar todavía. La primera respuesta debe ser un diseño técnico revisable.
