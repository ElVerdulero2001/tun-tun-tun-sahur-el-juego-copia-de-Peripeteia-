# Estados nativos por ENet y correcciones por NetSync — entrega 13

El recorrido de esta entrega usa dos procesos y los mensajes reales de `NetSync`: el cliente manda inputs/estados afirmados, el host simula al actor y publica snapshots, y `scene_network_bridge.gd` lleva el estado propio recibido al `history_bridge` validado. Los estados del mundo nativo viajan por `authority_channel.gd`. El laboratorio principal todavía no instancia estos componentes.

## Propiedad y orden

Cada escena posee sus nodos: `SimClock`, `NetSync`, `ClientPrediction`, adaptador, registrador, canal y punto de conexión. No hay autoload nuevo. El experimento conserva un actor, una mano, un objeto concedido al cliente y topología/contexto fijos; el host sigue siendo autoridad.

1. La escena crea un adaptador y un registrador frescos como indica el [README local](README.md). Configura el reloj de `NetSync`.
2. Con ENet conectado, crea `authority_channel.gd` **en la misma ruta de nodo** en ambos extremos. Su autoridad de Godot es el servidor 1. Llama `start(scope, peer)` con el ámbito del adaptador y el peer concedido (host) o 1 (cliente). La escena valida antes la concesión, versión/código, conexión y contexto. Los campos de ámbito no autentican al emisor.
3. En el cliente, crea `scene_network_bridge.gd` y llama `start(history, sync, channel, on_other_state, on_base_state)`. Requiere el mismo reloj y un canal vinculado. Los callbacks de otros actores/bases siguen perteneciendo a la escena.
4. Conecta `before_actor_tick(tick)` a `tick_started`, antes de capturar/mover. Consume los tramos de tiempo **recibidos por NetSync**, notifica al registrador antes del replay y pasa el estado propio recibido a `reconcile_actor`. La escena conserva los eventos, consumibles y cambios de época en su callable de paso y sus responsabilidades de sincronizar el margen del reloj. Este ejemplo no implementa todos esos sistemas del laboratorio.
5. El proveedor llama `history.capture_input(input)` también suspendido. La escena sigue usando `ClientPrediction.record` y `NetSync.send_ticks` después del motor.
6. El punto de conexión aplica estados nativos en `tick_finished`, después del adaptador y el registrador. Un estado futuro espera; sin base del actor espera un nuevo estado/corrección. En pausa puede llamarse `after_actor_tick()` entre ticks terminados. Nunca restaura en el proveedor o dentro del replay del actor.
7. El host publica un paquete con `channel.publish(packet)` **después** de simular su tick. Conserva versión, ámbito, revisión, tick, ACK de acciones y snapshot nativo posterior a esas acciones. Se usa la misma API de autoridad de la entrega 11. La revisión es creciente; el tick puede repetirse pero no retroceder.

No se modificaron `NetSync`, su formato de paquetes, `SimClock`, `ActorMotor` ni `ClientPrediction` en esta entrega. El argumento optativo de ClientPrediction de la entrega 12 ya estaba reflejado en el árbol original; sigue con su valor por defecto en `net_lab.gd`.

## Transporte y límites

| Elemento | Límite/comportamiento |
| --- | --- |
| RPC de estados | servidor → cliente concedido; confiable, canal ENet 1 |
| Fragmento | cabecera binaria de 52 bytes + hasta 960 de datos; payload RPC ≤ 1012 bytes |
| Transferencia | hasta 1 050 000 bytes / 1094 fragmentos; una recepción parcial |
| Snapshot dentro del sobre | hasta 1 048 620 bytes; hasta 16 ACK únicos |
| Envío | hasta 8 fragmentos por callback `_process`; un envío en vuelo y un único sobre pendiente reemplazable |
| Control de flujo | el siguiente envío espera el ACK remoto de **transferencia completa**, separado de los ACK físicos del sobre |
| Caducidad | 5 s desde inicio, no renovados por duplicados; el envío vencido detiene el vínculo |
| Recepción pendiente | un único estado completo, el más reciente por revisión/tick |
| Reconexión | nodo nuevo, adaptador nuevo y nueva época de conexión; un canal detenido no se reutiliza |

La cabecera contiene magic, conexión, transferencia, tamaño total, índice/cantidad y SHA-256 del sobre completo. Se verifican remitente/vínculo, dimensiones, duplicados coherentes, SHA y ámbito antes de entregar el sobre al registrador. Un fragmento repetido idéntico es idempotente; uno conflictivo descarta esa transferencia. Fragmentos fuera de orden se rearman; transferencias anteriores no resucitan. No se usa `bytes_to_var` ni se crean objetos desde el wire.

Los RPC guardan sobres; **no restauran mundos nativos dentro del callback de red**. El receptor solo acepta del servidor 1 de su conexión viva. El host no tiene una entrada de snapshot desde invitados. El SHA detecta errores de transferencia y no vuelve seguro un snapshot hostil: los bytes nativos siguen siendo `trusted`, producidos por un host de confianza y con código compatible. No se repite N3.

Son cotas de contenido retenido por la aplicación y del trabajo enviado por callback. Hay copias temporales al serializar/rearmar, buffers de Godot/ENet, metadatos y dos mundos durante la corrección. No equivalen a una cota de RAM del proceso. El tamaño máximo no certifica que todos los equipos/redes lo transfieran antes de la caducidad. No se midió throughput sostenido ni memoria pico en la notebook.

Al cerrarse el canal se descarta el estado pendiente, se invalida la historia y se detiene la predicción del objeto. El dueño de la escena conserva el cierre de sesión y la reconstrucción de nodos/concesiones; este canal no cambia ni reinicia por su cuenta la conexión del actor.

## Pedidos y confirmaciones de acciones

`request_action({id, tick, kind, anchor, impulse})` manda una intención pequeña y confiable del cliente al host. El parser exige el peer concedido, ámbito, tamaños y valores finitos/acotados. No admite snapshots. El host recibe `action_requested` y **debe** validar permisos, alcance, inventario, transición y una tabla idempotente antes de programar la acción. La señal no concede esos permisos.

El driver concede expresamente la única caja/mano al único cliente. Su tabla acotada admite los dos IDs de prueba y su duplicado idéntico; programa en `max(requested_tick, host_tick + 1)` y genera el ACK con el tick realmente aplicado. La suelta solicita un impulso fijo de la fixture. No es el protocolo de inventario general ni una decisión para permisos de objetos reales.

Una acción que el cliente ya encoló antes de suspender conserva su identidad. Una acción nueva durante suspensión sigue devolviendo `not_ready`; el juego todavía tiene que definir su política de interfaz. Las señales de efecto provisional y confirmación conservan la distinción de la entrega 12.

## Reproducir

```powershell
& .\tools\testing\run_object_network_probe.ps1
```

El runner copia fuentes exactas a un proyecto temporal e instala allí la DLL ya compilada. Importa y ejecuta `net_plain` y `net_time`, cada uno con un proceso host y otro cliente por loopback, a ritmo real, sin fixed-fps. Limita cada proceso a 8 s y solo termina los procesos que creó. Guarda hashes, stdout/stderr, resultados y trazas en `tmp/network_probe/`.

`probe_network.gd` utiliza el actor/motor/reloj, ClientPrediction y NetSync reales. El cliente comienza algo adelantado; el reloj de sincronización por ping del laboratorio no se certifica. El host usa `NetSync.input_for`; no fabrica inputs del cliente en paralelo. Una perturbación local de 12 cm obliga a corregir al personaje por un snapshot realmente recibido. El modo `net_time` anuncia tarde por NetSync un tramo pasado. El pedido de suelta se demora 250 ms antes de enviarlo por ENet, para llegar después del tick solicitado, y se reenvía con el mismo ID.

Se compara el hash de poses/velocidades nativas entre procesos en el mismo tick **después de un replay positivo desde un checkpoint posterior a la suelta**, antes del checkpoint final. También se exige igualdad final, correcciones reales del personaje, historial de replay, efectos únicos y confirmaciones únicas. Las pruebas de formato, conflicto, timeout y presión usan un nodo de transporte adicional vinculado a la conexión real, mediante puntos de prueba locales; sus buffers opacos nunca entran al deserializador nativo. Los ACK reales de transferencia sí corren entre los dos procesos.

No se certifican todavía `net_lab.gd` migrado, controles de InvHands, selección/alcance, inventario, múltiples manos, catálogo variable, presentación, notebook o dos PC físicas. El siguiente paso es instalar este recorrido en una escena utilizable del laboratorio, con las concesiones y representación de objetos correspondientes.
