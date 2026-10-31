# V3 — Hanging: diseño paso a paso

## Propósito

Documento de trabajo para diseñar **Hanging** de V3 muy lentamente, un punto
por vez. Cada paso se cierra con el usuario antes de abrir el siguiente. Nada
de lo que no esté aprobado aquí se da por decidido, aunque exista en otros md
o en el laboratorio.

Registra decisiones y su estado. No contiene lógica, scripts, llamadas ni
pseudocódigo salvo que un paso lo pida expresamente.

## Marco dado por el usuario (2026-09-19)

- **V3 es el core.** No se piensa tocar mucho.
- **La idea del switchboard queda descartada.** Todo lo que los md digan sobre
  él (`switchboard_sistema_pruebas.md`, gates de capacidades, "capacidades
  consultadas en la frontera") **no se usa** como referencia para este diseño.
- Temporalmente, **Hanging es el único core contextual** por ahora (lectura
  del usuario: "temporalmente es la única por ahora"; confirmar si se refería
  a esto).
- Se usan los md de `docs/parkour/` como **referencia**, no como ley.
- Método: **por pasos, punto por punto**, sin adelantar.

## Referencias principales

| Documento | Para qué sirve aquí |
| --- | --- |
| `v3_hanging_flujo_completo.md` | Recorrido único actual: player → sondas → candidato → contacto → snap → Hanging. |
| `v3_hanging_deteccion_propuesta.md` | Sondas de detección (pared, tapa, volumen, pose). |
| `v3_hanging_captura_sondas_borrador.md` | Sondas de captura (disco y esfera). Decisiones del usuario. |
| `v3_hanging_captura_sondas_implementada.md` | Valores y geometría ya probados en el laboratorio. |
| `v3_hanging_arbol_eventos.md` | Recorrido real del runtime actual. |
| `v3_hanging_contrato_borrador.md` | Prerrequisitos duros de entrada. |

## Pasos

| # | Tema | Estado |
| ---: | --- | --- |
| 0 | Crear este documento | Hecho |
| 1 | Qué sondas se usan para ver el entorno | **Aprobado (2026-09-20):** por ahora solo 4 (grilla frontal, rayos descendentes, cilindro de pared, esfera del player). Volumen frontal fuera; pose ocupable pasa a validación aparte. |
| 2 | Ranura tapada y agarres múltiples (listones) | **Dirección decidida (2026-09-20):** fila vertical de tramos cortos hacia abajo; un cilindro por agarre válido. Valores abiertos, ver "Abierto en este paso". |
| 2b | Contacto cilindro ↔ esfera | **Decidido (2026-09-20):** actor nuevo `HangingCaptureContactDetector`. Ver la última sección. |
| 3+ | Sin definir (pendientes: barrido entre ticks de los rayos horizontales; pose ocupable como validación) | — |

## Paso 1 — Sondas del entorno

Solo se enumeran las sondas. No se define cuándo corren, cómo se combinan ni
qué deciden.

### Regla general: las sondas son bobas (2026-09-20, dicho por el usuario)

Las sondas **solo adquieren y muestran datos**. No calculan, no procesan, no
computan. Cada core que necesita ese dato lo consume y hace lo suyo.

### Principio: dos grupos de sondas (2026-09-20, aclarado por el usuario)

**Grupo 1: detección. Rayos horizontales y rayos verticales.**
Son las sondas que avisan "acá detecté algo". Solo informan que tocaron algo y
dónde. No interpretan ni deciden. Cada consumidor hace su parte con ese dato.

**Grupo 2: captura. Cilindro de pared y esfera del player.**
Aparecen **solo cuando V3 ya determinó que la pared sirve para Hanging**. Sirven
únicamente para indicar **el momento del snap**. Nada más.

Con esto queda resuelto el punto abierto sobre la esfera: no existe siempre, solo
aparece junto con el cilindro cuando el agarre es válido.

Con esto también, la regla del espacio libre mínimo sobre el borde no es de la
sonda: la aplica quien consume los datos de la fila vertical. La sonda solo
reporta lo que tocó cada tramo.

### Sondas de detección (leen el mundo)

1. **Rayos horizontales (grilla frontal).** Serie vertical de rayos hacia
   adelante. Publican dónde hay pared, con punto y normal.
   Laboratorio actual: 5 rayos entre 0.3 y 1.5 m de altura, 0.85 m de alcance.
   Pendiente: barrido entre ticks para altas velocidades.
2. **Rayos verticales (fila de tramos cortos hacia abajo).** Una sola fila,
   pegada a la cara de la pared y apenas hacia adentro, que cubre el rango
   alcanzable. Publican qué tocó cada tramo. Ver Paso 2.

Fuera de la lista (2026-09-20): el **volumen frontal** ya no se usa, y la
**consulta de pose ocupable** pasa a ser una validación aparte, no una sonda.

### Sondas de captura (describen los volúmenes de captura)

3. **Cilindro de pared.** Cilindro **acostado**, con el eje perpendicular al
   muro: nace en la cara del muro (no dentro) y sale hacia afuera. Su parte
   superior queda al ras del borde. Longitud **0.5 m**; radio **editable**.
   Sigue al player a lo largo del muro (no a su cámara). Uno por cada agarre
   válido. Aparece solo cuando V3 valida el agarre.
4. **Esfera del player.** Parte alta de la cápsula, del lado que mira al muro,
   pegada al frente (tangente por dentro). Su posición sigue al body, no a la
   cámara. Aparece junto con el cilindro cuando el agarre es válido.
   Laboratorio anterior: offset (0, 1.30, 0), radio 0.10 m (valores por
   redefinir).

El contacto entre estas dos sondas no lo calculan ellas: lo detecta
`HangingCaptureContactDetector` (ver "Contacto cilindro ↔ esfera").

### Cambios pedidos por el usuario sobre la lista

- **Cilindro de pared:** ya no es un disco vertical. Según `SUM-3.png` es un
  cilindro acostado, con eje perpendicular al muro, que sale de su cara.
  "Grosor" pasa a llamarse **longitud** y sube a **0.5 m** (0.25 m era corto).
  Vista de lado: rectángulo horizontal con su tope al ras del borde. Vista de
  arriba: rectángulo que sale perpendicular del muro.
- **Independencia de la cámara** (`SUM-2.png`): en los cuatro casos dibujados
  la cámara apunta a lados distintos, pero el cilindro y la esfera quedan en
  la misma posición. Solo dependen del body y del muro.
- **Esfera del player:** ya **no va en el centro del body**. Va **pegada al
  frente de la cápsula**, en la parte alta, tangente al borde frontal por
  dentro (según el dibujo `1.png`). Sigue siendo independiente de la pose final.
  "Frente" y su posición siguen **al body del player, no a la cámara**.
  Concretamente: la esfera queda siempre **del lado de la cápsula que mira al
  muro** (la dirección la da el muro, no la cámara).
- **Nombre:** el "disco de pared" pasa a llamarse **cilindro de pared**. Sigue
  al player (no a su cámara) a lo largo del muro.
- **Grilla de rayos frontales:** hay un problema **no verificado** a altas
  velocidades. Se quiere un **barrido entre ticks**: lanzar un rayo entre la
  posición anterior y la actual de cada sonda; si toca algo, hay algo ahí.
  Método a definir en un paso posterior.
- **Rayos descendentes:** duda abierta sobre huecos tapados (ranura de 10 cm
  con techo). Ver respuesta en la conversación; el diseño actual no los ve.
- **Volumen frontal:** en cuestión. Hoy es solo debug y no influye en nada.
- **Consulta de pose ocupable:** el usuario pidió explicación; pendiente de
  decidir si cuenta como "sonda" o como validación.

### Fuera de este paso

- **Rayo lateral de soporte** (shimmy): existe en el laboratorio pero shimmy
  está fuera de alcance por ahora.
- **Esfera de captura centrada en la pose P**: propuesta anterior, reemplazada
  por disco + esfera según el borrador de sondas.
- **`Marker3D`** para superficies sin geometría identificable: no diseñado.

### Puntos abiertos que tocan a las sondas

- Huecos espaciales entre rayos (una arista fina entre dos rayos vecinos). El
  borrador sugiere un volumen en vez de rayos sueltos; sin resolver.
- ~~Si la esfera del player existe siempre o solo con candidato válido.~~
  Resuelto: solo aparece cuando V3 valida el agarre.
- Valores por defecto de radios, grosores y alturas.

## Paso 2 — Ranura tapada y agarres múltiples

Estado: **dirección elegida (2026-09-20)**, valores y detalles sin cerrar.

### Problema 1: ranura tapada

Caso: agujero de 1 m de largo, 10 cm de alto y 1 m de profundidad, con material
sólido encima. El jugador ve que puede agarrarse del piso de la ranura.

- Hoy el rayo descendente parte de una altura fija (1.8 m sobre el body), 8 cm
  dentro de la pared, y devuelve la primera superficie que ve. Si parte por
  encima de la tapa, topa con ella y da un borde a altura equivocada; si parte
  dentro del sólido, puede llegar al piso por casualidad, según la geometría.
  No es confiable.
- La pregunta correcta no es "cuál es la primera superficie desde arriba", sino
  "¿hay una superficie que mira hacia arriba con espacio libre encima para las
  manos?". Lo que haya más arriba de ese espacio no importa.
- **Decisión (2026-09-20): línea vertical continua de tramos cortos.** Una fila
  de rayos cortos, uno pegado al otro, todos mirando **hacia abajo** (hacia abajo
  ven pisos; hacia arriba verían techos). Cada tramo cubre solo su pedazo de
  altura: termina donde empieza el siguiente y la fila cubre todo el rango
  alcanzable. Dibujo del usuario: `SUM-5.png`.
- **Ubicación (dibujo `SUM-6.png`):** una **sola** fila, pegada a la cara de la
  pared y apenas hacia adentro, en el punto donde los rayos horizontales
  encontraron la pared. No una fila por cada impacto: en una pared normal todas
  serían copias de la misma. Cubre el **rango alcanzable completo**. Los
  detalles del dibujo (qué rayo entra en la ranura, largo de la línea roja) son
  solo ejemplo.
- Es el "sondeo" que el usuario planteó en otro chat (un rayo entre sondas
  consecutivas), aplicado en vertical.
- Ventajas: sin huecos entre muestras, ningún rayo atraviesa la pared entera, y
  se reduce la duda de los rayos que nacen dentro del sólido.
- Se acepta el piso con **espacio libre mínimo sobre el borde**. Esa regla la
  aplica el consumidor, no la sonda (ver "Principio" en el Paso 1).
- Valores **editables**: espacio libre mínimo (propuesto 10 cm, pendiente de
  confirmar) y largo de cada tramo.
- Reemplaza la versión anterior "varios rayos largos partiendo a alturas
  distintas". Descartado también: un solo rayo partiendo justo encima del
  impacto de pared (falla si la tapa está más arriba).

### Problema 2: varios agarres válidos (listones)

Caso: listones horizontales apilados con huecos; cada uno es un agarre válido.
Hoy el evaluador se queda con un solo candidato por mayor alineación; con
listones iguales hay empate y gana el primero de la lista (orden accidental).

- **Decisión: Opción 1, un cilindro de pared por cada agarre válido.** La esfera
  del player toca el que le queda cerca y ese contacto decide qué agarre se usa
  y dónde queda la pose.
- Motivos: coincide con la regla de V3 (hechos primero, decisión después; el
  orden accidental no decide), con el "primer contacto dispara el snap" del
  borrador de sondas, y da un snap chico.
- Descartada: Opción 2, un solo cilindro con regla de desempate.
- **Salvedad:** V3 prevé que cada core proponga un candidato con certeza para el
  árbitro. Con varios cilindros, Hanging concretaría su candidato recién al
  contacto. No molesta mientras Hanging sea el único core (certeza 100); a
  revisar si hay más cores.

### Abierto en este paso

- Confirmar 10 cm como espacio libre mínimo por defecto.
- Rango alcanzable que cubre la fila de tramos.
- Largo de cada tramo y su relación con el espacio libre mínimo.
- Cuántos cilindros máximos a la vez y cómo se ven en el debug.

## Contacto cilindro ↔ esfera

Estado: **decidido (2026-09-20).** Se agrega un actor V3 nuevo,
`HangingCaptureContactDetector`. No es una sonda, un core ni el evaluador de
candidatos: su único trabajo es detectar el contacto continuo entre las sondas
de captura y publicar ese hecho crudo.

Pertenece a la familia genérica **detectores de contacto**: componentes que
comparan volúmenes o trayectorias de sondas y publican si hubo contacto. En
este caso concreto, el detector es continuo porque también mira el cruce entre
ticks, no sólo el solapamiento de la muestra actual.

### Contexto

- Regla general: las sondas solo adquieren y muestran datos; no calculan, no
  procesan, no computan.
- El cilindro de pared y la esfera del player son sondas de captura. Solo
  sirven para indicar el momento del snap.
- La esfera y los cilindros siguen siendo **sondas bobas**: exponen posición,
  tamaño, orientación e identidad del agarre; no calculan contacto ni deciden
  gameplay.
- `HangingCaptureContactDetector` consume esos datos y responde solamente:
  “¿la esfera tocó o cruzó un cilindro entre el tick anterior y éste; cuál?”
  Debe contemplar tanto el contacto de la muestra actual como el barrido entre
  ticks, para no perder una captura a alta velocidad.
- El detector publica el evento crudo, su tipo (contacto actual o barrido) y
  el cilindro/agarre involucrado. No valida candidata, intención, postura,
  locks ni pose; tampoco solicita ni aplica un snap.
- `HangingCore` consume el evento junto a sus propias condiciones y, si
  corresponde, solicita el snap. `V3PhysicsBody`, como autoridad física, lo
  aplica.
- No se crean `Area3D`, colliders ni capas de colisión sólo para estos
  volúmenes imaginarios. La alternativa de delegarlo al motor de física queda
  descartada por ahora.

Flujo acordado:

```text
sondas de captura (cilindro/esfera) → HangingCaptureContactDetector
    → HangingCore → V3PhysicsBody
```
