class_name InvHoldMotion
extends RefCounted

## Cómo lleva la mano un objeto sostenido, en un solo lugar para el host y para
## la máquina del jugador (desde el 2026-11-15, revisión pedida en
## docs/net/prompt_claude_revision_objetos_fisicos.md): las mismas cuentas, en
## el mismo orden, con los mismos números.
##
## En cada tick T, con el personaje ya movido en ese tick:
##
## 1. target(): adónde va el punto agarrado (los ojos del personaje más la
##    vista por la distancia) y con qué giro (el pedido, relativo al yaw de la
##    cámara), con lo que trae el input del tick T (ActorInput.hold).
## 2. velocities(): con la pose y las velocidades de después del tick T - 1,
##    las velocidades con que la mano lo lleva en el paso del tick T, acotadas
##    por el Tuning (Hold Follow Time, Move Limit, Accel Limit, Turn Limit y
##    Turn Accel). Contra una pared empuja con eso como mucho.
## 3. guard(): las dos máquinas miran el nivel antes del paso, con las formas
##    achicadas (InvItemPhysics.blocked_inset), en pasos de 1 cm, también al
##    girar sin moverse, y se quedan con lo que no se mete (o, si ya estaba
##    metido, con lo que no se mete más).
## 4. El paso: en el host lo da Jolt, con esas velocidades, sin gravedad ni
##    freno mientras se sostiene (InvWorldItem.begin_hold) y con todos sus
##    choques (con los demás objetos, también). En la máquina del jugador,
##    integrate() hace lo mismo que Jolt sin choques (el centro de masa avanza
##    con la velocidad, el giro es exacto alrededor de él).
##
## El resultado de cada tick se cuantiza igual que viaja (quantize), así lo que
## afirma la máquina del jugador y lo que adopta el host son los mismos números.
## Hasta ese día las velocidades se calculaban en InvWorldItem._integrate_forces,
## que Jolt llama al empezar el cuadro de física, antes del tick: la mano usaba
## el pedido del tick anterior (medido el 2026-11-15 con Godot 4.7.2).

## Lo que afirma la máquina del jugador de lo que sostiene después de un tick
## (va en ActorInput.held_claim): número (4), sesión (4), versión (1), lugar
## (3 × 4), giro (4 × 2), velocidad (3 × 2) y velocidad de giro (3 × 2).
const CLAIM_BYTES := 41
const QUAT_STEPS := 32767.0
## Paso de la velocidad (m/s) y de la velocidad de giro (rad/s) al viajar.
const VELOCITY_STEP := 0.01
## Lo que puede meterse de más, en cada paso de 1 cm, algo que ya arranca
## metido (path_free): lo que varía la profundidad que da Jolt (elegido por
## Claude el 2026-11-15).
const DEPTH_SLACK := 0.001


## Adónde lleva la mano el punto agarrado y con qué giro: Transform3D con el
## giro del objeto y, de origen, el punto. `distance` se acota entre Hold Min y
## Hold Max Distance.
static func target(eyes: Vector3, yaw: float, pitch: float, distance: float, rotation: Quaternion,
		tuning: ActorTuning) -> Transform3D:
	var low := tuning.hold_min_distance if tuning != null else 0.6
	var high := maxf(tuning.hold_max_distance if tuning != null else 2.5, low)
	var look := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(rotation), eyes + look * clampf(distance, low, high))


## El target del input de un tick (ActorInput.hold), con los ojos de ese tick.
static func target_of(eyes: Vector3, input: ActorInput, tuning: ActorTuning) -> Transform3D:
	return target(eyes, input.look_yaw, input.hold_pitch(), input.hold_distance(), input.hold_rotation(), tuning)


## Las velocidades [lineal, de giro] con que la mano lleva el cuerpo en el
## paso que sigue: hacia donde tiene que estar el centro de masa para que el
## punto agarrado (`anchor`, en el espacio del objeto) quede en el target con su
## giro, con velocidades y aceleraciones acotadas. `pose`, `lv` y `av`: cómo
## está ahora; `com_local`: su centro de masa (InvItemPhysics.center_of_mass).
static func velocities(pose: Transform3D, com_local: Vector3, lv: Vector3, av: Vector3, anchor: Vector3,
		goal: Transform3D, tuning: ActorTuning, dt: float) -> Array:
	var step := maxf(dt, 0.0001)
	var follow := maxf(tuning.hold_follow_time if tuning != null else 0.08, 0.001)
	var move_limit := tuning.hold_move_limit if tuning != null else 12.0
	var accel_limit := tuning.hold_accel_limit if tuning != null else 80.0
	var turn_limit := deg_to_rad(tuning.hold_turn_limit if tuning != null else 720.0)
	var turn_accel := deg_to_rad(tuning.hold_turn_accel if tuning != null else 7200.0)
	var com := pose * com_local
	var basis := goal.basis.orthonormalized()
	var wanted := goal.origin - basis * (anchor - com_local)
	var velocity := ((wanted - com) / follow).limit_length(move_limit)
	var next_lv := lv + (velocity - lv).limit_length(accel_limit * step)
	var error := Quaternion(basis) * Quaternion(pose.basis.orthonormalized()).inverse()
	if error.w < 0.0:
		error = -error
	var angle := 2.0 * acos(clampf(error.w, -1.0, 1.0))
	var spin := Vector3.ZERO
	if angle > 0.0001:
		var axis := Vector3(error.x, error.y, error.z) / maxf(sin(angle * 0.5), 0.000001)
		spin = (axis.normalized() * angle / follow).limit_length(turn_limit)
	var next_av := av + (spin - av).limit_length(turn_accel * step)
	return [next_lv, next_av]


## Un paso sin choques, como lo da Jolt: el centro de masa avanza `lv` × `dt`
## y el objeto gira `av` × `dt` alrededor de él.
static func integrate(pose: Transform3D, com_local: Vector3, lv: Vector3, av: Vector3, dt: float) -> Transform3D:
	var com := pose * com_local + lv * dt
	var basis := pose.basis.orthonormalized()
	var angle := av.length() * dt
	if angle > 1e-9:
		basis = (Basis(av / av.length(), angle) * basis).orthonormalized()
	return Transform3D(basis, com - basis * com_local)


## La pose y las velocidades con los mismos números con que viajan.
static func quantize(pose: Transform3D, lv: Vector3, av: Vector3) -> Array:
	var q := pose.basis.orthonormalized().get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var steps := Quaternion(roundi(q.x * QUAT_STEPS), roundi(q.y * QUAT_STEPS), roundi(q.z * QUAT_STEPS), roundi(q.w * QUAT_STEPS))
	var back := Quaternion(steps.x / QUAT_STEPS, steps.y / QUAT_STEPS, steps.z / QUAT_STEPS, steps.w / QUAT_STEPS).normalized()
	var origin := Vector3(_f32(pose.origin.x), _f32(pose.origin.y), _f32(pose.origin.z))
	return [Transform3D(Basis(back), origin), _velocity(lv), _velocity(av)]


static func _f32(value: float) -> float:
	var b := StreamPeerBuffer.new()
	b.put_float(value)
	b.seek(0)
	return b.get_float()


static func _velocity(value: Vector3) -> Vector3:
	return Vector3(clampi(roundi(value.x / VELOCITY_STEP), -32767, 32767), clampi(roundi(value.y / VELOCITY_STEP), -32767, 32767),
			clampi(roundi(value.z / VELOCITY_STEP), -32767, 32767)) * VELOCITY_STEP


## La afirmación de un tick, en CLAIM_BYTES bytes (de una pose ya cuantizada).
static func pack_claim(uid: int, session: int, version: int, pose: Transform3D, lv: Vector3, av: Vector3) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(uid & 0xFFFFFFFF)
	b.put_u32(session & 0xFFFFFFFF)
	b.put_u8(version & 0xFF)
	b.put_float(pose.origin.x)
	b.put_float(pose.origin.y)
	b.put_float(pose.origin.z)
	var q := pose.basis.orthonormalized().get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	for value in [q.x, q.y, q.z, q.w]:
		b.put_16(clampi(roundi(value * QUAT_STEPS), -32767, 32767))
	for value in [lv.x, lv.y, lv.z, av.x, av.y, av.z]:
		b.put_16(clampi(roundi(value / VELOCITY_STEP), -32767, 32767))
	return b.data_array


## La afirmación que armó pack_claim, o {} si no tiene esa forma: {"uid",
## "session", "version", "xf", "lv", "av"}.
static func unpack_claim(data: PackedByteArray) -> Dictionary:
	if data.size() != CLAIM_BYTES:
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var uid := b.get_u32()
	var session := b.get_u32()
	var version := b.get_u8()
	var origin := Vector3(b.get_float(), b.get_float(), b.get_float())
	var q := Quaternion(b.get_16() / QUAT_STEPS, b.get_16() / QUAT_STEPS, b.get_16() / QUAT_STEPS, b.get_16() / QUAT_STEPS)
	var lv := Vector3(b.get_16(), b.get_16(), b.get_16()) * VELOCITY_STEP
	var av := Vector3(b.get_16(), b.get_16(), b.get_16()) * VELOCITY_STEP
	if not origin.is_finite() or q.length_squared() < 0.25 or not q.is_finite():
		return {}
	return {"uid": uid, "session": session, "version": version, "xf": Transform3D(Basis(q.normalized()), origin), "lv": lv,
			"av": av}


## Cuánto difieren dos poses de un objeto: [lo más lejos que quedan su centro
## de masa y su punto agarrado, en metros; el ángulo entre sus giros, en grados].
static func difference(a: Transform3D, b: Transform3D, com_local: Vector3, anchor: Vector3) -> Array:
	var moved := maxf((a * com_local).distance_to(b * com_local), (a * anchor).distance_to(b * anchor))
	var qa := Quaternion(a.basis.orthonormalized())
	var qb := Quaternion(b.basis.orthonormalized())
	var dot := absf(qa.dot(qb))
	return [moved, rad_to_deg(2.0 * acos(clampf(dot, -1.0, 1.0)))]


## El paso de un tick de la mano, sin meterse en el nivel (`mask`): las mismas
## reglas en el host (antes de darle las velocidades a Jolt) y en la máquina del
## jugador (en vez de Jolt). Jolt frena los choques al moverse (CCD), no al
## girar: una caja girada apretada contra la pared de 2 cm la cruzaba con una
## punta (medido el 2026-11-15). Devuelve [velocidad, velocidad de giro, la
## pose después del paso]:
##
## - si todo el camino (en pasos de 1 cm de cualquier punto, también girando sin
##   moverse) está libre (path_free), el paso entero;
## - si no, sin girar, la velocidad con los ejes que dejan el camino libre (así
##   se desliza por una pared en vez de pegarse);
## - si tampoco, solo el giro;
## - si nada, quieto.
## Si ya arrancaba metido (lo apretó una pila, o Jolt lo dejó así), path_free
## lo deja salir o arrastrarse sin meterse más. Hasta el 2026-11-15 solo lo
## dejaba dar un paso de 2 cm que lo sacara entero, y la mano pide más: lo
## metido quedaba trabado (lo encontró el usuario en las dos notebooks).
static func guard(space: PhysicsDirectSpaceState3D, def: InvItemDef, pose: Transform3D, com: Vector3, lv: Vector3, av: Vector3,
		dt: float, mask: int, exclude: Array[RID] = []) -> Array:
	var to := integrate(pose, com, lv, av, dt)
	if space == null or path_free(space, def, pose, to, mask, exclude, 0.01, 64):
		return [lv, av, to]
	var slide := Vector3.ZERO
	for axis in 3:
		var part := Vector3.ZERO
		part[axis] = lv[axis]
		if part == Vector3.ZERO:
			continue
		var tried := slide + part
		if path_free(space, def, pose, integrate(pose, com, tried, Vector3.ZERO, dt), mask, exclude, 0.01, 64):
			slide = tried
	if slide != Vector3.ZERO:
		return [slide, Vector3.ZERO, integrate(pose, com, slide, Vector3.ZERO, dt)]
	var turn := integrate(pose, com, Vector3.ZERO, av, dt)
	if path_free(space, def, pose, turn, mask, exclude, 0.01, 64):
		return [Vector3.ZERO, av, turn]
	return [Vector3.ZERO, Vector3.ZERO, pose]


## Si el objeto puede ir de `from` a `to` sin meterse en nada de `mask`: en
## pasos tan chicos que ningún punto de sus formas avanza más de `step` metros
## por paso (también al girar sin moverse), con las formas achicadas
## (InvItemPhysics.blocked_inset). Como mucho `most` pasos; si haría falta más,
## no (es un movimiento que la mano no da en un tick). `exclude`: lo propio.
##
## Si `from` ya está metido, el camino puede seguir metido mientras no se meta
## más hondo que al arrancar (InvItemPhysics.depth, con DEPTH_SLACK por paso):
## así sale para arriba o se arrastra por el piso, pero no se hunde ni cruza
## una pared; y una vez afuera, no vuelve a meterse.
static func path_free(space: PhysicsDirectSpaceState3D, def: InvItemDef, from: Transform3D, to: Transform3D,
		mask: int, exclude: Array[RID] = [], step := 0.01, most := 48) -> bool:
	var count := steps_between(def, from, to, step)
	if count > most:
		return false
	# Hasta cuánto puede seguir metido; negativo: tiene que estar afuera.
	var limit := -1.0
	if InvItemPhysics.blocked_inset(space, def, from, mask, exclude):
		limit = InvItemPhysics.depth(space, def, from, mask, exclude) + DEPTH_SLACK
	for i in range(1, count + 1):
		var place := from.interpolate_with(to, float(i) / count)
		if not InvItemPhysics.blocked_inset(space, def, place, mask, exclude):
			limit = -1.0
			continue
		if limit < 0.0:
			return false
		var deep := InvItemPhysics.depth(space, def, place, mask, exclude)
		if deep > limit:
			return false
		limit = minf(limit, deep + DEPTH_SLACK)
	return true


## Cuántos pasos hacen falta para que ningún punto del cuerpo avance más de
## `step` por paso entre dos poses: el centro de masa y el giro por lo más
## lejos que llega el cuerpo de él.
static func steps_between(def: InvItemDef, from: Transform3D, to: Transform3D, step: float) -> int:
	var com := InvItemPhysics.center_of_mass(def)
	var box := InvItemPhysics.body_bounds(def)
	var reach := 0.0
	for i in 8:
		reach = maxf(reach, box.get_endpoint(i).distance_to(com))
	var diff := difference(from, to, com, com)
	var travel: float = diff[0] + deg_to_rad(diff[1]) * reach
	return maxi(1, ceili(travel / maxf(step, 0.001)))
