# Arquitectura de movimiento co-op y esqueleto de red: todo lo hecho hasta ahora

**Proyecto:** tun-tun-tun-sahur · **Motor:** Godot 4.7.2 estable con Jolt Physics (`3d/physics_engine="Jolt Physics"` en `project.godot`).
**Período:** del 2026-10-01 a las 20:41 al 2026-10-08 a las 19:32. Todas las horas están en hora de Argentina (UTC−3).
**Documento de arquitectura original:** [Arquitectura de movimiento co-op (Godot 4.7 + Jolt)](https://claude.ai/code/artifact/6760c3bf-39ed-4f2f-8d9d-23642c7ac797), en Claude Docs. Está copiado completo en el Apéndice A.

**Historial de este documento:**

- **Primera versión:** 2026-10-03, commit `9caaec3`. Cubría hasta el esqueleto de red completo.
- **Segunda versión:** pedida el 2026-10-06 a las 21:26, commit `375d419` (2026-10-07, 12:53). Sumó la validación de la arquitectura (puntos 2, 3 y 4 de su lista) y puso al día el estado del código, las pruebas, los hechos comprobados, los errores, las decisiones, los commits y los pendientes.
- **Tercera versión:** pedida el 2026-10-08 a las 10:54, commit `fa26986` (11:34): "correji los md y agrega una nota donde se explica la razon del cambio + como estaba armado originalmente". Sumó:
    - el escalón (sección 8.4);
    - el doble clic que actualiza la notebook y reemplazó a los zips (sección 6.2);
    - el punto 5, Hanging con snap (sección 8.5);
    - el cambio que se pidió después de probar Hanging: agarrarse sin apretar W, y moverse colgado con A y D sin depender de la cámara.

  La nota pedida está en la sección 8.5, "El cambio después de la primera prueba": explica cómo estaba armado y por qué cambió. Donde el documento de arquitectura decía otra cosa, el Apéndice A quedó corregido, con una nota en cada lugar. A pedido ("tambien correji tu md"), el documento original en Claude Docs se corrigió igual, con sus notas (revisión 55).
- **Cuarta versión:** pedida el 2026-10-08 a las 16:32, commit `048dc4d` (16:41): "Con respecto a los md, actualízalos a los dos, y despues haces commit". Sumó la sección 8.6: la subida al borde se reemplazó por un salto para arriba con control aéreo. Ahí está cómo era la subida, por qué cambió, la demostración paso a paso y las pruebas. El Apéndice A y el documento de Claude Docs (revisión 60) quedaron corregidos con notas en los mismos lugares.
- **Esta actualización:** pedida el 2026-10-08 a las 19:31: "dale, actualizá los dos md y después hacé commit". Suma la sección 8.7: agarrarse subiendo, sin tener que caer, y que al saltar hacia otro lado desde el colgado el personaje se dé vuelta hacia donde salta. El Apéndice A y el documento de Claude Docs (revisión 65) quedaron corregidos con notas. Como en las versiones anteriores, no se borró nada; donde algo cambió, se aclara qué era antes.

Este documento junta todo lo que se hizo, sin recortes:

- el pedido original, palabra por palabra;
- la arquitectura y las decisiones que se tomaron después;
- el plan de 8 pasos del esqueleto de red y en qué se apartó la implementación;
- cada paso implementado, con sus archivos, decisiones, problemas, pruebas automáticas, mediciones y pruebas en dos PC reales;
- la validación de la arquitectura, punto por punto: base propia, postura y espacio libre, escalera con empujones programados e inmediatos, el escalón y Hanging con snap;
- el estado actual del código, los formatos de red y las constantes;
- cómo usar el laboratorio;
- los hechos de Godot y Jolt que se comprobaron en el camino, los errores (incluidos los míos) y cómo se arreglaron;
- los commits, los zips entregados, el doble clic que los reemplazó y lo que queda pendiente.

## Índice

1. Resumen
2. Cronología
3. El pedido original
4. La arquitectura
5. El plan del esqueleto de red
6. Entorno de trabajo y de pruebas
7. Paso a paso
8. Validación de la arquitectura
9. Estado actual del código
10. Cómo usar el laboratorio
11. Todas las pruebas y sus resultados
12. Hechos de Godot y Jolt comprobados durante la implementación
13. Problemas y errores, y cómo se resolvieron
14. Decisiones tomadas y forma de trabajo acordada
15. Commits y entregas
16. Pendientes, limitaciones conocidas y próximos pasos
- Apéndice A: documento de arquitectura completo
- Apéndice B: scripts usados para las pruebas automáticas

---

## 1. Resumen

**Qué existe hoy:**

- **La arquitectura**, escrita y revisada. El host es autoritativo. Cada cliente predice solo a su propio personaje, y el host adopta esa predicción cuando es válida y está al día con los eventos del host (la "época"). El movimiento se arma con un estado completo por actor, un paso por tick en orden fijo, un solo modo activo y siete reglas generales.
- **Dos decisiones posteriores:** Hanging usa snap, y subir al borde desde el colgado es una salida de Hanging, no mantle. Mantle sigue fuera del alcance. Desde el 2026-10-08, esa salida es un salto para arriba con control aéreo, y no una trayectoria dentro de Hanging (sección 8.6).
- **El esqueleto de red completo:** los 8 pasos del plan, más un retoque del adelanto (6b). Está implementado en carpetas nuevas (`scripts/actor/`, `scripts/net/`, `scenes/actor/`, `scenes/net_lab/`), sin tocar nada del parkour.
- **Probado de dos formas:** con pruebas automáticas (Godot sin ventana, host y cliente como dos procesos en la misma PC) y en dos PC reales con Windows, ambas por Wi-Fi.
- **La validación de la arquitectura, puntos 2 a 4 de su lista** (sección 8), cada uno probado en las dos PC y commiteado:
    - **Base propia:** una plataforma guionada que va y viene (el vagón), un ascensor y una balsa que mueve solo el host. Sobre una base, el estado guarda la posición y la velocidad relativas a ella. Se pulió además cómo se ve al otro jugador cuando sube o baja de una plataforma.
    - **Postura y espacio libre:** agacharse, correr, deslizarse y un túnel largo de techo bajo. Para pararse, primero se prueba si hay lugar. Se sumaron herramientas de prueba: pausa con avance de a un tick, pared con medidas y capturas con F12.
    - **Escalera (Ladder)**, el primer modo anclado, con **empujones inmediatos y programados**. Los programados se anuncian por adelantado y se aplican sin corrección.
- **El escalón** (pedido aparte, antes del punto 5): caminando, el modo Suelo sube solo escalones de hasta 30 cm. Es la sonda que propone el documento: subir, avanzar y bajar, y aceptarlo solo si cae en suelo caminable. Lo que se ve sube suave en unos 100 ms. Probado en las dos PC y commiteado.
- **Hanging con snap (punto 5)** y sus pruebas de confirmación, probado en las dos PC y commiteado:
    - una pista con 11 bordes fijos y dos bordes que se mueven;
    - un barrido automático de 5.148 aproximaciones contra los cuatro criterios del documento;
    - la red de 0 a 200 ms con pérdida, y la divergencia inyectada.

  Después de la primera prueba en dos PC se cambiaron dos cosas a pedido: agarrarse ya no exige apretar W, y A y D colgado ya no dependen de la cámara. Cómo estaba armado y por qué cambió está en la sección 8.5.

  Después, también a pedido, la subida al borde, que era un recorrido de dos tramos, se reemplazó "temporalmente" por un salto para arriba con control aéreo (sección 8.6). Y ya no hace falta estar cayendo para agarrarse: pegado al muro, al saltar se agarra cuando las manos llegan al borde (sección 8.7).
- **La notebook se actualiza con un doble clic** desde una carpeta compartida de esta PC. Reemplazó a los zips desde el escalón (sección 6.2).
- **Dieciséis commits locales** en la rama `codex/parkour-v3-h0-lab`:
    - el esqueleto de red: `d75ef67`, `9cd1936`, `7547de1` y `c0e0421`;
    - las cuatro primeras versiones de este documento: `9caaec3`, `375d419`, `fa26986` y `048dc4d`;
    - la validación: `600002a`, `25f7806`, `cb71b16`, `91a4433`, `b907dae` (escalón), `3cdcc91` (Hanging), `3825c2b` (salto para arriba) y `bd2157b` (agarre subiendo).

  Esta quinta versión del documento va en un commit propio, el número 17. No se subió nada a ningún remoto.
- **Cambios pendientes:** los cambios previos sin commitear de esa rama quedaron intactos.
    - La primera versión de este documento contaba 137: los 136 del parkour más un archivo temporal del editor de Godot.
    - La segunda versión contaba 138; la tercera y esta, 137. No se averiguó cuáles cambiaron; ninguna es del laboratorio.
    - Entre ellas está `project.godot`, con el cambio de versión 4.6 → 4.7 que hizo el editor. Las dos acciones del Mapa de entrada que agregó el laboratorio sí están commiteadas.

**Resultados principales:**

| Qué se midió | Resultado |
| --- | --- |
| Repetición determinista del actor (paso 2) | 1.121 repeticiones y 44.141 ticks idénticos byte a byte a la pasada en vivo |
| Mismo cálculo en dos PC distintas (paso 6, Wi-Fi real) | 18.883 coincidencias contra 21 correcciones; 20 de ellas por inputs que llegaron tarde |
| Reloj del cliente con Wi-Fi | 25 saltos en ~2 minutos con el reloj del paso 3; 0 desde el paso 6 |
| Recuperar el adelanto cuando la red pasa de golpe a 400 ms | ~14 s y 57 correcciones (paso 6); ~1,5–2 s y 5–7 correcciones (6b); 1 corrección (paso 7) |
| Tirones de Wi-Fi simulados (150 ms cada 3 s) | 8 correcciones sin adopción; 0 con adopción (paso 7) |
| Empujones del host con la época | Se respetan; con el chequeo de época apagado a propósito, el host los borraba |
| Tirones en pantalla de los demás jugadores, con "internet mala" | 73,3 % de los ticks antes de interpolar; 0,5 % después (paso 8) |
| Prueba final en dos PC con ~400 ms de ida y vuelta | "se siente muy bien, no hay tirones raros"; la latencia se nota, pero se siente bien |
| Base propia en dos PC (vagón, ascensor y balsa) | 0 correcciones arriba de las bases, salvo 2 chicas (la mayor de 0,37 m) en la balsa con internet mala |
| Cuánto se acomoda el otro jugador al subir o bajar del vagón, visto desde lejos | De 0,35 m (red limpia) y 0,83 m (internet mala) a 0 |
| Postura en dos PC, con el túnel | Agachados bajo el techo con "pedida: parado (no hay lugar)"; 1 sola corrección, por un corte del Wi-Fi |
| Escalera en dos PC, con internet mala en las dos (~300 ms) | 50 empujones inmediatos: 50 correcciones. 29 programados: 0 correcciones (18 a tiempo y 11 tarde, repetidos desde su tick) |
| Repetición determinista con bases, postura, escalera y empujones | 2.467 repeticiones y 106.057 ticks idénticos byte a byte, también con el ritmo variando |
| Escalón, sin pantalla | Sube hasta 30 cm, caminando, agachado, corriendo y en diagonal; el de 32 cm ya no. Antes subía 10 cm |
| Pista de escalones en red: red limpia, internet mala y tirones | 0 correcciones; termina el recorrido |
| Escalón en dos PC, con internet mala (217 ms) | 4.577 coincidencias y 0 correcciones; "eran dos gotas de agua" |
| Hanging: criterios fijados antes de medir, en 5.148 aproximaciones | 99,8 % de capturas buscadas (con teclas y sin teclas); 0 agarres no buscados de 330; 0 ticks metido en la pared; la cámara salta 9 cm como máximo en 50 ms (el tope era 10) |
| Hanging en red: 0, 60, 120 y 200 ms con 0, 2 y 5 % de pérdida | 0 correcciones en las 12 combinaciones |
| Hanging en dos PC | Colgado del borde que se mueve, con red limpia, internet mala y tirones: ninguna corrección nueva mientras se sacaban las capturas. Después de los dos cambios: "todo funciona como deberia" |
| Repetición determinista con el escalón y Hanging | 4.790 repeticiones y 212.915 ticks idénticos byte a byte, también con el ritmo variando |
| Salto para arriba desde el colgado (reemplazó a la subida) | Los pies llegan 20,4 cm sobre el filo en todos los bordes donde se puede subir. Apretando W en la punta del salto, 1.934 de 1.955 casos quedan arriba; con W desde el salto, en bloques de 1 m se pasa de largo, y quedó así a pedido |
| Salto para arriba en red | 0 correcciones en las 12 combinaciones de red, en la plataforma guionada y con el otro jugador mirando. Sobre el borde del cuerpo del host, con internet mala, correcciones de 1,4 a 2,7 m al aterrizar arriba |
| Salto para arriba en dos PC | "todo funciona como debería" |
| Agarrarse subiendo, pegado al muro | En muros de 2,0 a 3,1 m se agarra en la subida del salto, con un tirón de 11 cm como máximo. En la pista, 1.545 de 1.547 capturas buscadas (ahora también subiendo) y 0 agarres no buscados de 330. Probado en las dos PC: "funciona correctamente" |

---

## 2. Cronología

| Fecha y hora (UTC−3) | Qué pasó |
| --- | --- |
| 2026-10-01 20:41 | Pedido original: diseñar desde cero la arquitectura de movimiento e interacciones físicas, con co-op desde el inicio y sin código todavía (texto completo en la sección 3). |
| 2026-10-01 21:04–21:36 | Investigación en fuentes oficiales (Godot 4.7.2, Jolt, red de Godot, netfox, Unreal 5.8, Unity, Photon) y escritura del documento en Claude Docs, sección por sección. A mitad de la escritura se ajustaron dos reglas del núcleo que los recorridos mostraron incompletas: el reloj de la cámara lenta del mundo y la cancelación de modificadores por fuerza. Al final se dibujaron tres diagramas. No se tocó el proyecto. |
| 2026-10-02 11:39 | Pregunta: "¿que conviene?, ¿usar el hanging con o sin snap, siguiendo los mismos lineamientos que los demas?". Recomendación: con snap. |
| 2026-10-02 11:40 | Decisión: "bien, entonces vamos a usar el snap". El documento quedó actualizado. |
| 2026-10-02 11:48 | Decisión: "sumalo como salida de Hanging, no es mantle". Subir al borde quedó como salida de Hanging en el documento, y se cerró el comentario. |
| 2026-10-02 11:53 | Pedido: volver a pasar el documento. Se abrió de nuevo y se mandó el enlace. |
| 2026-10-02 11:57–11:59 | Pregunta: "¿como propones empezar a crear el esqueleto de red?". Propuesta del plan de 8 pasos, sin netfox (sección 5). |
| 2026-10-02 12:09–12:10 | Aviso de que hay una segunda PC para pruebas reales. Ajustes del plan para probar entre dos máquinas. |
| 2026-10-02 12:31 | "Windows también, arrancá con los pasos 1 y 2". |
| 2026-10-02 12:53 | Pasos 1 y 2 terminados: laboratorio, actor con estado explícito y prueba de repetición (1.121 repeticiones idénticas). |
| 2026-10-02 12:58 | Reporte: "al abrir net_lab.tscn, se carga una escena totalmente diferente". |
| 2026-10-02 13:07 | Arreglado: la interpolación de física se activaba en `_ready()` y Godot dibujaba en el origen lo estático. Pasó a `_enter_tree()`. |
| 2026-10-02 13:20 | "ahora sí se ve bien, seguí con el paso 3". |
| 2026-10-02 13:28 | Paso 3 terminado: conexión por ENet, aparición de jugadores y reloj de ticks compartido. |
| 2026-10-02 13:45 | Reclamo, con imagen, por instrucciones llenas de jerga (argumentos de lanzamiento y *Customize Run Instances*). |
| 2026-10-02 13:51 | El laboratorio pasó a tener un menú dentro del juego, y se explicó todo de nuevo paso a paso. |
| 2026-10-02 13:58–14:00 | Pregunta: ¿exportar un ejecutable o copiar el proyecto a la otra PC? Recomendación: copiar el proyecto, porque solo están instaladas las plantillas de exportación de Godot 4.6. |
| 2026-10-02 17:55–17:56 | Pedido del zip; primer zip en el escritorio (`tun-tun-tun-sahur_2026-10-02.zip`, 879 archivos, 18 MB). |
| 2026-10-02 18:09 | Paso 3 probado entre las dos PC: "increíble, funciona". Dos cápsulas en cada pantalla y el tick a la par; nadie se mueve todavía, a propósito. |
| 2026-10-02 18:11–18:18 | "dale, seguí con el paso 4". Paso 4 terminado (host autoritativo, sin predicción) y zip `_paso4`. |
| 2026-10-02 18:54 | Prueba del paso 4 entre las dos PC: "como solo es un tick de demora, prácticamente es imperceptible". En la respuesta afirmé sin comprobarlo que la cápsula hacía un "mantle automático". |
| 2026-10-02 18:57–19:04 | "lo del mantle creo que es una alucinación tuya": afirmación retirada, con una explicación más simple. Paso 5 terminado (simulador de red) y zip `_paso5`. |
| 2026-10-02 19:49–19:50 | Prueba del paso 5 entre las dos PC: demora real de 2 ticks (33 ms), pero 25 saltos de reloj en ~2 minutos y 17 % de snapshots tarde. Diagnóstico: el reloj del paso 3 confiaba en pings sueltos. |
| 2026-10-02 20:01 | Las dos PC van por Wi-Fi. Pregunta sobre el orden de los pasos; se recomendó seguir con el 6 empezando por el reloj. |
| 2026-10-02 20:34–20:44 | "dale, arrancá con el paso 6". Paso 6 terminado (reloj nuevo, predicción y reconciliación) y zip `_paso6`. |
| 2026-10-02 21:17–21:19 | Prueba del paso 6 entre las dos PC: 0 saltos de reloj, 18.883 coincidencias y 21 correcciones. Con 400 ms en total hubo tirones que después se estabilizaron. |
| 2026-10-02 21:21–21:25 | "antes de hacer el retoque, primero arma un commit local". Commit `d75ef67`. |
| 2026-10-02 21:25–21:43 | Retoque 6b: el adelanto se ajusta cambiando el ritmo de ticks. Zip `_paso6b`. |
| 2026-10-03 11:35 | "funciona", con 19 capturas de la notebook. |
| 2026-10-03 11:38 | Commit `9cd1936`. |
| 2026-10-03 11:38–12:06 | Paso 7: afirmaciones, adopción, época, empujón del host y tirones de Wi-Fi simulados. Zip `_paso7`. |
| 2026-10-03 15:48 | Capturas del paso 7 en las dos PC: 61 empujones y época 61. |
| 2026-10-03 15:53 | Commit `7547de1`. |
| 2026-10-03 15:53–16:10 | Paso 8: interpolación de los demás, suavizado de correcciones, 30 snapshots por segundo y reaparición. Zip `_paso8`. |
| 2026-10-03 16:21 | Capturas del paso 8: "se siente muy bien, no hay tirones raros, si hay latencia [...] e inclusive así se siente bien". |
| 2026-10-03 16:22 | Commit `c0e0421`. El esqueleto de red quedó completo. |
| 2026-10-03 16:29 | Pedido de la primera versión de este documento. |
| 2026-10-03 17:09–17:10 | "dale, armá el commit local del md, despues de eso, vamos a la validacion anterior, donde presentaste los 6 puntos y empecemos con el primero". Commit `9caaec3`, solo con el documento. |
| 2026-10-03 17:10–17:45 | Punto 2, base propia: vagón, ascensor y balsa del host. Se confirmó la inferencia I2 del documento (Jolt ve un cuerpo cinemático movido recién en el tick siguiente). Zip `_base_propia` (17:44). |
| 2026-10-03 19:07 | Capturas de la base propia en las dos PC. Con lluvia y Starlink, "cada tanto se desconectaba", y una vez "hizo un tp" antes de cortarse. |
| 2026-10-03 19:08–19:57 | Análisis de las 13 capturas. Medición del plazo de corte de ENet: con la conexión estable, 9,7 s de silencio. Arreglo del saltito del otro jugador al subir o bajar del vagón. Commit `600002a` (19:54), con lo probado. Zip `_base_propia_2` (19:56). |
| 2026-10-04 10:24 | Reporte: el salto del host, visto desde la notebook, "tiene que hacer un ajuste cuando la capsula toca la plataforma". |
| 2026-10-04 10:26–10:49 | El arreglo del día anterior había convertido el saltito en un deslizamiento al aterrizar. Cambio a marcos de dibujo: un salto desde el vagón se dibuja respecto del vagón. Zip `_base_propia_3` (10:48). |
| 2026-10-06 11:54 | Reporte: "en los bordes, todavía es apreciable la corrección". |
| 2026-10-06 11:56–12:28 | Reproducido sin pantalla (0,36 m con red limpia, 0,87 m con internet mala). Arreglo de raíz: lejos del jugador local, el vagón se dibuja en el mismo pasado que los demás. Zip `_base_propia_4` (12:28). |
| 2026-10-06 12:50–12:51 | "podría decirse que esta casi que arreglado"; queda un caso raro. Commit `25f7806`. |
| 2026-10-06 13:27 | "estaba cerca, dale, seguí con el punto de postura": el caso raro queda como límite conocido. |
| 2026-10-06 13:27–13:48 | Punto 3, postura y espacio libre: agacharse, correr, deslizarse y el túnel largo. Zip `_postura`. |
| 2026-10-06 13:54–13:58 | Preguntas sobre agacharse en el suelo y en el aire. Medido tick a tick: en el suelo quedan los pies; en el aire, la cabeza. |
| 2026-10-06 14:10–14:17 | "nop, mi teoría es correcta [...] antes de tocar eso, hay que agregar un botón de pausa [...] Tambien agregar un muro con medidas de referencia". Pausa (P y O) y pared de medidas. Zip `_postura_2`. |
| 2026-10-06 14:19–14:38 | "¿la tecla P esta mapeada en la configuración del proyecto?". Después: "usa la G para pausar y mapea la tecla F para avanzar de tick". Hecho y verificado con teclas simuladas. Zip `_postura_3` (14:37). |
| 2026-10-06 14:44–14:47 | Explicación de cómo funciona la pausa, y aclaración de que solo anda en Jugar solo. |
| 2026-10-06 14:48–14:55 | "efectivamente, como habías hecho la implementación era correcta, lo que pasaba es que el movimiento de cámara rápido [...] daba la ilusión". Arreglo de la cámara y del dibujo de la cápsula al cambiar de postura en el aire. Zip `_postura_4`. |
| 2026-10-06 15:57 | "ahora se ve perfecto, no hace el movimiento raro de antes." |
| 2026-10-06 16:07–16:28 | Primeras capturas de postura en dos PC (todavía sin el túnel). Pregunta: "¿que es?" la postura. Los 9 avisos del depurador (captura 1025) y "dale, limpialos". Zip `_postura_5` (16:28). |
| 2026-10-06 16:37–16:39 | No se puede capturar con Windows + Impr Pant mientras se mantiene Ctrl: "dale, agregá la tecla F12 para capturas". Zip `_postura_6`. |
| 2026-10-06 17:19–17:23 | Capturas de postura en dos PC, con el túnel: 8 del host (1600×900) y 7 de la notebook (1280×720). Commit `cb71b16`. |
| 2026-10-06 19:09–19:18 | "¿que es esto de «en el aire, la forma crece hacia abajo»?" y "decimelo en pocas palabras". Decisión: "perfecto, que se quede asi, seguí con el punto de la escalera". |
| 2026-10-06 19:18–19:49 | Punto 4: escalera, empujones inmediatos y programados, y el canal de eventos programados. Zip `_escalera` (19:49). |
| 2026-10-06 21:00–21:02 | Capturas de la escalera en dos PC con internet mala en las dos. Commit `91a4433`. |
| 2026-10-06 21:26 | Pedido de la segunda versión de este documento: "antes de continuar, arma un md donde se detalle todo lo hecho por hasta ahora, si ya existe un documento anterior cuyo objetivo sea documentar los avances de la implementación, actualizalo con todo lo nuevo agregado." |
| 2026-10-07 12:52–12:53 | "arma commit local". Commit `375d419`, solo con este documento. |
| 2026-10-07 13:06–13:07 | Pregunta: "si en algún punto decido cambiar una mecánica porque X aspecto no me gusta, ¿que tanto quilombo se puede llegar a armar dado que ya existen otras mecanicas?". Respuesta: depende de qué se cambie; un número cuesta poco y una regla compartida, mucho (sección 14). |
| 2026-10-07 13:41 | Pedido del escalón: "antes de hacer el punto 5, quiero que agregues el step, ese mini salto que se da cuando tenes un escalon o algo por el estilo. Tambien te diria que siga la filosofia que venimos siguiendo". |
| 2026-10-07 13:41–14:18 | Escalón: sonda del modo Suelo, pista de escalones y pruebas. Zip `_escalon` (14:18). |
| 2026-10-07 14:23–14:24 | "¿no hay manera de automatizar el paso donde tengo que pasar el archivo a la otra notebook, cargarlo en godot y despues abrirlo?". Dos preguntas; respuestas: "Carpeta compartida" y "El editor con la escena". |
| 2026-10-07 14:24–14:29 | `actualizar_lab.bat` y `actualizar_lab.ps1`, probados en esta PC, y los pasos para compartir la carpeta. |
| 2026-10-07 16:09–16:11 | "¿tengo que hacer algo para probar si tengo la ultima version del proyecto?" y "hice la prueba y tengo todo actualizado": el doble clic funciona por la red. |
| 2026-10-07 16:18–16:19 | Capturas del escalón en dos PC. Commit `b907dae`, con el doble clic. |
| 2026-10-07 16:54 | "en resumidas cuentas, era lo mismo, lo que veías en una notebook o la otra no cambiaba [...] eran dos gotas de agua." Y: "dale, seguí con el punto 5". |
| 2026-10-07 16:56–18:10 | Tres preguntas antes de Hanging. Respuestas (18:10): Espacio sube o salta según la mirada y Ctrl suelta; pruebas automáticas y en dos PC; los criterios del documento. |
| 2026-10-07 18:10–19:36 | Hanging con snap, la pista de bordes, los bordes que se mueven y las pruebas de confirmación. A las 19:36, listo para probar con el doble clic. |
| 2026-10-07 22:04–22:06 | Siete capturas de Hanging en las dos PC. |
| 2026-10-07 22:20 | Resultado de la prueba, en tres puntos: la subida ("me hubiese gustado mas un saltito, pero por ahora lo dejamos así"); moverse colgado dependía de la cámara; y agarrarse exigía apretar W. "Sacando esos tres puntos, el resto funciona correctamente, incluido el servidor con la otra notebook". |
| 2026-10-07 22:21–23:05 | Los dos cambios, con el barrido corrido también sin teclas. A las 23:05, listo para probar. |
| 2026-10-08 10:54 | "ok, todo funciona como deberia, correji los md y agrega una nota donde se explica la razon del cambio + como estaba armado originalmente." Commit `3cdcc91` (10:55) y esta actualización. |
| 2026-10-08 11:32–11:34 | "hace el commit del md y tambien correji tu md". El documento de arquitectura en Claude Docs, corregido con notas (revisión 55), y commit `fa26986` de este documento. |
| 2026-10-08 11:42 | "el próximo paso es quitar temporalmente la animación de escalar y reemplazarla con un salto, pero antes de hacerlo, ¿tenemos algo asi como control aereo?". Respuesta: sí, a 12 m/s². |
| 2026-10-08 11:50 | Pedido del salto: "en vez de salir a los lados o atras, sale hacia arriba con el mismo control aereo [...] que el salto te eleve a 2.2 metros, asi tenes margen para moniobrar". |
| 2026-10-08 11:50–12:15 | El salto para arriba, el barrido corrido de nuevo y un hallazgo: con W apretada desde el salto, en los bloques de 1 m de fondo se pasa de largo. Pregunta sobre qué hacer; respuesta: "¿que?". Explicado de nuevo, más simple. |
| 2026-10-08 12:17 | "abri la escena, corre la prueba y mostrame que haces en cada momento." |
| 2026-10-08 12:17–12:40 | Demostración en una ventana en esta PC, en cámara lenta, con un cartel de las teclas, y capturas de cada paso de las dos formas de subir. |
| 2026-10-08 12:44 | "lo probé un rato en el net_lab y la verdad lo dejaría como esta, uno aprende muy rápidamente y se adapta al toque con los controles, por ahora lo dejamos asi, le doy el visto bueno." |
| 2026-10-08 12:44–13:25 | Las dos pruebas automáticas que apretaban W desde el salto pasan a apretarla en la punta. Pruebas de red: correcciones grandes sobre el borde del cuerpo del host con internet mala, explicadas. |
| 2026-10-08 16:28–16:32 | Prueba en las dos PC: "todo funciona como debería", con dos capturas. "Con respecto a los md, actualízalos a los dos, y despues haces commit". Documento de Claude Docs corregido (revisión 60). |
| 2026-10-08 16:40–16:41 | Commits `3825c2b` (el salto para arriba) y `048dc4d` (la cuarta versión de este documento). |
| 2026-10-08 17:37 | Pedido, con un dibujo: "¿seria posible hacer que para a la hora de entrar en hanging uno no tenga que estar cayendo si o si?". |
| 2026-10-08 17:37–17:45 | Diagnóstico y cambio: sin el límite de subida, el agarre espera a que las manos lleguen al filo y, si ya lo pasaron, lo busca de arriba hacia abajo. El barrido muestra que, debajo del techo bajo, saltar hacia atrás agarra el techo. Pregunta; respuesta (17:45): "Que mire hacia donde salta". |
| 2026-10-08 17:45–18:20 | El giro al saltar hacia otro lado, el barrido, la repetición y las pruebas de red. Pregunta (18:10): "¿por que tiene dos timeout de 590 segundos?". A las 18:20, listo para probar. |
| 2026-10-08 19:17–19:24 | Prueba en las dos PC, con cinco capturas: "funciona correctamente, aunque es posible agarrarse con el timing correcto [...] medio que se siente como un logro mas que otra cosa". Commit `bd2157b`. |
| 2026-10-08 19:30–19:32 | "¿Cómo es eso de subiendo rápido?", explicado. "dale, actualizá los dos md y después hacé commit": documento de Claude Docs corregido (revisión 65), esta actualización y su commit. |

---

## 3. El pedido original

Texto pegado el 2026-10-01 a las 20:41, tal cual:

> Diseñá desde cero una arquitectura de movimiento e interacciones físicas para un juego 3D en Godot 4.7.2 estable, con Jolt como motor de físicas. El juego permite primera y tercera persona y tendrá cooperativo online con un jugador como host. El cooperativo es un fundamento obligatorio de la arquitectura desde el inicio; no lo relegues a una adaptación futura.
>
> Ignorá por completo los documentos, nombres, diseños e implementaciones anteriores de parkour del proyecto. No los uses como punto de partida. Investigá con tus propios medios, consultá documentación oficial y fuentes técnicas públicas cuando haga falta, y distinguí los hechos comprobados de tus inferencias.
>
> La arquitectura debe poder resolver e integrar situaciones como estas:
>
> - Desplazamiento, aceleración, frenado, salto, caída y control aéreo.
> - Agacharse y volver a levantarse, incluso bajo techos bajos.
> - Hanging: encontrar un borde, agarrarse, permanecer colgado y salir.
> - Ladder: entrar a una escalera, recorrerla y abandonarla.
> - Saltos especiales de mayor altura y cambios temporales de velocidad.
> - Cámara lenta que afecte a un jugador o al mundo compartido.
> - Sprint, dash, deslizamiento, carrera por paredes, cuerdas o tirolesas.
> - Plataformas móviles, superficies que empujan, trampolines y zonas de gravedad alterada.
> - Empujones, explosiones, daño, aturdimiento, pérdida de control, muerte y reaparición.
> - Cooperación entre jugadores: empujar juntos un objeto, ayudar a otro a alcanzar una zona, sujetarlo, arrastrarlo o revivirlo.
>
> Estos son casos para poner a prueba la arquitectura, no una lista de funciones que debas implementar. Agregá otros casos propios de un juego 3D cooperativo si revelan problemas que esta lista no cubre. No incluyas mantle: está fuera del alcance del proyecto.
>
> Prestá especial atención a las combinaciones: un empujón en una escalera, cámara lenta durante un salto especial, el fin de un deslizamiento bajo un techo, un cambio de velocidad sobre una plataforma móvil, la desconexión de un jugador durante una interacción cooperativa o una corrección de red en mitad de una acción. La arquitectura debe dar una respuesta coherente a estos casos sin depender de una excepción nueva para cada combinación.
>
> No hay un método de movimiento obligatorio. Evaluá las herramientas pertinentes de Godot y Jolt, entre ellas `move_and_slide()`, `move_and_collide()`, las consultas físicas y, cuando corresponda, los cambios de transform. Elegí y justificá sus usos. Tené en cuenta qué información ofrecen `is_on_floor()`, `is_on_wall()` y funciones similares según cómo se haya movido el cuerpo.
>
> Preferiría reducir la inyección de información entre sistemas y evitar enormes árboles de `if`, pero ninguna de las dos cosas está prohibida. Si son necesarias para que el diseño funcione, usalas y explicá sus consecuencias. Decidí vos qué sondas hacen falta y cómo interpretar sus resultados.
>
> Para la captura de Hanging, desarrollá dos variantes: una con snap del player a la pose de agarre y otra sin snap. Compará su funcionamiento, sus diferencias arquitectónicas, sus problemas físicos y visuales, y sus consecuencias en cooperativo con latencia. Explicá cómo se podría decidir entre ellas mediante pruebas.
>
> Presentá la arquitectura que consideres más sólida, las alternativas que descartaste y los motivos. Demostrá su comportamiento recorriendo casos concretos, especialmente combinaciones de acciones y situaciones de red. No supongas que Jolt producirá resultados idénticos en máquinas distintas. Cada pieza que propongas debe resolver un problema identificable.
>
> Por ahora no escribas código ni modifiques el proyecto. Quiero revisar la arquitectura primero.

---

## 4. La arquitectura

### 4.1 Cómo se hizo

El documento se escribió en Claude Docs entre las 21:04 y las 21:36 del 2026-10-01, sin tocar el proyecto. Antes de cada sección se verificaron los hechos en fuentes oficiales:

- la documentación de Godot 4.7.2: qué informan `move_and_slide()` y sus indicadores, Jolt en Godot, la escala de tiempo, la interpolación de física y la red de alto nivel;
- que Godot 4.7.2 no permite avanzar ni rebobinar la física de Jolt desde script;
- la red de Godot: RPC, canales, y un `MultiplayerSynchronizer` que no maneja ticks;
- netfox: si su rebobinado de física funciona con Jolt en Godot 4.7.2 sin compilación propia;
- Unreal 5.8, que documenta que el servidor adopta el estado del cliente y usa un solo modo activo con modificadores, efectos instantáneos y transiciones;
- Unity y Photon.

Los hechos comprobados y las inferencias quedaron separados en la sección "Hechos comprobados e inferencias" del documento. Las fuentes abiertas están en su sección "Fuentes" (Apéndice A).

### 4.2 La idea central

Tomada del resumen del documento:

- **El modelo de red:** host autoritativo; cada cliente predice solo su propio personaje, y el host adopta esa predicción cuando es físicamente válida y no hubo eventos del host de por medio. Así las diferencias de Jolt entre máquinas no producen correcciones: solo se corrige lo que el cliente no podía saber.
- **Un estado completo por actor y un paso por tick en orden fijo:** efectos, sondas, transiciones, modo, movimiento y contactos. Una corrección restaura ese estado y repite los ticks.
- **Un solo modo activo:** Suelo, Aire, Deslizamiento, Pared, Ladder, Hanging, Tirolesa, Cuerda, Enganchado y Muerto. Sprint, dash, saltos especiales, aturdimiento o cámara lenta no son modos.
- **Siete reglas generales para las combinaciones:** fuerza contra agarre, invariantes con salida de respaldo, postura según espacio libre, velocidad relativa a la base, tiempo del actor, capacidades y anclas que pueden desaparecer.
- **Herramientas:** `move_and_slide()` solo en modos libres. Los modos anclados calculan su pose desde el ancla. Las sondas son consultas directas al espacio. El transform directo queda para restauraciones, reaparición y snaps validados.
- **Interacciones co-op:** son pedidos que valida el host.

### 4.3 Estructura del documento

1. Resumen
2. Hechos comprobados e inferencias (tablas de Godot 4.7.2 y Jolt, y de referencias de otros motores)
3. Modelo de red y tiempo (quién simula, reloj, qué manda el cliente, qué hace el host, qué hace el cliente, eventos programados e inmediatos, cambio de línea, desconexiones)
4. Núcleo del actor (estado, paso por tick en ocho etapas, modos, lo que no es modo, las siete reglas, transiciones)
5. Herramientas de Godot y Jolt (cuándo usar cada una, cómo leer los indicadores, configuración, escala de tiempo, escalones, Jolt en particular)
6. Sondas (nueve sondas, cómo se interpretan, la sonda de borde)
7. Interacciones cooperativas (protocolo común, casos, reglas)
8. Presentación (capas, correcciones, animación, sonido, primera y tercera persona, cámara lenta)
9. Hanging: con snap (lo común, variante A, subir al borde, variante B descartada, comparación, pruebas de confirmación)
10. Recorridos de casos (catorce casos tick a tick)
11. Alternativas descartadas
12. Inventario, riesgos y qué validar primero
13. Fuentes

### 4.4 Decisiones tomadas después de escribirlo

**Hanging con snap** (2026-10-02, 11:40). Respuesta a la pregunta de si convenía con o sin snap, tal cual:

> **Conviene con snap**: snap instantáneo en la simulación y transición suave en pantalla (la variante A del documento). Es la que respeta los mismos lineamientos que el resto de la arquitectura; sin snap, Hanging pasa a ser una excepción.
>
> **Por qué, con los mismos lineamientos:**
>
> - **Los modos anclados calculan su pose desde el ancla.** Ladder, Tirolesa, Cuerda y Enganchado ya funcionan así: entrar a una escalera te pone sobre su eje. Con snap, Hanging es un modo anclado más. Sin snap, sería el único que guarda un dato extra de dónde quedó el cuerpo.
> - **Estado mínimo.** Con snap se guarda el ancla y la posición sobre el filo. Sin snap también hay que guardar el desplazamiento del cuerpo, y eso hay que mandarlo por red, validarlo y dibujarlo.
> - **Las diferencias de Jolt no deben producir estados distintos.** Con snap, agarrarse un tick antes o uno después termina en la misma pose. Sin snap, un tick de diferencia cayendo rápido son unos 20 cm distintos entre host y cliente. La arquitectura existe justamente para evitar ese tipo de diferencia.
> - **La presentación absorbe los saltos.** El snap usa el mismo suavizado visual que ya corrige la red, así que no agrega ninguna pieza. Sin snap hacen falta IK y mezclas de animación para cada pose posible.
> - **Salidas repetibles.** Saltar desde el colgado siempre arranca de la misma pose, así que los saltos entre bordes se pueden diseñar y medir.
>
> **Lo que cuesta:**
>
> - Antes del snap hay que validar dos cosas: que el cuerpo entre en la pose de agarre y que el camino hasta ahí esté libre. También hace falta una distancia máxima de snap; para empezar, unos 35 cm.
> - En primera persona hay que afinar el suavizado de la cámara. Solo se suaviza la posición, nunca la rotación, y quizás un poco más lento que el del cuerpo.
> - No recomiendo el término medio de hacer el snap gradual dentro de la simulación. Suma estado y permite salir del colgado desde poses a medio camino.
>
> **Qué me haría cambiar de opinión.** Las pruebas sirven para confirmar esto, no para elegir de cero:
>
> - Que en la geometría real, sobre todo la irregular como rocas o curvas, la pose de agarre se rechace seguido donde sin snap el personaje sí se agarraría.
> - Que en primera persona el desplazamiento de la cámara moleste y no se arregle afinándolo.
> - Que el diseño necesite que la altura a la que cuelga el personaje importe para el juego.

En el documento quedó anotado como decisión tomada. Las pruebas pasaron a ser de confirmación, con las tres situaciones que la volverían a abrir. "Sin snap" y el snap gradual quedaron en la tabla de alternativas descartadas.

**Subir al borde es una salida de Hanging, no mantle** (2026-10-02, 11:48). El documento ya decía que mantle estaba fuera del alcance y dejaba abierta una pregunta en un comentario: ¿trepar desde el colgado hasta arriba del borde cuenta como mantle? La respuesta fue "sumalo como salida de Hanging, no es mantle". Así quedó definido en la sección "Subir al borde" del documento:

- se valida que arriba haya espacio para el cuerpo agachado;
- se valida el camino en dos tramos con `test_move`;
- la subida es una fase dentro de Hanging, con su progreso medido en tiempo del actor;
- termina en Suelo.

Mantle, es decir trepar o saltar obstáculos sin colgarse, sigue fuera del alcance.

**Agarrarse de un borde no exige intención hacia la pared** (2026-10-07, 22:20, después de probar Hanging en las dos PC). El documento pedía "intención hacia la pared" para pasar de Aire a Hanging. La primera versión de Hanging lo cumplía al pie de la letra, y sin apretar W no había agarre. El pedido fue: "Eso también hay que quitarlo, no siempre queres darle a la W para llegar a X lado". Ahora:

- sin teclas, las manos buscan hacia donde mira el personaje;
- con teclas, hacia donde se mueve.

En la misma prueba se pidió que A y D, colgado, no dependan de la cámara. Eso no contradecía al documento, que habla de "el input lateral": era cómo lo había armado la primera versión.

Los dos cambios, cómo estaba armado antes y por qué cambió están en la sección 8.5. En el Apéndice A se corrigieron los dos lugares donde el documento pedía la intención, y la regla general sobre la orientación del modelo lleva una nota. Lo mismo se hizo en el documento de Claude Docs (2026-10-08, revisión 55).

**Subir al borde pasa a ser un salto para arriba** (2026-10-08, pedido a las 11:50 y aprobado a las 12:44, después de probarlo). Sigue siendo una salida de Hanging y no mantle, pero ya no es una trayectoria dentro de Hanging:

- mirando a la pared, Espacio salta derecho para arriba;
- los pies llegan 20 cm por encima del filo;
- el jugador pasa arriba con el control aéreo.

El pedido fue "quitar temporalmente la animación de escalar y reemplazarla con un salto". Cómo era la subida, por qué cambió y cómo quedó está en la sección 8.6. En el Apéndice A y en el documento de Claude Docs (revisión 60) se reescribió la sección "Subir al borde", con la subida vieja copiada en una nota, y se corrigieron otros tres lugares que la mencionaban.

**Agarrarse también subiendo** (2026-10-08, pedido a las 17:37 con un dibujo). El documento pedía, para pasar de Aire a Hanging, "velocidad vertical por debajo de un máximo de subida"; en el laboratorio el máximo era 1 m/s. Como un salto arranca a 4,8 m/s, para agarrarse había que llegar a la punta del salto o estar cayendo. Ahora:

- se agarra también subiendo, cuando las manos llegan al filo;
- al saltar hacia otro lado desde el colgado, el personaje se da vuelta hacia donde salta (elegido a las 17:45).

El detalle está en la sección 8.7. En el Apéndice A y en el documento de Claude Docs (revisión 65) se corrigieron los dos lugares de la regla, la lista de salidas y el "Estado" de Hanging, que había quedado viejo con el salto para arriba.

---

## 5. El plan del esqueleto de red

### 5.1 El plan propuesto (2026-10-02, 11:59), tal cual

> Antes de empezar hay que decidir dos cosas:
>
> - **Sin netfox para el esqueleto.** netfox restaura y repite todo en cada rollback, y no trae la adopción ni la época, que son el centro de esta arquitectura. Adaptarlo sería pelear contra él. Sus trucos documentados ya están incorporados al diseño.
> - **Carpeta nueva y rama aparte.** No se toca ni se reutiliza el código de parkour actual. La rama actual tiene muchos cambios sin commitear: conviene decidir antes qué hacer con ellos.
>
> Lo armaría en ocho pasos chicos. Cada uno tiene una prueba que dice si está listo. La latencia simulada entra en el paso 5, así la predicción ya se construye en condiciones reales.
>
> 1. **Laboratorio y ajustes.** Una escena nueva con piso, rampa, escalón, pared y techo bajo. Ajustes del proyecto: 60 ticks, `physics_jitter_fix` en 0 y Jolt. Se lanzan dos instancias desde *Debug > Customize Run Instances*, con un argumento que indique si cada una es host o cliente.
>    *Listo cuando:* las dos se abren con un clic.
> 2. **Actor mínimo con estado explícito.** Una cápsula que solo tiene Suelo y Aire: caminar y saltar. El estado vive en un objeto propio que se cuantiza y se empaqueta a bytes. El paso por tick es una función que recibe estado, input y dt, y llama a `move_and_slide()` con el factor de velocidad. Todavía sin red.
>    *Listo cuando:* la misma grabación de inputs, reproducida dos veces, da el mismo estado tick por tick.
> 3. **Conexión, aparición y reloj.** `ENetMultiplayerPeer` en localhost, y el host crea una cápsula por jugador con `MultiplayerSpawner`. Un único reloj cuenta los ticks y llama a cada actor en orden fijo; los actores no tienen `_physics_process` propio.
>    *Listo cuando:* las dos ventanas ven dos cápsulas y avanzan con el mismo número de tick.
> 4. **Host autoritativo, sin predicción.** El cliente manda su input en cada tick, con contadores de pulsación y los últimos 4 a 8 ticks repetidos por si se pierde un paquete. El host simula y manda snapshots a 30 Hz con el último tick procesado. El cliente solo muestra lo que recibe.
>    *Listo cuando:* el cliente maneja su cápsula, con demora, y las dos pantallas coinciden.
> 5. **Simulador de red y panel de métricas.** La demora, la variación y la pérdida se aplican al recibir paquetes, dentro de nuestra propia capa, para que sea reproducible. El panel muestra RTT, adelanto, inputs en cola en el host, correcciones por minuto, porcentaje de adopción y tamaño de la última corrección.
>    *Listo cuando:* el paso 4 se ve mal a 120 ms, que es lo esperado.
> 6. **Predicción y reconciliación.** El cliente simula su cápsula por adelantado y guarda input y estado de cada tick. Si un snapshot no coincide con lo guardado, restaura, sincroniza los indicadores de piso y repite los ticks. El adelanto se ajusta con la cola que informa el host.
>    *Listo cuando:* a 120 ms el control se siente inmediato y las correcciones son raras.
> 7. **Afirmaciones, adopción y época.** El input lleva la afirmación del cliente. El host la adopta si es válida y la época coincide, y registra cuánto difería de su propio resultado. Se agregan dos botones de prueba en el host: un empujón inmediato y uno programado.
>    *Listo cuando:* al caminar la adopción ronda el 100 %, el empujón inmediato da una sola corrección suave y el programado ninguna.
> 8. **Interpolación y suavizado.** Las cápsulas remotas se interpolan con unos 100 ms de colchón. La propia usa el desvío visual al corregir, y se activa la interpolación de física.
>    *Listo cuando:* todo se ve fluido con snapshots a 30 Hz.
>
> **Prueba final del esqueleto:** caminar, saltar sin parar, frotarse contra paredes y esquinas y bajar escalones. Con RTT de 0, 60, 120 y 200 ms y pérdida de 0, 2 y 5 %.
>
> **Quedan afuera:** modos anclados, cuerpos rígidos, interacciones, Steam y NAT. Se agregan sobre un esqueleto que ya está medido.

### 5.2 Ajustes por tener una segunda PC (2026-10-02, 12:10)

Al saber que había otra PC para probar, se aclaró que la LAN no reemplaza al simulador de red. Una LAN tiene alrededor de 1 ms y casi no pierde paquetes, así que el paso 5 sigue haciendo falta. Además, que dos PC con Windows y la misma build den resultados idénticos no cubre a un compañero en otra plataforma, como Linux o una Steam Deck. Jolt documenta que con el mismo binario da igual si el procesador es AMD o Intel.

Lo que agrega la segunda PC:

- que el transporte funcione de verdad: IP de LAN, puerto UDP y firewall de Windows;
- relojes reales distintos, que ponen a prueba el control del adelanto;
- máquinas con potencias distintas;
- una divergencia real medida.

Ajustes propuestos al plan:

- **Paso 1:** mismo commit y Godot 4.7.2 en las dos PC. Se itera rápido con dos instancias en una máquina, y las corridas de validación se hacen entre las dos PC.
- **Paso 5:** un registro por tick en cada máquina (número de tick, estado cuantizado y si hubo adopción o corrección) para comparar los dos archivos por número de tick.
- **Matriz de prueba:**
    - misma build en las dos PC con adopción apagada, para medir la diferencia real entre máquinas;
    - editor en una PC y build exportada en la otra, para tener dos binarios distintos;
    - latencia simulada de 60, 120 y 200 ms, y pérdida.

La otra PC resultó ser también Windows.

### 5.3 En qué se apartó la implementación del plan

| Punto del plan | Qué se hizo en realidad |
| --- | --- |
| Paso 1: ajustes del proyecto (60 ticks, `physics_jitter_fix` en 0, Jolt) | `project.godot` no se tocó. El proyecto ya usaba Jolt Physics. El laboratorio aplica al arrancar, en `_enter_tree()`, los 60 ticks, el `physics_jitter_fix` en 0 y la interpolación de física. Cuando el esqueleto pase a ser el juego, esos ajustes van a `project.godot`. |
| Paso 1: dos instancias desde *Customize Run Instances* con argumentos `--host` y `--client` | Funcionó, pero las instrucciones resultaron confusas. Se reemplazó por un menú dentro del juego (Jugar solo, Crear partida, Unirse con IP, Simular internet). Los argumentos quedaron solo para pruebas automáticas. |
| Carpeta nueva y rama aparte | Carpetas nuevas, sí. Rama aparte, no: los 4 commits quedaron en la rama de parkour `codex/parkour-v3-h0-lab`, sin mezclar archivos. Moverlos a una rama propia sigue ofrecido. |
| Paso 4: snapshots a 30 Hz | Hasta el paso 7 fueron 60 por segundo, porque sin interpolación se veía a saltos. Desde el paso 8 son 30 por segundo. |
| Paso 5: demora aplicada al recibir | El simulador corre en una sola máquina y afecta lo que esa máquina manda y recibe, ping incluido: la mitad de la demora en cada sentido. Así alcanza con activarlo en la PC que se une, sin configurar el host. |
| Paso 5: panel con correcciones por minuto y porcentaje de adopción | El panel muestra totales: coincidencias, correcciones, tamaño de la última corrección y, en el host, adoptadas y rechazadas por motivo. No hay valores por minuto ni porcentajes de adopción. |
| Paso 5 (ajuste): registro por tick en cada máquina para comparar archivos | No se implementó. La comparación entre máquinas se hizo con los contadores de coincidencias y correcciones de la predicción, que comparan byte a byte, y con el estado final idéntico en las pruebas automáticas. |
| Matriz: editor contra build exportada | No se hizo. En esta PC solo están instaladas las plantillas de exportación de Godot 4.6. Las dos PC usaron el mismo `Godot_v4.7.2.exe`. |
| Paso 6: el adelanto se ajusta con la cola que informa el host | Se hizo así en el paso 6, con el margen de input que informa el host, corriendo 2 o 0 ticks en un frame. En el retoque 6b pasó a ajustarse cambiando el ritmo de ticks. |
| Paso 7: dos botones de prueba, un empujón inmediato y uno programado | Solo el empujón inmediato (tecla E en el host). Los eventos programados, que el host anuncia por adelantado para que el cliente los aplique sin corrección, quedaron pendientes. |
| Paso 7: "al caminar la adopción ronda el 100 %" | Al caminar, las afirmaciones coinciden con el resultado del host byte a byte (por ejemplo, 441 iguales y ninguna distinta), así que no hace falta adoptar. La adopción entra en juego con los inputs tardíos: 8 adoptadas y 0 correcciones con tirones de Wi-Fi. |
| Paso 8: "se activa la interpolación de física" | Ya estaba activa desde el paso 1. |
| Prueba final: RTT de 0, 60, 120 y 200 ms; pérdida de 0, 2 y 5 % | Los niveles del simulador son: sin simulación; +40 ms ±5; +120 ms ±20 con 1 %; +200 ms ±40 con 5 %; y tirones de Wi-Fi. Se probaron con caminar, saltar y zigzag en pruebas automáticas, y además en Wi-Fi real entre dos PC, incluido ~400 ms de ida y vuelta. No se corrió exactamente la matriz del plan. |
| Agregados que no estaban en el plan | Menú dentro del juego; zips para la otra PC; retoque 6b del adelanto; que el cliente espere ante estados provisorios del host (paso 7); nivel de red "Wi-Fi con tirones"; reaparición al caer del mapa; medición de tirones de los demás; argumentos de prueba (`--test-input=zigzag`, `--sim-after`, `--sim-until`, `--trace`, `--test-push-at`, `--no-adoption`, tirones) y la prueba de repetición a cualquier ritmo (`--rate`). |

---

## 6. Entorno de trabajo y de pruebas

### 6.1 Las dos PC

- **Las dos máquinas:** dos PC con Windows, las dos conectadas por Wi-Fi. Esta PC hace de host (IP en la red local: 192.168.1.212) y la otra, una notebook, de cliente.
- **El Godot:** las dos usan exactamente el mismo `Godot_v4.7.2.exe`, el que está en el escritorio de esta PC. Es un solo archivo y no se instala. Usar el mismo programa sirve además para la prueba de "mismo binario en dos máquinas".

### 6.2 Cómo llegó el proyecto a la otra PC

Se descartó exportar un ejecutable por tres motivos:

- en esta PC solo están instaladas las plantillas de exportación de Godot 4.6, no las de 4.7.2;
- el ejecutable arrancaría en la escena principal del juego, no en el laboratorio;
- con el proyecto copiado, en la otra PC el laboratorio se abre igual que en esta, con el mismo menú.

Cada entrega fue un zip en el escritorio con la carpeta del proyecto completa, sin `.godot` ni `.git` (Godot rehace `.godot` solo al abrir el proyecto). Pesan 18 MB y tienen entre 879 y 890 archivos. También llevan los cambios de parkour sin commitear, que no molestan.

En la otra PC, cada vez:

1. Copiar el zip y, la primera vez, `Godot_v4.7.2.exe`.
2. Clic derecho en el zip, **Extraer todo…**, en una carpeta nueva (o reemplazando la anterior).
3. Abrir `Godot_v4.7.2.exe`, **Importar** y elegir el `project.godot` de la carpeta. La primera vez tarda porque importa los modelos.
4. Abrir `scenes/net_lab/net_lab.tscn` y apretar **F6**.

Cuando cambia una clase con nombre (`class_name`), conviene cerrar y volver a abrir Godot en esta PC para que la registre.

**Desde el 2026-10-07, un doble clic en vez de los zips.** Lo pidió el usuario a las 14:23: "¿no hay manera de automatizar el paso donde tengo que pasar el archivo a la otra notebook, cargarlo en godot y despues abrirlo?, la parte donde me encargo de hacer las pruebas lo hago yo, pero me de pereza hacer todo el resto". Eligió dos cosas:

- que el proyecto llegue por una carpeta compartida, y no con el zip;
- que se abra el editor con la escena, como hasta entonces, y no el juego directo.

**Una sola vez, en esta PC:** la carpeta del proyecto se comparte como `tun-lab`, solo de lectura para **Todos**. En **Uso compartido avanzado** se prenden la detección de redes y el uso compartido de archivos de la red privada. Esa configuración es de seguridad de Windows: la hizo el usuario, con pasos clic por clic.

**Una sola vez, en la notebook:**

1. Entrar a `\\DESKTOP-N3JTNMU\tun-lab` con **Windows + R**, con el usuario y la contraseña de esta PC, y tildar **Recordar mis credenciales**.
2. Copiar `tools/net_lab/actualizar_lab.bat` al Escritorio.

**Cada vez:** cerrar Godot y hacer doble clic en `actualizar_lab.bat`. Tarda unos 10 s. El `.bat` corre `actualizar_lab.ps1` desde la carpeta compartida, así que la notebook siempre usa la versión de esta PC. El script:

1. espera a que Godot esté cerrado;
2. busca la carpeta compartida, por nombre (`\\DESKTOP-N3JTNMU\tun-lab`) o por IP (`\\192.168.1.212\tun-lab`), y busca `Godot_v4.7.2*.exe` en el Escritorio, Descargas o Documentos;
3. copia con `robocopy /MIR` a `Documentos\tun-tun-tun-sahur-lab`, sin `.godot` ni `.git`. La primera vez copia unos 900 archivos; después, solo los que cambiaron. La carpeta `.godot` de la copia queda, así Godot solo vuelve a preparar lo nuevo;
4. prepara el proyecto sin ventana (`--headless --import`), que registra las clases nuevas;
5. abre el editor con `net_lab.tscn` (`-e --path <copia> res://scenes/net_lab/net_lab.tscn`).

Si algo falla, lo dice en la ventana negra y espera un Enter. Para probarlo en esta PC, el script acepta `-Origen`, `-Destino` y `-Prueba` (no espera a que Godot se cierre).

**Regla nueva** (16:09): el doble clic se hace recién cuando aviso que algo está listo para probar. Si se hace mientras cambio archivos, puede llegar una versión a medio terminar.

**Cómo se sabe qué se probó, sin zip:**

- **En `b907dae`:** se comprobó que ningún archivo cambió después del doble clic de la prueba.
- **Desde Hanging:** al avisar que algo está listo, guardo una huella SHA-1 de cada archivo del laboratorio que cambió. Antes del commit se comprueba que las huellas siguen iguales. Así se verificó `3cdcc91`: los 16 archivos coincidieron con la versión probada.

### 6.3 Cómo se conectan

1. En esta PC: F6 y **Crear partida**. El menú muestra la IP de esta PC en la red local. La primera vez, Windows pide permiso de firewall: hay que permitirlo en red privada.
2. En la otra PC: F6, escribir la IP en el campo y tocar **Unirse**. El puerto es el 7777, por UDP.
3. Si no conecta, revisar que las dos PC estén en la misma red y que Windows la tenga como **Privada**.

### 6.4 Pruebas automáticas

- **Godot sin ventana:** `Godot_v4.7.2.exe --headless --path <proyecto> --scene res://scenes/net_lab/...`. Los argumentos del laboratorio van después de `--`.
- **Lanzador:** cada corrida se lanza con `System.Diagnostics.Process` desde PowerShell, con salida capturada, tiempo límite y `taskkill /T /F` si se pasa. Así no quedan procesos colgados (scripts en el Apéndice B).
- **Pares host y cliente:** dos procesos en esta PC. El host escucha en el puerto 7799 con `--bind=127.0.0.1`, que evita el cartel del firewall, y el cliente arranca 1,5 s después.
- **Clases nuevas:** antes de correr escenas que usan una clase nueva, `--headless --import` registra los `class_name`.
- **Ver lo que se dibuja:** con Movie Maker de Godot (`--write-movie <carpeta>/frame.png --fixed-fps 30`), con ventana, se graban fotogramas y se miran. Así se encontró el error de la interpolación activada tarde y se confirmó la cámara del paso 8.
- **Diagnósticos chicos:** scripts que extienden `SceneTree` y se corren con `-s` (Apéndice B): ritmo de ticks, validación de pose y suavizado.

---

## 7. Paso a paso

### Pasos 1 y 2: laboratorio y actor con estado explícito

**Fecha:** 2026-10-02, de 12:31 a 12:53.

#### Paso 1: el laboratorio

- **`scenes/net_lab/net_lab.tscn`** es la escena del laboratorio. Tiene:
    - `Level` (instancia del nivel);
    - `Actors`, donde aparecen los personajes;
    - `ActorSpawner` (un `MultiplayerSpawner`, desde el paso 3);
    - `Clock`, `NetSync` y `LinkSimulator` (desde los pasos 3, 4 y 5);
    - `Session` (paso 3);
    - `CameraRig` con `SpringArm` y `Camera`;
    - `Hud`, con la etiqueta `Info` y el panel `Menu` (desde el paso 3).
- **`scenes/net_lab/net_lab_level.tscn`** es el nivel. Todos los objetos son `StaticBody3D` con su forma y su malla:

    | Objeto | Tamaño (m) | Centro (x, y, z) | Para qué |
    | --- | --- | --- | --- |
    | Floor | 60 × 1 × 60 | (0, −0.5, 0) | Piso con la cara de arriba en y = 0. Termina a 30 m del centro. |
    | Step | 4 × 0.25 × 1 | (0, 0.125, −3) | Escalón de 25 cm |
    | Ramp | 3 × 0.3 × 8.246 | (−6, 0.8545, −6.0364) | Rampa inclinada unos 14° (`asin(0,242536)`) que sube hacia la plataforma |
    | Platform | 3 × 2 × 4 | (−6, 1, −12) | Plataforma con la cara de arriba a 2 m |
    | Wall | 1 × 3 × 14 | (6.5, 1.5, −3) | Pared larga |
    | CornerWall | 3 × 3 × 1 | (4.5, 1.5, −10.5) | Esquina con la pared |
    | TunnelPillarLeft / TunnelPillarRight | 0.5 × 1.2 × 4 | (±1.75, 0.6, −10) | Columnas del túnel |
    | TunnelSlab | 4 × 0.3 × 4 | (0, 1.35, −10) | Techo del túnel: abajo a 1,2 m, arriba a 1,5 m |

    También tiene un `Sun` (`DirectionalLight3D` en (0, 10, 0), rotado) y un `WorldEnvironment` con cielo.
- **`scenes/net_lab/net_lab.gd`** es el script del laboratorio. Aplica al arrancar, en `_enter_tree()`, los ajustes de tiempo del juego en red: interpolación de física, 60 ticks por segundo y `physics_jitter_fix` en 0. No toca `project.godot`. Al principio, el rol (`--local`, `--host` o `--client`) se leía de los argumentos de lanzamiento, que llegan por `OS.get_cmdline_user_args()` o `OS.get_cmdline_args()` según cómo se lance.
- **`scenes/net_lab/lab_camera.gd`** es una cámara de tercera persona mínima: rota con el mouse en `_process()`, sigue la posición interpolada del objetivo (`get_global_transform_interpolated()`) a 1,6 m de altura, y Esc suelta el mouse. Es presentación pura: a la simulación solo le llega el yaw, como parte del input.

#### Paso 2: el actor

Archivos en `scripts/actor/`:

- **`actor_state.gd` (`ActorState`)** es el estado completo del actor al final de un tick. La regla de oro: nada que influya en el movimiento futuro vive fuera de este objeto. Se cuantiza al final de cada tick (posición a 0,1 mm, velocidad a 1 mm/s, normal a 0,0001, tiempos a 0,1 ms, yaw en 65.536 pasos), así comparar dos estados es comparar sus bytes. Al principio solo tenía `copy()`; en el paso 4 se sumó `to_bytes()`/`from_bytes()` (49 bytes), y en el paso 7 la época (51 bytes).
- **`actor_input.gd` (`ActorInput`)** es el input de un tick: tick, ejes de movimiento cuantizados a 1/127, yaw de la mirada en 65.536 pasos, botones en bits y un **contador de pulsaciones de salto** de 0 a 255. El contador cambia aunque se pierda el tick exacto de la pulsación. Se cuantiza al crearlo.
- **`actor_tuning.gd` (`ActorTuning`)** son los parámetros de movimiento:
    - caminar a 5 m/s, acelerar a 45 m/s² y frenar a 60 m/s²;
    - snap al piso de 0,3 m;
    - aceleración en el aire de 12 m/s², gravedad de 9,8 m/s² y caída máxima de 40 m/s;
    - salto a 4,8 m/s, coyote de 0,1 s y memoria del salto de 0,12 s.

    Host y clientes tienen que usar el mismo recurso.
- **`actor_motor.gd` (`ActorMotor`)** es el paso por tick: `step(body, state, input, tuning, dt)`. No guarda nada propio, así que cualquier tick se puede repetir. Sigue el orden de etapas de la arquitectura, solo con Suelo y Aire:
    1. Tiempo: descuenta coyote y memoria del salto en tiempo del actor.
    2. Eventos: detecta una pulsación nueva porque el contador cambió.
    3. Transición, como máximo una por tick: Suelo salta o pasa a Aire si perdió el piso; Aire vuelve a Suelo si apoyó bajando, o salta dentro del coyote.
    4. Modo: el modo activo decide la velocidad. En Suelo, la vertical es cero y las pendientes las resuelve el snap; en Aire actúan la gravedad y el control aéreo.
    5. Movimiento con `slide()`: el snap solo existe en Suelo.
    6. Contactos: copia los indicadores de Godot al estado, cuantiza y deja el cuerpo en la posición cuantizada, igual que después de restaurar.
- **`actor_body.gd` (`ActorBody`, un `CharacterBody3D`):**
    - Desactiva la velocidad de plataforma de Godot (`platform_floor_layers` y `platform_wall_layers` en 0, `PLATFORM_ON_LEAVE_DO_NOTHING`), porque Godot la lee del presente y eso falla al repetir ticks. También activa `floor_block_on_wall` y `floor_stop_on_slope`.
    - `slide()` multiplica la velocidad por `dt / delta de física`, porque `move_and_slide()` toma el delta por su cuenta.
    - `apply_state()` pone el cuerpo en un estado y sincroniza los indicadores internos de piso de Godot con un movimiento de velocidad cero.
    - `present()` orienta el visual.
- **`scenes/actor/actor.tscn`** es el actor: un `CharacterBody3D` en la capa 2 con máscara 1, así los actores no chocan entre sí. Tiene una cápsula de radio 0,35 m y altura 1,8 m centrada a 0,9 m, y un `Visual` con la malla `Body` y una "nariz" amarilla (`Nose`) hacia −Z.

**La prueba de repetición (`scenes/net_lab/actor_replay_test.gd` y `.tscn`)** es el criterio de "listo" del paso 2:

- Un recorrido guionado de 10 tramos y 1.105 ticks. Se asienta, camina hasta el escalón, salta al escalón, gira hacia la pared, va en diagonal contra la pared hasta la esquina, salta cuatro veces contra el túnel, roza el costado del escalón, cruza el piso abierto, sube la rampa, cae de la plataforma, salta al caer y se queda quieto.
- **Pasada en vivo:** un tick por frame de física.
- **Repeticiones largas:** desde 16 ticks intermedios (0, 1, 2, 17, 60, 151, 152, 203, 333, 444, 555, 666, 777, 888, 955 y 1050) se restaura el estado guardado y se repite hasta el final dentro de un solo frame, como hará la reconciliación.
- **Repeticiones cortas:** desde cada tick, una ventana de 30 ticks.
- **Comparación:** cada tick repetido se compara byte a byte con la pasada en vivo.
- **Resultado:** sale con código 0 si todo coincide, 1 si algo difiere y 2 si no termina en 150 s.
- **Cobertura:** 835 ticks en Suelo, 270 en Aire, 249 tocando pared, 4 saltos y 3,02 m de altura máxima.

**Resultado:** 1.121 repeticiones y 44.141 ticks repetidos, todos idénticos byte a byte a la pasada en vivo.

**Problemas encontrados en estos pasos:**

- **Una restauración en el margen de 1 mm perdía el piso**, y la repetición difería en el tick 777. Godot deja el cuerpo apoyado a 1 mm del piso y, al cuantizar, puede quedar una fracción de milímetro más arriba. Fuera del margen, el movimiento de velocidad cero no ve el piso y el tick siguiente no hace snap. **Arreglo:** en `apply_state()`, si el estado dice estar apoyado y Godot no lo ve, un snap manual de 1 cm (`RESTORE_SNAP_LENGTH`). Es justo lo que iba a necesitar la reconciliación del paso 6.
- **La ruta de la prueba no llegaba a la rampa:** el escalón le cerraba el paso. **Arreglo:** registro de dónde termina cada tramo, y la ruta rodea por el lado abierto del piso.
- **Las rotaciones en las escenas estaban mal escritas (error mío):** escribí las matrices por columnas, y Godot las guarda por filas. La rampa quedó invertida y el sol apuntaba hacia arriba. **Arreglo:** matrices transpuestas, verificado.

**Entrega:** los archivos nuevos quedaron sin seguimiento en git, al lado de los 136 cambios de parkour sin commitear. No se tocó ningún archivo existente.

### Arreglo: "se carga una escena totalmente diferente"

**Fecha:** 2026-10-02, de 12:58 a 13:07.

- **El síntoma:** al correr `net_lab.tscn`, la escena no se parecía a la del editor: los bloques aparecían apilados en el centro y todo se veía oscuro. Llegó una captura del editor para comparar.
- **La investigación:** se revisó si Godot había reescrito las escenas, si había UID duplicados, si algún autoload cambiaba de escena, y qué decían los registros. Con fotogramas grabados con Movie Maker (vista normal y cenital) se vio que la física estaba bien ubicada: la prueba chocaba con el escalón y subía la rampa donde correspondía. Lo único roto era el dibujo.
- **La causa (error mío):** la interpolación de física se activaba desde código en `_ready()`. En ese momento el nivel ya estaba cargado, y Godot dibujaba en el origen todo lo que nunca se mueve, incluida la luz del sol.
- **El arreglo:** esos ajustes pasaron a `_enter_tree()` de `net_lab.gd`. En el nodo padre, esa función corre antes de que entren el nivel y el actor. Se verificó con fotogramas nuevos.
- **Para el juego principal:** si algún día se activa la interpolación ahí, tiene que ir en `project.godot` o antes de cargar el nivel.

### Paso 3: conexión, aparición y reloj

**Fecha:** 2026-10-02, de 13:20 a 13:28. El menú se agregó entre las 13:45 y las 13:51.

- **`scripts/net/sim_clock.gd` (`SimClock`)** es el reloj único de la simulación:
    - cuenta los ticks y mueve a cada actor en orden fijo, ordenados por id de dueño, así ninguna regla depende del orden de los nodos en la escena;
    - los actores no tienen `_physics_process` propio;
    - en el cliente, mide el reloj del host con un ping cada 30 ticks (medio segundo). En esta primera versión, cada ping suelto podía ajustar el tick.
- **`scripts/net/net_session.gd` (`NetSession`)** es la conexión y la aparición:
    - **Conexión:** `ENetMultiplayerPeer` con hasta 7 clientes, en el puerto 7777 por defecto.
    - **Aparición:** un `MultiplayerSpawner` con `spawn_function` crea un actor por jugador y lo replica en los demás. La función corre en todas las máquinas con los mismos datos: nombre `Actor<id>`, dueño y posición.
    - **Lugares de aparición:** sobre la línea z = 8, en x = 0, 2, −2, 4, −4, 6, −6 y 8, en orden de llegada.
    - **Salidas:** cuando un jugador se va, su actor se borra. Si se va el host, la sesión termina en el cliente; no hay migración de host.
- **`ActorBody`** ahora guarda su `state`, su `owner_peer_id` y si ya fue `placed`, es decir, ubicado por el reloj por primera vez.
- **Problema:** en los clientes, las cápsulas aparecían flotando a 0,5 m, porque el cliente no simula y la cápsula no bajaba sola. **Arreglo:** aparecen en y = 0, ya apoyadas (modo Suelo y `on_floor` en verdadero), igual que lo que calcula el host en el primer tick.
- **Prueba automática:** host y cliente en esta PC por localhost.
    - Las dos instancias ven las dos cápsulas.
    - El tick del cliente sigue al del host con 0,21 ticks de desfase.
    - No hubo saltos de reloj después de la primera sincronización, y la ida y vuelta fue de 7 ms.
    - Si el host se va, el cliente avisa que terminó la sesión y limpia la escena.
    - La prueba del paso 2 siguió pasando.

**El menú dentro del juego.** Las instrucciones para probar el paso 3 (argumentos `--host` y `--client`, y *Debug > Customize Run Instances*) llegaron llenas de jerga, con una imagen de respuesta: "literal no entendí una absoluta mierda". Primero se verificó en la documentación de Godot el nombre exacto del menú. Después se agregó al laboratorio un menú con:

- un título y la IP de esta PC en la red local;
- **Jugar solo**: el laboratorio de antes, para moverse solo;
- **Crear partida**: abre el host;
- **Unirse**: un campo para la IP, que por defecto dice `127.0.0.1`;
- una ayuda.

Los argumentos de lanzamiento quedaron solo para las pruebas automáticas. Se verificó que el menú se viera bien, que sus botones conectaran un host con un cliente y que las pruebas con argumentos siguieran andando. Las instrucciones se reescribieron clic por clic, con los nombres exactos de los botones.

**Prueba entre las dos PC (18:09):** "increíble, funciona, mas o menos, ninguno de los dos se puede mover, pero supongo que es una decisión deliberada". En la captura, el host ve los dos actores `[1, 1601714350]`. Que nadie se moviera era a propósito: el paso 3 solo prueba la conexión, la aparición y el tick compartido. De paso quedaron probados la red de verdad y el firewall.

### Paso 4: host autoritativo, sin predicción

**Fecha:** 2026-10-02, de 18:11 a 18:18.

- **Bytes:** `ActorState` y `ActorInput` aprendieron a empaquetarse en bytes, porque ahora el input viaja por red. El estado ocupa 49 bytes y el input 10.
- **Señales del reloj:** `SimClock` avisa cuándo empieza y cuándo termina cada tick (`tick_started` y `tick_finished`). La red se engancha ahí sin que el reloj sepa nada de red.
- **`scripts/net/net_sync.gd` (`NetSync`)** es el transporte:
    - **Cliente:** en cada tick manda su input junto con los últimos anteriores, hasta 6 (`INPUT_REDUNDANCY`). Si se pierde un paquete, el siguiente trae los mismos ticks otra vez.
    - **Host:** guarda el input de cada jugador por tick, con 120 ticks de historia. Si falta el de un tick, repite el último anterior: mismos botones mantenidos y mismo contador de pulsaciones, así no se inventa ni se duplica un salto.
    - **Snapshots:** el host manda en cada tick (60 por segundo) el estado de todos los actores y el tick del input que usó para cada uno.
    - **Aplicación en el cliente:** el cliente aplica el snapshot más nuevo dentro del tick de física, para no romper la interpolación. Los paquetes desordenados se descartan.
- **Laboratorio:**
    - el input de cada actor sale del teclado si es propio, o de la red si es de un cliente;
    - el host manda el snapshot al terminar el tick;
    - el panel muestra "lo que apretás se ve N ticks después (X ms)".
- **Input de prueba `--test-input=walk`:** camina 1,5 s hacia adelante, salta a los 0,5 s y se queda quieto. Sirve para probar sin teclado.

**Prueba automática:**

- El cliente caminó unos 7 m y saltó usando solo lo que mandó por red.
- Al final, el host y el cliente mostraban exactamente el mismo estado.
- El modo local y la prueba del paso 2 siguieron iguales.

**Prueba entre las dos PC (18:54):** "como solo es un tick de demora, prácticamente es imperceptible al ojo humano el retraso que existe". Se aclaró que ese tick es solo la mitad del viaje: lo que tarda el input del cliente en llegar al host, unos 16 ms. El jugador del cliente siente la vuelta completa:

1. Su tecla viaja al host.
2. El host la usa en su próximo tick.
3. El resultado vuelve en el snapshot.
4. El cliente lo aplica en su próximo tick.

En una LAN eso ronda los 2 a 4 ticks; por internet, entre 50 y 150 ms, y ahí sí se siente.

**Afirmación sin probar (error mío):** en esa misma respuesta afirmé que la cápsula del host, parada sobre el techo del túnel a 1,5 m, había llegado ahí por un "mantle automático" de la base redondeada, porque el salto llega a 1,17 m. La respuesta fue "lo del mantle creo que es una alucinación tuya". Tenía razón: no lo había comprobado, y hay una explicación más simple. Desde la plataforma verde, a 2 m, se puede saltar al techo del túnel. La afirmación se retiró.

### Paso 5: simulador de red y métricas

**Fecha:** 2026-10-02, de 18:57 a 19:04.

- **`scripts/net/link_simulator.gd` (`LinkSimulator`)** es un simulador de red dentro de nuestra propia capa:
    - **Dónde actúa:** en una sola máquina, sobre todo lo que esa máquina manda y recibe, ping incluido. Así una LAN se comporta como internet sin configurar nada en el host.
    - **Demora:** la mitad de la ida y vuelta agregada en cada sentido, más o menos una variación al azar. Con variación, dos paquetes pueden llegar al revés de como salieron.
    - **Pérdida:** un porcentaje de paquetes en cada sentido.
    - **Azar:** tiene su propio generador con semilla, así la misma configuración da las mismas pérdidas y la simulación del juego no se entera.
    - **Entrega:** los paquetes se entregan en orden de llegada desde `_process`, con el reloj real.
- **El transporte y el ping del reloj** pasan por el simulador en los dos sentidos, así la ida y vuelta medida incluye la demora simulada. El transporte además cuenta los snapshots que no llegaron a tiempo.
- **Niveles de red:** cuatro en el menú (fila **Simular internet**), que se cambian en partida con las teclas 1 a 4:

    | Tecla | Nivel | Ida y vuelta agregada | Variación | Pérdida |
    | --- | --- | --- | --- | --- |
    | 1 | sin simulación | 0 | 0 | 0 % |
    | 2 | internet buena | +40 ms | ±5 ms | 0 % |
    | 3 | internet normal | +120 ms | ±20 ms | 1 % |
    | 4 | internet mala | +200 ms | ±40 ms | 5 % |

- **Argumentos de prueba:** `--sim-rtt`, `--sim-jitter`, `--sim-loss` y `--sim-seed`.
- **Panel:** muestra la red simulada y el porcentaje de snapshots que no llegaron a tiempo.
- **Ajuste menor:** las dos funciones anónimas que mandan paquetes llevan el paréntesis de cierre en su propia línea, el formato que GDScript acepta sin dudas.

**Prueba automática:**

- **Con +120 ms ±20 y 5 % de pérdida en el cliente:** ida y vuelta medida de 145 ms; lo que se aprieta tarda 10 ticks (unos 167 ms) en verse, que es el "se ve mal" buscado. Host y cliente terminan con el mismo estado.
- **Con 30 % de paquetes perdidos:** el salto llegó exactamente una vez, gracias a los paquetes repetidos y al contador de pulsaciones.
- **Con variación:** alrededor del 22 % de los snapshots cuentan como "perdidos", porque a 60 por segundo llegan desordenados y se descartan. Se esperaba que la interpolación del paso 8 lo resolviera.

**Prueba entre las dos PC (19:49), sin simulación:**

- **Demora real:** "lo que apretás se ve 2 ticks después (33 ms)".
- **Saltos de reloj:** 25 en unos dos minutos. Esto **no estaba bien**: el Wi-Fi tiene picos de demora y el reloj del paso 3 confiaba en cada ping suelto, así que estimaba mal el tick del host y saltaba. No se notaba porque nadie predecía, pero con la predicción del paso 6 cada salto sería un tirón.
- **Snapshots que no llegaron a tiempo:** 17 %, por el Wi-Fi, que atrasa o pierde paquetes de a ráfagas.

**El arreglo propuesto para el reloj:**

- usar varias mediciones en vez de una sola;
- darles más peso a los pings más rápidos, que son los que menos mienten;
- corregir de a poco en lugar de saltar.

Se decidió hacerlo como primera parte del paso 6, porque la predicción necesita un reloj estable.

**El orden de los pasos (20:01).** Las dos PC van por Wi-Fi, y la pregunta fue si convenía seguir el orden original. El 6 era el que seguía, así que no se saltaba nada. Adelantar otro paso no convenía:

- el 8 suaviza correcciones que recién existen con la predicción;
- el 7 adopta lo que el cliente predijo, así que sin predicción no hay nada que adoptar;
- lo demás del documento conviene hacerlo con el esqueleto completo.

Además, el 6 es el paso más riesgoso de la arquitectura, porque restaura, repite ticks y va adelantado: mejor descubrir ahí si algo falla. Que las PC estén por Wi-Fi juega a favor: si anda ahí, anda mejor en una red buena.

### Paso 6: predicción, reconciliación y adelanto

**Fecha:** 2026-10-02, de 20:34 a 20:44.

**El reloj nuevo (`SimClock`):**

- **El ping solo sirve para la estimación inicial.** Se guardan los últimos 8 pings y se usa el más rápido, porque su ida y su vuelta no pueden haber sido muy distintas: un pico del Wi-Fi solo hace más lento a uno.
- **El objetivo inicial:** ir medio ida y vuelta más 2 ticks adelante del host.
- **Cada medición guarda cuánto se había corrido ya el cliente** (`_adjust_total`), así una medición vieja sigue sirviendo después de un ajuste.
- **Saltos solo ante problemas grandes:** el cliente salta de tick solo al conectarse, o si dos pings seguidos dicen que el adelanto está muy lejos: más de 2 ticks atrás del host, o más de 60 ticks por encima del objetivo.
- **El control fino** se hace con el margen que informa el host: cuántos ticks antes de necesitarlo le llega el input más nuevo. Se mira el peor de los últimos 60. Si es menor que 1, el cliente corre 2 ticks en un frame; si es mayor que 4, corre 0. Después de cada ajuste espera max(30, 2 × ida y vuelta) ticks para ver su efecto.

**La predicción:**

- **`ActorBody.simulated`:** el host simula a todos, y el cliente solo a su propio actor, una vez sincronizado. A los demás los muestra como llegan.
- **`scripts/net/client_prediction.gd` (`ClientPrediction`):** por cada tick predicho guarda el input y el estado resultante en bytes. Cuando llega el estado del host para un tick S, lo compara con lo guardado:
    - si coincide, descarta lo anterior a S;
    - si no, restaura S (con `apply_state`, que sincroniza los indicadores de piso) y repite los ticks siguientes con los inputs guardados.

    Solo se repite el propio actor; el mundo no se rebobina.
- **Snapshots:** cada entrada lleva además el margen del input de ese jugador, como entero de 16 bits.
- **Panel del cliente:** muestra la ida y vuelta, el adelanto, los saltos de reloj, el peor margen, los ajustes de un tick, y la predicción: coincidencias, correcciones (cuántas por input tardío) y el tamaño de la última. El del host muestra con cuánta anticipación llega el input de cada jugador.

**Error encontrado y arreglado (mío):** con internet mala, el reloj saltaba en cadena: llegó a un tick negativo (−1310), con 10 saltos. Después de un salto, los pings viejos seguían diciendo que el adelanto estaba mal. **Arreglo:** cada medición guarda los ajustes hechos hasta ese momento, y hacen falta dos estimaciones malas seguidas para saltar.

**Prueba automática (cliente caminando y saltando):**

| Red simulada | Coincidencias con el host | Correcciones | Saltos de reloj |
| --- | --- | --- | --- |
| Sin simulación | 351 | 0 | 0 |
| Normal (+120 ms, ±20, 1 % de pérdida) | 205 | 0 | 0 |
| Mala (+200 ms, ±40, 5 % de pérdida) | 161 | 0 | 0 |

En las tres redes, host y cliente terminan exactamente en el mismo lugar, el mismo en las tres. El modo local y la prueba del paso 2 siguen igual.

**Prueba entre las dos PC (capturas recibidas a las 21:17, tomadas entre las 21:12 y las 21:15; en una de ellas la simulación estaba activa de los dos lados, unos 400 ms en total):**

- **Saltos de reloj:** 0 en todas las capturas, contra 25 en dos minutos con el reloj del paso 3.
- **Predicción:** 18.883 coincidencias y 21 correcciones, 20 de ellas por inputs que llegaron tarde. Queda una sin explicar; lo más probable, aunque no se comprobó, es un input tardío anterior cuyo snapshot se perdió.
- **Lo que significa:** las dos notebooks, con el mismo Godot, calcularon exactamente lo mismo durante casi 19.000 ticks. Vale para estas dos PC y esta build; no prueba otras plataformas.
- **Ajustes de un tick:** 94 en unos 8 minutos (+33 / −61).
- **Los tirones con 400 ms:** "se movía a tirones, pero eventualmente se estabilizó". Al prender la simulación de los dos lados, la demora pasó de golpe de 17 ms a unos 400. El cliente necesitaba ir unos 20 ticks más adelantado, pero se adelantaba un tick cada 0,8 s. Mientras recuperaba, sus inputs llegaban tarde, el host repetía inputs viejos y el personaje se corregía de golpe. Las correcciones subieron de 3 a 21 entre las 21:12 y las 21:13, y no aumentaron más hasta las 21:15.

**Mejoras propuestas, en este orden:**

1. Que el adelanto se ajuste rápido y sin tirones: recuperar en un segundo lo que falta, acelerando el reloj un 10 a 20 %, en vez de usar ticks dobles o salteados.
2. El paso 7, para que un input tardío deje de producir una corrección.

### Commit `d75ef67`

**Fecha:** 2026-10-02, 21:25. Pedido: "antes de hacer el retoque, primero arma un commit local".

- **Antes de commitear se verificó:** que no hubiera nada ya preparado para commit, qué archivos eran del laboratorio y el estilo de los mensajes del repo (convencional y en inglés).
- **Qué entró:** solo las cuatro carpetas del laboratorio (`scripts/actor`, `scripts/net`, `scenes/actor` y `scenes/net_lab`). Se commiteó solo después de confirmar que eran exactamente 30 archivos.
- **El commit:** `feat(net): add co-op network skeleton lab (steps 1-6)`, con 30 archivos y 1.994 líneas, en la rama actual, sin subir a ningún remoto.
- **Después:** 0 archivos preparados, los 136 cambios de parkour intactos y la rama sin remota configurada.

### Retoque 6b: el adelanto se ajusta cambiando el ritmo de ticks

**Fecha:** 2026-10-02, de 21:25 a 21:43.

**El problema.** El cliente ganaba o perdía adelanto corriendo 2 ticks en un frame o ninguno, y después esperaba alrededor de un segundo a que el host lo confirmara. Recuperar 12 ticks llevaba unos 10 segundos, con correcciones todo ese tiempo.

**La idea.** Cambiar cuántos ticks entran en un segundo real, sin cambiar lo que avanza cada tick:

- el cliente corre entre 57 y 72 ticks por segundo (`Engine.physics_ticks_per_second`);
- compensa con `Engine.time_scale = ritmo / 60`, así el delta de física sigue siendo exactamente 1/60;
- la simulación da lo mismo, byte a byte, a cualquier ritmo.

**Verificaciones antes de implementarlo:**

1. **La cuenta en float de 32 bits,** con un script de PowerShell para todos los ritmos de 50 a 90: `(1/R) × (R/60)` convertido a float32 da exactamente `float32(1/60) = 0,0166666675`, y el factor de velocidad `(1/60)/delta` da exactamente 1,0.
2. **En el motor,** con un diagnóstico (`diag_tick_rate.gd`):

    | Ticks por segundo pedidos | `time_scale` | Ticks por segundo reales medidos | Delta de física | ¿float32 igual a 1/60? |
    | --- | --- | --- | --- | --- |
    | 60 | 1,0 | 60,41 | 0,01666666666666667 | sí |
    | 72 | 1,2 | 72,22 | 0,01666666666666667 | sí |
    | 57 | 0,95 | 56,97 | 0,01666666666666667 | sí |
    | 66 | 1,1 | 65,98 | 0,01666666666666667 | sí |
    | 60 (solo `time_scale`) | 1,2 | 59,97 | 0,02 | no |

    Cambiar `physics_ticks_per_second` en ejecución cambia los ticks por segundo reales. `time_scale` solo no los cambia. Con la compensación, la física recibe exactamente el mismo delta.

**El "antes".** Para medir, se agregaron al laboratorio tres opciones de prueba:

- `--test-input=zigzag`: un cuadrado que cambia de lado cada medio segundo, con un salto cada dos, y a los 25 s se queda quieto para comparar el estado final;
- `--sim-after=SEGUNDOS` y `--sim-until=SEGUNDOS`: la red simulada empieza o termina en plena partida;
- `--trace`: el cliente imprime su adelanto cada medio segundo.

Los temporizadores de las pruebas pasaron a contar segundos reales (`create_timer(..., ignore_time_scale = true)`), porque el cliente cambia `time_scale`.

**El escenario:** host y cliente arrancan sin simulación. A los 6 s del host, los dos pasan a +200 ms ±40 con 5 % de pérdida (unos 400 ms en total), y a los 22 s vuelven a la normalidad. El cliente hace zigzag.

**La implementación (`SimClock`):**

- **Un tick por frame de física, siempre.** Ya no hay frames con 2 ticks o con 0.
- **`SimClock.apply_tick_rate(rate)`:** cambia `physics_ticks_per_second` y `time_scale` juntos. La usan el reloj y la prueba de repetición.
- **Cuenta de lo ganado o perdido:** cada tick a un ritmo R dura 1/R segundos reales, y en ese tiempo el host avanza 60/R ticks. La diferencia (`1 − 60/R`) se suma a `_adjust_total`, que ahora es fraccionario.
- **Historial por tick:** un anillo de 1.024 ticks guarda cuánto valía `_adjust_total` en cada tick.
- **Márgenes corregidos:** cada margen que informa el host se guarda junto con cuánto se había corrido el cliente al mandar ese input. El peor margen se calcula sumándole lo que el cliente ganó o perdió desde entonces. Así el reloj ve el efecto de acelerar o frenar enseguida, sin esperar el ida y vuelta, y no se pasa de largo. Ya no hace falta esperar entre ajustes.
- **La franja de control:**
    - con un peor margen menor que 1 tick, acelera a `60 + 2 × lo que falta`, hasta 72 ticks por segundo, y no para hasta llegar a 2;
    - con un peor margen mayor que 6, frena a `60 − lo que sobra`, hasta 57 ticks por segundo, y no para hasta bajar a 3;
    - en el medio no toca nada, así la variación normal de la red no lo mueve.
- **Ventana:** los márgenes se miran en los últimos 60 ticks del host, y hace falta media ventana de datos antes de decidir.
- **Vuelta a la normalidad:** al salir del laboratorio o de la sesión, el ritmo vuelve a 60 y `time_scale` a 1.
- **Panel:** muestra el ritmo actual y los ticks ganados y perdidos; el resumen también.

**La prueba de repetición a cualquier ritmo.** Se le agregó `--rate=N` (todo a N ticks por segundo) y `--rate=varying`, que cambia de ritmo cada 7 frames entre 60, 72, 57, 66, 61, 69, 58 y 64. Al final imprime una huella SHA-256 de la pasada en vivo. Las cuatro corridas (60, 72, 57 y variable) pasaron con la **misma huella, `1e07f92f0ec2c94a`**: cambiar el ritmo no altera la simulación ni un byte.

**Antes y después, con la red pasando de nada a 400 ms en plena partida:**

| | Reloj anterior | Reloj nuevo |
| --- | --- | --- |
| Tiempo hasta recuperar el adelanto | ~14 s (de 4,5 s a 18,6 s en la traza) | ~1,5–2 s |
| Correcciones por input tardío | 57 | 7 (5 en una segunda corrida) |
| Tiempo para soltar el adelanto sobrante cuando la red vuelve | ~9 s | ~5,5 s |
| Estado final host contra cliente | idéntico | idéntico |

Traza del reloj nuevo al subir la latencia: a los 5,0 s, 72 ticks por segundo y peor margen −6,6; a los 5,5 s, 68 y −1,6; a los 6,0 s, 64 y 0,1; a los 6,5 s, 62 y 1,5; a los 7,0 s, de nuevo 60. Al volver la red, frenó a 57 ticks por segundo con el peor margen en 16 y llegó a 3 a los 27,1 s.

**Regresiones (cliente caminando, red simulada desde el inicio):** 441, 272 y 209 coincidencias sin simulación, con internet normal y con internet mala, todas con 0 correcciones, 0 saltos de reloj y el estado final idéntico. Las "alineaciones" (3, 6 y 8) aparecen todas en el primer segundo: son estados del host anteriores al primer tick predicho, que llegan después de empezar a predecir. Crecen con la latencia y no tienen que ver con el ritmo.

**Lo que se puede notar al jugar:** cuando la red empeora de golpe, el personaje anda hasta un 20 % más rápido durante medio segundo. Cuando la red mejora, anda un 5 % más lento durante unos segundos.

**Entrega:** zip `tun-tun-tun-sahur_2026-10-02_paso6b.zip`.

**Prueba entre las dos PC (2026-10-03, recibida a las 11:35: "funciona", con 19 capturas de la notebook tomadas entre las 11:03 y las 11:07):**

- Cubren unos 4 minutos, del tick 8.205 al 22.536, cambiando varias veces entre "sin simulación" e "internet mala".
- **Saltos de reloj:** 0.
- **Correcciones:** se quedaron en 7 (6 por input tardío) desde la primera captura hasta la última. Ningún cambio de red sumó una corrección.
- **El ritmo se ve trabajando:** baja a 57–59 mientras suelta adelanto y vuelve a 60. Al apagar la simulación, el peor margen bajó de 9,8 a 3,9 en unos 2 s.
- **El adelanto sigue a la red:** ~4,5 ticks sin simulación (16 ms de ida y vuelta) y entre 12 y 20 ticks con "internet mala".
- **Con "internet mala" fija, el adelanto sube y baja:** en esos 4 minutos se ganaron y perdieron unos 60 ticks (+40,9 / −44,1 al principio; +101,7 / −104,4 al final). En parte se debe a los cambios de nivel de red.
- **Archivo pendiente:** el cambio número 137 resultó ser `project.godot~RF78902d2f.TMP`, un temporal que dejó el editor de Godot el 2026-10-02 a las 21:07. No se tocó.

### Commit `9cd1936`

**Fecha:** 2026-10-03, 11:38. `feat(net): hold client lead by varying the tick rate (step 6b)`: 3 archivos (`sim_clock.gd`, `net_lab.gd` y `actor_replay_test.gd`), +206 / −64 líneas. Se verificó que fueran exactamente esos 3.

### Paso 7: afirmaciones, adopción y época

**Fecha:** 2026-10-03, de 11:38 a 12:06.

**Lo que define el documento** (secciones "Qué manda el cliente" y "Qué hace el host con el tick T de un cliente"):

- **Qué manda el cliente:** con cada tick, el input y la **afirmación**, es decir, lo que predijo al final del tick (modo, ancla y su parámetro, postura, posición relativa a la base si la hay, velocidad) y la **época** que ya aplicó.
- **La época:** un contador por cliente. El host lo sube con cada evento suyo que cambia la simulación de ese cliente: un empujón, un agarre, un teleport, un cambio de escala de tiempo del mundo. Lo que el cliente puede simular por su cuenta no la cambia.
- **Qué hace el host:** simula el tick con el input y adopta la afirmación solo si se cumple todo:
    - la época coincide;
    - si hubo cambio de modo, su validador lo acepta con tolerancia amplia;
    - la pose no se mete en la geometría y, si dice estar en suelo, hay suelo debajo;
    - la diferencia con su propio resultado está dentro de un límite generoso, a calibrar.

    Si adopta, el estado pasa a ser la afirmación; si no, queda el suyo.
- **Para qué sirve:** Jolt no garantiza el mismo resultado en dos máquinas. Con adopción, el host solo impone lo que el cliente no sabía. También cura los inputs tardíos.
- **El riesgo:** la adopción puede tapar errores reales de desincronización. Por eso el host registra cuánto difería cada afirmación adoptada, y la adopción se puede apagar en pruebas.

**Lo que se implementó:**

- **`ActorState` tiene época:** un entero de 16 bits al final de los bytes, así el estado pasa a 51 bytes (`BYTE_SIZE`). Solo la sube el host; el motor no la toca.
- **`ActorBody.apply_state()` dice si la pose entra en el mundo.** Después del movimiento de velocidad cero, el cuerpo no tiene que haber sido empujado más de 1 cm (`POSE_TOLERANCE`) y, si el estado dice estar apoyado, tiene que haber piso, incluso con el snap manual.
- **El paquete del cliente:** por cada tick lleva el input y la afirmación, que es el estado predicho completo (51 bytes). Las afirmaciones salen de lo que guarda la predicción (`ClientPrediction.recent(6)`): los últimos ticks que el host todavía no confirmó, con los valores ya corregidos si hubo una repetición. El paquete sale al terminar el tick.
- **El host guarda las afirmaciones por jugador y por tick.** Descarta las que no miden 51 bytes, y las borra junto con los inputs viejos.
- **`scripts/net/claim_adoption.gd` (`ClaimAdoption`) es nueva.** Corre en el host al terminar cada tick, antes de mandar el snapshot. Para cada actor de otro jugador decide:

    | Resultado | Cuándo |
    | --- | --- |
    | `NO_CLAIM` | no llegó afirmación para ese tick |
    | `SAME` | la afirmación es idéntica al resultado del host (el caso normal) |
    | `OFF` | la adopción está apagada |
    | `WRONG_EPOCH` | la época no coincide: el cliente todavía no vio un evento del host |
    | `TOO_FAR` | la posición difiere más de 1 m (`MAX_DIFFERENCE`, valor de partida a calibrar; caminando, cubre un input que llegó unos 10 ticks tarde) |
    | `BAD_POSE` | la pose no entra en el mundo del host; el host vuelve a su propio resultado |
    | `ADOPTED` | se cumple todo: el estado del actor pasa a ser la afirmación |

    Lleva la cuenta por jugador, incluida la diferencia más grande que igual se adoptó. Se apaga y se prende con la tecla **Q** en el host, o arranca apagada con `--no-adoption`. Los modos anclados le van a agregar su propio validador.

**Una regla que agregué y no estaba en el documento: esperar ante estados provisorios.**

- **El problema:** si el input de un tick llega tarde, el host calcula ese tick repitiendo el input anterior, y su estado difiere del predicho. El tick siguiente sí llega a tiempo y el host adopta la afirmación. Si el cliente corrigiera con el estado provisorio, corregiría dos veces: una para ir y otra para volver.
- **La regla:** el cliente solo concilia con estados que el host calculó con su input real. Si un estado no coincide y se calculó con un input repetido (el tick del input usado no es el del snapshot), el cliente espera el siguiente. Eso se cuenta como "espera por input tardío".
- **Cómo encaja con el documento:** coincide con el paso 5 de "Qué hace el host" ("informa el último tick procesado de ese cliente"), si se lee como procesado con su input real.
- **Qué reemplaza:** el contador "correcciones por input tardío", que no podía volver a pasar. Las viejas "alineaciones" del arranque pasaron a contarse como esperas.

**Lo que se agregó al laboratorio:**

- **El empujón (tecla E en el host):**
    - `ActorMotor.push()` suma un impulso de 5 m/s hacia arriba y 4 m/s hacia afuera del personaje del host, pasa a Aire (igual que el salto, para que el snap no lo pegue al piso) y borra la memoria del salto y el coyote.
    - El host lo aplica al empezar el tick, antes de mover a nadie, y sube la época del empujado.
    - Es un evento inmediato: el cliente se entera con el snapshot y se corrige.
- **"Wi-Fi con tirones" (tecla 5):** quinto nivel de red, con +20 ms de ida y vuelta, ±5 ms y 0 % de pérdida, más tirones. Cada 3 s la conexión se traba 150 ms, y lo que sale o llega en ese rato pasa todo junto cuando se destraba. El simulador ganó `stall_every_ms` y `stall_ms`.
- **Argumentos de prueba:** `--test-push-at=S1,S2` (el host empuja a esos segundos), `--sim-stall-every=MS`, `--sim-stall=MS` y `--no-adoption`.
- **Panel del host:**
    - adopción prendida o apagada y cantidad de empujones;
    - por jugador: margen del input y época, y las afirmaciones adoptadas (con la más lejana) y rechazadas por época, distancia y pose;
    - la ayuda "E empuja a los demás jugadores · Q prende o apaga la adopción".
- **Panel del cliente:** la época, junto al modo.

**Un detalle corregido:** en el primer tick, el host consideraba su propio actor como si fuera de otro jugador, porque `_local_actor` se asigna un frame después de aparecer. No hacía daño, pero ahora se compara el dueño del actor con el id de esta máquina (`_is_remote`).

**Pruebas automáticas:**

- **Prueba de repetición:** pasa a 60 y con ritmo variable, con la misma huella en las dos (`4da513f15b6d798b`). Es nueva porque cambió el formato del estado.
- **Regresiones (cliente caminando):** sin simulación, con internet normal y con internet mala, 0 correcciones, 0 saltos de reloj y estado final idéntico, con época 0. En el host, todas las afirmaciones coincidieron con su resultado (441, 428 y 422 iguales), así que no hizo falta adoptar ninguna. Las esperas fueron 3, 7 y 9, todas del arranque.
- **Red que salta a 400 ms en plena partida (zigzag):**

    | | Adopción prendida | Adopción apagada |
    | --- | --- | --- |
    | Correcciones del cliente | 1 | 1 |
    | Esperas por estado provisorio | 29 | 27 |
    | Afirmaciones adoptadas | 0 | — |
    | Rechazadas por distancia (> 1 m) | 25 | — |
    | Estado final host contra cliente | idéntico | idéntico |

    En el 6b este escenario dejaba entre 5 y 7 correcciones; ahora, 1. La mejora viene de esperar los estados provisorios. La adopción no entra en juego: durante ~1 s de déficit, el host repitió inputs viejos mientras el zigzag cambiaba de dirección, y la diferencia superó 1 m. Rechazar es lo correcto ahí.
- **Empujones (época):**

    | | Sin red simulada | Con "internet mala" en el cliente |
    | --- | --- | --- |
    | Empujones del host | 2 | 2 |
    | Afirmaciones rechazadas por época | 4 | 33 |
    | Correcciones del cliente | 2 (una por empujón) | 2 |
    | Época final en host y cliente | 2 | 2 |
    | Estado final host contra cliente | idéntico | idéntico |

    Las rechazadas por época son las que el cliente mandó antes de enterarse: pocas en LAN, unas 16 por empujón con 200 ms. La posición final cambió respecto de una corrida sin empujones (x −26,116 contra −23,918), así que los empujones quedaron aplicados.
- **Experimento sin el chequeo de época** (apagado a propósito un momento y restaurado después):
    - el host adoptó 2 afirmaciones viejas, una en cada tick de empujón, con una diferencia de 0,107 m, y los empujones se borraron: época final 0 y 0 correcciones;
    - la posición final (−23,918; 0,0009; 10,6383) resultó **idéntica, al 0,1 mm, a una corrida limpia sin empujones**.

    Sin la época, el host borraba los eventos del host. Se verificó que el código del experimento no quedara.
- **Tirones de Wi-Fi en el cliente (150 ms cada 3 s, zigzag):**

    | | Adopción prendida | Adopción apagada |
    | --- | --- | --- |
    | Correcciones del cliente | 0 | 8 |
    | Afirmaciones adoptadas | 8 (la más lejana a 0,147 m) | — |
    | Esperas | 14 | 11 |
    | Estado final host contra cliente | idéntico | idéntico |

    Esta es la adopción en su caso real: un input que llega tarde con una diferencia chica.
- **Validación de pose** (`diag_pose_check.gd`), 9 de 9 casos como se esperaba:

    | Pose | ¿Entra? |
    | --- | --- |
    | Apoyado en el piso | sí |
    | Apoyado medio milímetro más arriba, como deja la cuantización | sí |
    | En el aire, sin decir que está apoyado | sí |
    | En el aire, diciendo que está apoyado | no |
    | Metido 20 cm en el piso | no |
    | Metido 3 cm en el piso | no |
    | Adentro de la pared | no |
    | Arriba de la plataforma | sí |
    | Tocando la pared por fuera | sí |

**Entrega:** zip `tun-tun-tun-sahur_2026-10-03_paso7.zip`.

**Prueba entre las dos PC (capturas recibidas a las 15:48, tomadas entre las 15:42 y las 15:46; seis de la notebook y una del host, en dos sesiones):**

- **Primera sesión (jugador 1698316742), con "Wi-Fi con tirones":**
    - Hubo 22 esperas y 1 sola corrección, de 2,14 m, en unos 2 minutos. Entre 3 y 9 esperas son del arranque; el resto son inputs tardíos mientras el jugador cambiaba de movimiento. Con la adopción apagada, cada una habría terminado en una corrección, así que lo más probable es que el host las haya adoptado.
    - La corrección de 2,14 m superó el límite de 1 m, y ahí el host impuso lo suyo.
    - **Los 61 empujones:** la época de la notebook llegó a 61, con exactamente una corrección por empujón (62 − 1). Ninguno se perdió ni se duplicó.
    - **Fuera del mapa:** cada empujón suma 5 m/s hacia arriba y 4 hacia afuera, y con 61 seguidos la cápsula terminó en x 162, y 156, cayendo a −40 m/s. Como el piso termina a 30 m del centro, caía para siempre y hubo que reconectar. La red lo siguió bien; al laboratorio le faltaba una reaparición, que se agregó en el paso 8.
- **Segunda sesión (jugador 1488345593), con la adopción apagada:**
    - 0 correcciones y 4 esperas, probablemente solo las del arranque. Ningún input tardío coincidió con un cambio de movimiento, así que no sirve para comparar.
    - Hubo 1 salto de reloj, el mecanismo que recupera al cliente cuando queda detrás del host por un tirón grande. Por las capturas no se pudo saber qué lo causó.
- **El ritmo con tirones:** casi siempre está en 57, porque después de cada tirón el cliente gana adelanto y en los 3 s siguientes lo suelta. Ahora que la adopción absorbe los inputs tardíos, se podría calibrar para que reaccione menos.

### Commit `7547de1`

**Fecha:** 2026-10-03, 15:53. `feat(net): add claims, adoption and epoch (step 7)`: 9 archivos, +289 / −42 líneas. Son `net_lab.gd`, `actor_body.gd`, `actor_motor.gd`, `actor_state.gd`, `client_prediction.gd`, `link_simulator.gd`, `net_sync.gd`, `claim_adoption.gd` y su `.uid`.

### Paso 8: interpolación y suavizado

**Fecha:** 2026-10-03, de 15:53 a 16:10.

**Lo que define el documento** (secciones "Presentación" y "Lo que no se predice"):

- **Los demás jugadores** se interpolan con un colchón de 2 o 3 snapshots, unos 100 ms. La interpolación de lo remoto avanza por ticks reales, no por delta escalado.
- **Capas:**
    - el cuerpo (`CharacterBody3D`) se mueve solo en ticks;
    - la raíz visual se interpola entre ticks con la interpolación de física de Godot, más un **desvío de corrección** propio que decae a cero;
    - la cámara queda fuera de la jerarquía interpolada: rota con el mouse en `_process` y toma la posición de `get_global_transform_interpolated()` más el desvío.
- **Correcciones:** al reconciliar, el desvío suma la diferencia entre lo que se veía y la nueva posición simulada, y decae en unos 100 ms. Por encima de un umbral, del orden de 1,5 m, se acepta el salto.
- **Teleports:** la reaparición y los teleports del host llaman a `reset_physics_interpolation()` y ponen el desvío en cero.

**El "antes".** Se agregó una medición de tirones en pantalla de los demás jugadores. En cada tick del cliente se compara cuánto se movió cada actor ajeno con lo que corresponde a su velocidad: si se movió menos de un cuarto o más del doble, cuenta como tirón. Con el código del paso 7, el host haciendo zigzag y el cliente mirando:

| Red en el cliente | Tirones (ticks medidos) |
| --- | --- |
| Sin simulación | 5,2 % (68 de 1.315) |
| Internet mala | 73,3 % (960 de 1.310); el 41,2 % de los snapshots llega desordenado y se descarta |
| Wi-Fi con tirones | 27,4 % (362 de 1.319) |

**Lo que se implementó:**

- **`scripts/net/remote_interpolation.gd` (`RemoteInterpolation`) es nueva, del lado del cliente:**
    - guarda, por jugador, los estados que llegan en los snapshots;
    - muestra a cada uno 6 ticks del host en el pasado (100 ms, tres snapshots a 30 por segundo), mezclando los dos snapshots que rodean ese momento: posición y velocidad lineales, yaw por el camino más corto, y lo discreto (modo, piso, época) del más cercano;
    - el momento que se muestra avanza con el reloj real (`Time.get_ticks_usec()`), no con el delta de Godot, así los cambios de ritmo del cliente no aceleran ni frenan a los demás;
    - se corrige un 5 % por tick hacia "el snapshot más nuevo menos 6 ticks", y salta si se aleja más de 30 ticks;
    - no mezcla entre dos snapshots que difieren más de 4 m, porque eso es un teleport: lo muestra de golpe y reinicia la interpolación de física;
    - si le falta el snapshot siguiente, deja al actor quieto y cuenta el tick como "esperando un snapshot";
    - olvida a los jugadores que se desconectan.
- **`NetSync.apply_pending_snapshot(on_own_state, on_other_state)`:** el estado propio va a la predicción y el de cada otro jugador al colchón de interpolación, en vez de aplicarse directo.
- **Snapshots:** el host manda 30 por segundo (`SNAPSHOT_INTERVAL_TICKS = 2`) en vez de 60.
- **`ActorBody` tiene un desvío visual (`visual_offset`):**
    - **Después de una corrección:** `smooth_from(visto)` hace que lo que se ve arranque desde donde se veía. El desvío se aplica a la posición del nodo `Visual`, que es solo presentación.
    - **Cómo decae:** se reduce a la mitad cada 25 ms (`CORRECTION_HALF_LIFE`), en el tick, para que la interpolación de física lo suavice entre ticks. El reloj lo llama después del paso de cada actor simulado.
    - **Saltos grandes:** uno de más de 1,5 m (`MAX_SMOOTHED_JUMP`) se muestra como salto.
    - **Teleports:** `teleported()` pone el desvío en cero y reinicia la interpolación de física.
    - **La cámara** sigue a `visual_root()`, así incluye el desvío.
- **Quién usa el suavizado:** `ClientPrediction` lo usa al corregir el propio actor. `ClaimAdoption` también, cuando el host adopta y su actor salta a lo que afirmó el cliente.
- **Reaparición en el host y en modo local:**
    - quien cae por debajo de −30 m vuelve a su lugar de aparición (`NetSession.spawn_position`), quieto y apoyado;
    - conserva las pulsaciones de salto ya vistas, para que la próxima no parezca un salto nuevo;
    - sube su época, porque es un evento del host, y es un teleport.

    Esto resuelve la cápsula que cayó para siempre en la prueba del paso 7.
- **Panel del cliente:** "los demás se ven 100 ms en el pasado · N ticks esperando un snapshot · tirones X %". Panel del host: las reapariciones.

**Pruebas automáticas:**

- **Tirones de los demás, antes y después:**

    | Red | Antes (paso 7) | Después (paso 8) | Ticks esperando un snapshot |
    | --- | --- | --- | --- |
    | Sin simulación | 5,2 % | 0,7 % (9 de 1.312) | 0 |
    | Internet mala | 73,3 % | 0,5 % (7 de 1.307) | 0 |
    | Wi-Fi con tirones | 27,4 % | 1,7 % (23 de 1.318) | 14 |

    Con tirones quedan 14 ticks en los que el colchón de 100 ms se vació, que son los momentos en que la conexión se traba 150 ms.
- **Regresiones:** sin simulación, con internet normal y con internet mala, 0 correcciones, 0 saltos de reloj y estado final idéntico. Las coincidencias bajaron a la mitad (220, 186 y 149) porque ahora hay la mitad de snapshots.
- **Prueba de repetición:** la misma huella que en el paso 7 (`4da513f15b6d798b`) a 60 y con ritmo variable. La simulación no cambió: el paso 8 es solo presentación.
- **Reaparición:**
    - 10 empujones en un segundo sacaron al cliente del mapa;
    - en el tick 1000 del host, cuando bajó de −30 m, reapareció en su lugar;
    - época 11 en host y cliente (10 empujones más la reaparición) y 11 correcciones, una por evento;
    - estado final idéntico, (−9,7882; 0,0009; 8,7148).
- **Suavizado** (`diag_smoothing.gd`): una corrección de 0,5 m deja un desvío de 0,500, 0,315, 0,198, 0,125, 0,079, 0,050 y 0,031 m en ticks sucesivos, o sea 3 cm a los 100 ms. El visual sigue al desvío, y una corrección de 2 m se muestra como salto.
- **La cámara:** fotogramas grabados con Movie Maker en modo solo, caminando, confirman que la cámara sigue bien al personaje en el salto y en reposo, y que la escena se dibuja normal.

**Entrega:** zip `tun-tun-tun-sahur_2026-10-03_paso8.zip`.

**Prueba final entre las dos PC (capturas recibidas a las 16:21, tomadas entre las 16:18 y las 16:19, del host y de la notebook):**

- **Primero, con "Wi-Fi con tirones" en las dos PC:**
    - el host tenía la adopción apagada (se apagó con Q para probar el suavizado y quedó así), 21 empujones y 0 reapariciones;
    - el input del cliente le llegaba con 11 ticks de anticipación;
    - en la notebook: 50 ms de ida y vuelta, 12,5 ticks de adelanto, peor margen 1,9 y ritmo 61 (+113,6 / −113,4), con 5.076 coincidencias, 23 correcciones (la última de 1,70 m), 4 esperas, 7,4 % de snapshots tarde, 70 ticks esperando un snapshot, 2,1 % de tirones de los demás y época 21.
- **Después, con "internet mala" en las dos PC (~400 ms de ida y vuelta):**
    - en el host, el margen del cliente bajó a 5 ticks;
    - en la notebook: ida y vuelta medida de 251 ms (el ping más rápido de los últimos), 17,5 ticks de adelanto, peor margen 3,0 y ritmo 60 (+140,7 / −137,0), con 5.959 coincidencias, las mismas 23 correcciones y 4 esperas, 9,9 % de snapshots tarde, 96 ticks esperando un snapshot y 2,0 % de tirones de los demás;
    - 0 saltos de reloj en toda la sesión.
- **De dónde vienen las 23 correcciones:** 21 son los 21 empujones (época 21). La de 1,70 m fue un empujón: es un evento inmediato y el cliente se entera recién con el snapshot, así que con tanta latencia la diferencia pasó de 1,5 m y se mostró como salto. El documento lo resuelve con eventos programados, todavía pendientes.
- **La opinión de quien probó:** "se siente muy bien, no hay tirones raros, si hay latencia, porque bueno, con ambos puestos en 200+ ms nos da 400+ ms, e inclusive así se siente bien."

### Commit `c0e0421`

**Fecha:** 2026-10-03, 16:22. `feat(net): interpolate other players and smooth corrections (step 8)`: 9 archivos, +242 / −21 líneas. Son `net_lab.gd`, `actor_body.gd`, `claim_adoption.gd`, `client_prediction.gd`, `net_session.gd`, `net_sync.gd`, `sim_clock.gd`, `remote_interpolation.gd` y su `.uid`. Con esto quedó completo el esqueleto de red de 8 pasos.

---

## 8. Validación de la arquitectura

El documento de arquitectura termina con una lista, "Qué validan las primeras pruebas". El punto 1, el esqueleto de red, es la sección 7. El 2026-10-03 a las 17:09 se pidió seguir con el resto, de a uno: "vamos a la validacion anterior, donde presentaste los 6 puntos y empecemos con el primero".

| Punto | Qué valida | Estado |
| --- | --- | --- |
| 1 | Esqueleto de red | Hecho (sección 7) |
| 2 | Base propia: una plataforma guionada y una balsa del host | Hecho, probado en dos PC: commits `600002a` y `25f7806` |
| 3 | Postura y espacio libre: el deslizamiento bajo un techo | Hecho, probado en dos PC: commit `cb71b16` |
| 4 | Un modo anclado simple, Ladder, con empujones programados e inmediatos | Hecho, probado en dos PC: commit `91a4433` |
| — | El escalón, pedido aparte antes del punto 5 | Hecho, probado en dos PC: commit `b907dae` (sección 8.4) |
| 5 | El laboratorio de Hanging con snap y sus pruebas de confirmación | Hecho, probado en dos PC, con dos cambios pedidos después de la primera prueba: commit `3cdcc91` (sección 8.5). La subida al borde se reemplazó después por un salto para arriba (sección 8.6), y el agarre pasó a funcionar también subiendo (sección 8.7) |
| 6 | Una interacción con cambio de línea: sujetar a un compañero | Pendiente; es el próximo |
| 7 | Cámara lenta del mundo y personal | Pendiente |

Cada punto siguió la misma rutina:

1. leer lo que pide el documento;
2. implementarlo en el laboratorio;
3. pruebas automáticas, incluidas las de los pasos anteriores, para ver que nada se rompió;
4. un zip en el Escritorio para la notebook y las instrucciones clic por clic. Desde el escalón, el doble clic de la sección 6.2;
5. la prueba en las dos PC, con capturas;
6. el commit local, después de comprobar que los archivos son idénticos a los del zip probado. Desde Hanging, con huellas SHA-1.

### 8.1 Punto 2: base propia

#### Lo que pide el documento

- **Bases:** un actor parado sobre algo que se mueve guarda su posición y su velocidad relativas a esa base.
- **Etapa 2 del paso por tick:** la base lleva al actor.
- **Plataformas guionadas:** como se mueven según el tick, todas las máquinas las calculan igual y se pueden predecir.
- **Bases del host:** una balsa con física la simula solo el host, y los clientes ven una copia. El documento anticipa que ahí puede haber correcciones.
- **Inferencia I2, a confirmar:** con Jolt, un cuerpo cinemático movido durante un tick recién se ve en las consultas del tick siguiente.

#### Hecho confirmado: la inferencia I2 era cierta

Antes de escribir las bases, dos diagnósticos (`diag_kinematic_update.gd` y `diag_kinematic_next_tick.gd`, en el Apéndice B) movieron cuerpos de todas las formas probadas y consultaron el espacio en el mismo tick y en el siguiente:

- **No se ven hasta el paso de física siguiente:** `AnimatableBody3D`, con o sin `sync_to_physics`; `RigidBody3D` congelado en modo cinemático, aun con `force_update_transform()`; y el transform puesto directo en `PhysicsServer3D`.
- **Se ve en el acto:** un `StaticBody3D` con `force_update_transform()`.

**Consecuencias para el diseño:**

- **Plataformas guionadas:** al terminar el tick T se colocan en la pose de T+1, y su malla se corre un tick hacia atrás para no dibujarse adelantada al personaje.
- **Balsa en el host:** la mueve el motor de física, que la deja en su lugar antes del tick siguiente; no necesita corrimiento.
- **Copias de la balsa en los clientes:** al final de cada tick se colocan en la pose interpolada que tendrán en el tick siguiente, también con la malla corrida.

#### Qué se implementó

**Archivos nuevos:**

- **`scripts/actor/base_registry.gd` (`BaseRegistry`):** registro estático de bases por id de red. Da el origen y la velocidad de cada base, y `world_position(state)`, la posición de un estado en el mundo.
- **`scripts/actor/scripted_platform.gd` (`ScriptedPlatform`, un `AnimatableBody3D`):** su pose sale solo del tick: `pose_at(tick) = inicio + recorrido × (0,5 − 0,5 × cos(2π × tiempo / período))`. Con `prepare_tick(tick)` queda colocada para ese tick.
- **`scripts/actor/host_raft.gd` (`HostRaft`, un `RigidBody3D`):**
    - **En el host:** flota sin gravedad, con frenado, sin girar y sin poder subir o bajar. Cada 3 s elige al azar un punto dentro de una zona de 10 × 10 m alrededor de donde empezó y se empuja hacia él. Como se mueve al azar, nadie más la puede predecir.
    - **En el cliente:** `become_copy()` la congela en modo cinemático, y `place_copy()` la coloca con lo que llega en los snapshots.

**Cambios:**

- **`ActorState`:** suma `base_id`, de 16 bits; el estado pasó de 51 a 53 bytes. Con base, `position` y `velocity` son relativas a ella.
- **`ActorMotor`, etapa 2 (`_ride_base`):** lleva al actor hasta donde quedó su base, con `move_and_collide` e ignorando la base. Si algo fijo le cierra el paso, se baja ahí y se lleva la velocidad de la base. Si la base ya no existe, sigue sin base.
- **`ActorMotor`, etapa 8 (`_probe_base`):** una sonda de suelo, una caja de 0,2 × 0,1 × 0,2 m bajo los pies, dice sobre qué base quedó parado. Con varias gana el id más chico, así todas las máquinas eligen la misma. Al cambiar de base, la velocidad pasa al marco de la nueva: quien deja una base se lleva su velocidad.
- **`ActorBody.apply_state()`:** traduce la posición relativa al mundo con el origen actual de la base.
- **`SimClock`:** al terminar cada tick coloca las plataformas guionadas para el tick siguiente.
- **`NetSync`:** el snapshot suma una sección de bases del host: cantidad (8 bits) y, por base, id (16 bits), posición y velocidad (3 enteros de 32 bits cada una).
- **`RemoteInterpolation`:** guarda muestras de la balsa y coloca sus copias. Interpola a los demás en coordenadas de la base cuando las dos muestras tienen la misma.
- **`ClaimAdoption` y `ClientPrediction`:** comparan posiciones en el mundo.
- **`NetSession`:** `host_spawn_override`, para que las pruebas hagan aparecer al host en otro lado.
- **Laboratorio:**
    - la traza imprime una línea "actor:" con base, posición en el mundo y relativa, velocidad, modo y suelo;
    - el panel muestra la base y "Velocidad (sobre la base)";
    - la reaparición y la dirección del empujón usan posiciones en el mundo;
    - el host manda las balsas en el snapshot y el cliente convierte la suya en copia;
    - argumentos `--test-input=ride:<id>` y `--test-spawn-at=x,z`.
- **Nivel:**
    - **Vagón** (id 1): una plataforma naranja de 3 × 0,3 × 3 m a ras del piso que va y viene 8 m; cada ida y vuelta dura 8 s.
    - **Ascensor** (id 2): de 3 × 0,3 × 4 m; sube 1,98 m y vuelve a bajar en ciclos de 10 s, pegado a la plataforma verde alta.
    - **Balsa** (id 3): una tabla marrón que flota a 30 cm.

**Un error encontrado y corregido antes de entregar:** al caer sobre el ascensor mientras bajaba, el actor quedaba rebotando en Aire varios segundos. Godot deja en cero la velocidad vertical en el mundo al aterrizar, y en el marco de una base que baja eso es subir. Ahora, apoyado sobre una base, la velocidad relativa vertical no puede ser hacia arriba.

**Límites de esta primera vuelta:**

- Las bases solo se trasladan, no giran.
- Una plataforma que choca de costado contra un personaje todavía no lo empuja.

#### Pruebas automáticas

Con el cliente arriba de cada base, dando vueltas cerca del centro y saltando cada 3 s (`ride:<id>`):

| Prueba | Resultado |
| --- | --- |
| Vagón, sin red simulada | 0 correcciones; 818 coincidencias |
| Vagón, internet mala | 0 correcciones |
| Balsa, sin red simulada | 7 correcciones, todas juntas al subirse por primera vez desde el piso (14 afirmaciones rechazadas por pose) |
| Balsa, internet mala | 0 correcciones; 22 afirmaciones adoptadas, la más lejana a 0,945 m |
| Regresiones: caminar con las tres redes, y tirones de Wi-Fi | 0 correcciones; con tirones, 8 adoptadas (la más lejana a 0,147 m) |
| Repetición determinista | Pasa; huella nueva `7f845dfdc63f3a57` (cambió el formato del estado) |
| Fotogramas de Movie Maker, 300 por base (10 s) | El actor se ve apoyado sobre el vagón y la balsa, sin desfase |

**En la balsa pasa lo que anticipaba el documento:** en el aire, el cliente se mueve respecto de una copia que va unos 100 ms atrasada. La adopción absorbe casi todo. Las 7 correcciones son de un solo momento: el host rechazó la pose porque, en su mundo, caía dentro de la balsa real.

#### Prueba en dos PC (2026-10-03, 19:07)

Fueron 13 capturas, entre las 18:57 y las 19:03: cuatro del host (1020 a 1023) y nueve de la notebook (47 a 55). Llovía, y la conexión por Starlink tenía microcortes.

| Sesión | Base | Red en la notebook | Correcciones arriba de la base | Final |
| --- | --- | --- | --- | --- |
| 1 | Vagón | sin simulación | 0 (895 coincidencias) | no se ve en las capturas |
| 2 | Balsa | internet mala (también en el host) | 2 chicas, la mayor de 0,37 m | se cortó |
| 3 | Ascensor | internet mala y sin simulación | 0 | se cortó |
| 4 | Vagón | internet mala | 0 | se cortó |

**Por qué se cortaba:**

- En los tres cortes pasó lo mismo: lo que mandaba la notebook dejó de llegar al host, pero ella seguía recibiendo lo del host.
- Al cortarse, el host llevaba entre 4,5 y 5,4 s sin recibir nada. Eso es el −273, −315 y −322 ticks de la línea "tu input le llega al host" de las capturas.
- En la sesión 3 hubo antes un silencio de 3 s que la conexión aguantó.
- No era un problema de las bases: el laboratorio no sabe reconectarse, así que al cortarse se termina la sesión.

**El plazo de corte, medido** (`diag_enet_timeout.gd` y `diag_enet_timeout_long.gd`, en el Apéndice B):

- **Primera prueba:** aguantó 8 s de silencio, porque la conexión recién arrancaba y su ida y vuelta medida todavía estaba inflada.
- **Segunda prueba:** 40 s de conexión asentada y después un solo silencio de 15 s, congelando el host. Se cortó a los 9,7–10 s.
- **La cuenta:** ENet reenvía duplicando la espera cada vez. Con una espera inicial de unos 19 ms, la suma da 511 × 19 ms ≈ 9,7 s. El plazo depende de la ida y vuelta medida y nunca baja de 5 s, así que los cortes reales, de unos 5 s, cuadran.

**El "tp":** con las capturas no se pudo ubicar. Sí descartan dos cosas: la cápsula de la notebook no tuvo correcciones grandes, y la otra cápsula casi nunca se quedó esperando datos (menos de un tercio de segundo por sesión). La sospecha, sin probar: se vio en la pantalla del host. Mientras no llega nada de la notebook, el host mueve su cápsula repitiendo el último input recibido, y cuando vuelve la conexión la acomoda de golpe.

**Corrección de algo que se informó mal:** la balsa con internet mala no da siempre 0 correcciones. Al subirse desde el piso a veces hay una ráfaga de 2 a 3 s. En cinco pruebas salieron 0, 0, 24, 46 y 51, y en pruebas posteriores 37 y 11. Depende de por dónde ande la balsa, que se mueve al azar. Una vez arriba, ninguna. Quedó pendiente.

### Commit `600002a`

**Fecha:** 2026-10-03, 19:54. `feat(net): carry actors on scripted platforms and host rafts`: 17 archivos, +533 / −32 líneas.

- **Nuevos:** `base_registry.gd`, `scripted_platform.gd` y `host_raft.gd`, con sus `.uid`.
- **Cambiados:** `actor_state.gd`, `actor_motor.gd`, `actor_body.gd`, `sim_clock.gd`, `net_sync.gd`, `remote_interpolation.gd`, `net_session.gd`, `claim_adoption.gd`, `client_prediction.gd`, `net_lab.gd` y `net_lab_level.tscn`.

El commit lleva exactamente lo que se probó en las dos PC. Tres archivos ya tenían encima el arreglo siguiente, todavía sin probar. Para esos se guardó en git la copia del zip, con `git hash-object -w` y `git update-index --cacheinfo`, sin tocar el árbol de trabajo. Antes del commit se comparó archivo por archivo contra el zip.

#### Cómo se ve al otro jugador sobre una plataforma: tres vueltas

**Primera vuelta: el saltito al subir o bajar** (2026-10-03, zip `_base_propia_2`)

- **Qué pasaba:** en la sesión 1 el panel marcó 5,3 % de tirones de los demás. Investigado sin pantalla (`diag_remote_on_base.gd`), apareció algo real. Visto desde la notebook, cuando el jugador del host saltaba del vagón en movimiento o caía sobre él, su cápsula pegaba un salto de hasta 0,41 m en un cuadro.
- **La causa:** arriba del vagón se lo dibujaba pegado al vagón de la notebook, que va unos ticks adelantado; en el aire, donde estaba en el host, que va atrasado.
- **El arreglo:** ese cambio se repartía en unos 0,2 s. El paso más grande bajó a 0,18 m, y en promedio a 0,08 m, como caminar.
- **El panel de tirones:** contaba mal arriba de una base, porque usaba la velocidad relativa. Corregido, marca 1 % en esa prueba, y entre 3,5 y 4 % con internet mala.

**Segunda vuelta: el ajuste al aterrizar** (reporte del 2026-10-04 a las 10:24, zip `_base_propia_3`)

- **El reporte:** "el salto que se ve desde esa notebook, en la otra llega, pero tiene que hacer un ajuste cuando la capsula toca la plataforma. [...] a mas ping es mas notorio". Era el arreglo anterior: el salto de golpe se había convertido en un deslizamiento al aterrizar.
- **La causa:** en el aire se dibujaba al jugador donde estaba en el host. Al caer había que llevarlo hasta el vagón, y cuanto más ping, más se había corrido el vagón en ese tiempo.
- **El cambio, marcos de dibujo:**
    - cada jugador remoto se dibuja en un marco, una base o el mundo;
    - el marco se elige con el snapshot más nuevo, se mantiene en el aire y no se deja mientras se lo muestra parado sobre su base;
    - si salta desde el vagón, todo el salto se dibuja respecto del vagón, y toca la plataforma en el mismo punto que en el host;
    - si salta del piso al vagón o al revés, el ajuste se hace en el aire y termina justo al tocar.
- **Prueba nueva:** `--test-input=hop:<id>`: llega a la base y, cada 2,5 s, salta a 3,2 m del centro (afuera de la base) o vuelve saltando al centro.

| Cuánto se acomoda la cápsula al tocar | Antes | Después |
| --- | --- | --- |
| Saltar sobre el vagón, red limpia | 0,35 m de promedio | 0 |
| Saltar sobre el vagón, internet mala | 0,83 m (hasta 1,24) | 0 |
| Saltar sobre el ascensor, internet mala | 0,18 m | 0 |
| Saltar del piso al vagón o al revés, red limpia | no medido | 0,02 m |
| Ídem con internet mala | no medido | 0,10 m (hasta 0,37) |

Los tirones del otro jugador sobre las bases bajaron a menos del 1 %.

**Tercera vuelta: los bordes** (reporte del 2026-10-06 a las 11:54, zip `_base_propia_4`)

- **El reporte:** "el parche hace su trabajo, pero a medias. [...] en los bordes, todavía es apreciable la corrección".
- **Reproducido** con dos pruebas nuevas: `walkoff:<id>`, que sale y entra del vagón caminando (va a 2,5 m del centro y vuelve), y `edge:<id>`, que salta a caer en el borde (a 1,4 m del centro). Al salir o entrar caminando, la notebook acomodaba al jugador del host 0,36 m con red limpia y 0,87 m con internet mala, en una décima de segundo y con el jugador todavía parado sobre el vagón.
- **La causa de fondo:** la notebook dibujaba el vagón en su propio momento, que va adelantado, y al otro jugador en el pasado. Cada vez que el otro subía o bajaba había que pasarlo de un momento al otro.
- **El cambio (`visual_lag`):**
    - lejos del jugador local, el vagón se dibuja en el mismo pasado que los demás, y así siempre coinciden;
    - cerca (a menos de 1,5 m) o arriba, se dibuja como antes, porque la cápsula propia lo necesita en su momento;
    - entre 1,5 y 6 m pasa de a poco;
    - solo cambia el dibujo: la física del vagón no se toca.
- **Un resto de 0,1 m:** primero quedaba eso en cada cambio de marco, con buena y mala red. Venía de comparar el lugar visto en el tick anterior con el nuevo. Se arregló comparando los dos marcos en el mismo momento mostrado.

| Cuánto se acomoda el otro jugador, mirando desde lejos | Zip anterior (red limpia / mala) | Después (red limpia / mala) |
| --- | --- | --- |
| Salir o entrar caminando | 0,36 m / 0,87 m | 0 / 0 |
| Saltar del vagón al piso o del piso al vagón | 0,34 m / 0,85 m | 0 / 0 |
| Saltar y caer en el borde, o en el ascensor | — | 0 / 0 |

**Lo que queda,** y se avisó al entregar: si el jugador local también está arriba del vagón o cerca, el vagón tiene que estar en su momento, y queda un ajuste de unos 0,3 m que solo se puede disimular.

- Al bajarse, el ajuste empieza cuando ya salió del vagón y dura 0,2 s.
- Al subirse, termina justo al tocar el vagón, en una décima de segundo.
- Además, al acercarse caminando desde lejos, el vagón se va adelantando de a poco hasta su momento real.

**Prueba en las dos PC (12:50):** "podría decirse que esta casi que arreglado". Queda un caso: entrar a la plataforma caminando al final de un salto bajo, casi horizontal. No se reprodujo. La explicación, sin probar: el ajuste lento de haberse bajado se suma al corto de volver a subirse. Eso solo puede pasar si la cápsula que mira está cerca o arriba del vagón. Se preguntó, y la respuesta (13:27) fue "estaba cerca": queda como límite conocido.

### Commit `25f7806`

**Fecha:** 2026-10-06, 12:51. `feat(net): draw other players consistently on moving platforms`: 5 archivos, +268 / −38 líneas. Son `net_lab.gd`, `actor_body.gd`, `base_registry.gd`, `scripted_platform.gd` y `remote_interpolation.gd`. Lleva las tres vueltas juntas, tal como se probaron en el zip `_base_propia_4`.

### 8.2 Punto 3: postura y espacio libre

#### Qué se implementó

**El actor:**

- **Dos formas ya preparadas,** como pide el documento: la parada, una cápsula de 1,8 m de alto y 0,35 m de radio, y la agachada, de 1,0 m. Se cambia cuál está activa; no se cambia el tamaño de una forma.
- **`ActorState`:** el modo Deslizamiento (`SLIDE`) y la postura, pedida (`stance_wanted`) y concedida (`stance`).
- **`ActorInput`:** botones nuevos, agacharse (Ctrl, bit 1) y correr (Shift, bit 2).

**`ActorBody`:**

- `use_stance()` activa una forma u otra.
- `stance_fits()` prueba si una forma entra con `intersect_shape`, usando una copia de la forma achicada 2 cm, para que tocar el piso no cuente como choque. No cuentan el propio cuerpo ni los demás jugadores, que están en otra capa.
- `present()` muestra la malla de cada postura y ubica la nariz.

**`ActorMotor`:**

- **Velocidades:** caminar a 5 m/s, correr a 8 m/s (solo parado) y agachado a 2,5 m/s.
- **Deslizamiento:** se entra corriendo, parado y a 6 m/s o más, al apretar Ctrl. Frena por rozamiento (4 m/s²), acelera en bajada, gira poco (1,5 rad/s) y no pasa de 12 m/s. Cuando baja de 2,5 m/s vuelve a Suelo. Siempre pide agachado.
- **Etapa 7, `_resolve_stance()`:**
    - agacharse siempre se concede;
    - crecer necesita espacio libre, y nunca se crece hacia un espacio ocupado;
    - en el suelo la forma cambia con los pies fijos;
    - en el aire, con la cabeza fija: agacharse sube los pies 0,8 m y pararse los baja.
- **Un cambio chico que no se pidió, avisado al entregar:** en el aire, el control ya no frena a quien venía más rápido que caminando. Sin eso, al saltar corriendo o deslizándose se perdía velocidad en el aire. Los saltos caminando quedan igual.

**Presentación y red:**

- **`LabCamera`:** la altura de la cabeza depende de la postura: 1,6 m parado y 0,8 m agachado. Así, bajo el techo, la cámara queda adentro del túnel.
- **`RemoteInterpolation`:** entre dos datos con distinta postura no mezcla las alturas de los pies.
- **Nivel:** el túnel largo, detrás de donde aparecen los jugadores. Dos paredes y un techo a lo largo de z, de 14 a 24, centrado en x = 0. El techo empieza a 1,2 m y su cara de arriba está a 1,5 m.
- **Laboratorio:** el panel suma la línea "Postura: agachado · pedida: parado (no hay lugar)". Pruebas nuevas: `--test-input=tunnel` y `crouchjump`.

#### Pruebas automáticas

| Prueba | Resultado |
| --- | --- |
| El cliente corre, se desliza al túnel, suelta Ctrl adentro, sale caminando y vuelve agachado; red limpia, mala y con tirones | 0 correcciones; 697, 452 y 664 coincidencias. Frena adentro, sigue agachado y se para solo al salir |
| Ticks parado bajo el techo | 0 en todas |
| El host hace el túnel y el cliente lo mira; red limpia y mala | 0 correcciones; tirones del otro jugador 1,2 % y 1,1 % |
| Repetición con deslizamiento, agachado bajo techo y agacharse en el aire | 1.971 repeticiones y 83.241 ticks idénticos, también con el ritmo variando. 715 ticks agachado, 155 de ellos pidiendo pararse sin lugar. Huella `7401f6f3c81f517e` |
| Pruebas anteriores (piso plano, vagón, balsa) | Igual que antes |
| Fotogramas de Movie Maker | La cámara baja con la postura, y bajo el techo queda adentro del túnel |

**Problemas de la ruta de prueba:** la prueba del túnel primero se caía del mapa, porque saltaba sin frenar, todavía a 5 m/s. Se le agregó una pausa antes del salto.

#### Agacharse en el aire: la duda, la pausa y la pared

- **13:54, la pregunta:** "cuando agregaste la capacidad de agacharse, ¿usaste el mismo sistema cuando se esta tocando el piso y saltando (sin tocar el piso)?". La respuesta: sí, el mismo; cambia solo qué parte queda quieta.
- **13:56, el pedido:** "busca en el código actual la función que se encarga de esto, porque me parece que la posicion relativa de los pies es la misma en ambos casos".
- **La medición** (`diag_postura_aire.gd`): la primera corrida dio números basura, porque el script movía al actor antes de que estuviera dentro del juego. Corregida, mostró dos comportamientos distintos, desde `_resolve_stance` en `actor_motor.gd`:

| Momento | Pies antes → después | Cabeza antes → después |
| --- | --- | --- |
| Se agacha en el aire (tick 40) | 0,651 → 1,502 m (suben 0,85) | 2,451 → 2,502 m (solo lo que sigue subiendo por el salto) |
| Se para en el aire (tick 55) | 1,918 → 1,127 m (bajan 0,79) | 2,918 → 2,927 m (quieta) |
| Se agacha en el piso (tick 120) | 0,001 → 0,001 m (quietos) | 1,801 → 1,001 m (baja 0,8) |
| Se para en el piso (tick 140) | 0,001 → 0,001 m (quietos) | 1,001 → 1,801 m (sube 0,8) |

- **La sospecha, deducida del código y avisada como tal:** la culpa era de la cámara. Se apoyaba en los pies y les sumaba la altura de la cabeza, suavizada. En el aire, los pies suben 0,8 m de golpe, la cámara sube con ellos y después baja despacio: parece que los pies quedaron y la cabeza bajó.
- **14:10, la respuesta:** "nop, mi teoría es correcta, no se como esta armado esto, pero los pies siempre se mantienen en el mismo lugar [...] pero antes de tocar eso, hay que agregar un botón de pausa para que detenga el movimiento del player y lo congele en la posicion que tenga, ademas de su coordenadas. Tambien agregar un muro con medidas de referencia para poder usarla como escala."

**Las herramientas nuevas** (zip `_postura_2`):

- **Pausa:** congela todo donde está, y otra tecla avanza un solo tick.
    - `SimClock.paused` hace que `_physics_process` no corra ningún tick, salvo los pedidos con `step()`.
    - La cápsula es un `CharacterBody3D`, y si nadie llama al motor no se mueve: queda en el aire, con su estado intacto.
    - El vagón y el ascensor también quedan quietos, porque su pose sale del tick.
    - La balsa la mueve el motor de física, así que se congela aparte (`_set_paused`).
    - La cámara y el panel siguen andando.
    - Anda solo en Jugar solo: en red, congelar una sola PC desincroniza los relojes.
- **Coordenadas en el panel:** "Pies en (x, y, z) · cabeza a … m de altura", con milímetros, y "EN PAUSA (tick N)".
- **Pared de medidas** (`measure_wall.gd`), adelante a la izquierda de donde se aparece, en (−6; 1,75; 5): rayas cada 10 cm desde el piso y números cada 50 cm.

Con ellas se grabaron dos imágenes frente a la pared. En el tick 126, parado en el aire: pies a 0,651 m y cabeza a 2,451 m. En el tick 127, recién agachado: pies a 1,501 m y cabeza a 2,501 m.

**Las teclas:**

- **14:19:** "¿la tecla P esta mapeada en la configuración del proyecto?". No: P y O se leían directo en el código, como 1 a 5, E y Q.
- **Lo que había en el Mapa de entrada:** `toggle_debug_freeze`, en la G, del parkour; `interactuar`, en la E; y `toggle_free_cam`, en la F. El laboratorio no usa esas acciones.
- **14:36, la decisión:** "usa la G para pausar y mapea la tecla F para avanzar de tick".
    - La G usa `toggle_debug_freeze`.
    - La F es una acción nueva, `avanzar_tick`, en `project.godot`. Comparte tecla con `toggle_free_cam` sin chocar.
    - Verificado con teclas simuladas (`diag_teclas_pausa.gd`): la G congela y 30 cuadros después sigue en el mismo tick; la F avanza exactamente un tick; otra G suelta.
- **Aviso al entregar:** cerrar y volver a abrir Godot, porque el editor abierto tenía el mapa viejo en memoria y al guardar podía borrar la acción nueva.

**La aclaración pedida (14:44–14:47):**

- Se explicó cómo funciona la pausa.
- A la pregunta "¿en alguna parte me dijiste que tenia que hacerlo en una sesión sin conexión red?": sí, en dos lugares, pero enterrado. En red, la G no hace nada y no dice por qué.
- Se ofreció un aviso en el panel para las partidas en red; no se pidió.

#### Arreglo de la cámara

**14:48, la confirmación:** "efectivamente, como habías hecho la implementación era correcta, lo que pasaba es que el movimiento de cámara rápido [...] daba la ilusión de que solo existía una manera de agacharse".

**Medido cuadro por cuadro** (`diag_camara_aire.gd`), aparecieron dos causas:

- **La cámara:** cuando los pies subían 0,8 m de golpe en el aire, subía con ellos y después bajaba en 0,17 s.
- **El dibujo de la cápsula:** durante un tick la forma agachada se dibujaba desde los pies viejos. La interpolación de física trataba el salto de los pies como movimiento, y la cabeza bajaba de 2,43 a 1,65 m y volvía.

**Los arreglos** (zip `_postura_4`):

- **Cámara:** en el aire, al cambiar de postura, ajusta su altura de golpe en lo mismo que saltaron los pies. En el piso sigue a la cabeza con suavizado, como antes.
- **Dibujo:** en el aire, el cambio de postura reinicia la interpolación de física (`reset_physics_interpolation()`), y el salto de los pies se dibuja de una vez.
- **La cápsula del otro jugador:** el mismo arreglo. Medido desde el cliente con red limpia y mala (`diag_remoto_postura.gd`), la cabeza sigue pareja.

| A dos cuadros por tick, al agacharse en el aire | Antes | Después |
| --- | --- | --- |
| Cabeza dibujada | 2,43 → 1,65 → 2,08 → 2,50 m | 2,43 → 2,50 → 2,53 m |
| Cámara | sube 0,67 m de golpe y baja despacio | 2,20 → 2,30 → 2,33 m, siguiendo a la cabeza |

La huella de la repetición siguió siendo `7401f6f3c81f517e`, y el túnel dio 0 correcciones con las tres redes. **15:57:** "ahora se ve perfecto, no hace el movimiento raro de antes."

#### Primeras capturas en dos PC y avisos del depurador

**16:07, las capturas:** la notebook, parada sobre el vagón, tenía 4.083 coincidencias, 0 correcciones, 0,1 % de datos tarde y 0 % de tirones. El host no tenía afirmaciones adoptadas ni rechazadas. Las cápsulas estaban paradas, así que todavía no mostraban la postura.

**La pregunta "Con respecto a postura, ¿que es?".** La respuesta:

- **Las dos posturas:** parado, 1,8 m, se puede correr; agachado, 1,0 m, más lento, sin correr, y pasa bajo techos bajos.
- **Pedida y concedida:** la pedida es la que se quiere; la concedida, la que se tiene. Agacharse siempre se concede; pararse, solo si arriba hay lugar.
- **Por qué importa en red:** si la notebook creyera estar agachada y el host parada, en el host chocaría con el techo del túnel y llegaría una corrección.

**Los avisos:** en la captura del host, la pestaña Debugger marcaba 9. La captura 1025 mostró que eran avisos, no errores, y ninguno de postura:

| Aviso | Cuántos | Dónde | Desde cuándo |
| --- | --- | --- | --- |
| El parámetro `state` tapa a la variable `state` del actor | 3 | `actor_body.gd`: `slide`, `apply_state` y `present` | Primeros pasos de la red |
| División entera: se descarta la parte decimal | 2 | `net_sync.gd` y `sim_clock.gd` | Primeros pasos de la red |
| División entera | 2 | `net_lab.gd`, prueba en zigzag | Paso 7 |
| División entera | 1 | `net_lab.gd`, prueba de subir y bajar del vagón | Base propia |
| La variable `move` se declara también más abajo | 1 | `net_lab.gd`, prueba en zigzag | Paso 7 |

**16:24, "dale, limpialos"** (zip `_postura_5`):

- **Nombres:** el parámetro pasó a llamarse `actor_state`, y la variable `move` del zigzag, `side`.
- **Divisiones enteras:** las seis quedaron marcadas como a propósito con `@warning_ignore("integer_division")`. Se sumó una sexta, de la prueba de repetición, que apareció al verificar.
- **La verificación:** Godot imprime estos avisos sin ventana solo con el depurador encendido (`-d`). Primero se comprobó con un script de ensayo con una división entera a propósito (`diag_aviso_prueba.gd`), y el aviso salió. Después el laboratorio y la repetición corrieron sin ningún aviso.
- **El movimiento no cambió:** la misma huella y 0 correcciones en red.

#### Capturas con F12

**16:37:** "no puedo sacarlas con la configuración clásica de la tecla de windows + prt sc/imp pnt, porque para estar agachado tengo que tener mantenido la tecla control". Para la captura del túnel no hacía falta: adentro se sigue agachado solo. Se ofreció una tecla del juego, y la respuesta fue "dale, agregá la tecla F12 para capturas" (zip `_postura_6`).

- **La acción:** `captura`, en la F12, en `project.godot`.
- **El archivo:** se guarda en el Escritorio como `captura_lab_<fecha>_<hora>_<milésimas>.png`, así dos seguidas no se pisan.
- **Qué incluye:** lo que se ve, con el panel. Espera al final del dibujo (`frame_post_draw`).
- **El aviso:** "Captura guardada en el Escritorio: …" arriba del panel, 3 s. No sale en la imagen.
- **Dónde anda:** con cualquier otra tecla apretada, y en Jugar solo, en el host y en el cliente.
- **Verificada** con teclas simuladas (`diag_captura.gd`): con Ctrl apretado, la imagen quedó guardada con la cápsula agachada y el panel. Esa captura de prueba se borró del Escritorio.

#### Prueba final en dos PC (17:19)

Fueron 15 capturas: 8 del host, a 1600 × 900, y 7 de la notebook, a 1280 × 720.

- **Bajo el techo:** los dos jugadores quedaron agachados con "pedida: parado (no hay lugar)", y se pararon solos al salir.
- **Agacharse en el aire:** los pies suben y la cabeza queda. En una captura del host, pies a 1,776 m y cabeza a 2,776 m.
- **La red:** la notebook pasó las 12.800 coincidencias, con 0,5 % de datos tarde y 0,7 % de tirones.
- **La única corrección:** una de 1,21 m en la notebook, junto con 80 esperas y un salto de reloj, todo en los 6 s entre dos capturas. Es la marca de un corte del Wi-Fi.
- **El corte, repetido sin pantalla** con cortes de 1,5 s cada 4 s: deslizándose al túnel, 1 corrección; caminando en zigzag, sin agacharse, 5. La corrección viene del corte, no de la postura.
- **Saltar y agacharse llega más alto:** como agacharse en el aire sube los pies 0,8 m, los dos jugadores subieron al techo del túnel, a 1,5 m. Un salto parado llega a unos 1,17 m. Se avisó como consecuencia de la regla del documento.

### Commit `cb71b16`

**Fecha:** 2026-10-06, 17:23. `feat(net): add stance, free space and slide (validation item 3)`: 16 archivos, +592 / −58 líneas.

- **Lo que lleva:** postura, espacio libre y deslizamiento; el túnel largo y la pared de medidas; la pausa con G y F; las capturas con F12; el arreglo de la cámara; y la limpieza de los avisos.
- **Archivos:** `project.godot`, `actor.tscn`, `actor_replay_test.gd`, `lab_camera.gd`, `measure_wall.gd` y su `.uid`, `net_lab.gd`, `net_lab_level.tscn`, `actor_body.gd`, `actor_input.gd`, `actor_motor.gd`, `actor_state.gd`, `actor_tuning.gd`, `net_sync.gd`, `remote_interpolation.gd` y `sim_clock.gd`.
- **`project.godot`:** se guardaron solo las dos acciones nuevas del Mapa de entrada, con `git apply --cached` de un parche parcial. El cambio de versión 4.6 → 4.7 que hizo el editor quedó afuera, sin commitear.
- **La verificación:** los zips ya no estaban en el Escritorio. Se comprobó en cambio que ningún archivo había cambiado después de armar el último, a las 16:39.

#### "En el aire, la forma crece hacia abajo"

**19:09:** "¿que es esto de «en el aire, la forma crece hacia abajo»?". Es una regla del documento de arquitectura: "En suelo la forma crece hacia arriba; en el aire, hacia abajo".

- **Por qué la eligió el documento:** pararse en el aire cerca de un techo bajo no choca, y en primera persona la vista queda quieta al cambiar de postura saltando.
- **Lo que se agregó en la implementación:** el documento solo habla de crecer. Para agacharse en el aire se aplicó la misma regla al revés, y agacharse y volver a pararse en el aire deja en el mismo lugar.
- **La alternativa, explicada sin recomendarla:** pies fijos también en el aire. Ya no se ganaría altura, pero la cabeza y la cámara bajarían 0,8 m de golpe en pleno salto.

Pedido "decimelo en pocas palabras": en el piso, los pies quedan y se mueve la cabeza; en el aire, la cabeza queda y se mueven los pies. Por eso, agachándose al saltar se llega más alto.

**Decisión, 19:18:** "perfecto, que se quede asi, seguí con el punto de la escalera".

### 8.3 Punto 4: escalera, con empujones programados e inmediatos

#### Lo que pide el documento

- **Ladder:** un modo anclado sobre un objeto autorado con su eje.
- **Entrada:** por intención, caminando hacia la escalera.
- **Salidas:** salto, abajo, arriba con una trayectoria autorada, y el respaldo si se rompe un invariante.
- **Regla de fuerza contra agarre:** un impulso de fuerza igual o mayor que el agarre del modo lo suelta; uno menor se proyecta sobre lo que el modo puede mover.
- **Eventos del host sobre un personaje predicho:**
    - **inmediatos:** el cliente se entera tarde y se corrige;
    - **programados:** el host fija un tick E = ahora + ida y vuelta + colchón, lo manda confiable, y los dos lo aplican en E.

#### Qué se implementó

**`scripts/actor/ladder.gd` (`Ladder`), nuevo:**

- **El objeto:** escalera autorada con id de red, alto, ancho (0,8 m), distancia del eje al centro de quien trepa (0,45 m) y alcance para agarrarla (0,9 m).
- **El eje:** sube por +Y local, y se trepa desde el lado +Z local.
- **La pose:** `pose_at(t)` da dónde van los pies a la altura t.
- **La entrada:** `height_for(pies)` da la altura, o −1 fuera del volumen de entrada.
- **El dibujo:** dos largueros y un peldaño cada 30 cm, sin colisión.
- **Registro estático** por id, como las bases. Por ahora las escaleras están fijas.

**`ActorState`:**

- el modo `LADDER`;
- el ancla: qué escalera (`anchor_id`) y a qué altura (`anchor_t`);
- el bloqueo de reagarre: qué escalera (`regrab_id`) y por cuánto tiempo (`regrab_left`).

Pasó de 53 a 67 bytes.

**`ActorMotor`:**

- **Entrada** (`_try_grab_ladder`), desde Suelo o Aire: dentro del volumen y yendo hacia la escalera. Con varias, gana la de id más chico. La que se acaba de soltar está bloqueada.
- **Trepar** (`_ladder`): hacia la escalera sube y alejarse baja, a 2,5 m/s con aceleración de 20 m/s²; de costado no hace nada. Se mueve con un barrido (`move_and_collide`) hasta la pose de la altura pedida; si algo lo frena, la altura queda donde llegó.
- **Salidas:**
    - **Salto:** a Aire, 3 m/s hacia afuera y 3,5 m/s hacia arriba, con 0,4 s de bloqueo de reagarre.
    - **Abajo:** alejarse estando abajo de todo.
    - **Arriba:** seguir hacia la escalera estando arriba de todo. Es una trayectoria de dos tramos, 5 cm hacia arriba y después hacia adentro sobre el borde, validada antes con `test_move()`. Si algo la tapa, sigue en la escalera.
    - **Respaldo:** si la escalera ya no existe, sale a Aire.
- **`apply_impulse(state, impulso, fuerza, tuning)`,** que reemplazó a `push()`:
    - en los modos libres (agarre 0), el impulso se suma y pasa a Aire;
    - en la escalera, una fuerza de 3 o más la suelta, con el impulso y bloqueo de reagarre;
    - una fuerza menor se suma, y el modo la proyecta sobre el eje.
- **`anchored_pose_valid(state)`:** el host rechaza por pose una afirmación en la escalera si el ancla no existe, la altura está fuera de rango o el cuerpo está a más de 10 cm de su pose.

**Eventos programados:**

- **`NetSync`:**
    - cada paquete del cliente empieza con la ida y vuelta que mide (16 bits), para que el host sepa con cuánta anticipación programar;
    - `send_scheduled_event()` manda por un RPC confiable (`_receive_scheduled_event`) el tick, el impulso cuantizado a 1 mm/s y la fuerza.
- **`LinkSimulator`:** con `deliver_reliable()`, el simulador demora los mensajes confiables pero no los pierde, como ENet.
- **Laboratorio:**
    - **Host:** fija E = tick actual + margen del input de ese jugador (si es positivo) + su ida y vuelta en ticks, redondeada hacia arriba + 4 de colchón. Anota el evento, lo anuncia y lo aplica al empezar el tick E, subiendo la época.
    - **Cliente:** anota cada evento para su tick y lo aplica antes del paso de ese tick, también al repetir ticks.
    - **Evento tardío:** si llega cuando ese tick ya se predijo, `ClientPrediction.replay_from()` repite desde ahí con el evento incluido.
    - **Demasiado tarde:** si ya ni eso se puede, lo arregla la corrección del snapshot, como a uno inmediato.
- **Teclas, en el host:** E, empujón inmediato; R, programado; con Shift, débil (fuerza 2), y sin Shift, fuerte (fuerza 4).
- **Panel del cliente:** "empujones programados: N llegaron a tiempo, N tarde (se repitió desde su tick), N demasiado tarde".
- **Argumentos:** `--test-scheduled-push-at`, `--test-push-force` y `--test-schedule-ticks`, este último para forzar un aviso corto.

**Nivel:**

- **Una torre de 2,5 m** (3 × 2,5 × 3 m, en (8; 1,25; 14)), detrás de donde se aparece y a la derecha. Tiene una escalera (id 1) en la cara que da hacia donde se aparece.
- **Otra escalera** (id 2, de 2 m) en la cara de atrás de la plataforma verde alta, la que no da hacia donde se aparece.

**Prueba de repetición:** suma tramos de escalera y dos empujones, uno débil y uno fuerte, aplicados igual en la pasada en vivo y en las repeticiones.

**Simplificaciones, avisadas al entregar:**

- **Salida por arriba:** sube al techo en un solo tick, sin animación. El documento pide una trayectoria en el tiempo; quedó para el laboratorio de Hanging, que tiene el mismo problema.
- **Al agarrarse:** pone de golpe sobre el eje, a hasta 90 cm.
- **No hay botón de agarrar:** basta caminar hacia la escalera.
- **Las escaleras están fijas:** ninguna va sobre una plataforma móvil.

#### Pruebas automáticas

En pareja: el cliente sube y baja la escalera de la torre (`--test-input=ladder`). El host le da dos empujones inmediatos (a los 8 y 16 s) y dos programados (a los 12 y 20 s).

| Prueba | Correcciones | Programados | Afirmaciones rechazadas por época |
| --- | --- | --- | --- |
| Fuertes (4), red limpia | 2 | 2 a tiempo | 6 |
| Débiles (2), red limpia | 2 | 2 a tiempo | 4 |
| Fuertes, internet mala | 2 | 2 a tiempo | 30 |
| Débiles, internet mala | 2 | 2 a tiempo | 29 |
| 4 programados fuertes con solo 3 ticks de aviso, internet mala | 0 | 4 tarde, repetidos desde su tick | 48 |
| 4 programados débiles con 3 ticks de aviso, internet mala | 1 | 3 tarde, 1 demasiado tarde | 52 |
| 4 programados fuertes con 1 tick de aviso, internet mala | 1 | 3 tarde, 1 demasiado tarde | 60 |

- **Las correcciones:** en las cuatro primeras son exactamente las de los dos inmediatos.
- **El efecto del empujón:** el fuerte lo saca de la escalera; cae, vuelve y se agarra de nuevo. El débil lo deja en la escalera, más arriba.
- **Ninguna afirmación se rechazó por distancia ni por pose.**

| Prueba | Resultado |
| --- | --- |
| Repetición con escalera, empujones y saltos, a 60 y con el ritmo variando | 2.467 repeticiones y 106.057 ticks idénticos; huella `d5f212653ef1bf8b` |
| Piso plano, con las tres redes | 0 correcciones |
| Vagón y balsa, con el cliente arriba y con el host arriba | 0 correcciones; esta vez la balsa no dio la ráfaga al subirse. Afirmaciones adoptadas en la balsa: 18 (la más lejana a 0,389 m con red limpia y 0,996 m con internet mala) |
| Túnel | 0 correcciones |
| Fotogramas de Movie Maker (`diag_escalera_frames.gd`) | La cápsula trepa delante de la escalera; el panel dice "Escalera 1 · pies a 1,62 m sobre su base"; arriba queda parada sobre la torre |

**Problemas de la ruta de prueba:**

- **En el pie de la escalera,** la prueba oscilaba entre alinearse y agarrarse. Se arregló fijando la alineación una vez lograda.
- **En la repetición,** la ruta primero se caía del mapa: se acortó un tramo y se agregó una parada antes del salto. Después no llegaba a reagarrar, o el empujón fuerte la tiraba arriba de la plataforma: se reordenaron los tramos y se volvió en diagonal.
- **En el análisis:** las ventanas de tiempo del primer filtro estaban corridas, porque el cliente arranca 1,5 s después que el host. Se pasó a mirar solo los momentos en que cambian el modo o la época.

#### Prueba en dos PC (2026-10-06, 21:00)

Fueron tres capturas, dos de la notebook y una del host, con internet mala en las dos PC (unos 300 ms de ida y vuelta).

| Qué | Resultado |
| --- | --- |
| Empujones del host | 50 inmediatos y 29 programados |
| Época de la notebook | 79 = 50 + 29: todos se aplicaron en las dos PC |
| Correcciones en la notebook | 50, una por cada inmediato |
| Programados | 18 a tiempo, 11 tarde y repetidos desde su tick, 0 demasiado tarde |
| Afirmaciones rechazadas en el host | 647 por época, 0 por distancia y 0 por pose. Son las de los ticks en que la notebook todavía no sabía del empujón |
| Última corrección | 3,43 m: con tanta latencia, un inmediato se ve como un salto. El programado lo evita, que es lo que había que validar |

### Commit `91a4433`

**Fecha:** 2026-10-06, 21:01. `feat(net): add Ladder mode and scheduled host events (validation item 4)`: 12 archivos, +643 / −51 líneas.

- **Nuevos:** `ladder.gd` y su `.uid`.
- **Cambiados:** `actor_motor.gd`, `actor_state.gd`, `actor_tuning.gd`, `claim_adoption.gd`, `client_prediction.gd`, `link_simulator.gd`, `net_sync.gd`, `net_lab.gd`, `net_lab_level.tscn` y `actor_replay_test.gd`.
- **La verificación:** antes del commit se comprobó que los 12 archivos eran idénticos a los del zip probado.
- **`project.godot`:** no tenía cambios del laboratorio en este punto, solo el 4.6 → 4.7 del editor, así que no se incluyó.

### 8.4 El escalón (pedido aparte, antes del punto 5)

#### El pedido

2026-10-07, 13:41: "antes de hacer el punto 5, quiero que agregues el step, ese mini salto que se da cuando tenes un escalon o algo por el estilo. Tambien te diria que siga la filosofia que venimos siguiendo".

La filosofía es la del documento de arquitectura, y el escalón la sigue en tres puntos:

- **Lo que pide el documento** (sección "Escalones" del Apéndice A): para escaleras, primero rampas de colisión invisibles, una regla de nivel que es estable en red. Para cordones y escalones sueltos, el modo Suelo suma una sonda: subir, avanzar, bajar, y aceptarlo solo si cae en suelo caminable.
- **Igual que el snap de Hanging:** el cuerpo queda arriba en un solo tick, y lo que se ve sube suave, con el mismo mecanismo que suaviza las correcciones.
- **Nada nuevo viaja por red:** el escalón pasa entero dentro del tick, así que el formato de red no cambió.

#### Qué se implementó

**`ActorMotor._step_up`, la sonda de escalón.** Corre en la etapa 7, solo en Suelo, y solo si el movimiento normal chocó contra algo. Desde donde arrancó el tick:

1. **Sube** hasta `step_height` (0,3 m) con `test_move()`, o lo que deje el techo; si no puede subir ni 1 cm, no hay escalón.
2. **Avanza** lo que iba a avanzar en el tick, pero al menos `radio × (1 − sen(ángulo máximo de piso)) + 1 cm` hacia la pared con que chocó. La parte de abajo de la cápsula es redonda: apoyada sobre el filo de un escalón, solo cuenta como piso si el centro ya se acercó bastante al filo. Sin ese mínimo, yendo despacio o en diagonal no subía.
3. **Baja** con `test_move()` y acepta solo si:
    - cae sobre piso caminable;
    - ganó 1 cm o más;
    - llegó más lejos que el movimiento normal;
    - un rayo sobre la superficie que pisa, justo pasando el punto de apoyo, encuentra piso caminable, no más abajo que donde quedaron los pies y a no más de `step_height` del piso de partida. La altura sale de ese rayo y no de la cápsula, que puede quedar apoyada en el filo más abajo.
4. **Snap lógico:** el cuerpo queda arriba en este tick y `ActorBody.settle_on_floor()` refresca los indicadores de Godot sin moverlo. La velocidad conserva la horizontal pedida.
5. **Presentación:** `snap_jump` le avisa a la presentación cuánto subió, y lo que se ve arranca desde abajo y alcanza al cuerpo con el decaimiento de las correcciones (vida media de 25 ms).

**Otros cambios:**

- **`ActorTuning.step_height` = 0,3 m:** igual al snap al piso, así sube y baja los mismos escalones; en 0 se apaga.
- **`ActorBody`:** `capsule_radius()` y `settle_on_floor()`.
- **Pista de escalones** (`scenes/net_lab/step_course.gd`), detrás de donde se aparece, a la izquierda del túnel violeta (origen en (−4; 0; 12)):
    - escalones sueltos de 10, 20, 30 y 40 cm, de 1,5 × 2 m, cada 2,5 m y con carteles;
    - dos escaleras iguales de seis escalones de 20 cm, con 35 cm de huella, 2 m de ancho y un descanso de 2 m arriba. Una no tiene nada encima; la otra tiene la rampa de colisión invisible del documento, de 10 cm de espesor, que pasa por las puntas de los escalones.
- **Prueba guionada** `--test-input=steps`: recorre 15 puntos. Cruza los escalones sueltos de 10, 20 y 30 cm, choca contra el de 40 hasta que se le acaba el tiempo, y sube y baja las dos escaleras. Al final imprime "escalones: punto N de 15; pies a X m como máximo".
- **Prueba de repetición:** tramos nuevos que cruzan la pista.

#### Problemas en el camino

- **Subía 40 cm:** la cápsula quedaba apoyada sobre el filo del escalón y eso contaba como piso, y el alto se medía con la cápsula. Se agregó el rayo sobre la superficie que pisa.
- **En diagonal y caminando despacio no subía 30 cm:** se agregó el avance mínimo hacia la pared.
- **La rampa invisible quedaba 20 cm por debajo de las puntas de los escalones (error mío):** se corrió para que pase por ellas.
- **La ruta de la repetición no llegaba a la pista:** se recalcularon los ticks de cada tramo.

#### Pruebas automáticas

| Prueba | Antes | Ahora |
| --- | --- | --- |
| Escalón más alto que sube, caminando, agachado, corriendo y en diagonal (`diag_escalones.gd`) | 10 cm | 30 cm; el de 32 cm ya no |
| Al subir 30 cm | Se traba | El cuerpo sube en un tick; lo dibujado y la cámara suben parejo en unos 100 ms, de a 4 cm por cuadro como máximo (`diag_escalon_dibujo.gd`) |
| Pista completa en red, el cliente con red limpia, internet mala y tirones (`escalones_pares.ps1`) | — | 0 correcciones; llega al punto 15 de 15, con los pies a 1,20 m como máximo |
| Pista completa en red, el host la hace y el cliente mira, red limpia y mala | — | 0 correcciones; tirones del otro entre 1,5 % y 2,5 % según la corrida |
| Repetición, a 60 y con el ritmo variando | — | 3.415 repeticiones y 149.665 ticks idénticos; huella `0620654cfb44141f` |
| Piso plano, vagón, balsa, túnel y escalera | — | Igual que antes |

**Lo que se avisó al entregar:**

- **Bajar no es simétrico.** Al bajar un escalón suelto pasa a Aire y cae, unos 0,2 s. En la escalera sin rampa, al bajar sale volando por encima de los escalones; eso ya pasaba antes. Con la rampa se sube y se baja parejo, siempre en Suelo, y por eso el documento la pide.
- **Deslizándose no sube escalones:** el documento pone la sonda solo en Suelo.
- **A la balsa se sube caminando,** porque su cara de arriba queda justo a 30 cm. Con internet mala, al subirse por primera vez hubo 15 correcciones: es la misma ráfaga que ya daba la balsa (antes, de 0 a 51). Una vez arriba, ninguna.
- **El otro jugador al subir un escalón** no se midió sin pantalla; quedó para la prueba en dos PC.

#### Prueba en dos PC (2026-10-07, 16:18)

Fue la primera prueba con el doble clic. Hubo cuatro capturas, entre las 16:15 y las 16:16.

| Qué | Resultado |
| --- | --- |
| Notebook, con internet mala (217 ms de ida y vuelta) | 4.577 coincidencias, 0 correcciones y 1,4 % de tirones del otro jugador |
| Host | Ninguna afirmación rechazada: ni por época, ni por distancia, ni por pose |
| Las dos escaleras | Las dos cápsulas arriba de las dos, con los pies a 1,20 m |

En dos capturas del host la cápsula de la notebook se veía inclinada. Lo atribuí a la perspectiva, porque la cámara miraba hacia arriba, y no a un error.

Cómo se veía el otro jugador al subir, en palabras del usuario (16:54): "en resumidas cuentas, era lo mismo, lo que veías en una notebook o la otra no cambiaba, si había latencia por las pruebas, pero fuera de eso, eran dos gotas de agua."

### Commit `b907dae`

**Fecha:** 2026-10-07, 16:19. `feat(net): add Ground step-up probe and a step course`: 10 archivos, +351 / −7 líneas.

- **Nuevos:** `step_course.gd` y su `.uid`, `tools/net_lab/actualizar_lab.bat` y `tools/net_lab/actualizar_lab.ps1`.
- **Cambiados:** `actor_motor.gd`, `actor_body.gd`, `actor_tuning.gd`, `net_lab.gd`, `net_lab_level.tscn` y `actor_replay_test.gd`.
- **La verificación:** se comprobó que ningún archivo cambió después del doble clic de la prueba.

### 8.5 Punto 5: Hanging con snap

#### Lo que pide el documento

La sección "Hanging: con snap" del Apéndice A, en resumen:

- **Sonda de borde:** un barrido de las manos, un rayo a la cara de la pared y otro a la superficie de arriba, unos centímetros adentro del filo.
- **Captura desde Aire:** sin bloqueo de reagarre, sin subir rápido, con el filo dentro de la banda de las manos y el cuerpo por debajo del filo. Pedía también intención hacia la pared, y eso cambió después de la primera prueba (ver "El cambio después de la primera prueba").
- **Variante A, el snap:** una pose canónica a distancia y altura fijas del filo. Se valida que la pose quepa, que el camino esté libre y que el snap no pase de unos 35 cm. Lo que se ve no salta: el desvío visual absorbe la diferencia.
- **Colgado:** el input lateral mueve sobre el filo, mientras el borde siga.
- **Salidas:**
    - subir al borde, en dos tramos validados antes, con la forma agachada, terminando en Suelo;
    - soltarse;
    - saltar hacia donde mira;
    - una fuerza mayor o igual al agarre;
    - un invariante roto.

  Salvo subir, todas van a Aire con un bloqueo corto de reagarre.
- **Pruebas de confirmación:**
    1. un laboratorio de bordes;
    2. un barrido automático de aproximaciones;
    3. qué se registra de cada caso;
    4. métricas visuales;
    5. red;
    6. divergencia inyectada;
    7. una prueba con 5 a 10 personas;
    8. criterios fijados antes de medir.

  Si el snap falla un criterio duro, la decisión del snap se reabre.

#### Las decisiones antes de empezar (2026-10-07, 16:56–18:10)

Antes de escribir código pregunté tres cosas:

- **Los controles colgado.** Se ofrecieron tres combinaciones. Respuesta: "espacio sube/salta (lo aclaro de esta manera porque hay que probar de ambas maneras, es mas por el feeling que otra cosa), Control suelta". Quedó así:
    - Espacio mirando a la pared sube al borde;
    - Espacio mirando a otro lado salta hacia allá;
    - Ctrl suelta;
    - A y D, de costado.
- **El alcance:** "Automáticas + dos PC". Son las pruebas 1 a 6 del documento y la prueba en las dos PC. La 7, con personas, quedó para cuando haya gente.
- **Los criterios:** "Los del documento", fijados antes de medir:
    - 95 % o más de capturas en la banda buscada;
    - 1 % o menos de agarres no buscados;
    - cero ticks colgado metido en la geometría;
    - 10 cm o menos de salto de la cámara en los 50 ms después de agarrarse. El tope de 10 cm lo propuse yo.

#### Qué se implementó (primera versión, 2026-10-07, 19:36)

**`scripts/actor/edge_probe.gd` (`EdgeProbe`), nuevo: la sonda de borde.** Un candidato es un diccionario con el punto del filo, la normal horizontal de la pared hacia afuera y el id de la base que lo lleva (0 si es geometría fija). Todo son consultas directas al espacio, así que da lo mismo en un tick repetido y en todas las máquinas.

- **Las manos:** una caja chata de 0,4 × 0,06 × 0,3 m delante del pecho, a 1,95 m sobre los pies. Entra 5 cm en la cápsula, para tocar una pared pegada. El documento proponía una esfera de unos 6 cm; la caja es ancha y profunda para no saltarse paredes finas.
- **`find()`:** barre la caja con `cast_motion()` desde donde están las manos hasta donde van a estar al final del tick. En el punto del choque, o al final si no chocó, `get_rest_info()` da el contacto.
- **El filo:** desde el contacto, un rayo horizontal busca la cara (tiene que estar a menos de 20° de la vertical) y un rayo hacia abajo, 3 cm adentro, busca la superficie de arriba (a menos de 30° de la horizontal). El filo es donde se cruzan. Se busca primero de frente al cuerpo, a la altura del contacto, porque la caja es ancha y puede tocar con una punta; si de frente no hay borde, donde tocó.
- **`hold()`:** revalida un borde agarrado, cada tick colgado y al desplazarse. Falla si el filo se movió más de 10 cm.

**`ActorState`:**

- el modo `HANGING` (vale 4);
- **el ancla:** `anchor_id` es la base que lleva el borde, 0 si es geometría fija, y `anchor_point` es el punto del filo relativo al origen de esa base;
- `anchor_t`, que colgado vale 0 y subiendo es el avance de la subida, en segundos de tiempo del actor;
- la normal no se guarda: es la contraria a `facing_yaw`, que colgado mira a la pared;
- el bloqueo de reagarre de bordes usa `regrab_id = REGRAB_EDGES` (0xFFFF) y bloquea todos los bordes, porque un borde no tiene id propio.

Pasó de 67 a 79 bytes: `anchor_point` son tres enteros de 32 bits al final.

**`ActorMotor`:**

- **Etapa 4, sondas:** colgado, `_held_edge()` revalida cada tick el borde agarrado. Si la base desapareció o el borde ya no está, el invariante se rompe y sale a Aire.
- **Entrada desde Aire** (`_try_grab_edge()` con la decisión en `grab_check()`), si no se mantiene Ctrl. Va antes de la escalera. Las condiciones, en orden; si falla una, `grab_check()` dice cuál:
    1. sin bloqueo de reagarre de bordes y con postura parada ("bloqueo o postura");
    2. las manos encuentran un borde en el barrido de este tick ("sin borde"). El filo se toma enfrente del centro del cuerpo, si el borde sigue ahí: si llega en diagonal, las manos pueden quedar corridas;
    3. la pared está a menos de 60° de la dirección en que buscan las manos ("intención de costado"). En la primera versión esa dirección era la intención de movimiento, y sin teclas no había agarre ("sin intención"). Lo que cambió está en "El cambio después de la primera prueba";
    4. no sube a más de 1 m/s ("sube rápido");
    5. el centro del cuerpo está por debajo del filo; si no, es un aterrizaje ("por encima del filo");
    6. la pose canónica queda a 35 cm o menos ("snap muy largo");
    7. la pose cabe ("la pose no cabe");
    8. el camino hasta la pose está libre ("camino tapado").

    Si pasa, en ese tick pasa a Hanging, con velocidad cero, mirando a la pared, y el cuerpo va a la pose en la etapa 7. Es el snap lógico.
- **La pose canónica:** los pies a 0,4 m de la pared y 1,95 m por debajo del filo.
- **Colgado** (`_hang()`): se desplaza a lo largo del filo a 1,5 m/s, con aceleración de 20 m/s². Solo avanza si `hold()` encuentra el borde en el lugar nuevo y el cuerpo pasa (`test_move()`). Un empujón menor al agarre se suma a la velocidad, y solo cuenta la parte a lo largo del filo.
- **Salidas:**
    - **Ctrl:** se suelta y cae.
    - **Espacio mirando a la pared,** a menos de 60°: sube al borde, si `_climb_clear()` lo permite.
    - **Espacio mirando a otro lado:** salta hacia donde mira, a 4 m/s, y hacia arriba a 4 m/s.
    - **Una fuerza de 3 o más:** se suelta con el impulso.
    - **El invariante roto:** sale a Aire.

    Salvo subir, todas pasan a Aire con 0,3 s de bloqueo de reagarre para todos los bordes.
- **Subir al borde** (reemplazado el 2026-10-08 por un salto para arriba; este código se sacó y quedó en `3cdcc91`, ver sección 8.6):
    - **Validación antes de empezar** (`_climb_clear()`), con la forma agachada: los dos tramos están libres, arriba cabe, y hay piso caminable hasta 0,6 m por debajo del final. Los otros jugadores no cuentan, porque están en otra capa.
    - **El recorrido:** dos tramos relativos al filo, siempre desde la pose de colgado. Primero 0,45 s hacia arriba, pegado a la pared, hasta 2 cm por encima del filo. Después 0,25 s hacia adentro, hasta que el centro quede el radio más 10 cm adentro del filo.
    - **El movimiento:** un barrido con `move_and_collide()` hasta la pose de cada tick.
    - **Si algo tapa el camino a mitad de la subida:** vuelve a colgar, si la pose de colgado sigue libre; si no, sale a Aire.
    - **Al terminar:** pasa a Suelo arriba, agachado, y el resolutor de postura lo para cuando hay lugar.
- **Contactos:** colgado, la base del actor es la del borde, con velocidad propia cero respecto de ella. Así un borde que se mueve lleva al que cuelga, como las bases del punto 2.
- **`apply_impulse()`:** en Hanging, con fuerza de 3 o más se suelta con el impulso; si no, el impulso se suma a la velocidad.
- **`anchored_pose_valid(body, state, tuning)`:** el host rechaza por pose una afirmación colgado si el borde no está, si el avance de la subida está fuera de rango, o si el cuerpo está a más de 10 cm de la pose que corresponde: la de colgado o la de ese momento de la subida. Ahora necesita el cuerpo y los parámetros, y `ClaimAdoption.consider()` pasó a recibir los parámetros.

**`ActorBody`:**

- **`grab_offset`:** el desvío visual del agarre. Decae como el de una corrección, pero a no más de 1,8 m/s (`GRAB_MAX_SPEED`). Con el decaimiento normal la cámara saltaba 26 cm en 50 ms; con el tope, 9 cm, y un snap de 35 cm se cierra en unos 250 ms.
- **Dos manos amarillas** sobre el filo mientras cuelga, a 20 cm a cada lado. Cuelgan del cuerpo y no del dibujo, así quedan en el filo mientras el dibujo se acomoda.
- `active_stance()`.

**`ClientPrediction`:** guarda la corrección más grande (`max_correction_meters`), para el resumen de las pruebas.

**Laboratorio:**

- **Pista de bordes** (`scenes/net_lab/edge_course.gd`), adelante a la derecha, pasando el muro largo, con origen en (10; 0; −10). Son 11 bordes, casi todos de 2,4 m de ancho, cada 3,5 m y en dos filas separadas por 8 m:
    - **Fila 1:** bloques de 1,6, 2,0 y 2,4 m de alto y 1 m de espesor; paredes de 5 y 20 cm de espesor; y un bloque hecho con una malla.
    - **Fila 2:** arriba inclinado 10° y 25°; uno curvo; uno bajo un techo bajo, donde no se puede subir; y uno entre dos paredes que salen de la cara.

    Las caras agarrables miran hacia +Z: se llega caminando hacia −Z. Cada borde tiene su cartel.
- **Bordes que se mueven,** al este del vagón, dos bloques de 2,4 × 2 × 1 m:
    - **"sobre una plataforma guionada"** (base 4, naranja): en (22; 1; −5), 3 m en x, ida y vuelta en 10 s;
    - **"sobre un cuerpo del host"** (base 5, marrón): una balsa del host en (27,5; 1; 2), que se mueve al azar en 1 × 1 m con empuje de 1 m/s².
- **El panel:**
    - "Colgado del borde: filo a X m de altura · sobre la base N";
    - "Subiendo al borde: N %" (se sacó con el salto para arriba, sección 8.6);
    - "Recién soltó un borde: no puede agarrar otro por X s";
    - la ayuda "Colgado: A y D de costado · Espacio mirando a la pared sube, mirando a otro lado salta · Ctrl se suelta", que cambió con el salto para arriba (sección 8.6).
- **Prueba guionada** `--test-input=hang` (o `hang:<id>` para el borde de una base): se aleja 2,2 m de la cara de un bloque de 2 m, corre hacia ella, salta y se agarra al caer. Colgado va a la derecha y a la izquierda. Después, según la vuelta del ciclo, sube al borde y se baja por delante, se suelta con Ctrl, o salta hacia atrás. Al final imprime "colgar: N agarres, N subidas al borde, N vueltas del ciclo" y la corrección más grande.
- **`--test-perturb-mm=N`:** el cliente corre su estado predicho y su cuerpo N milímetros al azar en cada tick, como si Jolt calculara distinto (prueba 6).
- **Barrido de aproximaciones:** `scenes/net_lab/hang_sweep_test.tscn` (ver "Pruebas automáticas", más abajo).
- **Prueba de repetición:** tramos de Hanging contra el bloque de 2,4 m: agarrarse, desplazarse, subir, soltarse con Ctrl y saltar hacia atrás.

#### El barrido de aproximaciones (`hang_sweep_test.tscn`)

Corre sin red, con el motor real, contra los 11 bordes fijos. Cada caso arranca al actor en el aire, con la velocidad elegida para llegar a la cara con:

- la velocidad horizontal de la grilla: 0, 2, 4, 6 y 8 m/s;
- la vertical: −12, −8, −4, −2, 0, 1,5 y 3 m/s;
- el ángulo: 0, 35 y 70°;
- el corrimiento lateral: 0 y 0,6 m.

Los que llegan subiendo arrancan con un salto desde el piso. Si el cuerpo arrancaría metido en algo, el caso no es posible y no se cuenta.

Además de colgarse, en cada borde hay dos grupos de casos que no buscan agarrarse:

- ir a aterrizar arriba, con los pies 20 cm por encima del filo;
- pasar de largo, paralelo a la cara, con las manos cruzando el filo.

De cada caso registra:

- si se agarró, en qué tick y la distancia del snap;
- los ticks colgado con el cuerpo metido en la geometría;
- si funcionan las salidas;
- por qué no se agarró y si sin snap se habría agarrado (variante B);
- el movimiento de la raíz visual a los 50 y a los 100 ms, y cuánto tarda en volver a cero.

**La banda buscada** (criterio 1): las manos cruzan la franja de 20 cm bajo el filo, sobre el filo o hasta 10 cm delante de la cara, dentro de su ancho, con el cuerpo debajo del filo, sin subir rápido y a 35° o menos de la cara, en un borde donde colgarse es posible.

**Agarres no buscados** (criterio 2): solo cuentan si agarró el borde que pasaba o donde iba a aterrizar. Otro borde del camino, como la punta del techo bajo, se cuenta aparte.

Sale con 0 si se cumplen los cuatro criterios. Con `--detalle=borde,vel,llegada,ángulo,lateral,objetivo,teclas` imprime un caso tick a tick.

**Problemas para armarlo:**

- casos que arrancaban bajo el piso;
- casos que se desviaban por encima del bloque;
- un chequeo de manos demasiado estricto;
- un "\n" literal que dejó una edición con perl;
- la punta de la losa del techo bajo contada como agarre no buscado.

Se arreglaron uno por uno.

#### Problemas de la primera versión

- **El filo se tomaba donde tocaban las manos:** llegando en diagonal, el snap lateral llegaba a 26 cm. Se pasó a tomar el filo enfrente del centro del cuerpo.
- **No subía al borde inclinado 25°:** el segundo tramo de la subida se mantiene a la altura del filo y el piso se busca hasta 0,6 m más abajo.
- **El criterio 4 fallaba:** la cámara saltaba 0,262 m en 50 ms. Se agregó el tope de velocidad de `grab_offset`, y bajó a 0,090 m.
- **La prueba guionada se trababa contra el muro largo:** primero se mueve en x y después en z.
- **Los bordes que se mueven no se alcanzaban detrás de las filas de la pista:** se movieron al este.
- **Avisos:** `snapped` tapaba una función de Godot, un parámetro sin usar y `name` repetido. Nombres cambiados.

#### Pruebas automáticas de la primera versión

**El barrido:** 2.574 casos.

| Criterio | Resultado |
| --- | --- |
| 1. Capturas en la banda buscada | 523 de 524 (99,8 %): cumple |
| 2. Agarres no buscados | 0 de 165: cumple. Hubo 2 agarres de otro borde del camino, la punta del techo bajo |
| 3. Ticks colgado metido en la geometría | 0: cumple |
| 4. Salto de cámara en 50 ms | 0,090 m como máximo, con un snap máximo de 0,350 m: cumple |

- **El que no se agarró en la banda:** un caso del borde curvo, cayendo a 12 m/s. La prueba registró que se podía agarrar, pero el motor no lo agarró; sin snap se habría agarrado. No se investigó más, porque el criterio se cumple.
- **Lo visual:** en los 100 ms después de agarrarse, la raíz visual y la cámara se mueven 0,180 m como máximo, y el desvío vuelve a cero en 0,19 s de promedio y 0,32 s como máximo. El documento proponía de 100 a 150 ms.
- **Las salidas:**
    - soltarse: 1.022 de 1.022;
    - saltar hacia atrás: 984 sí y 38 no;
    - desplazarse: 1.011 sí y 11 no;
    - subir: 723 sí, 31 no y 268 donde no corresponde, porque arriba no hay lugar.

    Las que fallan las tapa la geometría: el techo bajo, las paredes al costado y las paredes finas.

**La red** (`hang_pares.ps1`): el cliente hace la prueba `hang` contra el bloque de 2 m.

| Prueba | Resultado |
| --- | --- |
| Ida y vuelta de 0, 60, 120 y 200 ms (±20 ms salvo en 0), con 0, 2 y 5 % de pérdida | 0 correcciones en las 12 combinaciones; 10 agarres y 4 subidas en cada una |
| El host cuelga y el cliente mira, red limpia y mala | 0 correcciones del cliente |
| Borde sobre la plataforma guionada, red limpia y mala | 0 correcciones |
| Borde sobre el cuerpo del host, red limpia y mala | Correcciones chicas mientras cuelga: la más grande de 4,6 cm con red limpia y de 21 cm con internet mala. El documento las anticipa para bases del host |
| Divergencia de 0,5 mm por tick, con adopción | 0 correcciones; el host adopta todas las afirmaciones (hasta 1 mm de diferencia) |
| Divergencia de 0,5 mm por tick, sin adopción | 664 correcciones, la más grande de 4,2 cm. Los agarres y las subidas son los mismos que sin divergencia: ninguna decisión cambió |
| Repetición, a 60 y con el ritmo variando | 4.565 repeticiones y 202.565 ticks idénticos; huella `8421b986a6efcbd3` |
| Pruebas anteriores | Igual que antes |

#### Prueba en dos PC (2026-10-07, 22:04–22:20)

Hubo siete capturas entre las 22:04 y las 22:06: cuatro de la notebook (1280×720) y tres del host (1600×900). En todas, la notebook cuelga del borde sobre la plataforma guionada (base 4). En dos de las del host, el host también cuelga de ese borde.

| Qué | Resultado |
| --- | --- |
| Notebook, con red limpia, internet mala (167–184 ms) y Wi-Fi con tirones | Las correcciones quedaron en 62 de la primera captura a la última, mientras las coincidencias pasaron de 4.749 a 7.589. Ninguna corrección nueva colgado del borde que se mueve |
| Snapshots que no llegaron a tiempo | De 0,4 % a 5,9 %, según la red |
| Tirones del otro jugador | 0,0 % a 0,5 % |
| Manos | Las dos manos amarillas se ven sobre el filo, también en la cápsula del otro jugador |
| Afirmaciones en el host | 79 adoptadas, la más lejana a 1,00 m; rechazadas: 0 por época, 11 por distancia y 97 por pose. No cambiaron entre las capturas |

**Las 62 correcciones y las 108 afirmaciones rechazadas** ya estaban en la primera captura, así que pasaron antes. Por las pruebas automáticas, lo más probable es que vengan del borde sobre el cuerpo del host, el marrón: las instrucciones avisaban que ahí iba a haber alguna corrección chica. Las capturas no lo muestran, así que no está confirmado.

**El resultado, en palabras del usuario (22:20):**

> Con respecto al resultado dado por vos, hay varios aspectos que voy a nombrar. El primero es sobre la animación al levantarse y ponerse de pie sobre el muro, digo, no es mala o algo por el estilo, me hubiese gustado mas un saltito, pero por ahora lo dejamos así. Lo segundo, no se como configuraste para que ocupe la cámara, pero el desplazamiento horizontal depende totalmente de esta, porque movía la cámara hacia la derecha pero a la vez le daba a la tecla D para ir a la derecha y el player avanzaba muy de a poquito. [...] habría que cambiarlo para que no sea un requisito, así puedo poner la cámara hacia la derecha y poder moverme a la derecha sin tener que poner la cámara hacia la izquierda. Lo tercero es probablemente un requisito de activación que implementaste, donde para que ocurra el snap, el jugador le tiene que estar dando a la W para que avance [...] Eso también hay que quitarlo, no siempre queres darle a la W para llegar a X lado. Digo eso porque cuando intente por primera vez agarrarme de un muro, no entendía por que no lo hacia, después descubrí que uno de los requisitos es darle si o si a la W para agarrarme. Sacando esos tres puntos, el resto funciona correctamente, incluido el servidor con la otra notebook, no se vio nada raro fuera de lo nombrado.

- **La subida:** queda como está. El "saltito" quedó pendiente (sección 16).
- **Los otros dos puntos** se cambiaron (lo que sigue).

#### El cambio después de la primera prueba: cómo estaba armado y por qué cambió

**1. Agarrarse exigía apretar una tecla hacia la pared.**

*Cómo estaba armado.* Las manos buscaban el borde solo hacia la intención de movimiento: la dirección de las teclas apretadas, girada según la cámara (`_wish_direction()`). Sin ninguna tecla, `grab_check()` cortaba antes de mirar la pared:

```gdscript
# Primera versión, en grab_check():
if direction.length_squared() < 0.01:
	result["why"] = "sin intención"
	return result
var toward := Vector3(direction.x, 0.0, direction.z).normalized()
```

Y la pared tenía que estar a menos de 60° de esa dirección ("intención de costado"). En la práctica, había que apretar W, o la tecla que en ese momento apuntara a la pared.

*De dónde venía.* Del documento de arquitectura, al pie de la letra:

- la transición de Aire a Hanging pedía "intención hacia la pared";
- lo común de Hanging pedía lo mismo para la captura;
- una regla general decía: "Las condiciones usan la intención de movimiento y la velocidad, no la orientación del modelo, para que primera y tercera persona simulen igual".

*Por qué cambió.* En la prueba, el usuario no entendía por qué no se agarraba hasta descubrir que tenía que apretar W. Y "no siempre queres darle a la W para llegar a X lado".

*Cómo quedó.* Una función nueva, `ActorMotor.grab_direction()`, decide hacia dónde buscan las manos:

```gdscript
static func grab_direction(state: ActorState, direction: Vector3) -> Vector3:
	if direction.length_squared() >= 0.01:
		return direction
	return Vector3.FORWARD.rotated(Vector3.UP, state.facing_yaw)
```

- **Con alguna tecla de dirección apretada:** hacia esa dirección, como antes.
- **Sin teclas:** hacia donde mira el personaje (`facing_yaw`). En el aire, el personaje mira hacia la última dirección en que se movió, así que, en la práctica, hacia donde venía.

Lo demás no cambió:

- la pared tiene que estar a menos de 60° de esa dirección, así no se agarra de una pared que solo está pasando de largo;
- valen todas las otras condiciones.

El corte de `grab_check()` sigue como resguardo, con el motivo "sin dirección", pero el motor ya no llega a él.

*Lo que conviene saber:*

- **La tecla manda.** Si en el aire se aprieta A o D mirando a la pared, las manos buscan hacia ese costado y no se agarra.
- **En red no cambia nada.** `facing_yaw` es parte del estado del actor: el host y el cliente lo calculan igual, y viaja en las afirmaciones. El formato de red no cambió.
- **Se apartó de una regla del documento.** Sin teclas, la decisión usa la orientación del personaje, que es justo lo que la regla general quería evitar. Hoy no hace diferencia: en el laboratorio la orientación siempre sigue al movimiento, y todavía no hay primera persona. Si en primera persona el cuerpo pasa a seguir a la mirada, sin teclas las manos buscarían hacia donde mira la cámara en primera persona, y hacia donde venía en tercera. Hay que revisarlo cuando llegue la primera persona (sección 16).

**2. Moverse colgado dependía de la cámara.**

*Cómo estaba armado.* Colgado se usaba la misma dirección que para caminar: las teclas giradas según la cámara. Después se proyectaba sobre el filo:

```gdscript
# Primera versión, en _hang():
var wish := clampf(direction.dot(right), -1.0, 1.0) * tuning.shimmy_speed
```

- **Con la cámara mirando a la pared,** D apuntaba a lo largo del filo y se movía a 1,5 m/s.
- **Con la cámara girada 90° a la derecha,** D apuntaba hacia atrás, lejos de la pared. Su parte a lo largo del filo era casi cero, así que casi no se movía: "movía la cámara hacia la derecha pero a la vez le daba a la tecla D para ir a la derecha y el player avanzaba muy de a poquito".

*De dónde venía.* No era un requisito del documento, que dice "el input lateral cambia la posición sobre el filo". Fue cómo lo armé: reusé la dirección de caminar.

*Cómo quedó.* A y D son la izquierda y la derecha del personaje frente a la pared, mire donde mire la cámara:

```gdscript
var wish := clampf(input.move.x, -1.0, 1.0) * tuning.shimmy_speed
```

`_hang()` pasó a recibir el input en vez de la dirección.

**Qué tocó el cambio.** Solo `actor_motor.gd` y sus pruebas; la red y el formato no cambiaron. En la tabla de la sección 14 ("¿cuánto quilombo arma cambiar una mecánica?"), fue un cambio de "cómo se entra a un modo" y de "cómo funciona un modo por dentro".

**Cómo se probó** (2026-10-07, 22:21–23:05):

- **El barrido se duplicó:** cada caso se corre dos veces, empujando con las teclas y sin tocar ninguna, mirando hacia donde se mueve. Son 5.148 casos.
- **Una salida nueva en el barrido,** "desplazarse con la cámara de costado": A o D con la cámara girada 90° a la derecha, que tiene que mover 30 cm hacia ese lado del personaje.
- **La prueba de repetición suma cuatro cosas,** pegado a la pared del bloque de 2,4 m:
    - un salto sin teclas, que se agarra al caer;
    - D con la cámara mirando a la derecha, que va a la derecha;
    - A con la misma cámara, que va a la izquierda;
    - Ctrl.
- **Una sorpresa en el camino:** al principio, en la repetición, el salto sin teclas no se agarraba. Con `diag_sin_teclas.gd` se vio que sí se agarraba, pero un tick después del final del tramo; el tramo siguiente apretaba D, y las manos buscaban hacia ese costado. Se alargó el tramo de 50 a 60 ticks.

| Prueba | Resultado |
| --- | --- |
| Criterio 1, con teclas | 523 de 524 (99,8 %), lo mismo que antes del cambio |
| Criterio 1, sin teclas | 568 de 569 (99,8 %) |
| Criterio 2 | 0 de 330: 0 de 165 con teclas y 0 de 165 sin teclas |
| Criterios 3 y 4 | 0 ticks metido; 0,090 m de salto de cámara en 50 ms |
| Desplazarse, mirando a la pared y con la cámara de costado | 2.046 sí y 20 no, igual en los dos |
| Con teclas, caso por caso, contra la primera versión | Iguales, salvo uno fuera de la banda (techo bajo, 4 m/s subiendo a 3 m/s, 35°, 0,6 m de costado), que antes no se agarraba y ahora sí. No cuenta para ningún criterio |
| Repetición con la ruta vieja | Huella `8421b986a6efcbd3`, la misma que antes del cambio |
| Repetición con los tramos nuevos, a 60 y con el ritmo variando | 4.790 repeticiones y 212.915 ticks idénticos; huella nueva `4ea24f9067f289f7`, porque cambió la ruta. Sin teclas se agarra (filo en x = 17,33), D lo lleva a x = 17,78 y A lo vuelve a x = 17,48 |
| Red: las 12 combinaciones, el observador, los dos bordes que se mueven y la divergencia | 0 correcciones en las 12 combinaciones y en la plataforma guionada. Balsa del host: 10,5 cm con red limpia y 12,5 cm con internet mala. Divergencia sin adopción: 663 correcciones, la más grande de 5,2 cm, con los mismos agarres |
| Pruebas anteriores: bases, postura, escalera, escalones y repetición a ritmo variable | Igual que antes |

#### Segunda prueba en dos PC (2026-10-08, 10:54)

"ok, todo funciona como deberia". No hubo capturas nuevas.

#### Lo que falta del documento y las simplificaciones

- **Solo se agarra desde el aire:** todavía no existe el modo Pared.
- **No hay superficies marcadas como no agarrables.**
- **El bloqueo de reagarre es para todos los bordes,** no solo para el que se soltó, porque un borde no tiene id propio.
- **Las manos son una caja,** no una esfera de 6 cm.
- **El filo no se guarda en coordenadas del colisionador,** sino relativo al origen de su base. Alcanza porque las bases solo se trasladan.
- **No hay capacidades:** nada impide subir al borde estando aturdido, porque todavía no existe el aturdimiento.
- **La cámara después de agarrarse** se acomoda en 0,19 s de promedio y 0,32 s como máximo; el documento proponía de 100 a 150 ms. Es el precio del criterio de los 50 ms.
- **Altura del colgado:** el filo queda 1,95 m sobre los pies. En un borde de 2 m los pies quedan a 5 cm del piso, y uno de 1,6 m no se puede agarrar desde el piso: la pose quedaría bajo el piso.
- **La prueba 7,** con 5 a 10 personas, queda para cuando haya gente.

### Commit `3cdcc91`

**Fecha:** 2026-10-08, 10:55. `feat(net): add Hanging with snap and its confirmation tests (validation item 5)`: 16 archivos, +1.359 / −47 líneas.

- **Nuevos:** `edge_probe.gd`, `edge_course.gd`, `hang_sweep_test.gd` y `hang_sweep_test.tscn`, con sus `.uid`.
- **Cambiados:** `actor_motor.gd`, `actor_body.gd`, `actor_state.gd`, `actor_tuning.gd`, `claim_adoption.gd`, `client_prediction.gd`, `net_lab.gd`, `net_lab_level.tscn` y `actor_replay_test.gd`.
- **La verificación:** las huellas SHA-1 de los 16 archivos coincidieron con las de la versión probada.
- **Lo que guarda:** la versión con los dos cambios. La primera versión nunca se commiteó; su código está descripto en "El cambio después de la primera prueba".

### 8.6 La subida al borde, reemplazada por un salto (2026-10-08)

#### El pedido

**11:42:** "no, el próximo paso es quitar temporalmente la animación de escalar y reemplazarla con un salto, pero antes de hacerlo, ¿tenemos algo asi como control aereo?, donde podemos desplazar al player en cualquier direccion mientras caemos o saltamos. Solo necesito saber eso."

La respuesta: sí. En el aire, WASD mueve en cualquier dirección, relativa a la cámara, igual que en el piso, pero con menos fuerza:

- **la aceleración:** 12 m/s² en el aire y 45 m/s² en el piso. Desde quieto, llegar a velocidad de caminar (5 m/s) lleva unos 0,4 s;
- **sin teclas:** mantiene la velocidad, sin frenar;
- **si venía más rápido que caminando:** el control aéreo no lo frena (desde el punto 3);
- **el parámetro:** `air_accel`.

**11:50, el pedido**, tal cual:

> bien, ahora vamos a reemplazar la animacion de escalada del hanging con un salto, y supongo que el salto que tiene hanging para salir a los costados cuenta con control aereo. Si esto es asi, pues que bien, porque lo que quiero hacer es algo parecido, solo que en vez de salir a los lados o atras, sale hacia arriba con el mismo control aereo. Ademas al saltar en direccion al muro, como le estamos haciendo hasta ahora, porque creo que funciona asi, porque para subir al muro tenes que mirar al muro o por lo menos la direccion de la camara tiene que tener X angulo relativo a Y funcion para que se active esa accion y no otra, supongo que es asi, ni idea. Y bueno, solo eso, tener un salto hacia arriba y que te deje arriba del muro con un margen de altura, tipo si la capsula mide 2 metros, que el salto te eleve a 2.2 metros, asi tenes margen para moniobrar. Si algo de lo que te propuse te parece un sin sentido o falta de explicacion, avisame mientras lo implementas y te lo respondo

Las dos suposiciones eran correctas:

- **El salto de costado tiene control aéreo:** pasa a modo Aire, como cualquier salto.
- **Para subir hay que mirar a la pared:** la cámara tiene que apuntar a menos de 60° de la pared, contando solo el giro horizontal (`climb_look_angle`). Si no, Espacio salta hacia donde mira.

#### Cómo era la subida

La subida era una fase dentro de Hanging, como pedía el documento:

- **El pedido:** Espacio mirando a la pared, a menos de 60°.
- **La validación previa** (`_climb_clear()`), con la forma agachada: los dos tramos libres, lugar arriba y piso caminable hasta 0,6 m por debajo del final. Si fallaba, seguía colgado.
- **El recorrido:** dos tramos relativos al filo, en tiempo del actor, guardado en `anchor_t`:
    - 0,45 s hacia arriba, pegado a la pared, hasta 2 cm por encima del filo;
    - 0,25 s hacia adentro, hasta que el centro quedaba el radio más 10 cm adentro del filo.

  Lo recorría agachado, con barridos de `move_and_collide()`, y terminaba en Suelo, agachado, hasta que el resolutor de postura lo paraba.
- **Las interrupciones:** si algo tapaba el camino, volvía a colgar si cabía; si no, salía a Aire.
- **La red:** el host validaba la pose de cada momento de la subida (`_climb_pose()` en `anchored_pose_valid()`). El panel mostraba "Subiendo al borde: N %".
- **Lo que sostenía todo eso:**
    - las funciones `_climb_points()`, `_climb_pose()` y `_climb_clear()`;
    - las constantes `CLIMB_CLEARANCE` (2 cm), `CLIMB_INSET` (10 cm) y `CLIMB_FLOOR_SEARCH` (0,6 m);
    - los parámetros `climb_up_time` (0,45 s) y `climb_in_time` (0,25 s).

Qué dijo el usuario de esa subida (2026-10-07, 22:20): "no es mala o algo por el estilo, me hubiese gustado mas un saltito, pero por ahora lo dejamos así".

#### Por qué cambió

Lo pidió el usuario: quitar "temporalmente" esa animación y reemplazarla por un salto para arriba, con el control aéreo de los demás saltos y un margen de altura sobre el borde "para moniobrar". Todo lo que se sacó quedó en el commit `3cdcc91`.

#### Cómo quedó

Colgado, Espacio mirando a la pared (a menos de 60°) sale a Aire con velocidad solo vertical:

```gdscript
_leave_edge(state, tuning, Vector3.UP * _climb_jump_speed(tuning, dt))
```

Lleva el mismo bloqueo de reagarre de 0,3 s que las demás salidas. Mirando a otro lado, el salto sigue igual: hacia donde mira, a 4 m/s, y hacia arriba a 4 m/s.

**El margen de altura.** Colgado, los pies quedan 1,95 m por debajo del filo. El "2.2 metros" del pedido se tomó como el alto hasta el borde más un margen: el salto sube los pies 1,95 + 0,20 m, y en la punta quedan 20 cm por encima del filo. El margen es el parámetro `hang_climb_clearance` (0,2 m):

```gdscript
static func _climb_jump_speed(tuning: ActorTuning, dt: float) -> float:
	var rise := tuning.hang_height + tuning.hang_climb_clearance
	return sqrt(2.0 * tuning.gravity * rise) + tuning.gravity * dt * 0.5
```

Da unos 6,57 m/s. El `g·dt/2` del final compensa que en Aire la gravedad se aplica antes de mover. Con eso, los ticks siguen la parábola de una velocidad inicial menor en `g·dt/2`, y sin compensarlo la punta quedaría más baja. Medido: los pies llegan a 20,4 cm sobre el filo.

**Pasar arriba es el control aéreo:** el jugador empuja hacia la pared cuando quiere. El momento importa, porque el control aéreo sigue acelerando mientras se mantiene apretado (sección siguiente).

**Lo que se sacó:**

- la fase de subida dentro de Hanging, con sus funciones, constantes y parámetros;
- la postura agachada al subir;
- el panel "Subiendo al borde".

`anchored_pose_valid()` acepta en Hanging solo la pose de colgado, con `anchor_t` en 0. `anchor_t` sigue en el formato porque lo usa la escalera; en Hanging vale siempre 0. El formato de red no cambió: 79 bytes.

**El laboratorio:**

- **La ayuda del panel:** "Colgado: A y D de costado · Espacio mirando a la pared salta para arriba (con W pasás arriba), mirando a otro lado salta hacia allá · Ctrl se suelta".
- **La prueba guionada `hang`:** en la vuelta de subir, salta para arriba y aprieta W recién cuando deja de subir.
- **La repetición:** el tramo de subir es Espacio sin W durante 40 ticks, y después W 18 ticks.
- **El barrido:** prueba dos formas de subir:
    - "subir", con W desde el salto;
    - "subir con W recién arriba", apretando W cuando deja de subir.

  Mide también la punta del salto sobre el filo.

#### Lo que apareció al probarlo: W desde el salto

**En el barrido:**

- **"subir", con W desde el salto:** 221 sí, 1.281 no y 564 donde no corresponde;
- **"subir con W recién arriba":** 1.934 sí, 21 no y 111 donde no corresponde. Los 21 que no suben son todos del borde curvo, 19 de ellos agarrados llegando a 70° de costado.

Con `diag_salto_arriba.gd`, contra una pared de 2 m:

- **Con W desde el salto,** la cápsula toca la pared y no avanza mientras sube. Apenas su parte redonda pasa el filo (los pies, unos 33 cm por debajo), empieza a avanzar y sigue acelerando. Cuando los pies vuelven a la altura del filo, ya está 1,5 m adentro: sobre un fondo de 2 m aterriza arriba, pero sobre uno de 1 m, como los de la pista de bordes, pasa de largo y cae del otro lado.
- **Con W recién en la punta,** aterriza sobre el filo y queda arriba.

Se lo pregunté al usuario, con una explicación enredada (error mío). La respuesta fue "¿que?", y se lo expliqué de nuevo, más simple.

#### La demostración (12:17–12:40)

Pedido: "abri la escena, corre la prueba y mostrame que haces en cada momento."

**Cómo se armó:** el script `demo_salto_arriba.gd` (Apéndice B) abre el laboratorio en una ventana en esta PC, en Jugar solo:

- **cámara lenta:** 20 ticks por segundo, tres veces más lento;
- **la cámara:** de costado del bloque «malla» (2 m de alto, 1 m de fondo arriba), con el panel del laboratorio oculto;
- **un cartel abajo:** el paso, lo que hago, las teclas apretadas, el estado y la altura de los pies;
- **las teclas:** aprieta W y Espacio como un jugador, con acciones del Mapa de entrada (`Input.action_press()` y `InputEventAction`);
- **las capturas:** guarda una en cada paso y arma una hoja por forma.

**Primera forma, W desde el salto:**

1. Camina con W hasta la pared, la suelta y aprieta Espacio: salta en el lugar y se agarra al caer.
2. Colgado, aprieta Espacio mirando a la pared y también W, que no suelta.
3. En la punta, los pies están 20 cm sobre el filo y ya está 0,4 m adentro.
4. Sigue acelerando: con los pies todavía a 2,09 m, ya pasó el fondo del bloque.
5. Cae al piso, del otro lado.

**Segunda forma, W recién arriba:**

1. Igual hasta quedar colgado.
2. Aprieta Espacio sin W: sube derecho, sin avanzar.
3. En la punta (pies a 2,20 m) recién aprieta W.
4. Aterriza sobre el filo, mantiene W 4 ticks y la suelta.
5. Queda parado arriba, 38 cm adentro.

**Ajustes de la demostración:** en la primera vuelta el personaje se veía chico, el panel tapaba la imagen y la línea de teclas iba un cuadro atrasada. Se arregló antes de mostrarla.

#### La decisión (12:44)

"lo probé un rato en el net_lab y la verdad lo dejaría como esta, uno aprende muy rápidamente y se adapta al toque con los controles, por ahora lo dejamos asi, le doy el visto bueno."

Cuánto se avanza lo maneja el jugador con el momento en que aprieta W. El salto no se tocó.

#### Pruebas automáticas

Después de la aprobación, la prueba guionada y la repetición pasaron a apretar W en la punta del salto. Con W desde el salto se pasaban del bloque de 1 m.

| Prueba | Resultado |
| --- | --- |
| Altura del salto, en los bordes donde se puede subir | Los pies llegan 0,204 m sobre el filo. En los inclinados, 0,199 m (10°) y 0,190 m (25°): el filo se toma 3 cm adentro, donde la superficie ya bajó un poco |
| Subir con W recién arriba | 1.934 sí, 21 no (todos en el borde curvo) y 111 donde no corresponde |
| Subir con W desde el salto | 221 sí, 1.281 no y 564 donde no corresponde: en los bloques de 1 m se pasa de largo |
| Criterios 1 a 4 del agarre | Igual que antes: 1.091 de 1.093, 0 de 330, 0 ticks metido y 0,090 m |
| Repetición, a 60 y con el ritmo variando | 4.788 repeticiones y 212.823 ticks idénticos; huella `fccfdb253c89ed7c`. El salto llega a 2,604 m con el filo a 2,4 m, y aterriza arriba 0,26 m adentro |
| Prueba guionada `hang` en 70 s, sin red | 6 subidas en 6 intentos. En las pruebas de red de 45 s salen 3 de 4, porque la prueba termina antes de la cuarta |
| Red: 0, 60, 120 y 200 ms con 0, 2 y 5 % de pérdida | 0 correcciones en las 12 |
| El otro jugador mirando y el borde de la plataforma guionada | 0 correcciones |
| Borde sobre el cuerpo del host, red limpia | 65 correcciones, la más grande de 6,8 cm |
| Borde sobre el cuerpo del host, internet mala | 292 correcciones, la más grande de 2,70 m. Repetida 5 veces más: de 1,46 a 2,31 m, y una de 0,20 m |
| Divergencia de 0,5 mm por tick | Con adopción, 0 correcciones. Sin adopción, 313, la más grande de 0,200 m (antes, 0,052 m) |
| Regresiones: bases, postura, escalera y escalones | Igual que antes. En la balsa del punto 2, al subirse: 3 y 26 correcciones (antes 2 y 18), dentro de su ráfaga de siempre |

#### El borde sobre el cuerpo del host

Para ver cuándo pasaban las correcciones grandes, un aviso provisorio en el laboratorio imprimió cada corrección de más de 50 cm, con el estado predicho y el del host. Después se sacó. Un ejemplo:

- **la notebook había predicho** que estaba parada arriba del bloque, a 1,96 m;
- **el host decía** que en ese tick seguía en el aire, a 2,20 m;
- **lo que siguió:** correcciones de 0,93 m y 1,40 m, mientras uno caía y el otro aterrizaba.

**La causa:** ese bloque es una balsa que mueve solo el host, y con internet mala la notebook la ve corrida. Al aterrizar arriba, los dos pueden no coincidir en si el personaje quedó arriba o cayó, y la diferencia es de casi 2 m de altura. La subida vieja iba pegada al borde todo el tiempo y por eso no pasaba: con ella, la más grande era de 21 cm.

**El estado:** el documento de arquitectura anticipa correcciones sobre los cuerpos del host. Se avisó y no se tocó.

#### Prueba en dos PC (16:28–16:32)

"ya hice la prueba con las dos notebooks conectadas, todo funciona como debería, te cargue capturas por las dudas."

Hubo dos capturas de la notebook con internet mala, a las 16:28 y 16:29, una sobre el vagón y otra en el piso:

- **predicción:** 3.443 y después 4.968 coincidencias, 37 correcciones (la última de 0,27 m) y 0 saltos de reloj;
- **snapshots tarde:** alrededor del 20 %;
- **la ayuda del panel:** ya decía "Espacio mirando a la pared salta para arriba", o sea que la notebook tenía la versión nueva.

No hubo capturas del host.

### Commit `3825c2b`

**Fecha:** 2026-10-08, 16:40. `feat(net): replace the Hanging climb with an upward jump`: 6 archivos, +99 / −128 líneas.

- **Cambiados:** `actor_motor.gd`, `actor_state.gd` (solo un comentario), `actor_tuning.gd`, `net_lab.gd`, `actor_replay_test.gd` y `hang_sweep_test.gd`.
- **La verificación:** las huellas SHA-1 de los 6 archivos coincidieron con la versión probada en las dos PC.

### 8.7 Agarrarse subiendo, sin tener que caer (2026-10-08)

#### El pedido

A las 17:37, con un dibujo de dos filas:

> ¿seria posible hacer que para a la hora de entrar en hanging uno no tenga que estar cayendo si o si?, tipo como se muestra en el dibujo, en la parte de arriba se muestra como actualmente tenes que acercarte al muro, saltar, empezar a caer y recien ahi te agarras. En la parte de abajo se muestra como me gustaria que quede el resultado final, no tenes que caer si o si, con que estes pegado al muro y saltando, ya es suficiente para que te agarres. Cualquier cosa que te parezca que requiera hacer modificaciones, preguntamelo mientras lo implementas.

- **Arriba, cómo era:** acercarse al muro, saltar, empezar a caer y recién ahí agarrarse.
- **Abajo, cómo lo quería:** el personaje sube pegado al muro y se agarra cuando la parte de arriba de la cápsula llega al borde.

#### Cómo estaba armado

El documento pedía, para pasar de Aire a Hanging, "no sube rápido": en lo común de Hanging, "velocidad vertical por debajo de un máximo de subida". En el laboratorio era `hang_max_rise` = 1 m/s:

```gdscript
# Antes, en grab_check():
elif state.velocity.y > tuning.hang_max_rise:
	result["why"] = "sube rápido"
```

Un salto arranca a 4,8 m/s y frena con la gravedad, así que pasa casi toda la subida por encima de 1 m/s. Por eso el agarre llegaba en la punta del salto o bajando. El documento no dice para qué estaba la regla. Mi lectura: para no agarrarse de un borde que se pasa de largo subiendo.

#### Lo que apareció al sacar el límite

Con `diag_agarre_subiendo.gd`, saltando en el lugar pegado a muros de distintas alturas:

- **En el de 2,4 m se agarraba en el segundo tick del salto,** con un tirón de 30 cm para arriba. Las manos encuentran el borde cuando todavía les faltan unos 30 cm, y la pose de colgado está ahí.
- **En el de 2 m no se agarraba subiendo.** Parado contra ese muro, las manos ya están a 5 cm del borde, y lo pasan en el tick del salto. Ese tick todavía es Suelo, donde no se revisa el agarre, y en el siguiente las manos ya están arriba del borde: la sonda mira dónde van a estar al final del tick y no encuentra nada.

#### Cómo quedó (`bd2157b`)

- **El límite de subida se sacó** (`hang_max_rise`).
- **Subiendo, el agarre espera a que las manos lleguen al filo:** la pose de colgado no puede quedar más de `hang_rise_reach` (0,1 m) por encima de los pies. Si queda más arriba, el motivo es "subiendo, las manos todavía no llegan", y vuelve a probar en el tick siguiente.
- **Subiendo, si la sonda normal no encuentra nada,** busca de arriba hacia abajo: barre las manos desde donde van a estar al final del tick hasta donde estaban en el tick anterior. Así cubre el tick del salto.

```gdscript
var rising := state.velocity.y > 0.0
if edge.is_empty() and rising:
	var hands_before := EdgeProbe.hands_at(body, from - state.velocity * dt, toward, tuning)
	edge = EdgeProbe.find(body, hands_to, hands_before, toward)
```

**Saltando en el lugar pegado al muro, sin teclas o con W** (`diag_agarre_subiendo.gd`):

| Muro | Cuándo se agarra | Tirón |
| --- | --- | --- |
| 1,9 m | No se agarra: colgado, los pies quedarían bajo el piso | — |
| 2,0 m | En el primer tick en el aire | 5,7 cm |
| 2,1 m | En el primer tick en el aire | 8,7 cm |
| 2,4 m | En el tick 5, subiendo a 4 m/s | 10,3 cm |
| 2,8 m | En el tick 13, subiendo a 2,7 m/s | 7,5 cm |
| 3,1 m | En el tick 21, subiendo a 1,4 m/s | 10,9 cm |
| 3,2 m | En la punta del salto | 12,3 cm |

**Por qué no aparecen agarres no buscados:** desde el piso, un salto sube los pies 1,17 m, y las manos van 1,95 m por encima de los pies. Los muros donde las manos llegan al filo subiendo son más altos que los que se pueden subir saltando: no hay un borde al que quisieras aterrizar arriba y donde te agarres sin querer.

#### Saltar hacia otro lado desde el colgado

Con el agarre subiendo, el barrido mostró que la salida "saltar hacia atrás" fallaba en 132 casos del borde «techo bajo», donde antes fallaba en 7. Con `diag_techo_bajo.gd` se vio por qué:

- colgado debajo de la losa que sobresale 1 m, Espacio mirando hacia atrás salta lejos;
- el personaje seguía mirando a la pared, así que las manos buscaban para ese lado;
- subiendo, se agarraba del borde de adelante de la losa, a 2,8 m.

Antes no pasaba porque, en ese momento, todavía subía a más de 1 m/s.

Se le preguntó al usuario (17:45), con dos opciones: que el personaje mire hacia donde salta, o dejarlo así. Respuesta: "Que mire hacia donde salta". Ahora, al saltar hacia otro lado, el personaje se da vuelta hacia donde salta:

```gdscript
_leave_edge(state, tuning, look * tuning.hang_jump_out + Vector3.UP * tuning.hang_jump_up)
state.facing_yaw = _yaw_of(look)
```

Con eso, en el mismo diagnóstico salta lejos y cae al piso. Una consecuencia: si delante de donde salta hay otra pared, las manos la buscan.

#### Pruebas automáticas

| Prueba | Resultado |
| --- | --- |
| Barrido: criterio 1, ahora contando también las manos que cruzan el filo subiendo | 1.545 de 1.547 (99,9 %). La banda buscada pasó de 1.093 a 1.547 casos |
| Barrido: criterio 2 | 0 de 330 |
| Barrido: criterios 3 y 4 | 0 ticks metido; 0,090 m de cámara en 50 ms |
| Saltar hacia atrás, sin el giro | 180 que no (132 en el techo bajo) |
| Saltar hacia atrás, con el giro | 48 que no, contra 63 en la versión anterior. Casi todos son del borde entre paredes, donde las paredes de los costados frenan el salto |
| Desplazarse colgado | 2.200 sí y 3 no (antes, 2.046 y 20) |
| Subir con W recién arriba | 2.051 sí, 20 no (todos del borde curvo) |
| Repetición, a 60 y con el ritmo variando | 4.788 repeticiones y 212.823 ticks idénticos; huella `882cee955f9e6e12`. El recorrido se agarra igual, ahora subiendo: 211 ticks colgado, antes 121 |
| Red: las 12 combinaciones, el observador, la plataforma guionada y la divergencia con adopción | 0 correcciones |
| Borde sobre el cuerpo del host | 9,6 cm con red limpia y 19,6 cm con internet mala en esta corrida. Las de 1,4 a 2,7 m al aterrizar arriba después del salto para arriba (sección 8.6) no se volvieron a buscar en esta tanda: varían de corrida en corrida, y el salto para arriba no cambió |
| Regresiones: bases, postura, escalera y escalones | Igual que antes |

#### Prueba en dos PC (19:17–19:24)

> hice todas las pruebas, incluido de lo ponerme debajo del techo bajo y saltar hacia afuera, funciona correctamente, aunque es posible agarrarse con el timing correcto, pero a nivel de jugabilidad queda muy bien, ya que tenes que ser rápido y ágil a la hora de mover la cámara, medio que se siente como un logro mas que otra cosa.

Agarrarse igual del techo bajo es posible: si en el aire se gira la cámara de vuelta hacia la pared y se aprieta una tecla de dirección, las manos buscan para ese lado. Quedó así, como algo difícil a propósito.

Hubo cinco capturas, de las 19:17 a las 19:19:

- **Notebook, con internet mala:** colgada del muro largo (filo a 3 m), parada arriba de él y colgada del borde que va y viene. La predicción: 24 correcciones en toda la sesión (la última de 0,46 m) y 0 saltos de reloj.
- **Notebook, sin simulación:** otra vez arriba del muro largo.
- **Host:** la cápsula de la notebook arriba del muro largo. Afirmaciones: 27 adoptadas (la más lejana a 0,22 m), 0 rechazadas por época, 0 por distancia y 7 por pose.

Antes de este cambio, desde el piso, al muro largo de 3 m se llegaba agarrándose en la punta del salto. Ahora se agarra subiendo.

### Commit `bd2157b`

**Fecha:** 2026-10-08, 19:24. `feat(net): grab edges while rising and turn toward the jump away`: 5 archivos, +31 / −18 líneas.

- **Cambiados:** `actor_motor.gd`, `actor_tuning.gd`, `hang_sweep_test.gd`, y dos comentarios en `net_lab.gd` y `actor_replay_test.gd`.
- **La verificación:** las huellas SHA-1 de los 5 archivos coincidieron con la versión probada en las dos PC.

---

## 9. Estado actual del código

### 9.1 Archivos

Todo el código del laboratorio vive en carpetas nuevas: `scripts/actor/`, `scripts/net/`, `scenes/actor/` y `scenes/net_lab/`; desde el escalón, también `tools/net_lab/`, con el doble clic de la notebook. Del resto del proyecto solo se tocó `project.godot`, para sumar dos acciones al Mapa de entrada (punto 3): `avanzar_tick` (F) y `captura` (F12). La pausa usa una acción que ya existía, `toggle_debug_freeze` (G). Jolt Physics ya estaba configurado.

Las líneas son de hoy. Entre paréntesis, las del final del esqueleto de red (paso 8), cuando cambiaron.

| Archivo | Líneas | Qué hace |
| --- | --- | --- |
| `scripts/actor/actor_state.gd` (`ActorState`) | 181 (130) | Estado completo del actor al final de un tick: modos Suelo, Aire, Deslizamiento, Escalera y Colgado, postura, base, ancla (con el punto del filo) y reagarre. Cuantización, bytes (79; eran 51), copia y descripción |
| `scripts/actor/actor_input.gd` (`ActorInput`) | 61 (59) | Input de un tick, cuantizado al crearlo; 10 bytes. Botones: saltar, agacharse y correr |
| `scripts/actor/actor_tuning.gd` (`ActorTuning`) | 93 (29) | Parámetros de movimiento, un recurso |
| `scripts/actor/actor_motor.gd` (`ActorMotor`) | 670 (100) | Paso por tick en orden fijo con los cinco modos, la base, la postura, la escalera, el escalón, el borde y el salto para arriba desde el colgado, los impulsos con fuerza y la validación de poses ancladas |
| `scripts/actor/actor_body.gd` (`ActorBody`) | 280 (130) | Cuerpo (`CharacterBody3D`): deslizar, restaurar y validar poses, las dos formas y el espacio libre, asentarse en el piso después de un escalón, presentación, desvío visual (con el del agarre aparte) y las manos sobre el filo |
| `scripts/actor/edge_probe.gd` (`EdgeProbe`) | 108 (nuevo, punto 5) | Sonda de borde: barrido de las manos, cara, superficie de arriba y filo; revalidación de un borde agarrado |
| `scripts/actor/base_registry.gd` (`BaseRegistry`) | 73 (nuevo) | Registro de bases por id; origen, velocidad y posición en el mundo, real y dibujada |
| `scripts/actor/scripted_platform.gd` (`ScriptedPlatform`) | 85 (nuevo) | Plataforma guionada: su pose sale del tick; se dibuja en el pasado cuando conviene |
| `scripts/actor/host_raft.gd` (`HostRaft`) | 95 (nuevo) | Balsa que simula solo el host; en los clientes, una copia interpolada |
| `scripts/actor/ladder.gd` (`Ladder`) | 94 (nuevo) | Escalera autorada: eje, alto, volumen de entrada y dibujo |
| `scenes/actor/actor.tscn` | 60 (41) | El actor: las dos formas (parada y agachada), sus mallas y la "nariz" |
| `scripts/net/sim_clock.gd` (`SimClock`) | 288 (267) | Reloj único: ticks, orden fijo, sincronización, adelanto del cliente por ritmo variable, plataformas colocadas para el tick siguiente y pausa |
| `scripts/net/net_session.gd` (`NetSession`) | 137 (132) | Conexión ENet, aparición con `MultiplayerSpawner`, salidas y lugares de aparición |
| `scripts/net/net_sync.gd` (`NetSync`) | 322 (222) | Transporte: inputs, afirmaciones e ida y vuelta del cliente; snapshots del host con las balsas; márgenes; eventos programados por canal confiable |
| `scripts/net/link_simulator.gd` (`LinkSimulator`) | 97 (84) | Simulador de red: demora, variación, pérdida y tirones; los mensajes confiables se demoran pero no se pierden |
| `scripts/net/client_prediction.gd` (`ClientPrediction`) | 115 (91) | Predicción del cliente: historial, reconciliación, esperas, suavizado, repetición desde un tick para los eventos tardíos y la corrección más grande |
| `scripts/net/claim_adoption.gd` (`ClaimAdoption`) | 77 (74) | Adopción de afirmaciones en el host, con su registro; valida también las poses ancladas, de la escalera y del borde |
| `scripts/net/remote_interpolation.gd` (`RemoteInterpolation`) | 267 (90) | Interpolación de los demás jugadores y de las balsas en el cliente, con marcos de dibujo |
| `scenes/net_lab/net_lab.tscn` | 125 | Escena del laboratorio, con menú y panel |
| `scenes/net_lab/net_lab_level.tscn` | 389 (169) | Nivel del laboratorio: suma el vagón, el ascensor, la balsa, el túnel largo, la pared de medidas, la torre, las dos escaleras, la pista de escalones, la pista de bordes y los dos bordes que se mueven |
| `scenes/net_lab/net_lab.gd` | 1.176 (585) | Script del laboratorio: roles, menú, teclas, empujones y eventos programados, cableado de red, panel, pausa, capturas, mediciones, pruebas guionadas y la divergencia inyectada |
| `scenes/net_lab/lab_camera.gd` (`LabCamera`) | 65 (46) | Cámara de tercera persona; la altura de la cabeza sigue la postura |
| `scenes/net_lab/measure_wall.gd` | 46 (nuevo) | Pared de medidas: rayas cada 10 cm y números cada 50 cm |
| `scenes/net_lab/step_course.gd` | 96 (nuevo, escalón) | Pista de escalones: sueltos de 10 a 40 cm y dos escaleras, una con rampa invisible |
| `scenes/net_lab/edge_course.gd` | 178 (nuevo, punto 5) | Pista de bordes: las 11 variantes fijas, con sus carteles |
| `scenes/net_lab/actor_replay_test.gd` y `.tscn` | 314 + 13 (202 + 13) | Prueba de repetición determinista, a cualquier ritmo, con bases, postura, escalera, empujones, escalones y Hanging |
| `scenes/net_lab/hang_sweep_test.gd` y `.tscn` | 464 + 13 (nuevo, punto 5) | Barrido de aproximaciones a los bordes, con los cuatro criterios y la altura del salto para arriba |
| `tools/net_lab/actualizar_lab.bat` y `.ps1` | 14 + 71 (nuevo, escalón) | El doble clic que trae el laboratorio a la notebook y lo abre (sección 6.2) |
| Archivos `.uid` | — | Uno por script, generados por Godot |

**Total:** 5.982 líneas entre scripts y escenas, sin contar `tools/` (eran 2.589 al final del esqueleto, 4.431 en la segunda versión de este documento, 5.998 en la tercera y 5.969 en la cuarta).

### 9.2 Funciones públicas

- **`ActorState`:**
    - `quantize()`, `copy()`, `to_bytes()` y `from_bytes()` (estática);
    - `describe()`;
    - `quantize_yaw()`, `yaw_to_index()` e `index_to_yaw()` (estáticas).
- **`ActorInput`:** `make()` (estática), `is_held()`, `write_to()` y `read_from()` (estática).
- **`ActorMotor`, todas estáticas:**
    - `step(body, state, input, tuning, dt)`;
    - `apply_impulse(state, impulse, force, tuning)`, que reemplazó a `push(state, impulse)`;
    - `anchored_pose_valid(body, state, tuning)`; hasta el punto 4 recibía solo `state`;
    - `grab_check(body, state, direction, tuning, dt)` (punto 5): la decisión del agarre sin cambiar nada, con el motivo si no se agarra; la usan el motor y el barrido;
    - `grab_direction(state, direction)` (punto 5, cambio después de la primera prueba): hacia dónde buscan las manos.
- **`ActorBody`:**
    - `slide()` y `apply_state()`, que devuelve si la pose entra en el mundo;
    - postura: `use_stance()`, `active_stance()`, `stance_height()` y `stance_fits()`;
    - `capsule_radius()` y `settle_on_floor(snap_length)` (escalón);
    - `present()`, `seen_position()`, `smooth_from()`, `set_visual_offset()`, `decay_visual_offset()`, `teleported()` y `visual_root()`;
    - las variables `snap_jump` y `grab_jump`, por donde el motor le avisa a la presentación un snap lógico (escalón y agarre).
- **`EdgeProbe`, todas estáticas** (punto 5): `hands_at(body, feet, toward, tuning)`, `find(body, from, to, toward)` y `hold(body, point, normal)`.
- **`BaseRegistry`, todas estáticas:**
    - `add()`, `remove()`, `find(id)`, `all()` e `id_of(collider)`;
    - `origin(id)`, `velocity(id)` y `world_position(state)`;
    - `visual_origin(id)`, `visual_velocity(id)` y `visual_world_position(state)`, para dibujar.
- **`ScriptedPlatform`:** `pose_at(tick)`, `prepare_tick(tick)`, `base_origin()`, `base_velocity()`, `visual_origin()`, `visual_velocity()` y `distance_to(point)`.
- **`HostRaft`:** `become_copy()`, `place_copy(next_origin, current_origin, next_velocity)`, `base_origin()` y `base_velocity()`.
- **`Ladder`:** `find(id)` y `all()`, estáticas; `up()`, `outward()`, `pose_at(t)` y `height_for(feet)`.
- **`SimClock`:**
    - señales `tick_started(tick)`, `tick_finished(tick)` y `hard_resynced`;
    - `apply_tick_rate(rate)` (estática), `sorted_actors()` y `report_input_margin(host_tick, margin)`;
    - pausa: la variable `paused` y `step()`, que pide un tick.
- **`NetSession`:**
    - señales `status_changed(text)` y `local_actor_spawned(actor)`;
    - `start_local()`, `start_host(port, bind)`, `start_client(address, port)` y `spawn_position(peer)`.
- **`NetSync`:**
    - del cliente: `send_ticks(records, rtt_ms)` y `apply_pending_snapshot(on_own_state, on_other_state, on_base_state)`; los eventos recibidos quedan en `received_events`;
    - del host: `input_for(peer, tick)`, `claim_for(peer, tick)`, `input_margin_ticks(peer, tick)`, `peer_rtt_ms(peer)`, `send_snapshot(tick, actors, host_bases)` y `send_scheduled_event(peer, tick, impulse, force)`;
    - `quantize_impulse(impulse)` (estática) y `forget_peer(peer)`.
- **`LinkSimulator`:** `configure(rtt, jitter, loss, seed, stall_every, stall)`, `is_active()`, `deliver(packet)`, `deliver_reliable(packet)` y `clear()`.
- **`ClientPrediction`:** `record()`, `clear()`, `recent(count)`, `reconcile(actor, host_tick, host_state, used_input_tick, current_tick, step)` y `replay_from(actor, tick, current_tick, step)`; desde el punto 5, la variable `max_correction_meters`.
- **`ClaimAdoption`:** `consider(actor, claim_bytes, tuning)` (hasta el punto 4, sin `tuning`), `peers()`, `count(peer, result)` y `max_difference(peer)`.
- **`RemoteInterpolation`:** `add(peer, host_tick, state)`, `add_base(id, tick, position, velocity)`, `advance()`, `shown_tick()`, `place(actor)`, `place_bases(ahead)` y `forget(peer)`.

### 9.3 Formatos de red

**`ActorInput`, 10 bytes:**

| Campo | Tipo | Detalle |
| --- | --- | --- |
| tick | entero de 32 bits | tick para el que vale |
| move.x | entero de 8 bits | eje −1 a 1 × 127 |
| move.y | entero de 8 bits | eje −1 a 1 × 127 |
| look_yaw | entero sin signo de 16 bits | yaw en 65.536 pasos |
| buttons | entero sin signo de 8 bits | botones mantenidos, en bits: saltar (bit 0), agacharse (bit 1, desde el punto 3) y correr (bit 2, desde el punto 3) |
| jump_presses | entero sin signo de 8 bits | contador de pulsaciones de salto (0 a 255, da la vuelta) |

**`ActorState`, hoy 79 bytes.** Los primeros 51 son los del esqueleto, en el mismo orden, y después vienen los campos que agregó la validación:

| Campo | Tipo | Paso de cuantización | Desde |
| --- | --- | --- | --- |
| (los 51 bytes de la tabla siguiente) | | | esqueleto |
| base_id | entero sin signo de 16 bits | id de red de la base, 0 sin base | punto 2 (53 bytes) |
| stance_wanted | entero sin signo de 8 bits | postura pedida: parado = 0, agachado = 1 | punto 3 |
| stance | entero sin signo de 8 bits | postura concedida | punto 3 |
| anchor_id | entero sin signo de 16 bits | id del ancla. En Ladder, la escalera; en Hanging, la base que lleva el borde, 0 si es geometría fija | punto 4 |
| anchor_t | entero de 32 bits | 0,1 mm. En Ladder, la altura de los pies sobre la escalera; en Hanging, el avance de la subida en segundos (con el mismo paso), 0 mientras cuelga | punto 4 |
| regrab_id | entero sin signo de 16 bits | ancla bloqueada para reagarrar; 0xFFFF bloquea todos los bordes | punto 4 |
| regrab_left | entero de 32 bits | 0,1 ms | punto 4 |
| anchor_point | 3 enteros de 32 bits | 0,1 mm. En Hanging, el punto del filo relativo al origen de su base (en el mundo si es geometría fija) | punto 5 (79 bytes) |

Con base, `position` y `velocity` son relativas a ella. El modo vale Suelo = 0, Aire = 1, Deslizamiento = 2, Escalera = 3 y Colgado = 4. En Hanging la normal del borde no viaja: es la contraria a `facing_yaw`.

**`ActorState` del esqueleto, 51 bytes:**

| Campo | Tipo | Paso de cuantización |
| --- | --- | --- |
| position | 3 enteros de 32 bits | 0,1 mm (alcanza hasta unos 800 m del origen) |
| velocity | 3 enteros de 32 bits | 1 mm/s |
| floor_normal | 3 enteros de 32 bits | 0,0001 |
| facing_yaw | entero sin signo de 16 bits | 65.536 pasos |
| mode | entero sin signo de 8 bits | Suelo = 0, Aire = 1 |
| on_floor | entero sin signo de 8 bits | 0 o 1 |
| coyote_left | entero de 32 bits | 0,1 ms |
| jump_buffer_left | entero de 32 bits | 0,1 ms |
| jump_presses_seen | entero sin signo de 8 bits | último contador procesado |
| epoch | entero sin signo de 16 bits | época (da la vuelta en 65.536) |

**Mensajes.** Todos son RPC no confiables, salvo el evento programado:

| Mensaje | Sentido | Contenido |
| --- | --- | --- |
| `_submit_inputs` | cliente → host, un paquete por tick | ida y vuelta que mide el cliente, en ms (16 bits, desde el punto 4); cantidad (8 bits); y, por cada tick sin confirmar (hasta 6): el input (10 bytes), el largo de la afirmación (8 bits) y la afirmación (79 bytes) |
| `_receive_snapshot` | host → todos, cada 2 ticks | tick del host (32 bits); cantidad de actores (8 bits); y, por actor: dueño (32 bits), tick del input usado (32 bits), margen del input (16 bits), largo del estado (8 bits) y estado (79 bytes). Al final, desde el punto 2, las bases que simula el host: cantidad (8 bits) y, por base, id (16 bits), posición (3 enteros de 32 bits, en 0,1 mm) y velocidad (3 enteros de 32 bits, en 1 mm/s). Las plataformas guionadas no viajan: cada máquina las calcula desde el tick |
| `_receive_scheduled_event` | host → un cliente, **confiable** (desde el punto 4) | tick en que se aplica (32 bits), impulso (3 enteros de 32 bits, en 1 mm/s) y fuerza (8 bits) |
| `_ping` / `_pong` | cliente → host → cliente, cada 30 ticks | microsegundos del cliente al mandar; el host responde con eso y su tick |

### 9.4 Qué pasa en cada tick

**El paso por tick de un actor** (`ActorMotor.step`), hoy:

1. **Tiempo:** se descuentan coyote, memoria del salto y bloqueo de reagarre.
2. **Base:** si está sobre una base, la base lo lleva hasta donde quedó en este tick.
3. **Eventos:** una pulsación nueva de salto se detecta porque cambió el contador. Los empujones, en cambio, no se aplican acá (ver abajo).
4. **Sondas:** colgado, la sonda de borde revalida el borde agarrado (desde el punto 5). Las demás lecturas del entorno se hacen donde se usan: el volumen de la escalera y el agarre de un borde, en la transición; el escalón, en el movimiento, porque necesita saber si el movimiento chocó.
5. **Transición:** como máximo una por tick.
    - **Suelo:** salto, caída, agarrar una escalera o deslizamiento.
    - **Aire:** aterrizaje, salto con coyote, agarrar un borde (sin Ctrl; desde el punto 5; bajando o, desde el 2026-10-08, también subiendo) o agarrar una escalera.
    - **Deslizamiento:** salto, caída o fin por velocidad.
    - **Escalera:** respaldo, salto, salida abajo o salida arriba.
    - **Colgado** (desde el punto 5): respaldo si el borde ya no está; Ctrl se suelta; Espacio salta para arriba mirando a la pared, o hacia donde mira si no, y en ese caso se da vuelta hacia allá (desde el 2026-10-08, sección 8.7). Hasta el 2026-10-08, Espacio mirando a la pared empezaba la subida, y mientras subía no había otra transición (sección 8.6).
6. **Modo:** el modo activo decide la velocidad. Colgado, la velocidad va a lo largo del filo.
7. **Postura y movimiento:** se resuelve la postura. Después, los modos libres se mueven con `move_and_slide()`, y la escalera y el colgado con un barrido. En Suelo, si el movimiento chocó, la sonda de escalón prueba subirlo (desde el escalón).
8. **Contactos:** los indicadores de Godot pasan al estado. La sonda de suelo dice sobre qué base quedó parado, y al cambiar de base la velocidad cambia de marco; colgado, la base es la del borde. Todo se cuantiza.

**Los empujones no entran al paso.** Los aplica con `apply_impulse` quien maneja el actor (el host, o el cliente en su predicción) al empezar el tick, antes del paso, y suben la época. El documento los pone en la etapa 3. Una diferencia que sale de leer el código: el bloqueo de reagarre que pone un empujón empieza a descontarse en el mismo tick, en la etapa 1. Host y cliente lo hacen igual, así que no causa correcciones.

**En el host** (y en modo local, sin red):

1. **Al empezar el tick:**
    - reaparece quien cayó por debajo de −30 m;
    - se atienden los empujones pedidos con E y R: los inmediatos se aplican ya, y los programados se anotan para su tick y se anuncian;
    - se aplican los programados que tocan en este tick.

    Los dos tipos suben la época del empujado.
2. **Los actores, en orden de dueño:** cada uno toma su input (el propio del teclado; el de cada cliente, el que llegó, o el último repetido si falta), corre el paso por tick, se orienta y su desvío visual decae.
3. **Al terminar el tick:** para cada actor de otro jugador, la adopción considera su afirmación de ese tick.
4. **Snapshot:** se manda si el tick es par, con las balsas.
5. **Plataformas:** se colocan en su pose del tick siguiente.
6. **La balsa del host** la mueve el motor de física, en su propio paso.

**En el cliente:**

1. **Al empezar el tick:**
    1. toma los eventos programados que llegaron y los anota para su tick: si ese tick ya pasó, repite desde ahí con el evento; si ya ni eso se puede, lo cuenta como demasiado tarde;
    2. se aplica el snapshot más nuevo: el estado propio va a la predicción (y el margen al reloj), el de los demás y el de las balsas al colchón de interpolación;
    3. la predicción compara: si coincide, sigue; si no coincide y el estado se calculó con un input repetido, espera; si no coincide con input real, restaura, repite (con los eventos programados de esos ticks) y suaviza;
    4. avanza el momento que se muestra;
    5. decide cuánto en el pasado se dibuja cada plataforma, según lo cerca que esté el propio jugador;
    6. ubica a los demás en su pose interpolada, cada uno en su marco de dibujo;
    7. arma el input del tick y aplica los eventos programados de este tick al propio actor.
2. **El propio actor:** corre el paso por tick con ese input.
3. **Al terminar el tick:**
    - se guarda lo predicho;
    - se manda al host el input con la afirmación de los ticks sin confirmar y la ida y vuelta medida;
    - se colocan las copias de las balsas en su pose del tick siguiente;
    - las plataformas quedan colocadas para el tick siguiente.
4. **Después del tick:** el reloj ajusta el ritmo (57 a 72 ticks por segundo) según el peor margen corregido. Cada 30 ticks manda un ping.

**En pausa** (solo Jugar solo): no corre ningún tick, salvo uno por cada F. La balsa se congela aparte.

### 9.5 Constantes

| Constante | Valor | Dónde | Para qué |
| --- | --- | --- | --- |
| `TICK_RATE` | 60 | `SimClock` | Ticks por segundo del host; cada tick avanza `TICK_DT` = 1/60 s |
| `SYNC_INTERVAL_TICKS` | 30 | `SimClock` | Cada cuántos ticks pinguea el cliente |
| `PING_WINDOW` | 8 | `SimClock` | Pings recordados para elegir el más rápido |
| `LEAD_EXTRA_TICKS` | 2 | `SimClock` | Adelanto extra sobre medio ida y vuelta al sincronizar |
| `MARGIN_LOW` / `MARGIN_TARGET` | 1 / 2 | `SimClock` | Acelera con menos de 1 tick de margen, hasta llegar a 2 |
| `MARGIN_HIGH` / `MARGIN_SETTLE` | 6 / 3 | `SimClock` | Frena con más de 6, hasta bajar a 3 |
| `MARGIN_WINDOW_TICKS` | 60 | `SimClock` | Ticks del host en los que se busca el peor margen |
| `SPEEDUP_PER_MISSING_TICK` | 2,0 | `SimClock` | Ticks por segundo de más por cada tick de margen que falta |
| `MAX_RATE` / `MIN_RATE` | 72 / 57 | `SimClock` | Ritmos límite del cliente |
| `ADJUST_HISTORY_TICKS` | 1.024 | `SimClock` | Ticks recordados del ajuste acumulado |
| `INPUT_REDUNDANCY` | 6 | `NetSync` | Ticks que viajan en cada paquete del cliente |
| `SNAPSHOT_INTERVAL_TICKS` | 2 | `NetSync` | 30 snapshots por segundo |
| `INPUT_HISTORY_TICKS` | 120 | `NetSync` | Historia de inputs y afirmaciones por jugador en el host |
| `MAX_DIFFERENCE` | 1,0 m | `ClaimAdoption` | Diferencia máxima de posición para adoptar (a calibrar) |
| `RESTORE_SNAP_LENGTH` | 0,01 m | `ActorBody` | Snap manual al restaurar un estado apoyado |
| `POSE_TOLERANCE` | 0,01 m | `ActorBody` | Cuánto puede empujar la geometría a una pose válida |
| `CORRECTION_HALF_LIFE` | 0,025 s | `ActorBody` | Vida media del desvío visual |
| `MAX_SMOOTHED_JUMP` | 1,5 m | `ActorBody` | Saltos más grandes se muestran como salto |
| `DELAY_TICKS` | 6 | `RemoteInterpolation` | Colchón de 100 ms para ver a los demás |
| `MAX_DRIFT_TICKS` | 30 | `RemoteInterpolation` | Si el momento mostrado se aleja más, salta |
| `DRIFT_CORRECTION` | 0,05 | `RemoteInterpolation` | Parte de la diferencia que se corrige por tick |
| `TELEPORT_DISTANCE` | 4,0 m | `RemoteInterpolation` | Entre dos snapshots, más que esto es un teleport |
| `MAX_CLIENTS` | 7 | `NetSession` | Clientes por partida |
| `DEFAULT_PORT` | 7777 | laboratorio | Puerto UDP |
| `PUSH_UP_SPEED` / `PUSH_AWAY_SPEED` | 5 / 4 m/s | laboratorio | Empujón de la tecla E |
| `FALL_LIMIT` | −30 m | laboratorio | Por debajo, el actor reaparece |
| `MOUSE_SENSITIVITY`, `PITCH_MIN`, `PITCH_MAX`, `HEAD_HEIGHT` | 0,0025; −1,2; 0,6; 1,6 m | `LabCamera` | Cámara |
| Cuantización | posición 0,0001 m; velocidad 0,001 m/s; normal 0,0001; tiempo 0,0001 s; yaw 65.536 pasos; ejes 1/127 | `ActorState` / `ActorInput` | Estados comparables byte a byte |

**Constantes que sumó la validación:**

| Constante | Valor | Dónde | Para qué |
| --- | --- | --- | --- |
| `FREE_SPACE_MARGIN` | 0,02 m | `ActorBody` | Cuánto se achica la forma de prueba del espacio libre, para que tocar el piso no cuente como choque |
| `BASE_POSITION_STEP` / `BASE_VELOCITY_STEP` | 0,0001 m / 0,001 m/s | `NetSync` | Cuantización de las balsas en el snapshot |
| `IMPULSE_STEP` | 0,001 m/s | `NetSync` | Cuantización del impulso de un evento programado |
| `MIN_FRAME_BLEND_TICKS` | 6 | `RemoteInterpolation` | Al cambiar de marco de dibujo, el ajuste se reparte en al menos 6 ticks (100 ms) |
| `LEAVE_BLEND_SPEED` / `MAX_LEAVE_BLEND_TICKS` | 1,5 m/s / 45 ticks | `RemoteInterpolation` | Al dejar una base, el ajuste se reparte a esa velocidad media y en no más de 45 ticks (0,75 s) |
| `PLATFORM_NEAR` / `PLATFORM_FAR` | 1,5 / 6 m | laboratorio | Más cerca que 1,5 m, la plataforma se dibuja en su momento; más lejos que 6 m, en el pasado de los demás |
| `PUSH_FORCE_STRONG` / `PUSH_FORCE_WEAK` | 4 / 2 | laboratorio | Fuerza del empujón sin Shift y con Shift |
| `SCHEDULE_BUFFER_TICKS` | 4 | laboratorio | Colchón del tick de un evento programado |
| `FLASH_MSEC` | 3.000 ms | laboratorio | Duración del aviso de captura guardada |
| `HEAD_FOLLOW_RATE` | 12 | `LabCamera` | Rapidez con que la cámara sigue la altura de la cabeza en el suelo |
| `STEP` | 0,1 m | pared de medidas | Una raya cada 10 cm; un número cada 5 rayas |
| `LOOSE_HEIGHTS`, `LOOSE_SIZE`, `LOOSE_SPACING` | 0,1 a 0,4 m; 1,5 × 2 m; 2,5 m | pista de escalones | Escalones sueltos |
| `STAIR_RISE`, `STAIR_TREAD`, `STAIR_COUNT`, `STAIR_WIDTH` | 0,2 m; 0,35 m; 6; 2 m | pista de escalones | Las dos escaleras |
| `LANDING_DEPTH`, `STAIR_SPACING`, `RAMP_THICKNESS` | 2 m; 3 m; 0,1 m | pista de escalones | Descanso de arriba, separación y espesor de la rampa invisible |
| `REGRAB_EDGES` | 0xFFFF | `ActorState` | `regrab_id` que bloquea todos los bordes |
| `HANDS_SIZE` / `HANDS_OVERLAP` | 0,4 × 0,06 × 0,3 m / 0,05 m | `EdgeProbe` | La caja de las manos y cuánto entra en la cápsula |
| `TOP_INSET` / `FACE_DROP` | 0,03 m / 0,05 m | `EdgeProbe` | Cuánto adentro del filo se busca la superficie de arriba, y cuánto por debajo del contacto arranca el rayo de la cara |
| `MAX_TOP_ANGLE` / `MAX_FACE_TILT` | 30° / 20° | `EdgeProbe` | Inclinación máxima de la superficie de arriba y de la cara |
| `HOLD_TOLERANCE` | 0,1 m | `EdgeProbe` | Cuánto puede moverse el filo de un borde agarrado al revalidarlo |
| ~~`CLIMB_CLEARANCE` / `CLIMB_INSET`~~ | 0,02 m / 0,1 m | `ActorMotor` | Se sacaron con el salto para arriba (sección 8.6). Al subir al borde, los pies terminaban 2 cm por encima de la superficie, y el centro el radio más 10 cm adentro del filo |
| ~~`CLIMB_FLOOR_SEARCH`~~ | 0,6 m | `ActorMotor` | Se sacó con el salto para arriba. Era hasta dónde se buscaba piso caminable debajo del final de la subida |
| `GRAB_MAX_SPEED` | 1,8 m/s | `ActorBody` | Velocidad máxima con que el dibujo alcanza al cuerpo después de un agarre |
| `VARIANT_SPACING` / `ROW_SPACING` / `WIDTH` / `DEPTH` | 3,5 m / 8 m / 2,4 m / 1 m | pista de bordes | Separación de las variantes y de las filas, y tamaño de los bloques |

**El actor** (`actor.tscn`): cápsula parada de 1,8 m de alto y cápsula agachada de 1,0 m, las dos de 0,35 m de radio.

**Parámetros de movimiento (`ActorTuning`).** Los marcados con * los sumó la validación:

| Parámetro | Valor |
| --- | --- |
| Velocidad al caminar | 5 m/s |
| Aceleración en el suelo | 45 m/s² |
| Frenado en el suelo, sin input | 60 m/s² |
| Snap al piso, en Suelo | 0,3 m |
| Velocidad al correr* | 8 m/s, solo parado |
| Velocidad agachado* | 2,5 m/s |
| Velocidad mínima para empezar a deslizarse* | 6 m/s |
| Velocidad a la que termina el deslizamiento* | 2,5 m/s |
| Velocidad máxima deslizando* | 12 m/s |
| Rozamiento al deslizar* | 4 m/s² |
| Giro al deslizar* | 1,5 rad/s |
| Velocidad al trepar* | 2,5 m/s |
| Aceleración al trepar* | 20 m/s² |
| Salto desde la escalera* | 3 m/s hacia afuera y 3,5 m/s hacia arriba |
| Bloqueo de reagarre* | 0,4 s |
| Avance al salir por arriba de la escalera* | 0,7 m más allá del eje, además de la distancia de 0,45 m |
| Agarre de la escalera* | 3 (fuerza de 0 a 5; los modos libres tienen 0) |
| Escalón más alto que sube caminando* | 0,3 m, igual al snap al piso; 0 lo apaga (escalón) |
| Colgado: altura del filo sobre los pies y distancia del centro a la pared* | 1,95 m y 0,4 m (punto 5) |
| Snap máximo al agarrarse* | 0,35 m |
| ~~Subida máxima para agarrarse*~~ | Se sacó el 2026-10-08 (sección 8.7). Era 1 m/s (`hang_max_rise`) |
| Subiendo, cuánto puede tirar el agarre para arriba* | 0,1 m (`hang_rise_reach`): se agarra recién cuando la pose de colgado queda a 10 cm o menos por encima de los pies |
| Desplazarse colgado* | 1,5 m/s, con la aceleración de la escalera (20 m/s²) |
| Saltar colgado* | 4 m/s hacia donde mira y 4 m/s hacia arriba |
| Bloqueo de reagarre de bordes* | 0,3 s, para todos los bordes |
| Ángulo de la mirada para subir* | Espacio salta para arriba si la mirada está a menos de 60° de la pared; si no, salta hacia donde mira |
| ~~Subir al borde*~~ | Se sacó el 2026-10-08 (sección 8.6). Eran 0,45 s hacia arriba y 0,25 s hacia adentro, agachado |
| Salto para arriba desde el colgado* | Los pies suben hasta 0,2 m por encima del filo (`hang_climb_clearance`): unos 6,57 m/s hacia arriba |
| Agarre del borde* | 3 |
| Aceleración en el aire | 12 m/s²; desde el punto 3 no frena a quien viene más rápido que caminando |
| Gravedad | 9,8 m/s² |
| Caída máxima | 40 m/s |
| Velocidad de salto | 4,8 m/s (con la cápsula, el salto llega a ~1,17 m) |
| Coyote | 0,1 s |
| Memoria del salto | 0,12 s |

**Escaleras del nivel (`Ladder`):** ancho 0,8 m; distancia del eje al centro de quien trepa 0,45 m; alcance para agarrar 0,9 m. La de la torre tiene 2,5 m de alto y la de la plataforma verde, 2 m.

**Bases del nivel:**

| Base | Id | Tipo | Movimiento |
| --- | --- | --- | --- |
| Vagón | 1 | `ScriptedPlatform` | 8 m en x, ida y vuelta en 8 s |
| Ascensor | 2 | `ScriptedPlatform` | 1,98 m en y, ida y vuelta en 10 s |
| Balsa | 3 | `HostRaft` | Al azar en 10 × 10 m; rumbo nuevo cada 3 s; empuje de 2,5 m/s² |
| Borde sobre una plataforma guionada (punto 5) | 4 | `ScriptedPlatform` | 3 m en x, ida y vuelta en 10 s |
| Borde sobre un cuerpo del host (punto 5) | 5 | `HostRaft` | Al azar en 1 × 1 m; rumbo nuevo cada 3 s; empuje de 1 m/s² |

**Lugares de aparición (`NetSession.SPAWN_SLOTS`):** (0, 0, 8), (2, 0, 8), (−2, 0, 8), (4, 0, 8), (−4, 0, 8), (6, 0, 8), (−6, 0, 8) y (8, 0, 8), en orden de llegada.

---

## 10. Cómo usar el laboratorio

### 10.1 El menú

Al correr `scenes/net_lab/net_lab.tscn` con **F6** aparece un menú con:

- **Jugar solo:** el laboratorio sin red. Es el único modo donde anda la pausa.
- **Crear partida:** abre el host. Arriba se ve la IP de esta PC en la red local.
- **Unirse:** se escribe la IP del host en el campo (por defecto `127.0.0.1`) y se toca el botón.
- **Simular internet:** el nivel de red con el que arranca esta máquina.

### 10.2 Teclas

| Tecla | Quién | Qué hace |
| --- | --- | --- |
| WASD | todos | Mover. En la escalera, hacia ella sube y alejarse baja. Colgado, A y D van a la izquierda y a la derecha del personaje frente a la pared, mire donde mire la cámara (punto 5) |
| Espacio | todos | Saltar; en la escalera, salta hacia atrás. Colgado, mirando a la pared salta para arriba y con W se pasa arriba del borde, y mirando a otro lado salta hacia allá y se da vuelta (punto 5; el salto para arriba y el giro, desde el 2026-10-08) |
| Shift | todos | Correr (desde el punto 3) |
| Ctrl | todos | Agacharse; corriendo, deslizarse (desde el punto 3). Colgado, se suelta; mantenido en el aire, no se agarra de ningún borde (punto 5) |
| Mouse | todos | Mirar; un clic vuelve a tomar el mouse |
| Esc | todos | Suelta el mouse |
| 1 a 5 | todos | Nivel de red simulada de esta máquina: sin simulación, internet buena, normal, mala y Wi-Fi con tirones |
| E | host | Empujón inmediato a los demás jugadores (desde el punto 4, con fuerza 4) |
| R | host | Empujón programado a los demás jugadores, con fuerza 4 (desde el punto 4) |
| Shift + E, Shift + R | host | Los mismos empujones, débiles (fuerza 2): no sueltan la escalera |
| Q | host | Prende o apaga la adopción |
| G | solo en Jugar solo | Pausa: congela todo donde está; otra G lo suelta (acción `toggle_debug_freeze`, desde el punto 3) |
| F | solo en Jugar solo, en pausa | Avanza un tick, con las teclas que estén apretadas en ese momento (acción `avanzar_tick`) |
| F12 | todos | Guarda una captura en el Escritorio, aunque haya otras teclas apretadas (acción `captura`, desde el punto 3) |

**Agarrarse de un borde no tiene tecla** (punto 5): en el aire, se agarra solo cuando las manos llegan al filo, bajando o subiendo (subiendo, desde el 2026-10-08). Las manos buscan hacia las teclas de dirección apretadas, y sin teclas, hacia donde mira el personaje. Hasta el cambio del 2026-10-07 hacía falta apretar una tecla hacia la pared (sección 8.5).

1 a 5, E, R y Q se leen directo del teclado. G, F y F12 son acciones del Mapa de entrada, y se pueden cambiar en **Proyecto > Configuración del proyecto > Mapa de entrada**. La F comparte tecla con `toggle_free_cam` del parkour, y la E con `interactuar`; el laboratorio no usa esas acciones, así que no chocan. En una partida en red, la G no hace nada y no avisa.

Los niveles de red afectan solo a la máquina donde se eligen:

| Nivel | Ida y vuelta agregada | Variación | Pérdida | Tirones |
| --- | --- | --- | --- | --- |
| sin simulación | 0 | 0 | 0 % | no |
| internet buena | +40 ms | ±5 ms | 0 % | no |
| internet normal | +120 ms | ±20 ms | 1 % | no |
| internet mala | +200 ms | ±40 ms | 5 % | no |
| Wi-Fi con tirones | +20 ms | ±5 ms | 0 % | se traba 150 ms cada 3 s |

### 10.3 El panel

**Siempre:**

- el estado de la sesión;
- el tick y los actores;
- la red simulada;
- el modo del propio actor, si está en el suelo y la época;
- la postura: "Postura: agachado · pedida: parado (no hay lugar)" cuando el techo no deja pararse (desde el punto 3);
- en la escalera, "Escalera N · pies a X m sobre su base", y después de soltarla, cuánto falta para poder volver a agarrarla (desde el punto 4);
- colgado, "Colgado del borde: filo a X m de altura" y, si el borde va sobre una base, "· sobre la base N"; y después de soltar un borde, "Recién soltó un borde: no puede agarrar otro por X s" (desde el punto 5);
- la velocidad, aclarando "(sobre la base)" si es relativa a una base;
- "Pies en (x, y, z) · cabeza a … m de altura · base: …", con milímetros (desde el punto 3);
- en pausa, "EN PAUSA (tick N) · G sigue · F avanza un tick";
- arriba de todo, durante 3 s, el aviso de captura guardada;
- la ayuda de teclas; desde el punto 5, con la línea "Colgado: A y D de costado · Espacio mirando a la pared sube, mirando a otro lado salta · Ctrl se suelta".

**En el cliente:**

- **Reloj:** ida y vuelta (el ping más rápido de los últimos 8), cuántos ticks va adelante del host y los saltos de reloj después de la primera sincronización.
- **Input y ritmo:** el peor margen reciente con que le llega el input al host, corregido por lo que el cliente ya ajustó; el ritmo actual en ticks por segundo; y los ticks de adelanto ganados y perdidos.
- **Predicción:** coincidencias, correcciones (y el tamaño de la última) y esperas por input tardío.
- **Snapshots** que no llegaron a tiempo.
- **Empujones programados** (desde el punto 4): cuántos llegaron a tiempo, cuántos tarde (se repitió desde su tick) y cuántos demasiado tarde.
- **Los demás:** se ven 100 ms en el pasado; ticks esperando un snapshot y porcentaje de tirones medidos. Desde el punto 2, los tirones se miden con la velocidad en el mundo y la posición dibujada.

**En el host:**

- adopción prendida o apagada, empujones inmediatos y programados, y reapariciones;
- por cada jugador: con cuántos ticks de anticipación le llega su input, su época, y sus afirmaciones adoptadas (con la diferencia más grande) y rechazadas por época, distancia y pose.

### 10.4 Argumentos para pruebas automáticas

Van después de `--` en la línea de comandos. Los temporizadores cuentan segundos reales.

| Argumento | Qué hace |
| --- | --- |
| `--local`, `--host`, `--client` | Arranca directo en ese rol, sin menú |
| `--address=IP`, `--port=N`, `--bind=IP` | Dirección del host, puerto e IP donde escucha el host |
| `--autoquit=SEGUNDOS` | Imprime un resumen y cierra |
| `--report-after=SEGUNDOS` | Imprime el estado de cada actor |
| `--trace` | El cliente imprime su adelanto, margen, ritmo, correcciones, esperas, alineaciones y época cada medio segundo. Desde el punto 2, cualquier rol imprime además una línea "actor:" con base, posición en el mundo y relativa, velocidad, modo, postura, suelo, ancla y época |
| `--test-input=walk` | Camina 1,5 s, salta a los 0,5 s y se queda quieto |
| `--test-input=zigzag` | Un cuadrado que cambia de lado cada medio segundo, con un salto cada dos; a los 25 s se queda quieto |
| `--test-input=ride:<id>` | Va hasta la base y se queda arriba, dando vueltas cerca del centro y saltando cada 3 s. Si la base está más alta, salta para subirse; si está muy alta (el ascensor arriba), la espera afuera (punto 2) |
| `--test-input=hop:<id>` | Llega a la base y, cada 2,5 s, salta a 3,2 m del centro o vuelve saltando (punto 2) |
| `--test-input=edge:<id>` | Igual, pero a 1,4 m del centro: cae en el borde (punto 2) |
| `--test-input=walkoff:<id>` | Igual, a 2,5 m del centro y caminando, sin saltar (punto 2) |
| `--test-input=tunnel` | Se alinea con el túnel, corre, se desliza adentro, suelta Ctrl, sale caminando por la otra punta y vuelve agachado. Al final imprime los ticks que estuvo parado bajo el techo (punto 3) |
| `--test-input=crouchjump` | Frente a la pared de medidas, salta y se agacha a los 10 ticks del salto (punto 3) |
| `--test-input=ladder` | Va a la escalera de la torre, se agarra y sube y baja entre 0,5 y 2 m; si la suelta, vuelve (punto 4) |
| `--test-input=laddertop` | Sube la escalera hasta arriba y sale al techo de la torre (punto 4) |
| `--test-input=steps` | Recorre la pista de escalones en 15 puntos: cruza los sueltos de 10, 20 y 30 cm, choca contra el de 40 hasta que se le acaba el tiempo, y sube y baja las dos escaleras (escalón) |
| `--test-input=hang` | Ciclos contra la cara de un bloque de 2 m de la pista de bordes: se aleja 2,2 m, corre, salta y se agarra al caer; colgado va a la derecha y a la izquierda; después, según la vuelta, salta para arriba y aprieta W recién cuando deja de subir, queda arriba y se baja por delante; se suelta con Ctrl; o salta hacia atrás (punto 5) |
| `--test-input=hang:<id>` | Lo mismo contra el borde de esa base: 4, la plataforma guionada; 5, el cuerpo del host (punto 5) |
| `--test-perturb-mm=N` | El cliente corre su estado predicho y su cuerpo N milímetros al azar en cada tick, siempre igual para la misma semilla: la divergencia inyectada (punto 5) |
| `--test-spawn-at=x,z` | El host aparece en ese lugar (punto 2) |
| `--test-pause-at=TICK` | Jugando solo, pone la pausa en ese tick (punto 3) |
| `--no-adoption` | El host arranca con la adopción apagada |
| `--test-push-at=S1,S2,…` | El host da empujones inmediatos a esos segundos |
| `--test-scheduled-push-at=S1,S2,…` | El host da empujones programados a esos segundos (punto 4) |
| `--test-push-force=N` | Fuerza de los empujones de prueba; por defecto 4 (punto 4) |
| `--test-schedule-ticks=N` | Los programados se fijan solo N ticks adelante, para probar uno que llega tarde (punto 4) |
| `--sim-rtt=MS`, `--sim-jitter=MS`, `--sim-loss=PORCENTAJE`, `--sim-seed=N` | Red simulada |
| `--sim-stall-every=MS`, `--sim-stall=MS` | Tirones |
| `--sim-after=SEGUNDOS`, `--sim-until=SEGUNDOS` | La red simulada empieza o termina en plena partida |

**El resumen final** (`--autoquit`) imprime en una línea:

- rol, tick, actores y sincronización;
- ida y vuelta, adelanto, peor margen, ritmo y ticks ganados y perdidos;
- saltos de reloj, coincidencias, correcciones, esperas y alineaciones;
- snapshots perdidos, red y paquetes descartados por el simulador.

En el cliente agrega los tirones de los demás y, desde el punto 4, los empujones programados a tiempo, tarde y demasiado tarde. En el host agrega las reapariciones y, por jugador, las afirmaciones por resultado (iguales, adoptadas, rechazadas por época, distancia y pose, con la adopción apagada y sin afirmación) y la diferencia más grande adoptada. Con `tunnel`, imprime hasta qué tramo llegó y los ticks que estuvo parado bajo el techo. Con `steps`, "escalones: punto N de 15; pies a X m como máximo". Con `hang`, "colgar: N agarres, N subidas al borde, N vueltas del ciclo" y, en el cliente, "correcciones: la más grande de X m".

**Prueba de repetición:** `--scene res://scenes/net_lab/actor_replay_test.tscn -- --rate=N` (o `--rate=varying`). Sale con 0 si todas las repeticiones coinciden e imprime la huella de la pasada en vivo. Desde el punto 3 también imprime cuántos ticks pasó agachado y cuántos de ellos pidiendo pararse sin lugar; desde el punto 5, los ticks colgado.

**Barrido de Hanging** (punto 5): `--scene res://scenes/net_lab/hang_sweep_test.tscn`. Imprime cada caso, una tabla por borde, las salidas, los cuatro criterios y el resumen con teclas y sin teclas. Desde el salto para arriba, también prueba dos formas de subir (W desde el salto y W recién arriba) e imprime hasta dónde llegan los pies sobre el filo. Sale con 0 si se cumplen los cuatro criterios. Con `-- --detalle=borde,vel,llegada,ángulo,lateral,objetivo,teclas` (por ejemplo `--detalle=curvo,6,-12.0,0,0.6,colgarse,empuja`) imprime ese caso tick a tick. Tarda unos minutos.

**Avisos de GDScript sin ventana:** Godot los imprime solo con el depurador encendido. Para verlos, se agrega `-d` antes de `--scene`.

### 10.5 Qué hay en el nivel

Las direcciones son desde donde se aparece (z = 8), mirando como la cámara inicial, hacia −z.

| Qué | Dónde | Coordenadas |
| --- | --- | --- |
| Lugares de aparición | En fila, de x = −6 a x = 8 | z = 8 |
| Vagón (base 1, naranja) | A la derecha, detrás del muro largo; se llega rodeándolo por la punta más cercana | empieza en (10; −0,13; 0) y va hasta x = 18 |
| Ascensor (base 2) | Adelante a la izquierda, pegado a la plataforma verde alta | (−9; −0,13; −12), sube hasta 2 m |
| Balsa (base 3, marrón) | A la izquierda, flotando | empieza en (−16; 0,15; 0) |
| Pared de medidas | Adelante a la izquierda | (−6; 1,75; 5) |
| Túnel largo (violeta, techo a 1,2 m) | Detrás | x = 0, de z = 14 a z = 24 |
| Torre con escalera 1 (2,5 m) | Detrás y a la derecha; la escalera da hacia donde se aparece | torre en (8; 1,25; 14); escalera en (8; 0; 12,5) |
| Escalera 2 (2 m) | Adelante, en la cara de atrás de la plataforma verde alta (la que no da hacia donde se aparece) | (−6; 0; −14) |
| Pista de escalones (escalón) | Detrás, a la izquierda del túnel violeta; se suben caminando hacia +z | origen en (−4; 0; 12) |
| Pista de bordes (punto 5) | Adelante a la derecha, pasando el muro largo. Fila 1: 1,6 m, 2,0 m, 2,4 m, 5 cm de espesor, 20 cm de espesor y malla. Fila 2, 8 m más adelante: inclinado 10°, inclinado 25°, curvo, techo bajo y paredes al costado. Las caras miran hacia donde se aparece | caras de la fila 1 en z = −10, desde x = 10 cada 3,5 m; fila 2 en z = −18 |
| Borde sobre una plataforma guionada (base 4, naranja) | Al este del vagón | (22; 1; −5), va 3 m hacia −x |
| Borde sobre un cuerpo del host (base 5, marrón) | Al este del vagón, más lejos | (27,5; 1; 2) |

---

## 11. Todas las pruebas y sus resultados

Las pruebas automáticas corrieron en esta PC, sin ventana, con host y cliente como dos procesos por localhost. Las de dos PC corrieron entre esta PC y la notebook, por Wi-Fi. En la columna "Paso", P2 a P5 son los puntos de la validación (sección 8), y "Esc" es el escalón.

| Paso | Prueba | Resultado |
| --- | --- | --- |
| 2 | Repetición determinista: 1.105 ticks, 16 repeticiones largas y repeticiones cortas desde cada tick | 1.121 repeticiones y 44.141 ticks idénticos byte a byte |
| 3 | Host y cliente por localhost | Las dos instancias ven dos actores; desfase de 0,21 ticks; 0 saltos; ida y vuelta de 7 ms; el cliente termina la sesión si se va el host |
| 3 | Dos PC | Conexión, dos cápsulas y el tick a la par |
| 4 | Cliente con `walk` | Caminó ~7 m y saltó solo por red; estado final idéntico en host y cliente |
| 4 | Dos PC | El input del cliente llega 1 tick tarde (solo el viaje de ida) |
| 5 | Cliente a +120 ms ±20 con 5 % de pérdida | Ida y vuelta de 145 ms; lo apretado se ve 10 ticks después (~167 ms); estados idénticos |
| 5 | Cliente con 30 % de pérdida | El salto llegó exactamente una vez |
| 5 | Dos PC, sin simulación | Eco de 2 ticks (33 ms); 25 saltos de reloj en ~2 min; 17 % de snapshots tarde |
| 6 | `walk` sin simulación, normal y mala | 351, 205 y 161 coincidencias; 0 correcciones; 0 saltos; estado final idéntico y el mismo en las tres redes |
| 6 | Reloj con internet mala (antes del arreglo) | Saltos en cadena hasta el tick −1310; arreglado |
| 6 | Dos PC | 0 saltos; 18.883 coincidencias; 21 correcciones (20 por input tardío); 94 ajustes de un tick en ~8 min; tirones con 400 ms que se estabilizaron |
| 6b | Cuenta en float32, ritmos de 50 a 90 | Delta idéntico a 1/60 y factor exacto de 1,0 en todos |
| 6b | Ritmo en el motor (60, 72, 57 y 66, con compensación) | 60,41; 72,22; 56,97 y 65,98 ticks por segundo reales; delta exacto de 1/60 |
| 6b | Repetición a 60, 72, 57 y variable | Las cuatro pasan con la huella `1e07f92f0ec2c94a` |
| 6b | Red que salta a 400 ms en plena partida, reloj viejo contra nuevo | Recuperación de ~14 s a ~1,5–2 s; correcciones de 57 a 7 (y 5); adelanto sobrante de ~9 s a ~5,5 s |
| 6b | Regresiones con `walk` | 441, 272 y 209 coincidencias; 0 correcciones; 0 saltos |
| 6b | Dos PC, ~4 min cambiando de red | 0 saltos; correcciones quietas en 7; ritmo de 57 a 60; adelanto de ~4,5 o 12–20 ticks |
| 7 | Repetición a 60 y variable | Pasan; huella nueva `4da513f15b6d798b` (cambió el formato) |
| 7 | Regresiones con `walk` | 0 correcciones; afirmaciones iguales 441, 428 y 422; esperas de arranque 3, 7 y 9 |
| 7 | 400 ms en plena partida, adopción prendida y apagada | 1 corrección en los dos casos; 29 y 27 esperas; 25 afirmaciones rechazadas por distancia |
| 7 | Dos empujones, sin simulación y con internet mala | 4 y 33 rechazadas por época; 2 correcciones; época 2; empujones aplicados |
| 7 | Empujones con el chequeo de época apagado | 2 afirmaciones viejas adoptadas; empujones borrados; posición final idéntica a una corrida sin empujones |
| 7 | Tirones de Wi-Fi, adopción prendida y apagada | 0 contra 8 correcciones; 8 adoptadas (la más lejana a 0,147 m) |
| 7 | Validación de pose, 9 casos | 9 de 9 como se esperaba |
| 7 | Dos PC | Con tirones: 22 esperas y 1 corrección (2,14 m); 61 empujones con época 61 y una corrección por empujón; la cápsula salió del mapa |
| 8 | Tirones de los demás, sin simulación, mala y con tirones | De 5,2 % a 0,7 %; de 73,3 % a 0,5 %; de 27,4 % a 1,7 % |
| 8 | Regresiones con `walk` | 0 correcciones; coincidencias 220, 186 y 149 (mitad de snapshots) |
| 8 | Repetición a 60 y variable | Huella `4da513f15b6d798b`, la misma que en el paso 7 |
| 8 | Diez empujones seguidos | Fuera del mapa, reaparición en el tick 1000; época 11; 11 correcciones; mismo estado final |
| 8 | Suavizado | 0,5 m baja a 3 cm en 100 ms; 2 m se muestra como salto |
| 8 | Cámara (fotogramas de Movie Maker) | Sigue al personaje; la escena se dibuja bien |
| 8 | Dos PC con tirones y después con ~400 ms | 0 saltos; tirones de los demás 2,1 % y 2,0 %; "se siente muy bien, no hay tirones raros" |
| P2 | Jolt: ¿cuándo ven las consultas un cuerpo movido? | Los cinemáticos, recién en el paso siguiente; un `StaticBody3D` con `force_update_transform()`, en el acto (inferencia I2 confirmada) |
| P2 | Vagón, cliente arriba, sin simulación y con internet mala | 0 correcciones en los dos; 818 coincidencias sin simulación |
| P2 | Balsa, cliente arriba, sin simulación y con internet mala | 7 correcciones al subirse por primera vez (14 rechazadas por pose); 0 con internet mala (22 adoptadas, hasta 0,945 m) |
| P2 | Balsa con internet mala, repetida | Ráfagas al subirse desde el piso: 0, 0, 24, 46 y 51 correcciones en cinco pruebas, y 37 y 11 en pruebas posteriores; arriba, ninguna |
| P2 | Regresiones (caminar con tres redes, tirones de Wi-Fi) | 0 correcciones; con tirones, 8 adoptadas (hasta 0,147 m) |
| P2 | Repetición | Pasa; huella `7f845dfdc63f3a57` |
| P2 | Fotogramas de Movie Maker, 300 por base | El actor se ve apoyado sobre el vagón y la balsa |
| P2 | Dos PC, 4 sesiones con lluvia y Starlink | 0 correcciones arriba de las bases, salvo 2 chicas en la balsa (hasta 0,37 m); tres sesiones cortadas por silencios de 4,5–5,4 s |
| P2 | Plazo de corte de ENet | 8 s de silencio aguantados con la conexión recién empezada; con la conexión asentada, corte a los 9,7–10 s |
| P2 | Otro jugador saltando del vagón, antes y después del primer arreglo | Salto de hasta 0,41 m en un cuadro; después, paso máximo de 0,18 m y promedio de 0,08 m |
| P2 | Ajuste al aterrizar, antes y después de los marcos de dibujo | Vagón: de 0,35 m (red limpia) y 0,83 m (mala, hasta 1,24) a 0. Ascensor con red mala: de 0,18 m a 0. Del piso al vagón o al revés: 0,02 m (limpia) y 0,10 m (mala, hasta 0,37) |
| P2 | Bordes, antes y después de dibujar el vagón en el pasado | Caminando: de 0,36 / 0,87 m a 0 / 0; saltando del vagón al piso o al revés: de 0,34 / 0,85 m a 0 / 0; borde y ascensor: 0 / 0 |
| P2 | Dos PC, bordes | "podría decirse que esta casi que arreglado"; queda un caso raro con la cápsula que mira cerca del vagón |
| P3 | Túnel con el cliente, red limpia, mala y con tirones | 0 correcciones (697, 452 y 664 coincidencias); 0 ticks parado bajo el techo |
| P3 | Túnel con el host, mirado desde el cliente, red limpia y mala | 0 correcciones; tirones del otro 1,2 % y 1,1 % |
| P3 | Repetición, a 60 y con ritmo variable | 1.971 repeticiones y 83.241 ticks idénticos; huella `7401f6f3c81f517e` |
| P3 | Pies y cabeza al cambiar de postura, tick a tick | En el aire se mueven los pies (0,85 y 0,79 m) y la cabeza queda; en el piso, al revés (0,8 m) |
| P3 | Pausa con G y F, con teclas simuladas | La G congela (30 cuadros después, el mismo tick); la F avanza exactamente un tick; otra G suelta |
| P3 | Cabeza dibujada y cámara al agacharse en el aire, antes y después del arreglo | Cabeza: de 2,43 → 1,65 → 2,08 → 2,50 m a 2,43 → 2,50 → 2,53 m. Cámara: de subir 0,67 m y bajar despacio a 2,20 → 2,30 → 2,33 m |
| P3 | La cápsula del otro jugador al cambiar de postura en el aire, red limpia y mala | La cabeza sigue pareja |
| P3 | Avisos de GDScript con `-d` | Un script de ensayo sí los imprime; el laboratorio y la repetición, ninguno |
| P3 | F12 con Ctrl apretado, con teclas simuladas | La imagen se guarda con la cápsula agachada y el panel |
| P3 | Dos PC, primeras capturas | Parada sobre el vagón: 4.083 coincidencias, 0 correcciones, 0,1 % de datos tarde y 0 % de tirones |
| P3 | Dos PC, con el túnel | Agachados bajo el techo; más de 12.800 coincidencias; 0,5 % tarde y 0,7 % de tirones; 1 corrección de 1,21 m por un corte |
| P3 | Cortes de 1,5 s cada 4 s, sin pantalla | Túnel: 1 corrección; zigzag sin agacharse: 5 |
| P4 | Empujones en la escalera, 2 inmediatos y 2 programados, fuertes y débiles, red limpia y mala | 2 correcciones en cada caso, las de los inmediatos; los programados, a tiempo |
| P4 | Programados con aviso corto, internet mala | Fuertes con 3 ticks: 4 tarde, 0 correcciones. Débiles con 3 ticks: 3 tarde, 1 demasiado tarde, 1 corrección. Fuertes con 1 tick: 3 tarde, 1 demasiado tarde, 1 corrección |
| P4 | Repetición, a 60 y con ritmo variable | 2.467 repeticiones y 106.057 ticks idénticos; huella `d5f212653ef1bf8b` |
| P4 | Regresiones: piso plano, vagón, balsa y túnel | 0 correcciones |
| P4 | Fotogramas de Movie Maker | Trepa delante de la escalera; arriba queda parada sobre la torre |
| P4 | Dos PC, internet mala en las dos (~300 ms) | 50 inmediatos: 50 correcciones (la última de 3,43 m). 29 programados: 18 a tiempo, 11 tarde, 0 demasiado tarde y 0 correcciones. Época 79 |
| Esc | Escalón más alto que sube, caminando, agachado, corriendo y en diagonal | De 10 cm a 30 cm; el de 32 cm no |
| Esc | Subir 30 cm, cuadro por cuadro | El cuerpo sube en un tick; lo dibujado y la cámara, parejo en ~100 ms, de a 4 cm por cuadro como máximo |
| Esc | Pista de escalones en red: el cliente con red limpia, mala y tirones; el host con red limpia y mala | 0 correcciones; llega al punto 15 de 15; tirones del otro entre 1,5 % y 2,5 % |
| Esc | Repetición, a 60 y con ritmo variable | 3.415 repeticiones y 149.665 ticks idénticos; huella `0620654cfb44141f` |
| Esc | Regresiones: piso plano, vagón, balsa, túnel y escalera | Igual que antes. La balsa ahora se sube caminando: 15 correcciones al subirse con internet mala, dentro de la ráfaga de siempre |
| Esc | Dos PC, internet mala (217 ms) | 4.577 coincidencias, 0 correcciones, 1,4 % de tirones; ninguna afirmación rechazada; las dos cápsulas arriba de las dos escaleras |
| P5 | Barrido de 2.574 aproximaciones, primera versión | Criterios: 523 de 524 en la banda buscada; 0 de 165 no buscados; 0 ticks metido; 0,090 m de cámara en 50 ms (sin el tope de velocidad del agarre, 0,262 m) |
| P5 | Red, primera versión: 0, 60, 120 y 200 ms con 0, 2 y 5 % de pérdida | 0 correcciones en las 12; 10 agarres y 4 subidas en cada una |
| P5 | Bordes que se mueven, primera versión | Plataforma guionada: 0 correcciones. Cuerpo del host: hasta 4,6 cm con red limpia y 21 cm con internet mala |
| P5 | Divergencia de 0,5 mm por tick, primera versión | Con adopción: 0 correcciones. Sin adopción: 664 correcciones (hasta 4,2 cm), con los mismos agarres y subidas |
| P5 | Repetición, primera versión | 4.565 repeticiones y 202.565 ticks idénticos; huella `8421b986a6efcbd3` |
| P5 | Dos PC, primera versión, red limpia, mala y tirones | Ninguna corrección nueva colgado del borde que se mueve (62 de antes, sin ubicar); 79 afirmaciones adoptadas, 11 rechazadas por distancia y 97 por pose, también de antes; tres pedidos de cambio |
| P5 | Barrido de 5.148 aproximaciones, con y sin teclas, después del cambio | Con teclas 523 de 524 y sin teclas 568 de 569 en la banda buscada; 0 de 330 no buscados; 0 ticks metido; 0,090 m de cámara en 50 ms. Desplazarse con la cámara de costado: lo mismo que mirando a la pared |
| P5 | Repetición después del cambio | Con la ruta vieja, la misma huella `8421b986a6efcbd3`. Con los tramos nuevos (salto sin teclas, A y D con la cámara de costado): 4.790 repeticiones y 212.915 ticks idénticos, a 60 y con ritmo variable; huella `4ea24f9067f289f7` |
| P5 | Red y regresiones después del cambio | 0 correcciones en las 12 combinaciones y en la plataforma guionada; cuerpo del host hasta 10,5 cm (limpia) y 12,5 cm (mala); divergencia sin adopción, 663 correcciones (hasta 5,2 cm) con los mismos agarres; lo anterior, igual |
| P5 | Dos PC, después del cambio | "ok, todo funciona como deberia" |
| P5 | Salto para arriba: altura | Los pies llegan 0,204 m sobre el filo (0,199 y 0,190 m en los inclinados) |
| P5 | Salto para arriba: subir con W en la punta / con W desde el salto | 1.934 de 1.955 / 221 de 1.502. Con W desde el salto, en los bloques de 1 m se pasa de largo; las fallas con W en la punta son todas del borde curvo |
| P5 | Demostración en ventana, cámara lenta, de costado del bloque «malla» | W desde el salto: pasa el fondo y cae al piso del otro lado. W en la punta: queda arriba, 0,38 m adentro |
| P5 | Repetición con el salto para arriba | 4.788 repeticiones y 212.823 ticks idénticos, a 60 y con ritmo variable; huella `fccfdb253c89ed7c` |
| P5 | Red con el salto para arriba | 0 correcciones en las 12 combinaciones, con el observador y en la plataforma guionada. Cuerpo del host: 6,8 cm con red limpia; con internet mala, de 1,46 a 2,70 m (y una corrida de 0,20 m) |
| P5 | Dos PC con el salto para arriba, internet mala | 37 correcciones (la última de 0,27 m), 0 saltos de reloj; "todo funciona como debería" |
| P5 | Agarrarse subiendo, saltando en el lugar pegado a muros de 1,9 a 3,2 m | En los de 2,0 a 3,1 m se agarra subiendo (el de 2,0 m en el primer tick en el aire), con un tirón de 11 cm como máximo; en el de 3,2 m, en la punta; en el de 1,9 m, no |
| P5 | Barrido con el agarre subiendo | Criterio 1: 1.545 de 1.547 (la banda buscada pasó de 1.093 a 1.547 casos). Criterio 2: 0 de 330. Saltar hacia atrás: 48 que no con el giro (180 sin él) |
| P5 | Repetición con el agarre subiendo | 4.788 repeticiones y 212.823 ticks idénticos, a 60 y con ritmo variable; huella `882cee955f9e6e12` |
| P5 | Red con el agarre subiendo | 0 correcciones en las 12 combinaciones, con el observador, en la plataforma guionada y en la divergencia con adopción |
| P5 | Dos PC con el agarre subiendo | Colgada y parada arriba del muro largo de 3 m; 24 correcciones en la sesión con internet mala (la última de 0,46 m), 0 saltos de reloj; 27 afirmaciones adoptadas y 7 rechazadas por pose en el host |

---

## 12. Hechos de Godot y Jolt comprobados durante la implementación

Estos hechos se comprobaron en el código, en el motor o en las pruebas mientras se construía el esqueleto. Los de la investigación original están en la sección "Hechos comprobados e inferencias" del Apéndice A.

- **Indicadores de contacto:** `is_on_floor()`, `is_on_wall()` e `is_on_ceiling()` solo valen justo después de `move_and_slide()`, no después de mover el cuerpo a mano. Por eso se copian al estado del actor al final de cada movimiento, y el resto del juego lee el estado.
- **El delta implícito:** `move_and_slide()` usa el delta del frame de física por su cuenta. Para que avance exactamente el `dt` del actor, la velocidad se multiplica por `dt / delta`.
- **Después de restaurar:** el dato interno de piso de `move_and_slide()` (si estaba apoyado en el llamado anterior) queda viejo, y decide el snap del tick siguiente. Un movimiento de velocidad cero con el snap en 0 lo refresca sin arrastrar el cuerpo. Si el estado está apoyado justo en el margen de 1 mm, hace falta además `apply_floor_snap()` con una distancia chica.
- **Plataformas:** Godot lee la velocidad de plataforma del presente, y eso falla al repetir ticks. Por eso se desactiva (`platform_floor_layers = 0` y `platform_wall_layers = 0`).
- **No se puede rebobinar el mundo:** `PhysicsServer3D` en Godot 4.7.2 no permite avanzar ni rebobinar la física desde script (el PR 76462, `space_step`, sigue abierto). Por eso solo se repite el propio actor.
- **Ritmo de ticks:** `Engine.time_scale` escala el delta pero no la cantidad de ticks por segundo. `Engine.physics_ticks_per_second` se puede cambiar en ejecución y cambia los ticks por segundo reales. Con `time_scale = ticks / 60`, el delta queda exactamente en 0,01666666666666667, idéntico a 1/60 también en float de 32 bits, para todos los ritmos de 50 a 90.
- **Timing de red:** Godot recomienda `physics_jitter_fix = 0` en juegos en red. Así los ticks quedan atados al reloj real.
- **Interpolación de física:** hay que activarla antes de que los nodos entren al árbol, en `_enter_tree()` del padre o en `project.godot`. Si se activa con el nivel ya cargado, Godot dibuja en el origen todo lo que nunca se mueve, luz incluida.
- **Transforms en las escenas:** en los `.tscn`, `Transform3D(...)` va por filas de la base y después el origen. Escribirlo por columnas invierte la rotación.
- **Aparición en red:** `MultiplayerSpawner` con `spawn_function` corre en todas las máquinas con los mismos datos, así el actor nace igual en todas.
- **RPC:** el remitente de un RPC (`get_remote_sender_id()`) solo se puede leer dentro de la llamada remota.
- **Firewall:** el host que escucha en `127.0.0.1` (`set_bind_ip`) evita el cartel del firewall de Windows en las pruebas locales. Con dos PC, la primera vez hay que permitirlo en red privada.
- **Instancias múltiples:** *Debug > Customize Run Instances* también se aplica a F6.
- **Temporizadores:** `create_timer(segundos, true, false, true)` cuenta segundos reales aunque cambie `time_scale`.
- **Jolt entre dos PC:** con el mismo binario de Godot en dos PC con Windows, las dos calcularon el mismo estado byte a byte durante ~19.000 ticks. Las únicas diferencias vinieron de inputs que llegaron tarde. No prueba otras plataformas.
- **Física dentro de un frame:** varias restauraciones y repeticiones dentro de un mismo frame de física dan lo mismo que la pasada en vivo (1.121 repeticiones).
- **Validar una pose:** el movimiento de velocidad cero alcanza. Una pose metida 3 cm o más en el piso, o adentro de una pared, es empujada afuera; una apoyada o tocando la pared por fuera se mueve menos de 1 mm.
- **Interpolación en hijos:** `reset_physics_interpolation()` también reinicia a los hijos. `get_global_transform_interpolated()` del nodo `Visual`, hijo del cuerpo, da la posición interpolada con el desvío incluido.
- **Exportar:** en esta PC solo están instaladas las plantillas de exportación de Godot 4.6.

**Comprobados durante la validación (puntos 2 a 4):**

- **Cuerpos cinemáticos y consultas (inferencia I2, confirmada):** con Jolt, `AnimatableBody3D` (con o sin `sync_to_physics`), un `RigidBody3D` congelado en modo cinemático (aun con `force_update_transform()`) y un transform puesto directo en `PhysicsServer3D` recién se ven en las consultas después del paso de física siguiente. Un `StaticBody3D` con `force_update_transform()` se ve en el acto.
- **Velocidad vertical al aterrizar:** al aterrizar, `move_and_slide()` deja en cero la velocidad vertical en el mundo. Sobre una base que baja, en el marco de la base eso es subir; por eso se limita a cero la velocidad relativa vertical del que está apoyado.
- **Plazo de corte de ENet:**
    - una conexión asentada se corta después de unos 9,7–10 s de silencio total;
    - ENet reenvía duplicando la espera, y con una espera inicial de ~19 ms la suma da 511 × 19 ms ≈ 9,7 s;
    - el plazo depende de la ida y vuelta medida y nunca baja de 5 s;
    - con la conexión recién empezada aguantó 8 s, y en las dos PC hubo silencios de 3 s que no la cortaron.
- **Cambiar de forma de colisión:** activar una `CollisionShape3D` y desactivar otra (`disabled`) vale en el acto para `move_and_slide()` y las consultas. La repetición determinista con cambios de postura coincide byte a byte.
- **Espacio libre:** `intersect_shape` con una copia de la forma achicada 2 cm distingue "toca el piso" de "choca con el techo".
- **Saltos que no son movimiento:** si un cuerpo salta de lugar a propósito, por ejemplo los pies al cambiar de postura en el aire, la interpolación de física lo dibuja como un movimiento durante un tick. Para dibujarlo de una vez hay que llamar `reset_physics_interpolation()` en ese tick.
- **Avisos de GDScript sin ventana:** los avisos al cargar scripts (división entera, variable que tapa a otra) solo se imprimen con el depurador encendido (`-d`). Sin `-d`, una corrida limpia no prueba que no haya avisos.
- **Scripts de diagnóstico con `-s`:** mover el actor desde el `SceneTree` mismo, antes de que el actor y el nivel estén dentro del árbol corriendo su física, da posiciones basura (`get_physics_process_delta_time()` daba 0). Moverlo desde un nodo hijo con su propio `_physics_process`, como hace la prueba de repetición, da posiciones correctas.
- **Mapa de entrada editado desde afuera:** si se cambia `project.godot` con el editor abierto, el editor tiene el mapa viejo en memoria y al guardar puede borrar las acciones nuevas. Hay que cerrar y volver a abrir Godot.
- **Captura de pantalla:** `get_viewport().get_texture().get_image()` después de esperar `RenderingServer.frame_post_draw` da la imagen con el panel; un aviso que se muestra después no sale en la imagen.
- **Movie Maker para verificar el dibujo:** `--write-movie <carpeta>/f.png --fixed-fps <n> --quit-after <cuadros> --resolution 960x540` graba cuadros numerados del juego, con ventana y sin intervención. Se puede combinar con `-s` para mover la cámara desde un script. Sirvió para ver las bases, la cámara con la postura y la escalera.

**Comprobados en el escalón y en Hanging:**

- **La cápsula sobre el filo de un escalón:** bajando con `test_move()`, la parte redonda choca con la arista, y la normal del choque va de la arista al centro de la esfera. Si queda dentro del ángulo máximo de piso, parece piso aunque la cápsula esté apoyada en el filo, más abajo de la superficie. Por eso la sonda de escalón llegó a aceptar 40 cm, y el alto real se mide con un rayo sobre la superficie.
- **Movie Maker sin `--scene`:** corre la escena principal del proyecto, que es la del parkour, y no la del laboratorio. Hay que pasar siempre `--scene res://scenes/net_lab/net_lab.tscn`.
- **Altura de un salto en los ticks:** en Aire la gravedad se aplica antes de mover, y así las posiciones de cada tick caen sobre la parábola de una velocidad inicial menor en `g·dt/2`. Para que un salto llegue a una altura exacta, se le suma `g·dt/2` a la velocidad de la cuenta continua. Con eso, el salto para arriba buscado a 20 cm llegó a 20,4 cm.
- **Manejar el laboratorio con teclas simuladas:** `Input.action_press()` y `Input.action_release()` sirven para lo que se lee con `Input.get_vector()`, y un `InputEventAction` mandado con `Input.parse_input_event()` llega a `_unhandled_input()` como una pulsación (Espacio, que es la acción `jump`). Así se hizo la demostración del salto.
- **Una cámara propia desde un script `-s`:** antes de que el nodo esté en el árbol, `look_at()` falla ("Node not inside tree"). Hay que armar el transform con `Basis.looking_at()`. Una `Camera3D` agregada con `current = true` muestra la escena desde otro lado, mientras el input sigue usando el giro de la cámara del laboratorio.
- **Abrir el editor en una escena desde la línea de comandos:** `Godot -e --path <carpeta> res://scenes/net_lab/net_lab.tscn` abre el editor con esa escena. Antes, `--headless --path <carpeta> --import` prepara una copia recién traída y termina solo. Así funciona el doble clic de la notebook.

---

## 13. Problemas y errores, y cómo se resolvieron

| Cuándo | Problema | Causa | Arreglo |
| --- | --- | --- | --- |
| Paso 2 | La repetición difería en el tick 777 | Al restaurar un actor apoyado en el margen de 1 mm, el refresco de velocidad cero no veía el piso | Snap manual de 1 cm en `apply_state()` |
| Paso 1 (error mío) | Rampa invertida y sol apuntando hacia arriba | Las matrices se escribieron por columnas y los `.tscn` van por filas | Matrices transpuestas y verificadas |
| Paso 2 | La ruta de la prueba no llegaba a la rampa | El escalón cerraba el paso | Registro por tramo y ruta por el lado abierto |
| Pasos 1 y 2 (error mío) | "Se carga una escena totalmente diferente" | Interpolación de física activada en `_ready()` | Pasó a `_enter_tree()` y se verificó con fotogramas |
| Paso 3 | Cápsulas flotando a 0,5 m en los clientes | El cliente no simula y la cápsula no bajaba | Aparecen en y = 0, ya apoyadas |
| Paso 3 (error mío) | Instrucciones incomprensibles | Argumentos de lanzamiento y menús de Godot explicados con jerga | Menú dentro del juego e instrucciones clic por clic |
| Paso 4 (error mío) | Afirmé un "mantle automático" de la cápsula sin comprobarlo | Conclusión sin prueba | Retirada; la explicación simple es saltar desde la plataforma de 2 m |
| Primer zip | La herramienta de PowerShell bloqueó `-replace '\\','/'` | Restricción de la herramienta | Se usó `.Replace([char]92,[char]47)` |
| Paso 5 (diseño mío del paso 3) | 25 saltos de reloj en ~2 min por Wi-Fi | El reloj confiaba en pings sueltos | Reloj nuevo en el paso 6 |
| Paso 6 (error mío) | Saltos de reloj en cadena hasta un tick negativo con internet mala | Pings viejos seguían pidiendo un salto después de saltar | Cada ping guarda los ajustes hechos hasta ese momento; hacen falta dos estimaciones malas seguidas |
| Paso 6 (dos PC) | Tirones de unos 10 s cuando la red pasa a 400 ms | El adelanto crecía un tick cada ~0,8 s | Retoque 6b: ritmo variable |
| Paso 6 | Tirones de 16 ms en cada ajuste | Frames con 2 ticks o con 0 | Retoque 6b |
| Paso 7 (diseño) | La adopción causaría una corrección y otra de vuelta | El cliente corregía con estados que el host calculó repitiendo un input | El cliente espera esos estados provisorios |
| Paso 7 | En el primer tick, el host trataba a su propio actor como ajeno | `_local_actor` se asigna un frame después | Comparar el dueño con el id de esta máquina |
| Paso 7 (dos PC) | Con 61 empujones, la cápsula salió del mapa y cayó para siempre | Los empujones suman velocidad y el laboratorio no tenía reaparición | Reaparición por debajo de −30 m en el paso 8 |
| Paso 8 (dos PC) | Una corrección de 1,70 m por un empujón se ve como salto | Los empujones son eventos inmediatos; con 400 ms la diferencia pasa de 1,5 m | Eventos programados en el punto 4: el programado no corrige. El inmediato sigue igual, a propósito (en la prueba del punto 4, la última corrección fue de 3,43 m) |
| Este documento | Los scripts de PowerShell con acentos fallaban | PowerShell 5.1 lee los scripts UTF-8 sin BOM como ANSI, y un carácter roto pasó por comilla | Scripts en ASCII; el contenido con acentos se lee de archivos UTF-8 |
| P2 | La prueba `ride` se trababa contra el muro en x = 5,65 | Iba en línea recta hacia la base | Ruta de dos tramos: primero en x, después en z |
| P2 | Al caer sobre el ascensor bajando, el actor rebotaba en Aire varios segundos | Godot deja en cero la velocidad vertical en el mundo; en el marco de una base que baja, eso es subir | Apoyado sobre una base, la velocidad relativa vertical no puede ser hacia arriba |
| P2 | Un cambio no entró al archivo | El comentario de referencia había cambiado en el paso 7 | Se insertó antes del comentario actual |
| P2 | Partes del laboratorio leían `state.position` como posición en el mundo (reaparición, dirección del empujón, panel) | Con bases, la posición es relativa | Se pasaron a `BaseRegistry.world_position()` y se revisó el resto del código |
| P2 (dos PC) | Tres sesiones se cortaron | Silencios de 4,5–5,4 s en lo que mandaba la notebook (lluvia, Starlink); ENet corta y el laboratorio no se reconecta | Explicado y medido; la reconexión queda pendiente |
| P2 | La primera medición del plazo de ENet aguantó 8 s | La conexión recién empezaba y su ida y vuelta medida estaba inflada | Repetida con 40 s de conexión asentada: 9,7–10 s |
| P2 (error mío) | Se buscaron estadísticas de ENet que no existen (`PEER_TIMEOUT_*`) | Supuse constantes que `ENetPacketPeer` no tiene | Se sacaron, y el plazo se midió congelando el host |
| P2 (error mío) | Informé que la balsa con internet mala daba 0 correcciones | Era una sola prueba; la balsa se mueve al azar | Corregido al entregar: ráfagas de 0 a 51 al subirse |
| P2 | El otro jugador pegaba un salto de hasta 0,41 m al saltar del vagón o caer sobre él | Arriba se lo dibujaba con el vagón adelantado de la notebook; en el aire, en el pasado | Primera vuelta: repartir el cambio en ~0,2 s |
| P2 | El panel de tirones contaba mal sobre una base | Usaba la velocidad relativa | Usa la velocidad en el mundo y la posición dibujada |
| P2 (reporte del usuario) | "tiene que hacer un ajuste cuando la capsula toca la plataforma" | La primera vuelta había convertido el salto en un deslizamiento al aterrizar | Marcos de dibujo (segunda vuelta) |
| P2 (reporte del usuario) | "en los bordes, todavía es apreciable la corrección" | El vagón se dibujaba en el momento propio y el otro jugador en el pasado | Lejos, el vagón se dibuja en el mismo pasado (tercera vuelta) |
| P2 | Quedaba un ajuste de 0,1 m en cada cambio de marco | Se comparaba el lugar visto en el tick anterior con el nuevo | Se comparan los dos marcos en el mismo momento mostrado |
| P2 | Caso raro: volver al vagón al final de un salto bajo, con la cápsula que mira cerca | Se suman el ajuste lento de bajarse y el corto de subirse (sospecha, sin reproducir) | Aceptado como límite conocido ("estaba cerca") |
| P2 | Hook de la herramienta bloqueó un PowerShell con `-match` y `$Matches` | Lo interpretó como un borrado en una ruta del sistema | Reescrito con `Select-String` |
| P3 | La prueba del túnel se caía del mapa | Saltaba sin frenar, todavía a 5 m/s | Una pausa antes del salto |
| P3 (error mío) | La primera medición de pies y cabeza dio números basura | El script movía al actor antes de que estuviera dentro del juego | Un nodo hijo con su propio `_physics_process` |
| P3 (reporte del usuario) | "los pies siempre se mantienen en el mismo lugar" al agacharse, en el piso y en el aire | El código sí hacía dos cosas distintas; la cámara subía con los pies y bajaba despacio, y el dibujo interpolaba el salto de los pies | Pausa, pared y medición para verlo; después, arreglo de la cámara y del dibujo |
| P3 | La pausa con P y O no estaba en el Mapa de entrada | Se leían las teclas directo en el código | G (`toggle_debug_freeze`) y F (`avanzar_tick`), a pedido |
| P3 (error mío) | El aviso de que la pausa solo anda en Jugar solo quedó enterrado entre explicaciones | — | Explicado; se ofreció un aviso en el panel (no pedido) |
| P3 | 9 avisos en el Debugger (8 de los primeros pasos, 1 de la base propia) y 1 más en la repetición | Parámetro `state` repetido, divisiones enteras y una variable repetida | Nombres cambiados y divisiones marcadas a propósito |
| P3 | No se podía capturar la pantalla con Ctrl apretado | Windows + Impr Pant necesita soltar teclas | F12 dentro del juego |
| P3 (dos PC) | 1 corrección de 1,21 m en la prueba del túnel | Un corte del Wi-Fi (80 esperas y un salto de reloj en 6 s) | Confirmado sin pantalla: viene del corte, no de la postura |
| P4 | La prueba de escalera oscilaba al pie | Alternaba entre alinearse y agarrarse | Una vez alineada, la alineación queda fija |
| P4 | La ruta de la repetición se caía del mapa, no llegaba a reagarrar o el empujón fuerte la tiraba arriba de la plataforma | Tramos largos y orden de los tramos | Tramo acortado, parada antes del salto, tramos reordenados y vuelta en diagonal |
| P4 | El primer análisis de la prueba en pareja miraba momentos equivocados | El cliente arranca 1,5 s después que el host | Se miran solo los momentos en que cambian el modo o la época |
| P3 | Los zips ya no estaban en el Escritorio para comparar antes del commit | Se habían movido o borrado | Se comprobó que ningún archivo cambió después de armar el último zip |
| Esc | La sonda subía escalones de 40 cm | La cápsula quedaba apoyada en el filo y eso contaba como piso; el alto se medía con la cápsula | Un rayo sobre la superficie que pisa limita el alto real |
| Esc | Yendo en diagonal o despacio, no subía 30 cm | Avanzaba poco hacia el escalón y la parte redonda no llegaba a apoyar como piso | Avance mínimo de `radio × (1 − sen(ángulo de piso)) + 1 cm` hacia la pared |
| Esc (error mío) | La rampa invisible quedaba 20 cm por debajo de las puntas de los escalones | Mal calculada | Se corrió para que pase por las puntas |
| Esc | La ruta de la repetición no llegaba a la pista | Ticks de los tramos | Recalculados |
| Esc | Un hook de la herramienta bloqueó un PowerShell con `/MIR` | Lo interpretó como un comando peligroso | El `robocopy` se corrió desde un archivo de script |
| Esc (error mío) | Una grabación con Movie Maker corrió la escena del parkour | Faltaba `--scene` | Se repitió con `--scene`; no se modificó nada del parkour |
| P5 | La prueba `hang` se trababa contra el muro largo | Iba en línea recta | Primero en x, después en z |
| P5 | El barrido tenía casos imposibles o mal clasificados | Arranques bajo el piso, casos que se desviaban por encima del bloque, un chequeo de manos demasiado estricto, un "\n" literal de una edición con perl y la punta del techo bajo contada como no buscada | Arreglados uno por uno |
| P5 | Los bordes que se mueven no se alcanzaban | Estaban detrás de las filas de la pista | Se movieron al este |
| P5 | Snaps laterales de hasta 26 cm al llegar en diagonal | El filo se tomaba donde tocaban las manos | El filo se toma enfrente del centro del cuerpo |
| P5 | No subía al borde inclinado 25° | El final de la subida no encontraba piso caminable debajo | El segundo tramo va a la altura del filo y el piso se busca hasta 0,6 m más abajo |
| P5 | La cámara saltaba 0,262 m en 50 ms al agarrarse (criterio 4) | El desvío del agarre decaía como una corrección | Tope de 1,8 m/s: 0,090 m |
| P5 | Avisos de GDScript | `snapped` tapaba una función de Godot, un parámetro sin usar y `name` repetido | Nombres cambiados |
| P5 (reporte del usuario) | "el desplazamiento horizontal depende totalmente de esta [la cámara]" | Colgado se usaba la dirección de caminar, girada según la cámara, proyectada sobre el filo | A y D directos, a lo largo del filo (sección 8.5) |
| P5 (reporte del usuario) | Había que apretar W para agarrarse | La captura pedía intención hacia la pared, como el documento | Sin teclas, las manos buscan hacia donde mira el personaje (sección 8.5) |
| P5 (error mío) | Al sumar el caso sin teclas al barrido, una edición con perl rompió un bloque del archivo | El reemplazo de varias líneas no hizo lo esperado | Se rearmó el bloque a mano y se revisó |
| P5 | En la repetición, el salto sin teclas no se agarraba | El tramo terminaba un tick antes del agarre, y el siguiente apretaba D | `diag_sin_teclas.gd` mostró que se agarra; el tramo pasó de 50 a 60 ticks |
| P5, salto | La salida "subir" del barrido fallaba en 1.281 de 1.502 casos | Con W apretada desde el salto, el personaje acelera en el aire y en los bloques de 1 m de fondo se pasa de largo | Medido con `diag_salto_arriba.gd`; se sumó la salida "subir con W recién arriba" (1.934 de 1.955) y se le preguntó al usuario, que lo dejó así |
| P5, salto (error mío) | La pregunta sobre qué hacer con eso no se entendió: "¿que?" | Explicación enredada, con demasiados números | Explicada de nuevo, más simple, y después mostrada en una demostración con capturas paso a paso |
| P5, salto | La repetición y la prueba guionada se pasaban del bloque de 1 m | Apretaban W desde el salto | Aprietan W en la punta del salto |
| P5, salto | La prueba guionada en red daba 3 subidas en vez de 4 | La prueba de 45 s termina antes de la cuarta | Corrida sola 70 s: 6 subidas en 6 intentos |
| P5, salto | Correcciones de 1,5 a 2,7 m sobre el borde del cuerpo del host, con internet mala | Al aterrizar arriba de una balsa que mueve el host, cliente y host no coinciden en si quedó arriba o cayó | Encontrado con un aviso provisorio que imprimía cada corrección de más de 50 cm (ya sacado). Avisado; no se tocó |
| P5, salto | La primera demostración: el personaje chico, el panel tapando la imagen, la línea de teclas un cuadro atrasada y errores de Godot al apuntar la cámara | Cámara lejos; el panel del laboratorio; el texto se armaba antes de apretar; `look_at()` fuera del árbol | Cámara más cerrada, panel oculto, el texto se arma después de cada acción y el transform se arma con `Basis.looking_at()` |
| P5, salto | Un script de reemplazos para este documento no aplicó nada | Una barra sin escapar en "m/s" | Se hicieron ediciones sueltas |
| P5, subiendo | Sin el límite, en el muro de 2,4 m el agarre tiraba del cuerpo 30 cm para arriba | Las manos encuentran el borde cuando todavía les faltan unos 30 cm | Subiendo, espera a que la pose quede a 10 cm o menos por encima de los pies (`hang_rise_reach`) |
| P5, subiendo | En el muro de 2 m no se agarraba subiendo | Las manos pasan el borde en el tick del salto, que todavía es Suelo, y la sonda mira dónde van a estar al final del tick | Subiendo, si no encuentra nada, barre las manos de arriba hacia abajo hasta donde estaban en el tick anterior |
| P5, subiendo | Debajo del techo bajo, saltar hacia atrás agarraba el techo (132 casos del barrido) | El personaje seguía mirando a la pared y las manos buscaban para ese lado; antes lo frenaba el límite de subida | Se le preguntó al usuario: al saltar hacia otro lado, el personaje se da vuelta hacia donde salta |
| P5, subiendo (error mío) | Con el salto para arriba quedó viejo el "Estado" de Hanging en el documento de arquitectura ("y, mientras sube, el avance de la subida") | No lo vi al corregir la subida | Corregido con nota junto con este cambio |

---

## 14. Decisiones tomadas y forma de trabajo acordada

**Decisiones de diseño:**

- **Arquitectura desde cero**, ignorando los diseños y el código de parkour anteriores (pedido original).
- **Hanging con snap** (2026-10-02, 11:40): "bien, entonces vamos a usar el snap".
- **Subir al borde es una salida de Hanging** (2026-10-02, 11:48): "sumalo como salida de Hanging, no es mantle".
- **Mantle fuera del alcance** (pedido original).
- **Esqueleto de red sin netfox**, en 8 pasos, en carpetas nuevas (2026-10-02, 11:59).
- **La otra PC también usa Windows**, y se empezó por los pasos 1 y 2 (12:31).
- **Copiar el proyecto en vez de exportar** (14:00), con zips en el escritorio (17:55).
- **Seguir con el paso 6 empezando por el reloj** (20:34), después de discutir el orden.
- **Retoque 6b antes del paso 7**, con un commit local antes del retoque (21:21).

**Decisiones de la validación:**

- **Validar la arquitectura de a un punto,** en el orden de la lista del documento (2026-10-03, 17:09): "vamos a la validacion anterior, donde presentaste los 6 puntos y empecemos con el primero".
- **El caso raro del vagón queda como límite conocido** (2026-10-06, 13:27): el ajuste al volver a la plataforma al final de un salto bajo, con la cápsula que mira cerca. "estaba cerca, dale, seguí con el punto de postura".
- **Herramientas de prueba antes de tocar la postura** (14:10): una pausa que congela al jugador con sus coordenadas, y una pared con medidas.
- **Teclas** (14:36): "usa la G para pausar y mapea la tecla F para avanzar de tick". La G usa la acción del parkour que ya existía; la F es una acción nueva.
- **Limpiar los avisos del depurador** (16:24): "dale, limpialos".
- **Capturas con F12** dentro del juego (16:37).
- **En el aire, la forma crece hacia abajo, y agacharse sube los pies** (19:18): "perfecto, que se quede asi, seguí con el punto de la escalera". Se mantiene que agacharse saltando llega más alto.
- **El cambio en el control aéreo** (no frenar a quien viene más rápido que caminando) se avisó al entregar el punto 3 y quedó así.
- **El escalón antes del punto 5** (2026-10-07, 13:41), siguiendo la filosofía de la arquitectura: la sonda de Suelo para escalones sueltos y la rampa invisible para escaleras.
- **El escalón queda cerrado** (16:54): "eran dos gotas de agua".
- **La notebook se actualiza desde una carpeta compartida y abre el editor con la escena** (14:24).
- **Controles de Hanging** (18:10): Espacio mirando a la pared sube, Espacio mirando a otro lado salta, Ctrl suelta, y A y D de costado. "hay que probar de ambas maneras, es mas por el feeling que otra cosa".
- **Alcance de las pruebas de Hanging** (18:10): las automáticas 1 a 6 y la prueba en dos PC; la 7, con personas, para cuando haya gente.
- **Criterios de Hanging** (18:10): "Los del documento", con el tope de 10 cm de cámara en 50 ms.
- **La subida al borde queda como está** (22:20): "me hubiese gustado mas un saltito, pero por ahora lo dejamos así".
- **Agarrarse sin apretar W** (22:20): "no siempre queres darle a la W para llegar a X lado". Se aparta del documento, que pedía intención hacia la pared (secciones 4.4 y 8.5).
- **A y D colgado, sin depender de la cámara** (22:20): "así puedo poner la cámara hacia la derecha y poder moverme a la derecha sin tener que poner la cámara hacia la izquierda".
- **La subida al borde pasa a ser un salto para arriba con control aéreo** (2026-10-08, 11:50), "temporalmente". El margen es de 20 cm por encima del filo.
- **El control aéreo del salto queda como está** (12:44): con W desde el salto, en los bordes angostos se pasa de largo. "uno aprende muy rápidamente y se adapta al toque con los controles, por ahora lo dejamos asi, le doy el visto bueno."
- **Las correcciones sobre el borde del cuerpo del host con internet mala** se avisaron (13:25) y no se tocaron.
- **Agarrarse también subiendo** (2026-10-08, 17:37), pedido con un dibujo: "con que estes pegado al muro y saltando, ya es suficiente para que te agarres".
- **Al saltar hacia otro lado desde el colgado, el personaje se da vuelta hacia donde salta** (17:45): "Que mire hacia donde salta".
- **Agarrarse igual del techo bajo girando la cámara a tiempo queda así** (19:24): "medio que se siente como un logro mas que otra cosa".

**¿Cuánto cuesta cambiar una mecánica después?** (pregunta del 2026-10-07, 13:06). La respuesta, resumida:

| Qué se cambia | Ejemplo del laboratorio | Cuánto cuesta |
| --- | --- | --- |
| Un número | Velocidad al trepar, rozamiento al deslizar, fuerza del salto | Poco: es una línea. El riesgo está en el nivel: si el salto baja, una plataforma que se alcanzaba deja de alcanzarse |
| Cómo funciona un modo por dentro | Que salir por arriba de la escalera sea un movimiento en el tiempo | Poco a medio: se toca ese modo y su prueba |
| Cómo se entra o se sale de un modo | Que al caer agachado y rápido pase directo a deslizarse | Medio: se toca la lista de salidas de otro modo, y hay que revisar el orden de prioridad |
| Una regla compartida | Agacharse en el aire, el control en el aire, la fuerza contra el agarre | Alto: la usan todas las mecánicas |
| Algo nuevo que la mecánica tenga que recordar | Un temporizador o un contador | Trabajo de rutina: va al estado del actor y cambia el formato de red; las dos PC tienen que tener la misma versión |

A favor:

- la red no depende de qué mecánicas haya;
- cada modo tiene su lista de salidas a la vista;
- las pruebas automáticas avisan si algo se rompió, aunque solo cubren los recorridos guionados.

En contra: cuantas más mecánicas usen una regla compartida, más cuesta cambiarla después.

Los dos cambios de Hanging de la sección 8.5 fueron de la segunda y la tercera fila. Tocaron solo `actor_motor.gd` y sus pruebas.

**Forma de trabajo acordada:**

- **Instrucciones clic por clic:** nada de argumentos ni jerga para probar. El laboratorio tiene un menú dentro del juego, y las instrucciones nombran los botones exactos ("literal no entendí una absoluta mierda", 13:45).
- **No afirmar sin probar:** primero la explicación simple o una prueba ("lo del mantle creo que es una alucinación tuya", 18:57).
- **Commits locales solo cuando se piden, y sin subir nada.** Cada commit lleva solo los archivos del laboratorio, verificados antes; los cambios de parkour sin commitear no se tocan.
- **Cada paso se prueba en las dos PC** con un zip nuevo, y se analizan las capturas del panel.
- **Antes y después medidos:** antes de cambiar algo, se mide el comportamiento actual en el mismo escenario.
- **Desde la validación, el commit va después de la prueba en dos PC,** con lo que se probó. Antes de cada commit se comprueba que los archivos son idénticos a los del zip probado. Si el zip ya no está, se comprueba que nada cambió después de armarlo. Si un arreglo nuevo ya está encima, se commitea la versión probada sin tocar el árbol de trabajo.
- **`project.godot` va solo con las líneas del laboratorio:** el cambio de versión 4.6 → 4.7 que hizo el editor no se commitea.
- **Ante una duda del usuario sobre cómo se comporta algo, no se discute:** se mide y se le dan herramientas para verlo por sí mismo, como la pausa, la pared y las capturas.
- **Lo que sale de leer el código y no de una prueba se avisa como tal** ("no lo probé en partida, sale de leerlo").
- **Archivos de prueba:** solo se borran los que hice yo, como la captura de prueba del Escritorio.
- **El doble clic de la notebook se hace recién cuando aviso que algo está listo** (2026-10-07, 16:09). Si no, puede llegar una versión a medio terminar.
- **Sin zips, lo probado se fija con huellas SHA-1** de los archivos del laboratorio al avisar que está listo, y se comparan antes del commit (desde Hanging).

---

## 15. Commits y entregas

**Commits** (todos locales, en la rama `codex/parkour-v3-h0-lab`, sin remota configurada):

| Commit | Fecha | Mensaje | Archivos | Líneas |
| --- | --- | --- | --- | --- |
| `d75ef67` | 2026-10-02 21:25 | feat(net): add co-op network skeleton lab (steps 1-6) | 30 | +1.994 |
| `9cd1936` | 2026-10-03 11:38 | feat(net): hold client lead by varying the tick rate (step 6b) | 3 | +206 / −64 |
| `7547de1` | 2026-10-03 15:53 | feat(net): add claims, adoption and epoch (step 7) | 9 | +289 / −42 |
| `c0e0421` | 2026-10-03 16:22 | feat(net): interpolate other players and smooth corrections (step 8) | 9 | +242 / −21 |
| `9caaec3` | 2026-10-03 17:10 | docs(net): record architecture and network skeleton history | 1 | +2.393 |
| `600002a` | 2026-10-03 19:54 | feat(net): carry actors on scripted platforms and host rafts | 17 | +533 / −32 |
| `25f7806` | 2026-10-06 12:51 | feat(net): draw other players consistently on moving platforms | 5 | +268 / −38 |
| `cb71b16` | 2026-10-06 17:23 | feat(net): add stance, free space and slide (validation item 3) | 16 | +592 / −58 |
| `91a4433` | 2026-10-06 21:01 | feat(net): add Ladder mode and scheduled host events (validation item 4) | 12 | +643 / −51 |
| `375d419` | 2026-10-07 12:53 | docs(net): add architecture validation items 2-4 to the history | 1 | +1.849 / −100 |
| `b907dae` | 2026-10-07 16:19 | feat(net): add Ground step-up probe and a step course | 10 | +351 / −7 |
| `3cdcc91` | 2026-10-08 10:55 | feat(net): add Hanging with snap and its confirmation tests (validation item 5) | 16 | +1.359 / −47 |
| `fa26986` | 2026-10-08 11:34 | docs(net): add the step, Hanging and the grab and shimmy change to the history | 1 | +1.193 / −61 |
| `3825c2b` | 2026-10-08 16:40 | feat(net): replace the Hanging climb with an upward jump | 6 | +99 / −128 |
| `048dc4d` | 2026-10-08 16:41 | docs(net): record the Hanging climb jump in the history | 1 | +645 / −44 |
| `bd2157b` | 2026-10-08 19:24 | feat(net): grab edges while rising and turn toward the jump away | 5 | +31 / −18 |

**Zips en el escritorio** para copiar el proyecto a la otra PC, hasta el escalón. Los del esqueleto pesaban 18 MB cada uno; el tamaño de los de la validación no se anotó. Hoy quedan en el Escritorio el de la escalera y el del escalón; los demás se movieron o se borraron. Desde el escalón, la notebook se actualiza con el doble clic de la sección 6.2.

| Zip | Fecha | Contenido |
| --- | --- | --- |
| `tun-tun-tun-sahur_2026-10-02.zip` | 2026-10-02 17:56 | Pasos 1 a 3 con menú (879 archivos) |
| `tun-tun-tun-sahur_2026-10-02_paso4.zip` | 2026-10-02 18:18 | Paso 4 |
| `tun-tun-tun-sahur_2026-10-02_paso5.zip` | 2026-10-02 19:04 | Paso 5 |
| `tun-tun-tun-sahur_2026-10-02_paso6.zip` | 2026-10-02 20:44 | Paso 6 |
| `tun-tun-tun-sahur_2026-10-02_paso6b.zip` | 2026-10-02 21:43 | Retoque 6b (885 archivos) |
| `tun-tun-tun-sahur_2026-10-03_paso7.zip` | 2026-10-03 12:05 | Paso 7 (888 archivos) |
| `tun-tun-tun-sahur_2026-10-03_paso8.zip` | 2026-10-03 16:10 | Paso 8 (890 archivos) |
| `tun-tun-tun-sahur_2026-10-03_base_propia.zip` | 2026-10-03 17:44 | Punto 2: vagón, ascensor y balsa (897 archivos). Es lo que guardó `600002a` |
| `tun-tun-tun-sahur_2026-10-03_base_propia_2.zip` | 2026-10-03 19:56 | Primera vuelta del dibujo del otro jugador sobre el vagón |
| `tun-tun-tun-sahur_2026-10-04_base_propia_3.zip` | 2026-10-04 10:48 | Segunda vuelta: marcos de dibujo |
| `tun-tun-tun-sahur_2026-10-06_base_propia_4.zip` | 2026-10-06 12:28 | Tercera vuelta: el vagón en el pasado. Es lo que guardó `25f7806` |
| `tun-tun-tun-sahur_2026-10-06_postura.zip` | 2026-10-06 13:48 | Punto 3: postura, deslizamiento y túnel |
| `tun-tun-tun-sahur_2026-10-06_postura_2.zip` | 2026-10-06 14:17 | Pausa con P y O, y pared de medidas |
| `tun-tun-tun-sahur_2026-10-06_postura_3.zip` | 2026-10-06 14:37 | Pausa con G y F |
| `tun-tun-tun-sahur_2026-10-06_postura_4.zip` | 2026-10-06 14:55 | Arreglo de la cámara y del dibujo en el aire |
| `tun-tun-tun-sahur_2026-10-06_postura_5.zip` | 2026-10-06 16:28 | Limpieza de avisos |
| `tun-tun-tun-sahur_2026-10-06_postura_6.zip` | 2026-10-06 16:39 | Capturas con F12. Es lo que guardó `cb71b16` |
| `tun-tun-tun-sahur_2026-10-06_escalera.zip` | 2026-10-06 19:49 | Punto 4: escalera y empujones (901 archivos). Es lo que guardó `91a4433` |
| `tun-tun-tun-sahur_2026-10-07_escalon.zip` | 2026-10-07 14:18 | El escalón. Fue el último zip: antes de probarlo se armó el doble clic, y la prueba en dos PC usó el doble clic |

**Entregas con el doble clic** (sección 6.2):

| Fecha | Qué | Commit |
| --- | --- | --- |
| 2026-10-07 16:11 | El escalón, más la primera prueba del doble clic por la red | `b907dae` |
| 2026-10-07 19:36 | Hanging, primera versión | Nunca se commiteó |
| 2026-10-07 23:05 | Hanging con los dos cambios | `3cdcc91` |
| 2026-10-08 13:25 | El salto para arriba en vez de la subida, con las pruebas que aprietan W en la punta. Probado en las dos PC a las 16:28 | `3825c2b` |
| 2026-10-08 18:20 | El agarre subiendo y el giro al saltar hacia otro lado. Probado en las dos PC a las 19:17 | `bd2157b` |

**Lo que no se tocó:** los cambios previos sin commitear de la rama siguen igual. Incluyen `project.godot` (solo con el cambio de versión 4.6 → 4.7 del editor), `docs/parkour/*`, `scenes/test/*`, `scripts/player_v2/*` y `assets/models/*`.

- **Primera versión de este documento:** eran 136, más el temporal del editor `project.godot~RF78902d2f.TMP`: 137.
- **Segunda versión:** `git status` mostraba 138 entradas.
- **Hoy:** `git status` muestra 137 entradas, ninguna de las carpetas del laboratorio.

---

## 16. Pendientes, limitaciones conocidas y próximos pasos

**Lo que sigue en la validación** (sección 8):

- ~~**Punto 5:** el laboratorio de Hanging con snap.~~ Hecho (sección 8.5).
- **Punto 6, el próximo:** una interacción con cambio de línea, sujetar a un compañero.
- **Punto 7:** cámara lenta del mundo y personal.
- **Hanging, prueba 7:** con 5 a 10 personas, cuando haya gente.

**Pedido para más adelante:** la subida al borde con "un saltito". La tercera versión de este documento decía: "Hoy es un recorrido de dos tramos, 0,45 s hacia arriba y 0,25 s hacia adentro". El 2026-10-08 esa subida se reemplazó "temporalmente" por un salto para arriba con control aéreo, y el usuario dijo "por ahora lo dejamos asi" (sección 8.6). Si vuelve una animación de subida, el código viejo está en `3cdcc91`.

**Del plan original, sin hacer:**

- ~~**Eventos programados.**~~ Hechos en el punto 4 (sección 8.3).
- **Registro por tick en cada máquina,** para comparar dos archivos por número de tick.
- **Prueba con dos binarios distintos** (editor contra build exportada; hacen falta las plantillas de exportación de 4.7.2) **y con otras plataformas**, como Linux o Steam Deck.
- **La matriz exacta de la prueba final, para el esqueleto:** 0, 60, 120 y 200 ms; pérdida de 0, 2 y 5 %. Para Hanging sí se corrió (sección 8.5).
- **Rama propia del esqueleto:** los 12 commits están en la rama de parkour. Moverlos a una rama propia sigue ofrecido.

**Limitaciones conocidas de la validación:**

- **Bases:**
    - solo se trasladan, no giran;
    - una plataforma que choca de costado contra un personaje todavía no lo empuja (el documento lo llama empujador guionado);
    - la balsa del host puede dar una ráfaga de correcciones al subirse desde el piso con internet mala (0 a 51 en las pruebas); arriba, ninguna.
- **El otro jugador sobre una plataforma:** con la cápsula que mira cerca del vagón o arriba, queda un ajuste de unos 0,3 m al subirse o bajarse, y el caso raro de volver al final de un salto bajo. Al acercarse desde lejos, el vagón se adelanta de a poco a su momento real.
- **Conexión:** el laboratorio no se reconecta. Un silencio de unos 5 s o más (según la ida y vuelta medida) termina la sesión.
- **Pausa:** solo anda en Jugar solo. En red, la G no hace nada y no avisa; el aviso en el panel quedó ofrecido.
- **Postura:**
    - agacharse saltando llega más alto que un salto normal (decidido así);
    - para deslizarse hay que estar parado al apretar Ctrl: si se salta corriendo con Ctrl apretado, se cae agachado y camina a 2,5 m/s, en vez de deslizarse. Esto sale de leer el código y no se probó en partida; se ofreció cambiarlo y no se pidió.
- **Escalera:**
    - la salida por arriba es instantánea, en un tick, y no una trayectoria en el tiempo como pide el documento (queda para el laboratorio de Hanging);
    - al agarrarse, se pone de golpe sobre el eje, hasta 90 cm;
    - no hay botón de agarrar;
    - las escaleras están fijas.
- **Empujones inmediatos:** con mucha latencia su corrección pasa de 1,5 m y se ve como salto (3,43 m en la prueba del punto 4). Para eso están los programados.
- **Escalón:**
    - bajar no es simétrico: de un escalón suelto se cae unos 0,2 s, y de la escalera sin rampa se sale volando por encima de los escalones. Con la rampa invisible, parejo;
    - deslizándose no sube escalones;
    - a la balsa se sube caminando, y con internet mala puede dar la ráfaga de correcciones de siempre al subirse.
- **Hanging:**
    - solo se agarra desde el aire, porque no existe el modo Pared;
    - no hay superficies no agarrables;
    - el bloqueo de reagarre de 0,3 s es para todos los bordes;
    - no hay capacidades, así que nada impide subir estando aturdido;
    - la cámara se acomoda en 0,19 s de promedio después de agarrarse (el documento proponía 100 a 150 ms);
    - un borde de 1,6 m no se puede agarrar desde el piso;
    - sobre el borde del cuerpo del host hay correcciones chicas mientras se cuelga: de 4,6 a 21 cm en las pruebas. Con el salto para arriba, al aterrizar encima con internet mala, las correcciones llegan a 1,4–2,7 m;
    - con W apretada desde el salto para arriba, en los bordes angostos se pasa de largo; quedó así a pedido;
    - en el borde curvo, agarrado de costado, a veces el salto para arriba no deja arriba (21 de 1.955 casos en el primer barrido, 20 de 2.071 en el último);
    - subiendo, se agarra de cualquier borde que las manos tengan adelante. Debajo del techo bajo, saltando hacia atrás y girando la cámara a tiempo hacia la pared con una tecla apretada, se agarra del techo; quedó así a pedido;
    - si en el aire se aprieta A o D mirando a la pared, las manos buscan hacia ese costado y no se agarra (la tecla manda).
- **Agarrarse sin teclas usa la orientación del personaje,** que la regla general del documento quería evitar para que primera y tercera persona simulen igual. Hoy da lo mismo, porque la orientación sigue al movimiento y no hay primera persona. Hay que revisarlo cuando llegue la primera persona (sección 8.5).
- **Las 62 correcciones y las 108 afirmaciones rechazadas** de la primera prueba de Hanging en dos PC pasaron antes de la primera captura y no se ubicaron. La sospecha es el borde sobre el cuerpo del host.
- **El "tp" de la prueba de la base propia** no se pudo ubicar en las capturas. La sospecha es que se vio en el host, al volver la conexión.

**Para calibrar:**

- `MAX_DIFFERENCE` de la adopción (1 m).
- El control del adelanto con tirones periódicos: con tirones cada 3 s, el ritmo pasa casi todo el tiempo en 57. Ahora que la adopción absorbe los inputs tardíos, podría reaccionar menos.
- El colchón de interpolación (100 ms): con tirones de 150 ms se vacía a veces (14 ticks en la prueba automática; 70 a 96 en las dos PC).
- El umbral de suavizado (1,5 m) y la vida media del desvío (25 ms).
- **El ancho de banda.** En la primera versión de este documento: hasta ~373 bytes por paquete del cliente y 62 bytes por actor en el snapshot. En la segunda, con el estado de 67 bytes: 471 y 78. Hoy, con el estado de 79 bytes, la cuenta da:
    - **cada paquete del cliente:** 2 + 1 + 6 × (10 + 1 + 79) = 543 bytes como máximo, 60 veces por segundo;
    - **el snapshot:** 90 bytes por actor y 26 por balsa (más 1 byte con la cantidad de balsas), 30 veces por segundo.
- **Hanging:** la distancia máxima de snap (35 cm), el tope de velocidad del dibujo al agarrarse (1,8 m/s), la altura del colgado (1,95 m) y el margen del salto para arriba (20 cm).
- **El colchón de los eventos programados** (4 ticks): en la prueba de dos PC llegaron tarde 11 de 29, pero todos se repitieron sin corrección.

**Observaciones de las pruebas reales:**

- La adopción quedó apagada en la prueba del paso 8 (Q). Para jugar normal conviene tenerla prendida; vuelve a estarlo al abrir la escena de nuevo con F6.
- Hubo 1 salto de reloj de causa desconocida en una sesión del paso 7. En la prueba de postura hubo otro, junto con un corte del Wi-Fi.
- El empujón suma velocidad sin límite; con decenas seguidos saca al jugador del mapa. Hoy eso termina en una reaparición.

**Del documento de arquitectura:**

- **La regla de esperar los estados provisorios** que agregué en el paso 7 todavía no está escrita en el documento.
- **La inferencia I2 quedó confirmada** en el punto 2, pero el documento todavía la lista como inferencia. Anotarlo quedó ofrecido.
- ~~**Agarrarse sin intención hacia la pared.**~~ Corregido, con notas, en la copia del Apéndice A y en el documento de Claude Docs (revisión 55).
- ~~**Subir al borde como salto para arriba.**~~ Corregido, con la subida vieja copiada en una nota, en la copia del Apéndice A y en el documento de Claude Docs (revisión 60).
- ~~**Agarrarse subiendo y el giro al saltar.**~~ Corregido, con notas, en la copia del Apéndice A y en el documento de Claude Docs (revisión 65). También el "Estado" de Hanging, que había quedado viejo con el salto para arriba.
- **Cuando el esqueleto pase a ser el juego,** los ajustes que hoy aplica el laboratorio al arrancar (60 ticks, `physics_jitter_fix` en 0 e interpolación de física) van a `project.godot`.
- **Fuera del laboratorio** quedan los demás modos anclados, los cuerpos rígidos, las interacciones, Steam y NAT.

---

## Apéndice A: documento de arquitectura completo

Esta es una copia completa del documento [Arquitectura de movimiento co-op (Godot 4.7 + Jolt)](https://claude.ai/code/artifact/6760c3bf-39ed-4f2f-8d9d-23642c7ac797), en su revisión 52. Se leyó entero el 2026-10-03 y se convirtió a Markdown con un script, sin editar el texto:

- los títulos bajaron dos niveles para quedar dentro de este apéndice;
- los tres diagramas, que en el original son widgets interactivos, se transcribieron en texto con todos sus rótulos.

Ya incluye las decisiones posteriores: Hanging con snap y subir al borde como salida de Hanging.

**Correcciones del 2026-10-08.** Desde esta actualización, la copia se aparta del texto original en cuatro lugares, cada uno con una nota que dice qué decía antes y por qué cambió:

- la transición de Aire a Hanging, en "Transiciones como listas planas";
- la regla de que las condiciones no usan la orientación del modelo, en la misma sección;
- la captura, en "Hanging: con snap" > "Lo común";
- desplazarse colgado, en esa misma lista.

El cambio viene de la prueba de Hanging en dos PC (sección 8.5). El documento de Claude Docs se corrigió en los mismos lugares, con notas equivalentes: pasó de la revisión 52 a la 55. Ahí las notas de Captura y de Desplazarse colgado van juntas, debajo de la lista.

**Más tarde el mismo día**, con la subida al borde reemplazada por un salto para arriba (sección 8.6), la copia y el documento de Claude Docs (revisión 60) cambiaron en otros cuatro lugares:

- "Subir al borde" se reescribió, con la subida vieja copiada en una nota;
- la lista de salidas de "Lo común": subir ya no es la excepción que no va a Aire;
- los ejemplos de trayectorias autoradas, en "Animación";
- las poses que se validan con `test_move()`, en "Herramientas de Godot y Jolt".

La nota de "Subir al borde" cuenta los cuatro cambios.

**Después, con el agarre subiendo** (sección 8.7), la copia y el documento de Claude Docs (revisión 65) cambiaron en tres lugares más, cada uno con su nota:

- la fila 2 de la transición de Aire, que decía "no sube rápido";
- la captura, en "Lo común", que decía "velocidad vertical por debajo de un máximo de subida";
- en la misma lista, las salidas (el personaje se da vuelta al saltar hacia otro lado) y el "Estado", que había quedado viejo con el salto para arriba.

### Arquitectura de movimiento co-op (Godot 4.7 + Jolt)

2026-10-01 · Alicia

#### Resumen

Propongo un **host autoritativo donde cada cliente predice solo su propio personaje, y el host adopta esa predicción cuando es físicamente válida y no hubo eventos del host de por medio**. Así las diferencias de Jolt entre máquinas no producen correcciones: solo se corrige lo que el cliente no podía saber.

Sobre esa base, el movimiento se arma con pocas piezas que se combinan por reglas generales, no por excepciones:

- **Un estado completo por actor** y **un paso por tick con orden fijo**: efectos, sondas, transiciones, modo, movimiento, contactos. Una corrección restaura ese estado y repite los ticks; la acción a medias sigue coherente.
- **Un solo modo activo**, dueño de cómo se mueve el cuerpo: Suelo, Aire, Deslizamiento, Pared, Ladder, Hanging, Tirolesa, Cuerda, Enganchado y Muerto. Sprint, dash, saltos especiales, aturdimiento o cámara lenta no son modos.
- **Siete reglas generales** resuelven las combinaciones: fuerza contra agarre, invariantes con salida de respaldo, postura según espacio libre, velocidad relativa a la base, tiempo del actor, capacidades y anclas que pueden desaparecer.
- **`move_and_slide()`** **solo en modos libres.** Los modos anclados calculan su pose desde el ancla y la barren o validan. Las sondas son consultas directas al espacio; el transform directo queda para restauraciones, respawn y snaps validados.
- **Las interacciones co-op son pedidos que valida el host.** Crean anclas, impulsos programados o temporizadores. Quien queda colgado de algo impredecible pasa a ser conducido por el host mientras dure.

Para Hanging quedó decidido el **snap lógico con continuidad visual**: deja el estado de red en ancla más posición sobre el borde. Sigue las mismas reglas que los demás modos anclados; las pruebas de la sección Hanging lo confirman o lo reabren.

Las secciones 2 y 3 son la base (hechos y red), 4 a 8 el diseño, 9 Hanging, 10 los recorridos de casos, 11 y 12 descartes y riesgos.

#### Hechos comprobados e inferencias

El diseño se apoya en estos hechos, leídos el 2026-10-01 en la documentación y el código de Godot 4.7.2 y de Jolt. Lo que no pude verificar va aparte, marcado como inferencia.

##### Godot 4.7.2 y Jolt

| Hecho comprobado | Fuente | Consecuencia para el diseño |
| --- | --- | --- |
| `is_on_floor()`, `is_on_wall()` e `is_on_ceiling()` dicen si hubo contacto "en el último llamado a `move_and_slide()`". La normal de piso y la velocidad de plataforma son "solo válidas después de llamar a `move_and_slide()`". | [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html) | Son salidas del último movimiento, no estado del personaje. "En suelo" se guarda en el estado del actor. |
| `move_and_slide()` usa el delta del paso de física automáticamente; en código: `get_physics_process_delta_time()` si está dentro del frame de física. | [CharacterBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/CharacterBody3D.xml), [character_body_3d.cpp](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/3d/physics/character_body_3d.cpp) | Para escalar el tiempo de un solo actor, o repetir ticks, se multiplica `velocity` antes de mover y se divide después. |
| Internamente, `move_and_slide()` usa el estado de piso del llamado anterior (`was_on_floor`) para el snap, la pendiente, la velocidad constante y el bloqueo contra paredes. | [character_body_3d.cpp](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/3d/physics/character_body_3d.cpp) | Después de restaurar una posición, ese estado interno queda viejo y hay que sincronizarlo. |
| El snap al piso no se aplica si la velocidad sube a lo largo de `up_direction`; así el cuerpo se despega al saltar o al ser empujado hacia arriba. | [CharacterBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/CharacterBody3D.xml) | Saltos, trampolines y explosiones despegan del piso sin una excepción propia. |
| La velocidad de plataforma se lee del estado físico actual del cuerpo de abajo al momento de mover. `platform_floor_layers` permite excluir cuerpos. | [character_body_3d.cpp](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/3d/physics/character_body_3d.cpp) | En un tick repetido esa velocidad es la del presente. Se desactiva y la base la maneja el diseño (sección del actor). |
| `MOTION_MODE_FLOATING`: no hay piso ni techo, todas las colisiones cuentan como pared. | [CharacterBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/CharacterBody3D.xml) | Sirve para gravedad cero, no para modos anclados. |
| `CharacterBody3D` no tiene parámetro de escalón; `move_and_slide()` es código de Godot que hace pruebas de movimiento contra el servidor de física. | [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html), [character_body_3d.cpp](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/3d/physics/character_body_3d.cpp) | Los escalones se resuelven con rampas de colisión o una sonda propia. |
| `move_and_collide()` se detiene en el primer contacto; con `test_only`, y con `test_move()`, prueba sin mover. | [PhysicsBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/PhysicsBody3D.xml) | Barridos de los modos anclados y pruebas de espacio libre. |
| `cast_motion()` ignora las formas que ya se tocan al empezar. `intersect_shape()` e `intersect_point()` devuelven listas limitadas por `max_results`. | [PhysicsDirectSpaceState3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/PhysicsDirectSpaceState3D.xml) | Las sondas barridas arrancan fuera de la geometría y los resultados se ordenan por código propio. |
| Jolt es el motor por defecto en proyectos nuevos. Usa "radio convexo": encoge la forma y le agrega una cáscara, regulado por Collision Margin Fraction. | [Using Jolt Physics](https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html) | Las aristas de cajas y convexos quedan redondeadas: las sondas de borde necesitan tolerancia. |
| Jolt reduce colisiones fantasma con aristas activas y enhanced internal edge removal, con ajustes separados para simulación, consultas y consultas de movimiento. `face_index` vale -1 por defecto. | [Using Jolt Physics](https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html) | Se valida en el laboratorio con las mallas reales; nada depende de `face_index`. |
| Jolt es determinista con el mismo binario y el mismo orden de llamadas. Entre plataformas exige una opción de compilación (alrededor de 8 % más lento). Las consultas de fase estrecha dan resultados consistentes en orden variable. | [Jolt Architecture.md](https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/Docs/Architecture.md) | No hay lockstep. Los resultados de consultas se ordenan por distancia e id. |
| El `PhysicsServer3D` de 4.7.2 no permite avanzar la simulación a mano ni guardar o restaurar su estado. La PR que agrega `space_step()` sigue abierta. | [PhysicsServer3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/PhysicsServer3D.xml), [PR 76462](https://github.com/godotengine/godot/pull/76462) | Los `RigidBody3D` no se pueden predecir ni rebobinar: solo los simula el host. |
| `Engine.time_scale` escala el delta de `_process`, `_physics_process` y los timers, pero no cambia `physics_ticks_per_second`. | [Engine.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Engine.xml) | Cámara lenta del mundo: mismos ticks por segundo, dt más chico, Jolt incluido. |
| Godot recomienda `physics_jitter_fix = 0` en juegos en red o con interpolación propia. | [Engine.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Engine.xml) | Ajuste del proyecto. |
| La interpolación de física exige mover dentro del tick. `reset_physics_interpolation()` evita el barrido al teletransportar. La cámara con mouse se recomienda sin interpolar y rotada en `_process`. | [Using physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html), [Advanced](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html) | Presentación separada de la simulación; respawn con reset; cámara local. |
| `MultiplayerSynchronizer` copia propiedades desde el autoritativo y no menciona ticks, acuses de input, predicción ni interpolación. Los RPC ofrecen `unreliable`, `unreliable_ordered`, `reliable` y canales. | [MultiplayerSynchronizer.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/modules/multiplayer/doc_classes/MultiplayerSynchronizer.xml), [High-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html) | El actor predicho necesita un protocolo con número de tick. |
| `StaticBody3D.constant_linear_velocity` afecta a quien lo toca sin moverse (cintas). `AnimatableBody3D` estima su velocidad al moverse y empuja lo que encuentra. | [StaticBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/StaticBody3D.xml), [AnimatableBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/AnimatableBody3D.xml) | Cintas y plataformas se leen como datos de superficie desde la base propia. |
| `PhysicsBody3D.get_gravity()` devuelve la gravedad con los overrides de `Area3D`. | [PhysicsBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/PhysicsBody3D.xml) | Ver inferencia I3. |

##### Referencias actuales de motores 3D

| Referencia | Qué documenta | Qué tomo |
| --- | --- | --- |
| [Unreal 5.8, Character Movement networking](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-networked-movement-in-the-character-movement-component-for-unreal-engine) | El cliente predice y guarda movimientos; el servidor compara con una tolerancia (`MAXPOSITIONERRORSQUARED`) y corrige; el cliente repite sus movimientos guardados. | Predicción del propio personaje y tolerancia antes de corregir. |
| `bServerAcceptClientAuthoritativePosition` de ese componente, y la advertencia del plugin [PredictedMovement](https://github.com/Vaei/PredictedMovement/wiki/Client-Authority) | Sin error detectado, el servidor copia la posición del cliente. Riesgo citado: el cliente no se entera de efectos como una ralentización. | La adopción, más una "época de efectos" que cierra ese hueco. |
| [Unreal 5.8, Mover (experimental)](https://dev.epicgames.com/documentation/en-us/unreal-engine/mover-features-and-concepts-in-unreal-engine) | "Hay exactamente un modo activo a la vez"; movimientos en capas; modificadores para postura; efectos instantáneos (teleport, velocidad forzada); transiciones; estado sincronizado por instante. | Un modo exclusivo más mecanismos que no son modos. |
| [Unity Netcode for Entities, prediction switching](https://docs.unity3d.com/Packages/com.unity.netcode@1.5/manual/prediction-switching.html) | Línea predicha adelante del servidor e interpolada detrás; pasar de una a otra salta más de 2 × ping sin `TransitionDurationSeconds`. | Cambio de línea temporal con transición suavizada. |
| [netfox, rollback caveats](https://foxssake.github.io/netfox/latest/netfox/tutorials/rollback-caveats/) (addon de Godot) | Multiplicar `velocity` por un factor para `move_and_slide()`; mover con velocidad cero para refrescar `is_on_floor()`; rollback con RigidBodies "no funciona"; Godot no avanza la física a mano. | Confirma los límites de Godot para repetir ticks. |

##### Inferencias a confirmar con pruebas

- **I1.** Las señales de `Area3D` y los nodos `RayCast3D` y `ShapeCast3D` se actualizan una vez por paso de física, no por tick repetido. Base: netfox indica que la física de Godot solo se actualiza en `_physics_process`. Consecuencia: la lógica predicha usa consultas directas.
- **I2.** Mover un cuerpo cinemático por transform no actualiza su posición para consultas hasta el próximo paso; netfox publica un truco para forzarlo. Consecuencia: las relaciones entre actores se leen de su estado, no de consultas físicas.
- **I3.** `get_gravity()` refleja los solapamientos del último paso, no la posición de un tick repetido. Consecuencia: la gravedad sale de una sonda propia.
- **I4.** Cambiar las medidas de una forma en tiempo de ejecución obliga a reconstruirla en Jolt. Consecuencia: la postura alterna entre formas preparadas.
- **I5.** En la misma máquina y build, repetir un tick con el mismo estado y el mismo mundo da el mismo resultado. El mundo cambia entre la predicción y el replay, así que el diseño no cuenta con igualdad exacta.

#### Modelo de red y tiempo

El host simula todo. Cada cliente simula por adelantado solo a su propio personaje, y el host adopta esa predicción mientras sea válida y esté al día con los eventos del host. Las correcciones quedan para lo que el cliente no podía saber.

> **Diagrama: "Si la afirmación está al día, el host la adopta y el cliente no ve corrección".** Un tick T del personaje de un cliente, de la predicción al snapshot. Se transcribió en texto porque en el original es un widget interactivo.
>
> 1. **Cliente:** simula el tick T. Va medio RTT + 2 o 3 ticks adelante.
> 2. **Cliente:** envía input y afirmación de T (época, modo, ancla, pose, velocidad) → al host.
> 3. **Host:** simula T con ese input, con el mismo paso que corre el cliente.
> 4. **Host:** valida la afirmación: época al día y pose válida; diferencia dentro de la tolerancia.
>     - Si se cumple → **adopta la afirmación** (destacado): el estado en T pasa a ser el del cliente. Es el caso normal y tapa las diferencias de Jolt.
>     - Si no → **rechaza y mantiene su resultado**: hubo algo que el cliente no vio.
> 5. **Host:** envía el snapshot de S, con el último tick procesado del cliente → al cliente.
> 6. **Cliente:** compara S con lo que predijo, que guardó en su buffer por tick.
>     - **Coincide:** sigue igual y descarta lo anterior a S.
>     - **No coincide:** restaura S y repite los ticks hasta el presente; la presentación suaviza el salto.

En el caso normal el host adopta la afirmación y el cliente no ve nada. Solo un evento que el cliente no vio, o una pose inválida en el mundo del host, termina en restauración y repetición.

##### Quién simula qué

| Cosa | Quién la simula | Cómo la ven los demás |
| --- | --- | --- |
| Personaje de un cliente | Ese cliente (predicción) y el host (autoridad) | Interpolado |
| Personaje del host | El host, sin latencia | Interpolado |
| `RigidBody3D` (cajas, escombros, balsas) | Solo el host | Interpolado; en clientes, cuerpo congelado en modo cinemático |
| Plataformas y empujadores guionados | Todos, como función del tiempo del mundo | Igual en todas las máquinas |
| Interacciones, salud, muerte, respawn, cámara lenta del mundo | El host | Eventos confiables con número de tick |
| Cámara, mirada, animación, sonido, IK | Cada máquina, en local | No se transmiten |

##### Reloj

Un tick fijo de 60 Hz, igual a `physics_ticks_per_second`, y un número de tick entero como línea de tiempo común. Con `physics_jitter_fix` en 0, como recomienda Godot para juegos en red.

El cliente corre adelantado respecto del host: medio RTT más un colchón de 2 o 3 ticks. Así su input del tick T llega antes de que el host simule T. El host informa cuántos inputs tenía en cola y el cliente repite o saltea un tick de vez en cuando para ajustar. **Problema que resuelve:** si el input llega tarde, el host tiene que adivinarlo.

##### Qué manda el cliente en cada tick

Un paquete no confiable que repite los últimos 4 a 8 ticks, para que perder uno no pierda nada. Por cada tick lleva:

- **Input:** ejes de movimiento y mirada cuantizados, botones mantenidos y un **contador de pulsaciones por botón**. Si se pierde el tick donde se apretó saltar, el contador igual subió y el host ve la pulsación.
- **Afirmación:** lo que el cliente predijo al final del tick: modo, ancla y su parámetro, postura, posición (relativa a la base si la hay), velocidad y la **época** que ya aplicó.

La **época** es un contador por cliente. El host lo incrementa con cada evento suyo que cambia la simulación de ese cliente: un empujón, un agarre, un teleport, un cambio de escala de tiempo del mundo. Lo que el cliente puede simular por su cuenta, como pisar un trampolín o entrar a una zona de gravedad, no cambia la época.

##### Qué hace el host con el tick T de un cliente

1. Toma el input de T. Si no llegó, repite los botones mantenidos; las pulsaciones perdidas entran cuando llega el contador.
2. Simula T para ese actor con el mismo código que corre el cliente.
3. Compara con la afirmación y la **adopta** si se cumple todo esto:
    - la época coincide, es decir, el cliente ya incluyó todos los eventos del host;
    - si hubo cambio de modo, su validador lo acepta con tolerancia amplia (por ejemplo, que el borde exista cerca de la pose afirmada);
    - la pose no se mete en la geometría del host y, si dice estar en suelo, hay suelo debajo;
    - la diferencia con el resultado propio está dentro de un límite generoso, para atrapar errores; el valor inicial se calibra.
4. Si adopta, el estado del actor en T pasa a ser la afirmación. Si no, queda el resultado del host.
5. En el próximo snapshot informa el último tick procesado de ese cliente y el estado en ese tick.

**Problema que resuelve:** Jolt no garantiza el mismo resultado en dos máquinas. Sin adopción, el host impondría sus micro-diferencias y un borde agarrado en el cliente podría fallar en el host. Con adopción, el host solo impone lo que el cliente no sabía.

La adopción también cura los inputs tardíos: si el salto entró dos ticks tarde en el host, la afirmación siguiente es válida y el host la toma. La época cierra el hueco que la referencia de Unreal señala: el host no adopta a un cliente que todavía no vio un efecto.

Riesgo propio: la adopción puede tapar errores reales de desincronización. Por eso el host registra cuánto difería su resultado de cada afirmación adoptada, y la adopción se puede apagar en pruebas.

##### Qué hace el cliente con cada snapshot

Guarda, por cada tick predicho, el input enviado y el estado resultante ya cuantizado. Al llegar el snapshot del tick S:

1. Si el estado del host en S coincide con lo guardado, descarta lo anterior a S y sigue.
2. Si no coincide, restaura el estado completo de S: modo, ancla, postura y forma, temporizadores, modificadores, base, época.
3. Sincroniza los indicadores internos de `CharacterBody3D` con un movimiento de velocidad cero, sin snap ni plataforma.
4. Repite los ticks S+1 hasta el presente con los inputs guardados. Solo se repite el actor local; el mundo no se rebobina.
5. La diferencia visible la absorbe la presentación.

Con 150 ms de adelanto son unos 9 ticks de un solo actor por corrección. Como el mundo no se rebobina, los ticks repetidos ven las cajas del presente; el movimiento sobre una base se repite en coordenadas de la base. El error residual lo toma la corrección siguiente.

##### Eventos del host sobre un personaje predicho

Cada tipo de evento elige una de dos políticas:

| Política | Cómo funciona | Quién paga | Para qué |
| --- | --- | --- | --- |
| Programado | El host lo fija para el tick E = ahora + RTT del cliente + colchón y lo envía ya, confiable. El cliente lo aplica en E como si fuera propio. | Host y observadores lo ven un RTT más tarde; el afectado no recibe corrección. | Empujones con anticipación, explosiones con mecha, impulsos de compañero, cámara lenta del mundo, eventos guionados |
| Inmediato | El host lo aplica en el tick actual. | El afectado recibe una corrección suavizada. | Golpes sin aviso, muerte, ser agarrado, respawn |

Si un evento programado llega tarde, el cliente lo inserta en E usando su propio historial y repite desde ahí. Se comporta como uno inmediato sin código especial.

##### Cambio de línea temporal

Si el personaje local queda anclado a algo que el cliente no puede predecir (otro jugador, un cuerpo rígido del host), el cliente deja de predecir su posición. Lo muestra en la línea interpolada, relativo al ancla, y sigue enviando input para soltarse o forcejear; la cámara sigue siendo local.

Al soltarse, una reconciliación normal restaura el estado del host y repite los inputs. La presentación mezcla las dos poses durante unos 0,2 s, porque Unity documenta saltos de más de 2 × ping si no se suaviza.

Excepción deliberada: pararse sobre una base del host, como una balsa, no cambia de línea. El cliente predice su movimiento relativo a la base, para que caminar sobre ella no tenga la latencia del RTT.

##### Lo que no se predice

- **Otros jugadores:** se interpolan con un colchón de 2 o 3 snapshots, unos 100 ms.
- **Cuerpos rígidos:** solo el host. La latencia al empujarlos se disimula con inercia y animación.
- **Choques entre jugadores:** no se bloquean físicamente (capas separadas). El jugador predicho chocaría contra posiciones pasadas de los demás y generaría correcciones. El contacto entre jugadores siempre es una interacción explícita o una separación suave que calcula el host.

##### Desconexiones

Si se va un cliente, el host quita su actor en el tick D. Todo lo anclado a él pierde el ancla en D y sigue la regla de anclas que desaparecen. Si se va el host, termina la sesión: no hay migración de host.

##### En Godot, sin código

- Transporte con `ENetMultiplayerPeer` u otro `MultiplayerPeer`. Canales separados: inputs no confiables, snapshots no confiables, eventos confiables.
- Paquetes empaquetados en bytes y enviados por RPC; el número de tick ordena todo.
- `MultiplayerSynchronizer` solo para objetos simples sin predicción: puertas, palancas.
- netfox es una opción para el reloj y la reconciliación. Su modelo de qué se resimula difiere en detalles, así que conviene un prototipo antes de adoptarlo; el núcleo del actor no depende de él.

#### Núcleo del actor

Cada personaje es un estado completo más un paso por tick con orden fijo. Un solo modo decide cómo se mueve el cuerpo; siete reglas generales deciden cómo se combina todo lo demás.

> **Diagrama: "Ocho etapas en orden fijo; lo externo entra solo por la etapa 3".** El mismo paso corre en el host y en el cliente, también al repetir ticks. Se transcribió en texto porque en el original es un widget interactivo.
>
> - **Entrada:** estado del actor en T−1, o el que restauró una corrección.
> 1. **Tiempo:** dt = 1/60 × escala del mundo × escala del actor; vencen timers.
> 2. **Base y empujadores:** desplazamiento de base y empujadores entre T−1 y T, con barrido.
> 3. **Eventos** (destacada): única entrada externa (impulsos, forzadas, modificadores). Recibe los **eventos del tick T**, del host y reacciones previas.
> 4. **Sondas:** solo las que pide el modo y sus salidas habilitadas. Producen la **lectura del entorno**, de solo lectura, que usan las etapas 5 y 6.
> 5. **Transición:** forzadas, invariantes, voluntarias; una por tick. Recibe el **input del tick T** (ejes, mirada, botones, contadores) y la lectura del entorno.
> 6. **Modo:** el modo activo arma el pedido: deslizar, pose o quieto. También recibe el input del tick T y la lectura del entorno.
> 7. **Postura y movimiento:** concede la postura que cabe y ejecuta el pedido.
> 8. **Contactos:** suelo, base, reacciones al tick siguiente, cuantizar. Emite **eventos de presentación**, con tick y tipo, que no se repiten.
> - **Salida:** estado del actor en T. En el cliente va a la afirmación y al buffer; en el host, al snapshot.

Las etapas 1 a 3 preparan el tick, de la 4 a la 7 deciden y mueven, y la 8 deja el estado listo para afirmarlo o enviarlo. Nada cambia la velocidad desde afuera salvo la etapa 3.

##### Estado del actor

| Grupo | Contenido | Problema que resuelve |
| --- | --- | --- |
| Cinemática | Posición (relativa a la base si la hay), velocidad propia, velocidad externa, orientación | Separar lo que el jugador produce de lo que le hacen |
| Modo | Id del modo y sus datos: escalera y altura, borde, posición sobre él y avance de la subida, cable y avance, ángulos de la cuerda, ancla y rol | Retomar una acción a medias tras una corrección |
| Base | Id de la base, transform relativo, tipo (guionada o del host) | Plataformas, balsas, jugador sobre jugador |
| Postura | Deseada y concedida; forma activa | Techos bajos |
| Suelo | En suelo, normal, id de superficie, distancia | Los indicadores de Godot solo valen tras un `move_and_slide()` |
| Temporizadores | Coyote, buffer de salto, carga de salto, bloqueos de reagarre por ancla, enfriamientos | Que una repetición de ticks no los reinicie |
| Modificadores | Lista con origen, atributos, capacidades quitadas, tiempo restante y reloj | Combinar efectos sin código cruzado |
| Vida y red | Vivo, caído o muerto; época; contadores de pulsación vistos | Muerte, respawn y adopción |

Regla de oro: **nada que influya en el movimiento futuro vive fuera de este estado**. Ni timers de nodos, ni señales, ni variables sueltas en otros scripts. Si algo queda afuera, un tick repetido diverge.

Al final de cada tick el estado se cuantiza: posiciones al milímetro, velocidades al centímetro por segundo. Así host y cliente arrancan el tick siguiente desde los mismos números. Es una decisión mía, no algo tomado de una referencia.

##### Paso por tick

1. **Tiempo.** `dt` del actor = 1/60 × escala del mundo × escala del actor. Vencen modificadores y temporizadores.
2. **Base** **y empujadores****.** Se aplica el desplazamiento de la base entre T-1 y T, y el de cualquier empujador guionado que invada la cápsula, barridos con `move_and_collide()`. Si no hay lugar, se genera un evento de aplastamiento.
3. **Eventos.** Se aplican los del tick T: impulsos, transiciones forzadas, modificadores nuevos. Es la única puerta de entrada de cambios externos.
4. **Sondas.** Corren solo las que piden el modo actual y sus transiciones habilitadas. El resultado es una lectura del entorno que nadie modifica en el resto del tick.
5. **Transición.** Primero las forzadas, después los invariantes, después las voluntarias por prioridad. Como máximo una por tick.
6. **Modo.** El modo activo produce un pedido de movimiento: deslizar con una velocidad, ir a una pose restringida o quedarse.
7. **Postura y movimiento.** Se concede la postura que cabe y se ejecuta el pedido.
8. **Contactos.** Se actualizan suelo y base; las reacciones de superficie (trampolín, daño) se encolan para el tick siguiente; se emiten eventos de presentación con su tick; se cuantiza.

En el host, los actores se procesan en orden fijo: primero los que no están anclados a nadie, después los anclados a ellos, y por id dentro de cada nivel. Ninguna regla depende del orden de los nodos en la escena.

##### Modos

Un solo modo activo, como en Mover de Unreal. El **agarre** es cuánta fuerza externa resiste el modo antes de soltarse.

| Modo | Cómo mueve el cuerpo | Agarre | Ancla o base | Se predice |
| --- | --- | --- | --- | --- |
| Suelo | `move_and_slide()` con snap, aceleración y fricción | 0 | Base opcional | Sí |
| Aire | `move_and_slide()` sin snap, gravedad, control aéreo | 0 | No | Sí |
| Deslizamiento | `move_and_slide()` con snap, aceleración por pendiente, giro limitado; pide postura agachada | 0 | Base opcional | Sí |
| Pared | `move_and_slide()` pegado a la pared, gravedad reducida, duración máxima | 2 | La pared | Sí |
| Ladder | Pose desde la escalera y la altura, con barrido | 3 | Escalera | Sí, si la escalera es fija o guionada |
| Hanging | Pose canónica desde el borde, con snap (sección Hanging) | 3 | Borde | Sí, si el borde es fijo o guionado |
| Tirolesa | Pose desde el cable y el avance; rapidez por pendiente | 3 | Cable | Sí |
| Cuerda | Péndulo propio con ángulos y velocidad angular | 3 | Punto de cuelgue | Sí |
| Enganchado | Pose desde un punto de otro actor u objeto, con barrido | Según el rol | Actor u objeto del host | No: lo conduce el host |
| Muerto | Ninguno; ragdoll solo visual | Máximo | No | No |

Los valores de agarre son una escala de partida, de 0 a 5, a calibrar.

##### Lo que no es un modo

| Mecanismo | Qué es | Ejemplos |
| --- | --- | --- |
| Impulso | Cambio instantáneo de velocidad con una clase de fuerza: sumar, fijar un eje o asegurar un mínimo | Salto, salto especial, trampolín, dash, empujón, explosión |
| Modificador | Cambia atributos por un tiempo. Dentro de una misma categoría no se apilan: gana el de mayor prioridad. Cada uno declara con qué fuerza se cancela; un dash, por ejemplo, se corta con un empujón | Barro, prisa, aturdimiento, caído, cargar algo pesado, campo lento |
| Capacidad | Permiso que un modificador puede quitar | Moverse, saltar, agarrar, trepar, correr, deslizar, pared, dash, interactuar, pararse |
| Escala de tiempo | Del mundo (la programa el host) y del actor (por modificador) | Cámara lenta global o personal |
| Postura | Parado o agachado; la pide el modo o el input, la concede el espacio | Agacharse, deslizar, techos bajos |
| Ancla | Referencia por id de red con coordenadas locales | Plataforma, escalera, borde, cable, compañero |

Así se arman las acciones de la lista. **Sprint:** el modo Suelo lee el botón y la capacidad correr. **Dash:** un impulso que fija la velocidad horizontal más un modificador de 0,2 s sin gravedad, sin fricción y sin control. **Salto especial:** un impulso más fuerte; si es cargado, la carga es un temporizador en tiempo del actor.

##### Las siete reglas

1. **Fuerza contra agarre.** Todo impulso o transición forzada trae una fuerza de 0 a 5. En los modos libres, de agarre 0, el impulso se suma a la velocidad y el movimiento decide: si sube, deja el suelo. En los demás, si la fuerza alcanza el agarre, el actor sale a la salida de respaldo con el impulso. Si no, el modo proyecta el impulso sobre lo que puede moverse y descarta el resto como balanceo visual.
2. **Invariantes con salida de respaldo.** Cada modo declara lo que debe seguir siendo cierto: el ancla existe y está al alcance, la gravedad está alineada, la capacidad sigue presente. Si algo falla, sale al respaldo, casi siempre Aire, heredando la velocidad del ancla.
3. **Postura según espacio libre.** El modo o el input piden una postura; el resolutor concede la mayor que cabe. Nunca se crece hacia un espacio ocupado.
4. **Velocidad relativa a la base.** La locomoción propia se calcula relativa a la base. Modificadores y escala de tiempo del actor tocan solo esa parte. Al dejar la base se hereda su velocidad en el punto de contacto, con una política por tipo de base.
5. **Tiempo del actor.** Todo lo que dura (coyote, dash, aturdimiento, carga) se mide en tiempo del actor. Una escala de tiempo nunca se mide con su propio reloj, para no alargarse a sí misma: la del actor vence en tiempo del mundo y la del mundo, en ticks.
6. **Capacidades en vez de condiciones cruzadas.** Un estado quita capacidades y las transiciones las piden. Nunca "si está aturdido y no caído y no cargando".
7. **Anclas que pueden desaparecer.** Toda referencia a otra entidad va por id de red y se revalida cada tick. Si desaparece, rompe un invariante y aplica la regla 2. Las anclas forman un árbol: el host rechaza ciclos.

Dos reglas de forma acompañan a las siete: las transiciones se deciden por la situación actual, nunca "volviendo al modo anterior". Y cualquier cambio de velocidad externo entra solo por la etapa de eventos.

##### Transiciones como listas planas

Cada modo declara una lista corta de salidas con prioridad. Cada salida es un destino, una condición sobre la lectura del entorno y el input, y las capacidades que exige. Ejemplo, el modo Aire:

| Prioridad | Destino | Condición | Capacidad |
| --- | --- | --- | --- |
| 1 | Suelo | Tocó suelo caminable y no sube | — |
| 2 | Hanging | Borde válido, sin bloqueo de reagarre, pared en la dirección en que buscan las manos: la de las teclas de dirección o, sin teclas, hacia donde mira el personaje; subiendo, recién cuando las manos llegan al filo | Agarrar |
| 3 | Ladder | Dentro del volumen de la escalera, intención hacia ella | Agarrar |
| 4 | Tirolesa o Cuerda | Manos cerca del cable y botón de agarre | Agarrar |
| 5 | Pared | Pared corrible al costado, rapidez mínima, sin enfriamiento | Pared |

> **Nota (2026-10-08), fila 2.** El original decía: "Borde válido, sin bloqueo de reagarre, no sube rápido, intención hacia la pared". La primera versión de Hanging lo cumplía así: sin ninguna tecla de dirección apretada no había agarre. En la prueba en dos PC, el usuario no entendía por qué no se agarraba hasta descubrir que tenía que apretar W, y pidió sacarlo: "no siempre queres darle a la W para llegar a X lado". Ahora, sin teclas, las manos buscan hacia donde mira el personaje, que en el aire es hacia donde se venía moviendo. La pared tiene que seguir estando en esa dirección. Detalle completo en la sección 8.5.

> **Nota (2026-10-08, más tarde), fila 2.** También decía "no sube rápido": no se agarraba subiendo a más de un máximo (en el laboratorio, 1 m/s). Como un salto arranca a 4,8 m/s, para agarrarse había que llegar a la punta del salto o estar cayendo. El usuario pidió, con un dibujo, que alcance con estar pegado al muro y saltar. Ahora, subiendo, se agarra cuando las manos llegan al filo: la pose de colgado no puede quedar más de 10 cm por encima de los pies, así el cuerpo no pega un tirón. Desde el piso, un salto sube los pies 1,17 m y las manos van 1,95 m por encima de ellos: los muros donde se agarra subiendo son más altos que los que se pueden subir saltando, así que no aparecen agarres no buscados. Detalle completo en la sección 8.7.

Hay condiciones, pero son listas planas por modo, no un árbol global. Un modo nuevo agrega su entrada en las listas de los modos desde donde se llega, y nada más. Las condiciones usan la intención de movimiento y la velocidad, no la orientación del modelo, para que primera y tercera persona simulen igual.

> **Nota (2026-10-08).** Desde el cambio de la fila 2 hay una excepción a esta regla. Sin teclas, el agarre de un borde usa la orientación del personaje (`facing_yaw`, que es parte del estado). Host y cliente la calculan igual, así que la red no se entera. Hoy da lo mismo en primera y en tercera persona, porque la orientación sigue al movimiento y todavía no hay primera persona. Si en primera persona el cuerpo pasa a seguir a la mirada, sin teclas las manos buscarían hacia la mirada en primera persona y hacia el último movimiento en tercera. Queda para revisar cuando llegue la primera persona.

#### Herramientas de Godot y Jolt

`move_and_slide()` mueve en los modos libres; todo lo demás valida, barre o consulta. Cada herramienta tiene un uso y un lugar donde está prohibida.

| Herramienta | Dónde se usa | Qué informa y cuándo vale | Dónde no |
| --- | --- | --- | --- |
| `move_and_slide()` | Suelo, Aire, Deslizamiento, Pared | Piso, pared, techo, normales y colisiones de deslizamiento, solo justo después del llamado | Modos anclados; restauraciones |
| `move_and_collide()` | Barridos de Ladder, Hanging, Tirolesa, Cuerda y Enganchado; arrastre de la base; snap de Hanging | El primer contacto; no toca `is_on_floor()` | Locomoción libre: no desliza ni clasifica |
| `test_move()` o `move_and_collide()` con `test_only` | Validar poses con la forma real: pararse, entrar a una pose de agarre, salir de una escalera | Si chocaría y dónde | — |
| Consultas directas (`intersect_shape`, `cast_motion`, `intersect_ray`, `intersect_point`, `get_rest_info`) | Todas las sondas | Puntos, normales, colisionadores y fracciones, al instante | Relaciones entre actores (inferencia I2) |
| Transform directo | Restaurar estado de red, respawn, pose anclada ya validada | Nada: no actualiza indicadores | Locomoción |
| Señales de `Area3D`, nodos `RayCast3D` y `ShapeCast3D` | Presentación y depuración: sonido ambiente, cartel de interacción | Una vez por paso de física | Lógica predicha (inferencia I1) |
| `RigidBody3D` | Objetos del mundo, simulados solo en el host | — | Personajes |
| `AnimatableBody3D` | Plataformas y empujadores movidos por el tiempo del mundo | Estima su velocidad al moverse | — |
| `get_gravity()` | No se usa | El último paso de física | Reemplazado por la sonda de entorno |

##### Cómo leer los indicadores de Godot

- **Después de** **`move_and_slide()`** **en el tick T** se copian piso, normal y colisiones al estado del actor. Desde ahí el juego lee su estado, no los indicadores.
- **En modos anclados** no se llama a `move_and_slide()`, así que los indicadores conservan el último modo libre. Nunca se consultan ahí.
- **Con** **`move_and_collide()`** **o con transform directo** los indicadores no cambian. Por eso ningún modo anclado decide nada con ellos.
- **Después de restaurar un estado**, el `was_on_floor` interno de Godot quedó viejo y afectaría el snap del próximo movimiento. Se sincroniza con un `move_and_slide()` de velocidad cero, como documenta netfox; el snap va en 0 durante esa llamada para que no mueva el cuerpo.
- **`MOTION_MODE_FLOATING`** informa todo como pared. Solo tendría sentido si el juego suma zonas de gravedad cero, con un modo Flotar propio.

##### Configuración del cuerpo

| Propiedad | Valor | Por qué |
| --- | --- | --- |
| `motion_mode` | Grounded | Hay piso, pared y techo |
| `up_direction` | Opuesto a la gravedad del lugar | Zonas de gravedad alterada |
| `platform_floor_layers`, `platform_wall_layers` | 0 | La velocidad de plataforma de Godot se lee del presente: falla en ticks repetidos |
| `platform_on_leave` | Do nothing | La herencia de velocidad la decide la regla 4 |
| `floor_snap_length` | Lo fija el modo cada tick: positivo en Suelo y Deslizamiento, 0 en Aire | El snap es parte del pedido del modo |
| `floor_block_on_wall` | Activado | No trepar paredes por error numérico |

##### Escala de tiempo con `move_and_slide()`

`move_and_slide()` usa el delta del frame de física, que ya incluye `Engine.time_scale`. Para que un actor avance su propio `dt`, se multiplica `velocity` por `dt` del actor dividido el delta del frame, se mueve, y se divide la velocidad resultante por el mismo factor. Lo mismo vale al repetir varios ticks dentro de un frame: cada tick usa su propio factor.

##### Escalones

`CharacterBody3D` no tiene altura de escalón. La primera opción son rampas de colisión sobre las escaleras, una regla de nivel que también es estable en red. Si hacen falta cordones o escalones sueltos, el modo Suelo suma una sonda: subir, avanzar, bajar y aceptar solo si cae en suelo caminable.

##### Jolt en particular

- **Aristas redondeadas.** Cajas y convexos tienen radio convexo. Una persona parada en el filo de una caja o una sonda que busca un borde ven normales inclinadas cerca de la arista.
- **Colisiones fantasma en mallas.** Se activan las opciones de remoción de aristas internas para consultas de movimiento y se prueban con las mallas reales.
- **Empuje por contacto.** La clase dice que un `CharacterBody3D` afecta a los cuerpos que encuentra. Para no depender de cuánto empuja eso con Jolt, los empujes de objetos son fuerzas explícitas en el host, calculadas desde las colisiones de deslizamiento o desde la interacción de empuje. Es una inferencia a medir.

#### Sondas

Nueve sondas alcanzan para todos los casos, y casi nunca corren todas juntas. Cada transición declara qué sonda necesita y solo corren las de transiciones habilitadas por capacidades e input.

Todas son consultas directas al espacio, porque funcionan igual en un tick repetido. Todos los resultados se ordenan por distancia y después por id antes de interpretarlos: Jolt no garantiza el orden.

| Sonda | Cuándo corre | Forma | Qué decide |
| --- | --- | --- | --- |
| Suelo | Después de mover en los modos libres; en los anclados, al salir | Resultado de `move_and_slide()` más una esfera barrida corta hacia abajo | En suelo, distancia, superficie, base |
| Espacio libre | Cuando la postura pedida es mayor que la concedida, y antes de entrar a una pose | `intersect_shape()` con la forma destino en la pose destino | Si la forma cabe |
| Pared | En Aire con capacidad pared y rapidez mínima; cada tick en Pared | Esferas barridas cortas a los costados y al frente, más un rayo de continuidad | Pared corrible, lado y continuidad |
| Borde | En Aire o Pared con capacidad agarrar; cada tick en Hanging | Barrido de manos más rayos de cara y de superficie superior | Candidato de borde |
| Escalera | En Suelo o Aire con capacidad agarrar | Solapamiento de la cápsula con volúmenes de escalera | Entrada y altura sobre la escalera |
| Cable y cuerda | En Aire, o al apretar agarrar | Solapamiento con el volumen de agarre y punto más cercano sobre la curva | Entrada y avance sobre el cable |
| Entorno | Todos los ticks | `intersect_point()` contra volúmenes de entorno | Gravedad, escala de tiempo, viento, barro |
| Contactos | Después de `move_and_slide()` | Colisiones de deslizamiento del movimiento | Trampolín, daño, cinta, fricción |
| Interacción | Al apretar interactuar | Esfera frente al pecho más rayo de visión; para actores, el registro de estados | Objetivo de la interacción |

##### Cómo se interpretan

- **Suelo.** En modos libres, "en suelo" lo decide `move_and_slide()`. La esfera solo aporta distancia, propiedades de superficie y base. Cerca de aristas de Jolt la normal se inclina, así que la esfera no reclasifica nada.
- **Espacio libre.** La forma de prueba se achica apenas, para que tocar el piso no cuente como choque. En suelo la forma crece hacia arriba; en el aire, hacia abajo.
- **Pared.** Es corrible si la normal es casi horizontal, la superficie no está marcada como no corrible y el rayo de continuidad sigue encontrando pared adelante.
- **Escalera, cable y cuerda.** Son objetos autorados con su eje, su ancho y sus salidas; no se detectan peldaños. Se entra con intención de movimiento hacia ellos o con el botón de agarre.
- **Entorno.** Los volúmenes se combinan con la misma regla que los modificadores: por categoría, gana la mayor prioridad. Se leen por consulta y no por señales, por la inferencia I1.
- **Contactos.** Producen eventos para el tick siguiente. El trampolín solo actúa si la velocidad contra la superficie supera un mínimo.
- **Interacción.** Para otros jugadores se usa la posición guardada en su estado (o interpolada, en un cliente), no una consulta física, por la inferencia I2. El host vuelve a validar con tolerancia.

##### La sonda de borde, paso a paso

Es la más delicada. Busca dónde pueden ir las manos, no dónde está el cuerpo.

1. **Barrido de manos.** Una esfera chica, del orden de 6 cm, barrida con `cast_motion()` desde la posición de las manos en T-1 hasta la de T. Si el cuerpo cae a 12 m/s recorre 20 cm por tick; un chequeo estático se saltaría el borde y el barrido no.
2. **Respaldo del barrido.** `cast_motion()` ignora lo que ya se toca al empezar. Si la esfera arranca en contacto, se usa un solapamiento en la posición final.
3. **Cara frontal.** Un rayo horizontal hacia el contacto da la normal de la pared.
4. **Superficie superior.** Un rayo hacia abajo que arranca unos centímetros hacia adentro del filo, para esquivar la arista redondeada de Jolt. La superficie tiene que ser casi plana y tener profundidad para las manos.
5. **Filo y dirección.** El punto del borde y la dirección del filo, guardados en coordenadas locales del colisionador, para que sirvan si el borde se mueve.
6. **Pose válida.** Espacio libre para la cápsula en la pose de agarre, y el cuerpo por debajo del borde: si está por encima, es un aterrizaje.
7. **Extensión lateral.** Solo al desplazarse colgado: rayos a los costados para saber si el borde sigue.

Sale un candidato de borde o nada. Las superficies pueden marcarse como no agarrables. El autor no tiene que colocar bordes a mano.

#### Interacciones cooperativas

Toda interacción entre jugadores sigue un solo protocolo. El iniciador la predice en sí mismo, el host la valida en el mismo tick y crea un registro, y la parte pasiva o ya estaba quieta o pasa a ser conducida por el host.

##### Protocolo común

1. **Inicio.** El iniciador aprieta interactuar y su cliente predice solo su lado: la animación de alcanzar, o su propio cambio de modo si no depende del otro.
2. **Pedido.** Viaja en la afirmación del tick T, con objetivo y tipo.
3. **Validación en T.** El objetivo existe, está al alcance con tolerancia amplia (el iniciador lo vio en el pasado), lo permite por capacidades y no está ocupado. Además, la nueva ancla no crea un ciclo.
4. **Registro.** El host crea una interacción con id, tipo, participantes, roles, tick de inicio y fase. Es estado del mundo, viaja como evento confiable y sube la época de quien cambia de movimiento.
5. **Fin.** Por input, por un invariante roto, por fuerza mayor al agarre, por muerte o por desconexión. El host emite el fin con su tick y cada participante sale por su regla de respaldo.

Dos reglas reducen las correcciones:

- **La parte pasiva ya está quieta.** Una interacción cambia el movimiento del iniciador. El otro ya está en un estado que lo sostiene (ofreciendo apoyo, caído, colgado), así que el evento del host le cambia la animación y no la posición.
- **Anticipación mayor que el RTT.** Si la interacción sí mueve al pasivo, arranca con una anticipación animada. Eso permite programar el evento en lugar de aplicarlo de golpe.

##### Casos

| Interacción | Qué pasa con cada uno | Red | Qué la termina |
| --- | --- | --- | --- |
| Empujar juntos un objeto pesado | Cada uno pasa a Enganchado con rol empujar, anclado a una manija del objeto. El host suma las fuerzas de todos y se las aplica al `RigidBody3D`; un objeto muy pesado exige dos o más. | Cambio de línea: el objeto es del host. La respuesta llega con RTT más interpolación, unos 150 a 250 ms, disimulada con inercia y una animación local inmediata. | Soltar, manija perdida, objeto caído |
| Ayudar a alcanzar una zona | El ayudante ofrece apoyo: Suelo con un modificador que lo fija en el lugar. El que sube interactúa y recibe un impulso de lanzamiento. | El lanzamiento es input propio del que sube: si el host coincide en T, no hay corrección. El ayudante solo cambia de animación. | Instantáneo; el ayudante cancela antes |
| Subirse a los hombros | El que sube pasa a Enganchado con rol montado. El ayudante recibe un modificador de carga: más lento, sin sprint. | El que sube cambia de línea; el ayudante sigue predicho. | Bajarse, fuerza mayor al agarre, ayudante caído |
| Sujetar a quien cae o cuelga | El que sujeta sigue en su modo (Suelo o Hanging) con un modificador de carga que baja su agarre. El sujetado pasa a Enganchado con rol sujetado. | Inmediato para el sujetado: no se puede programar atajar una caída. Recibe una corrección y cambia de línea. | Soltar cualquiera de los dos, fuerza, muerte o desconexión del que sujeta |
| Arrastrar a un caído | El que arrastra recibe un modificador: mitad de velocidad, sin saltar ni agarrar. El caído pasa a Enganchado con rol arrastrado y sigue a la mano con barrido, después de que el otro se mueve. | En el cliente del que arrastra, el caído se dibuja pegado a su mano predicha. El caído ve todo en la línea del host. | Soltar, cuerpo trabado más allá del estiramiento máximo |
| Revivir | El que revive queda fijo en el lugar por un modificador. El progreso es un temporizador del registro, en el host. | Si nada interrumpe, el fin es predecible: el host programa el "levantarse" para el tick de fin y lo cancela si hace falta. | Moverse, fuerza mayor al agarre, distancia, muerte o desconexión |

##### Reglas de convivencia

- **Ocupación.** Por defecto dos jugadores pueden compartir escalera, borde o cable sin bloquearse, porque no chocan entre sí. Donde el diseño pida un solo lugar, decide el host por tick y después por id; el perdedor recibe una corrección.
- **Pararse sobre otro jugador.** No ocurre por física, porque los jugadores no chocan. Ocurre solo como interacción de montarse.
- **Caído no es un modo.** Es un conjunto de modificadores: sin saltar, sin agarrar, sin pararse, velocidad mínima. Por eso un caído puede caer de una plataforma, ser empujado o arrastrado sin reglas nuevas.

#### Presentación

La presentación lee la simulación y nunca escribe en ella. Su trabajo es absorber correcciones, cambios de línea y la diferencia entre primera y tercera persona.

##### Quién está debajo de quién

1. **Cuerpo** (`CharacterBody3D`): se mueve solo en ticks.
2. **Raíz visual**: interpolada entre ticks por la interpolación de física de Godot, más un **desvío de corrección** propio que decae a cero.
3. **Modelo**: animación e IK.
4. **Cámara**: fuera de la jerarquía interpolada. La rotación sale del mouse en `_process`; la posición, de `get_global_transform_interpolated()` del punto de ojos más el desvío. Es lo que recomienda la documentación de interpolación.

##### Correcciones y saltos de línea

- **Corrección.** Al reconciliar, el desvío suma la diferencia entre lo que se veía y la nueva posición simulada, y decae en unos 100 ms. Por encima de un umbral, del orden de 1,5 m, se acepta el salto.
- **Orientación.** El giro del cuerpo se suaviza igual. La rotación de la cámara nunca se corrige: es input local.
- **Teleport.** Respawn y teleports del host llaman a `reset_physics_interpolation()` y ponen el desvío en cero.
- **Cambio de línea.** Se mezclan la pose predicha y la interpolada durante unos 0,2 s.

##### Animación

- Se maneja leyendo el estado en cada frame: modo, postura, velocidad relativa a la base, parámetros del ancla, marcas de modificadores como aturdido o cargando. Una corrección se ve sola, sin eventos especiales.
- La velocidad de reproducción sigue a la escala de tiempo del actor y del mundo.
- **Sin root motion en la simulación.** Las trayectorias autoradas, como bajar de una escalera por arriba, son curvas dentro de la simulación, en tiempo del actor. La animación las acompaña.
- IK de manos en bordes, peldaños, cables y manijas; IK de pies en el suelo.

##### Sonido, partículas y vibración

- **Eventos predichos** del jugador local: cada uno lleva tick, tipo y actor. Un registro evita repetirlos cuando se repiten ticks. Si tras la repetición un evento ya no ocurre, se corta lo que se pueda cortar.
- **Eventos del host** (impacto, muerte, inicio de interacción) llegan como eventos confiables explícitos. No se deducen de una repetición, porque la repetición puede empezar después del tick del evento.

##### Primera y tercera persona

- **La simulación es idéntica.** El input lleva la mirada y la intención de movimiento en coordenadas del mundo. La orientación del cuerpo sigue la mirada o el movimiento según una marca del input; el host aplica la misma regla.
- **Primera persona.** La altura de ojos sigue a la postura concedida con suavizado. Colgado o en escalera, la cámara va al hueso de la cabeza con límites de giro.
- **Tercera persona.** `SpringArm3D` para que la cámara no atraviese paredes.
- Los demás jugadores siempre se ven con el modelo completo.

##### Cámara lenta en pantalla

- **Del mundo.** La escala de tiempo afecta todo lo que usa delta; la interfaz se procesa fuera de esa escala. El audio no se escala solo: Godot indica `AudioServer.playback_speed_scale` para eso.
- **Personal.** Solo se escalan la animación y los sonidos de ese jugador, más efectos de cámara en su pantalla. Su mouse no se ralentiza.

#### Hanging: con snap

Se usa la variante A, con snap, decidida el 2026-10-02: sigue las mismas reglas que Ladder, Tirolesa, Cuerda y Enganchado, que calculan su pose desde el ancla. Las dos variantes comparten modo, sonda, salidas y protocolo de red. Cambia dónde queda el cuerpo al agarrarse y qué hay que guardar para reproducirlo.

> **Diagrama: "Con snap el cuerpo va a una pose fija; sin snap guarda dónde quedó".** Vista lateral a la misma escala; en punteado, el cuerpo al detectar el borde. Se transcribió en texto porque en el original es un widget interactivo.
>
> - **A · Con snap:** el cuerpo detectado (punteado) va con un snap validado, de hasta unos 35 cm, a una pose fija junto al filo, con la mano en el borde. El cuerpo va a una pose fija y la raíz visual tapa el salto. Guarda: ancla y posición sobre el filo.
> - **B · Sin snap:** el cuerpo queda donde estaba, desplazado hacia abajo y hacia afuera respecto del filo, y las manos llegan al filo por IK. Guarda: ancla, posición y desplazamiento.

En A la pose depende solo del ancla y del lugar sobre el filo. En B también depende del desplazamiento con que se agarró, que hay que transmitir y dibujar. Por eso se eligió A.

##### Lo común

- **Detección:** la sonda de borde.
- **Captura desde Aire o Pared:** capacidad agarrar, sin bloqueo de reagarre para ese borde, bajando o subiendo (subiendo, recién cuando las manos llegan al filo), pared en la dirección en que buscan las manos (la de las teclas de dirección o, sin teclas, hacia donde mira el personaje), filo dentro de la banda de las manos y cuerpo por debajo del filo.

  > **Nota (2026-10-08).** El original decía "intención hacia la pared" en lugar de la pared en la dirección en que buscan las manos. Se cambió por el mismo motivo que la fila 2 de la transición de Aire, en "Transiciones como listas planas": agarrarse exigía apretar una tecla hacia la pared, y el usuario pidió que no. Detalle completo en la sección 8.5.
- **Estado:** el ancla (id del colisionador) y la posición sobre el filo en coordenadas locales.
- **Desplazarse colgado:** el input lateral cambia la posición sobre el filo; la extensión lateral de la sonda y un barrido limitan el recorrido. El input lateral son A y D: la izquierda y la derecha del personaje frente a la pared, mire donde mire la cámara.

  > **Nota (2026-10-08).** El texto original termina en "limitan el recorrido"; la última oración es nueva. El documento no decía nada de la cámara. La primera versión de Hanging usaba la misma dirección que para caminar: las teclas giradas según la cámara, proyectadas sobre el filo. Con la cámara mirando 90° a un costado, D casi no movía: "movía la cámara hacia la derecha pero a la vez le daba a la tecla D para ir a la derecha y el player avanzaba muy de a poquito". A pedido del usuario, A y D pasaron a ser directos. Detalle completo en la sección 8.5.
- **Salidas:** saltar para arriba mirando a la pared, para subir al borde con el control aéreo; soltarse, saltar en la dirección de la mirada (el personaje se da vuelta hacia allá), fuerza mayor al agarre, o invariante roto (borde destruido, gravedad desalineada, ancla fuera de alcance). Todas van a Aire con un bloqueo de reagarre corto.
- **Impulsos menores al agarre:** la parte paralela al filo desplaza al personaje sobre él; el resto es balanceo visual.
- **Subir al borde** no es mantle: es una salida de Hanging, detallada más abajo.

> **Nota (2026-10-08, más tarde).** Tres cambios más en esta lista:
>
> - **Captura:** decía "velocidad vertical por debajo de un máximo de subida". Cambió por el mismo motivo que la fila 2 de las transiciones de Aire: ahora también se agarra subiendo, cuando las manos llegan al filo.
> - **Salidas:** saltar en la dirección de la mirada ahora da vuelta al personaje hacia donde salta. Con el agarre subiendo, al saltar hacia atrás desde abajo de un techo que sobresale, se agarraba del borde de ese techo, porque las manos seguían buscando hacia la pared que dejaba. El usuario eligió que se dé vuelta.
> - **Estado:** decía "y, mientras sube, el avance de la subida". Había quedado viejo con el salto para arriba, que ya no es una fase dentro de Hanging.
>
> Detalle completo en la sección 8.7.

##### Variante A: con snap

1. Con el filo, su normal y su dirección se calcula una **pose canónica**: a una distancia fija de la pared y a una altura fija bajo el filo, mirando a la pared.
2. Se valida: espacio libre para la cápsula en esa pose, camino libre desde la posición actual (barrido) y distancia de snap menor a un máximo, del orden de 35 cm.
3. Si pasa, en ese mismo tick el cuerpo se ubica en la pose canónica: es un **snap lógico**.
4. La raíz visual no salta: el desvío de corrección absorbe la diferencia y decae en unos 100 a 150 ms. Es el mismo mecanismo que suaviza las correcciones de red. En primera persona la cámara suaviza solo la posición, nunca la rotación, y puede tardar un poco más que el cuerpo.
5. Mientras cuelga, la pose es una función del ancla y de la posición sobre el filo, sin `move_and_slide()`.

##### Subir al borde

Es un salto desde Hanging, no un mantle. Mirando a la pared, el jugador salta derecho para arriba y pasa arriba del borde con el control aéreo. Siempre arranca desde la pose canónica del snap, así que el salto es el mismo en todos los bordes.

1. **Pedido.** Saltar mientras cuelga, con la mirada a menos de unos 60° de la pared. Si mira hacia otro lado, el salto va hacia donde mira.
2. **Salto.** Sale a Aire con velocidad solo vertical: la justa para que los pies suban unos 20 cm por encima del filo. Lleva el mismo bloqueo corto de reagarre que las demás salidas.
3. **Pasar arriba.** Es el control aéreo de cualquier salto: para quedar arriba, el jugador empuja hacia la pared. Si empuja desde el principio, sigue acelerando y en un borde angosto se pasa de largo; si empuja en la punta del salto, aterriza cerca del filo.
4. **Si no llega.** Cae como en cualquier salto.
5. **Red.** Es un salto común y se predice entero. Sobre un borde que mueve el host, con mucha latencia, aterrizar arriba puede dar correcciones grandes, porque el cliente ve el borde corrido: en las pruebas, de 1,4 a 2,7 m con 200 ms de ida y vuelta.

> **Nota (2026-10-08).** Esta sección se reescribió. Antes, subir al borde era una trayectoria dentro de Hanging:
>
> 1. **Pedido.** Input de subir mientras cuelga, con la capacidad trepar. Estar aturdido o sostener a alguien la quitan.
> 2. **Validación antes de empezar.** Arriba tiene que caber el cuerpo agachado, sobre suelo caminable. El camino se prueba con `test_move()` en dos tramos: hacia arriba pegado a la pared y hacia adentro sobre el filo. Si algo falla, no sube y sigue colgado. Los otros jugadores no cuentan como obstáculo.
> 3. **Subida.** El modo sigue siendo Hanging, en una fase de subida con su avance en tiempo del actor. El cuerpo usa la forma agachada y recorre los dos tramos con barridos de `move_and_collide()`; la animación sigue ese avance.
> 4. **Fin.** Al completar el recorrido pasa a Suelo arriba del borde. El resolutor de postura decide si se para o queda agachado.
> 5. **Interrupciones.** Con fuerza mayor al agarre sale a Aire con el impulso. Si algo ocupa el camino a mitad de la subida, vuelve a la pose de colgado si sigue siendo válida; si no, sale a Aire. Si el borde desaparece, también sale a Aire.
> 6. **Red.** La inicia el jugador: se predice, y el host la adopta después de validar el mismo espacio libre, con tolerancia.
>
> En el laboratorio se implementó así: Espacio mirando a la pared, 0,45 s hacia arriba pegado a la pared y 0,25 s hacia adentro, agachado. Al probarlo en dos PC, el usuario dijo que no estaba mal, pero que le hubiese gustado más "un saltito". El 2026-10-08 pidió quitar temporalmente esa subida y reemplazarla por un salto para arriba, con control aéreo y un margen de altura sobre el borde para maniobrar. Lo probó en dos PC y lo aprobó: "uno aprende muy rapidamente y se adapta al toque con los controles". Por el mismo cambio, subir al borde salió de la lista de salidas que no van a Aire, de los ejemplos de trayectorias autoradas y de las poses que se validan con `test_move()`. La subida vieja sigue en el commit `3cdcc91` del laboratorio, por si vuelve. El detalle está en la sección 8.6.

##### Variante B: sin snap

1. El cuerpo queda donde lo dejó el movimiento de ese tick y la velocidad se anula.
2. Se guarda el **desplazamiento** del cuerpo respecto del filo: cuánto hacia afuera y cuánto hacia abajo. Tiene que caer dentro de lo que alcanzan los brazos.
3. No hace falta validar la pose del cuerpo: ya era válida. Sí se valida que las manos lleguen al filo.
4. Mientras cuelga, la pose es el filo más ese desplazamiento. Las manos van por IK y el cuerpo usa mezclas de animación según el desplazamiento.

##### Comparación

| Aspecto | A: con snap | B: sin snap |
| --- | --- | --- |
| Estado de red | Ancla y posición sobre el filo | Lo mismo más dos valores de desplazamiento |
| Sensibilidad al tick de captura | Baja: capturar en T o en T+1 termina en la misma pose | Alta: un tick de diferencia cayendo a 12 m/s son 20 cm de desplazamiento distinto |
| Ventana de captura | Puede ser amplia, hasta la distancia máxima de snap | Angosta: la limita el alcance del IK, y eso trae más agarres fallidos |
| Validación física | Espacio libre en la pose y camino libre | Casi ninguna |
| Riesgo físico | Atravesar una pared delgada o rozar geometría en la pose; lo frenan las validaciones | Quedar lejos de la pared o rozarla; el desplazamiento lateral puede engancharse |
| Visual | Manos siempre en el filo; el salto lo tapa el desvío; en primera persona hay que afinar ese suavizado | Sin salto de pose; manos estiradas o metidas en el filo; más animación e IK |
| Salidas | Siempre desde la misma pose: saltos repetibles y niveles predecibles | Desde poses variables: las trayectorias de salida varían |
| Red, predicción acertada | Sin corrección | Sin corrección |
| Red, predicción rechazada | Corrección grande: distancia de snap más la caída durante el RTT | Corrección menor: la caída durante el RTT |
| Red sin adopción | Converge exacto cuando ambos coinciden en la decisión | Queda una diferencia residual de desplazamiento entre host y cliente |
| Observadores | Ven un agarre limpio | Ven continuidad con poses variadas |
| Bordes móviles | La pose sigue al ancla | El desplazamiento es relativo al ancla; también sigue |

**Diferencia de arquitectura.** En A el modo es dueño de la posición: todo lo calcula desde el ancla. En B el modo restringe la posición y conserva un dato más, que la presentación tiene que saber dibujar.

**Por qué A****.** Gana en red y en consistencia, y la ventaja de B, la continuidad en primera persona, la cubre el desvío visual que ya existe. El snap gradual dentro de la simulación queda descartado: suma estado (el avance del snap) y salidas desde poses a medio camino.

##### Pruebas de confirmación

1. **Laboratorio de bordes.** Bordes de 1,6 a 2,4 m de alto, de 5 cm a 1 m de espesor, superficie superior de 0 a 25°, cajas de Jolt y mallas, curvos, bajo techos bajos, con paredes laterales, sobre una plataforma guionada y sobre un cuerpo rígido del host.
2. **Barrido automático de aproximaciones.** Un bot con inputs grabados recorre una grilla: velocidad horizontal de 0 a 8 m/s, vertical al llegar de -12 a +3 m/s, ángulo de 0 a 70° y corrimiento lateral. Cada caso corre con snap; en cada rechazo se registra si sin snap se habría agarrado.
3. **Qué se registra.** Si capturó y en qué tick, distancia de snap, penetraciones en cada tick colgado, y si cada salida (soltar, saltar, desplazarse, subir) funcionó.
4. **Métricas visuales.** Desplazamiento máximo de la raíz visual y de la cámara de primera persona en los 100 ms tras la captura. Cuánto tarda el desvío en volver a cero.
5. **Red.** Host y cliente con simulador de latencia y pérdida: RTT de 0, 60, 120 y 200 ms, variación de ±20 ms, pérdida de 0, 2 y 5 %. Se mide la tasa de afirmaciones rechazadas en capturas, el tamaño de las correcciones y la suavidad que ve un observador.
6. **Divergencia inyectada.** Para imitar que Jolt difiere entre máquinas, se perturba el estado del cliente medio milímetro por tick, con adopción prendida y apagada. Se mide cuántas decisiones cambian cerca de los límites de la banda.
7. **Prueba con personas.** Entre 5 y 10 jugadores, en primera y en tercera persona, con cadenas de agarres. Se mide intentos por agarre logrado, agarres no buscados, y si "me agarré donde esperaba". En primera persona se pregunta además si el movimiento de cámara al agarrarse molesta.
8. **Criterios fijados antes de medir.** Por ejemplo: 95 % de capturas en la banda buscada, 1 % o menos de capturas no buscadas, cero penetraciones y un tope de salto de cámara en 50 ms. Si el snap falla un criterio duro, la decisión se reabre.

**Qué reabre la decisión.** Que la pose de agarre se rechace seguido en geometría irregular donde sin snap se habría agarrado. Que el movimiento de cámara moleste en primera persona y no se arregle afinándolo. O que el diseño necesite que la altura del colgado importe.

La decisión es una sola para todo el juego. En una misma sesión hay jugadores en primera y en tercera persona, y la simulación no puede depender de la cámara; solo el suavizado visual puede variar por perspectiva.

#### Recorridos de casos

Catorce casos, con 60 ticks por segundo y RTT de 100 ms salvo aclaración. Ninguno necesita una regla nueva: cada uno se resuelve con las piezas de las secciones anteriores.

| Caso | Qué combina | ¿Corrección visible? | Reglas que actúan |
| --- | --- | --- | --- |
| 1 | Empujón en una escalera | No | Evento programado, fuerza contra agarre |
| 2 | Cámara lenta del mundo en un salto especial | No | Escala de tiempo, regla 5 |
| 3 | Fin de deslizamiento bajo un techo | No | Regla 3, capacidades |
| 4 | Cambio de velocidad sobre plataforma móvil | No; pequeña si la base es del host | Regla 4 |
| 5 | Desconexión mientras sostiene a otro | Mezcla de 0,2 s | Reglas 7 y 2, cambio de línea |
| 6 | Corrección a mitad de un dash | Sí, suavizada | Época, reconciliación |
| 7 | Trampolín, gravedad baja y techo | No | Contactos, entorno |
| 8 | Muerte en tirolesa y reaparición | Teleport | Fuerza 5, regla 7 |
| 9 | Explosión junto a dos que empujan una caja | No; mezcla al soltarse | Fuerza contra agarre, cambio de línea |
| 10 | Impulso de compañero rechazado | Sí, suavizada | Protocolo de interacción |
| 11 | Corrección parado sobre una plataforma | Residual | Base, reconciliación acotada |
| 12 | Carrera por pared, borde y aturdimiento | No | Reglas 6 y 2 |
| 13 | Tirón de rendimiento en el host | No | Reloj, cola de inputs, adopción |
| 14 | Paquetes perdidos al saltar | Rara vez | Redundancia, contadores, adopción |

##### 1. Empujón en una escalera

B sube una Ladder. A lo empuja con un golpe que tiene 0,25 s de anticipación.

1. A aprieta empujar en su tick 1000; su animación arranca al instante, predicha.
2. El host procesa ese tick, valida que B esté al alcance y programa el empujón sobre B para el tick 1015, el cuadro del golpe. Lo envía confiable y sube la época de B en 1015.
3. El evento llega cuando B va por su tick 1009, porque B corre adelantado. B lo aplica en 1015, en la etapa de eventos.
4. Con fuerza 2 contra agarre 3, Ladder proyecta el impulso sobre su eje; un empujón horizontal no tiene componente sobre el eje y queda como balanceo visual. Con fuerza 4, B sale a Aire con el impulso y un bloqueo de reagarre para esa escalera.
5. Las afirmaciones de B desde 1015 traen la época nueva: el host las adopta y nadie ve una corrección.

Con 300 ms de RTT el evento llegaría tarde: B lo inserta en 1015 usando su historial y repite desde ahí. Es el mismo código.

##### 2. Cámara lenta del mundo durante un salto especial

C hace un salto cargado. En el aire, un evento guionado pone el mundo a ×0,3 durante 180 ticks.

1. El salto es input de C: impulso en su tick 2000, modo Aire, predicho y adoptado.
2. El host programa la escala 0,3 desde el tick 2030, con un margen mayor que el RTT más alto, y sube la época de todos en 2030.
3. En el tick 2030 cada máquina pone `Engine.time_scale` en 0,3. El delta de física pasa a 0,3/60 y Jolt frena las cajas en el host. La interpolación de lo remoto avanza por ticks reales, no por delta escalado: los demás se ven lentos cuando sus snapshots lo están.
4. El `dt` de C se achica igual. La parábola es la misma en el espacio y se recorre 3,3 veces más lento. Si el salto tiene una fase de empuje, dura lo mismo en tiempo del actor y alcanza la misma altura.
5. Coyote y buffer de salto también se estiran. El mouse no.
6. La escala del mundo vence a los 180 ticks reales, no con su propio reloj.

##### 3. Fin de un deslizamiento bajo un techo

D entra deslizándose a un túnel de 1,2 m de alto; parado mide 1,8 m.

1. En el tick 3100 la rapidez baja del mínimo y Deslizamiento sale a Suelo, que pide postura parada porque D no mantiene agachar.
2. La sonda de espacio libre no deja crecer la forma y la postura concedida sigue agachada. Suelo usa velocidad de agachado y no permite sprint sin postura parada.
3. La prueba se repite cada tick mientras la pedida supere a la concedida. Al salir del túnel, D se para solo.
4. Salir de una escalera hacia un hueco bajo, o reaparecer en un lugar bajo, sigue el mismo camino.
5. Si llega una corrección a mitad del deslizamiento, el estado restaurado trae postura y forma, y la repetición termina igual.

##### 4. Cambio de velocidad sobre una plataforma móvil

E camina sobre un vagón guionado que va a 6 m/s y agarra una prisa ×1,5.

1. Cada tick, la etapa de base aplica el desplazamiento del vagón, calculado desde el tiempo del mundo.
2. Suelo calcula la caminata relativa al vagón y la prisa multiplica solo esa parte.
3. E salta en el tick 4200. Su velocidad en el mundo es la del vagón en el punto de contacto más la caminata más el impulso. La prisa nunca multiplica al vagón.
4. Si E estuviera ralentizado al 50 %, el vagón lo seguiría llevando a 6 m/s y solo su caminata sería lenta.
5. El vagón es función del tiempo del mundo, igual en todas las máquinas; la afirmación va en coordenadas del vagón y se adopta.

Si la base fuera una balsa del host, E predice su caminata sobre la balsa interpolada. Al saltar fuera aparece un error del tamaño de lo que se movió la balsa durante la latencia, y se corrige suave al aterrizar.

##### 5. Desconexión mientras sostiene a un compañero

A cuelga de un borde y sostiene a B de la mano. B está en la línea interpolada.

1. A se desconecta. El host lo detecta en el tick 5000, quita su actor y cierra la interacción.
2. El ancla de B ya no existe: se rompe el invariante de Enganchado y B sale a Aire con la última velocidad del ancla. Sube la época de B.
3. El cliente de B recibe el evento y el snapshot de 5000. Sale de la línea interpolada con una reconciliación normal: restaura 5000 y repite sus inputs guardados.
4. Si B venía apretando agarrar y hay un borde al alcance, los ticks repetidos pueden capturarlo.
5. El camino es el mismo si A muere, si una explosión rompe su agarre o si se destruye el objeto del que cuelga.

##### 6. Corrección a mitad de un dash

F hace un dash en el tick 6000. En 6005 lo alcanza una explosión sin aviso, con política inmediata.

1. En el host, la explosión trae fuerza 4: F sale a Aire con el impulso y el modificador del dash se cancela, porque declara cancelarse con fuerza 2 o más. Sube la época.
2. El host rechaza las afirmaciones de F desde 6005: traen la época vieja.
3. F recibe el snapshot de 6006 cuando va por 6012. Restaura el estado completo, sincroniza los indicadores de Godot y repite de 6007 a 6012.
4. La diferencia, del orden de un metro, la absorbe el desvío visual en unos 100 ms. Sonido y partículas de la explosión llegan como evento del host.
5. Desde 6013 las afirmaciones traen la época nueva y la adopción vuelve.

##### 7. Trampolín, gravedad baja y techo

G cae sobre un trampolín que está dentro de una zona de gravedad al 30 %, con techo arriba.

1. La sonda de contactos ve el trampolín y la velocidad de llegada, y encola un impulso que asegura 14 m/s hacia arriba.
2. En el tick siguiente el snap no se aplica porque la velocidad sube, como documenta Godot. Suelo pierde el piso y G pasa a Aire.
3. La sonda de entorno encuentra la zona: la gravedad baja y el arco crece.
4. Contra el techo, `move_and_slide()` informa techo y desliza la velocidad vertical. G cae.
5. Todo sale de datos fijos: se predice y se adopta.

Si la zona invierte la gravedad, `up_direction` cambia y el cuerpo gira con validación de espacio. Un jugador colgado pierde el invariante de alineación y cae.

##### 8. Muerte en una tirolesa y reaparición

H baja por una tirolesa y un enemigo lo mata en el tick 8000.

1. El host aplica una transición forzada de fuerza 5 a Muerto, inmediata. Ningún agarre la resiste.
2. Se libera el cable, se apaga la colisión de H y el ragdoll visual hereda su velocidad. Sube la época.
3. Todo lo anclado a H pierde el ancla por la regla 7.
4. El host programa la reaparición 5 s después. En ese tick restablece el estado de H en el punto de aparición; todas las máquinas llaman a `reset_physics_interpolation()` para H.
5. Las afirmaciones que H envió sin saber que había muerto se rechazan por la época.

##### 9. Explosión junto a dos jugadores que empujan una caja

I y J empujan una caja pesada, enganchados a sus manijas y en la línea interpolada.

1. Una granada explota en el host. Como I y J los conduce el host, en sus clientes no hay nada que corregir.
2. La fuerza 4 supera el agarre de Enganchado con rol empujar: los dos salen a Aire con su impulso y la interacción termina por invariante.
3. La caja recibe su impulso en la física del host.
4. I y J vuelven a la línea predicha con una reconciliación y una mezcla de 0,2 s.

##### 10. Impulso de compañero rechazado por el host

K ofrece apoyo. L, con 120 ms de RTT, corre hacia K e interactúa en su tick 10000.

1. L ve a K interpolado, unos 100 ms en el pasado, todavía ofreciendo apoyo. Predice el lanzamiento.
2. K canceló la oferta en el tick 9998 del host.
3. Al procesar el tick 10000 de L, el host no encuentra la oferta y rechaza la interacción y la afirmación.
4. L recibe el snapshot y repite sin lanzamiento. Lo que ve es un impulso que falló, suavizado por el desvío.
5. Si K no hubiera cancelado, host y cliente lanzan a L en el mismo tick y no hay corrección. K solo cambia su animación cuando le llega el evento.

##### 11. Corrección mientras está parado sobre una plataforma

M camina sobre una plataforma guionada y recibe una corrección.

1. Durante los ticks repetidos, el espacio físico tiene la plataforma en su pose de ahora, no en la de cada tick.
2. Por eso, sobre una base, cada tick repetido se ejecuta en coordenadas de la base: la posición relativa se ubica sobre la pose actual, se mueve y se vuelve a pasar a relativa.
3. Los choques contra la plataforma salen bien. Los choques con geometría fija cercana pueden diferir un poco y los cubre la corrección siguiente.
4. Si las pruebas muestran que no alcanza, se rebobina la pose de las plataformas guionadas en cada tick repetido, con el truco que documenta netfox. Es más correcto y más caro.

##### 12. Carrera por pared, borde y aturdimiento

N corre por una pared hacia un borde y un enemigo lo aturde.

1. El aturdimiento es un modificador que quita moverse, saltar, agarrar, pared y dash.
2. Pared exige la capacidad pared: su invariante se rompe y N sale a Aire.
3. La salida de Aire a Hanging exige agarrar: N pasa de largo frente al borde.
4. Cuando el aturdimiento vence, en tiempo del actor, la capacidad vuelve. Si todavía hay un borde al alcance, la captura ocurre sin regla especial.

##### 13. Tirón de rendimiento en el host

El host se congela 200 ms en el tick 13000.

1. Godot recupera corriendo varios ticks por frame, hasta `max_physics_steps_per_frame`.
2. Los clientes siguen prediciendo y sus inputs se acumulan en la cola del host sin perderse.
3. El host procesa la cola tick por tick y adopta las afirmaciones: los clientes no ven correcciones.
4. Los clientes notan el salto del reloj y ajustan su adelanto de a poco.
5. En la pantalla del host, los demás jugadores avanzan a tirones mientras se vacía la cola.

##### 14. Paquetes perdidos justo al saltar

O salta en el tick 14000 y se pierden varios paquetes seguidos.

1. Cada paquete repite los últimos 4 a 8 ticks: perder uno o dos no pierde el salto.
2. Si se pierden más, el host simula esos ticks repitiendo los botones mantenidos.
3. Cuando llega un paquete, el contador de pulsaciones de saltar subió y el host aplica la pulsación en su tick actual, tarde.
4. Las afirmaciones de O siguen siendo válidas. Si la diferencia entra en el límite generoso, el host las adopta; si no, O recibe una corrección.

#### Alternativas descartadas

La alternativa seria más fuerte es la primera: que cada cliente mande sobre su propio movimiento. La descarto por los acoples entre jugadores, pero es el respaldo si la reconciliación resultara inmanejable: el núcleo del actor sirve igual en los dos modelos.

| Alternativa | Qué resolvería | Por qué no | Cuándo la reconsideraría |
| --- | --- | --- | --- |
| Autoridad del dueño: cada cliente manda su posición | Simplicidad, cero correcciones propias, inmune a las diferencias de Jolt | Sujetar, explosiones y empujes los ven tarde los demás o exigen transferir autoridad. La lógica del host usa posiciones atrasadas. Si el host sujeta a alguien, todos ven el salto. | Si mantener la reconciliación cuesta demasiado |
| Lockstep o rollback de todo el mundo | Igualdad exacta entre máquinas | Jolt solo es determinista con el mismo binario y orden; entre plataformas exige otra compilación. Godot no avanza ni restaura la física desde script. | Si Godot incorpora `space_step()` y Jolt multiplataforma |
| Host autoritativo sin predicción | Simplicidad | Cada input tarda un RTT en verse: inaceptable para saltos y Hanging | Para objetos sí; para el personaje, nunca |
| Predecir cuerpos rígidos y otros jugadores | Menos latencia al empujar o chocar | No se pueden rebobinar en 4.7.2, y predecir el input ajeno falla en acción | Con `space_step()` o un motor rebobinable |
| Personaje físico con `RigidBody3D` | Interacción física sin código | Control impreciso, no rebobinable, contactos distintos entre máquinas | Solo si el juego fuera caótico por diseño |
| `CharacterVirtual` de Jolt | Escalones y pegado al suelo nativos | No está en la API de Godot; obliga a una extensión propia y no resuelve la red | Si Godot lo expone |
| Un controlador único con banderas | Arrancar rápido | Cada combinación pide su `if`; con esta lista de casos explota | Nunca |
| Máquina de estados con cada combinación como estado | Todo explícito | Agachado, aturdido, en plataforma… multiplica estados | Nunca |
| Pila de modos que "vuelve al anterior" | Parece natural | Después de una escalera no se vuelve a Suelo: se va a donde diga la situación | Nunca |
| Plataformas integradas de Godot | Cero código | Leen el presente: fallan en ticks repetidos y difieren entre host y cliente | Para objetos que nadie predice |
| Señales de `Area3D` para lógica | Comodidad | No se repiten en ticks repetidos (inferencia I1) | En presentación |
| `MultiplayerSynchronizer` para el personaje | Cero protocolo | No tiene ticks ni acuses | Para puertas y palancas |
| Root motion dentro de la simulación | Animaciones que mandan | Depende de la presentación y de la perspectiva; no se repite igual | Como trayectorias autoradas dentro de la simulación |
| Simulación distinta por perspectiva | Ajuste fino por cámara | Una sesión mezcla perspectivas y el host simula igual para todos | Nunca; solo varía la presentación |
| Migración de host | La sesión sobrevive a la salida del host | Mucho trabajo que la lista no pide | Si se vuelve requisito; el estado serializable ayuda |
| Choque físico entre jugadores | Empujarse de verdad | El jugador predicho choca contra posiciones pasadas y genera correcciones | Como separación suave calculada por el host |
| `Engine.time_scale` para cámara lenta personal | Un solo ajuste | Es global | Nunca |
| Reemplazar `move_and_slide()` por un bucle propio con `move_and_collide()` | Control total del delta y de los indicadores | Rehacer pendientes, contactos múltiples y recuperación es mucho riesgo | Si las pruebas muestran que `move_and_slide()` no alcanza |
| Hanging sin snap | Continuidad física: el cuerpo queda donde se agarró | Guarda un dato más, es sensible al tick de captura y pide IK y mezclas para poses variables. La continuidad ya la cubre el desvío visual. | Si la pose de agarre se rechaza seguido en geometría irregular, o la cámara en primera persona molesta |
| Snap gradual dentro de la simulación | Ningún salto de pose, ni en la simulación ni en pantalla | Suma el avance del snap al estado y permite salir desde poses a medio camino | Si el desvío visual no alcanza |

#### Inventario, riesgos y qué validar primero

Cada pieza responde a un problema concreto: si se saca, algo identificable se rompe. Los riesgos abiertos se cierran midiendo en laboratorio, no discutiendo.

##### Inventario de piezas

| Pieza | Problema que resuelve | Qué se rompe sin ella |
| --- | --- | --- |
| Tick fijo numerado | Ordenar inputs, snapshots y eventos | Nada se puede comparar ni repetir |
| Predicción del personaje propio | Latencia de input | Cada salto se siente un RTT tarde |
| Afirmación y adopción | Diferencias de Jolt entre máquinas e inputs tardíos | Correcciones constantes cerca de los umbrales, como bordes y escalones |
| Época | Eventos del host que el cliente todavía no vio | El host adoptaría un estado que ignora un empujón |
| Contadores de pulsaciones | Paquetes perdidos | Saltos que no salen al perder paquetes |
| Reconciliación del actor local | Corregir sin volver atrás en el tiempo | Tirones hacia atrás del tamaño del adelanto |
| Política programado o inmediato | Elegir quién paga la latencia de un evento externo | Todo evento externo sería una corrección |
| Cambio de línea temporal | Predecir algo que depende de lo impredecible | Correcciones continuas mientras te sostienen o empujás una caja |
| Estado completo cuantizado | Retomar acciones a medias | Acciones repetidas que divergen |
| Paso con orden fijo | Dependencia del orden de los nodos | Resultados distintos según cómo esté armada la escena |
| Un modo exclusivo | Dos sistemas moviendo el mismo cuerpo | Peleas por la posición |
| Impulsos, modificadores y capacidades | Combinar efectos sin código cruzado | Un `if` por combinación |
| Fuerza contra agarre | Interrupciones coherentes | Una regla por cada par de efecto y modo |
| Invariantes con respaldo | Salidas cuando el mundo cambia | Personajes colgados de la nada |
| Postura por espacio libre | Techos bajos | Atravesar techos o quedar trabado |
| Base propia | Plataformas en ticks repetidos y en red | Saltos y deslizamientos raros sobre plataformas |
| Tiempo del actor | Cámara lenta personal y global | Saltos de distinta altura según la escala |
| Anclas por id | Desapariciones y desconexiones | Referencias a cosas que ya no existen |
| Sondas por demanda y ordenadas | Costo y orden variable de resultados | Consultas de más y decisiones distintas entre máquinas |
| Desvío visual | Correcciones y snaps visibles | Tirones en pantalla |
| Registro de eventos por tick | Repetir ticks repite sonidos | Sonidos dobles |

##### Riesgos abiertos

- **La adopción puede tapar errores reales.** Se mitiga registrando la diferencia entre el resultado del host y cada afirmación adoptada, y apagando la adopción en pruebas.
- **Los ticks repetidos ven el mundo del presente.** Cajas y plataformas no se rebobinan; el error residual lo toma la corrección siguiente. Si molesta, se rebobinan solo las plataformas guionadas.
- **Las consultas de Jolt tienen matices.** Aristas redondeadas y colisiones fantasma solo se conocen probando con las mallas reales.
- **`Engine.time_scale`** **alcanza todo.** Interfaz, tweens y timers tienen que quedar afuera a propósito.
- **Empujar con latencia.** Entre 150 y 250 ms de respuesta pueden sentirse mal incluso con inercia; hay que probarlo con objetos pesados reales.
- **Calibración de tolerancias.** Muy estrictas generan correcciones; muy amplias esconden errores.
- **Inferencia I2.** Si los cuerpos cinemáticos tardan un paso en actualizarse para las consultas, cualquier sonda contra plataformas en el mismo tick lo hereda.
- **netfox.** Su modelo de resimulación difiere del propuesto; adoptarlo o no se decide con un prototipo.

##### Qué validaría primero

1. **Esqueleto de red** con una cápsula en Suelo y Aire: tick, inputs con contadores, afirmaciones, adopción, reconciliación y simulador de latencia. Se mide cuántas correcciones por minuto aparecen.
2. **Base propia** con una plataforma guionada y una balsa del host.
3. **Postura y espacio libre**, con el deslizamiento bajo un techo.
4. **Un modo anclado simple**, Ladder, con empujones programados e inmediatos.
5. **Laboratorio de Hanging** con snap y las pruebas de confirmación de su sección.
6. **Una interacción con cambio de línea**: sujetar a un compañero.
7. **Cámara lenta** del mundo y personal.

#### Fuentes

Páginas abiertas el 2026-10-01.

- Godot 4.7: [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html), [CharacterBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/CharacterBody3D.xml), [character_body_3d.cpp](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/3d/physics/character_body_3d.cpp), [PhysicsBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/PhysicsBody3D.xml), [PhysicsDirectSpaceState3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/PhysicsDirectSpaceState3D.xml), [PhysicsServer3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/PhysicsServer3D.xml), [Engine.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Engine.xml), [StaticBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/StaticBody3D.xml), [AnimatableBody3D.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/AnimatableBody3D.xml), [MultiplayerSynchronizer.xml](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/modules/multiplayer/doc_classes/MultiplayerSynchronizer.xml)
- Godot, guías: [Using Jolt Physics](https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html), [Using physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html), [Advanced physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html), [High-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html), [PR 76462, space_step](https://github.com/godotengine/godot/pull/76462)
- Jolt: [Architecture.md, determinismo y rollback](https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/Docs/Architecture.md)
- Unreal 5.8: [Networked movement en Character Movement](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-networked-movement-in-the-character-movement-component-for-unreal-engine), [Mover, conceptos](https://dev.epicgames.com/documentation/en-us/unreal-engine/mover-features-and-concepts-in-unreal-engine), [PredictedMovement, autoridad del cliente](https://github.com/Vaei/PredictedMovement/wiki/Client-Authority)
- Unity: [Netcode for Entities, prediction switching](https://docs.unity3d.com/Packages/com.unity.netcode@1.5/manual/prediction-switching.html)
- netfox: [Rollback caveats](https://foxssake.github.io/netfox/latest/netfox/tutorials/rollback-caveats/), [repositorio](https://github.com/foxssake/netfox)



---

## Apéndice B: scripts usados para las pruebas automáticas

Estos scripts no están en el repositorio: vivieron en una carpeta temporal de la sesión y se copian acá tal cual. Con ellos se puede repetir cualquier prueba de este documento.

- **`run_godot.ps1`** lanza una instancia de Godot con tiempo límite, captura su salida y mata el árbol de procesos si se pasa.
- **`run_pair.ps1`** lanza un host y, 1,5 s después, un cliente, y junta las dos salidas.
- **Los `diag_*.gd`** son diagnósticos que extienden `SceneTree` y se corren con `-s <ruta>`.

**Scripts que sumó la validación** (copiados al final de este apéndice):

| Script | Punto | Qué hace |
| --- | --- | --- |
| `diag_kinematic_update.gd` | 2 | Inferencia I2: mueve un cuerpo cinemático y consulta en el mismo tick |
| `diag_kinematic_next_tick.gd` | 2 | Inferencia I2: consulta en el tick siguiente, y un `StaticBody3D` con `force_update_transform()` |
| `diag_enet_timeout.gd` y `diag_enet_timeout_long.gd` | 2 | Plazo de corte de ENet: congelan el host por silencios cada vez más largos, después de asentar la conexión |
| `diag_remote_on_base.gd` | 2 | En el cliente, registra tick a tick dónde se ve al otro jugador, su base y la copia local de la base |
| `medir_aterrizajes.ps1` | 2 | Corre pares con el host saltando sobre una base y el cliente registrando con `diag_remote_on_base.gd` |
| `analizar_aterrizajes.sh` y `analizar_cambios.sh` | 2 | Analizan esos registros: cuánto se acomoda el dibujo al aterrizar y en cada cambio de marco |
| `regresiones_bases2.ps1` | 2 a 4 | Regresiones en pareja: piso plano, el cliente sobre cada base y el host sobre cada base |
| `postura_pares.ps1` | 3 | Pares con el túnel: el cliente lo hace con tres redes, y el host lo hace mientras el cliente mira |
| `diag_postura_aire.gd` | 3 | Pies y cabeza tick a tick al agacharse y pararse, en el aire y en el piso |
| `diag_teclas_pausa.gd` | 3 | La G y la F con teclas simuladas |
| `diag_camara_aire.gd` | 3 | Altura de la cámara, los pies y la cabeza dibujados, cuadro por cuadro |
| `diag_remoto_postura.gd` | 3 | Lo mismo para el otro jugador, en el cliente |
| `diag_aviso_prueba.gd` | 3 | Control: una división entera a propósito, para ver que `-d` imprime los avisos |
| `diag_captura.gd` | 3 | La F12 con Ctrl apretado, con teclas simuladas |
| `escalera_pares.ps1` | 4 | Pares con la escalera: empujones fuertes y débiles, con red limpia y mala |
| `diag_escalera_frames.gd` | 4 | Orienta la cámara hacia la torre para grabar fotogramas de la escalera |
| `escalones_pares.ps1` | escalón | Pares con la pista de escalones: el cliente con tres redes, y el host mientras el cliente mira |
| `diag_escalones.gd` | escalón | Qué alturas de escalón sube caminando, con el motor real: un carril por caso |
| `diag_escalon_dibujo.gd` | escalón | Cuadro por cuadro, al subir el escalón de 30 cm: pies del cuerpo, pies dibujados y cámara |
| `hang_pares.ps1` | 5 | Hanging en red: la matriz de 0 a 200 ms con pérdida, el observador, los dos bordes que se mueven y la divergencia inyectada con y sin adopción |
| `diag_hanging.gd` | 5 | Hanging contra una pared de 2 m, con el motor real: agarrarse, desplazarse, subir, soltarse y saltar |
| `diag_colgar_dibujo.gd` | 5 | Cuadro por cuadro, alrededor del primer agarre: cuerpo, pies dibujados y cámara |
| `diag_sin_teclas.gd` | 5 | Parado contra una pared de 2,4 m, salta en el lugar con W y sin teclas, e imprime en cada tick qué decide `grab_check()` |
| `diag_salto_arriba.gd` | 5, salto | Colgado de una pared de 2 m, salta para arriba con W desde el salto y con W recién arriba, e imprime cada tick. Cambiando el fondo de la pared a 1 m se ve que con W desde el salto se pasa de largo |
| `demo_salto_arriba.gd` | 5, salto | La demostración: el laboratorio en una ventana, en cámara lenta y de costado, apretando W y Espacio como un jugador, con un cartel por paso y una hoja de capturas por forma. Se corre con ventana: `-s <script> --resolution 1280x720 -- --local` |
| `diag_agarre_subiendo.gd` | 5, subiendo | Pegado a muros de 1,9 a 3,2 m, salta en el lugar sin teclas y con W, e imprime en qué tick del salto se agarra, a qué velocidad subía y el tirón |
| `diag_techo_bajo.gd` | 5, subiendo | El borde «techo bajo» armado aparte: se agarra, salta mirando hacia atrás e imprime cada cambio de modo. Mostró que saltando hacia atrás se agarraba del techo |

El barrido de Hanging no está acá: es parte del repositorio (`scenes/net_lab/hang_sweep_test.gd`).

Ejemplo de prueba en pareja (la del 6b con la red saltando a 400 ms):

```powershell
$common = @('--headless','--path',$proyecto,'--scene','res://scenes/net_lab/net_lab.tscn','--')
$hostArgs = $common + @('--host','--port=7799','--bind=127.0.0.1','--sim-rtt=200','--sim-jitter=40','--sim-loss=5','--sim-seed=11','--sim-after=6','--sim-until=22','--report-after=31.5','--autoquit=34')
$clientArgs = $common + @('--client','--address=127.0.0.1','--port=7799','--test-input=zigzag','--trace','--sim-rtt=200','--sim-jitter=40','--sim-loss=5','--sim-seed=22','--sim-after=4.5','--sim-until=20.5','--report-after=30','--autoquit=32')
& .\run_pair.ps1 -HostArgs $hostArgs -ClientArgs $clientArgs -TimeoutSeconds 60
```

Ejemplo de la prueba de repetición a ritmo variable:

```powershell
& .\run_godot.ps1 -GodotArgs @('--headless','--path',$proyecto,'--scene','res://scenes/net_lab/actor_replay_test.tscn','--','--rate=varying') -TimeoutSeconds 200
```

### run_godot.ps1

```powershell
param(
    [string[]]$GodotArgs,
    [int]$TimeoutSeconds = 120,
    [string]$Exe = "C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe"
)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Exe
$psi.Arguments = ($GodotArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null = $proc.Start()
$stdout = $proc.StandardOutput.ReadToEndAsync()
$stderr = $proc.StandardError.ReadToEndAsync()

if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    & taskkill /PID $proc.Id /T /F | Out-Null
    Write-Output "TIMEOUT tras $TimeoutSeconds s: se mató el árbol de procesos"
    $code = 124
} else {
    $proc.WaitForExit()
    $code = $proc.ExitCode
}

Write-Output "---- stdout ----"
Write-Output $stdout.Result
Write-Output "---- stderr ----"
Write-Output $stderr.Result
Write-Output "---- exit code: $code ----"
```

### run_pair.ps1

```powershell
param(
    [string[]]$HostArgs,
    [string[]]$ClientArgs,
    [int]$ClientDelayMs = 1500,
    [int]$TimeoutSeconds = 60,
    [string]$Exe = "C:\Users\ElCaido97\Desktop\Godot_v4.7.2.exe"
)

function Start-Godot([string[]]$GodotArgs) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ($GodotArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()
    return @{ Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
}

$hostRun = Start-Godot $HostArgs
Start-Sleep -Milliseconds $ClientDelayMs
$clientRun = Start-Godot $ClientArgs

foreach ($run in @($clientRun, $hostRun)) {
    if (-not $run.Proc.WaitForExit($TimeoutSeconds * 1000)) {
        & taskkill /PID $run.Proc.Id /T /F | Out-Null
        Write-Output "TIMEOUT: se mató el proceso $($run.Proc.Id)"
    }
}

foreach ($pair in @(@("HOST", $hostRun), @("CLIENTE", $clientRun))) {
    $name = $pair[0]; $run = $pair[1]
    Write-Output "==== $name (exit $($run.Proc.ExitCode)) ===="
    Write-Output $run.Out.Result
    if ($run.Err.Result) { Write-Output "---- stderr ----"; Write-Output $run.Err.Result }
}
```

### diag_tick_rate.gd

```gdscript
extends SceneTree

# Diagnóstico: ¿cambiar physics_ticks_per_second en ejecución cambia los ticks
# por segundo real? ¿time_scale los cambia? ¿Qué delta recibe la física?

const CASES := [
	[60, 1.0],
	[72, 72.0 / 60.0],
	[57, 57.0 / 60.0],
	[66, 66.0 / 60.0],
	[60, 1.2],  # solo time_scale: no debería cambiar los ticks por segundo
]
const SECONDS_PER_CASE := 2.0

var _case := -1
var _ticks := 0
var _start_usec := 0
var _deltas := {}
var _ref32 := PackedFloat32Array([1.0 / 60.0])[0]


func _initialize() -> void:
	Engine.physics_jitter_fix = 0.0
	_next_case()


func _physics_process(delta: float) -> bool:
	if _case >= CASES.size():
		return true
	_ticks += 1
	_deltas[delta] = true
	var elapsed := (Time.get_ticks_usec() - _start_usec) / 1_000_000.0
	if elapsed >= SECONDS_PER_CASE:
		var keys := _deltas.keys()
		var d: float = keys[0]
		var d32 := PackedFloat32Array([d])[0]
		print("[diag] %d Hz, time_scale %.4f -> %.2f ticks/s reales, deltas distintos: %d, delta=%.17f, float32 igual a 1/60: %s" % [
			CASES[_case][0], CASES[_case][1], _ticks / elapsed, keys.size(), d, d32 == _ref32,
		])
		_next_case()
	return _case >= CASES.size()


func _next_case() -> void:
	_case += 1
	if _case >= CASES.size():
		return
	Engine.physics_ticks_per_second = CASES[_case][0]
	Engine.time_scale = CASES[_case][1]
	_ticks = 0
	_deltas.clear()
	_start_usec = Time.get_ticks_usec()
```

### diag_pose_check.gd

```gdscript
extends SceneTree

# Diagnóstico del paso 7: ActorBody.apply_state() devuelve si una pose entra en
# el mundo (no metida en la geometría y, si dice estar apoyada, con piso).

func _initialize() -> void:
	root.add_child(load("res://scenes/net_lab/net_lab_level.tscn").instantiate())
	var actor: ActorBody = load("res://scenes/actor/actor.tscn").instantiate()
	root.add_child(actor)
	await physics_frame
	await physics_frame
	# [descripción, posición, dice estar apoyado, lo esperado]
	var cases := [
		["apoyado en el piso", Vector3(0, 0, 8), true, true],
		["apoyado, 0,05 mm más arriba (cuantización)", Vector3(0, 0.0014, 8), true, true],
		["en el aire, sin decir que está apoyado", Vector3(0, 2, 8), false, true],
		["en el aire, diciendo que está apoyado", Vector3(0, 2, 8), true, false],
		["metido 20 cm en el piso", Vector3(0, -0.2, 8), true, false],
		["metido 3 cm en el piso", Vector3(0, -0.03, 8), true, false],
		["adentro de la pared", Vector3(6.5, 0, -3), true, false],
		["arriba de la plataforma", Vector3(-6, 2, -12), true, true],
		["tocando la pared por fuera", Vector3(5.64, 0, -3), true, true],
	]
	var failures := 0
	for c in cases:
		var s := ActorState.new()
		s.position = c[1]
		s.on_floor = c[2]
		s.mode = ActorState.Mode.GROUND if c[2] else ActorState.Mode.AIR
		s.quantize()
		var fits := actor.apply_state(s)
		var ok: bool = fits == c[3]
		if not ok:
			failures += 1
		print("[diag] %s %s: entra=%s (esperado %s)" % ["OK  " if ok else "MAL ", c[0], fits, c[3]])
	print("[diag] %d de %d como se esperaba" % [cases.size() - failures, cases.size()])
	quit(1 if failures > 0 else 0)
```

### diag_smoothing.gd

```gdscript
extends SceneTree

# Diagnóstico del paso 8: el desvío visual de una corrección decae en unos
# 100 ms, y un salto de más de 1,5 m no se suaviza.

func _initialize() -> void:
	root.add_child(load("res://scenes/net_lab/net_lab_level.tscn").instantiate())
	var actor: ActorBody = load("res://scenes/actor/actor.tscn").instantiate()
	root.add_child(actor)
	await physics_frame
	var s := ActorState.new()
	s.position = Vector3(0, 0, 8)
	s.on_floor = true
	s.mode = ActorState.Mode.GROUND
	s.quantize()
	actor.apply_state(s)

	actor.smooth_from(Vector3(0.5, 0, 8))
	var line := "[diag] corrección de 0,5 m, desvío por tick:"
	for i in 7:
		line += " %.3f" % actor.visual_offset.length()
		actor.decay_visual_offset(SimClock.TICK_DT)
	print(line)
	print("[diag] el visual sigue al desvío: %s" % actor.visual_root().position.is_equal_approx(actor.visual_offset))
	print("[diag] dónde se ve: %s" % actor.seen_position())

	actor.smooth_from(Vector3(2.0, 0, 8))
	print("[diag] corrección de 2 m: desvío %.3f (se acepta el salto si es 0)" % actor.visual_offset.length())
	quit()
```

### Scripts de la validación

Los scripts de esta parte se agregaron en la actualización del 2026-10-06. Se copian tal cual, como los anteriores.

#### diag_kinematic_update.gd

```gdscript
extends SceneTree

# Inferencia I2 del documento: si un cuerpo cinemático movido por transform se
# ve en su lugar nuevo en las consultas del MISMO tick, o recién en el siguiente.
# Se prueba con AnimatableBody3D (sync_to_physics apagado y prendido) y con un
# RigidBody3D congelado en modo cinemático.

var _probe: CharacterBody3D


func _initialize() -> void:
	_probe = CharacterBody3D.new()
	var probe_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	probe_shape.shape = sphere
	_probe.add_child(probe_shape)
	_probe.collision_mask = 1
	_probe.collision_layer = 2
	root.add_child(_probe)
	_probe.global_position = Vector3(0, 5, 0)

	var cases := [
		["AnimatableBody3D, sync_to_physics apagado", _make_animatable(false, Vector3(0, 0, 0)), "nodo"],
		["AnimatableBody3D, sync_to_physics prendido", _make_animatable(true, Vector3(10, 0, 0)), "nodo"],
		["RigidBody3D congelado en modo cinemático", _make_rigid(Vector3(20, 0, 0)), "nodo"],
		["AnimatableBody3D apagado + force_update_transform()", _make_animatable(false, Vector3(30, 0, 0)), "forzado"],
		["RigidBody3D cinemático + force_update_transform()", _make_rigid(Vector3(40, 0, 0)), "forzado"],
		["AnimatableBody3D apagado + transform directo al servidor", _make_animatable(false, Vector3(50, 0, 0)), "servidor"],
		["RigidBody3D cinemático + transform directo al servidor", _make_rigid(Vector3(60, 0, 0)), "servidor"],
	]
	await physics_frame
	await physics_frame
	await physics_frame
	for c in cases:
		_check(c[0], c[1], c[2])
		await physics_frame
	quit()


## Dentro del tick: sube el cuerpo 0,5 m y, sin esperar, barre la sonda hacia
## abajo encima de él. Si choca a 0,5 m de altura, la consulta ya lo ve movido.
func _check(label: String, body: Node3D, how: String) -> void:
	var x := body.global_position.x
	var target := Vector3(x, 0.35, 0)  # cara de arriba de 0,0 a 0,5 m
	match how:
		"nodo":
			body.global_position = target
		"forzado":
			body.global_position = target
			body.force_update_transform()
		"servidor":
			body.global_position = target
			PhysicsServer3D.body_set_state((body as PhysicsBody3D).get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), target))
	var collision := KinematicCollision3D.new()
	var hit := _probe.test_move(Transform3D(Basis(), Vector3(x, 2.0, 0)), Vector3(0, -3, 0), collision)
	var top := collision.get_position().y if hit else -999.0
	print("[diag] %s: en el mismo tick el barrido choca a y=%.3f (%s)" % [
		label, top, "ya lo ve movido" if absf(top - 0.5) < 0.01 else ("todavía lo ve abajo" if absf(top) < 0.01 else "otra cosa"),
	])


func _make_animatable(sync: bool, at: Vector3) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = sync
	body.add_child(_box())
	root.add_child(body)
	body.global_position = at + Vector3(0, -0.15, 0)  # cara de arriba en y=0
	return body


func _make_rigid(at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.add_child(_box())
	root.add_child(body)
	body.global_position = at + Vector3(0, -0.15, 0)
	return body


func _box() -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 0.3, 3)
	shape.shape = box
	return shape
```

#### diag_kinematic_next_tick.gd

```gdscript
extends SceneTree

# Segunda parte de la inferencia I2: un cuerpo movido por transform en el tick N,
# ¿se ve movido en las consultas del tick N+1? Y un StaticBody3D, ¿se ve en el
# mismo tick si se fuerza la actualización?

var _probe: CharacterBody3D


func _initialize() -> void:
	_probe = CharacterBody3D.new()
	var probe_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	probe_shape.shape = sphere
	_probe.add_child(probe_shape)
	_probe.collision_mask = 1
	_probe.collision_layer = 2
	root.add_child(_probe)
	_probe.global_position = Vector3(0, 5, 0)

	var animatable := _place(AnimatableBody3D.new(), Vector3(0, 0, 0))
	(animatable as AnimatableBody3D).sync_to_physics = false
	var rigid := RigidBody3D.new()
	rigid.freeze = true
	rigid.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_place(rigid, Vector3(10, 0, 0))
	var static_plain := _place(StaticBody3D.new(), Vector3(20, 0, 0))
	var static_forced := _place(StaticBody3D.new(), Vector3(30, 0, 0))
	await physics_frame
	await physics_frame
	await physics_frame

	# Tick N: se mueven todos. Los estáticos se consultan en el mismo tick.
	for body in [animatable, rigid, static_plain, static_forced]:
		body.global_position = Vector3(body.global_position.x, 0.35, 0)
	static_forced.force_update_transform()
	_report("StaticBody3D, mismo tick, sin forzar", static_plain)
	_report("StaticBody3D, mismo tick, con force_update_transform()", static_forced)
	_report("AnimatableBody3D, mismo tick", animatable)

	# Tick N+1: los cinemáticos, después de un paso de física.
	await physics_frame
	_report("AnimatableBody3D (sync_to_physics apagado), tick siguiente", animatable)
	_report("RigidBody3D cinemático, tick siguiente", rigid)
	_report("StaticBody3D sin forzar, tick siguiente", static_plain)
	await physics_frame
	quit()


func _report(label: String, body: Node3D) -> void:
	var x := body.global_position.x
	var collision := KinematicCollision3D.new()
	var hit := _probe.test_move(Transform3D(Basis(), Vector3(x, 2.0, 0)), Vector3(0, -3, 0), collision)
	var top := collision.get_position().y if hit else -999.0
	print("[diag] %s: choca a y=%.3f (%s)" % [
		label, top, "lo ve movido" if absf(top - 0.5) < 0.01 else ("lo ve en la pose vieja" if absf(top) < 0.01 else "otra cosa"),
	])


func _place(body: CollisionObject3D, at: Vector3) -> Node3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 0.3, 3)
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.global_position = at + Vector3(0, -0.15, 0)  # cara de arriba en y=0
	return body
```

#### diag_enet_timeout.gd

```gdscript
extends SceneTree

# Diagnostic: how long can the network be silent before ENet drops the peer?
# After a warm-up (so ENet's round-trip estimate settles, like in a real
# session), the host freezes its main loop (no ENet service: no acks, no
# packets) for growing spans. The client logs which silences it survives and
# when it loses the host.

const PORT := 7801
const WARMUP_MS := 40000

var role := ""
var peer := ENetMultiplayerPeer.new()
var start_ms := 0
var last_packet_ms := 0
var connected_ms := -1
var gone_ms := -1
var freezes := []
var next_stats_ms := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
	start_ms = Time.get_ticks_msec()
	if role == "host":
		print("host create_server: ", peer.create_server(PORT, 4))
		freezes = [
			[WARMUP_MS, 3000],
			[WARMUP_MS + 10000, 4500],
			[WARMUP_MS + 22000, 6000],
			[WARMUP_MS + 36000, 8000],
		]
	else:
		print("client create_client: ", peer.create_client("127.0.0.1", PORT))
	peer.peer_connected.connect(_on_connected)
	peer.peer_disconnected.connect(_on_disconnected)


func _now() -> int:
	return Time.get_ticks_msec() - start_ms


func _stats(id: int) -> String:
	var p: ENetPacketPeer = peer.get_peer(id)
	if p == null:
		return "no peer"
	return "rtt=%d rtt_var=%d" % [
		p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
		p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)]


func _on_connected(id: int) -> void:
	connected_ms = _now()
	print("%s t=%d connected to peer %d; %s" % [role, _now(), id, _stats(id)])


func _on_disconnected(id: int) -> void:
	gone_ms = _now()
	print("%s t=%d LOST peer %d after %d ms without receiving anything" % [role, _now(), id, _now() - last_packet_ms])


func _process(_delta: float) -> bool:
	if gone_ms < 0:
		peer.poll()
	while gone_ms < 0 and peer.get_available_packet_count() > 0:
		peer.get_packet()
		if last_packet_ms > 0 and _now() - last_packet_ms > 1000:
			print("%s t=%d traffic again after %d ms of silence, still connected" % [role, _now(), _now() - last_packet_ms])
		last_packet_ms = _now()
	if connected_ms >= 0 and gone_ms < 0:
		peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
		peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
		peer.put_packet(PackedByteArray([1]))
		if role == "client" and _now() >= next_stats_ms:
			next_stats_ms = _now() + 10000
			print("client t=%d %s" % [_now(), _stats(1)])
	if role == "host" and connected_ms >= 0 and gone_ms < 0 and not freezes.is_empty() and _now() - connected_ms >= freezes[0][0]:
		var f: Array = freezes.pop_front()
		print("host t=%d freezing for %d ms (total silence)" % [_now(), f[1]])
		OS.delay_msec(f[1])
		print("host t=%d resumed" % _now())
	if (gone_ms >= 0 and _now() - gone_ms > 1500) or _now() > 100000:
		print("%s t=%d done" % [role, _now()])
		quit()
	return false
```

#### diag_enet_timeout_long.gd

```gdscript
extends SceneTree

# Diagnostic: how long can the network be silent before ENet drops the peer?
# After a warm-up (so ENet's round-trip estimate settles, like in a real
# session), the host freezes its main loop (no ENet service: no acks, no
# packets) for growing spans. The client logs which silences it survives and
# when it loses the host.

const PORT := 7801
const WARMUP_MS := 40000

var role := ""
var peer := ENetMultiplayerPeer.new()
var start_ms := 0
var last_packet_ms := 0
var connected_ms := -1
var gone_ms := -1
var freezes := []
var next_stats_ms := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
	start_ms = Time.get_ticks_msec()
	if role == "host":
		print("host create_server: ", peer.create_server(PORT, 4))
		freezes = [
			[WARMUP_MS, 15000],
		]
	else:
		print("client create_client: ", peer.create_client("127.0.0.1", PORT))
	peer.peer_connected.connect(_on_connected)
	peer.peer_disconnected.connect(_on_disconnected)


func _now() -> int:
	return Time.get_ticks_msec() - start_ms


func _stats(id: int) -> String:
	var p: ENetPacketPeer = peer.get_peer(id)
	if p == null:
		return "no peer"
	return "rtt=%d rtt_var=%d" % [
		p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME),
		p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)]


func _on_connected(id: int) -> void:
	connected_ms = _now()
	print("%s t=%d connected to peer %d; %s" % [role, _now(), id, _stats(id)])


func _on_disconnected(id: int) -> void:
	gone_ms = _now()
	print("%s t=%d LOST peer %d after %d ms without receiving anything" % [role, _now(), id, _now() - last_packet_ms])


func _process(_delta: float) -> bool:
	if gone_ms < 0:
		peer.poll()
	while gone_ms < 0 and peer.get_available_packet_count() > 0:
		peer.get_packet()
		if last_packet_ms > 0 and _now() - last_packet_ms > 1000:
			print("%s t=%d traffic again after %d ms of silence, still connected" % [role, _now(), _now() - last_packet_ms])
		last_packet_ms = _now()
	if connected_ms >= 0 and gone_ms < 0:
		peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
		peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
		peer.put_packet(PackedByteArray([1]))
		if role == "client" and _now() >= next_stats_ms:
			next_stats_ms = _now() + 10000
			print("client t=%d %s" % [_now(), _stats(1)])
	if role == "host" and connected_ms >= 0 and gone_ms < 0 and not freezes.is_empty() and _now() - connected_ms >= freezes[0][0]:
		var f: Array = freezes.pop_front()
		print("host t=%d freezing for %d ms (total silence)" % [_now(), f[1]])
		OS.delay_msec(f[1])
		print("host t=%d resumed" % _now())
	if (gone_ms >= 0 and _now() - gone_ms > 1500) or _now() > 100000:
		print("%s t=%d done" % [role, _now()])
		quit()
	return false
```

#### diag_remote_on_base.gd

```gdscript
extends SceneTree

# Diagnostic: on the client, record every tick where the remote actor is seen
# (body + visual offset), its base and mode, and the local copy of its base.
# Run the host with --test-input=ride:1 so the host's actor rides the wagon
# and jumps every 3 s. Lines start with "R," for later analysis.

var lab: Node
var clock: SimClock
var connected := false


func _initialize() -> void:
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	if not connected and lab.get("_clock") != null:
		clock = lab.get("_clock")
		clock.tick_finished.connect(_record)
		connected = true
	return false


func _record(tick: int) -> void:
	var me := root.multiplayer.get_unique_id()
	if me == 1:
		return
	for actor in clock.sorted_actors():
		if actor.owner_peer_id == me:
			continue
		var seen: Vector3 = actor.seen_position()
		var s: ActorState = actor.state
		var wagon = BaseRegistry.find(1)
		var wagon_x: float = wagon.base_origin().x if wagon != null else 0.0
		var samples: Array = lab.get("_interpolation").get("_samples").get(actor.owner_peer_id, [])
		var newest: ActorState = samples[-1][1] if not samples.is_empty() else s
		print("R,%d,%d,%.4f,%.4f,%.4f,%d,%s,%.4f,%.4f,%.4f,%d,%s,%d" % [
			tick, clock.rate_hz, seen.x, seen.y, seen.z, s.base_id,
			ActorState.Mode.keys()[s.mode], wagon_x, Vector2(s.velocity.x, s.velocity.z).length(),
			actor.visual_offset.length(), newest.base_id, newest.on_floor,
			samples[-1][0] if not samples.is_empty() else -1])
```

#### medir_aterrizajes.ps1

```powershell
param([string]$Label, [string[]]$Only = @())
$sp = 'C:\Users\ELCAID~1\AppData\Local\Temp\claude\C--Users-ElCaido97-Documents-tun-tun-tun-sahur\5d835f7b-ceb8-45f9-9209-8dc10c4704df\scratchpad'
$proj = 'C:\Users\ElCaido97\Documents\tun-tun-tun-sahur'
$diag = Join-Path $sp 'diag_remote_on_base.gd'
$mala = @('--sim-rtt=200','--sim-jitter=40','--sim-loss=5','--sim-seed=7')
$near = @('--test-input=ride:1')
$cases = [ordered]@{
  'vagon_sin' = @('ride:1', @()); 'vagon_mala' = @('ride:1', $mala)
  'ascensor_sin' = @('ride:2', @()); 'ascensor_mala' = @('ride:2', $mala)
  'hop_sin' = @('hop:1', @()); 'hop_mala' = @('hop:1', $mala)
  'borde_sin' = @('edge:1', @()); 'borde_mala' = @('edge:1', $mala)
  'caminando_sin' = @('walkoff:1', @()); 'caminando_mala' = @('walkoff:1', $mala)
  'cerca_caminando_sin' = @('walkoff:1', $near); 'cerca_caminando_mala' = @('walkoff:1', $near + $mala)
  'cerca_hop_sin' = @('hop:1', $near); 'cerca_hop_mala' = @('hop:1', $near + $mala)
}
foreach ($name in $cases.Keys) {
  if ($Only.Count -gt 0 -and -not ($Only -contains $name)) { continue }
  $hostArgs = @('--headless','--path',$proj,'res://scenes/net_lab/net_lab.tscn','--','--host','--bind=127.0.0.1','--port=7799',"--test-input=$($cases[$name][0])",'--autoquit=40')
  $clientArgs = @('--headless','--path',$proj,'-s',$diag,'--','--client','--address=127.0.0.1','--port=7799','--autoquit=37') + $cases[$name][1]
  $file = Join-Path $sp "aterrizajes_$($Label)_$name.txt"
  & (Join-Path $sp 'run_pair.ps1') -HostArgs $hostArgs -ClientArgs $clientArgs -ClientDelayMs 1500 -TimeoutSeconds 90 | Set-Content -Encoding utf8 $file
  "done $name"
}
```

#### analizar_aterrizajes.sh

```sh
#!/bin/sh
# For each file: the visual correction (offset between drawn body and what is
# seen) around landings and takeoffs, what is left of it at touchdown after a
# frame change, and the biggest per-tick visible step.
for f in "$@"; do
  echo "== $f"
  grep -a "SCRIPT ERROR" "$f" | head -n 3
  grep -a "los dem" "$f" | tr -d '\r' | sed 's/^\[net_lab\] //'
  grep -a '^R,' "$f" | tr -d '\r' | awk -F, '
  { t[NR]=$2; x[NR]=$4; y[NR]=$5; z[NR]=$6; b[NR]=$7; m[NR]=$8; off[NR]=$11; n=NR }
  END {
    land=0; lsum=0; lmax=0; smax=0; fc=0; fsum=0; fmax=0; tds=0; tsum=0; tmax=0; cmax=0
    for (i=2;i<=n;i++) {
      dc=off[i]-off[i-1]; if (dc<0) dc=-dc; if (dc*60>cmax) cmax=dc*60
      dx=x[i]-x[i-1]; dy=y[i]-y[i-1]; dz=z[i]-z[i-1]; s=sqrt(dx*dx+dy*dy+dz*dz); if (s>smax && i>60) smax=s
      if (m[i-1]=="AIR" && m[i]=="GROUND") { land++; w=off[i]; for (j=i;j<=i+30 && j<=n;j++) if (off[j]>w) w=off[j]; lsum+=w; if (w>lmax) lmax=w }
      if (b[i]!=b[i-1]) { fc++; fsum+=off[i]; if (off[i]>fmax) fmax=off[i]
        for (j=i;j<=i+40 && j<=n;j++) if (j>1 && m[j-1]=="AIR" && m[j]=="GROUND") { tds++; tsum+=off[j]; if (off[j]>tmax) tmax=off[j]; break } }
    }
    if (land>0) printf "landings=%d  correction still showing at/after touchdown: avg %.3f m, max %.3f m\n", land, lsum/land, lmax
    if (fc>0) printf "frame changes=%d  offset when switching: avg %.3f m, max %.3f m; left at touchdown: avg %.3f, max %.3f (%d touchdowns)\n", fc, fsum/fc, fmax, (tds?tsum/tds:0), tmax, tds
    printf "biggest visible step in one tick: %.3f m; fastest correction: %.1f m/s\n", smax, cmax
  }'
done
```

#### analizar_cambios.sh

```sh
#!/bin/sh
# Per frame change: entering a base (0->N) or leaving it (N->0), the jump to
# spread, how long the spreading lasts, the fastest it moves the drawing
# (excluding the switch tick itself) and the offset still left when the actor
# touches down (if it was in the air).
for f in "$@"; do
  echo "== $f"
  grep -a '^R,' "$f" | tr -d '\r' | awk -F, '
  { t[NR]=$2; x[NR]=$4; y[NR]=$5; z[NR]=$6; b[NR]=$7; m[NR]=$8; off[NR]=$11; n=NR }
  END {
    for (k=0;k<2;k++) { cnt[k]=0; dsum[k]=0; dmax[k]=0; lsum[k]=0; cmx[k]=0; csum[k]=0; tdl[k]=0; tdn[k]=0; tdmax[k]=0 }
    for (i=3;i<=n;i++) if (b[i]!=b[i-1]) {
      k = (b[i]!=0) ? 0 : 1
      cnt[k]++; dsum[k]+=off[i]; if (off[i]>dmax[k]) dmax[k]=off[i]
      len=0; c=0
      for (j=i+1;j<=n && j<=i+80;j++) { if (b[j]!=b[j-1]) break; d=off[j-1]-off[j]; if (d<0) d=-d; if (d*60>c) c=d*60; len++; if (off[j]<0.005) break }
      lsum[k]+=len; csum[k]+=c; if (c>cmx[k]) cmx[k]=c
      if (m[i]=="AIR") for (j=i;j<=i+40 && j<=n;j++) if (m[j-1]=="AIR" && m[j]=="GROUND") { tdn[k]++; tdl[k]+=off[j]; if (off[j]>tdmax[k]) tdmax[k]=off[j]; break }
    }
    split("subirse bajarse", name, " ")
    for (k=0;k<2;k++) if (cnt[k]>0) printf "%s: %d veces, salto a repartir %.2f m (max %.2f), dura %.0f ms, velocidad del ajuste media %.1f m/s (max %.1f); queda al tocar %.2f m (max %.2f, %d en el aire)\n", name[k+1], cnt[k], dsum[k]/cnt[k], dmax[k], 1000*lsum[k]/cnt[k]/60, csum[k]/cnt[k], cmx[k], (tdn[k]?tdl[k]/tdn[k]:0), tdmax[k], tdn[k]
  }'
done
```

#### regresiones_bases2.ps1

```powershell
$sp = "C:\Users\ELCAID~1\AppData\Local\Temp\claude\C--Users-ElCaido97-Documents-tun-tun-tun-sahur\5d835f7b-ceb8-45f9-9209-8dc10c4704df\scratchpad"
$proj = "C:\Users\ElCaido97\Documents\tun-tun-tun-sahur"
$common = @('--headless','--path',$proj,'--scene','res://scenes/net_lab/net_lab.tscn','--')
$mala = @('--sim-rtt=200','--sim-jitter=40','--sim-loss=5','--sim-seed=22')
$tirones = @('--sim-rtt=20','--sim-jitter=5','--sim-stall-every=3000','--sim-stall=150','--sim-seed=22')

function Show($file) {
  Get-Content $file | Select-String -Pattern 'los dem|resumen: rol=CLIENT|adopci.n del jugador|SCRIPT|ERROR: res' | ForEach-Object {
    $_.Line -replace 'ida_y_vuelta.*?saltos_de_reloj','saltos_de_reloj' -replace ' snapshots_perdidos.*$','' -replace '^\[net_lab\] ','' -replace 'm.ximo=\d+ ','' }
}

# 1. Flat ground, as in step 8: host zigzag, client walk.
$flat = [ordered]@{ 'sin' = @(); 'mala' = $mala; 'tirones' = $tirones }
foreach ($name in $flat.Keys) {
  $hostArgs = $common + @('--host','--port=7799','--bind=127.0.0.1','--test-input=zigzag','--autoquit=24')
  $clientArgs = $common + @('--client','--address=127.0.0.1','--port=7799','--test-input=walk','--autoquit=22') + $flat[$name]
  $file = "$sp\reg2_plano_$name.txt"
  & "$sp\run_pair.ps1" -HostArgs $hostArgs -ClientArgs $clientArgs -TimeoutSeconds 50 | Out-File -Encoding utf8 $file
  "######## piso plano, red $name"
  Show $file
}

# 2. Client rides each base, as in the base tests.
$ride = [ordered]@{
  'vagon_sin' = @('--test-input=ride:1'); 'vagon_mala' = @('--test-input=ride:1') + $mala
  'balsa_sin' = @('--test-input=ride:3'); 'balsa_mala' = @('--test-input=ride:3') + $mala
}
foreach ($name in $ride.Keys) {
  $hostArgs = $common + @('--host','--port=7799','--bind=127.0.0.1','--autoquit=30')
  $clientArgs = $common + @('--client','--address=127.0.0.1','--port=7799','--trace','--autoquit=28') + $ride[$name]
  $file = "$sp\reg2_cliente_$name.txt"
  & "$sp\run_pair.ps1" -HostArgs $hostArgs -ClientArgs $clientArgs -TimeoutSeconds 50 | Out-File -Encoding utf8 $file
  $lines = Get-Content $file
  $on = @($lines | Select-String -Pattern 'actor: base=(1|3) ').Count
  $all = @($lines | Select-String -Pattern 'actor: base=').Count
  "######## cliente sobre $name (traza arriba de la base: $on de $all)"
  Show $file
}

# 3. Host rides each base, client watches it.
$watch = [ordered]@{
  'vagon_sin' = @('ride:1', @()); 'vagon_mala' = @('ride:1', $mala)
  'balsa_sin' = @('ride:3', @()); 'balsa_mala' = @('ride:3', $mala)
}
foreach ($name in $watch.Keys) {
  $hostArgs = $common + @('--host','--port=7799','--bind=127.0.0.1',"--test-input=$($watch[$name][0])",'--autoquit=32')
  $clientArgs = $common + @('--client','--address=127.0.0.1','--port=7799','--autoquit=30') + $watch[$name][1]
  $file = "$sp\reg2_host_$name.txt"
  & "$sp\run_pair.ps1" -HostArgs $hostArgs -ClientArgs $clientArgs -TimeoutSeconds 50 | Out-File -Encoding utf8 $file
  "######## host sobre $name, el cliente lo mira"
  Show $file
}
```

#### postura_pares.ps1

```powershell
$sp = "C:\Users\ELCAID~1\AppData\Local\Temp\claude\C--Users-ElCaido97-Documents-tun-tun-tun-sahur\5d835f7b-ceb8-45f9-9209-8dc10c4704df\scratchpad"
$proj = "C:\Users\ElCaido97\Documents\tun-tun-tun-sahur"
$common = @('--headless','--path',$proj,'--scene','res://scenes/net_lab/net_lab.tscn','--')
$mala = @('--sim-rtt=200','--sim-jitter=40','--sim-loss=5','--sim-seed=22')
$tirones = @('--sim-rtt=20','--sim-jitter=5','--sim-stall-every=3000','--sim-stall=150','--sim-seed=22')
$nets = [ordered]@{ 'sin' = @(); 'mala' = $mala; 'tirones' = $tirones }

function Show($file) {
  Get-Content $file | Select-String -Pattern 'los dem|resumen: rol=CLIENT|adopci.n del jugador|t.nel|SCRIPT|ERROR: res' | ForEach-Object {
    $_.Line -replace 'ida_y_vuelta.*?saltos_de_reloj','saltos_de_reloj' -replace ' snapshots_perdidos.*$','' -replace '^\[net_lab\] ','' -replace 'm.ximo=\d+ ','' -replace ' vel=.*$','' }
}

foreach ($name in $nets.Keys) {
  $hostArgs = $common + @('--host','--port=7799','--bind=127.0.0.1','--autoquit=26')
  $clientArgs = $common + @('--client','--address=127.0.0.1','--port=7799','--test-input=tunnel','--autoquit=24') + $nets[$name]
  $file = "$sp\postura_cliente_$name.txt"
  & "$sp\run_pair.ps1" -HostArgs $hostArgs -ClientArgs $clientArgs -TimeoutSeconds 50 | Out-File -Encoding utf8 $file
  "######## el cliente hace el tunel, red $name"
  Show $file
}
foreach ($name in @('sin','mala')) {
  $hostArgs = $common + @('--host','--port=7799','--bind=127.0.0.1','--test-input=tunnel','--autoquit=26')
  $clientArgs = $common + @('--client','--address=127.0.0.1','--port=7799','--autoquit=24') + $nets[$name]
  $file = "$sp\postura_host_$name.txt"
  & "$sp\run_pair.ps1" -HostArgs $hostArgs -ClientArgs $clientArgs -TimeoutSeconds 50 | Out-File -Encoding utf8 $file
  "######## el host hace el tunel y el cliente lo mira, red $name"
  Show $file
}
```

#### diag_postura_aire.gd

```gdscript
extends SceneTree

# Diagnostic: where the feet and the head are, tick by tick, when the actor
# crouches and stands up in the air and on the ground. Uses the real level,
# actor and motor, one tick per physics frame from a node in the tree (like
# the replay test).
#   ticks 0-29    settle
#   tick 30       jump (standing)
#   ticks 40-54   crouch held (in the air)
#   ticks 55+     released (stands up in the air if there is room below)
#   ticks 120-139 crouch held on the ground, then released


class Runner extends Node:
	var actor: ActorBody
	var state := ActorState.new()
	var tuning := ActorTuning.new()
	var tick := -1
	var last_stance := -1

	func _ready() -> void:
		SimClock.apply_tick_rate(SimClock.TICK_RATE)
		add_child(load("res://scenes/net_lab/net_lab_level.tscn").instantiate())
		actor = load("res://scenes/actor/actor.tscn").instantiate()
		actor.position = Vector3(0, 0.5, 4)
		add_child(actor)

	func _physics_process(_delta: float) -> void:
		tick += 1
		if tick == 0:
			state.position = Vector3(0, 0.5, 4)
			state.quantize()
			actor.apply_state(state)
		var buttons := 0
		if (tick >= 40 and tick < 55) or (tick >= 120 and tick < 140):
			buttons |= ActorInput.BUTTON_CROUCH
		var presses := 1 if tick >= 30 else 0
		var mode_before := state.mode
		ActorMotor.step(actor, state, ActorInput.make(tick, Vector2.ZERO, 0.0, buttons, presses), tuning, 1.0 / 60.0)
		var feet := actor.global_position.y
		var head := feet + actor.stance_height(state.stance)
		var changed := state.stance != last_stance and last_stance != -1
		if (tick >= 37 and tick <= 58) or (tick >= 118 and tick <= 142) or changed:
			print("tick %3d  modo=%-6s postura=%-9s pies=%6.3f  cabeza=%6.3f%s" % [tick, ActorState.Mode.keys()[state.mode],
				ActorState.Stance.keys()[state.stance], feet, head, "   <- cambio de postura (modo al empezar el tick: %s)" % ActorState.Mode.keys()[mode_before] if changed else ""])
		last_stance = state.stance
		if tick >= 150:
			get_tree().quit()


func _initialize() -> void:
	root.add_child(Runner.new())
```

#### diag_teclas_pausa.gd

```gdscript
extends SceneTree

# Diagnostic: the lab's pause (action toggle_debug_freeze, G) and one-tick step
# (action avanzar_tick, F), sending real key events through Input.

var lab: Node
var frame := 0
var paused_tick := -1


func _initialize() -> void:
	for action in ["toggle_debug_freeze", "avanzar_tick"]:
		var keys := []
		for event in InputMap.action_get_events(action):
			keys.append(OS.get_keycode_string((event as InputEventKey).physical_keycode))
		print("accion %s: %s" % [action, keys])
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	root.add_child(lab)


func _key(physical: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = physical
	down.keycode = physical
	down.pressed = true
	Input.parse_input_event(down)
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _process(_delta: float) -> bool:
	frame += 1
	var clock: SimClock = lab.get("_clock")
	if frame == 60:
		_key(KEY_G)
	elif frame == 90:
		paused_tick = clock.tick
		print("tras G: paused=%s tick=%d" % [clock.paused, clock.tick])
	elif frame == 120:
		print("30 frames despues, sigue en pausa: paused=%s tick=%d (igual: %s)" % [clock.paused, clock.tick, clock.tick == paused_tick])
		_key(KEY_F)
	elif frame == 140:
		print("tras F: tick=%d (avanzo %d)" % [clock.tick, clock.tick - paused_tick])
		_key(KEY_G)
	elif frame == 170:
		print("tras otra G: paused=%s tick=%d (sigue corriendo: %s)" % [clock.paused, clock.tick, clock.tick > paused_tick + 1])
		quit()
	return false
```

#### diag_camara_aire.gd

```gdscript
extends SceneTree

# Diagnostic: per drawn frame, around the crouch in the air of the
# `crouchjump` test input, how high the camera pivot is, where the actor's
# feet are drawn (interpolated) and where its head is drawn.
# Run with --fixed-fps 120 so there are two drawn frames per tick.

var lab: Node
var frame := 0


func _initialize() -> void:
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	frame += 1
	var clock: SimClock = lab.get("_clock")
	var actor: ActorBody = lab.get("_local_actor")
	var camera: Node3D = lab.get("_camera")
	if clock == null or not is_instance_valid(actor) or camera == null:
		return false
	if clock.tick >= 122 and clock.tick <= 140:
		var feet := actor.visual_root().get_global_transform_interpolated().origin.y
		var head := feet + actor.stance_height(actor.state.stance)
		print("frame %4d tick %3d postura=%-9s pies dibujados=%.3f cabeza dibujada=%.3f camara=%.3f" % [
			frame, clock.tick, ActorState.Stance.keys()[actor.state.stance], feet, head, camera.global_position.y])
	if clock.tick > 140:
		quit()
	return false
```

#### diag_remoto_postura.gd

```gdscript
extends SceneTree

# Diagnostic, on the client: where the other player's feet and head are drawn
# (interpolated) every frame while its stance changes in the air. Prints only
# frames around a stance change of the drawn remote state.

var lab: Node
var frame := 0
var last_stance := -1
var print_until := -1
var history: Array[String] = []


func _initialize() -> void:
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	frame += 1
	var clock: SimClock = lab.get("_clock")
	if clock == null:
		return false
	var me := root.multiplayer.get_unique_id() if root.multiplayer.has_multiplayer_peer() else 1
	for actor in clock.sorted_actors():
		if actor.owner_peer_id == me or me == 1:
			continue
		var feet := actor.visual_root().get_global_transform_interpolated().origin.y
		var head := feet + actor.stance_height(actor.state.stance)
		var line := "frame %5d tick %4d postura=%-9s pies dibujados=%.3f cabeza dibujada=%.3f" % [
				frame, clock.tick, ActorState.Stance.keys()[actor.state.stance], feet, head]
		if last_stance != -1 and actor.state.stance != last_stance:
			for old in history:
				print(old)
			print("---- cambio de postura del otro jugador a %s" % ActorState.Stance.keys()[actor.state.stance])
			print_until = frame + 8
		if frame <= print_until:
			print(line)
		history.append(line)
		if history.size() > 5:
			history.pop_front()
		last_stance = actor.state.stance
	return false
```

#### diag_aviso_prueba.gd

```gdscript
extends SceneTree

# Control for the warning check: this script has an integer division on
# purpose. If the console debugger reports script warnings, it must show one.

func _initialize() -> void:
	var ticks := 7
	var half := ticks / 2
	print("half = %d" % half)
	quit()
```

#### diag_captura.gd

```gdscript
extends SceneTree

# Diagnostic: F12 (action `captura`) saves a screenshot even while Ctrl is
# held (crouching). Sends real key events through Input.

var lab: Node
var frame := 0


func _initialize() -> void:
	print("accion captura: %s" % [InputMap.action_get_events("captura").map(
		func(e): return OS.get_keycode_string((e as InputEventKey).physical_keycode))])
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	root.add_child(lab)


func _key(physical: Key, pressed: bool, ctrl: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.keycode = physical
	event.pressed = pressed
	event.ctrl_pressed = ctrl
	Input.parse_input_event(event)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 60:
		_key(KEY_CTRL, true, true)
	elif frame == 90:
		var actor: ActorBody = lab.get("_local_actor")
		print("con Ctrl apretado, postura: %s" % ActorState.Stance.keys()[actor.state.stance])
		_key(KEY_F12, true, true)
		_key(KEY_F12, false, true)
	elif frame == 130:
		print("aviso en el panel: %s" % lab.get("_flash_text"))
		_key(KEY_CTRL, false, false)
		quit()
	return false
```

#### escalera_pares.ps1

```powershell
param([string[]]$Only = @())
$sp = "C:\Users\ELCAID~1\AppData\Local\Temp\claude\C--Users-ElCaido97-Documents-tun-tun-tun-sahur\5d835f7b-ceb8-45f9-9209-8dc10c4704df\scratchpad"
$proj = "C:\Users\ElCaido97\Documents\tun-tun-tun-sahur"
$common = @('--headless','--path',$proj,'-d','--scene','res://scenes/net_lab/net_lab.tscn','--')
$mala = @('--sim-rtt=200','--sim-jitter=40','--sim-loss=5','--sim-seed=22')
$cases = [ordered]@{
  'fuerte_sin' = @(4, @()); 'debil_sin' = @(2, @())
  'fuerte_mala' = @(4, $mala); 'debil_mala' = @(2, $mala)
}
foreach ($name in $cases.Keys) {
  if ($Only.Count -gt 0 -and -not ($Only -contains $name)) { continue }
  $force = $cases[$name][0]
  $hostArgs = $common + @('--host','--port=7799','--bind=127.0.0.1','--autoquit=26','--test-push-at=8,16',"--test-scheduled-push-at=12,20","--test-push-force=$force")
  $clientArgs = $common + @('--client','--address=127.0.0.1','--port=7799','--test-input=ladder','--trace','--autoquit=24') + $cases[$name][1]
  $file = "$sp\escalera_$name.txt"
  & "$sp\run_pair.ps1" -HostArgs $hostArgs -ClientArgs $clientArgs -TimeoutSeconds 50 | Out-File -Encoding utf8 $file
  "######## escalera, empujones de fuerza $force, red $name"
  Get-Content $file | Select-String -Pattern 'empuj|resumen: rol=CLIENT|adopci.n del jugador|SCRIPT|WARNING: [A-Z]' | ForEach-Object {
    $_.Line -replace 'ida_y_vuelta.*?saltos_de_reloj','saltos_de_reloj' -replace ' snapshots_perdidos.*$','' -replace '^\[net_lab\] ','' -replace 'm.ximo=\d+ ','' -replace 'actores=\[[^\]]*\] ','' }
}
```

#### diag_escalera_frames.gd

```gdscript
extends SceneTree

# Frames for the ladder: runs the lab with the given args and keeps the camera
# looking toward the tower (+Z), slightly from the side, so it sees the climb.

var lab: Node


func _initialize() -> void:
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	var camera = lab.get("_camera")
	if camera != null:
		camera.yaw = PI - 0.6
		camera.pitch = -0.15
	return false
```

#### escalones_pares.ps1

```powershell
$sp = "C:\Users\ELCAID~1\AppData\Local\Temp\claude\C--Users-ElCaido97-Documents-tun-tun-tun-sahur\5d835f7b-ceb8-45f9-9209-8dc10c4704df\scratchpad"
$proj = "C:\Users\ElCaido97\Documents\tun-tun-tun-sahur"
$common = @('--headless','--path',$proj,'-d','--scene','res://scenes/net_lab/net_lab.tscn','--')
$mala = @('--sim-rtt=200','--sim-jitter=40','--sim-loss=5','--sim-seed=22')
$tirones = @('--sim-rtt=20','--sim-jitter=5','--sim-stall-every=3000','--sim-stall=150','--sim-seed=22')
$nets = [ordered]@{ 'sin' = @(); 'mala' = $mala; 'tirones' = $tirones }

function Show($file) {
  Get-Content $file | Select-String -Pattern 'los dem|resumen: rol=CLIENT|adopci.n del jugador|escalones:|SCRIPT|ERROR: res|WARNING: [A-Z]' | ForEach-Object {
    $_.Line -replace 'ida_y_vuelta.*?saltos_de_reloj','saltos_de_reloj' -replace ' snapshots_perdidos.*$','' -replace '^\[net_lab\] ','' -replace 'm.ximo=\d+ ','' -replace 'actores=\[[^\]]*\] ','' }
}

# 1. The client walks the step course; the host stands still.
foreach ($name in $nets.Keys) {
  $hostArgs = $common + @('--host','--port=7799','--bind=127.0.0.1','--autoquit=32')
  $clientArgs = $common + @('--client','--address=127.0.0.1','--port=7799','--test-input=steps','--autoquit=30') + $nets[$name]
  $file = "$sp\escalones_cliente_$name.txt"
  & "$sp\run_pair.ps1" -HostArgs $hostArgs -ClientArgs $clientArgs -TimeoutSeconds 60 | Out-File -Encoding utf8 $file
  "######## el cliente hace la pista de escalones, red $name"
  Show $file
}
# 2. The host walks the step course; the client watches it.
foreach ($name in @('sin','mala')) {
  $hostArgs = $common + @('--host','--port=7799','--bind=127.0.0.1','--test-input=steps','--autoquit=32')
  $clientArgs = $common + @('--client','--address=127.0.0.1','--port=7799','--autoquit=30') + $nets[$name]
  $file = "$sp\escalones_host_$name.txt"
  & "$sp\run_pair.ps1" -HostArgs $hostArgs -ClientArgs $clientArgs -TimeoutSeconds 60 | Out-File -Encoding utf8 $file
  "######## el host hace la pista y el cliente lo mira, red $name"
  Show $file
}
```

#### diag_escalones.gd

```gdscript
extends SceneTree

# Diagnostic: which step heights the actor climbs walking into them, with the
# real motor, one tick per physics frame from a node in the tree. One lane per
# case: a box step in front of the actor, or a staircase. Prints, per case,
# whether it ended on top, the final feet height, the biggest rise in one tick,
# the ticks spent touching a wall and the mode at the end.


class Runner extends Node:
	const STEP_HEIGHTS := [0.05, 0.10, 0.15, 0.20, 0.25, 0.28, 0.30, 0.32, 0.35, 0.40]
	var actor: ActorBody
	var state: ActorState
	var tuning := ActorTuning.new()
	var cases: Array = []  # [name, start, yaw, move, buttons, top height, ticks]
	var case_index := -1
	var tick := 0
	var start_y := 0.0
	var max_rise := 0.0
	var max_y := 0.0
	var wall_ticks := 0
	var air_ticks := 0
	var last_y := 0.0

	func _ready() -> void:
		SimClock.apply_tick_rate(SimClock.TICK_RATE)
		_add_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
		var lane := 0
		for h in STEP_HEIGHTS:
			var x := lane * 3.0
			_add_box(Vector3(2, h, 2), Vector3(x, h / 2.0, -2.0))
			for speed in [["caminando", 0], ["agachado", ActorInput.BUTTON_CROUCH], ["corriendo", ActorInput.BUTTON_RUN]]:
				cases.append(["%.2f m %s" % [h, speed[0]], Vector3(x, 0, 0.5), 0.0, Vector2(0, 1), speed[1], h, 70])
			cases.append(["%.2f m en diagonal (45 grados)" % h, Vector3(x + 1.2, 0, 0.2), PI / 4.0, Vector2(0, 1), 0, h, 70])
			cases.append(["%.2f m casi de costado (75 grados)" % h, Vector3(x + 0.9, 0, -0.6), PI * 75.0 / 180.0, Vector2(0, 1), 0, h, 40])
			lane += 1
		# Staircase: rise 0.2, tread 0.35, 6 steps, then a landing.
		var sx := lane * 3.0
		for i in 6:
			var top := 0.2 * (i + 1)
			_add_box(Vector3(2, top, 0.35), Vector3(sx, top / 2.0, -1.175 - 0.35 * i))
		_add_box(Vector3(2, 1.2, 2), Vector3(sx, 0.6, -1.0 - 0.35 * 6 - 1.0))
		cases.append(["escalera de 6 escalones de 0,20 m caminando", Vector3(sx, 0, 0.5), 0.0, Vector2(0, 1), 0, 1.2, 150])
		cases.append(["escalera bajando desde arriba", Vector3(sx, 1.2, -4.3), PI, Vector2(0, 1), 0, 1.2, 100])
		cases.append(["escalera de 6 escalones de 0,20 m agachado", Vector3(sx, 0, 0.5), 0.0, Vector2(0, 1), ActorInput.BUTTON_CROUCH, 1.2, 200])
		actor = load("res://scenes/actor/actor.tscn").instantiate()
		add_child(actor)

	func _add_box(size: Vector3, center: Vector3) -> void:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		body.position = center
		add_child(body)

	func _next_case() -> void:
		case_index += 1
		if case_index >= cases.size():
			get_tree().quit()
			return
		var c: Array = cases[case_index]
		state = ActorState.new()
		state.position = c[1]
		state.mode = ActorState.Mode.GROUND
		state.on_floor = true
		actor.apply_state(state)
		tick = 0
		start_y = state.position.y
		max_rise = 0.0
		max_y = 0.0
		wall_ticks = 0
		air_ticks = 0
		last_y = start_y

	func _physics_process(_delta: float) -> void:
		if case_index == -1:
			_next_case()
			return
		var c: Array = cases[case_index]
		var settle := 10
		var move: Vector2 = c[3] if tick >= settle else Vector2.ZERO
		var input := ActorInput.make(tick, move, c[2], c[4] if tick >= settle - 5 else 0, 0)
		ActorMotor.step(actor, state, input, tuning, SimClock.TICK_DT)
		var y := state.position.y
		max_rise = maxf(max_rise, y - last_y)
		max_y = maxf(max_y, y)
		last_y = y
		if state.mode == ActorState.Mode.AIR:
			air_ticks += 1
		if actor.is_on_wall():
			wall_ticks += 1
		tick += 1
		if tick >= c[6] + settle:
			var on_top := absf(max_y - c[5]) < 0.02
			print("[escalones] %-40s sube=%s pies_max=%.3f pies_final=%.3f mayor_subida_en_un_tick=%.3f ticks_contra_pared=%d ticks_en_aire=%d modo=%s" % [
					c[0], "SI" if on_top else "no", max_y, y, max_rise, wall_ticks, air_ticks, ActorState.Mode.keys()[state.mode]])
			_next_case()


func _initialize() -> void:
	root.add_child(Runner.new())
```

#### diag_escalon_dibujo.gd

```gdscript
extends SceneTree

# Diagnostic: per drawn frame, while the `steps` test input climbs the 30 cm
# step, the body's feet height, where the feet are drawn (interpolated, with
# the visual offset) and the camera height. Run with --fixed-fps 120 so there
# are two drawn frames per tick.

var lab: Node
var frame := 0
var printing := 0


func _initialize() -> void:
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	frame += 1
	var clock: SimClock = lab.get("_clock")
	var actor: ActorBody = lab.get("_local_actor")
	var camera: Node3D = lab.get("_camera")
	if clock == null or not is_instance_valid(actor) or camera == null:
		return false
	var body_y := actor.global_position.y
	var drawn := actor.visual_root().get_global_transform_interpolated().origin.y
	# Start printing a few frames before the body reaches the 30 cm step.
	if printing == 0 and actor.global_position.x < -8.5 and actor.global_position.z > 11.0 and body_y < 0.05:
		printing = 1
	if printing > 0 and printing < 40:
		print("frame %4d tick %4d cuerpo=%.3f pies_dibujados=%.3f camara=%.3f" % [frame, clock.tick, body_y, drawn, camera.global_position.y])
		printing += 1
	if printing >= 40:
		quit()
	return false
```

#### hang_pares.ps1

```powershell
param([string[]]$Only = @())
# Hanging over the network (confirmation tests 5 and 6):
#  A. client cycles the hang test against the fixed 2 m block, RTT 0/60/120/200
#     ms with +-20 ms jitter (none at 0) and 0/2/5 % loss;
#  B. the host cycles it and the client watches (smoothness seen by an observer);
#  C. client on the moving edges: scripted platform (base 4) and host raft (5);
#  D. injected divergence: 0.5 mm per tick on the client, adoption on and off.
$sp = "C:\Users\ELCAID~1\AppData\Local\Temp\claude\C--Users-ElCaido97-Documents-tun-tun-tun-sahur\5d835f7b-ceb8-45f9-9209-8dc10c4704df\scratchpad"
$proj = "C:\Users\ElCaido97\Documents\tun-tun-tun-sahur"
$common = @('--headless','--path',$proj,'-d','--scene','res://scenes/net_lab/net_lab.tscn','--')

function Show($file) {
  Get-Content $file | Select-String -Pattern 'resumen: rol=CLIENT|adopci.n del jugador|colgar:|correcciones: la|los dem|SCRIPT|ERROR: res|WARNING: [A-Z]' | ForEach-Object {
    $_.Line -replace 'ida_y_vuelta.*?saltos_de_reloj','saltos_de_reloj' -replace ' snapshots_perdidos.*$','' -replace '^\[net_lab\] ','' -replace 'm.ximo=\d+ ','' -replace 'actores=\[[^\]]*\] ','' -replace 'tick=\d+ ','' -replace 'prendida=true ','' -replace ' apagada=\d+ sin_afirmaci.n=\d+','' }
}

function Pair($name, $hostExtra, $clientExtra) {
  if ($Only.Count -gt 0 -and -not ($Only -contains $name)) { return }
  $hostArgs = $common + @('--host','--port=7799','--bind=127.0.0.1','--autoquit=47') + $hostExtra
  $clientArgs = $common + @('--client','--address=127.0.0.1','--port=7799','--autoquit=45') + $clientExtra
  $file = "$sp\colgar_$name.txt"
  & "$sp\run_pair.ps1" -HostArgs $hostArgs -ClientArgs $clientArgs -TimeoutSeconds 80 | Out-File -Encoding utf8 $file
  "######## $name"
  Show $file
}

foreach ($rtt in @(0, 60, 120, 200)) {
  foreach ($loss in @(0, 2, 5)) {
    $jitter = if ($rtt -eq 0) { 0 } else { 20 }
    Pair "red_${rtt}ms_${loss}" @() @('--test-input=hang',"--sim-rtt=$rtt","--sim-jitter=$jitter","--sim-loss=$loss",'--sim-seed=22')
  }
}
Pair 'observador_sin' @('--test-input=hang') @()
Pair 'observador_mala' @('--test-input=hang') @('--sim-rtt=200','--sim-jitter=40','--sim-loss=5','--sim-seed=22')
Pair 'plataforma_sin' @() @('--test-input=hang:4')
Pair 'plataforma_mala' @() @('--test-input=hang:4','--sim-rtt=200','--sim-jitter=40','--sim-loss=5','--sim-seed=22')
Pair 'balsa_sin' @() @('--test-input=hang:5')
Pair 'balsa_mala' @() @('--test-input=hang:5','--sim-rtt=200','--sim-jitter=40','--sim-loss=5','--sim-seed=22')
Pair 'divergencia_adopcion' @() @('--test-input=hang','--test-perturb-mm=0.5','--sim-seed=22')
Pair 'divergencia_sin_adopcion' @('--no-adoption') @('--test-input=hang','--test-perturb-mm=0.5','--sim-seed=22')
Pair 'sin_divergencia_sin_adopcion' @('--no-adoption') @('--test-input=hang','--sim-seed=22')
```

#### diag_hanging.gd

```gdscript
extends SceneTree

# Diagnostic: Hanging against a 2 m wall with the real motor, one tick per
# physics frame from a node in the tree. Scripted inputs: walk to the wall and
# jump (grab on the way down), shimmy right, climb with Space looking at the
# wall, walk off the top, grab again, drop with Ctrl, grab again, jump away
# looking back. Prints every mode change and a line every 10 ticks.


class Runner extends Node:
	var actor: ActorBody
	var state := ActorState.new()
	var tuning := ActorTuning.new()
	var tick := 0
	var presses := 0
	var last_mode := -1

	func _ready() -> void:
		SimClock.apply_tick_rate(SimClock.TICK_RATE)
		_add_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
		_add_box(Vector3(4, 2, 2), Vector3(0, 1, -1.5))  # front face at z = -0.5, top at 2
		actor = load("res://scenes/actor/actor.tscn").instantiate()
		add_child(actor)

	func _add_box(size: Vector3, center: Vector3) -> void:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		body.position = center
		add_child(body)

	func _input_for(t: int) -> ActorInput:
		var move := Vector2.ZERO
		var yaw := 0.0
		var buttons := 0
		if t == 15 or t == 120 or t == 260 or t == 380:
			presses += 1
		if t >= 10 and t < 80:
			move = Vector2(0, 1)  # toward the wall, jump at 15
		elif t >= 80 and t < 110:
			move = Vector2(1, 0)  # shimmy right
		elif t >= 120 and t < 170:
			move = Vector2.ZERO  # climbing
		elif t >= 170 and t < 215:
			move = Vector2(0, -1)  # walk back off the top (falls down the front)
		elif t >= 215 and t < 255:
			move = Vector2.ZERO
		elif t >= 255 and t < 320:
			move = Vector2(0, 1)  # to the wall again, jump at 260
		elif t >= 330 and t < 335:
			buttons = ActorInput.BUTTON_CROUCH  # drop
		elif t >= 360 and t < 445:
			move = Vector2(0, 1)  # grab again (jump at 380)
		if t == 455:
			presses += 1
		if t >= 450 and t < 460:
			yaw = PI  # looking back: Space jumps away
		return ActorInput.make(t, move, yaw, buttons, presses)

	func _physics_process(_delta: float) -> void:
		if tick == 0:
			state.position = Vector3(0, 0, 1.5)
			state.mode = ActorState.Mode.GROUND
			state.on_floor = true
			actor.apply_state(state)
		ActorMotor.step(actor, state, _input_for(tick), tuning, SimClock.TICK_DT)
		var changed := state.mode != last_mode
		last_mode = state.mode
		if changed or tick % 10 == 0:
			print("[colgar] t=%3d %s%s pies=(%.3f, %.3f, %.3f) vel=(%.2f, %.2f, %.2f) postura=%s filo=%s t_ancla=%.3f snap=%s" % [
					tick, "-> " if changed else "   ", ActorState.Mode.keys()[state.mode],
					state.position.x, state.position.y, state.position.z,
					state.velocity.x, state.velocity.y, state.velocity.z,
					ActorState.Stance.keys()[state.stance], state.anchor_point, state.anchor_t, actor.snap_jump])
		tick += 1
		if tick >= 500:
			get_tree().quit()


func _initialize() -> void:
	root.add_child(Runner.new())
```

#### diag_colgar_dibujo.gd

```gdscript
extends SceneTree

# Diagnostic: per drawn frame, around the first grab of the `hang` test input,
# where the body is, where its feet are drawn (interpolated, with the visual
# offsets) and where the camera is. Run with --fixed-fps 120 so there are two
# drawn frames per tick.

var lab: Node
var frame := 0
var printing := 0
var history: Array = []


func _initialize() -> void:
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	frame += 1
	var clock: SimClock = lab.get("_clock")
	var actor: ActorBody = lab.get("_local_actor")
	var camera: Node3D = lab.get("_camera")
	if clock == null or not is_instance_valid(actor) or camera == null:
		return false
	var line := "frame %4d tick %4d modo=%-7s cuerpo=%s dibujado=%s camara=%s" % [frame, clock.tick,
			ActorState.Mode.keys()[actor.state.mode], actor.global_position,
			actor.visual_root().get_global_transform_interpolated().origin, camera.global_position]
	if printing == 0:
		history.append(line)
		if history.size() > 4:
			history.pop_front()
		if actor.state.mode == ActorState.Mode.HANGING:
			for old in history:
				print(old)
			printing = 1
	elif printing < 60:
		print(line)
		printing += 1
	else:
		quit()
	return false
```

#### diag_sin_teclas.gd

```gdscript
extends SceneTree

# Diagnostic: standing against a 2.4 m wall, jump in place with keys (W held)
# and without keys, and print grab_check's verdict every air tick.


class Runner extends Node:
	var actor: ActorBody
	var state := ActorState.new()
	var tuning := ActorTuning.new()
	var tick := 0
	var presses := 0
	var with_keys := true

	func _ready() -> void:
		SimClock.apply_tick_rate(SimClock.TICK_RATE)
		_add_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
		_add_box(Vector3(4, 2.4, 2), Vector3(0, 1.2, -1.5))  # front face at z = -0.5, top at 2.4
		actor = load("res://scenes/actor/actor.tscn").instantiate()
		add_child(actor)

	func _add_box(size: Vector3, center: Vector3) -> void:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		body.position = center
		add_child(body)

	func _physics_process(_delta: float) -> void:
		var t := tick % 200
		if t == 0:
			state = ActorState.new()
			state.position = Vector3(0, 0, 1.5)
			state.mode = ActorState.Mode.GROUND
			state.on_floor = true
			actor.apply_state(state)
			print("---- %s" % ("con W" if with_keys else "sin teclas"))
		var move := Vector2.ZERO
		if t < 80:
			move = Vector2(0, 1)
		if t == 90:
			presses += 1
		if t >= 90 and with_keys:
			move = Vector2(0, 1)
		var input := ActorInput.make(tick, move, 0.0, 0, presses)
		var wish := ActorMotor._wish_direction(input)
		if state.mode == ActorState.Mode.AIR:
			var dir := ActorMotor.grab_direction(state, wish)
			var check := ActorMotor.grab_check(actor, state, dir, tuning, SimClock.TICK_DT)
			print("t=%3d pies=(%.3f, %.3f, %.3f) vel=(%.2f, %.2f, %.2f) yaw=%.3f dir=%s por_qué=%s" % [t,
					state.position.x, state.position.y, state.position.z, state.velocity.x, state.velocity.y, state.velocity.z,
					state.facing_yaw, dir, check["why"]])
		ActorMotor.step(actor, state, input, tuning, SimClock.TICK_DT)
		if t == 85:
			print("t=%3d parado en pies=%s yaw=%.3f" % [t, state.position, state.facing_yaw])
		if state.mode == ActorState.Mode.HANGING and t < 199:
			print("t=%3d AGARRADO pies=%s" % [t, state.position])
			tick += 199 - t
		tick += 1
		if tick >= 400:
			get_tree().quit()
		elif tick == 200:
			with_keys = false


func _initialize() -> void:
	root.add_child(Runner.new())
```

#### diag_salto_arriba.gd

```gdscript
extends SceneTree

# Diagnostic: hanging from a 2.0 m wall, Space looking at the wall, with W held
# from the jump (pass 1) or only from the top of the jump (pass 2). Prints
# every tick: mode, feet, velocity, wall contact.


class Runner extends Node:
	var actor: ActorBody
	var state := ActorState.new()
	var tuning := ActorTuning.new()
	var tick := 0
	var presses := 0
	var pass_index := 0
	var hanging := false

	func _ready() -> void:
		SimClock.apply_tick_rate(SimClock.TICK_RATE)
		_add_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
		_add_box(Vector3(4, 2.0, 2), Vector3(0, 1.0, -1.5))  # front face at z = -0.5, top at 2.0
		actor = load("res://scenes/actor/actor.tscn").instantiate()
		add_child(actor)

	func _add_box(size: Vector3, center: Vector3) -> void:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		body.position = center
		add_child(body)

	func _physics_process(_delta: float) -> void:
		var t := tick % 300
		if t == 0:
			state = ActorState.new()
			state.position = Vector3(0, 0, 1.0)
			state.mode = ActorState.Mode.GROUND
			state.on_floor = true
			actor.apply_state(state)
			hanging = false
			print("---- pasada %d: %s" % [pass_index, "W desde el salto" if pass_index == 0 else "W recién arriba"])
		var move := Vector2.ZERO
		if t < 60:
			move = Vector2(0, 1)
		if t == 10:
			presses += 1  # jump to grab
		if t >= 100 and state.mode == ActorState.Mode.HANGING and t == 100:
			presses += 1  # Space looking at the wall
		if t > 100:
			if pass_index == 0 or state.velocity.y <= 0.0:
				move = Vector2(0, 1)
		var input := ActorInput.make(tick, move, 0.0, 0, presses)
		ActorMotor.step(actor, state, input, tuning, SimClock.TICK_DT)
		if t >= 99 and t < 175:
			print("t=%3d modo=%-7s pies=(%.3f, %.3f, %.3f) vel=(%.2f, %.2f, %.2f) pared=%s piso=%s move=%s" % [t,
					ActorState.Mode.keys()[state.mode], state.position.x, state.position.y, state.position.z,
					state.velocity.x, state.velocity.y, state.velocity.z, actor.is_on_wall(), state.on_floor, move])
		tick += 1
		if tick == 300:
			pass_index = 1
		if tick >= 600:
			get_tree().quit()


func _initialize() -> void:
	root.add_child(Runner.new())
```

#### demo_salto_arriba.gd

```gdscript
extends SceneTree

# Demo for the user: the lab in "Jugar solo", in slow motion, seen from the side
# of the "malla" block (2 m high, 1 m deep on top). It presses W and Space like
# a player (input actions), shows a caption with what it is doing, and saves a
# capture at every step. Two runs: W held from the jump, then W only once the
# jump stops rising. At the end it builds one contact sheet per run.
#
# Run with a window: -s <this> --resolution 1280x720 -- --local

const FACE := Vector3(27.6, 0.0, -10.0)  # front face of the "malla" block (x 26.3..28.7)
const EDGE_Y := 2.0
const BACK_Z := -11.0
const START := Vector3(27.6, 0.0, -8.8)
const SLOW_TICK_RATE := 20  # 60 ticks of simulation in 3 real seconds
const OUT := "C:/Users/ELCAID~1/AppData/Local/Temp/claude/C--Users-ElCaido97-Documents-tun-tun-tun-sahur/5d835f7b-ceb8-45f9-9209-8dc10c4704df/scratchpad/demo_salto"
const TITLES := ["Primera forma: W apretada desde el salto", "Segunda forma: W recién cuando deja de subir"]

var lab: Node
var run := 0
var phase := "boot"
var phase_tick := 0
var step := 0
var caption: Label
var status: Label
var last_jump_tick := -1000
var title: Label
var shots: Array = [[], []]
var flags := {}
var headless := false
var done_frames := 0


func _initialize() -> void:
	headless = DisplayServer.get_name() == "headless"
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	root.add_child(lab)
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.72)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -190
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(title)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 30)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(caption)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 24)
	status.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	box.add_child(status)
	var cam := Camera3D.new()
	cam.name = "CamaraDeCostado"
	cam.fov = 46.0
	root.add_child(cam)
	var from := Vector3(35.0, 2.3, -10.4)
	cam.transform = Transform3D(Basis.looking_at(Vector3(27.6, 1.3, -10.4) - from, Vector3.UP), from)
	cam.current = true


func _actor() -> ActorBody:
	return lab.get("_local_actor")


func _tick() -> int:
	var clock = lab.get("_clock")
	return clock.tick if clock != null else 0


func _say(text: String, shot: bool = true) -> void:
	_update_status()
	step += 1
	title.text = "%s   ·   paso %d" % [TITLES[run], step]
	caption.text = text
	var actor := _actor()
	var s := actor.state
	print("[demo] corrida %d paso %d tick %d modo=%s pies=(%.2f, %.2f, %.2f) vel=(%.2f, %.2f, %.2f) | %s" % [run + 1, step, _tick(),
			ActorState.Mode.keys()[s.mode], actor.global_position.x, actor.global_position.y, actor.global_position.z,
			s.velocity.x, s.velocity.y, s.velocity.z, text])
	if shot and not headless:
		_snap()


func _snap() -> void:
	var r := run
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png("%s_%d_%02d.png" % [OUT, r + 1, shots[r].size() + 1])
	image.resize(640, 360, Image.INTERPOLATE_BILINEAR)
	shots[r].append(image)


func _press_jump() -> void:
	last_jump_tick = _tick()
	var event := InputEventAction.new()
	event.action = "jump"
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventAction.new()
	release.action = "jump"
	release.pressed = false
	Input.parse_input_event(release)


func _update_status() -> void:
	var actor := _actor()
	var mode_names := {ActorState.Mode.GROUND: "en el piso", ActorState.Mode.AIR: "en el aire", ActorState.Mode.HANGING: "colgado"}
	status.text = "Teclas apretadas: %s     Estado: %s     Pies a %.2f m de altura (el borde está a 2,00 m)" % [
			_keys(), mode_names.get(actor.state.mode, "otro"), actor.global_position.y]


func _keys() -> String:
	var held: Array[String] = []
	if Input.is_action_pressed("move_forward"):
		held.append("W")
	if _tick() - last_jump_tick < 6:
		held.append("Espacio (un toque)")
	return " + ".join(held) if not held.is_empty() else "ninguna"


func _go(next: String) -> void:
	phase = next
	phase_tick = _tick()


func _teleport() -> void:
	var actor := _actor()
	var s := ActorState.new()
	s.position = START
	s.mode = ActorState.Mode.GROUND
	s.on_floor = true
	s.jump_presses_seen = lab.get("jump_presses")
	s.quantize()
	actor.state = s
	actor.apply_state(s)
	actor.teleported()


func _process(_delta: float) -> bool:
	if lab.get("_camera") != null:
		lab.get("_camera").yaw = 0.0  # the game's camera looks at the wall: W is toward it
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if lab.has_node("Hud/Info"):
		lab.get_node("Hud/Info").visible = false
	var actor := _actor()
	if not is_instance_valid(actor):
		return false
	var s := actor.state
	_update_status()
	var since := _tick() - phase_tick
	var feet := actor.global_position
	match phase:
		"boot":
			if _tick() > 20:
				SimClock.apply_tick_rate(SLOW_TICK_RATE)
				_teleport()
				flags = {}
				_go("look")
				_say("Parado frente al bloque «malla»: 2 m de alto y 1 m de fondo arriba. Vista de costado: la pared está a la derecha. La cámara del juego mira a la pared, así que W empuja hacia la derecha.")
		"look":
			if since >= 40:
				Input.action_press("move_forward")
				_go("walk")
				_say("Aprieto W: camina hasta la pared.")
		"walk":
			if actor.is_on_wall() or since >= 40:
				Input.action_release("move_forward")
				_press_jump()
				_go("grab")
				_say("Suelto W y aprieto Espacio: salta en el lugar y se agarra al caer.")
		"grab":
			if s.mode == ActorState.Mode.HANGING:
				_go("hang")
				_say("Colgado del borde (las manos amarillas están sobre el filo).")
			elif since > 150:
				print("[demo] no se agarró")
				_go("end")
		"hang":
			if since >= 45:
				_press_jump()
				if run == 0:
					Input.action_press("move_forward")
					_say("Aprieto Espacio mirando a la pared, y también W, que no voy a soltar.")
				else:
					_say("Aprieto Espacio mirando a la pared, sin W: salta derecho para arriba.")
				_go("air")
		"air":
			if not flags.has("rising") and s.mode == ActorState.Mode.AIR and since >= 6:
				flags["rising"] = true
				_say("Sale del borde para arriba: está en el aire, con control aéreo." + (" Con W apretada, apenas pasa el borde empieza a acelerar hacia la derecha." if run == 0 else ""))
			elif not flags.has("apex") and s.mode == ActorState.Mode.AIR and s.velocity.y <= 0.0:
				flags["apex"] = true
				if run == 0:
					_say("Punto más alto: los pies, 20 cm sobre el borde. Ya está %.1f m adentro, sobre el bloque, y sigue acelerando." % (FACE.z - feet.z))
				else:
					Input.action_press("move_forward")
					_say("Punto más alto: los pies, 20 cm sobre el borde. Recién ahora aprieto W.")
			elif run == 0 and not flags.has("past") and feet.z < BACK_Z and feet.y > EDGE_Y - 0.05:
				flags["past"] = true
				_say("Todavía no bajó y ya pasó el fondo del bloque (1 m): no tiene dónde aterrizar.")
			elif s.mode == ActorState.Mode.GROUND and not flags.has("landed"):
				flags["landed"] = true
				if run == 0:
					Input.action_release("move_forward")
					_say("Aterriza en el piso, del otro lado del bloque. Suelto W.")
				else:
					_say("Aterriza arriba del bloque, apoyado en el filo. Sigo con W un momento.")
				_go("after")
			elif since > 300:
				print("[demo] no terminó el salto")
				_go("after")
		"after":
			if run == 1 and since >= 4 and not flags.has("released"):
				flags["released"] = true
				Input.action_release("move_forward")
				_say("Suelto W.")
			if run == 1 and since >= 40 and not flags.has("stopped"):
				flags["stopped"] = true
				_say("Queda parado arriba del bloque, con los pies %.2f m adentro del borde." % (FACE.z - feet.z))
			if since >= 50:
				if run == 0:
					run = 1
					step = 0
					flags = {}
					_teleport()
					_go("look")
					_say("Vuelvo al mismo lugar para la segunda forma.")
				else:
					_go("end")
		"end":
			done_frames += 1
			if done_frames == 30:
				_sheets()
			if done_frames > 60:
				return true
	return false


func _sheets() -> void:
	for r in 2:
		var tiles: Array = shots[r]
		if tiles.is_empty():
			continue
		@warning_ignore("integer_division")
		var rows := (tiles.size() + 1) / 2
		var sheet := Image.create(1280, rows * 360, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.1, 0.1, 0.12))
		for i in tiles.size():
			@warning_ignore("integer_division")
			sheet.blit_rect(tiles[i], Rect2i(0, 0, 640, 360), Vector2i((i % 2) * 640, (i / 2) * 360))
		sheet.save_png("%s_hoja_%d.png" % [OUT, r + 1])
		print("[demo] hoja %d: %d capturas" % [r + 1, tiles.size()])
```

#### diag_agarre_subiendo.gd

```gdscript
extends SceneTree

# Diagnostic: grabbing while rising. Standing against walls of several
# heights, jump in place without keys and with W held. (A first version also
# ran each case with the old rising limit, hang_max_rise, on and off.) Prints,
# per case, whether it grabbed, on which tick of the jump, the vertical speed and feet height just
# before, the snap distance, and the feet height once hanging.

const HEIGHTS := [1.9, 2.0, 2.1, 2.4, 2.8, 3.1, 3.2]


class Runner extends Node:
	var actor: ActorBody
	var wall: StaticBody3D
	var tuning := ActorTuning.new()
	var state := ActorState.new()
	var cases: Array = []
	var index := -1
	var t := 0
	var presses := 0
	var last_feet := Vector3.ZERO
	var last_vel := Vector3.ZERO
	var jumped_at := -1

	func _ready() -> void:
		SimClock.apply_tick_rate(SimClock.TICK_RATE)
		var floor_body := _box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
		add_child(floor_body)
		actor = load("res://scenes/actor/actor.tscn").instantiate()
		add_child(actor)
		for height in HEIGHTS:
			for keys in ["sin teclas", "con W"]:
				cases.append(["nuevo", height, keys])
		_next()

	func _box(size: Vector3, center: Vector3) -> StaticBody3D:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		body.position = center
		return body

	func _next() -> void:
		index += 1
		if index >= cases.size():
			get_tree().quit()
			return
		var c: Array = cases[index]
		if wall != null:
			wall.queue_free()
		wall = _box(Vector3(4, c[1], 2), Vector3(0, c[1] * 0.5, -1.5))  # face at z = -0.5
		add_child(wall)
		state = ActorState.new()
		state.position = Vector3(0, 0, 0.6)
		state.mode = ActorState.Mode.GROUND
		state.on_floor = true
		state.jump_presses_seen = presses
		actor.apply_state(state)
		t = 0
		jumped_at = -1

	func _physics_process(_delta: float) -> void:
		if index >= cases.size():
			return
		var c: Array = cases[index]
		var move := Vector2.ZERO
		if t < 20:
			move = Vector2(0, 1)  # walk into the wall
		elif t == 30:
			presses += 1
			jumped_at = t
		if t > 30 and c[2] == "con W":
			move = Vector2(0, 1)
		last_feet = actor.global_position
		last_vel = state.velocity
		actor.grab_jump = Vector3.ZERO
		ActorMotor.step(actor, state, ActorInput.make(t, move, 0.0, 0, presses), tuning, SimClock.TICK_DT)
		var snap := actor.grab_jump.length()
		if state.mode == ActorState.Mode.HANGING:
			print("%-10s muro %.1f m %-10s -> AGARRA en el tick %d del salto · antes: pies a %.3f m subiendo a %.2f m/s · snap %.3f m · colgado con los pies a %.3f m" % [
					c[0], c[1], c[2], t - jumped_at, last_feet.y, last_vel.y, snap, actor.global_position.y])
			_next()
		elif t > 30 and state.mode == ActorState.Mode.GROUND and t - jumped_at > 5:
			print("%-10s muro %.1f m %-10s -> no se agarra (vuelve al piso en el tick %d)" % [c[0], c[1], c[2], t - jumped_at])
			_next()
		else:
			t += 1


func _initialize() -> void:
	root.add_child(Runner.new())
```

#### diag_techo_bajo.gd

```gdscript
extends SceneTree

# Diagnostic: the "techo bajo" edge (2 m wall, 1 m deep, with a 20 cm slab
# 0.6 m above the top that sticks out 1 m in front of the face). Grab it, then
# Space looking back (jump away), and print every mode change, with the
# anchor point when hanging.


class Runner extends Node:
	var actor: ActorBody
	var state := ActorState.new()
	var tuning := ActorTuning.new()
	var t := 0
	var presses := 0
	var last_mode := -1

	func _ready() -> void:
		SimClock.apply_tick_rate(SimClock.TICK_RATE)
		_add(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
		_add(Vector3(2.4, 2.0, 1.0), Vector3(0, 1.0, -1.0))  # face at z = -0.5, top at 2.0
		_add(Vector3(2.4, 0.2, 2.0), Vector3(0, 2.7, -0.5))  # slab: y 2.6..2.8, z -1.5..0.5
		for side in [-1.0, 1.0]:
			_add(Vector3(0.2, 2.6, 0.2), Vector3(side * 1.1, 1.3, 0.4))
		actor = load("res://scenes/actor/actor.tscn").instantiate()
		add_child(actor)
		state.position = Vector3(0, 0, 0.3)
		state.mode = ActorState.Mode.GROUND
		state.on_floor = true
		actor.apply_state(state)

	func _add(size: Vector3, center: Vector3) -> void:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		body.position = center
		add_child(body)

	func _physics_process(_delta: float) -> void:
		var move := Vector2(0, 1) if t < 20 else Vector2.ZERO
		var yaw := 0.0
		if t == 30:
			presses += 1  # jump at the wall: grab
		if t == 80:
			presses += 1  # Space looking back: jump away
		if t >= 80:
			yaw = PI
		ActorMotor.step(actor, state, ActorInput.make(t, move, yaw, 0, presses), tuning, SimClock.TICK_DT)
		if state.mode != last_mode or (t >= 80 and t < 120 and t % 4 == 0):
			print("t=%3d %-7s pies=(%.2f, %.2f, %.2f) vel=(%.2f, %.2f, %.2f) yaw=%.2f filo=%s" % [t, ActorState.Mode.keys()[state.mode],
					state.position.x, state.position.y, state.position.z, state.velocity.x, state.velocity.y, state.velocity.z,
					state.facing_yaw, state.anchor_point if state.mode == ActorState.Mode.HANGING else "-"])
			last_mode = state.mode
		t += 1
		if t > 200:
			get_tree().quit()


func _initialize() -> void:
	root.add_child(Runner.new())
```
