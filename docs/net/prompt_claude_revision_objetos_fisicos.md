# Revisión de objetos físicos: colisiones, agarre y movimiento en red

Implementá los cambios de este documento en `C:\Users\ElCaido97\Documents\tun-tun-tun-sahur`. Son las decisiones tomadas por el usuario después de probar la primera implementación de objetos dinámicos y revisar sus problemas. No te quedes en un análisis o un plan: realizá la implementación, las pruebas que puedas ejecutar y la actualización documental.

**Estado de este documento:** instrucciones de trabajo. Los cambios descritos todavía no están implementados ni aprobados por una prueba de juego. La predicción/adopción de objetos necesita un prototipo verificable antes de dar por resuelto su comportamiento.

## 1. Reconstruir el estado y conservar el trabajo existente

Leé las instrucciones aplicables del repositorio. Revisá rama, HEAD, cambios locales e historial reciente. Al preparar este pedido, HEAD era `677086f`, la incorporación de objetos sueltos con física. No supongas que sigue igual: contrastá el código que tengas delante.

Conservá todos los cambios existentes, incluidos archivos nuevos y eliminaciones locales. No cambies de rama, limpies carpetas, hagas commit ni subas cambios por iniciativa propia. No implementes el menú de debug futuro como parte de esta tarea.

Fuentes de contexto, en este orden:

1. `docs/net/guia_del_laboratorio.md`.
2. `docs/net/objetos_fisicos.md`.
3. `docs/net/problemas_objetos_fisicos_2026-11-14.md`.
4. `docs/net/inventario_de_grilla.md`, `problema_objeto_sobre_un_borde.md` y las secciones pertinentes de las auditorías de interacción/inventario/editor.
5. `docs/net/prompt_claude_objetos_dinamicos.md`, como pedido original, y `arquitectura_coop_y_esqueleto_de_red.md`, como historial.

**Este documento reemplaza las decisiones anteriores en los puntos que cambia expresamente.** En particular, ya no rige prohibir la hitbox custom en la selección; tampoco se elige H2 como una ayuda de segunda oportunidad. Las alternativas L1/L2/L3, T1/T2/T3, S1/S2 y H1/H2/H3 del informe son antecedentes, no una lista de opciones pendientes para volver a preguntarle al usuario.

Trabajá en el laboratorio actual. No migres automáticamente sistemas legacy ni rediseñes el movimiento del personaje. Verificá la versión instalada de Godot/Jolt y la disponibilidad real de las APIs antes de usarlas. No agregues autoloads para esta incorporación.

## 2. Decisiones aprobadas y resultado esperado

Hay tres problemas a resolver y un cambio de selección integrado con ellos:

| Tema | Decisión |
| --- | --- |
| Cuerpo físico defectuoso | Reemplazar el generador propio de tajadas/muestras por generación de colisiones de Godot, con formas simples o configuradas cuando convenga. |
| Selección y agarre | Mantener una forma de agarre independiente del cuerpo físico. Si existe custom válida, usarla como selección principal; sin custom, usar la geometría del modelo. |
| Objeto atrasado al mover la vista | Predicción local inmediata y validación del host, con adopción acotada de resultados creíbles inspirada en el personaje. Corregir además las etiquetas temporales de las poses. |
| Objetos flotando al retirar su apoyo | Despertar cuerpos cercanos e integrar ese despertar con el registro de cuerpos activos, el estado del mundo y la réplica. |

No alcanza con endurecer el seguimiento, aumentar la densidad de muestras del generador viejo o agregar una excepción para la tabla. La solución debe servir a los objetos existentes y al flujo de creación de objetos nuevos.

Conservá las capacidades ya elegidas: dos esquemas de botones y dos modos de sostener, preferencias independientes, rueda para distancia, botón central para girar, tercer eje con Shift, prioridad de interfaces y exclusión del zoom mientras se usa la rueda con un objeto sostenido. Conservá el agarre por una punta, el giro con la vista, recoger con E, pilas, cantidades parciales, inventarios, contenedores, consumibles, equipo, barra rápida y miniaturas. Los objetos siguen sin chocar con los personajes, según la decisión vigente. Todos mantienen la misma masa física y el mismo impulso de lanzamiento; no implementes ahora un sistema de peso ni daño por impacto.

## 3. Dos apartados independientes en el editor

El panel Objetos debe presentar claramente:

- **Cuerpo físico:** las formas con que el objeto cae, choca, se apoya y atraviesa una abertura cuando realmente cabe.
- **Hitbox de agarre:** el volumen con que se apunta, selecciona y agarra; puede ser más generoso que el modelo para ayudar con objetos pequeños o con huecos.

Son dos configuraciones, no dos mallas visuales completas obligatorias. Pueden compartir controles de formas primitivas, desplazamiento, rotación y previsualización, pero se guardan y se modifican independientemente. Agrandar la hitbox de una llave no debe agrandar su colisión física. No reutilices silenciosamente una como fallback de la otra.

Reutilizá los datos existentes (`body_shape` y `pickup_hitbox`) cuando corresponda. Si el cuerpo necesita una lista de formas para la descomposición convexa, extendé su representación de manera explícita y compatible. Duplicar y guardar deben conservar o copiar correctamente los recursos según las reglas actuales del panel. Mantené previsualizaciones distinguibles y controles para mostrar/ocultar cada forma.

## 4. Generación física con las herramientas de Godot

Retirá del flujo vigente la generación basada en `_samples`, `_split`, `_components`, `_merge_small` y la reducción propia de puntos cuando sean parte del algoritmo defectuoso. No la mantengas como fallback silencioso. Conservá lo reutilizable de `InvItemPhysics`: configuración, consulta de formas, límites, caché, compatibilidad y utilidades que sigan siendo correctas.

Integrá la generación estándar de Godot en el flujo del editor:

1. Una forma convexa para objetos compactos cuando represente bien el volumen.
2. Varias formas convexas mediante la descomposición del motor para objetos que necesiten conservar huecos o entrantes.
3. Primitivas o formas físicas configuradas por el creador cuando sean más sencillas, baratas o adecuadas. Una caja ajustada para una tabla rectangular puede ser la solución definitiva.

Generá y guardá el resultado al preparar el objeto, mediante el panel/editor o una migración reproducible de los recursos existentes. Reutilizá esas formas durante la partida: no hagas la descomposición en cada instancia, cuadro o conexión, ni dependas de que cada PC vuelva a generar exactamente el mismo resultado. Las formas guardadas y sus transformaciones deben entrar en la huella de compatibilidad.

Las funciones auxiliares de Godot pueden crear un `StaticBody3D` de prueba: reutilizá las formas válidas en el cuerpo dinámico real, sin dejar un cuerpo estático duplicado. No uses una colisión cóncava de triángulos como cuerpo dinámico. Verificá que la generación requerida esté disponible en el entorno de editor usado y que el juego exportado solo necesite cargar el resultado preparado.

La geometría utilizada debe respetar tamaño, offsets y transformaciones del modelo tal como se ve en el mundo. No ejecutes scripts arbitrarios de modelos importados para obtener la geometría y conservá las validaciones/fallbacks de modelos vacíos existentes.

La generación del motor es una aproximación, no una garantía de que todo modelo quede perfecto. Permití revisar visualmente el resultado y ajustar el modo, sus parámetros pertinentes o una forma propia. No rellenes huecos físicos importantes para aprobar una prueba. Una hitbox de agarre puede cubrir el centro de un aro; su cuerpo físico debe mantener el hueco si forma parte de su uso.

Prepará los objetos actuales para que funcionen al abrir el laboratorio, conservando IDs, cantidades, estados y encuadres. No dejes al usuario con la obligación de reparar a mano todos los recursos antes de poder probar. No sobrescribas configuraciones físicas personalizadas válidas sin necesidad. Si falla una generación, informalo y evitá guardar una colisión inválida como si fuera correcta.

Referencias oficiales para verificar las APIs, contrastadas con la versión instalada:

- https://docs.godotengine.org/en/stable/tutorials/physics/collision_shapes_3d.html
- https://docs.godotengine.org/en/stable/classes/class_mesh.html
- https://docs.godotengine.org/en/stable/classes/class_meshinstance3d.html

## 5. Custom como selección principal y punto de agarre

La regla única debe ser:

- Con `pickup_hitbox` custom válida: el selector consulta esa forma, aunque el rayo cruce un hueco visual del modelo. No exige acertar primero a los triángulos.
- Sin custom configurada: consulta la geometría del modelo, con el comportamiento de fallback válido que corresponda al recurso.

No implementes H2: la custom no espera a que falle la selección de todos los modelos. Resolvé el primer objetivo válido según esta regla, manteniendo la oclusión y las reglas de primera/tercera persona. El indicador, E, el agarre físico y la validación del host deben compartir el resultado y la política.

El agarre conserva el contacto con la forma efectiva de selección en coordenadas locales del objeto. Si ese contacto queda dentro de un hueco visual, es un **anclaje virtual válido**: no lo cambies automáticamente por el centro ni por el punto del modelo más cercano. Debe seguir siendo posible agarrar por un extremo y rotar sin saltar al centro. Adaptá cualquier recalculado de anclaje autoritativo para que respete esta decisión.

La ayuda de puntería no autoriza atravesar paredes ni alcanzar un objeto distante usando una custom excesiva. Conservá el límite desde los ojos hasta el contacto seleccionado y verificá además que el objeto representado sea físicamente accesible. Una custom que sobresale de una pared no puede, por sí sola, validar el objeto oculto detrás.

Resolvé esa comprobación mediante una regla geométrica explícita y compartida, usando un punto o superficie accesible del cuerpo/modelo cuando haga falta. Esa comprobación de acceso no reemplaza el anclaje virtual ni exige que el rayo original acierte a un detalle diminuto del modelo. No basta con comprobar paredes solo hasta el primer contacto de la custom. Mostrá con pruebas que se conserva la ayuda para una llave pequeña y se rechaza el objeto detrás de una pared cuya custom sobresale. Documentá la regla y cualquier tolerancia elegida.

Conservá el índice espacial; incluí en sus límites el volumen de selección efectivo y actualizalo con movimiento y rotación. No vuelvas a recorrer todos los objetos para consultar customs ni agregues un límite de candidatos que omita objetivos válidos. Conservá las exclusiones de recogidas predichas, la identidad por UID y la limpieza de índices al retirar objetos.

## 6. Movimiento local, validación y adopción acotada

La decisión es **predicción local con control del host**, tomando la idea de adopción del personaje como referencia. No se aprobó transferir autoridad libre al cliente ni permitirle imponer posiciones sin validación.

Leé `scripts/net/client_prediction.gd`, `claim_adoption.gd` y el orden de simulación/adopción de `net_lab.gd`. Entendé qué se compara por tick, las afirmaciones antiguas, las épocas/eventos y cómo se evita corregir dos veces. Reutilizá los principios pertinentes sin copiar tolerancias, estados ni comprobaciones propias de la cápsula del personaje.

Implementá primero un recorrido completo y medible con un objeto sostenido; después extendelo a los demás. Debe incluir:

1. Predicción local del seguimiento y de las colisiones necesarias para responder al mouse sin esperar cada actualización del host. La cámara y el anclaje conservan sus controles actuales.
2. Cálculo de seguimiento compartido, o una fuente común de sus reglas, entre cliente y host. Conservá posición, orientación, velocidades lineal/angular y el anclaje/sesión necesarios. Copiar dos fórmulas que después divergen no es suficiente.
3. Historial acotado de inputs y estados predichos. Cada estado y afirmación debe estar asociado al paso físico/input que realmente representa. Corregí el desfase que etiqueta la pose de un tick con el siguiente; no basta con cambiar un número sin revisar cuándo se captura el cuerpo respecto de la simulación Jolt y del actor.
4. El host mantiene su simulación y decide qué resultados locales puede adoptar. Validá UID, jugador, sesión de agarre, versión de eventos, tiempos, finitud, límites de posición/orientación/velocidades y un recorrido físicamente admisible, con tolerancias justificadas para estos objetos.
5. Compará estado predicho y estado autoritativo del mismo instante. No trates la diferencia entre pose real y objetivo ideal como si toda ella fuera un choque; el controlador de seguimiento también genera atraso normal en el aire.
6. Adoptá únicamente diferencias que no borren choques o eventos autoritativos ni creen penetraciones o movimiento imposible. Cuando no sea admisible, el cliente se reconcilia con el host y lleva el resultado al presente usando los inputs pendientes que corresponda, suavizando la presentación donde sea seguro.

No corrijas la física teletransportando indiscriminadamente un `RigidBody3D` cada cuadro ni quitando todas sus colisiones. Un resultado adoptado tiene que aplicarse mediante una transición física controlada que no genere impulsos artificiales. Una pose final libre no demuestra que el objeto haya seguido un recorrido libre; revisá desplazamiento y rotación de piezas largas y los contactos con otros cuerpos.

La sujeción local necesita comprobar también **rotaciones sin desplazamiento del origen**. La función actual `_keep_out_of_walls` sale temprano si casi no hay traslación y no protege correctamente ese caso. El nuevo recorrido no puede conservar ese agujero ni barrer solo una orientación final como si representara todo el giro.

Los choques con cajas compartidas o con objetos sostenidos por otro jugador deben tener una política explícita. El host resuelve los conflictos; no adoptes una corrección que haga desaparecer la respuesta de un choque mientras deja sus impulsos ya aplicados en otros cuerpos. Conservá una única consecuencia autoritativa de cada lanzamiento/impacto. No agregues transferencia recursiva de autoridad a todos los objetos empujados como solución improvisada.

Extendé el mecanismo de sesiones/versiones para que una confirmación o afirmación vieja no vuelva a agarrar un objeto soltado, no reabra un estado previo a un lanzamiento y no reviva un objeto recogido. Agarrar, soltar, lanzar, retirar del mundo, muerte y desconexión deben invalidar lo que corresponda. La liberación y el lanzamiento transmiten/recuperan un estado coherente de pose y velocidades, sin doble impulso ni salto hacia una pose antigua.

No vuelvas a aplicar impactos o lanzamientos durante una reconciliación de inputs. No hagas rollback y simulación repetida de todo el mundo como requisito de esta tarea. Mantené acotados historial, correcciones y costo; distinguí la presentación predicha del único mundo físico autoritativo. Evitá que los cuerpos de predicción dupliquen choques en la escena.

Primero corregí la comparación temporal y la predicción; después ajustá los valores de seguimiento si la mano sigue demasiado blanda. Endurecerlos es un ajuste jugable, no el arreglo de red. Conservá límites seguros de velocidad/aceleración y la liberación por atasco. No prometas latencia cero ni ausencia total de correcciones con otros cuerpos móviles.

Registrá de forma acotada errores, adopciones y rechazos con su motivo para poder medir esta implementación. Usá los mecanismos de diagnóstico existentes; no construyas el menú de debug futuro ni llenes la salida con una línea por cuadro. Si una prueba demuestra que una forma de adopción es inestable, corregí su diseño o limitá explícitamente esa adopción; no escondas el fallo aumentando tolerancias ni declares resuelto el recorrido que falla.

## 7. Despertar cuerpos cuando se elimina su apoyo

Al retirar del mundo un cuerpo que podía sostener a otros, buscá vecinos mediante el índice espacial existente, usando su volumen mundial previo agrandado por un margen pequeño y justificado. Filtrá los candidatos cercanos y despertá los cuerpos dinámicos que corresponda. Se acepta despertar alguno de más; no despiertes todos los objetos del mapa ni desactives globalmente el sueño.

Hacé la consulta y guardá el volumen/candidatos antes de que retirar el UID del índice o liberar el nodo impida encontrarlos. Coordiná el orden con `queue_free` y el próximo paso de física para que se retire el apoyo y empiece la caída.

**No alcanza con `body.sleeping = false`.** Cambiar esa propiedad manualmente no emite la señal que hoy usa `InvBodies` para mantener `_awake`. En una comprobación aislada con el gestor real, el cuerpo cayó de aproximadamente 10 a 8,75 m mientras la posición registrada en `authority.world` seguía en aproximadamente 10 m y `_awake` permanecía vacío.

Centralizá el despertar programático en una operación del gestor que actualice el cuerpo, registros de actividad, marcadores de nacimiento dormido o sueño programado que interfieran, lectura de pose, índice/historia y envío de cambios según corresponda. No emitas señales artificiales como sustituto de entender esas transiciones.

Integrá ese recorrido donde se retira realmente el cuerpo del mundo, incluida la recogida con E. No lo dispares al eliminar solo una copia visual del cliente ni al recoger parte de una pila que sigue existiendo como cuerpo. Probá una pila de varios objetos y asegurá que la caída se propague y finalmente vuelvan a reposar. Conservá la política vigente de spawns inicialmente dormidos; si despierta un objeto por haber perdido su apoyo, no debe volver a dormirse inmediatamente por un marcador de inicialización viejo.

## 8. Pruebas y criterios de aceptación

Reutilizá los arneses de `scenes/net_lab/inventario/pruebas/` y del editor. Los probes de `tmp/probe_partes.gd`, `probe_latencia.gd`, `probe_apoyo.gd`, `probe_tabla2.gd` y `probe_fina.gd` son referencias diagnósticas si siguen presentes, no pruebas suficientes de la implementación nueva. Convertí las regresiones relevantes en verificaciones mantenibles, sin depender solo de scripts descartables.

### Formas físicas y selección

- Tabla larga: cuerpo continuo sin rendijas artificiales; pasa longitudinalmente por la ranura y se frena al cruzarla. Agarrarla por cualquiera de sus extremos mantiene ese anclaje al girar.
- Objetos redondos y cajas del catálogo: sin extremos recortados ni objetos hundidos por el generador. No basta con comprobar el tamaño global o la cobertura sobre un solo eje.
- Objeto con hueco real: el cuerpo lo conserva con una configuración apropiada; la custom de agarre puede cubrirlo sin cerrar físicamente la abertura.
- Llave pequeña: una custom más grande permite apuntarle sin agrandar su cuerpo físico. Modificar o duplicar una de las formas no cambia la otra.
- Con custom y sin custom: indicador, E, agarre y host coinciden; geometría/paredes delante bloquean; una custom que sobresale de una pared no habilita recoger lo inaccesible. Probar borde de estante y alcance medido desde los ojos.
- Previsualización, guardado, recarga, duplicación y recursos anteriores. Verificar formas generadas persistidas, transforms correctos y huella igual en ambas copias, sin generarlas de nuevo al jugar.
- Mantener el costo local del selector al agregar objetos lejanos; revisar que una custom más grande esté incluida en el índice sin un recorrido global.

### Movimiento y red

- Comparar host y cliente al girar y detener la cámara a velocidades reproducibles, en el aire y frente a una pared. Medir atraso y tiempo de asentamiento antes/después, separando atraso del controlador, red y presentación. Incluir la caja de herramientas del caso original y la tabla agarrada por una punta.
- Probar traslación, rotación pura y ambas juntas contra ranura y pared fina; no admitir atravesar momentáneamente una pared como criterio de éxito por volver después.
- Ejecutar al menos un host y un cliente en procesos distintos con baja latencia y con demora/pérdida/jitter configurados. No presentar el probe de un proceso como prueba completa del cliente nuevo.
- Demostrar afirmaciones aceptadas y rechazadas por causas concretas; ticks coherentes, correcciones que convergen y ausencia de oscilaciones o impulsos acumulados. Conservar controles exclusivos y un solo portador por UID.
- Empujar una caja libre y enfrentar dos objetos sostenidos por jugadores distintos. Probar soltar/lanzar antes de confirmar el agarre, paquetes antiguos y recogida durante la sujeción. Ningún replay duplica impulsos o impactos.
- Muerte, desconexión, cambio de interfaz, pérdida de foco y entrada tardía. Conservar controles, preferencias, recoger pilas parcialmente y las garantías del inventario.
- Cámara lenta: el avance físico, predicción e historial usan una escala coherente sin aplicarla dos veces. No rediseñar todos los pendientes de cámara lenta en esta tarea.

### Apoyos y regresiones

- Dos cuerpos dormidos apilados: recoger el inferior hace caer al superior en el host y actualiza su pose/índice en el cliente durante la caída, no solo al final.
- Pila de varios cuerpos, un objeto que nació dormido y vecinos que no pierden su apoyo. La actividad vuelve a reposo sin costo permanente ni registros abandonados.
- Ejecutar carga/parseo y las suites pertinentes de inventario, alcance, indicador, física y editor. Ajustar expectativas sustituidas por este diseño sin retirar comprobaciones que protejan otros comportamientos.

## 9. Documentación y entrega

Actualizá `objetos_fisicos.md`, `guia_del_laboratorio.md`, `inventario_de_grilla.md` y los comentarios activos que describan reglas reemplazadas. En el informe de problemas, añadí seguimiento con lo implementado, evidencia y pendientes, conservando el análisis original como histórico. No dejes una guía activa afirmando a la vez que la custom no se usa y que es la selección principal.

Documentá los dos apartados del editor y cómo generar/revisar/ajustar las colisiones; el fallback de selección, anclaje virtual y validación de acceso; el contrato temporal y límites de predicción/adopción; el despertar con réplica; y dónde están los valores de Tuning. Distinguí decisiones del usuario de elecciones técnicas tuyas.

Entregá un resumen breve de cambios y una lista concreta para la prueba manual con mouse y las dos notebooks. Separá lo ejecutado de lo inspeccionado o pendiente. Informá resultados y limitaciones reales, sin decir que quedó resuelto lo que todavía no se probó.

Resolvé las elecciones técnicas rutinarias dentro de este alcance. Si aparece una incompatibilidad real que obliga a cambiar una decisión jugable, explicá el caso concreto antes de sustituirla. No vuelvas a pedir que el usuario elija entre las alternativas del informe que este documento ya reemplaza.
