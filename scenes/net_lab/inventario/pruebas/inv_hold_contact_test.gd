extends "res://scenes/net_lab/inventario/pruebas/inv_fisica_test.gd"

## Regresión del temblor del invitado después de tocar otro objeto (2026-11-15).
## Solo: el cambio de versión reconoce el choque y conserva el dibujo durante
## correcciones consecutivas. En pareja: levantar la caja de otro cuerpo y
## moverla en el aire sin quedar corrigiendo aquel contacto para siempre.
## Usa los mismos argumentos mano_host / mano_cliente que inv_fisica_test.

const CONTACT_SPOT := TEST_FLOOR + Vector3(0, 0, 2)
const CONTACT_BOX := TEST_FLOOR + Vector3(0, 0.278, 1)

var _visual_probe := {}
var _correction_samples := 0
var _worst_visual_jump := 0.0


func _solo() -> void:
	await get_tree().process_frame
	lab._start(0)
	await _wait_local()
	_test_floor()
	await _ticks(2)
	var uid := _spawn(&"caja_de_herramientas", Transform3D(Basis.IDENTITY, TEST_FLOOR + Vector3(0, 2, 0)))
	_test_contact_checkpoint(uid)
	_test_consecutive_corrections(uid)
	_test_visual_floor(uid)
	_test_input_packets()
	_test_reordered_revisions()
	_test_input_readiness()
	_test_release_smoothing(uid)
	_finish()


func _test_contact_checkpoint(uid: int) -> void:
	var bodies := net.bodies
	var body := _body(uid)
	var here := body.global_transform
	var peer := 12345
	var claims := {}
	var source := bodies.claim_source
	bodies.claim_source = func(_peer: int, tick: int) -> PackedByteArray: return claims.get(tick, PackedByteArray())
	# La historia coincide hasta 90; un choque en 100 cambia la trayectoria.
	var hold := {"peer": peer, "session": 1, "anchor": Vector3.ZERO, "version": 0,
			"fresh": false, "prev": here, "since": 90, "bumped": 90,
			"checkpoint": [90, here], "touched": 100}
	bodies.holds()[uid] = hold
	var claimed := here.translated(Vector3(0.01, 0, 0))
	claims[100] = InvHoldMotion.pack_claim(uid, 1, 0, claimed, Vector3.ZERO, Vector3.ZERO)
	bodies._judge_holds(100)
	_check(hold["version"] == 1 and body.global_transform.is_equal_approx(here),
			"el choque rechaza la trayectoria anterior y conserva el resultado físico del host")
	claims[101] = InvHoldMotion.pack_claim(uid, 1, 0, claimed, Vector3.ZERO, Vector3.ZERO)
	_check(bodies._judge_claim(uid, hold, body, 101) == "versión vieja",
			"una afirmación anterior a la corrección sigue rechazada")
	claims[101] = InvHoldMotion.pack_claim(uid, 1, 1, claimed, Vector3.ZERO, Vector3.ZERO)
	var result := bodies._judge_claim(uid, hold, body, 101)
	_check(result == "adoptada", "después de incorporar el choque se vuelve a adoptar: " + result)
	# Un contacto NUEVO tiene que volver a impedir borrar la respuesta física.
	hold["touched"] = 102
	claims[102] = InvHoldMotion.pack_claim(uid, 1, 1, claimed.translated(Vector3(0.01, 0, 0)), Vector3.ZERO, Vector3.ZERO)
	_check(bodies._judge_claim(uid, hold, body, 102) == "tocó otro objeto",
			"un choque nuevo sigue protegido aunque ya se corrigió el anterior")
	bodies.holds().erase(uid)
	bodies.claim_source = source


func _test_consecutive_corrections(uid: int) -> void:
	var copy := _body(uid)
	var place := copy.global_transform
	var com := InvItemPhysics.center_of_mass(copy.def)
	hands._uid = uid
	hands._session = 1
	hands._confirmed = true
	hands._anchor = com
	hands._start_tick = 90
	hands._checked = -1
	hands._version = 0
	hands._pred.clear()
	hands._goals.clear()
	hands._shown = Transform3D(Basis(Vector3.UP, 0.1) * place.basis, place.origin + Vector3(0.15, 0, 0))
	hands._smooth_pos = Vector3(0.15, 0, 0)
	hands._smooth_turn = Quaternion(Vector3.UP, 0.1)
	hands._smooth_left = 4
	for version in range(1, 4):
		var host_tick := 99 + version
		var tick := host_tick + 3
		var old_shown := hands._shown
		hands._pred[tick - 1] = [place, Vector3.ZERO, Vector3.ZERO]
		var corrected := Transform3D(Basis(Vector3.UP, -0.1 * version), place.origin + Vector3(-0.1 * version, 0, 0))
		net.bodies.add_sample(uid, host_tick, corrected, Vector3.ZERO, false, true, Vector3.ZERO, version)
		hands._reconcile(tick, copy.def, com)
		hands._show(copy, hands._pred[tick - 1], com)
		var diff := InvHoldMotion.difference(old_shown, hands._shown, com, Vector3.ZERO)
		_check(diff[0] < 0.00001 and diff[1] < 0.05,
				"corrección consecutiva %d conserva lo que se veía: %.4f m, %.3f grados" % [version, diff[0], diff[1]])
		# Avanza el suavizado; llega otra corrección antes de que termine.
		hands._show(copy, hands._pred[tick - 1], com)
	hands._uid = 0
	hands._confirmed = false
	hands._pred.clear()
	hands._smooth_left = 0


func _test_visual_floor(uid: int) -> void:
	var copy := _body(uid)
	var com := InvItemPhysics.center_of_mass(copy.def)
	var ground := _on_floor(&"caja_de_herramientas", TEST_FLOOR, 0.002)
	hands._shown = ground
	var raw := ground.translated(Vector3.UP * 0.12)
	hands._start_smoothing(ground, raw, com)
	# El siguiente tick crudo baja 3 cm, pero el dibujo ya estaba en el piso.
	var next := raw.translated(Vector3.DOWN * 0.03)
	hands._show(copy, [next, Vector3.ZERO, Vector3.ZERO], com)
	_check(hands._shown.origin.y < ground.origin.y + 0.005 and hands._shown.origin.distance_to(ground.origin) < 0.01,
			"el suavizado contra el piso no salta a la pose cruda 9 cm más arriba")
	_check(not InvItemPhysics.blocked_inset(actor.get_world_3d().direct_space_state, copy.def, hands._shown, InvAuthority.WORLD_MASK),
			"el dibujo corregido sigue fuera del piso")
	for i in InvHands.SMOOTH_TICKS:
		hands._show(copy, [next, Vector3.ZERO, Vector3.ZERO], com)
	_check(hands._shown.is_equal_approx(next), "al terminar el suavizado converge a lo predicho")
	# Dos extremos libres separados por una pared de 2 cm: no se cruza al dibujar.
	var wall := _wall(TEST_FLOOR + Vector3(2, 1, 0), Vector2(2, 2))
	var from := Transform3D(Basis.IDENTITY, TEST_FLOOR + Vector3(2, 1, 0.4))
	var to := from.translated(Vector3(0, 0, -0.8))
	hands._shown = from
	hands._smooth_left = 0
	hands._show(copy, [to, Vector3.ZERO, Vector3.ZERO], com)
	_check(hands._shown.origin.z > wall.global_position.z,
			"una corrección no salta a través de una pared fina aunque el destino esté libre")
	wall.queue_free()


func _test_input_packets() -> void:
	for holding in [false, true]:
		for uses in [0, ActorInput.MAX_USES]:
			var records := []
			var held := InvHoldMotion.pack_claim(1, 1, 0, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
			var state := ActorState.new().to_bytes()
			for i in NetSync.INPUT_REDUNDANCY:
				var input := ActorInput.make(100 + i, Vector2.ZERO, 0, 0, 0)
				if holding:
					input.hold = ActorInput.pack_hold(1, 0, 1, Quaternion.IDENTITY)
					input.held_claim = held
				for use in uses:
					input.uses.append([use + 1, 0, -1])
				records.append([input, state])
			var seen := []
			var packets := NetSync.input_packets(records, 200)
			for packet in packets:
				_check(packet.size() <= NetSync.MAX_INPUT_PACKET_BYTES, "payload de inputs cabe sin fragmentación: %d bytes" % packet.size())
				var b := StreamPeerBuffer.new()
				b.data_array = packet
				_check(b.get_u16() == 200, "cada datagrama conserva el RTT")
				var count := b.get_u8()
				_check(count <= NetSync.INPUT_REDUNDANCY, "cada datagrama conserva el límite de registros")
				for i in count:
					var input := ActorInput.read_from(b)
					_check(input != null and input.uses.size() == uses and input.held_claim == (held if holding else PackedByteArray()),
							"el registro llega entero con sus usos y la afirmación del objeto")
					seen.append(input.tick if input != null else -1)
					var length := b.get_u8()
					_check(b.get_data(length)[1] == state, "conserva la afirmación del personaje")
				_check(b.get_available_bytes() == 0, "datagrama sin bytes sobrantes")
			_check(seen[0] == 105, "el primer datagrama prioriza el tick más reciente con sus predecesores")
			seen.sort()
			_check(seen == [100, 101, 102, 103, 104, 105], "no se pierde ninguno de los seis ticks redundantes")
	var heartbeat := NetSync.input_packets([], 12)
	_check(heartbeat.size() == 1 and heartbeat[0].size() == 3, "sin predicción sigue saliendo el heartbeat")


func _test_reordered_revisions() -> void:
	var newer := ActorInput.make(100, Vector2.ZERO, 0, 0, 0)
	var older := ActorInput.make(100, Vector2.ZERO, 0, 0, 0)
	for versions: Array in [[1, 2], [255, 0], [254, 1]]:
		older.held_claim = InvHoldMotion.pack_claim(1, 1, versions[0], Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
		newer.held_claim = InvHoldMotion.pack_claim(1, 1, versions[1], Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
		_check(NetSync.is_older_hold_claim(older, newer), "un duplicado atrasado no borra la corrección: %d después de %d" % versions)
		_check(not NetSync.is_older_hold_claim(newer, older), "la revisión nueva sí reemplaza la anterior")
	_check(not NetSync.is_older_hold_claim(newer, newer), "una retransmisión de la misma versión sigue admitida")
	older.held_claim = InvHoldMotion.pack_claim(1, 2, 0, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO)
	_check(not NetSync.is_older_hold_claim(older, newer), "no compara revisiones de sesiones distintas")


func _test_input_readiness() -> void:
	actor.simulated = false
	_check(hands.blocked(), "antes de simular al jugador la mano no permite agarrar sin enviar inputs")
	actor.simulated = true
	_check(not hands.blocked(), "la mano se habilita al empezar la simulación del jugador")


func _test_release_smoothing(uid: int) -> void:
	# Usa una copia existente sin avanzar la física ni mandar pedidos. La mano
	# entra momentáneamente por su rama cliente para verificar la transición.
	var authority := net.authority
	net.authority = null
	var raw := Transform3D(Basis.IDENTITY, TEST_FLOOR + Vector3(0, 2, 1))
	var visible := raw.translated(Vector3(0.1, 0, 0))
	hands._uid = uid
	hands._confirmed = true
	hands._done_tick = 110
	hands._shown = visible
	hands._pred[110] = [raw, Vector3.ZERO, Vector3.ZERO]
	hands._end_local()
	_check(not hands._free.is_empty() and hands._smooth_left > 0,
			"al soltar conserva el suavizado pendiente con el pivote de caída")
	hands._predict_free(111)
	_check(absf(hands._shown.origin.x - visible.origin.x) < 0.001,
			"el primer tick soltado no pierde los 10 cm de suavizado lateral pendiente")
	net.authority = authority
	hands._free = {}
	hands._blend_uid = 0
	hands._smooth_left = 0


func _mano_host() -> void:
	_test_floor()
	await _wait_local()
	await _until(func() -> bool: return _first_remote() != 0, 30.0)
	var peer := _first_remote()
	_check(peer != 0, "llegó el invitado")
	if peer == 0:
		_finish()
		return
	await _teleport(CONTACT_SPOT + Vector3(0, 0, 4), 0)
	_spawn(&"caja_de_herramientas", Transform3D(Basis.IDENTITY, TEST_FLOOR + Vector3(0, 0, 1)))
	var box := _spawn(&"caja_de_herramientas", Transform3D(Basis.IDENTITY, CONTACT_BOX))
	_move_remote(peer, CONTACT_SPOT, 0)
	_check(await _until(func() -> bool: return _holder(box) == peer, 30.0), "el invitado sostiene la caja apoyada en otra caja")
	var contacts := 0
	var clean_ticks := 0
	var tail := []
	while _holder(box) == peer:
		var hold: Dictionary = net.bodies.holds().get(box, {})
		if _body(box).get_colliding_bodies().any(func(other: Node) -> bool: return other is RigidBody3D):
			contacts += 1
			clean_ticks = 0
		else:
			clean_ticks += 1
		var stats: Dictionary = net.bodies.adoption.get(peer, {})
		var recovered: int = stats.get("adoptada", 0) + stats.get("igual", 0)
		tail.append([hold.get("version", 0), recovered])
		if tail.size() > 45:
			tail.pop_front()
		await _ticks(1)
	_check(contacts > 0, "Jolt registró contacto real con otro objeto (%d ticks)" % contacts)
	var accepted: int = int(tail[-1][1]) - int(tail[0][1]) if tail.size() == 45 else 0
	_check(accepted >= 20, "recupera la adopción al parar después del contacto (%d ticks aceptados de los últimos 45)" % accepted)
	_check(tail.size() >= 25 and tail[-25][0] == tail[-1][0] and clean_ticks >= 60,
			"al recuperarse deja de cambiar de versión por el contacto viejo")
	_log(net.bodies.adoption_text(peer))
	await _until(func() -> bool: return multiplayer.get_peers().is_empty(), 15.0)
	_finish()


func _mano_cliente() -> void:
	_test_floor()
	await _wait_local()
	await _until(func() -> bool: return actor.global_position.distance_to(CONTACT_SPOT) < 0.3 \
			and _uid_near(CONTACT_BOX, &"caja_de_herramientas") != 0, 30.0)
	var box := _uid_near(CONTACT_BOX, &"caja_de_herramientas")
	_check(box != 0, "el host preparó la caja sobre otro objeto")
	if box == 0:
		_finish()
		return
	await _ticks(30)
	if await _mano_grab(box, _box_of(box).get_center()):
		# Un poco hacia abajo asegura contacto; después se retira y se gira libre.
		camera.pitch = -1.0
		hands._distance = 1.6
		_sample_correction()
		for i in 24:
			await _ticks(1)
			_sample_correction()
		hands._distance = 1.0
		for i in 90:
			camera.pitch = lerpf(-1.0, 0.2, minf(i / 35.0, 1.0))
			camera.yaw += deg_to_rad(1.5)
			await _ticks(1)
			_sample_correction()
		var resets_before := hands.held_version_resets
		var low_throttle := 32.0
		for i in 180:
			camera.yaw += deg_to_rad(1.5)
			await _ticks(1)
			_sample_correction()
			var peer := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(1)
			low_throttle = minf(low_throttle, peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE))
		# Con pérdida real alta, pedir cero correcciones durante el giro no es
		# un contrato válido. Sí lo son recuperar la misma pose al parar y no
		# seguir corrigiendo aquel contacto. Se exige medio segundo de acuerdo
		# continuo, sin apagar el simulador ni el control de congestión de ENet.
		var stable := 0
		var last_resets := hands.held_version_resets
		var distance := INF
		for i in 300:
			await _ticks(1)
			_sample_correction()
			var newest := net.bodies.newest_sample(box)
			var predicted: Array = hands._pred.get(newest[0], []) if not newest.is_empty() else []
			var same := false
			if not predicted.is_empty() and hands.held_uid() == box:
				var diff := InvHoldMotion.difference(predicted[0], newest[1], InvItemPhysics.center_of_mass(net.world_view(box).def), hands._anchor)
				distance = diff[0]
				same = diff[0] < 0.02 and diff[1] < 2.0 and hands.held_version_resets == last_resets
			stable = stable + 1 if same else 0
			last_resets = hands.held_version_resets
			if stable >= 30:
				break
		_check(hands.held_uid() == box, "sigue agarrada después de levantarla y girar")
		_check(stable >= 30, "al parar, host y predicción coinciden 30 ticks seguidos (distancia final %.4f m)" % distance)
		_log("medición: recuperada con %.4f m de diferencia; %d correcciones en el aire; throttle mínimo ENet %.0f/32" % [
				distance, hands.held_version_resets - resets_before, low_throttle])
		var visual_result := "correcciones durante contacto sin saltos del suavizado: %d muestras, máximo %.2f mm" % [_correction_samples, _worst_visual_jump * 1000]
		_log("medición: " + visual_result)
		_check(_correction_samples >= 2 and _worst_visual_jump < 0.001, visual_result)
		_log(hands.prediction_text())
		hands.release()
	await _ticks(30)
	_finish()


## En un tick corregido, el cambio dibujado debe ser el movimiento de ESE tick,
## sin sumar un salto que borre la corrección visual todavía pendiente.
func _sample_correction() -> void:
	var tick := hands._done_tick
	if not _visual_probe.is_empty() and tick == int(_visual_probe["tick"]) + 1 \
			and hands.held_version_resets > int(_visual_probe["resets"]) and hands._smooth_left == InvHands.SMOOTH_TICKS - 1:
		var before: Array = hands._pred.get(tick - 1, [])
		var now: Array = hands._pred.get(tick, [])
		if not before.is_empty() and not now.is_empty():
			var pivot := hands._anchor
			var last: Transform3D = _visual_probe["shown"]
			var expected := last * pivot + (now[0] as Transform3D) * pivot - (before[0] as Transform3D) * pivot
			var error := expected.distance_to(hands._shown * pivot)
			var basis := last.basis * (before[0] as Transform3D).basis.inverse() * (now[0] as Transform3D).basis
			var xf := Transform3D(basis, expected - basis * pivot)
			var space := actor.get_world_3d().direct_space_state
			var def := net.world_view(hands.held_uid()).def
			if not InvHoldMotion.path_free(space, def, last, xf, InvAuthority.WORLD_MASK, [], 0.01, 64):
				# Contra el piso puede acortar el movimiento, pero nunca sustituirlo
				# por un salto al estado crudo (el defecto que mide esta prueba).
				var step := ((now[0] as Transform3D) * pivot).distance_to((before[0] as Transform3D) * pivot)
				error = maxf(0, (hands._shown * pivot).distance_to(last * pivot) - step)
			_worst_visual_jump = maxf(_worst_visual_jump, error)
			_correction_samples += 1
	_visual_probe = {"tick": tick, "shown": hands._shown, "resets": hands.held_version_resets}
