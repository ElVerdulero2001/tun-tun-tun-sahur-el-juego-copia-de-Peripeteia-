# Suelta y lanzamiento: límite del modelo actual de sincronización

## Estado y evidencia

Análisis de la nueva prueba del usuario del 2026-11-15, posterior a `correccion_temblor_objetos_guest_2026-11-15.md`. **No se modificó la lógica del juego en esta revisión.** No se ejecutaron pruebas headless ni se inició Godot.

El trabajo propuesto se desarrolla en el [plan de refactorización y reconstrucción](plan_refactorizacion_sincronizacion_objetos.md), con etapas y condiciones de aprobación. El plan todavía no está implementado.

Se leyeron el `kavi.txt` actual y el código; se inspeccionaron cuadros del video `2026-11-15 22-42-27.mp4` (25,37 s, 1280 × 720, 30 FPS), ambos en `C:\Users\ElCaido97\Documents\otro proyecto bobo\capturas`. Las imágenes de inspección quedaron en `tmp/sync_review_20261115/`.

El usuario informa un rebote visible solo en el invitado a partir de aproximadamente 0,5 m, de amplitud aparentemente constante, y cambios de trayectoria al soltar o lanzar, caminando o quieto. **No hay grabación simultánea del host ni una traza de estados de este episodio.** No se puede atribuir cada cuadro a una corrección concreta ni tratar esos 0,5 m como un umbral confirmado del código.

## Hallazgo confirmado: dos modelos físicos distintos

| Parte | Qué hace hoy | Dónde |
| --- | --- | --- |
| Cuerpo del host | `RigidBody3D` con Jolt, formas físicas, material, gravedad y respuesta a contactos | `InvWorldItem.setup`, `begin_hold`, `end_hold`; `InvBodies` |
| Copia del invitado | Cuerpo congelado, sin formas ni capas de colisión | `InvWorldItem.setup`, rama `simulated == false` |
| Caída anticipada del invitado | Integra gravedad y amortiguación a mano y recorta el desplazamiento/giro contra el nivel | `InvHands._fall`, `InvHoldMotion.guard` |
| Corrección durante esa caída | Parte de una muestra del host, la adelanta con el mismo cálculo simplificado y reinicia el suavizado | `InvHands._predict_free` |
| Retorno a la representación remota | Cuando el host dice que duerme, o tras 120 ticks, mezcla durante 250 ms con la pose del reloj de interpolación | `InvHands._end_free`, `_place_blend`; `InvBodies.sample_at` |

La caída manual **no es el resolvedor de contactos de Jolt**. `guard` conserva el paso libre, prueba deslizar por ejes o girar y, si no, pone velocidades en cero. No reproduce la restitución, el roce y los impulsos de contacto del cuerpo real. Además usa `InvAuthority.WORLD_MASK` (`1 | 4`), que no incluye la capa de los otros objetos sueltos (`8`). El host sí resuelve esos contactos.

Por tanto, incluso con igual gravedad y un tick correctamente identificado, las dos máquinas pueden obtener apoyos, giros y trayectorias diferentes. Ajustar solamente la rapidez del suavizado no elimina esa diferencia.

## Tiempo y transición de estado

El objeto del dueño se anticipa al presente del jugador; los objetos remotos se muestran en un reloj retrasado para interpolar muestras del host. Es una distinción deliberada y útil, pero necesita un traspaso explícito.

Actualmente, tras soltar o lanzar, se suceden caída manual, correcciones adelantadas con esa misma caída manual, mezcla hacia el reloj remoto y finalmente interpolación remota. `_place_blend` usa directamente `copy.place`; no pasa por `_visual_step`, que protege los movimientos mostrados por `_show`. No existe una única regla de presentación aplicada a toda esa transición.

Además, `InvBodies.schedule_release` espera el tick pedido si todavía no se simuló. Si el pedido llega tarde y ese tick ya pasó, `InvAuthority._release` suelta el cuerpo actual: no reconstruye el estado físico del instante original de suelta. Esto puede hacer que el inicio autorizado difiera del que anticipó el invitado. Que haya una corrección después de una entrega tardía no demuestra por sí solo un fallo; hay que registrar ese estado inicial y el tick que realmente se aceptó.

**Interpretación:** el rebote aparente y la trayectoria que cambia son compatibles con estas diferencias de modelo y de traspaso. La amplitud aparentemente constante también es compatible con una corrección de apoyo o de representación. **No está demostrado cuál de esos mecanismos produjo cada rebote del video.**

## Qué no demostraban las pruebas anteriores

La prueba de la caja soltada de 2,16 m mide el primer salto y cuánto se mete el modelo debajo del piso. Su medida `sunk` solo registra penetración; no falla si el invitado sube unos centímetros después de tocarlo. Las regresiones de continuidad de la mano tampoco comparaban toda la curva de caída con la del host.

Los resultados anteriores siguen siendo evidencia de los defectos que cubren, pero no validan ausencia de rebote falso, equivalencia completa de colisiones ni una suelta en movimiento coherente entre ambas máquinas. No debe darse por resuelta esa parte por el número de comprobaciones que pasó.

## Recomendación

**Refactorización acotada de la sincronización de objetos**, conservando catálogo, cuerpos preparados, selección, inventario y la red del personaje. No incorporar otra excepción por altura ni una corrección especial para la caja.

Dos modelos posibles, con un costo de interacción diferente:

| Modelo | Beneficio | Costo |
| --- | --- | --- |
| Física únicamente en el host y representación remota coherente | Una sola respuesta física; referencia sencilla para aislar movimientos inventados por el cliente | La respuesta visible de suelta/lanzamiento espera datos del host; con latencia puede sentirse lenta |
| Host autoritativo y predicción física local con Jolt para el objeto propio | Respuesta inmediata, con un resolvedor real de contactos en la anticipación | Más implementación y costo local; el estado de otros cuerpos sigue llegando tarde y puede requerir correcciones |

**Para conservar la respuesta inmediata buscada, la segunda opción es el objetivo a prototipar.** Usar Jolt en ambos lados no garantiza resultados idénticos: predecir un contacto con un cuerpo remoto requiere decidir qué estado de ese cuerpo se usa. No se propone fingir que existe un rollback exacto del mundo ni transferir autoridad a los clientes.

El prototipo debe tener:

1. **Física, autoridad y dibujo separados.** Una sola función decide qué pose se presenta en cada estado. La pose suavizada no se reutiliza como estado físico autorizado.
2. **Estados explícitos:** réplica remota, objeto propio predicho, transición de suelta/lanzamiento y retorno a réplica. Cada muestra tiene tick y una versión del objeto que sobrevive a esos cambios; no basta una versión válida únicamente mientras se sostiene.
3. **Suelta/lanzamiento como un evento único:** identificador, tick solicitado y confirmación con el tick realmente procesado, pose y velocidades iniciales autorizadas. Definir qué se hace si llega tarde, sin aplicar dos veces el impulso ni asumir que se aceptó una pose pasada.
4. **Predicción local con física real** para el objeto propio y una política expresa para contactos con otros objetos. El host conserva la decisión final. Primero se comprueba el piso y la pared; después se prueba el contacto con otro cuerpo antes de aprobar el modelo.
5. **Un reloj de presentación por tipo de vista y una transición coherente entre ellos.** El objeto propio puede verse adelantado y los remotos retrasados; al cambiar de modalidad no se vuelve arbitrariamente a una parte anterior de la caída. Todas las rutas de presentación deben respetar el nivel.

## Cómo decidir antes de migrar

Preparar una escena mínima de referencia con una caja, piso, pared fina y un segundo cuerpo. El modo de solo host sirve como comparación; no implica reemplazar silenciosamente la respuesta inmediata del juego por una interacción con espera.

Medir ambos lados, alineados por tick y evento:

- estado y velocidades al soltar, quieto y caminando;
- alturas de 0,2, 0,5 y 1 m: primer contacto, altura posterior y cualquier rebote presente en una sola máquina;
- lanzamiento y cambio de trayectoria antes/después de un contacto real;
- paso de predicción a réplica y retorno al reposo;
- un contacto con otro cuerpo, pérdida/reorden de paquetes y recepción tardía de la suelta.

Separar el rebote físico real, una divergencia de predicción y un movimiento añadido por el dibujo. Las pruebas deben fallar ante el rebote que muestra el usuario, no solo ante penetraciones del piso. Usar corridas breves con límite externo y salida inmediata ante errores de carga; no encadenar recorridos completos mientras la hipótesis puntual siga sin comprobarse.

Este documento es un diagnóstico y una propuesta de sustitución del modelo de objetos. **La migración y el prototipo no están implementados.**
