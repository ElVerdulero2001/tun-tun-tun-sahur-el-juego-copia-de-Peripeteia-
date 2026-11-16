extends RefCounted

## Observación de divergencias. La corrección por traslado de un error viejo
## fue refutada en F1/F3 y se retiró. No esconder la falta de reconciliación
## trasladando el cuerpo ni modificando la historia física.
const HISTORY_LIMIT := 180
var active := false
var start_tick := 0
var history := {}

func begin(tick: int) -> void:
	active = true
	start_tick = tick
	history.clear()

func observe(sample, contacts: int) -> void:
	if not active:
		return
	history[sample.tick] = {"state": sample.copy(), "contacts": contacts}
	while history.size() > HISTORY_LIMIT:
		history.erase(history.keys()[0])

func reconcile(sample, body, now: int) -> Dictionary:
	if not active or sample.tick < start_tick:
		return {"status": "outside_history"}
	if not history.has(sample.tick):
		return {"status": "missing_history"}
	var previous = history[sample.tick].state
	if previous.epoch != sample.epoch or previous.revision != sample.revision:
		return {"status": "different_transition"}
	var distance: float = previous.pose.origin.distance_to(sample.pose.origin)
	var angle: float = previous.pose.basis.get_rotation_quaternion().angle_to(sample.pose.basis.get_rotation_quaternion())
	if distance <= 0.002 and angle <= deg_to_rad(0.3) and previous.lv.distance_to(sample.lv) < 0.02:
		return {"status": "same", "distance": distance, "angle": angle}
	# Medir contactos también cuando no se aplica ninguna corrección.
	var contacted := false
	for tick: int in history:
		if tick >= sample.tick and history[tick].contacts > 0:
			contacted = true
			break
	var position_error: Vector3 = sample.pose.origin - previous.pose.origin
	var velocity_error: Vector3 = sample.lv - previous.lv
	return {"status": "model_blocked", "distance": distance, "angle": angle,
		"position_error": [position_error.x, position_error.y, position_error.z],
		"velocity_error": [velocity_error.x, velocity_error.y, velocity_error.z],
		"contact_since_source": contacted, "application_tick": now,
		"physical_correction": false, "current_tick": body.prepared_tick}

func stop() -> void:
	active = false
	history.clear()
