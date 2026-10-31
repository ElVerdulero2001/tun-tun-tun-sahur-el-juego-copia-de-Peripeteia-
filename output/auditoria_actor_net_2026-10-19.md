# Segunda auditoría del laboratorio actor/net

Fecha: 19 de octubre de 2026. Versión local: `net-lab`, HEAD `b267dc9`. Comparación: auditoría del 12 de octubre, realizada sobre `97d23cc`.

**Veredicto: la implementación mejoró de forma comprobable. El diseño de estado, input y tick sigue siendo una buena base para este laboratorio, y varias debilidades anteriores tienen correcciones reales. Quedan tres problemas reproducidos de compatibilidad, validación y autoría de escaleras.**

El usuario aclaró que todavía no se hizo la integración al juego. El documento del proyecto agrupa en ese trabajo pendiente la extracción de la coordinación de `net_lab.gd`, los registros por mundo y el desacople de las pruebas respecto de la escena de laboratorio. Esta revisión los registra como deuda acordada para esa etapa. No propone realizar esa migración ahora.

## Alcance y Git

Se revisaron los 22 commits posteriores a `97d23cc`, los scripts y escenas actuales de `actor/net`, las pruebas permanentes y los diagnósticos pertinentes incluidos en la documentación. Entre las novedades están validación y huella de compatibilidad, poderes, postura encogida, esquinas, salto aéreo, cables, edición de escaleras y cables, y colgarse del compañero como de un cilindro.

Se consultó GitHub por su API durante la auditoría: la rama remota `net-lab` termina en `1dfb1e303e4d14a1c464595be40ba82005518f27`. El único commit local posterior es `b267dc9`, que divide una línea de ayuda para la notebook. La lógica auditada de movimiento y red ya está en GitHub.

La modificación preexistente de `project.godot` sigue siendo la etiqueta de características de 4.6 a 4.7. La auditoría no modificó implementación ni creó commits.

Rama remota: https://github.com/ElVerdulero2001/tun-tun-tun-sahur-el-juego-copia-de-Peripeteia-/tree/net-lab

## Qué quedó de los hallazgos anteriores

| Hallazgo del 12 de octubre | Estado comprobado el 19 de octubre |
| --- | --- |
| Adopción de velocidad de 1.000 m/s y temporizadores absurdos | Corregido para esas reproducciones: devuelve `BAD_VALUES` |
| Aceptar un `hooked_by` inventado | Corregido para un ID no autorizado; persiste una excepción demasiado amplia para el valor cero, detallada abajo |
| Quitar la cámara lenta personal desde una afirmación | La cámara lenta personal y `slow_left` fueron retirados por el cambio de diseño a una única cámara lenta del mundo; ese caso anterior dejó de aplicar |
| Ticks de input arbitrariamente futuros | Corregido con reloj conectado: los paquetes de la reproducción son descartados |
| Paquetes truncados o con demasiados registros | Se agregaron controles y pasaron las pruebas puntuales de recepción |
| Sin comprobación de copias compatibles | Se agregó y rechaza Tuning distinto; la cobertura de la huella sigue incompleta |
| `ActorBody.active_stance()` sin consumidores | Eliminada; no apareció otro método público sin referencias en el rastreo realizado |
| Registros globales, coordinación en el laboratorio y lectura de Tuning desde su escena | Pendientes dentro de la integración aplazada |

La solución a las bases con ID repetido es parcial: ahora avisa, pero mantiene el reemplazo de la base anterior. Las escaleras pasaron a IDs calculados por orden de ruta y los cables usan el mismo esquema. Ambos siguen siendo listas globales y su numeración cambia al agregar o retirar elementos anteriores. El código y la guía limitan explícitamente su uso actual a un nivel fijo; no se presentan aquí como soporte de objetos dinámicos.

## Problemas reproducidos

### 1. Prioridad media: la huella de compatibilidad omite datos que cambian la física

Archivos: `scripts/net/sim_fingerprint.gd:25`, `:55`, `:71`; llamada en `scenes/net_lab/net_lab.gd:422`; configuración física en `scenes/actor/actor.tscn`.

La comprobación reúne exports del Tuning, texto de scripts y parte del nivel. La escena del actor no entra en esa lista de scripts ni en el subárbol `Level`. El recorrido del nivel tampoco incluye propiedades nativas relevantes de los cuerpos, como sus capas de colisión.

Se reprodujo lo siguiente con el código actual:

- Cambiar `collision_layer` de un suelo de 1 a 2 deja exactamente la misma huella.
- Cambiar el radio de la cápsula del actor de 0,35 a 0,60 y su `safe_margin` deja la misma huella.
- Como controles positivos, cambiar el tamaño de la forma del suelo o `walk_speed` sí cambia la huella.

Con el `collision_mask=1` del actor, el primer cambio puede convertir un suelo visible en uno que el actor no detecta. El segundo cambia contactos y espacio libre. Por tanto, coincidir en la huella actual no alcanza para asegurar que ambas copias simulen lo mismo.

Esto se comprobó llamando al generador real antes y después de cambiar esos datos en una escena de prueba. No se ejecutó una pareja completa con escenas del actor distintas. Sí se ejecutó una pareja con Tuning diferente y se confirmó el rechazo correcto.

Corrección sugerida: incorporar los parámetros físicos efectivos del actor y las propiedades de colisión del nivel. Para exportaciones, generar una identidad de simulación al construir el proyecto: `code_text()` ya advierte que en builds sin fuentes `.gd` su parte puede quedar vacía. Esa limitación de exportación se obtuvo del código; no se probó una build exportada.

### 2. Prioridad media: se puede borrar `hooked_by` sin abandonar el modo que sostiene al compañero

Archivo: `scripts/net/claim_adoption.gd:115`.

La condición acepta que `claim.hooked_by` coincida con el host **o sea cero**, sin exigir en el segundo caso que el actor se haya soltado. El comentario describe permitir cero al abandonar el agarre, pero el código lo permite también permaneciendo en la misma escalera.

Reproducción: A está en modo `LADDER`, con `hooked_by=77`; B tiene el ID 77 y está en modo `HOOKED`, anclado a A. Una copia del estado de A que únicamente cambia `hooked_by` a cero devuelve `ADOPTED`. A sigue en `LADDER` y el host termina ese paso con el campo en cero.

Esto demuestra una validación incompleta del dato reservado al host. No demuestra por sí solo que el jugador pueda moverse indefinidamente con alguien colgado: `assign_hooks()` vuelve a calcular la relación al empezar el tick siguiente. El alcance comprobado es la aceptación y publicación temporal de un estado incoherente.

Corrección sugerida: limitar la excepción de cero a una salida válida del modo de sujeción y validar la coherencia con la relación entre actores. Mantener los eventos de época agregados en `3c3fab8`: son una mejora para la liberación provocada por el compañero y no sustituyen esta comprobación.

### 3. Prioridad media: escalar el nodo de una escalera desajusta dibujo y trepada

Archivo: `scripts/actor/ladder.gd:142`, `:152`, `:158`.

El dibujo hereda la escala de la escena. `height_for()` transforma los pies a coordenadas locales, mientras que `pose_at()` usa ejes globales normalizados y suma altura y separación sin aplicar la escala. Son dos interpretaciones distintas del mismo nodo.

Las funciones base ya tenían esta interpretación antes de los cambios de la semana; es un hallazgo adicional de esta revisión, no una regresión atribuida al nuevo editor de piezas.

Reproducción: con `height=2,5`, `standoff=0,45` y escala uniforme 2, el extremo autorado queda 5 m sobre el origen y a 0,90 m de separación. La pose lógica sigue a 2,5 m y 0,45 m: una diferencia de aproximadamente 2,54 m.

El caso funciona con escala 1. Para cambiar el tamaño del diseño actual se pueden usar `height` y `width`. El problema es que el editor permite escalar el nodo o sus padres y no hay una restricción que avise de esa incompatibilidad.

Corrección sugerida: elegir una unidad consistente para el parámetro de escalera y aplicar correctamente su transformación, o restringir explícitamente la escala a 1 con un aviso de configuración. La auditoría reprodujo la discordancia matemática; no recorrió en partida una escalera escalada.

## Dependencias, globales y código sin uso

No encontré addons de red, GDExtensions, paquetes externos o bibliotecas adicionales requeridos por estas carpetas. Se mantienen GDScript, clases del motor, Jolt y ENet. Los dos modelos `.glb` de peldaños y largueros son assets locales, con representación provisoria si no se usa un modelo.

Siguen los autoloads previos `UIHacking` y `DebugDraw` en el proyecto completo. No encontré referencias a ellos desde `actor/net`, y las verificaciones de esta auditoría se hicieron en una copia sin esos autoloads.

Hay estado global mutable en `BaseRegistry`, `Ladder`, `Cable` y `SimClock`. Declarar una clase con `class_name` no la convierte en singleton: lo relevante aquí son sus registros y campos `static`. El caché de consulta física de `ActorMotor` es distinto de esos registros de gameplay. La migración a contexto por mundo sigue pendiente y el sistema actual no satisface literalmente un requisito de ausencia total de estado global.

Se rastrearon por nombre de clase y ruta de recurso los 19 scripts de `scripts/actor` y `scripts/net`: todos tienen consumidores encontrados en scripts o escenas. No aparecieron scripts completos huérfanos ni métodos públicos sin referencias en esa búsqueda. Es una comprobación estática, no una prueba de alcance de todas las ramas. Los archivos históricos, assets y sistemas `player_v2` no se clasificaron como código muerto por quedar fuera del alcance.

El núcleo conserva sus ventajas: estado serializable por actor, input cuantizado, orden de tick explícito y separación reconocible del suavizado visual. Las mecánicas nuevas guardan en `ActorState` los datos relevantes de salto aéreo, encogimiento, esquinas y anclas. `ActorMotor` creció de unas 944 a 1.647 líneas y el coordinador del laboratorio también creció. Es un costo de mantenimiento a vigilar; el número de líneas por sí solo no prueba una arquitectura defectuosa ni obliga a una reescritura.

## Calidad y límites de las pruebas

Los dos tests permanentes siguen teniendo resultados explícitos. El recorrido de repetición comprueba igualdad de bytes, pero su cobertura se imprime y no exige mínimos de ticks por modo. Si un cambio del nivel evita una mecánica, puede seguir pasando sin probarla. La documentación reconoce esta limitación.

Varias comprobaciones nuevas están conservadas como scripts completos dentro del Markdown histórico, con rutas temporales. Son recuperables y útiles para reproducir, pero todavía no constituyen una suite mantenida con ejecución uniforme. El diagnóstico `diag_pista.gd`, por ejemplo, cuenta estaciones problemáticas y acaba siempre con `quit(0)`. Esta vez imprimió cero problemas; su código de salida por sí solo no detectaría una regresión.

La documentación también mantiene pendiente reparar las pruebas de empujones sobre compañeros que ya no alcanzan a colgarse. No se debe interpretar cero correcciones en un recorrido con cero agarres como validación de esa interacción. La prueba en red de esta auditoría sí registró 11 agarres reales al compañero en un cable.

## Verificación ejecutada

Copia mínima en `tmp/audit_actor_net_20261019`, con `.gdignore`, sin autoloads y con los scripts actuales copiados sin cambios. Se usó Godot 4.7.2 instalado, Jolt y renderizado compatible sin ventana. Los diagnósticos añadidos y los scripts extraídos se guardaron fuera de las carpetas que forman la huella de código.

| Comprobación | Resultado |
| --- | --- |
| Repetición a 60 ticks/s | Exit 0; 5.647 repeticiones y 252.337 ticks repetidos; misma simulación byte a byte |
| Repetición con ritmo variable de 57 a 72 | Exit 0; mismo resultado y huella `64564ccef7594dba` |
| Cobertura del recorrido | Suelo, aire, slide, escalera, Hanging, 29 ticks en cable, salto aéreo, encogimiento, súper y cámara lenta |
| Recepción de paquetes con peer ENet conectado | Conserva paquete válido y descarta futuro remoto, 7 registros, cabecera truncada, afirmación truncada y peer inexistente |
| Afirmaciones anteriores de 1.000 m/s, coyote de 10 s e ID de compañero inventado | Las tres devuelven `BAD_VALUES` |
| Pareja de procesos con `walk_speed` distinto | El host rechaza la entrada y el cliente informa la diferencia de Tuning |
| Diez estaciones del diagnóstico de compañeros recuperado del documento | Cero estaciones problemáticas; sin penetración ni cruce de los obstáculos comprobados |
| Host en cable y cliente colgándose; 200 ms, jitter de 40 ms y 5 % de pérdida agregados | Ambos exit 0; 11 agarres, 10 vueltas del recorrido, cero correcciones y ningún rechazo por datos imposibles en esa corrida |
| Barrido completo de 5.148 aproximaciones a bordes | Exit 0; 1.545/1.547 capturas buscadas, 0/330 agarres no buscados del criterio, cero ticks de penetración y salto visual máximo de 0,09 m en 50 ms; cumple los cuatro criterios |
| Pruebas de los tres hallazgos | Reproducidos en `audit_probes.log` |

El primer intento del barrido alcanzó el límite de 55 segundos sin resultado. Se repitió con un límite de 180 segundos y terminó por sí mismo con exit 0; el resultado de la tabla pertenece a esa ejecución completa. Los límites se aplicaron únicamente a los procesos creados para la auditoría.

Evidencia reproducible en la copia: `replay_60.log`, `replay_varying.log`, `hang_sweep_complete.log`, `hook_course.log`, `audit_probes.log`, `audit_packets.log`, `mismatch_pair_0.log`, `mismatch_pair_1.log`, `hook_cable_pair_0.log` y `hook_cable_pair_1.log`, junto con sus arneses. La prueba de pareja genera un resumen de comportamiento: exit 0 por sí solo no asegura que el escenario se haya ejercitado; se revisaron sus contadores.

Godot emitió un error de acceso al almacén de certificados del sistema en este entorno. La importación también informó que no podía guardar los ajustes globales del editor. Los resultados se capturaron dentro de la copia. No se repitieron pruebas en dos PC, builds exportadas ni otras plataformas, y los resultados no garantizan determinismo universal ni ausencia total de bugs.

**Orden sugerido:** completar la huella física y acotar la excepción de `hooked_by`; definir la política de escala de escaleras; convertir las comprobaciones nuevas en tests con condiciones de éxito y cobertura. La extracción del runtime y los registros por mundo conservan su lugar en la integración pendiente al juego.
