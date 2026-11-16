# Revisión de Codex y entrega 2

2026-11-16. Revisión de los resultados de Claude en `entrega_1.md` y `criterios_entrega_1.md`, del código de sus drivers/verificador y de las trazas. Se incorporó por avance directo su commit `5a5d92f` a la copia `implementacion`, sin modificar las pruebas ni sus criterios. La base de implementación evaluada por Claude era `b86dda9`.

## Dictamen

**La entrega 1 no supera la puerta de viabilidad del plan.** Los defectos F1–F4 son reales. La evidencia de trayectorias iguales con acciones alineadas favorece conservar Jolt y el principio del reloj; no valida transportar un error antiguo al presente ni usar cuerpos cinemáticos retrasados para resolver contactos dinámicos.

Esta entrega 2 corrige errores de estado, causalidad e instrumentación y retira la corrección inestable. **No presenta una reconciliación alternativa aprobada ni habilita la migración al laboratorio.** El sistema del juego continúa sin cambios.

## Cambios aplicados

| Hallazgo de Claude | Cambio de implementación |
| --- | --- |
| F2: agarre sin respetar tick ni ventana futura | Todas las acciones se programan después del tick solicitado, dentro de la ventana; un agarre imposible en el futuro se rechaza. También se identifica un agarre realmente tardío |
| F6: especulación sube la revisión autorizada | `state` conserva exclusivamente muestras autorizadas; `predicted_state` identifica el recorrido local. Un rechazo cancela la especulación sin bloquear las poses vigentes del host |
| F7: salida anterior al ACK espera y pierde dirección | Se conservan acción, tick y dirección originales. Se ejecuta localmente y se transmite sin esperar el viaje de regreso. La autoridad mantiene una salida dependiente de la concesión del mismo peer/sesión y las aplica en orden |
| F1/F3: oscilación y saltos por trasladar diferencias | Se elimina ese mecanismo y su escritura de transform/velocidades. La divergencia se mide como `model_blocked`; no se interpreta como resuelta por dejar de corregir |
| F5: reseed en reposo y retroceso del reloj | No se teletransporta el cuerpo al reposo del host. Solo se cede una representación ya coincidente dentro del criterio previo, preservando el reloj mostrado; si diverge, se registra y bloquea |
| F10: ACK anterior al impulso | Un impulso central se materializa como `Δv = J/m` en el límite físico, una vez. La confirmación captura la velocidad de salida posterior al impulso |
| F10: huella con constantes escritas a mano | Se calcula desde formas/parámetros reales de arranque, ajustes físicos, versión del motor y hashes de scripts. Se mantiene estable durante los cambios entre mano y caída |
| F10: objetivos después de desconectar y silencio ante `stale` | Se vacían objetivos del agarre liberado y se responde explícitamente al duplicado antiguo, sin ejecutarlo otra vez |
| Instrumentación insuficiente | Se agregan proxies, objetivos consumidos, divergencia vectorial, descartes, intenciones dependientes, giro visible, tick completado y causas de espera del traspaso |

No se sustituyeron los proxies por otra aproximación sin probar. Tampoco se cambiaron el material, las tolerancias de Jolt ni las pruebas para absorber F8.

## Verificación enfocada con las pruebas originales

Se reutilizaron los archivos de Claude sin editar sus expectativas. Un caso por corrida, tiempo real, máximo externo de 20 s, sin baterías paralelas. Evidencia en `implementacion/tmp/revision_entrega_2/`.

| Caso | Resultado observado por Codex |
| --- | --- |
| Contrato | 74 pasan, 0 fallan; incluye el rechazo de agarre futuro que fallaba |
| `drop050 / clean` | Todos los criterios ejecutados pasan. Diferencia física del mismo tick: 0 m/0°; sin correcciones, ascenso artificial ni salto/retroceso en traspaso |
| `throw_before_ack / clean` | Todos los criterios ejecutados pasan. Salida en 1 tick, 1 impulso por lado, dirección a 0,01527° de la solicitada y trayectorias iguales |
| `release_before_ack / degraded` | Salida local en 1 tick, trayectorias iguales, mismo contacto y traspaso sin salto. P5 conserva dos fallos de la banda de amortiguación ya reconocida como mal planteada en el informe de Claude; no se modificó la prueba ni se ocultan esos fallos |
| `grab_rejected / clean` | G1 y G2 pasan: sin predictor huérfano y error máximo de réplica de 1,51 mm, frente a 1,25 m en la entrega 1 |
| `disconnect_holding / clean` | E0 y X1 pasan en la última corrida: una liberación, sin impulso, sin objetivos posteriores y ambos procesos con salida 0. La primera corrida detectó un error nuevo de instrumentación al consultar la identidad de una conexión ya cerrada; se preservó su resultado, se corrigió la limpieza de sesión y se repitió solo ese caso |
| `late_release_hitch / clean` | **Sigue fallando.** Suelta 9 ticks tarde, diferencia física de hasta 36,3 cm y contacto 9 ticks desfasado. Ya no hay teletransporte por reconciliación y el traspaso no salta, pero el ascenso artificial medido aún suma 9,85 mm por mostrar la trayectoria desfasada |

No aprobar la entrega completa contando solo los criterios que pasan. En particular, C5 queda sin saltos porque se retiró una escritura inestable: la comprobación independiente de C1/C4 continúa detectando el problema temporal en el caso tardío.

El runner de Claude termina sus procesos y escribe `run.json`, pero su comprobación final con `Get-CimInstance Win32_Process` recibe acceso denegado en este entorno. No se alteró el runner: se registró esa excepción y se llamó por separado al verificador original sobre los archivos escritos. `run.json` conserva salidas, errores, duración y PID terminados por timeout. El resultado no se toma como una corrida normal del runner sin esta salvedad. El aviso de certificados raíz de Windows se conserva.

Se conserva un resumen de cada corrida, incluidos los fallos, en `resultados_codex_entrega_2.json`. La última corrección funcional afecta al cierre de sesión; por eso se repitió el caso de desconexión y no toda la batería. La revisión independiente sobre el hash final de esta entrega continúa pendiente.

## Lo que continúa bloqueado

1. **Contacto dinámico F4:** los proxies retrasados e inamovibles continúan refutados. Empuje, caja móvil y apoyo no se consideran corregidos por estos cambios ni se volvieron a ejecutar para producir otro resultado conocido.
2. **Salida realmente tardía F3:** aceptar una acción en un paso posterior cambia la edad física de su caída. Eliminar el teletransporte evita un daño adicional, pero no hace iguales dos historias diferentes.
3. **Reconciliación y retorno general F1/F5:** falta una política que pueda corregir el pasado físico relevante sin falsificar la trayectoria presente. Un objeto que termina en reposo diferente puede permanecer sin traspaso; `handoff_blocked` es evidencia de fallo, no una modalidad final aceptable.
4. **Penetración F8:** las tolerancias del resolvedor y la protección de movimientos/giros requieren investigación propia. No se confundió con sincronización ni se cambió el grosor de pared para aceptar la prueba.
5. **Presentación y transporte F9:** búfer bajo jitter, muestras fuera de orden, redundancia de inputs y protección visual completa siguen pendientes. No se certificaron mediante este subconjunto de casos.

## Siguiente puerta técnica: capacidad real de rollback de una isla

Para preservar respuesta inmediata y autoridad del host, la alternativa a evaluar es **simular conjuntamente los cuerpos que se afectan y disponer de restauración y repetición física de esa isla**, con sus comandos y cambios de topología. No basta convertir el proxy retrasado en otro cuerpo dinámico ni sustituir el traslado por un resorte.

Se ejecutó `res://tools/inspect_physics_api.gd` sobre el binario instalado 4.7.2: `PhysicsServer3D.get_method_list()` no expone métodos de paso, guardado o restauración (`step_state_methods: []`). Esto confirma la falta de esa interfaz pública en esta instalación; no prueba que sea imposible construir una extensión.

La documentación de [Jolt: Rolling Back a Simulation](https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md#rolling-back-a-simulation) describe `SaveState` y `RestoreState`, con requisitos adicionales para IDs, altas/bajas y llamadas ordenadas. Son capacidades del SDK; **no están automáticamente disponibles desde `RigidBody3D`**. La [discusión del mantenedor de Godot Jolt](https://github.com/godot-jolt/godot-jolt/discussions/623) también distingue guardar Jolt de restaurar el estado de su integración. No se usa esa discusión antigua como prueba de la API de 4.7.2: para eso está la inspección del binario.

La próxima comprobación de viabilidad debe producir una interfaz nativa o integración existente verificable, aislada del juego, que permita:

- Crear dos cuerpos dinámicos y el piso con geometría y parámetros idénticos en ambos lados.
- Guardar el estado, aplicar comandos durante N pasos, restaurar y repetir los mismos N pasos incluyendo contactos; comparar cuerpos, velocidades, apoyos y reposo.
- Cambiar un comando tardío y demostrar la nueva trayectoria recalculada, con IDs y efectos de juego idempotentes. No repetir sonidos, recogidas o impulsos externos durante replay.
- Mantener fuera de esa isla al personaje y al resto del mundo; declarar cómo se incorporan apoyos, vecinos y geometría móvil antes de prometer una isla local correcta.
- Medir memoria y costo del replay en una ventana limitada, con corte explícito cuando la isla crezca demasiado. No prometer rendimiento en el i3 sin medirlo.

**Esta capacidad todavía no se implementó.** No se instaló un addon, no se cambió el motor y no se migró el proyecto para simular que existe. Si no resulta viable, habrá que elegir explícitamente entre una respuesta con espera del host o una relajación de las garantías de predicción; no introducir ese cambio de experiencia de forma silenciosa.

Disponer de rollback tampoco garantiza correcciones invisibles cuando aparece información nueva. Permitiría recalcular contactos de forma coherente; todavía habría que demostrar selección de la isla, costo y presentación de las divergencias. No se ofrece como solución automática ni se cambian los criterios de las pruebas para aprobarlo.

## Encargo de revisión para Claude

La entrega 2 está en la rama `objetos/implementacion`. La copia de Claude se conserva en `5a5d92f`, con sus pruebas y trazas intactas. El archivo `..\entrega_2.json` registra la base nueva cuando se publica.

Para revisar, desde `validacion_claude`: comprobar que solo haya resultados sin versionar y que no haya cambios de código pendientes; luego importar la rama local de `..\implementacion` mediante `git fetch --no-tags ..\implementacion objetos/implementacion` y `git merge --ff-only FETCH_HEAD`. No resetear, borrar resultados ni reemplazar carpetas. Si hay cambios pendientes o avance incompatible, informar antes de resolverlos.

Prioridad de la siguiente revisión: confirmar F2/F6/F7/F10 y que no se hayan debilitado revisiones, idempotencia o preparación; comprobar el caso temprano con degradación y guardar un ejemplo de ACK con velocidad posterior al impulso. El caso tardío debe seguir registrado como fallo y los contactos dinámicos como modelo no aprobado. No repetir las 29 corridas antes de resolver esa puerta técnica. Si hace falta corregir P5, hacerlo como cambio independiente del verificador, con justificación y conservación del resultado previo.
