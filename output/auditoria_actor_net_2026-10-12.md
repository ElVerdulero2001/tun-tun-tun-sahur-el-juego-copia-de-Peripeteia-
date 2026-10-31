# Auditoría del laboratorio actor/net

Fecha: 12 de octubre de 2026. Alcance confirmado por el usuario: `scripts/actor`, `scripts/net`, `scenes/actor` y `scenes/net_lab`, con revisión del historial y de la configuración que los acompaña.

**Veredicto: buena base funcional para un laboratorio; todavía no cumple el criterio de una arquitectura aislada, sin estado global compartido y lista para incorporarse al juego.** Conviene conservar el diseño de estado/input/tick, corregir la validación del host y extraer la coordinación del laboratorio. Los problemas encontrados no justifican rehacer todo el motor.

## Historial y versión revisada

- Rama local: `net-lab`, HEAD `97d23ccdd7c7ac1f7166f92cc6107b327b4c2954`.
- GitHub, consultado por su API durante la auditoría: `net-lab` termina en `e1d9eb9d9ce1e9f10f0cb05e6daeca58bfdf812d`.
- Hay dos commits locales posteriores: `1184427` (movimiento libre independiente del delta del frame) y `97d23cc` (reconexión conservando estado).
- Se revisó la evolución desde `0f90cde`, incluyendo adopción/épocas, interpolación, bases móviles, postura, escalera, escalones, Hanging, compañero, cámara lenta y los dos cambios locales. Los mensajes atribuyen coautoría a Claude.
- No aparece un nombre nuevo de producto: `project.godot` conserva `Tun tun tun sahur`. El documento llama al sistema «Arquitectura de movimiento co-op y esqueleto de red»; las clases usan el prefijo `Actor`.
- La modificación preexistente de `project.godot` cambia la etiqueta de características de 4.6 a 4.7; no forma parte de los dos commits anteriores. La auditoría no cambió archivos de implementación.

GitHub: https://github.com/ElVerdulero2001/tun-tun-tun-sahur-el-juego-copia-de-Peripeteia-/tree/net-lab

## Qué funciona bien

1. **Estado explícito.** `ActorState` concentra posición, velocidad, postura, modo, anclas, temporizadores y época. `ActorInput` guarda el input cuantizado. Esto permite restaurar y repetir una simulación de forma verificable.
2. **Una secuencia clara de simulación.** `SimClock` ordena los actores y `ActorMotor.step()` ejecuta etapas explícitas. Los actores no compiten con sus propios `_physics_process`. Es una elección razonable para reconciliación y relaciones entre compañeros.
3. **Presentación distinguible de la simulación.** Los desvíos visuales del cuerpo, el suavizado de agarres y la interpolación remota tienen objetivos claros y no gobiernan el movimiento lógico.
4. **Sin dependencias externas adicionales encontradas para este sistema.** El laboratorio usa GDScript y clases del motor, Jolt, ENet y `SceneMultiplayer`. No encontré un addon de networking, GDExtension, biblioteca nativa o paquete externo necesario para estas carpetas. Esto no significa que el motor sea una función pura: sigue necesitando la escena física de Godot.
5. **Pruebas de comportamiento útiles.** La repetición compara estados byte a byte; el barrido tiene criterios de captura, falsos agarres, penetración y movimiento visual. Es una evidencia bastante mejor que limitarse a comprobar que el proyecto abre.

## Hallazgos y prioridad

### 1. Prioridad alta: el host adopta campos que no validó

Ubicación: `scripts/net/claim_adoption.gd`, líneas 57–77; `scripts/actor/actor_motor.gd`, línea 479 y siguientes.

La adopción verifica época, distancia de posición, coherencia del ancla y que la pose entre en la geometría. Luego reemplaza **todo** `actor.state` por el estado del cliente. No restringe suficientemente la velocidad ni los temporizadores y campos que el diseño atribuye al host.

Reproducción aislada: partiendo de la misma posición y época, con `slow_left=3` en el host, una afirmación que pide velocidad `(1000, 1000, 0)`, `slow_left=0`, `hooked_by=123456` y `coyote_left=10` devuelve `ADOPTED`. El actor termina con esos valores.

La prueba llama a `consider()` con el mismo formato binario que recibe desde `NetSync`; no es una demostración de ataque remoto completo. Sí confirma que la frontera de validación acepta ese estado. Para un co-op con clientes cooperativos puede existir tolerancia deliberada, pero entonces la autoridad del host debe describirse con ese límite. La coincidencia de época por sí sola no demuestra que los campos contengan los efectos del evento.

Corrección recomendada: definir qué campos puede aportar el cliente, preservar/validar los que controla el host y validar rangos, transiciones y movimiento admisible. Conservar la tolerancia para diferencias físicas pequeñas sin permitir que esa tolerancia autorice el estado completo.

### 2. Prioridad media: hay registros globales con comportamiento de singleton

Ubicaciones:

- `scripts/actor/base_registry.gd:13`: `_bases` es estático.
- `scripts/actor/ladder.gd:15`: `_ladders` es estático.
- `scripts/net/sim_clock.gd:113`: `_world_slow` es estático.
- `scripts/actor/actor_body.gd:105`: los compañeros se buscan en el grupo de actores de todo el `SceneTree`.

No son autoloads ni existe una propiedad literal `Singleton.instance`, pero son estado mutable compartido por todas las instancias. Si el criterio es evitar singletons funcionales, el sistema no lo cumple.

Los registros de bases y escaleras tienen limpieza en `_exit_tree`: no sería correcto decir que nunca se limpian. El problema es su alcance global y que un ID repetido sobrescribe silenciosamente la entrada anterior. Reproducción: registrar A y B con el mismo `base_id` deja B; quitar B deja el registro vacío aunque A siga existiendo.

También se comprobó que agregar un segundo `SimClock` borra los tramos de cámara lenta del primero, porque `_ready()` llama al limpiador estático. El reloj cambia `Engine.physics_ticks_per_second` y `Engine.time_scale`, de alcance global. Al salir impone 60/1 en vez de restaurar los valores previos.

Con un único mundo y un único reloj esto puede funcionar, como muestra el laboratorio. Complica mundos simultáneos, escenas aditivas, pruebas aisladas y reutilización. Corrección recomendada: un contexto de simulación por sesión/mundo con registro de bases, escaleras, actores y tiempo; pasar ese contexto a quienes lo necesitan y detectar IDs duplicados. No hace falta convertir cada clase en un servicio global nuevo.

La consulta estática reutilizable `_probe_params` de `ActorMotor` es un caché técnico; no la equiparo por sí sola con un singleton de gameplay.

### 3. Prioridad media: el laboratorio contiene parte esencial del runtime

Ubicación: `scenes/net_lab/net_lab.gd`, especialmente líneas 1118, 1170, 1324, 1466, 1492 y 1506.

Sus 1.879 líneas mezclan menú, controles, cámara, métricas, scripts de pruebas y reglas indispensables: orden de recepción/corrección, aplicación de eventos, adopción, envío de snapshots, relación entre compañeros, cámara lenta y respawn.

El problema no es simplemente la cantidad de líneas: instanciar `ActorBody`, `SimClock` y `NetSync` en otro nivel no reproduce el comportamiento sin trasladar también esta coordinación. `ClaimAdoption`, `ClientPrediction` y `RemoteInterpolation` tienen como consumidor de producción actual al script del laboratorio.

Corrección recomendada: extraer un coordinador de la simulación/sesión y dejar al laboratorio crear el nivel, configurar pruebas y mostrar controles. Mantener una secuencia de tick explícita; dividirla indiscriminadamente en muchos nodos no mejora la arquitectura.

`ActorMotor`, con 944 líneas, reúne seis modos y sondas. Tiene organización interna reconocible y pruebas. Su tamaño solo no prueba una mala implementación. Se pueden extraer modos o sondas si el crecimiento dificulta cambios concretos, manteniendo un solo dueño de las transiciones.

### 4. Prioridad media: recepción y compatibilidad insuficientemente acotadas

Ubicación: `scripts/net/net_sync.gd:164`, `scripts/actor/actor_state.gd:135`, `scripts/net/net_session.gd:202`.

`_accept_inputs()` lee contadores y registros sin comprobar previamente todos los bytes disponibles. Comprueba el tamaño de cada afirmación, pero no sus enums y rangos. Tampoco restringe los ticks al intervalo razonable alrededor del tick del host.

Reproducción: diez paquetes válidos con seis inputs cada uno, fechados desde el tick 100.000, quedan con 60 entradas guardadas cuando se consulta el tick 100. La poda solo elimina pasado antiguo, no futuro arbitrario. Repetir el patrón permite seguir aumentando el almacenamiento; no se comprobó un agotamiento de memoria real.

La autenticación comprueba la longitud de la llave de reconexión. No verifica versión de protocolo ni igualdad de configuración de movimiento. El propio comentario de `ActorTuning` advierte que host y cliente deben usar los mismos valores, porque las diferencias pueden producir divergencia sin aviso.

Corrección recomendada: decodificación con rechazo explícito de paquetes inválidos, límites de cantidad/tamaño/ticks, validación del estado antes de tocar el cuerpo, y verificación de compatibilidad al conectar. Para ajustes que afectan la física, acordar una configuración o comprobar su huella.

### 5. Prioridad baja: la configuración del actor apunta al laboratorio

Ubicación: `scripts/actor/actor_tuning.gd:15` y `:140`.

La función usada por las pruebas lee los exports buscando el script dentro de `res://scenes/net_lab/net_lab.tscn`. Esto evita que las pruebas ignoren los valores elegidos en el Inspector, lo cual está bien, pero agrega una dependencia del código del actor a una escena de laboratorio. Un cambio de ruta o estructura obliga a atender este lector.

Corrección recomendada: separar el lector de pruebas del tipo de configuración o hacer explícita su fuente. Se puede conservar el nodo editable en el Inspector, que fue una preferencia del usuario; esta observación no exige convertirlo a `.tres`.

## Autoloads y código sin uso

`project.godot` conserva `UIHacking` y `DebugDraw`, presentes antes del laboratorio. No encontré referencias a ellos desde las carpetas auditadas y el sistema corrió en una copia sin esos autoloads. Por tanto, el laboratorio **no depende** de ellos, aunque al abrirlo dentro del proyecto completo se carguen los autoloads del proyecto.

Los 17 scripts de `scripts/actor` y `scripts/net` tienen consumidores estáticos encontrados por nombre de clase o ruta de recurso en scripts/escenas. No encontré scripts completos huérfanos dentro del alcance. La búsqueda por texto es una comprobación estática, no una garantía de que cada rama de cada función sea alcanzable.

`ActorBody.active_stance()` (`scripts/actor/actor_body.gd:131`) no tiene llamadas encontradas en los scripts actuales. Es un candidato menor a limpieza o una API aún sin consumidor; no basta para afirmar que todo el proyecto esté lleno de código muerto. Los archivos de `player_v2`, archivos históricos y assets quedan fuera del alcance confirmado, y no se propone borrarlos.

## Verificación ejecutada durante esta auditoría

Se creó una copia mínima del código actual en `tmp/audit_actor_net_20261012`, usando el ejecutable instalado Godot 4.7.2 y Jolt. La copia no tiene los autoloads del proyecto; usa renderizado compatible para ejecución sin ventana. Los scripts originales se copiaron sin cambios. La carpeta tiene `.gdignore` para que el proyecto principal no importe estas copias como clases duplicadas.

| Comprobación | Resultado |
| --- | --- |
| Repetición a 60 ticks/s | Exit 0; 5.311 ticks de recorrido, 5.327 repeticiones y 237.617 ticks repetidos; coinciden byte a byte |
| Repetición con ritmo variable entre 57 y 72 | Exit 0; mismas cantidades y misma huella `db0389fa454c82d1` |
| Cobertura del recorrido | Suelo, aire, slide, escalera, Hanging, cambios de postura y cámara lenta; no cubre todo el sistema de red ni Hooked |
| Barrido de Hanging | Exit 0; 1.545/1.547 capturas buscadas, 0/330 agarres no buscados del criterio, cero ticks de penetración y salto visual máximo de 0,09 m en 50 ms |
| Host/cliente reales en procesos separados, localhost, corte de ocho segundos por relevo UDP | Ambos exit 0; reconexión lograda, posición preservada `(2, 0.0009, 4.001)`, cero correcciones en este recorrido |
| Pruebas de los hallazgos | Sobrescritura del registro, borrado del tiempo global por otro reloj, adopción de campos indebidos y retención de ticks futuros reproducidos |

Godot emitió advertencias/errores de acceso al almacén de certificados del sistema en este entorno y, en las primeras corridas, al archivo global `user://logs`; los resultados se capturaron por stdout/stderr. No aparecieron errores de scripts en esas corridas. La prueba de pareja usó un archivo de log dentro de la copia.

No se repitieron pruebas en dos PC, builds exportadas, otros sistemas operativos ni toda la matriz de latencia/pérdida. Los resultados anteriores no garantizan determinismo universal ni que todas las mecánicas estén libres de bugs. Los scripts de pruebas existentes imprimen cobertura, pero una cobertura que cae al modificar el tuning no convierte por sí sola la prueba de repetición en fallo: hay que evaluar esa cobertura.

Logs y arneses: `replay_60.log`, `replay_varying.log`, `hang_sweep.log`, `audit_probes.log`, `pair_0.log`, `pair_1.log`, `audit_probes.gd`, `run_audit.ps1` y `run_pair_audit.ps1`, dentro de la copia temporal.

**Orden sugerido de trabajo:** primero limitar la adopción y validar lo recibido; después eliminar el alcance global implícito y extraer la coordinación del laboratorio; luego desacoplar la configuración y retirar APIs sin consumidores. Conservar las pruebas y agregar comprobaciones para estas fronteras al corregirlas.
