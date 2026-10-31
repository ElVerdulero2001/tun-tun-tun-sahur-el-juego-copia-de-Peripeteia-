# V3 — Hanging: captura por contacto de sondas (borrador)

## Estado

**Borrador de conversación (2026-09-19).** Recoge lo que el usuario explicó
de palabra y con dibujos. No es una propuesta cerrada: lo que no fue dicho
figura en "Abierto" y no se completa por inferencia.

Si el usuario lo confirma, este documento **reemplaza** la esfera de captura
centrada en `P` de `v3_hanging_captura_propuesta.md`.

No define técnica (raycast, ShapeCast, nodos, API). Define comportamiento.

## 1. Idea

Cuando Hanging es posible, el snap a la pose de colgado se dispara en el
instante en que dos sondas se tocan: una que vive en la pared y otra que vive
dentro del player. No antes, no después.

```text
Hanging posible (hechos + prerrequisitos aprobados)
   → existe la sonda de pared (disco)
   → la sonda del player (esfera) toca el disco, en cualquier punto
   → SNAP a la pose de colgado
```

## 2. Sonda de pared (disco)

Cilindro bajo, de eje vertical, plano como un disco.

- Solo existe mientras Hanging es posible.
- Sigue al player **a lo largo del muro** (su posición lateral).
- Arranca en la **cara del muro** y sale hacia afuera. **No queda metido en
  la pared.**
- Según el dibujo del usuario, su cara superior queda a la altura del borde
  superior del muro y su grosor se extiende hacia abajo.
- Todo es configurable: altura respecto del borde, alcance/radio, grosor.

```text
   ▓▓▓▓▓█████████    ← disco: sale de la cara del muro, tope al ras del borde
   ▓▓▓▓▓
   ▓▓▓▓▓
```

## 3. Sonda del player (esfera) y pose final

Son **dos valores configurables independientes** en el editor:

1. **Posición de la esfera** dentro del body. Decide *cuándo* se dispara el
   agarre.
2. **Pose final** del player respecto del muro (distancia al muro y altura
   respecto del borde). Decide *dónde* queda al colgarse.

La esfera:

- Vive **dentro del body**, en la parte alta.
- Su altura es relativa al **body completo** (el conjunto que se mueve
  entero), no a la cámara ni a la cápsula por separado. Motivo: si algo no
  queda bien se ajusta un valor y se mueve todo, sin desalineaciones
  difíciles de diagnosticar.

## 4. Regla de disparo

- El snap ocurre en el **primer contacto** entre esfera y disco, en cualquier
  punto de ambos.
- La captura vale **cayendo y subiendo**. No hay límite de velocidad vertical
  como prerrequisito.
- Los prerrequisitos duros del contrato (`v3_hanging_contrato_borrador.md`)
  siguen: aire, pared y borde válidos, pose que cabe, intención no
  contradictoria.
- Agarrarse mientras se cae **no produce daño de caída**. Decisión
  deliberada, por feeling.

## 5. Tamaño del snap

Objetivo: que el snap sea pequeño. Ningún jugador debe ver un salto grande de
cámara al capturarse.

La esfera y la pose final son independientes (sección 3). El snap mide la
distancia entre el punto donde la esfera tocó el disco y la pose final. Se
afina moviendo los dos valores hasta que coincidan y esa distancia sea
mínima.

**Nota (consecuencia, no decisión):** como el contacto vale en cualquier
punto del disco pero la pose final es un solo punto, el tamaño del disco
también limita el salto máximo del snap. Disco chico = snap casi
imperceptible, pero más fácil de no tocar. Disco grande = agarra más, con
salto más visible.

**Sugerencia de debug (no discutida):** mostrar en pantalla la distancia real
del último snap, para poder afinar los dos valores a ojo.

## 6. Contacto entre ticks

La física avanza a saltos. Un player rápido puede pasar de un lado del disco
al otro entre dos ticks sin quedar solapado en ninguno.

**Requisito propuesto:** un contacto no debe perderse por velocidad. Se
prefiere que también cuente que el recorrido entre la posición anterior y la
actual de la esfera cruce el disco.

La técnica no se fija aquí. Una idea del usuario es generar rayos
intermedios entre muestras; aplicada al tiempo equivale a un barrido desde la
posición anterior hasta la actual.

**Problema distinto, mismo documento:** los huecos *espaciales* entre rayos
de la sonda de detección (una arista fina que cae entre dos rayos vecinos).
No es lo mismo que el cruce entre ticks y tiene su propia solución posible
(por ejemplo, un volumen en lugar de rayos sueltos). Queda para el documento
de detección.

## 7. Bloqueo de entrada (Ctrl)

`Ctrl` produce un bloqueo que impide entrar a **cualquier** core, aunque
tenga todo lo necesario:

- **Mantenido:** bloquea mientras está apretado.
- **Un toque:** queda agachado, y el estado agachado también bloquea.

El jugador elige el modo. El efecto sobre los cores es el mismo:
`bloqueo = Ctrl mantenido O agachado`. H0 siempre gana. El nombre del flag
está pendiente.

## 8. Otras decisiones registradas

- **Salto de salida:** hacia donde apunta la cámara, incluido el pitch. Si la
  cámara mira al muro, salta hacia arriba. Válido en primera y tercera
  persona.
- **Árbitro:** mientras Hanging sea el único core, la certeza que lee es
  100.
- **Switchboard:** la captura, el shimmy, el salto de salida y la protección
  de reenganche son capacidades consultadas en la frontera de cada
  transición (`switchboard_sistema_pruebas.md`, considerado ejemplo, no ley).
  El switchboard aún no existe en código.

## 9. Superficies sin geometría identificable

Para planos sin geometría 3D identificable, un `Marker3D` define el punto de
captura. **No está diseñado.**

## 10. Diferencias con la implementación mínima actual

| Tema | Implementación actual | Este borrador |
|---|---|---|
| Disparo | Autoactivación al leer una candidata válida | Contacto disco↔esfera |
| Velocidad | Bloquea si sube a más de 0.5 m/s | Sin límite; captura también subiendo |
| Pose | Offsets fijos 0.68 y -1.5 | Valor configurable propio, independiente de la esfera |
| Salto de salida | Vertical puro, 5 m/s | Según cámara |
| Bloqueo | Ctrl solo suelta | Ctrl y agachado bloquean la entrada |
| Shimmy y reenganche | Siempre activos | Capacidades del switchboard |

## 11. Abierto

- Si este documento reemplaza definitivamente la captura anterior.
- Si la esfera existe siempre o solo con candidato válido.
- Radio, grosor y altura por defecto de ambas sondas.
- Técnica del contacto entre ticks.
- Diseño del `Marker3D`.
- Nombre del flag de bloqueo.
- Si el snap se aplica en el mismo tick del contacto o se tolera un tick de
  latencia (unos 16 ms). Propuesta provisional: tolerarlo y revisarlo en el
  prototipo.
- Tensión: el switchboard pone Mantle bajo Hanging; V3 lo define como core
  aparte.

## 12. Fuera de alcance

Shimmy, mantle, esquinas, soporte móvil, animación, interpolación del snap y
fórmula de certeza.
