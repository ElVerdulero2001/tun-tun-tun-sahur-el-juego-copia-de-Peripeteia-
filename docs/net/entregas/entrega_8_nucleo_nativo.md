# Entrega 8: primer núcleo nativo de objetos

2026-11-16 (hora argentina; las carpetas de evidencia usan UTC del 17). Continúa `48b1a1b`. **Construido, compilado y probado por Codex. Pendiente de verificación independiente; no se migró el laboratorio.**

## Resultado concreto

Existe una GDExtension propia que utiliza el solver Rapier 0.36.0 y mantiene un mundo por instancia. Guarda y restaura cuerpos, contactos, reposo, controlador y asociación con identidades públicas. No utiliza StateManager3D ni reescribe IDs o espacios del servidor global de Godot. Jolt permanece seleccionado y activo.

Pasaron nueve pruebas Rust y siete procesos Godot de construcción. La documentación de API y reproducción está en [native/objetos_core/README.md](../../../native/objetos_core/README.md). El resumen versionado es [resultados_codex_entrega_8.json](resultados_codex_entrega_8.json), con hashes de fuentes, lockfile, motor y DLL. Ningún resultado de esta entrega equivale a una aceptación independiente del modelo completo.

## Qué se implementó

- Identidades públicas UID/aparición separadas de handles Rapier, RIDs e InstanceIDs de Godot. Cambiar el orden de creación o tener otro mundo con los mismos UID no mezcla sus cuerpos. Retirar un UID exige una aparición posterior para reutilizarlo.
- Mundos nativos propios con paso manual único. Las cajas tienen origen y centro de masa centrales; materiales y controlador de la fixture tienen parámetros explícitos.
- Agarre por punto, objetivo de posición/giro, límites de velocidad/aceleración, suelta e impulso central. Las acciones de dominio y permisos continúan siendo responsabilidad de la autoridad del juego.
- Snapshots del PhysicsWorld completo y del controlador, con versión/modelo, contexto, manifiesto, longitud y checksum. Se construye y valida el candidato antes de reemplazar el mundo activo. No se importa el mapa global de IDs de otro proceso.
- Caché limitada a 120 checkpoints y 16 MiB. Restaurar uno local retira su futuro; importar estado autorizado invalida toda la caché de la predicción anterior. Un checkpoint vencido se rechaza.
- Raycast nativo de las cajas propias, creación/liberación solo antes de sellar topología, parámetros finitos y límites de capacidad. No se añade física de caída manual ni transporte de errores históricos.
- Herramientas de compilación offline y ejecución con plazos externos, logs, códigos reales de salida y copias de ejecución dentro de tmp. Las fuentes llevan una plantilla `.gdextension.in`; la extensión activa y la DLL se crean solo en la copia temporal.

## Verificación final

| Caso | Resultado |
| --- | --- |
| Rust: 9 pruebas de contrato | 9 pasan, 0 fallan; ejecutable limitado a 8 s |
| Contacto dinámico activo | Checkpoint en tick 17, 6.179 bytes; restauración y repetición con posiciones, cuaterniones, velocidades, reposo y contactos exactos por bits |
| Reposo y despertar | Incluidos en una referencia de 360 pasos; el segundo impulso despierta B en el paso relativo 240 |
| Otro mundo vivo | Restaurar A no modifica B; crear Y, consultar X, liberar Y e impulsar X conservan identidad y movimiento; 120 pasos exactos contra un control |
| Orden de creación inverso | Cargar el checkpoint en B/A, en vez de A/B, conserva identidades y reproduce la referencia exacta |
| Rechazos | Manifiesto, contexto, checksum y longitud incompatibles no modifican el mundo. Se rechazan entradas inválidas, masas que desbordan/subdesbordan la conversión, operaciones sobre identidad retirada y topología sellada |
| Godot local | PASSED; Jolt sigue seleccionado, un cuerpo Jolt conserva su estado durante las operaciones nativas y otro mundo propio conserva su trayectoria |
| Archivo entre procesos | PASSED; restaura en un proceso con orden distinto y repite exactamente la referencia |
| ENet entre procesos | PASSED; contenido íntegro y mismo resultado por una conexión real en localhost |
| Suelta tardía por ENet | PASSED: predicha en 46, enviada en 74, aplicada por el host en 73 en la corrida final; el invitado restaura 73 y repite 3 pasos hasta su presente 76 |
| Comparación final de esa suelta | Estado del tick físico 140 exactamente igual en host e invitado, incluido contacto/reposo; mismo SHA-256 |
| Duplicado de la acción | Pedido repetido en 95, una sola suelta física en host y una predicción local; confirmación repetida ignorada |

Los ticks de recepción/aplicación dependen de la planificación real de ambos procesos: una corrida anterior aplicó en 71 y repitió cuatro pasos. El criterio es comparar el mismo instante y usar el tick realmente confirmado, no exigir un número de llegada fijo. No se usó fixed-fps.

El caso tardío tiene objetivos de mano preacordados y cuatro pasos iniciales de ventaja; demora explícitamente el envío de la suelta. Puede esperar hasta que el predictor esté dos pasos por delante del checkpoint recibido para asegurar que el ensayo ejercite replay. **Es instrumentación de construcción, no una regla de reloj ni una solución de latencia para producción.** Tampoco conecta todavía el input real del actor ni el protocolo previo de objetos.

El artefacto de archivo/ENet ocupa 371.712 bytes porque contiene el checkpoint y toda la historia de referencia del verificador. No es el tamaño propuesto de un paquete de producción. El checkpoint nativo medido es el de 6.179 bytes indicado arriba. El perfil usado es dev optimizado a nivel 1, no release ni un presupuesto aprobado para el catálogo.

## Evidencia y reproducción

- Rust final: `implementacion/tmp/native_build/20261117_001028_CoreTests_8d4e4e/`.
- DLL final: `implementacion/tmp/native_build/20261117_001417_Extension_ff7425/`; binario en `implementacion/tmp/native_target/debug/sahur_object_world.dll`.
- Godot final: `implementacion/tmp/native_probe/20261117_001419_ba2bc3/`. Los siete procesos terminaron en código 0, sin vencer ni errores de script/carga; el mayor tardó 2,665 s. Se conserva el aviso conocido de certificados raíz de Windows.

Compilar con `build_object_native.ps1 -Stage CoreTests` y luego `-Stage Extension`; ejecutar `run_object_native_probe.ps1 -Stages all`. Dependencias bloqueadas por Cargo.lock y modo offline. El builder admite una caché compartida mediante `-CargoCachePath`, con targets y resultados propios para cada copia. Cada compilación tiene límite de 180 s y cada prueba/proceso Godot de 8 s.

## Fallos de construcción corregidos y conservados

Los primeros checks detectaron una llamada a una API inexistente, una conversión de Array incorrecta en godot-rust y una preparación que ejecutaba collision-only antes del primer paso dinámico. En esa preparación los cuerpos no caían, por lo que cuatro casos físicos fallaron. Se eliminó esa secuencia; las consultas usan el raycast nativo de la forma sin consumir los flags previos al paso dinámico. La fixture continúa exigiendo contacto dinámico con velocidad y luego reposo/despertar; no se relajó su criterio. Los logs fallidos se conservaron.

También se guardó un fallo de lanzamiento por USERPROFILE ausente y se añadió selección explícita de ToolchainBin. Durante las verificaciones cambió la configuración del launcher de esta sesión a rutas POSIX inválidas en Windows: los pasos finales utilizaron acceso JavaScript al mismo repositorio y procesos locales acotados. Se conservaron los mismos ejecutables, límites y comandos de pruebas; no se usó otro motor ni se modificaron las pruebas de Claude.

## Qué falta antes de integrar

No se comprobaron el catálogo real, formas convexas/custom, COM desplazados, geometría preparada del nivel, apoyos móviles, inventario ni cambios de topología. Tampoco SimClock, cámara lenta/pausa, handoff/presentación ni dos notebooks. Los snapshots nativos son datos confiables de la fixture: checksum y validación de manifiesto no constituyen autenticación ni una defensa completa ante datos nativos hostiles. La entrada de red de producción necesita su frontera de validación antes de usar esta API.

El siguiente paso es la revisión independiente del núcleo y luego un adaptador para el prototipo real. **model_approved=false; laboratory_migrated=false.** Las pruebas anteriores de Claude y el runtime Jolt del prototipo se conservan sin cambios.

## Encargo de Claude

1. Actualizar su copia por fetch local y avance directo desde `implementacion`, conservando sus pruebas y trazas. `../entrega_8.json` identifica el commit y los hashes; comparar fuentes con SHA-256 normalizado a LF si el checkout cambia CRLF.
2. Leer el contrato, API y este informe. Construir criterios propios antes de ejecutar. Puede agregar instrumentos en `prototypes/objetos_nativo/validacion_claude/`, `native/objetos_core/tests/claude_*.rs` e informes en `docs/net/validacion_objetos/`. No modificar núcleo, binding, runners, fixtures de Codex ni tolerancias para obtener aprobación.
3. En su copia, compilar con `-CargoCachePath '..\implementacion\tmp\native_toolchain\cargo'` en los dos comandos del builder; usa los paquetes descargados, compila sus propias fuentes y deja resultados separados. Si falta una variable de perfil, pasar `-ToolchainBin 'C:\Users\ElCaido97\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin'`.
4. Comprobar independientemente contacto activo, reposo/despertar, identidad con orden distinto, aislamiento entre instancias, rayos y creación/liberación ajenos, rechazos atómicos, caducidad/límites y descartes de caché al importar autoridad.
5. Validar el caso de ENet tardío comparando ticks iguales, un solo impulso físico, tratamiento del duplicado y continuidad de los vecinos dinámicos. Distinguir este driver preacordado del input, reloj y presentación del juego. Señalar datos faltantes antes de inventar instrumentación sobre el runtime.
6. Procesos de prueba limitados externamente a 8 s. No repetir las baterías de Jolt ni declarar migración o rendimiento aprobados. Los fallos antiguos de StateManager3D siguen siendo antecedentes válidos; este núcleo no los vuelve verdes modificando sus pruebas.
