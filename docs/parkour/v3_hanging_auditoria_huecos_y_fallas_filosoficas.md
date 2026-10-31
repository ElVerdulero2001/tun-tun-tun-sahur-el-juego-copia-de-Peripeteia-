# V3 Hanging — auditoría de huecos antes de continuar

> **Estado:** corte de implementación. Este documento describe el estado real
> del laboratorio al 2026-09-18 y lo contrasta con los fundamentos ya
> acordados de V3. No autoriza una nueva implementación ni elige soluciones
> técnicas para los huecos.

> **Actualización — separación de providers:** el detector compuesto citado
> originalmente en esta auditoría fue reemplazado por `ForwardWallProbe`,
> `TopSurfaceProbe`, `FrontVolumeProbe` y `HangingCandidateEvaluator`. Las
> sondas ya sólo publican lecturas crudas; la interpretación quedó en el
> consumidor de Hanging. Los demás huecos descritos aquí siguen bloqueando
> avance de la interacción.

> **Limpieza aplicada:** la ruta temporal `cilindro/esfera → P → EntryLab → snap` fue
> retirada por completo, junto con su API física. Las secciones que la
> describen conservan la evidencia del problema que motivó el retiro; ya no
> describen código activo. El mapa técnico actual es
> `v3_hanging_laboratorio_mapa_tecnico.md`.

## Alcance

La auditoría cubre la ruta que existe hoy en el laboratorio:

```text
lectura de pared/borde → candidato Hanging → cilindro/esfera → retención de P → snap
```

No evalúa todavía shimmy, saltos de Hanging, mantle, Ladder ni tercera persona
como mecánicas completas. Tampoco cuestiona que sean futuros temas: el punto
es determinar si la entrada actual puede seguir creciendo sin traicionar la
filosofía de V3.

Las referencias de diseño usadas son `v3_idea_base.md`,
`v3_autoridad_movimiento_propuesta.md`,
`v3_hanging_contrato_borrador.md`,
`v3_hanging_deteccion_propuesta.md` y `PARKOUR_SYSTEM_ARCHITECTURE.md`.

## Radiografía honesta: qué existe ahora

El laboratorio tiene cuatro piezas principales:

| Pieza real | Hace hoy | No es todavía |
| --- | --- | --- |
| `V3HangingDetector` | Lee rayos/volumen, agrupa pared y borde, calcula `E`, `N`, `C`, `P`, intención y un candidato. | Un provider neutral ni un core Hanging activo completo. |
| `V3HangingCaptureProbe` | Dibuja y mide el contacto actual entre el cilindro `C` y la esfera corporal `S`. No guarda historial. | Una decisión de entrada ni una colisión física. |
| `V3HangingEntryLab` | Cuando cilindro/esfera entra y P cabe, guarda la `P` de ese instante y pide snap; luego la vuelve a pedir todos los ticks. | El core Hanging, el árbitro o una transición oficial. |
| `V3PhysicsBody` | Es el único que modifica el `CharacterBody3D`; aplica el snap solicitado. | Un contrato físico final para poses, trayectorias y resultados. |

El flujo efectivo depende del orden de prioridad de scripts: H0 publica una
intención, la física la aplica, luego se detecta Hanging, se lee cilindro/esfera y al final
el ejecutor temporal solicita un snap que se aplicará en el tick siguiente.
No existe todavía una decisión explícita de gobierno en ese flujo.

## Lo que sí está bien encaminado

No todo debe tirarse. Estas partes son compatibles con V3 y se pueden
conservar como evidencia de laboratorio:

- **La lectura cilindro/esfera es tonta y actual.** Sólo responde si la esfera corporal
  entra en el cilindro durante este tick. No recuerda una entrada anterior ni
  mueve al player.
- **La capa física sigue siendo la única escritora del body.** Ningún script
  de Hanging escribe por su cuenta `global_transform`, `velocity` o llama a
  `move_and_slide()`.
- **La detección explica sus motivos.** Pared, borde, normal, aire,
  intención, volumen y pose son visibles. Eso conserva la telemetría que V3
  necesita para ajustar el mundo 3D sin adivinar.
- **C y S no dependen de la orientación de cámara.** Para este mecanismo de
  captura corporal, eso coincide con la decisión ya tomada: la cámara puede
  ser información de intención en otras mecánicas, pero no debe mover el
  sensor corporal de Hanging.
- **Hay una escena técnica aislada.** El experimento no está contaminando una
  escena de gameplay.

El problema no es la existencia de C, S o P. El problema es qué los consume y
qué consecuencias tienen hoy.

## Fallas graves de filosofía

### 1. No existe un traspaso de gobierno: existe precedencia accidental

V3 dice que H0 gobierna por defecto y que, al ejecutar otro core, H0 deja de
emitir movimiento físico. Hoy H0 continúa corriendo normalmente. El snap de
`HangingEntryLab` simplemente tiene precedencia dentro de `V3PhysicsBody` y
descarta la intención que H0 ya había publicado.

Eso no expresa `H0 → Hanging`; expresa “un script tardío ganó este tick”. El
debug puede mostrar que la física recibió `HangingEntryLab`, pero el sistema
no posee un estado de core gobernante ni una concesión explícita de control.

**Consecuencia:** agregar Ladder, Mantle o cualquier otra entrada convertiría
el orden de ejecución y las prioridades de nodos en el árbitro real de V3.
Eso es exactamente lo que la arquitectura busca evitar.

### 2. No existe un ciclo de vida de Hanging ni una salida a H0

Una vez que `V3HangingEntryLab` guarda `held_pose`, la solicita para siempre.
No hay liberación voluntaria, pérdida de soporte, bloqueo físico, interrupción
externa ni devolución de gobierno a H0.

La regla V3 no es sólo que el core *entre* desde H0: también debe terminar en
H0. Sin esa mitad, ni siquiera se puede describir el estado actual como un
core temporal seguro; es una retención de diagnóstico.

### 3. La retención convierte una verdad de tick en una coordenada eterna

Se decidió expresamente que bordes, plataformas y demás soportes son
metaestables: se leen de nuevo mientras el core los necesita. El ejecutor
actual copia `candidate.pose` al entrar y conserva esa transform mundial como
`held_pose`.

Si el borde se mueve, rota, se destruye o deja de tener soporte, cilindro/esfera y el
detector pueden cambiar en los ticks posteriores, pero la retención ignora ese
cambio. Esto contradice directamente la regla “dato nuevo, verdad nueva”.

**Consecuencia:** no puede escalar a plataformas móviles ni a geometría que
cambie, y tampoco sirve como base de una entrada reactiva.

### 4. Resuelto parcialmente: las sondas ya no mezclan la interpretación

El antiguo `V3HangingDetector` se presentaba como provider, pero hacía las
tres cosas:

1. obtiene hechos geométricos con rayos y volumen;
2. interpreta esos hechos como *Hanging* (`borde coherente`, rango,
   intención contradictoria, `P`);
3. publica una candidata ya válida o rechazada.

Los puntos 2 y 3 pertenecen al consumidor/core Hanging; el punto 1 sí es
lectura neutral. Esta frontera ya fue corregida: `ForwardWallProbe`,
`TopSurfaceProbe` y `FrontVolumeProbe` publican hechos, y
`HangingCandidateEvaluator` interpreta Hanging.

El paso pendiente ya no es separar archivos, sino cerrar el contrato: qué
resultado del consumidor cuenta como candidato para el árbitro y qué parte de
la entrada sigue siendo sólo laboratorio.

### 5. Candidato válido, cilindro/esfera y P no tienen un contrato único

Hay tres “puertas” simultáneas y su relación cambió durante el laboratorio:

```text
candidato válido       ← geometría, aire e intención
cilindro/esfera entra               ← ventana corporal de captura
P cabe                  ← consulta de ocupación de la pose
```

El contrato de entrada dice que la pose libre es requisito duro del candidato.
El detector actual, en cambio, publica candidato válido aunque `pose_clear`
sea falso; la entrada temporal vuelve a exigir `pose_clear` y repite
`can_occupy_pose()`. La documentación técnica, además, contiene ambos estados
históricos: afirma que la entrada fue retirada y describe el ejecutor que hoy
está nuevamente instanciado.

**Consecuencia:** no está definido si P es parte de la posibilidad de
Hanging, una validación final de entrada o sólo un dato de debug. Mientras eso
no esté cerrado, modificar la altura de P, C o S puede cambiar reglas de
gameplay sin que sepamos cuál era la regla que se pretendía ajustar.

### 6. cilindro/esfera salta la selección contextual acordada

La filosofía V3 es:

```text
hechos → prerrequisitos del core → certeza contextual → árbitro → gobierno
```

Hoy cilindro/esfera, junto con P ocupable, entra directamente en el snap. No hay
distribución de certeza, umbral provisional, supresión con Ctrl ni árbitro.
Es aceptable para medir un gatillo de laboratorio, pero no puede presentarse
como entrada de Hanging ni crecer con más “if” hasta parecer una.

Además, `local_evidence_score` existe pero no participa de ninguna decisión:
es telemetría, no la certeza contextual prometida. Eso está bien si se etiqueta
como tal; sería un error tratarlo implícitamente como la predicción V3.

### 7. El snap actual no demuestra el contrato físico reactivo

La capa física central recibe el pedido, que es el límite correcto. Pero el
pedido actual aplica un `global_transform` directo, pone la velocidad a cero y
lo repite cada tick. Sólo se consulta que la pose pueda ocuparse antes del
teletransporte; no hay una intención de movimiento de Hanging definida, ni un
resultado físico que Hanging use para decidir su siguiente tick.

Esto no significa que el snap esté “prohibido”: las asistencias de entrada y
sus tolerancias siguen abiertas. Significa que el experimento aún no responde
qué es una solicitud física de Hanging ni cómo la simulación devuelve éxito,
bloqueo, desplazamiento o pérdida de soporte.

### 8. El soporte físico no forma parte de la retención

`E`, `N`, `C` y `P` son coordenadas mundiales de la lectura actual. No se
conserva una relación con el collider de soporte, ni se vuelve a construir una
pose a partir de ese soporte mientras se sostiene Hanging.

La falta es más amplia que plataformas móviles: tampoco está definido qué
ocurre si se llega a una esquina, una pared deja de ser vertical, aparece una
obstrucción o el borde se termina. Son datos indispensables para *sostener* el
core, no submecánicas opcionales como shimmy.

### 9. Cámara, orientación corporal y pose de Hanging no tienen contrato

El nuevo `CameraPivot` separa yaw de cámara y orientación del body, lo cual va
en la dirección de cámara compartida. Pero durante la retención el body sigue
siendo reseteado a la base de P y no existe una política que diga qué puede
rotar mientras Hanging gobierna, cuál es la referencia visual de la pose o
cómo interactúa eso con primera/tercera persona.

No hay que resolver toda tercera persona ahora. Sí hay que fijar la frontera:
la cámara continúa compartida y no sale de Hanging por sí sola, pero el core
debe declarar qué orientación física conserva o solicita. Sin eso, modificar
la cámara puede arreglar visualmente un laboratorio mientras oculta que la
pose física no está definida.

### 10. Faltan las compuertas globales que V3 ya decidió

El proyecto decidió dos reglas que la entrada temporal no consume:

- mantener `Ctrl` excluye cores contextuales que acepten esa supresión;
- una condición externa puede interrumpir un core o modificarlo sin cortarlo.

Tampoco existe aún un estado general que corte la captura de directivas de
input para menú, escena inmóvil u otra pérdida de voluntad. No son detalles de
Hanging: determinan cuándo un candidato puede siquiera competir o cuándo una
ejecución debe terminar.

### 11. El laboratorio no tiene el nivel de prueba necesario para cerrar la entrada

La pared actual permitió ajustar números, pero ya mostró acoplamientos: al
cambiar la altura de P hubo que elevar el muro para que el player siguiera
llegando al volumen en aire. Eso demuestra que `altura de borde`, `P`, `C`,
`S`, altura corporal y salto no pueden tunearse como sliders independientes.

Faltan fixtures, al menos conceptualmente, para borde bajo/alto, borde finito,
esquina, techo/saliente, geometría delgada, soporte móvil y pérdida de soporte.
No se pide implementar todos ahora; hace falta decidir cuál es el conjunto
mínimo para declarar válida una entrada de Hanging.

## Huecos importantes, pero no errores de la sonda cilindro/esfera

Estos son temas aún abiertos que deben quedar declarados antes de retomar
implementación. No se resuelven añadiendo parámetros al inspector.

| Hueco | Por qué importa antes de avanzar |
| --- | --- |
| Estado de gobierno y ciclo `H0 → Hanging → H0` | Decide quién emite movimiento, cuándo H0 se pausa y cómo vuelve. |
| Contrato de candidato frente a gatillo cilindro/esfera | Decide si cilindro/esfera es hecho, prerrequisito, asistencia o gatillo posterior a la selección. |
| Semántica de P | Decide si es pose física de entrada, dato de prueba o ambos, y quién la valida. |
| Solicitud/respuesta física | Decide qué pide el core cada tick y qué resultado real recibe. |
| Condiciones de sostén y salida | Sin esto cualquier agarre es una retención infinita. |
| Soportes metaestables | Necesario para bordes, plataformas y geometría dinámica. |
| Supresión de cores e interrupciones externas | Evita entradas automáticas cuando el jugador o un sistema externo las bloqueó. |
| Orden/snapshot por tick | Evita que una decisión se tome con datos de un tick y se aplique ciegamente en otro. |
| Capacidades y toggles efectivos | Hay que poder apagar ejecución sin apagar observación, como exige V3. |
| Cobertura verificable | Los smoke tests existen, pero deben comprobarse como ejecución real y ampliarse desde contratos, no desde la jerarquía actual de nodos. |

## Inconsistencias documentales detectadas

No son una falla del gameplay, pero sí una fuente de decisiones equivocadas:

- `v3_hanging_entrada_laboratorio_estado_actual.md` abre diciendo que
  `HangingEntryLab` ya no está en escena, aunque actualmente volvió a estarlo
  y vuelve a retener P.
- Ese mismo documento conserva nombres y valores anteriores (`hang_root_offset_y`)
  mientras el código actual usa `hanging_body_offset_from_edge_y`.
- `v3_hanging_deteccion_propuesta.md` dice que aún no existe traspaso ni snap;
  ya existe un snap de laboratorio, aunque no un traspaso V3 válido.
- El debug todavía contiene mensajes equivalentes a “detección solamente” o
  “sin movimiento colgado” pese a que hay retención temporal.

La solución no es reescribir los fundamentos. Primero hay que cerrar los
huecos de arriba; después se actualiza la radiografía técnica para que describa
una sola realidad.

## Orden de cierre recomendado

Este orden no propone implementaciones; evita que una decisión posterior
deshaga el laboratorio otra vez.

1. **Definir el ciclo de gobierno**: qué significa entrar, estar activo,
   terminar y volver a H0; H0 no puede quedar “corriendo pero ignorado”.
2. **Definir qué representa cada resultado de entrada**: hechos neutrales,
   candidato Hanging, certeza/árbitro, cilindro/esfera y P. En particular, decidir la
   relación contractual entre cilindro/esfera y P.
3. **Definir las condiciones mínimas de sostén y salida** de Hanging,
   incluyendo pérdida o cambio de soporte. No hace falta diseñar shimmy para
   cerrar esta frontera.
4. **Definir el contrato físico mínimo para ese ciclo**, incluido qué informa
   la capa física al core después de intentar su solicitud.
5. **Ubicar las compuertas globales**: supresión con Ctrl, input bloqueado e
   interrupciones externas.
6. **Recién entonces** decidir qué experimento de cilindro/esfera, P o snap se conserva,
   ajustar fixtures y volver a implementar.

## Conclusión

La decisión de frenar Hanging es correcta. La detección compuesta y la sonda
tonta cilindro/esfera entregaron información útil, pero la interacción actual es un
andamio de laboratorio: no satisface todavía gobierno exclusivo, retorno a
H0, relectura metaestable, selección contextual ni contrato físico reactivo.

Seguir con salidas, shimmy o más tuning de sliders sobre este estado sólo haría
más costoso separar luego experimento, decisión y ejecución. Primero hay que
cerrar las fronteras; después el laboratorio puede volver a ser una prueba
limpia de esas decisiones.
