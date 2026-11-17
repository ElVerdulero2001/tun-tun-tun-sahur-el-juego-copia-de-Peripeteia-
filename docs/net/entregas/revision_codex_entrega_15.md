# Revision de Claude 15 y entrega 16: registro de acciones del host

2026-11-17. Informe e instrumentos de Claude incorporados sin cambios por avance directo de `76a71bb` a `422884f`.

## Decision sobre la entrega 15

Se aceptan H1 y H2 como resueltos en el alcance independiente: loopback con ENet y NetSync, seis corridas de carriles (incluidos controles negativos con el canal viejo), 308 vencimientos y regresiones del puente/cierre. Claude informa 0 FAIL y 0 INSUFICIENTE. No se repiten las mismas pruebas sin un cambio que lo justifique.

Esto aprueba las correcciones de ciclo de vida y vencimiento, no la integracion de laboratorio, inventario ni rendimiento. El informe completo sigue en `docs/net/validacion_objetos/entrega_15.md`.

## Avance nuevo

`host_action_journal.gd` reemplaza la tabla de dos IDs fijos de la fixture por un componente reutilizable para **un objeto y un peer ya concedidos por la escena**. Se conecta en una fixture nueva de red real. No instala permisos reales de inventario ni modifica el canal o el adaptador validado.

| Operacion | Contrato |
| --- | --- |
| `start(adapter, peer, policy)` | Un solo vinculo por instancia; escena host con adaptador propio. `policy(peer, action, execution_tick)` es obligatorio. Un String vacio permite; otro String rechaza; otro tipo rechaza con `invalid_policy_result`. |
| `request(peer, action)` | Se llama despues de verificar peer/ambito en el canal. Exactamente id, tick, kind, anchor e impulse, con los limites del canal. Rechaza otro peer, datos invalidos, IDs anteriores y conflictos de contenido. Devuelve copias. |
| Programacion | Una accion por tick; solicitado dentro de +/-120 ticks del reloj. Se programa en max(solicitado, reloj+1). La ejecucion conserva orden de IDs: no se inserta una accion nueva antes de otra ya programada; devuelve `action_order`. No reordena ni cambia silenciosamente el tick pedido. |
| `before_capture(tick)` | Proveedor del host antes de `adapter.capture`. Comprueba fase, transicion libre/sostenido y politica en el tick real, y encola en el adaptador. Una revocacion entre recepcion y ejecucion impide actuar. |
| `action_resolved(result)` | Una sola vez por accion registrada al aplicar, rechazar en ejecucion o cancelar. Solo marca `applied` despues de que termine el paso nativo. Conserva requested_tick, scheduled_tick y applied_tick. |
| Duplicado | Mientras se conserva, devuelve el resultado original sin ejecutar otra vez. Otro contenido con el mismo ID se rechaza. Un pedido rechazado antes del registro no consume un ID ni genera resultado terminal. |
| `confirmations()` | Como maximo los 16 ACK fisicos mas recientes, copiados y con tick aplicado real; listos para el sobre existente. No garantiza que toda accion reciba ACK antes de caducar en el cliente. |
| Retiro | Registros terminales anteriores a reloj-120; marca de IDs retirados, sin fingerprints perpetuos. Hasta 256 registros activos. IDs positivos crecientes de 31 bits, sin wrap. |
| Cierre/suspension | Cancela pendientes una vez y deja de admitir pedidos. La escena conecta `channel.closed` a `stop`. `adapter.recovery_required` lo cierra automaticamente. Para otra concesion usar nodos nuevos. |

`cancelled` significa que este recorrido termino sin una confirmacion de ejecucion; no autoriza a repetir un impulso ni prueba por si solo una transaccion de inventario. Detener el registro no suelta por si solo un cuerpo sostenido: la escena conserva la finalizacion del dominio y la recuperacion/reconstruccion del mundo.

La politica es codigo local confiable, recibe una copia y debe limitarse a consultar validacion. No debe reentrar en el registro ni modificar/avanzar el mundo. Los listeners reciben resultados copiados. El modulo no es un RPC ni acepta snapshots; tampoco comprueba `multiplayer.is_server()` en pruebas locales. Solo la escena host debe instanciarlo; nunca concede autoridad por recibir un diccionario.

## Uso y limites de integracion

`probe_journal_network.gd` usa el canal validado, actor real, SimClock, ClientPrediction y NetSync. Sustituye la admision/programacion fija por el registro. Su proveedor llama `before_capture`, su publicador toma `confirmations`, y `action_resolved` registra el tick real de la suelta. Conserva pedido duplicado, demora de 250 ms de la suelta, replay positivo y comparacion exacta en el mismo tick.

La politica de esa escena sigue siendo una **concesion explicita de fixture de una caja a un cliente**. No se presenta como validacion de alcance ni InvAuthority. Los rechazos salen por retorno/callback LOCAL del host; todavia falta enviarlos al cliente y resolver su prediccion de una accion rechazada. El formato de red no cambia en esta entrega.

No se modifican `probe_network.gd`, el laboratorio, InvHands, el inventario, la DLL ni los instrumentos independientes. Sigue pendiente conectar permisos/alcance reales, arbitraje de varias manos/objetos, resultados de rechazo remotos, catalogo/formas reales, presentacion y politica de suelta sin confirmar. `model_approved=false`; `laboratory_migrated=false`.

## Comprobaciones de construccion

Evidencia, hashes y resultados: [resultados_codex_entrega_16.json](resultados_codex_entrega_16.json).

- Corrida final `tmp/lifecycle_probe/20261117_222107_c6d619`: los tres procesos de prueba PASSED y codigo 0. `host_journal`: 10530 comprobaciones, 0 fallas; 750 ticks con pedidos y un paso adicional para una accion tardia; 749 IDs con un efecto cada uno. Rechazo de transicion invalida y revocacion de politica sin efectos; IDs salteados, duplicados/conflictos, aislamiento de copias, limites de tiempo y confirmacion posterior al paso nativo.
- Maximo estable de 121 registros durante los 750 pedidos. En la cola final con pedidos futuros/cancelados se conservan 123; el limite es 256, no se declara un maximo universal de 121. ACKs limitados a 16; retry viejo rechazado, inversion de orden de IDs rechazada.
- La ultima version de la fixture omite deliberadamente capture en el paso 752. El adaptador detiene su prediccion; la accion en vuelo y otra futura quedan canceladas una vez, sin efectos, y el mundo se queda en el 751. Esta prueba comprueba que un fallo de paso no produzca un ACK fisico.
- `net_journal`: la suelta solicitada en 38 se ejecuta en 47. Cliente y host coinciden en el tick 56 despues de replay desde 48 y al final en 80, con efectos/confirmaciones unicos.
- Corrida anterior `tmp/lifecycle_probe/20261117_222020_0e8485`: pasan registro local, pareja de red (suelta en 48, comparacion en 55 desde 48), regresion de 900 acciones y cierre remoto. La version local anterior usaba cierre explicito; queda rotulada porque la final prueba suspension por captura omitida.
- No hubo fallas funcionales en estas corridas. El aviso del almacen de certificados raiz de Windows es el unico error de entorno excluido por el runner existente. No se recompila Rust, repite N3 ni mide rendimiento de ticks manuales.

Reproducir:

```powershell
& .\tools\testing\run_object_lifecycle_probe.ps1 -Modes 'host_journal,net_journal'
```

Cada proceso sigue limitado a ocho segundos; el runner guarda las fuentes exactas y solo termina sus propios procesos.

## Encargo de Claude: entrega 16

1. Actualizar desde implementacion por fetch local y avance directo, conservando instrumentos. `../entrega_16.json` identifica el checkpoint. Leer el registro y la nueva fixture de red; fijar criterios antes de correr.
2. Validar el registro fuera de los dos IDs de fixture: crecimiento, retiro, huecos y extremos de ID, duplicado pendiente/aplicado/rechazado, contenido conflictivo, peer equivocado y limites de tick. Comprobar atomicidad respecto al mundo y las acciones validas.
3. Probar politica revocada entre recepcion y ejecucion, transicion invalida, retorno de politica de tipo incorrecto y que la politica no pueda modificar el pedido por su copia. Verificar que se consulta al ejecutar, con tick real, y que no hay efecto/ACK de rechazos.
4. Probar futuro alcanzado, orden de IDs frente a ticks solicitados en otro orden, fase erronea, tick de ejecucion omitido, falta de captura, suspension y cierre. Nunca confirmar antes de completar el paso nativo; resultado terminal una sola vez. Documentar que cierre no es auto-release de dominio.
5. Usar ENet/NetSync reales para pedidos duplicados y suelta tardia. Exigir efecto unico, requested/applied correctos e igualdad despues de replay en el mismo tick. Las pruebas de permisos reales, inventario y rechazo remoto siguen fuera del alcance: no declararlas aprobadas por esta fixture.
6. Conservar resultados insuficientes y no reescribir umbrales. No repetir la bateria del nucleo ni los carriles de latidos que no cambiaron, salvo regresion demostrada.
