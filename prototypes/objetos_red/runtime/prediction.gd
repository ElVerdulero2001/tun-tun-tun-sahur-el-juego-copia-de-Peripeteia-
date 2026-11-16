extends RefCounted

## Reconciliación experimental sin replay. La historia guarda resultados
## físicos observados, sin reescribirlos para aparentar concordancia.
const HISTORY_LIMIT := 180
var active := false
var start_tick := 0
var correction_barrier := -1
var history := {}

func begin(tick: int) -> void:
	active = true
	start_tick = tick
	correction_barrier = -1
	history.clear()

func observe(sample, contacts: int) -> void:
	if not active:
		return
	history[sample.tick] = {"state": sample.copy(), "contacts": contacts}
	while history.size() > HISTORY_LIMIT:
		history.erase(history.keys()[0])

func reconcile(sample, body, now: int) -> Dictionary:
	if not active or sample.tick < start_tick or sample.tick < correction_barrier:
		return {"status": "outside_history"}
	if not history.has(sample.tick):
		return {"status": "missing_history"}
	var previous = history[sample.tick].state
	if previous.epoch != sample.epoch or previous.revision != sample.revision:
		return {"status": "different_transition"}
	var distance: float = previous.pose.origin.distance_to(sample.pose.origin)
	var angle: float = previous.pose.basis.get_rotation_quaternion().angle_to(sample.pose.basis.get_rotation_quaternion())
	if distance < 0.005 and angle < deg_to_rad(0.5) and previous.lv.distance_to(sample.lv) < 0.02:
		return {"status": "same", "distance": distance, "angle": angle}
	# Un contacto posterior impide transportar el error como si el intervalo
	# siguiera siendo vuelo libre. Esperar recuperación autoritativa explícita.
	for tick: int in history:
		if tick >= sample.tick and history[tick].contacts > 0:
			return {"status": "contact_recovery_required", "distance": distance, "angle": angle}
	var delta: Transform3D = sample.pose * previous.pose.affine_inverse()
	if not body.safe_correction(delta, sample.lv - previous.lv, sample.av - previous.av):
		return {"status": "blocked_recovery_required", "distance": distance, "angle": angle}
	# Las muestras anteriores a la aplicación todavía no contienen el efecto
	# de esta corrección. No volver a aplicar el mismo error sobre ellas.
	correction_barrier = now
	return {"status": "corrected", "distance": distance, "angle": angle}

func stop() -> void:
	active = false
	history.clear()
