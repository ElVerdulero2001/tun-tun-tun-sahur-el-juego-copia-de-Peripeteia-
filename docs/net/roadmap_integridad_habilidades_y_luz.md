# Roadmap del laboratorio: integridad, habilidades y luz

Decisiones y propuestas del 2026-11-05 para `net-lab`. Para el comportamiento actual, ver la [guía del laboratorio](guia_del_laboratorio.md).

| Punto | Estado |
| --- | --- |
| 1. Integridad corporal, luz naranja, caídas y muerte | **Implementado el 2026-11-05, pendiente de tu prueba manual.** Detalle, valores, pruebas y la lista para probar a mano: sección 14 de [`hud_salud_estamina_y_estados.md`](hud_salud_estamina_y_estados.md#14-integridad-corporal-luz-naranja-daño-de-caída-y-muerte-2026-11-05). **Seguido el 2026-11-06** con el botiquín sobre una parte del cuerpo y las Vendas, también pendiente de tu prueba: sección 15 del mismo documento. **A la noche**, el panel y la curación de partes sin esperar al host: sección 16 |
| 2. Selector radial de habilidades | Pendiente |
| 3. Termómetro de luz | Pendiente |

## 1. Integridad corporal, luz naranja, caídas y muerte

**Implementado el 2026-11-05, pendiente de tu prueba manual.** Lo de abajo es el pedido tal como estaba; cómo quedó, en la sección 14 de `hud_salud_estamina_y_estados.md`. En resumen:

- **Lo que decidiste al pedirlo** (reglas provisorias del laboratorio): el daño de integridad de una caída se reparte por igual entre las dos piernas, y cada una conserva su valor; por ahora las lesiones solo se ven en el panel y en la luz (no cambian el movimiento); el botiquín cura la salud general y no la integridad; la muerte de prueba devuelve las seis partes al 100 %. La luz se prende con cualquier parte por debajo del 100 %. El panel muestra directamente la silueta, y la caja abierta tiene prioridad en ese lugar.
- **Los valores iniciales** (nodo **Tuning**, grupo **Daño de caída**): **Fall Safe Speed** 10 m/s, **Fall Lethal Speed** 13 m/s y **Fall Leg Damage** 150. Un salto con el súper llega al piso a 7,2 m/s.
- **En la torre de parkour**, tres tablas: verde a 4 m (segura), amarilla a 7 m (lastima la salud y las piernas) y roja a 9,5 m (letal).
- **El 2026-11-06, el botiquín sobre una parte** (pedido tuyo): con Tab, un clic agarra el botiquín y otro lo suelta sobre una parte dañada del panel; esa parte vuelve al 100 % y se gasta uno, sin tocar la salud ni las otras partes (también con la salud completa). Sobre una parte sana o entre dos partes, sigue en la mano y no se gasta; nunca va al piso. Lo valida el host, que cura y gasta juntos. Usado normal, sigue curando 50 de salud. La capacidad va en los datos del consumible (**Part Repair**: 100 deja la parte entera; menos, la sube eso); desde la tarde se pone en el panel Objetos (**Cura una parte del cuerpo**). **Las Vendas** curan 25, la mitad que el botiquín, y no curan partes; hay una en la zona de inventario.

### Panel de integridad

- **Tab** abre la interfaz del jugador con el inventario a la izquierda. A la derecha irá un menú de secciones del jugador, incluida **Integridad corporal**. Para el prototipo, mostrar directamente la integridad en el panel derecho. Si se abre una caja, la propuesta es darle prioridad a su grilla en ese panel para poder transferir objetos.
- Dibujar una silueta esquemática con seis zonas independientes: cabeza, torso, brazo izquierdo, brazo derecho, pierna izquierda y pierna derecha. Cada una muestra la integridad restante como porcentaje, por ejemplo `72 %`. A integridad completa se ve verde y se va tornando roja al degradarse. El porcentaje se actualiza en vivo y permite leer el estado sin depender del color.
- La integridad es independiente de la salud general. El panel muestra los valores del jugador local a partir del estado confirmado por el host. *(2026-11-06 a la noche, pedido tuyo después de probar en red: el panel llegaba tarde con latencia alta. Ahora muestra lo que calcula tu PC, como la aguja de la salud; sección 16 de `hud_salud_estamina_y_estados.md`.)* La luz naranja del medidor de salud queda reservada para avisar de lesiones. Para la primera prueba se propone encenderla si al menos una zona está por debajo del 100 %.

### Daño de caída y animación de muerte

- Probar primero tres resultados en la torre del laboratorio: aterrizaje seguro, impacto que daña la salud y las piernas, e impacto letal. Usar umbrales ajustables en `Tuning` y la velocidad contra la superficie justo antes del contacto, teniendo en cuenta las plataformas móviles.
- La caída letal y la cápsula letal deben pasar por el mismo flujo de muerte. Para el prototipo se propone una caída breve de cámara en primera persona y un desplome visual para el compañero, una vez por muerte. Se parte del flujo de muerte de prueba actual, que recupera la salud en el lugar.
- **Por decidir:** cómo se reparte el daño de una caída entre ambas piernas, qué efectos tienen las lesiones sobre el movimiento y qué recupera la integridad, incluidos el botiquín y la muerte. *(2026-11-05: para el prototipo lo decidiste al pedir la implementación, como reglas provisorias: arriba, en el resumen. Lo definitivo sigue por decidir.)*
- **Prueba de cierre:** repetir las tres caídas como cliente con latencia simulada y comprobar que el daño se aplica una vez, host y cliente coinciden, el panel y la luz reflejan la lesión y la animación aparece una vez. Cubrir un salto normal con el súper, un agarre antes de tocar el suelo y una plataforma móvil.

## 2. Selector radial de habilidades

- **Mantener Q** abre el selector. Tiene dos sectores, con un sprite para **velocidad y salto** y otro para **cámara lenta**. Mientras está abierto, el movimiento del mouse orienta el indicador radial y deja de girar la cámara. El mundo sigue corriendo.
- El indicador sale del centro y resalta el sector según la dirección del mouse, incluso fuera del círculo. La zona muerta central evita que una pulsación sin movimiento seleccione algo.
- **Soltar Q** confirma y cierra el selector. Si hay un sector resaltado, prende o apaga esa habilidad en el momento de confirmar, mediante el control de estados existente. Si se suelta en el centro, cierra sin cambiar ningún estado.
- Las habilidades se alternan de forma independiente. Cada estado conserva su costo y las reglas de agotamiento. La cámara lenta afecta al mundo mientras alguien la pida y cada jugador paga su propio pedido. La confirmación con Q respeta la sincronización actual en red.
- Q hoy alterna la adopción de movimiento del host. Al implementar el radial, reasignar ese atajo de depuración y comprobar que el selector funciona para host y cliente, sin interferir con el inventario ni la barra rápida.
- **Prueba de cierre:** desde el cliente, prender ambas habilidades y apagar solo velocidad y salto. La cámara lenta debe seguir activa. Mantener y soltar Q sin mover el mouse debe dejar los estados intactos.

## 3. Termómetro de luz

- Conectar el termómetro del HUD a la exposición a la luz del personaje. Se propone **0** para oscuridad y **100** para máxima exposición.
- Probar un lugar iluminado, una zona de sombra bajo techo y un cuarto oscuro. La lectura debe distinguir los tres y variar con suavidad al cruzar el borde de una sombra.
- **Por decidir:** cómo calcular la exposición. Si la lectura pasa a influir en el sigilo o las habilidades, el host debe poder determinar el valor que usa la simulación.
