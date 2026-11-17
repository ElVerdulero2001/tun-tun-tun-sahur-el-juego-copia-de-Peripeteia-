# Plan de refactorización y reconstrucción de la sincronización de objetos

**Estado actual, entrega 11:** [revisión de Claude 10 y API de autoridad/recuperación](entregas/revision_codex_entrega_10.md). El adaptador local está validado en su alcance; las nuevas entradas separan revisión/tick, rechazan otros ámbitos, confirman acciones mediante estado posterior y recuperan historia corregida sin repetir al actor. Once escenarios propios pasan. Todavía son entradas y checkpoints locales inyectados: faltan transporte, conexión con NetSync, múltiples manos, catálogo, presentación y notebook. La condición 4 completa y la migración siguen sin aprobar. Los estados anteriores son historial.

**Avance de construcción, entrega 8:** existe un núcleo Rapier por instancia, sin StateManager ni servidor global. [Resultados, límites y puerta independiente](entregas/entrega_8_nucleo_nativo.md). Pasan fixtures propias de identidad, aislamiento, replay y una suelta tardía por ENet; todavía no se aprobó el modelo completo ni se migró el laboratorio. Las decisiones anteriores se conservan como historial.

**Decisión después de la validación 5:** se rechaza integrar `StateManager3D` publicado como predictor aislado por R3/R4 reproducidos. El siguiente candidato será un [núcleo nativo con mundos de objetos propios](contrato_nucleo_fisico_objetos.md), conservando Jolt para el personaje. [Entrega 6, correcciones y bloqueo de compilación](entregas/revision_codex_entrega_5.md). La capacidad básica de replay confirmada debajo no aprueba la integración.

**Actualización de capacidad (entrega 5, 2026-11-16):** Rapier v0.36.0 restauró y repitió contactos en una fixture de tres cuerpos, localmente y mediante checkpoint entre dos procesos con IDs distintos. [Evidencia y límites](entregas/ensayo_rollback_rapier_entrega_5.md). No se aprobó el modelo de red ni se migró el laboratorio; falta comprobar aislamiento de espacios, topología y el controlador real. Las decisiones y limitaciones históricas de Jolt que siguen se conservan como antecedentes.

## Estado y decisión

**Plan de trabajo; implementación pendiente.** Este documento no cambia la lógica del juego ni certifica una solución. Se apoya en el [diagnóstico de suelta y lanzamiento](diagnostico_suelta_y_lanzamiento_objetos.md), el `kavi.txt`, el video de la prueba y el código actual. La referencia funcional sigue siendo [objetos_fisicos.md](objetos_fisicos.md).

**Avance del 2026-11-16:** se construyó una primera entrega experimental en `prototypes/objetos_red/`, sin migrar el laboratorio. [Coordinación, base preservada y estado](coordinacion_refactor_objetos.md). Codex construye e integra; Claude realiza las pruebas independientes. La puerta de viabilidad de la etapa 1 sigue pendiente.

**Resultado de esa puerta:** Claude refutó el traslado de errores históricos y los proxies cinemáticos retrasados. Se retiró el primer mecanismo y se corrigieron contratos en una entrega 2; **la etapa 1 no está aprobada**. El caso tardío y los contactos dinámicos siguen bloqueados. La siguiente alternativa requiere demostrar restauración y repetición física de una isla mediante una integración real; todavía no existe en este prototipo. Ver [revisión y evidencia](entregas/revision_codex_entrega_1.md).

La decisión propuesta es **reconstruir el recorrido de simulación, sincronización y presentación de los objetos**, conservando los sistemas que lo rodean. El host conserva la autoridad; el jugador local debe poder agarrar, mover, soltar y lanzar con respuesta inmediata. La predicción local con Jolt es el modelo que se debe comprobar antes de migrar el laboratorio.

La primera entrega será un prototipo pequeño con resultados comparables entre host e invitado. Si no supera las condiciones físicas, temporales y de rendimiento, se revisa el modelo antes de trasladarlo al resto del sistema. No se prolonga la caída manual mediante excepciones por altura, objeto o superficie.

## 1. Alcance y comportamiento que se conserva

| Se reconstruye | Se conserva y se verifica al integrar |
| --- | --- |
| Relación entre tick de red y paso físico del objeto | Simulación y red del personaje, parkour y cámara |
| Predicción de la mano y del objeto recién soltado | Controles, preferencias, prioridades de interfaz y valores de Tuning |
| Confirmaciones de agarre, suelta y lanzamiento | Autoridad del host, alcance y validación del acceso |
| Identidad temporal de eventos y muestras | Catálogo, tipos de objeto, cantidades y versiones del inventario |
| Corrección física y traspaso a representación remota | Formas físicas preparadas por el editor, masa, centro de masa y materiales |
| Responsable único de la pose visible | Hitbox de selección independiente del cuerpo, punto de agarre e indicador |
| Pruebas de trayectorias, contactos y transiciones | Inventarios, contenedores, barra rápida, miniaturas y herramienta de objetos |

Reglas que no deben cambiar durante la reconstrucción:

- Un objeto tiene un solo dueño de agarre y cada jugador sostiene como máximo uno. Estar sostenido sigue siendo estar en el mundo.
- El host decide las transacciones. La predicción no concede permisos para recoger, atravesar paredes ni apropiarse de objetos ajenos.
- Se conserva el agarre por el punto seleccionado, la rotación, la distancia de la mano y sus límites. Se prueban la tabla larga y los objetos con centro de masa desplazado.
- Los objetos físicos chocan con el nivel, las escaleras y otros objetos; se mantiene la decisión actual de que no choquen con los personajes. La comprobación de espacio al sacar algo del inventario sigue evitando aparecer dentro de un personaje.
- Recoger parcialmente una pila deja el sobrante en el mundo y, cuando corresponda, en la mano. Retirar un apoyo despierta a los cuerpos que dependían de él.
- Muerte, desconexión, cambio de personaje, distancia excesiva, obstrucción y apertura de interfaces conservan las reglas actuales de finalización del agarre.
- La pausa individual y la cámara lenta deben funcionar sin integrar dos veces el tiempo. Se respeta el orden actual entre usos de consumibles y pedidos de inventario.
- La entrada tardía a la partida debe recibir el estado completo y vigente. No se simula todo el mundo otra vez en cada cliente.

La reconstrucción se desarrolla dentro del laboratorio y de sus componentes de inventario. No agrega autoloads ni cambia la autoridad del movimiento del personaje. Una adaptación de los campos de input o de los puntos de conexión con el reloj no autoriza a rehacer su simulación.

## 2. Qué se aprovecha y qué se sustituye

| Pieza actual | Tratamiento |
| --- | --- |
| `InvItemPhysics`, `InvBodyShape`, recursos preparados y editor | Reutilizar. Verificar que host y predictor usan las mismas formas y parámetros; no regenerar el catálogo para disimular divergencias |
| `InvReach`, hitboxes, índice espacial e historial para el rayo | Conservar las reglas. Actualizar el índice visible desde el nuevo presentador y mantener separado el historial autorizado |
| `InvHoldMotion` | Reutilizar cálculos de objetivo, límites y consultas útiles. Separar esas funciones del resolvedor de movimiento libre; consultar una pared no sustituye a Jolt |
| Protección de contactos y checkpoint del agarre | Conservar la garantía: un contacto nuevo invalida una adopción insegura y uno ya incorporado no provoca rechazos perpetuos. Adaptar su representación al nuevo contrato |
| `NetSync.input_packets` y filtro de revisiones antiguas | Conservar las garantías de tamaño y orden. Recalcular tamaños con los nuevos campos; no perder redundancia para que el paquete quepa |
| Espera de actor simulado y reloj sincronizado | Conservar. Agregar el estado de preparación del predictor antes de admitir acciones locales |
| `InvHands._fall` y su uso para adelantar muestras | Sustituir por predicción física comprobada. No mantener un segundo resolvedor de caídas como alternativa oculta |
| `_free`, `_blend` y retorno por duración fija | Sustituir por estados y una política explícita de tiempo. El vencimiento de un temporizador no demuestra que dos representaciones coincidan |
| Escrituras de pose repartidas entre mano, copias y mezcla | Concentrar la presentación en un solo responsable por objeto |
| Pruebas existentes | Conservar las regresiones útiles y corregir las lagunas de cobertura. El total de comprobaciones no es el criterio de aprobación |

## 3. Contratos del sistema nuevo

### 3.1 Tres responsabilidades separadas

**Autoridad:** decide quién puede actuar, ordena las acciones y publica resultados. Solo el host modifica el estado canónico del mundo y del inventario.

**Simulación:** mantiene el cuerpo físico autorizado o el predictor local. La mano entrega un objetivo y límites al controlador; Jolt resuelve el movimiento y los contactos. El predictor puede equivocarse y ser corregido sin convertirse en autoridad.

**Presentación:** elige qué muestra se dibuja y cómo se reduce un error visual. Mantiene aparte el transform físico y el desplazamiento del modelo. Ninguna pose suavizada se reutiliza como estado inicial autorizado de una suelta.

No hace falta crear una clase por cada concepto. Sí debe existir una frontera verificable: ninguna ruta puede escribir por fuera del responsable de presentación y ninguna corrección visual puede aplicar un impulso físico.

### 3.2 Identificadores y estados

El contrato definitivo debe contener, al menos, los siguientes conceptos. Se fija el tamaño de cada campo después del prototipo y se documentan sus límites y comparación; no se reutiliza sin más el contador de un byte del agarre.

| Dato | Finalidad |
| --- | --- |
| ID de objeto e identidad de su aparición en el mundo | Separar un cuerpo vigente de paquetes anteriores a recogerlo, destruirlo o volverlo a crear |
| Revisión autoritativa de estado | Ordenar cambios entre libre, sostenido, retirado y reaparecido; sigue siendo significativa al soltar |
| Sesión de conexión, dueño y sesión de agarre | Invalidar órdenes de otro dueño, de un agarre anterior o de una conexión anterior |
| ID de acción y última acción procesada | Hacer idempotentes las acciones y relacionar una confirmación con la predicción exacta |
| Tick solicitado, tick aplicado y tick físico de la muestra | Distinguir intención, ejecución y estado observado; no etiquetar un paso pendiente como ya simulado |
| Pose, velocidades lineal y angular, reposo y punto de agarre cuando corresponda | Reconstruir el estado necesario sin inferirlo desde el dibujo |

La revisión de transición, la revisión de corrección del agarre y el número de muestra tienen responsabilidades diferentes. No se incrementa la revisión de transición en cada snapshot. Una eliminación conserva información suficiente para rechazar poses antiguas hasta que expire la ventana de tráfico admitida.

El **estado de dominio del host** es uno de `LIBRE`, `SOSTENIDO` o `FUERA_DEL_MUNDO`. El **modo de representación local** es independiente:

| Modo local | Regla de entrada y salida |
| --- | --- |
| Réplica remota | Muestras autorizadas en el reloj de interpolación; sin cuerpo local que empuje el mundo |
| Agarre solicitado | Anticipación provisional identificada por acción; concesión o rechazo resuelve el estado sin duplicar el objeto |
| Agarre propio predicho | Dueño confirmado y controlador local activo; guarda historia física y de inputs |
| Libre propio predicho | Suelta o lanzamiento ejecutado localmente; continúa con física mientras se confirma y reconcilia |
| Traspaso a réplica | Ya tiene confirmación y muestras compatibles; conserva continuidad temporal y espacial antes de ceder la presentación |
| Retirado | No puede revivir por una pose o confirmación antigua; respeta la política temporal de retirada del mundo |

Debe existir una tabla de transiciones con evento, precondición, efecto físico, efecto visual y respuesta a rechazo. Soltar o lanzar antes de recibir la concesión del agarre se registra como intención dependiente de ese mismo pedido; al rechazar el agarre se cancela. No queda una orden sin objeto ni se lanza tras un rechazo.

### 3.3 Tiempo físico: condición previa, no detalle posterior

El `SimClock` actual cambia el ritmo del cliente entre 57 y 72 ticks por segundo mediante `Engine.physics_ticks_per_second` y compensa con `Engine.time_scale`: ejecuta un tick lógico por `_physics_process`, con duración física objetivo constante, o escalada durante cámara lenta. Varios pasos por cuadro de dibujo no significan varios ticks lógicos sin sus pasos físicos. La lectura actual de los cuerpos se etiqueta como `tick - 1`. **Se debe comprobar el orden real entre callback, lectura, preparación y paso terminado; repetir manualmente ticks del personaje no implica replay de cuerpos Jolt.**

El prototipo debe definir y registrar:

1. Cuándo se captura el input, cuándo se entrega el objetivo al cuerpo y cuándo termina el paso físico que lo aplicó.
2. Cómo se relacionan el tick del actor, el paso físico y el tick del host, incluso cuando el reloj acelera, frena o se resincroniza.
3. Qué duración del mundo integra cada paso, incluyendo cámara lenta y pausa. No basta con que ambos lados tengan el mismo valor de gravedad.
4. Cómo se compara una muestra del host con la historia física local correspondiente; no se comparan estados de instantes diferentes como si fueran errores de posición.

Se prefiere una adaptación para los objetos que conserve el reloj del personaje. Si la API y la planificación reales no permiten una correspondencia válida, esta fase queda bloqueada y se presenta la alternativa concreta antes de ampliar el cambio al reloj global.

### 3.4 Confirmación de suelta y lanzamiento

- Un pedido lleva objeto, aparición, sesión, acción y último tick de sujeción solicitado. La confirmación incluye aceptación o motivo de rechazo, tick realmente aplicado, revisión resultante, pose y velocidades físicas de salida.
- Si el tick solicitado todavía no fue simulado y entra en la ventana admitida, el host programa la acción después de ese paso. Si ya pasó, la propuesta inicial es aplicarla en el siguiente límite físico seguro con el estado actual autorizado y declararla tardía. No se reconstruye una pose pasada atravesando el mundo.
- Los ticks futuros fuera de la ventana se rechazan; las acciones con dependencias válidas pendientes esperan solo dentro de límites documentados. Nunca se espera indefinidamente un input o un consumible ausente.
- El lanzamiento aplica el impulso una sola vez. Un duplicado recibe el resultado registrado; no vuelve a soltar ni vuelve a sumar velocidad. Se conserva la velocidad física que llevaba el cuerpo y no se añade de nuevo la velocidad del personaje sin una decisión de diseño expresa.
- La suelta automática usa el mismo recorrido autoritativo, cancela intenciones incompatibles y avisa su causa. Una confirmación tardía de agarre no la deshace.
- Eventos confiables y poses pueden llegar en distinto orden. Se almacenan temporalmente o descartan según identidad y revisión; una pose adelantada no habilita por sí sola un agarre ni resucita un cuerpo retirado.

La llegada tardía puede exigir una corrección real: el contrato debe explicar su causa y medirla. La meta no es ocultar toda diferencia causada por la red, sino evitar diferencias fabricadas por modelos incompatibles o por ejecutar mal el mismo evento.

### 3.5 Predicción, contactos y corrección

La primera implementación busca predecir **el cuerpo propio**, con las mismas formas, masa, centro de masa, materiales, amortiguación, CCD y controlador que el host. Los remotos mantienen su representación de red. No se activan cuerpos para todo el catálogo en el invitado.

Para los contactos dinámicos, el primer candidato son proxies físicos acotados de vecinos relevantes, alimentados con muestras identificadas temporalmente. Son representaciones auxiliares: no modifican inventarios ni convierten su movimiento en el estado canónico de otro jugador. No se usan a la vez un proxy y otra colisión del mismo objeto. Su diferencia de tiempo y su política de actualización deben quedar visibles en la traza.

Este candidato debe probarse contra un segundo cuerpo móvil y un apoyo. Si mueve artificialmente al predictor, produce rebotes repetidos o necesita simular una isla de cuerpos para ser estable, se evalúa esa alternativa con un límite de costo explícito. **No se aprueba la predicción ignorando el contacto con otros objetos que el host sí resuelve.**

La reconciliación inicial se estudia sin rollback del mundo: comparar estado autorizado e historia del mismo instante, trasladar la corrección al presente de forma comprobable y aplicarla en un límite físico seguro. Esa traslación es una aproximación cuando hubo contactos posteriores; debe detectarlos y tener una política expresa de recuperación. No se inyecta una muestra vieja como si fuera una pose del presente ni se adelanta con `_fall`.

Si hace falta replay físico, primero hay que demostrar que existe una forma soportada de avanzar el predictor y sus dependencias con pasos controlados y costo limitado. Usar Jolt en ambas máquinas no demuestra determinismo ni proporciona por sí solo esa capacidad. La política de corrección es una salida obligatoria del prototipo: no se deja para arreglarla con suavizado al final.

### 3.6 Presentación y traspaso

- El objeto propio responde en el presente local; los remotos usan el reloj retrasado. Ambos instantes se registran y no se confunden con el tick físico.
- Una sola ruta dibuja cada objeto. El host también evita mezclar la interpolación automática del motor con otra manual sobre el mismo modelo.
- La corrección física y el error visual se contabilizan aparte. El suavizado conserva continuidad desde lo que se estaba mostrando, con protección común contra atravesar el nivel.
- El traspaso necesita muestras de la misma aparición y revisión que cubran un instante compatible. No puede volver del reposo a una muestra anterior que aún estaba cayendo ni reproducir por segunda vez el contacto o el lanzamiento.
- Si faltan muestras compatibles, se mantiene una modalidad definida y acotada, se solicita recuperación y se registra la causa. Un timeout activa esa recuperación; no autoriza una mezcla arbitraria hacia el pasado.
- Reposo, despertar, retirada de un apoyo y desaparición de un objeto se presentan en orden causal con los cuerpos afectados. Se conserva la regla de selección que corresponde a lo que efectivamente ve el jugador.

## 4. Ejecución por etapas

### Etapa 0 — Congelar la referencia y preparar evidencia

**Trabajo:** registrar rama, HEAD, cambios existentes y parámetros físicos; preservar los recursos y el trabajo sin commit. Usar el video y el TXT como evidencia original y guardar una referencia legible del comportamiento y los controles. Identificar los puntos de entrada de mano, cuerpos, autoridad, réplica y reloj.

Preparar una traza optativa y acotada por objeto/acción: identidad, modo, tick de input, paso físico terminado, tick aplicado, tick mostrado, pose física, pose visible, velocidades, contacto, reposo y causa de corrección. Incluir RTT observado, edad de muestras, pérdida y estado de preparación. No volcar todos los objetos en cada cuadro.

**Salida:** referencia preservada y esquema de trazas. No se necesita repetir todas las pruebas para iniciar el prototipo.

### Etapa 1 — Prototipo físico y temporal aislado

**Trabajo:** crear una escena mínima con piso, pared fina, caja representativa y segundo cuerpo; reutilizar recursos y parámetros reales. Comparar dos modos explícitos: referencia con física solo en el host y candidato con predicción local Jolt. El modo de referencia sirve para medir; no cambia silenciosamente la interacción del laboratorio.

Resolver primero la correspondencia entre reloj lógico y paso físico. Luego probar caída, suelta y lanzamiento, sin un suavizado que pueda ocultar el error. Agregar corrección y traspaso solo después de medir las trayectorias físicas. Probar un contacto dinámico antes de aprobar el modelo.

**Salida:** política escrita de pasos, contactos, reconciliación y retorno a réplica, acompañada de trazas comparables. Debe mostrar respuesta inmediata y convergencia sin rebote añadido por presentación. También debe funcionar cuando el reloj corrige su ritmo y durante cámara lenta.

**Puerta de decisión:** si requiere un replay que no puede ejecutarse, un predictor de todo el mundo o correcciones perceptibles repetidas en un caso ordinario, no se migra. Se documenta el límite y se compara la alternativa con su costo de latencia. Cambiar la respuesta inmediata por espera al host es una decisión de diseño que debe consultarse, no un resultado aprobado por defecto.

### Etapa 2 — Contrato estable, estados y transporte

**Trabajo:** trasladar lo comprobado a contratos compartidos, implementar identidades, revisiones y transiciones; actualizar serialización, confirmaciones y réplica. Mantener las reglas existentes del inventario y el orden de sus dependencias.

Subir la versión de protocolo y su huella cuando cambie el formato; actualmente `InvProtocol.VERSION` es 3. Rechazar clientes incompatibles al conectar. Preservar el presupuesto de payload de inputs de 1200 bytes, medir también los nuevos paquetes de objetos y dividirlos por tamaño real. Probar registros máximos, duplicados, reorden y acciones de otra sesión.

**Salida:** eventos idempotentes y muestras inequívocas, con pruebas de transición y de tamaño. Ningún paquete antiguo puede restaurar un agarre terminado, un objeto recogido ni un impulso ya aplicado.

### Etapa 3 — Migrar el agarre y su controlador

**Trabajo:** conectar intención de mano, concesión del host y predictor. Usar el punto de agarre autorizado y el mismo controlador de objetivos y límites en ambas máquinas. Integrar protección de contactos y adopción validada donde siga siendo aplicable; no extender la adopción del agarre a autoridad libre sobre trayectorias o impactos.

Probar mover, girar, cambiar distancia, contacto persistente, contacto nuevo, esquina, pared fina, punto de agarre lejano al centro y solicitudes simultáneas de dos jugadores. Un agarre rechazado vuelve al estado autorizado sin dejar una copia física activa.

**Salida:** agarre completo estable, con una sola simulación local pertinente y una sola presentación. Esta etapa no se aprueba solo con el objeto suspendido en aire libre.

### Etapa 4 — Migrar suelta, lanzamiento y retorno a réplica

**Trabajo:** conectar la transacción de salida, continuidad física del predictor, confirmación y corrección demostradas en el prototipo. Integrar el presentador único. Eliminar del recorrido nuevo la caída manual y el blend fijo hacia snapshots anteriores.

Cubrir suelta quieto y caminando, lanzamiento, confirmación tardía, rechazo, acción anterior a la concesión, reposo y despertar. Separar el resultado de la suelta del impulso del lanzamiento, aunque compartan infraestructura.

**Salida:** reproducción del caso del `kavi.txt` con comparación host/invitado y medición de contacto, elevación posterior y traspaso. No debe existir un rebote añadido únicamente al cambiar de modo de dibujo.

### Etapa 5 — Integrar el ciclo completo del mundo

**Trabajo:** recoger y sacar del inventario, cantidades parciales, apoyos y pilas, retirada temporal, suelta automática, rescate fuera del mapa, desconexión y entrada tardía. Verificar limpieza de predictor, proxies, historial y solicitudes al reiniciar la sesión o cambiar de personaje.

**Salida:** un objeto solo existe en su lugar válido, las cantidades se conservan y no quedan cuerpos invisibles, colisiones duplicadas ni paquetes capaces de revivirlo. Resolver también la discrepancia pendiente del instante en que cae una pila al retirar su apoyo; no ampliar el margen de la prueba para hacerla pasar.

### Etapa 6 — Validación en red y en las dos PC

**Trabajo:** ejecutar la matriz acotada de la sección 6 y después una pasada de las regresiones pertinentes de inventario, selección, red y editor. Comparar rendimiento con la referencia en el equipo objetivo; separar costo de física, proxies, presentación y tráfico.

Hacer una prueba visible en las dos PC, alternando quién hospeda, con grabaciones o trazas simultáneas. Repetir específicamente las acciones descritas en el TXT, incluyendo suelta en movimiento. El resultado automatizado no sustituye esta comprobación de la interacción real.

**Salida:** resultados con parámetros, evidencia, divergencias y límites. No se declara terminada la reconstrucción mientras falte la prueba real o quede un fallo del caso original sin explicar.

### Etapa 7 — Retirar el recorrido anterior y actualizar la documentación

**Trabajo:** borrar el predictor manual y las rutas de presentación sustituidas una vez que el nuevo recorrido esté aprobado. Retirar flags temporales y código de comparación que ya no haga falta; conservar una escena de regresión reproducible y trazas optativas.

Actualizar `objetos_fisicos.md`, la guía, formato de paquetes y mapa de archivos. Marcar qué diagnósticos son historia y qué límites siguen vigentes. Revisar que no haya escrituras de pose o controladores activos fuera del contrato.

**Salida:** una arquitectura operativa, sin dos implementaciones activas de la misma acción ni documentación que afirme correcciones no verificadas.

## 5. Mapa de responsabilidades y archivos

Los nombres finales de auxiliares pueden ajustarse al prototipo. La división de responsabilidades es obligatoria; no lo es multiplicar archivos.

| Zona actual | Responsabilidad después de la migración |
| --- | --- |
| `scripts/inventory/inv_authority.gd` | Estado canónico, permisos, orden y resultado idempotente de las acciones |
| `scripts/inventory/inv_protocol.gd`, `inv_net.gd`, `inv_replica.gd` | Contratos, codificación, validación, orden entre eventos y snapshots y estado completo al entrar |
| `scripts/inventory/inv_bodies.gd` | Ciclo de cuerpos autorizados y sus muestras; delegar presentación y predicción para no concentrar todo aquí |
| `scripts/inventory/inv_hands.gd` | Intención local e interacción; delegar predicción física, reconciliación y dibujo |
| `scripts/inventory/inv_world_item.gd` | Cuerpo y visual con roles explícitos; separar el cuerpo físico del modelo que puede llevar desplazamiento visual |
| `scripts/inventory/inv_hold_motion.gd` | Controlador compartido de la mano y consultas geométricas útiles; sin resolvedor paralelo de caída |
| Auxiliar de predicción, si hace falta | Historia física local, contactos auxiliares, corrección y preparación/limpieza |
| Auxiliar de presentación, si hace falta | Reloj mostrado, selección de fuente y continuidad entre modalidades |
| `scripts/net/net_sync.gd`, `scripts/actor/actor_input.gd`, conexiones de `net_lab.gd` | Adaptaciones de transporte y captura de acciones; conservar la simulación del personaje |
| `scenes/net_lab/inventario/pruebas/` | Escena mínima, regresiones de transición y comparación de trayectorias |

Se puede activar el recorrido nuevo mediante una opción de desarrollo al iniciar la escena. No se permite cambiar de recorrido en mitad de un agarre sin reiniciar sus estados y cuerpos. Por objeto y máquina hay un único controlador físico pertinente; la comparación entre implementaciones se hace en corridas o espacios aislados, nunca empujando dos veces el mismo mundo.

## 6. Matriz de aceptación

### Métricas y criterios

La traza debe permitir separar tres preguntas: qué simuló cada máquina en el mismo instante, qué corrección produjo la autoridad y qué movimiento agregó la presentación. Comparar cuadros de llegada sin alinear tiempos confunde latencia con error físico.

Registrar por caso:

- Pose y velocidades de salida; tick solicitado y aplicado; número de aplicaciones del impulso.
- Primer contacto, penetración máxima, elevación máxima posterior y cambios de velocidad vertical. Comparar también el giro: una caja puede levantarse al girar sin un rebote del centro de masa.
- Error de posición y ángulo contra la historia autorizada alineada; causa y tamaño de cada corrección, diferenciando contacto y ausencia de contacto.
- Salto visible al corregir o cambiar de modalidad, instante físico representado y duración hasta converger.
- Cantidad de predictores y proxies, duración de pasos, bytes y edad de muestras.

Antes de evaluar resultados se fijan tolerancias geométricas a partir de las formas, la cuantización y los parámetros reales; se registran en la prueba. No se ajustan después de observar un fallo para convertirlo en éxito. En red no se exige identidad perfecta entre mundos con información distinta, pero sí ausencia de impulsos duplicados, regresos a revisiones antiguas y rebotes creados por la presentación. Una divergencia física repetida en el caso cotidiano impide aprobar el modelo aunque el dibujo la oculte.

| Caso | Evidencia necesaria para aprobar |
| --- | --- |
| Caída desde 0,2; 0,5 y 1 m sobre la misma superficie | Trayectoria y primer contacto comparables; elevación posterior atribuible a física registrada, sin subida añadida por corrección visual |
| Caja con restitución nula en el prototipo y caja con material real | El control sin rebote detecta movimiento artificial; el material real conserva su respuesta física. No cambiar el material del juego para aprobar |
| Soltar quieto, caminando, frenando y girando | Velocidad de salida coherente con el cuerpo, sin sumar dos veces la del jugador ni arrancar desde el offset visual |
| Lanzar en aire y contra pared fina | Un impulso por acción, sin cruce de pared; cambios de trayectoria explicables por contactos o correcciones identificadas |
| Agarre contra pared y esquina; tabla por una punta | Sin adopción a través del nivel, oscilación persistente ni bloqueo perpetuo por un contacto ya incorporado |
| Choque con cuerpo quieto, cuerpo móvil y pila | Política dinámica comprobada; no se ocultan contactos que el host sí resuelve ni aparecen dobles colisiones |
| Dormir, despertar y devolver a réplica | Sin volver a una caída anterior, segundo impacto ni desplazamiento generado por el cambio de reloj |
| Retirar o recoger un apoyo | Desaparición y caída en orden causal, cantidades correctas y margen temporal original satisfecho |
| Duplicado, reorden, suelta tardía y muestra vieja tras recogida | Una acción efectiva, confirmación correcta y ninguna resurrección o reapropiación |
| Dos agarres simultáneos, rechazo y salida antes del ACK | Un dueño, cancelación coherente y ningún predictor huérfano |
| Muerte, desconexión, reconexión y entrada tardía | Estado completo vigente y liberación/limpieza de sesiones anteriores |
| Cámara lenta, pausa y resincronización del reloj | Tiempo integrado correcto, sin pasos ficticios, doble escala ni historia incompatible reutilizada |
| Muchos dormidos lejos y contactos cercanos | Predictor limitado al entorno pertinente; costo y tráfico medidos sin recorrer o simular todo el mundo en el cliente |

Los casos físicos centrales se ejecutan primero en conexión local sin degradación. Luego se repiten con **200 ms de RTT, jitter de ±40 ms y 5 % de pérdida configurada**, anotando qué significa cada parámetro en el simulador y cuánto se observó realmente. Agregar un caso dirigido de demora/reorden del evento de salida; no basta esperar que el azar lo produzca. Si ENet reduce su throttle, se registra: la pérdida efectiva puede superar la configurada.

### Ejecución breve y controlada

- Una hipótesis y una escena enfocada por corrida. La captura de métricas se apaga fuera de la prueba.
- Límite externo inicial de **20 segundos por caso automatizado enfocado**, incluyendo preparación, con plazo menor de preparación y cierre explícito. Si un caso necesita más, se divide o se documenta su duración antes de lanzarlo. Las pruebas manuales quedan fuera de ese límite.
- Error de carga, parseo, proceso hijo muerto o preparación que vence: terminar los procesos propios de esa corrida, informar y corregir. No esperar al final de una batería para enterarse de que el cliente no arrancó.
- Como máximo host e invitado para estos casos; el tercer jugador se usa solo para carreras o regresiones que lo requieran. Sin procesos abandonados ni múltiples baterías en segundo plano.
- No forzar un reloj acelerado de headless para sacar conclusiones sobre latencia real. Registrar tiempo real y tiempo simulado.
- Después de aprobar el caso dirigido, avanzar. Las baterías amplias se ejecutan al integrar; se repiten solo si un cambio o fallo nuevo lo justifica.
- Informar qué se aprendió y el siguiente criterio pendiente. Si una comprobación falla, no encadenar semillas y ajustes de umbral sin una causa identificada.

## 7. Condiciones para cerrar la reconstrucción

La entrega se considera completa cuando:

1. El prototipo demostró una relación válida entre inputs, ticks y pasos de Jolt, junto con una política viable de contactos y reconciliación.
2. El recorrido integrado usa una sola simulación pertinente y una sola presentación por objeto; no depende de la caída manual sustituida.
3. Suelta y lanzamiento tienen confirmación, estado físico de salida y ejecución idempotente; el tráfico antiguo no revierte estados.
4. Los casos del video/TXT y las regresiones de agarre, pared, pila e inventario cumplen sus criterios, con evidencia simultánea de ambas máquinas.
5. La prueba en las dos PC está realizada y el costo medido es aceptable en el equipo objetivo. Si todavía no pudo hacerse, la entrega se declara pendiente de esa validación.
6. Se retiraron las rutas reemplazadas y la documentación explica el sistema que realmente quedó.

El orden de trabajo es **prototipo verificable → contratos estables → agarre → suelta y presentación → ciclo del mundo → validación real → limpieza**. Cada etapa deja un resultado evaluable; un fallo del modelo vuelve a la decisión técnica correspondiente, no abre otra capa de excepciones.
