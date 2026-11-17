# Revision de Claude 14 y entrega 15: latidos confiables y aviso de vencimiento

2026-11-17. Base de implementacion `c127cf8`; informe e instrumentos independientes incorporados por avance directo hasta `8073085`, sin modificarlos.

## Decision

Se aceptan los resultados de Claude dentro del alcance medido: cierre remoto, rechazo de controles con peer/ambito incorrectos, dos slots sin ticks futuros, retiro acotado y recuperacion con acciones. H1 es bloqueante: un latido no confiable puede desaparecer por el throttle de ENet y provocar el cierre de un vinculo vivo. H2 tambien es valido: sin un evento de vencimiento la escena no distingue una confirmacion pendiente de una que ya no llegara por esta API.

No se declara verde la entrega 14 completa. Se conserva su informe original, incluidos los FAIL de los carriles silenciosos y los limites de cobertura. No se migra net_lab mientras estas correcciones esperan revision independiente.

## Cambios

1. `authority_channel._heartbeat` usa RPC confiable en canal 0, separado de los fragmentos de snapshots en canal 1. Mantiene el intervalo de 500 ms, el lease de 5 s, el mismo ambito y validacion de remitente. No aumenta umbrales ni toca el throttle de ENet o el transporte de inputs de NetSync. Ambos extremos deben cargar este canal nuevo. Confiable permite retransmision; no garantiza presencia ante una perdida total o una demora de red superior al lease.
2. `history_bridge.action_expired(id, kind, requested_tick)` se emite una vez al retirar una accion conocida que nunca fue confirmada. La limpieza se completa antes del callback. Una accion confirmada no emite vencimiento; una accion encolada cuya ejecucion se cancelo al suspender tambien vence. El retiro se comprueba aunque falte la captura de input. No se guardan IDs vencidos adicionales: memoria acotada.
3. El borde sigue igual: un ACK al cumplir 120 ticks confirma; al avanzar al tick solicitado + 121, sin confirmacion, se emite vencimiento. Un ACK posterior se ignora para callbacks, sin volver a emitir efectos. Replay y recuperacion no reemiten el evento.

El vencimiento significa **resultado de autoridad desconocido por este registro temporal**. No significa rechazo, deshacer una accion, liberar un objeto ni permiso para reintentar una transaccion con otro ID. La escena debe resolver el estado con autoridad y el futuro inventario necesita su ledger persistente. La ventana corre por ticks del reloj; una pausa sin ticks no produce vencimientos por tiempo de pared. El cierre del vinculo sigue teniendo su senal propia.

## Pruebas y evidencia

Ver `resultados_codex_entrega_15.json` para corridas, hashes, resultados completos y limitaciones. Las pruebas propias agregan silencio real mayor a un lease usando el canal base sin subclases RPC y controles de vencimiento exacto, sin duplicados, confirmado en el borde, ACK tardio y accion no ejecutada durante suspension. El runner conserva nombres distintos al repetir un modo.

El primer intento del nuevo driver de silencio fallo por su cierre de prueba: el cliente terminaba antes de que el host midiera, y desconectaba la sesion. Se corrigio el driver con un intercambio de finalizacion despues de que ambas puntas comprueban; no se cambia el runtime para ese fallo. El intento queda preservado en `tmp/lifecycle_probe/20261117_213310_14cb9e`. La corrida posterior `20261117_213355_fb504e` pasa, pero sus modos repetidos sobrescribian los logs del mismo nombre; se corrigio el runner y se usa una corrida final con nombres unicos.

No se alteran instrumentos de Claude, Rust, DLL, fuentes de produccion, permisos ni inventario. No se repite N3 ni se afirma rendimiento, memoria pico o red entre dos PC.

## Encargo para Claude: entrega 15

1. Actualizar `validacion_claude` mediante fetch local y avance directo desde `implementacion`, preservando sus archivos y trazas. El checkpoint y manifest estan en `../entrega_15.json`. Leer este informe y fijar criterios antes de correr.
2. Revisar H1 con canal real: enlaces silenciosos vivos mas de 5 s, ambas direcciones, con throttle bajo medido si se logra, ademas de ausencia real, aviso perdido, cierres, peer/ambito erroneos y timeout de envio. El plazo sigue siendo 5 s; no aceptar la correccion solo por subir el umbral.
3. **Instrumentacion:** `cv14_tap_channel.gd` de Claude redefine `_heartbeat` con `unreliable`. Por ello sus carriles NO prueban el canal confiable nuevo aunque llamen `super`. Crear una version nueva de ese instrumento con la configuracion RPC confiable equivalente, o usar directamente el canal base. Conservar los originales y rotular la adaptacion antes de correr. Codex no los ha modificado ni declara aprobado el modo `lanes` con ese override antiguo.
4. Verificar `action_expired` con ACK a 120 y 121 ticks, sin ACK, duplicados tardios, confirmados que se retiran, accion que nunca ejecuto durante suspension, falta de captura, replay/recuperacion y limpieza antes del callback. Comprobar identidad original, una sola senal por accion y memoria constante. Conservar pruebas de atomicidad de ACK invalidos.
5. Repetir regresiones afectadas del puente y del cierre. No volver a validar el nucleo nativo que no cambio. Informar FAIL/INSUFICIENTE sin ajustar umbrales para convertirlos en PASS.

Siguen pendientes la integracion real con laboratorio, InvHands, permisos, alcance, inventario, varias manos, presentacion, politica de suelta sin confirmar y pruebas en ambas PC. `model_approved=false`; `laboratory_migrated=false`.

## Evidencia de construccion

Resultados completos, hashes y veredictos originales: [resultados_codex_entrega_15.json](resultados_codex_entrega_15.json).

- Runner propio: `tmp/lifecycle_probe/20261117_213458_0e9c8e`. Los 15 procesos de prueba terminan PASSED, codigo 0, sin errores funcionales. Incluye tres parejas en silencio durante mas de cinco segundos, cierre normal, timeout de envio, ausencia real y cliente atrasado. En las tres parejas el throttle del cliente baja a 1/32, sin cierres; el mayor hueco de actividad es 504 ms. No se modifica el umbral de 5 s.
- Fixture de acciones: 3979 comprobaciones, 900 efectos para 900 acciones, memoria activa maxima 121. Comprueba un primer ACK a d=120, 18 vencimientos sin ACK (exactamente d=121), ningun vencimiento de confirmadas y una accion adicional encolada antes de suspender que vence sin ejecutar ni emitir efecto. Confirma limpieza antes del callback y que un ACK tardio no confirma una accion vencida.
- Regresion con instrumentos originales de Claude, sin cambios: `tmp/validacion_objetos/entrega_14/run14_20261117_183538`. 1876 comprobaciones de acciones y 269 del puente, sin fallas; pasan quiet, los tres cierres, ausencia y futuro. Hueco maximo de actividad en quiet: 505 ms, con throttle cliente a host = 1/32 en 12 de 59 muestras.
- Se conserva el reporte original: **32 PASS / 1 FAIL / 1 INSUFICIENTE / 1 HALLAZGO / 2 INFO**. El FAIL del runner cuenta en cada proceso la linea del almacen de certificados raiz de Windows; es la unica linea de error y todos terminan con codigo 0. INSUFICIENTE corresponde a lanes, omitido deliberadamente por su override antiguo. A3h es texto fijo del reporte de la entrega 14: ese instrumento no escucha action_expired y sigue imprimiendo que no existe. No se reescribe el reporte ni se declara que la nueva senal fue validada por Claude.
- Primer intento propio descartado: el driver de quiet dejaba salir al cliente antes de que el host terminase su intervalo y lo desconectaba. Se corrigio el handshake del driver y se conservaron los resultados fallidos. La corrida intermedia paso pero reutilizaba nombres en las repeticiones; el runner final agrega sufijos y conserva todas las parejas.

No cambian produccion, Rust, lockfile ni DLL. No se recompila ni repite N3. Los resultados no certifican rendimiento, RAM pico, red real o integracion con inventario.
