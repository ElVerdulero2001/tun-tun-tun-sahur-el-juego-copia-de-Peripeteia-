class_name TraversalExitReason
extends RefCounted

## Motivo de cierre de un TraversalLease (doc de arquitectura V0.3, sección 9).
##
## Fase 2 (PlayerMotor, sin controller) usaba dos valores genéricos:
##  - OWNER_RELEASED: el dueño llamó end_traversal() explícitamente.
##  - FORCED_NO_RENEWAL: el motor cerró el lease porque no llegó una
##    apply_traversal_pose() válida en el tick correspondiente.
##
## Fase 4 (TraversalController: FREE/ACQUIRE_LEDGE/HANGING) agrega los
## motivos concretos de sus propias transiciones:
##  - HANG_RELEASED: release voluntario desde HANGING (atrás o crouch).
##  - ACQUIRE_ABORTED: el jugador saltó durante ACQUIRE_LEDGE — mantle
##    todavía no existe, así que un salto ahí aborta, no transiciona.
##  - ACQUIRE_TIMEOUT: ACQUIRE_LEDGE tardó más que acquire_timeout_seg sin
##    llegar a HANGING.
##  - ACQUIRE_BLOCKED: apply_traversal_pose() devolvió BLOCKED o REJECTED
##    durante el acercamiento guiado. Mismo motivo para ambos: un REJECTED
##    del propio lease del controller sería una anomalía defensiva (nadie
##    más debería poder invalidarlo), no un caso alcanzable hoy.
##  - HANG_BLOCKED: apply_traversal_pose() devolvió BLOCKED mientras se
##    mantenía la pose anclada en HANGING — algo ocupó el espacio de la
##    pose de hang. Solo se usa cuando el lease TODAVÍA es válido en ese
##    momento (por eso el controller es quien lo cierra); si en cambio
##    apply_traversal_pose() devuelve REJECTED, el lease ya estaba
##    invalidado de otra forma y no hace falta (ni corresponde) volver a
##    cerrarlo con este motivo.
##
## Fase 5 (MANTLING) agrega:
##  - MANTLE_COMPLETED: la trayectoria de mantle llegó a la pose de
##    aterrizaje dentro de la tolerancia configurada.
##  - MANTLE_BLOCKED: apply_traversal_pose() devolvió BLOCKED durante el
##    mantle Y, al revalidar, la pose de hang tampoco sigue siendo válida
##    (sección 9.1: "hang ya inválido"). Si el mantle se bloquea pero el
##    hang SIGUE siendo válido, no hay cierre de lease — se vuelve a
##    HANGING con el mismo lease, así que ese caso no necesita un motivo
##    propio.
##
## Fase 6 (LADDER) agrega:
##  - LADDER_RELEASED: salida voluntaria por crouch, o por retroceso
##    específicamente en el extremo inferior sin neighbour_down (ahí
##    retroceder ya no significa "bajar" — no hay más abajo — así que se
##    trata como un release, igual que HANG_RELEASED). En cualquier otro
##    punto del recorrido, retroceso es movimiento normal (bajar), no salida.
##  - LADDER_JUMP_EXIT: salida por salto, con impulso horizontal en la
##    dirección de detector.aim_source (nunca una lectura global oculta) más
##    la vertical estándar de PlayerMotor.JUMP_VELOCITY.
##  - LADDER_BLOCKED: apply_traversal_pose() devolvió BLOCKED durante el
##    ascenso/descenso, o el segmento dejó de ser válido a mitad de camino.
##    Mismo motivo para ambos casos (mismo criterio que ACQUIRE_BLOCKED en
##    Fase 4: la recuperación del controller es idéntica para los dos). A
##    diferencia de MANTLING (sección 9.1), LADDER no revalida ni reintenta
##    acá — libera y vuelve a FREE directo, como pide esta fase. Si en
##    cambio apply_traversal_pose() devuelve REJECTED, el lease ya estaba
##    invalidado por otra vía y no corresponde volver a cerrarlo (mismo
##    criterio que HANG_BLOCKED/ACQUIRE_BLOCKED).
##
## Shimmy (desplazamiento lateral dentro de HANGING) no agrega motivos
## propios: un shimmy bloqueado no suelta al jugador ni cierra el lease,
## simplemente no avanza ese tick (sección 8) — no hay salida que nombrar.

enum Value {
	OWNER_RELEASED, FORCED_NO_RENEWAL, HANG_RELEASED, ACQUIRE_ABORTED,
	ACQUIRE_TIMEOUT, ACQUIRE_BLOCKED, HANG_BLOCKED, MANTLE_COMPLETED, MANTLE_BLOCKED,
	LADDER_RELEASED, LADDER_JUMP_EXIT, LADDER_BLOCKED,
}
