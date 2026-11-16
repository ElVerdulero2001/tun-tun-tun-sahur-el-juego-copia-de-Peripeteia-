# Ensayo aislado de capacidad de rollback

**Revisión independiente 5: bloqueado para integrarlo como predictor aislado.** Se confirmaron las capacidades básicas y se reprodujeron corrupción de IDs e interferencias de restauración. [Revisión y próximo candidato](../../docs/net/entregas/revision_codex_entrega_5.md). Los resultados positivos siguientes conservan el alcance limitado de sus fixtures.

**Ejecutado con Rapier el 2026-11-16: restauración local e intercambio entre dos procesos aprobados en la fixture.** [Resultados y límites](../../docs/net/entregas/ensayo_rollback_rapier_entrega_5.md). Este ensayo no forma parte del juego ni del prototipo de red en Jolt.

Versión fijada: Godot Rapier **v0.36.0**, Windows x64, Godot 4.7. Paquete oficial:

https://github.com/appsinacup/godot-rapier-physics/releases/download/v0.36.0/godot-rapier-3d-single.zip

SHA-256: `9700717c8ef83acd219e62edaeb3af503556273bc5afa2be4e363ebc8f243c7a`.

`tools/testing/prepare_rapier_probe.ps1` recibe `-ArchivePath` y `-EnginePath`. Por defecto busca el ZIP sin extraer en `C:\Users\ElCaido97\Downloads\godot-rapier-3d-single.zip` y Godot 4.7.2 en el escritorio. Verifica el hash, crea una carpeta nueva en `tmp/`, copia la fixture y extrae allí únicamente el addon 3D y el binario Windows x64 necesario. No descarga archivos ni escribe en los addons o configuración del juego. Cada uno de sus tres procesos tiene límite externo de 8 s; conserva los logs y termina solo sus procesos si vencen.

La fixture no necesita recursos importados. El preparador registra la extensión en `.godot/extension_list.cfg` y arranca directamente con Rapier: la combinación de importación en editor Jolt y extensión Rapier produjo un cierre nativo anormal. También sitúa `APPDATA` y `LOCALAPPDATA` de los hijos dentro del ensayo; restaura el entorno del preparador tras lanzarlos y conserva los códigos de salida reales.

El ensayo guarda un checkpoint de un piso y dos cuerpos dinámicos, verifica exportación binaria, avanza 90 pasos con un impulso y contacto entre cuerpos, restaura y compara toda la historia repetida. Después simula una rama sin el comando y comprueba que restaurar y repetir con él recupera la trayectoria de referencia. También mide sincronización entre estado nativo y nodos, y demuestra un registro de efectos que no se duplica durante replay.

`exchange_probe.gd` y `exchange.tscn` agregan exportación a un archivo local confiable e importación desde un segundo proceso. Este altera previamente la historia de asignación de cuerpos y formas, manteniendo nombres y topología estables. Simula primero una trayectoria incorrecta, importa el checkpoint y compara los 90 pasos repetidos con la referencia del primero. Verifica el estado porque `import_state` no devuelve éxito. El archivo usa variantes sin objetos; no es un decodificador para datos de red.

Un resultado positivo solo demuestra capacidad en **tres cuerpos y topología fija**, localmente y entre dos procesos en la misma máquina. No valida transporte de red, inventario, altas/bajas, crecimiento de islas, rendimiento del catálogo, personajes, parkour ni cámara lenta. El registro de efectos es una fixture, no una validación del inventario real. El StateManager restaura un espacio completo y su contador global de IDs; todavía no se ha demostrado que pueda aislarse de otros espacios vivos sin interferencias.

Se preserva el control negativo histórico con Jolt: `BLOCKED / backend_not_prepared`, código 2. Los resultados nuevos con Rapier, incluidos los intentos de preparación fallidos, están documentados en la entrega 5. Las pruebas de Claude no se modificaron.

Se contrastaron las API con la versión exacta, no solo con la documentación actual:

- [state_manager.rs](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/src/nodes/state_manager.rs): registra `StateManager3D`, sin el prefijo Rapier usado en documentación más nueva.
- [rapier_physics_server_extra.rs](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/src/servers/rapier_physics_server_extra.rs): `space_step` y `space_flush_queries` estáticos.
- [types.rs](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/src/types.rs): `RustBincode` como formato de texto, no un entero inferido.
- [configuración GDExtension](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/bin3d/addons/godot-rapier3d/godot-rapier3d.gdextension): compatibilidad y biblioteca Windows x64.
