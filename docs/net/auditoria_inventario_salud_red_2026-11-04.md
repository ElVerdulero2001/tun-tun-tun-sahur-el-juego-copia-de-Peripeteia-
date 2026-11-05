# Auditoría de inventario, salud y red

Fecha: 2026-11-04 (Argentina). Revisión de solo lectura de la implementación; este informe es el único archivo incorporado por la auditoría.

## 1. Resultado

La base separa correctamente definiciones, instancias, grillas, autoridad y presentación. Las pruebas habituales pasan, incluidas las de contenedores compartidos, entrada tardía y reconexión. No reproduje duplicación ni pérdida de unidades confirmadas en esos recorridos.

Sin embargo, la incorporación del uso de consumibles al input de movimiento dejó una diferencia importante: un contador con **el último objeto usado** no representa una cola de acciones. Encontré pérdida de usos bajo determinadas entregas de inputs, carreras con operaciones de inventario y una reconstrucción local que cambia el orden de las acciones. También reproduje estados que vuelven a encenderse durante el tick de una muerte.

No hace falta quitar la respuesta inmediata elegida por el usuario. Conviene corregir la identidad, entrega y orden de las acciones que hay detrás de esa presentación antes de agregar más efectos dependientes del inventario.

### Hallazgos por prioridad

Gravedad mide la consecuencia; confianza, la solidez de la evidencia; prioridad, cuándo intervenir. P1: antes de ampliar esta base. P2: antes de integrar al juego o del crecimiento indicado. P3: puede esperar con un disparador definido. No hay hallazgos críticos en esta revisión.

| ID | Hallazgo | Clasificación | Gravedad | Confianza | Prioridad |
| --- | --- | --- | --- | --- | --- |
| INV-01 | El último contador no conserva los usos intermedios; el ACK modular tampoco limita su ventana | Error actual condicionado por la entrega de inputs | Alta | Alta: reproducción de componentes reales | P1 |
| INV-02 | Recoger/mover y usar no comparten un orden causal en el host | Error actual | Alta | Alta: reproducido también en dos procesos | P1 |
| INV-03 | La vista predicha ejecuta todas las recogidas/drops antes de todos los usos | Error actual y discrepancia con su contrato documentado | Media | Alta: reproducción de componentes reales | P1 |
| INV-04 | Una muerte puede terminar el mismo tick con los estados encendidos | Error actual | Media | Alta: ejecución del recorrido real | P1 |
| PRU-01 | El timeout de las pruebas de red puede terminar con código de éxito y cero comprobaciones | Error actual en la verificación | Media | Alta: reproducción aislada | P1 |
| ARQ-01 | La predicción de USE pierde el contexto de instancia que sí recibe la autoridad | Riesgo futuro concreto | Media | Alta sobre el contrato; efectos futuros sin ejecutar | P2, antes de ampliar capacidades |
| EDT-01 | Instanciar un modelo ejecuta su inicialización aunque nunca entre al árbol | Riesgo futuro concreto y discrepancia documental | Media | Alta: inicialización reproducida | P2, antes de admitir modelos de escenas con lógica |
| ESC-01 | Cada acción copia la grilla completa y puede recorrer todo el mundo para refrescar presentación | Riesgo futuro concreto | Media | Alta por inspección; umbral de rendimiento no medido | P2, antes de ampliar mucho el contenido |
| ESC-02 | El historial de cámara lenta crece durante toda la sesión y se recorre continuamente | Riesgo futuro concreto | Media | Alta por inspección; umbral no medido | P3 en el laboratorio; P2 para sesiones largas |

## 2. Estado exacto y alcance

- Repositorio: `C:\Users\ElCaido97\Documents\tun-tun-tun-sahur`.
- Rama: `net-lab`.
- HEAD: `858df9a609eee98d40836e167005f8cae0f39430`.
- Índice: sin diferencias staged.
- Estado local inicial conservado:
  - eliminado localmente: `docs/net/auditoria_parkour_2026-10-30.md`;
  - modificados: `guia_del_laboratorio.md`, `hud_salud_estamina_y_estados.md`, `inventario_de_grilla.md`;
  - sin seguimiento: `archive/`, `output/pdf/`, `tmp/`, `project.godot~RF78902d2f.TMP`.
- Había 501 archivos sin seguimiento. Se inventariaron sus tipos y ubicaciones; incluyen copias, diagnósticos, logs y salidas. No se atribuyen a la incorporación ni se consideran automáticamente código activo. El `.TMP` se comparó con `project.godot`: es distinto y carece de varios ajustes actuales; no es la configuración que se ejecutó. No se limpió ni restauró nada.
- Los tres Markdown modificados contienen decisiones y resultados posteriores a los commits: se revisó su contenido del disco, especialmente el uso/recogida/drop predichos del 04/11. No hay cambios locales en los scripts rastreados que sustituyan lo auditado en HEAD.

### Base de comparación

No existe un único commit que represente toda la incorporación. Se tomó como límite amplio el padre de `12fa57b`, `2f809c3`, y se siguió el estado actual de los sistemas involucrados:

| Commit | Alcance relevante |
| --- | --- |
| `12fa57b` | Inventario de grilla, autoridad, contenedores y zona de prueba |
| `ca2186d` y documentos posteriores | Intención, decisiones de pruebas y evolución del inventario |
| `593b325` | Salud, estamina, poderes, HUD, consumibles y daño en el tiempo; incluye también cambios de contenido que no se atribuyen todos a la lógica de salud |
| `9a7219f` | Panel Objetos y herramientas de autoría |
| `0072b36` | Documentación de esas incorporaciones |
| `c392774` | Consumibles en el input y recogida con presentación inmediata |
| `2cf8fb1` | Drop predicho y validación del lugar propuesto |
| `858df9a` | Variable renombrada en la réplica y medición en la prueba de red |

El foco fue `scripts/inventory/`, las partes pertinentes de `scripts/actor/` y `scripts/net/`, `scenes/net_lab/`, sus escenas/recursos de inventario y HUD, y `addons/inventario_objetos/`. Se revisaron `project.godot`, el preset de exportación y el ciclo de vida de actores porque tienen conexiones concretas con estos sistemas. No se auditó PlayerV2 ni el inventario anterior como sistemas activos de esta implementación.

No apareció un `AGENTS.md` físico en la búsqueda recursiva del repositorio. Se aplicaron las instrucciones aportadas en la conversación y las reglas pertinentes de la guía. La instrucción específica de esta tarea de no modificar implementación ni hacer commits prevalece sobre la regla histórica de commitear después de una prueba satisfactoria.

### Versión y configuración verificadas

El ejecutable localizado en `C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe` respondió `4.7.2.stable.official.ed1daf0bf`. `project.godot` declara características `4.7`, Forward Plus, física Jolt y driver Windows D3D12. El plugin habilitado es `res://addons/inventario_objetos/plugin.cfg`. Los autoloads preexistentes `UIHacking` y `DebugDraw` siguen en la configuración; el inventario nuevo no agregó uno propio.

El laboratorio es la escena indicada por el override `run/main_scene.lab_coop`; no se tomó la escena principal general como entrada de estas pruebas. El preset exporta con `lab_coop`, scripts como texto y excluye `tmp`, `archive`, `output`, `docs` y `tools`. Se inspeccionó esa configuración; **no se ejecutó una exportación**. Las pruebas se lanzaron explícitamente contra las escenas del laboratorio y sin pantalla.

## 3. Intención y recorrido implementado

Se empezó por `guia_del_laboratorio.md`. Se identificaron los siete Markdown actuales de `docs/net` y se consultaron los documentos de inventario y HUD/salud junto con sus tres prompts. Del historial de arquitectura se usaron los apartados de autoridad/adopción, eventos, tiempo y la sección 8.36 de la auditoría anterior; sus versiones y fragmentos antiguos no se trataron como código vigente.

### Decisiones que se respetaron

| Origen | Decisión o límite |
| --- | --- |
| Usuario, decisiones posteriores documentadas | Caminar con inventario abierto; barra con referencias a objetos de la grilla; usar, recoger y soltar con respuesta local inmediata, incluida la salud |
| Usuario | Sin regeneración de salud/estamina; los estados suman costos; agotamiento apaga todos; muerte de prueba conserva posición, inventario y estamina, restaura salud y apaga estados |
| Usuario | Una sola intensidad de cámara lenta compartida; cada jugador paga su propio pedido; daño en el tiempo acumulable hasta cuatro efectos, ligado al tiempo del mundo |
| Claude | Un uso por tick; costo de poderes por tick de reloj real; contadores y unidades internas; bloqueo de una pila mientras se confirma su uso; elección del lugar de drop y margen de latencia |
| Límites documentados que no son bugs por sí mismos | Objetos sin física; una caja abierta por jugador; inventario descartado al abandonar definitivamente; conservación tras corte dentro de la ventana de reconexión; sin guardado; termómetro fijo; integridad del cuerpo pendiente |
| Futuro, no implementado | Guardado, combate completo, daño del escenario, física de objetos, propiedades con mecánicas propias y otras capacidades |

La predicción posterior cambia legítimamente el prompt inicial que pedía todas las operaciones como solicitudes al host. No se marca ese cambio autorizado como incumplimiento. Los problemas son las garantías que faltan para sostenerlo.

### Recorrido real

1. E llama a `InvUI.pick_up_world`; las operaciones de grilla pasan por `InvReplica.request`, `InvNet` y `InvAuthority`. Los pedidos confiables tienen secuencia y resultados acotados para deduplicar. La autoridad valida identidad del remitente, acceso, versiones, cantidades y espacio según la operación. Los commits agrupan los cambios de una transferencia.
2. Usar desde menú o barra llama a `InvUI.use_item`, `InvNet.queue_use` y `take_use`. El input de 17 bytes lleva contador de ocho bits y UID del último uso. `SimClock.before_step` llama a `use_before_step` antes del motor; en la autoridad valida y gasta, y en el cliente aplica el efecto predicho. El estado de 153 bytes incluye el contador procesado.
3. `ActorVitals` cambia salud/estamina y efectos; `ActorMotor` descuenta el daño en el tiempo y luego procesa `ActorPowers`. La adopción exige coincidencia de salud, muertes, efectos y contador de uso, y no permite aumentar estamina respecto del host.
4. La salud viaja por snapshots de actor; la grilla y el ACK de uso viajan por commits confiables del inventario. `ClientPrediction` restaura/repite el actor; `InvReplica` reconstruye la grilla mostrada. Son dos confirmaciones distintas, sin una secuencia causal común para todas las acciones.
5. El HUD lee el estado local. El host deriva el pedido global de cámara lenta de los bits de los jugadores y programa tramos. La reconexión transfiere el componente de inventario al actor nuevo y resincroniza el contador local.

Se encontraron mecanismos reales que evitan varios problemas sospechables: copia de estado por instancia, operaciones de grilla que validan antes de mutar, transferencia atómica, propietario obtenido de la conexión, límites en inputs, comprobación de pose en adopción, versiones para pedidos confiables, conservación del componente en reconexión y limpieza de suscripciones. No se reporta que esos mecanismos falten.

## 4. Hallazgos

### INV-01 — El input conserva el último uso, no los usos pendientes

**Clasificación:** error actual. **Gravedad:** alta. **Confianza:** alta. **Prioridad:** P1.

**Referencias:** `scripts/actor/actor_input.gd:48` y su serialización; `scripts/net/net_sync.gd:13`, `input_for:220`; `scripts/inventory/inv_net.gd:193`, `take_use:201`, `use_before_step:232`; `scripts/inventory/inv_replica.gd:317` (filtro del ACK `u`).

**Condición y recorrido:** se usan A y B en ticks consecutivos. Si el host ya pasó esos ticks repitiendo un input antiguo y luego selecciona uno con contador 2/UID B, `use_before_step` compara solamente desigualdad con el contador visto, escribe 2 y aplica B una vez. No reconstruye A ni existe una cola retransmitida de acciones sin confirmar. Los seis inputs redundantes ayudan a entregar datos; no hacen que el host vuelva a ejecutar un tick ya pasado ni recorra cada contador intermedio.

**Evidencia ejecutada:** con la autoridad real del laboratorio, salud 60, cinco venenos A y tres botiquines B, se inyectó en `NetSync` únicamente el input 101, contador 2, B. El host curó a 100, dejó los cinco venenos y avanzó el contador a 2. Ejecutar A y después B habría dejado salud 70 y cuatro venenos. La réplica tenía usos 1/A y 2/B: al recibir `u=[2, ""]` eliminó ambos pendientes, sin rechazo para A. Es una reproducción determinista de componentes; no una medición de frecuencia en internet real.

**Segundo borde del mismo protocolo:** la comparación modular del ACK presupone menos de 128 usos asignados en vuelo, pero no hay límite ni contrapresión que lo garantice. Con 130 usos pendientes y ACK 1, quedaron 128; el uso 130 ya había desaparecido aunque solo se confirmó el primero. La cola y el caché de definiciones también usan ese contador pequeño. No se afirma que 130 usos en vuelo sea habitual: es un invariante necesario que actualmente no se impone.

**Consecuencia:** un uso puede verse aplicado y luego desaparecer por corrección sin haber consumido el objeto ni recibido su resultado individual. La confirmación acumulativa puede dar por cerrada una intención que el host nunca ejecutó. No se demostró pérdida de la unidad confirmada: se pierde la acción solicitada.

**Corrección mínima:** representar cada uso como comando con identidad, UID y resultado; retener/retransmitir los no confirmados y confirmar únicamente los efectivamente resueltos. Si faltan intermedios, no considerarlos exitosos por observar el contador siguiente. Imponer una ventana inequívoca o ampliar los identificadores. Puede conservarse la aplicación local inmediata y aplicar tarde en el host con corrección; no exige rebobinar todo el inventario compartido.

**Comprobación de resolución:** perder/retrasar el tick de A, entregar B primero y después A; exigir dos resultados identificables, cantidades correctas y ningún efecto repetido con retransmisiones. Repetir con objetos distintos, muerte, daño en el tiempo y la frontera de vuelta del identificador. Verificar explícitamente el límite de pendientes.

### INV-02 — Las dependencias entre inventario y uso pueden llegar invertidas

**Clasificación:** error actual. **Gravedad:** alta. **Confianza:** alta. **Prioridad:** P1.

**Referencias:** `scripts/inventory/inv_ui.gd:280`, `_press_slot:304`, `_waiting:510`, `_busy:518`, `_open_menu:833`, `use_item:900`; `inv_net.gd:232`, `_physics_process:453`; `inv_authority.gd:330`, `use_from_input:406`; `scripts/net/link_simulator.gd:43`, `55`, `63`.

**Condición y recorrido:** recoger muestra el objeto inmediatamente y permite usarlo. PICKUP espera en la fila confiable; USE viaja en inputs no confiables y se resuelve por tick. No lleva la dependencia «este uso requiere que se haya procesado aquella recogida». Si el input llega primero, el host rechaza un UID que aún no posee el jugador y avanza su contador; cuando PICKUP se acepta después, el uso no se reintenta.

**Evidencia ejecutada en dos procesos:** una reproducción temporal heredó la prueba existente y usó `ui.pick_up_world(uid)` seguido de `ui.use_item(uid)`. Se retrasó exclusivamente el envío confiable de PICKUP 350 ms, dejando circular el input. El cliente mostró salud 60 y cuatro venenos. Al estabilizarse quedó salud 100, cinco venenos y `No se usó: ese objeto ya no está en tu inventario`. PICKUP sí se aceptó. El retraso fue impuesto para demostrar el orden; no se lo presenta como una prueba de dos PC ni como reproducción espontánea de esa latencia.

**Variante validada:** el menú deshabilita Usar cuando `_waiting(uid)` es verdadero, pero `use_item` no hace esa comprobación; la barra rápida lo llama directamente. Un probe con MOVE pendiente confirmó `_waiting(uid)==true` y `use_item(uid)==true`. La protección existente es asimétrica: bloquea mover después de usar, pero no asegura el orden inverso desde todos los accesos. Puede producir rechazo por versión o cambio de dueño según el orden recibido; no implica duplicación automática.

**Consecuencia:** acciones válidas al encadenarlas desde la vista inmediata fracasan y revierten salud. Consumir y mover/transferir una misma pila pueden competir sin respetar la intención local.

**Corrección mínima:** asociar los usos a la secuencia/dependencia del inventario y esperar esa dependencia en la autoridad antes de validarlos. Conservar la predicción visual. Como contención, aplicar la validación de pendientes dentro de `use_item`, común a menú y barra; bloquear temporalmente usos dependientes de recogidas sería otra contención, pero altera el flujo inmediato y no reemplaza el orden en el servidor. Coordinar con INV-01 para no crear dos protocolos nuevos independientes.

**Comprobación de resolución:** recoger→usar, caja→inventario→usar, mover→usar y usar→transferir, invirtiendo entregas de forma determinista. El resultado debe corresponder al orden causal, o rechazar explícitamente la dependencia que falló. Repetir desde menú y barra, con dos jugadores disputando la recogida.

### INV-03 — La reconstrucción local cambia identidades al reordenar acciones

**Clasificación:** error actual y discrepancia documental. **Gravedad:** media. **Confianza:** alta. **Prioridad:** P1.

**Referencias:** `scripts/inventory/inv_replica.gd:139`, `_rebuild_shown:195` —primero itera `pending`, y recién después `_uses`—; `scripts/inventory/inv_ops.gd:177`; `scripts/inventory/inv_ui.gd:901`.

**Condición y recorrido:** usar la última unidad de una pila A y después recoger una pila B del mismo tipo antes de que el host confirme A. La vista se reconstruye desde el inventario confirmado insertando B **antes** de consumir A. Esto llena A con unidades nuevas y después quita una, aunque en el orden real A ya se había terminado.

**Evidencia ejecutada:** inventario con veneno UID 30001, cantidad 1; se añadió su uso pendiente, y luego recogida de UID 30002, cantidad 5. La vista mostró UID 30001×4 y UID 30002×1. Aplicando las acciones en el orden solicitado debería quedar solamente UID 30002×5. La cantidad total coincide, pero identidad, colocación y versiones no. El comentario de la réplica promete conservar el orden; separar las dos listas no lo conserva.

**Consecuencia:** la interfaz puede operar sobre una pila que ya se habría agotado y provocar nuevas intenciones con UID incorrecto, cancelaciones de arrastre o rechazos. Los commits posteriores pueden corregirlo; no se probó corrupción permanente del inventario autoritativo por este caso.

**Corrección mínima:** un registro local único de intenciones con orden común para recogida, drop y uso, reconstruido con sus resultados y dependencias. No basta ajustar el orden fijo de los dos bucles: el caso inverso necesita el orden contrario. Reutilizar la identidad de acciones de INV-01/02.

**Comprobación de resolución:** comparar snapshot completo —UID, cantidad, versión, celda y giro— del resultado predicho con la ejecución secuencial de las mismas acciones. Incluir usar última unidad→recoger, recoger→usar, drop parcial→usar y rechazo de una operación intermedia. Comprobar que barra y arrastre no retengan IDs agotados.

### INV-04 — La muerte pierde prioridad frente a los toggles del mismo tick

**Clasificación:** error actual. **Gravedad:** media. **Confianza:** alta. **Prioridad:** P1.

**Referencias:** `scripts/inventory/inv_net.gd:232`; `scripts/actor/actor_vitals.gd:107`, `die:161`; `scripts/actor/actor_motor.gd:103` (daño en el tiempo) y `:116` (`ActorPowers.step`); `scripts/actor/actor_powers.gd:54`, `retire:110`; `scripts/net/sim_clock.gd:229` y su llamada a `before_step`.

**Condición y recorrido:** el actor ya tiene los dos estados prendidos y pulsa sus teclas para apagarlos en el mismo tick en que usa una cápsula letal. El uso mata y `die` pone poderes en cero. Después el motor procesa las pulsaciones nuevas contra ese cero y vuelve a prender los dos. El contador de pulsaciones no se había consumido al morir. El orden del daño en el tiempo antes de poderes presenta el mismo borde por inspección.

**Evidencia ejecutada:** `use_before_step` con cápsula letal y ambos contadores nuevos dejó `deaths=1, powers=0`; ejecutar inmediatamente `ActorMotor.step` con ese input dejó `deaths=1, powers=3`. Las pulsaciones pretendían apagar estados que estaban activos, pero terminaron encendiéndolos. La variante con cápsula se ejecutó; la variante con muerte por daño en el tiempo se deduce del orden y queda como regresión a agregar.

**Consecuencia:** un tick de muerte puede terminar con súper/cámara lenta activos y cobrando, en contra de la regla de apagado. El host puede conservar el pedido de cámara lenta de ese jugador. La autoridad y el cliente pueden coincidir en este resultado incorrecto, por lo que una prueba de determinismo no lo detecta.

**Corrección mínima:** definir muerte como transición prioritaria del tick y consumir los contadores sin reactivar poderes durante ese tick, abarcando tanto el pre-step de consumibles como el daño del motor. No alcanza medir el contador de muertes solamente al entrar al motor: la cápsula ya pudo matar antes.

**Comprobación de resolución:** cápsula/daño en el tiempo + toggles simultáneos, con cero/uno/dos estados previos. Exigir poderes finales cero, consumo correcto de la cápsula, una sola muerte y ninguna reactivación al repetir el input; permitir una pulsación realmente posterior. Con otro jugador sosteniendo la cámara lenta, su pedido debe continuar.

### PRU-01 — Un timeout puede presentarse como prueba exitosa

**Clasificación:** error actual de pruebas. **Gravedad:** media. **Confianza:** alta. **Prioridad:** P1.

**Referencias:** `scenes/net_lab/inventario/pruebas/inv_instant_test.gd:39`, `_finish:68`, `_settle:246`; `inv_pair_test.gd:40`, `_finish:70`.

**Condición y recorrido:** vence el temporizador de 100 s antes de completar el recorrido. El callback imprime `TIEMPO AGOTADO` y llama a `_finish` sin incrementar fallas; `_finish` decide la salida con `_failures > 0`. La prueba puede aprobar con cero comprobaciones o con solo el prefijo ejecutado. `_settle` también ignora el booleano que devuelve su espera, debilitando algunos checkpoints.

**Evidencia ejecutada:** se creó fuera del repositorio una copia dinámica del script de `inv_instant_test`, cambiando exclusivamente el plazo de 100 s a 0,1 s. Host sin cliente: imprimió `TIEMPO AGOTADO`, `RESULTADO 0 comprobaciones, 0 fallas` y salió con código **0**. El mismo patrón del callback se verificó por inspección en `inv_pair_test`. Las corridas aprobadas de esta auditoría sí alcanzaron sus resultados finales; no se basaron solo en el código de salida.

**Consecuencia:** una regresión que cuelgue el recorrido puede dar verde en automatización y dejar sin ejecutar las comprobaciones relevantes.

**Corrección mínima:** timeout debe sumar fallo y salir distinto de cero; exigir marca explícita de recorrido terminado y comprobar los resultados de esperas necesarias. Mantener salidas no exitosas también cuando no hubo comprobaciones.

**Comprobación de resolución:** host sin cliente, dependencia que nunca llega y timeout a mitad de la secuencia deben fallar; la ejecución completa debe conservar sus resultados normales. Agregar los casos de INV-01 a INV-04: las pruebas actuales de dos usos consecutivos y rechazo simple no los cubren. En particular, `_pick_up` espera confirmación antes del siguiente paso y no cubre INV-02.

### ARQ-01 — USE predicho no recibe el contexto de instancia del contrato

**Clasificación:** riesgo futuro concreto. **Gravedad:** media. **Confianza:** alta por inspección. **Prioridad:** P2 antes de ampliar capacidades.

**Referencias:** `scripts/inventory/inv_ability.gd:28`, `:34`; `inv_net.gd:201`, `:232` —guarda una definición por contador y llama a `check(null, null, vitals)` / `apply(null, null, vitals)`—; `inv_authority.gd:371` —entrega loadout y stack reales—; `inv_stack.gd`, campo `state`; `inv_consumable.gd`, que hoy ignora esos dos argumentos.

**Condición y mecanismo:** una capacidad USE empieza a consultar carga, condición, contenido u otro dato de la instancia, o del loadout. El contrato ya acepta esos argumentos y el estado individual ya existe, pero la predicción le pasa null y conserva solamente `InvItemDef`. Repetir un tick tampoco reconstruye una copia de la instancia consumida.

**Consecuencia:** esa capacidad puede funcionar en la autoridad y fallar, no predecirse o provocar errores en el cliente. Actualmente `InvConsumable` usa solo parámetros compartidos y vitals, por lo que no se afirma que sus objetos actuales sufran este fallo.

**Evidencia:** recorrido estático de las llamadas y de `_use_defs`; no se implementó una capacidad futura para dar por roto el contenido existente.

**Prevención mínima:** hacer explícito qué capacidades son predecibles y qué contexto inmutable de instancia necesita cada acción durante su predicción y repetición. Proveer el mismo contrato o rechazar explícitamente la predicción no soportada, en lugar de asumir que cualquier USE tolera null. Coordinar el descriptor de acción con INV-01/02; no exige implementar carga ni durabilidad ahora.

**Comprobación:** capacidad de prueba que lea un dato de stack y lo use para calcular el efecto, con replay, rechazo y consumo de la última unidad. Host y cliente deben obtener el mismo resultado sin depender de un recurso mutable o una instancia que ya desapareció.

**Qué crecimiento lo encarece:** cada nueva capacidad y campo de instancia consolidaría un camino autoritativo completo y otro predicho incompleto. Corregir después requiere adaptar todos esos efectos y sus historiales, no solo el transporte inicial.

### EDT-01 — «No entrar al árbol» no impide ejecutar la inicialización del modelo

**Clasificación:** riesgo futuro concreto y discrepancia documental. **Gravedad:** media. **Confianza:** alta. **Prioridad:** P2 antes de admitir modelos de escenas con lógica.

**Referencias:** `scripts/inventory/inv_visuals.gd:12`, especialmente `def.model.instantiate():18`; `inv_thumbnails.gd`, `build_viewport`; `inv_world_item.gd`, `setup`; `docs/net/inventario_de_grilla.md`, sección 4, Apariencia: promete que no corren scripts.

**Condición y recorrido:** se asigna como modelo un `.tscn` con script cuya inicialización tenga efectos secundarios. `InvVisuals.build` instancia primero la escena completa, copia mallas y luego libera la instancia. Evitar `add_child` sí evita `_ready`/procesamiento en el árbol, pero no la inicialización de los scripts al instanciar.

**Evidencia ejecutada:** se armó en memoria una `PackedScene` con un script de `Node3D` que imprimía desde `_init`. Al llamar a `InvVisuals.build` volvió a imprimir `MODEL INIT EXECUTED` entre las marcas de entrada/salida de esa función, sin añadir el modelo al árbol. No se modificó ningún modelo real. No se comprobó que los modelos actuales tengan un inicializador dañino.

**Consecuencia:** reutilizar una escena de gameplay como apariencia puede ejecutar lógica inesperada durante generación de miniaturas, aparición de objetos o equipamiento. El contrato documentado de aislamiento es más fuerte que lo implementado.

**Prevención mínima:** limitar/validar las escenas aceptadas como apariencia para excluir nodos con lógica ejecutable, o extraer las mallas sin instanciar la escena completa. Documentar el límite mientras no exista esa separación. No hace falta modificar assets existentes para esta auditoría.

**Comprobación:** modelo con `_init`, setters y nodos con lógica de prueba: crear su miniatura y representación no debe dispararlos. Conservar transformaciones y materiales de los modelos normales.

**Qué crecimiento lo encarece:** cuantos más objetos reutilicen escenas completas, más dependencias incidentales pueden quedar incorporadas al catálogo y más difícil será reemplazarlas por apariencias sin lógica sin alterar contenido.

### ESC-01 — Una acción pequeña provoca copias y refrescos de alcance amplio

**Clasificación:** riesgo futuro concreto. **Gravedad:** media. **Confianza:** alta por inspección; sin benchmark. **Prioridad:** P2 antes de aumentar mucho objetos y grillas.

**Referencias:** `scripts/inventory/inv_authority.gd:406`, `flush:649`; `inv_grid.gd:139`, `:165`; `inv_replica.gd:190`, `:195`, `apply_commit:266`; `inv_net.gd:113` (señales), `_sync_world_views:531`, `interaction_target`; `inv_authority.gd:584`; `inv_grid.gd:73`, `free_spot:94`.

**Condición y mecanismo:** cada uso aceptado o rechazado marca al jugador y envía snapshots completos de grilla/loadout. La copia de grilla serializa y reconstruye todas las pilas; ordenar y buscar ubicaciones añade trabajo. Cada invalidación de `shown_own`, incluso por un uso que no cambia el mundo, emite `shown_changed`, conectada a `_sync_world_views`, que vuelve a recorrer todos los objetos sueltos. Un commit que también cambia mundo dispara otro recorrido por `world_changed`. No se afirma que cada acción retransmita el mundo completo: los cambios del mundo ya viajan como altas/bajas.

**Consecuencia:** una acción de una unidad deja de costar solo lo tocado: crece con las pilas de la grilla y con los objetos sueltos del mundo local. Los cambios del mundo se publican a todos los peers bienvenidos. La selección por mira y el descarte por amontonamiento también recorren la colección completa. Más jugadores operando y más objetos multiplican trabajo y tráfico aunque estén lejos.

**Evidencia:** inspección trazable de snapshots, señales y bucles. No se midió un límite de FPS, memoria ni número seguro de objetos; el laboratorio actual pasó sus pruebas.

**Prevención mínima:** separar invalidación de grilla y mundo; refrescar solo objetos del mundo que realmente cambiaron, evitando el doble refresco. Agrupar envíos por tick cuando no rompa atomicidad. Antes de adoptar grillas/mapas mucho mayores, medir tamaño de commits y tiempo por acción para decidir deltas y consultas espaciales. No hace falta construir ahora streaming de mundo.

**Comprobación:** un uso propio sin cambios del mundo no debe refrescar sus W vistas; variar pilas, objetos y jugadores, medir bytes/acción y tiempo de trabajo. Mantener transferencias atómicas y entrada tardía completa.

**Qué crecimiento lo encarece:** mapas con objetos acumulados, contenedores grandes y más operaciones concurrentes. Si UI y suscriptores asumen siempre snapshots completos y refrescos globales, migrar después obliga a cambiar muchos consumidores del estado.

### ESC-02 — La cámara lenta conserva una historia ilimitada en el camino frecuente

**Clasificación:** riesgo futuro concreto. **Gravedad:** media. **Confianza:** alta por inspección; sin benchmark. **Prioridad:** P3 para el laboratorio corto; P2 antes de sesiones largas.

**Referencias:** `scripts/net/sim_clock.gd:123`, `add_world_slow:149`, `world_scale:173`, `world_dt:181`, `world_ticks:188`; `scenes/net_lab/net_lab.gd:2001`, `_announce_world_slow_to:2077`; usos de `world_ticks` en bases/plataformas.

**Condición y mecanismo:** activar y desactivar la cámara lenta repetidamente agrega tramos a `_world_slow`; solo se vacían al reiniciar el reloj/sesión. `world_scale` y `world_ticks` recorren esa historia; el segundo necesita el descuento acumulado para ubicar plataformas. Al entrar un peer, el host vuelve a enviar todos los tramos históricos.

**Consecuencia:** consultas de tiempo que se hacen continuamente, y la sincronización de entrada tardía, crecen con la cantidad total de activaciones pasadas, no solo con lo que está activo o puede necesitar replay. No es correcto borrar simplemente los tramos viejos: se perdería el tiempo acumulado y cambiaría la pose de plataformas.

**Evidencia:** inspección de almacenamiento, bucles y envío de bienvenida. No se simuló una partida de horas ni se atribuye degradación actual.

**Prevención mínima:** definir una frontera temporal y un acumulado de tiempo de mundo para el pasado, conservando tramos recientes necesarios para replay. Hacer explícita esa representación al sincronizar un peer. Puede esperarse mientras las sesiones sean breves, pero conviene fijar el contrato antes del guardado y mapas persistentes.

**Comprobación:** muchos ciclos sintéticos y cliente tardío: igual `world_ticks`, misma pose de bases y mismas correcciones con y sin compactación; memoria e historial activo acotados, respetando la ventana de repetición.

**Qué crecimiento lo encarece:** sesiones largas con muchos toggles y reconexiones. Si el tiempo absoluto del mundo y futuras partidas guardadas dependen del listado completo, luego habrá que migrar también esos datos y todos los usuarios del reloj.

## 5. Auditoría anterior y discrepancias documentales

El informe de parkour del 30/10 está eliminado en el árbol local. Se leyó su versión de HEAD mediante Git, sin restaurarlo, y se contrastó con el código actual y el seguimiento de la sección 8.36.

| Hallazgo anterior | Estado verificado en esta revisión |
| --- | --- |
| H1: agarre desde arriba sin criterio propio | La prueba dedicada existe y pasó 22/22. El barrido contiene detección por decisión del motor y criterio adicional; no se volvió a ejecutar su barrido completo. El hueco señalado dejó de estar abierto en su forma original. |
| H2: mantle sin prueba funcional mantenida | Resuelto en lo verificable: `mantle_test` completó 50 casos, y replay exige un mantle terminado arriba. No se convierte eso en garantía de todas las redes/plataformas. |
| H3: límites de adopción de estados | Sigue siendo el límite aceptado de arquitectura. Existen controles adicionales de vitals. No se reprodujo exploit y no se eleva el criterio de antitrampas por preferencia del auditor. |
| H4: correcciones sobre bases movidas por host | Sigue documentado como límite aceptado para mala red. No se volvió a medir ese máximo ni se lo presenta como una regresión nueva. |
| H5: ocho cambios locales de aquella revisión | Esa fotografía quedó superada por los commits posteriores. Hoy el estado local es el descrito en la sección 2, principalmente documental y salidas/copias. No se considera «resuelto» por borrar trabajo local. |
| H6: pendientes históricos del súper | El seguimiento histórico indica la actualización y la guía actual describe el súper aplicado a esas velocidades. Quedan párrafos históricos y resultados de etapas anteriores; no se deduce del pasado un incumplimiento actual. |

Discrepancias actuales que conviene corregir con los arreglos, sin reemplazar las decisiones del usuario:

- La réplica promete reconstruir las acciones en orden, pero INV-03 muestra que separa usos y pedidos en fases fijas.
- El texto sobre un uso que llega tarde dice que se aplica después y trae una corrección chica. INV-01 muestra que eso solo cubre el caso en que todavía sobrevive el mismo uso como último; no todos los usos intermedios.
- La documentación de apariencias promete que no corren scripts; EDT-01 acota lo que realmente se evita.
- Inventario/HUD conservan apartados de «falta tu prueba en dos PC» junto a secciones posteriores que registran pruebas del usuario satisfactorias. No se desconoce esa evidencia posterior; deben rotularse por fecha/versión. Lo mismo ocurre con huellas y cantidades antiguas de comprobaciones. La huella del replay medida ahora fue `f9b53da25ac45f16`, no la de estados de menor tamaño.

## 6. Pruebas ejecutadas y límites

Todas las ejecuciones fueron en esta PC, sin pantalla, con Godot 4.7.2 y el estado de trabajo indicado. Logs y scripts auxiliares se escribieron en `%TEMP%\auditoria_inv_salud_20261104`, fuera del repositorio. Allí quedaron `probes.gd`/`probes.log`, `extra.gd`/`extra.log`, `race_runner.gd`, `race_node.gd`, `race_host.log`, `race_client.log` y `timeout.gd`/`timeout.log`; son auxiliares temporales, no pruebas incorporadas al proyecto. No se instalaron herramientas, modificó contenido, cambió de rama ni hizo commit/push.

| Prueba | Resultado observado |
| --- | --- |
| `inv_model_test.tscn` | 70 comprobaciones, 0 fallas; salida 0 |
| `inv_lab_test.tscn` | 166 comprobaciones, 0 fallas; 63 aceptados, 23 rechazados, 1 repetido; salida 0 |
| `estados_test.tscn` | 104 comprobaciones, 0 fallas; salida 0 |
| `inv_instant_test.tscn`, dos procesos | Cliente 69 comprobaciones, host 1, 0 fallas; salidas 0. Host con +200 ms; cliente con +200 ms, jitter ±40 ms y 2 % pérdida simulada. Cliente terminó con salud 80, una muerte y contador 8; una corrección correspondiente al rechazo provocado. |
| `inv_pair_test.tscn`, tres procesos | Host 18, A 24, B 7 comprobaciones; 0 fallas y salidas 0. A con +120 ms, jitter ±40 ms, 2 % pérdida, relevo y corte de 8 s; B entró tarde. Se conservaron inventario e IDs al reconectar y se limpiaron suscripciones. |
| `actor_replay_test.tscn` | 6195 repeticiones, 277545 ticks repetidos; coincidencia byte a byte y salida 0. Huella `f9b53da25ac45f16`. |
| `grab_above_test.tscn` | 22 comprobaciones, 0 fallas; salida 0 |
| `mantle_test.tscn` | Los 50 casos dieron lo esperado; salida 0 |
| Probes deterministas de componentes reales | Confirmaron salto de uso intermedio/ACK, accesibilidad de recogida predicha, rechazo al invertir entrega, orden incorrecto de reconstrucción y bypass de pendiente desde `use_item`. |
| Probe de muerte y toggles | Antes del motor `deaths=1,powers=0`; después `deaths=1,powers=3`. |
| Probe del ACK con 130 pendientes | ACK 1 dejó 128 pendientes y quitó el 130 prematuramente. |
| Probe de modelo con `_init` | La inicialización se ejecutó dentro de `InvVisuals.build`. |
| Recogida→uso en dos procesos, retraso confiable impuesto | Predicción 60 de salud/4 venenos; resultado 100/5 y rechazo del uso, aunque la recogida se aceptó. |
| Copia temporal del timeout de `inv_instant_test` | Solo se acortó el temporizador a 0,1 s: agotó tiempo con 0 comprobaciones y salió 0. Reproduce PRU-01. |

Comando base utilizado, con log por ejecución:

```powershell
& 'C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe' --headless --path . `
  --log-file "$env:TEMP\auditoria_inv_salud_20261104\nombre.log" `
  res://scenes/net_lab/estados_test.tscn
```

Para repetir las parejas existentes, usar la escena correspondiente de `scenes/net_lab/inventario/pruebas/` y los argumentos documentados en `inventario_de_grilla.md`; los puertos utilizados aquí fueron 17861 para instant y 17871/17891 para pareja/relevo. B se inició después de las operaciones del host, como entrada tardía; no se midió un plazo exacto de llegada como requisito de la prueba.

**Límites e incidencias de ejecución:**

- Godot imprimió `Failed to read the root certificate store` al arrancar. No impidió estas suites ni las conexiones locales. No se verificaron conexiones TLS externas.
- Algunas reproducciones temporales con scripts dinámicos y salida temprana imprimieron avisos de recursos/RID al cerrar. No se atribuyen como fuga del juego sin aislar su ciclo de limpieza; no invalidan los estados observados antes de salir. Las suites principales se valoraron por su resultado final y salida, además del log.
- No se probó en dos PC físicas, con internet real, con entrada humana de mouse ni en una exportación. Las pruebas previas del usuario que figuran en los Markdown se consideran antecedentes, no ejecuciones de esta auditoría.
- El plugin se revisó por inspección: guardado con validación y rollback, borradores, preservación de recursos externos, colocación con undo/redo y referencias a destinos del laboratorio. No se ejecutaron sus suites de editor porque escriben recursos y escenas; deben correrse en una copia aislada, como ya indica su documentación. No se certifica guardado/undo/redo mediante ejecución en esta auditoría.
- No se ejecutó el barrido largo completo de bordes, un benchmark masivo ni sesiones de horas. ARQ-01 y los riesgos ESC son deducciones trazables, no fallas de rendimiento medidas.
- Las reproducciones nuevas forzaron estados/entregas definidos o construyeron recursos en memoria. No se infiere su probabilidad de aparición a partir de una sola ejecución.

### Pasos concretos que quedan para la validación de integración

1. En una copia del proyecto, ejecutar las dos suites del creador y revisar los recursos resultantes; probar también apariencias con inicialización si se habilitan `.tscn` arbitrarios.
2. Tras corregir el protocolo, ejecutar los encadenamientos de INV-01/02 con demoras asimétricas y pérdidas en ráfaga, además de las parejas existentes. Repetir en las dos PC y con el exportado.
3. Agregar las regresiones deterministas de INV-03/04 y el timeout negativo antes de aceptar resultados por código de salida.
4. Medir crecimiento con grillas/objetos representativos del futuro juego; compactar tiempo sin cambiar poses ni replay antes de usar sesiones persistentes.

## 7. Cuándo resolver y orden recomendado

### Resolver antes de seguir ampliando

1. **PRU-01:** asegurar que el verificador falla si el recorrido no termina. Es pequeño y evita confiar en verdes falsos durante los siguientes arreglos.
2. **INV-01 + INV-02:** definir identidad de acción, resultados individuales/confirmación contigua, retransmisión y dependencia con inventario. Corregir juntos porque comparten la frontera entre input y transacciones.
3. **INV-03:** usar ese mismo orden de acciones en la reconstrucción local; comparar también identidad y versiones, no solo cantidades.
4. **INV-04:** resolver la prioridad de muerte en todo el tick y verificar consumibles, daño en el tiempo y cámara lenta de otro jugador.

La urgencia es consolidar garantías correctas mientras solo hay unos pocos efectos. No se recomienda construir combate, persistencia ni física de objetos para arreglar estos puntos.

### Resolver antes de integrar al juego

- **ARQ-01**, antes de sumar USE que dependa de datos individuales. Se puede mantener la capacidad actual simple, pero el contrato debe dejar claro qué se predice.
- **EDT-01**, antes de reutilizar escenas con lógica como apariencias; corregir además la promesa documental.
- **ESC-01**, al pasar de la zona pequeña a mapas con mucho contenido. Primero separar invalidaciones y medir; no imponer una arquitectura de streaming sin necesidad demostrada.
- **ESC-02**, si la integración incluye sesiones largas o estado persistente: introducir acumulado/frontera temporal antes de fijar ese formato.
- Ejecutar en copia las pruebas del editor, y después la pareja real/exportación; eso no quedó certificado por esta auditoría.

### Puede esperar

La optimización extensa de búsqueda espacial, deltas de grilla y compactación del historial puede esperar mientras el laboratorio siga siendo pequeño y las sesiones cortas, con los disparadores anteriores documentados. También pueden esperar los sistemas futuros que ya estaban explícitamente fuera de alcance. La revisión no recomienda cambiar la falta de regeneración, el beneficio compartido de cámara lenta, el descarte al abandonar o los objetos sin física.

### Comprobación de conservación del trabajo

Las ejecuciones terminaron y se verificó el estado de Git: los cambios locales iniciales se conservaron. La única incorporación intencional de esta auditoría es `docs/net/auditoria_inventario_salud_red_2026-11-04.md`. No se corrigió implementación durante la revisión.
