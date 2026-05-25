extends CanvasLayer

@onready var label = $Label
@onready var player = get_tree().get_first_node_in_group("player")

func _process(_delta):
	if player == null:
		return
	var movement = player.get_node("MovementController")
	var vel_horizontal = Vector2(player.velocity.x, player.velocity.z).length()
	var vel_vertical = player.velocity.y
	var vel_x = player.velocity.x
	var vel_z = player.velocity.z
	var agachado = "SI" if movement.is_crouching else "NO"
	var en_piso = "SI" if player.is_on_floor() else "NO"
	var angulo_vertical = rad_to_deg(player.get_node("Camera3D").rotation.x)
	var angulo_horizontal = rad_to_deg(player.rotation.y)

	# ── Estado del TraversalController ────────────────────────────
	# Lo pedimos como texto. Si por algún motivo el nodo no está,
	# mostramos "??" en vez de crashear el debug.
	var estado_traversal = "??"
	var traversal = player.get_node_or_null("TraversalController")
	if traversal != null:
		estado_traversal = traversal.get_state_name()

	label.text = "Vel horizontal: %.2f\nVel vertical: %.2f\nVel X: %.2f\nVel Z: %.2f\nAngulo vertical: %.1f\nAngulo horizontal: %.1f\nAgachado: %s\nEn piso: %s\nEstado traversal: %s" % [vel_horizontal, vel_vertical, vel_x, vel_z, angulo_vertical, angulo_horizontal, agachado, en_piso, estado_traversal]
