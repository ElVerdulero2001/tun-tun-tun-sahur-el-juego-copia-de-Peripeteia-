extends CanvasLayer

@onready var label = $Label
@onready var player = get_tree().get_first_node_in_group("player")

func _process(_delta):
	if player == null:
		return
	var movement  = player.get_node("movement/MovementController")
	var vel_horizontal = Vector2(player.velocity.x, player.velocity.z).length()
	var vel_vertical   = player.velocity.y
	var vel_x          = player.velocity.x
	var vel_z          = player.velocity.z
	var agachado       = "SI" if movement.is_crouching else "NO"
	var en_piso        = "SI" if player.is_on_floor() else "NO"
	var angulo_vertical   = rad_to_deg(player.get_node("Camera3D").rotation.x)
	var angulo_horizontal = rad_to_deg(player.rotation.y)
	var pos_x          = player.global_position.x
	var pos_y          = player.global_position.y
	var pos_z          = player.global_position.z

	var estado_traversal = "??"
	var traversal = player.get_node_or_null("movement/TraversalController")
	if traversal != null:
		estado_traversal = traversal.get_state_name()

	label.text = (
		"Vel horizontal: %.2f\n" +
		"Vel vertical: %.2f\n" +
		"Vel X: %.2f\n" +
		"Vel Z: %.2f\n" +
		"Angulo vertical: %.1f\n" +
		"Angulo horizontal: %.1f\n" +
		"Agachado: %s\n" +
		"En piso: %s\n" +
		"Estado traversal: %s\n" +
		"Pos X: %.2f\n" +
		"Pos Y: %.2f\n" +
		"Pos Z: %.2f"
	) % [vel_horizontal, vel_vertical, vel_x, vel_z,
		 angulo_vertical, angulo_horizontal,
		 agachado, en_piso, estado_traversal,
		 pos_x, pos_y, pos_z]
