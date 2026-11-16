# Preparación del núcleo nativo, entrega 7

**Corrección del lanzador:** se encontró una copia del `.cmd` en Descargas sin su `.ps1` compañero. El enlace del chat descarga solo el archivo enlazado, por lo que la primera versión no podía encontrar el preparador desde allí. El `.cmd` ahora utiliza el preparador del proyecto cuando falta el archivo adyacente, conserva el código de salida y permite `-CheckOnly`. Se comprobó esa ruta desde una carpeta temporal que contiene únicamente el `.cmd`: terminó en 0 y seleccionó la implementación y caché correctas. Este chequeo no descarga bibliotecas ni se registra como descarga completa. Es necesario ejecutar la versión corregida; la copia anterior de Descargas conserva su contenido viejo.

2026-11-16. Continúa `682a386` (entrega 6). El usuario instaló las herramientas. **La compilación Rust/MSVC funciona; la descarga de dependencias está bloqueada en la red de esta sesión. El núcleo de objetos todavía no está implementado ni compilado.**

## Comprobaciones

- Rust `1.100.0`, Cargo `1.100.0`, toolchain `stable-x86_64-pc-windows-msvc`.
- Visual Studio 2022 Community, herramientas MSVC `14.44.35207`; Windows SDK `10.0.26100.0`.
- Compilación de una fuente Rust mínima como `cdylib`: código 0 y DLL de 118.272 bytes. Fuente, stdout/stderr y resultado en `implementacion/tmp/native_toolchain/compiler_probe/`. Es una prueba del compilador y enlazador, no de GDExtension ni de físicas.
- `cargo metadata --offline --no-deps` acepta el manifiesto del nuevo paquete.
- Análisis de PowerShell del preparador: 0 errores; `-CheckOnly` selecciona la copia de implementación y la caché correctas.

## Preparación creada

`native/objetos_core/` declara Rapier 0.36.0 con serialización y determinismo mejorado, godot-rust 0.5.4 para Godot 4.7 y el formato binario/checksum previsto. El archivo `src/lib.rs` es todavía un punto de partida vacío; no se presenta como un módulo funcional. Los builds y la caché quedan dentro de temporales, fuera de los recursos Godot.

Se prepararon:

- `tools/testing/descargar_dependencias_objetos.cmd`: entrada para que el usuario descargue las dependencias con doble clic.
- `tools/testing/prepare_object_native_dependencies.ps1`: ejecuta solo `cargo fetch`, con caché local al proyecto, progreso cada 5 segundos, límite total de 180 segundos y registro del código real. Si ya existe `Cargo.lock`, usa `--locked`. No instala herramientas ni escribe configuraciones globales.

El resultado `READY` solo se escribe si Cargo termina en código 0 y existe `Cargo.lock`. Ese archivo debe conservarse antes de compilar para fijar todas las versiones transitivas.

## Bloqueo confirmado

El primer `cargo fetch` falló al conectar con `index.crates.io:443` (error de conexión 7). Se comprobó también la rama real de fallo del preparador recién creado: conserva stdout/stderr y `result.json` con `FAILED`, código 101 y `native_core_compiled=false`, en `implementacion/tmp/native_toolchain/downloads/20261116_224631_cc431d/`. Terminó sin dejar Cargo abierto. No se declara la descarga completa ni se intenta eludir la restricción desde otro proceso de la sesión.

Hace falta que el usuario ejecute el `.cmd` desde Windows, fuera de esta sesión, para completar la descarga. Una vez disponible la caché y su lockfile, Codex podrá trabajar sin esa conexión para compilar y construir los ensayos del [contrato nativo](../contrato_nucleo_fisico_objetos.md).

No hubo cambios del runtime, pruebas de Claude ni configuración del juego. No se ejecutaron nuevos ensayos físicos. `model_approved=false`, `laboratory_migrated=false`, `native_core_implemented=false`. No se pide a Claude repetir las pruebas anteriores mientras falte el componente nuevo.
