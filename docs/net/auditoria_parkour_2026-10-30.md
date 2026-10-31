# Auditoría de la implementación actual del parkour

Fecha: 2026-10-30.  
Rama revisada: `net-lab`.  
Commit de referencia: `e0eeb88`, más los cambios locales presentes durante la revisión.  
Tipo de trabajo: análisis del código y contraste con las guías; sin implementar correcciones.

## 1. Resultado y alcance

En la revisión realizada no se confirmó un fallo lógico que rompa el parkour en las situaciones habituales. Se encontraron huecos concretos en la validación automática, riesgos en la adopción de estados del cliente y problemas de documentación y entrega.

Esto no certifica que la implementación esté libre de errores. Las pruebas iniciadas durante esta auditoría no proporcionaron un resultado final verificable, por lo que no se consideran aprobadas.

La implementación revisada es la del laboratorio descrito en `docs/net`: `scripts/actor/`, `scripts/net/`, `scenes/actor/` y `scenes/net_lab/`. No se debe confundir con el sistema anterior de `scripts/player_v2/traversal/`, que no fue el objeto de esta revisión.

Se consultaron especialmente:

- [Guía del laboratorio](guia_del_laboratorio.md).
- [Historial, arquitectura y pruebas](arquitectura_coop_y_esqueleto_de_red.md), incluidas las secciones recientes 8.24 a 8.35, el estado del código y los pendientes.
- El motor de movimiento, el estado serializado, la presentación del actor, las sondas de borde y los parámetros de movimiento.
- La adopción de estados, la predicción del cliente y partes del transporte de red.
- Las pruebas mantenidas de repetición y barrido de bordes.
- El estado de Git y las diferencias locales de los archivos del laboratorio.

Las referencias a números de línea corresponden al estado inspeccionado y pueden cambiar con futuras modificaciones.

## 2. Resumen de hallazgos

| ID | Tema | Qué quedó comprobado | Prioridad sugerida |
| --- | --- | --- | --- |
| H1 | Agarre con las manos por encima del filo | Sus métricas visuales se informan aparte y no tienen un criterio automático propio de aprobación | Media |
| H2 | Cobertura del mantle | La repetición exige entrar al modo, pero no verifica todas sus variantes ni sus resultados funcionales | Media |
| H3 | Adopción de estados | El host admite diferencias acotadas sin reconstruir la transición completa; la validación de mantle es amplia | Media; mayor si se pretende resistir clientes modificados |
| H4 | Plataformas movidas por el host | Las guías registran correcciones de mantle de hasta aproximadamente 21,5 cm con internet mala | Media para experiencia de juego |
| H5 | Cambios sin commit | Ocho archivos modificados mezclan varios temas; el comportamiento probado no corresponde solo a HEAD | Media para entrega y reproducción |
| H6 | Documentación contradictoria | Quedaron pendientes históricos que contradicen cambios ya implementados, especialmente el súper | Baja |

Las prioridades son recomendaciones de la auditoría, no severidades demostradas mediante reproducción de un bug.

## 3. H1: agarre con las manos por encima del filo

### Evidencia

En `scripts/actor/actor_motor.gd`, función `grab_check` desde la línea 1110, existe una búsqueda adicional hacia abajo cuando la búsqueda normal no encuentra borde. Usa `hang_reach_down`, cuyo valor por defecto es 1 m.

La validación del snap cambia según el tipo de agarre:

- En el agarre normal, la distancia total está limitada por `hang_snap_max`, por defecto 0,35 m.
- En el agarre desde arriba, se comprueban por separado la distancia horizontal y la bajada vertical; esta última puede llegar a `hang_reach_down`.

Al entrar en Hanging se asigna `hang_drop_speed` a la presentación de ese agarre. Su valor por defecto es 4 m/s, frente al límite visual normal de 1,8 m/s.

En `scenes/net_lab/hang_sweep_test.gd`, alrededor de las líneas 411 a 428, las capturas con una velocidad visual diferente de `ActorBody.GRAB_MAX_SPEED` se acumulan en métricas separadas. Al final, las líneas 479 a 492 solo usan la métrica normal para el criterio de cámara de 10 cm en 50 ms. El resultado desde arriba se imprime, pero no tiene un umbral propio que haga fallar la prueba.

La guía también indica que el cambio estuvo presente en pruebas posteriores, pero no tuvo una prueba manual aislada en las dos PC.

### Implicación

El barrido puede terminar exitosamente aunque empeore mucho la presentación de esta variante. Además, clasificarla por la velocidad visual en vez de por una bandera explícita hace que cambiar `hang_drop_speed` al valor normal cambie cómo se contabiliza.

La bajada más rápida fue una decisión del usuario. Excluirla del límite visual normal no es por sí mismo un bug ni prueba que el cambio se vea mal. El problema es que falta un criterio alternativo que represente el comportamiento deseado.

### Validación recomendada

Agregar casos específicos con las manos a distintas alturas sobre el filo, llegando en subida y caída, y con el salto capaz o incapaz de superar el borde. Comprobar la captura esperada, el límite de bajada, que no atraviese geometría y la duración del ajuste visual.

Conservar la presentación rápida elegida y definir para ella un criterio propio. Probarla también con host y cliente, incluyendo pérdida y latencia.

## 4. H2: cobertura automática insuficiente del mantle

### Evidencia

En `scenes/net_lab/actor_replay_test.gd` se incrementa `_ticks_mantle` cuando el actor está en `MANTLE`. En `_missing_coverage`, alrededor de las líneas 250 a 266, basta con que ese contador no sea cero.

El recorrido guionado incluye un mantle desde parado hacia el techo fijo del túnel corto. La prueba compara el estado repetido con el estado de la pasada en vivo.

Ese mecanismo verifica que el recorrido se puede repetir de forma determinista y que se entra al modo. No exige explícitamente que cada variante termine en el lugar y postura correctos.

### Implicación

Una regresión funcional puede repetirse idénticamente y, por tanto, aprobar la comparación byte a byte. Entrar un momento en `MANTLE` tampoco garantiza que la subida termine correctamente.

La prueba mantenida no cubre de forma específica y con condiciones de éxito todas estas variantes:

- Alturas inmediatamente por debajo y por encima de los límites mínimo y máximo.
- Entrada en subida frente a entrada en caída.
- Salto que por sí solo supera el filo.
- Dirección diagonal, límite lateral y cambio de dirección durante el recorrido.
- Cancelación con Ctrl y salida por impulso fuerte.
- Destino en el que solo cabe agachado.
- Muro fino o baranda sin piso suficiente detrás.
- Borde frente a una escalera.
- Unión de cajas apiladas y bordes próximos a otra geometría.
- Base guionada y cuerpo movido únicamente por el host.
- Predicción y corrección con pérdida y latencia.

Esto no significa que nunca se hayan probado: las guías registran pruebas manuales y diagnósticos específicos. El hueco es su ausencia en una colección mantenida de regresiones con resultados verificables.

### Validación recomendada

Mantener la prueba de determinismo y complementarla con casos funcionales. Cada caso debería comprobar modo final, posición aproximada, postura, ausencia de penetración y tiempo máximo de finalización.

Los casos negativos deben verificar que no se inicia el mantle. Los positivos deben verificar que se completa; contar ticks del modo no alcanza.

## 5. H3: alcance de la autoridad del host y validación de estados

### Evidencia

En `scripts/net/claim_adoption.gd`, `MAX_DIFFERENCE` vale 1 m. Antes de adoptar se comparan época, valores, distancia, pose anclada y posibilidad de aplicar el estado en el mundo.

Por lo tanto, no se acepta cualquier posición: existen controles reales. Sin embargo, el host puede conservar un resultado del cliente distinto de su propia simulación.

En `scripts/actor/actor_motor.gd`, `anchored_pose_valid`, rama `MANTLE` alrededor de las líneas 757 a 769, se comprueba que el borde exista y que la posición esté dentro de un rango vertical y de profundidad respecto de su cara.

Esa rama no reconstruye la entrada al mantle mediante `mantle_check` ni valida por sí misma el recorrido completo desde el estado anterior. Tampoco establece en esa comprobación un límite explícito al desplazamiento tangencial respecto del punto guardado; el límite general de diferencia de posición sigue aplicándose.

### Implicación

El modelo de adopción es una decisión de arquitectura para tolerar diferencias y reducir correcciones. Puede funcionar bien en cooperativo entre jugadores de confianza.

No alcanza para afirmar que un cliente modificado no pueda introducir movimiento ventajoso mediante estados plausibles. La tolerancia de 1 m es por afirmación comparada, no una garantía de que cualquier error acumulado quede limitado a 1 m durante toda la sesión.

Esta auditoría no reprodujo un exploit ni demostró un salto concreto que el cliente pueda imponer. Se registra como límite de las garantías y como riesgo a validar, no como vulnerabilidad explotada.

### Validación recomendada

Crear casos de afirmaciones imposibles: entrada al mantle sin salto, selección de otro borde, avance lateral injustificado y cambios repetidos próximos al límite de adopción. Verificar el rechazo y que el estado autoritativo permanezca consistente.

Si se necesita endurecerlo, validar transiciones y avance desde el estado anterior, además de la pose final. Calibrar esas comprobaciones conservando las tolerancias necesarias para la red real.

## 6. H4: mantle sobre cuerpos movidos únicamente por el host

### Evidencia y límite

La sección 8.33 del historial y la sección 9 de la guía registran resultados distintos según el soporte:

- Bloque fijo y plataforma guionada: se informaron 0 correcciones en las pruebas realizadas.
- Bloque movido solo por el host con internet mala: se informaron correcciones pequeñas, de hasta aproximadamente 0,215 m.

Son resultados documentados por Claude y las pruebas previas del usuario; no fueron medidos de nuevo en esta auditoría.

### Implicación

La afirmación «el mantle tiene 0 correcciones» solo es válida para los escenarios donde se midió ese resultado. Un ajuste de unos 21,5 cm puede ser perceptible cerca de bordes y huecos, aunque el suavizado reduzca el salto visual.

La guía reconoce el comportamiento y aclara que no se añadió a las mecánicas dependientes de buen internet porque no se consultó al usuario. Esto es un pendiente de criterio de aceptación, no prueba de un fallo nuevo.

### Validación recomendada

Repetir con el cliente realizando el mantle y el host observando, y luego invertir roles. Medir cantidad y magnitud de correcciones, posición final y presencia de caídas o cancelaciones inesperadas.

## 7. H5: estado probado y estado versionado diferentes

### Evidencia

Durante la revisión, Git mostraba estos ocho archivos modificados:

| Archivo | Contenido observado en las diferencias |
| --- | --- |
| `scripts/actor/actor_motor.gd` | Agarre con las manos por encima del filo |
| `scripts/actor/actor_body.gd` | Velocidad de ajuste visual de ese agarre |
| `scripts/actor/actor_tuning.gd` | `hang_reach_down` y `hang_drop_speed` |
| `scenes/net_lab/hang_sweep_test.gd` | Métricas y diagnósticos del agarre |
| `scenes/net_lab/net_lab.gd` | F1, direcciones del menú y adaptación del guion de prueba `hang` |
| `scenes/net_lab/net_lab.tscn` | UID añadido a la referencia del nivel |
| `export_presets.cfg` | Ajustes de exportación del laboratorio |
| `project.godot` | Opciones de exportación y cambio de versión declarada 4.6 a 4.7 |

Había además archivos sin seguimiento de otros trabajos. No se modificaron ni se incorporaron a esta auditoría.

### Implicación

Reproducir solo HEAD no reproduce exactamente lo que se estaba jugando. Un commit amplio también puede mezclar cambios con distintos estados de validación o incluir la línea de versión que las reglas del proyecto indican no incorporar.

La documentación ya reconoce la mayor parte de estos cambios pendientes. Su existencia no demuestra que el movimiento sea incorrecto; dificulta aislar, distribuir y reproducir su estado.

### Acción recomendada

Separar las tandas por finalidad y revisar cada diff antes de preparar commits. Guardar qué estado se probó y con qué parámetros. La auditoría no autoriza por sí sola commits ni push.

## 8. H6: documentación histórica contradictoria

En los pendientes del historial, alrededor de la línea 7490, permanece una afirmación de que el súper no multiplica ciertas velocidades de escalera, colgado y saltos hacia afuera. Otras secciones describen correctamente que ese cambio ya se hizo.

`scripts/actor/actor_tuning.gd`, función `with_boost`, multiplica los valores flotantes almacenados cuyos nombres terminan en `_speed`, salvo las exclusiones de `NOT_BOOSTED`. La velocidad terminal está excluida.

Hay que distinguir las velocidades horizontales renombradas con `_speed` de parámetros como `hang_jump_up` o `ladder_jump_up`: no todo parámetro que representa físicamente una velocidad entra en esa regla por nombre. La altura extra de ciertos saltos también tiene un tratamiento separado.

El Apéndice A conserva además afirmaciones antiguas de que el mantle estaba fuera de alcance; el propio historial reciente reconoce ese desfase.

### Implicación y acción recomendada

Un lector puede tomar un pendiente obsoleto como descripción actual y proponer cambios innecesarios. Conviene marcar explícitamente lo resuelto y mantener una descripción breve y única del comportamiento vigente, dejando el resto como historia.

## 9. Deuda de integración ya conocida

La guía, alrededor de la línea 526, recuerda que el laboratorio todavía no es el juego. El punto 4 de una revisión anterior sigue pendiente para el traslado: extraer reglas necesarias de `net_lab.gd` y evitar registros globales cuando existan varios mundos.

No se presenta como un descubrimiento nuevo ni como un bug de la sesión actual. Es una condición a resolver antes de reutilizar el laboratorio como sistema general del juego.

Otros pendientes documentados que no se confirmaron ni descartaron en esta revisión:

- Los guiones antiguos de empujones al jugador colgado de un compañero ya no llegan a colgarse y necesitan reparación antes de servir como evidencia.
- Falta la prueba de juego a distancia entre dos casas con un ejecutable actualizado.
- Quedan pruebas con más jugadores y con otras plataformas.
- Los cables y escaleras actuales son fijos; las bases revisadas no cubren el soporte general de rotación.

## 10. Verificaciones realizadas y sus límites

Se inspeccionaron las guías, los archivos citados, el historial reciente de commits y las diferencias del árbol de trabajo. `git diff --check` no informó errores de espacios en la revisión inicial.

Se encontró y ejecutó Godot `4.7.2.stable.official.ed1daf0bf`. Se inició `actor_replay_test.tscn` en modo headless y se observaron múltiples tramos, incluyendo mantle, Hanging, cable y escalera. No se capturó su salida final de éxito, cobertura y huella.

También se intentó ejecutar `hang_sweep_test.tscn`, sin obtener un resumen final verificable. Se detuvo un proceso de prueba iniciado durante la auditoría que seguía activo. Un intento posterior de ejecutar con captura controlada fue rechazado por la política de ejecución del entorno.

Se observaron errores de acceso al archivo de log de Godot y al almacén de certificados del sistema. No se atribuyen al motor de parkour. Tampoco se afirma que se haya compilado correctamente todo el proyecto: solo se observó que el escenario de repetición pudo cargar y ejecutar numerosos ticks sin un error inmediato de análisis en esa salida.

**Resultado de esta auditoría: ninguna prueba completa se declara aprobada.** Los resultados anteriores consignados en las guías se identifican como antecedentes, no como resultados de esta ejecución.

Durante el análisis no se editaron scripts, escenas, assets ni ajustes. Este informe es el único archivo añadido para documentar sus resultados.

## 11. Orden recomendado de trabajo

1. Definir y ejecutar una prueba específica del agarre con las manos por encima del filo, con criterios funcionales y visuales propios.
2. Mantener casos funcionales del mantle con resultados esperados, empezando por cancelación, techo bajo, muro fino, altura límite y dirección diagonal.
3. Completar la repetición y el barrido existentes con salida final y código de retorno capturados.
4. Ejecutar pruebas de mantle en pareja sobre soporte fijo, guionado y movido por el host, incluyendo pérdida y latencia.
5. Probar afirmaciones de cliente inválidas si se busca endurecer la autoridad del host.
6. Corregir los pendientes obsoletos de los documentos y separar los cambios locales en tandas reproducibles.

Estos pasos son recomendaciones. Este documento no aplica correcciones ni cambia las decisiones de comportamiento elegidas por el usuario.
