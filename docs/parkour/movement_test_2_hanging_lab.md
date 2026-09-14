# `movement_test_2` — Laboratorio multivariante de Hanging Core

## 1. Decisión

Se pausa el desarrollo expansivo del parkour actual. No se elimina ni se reescribe el trabajo V2 existente: queda congelado como referencia WIP.

Se crea un laboratorio nuevo, `movement_test_2.tscn`, que reúne tres variantes de player en una misma geometría de prueba:

```text
V1      referencia histórica de comportamiento, adaptada al lab.
V2      implementación actual congelada.
V2.1    candidato experimental nuevo.
```

El siguiente trabajo no intenta terminar parkour, shimmy, mantle, escaleras o combinaciones. El laboratorio permite desarrollar y romper únicamente el **Hanging Core** de V2.1, comparándolo inmediatamente contra V1-Lab y V2 congelado bajo la misma geometría.

El objetivo es construir un hanging contextual, permisivo y robusto antes de permitir que otras mecánicas dependan de él.

## 2. Referencias y límites

- El V1 histórico (`860a999f2c5ada8fc01ab74179a3442f887883d3`, equivalente a `bd38e49^`) permanece intacto como oráculo de comportamiento fuera del laboratorio.
- `V1-Lab` es una adaptación de convivencia de V1, no el original histórico. Su locomoción base es la referencia inicial de sensación para V2.1.
- El V2 actual se preserva como variante congelada: no se destruye, no se borra y no se mezcla con V2.1 por inercia.
- V2.1 es el único candidato experimental que recibe cambios de gameplay durante H0.
- El Hanging Core experimental no debe copiar scripts V1 ni heredar sus accidentes de ejecución. Debe expresar sus reglas de forma explícita y verificable.
- Un `Marker3D` de spawn, reset o debug está permitido. Ningún marker de laboratorio puede ser leído por el sistema como ayuda para decidir un hanging normal.

## 2.1 Arquitectura de variantes y aislamiento

`movement_test_2.tscn` funciona como `LabHost`. No contiene lógica de parkour de ninguna variante.

```text
LabHost
├─ Geometría neutral, zonas y spawns de prueba
├─ Selector de variante
├─ UI y telemetría neutral de sólo lectura
└─ Un actor activo
   ├─ V1LabAdapter
   ├─ V2FrozenAdapter
   └─ V2_1Adapter
```

Las tres variantes pueden estar registradas por el host, pero **sólo una existe en el árbol de escena y procesa input/física a la vez**. Cambiar de variante debe seguir este ciclo:

1. Guardar el spawn/escenario elegido, no el estado de gameplay anterior.
2. Desconectar input, cámara y debug de la variante activa.
3. Liberar la instancia activa y limpiar su telemetría transitoria.
4. Instanciar la variante elegida en el mismo spawn/orientación.
5. Conectar sólo su telemetría de lectura al host.

V1, V2 y V2.1 no comparten candidatos, señales, estados, decisiones, recursos de gameplay ni switchboards. La única frontera permitida es un snapshot neutral y de sólo lectura para que el host muestre posición, velocidad, estado, candidato, motivo de rechazo y capacidades activas.

## 2.2 Convivencia de V1-Lab

Un único proyecto Godot no puede ejecutar tres `project.godot` distintos ni aislar automáticamente sus autoloads, InputMap y grupos globales. Por eso V1 necesita una adaptación de laboratorio.

Cambios permitidos en V1-Lab:

- rutas, namespaces y recursos de laboratorio;
- servicios/autoloads de compatibilidad;
- InputMap común y routing de input del host;
- grupos globales, spawn, reset, cámara y selector;
- telemetría y debug estrictamente pasivos.

Cada cambio de V1-Lab debe registrarse en una tabla de compatibilidad con una de estas etiquetas:

| Etiqueta | Significado |
|---|---|
| `CONVIVENCIA — sin efecto de parkour conocido` | Cambio de rutas, aislamiento o presentación sin tocar reglas de movimiento/traversal. |
| `RIESGO CONDUCTUAL — validar contra V1 histórico` | Puede afectar probes, timing, estados, cámara, aceleración o reglas de hanging. Requiere contraste explícito con el V1 histórico externo al lab. |

La línea roja: V1-Lab no se "arregla" para facilitar la convivencia. Si hay que tocar comportamiento de parkour, se documenta como divergencia y se valida; nunca se disimula como cambio técnico.

## 3. Alcance H0: Hanging Core

### Incluido

```text
locomoción base
→ salto o caída
→ probes contextuales de borde
→ candidato observable
→ admisión/rechazo según contexto
→ snap breve
→ hanging estable
→ salto o soltar
→ limpieza del estado / protección de reenganche
```

### Excluido expresamente

- Shimmy y cambios de esquina.
- Mantle y subida a plataforma.
- Escaleras, cables, cuerdas y otras rutas verticales especializadas.
- Kick, inventario e interacción ajena a traversal.
- Pesos predictivos de intención.
- Cualquier agarre desde simple proximidad en suelo.

Las exclusiones no implican que la escena no contenga geometría útil para ellas. Significan que no pueden ejecutar transiciones ni alterar el contrato de H0.

## 4. Contrato de H0

Un resultado es correcto cuando:

1. Caminar, correr o quedarse parado frente a una caja desde suelo no activa hanging.
2. Un salto o caída hacia un borde físicamente válido puede producir un candidato contextual.
3. El sistema distingue entre borde válido, borde inválido y mecánica desactivada; nunca deja al usuario adivinando cuál fue el motivo.
4. El snap es directo y breve; no se siente como una animación lenta obligatoria.
5. Una vez colgado, el jugador queda estable y conserva el control de cámara acordado.
6. Saltar o soltar devuelve la autoridad de movimiento sin estado residual, lease residual ni bloqueo invisible.
7. Geometría hostil o imposible provoca rechazo limpio; nunca teletransporte, clipping, bloqueo permanente o crash.

H0 no se declara cerrado por tener tests verdes. Requiere playtest humano repetido en escenarios variados.

## 5. Diseño de `movement_test_2.tscn`

La escena es un gimnasio técnico, no un nivel lineal ni un único circuito estético. Sus zonas están físicamente separadas, tienen identificadores legibles y spawns de debug para volver a un caso sin recorrer el mapa.

### 5.1 Zonas de geometría

| Zona | Contenido | Uso inicial en H0 |
|---|---|---|
| Hub | Suelo plano, reset, selector de spawn, lectura de escenario. | Sí. |
| Bloques estáticos | Cajas con alturas, profundidades, anchos y separaciones variadas. | Sí: base del hanging. |
| Paredes y bordes | Muros, plataformas profundas/finitas, bordes bajos/altos. | Sí. |
| Rampas | 15°, 30°, 45°, 60°; ascendentes, descendentes y flotantes. | Sí: aproximaciones y normals raras. |
| Clearance | Techos bajos, plataformas cortas, obstáculos detrás/arriba. | Sí: rechazo limpio. |
| Curvas | Círculos, semicircunferencias, cilindros. | Sólo observación H0; reservada para shimmy. |
| Formas en L | Esquinas interiores/exteriores y brazos de distintos tamaños. | Sólo observación H0; reservada para shimmy. |
| Combinaciones | Rampa→bloque, bloque→curva, L→plataforma, alturas mezcladas. | Casos de estrés H0 sin transiciones extras. |
| Física dinámica | Cajas `RigidBody3D`, quietas y móviles. | Observación/decisión futura; no requisito de soporte H0. |
| Vertical especial | Escaleras, cables, cornisas finas. | Reservada; no activa en H0. |
| Stress | Borde mínimo, hueco, techo, geometría muy cercana o deliberadamente imposible. | Sí: robustez y rechazo. |

Cada zona usa colisiones físicas reales y un ID estable, por ejemplo `H0-BLOQUE-01` o `H0-TECHO-03`. Los colores o carteles sirven a la lectura humana; nunca codifican reglas de gameplay.

### 5.2 Medidas y variantes

No hace falta construir todas las combinaciones desde el primer día. La escena debe permitir añadir variantes de una sola variable:

- altura del borde;
- profundidad/ancho de la plataforma;
- distancia horizontal de aproximación;
- velocidad y tipo de entrada: salto vertical, carrera o caída;
- ángulo de aproximación;
- espacio libre superior y posterior;
- inclinación de la superficie;
- geometría estable frente a cuerpo dinámico.

## 6. Switchboard de mecánicas

El laboratorio incorpora una configuración central de capacidades. No se permite repartir checks de habilitación por scripts sin una fuente común.

Cada capacidad tiene dos conceptos:

| Concepto | Significado |
|---|---|
| Estado pedido | El usuario pide habilitar o deshabilitar la mecánica. |
| Estado efectivo | La mecánica puede o no ejecutarse según dependencias y overrides. |

Estados visuales deseados:

| Estado | Significado |
|---|---|
| Verde/normal | Activa y con dependencias válidas. |
| Gris | Apagada explícitamente o apagada por una dependencia. |
| Amarillo/naranja | Forzada activa aunque una dependencia requerida está apagada. Es inválida, pero permitida para experimentación. |

Reglas:

1. Apagar una mecánica core deshabilita efectivamente a sus dependientes, sin borrar la preferencia guardada de cada dependiente.
2. Un dependiente puede forzarse activo con el core apagado. Debe quedar marcado como configuración inválida.
3. Forzar una mecánica no le inventa contexto ni viola sus invariantes: si falta Hanging Core, Shimmy no puede mover un cuerpo que nunca entró en hanging. Debe degradar de forma segura y explicable.
4. Al reactivar el core, los dependientes pedidos vuelven a su estado normal automáticamente si ya no les falta nada.
5. La primera versión puede usar warnings/texto e `@tool`; el color propio de cada checkbox requiere un `EditorInspectorPlugin` y puede llegar después sin cambiar el contrato.

Árbol de dependencias inicial:

```text
Locomoción Base
├─ Hanging Core
│  ├─ Shimmy
│  ├─ Mantle
│  ├─ Salto desde hanging
│  └─ Soltar / protección de reenganche
│
├─ Vault                         (independiente de Hanging Core)
├─ Slide / crouch                (independiente de Hanging Core)
└─ Escalera especializada
   ├─ Subida / bajada
   ├─ Salida
   └─ Encadenamiento
```

Durante H0 sólo necesitan existir `Locomoción Base` y `Hanging Core`. El árbol define el contrato futuro; no obliga a implementar módulos aún ausentes.

## 7. Observación separada de ejecución

La mecánica puede estar apagada; la observación no.

```text
Geometría + probes
        ↓
Registro de datos observables
        ↓
Reglas de dependencia / toggle / contexto
        ↓
Ejecución de estado y movimiento
```

Aunque Hanging Core esté desactivado, el laboratorio debe poder mostrar que el borde habría sido válido, con los datos relevantes y una decisión del estilo:

```text
EDGE_VALID
contexto: caída válida
clearance: válido
resultado: RECHAZADO — Hanging Core desactivado
```

Del mismo modo, una mecánica futura apagada puede mostrar candidato y motivo de rechazo sin ejecutar una transición. El debug consume un registro común de observaciones actuales; debe indicar timestamp/validez para no presentar datos viejos como si siguieran activos.

## 8. Catálogo de preguntas naturales del jugador

Este catálogo no es un compromiso de implementar todo. Ordena posibles mecánicas por la pregunta que un jugador razonable haría y por su dependencia.

```text
Base común
├─ ¿Puedo caminar, correr, saltar y corregir el salto?
└─ ¿La cámara responde con libertad?

Hanging Core
├─ ¿Puedo agarrarme de ese borde?
├─ ¿Puedo quedarme colgado sin que me saque del estado?
└─ ¿Puedo saltar o soltarme?

Dependen de Hanging Core
├─ ¿Puedo moverme por ese borde?                 → Shimmy
├─ ¿Puedo doblar esa esquina?                    → Shimmy / cambio de cara
├─ ¿Puedo subir arriba?                          → Mantle
└─ ¿Puedo saltar de un borde a otro?             → Transfer jump

Vertical especializado
├─ ¿Puedo escalar eso verticalmente?             → Escalera
├─ ¿Puedo recorrer algo demasiado fino?          → Cable / cuerda / cornisa
└─ ¿Puedo continuar una escalera cercana?        → Encadenamiento

Locomoción contextual independiente
├─ ¿Puedo pasar por encima sin agarrarme?        → Vault
├─ ¿Puedo pasar por debajo?                       → Slide / crouch
├─ ¿Puedo saltar con precisión a esa superficie? → Salto / aterrizaje
└─ ¿Puedo amortiguar una caída?                   → Roll / caída controlada
```

## 9. Infraestructura mínima de prueba

- Selector V1-Lab / V2 congelado / V2.1, con una sola variante activa a la vez.
- Spawn/reset por zona conservado al cambiar de variante.
- ID visible de escenario.
- Telemetría neutral de sólo lectura: posición, velocidad, estado, candidato, decisión, motivo de rechazo y capacidades activas/forzadas.
- Debug propio de cada variante, desconectado al abandonar esa variante.
- Registro manual mínimo por intento: `ID | escenario | inicio | input | resultado | ticks | nota`.
- Colisiones reales y geometría estable para los casos baseline.

Vídeo, hojas de cálculo grandes, búsqueda binaria de umbrales y escenarios exhaustivos se agregan sólo cuando una incógnita concreta lo justifique.

## 10. Orden de trabajo

1. Auditar read-only el V2 WIP y congelar su alcance; no borrar nada. Documentar qué queda como V2 congelado.
2. Preparar V1-Lab y su tabla de compatibilidad, preservando V1 histórico fuera del laboratorio.
3. Especificar/crear `LabHost`, el selector de variante y el ciclo seguro de spawn/cambio.
4. Crear el esqueleto de `movement_test_2.tscn` y sus zonas H0 necesarias.
5. Instanciar y verificar V1-Lab y V2 congelado en la misma zona, uno por vez, antes de crear V2.1.
6. Crear V2.1 con locomoción base de referencia y switchboard mínimo: Locomoción Base + Hanging Core, con estado pedido, efectivo y motivo visible.
7. Construir en V2.1 el detector/observación contextual de borde sin permitir todavía que todo candidato ejecute hanging.
8. Implementar en V2.1 el circuito H0: admitir → snap → hanging → salto/soltar.
9. Jugar y romper H0 en las zonas de bloques, rampas, clearance y stress, comparando V1-Lab, V2 y V2.1 sólo cuando la misma prueba lo requiera.
10. Ajustar H0 hasta que sea robusto y agradable; sólo entonces discutir Shimmy.

## 11. Condición para abandonar H0

Se puede abrir Shimmy sólo cuando Hanging Core sea confiable en playtest humano: sin falsos agarres desde suelo, con agarres válidos consistentes, con rechazos explicables y sin estados residuales al salir.

La pregunta siguiente será únicamente: **«Ya que puedo agarrarme de ese borde, ¿puedo moverme por él?»**
