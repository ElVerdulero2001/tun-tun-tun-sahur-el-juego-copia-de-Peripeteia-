extends Node

## Prueba de la salud, la estamina y los estados (2026-11-02), en el
## laboratorio de verdad y en un solo proceso: arranca net_lab.tscn jugando
## solo, aprieta las teclas como el jugador (los contadores del 1 y el 2 del
## teclado numérico, el Mapa de entrada para caminar), usa los consumibles por
## el camino de la interfaz (InvReplica → InvNet → InvAuthority) y mira lo que
## muestra el HUD. Un segundo jugador se simula en el host, como en la prueba
## del inventario: su pedido de cámara lenta se prende y se apaga en su estado,
## que es lo que el host ve de un jugador de verdad.
##
## --headless --fixed-fps 60 --scene res://scenes/net_lab/estados_test.tscn

const Op := InvProtocol.Op
## Recoger y abrir llevan la dirección de la mano (desde el 2026-11-11 a la noche).
const Mano := preload("res://scenes/net_lab/inventario/pruebas/inv_mano_de_prueba.gd")
const UNIT := ActorPowers.STAMINA_UNIT
const H := ActorState.HEALTH_UNIT
const ZONE := Vector3(37, 0, 13)

var lab: Node3D
var net: InvNet
var hud: LabHud
var ui: InvUI
var tuning: ActorTuning
var actor: ActorBody
var other: ActorBody
var _answers := {}
var _checks := 0
var _failures := 0


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[estados_test] TIEMPO AGOTADO")
		get_tree().quit(2))
	lab = load("res://scenes/net_lab/net_lab.tscn").instantiate()
	add_child(lab)
	net = lab.get_node("Inventario")
	hud = lab.get_node("Hud/Instrumentos")
	ui = lab.get_node("Hud/InventarioUI")
	tuning = lab.tuning
	net.replica.answered.connect(func(seq: int, ok: bool, reason: String) -> void: _answers[seq] = [ok, reason])
	await get_tree().process_frame
	lab._start(0)
	for i in 120:
		await get_tree().physics_frame
		if net.replica.own != null and is_instance_valid(lab._local_actor):
			break
	actor = lab._local_actor
	await _start_full()
	await _moving_costs_nothing()
	await _costs_add_up()
	await _world_slow_two_players()
	await _exhaustion()
	await _consumables()
	await _death()
	await _damage_over_time()
	await _without_waiting()
	await _death_beats_keys()
	await _uses_in_order()
	await _cut_and_leave()
	print("[estados_test] %d comprobaciones, %d fallas" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Ayudas --------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[estados_test] FALLA: %s" % what)


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _stamina(state: ActorState = null) -> float:
	return (state if state != null else actor.state).stamina / float(UNIT)


func _health() -> float:
	return actor.state.health / float(H)


func _req(op: int, args: Array, uids: Array = []) -> Array:
	args = Mano.aimed(net, lab._local_actor, op, args)
	var seq := net.replica.request(op, args, uids)
	if seq == 0:
		return [false, "no salió"]
	for i in 30:
		if _answers.has(seq):
			return _answers[seq]
		await get_tree().physics_frame
	return [false, "sin respuesta"]


func _teleport(position: Vector3) -> void:
	var state := actor.state
	state.position = position
	state.velocity = Vector3.ZERO
	state.mode = ActorState.Mode.GROUND
	state.on_floor = true
	state.base_id = 0
	state.quantize()
	actor.apply_state(state)
	actor.teleported()
	await _ticks(3)


func _own(def_id: StringName) -> int:
	for uid in net.replica.own.sorted_uids():
		if net.replica.own.stacks[uid].def_id == def_id:
			return uid
	return 0


func _quantity(uid: int) -> int:
	var stack := net.replica.own.get_stack(uid)
	return stack.quantity if stack != null else 0


## Gasto medido en `count` ticks, en estamina visible.
func _spent_over(count: int) -> float:
	await get_tree().physics_frame
	var before := actor.state.stamina
	var from: int = lab._clock.tick
	await _ticks(count)
	_check(lab._clock.tick - from == count, "se midieron %d ticks (fueron %d)" % [count, lab._clock.tick - from])
	return (before - actor.state.stamina) / float(UNIT)


func _press_power() -> void:
	lab.power_presses = (lab.power_presses + 1) & 0xFF
	await _ticks(2)


func _press_slow() -> void:
	lab.ability_presses = (lab.ability_presses + 1) & 0xFF
	await _ticks(2)


func _lit() -> Array:
	return hud.lit_powers().map(func(power: Dictionary) -> String: return power["name"])


func _scale_now() -> float:
	return SimClock.world_scale(lab._clock.tick)


## Espera hasta que la escala del mundo sea esa, como mucho `most` ticks.
func _wait_scale(scale: float, most := 40) -> bool:
	for i in most:
		if is_equal_approx(_scale_now(), scale):
			return true
		await get_tree().physics_frame
	return is_equal_approx(_scale_now(), scale)


# --- 1. Todo completo al empezar -------------------------------------------------

func _start_full() -> void:
	await _frames(20)
	_check(actor.state.health == tuning.health_max * H and actor.state.health == 100 * H, "salud completa: %.1f" % _health())
	_check(actor.state.stamina == tuning.stamina_max * UNIT and is_equal_approx(_stamina(), 200.0), "estamina completa: %.3f" % _stamina())
	var needles := hud.needles()
	_check(is_equal_approx(needles[0], 10.0) and is_equal_approx(needles[1], 200.0), "las agujas marcan 10 y 200: %s" % [needles])
	_check(hud.lit_powers().is_empty() and actor.state.powers == 0, "sin luces de estados")
	_check(SimClock.world_slow_spans().is_empty(), "sin cámara lenta")


# --- 2. Correr y saltar no gastan; esperar no devuelve -----------------------------

func _moving_costs_nothing() -> void:
	var from := BaseRegistry.world_position(actor.state)
	var jumps_before := actor.state.jump_presses_seen
	Input.action_press("move_forward")
	Input.action_press("run")
	await _ticks(20)
	lab.jump_presses = (lab.jump_presses + 1) & 0xFF
	await _ticks(70)
	Input.action_release("move_forward")
	Input.action_release("run")
	await _ticks(40)
	var moved := BaseRegistry.world_position(actor.state).distance_to(from)
	_check(moved > 3.0 and actor.state.jump_presses_seen != jumps_before, "corrió %.1f m y saltó" % moved)
	_check(actor.state.stamina == 200 * UNIT, "correr y saltar no gastan estamina: %.3f" % _stamina())
	actor.state.stamina = 100 * UNIT
	await _ticks(120)
	_check(actor.state.stamina == 100 * UNIT, "esperando con la reserva a medias no vuelve sola: %.3f" % _stamina())
	actor.state.stamina = 200 * UNIT


# --- 3. Los costos se suman ----------------------------------------------------------

func _costs_add_up() -> void:
	await _press_power()
	_check(actor.state.boosted and _lit() == ["Súper"], "el 2 prende el súper y su luz: %s" % [_lit()])
	var spent := await _spent_over(60)
	_check(is_equal_approx(spent, tuning.boost_stamina_cost), "el súper gasta %.3f por segundo (gastó %.3f en 60 ticks)" % [
			tuning.boost_stamina_cost, spent])
	await _press_slow()
	_check(actor.state.powers == ActorPowers.ALL and _lit() == ["Súper", "Cámara lenta"], "el 1 prende el pedido de cámara lenta: dos luces %s" % [_lit()])
	_check(await _wait_scale(NetSync.steps_to_scale(NetSync.scale_to_steps(tuning.slow_scale))), "el mundo va lento: %.3f" % _scale_now())
	spent = await _spent_over(60)
	var both := tuning.boost_stamina_cost + tuning.slow_stamina_cost
	_check(is_equal_approx(spent, both), "los dos juntos gastan la suma, %.3f por segundo (gastó %.3f)" % [both, spent])
	await _press_power()
	spent = await _spent_over(60)
	_check(not actor.state.boosted and is_equal_approx(spent, tuning.slow_stamina_cost),
			"apagar el súper saca solo su costo: %.3f (gastó %.3f)" % [tuning.slow_stamina_cost, spent])
	_check(_lit() == ["Cámara lenta"], "queda solo la luz de la cámara lenta: %s" % [_lit()])


# --- 4. Cámara lenta con dos jugadores ------------------------------------------------

func _world_slow_two_players() -> void:
	var slow := NetSync.steps_to_scale(NetSync.scale_to_steps(tuning.slow_scale))
	other = load("res://scenes/actor/actor.tscn").instantiate()
	other.name = "Actor2"
	other.owner_peer_id = 2
	other.state.position = ZONE + Vector3(-5, 0, 5)
	other.state.mode = ActorState.Mode.GROUND
	other.state.on_floor = true
	other.position = other.state.position
	lab.get_node("Actors").add_child(other)
	await _ticks(3)
	# B también la pide: la misma escala, un solo tramo, y cada uno paga lo suyo.
	other.state.powers |= ActorPowers.SLOW
	await _ticks(10)
	var spans := SimClock.world_slow_spans()
	_check(spans.size() == 1 and spans[0][1] == SimClock.OPEN_END and is_equal_approx(_scale_now(), slow),
			"A y B la piden: un solo tramo abierto, al %.0f %% (%s)" % [_scale_now() * 100.0, spans])
	var a_before := actor.state.stamina
	var b_before := other.state.stamina
	await _ticks(60)
	var per_tick := ActorPowers.cost_per_tick(tuning.slow_stamina_cost)
	_check(a_before - actor.state.stamina == 60 * per_tick and b_before - other.state.stamina == 60 * per_tick,
			"cada uno paga su pedido, una vez por tick: A %.3f y B %.3f en 60 ticks" % [
			(a_before - actor.state.stamina) / float(UNIT), (b_before - other.state.stamina) / float(UNIT)])
	# A la suelta: sigue lenta por B; A deja de pagar, B sigue.
	await _press_slow()
	await _ticks(20)
	a_before = actor.state.stamina
	b_before = other.state.stamina
	await _ticks(30)
	_check(is_equal_approx(_scale_now(), slow) and SimClock.world_slow_spans().size() == 1,
			"A la suelta y sigue lenta, porque B la pide (%.2f)" % _scale_now())
	_check(actor.state.stamina == a_before and b_before - other.state.stamina == 30 * per_tick,
			"A dejó de pagar y B sigue pagando")
	_check(hud.lit_powers().is_empty(), "A no tiene luz: la cámara lenta de B no prende la suya")
	# B la suelta: termina.
	other.state.powers &= ~ActorPowers.SLOW
	_check(await _wait_scale(1.0), "B la suelta y nadie la pide: el mundo vuelve a 1 (%.2f)" % _scale_now())
	# Al revés, y con un fin ya programado: A la pide, la suelta y B la pide antes
	# de que termine. El fin viejo no corta la de B, ni un tick.
	await _press_slow()
	_check(await _wait_scale(slow), "A la vuelve a pedir")
	lab.test_schedule_ticks = 12
	await _press_slow()
	var end: int = SimClock.world_slow_spans()[-1][1]
	lab.test_schedule_ticks = 3
	other.state.powers |= ActorPowers.SLOW
	var normal := 0
	for i in 30:
		await get_tree().physics_frame
		if _scale_now() >= 1.0:
			normal += 1
	_check(end != SimClock.OPEN_END and normal == 0 and SimClock.world_slow_spans()[-1][1] == SimClock.OPEN_END,
			"B la pide antes del fin que había programado A (tick %d): el tramo sigue, sin ticks normales (%d)" % [end, normal])
	lab.test_schedule_ticks = 0
	other.state.powers &= ~ActorPowers.SLOW
	_check(await _wait_scale(1.0), "y termina cuando la suelta B")
	var overlap := false
	var spans_now := SimClock.world_slow_spans()
	for i in range(1, spans_now.size()):
		overlap = overlap or spans_now[i][0] < spans_now[i - 1][1]
	_check(not overlap, "ningún tramo se superpone con otro: %s" % [spans_now])
	var expected: float = lab._clock.tick - lab.slow_ticks_seen * (1.0 - slow)
	_check(absf(SimClock.world_ticks(lab._clock.tick + 1) - 1.0 - expected) < 0.01,
			"el tiempo del mundo descuenta cada tick lento una sola vez: %.3f, %.3f esperado" % [SimClock.world_ticks(lab._clock.tick + 1) - 1.0, expected])


# --- 5. Agotarse ------------------------------------------------------------------------

func _exhaustion() -> void:
	await _press_power()
	await _press_slow()
	_check(actor.state.powers == ActorPowers.ALL, "los dos prendidos")
	var sounds := hud.exhaustion_sounds
	var count := actor.state.exhaustions
	# Lo que gastan tres ticks, sean cuales sean los costos del Tuning.
	actor.state.stamina = ActorPowers.tick_cost(actor.state.powers, tuning) * 3
	await _ticks(10)
	_check(actor.state.stamina == 0 and actor.state.powers == 0, "con la reserva en cero se apagan los dos juntos")
	_check(actor.state.exhaustions == (count + 1) & 0xFF, "un solo agotamiento")
	await _frames(30)
	_check(hud.exhaustion_sounds == sounds + 1, "un solo sonido (%d)" % (hud.exhaustion_sounds - sounds))
	_check(is_zero_approx(hud.needles()[1]) and hud.lit_powers().is_empty(), "la aguja termina en cero y no hay luces: %.3f" % hud.needles()[1])
	await _press_power()
	await _press_slow()
	_check(actor.state.powers == 0 and actor.state.stamina == 0 and hud.exhaustion_sounds == sounds + 1,
			"con la reserva en cero no se prende ninguno, ni suena de nuevo")
	_check(await _wait_scale(1.0), "y la cámara lenta del mundo termina (nadie la pide)")
	# Una corrección que vuelve atrás y adelante el mismo agotamiento no suena dos veces.
	actor.state.exhaustions = count
	await _frames(5)
	actor.state.exhaustions = (count + 1) & 0xFF
	await _frames(5)
	_check(hud.exhaustion_sounds == sounds + 1, "repetir el mismo agotamiento (una corrección) no vuelve a sonar")


# --- 6. Consumibles -------------------------------------------------------------------------

func _consumables() -> void:
	for def_id in [&"bebida_energetica", &"botiquin", &"veneno", &"capsula_letal"]:
		for uid in net.replica.world.keys():
			if net.replica.world[uid]["stack"].def_id == def_id:
				await _teleport(net.replica.world[uid]["pos"] + Vector3(-1, 0, 0))
				var got := await _req(Op.PICKUP, [uid], [uid])
				_check(got[0], "recoger %s: %s" % [def_id, got[1]])
				break
	var drink := _own(&"bebida_energetica")
	var kit := _own(&"botiquin")
	var poison := _own(&"veneno")
	var pill := _own(&"capsula_letal")
	_check(drink != 0 and kit != 0 and poison != 0 and pill != 0, "los cuatro en el inventario")
	# Desde el menú (Usar): la bebida devuelve 100, sin pasar de 200.
	var r := await _req(Op.USE, [drink, net.replica.own.get_stack(drink).ver], [drink])
	_check(r[0] and actor.state.stamina == 100 * UNIT and _quantity(drink) == 3, "la bebida devuelve 100 y gasta una: %.1f, quedan %d" % [_stamina(), _quantity(drink)])
	await _press_power()
	_check(actor.state.boosted, "con reserva, el súper se vuelve a prender a mano")
	await _press_power()
	actor.state.stamina = 150 * UNIT
	r = await _req(Op.USE, [drink, net.replica.own.get_stack(drink).ver], [drink])
	_check(r[0] and actor.state.stamina == 200 * UNIT, "otra: 150 + 100 queda en 200, no pasa (%.1f)" % _stamina())
	r = await _req(Op.USE, [drink, net.replica.own.get_stack(drink).ver], [drink])
	_check(not r[0] and r[1] == "ya tenés la estamina completa" and _quantity(drink) == 2,
			"con la reserva llena no se usa ni se gasta: %s" % r[1])
	r = await _req(Op.USE, [kit, net.replica.own.get_stack(kit).ver], [kit])
	_check(not r[0] and r[1] == "ya tenés la salud completa" and _quantity(kit) == 3, "el botiquín con la salud completa: %s" % r[1])
	# Desde la barra rápida: el veneno se usa con la salud completa.
	r = await _req(Op.HOTBAR_SET, [3, poison])
	r = await _req(Op.HOTBAR_PRESS, [3], [poison])
	_check(r[0] and actor.state.health == 60 * H and _quantity(poison) == 4, "el veneno con la salud completa: 100 → %.1f, quedan %d" % [_health(), _quantity(poison)])
	r = await _req(Op.USE, [kit, net.replica.own.get_stack(kit).ver], [kit])
	_check(r[0] and actor.state.health == 100 * H and _quantity(kit) == 2, "el botiquín: 60 + 50 queda en 100, no pasa (%.1f)" % _health())
	# Lo que dice el menú y la inspección.
	ui.open()
	ui._open_menu(InvProtocol.OWN, kit)
	var use_text := ""
	var use_disabled := false
	for child in ui._menu_box.get_children():
		if child is Button and child.text.begins_with("Usar"):
			use_text = child.text
			use_disabled = child.disabled
	_check(use_disabled and use_text.contains("ya tenés la salud completa"), "el menú apaga Usar y dice por qué: %s" % use_text)
	ui._close_menu()
	ui._show_inspect(InvProtocol.OWN, poison)
	_check(ui._inspect_text.text.contains("quita 40 de salud"), "la inspección dice lo que hace el veneno")
	ui._inspect.hide()
	ui.close()


# --- 7. Muerte de prueba ----------------------------------------------------------------------

func _death() -> void:
	var pill := _own(&"capsula_letal")
	var poison := _own(&"veneno")
	# Sin costos por un rato, así la estamina se puede comparar justo antes y después.
	var costs := [tuning.boost_stamina_cost, tuning.slow_stamina_cost]
	tuning.boost_stamina_cost = 0.0
	tuning.slow_stamina_cost = 0.0
	actor.state.stamina = 120 * UNIT
	await _press_power()
	await _press_slow()
	other.state.powers |= ActorPowers.SLOW
	_check(await _wait_scale(NetSync.steps_to_scale(NetSync.scale_to_steps(tuning.slow_scale))), "A y B piden la cámara lenta")
	var where := BaseRegistry.world_position(actor.state)
	var deaths := actor.state.deaths
	var shown := hud.deaths_shown
	await _req(Op.HOTBAR_SET, [4, pill])
	# El mismo pedido dos veces: mata una vez y gasta una cápsula.
	var seq := net.replica.request(Op.HOTBAR_PRESS, [4], [pill], [4])
	net._send_request(seq, Op.HOTBAR_PRESS, [4])
	await _ticks(4)
	_check(actor.state.deaths == (deaths + 1) & 0xFF and net.authority.deaths >= 1, "una muerte de prueba")
	_check(_quantity(pill) == 1, "el pedido repetido no mata dos veces ni gasta otra cápsula (quedan %d)" % _quantity(pill))
	_check(actor.state.health == tuning.health_max * H and actor.state.powers == 0, "salud al máximo y estados apagados")
	_check(actor.state.stamina == 120 * UNIT, "la estamina se conserva: %.1f" % _stamina())
	_check(BaseRegistry.world_position(actor.state).distance_to(where) < 0.05, "la posición se conserva")
	_check(_quantity(poison) == 4 and _own(&"botiquin") != 0, "el resto del inventario se conserva")
	await _frames(3)
	_check(hud.deaths_shown == shown + 1 and hud.is_showing_death(), "el aviso de muerte se ve")
	await _ticks(10)
	_check(is_equal_approx(_scale_now(), NetSync.steps_to_scale(NetSync.scale_to_steps(tuning.slow_scale))) and other.state.powers & ActorPowers.SLOW,
			"la muerte de A no apaga el pedido de B: sigue lenta")
	await _ticks(60)
	_check(actor.state.powers == 0, "los estados no se vuelven a prender solos")
	# El aviso dura segundos reales (con --fixed-fps los temporizadores no).
	var until := Time.get_ticks_msec() + roundi((hud.death_notice_seconds + 0.2) * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	_check(not hud.is_showing_death() and hud.deaths_shown == shown + 1, "el aviso se va solo y no se repite")
	tuning.boost_stamina_cost = costs[0]
	tuning.slow_stamina_cost = costs[1]


# --- 8. Daño en el tiempo ---------------------------------------------------------------------------

## Salud perdida en `count` ticks, en puntos.
func _health_lost_over(count: int) -> float:
	await get_tree().physics_frame
	var before := actor.state.health
	await _ticks(count)
	return (before - actor.state.health) / float(H)


## Espera hasta que no quede ningún daño en el tiempo, como mucho `most` ticks.
func _wait_effects_end(most := 600) -> bool:
	for i in most:
		if actor.state.effect_duration.count(0) == ActorState.MAX_EFFECTS:
			return true
		await get_tree().physics_frame
	return false


func _damage_over_time() -> void:
	# B todavía pide la cámara lenta (de la prueba de la muerte).
	other.state.powers &= ~ActorPowers.SLOW
	for uid in net.replica.world.keys():
		if net.replica.world[uid]["stack"].def_id == &"toxina_lenta":
			await _teleport(net.replica.world[uid]["pos"] + Vector3(-1, 0, 0))
			var got := await _req(Op.PICKUP, [uid], [uid])
			_check(got[0], "recoger la toxina lenta: %s" % got[1])
			break
	var toxin := _own(&"toxina_lenta")
	_check(toxin != 0 and _quantity(toxin) == 4, "cuatro toxinas lentas (20 de daño en 4 s cada una)")
	var described: String = net.catalog.find(&"toxina_lenta").abilities[0].describe()
	_check(described.contains("quita 20 de salud de a poco, en 4 s (5 por segundo"), "la inspección dice lo que hace: %s" % described)
	_check(await _wait_scale(1.0), "sin cámara lenta")
	# Una: con la salud completa se usa, y baja parejo, 5 por segundo.
	actor.state.health = 100 * H
	var r := await _req(Op.USE, [toxin, net.replica.own.get_stack(toxin).ver], [toxin])
	_check(r[0] and _quantity(toxin) == 3, "con la salud completa se usa y gasta una: %s" % r[1])
	var lost := await _health_lost_over(60)
	_check(absf(lost - 5.0) < 0.01, "baja 5 por segundo: %.3f en 60 ticks" % lost)
	var drops := []
	for i in 30:
		var before := actor.state.health
		await get_tree().physics_frame
		drops.append(before - actor.state.health)
	_check(drops.min() >= 80 and drops.max() <= 87, "parejo, sin saltos: de %.3f a %.3f por tick" % [drops.min() / float(H), drops.max() / float(H)])
	_check(await _wait_effects_end() and actor.state.health == 80 * H, "termina y quitó justo 20: %.3f" % _health())
	var stays := actor.state.health
	await _ticks(30)
	_check(actor.state.health == stays, "terminado, no baja más")
	# Dos a la vez se acumulan: el doble de rápido mientras duran los dos.
	actor.state.health = 100 * H
	await _req(Op.USE, [toxin, net.replica.own.get_stack(toxin).ver], [toxin])
	await _req(Op.USE, [toxin, net.replica.own.get_stack(toxin).ver], [toxin])
	lost = await _health_lost_over(60)
	_check(absf(lost - 10.0) < 0.05 and actor.state.effect_duration.count(0) == ActorState.MAX_EFFECTS - 2,
			"dos se acumulan, cada uno con su ritmo: %.3f en 60 ticks" % lost)
	_check(await _wait_effects_end() and actor.state.health == 60 * H, "y quitan 40 entre los dos: %.3f" % _health())
	# Con cuatro encima, otro no se usa ni se gasta.
	for i in ActorState.MAX_EFFECTS:
		ActorVitals.of(actor.state, tuning).apply(0, 0, 1, 100.0)
	r = await _req(Op.USE, [toxin, net.replica.own.get_stack(toxin).ver], [toxin])
	_check(not r[0] and r[1] == "ya tenés 4 daños en el tiempo encima" and _quantity(toxin) == 1, "con cuatro encima: %s" % r[1])
	actor.state.effect_total.fill(0)
	actor.state.effect_duration.fill(0)
	actor.state.effect_elapsed.fill(0)
	# Con la cámara lenta va más despacio: al 30 %, 1,5 por segundo real.
	var slow := NetSync.steps_to_scale(NetSync.scale_to_steps(tuning.slow_scale))
	actor.state.stamina = 200 * UNIT
	await _press_slow()
	_check(await _wait_scale(slow), "con cámara lenta")
	actor.state.health = 100 * H
	await _req(Op.USE, [toxin, net.replica.own.get_stack(toxin).ver], [toxin])
	lost = await _health_lost_over(60)
	_check(absf(lost - 5.0 * slow) < 0.01, "con la cámara lenta baja %.2f por segundo real: %.3f en 60 ticks" % [5.0 * slow, lost])
	await _press_slow()
	_check(await _wait_scale(1.0) and await _wait_effects_end() and actor.state.health == 80 * H,
			"y al final quitó justo 20 igual: %.3f" % _health())
	# Matar: se corta en la muerte, con el aviso, y la salud vuelve al máximo.
	actor.state.stamina = 200 * UNIT
	await _press_power()
	actor.state.health = 3 * H
	var deaths := actor.state.deaths
	var shown := hud.deaths_shown
	ActorVitals.of(actor.state, tuning).apply(0, 0, 10, 1.0)
	_check(await _wait_effects_end(120), "se corta")
	_check(actor.state.deaths == (deaths + 1) & 0xFF and actor.state.health == tuning.health_max * H and actor.state.powers == 0,
			"a los 3 de salud, el daño en el tiempo mata: muerte de prueba, salud al máximo y estados apagados")
	await _frames(3)
	_check(hud.deaths_shown == shown + 1, "con el aviso")
	await _ticks(30)
	_check(actor.state.health == tuning.health_max * H, "y no sigue bajando después de morir")


# --- 9. Sin esperar al host (2026-11-04) ------------------------------------------------------------

func _count_shown(def_id: StringName) -> int:
	return net.replica.shown_own().quantity_of(def_id)


## Usar desde la interfaz (el menú y la barra): se ve gastado en el mismo
## cuadro y el efecto llega en el tick siguiente, desde el input, sin pedido.
## Recoger: se ve en la grilla ya, y si el host dice que no, vuelve al piso.
## Jugando solo el host es esta misma máquina, pero el camino es el de la red.
func _without_waiting() -> void:
	actor.state.health = 50 * H
	var kit := _own(&"botiquin")
	var kits := _count_shown(&"botiquin")
	var epoch := actor.state.epoch
	_check(ui.use_item(kit), "usa un botiquín desde la interfaz")
	_check(_count_shown(&"botiquin") == kits - 1 and net.replica.pending.is_empty() and not ui._waiting(kit),
			"en el mismo cuadro se ve gastado, sin pedido ni \"esperando…\"")
	await _ticks(2)
	_check(actor.state.health == 100 * H and actor.state.epoch == epoch, "en el tick siguiente cura, sin subir la época: %.1f" % _health())
	_check(net.replica.own.quantity_of(&"botiquin") == kits - 1 and net.replica._uses.is_empty(), "y el host gastó uno")
	_check(not ui.use_item(kit) and ui.last_message().contains("salud completa") and _count_shown(&"botiquin") == kits - 1,
			"con la salud completa no sale y lo dice: %s" % ui.last_message())
	# Desde la barra: dos venenos en el mismo cuadro van uno por tick.
	var poison := _own(&"veneno")
	var poisons := _count_shown(&"veneno")
	await _req(Op.HOTBAR_SET, [6, poison])
	ui._press_slot(6)
	ui._press_slot(6)
	_check(_count_shown(&"veneno") == poisons - 2 and net.replica.pending.is_empty(), "dos venenos desde la barra: los dos se ven gastados, sin pedido")
	await _ticks(1)
	var after_one := actor.state.health
	await _ticks(2)
	_check(after_one == 60 * H and actor.state.health == 20 * H, "uno por tick: 100 → 60 → 20 (%.1f, %.1f)" % [after_one / float(H), _health()])
	_check(net.replica.own.quantity_of(&"veneno") == poisons - 2, "el host gastó los dos")
	# Uno que el host no puede usar (lo pide sin la interfaz): vuelve y lo dice.
	actor.state.health = 100 * H
	net.queue_use(kit, net.catalog.find(&"botiquin"))
	_check(_count_shown(&"botiquin") == kits - 2, "se ve gastado")
	await _ticks(2)
	_check(_count_shown(&"botiquin") == kits - 1 and ui.last_message().contains("No se usó"), "el host no lo usa: vuelve a verse y lo dice: %s" % ui.last_message())
	# Recoger: una botella del piso, ya en la grilla.
	var bottle := 0
	for uid in net.replica.world.keys():
		if net.replica.world[uid]["stack"].def_id == &"botella":
			bottle = uid
			break
	_check(bottle != 0, "hay una botella en el piso")
	if bottle == 0:
		return
	var bottles := _count_shown(&"botella")
	var quantity: int = net.replica.world[bottle]["stack"].quantity
	var where: Vector3 = net.replica.world[bottle]["pos"]
	# Lejos: el host dice que no y vuelve al piso.
	await _teleport(where + Vector3(-6, 0, 0))
	var seq := ui.pick_up_world(bottle, "", Mano.toward_item(net, lab._local_actor, bottle))
	_check(seq != 0 and _count_shown(&"botella") == bottles + quantity and net.replica.is_taken(bottle) and net.world_view(bottle) == null,
			"lejos: en el mismo cuadro se ve en la grilla y no en el piso")
	await _ticks(3)
	_check(_answers.has(seq) and not _answers[seq][0] and _count_shown(&"botella") == bottles and net.world_view(bottle) != null,
			"el host dice que no y vuelve al piso: %s" % [_answers.get(seq, [])])
	_check(ui.last_message().contains("lejos"), "y lo dice: %s" % ui.last_message())
	# Cerca: queda.
	await _teleport(where + Vector3(-1, 0, 0))
	seq = ui.pick_up_world(bottle, "", Mano.toward_item(net, lab._local_actor, bottle))
	_check(_count_shown(&"botella") == bottles + quantity and net.world_view(bottle) == null and not ui._waiting(_own(&"botella")),
			"cerca: se ve en la grilla ya, sin \"esperando…\"")
	await _ticks(3)
	_check(_answers.has(seq) and _answers[seq][0] and net.replica.own.quantity_of(&"botella") == bottles + quantity
			and net.replica.shown_own() == net.replica.own, "el host la confirma y no queda nada sin confirmar")
	# Soltar: ya se ve en el piso, en el lugar donde la va a dejar el host.
	var kept := _own(&"botella")
	var before := _count_shown(&"botella")
	seq = ui.drop_item(InvProtocol.OWN, kept, net.replica.shown_own().get_stack(kept).ver, 1)
	var ghost := net.world_view(-seq)
	_check(seq != 0 and ghost != null and _count_shown(&"botella") == before - 1 and not ui._waiting(kept),
			"soltar una botella: en el mismo cuadro se ve en el piso y una menos en la grilla, sin \"esperando…\"")
	var at := ghost.global_position if ghost != null else Vector3.INF
	await _ticks(3)
	var landed := 0
	for uid in net.replica.world:
		if net.replica.world[uid]["stack"].def_id == &"botella" and (net.replica.world[uid]["pos"] as Vector3).distance_to(at) < 0.002:
			landed = uid
	_check(_answers.has(seq) and _answers[seq][0] and landed != 0 and net.world_view(-seq) == null and net.world_view(landed) != null,
			"el host la deja en ese mismo lugar")
	_check(net.replica.shown_own() == net.replica.own and net.replica.predicted_drops().is_empty(), "y no queda nada sin confirmar")


# --- 10. Auditoría del 2026-11-04 ---------------------------------------------------------------

## INV-04: si muere en el mismo tick en que aprieta el 1 y el 2, la muerte gana:
## termina con todo apagado. Con la cápsula (antes del motor) y con el daño en
## el tiempo (en el motor). B sigue sosteniendo su cámara lenta.
func _death_beats_keys() -> void:
	var slow := NetSync.steps_to_scale(NetSync.scale_to_steps(tuning.slow_scale))
	var costs := [tuning.boost_stamina_cost, tuning.slow_stamina_cost]
	tuning.boost_stamina_cost = 0.0
	tuning.slow_stamina_cost = 0.0
	actor.state.stamina = 200 * UNIT
	actor.state.health = 100 * H
	other.state.powers |= ActorPowers.SLOW
	for kind in ["cápsula", "daño en el tiempo"]:
		if not actor.state.boosted:
			await _press_power()
		if not actor.state.powers & ActorPowers.SLOW:
			await _press_slow()
		_check(actor.state.powers == ActorPowers.ALL, "%s: A con los dos estados prendidos" % kind)
		var deaths := actor.state.deaths
		# Las dos teclas y la muerte, en el mismo tick.
		lab.power_presses = (lab.power_presses + 1) & 0xFF
		lab.ability_presses = (lab.ability_presses + 1) & 0xFF
		if kind == "cápsula":
			var pill := _own(&"capsula_letal")
			_check(pill != 0 and ui.use_item(pill), "usa la última cápsula letal")
		else:
			actor.state.health = 1
			ActorVitals.of(actor.state, tuning).apply(0, 0, 10, 1.0)
		await _ticks(2)
		_check(actor.state.deaths == (deaths + 1) & 0xFF and actor.state.powers == 0,
				"%s: muere en el tick en que aprieta el 1 y el 2 y termina con todo apagado (estados %d)" % [kind, actor.state.powers])
		await _ticks(10)
		_check(actor.state.powers == 0 and actor.state.deaths == (deaths + 1) & 0xFF, "%s: los siguientes ticks no los prenden" % kind)
		_check(is_equal_approx(_scale_now(), slow) and other.state.powers & ActorPowers.SLOW, "%s: B sigue pidiendo la cámara lenta" % kind)
	await _press_power()
	_check(actor.state.boosted, "una pulsación después de la muerte sí prende el súper")
	await _press_power()
	other.state.powers &= ~ActorPowers.SLOW
	_check(await _wait_scale(1.0) and actor.state.powers == 0, "todo apagado otra vez")
	tuning.boost_stamina_cost = costs[0]
	tuning.slow_stamina_cost = costs[1]


## Un input de B con estos usos (cada uno [objeto, pedido anterior]), el más
## nuevo con el número `last`.
func _b_input(last: int, uses: Array) -> ActorInput:
	var input := ActorInput.make(lab._clock.tick, Vector2.ZERO, 0.0, 0, other.state.jump_presses_seen,
			other.state.ability_presses_seen, other.state.power_presses_seen)
	input.use_presses = last & 0xFF
	input.uses = uses
	return input


## INV-01 e INV-02, en el host, con el inventario de B: el host hace todos los
## usos que trae el input, en orden, y respeta el orden con los pedidos.
func _uses_in_order() -> void:
	var inventory := net.authority.player_inventory(2)
	_check(inventory != null, "B tiene inventario en el host")
	if inventory == null:
		return
	var poison := InvStack.make(net.authority.alloc_uid(), &"veneno", 5, {})
	var kit := InvStack.make(net.authority.alloc_uid(), &"botiquin", 3, {})
	InvOps.insert(inventory.grid, poison)
	InvOps.insert(inventory.grid, kit)
	var count := func(uid: int) -> int:
		var stack := inventory.grid.get_stack(uid)
		return stack.quantity if stack != null else 0
	# INV-01: el host se perdió el tick del veneno y le llega el input que ya
	# trae el botiquín: hace los dos, en orden. Antes hacía solo el botiquín.
	other.state.health = 60 * H
	var seen := other.state.use_presses_seen
	var input := _b_input(seen + 2, [[poison.uid, 0], [kit.uid, 0]])
	net.use_before_step(other, input)
	_check(other.state.health == 70 * H and count.call(poison.uid) == 4 and count.call(kit.uid) == 2
			and other.state.use_presses_seen == (seen + 2) & 0xFF,
			"le llegan dos usos juntos: veneno y después botiquín, 60 → 20 → 70 (%.1f)" % (other.state.health / float(H)))
	net.use_before_step(other, input)
	_check(other.state.health == 70 * H and count.call(poison.uid) == 4 and count.call(kit.uid) == 2,
			"el mismo input otra vez no repite nada")
	net.use_before_step(other, _b_input(seen + 1, [[poison.uid, 0]]))
	_check(other.state.health == 70 * H and other.state.use_presses_seen == (seen + 2) & 0xFF, "uno viejo, que va atrás, tampoco")
	var rejected := net.authority.rejected
	net.use_before_step(other, _b_input(seen + 5, [[kit.uid, 0]]))
	_check(other.state.use_presses_seen == (seen + 5) & 0xFF and net.authority.rejected == rejected + 2
			and other.state.health == 100 * H and count.call(kit.uid) == 1,
			"si faltan dos en el input, se contestan como perdidos y se hace el que vino")
	# INV-02: un uso hecho después de un pedido que el host todavía no recibió espera.
	var seq: int = net._done_seq.get(2, 0) + 1
	other.state.health = 50 * H
	seen = other.state.use_presses_seen
	input = _b_input(seen + 1, [[kit.uid, seq]])
	net.use_before_step(other, input)
	_check(other.state.health == 50 * H and other.state.use_presses_seen == seen, "un uso que va después de un pedido que no llegó espera")
	net._inbox.append([2, seq, Op.HOTBAR_SET, [0, kit.uid], -1])
	await _ticks(2)
	_check(inventory.loadout.hotbar[0] == kit.uid, "llega el pedido y el host lo procesa")
	net.use_before_step(other, input)
	_check(other.state.health == 100 * H and other.state.use_presses_seen == (seen + 1) & 0xFF and count.call(kit.uid) == 0,
			"y recién ahí el uso")
	# Un pedido hecho después de un uso que todavía no llegó espera.
	var next := (other.state.use_presses_seen + 1) & 0xFF
	net._inbox.append([2, seq + 1, Op.HOTBAR_SET, [1, poison.uid], next])
	await _ticks(3)
	_check(inventory.loadout.hotbar[1] == 0 and net.queued_requests() == 1, "un pedido que va después de un uso que no llegó espera")
	net.use_before_step(other, _b_input(next, [[poison.uid, seq]]))
	await _ticks(2)
	_check(other.state.health == 60 * H and inventory.loadout.hotbar[1] == poison.uid and net.queued_requests() == 0,
			"llega el uso: primero el uso y después el pedido")
	# Lo que nunca llega no traba para siempre: a los ORDER_WAIT_MSEC se sigue.
	var stuck := (other.state.use_presses_seen + 1) & 0xFF
	input = _b_input(stuck, [[poison.uid, seq + 50]])
	var from := Time.get_ticks_msec()
	while other.state.use_presses_seen != stuck and Time.get_ticks_msec() - from < InvNet.ORDER_WAIT_MSEC + 2000:
		net.use_before_step(other, input)
		await get_tree().physics_frame
	var waited := Time.get_ticks_msec() - from
	_check(other.state.use_presses_seen == stuck and waited >= InvNet.ORDER_WAIT_MSEC and count.call(poison.uid) == 3,
			"un uso que espera un pedido que nunca llega se rechaza a los %d ms, sin gastar" % waited)
	net._inbox.append([2, seq + 2, Op.HOTBAR_SET, [2, poison.uid], (stuck + 1) & 0xFF])
	from = Time.get_ticks_msec()
	while inventory.loadout.hotbar[2] != poison.uid and Time.get_ticks_msec() - from < InvNet.ORDER_WAIT_MSEC + 2000:
		await get_tree().physics_frame
	waited = Time.get_ticks_msec() - from
	_check(inventory.loadout.hotbar[2] == poison.uid and waited >= InvNet.ORDER_WAIT_MSEC,
			"un pedido que espera un uso que nunca llega se procesa igual a los %d ms" % waited)
	# El límite de usos sin confirmar en esta máquina.
	var before := actor.state.use_presses_seen
	var queued := 0
	for i in InvNet.MAX_USES_WAITING + 8:
		if net.queue_use(999999, net.catalog.find(&"veneno")):
			queued += 1
	_check(queued == InvNet.MAX_USES_WAITING, "no salen más de %d usos sin confirmar (salieron %d)" % [InvNet.MAX_USES_WAITING, queued])
	for i in 120:
		if net.replica.uses_waiting() == 0:
			break
		await get_tree().physics_frame
	_check(net.replica.uses_waiting() == 0 and actor.state.use_presses_seen == (before + InvNet.MAX_USES_WAITING) & 0xFF,
			"el host los contesta todos, de a uno por tick y en orden")


# --- 11. Corte y salida ---------------------------------------------------------------------------

func _cut_and_leave() -> void:
	# A B se le corta la conexión: el host le apaga los estados.
	var b_stamina := other.state.stamina
	lab._on_player_waiting(2)
	_check(other.state.powers == 0 and other.state.stamina == b_stamina, "a B se le corta: se le apaga el pedido y conserva la estamina")
	_check(await _wait_scale(1.0), "nadie la pide: termina")
	# B vuelve a pedirla y se va del todo: termina igual.
	other.state.powers |= ActorPowers.SLOW
	_check(await _wait_scale(NetSync.steps_to_scale(NetSync.scale_to_steps(tuning.slow_scale))), "B la vuelve a pedir")
	other.queue_free()
	_check(await _wait_scale(1.0), "B se va del todo: no queda cámara lenta huérfana")
