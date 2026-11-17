# Revisión de Claude 9 y entrega 10: primer adaptador local

2026-11-17. Base independiente: `74deb0e`, sobre la entrega 9 `db4b6e0`. Se leyeron el informe, criterios y verificadores; se incorporaron por avance directo en `implementacion`, conservando la copia de Claude y sus instrumentos.

## Decisión

Se acepta la corrección de grafos y pose fija **dentro del uso `trusted` declarado**. Claude comprobó las 22 mutaciones que provocaban pánico, las 25 que movían el piso y 1.692 restauraciones genuinas sin falsos rechazos. Sus regresiones de 135 comprobaciones Rust y 79 Godot pasan. La diferencia de signo de cinco ceros no tuvo efecto físico medido, pero queda corregida para cumplir la comparación estricta por bits.

N3 confirma que datos internos alterados con checksum recalculado pueden colgar o abortar `step()`. No se acepta este formato como frontera de red ni se amplía esa promesa. Se conserva el diagnóstico y la marca `#[ignore]` del instrumento exploratorio de Claude. No se vuelve a ejecutar con `--ignored`: no es un criterio cerrado ni aprobado por esta entrega.

El costo adicional de validación medido por Claude —unos 4,2 ms por restauración de su pila de 128, contra 1,9 ms antes— queda registrado. Son tiempos dev opt 1 en una PC; no aprueban rendimiento. No se retira la validación de la caché local para mejorar artificialmente esos tiempos.

## Construcción nueva

1. La pose real del cuerpo fijo y su manifiesto se comparan mediante `to_bits`, incluidos +0/−0. Se amplió una prueba propia y se conservaron los barridos originales de Claude.
2. Se creó [el adaptador local de actor y reloj](../../../prototypes/objetos_adaptador/README.md), sin cambiar los scripts de producción. Captura `ActorInput` con su codec real y recibe `tick_finished` del `SimClock` real después de `ActorMotor`.
3. Los objetivos usan los ojos reales del actor en ese tick y `InvHoldMotion.target_of`; el paso usa el dt del mundo de ese tick. Se guardan input, ojos, dt y acción para repetirlos sin consultar el input actual ni volver a mover al actor.
4. La reconciliación restaura y avanza un mundo candidato. Solo sustituye el activo al completar todos los pasos. El lanzamiento se repite físicamente cuando corresponde, pero las señales de efecto externo no se repiten.
5. Diario, acciones y trabajo tienen límites explícitos. Un salto del reloj, cambio de Tuning, falta de historia o exceso de replay detienen la predicción y solicitan recuperación. El adaptador todavía no implementa esa recuperación ni el traspaso visual.

Alcance deliberadamente acotado: un actor/una mano, vecinos libres, contexto fijo y cajas centradas. El driver inyecta entradas en la captura y usa checkpoints de una referencia local. No se han integrado `InvHands`, `NetSync`, autoridad/inventario, dos manos activas, transporte, geometría preparada del nivel ni presentación. La condición 4 completa del contrato sigue abierta.

## Evidencia final

| Verificación | Resultado |
| --- | --- |
| CoreTests, incluidos instrumentos de Claude 9 | 29 funciones pasan en 15 ejecutables; una exploratoria permanece ignorada; ningún proceso vencido |
| N2, 64.440 mutaciones de todos los bits | Ambos ejecutables pasan; 0 poses fijas distintas por bits aceptadas |
| N1, snapshots genuinos | Sin falsos rechazos; se conserva la repetición exacta en los escenarios de Claude |
| Runner Rust original de Claude | 135 PASS, 0 FAIL, 23 INFO, 1 NOEVAL; SHA de referencia conservado entre procesos |
| Runner Godot y analizador originales de Claude | 79 PASS, 0 FAIL, 4 INFO; nueve procesos en código 0 y sin vencer |
| Adaptador: normal, cámara lenta y pausa | Igualdad exacta con una referencia en el mismo tick; dos reconciliaciones, 17 pasos repetidos por proceso; actor/reloj no repetidos y efectos no duplicados |
| Adaptador: resync, presupuesto y Tuning | Recuperación explícita y mundo nativo conservado |
| Adaptador: historia | 150 ticks reales, solo 120 frames conservados; el primero es el 31 |
| Importación y siete procesos del adaptador | Código 0, sin vencer 8 s, sin errores de script/carga; máximo observado 3,702 s, en la importación |
| Instrumentos de Claude | Sin diferencias respecto de `74deb0e` |

Son ensayos de construcción de Codex. La extensión recompiló con código 0 en 9,654 s. Godot solo conserva el aviso conocido de certificados raíz de Windows.

Carpetas de evidencia dentro de `implementacion/`:

- `tmp/native_build/20261117_121045_CoreTests_636168/`.
- `tmp/native_build/20261117_121059_Extension_8b444e/`.
- `tmp/revision_entrega_9/rust_20261117_092112/`, con `report.json` del analizador original.
- `tmp/revision_entrega_9/godot_20261117_092113/`, con `compare.json` del analizador original.
- `tmp/clock_probe/20261117_122210_1579ca/`: importación, siete modos, trazas por tick y hashes de scripts copiados.
- [Resumen y hashes](resultados_codex_entrega_10.json).

## Fallos de construcción conservados

La primera ampliación de la prueba propia intentaba introducir −0 mediante `RigidBody.set_position`, pero Rapier compara numéricamente y no reemplaza una posición equivalente. Esa fixture no estaba alterada. Se cambió el signo en el manifiesto del candidato; el barrido independiente sigue probando la mutación de los cuerpos. El fallo original se conserva en `tmp/native_build/20261117_120817_CoreTests_3ced75/`.

El primer control negativo del adaptador aplicaba un impulso que la mano cancelaba antes del paso y no generaba divergencia. Se aumentó el impulso del control para ejercer la corrección sin cambiar su criterio. Dos intentos posteriores del driver usaban checkpoints ya aceptados para probar presupuesto y cambio de Tuning: correctamente se ignoraban como duplicados. Se corrigió el driver para usar un checkpoint nuevo. Esas corridas fallidas se conservan en `tmp/clock_probe/` y no cuentan como aprobadas.

## Próximos pasos y límites

Antes de trasladarlo al laboratorio faltan el transporte autorizado/acotado de entradas y checkpoints, la política temporal de acciones que llegan tarde, la integración con las correcciones del actor, el replay de todas las manos activas de la isla, el catálogo/topología variable y la presentación. El diario de ojos/dt debe corregirse o invalidarse si cambia la historia del actor o del tiempo; no se ha conectado esa ruta a `NetSync`.

Los límites provisionales son 120 frames y 256 KiB serializados de diario, 256 acciones y 24 pasos por corrección. No son presupuestos de rendimiento aprobados. Durante la corrección hay dos mundos y sus cachés vivos; hace falta medir el pico de memoria y el costo en la notebook. **`model_approved=false`; `laboratory_migrated=false`.**

## Encargo de Claude: entrega 10

1. Actualizar su copia mediante fetch local y avance directo desde `implementacion`, conservando instrumentos y trazas. `../entrega_10.json` identifica el checkpoint y hashes. Compilar su propia DLL con la caché compartida; no hacen falta dependencias nuevas.
2. Verificar el cambio de signo del cero mediante sus N1/N2 originales. No repetir N3 exploratorio ni declarar resuelto el formato hostil. Mantener todos los procesos limitados externamente a 8 s.
3. Leer `prototypes/objetos_adaptador/README.md` y construir criterios propios para este alcance local. Verificar con hashes que ActorInput, ActorMotor, SimClock, el actor y las funciones de ojos/objetivo son copias exactas, y que el actor realmente se mueve antes de tomar el objetivo.
4. Construir instrumentos propios en `prototypes/objetos_adaptador/validacion_claude/`. Variar las entradas en el momento de capturarlas; comprobar que replay no consulta al proveedor ni al actor del presente y usa los bytes/ojos/dt guardados. Probar cámara lenta, pausa, duplicados, errores atómicos, límites, resincronización y cambio de Tuning.
5. Ejercitar una restauración anterior al lanzamiento para comprobar tanto la repetición física de esa acción como la ausencia de efectos externos repetidos. Incluir controles negativos sensibles y comparar el mismo tick. Señalar datos/API faltantes antes de inventar una integración con red o inventario.
6. No modificar adaptador, núcleo, driver/runners de Codex, producción ni tolerancias. Si hace falta instrumentación, describirla. Informe en `docs/net/validacion_objetos/entrega_10.md`.
7. No certificar ENet del adaptador, controles completos del juego, presentación, dos PC ni rendimiento: aún no están implementados/probados en este recorrido.
