# kick_controller.gd
# Nodo hijo del Player.
# Responsabilidad: detectar y resolver el kick del jugador.
# Usa el raycast_interaction existente para saber qué está mirando
# la cámara — sin duplicar queries de física.
#
# Uso desde player.gd:
#   kick.setup(self, camera, raycast)
#   kick.process(delta)   ← llamar siempre, sin condiciones

extends Node

# ── Parámetros exportados ─────────────────────────────────────────
# Fuerza del impulso aplicado al RigidBody impactado.
@export var kick_force     : float = 8.0

# Fracción de la fuerza que sube (componente Y del impulso).
# 0.0 = impulso puramente horizontal. 0.2 = algo de vuelo.
@export var kick_upward    : float = 0.2

# ── Referencias ───────────────────────────────────────────────────
var body     : CharacterBody3D
var camera   : Camera3D
var raycast  : Node   # raycast_interaction — fuente de verdad de qué se mira

# ── Estado interno ────────────────────────────────────────────────
var _kicked_this_frame : bool = false

# ─────────────────────────────────────────────────────────────────
func setup(p_body: CharacterBody3D, p_camera: Camera3D, p_raycast: Node) -> void:
	body    = p_body
	camera  = p_camera
	raycast = p_raycast

# ─────────────────────────────────────────────────────────────────
func process(_delta: float) -> void:
	_kicked_this_frame = false

	if Input.is_action_just_pressed("kick"):
		_execute_kick()

# ─────────────────────────────────────────────────────────────────
func _execute_kick() -> void:
	if _kicked_this_frame:
		return
	_kicked_this_frame = true

	# Dirección del kick: donde apunta la cámara, con Y aplanado.
	# Sin aplanar, si mirás hacia abajo el objeto sale al piso — se ve fatal.
	var facing    = -camera.global_transform.basis.z
	facing.y      = 0.0
	facing        = facing.normalized()

	# Leer qué está mirando el raycast de interacción.
	# objeto_mirado ya tiene el nodo interactable más cercano, o null.
	var objetivo = raycast.objeto_mirado

	# Debug: línea desde el player en la dirección del kick.
	var origen    = body.global_position + Vector3.UP * 0.1
	var kick_end  = origen + facing * 1.0
	DebugDraw.ray(origen, kick_end, Color.YELLOW)

	if objetivo == null:
		return

	_resolve_impact(objetivo, facing)

# ─────────────────────────────────────────────────────────────────
# ── RESOLUCIÓN DE IMPACTO ─────────────────────────────────────────
# Por ahora solo resuelve RigidBodies.
# Cuando haya enemigos con salud, agregar un elif acá.
# ─────────────────────────────────────────────────────────────────

func _resolve_impact(collider: Node, direction: Vector3) -> void:
	if collider is RigidBody3D:
		_push_rigidbody(collider, direction)

func _push_rigidbody(rb: RigidBody3D, direction: Vector3) -> void:
	var impulse  = direction * kick_force
	impulse.y   += kick_force * kick_upward
	rb.apply_central_impulse(impulse)

	DebugDraw.sphere(rb.global_position, 0.3, Color.RED)
