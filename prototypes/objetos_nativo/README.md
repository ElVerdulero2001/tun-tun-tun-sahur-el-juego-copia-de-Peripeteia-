# Fixture del núcleo nativo de objetos

Escenario de construcción de la [entrega 8](../../docs/net/entregas/entrega_8_nucleo_nativo.md), separado del laboratorio y del prototipo anterior. Usa la clase SahurObjectWorld; Godot conserva Jolt.

Ejecutar desde la raíz de la copia mediante `tools/testing/run_object_native_probe.ps1 -Stages all`, después de compilar con `build_object_native.ps1 -Stage Extension`. El runner crea la copia temporal, convierte la plantilla de GDExtension en una extensión activa y copia la DLL comprobada allí.

- `local`: contacto activo, replay, reposo/despertar, aislamiento y rechazo de manifiestos.
- `file`: exportación/importación entre procesos con órdenes de creación distintos.
- `enet`: transferencia real del artefacto confiable por localhost y repetición.
- `late`: suelta predicha en 46, enviada en 74 y duplicada en 95. El host confirma su tick real de aplicación; el invitado restaura y repite hasta su presente. Comparación exacta en tick 140.

El caso tardío usa un controlador y objetivos preacordados, no el input/actor ni el reloj del juego. La ventaja inicial de cuatro pasos y la espera mínima de dos pasos para ejercitar replay son condiciones del ensayo, no ajustes propuestos de producción.

Cada proceso tiene límite externo de 8 segundos. Los resultados y hashes del binario/lockfile quedan en runner.json y en los resultados de cada rol dentro de tmp/native_probe. El modelo completo y la integración siguen pendientes de validación independiente.
