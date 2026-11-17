// Validacion independiente (Claude), entrega 16: califica una carpeta de run_claude_e16.ps1 segun
// docs/net/validacion_objetos/criterios_entrega_16.md. Uso: node cv16_report.mjs <carpeta>
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
if (!dir) { console.error('falta la carpeta'); process.exit(2); }
const read = (f) => { const p = path.join(dir, f); return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, 'utf8').replace(/^﻿/, '')) : null; };
const runner = read('runner.json');
const rows = [];
const add = (id, verdict, note = '') => rows.push({ id, verdict, note });
const pass = (b) => (b ? 'PASS' : 'FAIL');

const EXPECTED = [/Failed to read the root certificate store/];
const procs = runner ? runner.records.filter((r) => r.name !== 'import') : [];
const other = (r) => r.error_lines.filter((l) => !EXPECTED.some((e) => e.test(l)) && !/^\s+at:/.test(l));
const bad = procs.filter((r) => r.timed_out || r.exit_code !== 0 || other(r).length || !r.result);
add('runner_processes', pass(procs.length > 0 && bad.length === 0),
  `${procs.length} procesos; con problema: ${bad.map((r) => `${r.name}(exit ${r.exit_code}${r.timed_out ? ' vencido' : ''}, lineas ${other(r).length}: ${other(r).slice(0, 2).join(' | ')})`).join('; ') || 'ninguno'}; max ${Math.max(0, ...procs.map((r) => r.ms))} ms; Godot abiertos ${runner?.godot_left}`);

const group = (res, prefix, id, extra = '') => {
  const cs = res.checks.filter((c) => c.id.startsWith(prefix));
  if (!cs.length) { add(id, 'INSUFICIENTE', 'sin comprobaciones'); return; }
  const failed = cs.filter((c) => !c.passed).map((c) => c.id);
  add(id, failed.length ? 'FAIL' : 'PASS', `${cs.length - failed.length}/${cs.length}${failed.length ? ' fallan: ' + failed.slice(0, 8).join(', ') : ''}${extra ? ' | ' + extra : ''}`);
};

const j = read('journal.result.json');
if (j) {
  group(j, 'setup_', 'J_setup');
  group(j, 'G_', 'J_global', `${JSON.stringify(j.info.counts)}; estados ${JSON.stringify(j.info.statuses)}`);
  for (const p of ['J1_', 'J2_', 'J3_', 'J4_', 'J5_', 'J6_', 'J7_', 'J8_', 'J9_', 'J10_', 'J11_', 'J12_', 'J13_', 'J14_', 'J15_', 'J16_', 'J17_', 'J18_', 'J19_']) group(j, p, p.slice(0, -1));
  add('J_info', 'INFO', `memoria ${JSON.stringify(j.info.mem)}; registros tras programar 120 futuros ${j.rows.j15_records_after_scheduling}; bloqueo por la de +120: ${j.info.blocked.action_order}/${j.info.blocked.tries} pedidos dieron action_order (otros ${JSON.stringify(j.info.blocked.other.slice(0, 3))}); J17 ${JSON.stringify(j.rows.j17)}; J18 ${JSON.stringify(j.rows.j18)}; ${j.info.ms} ms`);
  add('J_status', pass(j.status === 'PASSED'), `${j.failures} fallas, ${j.checks.length} comprobaciones`);
} else add('J', 'INSUFICIENTE', 'sin resultado de journal');

for (const m of ['journal_close', 'journal_inflight', 'journal_capture']) {
  const r = read(m + '.result.json');
  if (!r) { add(m, 'INSUFICIENTE', 'sin resultado'); continue; }
  const failed = r.checks.filter((c) => !c.passed).map((c) => c.id);
  let note = `${r.checks.length - failed.length}/${r.checks.length}${failed.length ? ' fallan: ' + failed.join(', ') : ''}; estados ${JSON.stringify(r.info.statuses)}`;
  if (m === 'journal_inflight') note += `; INFO: ${JSON.stringify(r.rows.inflight)}`;
  if (m === 'journal_capture') note += `; motivos ${JSON.stringify(r.rows.capture_reasons)}; mundo ${r.native_tick}`;
  if (m === 'journal_close') note += `; agarrada antes ${r.rows.held_before_stop}`;
  add(m, pass(r.status === 'PASSED'), note);
}

// ---- red
const tags = [...new Set(procs.map((r) => r.name).filter((n) => /^net16/.test(n)).map((n) => n.replace(/_(host|client)$/, '')))];
const allCmp = [];
let releaseQualified = 0;
for (const tag of tags) {
  const h = read(tag + '_host.result.json'), c = read(tag + '_client.result.json');
  const hx = read(tag + '_host.cv16.json'), cx = read(tag + '_client.cv16.json');
  if (!h || !c || !hx || !cx) { add(tag, 'INSUFICIENTE', 'faltan resultados'); continue; }
  const log = (id) => hx.request_log.filter((r) => r.id === id);
  const res = (id) => hx.resolved_log.filter((r) => r.id === id);
  const r1 = log(1), r2 = log(2), r3 = log(3);
  const res2 = res(2)[0] || {}, res3 = res(3)[0] || {};
  const dup2 = r2.find((r) => r.clock >= 55 && r.status === 'applied' && JSON.stringify(r.impulse) === JSON.stringify(r2[0]?.impulse));
  const conflict2 = r2.find((r) => r.reason === 'action_identity_conflict');
  const dup3 = r3.length >= 2 ? r3[r3.length - 1] : null;
  const n1 = r1.length >= 2 && r1[0].status === 'scheduled' && r1.slice(1).every((r) => ['scheduled', 'applied'].includes(r.status))
    && r2.length >= 4 && r2[0].status === 'scheduled' && !!dup2 && dup2.result.applied_tick === res2.applied_tick && !!conflict2
    && r3.length >= 2 && r3[0].status === 'scheduled' && res3.status === 'rejected' && res3.reason === 'invalid_hand_transition'
    && dup3 && dup3.status === 'rejected' && dup3.reason === 'invalid_hand_transition';
  add(`${tag}:N1`, pass(n1), `1: ${r1.map((r) => r.status).join(',')}; 2: ${r2.map((r) => `${r.status}${r.reason ? ':' + r.reason : ''}@${r.clock}`).join(',')}; 3: ${r3.map((r) => `${r.status}${r.reason ? ':' + r.reason : ''}@${r.clock}`).join(',')}; resultado 3 ${res3.status}:${res3.reason}`);
  const n2 = JSON.stringify(hx.host_effects) === JSON.stringify({ 1: 1, 2: 1 }) && JSON.stringify(cx.effects) === JSON.stringify([[1, 'grab'], [2, 'release']]);
  add(`${tag}:N2`, pass(n2), `host ${JSON.stringify(hx.host_effects)}; cliente ${JSON.stringify(cx.effects)}`);
  const conf2 = (cx.confirmations || []).find((x) => x[0] === 2) || [];
  const n3 = res2.status === 'applied' && res2.requested_tick === cx.release_requested && res2.applied_tick === res2.scheduled_tick
    && res2.applied_tick > res2.requested_tick && conf2[2] === res2.requested_tick && conf2[3] === res2.applied_tick;
  add(`${tag}:N3`, pass(n3), `host pedido ${res2.requested_tick}, programado ${res2.scheduled_tick}, aplicado ${res2.applied_tick}; cliente pidio ${cx.release_requested}, confirmacion ${JSON.stringify(conf2)}`);
  const ackHas3 = hx.published_acks.some(([, ids]) => ids.includes(3));
  add(`${tag}:N4`, pass(!ackHas3 && (cx.rejected_authorities || []).length === 0 && res(3).length === 1),
    `sobres con ACK del 3: ${ackHas3}; rechazos del cliente ${JSON.stringify(cx.rejected_authorities)}; sobres publicados ${hx.published_acks.length}`);
  const cmp = hx.comparisons;
  allCmp.push(...cmp.map((x) => ({ ...x, tag, release: res2.applied_tick })));
  const q = cmp.filter((x) => x.frames_equal);
  const diff = q.filter((x) => !x.hash_equal);
  releaseQualified += q.filter((x) => x.c >= res2.applied_tick).length;
  add(`${tag}:N5`, diff.length ? 'FAIL' : 'INFO', `${cmp.length} comparaciones, ${q.length} calificadas, ${diff.length} distintas; sin calificar distintas ${cmp.filter((x) => !x.frames_equal && !x.hash_equal).length}; calificadas tras la suelta ${q.filter((x) => x.c >= res2.applied_tick).length}; sin evaluar ${hx.cmp_unevaluated.length}; ejemplos ${JSON.stringify(q.slice(0, 4).map((x) => [x.c, x.t]))}`);
  const failed = [...h.checks, ...c.checks].filter((x) => !x.passed).map((x) => x.id);
  add(`${tag}:N6`, pass(h.status === 'PASSED' && c.status === 'PASSED'), failed.length ? 'fallan: ' + failed.join(', ') : `escena de Codex PASSED; comparacion intermedia ${c.midpoint_checkpoint}->${c.midpoint_tick}`);
}
const qAll = allCmp.filter((x) => x.frames_equal);
const dAll = qAll.filter((x) => !x.hash_equal);
add('N5_total', dAll.length ? 'FAIL' : (qAll.length >= 3 ? 'PASS' : 'INSUFICIENTE'), `${qAll.length} calificadas en ${tags.length} corridas, ${dAll.length} distintas`);
add('N5r', releaseQualified > 0 ? 'PASS' : 'INSUFICIENTE', `${releaseQualified} calificadas con checkpoint >= tick aplicado de la suelta`);

const width = Math.max(...rows.map((r) => r.id.length));
for (const r of rows) console.log(`${r.id.padEnd(width)}  ${r.verdict.padEnd(12)} ${r.note}`);
const count = (v) => rows.filter((r) => r.verdict === v).length;
console.log(`\nPASS ${count('PASS')} / FAIL ${count('FAIL')} / INSUFICIENTE ${count('INSUFICIENTE')} / HALLAZGO ${count('HALLAZGO')} / INFO ${count('INFO')}`);
fs.writeFileSync(path.join(dir, 'cv16_report.json'), JSON.stringify(rows, null, 1));
