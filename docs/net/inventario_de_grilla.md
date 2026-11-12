# Inventario de grilla en el laboratorio

Hecho el 2026-10-31 a partir de [`prompt_claude_inventario_grilla.md`](prompt_claude_inventario_grilla.md). Es un sistema nuevo, desde cero: no usa ni toca el inventario anterior (`scripts/player n entities/inventory_v2`, PlayerV2), que sigue en su lugar sin que nada del laboratorio lo nombre.

Lo que decidiste vos antes de empezar:

- **La simulación de internet** pasó a **Alt + 1 a 5**, para dejarle la fila de arriba a la barra rápida.
- **E** recoge y abre cajas. Los empujones del host pasaron a **Y** (inmediato) y **U** (programado); con Shift siguen siendo débiles.

Todo lo demás lo eligió Claude y está anotado en la sección 7, "Decisiones chicas y límites".

El [roadmap de integridad, habilidades y luz](roadmap_integridad_habilidades_y_luz.md#panel-de-integridad) describe cómo se incorporará el panel corporal a la interfaz que se abre con Tab.

### Segunda vuelta, con tus notas de la prueba (2026-10-31)

Lo que pediste en `capturas/ifac.txt` (el mantle quedó para otro momento):

- **Un clic agarra y otro clic deja.** Ya no hay que mantener el botón.
- **Clic derecho con el objeto en la mano:** deja una unidad en una grilla, en un lugar libre o sobre una pila igual, y el resto sigue en la mano. Tres clics, tres unidades. Para terminar, un clic en su lugar lo devuelve. **Dividir…** sigue en el menú, para cantidades grandes (lo elegiste así).
- **Se suelta al piso desde cualquier lado**, también desde una caja abierta, sin pasar por el inventario.
- **El giro tiene cuatro posiciones** (0°, 90°, 180° y 270°), y la imagen gira con el objeto.
- **El banquito se gira.**
- **Se agarra o se abre solo lo que mirás.** La regla quedó así: tu idea del cono, con un cambio que propuso Claude y aceptaste:
    - Cuenta lo que apunta la cámara, por el centro de la pantalla.
    - El personaje lo tiene que ver desde los ojos, sin una pared en el medio. Esto lo comprueba también el host.
    - En tercera persona, la mira cuenta desde la cabeza para adelante: lo que queda entre la cámara y el personaje no se elige.
    - En tercera persona, además, tiene que estar adelante del cuerpo, a no más de 75° de hacia donde mira el personaje. Así, aunque gires la cámara para mirar algo que está detrás, no se agarra. En primera persona no hace falta (lo elegiste así): la cámara es la vista.
    - Desde el 2026-11-06 (pedido tuyo), un objeto suelto se apunta por la forma de su modelo: la mira lo tiene que tocar o pasar a menos del margen del Tuning, **Pickup Aim Margin** (2 cm de fábrica). Hasta ese día era una esfera invisible alrededor de él, de la mitad de su tamaño más 12 cm de radio. Las cajas siguen con su colisión. El detalle, en la sección 16 de `guia_del_laboratorio.md`. **Desde el 2026-11-11 a la noche, sin margen:** el rayo de la mano tiene que tocar el modelo (abajo, "El rayo de la mano").
- **Los cuatro avisos de Godot** (`is_host`, `seq`, `size` y `_text`) eran nombres repetidos en `inv_net.gd` y en `inv_ui.gd`. Ya no aparecen, y apareció uno más en una prueba, también arreglado.

**Para más adelante, sin hacer (lo elegiste así): la física de los objetos sueltos.** Según tus notas:

- Chocan con el entorno, no con el personaje.
- Con el jugador solo interactúan cuando se los arroja o vienen hacia él. Pararse o caminar encima no hace nada. Así se evitan los errores raros de la física (Jolt).
- Al tirarlos, por ahora todos salen con la misma fuerza.

### Tercera vuelta, con tu segunda prueba (2026-10-31)

- **El giro es alrededor del centro de la celda que agarraste**, como en tu dibujo (`capturas/afggggg.png`): no importa en qué parte de la celda hagas clic. Al agarrarlo, el objeto se acomoda para que el cursor quede en el centro de esa celda, y ahí sigue en los cuatro giros. Al dejarlo, esa celda va a la celda que está bajo el cursor.
- **Con la mano vacía, el cursor sobre un objeto muestra su nombre** en un cartelito, en las grillas y en la barra rápida.
- **E también cierra la caja**, junto con el inventario, como Tab. Con el inventario abierto con Tab y sin caja, E no lo cierra: recoge o abre lo que mirás, como siempre. Con la caja abierta, abajo dice "E: cerrar …" (hasta el 2026-11-06: desde ese día no hay avisos de E encima de la barra; lo que E elegiría lo marca el indicador, sección 16 de la guía).

### Cuarta vuelta, con tu tercera prueba (2026-11-01)

- **Sin "recuerdo":** con un objeto en la mano, su lugar de antes queda vacío; antes se veía apagado. También queda vacío mientras lo que dejaste espera al host; en el lugar nuevo se ve el borde amarillo. Si el host lo rechaza, vuelve a aparecer en su lugar. Asignarlo a un acceso de la barra no lo mueve: ahí sigue viéndose.
- **"No hay lugar cerca para soltarlo"** colgado del cable es a propósito, mientras los objetos no tengan física: no caen, así que el host los apoya directo en el piso, y solo busca piso hasta 1,5 m debajo de tus pies, de 0,7 a 1,5 m alrededor tuyo. Colgado o en el aire, más alto que eso, no hay dónde apoyarlo. Con la física, va a caer desde la mano.

### El panel Objetos (2026-11-01)

Pediste una herramienta para no crear los objetos a mano, y elegiste un panel en el editor: la pestaña **Objetos**, al lado del **Inspector**. Con un botón hace los tres pasos de la sección 4. Cómo activarlo y usarlo, en la sección 4.

La primera versión rompía la vista 3D del editor (tu captura del mismo día: los íconos de la luz y de la cámara gigantes, sin perspectiva). Con la pestaña **Objetos** oculta, su texto de ayuda quedaba sin ancho y se partía letra por letra; su alto estiraba todo el editor, y la vista 3D llegaba a 5448 píxeles de alto, de los que se veía un pedazo. Arreglado ese día: los textos largos del panel tienen un ancho mínimo, y la vista volvió a su tamaño (comprobado con una foto del editor).

### El panel Objetos, segunda versión (2026-11-01)

Pedida en [`prompt_claude_creador_de_objetos.md`](prompt_claude_creador_de_objetos.md). El mismo panel, ampliado:

- Crea, abre, edita y duplica **ítems** y también **contenedores**.
- Muestra todo lo que antes había que cambiar en el Inspector, con una **vista previa**: el objeto en el piso o en la mano, la miniatura, y la huella sin girar y girada 90°.
- **Guardar** y **Colocar en la zona** son pasos separados. Colocar ya no guarda la zona sola.

Cómo se usa, en la sección 4.

### Acomodar la miniatura (2026-11-01, tus capturas 1079 y 1080)

Probaste la segunda versión y anduvo. Pediste dos cosas:

- **Acomodar el objeto en su miniatura,** como uno quiera. La puerta salía en diagonal porque toda miniatura arranca girada −20° y 35°.
- **"Apariencia y miniatura" no se entendía.**

Lo que cambió:

- Sección nueva, **Miniatura del inventario**: la imagen que se ve en la grilla, grande, para acomodarla con el mouse (girar, correr, acercar) o con botones (**↺ 90°**, **↻ 90°**, **De frente**, **Centrar** y **Automático**).
- Se sacaron del panel los números de giro y zoom y la casilla "acostarlo"; siguen en el Inspector.
- **Apariencia** muestra la forma simple y el color solo si no hay modelo, porque con modelo no se usan.
- Para poder correr el objeto en la miniatura, `InvItemDef` tiene un dato nuevo, **Thumbnail Offset**.

### Buscador y textos más claros (2026-11-01)

Tras tu prueba:

- **Abrir** pasó a ser un **buscador** con una lista: hoy hay pocos objetos, pero con cientos ya no alcanza una lista desplegable.
- No se entendían **Estado inicial** ni **Colocar en la zona**. Sus textos en el panel ahora dicen para qué sirven, con un ejemplo (también en la sección 4).
- Cada dato del estado va en dos renglones: arriba el nombre, abajo el tipo y el valor. Antes, el tipo no se leía.

### Consumibles con salud y estamina (2026-11-02)

Probado: el modelo 70 de 70, el laboratorio 166 de 166, tres procesos (host 18, A 24 y B 7) y el panel en una copia (144 de 144 en el editor, 25 de 25 jugando).

Pedido en [`prompt_claude_hud_salud_estamina_y_estados.md`](prompt_claude_hud_salud_estamina_y_estados.md); todo el detalle, en [`hud_salud_estamina_y_estados.md`](hud_salud_estamina_y_estados.md). Para el inventario cambió esto:

- **La vitalidad de prueba ya no existe.** Era un contador de la barra (`InvLoadout.test_vitality`, de 40 a 100). Los consumibles ahora cambian la salud y la estamina del personaje, que muestra el HUD. Así no hay dos números que parezcan la salud.
- **El consumible tiene dos números:**
    - **Efecto en la salud:** positivo cura y negativo daña; un daño mayor a lo que queda mata (muerte de prueba).
    - **Recupera estamina.**
    
    Uno que solo cura no se usa con la salud completa, y uno que solo devuelve estamina, con la reserva llena: no se gastan. Uno que daña se usa siempre. El host aplica el efecto y gasta la unidad en el mismo paso, y un pedido repetido no se vuelve a aplicar.
- **La Botella de agua cura 25** (lo que antes sumaba a la vitalidad). Hay cuatro objetos nuevos en la zona: **Botiquín**, **Bebida energética**, **Frasco de veneno** y **Cápsula letal**.
- **A la izquierda de la barra** ya no dice la vitalidad: ahí van los instrumentos del HUD. "Equipado: …" pasó a la derecha de la barra.
- **Las capacidades reciben la salud y la estamina del que las usa** (`ActorVitals`), para el menú y para el host. Es todo lo que el inventario ve del personaje.

### Menos texto en el panel: las burbujitas (2026-11-02)

Pediste sacar el texto que explica, porque el panel estaba muy cargado. Ahora cada explicación está en una **burbujita**: un signo de pregunta en un círculo, al lado del nombre del campo o del título de la sección. Un clic abre un globo con la explicación; otro clic, uno afuera o Escape lo cierran. Hay burbujitas en el buscador, Identidad (ID y Archivo), Apariencia (la sección, Modelo y Tamaño en el piso), Miniatura del inventario, Capacidades, los cuatro números del consumible, la Posición y el Tamaño del equipable, Estado inicial, Vista previa, Colocar en la zona (la sección, Unidades y Datos propios) y, en contenedores, Escena, Inventario y caja, Grilla, Medidas de la caja y Alcance.

Algunas cambian con lo que está abierto: la de **ID** dice si se puede cambiar, la de **Modelo** dice qué se ve ahora, y las de **Colocar** y **Vista previa** cambian entre ítems y contenedores.

Lo que eligió Claude: **siguen a la vista** los avisos, que cambian con lo que escribís: lo que falta para guardar, lo que no entra en una grilla, la línea del consumible que dice lo que hace, el resultado de guardar o colocar, lo que no se pudo dibujar en la vista previa y que la caja base no se cambia. La sección **Ayuda** del final, plegada, quedó igual. La burbujita está en `addons/inventario_objetos/ayuda.gd`.

### Usar, recoger y soltar sin esperar al host (2026-11-04)

Probaste todo en red y anduvo, pero al usar un veneno salía "esperando…" un momento, más largo con más latencia, y al recoger pasaba lo mismo. Era el viaje de ida y vuelta al host. Pediste sacarlo, también para la salud. El detalle está en la sección 12 de [`hud_salud_estamina_y_estados.md`](hud_salud_estamina_y_estados.md); para el inventario cambió esto:

- **Usar un consumible** (menú o barra rápida) ya no es un pedido: va en el input del personaje y lo aplican tu PC y el host en el mismo tick. La unidad se ve gastada en el mismo cuadro y la salud cambia en el tick siguiente.
- **Recoger** sigue siendo un pedido, pero lo recogido se ve en la grilla en el mismo cuadro y deja de verse en el piso. Si el host dice que no, vuelve al piso con el aviso.
- **El amarillo de "esperando…"** queda para mover, dividir y equipar. Soltar también esperaba, hasta el cambio de abajo.
- **Lo eligió Claude:** un uso por tick; mientras el host no confirma un uso (un ping), esa pila no se agarra ni se mueve, pero se puede volver a usar.

Probado sin red (`estados_test`, 101 de 101) y con host y cliente en esta PC, con internet mala (`pruebas/inv_instant_test.tscn`, 61 de 61, también con 300 ms y 8 % de pérdida). Las pruebas de antes, iguales. Lo probaste en las dos PC con +200 ms: funciona correctamente. Commit local `c392774`.

Después pediste lo mismo para **soltar**, que con latencia tardaba en aparecer en el piso. Ahora tu PC elige el lugar con la misma regla que el host y lo dibuja ahí ya. Se lo manda en un pedido nuevo (`DROP_AT`), y el host lo deja en ese lugar si sirve, así no salta. Vale desde la mano, desde **Soltar** del menú y desde **Soltar una cantidad…**, también desde una caja. Probado sin red (104 de 104) y en red con 120 y 300 ms (69 de 69), y por vos en las dos PC: funciona (commit local `2cf8fb1`). Medido con +200 ms en las dos, el host ve recoger y soltar a la misma demora, entre 232 y 240 ms. El detalle está en la sección 12 de [`hud_salud_estamina_y_estados.md`](hud_salud_estamina_y_estados.md).

### Los arreglos de la auditoría de GPT (2026-11-04, a la noche)

GPT revisó el inventario, la salud y la red ([`auditoria_inventario_salud_red_2026-11-04.md`](auditoria_inventario_salud_red_2026-11-04.md)). Los cinco errores que marcó eran ciertos y están arreglados. De los cuatro riesgos a futuro, elegiste tres para ahora. El detalle punto por punto, las pruebas y tu recorrido de prueba están en la sección 13 de [`hud_salud_estamina_y_estados.md`](hud_salud_estamina_y_estados.md). Para el inventario cambió esto:

- **El host hace las cosas en el orden en que las hiciste.** Recoger o soltar (pedidos) y usar (en el input) viajan por caminos distintos. Ahora un uso espera a que el host procese lo que pediste antes, y un pedido espera a los usos de antes. Antes, recoger algo y usarlo enseguida podía terminar en "No se usó: ese objeto ya no está en tu inventario".
- **Cada uso llega:** viaja en todos los inputs hasta que el host lo contesta, y el host contesta uno por uno.
- **La grilla que ves sigue ese mismo orden.** Antes, usar lo último de una pila y recoger otra igual mostraba la pila vieja llena.
- **La barra rápida respeta el "esperando…"** igual que el menú.
- **Un modelo con scripts no se usa como apariencia** (sección 4): se ve la caja de su color y se avisa. Los de hoy son `.glb` y no cambian.
- **Usar un consumible no redibuja los objetos del piso.**

### La integridad corporal a la derecha (2026-11-05)

Con el punto 1 del [roadmap](roadmap_integridad_habilidades_y_luz.md#panel-de-integridad), lo que abre **Tab** tiene un panel a la derecha de tu grilla: la **integridad corporal**, una silueta con el porcentaje de cada parte del cuerpo. **Pendiente de tu prueba manual.** Para el inventario cambió esto:

- **El panel va donde va la caja,** al lado de tu grilla y con su mismo alto. Con una caja abierta, **la caja tiene prioridad** y el panel no se ve, así seguís pasando objetos; al cerrarla, vuelve.
- **Abrir una caja con E entra directo en modo caja** (2026-11-08, pedido tuyo: antes se veía la integridad hasta que contestaba el host). Mientras el host contesta, el lado derecho queda reservado con el marco de la caja, de sus mismas medidas, y si tarda más de 0,15 s dice "Abriendo…". Si el host dice que no, todo vuelve a como estaba antes de E. Detalle en la sección 17 de [`hud_salud_estamina_y_estados.md`](hud_salud_estamina_y_estados.md). Lo probaste en las dos PC: funciona.
- **Tab con una caja abierta cierra solo la caja** (2026-11-08 a la tarde, pedido tuyo): el inventario sigue abierto y a la derecha vuelve la integridad. Lo que tenías en la mano desde la caja vuelve a la caja; lo de tu grilla sigue en la mano. E sigue cerrando la caja junto con el inventario, y Esc también cierra todo. Lo probaste en red: funciona.
- **Un clic con un objeto en la mano sobre el panel no lo suelta al piso.** Desde el 2026-11-06, si es un botiquín y la parte está dañada, la cura (abajo); si no, dice por qué y lo seguís teniendo en la mano.
- **Las luces de los estados** siguen yendo arriba a la derecha con el inventario abierto, ahora también lejos del panel.
- El lugar lo calcula la interfaz (`InvUI.side_panel_rect`) y el panel lo dibuja el HUD. Qué muestra y cómo se prueba, en la sección 14 de [`hud_salud_estamina_y_estados.md`](hud_salud_estamina_y_estados.md). Las pruebas del inventario dan lo mismo que antes: 91 de 91, 166 de 166, 83 de 83, y host 18, A 24 y B 7.

### El botiquín sobre una parte del cuerpo, y las vendas (2026-11-06)

Pedido tuyo, para seguir el punto 1 del roadmap. **Pendiente de tu prueba manual.** El detalle está en la sección 15 de [`hud_salud_estamina_y_estados.md`](hud_salud_estamina_y_estados.md). Para el inventario:

- **El gesto es el de siempre:** con **Tab**, un clic agarra el botiquín de tu grilla y otro clic lo suelta sobre una parte dañada del panel de integridad. La parte vuelve al 100 % y se gasta un solo botiquín. La salud y las otras partes no cambian, y anda también con la salud completa.
- **Donde no sirve, sigue en la mano y no se gasta nada:** sobre una parte entera ("Esa parte ya está entera"), entre dos partes o fuera de la silueta ("Apuntá a una parte del cuerpo"), con un objeto que no cura partes ("Eso no cura partes del cuerpo") o con clic derecho. Nada de eso lo tira al piso.
- **Con el objeto en la mano,** la parte bajo el cursor se marca: borde blanco y "curar pierna izquierda" si sirve, borde rojo si no.
- ~~**Es un pedido al host** (`HEAL_PART`, nuevo)~~: el host mira que el botiquín siga en tu inventario, que cure partes, que la parte exista y que tu personaje la tenga dañada, y cura y gasta juntos. **Desde la noche del mismo día (pedido tuyo) no espera al host:** va en el input como el uso normal, con la parte; tu PC la cura y muestra una unidad menos en el cuadro siguiente, y el objeto se puede volver a agarrar enseguida para curar otra parte (llevarlo a otro lugar de la grilla espera un instante, lo que tarda el host). El pedido `HEAL_PART` ya no existe. Detalle en la sección 16 de `hud_salud_estamina_y_estados.md`.
- **Usado normal** (menú o barra rápida), el botiquín sigue curando 50 de salud y no toca las partes.
- **La capacidad está en los datos del consumible:** **Part Repair**, en el grupo **Partes del cuerpo** del consumible, en puntos de porcentaje. El botiquín tiene 100 (la deja entera); uno con 30 sube la parte 30 puntos, sin pasar del 100 %. En 0, no cura partes. **Desde la tarde del 2026-11-06 está en el panel Objetos** (lo pediste): es el quinto número del consumible, **Cura una parte del cuerpo**, y uno que solo cura partes ya se guarda (usado normal, no hace nada ni se gasta). Detalle en la sección 15 de `hud_salud_estamina_y_estados.md`.
- **Las Vendas** (nuevas): curan 25 de salud, la mitad que el botiquín, con el mismo tope; no curan partes. Hay una en la zona, en la tercera columna, después de la toxina lenta. Pila de 5, 1 × 1.
- **La huella:** cambiaron el catálogo y la zona. En la notebook, `actualizar_lab.bat`.

### La hitbox de agarre (2026-11-07)

> **Desde el 2026-11-11 a la noche no interviene al recoger** (abajo, "El rayo de la mano"): se guarda en el `.tres`, se edita y se ve en el panel y entra en la huella, pero el juego no la arma en el mundo. Lo que sigue es cómo funcionaba hasta ese día.

Pedido tuyo. Cada tipo de objeto puede tener una **hitbox de agarre**: una caja, una esfera, un cilindro o una forma convexa propia, que la mira tiene que tocar para elegirlo suelto, con E y con el indicador. Sirve para que una llave chica sea fácil de apuntar, o para tapar los huecos de la silueta de un arma. El visor del panel ya fue probado a mano. Cómo se ajusta, cómo se ve y la lista para comprobar la recogida jugando están en la sección 16 de [`guia_del_laboratorio.md`](guia_del_laboratorio.md). Para el inventario:

- **Se edita en el panel Objetos**, sección **Hitbox de agarre**, debajo de **Apariencia** (sección 4, paso 5), con su vista previa en celeste.
- **Se guarda en el `.tres`** del ítem (`InvItemDef.pickup_hitbox`, un recurso `InvPickupHitbox`): el juego no necesita el panel.
- **Sin hitbox, o con «Forma del modelo»,** todo sigue como desde el 2026-11-06: los triángulos del modelo, con el margen **Pickup Aim Margin** del Tuning. **Con hitbox,** la mira toca esa forma, sin margen.
- **Un solo selector** para E y el indicador: gana lo que la mira toca primero. Las paredes, el alcance, la vista, el cono y lo que valida el host siguen igual; una hitbox que cruza una pared no deja recogerlo a través de ella. Desde el 2026-11-11 el alcance y la vista se miden con el modelo, nunca con la hitbox (abajo).
- **La huella:** entra la hitbox que usa la mira, con números redondeados. Si las dos PC no la tienen igual, la notebook no entra ("difiere en el inventario").
- **Ejemplo configurado:** `scenes/net_lab/inventario/objetos/machete.tres` ya tiene hitbox y encuadre propio para la barra rápida. Los ítems anteriores sin esos datos usan la forma del modelo y la miniatura de la grilla.

### El rayo de la mano (2026-11-11 a la noche)

Pedido tuyo, para el objeto sobre un borde que asoma poco. Todo el detalle (la regla, qué valida el host, las tolerancias, las diferencias con lo de esa mañana, el costo, los límites, las pruebas y la lista para las dos PC) está en [`problema_objeto_sobre_un_borde.md`](problema_objeto_sobre_un_borde.md). Para el inventario:

- **La regla:** un rayo desde los ojos del personaje (1,65 m sobre los pies parado, 0,85 m agachado), hacia el punto que señala la mira, tiene que tocar el objeto o la caja antes que otra cosa, a no más de **Interaction Range**, medido de los ojos al punto tocado. Un objeto se toca con los triángulos de su modelo tal como se ve; una caja, con su colisión. Tapan el nivel, las cajas y los demás objetos sueltos; los personajes, no.
- **Primera y tercera persona:** la mira elige el punto y la mano va desde los ojos. Si desde los ojos lo primero es otra cosa, gana eso: el indicador marca lo que hace E. El cono de la tercera persona sigue igual.
- **La caja abierta:** sigue abierta mientras los ojos estén a no más de **Interaction Range** de su parte más cercana. No hace falta mirarla.
- **El pedido** de recoger o abrir lleva la dirección de la mano y el tick del último input de tu PC. El host espera a tener a tu personaje en ese tick y tira su propio rayo desde sus ojos.
- **Sin** torso, vista con pocos puntos, **Pickup Aim Margin** ni hitbox de agarre.
- **La huella:** cada tipo suma sus triángulos (cuántos y una suma de todos), en vez de su caja envolvente y sus puntos. En la notebook, `actualizar_lab.bat`.

### Un solo alcance para recoger y abrir (2026-11-11)

*Esa mañana; desde la noche lo reemplaza el rayo de la mano (arriba). Siguen de esto el alcance común en el Tuning, el código único y la caja abierta sin mirarla.*

Con tus decisiones sobre [`problema_alcances_del_inventario.md`](problema_alcances_del_inventario.md), donde está todo el detalle (la regla, los ejemplos, lo que eligió Claude, los límites, las pruebas y la lista para probar en las dos PC):

- **La regla:** la distancia se mide en 3D desde el **torso** del personaje (el centro de su cápsula: 0,9 m sobre los pies parado y 0,5 m agachado) hasta la **parte más cercana** del objeto o de la caja, y tiene que ser como mucho **Interaction Range**. Una caja, con su caja de colisión, su lugar, su giro y su escala; un objeto suelto, con la caja de su modelo como se ve en el piso. La hitbox de agarre no cuenta: solo elige.
- **Dónde se ajusta:** nodo **Tuning**, grupo **Recoger y abrir**, **Interaction Range** (2 m de fábrica; en tu escena, 2,7 m, el ajuste que tenías en **Pickup Range**). Es uno solo para objetos y cajas: las cajas ya no tienen **Access Range**, ni en el Inspector ni en el panel Objetos.
- **La vista:** se tiene que ver desde los ojos una parte que esté al alcance; se prueban unos pocos puntos del objeto o de la caja (como mucho 8 rayos), no un solo punto fijo. Lo que se ve fuera del alcance, el aire de la caja envolvente de un objeto y una hitbox que cruza una pared no cuentan.
- **Con la caja abierta,** alcanza con la distancia: no hace falta seguir mirándola. Más lejos, el host la cierra.
- **Un solo código** (`InvReach`, en `scripts/inventory/inv_reach.gd`) lo usan tu PC, para el indicador y E, y el host, para recoger, abrir, operar y cerrar, con sus propios datos.
- **La huella:** suma la caja del modelo y los puntos de la vista de cada tipo, y el volumen de cada caja con su giro y su escala. En la notebook, `actualizar_lab.bat`.

---

## 1. Dónde está cada cosa

| Qué | Dónde |
| --- | --- |
| El código del inventario (modelo, red, interfaz, miniaturas) | `scripts/inventory/` |
| La caja reutilizable | `scenes/inventory/caja.tscn` |
| La zona de prueba | `scenes/net_lab/inventario/zona_de_inventario.tscn`, nodo **ZonaDeInventario** de `net_lab.tscn` (en x 37, z 13, pegada al borde este del piso) |
| Los objetos de prueba y su catálogo | `scenes/net_lab/inventario/objetos/*.tres` y `scenes/net_lab/inventario/catalogo_de_prueba.tres` |
| El panel **Objetos** del editor, para crear ítems y contenedores (sección 4) | `addons/inventario_objetos/`; sus pruebas, en `addons/inventario_objetos/pruebas/` |
| La hitbox de agarre de cada tipo (desde el 2026-11-07; desde el 2026-11-11 a la noche no interviene al recoger) | `scripts/inventory/inv_pickup_hitbox.gd`, guardada en el `.tres` de cada ítem; la edita el panel Objetos; su prueba, `scenes/net_lab/inventario/pruebas/inv_hitbox_test.tscn` |
| El rayo de la mano para recoger y abrir (desde el 2026-11-11 a la noche) | `scripts/inventory/inv_reach.gd` (`InvReach`), que usan `inv_net.gd` (el selector) e `inv_authority.gd` (el host); el pedido, en `inv_protocol.gd`; el valor, **Interaction Range** en el nodo **Tuning**; su prueba, `scenes/net_lab/inventario/pruebas/inv_alcance_test.tscn` |
| Los visores y la edición de miniaturas (sección 4) | En `addons/inventario_objetos/`, `vista_previa.gd` controla los visores 3D y `acomodador.gd` y `gizmo_rotacion.gd` editan los dos encuadres. En `scripts/inventory/`, `inv_thumbnails.gd` renderiza las imágenes e `inv_ui.gd` las dibuja en la interfaz. |
| Los contenedores creados con el panel | `scenes/net_lab/inventario/contenedores/` (se crea con el primero) |
| La red y los valores ajustables | nodo **Inventario** de `net_lab.tscn` (script `inv_net.gd`) |
| La interfaz | nodo **Hud → InventarioUI** de `net_lab.tscn` (script `inv_ui.gd`) |
| Las pruebas | `scenes/net_lab/inventario/pruebas/` |

---

## 2. Arquitectura

**Datos, separados:**

- **Definición** (`InvItemDef`, un `.tres` por tipo): nombre, tamaño, si gira, si se apila y hasta cuánto, sus capacidades, su modelo y, desde el 2026-11-07, su hitbox de agarre (`InvPickupHitbox`, opcional). Es compartida y no se cambia en el juego.
- **Instancia** (`InvStack`): un id estable, el tipo, la cantidad y su estado (por ejemplo `{"carga": 40}`). No sabe dónde está.
- **Colocación** (dentro de `InvGrid`): la celda y el giro de cada id. Es de la grilla, no del objeto.
- **Operaciones** (`InvOps`): mover (también entre grillas), apilar, dividir, sacar y meter lo que se recoge. Cada una valida todo antes de cambiar algo. Se prueban sin escena ni red.
- **Barra y equipo** (`InvLoadout`): la barra guarda ids, no copias. El objeto sigue ocupando su lugar en la grilla. (Hasta el 2026-11-01 también tenía la vitalidad de prueba; los consumibles ahora cambian la salud y la estamina del personaje.)

**Componentes por entidad:** `InvInventory` es el inventario de una entidad. La caja lo trae en su escena. Al personaje se lo agrega el host cuando aparece (un nodo **Inventario** hijo del actor), así `actor.tscn` no cambió. No hay inventario global, ni Autoload, ni singleton.

**Red** (`InvNet`, el nodo **Inventario**). Usa la misma conexión del laboratorio y pasa por el mismo simulador de red, con mensajes propios:

- El jugador pide con números de pedido (`InvProtocol`): solo números enteros, nunca nodos ni rutas.
- El host los ordena por número, descarta los repetidos (les vuelve a mandar el resultado) y los procesa en fila, uno por uno (`InvAuthority`). Cada pedido se valida y se aplica en el mismo paso.
- Por cada operación sale **un solo paquete por jugador**, con su resultado, sus inventarios, la caja abierta, los objetos del mundo y el equipo. Una transferencia entre dos inventarios llega junta: nunca se ve a medias.
- Los paquetes van numerados y cada máquina los aplica en orden (`InvReplica`), aunque el simulador de red los desordene.
- El jugador del host y "Jugar solo" usan el mismo camino, sin red.
- **Usar un consumible** no es un pedido: va en el input del personaje (desde el 2026-11-04). Cada pedido lleva el número del último uso hecho antes, y cada uso, el número del último pedido hecho antes. El host no hace uno antes que el otro: así los dos caminos se hacen en el orden en que jugaste (auditoría del 2026-11-04). Si lo que se espera no llega en 3 s, el host sigue sin él.

**Presentación local:** la interfaz lee lo que confirmó el host y pide cambios; nunca escribe ese estado. Los objetos sueltos en el mundo y lo equipado se dibujan en cada máquina con lo que cuenta el host. Las miniaturas se hacen en cada máquina y no viajan por red.

**Lo que se deja con clic derecho** sale de a un pedido por vez, porque cada uno necesita la versión que dejó el anterior. Los clics que llegan mientras uno espera quedan en fila, marcados con borde amarillo y "+N". Varios seguidos sobre el mismo lugar van en un solo pedido. Cuando llega la respuesta, el lugar se vuelve a calcular: un clic sobre la unidad recién dejada la suma a esa pila. Si el lugar cambió mientras tanto (por ejemplo, se cerró la caja), ese pedido no sale, y no se adivina otro.

### Quién valida qué (siempre el host)

| Operación | Qué comprueba el host antes de aplicarla |
| --- | --- |
| Mover, girar, transferir | Que el objeto exista con la versión que vio el jugador, que el destino tenga lugar, que el giro sea de 0 a 3 (y 0 si el objeto no gira) y que el jugador pueda tocar las dos grillas: la suya o la caja que tiene abierta y al alcance. El inventario de otro jugador, nunca |
| Apilar | Igual que mover, más: mismo tipo, mismo estado y lugar en la pila de destino. Pasa la cantidad pedida (con clic, toda la pila; con clic derecho, las unidades), hasta llenarla; el resto se queda |
| Dividir | Cantidad entera entre 1 y la cantidad menos 1, y lugar libre para la pila nueva, que recibe un id nuevo |
| Recoger | Que el objeto siga en el mundo y que el rayo del host, desde los ojos del personaje en su estado y en la dirección que manda el jugador, lo toque antes que otra cosa, a no más de **Interaction Range** (2 m de fábrica) de los ojos (desde el 2026-11-11 a la noche; esa mañana, del torso a la caja de su modelo, con la vista a unos pocos puntos; antes, del pecho a su punto de apoyo, con **Pickup Range**, y la vista a un solo punto). La dirección tiene que ser de tres números finitos y de largo 1, y el host espera a haber movido al personaje hasta el tick que trae el pedido. Primero completa pilas compatibles y después busca lugar libre, siempre en el mismo orden. Si entra solo una parte, el resto queda en el mundo |
| Soltar | Desde el inventario propio o desde la caja que tiene abierta y al alcance. Cantidad válida y un lugar en el piso cerca del personaje: que se vea desde el pecho, con piso abajo y sin pisar personajes, paredes, cajas ni otro objeto suelto. Si no hay lugar, no se suelta nada. Desde el 2026-11-04 el lugar lo elige tu PC con esa misma regla y lo manda en el pedido (`DROP_AT`); el host lo acepta si cumple la regla mirado desde tu personaje en el host, con 1 m de margen por la demora, y si no, elige él |
| Usar, equipar | Que el objeto esté en el inventario propio, que tenga esa capacidad y que se pueda (por ejemplo, con la salud completa, la botella no se usa ni se gasta). El efecto en la salud y la estamina y el gasto de la unidad van en el mismo paso |
| Barra rápida | Que el acceso exista y que el objeto sea del inventario propio |
| Abrir una caja | Que exista y que el rayo del host, como al recoger, la toque antes que otra cosa, a no más de **Interaction Range** de los ojos (desde el 2026-11-11 a la noche; esa mañana, del torso a su parte más cercana, con la vista a unos pocos puntos; antes, de los pies al centro de su base, con el **Access Range** de cada caja, y la vista a su centro). Con la caja abierta, en cada movimiento y en cada cuadro, solo la distancia de los ojos a su parte más cercana (con su lugar, su giro y su escala): si se aleja o la caja desaparece, se le cierra (no hace falta seguir mirándola, ni dejar de hacerlo) |

**Quién pide** sale siempre de la conexión, nunca del pedido. Un pedido hecho sobre una versión vieja de un objeto (otro lo cambió antes) se rechaza.

**Qué se mira lo elige cada máquina,** como dónde se apunta: el host no sabe hacia dónde mira la cámara. Desde el 2026-11-11 a la noche, la máquina manda la dirección de la mano y el host tira su propio rayo con ella, desde los ojos del personaje en su estado; no vuelve a mirar el cono de la tercera persona. La regla sale de un solo código, `InvReach`, que usan igual el selector y el host; el host la cumple con su estado del personaje, sus cajas y su copia del tipo de cada objeto, sin creerle al cliente posiciones, distancias ni lo que tocó.

**Cómo toca la mira un objeto suelto** (`InvNet.interaction_target`, el mismo selector para E y para el indicador). **Desde el 2026-11-11 a la noche,** la línea de la cámara elige el punto al que apuntás y un rayo desde los ojos hacia ese punto tiene que tocar el modelo (sus triángulos, armados una vez por tipo en `InvReach`) antes que otra cosa, al alcance. Los objetos sueltos ya no llevan ninguna forma invisible. Lo que sigue es cómo era hasta ese día.

Hasta el 2026-11-11, cada objeto suelto llevaba una forma invisible para apuntar, una Area3D que no chocaba con nada (`InvWorldItem.aim_area`). Esa forma era:

- **los triángulos de su modelo** (desde el 2026-11-06), en la capa 4, y la mira los toca con una esfera del radio de **Pickup Aim Margin** que viaja por la línea; lo que la esfera ya toca al salir cuenta, a distancia 0 (desde la auditoría del 2026-11-08, AG-01: antes, con la mira a menos del margen del modelo, no se elegía); o
- **la hitbox de agarre de su tipo** (desde el 2026-11-07), en la capa 5 (desde la auditoría del 2026-11-08, REND-01: antes compartían la capa 4 y la mira armaba en cada cuadro listas para excluir las formas de todos los objetos sueltos), y la mira la toca con la línea, sin margen.

Se buscan las dos clases, se ordenan por la distancia sobre la línea y gana el primero que se puede recoger. Tiene que estar antes que la caja o la pared que toca la mira: la hitbox, sin margen; la forma del modelo, con el margen. Después, como siempre, el alcance, la vista y el cono se miden con el objeto, no con su forma para apuntar (desde el 2026-11-11, con `InvReach`: hasta la caja de su modelo, y la vista a puntos de su modelo). De cada manera se sigue mirando hasta el primero que se puede recoger, hasta 32 formas (desde la auditoría del 2026-11-08, AG-02: antes eran 8 cualesquiera, y 8 hitbox de objetos que no se podían recoger, por ejemplo lejanos con la hitbox adelantada, tapaban al de atrás). Si alguna vez se llega a 32, `InvNet.aim_saturated` lo cuenta. Con varias formas a la misma distancia, gana la de origen más cercano y después la de número más bajo. Las formas se arman una vez por tipo y se olvidan cuando el inventario se va del mundo.

---

## 3. Cómo probarlo

### Solo, en esta PC

1. Abrí Godot. En las pestañas de arriba del visor, elegí **net_lab**.
2. **F6** → **Jugar solo**.
3. Date vuelta hacia la derecha (al este) y caminá unos 30 m: pasando el borde del piso está la **Zona de inventario**, con su cartel, una pared, dos cajas (la grande y el cajón chico) y tres filas de objetos en el piso (la tercera, desde el 2026-11-02, con los consumibles de salud y estamina).
4. Acercate a un objeto y miralo (el centro de la pantalla sobre él): aparecen cuatro esquinas alrededor y su nombre debajo (desde el 2026-11-06; antes, abajo decía "E: recoger …"). Apretá **E**.
5. **Tab** abre el inventario.
6. Clic en un objeto: queda en la mano. Clic donde lo querés dejar. Con una pila en la mano (por ejemplo, los tornillos), probá varios clics derechos en un lugar libre: deja de a una unidad.
7. Con la mano vacía, pasá el cursor por un objeto: aparece su nombre. Agarrá el machete por la punta de abajo y apretá **R** cuatro veces: gira alrededor de esa celda, que queda siempre bajo el cursor.
8. Cerrá con **Tab**, mirá la **Caja compartida** y apretá **E**: se abre. Otra vez **E**: se cierra.

### En las dos PC

1. **En esta PC:** guardá todo (**Ctrl+S**), pestaña **net_lab**, **F6** → **Crear partida**.
2. **En la notebook:** cerrá Godot y hacé doble clic en `actualizar_lab.bat` (en el Escritorio). Después **F6**, escribí la IP de esta PC y **Unirse**.
3. Los dos van a la zona de inventario.
4. Para probar la caja compartida:
    - Los dos se paran al lado de la **Caja compartida**, la miran y apretan **E**: se les abre a los dos.
    - Uno pasa un objeto de su grilla a la caja (clic en el objeto, clic en la caja): el otro lo ve aparecer.
    - Los dos pasan a la vez el mismo objeto de la caja a su inventario: se lo lleva uno solo, y al otro le aparece un aviso.
    - Uno agarra un objeto de la caja con un clic y, mientras lo tiene en la mano, el otro lo mueve: al primero se le suelta de la mano, con aviso.
    - Uno deja unidades de una pila en la caja con clic derecho: el otro las ve aparecer de a una.
    - Uno se aleja de la caja: se le cierra sola.
5. Uno se equipa el machete o la linterna (clic derecho → **Equipar**): el otro lo ve en su mano.
6. Uno suelta algo al piso (con el objeto en la mano, clic afuera de los paneles; o clic derecho → **Soltar**), también algo que esté en la caja: el otro lo ve en el piso, con su cantidad.
7. Para la entrada tardía: la notebook cierra la ventana del juego y vuelve a entrar. Tiene que ver todo lo soltado y lo equipado. Su inventario empieza vacío: al irse del todo, se va con su personaje.

Si la notebook no entra y dice "difiere en el inventario", las dos copias no tienen los mismos objetos, cajas o valores del nodo **Inventario**: actualizala con `actualizar_lab.bat`.

### Controles

| Tecla | Qué hace |
| --- | --- |
| **Tab** | Abre y cierra el inventario. El mundo no se pausa: con WASD seguís caminando y con Espacio saltás. El mouse queda libre y la cámara no gira. Con una caja abierta, cierra solo la caja: el inventario sigue abierto y a la derecha vuelve la integridad (desde el 2026-11-08) |
| **E** | Recoge el objeto o abre la caja que estás mirando (lo que diga el cartel de abajo), si está al alcance y a la vista. Con una caja abierta, la cierra junto con el inventario |
| **Cursor** sobre un objeto | Con la mano vacía, muestra su nombre. También sobre un acceso de la barra |
| **Clic** en un objeto | Lo agarra: queda en la mano, sin mantener el botón, con el cursor en el centro de la celda donde hiciste clic. Su lugar queda vacío |
| **Clic** con algo en la mano | Lo deja ahí. Verde: entra; celeste: se apila; rojo: no se puede (dice por qué, y lo seguís teniendo). Sobre otra grilla, lo pasa; sobre un acceso de la barra, lo asigna; afuera de los paneles, lo suelta al piso, también si es de la caja. En su propio lugar, lo devuelve |
| **Clic derecho** con algo en la mano | Deja una unidad en una grilla: en un lugar libre, o sumada a una pila igual. Lo demás sigue en la mano; con la última, la mano queda vacía. Sobre su propio lugar no deja nada |
| **R** (con algo en la mano) | Gira 90° en el sentido del reloj, alrededor del centro de la celda por donde lo agarraste, que sigue bajo el cursor. Cuatro veces vuelve a como estaba |
| **Clic derecho** en un objeto | Menú: Usar, Equipar o Desequipar, Inspeccionar, Dividir…, Soltar, Soltar una cantidad… y Quitar del acceso. Lo que no se puede aparece apagado y dice por qué. Soltar anda también en la caja |
| **Clic derecho** en un acceso | Lo vacía |
| **Clic en un acceso y clic en otro** | Los intercambia |
| **1 a 9 y 0** | Usan o equipan lo que tiene ese acceso (la botella cura 25 de salud; el machete y la linterna se equipan o desequipan) |
| **Esc** | Primero suelta lo que tenés en la mano (vuelve a su lugar) o cierra el diálogo, después el menú y por último el inventario. Con todo cerrado, suelta el mouse como siempre |
| **Alt + 1 a 5** | La simulación de internet (antes, 1 a 5 sin Alt) |
| **Y**, **U** (solo el host) | Empujón inmediato y programado (antes, E y R) |

Lo que está esperando al host se ve con un borde amarillo y dice "esperando…". Mientras tanto ese objeto no se puede volver a agarrar. Lo que dejaste con clic derecho y todavía no salió se marca con borde amarillo y "+N". Desde el 2026-11-04, usar un consumible, recoger y soltar no esperan: se ven en el momento (sección "Usar, recoger y soltar sin esperar al host", arriba).

### Qué hay en la zona

| Objeto | Tamaño | Para qué |
| --- | --- | --- |
| Botella de agua (2 y 1) | 1 × 2, pilas de 3 | Consumible: cura 25 de salud (hasta el 2026-11-01 subía la vitalidad de prueba). Con la salud completa no se usa ni se gasta |
| Botiquín (3) | 2 × 1, pilas de 3 | Consumible: cura 50 (desde el 2026-11-02). Desde el 2026-11-06, con Tab, soltado sobre una parte dañada del cuerpo la deja al 100 %, sin tocar la salud |
| Bebida energética (4) | 1 × 2, pilas de 4 | Consumible: +100 de estamina |
| Frasco de veneno (5) | 1 × 1, pilas de 5 | Consumible: −40 de salud, también con la salud completa |
| Cápsula letal (2) | 1 × 1, pilas de 2 | Consumible: −1000 de salud, una mata (muerte de prueba) |
| Toxina lenta (4) | 1 × 1, pilas de 4 | Consumible: quita 20 de salud de a poco en 4 s (daño en el tiempo, desde el 2026-11-02 a la tarde; ver `hud_salud_estamina_y_estados.md`, sección 11) |
| Vendas (1) | 1 × 1, pilas de 5 | Consumible: cura 25 de salud, la mitad que el botiquín; no curan partes del cuerpo (desde el 2026-11-06) |
| Machete | 1 × 3 | Equipable, con un modelo `.glb` |
| Linterna | 1 × 2 | Equipable, con una malla simple (un cilindro) |
| Banquito | 2 × 3 | Grande; se gira |
| Caja de herramientas | 3 × 2 | Ancho; se gira |
| Llave | 1 × 1 | No se apila |
| Tornillos (20 y 20) | 1 × 1, pilas de 30 | Al juntarlas, una queda en 30 y la otra en 10 |
| Granadas inertes (3 y 2) | 1 × 1, pilas de 4 | Pilas compatibles |
| Baterías de carga 100 y de carga 40 | 1 × 1, pilas de 4 | Mismo nombre, distinto estado: no se apilan |
| Caja compartida | 8 × 8 | La pueden tener abierta varios a la vez |
| Cajón chico | 4 × 3 | Para probar que algo grande no entra |

---

## 4. Crear un ítem o un contenedor

### Con el panel Objetos

**Dónde está:** la pestaña **Objetos**, al lado de **Inspector**. Ya está activada en `project.godot`. Si no la ves: **Project** → **Project Settings…** → pestaña **Plugins** → en la fila **Objetos del inventario**, tildá la casilla de la derecha. Para verla más grande, el menú ⋮ de la pestaña la hace flotante o la pasa abajo.

Arriba se elige **Ítems** o **Contenedores**. Debajo:

- **El buscador**: escribí parte del nombre, del ID o del archivo y la lista de abajo muestra los que coinciden (sin importar mayúsculas ni tildes; con varias palabras, tienen que estar todas). Un clic en la lista lo abre; Enter abre el primero. Muestra hasta 200 a la vez: si hay más, escribí más para achicar.
- **Nuevo**: uno vacío.
- **Duplicar**: una copia del que está abierto, con otro ID y otro archivo. El original no cambia.

Si cambiás de objeto o de pestaña con cambios sin guardar, pregunta: **Guardar**, **Descartar** o **Cancelar**.

Si algo no se entiende, hacé clic en el **?** que tiene al lado: abre la explicación. Se cierra con otro clic, con uno afuera o con Escape.

#### Crear un ítem

1. **Ítems** → **Nuevo**.
2. **Identidad**:
    - **Nombre**: el que se lee en el juego.
    - **Descripción**.
    - **ID** y **Archivo**: salen solos del nombre ("Termo de café" → `termo_de_cafe` y `objetos/termo_de_cafe.tres`). Se pueden cambiar antes de guardar; después, no.
3. **Grilla y pila**:
    - **Celdas**: ancho × alto.
    - **Se gira**.
    - **Se apila, hasta**: cuántos entran en una pila. Sin tildar, va de a uno.
    - Si no entra en la grilla del jugador (12 × 16) o en alguna caja conocida, lo avisa; igual se puede guardar.
4. **Apariencia**: cómo se ve en el piso, en la mano y en la miniatura.
    - **Modelo**: arrastrá un `.glb` o `.tscn` desde **FileSystem**. No se copia ni se cambia. Solo se usan sus mallas: no corren su física ni sus efectos. **Tiene que ser un modelo sin scripts** (un `.glb` importado no trae): armar la miniatura o el objeto en el piso crea la escena, y eso correría la lógica de sus scripts. Uno con scripts no se usa: se ve la caja de su color, la vista previa lo dice y el catálogo lo avisa en la consola (desde la auditoría del 2026-11-04; antes este texto decía que sus scripts no corrían, y no era del todo cierto).
    - Sin modelo aparecen **Forma simple** (caja, cilindro, esfera o cápsula, con sus medidas, o una malla de un archivo) y **Color**. Con modelo no se muestran, porque no se usan. Sin modelo ni forma, se ve como una caja de su color.
    - **Tamaño en el piso**: cuánto mide su lado más largo cuando está suelto en el mundo, en metros.
5. **Hitbox de agarre** (opcional, desde el 2026-11-07): un volumen fácil de apuntar para cuando está suelto. **Desde el 2026-11-11 a la noche el juego no la usa para recoger** (se recoge apuntando al modelo); se guarda y se ve igual, y lo que sigue es cómo se edita y cómo funcionaba.
    - **Forma del modelo** (lo que tiene un ítem nuevo): sus triángulos, con el margen **Pickup Aim Margin** del Tuning.
    - **Caja**, **Esfera** o **Cilindro**: arrancan ajustados al modelo como se ve en el piso. Las medidas y el **Desplazamiento** van en metros, al milímetro; la **Rotación**, en grados. **−1 cm** y **+1 cm** cambian 1 cm por cada lado, y **Ajustar al modelo** la vuelve a ajustar.
    - **Forma personalizada**: un recurso de colisión convexo (una ConvexPolygonShape3D, o una caja, esfera, cilindro o cápsula de colisión), que se corre y se gira igual.
    - Con una forma, la mira la tiene que tocar, sin margen. Se ve en celeste en el visor de la misma sección, que se actualiza al editar. Arrastrá con clic izquierdo para girar, con **Shift** para desplazar la cámara y usá la rueda para acercar. Podés desplazar los controles sin perder de vista el modelo. La casilla **Ver la hitbox de agarre** la oculta. También se ve en la **Vista previa** general, en el piso.
    - Si cambiás el modelo o su tamaño, la hitbox no se mueve sola: se avisa, y al guardar se pregunta.
    - Todo el detalle, en la sección 16 de `guia_del_laboratorio.md`.
6. **Miniatura del inventario**: la imagen que se ve en la grilla, grande, con las líneas de sus celdas. Se acomoda con el mouse:
    - Arrastrar la gira (con **Ctrl**, de a 15°).
    - Arrastrar con **Shift** y clic izquierdo, o con el botón derecho, la corre.
    - La rueda la acerca o la aleja.
    - Debajo de la imagen, arrastrá la etiqueta **X**, **Y** o **Z** hacia la izquierda o la derecha para girar sobre ese eje del modelo. También podés arrastrar los anillos. Mantené **Shift** para ajustar más fino o **Ctrl** para girar de a 15°.
    - Botones: **↺ 90°** y **↻ 90°** la giran un cuarto de vuelta en la pantalla; **De frente** la deja sin giro; **Centrar** la pone en el medio, sin acercar; **Automático** la deja como sale sola (en diagonal, acostada si su lado largo no coincide con el de la huella, y en el medio).
    - Es la misma imagen que hace el juego: al girar el objeto con R en la grilla, gira con él.
7. **Miniatura de la barra rápida**: abrí la sección y activá **Usar un encuadre propio** para girar, correr o acercar el modelo en el casillero cuadrado con los mismos controles y anillos de rotación. Con la casilla apagada se usa la miniatura de la grilla, centrada y sin estirar. Al apagarla se conservan tus ajustes para cuando vuelvas a activarla.
8. **Capacidades** (opcionales):
    - **+ Consumible**: al usarlo gasta una unidad y cambia la salud o la estamina del que lo usa (desde el 2026-11-02; antes subía la vitalidad de prueba). **Efecto en la salud (puntos)**: positivo cura y negativo daña; la salud completa son 100, y un daño mayor que lo que queda mata (muerte de prueba). **Recupera estamina**: la reserva completa son 200. Además, el daño en el tiempo con sus segundos y, desde el 2026-11-06, **Cura una parte del cuerpo** (con Tab, soltado sobre una parte dañada del panel del cuerpo, le suma ese porcentaje). Debajo, una línea dice lo que hace. Con todo en 0 no se guarda. Más detalle en `hud_salud_estamina_y_estados.md`, sección 5.
    - **+ Equipable**: se lleva en la mano y los demás lo ven. Elegís su posición, giro y tamaño en la mano. No dispara, no pega ni ilumina.
    - La primera de la lista es la de la barra rápida; las flechas cambian el orden.
9. **Estado inicial** (opcional): datos que lleva cada unidad del objeto, y con estos valores nace. Por ejemplo, una batería con `carga = 100` (cada dato es un número entero, un número con decimales, un texto o sí/no). Para qué sirve hoy: dos unidades del mismo objeto se juntan en una pila solo si sus datos son iguales. Una batería con carga 100 y otra con carga 40 no se apilan, aunque se llamen igual. Hoy ningún dato cambia solo al jugar (la carga no baja): queda listo para mecánicas futuras. Si no lo necesitás, dejalo vacío.
10. Mirá la **Vista previa**: el objeto en el piso, con su hitbox de agarre si tiene una (o **En la mano**, si es equipable; se gira arrastrando), y su miniatura como queda en la grilla, sin girar y girada 90°. En este visor, **Shift + arrastre izquierdo** desplaza la cámara. En la imagen de una miniatura editable, el mismo gesto corre el modelo dentro del cuadro y modifica el encuadre que se guarda.
11. **Guardar**. Crea el `.tres` y lo suma una vez al catálogo. No pone nada en el mapa.

#### Crear un contenedor

1. **Contenedores** → **Nuevo**, o abrí la **Caja base** y apretá **Duplicar**.
2. **Nombre**, **Grilla** (columnas × filas, hasta 64 × 64), **Medidas de la caja** (x, y, z en metros) y **Color**. Hasta el 2026-11-11 había también un **Alcance** por caja, con su círculo amarillo en la vista previa: desde ese día todas se abren con **Interaction Range** del nodo **Tuning**, medido hasta su parte más cercana, y la vista previa muestra la caja con el personaje al lado, para ver el tamaño.
3. **Guardar**. Crea `contenedores/<nombre>.tscn`, una escena heredada de `caja.tscn`: trae su inventario y lo enlaza solo. Se crea vacía; lo de adentro se pone jugando.

#### Colocar en la zona

**Para qué sirve:** guardar crea el objeto (el juego lo conoce), pero no lo pone en ningún lado del mundo. Colocar pone unidades en el piso de la zona de inventario, pasando el borde este del piso, para encontrarlas y recogerlas con E al jugar. Es para probar en el laboratorio; en el juego de verdad los pondrá cada nivel.

Con lo guardado abierto, sección **Colocar en la zona**:

- **Ítems**: **Unidades**. Van en pilas válidas: 12 de a 5 son tres pilas, de 5, 5 y 2. Con 0 no se coloca nada. Abajo, **Datos propios de estas unidades** (opcional) reemplaza datos del estado inicial solo para las que pongas ahora: por ejemplo, unas baterías gastadas con `carga = 40`.
- **Contenedores**: **Cajas**, cuántas. Cada caja tiene su propio inventario, aunque sean de la misma escena.

**Colocar en la zona** abre la zona, busca lugares libres en el piso y deja lo colocado seleccionado, para moverlo con las herramientas de Godot. **La zona queda sin guardar**: guardala con **Ctrl+S** o con **Guardar la zona**. Si no hay lugar para todo, dice cuántos entran y no coloca nada.

#### Editar

**Abrir** → cambiás → **Guardar**.

- Mientras escribís, lo guardado no cambia. **Descartar cambios** vuelve a lo guardado sin escribir nada.
- Se guarda en el mismo archivo, con el mismo uid. Todo lo que lo usa (el catálogo, la zona) sigue apuntando a él. Lo que el panel no muestra se conserva, como una capacidad que no conoce (se abre con **Abrir en el Inspector**).
- Si el archivo cambió desde que lo abriste (por ejemplo, en el Inspector), pregunta antes de pisarlo.
- Si un cambio afecta lo colocado, también pregunta, y no corrige nada solo. Por ejemplo, bajar el límite de la pila con marcadores de 20 unidades: al jugar, se recortarían.
- Un contenedor se guarda con el editor: abre su escena un momento, la guarda y vuelve a la que tenías. Las cajas ya colocadas toman los valores nuevos; si la zona tenía cambios sin guardar, la deja como está y avisa que hasta guardarla y reabrirla las ve con los valores viejos.
- La caja base (`caja.tscn`) no se cambia desde el panel: de ella heredan todas.

#### Qué produce

| Qué | Dónde |
| --- | --- |
| Un ítem | `scenes/net_lab/inventario/objetos/<id>.tres` (con su hitbox de agarre adentro, si tiene una), y una línea en `catalogo_de_prueba.tres` que apunta a él |
| Un contenedor | `scenes/net_lab/inventario/contenedores/<nombre>.tscn`, heredada de `scenes/inventory/caja.tscn` |
| Lo colocado | Nodos en `zona_de_inventario.tscn`: marcadores **InvPickupSpawn** adentro de **Objetos**, y cajas en la raíz de la zona |

Son recursos y escenas normales del proyecto: el juego no necesita el panel.

#### Qué deshace Ctrl+Z

Saca lo que se colocó en la zona. No borra el `.tres` ni la escena del contenedor, no los saca del catálogo ni deshace un guardado: eso ya está escrito en el disco.

#### Lo que se rechaza sin escribir nada

- Un nombre vacío.
- Un ID vacío, con mayúsculas, tildes o espacios, de más de 64 letras, o que ya está en el catálogo.
- Un archivo fuera de `scenes/net_lab/inventario/` o que ya existe: no se pisa nada.
- Medidas fuera de rango:
    - celdas, de 1 a 64;
    - pila, de 2 a 9999 si se apila;
    - tamaños, en metros.

    Hasta el 2026-11-11 también se rechazaba un alcance de caja que no llegaba desde ningún lado, y se avisaba "se abre solo desde los lados largos": con el alcance común, medido hasta la parte más cercana, ya no hace falta.
- Dos capacidades del mismo tipo.
- Un estado con nodos, recursos o números rotos. No se evalúa nada de lo escrito.
- Una hitbox de agarre que no sirve (desde el 2026-11-07): medidas de 0, negativas, de más de 10 m o que no son números; un desplazamiento de más de 10 m o una rotación de más de 360°; una forma personalizada sin recurso, vacía, sin volumen o que no es convexa.
- Colocar sin lugar en la zona.

Si un guardado falla a mitad de camino, deshace lo que alcanzó a escribir y lo dice. Por ejemplo, si se guardó el `.tres` pero no el catálogo, se borra el `.tres`. Si ni eso pudiera, dice exactamente qué quedó.

#### Probar lo creado

- **Solo:** sección 3, "Solo, en esta PC".
- **En las dos PC:** después de guardar o colocar, la notebook necesita la misma versión del laboratorio: `actualizar_lab.bat`, o una exportación nueva para los dos. Si no, no entra: "difiere en el inventario". El panel no manda nada por red: lo creado viaja por el mismo camino que lo hecho a mano.

#### Límites

- Trabaja solo con el catálogo y la zona del laboratorio. La red los usa porque el nodo **Inventario** de `net_lab.tscn` apunta a ese catálogo y tiene la zona de **World Root**; el panel comprueba que siga así. Otro nivel necesitaría su propio nodo **Inventario**.
- No borra ni cambia IDs. Para borrar uno, a mano: sus marcadores de la zona, su lugar en **Items** del catálogo y su `.tres`.
- Los contenedores son la caja de color de `caja.tscn`: sin modelos propios, sin contenido inicial y sin cerraduras.
- Del estado se editan números, textos y sí/no. Una lista o un vector que ya estuvieran se conservan, y se cambian en el Inspector.

### A mano

1. En **FileSystem**, clic derecho en `scenes/net_lab/inventario/objetos` → **Create New** → **Resource…** → buscá **InvItemDef** → **Create**. Ponele nombre (por ejemplo `cuerda.tres`) y **Save**.
2. Con el `.tres` seleccionado, en el Inspector:
    - **Id**: un nombre único, sin espacios (`cuerda`). Es lo que viaja por red.
    - **Display Name** y **Description**: lo que se lee en el juego.
    - Grupo **Grilla**: **Size** (ancho y alto en celdas, sin girar) y **Can Rotate**.
    - Grupo **Pila**: **Stackable** y **Max Stack**.
    - Grupo **Capacidades**: en **Abilities**, **Add Element** → **New InvConsumable** (cura, daña o devuelve estamina; **Health** y **Stamina**; y en su grupo **Partes del cuerpo**, **Part Repair**) o **New InvEquippable** (en la mano: **Hold Offset**, **Hold Rotation** y **Hold Size**). La primera de la lista es la que hace la barra rápida.
    - Grupo **Estado**: **Default State**, por ejemplo `carga: 100`. Dos pilas del mismo tipo se juntan solo si su estado es igual.
    - Grupo **Modelo**: arrastrá un `.glb` desde **FileSystem** a **Model**, o poné una malla en **Mesh** (con **Color**). **World Size** es cuánto mide en el piso el lado más largo.
    - Grupo **Hitbox de agarre** (opcional, desde el 2026-11-07): **Pickup Hitbox** → **New InvPickupHitbox**. Adentro, **Kind** (la forma), las medidas de esa forma, o **Custom Shape** para la personalizada, y en **Lugar**, **Offset** y **Rotation Degrees**. Vacío, se elige por la forma del modelo. Con el panel es más fácil: ajusta al modelo y la muestra.
    - Grupo **Miniatura** de la grilla. **Thumbnail Rotation** gira el modelo, **Thumbnail Zoom** lo acerca, **Thumbnail Offset** lo corre y **Thumbnail Auto Align** lo acuesta 90° si su lado largo no coincide con el de la huella.
    - Grupo **Miniatura de la barra rápida**. **Custom Hotbar Thumbnail** habilita el encuadre cuadrado con **Hotbar Thumbnail Rotation**, **Zoom** y **Offset**. El giro automático de la grilla se aplica solo a la miniatura del inventario.
3. Abrí `catalogo_de_prueba.tres` y en **Items** → **Add Element** → arrastrá tu `.tres`. Un objeto que no está en el catálogo no existe para la red.
4. Para que aparezca en el mundo: en `zona_de_inventario.tscn`, clic derecho en **Objetos** → **Add Child Node** → **InvPickupSpawn** → **Create**. En el Inspector, **Item** (tu `.tres`), **Quantity** y, si querés otro estado, **State Override**. Desde el 2026-11-06, **Show Label** apagada lo deja sin el cartel con su nombre arriba. Movelo hasta apoyarlo en el piso.
5. **Ctrl+S**. Las dos PC tienen que tener lo mismo, o la notebook no entra ("difiere en el inventario").

La miniatura sale sola del modelo, la primera vez que el objeto se ve en la interfaz. Sin modelo ni malla, se ve un rectángulo de su color con el nombre.

---

## 5. Otra caja, y cambiar las medidas de las grillas

- **Con el panel Objetos:** pestaña **Contenedores**, como en la sección 4.
- **Agregar una caja a mano:** en `zona_de_inventario.tscn` (o en cualquier nodo adentro de **ZonaDeInventario**), arrastrá `scenes/inventory/caja.tscn` desde **FileSystem** al árbol. En el Inspector: **Display Name**, **Columns** y **Rows** (su grilla), y **Box Size** y **Color** (cómo se ve y choca; **Box Size** es también hasta dónde se mide el alcance). Se puede girar y escalar: el alcance la sigue. No hace falta numerarla: se numeran solas por su orden en la escena. Hasta el 2026-11-11 tenía también **Access Range**.
- **La grilla del jugador:** nodo **Inventario** de `net_lab.tscn`, grupo **Grilla del jugador**, **Player Columns** y **Player Rows** (12 × 16).
- **El tamaño de las celdas en pantalla:** nodo **Hud → InventarioUI**, **Cell Size** (40 píxeles). Si la grilla no entra en la pantalla, se achica sola.
- **Los alcances:** recoger y abrir, nodo **Tuning**, grupo **Recoger y abrir**, **Interaction Range** (desde el 2026-11-11, uno solo para objetos y cajas, medido desde los ojos desde esa noche; reemplaza al **Pickup Range** del Tuning, que antes estuvo en este nodo, y al **Access Range** de cada caja). Soltar, nodo **Inventario**, **Drop Distance** (a qué distancia adelante cae lo que soltás).
- **Mirar:** nodo **Inventario**, grupo **Mirar**. **Look Cone Degrees** (75): en tercera persona, cuántos grados a cada lado de hacia donde mira el personaje puede estar lo que se agarra o se abre. Es de cada máquina: no hace falta que las dos PC lo tengan igual. Cuánto se perdonaba al apuntar a un objeto suelto era **Aim Margin** (0,12 m alrededor de su tamaño), en este grupo; del 2026-11-06 al 2026-11-11, **Pickup Aim Margin**, en el **Tuning** (2 cm alrededor de la forma del modelo). Desde el 2026-11-11 a la noche no hay margen: el rayo de la mano tiene que tocar el modelo.

---

## 6. Archivos que ya existían y se cambiaron

| Archivo | Qué cambió |
| --- | --- |
| `scenes/net_lab/net_lab.tscn` | Tres nodos nuevos: **ZonaDeInventario**, **Inventario** y **Hud → InventarioUI** |
| `scenes/net_lab/net_lab.gd` | Arranca el inventario con el rol, corta el teclado del personaje mientras se escribe una cantidad, oculta el panel con el inventario abierto, suma la huella del inventario, y las teclas movidas: Alt + 1 a 5, Y y U |
| `scenes/net_lab/lab_camera.gd` | `hold_mouse` y `release_mouse`: mientras una interfaz necesita el mouse, la cámara no lo recaptura ni gira. `aim_ray`: la mira, la línea por el centro de la pantalla desde la altura de la cabeza |
| `scripts/net/net_session.gd` | La señal `actor_replaced`, cuando un jugador vuelve de un corte y su actor se cambia por uno nuevo: el host le pasa el inventario |
| `scripts/net/sim_fingerprint.gd` | Una quinta parte de la huella, "el inventario" (código de `scripts/inventory`, catálogo, cajas, objetos y valores) |
| `project.godot` | Diez acciones nuevas, `acceso_rapido_1` a `acceso_rapido_0`. Se usan las que ya estaban: `toggle_inventario` (Tab), `rotar_item` (R) e `interactuar` (E) |

No se tocaron el nivel, el personaje (`actor.tscn`), el motor, los modelos, las texturas, los materiales, la escena principal ni la exportación. Los modelos de `assets/models/collectibles` se usan para las miniaturas sin modificarlos.

Con la segunda versión del panel Objetos (2026-11-01) cambiaron tres archivos del inventario. Lo que se ve en el juego quedó igual (comprobado con la prueba visual):

| Archivo | Qué cambió |
| --- | --- |
| `scripts/inventory/inv_thumbnails.gd` | Cómo se arma la escena de la miniatura pasó a dos funciones, `image_size` y `build_viewport`, y el dibujo girado a `draw_turned`. Las usan el juego y la vista previa del panel: la misma regla de encuadre |
| `scripts/inventory/inv_ui.gd` | Dibuja la miniatura girada con `InvThumbnails.draw_turned` |
| `scripts/inventory/inv_container.gd` | La malla y el cartel de la caja salen de `InvContainer.look`, que también usa la vista previa |
| `scripts/inventory/inv_item_def.gd` (al acomodar la miniatura) | Un dato nuevo, **Thumbnail Offset**: cuánto se corre el modelo en la miniatura, en partes del cuadro. Entra en la clave de la miniatura (`appearance_key`), no en la huella: es solo dibujo |
| `scripts/inventory/inv_thumbnails.gd` (al acomodar la miniatura) | El encuadre pasó a `frame`, que también aplica el corrimiento. El panel lo vuelve a llamar mientras acomodás, sin rearmar el modelo. Sin corrimiento, las miniaturas salen idénticas a las de antes (comparadas archivo por archivo) |

Al ser código de `scripts/inventory`, cambia la parte "el código" de la huella: la notebook necesita `actualizar_lab.bat`, como con cualquier cambio. La huella no necesitó nada nuevo: lo funcional que edita el panel ya estaba en ella (ID, grilla, pila, estado, efecto del consumible, cajas con sus medidas y alcance; desde el 2026-11-02 el efecto es la salud y la estamina). Lo de la mano y el modelo es solo dibujo, y no entra. *Desde el 2026-11-11 el modelo sí entra:* la caja que ocupa en el piso y los puntos de la vista deciden el alcance, así que van en la huella de cada tipo; las cajas ya no tienen alcance propio y suman su volumen con su giro y su escala.

Con la implementación inicial de la hitbox de agarre (2026-11-07):

| Archivo | Qué cambió |
| --- | --- |
| `scripts/inventory/inv_pickup_hitbox.gd` (nuevo) | El recurso `InvPickupHitbox`: la forma, sus medidas, su lugar, qué no sirve, cómo se ajusta al modelo y qué va en la huella |
| `scripts/inventory/inv_item_def.gd` | **Pickup Hitbox**, en el grupo **Hitbox de agarre**, y la hitbox que usa la mira en `fingerprint_text` |
| `scripts/inventory/inv_world_item.gd` | Su forma para apuntar (la misma Area3D, en la misma capa) lleva la hitbox, si el tipo tiene una que sirve, con su lugar; si no, los triángulos. Una forma por tipo. `has_pickup_hitbox` |
| `scripts/inventory/inv_net.gd` | `interaction_target` busca las dos clases de formas (`_aim_candidates`) y gana la primera sobre la mira; la hitbox, sin margen y antes que la pared |
| `scripts/inventory/inv_catalog.gd` | Avisa en la consola de una hitbox que no sirve |
| `addons/inventario_objetos/formulario_item.gd` | La sección **Hitbox de agarre** |
| `addons/inventario_objetos/vista_previa.gd` | La hitbox en celeste y su casilla |
| `addons/inventario_objetos/guardado.gd` | La hitbox se guarda y se copia con el resto, se valida, y se pregunta si cambió el modelo y la hitbox no |
| `addons/inventario_objetos/objetos_panel.gd` | Actualiza la sección en cada cambio; la burbujita de **Vista previa** la nombra |

Cambia la parte "el código" de la huella y, con una hitbox puesta, también "el inventario": en la notebook, `actualizar_lab.bat`.

### Visores y encuadre de la barra rápida

| Archivo | Qué hace |
| --- | --- |
| `addons/inventario_objetos/formulario_item.gd` y `vista_previa.gd` | El visor de la hitbox queda junto a los controles. Comparte el gesto de desplazar la cámara con la vista general. |
| `addons/inventario_objetos/acomodador.gd` y `gizmo_rotacion.gd` | Los dos encuadres comparten el editor y el gizmo. Los anillos y las etiquetas giran sobre ejes locales del modelo. |
| `scripts/inventory/inv_item_def.gd` y `addons/inventario_objetos/guardado.gd` | `custom_hotbar_thumbnail` elige el encuadre propio. Los campos `hotbar_thumbnail_rotation`, `hotbar_thumbnail_zoom` y `hotbar_thumbnail_offset` se guardan y se copian con el ítem. |
| `scripts/inventory/inv_thumbnails.gd` e `inv_ui.gd` | La barra reutiliza la textura de la grilla cuando el encuadre propio está apagado y la ajusta al casillero manteniendo la proporción. Con encuadre propio genera una imagen cuadrada que usa su propia clave de caché. |

Los ajustes visuales de ambas miniaturas forman parte de su clave de apariencia. La huella del catálogo incluye la hitbox de agarre, mientras que los cambios a los scripts del inventario afectan la parte de código.

---

## 7. Pruebas

| Prueba | Qué cubre | Resultado (2026-10-31) |
| --- | --- | --- |
| `inv_model_test.tscn` (modelo, sin escena) | Bordes, solapamiento, los cuatro giros (180° ocupa como sin girar; 270°, como 90°; giros de 4 o negativos se rechazan), un objeto que no gira, mover sobre la propia huella, rechazos que no cambian nada, pilas parciales y llenas, apilar solo una cantidad, estado distinto, divisiones inválidas y sin lugar, recogida parcial, soltar, transferir, barra después de cada operación y copias por red mal formadas (también con el giro viejo, verdadero o falso) | **70 de 70** |
| `inv_lab_test.tscn` (el laboratorio entero, un proceso) | Todo lo de arriba por el camino real del host, más: todos los objetos de la zona en el piso (los cuenta: si agregás uno, la prueba sigue andando); lejos no se recoge ni se abre; soltar contra una pared y encerrado entre paredes; soltar desde la caja; el banquito girado en la caja; transferencia que no entra en el cajón chico; cierre al alejarse; pedido repetido (una sola botella gastada) y pedido viejo; el inventario de otro; dos jugadores sobre la misma pila de la caja y sobre el mismo objeto del mundo (gana uno); desconexión; Esc en orden; WASD con el inventario abierto; W quieto mientras se escribe; cantidad no numérica; un clic agarra y otro deja; en la mano y mientras espera al host, su lugar de antes queda vacío (y asignado a un acceso, no); un clic donde no se puede deja el objeto en la mano; se agarra por el centro de la celda del clic y R lo gira cuatro veces alrededor de ella (la punta agarrada va a la izquierda, arriba, a la derecha y vuelve), y esa celda cae bajo el cursor aunque el cursor esté cerca del borde; el nombre al pasar el cursor (sobre un objeto y sobre un acceso; no sobre una celda vacía, con algo en la mano ni con el menú abierto); E cierra la caja con el inventario, no cierra el inventario abierto con Tab, y apretada antes de que conteste el host la caja no queda abierta; clic derecho: tres seguidos hacen una pila de 3, uno más se suma a esa pila, sobre su propio lugar no deja nada, con la última la mano queda vacía, y el total se conserva; mirar: se elige lo que se mira y no lo de al lado, en tercera persona no lo que está detrás del cuerpo, con una pared en el medio no se elige y el host no deja recoger; dejar sobre la barra, un panel o un menú no suelta al piso; la caja que desaparece con algo suyo en la mano; y que las cantidades se conserven. Desde el 2026-11-06, la mira por la forma del objeto: la forma para apuntar es la del modelo; con 2 cm de margen se elige pasando a 1 cm del borde y no a 4 cm (la esfera de antes sí lo agarraba); sin margen, solo tocándolo; con 8 cm, también a 4 cm | **166 de 166** (2026-11-01); **175 de 176** (2026-11-06, con la mira por la forma: la que falla cuenta los objetos de la zona, y las Vendas que colocaste en el nivel suman uno) |
| `inv_pair_test.tscn` con tres procesos en esta PC: host; cliente A con +120 ms, ±40 ms y 2 % de pérdida, que se corta 8 s y vuelve; cliente B, que entra tarde | Estado inicial; A camina, recoge las dos baterías (no se apilan) y abre la caja; carrera por la misma pila (ganó el host; A ve el rechazo); a A se le suelta de la mano la llave cuando el host la mueve; A ve el machete en la mano del host y los tornillos soltados; A vuelve del corte con el mismo inventario y los mismos ids; B ve lo soltado y el machete; al irse, el host no guarda suscripciones ni pedidos; el mundo, igual en los tres; el inventario de A, igual en A y en el host | **Host 18, A 24 y B 7, sin fallas** |
| `inv_visual_test.tscn` (con ventana) | Las 9 miniaturas hechas desde el modelo, con fondo transparente; tres clics derechos dejan 3; el nombre de la batería al pasar el cursor; capturas de la grilla, la caja, el objeto en la mano girado 90°, 180° y 270°, el rojo sobre otro objeto, el clic derecho, el nombre al pasar el cursor, el menú, la inspección, la división y lo equipado | **7 de 7** (y las capturas, revisadas) |
| El panel **Objetos**, primera versión, en una copia del proyecto | Crear con un botón, rechazos y colocación | **Todo bien** (2026-11-01, a la tarde); la reemplazan las dos de abajo |
| `addons/inventario_objetos/pruebas/prueba_del_creador.gd`: el panel de la segunda versión, en una copia del proyecto, con el editor sin ventana | Desactivar y activar el plugin tres veces: un solo panel y una sola conexión. **Ítem simple:** el ID y el archivo salen del nombre; guardarlo no pone nada en la zona; queda una sola vez en el catálogo, apuntando al `.tres`. **Apilable:** 12 de a 5 son marcadores de 5, 5 y 2, seleccionados, en **Objetos**; la zona queda sin guardar; Ctrl+Z los saca sin borrar el `.tres` ni sacarlo del catálogo; Ctrl+Y los vuelve a poner; guardada, cerrada y reabierta, los 3 siguen (12 unidades). **Rechazos sin escribir nada:** ID repetido, ID inválido, nombre vacío, tamaño 0, dato del estado sin nombre, estado con números rotos u objetos, ruta fuera de la carpeta, pisar otro archivo y 500 unidades sin lugar. **Consumible de 7 y equipable** con posición, giro y tamaño propios; dos del mismo tipo no se pueden sumar. **Editar:** la batería conserva su uid, su ID, su estado y un dato que el panel no muestra; el original no cambia mientras se escribe; el ID no se cambia ni a la fuerza; descartar no escribe; si cambió por afuera, pregunta; bajar el límite de los tornillos avisa por los marcadores de 20 y no recorta. **Duplicar** la linterna: otro ID, su propia capacidad y su propia malla; cambiar la copia no toca el original. **Cambios sin guardar** al cambiar de pestaña: pregunta; Cancelar, Descartar y Guardar hacen lo suyo. **Contenedor nuevo:** un alcance que no llega se rechaza sin crear la carpeta; la escena hereda de `caja.tscn` con su Inventory enlazado; dos colocados, cada uno con su inventario, sin pisarse; Ctrl+Z y Ctrl+Y; editado a 4 columnas, las cajas colocadas lo toman y la zona no deja pegado el valor viejo; con la zona sin guardar, no la recarga y avisa; la caja base no se edita y se duplica. **Fallos al guardar,** con un guardado que falla a propósito (sin dañar nada): si falla el catálogo, se borra el `.tres` nuevo y el catálogo queda igual; si falla una edición, el archivo y el recurso quedan como estaban; si falla un contenedor, no queda la escena. **Miniatura** (agregado al acomodarla): De frente, ↺ 90°, arrastrar de costado (gira alrededor del eje vertical de la pantalla), Ctrl de a 15°, correr y acercar escriben lo esperado y se guardan; Centrar; corrido fuera del cuadro se rechaza; Automático vuelve a los valores de fábrica. **Buscador** (agregado después): sin buscar están todos; «bater», «BATERÍA», «caja herr», «puerta_de» y «tornillos.tres» encuentran uno; algo que no existe no encuentra nada y lo dice; un clic abre y queda marcado; Enter abre el primero; en contenedores arranca vacío y está la caja base; con 500 que coinciden muestra 200 y lo dice, y escribiendo más se achica. **Burbujitas** (2026-11-02): con un consumible se ven 17, todas con su explicación; cada explicación está en una; ningún texto de ayuda queda suelto, tampoco en contenedores; la de una sección va pegada al título; un clic abre el globo con todos sus renglones, el clic que lo cierra no lo reabre y uno después sí; las del ID, el modelo, colocar, la vista previa y la escena cambian con lo que está abierto | **165 de 165** (2026-11-06, con la venda de prueba que solo cura 30 % de una parte: cinco números en el consumible, 18 burbujitas, 150 % rechazado; antes del cambio, 159 de 159, como el 2026-11-02; el 2026-11-01, 138 de 138 en tres corridas seguidas, y antes del buscador, 125) |
| `addons/inventario_objetos/pruebas/prueba_del_creador_juego.tscn`, jugando, en la misma copia, con lo que creó la anterior | La cuerda está en el piso en pilas de 5, 5 y 2, se recoge entera y ocupa 1 × 3. El termo: el host suma 7 de vitalidad de prueba y gasta uno (desde el 2026-11-02: cura 7 de salud y devuelve 3 de estamina; y un veneno creado con el panel quita 30 con la salud completa). La soga: otro jugador la recoge y se la equipa, y acá se ve en su personaje con la posición y el giro del panel. Los dos armarios: 4 × 3, cada uno con su inventario; una cuerda en el primero la ve el otro jugador, y el segundo sigue vacío | **32 de 32** (2026-11-06, con la venda: usada normal no se gasta; sobre una pierna en 50 %, 80 %; en 90 %, 100 % sin pasarse; sobre una entera, rechazada; antes del cambio, 26 de 26, como el 2026-11-02; antes de la salud y la estamina, 23) |
| Las del inventario en esa copia, con lo creado | El laboratorio entero y la de tres procesos: lo creado aparece igual en el host, en A y en B (que entra tarde) | **166 de 166**; **host 18, A 24 y B 7, sin fallas** |
| Revisión con ventana del editor, con fotos | El panel a la vista, oculto y con la ventana chica: la vista 3D mide lo mismo (883 × 472) y el panel entra en su ancho de siempre (260 px; lo de adentro pide 225), también con un nombre larguísimo. La vista previa dibuja el objeto, en el piso y en la mano, y la caja con su alcance. Las miniaturas se hacen en el editor, y cambiar de ítem borra la anterior. Ver "Lo que se arregló mirando las fotos" | Revisadas |
| Revisión con ventana de la miniatura | Arrastrar con el mouse la gira y cuenta como cambio. Al pasar de automático a manual, la imagen no salta: el machete, acostado solo, queda igual. La imagen del panel es la del juego: la misma medida y diferencia 0. Correrla 0,25 mueve lo dibujado un cuarto del ancho exacto. La puerta de frente se ve derecha, también girada 90° en la vista previa. Fotos de Apariencia con y sin modelo | Revisadas |
| Las de siempre, después del cambio en `scripts/inventory` | Modelo, laboratorio, visual y tres procesos | **70 de 70**, **166 de 166**, **7 de 7** (capturas revisadas: el giro de la imagen se ve igual), **host 18, A 24 y B 7**; lo mismo otra vez después de acomodar la miniatura |
| `inv_instant_test.tscn` (2026-11-04), host y cliente en esta PC; el cliente con internet mala | Usar, recoger y soltar sin esperar: en la grilla y en el piso en el mismo cuadro, sin "esperando…"; la salud en el tick siguiente; dos usos seguidos, uno por tick; uno que el host no puede usar vuelve con un aviso; uno que solo predijo tu PC se corrige solo; la muerte y la toxina; soltar desde el menú y desde la mano, y el host lo deja en el mismo lugar; al final, todo igual en el host y en el cliente. Anota las horas del pedido y del cambio en el piso, para medir la demora | **69 de 69** con 120 ms, ±40 ms y 2 % de pérdida, y con 300 ms, ±80 ms y 8 % (2026-11-04) |
| Las del laboratorio | Repetición, mantle y agarre por encima del filo | Iguales que antes: la repetición coincide con la misma huella (`7d3d417dd954d05b`, la de ese día; desde que el estado lleva la salud, la huella completa es otra: `f9b53da25ac45f16` desde el 2026-11-04), el mantle da 50 casos y el agarre, 22 de 22. No usan nada de lo que cambió con el panel: no se volvieron a correr |
| Después de los arreglos de la auditoría de GPT (2026-11-04, a la noche) | `inv_model_test` suma lo que se ve comparado con hacer las acciones una por una (id, cantidad, versión, celda y giro), la respuesta uso por uso con el número dando la vuelta, el input con sus usos y los modelos con scripts. `inv_instant_test` suma el caso de GPT: recoger y usar enseguida, con el pedido de recoger 350 ms tarde. Las dos de red, solas y con 3 s de límite, tienen que salir con error. El resto, igual que antes | **91 de 91**; **83 de 83** con 120 ms y con 300 ms y 8 %; las dos de red salen con error al agotarse el tiempo (antes, bien); **166 de 166**; **host 18, A 24 y B 7**; el panel **159 de 159** y **26 de 26**; repetición `f9b53da25ac45f16`, mantle 50, agarre 22 de 22. Detalle en la sección 13 de `hud_salud_estamina_y_estados.md` |
| Después de la integridad corporal (2026-11-05): el panel a la derecha y el estado del personaje de 165 bytes | Modelo, laboratorio, `inv_instant_test` con 120 ms, ±40 ms y 2 %, y tres procesos. El panel, la caja con prioridad y el clic sobre el panel, en la prueba nueva (`integridad_test.tscn`) | **91 de 91**, **166 de 166**, **83 de 83**, **host 18, A 24 y B 7**: iguales. La prueba nueva, **72 de 72**. Las del panel **Objetos** y la visual no se volvieron a correr: no usan nada de lo que cambió. Detalle en la sección 14 de `hud_salud_estamina_y_estados.md` |
| `inv_hitbox_test.tscn` (nueva, 2026-11-07), el laboratorio entero, jugando solo y en pareja | La hitbox de agarre, con una llave con una caja 1,5 cm más grande, dos marcos de 80 cm con un hueco (uno sin hitbox) y una granada pegada a la llave, puestos en memoria sin tocar archivos: la huella; los rechazos; una forma convexa propia; la Area3D y la capa; dentro de la hitbox sí y 1 cm afuera no, con o sin margen; la granada con margen; el primero sobre la mira; el hueco; paredes, también una que la hitbox cruza; E; lo soltado; primera y tercera persona; el indicador enmarca el modelo. En pareja: el cliente recoge el marco por el hueco y el host lo valida, el host la llave en tercera persona; y un cliente con la hitbox 1 mm distinta no entra | **74 de 74**; en pareja, **host 8 y cliente 6**, sin red simulada y con +200 ms, ±40 ms y 5 % de pérdida; el rechazo, **2 y 2** |
| La hitbox de agarre en el panel (2026-11-07), en una copia | `prueba_del_creador.gd`, 41 comprobaciones nuevas: la sección debajo de **Apariencia** y sus cinco formas, ajustada al modelo (con un modelo de origen lejano y con la caja de color), la vista previa del mismo tamaño y en el mismo lugar que en el juego y su casilla, el milímetro y ±1 cm, los rechazos, guardar, reabrir, que el borrador no toque el original, el aviso al cambiar el tamaño, esfera, cilindro, forma propia y duplicar. `prueba_del_creador_juego`, 6 nuevas: la varilla creada con el panel usa en el juego la hitbox de su `.tres`. Fotos con ventana de la sección y la vista previa | **206 de 206** y **38 de 38**; fotos revisadas. La comprobación "y la zona sigue marcada sin guardar" (de los contenedores) falla a veces, también con el panel de antes: en una corrida de control sin el cambio, una vez sí y otra no |
| Las de siempre, con la hitbox (2026-11-07) | Modelo, laboratorio, indicador (solo y en pareja), usar y recoger en red, tres procesos | **92 de 92**, **175 de 176** (la de las Vendas de tu nivel), **164 de 164** y **8 y 8**, **83 de 83**, **host 18, A 24 y B 7**. En la copia, con lo creado, el laboratorio da lo mismo |
| `inv_alcance_test.tscn` (nueva, 2026-11-11), el laboratorio entero, jugando solo y en pareja | El alcance común (`InvReach`), con dos cajas (una de 3 m y otra girada 37° y escalada) y objetos de prueba puestos en memoria: el torso parado y agachado; un objeto chico, uno largo y las dos cajas, de costado, de punta y desde una esquina, 1 cm adentro y 1 cm afuera, con el selector y el host de acuerdo y la distancia de una cuenta aparte; la esquina vacía de la caja alineada al mundo; un estante, el piso agachado y una plataforma; una hitbox 60 cm más grande que su modelo, también cruzando una pared; una L hueca detrás de una pared en diagonal; la caja con el centro tapado, y con lo cercano tapado y lo visible lejos; la caja abierta sin mirarla; **Interaction Range** en vivo y la huella; la mira en primera y tercera persona hasta la punta lejana. En pareja, el cliente con internet mala: lo que su selector elige lo acepta el host, y lo que no, lo rechaza; la caja abierta sin mirarla se cierra al alejarse. Y los rechazos por la huella (otro alcance, otro modelo) | **141 de 141**; en pareja, **host 7 y cliente 17** (cuatro corridas finales con +200 ms, ±40 ms y 5 %); los rechazos, **2 y 2** cada uno. Las de siempre después del cambio: **193 de 193**, hitbox **100 de 100**, indicador **164 de 164**, modelo **92 de 92**, tres procesos **18, 24 y 7**, usar sin esperar **1 y 83**, abrir caja **85 y 80**, partes **1 y 29**, el panel **231 de 231** y **38 de 38**. Detalle en `problema_alcances_del_inventario.md` |
| El rayo de la mano (2026-11-11 a la noche): `inv_alcance_test.tscn` reescrita, `inv_hitbox_test.tscn` adaptada, y las demás con la dirección de la mano en los pedidos | La regla nueva caso por caso (objetos y cajas en el borde del alcance, parado y agachado, el cubito que asoma 1 cm de un estante, lo que tapa, la hitbox que no ayuda, el hueco del marco, la tercera persona con una cámara que ve por encima de un murito, la cámara de verdad, los pedidos inválidos, la caja abierta desde los ojos, la huella y el costo); en pareja, con internet mala; la hitbox se guarda pero no interviene | Alcance **170 de 170**, en pareja **8 y 24**, rechazos **2 y 2**; hitbox **90 de 90**, en pareja **9 y 7**, rechazo **2 y 2**; laboratorio **190 de 190**; indicador **164 de 164** y **8 y 8**; modelo **92**; estados **129**; integridad **113**; selector **50**; tres procesos **18, 24 y 7**; usar sin esperar **1 y 83**; abrir caja **85 y 80**; partes **29** (tres veces); visual **12 de 12**; el panel **231 de 231** y **38 de 38**; repetición `38989aaf9fd19d18`, mantle 50, agarre 22. Detalle en `problema_objeto_sobre_un_borde.md` |
| El botiquín sobre las partes y las vendas (2026-11-06) | `integridad_test.tscn` con el gesto de agarrar y soltar sobre el panel; `inv_partes_test.tscn` (nueva, host y cliente con +200 ms y con +120 ms); y las del inventario | **103 de 103**; la de red, **32 de 32** en el cliente con las dos latencias, y host y cliente terminan iguales; **91 de 91**, **166 de 166**, **83 de 83**, **host 18, A 24 y B 7**. Las del panel **Objetos** no se volvieron a correr (no cambió el panel). Detalle en la sección 15 de `hud_salud_estamina_y_estados.md` |

En la prueba visual posterior, `inv_visual_test.tscn` dio **10 de 10**, incluidos el ajuste proporcional y el encuadre cuadrado de la barra. La prueba del creador en una copia dio **216 de 217**, incluido guardar y reabrir el encuadre propio. La única falla fue la comprobación preexistente de que la zona quede marcada como pendiente de guardar. En una prueba con render se verificaron los tres anillos y las tres etiquetas, el ajuste fino y la independencia de las dos miniaturas. También probaste a mano el visor de la hitbox, el desplazamiento de cámara y el gizmo inicial.

**Lo que se arregló mirando las fotos (2026-11-01):** en la primera foto, el contenido del panel era más ancho que el panel y se cortaba a la derecha. Por eso los campos van uno abajo del otro, con su nombre arriba, y los números usan el control angosto del Inspector. Los x, y, z van uno por renglón y las listas recortan su texto. El editor nunca se estiró: la vista 3D medía lo mismo con el panel a la vista y oculto.

**Para correrlas** (Claude): `--headless --path . --scene res://scenes/net_lab/inventario/pruebas/inv_model_test.tscn`; la del laboratorio, igual con `--fixed-fps 60`. La de pareja necesita tres procesos en tiempo real: host con `-- --host --port=7781 --test-spawn-at=34,10 --inv-pair=host`; A con `-- --client --address=127.0.0.1 --port=7781 --test-relay=7791 --test-cut-at=28 --test-cut-for=8 --sim-rtt=120 --sim-jitter=40 --sim-loss=2 --inv-pair=a`; y B a los 22 s con `-- --client --address=127.0.0.1 --port=7781 --inv-pair=b`. La de usar, recoger y soltar (`inv_instant_test.tscn`), dos procesos en tiempo real: host con `-- --host --port=7861 --test-spawn-at=34,10 --inv-instant=host` y cliente con `-- --client --address=127.0.0.1 --port=7861 --sim-rtt=120 --sim-jitter=40 --sim-loss=2 --inv-instant=client`; para medir como en tus dos PC, `--sim-rtt=200` en los dos. Las dos de red aceptan `--inv-timeout=SEGUNDOS` para acortar su límite de 100 s: el host solo, con 3, tiene que salir con error. La visual, sin `--headless`, con `-- --out=CARPETA`. La de la hitbox de agarre (`inv_hitbox_test.tscn`), con `--fixed-fps 60`; en pareja, sin él, el host con `-- --host --bind=127.0.0.1 --port=7811 --hitbox-pair=host` y el cliente con `-- --client --address=127.0.0.1 --port=7811 --hitbox-pair=client` (y `--sim-rtt=200 --sim-jitter=40 --sim-loss=5` para la internet mala); el rechazo por la huella, con `--hitbox-pair=host_rechaza` y `--hitbox-pair=client_distinto`. La del alcance (`inv_alcance_test.tscn`, desde el 2026-11-11), con `--fixed-fps 60`; en pareja, sin él, el host con `-- --host --bind=127.0.0.1 --port=7871 --alcance-pair=host` y el cliente con `-- --client --address=127.0.0.1 --port=7871 --sim-rtt=200 --sim-jitter=40 --sim-loss=5 --alcance-pair=client`; los rechazos, con `--alcance-pair=host_rechaza` y `--alcance-pair=client_tuning` o `client_modelo`. Con `--alcance-detalle` escribe cada comprobación.

Las del panel escriben archivos: **solo en una copia del proyecto**. En la copia, importar primero con los plugins apagados; después activar el panel y la prueba con un `plugin.cfg` que diga `script="prueba_del_creador.gd"`, puesto en `addons/inventario_objetos/pruebas/`. En el proyecto de verdad no tiene `plugin.cfg`, así que no aparece en la lista de plugins. Se corre `--headless --editor --path <copia>`, y después, en la misma copia, `--headless --fixed-fps 60 --scene res://addons/inventario_objetos/pruebas/prueba_del_creador_juego.tscn`.

### Lo que no se probó

Esta lista se escribió el 2026-11-01 y se fue sumando. Después, varias cosas sí se probaron: jugaste con el mouse y la cámara en tus pruebas del 2026-10-31 y el 2026-11-01 ("todo funciona correctamente"), y el 2026-11-04 usaste, recogiste y soltaste en las dos PC con +200 ms. Los arreglos de la auditoría también los probaste en las dos PC, el 2026-11-04 a la noche: funcionan. Siguen sin probar el `.exe` exportado y lo creado con el panel en las dos PC.

- **Con el mouse, a mano.** Los clics, el menú y los diálogos se probaron llamando a la interfaz desde las pruebas, y se miraron en capturas, pero nadie hizo clic con el mouse de verdad. Falta tu prueba jugando.
- **Mirar con la cámara de verdad.** La regla se probó dándole la mira armada a mano; que la mira de la cámara arranque a la altura de la cabeza, solo con la cámara quieta. Falta probarlo jugando, en primera y en tercera persona.
- **El clic derecho con internet mala.** La fila de pedidos se probó en un proceso; con los tres procesos, solo el clic que agarra.
- **En las dos PC ni con el `.exe` exportado.** La red se probó con tres procesos en esta PC, con internet simulada.
- **El aviso "difiere en el inventario"** no se provocó a propósito. Es el mismo mecanismo que las otras partes de la huella.
- **El barrido de bordes** (7 min) no se corrió: no usa nada de lo que cambió.
- **Lo creado con el panel, en las dos PC.** Se probó con tres procesos en esta PC, en la copia.
- **Los arreglos de la auditoría de GPT (2026-11-04), con el `.exe`.** En las dos PC los probaste el mismo día y funcionan (sección 13 de `hud_salud_estamina_y_estados.md`).
- **El rayo de la mano con el `.exe`** (2026-11-11 a la noche). Lo probaste en las dos PC el 2026-11-12 y funciona, también un objeto arriba de un muro agarrado desde abajo (commit `32fc044`). Falta la prueba con el `.exe` exportado, a distancia. (La hitbox de agarre ya no interviene.)

### Decisiones chicas y límites (las eligió Claude)

- **Los objetos sueltos no tienen física:** no caen ni ruedan. El host los apoya en el piso y no chocan con nadie. Por eso solo se suelta con piso hasta 1,5 m debajo de los pies: colgado o en el aire, más alto, dice "No hay lugar cerca para soltarlo". La física queda para más adelante (ver "Segunda vuelta").
- **Lo de la caja suelto al piso** cae adelante del personaje, igual que lo del inventario propio; no al lado de la caja.
- **A la barra rápida** solo va lo del inventario propio: es una lista de ids de tus objetos. La miniatura entra centrada en el acceso y conserva su proporción.
- **Un clic derecho fuera de las grillas,** con algo en la mano, no hace nada: no tira una unidad al piso.
- **Con la última unidad dejada con clic derecho,** la pila puede quedar con el id de la primera unidad dejada, no con el de la original: se juntan de a una. Lo que estaba en la barra con el id original se limpia.
- **Si un jugador se va del todo,** su inventario se va con su personaje: no hay guardado. Si vuelve de un corte dentro de los 60 s, lo conserva.
- **Si una caja desaparece,** se cierra para todos y lo que tenía adentro se va con ella. En el laboratorio las cajas no desaparecen: solo pasa en la prueba.
- **Una caja abierta por jugador:** abrir otra cierra la anterior.
- **Un objeto va en un solo acceso de la barra:** asignarlo a otro lo saca del anterior.
- **Un pedido sin respuesta en 10 s** deja de figurar como pendiente.
- **Usos de consumibles sin confirmar** (2026-11-04): hasta 32 en tu PC, y de esos, hasta 8 viajando a la vez. Un uso que espera un pedido que no llega, o un pedido que espera un uso, sigue sin él a los 3 s.
- **Una capacidad nueva no se adelanta** (no se aplica en tu PC antes del host) salvo que diga que sí (`InvAbility.predictable`): sale como pedido y espera al host. Los consumibles sí se adelantan.
- **El alcance** (decidido por vos): desde el 2026-11-11 a la noche, el rayo de la mano, desde los ojos hasta lo primero que toca, con **Interaction Range** (todo en `problema_objeto_sobre_un_borde.md`). Esa mañana, uno solo, **Interaction Range**, desde el torso hasta la parte más cercana de la caja o del modelo del objeto, en 3D. Hasta ese día, el de una caja se medía de los pies al centro de la caja, y el de un objeto, del pecho al objeto. La vista, desde los ojos, que bajan al agacharse: un objeto detrás de un murito bajo se puede agarrar si se lo ve por encima. Desde el 2026-11-11, a una parte del objeto al alcance, con pocos puntos: el detalle y sus límites, en `problema_alcances_del_inventario.md`.
- **El cono de la tercera persona** mide hacia donde mira el cuerpo, que gira hacia donde caminás. Quieto, si giraste la cámara sin caminar, lo de atrás no se elige hasta que des un paso hacia ahí.
- **Dos pilas se juntan** si tienen el mismo tipo y el mismo estado, clave por clave. El nombre o la miniatura no cuentan.
- **El machete equipado** se ve fino, porque el modelo es así. Se ajusta en su `.tres`, en **Hold Offset**, **Hold Rotation** y **Hold Size**.
- **E con una caja abierta (o pedida) la cierra junto con el inventario,** aunque el inventario lo hayas abierto antes con Tab. **Tab, en cambio, cierra solo la caja** (desde el 2026-11-08): el inventario sigue abierto, con la integridad a la derecha. Si cerrás con Tab una caja que el host todavía no contestó, E vuelve a actuar sobre lo que mirás, y aunque el host la abra después, no aparece (auditoría del 2026-11-08, CAJ-01).
- **El panel Objetos busca lugar** sobre el piso de la zona (a 0,4 m o más de su borde) y lejos de lo que ya hay. Para los ítems, en las columnas x −3, −1, 1, −5, 3 y 5, de z −5 a 6, cada 1,2 m (las filas que ya había), a 0,9 m o más de otro ítem o del borde de una caja y a 0,6 m de una pared. Para las cajas, en columnas parecidas, cada 0,5 m, con 0,8 m libres alrededor para pararse. Tiene en cuenta las medidas y el giro de cada caja, y si el nodo **Objetos** está corrido. Las cajas nuevas van en la raíz de la zona, después de las que ya hay: así no cambian los números de las cajas viejas.
- **Colocar no guarda la zona** (la primera versión del panel sí la guardaba): se guarda con Ctrl+S o con **Guardar la zona**. Si se te olvida, Godot la guarda al apretar F6.
- **Editar un contenedor** lo hace el editor (abre su escena, la guarda y vuelve), así se conservan los nodos que le hayas agregado y la herencia de `caja.tscn`. Después vuelve a cargar las escenas abiertas que tienen esas cajas, si no tenían cambios sin guardar; si tenían, no las toca y avisa.
- **Los números del panel** usan el control del Inspector y van de a milésimas (de a décimas los grados): abrir un objeto no redondea lo que tenía guardado. Lo que estuviera fuera de rango se muestra tal cual y lo avisa la validación al guardar.
- **El nombre aparece al instante,** sin esperar, y solo con la mano vacía: con algo en la mano, el cartel de al lado del cursor ya dice qué va a pasar con el clic.
- **Las miniaturas** se hacen la primera vez que se ve cada tipo, de a una. Durante esa fracción de segundo se ve el rectángulo con el nombre. En el editor, la vista previa del panel Objetos las hace con las mismas funciones del juego.
