# transport_platform.gd
extends AnimatableBody3D

@export var move_speed      : float = 4.0   # velocidad de crucero en m/s
@export var accel_distance  : float = 3.0   # metros de aceleración
@export var decel_distance  : float = 3.0   # metros de frenado
@export var stations        : Array[Node3D] = []
@export var detect_area     : Area3D

enum PlatformState { IDLE, MOVING }
var _state            : PlatformState = PlatformState.IDLE
var _current_station  : int     = 0
var _target_station   : int     = 0
var _journey_distance : float   = 0.0   # distancia total del viaje en metros
var _meters_traveled  : float   = 0.0   # metros recorridos en el viaje actual
var _origin_pos       : Vector3 = Vector3.ZERO
var _target_pos       : Vector3 = Vector3.ZERO
var _accel_dist_real  : float   = 0.0   # accel_distance ajustada para viajes cortos
var _decel_dist_real  : float   = 0.0   # decel_distance ajustada para viajes cortos
var _passenger        : CharacterBody3D = null
var _movement_ctrl    : Node    = null

signal arrived_at_station(index: int)

func _ready() -> void:
	if detect_area:
		detect_area.body_entered.connect(_on_body_entered)
		detect_area.body_exited.connect(_on_body_exited)
	call_deferred("_init_position")

func _init_position() -> void:
	if stations.size() > 0 and stations[0] != null:
		global_position = stations[0].global_position
	else:
		push_error("[TransportPlatform] No hay estaciones definidas.")

func _physics_process(delta: float) -> void:
	if _state == PlatformState.IDLE:
		return

	var pos_before = global_position
	_update_journey(delta)
	_apply_position()

	var platform_delta = global_position - pos_before
	if _passenger != null and is_instance_valid(_passenger):
		if platform_delta != Vector3.ZERO:
			_passenger.global_position += platform_delta

func go_to_station(index: int) -> void:
	if index < 0 or index >= stations.size():
		push_error("[TransportPlatform] Índice inválido: " + str(index))
		return
	if index == _current_station and _state == PlatformState.IDLE:
		print("[TransportPlatform] Ya estamos en estación: ", index)
		return

	_target_station   = index
	_origin_pos       = global_position
	_target_pos       = stations[index].global_position
	_journey_distance = _origin_pos.distance_to(_target_pos)
	_meters_traveled  = 0.0

	# Ajustar aceleración y frenado si el viaje es muy corto
	var total = accel_distance + decel_distance
	if total > _journey_distance:
		var ratio = _journey_distance / total
		_accel_dist_real = accel_distance * ratio
		_decel_dist_real = decel_distance * ratio
	else:
		_accel_dist_real = accel_distance
		_decel_dist_real = decel_distance

	_state = PlatformState.MOVING
	print("[TransportPlatform] Viajando a estación ", index, " — ", snappedf(_journey_distance, 0.01), "m")

func get_current_station() -> int:
	return _current_station

func get_station_count() -> int:
	return stations.size()

func _get_speed() -> float:
	var meters_remaining = _journey_distance - _meters_traveled

	if _meters_traveled < _accel_dist_real:
		# Zona de aceleración
		return move_speed * max(_meters_traveled / _accel_dist_real, 0.02)
	elif meters_remaining < _decel_dist_real:
		# Zona de frenado
		return move_speed * max(meters_remaining / _decel_dist_real, 0.02)
	else:
		# Crucero
		return move_speed

func _update_journey(delta: float) -> void:
	if _journey_distance <= 0.0:
		_arrive()
		return

	var speed = _get_speed()
	_meters_traveled += speed * delta

	if _meters_traveled >= _journey_distance:
		_meters_traveled = _journey_distance
		_arrive()

func _arrive() -> void:
	_current_station = _target_station
	_state           = PlatformState.IDLE
	print("[TransportPlatform] Llegó a estación: ", _current_station)
	arrived_at_station.emit(_current_station)

func _apply_position() -> void:
	var t         = _meters_traveled / _journey_distance
	var target    = _origin_pos.lerp(_target_pos, t)
	var delta_pos = target - global_position
	move_and_collide(delta_pos)

func _on_body_entered(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return
	if _passenger != null:
		return
	_passenger = body
	var movement_node = body.get_node_or_null("movement/MovementController")
	if movement_node:
		_movement_ctrl = movement_node
		_movement_ctrl.set_on_platform(true)
	print("[TransportPlatform] Pasajero subió: ", body.name)

func _on_body_exited(body: Node3D) -> void:
	if body != _passenger:
		return
	if _movement_ctrl:
		_movement_ctrl.set_on_platform(false)
	if _state == PlatformState.IDLE:
		_passenger = null
		_movement_ctrl = null
		print("[TransportPlatform] Pasajero bajó.")
