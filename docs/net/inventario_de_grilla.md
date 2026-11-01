# Inventario de grilla en el laboratorio

Hecho el 2026-10-31 a partir de [`prompt_claude_inventario_grilla.md`](prompt_claude_inventario_grilla.md). Es un sistema nuevo, desde cero: no usa ni toca el inventario anterior (`scripts/player n entities/inventory_v2`, PlayerV2), que sigue en su lugar sin que nada del laboratorio lo nombre.

Lo que decidiste vos antes de empezar:

- **La simulación de internet** pasó a **Alt + 1 a 5**, para dejarle la fila de arriba a la barra rápida.
- **E** recoge y abre cajas. Los empujones del host pasaron a **Y** (inmediato) y **U** (programado); con Shift siguen siendo débiles.

Todo lo demás lo eligió Claude y está anotado en la sección 7, "Decisiones chicas y límites".

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
- **Los cuatro avisos de Godot** (`is_host`, `seq`, `size` y `_text`) eran nombres repetidos en `inv_net.gd` y en `inv_ui.gd`. Ya no aparecen, y apareció uno más en una prueba, también arreglado.

**Para más adelante, sin hacer (lo elegiste así): la física de los objetos sueltos.** Según tus notas:

- Chocan con el entorno, no con el personaje.
- Con el jugador solo interactúan cuando se los arroja o vienen hacia él. Pararse o caminar encima no hace nada. Así se evitan los errores raros de la física (Jolt).
- Al tirarlos, por ahora todos salen con la misma fuerza.

### Tercera vuelta, con tu segunda prueba (2026-10-31)

- **El giro es alrededor del centro de la celda que agarraste**, como en tu dibujo (`capturas/afggggg.png`): no importa en qué parte de la celda hagas clic. Al agarrarlo, el objeto se acomoda para que el cursor quede en el centro de esa celda, y ahí sigue en los cuatro giros. Al dejarlo, esa celda va a la celda que está bajo el cursor.
- **Con la mano vacía, el cursor sobre un objeto muestra su nombre** en un cartelito, en las grillas y en la barra rápida.
- **E también cierra la caja**, junto con el inventario, como Tab. Con el inventario abierto con Tab y sin caja, E no lo cierra: recoge o abre lo que mirás, como siempre. Con la caja abierta, abajo dice "E: cerrar …".

### Cuarta vuelta, con tu tercera prueba (2026-11-01)

- **Sin "recuerdo":** con un objeto en la mano, su lugar de antes queda vacío; antes se veía apagado. También queda vacío mientras lo que dejaste espera al host; en el lugar nuevo se ve el borde amarillo. Si el host lo rechaza, vuelve a aparecer en su lugar. Asignarlo a un acceso de la barra no lo mueve: ahí sigue viéndose.
- **"No hay lugar cerca para soltarlo"** colgado del cable es a propósito, mientras los objetos no tengan física: no caen, así que el host los apoya directo en el piso, y solo busca piso hasta 1,5 m debajo de tus pies, de 0,7 a 1,5 m alrededor tuyo. Colgado o en el aire, más alto que eso, no hay dónde apoyarlo. Con la física, va a caer desde la mano.

---

## 1. Dónde está cada cosa

| Qué | Dónde |
| --- | --- |
| El código del inventario (modelo, red, interfaz, miniaturas) | `scripts/inventory/` |
| La caja reutilizable | `scenes/inventory/caja.tscn` |
| La zona de prueba | `scenes/net_lab/inventario/zona_de_inventario.tscn`, nodo **ZonaDeInventario** de `net_lab.tscn` (en x 37, z 13, pegada al borde este del piso) |
| Los objetos de prueba y su catálogo | `scenes/net_lab/inventario/objetos/*.tres` y `scenes/net_lab/inventario/catalogo_de_prueba.tres` |
| La red y los valores ajustables | nodo **Inventario** de `net_lab.tscn` (script `inv_net.gd`) |
| La interfaz | nodo **Hud → InventarioUI** de `net_lab.tscn` (script `inv_ui.gd`) |
| Las pruebas | `scenes/net_lab/inventario/pruebas/` |

---

## 2. Arquitectura

**Datos, separados:**

- **Definición** (`InvItemDef`, un `.tres` por tipo): nombre, tamaño, si gira, si se apila y hasta cuánto, sus capacidades y su modelo. Es compartida y no se cambia en el juego.
- **Instancia** (`InvStack`): un id estable, el tipo, la cantidad y su estado (por ejemplo `{"carga": 40}`). No sabe dónde está.
- **Colocación** (dentro de `InvGrid`): la celda y el giro de cada id. Es de la grilla, no del objeto.
- **Operaciones** (`InvOps`): mover (también entre grillas), apilar, dividir, sacar y meter lo que se recoge. Cada una valida todo antes de cambiar algo. Se prueban sin escena ni red.
- **Barra, equipo y vitalidad de prueba** (`InvLoadout`): la barra guarda ids, no copias. El objeto sigue ocupando su lugar en la grilla.

**Componentes por entidad:** `InvInventory` es el inventario de una entidad. La caja lo trae en su escena. Al personaje se lo agrega el host cuando aparece (un nodo **Inventario** hijo del actor), así `actor.tscn` no cambió. No hay inventario global, ni Autoload, ni singleton.

**Red** (`InvNet`, el nodo **Inventario**). Usa la misma conexión del laboratorio y pasa por el mismo simulador de red, con mensajes propios:

- El jugador pide con números de pedido (`InvProtocol`): solo números enteros, nunca nodos ni rutas.
- El host los ordena por número, descarta los repetidos (les vuelve a mandar el resultado) y los procesa en fila, uno por uno (`InvAuthority`). Cada pedido se valida y se aplica en el mismo paso.
- Por cada operación sale **un solo paquete por jugador**, con su resultado, sus inventarios, la caja abierta, los objetos del mundo y el equipo. Una transferencia entre dos inventarios llega junta: nunca se ve a medias.
- Los paquetes van numerados y cada máquina los aplica en orden (`InvReplica`), aunque el simulador de red los desordene.
- El jugador del host y "Jugar solo" usan el mismo camino, sin red.

**Presentación local:** la interfaz lee lo que confirmó el host y pide cambios; nunca escribe ese estado. Los objetos sueltos en el mundo y lo equipado se dibujan en cada máquina con lo que cuenta el host. Las miniaturas se hacen en cada máquina y no viajan por red.

**Lo que se deja con clic derecho** sale de a un pedido por vez, porque cada uno necesita la versión que dejó el anterior. Los clics que llegan mientras uno espera quedan en fila, marcados con borde amarillo y "+N". Varios seguidos sobre el mismo lugar van en un solo pedido. Cuando llega la respuesta, el lugar se vuelve a calcular: un clic sobre la unidad recién dejada la suma a esa pila. Si el lugar cambió mientras tanto (por ejemplo, se cerró la caja), ese pedido no sale, y no se adivina otro.

### Quién valida qué (siempre el host)

| Operación | Qué comprueba el host antes de aplicarla |
| --- | --- |
| Mover, girar, transferir | Que el objeto exista con la versión que vio el jugador, que el destino tenga lugar, que el giro sea de 0 a 3 (y 0 si el objeto no gira) y que el jugador pueda tocar las dos grillas: la suya o la caja que tiene abierta y al alcance. El inventario de otro jugador, nunca |
| Apilar | Igual que mover, más: mismo tipo, mismo estado y lugar en la pila de destino. Pasa la cantidad pedida (con clic, toda la pila; con clic derecho, las unidades), hasta llenarla; el resto se queda |
| Dividir | Cantidad entera entre 1 y la cantidad menos 1, y lugar libre para la pila nueva, que recibe un id nuevo |
| Recoger | Que el objeto siga en el mundo, que el pecho del personaje esté a menos de **Pickup Range** (2 m) y que el personaje lo vea desde los ojos, sin una pared en el medio. Primero completa pilas compatibles y después busca lugar libre, siempre en el mismo orden. Si entra solo una parte, el resto queda en el mundo |
| Soltar | Desde el inventario propio o desde la caja que tiene abierta y al alcance. Cantidad válida y un lugar en el piso cerca del personaje, calculado por el host: que se vea desde el pecho, con piso abajo y sin pisar personajes, paredes, cajas ni otro objeto suelto. Si no hay lugar, no se suelta nada |
| Usar, equipar | Que el objeto esté en el inventario propio, que tenga esa capacidad y que se pueda (por ejemplo, con la vitalidad al máximo, la botella no se usa ni se gasta) |
| Barra rápida | Que el acceso exista y que el objeto sea del inventario propio |
| Abrir una caja | Que exista, que los pies del jugador estén a menos de su **Access Range** (2,2 m) del centro y que la vea desde los ojos, sin una pared en el medio. Si se aleja o la caja desaparece, se le cierra (para cerrarse alcanza con alejarse: no hace falta dejar de mirarla) |

**Quién pide** sale siempre de la conexión, nunca del pedido. Un pedido hecho sobre una versión vieja de un objeto (otro lo cambió antes) se rechaza.

**Qué se mira lo elige cada máquina,** como dónde se apunta: el host no sabe hacia dónde mira la cámara. El host vuelve a medir el alcance y la vista desde los ojos, pero no el cono de la tercera persona.

---

## 3. Cómo probarlo

### Solo, en esta PC

1. Abrí Godot. En las pestañas de arriba del visor, elegí **net_lab**.
2. **F6** → **Jugar solo**.
3. Date vuelta hacia la derecha (al este) y caminá unos 30 m: pasando el borde del piso está la **Zona de inventario**, con su cartel, una pared, dos cajas (la grande y el cajón chico) y dos filas de objetos en el piso.
4. Acercate a un objeto y miralo (el centro de la pantalla sobre él): abajo aparece "E: recoger …". Apretá **E**.
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
| **Tab** | Abre y cierra el inventario. El mundo no se pausa: con WASD seguís caminando y con Espacio saltás. El mouse queda libre y la cámara no gira |
| **E** | Recoge el objeto o abre la caja que estás mirando (lo que diga el cartel de abajo), si está al alcance y a la vista. Con una caja abierta, la cierra junto con el inventario |
| **Cursor** sobre un objeto | Con la mano vacía, muestra su nombre. También sobre un acceso de la barra |
| **Clic** en un objeto | Lo agarra: queda en la mano, sin mantener el botón, con el cursor en el centro de la celda donde hiciste clic. Su lugar queda vacío |
| **Clic** con algo en la mano | Lo deja ahí. Verde: entra; celeste: se apila; rojo: no se puede (dice por qué, y lo seguís teniendo). Sobre otra grilla, lo pasa; sobre un acceso de la barra, lo asigna; afuera de los paneles, lo suelta al piso, también si es de la caja. En su propio lugar, lo devuelve |
| **Clic derecho** con algo en la mano | Deja una unidad en una grilla: en un lugar libre, o sumada a una pila igual. Lo demás sigue en la mano; con la última, la mano queda vacía. Sobre su propio lugar no deja nada |
| **R** (con algo en la mano) | Gira 90° en el sentido del reloj, alrededor del centro de la celda por donde lo agarraste, que sigue bajo el cursor. Cuatro veces vuelve a como estaba |
| **Clic derecho** en un objeto | Menú: Usar, Equipar o Desequipar, Inspeccionar, Dividir…, Soltar, Soltar una cantidad… y Quitar del acceso. Lo que no se puede aparece apagado y dice por qué. Soltar anda también en la caja |
| **Clic derecho** en un acceso | Lo vacía |
| **Clic en un acceso y clic en otro** | Los intercambia |
| **1 a 9 y 0** | Usan o equipan lo que tiene ese acceso (la botella sube la vitalidad de prueba; el machete y la linterna se equipan o desequipan) |
| **Esc** | Primero suelta lo que tenés en la mano (vuelve a su lugar) o cierra el diálogo, después el menú y por último el inventario. Con todo cerrado, suelta el mouse como siempre |
| **Alt + 1 a 5** | La simulación de internet (antes, 1 a 5 sin Alt) |
| **Y**, **U** (solo el host) | Empujón inmediato y programado (antes, E y R) |

Lo que está esperando al host se ve con un borde amarillo y dice "esperando…". Mientras tanto ese objeto no se puede volver a agarrar. Lo que dejaste con clic derecho y todavía no salió se marca con borde amarillo y "+N".

### Qué hay en la zona

| Objeto | Tamaño | Para qué |
| --- | --- | --- |
| Botella de agua (2 y 1) | 1 × 2, pilas de 3 | Consumible: sube 25 la **vitalidad de prueba**, un contador que se ve al lado de la barra (de 40 a 100). Con la vitalidad al máximo no se usa ni se gasta |
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

## 4. Crear un objeto

1. En **FileSystem**, clic derecho en `scenes/net_lab/inventario/objetos` → **Create New** → **Resource…** → buscá **InvItemDef** → **Create**. Ponele nombre (por ejemplo `cuerda.tres`) y **Save**.
2. Con el `.tres` seleccionado, en el Inspector:
    - **Id**: un nombre único, sin espacios (`cuerda`). Es lo que viaja por red.
    - **Display Name** y **Description**: lo que se lee en el juego.
    - Grupo **Grilla**: **Size** (ancho y alto en celdas, sin girar) y **Can Rotate**.
    - Grupo **Pila**: **Stackable** y **Max Stack**.
    - Grupo **Capacidades**: en **Abilities**, **Add Element** → **New InvConsumable** (sube la vitalidad de prueba; **Vitality Gain**) o **New InvEquippable** (en la mano: **Hold Offset**, **Hold Rotation** y **Hold Size**). La primera de la lista es la que hace la barra rápida.
    - Grupo **Estado**: **Default State**, por ejemplo `carga: 100`. Dos pilas del mismo tipo se juntan solo si su estado es igual.
    - Grupo **Modelo**: arrastrá un `.glb` desde **FileSystem** a **Model**, o poné una malla en **Mesh** (con **Color**). **World Size** es cuánto mide en el piso el lado más largo.
    - Grupo **Miniatura**: **Thumbnail Rotation** gira el modelo para la foto; **Thumbnail Zoom** lo acerca; **Thumbnail Auto Align** lo acuesta 90° si su lado largo no coincide con el de la huella.
3. Abrí `catalogo_de_prueba.tres` y en **Items** → **Add Element** → arrastrá tu `.tres`. Un objeto que no está en el catálogo no existe para la red.
4. Para que aparezca en el mundo: en `zona_de_inventario.tscn`, clic derecho en **Objetos** → **Add Child Node** → **InvPickupSpawn** → **Create**. En el Inspector, **Item** (tu `.tres`), **Quantity** y, si querés otro estado, **State Override**. Movelo hasta apoyarlo en el piso.
5. **Ctrl+S**. Las dos PC tienen que tener lo mismo, o la notebook no entra ("difiere en el inventario").

La miniatura sale sola del modelo, la primera vez que el objeto se ve en la interfaz. Sin modelo ni malla, se ve un rectángulo de su color con el nombre.

---

## 5. Otra caja, y cambiar las medidas de las grillas

- **Agregar una caja:** en `zona_de_inventario.tscn` (o en cualquier nodo adentro de **ZonaDeInventario**), arrastrá `scenes/inventory/caja.tscn` desde **FileSystem** al árbol. En el Inspector: **Display Name**, **Columns** y **Rows** (su grilla), **Box Size** y **Color** (cómo se ve y choca) y **Access Range**. No hace falta numerarla: se numeran solas por su orden en la escena.
- **La grilla del jugador:** nodo **Inventario** de `net_lab.tscn`, grupo **Grilla del jugador**, **Player Columns** y **Player Rows** (12 × 16).
- **El tamaño de las celdas en pantalla:** nodo **Hud → InventarioUI**, **Cell Size** (40 píxeles). Si la grilla no entra en la pantalla, se achica sola.
- **Los alcances:** nodo **Inventario**, **Pickup Range** (recoger) y **Drop Distance** (a qué distancia adelante cae lo que soltás). El de cada caja, en la caja (**Access Range**).
- **Mirar:** nodo **Inventario**, grupo **Mirar**. **Look Cone Degrees** (75): en tercera persona, cuántos grados a cada lado de hacia donde mira el personaje puede estar lo que se agarra o se abre. **Aim Margin** (0,12 m): cuánto se perdona al apuntar a un objeto suelto, alrededor de su tamaño. Son de cada máquina: no hace falta que las dos PC tengan los mismos.

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

---

## 7. Pruebas

| Prueba | Qué cubre | Resultado (2026-10-31) |
| --- | --- | --- |
| `inv_model_test.tscn` (modelo, sin escena) | Bordes, solapamiento, los cuatro giros (180° ocupa como sin girar; 270°, como 90°; giros de 4 o negativos se rechazan), un objeto que no gira, mover sobre la propia huella, rechazos que no cambian nada, pilas parciales y llenas, apilar solo una cantidad, estado distinto, divisiones inválidas y sin lugar, recogida parcial, soltar, transferir, barra después de cada operación y copias por red mal formadas (también con el giro viejo, verdadero o falso) | **70 de 70** |
| `inv_lab_test.tscn` (el laboratorio entero, un proceso) | Todo lo de arriba por el camino real del host, más: lejos no se recoge ni se abre; soltar contra una pared y encerrado entre paredes; soltar desde la caja; el banquito girado en la caja; transferencia que no entra en el cajón chico; cierre al alejarse; pedido repetido (una sola botella gastada) y pedido viejo; el inventario de otro; dos jugadores sobre la misma pila de la caja y sobre el mismo objeto del mundo (gana uno); desconexión; Esc en orden; WASD con el inventario abierto; W quieto mientras se escribe; cantidad no numérica; un clic agarra y otro deja; en la mano y mientras espera al host, su lugar de antes queda vacío (y asignado a un acceso, no); un clic donde no se puede deja el objeto en la mano; se agarra por el centro de la celda del clic y R lo gira cuatro veces alrededor de ella (la punta agarrada va a la izquierda, arriba, a la derecha y vuelve), y esa celda cae bajo el cursor aunque el cursor esté cerca del borde; el nombre al pasar el cursor (sobre un objeto y sobre un acceso; no sobre una celda vacía, con algo en la mano ni con el menú abierto); E cierra la caja con el inventario, no cierra el inventario abierto con Tab, y apretada antes de que conteste el host la caja no queda abierta; clic derecho: tres seguidos hacen una pila de 3, uno más se suma a esa pila, sobre su propio lugar no deja nada, con la última la mano queda vacía, y el total se conserva; mirar: se elige lo que se mira y no lo de al lado, en tercera persona no lo que está detrás del cuerpo, con una pared en el medio no se elige y el host no deja recoger; dejar sobre la barra, un panel o un menú no suelta al piso; la caja que desaparece con algo suyo en la mano; y que las cantidades se conserven | **166 de 166** (2026-11-01) |
| `inv_pair_test.tscn` con tres procesos en esta PC: host; cliente A con +120 ms, ±40 ms y 2 % de pérdida, que se corta 8 s y vuelve; cliente B, que entra tarde | Estado inicial; A camina, recoge las dos baterías (no se apilan) y abre la caja; carrera por la misma pila (ganó el host; A ve el rechazo); a A se le suelta de la mano la llave cuando el host la mueve; A ve el machete en la mano del host y los tornillos soltados; A vuelve del corte con el mismo inventario y los mismos ids; B ve lo soltado y el machete; al irse, el host no guarda suscripciones ni pedidos; el mundo, igual en los tres; el inventario de A, igual en A y en el host | **Host 18, A 24 y B 7, sin fallas** |
| `inv_visual_test.tscn` (con ventana) | Las 9 miniaturas hechas desde el modelo, con fondo transparente; tres clics derechos dejan 3; el nombre de la batería al pasar el cursor; capturas de la grilla, la caja, el objeto en la mano girado 90°, 180° y 270°, el rojo sobre otro objeto, el clic derecho, el nombre al pasar el cursor, el menú, la inspección, la división y lo equipado | **7 de 7** (y las capturas, revisadas) |
| Las del laboratorio | Repetición, mantle y agarre por encima del filo | Iguales que antes: la repetición coincide con la misma huella (`7d3d417dd954d05b`), el mantle da 50 casos y el agarre, 22 de 22 |

**Para correrlas** (Claude): `--headless --path . --scene res://scenes/net_lab/inventario/pruebas/inv_model_test.tscn`; la del laboratorio, igual con `--fixed-fps 60`. La de pareja necesita tres procesos en tiempo real: host con `-- --host --port=7781 --test-spawn-at=34,10 --inv-pair=host`; A con `-- --client --address=127.0.0.1 --port=7781 --test-relay=7791 --test-cut-at=28 --test-cut-for=8 --sim-rtt=120 --sim-jitter=40 --sim-loss=2 --inv-pair=a`; y B a los 22 s con `-- --client --address=127.0.0.1 --port=7781 --inv-pair=b`. La visual, sin `--headless`, con `-- --out=CARPETA`.

### Lo que no se probó

- **Con el mouse, a mano.** Los clics, el menú y los diálogos se probaron llamando a la interfaz desde las pruebas, y se miraron en capturas, pero nadie hizo clic con el mouse de verdad. Falta tu prueba jugando.
- **Mirar con la cámara de verdad.** La regla se probó dándole la mira armada a mano; que la mira de la cámara arranque a la altura de la cabeza, solo con la cámara quieta. Falta probarlo jugando, en primera y en tercera persona.
- **El clic derecho con internet mala.** La fila de pedidos se probó en un proceso; con los tres procesos, solo el clic que agarra.
- **En las dos PC ni con el `.exe` exportado.** La red se probó con tres procesos en esta PC, con internet simulada.
- **El aviso "difiere en el inventario"** no se provocó a propósito. Es el mismo mecanismo que las otras partes de la huella.
- **El barrido de bordes** (7 min) no se corrió: no usa nada de lo que cambió.

### Decisiones chicas y límites (las eligió Claude)

- **Los objetos sueltos no tienen física:** no caen ni ruedan. El host los apoya en el piso y no chocan con nadie. Por eso solo se suelta con piso hasta 1,5 m debajo de los pies: colgado o en el aire, más alto, dice "No hay lugar cerca para soltarlo". La física queda para más adelante (ver "Segunda vuelta").
- **Lo de la caja suelto al piso** cae adelante del personaje, igual que lo del inventario propio; no al lado de la caja.
- **A la barra rápida** solo va lo del inventario propio: es una lista de ids de tus objetos.
- **Un clic derecho fuera de las grillas,** con algo en la mano, no hace nada: no tira una unidad al piso.
- **Con la última unidad dejada con clic derecho,** la pila puede quedar con el id de la primera unidad dejada, no con el de la original: se juntan de a una. Lo que estaba en la barra con el id original se limpia.
- **Si un jugador se va del todo,** su inventario se va con su personaje: no hay guardado. Si vuelve de un corte dentro de los 60 s, lo conserva.
- **Si una caja desaparece,** se cierra para todos y lo que tenía adentro se va con ella. En el laboratorio las cajas no desaparecen: solo pasa en la prueba.
- **Una caja abierta por jugador:** abrir otra cierra la anterior.
- **Un objeto va en un solo acceso de la barra:** asignarlo a otro lo saca del anterior.
- **Un pedido sin respuesta en 10 s** deja de figurar como pendiente.
- **El alcance de una caja** se mide de los pies al centro de la caja; el de un objeto, del pecho al objeto. La vista, desde los ojos, que bajan al agacharse: un objeto detrás de un murito bajo se puede agarrar si se lo ve por encima.
- **El cono de la tercera persona** mide hacia donde mira el cuerpo, que gira hacia donde caminás. Quieto, si giraste la cámara sin caminar, lo de atrás no se elige hasta que des un paso hacia ahí.
- **Dos pilas se juntan** si tienen el mismo tipo y el mismo estado, clave por clave. El nombre o la miniatura no cuentan.
- **El machete equipado** se ve fino, porque el modelo es así. Se ajusta en su `.tres`, en **Hold Offset**, **Hold Rotation** y **Hold Size**.
- **E con una caja abierta la cierra junto con el inventario,** aunque el inventario lo hayas abierto antes con Tab: hace lo mismo que Tab.
- **El nombre aparece al instante,** sin esperar, y solo con la mano vacía: con algo en la mano, el cartel de al lado del cursor ya dice qué va a pasar con el clic.
- **Las miniaturas** se hacen la primera vez que se ve cada tipo, de a una. Durante esa fracción de segundo se ve el rectángulo con el nombre. En el editor no hay vista previa: solo en el juego.
