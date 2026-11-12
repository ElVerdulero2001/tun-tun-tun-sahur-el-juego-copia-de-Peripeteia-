# Prompt para Claude: herramienta de creación de ítems y contenedores

Este prompt describe la ampliación original del panel **Objetos**. Para una adición nueva, consultá primero la sección 4 de [Inventario de grilla](inventario_de_grilla.md#4-crear-un-ítem-o-un-contenedor) y las secciones 14 y 16 de la [Guía del laboratorio](guia_del_laboratorio.md). Ahí están el visor de la hitbox de agarre, los gestos de cámara y los dos encuadres de miniaturas con giro por eje. Usá este prompt como antecedente de diseño.

Necesito que implementes una herramienta visual dentro del editor de Godot para crear y configurar los objetos del inventario y los contenedores compartidos del laboratorio `net-lab`, sin tener que armar a mano recursos, entradas del catálogo y nodos de aparición.

Ya existe una primera versión: el panel **Objetos**, en `addons/inventario_objetos/`. Revisalo y amplialo. No crees un segundo editor paralelo ni rehagas el inventario. El resultado debe servir para crear contenido compatible con el sistema actual y probarlo jugando solo y en cooperativo.

## 1. Contexto que tenés que revisar

Repositorio: `C:\Users\ElCaido97\Documents\tun-tun-tun-sahur`.

Leé las instrucciones aplicables del repositorio y estos documentos:

- `docs/net/guia_del_laboratorio.md`, especialmente las secciones 1 y 14.
- `docs/net/inventario_de_grilla.md`, especialmente arquitectura, creación de objetos, contenedores y límites.
- `docs/net/prompt_claude_inventario_grilla.md`, como antecedente del diseño; las decisiones posteriores y el código vigente tienen prioridad.
- `docs/net/arquitectura_coop_y_esqueleto_de_red.md`, solo en los apartados necesarios para resolver dudas. Es un historial extenso, con código y decisiones antiguas: no lo trates entero como especificación vigente.

Inspeccioná al menos:

- `addons/inventario_objetos/plugin.gd` y `objetos_panel.gd`.
- `scripts/inventory/inv_item_def.gd`, `inv_catalog.gd`, `inv_ability.gd`, `inv_consumable.gd` e `inv_equippable.gd`.
- `scripts/inventory/inv_pickup_spawn.gd`, `inv_container.gd` e `inv_inventory.gd`.
- `scripts/inventory/inv_visuals.gd`, `inv_thumbnails.gd`, `inv_loadout.gd` y las partes pertinentes de `inv_net.gd` y `sim_fingerprint.gd`.
- `scenes/inventory/caja.tscn`.
- `scenes/net_lab/inventario/catalogo_de_prueba.tres`, `zona_de_inventario.tscn` y las pruebas existentes.

Verificá la versión real de Godot y la API de plugins disponible en este proyecto. No asumas la versión del juego anterior.

Antes de modificar, revisá `git status`: hay trabajo local que puede no estar commiteado. Conservá los cambios ajenos, incluso los del plugin que vas a ampliar. No hagas reset, limpieza, checkout de archivos ni commits automáticos.

Explicá brevemente qué encontraste, cómo vas a ampliar el panel y qué archivos existentes necesitás tocar. Después implementá por etapas. Resolvé las decisiones rutinarias sin pedirme confirmación por cada paso. Si una función pedida requiere un cambio importante fuera del alcance, explicá el límite y continuá con el resto.

## 2. Alcance y contratos que se conservan

La herramienta crea **ítems del inventario y contenedores fijos del mundo**. No incluye puertas, interruptores, terminales, sistemas de armas, daño, hambre, crafting ni contenedores transportables con inventarios anidados.

Es una herramienta de autoría en el editor, no un menú de administración durante la partida. Lo que guarda deben ser recursos y escenas normales del proyecto; el juego exportado no debe depender del plugin.

Respetá estos contratos:

- `InvItemDef` define un tipo compartido. `InvStack` representa una instancia o pila. La posición y el giro pertenecen a la grilla. No guardes cantidades ni estado individual en la definición compartida durante el juego.
- `InvCatalog` registra los tipos conocidos. Un recurso fuera del catálogo no alcanza para que exista en la red.
- `InvPickupSpawn` describe una aparición inicial; el host crea la instancia autoritativa. No inventes identificadores de instancias desde el editor.
- `InvContainer` tiene su propio `InvInventory`. Un contenedor fijo no es un `InvItemDef` ni necesita entrar al catálogo de ítems.
- El host sigue validando recogidas, uso, equipo y transferencias. Los inventarios de jugadores siguen separados y los contenedores siguen compartidos.
- La barra rápida referencia objetos que permanecen en la grilla.
- No agregues Autoloads, singletons, inventarios globales ni otra conexión de red.
- No conectes nada al inventario viejo, PlayerV2 ni sistemas legacy. No modifiques el movimiento, el parkour, la escena principal o los presets de exportación para resolver la herramienta.

Avisá antes de modificar `.tres`, escenas o assets existentes, indicando cuáles y para qué. Los ajustes de recursos y escenas del laboratorio necesarios para esta tarea están dentro del alcance. No alteres modelos fuente, importaciones, texturas o materiales compartidos para acomodar una vista previa.

## 3. Flujo de uso

Conservá una entrada clara en el editor, aprovechando la pestaña **Objetos**. Puede abrir un editor más amplio si el dock queda chico.

Quiero poder:

1. Elegir **Ítem de inventario** o **Contenedor del mundo**.
2. Crear uno nuevo, abrir uno existente para editarlo o duplicarlo como punto de partida.
3. Configurarlo con controles visuales agrupados y ayudas breves en español.
4. Ver una vista previa antes de guardar.
5. Guardar y, por separado, colocar una o varias instancias en la zona del laboratorio.
6. Seleccionar lo colocado para moverlo con las herramientas normales de Godot.

Separá **Guardar definición/escena** de **Colocar en el nivel**. Guardar un tipo no debe sembrar objetos en el mapa. Podés ofrecer también una acción explícita de guardar y colocar, si ambos pasos están claros.

El catálogo y la zona actuales son los destinos iniciales. Centralizá sus referencias para que no queden rutas duplicadas en todos los controles. No prometas integración automática con cualquier nivel: la red actualmente descubre los objetos bajo su `world_root`. Si permitís elegir otro destino, validá ese contrato o explicá qué integración le falta, sin reconfigurar otros sistemas silenciosamente.

## 4. Editor de ítems

Exponé en el panel los datos que hoy obligan a ir al Inspector:

### Identidad y grilla

- Nombre visible y descripción multilínea.
- ID estable, generado inicialmente a partir del nombre, con posibilidad de ajustarlo antes de crear.
- Ruta de guardado visible, dentro de la carpeta de contenido del laboratorio por defecto.
- Ancho y alto en celdas, y si permite los cuatro giros existentes.
- Si se apila y límite de unidades. Si no se apila, el límite efectivo es 1.

Renombrar un objeto existente no debe cambiar automáticamente su ID ni la ruta del recurso. Bloqueá la modificación casual del ID ya registrado: cambiarlo exigiría migrar referencias, y esa migración no es parte de esta tarea.

No confundas el tamaño del ítem con el tamaño actual de la mochila. Un objeto demasiado grande para la grilla del jugador puede ser válido para un contenedor; mostrá la advertencia correspondiente sin imponer 12 × 16 como límite universal.

### Apariencia y miniatura

- Modelo `PackedScene` compatible, por ejemplo `.glb` o `.tscn`.
- Alternativa mediante una malla o una forma simple de prueba, y color de respaldo.
- Tamaño en el mundo, en metros.
- Rotación, zoom y alineación automática de la miniatura.

Explicá la prioridad de modelo, malla y representación de respaldo según el código actual. No dejes al usuario configurar dos fuentes sin saber cuál se usa.

Los modelos son referencias: no copies ni modifiques los originales. Para los ítems, mantené la política actual de extraer su presentación visual sin activar la lógica, las colisiones o los efectos de la escena importada.

### Capacidades

Permití configurar las capacidades que realmente existen:

- Sin capacidad: se recoge, guarda, transfiere y suelta.
- Consumible: `InvConsumable`, con `vitality_gain`. Etiquetalo como **vitalidad de prueba**; no presentes esto como salud, comida o un efecto de medicamento real.
- Equipable: `InvEquippable`, con `hold_offset`, `hold_rotation` y `hold_size`. Llevarlo en la mano no implementa disparos, ataques ni iluminación de una linterna.

La definición ya usa una lista de capacidades. Conservá las capacidades existentes al editar. Si permitís combinar las soportadas, hacelo mediante una lista ordenable, sin duplicados ambiguos del mismo tipo, y mostrá que la primera determina la acción de la barra rápida. No reemplaces la lista por un enum que pierda información al guardar.

Si aparece una capacidad que el formulario no sabe editar, preservala y ofrecé acceso al Inspector; no la elimines ni la conviertas silenciosamente.

### Estado inicial

Permití editar `default_state` con claves y valores de los tipos de datos que admite el sistema. Podés usar un editor sencillo de pares y una vista avanzada validada. Rechazá nodos, recursos y datos no serializables; no evalúes código escrito en un campo.

Mostrá un ejemplo como `carga: 100` y explicá que dos pilas solo se juntan si tienen el mismo tipo y estado. Ese dato por sí solo no implementa consumo de batería ni nuevas mecánicas.

## 5. Editor de contenedores

Creá escenas reutilizables compatibles con `scenes/inventory/caja.tscn`, conservando la composición `InvContainer` más su referencia válida al hijo `InvInventory`.

El formulario debe permitir:

- Nombre visible y ruta de la escena nueva.
- Columnas y filas de su inventario, dentro de los límites soportados.
- Dimensiones físicas de la caja (`box_size`).
- Color y alcance de acceso (`access_range`).
- Vista previa de la caja y una representación de su grilla.

Para esta versión alcanza la caja de prueba configurable que ya existe. No hace falta ampliar el runtime para que los contenedores acepten modelos arbitrarios.

No agregues un formulario de contenido inicial si eso exige inventar un sistema de población que todavía no existe. La primera versión puede crear contenedores vacíos, que después se llenan jugando. Tampoco agregues cerraduras, animaciones, física de objetos arrojados o persistencia de partidas.

Al duplicar una escena, cada instancia debe tener su propio inventario de ejecución. No compartas un estado mutable entre dos cajas. Los identificadores de red siguen asignándose por el mecanismo actual; no son un campo editable del formulario.

## 6. Vista previa útil y acotada

Para ítems, mostrá:

- El objeto 3D con cámara y luces propias, o su representación de respaldo.
- La miniatura con la proporción de su huella en la grilla.
- La huella y el efecto de girarla 90 grados.

Reutilizá el criterio visual de `InvVisuals` e `InvThumbnails`. Si necesitás extraer un helper común, mantenelo pequeño y conservá el comportamiento del juego. No crees otro renderizador con reglas de encuadre incompatibles.

La vista previa trabaja con un borrador, se actualiza al cambiar los controles y no escribe recursos, escenas ni el catálogo. Tiene su propio mundo 3D y libera viewports, nodos y conexiones al cerrar o desactivar el plugin. No necesita renderizar permanentemente si no cambió nada.

Comprobá que cambiar de ítem invalide la imagen anterior. Manejá modelos vacíos o sin mallas con un mensaje y una forma de respaldo, sin bloquear el resto de la herramienta.

No ejecutes comportamientos de gameplay del modelo para mostrarlo. No conviertas todo `scripts/inventory/` a `@tool` por comodidad: usá la mínima separación necesaria entre el código del editor y el de ejecución.

## 7. Guardado, edición y duplicado

Al crear un ítem:

- Guardá un `.tres` externo de `InvItemDef`.
- Agregalo una sola vez al catálogo elegido, mediante una referencia al archivo externo.
- Actualizá FileSystem y la información del panel.

Al editar:

- Cargá una copia de trabajo con independencia de los subrecursos mutables que se van a editar.
- No cambies el original mientras se escribe en el formulario o se modifica la vista previa.
- Guardá conservando la identidad y las referencias del recurso existente.
- Preservá propiedades que el formulario no expone.
- Avisá si el recurso o la escena cambió externamente desde que lo abriste, para no pisar una edición más nueva.
- Si cambian dimensiones o capacidades, validá las consecuencias sobre los marcadores y referencias del destino conocido; no recortes cantidades ni borres datos en silencio.

Al duplicar, generá otra identidad y otro archivo. Las capacidades y los estados que se editen en la copia no deben modificar el original. Los modelos y otros assets de solo lectura pueden seguir compartidos.

Mostrá los cambios pendientes y ofrecé guardar, descartar o cancelar antes de cambiar de selección si se perdería trabajo.

No incluyas borrado masivo ni una migración general de IDs. Esas operaciones no hacen falta para cumplir esta tarea.

## 8. Colocación en el laboratorio

Para ítems, usá `InvPickupSpawn` con referencia al tipo, cantidad y un `state_override` opcional por aparición. La cantidad total se divide en pilas válidas antes de crear los marcadores: 12 unidades con límite 5 producen 5, 5 y 2. Con 0 unidades no se coloca nada.

Para contenedores, instanciá la escena guardada, con su inventario correctamente enlazado.

Conservá una forma cómoda de colocarlos en la zona de pruebas. Podés reutilizar y mejorar el buscador de posiciones libres del panel actual. No hagas crecer la tarea hacia un editor de niveles: alcanza colocar sin solapamientos evidentes y dejar los nodos seleccionados para moverlos.

Validá espacio y destino antes de modificar. Si no hay lugar para todas las pilas solicitadas, explicá cuántas entran y no hagas una colocación parcial silenciosa. Tené en cuenta las dimensiones de los contenedores nuevos y las transformaciones del destino.

Los nodos deben tener `owner` correcto y sobrevivir al guardar y reabrir la escena. La colocación usa el historial de deshacer y rehacer del editor.

No guardes automáticamente una escena que ya tenía modificaciones ajenas sin que el usuario haya elegido guardar. Indicá claramente cuándo los nodos quedaron agregados pero la escena sigue pendiente de guardado.

## 9. Validación y manejo de errores

Antes de escribir, validá:

- Nombre e ID no vacíos, ID válido y sin duplicados en el catálogo.
- Rutas válidas dentro de los destinos permitidos; sin sobrescribir otro archivo por una colisión de nombre.
- Dimensiones, límites de pila, cantidades, tamaños y alcances válidos.
- Estado inicial y sobrescrituras de estado compatibles con los tipos admitidos.
- Catálogo accesible, escena de destino correcta y referencias requeridas presentes.
- Coherencia de las capacidades y sus parámetros.

Validá también en la lógica que realiza la operación, no solo mediante los rangos de los controles.

Las operaciones de creación involucran varios archivos. Prepará y validá antes de escribir, comprobá cada resultado de guardado y restaurá los cambios de esa operación si falla un paso posterior. No dejes un recurso huérfano o un catálogo alterado después de informar que no se creó nada. Si un fallo impide recuperar todo, informá exactamente qué quedó guardado y qué requiere reparación.

Deshacer la colocación y deshacer una escritura en disco no son lo mismo. Definí y mostrá ese alcance: Ctrl+Z no debe sugerir que eliminó el `.tres` o desregistró el tipo si solo quitó los marcadores.

## 10. Compatibilidad del editor y del cooperativo

El panel anterior ya tuvo un fallo de layout: al ocultarlo, el texto se partía letra por letra y estiraba el editor hasta romper la proporción visible del viewport 3D. Conservá la corrección y verificá estos casos:

- Pestaña visible y oculta.
- Dock angosto y ventana chica.
- Texto largo, scroll y cambio entre formularios.
- Activar, desactivar y volver a activar el plugin, sin docks ni conexiones duplicadas.

En cooperativo, los recursos guardados por la herramienta deben recorrer el mismo camino que los creados a mano. No agregues RPC propios del creador ni mandes recursos o rutas arbitrarias desde el cliente.

Respetá la huella de compatibilidad. No la ignores ni la debilites para permitir conectarse con catálogos distintos. Revisá si algún dato funcional nuevo necesita incorporarse a ella. El plugin es del editor y no debe introducir por sí solo una dependencia de ejecución.

Explicá en la ayuda que, después de guardar contenido, ambas PC necesitan la misma versión del laboratorio o una nueva exportación compartida. No implementes distribución automática de assets.

## 11. Comprobación del resultado

Validá los casos que pueden provocar pérdida de datos, referencias rotas o diferencias entre edición y ejecución. Usá una copia o destinos temporales para las pruebas que escriban archivos; no llenes el catálogo real de recursos descartables.

Como mínimo, comprobá:

1. Ítem simple sin modelo: se guarda, se registra una sola vez, se coloca y puede recogerse.
2. Ítem apilable: 12 unidades con límite 5 generan 5, 5 y 2; se conserva el total.
3. Consumible con un valor distinto del predeterminado: el host aplica ese valor y consume la cantidad correcta.
4. Equipable con parámetros propios: se conserva la configuración y otro jugador lo ve equipado.
5. Edición y duplicado: se conservan ID y referencias al editar; cambiar capacidades o estado del duplicado no cambia el original; descartar no altera archivos.
6. Contenedor nuevo: se guarda, se reabre con las referencias correctas, dos jugadores pueden usarlo y dos contenedores no comparten su contenido.
7. Rechazos: ID repetido, entrada inválida y falta de lugar no generan escrituras parciales. Verificá también la recuperación ante un fallo de guardado mediante un mecanismo controlado que no dañe contenido real.
8. Colocación: deshacer y rehacer, guardar, cerrar y reabrir conservan lo esperado.
9. Vista previa y layout: revisá el editor con ventana, incluyendo panel oculto. Ejecutar sin pantalla no permite dar por verificado este punto.
10. Integración: ejecutá las pruebas existentes relevantes del inventario. Si tocaste datos que viajan por red o inicialización del mundo, ejecutá la prueba de pareja correspondiente y comprobá entrada tardía. Si no podés correr alguna, indicá cuál y por qué.

No modifiques pruebas para ocultar una regresión ni reemplaces un comportamiento real por un mock como única evidencia de que funciona. Informá por separado lo probado automáticamente, lo revisado visualmente y lo pendiente de probar con interacción manual o en dos PC.

## 12. Entrega

Implementá la herramienta y actualizá `docs/net/inventario_de_grilla.md` con:

- Cómo abrirla y crear un ítem o un contenedor.
- Cómo editar, duplicar, previsualizar y colocar.
- Qué archivos produce y cómo se guardan los cambios del nivel.
- Alcance de deshacer, validaciones y limitaciones reales.
- Cómo probar el contenido en solo y cooperativo.

Actualizá la sección 14 de `guia_del_laboratorio.md` con una referencia breve si cambió el flujo de uso. Evitá copiar toda la guía en varios lugares.

Al terminar, resumí qué implementaste, los archivos importantes modificados, las comprobaciones realizadas y los límites pendientes. El resultado tiene que permitir crear y probar contenido sin escribir GDScript ni editar a mano el catálogo; no alcanza con entregar una propuesta de arquitectura.
