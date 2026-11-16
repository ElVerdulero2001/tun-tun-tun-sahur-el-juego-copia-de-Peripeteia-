# Preparar la compilación nativa de objetos

El siguiente candidato necesita compilar una GDExtension pequeña en Rust que encapsule mundos de objetos. [Contrato y límites](contrato_nucleo_fisico_objetos.md). El ZIP de Rapier descargado permite probar la integración publicada; no incluye un compilador para modificarla o construir esta extensión.

La comprobación del 2026-11-16 no encontró `cargo` ni `rustc` en PATH ni en `%USERPROFILE%/.cargo/bin`, ni el localizador habitual de Visual Studio. Todavía no se compiló un núcleo propio.

Para preparar Windows x64:

1. Instalar [Rust mediante su instalador oficial](https://rust-lang.org/tools/install/), con la opción predeterminada MSVC x64. Para mantener la base de herramientas compatible con las dependencias examinadas, se usará Rust 1.94 o posterior.
2. Si lo solicita, instalar **Microsoft C++ Build Tools**. Seleccionar las herramientas MSVC x64/x86 y un Windows SDK dentro de la carga «Desarrollo para el escritorio con C++». [Instrucciones oficiales de Rust para Windows](https://rust-lang.github.io/rustup/installation/windows-msvc.html). El editor de código y Visual Studio completo no son necesarios.
3. Al terminar, avisar a Codex. Codex comprueba las herramientas, prepara la extensión y se encarga de compilarla y probarla. El usuario no necesita editar Rust ni ejecutar los ensayos a mano.

Estas instalaciones escriben fuera de la carpeta del repositorio y pueden requerir permisos de administrador. Los permisos actuales de esta sesión permiten escribir en el proyecto y temporales; no permiten instalar herramientas en carpetas del sistema. No se intentó una instalación global ni se solicitó eludir esa restricción.

El juego conserva su configuración actual. Instalar las herramientas no aprueba el candidato ni cambia automáticamente su motor físico.
