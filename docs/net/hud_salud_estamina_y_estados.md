# HUD, salud, estamina y estados en el laboratorio

Hecho el 2026-11-02 a partir de tu pedido, [`prompt_claude_hud_salud_estamina_y_estados.md`](prompt_claude_hud_salud_estamina_y_estados.md). Es parte del laboratorio (`net-lab`): no toca PlayerV2, el inventario viejo ni nada del juego.

Lo que trae:

- **Un HUD**: la salud, la estamina y el termómetro abajo a la izquierda, y una luz arriba por cada estado tuyo prendido.
- **Salud y muerte de prueba**, por jugador.
- **Estamina** que no vuelve sola.
- **El súper y la cámara lenta gastan estamina** mientras están prendidos.
- **Objetos** que curan, dañan o devuelven estamina.
- **Daño en el tiempo** (agregado el 2026-11-02 a la tarde, sección 11): un consumible que quita salud de a poco, parejo, durante un tiempo.
- **La cámara lenta compartida, corregida.**
- **Usar, recoger y soltar sin esperar al host** (agregado el 2026-11-04, sección 12): la salud cambia, lo recogido aparece en la grilla y lo soltado en el piso en el momento, sin "esperando…".
- **Los arreglos de la auditoría de GPT** (2026-11-04, a la noche, sección 13): cada uso llega al host aunque se pierda un tick, el host hace las cosas en el orden en que las hiciste, y la muerte gana a Kp 1 y Kp 2 en el mismo tick.

---

## 1. Qué decidiste vos y qué eligió Claude

**Lo que decidiste vos** (todo está en tu pedido):

- **Salud:** de 0 a 10 en el instrumento (10 completa, 0 muerto), con valores intermedios. La luz naranja va abajo, integrada y apagada: es para la futura integridad del cuerpo. Sin regeneración.
- **Estamina:** de 0 a 200, sin regeneración; solo vuelve con consumibles. Correr, saltar, trepar y agarrarse no gastan.
- **Termómetro:** de 0 a 100, fijo en 100.
- **Luces:** solo las de tus estados prendidos, sin límite de cantidad, sin panel de fondo. La cámara lenta de otro no prende la tuya.
- **Gasto:** cada estado tiene su costo por segundo; con varios, se suman. Pagás solo lo tuyo.
- **Agotamiento:** con la reserva en cero se apagan todos juntos, con un sonido leve, una sola vez. Con cero no se prende nada, y lo apagado no se prende solo al recuperar reserva.
- **Muerte de prueba:**
    - un aviso claro;
    - se apagan tus estados;
    - la salud vuelve al máximo;
    - se conservan la posición, el inventario y la estamina, y el objeto que te mató se gasta.
- **Cámara lenta compartida:**
    - cada uno pide la suya;
    - el mundo va lento mientras al menos uno la pida;
    - la intensidad es una sola;
    - cada uno paga su pedido;
    - un jugador que no la pidió y se beneficia no paga.
- **Teclas:** el 1 del teclado numérico para la cámara lenta y el 2 para el súper, como estaban.
- **Consumibles:**
    - uno que cura;
    - uno que devuelve estamina;
    - uno que daña, que se puede usar con la salud completa y puede matar;
    - sin pasarse del máximo;
    - uno que solo cura, con la salud completa, no se gasta.

**Lo que eligió Claude** (lo podés cambiar):

- **La salud se cuenta en puntos:** 100 es la completa (**Health Max**, en el Tuning). El instrumento muestra la proporción: 37 de 100 marca 3,7. Desde la tarde se guarda en milésimas de punto, para que el daño en el tiempo baje parejo.
- **El reloj del gasto:**
    - Se cobra por tick: 60 por segundo real. La cámara lenta no lo cambia, porque siguen siendo 60 ticks por segundo real; solo pasa menos tiempo del mundo en cada uno. Así un estado cuesta lo mismo por segundo con o sin cámara lenta, y la cámara lenta no se abarata sola.
    - No depende de los cuadros por segundo.
    - Al repetir ticks (las correcciones) se parte del estado guardado, así que un tick nunca se cobra dos veces.
- **Los costos de fábrica:** 5 por segundo el súper y 8 la cámara lenta. Son los de tu ejemplo, no un balance. Con 200 de reserva, el súper solo dura 40 s; la cámara lenta sola, 25 s; los dos juntos, unos 15 s.
- **El aviso de muerte:** "Moriste", 2,5 s, en una franja roja en el medio de la pantalla, sin pausar ni bloquear nada.
- **El sonido:** dos notas cortas que bajan, hecho para el laboratorio (`scenes/net_lab/hud/estados_apagados.wav`).
- **Un corte de conexión:**
    - cuando el host empieza a esperarte (60 s), te apaga los estados, así no gastás ni sostenés la cámara lenta de los demás mientras no estás;
    - al volver, seguís con tu salud y tu estamina, y prendés lo que quieras;
    - si te vas del todo, tu pedido se va con tu personaje.
- **Los objetos de prueba** (sección 3) y que la **Botella de agua**, que subía la vitalidad de prueba, ahora cure 25.
- **El consumible tiene dos números** (salud y estamina): con los dos se puede armar uno que haga las dos cosas. Se aplican juntos, primero la estamina y después la salud: si te mata, la estamina ganada queda.
- **El dibujo del HUD:**
    - placa oscura con tornillos;
    - la salud con esfera blanca;
    - la estamina con esfera negra;
    - el termómetro de bronce con columna azul, como el concepto;
    - luces verdes con un rayo (súper) y un reloj de arena (cámara lenta).
- **Con el inventario abierto, las luces van arriba a la derecha:** al medio tapaban el título de la caja.

---

## 2. Cómo probarlo

### Solo, en esta PC

1. Abrí Godot. En las pestañas de arriba del visor, **net_lab**. **F6** → **Jugar solo**.
2. **Al empezar:**
    - abajo a la izquierda, la aguja de la salud en 10, la de la estamina en 200 y el termómetro en 100;
    - arriba no hay luces;
    - el panel de valores (arriba a la izquierda) tiene una línea nueva: "Salud 100 / 100 · estamina 200.0 / 200 · muertes de prueba 0".
3. **Corré (Shift) y saltá (Espacio):** la estamina no baja.
4. **El súper (2 del teclado numérico):**
    - arriba aparece una luz con un rayo, "Súper";
    - la aguja de la estamina baja 5 por segundo;
    - el panel dice "gastando 5.0 por segundo (Súper)".
5. **La cámara lenta (1 del teclado numérico):**
    - aparece la segunda luz, con un reloj de arena, y el mundo va lento;
    - gasta 13 por segundo (5 + 8).
    - **2** otra vez: queda solo la luz de la cámara lenta, a 8 por segundo.
6. **Dejá que se acabe la reserva** (con la cámara lenta sola, unos 25 s):
    - suena el sonido una vez, se apagan las luces y la aguja queda en 0;
    - **1** y **2** no prenden nada.
7. **Andá a la zona de inventario:** pasando el borde este del piso, a la derecha de donde aparecés, unos 30 m. La tercera columna de objetos, la más cercana a la **Caja compartida**, tiene:
    - el **Botiquín** (rojo, cura 50);
    - la **Bebida energética** (lata verde, +100 de estamina);
    - el **Frasco de veneno** (violeta, quita 40);
    - la **Cápsula letal** (roja oscura, quita 1000).

    Recogelos con **E**.
8. **Tab**, clic derecho en la **Bebida energética** → **Usar**: la reserva sube a 100. Ahora **2** vuelve a prender el súper.
9. **Clic derecho en el Botiquín:**
    - con la salud completa, **Usar** aparece apagado y dice "ya tenés la salud completa";
    - **Inspeccionar** dice lo que hace.
10. **Veneno y botiquín:** **Usar** en el **Frasco de veneno**: la aguja de la salud baja a 6. **Usar** el **Botiquín**: vuelve a 10 (no pasa).
11. **La cápsula, desde la barra:**
    1. Clic en la **Cápsula letal** y clic en el acceso **5** de la barra.
    2. Cerrá con **Tab**.
    3. Prendé **1** y **2**.
    4. Apretá **5** (la fila de arriba).

    Aparece "Moriste", se apagan las luces, la salud vuelve a 10 y la estamina sigue donde estaba. Seguís en el mismo lugar, y queda una cápsula.

### En las dos PC

1. **En esta PC:** guardá todo (**Ctrl+S**), pestaña **net_lab**, **F6** → **Crear partida**.
2. **En la notebook:** cerrá Godot y hacé doble clic en `actualizar_lab.bat`, en el Escritorio. Después **F6**, la IP de esta PC y **Unirse**.
3. **A pide la cámara lenta (1) y después B también:**
    - el mundo va igual de lento;
    - cada uno ve bajar su estamina 8 por segundo;
    - cada uno ve solo su propia luz.
4. **A la suelta (1):** sigue lenta; la estamina de A deja de bajar y la de B sigue. **B la suelta:** termina.
5. **Lo mismo empezando por B, y los dos a la vez.**
6. **Uno sin pedir la cámara lenta, con el súper prendido:** paga solo su súper (5 por segundo), sin luz de cámara lenta.
7. **Muerte con los dos sosteniendo:** los dos piden la cámara lenta y A toma la **Cápsula letal**. A ve "Moriste" y deja de pagar; el mundo sigue lento por B.
8. **Agotamiento con los dos sosteniendo:** los dos la piden y uno se queda sin estamina. Le suena una vez a ese solo, y el otro la mantiene.
9. **Entrada tardía:** con la cámara lenta pedida por A, B cierra la ventana del juego y vuelve a entrar. B la ve lenta, sin luz y sin gastar, y sin avisos viejos.

Si la notebook no entra y dice "difiere en los valores del Tuning", "en el código" o "en el inventario", las dos copias no tienen lo mismo: `actualizar_lab.bat` otra vez. Desde esta etapa los costos, los máximos y los efectos de los consumibles están en la huella: una copia con otros no entra.

### Las teclas

| Tecla | Qué hace |
| --- | --- |
| **1 del teclado numérico** | Pedís o soltás tu cámara lenta del mundo. El mundo va lento mientras alguno la pida. Gasta tu estamina mientras la pedís |
| **2 del teclado numérico** | Tu súper salto y velocidad. Gasta tu estamina mientras está prendido |
| **Usar** (clic derecho en el inventario) o **1 a 9 y 0** (la barra rápida) | Usa un consumible: cura, daña o devuelve estamina |

---

## 3. Lo que hay en la zona de inventario

| Objeto | Efecto | Pila | Cuántos hay |
| --- | --- | --- | --- |
| **Botiquín** | Cura 50 | 3 | 3 |
| **Bebida energética** | Devuelve 100 de estamina | 4 | 4 |
| **Frasco de veneno** | Quita 40 de salud (tres seguidos te matan) | 5 | 5 |
| **Cápsula letal** | Quita 1000: una te mata | 2 | 2 |
| **Toxina lenta** (desde la tarde) | Quita 20 de a poco, en 4 s (5 por segundo) | 4 | 4 |
| **Botella de agua** (ya estaba) | Cura 25 (antes subía la vitalidad de prueba) | 3 | 3 |

Son `.tres` normales en `scenes/net_lab/inventario/objetos/`, y se abren, editan y duplican con el panel **Objetos**.

---

## 4. Cambiar valores

### En el nodo Tuning (tienen que ser iguales en las dos PC)

Abrí `net_lab.tscn`, seleccioná el nodo **Tuning** y, en el **Inspector**:

| Grupo | Valor | De fábrica | Qué es |
| --- | --- | --- | --- |
| **Salud y estamina** | **Health Max** | 100 | La salud completa, en puntos. El instrumento muestra la proporción, de 0 a 10 |
| **Salud y estamina** | **Stamina Max** | 200 | La reserva completa. El instrumento muestra la proporción: lleno marca 200 aunque cambies este valor |
| **Cámara lenta** | **Slow Stamina Cost** | 8 | Lo que gasta por segundo tu pedido de cámara lenta, aunque otro también la pida. 0 la deja gratis |
| **Súper salto y velocidad** | **Boost Stamina Cost** | 5 | Lo que gasta por segundo el súper. 0 lo deja gratis |

Los costos van de 0 a 1000, de a milésimas: el Inspector no deja poner uno negativo, y el código, si llegara uno, lo toma como 0. **Slow Scale** (0,3) sigue siendo la escala de la cámara lenta, una sola para todos.

### En el nodo Hud → Instrumentos (puede ser distinto en cada PC)

| Valor | De fábrica | Qué es |
| --- | --- | --- |
| **Size Scale** | 1 | Por cuánto se multiplica el tamaño de los instrumentos. Más grande no pasa del lugar que hay debajo de la grilla del inventario |
| **Needle Follow** | 14 | Qué tan rápido sigue la aguja al valor. Es solo dibujo: con la reserva en cero, la aguja termina en cero |
| **Death Notice Seconds** | 2,5 | Cuánto dura el aviso de muerte, en segundos reales |
| **Death Text** y **Death Detail** | "Moriste" y la explicación | Los textos del aviso |
| **Exhaustion Sound** | `estados_apagados.wav` | El sonido al quedarte sin estamina. Vacío, no suena. Se cambia arrastrando otro sonido desde **FileSystem** |
| **Exhaustion Volume Db** | −6 | Su volumen |

**Inventory Ui** y **Tuning** son las conexiones del HUD: no los cambies.

---

## 5. Crear un consumible con el panel Objetos

1. Pestaña **Objetos** (al lado de **Inspector**) → **Ítems** → **Nuevo**.
2. **Nombre** (por ejemplo "Vendas"), **Celdas**, **Se apila, hasta**, como cualquier ítem (sección 4 de `inventario_de_grilla.md`).
3. **Capacidades** → **+ Consumible**. Aparecen cuatro números:
    - **Efecto en la salud (puntos):** positivo cura y negativo daña. La salud completa son 100: con −100 o menos, una unidad mata. En 0 no la toca.
    - **Recupera estamina:** la reserva completa son 200. En 0 no la toca.
    - **Daño en el tiempo (puntos)** y **En cuántos segundos** (desde la tarde, sección 11): quita esos puntos de a poco, parejo, en esos segundos. Con 4 y 2, la vida baja 2 por segundo durante 2 s. En 0 puntos no hace nada.

    Debajo, una línea dice lo que hace con esos números. Por ejemplo: "Al usar una unidad: cura 30 de salud (sin pasar del máximo; con la salud completa no se usa ni se gasta)".
4. **Guardar.** Si no hace nada (salud, estamina y daño en el tiempo en 0), no se guarda: "El consumible no hace nada". Un daño en el tiempo tiene que durar de 0,1 a 600 s.
5. **Colocar en la zona** → **Unidades** → **Colocar en la zona**, y **Guardar la zona** (o **Ctrl+S**).
6. **F6** → **Jugar solo**: recogelo y usalo.

Para cambiar uno que ya existe: el buscador de arriba (por ejemplo "botiquín"), un clic en la lista, cambiás los números y **Guardar**.

**Uno que haga dos cosas** (por ejemplo, cura 10 y devuelve 50): los dos números distintos de 0. Se usa si alguno de los dos hace algo y gasta una unidad. Un consumible de antes con `vitality_gain` (la vitalidad de prueba) se lee como si curara eso mismo.

---

## 6. Arquitectura

### Dónde vive cada cosa

- **En el personaje (`ActorState`):**
    - `health`, la salud en milésimas de punto (desde la tarde; antes, en puntos);
    - `effect_total`, `effect_duration` y `effect_elapsed`, los daños en el tiempo: cuatro lugares (sección 11);
    - `stamina`, la estamina en unidades internas: una de estamina son 60.000, así un costo con milésimas se cobra exacto por tick;
    - `powers`, los estados prendidos, un bit por estado (el súper y el pedido de cámara lenta propio);
    - `ability_presses_seen`, el contador del 1 del teclado numérico;
    - `deaths` y `exhaustions`, los contadores de avisos.

    Viajan en cada snapshot, se predicen y se repiten como el resto: la regla de oro del laboratorio ("nada que influya en el movimiento futuro vive fuera de este objeto").
- **Los primeros 93 bytes del estado son los de siempre**, con el mismo movimiento. Lo nuevo va al final: el estado pasó de 93 a 102 bytes; con el daño en el tiempo, a 152, y desde el 2026-11-04, a 153 (hasta qué uso de consumible llegó, sección 12). `boosted` sigue existiendo, como el bit del súper.
- **En el motor (`ActorMotor`, etapa 3) y `ActorPowers`:** cada pulsación nueva del 1 o del 2 prende o apaga su estado. Con la reserva en cero no se prende. Después se cobra el tick: la suma de los costos de lo prendido. Si la reserva llega a cero, `powers` vuelve a 0 y `exhaustions` sube uno. Lo predice tu PC al instante, y el host hace la misma cuenta con tu input.
- **Por el inventario (`ActorVitals`):** un consumible cambia la salud y la estamina. Hasta el 2026-11-04 era un evento del host, que subía la época, como un empujón; desde entonces se usa desde tu input, y tu PC y el host lo aplican en el mismo tick, sin subir la época (sección 12). Si la salud llega a cero, en ese mismo paso:
    - `deaths` sube uno;
    - se apagan tus estados;
    - la salud vuelve al máximo.

    `ActorVitals` es todo lo que el inventario ve del personaje: la salud, la estamina y sus máximos.
- **En el host, la cámara lenta del mundo (`net_lab.gd`, `_follow_world_slow_holders`):**
    - al empezar cada tick, mira qué personajes tienen el bit de cámara lenta;
    - solo cuando pasa de nadie a alguno, o de alguno a nadie, programa el inicio o el fin del tramo, con anticipación para el jugador más lejano, como siempre;
    - si alguien la pide justo cuando el anterior la soltó y el fin todavía se puede avisar a tiempo, el tramo se vuelve a abrir.
- **El HUD (`scenes/net_lab/hud/lab_hud.gd`, nodo Hud → Instrumentos):** solo lee el estado de tu personaje (el predicho en el cliente, el que vale en el host). No toma el mouse ni el teclado, y no cambia nada.
    - **El aviso de muerte:** sale cuando sube `deaths`.
    - **El sonido:** cuando sube `exhaustions`.

    Los dos salen de contadores, no de cuántas veces llega un valor. Por eso:
    - repetir ticks o corregir no los repite;
    - una muerte con la salud restaurada al instante igual se avisa;
    - al entrar tarde o volver de un corte se toma el número que haya, sin avisar lo de antes.

### Lo que valida el host

- **El cliente no puede inventarse salud ni reserva.** Cuando el host adopta lo que predijo un cliente (paso 7 del laboratorio), ahora exige (`ClaimAdoption._vitals_possible`):
    - la misma salud, las mismas muertes y, desde el 2026-11-04, hasta el mismo uso de consumible;
    - una estamina que no sea más que la del host;
    - ningún estado prendido con la reserva en cero;
    - como mucho un agotamiento de más, y solo con todo apagado.
- **El consumible:** que el objeto esté en tu inventario, que tenga la capacidad y que haga algo. Aplica el efecto y gasta la unidad en el mismo paso. Desde el input, cada uso se aplica una vez: el estado guarda hasta qué uso llegó. Por pedido (lo usan las pruebas), además con la versión que viste, y un pedido repetido no se vuelve a aplicar: se contesta con el resultado guardado.
- **La huella de compatibilidad:** incluye los costos y los máximos (están en el Tuning), los efectos de cada consumible (en el catálogo) y el formato nuevo del estado (en el código).

### Agregar otro estado (la invisibilidad, por ejemplo)

1. Un bit y una fila en `ActorPowers.LIST`: el nombre de la luz, el ícono y el valor del Tuning con su costo.
2. Su costo en el Tuning.
3. Su tecla en el Mapa de entrada, con su contador en `ActorInput` y `ActorState`, y su vuelta en `ActorPowers.step`.
4. Su efecto, donde corresponda.

El gasto, el agotamiento, la muerte, el corte y la luz del HUD ya lo tienen en cuenta. El HUD dibuja los íconos `bolt` y `hourglass`; uno nuevo sin dibujo muestra la primera letra de su nombre hasta que se le haga uno.

---

## 7. La cámara lenta compartida: qué pasaba y qué cambió

**Lo que había:** cada pulsación del 1, de cualquiera, prendía o apagaba el mismo tramo global (`_request_world_slow`). No era de nadie.

**Lo que se reprodujo**, con el código de antes, en dos procesos de esta PC y una traza de la escala:

- **Si B la pide mientras A la tiene, la apaga:** su pulsación a los 9 s cortó la de A.
- **Con los dos a la vez, se anulan:** duró 9 o 10 ticks y se apagó.
- **Lo mismo con internet mala.**

**Lo que no se reprodujo:** la cámara "todavía más lenta".

- En ningún tick de los tres casos la escala del mundo bajó del 30 %.
- El tiempo del mundo nunca descontó un tick dos veces.
- Leyendo el código, la escala es la de un solo tramo y los tramos del host no se superponen.
- En el cliente se ve 0,285 un rato: es su reloj a 57 ticks por segundo mientras ajusta el adelanto (57/60 × 0,3). Es un 5 % y pasa igual con un solo jugador.

No se sabe qué viste: si te vuelve a pasar, un video o captura del panel (la línea "CÁMARA LENTA DEL MUNDO" y la de "reloj") ayudaría.

**Lo que cambió:** el pedido es de cada jugador (su bit en `ActorState`), y el host prende la del mundo mientras alguno la pida. Con el ejemplo de tu pedido:

1. **A la prende:** mundo lento, solo A paga.
2. **B también:** misma escala, un solo tramo, los dos pagan.
3. **A la suelta:** sigue lenta, A deja de pagar, B sigue.
4. **B la suelta o se agota:** termina.

La muerte, el agotamiento, el corte y la salida de un jugador apagan solo su pedido.

---

## 8. Archivos

### Nuevos

| Archivo | Qué es |
| --- | --- |
| `scripts/actor/actor_powers.gd` | Los estados, su gasto y el agotamiento |
| `scripts/actor/actor_vitals.gd` | La salud y la estamina para el inventario; la muerte de prueba; el daño en el tiempo, que el motor descuenta en cada tick |
| `scenes/net_lab/hud/lab_hud.gd` | El HUD |
| `scenes/net_lab/hud/estados_apagados.wav` | El sonido de agotamiento |
| `scenes/net_lab/estados_test.gd` y `.tscn` | La prueba de un proceso (sección 9) |
| `scenes/net_lab/inventario/objetos/botiquin.tres`, `bebida_energetica.tres`, `veneno.tres` y `capsula_letal.tres` | Los objetos de prueba |
| `scenes/net_lab/inventario/objetos/toxina_lenta.tres` (desde la tarde) | La toxina lenta: daño en el tiempo de prueba |

### Cambiados

| Archivo | Qué cambió |
| --- | --- |
| `scripts/actor/actor_state.gd` | Salud, estamina, estados (`powers`; `boosted` es su bit), contador del 1 y contadores de avisos; 102 bytes; `keep_player_state` |
| `scripts/actor/actor_motor.gd` | La etapa 3 llama a `ActorPowers.step` (antes prendía y apagaba solo el súper) |
| `scripts/actor/actor_input.gd` | Solo el comentario: el contador del 1 ahora lo usa el motor |
| `scripts/actor/actor_tuning.gd` | Grupo **Salud y estamina**, **Slow Stamina Cost** y **Boost Stamina Cost** |
| `scripts/net/claim_adoption.gd` | La adopción no deja subir la salud ni la estamina |
| `scripts/net/net_session.gd` | El actor nace con salud y reserva completas; la señal `player_waiting` al empezar a esperar a uno que se cortó |
| `scripts/net/sim_clock.gd` | `add_world_slow` devuelve el primer tick afectado también al volver a abrir un tramo |
| `scenes/net_lab/net_lab.gd` | La cámara lenta del mundo según los pedidos; el corte apaga los estados; el HUD; la línea del panel; `--test-harm-at`; el resumen con los estados |
| `scenes/net_lab/net_lab.tscn` | El nodo **Hud → Instrumentos** |
| `scripts/inventory/inv_ability.gd`, `inv_equippable.gd` | Las capacidades reciben la salud y la estamina del que las usa (`ActorVitals`) |
| `scripts/inventory/inv_consumable.gd` | Salud y estamina en vez de la vitalidad de prueba |
| `scripts/inventory/inv_loadout.gd`, `inv_inventory.gd` | Sin la vitalidad de prueba |
| `scripts/inventory/inv_authority.gd`, `inv_net.gd` | El consumible sobre el personaje; cuenta las muertes |
| `scripts/inventory/inv_ui.gd` | El menú pregunta con la salud y la estamina; "Equipado" pasó a la derecha de la barra (a la izquierda van los instrumentos); `hud_limits` para ubicar el HUD |
| `addons/inventario_objetos/formulario_item.gd`, `guardado.gd` | Los campos del consumible y su validación |
| `scenes/net_lab/inventario/objetos/botella.tres` | La descripción: cura 25 |
| `scenes/net_lab/inventario/catalogo_de_prueba.tres`, `zona_de_inventario.tscn` | Los cuatro objetos nuevos, en el catálogo y en la zona (x 1 de la zona) |
| Pruebas: `inv_lab_test.gd`, `prueba_del_creador.gd`, `prueba_del_creador_juego.gd` | La salud en vez de la vitalidad de prueba; el panel crea también un veneno |

No se tocaron el nivel, el personaje (`actor.tscn`), `project.godot`, la exportación, ni modelos, texturas o materiales. La imagen del concepto no se usa: el HUD se dibuja por código.

---

## 9. Pruebas

| Prueba | Qué cubre | Resultado (2026-11-02) |
| --- | --- | --- |
| `scenes/net_lab/estados_test.tscn` (nueva, un proceso, el laboratorio de verdad) | Todo completo al empezar (agujas en 10 y 200, sin luces); correr y saltar no gastan; esperar no devuelve; los costos exactos (5, 5+8 y 8 por segundo en 60 ticks); dos pedidos de cámara lenta: un tramo, cada uno paga lo suyo, uno la suelta y sigue, el otro sin luz; un fin programado no corta al que la pide antes de que llegue; sin tramos superpuestos; el tiempo del mundo descuenta cada tick lento una vez; agotarse: se apagan los dos juntos, un agotamiento, un sonido, la aguja en cero, con cero no se prende; una corrección que repite el agotamiento no suena; los cuatro consumibles desde el menú y la barra, los máximos, los rechazos sin gastar, el menú y la inspección; la muerte con un pedido repetido (una muerte, una cápsula), estados apagados, salud, estamina, posición e inventario; el aviso se ve y se va; la muerte de A no corta el pedido de B; el corte y la salida de B | **66 de 66** |
| Nueve casos en red, host y cliente en esta PC (con `--test-world-slow-at`, `--test-power-at`, `--test-harm-at`, `--test-tuning`, relevo y corte) | Los dos órdenes del ejemplo, a la vez, con internet mala (+200 ms, 5 % de pérdida), agotamiento de los dos con 40 por segundo, muerte del cliente, entrada tardía, corte de 8 s, y el súper de uno con la cámara lenta del otro | En todos, **un solo tramo, igual en el host y el cliente**; cada uno pagó exactamente sus ticks (por ejemplo, 300 ticks a 8 = 40); **0 correcciones** del cliente salvo la de la muerte (1); 0 afirmaciones con datos imposibles; agotamiento y muerte avisados una vez en el que corresponde; el que entró tarde, sin luz ni gasto; el cortado, sin estados al volver y con la misma estamina |
| La reproducción con el código de antes | Sección 7 | La cancelación, reproducida; la cámara más lenta, no |
| `actor_replay_test` | Repetición | Coincide. Su huella pasa de `7d3d417dd954d05b` a `ffadf8acf80e0045` solo porque el estado ahora lleva la salud y la estamina: **los 93 bytes del movimiento dan `7d3d417dd954d05b`, igual que antes** (comprobado con una copia de la prueba que calcula las dos) |
| `mantle_test`, `grab_above_test`, `hang_sweep_test` | El parkour con el estado nuevo | 50 casos, 22 de 22 y el barrido de bordes con sus cinco criterios cumplidos, igual que antes |
| `inv_model_test`, `inv_lab_test`, `inv_pair_test` (tres procesos) | El inventario, con la botella curando salud | 70 de 70, 166 de 166, host 18, A 24 y B 7 sin fallas |
| `prueba_del_creador.gd` y `prueba_del_creador_juego.tscn` (el panel Objetos, en una copia del proyecto) | El consumible con sus dos números: no se guarda si no hace nada ni con un daño fuera de rango; el termo cura 7 y devuelve 3; un **Veneno de prueba** creado con el panel (−30), con la línea que dice lo que hace, colocado y usado con la salud completa | **144 de 144** en el editor y **25 de 25** jugando (antes 138 y 23: lo nuevo suma 6 y 2) |
| Huella | Un cliente con otro **Slow Stamina Cost** | No entra: "difiere en los valores del Tuning" |
| Capturas con ventana, 1280 × 720 y 1600 × 900 (internas, no son entregables) | Al empezar, valores parciales con dos estados, el inventario abierto, el inventario con la caja, la muerte y la reserva en cero | Revisadas: nada cortado ni encima de la grilla, las luces a la derecha con el inventario abierto; con eso se ajustaron los textos de las esferas y la franja del aviso |

**Para correrlas** (Claude): `--headless --fixed-fps 60 --scene res://scenes/net_lab/estados_test.tscn`. Las de red: `--headless --scene res://scenes/net_lab/net_lab.tscn -- --host --port=N --autoquit=19 --test-world-slow-at=6,11` y el cliente con `--client --address=127.0.0.1 --port=N --test-world-slow-at=7.5,13.5`; al terminar, cada uno imprime los tramos, el tiempo del mundo, los estados de cada jugador con sus ticks y lo que avisó su HUD.

---

## 10. Límites y lo que falta

- **Tu prueba** (escrito el 2026-11-02): faltaba, solo y en las dos PC (la lista de la sección 2). El 2026-11-04 la hiciste en red: "todas funcionan correctamente". Falta con el `.exe` exportado.
- **La cámara más lenta que viste no se reprodujo** (sección 7).
- **Un agotamiento predicho que el host corrige** (por ejemplo, porque te llegó una bebida justo antes) ya sonó. Si después te agotás de verdad con el mismo número, no vuelve a sonar. Es raro: hace falta un consumible en el mismo momento.
- **Si uno suelta la cámara lenta y otro la pide un instante después,** pero ya tarde para avisar a todos que el tramo sigue, el mundo va normal unos pocos ticks (como mucho lo que tarda en avisarse, 0,1 a 0,3 s) y vuelve a ir lento.
- **Mientras el host no da por cortado a un jugador** (5 s sin noticias), su personaje sigue con lo que tenía prendido y paga.
- **Un input que llega tarde con un estado que se apaga** trae una corrección: el host no adopta una estamina mayor que la suya. Con internet normal no pasó en las pruebas.
- **La placa de los instrumentos tapa** la parte de abajo a la izquierda del panel de valores (**F1** lo oculta).
- **Con una caja de muchísimas filas,** las celdas se achican y la caja podría quedar encima de los instrumentos en 1280 × 720. Con las cajas del laboratorio no pasa.
- **Lo que queda para después:**
    - la luz naranja sigue apagada hasta que exista la integridad del cuerpo;
    - el termómetro marca 100 fijo hasta que se mida la luz;
    - no hay elementos del escenario que dañen, ni enemigos, hambre, daño de caída, reaparición ni guardado.

---

## 11. Daño en el tiempo (2026-11-02, a la tarde)

Pediste un consumible que haga daño en el tiempo: "4 de daño cada 2 segundos, o 5 de daño en el lapso de 1 segundo", con la vida bajando a velocidad constante hasta que termina el efecto o morís.

**Lo que decidiste vos** (tres preguntas, el mismo día):

- **Baja parejo, sin saltos:** ponés el total y la duración. 4 en 2 s son 2 por segundo, un poquito en cada tick.
- **Se acumulan:** cada uno sigue con su ritmo y su tiempo, hasta 4 a la vez. Con dos encima, baja el doble de rápido mientras duren los dos. Con 4, otro no se usa ni se gasta.
- **Con la cámara lenta va lento:** sigue el tiempo del mundo. Al 30 %, "4 en 2 s" tarda unos 6,7 s reales.

**Lo que eligió Claude:**

- **La salud se guarda en milésimas de punto,** así cada tick quita un poco (con 5 por segundo, 0,083 por tick). El instrumento y el panel siguen en puntos.
- **Cada daño guarda su total, su duración y cuánto lleva,** y cada tick quita la parte exacta del total que le toca. Así baja parejo desde el primer tick, también con daños chicos y largos (1 punto en 600 s), y al terminar quitó justo el total. La primera versión repartía lo que quedaba y se atrasaba un 0,4 %; con daños chicos, mucho más.
- **Lo descuenta el motor en cada tick** (`ActorVitals.step`, en la etapa 1, con el tiempo del mundo), igual en el host y en la predicción. El consumible solo lo pone: hasta el 2026-11-04, como un evento del host; desde entonces, en el mismo tick en tu PC y en el host (sección 12). Por eso no trae correcciones mientras baja, y repetir ticks no lo cobra dos veces.
- **Si mata,** es la muerte de prueba de siempre: se cortan todos los daños en el tiempo, se apagan tus estados y la salud vuelve al máximo. La predice tu PC: el aviso sale al instante.
- **Con daño de golpe y daño en el tiempo en el mismo consumible,** primero el de golpe. Si te mata, el daño en el tiempo ya no se pone.
- **El objeto de prueba:** la **Toxina lenta** (20 en 4 s, 5 por segundo), en la zona de inventario, en la tercera columna, después de la cápsula letal.
- **Tu "venen lento" no lo toqué:** sigue quitando 65 de golpe. Para pasarlo a daño en el tiempo, en el panel **Objetos**:
    1. Buscá "venen" en el buscador y hacé un clic en él.
    2. En **Capacidades**, poné **Efecto en la salud** en 0, **Daño en el tiempo (puntos)** en 65 y **En cuántos segundos** en lo que quieras.
    3. **Guardar.**

**Cómo se ve jugando:** la aguja de la salud baja sola, despacio. En el panel de valores (**F1**) aparece "DAÑO EN EL TIEMPO: N encima · quitan X de salud más · el más largo termina en Y s del mundo".

**En la red:** el daño en el tiempo viaja en el estado del personaje (152 bytes; 153 desde el 2026-11-04), y la adopción exige que coincida con el del host. Lo pone el consumible: hasta el 2026-11-04 solo el host, subiendo la época; desde entonces, tu PC y el host en el mismo tick (sección 12).

**Probado:**

| Prueba | Resultado |
| --- | --- |
| `estados_test.tscn`, sección 8 (en total, 85 de 85) | La inspección dice lo que hace; con la salud completa se usa; 5 por segundo en 60 ticks; parejo (entre 0,080 y 0,087 por tick); termina y quitó justo 20; no sigue bajando; dos se acumulan (10 por segundo) y quitan 40; con cuatro encima, el quinto no se usa ni se gasta; con la cámara lenta, 1,5 por segundo real, y al final igual 20; matar: muerte de prueba, estados apagados, aviso, y no sigue bajando |
| Cuatro casos en red, host y cliente en esta PC (`--test-poison-at`) | Dos encima (termina en 60); con la cámara lenta del host (quita 20 igual, más despacio); uno que mata (una muerte, un aviso, el súper apagado); dos encima con internet mala (60). Una corrección por cada daño que pone el host y ninguna mientras baja; 0 datos imposibles |
| El panel Objetos (en una copia) | El consumible tiene cuatro números; un daño en el tiempo sin duración no se guarda; el veneno de prueba quita 30 de golpe y 10 en 1 s, y la línea del panel lo dice. Jugando, baja 10 más en un segundo. **145 de 145** y **26 de 26**. Una comprobación de los contenedores ("la zona sigue marcada sin guardar") falló en una de tres corridas: es la marca de "sin guardar" del editor sin ventana, no algo de esto |
| Repetición, mantle, agarre, inventario, tres procesos | Iguales. La huella completa de la repetición pasa a `85afb38454f8bb04` (el estado más largo y tus costos de 0,8); los 93 bytes del movimiento siguen dando `7d3d417dd954d05b` |

**Falta** (escrito el 2026-11-02; el 2026-11-04 la hiciste en red y anduvo): tu prueba, solo y en las dos PC. Recorrido corto: recogé las **Toxinas lentas**, usá una y mirá bajar la aguja; usá dos seguidas; usá una con la cámara lenta prendida; con poca salud, usá varias hasta morir.

---

## 12. Usar, recoger y soltar sin esperar al host (2026-11-04)

Probaste todo en red y anduvo. Notaste que al usar un veneno salía "esperando…", que con más latencia tardaba más, y que al recoger pasaba lo mismo. Era así: usar y recoger eran pedidos al host, y tu PC no mostraba nada hasta la respuesta, un viaje de ida y vuelta (tu ping). Pediste sacarlo, **también para la salud** (lo elegiste entre las dos opciones).

**Cómo funciona ahora:**

- **Usar un consumible** (desde el menú o la barra rápida) ya no es un pedido. Viaja con las teclas de tu personaje, en el input de cada tick, como Kp 1 y Kp 2.
    - Tu PC aplica el efecto en el tick siguiente al clic, y la unidad se ve gastada en el mismo cuadro.
    - El host, cuando le llega ese input, hace lo mismo en ese mismo tick: mira que el objeto esté en tu inventario, aplica el efecto y gasta la unidad.
    - Como los dos hacen lo mismo en el mismo tick, la respuesta del host no trae corrección.
- **Recoger** sigue siendo un pedido, porque el host decide quién llegó primero. Pero lo que se ve no lo espera:
    - lo recogido aparece en tu grilla en el mismo cuadro, donde lo va a poner el host, y deja de verse en el piso;
    - si no entra, lo dice sin preguntarle al host.
- **El "esperando…" amarillo** queda solo para los pedidos que todavía esperan: mover, dividir y equipar. Soltar también esperaba, hasta el cambio de más abajo ("Soltar sin esperar").

**Si el host dice que no** (casi nunca; por ejemplo, tu compañero agarró el objeto primero):

- **Al recoger:** el objeto vuelve al piso y sale el aviso.
- **Al usar:** la unidad vuelve a verse y sale "No se usó: …". Si tu PC ya había aplicado el efecto, la corrección del host lo deshace.

**Lo que eligió Claude:**

- **Un uso por tick.** Dos clics en el mismo cuadro van en ticks seguidos (1/60 s), y el segundo se mira con lo que dejó el primero. Por ejemplo, dos botiquines con 60 de salud: el primero cura hasta 100 y el segundo no se usa, en las dos PC, y vuelve a verse.
- **Mientras el host no confirma un uso, esa pila no se agarra ni se mueve.** Dice "Ese objeto está esperando al host", porque un movimiento que llegara antes que el uso encontraría otra versión. Usarla otra vez sí se puede. Dura lo que tarda el host, un ping.
- **Equipar sigue siendo un pedido:** no cambia la salud.
- **El pedido de usar** (`InvProtocol` USE) sigue andando, para las pruebas: es un evento del host, como antes.
- **Si el input del tick del uso le llega tarde al host** (internet muy mala), el host lo aplica unos ticks después y hay una corrección chica. Las pruebas con 300 ms y 8 % de pérdida no la tuvieron. *Corrección del mismo día (sección 13): esto valía solo si el uso tardío seguía siendo el último. Con dos usos seguidos, el host podía saltearse el primero. Ya no pasa.*

**En la red:**

- El input tiene 5 bytes más: el contador de usos y el objeto, 17 en vez de 12. *Desde la sección 13: 14 bytes, más 8 por cada uso que el host todavía no confirmó.*
- El estado tiene uno más, 153: hasta qué uso llegó. La adopción exige que coincida con el del host.
- Un uso desde el input no sube la época.
- La huella cambió: las dos PC tienen que tener esta versión (en la notebook, `actualizar_lab.bat`).

**Dónde está:**

| Archivo | Qué cambió |
| --- | --- |
| `scripts/actor/actor_input.gd` | `use_presses` y `use_uid` (desde la sección 13, `uses` en vez de `use_uid`) |
| `scripts/actor/actor_state.gd` | `use_presses_seen` (153 bytes) |
| `scripts/actor/actor_vitals.gd` | `host_event`: si aplicar sube la época |
| `scripts/net/sim_clock.gd` | `before_step`: lo que se le aplica a un actor justo antes de moverlo |
| `scripts/net/net_sync.gd` | El host repite el uso junto con lo demás del input |
| `scripts/net/claim_adoption.gd` | La adopción exige el mismo uso |
| `scripts/inventory/inv_net.gd` | `queue_use`, `take_use` y `use_before_step`; lo recogido no se dibuja en el piso (desde la sección 13, `fill_input` en vez de `take_use`) |
| `scripts/inventory/inv_authority.gd` | `use_from_input`, y en el paquete, hasta qué uso llegó |
| `scripts/inventory/inv_replica.gd` | `shown_own`: la grilla como se ve, con lo recogido y lo usado; `is_taken` |
| `scripts/inventory/inv_ui.gd` | `use_item` y `pick_up_world`; la grilla se dibuja con `shown_own`; el amarillo solo para los pedidos |
| `scenes/net_lab/net_lab.gd` | El uso va en el input propio y se aplica también al repetir ticks |
| `scenes/net_lab/estados_test.gd` | Sección 9 nueva |
| `scenes/net_lab/inventario/pruebas/inv_instant_test.gd` y `.tscn` | La prueba nueva en red |

**Probado:**

| Prueba | Resultado |
| --- | --- |
| `estados_test.tscn`, sección 9 nueva | **101 de 101.** Lo nuevo: <ul><li>un botiquín desde la interfaz: gastado en el mismo cuadro, sin pedido; cura en el tick siguiente sin subir la época;</li><li>con la salud completa no sale y lo dice;</li><li>dos venenos desde la barra, uno por tick: 100 → 60 → 20;</li><li>uno que el host no puede usar vuelve y lo dice;</li><li>una botella lejos: se ve en la grilla, el host dice que no y vuelve al piso con el aviso; cerca, queda.</li></ul> |
| `inv_instant_test.tscn` (nueva), host y cliente en esta PC; el cliente con 120 ms, ±40 ms y 2 % de pérdida | **61 de 61.** <ul><li>Recoger cuatro consumibles: en la grilla en el mismo cuadro; el host contestó a los 166–214 ms.</li><li>Un veneno: −40 en el tick siguiente, sin corrección; el host lo confirmó a los 166 ms.</li><li>Dos botiquines con 60 y dos venenos seguidos (100 → 60 → 20).</li><li>La cápsula desde la barra: la muerte y el aviso al instante.</li><li>Uno que el host no pudo usar: la corrección lo deshace. Es la única corrección de la prueba.</li><li>La toxina: sin correcciones mientras baja, y quitó justo 20.</li><li>Al final, la salud, las muertes, los usos y el inventario dan igual en el host y en el cliente.</li></ul> |
| La misma, con 300 ms, ±80 ms y 8 % de pérdida | **61 de 61.** El host contestaba a los 317–434 ms: eso es lo que antes se esperaba |
| Lo de antes | Sin cambios: <ul><li>inventario 166 de 166, modelo 70 de 70, visual 7 de 7;</li><li>tres procesos: host 18, A 24 y B 7;</li><li>mantle 50 casos, agarre 22 de 22;</li><li>los 13 casos de red de la cámara lenta y los venenos, con las mismas correcciones que antes.</li></ul>La huella completa de la repetición pasa a `f9b53da25ac45f16` (el estado tiene un byte más); los 93 bytes del movimiento siguen dando `7d3d417dd954d05b`. El panel Objetos no cambió y sus pruebas no se volvieron a correr |

**Límite nuevo:** si tu PC predice una muerte por consumible y el host no la aplica (rarísimo: el objeto ya no estaba en tu inventario), el aviso ya salió. Si después morís de verdad con el mismo número, ese aviso no vuelve a salir. Es lo mismo que el agotamiento de la sección 10.

**Tu prueba:** en las dos PC, con +200 ms en las dos, el mismo 2026-11-04: "funciona correctamente". Commit local `c392774`, solo el código.

### Soltar sin esperar (2026-11-04, después de tu prueba)

Notaste que soltar algo con mucha latencia tardaba en aparecer en el piso: el host elegía el lugar y recién con su respuesta tu PC lo dibujaba. Ahora:

- **Tu PC elige el lugar** con la misma regla que el host: adelante del personaje o alrededor, con piso, a la vista y sin otro objeto encima. Lo dibuja ahí en el mismo cuadro y lo saca de la grilla.
- **Se lo manda al host en el pedido** (`DROP_AT`, nuevo). El host lo deja en ese mismo lugar si sirve, mirado desde tu personaje en el host, así no salta. Si no sirve, elige él, como antes, y el objeto aparece donde dice el host.
- **Vale para las tres maneras de soltar:** desde la mano con un clic afuera de la grilla, **Soltar** del menú y **Soltar una cantidad…**. También desde una caja abierta.
- **Sin lugar,** lo dice en el momento ("No hay lugar cerca para soltarlo"), sin preguntarle al host.

**Lo que eligió Claude:** el lugar que elige tu PC puede estar hasta 1 m más lejos de lo normal de tu personaje en el host. Es lo que pudo moverse el personaje mientras viajaba el pedido. El pedido viejo, donde el host elige el lugar (`DROP`), sigue andando para las pruebas.

**Dónde está:**

| Archivo | Qué cambió |
| --- | --- |
| `scripts/inventory/inv_protocol.gd` | El pedido `DROP_AT`, con el lugar en milímetros (`drop_args`, `drop_spot_of`) |
| `scripts/inventory/inv_authority.gd` | La regla del lugar pasó a una función que usan los dos (`find_drop_spot`); `drop_spot_ok` mira si el lugar que manda tu PC sirve, con el margen de 1 m (`DROP_LAG_MARGIN`) |
| `scripts/inventory/inv_net.gd` | `predict_drop_spot`: el lugar que elige tu PC; el piso se dibuja con lo soltado sin confirmar |
| `scripts/inventory/inv_replica.gd` | `predicted_drops`: lo soltado que el host todavía no confirmó; sale de la grilla en el mismo cuadro |
| `scripts/inventory/inv_ui.gd` | `drop_item`: las tres maneras de soltar mandan `DROP_AT`, sin "esperando…" |
| `scenes/net_lab/estados_test.gd` | Soltar una botella, en la sección 9 |
| `scenes/net_lab/inventario/pruebas/inv_instant_test.gd` | Soltar desde el menú y desde la mano, y las horas para medir |

**Probado:**

| Prueba | Resultado |
| --- | --- |
| `estados_test.tscn` | **104 de 104.** Lo nuevo: soltar una botella, que se ve en el piso en el mismo cuadro y una menos en la grilla, sin "esperando…"; el host la deja en ese mismo lugar y no queda nada sin confirmar |
| `inv_instant_test.tscn`, con 120 ms, ±40 ms y 2 % de pérdida, y con 300 ms, ±80 ms y 8 % | **69 de 69** las dos veces. Un veneno desde el menú y el botiquín entero desde la mano: en el piso en el mismo cuadro, y el host los dejó en el mismo lugar, a menos de 2 mm. Contestó entre 166 y 331 ms. Al final, todo igual en el host y en el cliente |
| Lo de antes | Inventario 166 de 166, tres procesos 18, 24 y 7, visual 7 de 7 |

**Tu prueba:** en las dos PC, el mismo día: funciona. Commit local `2cf8fb1`.

**Recoger y soltar, vistos desde el host.** Te pareció que recoger se ve antes que soltar. Lo medí con las dos PC en +200 ms, en `inv_instant_test`. Cada proceso anota la hora de la PC: el cliente cuando pide y el host cuando ve el cambio en el piso.

| Acción del cliente | Lo ve el host a los |
| --- | --- |
| Recoger (cuatro veces) | 232, 233, 240 y 240 ms |
| Soltar desde el menú | 238 ms |
| Soltar desde la mano | 238 ms |

Tardan lo mismo: es el viaje del pedido de ida. Lo único distinto: **Soltar** del menú sale al soltar el botón del mouse, como todo botón, y la E sale al apretarla. Esa diferencia es lo que tardás en soltar el clic. La prueba sigue anotando esas horas (las líneas "PIDE a las …" del cliente y "PISO a las …" del host), por si hay que volver a medirlo.

**El aviso de tu captura 1084** ("The variable "stack" is declared below in the parent block") era mío, de `inv_replica.gd`: dos variables con el mismo nombre en la misma vuelta. Funcionaba bien, pero se podían confundir. Le cambié el nombre a una (commit local `858df9a`). Cargando con el depurador todos los scripts que toqué estos días, no queda ningún aviso.

---

## 13. Los arreglos de la auditoría de GPT (2026-11-04, a la noche)

GPT revisó el inventario, la salud y la red en [`auditoria_inventario_salud_red_2026-11-04.md`](auditoria_inventario_salud_red_2026-11-04.md). Pediste revisar cada punto y arreglar lo necesario. Los nueve puntos se comprobaron contra el código: los cinco que marca como errores de hoy eran ciertos. De los cuatro riesgos a futuro, elegiste arreglar ahora tres chicos (ARQ-01, EDT-01 y ESC-01) y dejar anotado el cuarto (ESC-02). Lo que ves al jugar no cambia: usar, recoger y soltar siguen siendo instantáneos.

### Lo que estaba mal y cómo quedó

| Punto | Qué pasaba | Cómo quedó |
| --- | --- | --- |
| **INV-01** | El input llevaba solo el **último** uso. Si usabas dos cosas en ticks seguidos y el host se perdía el tick de la primera (el input llegó tarde), hacía solo la segunda. Además daba las dos por hechas, sin aviso. | Cada uso tiene su número y viaja en **todos** los inputs hasta que el host lo contesta. El host hace todos los que le faltan, en orden, y contesta **uno por uno** (el que no pudo, con su motivo). |
| **INV-02** | Recoger va por un camino (pedido) y usar por otro (input). Si recogías algo y lo usabas enseguida, el uso podía llegar antes: el host decía "ya no está en tu inventario" y la salud volvía. Además, la tecla de la barra rápida dejaba usar algo que estaba "esperando…" (el menú no). | El host respeta **el orden en que hiciste las cosas**: un uso espera a que el host procese lo que pediste antes, y un pedido espera a los usos de antes. La barra rápida respeta el "esperando…" igual que el menú. |
| **INV-03** | La grilla que ves sin esperar al host se armaba con todo lo recogido y soltado primero, y los usos al final. Si usabas la última unidad de una pila y después recogías otra del mismo tipo, veías la pila vieja llena. | Recoger, soltar y usar van en **un solo registro, con su orden**. Lo que ves es lo mismo que hacer las acciones una por una, y es lo que va a hacer el host. |
| **INV-04** | Si morías en el mismo tick en que apretabas Kp 1 y Kp 2 (con una cápsula, o con el daño en el tiempo), las teclas volvían a prender los estados después de la muerte. | **La muerte gana:** en ese tick las teclas se cuentan como apretadas pero no prenden nada. El tick termina con todo apagado. Una pulsación del tick siguiente ya vale. |
| **PRU-01** | Dos pruebas de red (`inv_instant_test` e `inv_pair_test`) daban "bien" aunque se les acabara el tiempo sin terminar. | Si se acaba el tiempo, si el recorrido no llega al final o si no comprobó nada, salen con error. |
| **ARQ-01** | Al usar sin esperar, tu PC aplicaba el efecto sin mirar la pila ni la barra. Hoy los consumibles no las miran, pero una capacidad futura (una carga, una munición) se rompería. | Cada capacidad dice si se puede **adelantar** (`predictable`). Los consumibles, sí. Una que no, sale como pedido y espera al host. Tu PC adelanta con una copia de la pila y la barra como estaban al usarla. |
| **EDT-01** | El documento del inventario decía que de un modelo "no corren sus scripts". No era del todo cierto: armar la miniatura o el objeto en el piso creaba la escena, y eso corre su `_init`. | Un modelo **con scripts** no se usa como apariencia: ni siquiera se crea. Se ve la caja de su color, y lo avisan el catálogo (en la consola) y la vista previa del panel **Objetos**. Los modelos de hoy son `.glb` sin scripts: no cambia nada. |
| **ESC-01** | Cada consumible usado redibujaba todos los objetos sueltos del mundo, y cada paquete del host podía redibujarlos dos veces. | Usar no redibuja el piso, y un paquete lo redibuja una sola vez. Varios usos en el mismo tick salen en un solo paquete del host. |
| **ESC-02** | La lista de tramos de cámara lenta crece toda la partida. | **Sin cambios, como elegiste.** Importa con partidas largas o guardadas: hay que resumir los tramos viejos sin mover las plataformas. Queda en "Límites" (abajo). |

### Lo que eligió Claude

- **Hasta 32 usos sin confirmar** en tu PC (en fila o en viaje); con más, dice "Esperá: hay muchos usos que el host todavía no confirmó". De esos, **hasta 8 viajan a la vez** en el input. Con la regla de un uso por tick, 8 son más de lo que tarda el host en contestar con 120 ms de ping. Así el número de cada uso, que da la vuelta en 256, nunca se confunde (GPT mostró que con 130 seguidos sí).
- **3 segundos de espera como mucho.** Si un uso espera un pedido que no llega, o al revés, a los 3 s el host sigue sin él: el uso se rechaza ("no llegó a tiempo lo que hiciste antes") y el pedido se procesa igual. Con un jugador normal no pasa: es para que nada quede trabado.
- **Un uso que el host no encuentra en el input** se contesta como perdido ("se perdió en el camino: probá de nuevo"). Con este juego no pasa, porque cada uso viaja hasta que el host lo contesta.
- **El uso que espera** se ve hecho en tu PC igual que siempre. En el host se hace unos ticks después y llega una corrección que no se nota: tu PC vuelve a aplicar el uso al repetir los ticks.
- **Las capacidades nuevas no se adelantan,** salvo que digan que sí (`predictable`). Así una que dependa de la pila no se rompe por olvido.

### En la red

- **El input:** 14 bytes, más 8 por cada uso sin confirmar (casi siempre ninguno o uno). Antes eran 17 fijos.
- **Cada pedido lleva el número del último uso** hecho antes que él.
- **El paquete del host** dice hasta qué uso llegó y cuáles no pudo hacer, cada uno con su motivo.
- **El estado del personaje no cambió** (153 bytes): la repetición da la misma huella, `f9b53da25ac45f16`.
- **Las dos PC tienen que tener esta versión:** en la notebook, `actualizar_lab.bat`, y para jugar a distancia, un `.exe` nuevo. Con versiones distintas la huella no deja entrar.

### Dónde está

| Archivo | Qué cambió |
| --- | --- |
| `scripts/actor/actor_input.gd` | `uses`: los usos sin confirmar, cada uno con su objeto y el pedido anterior; `read_from` descarta un input cortado o con más de 8 |
| `scripts/actor/actor_powers.gd`, `actor_motor.gd` | INV-04: si murió en el tick, las teclas no prenden nada |
| `scripts/net/sim_clock.gd`, `scenes/net_lab/net_lab.gd` | Le avisan al motor si el actor murió antes de moverse (por un consumible); el laboratorio arma el input con `InvNet.fill_input` |
| `scripts/net/net_sync.gd` | Lee el input nuevo; el input repetido trae los mismos usos |
| `scripts/inventory/inv_net.gd` | `queue_use`, `fill_input`, `use_before_step` (todos los usos que faltan, en orden, esperando al pedido anterior) y la fila de pedidos que espera al uso anterior |
| `scripts/inventory/inv_replica.gd` | Un solo registro con el orden; los usos con su número y su pedido anterior; la respuesta uso por uso; `world_view_changed` |
| `scripts/inventory/inv_authority.gd` | `use_from_input` anota la respuesta de cada uso; `use_refused` |
| `scripts/inventory/inv_protocol.gd` | El pedido lleva el uso anterior |
| `scripts/inventory/inv_ui.gd` | `use_item` respeta el "esperando…" y el límite de 32; lo que no se adelanta sale como pedido |
| `scripts/inventory/inv_ability.gd`, `inv_consumable.gd` | `predictable` |
| `scripts/inventory/inv_visuals.gd`, `inv_catalog.gd`, `addons/inventario_objetos/vista_previa.gd` | Modelos con scripts: no se usan, y se avisa |
| `scenes/net_lab/estados_test.gd`, `inventario/pruebas/inv_model_test.gd`, `inv_instant_test.gd`, `inv_pair_test.gd` | Las pruebas nuevas y el tiempo agotado como falla |

### Probado (2026-11-04, en esta PC)

| Prueba | Resultado |
| --- | --- |
| `inv_model_test` | **91 de 91** (antes 70). Lo nuevo: lo que se ve igual que hacer las acciones una por una, comparando id, cantidad, versión, celda y giro (usar lo último y recoger; recoger y usar; soltar parte y usar; un recoger rechazado en el medio); la respuesta uso por uso con el número dando la vuelta (254, 255, 0); el input de ida y vuelta, y uno cortado o con 9 usos se descarta; un modelo con `_init` no lo corre, no se usa y el catálogo lo avisa, y uno sin scripts se arma como siempre |
| `estados_test` | **129 de 129** (antes 104). Lo nuevo: <ul><li>la cápsula y el daño en el tiempo matando en el mismo tick de Kp 1 y Kp 2: todo apagado, también después; B sigue con su cámara lenta; una pulsación posterior sí prende;</li><li>dos usos que llegan juntos: veneno y después botiquín, 60 → 20 → 70; el mismo input otra vez no repite nada, y uno viejo tampoco;</li><li>dos que faltan en el input se contestan como perdidos;</li><li>un uso que espera su pedido, y un pedido que espera su uso;</li><li>los dos que nunca llegan, a los 3 s;</li><li>el límite de 32.</li></ul> |
| `inv_instant_test`, host y cliente | **83 de 83** (antes 69) con 120 ms, ±40 ms y 2 % de pérdida, y también con 300 ms, ±40 ms y 8 %. Lo nuevo es el caso de GPT: recoger un veneno que no tenías y usarlo enseguida, con el pedido de recoger 350 ms más tarde que el input. Se ve usado en el tick siguiente, el host lo hace después de recogerlo y no sale "No se usó" |
| El tiempo agotado | El host solo, sin cliente y con 3 s de límite: las dos pruebas de red salen **con error** (antes salían bien) |
| `inv_lab_test`, `inv_pair_test` (tres procesos) | 166 de 166; host 18, A 24 y B 7, sin fallas: iguales |
| Repetición, mantle, agarre por encima del filo | Iguales: huella `f9b53da25ac45f16`, 50 casos, 22 de 22 |
| El panel **Objetos**, en una copia del proyecto | 159 de 159 en el editor y 26 de 26 jugando: iguales |
| Que las pruebas nuevas de verdad detecten | Con el arreglo de INV-04 apagado, la prueba de estados falla (termina con los dos estados prendidos, como dijo GPT). Con los usos al final, como antes, la del modelo falla (se ve la pila vieja ×5) |
| Avisos de GDScript | Cargando con el depurador todos los scripts tocados: ninguno |

### Lo que no se probó y lo que queda

- **Con el `.exe`.** En las dos PC lo probaste el mismo día (abajo, "Resultado").
- **INV-01 e INV-04 no se pueden provocar a mano:** hace falta que el host se pierda un tick justo, o morir en el mismo 1/60 s en que apretás las teclas. Los cubren las pruebas automáticas.
- **ESC-02** (el historial de la cámara lenta): queda para cuando haya partidas largas o guardadas.
- **ESC-01, lo que no se hizo:** el host sigue mandando la grilla entera con cada cambio, y redibujar el piso todavía recorre todos los objetos sueltos. Con la zona del laboratorio no pesa. Antes de mapas con muchos objetos o grillas grandes, hay que medir cuánto ocupa cada paquete y cuánto tarda cada acción.

### Tu prueba en las dos PC

Lo de siempre tiene que seguir andando igual. En la notebook, primero `actualizar_lab.bat`.

1. En las dos PC, abrí Godot, elegí **net_lab** y apretá **F6**. En esta PC, **Crear partida**; en la notebook, **Unirse** con la IP de siempre.
2. En las dos, **Alt + 4** (internet mala, +200 ms), como en tu prueba anterior.
3. Caminá hasta la **Zona de inventario**. Mirá un **Frasco de veneno**, apretá **E** y enseguida **Tab**. Hacé clic derecho sobre el veneno → **Usar**, lo más rápido que puedas. La salud baja 40 en el momento y no sale "No se usó".
4. Recogé un **Botiquín** y usalo: la salud vuelve a 100. Después, con el inventario abierto (**Tab**), hacé clic en el veneno y clic en el acceso **1** de la barra de abajo. Cerrá con **Tab** y apretá **1** dos veces rápido: baja a 60 y a 20, sin avisos.
5. Prendé el súper (**Kp 2**) y la cámara lenta (**Kp 1**). Recogé la **Cápsula letal** y usala: "Moriste" y los dos estados apagados. Después, **Kp 2** sí prende el súper.
6. Soltá algo y recogelo, como siempre.

Si algo se ve distinto de antes, mandame la captura o el video.

**Resultado (2026-11-04):** esta lista resultó larga. La hiciste en cuatro pasos, de a uno, con **Alt + 4** en las dos: recoger y usar enseguida desde la notebook, morir con el súper prendido, soltar y recoger, y recoger y usar enseguida desde el host. **Todo funcionó.** "Lo más rápido que puedas" no hacía falta: lo que pasa en el mismo 1/60 s nadie lo hace a mano, y eso lo cubren las pruebas automáticas.

Notaste que, con las dos en Alt + 4, la cámara lenta tarda en arrancar también en el host. No es de este cambio, y el host no trabaja como cliente. La cámara lenta es del mundo: el host la programa para un poco más adelante, así llega el aviso a la notebook y arranca en el mismo tick en las dos. Con las dos en Alt + 4 se suman las dos demoras y la espera crece. Es de las "Mecánicas que dependen de un buen internet" de la guía.
