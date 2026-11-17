// Validación independiente (Claude), entrega 8: comparaciones de una corrida de run_native_claude.ps1.
// Uso: node cv_native_compare.mjs <carpeta godot_...>
// Criterios: docs/net/validacion_objetos/criterios_entrega_8.md §4 y §5.
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
const EPS = 0.00001, SENS = 0.001, FINAL = 140;
const read = (f) => { try { return JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8').replace(/^﻿/, '')); } catch { return null; } };
const runner = read('runner.json');
const recs = runner?.records ?? [];
const rec = (n) => recs.find((r) => r.name === n);
const checks = [];
const add = (id, verdict, metric, tol) => checks.push({ id, verdict, metric, tol });
const check = (id, ok, metric, tol) => add(id, ok ? 'PASS' : 'FAIL', metric, tol);
const KNOWN = /^ERROR: Failed to read the root certificate store\.$/;

// G0: procesos.
for (const r of recs) {
  const script = (r.error_lines ?? []).filter((l) => /^SCRIPT ERROR/.test(l));
  const other = (r.error_lines ?? []).filter((l) => !/^SCRIPT ERROR/.test(l) && !KNOWN.test(l));
  check(`G0_${r.name}`, !r.timed_out && r.ms <= 8500 && r.result && script.length === 0,
    `exit ${r.exit_code}, ${r.ms} ms${r.timed_out ? ' VENCIDO' : ''}, resultado=${r.result}, script_errors=${script.length}, otras_lineas=${JSON.stringify(other.slice(0, 4))}`,
    'sin vencer 8 s, con resultado, sin SCRIPT ERROR');
}
add('G0_procesos_propios_abiertos', runner?.own_processes_left === 0 ? 'PASS' : 'FAIL', runner?.own_processes_left, '0');

// H: checks del proceso binding y H2 contra los controles.
const b = read('binding.result.json'), c1 = read('control1.result.json'), c2 = read('control2.result.json');
if (b) for (const c of b.checks) add(c.id, c.verdict, typeof c.metric === 'string' ? c.metric : JSON.stringify(c.metric), c.tol);
if (b && c1 && c2) {
  const same = (x, y) => JSON.stringify(x.jolt_history) === JSON.stringify(y.jolt_history);
  const frames = b.jolt_history?.length;
  const moved = c1.jolt_history ? Math.abs(c1.jolt_history[0][1] - c1.jolt_history.at(-1)[1]) : 0;
  if (!same(c1, c2)) add('H2_jolt_intacto', 'NOEVAL', 'los dos controles difieren entre sí', 'controles iguales');
  else check('H2_jolt_intacto', same(b, c1) && frames === 90 && moved > 0.1, `cuadros=${frames} caida_del_control=${moved.toFixed(4)} m igual_por_bits=${same(b, c1)}`, 'igual a los controles, 90 cuadros, en movimiento');
}

// X: intercambio por archivo.
const ex = read('export.result.json'), im = read('import.result.json');
if (ex && im) {
  check('X1_archivo_integro', ex.facts.artifact_sha256 === im.facts.received_sha256 && ex.facts.artifact_bytes === im.facts.received_bytes,
    `${im.facts.received_bytes} bytes, ${im.facts.received_sha256}`, 'mismo SHA-256 que el exportado');
  for (const c of [...ex.checks, ...im.checks]) add(c.id, c.verdict, typeof c.metric === 'string' ? c.metric : JSON.stringify(c.metric), c.tol);
  add('X_hechos', 'INFO', JSON.stringify({ export: ex.facts, import: im.facts }), 'se registra');
}

// L: suelta tardía.
const pos = (n) => n.slice(0, 3), vel = (n) => n.slice(12, 15);
const dist = (a, b) => Math.sqrt(a.reduce((s, x, i) => s + (x - b[i]) ** 2, 0));
const norm = (a) => Math.sqrt(a.reduce((s, x) => s + x * x, 0));
const maxAbs = (a, b) => a.reduce((m, x, i) => Math.max(m, Math.abs(x - b[i])), 0);
for (const tag of ['late_codex', 'late_push']) {
  const ht = read(`${tag}_host.trace.json`), ct = read(`${tag}_client.trace.json`);
  const hr = read(`${tag}_host.result.json`), cr = read(`${tag}_client.result.json`);
  if (!rec(`${tag}_host`)) continue;
  const L = (id) => `L${id}_${tag.slice(5)}`;
  check(L('1_procesos_y_chequeos_de_codex'), rec(`${tag}_host`).exit_code === 0 && rec(`${tag}_client`)?.exit_code === 0 && hr?.status === 'PASSED' && cr?.status === 'PASSED',
    `host exit ${rec(`${tag}_host`).exit_code} ${hr?.status} fallas ${hr?.failures}; invitado exit ${rec(`${tag}_client`)?.exit_code} ${cr?.status} fallas ${cr?.failures}` +
    `${[...(hr?.checks ?? []), ...(cr?.checks ?? [])].filter((c) => !c.passed).map((c) => ' ' + c.name).join('')}`, 'exit 0 y PASSED en los dos');
  if (!ht || !ct) { add(L('trazas'), 'NOEVAL', `host=${!!ht} invitado=${!!ct}`, 'trazas escritas'); continue; }
  const T = ht.codex_vars.release_tick, P = ct.codex_facts.predicted_present_at_correction;
  const hs = new Map(ht.states.filter((s) => s.kind === 'step').map((s) => [s.tick, s]));
  const c2 = ct.states.filter((s) => s.branch === 2 && (s.kind === 'step' || s.kind === 'post_restore'));
  const cs = new Map(c2.map((s) => [s.tick, s]));
  const pre = ct.states.find((s) => s.kind === 'pre_restore' && s.branch === 1);
  // L2
  const bad = [];
  let compared = 0;
  for (let t = T; t <= FINAL; t++) {
    const h = hs.get(t), c = cs.get(t);
    compared++;
    if (!h || !c || h.sha !== c.sha) bad.push(t);
  }
  check(L('2_mismo_tick'), T > 46 && bad.length === 0 && compared === FINAL - T + 1, `T=${T} P=${P} ticks_comparados=${compared} distintos=${JSON.stringify(bad.slice(0, 10))}`, 'SHA igual en cada tick T..140');
  // L3
  const hRel = ht.ops.filter((o) => o.op === 'release_body' && o.ok);
  const hImp = ht.ops.filter((o) => o.op === 'apply_impulse');
  const ref = ht.reference ?? {};
  check(L('3_una_suelta_en_el_host'), hRel.length === 1 && hRel[0].uid === 2 && hImp.length === 0, `sueltas=${JSON.stringify(hRel)} impulsos=${hImp.length}`, '1 suelta, 0 impulsos');
  check(L('3_host_igual_a_mi_referencia'), ref.first_mismatch_tick === -1 && ref.ticks_compared === FINAL && ref.T === T, JSON.stringify(ref), '140 ticks iguales, suelta única en T');
  check(L('3_control_suelta_en_46'), ref.neg_release_46_diff_140 > SENS, ref.neg_release_46_diff_140, '> 1e-3');
  if (ref.neg_double_impulse_diff_140 === undefined) add(L('3_control_doble_impulso'), 'NOEVAL', `D=${ref.D}`, 'duplicado antes de 140');
  else check(L('3_control_doble_impulso'), ref.neg_double_impulse_diff_140 > SENS, `D=${ref.D} diferencia=${ref.neg_double_impulse_diff_140}`, '> 1e-3');
  // L4
  check(L('4_duplicado'), ht.codex_vars.duplicate_requests >= 1 && hRel.length === 1 && ct.restore_ok_count === 2 && ct.codex_vars.duplicate_confirmations >= 1,
    `pedidos_repetidos=${ht.codex_vars.duplicate_requests} sueltas_host=${hRel.length} restauraciones_invitado=${ct.restore_ok_count} confirmaciones_repetidas=${ct.codex_vars.duplicate_confirmations}`,
    '≥1 repetido, 1 suelta, 2 restauraciones');
  // L5 / L6: vecino B (uid 3) y C (uid 4).
  const replay = c2.filter((s) => s.kind === 'step' && s.tick > T && s.tick <= P);
  const hP = hs.get(P);
  const bPre = pre && hP ? dist(pos(pre.b['3'].n), pos(hP.b['3'].n)) : null;
  let bAfter = 0;
  for (let t = T; t <= FINAL; t++) { const h = hs.get(t), c = cs.get(t); if (h && c) bAfter = Math.max(bAfter, maxAbs(h.b['3'].n, c.b['3'].n)); }
  const bReplay = replay.map((s) => ({ tick: s.tick, sleeping: s.b['3'].sleeping, speed: +norm(vel(s.b['3'].n)).toFixed(4), contacts: s.b['3'].contacts }));
  const exercised = bReplay.some((x) => !x.sleeping && x.speed >= 0.05) && bReplay.some((x) => x.contacts.includes(2));
  if (tag === 'late_push') {
    check(L('5a_B_afectado_antes_de_corregir'), bPre !== null && bPre > SENS, `separacion_B_en_P=${bPre}`, '> 1e-3 m');
    check(L('5b_B_igual_despues'), bAfter <= EPS, `max_dif_B_T..140=${bAfter}`, '≤ EPS');
    if (exercised) check(L('5c_B_vivo_en_la_ventana_repetida'), true, JSON.stringify(bReplay), 'despierto, ≥0,05 m/s, contacto con A');
    else add(L('5c_B_vivo_en_la_ventana_repetida'), 'NOEVAL', JSON.stringify(bReplay), 'no ejercitado');
    const cHeld = [...hs.values()].every((s) => s.b['4'].held);
    const neg = ct.negative_c ?? {};
    check(L('5d_C_agarrado_y_entradas_repetidas'), cHeld && neg.restored === true && neg.diff_without_C_goals > SENS, `C_agarrado_1..140=${cHeld} control_sin_objetivos=${JSON.stringify(neg)}`, 'agarrado y > 1e-3');
  } else {
    add(L('6_vecino_en_codex'), 'INFO', `separacion_B_en_P=${bPre} max_dif_B_T..140=${bAfter} ventana=${JSON.stringify(bReplay)}`, 'se registra');
  }
  // L7
  const jumps = {};
  const post = cs.get(P);
  if (pre && post) for (const uid of Object.keys(pre.b)) jumps[uid] = +dist(pos(pre.b[uid].n), pos(post.b[uid].n)).toFixed(6);
  add(L('7_ticks_y_saltos'), 'INFO', JSON.stringify({ T, P, replayed: ct.codex_facts.replayed_steps, host_events: ht.events, client_events: ct.events,
    salto_en_la_correccion_m: jumps, goal_calls: { host: ht.goal_calls, client: ct.goal_calls } }), 'se registra');
}
const summary = Object.fromEntries(['PASS', 'FAIL', 'INFO', 'NOEVAL'].map((v) => [v, checks.filter((c) => c.verdict === v).length]));
fs.writeFileSync(path.join(dir, 'compare.json'), JSON.stringify({ dir, checks, summary }, null, 1));
for (const c of checks) console.log(`${c.verdict.padEnd(6)} ${c.id}: ${c.metric}  [${c.tol}]`);
console.log(JSON.stringify(summary));
