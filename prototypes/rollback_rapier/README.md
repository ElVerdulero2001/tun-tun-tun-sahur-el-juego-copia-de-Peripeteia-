# Ensayo aislado de capacidad de rollback

**Preparado; todavía no ejecutado con Rapier. Falta el paquete binario.** Este ensayo no forma parte del juego ni del prototipo de red en Jolt.

Versión fijada: Godot Rapier **v0.36.0**, Windows x64, Godot 4.7. Paquete oficial:

https://github.com/appsinacup/godot-rapier-physics/releases/download/v0.36.0/godot-rapier-3d-single.zip

SHA-256: `9700717c8ef83acd219e62edaeb3af503556273bc5afa2be4e363ebc8f243c7a`.

`tools/testing/prepare_rapier_probe.ps1` recibe `-ArchivePath` y `-EnginePath`. Por defecto busca el ZIP sin extraer en `C:\Users\ElCaido97\Downloads\godot-rapier-3d-single.zip` y Godot 4.7.2 en el escritorio. Verifica el hash, crea una carpeta nueva en `tmp/`, copia la fixture y extrae allí únicamente el addon 3D y el binario Windows x64 necesario. No descarga archivos ni escribe en los addons o configuración del juego. El import tiene límite de 12 s y el ensayo, 8 s; conserva los logs y termina sus procesos si vencen.

El ensayo guarda un checkpoint de un piso y dos cuerpos dinámicos, verifica exportación binaria, avanza 90 pasos con un impulso y contacto entre cuerpos, restaura y compara toda la historia repetida. Después simula una rama sin el comando y comprueba que restaurar y repetir con él recupera la trayectoria de referencia. También mide sincronización entre estado nativo y nodos, y demuestra un registro de efectos que no se duplica durante replay.

Un resultado positivo solo demostraría capacidad en **un proceso, tres cuerpos y topología fija**. No valida red, inventario, altas/bajas, crecimiento de islas, rendimiento del catálogo, personajes, parkour ni cámara lenta. El registro de efectos es una fixture, no una validación del inventario real.

Se comprobó la sintaxis de GDScript y PowerShell. Un control negativo con Jolt devuelve `BLOCKED / backend_not_prepared`, código 2. No hay resultado positivo: el binario no está disponible y no se ejecutó otro backend.

Se contrastaron las API con la versión exacta, no solo con la documentación actual:

- [state_manager.rs](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/src/nodes/state_manager.rs): registra `StateManager3D`, sin el prefijo Rapier usado en documentación más nueva.
- [rapier_physics_server_extra.rs](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/src/servers/rapier_physics_server_extra.rs): `space_step` y `space_flush_queries` estáticos.
- [types.rs](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/src/types.rs): `RustBincode` como formato de texto, no un entero inferido.
- [configuración GDExtension](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/bin3d/addons/godot-rapier3d/godot-rapier3d.gdextension): compatibilidad y biblioteca Windows x64.
