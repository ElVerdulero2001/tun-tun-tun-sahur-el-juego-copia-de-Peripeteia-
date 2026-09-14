# Comparación aislada P0 — Locomoción pura (V1 vs V2)

> D1 + P0 de `Parkour V2 - Prototipo de Comparación Aislada V0.6`. Objetivo único: comparar caminar,
> correr, saltar, agacharse, control aéreo e inercia — sin que hanging, mantle, shimmy, escalera ni
> DIRECT_MANTLE puedan intervenir en ninguno de los dos sistemas.
>
> No se anota "anda"/"no anda". Cada fila necesita una descripción concreta de lo que pasó. Si algo no
> se puede probar, se anota así, no se deja en blanco ni se inventa un resultado.

## Cómo abrir cada escena

- **V1**: worktree `C:\Users\ElCaido97\Documents\tun-tun-tun-sahur-v1-reference`, escena
  `scenes/test/v1_comparison_p0.tscn`.
- **V2**: repo principal `C:\Users\ElCaido97\Documents\tun-tun-tun-sahur`, escena
  `scenes/test/v2_comparison_p0.tscn`.

Mismos controles en las dos: `WASD` mover, `Espacio` saltar, `Shift` correr, `Ctrl` agachar.

## Geometría (idéntica en las dos escenas)

Solo Zona A (pasillo con caja baja, obligatoria, bloquea todo el ancho) y Zona E (pozo de salto largo,
~6 m de vacío, sin nada para engancharse). Mismas coordenadas de mundo en ambas escenas. Nada de bordes,
paredes, escalera ni geometría preparada para agarrarse — a propósito, es la forma en que esta comparación
bloquea el traversal sin tocar lógica (ver más abajo).

**Nota sobre el punto de aparición**: el jugador arranca en la misma posición física (mismo X/Z, apoyado
justo arriba del piso) en las dos escenas, pero el número de altura de spawn no es idéntico entre los dos
`.tscn` a propósito — V1 mide su posición desde el CENTRO de la cápsula, V2 la mide desde los PIES. Es una
diferencia de convención de cada motor, no una diferencia de comportamiento a registrar.

## Cómo se bloqueó el traversal (para que quede documentado, no es magia)

- **V1**: no se tocó ningún script. La única geometría presente (la caja de Zona A) es demasiado baja
  para calificar como borde agarrable con la aritmética real del detector, y no hay ningún nodo del grupo
  `"ladder"` en la escena — el detector de V1 simplemente nunca encuentra un candidato válido de ningún
  tipo. Confirmado por lectura de `parkour_detector.gd` y por una corrida headless de 120 frames sin
  errores.
- **V2**: tampoco se tocó ningún script de producción. `PlayerMotor` no tiene ninguna referencia dura a
  `TraversalController` ni a `TraversalDetector` — mientras no exista un `TraversalLease` activo, corre
  `_locomocion_normal()` sin más. La escena de comparación arma un `Body` mínimo con el script real
  `player_motor.gd` pero sin instanciar esos dos nodos, así que un lease nunca se crea. Confirmado por
  lectura de `player_motor.gd` y por una corrida headless de 120 frames sin errores.

Ninguna de las dos soluciones agregó un flag, un gate ni ningún código nuevo. El comportamiento por
defecto del juego real (fuera de estas dos escenas) no se tocó en absoluto.

---

## Pruebas

### 1. Caminar

| | V1 | V2 |
|---|---|---|
| Cómo probar | Caminar en línea recta unos metros, sin correr | igual |
| Resultado observable | *(completar)* | *(completar)* |

### 2. Correr

| | V1 | V2 |
|---|---|---|
| Cómo probar | Sostener Shift y correr en línea recta | igual |
| Resultado observable | *(completar)* | *(completar)* |

### 3. Frenar

| | V1 | V2 |
|---|---|---|
| Cómo probar | Corriendo a velocidad máxima, soltar todo input de golpe | igual |
| Resultado observable | *(completar)* | *(completar)* |

### 4. Salto quieto

| | V1 | V2 |
|---|---|---|
| Cómo probar | Parado, sin moverse, saltar | igual |
| Resultado observable | *(completar)* | *(completar)* |

### 5. Salto corriendo

| | V1 | V2 |
|---|---|---|
| Cómo probar | Correr y saltar sin frenar antes | igual |
| Resultado observable | *(completar)* | *(completar)* |

### 6. Crouch

| | V1 | V2 |
|---|---|---|
| Cómo probar | Agacharse parado, y agacharse en movimiento | igual |
| Resultado observable | *(completar)* | *(completar)* |

### 7. Salto largo — Zona E

| | V1 | V2 |
|---|---|---|
| Cómo probar | Tomar carrera (Shift) antes del pozo y saltar al filo; repetir caminando (sin Shift) | igual |
| Resultado observable | *(completar)* | *(completar)* |

### 8. Corrección lateral en el aire

| | V1 | V2 |
|---|---|---|
| Cómo probar | Saltar y, en pleno vuelo, mover el input lateral — probar tanto con poca velocidad horizontal como viniendo de una corrida a fondo | igual |
| Resultado observable | *(completar)* | *(completar)* |

### 9. Inercia en el aire (sin input)

| | V1 | V2 |
|---|---|---|
| Cómo probar | Saltar y soltar todo input en el aire — comparar cuánto tarda en perder la velocidad horizontal; repetir cayéndose de un borde sin haber saltado (usar el borde de la Zona E) | igual |
| Resultado observable | *(completar)* | *(completar)* |

---

## Diferencias encontradas

*(Completar solo después de correr ambas escenas. Una diferencia se anota con el número de prueba, qué
se vio en cada lado, y si se puede explicar por una constante conocida — ej. `RUN_SPEED` 9.0 en V1 vs 8.0
en V2 — o si queda sin explicación.)*

| Prueba # | V1 | V2 | Diferencia / explicación |
|---|---|---|---|
| | | | |

## Conclusión del jugador

*(No completar con "anda"/"no anda". Un párrafo real sobre si el movimiento base se siente igual, y si no,
en qué se nota.)*

---

**Este documento no cierra P0.** Falta que el jugador corra ambas escenas y complete los campos. Ninguna
constante de locomoción, de `PlayerMotor` ni de `MovementController` se tocó para armar esto.
