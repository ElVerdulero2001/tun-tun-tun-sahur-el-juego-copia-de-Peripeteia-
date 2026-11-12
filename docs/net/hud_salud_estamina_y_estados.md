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
- **Integridad corporal, luz naranja, daño de caída y muerte** (2026-11-05, punto 1 del [roadmap](roadmap_integridad_habilidades_y_luz.md), sección 14): seis partes del cuerpo con su porcentaje en un panel a la derecha del inventario, la luz naranja que avisa de lesiones, el daño al aterrizar y una caída de cámara y un desplome al morir. **Pendiente de tu prueba manual.**
- **El botiquín sobre una parte del cuerpo y las vendas** (2026-11-06, sección 15): con Tab, el botiquín soltado sobre una parte dañada la deja al 100 %; las vendas curan la mitad que el botiquín. **Pendiente de tu prueba manual.**
- **El panel del cuerpo y curar una parte, sin esperar al host** (2026-11-06 a la noche, sección 16): las piernas después de una caída y la parte curada se ven en el momento, también en el cliente con latencia. Lo probaste con latencia alta el 2026-11-08: "funciona correctamente".
- **Abrir una caja sin que se vea la integridad** (2026-11-08, sección 17): E entra directo en modo caja; mientras el host contesta, el lado derecho queda reservado para la caja. Lo probaste en las dos PC, con latencia alta: funciona.
- **Tab con una caja abierta cierra solo la caja** (2026-11-08 a la tarde, final de la sección 17): el inventario sigue abierto y a la derecha vuelve la integridad. Lo probaste en red: funciona.
- **El selector de habilidades con la Q** (2026-11-08, punto 2 del [roadmap](roadmap_integridad_habilidades_y_luz.md), sección 18): mantener Q abre un círculo con velocidad y salto a la izquierda y cámara lenta a la derecha; soltar Q prende o apaga la marcada. La adopción pasó a F2. Lo probaste en las dos PC el 2026-11-09: funciona.
- **Las luces arriba a la izquierda y la luz naranja que parpadea** (2026-11-09, sección 19): las luces de las habilidades quedan fijas arriba a la izquierda, también con el inventario o el selector abiertos; la luz naranja parpadea con alguna parte en 60 % o menos, como tu concepto. Lo probaste en red el 2026-11-10: funciona; las luces encima de la grilla pasaron a quedar debajo. Lo confirmaste: commit local `b6b1bfc`.

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
3. **Capacidades** → **+ Consumible**. Aparecen cinco números:
    - **Efecto en la salud (puntos):** positivo cura y negativo daña. La salud completa son 100: con −100 o menos, una unidad mata. En 0 no la toca.
    - **Recupera estamina:** la reserva completa son 200. En 0 no la toca.
    - **Daño en el tiempo (puntos)** y **En cuántos segundos** (desde la tarde, sección 11): quita esos puntos de a poco, parejo, en esos segundos. Con 4 y 2, la vida baja 2 por segundo durante 2 s. En 0 puntos no hace nada.
    - **Cura una parte del cuerpo** (desde el 2026-11-06, sección 15): con **Tab**, soltándolo sobre una parte dañada del panel del cuerpo, le suma ese porcentaje, sin pasar del 100 %, y gasta una unidad. 100 la deja entera; 30 lleva una del 50 % al 80 %. No cambia el uso normal. En 0 no cura partes.

    Debajo, una línea dice lo que hace con esos números. Por ejemplo: "Al usar una unidad: cura 30 de salud (sin pasar del máximo; con la salud completa no se usa ni se gasta)".
4. **Guardar.** Si no hace nada (los cinco en 0), no se guarda: "El consumible no hace nada". Un daño en el tiempo tiene que durar de 0,1 a 600 s, y lo que cura de una parte va de 0 a 100 %. Uno que solo cura partes se guarda: usado normal no hace nada ni se gasta.
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

El [roadmap de integridad, habilidades y luz](roadmap_integridad_habilidades_y_luz.md) describe el panel corporal, la luz naranja, el selector radial, el termómetro, el daño de caída y la animación de muerte previstos para `net-lab`.

- **Tu prueba** (escrito el 2026-11-02): faltaba, solo y en las dos PC (la lista de la sección 2). El 2026-11-04 la hiciste en red: "todas funcionan correctamente". Falta con el `.exe` exportado.
- **La cámara más lenta que viste no se reprodujo** (sección 7).
- **Un agotamiento predicho que el host corrige** (por ejemplo, porque te llegó una bebida justo antes) ya sonó. Si después te agotás de verdad con el mismo número, no vuelve a sonar. Es raro: hace falta un consumible en el mismo momento.
- **Si uno suelta la cámara lenta y otro la pide un instante después,** pero ya tarde para avisar a todos que el tramo sigue, el mundo va normal unos pocos ticks (como mucho lo que tarda en avisarse, 0,1 a 0,3 s) y vuelve a ir lento.
- **Mientras el host no da por cortado a un jugador** (5 s sin noticias), su personaje sigue con lo que tenía prendido y paga.
- **Un input que llega tarde con un estado que se apaga** trae una corrección: el host no adopta una estamina mayor que la suya. Con internet normal no pasó en las pruebas.
- **La placa de los instrumentos tapa** la parte de abajo a la izquierda del panel de valores (**F1** lo oculta).
- **Con una caja de muchísimas filas,** las celdas se achican y la caja podría quedar encima de los instrumentos en 1280 × 720. Con las cajas del laboratorio no pasa.
- **Lo que queda para después:**
    - ~~la luz naranja sigue apagada hasta que exista la integridad del cuerpo~~ (desde el 2026-11-05 avisa de lesiones: sección 14);
    - el termómetro marca 100 fijo hasta que se mida la luz;
    - no hay elementos del escenario que dañen, ni enemigos, hambre, reaparición ni guardado. El daño de caída existe desde el 2026-11-05 (sección 14).

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

---

## 14. Integridad corporal, luz naranja, daño de caída y muerte (2026-11-05)

Pediste implementar el punto 1 del [roadmap](roadmap_integridad_habilidades_y_luz.md): la integridad del cuerpo, la luz naranja, el daño de caída y una muerte que se vea. **Estado: implementado, pendiente de tu prueba manual.** Es todo del laboratorio: no se tocaron modelos, texturas, materiales, recursos ni escenas del juego, ni `net_lab.tscn`, `actor.tscn` o el nivel (las tablas de la torre se arman por código, como el resto de la torre).

### Lo que decidiste vos (en el pedido)

- **Seis partes independientes,** de 0 a 100: cabeza, torso, brazo izquierdo, brazo derecho, pierna izquierda y pierna derecha.
- **Con Tab,** el inventario a la izquierda y la integridad a la derecha: una silueta simple con el porcentaje de cada parte, verde completa y cada vez más roja al bajar. **Con una caja abierta, la caja tiene prioridad** en ese lugar, para seguir pasando objetos. El panel muestra al jugador local y se actualiza mientras está abierto.
- **La luz naranja,** la que ya estaba debajo de la salud: prendida mientras alguna parte tenga menos del 100 %, apagada con las seis completas. La salud y la integridad se leen por separado.
- **El daño de caída,** una vez al aterrizar, según la velocidad contra el piso, contando las plataformas que se mueven, con los umbrales en el **Tuning**, y tres resultados que se puedan repetir en la torre del laboratorio: seguro, lastima la salud y las piernas, y letal. Con margen para un salto normal con el súper.
- **La muerte:** la caída letal y la cápsula letal por el mismo flujo de siempre, con una caída breve de cámara en primera persona y un desplome que vea el compañero, una vez por muerte aunque haya correcciones. La salud se recupera en el lugar, como en la muerte de prueba.
- **Reglas provisorias del laboratorio:** el daño de integridad de una caída se reparte por igual entre las dos piernas, y cada una guarda su valor; por ahora las lesiones solo se ven en el panel y en la luz (no cambian el movimiento); el botiquín cura la salud general y no la integridad; la muerte de prueba devuelve las seis partes al 100 %, para repetir el ensayo. *(Desde el 2026-11-06, el botiquín soltado sobre una parte del panel la cura: sección 15.)*

### Lo que eligió Claude (lo podés cambiar)

- **Los umbrales:** hasta **10 m/s** contra el piso no pasa nada (caer caminando unos 5 m); desde **13 m/s**, letal (unos 8,6 m). En el medio, la salud baja en proporción, de casi nada a casi toda, y las piernas pierden entre las dos, en la misma proporción, hasta **150 puntos** (75 cada una). Un salto normal llega al piso a 4,7 m/s y uno con el súper a 7,2: le quedan 2,8 m/s de margen.
- **La velocidad que cuenta** es la que va contra el piso: la parte hacia la normal del piso, relativa a la base donde cae. Correr y saltar no suma (llega igual que parado); caer sobre una plataforma que sube golpea más, y sobre una que baja, menos.
- **El daño va en puntos enteros de salud** y en medios puntos por pierna: una diferencia de milésimas en la velocidad entre dos máquinas casi nunca cambia el resultado.
- **El panel:**
    - la silueta vista de atrás, como ves a tu personaje en tercera persona: tu izquierda queda a la izquierda, con "izq." y "der." arriba de los brazos;
    - el porcentaje entero, redondeado para abajo: con algo menos del 100 % ya no dice 100;
    - verde, amarillo, naranja y rojo según baja;
    - al lado de tu grilla y con su mismo alto;
    - un clic con un objeto en la mano sobre el panel no lo suelta al piso.
- ~~**El panel y la luz muestran lo que confirmó el host,** como dice el roadmap.~~ **Cambiado el 2026-11-06 a la noche (sección 16): ahora muestran lo predicho, como la aguja, sin esperar.** Lo de antes: En el host y jugando solo es instantáneo. En el cliente llegan un poco después de la aguja de la salud, que sigue mostrando lo predicho: lo que tarda la confirmación del host, más o menos un viaje de ida y vuelta (no se midió).
- **El desplome:** la cápsula cae de espaldas (la nariz queda para arriba y se ve de cualquier lado) en 0,45 s, queda en el piso 0,9 s y se levanta en 0,45 s. Es solo dibujo: la simulación no lo lee, y si te movés mientras dura, el dibujo se desliza acostado. Lo equipado se inclina con el cuerpo. Los tiempos son constantes de `actor_body.gd` (`COLLAPSE_FALL`, `COLLAPSE_DOWN`, `COLLAPSE_RISE` y `COLLAPSE_ANGLE`).
- **La cámara en primera persona** baja a 0,35 m del piso y se ladea 70° mientras dura el desplome, y vuelve. En tercera persona no se mueve: ves el desplome de tu cápsula.
- **El aviso** ahora dice "Muerte de prueba: la salud y el cuerpo volvieron al máximo y se apagaron tus estados".
- **Las tablas de la torre de parkour** (`parkour_tower.gd`), cada una saliendo 2 m hacia afuera sobre el piso libre, a ras de su terraza y con su cartel:
    - **verde**, desde la terraza 2 (4 m), por la cara oeste, del otro lado del techo bajo del tramo 3: segura;
    - **amarilla**, desde la terraza 3 (7 m), enfrente de donde llega la escalera del tramo 4: lastima;
    - **roja**, desde la terraza 4 (9,5 m), enfrente de donde se sube colgándose (tramo 6): letal.

    A la 2 y a la 3 se llega solo con escaleras: la de vuelta y la del tramo 4.
- **El panel de valores (F1)** tiene dos líneas nuevas: la integridad de cada parte, con "luz naranja prendida" o "apagada", y el último aterrizaje, por ejemplo "Último aterrizaje: 11.57 m/s contra el piso (segura hasta 10.0, letal desde 13.0) · quitó 52 de salud".

### Cómo funciona

- **La integridad vive en el personaje (`ActorState.integrity`):** seis números, en centésimas de punto. Viaja en cada snapshot, se predice y se repite como la salud. El estado pasó de 153 a 165 bytes; los primeros 93 siguen siendo los del movimiento.
- **El motor (`ActorMotor`, etapa 8)** mira si el tick arrancó sin apoyo y un movimiento libre lo dejó apoyado: eso es aterrizar. Pasa una sola vez por caída: repetir ticks parte del estado guardado y calcula lo mismo. Agarrarse de un borde, una escalera, un cable o un compañero antes de tocar el piso no es aterrizar; la caída cuenta desde donde te soltás.
- **`ActorVitals.land`** aplica el daño: salud y piernas, o la muerte de prueba si es letal o si la salud llega a cero. **`ActorVitals.die`** ahora devuelve además las seis partes al 100 %. La cápsula letal ya pasaba por `die`: es el mismo flujo.
- **Una vez por muerte:** el aviso del HUD, el desplome (`ActorBody.present`) y la caída de cámara salen de que avance el contador de muertes. Si una corrección lo hace volver atrás y adelante, no pasa del mismo número y no se repite. El compañero ve el desplome con el estado que manda el host.
- **El host no adopta** lo que afirma un cliente con otra integridad (`ClaimAdoption`): una caída que el host vio distinta vale la suya.

### Los valores

| Dónde | Valor | De fábrica | Qué es |
| --- | --- | --- | --- |
| **Tuning** → **Daño de caída** | **Fall Safe Speed** | 10 m/s | Hasta esta velocidad contra el piso, nada |
| **Tuning** → **Daño de caída** | **Fall Lethal Speed** | 13 m/s | Desde esta, muerte de prueba |
| **Tuning** → **Daño de caída** | **Fall Leg Damage** | 150 | Lo que pierden las dos piernas juntas justo debajo de la letal, la mitad cada una; 0 apaga el daño a las piernas |
| **CameraRig** → **Muerte** | **Death Eye Height** | 0,35 m | Hasta dónde baja la cámara en primera persona |
| **CameraRig** → **Muerte** | **Death Roll Degrees** | 70° | Cuánto se ladea |

Los del **Tuning** tienen que ser iguales en las dos PC (están en la huella); los del **CameraRig** pueden ser distintos. El súper no cambia los umbrales.

### Cuánto da cada caída (medido)

| Caída | Contra el piso | Resultado |
| --- | --- | --- |
| Salto normal, parado o corriendo | 4,65 m/s | Nada |
| Salto con el súper, en el piso | 7,24 m/s | Nada |
| Tabla verde (4 m), caminando hasta la punta | 8,80 m/s | Nada |
| Tabla amarilla (7 m) | 11,57 m/s | −52 de salud (queda 48: la aguja en 4,8); cada pierna −39,5 % (queda 60,5 %: el panel dice "60 %") |
| Tabla roja (9,5 m) | 13,53 m/s | Letal |
| Colgado del borde de la terraza 2 y soltándose con Ctrl (2 m) | menos de 10 m/s | Nada |
| Desde 7 m, quieto en el aire (la prueba de red) | 11,74 m/s | −58 de salud; piernas al 56,5 % |
| Sobre el ascensor desde 9,5 m, según cómo vaya | 11,90 o 13,88 m/s | −63, o letal |

### En la red

- **El estado tiene 12 bytes más (165).** La huella cambió (código y Tuning): en la notebook, `actualizar_lab.bat`; para jugar a distancia, un `.exe` nuevo.
- **Lo calcula el motor en el host y en la predicción,** con el mismo input: no hace falta un mensaje nuevo. Una caída que se ve igual en las dos máquinas no trae corrección.
- **Para las pruebas de Claude:** `--test-drop-at=S:ALTO:X:Z` (solo host: a esos segundos pone a los demás en el aire a esa altura y caen) y `--test-drop-all-at=…` (también al del host). Con `--autoquit`, cada máquina anota cada aterrizaje con daño que calculó, una vez, y el resumen dice cuántos desplomes dibujó de cada jugador.

### Dónde está

| Archivo | Qué cambió |
| --- | --- |
| `scripts/actor/actor_state.gd` | `integrity`, las partes (`Part`), `injured()`; 165 bytes |
| `scripts/actor/actor_tuning.gd` | El grupo **Daño de caída**; los umbrales no van con el súper (`NOT_BOOSTED`) |
| `scripts/actor/actor_vitals.gd` | `land` (el daño de caída); `die` devuelve las seis partes |
| `scripts/actor/actor_motor.gd` | Etapa 8: el aterrizaje y su velocidad contra el piso |
| `scripts/actor/actor_body.gd` | El desplome (nodo **Desplome** dentro de **Visual**, armado por código), `collapse_amount` y `last_landing` |
| `scripts/net/claim_adoption.gd` | La adopción exige la misma integridad |
| `scripts/inventory/inv_ui.gd` | `side_panel_rect`: el lugar del panel a la derecha (vacío con una caja abierta); ahí un clic no suelta al piso |
| `scenes/net_lab/hud/lab_hud.gd` | La luz naranja, el panel de integridad, `confirmed_state` y el texto del aviso |
| `scenes/net_lab/lab_camera.gd` | La caída de cámara en primera persona (grupo **Muerte**) |
| `scenes/net_lab/net_lab.gd` | El estado confirmado para el HUD, las dos líneas del panel de valores, `--test-drop-at`, `--test-drop-all-at` y lo que imprime el resumen |
| `scenes/net_lab/parkour_tower.gd` | Las tres tablas y sus carteles |
| `scenes/net_lab/integridad_test.gd` y `.tscn` (nuevos) | La prueba de un proceso |

### Probado (2026-11-05, en esta PC)

| Prueba | Resultado |
| --- | --- |
| `integridad_test.tscn` (nueva, un proceso, el laboratorio de verdad) | **72 de 72.** <ul><li>El estado de ida y vuelta (165 bytes, los 93 del movimiento iguales) y la adopción que rechaza otra integridad.</li><li>Salto normal, corriendo y con el súper: sin daño.</li><li>Las tres tablas, caminando hasta la punta: la verde, nada; la amarilla, la salud y las dos piernas lo que dice la cuenta, lo demás al 100 %, la luz prendida y el texto de cada pierna en el panel; la roja, en primera persona: una muerte, todo al 100 %, la luz apagada, un aviso, un desplome, la cámara a menos de 0,6 m del piso y después de vuelta en la cabeza, sin repetirse.</li><li>El panel a la derecha de la grilla, del mismo alto y dentro de la pantalla; un objeto en la mano no se suelta sobre él; con la caja abierta, la caja ocupa el lugar y el panel no se ve.</li><li>El botiquín cura la salud y deja las piernas y la luz igual; la cápsula: el mismo desplome y el mismo aviso, una vez, y todo al 100 %.</li><li>Cayendo junto al borde de la terraza 2, mirándolo, se agarra y no hay daño; al soltarse, 2 m sin daño; mirando para afuera, la misma caída lastima.</li><li>Una plataforma de prueba que sube y baja a 4,7 m/s: la velocidad contra ella es la propia más la suya (subiendo) o menos (bajando).</li><li>Repetir los ticks de una caída de 7 m y de una de 12 m desde medio metro antes del piso, como una corrección: el mismo tick, el mismo estado byte a byte, sin cobrar dos veces, una sola muerte, un solo desplome y un solo aviso.</li></ul> |
| Red, host y cliente en esta PC, con `--test-drop-at` (7 m, 12 m, 3 m y 6 m sobre el ascensor), `--test-harm-at` (como la cápsula) y `--test-drop-all-at` (los dos desde 12 m) | Con +120 ms, ±20 ms y 1 % de pérdida, y con +200 ms, ±40 ms y 5 % (como Alt + 4): **los mismos aterrizajes, en el mismo tick y con los mismos números en el host y en el cliente.** El cliente: tres muertes, tres avisos, tres desplomes propios y **uno del host** (lo que ve el compañero); el host: uno propio y tres del cliente. Correcciones: 6, las de los eventos de prueba (cada caída de prueba es un teleport del host). Adopción: 0 rechazos por datos imposibles |
| Lo mismo, con el host sin adopción y el cliente corrido 2 mm al azar en cada tick (`--test-perturb-mm=2`), para forzar correcciones | **101 correcciones** con sus repeticiones de ticks: cada aterrizaje se calculó una vez, igual que en el host; tres avisos y tres desplomes, sin repetirse |
| Cuatro caídas sobre el ascensor (que se mueve), con +200 ms | Host y cliente iguales, sobre la base del ascensor: 11,90 m/s (−63) y 13,88 m/s (letal), según cómo iba. 4 correcciones, las de las caídas de prueba |
| `estados_test` | **129 de 129**, igual que antes |
| `actor_replay_test` | Coincide. La huella completa pasa de `f9b53da25ac45f16` a `38989aaf9fd19d18` porque el estado lleva la integridad; **los 93 bytes del movimiento siguen dando `7d3d417dd954d05b`** (con una copia de la prueba que calcula las dos). El recorrido no tiene caídas con daño |
| `mantle_test`, `grab_above_test`, `hang_sweep_test` | 50 casos, 22 de 22 y los cinco criterios del barrido: iguales |
| `inv_model_test`, `inv_lab_test`, `inv_instant_test` (con 120 ms), `inv_pair_test` (tres procesos) | 91 de 91, 166 de 166, 83 de 83, y host 18, A 24 y B 7: iguales |
| Avisos de GDScript | Cargando con el depurador todos los scripts tocados: ninguno |
| Capturas con ventana (internas, no son entregables) | El HUD con la luz prendida, el panel con las piernas y un brazo lastimados, la caja en lugar del panel, las tablas desde el piso, el desplome de costado y la primera persona. Con eso, el desplome pasó de boca abajo a de espaldas (boca abajo, la nariz quedaba debajo de la cápsula) y la tabla del medio, de naranja a amarilla (se confundía con los techos bajos, que son naranjas) |

**Para correrlas** (Claude): `--headless --fixed-fps 60 --scene res://scenes/net_lab/integridad_test.tscn`. Las de red: host `--host --port=N --autoquit=42 --test-drop-at=6:7:-4:-24,12:12:-4:-24,18:3:-4:-24,24:6:-9:-12 --test-harm-at=29 --test-drop-all-at=33:12:-7:-24`, y cliente `--client --address=127.0.0.1 --port=N --autoquit=38 --sim-rtt=200 --sim-jitter=40 --sim-loss=5` (el cliente cierra antes, para imprimir con el host todavía conectado). En (−4, −24) no hay nada arriba; sobre donde se aparece pasa un cable que el salto con el súper alcanza.

### Lo que no se probó y los límites

- **A mano, en las dos PC y con el `.exe`.** Es tu prueba (abajo).
- **El salto en el aire frena la caída:** cayendo sin haber saltado (te caíste o te soltaste), Espacio justo antes del piso te da la velocidad de un salto para arriba, y el aterrizaje ya no lastima. Es el salto en el aire de siempre; no se cambió.
- **En la zona y la torre de servicio,** las caídas de más de unos 8,6 m ahora matan (con la muerte de prueba, en el lugar). Por ejemplo, caer de una terraza a la de abajo.
- ~~**En el cliente, el panel y la luz llegan un viaje de ida y vuelta después de la aguja de la salud**~~ (lo confirmado por el host contra lo predicho). Resuelto el 2026-11-06 a la noche: sección 16.
- **Si te movés durante el desplome,** el dibujo se desliza acostado: es solo dibujo y dura 1,8 s.
- **Sobre una plataforma que se mueve, al repetir ticks** se usa su velocidad de ahora (las bases no se rebobinan): una corrección que repite el aterrizaje podría dar otro daño, y lo arregla la corrección siguiente del host. En las pruebas no pasó.
- **Sobre la balsa del host** (la que solo mueve el host), el cliente la ve con atraso: un aterrizaje ahí puede traer una corrección de la salud, como el mantle sobre ella. Va con lo que depende de un buen internet.
- **Una muerte que el cliente predijo y el host no confirmó** ya mostró el aviso y el desplome; si después morís de verdad con el mismo número, no vuelven a salir. Es el mismo límite del aviso de la sección 10.
- **Morir colgado** (por la cápsula o la toxina) inclina el cuerpo con las manos en el filo. No se miró.

### Tu prueba

Lo automático ya cubrió las cuentas, la red con latencia y las repeticiones. Esto es para ver que se vea y se sienta bien.

**Dónde están las tablas:** la torre de parkour está adelante a la izquierda de donde aparecés, a unos 30 m (el núcleo gris con terrazas color arena). La escalera de vuelta y la tabla verde están del lado izquierdo de la torre, mirando desde donde aparecés: rodeala por la izquierda.

**Solo** (esta PC, pestaña **net_lab**, **F6** → **Jugar solo**):

1. **El súper en el piso:** **2** del teclado numérico y **Espacio**. Al caer, nada: la salud en 10 y la luz apagada. Apagalo con **2**.
2. **La tabla verde (4 m):** subí la escalera de vuelta a la terraza 2, pasá agachado (**Ctrl**) por debajo del techo bajo, y la tabla queda a tu izquierda. Caminá hasta la punta y seguí de largo. Al caer, nada. En el panel de valores: "Último aterrizaje: 8.80 m/s … sin daño".
3. **La tabla amarilla (7 m):** desde la terraza 2, la escalera del cartel "4 · escalera". Arriba, la tabla está enfrente: caminá derecho y seguí de largo. Al caer, la aguja de la salud baja a 4,8 y **se prende la luz naranja**. Con **Tab**, a la derecha, la silueta con las dos piernas en **60 %**, amarillentas, y lo demás en 100 %, verde. Con una caja abierta (en la zona de inventario), la caja ocupa ese lugar.
4. **La tabla roja (9,5 m), en primera persona:** desde la terraza 3, cruzá el hueco (tramo 5) y colgate del borde de la terraza 4 (tramo 6). Arriba, la tabla está enfrente. Acercá la cámara con la rueda hasta primera persona y caminá hasta caer: un "Moriste", **la cámara cae al piso ladeada y vuelve** en unos 2 s, la salud en 10, la luz apagada y, con **Tab**, todo en 100 %.

**Como cliente con latencia** (esta PC, **Crear partida**; la notebook, después de `actualizar_lab.bat`, **Unirse** y **Alt + 4**). De a una, mirando las dos pantallas:

1. **La notebook hace la tabla amarilla.** En la notebook, la aguja baja enseguida, y la luz y las piernas del panel un instante después (cuando confirma el host). En esta PC, el compañero aterriza normal.
2. **La notebook hace la tabla roja.** En la notebook, un "Moriste" y la cámara que cae (en primera persona). En esta PC, **la cápsula del compañero cae de espaldas, queda en el piso y se levanta, una sola vez**.
3. **La notebook usa la Cápsula letal** (zona de inventario). Lo mismo que en el punto 2, una vez en cada pantalla.
4. **Esta PC hace la tabla roja.** En la notebook se ve tu cápsula desplomarse una vez.

---

## 15. El botiquín sobre una parte del cuerpo y las vendas (2026-11-06)

Pediste seguir el punto 1 del [roadmap](roadmap_integridad_habilidades_y_luz.md): curar una parte dañada con el botiquín, desde el panel de integridad, y un consumible nuevo de curación menor. **Estado: implementado, pendiente de tu prueba manual.** El selector radial y el termómetro siguen para sus etapas.

### Lo que decidiste vos (en el pedido)

- **El gesto de siempre:** con **Tab**, un clic agarra el botiquín de la grilla y otro clic lo suelta sobre una parte dañada del panel corporal.
- **Si la parte está dañada,** vuelve al 100 % y se gasta un solo botiquín. Solo esa parte cambia: la salud y las otras partes quedan como estaban. Anda también con la salud completa.
- **Si la parte ya está al 100 %,** si el objeto no cura partes o si el clic cae entre dos partes, el objeto sigue en el cursor y no se gasta nada. Un clic dentro del panel nunca lo tira al mundo.
- **El panel se actualiza:** el porcentaje y el color de la parte curada. La luz naranja sigue prendida mientras quede otra parte dañada y se apaga al curar la última.
- **El uso normal del botiquín** (inventario o barra rápida) sigue curando la salud general. La capacidad de curar partes va en los datos del consumible, para poder sumar después uno que repare solo una parte del porcentaje.
- **Las Vendas:** curan la mitad de salud que el botiquín, con el mismo tope; por ahora no curan partes. Una en la zona de pruebas.
- **En red:** el host valida que el botiquín siga en tu inventario, que la parte sea de tu personaje y que siga dañada, y cura y gasta en una sola operación. Un clic repetido, un reintento o un rechazo no duplican la curación ni hacen desaparecer el objeto.

Esto cambia una de las reglas provisorias de la sección 14: el botiquín, usado normal, sigue sin curar la integridad, pero soltado sobre una parte la cura.

### Lo que eligió Claude (lo podés cambiar)

- ~~**Es un pedido al host,**~~ **Cambiado el 2026-11-06 a la noche (sección 16): ahora es un uso en el input y se ve al instante.** Lo de antes: era un pedido al host, como mover o equipar (`HEAL_PART`, nuevo), y no un uso sin esperar como el uso normal. El panel ya muestra lo confirmado por el host, así que la parte se pinta cuando el host contesta. Mientras tanto, el botiquín se ve "esperando…" en su lugar y no se puede volver a agarrar: un segundo clic no sale como otro pedido. Medido en esta PC: con +120 ms, la pierna se pintó a los 178 ms del clic; con +200 ms, a los 269 ms. Si preferís que se vea al instante, como el uso normal, se puede cambiar.
- **Al soltarlo, la mano queda vacía** y lo que queda de la pila vuelve a su lugar. Para curar otra parte, se agarra de nuevo.
- **Clic derecho sobre el panel** no cura: dice "Para curar una parte, clic izquierdo sobre ella" y lo seguís teniendo.
- **La parte bajo el cursor se marca:** con algo en la mano, borde blanco si ese objeto la cura (arriba del panel: "Clic: curar pierna izquierda"), borde rojo si no ("Esto no cura esa parte"). Al soltar, abajo sale "Parte curada: pierna izquierda".
- **El número del consumible** se llama **Part Repair** (grupo **Partes del cuerpo**), en puntos de porcentaje: 100 deja la parte entera; 30 la sube 30 puntos, sin pasar del 100 %; 0 no cura partes. El botiquín tiene 100 y las vendas 0. Lo que dice la ventana **Inspeccionar** del botiquín lo cuenta. **Desde la tarde del 2026-11-06 está en el panel Objetos** (lo pediste al no encontrarlo): ver más abajo.
- **El host sube la época** al curar una parte, como en un empujón: tu PC se entera con una corrección que no se nota.
- **Las Vendas:** 1 × 1, pila de 5, color crema, en la tercera columna de la zona, después de la toxina lenta.

### En el panel Objetos (2026-11-06, tarde)

Lo pediste al ir a probar las vendas: el panel no tenía dónde poner cuánto cura de una parte. Ahora el consumible tiene un quinto número, **Cura una parte del cuerpo** (es **Part Repair**), de 0 a 100 %, con su burbujita de ayuda.

- **La línea de debajo lo dice.** Con salud y 30: "Al usar una unidad: cura 25 de salud (…). Con Tab, soltado sobre una parte dañada del cuerpo, le devuelve 30 % (sin pasar del 100 %) y gasta una unidad, sin tocar la salud." Con 100 dice "la deja entera".
- **Uno que solo cura partes se guarda** (antes el panel lo rechazaba: "no hace nada"). Usado normal no hace nada ni se gasta. Desde el menú, **Usar** aparece apagado y dice "se usa con Tab, soltándolo sobre una parte dañada del cuerpo"; desde la barra rápida, lo mismo. Eso último es un cambio chico del juego (`InvConsumable.check` y su descripción), solo para estos consumibles: los que ya existían dicen lo mismo que antes.
- **Más de 100 no se guarda:** "Lo que cura de una parte del cuerpo va de 0 a 100 %".
- **Las vendas siguen en 0,** como pediste para esta etapa. Si querés que curen partes, ponelo vos desde el panel (abajo, en tu prueba).

### Cómo se ve, paso a paso

1. **Tab**, clic en el botiquín: queda en la mano.
2. Pasalo sobre la silueta: la parte bajo el cursor se marca.
3. Clic sobre una parte dañada: la mano queda vacía, la parte queda en 100 %, verde, y hay un botiquín menos. Desde la noche (sección 16), al instante; antes, el botiquín se veía "esperando…" un viaje de ida y vuelta.
4. Sobre una parte sana, entre dos partes o sobre el título: sigue en la mano y dice por qué.

### Lo que valida el host

Que el botiquín siga en tu inventario con la versión que viste ("Ese objeto cambió: probá de nuevo"); que cure partes ("Eso no cura partes del cuerpo"); que la parte exista ("Esa parte del cuerpo no existe"); y que tu personaje la tenga dañada ("Esa parte ya está entera"). El personaje es siempre el de quien pide: sale de la conexión, y el pedido solo dice cuál de las seis partes. Si algo no da, no cambia nada. Un pedido que llega dos veces se contesta con el resultado guardado: cura y gasta una vez.

### Dónde está

| Archivo | Qué cambió |
| --- | --- |
| `scripts/inventory/inv_consumable.gd` | `part_repair`, `repairs_parts`, `check_part`, `apply_part`; lo dice al inspeccionar; está en la huella |
| `scripts/inventory/inv_protocol.gd` | El pedido `HEAL_PART` [id, versión, parte]; desde la noche ya no existe (sección 16) |
| `scripts/inventory/inv_authority.gd` | `_heal_part`: valida, cura y gasta juntos, y sube la época |
| `scripts/inventory/inv_ui.gd` | Soltar sobre el panel (`_part_target`, `_heal_part`), el texto junto al cursor, el aviso de la parte curada, `held_def` y `pointer`, y `body_panel` (el HUD) |
| `scenes/net_lab/hud/lab_hud.gd` | `integrity_part_at` (qué parte hay bajo un punto), `part_name`, la marca de la parte bajo el cursor |
| `scenes/net_lab/net_lab.gd` | Le pasa el HUD a la interfaz del inventario |
| `scripts/actor/actor_state.gd`, `actor_vitals.gd` | Solo los comentarios de las reglas |
| `scenes/net_lab/inventario/objetos/botiquin.tres` | **Part Repair** 100 y la descripción |
| `scenes/net_lab/inventario/objetos/vendas.tres` (nuevo), `catalogo_de_prueba.tres`, `zona_de_inventario.tscn` | Las Vendas, en el catálogo y una en la zona |
| `scenes/net_lab/integridad_test.gd` | La sección nueva |
| `scenes/net_lab/inventario/pruebas/inv_partes_test.gd` y `.tscn` (nuevos) | La prueba en red |
| `addons/inventario_objetos/formulario_item.gd` (tarde) | El quinto número del consumible, **Cura una parte del cuerpo**, con su ayuda |
| `addons/inventario_objetos/guardado.gd` (tarde) | Valida de 0 a 100 %; uno que solo cura partes se guarda; la línea de debajo lo dice |
| `addons/inventario_objetos/pruebas/prueba_del_creador.gd` y `prueba_del_creador_juego.gd` (tarde) | La venda de prueba: creada con el panel y usada jugando |

### Probado (2026-11-06, en esta PC)

| Prueba | Resultado |
| --- | --- |
| `integridad_test.tscn`, con la sección nueva | **103 de 103** (antes 72). Lo nuevo, con el gesto de la interfaz (clic en la grilla y clic en el panel): <ul><li>la parte bajo el cursor se marca, y si sirve o no;</li><li>sobre el torso sano, entre las piernas, sobre el título y con clic derecho: sigue en la mano, sin pedido, sin gastar y sin tirar nada;</li><li>sobre la pierna izquierda, con la salud completa: sale un pedido, y el mismo pedido mandado otra vez se cuenta como repetido; el botiquín espera y no se puede volver a agarrar; queda la pierna izquierda al 100 %, la derecha, la salud y lo demás igual, un botiquín menos, la época sube una vez, la luz sigue prendida, el panel dice 100 % y 60 %, y el aviso nombra la parte;</li><li>cinco pedidos directos que el host rechaza (parte entera, parte que no existe, versión vieja, las vendas, un objeto que no está), sin curar ni gastar;</li><li>las vendas sobre una pierna: siguen en la mano;</li><li>el último botiquín sobre la última pierna: todo al 100 %, la luz apagada y el botiquín ya no está;</li><li>las vendas usadas normal: 40 → 65 de salud y la pierna igual.</li></ul> |
| `inv_partes_test.tscn` (nueva), host y cliente en esta PC; el host le lastima las piernas al cliente, y el cliente camina, recoge y hace todo con el gesto | Con +200 ms, ±40 ms y 5 % de pérdida, y con +120 ms, ±20 ms y 1 %: **32 de 32** las dos veces. Sobre una parte sana o entre las piernas, nada; la pierna izquierda con el pedido mandado dos veces: un solo botiquín gastado (el host cuenta 1 repetido); la derecha sigue dañada y la luz prendida; un pedido directo sobre la pierna ya curada, rechazado sin gastar; las vendas sobre la pierna, en la mano; la última pierna: todo al 100 % y la luz apagada. Al final, dos venenos (100 → 20), las vendas (+25) y el botiquín normal (+50): **salud 95 y el cuerpo entero en el host y en el cliente**, con los mismos botiquines, vendas y venenos. El panel mostró la pierna curada a los 269 ms del clic (+200 ms) y a los 178 ms (+120 ms). Correcciones: 2, las de las dos curaciones |
| `estados_test`, `inv_model_test`, `inv_lab_test`, `inv_instant_test` (+120 ms), `inv_pair_test` (tres procesos) | 129 de 129, 91 de 91, 166 de 166, 83 de 83, y host 18, A 24 y B 7: iguales |
| `mantle_test`, `grab_above_test` | 50 casos y 22 de 22: iguales. La repetición y el barrido no se volvieron a correr: el motor y el estado no cambiaron |
| Avisos de GDScript | Cargando con el depurador los scripts y recursos tocados: ninguno |
| Capturas con ventana (internas) | El botiquín sobre una pierna dañada (borde blanco, "curar pierna izquierda"), sobre el torso sano (borde rojo, "esa parte ya está entera") y la pierna curada, con el aviso y un botiquín menos |
| El panel **Objetos**, en una copia del proyecto (tarde) | Antes del cambio, 159 de 159 en el editor y 26 de 26 jugando. Después, **165 de 165** y **32 de 32**. Lo nuevo en el editor: el consumible tiene cinco números y 18 burbujitas; 150 % no se guarda; una "Venda de prueba" que solo cura 30 % se guarda, con 0 de salud, y la línea lo dice; se colocan 3; el botiquín abierto muestra 100. Jugando, con la venda: usada normal no se usa ni se gasta ("se usa con Tab…"); sobre la pierna izquierda en 50 %, sube a 80 %, con la derecha (90 %) y la salud (50) iguales; sobre la derecha, llega a 100 % sin pasarse; otra vez sobre la derecha, rechazada sin gastar; la última, sobre la izquierda en 80 %, la deja en 100 % y se terminan. Es el pedido del host directo, no el gesto con el mouse |
| `integridad_test.tscn`, otra vez (tarde) | **103 de 103**. Las demás no se volvieron a correr: el cambio del juego solo toca a los consumibles que curan partes y nada más, y no hay ninguno en el catálogo |

**Para correrla** (Claude): host `--host --port=N --test-spawn-at=34,10 --inv-partes=host` y cliente `--client --address=127.0.0.1 --port=N --sim-rtt=200 --sim-jitter=40 --sim-loss=5 --inv-partes=client`, las dos con `--scene res://scenes/net_lab/inventario/pruebas/inv_partes_test.tscn`.

### Lo que no se probó y los límites

- **A mano, con el mouse de verdad, en las dos PC y con el `.exe`.** Es tu prueba (abajo).
- ~~El panel Objetos no muestra Part Repair.~~ Resuelto la tarde del 2026-11-06 (arriba). **El quinto número no se miró con ventana:** usa los mismos controles que los otros cuatro, pero nadie vio cómo queda en el panel de verdad. Y un valor parcial con el gesto del mouse (no el pedido directo) solo lo vas a ver vos.
- ~~**En el cliente, la parte se pinta un viaje de ida y vuelta después del clic**~~ (resuelto a la noche, sección 16) (lo que tarda el host). Si el aviso del host llega antes que el snapshot, durante un instante el panel puede seguir mostrando la parte dañada; un segundo botiquín soltado ahí lo rechaza el host ("ya está entera") sin gastarlo.
- **Con una caja abierta no se ve el panel,** así que no se puede curar desde una caja: primero el botiquín a tu inventario.

### Tu prueba

**Solo** (esta PC, **F6** → **Jugar solo**): andá a la zona de inventario y recogé los **Botiquines** (3), las **Vendas** y un **Frasco de veneno**. Para lastimarte las piernas, tirate de la tabla amarilla de la torre de parkour (sección 14): la salud queda en 4,8 y las piernas en 60 %.

1. **Una pierna, con la otra todavía dañada:** **Tab**, clic en el botiquín y clic sobre la pierna izquierda. Queda en 100 %, verde; la derecha sigue en 60 % y **la luz naranja sigue prendida**. Hay un botiquín menos y la aguja de la salud no se movió.
2. **La última parte:** otro botiquín sobre la pierna derecha. Todo en 100 % y **la luz se apaga**.
3. **Sobre una parte sana:** agarrá el último botiquín y hacé clic sobre el torso. Sigue en tu mano, dice "Esa parte ya está entera" y no se gasta. Hacé clic entre las dos piernas: tampoco. **Esc** lo devuelve a su lugar.
4. **Botiquín normal contra vendas:** la salud sigue en 4,8 desde la caída. Con **Tab**, clic derecho en el veneno → **Usar**: la aguja baja a 0,8. Clic derecho en las vendas → **Usar**: sube a 3,3 (+25). Clic derecho en el botiquín → **Usar**: sube a 8,3 (+50, el doble). El panel no cambia con ninguno de los dos.
5. **Las vendas curando un poco** (agregado la tarde del 2026-11-06), en el editor: pestaña **Objetos** → **Ítems**, en el buscador escribí `vendas` y hacé clic en **Vendas**. En **Capacidades**, poné **Cura una parte del cuerpo** en **30**; la línea de debajo dice "le devuelve 30 %". **Guardar**. **F6** → **Jugar solo**, recogé las vendas, tirate de la tabla amarilla (piernas en 60 %) y, con **Tab**, soltá las vendas sobre la pierna izquierda: queda en **90 %**, la derecha sigue en 60 % y se gastan. Si después lo querés como antes, volvé el número a 0 y **Guardar**. Para la notebook, `actualizar_lab.bat` (el número va en la huella).

**Como cliente con latencia** (esta PC **Crear partida**; la notebook, después de `actualizar_lab.bat`, **Unirse** y **Alt + 4**). En la notebook, lastimate en la tabla amarilla y repetí los puntos 1 y 2: la pierna se pinta de verde al instante (desde la noche; sección 16); se gasta uno por pierna, aunque hagas doble clic, y la luz se apaga al curar la última.

## 16. El panel del cuerpo y curar una parte, sin esperar al host (2026-11-06, a la noche)

Probando en red notaste que, con latencia alta, curar una parte esperaba al host, y que después de una caída el porcentaje de las piernas también. Sospechabas que usar los botiquines y las vendas también esperaba. Claude lo midió en esta PC, con host y cliente, antes de cambiar nada:

| Qué pasa, visto en el cliente | Antes, +200 ms | Antes, +400 ms | Ahora, +200 ms | Ahora, +400 ms |
| --- | --- | --- | --- | --- |
| Caída: la aguja de la salud baja | al tocar el piso | al tocar el piso | al tocar el piso | al tocar el piso |
| Caída: las piernas en el panel y la luz naranja | 331 ms después | 517 ms después | **al tocar el piso** | **al tocar el piso** |
| Botiquín usado normal: la aguja sube | 10 ms (el cuadro siguiente) | 12 ms | 11 ms | 18 ms |
| Botiquín soltado sobre una pierna | 227 ms después | 435 ms después | **21 ms** | **20 ms** |
| Vendas soltadas sobre una pierna (con 25) | — | 462 ms después | **21 ms** | **21 ms** |

Así que tenías razón con las dos primeras, y lo del uso normal era percepción: ya no esperaba desde el 2026-11-04. Lo que se veía tarde era el panel. Pediste sacar las dos esperas.

### Qué cambió

- **El panel y la luz muestran lo que calcula tu PC**, como la aguja de la salud. El daño de caída ya se calculaba en tu PC en el mismo cuadro; el panel mostraba lo que confirmaba el host, como decía el roadmap. Si alguna vez tu PC y el host no coinciden, el panel se corrige solo, como la aguja. En las pruebas de red de la sección 14, el host y el cliente calcularon las mismas caídas, también con 101 correcciones forzadas.
- **Curar una parte ya no es un pedido al host:** va en el input, como el uso normal, con la parte del cuerpo. Tu PC la cura en el cuadro siguiente y muestra una unidad menos; el host hace lo mismo en el mismo tick, con su estado, y gasta la unidad. El pedido `HEAL_PART` ya no existe.
- **Se puede volver a agarrar enseguida** (elección de Claude): con un uso sin confirmar, el objeto se agarra igual, para soltarlo sobre otra parte. Llevarlo a otro lugar de la grilla o soltarlo al piso, todavía no: sigue en la mano y dice "Esperá: ese objeto todavía espera al host" (es un instante, lo que tarda el host). **Esc** lo devuelve a su lugar.
- **"Parte curada: pierna izquierda"** sale al soltarlo, no cuando contesta el host.

### Lo que valida el host

Lo mismo que antes, menos la versión: que el objeto siga en tu inventario ("Ese objeto ya no está en tu inventario"), que cure partes ("Eso no cura partes del cuerpo"), que la parte exista ("Esa parte del cuerpo no existe") y que tu personaje la tenga dañada en ese tick ("Esa parte ya está entera"). La versión ya no hace falta: el uso normal tampoco la lleva, y el host hace cada uso en el orden en que lo hiciste. Si dice que no, la parte y la unidad vuelven a verse como estaban, y sale el motivo. Cada uso tiene su número y viaja en varios inputs hasta que el host lo confirma, pero se hace una sola vez. Ya no sube la época: tu PC ya lo predijo, como en el uso normal.

### Dónde está

| Archivo | Qué cambió |
| --- | --- |
| `scenes/net_lab/hud/lab_hud.gd` | `integrity()` lee el estado del personaje propio; ya no está `confirmed_state` |
| `scenes/net_lab/net_lab.gd` | Ya no guarda el estado confirmado para el HUD |
| `scripts/actor/actor_input.gd` | Cada uso lleva la parte (un byte más: `USE_BYTES` pasa de 8 a 9); una parte que no existe descarta el input |
| `scripts/inventory/inv_net.gd` | `queue_use` con la parte; la predicción cura la parte si sigue dañada |
| `scripts/inventory/inv_replica.gd` | Los usos guardan la parte y la mandan |
| `scripts/inventory/inv_authority.gd` | `use_from_input` con la parte; `_heal_part` valida y aplica con el estado de ese tick |
| `scripts/inventory/inv_protocol.gd` | Sin `HEAL_PART` |
| `scripts/inventory/inv_ui.gd` | Soltar sobre una parte pone el uso en fila; agarrar con un uso sin confirmar; llevarlo a otro lado espera |
| `scripts/inventory/inv_consumable.gd`, `scripts/actor/actor_state.gd` | Solo los comentarios |
| Pruebas: `integridad_test.gd`, `inv_partes_test.gd`, `inv_model_test.gd`, `addons/inventario_objetos/pruebas/prueba_del_creador_juego.gd` | Curan con el uso nuevo |

### Probado (2026-11-06 a la noche, en esta PC)

| Prueba | Resultado |
| --- | --- |
| La medición de arriba (no es prueba fija: está en la carpeta de trabajo de Claude), host y cliente, con +200 ms, ±40 ms y 5 % de pérdida, y con +400 ms | Lo de la tabla |
| `integridad_test.tscn` | **106 de 106.** Lo nuevo: soltar sobre la pierna sale como uso, sin pedido, y ya se ve un botiquín menos; se vuelve a agarrar enseguida y llevarlo a otro lugar de la grilla espera; el host lo hace una vez y la época no sube; el mismo uso en otro input no cura ni gasta de nuevo; cinco usos que el host rechaza (parte entera, partes 9 y −3, algo que no cura partes y un objeto que no está), sin curar ni gastar; las vendas con 0, en la mano; con 25, la pierna de 60,5 % a 85,5 %, el panel dice 85 % y la luz sigue prendida; el último botiquín, todo al 100 % y la luz apagada; las vendas normal, +25 de salud |
| `inv_partes_test.tscn`, host y cliente | Con +200 ms, ±40 ms y 5 %, y con +120 ms, ±20 ms y 1 %: **29 de 29** y el host 1 de 1, las dos veces. El panel mostró la pierna curada a los 12 ms del clic (+200) y a los 19 ms (+120); las vendas, a los 19 y 11 ms; la última parte, a los 12 y 11 ms. **Cero correcciones** y el host terminó igual que el cliente: salud 70, el cuerpo entero, ningún botiquín ni venda |
| `inv_model_test` | **92 de 92** (antes 91): la parte de cada uso va y vuelve por la red, y una parte que no existe descarta el input |
| `estados_test`, `inv_lab_test`, `inv_instant_test` (+120 ms), `inv_pair_test` (tres procesos), `mantle_test`, `grab_above_test` | 129 de 129, 166 de 166, 83 de 83, host 18, A 24 y B 7, 50 casos y 22 de 22: iguales |
| El panel **Objetos**, en una copia | 165 de 165 y 32 de 32. En la primera corrida falló una vez "la zona sigue marcada sin guardar", la marca del editor sin ventana que ya falló así el 2026-11-02; en la segunda, todo bien |
| Avisos de GDScript | Cargando con el depurador los scripts tocados: ninguno nuevo |

La repetición y el barrido no se volvieron a correr: el motor no cambió y un input sin usos mide lo mismo que antes.

### Lo que no se probó y los límites

- **A mano, en las dos PC y con el `.exe`.** Es tu prueba (abajo). Cambió lo que viaja en el input: en la notebook hace falta `actualizar_lab.bat`.
- **Las Vendas, en su archivo, curan 25 de una parte** desde que les cambiaste el número en el panel. Su descripción todavía dice "No curan partes del cuerpo". Las pruebas ya no dependen de eso: les ponen el número en memoria.

### Tu prueba

**Como cliente con latencia** (esta PC **Crear partida**; la notebook, después de `actualizar_lab.bat`, **Unirse** y **Alt + 4**). En la notebook:

1. **Caída:** tirate de la tabla amarilla de la torre. Al tocar el piso, junto con la aguja, **Tab** muestra las piernas lastimadas y la luz naranja se prende, sin esperar.
2. **Curar:** recogé los botiquines y, con **Tab**, soltá uno sobre la pierna izquierda. Se pinta de verde en el momento y hay uno menos.
3. **Otra vez, enseguida:** agarrá el botiquín de nuevo apenas lo soltaste y soltalo sobre la derecha. Se agarra y cura sin esperar, y la luz se apaga.
4. **Las vendas** (con el 25 que les pusiste): lastimate otra vez y soltalas sobre una pierna. Sube 25 puntos en el momento.


---

## 17. Abrir una caja sin que se vea la integridad (2026-11-08)

Notaste un destello del panel de integridad al abrir una caja. Pediste revisar el camino desde que apretás E hasta que se ve la grilla de la caja, que entre directo en modo caja, que el lado derecho quede reservado para la caja mientras el host contesta, que vuelva a como estaba si el host dice que no, y que Tab solo siga mostrando la integridad.

**Lo que pasaba:** E abría el inventario en el momento, pero la caja recién existe en tu PC cuando contesta el host. Mientras tanto la interfaz era la de Tab, sin caja, y a la derecha se dibujaba la integridad. Claude lo midió con el código de antes, en esta PC, con la caja compartida vacía:

| Visto en | Cuánto tardó la caja | Cuadros con la integridad, antes | Ahora |
| --- | --- | --- | --- |
| El host | 21 a 22 ms | 1 (el destello) | **0** |
| El cliente con +200 ms, ±40 ms y 5 % de pérdida | 248 a 290 ms | 33 a 39 (desde los 8 ms hasta que llegó la caja) | **0** |

### Qué cambió

- **E entra directo en modo caja.** Desde el primer cuadro, el lado derecho es de la caja: su marco, su título ("Caja compartida (compartida) · 8 × 8"), la ayuda de abajo del título y la grilla vacía, del tamaño que va a tener. Cuando llega, aparecen sus objetos en ese mismo lugar: el marco no se mueve y las celdas no cambian de tamaño. Una caja vacía se ve igual que su lugar reservado.
- **"Abriendo…"** en el medio del marco, solo si la caja tarda más de 0,15 s (elección de Claude: en el host llega en un cuadro y el texto sería otro destello).
- **Si el host dice que no** (lejos, sin verla, o la caja ya no está), todo vuelve a como estaba antes de E (así entendió Claude tu "restaurá la vista previa"): si el inventario estaba cerrado, se cierra; si lo tenías abierto con Tab, vuelve la integridad. En los dos casos sale el motivo ("Estás muy lejos de la caja"). Si el host no contesta en 10 s, igual, con "El host no contestó: … no se abrió".
- **Tab mientras espera** cerraba todo, como antes. Si volvías a abrir con Tab antes de que conteste el host, veías el inventario normal con la integridad, y la caja ya no aparece aunque el host la haya abierto (se le pide que la cierre). Antes, en ese caso, la caja aparecía igual. Desde la tarde del mismo día, Tab deja la caja y el inventario sigue abierto (al final de esta sección).
- **Con algo en la mano**, un clic en el lugar reservado no lo suelta al piso: "Esperá a que se abra la caja".
- **Tab solo no cambia:** la integridad sigue a la derecha.

En la red no cambió nada: el pedido de abrir es el mismo y el host valida lo mismo.

### Dónde está

| Archivo | Qué cambió |
| --- | --- |
| `scripts/inventory/inv_ui.gd` | `open_box` (lo que hace E mirando una caja) guarda la caja pedida (`_box_wait`) antes de abrir el inventario; `side_panel_rect` queda vacío mientras tanto; `_reserved_grid_rect` y `_draw_reserved_box` dibujan el lugar; la respuesta del host, Tab, E y el vencimiento lo terminan; `is_waiting_box` para las pruebas |
| `scenes/net_lab/hud/lab_hud.gd` | `integrity_draws`: cuántas veces se dibujó el panel, para que las pruebas cuenten los cuadros de verdad |
| `scenes/net_lab/inventario/pruebas/inv_abrir_caja_test.gd` y `.tscn` (nuevos) | La prueba de abajo |

### Probado (2026-11-08, en esta PC)

| Prueba | Resultado |
| --- | --- |
| `inv_abrir_caja_test.tscn` (nueva), dos procesos: el host con el cajón chico y el cliente con la caja compartida, las dos vacías al empezar | Con +200 ms, ±40 ms y 5 %: **host 54 de 54 y cliente 53 de 53.** Con +400 ms: lo mismo. Cero correcciones. Cada uno: Tab muestra la integridad; E con la caja vacía, con un objeto adentro y con Tab ya abierto; en cada cuadro de la espera el lado derecho siguió reservado y el HUD no dibujó la integridad ni una vez; la grilla quedó justo en el lugar reservado. Lejos de la caja, el host dice que no y vuelve a como estaba (cerrado, o abierto con la integridad). Tab, Tab durante la espera: inventario normal y la caja no aparece. Al final, Tab muestra la integridad. La caja tardó 4 a 19 ms en el host, 207 a 295 ms con +200 y 390 a 475 ms con +400 |
| La medición de antes y después (no es prueba fija: está en la carpeta de trabajo de Claude), en dos copias del proyecto, una con la interfaz de antes | La tabla de arriba. Con capturas de pantalla como cliente con +400 ms: a los 250 ms de E, antes la integridad entera; ahora el marco de la caja con "Abriendo…" |
| `integridad_test`, `inv_indicador_test`, `inv_model_test`, `inv_partes_test` (+200 ms), `inv_instant_test` (+120 ms), `inv_pair_test` (tres procesos) | 106 de 106, 164 de 164, 92 de 92, 29 de 29 (cero correcciones), 83 de 83, host 18, A 24 y B 7: bien |
| `inv_lab_test` | 176 comprobaciones, **11 fallas**, todas del machete al girarlo y moverlo con la mano, y "hay 23 objetos en la zona". **No vienen de este cambio:** con la interfaz de antes, en una copia, dan las mismas 11. Vienen del trabajo sin commit que ya estaba en la carpeta (el machete cambió en su `.tres` y la prueba sumó comprobaciones) |

### Lo que no se probó y los límites

- **A mano, en las dos PC y con el `.exe`.** Es tu prueba (abajo). Cambió el código: en la notebook hace falta `actualizar_lab.bat`.
- **El lugar reservado usa las medidas de la caja en la escena** (Columns y Rows). Son las mismas que manda el host, porque las dos PC tienen el mismo nivel.

### Tu prueba

**Como cliente con latencia** (esta PC **Crear partida**; la notebook, después de `actualizar_lab.bat`, **Unirse** y **Alt + 4**). En la notebook, en la zona de inventario:

1. **Caja vacía:** mirá el **Cajón chico** y apretá **E**. A la derecha tiene que aparecer directo el marco del cajón (4 × 3), sin la silueta del cuerpo en ningún momento. **E** lo cierra.
2. **Con algo adentro:** abrí la **Caja compartida** con **E**, pasale un objeto, cerrala con **E** y abrila otra vez. Igual: directo la caja, y el objeto aparece en su lugar.
3. **Desde Tab:** apretá **Tab** (la integridad a la derecha) y, con el inventario abierto, mirá una caja y apretá **E**. La integridad tiene que cambiar directo por la caja.
4. **Tab solo:** cerrá todo y apretá **Tab** lejos de las cajas. La integridad sigue a la derecha.

Lo mismo en esta PC, como host: tampoco tiene que verse la integridad al abrir.

**Resultado de tu prueba (2026-11-08):** en las dos PC, con latencia alta, la integridad ya no aparece al abrir una caja y no hay demoras. Commit local `8ae157b`, solo el código (sin el cambio de la barra rápida del otro trabajo sin commit, que también está en `inv_ui.gd`). Verificado en una copia limpia de ese commit: host 54 de 54 y cliente 53 de 53.

### Tab con la caja abierta cierra solo la caja (2026-11-08, a la tarde)

Pediste que, con una caja abierta, **Tab** no cierre todo: que cierre la caja, deje el inventario abierto y muestre la integridad. Así Tab deja de cerrar el contenedor junto con el inventario. Más adelante a la derecha va a haber más cosas que la integridad.

**Cómo quedó:**

- **Con una caja abierta, Tab** cierra la caja (se le avisa al host) y el inventario sigue abierto: a la derecha se ve la integridad, en el lugar de la caja. **Tab otra vez** cierra el inventario, como siempre.
- **Con una caja pedida con E, mientras el host contesta**, Tab hace lo mismo: deja la caja y el inventario sigue abierto con la integridad. Aunque el host la abra, no aparece.
- **Lo que tenías en la mano** (elección de Claude): si venía de la caja, vuelve a la caja; si es de tu grilla, sigue en la mano, por ejemplo para soltar un botiquín sobre una pierna. Lo que ibas a dejar en la caja de a una unidad (clic derecho) y todavía no salió, no se deja.
- **E y Esc no cambiaron** (no lo pediste): E con la caja abierta sigue cerrando la caja junto con el inventario, y Esc también cierra todo.

**Dónde está:** `scripts/inventory/inv_ui.gd`: `toggle` (lo que hace Tab), `has_box`, `close_box` y `_leave_box` (lo que ya hacía `close` con la caja, ahora compartido). La prueba `inv_abrir_caja_test` suma los casos nuevos y aprieta Tab por el camino de la tecla.

**Probado (2026-11-08 a la tarde, en esta PC):**

| Prueba | Resultado |
| --- | --- |
| `inv_abrir_caja_test`, host y cliente | Con +200 ms y con +400 ms (±40 ms, 5 % de pérdida): **host 73 de 73 y cliente 70 de 70**, sin correcciones. Lo nuevo: con la caja abierta y su objeto en la mano, Tab cierra la caja, el inventario sigue abierto, se dibuja la integridad, la mano queda vacía y el host la da por cerrada; Tab otra vez cierra el inventario; al volver a abrirla, el objeto sigue en la caja; con un objeto propio en la mano, Tab cierra la caja y el objeto sigue en la mano, y Esc lo devuelve; Tab mientras espera al host deja la caja, el inventario sigue abierto con la integridad y la caja no aparece aunque el host la abra |
| `integridad_test`, `inv_indicador_test`, `inv_partes_test` (+200 ms), `inv_pair_test` (tres procesos) | 106 de 106, 164 de 164, 29 de 29 (sin correcciones), host 18, A 24 y B 7 |
| `inv_lab_test` | Las mismas 11 fallas del machete de antes, que no vienen de esto (arriba) |

**Tu prueba** (en las dos PC; en la notebook, `actualizar_lab.bat` primero, porque cambió el código):

1. Abrí la **Caja compartida** con **E** y apretá **Tab**: la caja se cierra, el inventario queda abierto y a la derecha aparece la integridad. **Tab** otra vez cierra el inventario.
2. Abrila con **E**, agarrá con un clic un objeto **de la caja** y apretá **Tab**: la mano queda vacía y el objeto sigue en la caja (abrila de nuevo para verlo).
3. Abrila con **E**, agarrá un botiquín **de tu grilla** y apretá **Tab**: el botiquín sigue en la mano y lo podés soltar sobre una pierna lastimada.
4. Con una caja abierta, **E** sigue cerrando todo.

**Resultado de tu prueba (2026-11-08):** en red, funciona. Commit local `cfc8760`, solo el código (otra vez sin el cambio de la barra rápida del otro trabajo sin commit). Verificado en una copia limpia de ese commit: host 73 de 73 y cliente 70 de 70 con +200 ms, sin correcciones.

## 18. El selector de habilidades con la Q (2026-11-08)

Punto 2 del [roadmap](roadmap_integridad_habilidades_y_luz.md). Pediste empezar la implementación y que Claude te preguntara las dudas.

### Lo que decidiste vos

- **En el roadmap:** mantener **Q** abre el selector, con dos sectores (velocidad y salto, cámara lenta). Mientras está abierto, el mouse mueve el indicador y no la cámara, y el mundo sigue. El indicador sale del centro y marca el sector según la dirección del mouse, también fuera del círculo, con una zona muerta en el centro. Soltar Q confirma: prende o apaga la marcada con el control de estados de siempre; en el centro, nada. Las dos se alternan por separado, con su costo y su agotamiento, y en red como hasta ahora. La Q dejaba de ser la adopción.
- **Al empezar** (preguntas de Claude, 2026-11-08):
    - velocidad y salto **a la izquierda** y cámara lenta **a la derecha**;
    - los dibujos son **los íconos de las luces del HUD** (el rayo y el reloj de arena), dibujados por código; se pueden cambiar por imágenes cuando las haya;
    - el **1 y el 2 del teclado numérico siguen** andando;
    - la adopción pasa a **F2** (solo el host, como antes).

### Lo que eligió Claude (lo podés cambiar)

- **La zona muerta:** 40 píxeles de movimiento del mouse desde que apretás Q (**Dead Zone**). El movimiento se junta hasta 2,5 zonas muertas, 100 píxeles (**Reach**): así, para pasar al otro lado alcanza con volver un poco más que eso.
- **El tamaño:** el círculo mide de radio el 20 % del alto de la pantalla (**Size Scale** lo agranda o achica).
- Los tres valores están en el nodo **Hud → SelectorDeHabilidades**, en la escena `net_lab.tscn`. Son de cada PC, como los de la cámara: no tienen que ser iguales en las dos.
- **Con el inventario abierto**, Q no abre el selector. **Tab con el selector abierto** abre el inventario y cierra el selector sin cambiar nada. **Perder la ventana** (por ejemplo, Alt + Tab) o **cortarse la conexión** también lo cierran sin cambiar nada: sin la ventana, el soltar Q no llega.
- **Cada sector dice si su habilidad está prendida** (ícono y "Prendida" en verde) o apagada.
- **El panel de texto de la izquierda se oculta** mientras el selector está abierto, como con el inventario: se mezclaba con el círculo. Vuelve solo al cerrarlo; F1 sigue igual.
- **Lo demás sigue andando** con el selector abierto: caminar, correr, saltar, la barra rápida (1 a 9 y 0) y la rueda del mouse (solo se frena el giro de la cámara).

### Cómo se ve

En el medio de la pantalla, un círculo oscuro con dos mitades separadas por una línea. Cada mitad tiene su ícono, su nombre y su estado. La marcada se ilumina con un borde naranja. En el centro, un círculo chico: ahí no se elige nada. La aguja naranja sale del centro: mientras no pasaste la zona muerta queda corta y apagada, y al pasarla llega hasta el borde. Debajo, "Mové el mouse hacia una habilidad y soltá Q · en el centro no cambia nada".

### En la red

No viaja nada nuevo. Soltar Q sobre un sector suma una pulsación al mismo contador que el 1 (cámara lenta) o el 2 (velocidad y salto) del numérico. Ese contador ya iba en el input: tu PC lo predice al instante y el host hace la misma cuenta. La cámara lenta del mundo sigue con la demora programada de siempre (una de las mecánicas que dependen de un buen internet).

### Dónde está

| Archivo | Qué cambió |
| --- | --- |
| `scenes/net_lab/hud/ability_wheel.gd` (nuevo) | El selector (`AbilityWheel`): la Q, el mouse, el sector marcado, el dibujo y el aviso `chosen` con la habilidad elegida |
| `scenes/net_lab/net_lab.tscn` | El nodo nuevo **Hud → SelectorDeHabilidades**, el último del Hud |
| `scenes/net_lab/net_lab.gd` | `_press_power`: suma la pulsación de una habilidad; la usan el 1 y el 2 del numérico y el selector. La adopción pasó de Q a F2. El panel oculto con el selector abierto y las líneas de ayuda |
| `scenes/net_lab/hud/lab_hud.gd` | El ícono de cada estado (`draw_icon`) se puede dibujar desde otro lado: lo usan las luces y el selector |
| `project.godot` | La acción nueva `selector_habilidades`, en la Q (por la posición de la tecla, como las demás) |
| `scenes/net_lab/selector_test.gd` y `.tscn` (nuevos) | La prueba de abajo |

### Probado (2026-11-08, en esta PC)

| Prueba | Resultado |
| --- | --- |
| `selector_test.tscn` (nueva), jugando solo | **44 de 44.** Las teclas y el mouse van como los de un jugador, por la ventana. Q sin mover: no cambia nada, ni los contadores. Un poco, dentro de la zona muerta: nada. Abierto, el mouse no le llega a la cámara. Izquierda prende velocidad y salto con el contador del 2. Derecha, mucho más allá del círculo, prende la cámara lenta y arranca la del mundo. Izquierda otra vez apaga solo velocidad y salto, y un segundo después la cámara lenta sigue (la propia y la del mundo). Q sin mover deja las dos. Ir a la izquierda y volver al centro no elige nada; sin soltar, de la izquierda a la derecha marca la derecha. Con el inventario abierto, Q no abre; Tab con el selector abierto lo cierra sin elegir; perder la ventana también. La barra rápida le llega al inventario con el selector abierto. El 2 del numérico sigue prendiendo y apagando. Derecha apaga la cámara lenta y termina la del mundo. Cerrado, el mouse vuelve a la cámara |
| La misma, en red: el host y un cliente en esta PC | **Host 53 de 53 y cliente 44 de 44**, sin internet simulada (0 correcciones), con +200 ms, ±40 ms y 5 % de pérdida (dos veces: 1 corrección y 0) y con +400 ms (0). El cliente hace el recorrido entero, que incluye la prueba de cierre del roadmap; el host ve llegar las dos prendidas, después solo la cámara lenta con la del mundo andando, y al final nada. En el host, Q ya no toca la adopción y F2 sí. Cuando el cliente se va, el host hace el recorrido él |
| `estados_test`, `integridad_test`, `inv_indicador_test` | 129 de 129, 106 de 106 y 164 de 164 |
| Avisos de GDScript, cargando con el depurador los cuatro scripts | Ninguno |
| Capturas con ventana (en la carpeta de trabajo de Claude) | El selector marcando cada lado, y con la cámara lenta prendida |

### Lo que no se probó y los límites

- **A mano, con el mouse y el teclado de verdad, y en las dos PC.** Es tu prueba (abajo). Cambiaron el código, la escena y el Mapa de entrada: en la notebook hace falta `actualizar_lab.bat`.
- **Sin pantalla la cámara no gira** (el mouse no queda capturado), así que la prueba no mira el giro: mira que el movimiento no le llegue a la cámara mientras el selector está abierto, y que le llegue cerrado.
- **Cuánto hay que mover el mouse** se ajusta con **Dead Zone**: los 40 píxeles son una elección para empezar.
- **Sin commit.** Está en la rama `net-lab-auditoria-hitbox`, encima del trabajo sin commit de la auditoría de la hitbox; los archivos de los dos no se cruzan.

### Tu prueba

Jugando solo y en las dos PC (en la notebook, `actualizar_lab.bat` primero):

1. **Q sin mover el mouse:** mantené **Q** y soltala sin mover el mouse. El círculo aparece y desaparece, y arriba no se prende ni se apaga ninguna luz.
2. **Prender:** mantené **Q**, mové el mouse a la **izquierda** (esa mitad se pone naranja y la cámara no gira) y soltá: arriba se prende la luz **Súper**.
3. **La prueba de cierre, como cliente** (la notebook, **Unirse** y **Alt + 4**): prendé las dos con la Q (izquierda y derecha) y después apagá solo velocidad y salto (Q, izquierda, soltar). La luz **Cámara lenta** sigue prendida y el mundo sigue lento.
4. **F2 en el host:** en esta PC, como host, apretá **F2**: la línea "adopción:" del panel pasa a apagada; otra vez **F2** la prende.

**Resultado de tu prueba (2026-11-09):** los cuatro pasos, jugando solo y en las dos PC (la notebook con Alt + 4): funciona. Commit local `e9468d7`, solo el código, la escena, el Mapa de entrada y la prueba (sin el trabajo sin commit de la auditoría de la hitbox ni estos md). Verificado en una copia limpia de ese commit: solo 44 de 44; en red, host 53 de 53 y cliente 44 de 44 con +200 ms.

## 19. Las luces arriba a la izquierda y la luz naranja que parpadea (2026-11-09)

Pediste, con tu concepto del HUD, que las luces de las habilidades prendidas pasen al lado izquierdo de la pantalla y que no se muevan al abrir el inventario o el selector (antes iban arriba al medio y, con el inventario abierto, se corrían a la derecha).

### Lo que decidiste vos

- **Las luces, arriba a la izquierda,** en fila, siempre en el mismo lugar.
- **Con el inventario abierto, debajo de la grilla** (2026-11-10, al verlas en tu captura 1114): la grilla queda donde está y la tapa. El 2026-11-09 habías elegido que se dibujaran encima de su título (pregunta de Claude; la otra opción era bajar la grilla), y en tu prueba se veían sobre "Inventario · 12 × 16". Como el panel del inventario es un poco transparente, detrás se adivina el brillo verde.
- **La luz naranja, como el concepto** (pregunta de Claude, porque tu concepto decía otra cosa que lo de hoy): parpadea mientras alguna parte del cuerpo esté en 60 % o menos, y se apaga del todo con todas arriba del 60 %. Hasta hoy se prendía fija con cualquier parte por debajo del 100 % (la regla provisoria del punto 1).

### Lo que eligió Claude (lo podés cambiar)

- **El 60 % cuenta como se lee en el panel:** una parte en 60,5 % dice "60 %" y hace parpadear la luz; en 61 %, no. Así la luz y el número nunca se contradicen. Por eso la tabla amarilla de la torre (que deja las piernas en 60,5 %) la hace parpadear.
- **El parpadeo:** medio segundo prendida y medio apagada, en tiempo real (la cámara lenta no lo hace más lento), y arranca prendida.
- Los dos valores, en el nodo **Hud → Instrumentos**, grupo **Luz naranja**: **Injury Light Percent** (60) e **Injury Blink Seconds** (0,5). Son de cada PC: solo cambian lo que se ve.
- **Las luces se ordenan como siempre** (primero el súper, después la cámara lenta), sin huecos: con solo la cámara lenta, esa va primera.
- **El panel de texto** (el de F1) empieza debajo de las luces mientras alguna está prendida. Con eso, en esta pantalla, sus últimas tres líneas de ayuda quedan detrás de los instrumentos; F1 lo oculta como siempre.

### Dónde está

| Archivo | Qué cambió |
| --- | --- |
| `scenes/net_lab/hud/lab_hud.gd` | Las luces, en un lugar fijo (`_lights_layout`, `lights_rect`), dibujadas con los instrumentos: el nodo Instrumentos va antes que el inventario en el Hud, así que la grilla las tapa (el 2026-11-09 iban en una capa propia encima del inventario, sacada el 2026-11-10). La luz naranja: `injury_warning` (avisa) e `injury_lamp_lit` (prendida en este momento), con los dos valores nuevos |
| `scenes/net_lab/net_lab.gd` | El panel de texto baja debajo de las luces; dice "luz naranja parpadeando" o "apagada" |
| `scenes/net_lab/integridad_test.gd`, `inventario/pruebas/inv_partes_test.gd` | La regla nueva: con una pierna en 85 % la luz ya no avisa. La de integridad suma el umbral (61 % no, 60,99 % y 60 % sí, 99,99 % no, 0,01 % sí) y el parpadeo |
| `scenes/net_lab/selector_test.gd` | Las luces arriba a la izquierda, el panel debajo, y el mismo lugar con el selector y con el inventario abiertos |

### Probado (2026-11-09, en esta PC)

| Prueba | Resultado |
| --- | --- |
| `integridad_test` | **113 de 113** (antes 106; las nuevas: el umbral en cinco valores y que parpadee prendida, apagada, prendida) |
| `selector_test`, solo y en red con +200 ms | Solo **50 de 50**; en red, **host 59 de 59 y cliente 50 de 50**, sin correcciones |
| `inv_partes_test`, en red con +200 ms | 1 y **29 de 29**, sin correcciones |
| `estados_test` | 129 de 129 |
| Capturas con ventana (carpeta de trabajo de Claude) | Las luces arriba a la izquierda sin inventario, con el inventario (encima del título) y con el selector; la luz naranja prendida y apagada |

### Tu prueba

Jugando solo alcanza: no cambió nada de lo que viaja por la red. Para jugar en las dos PC, la notebook necesita `actualizar_lab.bat`, porque cambió el código.

1. **Las luces:** prendé el súper con la Q (izquierda). La luz aparece arriba a la izquierda. Abrí el inventario con **Tab**: la grilla la tapa y el título "Tu inventario · 12 × 16" se lee entero. Cerralo y abrí el selector con **Q**: la luz no se mueve.
2. **La luz naranja:** tirate de la **tabla amarilla** de la torre de parkour (7 m). Las piernas quedan en 60 % y la luz naranja de la salud parpadea. Con **Tab**, curá las dos piernas (un botiquín o las vendas sobre cada una): cuando ninguna diga 60 % o menos, se apaga del todo.
**Resultado de tu prueba (2026-11-10 y 11):** en red funcionó todo; en tu captura 1114 las luces tapaban el título de la grilla y pediste que queden debajo. Con ese cambio, lo confirmaste. Commit local `b6b1bfc`, solo el código y las pruebas (sin el trabajo sin commit de la auditoría de la hitbox ni estos md). Verificado en una copia limpia de ese commit: selector 50 de 50, integridad 113 de 113 y partes en red con +200 ms 29 de 29, sin correcciones.
