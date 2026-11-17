# Núcleo nativo de objetos, primera implementación

**Núcleo nativo, adaptador local y API de autoridad/recuperación verificados independientemente en sus alcances. La entrega 12 agrega un registrador conectado al replay real de ClientPrediction, pendiente de revisión independiente; no cambia el código nativo ni integra el laboratorio.** [Revisión y evidencia vigente](../../docs/net/entregas/revision_codex_entrega_11.md). [Contrato y etapas restantes](../../docs/net/contrato_nucleo_fisico_objetos.md).

Cada instancia `SahurObjectWorld` posee su propio `PhysicsWorld` de Rapier 0.36.0, sus handles, identidades públicas y caché. No registra un PhysicsServer global ni usa StateManager3D, RIDs o InstanceIDs del proceso de origen. Jolt continúa activo en Godot. Se fija la resolución de dependencias con Cargo.lock; no se modifica ni reutiliza la DLL del addon godot-rapier.

## Compilar y ejecutar

Desde la copia de implementación, con la caché ya descargada:

```powershell
& .\tools\testing\build_object_native.ps1 -Stage CoreTests
& .\tools\testing\build_object_native.ps1 -Stage Extension
& .\tools\testing\run_object_native_probe.ps1 -Stages all
```

El builder admite `-ToolchainBin` y `-CargoCachePath`. En la copia de Claude, pasar `-CargoCachePath '..\implementacion\tmp\native_toolchain\cargo'`: comparte únicamente la caché de paquetes, genera sus propios binarios y no necesita descargar otra vez. Se compila con `--locked --offline`, dos tareas y perfil dev optimizado a nivel 1, sin símbolos de depuración. El resultado es `tmp/native_target/debug/sahur_object_world.dll`; no es un benchmark de release.

Cada compilación tiene límite externo de 180 s por defecto, con progreso; cada ejecutable Rust de pruebas y cada proceso Godot tienen límite de 8 s. El runner Godot copia el proyecto y DLL a un directorio nuevo dentro de tmp, registra allí la extensión y aísla AppData. No abre el editor ni instala la DLL en el juego. Usa `-Stages local`, `file`, `enet` o `late` para un caso acotado. Rechaza una DLL anterior a las fuentes y al lockfile.

## API de Godot

Crear mediante `ClassDB.instantiate("SahurObjectWorld")`; es un RefCounted, cuya referencia pertenece al controlador de la escena. Las operaciones devuelven bool o un valor vacío/-1 al rechazar; `get_last_error()` da el motivo. No se canoniza una pose recibida con escala, cizalla o valores no finitos.

| Operación | Contrato de esta versión |
| --- | --- |
| `add_box(uid, epoch, size, mass, initial)` | Caja centrada en el origen y COM central; masa 0 fija, masa positiva dinámica. Formas y material predeterminados de la fixture |
| `remove_body(uid, epoch)` | Solo antes de sellar; retirar una identidad exige una aparición mayor al reutilizar el UID |
| `seal_topology(context_revision)` | Fija miembros, formas y contexto; bloquea altas/bajas posteriores |
| `begin_hold`, `set_goal`, `release_body` | Controlador de punto de agarre, velocidad y giro con límites; la segunda suelta sin agarre se rechaza |
| `apply_impulse`, `step(dt)` | Impulso central y un único paso manual; dt finito en (0, 1/30] |
| `sample`, `samples` | Identidad, tick físico, pose, velocidades, reposo, agarre y contactos con identidades públicas |
| `cast_ray` | Raycast nativo sobre las cajas propias, incluso recién creadas; búsqueda lineal acotada por la capacidad |
| `snapshot_trusted`, `restore_trusted` | Snapshot completo del mundo, manifiesto y controlador; validación del candidato antes del reemplazo. Importar invalida toda la caché de la predicción anterior |
| `cache_checkpoint`, `restore_cached` | Caché local por tick; restaurar conserva el pasado y elimina el futuro de esa rama |

Límites: 128 cuerpos vivos, 512 UID retirados, 120 checkpoints y 16 MiB de caché. Payload de snapshot de hasta 1 MiB más 44 bytes de envoltorio; `get_build_info().max_snapshot_bytes` informa el límite de payload. Se verifican identidades, parámetros, contexto, asociación de handles y manifiesto de cajas. El checksum detecta alteraciones; **no autentica al emisor ni convierte el deserializador en un protocolo para datos hostiles**. Esta API se denomina trusted deliberadamente. Las fixtures usan datos generados por el propio ejecutable/host de ensayo.

## Estado y límites

La entrega 9 valida los enlaces de los grafos de contactos y la pose física real de los cuerpos fijos antes de importar. La vista de inspección depende del formato serde de Rapier 0.36.0 fijado por Cargo.lock; al actualizar el solver debe revisarse. No se borran ni regeneran contactos y no se convierte la API `trusted` en un decodificador para datos arbitrarios. Las pruebas originales de Claude pasan al ejecutarlas Codex: 135 comprobaciones Rust y 79 Godot. Claude confirmó esa corrección; la API del adaptador de la entrega 11 espera su revisión independiente.

La caché conserva **hasta** 120 checkpoints dentro de 16 MiB. En la fixture de 128 cuerpos apilados, cada snapshot mide 614.284 bytes y solo caben **27** checkpoints (unos 0,45 s a 60 ticks/s). El adaptador debe consultar los checkpoints realmente disponibles y recuperarse ante `checkpoint_expired`; no prometer dos segundos ni ampliar la memoria para ocultar el caso. El costo de inspección y replay requiere medición en la notebook.

Pasaron nueve pruebas Rust y siete procesos Godot de construcción, incluidos contacto activo, reposo/despertar, orden de creación distinto, mundo ajeno vivo, importación por archivo/ENet y reconciliación de una suelta tardía comparada en el mismo tick. Son ensayos de Codex, no una aceptación independiente.

El caso de red usa objetivos de mano preacordados, cuatro ticks iniciales de ventaja y un envío deliberadamente demorado. No sustituye al adaptador de input/actor ni a SimClock. La comparación final es exacta en el tick 140. Todavía faltan dos PC, geometría y COM del catálogo, movimiento del escenario, inventario/topología variable, presentación, reloj y presupuesto de producción.
