# Objetos sueltos con física: los problemas de tu prueba del 2026-11-14

**Qué es este documento:** el análisis de lo que anotaste en `tator.txt` (carpeta `otro proyecto bobo\capturas`) después de probar los objetos sueltos con física en las dos notebooks: por qué pasa cada cosa, cómo lo comprobé y qué soluciones había. **Desde el 2026-11-15 está implementado lo que decidiste** en [`prompt_claude_revision_objetos_fisicos.md`](prompt_claude_revision_objetos_fisicos.md): lo que se hizo, cómo se comprobó y lo que falta está al final, en **«Seguimiento (2026-11-15)»**. El análisis de abajo queda como estaba, como historia: las alternativas L, T, S y H ya no están pendientes. El detalle de cómo funciona todo está en [`objetos_fisicos.md`](objetos_fisicos.md).

**Antes de esto:** a tu pedido, todo lo de los objetos con física quedó commiteado (local, sin subir) en `677086f`. Quedaron afuera del commit: el borrado de `docs/net/auditoria_parkour_2026-10-30.md` (ya estaba borrado en tu disco y no es de este trabajo) y las carpetas que nunca se suben (`archive/`, `output/pdf/`, `tmp/` y el `.TMP` de `project.godot`). Entraron también tu pedido (`prompt_claude_objetos_dinamicos.md`) y el plan del menú de debug (`guia_debug_menu.md`), porque la guía del laboratorio ya los enlaza. Los md viejos todavía dicen "sin commit y pendiente de tu prueba": no los toqué.

## Resumen

| # | Lo que viste | Por qué pasa | ¿Error de lo agregado? |
| --- | --- | --- | --- |
| 1 | En la notebook (cliente), lo que sostenés se queda atrás al girar la cámara, sin latencia simulada | La mano es "blanda" a propósito (en el host también se atrasa), y el cliente además corrige con datos de hace unos 100 ms y se pasa de largo al parar | Sí: los números de la mano y la corrección del cliente son míos |
| 2 | La tabla larga queda metida en el muro de la ranura | El cuerpo automático de la tabla tiene **huecos de 20 cm** (solo la mitad del largo tiene forma), y el muro mide 20 cm | Sí: es un error de cómo se arma el cuerpo automático. Le pasa a 7 objetos del catálogo |
| 3 | Sacás con E el objeto de abajo y el de arriba queda flotando | Jolt no despierta a lo que estaba dormido encima cuando un cuerpo se borra | Sí: falta despertar a los de alrededor al borrar uno |
| 4 | La hitbox de agarre no sirve para los objetos con huecos | El juego no la usa desde el 2026-11-11 a la noche: lo decidiste ese día y el pedido de los objetos con física lo repite | No: es una decisión vigente. Si la querés de vuelta, hay que decidir cómo |

## 1. Lo que sostenés se atrasa en el cliente

### Lo que muestra tu video

Es la notebook cliente (F1: "CLIENTE", ida y vuelta de 10 a 15 ms, sin simulación de red, 4,3 ticks adelante del host). Sostiene la **Caja de herramientas** y gira la cámara. Al girar rápido, la caja queda atrás del centro de la pantalla. Cuando la cámara para, la caja sigue corrida un rato y después vuelve al centro.

### Por qué pasa: son dos cosas

**a) La mano es blanda, en las dos máquinas.** La mano no pone el objeto donde apuntás: lo lleva con una velocidad que lo acerca de a poco (**Hold Follow Time** = 0,08 s del Tuning), con un tope de velocidad (**Hold Move Limit**, 12 m/s) y de aceleración (**Hold Accel Limit**, 80 m/s²). Así no atraviesa paredes, pero siempre llega un poco tarde. Girando a 360°/s, el objeto queda unos 27° atrás. **Pasa también en el host.** Girando muy rápido (720°/s), con 1,5 m de distancia la mano tendría que llevarlo a 19 m/s, pero el tope es 12 m/s: el objeto no alcanza y queda hasta 100° atrás. Esos tres números los elegí yo, para ajustarlos jugando.

**b) La corrección del cliente usa datos viejos.** En el cliente, lo que sostenés se dibuja "adelantado": donde lo pide tu mano ahora, corrido por la diferencia que el host tenía entre lo que le pediste y donde quedó (`InvHands._place_held`). Esa diferencia llega tarde: el cliente va unos 4 ticks adelante del host, más el viaje y los paquetes, que salen cada 2 ticks. En total son unos 5 o 6 ticks, cerca de 100 ms. Encima se suaviza de a 25 % por tick. Por eso:

- Al empezar a girar, durante unos 100 ms no se atrasa nada, y recién después aparece el atraso.
- **Al parar, sigue aplicando el atraso de cuando girabas.** El objeto se va más atrás (30°, más que mientras girabas) y tarda el doble que en el host en volver al centro.

**c) Un detalle que lo empeora un poco:** el host manda la pose de un tick con el número del tick siguiente (`InvBodies._send_poses`), y el cliente la compara con lo que pidió en ese tick siguiente. Mientras girás, eso le suma un tick de atraso a la corrección.

### Cómo lo comprobé

Con una prueba de un solo proceso (`tmp/probe_latencia.gd`). Usa el cuerpo de verdad (Jolt, `InvWorldItem`) y calcula lo que dibujaría el cliente con las mismas cuentas de `_place_held`, con los números de tu video. La cámara gira media vuelta y para. **No lo medí con dos PC.**

| Giro de la cámara | Host: atraso máximo girando | Host: tarda en volver al centro (menos de 2°) | Cliente: atraso máximo girando | Cliente: tarda en volver al centro |
| --- | --- | --- | --- | --- |
| 180°/s | 14° | 133 ms | 16° | 317 ms |
| 360°/s | 27° | 167 ms | 20° (y 30° después de parar) | 350 ms |
| 720°/s | 102° | 200 ms | 71° | 400 ms |

A 360°/s, cuadro por cuadro:

| Desde que empieza a girar | Host | Cliente |
| --- | --- | --- |
| 67 ms, girando | 22° | 0° |
| 217 ms, girando | 27° | 18° |
| 517 ms, ya quieta | 16° | 24° |
| 567 ms | 7° | 30° |
| 667 ms | 2° | 17° |
| 767 ms | 0° | 5° |

### Soluciones posibles

- **L1. Una mano más firme** (solo valores del Tuning). Medido a 360°/s (atraso girando / lo que tarda en volver al centro al parar):

  | Hold Follow Time / Move Limit / Accel Limit | Host | Cliente |
  | --- | --- | --- |
  | 0,08 s / 12 / 80 (ahora) | 27° / 167 ms | 20° / 350 ms |
  | 0,04 s / 24 / 160 | 14° / 33 ms | 13° / 250 ms |
  | 0,02 s / 40 / 400 | 8° / enseguida | 9° / 200 ms |

  Lo bueno: no hay que programar nada y mejora las dos máquinas. Lo malo: empuja más fuerte contra paredes y otros objetos (hay que probarlo en la ranura y en la pared fina). Y no arregla la parte del cliente: el cliente sigue tardando 150 a 200 ms más que el host.
- **L2. Que el cliente calcule lo mismo que el host.** El cliente haría las mismas cuentas de la mano (la misma velocidad que se acerca de a poco, con los mismos topes), sin física. Del host solo corregiría lo que la física cambió: un choque, un objeto trabado. En el aire, el cliente vería lo mismo que el host, sin los 100 ms extra y sin pasarse al parar. Contra una pared, la corrección sigue llegando unos 100 ms tarde: eso no se puede evitar con red. Lo malo: es lo que más trabajo da de las tres. Lo esperado no está medido.
- **L3. Mandar cada pose con su propio número de tick.** Es chico y aparte. Comparando con lo pedido en el mismo tick, el cliente pasó de 19,7° a 12,5° de atraso girando a 360°/s. No cambia lo que tarda en volver al parar (350 ms).

**Lo que haría yo:** L2 y L3, y después ajustar L1 jugando. Si querés algo rápido para probar ya: L1 con 0,04 s.

## 2. La tabla larga queda metida en el muro

### Lo que muestran tus capturas

La tabla pasa por la ranura del muro y una parte queda adentro de la pared, como si la atravesara (20:15:39 a 20:16:03). En una aparece "Se te soltó: se trabó". Soltada, queda ahí.

### Por qué pasa

**El cuerpo físico automático de la tabla tiene huecos.** Es un error mío, de cómo se arma el cuerpo automático (`InvItemPhysics`):

1. Para armar el cuerpo, se toman puntos sobre los triángulos del modelo (`_samples`). Pero en cada triángulo hay como mucho 8 pasos: la tabla es una caja con triángulos de 1,6 m, así que los puntos quedan **cada 20 cm** a lo largo.
2. Después se buscan los pedazos que no se tocan, con celdas de 1/12 del largo: **13 cm** (`_auto`). Dos filas de puntos separadas 20 cm caen en celdas que no son vecinas, así que el código cree que hay pedazos separados.
3. Como "encontró huecos", elige partir la tabla en esos pedazos, y cada uno es una forma convexa con sus puntos. Entre pedazo y pedazo queda un espacio sin forma.

Resultado: la tabla tiene forma en 0–20 cm, 40–60 cm, 80–100 cm, 120–140 cm y en la punta, y **20 cm vacíos entre cada una**. El muro de la ranura mide justo 20 cm de espesor: un borde de la ranura entra en un hueco y la tabla queda enganchada, con el muro "adentro". No es Godot ni Jolt: Jolt hace chocar las formas que le damos, y esas formas tienen huecos.

### Cómo lo comprobé

- **Las piezas de la tabla** (`tmp/probe_partes.gd`): 16 piezas, y el 50 % del largo sin cubrir (4 huecos de 20 cm).
- **La tabla en la ranura** (`tmp/probe_tabla2.gd`): el mismo muro de la pista, la tabla metida por la ranura y la mano empujando para abajo, para arriba y girando. Son 63 casos, y se mide cuánto de la línea del medio de la tabla queda adentro del muro:

  | Cuerpo | Lo peor, sostenida | Quedaron metidas después de soltarlas |
  | --- | --- | --- |
  | Automático (el de ahora) | 16 cm adentro del muro | 42 de 63 |
  | Una caja entera del tamaño de la tabla | 0 cm | 0 de 63 |

- **La pared fina de 2 cm** (`tmp/probe_fina.gd`), girando la tabla hacia ella: con el cuerpo automático la cruzó en 2 de 6 casos; con la caja entera, en ninguno.
- **Lo que no causa esto:** girar rápido. Girando la tabla contra el muro de la ranura, sin meterla en ella, no entró más de 3 cm, ni siquiera con el cuerpo automático y el giro al máximo, 720°/s (`tmp/probe_tabla.gd`). Contra la pared fina, la caja entera entró como mucho 5 cm un instante y salió sola.

### A qué otros objetos les pasa

A los que tienen pocos triángulos grandes (cajas). Este es el largo, en el eje más largo del modelo, que no cubre ninguna pieza:

| Objeto | Piezas | Sin cubrir |
| --- | --- | --- |
| Tabla larga | 16 | 80 de 160 cm (4 huecos de 20 cm) |
| puerta de Peron | 16 | 22 de 45 cm (huecos de 5 y 6 cm) |
| porton de musolini | 16 | 22 de 45 cm (huecos de 5 y 6 cm) |
| Botiquín | 16 | 11 de 30 cm (huecos de 4 cm) |
| Caja de herramientas | 16 | 14 de 55 cm (huecos de 7 cm) |
| Batería | 16 | 7 de 18 cm (huecos de 2 cm) |
| Vendas | 16 | 6 de 16 cm (huecos de 2 cm) |

Los demás (botella, machete, llave, granada, banquito, tornillos, linterna, bebida, cápsula, venen lento) no tienen huecos.

**Otro error del mismo código, más chico:** en los objetos redondos, la forma queda más corta que el modelo en las puntas. Al **Frasco de veneno** le faltan 2 cm arriba y 2 abajo (de 15 cm), y a la **Toxina lenta**, 1 y 1. Al armar cada forma se guarda, de cada zona, el punto más alejado del centro (`_hull_points`). En una esfera todos están igual de lejos, así que se queda con cualquiera y pierde las puntas. Efecto esperado: se apoyan hundidos 1 o 2 cm en el piso (no lo miré en el juego).

### Soluciones posibles

- **T1. Arreglar el armado automático:** que los puntos sobre los triángulos queden más juntos que las celdas con que se buscan los pedazos. Así dos partes que se tocan nunca parecen separadas. Es el arreglo de fondo, y le sirve a todos los objetos, a los de ahora y a los que hagas. Para los redondos, quedarse con los puntos de las puntas de cada eje (o con más puntos) en vez del más alejado del centro.
- **T2. Una prueba que lo vigile:** para cada objeto del catálogo, comparar cuánto del modelo cubre su cuerpo. La de ahora no lo miraba: probaba que cae, que reposa y que cabe, pero no que no tenga huecos. Si el armado automático deja huecos donde el modelo no los tiene, falla. También podría avisarlo el panel **Objetos**, en **Cuerpo físico**.
- **T3. Mientras tanto, sin tocar código:** en el panel **Objetos**, a la tabla (y a los otros 6) ponerle **Cuerpo físico** = **Caja**. Arranca ajustada al modelo. Es un parche por objeto, no el arreglo.

**Lo que haría yo:** T1 y T2 juntas. T3 solo si querés seguir probando antes del arreglo.

## 3. Lo de arriba queda flotando al sacar lo de abajo con E

### Lo que muestran tus capturas

La **Llave** arriba de la **puerta de Peron** (20:24:49). Recogés la puerta con E y la llave queda en el aire (20:24:50). En la de 20:24:33 también hay una llave parada en el aire.

### Por qué pasa

Cuando un objeto queda quieto un rato, Jolt lo **duerme**: deja de simularlo hasta que algo lo toque. Si un cuerpo que se mueve choca con uno dormido, lo despierta. Pero **si el cuerpo de abajo se borra del mundo, Jolt no despierta a los que tenía encima**. Al recoger con E, el host borra el cuerpo (`InvBodies.despawn`), y la llave sigue dormida en el aire. Los clientes la ven igual, porque ven lo que hay en el host.

### Cómo lo comprobé

Con `tmp/probe_apoyo.gd`, en Godot 4.7.2 con Jolt:

| Caso | Resultado |
| --- | --- |
| Dos cajas comunes de Godot (sin nada nuestro): se duermen y se borra la de abajo | La de arriba **queda en el aire** |
| La puerta acostada y la llave arriba: se duermen y se borra la puerta | La llave **queda en el aire** |
| Lo mismo, pero después de borrarla se despierta a mano a la llave | La llave **cae** |
| La puerta no se borra: se la saca de abajo con la mano | La llave **cae** (la puerta, al moverse, la despierta) |

O sea: pasa solo cuando lo de abajo **desaparece** (recogerlo con E u otra cosa que lo saque del mundo), no cuando lo movés.

### Soluciones posibles

- **S1. Al sacar un objeto del mundo, despertar a los que están cerca:** los objetos sueltos cuya caja toca la del que se va, agrandada unos centímetros. Se buscan en el índice que ya tenemos para el rayo. Puede despertar alguno de más, pero a los 0,5 s se vuelve a dormir. Si había una pila, el que cae despierta al de más arriba al moverse (como en el último caso de la tabla).
- **S2. Despertar exactamente a los que lo tocan:** antes de borrarlo, preguntarle a la física qué objetos tocan sus formas. Es más exacto, pero algo más de código, y para esto no hace falta tanta precisión.

**Lo que haría yo:** S1.

## 4. La hitbox de agarre no sirve para los objetos con huecos

### Por qué pasa

**No es un error: el juego no usa la hitbox de agarre desde el 2026-11-11 a la noche.** Ese día elegiste que, para recoger, un rayo desde los ojos tenga que tocar el modelo, y que la hitbox quedara guardada sin intervenir (`docs/net/problema_objeto_sobre_un_borde.md`, sección "La hitbox de agarre"). El pedido de los objetos con física lo repite: *"La antigua `pickup_hitbox` guardada para edición no vuelve a ser la regla de recogida"*. Sostener usa el mismo rayo (`InvReach.first_hit`): por un hueco del modelo, el rayo pasa y no agarra.

Lo que confunde es que el panel **Objetos** la sigue dejando editar, la dibuja en celeste en la vista previa y entra en la huella. Del catálogo, solo el **Machete** tiene una.

### Soluciones posibles (si la querés de vuelta)

- **H1. Como del 2026-11-07 al 11:** si el tipo tiene hitbox, el rayo toca la hitbox en vez del modelo. Es simple y fácil de entender. Lo malo es lo que la sacó del juego: si la hitbox es más grande que el modelo y asoma de una pared, se agarra el objeto a través de la pared. Y tapa a los objetos que quedan detrás de ella.
- **H2. Como segunda oportunidad:** primero el modelo, como ahora. Solo si el rayo no toca ningún modelo antes del nivel, se prueba con las hitbox. No le roba el agarre a un objeto que estás mirando directo, y un hueco o un objeto finito se vuelven agarrables. Lo malo: la regla tiene dos pasos, y lo de la pared es igual que en H1 (se podría pedir además que no haya pared entre los ojos y el modelo).
- **H3. Dejarla como está** y que el panel lo muestre claro: la sección apagada o con un cartel de "no se usa en el juego".

En H1 y H2 hay que decidir además **por dónde se agarra** si el rayo tocó la hitbox en un hueco: por ese punto (en el aire, y el objeto cuelga de ahí) o por el punto del modelo más cercano.

**Lo que haría yo:** H2, con el punto del modelo más cercano. Pero es tu decisión de diseño: cambia la regla que elegiste el 11.

## Lo que no revisé

- **Los dos avisos "se cayó del mapa"** de tu captura del editor (objetos 3 y 4, a las 20:17). Ese aviso es lo previsto: un objeto que baja de −30 m vuelve, quieto, a donde reposó por última vez. Volvieron a lugares en z ≈ 1, fuera del piso de la zona de inventario. Si los lanzaste fuera del nivel, es lo esperado. Si cayeron solos o atravesaron algo, avisame: con los huecos del punto 2, un objeto puede cruzar una pared fina.
- **Los otros problemas** que mencionás y que no son de lo agregado: no están en el txt y no los miré.

## Las pruebas de este análisis

Son descartables. Están en `tmp/` (no se sube a git) y sirven para volver a medir después de cada arreglo. **No tenés que hacer nada con ellas.**

| Archivo | Qué mide |
| --- | --- |
| `tmp/probe_latencia.gd` | El atraso de lo sostenido al girar, en el host y en el cliente (punto 1) |
| `tmp/probe_partes.gd` | Las piezas del cuerpo automático de cada objeto y qué largo dejan sin cubrir (punto 2) |
| `tmp/probe_tabla.gd` | La tabla girada contra el muro de la ranura y forzada adentro de ella (punto 2) |
| `tmp/probe_tabla2.gd` | La tabla en la ranura, 63 casos, cuerpo automático contra caja entera (punto 2) |
| `tmp/probe_fina.gd` | La tabla girada contra la pared fina de 2 cm (punto 2) |
| `tmp/probe_apoyo.gd` | Lo de arriba al borrar o sacar lo de abajo (punto 3) |

Se corren sin ventana: `Godot_v4.7.2.exe --headless --fixed-fps 60 --path . --script res://tmp/<archivo>`.

---

## Seguimiento (2026-11-15)

Elegiste qué hacer en [`prompt_claude_revision_objetos_fisicos.md`](prompt_claude_revision_objetos_fisicos.md), y está implementado. **Sin commit** (el pedido decía no commitear por iniciativa propia) y **falta tu prueba** con el mouse y en las dos PC: la lista, en la sección 1 de [`objetos_fisicos.md`](objetos_fisicos.md), donde también está todo el detalle.

### 1. Lo sostenido en el cliente: predicción y control del host

**Lo hecho:**

- **Las mismas cuentas en el host y en tu PC** (`InvHoldMotion`), con el input de cada tick y los ojos de ese tick.
- **Tu PC predice** lo que sostenés y manda cómo le quedó con el input.
- **El host lo compara** con su resultado del mismo tick y lo adopta si es creíble (camino libre, sin tocar otro objeto, cerca de lo suyo). Si no, sube la versión de la sujeción y tu PC se corrige con lo del host y repite hasta el presente.
- **Las poses** salen con el tick que de verdad son: antes, con el del tick siguiente (la causa c).
- **Otra cosa que encontré al medir:** la mano del host usaba el pedido del tick anterior, porque Jolt llama a `_integrate_forces` antes del tick. Ahora las velocidades se ponen al terminar el tick, antes del paso de Jolt.
- **Contra las paredes:** las dos máquinas miran el nivel antes de cada paso, también al girar sin moverse. Jolt frena los choques al moverse, no al girar: una caja girada contra la pared de 2 cm la cruzaba.
- **Soltar y lanzar** esperan al último tick en que lo sostuviste, y en tu PC lo soltado sigue adelantado (no salta para atrás).
- **Un input que llega tarde** no termina en una corrección: el host valida el camino por las afirmaciones de esos ticks, y con la misma versión tu PC no corrige (espera a que el host las adopte). Si el host no puede, sube la versión: porque rechazó una, o porque pasó medio segundo sin ninguna que le sirva.

**Los valores de la mano** (Hold Follow Time y los límites) **no los cambié**: con la red resuelta, tu PC se siente igual que el host (abajo). Endurecerlos es un ajuste para cuando lo pruebes.

**La evidencia** (host y cliente en procesos distintos en esta PC, `inv_fisica_test` con `--fisica-pair=mano_host` y `mano_cliente`, la caja de herramientas a 1 m y 52° hacia arriba):

| Girando | Antes, el host | Antes, tu PC | Ahora, el controlador | Ahora, el host | Ahora, lo que ves |
| --- | --- | --- | --- | --- | --- |
| 180 °/s | 14°, quieta en 133 ms | 16°, 317 ms | 6,9°, 83 ms | 6,9°, 100 ms | 6,9°, 83 ms |
| 360 °/s | 27°, 167 ms | 20° girando y 30° al parar, 350 ms | 13,0°, 117 ms | 13,0°, 117 ms | 13,0°, 117 ms |
| 720 °/s | 102°, 200 ms | 71°, 400 ms | 26,3°, 167 ms | 23,3°, 167 ms | 26,3°, 167 ms |

- **0 correcciones** en todo el recorrido, sin red simulada (varias corridas) y con +200 ms, ±40 ms y 5 % de pérdida (ida y vuelta medida, 150 a 200 ms) en 3 de 4 corridas: el host adoptó o coincidió en unas 750 de 760 afirmaciones.
- **En la cuarta,** con muchos inputs que llegaron tarde (89 afirmaciones que no llegaron a tiempo), tu PC esperó en vez de corregir (22 veces) y se corrigió 4 veces, por versión nueva, como mucho 6 mm. La copia del host, la que ven los demás, llegó a quedar hasta 1 m corrida un momento, mientras le faltaban esos inputs.
- **La tabla agarrada por una punta,** a 360 °/s: 9,9°, quieta en 83 ms, y la punta agarrada no cambia.
- **Contra la pared fina,** empujando y girando sin moverse: 0 correcciones; lo que ves no la cruza ni se mete, y en el host tampoco.
- **Con cámara lenta:** el host y tu PC dan lo mismo, sin aplicar la escala dos veces.
- **La primera corrida,** antes de mirar el nivel al girar y de validar el camino tras un input tardío, daba 11 y 19 correcciones a 360 y 720 °/s, y la caja cruzaba la pared. Las dos cosas se arreglaron en el diseño, no subiendo tolerancias.
- **La tabla de «antes»** es la medición del análisis de arriba (un solo proceso), con la caja a 1,5 m mirando derecho: no es exactamente el mismo caso.

### 2. La tabla metida en el muro: el cuerpo físico

**Lo hecho:**

- **Se sacó el generador de tajadas.** Ahora el cuerpo lo arma Godot: una forma convexa (`Mesh.create_convex_shape`), varias (la descomposición de `MeshInstance3D.create_multiple_convex_collisions`, que solo está en el editor) o una primitiva.
- **Se prepara en el editor** y se guarda en el `.tres` (`InvBodyShape.shapes`, con de qué modelo salió). El juego solo lo carga.
- **El panel** tiene los dos apartados, **Cuerpo físico** e **Hitbox de agarre**, separados: **Generar del modelo**, los valores de la descomposición, el aviso de «Sin preparar» y la generación sola al guardar.
- **Los 19 objetos del catálogo** quedaron preparados con `addons/inventario_objetos/preparar_cuerpos.gd`:
  - la tabla y las otras cajas, con una caja ajustada;
  - la llave y el machete, también, por ser planos (lo de abajo);
  - los demás, con una forma convexa exacta.

**La evidencia** (`inv_fisica_test`, jugando solo):

- **La tabla** es una sola caja de todo su largo, pasa por la ranura y la cruzada se frena. Medido el 2026-11-14: con el cuerpo viejo quedaba metida en 42 de 63 casos, con una caja entera en 0.
- **Ningún vértice** de ningún modelo queda a más de 3 mm afuera de su cuerpo, y ningún cuerpo sobresale más de eso (la granada da 2,1 mm: Godot redondea el casco).
- **Apoyados derechos e inclinados**, nada queda metido en el piso más de 3 mm.
- **Un marco con hueco**, armado en memoria con varias formas, conserva el hueco, y su hitbox lo tapa sin cerrarlo.

**Lo que encontré de Jolt:**

- **Las formas convexas planas:** la llave (1,4 cm de grueso) y el machete (2,3 cm), apoyados inclinados, quedaban de 20 a 70 mm metidos en el piso con cualquier forma convexa. Probé la de Godot, la simplificada, la de los puntos al milímetro y la de la descomposición; con una caja, 0. Por eso lo plano va con una caja. Lo descubrió `inv_lab_test`: la llave soltada contra la pared quedaba 4 cm adentro del piso, y el rayo ya no la tocaba.
- **El rescate:** por si le pasa a otro modelo, si Jolt duerme un objeto metido en el nivel más que su tolerancia (2 cm) y 5 mm, el host lo saca (hasta 10 cm) y lo avisa. Con los cuerpos de ahora no hizo falta en ninguna prueba.

### 3. Lo de arriba flotando: el despertar

**Lo hecho:**

- **Al sacar un objeto del mundo** (E, entero), antes de sacarlo del índice, se despiertan los objetos cuya caja toca la suya agrandada 5 cm. El cuerpo sale del mundo físico en el acto.
- **Despertar es una operación del gestor** (`InvBodies.wake`), que pone al día la lectura de la pose, los paquetes, el estado del mundo y el arreglo de lo que nace dormido. Cambiar `sleeping` a mano no alcanzaba: una prueba vieja lo hacía y el rayo veía la pose quieta.

**La evidencia:**

- **Una pila de tres baterías:** recogida la de abajo, cae entera y vuelve a reposar una sobre otra. Lo mismo si se saca en el mismo tick en que nacieron dormidas.
- **La batería del costado,** que no pierde su apoyo, no se mueve.
- **La pose y el índice** de la que cae se ponen al día durante la caída, y al final no queda nada anotado de más.
- **Recoger una parte** de una pila que sigue en el mundo no despierta a nadie.
- **En red:** el cliente ve caer la batería de arriba durante la caída, con varias alturas distintas, no solo al final.

### 4. La hitbox de agarre: la selección principal

**Lo hecho:**

- **Con una hitbox que sirve,** el rayo la toca aunque pase por un hueco del modelo; sin hitbox, el modelo.
- **El acceso:** el punto del modelo más cercano al tocado tiene que verse desde los ojos y estar a no más del alcance más 25 cm. Al principio puse «25 cm más lejos que el punto tocado», y una hitbox muy grande no se podía elegir ni apuntando al modelo; quedó con el alcance.
- **Se agarra por el punto tocado** (anclaje virtual), igual en tu PC y en el host.
- **El índice** incluye la caja de la hitbox.
- **Una forma convexa propia** ahora se toca con las caras de su casco. Encontré un error mío en cómo se orientaban esas caras en una forma muy fina: está arreglado.

**La evidencia:**

- **La llave con una hitbox 3 cm más grande:** 2 cm al costado del modelo, se elige y se agarra por ese punto, también en el host; girando, sigue agarrada ahí; 2 cm afuera de la hitbox, no; su cuerpo no cambia.
- **Detrás de la pared fina,** con la hitbox asomando 8 cm de este lado, no se elige, y el host rechaza el pedido.
- **En el borde de la mesa,** lo que asoma del borde la elige.
- **El alcance:** a 15 cm menos que el alcance, sí; a 10 cm más, no.
- **`inv_hitbox_test` e `inv_alcance_test`** dan vuelta lo que comprobaban de la regla vieja: adentro de la hitbox, se elige; afuera, no. Siguen con las protecciones de antes: la pared delante, la pared que cruza el marco y las láminas lejanas con la hitbox adelantada 2 m (AG-02), que no tapan.

### Lo que falta

- **Tu prueba con el mouse y en las dos PC**, sobre todo la caja de herramientas en la notebook, como en tu video, y con **Alt + 4**. Lo de esta PC son dos procesos en la misma máquina, con la red simulada.
- **Con el `.exe` exportado**, a distancia.
- **Los demás «otros problemas»** que mencionaste en tu mensaje y que no son de esto: siguen sin mirar.

### Tu prueba en las notebooks (la tarde del 2026-11-15)

La hiciste esa tarde (`kavi.txt`). Las dos mallas, la de agarre y la física, funcionan como deben. Encontraste cuatro errores nuevos y 7 avisos del depurador:

- objetos que no se podían mover;
- el machete debajo de una pila, metido en el piso;
- lo sostenido que se seguía moviendo detrás de un muro;
- en la notebook, lo soltado de alto que se hundía en el piso o desaparecía un momento.

Están arreglados, sin commit. La causa, el arreglo y lo medido de cada uno, y el mecanismo de «no se ve» que pediste por escrito, están en la sección 17 de [`objetos_fisicos.md`](objetos_fisicos.md). Falta tu prueba de esos arreglos (sección 1 de ese documento).

### Tu segunda prueba (2026-11-15)

Reemplazaste las notas de `kavi.txt` y sumaste un video. Ya nada atraviesa el piso ni queda trabado. Quedaban tres problemas:

- «no se ve» no era instantáneo, y con más latencia tardaba más;
- lo soltado del inventario salía hacia donde mira el cuerpo, que no siempre es hacia donde mira la cámara;
- en la notebook, al sacar el de abajo de una torre, lo de arriba se quedaba en el aire un momento.

Están arreglados, sin commit; para la torre que desarma el invitado elegiste la opción que te recomendé. La causa, el arreglo y lo medido de cada uno están en la sección 18 de [`objetos_fisicos.md`](objetos_fisicos.md), y el mecanismo de «no se ve», puesto al día, en la 17. Falta tu prueba (sección 1 de ese documento).
