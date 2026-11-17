extends "res://prototypes/objetos_adaptador/probe_action_window.gd"
const Journal = preload("res://prototypes/objetos_adaptador/host_action_journal.gd")
var journal
var outcomes := {}
var policy_allowed := true
var policy_calls := 0
var largest := 0
var effects_by_id := {}
var omit_capture := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="): result_path = arg.trim_prefix("--result=")
	SimClock.clear_world_slow()
	tuning = ActorTuning.new(); add_child(tuning)
	var actors := Node3D.new(); add_child(actors)
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(12, 0.2, 12)
	shape.shape = box; floor_body.add_child(shape); add_child(floor_body); floor_body.position.y = -0.1
	actor = ACTOR.instantiate(); actor.owner_peer_id = 7; actors.add_child(actor)
	clock = SimClock.new(); clock.actors_root = actors; clock.tuning = tuning
	clock.paused = true; clock.input_provider = provide; add_child(clock); clock.set_physics_process(false)
	adapter = Adapter.new(); add_child(adapter)
	check("adapter_start", adapter.start(clock, actor, tuning, make_world, 2, 1, 1))
	journal = Journal.new(); add_child(journal)
	check("journal_start", journal.start(adapter, 7, authorize))
	journal.action_resolved.connect(on_resolved)
	adapter.action_effect.connect(func(id: int, _kind: String): effects_by_id[id] = effects_by_id.get(id, 0) + 1)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("wrong_peer_atomic", journal.request(8, intent(1)).reason == "invalid_peer" and journal.stats().records == 0)
	var malformed := intent(1); malformed.extra = PackedByteArray()
	check("extra_fields_rejected", journal.request(7, malformed).reason == "invalid_action")
	malformed = intent(1); malformed.impulse = Vector3(INF, 0, 0)
	check("nonfinite_rejected", journal.request(7, malformed).reason == "invalid_action")
	malformed = intent(1); malformed.tick = 121
	check("future_out_of_window", journal.request(7, malformed).reason == "action_tick_window")
	for tick in range(1, 751):
		var a := intent(tick)
		if tick == 1: a.kind = "release" # cannot release a free body
		check("schedule_%d" % tick, journal.request(7, a).status == "scheduled")
		var duplicate: Dictionary = journal.request(7, a)
		check("pending_duplicate_%d" % tick, duplicate.status == "scheduled")
		duplicate.status = "forged"
		check("copy_isolation_%d" % tick, journal.request(7, a).status == "scheduled")
		var conflict := a.duplicate(true); conflict.impulse = Vector3(1, 0, 0)
		check("conflict_%d" % tick, journal.request(7, conflict).reason == "action_identity_conflict")
		policy_allowed = tick != 3 # grant revoked AFTER scheduling
		clock._run_tick()
		check("terminal_once_%d" % tick, outcomes.has(a.id))
		check("terminal_duplicate_%d" % tick, journal.request(7, a) == outcomes.get(a.id, {}))
		check("native_ready_%d" % tick, adapter.ready_for_input and adapter.world.get_tick() == tick)
		largest = maxi(largest, journal.stats().records)
		if checks.any(func(c): return not c.passed): break
	check("750_steps", clock.tick == 750)
	check("invalid_transition_no_effect", outcomes.get(10, {}).get("reason") == "invalid_hand_transition" and not effects_by_id.has(10))
	check("revoked_policy_no_effect", outcomes.get(30, {}).get("reason") == "permission_revoked" and not effects_by_id.has(30))
	check("memory_bounded", largest <= 122 and journal.stats().scheduled == 0)
	check("old_retry_retired", journal.request(7, intent(2)).reason == "retired_action")
	var hole := intent(751); hole.id = 7499
	check("unseen_old_id_rejected", journal.request(7, hole).reason == "nonmonotonic_action_id")
	# A late request executes at the next real boundary, with original tick in ACK.
	var late := intent(751); late.tick = 740
	check("late_scheduled", journal.request(7, late).scheduled_tick == 751)
	clock._run_tick()
	check("late_ack_actual_tick", outcomes.get(7510, {}).get("requested_tick") == 740 and outcomes.get(7510, {}).get("applied_tick") == 751)
	check("next_action_scheduled", journal.request(7, intent(752)).status == "scheduled")
	var future := intent(755)
	check("future_scheduled", journal.request(7, future).status == "scheduled")
	var earlier := intent(756); earlier.tick = 753
	check("future_order_cannot_reverse_ids", journal.request(7, earlier).reason == "action_order")
	check("acks_bounded", journal.confirmations().size() == 16)
	omit_capture = true
	clock._run_tick() # adapter stops BEFORE native stepping; journal must not ACK
	check("suspension_closes_journal", not journal.stats().bound)
	check("uncompleted_step_never_acknowledged", outcomes.get(7520, {}).get("status") == "cancelled" and not effects_by_id.has(7520) and adapter.world.get_tick() == 751)
	check("pending_cancelled_once", outcomes.get(7550, {}).get("status") == "cancelled" and not effects_by_id.has(7550))
	var n := outcomes.size(); journal.stop()
	check("stop_idempotent", outcomes.size() == n and not journal.stats().bound and journal.stats().scheduled == 0)
	check("closed_rejects", journal.request(7, intent(756)).reason == "not_bound")
	var failures := checks.filter(func(c): return not c.passed).size()
	var result := {"mode": "host_journal", "status": "PASSED" if failures == 0 else "FAILED", "failures": failures,
		"checks": checks, "stats": journal.stats(), "max_records": largest, "policy_calls": policy_calls,
		"resolved": outcomes.size(), "effect_ids": effects_by_id.size()}
	FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(result))
	print("HOST_JOURNAL=" + JSON.stringify({"status": result.status, "failures": failures, "checks": checks.size(), "max_records": largest}))
	get_tree().quit(0 if failures == 0 else 1)

func intent(tick: int) -> Dictionary:
	return {"id": tick * 10, "tick": tick, "kind": "release" if adapter.world.sample(2, 1).held else "grab",
		"anchor": Vector3.ZERO, "impulse": Vector3.ZERO}

func authorize(peer: int, a: Dictionary, tick: int) -> String:
	policy_calls += 1
	check("policy_execution_phase_%d" % a.id, peer == 7 and clock.tick == tick and adapter.world.get_tick() == tick - 1)
	a.impulse = Vector3(90, 0, 0) # policy cannot mutate stored request
	return "" if policy_allowed else "permission_revoked"

func provide(_who: ActorBody, tick: int) -> ActorInput:
	var input := ActorInput.make(tick, Vector2.ZERO, 0.0, 0, 0)
	input.hold = ActorInput.pack_hold(1, -0.45, 1.8, Quaternion.IDENTITY)
	check("host_prepare_%d" % tick, journal.before_capture(tick))
	check("not_confirmed_before_native_step_%d" % tick, not outcomes.has(tick * 10) or outcomes[tick * 10].status != "applied")
	if not omit_capture: check("capture_%d" % tick, adapter.capture(input))
	return input

func on_resolved(result: Dictionary) -> void:
	check("resolution_once_%d" % result.id, not outcomes.has(result.id))
	if result.status == "applied":
		check("ack_after_native_%d" % result.id, result.applied_tick == clock.tick and adapter.world.get_tick() == clock.tick)
		check("effect_once_%d" % result.id, effects_by_id.get(result.id, 0) == 1)
	outcomes[result.id] = result.duplicate(true)
