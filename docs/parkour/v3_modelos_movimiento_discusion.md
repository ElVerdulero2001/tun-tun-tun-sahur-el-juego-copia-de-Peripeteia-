# V3 — discusión: pose por tick, trayectoria y modelo híbrido

## Estado

Esto es una propuesta para discutir, no una decisión cerrada ni una autorización de implementación.

## Los dos modelos

### A. Pose por tick

La mecánica calcula en cada tick la pose que busca y se la solicita al motor. El motor aplica el movimiento físico una sola vez, con sus validaciones y colisiones.

Es adecuado para comportamientos continuos y reactivos, como Hanging: el borde puede terminar, cambiar de normal en una esquina o modificarse durante la acción. La mecánica vuelve a evaluar qué pose pedir según el mundo actual.

### B. Trayectoria comprometida

La mecánica entrega un recorrido completo antes de comenzar: posición, orientación y velocidad esperadas durante una progresión temporal. El motor ejecuta y valida ese recorrido por fases.

Es adecuado para acciones cerradas, como Mantle o Vault: antes de iniciar se puede verificar el recorrido, el clearance y el destino. Si algo cambia, el motor aborta o aplica el fallback definido.

## Por qué considerar un híbrido

Usar únicamente pose por tick obligaría a Mantle/Vault a reconstruir e improvisar su recorrido cada frame, aun cuando su trayectoria puede validarse antes de entrar.

Usar únicamente trayectoria comprometida obligaría a Hanging a generar una trayectoria nueva todo el tiempo mientras responde al borde, al shimmy o a una esquina. En la práctica sería pose por tick disfrazada.

El híbrido no combina los dos modelos dentro de un mismo movimiento. Cada submecánica elige uno de los contratos antes de implementarse:

```text
Hanging activo  -> pose por tick
Ladder activo   -> pose por tick (salvo que su diseño posterior indique otra cosa)
Mantle iniciado -> trayectoria comprometida
Vault iniciado  -> trayectoria comprometida
```

Los dos contratos pasan por el mismo motor, que conserva la autoridad física única. El módulo activo conserva la política y el estado de su comportamiento; no obtiene acceso directo al `CharacterBody3D`.

## Límite necesario

El híbrido sólo tiene valor si permanece cerrado. No significa que cada mecánica pueda inventar su forma de mover al player. V3 tendría exactamente dos contratos de movimiento:

1. Pose por tick.
2. Trayectoria comprometida.

Toda nueva submecánica debe declarar cuál usa y justificarlo antes de implementarse. Si ninguna encaja, se abre una decisión de arquitectura en vez de agregar un tercer modo por conveniencia.

## Pregunta para cerrar

¿Se acepta este híbrido de dos contratos como base de V3, o se obliga a todas las mecánicas a usar solamente uno de ellos?
