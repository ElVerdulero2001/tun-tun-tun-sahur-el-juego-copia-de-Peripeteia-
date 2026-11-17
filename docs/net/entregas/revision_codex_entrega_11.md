# Revisión de Claude 11 y entrega 12: fuente real de historia del actor

2026-11-17. Se revisaron criterios, informe e instrumentos de `b4aa90c` sobre `0aed621`, y se incorporaron por avance directo a `implementacion`. La copia y los verificadores de Claude se conservan sin cambios.

## Decisión

Se acepta la API local de la entrega 11 en el alcance probado: ámbito/revisión, confirmación posterior a aplicar, invalidación y recuperación, atomicidad y límites. Claude obtuvo 55 PASS/0 FAIL/9 INFO en los cinco modos nuevos y conservó sus regresiones. Las observaciones H6 son válidas: una acción cancelada puede aparecer físicamente en la recuperación sin un efecto local y registrar un ID no demuestra ejecución.

La entrega 12 conecta un registrador con el replay real de `ClientPrediction` y resuelve esas dos observaciones mediante estados de cola explícitos y señales de confirmación/efecto. No agrega transporte ni instala todavía el recorrido en el laboratorio.

## Qué se construyó

1. **Registrador mientras la física está detenida.** `history_bridge.gd` captura intención, ojos y estado del actor, dt y acciones por tick, aunque el adaptador nativo no esté listo. La historia queda acotada e incluye el período suspendido. Se excluye de una copia `held_claim`, que es salida de predicción; no se cambia el input original.
2. **Ojos provenientes del replay real.** El puente delega en `ClientPrediction.reconcile`/`replay_from` y en el callable de paso del dueño de la escena. Observa el actor después de cada `ActorMotor` real y reconstruye el diario. No entrega una traslación fija de ojos como en las fixtures anteriores.
3. **Tiempo anunciado hacia atrás.** El punto de conexión agrega el tramo, invalida el objeto inmediatamente y pide el replay real del personaje; no espera al próximo snapshot de objetos. Si falta la historia, se queda detenido hasta obtener una base de actor válida.
4. **Estado coincidente con historia inválida.** Se agregó a `ClientPrediction.reconcile` un argumento final opcional, `replay_matching_state = false`. Solo el nuevo puente lo usa para reconstruir los ticks posteriores cuando su base quedó invalidada. Los llamadores existentes conservan el comportamiento por defecto y se mantienen las protecciones de input tardío/afirmación antigua. Es el único cambio en producción; no se cambian ActorMotor, SimClock, NetSync o el protocolo.
5. **Generaciones con el mundo detenido.** `invalidate_history_from` considera también el tick terminado del actor cuando el mundo nativo está congelado. Una corrección de esos ticks cambia el token; ya no se trata como futura por estar después del último paso nativo.
6. **Resolución de efectos.** El puente diferencia `queued`, `known` y `rejected`. `effect_ready` emite una vez por ID, desde la ejecución provisional o desde su primera confirmación aceptada. `action_confirmed` es independiente y se emite una vez. No hay sonidos ni transacciones implementadas por esas señales.

API, orden y responsabilidades: [README del adaptador](../../../prototypes/objetos_adaptador/README.md). El dueño de escena debe mantener `ClientPrediction.record` incluso durante la suspensión y usar su paso local existente, incluidos eventos/consumibles. Los ejemplos de pruebas no certifican la integración del inventario.

## Comprobaciones

- Los cinco modos `hist_*` ejecutan la clase real `res://scripts/net/client_prediction.gd`, el motor y el actor de producción. Los ojos esperados se observan dentro del callable real de replay y se comparan con el diario del puente.
- `hist_actor`: corrige un estado del tick 15 al comenzar el 26, repite realmente 16–25 y recupera el mundo nativo desde el 14 con esos registros y el nuevo 26. No se vuelve a mover el actor durante el replay nativo y queda igual por bits a la referencia.
- `hist_time`: anuncia en 30 un tramo pasado 20–34, ejecuta `ClientPrediction.replay_from` con el dt nuevo y obtiene ojos/estados realmente repetidos. El objeto se detiene desde el anuncio y se recupera con la historia reconstruida.
- `hist_gap`: falta el ancla del personaje; la recuperación se bloquea. Un snapshot coincidente del tick 30 fuerza tres pasos reales al comenzar 34. El cambio histórico posterior al último paso nativo congelado cambia la generación. Luego se recupera el objeto.
- `hist_effect`: una suelta encolada para 31 se cancela al corregir al actor en 30; aparece físicamente en la recuperación de 35. La confirmación del estado 36 emite su primer efecto en 37; otra revisión con el mismo ACK no repite efecto ni confirmación. `known` informa que el ID estaba registrado, no ejecutado.
- `hist_guards`: la ruta anterior de coincidencia sigue sin repetir al actor; el replay optativo conserva las protecciones de afirmaciones antiguas e input tardío.
- Los otros once escenarios del adaptador se mantienen. Los procesos propios usan ritmo real, sin fixed-fps, con límite externo de 8 s. Los instrumentos de Claude usan su fixed-fps original.

El resumen y las carpetas finales figuran en [resultados_codex_entrega_12.json](resultados_codex_entrega_12.json). El núcleo Rust/binding/lockfile y la DLL son los de la entrega anterior; no se recompilan ni se repite N3. La regresión original de Claude 11 da 55 PASS, 0 FAIL y 9 INFO; no se modifican sus instrumentos. El único aviso de Godot es el conocido de certificados raíz de Windows.

## Límite preciso

Este prototipo **sí llama al replay real del personaje**; los snapshots que lo disparan siguen siendo inyectados localmente. La escena `net_lab.gd` conserva sus llamadas y su física anteriores: no instancia el puente y no se conectó todavía la recepción de NetSync/ENet. Tampoco están migrados selección/InvHands, permisos, inventario, múltiples manos, catálogo/topología variable, ciclo de vida de actor/conexión ni presentación. Las señales nuevas no equivalen a transacciones del inventario.

La firma de `ClientPrediction.reconcile` es compatible con los llamadores anteriores. Antes de publicar este cambio para dos PC deben compartir el mismo código/fingerprint. No se alteró el formato de paquetes. La integración final deberá sustituir el recorrido anterior, no ejecutar dos predictores sobre el mismo objeto.

Historia limitada a 120 ticks/256 KiB serializados, además de contenedores; la historia interna de ClientPrediction conserva las reglas del sistema existente. No se midieron memoria pico ni rendimiento en la notebook. **`model_approved=false`; `laboratory_migrated=false`.** El siguiente trabajo es transporte acotado y conexión del recorrido experimental con recepción real, conservando estas garantías.

## Encargo de Claude: entrega 12

1. Actualizar su copia por fetch local y avance directo desde `implementacion`, conservando pruebas y trazas. `../entrega_12.json` identifica el checkpoint. No hay dependencias o cambios nativos nuevos; puede compilar su DLL con la caché compartida como antes.
2. Leer `history_bridge.gd`, el argumento optativo de ClientPrediction y el README. Fijar criterios propios antes de correr. Instrumentos en `prototypes/objetos_adaptador/validacion_claude/`; no modificar implementación, producción, núcleo, runners/fixtures de Codex ni tolerancias.
3. Verificar en el motor que se ejecuta ClientPrediction real y que los ojos/estados de cada frame salen de sus pasos reales. Variar movimiento, postura, input, correcciones y tramos pasados; comparar con una referencia propia, no con una traslación de ojos prefabricada.
4. Cubrir grabación durante suspensión, falta de historia, reanudación por estado coincidente, generaciones posteriores al mundo congelado, huecos/recuperación, reintento de captura idéntico y conflicto. Comprobar que el input original y sus claims no se modifican y que el replay nativo no vuelve a simular al actor.
5. Probar primer efecto por confirmación de una acción ejecutada solo en recuperación, revisiones/ACK duplicados y la diferencia entre ID conocido y acción ejecutada. Mantener separados efecto provisional y confirmación; no certificar permisos o transacciones no implementados.
6. Revisar el comportamiento anterior de ClientPrediction con el parámetro omitido y los guardas de input tardío/afirmación antigua con la opción activa. Ejecutar las regresiones pertinentes, conservando S1 anulado por el conteo conocido y sin modificarlo para volverlo verde. No repetir N3.
7. Procesos limitados a 8 s. Informe en `docs/net/validacion_objetos/entrega_12.md`. No certificar red, recepción real de NetSync, laboratorio migrado, dos PC ni rendimiento.
