# Encargo para Claude: validación independiente de objetos

**Encargo vigente: entrega 12.** Leer [revisión de Claude 11 e historia desde ClientPrediction](entregas/revision_codex_entrega_11.md), su encargo final y el README actualizado del adaptador. `../entrega_12.json` identifica el checkpoint. Verificar ojos/estados desde replay real, grabación durante suspensión, falta de historia y estado coincidente, generaciones, capturas idempotentes, efectos/confirmaciones y guardas anteriores de ClientPrediction. Mantener los instrumentos originales y S1 anulado por el conteo conocido sin cambiarlo para volverlo verde. Procesos limitados a 8 s. No modificar implementación ni aprobar transporte, integración, dos PC o rendimiento. No repetir N3.

**Antecedente: entrega 11.** [API local de autoridad e historia corregida](entregas/revision_codex_entrega_10.md) e [informe independiente](validacion_objetos/entrega_11.md).

**Antecedente: entrega 10.** [Adaptador local](entregas/revision_codex_entrega_9.md) e [informe independiente](validacion_objetos/entrega_10.md).

**Antecedente: entrega 9.** [Corrección](entregas/revision_codex_entrega_8.md) e [informe independiente](validacion_objetos/entrega_9.md).

**Antecedente: entrega 8.** [Núcleo nativo y reproducción](entregas/entrega_8_nucleo_nativo.md). Su [informe independiente](validacion_objetos/entrega_8.md) se conserva sin cambios.

**Antecedente: entrega 6.** Leer [revisión de Claude 5 y bloqueo nativo](entregas/revision_codex_entrega_5.md). No repetir Rapier sin un núcleo corregido y compilado. El único alcance nuevo de verificación independiente es D4/G02 y la regresión del giro. La copia de Claude permanece en `637fa91`; `../entrega_6.json` identifica la implementación nueva. Las secciones siguientes son antecedentes.

**Antecedente: entrega 5.** Leer [capacidad Rapier y verificación independiente acotada](entregas/ensayo_rollback_rapier_entrega_5.md). Incluye las verificaciones pendientes entonces de la entrega 4.

**Antecedente: entrega 4.** Leer [revisión de N3 y verificación acotada](entregas/revision_codex_entrega_3.md).

**Antecedente: entrega 3.** Leer [revisión de la entrega 2 y lista acotada de verificaciones](entregas/revision_codex_entrega_2.md). No repetir toda la matriz histórica.

**La entrega 1 ya fue evaluada.** Para la revisión siguiente, leer [correcciones y encargo de la entrega 2](entregas/revision_codex_entrega_1.md), que indica cómo actualizar la copia preservando las pruebas. Lo que sigue documenta el encargo original.

## Objetivo y carpeta de trabajo

Tu función es construir y ejecutar pruebas independientes del sistema que implementa Codex. **No reparar el runtime ni migrar el laboratorio.** El usuario acordó este reparto. Buscar defectos y demostrar límites es un resultado válido, aunque una prueba falle.

Trabajá en:

`C:\Users\ElCaido97\Documents\tun-tun-tun-sahur\tmp\colaboracion_objetos_20261116\validacion_claude`

Tu rama es `objetos/validacion`. Verificá `git status`, la rama y el hash de base indicados en `..\entrega_1.json`. Leé `docs/net/coordinacion_refactor_objetos.md`, el plan, el diagnóstico y `prototypes/objetos_red/README.md` de esa copia. El proyecto que se ejecuta para esta entrega es **`prototypes/objetos_red/project.godot`**.

Se trata de un prototipo experimental, no de una solución terminada. El laboratorio principal sigue usando el recorrido anterior. No hace falta repetir las baterías históricas de cientos de comprobaciones para evaluar esta entrega.

## Archivos permitidos

- Crear drivers, escenas auxiliares y verificadores en `prototypes/objetos_red/validation/`.
- Crear informes en `docs/net/validacion_objetos/`.
- Guardar logs y resultados en `tmp/validacion_objetos/`, con un archivo diferente por rol y corrida.
- Leer todo lo necesario. No modificar `runtime/`, `main.gd`, el proyecto, el runner, recursos ni contratos compartidos. Si falta un dato, informá la necesidad de instrumentación antes de cambiar la implementación.
- No committear logs, cachés ni resultados voluminosos. Los commits locales de pruebas son admisibles en tu copia; no hacer push, merges al original ni publicaciones.

## Primer bloque: contrato y tiempo

1. Verificar serialización de estado: tamaño 90 bytes, identidad, revisión persistente tras soltar, giro válido y rechazo de tamaño/versión/NaN/IDs inválidos. Probar bytes truncados y valores límite, no solo encode/decode de la misma implementación.
2. Probar idempotencia de acciones: duplicado antes y después de commit, repetición tras expulsar un resultado de la caché, acción vieja, sesión ajena y petición futura. Validar que un lanzamiento aporta un único impulso.
3. Comprobar el mapeo entre preparación y resultado nativo usando `physics`, `engine_frame`, `native_frame`, `native_callbacks` y `native_dt`. Ejecutar un caso con ajuste del ritmo del cliente y otro con `--slow=0.3` en ambos lados. Comparar por instante físico/acción, no por línea de log o por llegada del paquete.
4. Verificar que un invitado no actúa antes de `world_ready` y `clock_ready`, y que la huella incompatible impide continuar.

## Segundo bloque: el fallo del usuario

Construí un driver que sostenga la caja a altura conocida, la estabilice y la suelte, sin depender de mover manualmente el mouse. Usá la API pública del README. La altura se mide desde la parte más baja de la geometría al piso, no desde la cámara.

Casos iniciales: caída desde **0,2; 0,5 y 1 m**, suelta con objetivo moviéndose lateralmente y lanzamiento. Host e invitado registran trazas simultáneas. Separar:

- Trayectoria física autorizada y predicha del mismo instante.
- Primer contacto y elevación posterior del centro de masa y de la geometría.
- Correcciones y cualquier movimiento agregado por `visual` o `handoff`.

La prueba debe detectar un ascenso artificial del invitado aunque nunca se hunda en el piso. No basta con medir penetración. Una convergencia final no absuelve una trayectoria que cambia de forma perceptible durante la caída.

Usá primero conexión local sin degradación; después, para los mismos casos, `--one-way-ms=100 --jitter-ms=40 --loss=0.05` en ambos extremos. Registrá RTT real y la diferencia entre simulación de aplicación y transporte ENet. La semilla de aplicación de esta entrega es 12345; no lanzar muchas semillas sin investigar el primer fallo.

## Tercer bloque: los límites que deciden el modelo

- Choque de la caja propia contra la segunda caja quieta y móvil. Verificar qué tiempo usó el proxy y si agrega energía o induce correcciones repetidas.
- Pared de 2 cm, movimiento hacia una esquina y giro durante el contacto. Buscar cruce físico y penetración del dibujo por interpolación.
- Entrada/salida de reposo y retorno a réplica. Medir el salto de `handoff`; no aceptar un ajuste perceptible por estar registrado o por ocurrir una sola vez.
- Soltar/lanzar inmediatamente después de pedir el agarre, antes del ACK. El README declara una espera en esta entrega: cuantificarla y reportarla como pendiente de respuesta inmediata, sin cambiar el criterio.
- Pedido de suelta tardío, duplicado, snapshot anterior a la transición y desconexión mientras se sostiene. Comprobar dueño único y ausencia de impulso doble.

Los límites declarados no autorizan a pasar una prueba que los contradiga. Clasificá si cada fallo bloquea la viabilidad del modelo, la migración posterior o solo una prestación todavía fuera de esta fixture. No afirmar cobertura de inventario, pilas o catálogo completo con estas dos cajas.

## Criterios y ejecución

Antes de correr cada caso, dejá escrito qué se mide y cómo se determina éxito/fallo. Derivá tolerancias de la resolución física y de los requisitos visuales; no las adaptes a los resultados observados. No usar el resultado de `run_object_prototype.ps1` como prueba de física: ese runner solo controla carga y cierre.

Cada caso automatizado debe tener un límite externo de **20 segundos como máximo**, con plazo menor de preparación y finalización explícita. Error de script, carga, conexión o proceso muerto: terminar solo los procesos propios, informar y corregir el driver o reportar el fallo del runtime. No continuar una batería con el invitado sin preparar. No usar `--fixed-fps` para deducir latencia real ni dejar procesos corriendo al finalizar.

La ejecución y los registros deben permitir reproducir el primer fallo. No repetir baterías completas por cambios que solo afectan una comprobación puntual.

## Entrega esperada

Crear `docs/net/validacion_objetos/entrega_1.md` con:

1. Hash de base, motor, comandos exactos y archivos de pruebas nuevos.
2. Tabla por caso: ejecutado o pendiente, resultado, métrica, tolerancia fijada y evidencia.
3. Primer fallo reproducible de cada problema distinto, con trazas de ambos roles y análisis que separe hechos de hipótesis.
4. Instrumentación faltante y cambios de contrato que Codex deba resolver, sin implementarlos dentro de tus pruebas.
5. Dictamen: viable para continuar, requiere corregir implementación o requiere revisar el modelo; junto con límites que impiden una conclusión más fuerte.

Dejar el trabajo en tu copia para revisión por Codex. No marcar como validada la reconstrucción completa ni incorporar cambios al repositorio original.
