# V3 Hanging — mapa técnico del laboratorio de detección

## Estado y frontera

Este documento describe la primera rebanada **implementada** de Hanging. Su
único trabajo es observar una cornisa, construir un candidato explicable y
validar hipotéticamente que la pose propuesta cabe.

No hay todavía Hanging activo. El candidato no toma gobierno, no mueve el
`CharacterBody3D`, no hace snap y no modifica H0. Mientras se prueba este
laboratorio, H0 sigue siendo la única autoridad física.

La escena es `scenes/test/v3_hanging_detection_lab.tscn`. Instancia el
laboratorio H0 existente y le agrega una cornisa de práctica y observadores de
Hanging; por eso no cambia la escena principal ni rompe el laboratorio H0.

## Escena y nodos

```text
V3HangingDetectionLab
├─ H0Lab                              instancia de v3_h0_lab.tscn
│  └─ PlayerH0Lab/Body                V3PhysicsBody real
│     ├─ InputSource                  fuente compartida de input
│     ├─ CameraRig                    fuente compartida de cámara
│     └─ H0                           gobernador físico actual
├─ PracticeLedge                      bloque estático bajo de práctica
│  ├─ Mesh
│  └─ Collision
├─ HangingDetector                    observa y publica candidato
└─ HangingDebugCanvas/HangingDebug    sólo muestra la lectura
```

`PracticeLedge` mide `3 × 1.5 × 0.6 m` y está centrada en `(0, 0.75, 0)`.
El player viene desde el eje Z positivo, por lo que su cara frontal es una
pared accesible y su parte superior queda a `y = 1.5`.

## Piezas de código

| Pieza | Archivo | Responsabilidad |
|---|---|---|
| Candidato | `v3_hanging_candidate.gd` | Guarda borde, normal, pose, evidencia, validez y motivos de rechazo. Es un dato; no contiene movimiento. |
| Detector | `v3_hanging_detector.gd` | Hace las consultas geométricas, asocia pared+borde, revisa las condiciones duras y publica `last_candidate`. |
| Consulta física común | `v3_physics_body.gd` | Expone `can_occupy_pose(pose)`, que usa `test_move()` sin mover ni cambiar velocidad. |
| Debug Hanging | `v3_hanging_debug_overlay.gd` | Lee el detector y dibuja texto; no altera input, H0 ni física. |
| Laboratorio | `v3_hanging_detection_lab.tscn` | Une H0, la cornisa, detector y debug. |
| Smoke test | `v3_hanging_detection_smoke_test.gd/.tscn` | Comprueba los casos de piso, aire neutro e intención contradictoria. |

## Orden real del tick

La prioridad del detector es `150`; lee después de que el body haya aplicado
el movimiento normal de H0.

```text
prioridad -200      InputSource lee controles
prioridad  -50      FallDamageState consume caída anterior
prioridad    0      H0 publica intención de locomoción normal
prioridad  100      V3PhysicsBody aplica esa intención y publica hechos reales
prioridad  150      HangingDetector observa esos hechos y la geometría actual
prioridad  200      CameraRig acompaña visualmente la postura física
después, visual      H0Debug y HangingDebug muestran datos
```

Por ahora el candidato sólo queda disponible para lectura en el tick siguiente.
Todavía no existe árbitro que lo compare ni una orden para sustituir la
intención de H0.

## Flujo de lectura y candidato

```text
posición/velocidad/apoyo del body + input + cámara
        ↓
grilla de rayos hacia adelante: impactos de pared
        ↓
rayo descendente por pared: posible tapa/borde
        ↓
consulta volumétrica frontal: evidencia adicional
        ↓
HangingDetector asocia pared y borde coherentes
        ↓
clasifica intención + arma pose hipotética
        ↓
V3PhysicsBody.can_occupy_pose() comprueba la cápsula real
        ↓
V3HangingCandidate publicado en debug
```

### Lecturas “tontas” y evaluación

Las consultas individuales no activan nada ni cambian el body:

- `_query_wall()` devuelve un impacto de rayo o nada;
- `_find_edge_for_wall()` devuelve una relación geométrica pared+tapa o nada;
- `_query_front_volume()` devuelve colliders dentro del volumen frontal;
- `can_occupy_pose()` responde solamente si el collider actual cabría en una
  transformación hipotética.

En esta primera rebanada esas funciones viven juntas dentro de
`V3HangingDetector` para poder radiografiar el circuito en una sola escena. La
interpretación que asocia los hechos y publica `V3HangingCandidate` es la
capa específica de Hanging; las consultas de física no conocen ese concepto.

## Parámetros actuales de laboratorio

Son valores heredados o cercanos a los usados como referencia en V1/V2. Sirven
para observar el comportamiento; no son balance ni contrato final.

| Parámetro | Valor |
|---|---:|
| Alturas de rayos frontales | `0.3, 0.6, 0.9, 1.2, 1.5 m` |
| Alcance frontal | `0.85 m` |
| Altura de borde mínima/máxima | `0.5 / 1.5 m` |
| Inclinación máxima de pared/tapa | `30°` |
| Tolerancia lateral pared ↔ borde | `0.35 m` |
| Separación de la pose respecto de pared | `0.68 m` |
| Offset vertical temporal de pose | `-0.55 m` |
| Volumen frontal | `0.7 × 1.2 × 0.85 m` |
| Umbral temporal para intención | `0.2` de alineación |

La pose propuesta usa la normal de pared para mirar hacia ella, el borde como
referencia y los dos offsets de pose anteriores. Es una pose de **consulta**:
todavía no es el formato definitivo del cuerpo colgado ni una orden física.

## Requisitos duros ya ejecutados

Para publicar `is_valid = true`, el detector requiere:

1. una pared razonablemente vertical delante;
2. una tapa razonablemente horizontal;
3. coherencia lateral entre el punto de pared y el punto de borde;
4. altura del borde dentro del rango temporal;
5. `en_piso = false`;
6. intención distinta de `contradictoria`;
7. que `can_occupy_pose()` responda que la cápsula cabe.

La ausencia de `ShapeCast` o de una coincidencia volumétrica no invalida el
candidato. El volumen sólo aporta evidencia.

Los rechazos que el debug puede expresar hoy son:

| Motivo | Significado |
|---|---|
| `referencias_incompletas` | Faltan body, input o cámara; fue el primer bug de integración y se corrigió en la escena. |
| `sin_pared_y_borde_coherentes` | No se pudo formar una relación válida de pared+tapa dentro de los filtros actuales. |
| `en_piso` | La geometría existe, pero el contrato prohíbe entrar a Hanging desde apoyo. |
| `intencion_contradictoria` | La dirección activa aleja del borde propuesto. |
| `pose_bloqueada` | La cápsula actual no cabe en la pose propuesta. |

Los submotivos internos de una relación geométrica fallida —altura fuera de
rango, inclinación o tolerancia lateral— todavía se agrupan bajo
`sin_pared_y_borde_coherentes`. Desglosarlos en debug es una mejora futura;
no cambia la lógica actual.

## Intención y evidencia local

El detector transforma el eje de movimiento usando las mismas direcciones
planas de cámara que H0. Luego compara esa dirección con la dirección hacia la
pared propuesta:

```text
sin input                         → neutra
input hacia la pared/borde        → compatible
input activo alejándose del borde → contradictoria (rechazo duro)
```

`local_evidence_score` es sólo telemetría temporal del detector. No es la
certeza contextual normalizada de V3 ni participa todavía en un árbitro. Hoy
combina, con clamp entre 0 y 1:

```text
proporción de rayos que tocaron pared × 0.50
+ alineación frontal con la pared × 0.25
+ ShapeCast que respalda la pared × 0.15
+ intención compatible × 0.10
```

Con intención neutra, tres rayos sobre cinco, alineación `1.0` y volumen que
respalda la pared, la telemetría resulta `0.70`; es el caso validado en el
laboratorio.

## Debug visible

`HangingDebug` muestra en cada frame visual:

- cantidad de rayos que tocaron pared;
- cantidad de colliders del volumen y si respaldan la pared elegida;
- punto de borde, normal de pared y altura relativa;
- intención, alineación y evidencia local;
- origen de la pose propuesta y resultado de `can_occupy_pose()`;
- candidato válido/rechazado y los motivos;
- el recordatorio de que todavía no hay árbitro ni entrada física.

La validación manual ya confirmó dos estados visibles:

```text
frente a la cornisa en piso
→ pared/borde/pose aparecen, pero rechazo: en_piso

saltando frente a la misma cornisa
→ en_piso false + pose libre + intención neutra
→ candidato Hanging: VÁLIDO
```

## Cobertura automática

`v3_hanging_detection_smoke_test.tscn` instancia el laboratorio y contiene
aserciones para:

- detectar la pared de práctica desde piso y rechazar por `en_piso`;
- publicar candidato válido en aire con input neutro y pose libre;
- clasificar `move_back` como intención contradictoria y rechazarla.

## Lo que no existe todavía

- árbitro ni distribución real de certezas entre cores;
- transferencia de autoridad `H0 → Hanging`;
- entrada física/snap, inmovilización, gravedad específica o collider de
  Hanging activo;
- soltar, salto desde Hanging, shimmy, extremos o esquinas;
- búsqueda inversa desde tapa, soporte móvil y contacto reciente como fuente;
- visualización 3D de las líneas/volúmenes; el debug actual es textual;
- valores de gameplay aprobados o una forma definitiva de la pose de Hanging.

El próximo cambio de implementación debe respetar esta frontera: un candidato
válido no equivale todavía a un core ejecutándose.
