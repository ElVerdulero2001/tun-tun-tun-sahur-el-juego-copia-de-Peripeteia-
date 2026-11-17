extends "res://prototypes/objetos_adaptador/probe_network.gd"
const Journal = preload("res://prototypes/objetos_adaptador/host_action_journal.gd")
var journal

func setup(client_id: int) -> void:
	super.setup(client_id)
	if role == "host":
		clock.tick_finished.disconnect(after_tick)
		journal = Journal.new(); add_child(journal)
		check("host_journal_start", journal.start(adapter, client_id, policy))
		journal.action_resolved.connect(resolved)
		channel.closed.connect(func(): journal.stop())
		clock.tick_finished.connect(after_tick) # publish only AFTER journal ACKs

func policy(peer: int, _a: Dictionary, _tick: int) -> String:
	# Deliberate fixture grant ONLY. Real reach/inventory policy is not installed.
	return "" if peer == peer_id else "not_owner"

func receive_action(a: Dictionary) -> void:
	var result: Dictionary = journal.request(peer_id, a)
	check("request_accepted_%d" % a.id, result.status in ["scheduled", "applied"])
	if not ledger.has(a.id): ledger[a.id] = a.duplicate(true)

func provide(who: ActorBody, tick: int) -> ActorInput:
	if role == "host": check("journal_prepare_%d" % tick, journal.before_capture(tick))
	return super.provide(who, tick)

func resolved(result: Dictionary) -> void:
	check("journal_result_applied_%d" % result.id, result.status == "applied")
	check("journal_result_after_step_%d" % result.id, adapter.world.get_tick() == result.applied_tick)
	if result.kind == "release": release_applied = result.applied_tick; release_requested = result.requested_tick

func after_tick(tick: int) -> void:
	if role == "host": acks = journal.confirmations()
	super.after_tick(tick)
