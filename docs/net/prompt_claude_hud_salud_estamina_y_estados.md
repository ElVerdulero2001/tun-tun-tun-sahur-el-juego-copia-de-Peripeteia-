# Prompt para Claude: HUD, salud, estamina y estados activos

Necesito que implementes el HUD del laboratorio `net-lab` junto con las mecánicas mínimas que le dan funcionalidad: salud, consumibles que curan o dañan, estamina recuperable solo con consumibles y gasto por mantener estados activos. También hay que corregir la convivencia de la cámara lenta de varios jugadores.

El objetivo es poder crear objetos con el panel **Objetos**, recogerlos, usarlos y comprobar sus efectos jugando solo y en cooperativo. Implementá el trabajo: no te limites a proponer una arquitectura.

## 1. Contexto y revisión previa

Repositorio: `C:\Users\ElCaido97\Documents\tun-tun-tun-sahur`.

Antes de modificar:

- Leé las instrucciones aplicables del repositorio y revisá `git status`. Hay trabajo local, incluido el editor de objetos, que puede seguir cambiando. Conservá cambios ajenos y archivos no versionados. No hagas reset, limpieza, restauraciones ni commits automáticos por esta tarea.
- Leé `docs/net/guia_del_laboratorio.md` y `docs/net/inventario_de_grilla.md`. Usá `prompt_claude_creador_de_objetos.md` y `prompt_claude_inventario_grilla.md` como antecedentes; mandan las decisiones actuales y el código vigente.
- Consultá `arquitectura_coop_y_esqueleto_de_red.md` solamente para resolver dudas concretas: contiene un historial extenso, no una especificación íntegramente vigente.
- Verificá la versión real de Godot del laboratorio. No asumas la versión de los sistemas viejos del juego.
- Abrí y mirá la referencia visual: `C:\Users\ElCaido97\Documents\otro proyecto bobo\texuras\hud\hud 3.png`. Las correcciones escritas en este prompt tienen prioridad sobre los textos y fotos del concepto.

Inspeccioná las partes pertinentes de:

- `scenes/net_lab/net_lab.tscn`, `net_lab.gd` y su cámara.
- `scripts/actor/actor_state.gd`, `actor_input.gd`, `actor_motor.gd` y `actor_tuning.gd`.
- `scripts/net/sim_clock.gd`, `net_sync.gd`, `sim_fingerprint.gd` y el camino real de predicción, adopción y reconciliación.
- `scripts/inventory/inv_ability.gd`, `inv_consumable.gd`, `inv_loadout.gd`, `inv_inventory.gd`, `inv_authority.gd`, `inv_protocol.gd`, `inv_net.gd`, `inv_replica.gd` e `inv_ui.gd`.
- El panel actual en `addons/inventario_objetos/`, sus pruebas y los recursos de la zona de inventario.

Explicá brevemente qué encontraste, dónde va a vivir cada estado y qué archivos necesitás tocar. Avisá antes de modificar recursos `.tres`, escenas o assets existentes, indicando cuáles y para qué. Si hay que cerrar Godot para modificar el nivel o `project.godot`, avisalo antes y seguí las reglas de la guía. Los ajustes necesarios dentro del laboratorio y del panel están autorizados; resolvé las decisiones rutinarias sin pedir aprobación por cada archivo.

## 2. Alcance

Trabajá en el laboratorio nuevo y sus componentes reutilizables. Conservá inventarios separados por jugador, contenedores compartidos y host autoritativo. No conectes esto con PlayerV2, el inventario viejo ni sistemas legacy.

Esta etapa incluye:

- HUD funcional según el concepto corregido.
- Salud por jugador y muerte de prueba.
- Estamina por jugador, sin regeneración automática.
- Objetos del inventario que curen, dañen o recuperen estamina al usarse.
- Integración de los estados ya implementados: súper velocidad/salto y cámara lenta.
- Activación simultánea de varios estados, costos sumados y apagado por agotamiento.
- Corrección de cámara lenta compartida con activación independiente por jugador.
- Campos utilizables en el editor de objetos y contenido mínimo para probarlos.

La invisibilidad y otros poderes son ejemplos de estados futuros. Dejá una extensión razonable para agregarlos sin implementar ahora poderes nuevos. Los efectos temporales de consumibles propuestos en la conversación inicial tampoco son un requisito de esta etapa.

Los elementos del escenario que dañan quedan para después. La integridad corporal por partes y la medición real de oscuridad también. No agregues combate, enemigos, hambre, daño de caída, ragdolls, persistencia ni un sistema completo de reaparición.

## 3. Diseño del HUD

### Salud

- Instrumento circular con aguja y escala de **0 a 10**.
- **10 = salud completa; 0 = muerto.** La aguja debe representar también valores intermedios, no solamente diez escalones enteros.
- El RPM es una referencia de forma: el instrumento muestra salud. Eliminá las inscripciones de RPM y marcas comerciales de la presentación final.
- Conservá marcas principales numeradas y subdivisiones menores sin números.
- La escala se orienta hacia arriba, siguiendo la orientación del velocímetro de la referencia. No copies la disposición inclinada hacia la izquierda del RPM original. Los números deben leerse derechos.
- La luz naranja va integrada en la **parte inferior** del instrumento de salud, reemplazando la zona rectangular donde aparece el texto de RPM. Ya no cuelga por fuera del círculo.
- Esa luz queda apagada y reservada para la futura integridad corporal; no la hagas parpadear por salud baja ni inventes una mecánica sustituta.

### Estamina

- Segundo instrumento circular con aguja, orientado hacia arriba como el velocímetro del concepto.
- Escala de **0 a 200**: cero es reserva vacía; doscientos es reserva completa.
- Muestra estamina, sin inscripciones de km/h u odómetros decorativos que aparenten otra información.

### Termómetro

- Conservá la forma vertical y escala de **0 a 100** del concepto.
- En esta etapa marca **100 de forma constante**. No calcules iluminación ni presentes esto como un sensor de sigilo ya implementado.

### Luces de estados

- Arriba de la pantalla aparecen luces con un icono que identifica cada estado activado por el jugador local.
- Son luces indicadoras, no botones ni un selector de habilidades. No agregues un selector nuevo en esta etapa.
- Mostrá solamente las correspondientes a estados propios activos, sin el panel de fondo ni los botones fotográficos del concepto. Si no hay ninguno, esa zona no aparece.
- Pueden verse varias simultáneamente. Las cuatro luces de la imagen no establecen un límite de cuatro estados.
- Si otro jugador activa cámara lenta, su efecto alcanza al jugador local, pero la luz local de cámara lenta queda apagada mientras el jugador local no la haya activado por su cuenta.

### Presentación y convivencia con el laboratorio

Tomá de la referencia la composición: instrumentos abajo a la izquierda y luces arriba. Construí instrumentos limpios y legibles, conservando la intención industrial. El montaje de fotos y textos explicativos no es una textura lista para usar como HUD.

Usá controles, dibujo vectorial/procedural o assets propios del laboratorio según convenga. No modifiques los archivos fuente de la referencia ni modelos, texturas o materiales compartidos del juego para resolver el HUD. No hace falta reproducir marcas comerciales.

La aguja puede tener una interpolación visual breve, pero nunca debe modificar el valor real ni ocultar un agotamiento. Al llegar a cero de estamina, la representación debe terminar en cero. La muerte requiere un aviso explícito aunque la salud se restaure enseguida.

El HUD pertenece al jugador local y no captura sus controles. Debe convivir con la barra rápida, el inventario y los avisos del laboratorio. Conservá la posibilidad de caminar con el inventario abierto. Revisá al menos 1280 × 720 y 1600 × 900, sin instrumentos cortados ni superposiciones que impidan usar la grilla.

## 4. Salud y muerte de prueba

Cada jugador tiene su propia salud. Usá una unidad interna coherente y documentada; el instrumento siempre representa la proporción de salud en la escala 0–10. Salud y estamina empiezan completas para esta primera prueba.

Los consumibles pueden aumentar o disminuir la salud del usuario. El resultado se limita entre cero y su máximo; un daño superior a lo restante alcanza para matar. No agregues regeneración automática de salud.

Cuando el host confirma salud en cero:

1. Registrá una muerte de prueba del jugador afectado.
2. Desactivá todos sus estados activos, con las consecuencias correspondientes para el movimiento y la cámara lenta compartida.
3. Mostrá a ese jugador un mensaje claro, por ejemplo **“Moriste”**.
4. Restaurá su salud al máximo para continuar probando.

Conservá posición, inventario y estamina restante. Se gasta normalmente el objeto cuyo uso causó la muerte; restaurar salud no devuelve consumibles. Los estados no se reactivan solos después.

Es un ciclo de prueba, sin cambio de escena, teleport, pantalla bloqueante ni pausa global. Elegí una duración breve y configurable del aviso. Evitá que el reinicio inmediato de salud borre el evento antes de que el cliente pueda mostrarlo: una instantánea final con salud completa no alcanza para comunicar una muerte.

## 5. Estamina y estados activos

Reglas decididas:

- Reserva máxima **200**.
- **No se regenera automáticamente:** solo se recupera usando consumibles.
- Correr y saltar no consumen estamina. No agregues gasto a trepadas, agarres u otras acciones de parkour.
- Mantener activos estados como el súper o la cámara lenta consume estamina progresivamente.
- Cada estado tiene un costo por segundo configurable. Con varios activos, los costos se suman. Ejemplo ilustrativo, no balance definitivo: costos 5 y 8 producen un gasto de 13 por segundo.
- Un jugador paga solo sus propias activaciones. Recibir el efecto global de otro no consume su estamina.
- Al llegar a cero, **todos los estados propios se apagan juntos**. No los desactives uno por uno por falta de reserva.
- Ese agotamiento produce **un sonido leve de desactivación**, una sola vez para el jugador afectado. No uno por estado, por paquete, por fotograma o por reconciliación. El sonido debe existir en el proyecto y ser configurable; puede ser un tono sencillo si no hay un asset apropiado.
- Con cero no se pueden activar estados. Después de recuperar reserva con un consumible se pueden activar manualmente, sin exigir llenarla ni agregar una espera arbitraria. Los estados apagados no se reactivan solos al recuperar reserva.

Conservá los controles existentes: teclado numérico 1 para cámara lenta y 2 para el súper, según el Input Map vigente. La fila superior 1–0 sigue siendo la barra rápida. Preservá el comportamiento actual del súper mientras esté activo.

Documentá con precisión qué reloj usa el costo por segundo y su comportamiento durante la cámara lenta. Elegí una base temporal coherente con la simulación existente, sin depender del FPS ni mezclar inadvertidamente segundos reales, ticks y tiempo del mundo. No presentes esa elección técnica como una decisión previa del usuario.

Los costos y parámetros de prueba deben poder ajustarse en recursos o en los componentes del laboratorio, siguiendo el criterio de Tuning. Validá valores finitos y rangos, sin introducir costos negativos que regeneren reserva.

## 6. Cámara lenta compartida: corregir acumulación y propiedad

El usuario observó que al activarla dos jugadores puede producirse una cámara todavía más lenta. Reproducí y localizá el problema en el código vigente; no des por probado un mecanismo concreto solo por la descripción.

Además, el código revisado tiene un toggle sobre tramos globales en `_request_world_slow`, no una propiedad independiente por jugador. No alcanza con agregar un contador de estamina alrededor de ese toggle.

El contrato final es:

- Cada jugador puede tener su solicitud de cámara lenta activa o inactiva de forma independiente.
- La cámara lenta del mundo está activa mientras **al menos un jugador** la sostenga.
- La intensidad global es **una sola**, igual con uno, dos o más activadores. No se suman ni multiplican intensidades y no se descuenta dos veces el mismo intervalo al calcular el tiempo del mundo.
- Quien la tiene activada paga su costo, aunque otro también la sostenga. Quien la apaga deja de pagar.
- Si un jugador la apaga, agota su estamina, muere o abandona definitivamente la partida, se retira su activación. La cámara lenta continúa si queda otro activador y termina si no queda ninguno.
- El aviso de muerte o la estamina cero de un jugador no pueden apagar el súper ni las solicitudes de cámara lenta de otro.

Ejemplo que tiene que funcionar:

1. A la activa: mundo lento; solo A gasta por cámara lenta.
2. B la activa también: misma intensidad; A y B gastan cada uno por su activación.
3. A la desactiva: el mundo sigue lento; A deja de gastar por ese estado y B continúa.
4. B la desactiva o se queda sin estamina: termina la cámara lenta si no hay nadie más sosteniéndola.

Que un jugador se beneficie sin pagar mientras otro la sostiene es una consecuencia aceptada. No inventes cobros a espectadores, penalizaciones, reparto de costos ni reglas para impedirlo.

Conservá la programación y comunicación por ticks que necesita el laboratorio. Revisá cambios pendientes, solicitudes simultáneas, mensajes repetidos y entradas tardías para que no queden tramos superpuestos, un fin antiguo cancelando una activación nueva o efectos globales huérfanos. No simplifiques esto aplicando `Engine.time_scale` arbitrariamente desde cada cliente.

## 7. Consumibles y editor de objetos

Ampliá el mecanismo existente de capacidades de los objetos y el mismo panel **Objetos**. Quiero poder configurar y probar:

- Un objeto que cure una cantidad ajustable.
- Un objeto que recupere una cantidad ajustable de estamina.
- Un objeto que haga una cantidad ajustable de daño al usuario al consumirlo, incluso suficiente para provocar la muerte de prueba.

Una aplicación aceptada consume una unidad. La curación o recuperación se limita al máximo, sin rebalsar. Un objeto que solo cura, con salud completa, no se gasta; lo mismo para uno que solo recupera estamina con reserva completa. El objeto dañino sí se puede usar con salud completa y no debe quedar bloqueado por la comprobación antigua de vitalidad máxima.

No es obligatorio implementar combinaciones de múltiples efectos nuevos para cumplir esta etapa. Si el modelo permite combinarlas, validá y aplicá el uso como una operación atómica y documentá su orden; no consumas la unidad dejando un efecto a medio aplicar. Conservá las capacidades que ya existen y el orden de acciones de la barra rápida.

El formulario debe dejar claro el efecto y la cantidad, con nombres y ayudas en español. Los textos del menú y de inspección deben describir lo que realmente hace el objeto. Una clave libre en `default_state` no implementa un efecto: estos comportamientos necesitan soporte real del runtime y controles del editor.

Hoy `InvConsumable` modifica `InvLoadout.test_vitality`, un contador de prueba. Integrá o migrá ese comportamiento hacia la salud nueva de forma explícita. No dejes dos cifras independientes que aparenten ser la salud. Conservá IDs, referencias, modelos, cantidades y demás propiedades ajenas al efecto de los objetos existentes, y actualizá los tests que dependían de la vitalidad de prueba.

Creá contenido mínimo de prueba que se pueda abrir, editar, duplicar y colocar desde el panel. Puede usar formas simples. No hace falta agregar elementos dañinos al escenario ni objetos que otorguen nuevos poderes.

## 8. Arquitectura y red

La salud, la estamina y los estados pertenecen a cada personaje; el inventario permite aplicar efectos sobre ellos, y el HUD presenta lo confirmado o predicho según el contrato vigente. Evitá que los widgets se conviertan en la autoridad de gameplay o que el actor necesite tener una interfaz abierta para funcionar.

- No agregues Autoloads, singletons, conexiones de red alternativas ni inventarios globales.
- Usá componentes y referencias explícitas. Mantené pequeño cualquier contrato entre inventario y estado del actor.
- El host valida posesión, capacidad, cantidad y condiciones del uso; aplica efecto y consumo una sola vez. Preservá revisión de instancias y deduplicación de pedidos.
- El host también valida activación, consumo continuo, agotamiento, muerte y restauración de salud. El cliente no puede imponer saldo, curación o activaciones gratuitas mediante sus datos.
- Todo estado que influya en el movimiento futuro debe integrarse con el contrato de `ActorState`, predicción, adopción, serialización y repetición de ticks. No guardes el agotamiento del súper en un timer local que sobreviva fuera de una restauración.
- La simulación de ticks repetidos no puede volver a consumir un objeto ni reproducir sonidos o avisos de muerte. Separá estado e identificación de eventos de su presentación local.
- Coordiná el efecto del consumible con el inventario y los estados para que un resultado aceptado no pueda aplicarse dos veces por reenvío o reconexión. El gasto por tick tampoco puede cobrarse otra vez al reconciliar.
- Conservá funcionamiento solo, host jugador y clientes por el camino normal. Las instantáneas de entrada tardía deben incluir el estado actual necesario, sin reproducir avisos o sonidos históricos.
- Definí coherentemente qué ocurre durante un corte temporal, respetando la política actual de reconexión, y retirando las activaciones al abandonar definitivamente.
- Extendé el fingerprint y las validaciones del protocolo en lo necesario: clientes con costos, límites, capacidades o esquemas incompatibles no deben entrar como si fueran iguales.

No rehagas todo el sistema de red para este trabajo. Si necesitás extraer del laboratorio una pieza de estados o de cámara lenta, que sea una separación acotada al comportamiento requerido.

## 9. Pruebas y criterios de aceptación

Probá por etapas con verificaciones útiles, aprovechando las pruebas existentes. Diferenciá lo leído en código, lo ejecutado y lo que todavía requiere prueba manual en las dos PC. No afirmes que el problema reportado de cámara lenta quedó reproducido si solo verificaste el comportamiento nuevo.

Como mínimo:

1. Salud y reserva empiezan completas. Las agujas muestran 10 y 200; el termómetro, 100; no hay luces de estados activos.
2. Correr y saltar sin estados activos no reducen estamina. Esperar con reserva parcial tampoco la aumenta.
3. Consumibles de cura, reserva y daño funcionan desde el menú y la barra rápida. Se consume exactamente una unidad por uso aceptado; los rechazos no gastan nada.
4. Curación y reserva se limitan a su máximo. Probar salud parcial y objetos dañinos con salud completa.
5. Un consumible letal produce un aviso visible, apaga estados, restaura salud y conserva posición, inventario restante y estamina. Un mensaje repetido no vuelve a matar ni consume otra unidad.
6. El súper y la cámara lenta pueden estar activos juntos. Su gasto combinado corresponde a la suma de costos; apagar uno retira solo su costo.
7. El agotamiento simultáneamente apaga todos los estados propios y produce un solo sonido. No hay saldo negativo, reactivación automática ni activación aceptada con reserva cero.
8. Recuperar estamina con un consumible permite volver a activar estados manualmente.
9. Con dos jugadores, ejecutar el ejemplo de la sección 6, en ambos órdenes y con activaciones simultáneas. Verificar una sola intensidad y que el cálculo del tiempo del mundo tampoco acumule ralentización.
10. Con A y B sosteniendo cámara lenta, agotar o matar solo a A: B la mantiene y sigue pagando; A deja de pagar y sus luces se apagan. Al terminar B, el mundo recupera su escala normal.
11. Un jugador sin activación propia recibe la cámara lenta ajena sin luz propia ni gasto. Si tiene el súper activo, paga solamente por su súper.
12. Repetir casos de red con latencia, pérdida, pedidos duplicados, entrada tardía y desconexión. Comprobar ausencia de gastos dobles y cámara lenta huérfana.
13. Crear o editar los tres tipos de consumibles desde el panel, guardarlos, colocarlos y usarlos en el laboratorio. Las pruebas del editor que escriban fixtures deben usar una copia del proyecto.
14. Revisar capturas reales del HUD en las dos resoluciones indicadas, con inventario cerrado y abierto, valores parciales y varios estados activos. Las capturas internas de QA no son nuevos entregables.

Corré las pruebas existentes pertinentes de inventario, editor y movimiento. Si cambia serialización o predicción del actor, incluí las de repetición y parkour afectadas. Explicá cualquier cambio legítimo de huella; no actualices resultados esperados solo para ocultar divergencias.

## 10. Entrega y documentación

Implementá por etapas: estado y reglas, consumibles/editor, cámara lenta compartida, presentación y verificación, ajustando el orden cuando haya dependencias técnicas.

Al terminar:

- Actualizá las guías de `docs/net` con arquitectura final, archivos, controles, parámetros ajustables, creación de objetos y recorrido de prueba.
- Separá decisiones explícitas del usuario de elecciones técnicas o valores iniciales de balance.
- Explicá brevemente qué cambió y cómo se usa, con nombres exactos de botones e instrucciones en español para el editor en inglés.
- Informá las pruebas realizadas y sus resultados reales, los límites pendientes y lo que falta probar a mano en las dos PC.
- No subas cambios a GitHub ni hagas modificaciones ajenas a esta tarea.

El resultado tiene que permitir experimentar con el panel de objetos y ver efectos reales en el personaje y en el HUD, sin convertir esta etapa en una implementación de todos los sistemas futuros del juego.
