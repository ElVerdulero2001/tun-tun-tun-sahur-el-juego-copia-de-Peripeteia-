# Objetos dinámicos y manipulación física en el laboratorio cooperativo

Implementá esta incorporación en el repositorio `C:\Users\ElCaido97\Documents\tun-tun-tun-sahur`. No te quedes en una propuesta: reconstruí el estado vigente, realizá los cambios, ejecutá las verificaciones que puedas y actualizá la documentación correspondiente. Conservá todo el trabajo local existente. No hagas commit ni push por iniciativa propia.

## 1. Contexto, fuentes y alcance

Leé las instrucciones aplicables del repositorio. Empezá por `docs/net/guia_del_laboratorio.md`, seguí con `inventario_de_grilla.md`, `problema_objeto_sobre_un_borde.md` y las partes relevantes de las auditorías del 08/11 y 12/11. Consultá `arquitectura_coop_y_esqueleto_de_red.md` como historial, distinguiendo decisiones vigentes de implementaciones anteriores. Inspeccioná rama, HEAD y cambios locales antes de editar. Las correcciones del commit `344e277` y su documentación posterior ya estaban en el árbol al preparar este pedido: no trates INT-01 y DAT-01 de la auditoría del 12/11 como necesariamente abiertos.

Trabajá en el laboratorio actual y su arquitectura de actores, inventario y red. No migres el juego anterior ni recuperes automáticamente sistemas legacy. Usá la versión de Godot y el motor de física que realmente tenga el proyecto. No agregues autoloads para resolver esta incorporación.

Hoy `InvWorldItem` es un `Node3D` de presentación sin física. La autoridad y la réplica describen cada objeto del mundo esencialmente mediante pila, posición y cartel. `InvReach.first_hit` enumera todos los objetos y consulta sus triángulos. No es una conversión mecánica de `StaticBody3D` a `RigidBody3D`: hay que incorporar cuerpos físicos, orientación, velocidades, manipulación y sincronización sin crear una segunda identidad de ítem.

Revisá, al menos, `inv_world_item.gd`, `inv_reach.gd`, `inv_net.gd`, `inv_authority.gd`, `inv_replica.gd`, `inv_protocol.gd`, `inv_ui.gd`, `inv_pickup_spawn.gd`, `inv_item_def.gd`, `inv_visuals.gd`, `interact_focus.gd`, `interact_indicator.gd`, `lab_camera.gd`, el flujo de inputs/simulación y el panel `addons/inventario_objetos/`.

El alcance son los ítems sueltos del inventario, incluidos los creados por `InvPickupSpawn` y los soltados desde grillas. No conviertas todas las cajas, puertas, plataformas, escaleras ni el escenario en objetos transportables. Prepará una integración por componentes que permita ampliar los objetos manipulables después, sin implementar ahora esos sistemas futuros.

## 2. Resultado jugable

Los objetos sueltos tienen gravedad, chocan con el escenario y entre sí, pueden reposar y dormir, y se pueden sostener en el mundo, acercar/alejar, rotar, soltar y lanzar. No entran al inventario por sostenerlos físicamente.

Conservá recoger con E, las grillas, transferencias, pilas, consumibles, equipo, barra rápida, miniaturas, indicador y nombre. Diferenciá en código y documentación sostener físicamente de llevar un ítem con el cursor dentro del inventario.

Soltar desde la grilla debe producir un objeto físico en un lugar válido junto al personaje y dejarlo caer. Retirá del flujo vigente la obligación de encontrar piso para apoyarlo: tiene que poder soltarse en el aire o desde un cable. Conservá validaciones de acceso, cantidades y espacio inicial libre. Si no cabe sin atravesar una pared o al jugador, rechazá sin perder unidades. Adaptá la presentación anticipada existente y su reconciliación; no mantengas un objeto físico confirmado y un duplicado predicho simultáneos.

No agregues daño por lanzamiento, destrucción, sistema de peso del inventario, límites de carga ni mecánicas de fuerza del personaje en esta entrega.

## 3. Controles y preferencias del jugador

Implementá acciones semánticas y configuración accesible al jugador, reutilizando el menú/configuración existente si lo hay. Los dos ejes de preferencia son independientes:

| Preferencia | Opción | Comportamiento |
| --- | --- | --- |
| Botones | Principales | Derecho agarra/suelta; izquierdo lanza |
| Botones | Laterales | Lateral trasero, cerca de la palma, agarra/suelta; lateral delantero, cerca del cable, lanza |
| Sostener | Alternar | Un clic agarra y otro clic del mismo botón suelta sin lanzar |
| Sostener | Mantener | Agarra al presionar y suelta sin lanzar al liberar |

Como valores iniciales usá botones principales y alternar. Guardá las preferencias mediante el mecanismo existente; si no existe, agregá una solución local mínima y documentada. No instales software ni dependas de Logitech G HUB. El mouse de referencia es un Logitech G203, pero el sistema debe funcionar con otros dispositivos.

No confundas los nombres comerciales Mouse 4/Mouse 5 con los valores de `MouseButton` de Godot: `MOUSE_BUTTON_WHEEL_UP/DOWN` son 4/5; los laterales son `MOUSE_BUTTON_XBUTTON1/XBUTTON2` (atrás/adelante, normalmente 8/9). Usá constantes y acciones. Explicá cómo probar el mapeo si un controlador del mouse lo modificó.

Mientras se sostiene un objeto:

- Izquierdo, o lateral delantero según el esquema, lanza una vez al presionar. No lanza sin objeto sujeto. Después de lanzar, liberar el botón de agarre en modo mantener no genera otra operación. No debe agarrar otra cosa automáticamente hasta una nueva pulsación.
- La rueda aleja/acerca el punto de sujeción: hacia arriba lo aleja y hacia abajo lo acerca, con pasos, distancia mínima y máxima configurables. Este sentido es el valor inicial elegido para esta implementación; dejalo claramente indicado y fácil de invertir.
- Mantener presionado el botón central y mover el mouse rota el objeto. Al liberar el central vuelve a mirar normalmente. Mientras rota, ese movimiento no gira la cámara ni cambia la orientación del personaje como efecto secundario. Para dar acceso a los tres ejes, usá movimiento horizontal/vertical para dos ejes relativos a la vista y Shift + movimiento horizontal para el tercero; documentá ejes y sensibilidad. Es una convención inicial de esta implementación.
- La rueda no cambia el zoom de la cámara. El botón central queda reservado a la rotación y no dispara otro comportamiento de cámara o juego.
- Fuera del modo de rotación, mover el mouse sigue permitiendo mirar y trasladar el punto sostenido con la vista.

Sin objeto sujeto, los controles existentes de la cámara siguen funcionando. No alteres los atajos numéricos de zoom por deducción: el pedido reserva rueda y botón central. Los ajustes de distancia del objeto tienen límites seguros independientemente de los controles de cámara.

Resolvé la prioridad explícitamente: interfaz/modal primero, manipulación después y cámara/juego después. No dependas del orden accidental de los nodos ni de consumir un evento después de que la cámara ya actuó. Revisá también cualquier sondeo de `Input` que pueda ignorar el consumo de eventos.

Decisión inicial para los cambios de contexto: al abrir inventario, menú o una interfaz que toma el mouse, soltá físicamente sin lanzar antes de ceder el control. Al morir, desaparecer el actor, perder la conexión o cerrar la sesión también debe liberarse la sujeción. Cambiar las preferencias durante un agarre debe terminarlo limpiamente. No dejes estados de botón central, cursores o botones presionados enganchados al recuperar el foco.

## 4. Punto de agarre y comportamiento físico

El punto de agarre es el contacto real del rayo con el modelo, no el centro de su AABB, el origen del nodo ni el centro de masa. Reutilizá el selector vigente de cámara y rayo desde los ojos, con primer contacto, oclusión y alcance medido hasta el punto tocado. Conservá las reglas de primera/tercera persona y del indicador.

Al comenzar, convertí el contacto mundial a coordenadas locales del cuerpo y conservá ese anclaje durante todo el agarre. Actualizá su transformación al moverse y rotar. El objeto mantiene inicialmente su orientación: no debe saltar ni alinearse solo con la cámara. Rotarlo debe acomodarlo alrededor del punto sujeto sin reemplazar ese punto por el centro.

El objetivo es poder agarrar una pieza larga por cualquiera de sus extremos y orientarla para introducirla longitudinalmente por una abertura. Armá un caso de prueba de ese tipo. Respetá offsets del modelo y cualquier cambio del origen necesario para el cuerpo físico: que el origen visual actual esté en la base no autoriza a calcular mal el anclaje o el centro de masa.

Usá seguimiento físico estable del anclaje y de la orientación deseada, con fuerzas/torques o restricciones apropiadas para el motor instalado. Justificá brevemente la solución elegida. No hagas del cuerpo un hijo rígido de la cámara, no lo teletransportes cada cuadro a una transformación impuesta y no desactives todas sus colisiones mientras se sostiene.

Debe chocar al moverlo y girarlo. Cuando encuentra una pared, no acumula fuerza ilimitada ni atraviesa el obstáculo para llegar al objetivo. Acotá fuerzas, velocidades, distancia y error de seguimiento; si el jugador se aleja demasiado o el objeto queda atrapado, liberá de manera segura. Usá el volumen del cuerpo y no solo un rayo para proteger la manipulación de piezas largas. Evaluá CCD para los casos de lanzamiento que lo necesiten y probá contra paredes delgadas.

Podés excluir temporalmente la colisión con el propio portador para evitar vibración y autopropulsión, siempre que no permita atravesar el escenario y que la excepción se restaure al liberar. Gestioná la liberación con solapamiento sin impulsos explosivos. Respetá las capas/máscaras y el motor de movimiento actual; no rediseñes empuje, escalada o transporte del personaje sobre estos objetos en esta entrega.

Soltar corta la sujeción sin agregar impulso de lanzamiento ni borrar arbitrariamente el movimiento físico que el objeto ya tiene. Lanzar corta la sujeción y aplica una única vez un impulso común, configurable globalmente, en la dirección de lanzamiento derivada de la vista y validada por el host.

Todos los objetos tienen por ahora la misma configuración de masa física y de lanzamiento. La masa mínima necesaria para el motor no constituye un sistema de peso jugable. Dejá un punto claro de extensión para relacionar peso y lanzamiento en el futuro; no agregues ahora fórmulas o campos de peso por ítem sin necesidad. Separá agarre, impulso de lanzamiento y capacidades de inventario.

## 5. Colisión y precisión de selección

Separá tres conceptos: geometría visible, colisión física y selección precisa del rayo. Para cuerpos dinámicos usá primitivas o formas convexas/compuestas válidas para el motor; no conectes una malla cóncava de triángulos a un rigid body dinámico como solución general.

Generá o prepará la colisión por definición una vez, con caché o recursos reutilizables; no reconstruyas geometría por cuadro. Ofrecé una forma razonable de ajustar su volumen desde el flujo actual de creación de objetos si la generación automática no alcanza. No ejecutes scripts ni física arbitrarios de modelos importados para extraer su apariencia o colisión. Conservá los modelos vacíos con fallback y las validaciones vigentes.

Un único casco convexo puede tapar huecos y cavidades: no lo des por válido si impide el caso de la pieza y la abertura. Usá una composición adecuada donde haga falta. No uses una caja enorme de colisión para aprobar las pruebas.

Para seleccionar y fijar el anclaje, conservá el contacto preciso sobre el modelo. La antigua `pickup_hitbox` guardada para edición no vuelve a ser la regla de recogida. Un proxy de colisión física no debe hacer seleccionable un hueco visual. La prueba de triángulos debe operar con la transformación completa vigente del objeto, no con la resta de posición que hoy supone objetos sin giro.

## 6. Resolver el recorrido global del selector

El hallazgo REND-02 es costo de CPU creciente al consultar la escena; no confundirlo con latencia de ida y vuelta al host. Agregar cuerpos físicos no lo resuelve si `first_hit` sigue recorriendo todo `world` para cada rayo.

Incorporá una fase espacial de candidatos mediante las estructuras de física o un índice espacial apropiado. El rayo de cámara, el de la mano y la validación del host deben consultar candidatos locales al segmento y después resolver el primer contacto preciso. Conservá las paredes, las cajas, los objetos que ocultan a otros y las exclusiones de predicción.

No reemplaces el recorrido completo por otro recorrido completo que filtre distancia, una búsqueda global de nodos/grupos por cuadro ni un límite arbitrario de candidatos que omita el objetivo. Si una forma física aproximada da un falso contacto en un hueco, la selección precisa debe poder seguir hacia el objeto o pared que realmente está detrás.

El mecanismo debe actualizar altas, bajas, movimiento, rotación, reposo y reconciliaciones. No uses únicamente el contacto físico más próximo si su forma aproximada cambia qué modelo se ve primero. Mantené el índice coherente con la transformación consultada, distinguiendo representación interpolada y estado autoritativo.

Medí por separado el selector y la simulación: compará el mismo grupo de objetos cercanos con cantidades crecientes de objetos lejanos en reposo. Informá tiempos y candidatos consultados, condiciones y límites. No prometas costo total constante: agregar cuerpos también tiene costo de memoria, física y red. Evitá introducir un barrido completo por tick solo para mantener el índice si no hace falta.

## 7. Autoridad, identidad y sincronización cooperativa

El host arbitra las operaciones y simula la física autoritativa. Cada ítem conserva su UID, tipo, cantidad y estado. Un objeto no puede existir a la vez en una grilla y como cuerpo físico confirmado, ni estar sostenido por dos jugadores.

Definí transiciones explícitas entre mundo libre, mundo sostenido e inventario. Reutilizá `InvAuthority`, réplica, protocolo y orden de operaciones existentes. No fabriques un segundo inventario para el sistema físico.

En clientes, separá presentación fluida de simulación autoritativa. Podés usar interpolación y una anticipación local acotada para el portador, pero no dejes varias simulaciones independientes compitiendo por la posición real. La representación cliente debe seguir siendo consultable por el selector. No hagas esperar visualmente un ping completo para cada movimiento de la mano, ni prometas eliminar toda latencia física.

Extendé los datos del mundo más allá de `pos`: transformación/orientación, velocidades y estado necesario para alta, reposo, movimiento y sujeción. Definí frecuencia, orden y reconciliación de snapshots. No reconstruyas cuerpos con cada actualización del inventario y no mandes el inventario o todos los objetos completos por cada movimiento físico. Usá actualizaciones acotadas y reposo para reducir tráfico.

Separá operaciones discretas confiables —agarrar, soltar, lanzar, recoger, altas y bajas— del seguimiento continuo de objetivo/orientación. Incluí secuencias o identificadores de sesión de agarre para descartar movimientos y respuestas viejas. Un paquete tardío no puede volver a sujetar un objeto liberado, revivir uno recogido ni aplicar dos veces el impulso.

Validá en el host identidad, exclusividad, vida/acceso del actor, alcance, paredes, anclaje, límites y finitud de todos los números. El cliente expresa intención; no impone transformaciones, UID, velocidades ni fuerzas arbitrarias. Calculá o revalidá el contacto solicitado sobre la geometría autoritativa.

Conservá el contrato temporal vigente del tick y de las poses de los ojos. Ahora el objetivo también se mueve: especificá qué instante del objeto usa la validación y cómo se resuelven pequeñas diferencias entre presentación y host. No combines silenciosamente ojos históricos y posiciones actuales afirmando que representan el mismo instante. Elegí una política acotada, probala con objetivos en movimiento y documentá sus límites. No construyas un rollback completo del mundo como requisito de esta entrega.

Casos que deben tener una resolución coherente:

- Dos jugadores intentan agarrar el mismo UID: gana una sola operación; el otro recibe rechazo y revierte su presentación.
- E recoge un objeto libre o sujeto por el propio jugador: se valida y transfiere atómicamente; la sujeción termina si desaparece el cuerpo. Si entra solo parte de una pila, el resto conserva identidad, pose física y una sujeción válida si corresponde. No agregues un nuevo atajo especial para guardar.
- E sobre un objeto sostenido por otro jugador no permite quitárselo. No habilites robo o forcejeo accidentalmente.
- Pérdida/reordenamiento de mensajes, confirmación tardía del agarre después de haber soltado, cambio de actor, desconexión y muerte: sin objetos atrapados ni operaciones dobles.
- Un cliente que entra tarde o reconecta ve objetos que están cayendo, rotados, dormidos y sujetos, con su pose y portador correctos.

Integrá el avance físico con la cámara lenta global existente sin aplicarla dos veces. No reproduzcas impactos o impulsos como efectos secundarios durante replays de inputs del actor. No intentes arreglar en esta tarea todos los pendientes generales de cámara lenta.

## 8. Editor, recursos y documentación

Conservá el catálogo, `InvStack`, `state_override`, cantidades, carteles y los encuadres independientes de miniaturas. La física del mundo no debe ejecutarse dentro de los visores ni alterar el modelo equipado.

Si agregás datos de colisión/tuning, integrá edición, validación, duplicación y compatibilidad con recursos anteriores en el flujo actual. No requieras editar a mano cada `.tres` para que los objetos existentes funcionen. Incorporá a la huella de compatibilidad los datos que afecten la simulación y al protocolo su versión si corresponde.

Con objetos rotables, permití una orientación inicial coherente con el marcador de spawn y su preview. Las escenas previas, cuyos marcadores tenían orientación identidad, deben conservar su apariencia inicial. Respetá escala visual y offsets; no apliques escala no uniforme al cuerpo físico sin resolver correctamente sus formas.

Actualizá `guia_del_laboratorio.md` e `inventario_de_grilla.md`. Creá un documento específico de manipulación física si el tamaño lo justifica, enlazado desde la guía. Identificá como históricas las reglas sustituidas: objetos sin física, solo posición, colocación obligatoria sobre piso y recorrido global del rayo. Documentá controles, preferencias, tuning, transiciones, capas, política temporal, réplica y limitaciones reales.

## 9. Verificación y entrega

Ejecutá checks de carga/parseo y las suites existentes pertinentes de inventario, alcance, indicador, spawn/editor y red. Adaptá las expectativas que cambian por decisión de este pedido; no elimines protecciones para que pasen. Agregá pruebas significativas de las transiciones y regresiones nuevas, reutilizando los arneses actuales.

Prepará una escena o zona reproducible con: una pieza larga que se pueda agarrar por ambos extremos, una abertura estrecha para orientarla, una pared delgada para lanzar contra ella, una superficie y un borde para caídas, y varios objetos que se puedan ocultar entre sí. Sin introducir contenido pesado innecesario.

Comprobá al menos:

1. Ambos esquemas de botones combinados con ambos modos de sostener, sin doble suelta/lanzamiento; selección y persistencia de preferencias.
2. Agarre por una punta sin salto al centro, rotación alrededor del anclaje y acceso a los tres ejes; pieza introducida longitudinalmente por la abertura.
3. Rueda y botón central sin efectos simultáneos en cámara; vuelta normal al liberar; interfaz, Esc y pérdida de foco sin estados pegados.
4. Gravedad, reposo, choque entre objetos, movimiento y giro contra paredes, lanzamiento rápido contra pared delgada y límites de seguimiento.
5. Soltar desde inventario sin piso cercano, cantidades parciales, E, transferencias y rollback sin pérdida ni duplicación.
6. Dos clientes compitiendo, latencia/pérdida configuradas, soltar antes de que llegue el sí del agarre, desconexión/muerte y entrada tardía con cuerpos en distintos estados.
7. Objetos moviéndose y rotando que siguen siendo seleccionables con el punto correcto, huecos que no se convierten en sólidos seleccionables y oclusión en primera/tercera persona.
8. Medición del selector con muchos objetos lejanos, sin esconder el costo de física/red; reposo y eliminación limpian cuerpos, índices y cachés.

Al terminar, explicá qué implementaste, qué archivos cambiaste, cómo probar los controles y qué decisiones técnicas tomaste. Diferenciá pruebas ejecutadas de comprobaciones que requieren al usuario con mouse y dos PC. No declares probado lo que solo inspeccionaste ni ocultes limitaciones de latencia o colisión. Si aparece una incompatibilidad que obliga a cambiar un comportamiento pedido, describí el conflicto concreto antes de reemplazarlo silenciosamente. Resolvé por tu cuenta las elecciones técnicas rutinarias y completá la implementación dentro de este alcance.
