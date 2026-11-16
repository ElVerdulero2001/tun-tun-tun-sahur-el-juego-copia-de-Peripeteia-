# Revisión de Claude 5 y entrega 6

2026-11-16. Se revisó el informe de Claude `docs/net/validacion_objetos/entrega_5.md`, sus criterios y los instrumentos de `637fa91`. Se incorporaron por avance directo a `implementacion`, sin cambiar las pruebas ni su copia de validación.

## Dictamen

**Las correcciones N3/L19 de la entrega 4 quedan aceptadas por la validación independiente.** El productor real de giro, la canonización, los validadores estrictos y los duplicados consumidos cumplen los casos probados.

**Se rechaza usar `StateManager3D` de Rapier v0.36.0 como predictor aislado de este juego.** La capacidad básica de replay es real, pero no basta para integrarlo. Los resultados R3/R4 demuestran corrupción de identidad y rebobinado fuera de la raíz. El resultado positivo de la entrega 5 queda limitado a su fixture; no aprobaba esa integración.

## Reproducción enfocada por Codex

Instrumentos originales de Claude, sin cambios. Corrida: `implementacion/tmp/revision_entrega_6/rapier/20261116_191307/`. Cuatro procesos, cada uno limitado a 8 s; terminaron en menos de 0,4 s con código 0. En estos instrumentos, código 0 significa que el ensayo terminó, no que sus criterios pasaron.

| Caso | Resultado reproducido |
| --- | --- |
| `r3_export` | Exportación válida, 176.056 bytes de artefacto |
| `r3_import_reverse_only` | Fallan R3f/R3g: mismo contenido íntegro, orden de creación distinto, repetición y sincronización incorrectas |
| `r4_spaces` | Fallan R4b/R4c/R4d/R4f. X e Y vivos comparten IDs 15/16, consultas incorrectas y rebobinado de O |
| `r4_spaces_control` | Pasan sus cuatro criterios, sin restauración |
| Comparación contra el control | Segundo espacio físicamente exacto; O, del mismo espacio pero fuera de la raíz, se separa 2,1319 m |

Se ejecutó `rv_compare.mjs` original. No hay errores de script, procesos vencidos ni Godot restantes. El primer intento de Codex pasó `OutRoot` relativo: el runner lo reutilizó como ruta del proyecto desde otra carpeta y los procesos terminaron con 1 sin resultados. Se conserva en `rapier/20261116_191131/`; no se cuenta como reproducción. Se repitieron únicamente esos cuatro casos con ruta absoluta.

Se contrastaron las causas con el [StateManager fijado](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/src/nodes/state_manager.rs) y el [servidor extra](https://github.com/appsinacup/godot-rapier-physics/blob/v0.36.0/src/servers/rapier_physics_server_extra.rs): el primero carga el espacio completo y restaura `physics_server_id`; el segundo borra y vuelve a insertar asociaciones de IDs al importar cada objeto. La rama `main` consultada conserva ese código. No se afirma que cualquier versión futura tenga el mismo defecto.

## Correcciones de construcción de esta entrega

1. **D4:** `_apply_local_hand_goal` valida la entrada antes de entregarla al controlador y antes de ponerla en la historia redundante. Una entrada inválida deja `hand_input_encode_failed` con `reason=invalid_local_frame` y se descarta sola. El objetivo físico anterior se conserva; los siguientes ticks válidos se transmiten normalmente. El codec y el receptor siguen estrictos: no se cambió su tolerancia ni se canonizan paquetes entrantes.
2. **G02:** un punto de agarre no finito deja ahora `invalid_local_anchor` antes de rechazarse. Se conserva el objetivo y la cola anteriores.
3. C09b se mantiene como límite documentado de la API local: no se amplió el rango de determinantes aceptados ni se interpretó esa observación como un fallo físico del catálogo.

Verificaciones realizadas después de esas correcciones:

| Caso | Resultado |
| --- | --- |
| `grab_bad_target / clean`, driver y análisis originales | D1/D2/D3 pasan; un aviso en el tick inválido, ninguno de los cinco siguientes llega tarde. Respaldo del host limitado al único tick descartado |
| N2b en ese caso artificial | Sigue FAIL por ese tick deliberadamente inválido. No se declara aprobado ni se cambia el criterio |
| `grab_rotate_real / clean` | Pasan todos los criterios ejecutados. 20.400 eventos, 151 pasos comunes, 0 respaldos, 0 m/0° |
| `hand_rotation_test` original | 25 pasan, 0 fallan. C14 permanece correcto; además hay exactamente un `invalid_local_anchor` en la traza de G02 |

Los dos runners de red escribieron `run.json` con ambos procesos en código 0 y luego fallaron en la consulta CIM final por permisos de esta sesión, antes de llamar a su analizador. Se preservó ese error y se ejecutó por separado el analizador original sobre las trazas completas. No se modificó el runner de Claude. Los procesos no quedaron abiertos.

## Decisión técnica y bloqueo de construcción

El próximo candidato queda definido en el [contrato del núcleo físico de objetos](../contrato_nucleo_fisico_objetos.md): una extensión acotada, con mundos Rapier propios y sin cargar IDs del servidor global de Godot. Eso permite conservar Jolt para el personaje y evita depender de una reparación parcial del mapa global. **Es un diseño para comprobar; todavía no hay un núcleo propio compilado ni replay de red aprobado.**

No se añadieron wrappers que solo eleven el contador después de restaurar: eso no corrige las colisiones de IDs ni la confusión de mapas al importar. Tampoco se obliga a host e invitado a crear todo en el mismo orden para esconder R3.

La preparación encontró un bloqueo real: no están disponibles Rust/Cargo ni las herramientas de compilación de Windows en las rutas comprobadas. Sin eso no puede compilarse y validarse la extensión. [Preparación necesaria](../preparar_compilacion_objetos.md). Los permisos actuales no permiten instalar herramientas en carpetas del sistema. Se conserva el diagnóstico en `implementacion/tmp/revision_entrega_6/toolchain/preflight.json` y en el resumen versionado.

El laboratorio y los recursos del juego conservan su recorrido actual. `model_approved=false`, `laboratory_migrated=false`; el backend publicado se considera bloqueado para el predictor aislado. No se pide a Claude repetir sus ensayos de Rapier hasta que exista otro componente compilado. Si continúa con pruebas mientras se prepara el entorno, el alcance útil son D4/G02 y la regresión de giro de esta entrega.
