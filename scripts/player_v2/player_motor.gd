class_name PlayerMotor
extends CharacterBody3D

## PlayerMotor — autoridad física única de PlayerV2 (Parkour V2, Fase 2; doc
## de arquitectura V0.3, secciones 2, 4 y 9).
##
## Dueño exclusivo de velocity, postura, collider y move_and_slide()/
## move_and_collide(). Ningún otro componente debe escribir velocity
## directamente. Locomoción base (caminar, correr, crouch, salto, gravedad,
## control aéreo) vive acá y lee Input.* directamente — es independiente del
## pipeline TraversalIntent -> TraversalResolver -> TraversalController, que
## en esta fase todavía no existe.
##
## Mouse-look (yaw en este Body, pitch en View) queda igual que en el
## prototipo SUA-1.1 anterior: el doc de arquitectura separa esto en un
## CameraLook aparte, pero esa extracción no es parte de la Fase 2 y queda
## pendiente para cuando exista TraversalController.
##
## Contrato de traversal (sección 9): mientras un TraversalLease esté
## vigente, este motor NO aplica locomoción ni gravedad normales. Solo
## quien sostiene el lease puede mover el cuerpo, vía apply_traversal_pose().

# ── Parámetros de locomoción — PROVISIONALES (sección 14, pendientes de
# calibración de feel; no son contrato). ──────────────────────────────
const WALK_SPEED := 5.0
const RUN_SPEED := 8.0
const CROUCH_SPEED := 2.5
const ACCELERATION := 10.0
const FRICTION := 12.0
const AIR_CONTROL := 0.3
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003
const PITCH_LIMIT := 1.553343  # deg_to_rad(89°) — impide el giro vertical completo

const STANDING_HEIGHT := 1.8
const CROUCH_HEIGHT := 0.9

# Prioridad de proceso físico deliberadamente por encima del default (0):
# cuando exista TraversalController, puede quedarse con la prioridad por
# defecto y correrá antes que este motor sin tener que retocar esta
# constante (doc sección 9: "Motor y Controller ... prioridad de proceso
# Controller -> Motor").
const MOTOR_PHYSICS_PRIORITY := 100

# Umbral bajo el cual apply_traversal_pose() trata un movimiento guiado como
# "sin desplazamiento real" (una pose inmóvil, como en HANGING) y por lo
# tanto necesita revalidar por solape en vez de confiar en move_and_collide.
const _EPSILON_SIN_DESPLAZAMIENTO := 0.0001

# ── Referencias internas ────────────────────────────────────────────
@onready var _view: Node3D = $View
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

# ── Postura ──────────────────────────────────────────────────────────
var _agachado: bool = false
var _ultimo_can_stand: bool = true

# ── Detección de salto por estado sostenido (no por is_action_just_pressed:
# ese borde lo gestiona el motor de Godot entre frames reales, y este motor
# debe ser testeable con ticks manuales sin depender de eso). ──────────
var _salto_anterior_presionado: bool = false

# ── Traversal lease (sección 9) ─────────────────────────────────────
var _lease: TraversalLease = null
var _lease_renovado_este_tick: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	process_physics_priority = MOTOR_PHYSICS_PRIORITY


# ── Mouse-look ──────────────────────────────────────────────────────
## ui_cancel / ESC NO se maneja acá (SUA-1.4 C4-C): el cuerpo físico no es
## dueño del foco de input. Con el InventoryPanel abierto, PlayerInventoryUI
## consume ESC para cerrarlo; con nada abierto, ESC no hace nada.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_view.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		_view.rotation.x = clampf(_view.rotation.x, -PITCH_LIMIT, PITCH_LIMIT)


func _physics_process(delta: float) -> void:
	physics_tick(delta)


## Un paso físico completo. Público (no "_privado") a propósito: los tests
## de Fase 2 lo llaman a mano, con set_physics_process(false), para
## controlar con precisión el orden relativo a apply_traversal_pose() sin
## depender del framerate real de Godot.
func physics_tick(delta: float) -> void:
	if _lease != null:
		if _lease_renovado_este_tick:
			_lease_renovado_este_tick = false
		else:
			_forzar_salida_traversal()

	if _lease == null:
		_locomocion_normal(delta)


func snapshot() -> MotorSnapshot:
	var postura := MotorSnapshot.Stance.CROUCHING if _agachado else MotorSnapshot.Stance.STANDING
	return MotorSnapshot.new(is_on_floor(), velocity, postura, _ultimo_can_stand)


# ── Locomoción normal ────────────────────────────────────────────────
func _locomocion_normal(delta: float) -> void:
	_actualizar_postura()
	_procesar_salto()

	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direccion := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var velocidad_objetivo := _velocidad_objetivo_actual()
	var en_piso := is_on_floor()
	var aceleracion := ACCELERATION if en_piso else ACCELERATION * AIR_CONTROL
	var freno := FRICTION if en_piso else FRICTION * AIR_CONTROL

	var horizontal := Vector2(velocity.x, velocity.z)
	if direccion:
		horizontal = horizontal.move_toward(Vector2(direccion.x, direccion.z) * velocidad_objetivo, aceleracion * delta)
	else:
		horizontal = horizontal.move_toward(Vector2.ZERO, freno * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	move_and_slide()


func _procesar_salto() -> void:
	var salto_presionado := Input.is_action_pressed("jump")
	if salto_presionado and not _salto_anterior_presionado and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_salto_anterior_presionado = salto_presionado


func _velocidad_objetivo_actual() -> float:
	if _agachado:
		return CROUCH_SPEED
	if Input.is_action_pressed("run"):
		return RUN_SPEED
	return WALK_SPEED


# ── Postura / collider ───────────────────────────────────────────────
func _actualizar_postura() -> void:
	var quiere_agacharse := Input.is_action_pressed("crouch")

	if quiere_agacharse and not _agachado:
		_agachado = true
		_fijar_altura_collider(CROUCH_HEIGHT)

	if _agachado:
		_ultimo_can_stand = _puede_pararse()
		if not quiere_agacharse and _ultimo_can_stand:
			_agachado = false
			_fijar_altura_collider(STANDING_HEIGHT)
	else:
		_ultimo_can_stand = true


func _fijar_altura_collider(altura: float) -> void:
	var capsula := _collision_shape.shape as CapsuleShape3D
	capsula.height = altura
	_collision_shape.position.y = altura / 2.0


## No permite volver de crouch a standing si hay techo encima (can_stand).
## Prueba si el collider actual (tamaño crouch) podría desplazarse hacia
## arriba la diferencia de altura sin chocar. No usa motion cero: con motion
## cero, test_move con recovery_as_collision trataría el simple apoyo sobre
## el piso como si fuera una colisión (el cuerpo SIEMPRE toca el piso al
## estar parado), dando falsos "no puede pararse" incluso en espacio libre.
func _puede_pararse() -> bool:
	var espacio_necesario := STANDING_HEIGHT - CROUCH_HEIGHT
	return not test_move(global_transform, Vector3(0.0, espacio_necesario, 0.0))


# ── Contrato de traversal (sección 9) ────────────────────────────────
## Único dueño a la vez: si ya hay un lease vigente, rechaza al segundo
## dueño devolviendo null. begin_traversal() cuenta como renovación del
## tick en curso — el siguiente physics_tick() ya no lo da por sentado.
func begin_traversal(p_owner: Object) -> TraversalLease:
	if _lease != null:
		return null

	_lease = TraversalLease.new(p_owner, global_transform)
	_lease_renovado_este_tick = true
	return _lease


## Movimiento guiado CON colisión (move_and_collide), nunca teleport libre.
## Rechaza cualquier lease que no sea el vigente. Renueva el lease del tick
## SIEMPRE que el lease sea válido — incluso si el resultado final es
## BLOCKED: el lease sigue vigente hasta que el dueño llame end_traversal()
## explícitamente (ver TraversalController._salir_de_hang_por_falla).
##
## last_safe_pose del resultado nunca es "la pose actual porque sí": es
## lease.get_pose_segura(), actualizada SOLO cuando de verdad se confirma
## una pose sin penetración (linear OK, bloqueo lineal que dejó al cuerpo
## en un punto válido, u OK final). Si una pose INMÓVIL resulta penetrada
## por geometría nueva, global_transform ya no es segura — se devuelve la
## última pose segura almacenada, sin pisarla (sección 9.1).
func apply_traversal_pose(lease: TraversalLease, target_pose: Transform3D) -> TraversalMoveResult:
	if lease == null or lease != _lease or not lease.is_valid():
		return TraversalMoveResult.new(TraversalMoveResult.Status.REJECTED, global_transform, "lease_invalido_o_no_vigente")

	_lease_renovado_este_tick = true

	var motion := target_pose.origin - global_transform.origin
	var hay_desplazamiento := motion.length() > _EPSILON_SIN_DESPLAZAMIENTO

	if hay_desplazamiento:
		var colision := move_and_collide(motion)
		if colision != null:
			# Bloqueado en el tramo lineal: global_transform ya quedó en la
			# última posición segura que dejó move_and_collide (con la
			# orientación ANTERIOR — nunca se llegó a evaluar la nueva
			# rotación), y ESO es una pose físicamente válida real: se
			# registra en el lease para que last_safe_pose de un bloqueo
			# futuro no vuelva a caer en algo peor.
			lease._actualizar_pose_segura(global_transform)
			return TraversalMoveResult.new(TraversalMoveResult.Status.BLOCKED, global_transform, "colision_en_movimiento_guiado")

	var rotacion_cambia := not global_transform.basis.is_equal_approx(target_pose.basis)
	var basis_seguro := global_transform.basis
	if rotacion_cambia:
		global_transform.basis = target_pose.basis

	# Hace falta revalidar por solape cuando NO hubo desplazamiento real (una
	# pose inmóvil, como en HANGING) y/o cuando cambia la rotación:
	# move_and_collide con motion ~0 no hace un barrido real y no detecta
	# geometría nueva que haya aparecido exactamente encima de la pose — y
	# tampoco evaluó nunca la footprint de la nueva orientación. test_move
	# con motion cero y recovery_as_collision=true SÍ lo detecta. A
	# diferencia del falso positivo ya corregido en _puede_pararse() (que
	# fijaba position.y a mano, sin el safe_margin de la física real), acá
	# la pose se alcanzó por movimiento guiado real, así que el apoyo
	# normal no dispara recuperación — solo un solape genuino lo hace.
	if not hay_desplazamiento or rotacion_cambia:
		if test_move(global_transform, Vector3.ZERO, null, 0.001, true):
			global_transform.basis = basis_seguro
			var motivo := "rotacion_objetivo_penetra_geometria" if rotacion_cambia \
				else "pose_inmovil_penetrada_por_geometria_nueva"
			if not hay_desplazamiento:
				# global_transform ES la pose inmóvil que acaba de resultar
				# penetrada por algo nuevo: NO es segura. Se reporta la
				# última pose segura ya almacenada, sin sobrescribirla.
				return TraversalMoveResult.new(TraversalMoveResult.Status.BLOCKED, lease.get_pose_segura(), motivo)
			# Hubo desplazamiento lineal válido antes de este chequeo (ya
			# garantizado sin penetración por move_and_collide), y la
			# rotación quedó revertida a la última segura: esta posición sí
			# es una pose segura nueva.
			lease._actualizar_pose_segura(global_transform)
			return TraversalMoveResult.new(TraversalMoveResult.Status.BLOCKED, global_transform, motivo)

	lease._actualizar_pose_segura(global_transform)
	return TraversalMoveResult.new(TraversalMoveResult.Status.OK, global_transform)


## Única salida "normal" del contrato: el dueño se identifica con su lease.
## Restaura velocity a exit_velocity; la locomoción normal vuelve a regir
## desde el próximo physics_tick(). Toda salida —normal o forzada— pasa por
## acá: _forzar_salida_traversal() también la llama, con su propio lease.
func end_traversal(lease: TraversalLease, exit_velocity: Vector3, reason: TraversalExitReason.Value) -> void:
	if lease == null or lease != _lease:
		push_error("PlayerMotor.end_traversal: lease inválido o no es el dueño actual")
		return
	_cerrar_lease(exit_velocity, reason)


func _forzar_salida_traversal() -> void:
	# Salida forzada normalizada: sin impulso residual del tramo guiado.
	end_traversal(_lease, Vector3.ZERO, TraversalExitReason.Value.FORCED_NO_RENEWAL)


func _cerrar_lease(exit_velocity: Vector3, _reason: TraversalExitReason.Value) -> void:
	var saliente := _lease
	_lease = null
	_lease_renovado_este_tick = false
	if saliente != null:
		saliente._invalidar()
	velocity = exit_velocity
