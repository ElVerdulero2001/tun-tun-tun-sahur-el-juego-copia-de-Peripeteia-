extends Node

const LAB := preload("res://scenes/test/v3_hanging_detection_lab.tscn")


func _init() -> void:

	call_deferred("_run")


func _run() -> void:

	var lab := LAB.instantiate()
	get_tree().root.add_child(lab)
	var body := lab.get_node("H0Lab/PlayerH0Lab/Body") as V3PhysicsBody
	var detector := lab.get_node("HangingDetector") as V3HangingDetector
	var capture_probe := lab.get_node("HangingCaptureProbe") as V3HangingCaptureProbe

	for _frame in 30:
		await physics_frame
	assert(body.is_on_floor(), "Hanging lab: el body debe asentarse antes de probar")

	# El mismo borde debe existir geométricamente desde el piso, pero el
	# contrato prohíbe publicarlo como entrada válida mientras haya apoyo.
	body.global_position = Vector3(0.0, 0.0, 1.0)
	body.velocity = Vector3.ZERO
	for _frame in 3:
		await physics_frame
	assert(detector.last_candidate.wall_hit_count > 0, "Hanging lab: la grilla debe ver la pared de práctica")
	assert(not detector.last_candidate.is_valid, "Hanging lab: en piso nunca puede entrar a Hanging")
	assert(detector.last_candidate.rejection_reasons.has("en_piso"), "Hanging lab: el rechazo por piso debe ser explicable")
	assert(not capture_probe.last_zone_active, "Hanging lab: sin candidato válido las esferas de captura deben quedar ocultas")

	# En aire y sin dirección activa, el input es neutro: no bloquea el borde.
	body.global_position = Vector3(0.0, 0.45, 1.0)
	body.velocity = Vector3.ZERO
	await physics_frame
	assert(detector.last_candidate.intent_class == "neutra", "Hanging lab: sin input la intención debe ser neutra")
	assert(detector.last_candidate.is_valid, "Hanging lab: borde aéreo coherente debe publicar candidato válido")
	assert(capture_probe.last_zone_active, "Hanging lab: un candidato válido debe publicar las dos esferas")
	assert(capture_probe.last_sensor_distance_to_cylinder < INF, "Hanging lab: el sensor azul debe medir su distancia actual al cilindro")

	# Alejarse activamente del borde invalida la entrada aunque la geometría siga
	# siendo válida; no hay agarre magnético por cercanía.
	Input.action_press("move_back")
	await physics_frame
	assert(detector.last_candidate.intent_class == "contradictoria", "Hanging lab: retroceder debe clasificarse como intención contradictoria")
	assert(not detector.last_candidate.is_valid, "Hanging lab: la intención contradictoria debe bloquear Hanging")
	assert(detector.last_candidate.rejection_reasons.has("intencion_contradictoria"), "Hanging lab: el bloqueo de intención debe ser explicable")
	Input.action_release("move_back")

	# La interacción actual termina aquí: con un candidato válido, S entra en C.
	# P y el snap están aislados del laboratorio hasta diseñar el core Hanging.
	body.global_position = Vector3(0.0, 0.20, 0.86)
	body.velocity = Vector3.ZERO
	await physics_frame
	assert(detector.last_candidate.is_valid, "Hanging lab: la entrada de prueba debe conservar un candidato válido")
	assert(capture_probe.last_sensor_enters_cylinder, "Hanging lab: S debe entrar en C")

	print("V3 Hanging detection smoke test: OK")
	get_tree().quit(0)
