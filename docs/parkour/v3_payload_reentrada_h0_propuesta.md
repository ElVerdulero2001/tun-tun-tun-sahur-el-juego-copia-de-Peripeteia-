# Parkour V3 — payload de reentrada a H0

> **Estado:** propuesta mínima para discusión. No implementada.
>
> Este documento mantiene el ciclo de V3 (`H0 → core → H0`). No introduce
> secuelas, capas de movimiento, canales, prioridades ni un segundo gobierno.

---

## 1. El problema concreto

Al salir de Hanging con salto ocurren dos cosas que deben sobrevivir a la
salida del core:

1. se aplica una velocidad de lanzamiento una sola vez;
2. H0 debe retomar la locomoción aérea con una política temporal distinta de
   su política normal, y no debe reinterpretar la misma pulsación de Espacio
   como nuevos saltos al aterrizar.

Ese estado temporal existe en el gameplay. La decisión no es si existe, sino
dónde queda explícito. Esta propuesta lo guarda temporalmente en **H0**, que
es quien retoma y ejecuta la locomoción.

---

## 2. Regla de arquitectura

Un core no modifica campos de H0 ni lo llama directamente. Al terminar,
devuelve datos de reentrada. El punto de handoff de V3 (Player/Controller)
los entrega a H0.

```text
Hanging termina
  → V3CoreExit { launch_velocity, h0_resume }
  → Player/Controller aplica launch en V3PhysicsBody
  → Player/Controller llama H0.resume_from_core(hechos, h0_resume)
  → H0 vuelve a ser el único gobernante
```

No hay una mecánica viva después de que Hanging termina. H0 interpreta un
contrato general de reentrada; no conoce Hanging, Ladder ni un motivo de salida
específico.

---

## 3. Los tres contratos necesarios

| Contrato | Dueño | Responsabilidad |
| --- | --- | --- |
| `V3CoreExit` | Cualquier core | Declara que terminó, un efecto físico inmediato opcional y los datos para reanudar H0. |
| `H0ResumePayload` | H0 | Describe la política temporal que H0 puede aplicar al retomar. |
| `V3PhysicsBody.apply_launch()` | Body | Aplica una velocidad una vez. Sigue siendo el único escritor de `velocity` y del movimiento físico. |

### 3.1 `V3CoreExit`

```gdscript
class_name V3CoreExit

var reason: StringName
var launch_velocity: Vector3
var has_launch := false
var h0_resume: H0ResumePayload
```

`reason` sirve para debug, audio o animación; no es una entrada para que H0
elija ramas de mecánicas. `launch_velocity` es un efecto de una sola aplicación
del body, no un estado persistente de H0.

### 3.2 `H0ResumePayload`

La primera versión debe ser deliberadamente pequeña y basada sólo en datos:

```gdscript
class_name H0ResumePayload

enum AirMode {
    NORMAL,
    PRESERVE_MOMENTUM,
}

var air_mode := AirMode.NORMAL
var air_mode_duration := 0.0
var ignore_jump_while_held := false
```

Semántica:

- `NORMAL`: H0 usa su control aéreo normal.
- `PRESERVE_MOMENTUM`: sin input horizontal, H0 conserva la velocidad
  horizontal física actual; con input, usa la política que H0 defina para este
  modo.
- `air_mode_duration`: al vencer, H0 descarta el payload y vuelve a su
  comportamiento normal. Aterrizar también lo descarta si ésa es la regla de
  diseño elegida para ese modo.
- `ignore_jump_while_held`: H0 no solicita salto mientras siga sostenida la
  pulsación que existía al recibir el payload. Al soltarla, el bloqueo desaparece.

Hanging puede elegir valores de este contrato. No puede agregar campos,
modificar el estado interno de H0 ni entregar callbacks, referencias a nodos o
Resources de lógica ajena.

---

## 4. Ejemplo: salida de Hanging con salto

```gdscript
func _build_jump_exit() -> V3CoreExit:
    var payload := H0ResumePayload.new()
    payload.air_mode = H0ResumePayload.AirMode.PRESERVE_MOMENTUM
    payload.air_mode_duration = 0.75
    payload.ignore_jump_while_held = true

    var exit := V3CoreExit.new()
    exit.reason = &"hanging_jump"
    exit.launch_velocity = _get_jump_exit_velocity()
    exit.has_launch = true
    exit.h0_resume = payload
    return exit
```

El handoff lo consume sin saber de qué core procede:

```gdscript
func _return_to_h0(exit: V3CoreExit, facts: V3Hechos) -> void:
    if exit.has_launch:
        physics_body.apply_launch(exit.launch_velocity)
    h0.resume_from_core(facts, exit.h0_resume)
    active_core = null
```

El orden concreto de `apply_launch()` y la primera intención de H0 debe
conservar la regla existente del body: el launch reemplaza la velocidad una vez
y H0 toma los hechos físicos resultantes en el tick siguiente.

---

## 5. Estado mínimo dentro de H0

H0 conserva el payload activo y sus datos derivados, por ejemplo:

```gdscript
var _resume_payload: H0ResumePayload = null
var _resume_air_remaining := 0.0
var _jump_blocked_until_release := false
```

`resume_from_core()` copia los datos necesarios, rearma su estado derivado a
partir de `V3Hechos` y activa el bloqueo de salto sólo si la tecla ya estaba
sostenida. En cada tick H0:

1. libera `_jump_blocked_until_release` cuando observa que Espacio fue soltado;
2. aplica el modo aéreo temporal si sigue activo;
3. descarta el estado temporal al vencer su duración o cumplir su condición de
   fin;
4. emite la única intención de movimiento para `V3PhysicsBody`.

No hace falta que el input sea un sistema global de tokens para resolver este
caso: el latch vive en H0 y sólo afecta su propia solicitud de salto.

---

## 6. Límites explícitos

Esta solución deja de ser suficiente si aparece una necesidad real de que una
mecánica continúe gobernando mientras otro core gobierna, o de combinar dos
políticas físicas independientes. No se debe anticipar esa complejidad.

Si un core pide un campo nuevo, se decide antes:

1. ¿Es una capacidad general de reentrada de locomoción? Entonces se agrega un
   campo pequeño y genérico al payload de H0.
2. ¿Es semántica propia del core? Entonces el core debe conservar gobierno en
   una fase interna adicional, en lugar de contaminar el payload.
3. ¿No encaja en ninguna? Es una decisión de arquitectura nueva, no un campo
   improvisado.

Campos prohibidos en el payload: nombres de cores, razones específicas de
Hanging, referencias a nodos, callbacks, recursos mutables y listas de
modificadores apilables.

---

## 7. Criterio de aceptación inicial

Antes de ampliar el contrato, demostrar en el laboratorio:

1. Salir de Hanging con salto y sin input conserva el impulso horizontal
   durante 0.75 s.
2. Mantener Espacio desde la salida hasta aterrizar produce cero saltos extra.
3. Soltar Espacio y volver a apretarlo permite el siguiente salto normal de H0.
4. Una salida voluntaria sin launch ni payload devuelve H0 con su comportamiento
   normal.
5. H0 sigue siendo el único emisor de intención de movimiento después del
   handoff.

