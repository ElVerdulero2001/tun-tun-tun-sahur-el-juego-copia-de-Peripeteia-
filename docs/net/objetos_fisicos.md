# Objetos sueltos con física

Hecho el 2026-11-14 a partir de [`prompt_claude_objetos_dinamicos.md`](prompt_claude_objetos_dinamicos.md) y revisado el 2026-11-15 a partir de [`prompt_claude_revision_objetos_fisicos.md`](prompt_claude_revision_objetos_fisicos.md), después de tu prueba en las dos notebooks (los problemas y su análisis: [`problemas_objetos_fisicos_2026-11-14.md`](problemas_objetos_fisicos_2026-11-14.md)).

Los objetos sueltos del inventario caen, chocan con el nivel y entre sí, reposan y se pueden **sostener** en el mundo: acercar, alejar, girar, soltar y lanzar. Sostener no es guardar: el objeto sigue en el mundo y no entra al inventario. Para guardarlo, **E**, como siempre.

**Corrección posterior del temblor del invitado (2026-11-15):** [causas, implementación y regresiones](correccion_temblor_objetos_guest_2026-11-15.md). Actualiza el ciclo de corrección/adopción, el suavizado visual contra el nivel y el presupuesto de los paquetes de inputs (secciones 9 y 12). Sigue pendiente repetir el gesto del video en las dos máquinas físicas.

**Estado:** la primera versión está en el commit local `677086f` (la probaste en las dos PC). **La revisión del 2026-11-15 no tiene commit** (el pedido decía no commitear ni subir por iniciativa propia). **La probaste en las dos notebooks** esa tarde: las dos mallas, la de agarre y la física, andan como deben. Encontraste 4 errores y 7 avisos del depurador, y están arreglados (sección 17). **En tu segunda prueba** (el mismo día, `kavi.txt` nuevo y un video), ya nada atravesaba el piso ni quedaba trabado, y quedaban tres problemas: «no se ve» tardaba, lo soltado del inventario salía hacia donde mira el cuerpo y no la cámara, y el invitado veía la torre con retraso. Están arreglados (sección 18). **Falta probar** esos arreglos con el mouse y en las dos PC: la lista está en la sección 1. **La huella cambió:** en la notebook, `actualizar_lab.bat`.

**Lo que cambió el 2026-11-15**, en una línea cada uno:

- **El cuerpo físico** lo arma Godot (una forma convexa, varias o una primitiva) al preparar el objeto en el editor, y queda guardado en el `.tres`. Se acabó el generador propio de tajadas, que dejaba rendijas de 20 cm en la tabla (sección 7).
- **La hitbox de agarre** es la selección principal: si el tipo tiene una, se apunta y se agarra con ella, también por un hueco del modelo. Hay una regla de acceso para que no deje agarrar lo de atrás de una pared (sección 8).
- **Lo que sostenés en la notebook** se predice ahí mismo, con las mismas cuentas que el host. El host adopta lo que es creíble y corrige lo que no. Medido: girando a 360 °/s, tu PC va 13° atrás y queda quieta en 117 ms; antes, 30° y 350 ms (sección 9).
- **Sacar un apoyo despierta lo de arriba:** una pila cae entera al recoger el de abajo (sección 10).
- **Después de tu prueba en las notebooks** (la tarde del 2026-11-15, sección 17):
  - nada queda metido en el piso, ni debajo de una pila apretada;
  - lo que igual queda metido se agarra y se saca;
  - lo soltado en la notebook ya no se hunde;
  - lo sostenido que una pared tapa se suelta solo («no se ve»).
- **Después de tu segunda prueba** (sección 18):
  - «no se ve» suelta en el acto, y lo decide la máquina del que sostiene, sin esperar al host;
  - lo soltado del inventario sale hacia donde mira la cámara;
  - en la máquina del invitado, lo de abajo de una torre desaparece junto con la caída de lo de arriba.

---

## 0. Quién decidió qué

**Vos**, antes o durante el trabajo:

- Los objetos **no chocan con los personajes** (tus notas del 2026-10-31 y tu respuesta del 2026-11-14): se los atraviesa caminando y no se puede parar uno encima. Así el personaje, que tu PC adelanta, no se traba con algo que simula solo el host.
- Al lanzar, **todos salen con la misma fuerza** (tus notas del 2026-10-31).
- Lo sostenido **gira con vos**: si girás la cámara, el objeto gira con tu vista y conserva cómo lo tenías (respuesta del 2026-11-14).
- El panel **Opciones** se abre con **F3** y con un botón del menú del laboratorio (respuesta del 2026-11-14).
- **El 2026-11-15** (`prompt_claude_revision_objetos_fisicos.md`):
  - el cuerpo físico, con las herramientas de colisión de Godot, preparado en el editor y guardado;
  - la hitbox de agarre, independiente del cuerpo: si existe una que sirve, es la selección principal (no una segunda oportunidad, la «H2» del informe). Se agarra por el punto tocado aunque caiga en un hueco (anclaje virtual), y una hitbox que asoma de una pared no habilita lo de atrás;
  - lo sostenido, con predicción en tu PC y control del host, con una adopción acotada como la del personaje;
  - despertar a los vecinos al sacar un objeto del mundo;
  - dos apartados separados en el panel: **Cuerpo físico** e **Hitbox de agarre**.
- **La tarde del 2026-11-15,** después de tu prueba en las notebooks: lo sostenido que una pared tapa **se suelta solo**. Elegiste la opción que te recomendé y pediste el mecanismo por escrito: está en la sección 17.
- **En tu segunda prueba** (sección 18):
  - que «no se ve» no fuera instantáneo y dependiera del host lo marcaste como problema;
  - que lo soltado salía hacia donde mira la cápsula y no la cámara, también. Que el cuerpo gire hacia donde caminás es tuyo, del 2026-10-10, y sigue igual;
  - **la torre que desarma el invitado:** elegiste la opción que te recomendé. Si algo se apoya en lo que recogés con **E**, en tu máquina desaparece junto con la caída de lo de arriba; si no, en el acto, como antes.

**El pedido** (`prompt_claude_objetos_dinamicos.md`): los dos esquemas de botones y los dos modos de sostener, independientes; de fábrica, botones principales y alternar; la rueda para arriba aleja y para abajo acerca; el botón central mantenido gira y Shift da el tercer eje; la rueda no hace zoom mientras sostenés; prioridad interfaz → mano → cámara; el host manda.

**Claude:**

- **El 2026-11-14:** todos los números del Tuning (sección 4), dónde se guardan las preferencias, el índice de 1 m, 30 paquetes de poses por segundo, el segundo de historia del host, el cuarto de segundo para volver a lo del host al soltar, las capas y lo que pasa con lo que se cae del mapa.
- **El 2026-11-15:**
  - **Los cuerpos:** qué cuerpo le toca a cada objeto existente (sección 7, «Qué tiene cada objeto»), los valores de fábrica de la descomposición (concavidad 0,01 y resolución 100000) y que lo fino (menos de 2,5 cm) vaya con una caja.
  - **La hitbox:** la tolerancia del acceso (25 cm más allá del alcance).
  - **La adopción:** sus tolerancias (sección 9) y que soltar espere al último tick en que sostenías.
  - **Los choques de la mano:** que el host y tu PC miren el nivel antes de cada paso.
  - **El rescate** de lo que Jolt duerme metido en el nivel.
  - **La tarde del 2026-11-15** (sección 17):
    - bajar la tolerancia de penetración de Jolt a 2 mm en `project.godot`;
    - que lo metido pueda salir o arrastrarse sin meterse más;
    - que lo soltado en tu PC caiga con el mismo paso que la mano;
    - de «no se ve»: qué punto se mira, el margen de 1 cm y usar el mismo tiempo que «se trabó».
  - **Después de tu segunda prueba** (sección 18):
    - que «no se ve» lo decida la máquina del que sostiene, con **Hold Hidden Time** en 0 (en el primer tick tapado), y que el host igual lo suelte a los **Hold Break Time** si esa máquina no lo hizo;
    - que lo soltado del inventario use el yaw de la cámara del último input, el mismo que tiene el host;
    - que el invitado deje de dibujar lo que sacó el host en el tick en que salió, y que lo que se apoya o toca a lo que recogés sea lo mismo que despierta el host;
    - dos arreglos que encontré en el camino: lo que se despierta ya no se mueve antes de tiempo en el invitado, y el host respeta el giro con que tu máquina muestra lo que soltás.

  Todo se puede cambiar.

---

## 1. Cómo probarlo

### Dónde

La **Pista de física** está pegada a la zona de inventario, unos 12 m hacia el lado del cartel grande **PISTA DE FÍSICA** (se ve desde la zona). Tiene:

| Qué | Para qué |
| --- | --- |
| **Tabla larga** (1,6 m) derecha, y otra **cruzada** (su marcador está girado 90°) | Agarrarla por una punta, girarla y meterla a lo largo por la ranura. La cruzada muestra que un marcador girado deja el objeto girado |
| **Muro con ranura** (la ranura, 25 × 25 cm, entre 1,13 y 1,38 m del piso) | Meter la tabla a lo largo; cruzada, el muro la frena |
| **Pared fina** (2 cm de grosor, 2,5 m de alto y 4 m de largo) y una **granada** delante | Lanzar contra ella: rebota, no pasa. Empujar y girar algo contra ella: no la cruza |
| **Mesa** (1 m de alto) con tornillos, una llave y una granada en el borde | Caer de un borde; choque entre objetos |
| **Estante** (a 1,5 m) con una batería adelante, otra en el medio y un botiquín atrás, en fila | Lo de adelante tapa lo de atrás, en primera y en tercera persona |

### Los arreglos de tu segunda prueba (2026-11-15)

Primero, en la notebook: `actualizar_lab.bat` (cambiaron el código y el Tuning).

1. **«No se ve» en el acto, en la notebook:** agarrá la **tabla larga** por una punta (clic derecho) y caminá alrededor de la **pared fina** hasta que la pared quede entre vos y la punta que agarraste. Apenas la tapa, se suelta, cae, y abajo dice «Se te soltó: no se ve». Repetilo con **Alt + 4** (internet mala): igual de rápido.
2. **En esta PC,** lo mismo del paso 1: también en el acto.
3. **Lo que no se suelta:** agarrá la tabla por una punta y metela detrás de la pared con la punta agarrada de tu lado: no se suelta. Y apretá la caja de herramientas contra la pared fina, de tu lado: a medio segundo dice «se trabó», no «no se ve».
4. **Si lo querés más lento** (en esta PC, **Jugar solo**): en Godot, `net_lab.tscn` → nodo **Tuning** → grupo **Objetos sueltos** → **Hold Hidden Time**, poné **0,5**, **F6** → **Jugar solo**, y repetí el paso 1: tarda medio segundo. Volvelo a **0** (si queda distinto en las dos PC, la huella no deja conectarse).
5. **Soltar hacia la cámara, en la notebook:** en tercera persona, caminá para atrás con **S** unos pasos (el muñeco gira y queda mirando hacia la cámara) y frená. **Tab**, clic derecho sobre un objeto → **Soltar**: aparece del otro lado del muñeco, hacia donde mira la cámara, no entre el muñeco y la cámara. Probalo también arrastrándolo afuera de la grilla, mirando hacia un costado y en primera persona.
6. **La torre que desarma el host:** en esta PC, armá una torre de tres o cuatro objetos (soltándolos del inventario o apilándolos con la mano) a la vista de la notebook, esperá a que se queden quietos y recogé el de abajo con **E**. En la notebook, el de abajo desaparece en el mismo momento en que empieza a caer lo de arriba: lo de arriba ya no queda en el aire. Repetilo con **Alt + 4** en la notebook.
7. **La torre que desarma el invitado:** lo mismo, recogiendo el de abajo con **E** desde la notebook. Tarda un poco en desaparecer (unos 0,2 s; con **Alt + 4**, más), pero desaparece junto con la caída de lo de arriba. En el inventario aparece en el acto.
8. **Lo suelto, en el acto:** en la notebook, recogé con **E** un objeto que no tenga nada encima ni pegado: desaparece en el acto, como antes.

### Los arreglos de tu prueba en las notebooks (la tarde del 2026-11-15)

Primero, en la notebook: `actualizar_lab.bat` (cambiaron el código y la configuración de física del proyecto).

1. **Los avisos:** en el editor, abrí **net_lab**, apretá **F6** y cerrá el juego. Abajo, pestaña **Debugger** → **Errors**: no tiene que aparecer ninguno de los 7 de tu captura (los de `inv_bodies.gd` y `inv_reach.gd`).
2. **Lo metido en el piso:** en la pista, soltá desde el inventario varios objetos uno encima de otro sobre el **machete**. Agarrá el de arriba (clic derecho), mirá al piso y apretá para abajo un par de segundos. Soltalo (clic derecho). Después recogé la pila de a uno con **E**: el machete se ve apoyado arriba del piso, y se agarra y se mueve.
3. **Lo que no se podía mover:** agarrá la **caja de herramientas**, levantala por encima de tu cabeza (mirá para arriba) y soltala (clic derecho). Hacelo varias veces, también con otros objetos. Después, agarralos: todos se mueven, ninguno queda trabado.
4. **Lo soltado en la notebook:** en la notebook, lo mismo del paso 3: la caja cae y queda apoyada, sin meterse en el piso. Repetilo con **Alt + 4** (internet mala): tampoco desaparece.
5. **Detrás de un muro:** agarrá la **tabla larga** por una punta y caminá alrededor de la **pared fina** hasta que la pared quede entre vos y la punta que agarraste. Se suelta, cae, y abajo dice «Se te soltó: no se ve» (desde tu segunda prueba, en el acto; antes, a medio segundo). Probalo también en la notebook.
6. **Lo que no se suelta:** agarrá la tabla por una punta y metela detrás de la pared, con la punta agarrada de tu lado: no se suelta. Y apretá la caja contra la pared fina, de tu lado: dice «se trabó» (como antes), no «no se ve».

### Lo nuevo del 2026-11-15, en esta PC (con el mouse)

1. Godot, pestaña **net_lab**, **F6** → **Jugar solo**. Andá a la pista.
2. **La tabla en la ranura:** agarrala por una punta (clic derecho), ponela a lo largo a la altura de la ranura y empujala: pasa entera. Cruzada, el muro la frena. Ya no queda metida adentro del muro.
3. **La tabla por la otra punta:** soltala, agarrala por la punta contraria y girá la vista: sigue agarrada por esa punta, sin saltar al centro.
4. **Una pila que pierde su apoyo:** soltá dos objetos uno encima de otro desde el inventario (o apilalos con la mano), esperá a que se queden quietos y recogé con **E** el de abajo: el de arriba cae enseguida.
5. **Contra la pared fina:** agarrá la caja de herramientas, acercate a la pared fina, alejala con la rueda hasta que toque la pared y girala con el botón central: no la cruza, ni se mete.
6. **La hitbox de agarre** (en el panel **Objetos**, ítem **Llave** → sección **Hitbox de agarre** → **Caja** → **+1 cm** dos veces → **Guardar**): en el juego, apuntá al piso 1 cm al costado de la llave: se marca y **E** la recoge. Con la llave detrás de la pared fina y la hitbox asomando de tu lado, no se marca.
7. **El cuerpo de un objeto** (panel **Objetos** → un ítem → sección **Cuerpo físico**): elegí **Del modelo: varias formas (con huecos)** y apretá **Generar del modelo**; en la **Vista previa**, en naranja, se ven las formas. **Guardar**. Volvé a **Del modelo: una forma convexa** y guardá (se genera solo al guardar).

### En las dos PC

1. **La huella cambió** (código, cuerpos y protocolo): en la notebook, `actualizar_lab.bat`.
2. **En la notebook**, agarrá la **caja de herramientas** y girá la cámara rápido y de golpe, como en tu video: tiene que quedarse en la mira igual que en esta PC, sin irse para atrás al parar. Probá con **Alt + 4** (internet mala): tiene que verse igual.
3. **En la notebook**, empujala contra la pared fina y girala ahí: no la cruza (y en esta PC tampoco).
4. **En la notebook**, lanzá la tabla: sale de la mano, no salta para atrás.
5. Mirá el panel (F1): en el host, en la línea del jugador, **«lo que sostiene:»** dice cuántas afirmaciones adoptó o coincidieron y cuántas rechazó y por qué; en la notebook, **«lo que sostenés:»** dice cuántas veces corrigió.
6. Lo de la primera versión sigue valiendo: los dos agarran la misma tabla a la vez (la agarra uno solo); uno sostiene algo y el otro le aprieta **E** (no se lo quita); con **Alt + 4**, agarrar y soltar enseguida (queda suelto en los dos); el que sostiene algo cierra el juego o muere (para el otro, se suelta y cae); la notebook entra tarde (ve todo en su lugar).

### Lo de la primera versión, en esta PC

1. **Rueda para arriba:** se aleja. **Para abajo:** se acerca. La cámara no hace zoom.
2. Mantené el **botón central** (la rueda apretada) y mové el mouse: el objeto gira y la cámara no. De costado gira alrededor del eje vertical de la vista; para arriba o para abajo, del horizontal; con **Shift** y de costado, como un volante. Soltá el central: volvés a mirar.
3. Agarrá la **granada** de delante de la pared fina y hacé **clic izquierdo:** sale lanzada hacia donde mirás, rebota en la pared y no la atraviesa.
4. Llevá algo contra una pared y seguí empujando lejos: no la atraviesa y, trabado más de medio segundo, se suelta solo («Se te soltó: se trabó»).
5. Con algo agarrado, probá **Tab**, **F3**, la **Q**, **Esc** y **Alt+Tab** (cambiar de ventana): cada uno lo suelta sin lanzarlo, y al volver mirás normal, sin nada pegado.
6. **F3** → **Opciones**. En **Botones del mouse** elegí **Laterales**; en **Sostener**, **Mantener**. Abajo, en **Probá el mouse**, apretá cada botón lateral sobre el panel: el trasero (cerca de la palma) tiene que decir **8** y el delantero (cerca del cable), **9**. Cerrá con **F3**. Mantener el lateral trasero agarra y soltarlo suelta; el delantero lanza.
7. Con algo sostenido, **E**: lo guarda. Si no entra entero, lo que sobra sigue en tu mano.
8. Frente al **estante**, en primera y en tercera persona: solo se marca y se agarra lo de adelante.

---

## 2. Controles

Mientras no sostenés nada, todo sigue como antes: la rueda acerca y aleja la cámara, y el clic izquierdo y el derecho no hacen nada en el mundo.

| Esquema | Agarra y suelta | Lanza |
| --- | --- | --- |
| **Principales** (de fábrica) | Botón **derecho** (acción `objeto_agarrar`) | Botón **izquierdo** (`objeto_lanzar`) |
| **Laterales** | Lateral **trasero**, cerca de la palma (`objeto_agarrar_lateral`) | Lateral **delantero**, cerca del cable (`objeto_lanzar_lateral`) |

| Sostener | Cómo |
| --- | --- |
| **Alternar** (de fábrica) | Un clic agarra; otro del mismo botón suelta sin lanzar |
| **Mantener** | Agarra al apretar; suelta al soltar el botón |

Mientras sostenés algo, en los dos esquemas:

| Qué | Hace |
| --- | --- |
| Rueda para arriba (`objeto_alejar`) | Lo aleja de a **Hold Wheel Step** (10 cm), hasta **Hold Max Distance** |
| Rueda para abajo (`objeto_acercar`) | Lo acerca, hasta **Hold Min Distance**. Para dar vuelta el sentido: **Hold Wheel Inverted** |
| Botón central mantenido (`objeto_rotar`) | El mouse gira el objeto, no la cámara: de costado, alrededor del eje vertical de la vista; para arriba y abajo, del horizontal; **Shift** de costado, del que va hacia adelante. **Hold Rotate Sensitivity** grados por píxel |
| Mover el mouse sin el central | Mirás, y el punto agarrado va con la mira |
| **E** sobre lo sostenido | Lo guarda en el inventario (entero, o lo que entra) |

**Los números de los botones.** Lo que Windows y Logitech llaman «Mouse 4» y «Mouse 5» son los laterales: en Godot, `MOUSE_BUTTON_XBUTTON1` (8, el trasero) y `MOUSE_BUTTON_XBUTTON2` (9, el delantero). Los números 4 y 5 de Godot son la rueda (`MOUSE_BUTTON_WHEEL_UP` y `_DOWN`). Todo va por acciones del Mapa de entrada (`project.godot`), nunca por números sueltos en el código.

**Si el programa del mouse cambió los laterales** (Logitech G HUB u otro): **F3** → **Probá el mouse** y apretá cada lateral sobre el panel. Tienen que llegar como **8** y **9**. Si no aparece nada, o llega otro número, el programa del mouse les puso otra función: en ese programa, devolvé esos dos botones a su función de fábrica (atrás y adelante). El laboratorio no necesita G HUB ni lo usa; con otro mouse funciona igual.

**Prioridad:** primero las interfaces (inventario, Opciones, la Q, el menú, un diálogo, un campo con el foco, el mouse suelto), después la mano y después la cámara. Si una interfaz toma el mouse mientras sostenés algo, se suelta sin lanzar. También al perder la ventana, al morir, al cortarse la conexión y al cambiar las preferencias.

---

## 3. Preferencias

- Son **de cada PC**: no viajan por red ni entran en la huella. Cada uno elige las suyas.
- Se cambian en **Opciones** (**F3**, o el botón **Opciones** del menú del laboratorio). Se guardan al elegir: no hay botón de guardar.
- El laboratorio no tenía dónde guardar preferencias. Van en un archivo propio: `user://opciones_del_laboratorio.cfg`, que en Windows es `%APPDATA%\Godot\app_userdata\Tun tun tun sahur\opciones_del_laboratorio.cfg`, sección `[mano]`, con `botones` (`principales` o `laterales`) y `sostener` (`alternar` o `mantener`).
- Si el archivo no está o tiene algo raro, se usan las de fábrica. Borrarlo vuelve a las de fábrica.
- Código: `scripts/inventory/inv_hand_prefs.gd` (las preferencias) y `scenes/net_lab/hud/lab_options.gd` (el panel).

---

## 4. Valores (nodo Tuning, grupo Objetos sueltos)

Los eligió Claude, para ajustarlos jugando. Entran en la huella, como todo el Tuning.

| Valor | De fábrica | Qué es |
| --- | --- | --- |
| **Item Mass** | 2 kg | La masa de cada objeto suelto, la misma para todos (no es un sistema de peso) |
| **Item Friction** | 0,8 | Cuánto roza, de 0 (hielo) a 1 |
| **Item Bounce** | 0,05 | Cuánto rebota |
| **Item Angular Damp** | 2 | Cuánto se frena su giro por segundo. Jolt no frena lo que rueda: sin esto, una granada rueda para siempre y nunca reposa |
| **Throw Impulse** | 16 N·s | El impulso al lanzar, el mismo para todos: con 2 kg sale a 8 m/s más lo que ya traía, hacia donde mira la cámara |
| **Hold Min Distance** y **Hold Max Distance** | 0,6 y 2,5 m | Lo más cerca y lo más lejos de los ojos que va el punto agarrado |
| **Hold Follow Time** | 0,08 s | En cuánto tiempo, más o menos, llega el punto agarrado a donde lo lleva la vista. Más chico, más rígido |
| **Hold Move Limit** y **Hold Accel Limit** | 12 m/s y 80 m/s² | Lo más rápido que lo mueve la mano y lo más que lo acelera. Contra una pared empuja con esto como mucho: no junta fuerza ni la atraviesa |
| **Hold Turn Limit** y **Hold Turn Accel** | 720 °/s y 7200 °/s² | Lo mismo para el giro |
| **Hold Break Distance** y **Hold Break Time** | 0,8 m y 0,5 s | Trabado más lejos que esto de donde lo lleva la mano durante ese tiempo, se suelta solo. También si queda más lejos de los ojos que **Hold Max Distance** más esto. Y es lo que espera el host para soltar lo tapado de un cliente, si su máquina no lo soltó (sección 17) |
| **Hold Hidden Time** | 0 s | Tapado por el nivel o una caja más que esto, se suelta solo («no se ve»). En 0, en el primer tick tapado. Desde tu segunda prueba (sección 18) |
| **Hold Wheel Step** | 0,1 m | Cuánto mueve cada paso de la rueda |
| **Hold Wheel Inverted** | apagada | Prendida, la rueda para arriba acerca |
| **Hold Rotate Sensitivity** | 0,25 °/píxel | Cuánto gira con el botón central |

El súper (Kp 2) no cambia nada de esto: ningún valor termina en **Speed**.

---

### Valores que están en el código (elegidos por Claude, 2026-11-15)

No son de cómo se siente la mano, sino de cuánto se le cree a cada máquina. Por eso van en el código, como los de la adopción del personaje (`ClaimAdoption`), y no en el Tuning. Si querés ajustar alguno desde el Inspector, se pasa al Tuning.

| Qué | Cuánto | Dónde |
| --- | --- | --- |
| El acceso de la hitbox: lo más que puede estar el modelo más allá del alcance | 25 cm | `InvReach.ACCESS_SLACK` |
| El host deja como está lo que difiere menos que esto | 0,5 mm, 0,05° y 2 cm/s | `InvBodies.SAME_POS`, `SAME_ANGLE` y `SAME_SPEED` |
| El host adopta hasta esto por cada tick del camino | 6 cm y 8° | `InvBodies.ADOPT_POS` y `ADOPT_ANGLE` |
| La primera afirmación después de agarrar | 35 cm | `InvBodies.START_POS` |
| Lo más largo del camino por afirmaciones (inputs que llegaron tarde) | 8 ticks | `InvBodies.MAX_CHAIN` |
| Sin acuerdo durante esto, el host sube la versión para que tu PC se corrija | 30 ticks (0,5 s) | `InvBodies.STALE_TICKS` |
| Tu PC cuenta como coincidencia lo que difiere menos que esto (con la misma versión, igual no corrige) | 1 cm y 1,5° | `InvHands.CORRECT_POS` y `CORRECT_ANGLE` |
| Lo que se ve va de lo viejo a lo corregido en | 6 ticks (0,1 s) | `InvHands.SMOOTH_TICKS` |
| Las formas se achican esto para ver si un lugar está libre | 5 mm | `InvItemPhysics.INSET` |
| Algo que ya arranca metido puede meterse de más, por cada paso de 1 cm | 1 mm | `InvHoldMotion.DEPTH_SLACK` |
| Lo plano (más fino que esto) va con una caja | 2,5 cm | `InvItemPhysics.FLAT_LIMIT` |
| Lo que Jolt duerme metido en el nivel más que su tolerancia (2 mm) y 5 mm se saca hasta | 10 cm, 3 veces por objeto | `InvBodies.UNSTICK_MAX`, `UNSTICK_TRIES` y `UNSTICK_MARGIN` |
| Lo que se despierta alrededor de lo que sale del mundo | su caja más 5 cm | `InvBodies.WAKE_MARGIN` |
| El rayo de «no se ve» (y el del acceso) se corta antes del punto | 1 cm | `InvReach.ACCESS_TOUCH` |

**En la configuración del proyecto** (la tarde del 2026-11-15, elegido por Claude): `project.godot`, sección `[physics]`, `jolt_physics_3d/simulation/penetration_slop=0.002`. Es lo que Jolt deja meterse una cosa en otra sin corregirlo: **2 mm** (de fábrica, 2 cm). Vale para toda la física del proyecto. La repetición del personaje dio la misma huella byte a byte, así que el movimiento de los personajes no cambió. Para volver a la de fábrica, se borra esa línea (sección 17).

---

## 5. Dónde está cada objeto: suelto, sostenido o en un inventario

Cada objeto está en uno solo de tres lugares (`InvAuthority`, en el host):

| Lugar | Cómo es |
| --- | --- |
| **Suelto en el mundo** | Con su cuerpo físico, cae, choca y reposa. Nadie lo sostiene |
| **Sostenido en el mundo** | Sigue en el mundo, con su cuerpo, y lo lleva la mano de un jugador. Un solo jugador por objeto y un objeto por jugador. No está en ningún inventario |
| **En un inventario** | En una grilla. Ya no está en el mundo ni tiene cuerpo |

Los cambios son pedidos al host, en el mismo orden que todo el inventario (`InvProtocol`, versión 3 desde el 2026-11-15):

| Pedido | De → a | Qué mira el host |
| --- | --- | --- |
| **GRAB** (agarrar) | suelto → sostenido | Su propio rayo, desde tus ojos y con la dirección que mandaste, tiene que tocar ese objeto antes que otra cosa, al alcance (**Interaction Range**), con la regla de la sección 8. El punto que toca es por donde se agarra (aunque caiga en un hueco del modelo), y te lo devuelve para que tu PC use el mismo |
| **RELEASE** (soltar) | sostenido → suelto | Que lo sostengas vos, con esa sesión de agarre. Desde el 2026-11-15 lleva el último tick en que lo sostuviste: si el host todavía no lo simuló, lo sigue llevando hasta ese tick y recién ahí lo suelta, con la pose y las velocidades que tenía en tu mano |
| **THROW** (lanzar) | sostenido → suelto | Lo mismo, y le suma un solo impulso, en ese mismo momento |
| **PICKUP** (E) | suelto, o sostenido por vos → inventario | Suelto: el rayo, como siempre. Sostenido por vos: sin rayo (ya lo tenés en la mano). Lo que no entra queda en el mundo, con su lugar y, si lo sostenías, en tu mano. Sostenido por otro: no, nunca se le quita. Al sacarlo del mundo, despierta lo que se apoyaba en él (sección 10) |
| **DROP** y **DROP_AT** (soltar desde el inventario) | inventario → suelto | Aparece adelante, a la altura del pecho (o alrededor, si ahí no cabe), con el giro del personaje, y cae. Tiene que verse desde el pecho (no del otro lado de una pared) y caber sin tocar el nivel, una caja, una escalera, un personaje ni otro objeto suelto |

**El host suelta solo** lo que se traba («se trabó»), lo que queda lejos («quedó muy lejos»), lo que una pared tapa («no se ve», desde la tarde del 2026-11-15; el mecanismo, en la sección 17) y lo de un jugador que muere, se va, se desconecta o cambia de personaje.

**Las sesiones y las versiones:** cada agarre lleva un número que pone tu PC, de a uno más. Soltar y lanzar lo nombran, y lo que llega de una sesión vieja no hace nada. Así un paquete tardío no vuelve a agarrar algo soltado, no revive algo recogido y no lanza dos veces. Desde el 2026-11-15, además, cada sujeción tiene una **versión**, que sube cuando el host rechaza lo que afirmó tu PC (sección 9). Lo afirmado con una versión vieja no se adopta. Soltar, lanzar, recoger, morir y desconectarse terminan la sujeción: lo que llegue después ya no es de ninguna.

**Sostener no es llevar algo con el cursor dentro del inventario.** Eso es de la interfaz (`InvUI`) y no cambia nada en el host hasta que se deja.

---

## 6. Capas de física

| Capa | Qué hay | Los objetos sueltos chocan |
| --- | --- | --- |
| 1 | El nivel y las cajas | Sí |
| 2 | Los personajes | **No** (decidido por vos) |
| 3 | Las escaleras | Sí |
| 4 | Los objetos sueltos | Sí, entre ellos |

Para ver si algo cabe al soltarlo se miran el nivel, las cajas, los personajes y las escaleras con sus formas (no se suelta adentro de nadie), y los demás objetos sueltos por su caja, así la cuenta da lo mismo en el cliente, que no tiene los cuerpos. Los cuerpos tienen detección continua de choques (CCD): una granada a 120 m/s no atraviesa la pared de 2 cm.

En un cliente, los objetos son copias **sin forma de choque**: solo el host los simula. Lo que sostenés vos se predice con consultas al nivel, sin cuerpos de más que choquen en la escena (sección 9).

---

## 7. El cuerpo físico de cada tipo (desde el 2026-11-15)

Son tres cosas distintas, cada una con lo suyo:

- **Lo que se ve:** el modelo.
- **Con qué se apunta y se agarra:** la hitbox de agarre, si el tipo tiene una; si no, los triángulos del modelo (sección 8).
- **Con qué choca:** el cuerpo físico, `InvItemDef.body_shape` (un `InvBodyShape`), preparado en el editor y guardado en el `.tres`. El juego solo lo carga: no arma nada al jugar, ni en cada objeto, ni en cada conexión, y no depende de que cada PC lo arme igual.

**Las formas posibles** (panel **Objetos**, sección **Cuerpo físico**):

| Forma | Qué es | Para qué |
| --- | --- | --- |
| **Del modelo: una forma convexa** | Godot envuelve el modelo con una sola forma (`Mesh.create_convex_shape`) | Lo compacto y redondo: exacta en los bordes, tapa los huecos |
| **Del modelo: varias formas (con huecos)** | La descomposición de Godot (V-HACD, `MeshInstance3D.create_multiple_convex_collisions`): varias formas convexas que conservan huecos y entrantes. Valores: **Formas, como mucho** (16), **Concavidad** (0,01 m) y **Resolución** (100000) | Un marco, un aro, un banquito con patas |
| **Caja**, **Esfera**, **Cilindro** | Una primitiva, que arranca ajustada al modelo: medidas, **Ajustar al modelo**, **−1 cm**, **+1 cm**, lugar y giro | Lo que es una caja (una tabla) y lo plano |
| **Forma propia (en el Inspector)** | Un recurso de colisión convexo, tal cual | Lo que ninguna de las anteriores resuelve |

**Generar:** con una forma del modelo, el botón **Generar del modelo** las arma y las deja en el ítem; **Guardar** las guarda. Si cambiás el modelo, su tamaño o los valores, la sección dice **«Sin preparar»**: quedaron desactualizadas. Al guardar, si hace falta, se generan solas; si no salen, no se guarda (no queda un cuerpo que no sirve como si estuviera bien).

**Revisar:** en la **Vista previa** general el cuerpo se ve en **naranja** (la casilla **Ver el cuerpo físico** lo oculta) y la hitbox en **celeste** (**Ver la hitbox de agarre**). Debajo de la sección dice cuántas formas tiene, cuánto ocupa al lado del modelo y, después de generar, si alguna queda más de 6 mm adentro del modelo o sobresale.

**Para todos los del catálogo a la vez** (por ejemplo, después de cambiar varios modelos): `addons/inventario_objetos/preparar_cuerpos.gd`, un script para Godot sin ventana, con el proyecto cerrado:

```bash
"C:/Users/ElCaido97/Desktop/Godot_v4.7.2.exe" --headless --path . --script res://addons/inventario_objetos/preparar_cuerpos.gd
```

Prepara solo lo que no tiene cuerpo o lo tiene desactualizado. Lo que ya sirve no lo toca. Da siempre lo mismo con el mismo modelo, y conserva el identificador (UID) de cada archivo. Con `-- --probar` dice lo que haría sin guardar nada.

**Qué tiene cada objeto** (lo preparó ese script el 2026-11-15, con la regla de `InvItemPhysics.suggest`, elegida por Claude):

| Objeto | Cuerpo | Por qué |
| --- | --- | --- |
| Tabla larga, batería, caja de herramientas, puerta de Perón, portón de Musolini, botiquín, vendas | Caja ajustada | El modelo es una caja |
| Llave (1,4 cm) y machete (2,3 cm) | Caja ajustada | Son planos. Con cualquier forma convexa (la de Godot, la simplificada o la de la descomposición), Jolt los dejaba de 20 a 70 mm metidos en el piso, apoyados inclinados. Con la caja, 0 |
| Botella, granada, banquito, tornillos, linterna, bebida, frasco de veneno, cápsula, venen lento, toxina | Del modelo: una forma convexa | Compactos. La descomposición recortaba los bordes de lo chico (3 mm por lado a la llave y a la granada), y a lo redondo no se le recortan los extremos |
| (ninguno) | Del modelo: varias formas | Ninguno del catálogo tiene un hueco que cuente para jugar. La prueba lo comprueba con un marco hecho en memoria |

**Sin cuerpo preparado** (un ítem nuevo hecho a mano, sin el panel), el juego usa una sola forma convexa del modelo y la consola lo avisa una vez por tipo. En el editor no avisa: ahí lo muestra el panel en **Cuerpo físico** (antes el aviso salía al abrir el editor, por el ítem nuevo vacío del panel). Entra en la huella con sus puntos.

**La huella** suma, de cada tipo, las formas con sus puntos y su lugar, y si estaba preparado. Si las dos PC no las tienen igual, la notebook no entra.

**Hasta el 2026-11-15** el juego partía el modelo en tajadas en cada PC, con un algoritmo propio: dejaba rendijas de hasta 20 cm (la tabla quedaba metida en el muro de la ranura, de 20 cm). Ya no existe, ni como respaldo.

**Los marcadores (InvPickupSpawn)** dejan el objeto con el giro del marcador. El objeto arranca quieto y **dormido** donde está el marcador: no se mueve hasta que algo lo toca, alguien lo agarra o pierde su apoyo.

---

## 8. La hitbox de agarre: elegir, el acceso y por dónde se agarra (desde el 2026-11-15)

**La regla** (`InvReach.first_hit`, la misma para el indicador, para E, para agarrar y para lo que valida el host):

- **Con una hitbox de agarre que sirve** (`InvPickupHitbox.active`): el rayo toca esa forma, aunque pase por un hueco del modelo. No hace falta tocar antes sus triángulos.
- **Sin hitbox** (o con **Forma del modelo**, o con una que no sirve): los triángulos del modelo, como desde el 2026-11-11.
- Gana lo primero que toca el rayo desde los ojos, al alcance (**Interaction Range**, medido desde los ojos hasta el punto tocado). El nivel y las cajas tapan, y la tercera persona sigue con su cono.

**El acceso**, para que una hitbox que asoma de una pared no deje agarrar lo de atrás (`InvReach.access_point`). Cuando el rayo toca una hitbox:

1. se busca el punto del **modelo** más cercano al punto tocado;
2. ese punto tiene que **verse desde los ojos**: un rayo de los ojos a él no puede tocar el nivel ni una caja, salvo en el último centímetro (el objeto apoyado contra una pared);
3. y tiene que estar a no más del alcance **más 25 cm** desde los ojos.

Si no se cumple, esa hitbox no cuenta: no se elige ni tapa a lo de atrás. Así ayuda a apuntar (a una llave chica, a un arma con huecos) pero no deja agarrar algo detrás de una pared, ni algo que está más lejos que el alcance. Las hitbox de objetos lejanos que cruzan la mira tampoco tapan (como AG-02).

**Por dónde se agarra:** por el punto tocado de la hitbox, en el espacio del objeto, aunque caiga en un hueco del modelo o afuera de él (un **anclaje virtual**). No se cambia por el centro ni por el punto del modelo más cercano: agarrado por una punta, se gira alrededor de esa punta.

**El índice** (`InvSpatialIndex`) anota cada objeto con la caja de todo lo suyo: el modelo, el cuerpo y la hitbox, ya movida y girada. Una hitbox más grande se encuentra sin recorrer todos los objetos.

**Lo que no cambió:** el indicador enmarca el modelo, no la hitbox; la hitbox no choca con nada ni cambia el cuerpo; se edita en el panel (sección **Hitbox de agarre**, arriba de **Cuerpo físico**) y entra en la huella.

---

## 9. Lo que sostenés en tu PC: predicción y control del host (desde el 2026-11-15)

**Las mismas cuentas en las dos máquinas** (`InvHoldMotion`). En cada tick T, con el personaje ya movido:

1. **adónde va la mano:** tus ojos más la vista por la distancia, con el giro pedido sobre el yaw de la cámara, con el input de ese tick;
2. **las velocidades:** con lo de después del tick T − 1, acotadas por el Tuning (**Hold Follow Time**, **Move Limit**, **Accel Limit**, **Turn Limit**, **Turn Accel**);
3. **mirar el nivel:** antes de dar el paso, en pasos de 1 cm de cualquier punto del cuerpo, también al girar sin moverse. Si se mete en algo, se desliza por los ejes libres, gira solo o se queda. Jolt frena los choques al moverse, no al girar: una caja girada contra la pared de 2 cm la cruzaba con una punta. **Si ya estaba metido** (lo apretó una pila, o Jolt lo dejó así), puede salir o arrastrarse, pero no meterse más hondo que al empezar, y una vez afuera no vuelve a meterse (`InvHoldMotion.path_free`, desde la tarde del 2026-11-15). Antes solo le dejaba dar un paso de 2 cm que lo sacara entero, y la mano pide más: lo metido quedaba trabado (sección 17);
4. **el paso:** en el host lo da Jolt, con todos sus choques (también con los demás objetos); en tu PC, las mismas cuentas sin Jolt.

**El contrato del tiempo:**

- Lo predicho para el tick T es lo de después del paso del tick T. Viaja con el input de ese tick (`ActorInput.held_claim`, 41 bytes) y, como los inputs viajan de a seis, también en los cinco siguientes.
- El host lo compara al empezar el tick T + 1, con su propio resultado del tick T: el mismo instante.
- Las poses que manda el host dicen el tick que de verdad son. Hasta el 2026-11-15 salían con el número del tick siguiente.
- Hasta ese día, además, la mano del host usaba el pedido del tick anterior (iba en `_integrate_forces`, que Jolt llama antes del tick).

**El host decide** (`InvBodies._judge_claim`). Por cada tick, lo que afirmó tu PC:

- **igual:** casi lo mismo (menos de 0,5 mm, 0,05° y 2 cm/s): no toca nada;
- **adoptada:** queda en la pose y con las velocidades que afirmaste. Solo si se cumple todo:
  - es de esa sujeción, esa sesión y esa versión;
  - sus velocidades están dentro de los límites de la mano;
  - desde la última coincidencia o corrección del host no tocó otro objeto que se mueve;
  - está a menos de 6 cm y 8° de lo del host por cada tick del camino;
  - el camino, tick por tick, no mueve más de lo que mueve la mano en un tick ni se mete en nada (el nivel, una caja, una escalera, otro objeto).

  No se teletransporta a ciegas: el lugar y el camino están libres, así que Jolt no tiene nada que separar y no hay impulsos de más;
- **rechazada** («tocó otro objeto», «muy lejos», «movimiento imposible», «se mete», «valores imposibles»): se queda con lo suyo y sube la versión de la sujeción. La pose y el tick de esa corrección pasan a ser el nuevo punto de partida (`checkpoint`), también para los contactos: el choque anterior ya está incorporado. Lo que afirmó tu PC con la versión vieja ya no se adopta, y sube a lo sumo una vez por ida y vuelta (lo que llega con la versión vieja no se juzga);
- **el camino:** si un input llegó tarde (el host simuló ese tick con el anterior y quedó corrido), el camino va desde la última coincidencia o corrección, por lo que afirmaste de cada tick (hasta 8). Así un input tardío no termina en una corrección.

**El acuerdo de la versión:** con la misma versión, el host se compromete a adoptar o coincidir con lo que afirma tu PC. Si no puede, sube la versión: porque rechazó una afirmación, o porque pasó medio segundo sin ninguna que le sirva (**«sin acuerdo»**, por ejemplo si tus inputs no llegan).

**Tu PC corrige** (`InvHands._reconcile`) cuando llega una pose del host de un tick H:

- **con la misma versión, no corrige.** Si la pose difiere, es que al host le faltó tu input de ese tick (lo simuló con el anterior) y tu afirmación todavía viaja: corregir ahora sería corregir dos veces. Es lo mismo que hace el personaje con un input que llegó tarde;
- **con otra versión, corrige:** parte de lo del host en H y repite los ticks hasta el presente con lo que pedía la mano en cada uno. El suavizado empieza desde lo que realmente se estaba dibujando, incluyendo cualquier suavizado pendiente, y converge nominalmente en 0,1 s. El recorrido visual también respeta el nivel: si se traba contra el piso o una pared, avanza hasta el contacto, sin descartar el suavizado entero ni saltar a la pose cruda. Detalle de la corrección del temblor: [informe del 2026-11-15](correccion_temblor_objetos_guest_2026-11-15.md).

Esto lo encontró la prueba con internet mala: con una corrección por cada diferencia, un input tardío hacía corregir en tu PC hacia una pose que el host iba a reemplazar enseguida (14 correcciones girando a 360 °/s).

**Los choques con otros objetos** los resuelve el host. Empujar una caja suelta, o chocar con lo que sostiene otro jugador, rechaza la afirmación de ese momento y tu PC se corrige con lo del host. Nunca se adopta algo que borre la respuesta de un choque y deje su impulso en el otro objeto. No hay transferencia de autoridad a lo que se empuja.

**Soltar y lanzar:** el host espera al último tick en que lo sostuviste. En tu PC lo soltado sigue adelantado, cayendo o lanzado desde tu mano, y las poses del host lo corrigen llevadas al presente. Al quedar quieto en el host (o a los 2 s) vuelve a verse como los demás objetos. No salta para atrás. Desde la tarde del 2026-11-15, cada tick de esa caída usa el mismo paso que la mano (`InvHoldMotion.guard`): contra el piso se queda, contra una pared se desliza y, si la pose del host lo trae un poco metido, no se hunde más (sección 17).

**«No se ve», en tu PC** (desde tu segunda prueba): después de predecir cada tick, tu PC mira si el punto agarrado se ve desde los ojos, con la misma mirada que el host (`InvHands._check_hidden`). Tapado más de **Hold Hidden Time** (de fábrica, en el primer tick), lo suelta como con el botón: el pedido dice que lo sostuviste hasta ese tick y lo soltado sigue cayendo desde tu mano. El host no espera nada para eso. El mecanismo entero está en la sección 17.

**Al entrar:** la mano espera a que el actor local esté simulado y el reloj del cliente sincronizado, la misma condición necesaria para transmitir sus inputs. Tener ya la réplica del inventario no alcanza. Así no se inicia un agarre que solo se predice en el invitado mientras el host todavía no recibe sus objetivos.

**La cámara lenta:** tu PC usa el tiempo del mundo de cada tick (`SimClock.world_dt`), y Jolt el suyo (`Engine.time_scale`): la misma escala, una sola vez. Medido: con cámara lenta, el host y tu PC dan lo mismo.

**Lo que se mide:**

- **En el panel (F1):** en el host, la línea **«lo que sostiene:»** de cada jugador, con cuántas afirmaciones se adoptaron, cuántas coincidieron y cuántas se rechazaron, por motivo. En tu PC, **«lo que sostenés:»**, con cuántas veces coincidió, cuántas corrigió y la corrección más grande.
- **En la consola:** las tres primeras veces de cada motivo de rechazo.
- **Al terminar una prueba con resumen:** las dos líneas.

**F2** apaga la adopción del personaje y la de lo sostenido a la vez.

---

## 10. Sacar un apoyo: lo de arriba cae (desde el 2026-11-15)

**El problema:** Jolt no despierta lo que está dormido encima de un cuerpo que se borra. Lo de arriba quedaba flotando. Pasaba también con cajas comunes de Godot.

**Ahora** (`InvBodies.despawn` con `wake_neighbors`, y `InvBodies.wake`), cuando un objeto sale del mundo de verdad (recogido con **E**, entero):

1. **antes** de sacarlo del índice, se buscan en el índice los objetos cuya caja toca la suya agrandada 5 cm, y se despiertan. Alguno de más se despierta y se vuelve a dormir solo;
2. el cuerpo sale del mundo físico **en el acto**, no al final del cuadro: en el próximo paso de Jolt ya no sostiene a nadie;
3. **despertar** es una sola operación del gestor, que pone al día todo lo que dependía del sueño:
   - que se lea su pose en cada tick y salga en los paquetes, así tu PC lo ve caer durante la caída;
   - que su entrada del mundo ya no diga que duerme;
   - que no lo vuelva a dormir el arreglo de lo que nace dormido.

   Cambiar `sleeping` a mano no alcanza: Godot no avisa, y la pose que ve el rayo quedaba quieta.

**No despierta a nadie** recoger una parte de una pila que sigue en el mundo, ni borrar una copia en un cliente.

**Lo que ve el invitado** (desde tu segunda prueba, sección 18). Los objetos se le dibujan unos 0,1 s en el pasado, y la caída de lo de arriba le llega con ese atraso:

- **Lo saca el host** (lo recoge él, u otro jugador): el aviso trae el tick en que salió (`"wrt"`). El invitado lo sigue dibujando, sin poder mirarlo ni agarrarlo, hasta que lo que muestra llega a ese tick, y recién ahí lo deja de dibujar (`InvBodies._waits_for_fall`). Es el mismo tick en que empieza la caída de lo de arriba. Antes se borraba apenas llegaba el aviso, unos 6 ticks antes de que se viera caer lo de arriba, y eso quedaba en el aire.
- **Lo recoge el invitado con E:** si algún objeto toca su caja agrandada 5 cm (los mismos que despierta el host, `InvBodies._has_neighbors`), se sigue dibujando hasta que el host contesta y lo que muestra llega a su tick, como arriba. Si nada lo toca, desaparece en el acto, como desde el 2026-11-04. El inventario se pone al día en el acto en los dos casos. Lo elegiste vos.
- **Lo que se despierta empieza a moverse en su tick:** lo que duerme no recibe poses, salvo un repaso cada tanto, así que la última pose que tenía el invitado podía ser de hace mucho. Se interpolaba desde ahí, y empezaba a moverse antes de tiempo (en la prueba de la torre, la pose era de 26 ticks antes; con muchos objetos dormidos, por cuenta, puede ser más de un segundo). Ahora sigue quieto hasta el tick anterior a la primera pose en que se mueve (`InvBodies.add_sample`).

**El rescate** (`InvBodies._unstick`): si Jolt duerme un objeto metido en el nivel más que su tolerancia de penetración (2 mm en `project.godot` desde la tarde del 2026-11-15; 2 cm de fábrica) más 5 mm, medido con los puntos de contacto que da Jolt (`InvItemPhysics.depth`), el host lo saca por el camino más corto, de a 1 cm y hasta 10 cm, y lo deja caer. Como mucho 3 veces por objeto, y la consola dice qué objeto, dónde y en qué se metió.

Lo agregó Claude por la llave de la prueba: con su forma convexa, soltada contra una pared, quedaba 4 cm adentro del piso. Con los cuerpos de ahora no hizo falta en ninguna prueba.

Al principio el rescate actuaba desde 5 mm, y peleaba con Jolt: una granada apoyada un poco metida en el piso de la pista se sacaba, volvía a caer igual y se volvía a sacar. Debajo de su tolerancia, Jolt no corrige lo que se apoya, y es lo normal.

---

## 11. Qué instante usa cada uno

**Lo que ves en tu PC:**

- Los objetos (también los que sostiene otro) se ven en el mismo instante que los otros jugadores: el tick del host que tu PC muestra, unos 6 ticks (0,1 s) más la mitad de la ida y vuelta por detrás del host.
- **Lo que sale del mundo, también** (desde tu segunda prueba): se deja de ver al llegar al tick en que salió, no cuando llega el aviso (sección 10).
- Lo que sostenés vos se ve **en el presente**, predicho (sección 9). Lo que acabás de soltar o lanzar, también, hasta que queda quieto.
- Lo que recogés con **E** desaparece en el presente, salvo que algo se apoye en él o lo toque: entonces, junto con la caída de lo de arriba (sección 10).

**Lo que valida el host** al recoger, abrir o agarrar:

- **Tus ojos:** los del tick del input en que apretaste (auditoría del 2026-11-12, INT-01), es decir, tu personaje en su presente.
- **Los objetos:** donde estaban en el tick que tu PC mostraba al apretar. El host guarda la pose de lo que se mueve en cada tick del último segundo.
- No hay un rollback del mundo: solo se vuelven atrás las poses para ese rayo.

**Pausa** (G, solo jugando solo): los cuerpos se congelan donde están y al seguir recuperan su velocidad.

---

## 12. Qué viaja por la red

| Qué | Cómo | Cuándo |
| --- | --- | --- |
| **GRAB, RELEASE, THROW** y todo lo del inventario | Pedidos confiables, en orden (`InvProtocol`, versión 3) | Al hacerlo |
| **Respuesta al agarre** | Confiable: el punto por donde se agarró | Al aceptarlo |
| **Se te soltó** (el host soltó solo) | Confiable, con el motivo | Al pasar |
| **Lo que entra, sale, se agarra o se suelta** | En los paquetes confiables del inventario, con su pose entera. Lo que sale, desde tu segunda prueba, con el tick en que salió (`"wrt"`) | Al pasar, y entero al que entra tarde |
| **Las poses de lo que se mueve** | Sin confiable, **38 bytes** por objeto (desde el 2026-11-15, uno más: la versión de la sujeción), hasta 32 por paquete, con el tick que de verdad son | Cada 2 ticks (30 por segundo) |
| **La mano** (distancia, giro) y **lo que afirmás de lo sostenido** | En el input de cada tick (16 bytes de mano y 41 de afirmación) | Siempre que sostenés algo |

- **Paquetes de inputs:** `NetSync.input_packets` conserva los seis ticks redundantes, pero los reparte en datagramas de hasta **1200 bytes de payload** según su tamaño real, agrupando primero los más recientes. Con la afirmación del objeto y la del personaje, antes ocupaban 1437 bytes en un solo paquete (ENet recibía 1440 y avisaba MTU 1392). También se cuentan los usos pendientes; no se cortan registros. Si un tick corregido se vuelve a recibir con una versión de sujeción anterior, no sobrescribe la revisión nueva. El formato de lectura y el heartbeat siguen iguales.
- **Con todo quieto,** en medio segundo salen 15 poses, una por paquete (la ronda de los dormidos): 570 bytes. Medido con 0, 300 y 3000 objetos dormidos, da lo mismo.
- **Lo que se cae del mapa** (más abajo de −30 m) vuelve, quieto, a donde reposó por última vez.
- **La huella** suma la versión del protocolo, el cuerpo físico de cada tipo (sus formas), su hitbox, los valores del Tuning y el giro de los marcadores, además del código.

---

## 13. El índice de los objetos y lo que cuesta

Una grilla de celdas de 1 m (`InvSpatialIndex`): cada objeto se anota en las celdas que toca la caja de todo lo suyo (modelo, cuerpo y hitbox, ya movida y girada). El rayo recorre solo las celdas que cruza, en orden. Hay uno en el host (el de la autoridad, con la historia del último segundo) y uno en cada cliente (el de lo que se ve). Un objeto quieto no se toca.

**Medido en esta PC el 2026-11-15** (`inv_fisica_test`, el mismo grupo de objetos cerca y 0, 300 y 3000 objetos dormidos a 1 km):

| Objetos lejos | El selector (los dos rayos) | El rayo del host | Revisando todos | Un cuadro entero del laboratorio |
| --- | --- | --- | --- | --- |
| 0 | 59 µs | 19 µs | 0,3 ms | 2,3 ms |
| 300 | 59 µs | 19 µs | 1,0 ms | 2,7 ms |
| 3000 | 59 µs | 19 µs | 10,5 ms | 6,5 ms |

- El selector y el rayo del host no cambian con los objetos lejanos: miran 3 candidatos.
- **El cuadro entero sí sube** con 3000 dormidos: es lo que cuesta Jolt con tantos cuerpos, aunque duerman.
- La mano mira el nivel en pasos de 1 cm, en el host y en tu PC: con la tabla girando a 720 °/s, la punta lejana avanza unos 33 cm por tick, o sea unas 33 consultas por tick, solo para lo que se sostiene. Es una cuenta, no una medición.

---

## 14. Pruebas

**`scenes/net_lab/inventario/pruebas/inv_fisica_test.tscn`** (el laboratorio entero, con la pista de física):

- **Jugando solo** (**248 de 248**). Lo de la primera versión (lo colocado, las preferencias, los dos esquemas y los dos modos, la rueda y el botón central, las interfaces que sueltan, la tabla por la punta y en la ranura, reposo, choques, la mesa, la pared de 2 cm a 60 y 120 m/s, los límites, el inventario, el objeto que gira, la fila del estante, la medición) y, desde el 2026-11-15:
  - **los cuerpos:**
    - los 19 del catálogo, preparados y usados tal como están en el `.tres`;
    - ningún vértice de un modelo a más de 3 mm afuera de su cuerpo, y ningún cuerpo que sobresalga;
    - la tabla, una sola caja de todo su largo;
    - soltados derechos e inclinados, de 2 cm y (desde la tarde) de 1 m, nada queda metido en el piso más de 6 mm, y el host no tuvo que rescatar ninguno;
  - **el marco con hueco:** su cuerpo de varias formas, generado con la herramienta de Godot, no lo tapa. Sin hitbox, por el hueco no se elige; con una hitbox que lo tapa, sí, con el punto en el hueco (anclaje virtual), y el cuerpo sigue sin taparlo;
  - **la llave con una hitbox 3 cm más grande:**
    - su cuerpo no cambia y el índice incluye la hitbox;
    - 2 cm al costado del modelo, se elige y se agarra por ese punto, igual en la mano y en el host, y girando sigue ahí; afuera de la hitbox, no;
    - detrás de la pared fina, con la hitbox asomando 8 cm de este lado, no se elige y el host rechaza el pedido;
    - en el borde de la mesa, sí;
    - a 15 cm menos que el alcance, sí; a 10 cm más, no;
  - **las pilas:** tres baterías dormidas (y otras recién nacidas, en el mismo tick): recogida la de abajo, caen, se ponen al día durante la caída (la pose y el índice) y vuelven a reposar una sobre otra. La del costado no se mueve, no queda nada anotado, y recoger una parte de una pila no despierta a nadie;
  - **lo metido en el piso** (`_sunk_and_pressed`, la tarde del 2026-11-15):
    - el machete debajo de dos botiquines y la caja de herramientas, apretados 2 s para abajo con la mano: al reposar, a no más de 5 mm;
    - la caja de herramientas metida 1,5 cm: el camino deja arrastrarla y sacarla para arriba, no hundirla; agarrada con la mano, sale y nunca queda más metida que al empezar;
  - **lo tapado** (`_hidden_release`, la tarde del 2026-11-15): la tabla con una pared delante de una punta (agarrada por la otra se ve, por la tapada no); la caja sostenida con una pared que aparece entre los ojos y ella se suelta con «no se ve»: desde tu segunda prueba, con **Hold Hidden Time** en 0, en el primer tick, y en 0,25 s, a los 15 ticks, no antes;
  - **soltar hacia la cámara** (`_drop_toward_camera`, después de tu segunda prueba): con el cuerpo mirando para atrás de la cámara, a 0,9 y a −2,2 rad, lo que muestra esta máquina, el lugar que busca el host sin propuesta y lo que deja el host salen adelante de la cámara y girados como ella.
- **Tres procesos** (host, A con +200 ms, ±40 ms y 5 % de pérdida, y B que entra tarde): host 13, A 12 y B 8, sin fallas.
- **La mano en red** (`--fisica-pair=mano_host` y `mano_cliente`, dos procesos): host **14** y cliente **31**, sin fallas, sin red simulada y con +200 ms, ±40 ms y 5 % de pérdida. Mide la caja de herramientas a 180, 360 y 720 °/s y la tabla por una punta (el atraso del controlador, del host y de lo que se ve, el tiempo hasta quedar quieta y las correcciones); la caja soltada de 2,16 m, que lo que se ve en el cliente no se meta en el piso más de 1 cm al caer (desde la tarde del 2026-11-15); la pared fina, empujando y girando sin moverse (lo que se ve nunca la cruza ni se mete, en el host tampoco); la tabla lanzada (un solo impulso); la pila que cae, vista desde el cliente durante la caída; la cámara lenta; y lo que adoptó y rechazó el host, por motivo. Desde tu segunda prueba, además, sobre un piso de prueba que arman las dos máquinas:
  - **«no se ve»** con la pared solo en el cliente (la suelta el cliente en el primer tick y el host nunca la ve tapada) y solo en el host (la suelta el host a los 30 ticks y el cliente recibe «no se ve»);
  - **la pila, sacada por el host:** en el cliente, la de abajo se deja de ver a no más de 4 ticks de cuando empieza a caer la de arriba;
  - **lo que recoge el cliente con E:** una batería suelta se deja de ver en el acto; la caja de herramientas con una batería encima, a no más de 4 ticks de la caída de la batería.

**El panel Objetos** (`prueba_del_creador`, en una copia del proyecto): **256 de 256**. Lo nuevo de **Cuerpo físico**:

- un ítem nuevo, sin preparar y avisado;
- **Generar del modelo** con varias formas, y desactualizado al cambiar la concavidad;
- la caja ajustada, y la de ancho 0, rechazada;
- agrandar la hitbox no agranda el cuerpo, ni al revés;
- guardar, con el cuerpo y la hitbox cada uno en lo suyo, y releer;
- duplicar, con los dos copiados y sin tocar el original;
- volver a «Del modelo» y guardar, que lo genera solo;
- el juego usa la forma guardada, sin generar nada;
- dos copias dan la misma huella, y 1 mm la cambia.

Jugando en la misma copia (`prueba_del_creador_juego`): **39 de 39**, con la hitbox de la varilla que ahora cuenta.

**Las de antes, adaptadas a las reglas nuevas** (sin sacar protecciones):

- `inv_hitbox_test` e `inv_alcance_test` comprobaban que la hitbox no contaba: ahora comprueban que adentro de ella se elige y afuera no. Siguen la pared delante, la pared que cruza el marco, la hitbox que asoma de una pared y las láminas lejanas (AG-02).
- **El ayudante de las pruebas** (`inv_mano_de_prueba.gd`, `toward_item`) apunta primero al centro del objeto, como un jugador. Antes probaba primero la esquina más cercana a los ojos: un rayo que roza el borde. Con los ojos del host unos milímetros corridos (un input que llegó tarde), pasaba por arriba y tocaba el piso, y `inv_partes_test` fallaba 2 de 8 veces al recoger un botiquín («hay algo en el medio»). El juego no cambió en esto.
- `inv_model_test`: el input tiene un byte más (el largo de la afirmación), y se suma que la afirmación se lee igual del otro lado y que una de otro largo se descarta.
- `inv_fisica_test`:
  - **la granada de lanzar,** ahora redonda de verdad, rueda más lejos, y la prueba la vuelve a poner en su lugar;
  - **el objeto que gira** se despierta con el gestor (`net.bodies.wake`), no cambiando `sleeping`;
  - **la tabla por la ranura** se empuja hasta que pasa entera. Soltada con la punta agarrada todavía de este lado, volvía y quedaba apoyada en la ranura, tapando a la tabla cruzada en la parte siguiente.

**Resultados de la pasada final (con los arreglos de tu segunda prueba, Godot 4.7.2):**

| Prueba | Resultado |
| --- | --- |
| `inv_fisica_test` solo / tres procesos | **248 de 248** / **13, 12 y 8** |
| `inv_fisica_test`, la mano en dos procesos | Sin red y con internet mala: host **14** y cliente **31**, sin fallas |
| `inv_model_test` | **105 de 105** |
| `inv_lab_test` | **190 de 190** |
| `inv_alcance_test` / en pareja con +200 ms | **191 de 191** / **10 y 27** |
| `inv_hitbox_test` / en pareja / rechazo por la huella | **92 de 92** / **9 y 7** / **2 y 2** |
| `inv_indicador_test` / en pareja | **164 de 164** / **8 y 8** (una falla suelta de tres pasadas, abajo) |
| `inv_pair_test` (tres procesos, A con corte) | **18, 24 y 7** |
| `inv_instant_test` (usar sin esperar, +120 ms) | **1 y 83** |
| `inv_abrir_caja_test` / `inv_partes_test` | **85 y 80** / **1 y 29** |
| `inv_visual_test` (con ventana) | **12 de 12**, capturas miradas (a la mañana; después no se volvió a correr) |
| `estados_test`, `integridad_test`, `selector_test` | **129**, **113**, **50** |
| Repetición, mantle, agarre por encima del filo | Con la tolerancia nueva de Jolt: la repetición coincide byte a byte (`38989aaf9fd19d18`, la misma de antes); **50 casos**; **22 de 22** |
| El panel Objetos en una copia | **256 de 256** y **39 de 39** (a la mañana; el panel no cambió después) |

**Las pruebas nuevas de la tarde, con el código de antes de los arreglos**, en una copia del proyecto: fallaban las cuatro.

- El machete apretado quedaba 11,1 mm adentro.
- La caja metida no se movía (0,00 m).
- Soltados de 1 m, hasta 18,7 mm adentro.
- En el cliente, la caja soltada se veía 72,7 mm debajo del piso sin red simulada, y 691 mm con internet mala.

**Las pruebas nuevas de tu segunda prueba, con el comportamiento de antes** (en la copia, con esos cambios apagados): fallaban todas.

- «No se ve», jugando solo: a los 30 ticks, con **Hold Hidden Time** en 0 y en 0,25 s.
- En red, con la pared solo en el cliente: a los 60 ticks la seguía sosteniendo.
- Soltar con el cuerpo mirando para atrás: salía justo para atrás de la cámara, y el host lo dejaba sin girar.
- La torre, sin red simulada: lo que sacaba el host se dejaba de ver 7,1 ticks antes de la caída, y lo que recogía el invitado, 9,9 ticks antes.

**Una falla suelta:** `inv_indicador_test` en pareja falló una vez de tres en el cliente («hasta entonces la marcó sin cortes»: 81 ticks sin marcar la llave antes de que el host la recogiera). Las otras dos pasaron 8 y 8. Esa prueba no recoge ni suelta nada del cliente antes de esa comprobación, y no encontré relación con lo que cambió.

El barrido de bordes (7 min) no se corrió: no usa nada de lo que cambió. Los avisos del depurador no se pueden ver sin el editor: se arreglaron las 7 líneas de tu captura, y falta mirarlo en el panel **Debugger** (sección 1).


**Para correrlas** (Claude): `--headless --fixed-fps 60 --path . --scene res://scenes/net_lab/inventario/pruebas/inv_fisica_test.tscn` (con `--fisica-detalle` escribe cada comprobación; con `--fisica-solo=SECCIÓN`, solo esa, por ejemplo `_bodies_prepared`, `_hitbox_rules` o `_stack_wake`). Tres procesos, en tiempo real: el host con `-- --host --bind=127.0.0.1 --port=7891 --test-spawn-at=37,2 --fisica-pair=host`; A con `-- --client --address=127.0.0.1 --port=7891 --sim-rtt=200 --sim-jitter=40 --sim-loss=5 --fisica-pair=a`; y B, unos 28 s después, con `-- --client --address=127.0.0.1 --port=7891 --fisica-pair=b`. La mano, dos procesos: el host con `-- --host --bind=127.0.0.1 --port=7893 --test-spawn-at=37,2 --fisica-pair=mano_host` y el cliente con `-- --client --address=127.0.0.1 --port=7893 --fisica-pair=mano_cliente` (y `--sim-rtt=200 --sim-jitter=40 --sim-loss=5`, la internet mala).

---

## 15. Límites reales

- **Lo de los demás se ve atrasado:** lo que sostiene otro jugador va con la demora de la interpolación (unos 0,1 s más la mitad de la ida y vuelta), como los otros jugadores.
- **Con inputs que se pierden** (internet mala), lo que ve el que sostiene sigue bien, pero la copia del host, la que ven los demás, puede quedar corrida hasta que llegan sus afirmaciones: en una prueba con 5 % de pérdida, hasta 1 m durante un momento. Si no llegan en medio segundo, el host sube la versión y el que sostiene se corrige (en esa prueba, 4 veces, con 6 mm como mucho).
- **Contra otros objetos que se mueven** (empujar una caja suelta, chocar con lo que sostiene otro), tu PC no los tiene como cuerpos: el host rechaza lo que afirmás en esos ticks y tu PC se corrige con lo suyo, con una ida y vuelta de demora. No hay latencia cero ni ausencia de correcciones con otros cuerpos que se mueven.
- **Al agarrar con mucha demora,** tu PC lo empieza a mover enseguida y el host lo adopta en su primer tick si está a menos de 35 cm. Con más demora que eso, se corrige.
- **La mano sigue siendo blanda a propósito:** girando a 360 °/s, lo sostenido va 13° atrás, en las dos máquinas. Se endurece con **Hold Follow Time** y los límites del Tuning: es un ajuste de cómo se siente, para cuando lo pruebes.
- **Lo plano va con una caja:** la llave y el machete tapan sus entrantes. Jolt dejaba metidas en el piso sus formas convexas.
- **La descomposición en varias formas** es aproximada (en pasos de vóxeles): en lo chico recorta bordes. Ningún objeto del catálogo la usa. Para algo con un hueco que importe, se elige a mano en el panel y se revisa en la vista previa.
- **Jolt deja meterse un poco** lo que se apoya o se empuja: hasta su tolerancia de penetración, y debajo de eso no lo corrige. A la mañana del 2026-11-15 escribí acá que bajarla cambiaría toda la física del proyecto y que no lo hacía. Tu prueba mostró que la de fábrica (2 cm) era la causa de tres de los cuatro errores, y a la tarde la bajé a 2 mm (sección 17). Apretando una pila con la mano, el de abajo todavía llega a unos 9 o 10 mm mientras se aprieta, y vuelve a 2 mm al soltar.
- **«No se ve» mira un solo punto,** el agarrado (sección 17). Una tabla agarrada por una punta que ves se sigue moviendo con el resto detrás de un muro. Desde tu segunda prueba suelta en el acto, así que una reja o un poste fino que pase justo por delante del punto agarrado también la suelta, aunque sea un instante. Si molesta, se le da un poco de tiempo con **Hold Hidden Time**.
- **Lo que recogés debajo de otra cosa tarda en desaparecer** (lo elegiste vos, sección 18): lo que dura en llegar la caída del host. Medido en esta PC, 0,22 s sin red simulada y 0,44 s con internet mala. Lo que no tiene nada encima ni pegado desaparece en el acto.
- **Lo demás que hace el host se sigue viendo 0,1 s en el pasado,** más la mitad de la ida y vuelta: es lo que hace que se mueva parejo. Desde tu segunda prueba, lo que sale del mundo también, así que no queda nada en el aire, pero el atraso no desaparece.
- **Todos pesan lo mismo y salen igual de lanzados.** No es un sistema de peso.
- **Muchos cuerpos cuestan aunque duerman** (sección 13).
- **La historia del host es de un segundo:** un pedido con más demora valida contra las poses de ahora.
- **Lo que se cae del mapa** vuelve a donde reposó por última vez, no a su marcador.
- **Los arreglos de tu segunda prueba, sin probar con el mouse de verdad ni en las dos PC** (lo de esta PC son procesos en la misma máquina, con la red simulada), ni con el `.exe` exportado.

---

## 16. Archivos

**Nuevos el 2026-11-15:**

| Archivo | Qué es |
| --- | --- |
| `scripts/inventory/inv_hold_motion.gd` | Las cuentas de la mano, las mismas en el host y en tu PC: adónde va, las velocidades, el paso sin choques, mirar el nivel antes del paso, cuantizar, la afirmación que viaja |
| `addons/inventario_objetos/preparar_cuerpos.gd` | Prepara el cuerpo físico de todos los del catálogo (sección 7). Se corre con Godot sin ventana y el proyecto cerrado |

**Cambiados el 2026-11-15:**

- **El cuerpo y la selección:**
  - `inv_item_physics.gd` (sin el generador de tajadas; las formas guardadas, la generación con Godot, lo que conviene a cada tipo, el centro de masa, las formas achicadas);
  - `inv_body_shape.gd` (las formas del modelo guardadas, cómo se arman y de qué salieron);
  - `inv_reach.gd` (la hitbox como selección principal, el acceso, el punto del modelo más cercano y los rayos contra cajas, esferas, cilindros, cápsulas y formas convexas);
  - `inv_pickup_hitbox.gd` e `inv_item_def.gd` (sus comentarios).
- **La mano y la red:**
  - `inv_bodies.gd` (la mano antes del paso de Jolt, la adopción, las versiones, el soltar que espera, el despertar, el rescate y las poses con su tick verdadero y la versión);
  - `inv_hands.gd` (la predicción, la corrección y lo soltado adelantado);
  - `inv_world_item.gd` (el centro de masa, y sin gravedad ni freno mientras se sostiene, avisando sus choques);
  - `inv_authority.gd` (soltar y lanzar que esperan su tick; despertar antes de sacar del índice; el alcance para el acceso);
  - `inv_protocol.gd` (versión 3);
  - `inv_net.gd` (comentarios);
  - `scripts/actor/actor_input.gd` (la afirmación de lo sostenido);
  - `scripts/net/net_sync.gd` (`held_claim_for`);
  - `scenes/net_lab/net_lab.gd` (predecir antes de mandar el input, F2 apaga las dos adopciones, el panel y los resúmenes).
- **El panel:** `formulario_item.gd` (el apartado **Cuerpo físico** nuevo y los textos de la hitbox), `objetos_panel.gd` (prepara el cuerpo al guardar) y `guardado.gd` (un comentario).
- **Los objetos:** los 19 `.tres` de `scenes/net_lab/inventario/objetos/`, con su cuerpo preparado.
- **Las pruebas:** `inv_fisica_test.gd`, `inv_hitbox_test.gd`, `inv_alcance_test.gd`, `inv_model_test.gd`, `inv_lab_test.gd` (el motivo en un mensaje), `prueba_del_creador.gd` y `prueba_del_creador_juego.gd`.

**Cambiados la tarde del 2026-11-15** (los arreglos de tu prueba, sección 17):

- `project.godot`: la tolerancia de penetración de Jolt, 2 mm.
- `inv_item_physics.gd`: `depth`, cuánto está metido un objeto.
- `inv_hold_motion.gd`: `path_free` deja salir o arrastrarse lo que ya arranca metido, y `guard` ya no tiene su propia salida de 2 cm.
- `inv_hands.gd`: lo soltado cae con `guard`.
- `inv_bodies.gd`: «no se ve», el rescate con `depth` y dos avisos.
- `inv_reach.gd`: `held_visible` y cinco avisos.
- `inv_authority.gd`: un comentario.
- `inv_fisica_test.gd`: `_sunk_and_pressed`, `_hidden_release`, las caídas de 1 m y la caída vista desde el cliente.

**Cambiados después de tu segunda prueba** (sección 18):

- `scripts/actor/actor_tuning.gd`: **Hold Hidden Time**.
- `inv_hands.gd`: «no se ve» en tu PC (`_check_hidden`).
- `inv_bodies.gd`: «no se ve» del host con **Hold Hidden Time** para su jugador y el respaldo para los clientes; dejar de dibujar en el tick en que salió (`_waits_for_fall`, `_has_neighbors`, `_free_view`); lo que se despierta, quieto hasta su tick (`add_sample`).
- `inv_authority.gd`: el tick en que sale cada objeto (`"wrt"`), el lugar de respaldo hacia la cámara y el giro de lo que soltás.
- `inv_replica.gd`: `gone_ticks`.
- `inv_net.gd` e `inv_ui.gd`: soltar hacia la cámara (`drop_yaw`).
- `inv_fisica_test.gd`: `_hidden_release` con los dos tiempos, `_drop_toward_camera`, y las partes 5 a 7 de la mano en red.

**Nuevos el 2026-11-14** (la primera versión): `inv_bodies.gd`, `inv_hands.gd`, `inv_hand_prefs.gd`, `inv_item_physics.gd`, `inv_body_shape.gd`, `inv_item_space.gd`, `inv_spatial_index.gd`, `scenes/net_lab/hud/lab_options.gd`, `zona_de_fisica.tscn`, `tabla_larga.tres` e `inv_fisica_test`.

---

## 17. Tu prueba en las notebooks (la tarde del 2026-11-15)

Tus notas están en `kavi.txt`, con capturas, un video y los 7 avisos del depurador. **Las dos mallas** (la de agarre y la física) **funcionan como deben**, según tu prueba. Encontraste cuatro errores. Tres tenían la misma causa: Jolt dejaba los objetos hasta 2 cm adentro del piso. Todo está arreglado, sin commit, y falta tu prueba (sección 1, «Los arreglos de tu prueba en las notebooks»).

### La causa común: Jolt dejaba hasta 2 cm adentro

Jolt no corrige lo que una cosa se mete en otra mientras sea menos que su **tolerancia de penetración**, que de fábrica es **2 cm**. Un objeto que cae de más de unos 20 cm se mete un poco al chocar con el piso, y Jolt solo lo saca hasta dejarlo a 2 cm. Así queda.

Medido en esta PC con los 19 objetos del catálogo, soltados derechos e inclinados de 10 cm, 50 cm, 1 m y 2 m: **49 de 152** caídas quedaban más de 5 mm adentro, hasta 2 cm (la caja de herramientas, de 2 m). Con la tolerancia en **2 mm**, **0 de 152**. Todos se siguen durmiendo.

El cambio es una línea de `project.godot`: `jolt_physics_3d/simulation/penetration_slop=0.002`. Vale para toda la física del proyecto. La repetición del personaje dio la misma huella byte a byte (`38989aaf9fd19d18`), y el mantle, el agarre por encima del filo, los estados y la integridad pasan igual. Lo eligió Claude. Para volver a la de fábrica, se borra esa línea.

### 1. «Bajo ciertas circunstancias, los objetos no pueden ser movidos»

- **La causa:** la mano no deja que lo sostenido se meta en el nivel. Mira cada paso con las formas achicadas 5 mm, así lo que solo está apoyado no cuenta. Un objeto que Jolt había dejado 1 o 2 cm adentro arrancaba «metido», y la regla de entonces solo le dejaba dar un paso de 2 cm que lo sacara entero. La mano pide más que eso por tick, así que no lo movía, y a medio segundo se soltaba («se trabó»). Lanzarlo funcionaba casi siempre porque el impulso lo da Jolt, sin esa regla, y guardarlo lo saca del mundo.
- **El arreglo:**
  - la tolerancia de Jolt en 2 mm, para que no quede metido;
  - y, si igual queda metido (por ejemplo, apretado por una pila), `InvHoldMotion.path_free` lo deja **salir o arrastrarse mientras no se meta más hondo que al empezar** (con 1 mm de margen por cada paso de 1 cm, `DEPTH_SLACK`). Una vez afuera, no vuelve a meterse. Es la misma regla en el host, en tu PC y en lo que el host le valida a tu PC.
- **Medido:** la caja de herramientas puesta 1,6 cm adentro del piso.
  - **Antes:** agarrada, se movía 0,00 m.
  - **Ahora:** Jolt la sube sola hasta 1,2 cm al empezar. Agarrada, se mueve 43 cm, sale del todo (0 mm) y nunca queda más metida que al empezar.

### 2. «El objeto de más abajo de una pila atraviesa el piso» (el machete)

- **La causa:** la misma tolerancia. El machete mide 2,3 cm de grueso, así que Jolt lo dejaba meterse casi entero sin corregirlo. Una pila sola lo hundía poco (3 mm). Apretar la pila con la mano, que empuja hasta 12 m/s, lo hundía mucho más, y así quedaba.
- **El arreglo:** la tolerancia en 2 mm.
- **Medido:** el machete debajo de dos botiquines y la caja de herramientas, apretados 2 s para abajo con la mano:

  | | Mientras se aprieta | Al reposar |
  | --- | --- | --- |
  | Antes | 18,1 mm | 11,1 mm |
  | Ahora | 8,6 a 10,4 mm (según la corrida) | 1,7 mm |

### 3. «Detrás de un muro se lo puede seguir moviendo, como si el muro no existiera»

**Lo decidiste vos:** se suelta. Abajo está el mecanismo.

### 4. «En la notebook, lo soltado de más de 0,5 m se mete en el piso unos 800 ms; con un perfil de latencia, desaparece»

- **La causa:** en tu PC, lo que soltás sigue adelantado. Cae predicho desde tu mano, y las poses del host lo corrigen. Al llegar al piso, la pose del host lo traía unos milímetros metido (por la tolerancia de Jolt). La caída predicha tenía una regla mal hecha: si arrancaba metido, lo dejaba caer sin mirar el piso. Seguía cayendo a través del piso hasta que el host lo dormía, unos 0,8 s, y entonces volvía a su lugar. Con internet mala, cada pose del host que llegaba lo ponía al día cayendo hasta medio segundo de golpe, y se iba bajo el piso (lo que viste como «desaparece»). Era un error mío de la mañana; las pruebas no soltaban nada desde alto en el cliente.
- **El arreglo:** cada tick de esa caída usa el mismo paso que la mano (`InvHoldMotion.guard`). Contra el piso se queda, contra una pared se desliza y, si viene un poco metido, no se hunde más.
- **Medido:** la caja de herramientas soltada de 2,16 m, con el host y el cliente en procesos distintos en esta PC. Lo más que se vio metida en el piso en el cliente:

  | | Sin red simulada | Internet mala |
  | --- | --- | --- |
  | Antes | 72,7 mm | 691 mm |
  | Ahora | 3,9 mm | 4,0 mm |

### Los 7 avisos del depurador

| Dónde | Aviso | Arreglo |
| --- | --- | --- |
| `inv_bodies.gd`, al despertar a los vecinos | Una variable `view` con el nombre de una función | Se llama `near_body` |
| `inv_bodies.gd`, el mensaje del rescate | Los dos lados del `if … else` de distinto tipo | `str(...)` |
| `inv_reach.gd`, la caja de cada triángulo (5) | Divisiones enteras (`i / 3 * 2`) | Cada caja va en el lugar del primer punto de su triángulo: sin dividir |

Godot solo muestra estos avisos en el editor: no los pude ver en las pruebas sin ventana. Falta mirarlo en el panel **Debugger** (sección 1).

### El mecanismo de «no se ve»: lo que tapa una pared se suelta solo

**Quién decidió qué:**

- **Vos**, el 2026-11-15 a la tarde, después de tu prueba: que se suelte. Elegiste la opción que te recomendé y pediste el mecanismo por escrito.
- **Vos, en tu segunda prueba:** que no era instantáneo y que dependía del host (con alta latencia tardaba más).
- **Claude** eligió los detalles: mirar el punto agarrado, cortar el rayo 1 cm antes y, a la tarde, usar el mismo tiempo que «se trabó». Después de tu segunda prueba: que lo decida la máquina del que sostiene, en el primer tick tapado (**Hold Hidden Time** en 0), y que el host lo suelte igual a los **Hold Break Time** si esa máquina no lo hizo.

**Qué hace:** si el nivel corta la línea entre tus ojos y el punto por donde agarraste el objeto durante más de **Hold Hidden Time** (de fábrica, 0: en el primer tick tapado; en el nodo **Tuning**, grupo **Objetos sueltos**), se suelta. Se suelta sin impulso, cae como cualquier objeto soltado y tu pantalla dice «Se te soltó: no se ve».

**Quién lo suelta** (desde tu segunda prueba; hasta entonces lo soltaba siempre el host, a los **Hold Break Time**, y en tu PC se sumaba la ida y vuelta):

- **Lo que sostiene el jugador del host:** el host, en cada tick, en `InvBodies._carry`, al lado de «se trabó» y «quedó muy lejos».
- **Lo que sostiene un cliente:** su propia máquina, en cada tick que predice, en `InvHands._check_hidden`. Lo suelta como con el botón: le pide al host que lo suelte después del último tick en que lo sostuvo, y lo soltado sigue cayendo desde la mano, sin esperar la respuesta. El host lo suelta como cualquier soltar pedido.
- **El respaldo del host:** con lo que sostiene un cliente, el host mira lo mismo y, si lo ve tapado más de **Hold Break Time** (0,5 s) y la máquina del cliente no lo soltó, lo suelta él y le avisa «no se ve». Es para cuando el cliente no lo ve tapado y el host sí (lo predicho y lo del host difieren un poco) o cuando el cliente dejó de mandar.

**Cómo mira**, igual en el host y en tu PC:

1. **Los ojos:** los de tu personaje en ese tick (`InvAuthority.eyes`), los mismos con que la mano calcula adónde llevar el objeto. No es la cámara: en tercera persona cuenta lo que ve el personaje.
2. **El punto:** el punto del modelo más cercano al punto agarrado (`InvReach.closest_model_point`). Normalmente es el punto agarrado mismo. Si lo agarraste por la hitbox en un hueco del modelo, es el borde del modelo más cercano. En tu PC, con lo predicho para ese tick; en el host, con la pose de después del tick anterior.
3. **La línea:** un rayo de los ojos a ese punto que termina 1 cm antes de llegar (`InvReach.ACCESS_TOUCH`). Choca con el nivel, las cajas y las escaleras (capas 1 y 3, `InvAuthority.WORLD_MASK`). No choca con los personajes ni con los demás objetos sueltos: un compañero o un objeto delante no lo sueltan. El centímetro de margen es para que un objeto apretado contra una pared de tu lado siga contando como visto.
4. **El tiempo:** cada tick tapado suma su tiempo, el del mundo (con cámara lenta corre más lento). Un tick en que se ve lo vuelve a cero. Pasado **Hold Hidden Time**, se suelta. Medido: con 0, en el primer tick tapado, en el host y en el cliente; con 0,25 s, a los 15 ticks.

Es **la misma mirada que la regla de acceso de la hitbox** (sección 8): `InvReach.held_visible` usa `InvReach.access_point` sin límite de distancia. Lo que no se puede agarrar porque una pared lo tapa tampoco se puede seguir sosteniendo tapado.

**Qué no hace:**

- **No mira el objeto entero**, solo el punto agarrado. La tabla agarrada por una punta que ves no se suelta aunque el resto quede detrás de un muro; agarrada por la punta que queda detrás, sí.
- **No distingue una reja o un poste fino:** en el acto, si pasa justo por delante del punto agarrado, también lo suelta. Para darle un margen, **Hold Hidden Time**.

**Para cambiarlo:**

- **El tiempo** es **Hold Hidden Time**, en el Tuning. El respaldo del host usa **Hold Break Time**, el de «se trabó» (o **Hold Hidden Time**, si es más largo).
- **El margen** es `InvReach.ACCESS_TOUCH`. Lo comparte con el acceso de la hitbox.
- **Qué tapa** es `InvAuthority.WORLD_MASK`.

**Probado** (`inv_fisica_test`):

- la regla con la tabla y una pared delante de una punta: agarrada por la otra se ve, por la tapada no (`_hidden_release`);
- jugando solo, la caja sostenida 1,4 m adelante, con una pared que aparece entre los ojos y ella: con **Hold Hidden Time** en 0 se suelta en el primer tick, y en 0,25 s, a los 15 ticks; siempre con «no se ve» (`_hidden_release`);
- en red, con la pared solo en la máquina del cliente: el cliente la suelta en el primer tick y el host nunca la vio tapada; con la pared solo en el host: el host la suelta a los 30 ticks (**Hold Break Time**) y el cliente recibe «no se ve» (la mano en red, partes 5 y 6). Sin red simulada y con internet mala;
- empujar contra la pared fina de tu lado sigue diciendo «se trabó» (`_limits`);
- en red, la mano sostiene la caja contra la pared fina 150 ticks, girándola, sin soltarse.

**Falta** probarlo con el mouse y en las dos PC.

---

## 18. Tu segunda prueba en las notebooks (2026-11-15)

Reemplazaste las notas de `kavi.txt` por las nuevas y grabaste un video de 22 s en la notebook (el invitado, con internet mala). Lo de la sección 17 quedó bien: **nada atraviesa el piso ni queda trabado**. Quedaban tres problemas. Están arreglados, sin commit, y falta tu prueba (sección 1, «Los arreglos de tu segunda prueba»).

### 1. «Soltarlo automáticamente no es instantáneo [...] es dependiente del host»

- **La causa:** como lo hice a la tarde, lo soltaba siempre el host, cuando lo veía tapado más de **Hold Break Time** (0,5 s). A tu PC el aviso le llegaba media ida y vuelta después: con internet mala (200 ms de ida y vuelta), unos 0,6 s en total. Esto último es una cuenta, no una medición.
- **El arreglo:** lo decide la máquina del que sostiene, en el primer tick tapado (**Hold Hidden Time** en 0, en el Tuning). Para un cliente, es su propia máquina, que lo suelta como con el botón. El host solo lo suelta por su cuenta si a los **Hold Break Time** sigue tapado y esa máquina no lo hizo. El mecanismo entero está en la sección 17.
- **Medido:** jugando solo, la caja se suelta en el mismo tick en que aparece la pared; antes, a los 30. En red, con la pared solo en la máquina del cliente, el cliente la suelta en ese mismo tick y el host nunca la ve tapada, sin red simulada y con internet mala; antes, a los 60 ticks el cliente la seguía sosteniendo (esperaba al host, que no veía la pared).

### 2. «La cámara mira hacia adelante, pero [...] la cápsula mira hacia atrás. Esto afecta [...] a la hora de soltar objetos del inventario»

- **La cápsula:** que el cuerpo gire hacia donde camina, y no hacia la cámara, lo decidiste el 2026-10-10. Caminando para atrás con **S**, el muñeco queda mirando hacia la cámara, y eso ve el invitado. No lo cambié. Cuando haya armas, el modo de apuntar es el que hace que el cuerpo mire hacia la cámara.
- **La causa del problema:** soltar buscaba el lugar hacia donde mira el cuerpo (`facing_yaw`). Con el cuerpo mirando para atrás, lo soltado salía entre el muñeco y la cámara.
- **El arreglo:** sale hacia donde mira la cámara, con el yaw de la cámara del último input propio (`InvNet.drop_yaw`). El host usa el mismo, el de tu último input, cuando no le sirve el lugar que propuso tu máquina.
- **Otro error, encontrado al probarlo:** tu máquina mostraba lo soltado girado como el cuerpo, y el host lo ponía derecho, sin girar, porque no usaba el giro que viajaba en el pedido. Al confirmarse, el objeto cambiaba de giro de golpe. Ahora el host lo deja como lo mostró tu máquina.
- **Medido:** con el cuerpo mirando para atrás de la cámara (cámara a 0,9 y a −2,2 rad), lo que muestra tu máquina, el lugar que busca el host y lo que deja el host salen justo adelante de la cámara y girados como ella. Antes salían justo para atrás de la cámara, y lo que dejaba el host quedaba sin girar (giro 0), aunque tu máquina lo mostrara girado.
- **Lo que sigue con el cuerpo:** en tercera persona, para recoger o agarrar, lo que mirás tiene que estar adelante del cuerpo, a no más de 75° (el cono, tu idea, `inventario_de_grilla.md`). Caminando para atrás, lo que está adelante de la cámara queda atrás del cuerpo: hay que dar un paso hacia ahí. Eso no lo toqué.

### 3. «Una pequeña latencia a la hora de actualizar los objetos» (la torre)

- **Lo que se ve en tu video:** con internet mala, en la notebook desaparece el banquito de abajo, y la caja roja y lo de arriba quedan en el aire 6 cuadros (0,2 s) antes de caer.
- **La causa:** en la máquina del invitado, todo lo que simula el host (los otros jugadores y los objetos) se dibuja unos 6 ticks (0,1 s) en el pasado, para que se mueva parejo aunque los paquetes lleguen a destiempo. La caída de lo de arriba llegaba con ese atraso, pero lo que el host sacaba del mundo se borraba apenas llegaba el aviso. Lo de arriba quedaba en el aire esos 0,1 s, más lo que tardara algún paquete. Si lo recogía el invitado con **E**, en su máquina se borraba en el acto, y la caída le llegaba recién después de la ida y vuelta entera. El host no lo ve nunca porque es el que simula: no espera nada.
- **El arreglo** (sección 10):
  - lo que saca el host se deja de ver en el tick en que salió, el mismo en que empieza la caída de lo de arriba;
  - lo que recoge el invitado con **E**, si algo se apoya en él o lo toca, desaparece junto con la caída (lo elegiste vos); si no, en el acto, como antes.
- **Otro error, encontrado al medirlo:** en el invitado, lo que se despertaba empezaba a moverse antes de tiempo, porque se interpolaba desde la última pose de cuando dormía: en la prueba, de 26 ticks antes (0,4 s); con muchos objetos dormidos, por cuenta, más de un segundo. Ahora sigue quieto hasta su tick.
- **Medido**, en esta PC, con el host y el invitado en procesos distintos. Cuánto después de que se deja de ver lo de abajo empieza a caer lo de arriba, en ticks de lo que muestra el invitado (1 tick son 16,7 ms; negativo es que cae antes):

  | | Antes, sin red simulada | Ahora, sin red simulada | Ahora, internet mala |
  | --- | --- | --- | --- |
  | Lo saca el host | 7,1 ticks | 1,2 ticks | 0,0 ticks |
  | Lo recoge el invitado con E | 9,9 ticks | 0,0 ticks | −0,8 ticks |

  Lo que recoge el invitado debajo de otra cosa desaparece a los 0,22 s de apretar **E** sin red simulada y a los 0,44 s con internet mala. Lo que no tiene nada encima, en el acto.
- **Lo que no cambia:** el invitado sigue viendo lo que hace el host 0,1 s en el pasado, más media ida y vuelta. Ahora lo ve todo junto, sin nada en el aire.
