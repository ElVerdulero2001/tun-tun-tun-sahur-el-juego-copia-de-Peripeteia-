# Guía del laboratorio de red

Esta guía es para retomar el laboratorio después de un tiempo sin tener que leer todo el historial. Está armada por tareas: dónde está cada cosa, cómo probar, cómo agregar cables y escaleras, cómo se cuelga uno de un compañero, qué reglas acordamos y en qué sección del historial está el detalle.

- **El historial completo**, con cada decisión, prueba y error, en orden: [`arquitectura_coop_y_esqueleto_de_red.md`](arquitectura_coop_y_esqueleto_de_red.md).
- **El diseño de la arquitectura:** [Arquitectura de movimiento co-op (Godot 4.7 + Jolt)](https://claude.ai/code/artifact/6760c3bf-39ed-4f2f-8d9d-23642c7ac797), en Claude Docs. Está copiado en el Apéndice A del historial.

**Para pedirle algo a Claude en otra conversación:** "leé `docs/net/guia_del_laboratorio.md` y ayudame a …". Si hace falta más detalle, la sección 9 de esta guía dice en qué parte del historial buscarlo.

Escrita el 2026-10-15 y puesta al día el 2026-10-18. Si algo de acá no coincide con el código, manda el código, y hay que corregir la guía.

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
| Las pistas armadas por código (bordes, escalones, torre, pista de cables, pista de colgarse) | `scenes/net_lab/edge_course.gd`, `step_course.gd`, `parkour_tower.gd`, `cable_course.gd`, `hook_course.gd` |
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

**Los videos** (grabados con OBS) van a la misma carpeta. Claude los revisa sacando imágenes con ffmpeg: el tuyo, en `C:\ffmpeg\ffmpeg-9.0.2-essentials_build\bin`, que está en tu PATH desde el 2026-10-17. Conviene un video de cada PC.

### Las teclas del laboratorio

| Tecla | Qué hace |
| --- | --- |
| WASD | Mover. En la escalera, W sube y S baja, mire donde mire la cámara (desde el 2026-10-16). Al salir por arriba con W, mientras sigas con W sola vas derecho hacia donde subías, mire donde mire; soltar W o tocar A, S o D lo corta, y Shift, Espacio y Ctrl no. Colgado de un borde, A y D de costado. Colgado de un cable, según la cámara. Colgado de un compañero, W y S suben y bajan tus manos por su cuerpo, mire donde mire, y A y D te giran alrededor de él (desde el 2026-10-18) |
| Espacio | Saltar. Colgado o en la escalera, mirando a la pared salta para arriba; mirando a otro lado, hacia allá. En la escalera, el salto para arriba se vuelve a agarrar solo, sin teclas, en el punto más alto o, si pasó por encima del final, al volver a bajar hasta ella (desde el 2026-10-16). Cayendo sin haber saltado, salta en el aire una vez |
| Shift | Correr |
| Ctrl | Agacharse; corriendo, deslizarse. Colgado, se suelta. En la escalera, se suelta sin empujón: caés mientras lo tengas y, al soltarlo, si seguís frente a la escalera te agarrás solo; si llegaste al piso, te quedás ahí (desde el 2026-10-16). Con Ctrl no te agarrás de ninguna escalera, ni caminando hacia ella. Con alguien colgado de vos, se caen los dos. Colgado de un compañero, igual que en la escalera: caés mientras lo tengas y, al soltarlo, si seguís al alcance, te volvés a agarrar (desde el 2026-10-18) |
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

**Para que colgarse de un compañero sea más o menos permisivo** (grupo **Compañero**, desde el 2026-10-18): **Hook Reach** (1 m: hasta qué distancia de su eje te agarrás), **Hook Min Height** y **Hook Max Height** (0 y 1,5 m: la franja de su cuerpo de la que te agarrás, y hasta donde llegan W y S), **Hook Climb Speed** y **Hook Turn Speed** (1,5 m/s) y **Hook Turn Limit** (90°: cuánto girás por lado en un borde o una escalera). Los eligió Claude; están para que los ajustes vos.

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

### Cómo se juega

Las reglas, que decidiste vos, en la sección 8.21 del historial:

- **W sube y S baja,** mire donde mire la cámara; A y D no hacen nada.
- **Saliendo por arriba con W sola,** seguís derecho hacia donde subías; soltar W o tocar A, S o D lo corta.
- **Espacio mirándola** salta para arriba y te volvés a agarrar solo, en el punto más alto o, si pasaste el final, al volver a bajar.
- **Ctrl** te suelta sin empujón: caés mientras lo tengas y al soltarlo te agarrás. Con Ctrl no te agarrás de ninguna escalera, y con alguien colgado de vos, se caen los dos.

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

## 6. Colgarse de un compañero

Uno se agarra de un borde, una escalera o un cable, y el otro se cuelga de él. Las reglas, que decidiste vos, en las secciones 8.8 y 8.22 del historial:

- **Sin tecla y sin mirarlo:** el compañero es como un cilindro. Te agarrás si tus manos pasan a no más de 1 m de su eje, entre sus pies y sus hombros, y vas a su cintura del lado por el que llegaste.
- **Del que está en un cable,** de cualquier lado. **Del que está en un borde o una escalera,** solo por su espalda, hasta 90° para cada lado: nunca del lado de la pared o de la escalera.
- **Colgado:** W y S suben y bajan tus manos por su cuerpo, de sus pies a sus hombros, mire donde mire; A y D te giran alrededor de él. Si algo te tapa, no te movés.
- **El de arriba** queda quieto mientras alguien cuelga de él, aunque esté en un cable inclinado. Espacio no le hace nada, y Ctrl lo suelta y se caen los dos.
- **Espacio** mirándolo salta para arriba; mirando a otro lado, hacia allá. **Ctrl**, como en la escalera: caés mientras lo tengas y, al soltarlo, si seguís al alcance, te volvés a agarrar.
- **La altura importa:** colgarse desde el piso de uno en un cable pide un cable de entre 3,5 y 3,7 m, como el muro de 3,6 m. Más bajo, te agarrás del cable; más alto, no llegás de un salto.

Los valores para hacerlo más o menos permisivo están en el **Tuning**, grupo **Compañero** (sección 3 de esta guía).

### La pista de colgarse

Para buscar si moverse alrededor del compañero sirve para atravesar paredes o pisos. Está en el oeste del nivel (nodo **PistaDeColgarse**, en x −25), con un cartel en cada estación; los cables y los bordes tienen un cajón para subirse.

| N.º | Estación |
| --- | --- |
| 1 | Cable junto a una pared gruesa |
| 2 | Cable cruzado por una pared de 5 cm |
| 3 | Cable en un pasillo de 1,2 m |
| 4 | Cable sobre un piso con un agujero |
| 5 | Escalera contra una pared |
| 6 | Escalera suelta, sin pared |
| 7 | Escalera que atraviesa un piso |
| 8 | Borde de un muro grueso |
| 9 | Borde de una losa de 5 cm sin nada abajo |
| 10 | Borde de una columna |

En las pruebas sin red y en las tuyas, en ninguna se pudo meterse en una pared o un piso ni pasar al otro lado. Colgarse a través de una pared tampoco: los dos cuerpos quedan tocándose y no entra nada en el medio. Para cambiar las estaciones, se edita la lista en `hook_course.gd`; las piezas no se guardan en la escena.

---

## 7. Cómo trabajamos (reglas acordadas)

- **Godot cerrado antes de que Claude toque el nivel o `project.godot`.** Si está abierto, al guardar puede pisar el cambio. Claude avisa cuando hace falta cerrarlo; si Godot pregunta si guardar, a veces la respuesta es **No guardar**, y Claude lo dice.
- **El commit local va después de una prueba en las dos PC que sale bien,** sin esperar a que lo pidas (decidido el 2026-10-17: "seguí así, commit después de una prueba que sale bien"). Es local, en la rama `net-lab`; a GitHub se sube solo si lo pedís. Los md se commitean cuando lo pedís.
- **`project.godot` nunca va entero al commit:** el editor cambió una línea de 4.6 a 4.7 que no se commitea. Solo van las acciones del Mapa de entrada del laboratorio.
- **Los valores ajustables van en el nodo Tuning,** para que los cambies vos en el Inspector.
- **Instrucciones clic por clic,** con los nombres exactos de los botones. Tu Godot está en inglés.
- **Lo que decidís vos y lo que propone Claude se anota por separado,** y antes de sumar algo que no pediste, Claude pregunta.
- **Nada se afirma sin probarlo;** si algo sale de leer el código y no de una prueba, se dice.
- **El doble clic de la notebook se hace cuando Claude avisa que algo está listo,** no mientras cambia archivos.
- **Los poderes van en el teclado numérico** (1 y 2 usados; del 3 en adelante, libres), como acciones del Mapa de entrada.
- **Todo lo que te escribe Claude va en español,** también los avisos entre pasos.
- **Cuando Claude te nombra un archivo,** te dice qué es y si tenés que hacer algo con él.
- **Las pruebas automáticas:** la de repetición y el barrido de bordes están en el proyecto. Las demás (`diag_*.gd` y las pruebas en pareja) Claude las arma en una carpeta temporal que se borra; están copiadas enteras en el Apéndice B del historial, para volver a correrlas.

---

## 8. Lo que conviene recordar

- **Mecánicas que dependen de un buen internet** (se pide menos de 140 ms y poca pérdida): las correcciones de la balsa al subirse o saltar arriba, y la demora de la cámara lenta (0,1 s en la red de la casa, hasta 0,33 s con internet mala).
- **Si se va el host, se termina la partida:** no hay migración de host. Si a un cliente se le corta la red, el host lo espera hasta 60 s.
- **Cables y escaleras están fijos:** no se mueven ni se balancean. Sus números salen de su lugar en la escena, así que no se pueden agregar ni sacar en pleno juego sin cambiar eso.
- **El laboratorio no es el juego.** Antes de pasarlo al juego queda pendiente el punto 4 de la revisión externa: sacar las reglas que hoy están en `net_lab.gd` a una pieza propia (sección 8.12 del historial).
- **El muro de 3,6 m de la torre se sube solo desde el cajón,** aunque el cartel diga "con un compañero". Quedó así a pedido.
- **Las capturas de la notebook** también van a la carpeta de capturas.
- **Saliendo derecho de una escalera,** girar la cámara no hace doblar: hay que soltar W o tocar A, S o D.
- **Cuando el de arriba se suelta con alguien colgado,** el que cuelga recibe una corrección por caída, porque ve al de arriba con atraso. Es normal, también en el muro.
- **Colgándose de uno que todavía se mueve,** el host puede adoptar diferencias de 1 mm de lo que afirma el que se cuelga, porque su PC ve al de arriba en el pasado. No hay corrección.
- **Los números de cables y escaleras cambian si una pista nueva va antes en la escena:** con la pista de colgarse, la huella de la prueba de repetición pasó de `cb02d3f0640600f9` a `64564ccef7594dba`, sin que cambiara el movimiento.
- **Saltar de un borde no te deja agarrarte de un cable por 0,3 s;** del cable al borde, sí (desde el 2026-10-18, para cortar el bucle entre los dos).

La lista completa de pendientes y límites está en la sección 16 del historial.

---

## 9. Dónde está cada tema en el historial

| Tema | Sección |
| --- | --- |
| El pedido original y la arquitectura | 3 y 4 |
| El esqueleto de red: conexión, reloj, predicción, adopción, interpolación | 7 |
| Plataformas que se mueven y la balsa | 8.1 |
| Postura, deslizamiento y túnel | 8.2 |
| Escalera y empujones | 8.3 y 8.10 |
| El escalón | 8.4 |
| Colgarse de un borde (Hanging) | 8.5, 8.6, 8.7, 8.14 y 8.16 |
| Colgarse de un compañero | 8.8 y 8.22 |
| Cámara lenta | 8.9, 8.13 y 8.18 |
| El nodo Tuning y la primera persona | 8.10 |
| Reconexión y la rama `net-lab` | 8.11 |
| La comprobación de copias iguales al conectarse (la huella) | 8.12 |
| Súper salto y velocidad, y los poderes del teclado numérico | 8.13 |
| La torre de parkour | 8.15 |
| El salto en el aire | 8.17 |
| Cables: cómo se juegan | 8.19 |
| Cables y escaleras en el editor | 8.20 |
| La escalera: W y S, la salida por arriba, el salto y Ctrl; colgado del compañero con internet mala | 8.21 |
| El bucle entre un cable y un borde; colgarse del compañero en un cable y como de un cilindro; la pista de colgarse | 8.22 |
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

## 10. Dónde quedó (2026-10-18)

- **Último commit:** el de esta guía y la decimotercera versión del historial (2026-10-18), en `net-lab`. Antes, los cuatro del día: `9fc5d86` (el cilindro en la escalera y el borde, y la pista de colgarse), `4b4fdb6` (el cilindro en el cable), `8355cd2` (colgarse de un compañero en un cable) y `25a37f1` (el bucle entre el cable y el borde).
- **En GitHub:** la rama `net-lab` se subió el 2026-10-18 con todos los commits, hasta el de esta guía.
- **Sin commit:** nada del laboratorio. `project.godot` tiene la línea 4.6 → 4.7 del editor, que no se commitea.
- **Pendientes:** seguir probando si el cilindro es muy permisivo, con más escenarios; la línea de ayuda del compañero, que se corta en la notebook después de "espalda"; la cuerda con la cámara ("no lo vamos a tocar ahora"); las pruebas de empujones al que cuelga de un compañero, que ya no llegan a colgarse (de antes, sin investigar); y el punto 4 de la revisión externa, para cuando pase al juego. La lista completa, en la sección 16 del historial.
