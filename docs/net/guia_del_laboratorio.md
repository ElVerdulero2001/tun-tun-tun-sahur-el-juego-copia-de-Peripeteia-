# Guía del laboratorio de red

Esta guía es para retomar el laboratorio después de un tiempo sin tener que leer todo el historial. Está armada por tareas: dónde está cada cosa, cómo probar, cómo agregar cables y escaleras, qué reglas acordamos y en qué sección del historial está el detalle.

- **El historial completo**, con cada decisión, prueba y error, en orden: [`arquitectura_coop_y_esqueleto_de_red.md`](arquitectura_coop_y_esqueleto_de_red.md).
- **El diseño de la arquitectura:** [Arquitectura de movimiento co-op (Godot 4.7 + Jolt)](https://claude.ai/code/artifact/6760c3bf-39ed-4f2f-8d9d-23642c7ac797), en Claude Docs. Está copiado en el Apéndice A del historial.

**Para pedirle algo a Claude en otra conversación:** "leé `docs/net/guia_del_laboratorio.md` y ayudame a …". Si hace falta más detalle, la sección 8 de esta guía dice en qué parte del historial buscarlo.

Escrita el 2026-10-15. Si algo de acá no coincide con el código, manda el código, y hay que corregir la guía.

---

## 1. Dónde está cada cosa

Todo el laboratorio está en la rama `net-lab` y en estas carpetas. El resto del proyecto, el juego, no se toca.

| Qué | Dónde |
| --- | --- |
| La escena del laboratorio, con el menú y el panel | `scenes/net_lab/net_lab.tscn` (y su script, `net_lab.gd`) |
| Los valores de movimiento (el nodo **Tuning**) | Adentro de `net_lab.tscn`, nodo **Tuning** (script `scripts/actor/actor_tuning.gd`) |
| El nivel: piso, plataformas, pistas, torre, cables, escaleras | `scenes/net_lab/net_lab_level.tscn` |
| El personaje (la cápsula) | `scenes/actor/actor.tscn` |
| Cómo se mueve el personaje (todos los modos) | `scripts/actor/actor_motor.gd` |
| El estado del personaje, lo que viaja por red | `scripts/actor/actor_state.gd` y `actor_input.gd` |
| El cable | `scripts/actor/cable.gd` (nodo **Cable**) |
| La escalera | `scripts/actor/ladder.gd` (nodo **Ladder**) |
| Las plataformas que se mueven y la balsa | `scripts/actor/scripted_platform.gd` y `host_raft.gd` |
| La red: conexión, reloj, predicción, adopción | `scripts/net/` |
| Las pistas armadas por código (bordes, escalones, torre, pista de cables) | `scenes/net_lab/edge_course.gd`, `step_course.gd`, `parkour_tower.gd`, `cable_course.gd` |
| La cámara | `scenes/net_lab/lab_camera.gd`; sus valores, en el nodo **CameraRig** de `net_lab.tscn` |
| El doble clic de la notebook | `tools/net_lab/actualizar_lab.bat` y `.ps1` |
| Los modelos de escaleras | `assets/models/stairs/` |
| Las dos pruebas automáticas que están en el proyecto | `scenes/net_lab/actor_replay_test.tscn` (repetición) y `hang_sweep_test.tscn` (barrido de bordes) |

---

## 2. Cómo probar

### Solo, en esta PC

1. Abrí Godot.
2. Arriba del visor, en las pestañas, elegí **net_lab** (`net_lab.tscn`). Si no está, abrilo con doble clic en **FileSystem** → `scenes` → `net_lab` → `net_lab.tscn`.
3. Apretá **F6**. Aparece el menú del laboratorio.
4. Tocá **Jugar solo**.

**Ojo:** F6 corre la pestaña que está adelante. Si está adelante `net_lab_level`, corre el nivel solo y se ve una pantalla gris.

### En las dos PC

1. **En esta PC:** guardá todo (**Ctrl+S**), pestaña **net_lab**, **F6** y **Crear partida**. Arriba aparece la IP de esta PC; hasta ahora fue `192.168.1.212`.
2. **En la notebook:** cerrá Godot y hacé doble clic en `actualizar_lab.bat`, en el Escritorio. Trae los cambios de esta PC y abre Godot con el laboratorio. Desde el 2026-10-16 deja la copia de la notebook en 1280 × 720, porque los 1600 × 900 de esta PC no entran en su pantalla; esta PC no se toca. Para otra resolución, se cambian `$Ancho` y `$Alto` al principio de `tools/net_lab/actualizar_lab.ps1`.
3. En la notebook: **F6**, escribí la IP de esta PC en el campo y tocá **Unirse**.

**Si la notebook no entra** y dice "el host no te deja entrar: la copia del laboratorio de esta PC difiere en …": las dos máquinas no tienen lo mismo. Puede ser el Tuning, el código o el nivel. Guardá en esta PC, cerrá Godot en la notebook y volvé a hacer doble clic en `actualizar_lab.bat`.

### Simular internet

En el menú, **Simular internet**, o en el juego, las teclas **1** a **5** de la fila de arriba. Cada máquina elige la suya:

| Tecla | Red |
| --- | --- |
| 1 | Sin simulación |
| 2 | Internet buena (+40 ms) |
| 3 | Internet normal (+120 ms, 1 % de pérdida) |
| 4 | Internet mala (+200 ms, 5 % de pérdida) |
| 5 | Wi-Fi con tirones |

### Capturas

**F12** guarda una captura del juego en el **Escritorio**. Para pasárselas a Claude, se mueven a `C:\Users\ElCaido97\Documents\otro proyecto bobo\capturas`, que es donde las busca. Si no las encuentra ahí, también mira el Escritorio.

### Las teclas del laboratorio

| Tecla | Qué hace |
| --- | --- |
| WASD | Mover. Colgado de un borde, A y D de costado. Colgado de un cable, según la cámara |
| Espacio | Saltar. Colgado o en la escalera, mirando a la pared salta para arriba; mirando a otro lado, hacia allá. Cayendo sin haber saltado, salta en el aire una vez |
| Shift | Correr |
| Ctrl | Agacharse; corriendo, deslizarse. Colgado, se suelta |
| Rueda del mouse | Acerca la cámara, hasta primera persona |
| 1 del teclado numérico | Prende o apaga la cámara lenta del mundo, para todos |
| 2 del teclado numérico | Prende o apaga el súper salto y velocidad, para vos |
| E, R (solo el host) | Empujón inmediato y programado a los demás; con Shift, débiles. Q prende o apaga la adopción |
| G, F (solo en Jugar solo) | Pausa, y avanzar un tick en pausa |
| Esc | Suelta el mouse |

El detalle de cada una está en la sección 10.2 del historial.

---

## 3. Cambiar valores de movimiento (el Tuning)

Todo valor que se pueda ajustar está en el nodo **Tuning**, no en el personaje.

1. Abrí `net_lab.tscn` y seleccioná el nodo **Tuning**.
2. En el Inspector, los valores están por grupos: **Suelo**, **Deslizamiento**, **Escalera**, **Borde**, **Cable**, **Compañero**, **Cámara lenta**, **Súper salto y velocidad**, **Agarre**, **Aire** y **Salto**. Pasando el mouse por cada uno, se ve qué hace.
3. Cambialo y guardá con **Ctrl+S**.
4. Si vas a probar en las dos PC, actualizá la notebook: las dos tienen que tener los mismos valores, o la notebook no entra.

**Valores que cambiaste vos y no son los de fábrica:** el salto desde la escalera mirando a otro lado (**Ladder Jump Up**, 1,2), y en el grupo **Cable**, **Cable Grab Body** (0,3) y **Cable Reach** (0,6).

Los valores de la cámara están aparte, en el nodo **CameraRig**, y pueden ser distintos en cada PC.

---

## 4. Cables

Un cable es un nodo **Cable**: una curva que se dibuja en el editor. Lo que se ve es lo que el jugador agarra.

### Agregar uno

1. Abrí `net_lab_level.tscn`.
2. Clic derecho sobre el nodo donde lo querés (por ejemplo **NetLabLevel**) → **Add Child Node** → buscá **Cable** → **Create**. Aparece recto, de 4 m.
3. Movelo con las flechas. El primer punto de la curva es el lugar del nodo.
4. No hace falta ponerle número: los cables se numeran solos.

### Darle forma

Con el cable seleccionado, arriba del visor aparecen los botones de la curva:

- **Select Points:** arrastrar los puntos.
- **Select Control Points:** ver y arrastrar las manijas, para curvar el cable. En un punto nuevo, las manijas están pegadas al punto: se sacan arrastrando desde él. La manija del otro lado acompaña sola (opciones **Mirror Handle Angles** y **Mirror Handle Lengths**, en **Options**).
- **Add Point:** clic en el vacío suma un punto al final; clic sobre el cable lo parte en dos.
- **Delete Point:** clic sobre un punto lo saca.
- **Close Curve:** no la uses; cierra el cable en un círculo.

También se puede con números: en el Inspector, **Curve** → **Points**. Cada punto tiene **Position**, **In** y **Out**; queda suave si **In** es lo contrario de **Out**.

Se puede girar e inclinar el nodo sin problema: el cable va con él, tal cual se ve.

### Cómo se ve

En el Inspector, grupo **Dibujo**: **Look** (**Tube**, un tubo; **Model**, un modelo repetido a lo largo; **Texture**, una tira que mira a la cámara), **Thickness**, **Color**, **Material**, **Model**, **Texture** y **Texture Length**. **Model** pide una malla suelta, no un `.glb`. Quedó así a pedido: en el juego los cables van a ser texturas negras.

### Cómo se juega

Los valores están en el **Tuning**, grupo **Cable**. Las reglas, que decidiste vos, en la sección 8.19 del historial: se agarra sin tecla si el cable toca la parte de arriba del cuerpo; sin teclas se queda quieto en cualquier inclinación; las teclas van según la cámara; en uno inclinado, hacia abajo se desliza, hacia arriba sube despacio y soltando frena.

---

## 5. Escaleras

Una escalera es un nodo **Ladder**. Para el juego es solo un eje, un alto y un alcance; lo que se ve se arma con piezas.

### Agregar una

1. En `net_lab_level.tscn`: clic derecho → **Add Child Node** → **Ladder** → **Create**.
2. Movela: el nodo es el centro de abajo de la escalera.
3. Girala solo sobre el eje vertical. Se sube por el lado del eje Z del nodo (la flecha azul, con **Use Local Space** prendido o la tecla **T**). Si en el juego queda al revés, girala 180°.
4. En el Inspector: **Height** (alto), **Width** (ancho), **Standoff** (a qué distancia del eje queda el cuerpo) y **Reach** y **Side Reach** (desde qué distancia se agarra).
5. Para salir por arriba, poné un piso a la altura de **Height**.
6. No hace falta ponerle número: las escaleras se numeran solas.

### Con tus modelos

En el Inspector, grupo **Dibujo**:

- **Rail Model:** el larguero (un `.glb`). Va uno a cada lado, estirado hasta el alto; el de la derecha, espejado.
- **Rung Model:** el peldaño. Va uno cada **Rung Spacing**, estirado solo a lo ancho.
- **Tile Textures:** que la textura no se estire (la repite una vez por metro, según el lugar en el mundo; no usa el mapa UV de Blender).
- **Show Pieces:** apagado, no dibuja nada; para poner un modelo entero, hecho a mano, como hijo de la escalera.

Si dejás un modelo vacío, va una barra provisoria.

### Hacer los modelos en Blender

1. Una pieza por archivo: el larguero y el peldaño por separado.
2. El largo da igual, el código lo estira. Lo que se respeta es el grosor (de referencia: larguero de 6 × 6 cm y peldaño de 4 × 4 cm).
3. La orientación da igual: el lado más largo se toma como el largo. Pero la pieza tiene que estar alineada a los ejes, no en diagonal.
4. Antes de exportar, **Ctrl+A** → **Rotation & Scale**. El tamaño se ve con **N** → **Item** → **Dimensions**, en metros.
5. Sin detalles en las puntas del larguero (tapas, pies): se estiran con el resto.
6. **File** → **Export** → **glTF 2.0**: **glTF Binary (.glb)**, **Include** → **Selected Objects**, **Transform** → **+Y Up**.
7. Guardalo en `assets/models/stairs/`. Godot lo importa solo. Arrastralo desde **FileSystem** a **Rail Model** o **Rung Model**.

**Lo que todavía puede salir mal:** un peldaño plano puede quedar de canto (el código no sabe qué cara mira al que trepa), un material con shader propio se estira, y si volvés a exportar el `.glb` puede que la escalera no se actualice hasta tocar un valor. El detalle, en la sección 8.20 del historial.

---

## 6. Cómo trabajamos (reglas acordadas)

- **Godot cerrado antes de que Claude toque el nivel o `project.godot`.** Si está abierto, al guardar puede pisar el cambio. Claude avisa cuando hace falta cerrarlo; si Godot pregunta si guardar, a veces la respuesta es **No guardar**, y Claude lo dice.
- **El commit va después de la prueba en las dos PC**, y solo cuando lo pedís. Es local, en la rama `net-lab`; a GitHub se sube solo si lo pedís.
- **`project.godot` nunca va entero al commit:** el editor cambió una línea de 4.6 a 4.7 que no se commitea. Solo van las acciones del Mapa de entrada del laboratorio.
- **Los valores ajustables van en el nodo Tuning,** para que los cambies vos en el Inspector.
- **Instrucciones clic por clic,** con los nombres exactos de los botones. Tu Godot está en inglés.
- **Lo que decidís vos y lo que propone Claude se anota por separado,** y antes de sumar algo que no pediste, Claude pregunta.
- **Nada se afirma sin probarlo;** si algo sale de leer el código y no de una prueba, se dice.
- **El doble clic de la notebook se hace cuando Claude avisa que algo está listo,** no mientras cambia archivos.
- **Los poderes van en el teclado numérico** (1 y 2 usados; del 3 en adelante, libres), como acciones del Mapa de entrada.
- **Las pruebas automáticas:** la de repetición y el barrido de bordes están en el proyecto. Las demás (`diag_*.gd` y las pruebas en pareja) Claude las arma en una carpeta temporal que se borra; están copiadas enteras en el Apéndice B del historial, para volver a correrlas.

---

## 7. Lo que conviene recordar

- **Mecánicas que dependen de un buen internet** (se pide menos de 140 ms y poca pérdida): las correcciones de la balsa al subirse o saltar arriba, y la demora de la cámara lenta (0,1 s en la red de la casa, hasta 0,33 s con internet mala).
- **Si se va el host, se termina la partida:** no hay migración de host. Si a un cliente se le corta la red, el host lo espera hasta 60 s.
- **Cables y escaleras están fijos:** no se mueven ni se balancean. Sus números salen de su lugar en la escena, así que no se pueden agregar ni sacar en pleno juego sin cambiar eso.
- **El laboratorio no es el juego.** Antes de pasarlo al juego queda pendiente el punto 4 de la revisión externa: sacar las reglas que hoy están en `net_lab.gd` a una pieza propia (sección 8.12 del historial).
- **El muro de 3,6 m de la torre se sube solo desde el cajón,** aunque el cartel diga "con un compañero". Quedó así a pedido.
- **Las capturas de la notebook** también van a la carpeta de capturas.

La lista completa de pendientes y límites está en la sección 16 del historial.

---

## 8. Dónde está cada tema en el historial

| Tema | Sección |
| --- | --- |
| El pedido original y la arquitectura | 3 y 4 |
| El esqueleto de red: conexión, reloj, predicción, adopción, interpolación | 7 |
| Plataformas que se mueven y la balsa | 8.1 |
| Postura, deslizamiento y túnel | 8.2 |
| Escalera y empujones | 8.3 y 8.10 |
| El escalón | 8.4 |
| Colgarse de un borde (Hanging) | 8.5, 8.6, 8.7, 8.14 y 8.16 |
| Colgarse de un compañero | 8.8 |
| Cámara lenta | 8.9, 8.13 y 8.18 |
| El nodo Tuning y la primera persona | 8.10 |
| Reconexión y la rama `net-lab` | 8.11 |
| La comprobación de copias iguales al conectarse (la huella) | 8.12 |
| Súper salto y velocidad, y los poderes del teclado numérico | 8.13 |
| La torre de parkour | 8.15 |
| El salto en el aire | 8.17 |
| Cables: cómo se juegan | 8.19 |
| Cables y escaleras en el editor | 8.20 |
| El código hoy: archivos, funciones, formatos de red, constantes, valores del Tuning | 9 |
| Cómo usar el laboratorio: menú, teclas, panel, pruebas, el nivel | 10 |
| Todas las pruebas y sus resultados | 11 |
| Cosas de Godot y Jolt que se comprobaron | 12 |
| Errores y cómo se resolvieron | 13 |
| Decisiones y forma de trabajo | 14 |
| Commits | 15 |
| Pendientes y límites | 16 |
| Los scripts de las pruebas | Apéndice B |

---

## 9. Dónde quedó (2026-10-15)

- **Último commit:** el de esta guía y la undécima versión del historial (2026-10-16), en `net-lab`, solo local. Antes, `3e1bd48`, la décima versión del historial, y `7dd59ca`, los cables.
- **Sin commit:** el código de los cables como curva, los números solos de cables y escaleras, y la escalera con modelos (sección 8.20 del historial). Falta la prueba en las dos PC.
- **Por decidir antes del commit:** si se quedan en el nivel tus dos objetos de prueba, **CablePrueba1** y la escalera de 17 m (**Ladder**). Si se quedan, en el commit van también los dos `.glb` de `assets/models/stairs`.
