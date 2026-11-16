# Revisión de la entrega 2 y entrega 3

2026-11-16. Se revisaron el informe y criterios de Claude en `docs/net/validacion_objetos/entrega_2.md` y `criterios_entrega_2.md`, los cambios de sus instrumentos y las trazas. Su commit `8a81339` se incorporó por avance directo a `implementacion`. La revisión de Codex no modifica los tests independientes ni sus tolerancias.

## Resultado y alcance

Claude confirmó las correcciones de la entrega 2 y detectó dos errores nuevos y verificables. La entrega 3 los corrige en la implementación. **La migración sigue bloqueada por reconciliación, acciones realmente tardías, contactos dinámicos y presentación.** El laboratorio no se modificó y no se instaló otro motor físico.

| Hallazgo | Corrección |
| --- | --- |
| N1: `stale` sale sin `action` y el invitado accede a esa clave | Toda respuesta a una orden válida lleva `uid` y `action`, también pendiente, rechazo, resultado cacheado y respuesta antigua. El receptor valida la forma antes de acceder a campos; una respuesta malformada se descarta y registra |
| N2: se pierden movimientos mientras el agarre está programado pero aún no concedido | Una bandeja independiente guarda entradas identificadas por peer, objeto, aparición, sesión y tick. Se pueden recibir antes del GRAB, pero solo la autoridad que concede esa sesión puede consumirlas |
| Fragilidad de una única muestra de mano por datagrama | Nuevo formato binario de hasta seis ticks redundantes y cola de seis envíos después de soltar. Se mantiene el tick original de cada registro; los duplicados no se convierten en movimientos nuevos |
| Acción propia del host con un tick extra de demora | La recepción desde la bandeja de red y la ejecución local indican explícitamente el límite físico correspondiente; la acción local no agrega otro tick |
| Instrumentación incompleta | El controlador local también identifica el tick usado; la traza registra objetivo, respaldo utilizado y estado recibido en el ACK |

El objetivo del GRAB sirve como respaldo inicial. No se da su tick por consumido: si llega una entrada más reciente para ese mismo paso puede reemplazarlo antes de Jolt. La bandeja no es un permiso de agarre ni una modificación del inventario.

## Verificación enfocada de Codex

Motor 4.7.2 instalado, tiempo real, dos procesos por caso, límite externo de 20 s, semilla de aplicación 12345. Se usaron los instrumentos originales de Claude. Evidencia en `implementacion/tmp/revision_entrega_3/`, incluyendo corridas fallidas. El resumen versionado es `resultados_codex_entrega_3.json`.

| Comprobación | Resultado |
| --- | --- |
| `contract_test.gd` | 74 pasan, 0 fallan |
| `contract_test_e2.gd` | 13 pasan, 0 fallan |
| `grab_move_left / clean` | E0, H1/H2 y los demás criterios ejecutados pasan. Divergencia del agarre: 0 m/0° desde el primer tick, frente a los 14,2 mm de N2 |
| `dup_throw / clean` | E0 y D1–D3 pasan: un impulso, ninguna reejecución y `stale` asociado a la acción correcta. ACK con velocidad posterior al impulso: error 0 m/s |
| `grab_rejected / clean` | E0, G1 y G2 pasan; error de réplica de 0,188 mm. El agarre del jugador del host se pide en 25 y se aplica en 26, con `late=false`, en lugar del tick adicional observado por Claude |
| `grab_move_left / degraded` | **No aprueba el modelo.** Divergencia informativa de 4,836 mm durante el agarre; la salida llega un tick tarde y C4 mide 4,95 mm de ascenso aparente. El traspaso no salta. No se reinterpreta como aprobado por haber reducido el error |

La primera repetición de `grab_move_left / clean` quedó inválida por incompatibilidad de inspección: el driver leía `o.goals.size()` y la nueva implementación había retirado ese campo. Se preservó la corrida y se restituyó una vista de inspección de la bandeja canónica. No es otra cola de ejecución, no se modificó el driver ni se aceptó su resultado con errores. La repetición posterior no tiene errores y da H1 = 0 m.

El runner aún encuentra la restricción de `Get-CimInstance` en este entorno al terminar. Los procesos ya habían finalizado y `run.json` estaba escrito; se ejecutó el verificador original por separado. La excepción se conserva, al igual que el aviso de certificados raíz. No se afirma que el runner haya terminado sin esa salvedad.

## Contrato nuevo de entradas de mano

`runtime/hand_input.gd` codifica datos, y `runtime/hand_timeline.gd` conserva/elige entradas. El RPC `_hand_inputs(packet)` sustituye al antiguo `_goal(...)`. Ambas copias deben actualizarse juntas: no se promete compatibilidad de RPC con la entrega 2. El formato de snapshots sigue siendo el mismo de 90 bytes.

El paquete de mano usa little-endian. Cabecera de 4 bytes: magia `0x4849`, versión `1`, cantidad entre `1` y `6`. Cada registro ocupa 44 bytes:

| Offset dentro del registro | Tipo | Dato |
| --- | --- | --- |
| 0 | u32 | Objeto |
| 4 | u32 | Aparición (`epoch`) |
| 8 | u32 | Sesión de agarre |
| 12 | u32 | Tick del input |
| 16 | 3 × float32 | Posición del objetivo |
| 28 | 4 × float32 | Cuaternión x/y/z/w |

Payload máximo: **268 bytes**, por debajo del presupuesto de 1200 bytes de aplicación. No incluye cabeceras de ENet/IP. Se rechazan tamaño inconsistente, versión/magia incorrectas, IDs fuera de rango, datos no finitos, giro inválido y paquetes con registros inválidos. El emisor conserva primero el tick más reciente y repite los anteriores; el receptor no depende del orden de esos registros.

La bandeja:

- Conserva una ventana de 120 ticks pasados y 60 futuros; caduca entradas antiguas.
- Admite como máximo cuatro sesiones por peer y dos peers remotos en esta fixture. Las sesiones retiradas también tienen límite y caducidad.
- No cambia el dueño por recibir datos. El consumidor debe nombrar exactamente el dueño, objeto, aparición y sesión concedidos por la autoridad.
- Usa la entrada disponible más reciente que no sea futura ni ya consumida. Si falta la del paso actual, conserva el objetivo previo y registra `fallback`; no inventa un input ni repite Jolt.
- Retira la sesión al soltar y descarta sus paquetes retrasados; limpia las entradas al desconectar.
- Retira también las entradas de agarres rechazados que no estén vinculadas a una concesión o reserva vigente. Una repetición rechazada no retira la sesión activa de otro agarre. El consumidor excluye ticks anteriores al inicio solicitado de la sesión.
- No sobrescribe un tick existente con otro objetivo contradictorio. Su respuesta de diagnóstico distingue duplicado, conflicto, ventana, retiro y capacidad.
- Expone `o.goals` como vista de lectura para el driver anterior. La selección física se realiza únicamente en la bandeja nueva.

`controller` declara `input_tick` en ambos roles, objetivo y origen del respaldo. `result` incluye el estado inicial de una confirmación aceptada. Las respuestas malformadas se registran como `discarded_result`; no deben provocar excepciones ni efectos de juego.

## Lo que continúa abierto

No se reintrodujo la corrección histórica retirada. La redundancia y la bandeja resuelven pérdida evitable y orden de recepción; no dan rollback, no corrigen un evento ya tardío ni convierten un proxy cinemático en un cuerpo dinámico. F3/F4/F5/F8/F9 siguen bloqueados según los informes anteriores. Las verificaciones existentes no sustituyen una prueba independiente del nuevo formato y sus límites.

Se investigó una alternativa al desarrollo de una extensión propia: [Godot Rapier Physics](https://github.com/appsinacup/godot-rapier-physics). Su documentación describe [pasos manuales](https://godot.rapier.rs/docs/documentation/determinism/) y [guardado/restauración de espacios](https://godot.rapier.rs/docs/documentation/serialization/). **No se ha probado aquí ese backend ni se lo considera una solución aprobada.** La documentación también exige conservar la topología de nodos al restaurar: no resuelve por sí sola las altas/bajas del inventario.

Se identificó el paquete oficial `godot-rapier-3d-single.zip`, versión `v0.36.0`, de 63.038.621 bytes, mediante la API oficial de releases. La descarga directa está restringida en el entorno y el intento por navegador no confirmó la descarga dentro del límite. No se instaló ni se ejecutó un binario externo. No se seguirá insistiendo con consultas largas de navegador para obtenerlo.

Antes de adoptar Rapier habría que demostrar, en un proyecto aislado, restauración y repetición con dos cuerpos dinámicos en contacto, comandos tardíos, costo y sincronización de nodos. También verificar la compatibilidad de las APIs de la versión exacta. Cambiar el backend 3D del proyecto puede afectar al personaje y al parkour; no se asumirá que se puede cambiar solo el resolvedor de objetos sin demostrar ese aislamiento. Mantener Jolt con una integración de stepping sigue siendo otra alternativa a evaluar. No se elige ni instala ninguna de forma silenciosa.

## Encargo acotado para Claude

La entrega 3 está en `objetos/implementacion`. La copia de validación sigue en `8a81339` con sus resultados intactos. Para actualizar, verificar el estado y realizar desde `validacion_claude` el fetch local y avance directo de la rama `..\implementacion`, como en la entrega anterior. `..\entrega_3.json` registra el hash publicado. No reemplazar carpetas ni borrar trazas.

No repetir todas las corridas anteriores. Prioridad:

1. Confirmar N1 con `dup_throw`: acción/objeto correctos tras expulsión de caché, un impulso y ningún error de script. Probar además el receptor con respuestas malformadas sin identificadores o sin estado válido.
2. Confirmar N2 con `grab_move_left / clean`, desde el primer tick. Comparar los objetivos/ticks de ambos controladores, incluyendo la primera entrada. Evitar `grab_move` hacia la caja 2 para esta comprobación de movimiento libre.
3. Construir pruebas independientes de `hand_input.gd`: bytes armados manualmente, cantidades 0/1/6/7, tamaños, IDs, NaN/infinito/cuaterniones y máximo de 268 bytes.
4. Probar `hand_timeline.gd`: entrada antes del GRAB y antes de su concesión, orden inverso, duplicado, conflicto del mismo tick, sesión/peer/epoch ajenos, expiración, capacidad, retiro y desconexión. Verificar que recibir datos nunca permita consumir una sesión no autorizada en el adaptador.
5. Comprobar movimiento con pérdida y registrar inputs que llegan tarde, sin convertir ese fallo en tolerancia mayor. Verificar el tick de las acciones locales del host y que no regresen F6/F7.

Las pruebas nuevas deben fijar criterios antes de ejecutarse y mantener el límite externo de 20 s. El rollback físico, los contactos dinámicos y la instalación de otro motor no forman parte de este encargo de validación. Esos cambios corresponden a la construcción y a su propia puerta de viabilidad.

La revisión final agregó validación defensiva del encoder, límite inferior del tick de sesión y retiro de entradas rechazadas. Las corridas enfocadas anteriores verifican N1/N2; la verificación independiente del hash final, incluidos esos límites nuevos, está pendiente.
