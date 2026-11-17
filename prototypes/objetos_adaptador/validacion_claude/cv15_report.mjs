// Validacion independiente (Claude), entrega 15: califica las partes E y L de una carpeta de
// run_claude_e15.ps1 segun docs/net/validacion_objetos/criterios_entrega_15.md. Las regresiones
// (cv14_local y cv14_net) se califican con cv14_report.mjs sin cambios. Uso: node cv15_report.mjs <carpeta>
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
if (!dir) { console.error('falta la carpeta'); process.exit(2); }
const read = (f) => { const p = path.join(dir, f); return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, 'utf8').replace(/^﻿/, '')) : null; };
const runner = read('runner.json');
const rows = [];
const add = (id, verdict, note = '') => rows.push({ id, verdict, note });
const pass = (b) => (b ? 'PASS' : 'FAIL');
const f3 = (x) => (typeof x === 'number' ? Math.round(x * 1000) / 1000 : x);

// ---- procesos: lineas esperadas (documentadas en la entrega 14) aparte del resto
const EXPECTED = [/Method expected 1 argument\(s\), but called with 0/, /Failed to read the root certificate store/];
const procs = runner ? runner.records.filter((r) => r.name !== 'import') : [];
const other = (r) => r.error_lines.filter((l) => !EXPECTED.some((e) => e.test(l)) && !/^\s+at:/.test(l));
const bad = procs.filter((r) => r.timed_out || r.exit_code !== 0 || other(r).length || !r.result);
add('runner_processes', pass(procs.length > 0 && bad.length === 0),
  `${procs.length} procesos; con problema: ${bad.map((r) => `${r.name}(exit ${r.exit_code}${r.timed_out ? ' vencido' : ''}, otras lineas ${other(r).length}, result ${r.result})`).join('; ') || 'ninguno'}; lineas esperadas ${procs.reduce((a, r) => a + r.error_lines.filter((l) => EXPECTED.some((e) => e.test(l))).length, 0)}; max ${Math.max(0, ...procs.map((r) => r.ms))} ms; Godot abiertos al final ${runner?.godot_left}`);

// ---- E
const group = (res, prefix, id, extra = '') => {
  const cs = res.checks.filter((c) => c.id.startsWith(prefix));
  if (!cs.length) { add(id, 'INSUFICIENTE', 'sin comprobaciones'); return; }
  const failed = cs.filter((c) => !c.passed).map((c) => c.id);
  add(id, failed.length ? 'FAIL' : 'PASS', `${cs.length - failed.length}/${cs.length}${failed.length ? ' fallan: ' + failed.slice(0, 8).join(', ') : ''}${extra ? ' | ' + extra : ''}`);
};
const ex = read('expiry.result.json');
if (ex) {
  const i = ex.info;
  group(ex, 'setup_', 'E_setup');
  group(ex, 'capture_', 'E_capture');
  group(ex, 'C_', 'E_group_C', `${i.c_deliveries} sobres, ${i.c_delivery_failures} rechazados`);
  for (const e of ['E1', 'E2', 'E3', 'E4', 'E5', 'E6', 'E7', 'E8', 'E9', 'E10', 'E11', 'E12', 'E13']) group(ex, e + '_', e);
  add('E_info', 'INFO', `vencidas ${i.expiries} (esperadas ${i.expected}), confirmadas ${i.confirmed}, conocidas ${i.known}, rechazos de cola ${JSON.stringify(i.queue_rejected)}; reentrada ${JSON.stringify(i.reentry)}; memoria ${JSON.stringify(i.mem)}; sobres ${JSON.stringify(i.deliveries.map((d) => [d.label, d.clock, d.tick, d.ok, d.new_expiries]))}; muestras ${JSON.stringify(i.samples.map((e) => [e.tick, e.clock, e.kind]))}`);
  add('E_status', pass(ex.status === 'PASSED'), `${ex.failures} fallas, ${ex.checks.length} comprobaciones, ${i.ms} ms`);
} else add('E', 'INSUFICIENTE', 'sin resultado de expiry');

// ---- L, por corrida
const tags = [...new Set(procs.map((r) => r.name).filter((n) => /^lanes15/.test(n)).map((n) => n.replace(/_(host|client|intruder)$/, '')))];
const h1 = { runs: 0, stressed: 0, closes: [] };
for (const tag of tags) {
  const lh = read(tag + '_host.result.json'), lc = read(tag + '_client.result.json'), li = read(tag + '_intruder.result.json');
  if (!lh || !lc || !li) { add(tag, 'INSUFICIENTE', 'faltan resultados'); continue; }
  h1.runs++;
  const H = lh.lanes, C = lc.lanes;
  const one = (r) => (r.closes.length === 1 ? r.closes[0] : null);
  const ms = (c, from) => (c ? c.msec - from : null);
  const arrivals = (r, sender, after) => (r.heartbeat_at_unix ? (r.heartbeat_at_unix[String(sender)] || []).filter((u) => u > after).length : '?');
  const guard = [lh, lc, li].every((r) => r.rpc_guard && r.rpc_guard.ok) && [lh, lc].every((r) => r.timeout_ms === 5000 && r.heartbeat_ms === 500);
  add(`${tag}:L0`, pass(guard), `config RPC igual al canal base ${[lh, lc, li].map((r) => r.rpc_guard?.ok)}; base _heartbeat ${JSON.stringify(lh.rpc_guard?.base?._heartbeat)}; vieja ${JSON.stringify(lh.rpc_guard?.tap14?._heartbeat)}; plazo ${lh.timeout_ms} ms; estres pedido ${lh.stress}`);
  const l1 = [];
  { const c = one(C.notice); l1.push(['notice', c && c.error === 'peer_closed' && c.unix - H.notice.stop_unix < 0.5 && one(H.notice) && H.notice.restart_ok === false && C.notice.restart_ok === false]); }
  { const c = one(C.scope_close), h = one(H.scope_close); l1.push(['scope_close', c && h && c.rel >= 4.95 && h.rel >= 4.95 && c.error === 'peer_closed']); }
  { const h = one(H.intruder_close), c = one(C.intruder_close); l1.push(['intruder_close', h && c && h.rel >= 4.95 && c.rel >= 4.95 && h.error === 'peer_closed' && h.unix - C.intruder_close.stop_unix < 0.5]); }
  { const h = one(H.startup), c = one(C.startup);
    l1.push(['startup', h && c && h.error === 'peer_idle_timeout' && c.error === 'peer_idle_timeout' && ms(h, H.startup.start_msec) >= 5000 && ms(h, H.startup.start_msec) <= 5150 && ms(c, C.startup.start_msec) >= 5000 && ms(c, C.startup.start_msec) <= 5150]); }
  { const h = one(H.send_timeout), c = one(C.send_timeout); const d = h ? h.msec - H.send_timeout.tx_started_msec : null;
    l1.push(['send_timeout', h && h.error === 'send_timeout' && d >= 5000 && d <= 5150 && c && c.error === 'peer_closed']); }
  l1.push(['both_close', H.both_close.closes.length === 1 && C.both_close.closes.length === 1]);
  add(`${tag}:L1`, pass(l1.every((x) => x[1])), l1.map((x) => `${x[0]}=${x[1] ? 'ok' : 'MAL'}`).join(' '));
  const good = C.good_heartbeat;
  const goodOk = good.closes.length === 0 && good.bound_at_end;
  const sh = one(C.scope_heartbeat), ih = one(H.intruder_heartbeat);
  const shOk = sh && sh.error === 'peer_idle_timeout' && sh.last_activity_unix <= H.scope_heartbeat.silence_unix + 0.25 && ms(sh, sh.last_activity_msec) >= 5000 && ms(sh, sh.last_activity_msec) <= 5150;
  const ihOk = ih && ih.error === 'peer_idle_timeout' && ih.last_activity_unix <= C.intruder_heartbeat.silence_unix + 0.25 && ms(ih, ih.last_activity_msec) >= 5000 && ms(ih, ih.last_activity_msec) <= 5150;
  const gotSh = arrivals(C.scope_heartbeat, 1, H.scope_heartbeat.silence_unix), gotGood = arrivals(good, 1, H.good_heartbeat.silence_unix), gotIh = arrivals(H.intruder_heartbeat, lh.intruder_id, C.intruder_heartbeat.silence_unix);
  add(`${tag}:L2`, !goodOk ? 'FAIL' : pass(shOk && ihOk && gotSh > 0 && gotIh > 0),
    `control good: vinculado ${good.bound_at_end}, llegaron ${gotGood}/${lh.forged.heartbeat}; scope_heartbeat ${sh?.error} ${ms(sh, sh?.last_activity_msec)} ms, llegaron ${gotSh}; intruder_heartbeat ${ih?.error} ${ms(ih, ih?.last_activity_msec)} ms, llegaron ${gotIh}/${li.forged.heartbeat}`);
  const quietNames = ['quiet', 'quiet_idle', 'quiet_base', 'quiet_base_2'];
  const qBad = [];
  const qNotes = quietNames.map((q) => {
    const okq = H[q].closes.length === 0 && C[q].closes.length === 0 && H[q].bound_at_end && C[q].bound_at_end && H[q].act_max_gap < 1000 && C[q].act_max_gap < 1000;
    if (!okq) { qBad.push(q); h1.closes.push(`${tag}/${q}: host ${JSON.stringify(H[q].closes.map((x) => x.error))} cliente ${JSON.stringify(C[q].closes.map((x) => x.error))}`); }
    return `${q}(${H[q].kind}) huecos ${H[q].act_max_gap}/${C[q].act_max_gap} ms, llegadas ${JSON.stringify(H[q].heartbeats_in ?? '-')}/${JSON.stringify(C[q].heartbeats_in ?? '-')}${okq ? '' : ' MAL'}`;
  });
  add(`${tag}:L3`, pass(qBad.length === 0), qNotes.join('; '));
  // L4: poder de la corrida
  const unrel = ['quiet_unrel', 'quiet_unrel_2'];
  const hostIn = (q) => (H[q].heartbeats_in ? Object.values(H[q].heartbeats_in).reduce((a, b) => a + b, 0) : 0);
  const cliIn = (q) => (C[q].heartbeats_in ? Object.values(C[q].heartbeats_in).reduce((a, b) => a + b, 0) : 0);
  const stressed = unrel.some((q) => hostIn(q) <= 6 || cliIn(q) <= 6 || H[q].closes.some((x) => x.error === 'peer_idle_timeout') || C[q].closes.some((x) => x.error === 'peer_idle_timeout'));
  if (stressed) h1.stressed++;
  const thr = (res) => { const by = {}; for (const [, id, t] of res.throttle) { (by[id] ||= []).push(t); } return Object.entries(by).map(([id, ts]) => `${id === '1' ? 'al host' : 'a ' + id}: min ${Math.min(...ts)}, <=1 en ${ts.filter((t) => t <= 1).length}/${ts.length}`).join(', '); };
  add(`${tag}:L4`, stressed ? 'INFO' : 'INFO', `estres ${stressed ? 'SI' : 'no'}; control no confiable: llegadas host ${unrel.map(hostIn).join('/')} cliente ${unrel.map(cliIn).join('/')}, cierres ${JSON.stringify(unrel.map((q) => [H[q].closes.map((x) => x.error), C[q].closes.map((x) => x.error)]))}; throttle host [${thr(lh)}] cliente [${thr(lc)}] intruso [${thr(li)}]`);
}
add('L5_H1', h1.closes.length ? 'FAIL' : (h1.stressed > 0 ? 'PASS' : 'INSUFICIENTE'),
  `${h1.runs} corridas, ${h1.stressed} con estres; cierres o huecos >= 1000 ms en carriles con canal nuevo: ${h1.closes.join('; ') || 'ninguno'}`);

const width = Math.max(...rows.map((r) => r.id.length));
for (const r of rows) console.log(`${r.id.padEnd(width)}  ${r.verdict.padEnd(12)} ${r.note}`);
const count = (v) => rows.filter((r) => r.verdict === v).length;
console.log(`\nPASS ${count('PASS')} / FAIL ${count('FAIL')} / INSUFICIENTE ${count('INSUFICIENTE')} / HALLAZGO ${count('HALLAZGO')} / INFO ${count('INFO')}`);
fs.writeFileSync(path.join(dir, 'cv15_report.json'), JSON.stringify(rows, null, 1));
