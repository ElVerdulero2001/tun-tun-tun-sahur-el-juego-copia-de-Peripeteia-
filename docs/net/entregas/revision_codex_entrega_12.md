# Revisión de Claude 12 y entrega 13: recepción real y transporte de estados

2026-11-17. Base construida `c1359d2`; informe, criterios e instrumentos de Claude (siete archivos) incorporados por avance directo hasta `1356cee`, sin modificarlos.

## Decisión sobre la entrega 12

Se acepta el puente en el alcance probado por Claude: ojos/estados desde pasos reales de ClientPrediction/ActorMotor, grabación durante suspensión, recuperación exacta, huecos, generación, estado coincidente, confirmación y efecto únicos. Sus cinco casos de comparación con la versión anterior conservan el comportamiento por defecto de ClientPrediction. Resultado independiente: **60 PASS / 0 FAIL / 1 INFO**. Codex reprodujo el mismo resultado con los instrumentos originales.

Se conservan sus límites: snapshots de prueba inyectados localmente, acciones nuevas rechazadas durante suspensión, memoria sin medir y ninguna aprobación de inventario/permisos/laboratorio. El conflicto de captura fue leído pero no ejercitado en su escena. Algunas métricas de listas muestran el valor final por referencias mutables; no se modificaron las comprobaciones ni se oculta esa limitación.

La observación sobre `client_prediction.gd` del proyecto principal es correcta: se reflejó la versión de la entrega 12 con comprobación de su base, conservando los cambios locales anteriores y sin commit en el Git original. La entrega 13 no agrega cambios a producción: el laboratorio mantiene su llamador anterior y no instancia el puente nuevo.

## Entrega 13

1. **Canal ENet por escena**, servidor → invitado concedido, con formato binario acotado. El vínculo con el emisor precede al rearmado y a cualquier restauración nativa. Se verifican ámbito/revisión/tick, tamaños, duplicados, integridad y caducidad. Los RPC nunca restauran mundos.
2. **Control de flujo:** un envío en vuelo, ACK remoto de transferencia completa, un único sobre más reciente pendiente, ocho fragmentos por callback y un único rearmado parcial. La caducidad detiene el vínculo. Un canal detenido requiere otro nodo/conexión; no resucita mensajes de una sesión previa.
3. **Punto de conexión con NetSync real:** los estados recibidos del actor y los anuncios de cámara lenta entran a `history_bridge`; el estado nativo se aplica solo después del actor/registrador o en pausa. Si se cierra el canal, se invalida la predicción del objeto.
4. **Intenciones de acción cliente → host** pequeñas y confiables, con el peer/ámbito concedido. El dueño de la escena valida y programa. La fixture tiene una concesión explícita para una caja y una tabla de dos acciones; el ACK contiene el tick efectivamente aplicado. No es la autoridad general del inventario.
5. **Dos procesos reales:** `probe_network.gd` utiliza NetSync para inputs/estados del personaje y ENet para snapshots nativos y pedidos de acciones. Una suelta enviada con retraso llega después del tick solicitado; una repetición del ID no duplica aplicación o efecto. El modo `net_time` recibe por NetSync el anuncio pasado y utiliza el replay real del personaje.

API y responsabilidades: [README de red](../../../prototypes/objetos_adaptador/README_network.md). Entradas: `authority_channel.gd`, `scene_network_bridge.gd`. Reproducción: `tools/testing/run_object_network_probe.ps1`.

## Verificación y evidencia

Los dos modos de red deben pasar en ambos extremos, a ritmo real y con 8 s por proceso. Se exige igualdad del estado nativo entre procesos en el mismo tick después de un replay de uno o más pasos desde un checkpoint posterior a la suelta; esa comparación ocurre antes del checkpoint final. También se compara el final, y se exige corrección real del actor, recepción NetSync y efectos/confirmaciones únicos.

Las pruebas de parser, emisor equivocado, conexión antigua, tamaños, fragmentos fuera de orden, reintentos, conflictos, digest, ámbito, caducidad y presión de envío utilizan un punto de prueba local de nodos vinculados a la conexión viva. Los bytes opacos de esas pruebas nunca se entregan a la extensión. No equivalen a ataques RPC de un tercer proceso o una red adversarial. Los ACK de transferencia de la corrida sí son RPC reales.

Se conservan los 16 modos anteriores y la regresión original de Claude 12 (60/0/1). Resultados, hashes y carpetas de las corridas finales: [resultados_codex_entrega_13.json](resultados_codex_entrega_13.json). Los primeros intentos de construcción y sus logs se conservan; no se presentan como corridas aprobadas. El núcleo nativo, lockfile, bindings, DLL e instrumentos de Claude no cambian. No se recompila ni se repite N3.

## Alcance pendiente

Ahora hay recepción real en una escena de prueba con dos procesos de una PC. **`net_lab.gd` todavía no instala el recorrido.** No hay cambios de producción en esta entrega. Quedan concesiones/permisos de objetos reales, selección/InvHands, inventario, varias manos, topología/catálogo, presentación y ciclo de vida de sesión del laboratorio. El driver arranca con un adelanto fijo y no certifica el sincronizador de ping del laboratorio.

Un checksum y una conexión autorizada no vuelven seguro el deserializador ante snapshots nativos hostiles: siguen siendo trusted y provenientes de un host de confianza. No se hicieron pruebas en dos PC físicas, medición de memoria pico ni rendimiento en la notebook. `model_approved=false`; `laboratory_migrated=false`.

## Encargo de Claude: entrega 13

1. Actualizar por fetch local y avance directo desde `implementacion`, conservando pruebas y trazas. El checkpoint está en `../entrega_13.json`. Leer el README de red y fijar criterios propios antes de ejecutar.
2. Revisar `authority_channel.gd` y `scene_network_bridge.gd`. No modificar implementación, producción, núcleo, runners/fixtures de Codex ni tolerancias. Crear instrumentos propios en `prototypes/objetos_adaptador/validacion_claude/` y el informe `docs/net/validacion_objetos/entrega_13.md`.
3. Probar dos procesos ENet con fuentes reales de NetSync, ClientPrediction, actor y reloj. Confirmar que los estados del actor y los tramos de tiempo provienen de RPC de NetSync y que las acciones/snapshots de objetos usan el canal real. Comparar estado nativo en el mismo tick después de replay positivo, antes de una restauración final sin replay.
4. Variar demora/orden de recepción, cámara lenta pasada, correcciones del personaje, suelta tardía, pedidos/ACK duplicados, estado futuro y pausa. Separar ACK de transferencia de confirmación física. No convertir efectos en prueba de transacciones del inventario.
5. Verificar límites de formato, emisor/vínculo, conexión/ámbito antiguos, sobre/fragmentos truncados o excesivos, duplicados conflictivos, integridad, rearmado/timeout y liberación de buffers. Verificar un envío en vuelo, reemplazo del pendiente, espera del ACK, cierre y prohibición de reutilizar un nodo detenido. Buscar acumulación fuera de esas estructuras. Los buffers de prueba de transporte no deben llegar al deserializador nativo; no repetir N3.
6. Revisar rechazo de acciones nuevas mientras se suspende y, si es útil, cubrir el conflicto de captura que quedó sin ejecutar en entrega 12. Distinguir tests de puntos locales del parser y mensajes RPC reales. Registrar cualquier cobertura faltante.
7. Reproducir ambos modos nuevos y las regresiones pertinentes con instrumentos originales. No es necesario recompilar/repetir todo Rust si los hashes del núcleo no cambiaron. Mantener S1 anulado por el conteo conocido y no modificarlo para volverlo verde. Procesos limitados a 8 s; no certificar integración del laboratorio, inventario, dos PC o rendimiento.
