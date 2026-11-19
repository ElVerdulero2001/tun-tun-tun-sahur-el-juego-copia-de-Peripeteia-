# Pista de objetos · primera integración piloto en el laboratorio

**Entrega del 18 de noviembre.** El invitado puede soltar o lanzar la caja durante la recuperación. Mientras los estados del host superen la ventana de 48 ticks, el invitado dibuja la caja suelta con los estados recibidos y la caja en mano en su propia mano, y espera a recuperar la predicción para un nuevo agarre. El lanzador graba un diagnóstico por PC desde el arranque de la partida.

## Ventana de 48 ticks y caja en la mano al recuperar (18 de noviembre, noche)

**Lo que se vio en las dos notebooks.** Con los dos en Alt+4, la caja en mano del invitado iba muy atrás de la cámara. El host la veía bien. Según los dos JSONL de esa partida, mientras el invitado predice la caja no se atrasa con ninguna combinación de Alt (0 ms, medido cada 33 ms). El atraso aparecía solo en «recuperando»: los estados del host llegaban con 35 ticks de mediana y hasta 40, más que los 32 que el invitado podía rehacer. Entonces la caja se dibujaba donde la tenía el host unos 37 ticks antes (unos 0,6 s). Con el invitado en Alt+4 y el host en Alt+3, el invitado pasó el 16 % del tiempo con la caja en mano en recuperación; con los dos en Alt+4, el 75 %. Con el host en Alt+1 o Alt+2, el 0 %. La suma de las dos latencias es la que cuenta.

**Cambios en `pista_piloto.gd`.**

1. `GUEST_AUTHORITY_REPLAY_LIMIT` pasó de 32 a 48.
2. Si el invitado recupera y el host tiene la caja en la mano, el invitado la dibuja en su propia mano. La lleva desde los ojos hacia la meta de la mano y la frena en lo primero que toca. Ya no usa la pose vieja del host. Si el host la suelta, se dibuja suelta con sus estados, como antes. El diagnóstico anota `recovery_hand`.

**Pruebas en una PC (dos procesos, ENet).** La prueba vive en `tmp/revision_pista_latencia_20261118/ventana48_mano` (`probar_mano.ps1` y `probe_mano.gd`). Cada corrida guarda sus registros en su carpeta.

| Caso | Resultado |
| --- | --- |
| Guion completo sin red simulada | 8/8 acciones, 0 rechazos, 0 recuperaciones, hasta 7 ticks repetidos, 0,80 ms de media y 1,44 ms como máximo por estado. Caja sobre el bloque en y = 0,7249. |
| Guion completo, Alt+4 en las dos puntas | 8/8 acciones, 0 rechazos, 0 recuperaciones, hasta 39 ticks repetidos, 1,99 ms de media y 5,21 ms como máximo. |
| Caja en mano girando la cámara 2,5 rad/s, Alt+4 en las dos puntas | 0 rechazos y 0 recuperaciones en 6 s, hasta 38 ticks repetidos. |
| Lo mismo con 700 ms en el invitado (recupera todo el tiempo) | Caja dibujada a 12,4 cm de la meta de la mano en la mediana (con predicción, 15,4 cm; la medida incluye un cuadro de giro). La pose vieja del host quedaba a unos 3 m. |
| Soltar mientras recupera | La caja queda suelta en el dibujo antes de volver a predecir; deja de seguir la mano. |
| Volver a la red normal con la caja en la mano | Vuelve a predecir con la caja en la mano y la suelta funciona. |

**Costo.** Aplicar un estado de 48 ticks cuesta más que uno de 32. En las notebooks, con Alt+4, se midieron 3,3 ms de media y 5,7 ms como máximo por estado con la ventana anterior. Falta medirlo con 48 en las dos notebooks.

## Qué es

Una sala nueva del laboratorio de red, la **pista de objetos**, con la caja de la sala aprobada (`sala_objetos_prueba_camara.zip`). La caja vive en el mundo Rapier propio (`SahurObjectWorld`). El personaje, el reloj, la sesión de red, la predicción y la mano (`InvHands`) son los del laboratorio.

- El **host** valida y confirma agarrar, soltar y lanzar en el tick en que se ejecutan (distancia, línea libre hasta el punto agarrado, límite del impulso), con el registro de acciones de la entrega 16.
- El **invitado** usa los controles de siempre de la mano. Pide la acción y espera la respuesta del host, como en la sala. Mientras sostiene la caja, la mueve con predicción: cada estado del host se restaura y se repiten sus propios ticks.
- **Alcance del piloto:** una caja y un invitado (el primero que entra). El jugador del host ve la caja, pero no la agarra. El inventario, el catálogo y los choques entre varios objetos quedan para las entregas que siguen.

La pista está en el este del nivel (x 53, z −6). Se entra caminando por la pista de física de la zona de inventario. Tiene las medidas de la sala aprobada: piso de 12 m, bloque bajo y la caja. Además lleva una puerta con vidrio y paredes de 4,5 m con techo. La caja no sale de la sala: la puerta y el techo solo la frenan a ella.

## Cómo abrirla en las dos PC

1. En el host, abrí `tools/testing/Jugar_como_host.cmd`. Prepara la versión actual del proyecto piloto y abre la partida. Dejá esa ventana abierta mientras juegan.
2. La primera vez, pasá `Jugar_como_invitado.cmd` a la otra PC. El host lo deja en `pista_en_red`, al lado de `piloto_net_lab`, y también imprime un enlace de descarga para la red local.
3. En la otra PC, abrí `Jugar_como_invitado.cmd`. Descarga los archivos que falten o hayan cambiado, prepara Godot y entra directamente a la partida. Para las pruebas siguientes, cerrá el juego en ambas PC, abrí el lanzador del host y después el mismo lanzador del invitado.

Las dos PC usan Godot 4.7.2. Si el ejecutable está en el Escritorio como `Godot_v4.7.2.exe`, los lanzadores lo encuentran. También podés arrastrar el ejecutable a cada lanzador. El invitado recuerda esa ruta.

La publicación circula por la misma red local o VPN de la partida. Si Windows pide permiso para Node.js en el host, permití el acceso en la red privada que usás para probar. La copia del invitado queda en `%LOCALAPPDATA%\Sahur\PistaObjetos`. La carpeta local se actualiza únicamente al abrir el lanzador.

| Invitado | Control (los de la mano del laboratorio) |
| --- | --- |
| Agarrar o soltar | Clic derecho (en Opciones, F3: alternar o mantener) |
| Lanzar | Clic izquierdo con la caja agarrada |
| Acercar o alejar | Rueda |
| Girar la caja | Mantener el botón del medio y mover el mouse |

El panel (F1) tiene una línea **«Pista de objetos»** con el estado de la caja: libre, en mano o recuperando. También muestra cuántos estados del host llegaron y la corrección física más grande.

## Diagnóstico en las dos PC

Los lanzadores empiezan a grabar al entrar a la partida e imprimen la ruta de los JSONL. El host los guarda en `pista_en_red/diagnosticos_pista`. El invitado los guarda en `%LOCALAPPDATA%\Sahur\PistaObjetos\diagnosticos_pista`. Si abrís la escena desde el editor, podés empezar con **Ctrl+F8** durante la partida. En ese caso, Godot guarda el archivo en `user://diagnosticos_pista` e imprime la ruta completa.

- **Ctrl+F9** marca el momento del problema. Aparece como `mark` en el archivo.
- **Ctrl+F8** detiene la grabación y muestra el nombre del archivo guardado. Cerrar el juego también la guarda. Al volver a grabar se crea otro archivo.
- Para analizar un problema, alcanzan los dos `.jsonl` de la misma partida. El vínculo de la caja y los identificadores de acción permiten cruzarlos aun si los relojes de las dos PC difieren.

El archivo se escribe durante la partida y se vacía a disco cada segundo. Guarda la latencia y el perfil aplicado, la posición simulada y dibujada de los jugadores y la caja, la cámara, la edad y el costo de aplicar cada estado de la caja, los motivos de recuperación y los resultados de los pedidos. El medidor de pruebas por cuadro sigue disponible con `--pista-log=RUTA`.

## Pruebas de referencia de la primera entrega (una PC, ENet)

Estas corridas corresponden a la versión inicial de la pista, con una ventana de 24 ticks y el canal de estados anterior.

`tools/testing/run_pista_objetos.ps1` abre un host y un invitado. El invitado sigue un guion con la mano de siempre (`--test-input=pista`), en primera persona: agarra caminando de costado, gira, suelta caminando, agarra al frenar, suelta quieto, apoya sobre el bloque y lanza. Las dos máquinas anotan cada cuadro. `tools/testing/pista_objetos_report.mjs` separa los saltos del personaje, de la cámara y de la caja. Las corridas están en `tmp/pista_objetos/`.

Las 8 acciones (4 agarres y 4 sueltas) se aplicaron en cada corrida: 0 rechazadas y 0 vencidas. La caja soltada sobre el bloque quedó con el centro en y = 0,7249, sobre la cara de arriba del bloque (0,5 + 0,225), sin hundirse.

### Personaje y cámara (separado de la caja)

| Corrida | Correcciones del personaje | Cámara respecto del personaje dibujado |
| --- | --- | --- |
| Sin red simulada (`…_local_final`) | 0 | 0,0 cm en todas las fases |
| 120 ms ± 20, 1 % (`…_rtt120_tick`) | 0 | 0,0 cm |
| 200 ms ± 40, 5 % (`…_rtt200`) | 0 | 0,0 cm |
| Con empujones del host (`…_empujones`) | 5, la mayor de 0,60 m | En el cuadro de la corrección y los 3 siguientes, la cámara se movió como máximo 26,6 cm, contra un salto simulado de 70 cm |

Sin empujones, el «cambio de paso» del personaje llega a 2,5 cm por cuadro. Eso es arrancar o frenar al caminar, no una corrección.

**Cámara:** la del laboratorio ya sigue al personaje dibujado, con el suavizado de las correcciones. El ZIP de prueba hacía lo mismo en la sala: informaba 28 cm en el primer cuadro para una corrección de 75 cm. **No hizo falta trasladar ese ajuste.**

### Caja en el invitado

«En la vista»: cuánto salta la caja en pantalla respecto de la cámara.

| Caso | Sin red simulada | 120 ms |
| --- | --- | --- |
| Agarrar caminando de costado, al confirmar | 1,9 cm | 2,4 cm |
| Agarrar al frenar, al confirmar | 1,1 cm | 1,3 cm |
| En mano, quieto / girándola | 0,1 / 0,7 cm | 2,9 / 0,7 cm |
| Soltar quieto | 1,1 cm | 1,2 cm |
| **Soltar caminando de costado** | **7,6 cm**; la caja vuelve unos 30 cm hacia atrás en 4 cuadros | **15,4 cm**, con retroceso |
| Soltar sobre el bloque | 0,3 cm, hundida 0,0 cm | 0,0 cm, hundida 0,0 cm |
| Lanzar | 0,7 cm al soltar | 3,6 cm al soltar |

En el host, con 120 ms, la caja salta 0,5–4,9 cm al agarrarla y 0,2–1,8 cm al soltarla.

**Aplicar un estado del host** (restaurar y repetir los ticks propios) costó 0,52 ms de media y 1,8 ms como máximo sin red simulada. Con 120 ms, 1,5 ms de media y 3,5 ms como máximo, con hasta 21 ticks repetidos.

### Hallazgos

0. **Corregido en esta entrega: el tick pedido.** La sala acotaba el tick pedido a 15 por delante del último estado aplicado del host. Con 120 ms de ida y vuelta, ese tick ya había pasado en el invitado (unos 5 ticks antes del clic). El host agarraba entonces con la mano de antes del clic (1,0 m en vez de 2,05 m): en su vista la caja salía disparada unos 80 cm y volvía (35 cm de salto). Ahora se pide el tick que sigue del invitado, acotado a 15 por delante del presente estimado del host. El host usa la mano del clic y sus agarres saltan 0,5–4,9 cm.
1. **Soltar en movimiento: la caja vuelve para atrás en el invitado.** Mientras viaja el pedido, el invitado sigue dibujando la caja en la mano. El host la suelta en el tick pedido, unos 7 ticks antes en su tiempo. Al llegar la confirmación, la caja va a donde quedó de verdad. Es la política de la sala aprobada: esperar al host para soltar y dibujar la caja suelta con las poses del host. Crece con la latencia.
2. **Con 200 ms y 5 % de pérdida, la caja queda trabada en «Recuperando el estado de la caja».** Los estados del host llegan con más de 24 ticks de atraso, el máximo que repite el adaptador (`MAX_REPLAY_STEPS`), y se descartan. Con 120 ms se repitieron hasta 21. El personaje sigue bien.
3. **Cada corrección del personaje pone a la caja en recuperación** hasta el estado siguiente del host. Con empujones hubo 5 correcciones y 5 recuperaciones. Es el diseño del adaptador (entrega 12).
4. **La caja suelta del invitado avanza a velocidad escalonada:** interpola los estados del host, que llegan cada 4 ticks. Se nota en el lanzamiento.
5. **Al girar rápido con la caja, la caja se atrasa y alcanza la mano**, igual en el host y en el invitado. Es la física de la mano, no la red.

## Qué queda por verificar entre las dos PC

1. Con **Alt+1 en ambas PC**, agarrá, mové y soltá la caja. Después volvé a agarrarla.
2. Poné **Alt+4 en el host** y **Alt+2 en el invitado**. Agarrá la caja y, sin soltarla, pasá el invitado por **Alt+3** y **Alt+4**. Soltala y verificá que caiga en ambas vistas.
3. Si hay un tirón o la caja queda recuperándose, marcá el momento con **Ctrl+F9**. Al terminar, guardá los dos `.jsonl` de esa partida.

## Archivos

- `scenes/net_lab/pista_objetos/`: `pista_objetos.gd` (la sala, en Jolt y en el mundo de la caja), `pista_piloto.gd` (vínculo, reglas del host, mano y dibujo de la caja), `pista_canal.gd` (canal de la entrega 16 con el simulador de red del laboratorio), `pista_historia.gd` (registro de la historia del personaje, con la copia del input para objetos), `pista_mundo.gd` (el mundo nativo con el tick del reloj del laboratorio) y `pista_medidor.gd` (registro por cuadro de las pruebas).
- `scenes/net_lab/net_lab.gd`: casilla del menú, `--pista-objetos`, las conexiones de reloj, input, corrección y repetición, el panel y el guion de prueba.
- `scenes/net_lab/net_lab_level.tscn`: el nodo `PistaDeObjetos`.
- `scripts/inventory/inv_hands.gd`: si la mira toca la caja de la pista, agarrar, soltar y lanzar se le piden a la pista. Los botones, la rueda y el giro son los mismos. Las pruebas de la mano del inventario pasan: física 248/0, contacto 108/0, laboratorio 190/0, alcance 191/0, hitbox 92/0.
- `scripts/net/net_session.gd`: lugares de aparición configurables (dentro de la pista).
- `extension.gdextension` y `bin/sahur_object_world.dll`: la extensión de objetos, la misma DLL de la sala aprobada.
- `tools/testing/`: `run_pista_objetos.ps1`, `pista_objetos_report.mjs`, `abrir_pista_objetos.cmd` y `preparar_pista_objetos.ps1` (arma el ZIP).
