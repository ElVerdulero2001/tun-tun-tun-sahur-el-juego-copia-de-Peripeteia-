class_name ActorBody
extends CharacterBody3D

## Cuerpo físico de un actor. Solo lo mueve ActorMotor, y solo dentro de un
## tick. Los indicadores de Godot (is_on_floor() y compañía) se copian al
## estado del actor apenas termina cada movimiento: el resto del juego lee el
## estado, nunca los indicadores.

## Distancia del snap manual al restaurar un estado apoyado: solo tiene que
## cubrir la fracción de milímetro que agrega la cuantización.
const RESTORE_SNAP_LENGTH := 0.01
## Cuánto puede empujar la geometría a una pose restaurada sin que cuente como
## metida adentro. Una pose válida se mueve menos de un milímetro.
const POSE_TOLERANCE := 0.01
## Presentación: después de un salto del cuerpo (una corrección), el desvío
## visual se reduce a la mitad cada este tiempo; en unos 100 ms ya no se nota.
const CORRECTION_HALF_LIFE := 0.025
## Saltos más grandes que esto no se suavizan: se ven como un salto.
const MAX_SMOOTHED_JUMP := 1.5
## Presentación del agarre de un borde: su desvío decae igual que el de una
## corrección, pero a lo sumo a esta velocidad, en m/s. Así la cámara se mueve
## como mucho 9 cm en los 50 ms después de agarrarse (criterio de la
## arquitectura); un snap de 35 cm tarda unos 250 ms en cerrarse.
const GRAB_MAX_SPEED := 1.8
## Espacio libre: la forma de prueba se achica esto por cada lado, para que
## tocar el piso o una pared no cuente como choque.
const FREE_SPACE_MARGIN := 0.02
## Grupo de todos los actores, para encontrar a un compañero por su id.
const GROUP := "actores"

## Desvío del visual respecto del cuerpo. Es solo presentación: la simulación
## no lo lee nunca. El del agarre va aparte porque decae más lento.
var visual_offset := Vector3.ZERO
var grab_offset := Vector3.ZERO

## Estado del actor. Solo lo escriben ActorMotor y la red al restaurar.
var state := ActorState.new()
## Peer dueño del actor: el que manda su input. El host es 1.
var owner_peer_id := 1
## Falso hasta que el reloj ubica el cuerpo en su estado por primera vez.
var placed := false
## Si esta máquina lo simula. El host simula a todos; el cliente, solo al
## propio (predicción), y a los demás los muestra como los manda el host.
var simulated := true
## Evento de presentación del último paso: cuánto saltó el cuerpo a propósito
## (un snap lógico). Lo pone ActorMotor y lo consume present(); la simulación
## no lo lee. Subir un escalón usa snap_jump, que se suaviza como una
## corrección; agarrarse de un borde, de una escalera o de un compañero usa
## grab_jump, con su tope de velocidad.
var snap_jump := Vector3.ZERO
var grab_jump := Vector3.ZERO

## Forma activa: la de la postura concedida.
var _active_stance: int = ActorState.Stance.STANDING
## Postura que mostró present() la última vez.
var _presented_stance := -1
## Formas para probar el espacio libre, una por postura, ya achicadas.
var _probe_shapes: Array[CapsuleShape3D] = []
var _probe_params := PhysicsShapeQueryParameters3D.new()

@onready var _visual: Node3D = $Visual
## Por postura, en el orden de ActorState.Stance. Las formas están preparadas
## en la escena: cambiar las medidas de una forma en pleno juego obliga a Jolt
## a reconstruirla.
@onready var _shapes: Array[CollisionShape3D] = [$Shape, $CrouchShape]
@onready var _bodies: Array[Node3D] = [$Visual/Body, $Visual/BodyCrouch]
@onready var _nose: Node3D = $Visual/Nose
## Manos que se dibujan sobre el filo mientras cuelga. Solo presentación.
var _hands: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group(GROUP)
	# La base (plataformas) la maneja la arquitectura y no Godot: Godot lee la
	# velocidad de plataforma del presente, y eso falla al repetir ticks.
	platform_floor_layers = 0
	platform_wall_layers = 0
	platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING
	floor_block_on_wall = true
	floor_stop_on_slope = true
	for shape in _shapes:
		var capsule: CapsuleShape3D = shape.shape
		var probe := CapsuleShape3D.new()
		probe.radius = capsule.radius - FREE_SPACE_MARGIN
		probe.height = capsule.height - 2.0 * FREE_SPACE_MARGIN
		_probe_shapes.append(probe)
	var hand_mesh := BoxMesh.new()
	hand_mesh.size = Vector3(0.12, 0.06, 0.14)
	hand_mesh.material = ($Visual/Nose as MeshInstance3D).mesh.material
	for i in 2:
		var hand := MeshInstance3D.new()
		hand.mesh = hand_mesh
		hand.visible = false
		add_child(hand)
		_hands.append(hand)


## Los demás actores, por id de dueño, sin los que se están yendo.
func teammates() -> Array[ActorBody]:
	var list: Array[ActorBody] = []
	for node in get_tree().get_nodes_in_group(GROUP):
		var actor := node as ActorBody
		if actor != null and actor != self and not actor.is_queued_for_deletion():
			list.append(actor)
	list.sort_custom(func(a: ActorBody, b: ActorBody) -> bool: return a.owner_peer_id < b.owner_peer_id)
	return list


## El actor de otro jugador, o null si no está.
func teammate(peer_id: int) -> ActorBody:
	for actor in teammates():
		if actor.owner_peer_id == peer_id:
			return actor
	return null


## Activa la forma de colisión de una postura.
func use_stance(stance: int) -> void:
	if stance == _active_stance:
		return
	_active_stance = stance
	for i in _shapes.size():
		_shapes[i].disabled = i != stance


## Postura de la forma activa.
func active_stance() -> int:
	return _active_stance


## Radio de la forma activa.
func capsule_radius() -> float:
	var capsule: CapsuleShape3D = _shapes[_active_stance].shape
	return capsule.radius


## Alto de la forma de una postura, de los pies a la cabeza.
func stance_height(stance: int) -> float:
	var capsule: CapsuleShape3D = _shapes[stance].shape
	return capsule.height


## Si la forma de `stance` cabe con los pies en `feet`. No cuentan el propio
## cuerpo ni los demás jugadores, que están en otra capa.
func stance_fits(stance: int, feet: Vector3) -> bool:
	_probe_params.shape = _probe_shapes[stance]
	_probe_params.transform = Transform3D(Basis(), feet + _shapes[stance].position)
	_probe_params.collision_mask = collision_mask
	_probe_params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(_probe_params, 1).is_empty()


## Mueve el cuerpo con move_and_slide() avanzando exactamente dt.
## move_and_slide() toma el delta del frame de física por su cuenta; el factor
## lo compensa cuando dt es otro (escala de tiempo, ticks repetidos).
func slide(actor_state: ActorState, snap_length: float, dt: float) -> void:
	var factor := dt / get_physics_process_delta_time()
	floor_snap_length = snap_length
	var sent := actor_state.velocity * factor
	velocity = sent
	move_and_slide()
	# Si el movimiento no tocó la velocidad, queda la de antes, tal cual.
	# Deshacer el factor deja un error de redondeo que depende del delta del
	# frame: un tick repetido en otro frame (con cámara lenta, otro delta)
	# podría cuantizarse distinto.
	if velocity != sent:
		actor_state.velocity = velocity / factor


## Después de ubicar el cuerpo a mano sobre un piso (un escalón): refresca los
## indicadores de Godot sin moverlo. El cuerpo quedó al margen de seguridad del
## piso, donde el movimiento de velocidad cero puede no verlo; el snap lo
## encuentra igual.
func settle_on_floor(snap_length: float) -> void:
	floor_snap_length = snap_length
	velocity = Vector3.ZERO
	move_and_slide()
	if not is_on_floor():
		apply_floor_snap()


## Pone el cuerpo en el estado dado, por ejemplo al restaurar una corrección.
## Además sincroniza el estado interno de piso de Godot: move_and_slide() usa
## el resultado del llamado anterior para decidir el snap, y después de
## restaurar ese dato quedó viejo.
##
## Devuelve si el estado entra en este mundo: que la geometría no tenga que
## empujar el cuerpo para afuera y que, si dice estar apoyado, haya piso. Con
## eso el host valida la afirmación de un cliente antes de adoptarla.
##
## Sobre una base, la posición del estado es relativa: el cuerpo va a la pose
## que la base tiene ahora (al repetir ticks, eso es trabajar en coordenadas
## de la base).
func apply_state(actor_state: ActorState) -> bool:
	use_stance(actor_state.stance)
	var world := BaseRegistry.world_position(actor_state)
	global_position = world
	# Un movimiento de velocidad cero refresca los indicadores según el
	# contacto real; con el snap en 0 no arrastra el cuerpo hacia el piso.
	floor_snap_length = 0.0
	velocity = Vector3.ZERO
	move_and_slide()
	var fits := global_position.distance_to(world) <= POSE_TOLERANCE
	# Apoyado, el cuerpo queda a la distancia del margen, y al cuantizar puede
	# quedar una fracción de milímetro más arriba: fuera del margen, el
	# movimiento de arriba no ve el piso. El snap manual lo encuentra igual.
	if actor_state.on_floor and not is_on_floor():
		floor_snap_length = RESTORE_SNAP_LENGTH
		apply_floor_snap()
		fits = fits and is_on_floor()
	global_position = world
	velocity = actor_state.velocity
	present(actor_state)
	return fits


## Presentación mínima: orienta el visual y muestra la postura concedida. No
## escribe nada en la simulación.
func present(actor_state: ActorState) -> void:
	_visual.rotation.y = actor_state.facing_yaw
	for i in _bodies.size():
		_bodies[i].visible = i == actor_state.stance
	_nose.position.y = stance_height(actor_state.stance) - 0.3
	# En el aire, cambiar de postura mueve los pies y deja la cabeza: el origen
	# salta, no se mueve. Interpolarlo dibujaría la forma nueva desde los pies
	# viejos, con la cabeza bajando o subiendo durante un tick.
	if _presented_stance != -1 and actor_state.stance != _presented_stance \
			and actor_state.mode == ActorState.Mode.AIR:
		reset_physics_interpolation()
	_presented_stance = actor_state.stance
	# Un snap lógico (escalón, agarre): el cuerpo saltó de golpe, y el visual
	# arranca desde donde estaba y lo alcanza con el mismo decaimiento de las
	# correcciones.
	if snap_jump != Vector3.ZERO:
		set_visual_offset(visual_offset - snap_jump)
		snap_jump = Vector3.ZERO
	if grab_jump != Vector3.ZERO:
		grab_offset -= grab_jump
		grab_jump = Vector3.ZERO
		_visual.position = visual_offset + grab_offset
	# Colgado: las manos sobre el filo, a los costados. Colgado de un compañero,
	# sobre su cintura. Cuelgan del cuerpo y no del dibujo, así quedan donde
	# agarran mientras el dibujo se acomoda.
	var holding := actor_state.mode == ActorState.Mode.HANGING or actor_state.mode == ActorState.Mode.HOOKED
	for i in _hands.size():
		_hands[i].visible = holding
	if holding:
		var toward := Vector3.FORWARD.rotated(Vector3.UP, actor_state.facing_yaw)
		var right := toward.cross(Vector3.UP)
		var grip: Vector3
		if actor_state.mode == ActorState.Mode.HOOKED:
			# Las manos, donde las dejó el motor respecto del cuerpo en ese estado.
			grip = actor_state.anchor_point - BaseRegistry.world_position(actor_state)
		else:
			grip = BaseRegistry.origin(actor_state.anchor_id) + actor_state.anchor_point - global_position \
					+ Vector3.UP * 0.03 + toward * 0.05
		for i in _hands.size():
			_hands[i].position = grip + right * (0.2 if i == 0 else -0.2)
			_hands[i].rotation.y = actor_state.facing_yaw


## Dónde se ve el actor: el cuerpo más el desvío visual.
func seen_position() -> Vector3:
	return global_position + visual_offset + grab_offset


## El cuerpo acaba de saltar por una corrección y antes se lo veía en `seen`:
## el visual arranca desde ahí y llega solo a la posición nueva. Un salto más
## grande que MAX_SMOOTHED_JUMP se muestra tal cual. Lo que faltaba del agarre
## pasa a decaer como la corrección.
func smooth_from(seen: Vector3) -> void:
	visual_offset = seen - global_position
	grab_offset = Vector3.ZERO
	if visual_offset.length() > MAX_SMOOTHED_JUMP:
		teleported()
		return
	_visual.position = visual_offset


## Fija el desvío visual tal cual, sin que decaiga solo: lo va moviendo quien
## lo pide. Va en el tick, como decay_visual_offset().
func set_visual_offset(offset: Vector3) -> void:
	visual_offset = offset
	_visual.position = offset + grab_offset


## Una vez por tick, en el tick: el desvío decae hacia cero. Va en el tick
## para que la interpolación de física lo suavice entre ticks. El del agarre
## decae igual, pero sin pasar de GRAB_MAX_SPEED.
func decay_visual_offset(dt: float) -> void:
	if visual_offset == Vector3.ZERO and grab_offset == Vector3.ZERO:
		return
	var factor := pow(0.5, dt / CORRECTION_HALF_LIFE)
	visual_offset *= factor
	if visual_offset.length_squared() < 1e-8:
		visual_offset = Vector3.ZERO
	var grab_length := grab_offset.length()
	var step := minf(grab_length * (1.0 - factor), GRAB_MAX_SPEED * dt)
	grab_offset = grab_offset.move_toward(Vector3.ZERO, step)
	if grab_offset.length_squared() < 1e-8:
		grab_offset = Vector3.ZERO
	_visual.position = visual_offset + grab_offset


## El actor apareció en otro lugar (reaparición, teleport): sin desvío y sin
## interpolar desde la posición vieja.
func teleported() -> void:
	visual_offset = Vector3.ZERO
	grab_offset = Vector3.ZERO
	_visual.position = Vector3.ZERO
	reset_physics_interpolation()


## Nodo que se ve y que sigue la cámara: incluye el desvío visual.
func visual_root() -> Node3D:
	return _visual
