# Temblor de objetos sostenidos en el invitado: diagnóstico y corrección

Fecha: 2026-11-15. Implementado sobre la rama `net-lab-auditoria-hitbox`, HEAD `677086f`, **conservando las modificaciones locales que ya había**. Sin commit ni push.

**Nueva prueba posterior del usuario:** el `kavi.txt` actualizado y el video `2026-11-15 22-42-27.mp4` muestran problemas de suelta/caída y trayectoria. El análisis está en [diagnostico_suelta_y_lanzamiento_objetos.md](diagnostico_suelta_y_lanzamiento_objetos.md). Las comprobaciones de este informe no cubrían un rebote falso posterior al contacto ni la equivalencia completa de esas trayectorias; no deben interpretarse como validación de toda la sincronización de objetos.

## Evidencia utilizada

- El único video de `C:\Users\ElCaido97\Documents\otro proyecto bobo\capturas`, `2026-11-15 18-13-53.mp4`: 20,87 s, 1280 × 720, 30 FPS. El invitado sostiene la caja de herramientas cerca del banquito y el piso.
- Las notas de prueba `kavi.txt`, los documentos de físicas, inventario y laboratorio y los cambios locales contra HEAD.
- Los mensajes de la sesión local de Claude vinculada a este repositorio. En este entorno sí estaban disponibles en `.claude/projects` del perfil del usuario; no se accedió a su cuenta web.
- El registro de la partida real del host: el objeto 6 recibió rechazos **«tocó otro objeto»** en los ticks 4782, 4786 y 4790, con versiones 1, 2 y 3. Ese rechazo puede ser necesario durante un contacto real; por sí solo el registro no demuestra cuál de los siguientes defectos produjo cada salto del video.
- Reproducciones con Godot **4.7.2**, Jolt, host y cliente en procesos separados. Se hicieron mediciones antes de cambiar el código.

## 1. Un choque anterior podía seguir invalidando la trayectoria corregida

**Dónde:** `scripts/inventory/inv_bodies.gd`, `_judge_holds`, `_judge_claim` y `_claim_path`.

El host recordaba el último contacto en `touched` y la última coincidencia/adopción en `agreed`. Ante un rechazo subía `version`, pero no renovaba ese punto de partida. El cliente recibía la versión nueva, incorporaba la respuesta física y repetía sus ticks; aun así, la siguiente afirmación podía rechazarse por un contacto anterior a esa corrección. Solo se recuperaba si alguna afirmación volvía a coincidir casi exactamente con el host, por la salida anticipada «igual».

**Corrección:** hay un `checkpoint` explícito, con tick y pose, que se establece al agarrar, al coincidir/adoptar y al imponer una corrección. El camino de adopción y la protección de contactos parten de ese checkpoint. Un contacto nuevo sigue rechazando la trayectoria que borraría su respuesta física; una versión anterior sigue rechazada. No se relajan las tolerancias ni se elimina la validación del recorrido.

## 2. Una corrección nueva borraba el suavizado pendiente

**Dónde:** `scripts/inventory/inv_hands.gd`, `_reconcile` y `_predict_free`.

El suavizado se calculaba desde la pose simulada anterior, que no siempre era lo que se estaba dibujando: podía quedar parte de una corrección visual en curso. Reemplazar ese desplazamiento por otro hacía saltar la copia cada vez que llegaba una corrección antes de terminar la anterior. También ocurría con lo recién soltado.

**Corrección:** cada transición parte de `_shown`, la última pose realmente dibujada, y conserva posición y giro alrededor del anclaje correspondiente. La trayectoria simulada y las afirmaciones que valida el host siguen siendo independientes de este suavizado visual.

Esto incluye **soltar o lanzar mientras todavía se suavizaba una corrección**. `_end_local` cancelaba el suavizado pendiente, así que el primer tick de caída volvía a la pose cruda. Ahora se conserva la pose visible y se cambia el pivote al centro de masa para continuar la caída. Dos comprobaciones específicas fallaban antes (se perdían 10 cm de corrección lateral) y pasan después.

La prueba inicial de siete comprobaciones fallaba en cuatro: el contacto ya corregido y tres correcciones visuales consecutivas. La primera perdía **15 cm y 5,73°** del desplazamiento pendiente. Después del cambio conserva la pose dibujada dentro de la precisión numérica.

## 3. Contra el piso se descartaba todo el suavizado

**Dónde:** `InvHands._show`.

Si la pose suavizada tocaba el nivel, se descartaba entera y se dibujaba la pose cruda. En una caja presionada contra otro cuerpo y cerca del piso, eso alternaba entre el dibujo suavizado y la posición corregida por el host. Corregir únicamente el punto 2 no alcanzó: la reproducción en red seguía dando saltos cuando el suavizado intentaba bajar por el piso.

**Corrección:** `_visual_step` recorre desde la pose dibujada hasta la deseada con la misma comprobación geométrica de `InvHoldMotion.path_free`. Si el recorrido está bloqueado, conserva su tramo libre con ocho bisecciones. Se comprueba el camino completo, también cuando acaba el suavizado: dos extremos libres a lados opuestos de una pared fina no permiten cruzarla. No se sustituyen los choques de Jolt ni se envía la pose visual como afirmación física.

La reproducción anterior al arreglo midió **108,40 mm** de salto añadido por una corrección; otras ejecuciones intermedias confirmaron que el descarte contra el piso podía superar esa cifra. La regresión mide el salto añadido por el suavizado, separado del movimiento normal de ese tick y de su recorte legítimo contra el nivel.

## 4. Los inputs con objeto sostenido excedían el MTU

**Dónde:** `scripts/net/net_sync.gd`, `send_ticks` y `input_packets`.

Sin consumibles pendientes, seis registros con input, mano, afirmación del objeto y estado del personaje ocupaban **1437 bytes** de payload; ENet avisaba de un envío de **1440 bytes**, mayor que su MTU de **1392**. Es un defecto adicional del transporte; no se atribuye todo el temblor a este aviso.

**Corrección:** se serializa cada registro y se distribuyen todos los registros en datagramas de hasta **1200 bytes de payload**, sin reducir los seis ticks de redundancia. Se incluyen los usos pendientes en el cálculo. El receptor ya acepta paquetes independientes por tick y conserva su formato. Sin registros sigue saliendo el heartbeat de tres bytes.

Se agrupan **primero los ticks más recientes con sus predecesores inmediatos**. Esto importa para el reloj, que calcula su margen con el input más nuevo recibido: separar ese input en un paquete pequeño mientras sus predecesores siguen en otro, más antiguo, puede dar un margen optimista con jitter. Es una precaución del empaquetado; no se atribuyen a ella todos los fallos intermitentes de las pruebas.

Además, `_accept_inputs` conserva la revisión más nueva de un mismo tick y una misma sujeción (`is_older_hold_claim`). Antes, un duplicado atrasado podía sobrescribir un registro ya corregido con otro de versión anterior. La comparación es modular, incluyendo el paso de 255 a 0; no mezcla sesiones ni omite la validación física del host. Esta propiedad tiene una regresión específica con registros reenviados en orden inverso.

## 5. La mano podía empezar antes que los inputs del jugador

**Dónde:** `InvHands._active`, `predict` y la preparación de las pruebas en pareja.

Al entrar, el cliente ya podía tener personaje e inventario aunque el reloj todavía no se hubiera sincronizado. La mano admitía el agarre y `after_tick` predecía el objeto, pero el laboratorio aún no enviaba inputs del jugador. El host recibía el GRAB confiable, sostenía el objeto sin recibir los objetivos nuevos y terminaba corrigiendo por «sin acuerdo». Una reproducción registró el primer sincronizado recién en el tick 458, después de comenzar a mover la caja.

**Corrección:** la mano se habilita y predice cuando el actor local ya está simulado y, si usa sincronización de cliente, su reloj está listo. Las pruebas esperan la misma condición; no esperan una cantidad arbitraria de segundos. Se comprueba que la mano está bloqueada antes de simular y se habilita después.

### Cómo interpretar las corridas con pérdida alta

En algunas repeticiones ENet redujo su `PEER_PACKET_THROTTLE` hasta **2/32**, además del perfil configurado de 5 % de pérdida. Por lo tanto, «+200 ms y 5 %» no describe por sí solo la entrega efectiva de esas corridas. Se midió el throttle; no se desactivó el control de congestión del motor ni se relajaron las validaciones de adopción.

Exigir cero correcciones durante un giro con inputs que no llegan no era una prueba válida. La regresión definitiva exige que el suavizado no añada saltos, que al parar host y predicción coincidan durante **30 ticks consecutivos** (menos de 2 cm y 2°), que el host recupere adopciones/coincidencias y que la versión se estabilice. El plazo de recuperación es de cinco segundos sin apagar el simulador. La prueba determinista del apartado 1 sigue comprobando que un contacto ya incorporado deja de rechazarse; esa comprobación no se debilitó.

## Verificación

La regresión permanente es `scenes/net_lab/inventario/pruebas/inv_hold_contact_test.tscn`. Reutiliza el laboratorio y las herramientas de `inv_fisica_test`:

- sin argumentos de pareja: checkpoint del choque, rechazo de versión vieja y contacto nuevo, correcciones consecutivas con posición y giro, transición contra piso y pared fina, presupuesto de paquetes, lectura íntegra de los seis ticks con y sin mano y con cero u ocho usos pendientes, orden inverso de revisiones, heartbeat y disponibilidad de inputs;
- `--fisica-pair=mano_host` / `mano_cliente`: una caja sobre otra, contacto real de Jolt, presión hacia abajo, retirada y giro en el aire. Comprueba la continuidad visual durante las correcciones y, al parar, la coincidencia sostenida de host y predicción y la recuperación de la adopción.

Resultados de las corridas, con la excepción intermitente indicada expresamente:

| Prueba | Perfil | Comprobaciones | Fallas |
| --- | --- | ---: | ---: |
| Regresión nueva, un proceso | Sin red | 108 | 0 |
| Regresión nueva, contacto real | Sin latencia añadida | Host 5, invitado 5 | 0 |
| Regresión nueva, contacto real | +200 ms, ±40 ms, 5 % de pérdida, semillas 1 a 6 | Host 5, invitado 5 por semilla | 0 |
| `inv_fisica_test`, recorrido completo | Un proceso | 248 | 0 |
| `inv_fisica_test`, mano en red | Sin latencia añadida | Host 14, invitado 31 | 0 |
| `inv_fisica_test`, mano en red | +200 ms, ±40 ms, 5 % de pérdida | Host 14, invitado 31 | 0 en la última pasada; 1 intermitente previa en la pila |
| `inv_fisica_test`, tres procesos | A con red mala, B entra a los 30 s | Host 13, A 12, B 8 | 0 |

La reproducción final del contacto sin latencia añadida midió **0,02 mm** de salto visual añadido en doce correcciones, frente a **108,40 mm** en la reproducción anterior al arreglo. No es una medida del movimiento normal del objeto ni de la distancia entre su predicción y el host. Las correcciones necesarias durante un contacto real siguen existiendo. En las seis semillas de la serie final, al parar hubo coincidencia sostenida, con una diferencia final máxima informada de **0,1 mm**, y ninguna corrección adicional en el tramo de giro libre. Los registros de esa serie son `stable-seed-1` a `stable-seed-6`; sin latencia añadida, `stable-contact-normal`.

El recorrido existente verifica además la tabla agarrada por la punta, el lanzamiento, la pared fina, lo soltado de 2,16 m, el despertar de pilas, la recogida de su apoyo y la suelta por ocultación. Sin latencia añadida, los giros libres a 180, 360 y 720 °/s no necesitaron correcciones. Con red mala hubo tanto corridas sin correcciones como otras con correcciones y diferencias transitorias al faltar inputs; no se presentan como equivalencia perfecta durante todo el giro. No hubo nuevos avisos de MTU después de dividir los paquetes.

El motor escribe `Failed to read the root certificate store` al iniciar dentro de este entorno, tanto antes como después de los cambios. Se conserva en los registros y no se contabiliza como un fallo de las comprobaciones del juego; no hubo errores de script en las corridas finales. `git diff --check` también pasó.

El último ajuste de continuidad al soltar está comprobado en `release-transition-after` (**108/108**) y en `release-hand-normal` / `release-hand-bad` (**host 14/14 e invitado 31/31 en ambos**), además de `release-contact` con la semilla 4 y red mala (**5/5 y 5/5**). La revisión de tres procesos está en `stable-three` (**13/13, 12/12 y 8/8**).

**Excepción que no se da por resuelta:** en `stable-hand-bad`, al recoger el apoyo de una pila desde el invitado, lo de arriba comenzó a caer **5 ticks antes** de desaparecer el apoyo (unos 83 ms); la prueba admite 4. El host pasó 14/14 y el invitado 30/31. La repetición `stable-hand-bad-repeat` pasó 14/14 y 31/31 con el mismo perfil. La lógica de `_waits_for_fall`, `gone_ticks` y el despertar de pilas no fue modificada en esta corrección; aun así, no se atribuye automáticamente el resultado al código previo sin una comparación aislada. Queda registrado como un límite intermitente de esa sincronización, separado de la continuidad visual del objeto sostenido. No se elevó el umbral de la prueba para ocultarlo.

Los registros y la copia del estado previo usados para comparar están en `tmp/gpt_physics_review/`. Son archivos de diagnóstico, no una dependencia del juego.

### Cómo repetir las pruebas

Usar el ejecutable principal de Godot 4.7.2 de esta PC y `--log-file` para separar los registros. La prueba solo admite `--fixed-fps 60` cuando corre sin red. En pareja se usa el tiempo real; ejecutar el host y el cliente en dos terminales distintas:

```powershell
$godot = 'C:\Users\ElCaido97\Downloads\cositas\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2.exe'

# Regresión de un proceso
& $godot --headless --fixed-fps 60 --path . --scene res://scenes/net_lab/inventario/pruebas/inv_hold_contact_test.tscn

# Regresión en dos procesos, iniciando primero el host
& $godot --headless --path . --scene res://scenes/net_lab/inventario/pruebas/inv_hold_contact_test.tscn -- --host --bind=127.0.0.1 --port=7824 --fisica-pair=mano_host
& $godot --headless --path . --scene res://scenes/net_lab/inventario/pruebas/inv_hold_contact_test.tscn -- --client --address=127.0.0.1 --port=7824 --fisica-pair=mano_cliente --sim-rtt=200 --sim-jitter=40 --sim-loss=5
```

En un entorno sin permiso para escribir `user://`, las pruebas aceptan `--fisica-prefs-path=RUTA_ABSOLUTA_ESCRIBIBLE`. Es un parámetro del arnés; el juego conserva su ubicación habitual de preferencias. La primera corrida de las 248 comprobaciones falló solamente en guardar y releer ese archivo; al dar una ruta de prueba dentro del proyecto, pasaron **248 de 248**.

## Alcance y prueba manual pendiente

Se verificó el caso reproducido y las regresiones indicadas, sin ventana y en esta PC. Falta repetir **el gesto del video en las dos máquinas físicas**, con sus tiempos de render y su red real. Los choques entre objetos siguen siendo del host: con latencia puede haber una discrepancia temporal respecto de otros cuerpos; este cambio corrige los reinicios y saltos de reconciliación, no convierte las copias del cliente en otra simulación autoritativa.

Antes de esa prueba, actualizar ambas copias con el mismo código (`actualizar_lab.bat` en la notebook): cambió la huella. Probar arrastrar la caja junto al banquito y al piso, levantarla, girarla, volver a apoyarla y soltarla; después repetir con Alt + 4. El host debe seguir resolviendo los choques y el invitado no debe alternar bruscamente entre dos poses por las correcciones.

No se cambiaron masas, fuerza de lanzamiento, cuerpos del catálogo, hitbox, Tuning ni ajustes de Jolt como parte de esta corrección. Los cambios de ese tipo que aparecen contra HEAD ya estaban en el árbol de trabajo al empezar.
