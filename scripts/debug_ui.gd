extends CanvasLayer

@onready var label = $Label
@onready var player = get_tree().get_first_node_in_group("player")

func _process(_delta):
	if player == null:
		return
	var vel_horizontal = Vector2(player.velocity.x, player.velocity.z).length()
	var vel_vertical = player.velocity.y
	var vel_x = player.velocity.x
	var vel_z = player.velocity.z
	var agachado = "SI" if player.is_crouching else "NO"
	var en_piso = "SI" if player.is_on_floor() else "NO"
	var angulo_vertical = rad_to_deg(player.get_node("Camera3D").rotation.x)
	var angulo_horizontal = rad_to_deg(player.rotation.y)

	# Debug auto step
	var espacio = player.get_world_3d().direct_space_state
	var direction = -player.transform.basis.z
	var step_check = player.global_position + Vector3.UP * 0.3 + direction * 0.3
	var query = PhysicsRayQueryParameters3D.create(step_check, step_check + Vector3.DOWN * 0.4)
	query.exclude = [player]
	var resultado = espacio.intersect_ray(query)
	var step_detectado = "SI" if resultado else "NO"

	label.text = "Vel horizontal: %.2f\nVel vertical: %.2f\nVel X: %.2f\nVel Z: %.2f\nAngulo vertical: %.1f\nAngulo horizontal: %.1f\nAgachado: %s\nEn piso: %s\nStep detectado: %s" % [vel_horizontal, vel_vertical, vel_x, vel_z, angulo_vertical, angulo_horizontal, agachado, en_piso, step_detectado]
