# Prototipo de objetos en red: entrega 1

**Experimental, pendiente de validación independiente. No está integrado al laboratorio.** Abrir este `project.godot`, no el del proyecto principal. Requiere el Godot 4.7.2 con Jolt que usa actualmente el laboratorio.

## Qué contiene

- Dos cajas de prueba, piso y pared de 2 cm. Origen del cuerpo en su base, centro de masa a media altura. Masa 2 kg, fricción 0,8, restitución 0,05, amortiguación angular 2, CCD y tolerancia de penetración de 2 mm.
- El mismo cuerpo y controlador tanto en host como en predictor. La caída y el contacto los resuelve Jolt. No contiene `_fall` ni replay ficticio del motor.
- Acciones numeradas, revisión persistente al soltar, caché acotada de resultados y liberación al desconectar. El tick solicitado y el aplicado son distintos del tick de la muestra completada.
- Snapshots binarios de 90 bytes, eventos confiables, objetivos de mano y muestras no confiables en canales separados. Estado inicial confiable y huella de configuración.
- Historia física local sin reescribir, comparación de instantes, corrección experimental y un único selector de presentación. El cuerpo no se mueve desde el modelo visual.
- Proxies cinemáticos de la otra caja cuando está a menos de 3 m de un predictor. Usan el reloj remoto y no tienen autoridad sobre el mundo; esa diferencia de tiempo es parte de lo que debe evaluar Claude.
- Trazas JSONL optativas, degradación de red controlada y cierre por duración real. El material del juego no se cambia para ocultar el rebote.

## Cómo ejecutar

En Godot se puede abrir el subproyecto y ejecutar su escena. Por consola, usar el ejecutable real `Godot_v4.7.2.exe`; el lanzador `_console.exe` de esta instalación busca un nombre de archivo que no coincide con el instalado.

Argumentos después de `--`:

| Argumento | Significado |
| --- | --- |
| Sin rol | Un jugador local; no abre puerto |
| `--host` | Host ENet |
| `--join=127.0.0.1` | Invitado; se puede sustituir por la IP del host |
| `--port=43171` | Puerto del prototipo, independiente del laboratorio |
| `--mode=prediction` | Predicción local con cuerpo Jolt, modo predeterminado |
| `--mode=reference` | Invitado sin predicción; referencia con espera de datos del host |
| `--trace=C:/ruta/existente/caso.jsonl` | Traza. La carpeta debe existir y cada proceso usa su propio archivo |
| `--duration-ms=8000` | Cierre a los 8 segundos reales. Sin argumento, sesión manual sin cierre automático |
| `--one-way-ms=100` | Demora agregada a cada envío de este proceso; con 100 ms en ambos extremos se agregan aproximadamente 200 ms de RTT |
| `--jitter-ms=40` | Variación uniforme de cada envío, acotada para no tener demora negativa |
| `--loss=0.05` | Pérdida artificial de envíos no confiables; no elimina eventos confiables |
| `--slow=0.3` | Escala del mundo; debe coincidir en ambas máquinas |

El plan de pruebas debe distinguir la degradación de aplicación de esta entrega de la congestión/retransmisión real de ENet. No son mediciones equivalentes.

Para comprobar carga y cierre existe `tools/testing/run_object_prototype.ps1`, en la raíz del repositorio. Requiere `-EnginePath`, admite `-CheckOnly`, `-Role`, `-Address`, `-Mode`, `-DurationSeconds` (1 a 18), `-OneWayMs`, `-JitterMs`, `-Loss`, `-Slow` y `-LogDirectory`. Tiene límite externo y detecta errores aunque Godot termine con código 0. **Su resultado `LOAD_OK` no significa que la sincronización esté aprobada.**

Controles de la escena: F1 captura/libera el mouse; WASD, espacio y Ctrl mueven la cámara; clic derecho agarra/suelta; izquierdo lanza; rueda cambia distancia; central y movimiento del mouse giran. Son controles del prototipo, no sustituyen las preferencias del laboratorio.

## API para pruebas independientes

Un driver puede instanciar `main.tscn` y esperar `ready_for_input`. En cliente ese indicador espera mundo inicial y sincronización de reloj, no solo la apertura de ENet. No editar la implementación para introducir una prueba.

| Entrada pública | Uso |
| --- | --- |
| `request_grab(uid, anchor, target)` | `anchor` en espacio del cuerpo; `target` lleva el punto de agarre a una pose mundial. Desactiva el seguimiento por cámara para el driver |
| `set_goal(target)` | Objetivo mundial del punto agarrado. Mantiene la cámara fuera de la prueba |
| `request_release()` | Suelta sin añadir impulso |
| `request_throw(direction)` | Dirección normalizada; impulso central de 16 N·s una sola vez |
| `objects[uid]` | Acceso de inspección a `body`, `authority`, `prediction`, `view` y estado recibido. Las pruebas no deben mover el cuerpo o modificar estado canónico salvo preparación explícita del caso |
| `fingerprint()` | Configuración física/protocolo admitida por esta entrega |

El driver se conecta a `SceneTree.physics_frame` o usa un nodo con prioridad explícita. Debe registrar si su orden ocurre antes o después de `_physics_process` del adaptador: una diferencia de orden es un paso de diferencia en una intención, no una autorización para renumerar las trazas.

## Tiempo y trazas

El prototipo prepara un paso por `_physics_process`, captura el resultado de la preparación anterior antes de consumir eventos nuevos y registra `Engine.get_physics_frames()`, `PhysicsDirectBodyState3D.step` y contador de callbacks nativos. En el invitado adapta frecuencia entre 57 y 72 Hz compensando `time_scale`, como el principio usado por `SimClock`; aún no está conectado a ese componente.

La traza tiene `schema: 1`, `kind`, rol, modo, tiempo real en microsegundos, tick local, RTT observado, frecuencia y escala. Los eventos principales son:

| `kind` | Campos adicionales y significado |
| --- | --- |
| `boot`, `world_ready`, `clock_ready` | Separan arranque, estado inicial y preparación para actuar |
| `physics` | Tick físico completado, identidad/revisión/fase, pose `p/q`, velocidades `lv/av`, contactos, impulsos acumulados, duración y callback nativo |
| `request`, `applied`, `result` | Acción, operación, tick solicitado/aplicado, tardanza y estado inicial autorizado cuando se aplica |
| `received` | Muestra autorizada recibida, con su tick propio |
| `reconcile` | Fuente, diferencia y resultado: igualdad, corrección, historia ausente, transición distinta o recuperación necesaria por contacto/bloqueo |
| `visual` | Pose dibujada, instante seleccionado y si proviene del predictor; no debe confundirse con una muestra física |
| `handoff` | Momento de devolución a réplica, muestra y tamaño del ajuste en reposo |

## Límites deliberadamente expuestos de la entrega

1. Esto no implementa inventario, hitbox editable, validación desde ojos del personaje, rayos con historia, adopción del agarre, suelta por pared/muerte ni todos los cuerpos preparados. La selección y los límites de zona son una fixture del prototipo. No sustituir con ellos la autoridad existente al integrar.
2. La reconciliación transporta una diferencia entre poses hasta el presente solo si la historia no registra contactos posteriores y el movimiento corregido pasa las consultas geométricas. No es rollback ni replay. Su estabilidad bajo retraso es una hipótesis que se debe probar.
3. Si hubo contacto, se registra `contact_recovery_required` y se conserva la simulación local hasta recuperar en reposo. Esa espera puede dejar una divergencia física; no se considera resuelta por el hecho de acabar convergiendo.
4. El traspaso inicial exige reposo de ambos lados y que el reloj remoto alcance una muestra autorizada de reposo. Registra la distancia del ajuste, sin suavizarla. Un salto perceptible impide aprobarlo; el umbral no se eleva para aceptar la implementación.
5. Las poses remotas se interpolan entre muestras. Todavía no se incorporó una protección común del recorrido visual para rotaciones y todas las geometrías. Esa garantía del plan queda pendiente, no se presume por tener física Jolt.
6. Una suelta/lanzamiento solicitada antes del ACK del agarre queda dependiente de esa concesión. En esta entrega su ejecución local espera el ACK: hay que medir este caso y corregirlo antes de aprobar respuesta inmediata en pulsaciones rápidas.
7. Los objetivos de mano del prototipo no llevan todavía los seis inputs redundantes del laboratorio. Esa garantía y el presupuesto de payload deberán conservarse al integrar; medir pérdida aquí no certifica el transporte final.
8. La primera revisión compara un solo objeto propio y un vecino. No demuestra comportamiento con pilas, varias islas dinámicas, carga del catálogo ni el rendimiento objetivo.

La validación de Claude debe producir casos reproducibles para estos límites y separar fallos bloqueantes de prestaciones aún fuera de alcance. No marcar el prototipo como apto mientras el contacto, la corrección o el traspaso requieran cambios de modelo.

Referencias de API: [RigidBody3D](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html) y [PhysicsDirectBodyState3D](https://docs.godotengine.org/en/stable/classes/class_physicsdirectbodystate3d.html). El código registra el comportamiento de la versión instalada; la documentación no demuestra que un reintento lógico avance el resolvedor.
