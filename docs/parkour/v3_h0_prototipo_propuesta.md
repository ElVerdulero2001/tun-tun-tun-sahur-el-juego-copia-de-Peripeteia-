# V3 — Hipótesis técnica para un prototipo H0-only

## Alcance

Las decisiones conceptuales de H0 viven en `v3_h0_fundamento.md`. Este documento no las redefine: sólo propone una primera validación técnica reducida.

El objetivo es validar la columna vertebral de V3 sin implementar todavía Hanging, Ladder, Mantle ni otro core de parkour.

El prototipo contiene solamente `H0` y la infraestructura compartida necesaria para que gobierne el movimiento normal del player.

Este documento está en el nivel de **prototipo técnico**: propone una representación concreta para probar el concepto arquitectónico. No define el contrato final de V3 ni convierte sus elecciones técnicas en reglas universales.

## 🚨 Nota para Claude: esto es una hipótesis, no una ley de V3

La elección de que este prototipo H0-only use velocidad sirve únicamente para probar locomoción normal. No decide que todos los cores deban usar velocidad, que Destino esté adoptado como segundo formato, que V3 tenga exactamente dos formatos, ni qué operación de colisión usa cada uno.

Este prototipo ya implementa el salto mínimo por intención sostenida, una condición persistente de penalización tras caída, una primera ventana de control aéreo, crouch físico y sprint sostenido. Todavía **no implementa** la preferencia de sprint alternado ni orientación híbrida, aunque sus decisiones conceptuales se documenten por separado. Tampoco implementa Hanging, Ladder, Mantle, selección entre cores ni transiciones físicas entre esos cores. No rellenar esas ausencias con comportamiento de V2 ni pedir que se cierren para validar H0-only.

## Precondiciones arquitectónicas heredadas

Las siguientes reglas vienen de `v3_autoridad_movimiento_propuesta.md`; aquí no se vuelven a decidir ni se modifican:

- `H0` es el core que gobierna el movimiento físico normal del player.
- Un core no mueve directamente el cuerpo ni el collider. Una capa física común es la única que intenta aplicar movimiento real y resolver colisiones.
- Cámara e input son fuentes compartidas: no existen una cámara ni controles distintos para cada core. Un cambio de core no reinicia, reemplaza ni altera esas fuentes.
- Los providers exponen hechos neutrales; cada core consume sólo los datos que necesita.
- La simulación tiene prioridad. Una intención no garantiza un resultado físico.
- El ciclo parte desde `H0` y todo core vuelve a `H0`; no hay transferencias directas entre cores.
- El debug es observación de primera clase y no modifica gameplay.

## Circuito propuesto

```text
input + orientación de cámara
        ↓
H0 interpreta locomoción normal
        ↓
H0 emite una directiva de movimiento
        ↓
capa física común intenta mover el cuerpo real
        ↓
estado físico real actualizado y expuesto por providers
        ↓
H0 lee ese estado en el tick siguiente
```

La capa física no le envía un mensaje privado a H0. Después de intentar el movimiento, el body queda en un estado físico real; los providers exponen esos hechos y H0 los consume como cualquier otra información que necesita.

## 1. Hipótesis técnica: H0 expresa movimiento mediante velocidad

Cuando el jugador mantiene una dirección de movimiento, H0 interpreta input y orientación de cámara y calcula una **velocidad deseada**.

```text
Input W + dirección de cámara
        ↓
H0: “quiero moverme hacia adelante a esta velocidad”
        ↓
capa física: intenta aplicarlo al collider durante el paso físico
```

Se propone velocidad para H0 porque su dominio es locomoción continua: aceleración, frenado, caída e impulso. Pedir un destino nuevo cada tick para caminar obligaría a traducir artificialmente ese comportamiento continuo a posiciones objetivo.

H0 no escribe la posición, velocidad ni collider del player por cuenta propia. Sólo expresa su intención de movimiento.

## 2. Hipótesis técnica: directiva mínima de H0

Para el primer prototipo, la directiva de H0 contiene únicamente:

```text
- core emisor: H0
- tipo de movimiento: velocidad
- velocidad deseada en el mundo
- solicitud puntual de impulso de salto
- postura deseada: agachado / normal
```

La capa física ya conoce el delta del tick físico; H0 no necesita enviárselo. El salto llega como solicitud física mínima —impulso vertical sí/no— y la capa valida que el body siga sobre piso antes de aplicarlo. La postura también llega como intención: la capa puede aplicarla, rechazar volver a pararse por falta de espacio, o reanclar la misma cápsula reducida según el apoyo. La capa no aprende conceptos como “caminar” ni “Hanging”.

La interpretación práctica de la directiva es:

> H0 solicita que el body intente moverse con esta velocidad durante este paso físico.

## 3. Hipótesis técnica: alcance funcional inicial de H0

El prototipo actual valida locomoción horizontal, sprint sostenido, caída, salto desde piso, una ventana temporal de control aéreo y crouch físico. `Shift` se traduce en el hecho `sprint activo`; H0 lo usa sólo como modificador de velocidad, no como core separado. Si Shift sigue sostenido en aire, conserva velocidad de sprint durante la ventana de control. Si se suelta, la velocidad desacelera hacia la locomoción normal en lugar de caer instantáneamente; al aterrizar, el Shift actual decide si sigue corriendo o vuelve a caminar. La preferencia alternativa de una pulsación todavía no pertenece a este laboratorio.

Al alternar crouch, H0 solicita una postura; la capa física reemplaza la cápsula por una más baja. Si está en piso, conserva la base de la cápsula para mantener los pies; si está en aire, conserva su centro para que los pies suban y la cámara no cambie por ese crouch aéreo. Es una sola postura con dos anclas físicas, no dos estados de gameplay. Si se solicita volver a pararse, la capa consulta si la cápsula alta entraría realmente en el espacio actual. Si no entra, conserva la postura agachada y publica ese bloqueo. En el tick siguiente H0 descarta la orden fallida y vuelve a marcar crouch como postura deseada: salir del techo bajo no para al player automáticamente. La cámara compartida sólo acompaña la postura física real; no decide si puede producirse el cambio.

El salto no tiene coyote time: sólo se solicita si el hecho físico publicado por el tick anterior dice que el player está en piso, y la capa física vuelve a comprobarlo al aplicarlo. Espacio sostenido expresa esa solicitud cada vez que el player está apoyado; no hay buffer temporal. La capa física publica la distancia realmente descendida durante el aire y la distancia del último aterrizaje. Un estado externo de daño consume ese hecho y, si supera su umbral de laboratorio, publica una penalización persistente que H0 respeta. La recuperación no está implementada: por eso la penalización no vence por tiempo. Al despegar o abandonar un borde, H0 conserva control horizontal completo durante una ventana temporal; después conserva la inercia horizontal publicada por la física hasta volver a tocar piso. Las duraciones actuales son valores de laboratorio, no cifras de diseño cerradas.

No es una división arquitectónica nueva dentro de H0. Sprint y orientación híbrida podrán incorporarse luego sin cambiar las fronteras de esta propuesta.

## 4. Hipótesis técnica: hechos físicos publicados después del intento

Después de aplicar una directiva, los providers deben poder exponer hechos físicos neutrales. El mínimo propuesto es:

```text
- posición real final
- velocidad real final
- si el body está en suelo
- contactos o colisiones del paso
- si se solicitó un salto y si la capa pudo aceptarlo
- postura física aplicada, ancla actual y si una orden de pararse fue bloqueada
- distancia de caída actual y distancia del aterrizaje recién producido
- si el intento fue completo, parcial o bloqueado
```

Para esta integración con Godot, el hecho `está en suelo` puede venir de `CharacterBody3D.is_on_floor()` después del movimiento físico. Godot clasifica piso según `up_direction` y `floor_max_angle`; no agrega una comprobación de área mínima de apoyo. Por lo tanto, H0 no debe inventar una segunda regla de “soporte suficiente” encima de ese hecho en este prototipo.

Ejemplo:

```text
H0 pide avanzar a 6 m/s.
Una pared lo frena.
El body termina antes de lo pedido y registra contacto.
En el tick siguiente, H0 lee posición, velocidad y contacto reales.
```

Así H0 no decide a partir de su intención pasada, sino a partir del resultado que la simulación realmente permitió.

## 5. Hipótesis técnica: debug del prototipo

El debug observa el ciclo completo sin participar en él:

```text
input y cámara recibidos
        ↓
velocidad solicitada por H0
        ↓
movimiento físico aplicado
        ↓
posición, velocidad, salto y contactos reales
```

Debe poder mostrar, como mínimo:

- input y orientación de cámara consumidos por H0;
- velocidad solicitada;
- velocidad y desplazamiento reales;
- estado de suelo, contactos y bloqueos;
- intención/solicitud/aceptación del salto, distancia de caída y penalización por lesión, además del tiempo restante de control aéreo;
- postura deseada por H0, postura física real, ancla de piso/aire y bloqueo para pararse;
- diferencia entre intención y resultado.

Como H0 está ejecutando movimiento, la adquisición de estos datos relevantes ocurre al ritmo físico. La representación visual del debug puede refrescar más lento sin cambiar gameplay.

## Abierto después de validar el prototipo

- La forma exacta de una solicitud de destino, que probablemente necesitarán cores anclados como Hanging.
- Los campos exactos y tipos de la API física.
- Preferencia de sprint alternado y orientación híbrida dentro de H0.
- Cualquier core de parkour, candidatos, selección entre solicitudes y sus submecánicas.

La propuesta no usa restricciones como formato de solicitud hacia la capa física. Las reglas específicas de un core deben resolverse dentro de ese core antes de cruzar la frontera física.
