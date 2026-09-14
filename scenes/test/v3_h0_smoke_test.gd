extends SceneTree

const LAB := preload("res://scenes/test/v3_h0_lab.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := LAB.instantiate()
	root.add_child(lab)
	var body := lab.get_node("PlayerH0Lab/Body") as V3PhysicsBody

	for _frame in 30:
		await physics_frame
	assert(body.is_on_floor(), "H0 lab: el body debe asentarse sobre el piso")

	Input.action_press("move_forward")
	for _frame in 180:
		await physics_frame
	Input.action_release("move_forward")

	assert(body.global_position.z < -5.3, "H0 lab: H0 debe mover hacia adelante según la cámara")
	assert(body.global_position.z > -5.7, "H0 lab: la capa física debe detener al body en la pared")
	assert(body.last_intent_source_name == "H0", "H0 lab: la intención física debe venir de H0")
	assert(body.last_collision_count > 0, "H0 lab: la colisión contra la pared debe quedar publicada")

	print("V3 H0 smoke test: OK")
	quit(0)
