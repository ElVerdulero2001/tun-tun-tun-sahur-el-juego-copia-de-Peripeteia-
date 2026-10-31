# V3.2 — cuatro modelos posibles

## Punto de partida

Se descarta `H0 → Core → H0` como estructura central.

Ese esquema sirve cuando una acción puede empezar y terminar sin dejar continuidad que el comportamiento normal deba entender. Hanging no cumple eso: al soltar, el personaje puede conservar consecuencias de haber estado colgado hasta que algo físico las termine. Por lo tanto, entrar y volver a H0 como si todo arrancara limpio pierde información necesaria.

Este documento no elige una solución. Solo separa cuatro formas distintas de organizar el problema.

---

## 1. Máquina de estados

El personaje está en **un estado principal por vez**.

```text
Suelo ↔ Aire ↔ Hanging
```

Cada estado define qué controla, y los cambios entre estados son explícitos.

### Cómo sería hanging

- `Hanging` controla cuerpo, entrada y gravedad mientras está activo.
- Al soltar o saltar, ocurre una salida explícita hacia `Aire`.
- `Aire` recibe el contexto de salida que necesite y lo conserva hasta que una condición física lo cancele.

### Ventaja

La autoridad es clara: solo un estado principal manda. Es fácil responder “¿quién controla esto ahora?”.

### Costo

Las salidas y entradas son parte obligatoria del diseño. No se puede evitar definirlas, porque este modelo vive de las transiciones.

### Cuándo encaja

Cuando suelo, aire y hanging son comportamientos mutuamente excluyentes y completos.

---

## 2. Motor base + modificadores

El motor normal corre siempre. Hanging no reemplaza el motor: modifica partes concretas de él.

```text
motor base
  + modificador hanging
  + modificador de salida de hanging (si corresponde)
```

En este modelo H0 no es un estado al que se vuelve. Es el cálculo normal que existe en todos los frames.

### Cómo sería hanging

- El motor base calcula el movimiento normal.
- Mientras hay hanging, un modificador bloquea o reemplaza los aspectos necesarios: gravedad, movimiento, posición, orientación, etc.
- Al salir, ese modificador se retira.
- Si debe sobrevivir una consecuencia de la salida, existe otro modificador temporal cuya condición de fin es física.

### Ventaja

No existe el salto `H0 → Core → H0`; el comportamiento normal nunca desaparece ni se reinicia.

### Costo

Hay que definir con precisión qué modifica cada capa y qué pasa si dos modificadores quieren tocar el mismo aspecto. Si eso queda implícito, reaparece la confusión con otro nombre.

### Cuándo encaja

Cuando hanging es una alteración localizada del movimiento normal, no un personaje completamente distinto.

---

## 3. Autoridad por prioridades

Los sistemas no se reemplazan entre sí. Cada uno propone control sobre aspectos concretos, y un resolvedor decide cuál gana.

```text
motor base ──────── pide control de movimiento aéreo
hanging ─────────── pide control de posición y gravedad
salida de hanging ─ pide control aéreo especial
resolver ────────── elige por aspecto y prioridad
```

### Cómo sería hanging

- Hanging reclama autoridad sobre los aspectos que necesita mientras está activo.
- Al soltar, libera esas reclamaciones.
- La salida de hanging puede reclamar solo control aéreo hasta que ocurra la condición física de fin.

### Ventaja

Permite que cada comportamiento diga exactamente qué controla, sin convertir todo en un único estado gigante.

### Costo

El resolvedor pasa a ser una pieza central y delicada. Hay que diseñar prioridades, empates y reglas de combinación. Puede crecer rápido y esconder la causa de un resultado.

### Cuándo encaja

Cuando varios sistemas independientes necesitan influir simultáneamente sobre distintos aspectos del cuerpo.

---

## 4. Restricciones físicas

El centro del modelo no es un “modo” sino las restricciones físicas actuales del cuerpo.

```text
contactos + velocidad + geometría + restricciones
  → movimiento resultante
```

Hanging se representa como una restricción: el cuerpo queda sujeto a una posición, superficie o relación geométrica. Soltar elimina esa restricción y el cuerpo continúa según la física.

### Cómo sería hanging

- Detectar una geometría válida crea una restricción de agarre.
- Mientras existe, limita el cuerpo según esa restricción.
- Soltar o saltar la elimina y aplica, si corresponde, una velocidad o impulso definido.
- Suelo, paredes y velocidades posteriores determinan qué ocurre después.

### Ventaja

Es muy directo para explicar agarre, liberación, impulso y contacto: se piensa en qué fuerzas o límites existen ahora.

### Costo

La física no sabe por sí sola la intención del jugador, las reglas de animación ni todas las excepciones de diseño. Seguirán existiendo decisiones de juego alrededor de las restricciones.

### Cuándo encaja

Cuando hanging debe sentirse principalmente como una interacción corporal con una superficie y no como una habilidad abstracta.

---

## Comparación corta

| Modelo | Pregunta central | Riesgo principal |
|---|---|---|
| Máquina de estados | ¿En qué modo está el personaje? | Grafo de transiciones grande |
| Motor + modificadores | ¿Qué altera al movimiento normal ahora? | Conflictos entre capas |
| Autoridad por prioridades | ¿Quién manda en cada aspecto? | Resolvedor complejo |
| Restricciones físicas | ¿Qué limita físicamente al cuerpo? | Falta de reglas de juego explícitas |

La decisión de V3.2 debería empezar por una sola pregunta: **¿hanging cambia al personaje entero, altera el movimiento normal, compite con otros controladores o sujeta físicamente al cuerpo?**
