# Parkour V3 — reentrada a H0: decisiones cerradas

> **Estado:** decisiones cerradas, listas para implementar. No implementado.
>
> **Origen:** parte de `v3_payload_reentrada_h0_propuesta.md` (sin modificar
> ese documento) y cierra sus puntos abiertos. Mantiene `H0 → core → H0` sin
> agregar piezas nuevas.

---

## 1. Problema

Al salir de Hanging con Espacio pasan tres cosas que hoy salen mal
(medido en el laboratorio el 2026-09-25):

| Hoy | Debería |
| --- | --- |
| H0 pone en cero el impulso horizontal del salto un tick después si no hay input. | Conservar el impulso. |
| H0 usa una única ventana aérea de 0.75 s para todo. | 0.35 s en saltos normales; 0.75 s con otra regla tras un salto de salida. |
| Mantener Espacio desde la salida produce 3 saltos de H0 al aterrizar. | Cero saltos hasta soltar y volver a apretar. |

---

## 2. Contrato

H0 expone un único punto de reentrada:

```gdscript
enum AirMode { NORMAL, PRESERVE_MOMENTUM }

func resume_from_core(air_mode: AirMode) -> void
```

- Reemplaza a `set_locomotion_suspended(false)`.
  `set_locomotion_suspended(true)` sigue existiendo para ceder.
- El core **solo elige el modo**. No entrega duraciones, velocidades ni
  ningún otro valor.
- Hanging lo llama con la referencia a H0 que ya tiene. No se crea un nodo
  intermediario.
- El launch sigue yendo directo al body (`submit_launch`), como hoy.
- Es un enum y no una clase de payload. Si algún día hace falta un segundo
  dato, recién ahí se convierte en clase.

| Salida de Hanging | Llamada |
| --- | --- |
| Espacio | `submit_launch(...)` + `resume_from_core(PRESERVE_MOMENTUM)` |
| Ctrl / atrás / pérdida de soporte / snap rechazado | `resume_from_core(NORMAL)` |

---

## 3. Config de H0

Todos los valores pertenecen a H0. Ningún otro nodo los escribe.

| Export | Valor | Uso |
| --- | --- | --- |
| `air_control_duration` | **0.35** (vuelve desde 0.75) | Ventana normal. |
| `preserve_momentum_duration` | 0.75 | Duración del modo `PRESERVE_MOMENTUM`. |
| `preserve_momentum_acceleration` | a calibrar | Aceleración hacia la dirección de input en ese modo. |

---

## 4. Reglas

### 4.1 `NORMAL`

H0 retoma como hoy. Si está en el aire, arranca su ventana de 0.35 s en el
tick en que retoma.

### 4.2 `PRESERVE_MOMENTUM`

Mientras dura (0.75 s):

- **Sin input:** conserva la velocidad horizontal actual.
- **Con input:** `horizontal.move_toward(objetivo, preserve_momentum_acceleration * delta)`,
  con `objetivo = dirección * (sprint_speed si hay sprint, si no walk_speed)`.
  Nunca reemplaza de golpe. Así, tocar una tecla un tick no borra el impulso.

Termina por la primera de estas causas:

1. **Aterrizar.** Siempre, sin excepción. En piso vuelve la locomoción normal.
   Si no terminara, el modo sin input en piso conservaría la velocidad y el
   player patinaría como sobre hielo.
2. **Vencer en el aire.** Queda solo inercia hasta tocar piso. **No** arranca la
   ventana normal de 0.35 s después. El tiempo total de control es
   exactamente 0.75 s y no hay un salto de velocidad en pleno vuelo.
3. **Ceder a otro core** (`set_locomotion_suspended(true)`), por ejemplo un
   reagarre. El modo se descarta. La reentrada siguiente arranca desde cero con
   el modo que le pasen: nada se acumula.

El contador arranca en el primer tick en que H0 gobierna después de la
llamada. La diferencia de un tick con la aplicación del launch no importa para
gameplay; es el mismo criterio que ya se había cerrado para la ventana aérea.

### 4.3 Espacio sostenido al retomar

Es una regla fija de H0 para toda reentrada, no una opción que elige el core:

```text
al retomar: si Espacio está sostenido → bloquear salto hasta que se suelte
cada tick: si Espacio no está sostenido → quitar el bloqueo
```

Solo afecta la solicitud de salto de H0.

---

## 5. Descartado y por qué

| Idea | Motivo |
| --- | --- |
| Duración dentro del payload (`air_mode_duration = 0.75` puesto por Hanging) | Un valor de Hanging manejando a H0. Contradice la regla ya escrita: "Hanging no entrega una duración ni un override". |
| "Aterrizar lo descarta si ésa es la regla elegida" | Tiene que estar decidido. Sin descartar al aterrizar, el player patina. |
| Cola de carga de modos (`[PRESERVE 0.75, NORMAL 0.35, …]`) | En todos los casos legales se reduce a dos elementos fijos. Si se agrega al final al encadenar, se apila sin sentido. Si la arma el core, el core diseña la línea de tiempo de H0. Cada cambio de elemento es un salto de velocidad en el aire, y el tiempo total de control queda escondido. Lo que decide la cola se reduce a la regla 4.2.2. |
| `ignore_jump_while_held` como campo del payload | Debe valer en toda reentrada; si es opcional, alguien se olvida de pedirlo. |
| Nodo intermediario Player/Controller para el handoff | Hoy es un solo core con una referencia que ya existe. Se agrega cuando haya más de un core que lo justifique. |
| Clase `V3CoreExit` / `H0ResumePayload` | Contenedores para un solo enum. |

Si en el laboratorio el final por inercia se siente rígido, la alternativa es
arrancar la ventana normal al vencer. Es un cambio de una regla, no un
rediseño.

---

## 6. Cambios de código

| Archivo | Cambio |
| --- | --- |
| `h0_core.gd` | Enum `AirMode`, `resume_from_core()`, tres exports, estado `_air_mode` + `_air_mode_remaining` + `_jump_blocked_until_release`, rama `PRESERVE_MOMENTUM` en el cálculo aéreo. `air_control_duration` vuelve a 0.35. |
| `v3_hanging_core.gd` | `_jump_exit()` y `_release()` llaman a `resume_from_core(...)` en lugar de `set_locomotion_suspended(false)`. |
| `v3_hanging_detection_smoke_test.gd` | Líneas 81 y 151: dejan de esperar 0.75 en la ventana normal. |

`V3PhysicsBody` no cambia.

---

## 7. Criterios de aceptación (smoke test headless)

1. Salir con Espacio sin input: la velocidad horizontal tras el launch se
   mantiene (±tolerancia) mientras dura el modo.
2. Con input durante el modo, la velocidad cambia de a poco (aceleración),
   no se reemplaza en un tick.
3. Aterrizar durante el modo lo termina; en piso, sin input, el player se
   detiene como en H0 normal.
4. Si vence en el aire, la velocidad horizontal queda igual hasta tocar piso
   (sin ventana extra).
5. Mantener Espacio desde la salida hasta aterrizar: cero saltos. Soltar y
   apretar: salta normal.
6. Salida con Ctrl/atrás: H0 retoma con ventana de 0.35 s y sin launch.
7. Reagarre durante el modo y nueva salida con Espacio: el modo arranca de
   cero, sin restos del anterior.
8. Salto normal de H0 desde piso: 0.35 s de control, igual que antes.
