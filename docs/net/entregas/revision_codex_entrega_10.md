# Revisión de Claude 10 y entrega 11: autoridad e historia corregida

2026-11-17. Base independiente `b49d3ec`, sobre `5fb0d1f`. Se incorporaron criterios, informe y los instrumentos de Claude por avance directo a `implementacion`. Su copia y sus verificadores se conservan sin cambios.

## Dictamen y reproducción

Se acepta el adaptador local en el alcance validado por Claude: actor/motor/codec/reloj de producción, diario de entradas/ojos/dt, restauración anterior al agarre y lanzamiento, efectos únicos y límites. Claude verificó 517 frames en ocho modos y las regresiones de 135 comprobaciones Rust y 79 Godot. Los instrumentos propios usan fixed-fps; las fixtures de Codex siguen en tiempo real. Esto no aprueba red del adaptador, controles de jugadores, inventario, presentación, notebook ni rendimiento.

Se reproduce S1: el instrumento pide 24 ticks lentos cuando, en su comprobación del tick 32, han ocurrido 23. La traza completa guarda exactamente 24, del 10 al 33. No se modifica su prueba: S1 y el código 2 de su proceso se registran como el resultado conocido del instrumento, no como aprobaciones ni como un fallo físico corregido.

La diferencia observada por Claude en S3 es real dentro de la limitación documentada: repetir un diario cuyo dt ya quedó viejo reproduce la rama vieja. La entrega 11 añade una entrada que lo detecta e interfaces para invalidar y reemplazar esa historia.

## Construcción de la entrega 11

1. **Estado de autoridad identificado:** conexión, contexto, objeto/aparición, sesión de mano, firma de Tuning, revisión y tick. Una revisión nueva puede corregir el mismo tick; paquetes duplicados, viejos o de otro ámbito se rechazan antes de restaurar. La numeración externa no sustituye al manifiesto nativo ni autentica al emisor.
2. **Confirmación tardía definida:** la acción declara tick pedido y aplicado; el snapshot debe ser posterior a la aplicación. Se importa ese estado y se repite lo que viene después, sin insertar otra suelta ni otro impulso en el pasado.
3. **Invalidación histórica:** una corrección del actor o del tiempo retira los frames afectados y solicita recuperación. La entrada nueva de autoridad detecta dt guardados que no coincidan con los tramos actuales del reloj. La detección de cambios del actor requiere notificación del futuro integrador de `NetSync`.
4. **Recuperación utilizable:** se acepta un snapshot y un lote completo de frames corregidos hasta el presente del reloj, con token de generación. Una invalidación posterior invalida los lotes en vuelo. Los errores conservan el mundo y los metadatos aceptados; el éxito reemplaza mundo/diario y reactiva el input sin mover al actor/reloj ni repetir efectos.
5. **Validación antes de copiar o restaurar:** tipos, tamaños, continuidad, dt e identidad de input y acciones se comprueban antes del candidato. Permanecen las cotas de 24 pasos y 256 KiB serializados del diario. Los ojos corregidos son responsabilidad del productor de historia; no se fabrican a partir del actor presente.

API y contrato completo en [prototypes/objetos_adaptador/README.md](../../../prototypes/objetos_adaptador/README.md). La entrada histórica `reconcile_trusted(tick, bytes)` se conserva para las fixtures de la entrega 10 y **no es la ruta nueva de integración**. No se agregó RPC, formato binario de red ni código de transporte.

## Verificación de construcción

| Escenario nuevo | Resultado |
| --- | --- |
| `api_authority` | Estado distinto de la autoridad, repetición exacta; revisión nueva del mismo tick aceptada; duplicada ignorada |
| Suelta tardía en ese escenario | Predicha en 30, aplicada en referencia 34, confirmada mediante snapshot 34 en presente 37; igualdad exacta, dos efectos totales (agarre y suelta) |
| Confirmación anterior a aplicar | Se rechaza sin consumir revisión; después se acepta la válida |
| `api_scope` | Conexión, contexto, UID, aparición, sesión, firma, versión, revisión, campos extra, ACK desconocido y payload de tipo incorrecto rechazados sin crear el candidato ni cambiar el mundo |
| `api_time` | Un tramo pasado modifica dt de 25–32; se detecta el diario viejo, se rechaza el lote con dt viejo y se recupera con los ocho frames corregidos; igualdad exacta y reanudación |
| `api_recovery` | Invalidación del actor en 20; el actor avanza a 25 mientras el mundo queda en 20. Lotes incompletos o de generación anterior rechazados; recuperación de 10 pasos desde 15 y continuidad exacta |
| Siete modos anteriores de Codex | Pasan sin modificar producción ni reloj |
| Runner propio final | Importación y once escenarios en código 0, sin vencer 8 s ni errores de script/carga |
| Instrumentos originales de Claude 10 | Conservados; mismas comprobaciones funcionales, con S1 anulado por su conteo y su proceso en código 2 |

Evidencia propia final: `implementacion/tmp/clock_probe/20261117_141146_b22b02/`. La importación tardó 3,577 s; el modo más largo fue historia (3,122 s). Se conserva únicamente el aviso conocido de certificados raíz de Windows. Hay trazas por tick, resultados y hashes de copias.

Base reproducida: `implementacion/tmp/revision_entrega_10/baseline/adapter_20261117_105630/`. La primera lectura del analizador apuntó al árbol fuente ya modificado y por eso marcó diferencias de hashes; se conservó como `analysis_against_later_source.json`. La comparación de base se rehízo contra sus copias, contrastadas con el manifiesto de la entrega 10. No se relajaron criterios ni se repitió la física para borrar un fallo.

Regresión final de Claude: carpeta `implementacion/tmp/revision_entrega_10/final/`, indicada en [resultados_codex_entrega_11.json](resultados_codex_entrega_11.json). La salida cruda conserva los fallos del instrumento; se distinguen de fallos nuevos. El núcleo Rust, binding y lockfile no cambiaron; se reutiliza la DLL construida y verificada de la entrega 10. N3 no se ejecuta.

## Alcance pendiente

Estas interfaces todavía no reciben eventos reales de `NetSync` ni snapshots por ENet. La corrección de ojos del actor se inyecta en el driver sobre un piso libre; el adaptador recibe esos registros y no ejecuta el replay del actor. No hay adquisición automática de estados de recuperación, transacciones del inventario, múltiples manos activas, catálogo/topología variable, presentación ni pruebas en dos PC. El snapshot nativo sigue siendo solo para datos confiables; las etiquetas de ámbito no lo convierten en un deserializador hostil seguro.

Se recupera el mismo vínculo. Cambiar conexión, contexto, objeto o sesión exige preparar otro adaptador. Al suspender se cancelan las intenciones en cola; sus IDs quedan reservados para impedir que reaparezcan por un duplicado. La futura autoridad debe resolver esos pedidos, no asumir que un duplicado significa que se ejecutaron físicamente.

**`model_approved=false`; `laboratory_migrated=false`.** El próximo paso, tras verificar esta API, es el transporte acotado de entradas/confirmaciones/checkpoints y los puntos de conexión con el historial corregido del actor. No se anuncia una migración funcional por aprobar estas fixtures.

## Encargo de Claude: entrega 11

1. Actualizar por fetch local y avance directo desde `implementacion`, conservando pruebas y trazas. `../entrega_11.json` identifica el checkpoint. No hace falta otra descarga ni hay cambios nativos; puede compilar su propia DLL con la caché compartida como antes.
2. Leer el contrato nuevo del README y fijar criterios propios. Instrumentos en `prototypes/objetos_adaptador/validacion_claude/`. No modificar adaptador, producción, núcleo, runners/fixtures de Codex ni tolerancias.
3. Verificar ámbito y revisión, incluido mismo tick con revisión nueva, duplicados, estados viejos, etiquetas incompatibles y confirmaciones cuyo snapshot no contenga todavía la acción. Distinguir esas etiquetas de autenticación de red, que no existe aún.
4. Comprobar la política de suelta tardía con estado posterior a aplicarla y sin doble impulso/efecto. Comparar el mismo tick, con referencia y controles propios.
5. Ejercitar cambios históricos de dt y ojos, notificaciones repetidas mientras está detenido, rechazo de lotes en vuelo, continuidad/tipos/límites del lote y atomicidad de fallos. Confirmar que recupera la captura después de varios ticks suspendido sin avanzar el actor/reloj ni usar historia vieja implícita. El proveedor de ojos corregidos sigue siendo un instrumento, no `NetSync`.
6. Reproducir las regresiones anteriores sin modificar S1 para volverla verde: informar su error conocido aparte y detectar regresiones nuevas. No repetir N3 ni aprobar formato hostil, red, inventario, presentación, notebook o rendimiento.
7. Procesos limitados externamente a 8 s. Informe en `docs/net/validacion_objetos/entrega_11.md`.
