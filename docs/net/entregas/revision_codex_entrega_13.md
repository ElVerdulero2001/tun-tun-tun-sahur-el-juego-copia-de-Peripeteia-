# Revisión de Claude 13 y entrega 14: cierre, estados futuros y acciones prolongadas

2026-11-17. Informe, criterios e instrumentos de Claude incorporados sin cambios por avance directo de `c090b7d` a `f6d3af4` (ocho archivos).

## Decisión sobre la entrega 13

Se acepta la evidencia del recorrido de recepción/replay en el alcance medido: NetSync y ENet reales en dos procesos de una PC, con 113 comparaciones calificadas entre sus dos corridas, ninguna distinta; 43 de ellas con la caja sostenida e inputs iguales. Los parsers, límites de transferencia y distinción entre ACK de transferencia y confirmación física quedaron comprobados en los casos informados.

**No se declara la entrega completamente verde ni se instala en net_lab.** Su corrida final tiene 143 PASS, 2 FAIL, 2 INSUFICIENTE, 3 HALLAZGO y 3 INFO. Los FAIL registrados son cobertura insuficiente de una ventana posterior a la suelta y una acción durante una suspensión que terminó dentro del mismo tick. Se conserva el informe entero, las corridas anteriores y los criterios. El estrangulamiento de inputs de ENet que Claude observó también sin tráfico de objetos no se modifica aquí.

Los tres hallazgos de construcción son válidos: cierre de un solo lado, inanición por reemplazo continuo del estado futuro y agotamiento de 256 IDs por vínculo. Se corrigen antes de integrar el laboratorio.

## Correcciones de la entrega 14

### Cierre y detección de ausencia

`authority_channel.stop()` avisa al otro extremo mediante un RPC confiable de control en el canal 0, separado de los fragmentos del canal 1. El receptor comprueba el peer y los 52 bytes del **ámbito completo** antes de cerrar localmente, sin reenviar el aviso. `closed` se emite una vez, libera los buffers del canal y los dos estados del puente e invalida la base/predicción del objeto. También se usa cuando vence un envío.

Tras comenzar tráfico real hay un heartbeat cada 500 ms; si no se recibe actividad del otro extremo en 5 s, el vínculo caduca aunque se pierda el aviso. Antes del primer tráfico también hay 5 s de plazo de inicialización: el dueño debe comenzar publicación/pedidos dentro de ese plazo. Los nodos usados solo como parser local no mandan controles a una ruta remota inexistente. Los controles no certifican frescura del estado físico ni sustituyen la política de sesión del juego.

`stop(false)` permite cerrar localmente sin aviso (la prueba simula un aviso perdido). Desconexión, control remoto o plazo de ausencia terminan el vínculo; no se reutiliza el nodo. Cambios de conexión/contexto/concesión siguen necesitando una instancia nueva y un ámbito vigente. Los formatos de snapshots/inputs de NetSync y la extensión nativa no cambian; ambos extremos deben usar la versión nueva del canal.

### Cliente atrasado

`scene_network_bridge.gd` conserva el primer estado futuro esperando que el reloj lo alcance y un único sucesor más reciente. Si el sucesor ya es aplicable, se elige el más nuevo para ahorrar replay. Tras consumir un estado se promueve el sucesor. Hay como máximo **dos sobres en el puente**, además del sobre del canal y su rearmado. El nuevo tráfico ya no desplaza indefinidamente al primero. Nunca se aplica un tick futuro; en pausa también se respeta ese requisito. El cierre libera ambos slots.

### Registro de acciones con ventana

Los IDs nuevos deben ser **estrictamente crecientes, positivos y sin reutilización** dentro del vínculo (se admiten saltos); siguen limitados a 31 bits. Los duplicados conservados se comparan con su contenido original. Fuera de la ventana se conserva una marca de retiro, no cada fingerprint: un reintento viejo devuelve `retired_action` y un ID nuevo menor al máximo devuelve `nonmonotonic_action_id`. Agotar el rango de IDs requiere otro vínculo; no hay wrap.

Se retiran registros cuyo tick es anterior a `tick_actual - 120`, también mientras el objeto está suspendido. Los fingerprints, identidades, efectos y confirmaciones activos quedan acotados; la defensa de capacidad 256 sigue existiendo para datos activos, pero ya no es un máximo de acciones durante toda la partida. El driver de 900 acciones retuvo como máximo 121 registros.

**Política explícita:** un ACK de un ID ya retirado, con su tick también retirado y formato válido, se ignora para callbacks. No vuelve a emitir efecto **ni emite una primera confirmación tardía**. Una transacción persistente de inventario no debe depender de este registro temporal: requiere su propio ledger/contrato de autoridad, todavía pendiente. No se retiran identidades necesarias para los 24 pasos de replay permitidos. La prueba incluye recuperación con acciones después del retiro y recuperación tras una suspensión larga con un estado actual.

## Comprobaciones y límites

`tools/testing/run_object_lifecycle_probe.ps1` agrega:

- `net_future`: cliente retrasado, publicación continua; exige varios estados aplicados antes de que el host termine, sin aplicar futuro y con final igual.
- `net_close`: cierre real del host y aviso RPC; exige cierre único del cliente, buffers vacíos, base inválida y mundo congelado.
- `net_timeout`: envejece localmente un envío para activar su timeout; el aviso y cierre remoto sí viajan por RPC. No se presenta como pérdida real de ENet durante cinco segundos.
- `net_lease`: omite el aviso con `stop(false)` y espera **cinco segundos reales** hasta el cierre del cliente por ausencia de actividad.
- `action_window`: 900 acciones / 450 ciclos con pasos reales de SimClock, ActorMotor y la extensión. Es un bucle manual y no una medición de rendimiento por cuadro. Reintenta IDs retirados, rechaza IDs menores no vistos, confirma sin duplicar efectos, recupera diez pasos con acciones y verifica 140 ticks suspendidos, retiro y recuperación exacta desde un estado actual. Un ACK de una acción retirada que nunca se había confirmado no emite un callback tardío.

Los dos modos anteriores de red y los 16 del reloj se conservan. Se reproduce la entrega 12 con instrumentos de Claude sin cambios, y se corren `base`, `future` y `conflict_pause` de sus instrumentos 13. El modo `future` original ya aplica estados antes del final; sus comparaciones con replay positivo siguen insuficientes cuando el estado se aplica exactamente en su tick. Se conservan los FAIL de ventanas posteriores a la suelta no calificables. No se modifican verificadores para volverlos verdes.

Los criterios históricos que exigían `action_capacity` exactamente en la acción 257 o que el cierre fuese local cambiaron de contrato y no certifican este comportamiento nuevo. Se conservan originales para comparar; Claude debe agregar criterios nuevos, sin reescribir los anteriores. El primer intento del nuevo test de acciones consultó al actor/Jolt antes de inicializar el mundo; se corrigió la fixture añadiendo piso y espera de inicialización, sin modificar el motor. Otra corrida de regresión contó un Godot de una prueba simultánea como proceso abierto; se repitió aislada. Los intentos se conservan en tmp y no se presentan como aprobados.

El subgrupo final original de Claude 13 da **45 PASS / 0 FAIL / 1 INSUFICIENTE / 3 INFO**: el cliente atrasado aplica 18 estados antes del final, frente a cero en la entrega 13. La insuficiencia restante corresponde a replay positivo de ese modo, que aplica exactamente en el tick del checkpoint. La corrida anterior del mismo subgrupo conserva dos FAIL de ventanas sin calificar. La regresión aislada de Claude 12 da **60 PASS / 0 FAIL / 1 INFO**.

Corridas finales, veredictos íntegros y hashes: [resultados_codex_entrega_14.json](resultados_codex_entrega_14.json). No cambian Rust, binding, lockfile, DLL, producción ni instrumentos de Claude. No se repite N3. No se mide RAM pico, red adversarial, dos PC o rendimiento de notebook.

**Pendiente:** validación independiente de las correcciones; luego instalar el recorrido en el laboratorio con objetos reales, permisos/alcance, InvHands, inventario, catálogo, varias manos, presentación y ciclo de vida. También queda tratar la presentación de una suelta todavía no confirmada: las ventanas donde host y cliente ejecutaron acciones en ticks diferentes no se declaran convergentes. `model_approved=false`; `laboratory_migrated=false`.

## Encargo de Claude: entrega 14

1. Actualizar por fetch local y avance directo desde `implementacion`. `../entrega_14.json` identifica el checkpoint. Conservar instrumentos y trazas. Leer este informe, los cambios en los cuatro módulos y los README. Fijar criterios nuevos antes de correr.
2. Probar cierre remoto por RPC, cierre desde ambos lados, caducidad de envío, aviso omitido y ausencia real durante el plazo. Verificar `closed` una vez, buffers del canal y ambos slots del puente vacíos, predicción detenida, nodos no reutilizables. Cubrir control con peer/ámbito incorrecto, incluida conexión/contexto/UID/sesión anteriores. Diferenciar timeout inducido por reloj local de un plazo real.
3. Repetir cliente atrasado durante publicación continua; exigir aplicaciones **antes** del final, nunca ticks futuros y almacenamiento acotado a dos slots del puente. Cubrir pausa, sucesor ya aplicable, corrección del actor y falta de base.
4. Superar 256 acciones en el mismo vínculo, con y sin confirmaciones; verificar ventana, memoria, IDs crecientes/con saltos, duplicados conservados/conflictivos, IDs retirados, huecos del contador y no reutilización. Probar ACK retirado, incluidos el primero tardío y datos inválidos. No certificar transacciones del inventario con estos callbacks temporales.
5. Probar replay con acciones aún conservadas y suspensión mayor a la ventana: no perder una acción necesaria para el replay permitido ni repetir efectos. Mantener los casos anteriores de historia real, tiempo pasado y recuperación atómica.
6. Mantener separados los resultados de igualdad de replay calificada, ventanas de cobertura insuficiente, diferencias por inputs/acciones distintos y métricas visuales no medidas. Registrar los FAIL originales sin ajustar criterios a los resultados. Los tests antiguos de capacidad/cierre se conservan; agregar verificadores nuevos para el contrato cambiado.
7. Instrumentos en `prototypes/objetos_adaptador/validacion_claude/`, informe `docs/net/validacion_objetos/entrega_14.md`. No modificar implementación, producción, núcleo ni fixtures/runners de Codex. 8 s por proceso. No repetir N3 ni recompilar el núcleo sin cambios. No aprobar integración del laboratorio, inventario, dos PC, memoria pico o rendimiento.
