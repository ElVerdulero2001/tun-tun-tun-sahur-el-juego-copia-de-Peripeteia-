// Validación independiente (Claude), entrega 5: comparaciones entre procesos de una
// corrida de run_rapier.ps1. Uso: node rv_compare.mjs <carpeta de la corrida>
// Criterios: docs/net/validacion_objetos/criterios_entrega_5.md, parte B.
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
const EPS = 0.00001;
const PINNED = '9700717c8ef83acd219e62edaeb3af503556273bc5afa2be4e363ebc8f243c7a';
const read = (f) => { try { return JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8').replace(/^﻿/, '')); } catch { return null; } };
const runner = read('runner.json');
const R = (n) => read(n + '.result.json');
const checks = [];
const check = (id, ok, metric, tol, note = '') => checks.push({ id, ok, metric, tol, note });
const stage = (n) => (runner?.stages ?? []).find((s) => s.stage === n);
const dist = (a, b, from, n) => Math.sqrt([...Array(n).keys()].reduce((s, i) => s + (a[from + i] - b[from + i]) ** 2, 0));
function cmp(a, b, names) {
  const e = { len_a: a?.length ?? null, len_b: b?.length ?? null, pos: 0, basis: 0, vel: 0, sleep_mismatch: 0, hits_mismatch: 0, first_bad_step: -1, exact: true };
  if (!a || !b) return { ...e, pos: Infinity };
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    let bad = false;
    for (const k of names) {
      const x = a[i][k], y = b[i][k];
      const dp = dist(x.p, y.p, 0, 3), db = Math.max(dist(x.b, y.b, 0, 3), dist(x.b, y.b, 3, 3), dist(x.b, y.b, 6, 3));
      const dv = Math.max(dist(x.lv, y.lv, 0, 3), dist(x.av, y.av, 0, 3));
      e.pos = Math.max(e.pos, dp); e.basis = Math.max(e.basis, db); e.vel = Math.max(e.vel, dv);
      if (dp || db || dv) e.exact = false;
      if (x.sl !== y.sl) { e.sleep_mismatch++; bad = true; }
      if (JSON.stringify(x.hits) !== JSON.stringify(y.hits)) { e.hits_mismatch++; bad = true; }
      if (dp > EPS || db > EPS || dv > EPS) bad = true;
    }
    if (bad && e.first_bad_step < 0) e.first_bad_step = i;
  }
  return e;
}
const within = (e) => e.len_a === e.len_b && e.pos <= EPS && e.basis <= EPS && e.vel <= EPS && e.sleep_mismatch === 0 && e.hits_mismatch === 0;

// E0/E1: procesos.
const st = runner?.stages ?? [];
check('E0_procesos', st.length > 0 && st.every((s) => s.exit_code === 0 && !s.timed_out && s.result_file && s.ms <= 8000 + 2000),
  st.map((s) => `${s.stage}: exit ${s.exit_code}, ${s.ms} ms${s.timed_out ? ' VENCIDO' : ''}${s.result_file ? '' : ', sin resultado'}`).join('; '),
  'exit 0, sin vencer 8 s, con resultado');
check('E1_sin_errores_de_script', st.every((s) => !(s.error_lines ?? []).some((l) => /^SCRIPT ERROR/.test(l))),
  st.filter((s) => (s.error_lines ?? []).some((l) => /^SCRIPT ERROR/.test(l))).map((s) => s.stage).join(', ') || 'ninguno', 'ningún SCRIPT ERROR (validez de los instrumentos)');
check('E2_errores_del_motor', null, Object.fromEntries(st.filter((s) => (s.error_lines ?? []).length).map((s) => [s.stage, s.error_lines.slice(0, 6)])), 'se registra');
check('E3_procesos_abiertos', runner?.godot_left_running === 0, runner?.godot_left_running, '0');

// R1: ensayo entregado.
check('R1a_sha_del_paquete', runner?.archive_sha256 === PINNED, `${runner?.archive_sha256} (${runner?.archive_bytes} bytes)`, 'igual al fijado');
const cx = ['codex_probe', 'codex_export', 'codex_import'].map((n) => ({ n, s: stage(n), r: R(n) }));
if (cx.every((x) => x.s)) {
  check('R1b_ensayo_entregado', cx.every((x) => x.s.exit_code === 0 && !x.s.timed_out && x.r?.status === 'PASSED' && x.r?.backend_class === 'RapierPhysicsServer3D'
    && (x.s.error_lines ?? []).length === 0),
    cx.map((x) => `${x.n}: exit ${x.s.exit_code}, ${x.r?.status}, ${x.r?.backend_class}, errores ${(x.s.error_lines ?? []).length}`).join('; '),
    'tres códigos 0, PASSED, Rapier, sin errores');
  const p = R('codex_probe'), imp = R('codex_import'), ex = R('codex_export');
  check('R1c_valores_entregados', null, { snapshot_bytes_probe: p?.snapshot_bytes, snapshot_bytes_export: ex?.snapshot_bytes,
    same_replay: p?.same_replay, late_replay: p?.late_replay, change_without_command: p?.change_without_command?.position,
    cross_process_replay: imp?.cross_process_replay, ids: { source: imp?.source_body_ids, destination: imp?.destination_body_ids } }, 'se registra');
}

// R3: transporte e integridad.
const ex = R('r3_export'), exn = R('r3_enet_export');
const imps = ['r3_import_noise_reverse', 'r3_import_swap', 'r3_import_second', 'r3_import_second_control'].map((n) => ({ n, r: R(n) })).filter((x) => x.r);
if (ex) {
  check('R3k_archivo_integro', imps.length > 0 && imps.every((x) => x.r.facts?.received?.sha256 === ex.facts?.artifact_sha256),
    imps.map((x) => `${x.n}: ${x.r.facts?.received?.bytes} bytes`).join('; ') + ` / exportado ${ex.facts?.artifact_bytes}`, 'mismo SHA-256 que el exportado');
}
const imn = R('r3_enet_import');
if (exn && imn) {
  check('R3l_enet_integro', imn.facts?.received?.sha256 === exn.facts?.artifact_sha256 && exn.facts?.enet?.acked === true,
    { bytes: imn.facts?.received?.bytes, receive_ms: imn.facts?.received?.receive_ms, enet: exn.facts?.enet }, 'mismo SHA-256 y entrega confirmada');
}
if (ex && exn) {
  check('R3m_dos_exportaciones_iguales', null, { file_export: ex.facts?.snapshot_sha256, enet_export: exn.facts?.snapshot_sha256,
    same: ex.facts?.snapshot_sha256 === exn.facts?.snapshot_sha256, ids_file: ex.facts?.ids, ids_enet: exn.facts?.ids }, 'se registra');
}
const sec = R('r3_import_second'), secc = R('r3_import_second_control');
if (sec && secc) {
  const e = cmp(sec.facts?.s_hist, secc.facts?.s_hist, ['S']);
  check('R3j_segundo_espacio_igual_al_control', within(e), e, '≤ EPS en toda la repetición');
}

// R4: segundo espacio y mismo espacio fuera de la raíz, contra el control.
const r4 = R('r4_spaces'), r4c = R('r4_spaces_control');
if (r4 && r4c) {
  const es = cmp(r4.s_hist, r4c.s_hist, ['S']);
  check('R4g_segundo_espacio_igual_al_control', within(es), es, '≤ EPS en los 120 pasos');
  const eo = cmp(r4.o_hist, r4c.o_hist, ['O']);
  check('R4h_mismo_espacio_contra_control', null, eo, 'se registra');
  check('R4i_contador', null, { rollback: r4.facts?.global_id, control: r4c.facts?.global_id, X: r4.facts?.X, Y: r4.facts?.Y, Z: r4.facts?.Z,
    Y_control: r4c.facts?.Y, Z_control: r4c.facts?.Z }, 'se registra');
}

// Resumen de los ensayos de un proceso.
const per = {};
for (const s of st) {
  const r = R(s.stage);
  if (r?.checks) per[s.stage] = r.checks.map((c) => `${c.ok === true ? 'PASS' : c.ok === false ? 'FAIL' : 'INFO'} ${c.id}`);
}
const out = { dir, checks, per_stage: per };
fs.writeFileSync(path.join(dir, 'compare.json'), JSON.stringify(out, null, 1));
for (const c of checks) console.log(`${c.ok === true ? 'PASS' : c.ok === false ? 'FAIL' : 'INFO'} ${c.id}: ${typeof c.metric === 'string' ? c.metric : JSON.stringify(c.metric)}  [${c.tol}]`);
for (const [k, v] of Object.entries(per)) console.log(`  ${k}: ${v.join(', ')}`);
