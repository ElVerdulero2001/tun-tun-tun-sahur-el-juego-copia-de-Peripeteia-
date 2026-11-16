# Revisión de la entrega 3 y entrega 4

2026-11-16. Se revisaron el informe y criterios de Claude en `docs/net/validacion_objetos/entrega_3.md`, sus instrumentos y las trazas. Su commit `ed8968c` se incorporó por avance directo a `implementacion`, sin modificar las pruebas. La entrega anterior era `d347101`.

## Resultado

Claude confirmó N1/N2 y encontró N3: la rotación acumulaba error de float32 hasta dejar de ser codificable, cortando la mano sin diagnóstico. También encontró L19: un duplicado ya consumido se informaba como entrada nueva, aunque no se volvía a usar físicamente. Esta entrega corrige ambos. **El modelo físico general sigue sin aprobar y no se migró el laboratorio.**

## Implementación

- `runtime/hand_rotation.gd` conserva un cuaternión unitario y lo normaliza después de cada actualización. El mouse usa `rotate_goal`; no acumula indefinidamente matrices.
- `set_goal` y el agarre construyen un objetivo local de posición y orientación, sin escala ni cizalla del cuerpo. La normalización ocurre antes de simular y enviar.
- El receptor de red continúa siendo estricto. Órdenes y entradas comparten `HandInput.valid_target`; no se aumentaron tolerancias para admitir matrices deformadas.
- Un fallo de codificación deja `hand_input_encode_failed`; los objetivos locales no finitos o degenerados se rechazan conservando el anterior. La API local interpreta orientación, no escala; esa conversión no se aplica a paquetes entrantes.
- La bandeja conserva un registro acotado `seen` de los ticks recibidos dentro de su ventana. Distingue duplicado y conflicto después de consumir; no reejecuta esos datos. El registro caduca, se retira con la sesión y respeta los límites de capacidad. `o.goals` muestra solo pendientes.

## Verificación enfocada

Pruebas de Claude sin modificar sus criterios. Evidencia en `implementacion/tmp/revision_entrega_4/` y resumen en `resultados_codex_entrega_4.json`.

| Comprobación | Resultado |
| --- | --- |
| `grab_rotate / clean` | E0, H1, N2a/N2b y los demás criterios ejecutados pasan. 151 pasos con objetivos iguales, 0 respaldos, 0 m/0° de diferencia y traspaso sin salto |
| `hand_timeline_test.gd` | 23 pasan, 0 fallan, incluido L19 |
| `response_receiver_test.gd` | 27 pasan, 0 fallan con su argumento `--trace` |
| `hand_adapter_test.gd` | 15 pasan, 0 fallan con su argumento `--trace` |
| `tools/inspect_hand_rotation.gd`, de Codex | Productor nuevo: 20.001 eventos válidos y codificables. Es una comprobación de construcción, no una prueba independiente |

Se preservaron los primeros intentos de los dos verificadores a los que Codex omitió pasar `--trace`: fallaron las comprobaciones basadas en esa traza. Se repitieron únicamente esos instrumentos con la invocación completa. La prueba de red conserva la limitación de la consulta CIM final del runner y se analizó por separado con el verificador original.

El I16 anterior reproduce literalmente la fórmula vieja sobre una variable propia. **No se modificó ni se declara aprobado.** Debe conservarse como reproducción histórica y agregarse una prueba del productor nuevo; aflojar el validador para aceptarla reintroduciría el problema.

Una actualización del entorno dejó el launcher principal sin poder preparar procesos por una ruta POSIX de permisos inválida en Windows. Las verificaciones finales se ejecutaron con el mismo Godot y argumentos equivalentes desde JavaScript, con límites externos y dentro de la copia autorizada. Se conservan salidas y errores; no se cambió el motor.

## Ensayo siguiente y dependencia pendiente

Se construyó una fixture independiente en `prototypes/rollback_rapier/` y su preparador `tools/testing/prepare_rapier_probe.ps1`. [Descripción](../../../prototypes/rollback_rapier/README.md).

Primero debe demostrar guardado, restauración y repetición de contactos de dos cuerpos dinámicos. Usa API contrastadas con el código exacto de **Godot Rapier v0.36.0**, con hash fijado del paquete. El preparador trabaja en una copia nueva dentro de `tmp/`, excluida de la exploración del juego; no instala nada global ni cambia el backend del laboratorio.

Comprobado: sintaxis y control negativo con Jolt, que devuelve `BLOCKED / backend_not_prepared`. **No se ejecutó con Rapier.** La descarga no se pudo completar desde el entorno. Hace falta este ZIP oficial, sin extraer, en Descargas:

https://github.com/appsinacup/godot-rapier-physics/releases/download/v0.36.0/godot-rapier-3d-single.zip

Nombre esperado: `godot-rapier-3d-single.zip`, tamaño publicado 63.038.621 bytes. El preparador verifica el SHA-256 antes de utilizarlo. Recibir el archivo no aprueba Rapier ni cambia el juego.

F3/F4/F5/F8/F9 siguen abiertos. Un ensayo positivo no resolvería automáticamente la red, la topología de inventario, las islas, el costo o la compatibilidad del personaje. La adopción de otro motor no está decidida.

## Encargo acotado para Claude

La entrega 4 está en `objetos/implementacion`; `..\entrega_4.json` identifica el hash. La copia de validación se conserva en `ed8968c`. Actualizar por fetch local y avance directo, preservando pruebas y trazas.

Verificar solamente:

1. Productor real `rotate_goal`/`HandRotation` durante al menos 20.001 actualizaciones y `grab_rotate`. Conservar la fórmula antigua de I16 como control negativo y no cambiar tolerancias.
2. Canonización local, rechazo de objetivos no finitos/degenerados y coherencia de validadores de red.
3. Diagnóstico ante una codificación imposible, sin corte silencioso.
4. L19/L20 tras consumir, caducidad y límites de `seen`, sin reutilización física ni regresión del adaptador.

No repetir la matriz completa ni aprobar contactos o sueltas tardías. El ensayo del backend corresponde a Codex y espera la dependencia; no se pide a Claude instalar o validar un backend todavía no ejecutado.
