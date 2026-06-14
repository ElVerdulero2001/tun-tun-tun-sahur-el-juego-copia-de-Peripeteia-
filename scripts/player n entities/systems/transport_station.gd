# transport_station.gd
# Va en un Area3D que representa el panel o zona de llamada del ascensor.
# Cuando el jugador aprieta interact cerca, llama a la plataforma.
# Puede ser estación de abajo (llama para subir) o de arriba (llama para bajar).

extends Area3D

# ── Parámetros ────────────────────────────────────────────────────
@export var platform        : NodePath          # path al TransportPlatform
@export var station_type    : StationType = StationType.BOTTOM

enum StationType { BOTTOM, TOP }

# ── Referencias ───────────────────────────────────────────────────
var _platform    : Node    = null
var _player_near : bool    = false

# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	if platform:
		_platform = get_node(platform)
	else:
		push_warning("[TransportStation] No hay plataforma asignada en: " + name)
		return

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if not _player_near:
		return
	if not _platform:
		return

	if Input.is_action_just_pressed("interactuar"):
		_call_platform()

# ── Lógica ────────────────────────────────────────────────────────

func _call_platform() -> void:
	match station_type:
		StationType.BOTTOM:
			print("[TransportStation] Estación ABAJO — llamando plataforma hacia abajo.")
			_platform.call_to_bottom()
		StationType.TOP:
			print("[TransportStation] Estación ARRIBA — llamando plataforma hacia arriba.")
			_platform.call_to_top()

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_near = true
		print("[TransportStation] Jugador cerca de estación: ", name)

func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_near = false
