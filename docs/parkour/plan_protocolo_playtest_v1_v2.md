# Plan de playtest controlado — Parkour V1 / V2

## 1. Propósito

Este plan transforma la comparación entre el Parkour V1 y el V2 en una investigación reproducible. No se busca decidir por memoria que el V1 «se sentía mejor», ni copiar valores de código de manera aislada: se busca observar, medir y conservar la evidencia necesaria para explicar cada diferencia relevante.

El V1 histórico fijado en `860a999f2c5ada8fc01ab74179a3442f887883d3` (`bd38e49^`) es el **oráculo conductual**. No se modifica. El V2 no se rediseña durante esta etapa; sólo se contrasta contra los casos ya definidos.

## 2. Preguntas que debe responder la campaña

Para cada mecánica, la campaña debe permitir responder:

1. ¿En qué contexto físico y estado del jugador puede ocurrir?
2. ¿Qué input expresa la intención del jugador?
3. ¿Qué probes, guards o reglas aparentes permiten o niegan el resultado?
4. ¿Cuál es el resultado observable y cuánto tarda?
5. ¿Cuán permisiva es la ventana real de geometría, velocidad y timing?
6. ¿El resultado se repite? Si no, ¿qué mínima variación lo altera?
7. ¿Cómo difiere el mismo caso en V2?

No se acepta como conclusión una frase genérica como «se siente mal» o «es instantáneo». Debe quedar asociada a un caso, una condición de inicio, inputs, resultado y evidencia.

## 3. Artefactos de trabajo

Se usan dos artefactos complementarios.

### 3.1 Registro tabular de datos crudos

Una fila representa **un intento individual**, no una conclusión. Puede ser `.xlsx`, Google Sheets o CSV; debe permitir filtrar, ordenar y agrupar repeticiones.

Columnas obligatorias:

| Columna | Contenido |
|---|---|
| `id_intento` | Identificador único, por ejemplo `V1-P2-SNAP-004`. |
| `versión` | `V1` o `V2`. |
| `bloque` | P0 a P6. |
| `mecánica` | Locomoción, detección, hanging, shimmy, mantle, escalera, etc. |
| `escenario` | Zona/escena y variante geométrica exacta. |
| `estado_inicial` | Suelo, salto, caída, running, hanging, escalera, etc. |
| `posición_y_orientación` | Spawn, dirección de mirada y referencia espacial suficiente para repetirlo. |
| `geometría` | Altura, distancia, ancho, ángulo, techo/obstáculo u otras variables relevantes. |
| `input` | Teclas sostenidas, pulsadas y orden temporal. |
| `resultado` | Estado/acción observable: no engancha, snap, hanging, mantle, caída, salida, etc. |
| `tiempo_o_frames` | Duración medible del evento, o `N/D` si no se pudo medir. |
| `repetición` | Número de intento dentro de la misma serie. |
| `resultado_repetible` | Sí, no o parcial. |
| `observación` | Descripción corta de lo que se vio/sintió, sin convertirla aún en teoría. |
| `evidencia` | Nombre/ruta de vídeo, captura, log o `sin evidencia externa`. |
| `notas` | Anomalías, dudas o variables no controladas. |

### 3.2 Protocolo y conclusiones en Markdown

Este documento, o uno derivado de él, define los casos antes de jugarlos y guarda las conclusiones después de cerrar una serie. Una conclusión debe estar vinculada a los IDs de intentos que la sustentan.

Cada caso de prueba debe contener:

- ID y objetivo.
- Hipótesis o incógnita que intenta resolver.
- Escenario mínimo y configuración geométrica.
- Estado inicial y secuencia exacta de inputs.
- Datos que se deben registrar.
- Criterio de cierre: qué resultado permite afirmar, negar o dejar pendiente la hipótesis.
- Referencia al dato/código V1 que motivó la prueba, cuando exista.

Al cerrar una serie, usar estos rótulos explícitos:

- **HECHO OBSERVADO:** resultado repetido y respaldado por intentos concretos.
- **MEDICIÓN:** valor de frames, tiempo, distancia, altura o velocidad con contexto.
- **INFERENCIA:** explicación probable que une código y observación; no es un hecho hasta verificarla.
- **DECISIÓN V2:** replicar, preservar, rediseñar o dejar pendiente.

## 4. Disciplina de prueba

1. Una serie prueba una sola hipótesis principal. No mezclar cambios de velocidad, altura, cámara y geometría sin anotarlo.
2. Repetir el mismo caso varias veces antes de concluir que es fiable o aleatorio.
3. Cambiar una variable por vez al buscar un límite: primero distancia, luego altura, luego velocidad, por ejemplo.
4. Registrar tanto los éxitos como los fallos; un fallo es información sobre una guarda o una ventana de tolerancia.
5. Si una observación depende del timing, grabar vídeo o registrar frames cuando sea posible.
6. No modificar valores de V2 para «hacer que pase» mientras el bloque V1 correspondiente siga abierto.
7. Las pruebas V2 se ejecutan con la misma geometría, spawn e inputs que el caso V1 que ya fue cerrado.

## 5. Secuencia de bloques

La comparación se realiza por capas. No se pasa a una capa dependiente si la anterior aún no tiene un contrato observable mínimo.

| Bloque | Alcance | Preguntas mínimas | Dependencia |
|---|---|---|---|
| **P0 — Locomoción** | Aceleración, frenado, salto, carrera, control aéreo, pendientes. | ¿Cómo gana/pierde velocidad? ¿Cuánto control hay en aire? ¿Cuál es el alcance real del salto? | Ninguna. |
| **P1 — Detección** | Probes de borde y admisión de candidato. | ¿Desde qué altura, distancia y estado aparece un candidato? ¿En suelo se detecta o se prohíbe? | P0. |
| **P2 — Snap y hanging** | Entrada, snap, pose, cámara, salto y soltar. | ¿Cuánto dura el snap? ¿Puede cancelarse? ¿Qué libertad conserva la cámara? | P0, P1. |
| **P3 — Shimmy y esquinas** | Movimiento lateral por bordes normales, extremos y cambios de cara. | ¿Qué borde puede recorrerse sin markers? ¿A qué velocidad? ¿Cómo responde en una esquina? | P2. |
| **P4 — Mantle** | Salida superior desde hanging. | ¿Qué contexto lo permite? ¿Dónde termina el cuerpo? ¿Qué pasa con techo bajo o geometría corta? | P2. |
| **P5 — Escaleras** | Entrada, pulsos, salida y continuidad entre escaleras. | ¿Qué condición de caída/intención activa la escalera? ¿Cómo se encadenan segmentos cercanos? | P0; datos especializados de escalera. |
| **P6 — Regresión combinada** | Transiciones y anti-reenganche. | ¿Qué ocurre al soltar, caer, encadenar y volver a encontrar un borde/escalera? | P0 a P5. |

## 6. Casos prioritarios de arranque

Estos son los primeros casos que cierran las incógnitas más importantes del mapa forense. Cada uno debe desdoblarse en variantes mínimas y repetirse.

### P0 — Locomoción

- Salida desde quieto, frenado desde carrera y cambio de dirección.
- Salto vertical, salto desde marcha y salto desde carrera.
- Corrección lateral en aire a velocidad baja y alta.
- Comportamiento al soltar la dirección en el aire.
- Movimiento y quietud sobre una pendiente conocida.

### P1 — Detección de borde

- Mismo borde desde suelo, salto vertical, salto en carrera y caída.
- Búsqueda progresiva del límite horizontal de enganche.
- Búsqueda progresiva del límite vertical de enganche.
- Variación de altura libre sobre el borde y presencia de techo detrás.
- Casos que deberían fallar: borde demasiado alto, demasiado bajo, sin clearance o abordado desde una dirección inválida.

### P2 — Snap y hanging

- Medir desde la detección/enganche hasta posición estable de hanging.
- Pulsar salto durante snap: confirmar cancelación, velocidad de salida y posibilidad de reenganche.
- Soltar desde hanging y medir cooldown/distancia de exclusión efectiva.
- Medir cámara: yaw, pitch, límites, temblor y si el traversal aplica una transformación propia.
- Probar salto arriba y atrás desde hanging.

### P3 — Shimmy y esquinas

- Shimmy en borde recto largo, en ambos sentidos.
- Llegada al final físico del borde.
- Esquina exterior e interior de 90° sin `Marker3D` ni `TraversalSegment` de ledge.
- Variar ancho, grosor y continuidad del borde.
- Medir desplazamiento por segundo mediante vídeo/frames cuando sea viable.

### P4 — Mantle

- Comparar un bloque bajo que debería resolverse con salto normal contra un borde que requiere hanging + mantle.
- Mantle con superficie superior amplia, corta y con techo bajo.
- Medir posición final y si el cuerpo interpenetra, cae o queda estable.
- Probar mantle desde entrada lenta, corrida y caída.

### P5 — Escaleras

- Aproximación desde suelo: confirmar que no se activa por simple proximidad.
- Aproximación durante caída con la intención requerida.
- Subida, bajada, salto/salida y crouch/salida.
- Dos escaleras cercanas: confirmar encadenamiento sin sensación de corte.
- Probar límites de `StartMarker`/`EndMarker`, como geometría especializada autorizada.

### P6 — Combinaciones y reenganche

- Soltar de hanging y volver a aproximarse al mismo borde a distintas distancias/tiempos.
- Salir de escalera y comprobar reacceso inmediato o bloqueado.
- Encadenar salto → hanging → shimmy → mantle → caída.
- Combinar bordes cercanos, esquinas y escaleras sin confundir el contexto.

## 7. Unión con el mapa forense

El mapa `docs/parkour/v1_forensic_technical_map.md` es la fuente de hipótesis de código. La campaña no debe asumir que todo número o conducta inferida del código equivale automáticamente a la sensación efectiva.

Prioridades explícitas para confirmar por playtest:

1. La doble ejecución de `TraversalController._physics_process` durante traversal: medir su efecto efectivo sobre snap, shimmy, timeout y escalera.
2. La permisividad real de las probes de borde frente a altura, distancia y clearance.
3. El efecto conjunto de control aéreo, aceleración y velocidad de carrera sobre el alcance práctico.
4. La ausencia de una animación de entrada visible y la libertad de cámara durante hanging.
5. El mantle de target fijo sin validación de colisión: resultado real ante techo bajo y plataformas cortas.
6. La tolerancia y continuidad de escaleras con markers, separada de los bordes normales sin markers.
7. Los dos mecanismos de anti-reenganche y su ventana observable.

## 8. Cierre de un bloque

Un bloque puede considerarse cerrado sólo cuando:

1. Los casos prioritarios se ejecutaron en V1 y sus datos crudos están registrados.
2. Las conclusiones indican qué es hecho observado, qué se midió y qué sigue siendo incógnita.
3. Cada diferencia relevante tiene el mismo caso preparado para V2.
4. La comparación V1/V2 identifica la capa probable responsable, sin proponer todavía una implementación.
5. Las decisiones de rediseño quedan separadas del resultado observado.

## 9. Resultado esperado antes de reescribir V2

Al terminar P0 a P6 debe existir una matriz de comportamientos V1/V2 que permita decidir, caso por caso:

- **Replicar:** el comportamiento V1 es esencial para la sensación buscada.
- **Preservar V2:** el comportamiento V2 es mejor o necesario por seguridad/arquitectura.
- **Rediseñar con evidencia:** ambos fallan o el objetivo cambió, pero ya se conoce el contrato que se desea conservar.
- **Pendiente:** faltan datos; no se usa la intuición para completar el hueco.

El objetivo final no es clonar accidentalmente los bugs del V1 ni defender la arquitectura del V2: es recuperar la respuesta y permisividad que importan, con reglas explícitas y verificables.
