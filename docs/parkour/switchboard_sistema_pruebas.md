# Switchboard de capacidades para pruebas de parkour

## Estado

**Propuesta de infraestructura de laboratorio.**

Este documento conserva el acuerdo de diseño del switchboard: un registro
central de capacidades que permite habilitar o deshabilitar partes concretas
de los cores durante una prueba, sin reescribir escenas ni llenar el código de
condiciones dispersas.

No es el selector de variantes V1/V2 ni una mecánica de gameplay. Es una
herramienta local de experimentación y diagnóstico.

## 1. Propósito

El switchboard permite aislar una conducta para comprobar su efecto. Por
ejemplo:

- Desactivar la salida de `Hanging` con Espacio, conservando captura y
  retención.
- Impedir la captura/entrada de `Ladder`, aunque el detector publique una
  oportunidad válida.
- Probar `Shimmy` sin habilitar `Mantle`.
- Desactivar la protección de reenganche para observar sus consecuencias de
  forma deliberada.

La regla es que una feature apagada no destruye los datos ni desactiva la
observación: impide sólo la decisión o transición que representa.

## 2. Dos estados por capacidad

Cada capacidad tiene dos estados distintos:

| Estado | Significado |
|---|---|
| Solicitado | El valor elegido en la configuración de laboratorio. |
| Efectivo | Si la capacidad puede ejecutarse con sus dependencias activas. |

Esto preserva la configuración cuando se apaga un core padre. También permite
probar configuraciones inválidas de manera segura: una feature puede estar
solicitada, pero no será efectiva si le falta una dependencia.

Ejemplo:

```text
Hanging Core              solicitado: sí   efectivo: sí
├─ Shimmy                  solicitado: sí   efectivo: sí
├─ Mantle                  solicitado: sí   efectivo: sí
└─ Salto desde Hanging     solicitado: no   efectivo: no

Hanging Core              solicitado: no   efectivo: no
├─ Shimmy                  solicitado: sí   efectivo: no (requiere Hanging Core)
├─ Mantle                  solicitado: no   efectivo: no
└─ Salto desde Hanging     solicitado: no   efectivo: no
```

Apagar `Hanging Core` no modifica los valores solicitados de sus hijas. Al
volver a encenderlo, cada una recupera su estado solicitado anterior.

## 3. Árbol inicial de capacidades

La forma inicial del registro es la siguiente. Sólo se incorporan capacidades
que existan y puedan probarse; no hace falta implementar todo el árbol de una
vez.

```text
Locomoción base
├─ Hanging Core
│  ├─ Captura / entrada
│  ├─ Shimmy
│  ├─ Mantle
│  ├─ Salto / salida con Espacio
│  └─ Soltar + protección de reenganche
│
├─ Vault                         (independiente de Hanging)
├─ Slide / crouch                (independiente de Hanging)
│
└─ Ladder especializada
   ├─ Captura / entrada
   ├─ Salida
   └─ Encadenamiento
```

Ejemplos de consultas de intención en los cores:

```text
¿Puede Hanging capturar este candidato?       hanging.capture
¿Puede Hanging procesar Espacio como salida?  hanging.jump_exit
¿Puede Ladder tomar este candidato?           ladder.capture
¿Puede Ladder abandonar el segmento?          ladder.exit
```

Los nombres exactos se deciden al implementar, pero deben ser estables,
explícitos y expresar una sola decisión observable.

## 4. Contrato de ejecución

1. Detectores y evaluadores continúan publicando oportunidades y motivos de
   rechazo físico aunque una feature esté apagada.
2. Antes de una transición, el core o resolver consulta el switchboard para
   conocer el estado efectivo de esa capacidad.
3. Si la capacidad no está efectiva, la transición no ocurre.
4. El resultado de debug registra que la oportunidad fue rechazada por el
   switchboard, no por geometría, input o física.
5. Ningún core modifica directamente el estado de otro core para simular una
   feature apagada.

Por ejemplo, si `ladder.capture` está desactivada, el detector puede seguir
mostrando un candidato de escalera válido. La decisión final informa
`rechazado: ladder.capture desactivada`, y el player conserva su control
normal.

## 5. Dependencias y configuraciones forzadas

Una capacidad hija depende de que sus padres estén efectivos. Un hijo no
puede inventar el estado que le falta:

- `hanging.shimmy` requiere `hanging.core`.
- `hanging.jump_exit` requiere que exista el estado `HANGING` y que
  `hanging.core` esté efectivo.
- `ladder.exit` requiere que `ladder.core` pueda haber capturado al player.

Una configuración solicitada pero inválida se conserva para inspección. El
switchboard debe indicarla como advertencia de laboratorio, pero el juego no
debe crashear ni entrar en un estado imposible.

## 6. Observabilidad

El switchboard no apaga el diagnóstico. Como mínimo, la telemetría de una
decisión debe poder exponer:

```text
capacidad consultada
estado solicitado
estado efectivo
dependencia faltante, si existe
resultado: ejecutada / rechazada por switchboard
```

Ejemplos útiles:

```text
Hanging: candidato válido; captura rechazada por hanging.capture desactivada.
Hanging: Espacio recibido; salida rechazada por hanging.jump_exit desactivada.
Ladder: candidato válido; entrada rechazada por ladder.capture desactivada.
```

Esto permite distinguir una prueba de configuración de un fallo real de
detección, física o input.

## 7. Forma técnica mínima

La primera implementación puede ser un `Resource` local y exportado con
booleanos, descripciones y una API de consulta. Los cores reciben una
referencia explícita al recurso o a una interfaz local que lo exponga.

```text
SwitchboardResource
├─ requested(feature) -> bool
├─ is_effective(feature) -> bool
└─ describe_block(feature) -> String
```

No requiere autoload, singleton ni un panel de UI completo. Tampoco debe
desactivar nodos de la escena como mecanismo principal: el control sucede en
la frontera semántica de cada transición.

Un `@tool` puede añadir warnings de dependencias inválidas en el Inspector.
Los colores personalizados, checkboxes enriquecidos o un
`EditorInspectorPlugin` son mejoras opcionales; no bloquean el uso del
switchboard en pruebas.

## 8. Criterios de aceptación

La primera versión queda aceptada cuando:

1. Se puede apagar `hanging.jump_exit` y Espacio no saca al player de
   Hanging.
2. Se puede apagar `ladder.capture` y una candidata válida no captura al
   player.
3. Apagar un core padre desactiva efectivamente a sus hijas sin borrar sus
   valores solicitados.
4. Los detectores y el debug siguen mostrando oportunidades mientras una
   feature está apagada.
5. Cada rechazo provocado por configuración identifica la capacidad concreta
   y no se confunde con una falla física.
6. No existen condiciones de switchboard repartidas fuera de las fronteras de
   decisión de los cores.

## 9. Límites

El switchboard no define qué hace Hanging, Ladder, Vault o cualquier otro
core; sólo gobierna qué transiciones están permitidas durante una prueba.
Tampoco convierte una combinación inválida en una capacidad funcional. Su
valor es permitir experimentar sin ocultar las dependencias reales del
sistema.
