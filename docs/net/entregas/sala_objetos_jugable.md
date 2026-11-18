# Sala jugable de objetos

1. Extraé el ZIP completo en cada PC con Windows de 64 bits.
2. Abrí `abrir_sala_objetos.cmd`. Podés arrastrarle el ejecutable de Godot 4.7.2, o poner el ejecutable en la misma carpeta con el nombre `godot.exe`. La DLL de la sala viene en el ZIP.
3. En una ventana elegí **Alojar**. La sala muestra las direcciones del anfitrión. En la otra PC ingresá la IP de la red que estén usando (Wi-Fi/LAN o Radmin) y elegí **Conectar**. Para dos ventanas en la misma PC usá `127.0.0.1`. Usá el mismo puerto en las dos (29471 por defecto).
4. El anfitrión ve la sala desde una cámara fija. El invitado mueve al personaje y prueba la caja.

| Invitado | Control |
| --- | --- |
| Caminar y mirar | WASD y mouse |
| Agarrar o soltar | Clic derecho |
| Lanzar | Clic izquierdo con la caja agarrada |
| Acercar o alejar la caja | Rueda |
| Girar la caja | Mantener el botón del medio y mover el mouse |
| Soltar el cursor / volver | Esc / Esc de nuevo |

Probá soltar la caja quieto y caminando de costado. Mirá si en el invitado la caja salta de lugar, cambia de altura o vuelve hacia atrás en el momento de la suelta. La grilla del piso sirve de referencia. Podés alternar quién aloja volviendo al inicio en ambas ventanas.

La escena tiene una caja, suelo, paredes y un obstáculo bajo. El invitado espera la respuesta del anfitrión para agarrar, soltar o lanzar. Mientras sostiene la caja, predice el movimiento de la mano. Esta sala sirve para probar la física y presentación por separado del inventario y del laboratorio principal.

Si el invitado dice «Sin respuesta», comprobá la IP y el puerto y permití la entrada por UDP al ejecutable exacto de Godot en el firewall del anfitrión. Si dice que UDP se abrió pero la escena no inició, comprobá que ambas PC usen el mismo ZIP.

Esta versión hace que la caja sostenida responda antes al mouse del invitado y filtra movimientos mínimos cuando está casi quieta. Probalo caminando de costado, haciendo un giro corto con el mouse y frenando la caja junto a una pared.
