# V3 Hanging — borrador de generador de volúmenes de captura

## Estado

**Borrador conceptual (2026-09-20). No decidido y no implementable todavía.**

Este documento registra una posible pieza nueva para derivar los volúmenes de
captura de Hanging. No autoriza scripts, escenas, nodos, colliders, pruebas de
runtime ni cambios en el flujo vigente.

La pregunta que motivó este borrador es: si el cilindro de pared y la esfera
son volúmenes imaginarios que sólo existen con agarres válidos, ¿quién publica
sus datos para que el detector de contacto los pueda comparar?

## Idea propuesta

Nombre tentativo: `HangingCaptureVolumeGenerator`.

Sería un miembro de la familia genérica **generadores**. Un generador no lee
el mundo como una sonda, no compara formas como un detector de contacto y no
decide gameplay como un core: deriva un conjunto de datos para que otra pieza
lo consuma.

En este caso, no “crearía” ni “borraría” objetos reales. Publicaría un
**snapshot** nuevo cada tick con los volúmenes de captura que corresponden a
los agarres válidos de ese instante.

```text
agarres válidos del evaluador + body actual
        ↓
HangingCaptureVolumeGenerator
        ↓
snapshot de cilindros y esfera
        ↓
HangingCaptureContactDetector
```

## Por qué no se trata igual que los rayos

Los rayos horizontales y verticales son sondas genéricas permanentes: están
configurados desde el inicio y sólo leen el mundo cada tick.

Los volúmenes de captura no son permanentes:

- puede no haber agarres válidos, en cuyo caso no debe haber volúmenes;
- puede haber un cilindro por cada agarre válido;
- su posición depende de borde, normal de pared y posición actual del body;
- la esfera depende del body y del contexto de muro.

Por eso no se propone montar ni destruir nodos. El generador sólo describe
cómo se ven los volúmenes **ahora**.

## Entrada propuesta

El generador recibiría solamente datos ya decididos por otras piezas:

| Entrada | Dueño del dato | Uso del generador |
| --- | --- | --- |
| Agarres válidos | Evaluador de candidatos de Hanging | Produce un cilindro por cada agarre. |
| `grip_id` estable | Evaluador de candidatos de Hanging | Copia la identidad al cilindro; no la inventa. |
| Punto de borde, normal y pared | Evaluador de candidatos de Hanging | Ubica y orienta el cilindro. |
| Transform actual del body | `V3PhysicsBody` | Ubica la esfera y sigue el movimiento tangencial. |
| Contexto de captura | Política todavía sin decidir | Indica con qué muro/dirección se calcula la esfera. |

El generador no reevaluaría si un agarre sirve, no calcularía la pose `P` y no
elegiría cuál core gobierna.

## Salida propuesta

El resultado sería una estructura de datos de este estilo conceptual:

```text
CaptureVolumesSnapshot
  sphere:
    center
    radius
    capture_context_id

  cylinders[]:
    grip_id
    support_id
    center
    axis
    length
    radius
```

No son nombres de API aprobados; describen solamente el contrato mínimo.

Reglas de la salida:

- Sin agarres válidos: snapshot vacío; no queda ningún cilindro huérfano.
- Con varios agarres válidos en el mismo contexto: una esfera y un cilindro
  por agarre.
- En el tick siguiente se publica otra foto con las posiciones actuales.
- El generador no conserva el snapshot anterior como historial de contacto.

## Relación con el detector de contacto

El detector `HangingCaptureContactDetector` consumiría el snapshot actual y
conservaría, por su cuenta, la muestra previa que necesite para el barrido
entre ticks.

```text
snapshot actual + muestra previa compatible
        ↓
¿la esfera tocó o cruzó cuál cilindro?
        ↓
evento crudo: tipo de contacto + grip_id
```

La identidad debe nacer en el evaluador y viajar sin cambios:

```text
evaluador asigna grip_id
        ↓
generador lo copia al cilindro
        ↓
detector lo informa con el contacto
        ↓
HangingCore recupera el agarre y la pose P correspondientes
```

Si un `grip_id` cambia entre dos ticks, el detector no debe barrer entre sus
muestras como si fueran el mismo agarre. Debe descartar ese historial para
evitar un contacto falso.

## Fronteras de responsabilidad

| Pieza | Hace | No hace |
| --- | --- | --- |
| Sondas horizontales/verticales | Observan pared y superficies. | Construir captura. |
| Evaluador de candidatos | Determina agarres válidos, `P` e identidad. | Crear objetos de captura o detectar contacto. |
| Generador propuesto | Deriva snapshot de cilindros/esfera. | Validar agarres, elegir core o detectar contacto. |
| Detector de contacto | Compara esfera y cilindros, incluido el barrido. | Decidir Hanging o aplicar snap. |
| HangingCore | Decide entrar o no con el evento recibido. | Fabricar volúmenes o mover el body directamente. |
| `V3PhysicsBody` | Aplica el snap aceptado. | Elegir agarre o contacto. |

## Bloqueo de diseño: una esfera ante varios muros

La propuesta es clara cuando todos los agarres activos pertenecen a la misma
pared o a paredes con la misma dirección: hay una esfera y varios cilindros.

Todavía no está decidido qué debe pasar si el evaluador ve agarres válidos en
muros con normales distintas. La esfera necesita una dirección de muro para
ubicarse en el frente correcto de la cápsula.

Antes de aprobar este generador hay que probar ese caso y decidir una política:

1. admitir un solo contexto de muro a la vez;
2. permitir varios contextos y emitir una esfera por contexto; o
3. seleccionar un contexto antes de llegar al detector.

Ninguna de las tres está elegida. El generador no puede inventarla por su
cuenta.

## Qué prueba hace falta antes de decidir

Una fixture de laboratorio debe poner al player frente a candidatos válidos de
paredes con normales distintas, por ejemplo una esquina o dos paredes cercanas.
Debe mostrar simultáneamente:

- agarres candidatos e identidades;
- normal y contexto de cada agarre;
- posición que tendría la esfera;
- cilindros que se publicarían;
- contacto que produciría el detector.

La prueba busca responder qué comportamiento se siente correcto y entendible,
no simplemente confirmar que el código no falla.

## Decisiones que este borrador no toma

- Que el generador exista definitivamente en vez de que el evaluador publique
  los mismos descriptores.
- El nombre final de la pieza, estructuras o APIs.
- La política para varios muros/normales.
- El formato final de `grip_id` estable.
- Valores geométricos de cilindro y esfera.
- Implementación, orden de nodos o cambios al laboratorio.
