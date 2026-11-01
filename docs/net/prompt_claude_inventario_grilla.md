# Prompt para Claude: inventario de grilla nuevo en net-lab

Implementá un sistema de inventario de grilla funcional en este repositorio de Godot. Trabajá sobre el apartado `net-lab`, usando su personaje, movimiento y arquitectura de red actuales como base.

## 1. Objetivo y alcance

Estamos construyendo una base nueva del proyecto. El inventario se hace **desde cero**; no hay que conectarlo al inventario anterior ni a PlayerV2, reconstruir sistemas anteriores ni migrar sus datos. La implementación anterior puede consultarse para entender errores o antecedentes, pero no debe convertirse en una dependencia del sistema nuevo.

La captura adjunta es una referencia de disposición: grilla principal a la izquierda, mundo visible detrás y barra rápida abajo. No hace falta copiar marcos, decoración, tipografía, materiales, dinero, minimapa, brújula ni botones de diario o notas. Priorizá funcionalidad y legibilidad con controles simples de Godot.

El resultado debe funcionar tanto jugando solo como en cooperativo desde esta implementación: cada jugador tiene su inventario independiente y varios jugadores pueden acceder a un mismo contenedor compartido. El host valida y confirma los cambios.

No te limites a proponer una arquitectura: implementá el sistema, integralo al laboratorio y dejalo comprobable.

## 2. Revisar el contexto antes de modificar

Leé las instrucciones aplicables del repositorio y `docs/net/guia_del_laboratorio.md`. Consultá `docs/net/arquitectura_coop_y_esqueleto_de_red.md` y el código actual cuando necesites aclarar un contrato. El código vigente manda frente a documentación histórica.

Identificá el actor actual, cómo se determina el jugador local, cómo se crean y eliminan actores, cómo funciona la cámara, cómo se capturan entradas y cómo se comunican host y clientes. Verificá la versión real de Godot y las herramientas disponibles; no asumas la versión del inventario antiguo.

Trabajá dentro de la estructura del laboratorio. Podés crear componentes reutilizables en carpetas nuevas y claramente separadas, pero su integración debe depender de `net-lab`, no de escenas o servicios del juego anterior. No cambies la escena principal del proyecto ni los ajustes de exportación sin necesidad.

Antes de editar, explicá brevemente el diseño, los puntos de integración y qué archivos existentes necesitás tocar. Después continuá con la implementación por etapas sin pedir confirmación por cada paso rutinario. Avisá antes de modificar assets existentes, modelos, texturas, materiales, `.tres` o escenas de gameplay; no los cambies por motivos estéticos. Los recursos y escenas nuevos de prueba pueden ser simples.

## 3. Reglas de arquitectura

- Inventario como componente por entidad, utilizable por jugadores y contenedores. Nada de un inventario global, nuevo Autoload, singleton o EventBus global.
- Dependencias explícitas por referencias y composición de escenas. No localizar al dueño mediante búsquedas globales, grupos ambiguos o rutas rígidas entre árboles ajenos.
- Separá definición del tipo de objeto, instancia concreta, ubicación en la grilla, presentación y validación de operaciones. No dupliques datos autoritativos en la UI.
- Cada instancia o pila tiene un identificador estable. La posición y la orientación pertenecen a su colocación en un inventario. La barra rápida referencia identificadores, no índices de una lista.
- Los recursos de definición compartidos no se modifican en runtime para guardar cantidades, posiciones o estado individual.
- La lógica de grilla debe poder probarse sin cámara, interfaz ni física. La interfaz solicita operaciones; no escribe directamente el estado confirmado.
- Reutilizá la infraestructura de red del laboratorio mediante componentes específicos de inventario. No crees una segunda arquitectura de red ni mezcles las reglas del inventario con el cálculo del parkour.
- Evitá dependencias circulares entre escenas y recursos. Los mensajes de red transportan datos e identificadores validados, no nodos, recursos ni rutas arbitrarias aportadas por el cliente.

## 4. Grilla, colocación y manipulación

La grilla tiene columnas, filas y tamaño visual de celda configurables. Usá inicialmente 12 columnas por 16 filas como valor de prueba, fácil de cambiar desde el Inspector. No deduzcas un número obligatorio de celdas de la captura.

Cada tipo de objeto define su tamaño rectangular en celdas: por ejemplo 1×1, 1×2, 2×2 o 2×3. Puede permitir o prohibir rotación. Girar 90 grados intercambia ancho y alto.

Implementá arrastrar con botón izquierdo y rotar con `R` durante el arrastre. Mostrá una representación que siga al cursor y la huella de colocación en verde si es válida o rojo si es inválida. Conservá de forma coherente el punto por el que se agarró el objeto al moverlo y rotarlo.

No permitas superposiciones ni posiciones fuera de la grilla. Al mover un objeto dentro del mismo inventario, su posición original no debe bloquear su propia colocación. Rechazar una operación no mueve, rota, elimina ni duplica el objeto confirmado.

Arrastrar es una intención visual local: el objeto sigue perteneciendo a su origen hasta que el host confirma la operación. Mostrá claramente las operaciones pendientes y evitá enviar varias veces la misma acción por clics repetidos. No implementes intercambio automático de objetos ocupados en esta versión.

Si el arrastre se cancela o la posición es inválida, restaurá la representación del estado vigente. Si otro jugador cambió el origen durante el arrastre, descartá la intención y refrescá el estado real; no restaures una copia vieja sobre datos nuevos.

## 5. Recoger y soltar objetos del mundo

Implementá objetos recogibles en el laboratorio. Deben tener una definición, identidad y cantidad cuando corresponda. Recoger requiere interacción válida y cercanía comprobada por el host.

Al recoger, completá primero pilas compatibles y después buscá posiciones libres de forma determinista. Permití recogida parcial si solamente cabe una parte: lo restante queda en el mundo con la cantidad correcta. Si no cabe nada, no cambies el estado y mostrale el motivo al jugador.

Permití soltar mediante el menú contextual y arrastrando fuera de las zonas de inventario. No interpretes como soltar al mundo una liberación sobre un menú, un diálogo o la barra rápida. Un intento sobre una zona inválida de un panel se rechaza; no debe provocar un drop accidental.

Soltar una pila completa o una cantidad elegida crea su representación física en una posición cercana válida, calculada y comprobada por el host usando el actor actual. Evitá aparecer dentro del jugador, paredes o contenedores. Si no hay posición válida o falla la creación, la operación se rechaza conservando el inventario.

El cambio mundo ↔ inventario es atómico: un objeto no puede quedar en ambos lugares ni desaparecer. Recogida y drop se replican a los participantes relevantes. No aceptes como verdadera una posición de drop o una distancia enviada por el cliente.

## 6. Pilas y división de cantidades

Cada definición establece si se apila y su cantidad máxima por pila. Las cantidades son enteras positivas; rechazá valores inválidos y cantidades superiores a las existentes.

Apilá solamente objetos del mismo tipo y con estado compatible. Dos objetos con distinta condición, contenido u otro estado significativo no se fusionan por compartir nombre o icono. Documentá qué datos determinan la compatibilidad.

Arrastrar una pila sobre otra compatible transfiere hasta su capacidad máxima; el sobrante permanece en el origen. Arrastrarla sobre un objeto incompatible rechaza la operación. Una pila siempre ocupa la huella de su definición, sin importar la cantidad.

El menú contextual permite dividir indicando una cantidad entre 1 y cantidad original menos 1 y eligiendo una posición válida para la pila nueva. Hasta confirmar esa colocación, la división es tentativa. Cancelar o quedarse sin espacio deja el estado intacto.

La pila nueva recibe un identificador nuevo y la original conserva el suyo. Al fusionar, el destino conserva su identificador. Si el origen se agota, su identificador se retira y sus accesos rápidos se limpian. No reasignes silenciosamente accesos a otra pila del mismo tipo.

## 7. Contenedores y transferencias

Creá un contenedor de prueba interactuable. Al abrirlo, mostrá el inventario del jugador y la grilla del contenedor simultáneamente. Permití arrastrar en ambas direcciones, incluyendo rotación y apilado compatible entre inventarios.

Validá origen, destino, cantidad, orientación, espacio disponible y permiso de acceso antes de modificar cualquiera de los dos. Si una transferencia falla, no debe quedar aplicada a medias.

Un contenedor compartido puede estar abierto por varios jugadores. Las acciones se procesan en el host en un orden definido. Si dos jugadores intentan llevarse el mismo objeto, solamente puede confirmarse una operación; la otra se rechaza y su vista se actualiza. No bloquees todo el contenedor mientras alguien lo tiene abierto.

La distancia máxima de acceso es configurable. El host comprueba acceso al abrir y al operar; al alejarse se cierra el panel del contenedor y se cancelan las intenciones relacionadas. Manejá también la desaparición del contenedor y la desconexión del jugador sin dejar referencias ni operaciones pendientes huérfanas.

## 8. Barra rápida

Implementá diez accesos, asociados a `1`–`9` y `0`. Asignar un objeto arrastrándolo a un acceso guarda una referencia a esa instancia o pila: **el objeto continúa ocupando lugar en la grilla**. La barra no es otro inventario ni copia objetos.

Permití reemplazar, reorganizar y quitar asignaciones mediante controles claros. Los accesos muestran la imagen o representación provisional y la cantidad actual de su objeto.

Mover o rotar el objeto dentro del inventario del dueño conserva el acceso. Soltarlo, transferirlo fuera del inventario, consumirlo por completo o retirar su identificador limpia las asignaciones correspondientes. Los accesos no buscan automáticamente un sustituto del mismo tipo.

Pulsar el acceso usa o equipa según las capacidades definidas del objeto. Una acción inválida no consume nada. El host valida también el uso, el equipamiento y que el objeto siga perteneciendo al jugador.

## 9. Menú contextual, uso, equipamiento e inspección

El botón derecho abre un menú con las acciones aplicables: usar, equipar/desequipar, inspeccionar, dividir y soltar. Las acciones no disponibles se ocultan o deshabilitan con un motivo entendible.

Implementá capacidades por tipo de objeto, sin un gran bloque de condiciones basado en sus nombres. Para demostrar funcionamiento real, incluí:

- Un consumible apilable cuyo uso produzca un efecto verificable y autorizado por el host. Si el laboratorio no tiene salud, usá un contador de prueba visible claramente identificado, sin crear un sistema de salud completo. Consumí una unidad solamente si el uso fue válido.
- Un objeto equipable y un estado explícito de equipamiento, con una representación simple visible para los demás jugadores. En esta versión alcanza un objeto equipado a la vez. Equipar no lo retira de la grilla. Transferirlo o soltarlo debe desequiparlo de manera coherente. No construyas un sistema de armas ni combate para demostrar esta acción.
- Una ventana de inspección con nombre, descripción, tamaño, cantidad y propiedades relevantes de la instancia seleccionada. No implementes un visor 3D interactivo salvo que sea necesario para los requisitos ya pedidos.

No consideres implementada una acción de gameplay si solamente imprime un mensaje en consola.

## 10. Apertura, movimiento y manejo de entradas

Usá acciones del InputMap; aprovechá las existentes cuando sus significados coincidan. `Tab` abre/cierra el inventario. El cursor queda visible y libre al abrirlo, y la cámara deja de girar por movimiento del mouse.

**El mundo no se pausa y el jugador puede seguir caminando con WASD mientras organiza el inventario.** Conservá la locomoción actual sin reescribir sus reglas. No uses `SceneTree.paused` ni cambies la escala de tiempo para esta interfaz.

Los clics y atajos utilizados por la UI no deben ejecutar simultáneamente ataques, interacciones del mundo o acciones de otros paneles. Durante un arrastre, `R` pertenece al inventario. Si un campo numérico tiene foco, debe recibir sus teclas sin activar accesos rápidos ni mover al personaje mientras se edita.

`Esc` cancela primero el arrastre o diálogo activo, después cierra el menú contextual y, si no queda una operación de UI activa, cierra el inventario. `Tab` puede cerrarlo directamente cancelando las intenciones locales. Ninguno de estos cierres debe eliminar objetos ni deshacer operaciones ya confirmadas por el host.

Coordiná la captura del mouse con el mecanismo actual del laboratorio y con otros menús. No recaptures el cursor si todavía hay otra interfaz que lo necesita. Las interfaces y entradas pertenecen exclusivamente al jugador local, incluso cuando hay actores remotos en el mismo árbol.

## 11. Imágenes de los objetos

La representación final dentro de la grilla debe ser una **imagen generada a partir del modelo 3D del objeto**. Durante las primeras etapas podés usar cajas, rectángulos, colores y nombres para probar la lógica; esto es un recurso provisional, no un reemplazo permanente de la generación de imágenes.

Implementá un generador de miniaturas que encuadre el modelo completo, respete su proporción y produzca una textura con fondo transparente e iluminación suficiente. Permití ajustar orientación y encuadre por definición. Renderizá una representación visual aislada, sin activar scripts de gameplay, física ni efectos del objeto mundial.

Generá y almacená las miniaturas en caché por apariencia compartida; no mantengas un SubViewport activo por celda, por objeto o por cada apertura del panel. Usá una cola y liberá los recursos temporales. La rotación en la grilla debe tener una representación visual coherente.

La caché pertenece al sistema de presentación local, no a un Autoload nuevo. Las imágenes se generan en cada cliente; no se transmiten por red. Si falta el modelo o falla el render, usá un rectángulo con nombre como fallback. Dejá al menos una miniatura generada y funcionando con un modelo o malla simple de prueba.

## 12. Cooperativo y autoridad del host

Todas las operaciones que cambian estado confirmado pasan por solicitudes al host: recoger, soltar, mover, rotar, transferir, apilar, dividir, usar, equipar y modificar accesos rápidos. Jugar solo utiliza las mismas reglas mediante la autoridad local del host.

Validá la identidad del emisor a partir de la conexión, su actor, el inventario que puede modificar, la existencia actual de los objetos, cantidades, revisiones relevantes, acceso a contenedores y distancias. No confíes en un identificador de dueño aportado por el cliente. Validá y ejecutá en un mismo orden autoritativo, sin dejar una ventana entre la comprobación y el cambio.

Usá identificadores de solicitud y un mecanismo acotado de deduplicación para que reintentos no repitan consumos, divisiones ni drops. Rechazá solicitudes obsoletas o revalidalas contra el estado actual sin sobrescribir cambios ajenos. Una operación sobre dos inventarios debe publicarse como un único resultado lógico, sin estados intermedios visibles como confirmados.

Sincronizá el inventario propio con su dueño y los contenedores con quienes tengan acceso abierto. Replicá los objetos mundiales y el equipamiento visible a quienes corresponda. No hace falta enviar el contenido privado completo de todos los jugadores a todos los clientes.

La incorporación tardía recibe un estado coherente del mundo; al abrir un contenedor se obtiene un snapshot consistente y después sus cambios, sin perder una modificación entre ambos pasos. Una desconexión descarta suscripciones e intenciones del cliente sin revertir cambios ya confirmados. Respetá el ciclo de vida actual del actor; no inventes muerte, respawn ni persistencia de inventarios si no existen.

Si el laboratorio tiene comprobaciones de compatibilidad o huellas de código/escenas, integrá los archivos nuevos cuando corresponda. No deshabilites esos controles para hacer que una conexión funcione.

## 13. Implementación por etapas y pruebas

Organizá el trabajo en etapas comprobables: modelo y operaciones; grilla y arrastre; mundo y contenedores; pilas y división; barra y acciones; miniaturas e integración completa. La frontera de autoridad debe existir desde el comienzo, aunque pruebes primero con un solo proceso.

Creá una zona de prueba pequeña dentro del laboratorio, con objetos de distintos tamaños, uno no rotatable, pilas compatibles e incompatibles y un contenedor compartido. Evitá alterar las pistas de parkour o el comportamiento de red y movimiento existentes.

Comprobá con pruebas significativas de modelo y de integración:

1. Límites, solapamiento, rotación y movimiento sobre la propia huella; cancelación sin cambios.
2. Apilado parcial, pila llena, división cancelada, cantidades inválidas y división sin espacio.
3. Conservación de cantidades e identidad en recogidas parciales, drops y transferencias; fallo sin pérdidas ni duplicados.
4. Dos jugadores operando sobre el mismo objeto o pila, solicitudes repetidas y operaciones obsoletas.
5. Acceso rechazado a inventario ajeno o contenedor fuera de alcance.
6. Barra rápida coherente después de mover, dividir, fusionar, usar, equipar, transferir y soltar.
7. Cambios remotos durante un arrastre, cierre de paneles, desaparición de contenedor y desconexión.
8. Incorporación tardía, objetos soltados visibles y cantidades iguales en host y clientes.

Verificá visualmente la UI y el arrastre, la libertad del cursor, WASD con el panel abierto, los campos numéricos y el retorno al control de cámara. Probá los casos de red con host y cliente reales en procesos separados si el entorno lo permite. Un test de modelo no demuestra por sí solo que la replicación funciona.

Ejecutá las pruebas existentes pertinentes para confirmar que la integración no rompe el laboratorio. No agregues cientos de pruebas que solamente repitan getters o detalles internos. Si falta Godot, acceso a dos procesos o alguna capacidad del entorno, indicá exactamente qué quedó sin probar; no lo presentes como validado.

## 14. Entrega

Dejá el sistema integrado y un documento breve con:

- Arquitectura final, componentes y autoridad de cada operación.
- Cómo ejecutar la escena, controles y prueba cooperativa paso a paso.
- Cómo crear un objeto, configurar tamaño, pila, acciones y modelo para su miniatura.
- Cómo agregar otro contenedor y cambiar dimensiones de grilla.
- Archivos existentes modificados, pruebas ejecutadas, resultados y limitaciones reales.

No agregues por iniciativa propia peso, crafting, comercio, dinero, organización automática, objetos de forma irregular, mando, guardado en disco ni sistemas completos de armas o salud. No borres el inventario anterior: debe quedar fuera de la implementación nueva, sin dependencias desde el laboratorio. No hagas commit ni push salvo que yo lo pida.

Si aparece una decisión de diseño verdaderamente bloqueante que este pedido no cubre, preguntámela con alternativas concretas. Para detalles menores, elegí una solución simple, documentala y continuá.
