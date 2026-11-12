# El problema de los alcances del inventario

Anotado el 2026-11-11, a pedido tuyo, y **resuelto el mismo día** con las decisiones que tomaste (abajo). **Commit local `32fc044`** (2026-11-12), junto con el rayo de la mano que lo reemplazó. Lo probaste en las dos PC el mismo día: funciona, salvo un caso que quedó aparte en [`problema_objeto_sobre_un_borde.md`](problema_objeto_sobre_un_borde.md).

> **Desde la noche del mismo 2026-11-11, el alcance es otro: el rayo de la mano.** Lo decidiste para resolver ese caso. Un rayo desde los ojos, hacia donde apunta la mira, tiene que tocar el modelo del objeto (o la caja) antes que otra cosa, a no más de **Interaction Range**, medido de los ojos al punto tocado. Con la caja abierta, la distancia de los ojos a su volumen. Ya no hay torso, ni vista con pocos puntos, ni **Pickup Aim Margin**, y la hitbox de agarre no interviene. Todo, con las diferencias, en [`problema_objeto_sobre_un_borde.md`](problema_objeto_sobre_un_borde.md).
>
> **Lo que sigue de acá:** un solo alcance para objetos y cajas, **Interaction Range** en el **Tuning** (2 m de fábrica; 2,7 en tu escena), un solo código para tu PC y el host (`InvReach`), el host que mide con sus datos, la caja abierta que se usa sin mirarla y se cierra al alejarte, y la huella con lo que decide el alcance. Lo de abajo es cómo funcionó ese día, hasta la noche.

## Cómo funcionó ese día, hasta la noche

**Una sola regla para recoger un objeto y para abrir una caja:** la distancia se mide **en 3D**, desde **un punto del torso** del personaje hasta **la parte más cercana** del objeto o de la caja, y tiene que ser como mucho **Interaction Range**.

- **Dónde se ajusta:** nodo **Tuning** de `net_lab.tscn`, grupo **Recoger y abrir**, **Interaction Range**. **2 m de fábrica.** Vale igual para los objetos sueltos y para las cajas. Lo leen en el momento tu PC (para marcar y elegir) y el host (para aceptar), y entra en la huella: las dos PC lo tienen que tener igual.
- **Ojo, en tu escena quedó en 2,7 m.** Ese día habías puesto **Pickup Range** en 2,7 para probar distancias; ese ajuste se pasó tal cual a **Interaction Range**. Para volver a los 2 m de fábrica: seleccioná el nodo **Tuning**, y en el Inspector tocá la flechita circular al lado de **Interaction Range**. Ahora se mide distinto (hasta la parte más cercana, no hasta el punto de apoyo), así que 2,7 m alcanza más que antes.
- **La mira sigue eligiendo qué mirás,** como siempre: el rayo del centro de la pantalla, el cono de la tercera persona, el margen **Pickup Aim Margin**, la hitbox de agarre, quién gana entre dos cosas cerca y el indicador, sin cambios. La distancia se mide aparte: no importa en qué parte toca la mira lo que mirás.

### Desde dónde: el torso

Es el **centro de la cápsula del personaje en su postura**: la mitad de su alto, sobre los pies.

| Postura | Alto de la cápsula | Torso, sobre los pies |
| --- | --- | --- |
| Parado | 1,8 m | 0,9 m (igual que el "pecho" de antes) |
| Agachado | 1,0 m | 0,5 m |
| Encogido (subiendo desde un colgado) | 1,6 m, con el **Hang Climb Tuck** de hoy (20 cm) | 0,8 m |

Sale de los pies y de la postura que guarda el estado del personaje, y del alto de su forma (`actor.tscn`): datos que el host y los clientes tienen iguales. No depende de la cámara ni de las animaciones. No agrega ningún valor nuevo para ajustar.

### Hasta dónde: la parte más cercana

- **Una caja:** su caja de colisión, la misma que choca, con su lugar, su giro y su escala. Girarla no la agranda: no se usa una caja alineada al mundo que la encierre.
- **Un objeto suelto:** la caja que encierra su modelo **tal como se ve en el piso**: escalado a su **World Size**, apoyado y centrado como lo pone el juego (o la caja de color, si no tiene modelo). Se arma una vez por tipo, con los datos del tipo, sin necesitar el objeto dibujado: el host la calcula con su propia copia del modelo.
- **La hitbox de agarre no cuenta.** Sirve solo para apuntar: una llave con una hitbox enorme se apunta fácil, pero se agarra a la misma distancia que sin hitbox, y no a través de una pared.

### La vista: una parte que se vea y esté al alcance

Además, desde los ojos se tiene que ver **una parte del objeto o de la caja que esté al alcance**, sin nada del nivel en el medio (los personajes no tapan, como antes).

- Antes se miraba un solo punto: el centro de la caja, o 20 cm arriba del punto de apoyo de un objeto. **Ahora** se prueban unos pocos puntos: primero el más cercano al torso y después otros del objeto que estén al alcance, repartidos entre lo cercano y lo lejano, **como mucho 8 rayos** por cosa. Una caja grande con el centro tapado y un costado a la vista se abre.
- **Lo que se ve pero está fuera de alcance no cuenta:** si lo cercano está detrás de una pared y lo que se ve está lejos, no se alcanza.
- **El aire de la caja envolvente de un objeto no cuenta por sí solo:** los puntos de un objeto son puntos de su modelo (el vértice más cercano a cada punto de una grilla sobre su caja). El punto más cercano de su caja envolvente puede caer en el aire (al lado del caño de un arma, por ejemplo): cuenta solo si entre él y el modelo tampoco hay pared.
- **Una hitbox que cruza una pared no habilita nada:** la vista se mide con el modelo.
- **En una caja,** solo los puntos de las caras que dan a los ojos: las de atrás no se pueden ver.

### Con la caja abierta

No hace falta seguir mirándola: mientras estés al alcance (la misma distancia), la podés usar, meter y sacar cosas. **Más lejos, el host la cierra** ("te alejaste de la caja"). Bajar **Interaction Range** con una caja abierta también la cierra si quedás afuera. La vista no se vuelve a pedir con la caja abierta, como antes.

### Quién lo mide

Un solo código, `scripts/inventory/inv_reach.gd` (`InvReach`), que usan igual:

- **tu PC**, para el indicador y para lo que elige E (`InvNet.interaction_target`);
- **el host**, al recoger, al abrir, en cada movimiento con la caja abierta y en cada cuadro para cerrarla si te alejás (`InvAuthority`), con **su** estado de tu personaje, **su** caja en la escena y **su** copia del tipo del objeto. No se le cree ninguna distancia ni ningún punto que mande tu PC.

### El largo de la mira

La mira se estira sola: desde donde arranca (en tercera persona, a la altura de la cabeza, corrida del cuerpo) hasta el torso, más el alcance, más lo más grande que se puede elegir (la diagonal de la caja más grande, con su giro y su escala, o del objeto más grande del catálogo, con su hitbox). Así llega a la punta lejana de una caja larga que tenés al alcance por la otra punta, en primera y en tercera persona. Lo que queda más allá no puede estar al alcance. Hasta hoy eran 6 m, o el alcance más 2 m.

### Ejemplos, con los 2 m de fábrica y parado

| Qué | Hasta dónde se abre o se agarra |
| --- | --- |
| Caja compartida (1,2 × 0,8 m, 0,9 m de alto) | Con el torso a 2 m de su cara más cercana: los pies a 2 m de la caja **por cualquier lado**, también desde una esquina (antes: 1,8 m desde el lado largo, 1,6 m desde la punta y 1,48 m desde una esquina) |
| Cajón chico (0,8 × 0,6 m, 0,6 m de alto) | A unos 1,98 m de la caja, por cualquier lado (antes: 1,9, 1,8 y 1,7 m) |
| Una caja de 3 m de largo | A unos 2 m, también de punta (antes, 0,7 m de punta) |
| Una granada en el piso (16 cm de alto) | Parado, a unos 1,86 m de su borde; agachado, a 1,97 m (antes, desde el pecho hasta su punto de apoyo: unos 1,73 m del borde, parado o agachado) |
| Una tabla de 2 m en el piso | A unos 1,8 m de su punta más cercana (antes, la distancia se medía hasta su centro) |

Con los 2,7 m que tiene hoy tu escena: la caja compartida, a 2,7 m por cualquier lado; la granada, a unos 2,6 m de su borde.

## Lo que decidiste (2026-11-11)

- Un solo alcance para objetos y cajas, en el **Tuning**, de 2 m, ajustable.
- Desde un punto del torso, el mismo para recoger y abrir, que baja al agacharse, calculado con datos del personaje que tienen el cliente y el host, sin cámara ni animaciones.
- En 3D, con la altura.
- Hasta el volumen más cercano: las cajas, con su lugar, su giro y su escala; los objetos, con la caja de su modelo como se ve en el mundo, preparada por tipo.
- El rayo sigue eligiendo qué se mira; la distancia, aparte.
- La hitbox de agarre, separada del volumen para el alcance.
- Sacar el alcance de cada caja, del Inspector y del panel **Objetos**, y los avisos de "los lados largos".
- Reemplazar **Pickup Range**, conservando tu ajuste.
- La regla en un solo lugar, compartido por el cliente y el host; el host, con sus datos.
- Con la caja abierta, no hace falta seguir mirándola.
- La longitud del rayo, de acuerdo con el alcance y la separación de la cámara.
- Los datos nuevos, en la huella.
- La vista: con datos del host, sin dejar pasar lo que se ve lejos con lo cercano tapado, ni el aire de una caja envolvente, ni una hitbox que cruza una pared; con pocos puntos.
- Sin excepciones ni multiplicadores por objeto.

## Lo que eligió Claude

- **El torso es el centro de la cápsula** (la mitad de su alto): no agrega ningún valor nuevo y sale de lo que ya viaja por red.
- **El grupo del Tuning** pasó a llamarse **Recoger y abrir**, con **Interaction Range** y **Pickup Aim Margin**.
- **Los puntos de la vista:** el más cercano, y una grilla de 3 a 5 puntos por lado (cada 50 cm en las cajas; en los objetos, el vértice del modelo más cercano a cada punto de una grilla cada 25 cm), corridos 2 cm hacia adentro; hasta 8 rayos, el más cercano primero y después repartidos entre lo cercano y lo lejano dentro del alcance.
- **En los modelos muy pesados,** para elegir esos puntos se recorren como mucho 4096 vértices (uno de cada tantos).
- **La vista con la caja abierta** no se vuelve a pedir, como antes: solo la distancia.
- **El largo de la mira** (arriba).
- **La huella:** cada tipo de objeto suma la caja de su modelo y sus puntos (redondeados a la décima de milímetro); cada caja, su volumen con su lugar, su giro y su escala. Un modelo distinto en las dos PC ya no es "solo dibujo": la notebook no entra ("difiere en el inventario").
- **La vista previa de una caja** en el panel **Objetos** ya no tiene el círculo amarillo: muestra la caja con el personaje al lado, para ver el tamaño. La burbujita de **Medidas de la caja** explica que se abre con **Interaction Range**, hasta su parte más cercana.
- **En `inv_hitbox_test`, la pared que cruza el marco** entre su barra cercana y el resto: hasta hoy no dejaba elegirlo (la vista iba al centro, tapado); ahora sí, porque la barra cercana es parte del modelo, está de este lado, se ve y está al alcance. Es lo que pide la regla nueva. El caso de una hitbox que cruza una pared con el modelo entero detrás está en la prueba nueva.

## Aproximaciones y límites

- **Un objeto suelto se mide hasta su caja envolvente,** no hasta sus triángulos: uno con mucho hueco (una L, un arco, un marco) se alcanza desde un poco más lejos que su modelo, como mucho lo que mide el hueco. Los objetos sueltos nunca giran, así que esa caja es justa en sus lados.
- **La vista se prueba con pocos puntos:** una parte a la vista y al alcance, pero chica y entre dos puntos que no se ven, puede no encontrarse (se rechaza aunque un rayo exacto la vería). En los casos de las pruebas en que había una parte a la vista y al alcance (una columna delante del centro de la caja larga; un murito delante de su punta, con 3 m de alcance), se encontró. **En tu prueba en las dos PC apareció un caso:** un objeto sobre un borde, metido y visto desde abajo, que asoma poco y no se deja agarrar. Está medido, con un arreglo posible sin decidir, en [`problema_objeto_sobre_un_borde.md`](problema_objeto_sobre_un_borde.md).
- **El aire de la caja envolvente** cuenta si entre él y el modelo no hay pared. Un objeto muy irregular, con el modelo tapado por algo finito que no se mete en su caja envolvente (una columna delgada entre tus ojos y el objeto) y con el aire de su caja a la vista, podría contarse visto.
- **Las caras giradas y escaladas** se miden exacto mientras los ejes de la caja sean perpendiculares: girar y escalar el nodo de la caja lo son. Una escala desigual en un **padre** girado deforma la caja en diagonal, y ahí es una aproximación (Godot tampoco la soporta bien en la física).
- **Con la demora de la red,** tu PC mide con tu personaje como lo ve ella (un poco adelante del host). Quieto, los dos dicen lo mismo, también en el borde. Moviéndote justo en el borde, el host puede contestar distinto. La caja abierta se cierra cuando **el host** te ve afuera: con internet mala y caminando, en tu pantalla eso pasa uno o dos metros después de salir del alcance (medido con +200 ms y 2 m de alcance: en tu pantalla se cerró entre 3,3 y 3,7 m de la caja, y a 4,8 m en una corrida con una corrección grande de la red).

## Dónde está en el código

| Archivo | Qué hace con el alcance |
| --- | --- |
| `scripts/inventory/inv_reach.gd` (nuevo) | La regla entera: el torso (`torso`), la parte más cercana (`closest_point`), la distancia a una caja (`box_distance`) y a un objeto (`item_distance`), la caja y los puntos de cada tipo (`item_box`, `item_points`), la vista (`box_seen`, `item_seen`, `sees_reachable_part`) y lo que va en la huella (`fingerprint_of`) |
| `scripts/actor/actor_tuning.gd` | **Interaction Range** (`interaction_range`), grupo **Recoger y abrir**; reemplaza a `pickup_range` |
| `scripts/inventory/inv_net.gd` | `interaction_target` (lo que marca el indicador y elige E) mide con `InvReach`; `aim_length` (el largo de la mira); la huella de las cajas |
| `scripts/inventory/inv_authority.gd` | El host: `_pickup` (recoger), `_open` (abrir), `_grid_for` (operar con la caja abierta) y `watch_access` (cerrarla al alejarse), con `_box_in_reach` |
| `scripts/inventory/inv_container.gd` | Sin `access_range` ni `access_point`; `reach_box` es su volumen, el de su colisión |
| `scripts/inventory/inv_item_def.gd` | Su huella suma la caja del modelo y los puntos de la vista |
| `scenes/net_lab/net_lab.tscn` | El valor guardado: `pickup_range = 2.7` pasó a `interaction_range = 2.7` (nodo **Tuning**) |
| `addons/inventario_objetos/` | `formulario_contenedor.gd` sin el campo **Alcance**; `guardado.gd` sin `access_range` ni sus validaciones y avisos; `vista_previa.gd` sin el círculo; `objetos_panel.gd` y `formulario_item.gd`, las burbujitas |

## Pruebas

### Automáticas (en esta PC, con Godot 4.7.2)

- **`inv_alcance_test.tscn` (nueva):** jugando solo, **141 de 141**. En memoria, sin tocar archivos, suma dos cajas a la zona (una de 3 m y otra girada 37° y escalada 1,5 × 1 × 0,7) y objetos de prueba en un lugar despejado. Comprueba, con distancias de una cuenta aparte:
    - el torso: 0,9 m parado, 0,5 m agachado;
    - un objeto chico, uno largo (de punta y de costado) y la caja larga (de costado, de punta y desde una esquina): 1 cm afuera, ni el selector ni el host; 1 cm adentro, los dos;
    - la caja girada y escalada, igual, y junto a la esquina vacía de la caja alineada al mundo que la encierra, no;
    - parado y agachado (en el piso, agachado llega; en un estante de 1,4 m, agachado no) y desde una plataforma de 1 m, un objeto abajo;
    - una llave con una hitbox 60 cm más grande que su modelo: la mira la toca, pero el alcance es hasta el modelo; con una pared delante del modelo y la hitbox asomando, no se elige ni la deja el host;
    - una L hueca con su caja envolvente asomando de este lado de una pared en diagonal: no;
    - la caja con el centro tapado por una columna y un costado a la vista: se abre (con la regla de antes, no); con lo cercano tapado y lo visible fuera del alcance: no; con 3 m de alcance, sí;
    - la caja abierta, de espaldas: se usa 1 cm adentro y se cierra 1 cm afuera;
    - **Interaction Range** en vivo para el selector y el host, y la huella;
    - la mira, en primera y tercera persona, elige la caja larga por su punta lejana.
- **En pareja** (host y cliente en esta PC, el cliente con +200 ms, ±40 ms y 5 % de pérdida): el cliente camina; donde su selector dice que alcanza, E y el host acepta; donde dice que no, pide igual y el host lo rechaza; abre la caja larga, la deja de mirar, mete una granada y camina hasta que el host se la cierra. **Host 7 de 7 y cliente 17 de 17** en las cuatro corridas finales. La caja se le cerró en su pantalla entre 3,3 y 3,7 m de la caja (con 2 m de alcance), por la demora: nunca antes de salir del alcance. El rechazo por la huella: un cliente con otro **Interaction Range** no entra ("difiere en los valores del Tuning") y uno con la granada 1 cm más grande tampoco ("difiere en el inventario").
- **Lo que apareció con esa internet simulada:** en las primeras corridas, a veces el host corregía de golpe al cliente mientras caminaba (hasta 4,7 m, devolviéndolo adonde estaba antes de caminar), y la prueba fallaba porque no llegaba adonde iba. Pasó en 3 de 10 corridas con recoger y en 1 de 8 sin recoger nada, así que no es del alcance. El cuadro más largo del cliente después de E fue de 12 a 28 ms: no se congela. Desde entonces la prueba vuelve a caminar si una corrección la saca de lugar, y anota cuántas hubo. No se investigó más: es del movimiento en red, no de esta tarea.
- **Las de siempre:** los resultados están en la sección 13 de `guia_del_laboratorio.md`.

### Lo que falta comprobar a mano, en las dos PC

1. En esta PC: abrí `net_lab.tscn`, nodo **Tuning**, grupo **Recoger y abrir**: tiene que estar **Interaction Range** (2,7 en tu escena) y no **Pickup Range**. Si querés los 2 m de fábrica, tocá la flechita circular y guardá con **Ctrl+S**.
2. **F6 → Jugar solo**, en la zona de inventario. Acercate a la **Caja compartida** de costado, de punta y desde una esquina: el marco del indicador tiene que aparecer a la misma distancia de la caja por los tres lados.
3. Agachado (**Ctrl**) frente a una granada del piso: tiene que marcarse desde un poco más lejos que parado.
4. Abrí la caja con **E**, girá la cámara para el otro lado y mové algo de tu inventario a la caja: tiene que andar sin mirarla. Caminá alejándote: se tiene que cerrar sola al pasar el alcance.
5. En la notebook, `actualizar_lab.bat` (cambiaron el código, el Tuning y la huella). Después, **Crear partida** acá y **Unirse** allá. Repetí 2 a 4 desde la notebook, con **Alt + 4** (internet mala).
6. Si en el panel **Objetos** abrís un contenedor: ya no tiene **Alcance**, y la vista previa muestra la caja con el personaje al lado, sin círculo amarillo.

---

## El problema, como se anotó antes de resolverlo

*Lo que sigue es el texto del 2026-11-11, antes del arreglo. Las líneas de código que nombraba ya cambiaron.*

### Cómo funcionaba

Para recoger un objeto o abrir una caja, el juego hacía dos cosas:

1. **Un rayo elige qué estás mirando.** Sale del centro de la pantalla. Funcionaba bien.
2. **Después mide si estás lo bastante cerca.** Ahí estaba el problema.

|  | Objeto suelto | Caja |
|---|---|---|
| **Qué elige qué mirás** | El rayo | El rayo |
| **Desde dónde se mide** | Desde el pecho del personaje: 0,9 m sobre los pies | Desde los pies |
| **Hasta dónde** | Hasta el punto donde está apoyado el objeto, en el piso | Hasta el centro de la base de la caja, en el piso |
| **Cuánto** | **Pickup Range**, en el Tuning, grupo **Recoger**: 2 m | **Access Range** de cada caja: 2,2 m en las dos cajas del laboratorio |
| **Quién lo mide** | Tu PC, para elegir y marcar. El host, al recoger | Tu PC, para elegir. El host, al abrir, en cada movimiento dentro de la caja y todo el tiempo mientras está abierta, para cerrarla si te alejás |

- **El rayo** medía 6 m, salía a la altura de la cabeza y se estiraba solo si el alcance del Tuning pasaba de 4 m.
- **Con 2 m desde el pecho,** un objeto en el piso se agarraba parado a unos 1,8 m, medidos sobre el piso.

### Lo que estaba mal

1. **Dos reglas para lo mismo:** las cajas se medían desde los pies y los objetos desde el pecho, sin una buena razón.
2. **Las cajas se medían hasta su centro:** con el mismo alcance, la misma caja se abría desde más lejos por un lado que por otro. Con 2,2 m, medido desde el centro del personaje hasta el borde de la caja: la caja compartida (1,2 × 0,8 m), 1,8 m desde el lado largo, 1,6 m desde la punta y 1,48 m desde una esquina; el cajón chico (0,8 × 0,6 m), 1,9, 1,8 y 1,7 m; una caja de 3 m de largo, 1,8, 0,7 y 0,65 m. El panel **Objetos** tropezaba con esto: en vez de medir distinto, avisaba "Con ese alcance se abre solo desde los lados largos", y con uno más corto no dejaba guardar la caja: "Con ese alcance no se abre desde ningún lado".
3. **Un alcance por caja que nadie usaba:** las dos cajas tenían 2,2 m, el valor de fábrica, en el Inspector (**Access Range**) y en el panel Objetos (**Alcance**). Servía para abrir y para cerrar al alejarse.
4. **Los objetos se medían hasta el punto donde estaban apoyados:** no molestaba con objetos chicos, pero con uno largo pasaba lo mismo que con las cajas. Con una hitbox de agarre también se medía hasta el punto de apoyo, a propósito, para que una hitbox que atraviesa una pared no dejara agarrar el objeto a través de ella.

Todo eso lo eligió Claude al armar el inventario (2026-10-31), sin preguntarte. Tu pedido original (`prompt_claude_inventario_grilla.md`) solo decía, sobre las cajas: "La distancia máxima de acceso es configurable".

### Por qué no servía medir hasta donde pega el rayo

- **El host no tiene tu cámara:** tendría que creerle al punto que manda tu PC, y tu pedido original decía no creerle al cliente las distancias.
- **Con la caja abierta no hay rayo:** estás en el menú y no hace falta seguir mirándola, pero igual hay que saber si te alejaste.
- **Dependería de adónde apuntes:** la misma caja se abriría apuntando a la parte de adelante y no a la de atrás.

### Lo que funcionaba y no había que tocar

El rayo que elige lo que mirás (también en tercera persona, con el cono de 75°), las paredes que tapan, el host que vuelve a comprobar distancia y vista en cada pedido, y la caja que se cierra sola al alejarte. Siguen igual.

### Lo que había cambiado ese mismo día, antes de anotarlo

**Pickup Range** pasó del nodo **Inventario** al **Tuning**, a pedido tuyo, para probar distancias, y la mira se estiraba sola (6 m, o el alcance más 2 m). Con el arreglo, **Pickup Range** se reemplazó por **Interaction Range**.
