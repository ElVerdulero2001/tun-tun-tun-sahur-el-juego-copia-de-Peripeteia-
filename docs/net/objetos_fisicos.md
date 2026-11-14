# Objetos sueltos con física

Hecho el 2026-11-14 a partir de [`prompt_claude_objetos_dinamicos.md`](prompt_claude_objetos_dinamicos.md). Desde ese día los objetos sueltos del inventario caen, chocan con el nivel y entre sí, reposan y se pueden **sostener** en el mundo: acercar, alejar, girar, soltar y lanzar. Sostener no es guardar: el objeto sigue en el mundo y no entra al inventario. Para guardarlo, **E**, como siempre.

**Sin commit** (el pedido decía no commitear ni subir por iniciativa propia). **Falta tu prueba** con el mouse de verdad y en las dos PC: la lista está en la sección 1.

---

## 0. Quién decidió qué

**Vos**, antes o durante el trabajo:

- Los objetos **no chocan con los personajes** (tus notas del 2026-10-31 y tu respuesta del 2026-11-14): se los atraviesa caminando y no se puede parar uno encima. Así el personaje, que tu PC adelanta, no se traba con algo que simula solo el host.
- Al lanzar, **todos salen con la misma fuerza** (tus notas del 2026-10-31).
- Lo sostenido **gira con vos**: si girás la cámara, el objeto gira con tu vista y conserva cómo lo tenías (respuesta del 2026-11-14).
- El panel **Opciones** se abre con **F3** y con un botón del menú del laboratorio (respuesta del 2026-11-14).

**El pedido** (`prompt_claude_objetos_dinamicos.md`): los dos esquemas de botones y los dos modos de sostener, independientes; de fábrica, botones principales y alternar; la rueda para arriba aleja y para abajo acerca; el botón central mantenido gira y Shift da el tercer eje; la rueda no hace zoom mientras sostenés; prioridad interfaz → mano → cámara; el host manda.

**Claude:** todos los números del Tuning (sección 4), dónde se guardan las preferencias, la forma automática del cuerpo físico, el índice de 1 m, 30 paquetes de poses por segundo, el segundo de historia del host, el cuarto de segundo para volver a lo del host al soltar, las capas y lo que pasa con lo que se cae del mapa. Todo se puede cambiar.

---

## 1. Cómo probarlo

### Dónde

La **Pista de física** está pegada a la zona de inventario, unos 12 m hacia el lado del cartel grande **PISTA DE FÍSICA** (se ve desde la zona). Tiene:

| Qué | Para qué |
| --- | --- |
| **Tabla larga** (1,6 m) derecha, y otra **cruzada** (su marcador está girado 90°) | Agarrarla por una punta, girarla y meterla a lo largo por la ranura. La cruzada muestra que un marcador girado deja el objeto girado |
| **Muro con ranura** (la ranura, 25 × 25 cm, entre 1,13 y 1,38 m del piso) | Meter la tabla a lo largo; cruzada, el muro la frena |
| **Pared fina** (2 cm de grosor, 2,5 m de alto y 4 m de largo) y una **granada** delante | Lanzar contra ella: rebota, no pasa |
| **Mesa** (1 m de alto) con tornillos, una llave y una granada en el borde | Caer de un borde; choque entre objetos |
| **Estante** (a 1,5 m) con una batería adelante, otra en el medio y un botiquín atrás, en fila | Lo de adelante tapa lo de atrás, en primera y en tercera persona |

### Solo, en esta PC (con el mouse)

1. Godot, pestaña **net_lab**, **F6** → **Jugar solo**. Andá a la pista.
2. Mirá la **tabla larga** por una punta y hacé **clic derecho**: queda agarrada por esa punta, sin saltar al centro. Mové la vista: la punta sigue a la mira.
3. **Rueda para arriba:** se aleja. **Para abajo:** se acerca. La cámara no hace zoom.
4. Mantené el **botón central** (la rueda apretada) y mové el mouse: la tabla gira y la cámara no. De costado gira alrededor del eje vertical de la vista; para arriba o para abajo, del horizontal; con **Shift** y de costado, como un volante. Soltá el central: volvés a mirar.
5. Ponela derecha, a lo largo, a la altura de la ranura, y metela caminando hacia el muro: pasa del otro lado. Cruzada, el muro la frena.
6. Otro **clic derecho:** la suelta y cae.
7. Agarrá la **granada** de delante de la pared fina y hacé **clic izquierdo:** sale lanzada hacia donde mirás, rebota en la pared y no la atraviesa.
8. Llevá algo contra una pared y seguí empujando: no la atraviesa y, trabado más de medio segundo, se suelta solo ("Se te soltó: se trabó").
9. Con algo agarrado, probá **Tab**, **F3**, la **Q**, **Esc** y **Alt+Tab** (cambiar de ventana): cada uno lo suelta sin lanzarlo, y al volver mirás normal, sin nada pegado.
10. **F3** → **Opciones**. En **Botones del mouse** elegí **Laterales**; en **Sostener**, **Mantener**. Abajo, en **Probá el mouse**, apretá cada botón lateral sobre el panel: el trasero (cerca de la palma) tiene que decir **8** y el delantero (cerca del cable), **9**. Cerrá con **F3**.
11. Ahora mantener el lateral trasero agarra y soltarlo suelta; el delantero lanza. Lanzar y después soltar el trasero no hace nada más, y no agarra otra cosa hasta otra pulsación.
12. Cerrá el juego y volvé a abrirlo: **F3** muestra lo que elegiste. Volvé a **Principales** y **Alternar** si querés.
13. Saltá (o colgate de un cable), abrí **Tab** y soltá algo de la grilla: aparece adelante, a la altura del pecho, y cae. Ya no hace falta piso cerca.
14. Con algo sostenido, **E**: lo guarda. Si no entra entero, lo que sobra sigue en tu mano.
15. Frente al **estante**, en primera y en tercera persona: solo se marca y se agarra lo de adelante.

### En las dos PC

1. **La huella cambió** (código, protocolo y física): en la notebook, `actualizar_lab.bat`.
2. Los dos miran la misma tabla y hacen clic derecho a la vez: la agarra uno solo; al otro le dice "No se agarró: …" y la deja de ver en su mano.
3. Uno sostiene algo y lo mueve: el otro lo ve moverse (con la demora de la red). El otro aprieta **E** sobre eso: no se lo quita.
4. Con **Alt + 4** (internet mala): agarrar y soltar enseguida, antes de que conteste el host, queda suelto en los dos; lanzar da un solo lanzamiento.
5. El que sostiene algo cierra el juego (o muere con la cápsula letal): para el otro, el objeto se suelta y cae.
6. La notebook cierra y vuelve a entrar mientras el host sostiene algo y otra cosa cae: ve lo que cae, lo girado, lo dormido y lo sostenido, cada uno en su lugar.

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
| **Hold Break Distance** y **Hold Break Time** | 0,8 m y 0,5 s | Trabado más lejos que esto de donde lo lleva la mano durante ese tiempo, se suelta solo. También si queda más lejos de los ojos que **Hold Max Distance** más esto |
| **Hold Wheel Step** | 0,1 m | Cuánto mueve cada paso de la rueda |
| **Hold Wheel Inverted** | apagada | Prendida, la rueda para arriba acerca |
| **Hold Rotate Sensitivity** | 0,25 °/píxel | Cuánto gira con el botón central |

El súper (Kp 2) no cambia nada de esto: ningún valor termina en **Speed**.

---

## 5. Dónde está cada objeto: suelto, sostenido o en un inventario

Cada objeto está en uno solo de tres lugares (`InvAuthority`, en el host):

| Lugar | Cómo es |
| --- | --- |
| **Suelto en el mundo** | Con su cuerpo físico, cae, choca y reposa. Nadie lo sostiene |
| **Sostenido en el mundo** | Sigue en el mundo, con su cuerpo, y lo lleva la mano de un jugador. Un solo jugador por objeto y un objeto por jugador. No está en ningún inventario |
| **En un inventario** | En una grilla. Ya no está en el mundo ni tiene cuerpo |

Los cambios son pedidos al host, en el mismo orden que todo el inventario:

| Pedido | De → a | Qué mira el host |
| --- | --- | --- |
| **GRAB** (agarrar) | suelto → sostenido | Su propio rayo, desde tus ojos y con la dirección que mandaste, tiene que tocar ese objeto antes que otra cosa, al alcance (**Interaction Range**). El punto que toca es por donde se agarra (el de verdad, no el centro), y te lo devuelve para que tu PC use el mismo |
| **RELEASE** (soltar) | sostenido → suelto | Que lo sostengas vos, con esa sesión de agarre |
| **THROW** (lanzar) | sostenido → suelto | Lo mismo, y le suma un solo impulso |
| **PICKUP** (E) | suelto, o sostenido por vos → inventario | Suelto: el rayo, como siempre. Sostenido por vos: sin rayo (ya lo tenés en la mano). Lo que no entra queda en el mundo, con su lugar y, si lo sostenías, en tu mano. Sostenido por otro: no, nunca se le quita |
| **DROP** y **DROP_AT** (soltar desde el inventario) | inventario → suelto | Aparece adelante, a la altura del pecho (o alrededor, si ahí no cabe), con el giro del personaje, y cae. Tiene que verse desde el pecho (no del otro lado de una pared) y caber sin tocar el nivel, una caja, una escalera, un personaje ni otro objeto suelto |

**El host suelta solo** lo que se traba ("se trabó"), lo que queda lejos ("quedó muy lejos") y lo de un jugador que muere, se va, se desconecta o cambia de personaje.

**Las sesiones de agarre:** cada agarre lleva un número que pone tu PC, de a uno más. Soltar y lanzar lo nombran; lo que llega de una sesión vieja no hace nada. Así un paquete tardío no vuelve a agarrar algo soltado, no revive algo recogido y no lanza dos veces.

**Sostener no es llevar algo con el cursor dentro del inventario.** Eso es de la interfaz (`InvUI`) y no cambia nada en el host hasta que se deja.

---

## 6. Capas de física

| Capa | Qué hay | Los objetos sueltos chocan |
| --- | --- | --- |
| 1 | El nivel y las cajas | Sí |
| 2 | Los personajes | **No** (decidido por vos) |
| 3 | Las escaleras | Sí |
| 4 | Los objetos sueltos | Sí, entre ellos |

Para ver si algo cabe al soltarlo se miran el nivel, las cajas, los personajes y las escaleras con sus formas (no se suelta adentro de nadie), y los demás objetos sueltos por su caja, así la cuenta da lo mismo en el cliente, que no tiene los cuerpos. Los cuerpos tienen detección continua de choques (CCD): una granada a 120 m/s no atraviesa la pared de 2 cm. Del 2026-11-06 al 2026-11-11 la capa 4 era la de la forma invisible para apuntar, que ya no existe.

En un cliente, los objetos son copias **sin forma de choque**: solo el host los simula. Lo que sostenés vos se dibuja adelantado y no se mete en el nivel, las cajas ni las escaleras (sección 9).

---

## 7. El cuerpo físico de cada tipo

Son tres cosas distintas:

- **Lo que se ve:** el modelo.
- **Con qué se elige y se agarra:** los triángulos del modelo (el rayo de la mano, `InvReach`). Un hueco del modelo no se vuelve agarrable aunque el cuerpo lo tape.
- **Con qué choca:** el cuerpo físico (`InvItemPhysics`), una o varias formas convexas, armadas una vez por tipo y compartidas por todos los objetos de ese tipo.

**De fábrica, la forma automática:** el modelo se parte en tajadas a lo largo de un eje y, en cada tajada, cada pedazo que no se toca con los demás es una forma convexa. Una tabla larga son unas pocas cajas en fila; las patas de un banquito, una forma cada una; un marco, sus lados, sin tapar el hueco del medio. Elige sola cuántas tajadas (hasta 4) y qué eje. Como mucho 16 formas y 64 puntos por forma; un lado más finito que 4 mm se engorda hasta 4 mm.

**Los `.tres` de antes no necesitan nada:** sin cuerpo propio usan la automática.

**En el panel Objetos**, sección **Cuerpo físico**, debajo de **Hitbox de agarre**:

1. **Forma:** **Automática (del modelo)**, **Caja**, **Esfera**, **Cilindro** o **Forma propia (en el Inspector)**.
2. Con **Automática**: **Partes** (0: las elige sola; 1: una sola forma convexa, que tapa los huecos) y **Eje de las tajadas**.
3. Con caja, esfera o cilindro: arranca ajustada al modelo; después, sus medidas, **Ajustar al modelo**, **−1 cm** y **+1 cm**, el lugar y el giro, como en la hitbox de agarre.
4. En la **Vista previa** general se ve en **naranja**; la casilla **Ver el cuerpo físico** la oculta. Debajo de la sección dice cuántas formas tiene y cuánto ocupa, al lado del modelo.
5. **Guardar.** Va adentro del `.tres` (`InvItemDef.body_shape`, un `InvBodyShape`). **Duplicar** le da a la copia un cuerpo propio. Volver a **Automática** con todo en automático deja el ítem sin cuerpo propio, como los de antes.

Lo que no se guarda: las mismas medidas que la hitbox (0, negativas, de más de 10 m, que no son números) y más de 8 partes. El cuerpo entra en la huella: si las dos PC no lo tienen igual, la notebook no entra.

**Los marcadores (InvPickupSpawn)** ahora dejan el objeto con el giro del marcador, y la vista previa del editor lo muestra así. Los de antes, sin girar, quedan igual que siempre. La escala del marcador no cuenta (el cuerpo no se escala). El objeto arranca quieto y **dormido** donde está el marcador: no se mueve hasta que algo lo toca o alguien lo agarra. Un marcador en el aire lo deja flotando hasta entonces.

---

## 8. Qué instante usa cada uno

Los objetos ahora se mueven, así que importa de qué momento es cada cosa.

**Lo que ves en tu PC:**

- Los objetos (también los que sostiene otro) se ven en el mismo instante que los otros jugadores: el tick del host que tu PC muestra, unos 6 ticks (0,1 s) más la mitad de la ida y vuelta por detrás del host.
- Lo que sostenés vos se ve **adelantado**: donde lo pide tu mano ahora, corrido por la diferencia que el host tenía en el último tick que contó (si allá está trabado contra una pared, acá también). Al soltarlo vuelve en un cuarto de segundo a lo que manda el host.

**Lo que valida el host** al recoger, abrir o agarrar:

- **Tus ojos**, los del tick del input en que apretaste (auditoría del 2026-11-12, INT-01): tu personaje en su presente.
- **Los objetos**, donde estaban en el tick que tu PC mostraba al apretar (el pedido lo lleva, en centésimas de tick). El host guarda la pose de lo que se mueve en cada tick del último segundo.
- **No son el mismo instante del host, a propósito:** es lo que tenías en pantalla al apretar. Si el tick que mandás es de hace más de un segundo, o del futuro, el host usa las poses de ahora. El nivel y las cajas no se mueven: van como están.
- No hay un rollback del mundo: solo se vuelven atrás las poses para ese rayo.

**Mientras sostenés:** tu input lleva, en cada tick, la sesión, la distancia, el giro (relativo a tu vista) y la inclinación de la cámara. El host, al terminar cada tick, con los personajes ya movidos, lleva el punto agarrado a tus ojos más la dirección de la cámara por la distancia, con velocidad y aceleración acotadas (sección 4), sin gravedad mientras lo sostenés. Si un input se pierde, sigue con el último.

**La cámara lenta del mundo** frena a Jolt sola, como a todo (`Engine.time_scale`): no se escala nada aparte, así que no se aplica dos veces. Cuando un cliente repite ticks de su personaje, los objetos no se simulan ni se lanzan de nuevo: en el cliente no tienen física.

**Pausa** (G, solo jugando solo): los cuerpos se congelan donde están y al seguir recuperan su velocidad. Avanzar un tick (F) no los mueve.

---

## 9. Qué viaja por la red

| Qué | Cómo | Cuándo |
| --- | --- | --- |
| **GRAB, RELEASE, THROW** y todo lo del inventario | Pedidos confiables, en orden (`InvProtocol`, versión 2) | Al hacerlo |
| **Respuesta al agarre** | Confiable: el punto por donde se agarró, para que tu PC use el mismo | Al aceptarlo |
| **Se te soltó** (el host soltó solo) | Confiable, con el motivo | Al pasar |
| **Lo que entra, sale, se agarra o se suelta** | En los paquetes confiables del inventario, con su pose entera: lugar, giro, velocidades, si duerme, quién lo sostiene, su sesión y el tick | Al pasar, y entero al que entra tarde o vuelve de un corte |
| **Las poses de lo que se mueve** | Sin confiable, 37 bytes por objeto, hasta 32 por paquete | Cada 2 ticks (30 por segundo): lo que se movió, lo que se acaba de dormir (durante medio segundo, por si se pierde) y un dormido por vez, de a uno, para corregir cualquier diferencia |
| **La mano** (distancia, giro) | En el input de cada tick | Siempre que sostenés algo |

- **Con todo quieto,** en medio segundo (30 ticks) salen 15 poses, una por paquete (la ronda de los dormidos): 555 bytes. Medido con 0, 300 y 3000 objetos dormidos, da lo mismo.
- El cliente guarda hasta 24 poses por objeto, ordenadas por tick, e interpola entre las dos que rodean el instante que muestra. Más de 4 m entre dos seguidas es un salto: no se interpola.
- **Lo que se cae del mapa** (más abajo de −30 m) vuelve, quieto, a donde reposó por última vez.
- **La huella** suma la versión del protocolo, el cuerpo físico de cada tipo, los valores del Tuning y el giro de los marcadores.

---

## 10. El índice de los objetos y lo que cuesta

Hasta el 2026-11-14 el rayo de la mano revisaba **todos** los objetos sueltos del mapa en cada cuadro (la auditoría del 2026-11-12, REND-02, lo había medido y quedó sin aplicar). Ahora hay una grilla de celdas de 1 m (`InvSpatialIndex`): cada objeto se anota en las celdas que toca su caja (la del modelo y la del cuerpo, ya movida y girada), y el rayo recorre solo las celdas que cruza, en orden. Lo preciso, los triángulos, lo decide `InvReach` con esos pocos. Hay uno en el host (el de la autoridad, con la historia del último segundo) y uno en cada cliente (el de lo que se ve). Un objeto quieto no se toca.

**Medido en esta PC el 2026-11-14** (`inv_fisica_test`, el mismo grupo de objetos cerca y 0, 300 y 3000 objetos dormidos a 1 km):

| Objetos lejos | El selector (los dos rayos) | El rayo del host | Revisando todos (como antes) | Un cuadro entero del laboratorio |
| --- | --- | --- | --- | --- |
| 0 | 52 µs | 17 µs | 77 µs | 2,5 ms |
| 300 | 53 µs | 17 µs | 781 µs | 2,9 ms |
| 3000 | 55 µs | 17 µs | 8639 µs | 7,1 ms |

- El selector y el rayo del host no cambian con los objetos lejanos: miran 3 candidatos.
- **El cuadro entero sí sube** (de 2,5 a 7,1 ms con 3000 dormidos): es lo que cuesta Jolt con tantos cuerpos, aunque duerman. Con los objetos del laboratorio (unas pocas decenas) no se nota; con mapas grandes, conviene no tener miles de cuerpos a la vez (por ejemplo, armar solo los de la zona cercana).
- Al sacar los 3000 no queda nada en el índice, la historia ni los cuerpos (lo comprueba la prueba).

---

## 11. Pruebas

**Nueva: `scenes/net_lab/inventario/pruebas/inv_fisica_test.tscn`** (el laboratorio entero, con la pista de física):

- **Jugando solo: 141 de 141.** Lo colocado arranca dormido y en su lugar (también girado); las preferencias (de fábrica, guardar y leer); los dos esquemas con los dos modos (sin doble suelta ni doble lanzamiento, sin objeto no lanza, después de lanzar no agarra otra cosa); la rueda y el botón central sin cámara, con sus límites y los tres ejes; sin objeto, la rueda vuelve a la cámara; el inventario, Opciones, la Q y perder la ventana sueltan sin estados pegados; la tabla por la punta, sin salto al centro, girada alrededor de ese punto, metida a lo largo por la ranura, y cruzada contra el muro (la frena y se suelta sola); reposo, choque entre objetos, caída de la mesa; lanzada a 60 y a 120 m/s contra la pared de 2 cm, no la atraviesa; contra una pared empuja a no más de **Hold Move Limit** y se suelta sola; lejos y al morir, también; soltar en el aire, soltar una parte, E sobre lo sostenido (entero y en parte); un objeto que gira se elige por el punto que se ve; un hueco no es sólido; lo de adelante tapa lo de atrás, en primera y en tercera persona; la medición (sección 10).
- **Tres procesos en esta PC: host 13, A 12 y B 8, sin fallas.** A con +200 ms, ±40 ms y 5 % de pérdida: agarra por donde toca y lo mueve sin esperar al host; agarra y suelta antes de que conteste el host (queda suelto en los dos); el host y A piden el mismo a la vez (gana el host, A recibe el rechazo y deja de verlo en la mano); un solo impulso al lanzar; el host lo mata mientras sostiene (se suelta); B entra tarde y ve lo sostenido moviéndose, la tabla cruzada girada y dormida; A se va con algo en la mano y B lo ve soltarse y caer. Al final, el mundo del host y el de B, iguales.

**El panel Objetos** (`prueba_del_creador`, en una copia del proyecto): **247 de 247** (16 nuevas de **Cuerpo físico**: la sección debajo de la hitbox, la automática en la vista previa, la caja ajustada al modelo, ancho 0 rechazado, guardar y releer, que el juego choque con esa caja, duplicar, volver a automática, 1 parte = una sola forma) y jugando **38 de 38**. La prueba encontró que «1 parte» no daba una sola forma con un modelo de piezas sueltas (la varilla con su perilla); arreglado.

**Las de antes, adaptadas cuando lo pedido cambió una regla** (sin sacar protecciones):

- Soltar ya no busca piso: aparece en el aire y cae. Las pruebas esperan a que repose para mirar dónde quedó. En `inv_lab_test`, «cae en el piso» mira el punto más bajo del modelo, no su caja: la linterna acostada y algo girada sobre su eje tiene la caja girada 4 cm por debajo del piso.
- Las que cuentan objetos de la zona de inventario ignoran la pista de física (otras baterías, granadas, tornillos y una llave).

**Resultados de la pasada final (2026-11-14, Godot 4.7.2):**

| Prueba | Resultado |
| --- | --- |
| `inv_fisica_test` solo / tres procesos | **141 de 141** / **13, 12 y 8** |
| `inv_model_test` | **102 de 102** |
| `inv_lab_test` | **190 de 190** |
| `inv_alcance_test` / en pareja con +200 ms | **192 de 192** / **10 y 27** |
| `inv_hitbox_test` / en pareja | **90 de 90** / **9 y 7** |
| `inv_indicador_test` / en pareja | **164 de 164** / **8 y 8** |
| `inv_pair_test` (tres procesos, A con corte) | **18, 24 y 7** |
| `inv_instant_test` (usar sin esperar, +120 ms) | **1 y 83** |
| `inv_abrir_caja_test` / `inv_partes_test` | **85 y 80** / **1 y 29** |
| `inv_visual_test` (con ventana) | **12 de 12**, capturas revisadas |
| `estados_test`, `integridad_test`, `selector_test` | **129**, **113**, **50** |
| Repetición, mantle, agarre por encima del filo | La repetición coincide (`38989aaf9fd19d18`, la misma de antes); **50 casos**; **22 de 22** |
| El panel Objetos en una copia | **247 de 247** y **38 de 38** |

El barrido de bordes (7 min) no se corrió: no usa nada de lo que cambió. Todos los scripts cambiados cargan sin avisos.

**Para correrlas** (Claude): `--headless --fixed-fps 60 --path . --scene res://scenes/net_lab/inventario/pruebas/inv_fisica_test.tscn` (con `--fisica-detalle` escribe cada comprobación; con `--fisica-solo=SECCIÓN`, solo esa). Los tres procesos, en tiempo real: el host con `-- --host --bind=127.0.0.1 --port=7891 --test-spawn-at=37,2 --fisica-pair=host`; A con `-- --client --address=127.0.0.1 --port=7891 --sim-rtt=200 --sim-jitter=40 --sim-loss=5 --fisica-pair=a`; y B, unos 28 s después, con `-- --client --address=127.0.0.1 --port=7891 --fisica-pair=b`.

---

## 12. Límites reales

- **Con latencia, lo de los demás se ve atrasado:** lo que sostiene otro jugador va con la demora de la interpolación (unos 0,1 s más la mitad de la ida y vuelta). Lo tuyo se adelanta, pero **al agarrar con mucha demora** el objeto espera a que el host empiece a llevarlo (una ida y vuelta).
- **Lo que soltás desde el inventario** aparece enseguida a la altura del pecho, pero **cae cuando llegan las poses del host**: con +200 ms queda flotando un instante.
- **Lo tuyo adelantado** no se mete en el nivel, las cajas ni las escaleras, pero puede verse un instante adentro de otro objeto suelto hasta que llega lo del host: en tu PC los objetos no tienen forma de choque.
- **Los objetos no chocan con los personajes** (decidido por vos): se los atraviesa, no se puede parar uno encima y no empujan.
- **Todos pesan lo mismo y salen igual de lanzados.** No es un sistema de peso.
- **El cuerpo automático es aproximado:** formas convexas de hasta 64 puntos, hasta 16 por tipo. Un modelo con curvas reposa sobre caras planas; si algo se ve raro, se le pone un cuerpo propio en el panel.
- **Lanzada a 120 m/s**, la granada choca en el mismo paso en que sale: la velocidad que se mide ya es la del rebote. No atraviesa, pero esa prueba no mide que haya salido a 120.
- **Muchos cuerpos cuestan aunque duerman** (sección 10).
- **La historia del host es de un segundo:** un pedido con más demora valida contra las poses de ahora.
- **Lo que se cae del mapa** vuelve a donde reposó por última vez, no a su marcador.
- **Sin probar con el mouse de verdad ni en las dos PC:** Esc con el mouse capturado, Alt+Tab de verdad (la prueba simula la pérdida de foco con el aviso de la ventana), los laterales de tu G203 con G HUB, cómo se siente seguir la mira y los números del Tuning. Tampoco con el `.exe` exportado.

---

## 13. Archivos

**Nuevos:**

| Archivo | Qué es |
| --- | --- |
| `scripts/inventory/inv_bodies.gd` | Los cuerpos en el host, las copias en los clientes, las poses que viajan y lo sostenido (el nodo **ObjetosSueltos** de **Inventario**) |
| `scripts/inventory/inv_hands.gd` | La mano del jugador local: los botones, la rueda, el giro, lo adelantado |
| `scripts/inventory/inv_hand_prefs.gd` | Las preferencias de la mano y su archivo |
| `scripts/inventory/inv_item_physics.gd` | El cuerpo físico de cada tipo, armado una vez, y las capas |
| `scripts/inventory/inv_body_shape.gd` | El recurso del cuerpo propio de un tipo (`InvBodyShape`) |
| `scripts/inventory/inv_item_space.gd` | Los objetos como los ve el rayo, con su historia en el host |
| `scripts/inventory/inv_spatial_index.gd` | La grilla de celdas de 1 m |
| `scenes/net_lab/hud/lab_options.gd` | El panel **Opciones** (F3) |
| `scenes/net_lab/inventario/zona_de_fisica.tscn` | La pista de física, instanciada en la zona de inventario |
| `scenes/net_lab/inventario/objetos/tabla_larga.tres` | La tabla larga |
| `scenes/net_lab/inventario/pruebas/inv_fisica_test.gd` y `.tscn` | La prueba nueva |

**Cambiados:** `inv_world_item.gd` (el cuerpo, dormido al nacer, y la copia sin choque), `inv_authority.gd` (los tres lugares, GRAB, RELEASE, THROW, soltar sin piso, la validación con las poses vistas), `inv_replica.gd` e `inv_net.gd` (la réplica de las poses, las respuestas, el índice en el selector), `inv_protocol.gd` (versión 2, los pedidos nuevos y el tick de lo que se veía), `inv_reach.gd` (el rayo contra el índice, con poses de otro tick), `inv_item_def.gd` (**Body Shape**), `inv_pickup_spawn.gd` (el giro del marcador), `inv_ui.gd` (la mano y lo soltado), `scripts/actor/actor_input.gd` (la mano en el input), `actor_tuning.gd` (el grupo **Objetos sueltos**), `scripts/net/net_sync.gd`, `scenes/net_lab/net_lab.gd` (la mano, Opciones, F3 y la huella), `project.godot` (8 acciones: `objeto_agarrar`, `objeto_lanzar`, `objeto_agarrar_lateral`, `objeto_lanzar_lateral`, `objeto_rotar`, `objeto_alejar`, `objeto_acercar` y `opciones`), `catalogo_de_prueba.tres` (la tabla), `zona_de_inventario.tscn` (la pista), el panel Objetos (`formulario_item.gd`, `vista_previa.gd`, `guardado.gd`, `objetos_panel.gd`) y las pruebas que cambiaron por las reglas nuevas.
