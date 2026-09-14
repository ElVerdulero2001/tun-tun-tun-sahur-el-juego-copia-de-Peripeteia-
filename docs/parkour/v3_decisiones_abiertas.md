# Parkour V3 — decisiones abiertas

## Regla de este documento

Este es un inventario de preguntas de diseño. No autoriza implementación ni supone respuestas. Una pregunta sólo se cierra cuando la decisión queda escrita, su alcance queda claro y se conocen sus efectos sobre los demás módulos.

## 1. Player Base y autoridad física

1. ¿Cuál es exactamente la API con la que un módulo pide movimiento guiado al motor?
2. ¿Qué operaciones físicas conserva siempre el motor y cuáles puede solicitar un módulo activo?
3. ¿Cómo se solicita, concede, renueva y devuelve el control exclusivo de un módulo?
4. ¿Qué ocurre ante eyección forzada: daño, borde destruido, pérdida de soporte, bloqueo físico, pausa o cutscene?
5. ¿Qué posición, velocidad y postura recibe Player Base cuando una acción termina?
6. ¿Se impone un tick de Player Base entre dos módulos, o existen handoffs excepcionales? Si existen, ¿qué información pueden transportar?
7. ¿Cómo se solicita y valida una postura/collider especial sin que un módulo escriba el `CharacterBody3D` directamente?

## 2. Tick, input y lectura del mundo

1. ¿En qué orden exacto se construyen input, snapshot físico, candidatos, decisión, comando de movimiento y telemetría?
2. ¿Existe un único `InputSnapshot` por tick? ¿Qué distingue tecla sostenida, flanco, buffer y consumo de una intención?
3. ¿Qué datos contiene el `WorldSnapshot` común y cuáles consulta cada módulo bajo demanda?
4. ¿Cómo se evita que dos módulos saquen conclusiones sobre fotos distintas del mundo durante el mismo tick?
5. ¿Qué consultas se hacen siempre, cuáles se activan por contexto y cuáles sólo aparecen con debug?
6. ¿La observación de un módulo apagado se calcula siempre, sólo si el contexto es plausible o sólo bajo un toggle de debug?
7. ¿Cómo se expresan candidatos inválidos y sus motivos de rechazo sin ejecutar gameplay?

## 3. Árbitro y conflictos

1. ¿Qué acciones llegan al árbitro: sólo entradas a módulos especiales o también acciones de locomoción base?
2. ¿Qué condiciones mínimas debe cumplir una candidata antes de competir?
3. ¿Cómo se ponderan intención explícita, estado actual, seguridad física y prioridad de diseño?
4. ¿Cuál es el desempate estable entre Hanging, Ladder, Vault u otros módulos posibles a la vez?
5. ¿Qué acciones activas son interrumpibles y por qué causas?
6. ¿Cómo se impide que un candidato nuevo interrumpa accidentalmente una acción ya comprometida?

## 4. Módulos, submecánicas y capacidades

1. ¿Qué significa exactamente “módulo/core” en V3 y qué nombre se usará de forma consistente?
2. ¿Qué comportamientos pertenecen a Player Base y cuáles son módulos de parkour?
3. ¿Cuáles serán los primeros módulos de V3 y cuál es su dependencia entre sí?
4. ¿Mantle es una submecánica de Hanging, un módulo propio o una capacidad de Vault/Climb?
5. ¿Qué forma parte de Hanging: entrada, sostén, soltar, salto, shimmy, esquinas, mantle e interacción?
6. ¿Qué forma parte de Ladder: entrada, subida, bajada, salida, salto y encadenamiento?
7. ¿Qué capacidades de cada módulo son obligatorias para que sea seguro y cuáles pueden apagarse?
8. ¿Qué sucede al apagar una capacidad mientras el player ya está usándola?
9. ¿Cómo se representan estado pedido, estado efectivo, dependencias, overrides y motivos de desactivación?

## 5. Geometría y contratos de nivel

1. ¿Qué geometría común debe resolverse exclusivamente por probes?
2. ¿Qué estructuras especializadas pueden requerir datos authored, markers o componentes de nivel?
3. ¿Qué tags de nivel, capas de colisión y filtros de material existen para permitir, negar o modificar parkour?
4. ¿Qué requisitos geométricos mínimos necesita cada módulo: altura, profundidad, normal, continuidad y clearance?
5. ¿Cómo se comportan bordes finitos, esquinas, rampas, techos bajos, superficies móviles y geometría dinámica?

## 6. Movimiento, cámara e interacción

1. ¿Qué perfiles de movimiento puede pedir un módulo: sostener pose, velocidad objetivo, trayectoria guiada o caída controlada?
2. ¿Cómo se valida un desplazamiento guiado completo y qué fallback se usa si algo cambia a mitad de camino?
3. ¿Qué conserva el jugador de la locomoción base dentro de cada módulo: cámara, input lateral, gravedad, momentum y salto?
4. ¿Cuál es la política de cámara de cada módulo y cuáles son decisiones deliberadamente distintas de V1?
5. ¿Cómo pregunta el sistema de interacción si una acción está permitida durante Hanging, Ladder u otro módulo?
6. ¿Qué información contextual puede exponer un módulo a inventario, interacción, animación, cámara y VFX sin entregarles autoridad de gameplay?

## 7. Fidelidad V1, pruebas y medición

1. ¿Qué conductas de V1 son contratos a recuperar y cuáles son bugs o decisiones que V3 mejora deliberadamente?
2. ¿Qué valores deben medirse en V1 antes de convertirlos en fixtures: alturas, alcance, timing, velocidades, cooldowns y cámara?
3. ¿Qué tolerancias aceptan los tests y qué sólo puede cerrar el playtest humano?
4. ¿Qué casos mínimos debe tener el playground para cada módulo antes de implementarlo?
5. ¿Cómo se registra una diferencia V1/V3: hecho observado, medición, inferencia o decisión deliberada?
6. ¿Cuándo se considera cerrado un módulo y qué regresiones deben seguir protegiéndose?

## 8. Comparación, migración y alcance

1. ¿Cómo se mantiene V2 congelado y jugable como referencia sin contaminar V3?
2. ¿Qué parte de V1 se ejecuta o consulta como oráculo y cuál queda sólo como evidencia histórica?
3. ¿Qué escena o selector permite comparar variantes bajo la misma geometría cuando haga falta?
4. ¿Qué directorios, nombres y fronteras impiden que código de V3 dependa accidentalmente de PlayerV2?
5. ¿Qué se considera fuera de alcance del primer módulo para impedir que Claude adelante soluciones?

## Orden sugerido de cierre

Primero se cierran las secciones 1, 2 y 3: autoridad física, tick/input/snapshot y arbitraje. Con esas reglas, el resto se puede definir sin que un módulo invente su propia infraestructura. Después se decide el alcance del primer módulo, no al revés.
