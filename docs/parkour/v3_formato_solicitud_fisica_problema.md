# V3 — Problema abierto: formato de la solicitud física

## Nivel del documento: exploración de contrato técnico

Este documento no define el concepto arquitectónico de V3. Parte de ese concepto para explorar cómo podría representarse técnicamente una intención de movimiento. Ningún formato mencionado aquí queda adoptado hasta que se valide como una decisión de prototipo o implementación.

## 🚨 Nota para Claude: se está explorando, no cerrando el contrato

Velocidad y Destino son ejemplos técnicos bajo análisis; no son un conjunto cerrado adoptado para V3. Restricción sí queda fuera del contrato externo, porque obligaría a la capa física a comprender lógica específica del core.

No se decidió todavía si habrá otros formatos, qué campos tiene cada formato, si incluyen orientación, ni si un formato determina un modo de colisión. Tampoco se debe introducir `move_and_slide`, `move_and_collide`, `slide`, `block` u otra API/enum de Godot como requisito conceptual por analogía con V2.

Si se quisiera agregar, eliminar o fijar un formato, primero debe argumentarse como decisión técnica nueva; no se lo puede deducir de este documento ni de una implementación anterior.

## Precondiciones conceptuales

- Un core no mueve directamente el cuerpo ni el collider del player.
- Una capa física común es la única que aplica movimiento físico real y resuelve colisiones.
- El core que está en ejecución gobierna la intención de su mecánica y emite una solicitud física en cada tick.
- `H0` gobierna el movimiento normal. Cuando otro core entra en ejecución física, `H0` deja de emitir movimiento; sólo un core gobierna el cuerpo por tick.
- Cámara e input no cambian durante ese traspaso: son fuentes compartidas que continúan emitiendo el mismo estado. El core activo decide cuáles consume y cómo los interpreta.
- La simulación tiene prioridad sobre cualquier intención del core.

## Cadena de sucesos: ejemplo Hanging

```text
1. El player corre normalmente: H0 gobierna el movimiento físico.
2. Cámara y controles emiten sus datos normales.
3. Los proveedores leen geometría y estado del mundo.
4. Hanging concluye que existe un candidato válido.
5. El jugador realiza la intención necesaria; Hanging solicita ejecutar.
6. H0 deja de gobernar el movimiento físico; Hanging pasa a gobernarlo.
7. Hanging recibe cámara, input, geometría y estado físico actual.
8. Hanging emite una solicitud a la capa física.
9. La capa física intenta aplicarla, resuelve colisiones y devuelve el resultado real.
10. Hanging lee el resultado y vuelve a emitir su solicitud en el tick siguiente.
```

El problema está exclusivamente en el paso 8.

## Pregunta abierta

¿Qué forma debe tener la solicitud física que un core le entrega a la capa física común en cada tick?

La misma intención de Hanging —mantener al player colgado de un borde— podría expresarse de estas maneras:

- **Velocidad:** “intentá mover el cuerpo con esta velocidad”.
- **Destino:** “intentá llevar el cuerpo hacia este punto de agarre”.

Las restricciones no forman parte del contrato físico externo de V3. Una regla como “mantené las manos en este borde” pertenece a la lógica interna de Hanging; no se le entrega a la capa física para que comprenda qué significa un agarre.

No estamos preguntando quién mueve al player: eso ya está decidido. El core propone; la capa física aplica o rechaza según la simulación.

Necesitamos evaluar qué formato, o combinación mínima de formatos, conserva estas propiedades:

- la capa física permanece neutral y no aprende la lógica de Hanging, Ladder o Mantle;
- cada core conserva el comportamiento exclusivo de su mecánica;
- el movimiento sigue siendo reactivo ante cambios del mundo;
- las colisiones y los fallos físicos tienen una respuesta clara;
- el contrato no obliga a cada core a reinventar infraestructura física.

Todavía no se debe elegir una respuesta por comodidad de implementación ni definir el contrato completo de campos. Primero necesitamos entender los trade-offs arquitectónicos de cada forma de solicitud.
