# V3 — Propuesta: ciclo de gobierno de Hanging (entrada, sostén y salida)

## Propósito

Cierra, para Hanging en concreto, los huecos de gobierno que
`v3_hanging_auditoria_huecos_y_fallas_filosoficas.md` marcó como bloqueantes:
la relación entre candidato/cilindro/esfera/P, las condiciones mínimas de sostén y
salida, y la política de orientación durante el sostén.

No define shimmy, salto desde Hanging con sus parámetros exactos, mantle,
esquinas, soporte móvil ni ningún valor numérico. Tampoco reabre nada de
`v3_autoridad_movimiento_propuesta.md` ni de
`v3_hanging_contrato_borrador.md`: esta propuesta sólo aplica esas
decisiones ya fijadas al caso concreto de Hanging.

## Lo que asume sin reabrir

- `H0 → Hanging → H0`, sin handoff directo entre cores.
- Contrato físico reactivo por tick: Hanging emite una intención, la capa
  física la intenta y devuelve el resultado real. Ningún core entrega una
  trayectoria autónoma de varios ticks.
- Gatillo de entrada: prerequisitos duros del core aprobados + certeza
  contextual ≥ 90 sobre una distribución de 100. Al cumplirse ambas
  condiciones, Hanging **toma gobierno de inmediato** — no existe un estado
  de "preseleccionado pero sin gobernar".
- Soportes metaestables: toda coordenada de soporte se relee cada tick: si
  deja de sostener la ejecución, el core ajusta o termina.
- El candidato de entrada ya definido por `v3_hanging_contrato_borrador.md`
  (aire, pared+borde válidos, alcance, pose libre, intención no
  contradictoria) sigue siendo el prerequisito duro de Hanging.

## Decisión propuesta 1 — cilindro/esfera y P son el soporte metaestable de Hanging, no un gatillo aparte

El hueco #5 de la auditoría preguntaba si candidato válido, cilindro/esfera y P son tres
compuertas independientes o un contrato único. Propuesta: son una sola
lectura metaestable, aplicada dos veces con el mismo criterio.

```text
antes de gobernar: candidato válido (contrato_borrador) decide si Hanging
                    puede competir por certeza contextual
al ganar el gatillo: Hanging toma gobierno ya
mientras gobierna:  cada tick se releen pared/borde/normal desde los
                    providers, se recalcula cilindro/esfera y P de nuevo — nunca se
                    reusa el P del tick de entrada
```

`P` deja de ser una pose que se copia y se guarda al entrar. Es la
intención de pose que Hanging recalcula cada tick a partir de la lectura
actual del borde. `cilindro/esfera` deja de ser un gatillo de una sola vez: es el hecho
de soporte que Hanging vuelve a comprobar en cada tick, incluso después de
haber tomado gobierno.

**Consecuencia directa:** si en algún tick el borde deja de leerse como
válido o cilindro/esfera deja de solapar, eso no es un caso especial — es la misma regla
de soporte metaestable fallando, y dispara la salida por pérdida de soporte
(decisión 3).

## Decisión propuesta 2 — intención física del sostén estático

Se eligió cerrar primero el sostén sin desplazamiento; shimmy queda fuera de
esta propuesta.

Mientras Hanging gobierna, su intención de cada tick es **intentar ocupar o
mantener la `P` recalculada en ese mismo tick** — no un teletransporte
directo al `global_transform`. La capa física intenta acercar/mantener el
cuerpo en esa pose respetando colisión, y devuelve si lo logró.

- `movement_axis` no se consume todavía durante el sostén: sin shimmy, la
  intención lateral del jugador no tiene destino que interpretar.
- Si la capa física reporta que no pudo aplicar o mantener esa intención
  (algo bloquea la pose), eso dispara la salida por bloqueo físico
  (decisión 3), no un reintento silencioso indefinido.

Esto no fija todavía el formato técnico de esa intención (tipo, campos):
eso es un prototipo posterior, igual que el resto de V3.

## Decisión propuesta 3 — cuatro salidas explícitas, todas vuelven a H0

| Salida | Origen | Dispara cuando |
| --- | --- | --- |
| Soltar voluntario | Jugador | Se recibe una directiva explícita de soltar (control a definir; no es sólo dejar de moverse). |
| Salto desde Hanging | Jugador | Se recibe una directiva de salto mientras Hanging gobierna; produce un impulso de salida en vez de sólo soltar. |
| Pérdida de soporte metaestable | Sistema | El borde deja de leerse como válido o cilindro/esfera deja de solapar en el tick actual (decisión 1). |
| Bloqueo físico de la pose | Sistema | La capa física no puede aplicar/mantener la intención de `P` de ese tick (decisión 2). |

Las dos primeras son voluntarias; las dos últimas son involuntarias y no
requieren que el jugador haga nada. Ninguna salida dejará a Hanging pidiendo
una pose vieja para siempre: todas terminan devolviendo el gobierno a H0 en
el mismo tick en que se detectan.

Fuera de esta propuesta: qué velocidad/impulso exacto recibe el salto desde
Hanging, y si usa el mismo control de salto de H0 o uno propio.

## Decisión propuesta 4 — Hanging consume Ctrl como bloqueo de entrada

Hanging declara `Ctrl` como directiva de bloqueo. Mientras se mantiene
`Ctrl`, Hanging queda excluido antes de participar en la distribución de
certeza contextual — no le resta certeza, no compite. Esto coincide con el
ejemplo ya escrito en `v3_autoridad_movimiento_propuesta.md`; esta decisión
sólo lo declara explícito para Hanging en particular.

## Decisión propuesta 5 — cuerpo fijo a la pared, cámara libre de orbitar

Mientras Hanging gobierna, el cuerpo queda orientado según la normal de
pared usada para calcular `P` y no rota libremente. La cámara sigue siendo
la referencia compartida del player y puede orbitar sin restricción — igual
que la distancia continua de cámara en H0 no altera su locomoción, orbitar
durante Hanging no envía movimiento físico ni modifica `P`.

Esto no fija límites de pitch/yaw, comportamiento en primera persona pura
ni qué pasa con la orientación al hacer shimmy o girar en una esquina. Esa
parte queda para cuando se diseñe shimmy.

## Huecos de la auditoría que esta propuesta cierra

| Hueco | Estado con esta propuesta |
| --- | --- |
| #1 Traspaso de gobierno vs precedencia accidental | Cerrado para Hanging: el gatillo por certeza contextual reemplaza la precedencia de orden de ejecución. |
| #2 Ciclo de vida y salida a H0 | Cerrado: cuatro salidas explícitas, todas devuelven gobierno a H0 en el tick que se detectan. |
| #3 Retención como coordenada eterna | Cerrado: `P` se recalcula cada tick desde la lectura actual, nunca se congela. |
| #5 Contrato único candidato/C-S/P | Cerrado: una sola lectura metaestable, aplicada antes de gobernar y durante el sostén. |
| #7 Contrato físico reactivo | Cerrado para el sostén estático: intención de pose por tick, con bloqueo físico como salida explícita. |
| #8 Soporte físico fuera de la retención | Cerrado: el soporte se relee cada tick mientras se gobierna, no sólo al entrar. |
| #9 Orientación de cuerpo/cámara | Cerrado en su mínimo: cuerpo fijo a la pared, cámara libre. Pendiente para shimmy/esquinas. |
| #10 Compuertas globales (Ctrl) | Cerrado para Hanging: declara consumo de Ctrl como bloqueo de entrada. |

Quedan abiertos, sin tocar en esta propuesta: #4 (ya resuelto por separación
de providers, mencionado por completitud), #6 (certeza contextual como
fórmula concreta, es un tema general de V3, no específico de Hanging) y
#11 (fixtures de laboratorio necesarios para validar esto).

## Qué queda deliberadamente abierto

- Shimmy y su propio contrato de intención lateral.
- Parámetros del salto desde Hanging y si reutiliza el control de salto de
  H0 o define uno propio.
- Nombre y control dedicado para "soltar voluntario".
- Formato técnico exacto de la intención de pose que Hanging manda a la
  capa física (tipos, campos, API de Godot).
- Mantle, esquinas y soporte móvil/dinámico.
- Todos los valores numéricos: radios, umbrales de altura/distancia,
  duración de control aéreo tras el salto de salida, etc.
- El fixture mínimo de laboratorio necesario para probar las cuatro
  salidas sin inventar todavía shimmy.

## Por qué

Separar "candidato" de "cilindro/esfera" de "P" como tres compuertas distintas fue lo
que produjo el latch sin salida: cada pieza dejó de leer el mundo apenas
cumplía su condición una vez. Tratarlas como una sola lectura metaestable,
aplicada de la misma forma antes y durante el gobierno, es la que ya usa el
resto de V3 para bordes y soportes — no hace falta inventar un mecanismo
nuevo para Hanging, sólo dejar de tratarlo como caso especial.
