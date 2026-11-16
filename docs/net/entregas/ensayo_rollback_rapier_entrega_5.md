# Entrega 5: capacidad de restauración física con Rapier

2026-11-16. Continúa la entrega 4 (`3fadd23`). El usuario descargó el paquete oficial fijado. **Se demostró una capacidad de restauración y repetición; todavía no se aprobó un modelo de red ni se migró el laboratorio.** Codex construyó y ejecutó estos ensayos; la verificación independiente de Claude sigue pendiente.

## Qué se comprobó

Godot 4.7.2 oficial, Rapier3D v0.36.0, Windows x64. El SHA-256 del ZIP coincide con `9700717c8ef83acd219e62edaeb3af503556273bc5afa2be4e363ebc8f243c7a` (63.038.621 bytes).

| Caso | Resultado |
| --- | --- |
| Checkpoint local, restauración y repetición de 90 pasos | PASSED: diferencias máximas de posición, bases y velocidades iguales a cero; estados de reposo iguales |
| Rama sin impulso y corrección por restauración/replay | PASSED: la rama incorrecta difiere unos 4,57 cm; la repetición recupera la referencia con error cero |
| Contactos entre los dos cuerpos dinámicos | Observados; la prueba exige que existan |
| Estado nativo y pose de los nodos | Error máximo de posición cero en las ramas comprobadas |
| Exportación binaria a otro proceso | PASSED: snapshot de 10.217 bytes y misma trayectoria de 90 pasos |
| Identidad distinta del proceso importador | PASSED: RIDs de origen 24/26, destino 38/40; también difieren InstanceIDs. Siete cuerpos con formas fueron creados y liberados antes de construir la fixture importadora |
| Registro de efectos de la fixture | Un efecto externo; los impulsos físicos necesarios sí se repiten en cada replay |

El criterio EPS=0,00001 se conservó; los errores observados fueron cero. La prueba entre procesos comparte la misma máquina y nombres de nodos estables. No representa una conexión ENet ni una orden realmente recibida tarde por red: el archivo local confiable transporta el checkpoint y la historia de referencia. No se deserializan objetos ejecutables.

## Ejecución reproducible

Desde `implementacion`: `& .\tools\testing\prepare_rapier_probe.ps1`. Tres procesos independientes, cada uno limitado externamente a 8 segundos. El runner falla ante código de salida ausente/no cero, errores de carga/script o resultado incompatible; solo excluye el aviso conocido de certificados raíz de Windows.

Corrida final: `implementacion/tmp/rapier_probe_20261116_212405_a4af53/`. Conserva `dependency.json`, `probe_result.json`, `export_result.json`, `import_result.json`, stdout/stderr y el checkpoint local. El resumen versionado está en `resultados_codex_entrega_5.json`. No se committean DLL, cachés ni perfiles de Godot.

Se preservaron los intentos anteriores. El primero no pudo guardar ajustes en AppData; el preparador ahora pasa directorios de perfil locales a los hijos. Se corrigió además la captura del handle para conservar el código real de salida de procesos rápidos. Con ello apareció un acceso inválido nativo al cerrar el editor de importación Jolt con Rapier cargado (`-1073741819`): **no se contó como aprobado**. El proceso de juego Rapier sí cerró con código 0. La preparación final, sin editor ni recursos por importar, registra directamente la extensión fijada y completa los tres procesos sin ese fallo. No se ha validado abrir una escena Rapier en el editor ni convivir con Jolt en el mismo proceso.

## Qué implica para la reconstrucción

Es una base concreta para ensayar reconciliación mediante checkpoint y replay nativos. Evita inventar una corrección de posición basada en errores viejos después de contactos. Todavía no constituye un adaptador utilizable por el juego.

La lectura de [StateManager v0.36.0](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/src/nodes/state_manager.rs) muestra límites que deben comprobarse antes de elegir arquitectura:

- Guarda y restaura **todo un espacio**, además de escribir el contador global de IDs del servidor. Inferencia: no debe tratarse como una isla independiente sin verificar interferencias con otros cuerpos/espacios vivos y creación de objetos posterior al rollback.
- Resuelve objetos mediante rutas de nodos. La fixture fija esas rutas; falta el mapa estable objeto/aparición de un inventario real.
- El propio código declara pendiente la restauración de cuerpos añadidos/eliminados y cambios de formas. No se aprobó rollback sobre transacciones ni cambios de catálogo.
- Aún faltan checkpoints tomados durante contacto activo entre cuerpos, reposo/despertar, controlador de mano real, reloj/cámara lenta, límites de historia y rendimiento. Tampoco se midió la transferencia de snapshots por red: 10 KB para tres cuerpos no es un presupuesto de producción aprobado.

Se mantiene `model_approved=false`, `laboratory_migrated=false`. La disponibilidad del binario quedó resuelta. No se instaló Rapier en los addons ni se cambió `project.godot` del juego. Las pruebas y los criterios anteriores de Claude se conservaron.

## Siguiente verificación independiente de Claude

Actualizar su copia mediante fetch local y avance directo desde `implementacion`; `../entrega_5.json` identifica el commit. Preservar sus pruebas y resultados. Leer también la revisión de la entrega 4: sus correcciones de N3/L19 siguen pendientes de aceptación independiente si todavía no fueron probadas.

Para esta capacidad, fijar criterios antes de ejecutar y construir instrumentos propios sin modificar `probe.gd` ni aflojar EPS:

1. Reproducir el ensayo entregado, conservando los tres códigos reales de salida y verificando el SHA del paquete.
2. Demostrar restauración desde un checkpoint tomado durante contacto dinámico activo; comprobar trayectorias y velocidades, además de reposo/despertar.
3. Verificar el intercambio entre procesos con distinta asignación interna y rutas estables. Distinguir archivo local, transporte real y diferencia entre máquinas.
4. Investigar de manera acotada el contador global y un segundo espacio con cuerpos vivos: preservar sus estados y comprobar creación posterior al rollback. Informar si bloquea un predictor aislado; no ocultarlo excluyendo esos cuerpos.

Cada proceso debe tener límite externo de 8 segundos. No repetir la matriz de Jolt ni aprobar integración, inventario o rendimiento por estos ensayos. Codex se encargará del adaptador y de corregir los defectos demostrados; Claude no modifica el runtime.
