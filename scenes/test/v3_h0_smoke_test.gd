extends SceneTree

const LAB := preload("res://scenes/test/v3_h0_lab.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := LAB.instantiate()
	root.add_child(lab)
	var body := lab.get_node("PlayerH0Lab/Body") as V3PhysicsBody
	var h0 := lab.get_node("PlayerH0Lab/Body/H0") as H0Core
	var fall_damage_state := lab.get_node("PlayerH0Lab/Body/FallDamageState")
	var view := lab.get_node("PlayerH0Lab/Body/View") as Node3D
	var collider := lab.get_node("PlayerH0Lab/Body/CollisionShape3D") as CollisionShape3D

	for _frame in 30:
		await physics_frame
	assert(body.is_on_floor(), "H0 lab: el body debe asentarse sobre el piso")

	Input.action_press("crouch")
	await physics_frame
	Input.action_release("crouch")
	assert(body.is_crouched, "H0 lab: crouch debe reducir físicamente el body")
	for _frame in 20:
		await physics_frame
	assert(view.position.y < 1.2, "H0 lab: la cámara debe acompañar la postura agachada")

	body.global_position = Vector3(5.0, 0.0, 4.0)
	body.velocity = Vector3.ZERO
	await physics_frame
	Input.action_press("crouch")
	await physics_frame
	Input.action_release("crouch")
	assert(body.is_crouched, "H0 lab: un techo bajo debe impedir pararse")
	assert(body.last_stand_request_blocked, "H0 lab: el bloqueo para pararse debe publicarse")

	body.global_position = Vector3(0.0, 0.0, 4.0)
	body.velocity = Vector3.ZERO
	for _frame in 3:
		await physics_frame
	assert(body.is_crouched, "H0 lab: salir de un techo bajo no debe parar al player automáticamente")

	Input.action_press("crouch")
	await physics_frame
	Input.action_release("crouch")
	assert(not body.is_crouched, "H0 lab: una nueva pulsación en espacio libre debe permitir pararse")

	Input.action_press("run")
	Input.action_press("move_forward")
	for _frame in 13:
		await physics_frame
	assert(h0.last_sprint_active, "H0 lab: Shift debe activar sprint en piso")
	assert(is_equal_approx(h0.last_desired_horizontal_velocity.length(), h0.sprint_speed), "H0 lab: sprint debe solicitar su velocidad propia")

	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	assert(body.last_jump_accepted, "H0 lab: sprint debe poder saltar desde piso")
	await physics_frame
	assert(is_equal_approx(h0.last_desired_horizontal_velocity.length(), h0.sprint_speed), "H0 lab: Shift sostenido debe conservar velocidad de sprint en aire")

	Input.action_release("run")
	await physics_frame
	assert(h0.last_desired_horizontal_velocity.length() > h0.walk_speed, "H0 lab: soltar Shift en aire debe conservar inercia antes de caminar")

	for _frame in 120:
		await physics_frame
	assert(body.is_on_floor(), "H0 lab: sprint aéreo debe volver a piso")
	assert(is_equal_approx(h0.last_desired_horizontal_velocity.length(), h0.walk_speed), "H0 lab: sin Shift debe aterrizar caminando")
	Input.action_release("move_forward")

	Input.action_press("move_forward")
	for _frame in 180:
		await physics_frame
	Input.action_release("move_forward")

	assert(body.global_position.z < -5.3, "H0 lab: H0 debe mover hacia adelante según la cámara")
	assert(body.global_position.z > -5.7, "H0 lab: la capa física debe detener al body en la pared")
	assert(body.last_intent_source_name == "H0", "H0 lab: la intención física debe venir de H0")
	assert(body.last_collision_count > 0, "H0 lab: la colisión contra la pared debe quedar publicada")

	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	assert(body.last_jump_accepted, "H0 lab: el salto desde el piso debe ser aceptado")

	for _frame in 2:
		await physics_frame
	Input.action_press("crouch")
	await physics_frame
	Input.action_release("crouch")
	assert(body.is_crouched, "H0 lab: crouch debe poder activarse en el aire")
	assert(body.crouch_anchor == V3PhysicsBody.CrouchAnchor.AIR, "H0 lab: crouch aéreo debe usar ancla de aire")
	assert(is_equal_approx(collider.position.y, 0.9), "H0 lab: crouch aéreo debe conservar el centro de la cápsula")
	assert(is_equal_approx(view.position.y, 1.6), "H0 lab: crouch aéreo no debe bajar la cámara")

	for _frame in 3:
		await physics_frame
	assert(body.global_position.y > 0.2, "H0 lab: el salto debe separar al body del piso")

	for _frame in 120:
		await physics_frame
	assert(body.is_on_floor(), "H0 lab: después del salto debe volver al piso")
	assert(body.crouch_anchor == V3PhysicsBody.CrouchAnchor.GROUND, "H0 lab: al aterrizar crouch debe volver a anclarse al piso")
	assert(is_equal_approx(collider.position.y, 0.6), "H0 lab: crouch en piso debe conservar los pies")

	Input.action_press("crouch")
	await physics_frame
	Input.action_release("crouch")
	assert(not body.is_crouched, "H0 lab: debe poder volver a la postura normal tras aterrizar")

	Input.action_press("jump")
	var repeated_jump_count := 0
	for _frame in 180:
		await physics_frame
		if body.last_jump_accepted:
			repeated_jump_count += 1
	Input.action_release("jump")
	assert(repeated_jump_count >= 2, "H0 lab: sostener salto debe repetirlo en cada aterrizaje")

	for _frame in 120:
		await physics_frame
	assert(body.is_on_floor(), "H0 lab: al soltar salto debe volver a quedar en piso")

	fall_damage_state.jump_penalty_fall_distance = 0.5
	body.global_position.y = 2.0
	body.velocity = Vector3.ZERO
	for _frame in 180:
		await physics_frame
		if fall_damage_state.jump_is_penalized:
			break
	assert(fall_damage_state.jump_is_penalized, "H0 lab: una caída larga debe aplicar penalización")

	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	assert(not body.last_jump_accepted, "H0 lab: la penalización de caída debe bloquear el salto")

	print("V3 H0 smoke test: OK")
	quit(0)
