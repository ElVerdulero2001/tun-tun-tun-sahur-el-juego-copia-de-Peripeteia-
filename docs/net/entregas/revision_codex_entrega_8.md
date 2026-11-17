# Revisión de Claude 8 y entrega 9

2026-11-16, hora argentina. Se revisaron el informe, los criterios y los instrumentos de Claude en `25d97f8`, sobre la entrega `aeee009`. Se incorporaron por avance directo a `implementacion`. La copia de Claude, sus pruebas y su informe original se conservan sin cambios.

## Dictamen

Se aceptan las condiciones 1–3 del contrato en el alcance comprobado: contacto activo, reposo/despertar, identidad, aislamiento entre instancias e importación entre procesos. También se acepta la suelta tardía con vecinos dinámicos y una segunda mano durante la repetición, **con el cronograma preacordado del ensayo**. No valida el controlador real del actor, SimClock ni la presentación del juego.

La validación independiente de la entrega 8 arrojó 134 comprobaciones Rust aprobadas, una fallida y una no evaluable; las 79 de Godot pasaron. D18b demuestra un defecto real de restauración, aunque los datos alterados con checksum recalculado estén fuera del uso `trusted` declarado. Se reproduce y corrige aquí; no se cambia su criterio ni se captura el pánico para convertirlo en aprobación.

## Reproducción y corrección

Antes de modificar el núcleo se ejecutaron los instrumentos originales de Claude en `implementacion/tmp/revision_entrega_8/baseline/rust_20261116_230626`. Resultado: 134 PASS, 1 FAIL, 23 INFO, 1 NOEVAL. D18b acepta 22 snapshots que provocan pánico al consultar contactos y otros 25 que alteran la pose física del piso conservando su manifiesto.

Cambios de la entrega 9:

1. `snapshot_graph.rs` inspecciona los grafos serializados mediante una vista del formato serde de **Rapier 0.36.0 fijado por Cargo.lock**. Comprueba handles vivos y únicos, extremos, pares únicos sin autoaristas, límites y listas de adyacencia completas, con enlaces anteriores/siguientes consistentes y sin ciclos. Los índices se verifican antes de seguirlos. Una actualización de Rapier exige revisar esta vista. No se modifica ni reconstruye el grafo del candidato.
2. Se comprueba la asociación entre los extremos y el par físico, y que las consultas por collider devuelvan sus pares incidentes. Los errores son `snapshot_contact_graph` o `snapshot_contact_mapping`.
3. La pose real y el tipo del cuerpo fijo deben coincidir con su manifiesto; una discrepancia devuelve `snapshot_fixed_pose`. Comparar dos copias de `fixed_pose` no alcanzaba.
4. Todo se verifica antes de sustituir el estado activo o invalidar su caché. Dos pruebas propias cubren enlaces/ciclos/extremos/handles y cambios de traslación, giro o tipo del piso con checksum válido y conservación de la caché.

No se cambian el solver, formato del snapshot, controlador, umbrales físicos ni instrumentos de Claude. La inspección usa una copia temporal serializada acotada; su costo requiere medición en la notebook. Esta corrección no convierte el formato en un deserializador para datos arbitrarios de red: otras mutaciones con checksum recalculado siguen siendo aceptadas. La frontera de protocolo sigue pendiente y un invitado no puede aportar estos snapshots.

## Verificación después de corregir

| Verificación | Resultado |
| --- | --- |
| Builder CoreTests | 23 funciones Rust pasan: 9 originales, 12 de Claude (una diagnóstica) y 2 nuevas propias; todos los ejecutables en código 0 y sin vencer 8 s |
| Runner Rust original de Claude, con repetición en otro proceso | 135 PASS, 0 FAIL, 23 INFO, 1 NOEVAL; las trayectorias conservan el SHA original |
| D18b, mismo barrido de 8.055 mutaciones | 0 pánicos al restaurar o consultar; 0 rechazos que modifican el destino; 25 cambios del piso rechazados y 0 aceptados |
| Builder Extension | DLL recompilada en 10,248 s, código 0 |
| Siete procesos Godot de Codex | Todos PASSED y código 0; sin vencer, sin errores de script/carga |
| Nueve procesos Godot y analizador originales de Claude | 79 PASS, 0 FAIL, 4 INFO; código 0 y ningún proceso restante |
| Suelta tardía, variante push de Claude | T=71, presente P=75, 4 pasos repetidos; B en contacto y movimiento, C conserva agarre y objetivos; igualdad desde el mismo tick confirmado |
| Instrumentos de Claude | Sin diferencias respecto de `25d97f8` |

Solo aparece el aviso conocido de certificados raíz de Windows. Estos son resultados de Codex ejecutando instrumentos originales de Claude sobre una implementación corregida, **no una nueva aceptación independiente de Claude**.

Evidencia dentro de `implementacion/`:

- CoreTests: `tmp/native_build/20261117_021014_CoreTests_d1e378/`.
- Rust corregido: `tmp/revision_entrega_8/corrected/rust_20261116_231047/`, con `report.json` del analizador original.
- Extensión: `tmp/native_build/20261117_021049_Extension_a11427/`.
- Godot propio: `tmp/native_probe/20261117_021133_b35c67/`.
- Godot de Claude: `tmp/revision_entrega_8/corrected/godot_20261116_231121/`, con `compare.json` del analizador original.
- Resumen y hashes: [resultados_codex_entrega_9.json](resultados_codex_entrega_9.json).

## Capacidad y próximo adaptador

Se conserva el límite de 16 MiB y **hasta** 120 checkpoints. Con la fixture de 128 cuerpos apilados y 490 contactos listados, cada snapshot ocupa 614.284 bytes y caben **27** checkpoints: unos 0,45 s a 60 ticks/s. No se aumenta la memoria para ocultarlo. El adaptador deberá usar la historia realmente disponible y recuperarse explícitamente cuando el tick requerido haya vencido.

La siguiente construcción es el adaptador del prototipo, con estas condiciones antes de migrar:

1. Registrar por tick entradas reales de agarre, objetivo, giro, suelta y lanzamiento del actor, identificadas por sesión, aparición y acción. El replay usa esas entradas guardadas, no objetivos futuros conocidos por la fixture.
2. Conectar el paso manual al orden real de SimClock y guardar el dt del mundo por tick. Documentar adelanto, aplicación tardía, pausa/cámara lenta y saltos de reloj; conservar el reloj del personaje.
3. Presupuestar historia, máximo de pasos de replay y recuperación por contexto o historia vencida. Medir con geometría preparada y en la notebook objetivo.
4. Diseñar transferencia autorizada y acotada de checkpoints: los 6–614 KB medidos no se envían sin más como snapshots frecuentes de producción. Comprobar tamaño, reensamblado, sesión, revisión y límites antes de entregar bytes al núcleo.
5. Presentar las correcciones con un único responsable de dibujo y sin devolver offsets visuales a la física; probar traspaso a réplica. Los saltos físicos medidos de decenas de centímetros no demuestran continuidad visual.

Catálogo, COM desplazados, formas custom, geometría de nivel, apoyos móviles, inventario/topología variable, latencia/pérdida y dos PC siguen pendientes. **`model_approved=false`; `laboratory_migrated=false`.**

## Encargo acotado para Claude: entrega 9

1. Actualizar su copia por fetch local y avance directo desde `implementacion`, conservando pruebas y trazas. `../entrega_9.json` identifica el checkpoint y hashes. No copiar binarios de la implementación.
2. Revisar la corrección de grafos y pose fija antes de ejecutarla. Conservar D18 original y agregar verificadores propios si hacen falta; no modificar núcleo, bindings, fixtures, runners de Codex ni tolerancias.
3. Compilar CoreTests y Extension con `-CargoCachePath '..\implementacion\tmp\native_toolchain\cargo'`. No hacen falta dependencias nuevas. Ejecutar su runner Rust y analizador; confirmar D18 sin pánicos, ausencia de cambios del piso aceptados, rechazos atómicos e historia intacta.
4. Ejecutar su runner Godot y analizador originales: aislamiento, archivo y ambas variantes ENet. Mantener procesos limitados externamente a 8 s. Distinguir esta regresión de una aprobación del controlador real.
5. Revisar el acoplamiento de la vista serde a la versión fijada, falsos rechazos y costo adicional. Registrar límites sin aprobar rendimiento ni datos hostiles.
6. Informar en `docs/net/validacion_objetos/entrega_9.md`. No repetir los ensayos descartados de StateManager ni declarar migrado el laboratorio.
