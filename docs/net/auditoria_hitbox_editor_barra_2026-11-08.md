# Auditoría de hitbox de agarre, panel Objetos y barra rápida

Fecha: 2026-11-08.

## Resumen

La hitbox funciona en los recorridos normales probados. En dos procesos, el cliente marcó y recogió por la hitbox y el host confirmó. También se verificó el rechazo de una definición distinta y el arranque del laboratorio desde el ejecutable de Windows exportado. El encuadre cuadrado se renderizó por separado de la miniatura de grilla.

Los tres puntos para resolver primero son **el margen de la mira que pierde contactos iniciales**, **la apertura tardía de cajas que el HUD ya dio por fallida** y **las pruebas que dependen del machete de uso diario**. La primera falla deja al jugador sin indicador ni agarre en una posición desde la que el rayo sí toca el objeto. La segunda puede reemplazar la integridad por una caja después del aviso de que no se abrió. La tercera oculta regresiones entre fallas provocadas por editar el contenido de prueba.

| ID | Hallazgo | Clasificación | Gravedad | Confianza | Prioridad |
| --- | --- | --- | --- | --- | --- |
| AG-01 | La mira pierde el contacto inicial con el modelo cuando tiene margen | Error actual | Media | Alta, reproducción en Jolt | P1 |
| CAJ-01 | Cancelar o agotar la espera de una caja deja estados incompatibles en el HUD | Error actual | Media | Alta, reproducción con la UI y réplica reales | P1 |
| PRU-01 | Las pruebas de inventario y miniaturas cambian de resultado al editar el contenido del laboratorio | Error actual de verificación | Media | Alta, suite actual y comparación contra HEAD | P1 |
| OBJ-01 | El selector de forma personalizada permite crear un recurso sin dar acceso a sus propiedades | Error actual del editor | Media | Alta, señal y estado del Inspector verificados | P2 |
| AG-02 | Los candidatos descartados pueden agotar el límite antes del objeto válido | Riesgo futuro concreto | Media | Alta, reproducción con una disposición deliberadamente densa | P2 |
| REND-01 | La mira prepara exclusiones de todo el mundo en cada cuadro | Riesgo futuro concreto | Media | Alta sobre el mecanismo, costo sin medir | P2 |
| OBJ-02 | La zona conserva el movimiento del marcador, pero pierde la marca de edición pendiente | Error actual del editor, previo a la incorporación | Media | Alta sobre el síntoma, causa del editor pendiente | P2 |
| DOC-01 | La guía de inventario y el comentario de Show Label divergen de sus contratos vigentes | Discrepancia documental | Baja | Alta por inspección y contraste con pruebas | P3 |

**P1** antes de ampliar estas funciones. **P2** antes de integrar al juego o cuando se alcance el disparador indicado. **P3** puede esperar a la próxima edición de las guías.

## 1. Alcance y fotografía del repositorio

- Rama `net-lab-hitbox-agarre`, commit `cfc8760b59af66d08f7fb08369b56962dcaad330`. La rama local `net-lab` termina en `c7cea37324e30f49366de9e2fe84dc70229f397d`, ancestro de HEAD y referencia para el seguimiento de la auditoría anterior.
- **Base de la incorporación local.** Usé HEAD para el diff del trabajo sin commit. Incluye forma de modelo y hitbox editable, volumen y visor dedicado, miniatura de barra con encuadre propio, corrección de proporción, paneo y gizmo de rotación. El historial no divide ese diff en entregas independientes. El machete local pasa de 1 × 3 a 1 × 6, de 0,6 a 1,2 m y recibe hitbox y encuadres propios. Tomé eso como contenido de autoría, no como un defecto de grilla ni como una decisión de balance atribuible al usuario.
- **Integración vecina.** `8ae157b` abre la caja directamente en su modo y `cfc8760` cambia Tab para cerrar solo la caja. Revisé ambos por compartir el selector y el HUD. `ffcd6ee`, `c5f9043` y `add031e` aportan el indicador, integridad y curación, y su documentación. Son antecedentes de la integración, con revisión de los recorridos que toca esta entrega.
- **Estado local.** 25 rutas rastreadas con cambios sin preparar, incluida la eliminación local de `auditoria_parkour_2026-10-30.md`. El índice estaba vacío de cambios. Entre los archivos nuevos estaban `gizmo_rotacion.gd`, `inv_pickup_hitbox.gd`, la escena y el script de `inv_hitbox_test` y sus UID. También figuraban `archive/`, `output/pdf/`, `tmp/` y un temporal de `project.godot`. Excluí esas salidas y copias del alcance. La auditoría de parkour se consultó en Git.
- **Configuración real.** `project.godot:14–17,31–33,188–194` declara Godot 4.7, Forward Plus, Jolt, D3D12 en Windows y el plugin Objetos. El laboratorio arranca por su escena o por la variante `lab_coop` del preset Windows. El ejecutable de las pruebas reportó **4.7.2.stable.official.ed1daf0bf**. Los autoloads de otros sistemas son preexistentes. El selector de hitbox vive en el inventario del laboratorio. El lanzador genérico de pruebas todavía trae una ruta por defecto de 4.6.3 (`tools/testing/run_headless_test.ps1:114`), por lo que para estas escenas hay que pasar explícitamente el motor de 4.7.2.
- Apliqué las instrucciones de proyecto entregadas en el turno. Revisé la guía vigente y los documentos de inventario, HUD y Objetos, el roadmap y los prompts como antecedentes. Del historial usé especialmente las secciones 8.37–8.42 y la referencia de seguimiento de parkour de la guía. Las decisiones vigentes se contrastaron con el código y los recursos del árbol de trabajo.

### Decisiones y límites que orientan la revisión

El usuario pidió facilitar el agarre de objetos chicos y con huecos, un visor cómodo, encuadres independientes y giro por eje. También pidió que E abra la caja sin mostrar primero la integridad y que Tab cierre solo la caja. Los valores de ajuste inicial, margen, límite de consultas, tipos de colisión y conservación del objeto propio en la mano son decisiones de implementación. Para el cooperativo se conserva un inventario por jugador y el host arbitra los objetos y cajas. La compatibilidad es entre copias del laboratorio, con huella y distribución manual. El laboratorio descarta el inventario al irse definitivamente y conserva el de una reconexión dentro de su ventana. La curación de partes y los estados siguen sus reglas de prueba. El radial con Q, el termómetro de luz y el guardado de partidas quedan fuera de esta entrega.

### Recorrido comprobado

- **Mundo → E → inventario.** El host reúne marcadores de `world_root` y `pickup_root`, valida su pertenencia al catálogo, asigna UID y replica pila, posición y cartel. `InvNet._sync_world_views` crea `InvWorldItem`, que arma el `Area3D` de mira. `InvUI._look_target` entrega la cámara a `InvNet.interaction_target`. E y el indicador usan ese selector, que aplica pared, alcance, visibilidad y cono de tercera persona. El indicador proyecta el modelo. `pick_up_world` prueba espacio de grilla y presenta la recogida predicha. El host valida UID, alcance y vista y aplica `InvOps.insert`, con resultado total, parcial o rechazo. `InvReplica.apply_commit` actualiza mundo e inventario y elimina la intención pendiente. La selección por cámara es local por contrato. La autoridad vuelve a validar el acceso y la inserción, y arbitra dos recogidas por el mismo UID.
- **Cajas → panel derecho.** La apertura empieza en `InvUI.open_box` con un pedido `OPEN` y una reserva del panel derecho. `InvAuthority._open` comprueba acceso y envía snapshot. La réplica aplica el snapshot y emite la respuesta. Tab, E y Esc toman caminos distintos según el estado de UI. Las operaciones que ya salieron conservan su orden en el host.
- **Consumibles → simulación → HUD.** El uso predicho viaja por `ActorInput` con número de uso, UID, pedido anterior y, si corresponde, parte. `InvNet.use_before_step` ordena y valida los usos en el host y ejecuta su predicción sobre el estado local al avanzar o repetir ticks. `InvAuthority._heal_part` revalida capacidad y parte antes de gastar. El inventario confirmado viene del host y el HUD lee el estado del actor. La prueba de muerte, agotamiento y cámara lenta se hizo con los arneses existentes.
- **Editor → recursos → juego.** El formulario trabaja con un borrador. `Guardado` valida dimensiones y formas, conserva el recurso del ítem al editar y copia subrecursos internos al duplicar. La forma personalizada externa se comparte como referencia. La miniatura de grilla y la variante cuadrada usan los mismos encuadres en editor y juego y claves de caché separadas cuando corresponde. La variante de barra se genera localmente. El perfil de exportación conserva el script de la hitbox en el proyecto y el arranque de release se verificó con el preset existente.

## 2. Hallazgos por prioridad

### AG-01 — Una esfera de margen que ya toca el modelo deja la mira sin candidato

**Error actual · gravedad media · confianza alta · P1.** Afecta objetos en «Forma del modelo», incluidos los que usan la caja visual por defecto. Referencias: `scripts/inventory/inv_net.gd:456–481,496–544` (`interaction_target`, `_aim_candidates`), `scripts/inventory/inv_world_item.gd:146–160` (`_aim_shape`), `scripts/actor/actor_tuning.gd:377–385`.

**Disparador y recorrido.** Con margen positivo, el rayo excluye las áreas de modelo. El otro camino llama a `cast_motion` y consulta solapamientos recién en la fracción que informa el barrido. Si la esfera ya solapa la forma al arrancar y el barrido la omite, el modelo queda fuera de los dos caminos. `hit_from_inside` está en la consulta del rayo y no rescata las áreas excluidas de esa consulta.

**Evidencia ejecutada.** En una escena temporal con la forma generada por un `InvWorldItem` real y una `BoxMesh`, ubiqué el origen 2 mm antes de la cara. La consulta estática detectó el solapamiento inicial. El rayo tocó la cara a 2 mm y el selector de candidatos con margen cero devolvió el UID. Con margen de 20 mm devolvió una lista vacía. Esto explica el fallo del indicador y E si no hay otro candidato, aun estando dentro del alcance.

**Corrección y verificación.** Consultar el solapamiento inicial con el mismo filtro de áreas, incorporarlo con distancia cero, y continuar el barrido excluyendo los contactos ya considerados. Conservar las comprobaciones de alcance, pared y vista. Probar origen a 2 mm de la cara con margen cero y positivo, un origen apenas fuera del margen y un solapamiento que no cumple acceso. El indicador y E deben resolver el mismo UID en ambos modos de cámara cuando el objeto sea válido.

### CAJ-01 — La cancelación visual de una caja no coincide con el ciclo del pedido

**Error actual · gravedad media · confianza alta · P1.** Referencias: `scripts/inventory/inv_ui.gd:179–221,343–372,403–419,939–956,1487–1494`, `scripts/inventory/inv_replica.gd:312–330,363–384,409–423`, `scripts/inventory/inv_authority.gd:264–269,513–523`.

**Disparador y recorrido.** Si el inventario ya estaba abierto, se pide abrir una caja y vence el plazo local, `_box_wait_failed` borra la reserva y deja abierta la UI. La réplica puede aplicar después un snapshot válido y emitir `answered`, incluso con el pedido ya retirado de `pending`. Como ese vencimiento no marcó el pedido cancelado y la UI sigue abierta, `_on_answered` conserva la caja. En la cancelación manual con Tab sí se marca el pedido, pero `_e_closes_box` sigue consultando el `OPEN` pendiente. Hasta que llega la respuesta, E cierra el inventario y el indicador sigue suprimido aunque el panel ya muestre integridad.

**Evidencia ejecutada.** En el laboratorio aislado hice caducar un `OPEN` envejeciendo su marca de tiempo y apliqué un commit tardío con snapshot mediante `InvReplica.apply_commit`. El aviso fue «El host no contestó: Caja de prueba no se abrió», con `box_id = 0`. Al aplicar el commit, `box_id` cambió a 1 y el cliente no emitió `CLOSE`. En una segunda apertura, Tab dejó el inventario abierto, `is_waiting_box() = false`, `_e_closes_box() = true` y `can_interact() = false`. Esto fue una inyección controlada de la entrega tardía, no una medición de una red que demore diez segundos. El caso normal a +200 ms sí pasó.

**Corrección y verificación.** Dar a la apertura una sola transición de cancelación, común a vencimiento y Tab, que conserve su identidad hasta drenar la respuesta. E y el indicador deben consultar la intención visible. Al recibir una apertura cancelada, ignorar su snapshot para la UI y cerrar en el host esa suscripción sin afectar una apertura posterior. Verificar rechazo, éxito tardío, Tab seguido de E, cerrar y reabrir la misma caja y abrir otra con la respuesta anterior en vuelo. Afirmar estado en el HUD y suscripción efectiva en el host.

### PRU-01 — La edición de un ítem real rompe tres suites

**Error actual de verificación · gravedad media · confianza alta · P1.** Referencias: `scenes/net_lab/inventario/objetos/machete.tres:23–39`, `scenes/net_lab/inventario/pruebas/inv_lab_test.gd:45–47,576–620,648–679`, `inv_visual_test.gd:88–112` en la misma carpeta, `addons/inventario_objetos/pruebas/prueba_del_creador.gd:771–845`, `scenes/net_lab/net_lab.tscn:61–66`, `scenes/net_lab/net_lab_level.tscn:484–490`.

**Disparador y recorrido.** Una edición válida del machete cambió su huella y dejó de usar los encuadres de fábrica. Los arneses todavía esperan una huella 1 × 3, celdas de agarre y destino libres para esa huella, giro automático y barra sin encuadre propio. Además, el conteo inicial compara solo los marcadores de `ZonaDeInventario` con un mundo que también incluye los de `Level`. Parte de las fallas de movimiento y barra son consecuencias del primer intento de colocación inválido.

**Evidencia ejecutada.** La prueba general dio 11 fallas en 176 comprobaciones. El mismo arnés de HEAD dio 1 en 166, únicamente el conteo 22 contra 23. En la corrida visual, el machete ya tenía `custom_hotbar_thumbnail = true` al comprobar que ambas texturas fueran la misma. Fue la única falla en 10 comprobaciones. El editor dio 5 fallas en 217: cuatro están ligadas al ítem inicial o a sus encuadres. Por ejemplo, el texto `thumbnail_rotation` también coincide con `hotbar_thumbnail_rotation` aunque el encuadre de grilla haya vuelto a fábrica. La quinta falla se reprodujo en HEAD y está separada en OBJ-02.

**Corrección y verificación.** Usar un ítem de prueba controlado para la rotación y los valores de fábrica, y otro con encuadre de barra propio. Verificar las propiedades exactas después de recargar el recurso, contar ambos orígenes mediante el mismo contrato del host y comprobar un destino libre para el tamaño real. Para probar reutilización, exigir una textura no nula antes de comparar identidad. Ejecutar las tres suites con un machete de producción de tamaño o encuadre distinto. Una modificación de contenido válida debe conservar el resultado de las pruebas y una rotación o barra realmente rota debe hacerlas fallar.

### OBJ-01 — La forma personalizada nueva queda vacía desde el formulario

**Error actual del editor · gravedad media · confianza alta · P2, antes de producir formas personalizadas desde el panel.** Referencias: `addons/inventario_objetos/formulario_item.gd:573–596,617–622` (`_show_hitbox`, `_put_hitbox`), `scripts/inventory/inv_pickup_hitbox.gd:150–167` (`shape_problem`), `docs/net/guia_del_laboratorio.md:852`.

**Disparador y recorrido.** La guía ofrece «New ConvexPolygonShape3D» dentro del formulario. El recurso arranca sin puntos. El picker guarda el recurso en el borrador al cambiar la selección, pero el panel no conecta la apertura de ese recurso al Inspector ni muestra un control para sus puntos. La validación exige al menos cuatro puntos con volumen y hace bien en impedir guardar la forma vacía. Arrastrar un recurso ya construido desde FileSystem sí tiene un camino válido.

**Evidencia ejecutada.** En el plugin real, en una copia, asigné un recurso vacío a través de `resource_changed`. El picker tenía cero conexiones a `resource_selected`. Emití la señal de selección y el Inspector siguió con el mismo objeto nulo. La comprobación ejercitó el contrato del picker mediante señales, sin simular clics físicos.

**Corrección y verificación.** Dar acceso a las propiedades de la forma del borrador y actualizar previsualización y estado de guardado al cambiarla. Para recursos externos, mantener explícita la referencia compartida o editar una copia interna para evitar alterar otro ítem por arrastre. Crear desde el picker, editar cuatro puntos válidos, guardar y reabrir. Después duplicar y cambiar la forma interna de la copia y comprobar la del original.

### AG-02 — Ocho contactos descartados pueden tapar un candidato elegible

**Riesgo futuro concreto · gravedad media · confianza alta · P2, antes de poblar áreas densas con hitboxes grandes o desplazadas.** Referencias: `scripts/inventory/inv_net.gd:61–67,443–481,496–543`, `scripts/inventory/inv_pickup_hitbox.gd:31–37,119–145`.

**Disparador y recorrido.** El selector obtiene hasta ocho resultados de cada recorrido. Después descarta los que no están en la réplica, son predichos, están fuera de alcance o fuera de vista. Con ocho áreas personalizadas interceptadas cuyos objetos no son elegibles, nunca se devuelve el noveno resultado, aunque esté al alcance y a la vista. Los rangos válidos del editor permiten formas adelantadas respecto de su objeto. Cambiar solo el límite retrasa el caso.

**Evidencia ejecutada.** Con ocho áreas válidas que se cruzaban por delante del objetivo pero tenían su objeto fuera de alcance, los ocho UID llenaron la lista y `interaction_target` devolvió vacío. Quité una de las ocho áreas y, con el actor y la mira en el mismo sitio, devolvió el UID 50 del objeto elegible. Es un escenario sintético, no un problema observado en la densidad actual del nivel.

**Prevención y verificación.** Separar el presupuesto de consulta de la regla de elegibilidad. Filtrar por origen alcanzable, área activa y límite de oclusión antes de llenar la lista, o avanzar el recorrido hasta hallar un candidato elegible con una política de saturación medible. Mantener un desempate estable si hay contactos coincidentes. Probar más de ocho descartes, una mezcla de modelo y caja, y un descarte causado por una pared. Cuando haya muchos ítems en estanterías o depósitos, la geometría de autoría dependerá de esta regla y corregirla después exigiría revisar escenas ya ajustadas alrededor del límite.

### REND-01 — El trabajo de la mira crece con todos los objetos sueltos

**Riesgo futuro concreto · gravedad media · confianza alta en el mecanismo · P2, antes de integrar niveles con mucha utilería.** Referencias: `scripts/interaction/interact_indicator.gd:64–85` (`refresh`), `scripts/inventory/inv_ui.gd:396–429`, `scripts/inventory/inv_net.gd:496–543,786–820`, `scripts/inventory/inv_world_item.gd:25–34,134–160`, `scripts/inventory/inv_visuals.gd:79–95`.

**Disparador y recorrido.** Cada cuadro activo del indicador consulta el selector. Con margen positivo, construye dos listas de exclusión y copia en ellas los RID de todos los modelos o de todas las hitboxes de la réplica. Entrega esas listas a las consultas repetidas. El número de iteraciones está acotado, pero preparar el filtro crece con el total de áreas vivas aunque la cámara mire un pasillo vacío. Ante un cambio del mundo, `_sync_world_views` también repasa las vistas y reconstruye ambos listados. Además, la primera aparición de un tipo sin hitbox genera una forma cóncava con todos los triángulos visuales. Se reutiliza la forma por definición, aunque la caché estática retiene las definiciones y sus recursos.

**Evidencia por inspección.** Las copias están antes de saber qué toca la mira. El barrido y el rayo repiten consultas y el HUD vuelve a pedir el resultado por cuadro. Las listas se repueblan recorriendo todas las vistas. El modelo con `get_faces()` entra como colisión de selección y no como colisión de movimiento. No se midió un umbral de FPS ni se atribuyó el costo a tráfico de red.

**Prevención y verificación.** Separar las máscaras de modelo y hitbox en capas reservadas elimina las exclusiones masivas. Mantener entre intentos solo los RID ya consultados y decidir el alcance de la caché antes de cambiar catálogos o niveles en una misma ejecución. Comparar con el mismo catálogo objetos cercanos frente a objetos lejanos y registrar tiempo de consulta, costo de aparición y memoria tras recargar un nivel. Hacerlo antes de fijar capas de un juego mayor o de poblar catálogos con modelos densos evita migrar máscaras, escenas y recursos ya publicados.

### OBJ-02 — Editar la caja borra la marca de cambios de la zona

**Error actual del editor, previo a esta incorporación · gravedad media · confianza alta sobre el síntoma · P2, antes de editar mapas extensos con el panel.** Referencias: `addons/inventario_objetos/guardado.gd:599–658,667–674`, `addons/inventario_objetos/objetos_panel.gd:660`, `addons/inventario_objetos/pruebas/prueba_del_creador.gd:966–995`.

**Disparador y recorrido.** Con la zona abierta, mover un marcador mediante el historial del editor y guardar después la escena de una caja colocada. `save_box` detecta la zona sucia, cambia de escena para guardar la caja, vuelve y evita llamar a la recarga explícita de esa zona. Aun así, en la prueba la zona deja de figurar en `get_unsaved_scenes()` tras unos cuadros. El panel consulta ese estado para mostrar «Guardar la zona».

**Evidencia ejecutada.** Falló tanto en HEAD como en el árbol local con Godot 4.7.2 headless. El aviso de zona sucia salió, el marcador conservó su posición nueva en memoria y el guardado explícito posterior persistió esa posición. La prueba establece la pérdida de la indicación, no pérdida de datos. Queda por aislar si el editor limpió el historial, reabrió la escena o guardó antes de tiempo durante el cambio de pestaña.

**Corrección y verificación.** Registrar versión del historial y bytes de la zona en disco antes de abrir la caja, al regresar y tras unos cuadros. A partir de eso, ajustar el retorno a la pestaña o el modo de editar la escena de caja para preservar el estado sucio. Verificar en editor con ventana que sigue disponible guardar la zona, que su archivo cambia al guardar explícitamente y que Ctrl+Z revierte el movimiento.

### DOC-01 — Los contratos de Tab y Show Label tienen texto vigente contradictorio

**Discrepancia documental · gravedad baja · confianza alta · P3.** Referencias: `docs/net/inventario_de_grilla.md:593`, `docs/net/hud_salud_estamina_y_estados.md:990–1001`, `scripts/inventory/inv_ui.gd:179–185,300–311`, `scripts/inventory/inv_pickup_spawn.gd:31–37`, `scripts/inventory/inv_net.gd:853–865`, `scripts/inventory/inv_authority.gd:84–106`.

**Evidencia y consecuencia.** Inventario todavía dice que E y Tab hacen lo mismo con caja abierta. El HUD del 08/11 y las pruebas confirman que E cierra inventario y caja, y Tab cierra solo la caja. El comentario de `show_label` afirma que el valor entra en la huella. `fingerprint_text` enumera tipo, cantidad, estado y posición del marcador, pero no su cartel. El host transmite la opción en la entrada del mundo, así que la ausencia de huella de ese dato visual no prueba divergencia durante una partida.

**Corrección y verificación.** Actualizar el texto de inventario y el comentario del marcador para reflejar las reglas vigentes. Una prueba breve debe comprobar Tab y E por separado y verificar que cambiar solo el cartel conserva la huella y que el cliente ve el valor enviado por el host, si se mantiene ese contrato visual.

## 3. Seguimiento de auditorías anteriores

| ID del 04/11 | Estado verificado |
| --- | --- |
| INV-01 | Resuelto en el caso reportado. `fill_input` reenvía la lista acotada y `use_before_step` recorre números en orden. Pasaron las pruebas de estados, modelo y uso instantáneo con pérdida. |
| INV-02 | Resuelto en el caso reportado. `use_before_step` espera el pedido anterior y `InvNet._physics_process` espera el uso anterior. La suite instantánea probó la inversión de llegada a +300 ms y 8 % de pérdida. |
| INV-03 | Resuelto en el recorrido probado. `InvReplica._rebuild_shown` reúne operaciones y usos por `order`. `inv_model_test` pasó 92/92. |
| INV-04 | Resuelto en los casos previos a movimiento y en el tick del daño. `ActorMotor.step` pasa la muerte de ese tick a `ActorPowers.step`. `estados_test` pasó 129/129. |
| PRU-01 anterior | Resuelto en los dos arneses reportados. Ejecuté `inv_pair_test` e `inv_instant_test` sin cliente con `--inv-timeout=3`. Ambos reportaron 0 comprobaciones, 3 fallas y salida 1. El PRU-01 de este informe es una causa distinta. |
| ARQ-01 | Mitigado para el contrato actual. `InvAbility.predictable` habilita predicción explícita, y `_predict_use` reconstruye pila y barra desde copias. La curación de partes comparte comprobaciones con el host. |
| EDT-01 | Mitigado para escenas con scripts de nodo. `InvVisuals.usable_model/has_scripts` inspeccionan el árbol empaquetado antes de instanciar. Pasó la suite de modelo. |
| ESC-01 | Mitigada la frecuencia de refresco del piso, con señal separada de mundo y un envío por tick de usos. Sigue habiendo reconstrucción de grillas con predicción pendiente y recorridos del mundo ante cambios. REND-01 agrega un costo nuevo en el camino por cuadro. |
| ESC-02 | Abierto y diferido por decisión registrada en el historial, sección 8.42. `SimClock.add_world_slow/world_scale:149–177` conserva y recorre tramos de toda la sesión. Retomar para partidas largas o guardadas, con una ventana que respete el replay y la entrada tardía. |

Del informe de parkour del 30/10 repetí el agarre por encima del filo, mantle y replay, por la dependencia de movimiento, cámara y Tuning. Las pruebas específicas de agarre y mantle pasaron. El replay volvió a coincidir byte a byte consigo mismo. El resto de los límites de adopción y plataformas de ese informe queda como antecedente. El diff de esta entrega en movimiento solo agrega el margen de mira a Tuning y no justifica reabrirlos como regresiones nuevas.

## 4. Pruebas ejecutadas y límites

Todo se ejecutó en copias temporales del árbol de trabajo, salvo la lectura de Git y archivos. Las corridas de referencia repusieron blobs de HEAD en otra copia, sin cambiar de rama. Para las pruebas de red usé procesos independientes en loopback. Las cifras corresponden a las comprobaciones que realmente imprimió cada arnés.

| Prueba | Condiciones y resultado |
| --- | --- |
| `inv_hitbox_test` | Solo, 74/74. En pareja, host 8/8 y cliente 6/6. Con hitbox distinta, host 2/2 y cliente 2/2, rechazo por la parte de inventario de la huella. |
| `inv_indicador_test` y `inv_model_test` | 164/164 y 92/92. |
| `inv_lab_test` | Árbol local 165/176, salida 1. HEAD 165/166, salida 1. Ver PRU-01. |
| `inv_visual_test` | Ventana, Forward+ y D3D12. 10 miniaturas generadas, cero fallas de render. 9/10 comprobaciones, salida 1. Imagen cuadrada y proporción correctas en las comprobaciones que las ejercitan. Ver PRU-01 para el caso de reutilización. |
| `prueba_del_creador` y `prueba_del_creador_juego` | Editor headless, después juego en la misma copia con los recursos que generó el editor. Editor 212/217, salida 1. Su versión de HEAD dio 164/165, salida 1. Juego tras el editor 38/38. Correr juego por separado en una copia sin los recursos generados produjo fallas por datos faltantes, así que esa corrida no cuenta como regresión. |
| `inv_abrir_caja_test` | Dos procesos con +200 ms de RTT simulado. Host 73/73, cliente 70/70. |
| `inv_partes_test` | Dos procesos con +200 ms de RTT simulado. Host 1/1, cliente 29/29. |
| `inv_instant_test` | Dos procesos con +300 ms de RTT y 8 % de pérdida simulada. Host 1/1, cliente 83/83. |
| `inv_pair_test` | Host 18/18, A 24/24, B 7/7. A con +120 ms, jitter ±40 ms, 2 % de pérdida, relevo y corte de 8 s. B arrancó después de que el host soltó la pila. Un primer intento arrancó B antes de ese evento y dio cinco fallas en su guion. La corrida temporizada por el evento completó entrada tardía, carrera por la pila, reconexión y limpieza. |
| `estados_test`, `integridad_test` | 129/129 y 106/106. |
| `grab_above_test`, `mantle_test`, `actor_replay_test` | 22/22, 50 casos correctos y replay con huella `38989aaf9fd19d18`, coincidente byte a byte. La primera corrida de replay llegó al límite externo de 60 s. La repetición con un límite de 210 s terminó con salida 0. |
| Reproducciones acotadas | Solapamiento inicial y ocho áreas antes del UID elegible mediante los componentes reales de selección. Pedido vencido, snapshot tardío y Tab seguido del estado de E mediante UI y réplica reales. Selector de formas del editor mediante señales. |
| Exportación Windows release | Generé el ejecutable con el preset «Laboratorio co-op (Windows)» en una copia. Arrancó en modo host, imprimió la huella esperada y escuchó en loopback. La plantilla release bloquea `--scene`, por lo que la prueba dedicada de hitbox se ejecutó con el motor y la copia, y el release se verificó por su entrada normal. |

El editor headless imprimió advertencias de texturas de viewport y el probe corto registró advertencias de recursos al salir. Los traté como diagnósticos de esas corridas, con alcance separado de las aserciones de juego y de los resultados de render con ventana. La auditoría no incluyó prueba entre dos PC físicas, VPN, uso manual del gizmo, ni perfil de carga en la notebook. Para cerrar integración física, exportar una misma copia para ambas PC, marcar y recoger un ítem de modelo y otro con hitbox desde ambas cámaras, soltar y volver a recoger, repetir con una pared entre medio y comprobar la barra. Para el editor, repetir OBJ-01 y OBJ-02 con ventana y cambios visibles en el Inspector y las pestañas.

## 5. Orden de intervención

1. **Antes de seguir ampliando**, desacoplar las pruebas de los datos editables del machete y ajustar el conteo de las dos raíces. Así las correcciones siguientes recuperan una señal de regresión interpretable.
2. **Antes de seguir ampliando**, corregir AG-01 en el selector común y cubrir la posición inicial solapada. Luego resolver CAJ-01 antes de sumar otros contenidos al panel derecho, cuando todavía es sencillo probar todo el ciclo de apertura.
3. **Antes de integrar al juego**, completar la autoría de formas personalizadas y verificar el estado de guardado al editar escenas de caja. Atender el filtrado de candidatos y las capas de mira antes de niveles densos. Los dos cambios de selección deben probarse juntos con modelos, hitboxes y oclusión.
4. **Puede esperar** la limpieza de texto de DOC-01. Mantener ESC-02 diferido hasta que haya sesiones largas o persistencia. Su corrección depende de definir cuánto historial requieren la repetición de ticks y los jugadores que se incorporan tarde.

La única escritura de esta auditoría en el repositorio fue este informe. Los cambios locales, incluida la eliminación anterior del informe de parkour, se conservaron.
