extends "res://prototypes/objetos_adaptador/probe_journal_network.gd"
## Validacion independiente (Claude), entrega 16, parte N. Hereda la escena de red de Codex con el
## registro del host (ENet, NetSync, actor, ClientPrediction, history_bridge reales) sin cambiar su
## protocolo. Agrega, por RPC real del cliente: la suelta repetida ya aplicada y una variante con
## otro impulso (tick 60), un pedido 3 de soltar con la caja libre que el host debe rechazar al
## ejecutar (60) y su repeticion (70). Pisa receive_action y resolved SOLO para anotar los
## resultados del 3 y del conflicto (para 1 y 2 llama a la version de Codex). Compara el mundo en
## el mismo tick tras cada replay positivo del cliente, calificando por cuadros C+1..T iguales.
const RELEASE_IMPULSE := Vector3(1.5, 2, -1)
var request_log: Array = []
var resolved_log: Array = []
var host_effects := {}
var published_acks: Array = []
var cmp_pending: Array = []
var comparisons: Array = []
var cmp_sent: Array = []
var extra_sent := {}

func setup(client_id: int) -> void:
	super.setup(client_id)
	if role == "host":
		adapter.action_effect.connect(func(id: int, _k: String): host_effects[id] = host_effects.get(id, 0) + 1)
		journal.action_resolved.connect(func(r: Dictionary): resolved_log.append(r.duplicate(true)))
	else:
		network.object_authority_applied.connect(_cmp_applied)

func receive_action(a: Dictionary) -> void:
	var r: Dictionary = journal.request(peer_id, a)
	request_log.append({"id": a.id, "status": r.get("status", ""), "reason": r.get("reason", ""), "clock": clock.tick,
		"result": r, "impulse": a.impulse, "tick": a.tick})
	# Igual que la escena de Codex para 1 y 2 (su registro de la escena); el 3 es mio.
	if a.id in [1, 2] and r.get("status", "") in ["scheduled", "applied"] and not ledger.has(a.id): ledger[a.id] = a.duplicate(true)

func resolved(result: Dictionary) -> void:
	if result.id in [1, 2]: super.resolved(result)

func after_tick(tick: int) -> void:
	super.after_tick(tick)
	if role == "host":
		if tick % 4 == 0 or tick == FINAL_TICK: published_acks.append([tick, acks.map(func(k): return k.id)])
		eval_comparisons()
	else:
		if tick == 60:
			var rel := {"id": 2, "tick": release_requested, "kind": "release", "anchor": Vector3.ZERO, "impulse": RELEASE_IMPULSE}
			extra_sent.dup_release = channel.request_action(rel)
			var conflict := rel.duplicate(true); conflict.impulse = Vector3(0, 1, 0)
			extra_sent.conflict_release = channel.request_action(conflict)
			extra_sent.three = channel.request_action({"id": 3, "tick": tick + 2, "kind": "release", "anchor": Vector3.ZERO, "impulse": Vector3.ZERO})
			extra_sent.three_tick = tick + 2
		if tick == 70:
			extra_sent.three_dup = channel.request_action({"id": 3, "tick": extra_sent.get("three_tick", 62), "kind": "release",
				"anchor": Vector3.ZERO, "impulse": Vector3.ZERO})

func frames_digest(getter: Callable, a: int, b: int) -> String:
	var arr: Array = []
	for t in range(a, b + 1):
		var f: Dictionary = getter.call(t)
		if f.is_empty(): return ""
		var s := StreamPeerBuffer.new(); s.data_array = f.input
		var inp := ActorInput.read_from(s)
		if inp == null: return ""
		inp.held_claim = PackedByteArray()
		var o := StreamPeerBuffer.new(); inp.write_to(o)
		var act: Dictionary = f.action
		arr.append([f.tick, f.dt, f.eyes, o.data_array, [] if act.is_empty() else [act.id, act.kind, act.tick, act.anchor, act.impulse]])
	return var_to_bytes(arr).hex_encode().sha256_text()

func _cmp_applied(checkpoint: int, _revision: int) -> void:
	if clock.tick <= checkpoint: return
	var digest := frames_digest(history.recorded_frame, checkpoint + 1, clock.tick)
	cmp_sent.append([clock.tick, checkpoint])
	_cmp.rpc_id(1, clock.tick, checkpoint, state_hash(), digest)

@rpc("any_peer", "call_remote", "reliable")
func _cmp(t: int, c: int, client_hash: String, digest: String) -> void:
	if role != "host" or multiplayer.get_remote_sender_id() != peer_id: return
	cmp_pending.append({"t": t, "c": c, "hash": client_hash, "digest": digest})
	eval_comparisons()

func eval_comparisons() -> void:
	var rest: Array = []
	for p in cmp_pending:
		if not host_hashes.has(p.t): rest.append(p); continue
		var host_digest := frames_digest(adapter.recorded_frame, p.c + 1, p.t)
		comparisons.append({"t": p.t, "c": p.c, "hash_equal": host_hashes[p.t] == p.hash,
			"frames_equal": not p.digest.is_empty() and host_digest == p.digest})
	cmp_pending = rest

func finish() -> void:
	if done: return
	if not result_path.is_empty():
		var extra := {"role": role, "request_log": request_log, "resolved_log": resolved_log, "host_effects": host_effects,
			"published_acks": published_acks, "comparisons": comparisons, "cmp_unevaluated": cmp_pending, "cmp_sent": cmp_sent,
			"extra_sent": extra_sent, "release_requested": release_requested, "release_applied": release_applied,
			"confirmations": confirmations, "effects": effects, "rejected_authorities": rejected_authorities,
			"host_journal_stats": journal.stats() if journal != null else {}}
		FileAccess.open(result_path.replace(".result.json", ".cv16.json"), FileAccess.WRITE).store_string(JSON.stringify(extra))
	super.finish()
