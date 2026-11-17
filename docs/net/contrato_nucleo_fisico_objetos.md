# Contrato del núcleo físico de objetos: siguiente candidato

2026-11-17. **Condiciones 1–3, signo del cero y adaptador local de la entrega 10 verificados independientemente en sus alcances. La entrega 11 añade autoridad por ámbito/revisión e invalidación/recuperación histórica.** [Revisión, evidencia y alcance](entregas/revision_codex_entrega_10.md). Esas interfaces siguen sin transporte ni conexión a las correcciones reales de NetSync; no aprueban la condición 4 completa. Múltiples manos, presentación, notebook y modelo de red completo también pendientes. [Decisión histórica del núcleo](entregas/revision_codex_entrega_5.md).

## Problema que debe resolver

El solver Rapier repite correctamente los contactos probados. Su integración Godot v0.36.0 mediante `StateManager3D` no ofrece aislamiento suficiente para este proyecto: carga el espacio entero, restaura IDs globales y adopta IDs del proceso de origen. Los fallos R3/R4 de Claude están reproducidos por Codex. La versión `main` consultada conserva las operaciones involucradas; cambiar de versión sin una corrección verificada no es una solución demostrada.

El candidato implementado en la entrega 8 es una **GDExtension acotada que posee mundos Rapier de objetos**, en lugar de usar `StateManager3D` para rebobinar el servidor físico global de Godot. Jolt conserva el personaje y los sistemas existentes. No se reconstruye el solver ni se añade otro servidor global: se encapsula Rapier con estado y ciclo de vida propios.

Esta elección conserva la separación por escenas: cada controlador del mundo de objetos posee su instancia nativa. No hay autoload de física ni memoria de simulación compartida entre partidas o predictores.

## Identidad y propiedad

- Cada instancia nativa posee sus cuerpos, formas, contactos, contador de IDs y snapshots. Restaurar una instancia no puede modificar otra ni el `PhysicsServer3D` de Godot.
- La identidad pública es `(uid, aparición)`, validada por el host. Un handle Rapier es interno al mundo que lo creó; nunca equivale a un RID o InstanceID de Godot.
- Los callbacks y consultas devuelven identidades públicas, no direcciones o IDs del proceso remoto.
- La instancia puede reemplazar atómicamente su mundo interno por el de un checkpoint compatible. El mapa de identidades públicas viaja con ese mundo; los bindings de presentación locales se resuelven otra vez sin importar nodos del origen.
- Crear cuerpos en otro orden o asignar otros IDs en Godot no cambia la identidad pública ni mezcla cuerpos. Reutilizar una identidad retirada requiere una aparición nueva.

## Estado y restauración

El checkpoint debe incluir el estado persistente que participa en el siguiente paso: cuerpos, velocidades, reposo, contactos, estructuras del solver y la relación entre esos datos y las identidades públicas. La prueba inicial debe demostrar que incluye lo necesario; un DTO de poses y velocidades por sí solo no cumple el contrato.

El formato añade versión, huella de parámetros/solver, tick físico, revisión de topología y manifiesto de cuerpos/formas. La primera fixture admite topología fija y rechaza cualquier cambio incompatible **antes de modificar** el mundo activo. Su extensión a altas/bajas e inventario es una etapa posterior explícita, no una tolerancia al fallo.

Importar un checkpoint implica validar límites de tamaño, identidad, configuración y topología, construir el estado candidato separado y sustituirlo solo al completar las comprobaciones. Un rechazo deja el mundo anterior íntegro. Un checkpoint no concede autoridad sobre el inventario ni sobre otros objetos.

La restauración local y la importación autorizada entre procesos comparten estas garantías. Los snapshots nativos solo proceden del host; un paquete de un invitado nunca se entrega directamente a un deserializador nativo. La validación del protocolo precede a la extensión.

## Tiempo, simulación y presentación

- La única operación que avanza el mundo es `step(dt, inputs_del_tick)`. Se prohíbe avanzar automáticamente ese mundo además del paso manual.
- Las acciones físicas se ejecutan una vez por tick de cada trayectoria simulada; los efectos externos se publican una vez por identidad de acción confirmada. Un replay físico necesita repetir el impulso, no el sonido o la transacción.
- La historia tiene límites explícitos de ticks, cuerpos, memoria y trabajo por actualización. Fuera de la historia disponible se solicita recuperación; no se reproduce desde el comienzo de la partida ni se bloquea indefinidamente el juego.
- La presentación recibe poses etiquetadas con identidad/tick. Su suavizado no se introduce otra vez en el solver como estado físico.
- El host y el invitado usan las mismas formas preparadas, masa, centro de masa, materiales y controlador de mano. Antes de integrar hay que comprobarlo con la tabla larga y el catálogo real.

## Relación con Jolt y el escenario

El primer prototipo exportará a ese mundo un contexto estático de piso y paredes con revisión conocida. Los objetos dinámicos del contexto pertenecen también al mundo nativo de objetos, con su propia identidad; un proxy cinemático retrasado no sustituye a un vecino dinámico durante el replay.

Los personajes continúan en Jolt y se conserva la regla actual de que los objetos no chocan físicamente con ellos. Los controles de alcance, aparición dentro de personajes y selección siguen siendo validaciones del juego. La representación del nivel en ambos sistemas debe proceder de la misma geometría preparada. Puertas, apoyos móviles, cambios de nivel y crecimiento de la isla requieren un contrato de contexto actualizado; no se declaran resueltos por la fixture inicial.

## Puerta de aceptación

Antes de sustituir el prototipo Jolt se exige una extensión compilada y pruebas independientes de:

1. Checkpoints durante contacto activo, reposo y despertar, con la misma sensibilidad y EPS de los ensayos actuales.
2. Dos mundos vivos, restauración de uno y creación/liberación posterior sin alterar consultas, IDs, contactos o trayectoria del otro.
3. Exportación/importación con órdenes de creación distintos, identidades de Godot diferentes y formas compatibles; rechazo atómico de manifiestos incompatibles.
4. El controlador real de agarre, suelta y lanzamiento y la reconciliación de una orden que llega tarde por ENet.
5. Tamaño de checkpoints, memoria y costo de replay medidos en la notebook objetivo. La igualdad observada en una PC no aprueba dos PC ni CPU diferentes.

Si una condición falla, se corrige este núcleo antes de agregar excepciones de altura, contacto o tipo de objeto al juego. Los casos R3/R4 originales se conservan como reproducción de la integración descartada; el nuevo núcleo necesita instrumentos adaptados a su API sin aflojar esos objetivos.
