extends Node
## Installation points for a scene using NetSync, ClientPrediction and SimClock.
## No change to NetSync's actor wire format. One fixed granted binding only.
signal object_authority_applied(tick: int, revision: int)
signal object_authority_rejected(reason: String)
var history
var sync: NetSync
var channel
var own_states_received := 0
var slow_announcements := 0
var authorities_applied := 0
var _pending := {}
var _latest := {}
var _other: Callable
var _base: Callable

func start(p_history, p_sync: NetSync, p_channel, other_state: Callable, base_state: Callable) -> bool:
	if history != null or p_history == null or p_sync == null or p_channel == null \
		or p_sync.clock != p_history.clock or not p_channel.stats().bound \
		or not other_state.is_valid() or not base_state.is_valid(): return false
	history = p_history; sync = p_sync; channel = p_channel; _other = other_state; _base = base_state
	history.clock.tick_finished.connect(after_actor_tick)
	channel.closed.connect(_channel_closed)
	return true

## Call at tick_started BEFORE input capture/ActorMotor. The scene still owns
## scheduled events/consumables in step_actor; replay hooks must cover them too.
func before_actor_tick(tick: int) -> void:
	if history == null or tick != history.clock.tick or tick <= history.stats().actor_tick: return
	for span in sync.received_world_slow:
		history.apply_world_slow(span[0], span[1], span[2], tick)
		slow_announcements += 1
	sync.received_world_slow.clear()
	sync.apply_pending_snapshot(_own_state.bind(tick), _other, _base)

func _own_state(host_tick: int, state: PackedByteArray, used_tick: int, _margin: int, current: int) -> void:
	own_states_received += 1
	if host_tick < current: history.reconcile_actor(host_tick, state, used_tick, current)

## Connected AFTER the history recorder. Also callable while clock is paused;
## never restores inside tick_started/provider/replay.
func after_actor_tick(_tick: int = -1) -> void:
	var packet: Dictionary = channel.take_packet()
	if not packet.is_empty():
		if _pending.is_empty() or packet.tick == _pending.tick: _pending = packet
		else: _latest = packet
	if _pending.is_empty() or history.clock.tick != history.stats().actor_tick: return
	# Pin the first future state until reachable. Keep only the latest successor.
	# Once a newer state is already eligible, use it to reduce replay work.
	if not _latest.is_empty() and _latest.tick <= history.clock.tick:
		_pending = _latest; _latest = {}
	if _pending.tick > history.clock.tick or not history.actor_baseline_ready: return
	packet = _pending; _pending = _latest; _latest = {}
	if history.apply_authority_trusted(packet):
		authorities_applied += 1
		object_authority_applied.emit(packet.tick, packet.revision)
	else:
		object_authority_rejected.emit(history.last_error)

func _channel_closed() -> void:
	_pending.clear(); _latest.clear()
	history.actor_baseline_ready = false
	history.adapter.invalidate_history_from(history.clock.tick, "actor")
