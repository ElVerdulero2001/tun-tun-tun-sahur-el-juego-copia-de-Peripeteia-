# Coordinación de la reconstrucción de objetos

## Reparto acordado

El usuario asignó a **Codex/GPT la construcción e integración del sistema** y a **Claude las pruebas independientes**. Fecha de inicio: 2026-11-16. El [plan de reconstrucción](plan_refactorizacion_sincronizacion_objetos.md) define las etapas; este documento indica el estado y las fronteras de trabajo.

| Responsable | Puede modificar | No modifica |
| --- | --- | --- |
| Codex | Implementación, adaptadores, contratos, escena de referencia y documentación técnica | Pruebas de Claude para bajar sus exigencias o hacerlas coincidir artificialmente con la implementación |
| Claude | Nuevos drivers y verificadores en `prototypes/objetos_red/validation/`, informes en `docs/net/validacion_objetos/` y sus resultados fuera de código | `runtime/`, `main.gd`, protocolo, Tuning, recursos, lógica del laboratorio, runner de carga y umbrales acordados |
| Codex al integrar | Incorpora pruebas revisadas y corrige implementación ante fallos demostrados | No integra automáticamente ni modifica el trabajo original de otro sin revisar el diff |

Claude puede leer toda la implementación y señalar defectos. Si necesita instrumentación adicional, la describe con el dato ausente y el caso que lo requiere; Codex modifica el componente. No debe reparar el runtime dentro del encargo de validación.

## Base preservada y carpetas

El repositorio original continúa en su rama `net-lab-auditoria-hitbox`, sin commits nuevos de esta preparación. La base se capturó desde `677086fb4c882b8c678a5d9895b164cd76c3f52f`, incorporando los cambios locales y los archivos nuevos de código/documentación. La eliminación preexistente de la auditoría de parkour también se preservó.

Raíz de las copias independientes:

`C:\Users\ElCaido97\Documents\tun-tun-tun-sahur\tmp\colaboracion_objetos_20261116`

| Carpeta | Función |
| --- | --- |
| `base` | Checkpoint común; no se desarrolla allí |
| `implementacion` | Copia Git para continuar la construcción, rama `objetos/implementacion` |
| `validacion_claude` | Copia Git para Claude, rama `objetos/validacion` |
| `base_manifest.json` | Hashes SHA-256 de los 721 archivos preservados en la base inicial |
| `estado_original.txt`, `cambios_originales.patch` | Registro del estado y diff previos a comenzar la construcción |
| `entrega_1.json` | Identidad del checkpoint entregado, ramas y manifest del prototipo |

Se usan clones locales independientes en lugar de worktrees para no escribir metadatos en el Git original. Tienen su propio índice y sus propios objetos: cambiar de rama o hacer un commit en uno no cambia los archivos del otro. No copiar `.godot`, logs ni directorios `.git` entre ellos.

La carpeta `tmp` está excluida de exploración por Godot. Las fuentes nuevas revisables de esta entrega están también en `prototypes/objetos_red/` del repositorio original. El juego del laboratorio conserva su recorrido anterior mientras se evalúa el prototipo.

## Entrega 1

**Estado: prototipo construido, pendiente de validación independiente; migración al laboratorio bloqueada por la puerta de viabilidad del plan.**

Incluye cuerpo Jolt compartido, estado con identidad y revisión, acciones idempotentes, confirmaciones, transporte ENet, reloj de demostración, proxies cercanos, presentación separada y trazas. La [lectura de la entrega](../../prototypes/objetos_red/README.md) contiene API, comandos y límites conocidos. El [encargo de Claude](encargo_claude_validacion_objetos.md) define las pruebas.

Comprobaciones de construcción realizadas por Codex: análisis sintáctico de `main.gd` y dependencias; arranque local de 1,5 segundos con generación de traza y cierre normal. Eso **no valida** agarre, lanzamiento, red, convergencia ni ausencia del rebote original. El aviso de certificados raíz de Windows se conserva en stderr; no se confunde con un error de carga del script.

La inspección de `SimClock.apply_tick_rate` corrigió un punto del plan: el reloj ya modifica frecuencia física y escala conjuntamente y ejecuta un tick lógico por callback de física. El prototipo registra el orden de pasos para que Claude compruebe la correspondencia, en lugar de asumir una incompatibilidad del reloj.

## Entregas e integración

1. Claude trabaja únicamente en `validacion_claude` y registra el hash de base de `entrega_1.json` antes de empezar. No abre esa copia en Godot a la vez que un proceso de importación sobre la misma copia.
2. El primer informe distingue pruebas ejecutadas, fallos, casos todavía no construidos y decisiones abiertas. Adjunta comando, semilla, parámetros, trazas y criterio fijado previamente.
3. Codex revisa el diff y los casos reproducibles. Un fallo físico bloqueante vuelve a la implementación o al modelo, no a un aumento del umbral.
4. Una entrega posterior tiene nuevo identificador. Codex publica un diff o commit de implementación; Claude actualiza su copia preservando sus pruebas. No se sobrescribe toda su carpeta con una copia nueva.
5. Cambios de API/traza se documentan y acuerdan antes de depender de ellos. El contrato de la entrega 1 es provisional: todavía no es el protocolo final del laboratorio.
6. La integración al laboratorio, las pruebas de inventario/pilas y la validación manual en ambas PC siguen pendientes. Ningún resultado de carga autoriza a declararlas completadas.
