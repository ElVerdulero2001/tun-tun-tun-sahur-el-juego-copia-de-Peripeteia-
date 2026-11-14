# Auditoría de interacción, inventario y editor de objetos

Fecha: 2026-11-12. Revisión sin cambios de implementación.

## Resultado

El rayo de la mano resuelve los casos geométricos probados, incluido el objeto que asoma de un estante. Las pruebas habituales de inventario, cajas, consumibles, integridad, selector de habilidades y editor pasaron. También pasaron la competencia por una pila, la entrada tardía y la reconexión en procesos separados.

Encontré **un error actual en el contrato temporal de la interacción**, dos riesgos concretos al ampliar contenido y una discrepancia documental. No confirmé duplicación ni pérdida de objetos en los recorridos ejecutados. Eso no certifica todas las combinaciones posibles.

| ID | Hallazgo | Clasificación | Gravedad | Confianza | Intervención |
| --- | --- | --- | --- | --- | --- |
| INT-01 | Esperar un tick no garantiza haber recibido su input ni consultar la pose de ese tick | Error actual, con documentación que promete más | Media: rechazos de interacción y reversión visual | Alta: inspección y reproducción aislada | P1, antes de ampliar la interacción |
| REND-02 | Los dos rayos del selector recorren todos los objetos, incluso los lejanos | Riesgo futuro concreto | Media: presupuesto de CPU por cuadro | Alta sobre el mecanismo; medición sintética | P2, antes de mapas con muchos objetos |
| DAT-01 | Un modelo sin geometría pasa la validación y deja un objeto sin representación ni agarre | Riesgo futuro concreto de contenido | Media: contenido que no se puede recuperar con E | Alta: validación y geometría ejecutadas | P2, antes de ampliar el catálogo |
| DOC-02 | Instrucciones activas todavía describen hitbox de selección y protocolo de enteros | Discrepancia documental | Baja | Alta por contraste directo | P3, próxima actualización documental |

Gravedad describe la consecuencia; confianza, la calidad de la evidencia; prioridad, cuándo conviene intervenir. No identifiqué un hallazgo crítico ni un motivo para rehacer el inventario completo.

## 1. Estado y alcance exactos

### Repositorio e incorporación elegida

- Repositorio: `C:\Users\ElCaido97\Documents\tun-tun-tun-sahur`.
- Rama: `net-lab-auditoria-hitbox`.
- HEAD: `e95cd37f30e4f3fd49bb76d31b898bc551e2c3f5`.
- El último commit es documental. La incorporación funcional principal es `32fc04482deb8a3d6403b2aba554bc65fb47c77b`: rayo de la mano, alcance común, cambios de hitbox/editor y correcciones de la auditoría del 08/11 reunidos en una entrega. Su padre, `b6b1bfc`, sirve para identificar ese paquete de cambios, **no para atribuir todos sus cambios exclusivamente al rayo**. No existe un commit intermedio que aísle todas sus etapas.
- Integración vecina revisada: `06aba6e` (zoom numérico), `b6b1bfc` (luces del HUD), `e9468d7` (radial con Q), `cfc8760`/`8ae157b` (ciclo de cajas), y las dependencias de predicción, consumibles y salud ya existentes. Las auditorías del 04/11 y 08/11 aportan el contexto para distinguir regresiones de problemas anteriores.

### Estado local conservado

Al comenzar, el único cambio rastreado era la eliminación local de `docs/net/auditoria_parkour_2026-10-30.md`; el índice no tenía cambios preparados. Había 501 archivos sin seguimiento: 288 en `archive/`, 208 en `tmp/`, cuatro en `output/` y `project.godot~RF78902d2f.TMP`.

No había cambios locales de implementación rastreados que sumar al diff. Inventarié esas rutas nuevas y comprobé que el código del alcance no referencia `res://tmp/`, `res://archive/` ni `res://output/`. Son copias/salidas auxiliares y el preset las excluye; no las traté como implementación activa. El archivo temporal de configuración tampoco reemplaza a `project.godot`. No borré ni restauré esas rutas. Consulté el informe de parkour eliminado mediante su blob de HEAD.

La única incorporación al repositorio por esta tarea es este Markdown. No hubo cambio de rama, commit, push, limpieza ni modificación de código, escenas, recursos, assets o configuración originales.

### Instrucciones, fuentes y configuración

Apliqué las instrucciones de proyecto entregadas en el turno. La búsqueda local de `AGENTS.md`, tanto en el repositorio como en sus directorios ascendentes, no aportó instrucciones adicionales. La autorización de esta auditoría prevalece sobre la antigua regla documental de hacer commits después de una prueba.

Empecé por `guia_del_laboratorio.md` y reconstruí el alcance con Git, `problema_objeto_sobre_un_borde.md`, `problema_alcances_del_inventario.md`, `inventario_de_grilla.md`, las secciones pertinentes de `hud_salud_estamina_y_estados.md`, el roadmap y las auditorías anteriores. Identifiqué también los tres prompts originales de inventario, HUD y creador de objetos, y contrasté sus contratos pertinentes con las decisiones posteriores. Del historial `arquitectura_coop_y_esqueleto_de_red.md` usé especialmente 8.37–8.42 y los pendientes de inventario; sus notas antiguas no se tomaron como definición vigente del rayo.

Configuración verificada en archivos y ejecutable:

| Elemento | Estado real |
| --- | --- |
| Versión declarada | Godot 4.7, `project.godot:15` |
| Motor ejecutado | `4.7.2.stable.official.ed1daf0bf`, comprobado con `--version` |
| Física / render configurados | Jolt Physics / Forward Plus; D3D12 en Windows |
| Arranque del laboratorio | Su escena explícita; variante `run/main_scene.lab_coop` para el preset Windows |
| Plugin | Objetos, `addons/inventario_objetos/plugin.cfg`, habilitado |
| Autoloads | `UIHacking` y `DebugDraw`, preexistentes; el inventario no agregó uno |
| Alcance guardado | `interaction_range = 2.7` en el Tuning de `net_lab.tscn`; valor por defecto 2.0 |
| Exportación configurada | Preset Windows `lab_coop`, scripts en texto y exclusión de carpetas auxiliares |

No se usó la versión del juego anterior como referencia.

### Decisiones que se respetan

El usuario decidió el rayo directo desde los ojos, el primer contacto, medir hasta ese contacto, la ausencia de margen y de ayuda con varios rayos, conservar la hitbox guardada sin usarla para recoger, los dos pasos de mira/mano y medir también desde los ojos para mantener una caja abierta. No son errores que los objetos chicos exijan puntería ni que una caja abierta pueda usarse sin mirarla. Tampoco se exige ahora física de objetos sueltos, guardado de partidas, migración de host, termómetro de luz ni integración con el juego anterior.

La espera del tick, el uso de `TriangleMesh`, los detalles de caché y el recorrido de todos los objetos son elecciones de implementación documentadas como tales. El zoom numérico y las nuevas reglas de luces y Q también están pedidos y registrados. La pérdida del historial de deshacer al reconstruir ciertas escenas de cajas tiene una mitigación y un aviso aceptados; no se vuelve a presentar aquí como una regresión nueva.

## 2. Recorridos revisados y protecciones existentes

**E e indicador.** `LabCamera.aim_ray` entrega la línea de cámara; `InvUI._look_target` y `interaction_focus` usan `InvNet.interaction_target`. Este hace un rayo para obtener el punto de la mira y otro desde los ojos. Ambos usan `InvReach.first_hit`: física para nivel/cajas y triángulos del catálogo para objetos. El cono de tercera persona sigue siendo una selección local. El indicador y E comparten el selector. La presentación predicha excluye lo recogido localmente y no hace recogibles los drops aún no confirmados.

**Pedido y autoridad.** `InvUI.pick_up_world/open_box` mandan UID/ID, dirección y tick mediante `InvProtocol.aimed_args`. El protocolo comprueba forma y tipos, y la autoridad valida finitud y normalización de dirección. `InvNet` ordena números de pedido, espera dependencias con usos e intenta esperar el tick. `InvAuthority._reach_reason` consulta su propio estado, catálogo y mundo; exige que el primer contacto coincida con el objetivo solicitado y revalida alcance. Por eso INT-01 no permite elegir arbitrariamente otro objeto ni suprime las paredes del host.

**Mutación, réplica y presentación.** La inserción/transferencia ocurre en la autoridad; `InvOps` valida grillas y versiones. Los resultados y snapshots viajan numerados y la réplica los aplica en orden. La recogida puede ser parcial; lo rechazado vuelve a representarse desde el estado confirmado. La UI no es dueña del inventario autoritativo. Los tests de competencia por una pila y de predicción no mostraron duplicación en sus casos.

**Cajas.** Abrir reserva directamente el panel derecho. La intención de apertura tiene número propio (`_want_seq`, `_want_box`, `_want_answered`); dejarla con Tab, E o timeout envía cierre y descarta la presentación tardía. Una caja abierta se revalida al operar y en `watch_access`; desaparecer o alejarse cierra su acceso. La prueba de cajas cubrió Tab, aperturas canceladas y reapertura con la respuesta anterior en viaje.

**Salud, estados y red.** Los usos se conservan hasta confirmación, viajan en el input y respetan el pedido anterior; los pedidos respetan el uso anterior. La predicción y el host aplican la capacidad con pila/barra propias. La curación de partes valida parte y consumible antes de gastar. La adopción compara salud, integridad, muertes, efectos y número de uso, por lo que no adopta sin más una curación que el host rechazó. Muerte y agotamiento mantienen prioridad y apagado en los casos probados.

**Editor y datos.** Definición, pila y colocación siguen separadas; los borradores se copian y el guardado conserva la identidad de recursos editados. La edición de formas externas advierte el uso compartido y permite copia propia. Las miniaturas de grilla y barra tienen encuadres diferenciados y el dibujo mantiene proporción. El marcador usa solo posición al crear el objeto, coherente con su preview. No encontré una dependencia nueva del panel que deba ejecutarse para recoger en runtime; el host consulta datos y geometría, no las vistas de su propia pantalla.

## 3. Hallazgos ordenados por intervención

### INT-01 — El tick del pedido no fija el estado con el que se lanza el rayo

**Clasificación:** error actual del contrato de sincronización; incluye una promesa documental incorrecta. **Gravedad:** media. **Confianza:** alta sobre el mecanismo y las reproducciones; frecuencia en partidas sin medir. **Prioridad:** P1, antes de ampliar las acciones que dependen de apuntar mientras se mueve el personaje.

**Referencias:**

- `scripts/net/net_sync.gd:221–241`, `input_for`: distingue internamente el tick original usado, pero devuelve un input nuevo con el tick solicitado por la simulación.
- `scripts/inventory/inv_net.gd:265–273,308–313,492–497,649–687`: captura `_input_tick`, registra `_stepped` y usa ese registro como barrera.
- `scripts/inventory/inv_authority.gd:569–582`, `_reach_reason`: toma los ojos del estado actual, sin recuperar una muestra del tick pedido.
- `scripts/net/sim_clock.gd:249–263`: secuencia de simulación del actor.
- `scripts/inventory/inv_ui.gd:361–370,400–411`: captura dirección y tick al pedir.
- `docs/net/problema_objeto_sobre_un_borde.md:49–60,97`; `docs/net/inventario_de_grilla.md:178`: explican la espera como si diera la pose del instante de E.
- `scenes/net_lab/inventario/pruebas/inv_alcance_test.gd:1346–1354,1452–1462`: la prueba de pareja se detiene y espera antes de recoger.

**Disparador y recorrido.** Hay dos síntomas de la misma falta de asociación entre pedido y muestra autoritativa:

1. Si falta el input T, `NetSync.input_for(peer,T)` repite uno anterior y devuelve un objeto con `tick=T`. `use_before_step` registra T en `_stepped` igualmente. El pedido que esperaba el input T deja de esperar, aunque no se recibió. El registro mide hasta dónde avanzó la simulación, no qué input llegó.
2. Si el pedido llega cuando el host ya pasó T, la comparación `_stepped >= T` permite procesarlo. El rayo usa la pose actual. No hay historia de ojos/postura por tick ni una consulta ejecutada en el T del pedido. Por eso esperar solo «al menos T» tampoco reconstruye la pose de E en una entrega tardía sin pérdida de input.

**Protecciones buscadas.** Revisé `_used_input_tick`, el buffer de inputs, adopción, orden de pedidos, timeout y `_reach_reason`. `_used_input_tick` sí retiene la distinción correcta, pero la barrera de inventario no lo usa. Adopción puede reducir diferencias de movimiento; no guarda la pose consultable de T ni reintenta una recogida ya rechazada. El límite de tres segundos impide quedar bloqueado indefinidamente, pero no resuelve el vínculo temporal. La autoridad conserva las comprobaciones de geometría, identidad y distancia.

**Evidencia ejecutada.** Un probe temporal heredó el arnés real de alcance y usó `NetSync`, `InvNet`, autoridad, réplica y geometría reales. Se detuvo el avance automático para controlar la entrega; no fueron dos PC ni una medición de frecuencia de red:

```text
input_original=900 input_reconstruido=901 stepped=901
pedido_tick=901 respuesta=[true, ""] cola=0

selector_en_E=29 solicitado=29 tick_E=1000 tick_host=1003
desplazamiento=0.3 respuesta=[false, "no lo ves desde ahí: hay algo en el medio"]

misma_direccion_pose_original=[true, ""]
```

En el primer caso solo existía el input 900 en el buffer: se procesó la recogida sin recibir 901. En el segundo, el selector eligió el bloque en la pose de E; antes de procesar el pedido se desplazó en memoria al actor 30 cm de costado y se avanzó el registro tres ticks. El host rechazó esa dirección. Volver a la pose inicial y repetir la misma dirección permitió recoger. Esto aísla el efecto de usar la pose posterior; no afirma que esos tres ticks se hayan recorrido caminando en una red real.

**Consecuencia.** Puede marcarse un objeto y mostrarse recogido, para luego volver al piso con un mensaje de pared o puntería que no describe lo que vio el jugador al apretar E. También afecta abrir cajas. No se demostró pérdida permanente de inventario ni duplicación: el rechazo conserva el estado autoritativo. La nota documental sobre inputs perdidos reconoce parte de la limitación, pero no la falsa equivalencia entre simular T y recibir T ni el caso de consulta posterior.

**Corrección mínima e implicaciones.** Separar «último tick simulado» de «último input realmente usado/recibido» y probar expresamente ambos. Para sostener la promesa de consultar la pose de E, asociar la interacción a una muestra autoritativa de ese tick: ejecutarla al llegar a ese tick cuando el pedido ya esté disponible, o conservar una ventana acotada de ojos/postura para pedidos tardíos. Explicitar qué pasa fuera de la ventana y con una muestra basada en input repetido. No hace falta rebobinar todo el mundo; sí fijar si la oclusión se valida con el mundo actual y conservar las reglas de identidad, acceso y orden. Un getter de `_used_input_tick` arregla la barrera falsa, pero por sí solo no arregla el segundo síntoma.

Si se opta por validar siempre desde la pose actual como límite provisional del laboratorio, documentarlo así y aceptar expresamente esos rechazos; no describirlo como pose del tick solicitado. No recomiendo recuperar el margen ni los puntos auxiliares que el usuario decidió quitar.

**Comprobación de cierre.** Añadir una prueba con T ausente y T−1 presente; otra con el pedido T recibido cuando el host está en T+3; otra con cambio de postura entre ambos. Verificar UID del indicador, origen autoritativo de la consulta, motivo de rechazo, reversión y que no se aplique dos veces. Luego repetir con cliente en movimiento lateral y E sobre un objeto pequeño, con jitter y sin pérdida, y con pérdida. La prueba existente quieta debe seguir pasando.

**Costo de postergación.** Si puertas, terminales, objetos móviles o acciones de combate copian este contrato, el tick quedará interpretado de manera distinta en cada acción. Conviene fijar ahora la semántica y una prueba de entrega tardía compartida, antes de extender el protocolo.

### REND-02 — Mirar un espacio vacío cuesta según todos los objetos del mapa

**Clasificación:** riesgo futuro concreto. **Gravedad:** media. **Confianza:** alta en el mecanismo; medición sintética, sin umbral de FPS validado en la notebook. **Prioridad:** P2, antes de integrar mapas con cientos/miles de recogibles.

**Referencias:** `scripts/interaction/interact_indicator.gd:64–85`; `scripts/inventory/inv_ui.gd:417–453`; `scripts/inventory/inv_net.gd:450–461`; `scripts/inventory/inv_reach.gd:66–107,118–123,190–212`; `docs/net/problema_objeto_sobre_un_borde.md:98,101–113`.

**Disparador y recorrido.** El indicador pide el selector por cuadro. Este hace dos consultas y cada una enumera todo `world`. Se busca la definición y su geometría antes de comprobar la caja del objeto. Los objetos lejanos no llegan a la consulta de triángulos, pero igualmente pagan esa enumeración, búsquedas y transformación del segmento. El host también hace el recorrido global para validar cada pedido.

**Mecanismos que sí reducen costo.** La `TriangleMesh` se construye una vez por definición; la AABB descarta antes de consultar sus triángulos; no se crean nodos para cada consulta y la caché de `InvReach` se limpia al salir `InvNet`. No se están reconstruyendo todas las mallas cada cuadro. Sin embargo, no hay selección espacial previa por zona/celda/distancia.

**Evidencia ejecutada.** En el probe aislado se reutilizó un único tipo con `BoxMesh`, todos sus objetos a más de 10 km, mismo rayo de 2 m sin contacto con ellos. Tras calentar la caché se hicieron 300 consultas por tamaño:

| Objetos en `world` | Tiempo medio de un `first_hit` |
| --- | --- |
| 27 | 48 µs |
| 270 | 499 µs |
| 2700 | 5118 µs |

Son medidas de esta PC y esta carga sintética, no estimaciones de una exportación ni del hardware objetivo. La prueba mide **un rayo**, no el cuadro completo: el selector normalmente hace dos. La suite real de alcance también pasó sus 170 comprobaciones y midió un selector económico con 27 objetos. La documentación ya reconoce la limitación; la medición muestra que alejar el contenido no evita el costo.

**Consecuencia y crecimiento relevante.** Poblar otras habitaciones o zonas descargadas visualmente puede encarecer la mira actual aunque nada nuevo esté cerca de la pantalla. Aumentar el render culling no resuelve ese recorrido de diccionario. Más jugadores agregan consultas autoritativas al interactuar; no se afirma un tráfico de red por cuadro causado por estos rayos.

**Prevención mínima e implicaciones.** Antes de ese crecimiento, mantener una selección espacial de candidatos a partir de las altas/bajas y posiciones autoritativas, y consultar solo las celdas que cruza el segmento. Compartir el contrato entre host y cliente y preservar el desempate y el primer contacto con nivel/cajas. Puede conservarse la implementación actual como referencia de corrección. No hace falta sustituir `TriangleMesh` ni agregar física dinámica.

**Comprobación de cierre.** Comparar mismo contenido cercano con cantidades crecientes de contenido lejano, mirando cielo, piso y objetos. Medir selector completo y consulta del host, y contrastar el resultado contra la versión de recorrido completo. Incluir recoger/rechazar/soltar, entrada tardía y limpieza al cambiar de mundo para comprobar que el índice no conserva candidatos muertos.

**Por qué después cuesta más.** El actual diccionario del mundo ya alimenta picking, predicción y presentación. Si múltiples sistemas pasan a modificarlo directamente, introducir un índice coherente exige revisar cada alta y baja. Centralizar ahora ese contrato y dejar el caso de carga como referencia evita depender del costo global sin obligar a optimizar el laboratorio de 27 objetos inmediatamente.

### DAT-01 — Un modelo vacío se acepta, pero no tiene representación recuperable

**Clasificación:** riesgo futuro concreto de autoría; no se identificó un ítem actual roto del catálogo en las suites. **Gravedad:** media. **Confianza:** alta sobre la reproducción. **Prioridad:** P2, antes de ampliar el catálogo o importar contenido en volumen.

**Referencias:** `addons/inventario_objetos/guardado.gd:77–145` (`check_item`); `scripts/inventory/inv_catalog.gd:25–43` (`problems`); `scripts/inventory/inv_visuals.gd:22–43,101–118,138–144`; `scripts/inventory/inv_reach.gd:88–91,190–211`; `scripts/inventory/inv_world_item.gd:28–43`.

**Disparador y recorrido.** Asignar un `.tscn` válido sin mallas visibles, por ejemplo una raíz `Node3D` vacía. La validación comprueba que `model` sea una `PackedScene`, pero no que la apariencia resultante tenga triángulos. `has_visual` da true porque existe una escena utilizable y sin scripts. Por eso `world_model` elige `fitted`, que devuelve el contenedor vacío, en vez de la caja de reserva. `InvReach` obtiene cero vértices, guarda una malla null y descarta ese objeto en todos los rayos.

**Validaciones existentes revisadas.** La protección de modelos con scripts sí produce fallback y aviso; no evita este caso sin scripts. Las validaciones de hitbox tampoco ayudan: la hitbox ya no participa en el agarre por decisión vigente. El cartel puede revelar el nombre, pero no aporta geometría que E pueda tocar. La huella hace coincidir a las PC incluso si ambas tienen la misma geometría vacía.

**Evidencia ejecutada.** Se empaquetó un `Node3D` vacío en memoria, se asignó a una `InvItemDef` con ID/nombre/tamaños válidos y se ejecutaron las validaciones y la construcción reales:

```text
errores_guardado=[] avisos_catalogo=[] has_visual=true
vertices=0 malla_interaccion=<null>
```

Se comprobó la validación de edición con `check_item`; no se guardó ese recurso en el repositorio ni se atribuyó un error a los ítems existentes. Es el mismo camino geométrico usado por el host, sin depender del render headless.

**Consecuencia.** Un contenido que el panel considera válido puede soltarse o colocarse y permanecer como entrada autoritativa sin modelo seleccionable. Con `show_label=false` tampoco hay cartel. No es pérdida por transferencia en red: el objeto sigue en el estado, pero el jugador no puede recuperarlo con el mecanismo normal.

**Prevención mínima e implicaciones.** Al validar contenido, comprobar la geometría que realmente genera `InvVisuals`, no solo la existencia del archivo. Rechazar o avisar con una política explícita; si se permite el contenido, aplicar el mismo placeholder en visualización y consulta del host. Mantener válido el caso habitual «sin modelo», que ya tiene caja. No validar haciendo instanciar escenas que la protección de scripts considera inseguras.

**Comprobación de cierre.** Casos con escena vacía, todas las mallas ocultas y malla sin triángulos; un modelo válido y uno sin modelo como controles. Según la política elegida, debe impedirse guardar/colocar o debe verse y recogerse un placeholder coherente en host y cliente. Comprobar también `show_label=false` y reabrir el contenido guardado.

**Crecimiento y costo posterior.** Se vuelve relevante con catálogos/importaciones mayores y prefabs reorganizados. Si se incorporan muchas entradas vacías y luego partidas guardadas que las referencian, habrá que corregir también el contenido y su recuperación. Prevenirlo en la validación del editor es más pequeño que reparar ese estado después.

### DOC-02 — Quedan contratos activos del selector y protocolo anteriores

**Clasificación:** discrepancia documental. **Gravedad:** baja. **Confianza:** alta. **Prioridad:** P3; puede esperar a la próxima edición documental, salvo que se use como guía para ampliar estas APIs.

**Referencias y contraste:**

- `docs/net/guia_del_laboratorio.md:733` todavía presenta la sección Hitbox como la que define el volumen que elige la mira, sin marcar esa frase como histórica. La misma guía, líneas 740 y 878, explica correctamente que no participa; el código actual confirma esto.
- `docs/net/inventario_de_grilla.md:230` y `scripts/inventory/inv_protocol.gd:4–7` dicen «solo números enteros». Los argumentos actuales de PICKUP/OPEN requieren tres `TYPE_FLOAT` (`inv_protocol.gd:59,65,86–95,120–137`). No es una relajación del parser: las direcciones con enteros se rechazan.
- Los párrafos expresamente rotulados «hasta el 11/11» o «cómo era antes» no se cuentan como errores. La diferencia temporal del tick ya está agrupada en INT-01 y no es un quinto hallazgo.

**Disparador y consecuencia.** Retomar la guía por la sección del editor, o extender un constructor de pedidos siguiendo el encabezado del protocolo. Puede llevar a ajustar una hitbox que no afecta al juego o a fabricar paquetes que no cumplen el parser actual.

**Evidencia.** Inspección de esos textos frente a `InvReach`, a las tablas de tipos y a las pruebas de direcciones inválidas ejecutadas por `inv_alcance_test`. No se atribuye una decisión equivocada al usuario.

**Corrección mínima.** Identificar la hitbox como edición de datos conservados sin efecto actual y describir el mensaje como IDs/ticks enteros y dirección con componentes flotantes, sin nodos ni recursos. Mantener la historia antigua en su sección rotulada.

**Comprobación de cierre.** Una búsqueda de `Pickup Aim Margin`, `hitbox`, `solo números enteros` y `TYPE_FLOAT` debe dejar una única descripción vigente y distinguir explícitamente el comportamiento histórico. Conservar las pruebas de forma de protocolo y de hitbox sin efecto de selección.

## 4. Seguimiento de auditorías anteriores

Estados limitados a los casos y mecanismos comprobados ahora; no se trasladaron conclusiones antiguas automáticamente.

| Informe / ID | Estado en esta revisión | Evidencia actual |
| --- | --- | --- |
| 08/11, AG-01 | Causa retirada del runtime | No hay esfera/barrido de margen ni áreas de modelo; ahora se consulta el primer contacto por triángulos. Alcance 170/170 y hitbox 90/90 |
| 08/11, AG-02 | Límite antiguo retirado | Ya no hay lista de ocho candidatos que pueda agotarse. El problema de costo actual es REND-02 |
| 08/11, CAJ-01 | Resuelto en los casos reportados | `_want_seq` y cancelación común; inventario general 190/190 y caja host 85/85, cliente 80/80, incluidos pedidos cancelados y reapertura |
| 08/11, PRU-01 | Resuelto para las dependencias reportadas | Fixtures `inv_items_de_prueba.gd` y arneses ajustados; `inv_lab_test` pasa con el machete actual. El editor pasa 231/231. No se ejecutó el render visual de miniaturas con ventana |
| 08/11, OBJ-01 | Resuelto en el flujo automatizado de editor | Inspector/recurso editable, seguimiento de cambios y copia propia; comprobaciones de formas dentro de la suite 231/231 |
| 08/11, REND-01 | Causa de exclusiones masivas retirada; riesgo de escala persiste por otra causa | No se construyen exclusiones de todas las áreas; caché de `InvReach` liberada al salir. Ahora se enumera todo el mundo por rayo: REND-02 |
| 08/11, OBJ-02 | Mitigado; conserva el límite aceptado | `_keep_unsaved` vuelve a marcar las escenas reconstruidas y el guardado avisa que perdió el historial. La suite comprueba que la posición y el estado sin guardar se conservan |
| 08/11, DOC-01 | Contratos originales corregidos | Tab/E actuales diferenciados; `show_label` entra por `SimFingerprint.level_text`, no por `InvNet.fingerprint_text`. Pruebas actuales verifican ese comportamiento. DOC-02 es otro texto residual |
| 04/11, INV-01 / INV-02 / INV-03 | Correcciones conservadas en los casos probados | Reenvío de usos, dependencias entre canales y reconstrucción ordenada; modelo 92/92, estados 129/129 e instantáneo cliente 83/83 con pérdida |
| 04/11, INV-04 | Corrección conservada | Muerte transmitida a `ActorPowers.step`; estados 129/129 e integridad 113/113 |
| 04/11, PRU-01 | Corrección conservada | Sin cliente y con timeout de 3 s, `inv_pair_test` e `inv_instant_test` salen 1, con 0 comprobaciones y 3 fallas; no simulan éxito |
| 04/11, ARQ-01 | Mitigación del contrato actual conservada | `predictable`, copias de pila/barra en `_predict_use` y comprobaciones compartidas de partes; pruebas de modelo/instantáneo/partes |
| 04/11, EDT-01 | Mitigación conservada para scripts de nodo | `usable_model/has_scripts` inspeccionan la escena antes de instanciar. No significa que todo contenido geométricamente vacío esté validado: DAT-01 |
| 04/11, ESC-01 | Mitigación parcial conservada | Refresco de mundo separado de usos; aún se mandan snapshots completos de grilla al cambiar. No se hizo una nueva medición de ancho de banda y no se lo presenta como cerrado |
| 04/11, ESC-02 | Abierto y diferido por decisión registrada | `sim_clock.gd:149–177` conserva y busca tramos de cámara lenta de toda la sesión. Se mantiene el pendiente antes de partidas largas/guardadas; no se exige resolverlo en esta entrega |

Del informe de parkour del 30/10, H1/H2 tienen hoy pruebas específicas: agarre desde arriba 22/22 y mantle 50 casos correctos. No repetí el barrido completo ni replay; las reservas sobre adopción amplia y plataformas no se declaran cerradas por estas dos suites. El cambio de interacción no modifica esas reglas de movimiento. INT-01 sí cruza su contrato de inputs y por eso se revisó ese recorrido.

## 5. Pruebas ejecutadas y límites

### Método

Se trabajó en copias temporales del estado rastreado actual, incluyendo los archivos presentes en el árbol y omitiendo el informe ya eliminado. Se copiaron también los recursos importados necesarios. Las pruebas que escriben ítems y escenas se ejecutaron exclusivamente en una copia de editor. Su plugin de prueba se habilitó solo allí. Los probes y lanzadores adicionales también quedaron fuera del repositorio.

Se verificó la salida de los procesos y sus resúmenes, con límites externos de duración. Las escenas de un proceso que lo requieren se ejecutaron con `--fixed-fps 60`; las de red, sin aceleración de cuadros. La red fue loopback en esta PC, con procesos distintos. Las pérdidas y demoras citadas son las configuradas en el simulador de la aplicación, no mediciones de internet real.

### Resultados válidos finales

| Prueba | Condiciones | Resultado |
| --- | --- | --- |
| `inv_alcance_test` | Un proceso; geometría, ojos, estante, rayos, protocolo, cajas y tuning | 170/170, salida 0 |
| `inv_hitbox_test` | Un proceso, datos/editor y regla actual sin hitbox de selección | 90/90, salida 0 |
| `inv_lab_test` | Un proceso, inventario/UI/réplica/autoridad | 190/190, salida 0 |
| `inv_indicador_test` | Un proceso, seguimiento/proyección/selección | 164/164, salida 0 |
| `inv_model_test` | Modelo y operaciones de datos | 92/92, salida 0 |
| `estados_test` | Un proceso, incluyendo predicción, orden y muerte | 129/129, salida 0 |
| `integridad_test` | Un proceso, caídas/repetición/partes/luz | 113/113, salida 0 |
| `selector_test --selector=local` | Q e integración del HUD | 50/50, salida 0 |
| Alcance en pareja | Cliente +200 ms RTT, jitter ±40 ms, pérdida 5 %, semilla 141 | Host 8/8, cliente 24/24, ambos salida 0 |
| Rechazo por alcance distinto | Host y cliente con diferente Interaction Range | 2/2 en cada proceso; rechazo por Tuning |
| Rechazo por modelo distinto | Granada 1 cm mayor en el cliente | 2/2 en cada proceso; rechazo por inventario |
| `inv_abrir_caja_test` | Cliente +200 ms | Host 85/85, cliente 80/80, salida 0 |
| `inv_instant_test` | Cliente +300 ms RTT, pérdida 8 %, semilla 141 | Host 1/1, cliente 83/83, salida 0 |
| `inv_partes_test` | Cliente +200 ms | Host 1/1, cliente 29/29, salida 0 |
| `inv_pair_test` | Tres procesos; A con +120 ms, jitter ±40 ms y 2 % de pérdida; B entra tras el drop del host; corte del relevo de A de 8 s | Host 18/18, A 24/24, B 7/7, salida 0; conserva inventario/UID al reconectar y coincide el mundo final |
| `prueba_del_creador` | Editor headless, copia independiente con directorio de datos de usuario aislado | 231/231, salida 0 |
| `prueba_del_creador_juego` | Juego en esa misma copia, con lo creado por la prueba anterior | 38/38, salida 0 |
| `grab_above_test` | Un proceso | 22/22, salida 0 |
| `mantle_test` | Un proceso | 50 casos correctos, salida 0 |
| Timeouts negativos | Pair e instant sin cliente, `--inv-timeout=3` | Cada uno: 0 comprobaciones, 3 fallas y salida 1, como corresponde |
| Probe de auditoría | Componentes reales, estado controlado en memoria | 4 comprobaciones del defecto temporal/modelo vacío; salida 0; tres mediciones de carga de REND-02 |

En el caso de alcance en pareja no hubo correcciones en sus puntos de recorrido registrados. La suite instantánea terminó con nueve correcciones totales; incluye casos deliberados de predicción rechazada y no permite concluir «ninguna corrección de movimiento» para toda esa corrida. El caso que exige corregir un uso rechazado sí comprobó su reversión. La caja abierta se cerró en el cliente a 3.37 m, con alcance autoritativo 2 m, por la demora de la notificación; no se interpretó esa demora de pantalla como acceso autorizado fuera de alcance.

### Incidencias de ejecución que no se reportan como defectos del proyecto

- La primera copia omitió dos rutas Unicode al interpretar la salida escapada de Git. Hubo errores de recursos faltantes aunque algunas suites salieron 0. Se corrigió la copia con nombres sin escape y se repitieron las suites: esos primeros resultados no son la validación final.
- La primera corrida de integridad se lanzó sin la opción de cuadros fijos que exige su cabecera y dio dos fallas de ticks de aterrizaje; la corrida válida con esa opción dio 113/113. Selector requiere `--selector=local`; el intento sin ese argumento salió 3 y no cuenta como prueba funcional.
- La prueba de editor necesita cargarse como plugin, no como script principal. Además, el entorno restringido no permitía su archivo temporal `user://` en el perfil normal. Los primeros intentos incompletos no se cuentan como regresiones. Se repitió desde una copia limpia, con el plugin correcto y `APPDATA` aislado dentro de temporales, y pasó tanto editor como juego.
- Los logs del editor headless contienen errores de textura del render dummy al guardar previews. Las 231 aserciones no prueban render real. También apareció el diagnóstico de certificados del entorno. No se atribuyeron esas salidas a pérdidas de inventario ni se ocultaron bajo una afirmación de «cero errores de motor».
- Los procesos iniciados para estos intentos se cerraron; no se cerró una sesión del usuario.

### Qué sigue sin comprobarse

No se probaron dos PC físicas, VPN, exportación, medición de FPS en la notebook, render de miniaturas con GPU ni manipulación manual del gizmo. La comprobación del zoom fue de código, mapa de entrada y sus bloqueos; no se midió su tiempo visible en cámara lenta. No se ejecutaron el replay ni el barrido completo de parkour. Tampoco hubo pruebas de larga duración del historial de cámara lenta ni de compatibilidad de partidas guardadas, que aún no existen.

Para cerrar integración real: usar la misma exportación en ambas PC, recoger lateralmente en movimiento y apenas se suelta movimiento sobre un objeto pequeño y la franja del estante; repetir con pared y en ambas cámaras. Abrir/cancelar/reabrir una caja con demora, cortar y reconectar con inventario y consumibles pendientes. En el editor con ventana, verificar copia de forma personalizada, Ctrl+Z tras guardar una caja y proporción/encuadre de las miniaturas. Registrar orígenes de rayos y tick realmente usado al comprobar INT-01; no basta con observar el resultado final.

## 6. Orden de corrección recomendado

### Resolver antes de seguir ampliando

1. **INT-01:** fijar el significado del tick y añadir los dos casos que hoy faltan: input repetido y pedido recibido después de su tick. Es la dependencia para extender la interacción sin copiar una garantía falsa. Separar la señal de input recibido de la de simulación avanzada es el primer cambio pequeño; luego cerrar la política de pose tardía.

### Resolver antes de integrar al juego

2. **DAT-01:** comprobar la geometría efectiva al validar contenido. Es una prevención pequeña y evita sembrar objetos irrecuperables cuando crezca el catálogo.
3. **REND-02:** antes de poblar mapas grandes, introducir selección espacial y usar la consulta completa como referencia. La medición actual no obliga a optimizar de urgencia el laboratorio pequeño, pero sí a no asumir que objetos lejanos son gratis.
4. Mantener los pendientes previos de integración: separar las reglas todavía alojadas en `net_lab.gd` cuando se trasladen al juego, medir snapshots de grillas grandes y retomar ESC-02 antes de sesiones largas/guardadas. No son nuevas exigencias de esta incorporación ni se propone implementarlas todas ahora.

### Puede esperar

5. **DOC-02:** corregir los encabezados vigentes y marcar claramente lo histórico. Conviene hacerlo antes si otro trabajo va a usar esas líneas para generar paquetes o ajustar hitboxes.
6. Mantener, con su aviso, la mitigación aceptada de OBJ-02. La suite actual conserva los cambios pendientes; preservar íntegramente el historial del editor puede evaluarse después si el flujo de autoría lo requiere.

No hace falta volver al selector anterior ni rehacer el inventario. La prioridad es que la dirección capturada al apretar E se evalúe bajo un contrato temporal claro; después, prevenir contenido inválido y costo global al aumentar la cantidad de objetos.
