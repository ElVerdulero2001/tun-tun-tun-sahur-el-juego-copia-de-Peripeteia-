# El problema del objeto sobre un borde, visto desde abajo

Anotado el 2026-11-11, a pedido tuyo, después de tu prueba en las dos PC del alcance común (`problema_alcances_del_inventario.md`). **Resuelto el mismo día, a la noche, con el diseño que decidiste: el rayo de la mano.** Probado en esta PC y **por vos en las dos PC el 2026-11-12: funciona,** también un objeto puesto arriba de un muro y agarrado desde abajo. **Commit local `32fc044`** (2026-11-12). Abajo, el problema tal como se anotó antes de resolverlo.

## Cómo quedó: el rayo de la mano

### La regla

**Un rayo desde los ojos del personaje tiene que tocar el objeto antes que cualquier otra cosa, y a no más de Interaction Range.**

- **Desde dónde:** los ojos del personaje, que salen de su estado y del alto de su forma, igual en tu PC y en el host: 1,65 m sobre los pies parado, 0,85 m agachado y 1,45 m encogido (15 cm por debajo de la punta de la cápsula). No de la cámara.
- **Hasta dónde:** hasta el punto que toca el rayo. La distancia se mide de los ojos a ese punto, con **Interaction Range** (nodo **Tuning**, grupo **Recoger y abrir**; 2 m de fábrica, 2,7 m en tu escena). No hay otra distancia: el torso ya no cuenta.
- **Qué toca:** el modelo del objeto, sus triángulos, tal como se ve en el mundo (con su escala y apoyado en el piso; la caja de color si no tiene modelo). De un objeto largo cuenta la parte que tocás: la punta cercana de una tabla de 2 m se agarra, y la lejana, más allá del alcance, no.
- **Lo que asoma de un borde se agarra** si el rayo lo toca: en la prueba, un cubito metido en un estante más alto que los ojos, del que asoma 1 cm, se agarra apuntando a esa franja. Apuntando 1 cm más abajo, el rayo toca el estante y no.
- **No se mira nada más:** ni el centro del objeto, ni su punto de apoyo, ni puntos repartidos. La regla de la mañana (unos pocos puntos del modelo, corridos 2 cm hacia adentro) ya no existe.

### Primera y tercera persona

Son dos pasos, iguales en las dos vistas:

1. **La mira elige hacia dónde apuntás.** Es la línea del centro de la pantalla, que arranca a la altura de la cabeza (en tercera persona, lo que queda entre la cámara y el personaje no cuenta). Lo primero que toca (un objeto, una caja o el nivel) es el punto al que apuntás. Llega hasta la distancia de donde arranca a los ojos, más el alcance: lo que está más allá tampoco lo alcanza la mano.
2. **La mano va desde los ojos hacia ese punto.** Lo primero que toca ese rayo decide. Si es otra cosa que lo que vio la cámara, gana eso: si es otro objeto o una caja, se marca ese; si es el nivel, nada. Lo que marca el indicador es lo que hace E.

En primera persona la cámara está a 1,6 m y los ojos a 1,65 m: casi la misma línea, y la mano va al punto que tiene la mira. En tercera persona, ver algo con la cámara no deja atravesar lo que tapa los ojos: en la prueba, una cámara 1 m más alta que los ojos ve una granada por encima de un murito, pero el rayo desde los ojos toca el murito, y no se marca.

El cono de la tercera persona (**Look Cone Degrees**, 75°, nodo **Inventario**) sigue igual: lo que se agarra tiene que estar adelante del cuerpo.

### Lo que tapa

- **El nivel y las cajas** (las capas 1 y 3, como siempre). Una pared de 1 cm a 1 cm de una granada la tapa.
- **Los demás objetos sueltos:** el rayo toca el primero. Si apuntás a una granada a través de un bloque, se marca el bloque.
- **Los personajes no tapan,** como antes. Las formas del propio personaje no cuentan.
- **Lo que ya recogiste y el host todavía no confirmó** ya no se ve: el rayo lo atraviesa. Lo que soltaste y el host todavía no confirmó se ve, pero no se toca, como antes.

### La hitbox de agarre

**Ya no interviene al recoger.** La que tenés guardada (el **Machete** del catálogo, por ejemplo) sigue en su `.tres`, se edita y se ve en celeste en el panel **Objetos**, y entra en la huella, pero el juego no la arma en el mundo: una hitbox agrandada no ayuda a apuntar ni deja agarrar lo que está detrás de una pared. Las ayudas del panel lo dicen.

**Pickup Aim Margin** (el margen de 2 cm alrededor de la mira) **ya no está en el Tuning,** porque el rayo tiene que tocar el modelo. Lo decidiste vos. No estaba guardado en tu escena: `net_lab.tscn` no cambió.

### Las cajas

- **Para abrirla,** la misma regla: el rayo desde los ojos tiene que tocar la caja (su colisión) antes que otra cosa, a no más de **Interaction Range**.
- **Abierta,** sigue abierta mientras la distancia de los ojos a su parte más cercana (con su lugar, su giro y su escala) sea como mucho **Interaction Range**. No hace falta mirarla ni verla. Más lejos, el host la cierra ("te alejaste de la caja").
- Las dos usan los ojos, como elegiste: como el punto que toca el rayo es parte de la caja, al abrirla ya cumple la distancia y no se cierra sola.

### Qué verifica el host

Recoger y abrir llevan, desde ahora, **la dirección de la mano** (tres números) y **el tick del último input de tu PC**. El host:

1. **Mira la dirección:** tienen que ser tres números con decimales, finitos (sin NAN ni INF) y de largo 1 (con 1 % de margen). Si no, "pedido inválido: la dirección de la mano no sirve". Un pedido con otra forma (sin dirección, con enteros, con un número de más) ni llega: lo descarta antes de mirarlo, como siempre.
2. **Espera a tener al personaje en ese tick:** el pedido puede llegar antes que los últimos inputs (por ejemplo, los pasos en que frenaste). El host lo deja en fila hasta haber movido a tu personaje hasta ese tick, como ya hacía con los usos. Como mucho 3 s; después lo hace igual. Así tira el rayo con el personaje donde estaba cuando apretaste E, sin creerle a tu PC ninguna posición.
3. **Tira su propio rayo:** desde los ojos de tu personaje, con su estado y su postura, en esa dirección, contra su nivel, sus cajas y sus objetos (los triángulos de cada tipo, con su copia del catálogo). Sin dibujar nada: funciona igual sin pantalla.
4. **Acepta solo si lo primero que toca es eso que pediste, al alcance.** Si no:
    - lo pedido está más allá del alcance: "estás muy lejos para agarrarlo" o "… de la caja";
    - hay otra cosa antes (una pared, el piso, otro objeto, una caja): "no lo ves desde ahí: hay algo en el medio" o "no ves la caja desde ahí: …";
    - el rayo no lo toca: "no lo estás mirando" o "no estás mirando la caja".
5. **Lo demás, como siempre:** si otro lo agarró antes, "ya no está"; si no entra entero, se lleva lo que entra y el resto queda; un pedido repetido no se hace dos veces.

De tu PC el host usa solo la dirección y el tick: ni dónde está tu cámara, ni distancias, ni lo que tocó tu rayo, ni si lo ves. Mandar una dirección cualquiera no sirve para nada: lo que vale es lo que toca el rayo del host.

**Para decir por qué no,** el host sigue su rayo un poco más allá del alcance (2 m más, o hasta pasar lo pedido): eso solo elige el mensaje; lo que acepta es lo mismo que con un rayo del largo justo.

### Tolerancias y números

| Qué | Cuánto | Por qué |
| --- | --- | --- |
| El largo de la dirección | 1, con 1 % de margen | Viaja como tres números con decimales: un vector de largo 1 llega igual. Uno de largo 2 o 0 es un error |
| El tick | hasta 3 s de espera | El mismo límite que ya tenían los usos y los pedidos (`ORDER_WAIT_MSEC`): nada queda trabado |
| Un objeto apoyado justo donde toca el nivel | gana el objeto | Si el rayo los toca a la misma distancia, es el borde del objeto apoyado |
| El final del rayo | ninguna | Ya no hace falta cortar el rayo antes del punto: el rayo para en lo primero que toca, sea el piso o el objeto |

Lo eligió Claude: el 1 %, que gane el objeto en un empate, los mensajes y los 2 m de más para el mensaje.

### Diferencias con lo de antes

| | La mañana del 2026-11-11 | Ahora |
| --- | --- | --- |
| Distancia | Del torso (0,9 m sobre los pies) a la caja envolvente del modelo | De los ojos (1,65 m) al punto que toca el rayo |
| Qué se mira | La mira elegía; aparte, unos pocos puntos del modelo, corridos 2 cm hacia adentro, tenían que verse | Lo que toca el rayo de la mano, nada más |
| La mira | Con una esfera de 2 cm (**Pickup Aim Margin**) o con la hitbox de agarre | Tiene que tocar el modelo |
| Un objeto delante de otro | No tapaba | Tapa: gana el primero |
| La caja, al abrir | Distancia del torso + vista con pocos puntos | El rayo desde los ojos |
| La caja abierta | Distancia del torso a su volumen | Distancia de los ojos a su volumen |
| El pedido | Solo el número | El número, la dirección de la mano y el tick |
| La huella de cada tipo | Su caja envolvente y sus puntos | Sus triángulos (cuántos y una suma de todos) |

**Lo que cambia jugando** (son cuentas, no mediciones; con 2 m de alcance):

- **Parado, un objeto en el piso se agarra desde más cerca:** la granada, a unos 1,3 m de su centro (con el torso, a unos 1,9 m de su borde). **Agachado,** a unos 1,9 m. Con los 2,7 m de tu escena, parado, a unos 2,2 m.
- **Desde arriba de una plataforma de 1 m,** con 2 m no llegás a nada del piso de abajo: los ojos quedan a 2,65 m del piso. Con 2,7 m, sí, hasta 1 m de costado.
- **Algo a la altura de la cabeza se alcanza desde un poco más lejos que antes:** los ojos están casi a su altura y el torso estaba 70 cm más abajo.

### Límites

- **Hay que apuntar al modelo:** algo muy chico, en tercera persona y lejos, son pocos píxeles. Es lo que pediste para esta versión: sin ayuda de varios rayos ni márgenes. La hitbox de agarre queda guardada para cuando se decida otra cosa.
- **Con la demora de la red,** el host espera tu tick, pero si un input se perdió y el host te tiene en otro lugar (una corrección), tira el rayo desde ahí: puede no tocar un objeto chico. Quieto, no pasa.
- **Muchos objetos sueltos:** cada rayo revisa todos los objetos del mundo (primero su caja, y solo si la cruza, sus triángulos). Con los 27 de la prueba cuesta poco (abajo); con miles en un mapa grande habría que agruparlos por zona.
- **Desde el host,** la escena se ve como la ve el host: si en tu PC hay algo que el host no tiene, cuenta lo del host.

### Costo medido

En esta PC, jugando solo, con 27 objetos sueltos en el mundo (`inv_alcance_test`, 500 veces cada uno):

| Qué | Cuánto |
| --- | --- |
| El selector (lo que pide el indicador en cada cuadro: la línea de la cámara y el rayo de la mano), mirando el piso | 118 µs |
| Mirando un estante (el nivel) | 123 µs |
| Mirando el cielo (nada) | 121 µs |
| Mirando la franja de 1 cm de un cubito | 125 µs |
| El rayo del host al recoger | 50 µs |

Armar los triángulos de un tipo, una vez: hasta 0,5 ms (la granada, 1546 triángulos); sumarlos para la huella, hasta 0,6 ms. Cada consulta de un rayo contra los triángulos de un tipo, alrededor de 1 µs. El método de la mañana no se midió: ya no está.

### Pruebas (en esta PC, Godot 4.7.2)

- **`inv_alcance_test.tscn`, reescrita para la regla nueva:** jugando solo **170 de 170**. Las distancias se comparan con una cuenta aparte, triángulo por triángulo del modelo dibujado (coinciden al milímetro: por ejemplo, "lo toca a 2,0100 m; la cuenta aparte, a 2,0100"). Cubre:
    - los ojos, parado y agachado;
    - una granada, una tabla de 2 m (de punta y de costado) y las cajas (de costado, de punta, desde una esquina, la girada y escalada), 1 cm adentro y 1 cm afuera: el selector y el host dicen lo mismo; abierta, la caja no se cierra sola;
    - agachado en el mismo lugar, una granada del piso que parado no se alcanza; desde una plataforma de 30 cm, una de abajo;
    - **tu caso:** el cubito que asoma 1 cm de un estante más alto que los ojos (sí); 1 cm más abajo (no); agachado, no asoma (no); uno metido que no asoma (no, desde ninguna dirección); una varilla de 1,5 cm que sobresale 3 cm del filo, por abajo (sí) y por la parte de arriba del estante (no);
    - una pared de 1 cm a 1 cm de la granada; un bloque delante de una granada (se marca el bloque; la granada, el host no la da); la caja delante de una granada (se marca la caja);
    - la llave con una hitbox 60 cm más grande, asomando de una pared con el modelo atrás (no), y sin la pared, 1 cm al costado del modelo (no) y por el modelo (sí);
    - un marco de 60 cm: por el hueco, el rayo toca el piso (no); por una barra (sí);
    - tercera persona: la cámara ve por encima de un murito que tapa los ojos (no); sin el murito (sí);
    - con la cámara de verdad, en primera y tercera persona: el indicador, E y el host coinciden, también con el cubito del estante;
    - pedidos sin dirección, con NAN, INF, cero, largo 2, enteros, un número de más y el tick con decimales: el host no los acepta; con la mano para el otro lado, "no lo estás mirando"; otro objeto con la mano hacia la granada, no; pedido dos veces, "ya no está";
    - la caja abierta sin mirarla: con los ojos 1 cm adentro sigue abierta y se opera, 1 cm afuera el host la cierra; la girada, junto a la esquina vacía de la caja alineada al mundo que la encierra, se cierra;
    - **Interaction Range** en vivo, la huella (los triángulos; sin **Pickup Aim Margin**) y el costo.
- **En pareja** (host y cliente en esta PC): el cliente camina y apunta con su cámara; recoge una granada y la varilla del estante con E (el host acepta); pide el cubito metido, la tabla lejos y una dirección de largo 2 (el host rechaza cada uno); abre la caja larga con E, deja de mirarla, mete la granada y camina hasta que el host se la cierra. **Host 8 de 8 y cliente 24 de 24,** sin red simulada y con +200 ms, ±40 ms y 5 % de pérdida. El rechazo por la huella: otro **Interaction Range** y una granada 1 cm más grande, **2 y 2** cada uno.
- **`inv_hitbox_test.tscn`, adaptada:** jugando solo **90 de 90** (la hitbox se guarda, se valida y va en la huella, pero en el mundo no hay ninguna forma para apuntar; adentro de la hitbox y afuera del modelo, no se elige; por el hueco del marco, no; por una barra, sí; las hitbox de otros objetos delante no tapan). La parte de la auditoría AG-01 (la esfera del margen al salir) se sacó: sin margen no tiene sentido. En pareja con internet mala, **host 9 y cliente 7**; el rechazo por la huella, **2 y 2**.
- **Las de siempre, adaptadas a la dirección de la mano:**
    - `inv_lab_test` **190 de 190** (la mira: sin margen, a 2 mm y a 1 cm del borde no; por adentro, sí);
    - indicador **164 de 164** (gira la cámara 0,015 y 0,012 en vez de 0,04 y 0,025, porque sin margen se salía de la granada) y en pareja **8 y 8**;
    - modelo 92, estados 129, integridad 113, selector 50;
    - la de tres procesos **18, 24 y 7** (dos veces); usar sin esperar **1 y 83** (con +200 ms y con +300 ms y 8 % de pérdida); abrir caja **85 y 80** (con +200 y +400 ms);
    - partes del cuerpo **29 de 29**, tres veces.
    - La visual (con ventana) **12 de 12**; el panel **Objetos** en una copia **231 de 231** y jugando **38 de 38**;
    - la repetición del movimiento coincide byte a byte (huella `38989aaf9fd19d18`, la misma de antes), mantle 50 casos y agarre por encima del filo 22 de 22.
- **Lo que apareció en el camino:** la de partes falló una vez de dos antes de que el pedido esperara el tick: el cliente frenaba y pedía enseguida, el host lo tenía unos centímetros atrás, y el rayo hacia las vendas (bajas, desde arriba) terminaba en el piso. Con la espera, tres de tres. Y dos pruebas (`inv_lab_test` y la visual) se paraban del lado en que otro objeto tapaba la barra de prueba: ahora se paran del lado desde el que se ve, como haría un jugador.

### La prueba a mano, en las dos PC

**Hecha el 2026-11-12: "funcionó correctamente"**, también poner un objeto arriba de un muro y agarrarlo desde abajo. La notebook no tiene mouse y su trackpad no hace de rueda, así que no podía pasar a primera persona; para eso se sumaron **+** y **−** del teclado numérico, que acercan y alejan la cámara como la rueda (pedido tuyo; commit `06aba6e`; sección 2 de `guia_del_laboratorio.md`), y también las probaste: funcionan.

La lista que se siguió:

1. **En esta PC:** abrí `net_lab.tscn`, seleccioná el nodo **Tuning** y en el Inspector abrí el grupo **Recoger y abrir**. Tiene que estar solo **Interaction Range** (2,7); **Pickup Aim Margin** ya no aparece.
2. **F6 → Jugar solo.** En la **Zona de inventario**, en primera persona (rueda del mouse hasta adentro), apuntá a una granada: se marca solo con la mira sobre el modelo; uno o dos centímetros al costado, no.
3. **Tu caso:** volvé al objeto sobre el borde donde lo notaste (o a cualquier objeto sobre un borde alto) y, desde abajo, apuntá a la parte que asoma: se tiene que marcar y **E** lo tiene que recoger. Apuntando al borde, no.
4. Apuntá al costado del **Machete** (adentro de lo que era su hitbox): ya no se marca. Sobre el machete, sí.
5. Lo mismo en tercera persona (rueda del mouse hacia afuera).
6. **Abrí una caja con E** apuntándole, girá la cámara para el otro lado y mové algo: anda sin mirarla. Caminá alejándote: se cierra sola.
7. **En la notebook,** `actualizar_lab.bat` (cambiaron el código, el Tuning y la huella). **Crear partida** acá y **Unirse** allá, y repetí 2 a 6 desde la notebook, también con **Alt + 4** (internet mala). Probá apretar **E** apenas frenás al lado de un objeto.

### Lo que decidiste vos y lo que eligió Claude

- **Vos:** el rayo directo desde los ojos, el primer contacto, el alcance de los ojos al punto tocado, sin otras distancias ni vistas, sin ayuda de varios rayos; la hitbox, guardada pero sin intervenir; los dos pasos de la tercera persona; que el host tire su propio rayo con la dirección; los ojos también para la caja abierta; sacar **Pickup Aim Margin**.
- **Claude:** los triángulos de cada tipo en una `TriangleMesh` (una estructura de consulta de Godot) en vez de las formas invisibles de los objetos sueltos (abajo, por qué); que los objetos sueltos tapen a los de atrás; que gane el primero que toca el rayo desde los ojos aunque la cámara viera otra cosa; el tick en el pedido y la espera del host; los mensajes; el 1 % del largo de la dirección; la suma de los triángulos en la huella; sacar del mundo las formas para apuntar (las capas 4 y 5 quedaron libres).

**Por qué una `TriangleMesh` y no las formas invisibles que ya tenían los objetos sueltos:** esas formas eran parte de lo que dibuja cada máquina, y en el host se borraban apenas el jugador del host recogía algo, antes de que el host lo procesara. Si el host validara contra ellas, dependería de lo que muestra su pantalla. Los triángulos son los mismos (`InvVisuals.faces` del modelo como se ve en el mundo), se arman una vez por tipo, y el host los consulta con su propia lista de objetos, sin nodos ni dibujo. El nivel y las cajas se consultan con la física, como siempre.

### Lo que se sacó

- De `InvReach`: el torso, la caja envolvente de cada objeto para el alcance, los puntos de la vista (la grilla, el corrimiento de 2 cm) y la vista con pocos puntos. Queda la distancia a la caja abierta, ahora desde los ojos.
- De `InvNet`: la esfera del margen, la búsqueda de formas sobre la mira (AG-01 y AG-02 de la auditoría), el largo de la mira por el objeto más grande.
- De `InvWorldItem`: las formas invisibles para apuntar (el modelo en la capa 4 y la hitbox en la 5).
- De `InvAuthority`: la vista por un punto (`sees`).
- Del Tuning: **Pickup Aim Margin**.
- **La solución de antes de esta,** que pediste primero el mismo día (usar los puntos del modelo sin correrlos 2 cm y, si fallaba, buscar con la mira una parte visible), **quedó descartada antes de implementarse:** no hay nada de ella en el proyecto.

### Dónde está en el código

| Archivo | Qué |
| --- | --- |
| `scripts/inventory/inv_reach.gd` (`InvReach`) | La regla: `first_hit` (lo primero que toca un rayo: un objeto, una caja o el nivel), `aim_direction` (la mano hacia lo que señala la mira), los triángulos de cada tipo (`item_mesh`, `item_bounds`), la huella (`fingerprint_of`) y la caja abierta (`box_distance`, `closest_point`) |
| `scripts/inventory/inv_net.gd` | `interaction_target` (lo que marca el indicador y elige E), `aim_length`, `aim_tick` y la espera del host al tick (`_physics_process`, `use_before_step`) |
| `scripts/inventory/inv_authority.gd` | El host: `_pickup`, `_open`, `_reach_reason` (su rayo y los mensajes) y `_box_in_reach` (la caja abierta, desde los ojos) |
| `scripts/inventory/inv_protocol.gd` | Recoger y abrir con la dirección y el tick: `aimed_args`, `direction_of`, `aimed_tick_of` |
| `scripts/inventory/inv_ui.gd` | E manda la dirección que dio el selector (`pick_up_world`, `open_box`) |
| `scripts/inventory/inv_world_item.gd` | Solo dibujo: modelo, cartel y lo que marca el indicador |
| `scripts/actor/actor_tuning.gd` | **Interaction Range**, con su ayuda nueva; sin **Pickup Aim Margin** |
| `scripts/inventory/inv_pickup_hitbox.gd`, `inv_item_def.gd`, `inv_catalog.gd`, `inv_container.gd` | Comentarios y el aviso del catálogo: la hitbox no interviene |
| `addons/inventario_objetos/` | Las ayudas de **Hitbox de agarre**, de la vista previa y de las cajas |
| `scenes/net_lab/inventario/pruebas/inv_mano_de_prueba.gd` (nueva) | Para las pruebas: busca, como un jugador, una dirección desde los ojos que toque primero un objeto o una caja |

Ninguna escena ni `.tres` cambió.

---

## El problema, como se anotó antes de resolverlo

*Lo que sigue es el texto del 2026-11-11, antes del arreglo. Las funciones que nombra ya no existen.*

### Lo que notaste

Si un objeto está arriba de un borde (un estante, una plataforma) y lo querés agarrar desde abajo, cuando está muy metido adentro y asoma muy poco, no se puede agarrar. Fuera de eso, la prueba en las dos PC anduvo.

### Por qué pasa

**No es la distancia:** el objeto está al alcance. Lo que falla es la vista: la regla que decide si ves una parte del objeto.

1. Desde abajo de un borde, del objeto solo se ve la parte de arriba que asoma por encima del filo, a veces 1 o 2 cm.
2. Para decidir si lo ves, la regla no mira todo el modelo. Mira unos pocos puntos del modelo: el vértice más cercano a cada punto de una grilla sobre su caja (las esquinas, los centros de las caras, el del medio). Como mucho, tira 8 rayos desde los ojos.
3. **Esos puntos están corridos 2 cm hacia adentro del objeto.** Lo eligió Claude, para que el rayo no terminara justo sobre el piso donde está apoyado.
4. Si ninguno de esos puntos cae en la franja que asoma, la regla decide que no lo ves, aunque vos veas un pedacito.

Con 2 cm hacia adentro, los puntos de arriba de un objeto chico quedan debajo de lo que asoma. Y en los objetos finitos se juntan: en las puertas del catálogo quedan 4 puntos en vez de 8.

Es la limitación anotada en `problema_alcances_del_inventario.md` ("la vista se prueba con pocos puntos"), y el corrimiento de 2 cm la empeora.

### Lo que se midió

Con una prueba temporal, fuera del proyecto, en esta PC:

- **Los casos:** los 18 tipos del catálogo, sobre bordes de 1; 1,3; 1,5; 1,6; 1,7; 1,8; 1,9 y 2 m de alto. Metidos 5, 10, 20, 30, 50 y 80 cm (del filo al centro del objeto). Con el personaje a 0,4; 0,6; 0,8 y 1,2 m de la pared, parado y agachado. En total, 6912 casos, con el alcance de tu escena (2,7 m).
- **Lo que de verdad se ve:** muchos puntos sobre los triángulos del modelo, con un rayo desde los ojos hasta cada uno. Si alguno al alcance se ve, el objeto se ve.

En 5129 de los 6912 casos se ve una parte del objeto al alcance.

| Regla | Se ve una parte al alcance y no deja agarrar | Deja agarrar sin que se vea nada del objeto |
| --- | --- | --- |
| **La de hoy** | **271 (5 %)** | 0 |
| La de antes del 2026-11-11 (un punto en el aire, 20 cm arriba del punto de apoyo) | 583 | 296 |
| A: la de hoy, sin correr los puntos 2 cm hacia adentro; cada rayo termina 3 mm antes del punto | **128 (2,5 %)** | 0 |
| B: como A, con 5 puntos por lado de la grilla siempre | 135 | 0 |
| C: como B, también con los centros de los triángulos | 230 | 0 |
| D: como C, con 12 rayos en vez de 8 | 95 | 0 |

**Ejemplos que hoy no deja agarrar y se ven:**

- una granada sobre un borde de 1 m, metida 80 cm, agachado a 0,8 m de la pared;
- una llave sobre un borde de 1 m, metida 5 cm, agachado a 0,4 m: asoman 1,4 cm;
- una botella sobre un borde de 2 m, metida 50 cm, parado a 0,6 m.

**Lo que queda con A:** franjas finitas en las que no cae ningún punto. Por ejemplo, 1,1 cm de un machete acostado sobre un borde de 1,7 m (más alto que tus ojos), metido 80 cm, a 1,2 m de la pared.

**Más puntos no ayuda solos (B y C):** con los mismos 8 rayos, los rayos se reparten entre más puntos y aciertan menos. Más rayos (D) ayuda, pero cuesta más: el indicador hace esta cuenta en cada cuadro.

**La regla de antes fallaba más acá:** dejaba de agarrar más casos que se veían y además agarraba 296 que no se veían.

*(Esa prueba temporal no quedó guardada: sus números no se volvieron a medir. La regla nueva no tiene este problema por cómo funciona; los casos de la prueba nueva, arriba, son los que se midieron con ella.)*

### Una forma de arreglarlo (idea de Claude, sin decidir)

**La A:** usar los puntos del modelo tal como son, sin correrlos 2 cm hacia adentro, y cortar cada rayo 3 mm antes del punto. Ese corte es lo que evita que el rayo termine justo sobre el piso. Es un cambio chico, solo en `scripts/inventory/inv_reach.gd`, y solo para los objetos sueltos: las cajas siguen igual.

- **Lo que mejora:** baja los rechazos a la mitad (de 271 a 128), sin ningún caso aceptado sin verse.
- **Lo que sigue pasando:** cuando asoma una franja finita sin ningún punto, se sigue rechazando.
- **Lo que hay que hacer después del cambio:**
    - **La huella:** los puntos de cada tipo van en ella, así que cambia la huella del inventario y en la notebook hace falta `actualizar_lab.bat`.
    - **Las pruebas:** hay que volver a correr las del alcance y las del inventario.

**Lo que tendrías que decidir vos:**

- ¿Se aplica la A?
- ¿Alcanza con eso, o un pedacito que asoma 1 cm también tiene que dejar agarrar? Eso pide más rayos o mirar el modelo de otra forma, y cuesta más en cada cuadro.
- ¿O se deja como está?

### Dónde estaba en el código

| Archivo | Qué |
| --- | --- |
| `scripts/inventory/inv_reach.gd`, `_model_points` | Elegía los puntos de cada tipo y los corría hacia adentro (`_inset`, con `SIGHT_INSET`, 2 cm) |
| `scripts/inventory/inv_reach.gd`, `sees_reachable_part` | Tiraba los rayos: primero al punto más cercano y después repartidos, hasta `SIGHT_RAYS` (8) |
| `scripts/inventory/inv_reach.gd`, `lattice` e `ITEM_SPACING` | La grilla sobre la caja del objeto: de 3 a 5 puntos por lado, cada 25 cm |

### Cómo se midió

La prueba fue un script temporal, fuera del proyecto, que no quedó guardado. Hacía esto:

- un piso y bordes de cada alto, con el filo en x = 0;
- cada tipo del catálogo apoyado arriba, a cada profundidad;
- el personaje abajo, con los ojos a 1,65 m (agachado, 0,85) y el torso a 0,9 (agachado, 0,5);
- para cada caso, lo que de verdad se ve (15 puntos por triángulo del modelo, en unos 400 triángulos por tipo), `InvReach.item_seen` y cada variante.

Las variantes copiaban la cuenta de `sees_reachable_part` cambiando solo los puntos y la cantidad de rayos.
