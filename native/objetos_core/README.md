# Núcleo nativo de objetos: preparación

**Dependencias declaradas; módulo todavía sin implementar ni compilar.** Se conserva el [contrato](../../docs/net/contrato_nucleo_fisico_objetos.md). Este directorio prepara una GDExtension con mundos Rapier propios, sin registrar un `PhysicsServer3D` global.

La primera descarga requiere `tools/testing/descargar_dependencias_objetos.cmd`, ejecutado por el usuario fuera de la sesión de Codex porque su conexión a `crates.io` está bloqueada. Ese archivo llama a `prepare_object_native_dependencies.ps1`; selecciona la copia de implementación si existe, usa una caché dentro de sus temporales y ejecuta únicamente `cargo fetch`. No instala herramientas ni cambia el proyecto Godot.

El lanzador corregido también funciona si el enlace del chat lo guardó solo en Descargas: en ausencia de un preparador adyacente, busca el del proyecto en su ruta conocida. Las copias descargadas de la primera versión deben reemplazarse por la versión corregida, o se puede ejecutar directamente el archivo dentro de `tools/testing`.

Dependencias principales: Rapier 0.36.0 con serialización y determinismo mejorado, godot-rust 0.5.4 para Godot 4.7, bincode 1.3.3 y SHA-256. `Cargo.lock` se genera en esa primera descarga y debe conservarse en la entrega que construya el módulo. El compilador Rust/MSVC ya generó una DLL de prueba correctamente; esa DLL solo comprueba las herramientas, no las físicas.

Los resultados de descarga quedan en `tmp/native_toolchain/downloads/`. Cada ejecución tiene un límite de 180 segundos y conserva sus logs y resultado. Un error no se registra como dependencias listas. El estado `READY` solo significa descarga completa, no compilación, carga en Godot ni aceptación de red.
