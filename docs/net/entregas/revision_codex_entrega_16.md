# Entrega 17 · sala jugable de objetos

Claude validó el registro del host de la entrega 16 con 0 fallas y 0 casos insuficientes en la corrida final. Su informe e instrumentos se incorporaron por avance directo hasta `9a3024a`. También detectó que un cierre dentro del tick podía cancelar el registro de una suelta y dejarla encolada en el adaptador.

El cierre ahora retira del adaptador la acción que todavía no ejecutó. La identidad del pedido permanece reservada. Si el paso nativo ya terminó y el cuadro grabado contiene esa acción, el registro conserva el resultado aplicado. La escena acota los pedidos a 15 ticks por delante del anfitrión y mantiene un pedido local pendiente por vez, para que una solicitud futura quede cerca del momento en que el jugador la hizo.

La sala nueva arranca como proyecto Godot separado. El anfitrión ve la habitación desde una cámara fija y el invitado usa el movimiento del personaje, el mouse y los botones de la mano. El suelo, las paredes y el obstáculo usan las mismas dimensiones en Jolt y en el mundo nativo. Un único nodo dibuja la caja a partir de las poses del adaptador, con interpolación de presentación. Los cuerpos de objetos solo existen en el mundo nativo.

El anfitrión comprueba la distancia, la línea libre hasta el punto de agarre y el límite del impulso. El invitado espera el resultado del host para los cambios de mano. Una vez que recibe un estado con la caja agarrada, el invitado la mueve mediante predicción y reconciliación. El resultado fiable de la acción se muestra en la sala. Si fue aplicada, se espera además que llegue un estado físico que la incluya antes de admitir otra acción local. Esta es una política de la escena experimental y el alcance de juego se limita a una caja y un invitado.

## Verificación

- Cuatro parejas de procesos Godot conectadas por ENet en una PC. En cada pareja el invitado agarró, giró, caminó, soltó en movimiento, volvió a agarrar y lanzó. Ambos lados registraron cuatro acciones aplicadas. Los logs incluyen desplazamiento, giro y velocidad de salida del invitado. Evidencia en `implementacion/tmp/lifecycle_probe/20261117_225205_75e527`.
- Pasaron también `host_journal`, `net_journal`, `net_close` y `action_window` en la misma corrida.
- En los instrumentos existentes de Claude pasaron `journal_inflight`, `journal_capture` y `journal_close`. `journal_inflight` reportó cancelación sin confirmación, cero efectos y la caja todavía agarrada. Evidencia en `implementacion/tmp/validacion_objetos/entrega_16/run16_20261117_195128`.
- Se conservan las corridas anteriores. La primera quedó esperando un segundo agarre porque la caja se fue de alcance después de soltarla. El guion ahora camina para acercarse. La segunda midió el giro al último tick de la maniobra y una corrida no llegó al valor esperado. La corrida final usa un giro de mouse más amplio y registra el giro durante todo el tramo de movimiento.

```powershell
& .\tools\testing\run_object_lifecycle_probe.ps1 -Modes 'net_play_room,host_journal,net_journal'
```

La prueba visual entre dos PC se documenta al final de este informe. El laboratorio principal sigue como escena aparte. La guía del paquete explica cómo abrir la sala y los controles. [sala_objetos_jugable.md](sala_objetos_jugable.md)

## Ajuste de conexión de la sala

El anfitrión muestra las IPv4 disponibles. El invitado informa si se vence la espera sin respuesta UDP o si el transporte abrió y luego falló el inicio de la escena. El campo de IP comienza vacío para que la dirección de la propia máquina no se use por accidente al conectar desde otra PC. Se corrigieron los avisos del editor por los nombres locales de la posición y la huella del paquete.

La prueba automatizada completó el circuito de la caja en dos procesos de una misma PC usando localhost y sus direcciones de Wi-Fi y Radmin. Se verificó la escucha en todas las interfaces IPv4. La ruta entre dos equipos se comprobó en la sesión manual descrita abajo.

## Prueba manual entre dos PC · 18 de noviembre de 2026

En la grabación del invitado se ve el ciclo de agarrar, mover, soltar y lanzar la caja con los controles de la sala. El jugador confirmó que en el anfitrión vio el mismo comportamiento. La evidencia grabada corresponde a la perspectiva del invitado.

- Cerca de 0:06, la caja se suelta mientras el personaje se mueve junto al obstáculo. La caja sigue desplazándose, gira y se asienta en el suelo. En la secuencia revisada no se aprecia un salto brusco hacia atrás.
- Cerca de 0:41, el invitado muestra brevemente «Recuperando el estado de la caja» y vuelve a «Caja libre» en el cuadro siguiente revisado. Después vuelve a agarrar. La causa de la recuperación y su duración exacta quedan sin medir.
- Cerca de 0:48, la caja sale hacia arriba, cae y rueda junto a la pared. El invitado vuelve a agarrarla y continúa moviéndola.

Esta prueba valida el funcionamiento y la coincidencia visual reportada en una sesión real. La grabación del invitado no permite medir latencia ni comparar las dos vistas cuadro a cuadro. Video local: `Documents/otro proyecto bobo/capturas/2026-11-18 08-53-39.mp4`.

## Respuesta visual de la caja en mano

El retraso acumula la respuesta del controlador de Rapier y el suavizado del dibujo. Mientras sostiene la caja, el invitado anticipa el dibujo a partir de la velocidad simulada y el movimiento del mouse pendiente del próximo tick. El adelanto queda acotado a 18 cm y 10 grados, y se descarta si encuentra geometría en el recorrido. Con la caja casi quieta, se filtran variaciones de hasta unos 8 mm y 0,6 grados. El cálculo físico que usa el anfitrión para soltar y lanzar sigue tomando la pose y la velocidad del cuerpo.

Cuatro corridas de red en una PC completaron agarre, giro, traslado, suelta y lanzamiento. Una prueba dirigida verificó respuesta antes del próximo tick al mover el mouse, estabilidad frente a una variación quieta de 4 mm, límite de pose contra la pared y vuelta al dibujo habitual al soltar. Queda medir la sensación y reproducir el temblor reportado en las dos PC. La sala registra el motivo cuando suspende la predicción para recuperar un estado.

## Seguimiento físico de la caja después del video del invitado

En la grabación local `Documents/otro proyecto bobo/capturas/2026-11-18 09-34-02.mp4`, la mira cambia de dirección y la caja queda fuera del cuadro mientras sigue agarrada. El adelanto del dibujo anterior era insuficiente ante esos giros. La sala activa en Rapier un controlador físico más rápido para el cuerpo sostenido, tanto en el anfitrión como en la predicción del invitado. La caja sigue moviéndose por velocidad y conserva las colisiones. Al soltar, el cuerpo hereda como máximo la velocidad lineal y angular que permitía el controlador anterior, y un lanzamiento explícito conserva su impulso. Se redujo el adelanto visual del invitado para acompañar la nueva respuesta física.

Una prueba a 60 Hz desplazó el objetivo 2,5 m y lo giró 90°. El cuerpo tardó 6 ticks frente a 18 con la mano anterior en quedar a menos de 15 cm y 0,15 rad del objetivo. Pasaron el ensayo de pared, el límite al soltar, la restauración y repetición con el mismo perfil, y el rechazo de un estado de otro perfil. El controlador anterior sigue siendo el predeterminado de los demás ensayos. Cuatro parejas anfitrión/invitado y el ensayo del registro de acciones pasaron con la nueva compilación. Falta repetir la sensación del giro en las dos PC.
