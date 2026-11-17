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

**Estado histórico: validado por Claude y rechazado por problemas de modelo.** Ver el informe en `docs/net/validacion_objetos/entrega_1.md`. La migración continúa bloqueada.

Incluye cuerpo Jolt compartido, estado con identidad y revisión, acciones idempotentes, confirmaciones, transporte ENet, reloj de demostración, proxies cercanos, presentación separada y trazas. La [lectura de la entrega](../../prototypes/objetos_red/README.md) contiene API, comandos y límites conocidos. El [encargo de Claude](encargo_claude_validacion_objetos.md) define las pruebas.

Comprobaciones de construcción realizadas por Codex: análisis sintáctico de `main.gd` y dependencias; arranque local de 1,5 segundos con generación de traza y cierre normal. Eso **no valida** agarre, lanzamiento, red, convergencia ni ausencia del rebote original. El aviso de certificados raíz de Windows se conserva en stderr; no se confunde con un error de carga del script.

La inspección de `SimClock.apply_tick_rate` corrigió un punto del plan: el reloj ya modifica frecuencia física y escala conjuntamente y ejecuta un tick lógico por callback de física. El prototipo registra el orden de pasos para que Claude compruebe la correspondencia, en lugar de asumir una incompatibilidad del reloj.

## Entregas e integración

**Entrega 10:** [revisión de Claude 9 y primer adaptador local](entregas/revision_codex_entrega_9.md). La corrección anterior queda aceptada en su uso trusted. Se ajustó el signo del cero y se construyó `prototypes/objetos_adaptador/`: actor/reloj reales, diario de inputs/ojos/dt y replay local acotado con efectos externos únicos. Siete modos de construcción pasan; espera validación independiente. No contiene transporte ni reemplaza el laboratorio. `../entrega_10.json` en la raíz de colaboración identifica el checkpoint.

**Entrega 9:** [revisión de Claude 8 y restauración corregida](entregas/revision_codex_entrega_8.md). Condiciones 1–3 del núcleo aceptadas en el alcance independiente; D18b reproducido y corregido sin modificar instrumentos. Pasan 135 comprobaciones Rust y 79 Godot de Claude al ejecutarlas Codex; la corrección requiere revisión independiente. Capacidad medida: 27 checkpoints con 128 cuerpos en la fixture de pila. El siguiente adaptador conectará input real, SimClock, presentación y transferencia acotada antes de migrar.

**Entrega 8:** [núcleo nativo construido y compilado](entregas/entrega_8_nucleo_nativo.md). Nueve pruebas Rust y siete procesos Godot de construcción pasan, incluidos aislamiento de mundos, identidad y una suelta tardía por ENet con comparación exacta en el mismo tick. La revisión independiente corresponde a Claude; el laboratorio no está migrado y el modelo completo sigue sin aprobar.

**Entrega 7, preparación:** [herramientas verificadas y descarga pendiente](entregas/preparacion_nucleo_objetos_entrega_7.md). Rust/MSVC generan una DLL. La conexión de Codex a crates.io falla; se deja un preparador para que el usuario descargue las dependencias en la caché del proyecto. El núcleo nuevo todavía no está implementado ni compilado. No repetir validación física hasta que exista.

**Entrega 6:** [revisión de Claude 5 y decisión del núcleo](entregas/revision_codex_entrega_5.md). N3/L19 aceptados. D4 descarta únicamente la entrada inválida y G02 informa el rechazo. Se reproducen R3/R4: `StateManager3D` publicado no se aprueba como predictor aislado. El siguiente candidato tiene [estado nativo propio](contrato_nucleo_fisico_objetos.md) y espera el entorno de compilación; no se pide repetir los ensayos del mismo backend. No se migró el laboratorio.

**Entrega 5:** [capacidad nativa con Rapier](entregas/ensayo_rollback_rapier_entrega_5.md). Pasaron restauración local y exportación/importación entre procesos con IDs distintos en la fixture de topología fija. El modelo de red sigue sin aprobar; falta verificación independiente y aislamiento respecto de otros espacios vivos. El laboratorio conserva su motor y recorrido actuales.

**Entrega 4:** [revisión de N3 y ensayo siguiente](entregas/revision_codex_entrega_3.md). Giro corregido, L19 aprobado; el ensayo nativo está preparado y espera su paquete oficial. No se migró el laboratorio.

**Entrega 3 (2026-11-16):** [revisión de la entrega 2 y contrato de entradas](entregas/revision_codex_entrega_2.md). La validación de Claude confirmó las correcciones anteriores. Se corrigieron N1/N2 con respuestas identificadas y una bandeja de entradas tempranas, más redundancia de seis ticks. El modelo físico continúa sin aprobar; el nuevo formato todavía requiere su verificación independiente.

**Entrega 2 (2026-11-16):** [revisión de Codex, correcciones y próximo encargo](entregas/revision_codex_entrega_1.md). El trabajo está en `implementacion`; no se sobrescribió la copia de Claude. La caída y las acciones tempranas mejoraron en verificaciones enfocadas, pero el caso tardío sigue fallando y los proxies dinámicos no están aprobados. Falta evaluar una capacidad real de rollback de isla física; no se ha construido ni aprobado esa alternativa.

1. Claude trabaja únicamente en `validacion_claude` y registra el hash de base de `entrega_1.json` antes de empezar. No abre esa copia en Godot a la vez que un proceso de importación sobre la misma copia.
2. El primer informe distingue pruebas ejecutadas, fallos, casos todavía no construidos y decisiones abiertas. Adjunta comando, semilla, parámetros, trazas y criterio fijado previamente.
3. Codex revisa el diff y los casos reproducibles. Un fallo físico bloqueante vuelve a la implementación o al modelo, no a un aumento del umbral.
4. Una entrega posterior tiene nuevo identificador. Codex publica un diff o commit de implementación; Claude actualiza su copia preservando sus pruebas. No se sobrescribe toda su carpeta con una copia nueva.
5. Cambios de API/traza se documentan y acuerdan antes de depender de ellos. El contrato de la entrega 1 es provisional: todavía no es el protocolo final del laboratorio.
6. La integración al laboratorio, las pruebas de inventario/pilas y la validación manual en ambas PC siguen pendientes. Ningún resultado de carga autoriza a declararlas completadas.
