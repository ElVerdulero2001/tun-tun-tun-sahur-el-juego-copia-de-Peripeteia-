# V3 Hanging — estado real del laboratorio de entrada

> **Documento de radiografía.** Describe el código que existe hoy, con sus
> atajos y limitaciones. No reemplaza ni modifica los documentos de diseño de
> V3. En particular, no vuelve oficial la forma actual de `P`, del cilindro ni
> del snap.

> **Actualización — interacción aislada.** La escena ya no instancia
> `HangingEntryLab`: no hay snap, retención de `P` ni cambio de gobierno.
> La interacción activa termina al publicar el contacto actual `S entra en C`.
> `P` y `submit_pose_snap()` se conservan fuera del flujo como referencia de
> laboratorio y el debug puede mostrarlos, pero no pueden rechazar un
> candidato ni mover al player.

## Por qué existe este documento

La implementación de entrada a Hanging fue cambiando durante el laboratorio:

```text
esfera en P + cápsula completa
        ↓ descartado
dos esferas C/S
        ↓ descartado
cilindro C en el borde + esfera S en hombros
        ↓ estado actual
snap temporal y retención de P para inspección
```

El código actual sirve para observar y tocar parámetros, pero mezcla una
lectura válida de Hanging con un ejecutor temporal de prueba. Este documento
separa explícitamente qué hace cada pieza y qué no debe tomarse todavía como
arquitectura final.

## Vocabulario actual

| Símbolo | Nombre | Qué es hoy |
|---|---|---|
| `E` | borde | Punto superior detectado de una pared válida. |
| `N` | normal de pared | Dirección exterior de la pared detectada. |
| `C` | cilindro rosa | Volumen de captura que nace en `E` y se proyecta hacia afuera en dirección `N`. |
| `S` | esfera azul | Sensor virtual, fijo al body a una altura local de hombros. |
| `P` | pose propuesta | Transform del root del body usado como destino del snap de prueba. |

`C` y `P` son dos cosas diferentes. `C` decide el momento de entrada;
`P` decide dónde se coloca el body si el laboratorio acepta esa entrada.

## Nodos y responsabilidades

```text
V3HangingDetectionLab
├─ H0Lab/PlayerH0Lab/Body        V3PhysicsBody: única capa que mueve el body
│  ├─ H0                         locomoción normal mientras no hay snap
│  ├─ InputSource                input compartido
│  └─ CameraRig                  cámara compartida
├─ PracticeLedge                 bloque fijo de prueba
├─ HangingDetector               lee pared/borde y publica candidato + E/N/C/P
├─ HangingCaptureProbe           dibuja C/S y mide si S entra en C
├─ HangingEntryLab               ejecutor temporal que conserva P tras contacto
└─ HangingDebug                  observador textual
```

| Pieza | Archivo | Dueño de |
|---|---|---|
| Datos de candidato | `scripts/player_v2/parkour_v3/v3_hanging_candidate.gd` | Hechos geométricos, `C`, `P`, validez y rechazos. |
| Detector | `scripts/player_v2/parkour_v3/v3_hanging_detector.gd` | Detectar `E/N`, construir `C` y la `P` temporal. No mueve al player. |
| Sonda de captura | `scripts/player_v2/parkour_v3/v3_hanging_capture_probe.gd` | Visualizar cilindro/esfera y responder si hay contacto en el tick actual. No decide ni mueve. |
| Ejecutor de entrada | `scripts/player_v2/parkour_v3/v3_hanging_entry_lab.gd` | Aceptar temporalmente el contacto, guardar una `P` y pedir su snap. |
| Física común | `scripts/player_v2/parkour_v3/v3_physics_body.gd` | Aplicar `submit_pose_snap()`; es la única que modifica el `CharacterBody3D`. |

## Orden del tick relevante

```text
-200  InputSource
  -50  FallDamageState
    0  H0 publica locomoción normal
  100  V3PhysicsBody aplica H0 o un snap pendiente
  150  HangingDetector publica candidato actual
  175  HangingCaptureProbe actualiza C/S y su contacto actual
  176  HangingEntryLab solicita/retiene P si corresponde
  200  CameraRig actualiza presentación de cámara
```

Como `HangingEntryLab` observa después de física, un snap que solicita en el
tick actual se aplica en el tick físico siguiente. Esto es intencional en el
laboratorio y evita que detector o sonda muevan al body directamente.

## Cómo se construye el candidato actual

`HangingDetector` sigue haciendo la detección ya existente: rayos de pared,
rayo descendente a tapa, evidencia volumétrica, intención y consulta de pose.
Para que `candidate.is_valid` sea verdadero siguen siendo obligatorios:

- pared y borde coherentes;
- player en aire (`en_piso = false`);
- intención no contradictoria;
- `P` físicamente ocupable en la lectura actual.

Una vez que hay geometría de borde, el detector publica además:

```text
C_ancla = E - UP × capture_drop_from_edge
P       = E + N × hang_wall_gap + UP × hang_root_offset_y
```

Valores actuales del detector:

| Parámetro | Valor actual | Afecta |
|---|---:|---|
| `capture_drop_from_edge` | `0.20 m` | Baja el nacimiento de `C` bajo el borde. |
| `hang_wall_gap` | `0.68 m` | Aleja/acerca `P` de la pared. |
| `hang_root_offset_y` | `-2.00 m` | Sube/baja el **root** de `P`. El laboratorio usa el default del script; no tiene override de escena. |

La pose `P` actual nació como pose hipotética para `can_occupy_pose()`. No fue
calibrada todavía como postura visual de Hanging. Que `P` "quepa" sólo prueba
ausencia de penetración; no prueba que el player parezca colgado.

## Cilindro rosa C

El ancla `C_ancla` está en el borde. `HangingCaptureProbe` arma el cilindro
desde ahí, en la dirección exterior `N`:

```text
centro del cilindro = C_ancla + N × (largo / 2)
eje del cilindro    = N
```

Por lo tanto el cilindro nace en el borde y sobresale hacia el lado libre de
la pared. No depende de la cámara ni de `P`.

Valores actuales del laboratorio:

| Parámetro | Valor actual | Efecto |
|---|---:|---|
| `capture_cylinder_radius` | `0.15 m` | Grosor vertical/lateral del cilindro. El laboratorio usa el default del script; no tiene override de escena. |
| `capture_cylinder_length` | `0.80 m` | Cuánto sobresale hacia afuera. Este valor se ajustó manualmente en playtest. |

El cilindro sólo se dibuja y se considera activo si el candidato actual es
válido. No tiene `CollisionShape3D`, no bloquea al player y no es visible para
otros sistemas.

> **Fuente de verdad actual:** los parámetros de este laboratorio viven en los
> defaults de sus scripts; se eliminaron los overrides de escena que competían
> con ellos. Si se cambia un export durante una ejecución, ese cambio sólo
> afecta esa instancia hasta que se guarde explícitamente una nueva decisión.

## Esfera azul S

La esfera azul representa una zona corporal simplificada del player. Está
unida al body, no a la cámara renderizada:

```text
centro S = transform global del body × (0, shoulder_height, 0)
```

No cambia al mirar arriba/abajo ni al alejar la cámara en tercera persona. La
cámara puede participar en la intención del candidato, pero no mueve `S`.

Valores actuales:

| Parámetro | Valor actual | Efecto |
|---|---:|---|
| `shoulder_height` | `1.30 m` | Altura local del centro de S. |
| `shoulder_sensor_radius` | `0.10 m` | Tamaño de S; se redujo para que no active desde lejos. |

La altura de S sólo cambia el momento de contacto con `C`. No modifica `P`,
el snap ni la cámara. Su calibración exacta con hombros/cabeza/ojos sigue
abierta: hoy es un valor de laboratorio, no una representación anatómica
aprobada.

## Qué significa “S entra en C”

La sonda no usa posición anterior ni historial. En cada tick calcula la
distancia de la esfera azul al volumen de un cilindro finito rosa:

```text
distancia de S al sólido C <= radio de S
        ↓
last_sensor_enters_cylinder = true
```

Eso acepta que la esfera azul entre apenas un poco en el cilindro. Si no hay
contacto, el debug muestra un solapamiento negativo; si ya entró, el
solapamiento es cero o positivo.

La lectura `S entra C` todavía no es una orden oficial de V3 ni una decisión
del árbitro. Es el gatillo temporal del laboratorio.

## Snap temporal y por qué confunde el ajuste de P

Cuando, en el mismo tick, se cumplen estas condiciones:

```text
candidato válido
+ S entra en C
+ P sigue siendo ocupable
```

`HangingEntryLab` hace lo siguiente:

1. copia `candidate.pose` en `held_pose`;
2. marca `is_holding_pose = true`;
3. llama a `V3PhysicsBody.submit_pose_snap()`;
4. en el siguiente tick físico, `V3PhysicsBody` mueve el root a `held_pose`;
5. en los ticks posteriores, el ejecutor vuelve a solicitar ese mismo snap
   para mantener al player quieto y poder mirar la pose.

Esta retención tiene una consecuencia importante:

> Una vez que aparece `retiene P: true`, cambiar `hang_root_offset_y` o
> `hang_wall_gap` **no modifica al player ya capturado**. Esos parámetros sólo
> afectarán una entrada nueva, tras reiniciar la escena o liberar la prueba.

No existe todavía una orden de liberar la retención. Reiniciar la escena es
la única forma actual de probar otra `P`. Es una carencia de laboratorio,
no una regla de gameplay.

## Qué hace V3PhysicsBody durante el snap

`V3PhysicsBody` recibió una API nueva:

```gdscript
submit_pose_snap(source, target_pose)
```

El solicitante no escribe `global_transform` directamente. En el tick físico
siguiente, si la pose sigue ocupable, `V3PhysicsBody`:

- coloca su `global_transform` en la pose solicitada;
- pone `velocity` en cero;
- ignora esa intención de locomoción de H0 para ese tick;
- publica que el snap fue aplicado.

Esto respeta la frontera de que la capa física común es la única que mueve al
body. Aun así, el uso continuo de esta API por `HangingEntryLab` es una
retención de prueba, no el comportamiento final de un core Hanging.

## Debug que existe hoy

`HangingDebug` muestra:

- rayos, volumen, borde, normal, intención y razones de candidato;
- `C_ancla`, `P` y si `P` cabe;
- centro/radio/largo del cilindro rosa;
- centro/radio de la esfera azul;
- distancia de S al cilindro y si entró;
- razón del ejecutor temporal y si retiene P.

El texto mezcla aún etiquetas viejas como “detección solamente” con la entrada
temporal. Es una inconsistencia conocida del debug actual.

## Cobertura automática actual

`scenes/test/v3_hanging_detection_smoke_test.tscn` cubre:

1. borde detectado desde el piso, pero rechazo por `en_piso`;
2. candidato aéreo válido con intención neutra;
3. rechazo por intención de alejarse;
4. contacto de `S` con `C`;
5. activación de retención temporal;
6. snap aplicado por `V3PhysicsBody` a la `P` retenida.

## Límites y deuda explícita

Nada de esta lista debe resolverse agregando más parches al flujo actual:

1. **P no está validada como postura de Hanging.** Sólo fue validada como
   pose sin choque. Altura, separación de pared, cámara y orientación final
   siguen sin decidir.
2. **La retención guarda una verdad vieja.** Esto es útil para mirar una P de
   prueba, pero contradice la filosofía normal de releer hechos tick a tick.
   No puede sobrevivir igual al laboratorio.
3. **No hay liberación ni salida.** Reiniciar escena no es un diseño de juego.
4. **No hay core Hanging activo real.** No hay movimiento colgado, gravedad,
   shimmy, salto, caída, animación ni transferencia formal de gobierno.
5. **No hay árbitro.** El ejecutor acepta Hanging porque es el único core
   contextual de esta prueba.
6. **La esfera azul y el cilindro rosa sólo son hipótesis de feeling.** Sus
   dimensiones no son contrato final.
7. **La cámara y la tercera persona no están resueltas en esta entrada.** S
   es independiente de la cámara por decisión; la presentación de tercera
   persona todavía no existe en este laboratorio.

## Frontera recomendada para el próximo paso

Antes de implementar más Hanging, hay que elegir una sola tarea:

```text
A. limpiar el laboratorio de entrada y hacer su tuning explícito;
o
B. validar y redefinir P como postura de Hanging.
```

No conviene avanzar a movimiento colgado, salidas o árbitro mientras `P` y el
ciclo de retención temporal siguen ambiguos.
