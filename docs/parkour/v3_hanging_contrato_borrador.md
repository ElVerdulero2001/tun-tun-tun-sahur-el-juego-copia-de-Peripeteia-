# V3 — Contrato de entrada de Hanging (borrador)

## Propósito

Este documento fija qué debe significar, a nivel conceptual, que exista un
candidato válido para entrar al core **Hanging**. No es todavía el diseño
completo de Hanging: no decide cómo se desplaza colgado, cómo salta, cómo se
suelta ni cómo hace shimmy.

Tampoco define raycasts, `ShapeCast`, nodos de Godot, cantidades de probes,
distancias, tiempos ni umbrales numéricos. Esas son decisiones de
implementación posteriores.

## Frontera del core

Hanging interpreta información pública del mundo y del player para responder
una sola pregunta:

> ¿Existe ahora un borde al que este player puede entrar físicamente en pose
> de colgado?

No le corresponde a Hanging mover el `CharacterBody3D` directamente ni
activar por sí mismo su entrada. Si encuentra un candidato, lo publica para
que el árbitro lo compare con los demás candidatos contextuales. Sólo cuando
Hanging sea seleccionado se transfiere el gobierno físico desde H0 a Hanging;
la capa física común es quien aplica el resultado real.

```text
providers de información → candidato Hanging → árbitro
→ traspaso de gobierno: H0 → Hanging → capa física común
```

## Información que consume

Hanging recibe hechos, no decisiones ajenas:

- el hecho físico `en_piso`;
- posición, velocidad y orientación física actual del player;
- dirección compartida de cámara e inputs, incluida la intención de dirección
  del player frente al borde;
- observaciones neutrales de geometría: contacto con pared, punto y normal de
  la pared, punto y normal de una superficie superior, y datos necesarios para
  comprobar espacio físico.

Los providers no saben que existe Hanging: sólo publican esos hechos. Hanging
es quien interpreta si juntos describen un borde utilizable.

## Requisitos de un candidato válido

Para que Hanging publique un candidato, deben cumplirse todos estos requisitos
conceptuales:

1. **El player está en el aire.** `en_piso: false` es obligatorio. Un player
   apoyado frente a una caja o pared nunca genera una entrada a Hanging.
2. **Hay una pared válida y alcanzable delante del player.** Su inclinación y
   su normal deben describir una superficie a la que el cuerpo pueda quedar
   enfrentado; un piso, techo o plano demasiado inclinado no sirve como pared
   de agarre.
3. **La pared conduce a un borde superior válido.** Debe existir una
   superficie superior suficientemente horizontal y ligada físicamente a esa
   pared, no otro objeto cercano encontrado por casualidad.
4. **El borde es alcanzable desde la situación actual.** Su altura y distancia
   relativa deben quedar dentro del rango que pueda resolver la pose de
   Hanging. Los valores concretos se ajustarán en el laboratorio.
5. **La pose de colgado cabe físicamente.** La ubicación propuesta para el
   cuerpo no puede empezar dentro de geometría ni atravesarla al ser aplicada.
6. **La intención no contradice la entrada.** Respecto del borde propuesto, la
   intención direccional compartida se clasifica explícitamente como
   `compatible`, `neutra` o `contradictoria`:
   - `compatible` aporta certeza a Hanging;
   - `neutra` no lo invalida ni le regala certeza por sí misma;
   - `contradictoria` rechaza la entrada a Hanging como condición dura.

   Por ejemplo, mantener una directiva de alejamiento del borde no puede
   acabar en un agarre automático. La fórmula técnica que clasifica esos tres
   resultados se definirá en el laboratorio; la consecuencia contractual ya
   está fijada.

La ausencia de espacio para que el player quede **parado arriba** del borde no
invalida Hanging. Esa comprobación pertenece a un futuro Mantle: se puede
colgar de un borde aunque todavía no sea posible subir encima.

## Resultado que publica

Si los requisitos se cumplen, Hanging publica un candidato que contiene, como
mínimo:

- si es válido o no;
- el punto de borde que se usó;
- la normal de pared con la que se orientaría la pose;
- la pose física propuesta para colgarse;
- los hechos y motivos que lo validaron o rechazaron;
- su certeza calculada a partir de los datos y pesos que le correspondan, en
  la escala contextual común de V3.

Este resultado expresa una **posibilidad**, no una activación. Aun con un
candidato válido, Hanging no toma el control si el árbitro no lo selecciona o
si los prerrequisitos de entrada vigentes no se cumplen.

Las certezas de cores contextuales comparables no son porcentajes aislados.
Forman una distribución común de 100 puntos para el contexto actual. Hanging
debe producir un valor que pueda participar en esa distribución; el árbitro
compara esos valores ya normalizados y elige el mayor que además haya aprobado
sus requisitos duros. La fórmula para producir y normalizar los valores queda
fuera de este contrato.

## Qué queda deliberadamente abierto

- Cuántas sondas se usan, dónde se colocan y si son raycasts, shapecasts u otra
  técnica.
- Los rangos numéricos de altura, distancia, inclinación, volumen de pose y
  certeza mínima.
- La fórmula que clasifica la intención como compatible, neutra o
  contradictoria, y el peso concreto de cámara, movimiento y geometría.
- La fórmula de certeza y su normalización concreta dentro de la distribución
  contextual común.
- La forma del snap de entrada y la validación física que se haga durante él.
- Las reglas de Hanging activo: soltar, salto, shimmy, esquinas y salida hacia
  H0.

Nada de lo abierto debe inventarse al implementar las primeras sondas. El
primer prototipo sólo debe demostrar que puede publicar, explicar y depurar un
candidato de borde correctamente.
