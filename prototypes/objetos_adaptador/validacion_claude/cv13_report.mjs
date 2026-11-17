// Validación independiente (Claude), entrega 13: califica una corrida de run_network_claude_e13.ps1
// con los criterios de docs/net/validacion_objetos/criterios_entrega_13.md.
// Uso: node cv13_report.mjs <carpeta network13_...>
import fs from 'node:fs';
import path from 'node:path';

const [dir] = process.argv.slice(2);
const read = (f) => { try { return JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8').replace(/^﻿/, '')); } catch { return null; } };
const runner = read('runner.json');
const out = [];
const add = (mode, id, verdict, metric, tol = '') => out.push({ mode, id, verdict, metric: typeof metric === 'string' ? metric : JSON.stringify(metric), tol });
const pf = (ok) => (ok ? 'PASS' : 'FAIL');
const MAX_BYTES = 1050000;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// Proceso y copias
const copiesOk = (runner?.copies || []).every((c) => c.equal);
add('proceso', 'G0_copias', pf(copiesOk && (runner?.copies || []).length > 0), `copias=${(runner?.copies || []).length} distintas=${(runner?.copies || []).filter((c) => !c.equal).map((c) => c.path)}`, 'cada copia = repositorio');
add('proceso', 'G0_dll', 'INFO', runner?.dll_sha256 || '?');
for (const r of runner?.records || []) {
  const scriptErr = r.error_lines.filter((l) => /^SCRIPT ERROR:|^USER ERROR:/.test(l) || (/^ERROR:/.test(l) && !/CHECK_FAILED|root certificate/.test(l)));
  add('proceso', `G0_${r.name}`, pf(!r.timed_out && r.result !== false && scriptErr.length === 0 && (r.name === 'import' || r.result)),
    `exit ${r.exit_code}, ${r.ms} ms, vencido=${r.timed_out}, lineas=${r.error_lines.length}, otras=${JSON.stringify(scriptErr.slice(0, 3))}`, '< 8 s, sin errores de script');
}

const fieldNames = ['tick', 'dt', 'ojos', 'input', 'accion'];
function gradeMode(mode) {
  const host = read(`${mode}_host.result.json`);
  const cli = read(`${mode}_client.result.json`);
  const notes = read(`${mode}_client.trace.json`) || [];
  if (!host || !cli) { add(mode, 'G1_resultados', 'FAIL', `host=${!!host} cliente=${!!cli}`); return; }
  for (const [who, r] of [['host', host], ['cliente', cli]]) {
    const bad = r.checks.filter((c) => !c.passed).map((c) => c.id);
    for (const prefix of ['run_', 'rpc_', 'seam_']) {
      const mine = r.checks.filter((c) => c.id.startsWith(prefix));
      if (mine.length) add(mode, `G1_${who}_${prefix}`, pf(mine.every((c) => c.passed)), `${mine.length} comprobaciones, fallidas=${JSON.stringify(bad.filter((b) => b.startsWith(prefix)))}`);
    }
    if (r.capture_failures.length) add(mode, `G1_${who}_capturas`, 'INFO', r.capture_failures.slice(0, 6));
  }
  const ft = cli.final_tick;
  const hostAck2 = (host.acks || []).find((a) => a.id === 2);
  // B0a
  const runSnaps = notes.filter((n) => n.phase === 'run' && n.method === '_accept_snapshot');
  let maxSeen = -1, accepted = 0; const ownBad = [];
  for (const n of runSnaps) {
    if (n.tick > maxSeen) { maxSeen = n.tick; accepted++; }
    const h = host.ticks[String(n.tick)];
    if (!h || h.actor !== n.own_sha) ownBad.push(n.tick);
  }
  const senders = cli.tap?.in_senders || [];
  add(mode, 'B0a_estados_por_netsync', pf(senders.length > 0 && senders.every((s) => s === 1) && accepted === cli.final.snapshots_received
    && cli.provenance.latest_misses.length === 0 && ownBad.length === 0 && cli.final.own_states > 0),
  { rpc_entrantes: senders.length, remitentes_no_1: senders.filter((s) => s !== 1).length, ejecutados: runSnaps.length, aceptados_replica: accepted,
    snapshots_received: cli.final.snapshots_received, misses: cli.provenance.latest_misses, estado_propio_distinto: ownBad.slice(0, 5), own_states: cli.final.own_states },
  'todo snapshot de un RPC del peer 1; bytes propios = actor del host');
  // B0b
  if (['time_order', 'time_old'].includes(mode)) {
    const spans = host.slow_announced.map((s) => s.slice(0, 3));
    add(mode, 'B0b_tramo_por_netsync', pf(same(cli.tap.executed_slow, spans) && cli.final.slow_announcements === spans.length && cli.provenance.slow_not_drained === 0),
      { ejecutados: cli.tap.executed_slow, anunciados: host.slow_announced, consumidos: cli.final.slow_announcements, sin_vaciar: cli.provenance.slow_not_drained });
  }
  // B0c
  const pubByRev = new Map(host.publishes.filter((p) => p.ok).map((p) => [p.revision, p]));
  const compByRev = new Map(cli.completions.map((c) => [c.revision, c]));
  const appsRun = cli.applications.filter((a) => a.phase === 'run' || a.phase === 'final');
  const badApps = appsRun.filter((a) => { const c = compByRev.get(a.revision), p = pubByRev.get(a.revision); return !c || !p || c.snap !== p.snap || c.tick !== p.tick || a.C !== p.tick; });
  const hostAcks = host.final?.transfer_acks;
  add(mode, 'B0c_sobres_por_canal', pf(appsRun.length > 0 && badApps.length === 0 && cli.final.completed === hostAcks),
    { aplicados: appsRun.length, sin_origen: badApps.map((a) => a.revision), completos_cliente: cli.final.completed, acks_host: hostAcks, publicados: host.publishes.length });
  // B0d
  const sched = host.actions_in.filter((e) => e.outcome === 'scheduled');
  add(mode, 'B0d_pedidos_por_canal', pf(sched.length === 2 && sched.every((e) => e.sender === host.peer_id) && same(sched.map((e) => e.id).sort(), [1, 2])),
    { programados: sched.map((e) => [e.id, e.tick, e.applied, e.sender]), todos: host.actions_in.filter((e) => e.phase === 'run').map((e) => [e.id, e.outcome]) });
  // B1
  const graded = [], ungraded = [];
  for (const a of cli.applications.filter((x) => x.phase === 'run' && x.T > x.C)) {
    let reason = null;
    for (let t = a.C + 1; t <= a.T && !reason; t++) {
      const c = a.frames[String(t)], h = host.ticks[String(t)]?.frame;
      if (!h || !c) { reason = [t, 'sin cuadro']; break; }
      for (let i = 0; i < 5; i++) if (c[i] !== h[i]) { reason = [t, fieldNames[i]]; break; }
    }
    if (reason) ungraded.push([a.T, a.C, ...reason]);
    else graded.push({ T: a.T, C: a.C, equal: a.world === host.ticks[String(a.T)]?.world });
  }
  const mism = graded.filter((g) => !g.equal);
  const b1 = mism.length ? 'FAIL' : graded.length < 3 ? 'INSUFICIENTE' : 'PASS';
  add(mode, 'B1_mismo_tick_tras_replay', b1, { calificadas: graded.length, distintas: mism.map((g) => [g.T, g.C]), sin_calificar: ungraded.length,
    motivos: Object.entries(ungraded.reduce((m, u) => { m[u[3]] = (m[u[3]] || 0) + 1; return m; }, {})), ejemplo: ungraded.slice(0, 4),
    pasos: graded.map((g) => g.T - g.C) }, 'SHA igual en toda comparación calificada; >= 3');
  if (mode !== 'future') {
    const after = graded.filter((g) => hostAck2 && g.C >= hostAck2.applied_tick && g.equal);
    add(mode, 'B1r_tras_la_suelta', pf(after.length > 0), { suelta_aplicada: hostAck2?.applied_tick, calificadas_despues: after.map((g) => [g.T, g.C]) });
  }
  // B2
  const fin = cli.applications.find((a) => a.T === ft && a.C === ft);
  add(mode, 'B2_final_sin_replay', pf(!!fin && fin.world === host.ticks[String(ft)]?.world), { final: fin ? [fin.T, fin.C, fin.paused] : null, igual: fin?.world === host.ticks[String(ft)]?.world });
  // B3
  const effIds = cli.effects.map((e) => e[0]);
  const confIds = cli.confirmations.map((c) => c[0]);
  const conf2 = cli.confirmations.find((c) => c[0] === 2);
  const pubWith2 = (rev) => (pubByRev.get(rev)?.acks || []).includes(2);
  const firstWith2 = appsRun.find((a) => pubWith2(a.revision));
  const ackWithout2 = cli.completions.filter((c) => c.phase === 'run' && c.clock > cli.release_requested && !c.acks.includes(2));
  add(mode, 'B3_efecto_y_confirmacion', pf(same(effIds.slice().sort(), [1, 2]) && same(confIds.slice().sort(), [1, 2]) && conf2 && hostAck2
    && conf2[3] === hostAck2.applied_tick && firstWith2 && conf2[4] === firstWith2.revision && ackWithout2.length > 0),
  { efectos: cli.effects, confirmaciones: cli.confirmations, ack_host: hostAck2, primer_aplicado_con_2: firstWith2?.revision,
    transferencias_sin_la_2_despues_del_pedido: ackWithout2.map((c) => c.revision) }, 'una vez por id; la confirmación física llega con el sobre que la trae');
  // B4
  add(mode, 'B4_emisor', pf(host.watch.violations.length === 0 && host.watch.max_tx_bytes <= 2 * MAX_BYTES && host.final.max_wire <= 1012 && host.watch.observations > 0),
    { violaciones: host.watch.violations, max_tx: host.watch.max_tx_bytes, max_wire: host.final.max_wire, cuadros: host.watch.observations,
      max_cuadros_por_transferencia: Math.max(0, ...Object.values(host.watch.frames_by_transfer)) });
  // B5
  const cs = cli.struct, hs = host.struct;
  const capKeys = { bridge_ticks: 120, bridge_bytes: 262144, adapter_ticks: 120, bridge_pending: 1, channel_rx: MAX_BYTES };
  const capBad = Object.entries(capKeys).filter(([k, v]) => Math.max(cs.first[k] ?? 0, cs.second[k] ?? 0) > v);
  const hostBad = Math.max(hs.first.inputs ?? 0, hs.second.inputs ?? 0) > 241;
  add(mode, 'B5_estructuras_acotadas', pf(capBad.length === 0 && !hostBad && cli.rx_watch.max_rx <= MAX_BYTES && cli.provenance.slow_not_drained === 0),
    { excedidas: capBad, host_inputs: [hs.first.inputs, hs.second.inputs], max_rx: cli.rx_watch.max_rx, max_pendiente: cli.rx_watch.max_pending });
  if (mode === 'base') {
    const unc = ['pending_inputs', 'commands', 'pred_inputs', 'pred_states', 'pred_claimed', 'events', 'spans', 'tap_queue', 'adapter_pending', 'adapter_queued', 'known_actions', 'adapter_actions'];
    const grew = unc.filter((k) => (cs.second[k] ?? 0) > (cs.first[k] ?? 0));
    const hostGrew = ['claims', 'adapter_actions'].filter((k) => (hs.second[k] ?? 0) > (hs.first[k] ?? 0));
    add(mode, 'B5_sin_crecimiento_200_ticks', pf(grew.length === 0 && hostGrew.length === 0), { crecen_cliente: grew.map((k) => [k, cs.first[k], cs.second[k]]),
      crecen_host: hostGrew, primera: cs.first, segunda: cs.second }, 'segunda mitad <= primera en lo que no tiene cota');
    add(mode, 'I_objetos_godot', 'INFO', { cliente: [cs.first.objects, cs.second.objects], host: [hs.first.objects, hs.second.objects] });
    const rel = host.actions_in.filter((e) => e.id === 2 && e.phase === 'run');
    add(mode, 'M_base_duplicados_y_acks_falsos', pf(cli.forged_acks.length === 6 && rel.length === 3 && rel.filter((e) => e.outcome === 'scheduled').length === 1
      && rel.filter((e) => e.outcome === 'duplicate_same').length === 2 && cli.final.completed === host.final.transfer_acks),
    { acks_falsos: cli.forged_acks, pedidos_suelta: rel.map((e) => [e.outcome, e.host_tick]), completos: cli.final.completed, acks_host: host.final.transfer_acks });
  }
  if (mode === 'delay') {
    let mx = -1, late = 0; for (const t of cli.tap.executed_snapshots) { if (t < mx) late++; mx = Math.max(mx, t); }
    add(mode, 'I_snapshots_desordenados', 'INFO', { desordenados: late, ejecutados: cli.tap.executed_snapshots.length, perdidos_netsync: cli.final.snapshots_missing });
    const lag = host.publishes.filter((p) => p.tick !== ft).map((p) => p.at - p.tick);
    add(mode, 'M_delay_publicacion_tardia', pf(lag.length > 0 && lag.every((d) => d >= 6)), { demoras: [...new Set(lag)] });
  }
  if (mode === 'time_order') {
    const slowAt = cli.recoveries.find((r) => r[1] === 'timeline_invalidated:world_time');
    const recAfter = slowAt && appsRun.find((a) => a.T >= slowAt[0]);
    add(mode, 'M_time_order_sobre_antes_que_anuncio', pf(cli.hold.authority_tick >= 24 && !!slowAt && slowAt[0] >= cli.hold.released_at && !!recAfter),
      { retencion: cli.hold, invalidado: slowAt, recuperado_en: recAfter ? [recAfter.T, recAfter.C] : null, pedidos: cli.needs.slice(0, 8) });
  }
  if (mode === 'time_old' || mode === 'conflict_pause') {
    const s = cli.suspended_action;
    add(mode, 'M_accion_nueva_suspendido', pf(s.status === 'rejected' && s.reason === 'not_ready'), s);
  }
  if (mode === 'time_old') {
    const slowAt = cli.recoveries.find((r) => r[1] === 'timeline_invalidated:world_time');
    const recAfter = slowAt && appsRun.find((a) => a.T > slowAt[0]);
    add(mode, 'M_time_old_recupera', pf(!!slowAt && !!recAfter && slowAt[0] - 18 > 24), { invalidado: slowAt, atras: slowAt ? slowAt[0] - 18 : null, recuperado_en: recAfter ? [recAfter.T, recAfter.C] : null, pedidos: cli.needs.slice(0, 8) });
  }
  if (mode === 'conflict_pause') {
    const c = cli.conflict;
    const rec = appsRun.find((a) => a.T > 22);
    add(mode, 'M_conflicto_de_captura', pf(c.accepted === false && c.error === 'input_conflict' && c.ready === false && c.baseline === false
      && cli.needs.some((n) => n[1] === 'input_conflict') && !!rec), { conflicto: c, recuperado_en: rec ? [rec.T, rec.C] : null });
    add(mode, 'M_pausa', pf(cli.pause.resumed_tick === 56 && cli.pause.frames > 0), cli.pause);
  }
  if (mode === 'future') {
    const early = appsRun.filter((a) => a.T < ft);
    add(mode, 'M_future_seguridad', pf(appsRun.every((a) => a.C <= a.T) && !cli.rejected_authorities.some((r) => r[1] === 'future_authority') && cli.future.frames > 0),
      { cuadros_con_futuro: cli.future.frames, rechazos: cli.rejected_authorities });
    add(mode, 'I_future_vivacidad', early.length === 0 ? 'HALLAZGO' : 'INFO', { aplicados_antes_del_final: early.length, max_espera_ms: cli.future.max_wait_ms,
      reemplazos_mientras_esperaba: cli.future.replaced, episodios: cli.future.episodes, completos: cli.final.completed });
  }
  if (mode === 'big') {
    const revs = cli.completions.filter((c) => c.phase === 'run').map((c) => c.revision);
    const inc = revs.every((r, i) => i === 0 || r > revs[i - 1]);
    const gaps = revs.some((r, i) => i > 0 && r - revs[i - 1] > 1);
    const maxFrames = Math.max(0, ...Object.values(host.watch.frames_by_transfer));
    add(mode, 'M_big_presion', pf(cli.snapshot_bytes > 8 * 960 && maxFrames >= 2 && cli.rx_watch.partial_frames > 0 && inc && gaps && host.publishes.length > revs.length),
      { snapshot: cli.snapshot_bytes, cajas: cli.extra_boxes, tamanos: cli.box_sizes, max_cuadros_por_transferencia: maxFrames, cuadros_con_rearmado_parcial: cli.rx_watch.partial_frames,
        publicados: host.publishes.length, recibidos: revs.length, crecientes: inc, con_saltos: gaps });
  }
  if (mode === 'rpc') gradeRpc(host, cli);
}

function gradeRpc(host, cli) {
  const expect = { magic: 'chunk_header', old_connection: 'chunk_header', short: 'chunk_size', over_wire: 'chunk_size', total_over_max: 'chunk_header',
    count_mismatch: 'chunk_header', index_out_of_range: 'chunk_header', data_length: 'chunk_header', id_zero: 'chunk_header', id_over: 'chunk_header',
    stale_id: 'stale_transfer', digest: 'transfer_digest', scope: 'packet_format_or_scope', stale_revision: 'stale_authority', chunk_conflict: 'chunk_conflict',
    after_conflict: 'stale_transfer', transfer_conflict: 'transfer_conflict' };
  const seen = new Set();
  for (const c of cli.host_cases) {
    seen.add(c.case);
    const clean = c.rx_bytes === 0 && c.applied === 0 && c.world_same;
    let ok;
    if (c.case === 'control_accept') ok = clean && c.completed === 1 && c.rejected === 0 && c.pending_bytes > 0;
    else if (c.case === 'after_conflict') ok = clean && c.error === expect[c.case] && c.rejected >= 1 && c.completed === 0 && c.pending_bytes === 0;
    else ok = clean && c.error === expect[c.case] && c.rejected === 1 && c.completed === 0 && c.pending_bytes === 0;
    add('rpc', `R_host_a_cliente_${c.case}`, pf(ok), c, `error ${expect[c.case] || 'aceptado'}; rearmado 0; nada aplicado; mundo igual`);
  }
  const missing = [...Object.keys(expect), 'control_accept'].filter((k) => !seen.has(k));
  add('rpc', 'R_host_a_cliente_todos', pf(missing.length === 0), { faltan: missing });
  const counts = host.rpc_eval.counts || {};
  const others = Object.entries(counts).filter(([k]) => k !== 'control' && k !== 'forged_acks');
  add('rpc', 'R_cliente_a_host_acciones', pf(counts.control === 1 && others.length === 0 && (counts.forged_acks || 0) === 0),
    { emisiones: counts, control: host.rpc_eval.control_entry }, 'solo el control emite action_requested');
  add('rpc', 'R_cliente_a_host_acks_falsos', pf(host.rpc_eval.transfer_acks_after === host.rpc_eval.transfer_acks_before),
    [host.rpc_eval.transfer_acks_before, host.rpc_eval.transfer_acks_after]);
  const hc = host.host_close;
  add('rpc', 'R_cierre_host', pf(hc.closed === 1 && hc.publish === false && hc.error === 'not_authority_sender' && hc.restart === false && !hc.stats.bound && hc.stats.tx_bytes === 0), hc);
  const cr = cli.close;
  add('rpc', 'I_cierre_de_un_solo_lado', cr.client_bound_after_host_stop ? 'HALLAZGO' : 'INFO', { cliente_vinculado_tras_stop_del_host: cr.client_bound_after_host_stop });
  add('rpc', 'R_cierre_cliente', pf(cr.pending_before > 0 && cr.closed_once === 1 && cr.bridge_pending_empty && cr.baseline === false && cr.ready === false
    && String(cr.adapter_error).startsWith('timeline_invalidated:actor') && !cr.stats.bound && cr.stats.rx_bytes === 0 && cr.stats.pending_bytes === 0
    && cr.queue_new.status === 'rejected' && cr.queue_new.reason === 'not_ready' && cr.restart === false && cr.request === false), cr);
  add('rpc', 'R_fragmento_tras_cierre', pf(cli.after_close.error === 'unbound_sender' && cli.after_close.rejected === 1), cli.after_close);
}

function gradeCapacity() {
  const r = read('capacity.result.json');
  if (!r) { add('capacity', 'C1_resultado', 'FAIL', 'sin resultado'); return; }
  const q = r.capacity;
  const first = q.filter((e) => e[0] <= 256), rest = q.filter((e) => e[0] > 256);
  const t = r.ticks;
  const ok = first.length === 256 && first.every((e) => e[1] === 'queued') && rest.length > 0 && rest.every((e) => e[1] === 'rejected' && e[2] === 'action_capacity')
    && t['280']?.ready === true && t['280']?.known_actions === 256 && t['280']?.adapter_actions === 256 && t['280']?.bridge_ticks <= 120;
  add('capacity', 'C1_tope_de_acciones_por_vinculo', ok ? 'HALLAZGO' : 'FAIL', { encoladas: first.filter((e) => e[1] === 'queued').length,
    rechazos_despues: [...new Set(rest.map((e) => e[2]))], muestras: t, fallas_en_proceso: r.failures },
  'confirmado si 1..256 entran, desde 257 action_capacity, y los registros conservan 256 ids con el diario <= 120');
}

for (const m of runner?.modes || []) { if (m === 'capacity') gradeCapacity(); else gradeMode(m); }
const summary = out.reduce((s, c) => { s[c.verdict] = (s[c.verdict] || 0) + 1; return s; }, {});
for (const c of out) console.log(`${c.verdict.padEnd(6)} [${c.mode}] ${c.id}: ${c.metric.slice(0, 400)}${c.tol ? '  [' + c.tol + ']' : ''}`);
console.log(JSON.stringify(summary));
fs.writeFileSync(path.join(dir, 'report.json'), JSON.stringify({ dir, checks: out, summary }, null, 1));
