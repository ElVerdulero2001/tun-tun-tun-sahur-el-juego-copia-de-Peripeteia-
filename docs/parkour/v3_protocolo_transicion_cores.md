# Parkour V3 — protocolo de transición entre cores

> **Estado:** propuesta para reemplazar la comunicación directa actual. No implementada.
>
> Mantiene V3: H0 es el core por defecto, un solo core gobierna el movimiento físico y todo core vuelve a H0. No crea un bus de eventos, secuelas ni prioridades entre movimientos.

---

## 1. Problema que se reemplaza

Hoy la comunicación está repartida entre referencias directas y efectos laterales:

- `V3HangingCore` guarda referencias a `H0Core` y `V3PhysicsBody`.
- Hanging pausa/reactiva H0 llamando `set_locomotion_suspended()`.
- Hanging manda `submit_launch()` o `submit_pose_snap()` al body.
- H0, Body, input y sondas corren cada uno en su propio `_physics_process`, por lo que el orden de nodos cambia cuándo se ve o aplica una decisión.

No hay una transición como objeto: hay llamadas sueltas. Por eso H0 no recibe formalmente el contexto con que debe retomar y ningún sitio posee la secuencia completa de un tick.

---

## 2. Qué significa “comunicación” en V3

Los cores **no se mandan mensajes entre sí**. No hay señales globales, grupos, event bus ni llamadas `Hanging → H0`.

Cada core recibe una vista de solo lectura del tick y devuelve una decisión tipada. El host del player es el único que la enruta.

```text
Input + hechos + observaciones
            ↓
      core que gobierna
            ↓ devuelve decisión
       Host del player
       ├─ entrega una intención al Body
       └─ si hay salida, activa H0 y le entrega datos de reentrada
            ↓
     V3PhysicsBody aplica una única intención
```

El host no interpreta bordes, no calcula Hanging, no decide velocidades y no sabe cómo funciona Ladder. Sólo mantiene cuál core está activo y aplica reglas mecánicas de entrega.

El host debe vivir en el nodo raíz existente del player; no se crea un autoload ni un controlador global. En el laboratorio actual puede ser `PlayerH0Lab`; en la escena final, el nodo raíz real del player.

---

## 3. Interfaces mínimas

### 3.1 Contexto de lectura

Todos los cores reciben el mismo contexto inmutable por tick:

```gdscript
class_name V3TickContext

var delta: float
var input: V3InputFrame
var facts: V3Hechos
var observations: V3Observations
```

- `V3InputFrame` contiene input capturado una vez al inicio del tick.
- `V3Hechos` contiene el resultado físico del tick anterior.
- `V3Observations` contiene lecturas neutrales de sondas ya actualizadas.

Ningún core puede cambiar estos objetos; una intención de input o un hecho físico no es un mensaje privado entre cores.

### 3.2 Decisión de un core

Un core sólo puede devolver una de estas dos respuestas:

```gdscript
class_name V3CoreDecision

enum Kind { CONTINUE, EXIT_TO_H0 }

var kind: Kind
var motion: V3MotionIntent  # obligatorio en CONTINUE
var exit: V3ExitToH0        # obligatorio en EXIT_TO_H0
```

`CONTINUE` significa que el mismo core sigue gobernando y entrega una única intención física para este tick.

`EXIT_TO_H0` significa que el core ya terminó. No puede decidir cuál será el siguiente core ni volver a ejecutar durante ese tick.

### 3.3 Intención física

`V3MotionIntent` formaliza las operaciones que el body ya necesita sin inventar mezclas ni prioridades de gameplay:

```gdscript
class_name V3MotionIntent

enum Kind { VELOCITY, SNAP_POSE, HOLD_POSE }

var kind: Kind
var horizontal: Vector3     # VELOCITY
var request_jump: bool      # VELOCITY
var request_crouch: bool    # VELOCITY
var pose: Transform3D       # SNAP_POSE / HOLD_POSE
```

Por tick el host entrega exactamente una intención al body. `HOLD_POSE` sustituirá el snap por tick de Hanging; su barrido y respuesta de colisión se validan en el laboratorio, no se inventan en este protocolo.

### 3.4 Salida hacia H0

La comunicación entre una salida y H0 es una estructura dirigida al host, no una llamada al nodo H0:

```gdscript
class_name V3ExitToH0

var reason: StringName
var has_launch := false
var launch_velocity := Vector3.ZERO
var air_mode: H0Core.AirMode = H0Core.AirMode.NORMAL
```

Por ahora `air_mode` tiene sólo `NORMAL` y `PRESERVE_MOMENTUM`. Duración y aceleración siguen configuradas y ejecutadas por H0, según `v3_reentrada_h0_decisiones.md`.

No se agregan referencias a nodos, callbacks, listas de efectos ni nombres de mecánicas. `reason` es diagnóstico: H0 no ramifica comportamiento según él.

---

## 4. Protocolo de tick

El host es el único nodo participante que implementa `_physics_process`. Input, sondas, H0, cores y body exponen métodos llamados por él en este orden:

```text
1. input.capture()                         → V3InputFrame
2. body.facts()                            → V3Hechos (resultado N-1)
3. probes.observe(facts)                   → V3Observations
4. active_core.step(context)               → V3CoreDecision
5. host routea la decisión:
   - CONTINUE: entrega motion al body
   - EXIT_TO_H0:
       a. H0.resume_from_core(exit.air_mode)
       b. active_core = H0
       c. H0.step(context) entrega la intención continua del tick
       d. si exit.has_launch, la entrega como efecto único al body
6. body.apply(intent, launch opcional)     → resultado físico N
7. debug registra transición, intent y resultado
```

Una salida no habilita que otro core entre directamente. Si Hanging devuelve H0 en N, un nuevo candidato se evalúa desde H0 en el próximo punto de entrada permitido por V3. La regla de cuánto puede durar H0 antes de una nueva entrada sigue abierta en el fundamento de V3; este protocolo no la resuelve por accidente.

### Launch y reloj de reentrada

Si `exit.has_launch`, el body aplica el launch en el mismo tick y descarta la intención continua de H0 para física. H0 queda activo y armado, pero el tiempo de `PRESERVE_MOMENTUM` **no decrece hasta el primer tick en que su horizontal puede aplicarse después del launch**. Así los 0.75 s son tiempo de control real, no tiempo durante el que el launch reemplazó su salida.

El body publica el resultado del launch en `V3Hechos` del tick siguiente. H0 comienza el modo desde la velocidad física real, no desde una velocidad estimada por Hanging.

---

## 5. Entradas a cores

Mientras H0 gobierna, el host pide candidatos a los cores que no están activos:

```gdscript
func can_enter(context: V3TickContext) -> V3EntryCandidate
func begin(context: V3TickContext, candidate: V3EntryCandidate) -> V3MotionIntent
```

El core sólo publica un candidato o explica por qué no puede entrar. El host aplica la política de selección que V3 ya defina. Al conceder la entrada:

1. cambia `active_core`;
2. llama `begin()` del core elegido;
3. entrega su intención inicial —por ejemplo `SNAP_POSE`— al body;
4. el core recibe el resultado de aceptación/rechazo en `V3Hechos` del tick siguiente y decide continuar o salir a H0.

El host no adivina qué significa una candidata ni por qué falló un snap.

---

## 6. Reglas obligatorias

1. Sólo el host conoce referencias a H0, cores y body.
2. Un core no llama métodos de otro core ni del body.
3. Sólo el host entrega una intención al body; el body sigue siendo el único escritor de transform y velocidad.
4. Todo core termina exclusivamente con `EXIT_TO_H0`.
5. Una decisión tiene un destino único: continuar o volver a H0.
6. Input, hechos y observaciones son lectura; las decisiones son el único canal de salida de un core.
7. El host no contiene semántica de parkour ni una lista de reglas por core.

---

## 7. Qué no se agrega

- Ningún event bus, signal global, grupo ni singleton.
- Ningún sistema de prioridades entre movimientos.
- Ninguna secuela ni composición de `horizontal` de dos fuentes.
- Ninguna transferencia directa `Hanging → Ladder`.
- Ningún payload extensible de perfiles, callbacks o Resources ajenos en H0.
- Ninguna máquina de estados separada de los cores: `active_core` es el estado de ejecución que V3 ya tiene conceptualmente.

Si un futuro core necesita más que `air_mode`, primero se decide si es una capacidad genérica de H0 o una fase que debe seguir dentro de ese core. No se agrega un canal de comunicación genérico para “por si acaso”.

---

## 8. Migración mínima desde el laboratorio actual

1. Crear los tipos de contexto, decisión, intención y salida. Al principio pueden envolver los mismos valores que hoy se pasan por llamadas directas.
2. Añadir el host al nodo raíz existente y pasar su `_physics_process` allí, preservando el orden de §4.
3. Convertir `H0Core._physics_process()` en `step(context)` y `resume_from_core(air_mode)`; retirar referencias directas al input y body.
4. Convertir `V3HangingCore._physics_process()` en `step(context)` y hacer que devuelva `CONTINUE` o `EXIT_TO_H0`; retirar `h0` y `physics_body` de sus exports.
5. Convertir probes e input a métodos llamados por el host y retirar sus `_physics_process`.
6. Adaptar `V3PhysicsBody` a `apply(intent, launch)` y retirar sus APIs acumulativas `submit_*`.
7. Repetir los smoke tests actuales y agregar pruebas de orden: una decisión de N se aplica en N, y una reacción a un resultado físico ocurre en N+1.

---

## 9. Preguntas que el protocolo no debe ocultar

- La política definitiva para elegir entre varias candidatas contextuales.
- La implementación física y los criterios de bloqueo de `HOLD_POSE`.
- Si H0 puede volver a conceder otro core en el mismo tick de una salida.
- Cuáles son los modos de reentrada de H0 que el gameplay realmente necesita.

Son decisiones de gameplay o física. El protocolo sólo asegura que, cuando se decidan, viajan por un camino único, visible y testeable.

