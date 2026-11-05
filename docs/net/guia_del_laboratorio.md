# Guía del laboratorio de red

Esta guía es para retomar el laboratorio después de un tiempo sin tener que leer todo el historial. Está armada por tareas: dónde está cada cosa, cómo probar, cómo agregar cables y escaleras, cómo se cuelga uno de un compañero, cómo funciona el mantle, qué reglas acordamos y en qué sección del historial está el detalle.

- **El historial completo**, con cada decisión, prueba y error, en orden: [`arquitectura_coop_y_esqueleto_de_red.md`](arquitectura_coop_y_esqueleto_de_red.md).
- **El diseño de la arquitectura:** [Arquitectura de movimiento co-op (Godot 4.7 + Jolt)](https://claude.ai/code/artifact/6760c3bf-39ed-4f2f-8d9d-23642c7ac797), en Claude Docs. Está copiado en el Apéndice A del historial.

**Para pedirle algo a Claude en otra conversación:** "leé `docs/net/guia_del_laboratorio.md` y ayudame a …". Si hace falta más detalle, la sección 12 de esta guía dice en qué parte del historial buscarlo.

Escrita el 2026-10-15 y puesta al día el 2026-10-22 dos veces (la segunda, a la noche, con la cuarta vuelta de la escalera, el súper, la velocidad terminal, el freno al caerse de un borde y la pista de salto agachado), el 2026-10-24 (el súper en todas las velocidades), el 2026-10-30 dos veces (el mantle, la unión de dos cajas apiladas y frenar en la salida por arriba de la escalera; a la tarde, lo que salió de la auditoría de GPT del parkour), el 2026-10-31 tres veces (todo commiteado y subido a GitHub; a la noche, el inventario de grilla, sección 14, y después su segunda vuelta con tus notas de prueba) y el 2026-11-01 (la tercera y la cuarta vuelta del inventario, su commit y el panel Objetos para crear objetos, y a la noche su segunda versión, con contenedores y vista previa) y el 2026-11-02 (la salud, la estamina, los estados y el HUD, sección 15, y las burbujitas de ayuda del panel Objetos) y el 2026-11-04 (los commits, usar y recoger sin esperar al host, y después soltar sin esperar, la medición de recoger contra soltar y el arreglo del aviso de tu captura). Si algo de acá no coincide con el código, manda el código, y hay que corregir la guía.

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
| La zona de servicio (un pedazo de mapa con todo junto; sección 7) | `scenes/net_lab/zona_de_servicio.tscn`, nodo **ZonaDeServicio** del nivel |
| La torre de servicio, de 20 a 100 m, sobre la zona (sección 7) | `scenes/net_lab/torre_de_servicio.tscn`, nodo **TorreDeServicio**, adentro de **ZonaDeServicio** |
| La pista de salto agachado (sección 8) | `scenes/net_lab/crouch_jump_course.gd`, nodo **PistaDeSaltoAgachado** del nivel |
| El mantle (sección 9) | `scripts/actor/actor_motor.gd` (`mantle_check` y las funciones que empiezan con `_mantle`); sus valores, en el nodo **Tuning**, grupo **Mantle** |
| La cámara | `scenes/net_lab/lab_camera.gd`; sus valores, en el nodo **CameraRig** de `net_lab.tscn` |
| El doble clic de la notebook | `tools/net_lab/actualizar_lab.bat` y `.ps1` |
| La exportación a `.exe` para jugar a distancia (sección 2) | `export_presets.cfg` (el ajuste **Laboratorio co-op (Windows)**) y dos líneas de `project.godot`, las que terminan en `.lab_coop` |
| Los modelos de escaleras | `assets/models/stairs/` |
| Las cuatro pruebas automáticas que están en el proyecto | `scenes/net_lab/actor_replay_test.tscn` (repetición), `hang_sweep_test.tscn` (barrido de bordes) y, desde el 2026-10-30, `mantle_test.tscn` (el mantle, caso por caso) y `grab_above_test.tscn` (el agarre con las manos por encima del filo) |
| El inventario de grilla (sección 14; desde el 2026-10-31) | Código en `scripts/inventory/`; la zona de prueba, los objetos y sus pruebas en `scenes/net_lab/inventario/`; los nodos **Inventario** y **Hud → InventarioUI** de `net_lab.tscn`. Todo, en `docs/net/inventario_de_grilla.md` |
| La salud, la estamina, los estados y el HUD (sección 15; desde el 2026-11-02) | `scripts/actor/actor_powers.gd` y `actor_vitals.gd`; el HUD en `scenes/net_lab/hud/` y el nodo **Hud → Instrumentos** de `net_lab.tscn`; su prueba, `scenes/net_lab/estados_test.tscn`. Todo, en `docs/net/hud_salud_estamina_y_estados.md` |

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

**Si la notebook no entra** y dice "el host no te deja entrar: la copia del laboratorio de esta PC difiere en …": las dos máquinas no tienen lo mismo. Puede ser el Tuning, el código, el nivel o el personaje (`actor.tscn`; desde el 2026-10-19, también sus capas, su máscara y su margen, y los de cada cuerpo del nivel). Guardá en esta PC, cerrá Godot en la notebook y volvé a hacer doble clic en `actualizar_lab.bat`.

### A distancia, cada uno en su casa (desde el 2026-10-21)

Se juega con el laboratorio exportado (un solo `.exe`, sin Godot) y con **Radmin VPN**, que hace de red local entre las dos casas. Los dos usan **el mismo `.exe`**: cada vez que exportás de nuevo, se lo volvés a mandar. Si tiene uno viejo, el host no lo deja entrar y dice qué parte es distinta (la huella también mira el código, porque el `.exe` lleva los scripts como texto).

**Exportar** (Godot abierto, con todo guardado):

1. Menú **Proyecto → Exportar…** (*Project → Export…*).
2. A la izquierda, **Laboratorio co-op (Windows)**. Ya está todo ajustado; no hace falta tocar nada.
3. Abajo, **Exportar proyecto…** (*Export Project…*).
4. En la ventana de guardar, **destildá Exportar con depuración** (*Export With Debug*) y tocá **Guardar**. Queda en `C:\Users\ElCaido97\Documents\otro proyecto bobo\exports\TunTunTunSahur_LaboratorioCoop.exe`.
5. Para mandarlo: clic derecho en el `.exe` → **Enviar a → Carpeta comprimida (en zip)**, y el zip por Google Drive o WeTransfer (Gmail no deja mandar programas).

El primero ya está hecho (2026-10-21), con su zip al lado: `TunTunTunSahur_LaboratorioCoop.zip`, en la misma carpeta. Lleva lo que había en tu disco ese día, también lo que no tiene commit.

**Qué tiene el ajuste** (`export_presets.cfg` y dos líneas de `project.godot`): arranca en `net_lab.tscn` (en el editor, F5 sigue abriendo `movement_test`); abre la ventana maximizada, para que entre en cualquier pantalla; todo va adentro del `.exe`; los scripts van como texto, para la huella; y deja afuera `tmp`, `archive`, `output`, `docs` y `tools`. Las plantillas de exportación de 4.7.2 están instaladas desde el 2026-10-21; si algún día faltan, Godot avisa en esa ventana y se bajan con **Editor → Administrar plantillas de exportación → Descargar e instalar**.

**Jugar:**

1. **Los dos, una sola vez:** Radmin VPN abierto y prendido (tu amigo lo baja de radmin-vpn.com). Vos: **Crear red** (*Create Network*), con un nombre y una contraseña. Tu amigo: **Unirse a la red** (*Join Network*), con esos dos datos. Tiene que aparecerles el otro en la lista de la red.
2. **Vos:** abrí el `.exe` y tocá **Crear partida**. La primera vez Windows pregunta por el firewall: **Permitir acceso**. El menú muestra tus IP, una por conexión; la que le pasás es la de **Radmin VPN** (hasta ahora `26.107.101.113`).
3. **Tu amigo:** abre el `.exe` (la primera vez Windows avisa que es un programa desconocido: **Más información → Ejecutar de todas formas**; si pregunta por el firewall, **Permitir acceso**), escribe tu IP de Radmin VPN en el campo y toca **Unirse**.
4. **Simular internet** se deja en **sin simulación**: la internet ya es real. En el panel, **ida y vuelta** tiene que quedar por debajo de 140 ms.

Si algo sale mal, cada `.exe` deja lo que pasó en `%APPDATA%\Godot\app_userdata\Tun tun tun sahur\logs\godot.log`; con eso Claude puede ver qué pasó.

### Simular internet

En el menú, **Simular internet**, o en el juego, **Alt** + las teclas **1** a **5** de la fila de arriba (hasta el 2026-10-31 eran sin Alt; la fila de arriba sin Alt pasó a ser la barra rápida del inventario). Cada máquina elige la suya:

| Tecla | Red |
| --- | --- |
| 1 | Sin simulación |
| 2 | Internet buena (+40 ms) |
| 3 | Internet normal (+120 ms, 1 % de pérdida) |
| 4 | Internet mala (+200 ms, 5 % de pérdida) |
| 5 | Wi-Fi con tirones |

### Capturas

**F12** guarda una captura del juego en el **Escritorio**. Con el panel oculto (**F1**), sale sin el panel. Para pasárselas a Claude, se mueven a `C:\Users\ElCaido97\Documents\otro proyecto bobo\capturas`, que es donde las busca. Si no las encuentra ahí, también mira el Escritorio.

**Los videos** (grabados con OBS) van a la misma carpeta. Claude los revisa sacando imágenes con ffmpeg: el tuyo, en `C:\ffmpeg\ffmpeg-9.0.2-essentials_build\bin`, que está en tu PATH desde el 2026-10-17. Conviene un video de cada PC.

### Las teclas del laboratorio

| Tecla | Qué hace |
| --- | --- |
| WASD | Mover. En la escalera, W sube y S baja, mire donde mire la cámara (desde el 2026-10-16). Al salir por arriba con W, W va según la cámara; solo en tercera persona y con la cámara mirando para atrás seguís derecho hacia donde subías mientras sigas con W sola (desde el 2026-10-20); soltar W, tocar A, S o D, girar la cámara hacia adelante o pasar a primera persona lo corta, y Shift, Espacio y Ctrl no. Colgado de un borde, A y D de costado. Colgado de un cable, según la cámara. Colgado de un compañero, W y S suben y bajan tus manos por su cuerpo, mire donde mire, y A y D te giran alrededor de él (desde el 2026-10-18). En el mantle, al pasar arriba vas hacia donde apuntan, según la cámara, hasta 45° de costado (desde el 2026-10-25) |
| Espacio | Saltar. Colgado o en la escalera, mirando a la pared salta para arriba; mirando a otro lado, hacia allá. En la escalera, el salto para arriba se vuelve a agarrar solo, sin teclas, en el punto más alto o, si pasó por encima del final, al volver a bajar hasta ella (desde el 2026-10-16). Cayendo sin haber saltado, salta en el aire una vez. Saltando mirando un borde bajo, el mantle te sube solo (desde el 2026-10-25, sección 9) |
| Shift | Correr |
| Ctrl | Agacharse; corriendo, deslizarse. Colgado, se suelta. En la escalera, se suelta sin empujón: caés mientras lo tengas y, al soltarlo, si seguís frente a la escalera te agarrás solo; si llegaste al piso, te quedás ahí (desde el 2026-10-16). Con A o D apretada (antes de Ctrl, al tocarlo o mientras caés), te soltás y no te volvés a agarrar solo (desde el 2026-10-20). Con Ctrl no te agarrás de ninguna escalera, ni caminando hacia ella. Con alguien colgado de vos, se caen los dos. Colgado de un compañero, igual que en la escalera: caés mientras lo tengas y, al soltarlo, si seguís al alcance, te volvés a agarrar (desde el 2026-10-18). En el mantle, te suelta; con Ctrl apretado al saltar, no hay mantle (desde el 2026-10-25) |
| Rueda del mouse | Acerca la cámara, hasta primera persona |
| 1 del teclado numérico | Pedís o soltás la cámara lenta del mundo: va lenta para todos mientras al menos uno la pida. Desde el 2026-11-02 gasta tu estamina mientras la pedís (sección 15) |
| 2 del teclado numérico | Prende o apaga el súper salto y velocidad, para vos. Desde el 2026-11-02 gasta tu estamina mientras está prendido |
| Y, U (solo el host) | Empujón inmediato y programado a los demás; con Shift, débiles. Q prende o apaga la adopción. Hasta el 2026-10-31 eran E y R: E pasó a ser interactuar (elegido por vos) |
| Tab | Abre y cierra el inventario (sección 14). El mundo no se pausa: se sigue caminando |
| E | Recoge el objeto o abre la caja que estás mirando, si está al alcance y a la vista. Con una caja abierta, la cierra junto con el inventario |
| 1 a 9 y 0 | La barra rápida del inventario: usa o equipa lo que tiene cada acceso |
| G, F (solo en Jugar solo) | Pausa, y avanzar un tick en pausa |
| F1 | Oculta el panel de valores, y otra vez F1 lo muestra: para mirar o capturar el juego sin él (desde el 2026-10-19) |
| Esc | Con el inventario abierto, suelta lo que tenés en la mano (vuelve a su lugar) o cierra el diálogo, después cierra el menú y por último el inventario. Si no, suelta el mouse |

El detalle de cada una está en la sección 10.2 del historial.

---

## 3. Cambiar valores de movimiento (el Tuning)

Todo valor que se pueda ajustar está en el nodo **Tuning**, no en el personaje.

1. Abrí `net_lab.tscn` y seleccioná el nodo **Tuning**.
2. En el Inspector, los valores están por grupos: **Suelo**, **Deslizamiento**, **Escalera**, **Borde**, **Mantle** (desde el 2026-10-25), **Cable**, **Compañero**, **Salud y estamina** (desde el 2026-11-02, sección 15), **Cámara lenta**, **Súper salto y velocidad**, **Agarre**, **Aire** y **Salto**. Pasando el mouse por cada uno, se ve qué hace.
3. Cambialo y guardá con **Ctrl+S**.
4. Si vas a probar en las dos PC, actualizá la notebook: las dos tienen que tener los mismos valores, o la notebook no entra.

**Desde el 2026-10-19** (commit `a257e4b`, el 2026-10-30), en el grupo **Borde**, **Hang Reach Down** (1 m) y **Hang Drop Speed** (4 m/s): llegando a la pared con las manos hasta ese tanto por encima del filo, te agarrás en el acto, y el cuerpo baja a esa velocidad hasta colgar. Subiendo también, salvo que el salto te lleve los pies por encima del muro: ahí seguís y caés arriba. Con **Hang Reach Down** en 0, es como antes. Elegiste hasta 1 m y que la bajada fuera más rápida; los 4 m/s los puso Claude. Llegando subiendo con el filo a la altura del pecho, en vez de agarrarte hacés el mantle (sección 9). El detalle, en la sección 8.24 del historial.

**Desde el 2026-10-20,** en el grupo **Escalera**, **Ladder Exit Back Angle** (90°): desde qué ángulo la cámara cuenta como mirando para atrás al salir de una escalera. Lo eligió Claude.

**Desde el 2026-10-22** (lo pediste después de tus videos; los números los eligió Claude):

- **Grupo Escalera:**
    - **Ladder Top Land** (0,4 m): al salir por arriba, dónde termina el centro del cuerpo, detrás del eje de la escalera. Reemplaza a **Ladder Top Hop Speed**, el empujón de 2,5 m/s; desde el 2026-10-23 tampoco está **Ladder Top Hop Height**: ya no hay saltito.
    - **Ladder Top No Grab** (0,5 m): parado en el piso, en este tramo de arriba de una escalera no te agarrás.
    - **Ladder Grab Side** (0,3 m): hasta qué distancia del centro de la escalera, de costado, te agarrás.
- **Grupo Aire:**
    - **Max Fall Speed** (40 m/s): la velocidad terminal. Ya estaba; con 40 se llega cayendo unos 82 m.
    - **Unlimited Fall Speed** (casilla, apagada): prendida, no hay velocidad terminal.
    - **Walk Off Brake** (60 m/s²): cayéndote de un borde sin haber saltado y sin apretar nada, a qué ritmo frenás en el aire; con 60, como en el piso; 0 lo apaga.
- **Grupo Súper salto y velocidad:** **Boost Speed Scale** (1,5) multiplica solo todas las velocidades de moverse: todo valor del Tuning cuyo nombre termina en **Speed**, salvo **Max Fall Speed**. Desde el 2026-10-24 entran también la escalera (**Climb Speed**: trepás a 3,75 con el súper), colgado (**Shimmy Speed**), colgado de un compañero (**Hook Climb Speed** y **Hook Turn Speed**), el deslizamiento (los tres **Slide … Speed**) y los saltos hacia afuera desde la escalera, un borde o un compañero. No cambian las aceleraciones ni la altura de los saltos (la del súper salto es **Boost Jump Extra**). Una velocidad nueva que termine en Speed va con el súper sola, sin tocar nada más. **Ladder Jump Out** y **Hang Jump Out** ahora se llaman **Ladder Jump Out Speed** y **Hang Jump Out Speed**, con los mismos valores. **Boost Jump Max Speed** (los 6,5 m/s del tope del salto con el súper) ya no existe desde el 2026-10-22.

**Desde el 2026-10-25,** el grupo **Mantle** (sección 9). Cómo funciona lo decidiste vos; los números los eligió Claude, para que los ajustes jugando:

| Valor | De fábrica | Qué es |
| --- | --- | --- |
| **Mantle Min Height** | 0,3 m | Desde qué altura del filo sobre tus pies hay mantle; más bajo es un escalón, o el salto ya lo pasa |
| **Mantle Max Height** | 1,5 m | Hasta qué altura; más alto, te colgás. En 0 se apaga el mantle |
| **Mantle Up Speed** | 4 m/s | A qué velocidad sube el cuerpo hasta el filo |
| **Mantle Forward Speed** | 5 m/s | A qué velocidad pasa arriba |
| **Mantle Side Angle** | 45° | Pasando arriba, hasta cuánto de costado podés ir |
| **Mantle Land** | 0,45 m | Dónde terminás sin teclas: el centro del cuerpo, este tanto detrás del filo. También es lo que tiene que tener de fondo lo de arriba para que haya mantle |

**Valores que cambiaste vos y no son los de fábrica:** el salto desde la escalera mirando a otro lado (**Ladder Jump Up**, 1,2), en el grupo **Cable**, **Cable Grab Body** (0,3) y **Cable Reach** (0,6), y desde el 2026-11-02 los costos de estamina: **Slow Stamina Cost** y **Boost Stamina Cost** en 0,8 (los de fábrica, 8 y 5, fundían la reserva muy rápido). Los estás probando hasta que se sientan bien.

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

Los valores están en el **Tuning**, grupo **Cable**. Las reglas, que decidiste vos, en la sección 8.19 del historial: se agarra sin tecla si el cable toca la parte de arriba del cuerpo; sin teclas se queda quieto en cualquier inclinación; las teclas van según la cámara; en uno inclinado, hacia abajo se desliza, hacia arriba sube más despacio y soltando frena.

Desde el 2026-10-19 (lo pediste después de probar la zona de servicio):

- **Más rápido:** en uno plano o poco inclinado, a **Cable Speed** (3,5 m/s; antes 1,5, la de los bordes); para arriba en uno inclinado, a **Cable Climb Speed** (2 m/s; antes 0,75). Los números los eligió Claude: ajustalos vos.
- **El impulso se conserva al agarrarte:** te quedás con la velocidad que traías a lo largo del cable. Cayendo derecho sobre uno inclinado, salís hacia donde baja; sobre uno plano, no te mueve; corriendo y saltando a lo largo de él, seguís a esa velocidad. Lo que pase de la velocidad del cable se va perdiendo a **Cable Carry Brake** (6 m/s²) y después seguís como siempre. Ejemplo: cayendo 12 m sobre la bajada de la zona de servicio (35°), te agarrás a 8,3 m/s y en unos 2 m bajás a 6,8, la de deslizarse. Se conserva la parte de la caída que va a lo largo del cable, no toda.
- **El salto desde un cable con el súper prendido** sale como el salto en el aire con el súper: 1,5 veces más rápido y los pies suben 1,5 m más (2,3 m en vez de 0,8).
- **Con el súper, los cables van 1,5 veces más rápido** (desde el 2026-10-22): en uno plano, 5,25 m/s; subiendo uno inclinado, 3; y deslizándote, hasta 18 por el seno de la inclinación.
- **Del compañero al cable y del cable al compañero hay 0,3 s sin agarrarse,** como entre un borde y un cable: si no, colgado de un compañero que está en un cable, cada Espacio te pasaba del compañero al cable y del cable al compañero.

---

## 5. Escaleras

Una escalera es un nodo **Ladder**. Para trepar es solo un eje, un alto y un alcance; lo que se ve se arma con piezas, y desde el 2026-10-20 esas piezas chocan.

### Agregar una

1. En `net_lab_level.tscn`: clic derecho → **Add Child Node** → **Ladder** → **Create**.
2. Movela: el nodo es el centro de abajo de la escalera.
3. Girala solo sobre el eje vertical. El frente es el lado del eje Z del nodo (la flecha azul, con **Use Local Space** prendido o la tecla **T**). Si queda suelta, sin nada atrás, se trepa también por el otro lado (ver "De los dos lados", abajo). Si en el juego queda al revés contra una pared, girala 180°.
4. No la escales: **Scale** en 1, en ella y en los nodos de arriba. Escalada se dibuja de un tamaño y se trepa de otro; desde el 2026-10-19, Godot muestra un triángulo amarillo al lado del nodo, en la pestaña **Scene**, y al correr lo avisa la consola. El tamaño se cambia con **Height** y **Width**.
5. En el Inspector: **Height** (alto), **Width** (ancho), **Standoff** (a qué distancia del eje queda el cuerpo) y **Reach** y **Side Reach** (desde qué distancia se agarra).
6. Para salir por arriba, poné un piso a la altura de **Height**.
7. No hace falta ponerle número: las escaleras se numeran solas.

### Con tus modelos

En el Inspector, grupo **Dibujo**:

- **Rail Model:** el larguero (un `.glb`). Va uno a cada lado, estirado hasta el alto; el de la derecha, espejado.
- **Rung Model:** el peldaño. Va uno cada **Rung Spacing**, estirado solo a lo ancho, hasta el alto de la escalera: arriba solo sobresalen los largueros (desde el 2026-10-23).
- **Tile Textures:** que la textura no se estire (la repite una vez por metro, según el lugar en el mundo; no usa el mapa UV de Blender).
- **Show Pieces:** apagado, no dibuja nada; para poner un modelo entero, hecho a mano, como hijo de la escalera.

Si dejás un modelo vacío, va una barra provisoria.

### Colisión

Desde el 2026-10-20 (lo pediste: saltando contra una escalera, uno espera chocar y no atravesarla), cada larguero y cada peldaño choca con una caja del tamaño de su dibujo. Las cajas se arman solas a partir del modelo, centradas en cada pieza: no hay que acomodar nada a mano.

- **Grupo Colisión del Inspector:** **Collides** (prendido) la prende o la apaga, por escalera. **Top Rung Depth** (0,16 m, desde el 2026-10-23, pedido tuyo): el grosor de la caja de colisión del peldaño de arriba, de adelante hacia atrás. Es donde quedás parado arriba de una escalera suelta: con la caja finita de los demás peldaños (4 cm en las escaleras sin modelos) te caías enseguida. Con 0,16 m aguantás corrido hasta unos 20 cm del centro (antes, 15). Hasta 0,16 no toca al que trepa; desde 0,2 lo roza, y más grueso el que sube choca con él y no termina de subir (con 0,3, en la escalera de 4 m se trababa a 2,25 m). En 0 queda como los demás. El dibujo no cambia.
- **Se recortan de frente:** tus modelos son gruesos (largueros de 20 cm y peldaños de 15 cm), y quien trepa va a 10 cm del eje. Las cajas llegan hasta 8 cm del eje de cada lado: el dibujo queda igual y lo que sobra no choca, así nunca rozan a quien trepa.
- **Llegan hasta el alto:** lo que sobresale arriba (los largueros siguen 40 cm, para agarrarse al salir) no choca, así se puede pasar por encima al salir.
- **Van en su propia capa de física, la 3.** Los cuerpos chocan con ella; las manos no la toman como borde (no te colgás de un peldaño) y no se sube por los peldaños como si fueran escalones. La cámara tampoco choca con ella. Cuando haya armas, los disparos pueden mirar esa capa.
- **Sin piezas** (**Show Pieces** apagado), no hay colisión: si ponés un modelo entero como hijo, con su colisión, ponela en la capa 3.

Cómo se siente, probado sin red:

- Caminando o saltando contra una escalera sin ir a agarrarla (por ejemplo, agachado), chocás.
- Caminando pegado a la pared, la escalera te corre para afuera y pasás por delante.
- Cayendo desde arriba sobre una escalera suelta, quedás parado arriba (lo elegiste así).

### De los dos lados

Desde el 2026-10-20, una escalera se trepa también desde atrás si atrás, al pie, hay lugar para el cuerpo. Se calcula sola, la primera vez que hace falta:

- **Contra una pared:** de un solo lado, como siempre. Son casi todas las de la zona de servicio, de la torre y del laboratorio.
- **Con algo arriba del lado de atrás** (un balcón, un techo, la base de un tanque): desde atrás se trepa hasta que la cabeza toca eso, y de ahí se baja con S o se salta (lo elegiste así, después de las capturas de la escalera del balcón del 53). Al subir por atrás no se llega arriba: para eso, por el frente. Son la escalera del balcón del 53, la del tanque de agua (por atrás, debajo del tanque, se sube poco) y la de la corona (por atrás, hasta el balcón del 93).
- **Sueltas, sin nada atrás:** se suben enteras por los dos lados. Son la escalera grande del laboratorio (**Ladder**, de 17 m) y la estación 6 de la pista de colgarse.

Para agarrarla por atrás a cierta altura, el cuerpo tiene que caber ahí: cayendo desde más arriba (debajo del balcón), te agarrás recién donde entrás.

**Por atrás no se agarra donde hay piso debajo de los pies** (desde el 2026-10-20, después de tus capturas de la escalera de la corona): parado en el balcón al que se sale por arriba, caminando hacia la escalera, te agarrabas de su parte de atrás. Ahora por atrás se agarra al pie (hasta medio metro sobre su base, como entrar caminando desde el suelo) o en el aire, donde debajo de los pies no hay piso. Por adelante no cambió nada.

Desde atrás todo funciona igual que de frente: agarrarse caminando o saltando hacia ella, W y S, Espacio, Ctrl, salir por arriba y colgarse del que está en la escalera, solo por su espalda. El lado no es un dato nuevo: sale de hacia dónde mira el que trepa, así que no cambió nada de lo que viaja por red.

### Cómo se juega

Las reglas, que decidiste vos, en la sección 8.21 del historial:

- **W sube y S baja,** mire donde mire la cámara; A y D no hacen nada.
- **Saliendo por arriba con W,** W va según la cámara. Solo en tercera persona y con la cámara mirando para atrás (a más de **Ladder Exit Back Angle**, 90°, de hacia donde subías) seguís derecho hacia donde subías mientras sigas con W sola, para no volver a la escalera y caerte. Soltar W, tocar A, S o D, girar la cámara hacia adelante o pasar a primera persona lo corta (pedido del 2026-10-20: la guarda servía en ese caso y molestaba en los demás). En primera persona, mirando para atrás, W te lleva hacia atrás.
- **Espacio mirándola** salta para arriba y te volvés a agarrar solo, en el punto más alto o, si pasaste el final, al volver a bajar.
- **Ctrl** te suelta sin empujón: caés mientras lo tengas y al soltarlo te agarrás. Con Ctrl no te agarrás de ninguna escalera, y con alguien colgado de vos, se caen los dos.
- **Saltando para arriba desde un borde con una escalera arriba** (como las pilastras de la torre), alcanza con mirarla para agarrarte, sin W (desde el 2026-10-21; antes, sin teclas, subías y volvías a caer al borde). En el aire, en los demás casos, para agarrarte de una escalera tenés que ir hacia ella con las teclas, como siempre. Con A o D apretada no te agarrás: apuntan a otro lado.
- **A o D cortan la vuelta sola** (pedido del 2026-10-20, después del video): si apretás A o D antes de Ctrl, al tocarlo o mientras caés con Ctrl, te soltás y no te volvés a pegar. Lo mismo en el salto para arriba: A o D en el aire y caés al costado. Con un toque corto de Ctrl sin A ni D, al soltarlo te agarrás en el acto, como siempre. Para volver a una escalera, caminá o saltá hacia ella con W.

**Desde el 2026-10-22** (pedidos después de tus videos; el detalle, en la sección 8.31 del historial):

- **Salir por arriba, sin saltito** (desde el 2026-10-23, después de tu video de las 15:46: "averigua la manera de quitar [el saltito], no importa como"): al llegar al tope seguís agarrado de la escalera y pasás al piso de arriba deslizándote, como si te treparas al rellano. Lo poco que sube va a la velocidad de trepar, y hacia adelante vas como caminando: 5 m/s, o 7,5 con el súper (Shift no cambia nada, como pediste). Al principio iba a la velocidad de trepar, 2,5 m/s, y "se sienten horribles". W avanza; sin teclas frenás como caminando y, mientras sigas colgado del borde, te quedás donde estás, todavía en la escalera; pero si el centro del cuerpo ya está sobre el piso, la escalera termina y quedás parado ahí (desde el 2026-10-28, después de tus capturas de EscaleraTirolesa: antes seguías en la escalera, parado sobre la plataforma). S te devuelve a la escalera, donde bajás a la velocidad de trepar; a toques, avanzás de a poquito. El cuerpo pasa a la altura del piso de arriba (sube 2 mm, lo justo para no rozar), y al llegar (**Ladder Top Land**, 0,4 m detrás del eje) quedás parado y quieto si soltaste W antes. Con W apretada seguís caminando sin pausa, a la misma velocidad (hasta el 2026-10-23 a la noche frenaba un instante y volvía a arrancar). Si soltás W justo al llegar, frenás como caminando, unos 24 cm más adelante; en una escalera suelta quedás parado arriba, a unos 25 cm del centro. Hasta el 2026-10-23 a la noche subía 3 cm, y al terminar se notaba la bajada ("esos 3 cm se notan"). Antes, un saltito por el aire te llevaba al rellano: el 2026-10-22, a 2,5 m/s y con W empujando en el aire; después, un saltito de 20 cm que caía justo ahí. Para que no tenga que subir más, los peldaños ya no chocan por encima del alto (como los largueros): un peldaño de tus modelos justo en el alto sobresalía 7,5 cm del piso del techo de la sala de calderas.
- **Escaleras sueltas, sin piso arriba** (como la estación 6 de la pista de colgarse y la grande del laboratorio): la salida termina con vos parado arriba de la escalera, sobre el último peldaño. Así te podés quedar parado arriba de todo. Los peldaños se dibujan solo hasta el alto (antes, el de más arriba era solo dibujo y te atravesaba, tus capturas de las 12:59 del 2026-10-23), y la caja de colisión del de arriba es más gruesa (**Top Rung Depth**, en "Colisión", arriba). En la escalera grande, el peldaño de arriba de tus modelos toca 2,5 cm la punta de abajo del cuerpo parado. Falta probarlo en las dos PC.
- **Parado en el filo de arriba no te mete en la escalera:** en el último medio metro (**Ladder Top No Grab**), parado en el piso, no te agarrás, aunque estés asomado y aprietes W hacia ella. Para bajar por la escalera desde arriba, salí del filo y, cayendo, W hacia la escalera.
- **De costado, solo cerca del centro:** te agarrás si estás a 30 cm o menos del centro de la escalera (**Ladder Grab Side**). Antes alcanzaba con estar en su volumen, hasta 30 cm más allá de cada larguero, y el cuerpo iba de golpe al centro: se veía arrastrado o teletransportado (tu video del andamio y el salto desde la pilastra del 34, debajo de una pata).
- **No te traba más contra un larguero:** si algo tapa el camino hasta tu lugar en la escalera, no te agarra. Antes, agarrado de costado, el cuerpo chocaba con el larguero y quedabas colgado al lado, sin poder subir: ese era el "atascado".

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

## 7. La zona de servicio

Un pedazo de mapa para probar todo junto, armado como un patio de servicio entre edificios (pedido del 2026-10-19). Es la escena `scenes/net_lab/zona_de_servicio.tscn`, puesta en el nivel como el nodo **ZonaDeServicio** (en z −30, del otro lado del borde norte del piso). A diferencia de las pistas, no se arma por código: cada pared, techo y caja es un nodo que se ve y se mueve en el editor.

**Cómo llegar:** desde donde aparecés, caminá derecho hacia adelante (hacia donde mira la cámara al empezar), por la izquierda del túnel violeta. A unos 40 m está el portón, entre dos faroles.

### Qué hay

| Lugar | Alto | Para qué |
| --- | --- | --- |
| Patio | 0 | Tendido de cable a 2,9 m (se agarra saltando), contenedores en L con un rincón y esquinas a 2,6 m, cajones para subir al naranja |
| Sala de calderas (a la izquierda) | 4,5 m | Escalera desde el patio; o el taller de al lado (borde de 2,5 m) y desde su techo el borde de la sala |
| Terraza de la galería (al fondo) | 7 m | Borde que se agarra desde el techo de calderas; se puede correr colgado por encima del patio y doblar la esquina del final |
| Azotea del edificio alto | 12 m | Escalera desde la terraza; tanque de agua; arranca la tirolesa |
| Depósito (a la derecha) | 6,5 m | Llega el cable del cruce a su pared; el techo es la pista para correr |
| Anexo y caseta (junto al portón) | 5 y 7,5 m | Donde se cae después del salto; desde la caseta, la bajada al patio |

Los bordes que se agarran tienen un canto de chapa ocre. Las escaleras son blancas.

### Recorrido para probar todo

1. **Entrada:** saltá debajo del tendido y agarrate; correte con A o D y soltate con Ctrl. Colgate del contenedor naranja desde el patio, del lado de los cajones, y correte con A: doblás el rincón y después la esquina del contenedor verde. Por los cajones se sube al naranja saltando.
2. **Subida:** escalera de la sala de calderas hasta el techo. Andá al fondo, mirá la pared de la galería y saltá: te colgás del borde de la terraza (7 m). Espacio mirando la pared y W para subir.
3. **Cruce:** en la punta derecha de la terraza, debajo del pórtico, el cable asoma del filo: saltá hacia él o salí caminando del filo y te agarrás. Con W, mirando hacia el depósito, cruzás el patio en unos 3 s (se mueve con las teclas, no se desliza). Al llegar a la pared, Espacio mirándola: te colgás del borde del techo. Con D te corrés colgado hasta la esquina y la doblás; subí. Desde la terraza hasta acá no se toca el piso.
4. **Carrera:** en el techo del depósito andá al fondo, date vuelta y corré (Shift) hacia el anexo. Saltá en el filo: el pasaje mide 6 m. Corriendo sobra; caminando llegás justo al filo. Si no llegás, te agarrás del borde del anexo.
5. **Vuelta:** en el anexo, colgate de la caseta (borde de 2,5 m) y subí. Salí caminando de su borde, del lado del patio, debajo del cable: te agarrás de la bajada. W mirando hacia abajo y te deslizás hasta el patio; Ctrl para soltarte. Quedás a unos pasos de la escalera de la sala de calderas, para volver a empezar.

**Otras formas:** de la terraza, en vez del cruce, la escalera a la azotea (12 m) y la tirolesa hasta el depósito (se desliza con W; Ctrl al final). Corriendo por la terraza hacia la derecha y saltando desde su punta, se llega al techo del depósito sin el cable. Si caés al pasaje, la escalera del pasaje te sube de nuevo a la pista.

**Súper salto y velocidad (2 del teclado numérico):** desde la pista del depósito, corriendo en diagonal hacia la caseta y saltando unos 2 m antes del filo, se cae directo en su techo (desde el 2026-10-22 el salto con el súper sale a 9 m/s y no a 6,5: saltando en el filo, pasás por encima de la caseta); sin el súper, se choca con su pared. Desde el contenedor naranja se agarra el borde del depósito (6,5 m), que sin el súper no se alcanza. Desde lo más alto de cada techo no se llega a los edificios vecinos: la manzana está cerrada.

### Con un compañero

El contenedor naranja está debajo de donde llega el cable del cruce, contra el depósito.

1. **A** hace el cruce y, en vez de subir, se queda colgado del borde del depósito. Con A (la tecla) se corre un par de metros hasta quedar arriba del medio del contenedor.
2. **B** sube al contenedor por los cajones, se para debajo de A y salta: se cuelga de su cintura.
3. **B** sube con W hasta los hombros de A y gira con D (o A) hasta quedar a su costado, contra la pared.
4. **B** mira la pared y salta: se agarra del borde al lado de A. Espacio mirándola y W, y sube. Después sube A.

También anda saltando desde la espalda de A, mirándolo, con W apretada. Sin A, B no llega a ese borde.

### Cambiarla

Abrí `zona_de_servicio.tscn` (doble clic en **FileSystem** → `scenes` → `net_lab`). Los nodos están por edificio: **SalaDeCalderas**, **EdificioAlto**, **Deposito**, **Anexo**, **Patio**, **Cables**, **Vecinos** y **Suelo**. Cada pieza sólida es un **StaticBody3D** con su **Forma** (la colisión) y su **Malla** (el dibujo): se mueve con el nodo de arriba, pero para cambiarle el tamaño hay que cambiar **Size** en las dos. Las tiras ocres, las ventanas y los caños son solo dibujo. Los cables y las escaleras se cambian como en las secciones 4 y 5, y se numeran solos después de todos los demás (el nodo **ZonaDeServicio** va último por nombre), así los números de antes no cambiaron.

### Lo que se probó y lo que falta

- **Sin red, con el motor y el Tuning de hoy** (una prueba de Claude, 51 de 51): cada tramo del recorrido, las otras formas, los saltos con súper, la ruta del compañero entera y que la manzana quede cerrada. Da lo mismo con el agarre desde arriba (`hang_reach_down`) prendido o apagado.
- **El laboratorio entero:** carga sin avisos; en dos copias en esta PC, el cliente entra con la misma huella. La prueba de repetición coincide, pero su huella pasó a `46a23a75b9852601`: con más cuerpos en el mundo, un salto del tramo 16 da 0,1 mm distinto (sin la zona, con el motor de hoy, da `5d3ce24d879a32db`). El barrido de bordes cumple los cuatro criterios.
- **En las dos PC** (2026-10-19): "el mapa funciona correctamente y se ve bien". Commit `8d7b0b9`. Esa prueba trajo los cambios de los cables (sección 4).
- **Falta:** la cámara en los lugares angostos (la terraza, el pasaje); y la ruta del compañero en red, que no contaste si la probaste.

### La torre de servicio (de 20 a 100 m)

Pedido del 2026-10-19: llevar la zona de servicio hacia arriba, hasta unos 100 m, sin perder lo que había. El diseño es de Claude, a pedido. Es la escena `scenes/net_lab/torre_de_servicio.tscn`, puesta en el nivel como el nodo **TorreDeServicio**, hijo de **ZonaDeServicio**: usa las mismas coordenadas que la zona, y los números de los cables y escaleras de antes no cambiaron.

El bloque que cerraba el fondo del patio (el vecino norte, 20 m) pasó a ser la **Planta Técnica**, y sobre ella hay dos torres: la **Torre Norte**, escalonada hacia el patio, con la cubierta a 100 m, y la **Torre de Tanques**, de ladrillo, de 62 m. Cada nivel tiene su número pintado en la pared. Como en la zona, los cantos ocres se agarran y las escaleras son blancas.

| Lugar | Alto |
| --- | --- |
| Planta Técnica | 20 m |
| Terraza del 34 (Torre Norte, lado este) | 34 m |
| Terraza del 46 y balcón del 53 (Torre de Tanques) | 46 y 53 m |
| Techo de los tanques | 62 m |
| Terrazas del 52, 70 y 86 (Torre Norte, lado sur) | 52, 70 y 86 m |
| Cubierta, con el mástil de luz roja | 100 m |

**Cómo llegar:** a la azotea del edificio alto (12 m) por el recorrido de la zona. Ahí, pegada al tanque de agua, está la escalera nueva.

#### Recorrido solo, del patio a los 100 m

1. **El tanque (12 → 20).** Subí la escalera del tanque. Desde la tapa, caminá o corré hacia la pared de la planta y saltá en el borde: te colgás del filo del 20. **Espacio** mirando la pared y **W** para subir.
2. **La cornisa (20 → 34).** Colgate de la torre de enfriamiento (la caja gris clara) y subí. Corré hacia la Torre Norte y saltá: te agarrás de la cornisa del 26. Con **D**, hasta la esquina: la dobla sola. Seguí con **D** por la cara este hasta la columna de ventanas. **Espacio** mirando la pared cuatro veces (marcos del 28, 30 y 32, y el filo del 34) y **W** para subir.
3. **La pasarela y la línea de vida (34 → 46).** Cruzá la pasarela al andén de la Torre de Tanques. Saltá debajo del cable que sube por la pared de ladrillo y agarrate. **W** mirando hacia donde sube (al norte). En la punta, **Espacio** mirando la pared: te colgás del filo del 46. **Espacio** y **W**.
4. **El balcón y el montante (46 → 62).** La escalera al balcón se agarra desde el norte: pasá entre el montante (la columna de caños) y la escalera, y caminá hacia ella mirando al sur. En el balcón, mirá la pared y saltá: cornisa del 56. Con **A** vas al norte y rodeás el montante solo (un rincón, dos esquinas y otro rincón). Después, **Espacio** tres veces (58, 60 y el filo del 62) y **W**.
5. **La tirolesa al 52 (62 → 52).** En el lado oeste del techo, salí caminando del filo debajo del cable. **W** mirando hacia la Torre Norte. En la punta, **Ctrl**.
6. **El andamio (52 → 70).** Colgate de la plataforma baja (de madera) y subí. Caminá hacia el este por la viga hasta la plataforma media. Subí la escalera de la torre de acceso. Desde arriba, saltá hacia el oeste a la punta de la plataforma alta. En la escalera corta, subí hasta arriba y **Espacio** mirándola: te colgás del filo del 70.
7. **El hueco de ventilación (70 → 86).** Entrá por la puerta que dice VENTILACIÓN. Subí la escalera de la caja de ventiladores. Desde arriba, saltá hacia el este a la repisa. Con **D** te corrés al sur hasta quedar enfrente de la repisa de la otra pared. **Espacio** mirando la pared de enfrente: te agarrás de esa repisa. **Espacio** mirando al este: te agarrás del cable. **W** mirando al norte hasta la punta, y **Espacio** mirando la pared norte: te colgás del borde de arriba. Subí, caminá hacia el este por el borde (tiene baranda del lado de afuera) y bajá a la terraza del 86.
8. **La corona (86 → 100).** Escalera al balcón del 93. Desde el balcón, mirá la pared y saltá: cornisa del 96. Con **A**, hasta la esquina, que se dobla sola, y seguí con **A** por la cara oeste hasta el marco. **Espacio** dos veces (98 y el filo del 100) y **W**: estás en la cubierta.

#### Con un compañero

Agarrarse del compañero sirve para estirar el alcance hacia abajo: el que ya está arriba se cuelga, y el otro se cuelga de él. En las tres, el que llega primero hizo el recorrido normal y baja a buscar al otro.

- **El callejón entre las torres (a 26 m).** A hace el tramo 2 hasta la cara este y, en vez de subir, se corre con **A** hasta el tablero eléctrico (la caja azul): dobla el rincón y la esquina y queda colgado de la cara este del tablero, arriba de los dos cajones. B sube a los cajones, salta debajo de A y se cuelga de él. Sube con **W**, gira con **D** hasta el costado de A y salta mirando la pared: queda colgado al lado. Los dos se corren con **A** hasta la columna de ventanas y suben. Desde el cajón alto, sin A, al tablero solo se llega con el súper.
- **La escalera de incendios (de 34 a 52).** A, ya en el 52, baja por la escalera del lado este. Se agarra parado en el filo, de espaldas al vacío: **S** hasta caer y **W**. Baja con **S** y, en el final, se cae y queda colgado de la pilastra de abajo, mirando la pared. B, en la terraza del 34 y con el súper prendido, salta debajo de A y se cuelga de él. Sube, gira y salta mirando la pared: queda en la pilastra, al lado de A. Después A sube primero: **Espacio** y **W**, a la escalera y al 52. B se corre colgado con **A** o **D** hasta quedar debajo del centro de la escalera y hace lo mismo (desde el 2026-10-22: al lado de A queda a más de 30 cm del centro, y de ahí la escalera ya no te agarra). B se saltea la Torre de Tanques entera. Sin compañero, ni con el súper se llega.
- **La escalera de mantenimiento (de 70 a 86).** Igual que la de incendios: A baja desde el 86 por la escalera de la cara sur hasta la pilastra, y B, en el 70 y con el súper, se cuelga de él. A sube primero y B se corre hasta el centro. B se saltea el hueco de ventilación.

#### Súper salto y velocidad

- Del cajón alto del callejón, al filo del tablero.
- **Del techo de los tanques al 52 sin la tirolesa:** corré hacia el oeste por el lado sur del techo, lejos del cable, y dejate caer sin saltar. Sin el súper caés en la terraza del 34.
- De la caja de ventiladores del hueco, directo al cable, salteando las dos repisas.
- De la plataforma alta del andamio, directo al filo del 70.

Ninguno saltea más de un pedazo de un tramo: en diez lugares se probó que, ni con el súper, se llega al tramo siguiente.

#### Caídas y vuelta

- **Si te caés, caés en lo último que pasaste:** del tramo 1 a la azotea; del 2 a la planta; del 3 al andén o al callejón; del 4 a la terraza del 46 o al balcón; de la tirolesa al 52, a la terraza del 34, al andén o al callejón; del andamio al 52; del hueco al piso del hueco (70); de la corona al 86 o al balcón del 93. Lo más lejos que se cae es a la Planta Técnica (20).
- **Bajar rápido:** desde las terrazas del sur, saltando hacia el sur, se cae de terraza en terraza. Desde la punta sur del 34 se cae a la planta. Las escaleras de incendios y de mantenimiento también sirven para bajar: al final te colgás de la pilastra, y con **Ctrl** caés a la terraza de abajo.
- **La tirolesa de regreso:** desde la cubierta, salí caminando por el filo sur, debajo del cable. **W** mirando hacia abajo: bajás hasta el techo del vecino oeste (19 m) y, cuando el cuerpo toca el techo, **Ctrl**. Desde ahí, al techo de la sala de calderas y su escalera al patio. El 2026-10-20 bajaste su punta hasta casi tocar ese techo y elegiste dejarla así: desde el techo del vecino oeste se la puede agarrar saltando cerca de la punta y subir por ella hasta la cubierta, en unos 50 s.
- Si saltás al vacío por el norte o el oeste de la planta, reaparecés al principio, como siempre al caer del mapa.

#### Cambiarla

Abrí `torre_de_servicio.tscn`. Los nodos están por edificio y tramo: **PlantaTecnica**, **AccesoAzotea** (la escalera del tanque), **TorreNorte** (**Cuerpo**, **Cornisa26**, **VentanasDeServicio**, **Terraza34**, **Terraza52**, **Andamio**, **Terraza70**, **HuecoDeVentilacion** y **Corona**) y **TorreDeTanques** (**Cuerpo**, **Pasarela**, **LineaDeVida**, **Terraza46**, **Balcon** y **Azotea**). Las piezas son como en la zona: **StaticBody3D** con **Forma** y **Malla**, y para cambiar el tamaño hay que cambiar **Size** en las dos. Las barandas son una caja sólida sin dibujo (**Forma**) más los caños, que son solo dibujo. El vecino norte, que hace de frente de la Planta Técnica, sigue en la zona.

#### Lo que se probó y lo que falta

- **Sin red, con el motor y el Tuning de hoy** (una prueba de Claude, 70 de 70):
  - cada tramo del recorrido solo, del patio a la cubierta;
  - las tres rutas de a dos, con la llegada de los dos arriba;
  - los atajos con el súper, y que sin el súper no anden;
  - los diez lugares donde no se tiene que poder saltear nada;
  - la tirolesa de regreso;
  - que se pueda estar parado en todos los lugares del recorrido;
  - que la cámara tenga lugar detrás en cada agarre: 2,3 m como mínimo, en el tablero del callejón, y 2,8 m en el hueco.
- **El resto del laboratorio:** la prueba de la zona de servicio da 60 de 60, la de repetición coincide con la misma huella de antes (`46a23a75b9852601`) y el barrido de bordes cumple los cuatro criterios (ahora tarda unos 7 minutos). En dos copias en esta PC, el cliente entra con la misma huella, sin correcciones ni adopciones, con los dos quietos donde aparecen.
- **En las dos PC** (2026-10-20): "quedo bastante lindo a construcción". Commit `b4d35cb`. Esa prueba trajo la tercera vuelta de la escalera (sección 5).
- **Falta:** ver la cámara de verdad en el hueco y en el callejón, y cuáles de las tres rutas de a dos probaste en red (no se contó).
- **Desde el 2026-10-22,** las rutas de a dos de las escaleras de incendios y de mantenimiento van con A primero y B corriéndose hasta el centro (arriba, en "Con un compañero"). La prueba sin red las recorre así: 70 de 70.

---

## 8. La pista de salto agachado

Pedida el 2026-10-22: una zona para probar saltar y agacharse en el aire. El diseño es de Claude. Agachado en el aire, la cápsula se achica desde abajo, de 1,8 a 1,0 m, con la cabeza quieta: los pies suben 0,8 m y llegás más alto que saltando parado. Agachado no te colgás de los bordes: caés arriba o chocás.

**Dónde está:** al sur del piso del laboratorio, detrás de donde aparecés (date vuelta y caminá derecho unos 25 m). Tiene su propio piso, pegado al borde del piso del laboratorio. Ahí no la cruza ninguna prueba automática y no hay cables cerca.

| Lugar | Qué hay | Cómo se sube |
| --- | --- | --- |
| Fila de adelante | Seis bloques: 1,2 · 1,4 · 1,6 · 1,8 · 2,0 · 2,2 m | Parado, el de 1,2. Agachándote en el aire, hasta el de 2,0 (justo, desde cerca). El de 2,2, ni agachándote. Desde el 2026-10-25, sin Ctrl y saltando mirándolos, el mantle te sube solo: parado, de 1,2 a 1,8 m; caminando, también el de 2,0, justo. En el de 2,2 te colgás |
| Fila de atrás, a la izquierda | Un conducto: repisa a 1,6 m y techo a 3,0 m (1,4 m de alto) | Saltá y agachate en el aire; adentro no te podés parar: seguí agachado (con **Ctrl**) hasta el otro lado y bajá. O saltá mirándolo: el mantle te sube agachado |
| Fila de atrás, al medio | Un muro de 3,6 m con una ventana de 1,8 a 3,1 m | Saltá caminando hacia ella y agachate en el aire, en cualquier momento antes de lo más alto. El mantle no: el muro es finito |
| Fila de atrás, a la derecha | Con el súper: 2,6 · 3,0 · 3,4 m | El de 2,6, parado; los otros dos, agachándote |

Cada bloque tiene su cartel. A cada cosa se entra caminando hacia el sur.

**Probado sin red** (una prueba de Claude, 15 de 15): cada bloque, parado y agachado, caminando y corriendo, desde 0,8 y 1,5 m; el conducto (se entra agachado, soltando Ctrl adentro seguís agachado, se sale por atrás; parado no se entra); la ventana (agachado se pasa en 40 combinaciones de distancia, momento y velocidad; parado, en ninguna); y los bloques del súper. Con el mantle (2026-10-25), otra prueba de Claude recorrió cada bloque, el conducto y la ventana, parado y caminando: dio lo que dicen los carteles, que desde ese día cuentan también el mantle.

**Cambiarla:** las alturas y medidas son las constantes del principio de `crouch_jump_course.gd` (**BLOCK_HEIGHTS**, **BOOST_HEIGHTS**, **DUCT_FLOOR**, **DUCT_CEILING**, **WINDOW_Y** y las demás). Como las pistas, se arma por código: las piezas no se guardan en la escena. El nodo **PistaDeSaltoAgachado** se mueve en el editor.

---

## 9. El mantle

Pedido el 2026-10-25 (hasta ese día estaba fuera del alcance). Cómo funciona lo decidiste vos, pregunta por pregunta; los números los eligió Claude y están en el **Tuning**, grupo **Mantle** (sección 3). El detalle, en la sección 8.33 del historial.

**Cómo se hace:** saltá mirando un borde con el filo entre 0,3 y 1,5 m por encima de tus pies. Mientras subís en el salto, cuando las manos llegan al filo, el cuerpo sube solo, pegado al filo, y pasa arriba deslizándose, sin saltito, como en la salida por arriba de la escalera. No tiene tecla. En el panel, **Modo** dice **MANTLE**, con el alto del filo.

- **Hacia dónde:** sin teclas, derecho hacia adentro, y quedás quieto 45 cm detrás del filo. Con teclas, hacia donde apuntan según la cámara, hasta 45° de costado, mirando hacia allá, y apenas quedás arriba seguís caminando (lo pediste el 2026-10-25, después de probarlo solo: antes iba siempre derecho contra la pared).
- **Agachado:** si arriba solo cabés agachado (el conducto de la pista de salto agachado), subís agachado y seguís así hasta que haya lugar para pararte.
- **Con el colgado:** con el filo a la altura del pecho, si arriba hay lugar, subís en vez de colgarte. Con el filo a más de 1,5 m sobre tus pies, te colgás como siempre.
- **Cuándo no hay mantle:** cayendo, apretes lo que apretes (te colgás como siempre); sin haber saltado (bajar de espaldas, soltarte con Ctrl, un empujón); con **Ctrl** apretado; mirando de costado; delante de una escalera; si arriba no hay piso donde quedar parado (un muro finito, una baranda: chocás, y así la baranda del pasillo del 86 de la torre de servicio ya no te tira al vacío); y si el salto ya te lleva los pies por encima del filo (caés arriba solo).
- **A mitad de camino,** **Ctrl** te suelta, y un empujón fuerte también.
- **Con el súper,** todo 1,5 veces más rápido.

**Dónde probarlo:** en la pista de salto agachado (sección 8), con los carteles; en la pista de bordes, el bloque de 2 m caminando y saltando a un metro y pico; y el bloque con el cartel "sobre una plataforma guionada", que va y viene.

**Medido:** parado frente a un bloque, hay mantle hasta 1,9 m; caminando y saltando, hasta 2,0 m, justo; en 2,2 m te colgás. Un mantle de 1,6 m tarda unos 0,6 s.

**En red:** 0 correcciones, también con internet mala, en un bloque fijo y en la plataforma guionada. Sobre el bloque que mueve solo el host (la balsa del borde), con internet mala, correcciones chicas (21 cm como mucho), parecidas a las de colgarse de ese mismo bloque. El 2026-10-30 elegiste sumarlo a lo que depende de un buen internet (sección 11). Lo probaste en las dos PC el 2026-10-28: "no encontré ningún bug o rareza relacionada con el mantle". Commit `eb473ca`.

**Para Claude, la prueba automática en pareja:** `--test-input=mantle` (o `mantle:4`, en la plataforma guionada) hace mantles en ciclos contra el bloque de 2 m de la pista de bordes, uno de cada dos en diagonal con D.

**Para Claude, la prueba sin red:** `scenes/net_lab/mantle_test.tscn` (desde el 2026-10-30) corre 50 casos, cada uno con lo que tiene que pasar según lo que decidiste: si hay mantle, dónde termina (arriba, colgado o abajo), parado o agachado, hacia qué lado, y que Ctrl y un empujón fuerte lo corten. Falla sola si un caso da otra cosa. Usa los valores del **Tuning**: si cambiás la franja del mantle o la altura del salto, puede fallar sin que haya un error, y Claude te dice qué caso cambió.

---

## 10. Cómo trabajamos (reglas acordadas)

- **Godot cerrado antes de que Claude toque el nivel o `project.godot`.** Si está abierto, al guardar puede pisar el cambio. Claude avisa cuando hace falta cerrarlo; si Godot pregunta si guardar, a veces la respuesta es **No guardar**, y Claude lo dice.
- **El commit local va después de una prueba en las dos PC que sale bien,** sin esperar a que lo pidas (decidido el 2026-10-17: "seguí así, commit después de una prueba que sale bien"). Es local, en la rama `net-lab`; a GitHub se sube solo si lo pedís. Los md se commitean cuando lo pedís.
- **`project.godot` va entero al commit desde el 2026-10-31:** hasta ese día, la línea del editor que pasa de 4.6 a 4.7 quedaba afuera; ese día elegiste commitearla, porque las dos PC usan Godot 4.7.2.
- **Los valores ajustables van en el nodo Tuning,** para que los cambies vos en el Inspector.
- **Instrucciones clic por clic,** con los nombres exactos de los botones. Tu Godot está en inglés.
- **Lo que decidís vos y lo que propone Claude se anota por separado,** y antes de sumar algo que no pediste, Claude pregunta.
- **Nada se afirma sin probarlo;** si algo sale de leer el código y no de una prueba, se dice.
- **El doble clic de la notebook se hace cuando Claude avisa que algo está listo,** no mientras cambia archivos.
- **Los poderes van en el teclado numérico** (1 y 2 usados; del 3 en adelante, libres), como acciones del Mapa de entrada.
- **Todo lo que te escribe Claude va en español,** también los avisos entre pasos.
- **Cuando Claude te nombra un archivo,** te dice qué es y si tenés que hacer algo con él.
- **Las pruebas automáticas:** cinco están en el proyecto: la de repetición, el barrido de bordes, desde el 2026-10-30 la del mantle y la del agarre con las manos por encima del filo, y desde el 2026-11-02 la de los estados (`estados_test.tscn`, sección 15). Las del inventario y del panel Objetos están en sus carpetas (sección 14). La de repetición, desde el 2026-10-19, también falla si su recorrido deja de pasar por alguna mecánica (por ejemplo, porque un valor del Tuning lo desvió del cable); desde el 2026-10-30, el mantle tiene que terminar arriba, no alcanza con empezar. El barrido, desde el 2026-10-30, tiene un quinto criterio para los agarres desde arriba: el dibujo baja a **Hang Drop Speed** y la cámara no se mueve más que eso. Las demás (`diag_*.gd` y las pruebas en pareja) Claude las arma en una carpeta temporal que se borra; están copiadas enteras en el Apéndice B del historial, para volver a correrlas.

---

## 11. Lo que conviene recordar

- **Mecánicas que dependen de un buen internet** (se pide menos de 140 ms y poca pérdida): las correcciones de la balsa al subirse o saltar arriba, la demora de la cámara lenta (0,1 s en la red de la casa, hasta 0,33 s con internet mala) y, desde el 2026-10-30, las correcciones del mantle sobre la balsa del borde (21 cm como mucho, con internet mala).
- **La cámara lenta es de cada uno** (desde el 2026-11-02): el 1 del teclado numérico pide o suelta la tuya, y el mundo va lento mientras alguno la pida. Hasta ese día, la pulsación de cualquiera apagaba la del otro. Cada uno paga la suya con su estamina (sección 15).
- **Si se va el host, se termina la partida:** no hay migración de host. Si a un cliente se le corta la red, el host lo espera hasta 60 s.
- **Cables y escaleras están fijos:** no se mueven ni se balancean. Sus números salen de su lugar en la escena, así que no se pueden agregar ni sacar en pleno juego sin cambiar eso.
- **El laboratorio no es el juego.** Antes de pasarlo al juego queda pendiente el punto 4 de la revisión externa: sacar las reglas que hoy están en `net_lab.gd` a una pieza propia (sección 8.12 del historial).
- **El muro de 3,6 m de la torre se sube solo desde el cajón,** aunque el cartel diga "con un compañero". Quedó así a pedido.
- **Las capturas de la notebook** también van a la carpeta de capturas.
- **Saliendo derecho de una escalera** (solo en tercera persona y mirando para atrás), girar la cámara hacia los costados no hace doblar; hacia adelante, sí: ahí se corta la guarda.
- **Cuando el de arriba se suelta con alguien colgado,** el que cuelga recibe una corrección por caída, porque ve al de arriba con atraso. Es normal, también en el muro.
- **Colgándose de uno que todavía se mueve,** el host puede adoptar diferencias de 1 mm de lo que afirma el que se cuelga, porque su PC ve al de arriba en el pasado. No hay corrección.
- **Los números de cables y escaleras cambian si una pista nueva va antes en la escena:** con la pista de colgarse, la huella de la prueba de repetición pasó de `cb02d3f0640600f9` a `64564ccef7594dba`, sin que cambiara el movimiento.
- **Saltar de un borde no te deja agarrarte de un cable por 0,3 s;** del cable al borde, sí (desde el 2026-10-18, para cortar el bucle entre los dos). Entre un compañero y un cable, 0,3 s para los dos lados (desde el 2026-10-19, por el mismo motivo).

- **Para jugar a distancia, los dos con el mismo `.exe`** (sección 2): cada cambio de código o de valores pide exportar de nuevo y mandarlo. Si tu amigo tiene uno viejo, el host no lo deja entrar.
- **El agarre con las manos por encima del filo** (sección 3) estuvo sin commit del 2026-10-19 al 2026-10-30: estuvo en todas tus pruebas desde entonces, aunque nunca se probó aparte, y el 2026-10-30 elegiste commitearlo así (`a257e4b`). Desde ese día tiene su prueba fija, `grab_above_test.tscn`.
- **Caerse de un borde sin saltar** (desde el 2026-10-22): sin apretar nada, frenás en el aire y caés casi derecho, pegado al borde. Con las teclas apretadas seguís de largo, y saltando no cambia nada. Desde algo que se mueve (el vagón, la balsa) no frena: te llevás su velocidad. Lo que queda es la punta redonda de la cápsula resbalando por el filo al empezar a caer, unos 10 cm.
- **El súper multiplica todo por 1,5** (desde el 2026-10-22), también el tope del salto: corriendo con el súper saltás a 9 m/s, no a 6,5. Por eso el atajo a la caseta de la zona de servicio sale saltando antes del filo.
- **Agacharse corriendo** es el deslizamiento: de 8 m/s a 2,5 en 1,4 s, unos 7 m, y después seguís agachado a 2,5. El 2026-10-22 elegiste dejarlo así.
- **Un filo necesita lugar libre encima** (desde el 2026-10-27, después de tus capturas de la torre de parkour): la unión de dos cajas apiladas en una pared lisa ya no es un borde del que colgarse (antes, en el núcleo de la torre, te colgabas a 7 y a 10,2 m). Al armar niveles: si apoyás algo de más de 5 cm de alto a ras del filo de un borde, ese borde tampoco se agarra.
- **La salida por arriba de la escalera** (desde el 2026-10-28): si frenás con el cuerpo ya sobre el piso, la escalera termina y quedás parado; si frenás todavía colgado del borde, seguís en la escalera.
- **El mantle sobre el bloque que mueve solo el host,** con internet mala, da correcciones chicas, como colgarse de él. Desde el 2026-10-30 está en la lista de lo que depende de un buen internet (arriba): se te preguntó y elegiste sumarlo.
- **El caso de tu video del 2026-10-19** (pared de 2,5 m, saltando corriendo a 2,9 m) hoy es un mantle, no un agarre: llegás subiendo con el filo a la altura del pecho, y así lo decidiste el 2026-10-25. El agarre con las manos por encima del filo sigue en paredes más altas que el pecho, por ejemplo una de 2,8 m.

La lista completa de pendientes y límites está en la sección 16 del historial.

---

## 12. Dónde está cada tema en el historial

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
| La segunda revisión de GPT: la huella con el personaje, quién cuelga de quién, la escalera escalada y la cobertura de la repetición | 8.23 |
| El agarre con las manos por encima del filo | 8.24 |
| La zona de servicio | 8.25 |
| Los cables más rápidos, el impulso y el súper; el bucle entre el compañero y el cable | 8.26 |
| F1, que oculta el panel | 8.27 |
| La torre de servicio | 8.28 |
| La escalera: la salida derecha en tercera persona, la colisión, los dos lados, A o D, por atrás con piso y desde un borde; los commits parciales | 8.29 |
| Exportar y jugar a distancia | 8.30 |
| La escalera, cuarta vuelta (salir por arriba, la punta, de costado, la traba y las sueltas); el súper; la velocidad terminal; el saltito al borde; el deslizamiento; la pista de salto agachado | 8.31 |
| El súper en todas las velocidades | 8.32 |
| El mantle | 8.33 |
| La unión de dos cajas apiladas, que se tomaba como un filo | 8.34 |
| La salida por arriba de la escalera: frenando ya sobre el piso, termina | 8.35 |
| La auditoría de GPT del parkour: qué era cierto, las pruebas fijas del mantle y del agarre desde arriba, y el commit de la 8.24 | 8.36 |
| El código hoy: archivos, funciones, formatos de red, constantes, valores del Tuning | 9 |
| Cómo usar el laboratorio: menú, teclas, panel, pruebas, el nivel | 10 |
| Todas las pruebas y sus resultados | 11 |
| Cosas de Godot y Jolt que se comprobaron | 12 |
| Errores y cómo se resolvieron | 13 |
| Decisiones y forma de trabajo | 14 |
| Commits | 15 |
| Pendientes y límites | 16 |
| Los scripts de las pruebas | Apéndice B |
| El inventario de grilla (en el historial, lo que toca a la red; el detalle, en `inventario_de_grilla.md`) | 8.37 |
| El panel Objetos | 8.38 |
| La salud, la estamina, los estados y el HUD; la cámara lenta de cada uno | 8.39 |
| El daño en el tiempo | 8.40 |
| Usar, recoger y soltar sin esperar al host | 8.41 |
| La auditoría de GPT del inventario, la salud y la red | 8.42 |

---

## 13. Dónde quedó (2026-11-04)

- **Los arreglos de la auditoría de GPT** del inventario, la salud y la red (2026-11-04, a la noche; sección 13 de `hud_salud_estamina_y_estados.md`): cada uso llega al host aunque se pierda un tick, el host hace recoger, soltar y usar en el orden en que los hiciste, la grilla que ves sigue ese orden, la muerte gana a Kp 1 y Kp 2 en el mismo tick, y las pruebas de red ya no dan bien si se les acaba el tiempo. Probados en esta PC y por vos en las dos PC, con Alt + 4 (en cuatro pasos de a uno): funciona. En la notebook hace falta `actualizar_lab.bat`, porque cambió lo que viaja en el input. Con tu "Sí, commitealo": el código y las pruebas en `d806bdc`; los md del día (también el historial, en su decimoséptima versión) y el informe de GPT en `f156e09`; y sus hashes, en el commit siguiente. Solo locales.
- **Usar y recoger sin esperar al host** (sección 15), del 2026-11-04: lo probaste en las dos PC con +200 ms ("funciona correctamente") y quedó en el commit local `c392774`, solo el código. Los documentos de ese día fueron a `f156e09`.
- **Soltar sin esperar al host** (sección 15), del 2026-11-04: lo probaste en las dos PC y funciona; commit local `2cf8fb1`. El arreglo del aviso de tu captura 1084, en `858df9a`. Los documentos de ese día fueron a `f156e09`.
- **Commits del 2026-11-04,** cuando pediste el commit después de probar en red (solo locales, sin subir):
    - `593b325`, la salud, la estamina, los estados, el HUD, la cámara lenta de cada uno, los consumibles y el daño en el tiempo (sección 15);
    - `9a7219f`, el panel Objetos entero, con sus burbujitas de ayuda (sección 14);
    - `0072b36`, sus documentos y esta guía.
- **En GitHub** sigue hasta `48e666b` (el inventario del 2026-11-01).
- **Commits del 2026-11-01,** cuando pediste "Sí, commitealo", después de probar el inventario ("todo funciona correctamente"). Subidos a GitHub cuando pediste "Sí, subilo".
    - `12fa57b`, el inventario de grilla entero (sección 14): su código, la zona, los objetos, la caja, sus pruebas y los cambios en `net_lab.tscn`, `net_lab.gd`, `lab_camera.gd`, `net_session.gd`, `sim_fingerprint.gd` y `project.godot`;
    - `ca2186d`, su documento (`inventario_de_grilla.md`), tu pedido original (`prompt_claude_inventario_grilla.md`) y la sección 14 de esta guía;
    - y el de esta puesta al día de la guía.
- **Antes** (2026-10-31), cuando pediste "hace un commit de todo lo que falta hacerle y finaliza con un push al repositorio":
    - `33aaf32`, lo que quedaba del laboratorio: la exportación para jugar a distancia (sección 2), las IP del menú, F1, el uid del nivel y `project.godot` con la línea de Godot 4.7; sin la prueba a distancia con tu amigo, que sigue pendiente;
    - `843acde`, las texturas de los modelos de `assets/models`;
    - `98645dc`, los md de diseño de `docs/parkour`, la investigación del parkour y los tres informes de GPT;
    - y el de esta puesta al día de la guía y el historial.
- **Antes,** `a257e4b` (2026-10-30 a la tarde), después de la auditoría de GPT del parkour (sección 8.36 del historial): el agarre con las manos por encima del filo, que elegiste commitear sin una prueba aparte, y las pruebas: el criterio 5 del barrido, el mantle terminado en la repetición y las dos pruebas fijas nuevas (sección 1). La guía y el historial de esa tarde, en `a0427b8` (2026-10-31).
- **Antes,** `e0eeb88`, la guía y el historial del mediodía (2026-10-30), y `fde8f9a` (2026-10-30), frenando en la salida por arriba de la escalera con el cuerpo ya sobre el piso, termina; y `eb473ca` (2026-10-28), el mantle y la unión de dos cajas apiladas. Los dos, después de tu prueba en las dos PC.
- **Antes,** `d846680` (2026-10-24), la guía y el historial; `3fae993` (2026-10-24), el súper en todas las velocidades; y `1324a69` (2026-10-23 a la noche), lo del 2026-10-22 y la escalera del 2026-10-23, cada uno después de tu prueba en las dos PC.
- **Los commits del 2026-10-19 al 2026-10-21** (secciones 8.23 a 8.29 del historial), cada uno después de tu prueba en las dos PC:
    - `b3a4f80`, los arreglos de la segunda revisión de GPT;
    - `8d7b0b9`, la zona de servicio (sección 7);
    - `3d98ffe`, los cables más rápidos, con impulso y súper, y sin el bucle con el compañero (sección 4);
    - `b4d35cb`, la torre de servicio (sección 7);
    - `00e1d78`, la salida derecha de la escalera solo en tercera persona y mirando para atrás (sección 5);
    - `c588cfa`, las escaleras con colisión y de los dos lados, con tu tirolesa de regreso y las dos escaleras de a dos de la torre corridas 6,5 cm hacia la pared (sección 5);
    - `fccb2b0`, A o D cortan la vuelta sola (sección 5); además repara dos líneas que habían quedado fuera de lugar en `00e1d78` y `c588cfa` (en tu disco estaban bien);
    - `5469f78`, por atrás no se agarra la escalera donde hay piso debajo de los pies (sección 5);
    - `2a7e78f`, saltando para arriba desde un borde, mirar la escalera alcanza (sección 5);
    - `1324a69`, lo del 2026-10-22 y la escalera del 2026-10-23;
    - `3fae993`, el súper en todas las velocidades (sección 3).
- **En GitHub:** `net-lab` subida el 2026-11-01, con el inventario y esta puesta al día. Antes, el 2026-10-31, hasta `2f809c3`. Antes, el 2026-10-24, hasta `d846680`, y el 2026-10-18, hasta `1dfb1e3`.
- **La prueba de repetición** coincide. Desde el 2026-10-28 su huella es `7d3d417dd954d05b`: un tramo nuevo, antes del último, sube la escalera de la torre chica y frena en la salida por arriba con el cuerpo ya sobre la torre. Del 2026-10-25 al 2026-10-28 fue `560b7d53f2c117c1`, con el mantle (un salto parado frente al techo del túnel corto); la primera versión del mantle dio `0632c924e6de2955`. Desde el mantle, sus aproximaciones al colgado saltan pegadas a la pared, y con o sin el agarre con las manos por encima del filo da lo mismo. Desde el 2026-10-30 pide además que su mantle termine arriba; la huella no cambió. Antes, con lo que tenías en el disco, era `efb6d76da57d9ecd` desde el 2026-10-23 a la noche, por la salida por arriba a la altura del piso y sin pausa al terminar (su recorrido sale por arriba de la escalerita de la plataforma). El súper en todas las velocidades (2026-10-24) no la cambió: el recorrido no trepa ni se cuelga con el súper prendido. Sin el agarre con las manos por encima del filo (commiteado el 2026-10-30), da `e2f77d3eccd297c6` (lo que tiene `1324a69` solo). Un rato antes, todavía con la pausa, fue `8fef544164401d4f`. Esa tarde, con la salida hacia el rellano como caminando y 3 cm más arriba, fue `2a4b315010b9405b`. Un rato antes, con la salida sin saltito a la velocidad de trepar, fue `ccc95b9ae1765ef7`. Del 2026-10-22 al 2026-10-23 fue `025fb3508b46734d` (el súper nuevo, el freno al caerse de un borde y su salto del súper movido al tick 38); antes, `c06785573be6cf66`.
- **Lo del 2026-10-22** (sección 8.31 del historial): la escalera sin empujón arriba, la punta, de costado y sin trabas; el súper por 1,5 en todo; la casilla de la velocidad terminal; el freno al caerse de un borde; y la pista de salto agachado. Lo probaste en las dos PC a las 20:37: "todo funciona correctamente", salvo la salida por arriba de la escalera suelta, que te dejaba caer del otro lado. Arreglada a las 20:50 (sección 5). En tu prueba del 2026-10-23 quedabas parado arriba, pero te atravesaba el peldaño de más arriba, que era solo dibujo: desde entonces los peldaños llegan solo hasta el alto. Probado sin red. El 2026-10-23, además: el grosor del peldaño de arriba (**Top Rung Depth**) y la salida por arriba sin saltito, pasando al rellano agarrado de la escalera (sección 5). Probado en las dos PC el 2026-10-23 a la noche ("perfecto, ahora funciona perfectamente") y commiteado en `1324a69`; el 2026-10-24, "hice las pruebas en red, funciona correctamente todo".
- **Lo del 2026-10-24** (sección 8.32 del historial): el súper en todas las velocidades, también la escalera (sección 3). Probado en las dos PC, en casa ("todo funciona correctamente"), y commiteado en `3fae993`.
- **Lo del 2026-10-25 al 2026-10-28** (secciones 8.33 a 8.35 del historial): el mantle (sección 9); la unión de dos cajas apiladas, que ya no es un filo (sección 11); y la salida por arriba de la escalera, que termina si frenás con el cuerpo ya sobre el piso (sección 5). El mantle y las cajas, probados en las dos PC el 2026-10-28 y commiteados en `eb473ca`; la escalera, probada el 2026-10-30 ("funciona correctamente") y commiteada en `fde8f9a`.
- **Sin commit:** nada del laboratorio desde `d806bdc` y `f156e09` (2026-11-04, a la noche). `docs/net/auditoria_parkour_2026-10-30.md` aparece borrado en tu disco, pero sigue en el repositorio: el borrado no es de Claude y no entró en ningún commit. Quedan sin seguir, porque elegiste dejarlos afuera, `tmp/` (la copia del código y los logs de las revisiones de GPT), `archive/` (logs viejos de pruebas) y un `.TMP` que dejó el editor; y también `output/pdf/`, los PDF del diseño del Parkour V2, que no estaban en la lista.
- **Pendientes:** la prueba a distancia con tu amigo (con un `.exe` nuevo; las del 2026-10-24 fueron en casa); ajustar jugando los números del mantle, si hace falta (los eligió Claude); seguir probando si el cilindro es muy permisivo, con más escenarios; la cuerda con la cámara ("no lo vamos a tocar ahora"); las pruebas de empujones al que cuelga de un compañero, que ya no llegan a colgarse (de antes, sin investigar); el punto 4 de la revisión externa, para cuando pase al juego; y de la auditoría de GPT, endurecer la validación del host solo si algún día importan los tramposos (entre amigos no hace falta). De la auditoría del inventario (2026-11-04), para cuando haya partidas largas o mapas grandes: resumir el historial viejo de la cámara lenta sin mover las plataformas (ESC-02), y medir cuánto ocupa cada paquete del inventario antes de grillas o mapas con muchos objetos (lo que quedó de ESC-01). La lista completa, en la sección 16 del historial.

---

## 14. El inventario de grilla

Pedido el 2026-10-31 (`docs/net/prompt_claude_inventario_grilla.md`), hecho desde cero: no usa el inventario anterior. Todo el detalle (arquitectura, quién valida qué, cómo crear objetos y cajas, pruebas y límites) está en [`inventario_de_grilla.md`](inventario_de_grilla.md).

- **Dónde probarlo:** la **Zona de inventario**, pasando el borde este del piso (a la derecha de donde aparecés, unos 30 m), con dos cajas y objetos en el piso.
- **Teclas:**
    - **Tab** abre y cierra el inventario (el mundo no se pausa).
    - **E** recoge o abre lo que estás mirando; con una caja abierta, la cierra.
    - Un **clic** agarra un objeto y otro **clic** lo deja (también afuera de los paneles: al piso, aunque sea de la caja).
    - **R** gira 90° lo que tenés en la mano, alrededor del centro de la celda por donde lo agarraste: cuatro posiciones.
    - Con la mano vacía, el cursor sobre un objeto muestra su nombre.
    - El **clic derecho** con algo en la mano deja una unidad en una grilla; sin nada en la mano, abre el menú.
    - **1** a **9** y **0** usan o equipan.
- **Lo que decidiste vos:**
    - La simulación de internet pasó a **Alt + 1 a 5**.
    - **E** es interactuar; los empujones del host pasaron a **Y** y **U**.
    - Tras tu prueba del 2026-10-31: clic en vez de arrastrar, clic derecho por unidad, soltar desde la caja, cuatro giros y el banquito girable.
    - Tras tu segunda prueba, el mismo día: el giro alrededor del centro de la celda agarrada (tu dibujo), el nombre al pasar el cursor y E para cerrar la caja.
    - Se agarra o se abre solo lo que mirás. En tercera persona, además, tiene que estar adelante del cuerpo: es tu idea del cono, con la mira que arranca en la cabeza, que propuso Claude.
    - Tras tu tercera prueba (2026-11-01): con un objeto en la mano, su lugar de antes queda vacío, sin "recuerdo".
    - Para crear objetos sin hacerlo a mano, un panel en el editor (2026-11-01): la pestaña **Objetos**, al lado del **Inspector**, ya activada en `project.godot` (si no aparece: **Project** → **Project Settings…** → **Plugins** → **Objetos del inventario**). Su segunda versión, del mismo día:
        - Crea, edita y duplica ítems y contenedores, con vista previa.
        - Se buscan por nombre, ID o archivo (el buscador de arriba).
        - La miniatura del inventario se acomoda con el mouse (girar, correr, acercar) o con botones como **De frente** (tus capturas del 2026-11-01).
        - **Guardar** y **Colocar en la zona** van por separado: colocar deja la zona sin guardar (Ctrl+S).
        - Desde el 2026-11-02, lo que explica cada campo está en su **?**, al lado del nombre: un clic abre la explicación. A la vista quedan solo los avisos.
        - Cómo usarlo, en la sección 4 de `inventario_de_grilla.md`.
    - La física de los objetos sueltos queda para más adelante. Mientras tanto, solo se suelta con piso hasta 1,5 m debajo de los pies: colgado de un cable dice "No hay lugar cerca para soltarlo".
- **Los valores:**
    - En el nodo **Inventario** de `net_lab.tscn`: la grilla del jugador (12 × 16), los alcances y el grupo **Mirar**. **Look Cone Degrees** (75°) es el cono de la tercera persona; **Aim Margin**, cuánto se perdona al apuntar.
    - El tamaño de las celdas, en **Hud → InventarioUI**.
    - Los de cada caja, en la caja; los de cada objeto, en su `.tres`.
- **La huella** tiene una quinta parte, "el inventario": si las dos PC no tienen los mismos objetos, cajas o valores, la notebook no entra.
- **Probado** con pruebas automáticas, en un proceso y con tres procesos en esta PC (con internet simulada, un corte y uno que entra tarde). **Falta** tu prueba jugando, con el mouse y mirando con la cámara de verdad, y en las dos PC. *(Escrito el 2026-11-01; ese día y el anterior lo probaste jugando, y el 2026-11-04 usaste, recogiste y soltaste en las dos PC.)*
- **Auditoría de GPT** (2026-11-04, a la noche): el host hace recoger, soltar y usar en el orden en que los hiciste, y la grilla que ves también. Un modelo con scripts no se usa como apariencia: se ve la caja de su color y se avisa. Detalle en `inventario_de_grilla.md` y en la sección 13 de `hud_salud_estamina_y_estados.md`.

---

## 15. Salud, estamina, estados y el HUD

Pedido el 2026-11-02 (`docs/net/prompt_claude_hud_salud_estamina_y_estados.md`). Todo el detalle está en [`hud_salud_estamina_y_estados.md`](hud_salud_estamina_y_estados.md): qué decidiste vos y qué eligió Claude, arquitectura, archivos, pruebas y límites.

- **El HUD:**
    - abajo a la izquierda, la salud (de 0 a 10), la estamina (de 0 a 200) y el termómetro (100 fijo, todavía no mide la luz);
    - arriba, una luz por cada estado tuyo prendido;
    - la luz naranja de la salud está apagada: es para la futura integridad del cuerpo.

    Es solo dibujo: no toma el mouse ni el teclado. Se dibuja por código, sin las fotos del concepto.
- **La salud:** cada jugador tiene 100 puntos. No vuelve sola: la cambian los consumibles. Al llegar a 0, muerte de prueba:
    - aparece "Moriste";
    - se apagan tus estados;
    - la salud vuelve al máximo;
    - seguís en el mismo lugar, con tu inventario y tu estamina.
- **La estamina:** 200, no vuelve sola, solo con consumibles. Correr, saltar y trepar no gastan.
- **Los estados gastan mientras están prendidos:**
    - el súper (2 del teclado numérico), 5 por segundo de fábrica;
    - tu pedido de cámara lenta (1), 8 por segundo de fábrica;
    - con los dos, la suma.

    Desde el 2026-11-02 los tenés en 0,8 cada uno: el gasto es 0,8 o 1,6 por segundo.

    Sin estamina se apagan todos juntos, con un sonido. Con 0 no se prende nada.
- **La cámara lenta es de cada uno:**
    - el mundo va lento mientras al menos uno la pida, igual de lento con uno o con varios;
    - cada uno paga la suya;
    - si uno la suelta, se queda sin estamina o muere, sigue mientras otro la pida.
- **Los consumibles:**
    - en la zona de inventario, una tercera columna nueva: **Botiquín** (cura 50), **Bebida energética** (+100 de estamina), **Frasco de veneno** (−40) y **Cápsula letal** (te mata);
    - la **Botella de agua** ahora cura 25;
    - en el panel **Objetos**, **+ Consumible** tiene **Efecto en la salud (puntos)**, **Recupera estamina** y, desde la tarde, **Daño en el tiempo (puntos)** con **En cuántos segundos**.
- **El daño en el tiempo** (2026-11-02, a la tarde; sección 11 del documento):
    - quita salud de a poco, parejo, hasta terminar o hasta que morís;
    - se acumulan, cada uno con su ritmo, hasta 4 a la vez;
    - con la cámara lenta va más despacio;
    - lo decidiste vos.
    
    Para probarlo, la **Toxina lenta** de la zona (20 en 4 s).
- **Los valores:**
    - en el nodo **Tuning**: grupo **Salud y estamina** (**Health Max**, **Stamina Max**), **Slow Stamina Cost** (en **Cámara lenta**) y **Boost Stamina Cost** (en **Súper salto y velocidad**);
    - en el nodo **Hud → Instrumentos**: el tamaño, la duración del aviso de muerte y el sonido.
- **Si se te corta la conexión,** el host te apaga los estados mientras te espera (elección de Claude): no gastás ni sostenés la cámara lenta de los demás.
- **Usar, recoger y soltar sin esperar al host** (2026-11-04, pedido tuyo; sección 12 del documento):
    - un consumible ya no se le pide al host: va en el input, como Kp 1 y Kp 2, y tu PC y el host lo aplican en el mismo tick. La unidad se ve gastada en el mismo cuadro, y la salud cambia en el tick siguiente;
    - lo que recogés se ve en tu grilla en el mismo cuadro y deja de verse en el piso;
    - si el host dice que no, se deshace solo y sale un aviso;
    - soltar, después de tu prueba: tu PC elige el lugar con la misma regla que el host y lo dibuja ahí ya, y el host lo deja en ese lugar si sirve;
    - desde el host, recoger y soltar se ven con la misma demora: medido con +200 ms en las dos, entre 232 y 240 ms. **Soltar** del menú sale al soltar el clic y la E al apretarla; esa es la única diferencia.
- **Probado** sin red y en trece casos con host y cliente en esta PC, también con internet mala, y en la prueba de usar, recoger y soltar (`inventario/pruebas/inv_instant_test.tscn`). Hoy, con los arreglos de la auditoría: estados 129 de 129 y esa prueba 83 de 83 (antes, 104 y 69). Tus pruebas en las dos PC del 2026-11-04 salieron bien: la del uso sin esperar, con +200 ms en las dos, la de soltar y la de los arreglos de la auditoría.
- **Los arreglos de la auditoría de GPT** (2026-11-04, a la noche; sección 13 del documento):
    - cada uso viaja hasta que el host lo contesta, y el host contesta uno por uno: si se pierde el tick de uno, no se pierde el uso;
    - el host hace recoger, soltar y usar en el orden en que los hiciste: recoger algo y usarlo enseguida ya no termina en "No se usó";
    - si morís en el mismo tick en que apretás Kp 1 o Kp 2, la muerte gana y quedan apagados;
    - la barra rápida respeta el "esperando…" igual que el menú.

    Probado en esta PC: estados 129 de 129, modelo 91 de 91, usar y recoger en red 83 de 83 (también con 300 ms y 8 % de pérdida), y lo de antes igual. Lo probaste en las dos PC el mismo día: funciona.
- **El aviso de tu captura 1084** (una variable `stack` repetida en `inv_replica.gd`) está arreglado en `858df9a`. Cargando con el depurador los scripts de estos días, no queda ningún aviso.
- **La cámara "todavía más lenta"** que viste con dos jugadores no se pudo reproducir con el código de antes. Lo que sí pasaba era que el segundo, al pedirla, la apagaba. Detalle en la sección 7 de ese documento.
