# V3 — Problema abierto: detección compuesta de Hanging

## Qué problema se quiere resolver

El contrato de entrada de Hanging ya fija **qué** debe ser cierto para que un
borde pueda usarse. Todavía no fija **cómo** se observa esa geometría.

V1 usaba una grilla de rayos horizontales a distintas alturas. Cada impacto
contra pared podía disparar un rayo hacia abajo para buscar la superficie
superior y, con ambos datos, proponer un borde. Esa radiografía es visible,
barata y útil, pero no representa una solución definitiva por sí sola.

Una única técnica de detección puede equivocarse de dos formas:

- **falso positivo:** interpreta una columna, un techo, una decoración o una
  superficie cercana como un borde utilizable;
- **falso negativo:** no ve una cornisa fina, una arista entre muestras o una
  geometría válida pero irregular.

La intención actual es combinar varias fuentes de información para reducir el
ruido geométrico. El problema no es decidir si se pueden combinar —sí se
puede— sino decidir qué rol debe tener cada una.

## Fuentes candidatas de información

Estas fuentes no son necesariamente sistemas finales ni deben implementarse
todas. Son maneras distintas de observar el mismo mundo:

| Fuente | Qué podría aportar | Qué no puede garantizar sola |
| --- | --- | --- |
| Grilla de rayos frente al player | Puntos de pared y sus normales a varias alturas. | Que exista una tapa válida o que el cuerpo entre en la pose. |
| Rayos descendentes desde un impacto de pared | Punto y normal de una superficie superior. | Que esa tapa pertenezca realmente a la pared original. |
| `ShapeCast`/volumen frontal | Que existe una superficie con volumen frente al cuerpo, no sólo el contacto de una línea. | La posición exacta del borde superior o que sea agarrable. |
| Búsqueda inversa desde una tapa | Que una superficie superior tiene una pared que la sostiene. | Que esa superficie sea la que el player puede alcanzar. |
| Contacto físico reciente | Que el movimiento real encontró una pared durante el aire. | Anticipar un agarre antes del contacto ni describir el borde. |
| Validación de pose física | Que el `CharacterBody3D` puede ocupar la pose propuesta sin atravesar geometría. | Descubrir por sí sola dónde está un borde. |

Cada fuente debe publicar hechos crudos y explicables. Ninguna debe emitir
“activar Hanging”. La interpretación sigue perteneciendo al core Hanging.

## La tensión central

Pedir que **todas** las fuentes aprueben reduce falsos positivos, pero también
puede bloquear agarres correctos. Una cornisa angosta, por ejemplo, podría ser
vista por rayos precisos mientras un volumen frontal amplio no la toca. Si el
volumen fuera obligatorio, se rechazaría un borde que sí era utilizable.

En el extremo opuesto, tratar toda lectura como un peso suave permite que una
fuente poco confiable compense una contradicción física seria. Por ejemplo, un
volumen puede tocar una columna, pero si no hay borde coherente ni pose libre,
no debe existir Hanging aunque otros pesos sean altos.

Por lo tanto, una detección compuesta necesita separar:

```text
hechos que hacen imposible el agarre
≠
evidencia que vuelve más o menos probable el agarre
```

## División provisional de responsabilidades

Esto es una propuesta para discutir, no una decisión cerrada.

### Requisitos duros posibles

Un candidato no podría avanzar si falta alguno de estos hechos:

- el player está en el aire (`en_piso: false`);
- existe una relación coherente entre pared y borde superior;
- la pose propuesta de Hanging cabe físicamente;
- la intención del player no es contradictoria con entrar al borde.

### Evidencia de certeza posible

Estos datos podrían aumentar o reducir la certeza sin invalidar un candidato
por sí solos:

- cuántas muestras de rayos coinciden en la misma pared;
- si un volumen frontal también respalda esa pared;
- si una búsqueda inversa confirma la misma tapa;
- dirección y velocidad reales de acercamiento;
- dirección de cámara respecto del borde;
- un contacto físico reciente con la pared.

La distinción evita dos extremos: ni una sola sonda decide todo, ni un borde
correcto se pierde porque una fuente secundaria no lo vio.

## Flujo conceptual posible

```text
providers geométricos y físicos publican hechos crudos
→ Hanging agrupa los hechos que podrían describir el mismo borde
→ comprueba los requisitos duros
→ registra coincidencias, ausencias y contradicciones como evidencia
→ publica candidato explicable + certeza contextual
→ árbitro compara candidatos válidos
→ capa física vuelve a validar la pose al entrar
```

El flujo no implica que las fuentes corran con la misma frecuencia ni que
todas existan desde el primer prototipo. Sólo deja claro el lugar que ocuparía
cada una si se incorpora.

## Preguntas que siguen abiertas

1. ¿Qué fuentes se construyen para el primer laboratorio y cuáles se dejan
   para comparar más adelante?
2. ¿Una corroboración de `ShapeCast` será sólo evidencia o puede bloquear un
   candidato en algún caso concreto?
3. ¿Qué grado de desacuerdo entre pared, tapa y volumen significa “geometría
   incoherente” y debe ser rechazo duro?
4. ¿El contacto físico reciente sólo suma certeza, o habrá situaciones donde
   sea requisito de entrada?
5. ¿Cómo se mostrará en debug cada fuente, su peso y el motivo exacto de un
   rechazo?

No se deben decidir todavía cantidades de rayos, posiciones, fórmulas de
certeza ni APIs de Godot. Primero hace falta resolver esta frontera: qué datos
son condiciones físicas indispensables y cuáles sólo ayudan al sistema a
interpretar la intención del jugador.
