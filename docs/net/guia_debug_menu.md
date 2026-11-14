# Guía para implementar el menú de debug

**Fecha:** 2026-11-14.

**Estado:** diseño para una implementación futura; no implementado.

**Condición para empezar:** retomar esta guía cuando Claude haya terminado el trabajo actual y el usuario pida implementar el menú. Crear este documento no autoriza a comenzar esa implementación.

## 1. Objetivo y decisiones

Reunir las herramientas de depuración del laboratorio en un panel principal que abra subpaneles. Actualmente varias funciones se agregan a teclas de función y resulta engorroso recordarlas y usarlas. El objetivo es conservar las herramientas y cambiar su acceso, con una interfaz que pueda crecer junto al proyecto.

### Acordado con el usuario

- Dejar una sola tecla de acceso al conjunto de herramientas de debug y retirar los accesos dispersos que se migren al panel.
- Un panel principal desde el que desplegar subpaneles.
- Usar como referencia visual las capturas indicadas en la sección 3: apariencia técnica, oscura y compacta, asociada a Dear ImGui.
- Preparar primero esta guía; implementar después de que termine el trabajo actual de Claude.
- Se puede utilizar Dear ImGui o una solución propia. El usuario no impuso una biblioteca.

### Base propuesta para implementar

Estas son recomendaciones de esta guía, no decisiones adicionales atribuidas al usuario:

- Usar F1 como valor inicial para una acción configurable `debug_menu_toggle`.
- Subpaneles movibles, redimensionables y plegables, con varias ventanas abiertas simultáneamente.
- Recordar ventanas abiertas, posiciones y tamaños. Un buscador filtra herramientas por nombre y categoría.
- Mantener la simulación en marcha al abrir el menú; la pausa es una herramienta explícita disponible solo donde ya sea válida.
- Preferir Dear ImGui mediante una integración para Godot si supera la comprobación de compatibilidad y exportación. Alternativa: interfaz nativa de Godot con un tema equivalente.
- Guardar la disposición de la interfaz, pero no reactivar automáticamente operaciones de debug que alteren la simulación al iniciar otra partida.

## 2. Cómo retomar sin pisar el trabajo en curso

Este documento se preparó en la rama `net-lab-auditoria-hitbox`, con HEAD `3fbd594` y numerosos cambios locales de objetos dinámicos, física, interacción y opciones. Es una referencia temporal, no una rama o un commit al que haya que volver.

Antes de implementar:

1. Leer las instrucciones aplicables, revisar rama, HEAD, estado y cambios locales. Conservar todo trabajo existente; no hacer reset, limpieza, checkout ni restauraciones para volver a esta foto.
2. Empezar por [guia_del_laboratorio.md](guia_del_laboratorio.md), seguir con [inventario_de_grilla.md](inventario_de_grilla.md) y [hud_salud_estamina_y_estados.md](hud_salud_estamina_y_estados.md). Consultar [arquitectura_coop_y_esqueleto_de_red.md](arquitectura_coop_y_esqueleto_de_red.md) como historial, distinguiendo versiones anteriores de decisiones vigentes.
3. Revisar el resultado real del trabajo de objetos dinámicos. [prompt_claude_objetos_dinamicos.md](prompt_claude_objetos_dinamicos.md) explica el pedido, pero no prueba qué quedó implementado.
4. Rehacer el inventario de accesos de la sección 5 sobre el código terminado. Buscar tanto constantes `KEY_F*` como acciones del Input Map, comprobaciones directas de `Input`, botones, textos de ayuda y pruebas que simulan teclas.
5. Usar la versión efectiva de Godot, el renderizador y las plataformas del proyecto. Al preparar la guía, `project.godot` declara la línea 4.7 y Forward Plus; eso no identifica por sí solo la versión exacta del ejecutable utilizado.
6. Trabajar sobre el laboratorio vigente. No migrar el juego anterior ni recuperar automáticamente herramientas de `archive/`.

## 3. Referencias visuales

Carpeta proporcionada por el usuario:

`C:\Users\ElCaido97\Documents\otro proyecto bobo\capturas\resources\debugmenu`

| Referencia | Qué tomar de ella |
| --- | --- |
| `817-1702837676-1094207919.webp`, `817-1702837677-1119713764.webp`, `817-1702837682-1895546358.webp`, `817-1702837687-2081945081.webp` | Menú de GTA: categorías claras, controles directos, listas, secciones plegables, selectores y edición de valores. |
| `debug_aircraft_ap_window.png`, `debug_sim_info_window.png`, `debug_drag_window.png` | Ventanas técnicas con valores vivos y controles junto a las mediciones. |
| `debug_overlay_custom_views.webp`, `debug_overlay_memory.webp`, `images.jpg` | Varias ventanas sobre el juego, organización por sistema y gráficos de diagnóstico. |
| `debug_aircraft_interactive_overlay.png`, `debug_aircraft_lights.png`, `debug_pitch.png`, `debug_shadowmap.png`, `debug_simdimensions.png`, `debug_simforces.png` | Visualizaciones en el mundo: puntos, cajas, ejes, etiquetas y vectores, activables por separado. |

La carpeta es externa al repositorio. Abrir las imágenes antes de usarlas; si no están disponibles, usar esta descripción e informar la limitación. No asumir que otro agente conoce las capturas por haber participado en esta conversación.

Apariencia buscada: fondo negro o gris muy oscuro, transparencia moderada, cabeceras y controles azules, texto claro, bordes discretos y geometría rectangular. Tipografía compacta y legible; monoespaciada para valores cuando ayude. Evitar animaciones y decoración que dificulten leer o manipular herramientas. Ajustar escala para 1280 × 720 y 1600 × 900; no copiar el tamaño desproporcionado del menú de GTA.

Las referencias no implican implementar todas sus herramientas ni confirmar qué biblioteca usa cada juego. Dear ImGui es una biblioteca; su modelo de interfaz inmediata no es el nombre de una estética.

## 4. Elección técnica

Fuentes de partida consultadas al preparar la guía:

- Dear ImGui: <https://github.com/ocornut/imgui>
- Integración candidata para Godot: <https://github.com/pkdawson/imgui-godot>
- Documentación de la integración: <https://github.com/pkdawson/imgui-godot/wiki>

La integración candidata documenta soporte para GDScript mediante GDExtension. No hace falta convertir el proyecto a C++ o C#. La disponibilidad actual de un repositorio no garantiza que cualquier versión de sus binarios funcione con la versión futura del proyecto.

### Comprobación previa

Antes de adoptar la dependencia, hacer una prueba mínima aislada del proyecto principal: abrir una ventana desde GDScript, editar un valor, usar varias ventanas y comprobar entrada de mouse/teclado, escala y persistencia de disposición. Exportar para Windows x86_64 con la versión y el renderizador reales, y ejecutar sin el editor en otra PC cuando esté disponible.

Revisar mantenimiento, licencia, versiones de Godot admitidas, binarios para las plataformas necesarias, comportamiento en exportación y cómo excluir la interfaz de una entrega sin debug. Registrar versión o commit elegido, origen, instalación y actualizaciones; no depender de descargar lo último en cada ejecución.

| Opción | Beneficio | Costo que hay que comprobar |
| --- | --- | --- |
| Dear ImGui con integración para Godot | Controles y ventanas orientados a herramientas; apariencia cercana a las referencias. | Dependencia nativa, compatibilidad, entrada de eventos y empaquetado/exportación. |
| Controles nativos de Godot con tema propio | Integración con los controles existentes y sin esa dependencia nativa adicional. | Construir y mantener gestión de ventanas, disposición y presentación técnica equivalente. |

Preferencia inicial: Dear ImGui si la prueba resulta satisfactoria. Si falla por compatibilidad o costo de integración, documentar la evidencia y usar la alternativa nativa manteniendo el diseño funcional. No actualizar el motor ni cambiar el lenguaje del juego para forzar esta elección.

No agregar autoloads de lógica del juego para resolver el menú. Revisar si la integración necesita su propio bootstrap/autoload técnico y documentarlo por separado; eso no justifica convertir los sistemas de juego en singletons.

## 5. Inventario inicial y migración de accesos

Esta tabla procede de una inspección parcial del árbol local el 2026-11-14. Revalidarla y ampliarla después del trabajo pendiente. No describe una migración ya realizada.

| Acceso observado | Comportamiento actual | Destino propuesto |
| --- | --- | --- |
| F1, lectura directa en `net_lab.gd` | Muestra/oculta el panel de información. | F1 abre/cierra el conjunto. La información pasa a un subpanel. |
| F2, lectura directa en `net_lab.gd` | Activa/desactiva adopción; solo host. | Red → Adopción, con estado visible y misma restricción. |
| F3, acción `opciones` | Abre `LabOptions`, preferencias de manipulación y prueba de botones del mouse. | Entrada Opciones desde el panel principal; retirar F3. Conservar acceso desde el menú normal del laboratorio y preferencias existentes. |
| F12, acción `captura` | Guarda una captura en el Escritorio. | Capturas → Capturar; retirar el atajo al cumplir el objetivo de una sola F. Conservar destino y notificación. |
| G y F, acciones `toggle_debug_freeze` y `avanzar_tick` | Pausa y avance de simulación; solo modo local. | Simulación → Pausa / Avanzar un tick, con las mismas condiciones. |
| Alt + 1 a 5 | Presets de simulación de red de esta máquina. | Red → Simular internet. Retirar atajos de depuración migrados. |
| Y / U, con Shift para variante débil | Empujones de prueba; solo host. | Red/Pruebas → Empujones, conservando variantes y restricciones. |

No retirar controles jugables por parecer herramientas: WASD, salto, inventario, interacción, barra rápida, selector de habilidades, poderes y controles de cámara/manipulación mantienen su comportamiento. Clasificar cualquier acceso nuevo según su función antes de migrarlo. F5/F6/F8 del editor de Godot no son atajos del menú del juego y no se modifican.

`LabOptions` contiene preferencias del jugador: debe seguir disponible en una exportación sin herramientas de debug. El panel principal puede abrirlo; no duplicar sus datos ni convertir su acceso normal en una dependencia de ImGui. Revisar si alguna parte, como la prueba de botones, conviene mantener allí o exponer también en diagnóstico.

Para capturas sin interfaz, el botón debe programar la captura después de ocultar el conjunto y esperar un cuadro renderizado; si se ofrece demora, debe poder cancelarse. La restauración del menú no debe aparecer en la imagen ni alterar la selección de ventanas. Dar opciones claras de captura con/sin debug. No dejar F12 oculto como excepción por iniciativa propia.

Al retirar un acceso, actualizar Input Map cuando corresponda, handlers, etiquetas y pruebas. `scenes/net_lab/selector_test.gd` contiene pulsaciones de F2 en la foto inicial: revisar la intención de esa prueba y adaptarla, sin perder la cobertura de adopción. No quitar funciones hasta que estén disponibles y verificadas desde su nuevo control.

## 6. Panel principal y alcance inicial

El panel principal muestra categorías, herramientas disponibles y un buscador. Cada entrada abre o enfoca su subpanel; una segunda apertura no crea duplicados. Cerrar un subpanel lo oculta, sin borrar su configuración. La tecla global oculta todo el conjunto y al reabrir recupera la distribución; no apaga modos de debug activos silenciosamente.

| Categoría propuesta | Primera entrega | Ampliaciones posteriores |
| --- | --- | --- |
| Información y rendimiento | Datos útiles ya mostrados por el panel actual; indicadores de herramientas activas. | Gráficos históricos y mediciones por sistema. |
| Simulación | Pausa y avance de tick existentes. | Otras herramientas justificadas por pruebas reales. |
| Red | Adopción, presets y empujones existentes; rol y estado de conexión. | Inspección adicional de sincronización. |
| Objetos e interacción | Exponer herramientas de debug que realmente existan al retomar. | Inspección de objetos, cuerpos, contactos y visualizaciones espaciales. |
| Jugador | Exponer controles de prueba existentes, si los hay. | Herramientas de salud, partes, estamina y movimiento. |
| Capturas | Función actual, con y sin debug. | Exportación de diagnósticos. |
| Opciones | Abrir preferencias existentes. | Configuración de escala y disposición del debug. |
| Mundo/renderizado | Incorporar solo controles existentes y comprobados, si los hay. | Iluminación, ambiente y vistas de diagnóstico. |

La primera entrega debe resolver la centralización. No crear nuevos editores de objetos, herramientas de renderizado, protocolos de trucos, daño, teletransporte ni un profiler completo solo para llenar categorías. Ocultar categorías vacías o indicar con claridad su indisponibilidad. El creador de objetos del editor (`addons/inventario_objetos/`) sigue cumpliendo su función; no trasladarlo entero al menú en ejecución.

## 7. Estructura y conexión con los sistemas

Usar un nodo/escena de debug perteneciente al laboratorio, creado y destruido con él. Separar coordinación del menú, presentación de cada panel y operaciones del sistema correspondiente. No concentrar toda la lógica en `net_lab.gd` ni en un archivo gigantesco de interfaz.

Cada módulo aporta sus herramientas mediante un registro explícito y referencias inyectadas. Un contrato mínimo identifica herramienta/panel, categoría, nombre visible, disponibilidad, alcance y operación o lectura que expone. Las identidades deben ser estables para buscar y guardar disposición. Al salir un módulo, retirar sus entradas y conexiones sin referencias colgantes. Evitar descubrir todos los nodos por cuadro o construir un framework genérico innecesario.

Los botones llaman operaciones semánticas compartidas con las pruebas; no fabrican pulsaciones de F2, F3, etc. Las lecturas muestran el estado real y las escrituras pasan por validación. Abrir una ventana no debe ejecutar acciones, generar objetos ni cambiar parámetros.

Cuando no hay partida, actor u objeto válido, mostrar el motivo o deshabilitar el control. Al destruir un objeto seleccionado, desconectarse o reiniciar el laboratorio, invalidar la selección. En cooperativo, distinguir identificador de objeto/actor de referencias locales de nodos.

Separar valor actual, valor inicial de la sesión y valor por defecto cuando se ofrezca restablecer. Modificar valores en ejecución no debe escribir `.tscn`, `.tres` ni `project.godot`. No habilitar edición en caliente de todo el Tuning sin revisar su efecto en simulación, huellas de compatibilidad, predicción y red.

## 8. Entrada, foco y convivencia con otras interfaces

Reutilizar el mecanismo vigente de propiedad del mouse. En la foto inicial `LabCamera` dispone de `hold_mouse(holder)` y `release_mouse(holder)`, utilizados por `LabOptions`; las manos tienen bloqueadores de interfaz. Revalidar estos mecanismos al empezar.

- Abrir el debug solicita el mouse y detiene el giro de cámara por mouse. Cerrarlo libera únicamente su solicitud: no capturar el cursor si inventario, opciones u otra interfaz aún lo necesitan.
- Los clics, rueda, arrastres y atajos consumidos por el debug no recogen, sueltan, lanzan, rotan objetos ni mueven la cámara accidentalmente. Comprobar tanto eventos como consultas continuas con `Input`.
- Propuesta inicial: permitir caminar cuando ningún campo de edición tiene el foco, como en el inventario; al escribir o arrastrar un valor, bloquear entradas jugables que se solapen. Mantener el envío de estado neutro y liberaciones necesarias para no dejar movimientos o botones trabados.
- Si hay un objeto sostenido, reutilizar la política final de las manos al abrir una interfaz. El borrador de `LabOptions` lo suelta sin lanzar; no inventar una segunda política que deje al host y al cliente en estados distintos.
- Esc resuelve primero el popup o la edición activa del debug y después cierra el conjunto cuando corresponda. Consumirlo una sola vez; no cerrar simultáneamente inventario u opciones ni activar otras acciones.
- La tecla global se procesa una vez por pulsación, sin repetición automática. No se introduce como texto en un campo. La acción debe ser reconfigurable sin hardcodear F1 en cada panel.
- Al perder foco de la aplicación, cerrar la escena o desconectarse, limpiar captura y estados pendientes. Cerrar una ventana no debe dejar bloqueados los controles.

La UI debe seguir respondiendo cuando la simulación local esté congelada y bajo cámara lenta. No confundir la pausa del reloj actual con pausar indiscriminadamente todo el árbol. Definir qué pasa si se abren inventario, Opciones o el selector Q mientras se interactúa con debug, y comprobarlo sin romper sus gestos existentes.

## 9. Cooperativo y exportaciones

La disposición, el buscador y la visibilidad del debug son locales a cada PC. No replicarlos. Mostrar el alcance de cada herramienta: presentación local, simulación local o operación del host.

Conservar reglas actuales: adopción y empujones son del host; pausa y avance de tick son del modo local; la simulación de conexión se configura por máquina. Deshabilitar el botón de un cliente no sustituye la validación en la operación. No añadir una vía de escritura directa al estado autoritativo para facilitar la interfaz.

No diseñar un protocolo remoto nuevo para comandos futuros. Si se exponen operaciones que ya viajan por red, usar el camino vigente con sus validaciones, identidad y resultado. Ante rechazo del host, mostrar el resultado real sin dejar un control que aparente éxito.

Separar habilitación de herramientas de debug de la compilación con depuración del motor. El laboratorio actual se exporta también sin marcar **Export With Debug**: `OS.is_debug_build()` por sí solo no representa la intención de tener herramientas en ese laboratorio. Elegir y documentar una política explícita para:

1. Laboratorio de desarrollo/pruebas con herramientas habilitadas, incluido su `.exe` exportado.
2. Exportación sin herramientas: no crear el menú ni sus accesos; excluir la dependencia de UI cuando la integración lo permita y verificar ausencia de errores por clases o recursos faltantes.

Preservar Opciones de usuario en ambas variantes. No cambiar el protocolo o las huellas de compatibilidad inadvertidamente al incluir/excluir debug. Probar los pares de exportaciones que se declaren compatibles.

## 10. Persistencia y costo

Guardar preferencias de interfaz en `user://`, usando el mecanismo existente si resulta adecuado. Incluir una versión de formato, identidades de panel, geometría, escala y selección de ventanas abiertas. No persistir referencias de nodos ni selecciones inválidas de partidas anteriores. Validar los datos y recuperar una disposición utilizable ante un archivo roto o un monitor/resolución diferente. Ofrecer **Restablecer disposición** desde el panel principal.

No guardar como preferencias cambios de adopción, pausa, salud, inventario o física. No duplicar ni borrar el archivo de preferencias de manipulación ya creado por el sistema de opciones.

Con el menú oculto, suspender lecturas costosas, series históricas y visualizaciones que no sean necesarias; ocultar la interfaz no debe apagar silenciosamente una simulación de red que ya se activó. Con ventanas cerradas, no recorrer objetos para preparar información invisible. Mantener buffers de gráficos limitados y frecuencia de muestreo separada de la simulación. Los tiempos reales de diagnóstico no deben deformarse por `Engine.time_scale`.

Medir con la misma escena y condiciones: debug deshabilitado, habilitado pero cerrado y con paneles abiertos. Informar impacto en tiempo por cuadro y memoria sin inventar objetivos absolutos. Limpiar señales, buffers y recursos al terminar la escena.

## 11. Orden de implementación futura

1. **Reconstruir el estado:** terminar/revisar trabajo previo, inventariar accesos y registrar qué funciones se migrarán, preservarán o quedarán fuera.
2. **Elegir integración:** realizar la prueba aislada de la sección 4 y dejar registrada la decisión y versión.
3. **Crear la estructura mínima:** una acción de apertura, panel principal, registro y un subpanel de información; integrar cursor, foco, cierre y recuperación de disposición.
4. **Migrar por sistema:** conectar operaciones existentes, comprobar equivalencia y después retirar cada acceso anterior, sus ayudas y dependencias de pruebas. Incorporar Opciones sin duplicar sus preferencias.
5. **Completar uso diario:** búsqueda, escala, ventanas múltiples, restablecimiento y capturas con/sin interfaz.
6. **Verificar local y red:** ejecutar pruebas relevantes, revisar rendimiento y probar las variantes exportadas. Corregir fallos antes de ampliar herramientas.
7. **Actualizar documentación:** esta guía pasa de diseño a estado implementado con archivos y pasos reales; actualizar `guia_del_laboratorio.md`, tabla de teclas y documentación de sistemas afectados. No describir una prueba pendiente como superada.

No hacer commit, push ni publicación por iniciativa propia. Entregar cambios y evidencia de las verificaciones, distinguiendo lo automático de lo que todavía requiere una prueba manual.

## 12. Criterios de aceptación

| Comprobación | Resultado requerido |
| --- | --- |
| Una tecla de debug | Abre/cierra el conjunto. Las antiguas teclas migradas dejan de activar funciones por detrás. Los controles jugables siguen funcionando. |
| Navegación | Desde el panel principal se llega a todas las herramientas migradas. Buscar una herramienta permite abrirla o enfocarla sin duplicar su ventana. |
| Ventanas | Varias abiertas, movimiento, tamaño, plegado, cierre y reapertura correctos; utilizables a 1280 × 720 y 1600 × 900. |
| Persistencia | Restauración tras reiniciar, recuperación ante datos dañados o ventanas fuera de pantalla y restablecimiento accesible. Ningún truco se reactiva automáticamente. |
| Entrada | Editar textos/números y usar rueda/clics no dispara juego ni cámara. No quedan teclas sostenidas ni el mouse atrapado; Esc no se procesa dos veces. |
| Interfaces existentes | Inventario, contenedores, arrastre de consumibles a partes, opciones, selector Q y manipulación física conservan su comportamiento y propiedad del mouse. |
| Simulación | Abrir no pausa. Pausa/avance existentes funcionan solo donde corresponda; la UI responde congelada y bajo cámara lenta. |
| Cooperativo | Dos jugadores abren/cambian ventanas independientemente; restricciones verificadas en la operación, no solo en botones. Selecciones inválidas y desconexión se recuperan sin errores. |
| Capturas | Con/sin debug, archivo y aviso correctos, sin restauración prematura de ventanas ni acceso obligatorio a F12. |
| Exportación | Laboratorio exportado con herramientas funciona fuera del editor. Variante sin herramientas arranca y conserva Opciones sin referencias rotas. |
| Rendimiento y limpieza | Comparación medida abierto/cerrado/deshabilitado; sin crecimiento ilimitado ni recursos/conexiones duplicados al reiniciar la escena. |
| Documentación y pruebas | Tabla de teclas y ayudas actualizadas. Pruebas anteriores adaptadas; comprobaciones significativas de entrada, disponibilidad, permisos y ciclo de vida. |

La implementación estará completa cuando la centralización sea utilizable y conserve el comportamiento de las funciones migradas, no cuando solo exista una ventana con la apariencia de las referencias.
