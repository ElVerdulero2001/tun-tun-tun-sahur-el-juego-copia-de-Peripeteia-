# Parkour V3 — idea base

## Propósito

V3 no continúa el código ni replica el modelo final de gameplay de Parkour V2. V1 se conserva como radiografía de comportamiento: sirve para saber qué debe sentirse y cuándo una acción es posible. V3 implementa esos resultados con una arquitectura nueva, modular y verificable.

V2 queda congelado como referencia de comparación; no se borra ni se sigue expandiendo por inercia. Sus mejoras arquitectónicas frente a V1 sí se conservan como aprendizaje: contratos tipados, separación de responsabilidades, autoridad física centralizada, detección sin efectos laterales, decisiones explícitas y debug observable. Lo que no se replica es el modelo de mecánicas que, tras implementarse, no produjo el comportamiento ni el flujo de trabajo buscados.

## Estructura general

El player tiene una base que no se puede apagar:

- movimiento físico, gravedad, colisión y postura;
- cámara e input mínimos;
- lectura del mundo mediante probes, shape casts y contactos;
- telemetría y debug;
- una regla de arbitraje para elegir una sola acción compatible por tick.

Sobre esa base viven los cores de parkour, por ejemplo Hanging, Ladder o Vault. Cada core tiene sus propios estados, reglas de entrada, movimientos y salidas. Un salto desde hanging no es el salto normal adaptado: es una acción propia del core Hanging.

## Qué se comparte y qué no

Los cores no comparten decisiones de gameplay ni se escriben el estado físico unos a otros. El core activo es quien define cómo se comporta el player durante su acción.

Sí comparten infraestructura: el motor físico, input, cámara base, consultas al mundo, telemetría y contratos para tomar y devolver el control del player. Si dos comportamientos son realmente idénticos salvo parámetros, se reutiliza una implementación configurable; no se duplica código sólo por pertenecer a cores distintos.

El motor físico es siempre el único escritor del `CharacterBody3D`: aplica la velocidad, la postura de colisión y `move_and_slide()` una sola vez por tick. Un core con control exclusivo decide la política de movimiento y solicita una pose, velocidad o desplazamiento guiado; nunca modifica el cuerpo por fuera del motor.

## Lectura del mundo y candidatos

Las consultas físicas producen un snapshot de mundo coherente para el tick: superficies, normales, bordes, clearance, suelo y otros datos observables. Los cores consumen esa información para proponer candidatos sin ejecutar movimiento todavía.

Ejemplo: Hanging combina evidencia de pared/borde y clearance vertical. Si falta una de esas condiciones, el candidato se rechaza con un motivo observable. Ajustar una regla no debe esconder ese motivo: la telemetría tiene que mostrar qué probe o condición falló.

Cuando varios cores son posibles a la vez, un árbitro pequeño y explícito elige una sola transición. No es un mega-orquestador: sólo evita que el orden accidental de scripts decida entre Hanging, Ladder o Vault.

La locomoción base es el fallback, no una candidata que haya que arbitrar cada tick. El árbitro decide únicamente si una candidata de parkour especial puede reemplazar ese fallback. La política debe ser estable: primero se descarta lo incompatible con la intención y el estado; después se aplica una prioridad explícita para los empates reales.

## Control y transiciones

La base posee el control por defecto. Un core puede pedir control exclusivo al comienzo de un tick; el árbitro y el motor lo conceden sólo si la candidata fue aceptada. Mientras el core está activo, la base no aplica locomoción normal, pero el motor sigue siendo quien ejecuta físicamente su comando.

Toda salida entrega al motor una condición inicial explícita: posición, velocidad y postura solicitada. Una eyección forzada —por daño, geometría destruida, pérdida de soporte o cancelación de seguridad— revoca el control y devuelve al player a una caída o estado seguro con un motivo registrado.

Como regla inicial, una transición entre cores pasa por la base: `Hanging → Base → Ladder`, por ejemplo. Hay al menos un tick de base entre ambos. Un handoff especial sólo se considera si un playtest demuestra que ese intervalo se percibe mal en una cadena concreta.

## Capacidades y telemetría

Cada core y sus submecánicas pueden pedirse activas o inactivas desde el editor. El estado efectivo respeta sus dependencias y nunca deja al player en un estado inseguro.

Apagar una mecánica bloquea su ejecución, no su observación. Por eso el debug puede decir: “borde válido; Hanging desactivado”, en vez de ocultar que el candidato existía.

Cada core mantiene siempre sus mínimos de seguridad: entrar de forma válida, sostener el estado y salir de él de manera segura. Las capacidades opcionales pueden incluir shimmy, mantle, salto especializado o interacción durante hanging. La cámara base nunca se apaga; sólo puede cambiar la política especial de cámara de un core.

La postura de colisión también sigue esta regla: un core la solicita, pero el motor central la valida y aplica. En cambio, caminar, correr, salto normal, control aéreo, crouch y un step-up simple pertenecen a la base. Una maniobra que requiere trayectoria guiada o control restringido —mantle, vault, hanging o ladder— pertenece a un core.

## Pruebas

V3 tendrá un playground técnico propio, separado de escenas de juego. Debe permitir probar geometría normal, límites y casos hostiles, con telemetría visible y toggles de capacidades. Se construye de manera gradual según la mecánica que se esté validando, no como un mapa enorme desde el primer día.

Cada core se valida contra un fixture de comportamiento: medidas de geometría, timing y velocidades obtenidas de V1 por observación o medición. Los tests protegen esas condiciones con tolerancias; el playtest humano decide si la respuesta conserva la sensación buscada. Los datos inciertos de V1 se miden antes de convertirlos en contrato.

## Regla guía

> Cores independientes para el comportamiento; infraestructura compartida para la verdad física, la lectura del mundo y el control seguro del player.
