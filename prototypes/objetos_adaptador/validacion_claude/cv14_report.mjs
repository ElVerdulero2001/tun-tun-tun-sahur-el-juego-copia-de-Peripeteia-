// Validacion independiente (Claude), entrega 14: califica una carpeta de run_claude_e14.ps1
// segun docs/net/validacion_objetos/criterios_entrega_14.md. Uso: node cv14_report.mjs <carpeta>
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

// ---- procesos
const procs = runner ? runner.records.filter((r) => r.name !== 'import') : [];
const bad = procs.filter((r) => r.timed_out || r.exit_code !== 0 || r.error_lines.length || !r.result);
add('runner_processes', pass(procs.length > 0 && bad.length === 0),
  `${procs.length} procesos; con problema: ${bad.map((r) => `${r.name}(exit ${r.exit_code}${r.timed_out ? ' vencido' : ''}, ${r.error_lines.length} lineas, result ${r.result})`).join('; ') || 'ninguno'}; max ${Math.max(0, ...procs.map((r) => r.ms))} ms; Godot abiertos al final ${runner?.godot_left}`);

// ---- local
const byPrefix = (res, prefix) => res.checks.filter((c) => c.id.startsWith(prefix));
const group = (res, prefix, id, extra = '') => {
  const cs = byPrefix(res, prefix);
  if (!cs.length) { add(id, 'INSUFICIENTE', 'sin comprobaciones'); return; }
  const failed = cs.filter((c) => !c.passed).map((c) => c.id);
  add(id, failed.length ? 'FAIL' : 'PASS', `${cs.length - failed.length}/${cs.length}${failed.length ? ' fallan: ' + failed.slice(0, 8).join(', ') : ''}${extra ? ' | ' + extra : ''}`);
};
const actions = read('actions.result.json');
if (actions) {
  const i = actions.info;
  group(actions, 'capture_', 'A_setup_capture');
  group(actions, 'A1_', 'A1', `encoladas ${i.a1?.queued}, efectos ${i.a1?.effects_total}, id max ${i.a1?.max_id}`);
  group(actions, 'A2_', 'A2', `max todas [activas, conocidas, efectos, confirmadas, comandos] = ${JSON.stringify(i.a2?.all)}; 200-400 ${JSON.stringify(i.a2?.w1)}; 400-700 ${JSON.stringify(i.a2?.w2)}`);
  group(actions, 'A3_', 'A3', (i.a3 || []).map((r) => `d=${r.delay}:${r.accepted ? 'acept' : 'rech'}/${r.confirmed ? 'conf' : 'sin'}`).join(' '));
  const a3h = (i.a3 || []).filter((r) => r.delay >= 121);
  add('A3h', a3h.length && a3h.every((r) => r.accepted && !r.confirmed) ? 'HALLAZGO' : 'INFO',
    `acciones con primer ACK a d>=121 aceptado sin confirmacion: ${a3h.filter((r) => r.accepted && !r.confirmed).length}/${a3h.length}; ninguna senal de vencimiento en la API`);
  group(actions, 'A4_', 'A4', (i.a4 || []).map((r) => `${r.at}:${r.confirms}`).join(' '));
  group(actions, 'A5_', 'A5', (i.a5 || []).filter((r) => !r.case.startsWith('A5i')).map((r) => `${r.case}=${r.accepted ? 'ACEPTADO' : r.error}`).join('; '));
  const a5i = (i.a5 || []).filter((r) => r.case.startsWith('A5i'));
  add('A5i', 'INFO', a5i.map((r) => `${r.case}: ${r.accepted ? 'aceptado en silencio' : 'rechazado ' + r.error}, callback ${r.confirmed}`).join('; '));
  group(actions, 'A5i_', 'A5i_no_callback');
  group(actions, 'A6_', 'A6', (i.a6 || []).map((r) => `${r.case}=${r.status.status}${r.status.reason ? ':' + r.status.reason : ''}`).join('; '));
  group(actions, 'A7_', 'A7', JSON.stringify(i.a7));
  group(actions, 'A8_', 'A8', JSON.stringify(i.a8));
  group(actions, 'A9_', 'A9', `pedidos en suspension ${JSON.stringify(i.a9_status)}; ${JSON.stringify(i.a9_stats)}`);
  group(actions, 'A9b_', 'A9b', JSON.stringify(i.a9b));
  group(actions, 'A9c_', 'A9c');
  group(actions, 'A10_', 'A10', JSON.stringify(i.a10));
  add('A_status', pass(actions.status === 'PASSED'), `${actions.failures} fallas, ${actions.checks.length} comprobaciones, ${i.ms} ms, error adaptador '${actions.adapter_error}'`);
} else add('A', 'INSUFICIENTE', 'sin resultado de actions');

const bridge = read('bridge.result.json');
if (bridge) {
  const i = bridge.info;
  group(bridge, 'P_', 'P_setup');
  for (const p of ['P1', 'P2', 'P3', 'P4', 'P5', 'P6', 'P7', 'P8', 'P9']) group(bridge, p + '_', p);
  add('P_applied', 'INFO', (i.applied || []).map((a) => `${a.tick}@${a.clock}(r${a.revision})`).join(' ') + ` | rechazos ${JSON.stringify(i.rejected)} | pausa ${JSON.stringify(i.p4_pending)} | exactitud mal ${JSON.stringify(i.exact_bad)}`);
  add('P_status', pass(bridge.status === 'PASSED'), `${bridge.failures} fallas, ${bridge.checks.length} comprobaciones`);
} else add('P', 'INSUFICIENTE', 'sin resultado de bridge');

// ---- lanes
const lh = read('lanes_host.result.json'), lc = read('lanes_client.result.json'), li = read('lanes_intruder.result.json');
if (lh && lc && li) {
  const H = lh.lanes, C = lc.lanes;
  const one = (r) => r.closes.length === 1 ? r.closes[0] : null;
  const ms = (c, from) => (c ? c.msec - from : null);
  add('L_setup', pass(Object.values(H).every((r) => r.start_ok) && Object.values(C).every((r) => r.start_ok) && lh.server_relay === true),
    `ids cliente ${lh.client_id}, intruso ${lh.intruder_id}; relay ${lh.server_relay}; falsos: host ${JSON.stringify(lh.forged)}, cliente ${JSON.stringify(lc.forged)}, intruso ${JSON.stringify(li.forged)}`);
  { const c = one(C.notice), h = one(H.notice);
    add('L_notice', pass(c && c.error === 'peer_closed' && c.unix - H.notice.stop_unix < 0.5 && h && H.notice.restart_ok === false && C.notice.restart_ok === false),
      `cliente ${c?.error} a ${f3(c ? c.unix - H.notice.stop_unix : null)} s del stop; reinicio host ${H.notice.restart_ok}, cliente ${C.notice.restart_ok}`); }
  { const c = one(C.scope_close), h = one(H.scope_close);
    add('L_scope_close', pass(c && h && c.rel >= 4.95 && h.rel >= 4.95 && c.error === 'peer_closed' && c.unix - H.scope_close.stop_unix < 0.5),
      `cierres cliente ${JSON.stringify(C.scope_close.closes.map((x) => [x.rel, x.error]))}, host ${JSON.stringify(H.scope_close.closes.map((x) => [x.rel, x.error]))}`); }
  const good = C.good_heartbeat;
  const goodOk = good.closes.length === 0 && good.bound_at_end;
  add('L_good_heartbeat', pass(goodOk), `cliente vinculado al final ${good.bound_at_end}, cierres ${JSON.stringify(good.closes.map((x) => [x.rel, x.error]))}, silencio desde ${f3(H.good_heartbeat.silence_unix - lh.t0)} s`);
  { const c = one(C.scope_heartbeat);
    const ok = c && c.error === 'peer_idle_timeout' && c.last_activity_unix <= H.scope_heartbeat.silence_unix + 0.25 && ms(c, c.last_activity_msec) >= 5000 && ms(c, c.last_activity_msec) <= 5150;
    add('L_scope_heartbeat', ok ? 'PASS' : (goodOk ? 'FAIL' : 'INSUFICIENTE'),
      `cierre ${c?.error} a ${f3(c ? c.rel : null)} s; ultima actividad ${f3(c ? c.last_activity_unix - H.scope_heartbeat.silence_unix : null)} s despues del silencio; cierre-actividad ${ms(c, c?.last_activity_msec)} ms`); }
  { const h = one(H.intruder_close), c = one(C.intruder_close);
    add('L_intruder_close', pass(h && c && h.rel >= 4.95 && c.rel >= 4.95 && h.error === 'peer_closed' && h.unix - C.intruder_close.stop_unix < 0.5),
      `host ${JSON.stringify(H.intruder_close.closes.map((x) => [x.rel, x.error]))}, cliente ${JSON.stringify(C.intruder_close.closes.map((x) => [x.rel, x.error]))}`); }
  { const h = one(H.intruder_heartbeat);
    add('L_intruder_heartbeat', pass(h && h.error === 'peer_idle_timeout' && h.last_activity_unix <= C.intruder_heartbeat.silence_unix + 0.25 && ms(h, h.last_activity_msec) >= 5000 && ms(h, h.last_activity_msec) <= 5150),
      `host ${h?.error} a ${f3(h?.rel)} s; ultima actividad ${f3(h ? h.last_activity_unix - C.intruder_heartbeat.silence_unix : null)} s despues del silencio del cliente; cierre-actividad ${ms(h, h?.last_activity_msec)} ms`); }
  { const h = one(H.startup), c = one(C.startup);
    const okH = h && h.error === 'peer_idle_timeout' && ms(h, H.startup.start_msec) >= 5000 && ms(h, H.startup.start_msec) <= 5150;
    const okC = c && c.error === 'peer_idle_timeout' && ms(c, C.startup.start_msec) >= 5000 && ms(c, C.startup.start_msec) <= 5150;
    add('L_startup', pass(okH && okC), `host ${h?.error} ${ms(h, H.startup.start_msec)} ms; cliente ${c?.error} ${ms(c, C.startup.start_msec)} ms`); }
  { const h = one(H.send_timeout), c = one(C.send_timeout);
    const d = h && H.send_timeout.tx_started_msec >= 0 ? h.msec - H.send_timeout.tx_started_msec : null;
    let v = 'FAIL';
    if (h && h.error === 'send_timeout' && d >= 5000 && d <= 5150 && c && c.error === 'peer_closed') v = 'PASS';
    else if (h && h.error === 'peer_idle_timeout') v = 'INSUFICIENTE';
    add('L_send_timeout', v, `host ${h?.error} ${d} ms desde el inicio de la transferencia; cliente ${c?.error}; rechazos del cliente ${C.send_timeout.stats.rejected}`); }
  add('L_both_close', pass(H.both_close.closes.length === 1 && C.both_close.closes.length === 1), `host ${JSON.stringify(H.both_close.closes.map((x) => x.error))}, cliente ${JSON.stringify(C.both_close.closes.map((x) => x.error))}`);
  for (const q of ['quiet', 'quiet_idle']) {
    add('L_' + q, pass(H[q].closes.length === 0 && C[q].closes.length === 0 && H[q].bound_at_end && C[q].bound_at_end),
      `cierres host ${JSON.stringify(H[q].closes.map((x) => [x.rel, x.error]))} cliente ${JSON.stringify(C[q].closes.map((x) => [x.rel, x.error]))}; hueco max host ${H[q].act_max_gap} ms (${H[q].act_updates} act.), cliente ${C[q].act_max_gap} ms (${C[q].act_updates})`);
  }
  const thr = (res) => { const by = {}; for (const [, id, t] of res.throttle) { (by[id] ||= []).push(t); } return Object.entries(by).map(([id, ts]) => `${id}: min ${Math.min(...ts)}, <32 ${ts.filter((t) => t < 32).length}/${ts.length}, <=1 ${ts.filter((t) => t <= 1).length}`).join('; '); };
  add('L_throttle', 'INFO', `host [${thr(lh)}] cliente [${thr(lc)}] intruso [${thr(li)}]`);
} else add('L', 'INSUFICIENTE', 'faltan resultados de lanes');

// ---- red completa
const tags = [...new Set(procs.map((r) => r.name).filter((n) => /_(host|client)$/.test(n) && !n.startsWith('lanes')).map((n) => n.replace(/_(host|client)$/, '')))];
for (const tag of tags) {
  const h = read(tag + '_host.result.json'), c = read(tag + '_client.result.json');
  if (!h || !c) { add('N_' + tag, 'INSUFICIENTE', 'falta un resultado'); continue; }
  const failed = [...h.checks, ...c.checks].filter((x) => !x.passed).map((x) => x.id);
  const mode = h.mode;
  let cross = true, note = '';
  const hc = h.close[0], cc = c.close[0];
  if (mode === 'close_host') { cross = cc && cc.unix - h.stop_unix < 0.5; note = `cliente ${cc?.error} a ${f3(cc ? cc.unix - h.stop_unix : null)} s; transferencia en vuelo al cerrar ${h.stop_tx_in_flight}`; }
  if (mode === 'close_client') { cross = hc && hc.unix - c.stop_unix < 0.5 && hc.error === 'peer_closed'; note = `host ${hc?.error} a ${f3(hc ? hc.unix - c.stop_unix : null)} s`; }
  if (mode === 'close_both') { note = `host ${hc?.error}, cliente ${cc?.error}`; }
  if (mode === 'lease_silent') { cross = cc && cc.last_activity_unix <= h.stop_unix + 0.25; note = `cliente ${cc?.error}, cierre-actividad ${cc ? cc.msec - cc.last_activity_msec : null} ms, ultima actividad ${f3(cc ? cc.last_activity_unix - h.stop_unix : null)} s despues del silencio`; }
  if (mode === 'quiet') {
    const tmin = (r) => (r.throttle.length ? Math.min(...r.throttle.map((t) => t[1])) : null);
    const low = (r) => r.throttle.filter((t) => t[1] <= 1).length;
    note = `cierres host ${JSON.stringify(h.close.map((x) => [x.error, Math.round(x.msec)]))} cliente ${JSON.stringify(c.close.map((x) => [x.error, Math.round(x.msec)]))}; hueco max host ${h.act_max_gap} ms (${h.act_updates}), cliente ${c.act_max_gap} ms (${c.act_updates}); throttle min host->cliente ${tmin(h)} (<=1 en ${low(h)}/${h.throttle.length}), cliente->host ${tmin(c)} (<=1 en ${low(c)}/${c.throttle.length})`;
  }
  if (mode === 'future') note = `aplicados ${c.applied.length} (antes de 240: ${c.applied.filter((a) => a.tick < 240).length}), en pausa ${c.applied_in_pause}, futuros ${c.future_bad}, ocupacion max ${c.occupancy_max}, desplazados ${c.displaced.length}, espera max ${c.max_wait} ticks, cuadros de pausa ${c.paused_frames}`;
  add('N_' + tag, failed.length || !cross ? 'FAIL' : 'PASS', `${failed.length ? 'fallan: ' + failed.join(', ') + ' | ' : ''}${note}; ms host ${h.process_ms} cliente ${c.process_ms}`);
}

const width = Math.max(...rows.map((r) => r.id.length));
for (const r of rows) console.log(`${r.id.padEnd(width)}  ${r.verdict.padEnd(12)} ${r.note}`);
const count = (v) => rows.filter((r) => r.verdict === v).length;
console.log(`\nPASS ${count('PASS')} / FAIL ${count('FAIL')} / INSUFICIENTE ${count('INSUFICIENTE')} / HALLAZGO ${count('HALLAZGO')} / INFO ${count('INFO')}`);
fs.writeFileSync(path.join(dir, 'cv14_report.json'), JSON.stringify(rows, null, 1));
