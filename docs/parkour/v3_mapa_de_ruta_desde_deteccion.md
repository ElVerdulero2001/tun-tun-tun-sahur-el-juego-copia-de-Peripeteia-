# Parkour V3 — mapa de ruta desde la detección actual

> **Propósito:** ubicar el proyecto sin inventar decisiones. Separa código existente, destino arquitectónico, bloqueos previos a un Hanging activo y temas que pueden esperar.
>
> **Regla:** “decidido” no es “implementado”. “Implementado” no vuelve fundamento a un experimento. Un punto abierto no se completa desde V1, V2 ni una suposición técnica.

## 1. Dónde estamos

La frontera actual termina al publicar una candidata de Hanging.

```text
InputSource ─┐
CameraRig ───┼→ H0 → V3PhysicsBody → hechos físicos actuales
             │
CameraRig + Body → ForwardWallProbe → TopSurfaceProbe
                                 └──→ FrontVolumeProbe → debug

hechos físicos + input + cámara + pared + tapa
                    ↓
      HangingCandidateEvaluator
                    ↓
    candidata Hanging válida o rechazada
                    ↓
                 debug
```

| Área | Estado real |
| --- | --- |
| H0 | Caminar, salto, crouch, sprint, caída y cámara de laboratorio. Es la única autoridad física. |
| Input/cámara | Infraestructura compartida. H0 y evaluator la leen. |
| Física | `V3PhysicsBody` es el único escritor de velocidad y quien llama `move_and_slide()`. |
| Provider pared | Cinco rayos frontales publican impactos crudos. |
| Provider tapa | Publica un impacto descendente crudo por cada lectura de pared. |
| Provider volumen | Publica colliders de una caja frontal; por ahora sólo debug. |
| Consumidor Hanging | Forma candidata con pared+tapa, aire, altura, coherencia e intención no contradictoria. |
| Debug y test | Muestran/validan detección; no habilitan gameplay. |

### No existe hoy

```text
árbitro
certeza contextual calculada
traspaso H0 → Hanging
core Hanging activo
entrada física
sostén / salida
cilindro/esfera / P / snap
shimmy / corners / mantle
soporte dinámico
```

## 2. A dónde queremos ir

```text
input + cámara + mundo actual
        ↓
providers tontos publican hechos
        ↓
cada core consume sólo lo que necesita
        ↓
prerrequisitos propios aprobados
        ↓
candidatas contextuales + certeza total 100
        ↓
árbitro expresa la candidata preferida
        ↓
si pasa el gatillo: H0 cede gobierno al core
        ↓
core activo emite una intención física de este tick
        ↓
física común intenta aplicarla
        ↓
hechos físicos nuevos
        ↓
core continúa o devuelve gobierno a H0
```

Para Hanging, la ruta objetivo es:

```text
H0
→ candidata Hanging físicamente posible
→ comparación contextual
→ Hanging gana y recibe gobierno
→ Hanging solicita movimiento/pose del tick
→ física reporta resultado real
→ Hanging continúa o vuelve a H0
```

## 3. Cosas decididas que no hay que reabrir

| Decisión | Estado |
| --- | --- |
| Providers tontos: hechos, no cores. | Decidida e implementada en el laboratorio. |
| Cada core consume sólo sus datos. | Decidida. |
| Candidata es posibilidad, no activación. | Decidida e implementada. |
| H0 gobierna por defecto. | Decidida e implementada. |
| Core activo reemplaza la locomoción H0; no se combinan. | Decidida; falta mecanismo. |
| Física común es la única que mueve `CharacterBody3D`. | Decidida e implementada para H0. |
| Todo core inicia y termina en H0. | Decidida. |
| Cámara e input son compartidos. | Decidida conceptualmente. |
| Soportes y mundo son metaestables. | Decidida; falta core activo. |
| Certeza contextual suma 100 entre candidatos comparables. | Decidida. |
| Umbral 90. | Provisional decidido; calibrable con evidencia posterior. |
| Ctrl excluye cores contextuales que lo declaren. | Decidido; Hanging aún no lo consume en código. |
| Debug explica pero no gobierna. | Decidido e implementado. |

## 4. El vacío entre candidata y Hanging activo

La detección no responde estas preguntas:

```text
candidata válida
→ ¿participa en certeza contextual?
→ ¿el árbitro la elige?
→ ¿qué evento concede gobierno físico?
→ Hanging activo
→ ¿qué intención física emite este tick?
→ ¿qué devuelve la física: éxito, bloqueo o desplazamiento?
→ ¿qué sostiene Hanging?
→ ¿cuándo y cómo sale a H0?
```

Todo ese tramo está abierto. No se arregla agregando sliders, `if` o nodos a la escena.

## 5. Bloqueos antes de una entrada física

El orden es por dependencia, no una receta técnica. Cada bloque debe quedar escrito y entendido antes de codificar el siguiente.

### A. Contrato de candidata y captura

**Pregunta:** ¿qué significa exactamente “Hanging puede ocurrir” y qué hace falta antes de una entrada posible?

Ya existe:

```text
pared + tapa + aire + altura + intención no contradictoria
→ candidata geométrica
```

Falta decidir:

- si la candidata actual contiene todos los prerrequisitos físicos;
- si existe una ventana corporal adicional de captura;
- si cilindro/esfera vuelve, qué representa: entrada, sostén, ambos o ninguno;
- si cilindro/esfera vuelve, qué relación tienen sus volúmenes con body/borde y por qué;
- qué dato publica Hanging para competir sin ejecutarse.

**No codificar todavía:** cilindro/esfera, P, snap o pose guiada.

### B. Árbitro contextual

**Pregunta:** con varias candidatas válidas, ¿cuál representa mejor la intención actual?

Ya está definido:

```text
prerrequisitos aprobados
→ distribución total 100
→ árbitro expresa la mayor
→ si alcanza 90, puede iniciar desde H0
```

Falta cerrar/prototipar:

- qué datos de Hanging alimentan certeza y cuáles son sólo requisitos duros;
- normalización cuando haya dos o más candidatos;
- debug de pesos, signo, distribución, ganador y no-traspaso;
- Ctrl antes de la competencia;
- si una candidata única obtiene el 100 conceptual o si se espera otro core contextual para probar competencia.

**No codificar:** un árbitro que interprete geometría ni un core que se active por ser el único nodo de la escena.

### C. Gobierno del movimiento

**Pregunta:** ¿qué cambia cuando H0 deja de gobernar y Hanging empieza?

Debe definirse:

- estado mínimo: H0 gobierna / Hanging gobierna / retorno a H0;
- quién concede y revoca gobierno;
- cómo H0 deja de emitir locomoción durante Hanging;
- qué ocurre con dos solicitudes en el mismo tick;
- qué conserva H0 al volver: posición, velocidad, postura y hechos actuales;
- qué ve el debug.

La ruta `Hanging → H0 → posible core siguiente` ya está decidida. Falta el mecanismo que la haga real sin elegir por prioridades de nodos.

### D. Contrato físico reactivo

**Pregunta:** una vez activo, ¿qué puede pedir Hanging a la física en un tick y qué respuesta recibe?

El límite ya está decidido:

```text
Hanging decide su mecánica
→ física común intenta aplicarla
→ resultado real vuelve como hecho público
```

Falta definir, sin bajar aún a una API de Godot:

- intención mínima de sostén estático;
- significado de aplicado, bloqueado o aplicado parcialmente;
- qué datos del resultado posterior consume Hanging;
- qué postura/collider puede solicitar Hanging;
- cómo se comprueba un desplazamiento sin teletransportar ni validar sólo destino;
- qué ocurre ante colisión inesperada.

Este bloque reemplaza el snap descartado. No debe reintroducirlo con otro nombre.

### E. Sostén y salidas mínimas

**Pregunta:** cuando Hanging gobierna, ¿qué lo mantiene y cómo termina?

| Caso | Falta decidir |
| --- | --- |
| Soltar voluntario | Directiva y estado físico al volver a H0. |
| Salto desde Hanging | Directiva, impulso/resultado físico y retorno a H0. |
| Pérdida de borde/pared | Hechos actuales que cuentan como pérdida de soporte. |
| Bloqueo físico | Si ajusta, reintenta o sale; no puede quedar retenido en silencio. |
| Daño/interrupción externa | Interrupción obligatoria o modificador temporal. |
| Soporte dinámico | Reevaluación si se mueve, rota o desaparece. |

Shimmy, mantle y esquinas no hacen falta para responder estas salidas mínimas de Hanging estático.

### F. Orientación y presentación mínima

**Pregunta:** ¿qué orientación física necesita Hanging y qué puede hacer la cámara sin alterar esa realidad?

Falta fijar:

- si body se orienta a pared al entrar y cuándo puede actualizarse;
- libertad de cámara en primera/tercera persona;
- protección contra rotación corporal que haga caer de un borde;
- hechos confirmados disponibles para animación, VFX y sonido.

La cámara no puede iniciar, terminar ni fabricar física de Hanging.

## 6. Temas que pueden esperar

| Tema | Por qué puede esperar |
| --- | --- |
| Shimmy | Primero hace falta sostén estático y salida segura. |
| Esquinas | Dependen de shimmy y continuidad lateral. |
| Mantle | Es otro core o decisión posterior; no es una salida improvisada de Hanging. |
| Ladder | Competirá después, pero no bloquea limpiar la candidata actual. |
| Tercera persona completa | Cámara compartida ya existe; su presentación detallada puede esperar. |
| Animación, VFX, sonidos e IK | Reaccionan a simulación confirmada. |
| Valores finales de rayos/alturas/velocidades | Tuning posterior a los contratos. |
| Fixtures extremos | Se diseñan cuando se conozca el contrato a verificar. |

Las plataformas dinámicas no bloquean la detección actual, pero sí bloquean declarar cerrado un Hanging activo si forman parte esperada del gameplay.

## 7. Dependencias de trabajo

```text
Detección actual
        ↓
Contrato de candidata / captura
        ↓
Árbitro contextual
        ↓
Traspaso de gobierno
        ↓
Contrato físico reactivo
        ↓
Sostén estático
        ↓
Salidas mínimas a H0
        ↓
Laboratorio de entrada, sostén y salida
        ↓
Shimmy → esquinas → mantle u otras cadenas

Contrato físico reactivo → postura y cámara
Sostén estático → soporte dinámico
Salidas mínimas → interrupciones externas
```

La detección no necesita rehacerse por cada bloque. Lo que se debe evitar es enchufar directamente cualquiera de estos bloques posteriores a la escena antes de cerrar su contrato.

## 8. Documentos y autoridad

| Documento | Rol |
| --- | --- |
| `v3_idea_base.md` | Principios de V3. |
| `v3_autoridad_movimiento_propuesta.md` | Frontera conceptual core/física. |
| `PARKOUR_SYSTEM_ARCHITECTURE.md` | Fundamento arquitectónico transmutado a V3. |
| `v3_hanging_contrato_borrador.md` | Contrato de candidata; revisar al cerrar Bloque A. |
| `v3_hanging_laboratorio_mapa_tecnico.md` | Estado de código actual. |
| `v3_hanging_auditoria_huecos_y_fallas_filosoficas.md` | Evidencia de la ruta retirada y huecos pendientes. |
| Este documento | Mapa de navegación; no autoriza código. |

## Conclusión operativa

La detección no es media implementación de Hanging: es una capa completa de lectura y candidata. El siguiente trabajo no es mover al player; es cerrar el puente conceptual entre candidata y gobierno.

Hasta entonces, el límite sano sigue siendo:

```text
providers → candidata → debug
```
