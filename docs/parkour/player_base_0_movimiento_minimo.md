# Player Base 0 - Movimiento minimo

## Estado

**Siguiente bloque de diseno e implementacion.**

Este bloque reinicia el desarrollo desde la capa mas pequena posible. No intenta rescatar el traversal V2 existente ni iniciar Hanging Core. Su unica pregunta es:

> ¿Mover el player con WASD y mirar con el mouse se siente correcto?

## 1. Alcance cerrado

Incluido:

- `CharacterBody3D`, collider y suelo plano.
- Movimiento horizontal con WASD.
- Camara de primera persona con mouse-look.
- Gravedad minima para mantener el cuerpo sobre el suelo.
- Frenado al soltar direccion.

Excluido:

- Salto, carrera, crouch, slide y vault.
- Hanging, probes, traversal, resolver, controller, leases y debug de traversal.
- Switchboard de mecanicas.
- Rampas, geometria especial y playground completo.
- Inventario, kick, salud, UI legacy, autoloads y cualquier otra dependencia de V1.

La escena inicial puede ser un suelo plano, una pared de referencia y un spawn. `movement_test_2` como gimnasio completo llega despues de que este bloque sea aceptado.

## 2. Fuente V1: hechos relevantes

Fuente de codigo: V1 historico `860a999f2c5ada8fc01ab74179a3442f887883d3` (`bd38e49^`).

| Hecho V1 | Evidencia | Consecuencia para Base 0 |
|---|---|---|
| WASD construye una direccion a partir de la base del cuerpo y la normaliza. | `player.gd:_get_input_direction` | Diagonal no puede ser mas rapida que un eje. |
| Adelante usa `-basis.z`; atras `+basis.z`; izquierda `-basis.x`; derecha `+basis.x`. | `player.gd:_get_input_direction` | El movimiento horizontal sigue el yaw del cuerpo. |
| Sin `run` ni crouch, velocidad objetivo inicial = `5.0`. | `movement_controller.gd:SPEED` y `_update_speed` | `5.0` es la hipotesis inicial de velocidad para este bloque. |
| En suelo, velocidad horizontal converge hacia el objetivo con `lerp(..., ACCELERATION * delta)`, con aceleracion `14.0`. | `movement_controller.gd:_apply_movement`, `ACCELERATION` | La respuesta inicial debe aproximar el arranque y frenado de V1, no usar una inercia lenta arbitraria. |
| `move_and_slide()` integra el movimiento. | `player.gd:_physics_process` | El motor V2 conserva autoridad fisica unica; no se escribe `global_position` para locomocion. |
| El mouse rota yaw del cuerpo con sensibilidad `0.003`. | `player.gd:_input` | Valor inicial para el look horizontal. |
| El mouse rota pitch de camara y lo limita a `[-PI/2, PI/2]`. | `player.gd:_input` | Mirar arriba/abajo no puede voltear la camara ni inclinar la direccion horizontal. |
| Gravedad se aplica fuera de suelo. | `movement_controller.gd:_apply_gravity` | No hay salto, pero el cuerpo debe mantenerse fisicamente apoyado si pierde contacto. |

No se porta en este bloque `RUN_SPEED=9.0`, `JUMP_VELOCITY`, control aereo, crouch ni ningun estado de traversal. Que estos valores existan en V1 no los convierte en alcance de Base 0.

## 3. Extrapolacion hacia la arquitectura V2

No se copia el controlador V1. Se conserva la separacion de responsabilidades de V2 y se porta solamente el comportamiento observable de locomocion basica.

| Responsabilidad | V1 historico | V2 Base 0 |
|---|---|---|
| Leer WASD | `player.gd` | Nodo player / capa de input del player. |
| Convertir input en direccion horizontal | `player.gd:_get_input_direction` | Nodo player entrega una direccion normalizada a `PlayerMotor`. |
| Actualizar velocidad y gravedad | `MovementController` | `PlayerMotor`, unico dueno de `velocity` y gravedad. |
| Integrar colision | `player.gd:move_and_slide()` | `PlayerMotor` mediante la API fisica del player. |
| Yaw de cuerpo y pitch de camara | `player.gd:_input` | Nodo player/camara; no pertenece a traversal. |
| Traversal | detector + resolver + controller V1 | No existe en Base 0. |

Invariantes de arquitectura:

1. `PlayerMotor` es el unico escritor de velocidad, gravedad y movimiento fisico.
2. La capa de input no decide fisica: solo entrega direccion y look.
3. La camara modifica yaw/pitch, no la velocidad directamente.
4. No se crean placeholders de detector, resolver o controller para "preparar" traversal. Aun no existen.
5. No se usa ningun autoload o script legacy V1.

## 4. Contrato observable de Base 0

| Situacion | Resultado esperado |
|---|---|
| Mantener W | El cuerpo acelera hacia adelante relativo a su yaw. |
| Mantener S/A/D | El cuerpo acelera hacia la direccion correspondiente relativa a su yaw. |
| Mantener W+D | La direccion se normaliza; no supera la rapidez de W solo. |
| Soltar WASD | El cuerpo frena hacia reposo, sin deriva aceitosa prolongada. |
| Girar yaw mientras se mueve | La direccion solicitada cambia con el cuerpo; no con el pitch. |
| Mirar arriba/abajo | Solo rota la camara; el movimiento horizontal no despega ni se inclina. |
| Llegar al limite de pitch | La camara se mantiene estable; no da vuelta completa ni tiembla. |
| Pulsar Espacio | No ocurre nada: salto aun no existe. |

Valores iniciales de equivalencia V1, sujetos a playtest:

```text
velocidad objetivo: 5.0 m/s
respuesta de aceleracion/frenado: factor 14.0 * delta
sensibilidad de mouse: 0.003
pitch: -90° a +90°
```

Son una hipotesis inicial, no una orden de copiar toda implementacion V1. Si el motor V2 necesita expresar la misma respuesta con una formulacion mas estable, se documenta la equivalencia perceptible y se prueba.

## 5. Prueba minima

Escena minima:

```text
Player Base 0
├─ suelo plano con colision
├─ pared/frente visual para orientacion
└─ spawn fijo
```

Pruebas automatizables iniciales:

- Direccion diagonal normalizada.
- La capa de input entrega direccion correcta respecto al yaw.
- `PlayerMotor` es el unico camino que altera velocidad horizontal.
- Espacio no modifica velocidad vertical ni inicia estado alguno.
- Pitch se mantiene dentro de los limites establecidos.

Playtest humano minimo:

1. Avanzar, frenar y cambiar de direccion.
2. Moverse diagonalmente.
3. Girar con mouse mientras se avanza.
4. Llevar la camara a ambos extremos verticales.
5. Confirmar que no existe ninguna accion adicional inesperada.

## 6. Criterio de cierre

Base 0 se cierra cuando:

1. Los contratos automatizables pasan.
2. El player responde a WASD/camara de forma estable en suelo plano.
3. El playtest confirma que el arranque y frenado no tienen la sensacion aceitosa que se quiere evitar.
4. No existe salto ni traversal por accidente.
5. Ningun problema de este bloque se tapa agregando otra mecanica.

Al cerrar Base 0, la unica nueva pregunta autorizada es:

> ¿Como debe saltar este mismo player?
