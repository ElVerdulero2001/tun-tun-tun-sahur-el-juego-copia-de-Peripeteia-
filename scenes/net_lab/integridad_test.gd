extends Node

## Prueba de la integridad corporal, la luz naranja, el daño de caída y la
## muerte (punto 1 del roadmap, 2026-11-05), en el laboratorio de verdad y en
## un solo proceso, jugando solo. Camina como el jugador (el Mapa de entrada y
## el giro de la cámara), usa los consumibles por la interfaz y mira lo que
## muestran el HUD, el panel y la cámara.
##
## Cubre: el estado nuevo de ida y vuelta; un salto normal y uno con el súper
## (sin daño); las tres tablas de la torre de parkour (segura, lastima y
## letal); el panel a la derecha del inventario y la caja que tiene prioridad;
## el botiquín (cura la salud y no las piernas); la cápsula letal (el mismo
## flujo de muerte que la caída letal); el desplome y la caída de cámara una
## vez por muerte; agarrarse de un borde antes de tocar el piso; aterrizar
## sobre una plataforma que sube y sobre una que baja; y repetir los ticks de
## un aterrizaje, con lo que no se cobra dos veces ni se repite el desplome.
##
## --headless --fixed-fps 60 --scene res://scenes/net_lab/integridad_test.tscn

const Op := InvProtocol.Op
const H := ActorState.HEALTH_UNIT
const FULL := ActorState.INTEGRITY_FULL
const LEGS := [ActorState.Part.LEG_LEFT, ActorState.Part.LEG_RIGHT]
## Un lugar libre del piso, sin cables arriba (sobre donde se aparece pasa uno
## que el salto con el súper alcanza), para saltar y caer. La plataforma de
## prueba va en el mismo lugar mientras dura su parte.
const OPEN_FLOOR := Vector3(-4, 0, -24)
## Plataforma de prueba que sube y baja rápido, en un lugar libre del piso.
const LIFT_AT := OPEN_FLOOR
const LIFT_ID := 77

var lab: Node3D
var net: InvNet
var hud: LabHud
var ui: InvUI
var tuning: ActorTuning
var actor: ActorBody
var camera: LabCamera
var tower: Node3D
var _answers := {}
var _checks := 0
var _failures := 0


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[integridad_test] TIEMPO AGOTADO")
		get_tree().quit(2))
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	add_child(lab)
	net = lab.get_node("Inventario")
	hud = lab.get_node("Hud/Instrumentos")
	ui = lab.get_node("Hud/InventarioUI")
	camera = lab.get_node("CameraRig")
	tower = lab.get_node("Level/TorreDeParkour")
	tuning = lab.tuning
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	await get_tree().process_frame
	lab._start(0)
	for i in 120:
		await get_tree().physics_frame
		if net.replica.own != null and is_instance_valid(lab._local_actor):
			break
	actor = lab._local_actor
	await _state_and_start()
	await _injury_light_rule()
	await _jumps_are_safe()
	var harm := await _three_boards()
	await _consumables(harm)
	await _heal_parts()
	await _ledge_grab_first()
	await _moving_platform()
	await _replay_does_not_repeat()
	print("[integridad_test] %d comprobaciones, %d fallas" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Ayudas --------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[integridad_test] FALLA: %s" % what)


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Espera `seconds` segundos reales (el desplome y el aviso van con el reloj real).
func _real_wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _health() -> float:
	return actor.state.health / float(H)


func _legs() -> Array:
	return LEGS.map(func(part: int) -> int: return actor.state.integrity[part])


func _others_full() -> bool:
	for part in [ActorState.Part.HEAD, ActorState.Part.TORSO, ActorState.Part.ARM_LEFT, ActorState.Part.ARM_RIGHT]:
		if actor.state.integrity[part] != FULL:
			return false
	return true


func _req(op: int, args: Array, uids: Array = []) -> Array:
	var seq := net.replica.request(op, args, uids)
	if seq == 0:
		return [false, "no salió"]
	for i in 30:
		if _answers.has(seq):
			return _answers[seq]
		await get_tree().physics_frame
	return [false, "sin respuesta"]


## Parado en `position` (del mundo), mirando y con la cámara hacia `yaw`.
func _stand(position: Vector3, yaw: float) -> void:
	var state := actor.state
	state.position = position
	state.velocity = Vector3.ZERO
	state.mode = ActorState.Mode.GROUND
	state.on_floor = true
	state.base_id = 0
	state.facing_yaw = yaw
	state.quantize()
	actor.apply_state(state)
	actor.teleported()
	camera.yaw = yaw
	await _ticks(3)


## Quieto en el aire en `position`, mirando y con la cámara hacia `yaw`.
func _hold_in_air(position: Vector3, yaw: float) -> void:
	var state := actor.state
	state.position = position
	state.velocity = Vector3.ZERO
	state.mode = ActorState.Mode.AIR
	state.on_floor = false
	state.base_id = 0
	state.facing_yaw = yaw
	state.jumped = false
	state.quantize()
	actor.apply_state(state)
	actor.teleported()
	camera.yaw = yaw


## Espera hasta que quede apoyado en Suelo, como mucho `most` ticks.
func _until_landed(most := 300) -> bool:
	for i in most:
		await get_tree().physics_frame
		if actor.state.on_floor and actor.state.mode == ActorState.Mode.GROUND:
			return true
	return false


## Un punto de la torre de parkour (en sus coordenadas) en el mundo.
func _on_tower(local: Vector3) -> Vector3:
	return tower.global_transform * local


## Desde la terraza, camina hacia `yaw` hasta salir por la punta de la tabla,
## suelta las teclas en el aire y espera a tocar el piso.
func _walk_off(start_local: Vector3, yaw: float) -> bool:
	await _stand(_on_tower(start_local), yaw)
	Input.action_press("move_forward")
	var left := false
	for i in 240:
		await get_tree().physics_frame
		if not actor.state.on_floor and actor.state.mode == ActorState.Mode.AIR:
			left = true
			break
	Input.action_release("move_forward")
	if not left:
		return false
	return await _until_landed()


## Lo que tiene que quitar una caída a esa velocidad según el Tuning:
## [puntos de salud, centésimas de cada pierna].
func _expected(impact: float) -> Array:
	var share := (impact - tuning.fall_safe_speed) / (tuning.fall_lethal_speed - tuning.fall_safe_speed)
	@warning_ignore("integer_division")
	return [roundi(share * tuning.health_max), roundi(share * tuning.fall_leg_damage) * ActorState.INTEGRITY_UNIT / 2]


# --- 1. El estado nuevo y el arranque -----------------------------------------------

func _state_and_start() -> void:
	await _frames(10)
	var state := actor.state
	_check(state.integrity.size() == ActorState.PARTS and state.integrity.count(FULL) == ActorState.PARTS,
			"empieza con las seis partes al 100 %%: %s" % [state.integrity])
	_check(not hud.injury_warning() and not state.injured(), "la luz naranja empieza apagada")
	_check(hud.integrity_texts() == PackedStringArray(["100 %", "100 %", "100 %", "100 %", "100 %", "100 %"]),
			"el panel diría 100 %% en todo: %s" % [hud.integrity_texts()])
	_check(not hud.integrity_panel_rect().has_area(), "con el inventario cerrado no hay panel")
	var copy := state.copy()
	copy.integrity[ActorState.Part.ARM_RIGHT] = 4321
	var bytes := copy.to_bytes()
	_check(bytes.size() == ActorState.BYTE_SIZE and ActorState.BYTE_SIZE == 165 and ActorState.BYTE_SIZE <= 255,
			"el estado mide %d bytes (cabe en el byte de largo del snapshot)" % bytes.size())
	_check(ActorState.from_bytes(bytes).integrity == copy.integrity and ActorState.from_bytes(bytes).to_bytes() == bytes,
			"la integridad va y vuelve en los bytes")
	_check(bytes.slice(0, 93) == state.to_bytes().slice(0, 93), "los primeros 93 bytes siguen siendo el movimiento")
	_check(not ClaimAdoption._vitals_possible(copy, state) and ClaimAdoption._vitals_possible(state.copy(), state),
			"el host no adopta una integridad distinta de la suya")
	_check(tuning.with_boost(true).fall_safe_speed == tuning.fall_safe_speed
			and tuning.with_boost(true).fall_lethal_speed == tuning.fall_lethal_speed,
			"el súper no cambia los umbrales de caída")
	_check(copy.describe().contains("integridad="), "describe() muestra la integridad")


# --- 2. Saltos normales y con el súper: sin daño --------------------------------------

## La luz naranja desde el 2026-11-09 (como el concepto del usuario): parpadea
## con alguna parte que el panel muestre en injury_light_percent (60) o menos, y
## con todas arriba se apaga del todo. Cuenta el número que se lee: 60,99 %
## dice 60 % y avisa.
func _injury_light_rule() -> void:
	var arm := ActorState.Part.ARM_LEFT
	var limit := hud.injury_light_percent
	for case: Array in [[(limit + 1) * 100, false], [(limit + 1) * 100 - 1, true], [limit * 100, true],
			[ActorState.INTEGRITY_FULL - 1, false], [1, true]]:
		actor.state.integrity[arm] = case[0]
		await _ticks(2)
		_check(hud.injury_warning() == case[1], "un brazo en %s: la luz %s" % [hud.integrity_texts()[arm],
				"parpadea" if case[1] else "apagada"])
	actor.state.integrity[arm] = 3000
	await _frames(2)
	var samples := []
	var start := Time.get_ticks_msec()
	var span := roundi(hud.injury_blink_seconds * 1000.0 * 2.3)
	while Time.get_ticks_msec() - start < span:
		samples.append(hud.injury_lamp_lit())
		await get_tree().process_frame
	_check(samples.size() > 4 and samples[0] and samples.has(false) and samples.back(),
			"parpadea: arranca prendida, se apaga y se vuelve a prender (%d muestras en %d ms)" % [samples.size(), span])
	actor.state.integrity[arm] = FULL
	await _ticks(2)
	_check(not hud.injury_warning() and not hud.injury_lamp_lit() and actor.state.integrity.count(FULL) == ActorState.PARTS,
			"con todo entero, apagada del todo")


func _jumps_are_safe() -> void:
	await _stand(OPEN_FLOOR, 0.0)
	lab.jump_presses = (lab.jump_presses + 1) & 0xFF
	await _ticks(5)
	var landed := await _until_landed()
	var normal: float = actor.last_landing[0] if not actor.last_landing.is_empty() else -1.0
	_check(landed and normal > 4.0 and normal < 6.0 and actor.state.health == 100 * H, "un salto normal cae a %.2f m/s, sin daño" % normal)
	# Corriendo y saltando (hacia +X, donde el piso está libre): lo de costado
	# no cuenta, solo contra el piso.
	await _stand(OPEN_FLOOR, -PI * 0.5)
	Input.action_press("move_forward")
	Input.action_press("run")
	await _ticks(15)
	lab.jump_presses = (lab.jump_presses + 1) & 0xFF
	await _ticks(5)
	var horizontal := Vector2(actor.state.velocity.x, actor.state.velocity.z).length()
	landed = await _until_landed()
	Input.action_release("move_forward")
	Input.action_release("run")
	var running: float = actor.last_landing[0]
	_check(landed and horizontal > 4.0 and absf(running - normal) < 0.3,
			"corriendo a %.1f m/s cae igual contra el piso: %.2f m/s" % [horizontal, running])
	lab.power_presses = (lab.power_presses + 1) & 0xFF
	await _ticks(3)
	_check(actor.state.boosted, "súper prendido")
	await _stand(OPEN_FLOOR, 0.0)
	lab.jump_presses = (lab.jump_presses + 1) & 0xFF
	await _ticks(5)
	_check(actor.state.mode == ActorState.Mode.AIR and actor.state.velocity.y > 5.5, "salta con el súper: %.2f m/s para arriba" % actor.state.velocity.y)
	landed = await _until_landed()
	var boosted: float = actor.last_landing[0]
	_check(landed and boosted > 6.5 and boosted < tuning.fall_safe_speed - 2.0,
			"un salto con el súper cae a %.2f m/s: margen de %.1f m/s hasta la segura (%.1f)" % [boosted,
			tuning.fall_safe_speed - boosted, tuning.fall_safe_speed])
	_check(actor.state.health == 100 * H and actor.state.integrity.count(FULL) == ActorState.PARTS and not hud.injury_warning(),
			"el súper no lastima: salud %.1f, integridad completa, luz apagada" % _health())
	lab.power_presses = (lab.power_presses + 1) & 0xFF
	await _ticks(3)
	_check(not actor.state.boosted, "súper apagado")
	print("[integridad_test] aterrizajes: salto %.3f, corriendo %.3f, con el súper %.3f m/s" % [normal, running, boosted])


# --- 3. Las tres tablas de la torre -----------------------------------------------------

## Devuelve lo que dejó la caída que lastima: [salud, piernas].
func _three_boards() -> Array:
	var deaths := actor.state.deaths
	# Segura: desde la terraza 2 (4 m), hacia -X.
	var ok := await _walk_off(Vector3(-4.3, 4.0, -2.0), PI * 0.5)
	var safe: float = actor.last_landing[0]
	_check(ok and BaseRegistry.world_position(actor.state).y < 0.05, "de la tabla verde al piso")
	_check(safe > 8.0 and safe < tuning.fall_safe_speed and actor.state.health == 100 * H and _legs() == [FULL, FULL]
			and not hud.injury_warning(), "caída segura: %.2f m/s, salud %.1f, piernas %s, luz apagada" % [safe, _health(), _legs()])
	# Lastima: desde la terraza 3 (7 m), hacia -Z.
	ok = await _walk_off(Vector3(-4.25, 7.0, -4.2), 0.0)
	var hurt: float = actor.last_landing[0]
	var expected := _expected(hurt)
	_check(ok and BaseRegistry.world_position(actor.state).y < 0.05, "de la tabla amarilla al piso")
	_check(hurt > tuning.fall_safe_speed and hurt < tuning.fall_lethal_speed, "caída que lastima: %.2f m/s, entre la segura y la letal" % hurt)
	_check(actor.state.health == (100 - expected[0]) * H and actor.last_landing[1] == expected[0] and actor.state.deaths == deaths,
			"quita %d de salud (queda %.1f), sin morir" % [expected[0], _health()])
	_check(_legs() == [FULL - expected[1], FULL - expected[1]] and _others_full(),
			"las dos piernas pierden lo mismo (%s) y lo demás sigue al 100 %%" % [_legs()])
	_check(hud.injury_warning(), "la luz naranja parpadea: las piernas dicen 60 % o menos")
	var texts := hud.integrity_texts()
	@warning_ignore("integer_division")
	var leg_text := "%d %%" % ((FULL - expected[1]) / ActorState.INTEGRITY_UNIT)
	_check(texts[ActorState.Part.LEG_LEFT] == leg_text and texts[ActorState.Part.LEG_RIGHT] == leg_text and texts[0] == "100 %",
			"el panel dice %s en cada pierna: %s" % [leg_text, texts])
	_check(hud.needles()[0] < 10.0, "la aguja de la salud baja (la salud y la integridad van aparte)")
	var after := [actor.state.health, _legs()]
	await _panel_and_box()
	# Letal: desde la terraza 4 (9,5 m), hacia +X, en primera persona.
	camera._wanted_zoom = 0.0
	camera._zoom = 0.0
	await _frames(5)
	var collapses := actor.collapses_started
	var shown := hud.deaths_shown
	await _stand(_on_tower(Vector3(4.2, 9.5, -4.4)), -PI * 0.5)
	Input.action_press("move_forward")
	var fell := false
	for i in 240:
		await get_tree().physics_frame
		if actor.state.deaths != deaths:
			fell = true
			break
	Input.action_release("move_forward")
	var lethal: float = actor.last_landing[0]
	_check(fell and lethal >= tuning.fall_lethal_speed and actor.last_landing[2], "caída letal: %.2f m/s" % lethal)
	_check(actor.state.deaths == (deaths + 1) & 0xFF and actor.state.health == 100 * H, "una muerte de prueba y la salud al máximo")
	_check(actor.state.integrity.count(FULL) == ActorState.PARTS and not hud.injury_warning(),
			"la muerte devuelve las seis partes y apaga la luz")
	await _frames(3)
	_check(actor.collapses_started == collapses + 1 and actor.is_collapsing(), "empieza un desplome")
	_check(hud.deaths_shown == shown + 1, "el aviso de muerte sale una vez")
	_check(camera.death_fall_amount() > 0.0, "en primera persona la cámara cae")
	await _real_wait(0.5)
	var eye := camera.global_position.y - actor.get_global_transform_interpolated().origin.y
	_check(eye < 0.6, "la cámara queda cerca del piso: a %.2f m de los pies" % eye)
	await _real_wait(1.6)
	_check(not actor.is_collapsing() and camera.death_fall_amount() == 0.0, "se levanta y la cámara vuelve")
	eye = camera.global_position.y - actor.get_global_transform_interpolated().origin.y
	_check(eye > 1.4, "la cámara volvió a la cabeza: %.2f m" % eye)
	await _ticks(30)
	_check(actor.collapses_started == collapses + 1 and hud.deaths_shown == shown + 1, "el desplome y el aviso no se repiten")
	camera._wanted_zoom = camera.start_zoom
	camera._zoom = camera.start_zoom
	print("[integridad_test] tablas: segura %.3f, lastima %.3f (salud -%d, piernas -%.2f %%), letal %.3f m/s" % [safe, hurt,
			expected[0], expected[1] / float(ActorState.INTEGRITY_UNIT), lethal])
	return after


# --- 4. El panel a la derecha, y la caja con prioridad --------------------------------

func _panel_and_box() -> void:
	ui.open()
	await _frames(3)
	var panel := hud.integrity_panel_rect()
	var own := ui._panel_rect(InvProtocol.OWN)
	_check(panel.has_area() and panel.position.x > own.end.x and is_equal_approx(panel.position.y, own.position.y)
			and is_equal_approx(panel.size.y, own.size.y), "con Tab, el panel a la derecha de la grilla propia: %s" % panel)
	_check(panel.end.x < ui.size.x and ui.hud_limits()["panels_right"] >= panel.end.x, "entra en la pantalla y las luces lo esquivan")
	# Un objeto en la mano no se suelta al piso sobre el panel.
	var uid := 0
	for item in net.replica.own.sorted_uids():
		uid = item
		break
	if uid != 0:
		var stack: InvStack = net.replica.own.get_stack(uid)
		var hold := {"def": net.catalog.find(stack.def_id), "rot": 0, "src": InvProtocol.OWN, "uid": uid, "grab": Vector2i.ZERO}
		var target := ui._drop_target(hold, panel.get_center(), "all", true)
		_check(target["kind"] == "invalid", "sobre el panel no se suelta nada: %s" % [target])
	var crate := net.container(1)
	await _stand(crate.global_position + Vector3(-1.2, 0, 0), 0.0)
	var r := await _req(Op.OPEN, [1])
	await _frames(3)
	_check(r[0] and net.replica.box_id == 1 and ui.is_open, "abre la caja compartida")
	_check(not hud.integrity_panel_rect().has_area() and ui._grid_rect(1).position.x > own.end.x,
			"con la caja abierta, la caja tiene el lugar y el panel no se ve")
	ui.close()
	await _ticks(5)
	_check(net.replica.box_id == 0 and not hud.integrity_panel_rect().has_area(), "cerrado todo, no hay panel")
	ui.open()
	await _frames(2)
	_check(hud.integrity_panel_rect().has_area(), "sin caja, el panel vuelve")
	ui.close()


# --- 5. El botiquín cura la salud y no las piernas; la cápsula mata igual -----------

func _consumables(harm: Array) -> void:
	for def_id in [&"botiquin", &"capsula_letal"]:
		for uid in net.replica.world.keys():
			if net.replica.world[uid]["stack"].def_id == def_id:
				await _stand(net.replica.world[uid]["pos"] + Vector3(-1, 0, 0), 0.0)
				var got := await _req(Op.PICKUP, [uid], [uid])
				_check(got[0], "recoger %s: %s" % [def_id, got[1]])
				break
	var kit := 0
	var pill := 0
	for uid in net.replica.own.sorted_uids():
		var def_id: StringName = net.replica.own.stacks[uid].def_id
		kit = uid if def_id == &"botiquin" else kit
		pill = uid if def_id == &"capsula_letal" else pill
	# Otra vez lastimado, como después de la tabla amarilla.
	actor.state.health = harm[0]
	for i in LEGS.size():
		actor.state.integrity[LEGS[i]] = harm[1][i]
	await _ticks(2)
	_check(hud.injury_warning(), "lastimado: la luz prendida")
	var before := actor.state.health
	_check(kit != 0 and ui.use_item(kit), "usa un botiquín")
	await _ticks(4)
	_check(actor.state.health == mini(before + 50 * H, 100 * H) and _legs() == harm[1] and hud.injury_warning(),
			"el botiquín cura la salud (%.1f) y las piernas siguen igual (%s): la luz sigue prendida" % [_health(), _legs()])
	var deaths := actor.state.deaths
	var collapses := actor.collapses_started
	var shown := hud.deaths_shown
	_check(pill != 0 and ui.use_item(pill), "usa la cápsula letal")
	await _ticks(4)
	await _frames(3)
	_check(actor.state.deaths == (deaths + 1) & 0xFF and actor.state.health == 100 * H
			and actor.state.integrity.count(FULL) == ActorState.PARTS and not hud.injury_warning(),
			"la cápsula: muerte de prueba, salud y cuerpo enteros, luz apagada")
	_check(actor.collapses_started == collapses + 1 and hud.deaths_shown == shown + 1, "el mismo desplome y el mismo aviso, una vez")
	await _real_wait(2.0)


# --- 5b. El botiquín sobre una parte del panel; las vendas (2026-11-06) ---------------

## El centro de una parte del panel en la pantalla.
func _part_center(part: int) -> Vector2:
	return LabHud._part_rect(hud.integrity_panel_rect(), part).get_center()


## Un clic izquierdo de la interfaz en ese punto, como el mouse.
func _click(at: Vector2) -> void:
	ui._mouse = at
	ui._left_press()


func _right_click(at: Vector2) -> void:
	ui._mouse = at
	ui._right_press()


func _quantity(def_id: StringName) -> int:
	return net.replica.own.quantity_of(def_id)


func _heal_parts() -> void:
	var bandages_uid := 0
	for uid in net.replica.world.keys():
		if net.replica.world[uid]["stack"].def_id == &"vendas":
			await _stand(net.replica.world[uid]["pos"] + Vector3(-1, 0, 0), 0.0)
			var got := await _req(Op.PICKUP, [uid], [uid])
			_check(got[0], "recoger las vendas: %s" % got[1])
			break
	var kit := 0
	for uid in net.replica.own.sorted_uids():
		var def_id: StringName = net.replica.own.stacks[uid].def_id
		kit = uid if def_id == &"botiquin" else kit
		bandages_uid = uid if def_id == &"vendas" else bandages_uid
	_check(kit != 0 and _quantity(&"botiquin") == 2 and bandages_uid != 0 and _quantity(&"vendas") == 1,
			"dos botiquines y una venda en el inventario")
	# Lo que curan las vendas de una parte se pone acá, solo en memoria y sin
	# tocar su archivo: primero 0 (no curan partes) y después 25. Así la prueba
	# no depende de lo que tengan puesto.
	var bandage_use := net.catalog.find(&"vendas").ability_of(InvAbility.Kind.USE) as InvConsumable
	var bandage_repair := bandage_use.part_repair
	bandage_use.part_repair = 0.0
	# Las dos piernas lastimadas y la salud completa: el botiquín igual cura partes.
	_heal()
	actor.state.integrity[ActorState.Part.LEG_LEFT] = 6050
	actor.state.integrity[ActorState.Part.LEG_RIGHT] = 6050
	await _ticks(2)
	ui.open()
	await _frames(3)
	ui._layout()
	var panel := hud.integrity_panel_rect()
	var world_before := net.replica.world.size()
	_check(panel.has_area() and hud.injury_warning(), "el panel a la vista y la luz prendida")
	# Agarrar el botiquín con un clic, como siempre.
	_click(ui._item_rect(InvProtocol.OWN, kit).get_center())
	_check(ui.held_def() != null and ui.held_def().id == &"botiquin", "un clic agarra el botiquín")
	ui._mouse = _part_center(ActorState.Part.LEG_LEFT)
	_check(hud.hovered_part() == [ActorState.Part.LEG_LEFT, true], "sobre la pierna izquierda: se marca y sirve")
	ui._mouse = _part_center(ActorState.Part.TORSO)
	_check(hud.hovered_part() == [ActorState.Part.TORSO, false], "sobre el torso, sano: se marca que no sirve")
	# Donde no se puede: sigue en la mano, sin pedido, sin gastar ni tirar nada.
	var layout := LabHud._figure_layout(panel)
	var between_legs: Vector2 = layout[0] + Vector2(32.0, 75.0) * layout[1]
	var title := panel.position + Vector2(60, 30)
	for spot: Array in [[_part_center(ActorState.Part.TORSO), "entera", "sobre una parte sana"],
			[between_legs, "apuntá", "entre las dos piernas"], [title, "apuntá", "sobre el título del panel"]]:
		_click(spot[0])
		_check(ui.held_def() != null and net.replica.pending.is_empty() and ui.last_message().to_lower().contains(spot[1]),
				"%s: sigue en la mano, sin pedido, y dice \"%s\"" % [spot[2], ui.last_message()])
	_right_click(_part_center(ActorState.Part.LEG_LEFT))
	_check(ui.held_def() != null and net.replica.pending.is_empty() and ui.last_message().contains("clic izquierdo"),
			"clic derecho sobre una pierna: sigue en la mano y dice que es con clic izquierdo")
	_check(net.replica.world.size() == world_before and _quantity(&"botiquin") == 2, "nada fue al piso y no se gastó nada")
	# Sobre la pierna izquierda: sale un uso en el input, no un pedido, y no
	# espera al host (desde el 2026-11-06 a la noche): se ve en el tick siguiente.
	var peer := multiplayer.get_unique_id()
	var epoch := actor.state.epoch
	var accepted := net.authority.accepted
	_click(_part_center(ActorState.Part.LEG_LEFT))
	_check(ui.held_def() == null and net.replica.pending.is_empty() and net.replica.uses_waiting() == 1
			and net.replica.shown_own().quantity_of(&"botiquin") == 1,
			"sobre la pierna izquierda: la mano queda vacía, sale un uso (no un pedido) y ya se ve un botiquín menos")
	_check(ui.last_message().contains("pierna izquierda"), "dice qué parte curó: %s" % ui.last_message())
	# Con el uso sin confirmar se puede volver a agarrar enseguida; llevarlo a
	# otro lugar de la grilla espera al host.
	_click(ui._item_rect(InvProtocol.OWN, kit).get_center())
	_check(ui.held_def() != null and ui.held_def().id == &"botiquin", "se puede volver a agarrar enseguida, con el uso sin confirmar")
	_click(_free_spot_for_held())
	_check(ui.held_def() != null and ui.last_message().contains("todavía espera al host") and net.replica.pending.is_empty(),
			"llevarlo a otro lugar de la grilla, todavía no: sigue en la mano (%s)" % ui.last_message())
	ui._cancel_mode("")
	await _ticks(2)
	_check(net.replica.uses_waiting() == 0 and net.authority.accepted == accepted + 1, "el host lo hizo")
	_check(_legs() == [FULL, 6050] and _others_full() and actor.state.health == 100 * H,
			"la pierna izquierda al 100 %%; la derecha, la salud y lo demás, igual: piernas %s, salud %.1f" % [_legs(), _health()])
	_check(_quantity(&"botiquin") == 1, "gastó una sola unidad (queda %d)" % _quantity(&"botiquin"))
	_check(actor.state.epoch == epoch, "no es un evento del host: la época no sube (%d → %d)" % [epoch, actor.state.epoch])
	_check(hud.injury_warning() and hud.integrity_texts()[ActorState.Part.LEG_LEFT] == "100 %"
			and hud.integrity_texts()[ActorState.Part.LEG_RIGHT] == "60 %", "la luz sigue prendida: queda la pierna derecha")
	# El mismo uso que vuelve a llegar en otro input no se hace de nuevo.
	var again := ActorInput.make(lab._clock.tick, Vector2.ZERO, 0.0, 0, actor.state.jump_presses_seen,
			actor.state.ability_presses_seen, actor.state.power_presses_seen)
	again.use_presses = actor.state.use_presses_seen
	again.uses = [[kit, 0, ActorState.Part.LEG_RIGHT]]
	net.use_before_step(actor, again)
	await _ticks(2)
	_check(_legs() == [FULL, 6050] and _quantity(&"botiquin") == 1 and net.authority.accepted == accepted + 1,
			"el mismo uso, otra vez en un input: no cura ni gasta de nuevo")
	# Lo que el host rechaza (como un cliente que se equivoca): no cura ni gasta.
	var refused := []
	var on_refused := func(reason: String) -> void: refused.append(reason)
	net.replica.use_refused.connect(on_refused)
	for case: Array in [[kit, ActorState.Part.LEG_LEFT, "esa parte ya está entera"], [kit, 9, "esa parte del cuerpo no existe"],
			[kit, -3, "esa parte del cuerpo no existe"], [bandages_uid, ActorState.Part.LEG_RIGHT, "eso no cura partes del cuerpo"],
			[999999, ActorState.Part.LEG_RIGHT, "ese objeto ya no está en tu inventario"]]:
		var before := refused.size()
		net.authority.use_from_input(peer, actor.state, case[0], actor.state.use_presses_seen, case[1])
		net.authority.flush({})
		await _ticks(1)
		var said: String = refused.back() if refused.size() > before else "nada"
		_check(said == case[2], "el host dice que no: %s" % said)
	net.replica.use_refused.disconnect(on_refused)
	_check(_legs() == [FULL, 6050] and _quantity(&"botiquin") == 1 and _quantity(&"vendas") == 1,
			"después de los rechazos: nada curado ni gastado")
	# Las vendas con 0 sobre la pierna dañada: no curan partes, siguen en la mano.
	_click(ui._item_rect(InvProtocol.OWN, bandages_uid).get_center())
	_click(_part_center(ActorState.Part.LEG_RIGHT))
	_check(ui.held_def() != null and ui.held_def().id == &"vendas" and ui.last_message().contains("no cura partes")
			and net.replica.uses_waiting() == 0, "las vendas con 0 sobre la pierna: siguen en la mano y dice que no curan partes")
	ui._cancel_mode("")
	# Con 25, curan un poco: la pierna derecha, de 60,5 % a 85,5 %.
	bandage_use.part_repair = 25.0
	_click(ui._item_rect(InvProtocol.OWN, bandages_uid).get_center())
	_click(_part_center(ActorState.Part.LEG_RIGHT))
	await _ticks(2)
	_check(_legs() == [FULL, 8550] and actor.state.health == 100 * H and _quantity(&"vendas") == 0,
			"las vendas con 25: la pierna derecha queda en %.2f %%, la salud igual y se gastaron" % (_legs()[1] / 100.0))
	_check(not hud.injury_warning() and hud.integrity_texts()[ActorState.Part.LEG_RIGHT] == "85 %",
			"el panel dice 85 %% y la luz naranja se apaga: todo está arriba del 60 %% (%s)" % hud.integrity_texts()[ActorState.Part.LEG_RIGHT])
	# El último botiquín sobre la pierna derecha: la última parte dañada.
	_click(ui._item_rect(InvProtocol.OWN, kit).get_center())
	_click(_part_center(ActorState.Part.LEG_RIGHT))
	await _ticks(6)
	_check(actor.state.integrity.count(FULL) == ActorState.PARTS and not hud.injury_warning(),
			"la última parte: todo al 100 %% y la luz naranja se apaga")
	_check(_quantity(&"botiquin") == 0 and net.replica.own.get_stack(kit) == null, "con la última unidad, el botiquín ya no está")
	ui.close()
	bandage_use.part_repair = bandage_repair
	# Uso normal de las vendas: la mitad que el botiquín (25 contra 50), sin
	# tocar partes. Las de antes se gastaron: el host pone otras.
	InvOps.insert(net.authority.player_inventory(peer).grid, InvStack.make(net.authority.alloc_uid(), &"vendas", 1, {}))
	net.authority._dirty_players[peer] = true
	net.authority.flush({})
	await _ticks(2)
	var more := 0
	for uid in net.replica.own.sorted_uids():
		more = uid if net.replica.own.stacks[uid].def_id == &"vendas" else more
	actor.state.health = 40 * H
	actor.state.integrity[ActorState.Part.LEG_LEFT] = 5000
	await _ticks(2)
	_check(more != 0 and ui.use_item(more), "usa las vendas, normal")
	await _ticks(4)
	_check(actor.state.health == 65 * H and actor.state.integrity[ActorState.Part.LEG_LEFT] == 5000,
			"las vendas curan 25 de salud (40 → %.1f) y no la pierna" % _health())
	_heal()
	await _ticks(2)


## Dónde soltar lo que se tiene en la mano para que vaya a la esquina de abajo
## a la derecha de la grilla propia (libre en esta prueba).
func _free_spot_for_held() -> Vector2:
	var grid := net.replica.shown_own()
	var def: InvItemDef = ui._hold["def"]
	var cell: Vector2i = Vector2i(grid.columns, grid.rows) - def.footprint(ui._hold["rot"]) + ui._hold["grab"]
	return ui._grid_rect(InvProtocol.OWN).position + (Vector2(cell) + Vector2(0.5, 0.5)) * ui._cs


# --- 6. Agarrarse de un borde antes de tocar el piso ---------------------------------

func _ledge_grab_first() -> void:
	# Cae pegado a la cara -X de la terraza 2 (filo a 4 m), mirándola.
	var spot := _on_tower(Vector3(-5.5 - 0.45, 7.5, -0.9))
	var landings_before: Array = actor.last_landing.duplicate()
	_hold_in_air(spot, -PI * 0.5)
	var hung := false
	for i in 120:
		await get_tree().physics_frame
		if actor.state.mode == ActorState.Mode.HANGING:
			hung = true
			break
	_check(hung, "cayendo de 3,5 m sobre el filo, se agarra")
	_check(actor.state.health == 100 * H and actor.last_landing == landings_before, "agarrarse no es aterrizar: sin daño")
	Input.action_press("crouch")
	var landed := await _until_landed()
	Input.action_release("crouch")
	var drop: float = actor.last_landing[0]
	_check(landed and drop < tuning.fall_safe_speed and actor.state.health == 100 * H,
			"soltándose con Ctrl cae del colgado (2 m) a %.2f m/s, sin daño" % drop)
	# El mismo lugar, mirando para afuera: no se agarra y cae los 7,5 m.
	_hold_in_air(spot, PI * 0.5)
	landed = await _until_landed()
	var straight: float = actor.last_landing[0]
	_check(landed and straight > tuning.fall_safe_speed and actor.state.health < 100 * H,
			"sin agarrarse, de la misma altura cae a %.2f m/s y lastima (salud %.1f)" % [straight, _health()])
	_heal()
	await _ticks(2)
	await _real_wait(2.0)


# --- 7. Sobre una plataforma que se mueve ---------------------------------------------

func _moving_platform() -> void:
	var lift := ScriptedPlatform.new()
	lift.name = "PlataformaDePrueba"
	lift.base_id = LIFT_ID
	lift.travel = Vector3(0, 6, 0)
	lift.period = 4.0
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.4, 4)
	shape.shape = box
	lift.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	lift.add_child(mesh)
	lift.position = LIFT_AT + Vector3(0, 0.2, 0)
	lab.get_node("Level").add_child(lift)
	await _ticks(3)
	for rising in [true, false]:
		# Espera a que empiece a subir desde abajo (o a bajar desde arriba): así
		# cae sobre ella mientras va rápido para ese lado.
		var bottom := LIFT_AT.y + 0.2
		for i in 600:
			var vy: float = lift.base_velocity().y
			var y: float = lift.base_origin().y
			if (vy > 0.5 and y < bottom + 1.0) if rising else (vy < -0.5 and y > bottom + 5.0):
				break
			await get_tree().physics_frame
		var top: float = lift.base_origin().y + 0.2
		_hold_in_air(Vector3(LIFT_AT.x, top + 2.0, LIFT_AT.z), 0.0)
		var before_vy := 0.0
		var lift_vy := 0.0
		var landed := false
		for i in 200:
			before_vy = actor.state.velocity.y
			await get_tree().physics_frame
			if actor.state.on_floor:
				lift_vy = lift.velocity_at_tick(lab._clock.tick).y
				landed = true
				break
		# El motor cuenta la velocidad de antes del movimiento: la del tick
		# anterior menos la gravedad de este.
		var own_speed := -(before_vy - tuning.gravity * SimClock.TICK_DT)
		var impact: float = actor.last_landing[0] if landed else -1.0
		_check(landed and actor.state.base_id == LIFT_ID, "cae sobre la plataforma que %s" % ("sube" if rising else "baja"))
		_check(absf(impact - (own_speed + lift_vy)) < 0.02,
				"la velocidad contra la plataforma (%.3f) es la propia (%.3f) %s la de la plataforma (%.3f)" % [impact, own_speed,
				"más" if rising else "menos", absf(lift_vy)])
		_check((impact > own_speed) == rising, "%s, el golpe es %s" % ["subiendo" if rising else "bajando", "más fuerte" if rising else "más suave"])
		_heal()
		await _ticks(2)
	await _stand(OPEN_FLOOR, 0.0)
	lift.queue_free()
	await _ticks(3)
	await _real_wait(2.0)


# --- 8. Repetir los ticks de un aterrizaje -------------------------------------------

func _replay_does_not_repeat() -> void:
	for height in [7.0, 12.0]:
		await _stand(OPEN_FLOOR, 0.0)
		_heal()
		await _ticks(2)
		await _real_wait(2.0)
		lab._set_paused(true)
		await get_tree().process_frame
		_hold_in_air(OPEN_FLOOR + Vector3(0, height, 0), 0.0)
		# Hasta medio metro del piso, tick por tick: ahí se guarda el estado. Cada
		# vuelta pide un tick y espera al dibujo del cuadro, que va después de la
		# física: así corre exactamente uno.
		var saved := PackedByteArray()
		for i in 300:
			if BaseRegistry.world_position(actor.state).y < 0.5:
				saved = actor.state.to_bytes()
				break
			lab._clock.step()
			await get_tree().process_frame
		_check(saved.size() == ActorState.BYTE_SIZE and actor.state.mode == ActorState.Mode.AIR,
				"desde %.0f m: llega cayendo a medio metro del piso" % height)
		if saved.is_empty():
			lab._set_paused(false)
			continue
		var deaths := actor.state.deaths
		var collapses := actor.collapses_started
		var shown := hud.deaths_shown
		var first := await _step_until_landed()
		await _frames(3)
		var after_first := actor.state.to_bytes()
		var health_first := actor.state.health
		var legs_first := _legs()
		var deaths_first := actor.state.deaths
		# Como una corrección: vuelve al estado guardado y repite los mismos ticks.
		actor.state = ActorState.from_bytes(saved)
		actor.apply_state(actor.state)
		var second := await _step_until_landed()
		await _frames(3)
		_check(first > 0 and second == first, "desde %.0f m: el aterrizaje repetido cae en el mismo tick (%d y %d)" % [height, first, second])
		_check(actor.state.to_bytes() == after_first, "desde %.0f m: repetir da el mismo estado, byte a byte" % height)
		_check(actor.state.health == health_first and _legs() == legs_first and actor.state.deaths == deaths_first,
				"desde %.0f m: no cobra dos veces (salud %.1f, piernas %s, muertes %d)" % [height, _health(), _legs(), actor.state.deaths])
		if height > 10.0:
			_check(deaths_first == (deaths + 1) & 0xFF, "desde 12 m: una muerte")
			_check(actor.collapses_started == collapses + 1 and hud.deaths_shown == shown + 1,
					"desde 12 m: un solo desplome y un solo aviso, aunque se repitió")
		else:
			_check(deaths_first == deaths and health_first < 100 * H, "desde 7 m: lastima sin matar")
			_check(actor.collapses_started == collapses, "desde 7 m: sin desplome")
		lab._set_paused(false)
		await _ticks(3)


## En pausa, tick por tick hasta quedar apoyado. Devuelve cuántos ticks tardó.
func _step_until_landed() -> int:
	for i in 300:
		lab._clock.step()
		await get_tree().process_frame
		if actor.state.on_floor:
			return i + 1
	return -1


## Salud y cuerpo enteros, sin pasar por una muerte (entre un caso y otro).
func _heal() -> void:
	actor.state.health = tuning.health_max * H
	actor.state.integrity.fill(FULL)
