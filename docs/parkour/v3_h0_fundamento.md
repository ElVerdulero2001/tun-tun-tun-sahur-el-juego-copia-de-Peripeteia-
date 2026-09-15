# V3 — Fundamento de H0

## Propósito y nivel

Este documento reúne las decisiones **conceptuales** tomadas para `H0`, el core mínimo global del player. No define nodos de Godot, variables, fórmulas, APIs físicas ni valores de ajuste que todavía no estén decididos.

Si hay conflicto con `v3_autoridad_movimiento_propuesta.md`, prevalece ese fundamento general de V3. Este documento detalla H0 dentro de aquellas fronteras.

## Qué es H0

`H0` es el core de locomoción mínima y el gobernador físico por defecto del player. Mientras ningún otro core ejecuta movimiento físico, H0 gobierna el cuerpo a través de la capa física compartida.

Sus capacidades actuales son parte del mismo core, no cores separados:

- movimiento normal en suelo y aire;
- salto base;
- caída;
- agacharse;
- sprint.

H0 no es dueño de la cámara ni de la captura de input. Ambas son fuentes compartidas: H0 consume sus directivas para interpretar la locomoción normal, como lo harán otros cores cuando les toque gobernar.

La cámara no se divide entre una primera y tercera persona separadas: su distancia es continua y puede recorrer posiciones intermedias entre ambas. Cambiar esa distancia —la propuesta actual es usar la ruedita del mouse— no modifica la locomoción de H0: a uno o doce metros de distancia, la referencia de dirección y el movimiento son los mismos.

## Apoyo

Para las reglas de H0, estar apoyado es un hecho físico publicado por la capa común. H0 no agrega por ahora una condición propia de área mínima de soporte: si la capa física informa que el body está en piso, cuenta como apoyo válido para saltar, recuperar control aéreo y terminar una caída.

La forma concreta de obtener ese hecho pertenece a la integración técnica; no altera la regla conceptual de que el soporte se reevalúa en cada tick.

## Orientación híbrida

H0 usa una referencia híbrida, pensada también para tercera persona:

- En tercera persona, si no hay movimiento ni apuntado, la cámara es libre: puede orbitar para observar y no rota el cuerpo del player.
- Al moverse en tercera persona libre, la dirección se interpreta respecto de la cámara horizontal. `W` avanza hacia donde apunta la cámara; `A`, `S` y `D` expresan las demás direcciones respecto de esa misma referencia, sin requerir que la cámara se mueva.
- El cuerpo gira hacia la dirección real de desplazamiento durante esa locomoción libre.
- Al apuntar en tercera persona, cámara y cuerpo quedan acoplados a la mira, como en primera persona. `W`, `A`, `S` y `D` permiten avanzar, desplazarse lateralmente o retroceder respecto de esa mira, sin que el cuerpo deje de mirar la dirección apuntada.
- En primera persona se aplica esa misma referencia acoplada de cámara y cuerpo.

Esto no define cómo se calculan los vectores ni la velocidad concreta de giro. Define qué referencia tiene prioridad según el contexto.

El cambio de distancia o perspectiva no obliga a H0 a rotar el body. Sólo cuando H0 esté gobernando y sus reglas actuales permitan una alineación de orientación puede producirse; si la orientación está bloqueada por el escenario o por el core que gobierna, la cámara puede cambiar sin alterar el body. Toda alineación permitida debe respetar el soporte físico actual y no provocar una caída artificial.

## Suelo: acciones básicas sin combinaciones especiales

Mientras H0 está apoyado, sus submecánicas no fabrican maniobras especiales por combinar inputs.

- Sprint es una submecánica de H0: por ahora sólo aumenta la velocidad de locomoción normal y no toma el gobierno como core separado.
- Si se activa agacharse, H0 pasa a la postura y velocidad de agachado.
- Si el player venía en sprint y se agacha, deja la velocidad de sprint y usa la velocidad de agachado.

Agacharse es un estado persistente: una pulsación de su control alterna entre agachado y parado; no necesita mantenerse presionado. Esto es distinto de mantener `Ctrl`, que funciona como una directiva temporal para bloquear la entrada de los cores que declaren consumirla.

No aparece un deslizamiento, embestida u otra maniobra especial sólo por apretar sprint y agacharse. Si una de esas mecánicas existe en el futuro, deberá definirse explícitamente con sus propias reglas.

Esta regla de velocidad es de suelo. En el aire, agacharse reduce inmediatamente el tamaño físico del player, no sólo su animación. Así puede atravesar huecos bajos mientras salta o cae.

`Agachado` sigue siendo una sola postura. Lo que cambia con el hecho físico `en piso` es desde qué referencia se encoge la cápsula:

- En piso, los pies se mantienen apoyados; baja la parte superior de la cápsula y la cámara acompaña hacia abajo.
- En aire, el centro de la cápsula y la cámara se mantienen en su referencia normal; al reducir la altura, los pies suben.

No son dos estados de agachado. Son dos formas de colocar la misma cápsula reducida según exista o no soporte físico.

Cuando el player pide volver a pararse, H0 debe comprobar primero que haya espacio físico mínimo para recuperar su tamaño normal. Si no lo hay —por ejemplo, por un techo bajo—, la orden de pararse se rechaza y H0 conserva agachado como postura deseada. Salir luego de ese espacio no lo para automáticamente: el player debe pedir volver a pararse mediante una nueva pulsación. Así una salida de cobertura baja no expone al player por una orden vieja.

Sprint está activo por defecto mientras se mantiene su control presionado. La configuración puede cambiarlo a modo alternado: una pulsación lo activa y la siguiente lo desactiva. H0 recibe solamente el hecho `sprint activo/inactivo`, sin necesitar conocer la preferencia de controles que lo produjo.

## Aire, salto y caída

### Control aéreo

Al entrar al aire, H0 concede control aéreo total durante una ventana temporal. Mientras esa ventana esté vigente, el jugador puede corregir libremente la trayectoria.

Cuando termina, H0 conserva la trayectoria resultante y deja de aceptar correcciones aéreas hasta que el player vuelva a estar apoyado. La duración de la ventana y los parámetros físicos concretos siguen abiertos.

### Salto base

El salto base sólo puede ejecutarse si el player está realmente apoyado. Mantener presionado el control de salto expresa una intención continua: mientras el player siga habilitado para saltar, H0 vuelve a solicitarlo cada vez que recupera el apoyo.

- No existe tolerancia después de abandonar un borde: haber estado en suelo antes no habilita un salto en el aire.
- No existe un buffer de salto basado en tiempo. Soltar el control elimina la intención de saltar; mantenerlo permite repetir saltos al aterrizar.

Una vez que el player perdió el apoyo sin haber saltado, H0 lo trata como caída.

Si la distancia de caída recorrida supera el umbral que el sistema de daño considere lesivo, se aplica una condición de penalización que impide saltar. No vence por un temporizador: persiste hasta que el sistema que resuelva el daño, recuperación o muerte la retire. De esa forma, mantener Espacio durante una caída larga no fabrica un salto al aterrizar.

H0 no calcula el daño. Sólo consume el hecho público `puede saltar / salto penalizado` que le entregue el sistema externo correspondiente. El umbral de distancia y la forma de recuperación siguen abiertos.

H0 también permite saltar estando agachado. El salto conserva el tamaño físico reducido, pero tiene una penalización respecto del salto de pie. La magnitud concreta de esa penalización queda para ajuste posterior.

### Daño de caída actual

Hasta que exista una habilidad futura que cambie esta regla, el daño se determina por la distancia recorrida durante la caída. Como regla vigente de gameplay, una caída de más de `15` mata al player.

El cálculo exacto del daño entre cero y ese límite, la unidad definitiva y la futura habilidad no se definen aquí.

## Frontera con otros cores

H0 no emite movimiento físico cuando otro core gobierna. La ruta sigue siendo obligatoria:

```text
H0 → otro core → H0
```

No hay transferencias directas entre cores. Las reglas anteriores sólo describen H0 cuando recupera o conserva el gobierno.

## Todavía abierto

- Duración concreta del control aéreo total y sus parámetros físicos.
- Curva concreta de daño de caída y la habilidad futura que podría reemplazarla.
- Valores de velocidad, aceleración, giro, penalización de salto agachado y collider.
- Representación técnica de las directivas que H0 envía a la capa física.
